/** Session history card (`history`, PLUGIN_ARCH_PLAN PL4b): one complete card with list + detail.
 * Covers the user's rulings (6.2.1 Q11 / Q15 / Q21): opens floating from the title bar, can become a
 * standalone tab (several at once), never enters a split, at most one floating history card per tab.
 * Seeded archive only: no connection, credentials or live shell. Light and dark screenshots of the
 * empty list, the floating card with a replay, the card as a tab and the narrow (list / detail) card. */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdir,mkdtemp,open,writeFile,readFile,rm,realpath,readdir,rename} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {resolve,join} from 'node:path';
import {createHash} from 'node:crypto';
import {waitForServerReady,query,clickTestId,clickAt,key,type_,waitFor,screenshot,resizeWindow,mouseMove,focused,request} from '../zig-out/share/zenit/harness/client.ts';

const binary=resolve(process.argv[2]||'zig-out/bin/zerowork');
const out=resolve(process.argv[3]||'/tmp/zerowork-history-card/native');
await mkdir(out,{recursive:true});
const report:any={binary,sha256:createHash('sha256').update(await readFile(binary)).digest('hex'),checks:[],captures:[],limits:['Seeded archive; split rejection is covered by workspace unit tests (no live session to split with).']};
const shown=(n:any)=>n&&n.visible!==false&&n.hidden!==true&&n.rect.w>0&&n.rect.h>0&&(n.effective_opacity??1)>0;
const text=(n:any):string=>(n.text||'')+(n.children||[]).map(text).join('');
const visible=async(id:string,ms=10000)=>await waitFor(async()=>(await query(id)).find(shown)||null,ms);
const allShown=async(id:string)=>(await query(id)).filter(shown);
const gone=async(id:string)=>await waitFor(async()=>!(await query(id)).some(shown)||null,10000);
const inside=(a:any,b:any)=>a.rect.x>=b.rect.x-1&&a.rect.y>=b.rect.y-1&&a.rect.x+a.rect.w<=b.rect.x+b.rect.w+1&&a.rect.y+a.rect.h<=b.rect.y+b.rect.h+1;
const within=(root:any,id:string):any[]=>[...(root.test_id===id&&shown(root)?[root]:[]),...(root.children||[]).flatMap((c:any)=>within(c,id))];
async function clickNode(n:any){assert((await clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok);}
// zenit routes Escape to an open tooltip / overlay first (e.g. the toolbar tooltip under the pointer).
async function escClose(){const before=(await query('history.panel')).filter(shown).length;for(let i=0;i<3;i++){await key('escape');await new Promise(r=>setTimeout(r,300));if((await query('history.panel')).filter(shown).length<before)return;}assert.fail('Esc closes the floating history card');}

for(const theme of ['light','dark']){
 const isolated=await realpath(await mkdtemp(join(tmpdir(),'zw-history-card-'))),data=join(isolated,'data'),rpc=join(isolated,'rpc');
 for(const path of [rpc,join(data,'logs/history')])await mkdir(path,{recursive:true});
 await writeFile(join(data,'config.toml'),`[meta]\nconfig_revision=1\n[ui]\ntheme="${theme}"\nfont_family="Menlo"\nfont_size=14\n[ui.materials]\nblur_px=0\n[updates]\nauto_check=false\n`);
 await writeFile(join(data,'hosts.toml'),'[registry]\nschema_version=2\nrevision=1\nnext_connection_id=1\nnext_group_id=1\n');
 const started=Date.now()-60000;
 const rows=[['prod-web-01','root',0],['prod-db-02','admin',1],['beta-api-01','deploy',0]] as const;
 const index=rows.map(([host,user,exit],i)=>`${i+1}\t${started-i*600000}\t${started-i*600000+240000}\t240000\t${exit}\t${host}\t${user}\tlogs/history/r${i}.cast\tssh\t${100+i}\n`).join('');
 const lines=Array.from({length:60},(_,i)=>`line-${String(i+1).padStart(3,'0')} systemctl status nginx · active (running)`).join('\r\n');
 const cast=JSON.stringify({version:2,width:100,height:24})+'\n'+JSON.stringify([0,'o','BEGIN_WITNESS\r\n'+lines+'\r\nEND_WITNESS'])+'\n';
 // Staged outside the archive so the first open shows the empty list.
 const staging=join(isolated,'staged');await mkdir(staging);
 await writeFile(join(staging,'index.tsv'),index);
 for(let i=0;i<rows.length;i++)await writeFile(join(staging,`r${i}.cast`),cast);
 process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
 const log=await open(join(out,`${theme}.log`),'w');
 const child=spawn(binary,[],{env:{...process.env,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1',ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0'},stdio:['ignore',log.fd,log.fd]});
 const exited=new Promise(r=>child.once('close',r));
 const cap=async(name:string)=>{await mouseMove(20,20);await new Promise(r=>setTimeout(r,450));const file=join(out,`${theme}-${name}.png`);assert((await screenshot(file)).ok);report.captures.push(file);const tree:any={};for(const id of ['history.panel','history.header','history.list','history.detail','history.detail.empty','history.empty','history.record','terminal.history.card','tabs.strip','float.layer'])tree[id]=await query(id);await writeFile(join(out,`${theme}-${name}.tree.json`),JSON.stringify(tree,null,1));};
 try{
  await waitForServerReady();await resizeWindow(1440,900);
  await visible('workspace.empty');
  // ── Empty list: floating card, centered in the floating region, list + detail empty states ──
  assert((await clickTestId('toolbar.history')).ok);
  const panel=await visible('history.panel');
  await waitFor(async()=>(await query('history.empty')).some(n=>shown(n)&&text(n).includes('还没有会话历史'))||null);
  const detailEmpty=await visible('history.detail.empty');assert(text(detailEmpty).includes('没有可回看的记录'));
  assert(Math.abs(panel.rect.w-819)<=2&&panel.rect.h>=590&&panel.rect.h<=620,`calibrated default size ~820x600 (0.7 x / 0.72 x tab body), got ${panel.rect.w}x${panel.rect.h}`);
  assert(panel.rect.y>=44+8,'floating card stays below the title bar');
  assert.equal((await allShown('history.open_as_tab')).length,1);assert.equal((await allShown('history.close')).length,1);
  assert(['history.query','history.search'].includes((await focused()).test_id),'search has focus on open');
  await cap('empty');
  report.checks.push(`${theme}: empty archive → floating card (~820x600, centered below the title bar), list and detail empty states, search focused`);
  await escClose();await gone('history.panel');
  // ── Records: View selects inside the card (no new tab), replay bar is in the detail area ──
  for(const name of await readdir(staging))await rename(join(staging,name),join(data,'logs/history',name));
  assert((await clickTestId('toolbar.history')).ok);
  await waitFor(async()=>(await allShown('history.record')).length===rows.length||null);
  const count=await visible('history.count');assert(text(count).includes('3 条'));
  const firstView=within(await visible('history.panel'),'history.record.view')[0];await clickNode(firstView);
  const bar=await visible('terminal.history.card');
  const detail=await visible('history.detail'),card=await visible('history.panel');
  assert(inside(bar,detail)&&inside(detail,card),'replay bar lives in the card detail area');
  assert.equal((await allShown('history.list')).length,1,'list stays visible next to the replay');
  assert(!(await query('workspace.card.content')).some(shown),'View no longer opens a tab');
  const position=text(await visible('terminal.history.position'));
  await cap('float-detail');
  report.checks.push(`${theme}: View opens the replay inside the card (list + detail side by side, terminal.history.* in the detail), no tab is created`);
  // ── Open as tab: the same card moves into a standalone tab, selection and replay position kept ──
  await clickNode(await visible('history.open_as_tab'));
  const tabContent=await visible('workspace.card.content');
  const tabPanel=await waitFor(async()=>(await allShown('history.panel')).find(n=>inside(n,tabContent))||null);
  assert(tabPanel,'card root is now the tab content');
  assert.equal((await allShown('history.open_as_tab')).length,0,'a tab card has no open-as-tab / close controls');
  assert.equal(text(await visible('terminal.history.position')),position,'replay position survives the move');
  assert(text(await visible('tabs.strip')).includes('会话记录'),'the tab is titled 会话记录');
  await cap('tab-detail');
  report.checks.push(`${theme}: open-as-tab moves the same card into a standalone tab (replay position kept, no float controls)`);
  // ── One floating history card per tab: the history tab gets its own; reopening only raises it ──
  assert((await clickTestId('toolbar.history')).ok);
  await waitFor(async()=>(await allShown('history.panel')).length===2||null);
  assert((await clickTestId('toolbar.history')).ok);await new Promise(r=>setTimeout(r,400));
  assert.equal((await allShown('history.panel')).length,2,'at most one floating history card per tab');
  // A second history tab from that floating card: tabs can hold several history cards.
  await clickNode(await visible('history.open_as_tab'));
  await waitFor(async()=>(await query('workspace.card.content')).length===2||null);
  report.checks.push(`${theme}: reopening on a tab that already has a floating history card only raises it; a second history tab can be opened`);
  // ── Narrow card: list only, View switches to detail with Back ──
  await resizeWindow(860,480);
  assert((await clickTestId('toolbar.history')).ok);
  const narrow=await waitFor(async()=>(await allShown('history.panel')).find(n=>n.rect.w<450)||null);
  assert(narrow,'a narrow floating card');
  await waitFor(async()=>(await allShown('history.record')).length>0||null);
  assert(!(await allShown('history.detail')).some(n=>inside(n,narrow)),'narrow card shows the list only');
  await cap('narrow-list');
  const narrowNow=(await allShown('history.panel')).filter((n:any)=>n.rect.w<600).sort((a:any,b:any)=>a.rect.w-b.rect.w)[0];const narrowView=within(narrowNow,'history.record.view')[0];await clickNode(narrowView);
  await waitFor(async()=>(await allShown('history.panel')).some((p:any)=>p.rect.w<450&&within(p,'history.back').length>0)||null);
  await waitFor(async()=>(await allShown('terminal.history.card')).some((n:any)=>inside(n,narrow))||null);
  assert(!(await allShown('history.list')).some(n=>inside(n,narrow)),'narrow card shows the detail only');
  await cap('narrow-detail');
  {const p=(await allShown('history.panel')).filter((n:any)=>n.rect.w<600).sort((a:any,b:any)=>a.rect.w-b.rect.w)[0];await clickNode(within(p,'history.back')[0]);}
  await waitFor(async()=>(await allShown('history.list')).some(n=>inside(n,narrow))||null);
  report.checks.push(`${theme}: narrow card (<600) switches between list and detail with Back`);
  await escClose();
  assert((await request('POST','/zerowork/windows',{action:'quit'})).ok);
  await Promise.race([exited,new Promise((_,reject)=>setTimeout(()=>reject(new Error('normal App Quit timed out')),15000))]);
  assert.equal(child.exitCode,0,'App Quit with history cards open exits normally');
 }catch(error){report.ok=false;report.error=String(error);try{await cap('failure');}catch{}throw error;}
 finally{await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));if(child.exitCode===null&&child.signalCode===null)child.kill('SIGTERM');await exited;await log.close();await rm(isolated,{recursive:true,force:true});}
}
report.ok=true;
await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report,null,2));
