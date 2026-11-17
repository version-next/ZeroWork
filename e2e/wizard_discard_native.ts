/** Production connection editor: cancel / Escape discard a draft directly, also during a live connection test. */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createHash} from 'node:crypto';
import {createServer} from 'node:net';
import {mkdir,mkdtemp,realpath,open,readFile,writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {waitForServerReady,waitFor,query,clickAt,key,type_,inputState,resizeWindow,screenshot,screenPos,scrollAt,mouseMove,windows} from '../zig-out/share/zenit/harness/client.ts';
const binary=resolve(process.argv[2]),out=resolve(process.argv[3]),theme=process.argv[4]??'dark';
assert(['dark','light','sauber'].includes(theme));
await mkdir(out,{recursive:true});
const isolated=await realpath(await mkdtemp(join(tmpdir(),'zw-wizard-discard-'))),data=join(isolated,'data'),rpc=join(isolated,'rpc');
await mkdir(data);await mkdir(rpc);
await writeFile(join(data,'hosts.toml'),'');
await writeFile(join(data,'config.toml'),`[meta]\nconfig_revision=1\n[ui]\ntheme="${theme}"\nfont_family="Menlo"\nfont_size=14\n`);
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
// Own loopback peer: accepts the TCP connection and never answers, so the SSH handshake stays pending.
let connected=0,disconnected=0;const sockets=new Set<any>();
const peer=createServer(s=>{connected++;sockets.add(s);s.on('data',()=>{});s.on('error',()=>{});s.on('close',()=>{disconnected++;sockets.delete(s)});});
await new Promise<void>(r=>peer.listen(0,'127.0.0.1',r));const port=(peer.address() as any).port;
const log=await open(join(out,'app.log'),'w');
const child=spawn(binary,[],{env:{...process.env,ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1'},stdio:['ignore',log.fd,log.fd]});
const ended=new Promise<void>(r=>child.once('close',()=>r()));
const report:any={status:'running',binary,sha256:createHash('sha256').update(await readFile(binary)).digest('hex'),theme,checks:[],stages:[],limits:['Synthetic Harness input, not physical keyboard/IME verification','Own loopback server holds SSH handshake; no external host, credentials or remote commands']};
// Island B v3 (e1372d88): the connection editor is its own native window (wizard.zig window_spec 720×640, minimum
// 600×420); the Harness is bound to it while it is open. It has no in-window close button: the window closes
// through 取消 (wizard.cancel), Escape (wizard.zig windowKey) or its traffic light (windowCloseRequest → the same
// cancel). Cancelling never asks to discard (wizard.discard.confirm must not appear — e2e_ignore.txt).
const WINDOW={w:720,h:640},MINIMUM={w:600,h:420};
const STAGE_HEIGHT=54.6; // wizard_styles.zig testStage(): fixed row height (title 18 + gap 3 + detail 17.6 + padding 8+8)
const shown=(n:any)=>n&&n.visible!==false&&n.hidden!==true&&(n.effective_opacity??1)>0&&n.rect?.w>0&&n.rect?.h>0;
const flatten=(n:any):any[]=>[n,...(n.children??[]).flatMap(flatten)];
const text=(n:any)=>flatten(n).map(x=>x.text??'').join(' ');
const inside=(a:any,b:any)=>a.x>=b.x-.5&&a.y>=b.y-.5&&a.x+a.w<=b.x+b.w+.5&&a.y+a.h<=b.y+b.h+.5;
async function nodes(id:string):Promise<any[]>{const q=await query(id);return Array.isArray(q)?q:[];}
async function current(id:string){return (await nodes(id)).find(shown)??null;}
async function visible(id:string){return waitFor(()=>current(id));}
const SCROLLS=['wizard.scroll.identity','wizard.scroll.route','wizard.scroll.review'];
/** The node, scrolled fully into its step's scroll viewport when it lives in one. */
async function reveal(id:string){
 return waitFor(async()=>{
  const n=await current(id);if(!n)return null;
  let area:any=null;for(const s of SCROLLS){const a=await current(s);if(a&&flatten(a).some(x=>x.id===n.id)){area=a;break;}}
  if(!area)return n;
  const top=area.rect.y,bottom=area.rect.y+area.rect.h;
  if(n.rect.y>=top-0.5&&n.rect.y+n.rect.h<=bottom+0.5)return n;
  await scrollAt(area.rect.x+area.rect.w/2,area.rect.y+area.rect.h/2,0,n.rect.y<top?Math.min(400,top-n.rect.y+12):-Math.min(400,n.rect.y+n.rect.h-bottom+12));
  return null;
 });
}
/** Click the centre of a node once it is revealed and its rect has stopped moving. */
async function click(id:string){let prior='';const n=await waitFor(async()=>{const n=await reveal(id);const at=JSON.stringify(n.rect);const still=at===prior;prior=at;return still?n:null;});assert((await clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok,id);}
async function value(id:string){return (await inputState(id)).buffer;}
async function fill(id:string,v:string){await click(id);await key('a',{cmd:true});await type_(v);await waitFor(async()=>await value(id)===v||null);}
/** The editor window is open and bound, its frame filling it. `screenPos` answers with the rect only: a query for
 *  the window root would serialise the whole editor tree (too large once the test logs are expanded). */
async function editorOpen(size=WINDOW){return waitFor(async()=>{const w=(await windows()).windows;if(w.length!==2||!w[1].bound)return null;const r:any=await screenPos('wizard.window');return r&&r.x===0&&r.y===0&&r.w===size.w&&r.h===size.h?{rect:r}:null;});}
/** The editor window is gone (only the bound main window left) and no discard confirmation exists anywhere. */
async function closed(){await waitFor(async()=>{const w=(await windows()).windows;return w.length===1&&w[0].bound&&!(await nodes('wizard.window')).some(shown)?true:null;});assert(!(await nodes('wizard.discard.confirm')).some(shown),'no discard confirmation');}
async function open_(){await click('sidebar.empty.new');await editorOpen();assert.match(text(await visible('wizard.title')),/新建主机/);}
/** Fixed chrome: stepper on top, footer at the bottom, the step's scroll viewport between them, all inside the window. */
async function capture(name:string,size=WINDOW){
 const win=await editorOpen(size),steps=await visible('wizard.steps'),foot=await visible('wizard.footer');
 const area=(await Promise.all(SCROLLS.map(current))).find(Boolean);assert(area,name+': a step viewport is shown');
 assert(inside(foot.rect,win.rect)&&inside(steps.rect,win.rect),name+': stepper and footer inside the window');
 assert(area.rect.y>=steps.rect.y+steps.rect.h-.5&&area.rect.y+area.rect.h<=foot.rect.y+.5,name+': viewport between stepper and footer');
 await mouseMove(win.rect.w-40,20);await writeFile(join(out,name+'.json'),JSON.stringify({window:win.rect,steps:steps.rect,scroll:area.rect,footer:foot.rect},null,2));
 assert((await screenshot(join(out,name+'.png'))).ok);report.stages.push({name,rect:win.rect});
}
const deferred:any={};
try{
 await waitForServerReady(30000);assert.equal(Number(JSON.parse(await readFile(join(rpc,'owner.json'),'utf8')).pid),child.pid);
 await resizeWindow(1440,900);await open_();
 await fill('wizard.name','DB-Master');await fill('wizard.host','127.0.0.1');await fill('wizard.port',String(port));await fill('wizard.user','fixture');
 await capture('01-identity');await click('wizard.cancel');await closed();
 assert.equal(connected,0);assert.equal((await readFile(join(data,'hosts.toml'),'utf8')).trim(),'');
 report.checks.push('Cancel closes a populated draft directly and persists nothing');
 await open_();assert.equal(await value('wizard.name'),'','reopened editor has no cancelled draft');
 await fill('wizard.name','DB-Master');await fill('wizard.host','127.0.0.1');await fill('wizard.port',String(port));await fill('wizard.user','fixture');
 await click('wizard.next.identity');await capture('03-route');assert.match(text(await visible('wizard.access.direct')),/从本机直接连接/);
 await click('wizard.next.route');await capture('04-review');assert.match(text(await visible('wizard.review.name')),/DB-Master/);
 await click('wizard.review.modify');await visible('wizard.name');assert.equal(await value('wizard.name'),'DB-Master');await click('wizard.next.identity');await click('wizard.next.route');await visible('wizard.review.name');
 assert((await resizeWindow(MINIMUM.w,MINIMUM.h)).ok);await capture('07-review-compact',MINIMUM);assert((await resizeWindow(WINDOW.w,WINDOW.h)).ok);await editorOpen();
 // Live probe against the silent peer: one connection, the per-hop stage keeps endpoint and state.
 await click('wizard.test');await waitFor(async()=>connected===1||null,15000);
 await waitFor(async()=>/取消测试/.test(text(await visible('wizard.test')))||null);
 const stage=await reveal('wizard.test.stage.0');assert(Math.abs(stage.rect.h-STAGE_HEIGHT)<.1,'stage row height '+stage.rect.h);
 assert.match(text(stage),/第 1 跳 · DB-Master/);assert.match(text(stage),new RegExp('fixture@127\\.0\\.0\\.1:'+port));
 for(const line of flatten(stage).filter((n:any)=>n.text))assert(inside(line.rect,stage.rect),'stage text inside its row: '+line.text);
 assert(!(await current('wizard.test.hop.9')));await capture('08a-test-progress-visible');
 {
  const card=await visible('wizard.test.card'),toggle=await visible('wizard.test.toggle');
  deferred.toggle={card:card.rect,toggle:toggle.rect};
  const steps=await visible('wizard.steps'),actions=await visible('wizard.footer');assert(card.rect.y>=steps.rect.y+steps.rect.h-0.5&&card.rect.y<actions.rect.y);
 }
 await click('wizard.test.toggle');await reveal('wizard.test.hop.9');await capture('08b-test-details-expanded');
 // Details: the stage log viewport scrolls into the step viewport and ends above the footer.
 const logs=await reveal('wizard.test.logs.viewport');await capture('08b2-test-details-logs');assert(logs.rect.y+logs.rect.h<=(await visible('wizard.footer')).rect.y+1);
 await click('wizard.test.toggle');await waitFor(async()=>!(await current('wizard.test.hop.9'))||null);await reveal('wizard.test.stage.0');await capture('08c-test-details-collapsed');
 report.checks.push('Real per-hop stage summary keeps endpoint and state; details expand and collapse during the same live probe');
 // 取消 during the probe: the editor cancels that exact probe, waits for its release (editor.zig onCancelClick),
 // then the window closes; the peer sees the disconnect and nothing is saved.
 assert.equal(disconnected,0);await click('wizard.cancel');await closed();
 assert((await screenshot(join(out,'09-closed-after-test.png'))).ok);
 await waitFor(async()=>disconnected===1||null,15000);
 assert.equal((await readFile(join(data,'hosts.toml'),'utf8')).trim(),'');
 await open_();assert.equal(await value('wizard.name'),'','reopened editor has no cancelled draft');
 await click('wizard.cancel');await closed();
 await open_();await fill('wizard.name','unfinished');assert((await key('escape')).ok);await closed();
 assert((await screenshot(join(out,'10-closed-after-escape.png'))).ok);
 assert.equal(connected,1);assert.equal((await readFile(join(data,'hosts.toml'),'utf8')).trim(),'');
 report.checks.push('Cancel during the probe releases it and closes','No host persisted by cancellation','Reopen has no cancelled draft','Empty draft closes directly','Escape closes partial input directly','No discard confirmation shown');
 // 连接预检 header row (wizard.test.toggle) is a row of the test card: it stays inside the card's padding like the
 // stage rows below it (testResult padding 16; editor.zig mounts it `.width = .fill()`).
 {
  const {card,toggle}=deferred.toggle;report.test_toggle=deferred.toggle;
  assert(toggle.x+toggle.w<=card.x+card.w-16+.5,'连接预检 header stays inside the test card: '+JSON.stringify(deferred.toggle));
 }
 report.status='passed';
}catch(e){report.status='failed';report.error=String(e);await screenshot(join(out,'failure.png')).catch(()=>{});throw e;}
finally{report.peer={connected,disconnected};await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));child.kill('SIGTERM');await ended;for(const s of sockets)s.destroy();await new Promise<void>(r=>peer.close(()=>r()));await log.close();}
