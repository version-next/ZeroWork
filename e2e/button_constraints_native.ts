/** Production button/layout audit. Read-only navigation plus isolated Local terminal.
 * node e2e/button_constraints_native.ts OUT [light|dark] [path]   (binary: zig-out/bin/zerowork)
 *
 * Every node on each visited screen is scanned (hard assertions):
 * - a native Button's text lies inside the Button (the button-constraint invariant);
 * - a text node lies inside its direct parent box. Ellipsized text is clipped to its box and wrapped text is laid out
 *   inside it, so a text rectangle wider than its parent means the label really runs out of its column (over neighbours
 *   or past the window). Scroll viewports are not direct text parents (rows are), so scrolled content is not flagged.
 *
 * Current contract (re-checked against source):
 * - Window sizes: main window 1440×900, min 860×480 (process_windows.zig main_window); the preferences window is its own
 *   native window 960×780, min 760×480 (settings_shell.zig window) — each is swept at its default and minimum size.
 * - Empty workspace actions: native md Buttons 本地终端 / 快速连接 in a row with gap 8 (shell_styles.zig emptyActions).
 * - Transfers: title-bar tool `toolbar.transfers` opens the native Popover `transfer.manager` (the old `transfer.panel`
 *   is gone); with no jobs it shows `transfer.empty`.
 * - Settings: two-level navigation; the category / subpage / pane map is settings_nav.ts CATEGORIES + DIRECT (kept in
 *   sync with settings_subpages.zig), so every pane is reached and scrolled to its end. No draft ⇒ no Save Bar, no write.
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdir,mkdtemp,realpath,open,readFile,writeFile,rm,readdir} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {waitForServerReady,waitFor,query,tree,clickAt,clickTestId,key,type_,resizeWindow,screenshot,sleep,scrollAt,mouseMove,inputState,request} from '../zig-out/share/zenit/harness/client.ts';
import {aiToggleId} from './ai_entry.ts';
import {settingsNav,CATEGORIES,DIRECT} from './settings_nav.ts';
const nav=settingsNav({timeout:8000});
assert(process.argv[2],'output directory required');const out=resolve(process.argv[2]);await mkdir(out,{recursive:true});assert.equal((await readdir(out)).length,0,'use a fresh evidence directory');
const theme=process.argv[3]&&process.argv[3]!=='path'?process.argv[3]:'dark',pathOnly=process.argv.slice(3).includes('path');
assert(['light','dark'].includes(theme),'theme must be light or dark');
const binary=resolve('zig-out/bin/zerowork');
const longDirectory='/Users/fixture/Downloads/团队服务器归档与诊断输出/production-cluster-2026-10-26/very-long-download-destination';
const report:any={status:'running',theme,sha256:createHash('sha256').update(await readFile(binary)).digest('hex'),screens:[],checks:[],buttons:{},text_overflow:[],limits:['Synthetic Harness input; physical pointer/IME/OS picker not verified.','No external connections, destructive user-data actions or external AI calls.','Button rectangles cannot prove glyph ink fits: source metrics and pixel review are also required.']};
const iso=await realpath(await mkdtemp(join(tmpdir(),'zw-buttons-'))),rpc=join(iso,'rpc'),data=join(iso,'data');await mkdir(rpc);await mkdir(data);await writeFile(join(data,'config.toml'),`[meta]\nconfig_revision=1\n[ui]\ntheme="${theme}"\nfont_family="Menlo"\nfont_size=14\n[transfer]\ndownload_dir="${longDirectory}"\n`);
// One saved host: with an empty registry the second empty-state action is 新建主机 (opens the editor); with saved hosts it is
// 快速连接 (nav_host.zig syncHomeConnect / homeConnect), which is the panel this audit covers. 192.0.2.0/24 is TEST-NET-1.
await writeFile(join(data,'hosts.toml'),'[registry]\nschema_version=2\nrevision=1\nnext_connection_id=2\nnext_group_id=1\n[[hosts]]\nconnection_id=1\nrevision=1\nprotocol="ssh"\nauth_mode="password"\nname="audit-host"\nhost="192.0.2.10"\nport=22\nuser="root"\nroute=[]\n');
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;const log=await open(join(out,'app.log'),'w');
const app=spawn(binary,[],{env:{...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1',OPENAI_API_KEY:'',ANTHROPIC_API_KEY:''},stdio:['ignore',log.fd,log.fd]});const ended=new Promise<number|null>(done=>app.once('close',code=>done(code)));
const shown=(n:any)=>n?.rect&&n.hidden!==true&&n.visible!==false&&(n.effective_opacity??1)>0&&n.rect.w>0&&n.rect.h>0;
const flat=(n:any):any[]=>shown(n)?[n,...(n.children??[]).flatMap(flat)]:[];
const visible=async(id:string)=>waitFor(async()=>{const q=await query(id);assert(Array.isArray(q),`oversized query ${id}`);return q.find(shown)??null},8000);
const click=async(id:string)=>{await visible(id);assert((await clickTestId(id)).ok,id)};
const hidden=async(id:string)=>waitFor(async()=>!(await query(id)).some(shown)||null,8000);
const edit=async(id:string,value:string)=>{await click(id);await key('a',{cmd:true});await type_(value);await waitFor(async()=>(await inputState(id)).buffer===value||null,5000)};
const inside=(a:any,b:any)=>a.x>=b.x-0.6&&a.y>=b.y-0.6&&a.x+a.w<=b.x+b.w+0.6&&a.y+a.h<=b.y+b.h+0.6;
const buttonOverflow:any[]=[];
function scan(n:any,screen:string,path:string[]=[]){
 if(!shown(n))return;const name=n.test_id??n.component??n.tag,trail=[...path,name];
 if(n.component==='Button'){
  const text=flat(n).filter(v=>v.text).map(v=>v.text).join(' '),id=n.test_id??`node-${n.id}`;
  report.buttons[`${screen}:${id}`]={text,rect:n.rect};
  for(const leaf of flat(n).filter(v=>v.text))if(!inside(leaf.rect,n.rect))buttonOverflow.push({screen,id,path:trail.join('/'),text:leaf.text,button:n.rect,content:leaf.rect});
 }
 for(const c of n.children??[]){
  if(shown(c)&&c.text&&!inside(c.rect,n.rect))report.text_overflow.push({screen,path:[...trail,c.test_id??c.tag].join('/'),text:c.text,parent:n.rect,content:c.rect});
  scan(c,screen,trail);
 }
}
async function capture(name:string,ids:string[]){await sleep(150);const nodes:any={};for(const id of ids){const q=await query(id);nodes[id]=q;if(Array.isArray(q))for(const n of q)scan(n,name);else report.screens.push({name,id,query_limit:true});}await writeFile(join(out,name+'.json'),JSON.stringify(nodes,null,2));assert((await screenshot(join(out,name+'.png'))).ok);report.screens.push({name,ids});await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));}
/** Resize the key window (main or preferences; resizeWindow acts on the key window) and wait until its tree root has that size. */
async function sizeTo(w:number,height:number){assert((await resizeWindow(w,height)).ok);await waitFor(async()=>{const r:any=(await tree({visibleOnly:true}))?.rect;return r&&Math.abs(r.w-w)<1&&Math.abs(r.h-height)<1||null},5000)}
/** Scroll the settings content viewport to its end: scroll down until the lowest content edge stops moving (time-bounded). */
async function settingsBottom(){
 let last=Number.NaN;
 await waitFor(async()=>{
  const v=(await query('settings.viewport')).find(shown);if(!v)return null;
  const bottom=flat(v).filter((n:any)=>n!==v).reduce((m:number,n:any)=>Math.max(m,n.rect.y+n.rect.h),0);
  if(Math.abs(bottom-last)<0.5)return true;last=bottom;
  await scrollAt(v.rect.x+v.rect.w/2,v.rect.y+v.rect.h/2,0,-2400);return null;
 },8000);
}
const allPanes=[...CATEGORIES.flatMap(([,,subs])=>subs.flatMap(([,,panes])=>panes)),...DIRECT.flatMap(([,,panes])=>panes)];
const categories=[...CATEGORIES.map(([cat])=>cat),...DIRECT.map(([cat])=>cat)];
try{
 await waitForServerReady();assert.equal(Number(JSON.parse(await readFile(join(rpc,'owner.json'),'utf8')).pid),app.pid);
 if(pathOnly){
  await nav.open();
  for(const [w,height] of [[960,780],[760,480]]){await sizeTo(w,height);await nav.toField('download_dir');await capture(`long-directory-${w}`,['settings.field.download_dir','settings.transfer.defaults']);
   const button=await visible('settings.field.download_dir'),label=await visible('settings.directory.label');assert(inside(label.rect,button.rect),'path label is constrained by field');
   const panel=await visible('settings.panel');
   await mouseMove(panel.rect.x+20,panel.rect.y+panel.rect.h-20);await hidden('settings.directory.tooltip');await mouseMove(button.rect.x+button.rect.w/2,button.rect.y+button.rect.h/2);const tip=await visible('settings.directory.tooltip');assert(flat(tip).map((n:any)=>n.text??'').join('').includes(longDirectory),'full path retained');assert(inside(tip.rect,{x:0,y:0,w,h:height}),'tooltip stays inside the window');assert(tip.rect.h>30,'full path wraps');await capture(`long-directory-tooltip-${w}`,['settings.directory.tooltip']);
   await mouseMove(panel.rect.x+20,panel.rect.y+panel.rect.h-20);await hidden('settings.directory.tooltip');}
  await nav.close();
 }else{
 for(const [w,height] of [[1440,900],[860,480]]){
  await sizeTo(w,height);
  const local=await visible('workspace.empty.local'),choose=await visible('workspace.empty.choose');assert(flat(choose).some((n:any)=>n.text==='快速连接'),'with saved hosts the second action is 快速连接');
  assert(Math.abs(choose.rect.x-(local.rect.x+local.rect.w)-8)<0.5,`empty actions keep their 8 px gap (shell_styles.zig emptyActions), got ${choose.rect.x-local.rect.x-local.rect.w}`);
  assert(Math.abs(local.rect.y-choose.rect.y)<0.5&&Math.abs(local.rect.h-choose.rect.h)<0.5,'both native md Buttons share a row and a height');
  await capture(`empty-${w}`,['workspace.empty','workspace.sidebar']);
  await click('workspace.empty.choose');await visible('quick.query');await edit('quick.query','no-such-audit-host');await capture(`quick-${w}`,['quick.connect']);
  await click('quick.clear');await waitFor(async()=>(await inputState('quick.query')).buffer===''||null,5000);await click('quick.close');await hidden('quick.connect');report.checks.push(`quick clear/close ${w}`);
  await click('toolbar.transfers');const manager=await visible('transfer.manager'),empty=await visible('transfer.empty');assert(inside(empty.rect,manager.rect),'empty state inside the transfer popover');
  assert(inside(manager.rect,{x:0,y:0,w,h:height}),'transfer popover inside the window');await capture(`transfers-${w}`,['transfer.manager']);await key('escape');await hidden('transfer.manager');report.checks.push(`transfers popover open/Escape ${w}`);
 }
 await nav.open();
 for(const [w,height] of [[960,780],[760,480]]){
  await sizeTo(w,height);
  for(const cat of categories){
   await nav.toCategory(cat);await capture(`settings-${cat}-${w}`,['settings.panel']);
   await settingsBottom();await capture(`settings-${cat}-bottom-${w}`,['settings.panel']);
  }
  for(const pane of allPanes){
   await nav.toPane(pane);await settingsBottom();await capture(`${pane.replaceAll('.','-')}-bottom-${w}`,['settings.panel']);report.checks.push(`pane reachable and scrolled to its end ${pane} ${w}`);
  }
  // Unchanged settings: the floating Save Bar (with Save) only exists while a draft exists, so nothing can be saved and nothing is written.
  const before=await readFile(join(data,'config.toml'),'utf8');assert.equal(await nav.dirty(),false,'unchanged settings show no Save Bar');assert.equal(await readFile(join(data,'config.toml'),'utf8'),before,'navigation alone writes nothing');
  report.checks.push(`all ${categories.length} settings categories and ${allPanes.length} panes navigated and scrolled ${w}`);
 }
 await nav.close();await hidden('settings.panel');
 await sizeTo(1440,900);
 await click('workspace.empty.local');await visible('terminal.surface');report.checks.push('Local terminal actually opens');
 for(const [w,height] of [[1440,900],[860,480]]){
  await sizeTo(w,height);
  await capture(`local-${w}`,['tabs.strip','local.statusbar']);
  await click(await aiToggleId());await visible('ai.prompt');await capture(`ai-${w}`,['ai.panel']);await click('ai.collapse');await visible('ai.launcher');report.checks.push(`assistant open/collapse ${w}`);
  // Rename: the shortcut is F2 (actions.zig rename_tab) but it yields to a focused terminal (shortcut_router.zig
  // `.yield.content`), so the tab title's double-click opens the rename popover (as chromeless_controls_native does).
  {const title=await visible('tabs.title');assert((await clickAt(title.rect.x+title.rect.w/2,title.rect.y+title.rect.h/2,2)).ok);}await visible('tabs.rename.input');await capture(`rename-${w}`,['tabs.rename']);await key('escape');await hidden('tabs.rename');report.checks.push(`rename cancel ${w}`);
 }
 }
 report.button_overflow=buttonOverflow;
 assert.equal(buttonOverflow.length,0,`button text leaves its Button: ${JSON.stringify(buttonOverflow.slice(0,5))}`);
 report.checks.push(`${Object.keys(report.buttons).length} Button instances scanned: every Button keeps its text inside its rectangle`);
 const overflowPaths=[...new Set(report.text_overflow.map((c:any)=>c.path.split('/').filter((p:string)=>p.includes('.')).slice(-2).join(' › ')))];
 assert.equal(report.text_overflow.length,0,`text runs out of its parent box on ${report.text_overflow.length} captures: ${overflowPaths.join('; ')} (first: ${JSON.stringify(report.text_overflow[0])})`);
 report.checks.push('No text node leaves its parent box on any visited screen');
 assert((await request('POST','/quit')).ok);report.exit=await Promise.race([ended,sleep(20000).then(()=>'timeout')]);assert.equal(report.exit,0,'isolated App quits cleanly');
 report.status='passed';
}catch(e){report.status='failed';report.error=String(e);report.button_overflow=buttonOverflow;await capture('failure',['workspace.empty','settings.panel','quick.connect','transfer.manager','settings.directory.tooltip']).catch(()=>{});process.exitCode=1;}
finally{if(app.exitCode===null&&app.signalCode===null)app.kill('SIGTERM');await Promise.race([ended,sleep(3000)]);if(app.exitCode===null&&app.signalCode===null){app.kill('SIGKILL');await ended;}await log.close();await rm(iso,{recursive:true,force:true});await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));console.log(JSON.stringify({status:report.status,buttons:Object.keys(report.buttons).length,button_overflow:buttonOverflow.length,text_overflow:report.text_overflow.length,error:report.error,report:join(out,'report.json')}));}
