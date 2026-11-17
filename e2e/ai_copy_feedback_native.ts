/** Native copy feedback and code toolbar regression, using an isolated local provider. */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createServer} from 'node:http';
import {mkdir,mkdtemp,open,writeFile,readFile,rm} from 'node:fs/promises';
import {inflateSync} from 'node:zlib';
import {join,resolve} from 'node:path';
import {aiToggleId} from './ai_entry.ts';
import {hoverUserRow} from './ai_user_actions.ts';
import {readRequestText} from './provider_fixture.ts';
import {readPasteboardText,writePasteboardText} from './private_pasteboard.ts';

const prefix=resolve(process.env.ZW_AI_TEST_PREFIX??'zig-out');
const out=resolve(process.argv[2]??'/tmp/zw-ai-copy-evidence');
const theme=process.argv[3]??'dark';assert(theme==='dark'||theme==='light',`theme ${theme}`);
await mkdir(out,{recursive:true});
const iso=await mkdtemp('/private/tmp/zw-ai-copy-'),data=join(iso,'data'),rpc=join(iso,'rpc');
await mkdir(data);await mkdir(rpc);process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const h=await import(join(prefix,'share/zenit/harness/client.ts'));
const code='printf "COPY_CODE_EXACT"\n\n# '+ 'long_command_argument_'.repeat(16)+'\nprintf "完成"';
const answer='复制反馈检查\n\n```sh\n'+code+'\n```\n\nCOPY_COMPLETE';
let requests=0,titleRequests=0;const bodies:any[]=[];
const server=createServer(async(req,res)=>{
 const body=await readRequestText(req);
 if(req.method!=='POST')return res.end('{"data":[{"id":"copy-fixture"}]}');
 const request=JSON.parse(body);bodies.push(request);
 // The first message also asks for a conversation title: a separate tool-less request with the naming instruction
 // (src/ai/conversation_title.zig `instruction`, since fcec7cb4). It gets a title; every other POST is a chat turn.
 const naming=(request.tools??[]).length===0&&String(request.messages?.[0]?.content??'').includes('会话标题');
 if(naming)titleRequests++;else requests++;
 res.writeHead(200,{'content-type':'text/event-stream'});
 res.end('data: '+JSON.stringify({choices:[{index:0,delta:{content:naming?'复制反馈检查':answer}}]})+'\n\ndata: [DONE]\n\n');
});
await new Promise<void>(done=>server.listen(0,'127.0.0.1',done));
await writeFile(join(data,'config.toml'),`[meta]\nconfig_revision=1\n[ui]\ntheme="${theme}"\nfont_size=14\n[ai]\ndefault_provider="fixture"\n[[ai.providers]]\nid="fixture"\nkind="openai_compat"\nendpoint="http://127.0.0.1:${(server.address()as any).port}/v1/chat/completions"\nenabled=true\n[[ai.providers.models]]\nname="copy-fixture"\ncontext_window=200000\ndefault=true\n`);
const log=await open(join(out,'app.log'),'w');
const app=spawn(join(prefix,'bin/zerowork'),[],{env:{...process.env,ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1'},stdio:['ignore',log.fd,log.fd]});
const ended=new Promise<void>(done=>app.once('close',()=>done()));
const shown=(n:any)=>n&&n.visible!==false&&!n.hidden&&(n.effective_opacity??1)>0&&n.rect?.w>0&&n.rect?.h>0;
const visible=(id:string)=>h.waitFor(async()=>(await h.query(id)).find(shown)??null,15000);
const click=async(id:string)=>{await visible(id);assert((await h.clickTestId(id)).ok,id)};
// The app copies through zenit to the run's private pasteboard (ZENIT_E2E_PASTEBOARD, inherited by the app below), never
// the person's clipboard. A sentinel goes first so each assertion reads what that click copied.
const copiedBy=async(id:string)=>{const sentinel=`zw-e2e-sentinel-${Date.now()}`;await writePasteboardText(sentinel);await click(id);return await h.waitFor(async()=>{const value=await readPasteboardText();return value!==null&&value!==sentinel?value:null},5000).catch((error:any)=>{throw new Error(`${id}: the click did not put anything on the run's pasteboard (${error})`)})};
const report:any={status:'running',checks:[]};
// The harness tree omits icon assets, so the acknowledgement glyph is checked in the screenshot: the copy button's glyph
// pixels against the idle capture (PNG decoded here, no third-party code). Strong per-pixel changes only, so the
// button's hover / pressed tint does not count as a glyph change.
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
const glyphChange=async(shot:string,base:string,id:string)=>{
 const flat=(n:any):any[]=>Array.isArray(n)?n.flatMap(flat):n?[n,...(n.children??[]).flatMap(flat)]:[];
 const node=flat(JSON.parse(await readFile(join(out,shot+'.json'),'utf8'))).find((n:any)=>n.test_id===id);assert(node,`${shot}: ${id}`);
 const [a,b]=await Promise.all([shot,base].map(async name=>decode(await readFile(join(out,name+'.png')))));assert.equal(a.width,b.width);const scale=a.width/1440;
 const [x0,y0,w,hgt]=[node.rect.x+4,node.rect.y+4,node.rect.w-8,node.rect.h-8].map(v=>Math.round(v*scale));let changed=0;
 for(let y=y0;y<y0+hgt;y++)for(let x=x0;x<x0+w;x++){const i=(y*a.width+x)*a.channels;if(Math.max(Math.abs(a.pixels[i]-b.pixels[i]),Math.abs(a.pixels[i+1]-b.pixels[i+1]),Math.abs(a.pixels[i+2]-b.pixels[i+2]))>60)changed++}
 return changed};
try{
 await h.waitForServerReady();await h.resizeWindow(1440,1000);
 await click('workspace.empty.local');await click(await aiToggleId());await click('ai.prompt');
 await h.type_('检查复制和代码按钮');await click('ai.send');
 await visible('ai.turn.complete');await visible('ai.message.code.copy');
 const cap=async(name:string)=>{await h.mouseMove(1,1);assert((await h.screenshot(join(out,name+'.png'))).ok);await writeFile(join(out,name+'.json'),JSON.stringify(await h.query('ai.panel'),null,2));};
 await cap('00-idle');
 assert.equal(await copiedBy('ai.message.code.copy'),code+'\n');
 await cap('01-code-copied');
 await h.sleep(1100);await click('ai.message.code.copy');await h.sleep(1100);
 await cap('01b-code-renewed');await h.sleep(1100);await cap('01c-code-reset');
 report.checks.push('Code copy writes exact original bytes, is independent, renews on repeated clicks, and resets after two seconds');
 const initial=await visible('ai.message.code.text');const viewport=await visible('ai.message.code.scroll');
 assert(initial.rect.w>viewport.rect.w);
 await click('ai.message.code.wrap');
 await h.waitFor(async()=>{const n=await visible('ai.message.code.text');return n.rect.w<=viewport.rect.w&&n.rect.h>initial.rect.h?n:null},5000);
 await cap('02-code-wrapped');
 await click('ai.message.code.wrap');
 await h.waitFor(async()=>(await visible('ai.message.code.text')).rect.w>viewport.rect.w||null,5000);
 report.checks.push('Code wrap changes actual text layout in both directions');
 assert.equal(await copiedBy('ai.turn.copy'),answer);
 await cap('03-turn-copied');await h.sleep(2200);
 await hoverUserRow(h);assert.equal(await copiedBy('ai.message.copy'),'检查复制和代码按钮');
 await cap('04-user-copied');
 report.checks.push('Turn summary and user message copies write the correct content and acknowledge separately');
 await click('ai.turn.fork');await visible('ai.session.close.confirmation');await click('ai.session.close.accept'); // fork on a bound conversation asks 结束当前会话并使用副本？ (copy_use)
 await h.waitFor(async()=>!(await h.query('ai.session.close.confirmation')).some(shown)||null,15000);await visible('ai.turn.complete');
 await click('ai.sessions');await visible('ai.session.row.1');await visible('ai.session.row.2');
 await cap('05-fork');report.checks.push('Summary fork creates a separate conversation and retains the original');
 assert.equal(requests,1,'one chat turn: copy, wrap and fork never re-run the model');assert.equal(titleRequests,1,'one title request for the one conversation (conversation_title.zig: one title request per conversation; the fork keeps it)');
 const glyph:any={};for(const [shot,base,id] of [['01-code-copied','00-idle','ai.message.code.copy'],['01-code-copied','00-idle','ai.turn.copy'],['01b-code-renewed','00-idle','ai.message.code.copy'],['01c-code-reset','00-idle','ai.message.code.copy'],['03-turn-copied','00-idle','ai.turn.copy'],['04-user-copied','00-idle','ai.turn.copy']])glyph[`${shot}:${id}`]=await glyphChange(shot,base,id);report.glyph_changes=glyph;
 assert(glyph['01-code-copied:ai.message.code.copy']>20,'code copy shows its acknowledgement glyph');assert.equal(glyph['01-code-copied:ai.turn.copy'],0,'the turn copy button is independent of the code copy');
 assert(glyph['01b-code-renewed:ai.message.code.copy']>20,'a repeated code copy renews the two-second acknowledgement');assert.equal(glyph['01c-code-reset:ai.message.code.copy'],0,'the code copy glyph returns to idle');
 assert(glyph['03-turn-copied:ai.turn.copy']>20,'turn copy shows its acknowledgement glyph');assert.equal(glyph['04-user-copied:ai.turn.copy'],0,'the turn copy glyph resets 2.2 s later, independently of the user message copy');
 report.status='passed';
}catch(error){report.status='failed';report.error=String(error);process.exitCode=1;await h.screenshot(join(out,'failure.png')).catch(()=>{});}
finally{
 app.kill('SIGTERM');await Promise.race([ended,h.sleep(2000)]);
 if(app.exitCode===null&&app.signalCode===null){app.kill('SIGKILL');await ended;}
 await log.close();await new Promise<void>(done=>server.close(()=>done()));await rm(iso,{recursive:true,force:true});
 report.requests=bodies;await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));
}
console.log(report.status+': '+join(out,'report.json'));
