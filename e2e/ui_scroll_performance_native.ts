/** Real Metal-window scroll workload. Milliseconds are diagnostic, not a
 * hardware-dependent FPS promise; fixture input never touches user data.
 * node e2e/ui_scroll_performance_native.ts BINARY OUTPUT [THEME]   (THEME: dark | light | sauber, default light)
 *
 * Contract:
 *  - the window shell (`workspace.shell`, shell/styles.yss `root`) is exactly the window's height however long the host
 *    list is: `flex-basis: 0; min-height: 0` on the root (zenit MIGRATION「明确填充和固定留白」). Without it a 40-host list
 *    made the shell as tall as the list, the sidebar viewport (`sidebar.viewport`, a zenit ScrollArea) had nothing to
 *    scroll and the sidebar bottom row (`sidebar.bottom`) fell below the window;
 *  - so with 40 hosts the list content overflows the viewport, the wheel moves it, the last host row becomes fully
 *    visible inside the viewport, and the bottom row stays put inside the window;
 *  - the Settings window's viewport scrolls the same way (wheel and trackpad phases), a large host registry rebuilds the
 *    connection wizard's copy-source Select, and popups reopen.
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdir,mkdtemp,open,readFile,writeFile,rm,realpath} from 'node:fs/promises';
import {resolve,join} from 'node:path';
import * as h from '../vendor/zenit/e2e/client.ts';
import {cleanupOwnedBridgeDirectories} from './native_owned_cleanup.ts';
import {settingsNav} from './settings_nav.ts';
const nav=settingsNav();
const [binaryArg,outArg,themeArg]=process.argv.slice(2);assert(binaryArg&&outArg,'binary output-directory [theme]');
const theme=themeArg||'light';assert(['dark','light','sauber'].includes(theme),'theme: dark | light | sauber');
const binary=resolve(binaryArg),out=resolve(outArg),iso=await realpath(await mkdtemp('/private/tmp/zw-scroll-perf-'));
const data=join(iso,'data'),rpc=join(iso,'rpc');
await Promise.all([mkdir(out,{recursive:true}),mkdir(data),mkdir(rpc)]);
// Translucent materials keep the background-layer fill in the workload (paint_duplicate_fills).
await writeFile(join(data,'config.toml'),`[ui]\ntheme="${theme}"\n[ui.materials]\nblur_px=24\n[ui.materials.background]\ntransparency=50\n`);
const hostCount=Number(process.env.ZEROWORK_SCROLL_HOSTS??40);
assert(Number.isInteger(hostCount)&&hostCount>=40&&hostCount<=400,'fixture host count must be 40..400 (40 rows overflow a 900pt window)');
const groupCount=Math.min(10,Math.ceil(hostCount/4)),hostsPerGroup=Math.ceil(hostCount/groupCount);
let hosts=`[registry]\nschema_version=2\nrevision=1\nnext_connection_id=${hostCount+1}\nnext_group_id=${groupCount+1}\n`;
for(let g=0;g<groupCount;g++)hosts+=`[[groups]]\ngroup_id=${g+1}\nrevision=1\nname="Scroll fixture ${g+1}"\ncollapsed=false\nordered_connection_ids=[${Array.from({length:Math.max(0,Math.min(hostsPerGroup,hostCount-g*hostsPerGroup))},(_,i)=>g*hostsPerGroup+i+1).join(',')}]\n`;
for(let i=0;i<hostCount;i++)hosts+=`[[hosts]]\nconnection_id=${i+1}\nrevision=1\nasset_group_id=${Math.floor(i/hostsPerGroup)+1}\nprotocol="ssh"\nname="Fixture host ${i+1}"\nhost="192.0.2.1"\nuser="fixture"\n`;
await writeFile(join(data,'hosts.toml'),hosts);process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const log=await open(join(out,'app.log'),'w');
const app=spawn(binary,[],{env:{...process.env,ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1'},stdio:['ignore',log.fd,log.fd]});
const ended=new Promise(r=>app.once('close',r)),report:any={binary,theme,cases:[],limits:['Synthetic wheel/trackpad events use the real native dispatcher. CPU/GPU samples exclude RPC round-trip latency.','This is a local rendering workload, not live SSH/KVM network throughput.']};
const shown=(n:any)=>n&&n.hidden!==true&&n.visible!==false&&(n.effective_opacity??1)>0&&n.rect?.w>0&&n.rect?.h>0;
const flat=(n:any):any[]=>n?[n,...(n.children??[]).flatMap(flat)]:[];
const near=(a:number,b:number,s:string)=>assert(Math.abs(a-b)<.5,`${s}: ${a} vs ${b}`);
const bottom=(r:{y:number,h:number})=>r.y+r.h;
const visible=(id:string)=>h.waitFor(async()=>{const nodes=await h.query(id);assert(Array.isArray(nodes),`${id}: ${JSON.stringify(nodes)}`);return nodes.find(shown)||null},15000);
const hidden=(id:string)=>h.waitFor(async()=>{const nodes=await h.query(id);return Array.isArray(nodes)&&!nodes.some(shown)||null},15000);
/** Fully presented: opaque and unscaled (dialogs fade and scale in; a click mid-transition can miss). */
const presented=(n:any)=>shown(n)&&(n.effective_opacity??1)===1&&(n.world_transform?.[0]??1)===1&&(n.world_transform?.[3]??1)===1;
/** Click the shown instance once it is presented and its rect has stopped moving (retained panels share ids). */
async function click(id:string){
 let prior='';
 const node=await h.waitFor(async()=>{const n=(await h.query(id)).find(presented);if(!n){prior='';return null;}const at=JSON.stringify(n.rect);const settled=at===prior;prior=at;return settled?n:null;},15000);
 const result=await h.clickAt(node.rect.x+node.rect.w/2,node.rect.y+node.rect.h/2);assert(result.ok,`${id}: ${JSON.stringify(result)}`);
}
/** The ScrollArea's content box (first child of the viewport container). Only the shown subtree is serialized: the
 * full 40-host list exceeds the harness result buffer. */
