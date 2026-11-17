/** Approved SVG → native workspace acceptance. Disposable data, Local PTYs and
 * an optional owned loopback SFTP peer; never opens saved user connections.
 *
 * Current contract (Island B v3, e1372d88; numbers from src/features/shell/view/shell/styles.yss unless noted):
 * - sidebar column 264 wide from the window top, full height; content column = 44pt view bar over the focused island,
 *   island margin right / bottom 6 (space150); the sidebar toggle sits after the traffic lights at (72, 14, 24 × 24)
 *   (sidebar_view.zig window_controls) and stays there as sidebar.restore while the sidebar is hidden (⌘B).
 * - island content: pane header 30, terminal padding [10, 16, 12, 16] (terminal_styles.zig contentPadding).
 * - floating ai.launcher 48 × 48, right 24 / bottom 20 inside the island (design-r2 14 AI 浮钮默认位置 ⇒ x + w − 72, y + h − 68).
 * - title bar tools: 7 native 32 × 32 icon buttons in 稿 5 order, no theme button (title-click d6c927e3).
 * - empty tab strip: only the native ghost sm “+”; tab close buttons appear on hover (zenit TabStrip, 4811ee5a).
 * - sidebar search is an always-visible field (sidebar.search, header toggle removed in e1372d88) with a clear button.
 * - SFTP file workspace: files root padding 4 / gap 4, column_stack flex-basis 0 ⇒ two equal cards (W − 2×4 − 4)/2
 *   (src/features/files/view/styles.yss).
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdir,mkdtemp,open,readFile,writeFile,realpath} from 'node:fs/promises';
import {dirname,resolve,join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {aiToggleId} from './ai_entry.ts';
import {chooseTheme,openAppearance} from './theme_settings_entry.ts';
const binary=resolve(process.argv[2]??'zig-out/bin/zerowork');
const out=resolve(process.argv[3]??'/tmp/zerowork-mist-acceptance');
const live=process.argv.includes('--live-transfer');
const h=await import(pathToFileURL(resolve(dirname(binary),'../share/zenit/harness/client.ts')).href);
const iso=await realpath(await mkdtemp('/tmp/zw-mist-')),data=join(iso,'data'),rpc=join(iso,'rpc');
for(const p of [out,data,rpc])await mkdir(p,{recursive:true});
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const log=await open(join(out,'app.log'),'w');
let app:any,ended:Promise<any>,peer:any,peerEnded:Promise<any>,ready:any,peerLog:any;
const report:any={binary,sha256:createHash('sha256').update(await readFile(binary)).digest('hex'),isolated:iso,checks:[],scenes:[],live_transfer:live,limits:['Native Metal captures exclude macOS traffic-light compositing.','Layout scenes use real Local PTYs; SVG remote output is design data.','No physical IME, live KVM or external SSH server acceptance.']};
// ---- design constants (see the header comment for their sources) ----
const SIDEBAR_W=264,VIEW_BAR_H=44,ISLAND_MARGIN=6,PANE_HEADER_H=30,TERM_PAD_TOP=10,TERM_PAD_LEFT=16,TOOL=32,FAB=48,FAB_RIGHT=72,FAB_BOTTOM=68,TOGGLE={x:72,y:14,w:24,h:24};
const shown=(n:any)=>n?.rect?.w>0&&n.rect.h>0&&n.visible!==false&&n.hidden!==true&&(n.effective_opacity??1)>0;
const flatten=(n:any):any[]=>n?[n,...(n.children??[]).flatMap(flatten)]:[];
const text=(n:any)=>flatten(n).filter(shown).map(n=>n.text??'').join(' ');
const near=(a:number,b:number,e=.5)=>Math.abs(a-b)<=e;
const nodes=async(id:string)=>(await h.query(id)).filter(shown);
const visible=(id:string,ms=15000)=>h.waitFor(async()=>{assert(app.exitCode===null&&app.signalCode===null,'Owned native App stays alive');return (await nodes(id))[0]??null},ms);
const hidden=(id:string)=>h.waitFor(async()=>!(await nodes(id)).length||null,6000);
async function clickNode(n:any,why:string){await h.mouseMove(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2);const result=await h.clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2);report.last_action={why,rect:n.rect,result};assert(result.ok,why+' clicks');}
async function click(id:string){await clickNode(await visible(id),id);}
async function capture(name:string){await h.sleep(160);assert((await h.screenshot(join(out,name+'.png'))).ok);const ids=['workspace.sidebar','sidebar.header','sidebar.collapse','sidebar.restore','sidebar.search.well','sidebar.footer.new','workspace.titlebar','workspace.tabs.capsule','tabs.strip','toolbar.tools','toolbar.expand','workspace.pane','pane.header','terminal.surface.viewport','terminal.surface.row.0','ai.launcher','ai.panel','settings.appearance.themes','status.detail'];const snapshot=Object.fromEntries(await Promise.all(ids.map(async id=>[id,await h.query(id)])));await writeFile(join(out,name+'.json'),JSON.stringify(snapshot,null,2));report.scenes.push(name);}
function rect(n:any,x:number,y:number,w:number,height:number,what:string){assert.deepEqual(n.rect,{x,y,w,h:height},what);}
/** Window laid out at `width` × `height` (time bounded): the title bar ends at the right edge, the island 6 above the bottom. */
async function windowSize(width:number,height:number){
 await h.resizeWindow(width,height);
 await h.waitFor(async()=>{const t=(await nodes('workspace.titlebar'))[0],p=(await nodes('workspace.pane'))[0];return t&&p&&near(t.rect.x+t.rect.w,width)&&near(p.rect.y+p.rect.h,height-ISLAND_MARGIN)||null;},10000);
}
/** The island and its floating launcher for a window `width` × `height` with the sidebar shown / hidden. */
async function checkShell(width:number,height:number,sidebarShown:boolean,what:string){
 const left=sidebarShown?SIDEBAR_W:0;
 if(sidebarShown)rect(await visible('workspace.sidebar'),0,0,SIDEBAR_W,height,what+': sidebar column');
 rect(await visible('workspace.titlebar'),left,0,width-left,VIEW_BAR_H,what+': view bar');
 const pane=await visible('workspace.pane');rect(pane,left,VIEW_BAR_H,width-left-ISLAND_MARGIN,height-VIEW_BAR_H-ISLAND_MARGIN,what+': island');
 rect(await visible('ai.launcher'),pane.rect.x+pane.rect.w-FAB_RIGHT,pane.rect.y+pane.rect.h-FAB_BOTTOM,FAB,FAB,what+': floating AI launcher');
 return pane;
}
// design-r3 稿 5: folded tools live in the ⋯ menu; `tool` clicks a visible one or picks it from ⋯.
const menuRow:Record<string,string>={'status.connection.chain':'toolbar.more.chain','status.connection.forward':'toolbar.more.forward','toolbar.transfers':'toolbar.more.transfers','status.command-history':'toolbar.more.command_history','toolbar.history':'toolbar.more.history','toolbar.notifications':'toolbar.more.notifications','toolbar.settings':'toolbar.more.settings'};
async function tool(id:string){if((await nodes(id)).length){await click(id);return;}await click('toolbar.expand');await click(menuRow[id]);}
const tabIds=async()=>flatten((await nodes('tabs.strip'))[0]).filter(n=>shown(n)&&/^tabs\.tab\.\d+$/.test(n.test_id??'')).map(n=>n.test_id as string);
async function newLocal(){const before=(await tabIds()).length;await click('toolbar.new_session');await click('session.menu.local');await h.waitFor(async()=>(await tabIds()).length===before+1||null,10000);await visible('terminal.surface');}
/** Close a tab from its hover close button (the close appears while the pointer is over that tab). */
async function closeTab(tabId:string){
 const tab=await visible(tabId);await h.mouseMove(tab.rect.x+tab.rect.w/2,tab.rect.y+tab.rect.h/2);
 const close=await visible(tabId.replace('tabs.tab.','tabs.close.'));
 assert(close.rect.x>=tab.rect.x-.5&&close.rect.x+close.rect.w<=tab.rect.x+tab.rect.w+.5&&close.rect.y>=tab.rect.y-.5&&close.rect.y+close.rect.h<=tab.rect.y+tab.rect.h+.5,'The close button lies inside its own tab');
 await clickNode(close,'close '+tabId);
 if((await h.waitFor(async()=>(await nodes('session.close.confirm')).length>0||!(await nodes(tabId)).length||null,6000))&&(await nodes('session.close.confirm')).length)await click('session.close.accept');
 await hidden(tabId);
}
/** Opens a file card's path Input: the breadcrumb's parts navigate, any other point of files.path.edit starts editing. */
async function goPath(side:'local'|'remote',path:string){
 const card=await visible('files.'+side),edit=flatten(card).find(n=>n.test_id==='files.path.edit'&&shown(n));assert(edit,'files.path.edit');
 const frame=flatten(edit).find(n=>n.test_id==='files.breadcrumb'&&shown(n))??edit,parts=flatten(edit).filter(n=>n.test_id==='files.path.part'&&shown(n)).sort((a,b)=>a.rect.x-b.rect.x);
 const xs:number[]=[],last=parts.at(-1);if(!last||last.rect.x+last.rect.w<edit.rect.x+edit.rect.w-12)xs.push(edit.rect.x+edit.rect.w-6);
 for(let i=1;i<parts.length;i++){const m=(parts[i-1].rect.x+parts[i-1].rect.w+parts[i].rect.x)/2;if(m>frame.rect.x+2&&m<frame.rect.x+frame.rect.w-2)xs.push(m);}
 assert(xs.length,'A non-part point of the path bar');assert((await h.clickAt(xs[0],edit.rect.y+edit.rect.h/2)).ok);
 const field=await h.waitFor(async()=>flatten((await nodes('files.'+side))[0]).find(n=>n.test_id==='files.path'&&shown(n))??null,10000);
 await clickNode(field,'focus the '+side+' path');await h.key('a',{cmd:true});await h.type_(path);await h.key('return');
}
try{
 if(live){
  peerLog=await open(join(out,'peer.log'),'w');
  // Audited interpreter only; -I keeps cwd / user site out of sys.path.
  assert(process.env.ZW_TEST_PYTHON,'ZW_TEST_PYTHON (audited Python with paramiko) is required');
  peer=spawn(process.env.ZW_TEST_PYTHON,['-I','e2e/sftp_v3_peer.py','--out',join(out,'peer')],{stdio:['ignore',peerLog.fd,peerLog.fd]});peerEnded=new Promise(r=>peer.once('close',r));
  ready=await h.waitFor(async()=>{assert(peer.exitCode===null&&peer.signalCode===null,'Owned peer stays alive');try{return JSON.parse(await readFile(join(out,'peer/ready.json'),'utf8'))}catch{return null}},15000);
 }
 let hosts='[registry]\nschema_version=2\nrevision=1\nnext_connection_id=4\nnext_group_id=3\n[[groups]]\ngroup_id=1\nrevision=1\nname="生产环境"\nordered_connection_ids=[1,2]\n[[groups]]\ngroup_id=2\nrevision=1\nname="开发环境"\nordered_connection_ids=[3]\n';
 for(const [i,name]of ['production-web','staging-api','开发工作站'].entries())hosts+=`[[hosts]]\nconnection_id=${i+1}\nrevision=1\nprotocol="${live&&i===0?'sftp':'ssh'}"\nauth_mode="password"\nname="${name}"\nhost="127.0.0.1"\nport=${live&&i===0?ready.port:65530+i}\nuser="${live&&i===0?ready.user:'fixture'}"\nasset_group_id=${i<2?1:2}\n${live&&i===0?`options={strict_host_key=true}\nauth={password="${ready.password}"}\n`:''}`;
 await writeFile(join(data,'hosts.toml'),hosts);
 if(ready?.known_host)await writeFile(join(data,'known_hosts'),ready.known_host);
 await writeFile(join(data,'config.toml'),'[meta]\nconfig_revision=1\n[ui]\ntheme="reference-light"\nfont_family="JetBrains Mono"\nfont_size=13\n[transfer]\ndedicated_connection=true\nwindow_chunks=1\nchunk_kb=32\nmax_tasks=1\nverify_md5=false\n');
 app=spawn(binary,[],{env:{...process.env,ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1'},stdio:['ignore',log.fd,log.fd]});ended=new Promise(r=>app.once('close',r));report.pid=app.pid;
 await h.waitForServerReady();await windowSize(1440,900);
 const emptyCapsule=await visible('workspace.tabs.capsule'),emptyPlus=await visible('toolbar.new_session');
 // design-r3 稿 3: with no tabs the strip is only the native ghost sm “+” (24 in the design; zenit's sm icon-only square measures 25.6).
 assert(Math.abs(emptyCapsule.rect.w-emptyPlus.rect.w)<0.5,JSON.stringify({capsule:emptyCapsule.rect,plus:emptyPlus.rect}));assert(emptyPlus.rect.w<=26&&emptyPlus.rect.w>=24);
 assert(Math.abs(emptyPlus.rect.x+emptyPlus.rect.w/2-(emptyCapsule.rect.x+emptyCapsule.rect.w/2))<0.5);
 const plusIcon=flatten(emptyPlus).find(n=>n.rect?.w===14&&n.rect?.h===14&&shown(n));assert(plusIcon);
 assert(Math.abs(plusIcon.rect.x+7-(emptyPlus.rect.x+emptyPlus.rect.w/2))<0.5);assert(Math.abs(plusIcon.rect.y+7-(emptyPlus.rect.y+emptyPlus.rect.h/2))<0.5);
 await capture('empty-tabs-centered');
 await h.mouseMove(emptyPlus.rect.x+14,emptyPlus.rect.y+14);await capture('empty-plus-hover');
 await h.mouseDown(emptyPlus.rect.x+14,emptyPlus.rect.y+14);await capture('empty-plus-pressed');
 await h.mouseUp(emptyPlus.rect.x+14,emptyPlus.rect.y+14);await visible('session.menu.local');await capture('empty-plus-after-click');
 await h.key('escape');await hidden('session.menu.local');await capture('empty-plus-after-dismiss');
 await h.mouseMove(500,300);await h.mouseMove(emptyPlus.rect.x+14,emptyPlus.rect.y+14);await capture('empty-plus-rehover');
 await h.mouseMove(500,300);
 const notificationTool=await visible('toolbar.notifications');
 await h.mouseMove(notificationTool.rect.x+14,notificationTool.rect.y+14);await capture('toolbar-notification-hover');
 await h.mouseDown(notificationTool.rect.x+14,notificationTool.rect.y+14);await capture('toolbar-notification-pressed');
 await h.mouseUp(notificationTool.rect.x+14,notificationTool.rect.y+14);await visible('notifications.history');await capture('toolbar-notification-after-click');
 await h.key('escape');await hidden('notifications.history');await capture('toolbar-notification-after-dismiss');
 await h.mouseMove(500,300);await h.mouseMove(notificationTool.rect.x+14,notificationTool.rect.y+14);await capture('toolbar-notification-rehover');
 await h.mouseMove(500,300);
 report.checks.push('Empty tab strip is just the native sm “+”; its 14×14 glyph is centered; “+” and 提醒 open and dismiss their native popups.');
 await click('workspace.empty.local');await visible('terminal.surface');
 const pane=await checkShell(1440,900,true,'1440×900');
 rect(await visible('sidebar.collapse'),TOGGLE.x,TOGGLE.y,TOGGLE.w,TOGGLE.h,'Sidebar toggle right after the traffic lights');
 {// 稿 5: 7 native 32 × 32 icon-only tools in one row, settings at the right edge (title-click: 主题 left the title bar).
  const ids=['status.connection.chain','status.connection.forward','toolbar.transfers','status.command-history','toolbar.history','toolbar.notifications','toolbar.settings'];
  assert.equal((await nodes('status.connection.theme')).length,0,'no theme button in the title bar');
  const buttons=await Promise.all(ids.map(id=>visible(id)));
  for(const button of buttons){assert.equal(button.rect.w,TOOL);assert.equal(button.rect.h,TOOL);assert(near(button.rect.y,buttons[0].rect.y),'tools share one row');}
  for(let j=1;j<buttons.length;j++)assert(buttons[j].rect.x>=buttons[j-1].rect.x+TOOL,'tools keep the 稿 5 order without overlapping');
  assert(near(buttons.at(-1).rect.x+TOOL,1440-ISLAND_MARGIN),'settings sits at the view bar end (padding right 6)');
  assert.equal((await nodes('toolbar.expand')).length,0,'no ⋯ when everything fits');
 }
 {// The terminal fills the island under its 30pt pane header with padding [10, 16, …].
  const surface=await visible('terminal.surface'),row=await visible('terminal.surface.row.0');
  assert.equal(surface.rect.y,pane.rect.y+PANE_HEADER_H,'terminal surface starts under the pane header');
  assert.equal(row.rect.y,surface.rect.y+TERM_PAD_TOP,'first row 10 below the surface top');assert.equal(row.rect.x,pane.rect.x+TERM_PAD_LEFT,'first row 16 from the island edge');
  assert.equal((await nodes('workspace.statusbar')).length,0,'no bottom status bar');
 }
 await click('terminal.surface');await h.type_("PS1='local:/srv/zerowork$ '; clear; printf '\\033[32mNative workspace ready\\033[0m\\nTop groups: connection / history / application\\nTerminal viewport: padding 16\\n'");await h.key('return');
 await h.waitFor(async()=>text((await nodes('terminal.surface.viewport'))[0]).includes('Native workspace ready')||null,10000);
 {const firstInk=flatten(await visible('terminal.surface.row.0')).find(n=>typeof n.text==='string'&&n.text.trim()&&shown(n));assert(firstInk,'the first row has ink');assert.equal(firstInk.rect.x,pane.rect.x+TERM_PAD_LEFT,'ink starts at the 16pt padding');}
 await h.mouseMove(850,450);await capture('wide');
 report.checks.push('1440×900: 264-point full-height sidebar from the window top, 44-point view bar, island inset 6 right / bottom, seven 32-point tools in order, terminal under the 30-point pane header at padding [10, 16], floating 48-point AI launcher at right 24 / bottom 20; no bottom bar.');
 // Five real Local tabs: the strip is content-fit inside the view bar, every tab's close appears on hover inside that tab and closes it.
 for(let i=0;i<4;i++)await newLocal();
 const tabs=await tabIds();assert.equal(tabs.length,5);
 const strip=await visible('tabs.strip'),capsule=await visible('workspace.tabs.capsule'),titlebar=await visible('workspace.titlebar'),tools=await visible('toolbar.tools');
 assert(near(capsule.rect.x,strip.rect.x)&&near(capsule.rect.w,strip.rect.w),'The capsule is the content-fit strip');
 assert(capsule.rect.x+capsule.rect.w<=tools.rect.x+.5&&capsule.rect.x>=titlebar.rect.x,'The strip stays between the view bar start and the tools');
 const plus=await visible('toolbar.new_session');assert(plus.rect.x>=flatten(strip).filter(n=>shown(n)&&/^tabs\.tab\.\d+$/.test(n.test_id??'')).reduce((m,n)=>Math.max(m,n.rect.x+n.rect.w),0)-.5,'“+” follows the last tab');
 await click('terminal.surface');await h.type_("PS1='local:/srv/zerowork$ '; clear; printf '\\033[32mLocal workspace ready\\033[0m\\n\\nWorking directory: /srv/zerowork\\n'");await h.key('return');await h.mouseMove(4,4);await capture('wide-five-tabs');
 await closeTab(tabs[0]);assert.equal((await tabIds()).length,4);
 while((await tabIds()).length>1){const inactive=(await tabIds())[0];await closeTab(inactive);}
 report.checks.push('Five real Local tabs: the strip is content-fit between the view bar start and the tools, each tab shows its close on hover inside the tab, inactive tabs close one by one.');
 // Sidebar search filters hosts, clear restores them.
 await click('sidebar.search');await h.type_('staging');await h.waitFor(async()=>(await nodes('sidebar.host')).length===1&&text((await nodes('sidebar.host'))[0]).includes('staging-api')||null,6000);
 await click('sidebar.search.clear');await h.waitFor(async()=>(await nodes('sidebar.host')).length===3||null,6000);
 assert.equal((await visible('sidebar.search')).text??'','','Clear empties the search field');await h.mouseMove(850,450);
 report.checks.push('Sidebar search filters hosts to the match, its clear button restores all hosts and empties the field.');
 // ⌘B hides the sidebar: the island takes the full width, the toggle stays in place as sidebar.restore and the tabs follow it.
 await h.key('b',{cmd:true});await hidden('workspace.sidebar');
 await h.waitFor(async()=>near((await visible('workspace.pane')).rect.x,0)||null,6000);
 await checkShell(1440,900,false,'sidebar hidden');
 {const restore=await visible('sidebar.restore');rect(restore,TOGGLE.x,TOGGLE.y,TOGGLE.w,TOGGLE.h,'The toggle keeps its place while the sidebar is hidden');assert((await visible('workspace.tabs.capsule')).rect.x>=restore.rect.x+restore.rect.w,'Tabs start after the restore toggle');}
 await h.mouseMove(4,4);await capture('wide-sidebar-hidden');await h.key('b',{cmd:true});await visible('workspace.sidebar');await h.waitFor(async()=>near((await visible('workspace.pane')).rect.x,SIDEBAR_W)||null,6000);
 // The session card opens from the tab menu “会话连接” (right-click the tab's identity anchor) and keeps the metrics of the removed bottom bar.
 {const t=await visible('local.status.identity');assert((await h.clickAt(t.rect.x+t.rect.w/2,t.rect.y+t.rect.h/2,1,'right')).ok);await click('context.menu.session_identity');}
 const detail=await visible('status.detail');assert(text(detail).includes('UTF-8'));assert(text(detail).includes('网格'));assert(detail.rect.y>=VIEW_BAR_H);await h.key('escape');await hidden('status.detail');await h.mouseMove(850,450);
 // The AI panel opens from the floating launcher and closes without moving the terminal island.
 const before=(await visible('workspace.pane')).rect;
 await click(await aiToggleId());await visible('ai.panel');await click('ai.close');await hidden('ai.panel');assert.deepEqual((await visible('workspace.pane')).rect,before);
 report.checks.push('⌘B hides / restores the sidebar with the toggle in place; the session card shows encoding / grid; the AI panel opens from the launcher and closes without moving the island.');
 await windowSize(860,480);await h.mouseMove(500,300);
 await checkShell(860,480,true,'860×480');await capture('compact');
 assert.equal((await nodes('settings.window')).length,0);
 // title-click: 主题 is 设置 › 外观与主题, opened from 菜单栏“显示 › 外观…”.
 const theme=await openAppearance(h);await h.mouseMove(theme.rect.x+60,theme.rect.y+90);await visible('settings.appearance.themes');await capture('compact-theme');await h.key('escape');await hidden('settings.window');await h.mouseMove(500,300);
 await tool('status.command-history');await visible('terminal.command-history');await capture('compact-command-history');await h.key('escape');await hidden('terminal.command-history');await h.mouseMove(500,300);
 report.checks.push('860×480: same shell geometry at the compact size; 设置 › 外观与主题 (显示 › 外观…) and the command-history panel open from their native entries.');
 await windowSize(1440,900);await h.mouseMove(850,450);
 const geometry=async()=>JSON.stringify(await Promise.all(['workspace.sidebar','workspace.titlebar','workspace.pane','tabs.strip','toolbar.tools','ai.launcher'].map(async id=>(await visible(id)).rect)));
 const beforeThemes=await geometry(),tabsBefore=await tabIds();
 const settingsClosed=async()=>((await readFile(join(out,'app.log'),'utf8')).match(/macos_window_close_complete\] window=<[^>]*> title=设置/g)??[]).length;
 const closedBefore=await settingsClosed();
 await chooseTheme(h,'dark',join(data,'config.toml'));await h.mouseMove(850,450);
 // Reopen only after the previous settings window has completed its close (AppKit close + 0.25 s retention, logged by the
 // runtime): reopening “显示 › 外观…” while it is still closing loses the next theme click (reported as a product race).
 await h.waitFor(async()=>await settingsClosed()>closedBefore||null,5000);
 await chooseTheme(h,'reference-light',join(data,'config.toml'));await h.mouseMove(850,450);
 assert.equal(await geometry(),beforeThemes,'Theme switches keep the native geometry');assert.deepEqual(await tabIds(),tabsBefore,'Theme switches keep the existing sessions');
 await capture('wide-final');await click('toolbar.history');await visible('history.panel');await h.key('escape');await hidden('history.panel');await click('toolbar.notifications');await visible('notifications.history');await h.key('escape');await hidden('notifications.history');
 report.checks.push('晴霜 is selectable as a separate built-in theme; switching Dark → 晴霜 preserves native node geometry and existing sessions.');
 if(live){
  // design-r3 A2 (fe28ab5b): a row click only selects; the selected row's native “连接” connects.
  const host=(await nodes('sidebar.host')).find(n=>text(n).includes('production-web'));assert(host);assert((await h.clickAt(host.rect.x+60,host.rect.y+host.rect.h/2)).ok);
  await clickNode(await h.waitFor(async()=>flatten((await h.query('sidebar.host')).find(n=>n.id===host.id)).find(n=>n.test_id==='sidebar.host.connect_button'&&shown(n))??null,10000),'connect production-web');
  await h.waitFor(async()=>{if((await nodes('files.workspace')).length)return true;const title=(await nodes('plugin.challenge.title'))[0],modal=(await nodes('plugin.challenge.modal'))[0];if(title&&modal&&(modal.effective_opacity??1)>=.999){if(text(title).includes('核对主机密钥')){assert(text(await visible('plugin.challenge.material')).includes(ready.fingerprint));await click('plugin.challenge.choice.0');}else if(text(title).includes('SSH 密码认证')){const field=(await nodes('plugin.challenge.answer.0'))[0]??await visible('plugin.challenge.secret');await clickNode(field,'password');await h.type_(ready.password);await click('plugin.challenge.submit');}else throw Error('Unexpected owned authentication challenge');}return null},30000);
  await hidden('connection.progress');
  const filePanes=async(width:number)=>{const ws=await visible('files.workspace'),p=await visible('workspace.pane');for(const k of ['x','y','w','h'])assert(near(ws.rect[k],p.rect[k]),'the file workspace is the island content: '+k);const half=(ws.rect.w-2*4-4)/2;
   const columns=[await visible('files.column.local'),await visible('files.column.remote')];
   rect(columns[0],ws.rect.x+4,ws.rect.y+4,half,ws.rect.h-8,width+': local column');rect(columns[1],ws.rect.x+4+half+4,ws.rect.y+4,half,ws.rect.h-8,width+': remote column');
   // Each column is its file card over an optional transfer tray (column_stack gap 4): the card fills the column when there is no tray.
   for(const [i,side] of ['local','remote'].entries()){const card=await visible('files.'+side),col=columns[i].rect,tray=flatten(columns[i]).find(n=>n.test_id==='transfer.session.tray'&&shown(n));
    assert(near(card.rect.x,col.x)&&near(card.rect.w,col.w)&&near(card.rect.y,col.y),width+': '+side+' card starts its column');
    if(tray){assert(near(tray.rect.y,card.rect.y+card.rect.h+4)&&near(tray.rect.y+tray.rect.h,col.y+col.h)&&near(tray.rect.x,col.x)&&near(tray.rect.w,col.w),width+': '+side+' tray sits 4 below its card and ends with the column');}
    else assert(near(card.rect.h,col.h),width+': '+side+' card fills its column');}};
  await filePanes(1440);
  await goPath('local',iso);await h.waitFor(async()=>text((await nodes('files.local'))[0]).includes('data')||null,10000);await h.mouseMove(4,4);await capture('files-aligned');
  const payload=Buffer.alloc(512*1024,37),path=join(iso,'mist-progress.bin');await writeFile(path,payload);
  const remote=await visible('files.remote'),x=remote.rect.x+remote.rect.w/2,y=remote.rect.y+remote.rect.h-65;await h.dragAt(x,y,0);await h.dragAt(x,y,3,'file://'+encodeURI(path));await visible('files.copy.confirmation');await click('files.copy.submit');await hidden('files.copy.confirmation');
  await visible('toolbar.transfers');await capture('real-transfer');await tool('toolbar.transfers');await visible('transfer.manager');await capture('real-transfer-manager');await h.key('escape');await hidden('transfer.manager');
  const state=await h.waitFor(async()=>{try{const s=JSON.parse(await readFile(join(out,'peer/state.json'),'utf8'));const f=s.files['/fixture/mist-progress.bin'];return f?.bytes===payload.length&&f.sha256===createHash('sha256').update(payload).digest('hex')?s:null}catch{return null}},60000);assert(state);
  report.checks.push('Real owned loopback SFTP upload, the same global manager opens, destination SHA-256 matches all 512 KiB.');
  await windowSize(860,480);await h.mouseMove(500,300);await filePanes(860);await capture('files-compact');
  report.checks.push('File cards split the island into two equal halves inside its 4-point padding at 1440 and 860.');
 }
 report.ok=true;
}catch(error){report.ok=false;report.error=String(error);if(app)await capture('failure').catch(()=>{});await readFile(join(data,'config.toml'),'utf8').then(c=>writeFile(join(out,'failure-config.toml'),c)).catch(()=>{});throw error;}
finally{
 if(app&&app.exitCode===null&&app.signalCode===null){try{report.quit=await h.request('POST','/zerowork/windows',{action:'quit'});await Promise.race([ended!,h.sleep(10000)]);}catch{}if(app.exitCode===null&&app.signalCode===null){report.forced_shutdown=true;app.kill('SIGTERM');await ended!;}else report.exit_code=app.exitCode;}
 if(peer){peer.kill('SIGTERM');await peerEnded!;}
 if(peerLog)await peerLog.close();
 await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));await log.close();
}
console.log(JSON.stringify(report,null,2));
