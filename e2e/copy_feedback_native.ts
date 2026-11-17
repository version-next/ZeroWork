/** Shared clipboard acknowledgements outside AI, against production native views. */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdir,mkdtemp,open,writeFile,readFile,rm} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {inflateSync} from 'node:zlib';
import {readPasteboardText,writePasteboardText} from './private_pasteboard.ts';
const prefix=resolve(process.env.ZW_COPY_TEST_PREFIX??'zig-out');
const out=resolve(process.argv[2]??'/tmp/zw-copy-all-evidence');await mkdir(out,{recursive:true});
const theme=process.argv[3]??'dark';assert(theme==='dark'||theme==='light',`theme ${theme}`);
const h=await import(join(prefix,'share/zenit/harness/client.ts'));
const shown=(n:any)=>n?.rect?.w>0&&n.rect.h>0&&!n.hidden&&n.visible!==false;
const visible=(id:string)=>h.waitFor(async()=>(await h.query(id)).find(shown)??null,10000);
const click=async(id:string)=>{const n=await visible(id);assert((await h.clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok);};
const text=(n:any):string=>[n.text??'',...(n.children??[]).map(text)].join('');
// The previews copy through zenit to the run's private pasteboard (ZENIT_E2E_PASTEBOARD, inherited below), never the
// person's clipboard. A sentinel goes first so each assertion reads what that click copied.
const copiedBy=async(id:string)=>{const sentinel=`zw-e2e-sentinel-${Date.now()}`;await writePasteboardText(sentinel);await click(id);return await h.waitFor(async()=>{const value=await readPasteboardText();return value!==null&&value!==sentinel?value:null},5000).catch((error:any)=>{throw new Error(`${id}: the click did not put anything on the run's pasteboard (${error})`)})};
// Synthetic first transfer task of transfer-controls-preview (src/features/transfer/preview/transfer_controls_preview_runner.zig,
// `.local_path` / `.remote_path` literals): fixture data, not a path on this machine.
const fixtureRemote='/srv/releases/release.tar.gz',fixtureLocal='/private/var/folders/zz/000000000000000000000000000000/T/zerowork-native-transfer-fixture-long-directory/local/release.tar.gz';
const report:any={status:'running',checks:[]};
for(const scene of ['transfer','progress']){
 const iso=await mkdtemp('/private/tmp/zw-copy-feedback-');const rpc=join(iso,'rpc');await mkdir(rpc);process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
 const log=await open(join(out,scene+'.log'),'w');
 const app=spawn(join(prefix,'bin',scene==='transfer'?'transfer-controls-preview':'connection-progress-preview'),scene==='progress'?['direct',theme]:[`--theme=${theme}`],{env:{...process.env,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1'},stdio:['ignore',log.fd,log.fd]});
 const ended=new Promise<void>(done=>app.once('close',()=>done()));
 const cap=async(name:string)=>{assert((await h.screenshot(join(out,name+'.png'))).ok);await writeFile(join(out,name+'.json'),JSON.stringify(await h.tree(),null,2));};
 try{
  await h.waitForServerReady();await h.resizeWindow(1440,900);
  if(scene==='transfer'){
   // Task details open on a click on the file name (a Popover that stays open; hovering no longer opens them), the
   // contract transfer_controls_native.ts asserts: transfer_manager_view.zig test_id transfer.task.detail_popup.
   // Rows settle after the window resize (two identical consecutive samples), then the click lands on the name it measured.
   const flat=(n:any):any[]=>[n,...(n.children??[]).flatMap(flat)];let lastRows='';
   const row=await h.waitFor(async()=>{const rows=(await h.query('transfer.task')).filter(shown),now=JSON.stringify(rows.map((r:any)=>r.rect)),same=rows.length>0&&now===lastRows;lastRows=now;return same?rows[0]:null},10000);
   const name=flat(row).find((n:any)=>n.test_id==='transfer.task.name'&&shown(n));assert(name,'first task name');
   assert((await h.clickAt(name.rect.x+20,name.rect.y+name.rect.h/2)).ok);await visible('transfer.task.detail_popup');
   assert((await h.query('transfer.manager')).some(shown),'a click on a task name inside the transfer panel keeps the panel open (transfer_controls_native contract)');
   const local=await visible('transfer.detail.local');
   const park=async()=>h.mouseMove(local.rect.x+20,local.rect.y+local.rect.h/2);
   await park();await cap('00-transfer-idle');assert((await h.query('transfer.manager')).some(shown),'the transfer panel stays open under its details popover');
   assert.equal(await copiedBy('transfer.detail.copy_remote'),fixtureRemote);await park();await cap('01-transfer-copied');
   await h.sleep(1100);await click('transfer.detail.copy_remote');await park();await h.sleep(1100);await cap('02-transfer-renewed');
   await h.sleep(1200);await cap('03-transfer-reset');
   assert.equal(await copiedBy('transfer.detail.local'),fixtureLocal);await park();await cap('04-transfer-path-click');
   report.checks.push('Transfer copy buttons write exact remote/local paths; clicking a path acknowledges on its adjacent button; repeated clicks renew the two-second feedback');
  }else{
   await click('connection.progress.logs.toggle');
   await cap('05-logs-idle');await click('connection.progress.logs.copy');
   await h.waitFor(async()=>text(await visible('connection.progress.logs.copy')).includes('已复制')||null,3000);await cap('06-logs-copied');
   await h.sleep(1100);await click('connection.progress.logs.copy');await h.sleep(1100);
   assert(text(await visible('connection.progress.logs.copy')).includes('已复制'));await cap('07-logs-renewed');
   await h.waitFor(async()=>text(await visible('connection.progress.logs.copy')).includes('复制日志')||null,4000);await cap('08-logs-reset');
   report.checks.push('Connection log custom icon/text button acknowledges its callback, renews feedback on repeated clicks, and restores its original label after two seconds');
  }
 }catch(error){report.status='failed';report.error=String(error);process.exitCode=1;await cap(scene+'-failure').catch(()=>{});break;}
 finally{app.kill('SIGTERM');await Promise.race([ended,h.sleep(2000)]);if(app.exitCode===null&&app.signalCode===null){app.kill('SIGKILL');await ended;}await log.close();await rm(iso,{recursive:true,force:true});}
}
if(report.status!=='failed'){
 try{
  // Harness trees omit icon assets; inspect the exact button pixels (screenshot PNG decoded here, no third-party code).
  const paeth=(a:number,b:number,c:number)=>{const p=a+b-c,da=Math.abs(p-a),db=Math.abs(p-b),dc=Math.abs(p-c);return da<=db&&da<=dc?a:db<=dc?b:c};
  const decode=(bytes:Buffer)=>{
   assert(bytes.subarray(0,8).equals(Buffer.from('89504e470d0a1a0a','hex')),'screenshot must be PNG');
   const chunks:Buffer[]=[];let width=0,height=0,channels=0,offset=8,done=false;
   while(offset+12<=bytes.length){const length=bytes.readUInt32BE(offset),kind=bytes.toString('ascii',offset+4,offset+8),data=bytes.subarray(offset+8,offset+8+length);
    if(kind==='IHDR'){width=data.readUInt32BE(0);height=data.readUInt32BE(4);assert.equal(data[8],8);assert(data[9]===6||data[9]===2);channels=data[9]===6?4:3;assert.equal(data[12],0,'interlaced screenshot unsupported')}
    else if(kind==='IDAT')chunks.push(data);else if(kind==='IEND'){done=true;break}
    offset+=length+12}
   assert(done&&width&&channels&&chunks.length,'incomplete PNG');
   const rowBytes=width*channels,raw=inflateSync(Buffer.concat(chunks),{maxOutputLength:(rowBytes+1)*height}),pixels=Buffer.alloc(rowBytes*height);
   for(let y=0;y<height;y++){const filter=raw[y*(rowBytes+1)];assert(filter<=4,`unknown PNG filter ${filter}`);
    for(let x=0;x<rowBytes;x++){const i=y*rowBytes+x,a=x>=channels?pixels[i-channels]:0,b=y?pixels[i-rowBytes]:0,c=y&&x>=channels?pixels[i-rowBytes-channels]:0;
     pixels[i]=(raw[y*(rowBytes+1)+1+x]+(filter===0?0:filter===1?a:filter===2?b:filter===3?Math.floor((a+b)/2):paeth(a,b,c)))&255}}
   return {width,height,channels,pixels}};
  const find=(node:any,id:string):any=>{if(!node||typeof node!=='object')return null;if(node.test_id===id)return node;for(const child of node.children??[]){const f=find(child,id);if(f)return f}return null};
  // Success mark = the copy button's green check (success token): count clearly green pixels inside the button.
  const green=async(shot:string,id:string)=>{const node=find(JSON.parse(await readFile(join(out,shot+'.json'),'utf8')),id);assert(node,`${shot}: ${id}`);const image=decode(await readFile(join(out,shot+'.png'))),scale=image.width/1440;
   const [x0,y0,w,hgt]=['x','y','w','h'].map(k=>Math.round(node.rect[k]*scale));let count=0;
   for(let y=Math.max(0,y0);y<Math.min(image.height,y0+hgt);y++)for(let x=Math.max(0,x0);x<Math.min(image.width,x0+w);x++){const i=(y*image.width+x)*image.channels,r=image.pixels[i],g=image.pixels[i+1],b=image.pixels[i+2];if(g-r>40&&g-b>30)count++}
   return count};
  const remote='transfer.detail.copy_remote',local='transfer.detail.copy_local',counts:any={};
  for(const [shot,id] of [['00-transfer-idle',remote],['01-transfer-copied',remote],['01-transfer-copied',local],['02-transfer-renewed',remote],['03-transfer-reset',remote],['04-transfer-path-click',local]])counts[`${shot}:${id}`]=await green(shot,id);
  report.green_pixels=counts;
  assert.equal(counts['00-transfer-idle:'+remote],0,'idle remote copy button has no success mark');
  assert(counts['01-transfer-copied:'+remote]>15,'remote copy shows its success mark');
  assert.equal(counts['01-transfer-copied:'+local],0,'the local copy button is independent');
  assert(counts['02-transfer-renewed:'+remote]>15,'a repeated copy renews the two-second feedback');
  assert.equal(counts['03-transfer-reset:'+remote],0,'feedback resets automatically');
  assert(counts['04-transfer-path-click:'+local]>15,'clicking the local path acknowledges on its adjacent button');
  report.checks.push('Button pixels confirm independent success marks, renewed timeout and automatic reset in the details popover');
  report.status='passed';
 }catch(error){report.status='failed';report.error=String(error);process.exitCode=1;}
}
await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));console.log(report.status+': '+join(out,'report.json'));