async function content(viewportId:string){
 const t=await h.tree({root:viewportId,visibleOnly:true});
 assert(t?.test_id===viewportId&&t.children?.[0]?.rect,`${viewportId}: tree has a content box`);
 return {viewport:t.rect,content:t.children[0].rect,tree:t};
}
const contentY=async(id:string)=>(await content(id)).content.y;
/** Wheel (or trackpad phases) over the viewport until `steps` events are sent; wait (bounded) for content to move. */
async function scroll(x:number,y:number,dy:number,steps:number,trackpad:boolean){
 if(trackpad)await h.scrollAt(x,y,0,0,{phase:'began'});
 for(let i=0;i<steps;i++)assert((await h.scrollAt(x,y,0,dy,trackpad?{phase:'changed'}:{})).ok);
 if(trackpad)await h.scrollAt(x,y,0,0,{phase:'ended'});
}
/** Content y once two reads 120 ms apart agree (wheel momentum / animation settled), within 5 s. */
async function settledY(id:string){
 let prior=NaN;
 return h.waitFor(async()=>{const y=await contentY(id);const ok=Math.abs(y-prior)<.5;prior=y;if(!ok)await h.sleep(120);return ok?y:null;},5000);
}
/** The native Select's dropdown (zenit Select has no panel test id): a shown PopoverContent listing saved hosts. */
async function selectPanelShown(){
 const t=await h.tree({visibleOnly:true});
 return flat(t).some(n=>n.component==='PopoverContent'&&flat(n).some(c=>typeof c.text==='string'&&c.text.startsWith('Fixture host ')));
}
const waitSelectOpen=()=>h.waitFor(async()=>await selectPanelShown()||null,5000).catch(()=>assert.fail('copy-source Select opens its option panel'));
const waitSelectClosed=()=>h.waitFor(async()=>!await selectPanelShown()||null,5000).catch(()=>assert.fail('copy-source Select closes its option panel'));
async function workload(label:string,viewportId:string,trackpad=false){
 const v=await h.screenPos(viewportId),x=v.x+v.w-16,y=v.y+v.h/2;
 assert(v.w>0&&v.h>0,`${label}: viewport has real geometry`);
 const start=await content(viewportId);
 assert(start.content.h>start.viewport.h+20,`${label}: content (${start.content.h}) overflows the viewport (${start.viewport.h})`);
 const before=await settledY(viewportId);await h.mouseMove(x,y);await h.resetTiming();
 await scroll(x,y,-28,36,trackpad);
 await h.waitFor(async()=>await contentY(viewportId)<before-20||null,5000).catch(async()=>assert.fail(`${label}: content must actually scroll (${before} → ${await contentY(viewportId)})`));
 const after=await settledY(viewportId);
 const down=await h.stats();assert(down.timing_samples>=20,`${label}: collect real frames`);
 assert.equal(down.paint_duplicate_fills,0,`${label}: background fill emitted once`);
 assert((await h.screenshot(join(out,label+'.png'))).ok);
 // Reverse immediately, including a full gesture boundary, then let motion settle.
 await scroll(x,y,28,36,trackpad);
 await h.waitFor(async()=>await contentY(viewportId)>after+20||null,5000).catch(async()=>assert.fail(`${label}: reverse wheel direction remains usable (${after} → ${await contentY(viewportId)})`));
 const returned=await settledY(viewportId);
 const s0=await h.stats();await h.sleep(1200);const s1=await h.stats(); // 1.2 s measuring window: idle frames after settling
 report.cases.push({label,before,after,returned,down,settled_frame_delta:s1.frame_count-s0.frame_count});console.log(label+' passed');
 return {before,after,returned,x,y};
}
/** The sidebar list is reachable end to end: shell = window height, list overflows, the last row and the bottom row show. */
async function sidebarReach(){
 const shell=await h.screenPos('workspace.shell'),side=await h.screenPos('workspace.sidebar');
 near(shell.h,900,'shell is exactly the window height (shell/styles.yss root: flex-basis 0, min-height 0)');
 near(bottom(side),bottom(shell),'sidebar ends at the window bottom');
 const bar=await visible('sidebar.bottom');
 assert(bar.rect.y>=0&&bottom(bar.rect)<=bottom(shell)+.5,`sidebar bottom row is inside the window: ${JSON.stringify(bar.rect)}`);
 const {viewport}=await content('sidebar.viewport');
 assert(bottom(viewport)<=bar.rect.y+.5,'the list viewport ends above the bottom row');
 const last=async()=>{const n=(await h.query('sidebar.host.name')).find((n:any)=>n.text===`Fixture host ${hostCount}`);assert(n,'last host row exists');return n.rect;};
 assert((await last()).y>=bottom(viewport),'the last host starts below the fold before scrolling');
 const first=await workload('sidebar-wheel','sidebar.viewport');
 // Scroll to the end: the last row lies fully inside the viewport; the bottom row has not moved.
 await scroll(first.x,first.y,-28,Math.ceil(hostCount*40/28),false);
 await h.waitFor(async()=>{const r=await last();return r.y>=viewport.y-.5&&bottom(r)<=bottom(viewport)+.5||null;},5000).catch(async()=>assert.fail(`last host row reachable: ${JSON.stringify(await last())} in ${JSON.stringify(viewport)}`));
 const end=await settledY('sidebar.viewport'),endContent=(await content('sidebar.viewport')).content;
 near(bottom(endContent),bottom(viewport),'scrolled to the end, the content bottom meets the viewport bottom');
 const barAfter=await visible('sidebar.bottom');near(barAfter.rect.y,bar.rect.y,'the bottom row does not scroll');
 assert((await h.screenshot(join(out,'sidebar-end.png'))).ok);
 report.sidebar={shell,sidebar:side,viewport,bottom_row:bar.rect,end_content:endContent,end_y:end,last_row:await last()};
}
try{
 await h.waitForServerReady(60000);await h.resizeWindow(1440,900);
 await h.waitFor(async()=>(await h.screenPos('workspace.shell')).h===900||null,5000);
 await visible('sidebar.host.name');
 for(let i=0;i<2;i++){
  // 侧栏“+”菜单已删（e1372d88）：改用标题栏的新建会话菜单做“弹层反复开合”。
  await click('toolbar.new_session');await visible('session.menu');
  if(i===1)assert((await h.screenshot(join(out,'session-menu.png'))).ok);
  await h.key('escape');await hidden('session.menu');
 }
 report.popup_reopen_passed=true;
 await sidebarReach();
 // Settings is its own window with its own size (resizing the main window does not touch it). Two-level settings
 // (settings_nav.ts): pick subpages whose content overflows that window — 外观与主题 › 主题 (themes, app icon, materials,
 // preview) and AI 辅助 › 行为与权限 (seven sections). `workload` asserts the overflow before scrolling.
 // (SSH › 连接 no longer overflows: five fields fit the settings viewport.)
 await nav.toSub('appearance','theme');await visible('settings.appearance.app_icon');
 report.settings_viewport=await h.screenPos('settings.viewport');
 await workload('settings-wheel','settings.viewport');
 await workload('settings-trackpad','settings.viewport',true);
 await nav.toSub('ai','behavior');await visible('settings.ai.permissions');
 await workload('settings-ai-behavior-wheel','settings.viewport');
 await nav.close();await click('toolbar.transfers');await visible('transfer.manager');
 await click('transfer.scope.select');await visible('transfer.scope.menu');
 assert((await h.query('transfer.scope.menu')).some((n:any)=>JSON.stringify(n).includes('全局')),'empty transfer registry offers the global scope');
 await h.key('escape');await hidden('transfer.scope.menu');await click('transfer.window.close');await hidden('transfer.manager');
 // Saved hosts populate the wizard's real copy-source Select. Transfer scopes
 // contain only sessions with tasks, so idle saved hosts cannot test its count.
 // Island B v3（e1372d88）：新建主机在侧栏底部（sidebar.footer.new），直接打开连接向导窗口。
 await click('sidebar.footer.new');await click('wizard.copy.open');
 await click('wizard.copy.source');await waitSelectOpen();
 assert((await h.key('end')).ok);assert((await h.key('return')).ok);
 await h.waitFor(async()=>(await h.query('wizard.copy.source')).some((n:any)=>JSON.stringify(n).includes(`Fixture host ${hostCount}`))||null,5000).catch(()=>assert.fail('keyboard End selects the final saved host'));
 await click('wizard.copy.source');await waitSelectOpen();
 assert((await h.screenshot(join(out,'large-select.png'))).ok);
 assert((await h.key('escape')).ok);await waitSelectClosed();await click('wizard.copy.apply');
 await h.waitFor(async()=>(await h.query('wizard.name')).some((n:any)=>JSON.stringify(n).includes(`Fixture host ${hostCount}`))||null,5000).catch(()=>assert.fail('copy action resolves the selected host identity'));
 await click('wizard.cancel');
 assert(!(await readFile(join(out,'app.log'),'utf8')).includes('TooManySelectOptions'),'large host registry does not fail rebuilding Select');
 report.large_select_passed=true;report.host_count=hostCount;
 report.status='passed';console.log(JSON.stringify(report.cases.map(({label,down,settled_frame_delta}:any)=>({label,cpu_p95_ms:down.cpu_p95_us/1000,gpu_p95_ms:down.gpu_p95_us/1000,samples:down.timing_samples,settled_frame_delta}))));
}catch(error){report.status='failed';report.error=String(error);await h.screenshot(join(out,'failure.png')).catch(()=>{});throw error;}
finally{
 if(app.exitCode===null&&app.signalCode===null)app.kill('SIGTERM');await ended;
 if(app.pid)await cleanupOwnedBridgeDirectories(app.pid);await log.close();await rm(iso,{recursive:true,force:true});
 await writeFile(join(out,'report.json'),JSON.stringify(report,null,2)+'\n');
}
