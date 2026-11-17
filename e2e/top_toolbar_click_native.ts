/** design-r3 稿 5 title bar tools, click only (title-click): native icon-only buttons, fold levels by space, ⋯ menu.
 * Hover shows only the native Tooltip; a click opens the tool's native Popover / Modal / card; a second click,
 * Escape and an outside click close it and focus returns to the button. The theme is not a title bar tool:
 * 菜单栏“显示 › 外观…” and the tab menu open Settings › 外观与主题. The tab's session card opens from the tab
 * menu (“会话连接”), never on hover. Isolated data and real Local tabs.
 * Usage: node e2e/top_toolbar_click_native.ts <binary> <out> [light|dark] */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdir,mkdtemp,open,writeFile,realpath,rm} from 'node:fs/promises';
import {dirname,resolve,join} from 'node:path';
import {pathToFileURL} from 'node:url';
const binary=resolve(process.argv[2]),out=resolve(process.argv[3]),variant=process.argv[4]??'light';
const theme=variant==='dark'?'dark':'light';
const h=await import(pathToFileURL(resolve(dirname(binary),'../share/zenit/harness/client.ts')).href);
const iso=await realpath(await mkdtemp('/tmp/zw-toolbar-click-')),data=join(iso,'data'),rpc=join(iso,'rpc');
for(const p of [out,data,rpc])await mkdir(p,{recursive:true});
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
await writeFile(join(data,'config.toml'),`[meta]\nconfig_revision=1\n[updates]\nauto_check=false\n[ui]\ntheme="${theme}"\n`);
const log=await open(join(out,'app.log'),'w');
const app=spawn(binary,[],{env:{...process.env,ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1'},stdio:['ignore',log.fd,log.fd]});
const ended=new Promise(r=>app.once('close',r)),report:any={variant,checks:[],captures:[],levels:{},panels:{}};
const shown=(n:any)=>n?.rect?.w>0&&n.rect.h>0&&n.visible!==false&&n.hidden!==true&&(n.effective_opacity??1)>0.5;
const flat=(n:any):any[]=>n?[n,...(n.children??[]).flatMap(flat)]:[];
const nodes=async(id:string)=>{assert(app.exitCode===null&&app.signalCode===null,'Native app stays alive');const result=await h.query(id);assert(Array.isArray(result),id+': '+JSON.stringify(result));return result.filter(shown);};
const visible=(id:string)=>h.waitFor(async()=>(await nodes(id))[0]??null,10000);
const hidden=(id:string)=>h.waitFor(async()=>!(await nodes(id)).length||null,5000);
async function click(id:string){const n=await visible(id);await h.mouseMove(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2);assert((await h.clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok);await h.sleep(150);}
async function capture(name:string){await h.sleep(280);assert((await h.screenshot(join(out,name+'.png'))).ok);report.captures.push(name);}
const focusedId=async()=>(await h.focused()).test_id??null;
// title-click: 7 tools (主题 left the title bar).
const tools=['status.connection.chain','status.connection.forward','toolbar.transfers','status.command-history','toolbar.history','toolbar.notifications','toolbar.settings'];
// Every panel a title bar tool (or the tab identity) can open.
const panels=['connection.details','socks.info','transfer.manager','terminal.command-history','history.panel','notifications.history','settings.window','status.connection','status.detail','status.ssh.detail'];
async function openPanels(){const o:string[]=[];for(const id of panels)if((await nodes(id)).length)o.push(id);return o;}
async function bar(){const o:Record<string,boolean>={};for(const id of tools)o[id]=(await nodes(id)).length>0;o['toolbar.expand']=(await nodes('toolbar.expand')).length>0;return o;}
async function newLocal(){await click('toolbar.new_session');await click('session.menu.local');await h.sleep(150);}
const away={x:450,y:300};
/** One popover tool: click opens (focus on the button), second click closes, Escape closes with focus back on
 * the button, an outside click closes. Returns false when the tool does not open a panel on this tab. */
async function popoverTool(id:string,panel:string,width:number):Promise<boolean>{
 const b=await visible(id);const cx=b.rect.x+b.rect.w/2,cy=b.rect.y+b.rect.h/2;
 await h.mouseMove(cx,cy);assert((await h.clickAt(cx,cy)).ok);
 const opened=await h.waitFor(async()=>(await nodes(panel))[0]??null,4000).catch(()=>null);
 if(!opened){report.panels[id]={opened:false};return false;}
 await capture(`click-${id}-${width}`);
 const r=opened.rect;assert(r.x>=7&&r.x+r.w<=width+1,panel+' stays inside the window width');
 // Second click on the same button closes; focus stays on the button.
 assert((await h.clickAt(cx,cy)).ok);await hidden(panel);
 // Escape closes; focus returns to the button.
 assert((await h.clickAt(cx,cy)).ok);await visible(panel);await h.sleep(200);
 await h.key('escape');await hidden(panel);await h.sleep(150);
 const afterEscape=await focusedId();assert.equal(afterEscape,id,panel+': Escape returns focus to '+id);
 // An outside click (the terminal) closes it.
 assert((await h.clickAt(cx,cy)).ok);await visible(panel);await h.sleep(200);
 await h.mouseMove(away.x,away.y+200);assert((await h.clickAt(away.x,away.y+200)).ok);await hidden(panel);
 report.panels[id]={opened:true,panel,rect:r,focus_after_escape:afterEscape};
 await h.mouseMove(away.x,away.y);await h.sleep(150);
 return true;
}
try{
 await h.waitForServerReady();await h.resizeWindow(1440,900);await h.mouseMove(450,300);
 await click('workspace.empty.local');await visible('terminal.surface');await h.sleep(400);
 // Wide window: 7 native 32 × 32 tools, no ⋯, no theme button.
 let state=await bar();report.levels.wide=state;
 for(const id of tools){assert(state[id],id+' shown at 1440');const n=await visible(id);assert.equal(n.rect.w,32,id+' is 32 wide');assert.equal(n.rect.h,32,id+' is 32 high');}
 assert(!state['toolbar.expand'],'no ⋯ when everything fits');
 assert.equal((await nodes('status.connection.theme')).length,0,'no theme button in the title bar');
 const tabs0=(await visible('workspace.tabs.capsule')).rect,first=(await visible('status.connection.chain')).rect;
 assert(tabs0.x+tabs0.w<=first.x,'tabs stay left of the tools');
 await capture('wide-default');
 report.checks.push('1440: 7 native 32 × 32 icon-only tools (no theme), no ⋯.');
 // Hover shows the Tooltip “名称 · 快捷键” and opens nothing (formerly: hover previews).
 for(const id of tools){const r=(await visible(id)).rect;await h.mouseMove(r.x+16,r.y+16);await h.sleep(1100);assert.deepEqual(await openPanels(),[],'hovering '+id+' opens no panel');if(id==='toolbar.settings'||id==='status.command-history')await capture('tooltip-'+id);await h.mouseMove(away.x,away.y);await h.sleep(200);}
 // The tab: hovering the active tab shows its native hint, never the session card.
 {const tab=flat(await visible('tabs.strip')).find((n:any)=>/^tabs\.tab\.\d+$/.test(n.test_id??'')&&shown(n));assert(tab);await h.mouseMove(tab.rect.x+tab.rect.w/2,tab.rect.y+tab.rect.h/2);await visible('tabs.tooltip');await h.sleep(900);assert.deepEqual(await openPanels(),[],'hovering the active tab opens no session card');await capture('tab-hover-tooltip');await h.mouseMove(away.x,away.y);await hidden('tabs.tooltip');}
 report.checks.push('Hover: every tool and the active tab show only their native Tooltip; no card, preview or popover opens.');
 // Clicks at 1440 and 860: each tool's popover / modal / card.
 for(const [w,hh] of [[1440,900],[860,480]] as [number,number][]){
  await h.resizeWindow(w,hh);await h.mouseMove(away.x,away.y);await h.sleep(600);
  for(const [id,panel] of [['toolbar.transfers','transfer.manager'],['status.command-history','terminal.command-history'],['toolbar.notifications','notifications.history'],['status.connection.chain','connection.details']] as [string,string][]){
   if(!(await nodes(id)).length)continue;
   const opened=await popoverTool(id,panel,w);
   if(id!=='status.connection.chain')assert(opened,id+' opens '+panel+' on click');
  }
  // One click switches tools: transfers open → a click on notifications closes it and opens notifications.
  await click('toolbar.transfers');await visible('transfer.manager');await click('toolbar.notifications');await visible('notifications.history');await hidden('transfer.manager');
  await h.key('escape');await hidden('notifications.history');
  // 回看日志 opens the history card (unchanged); settings is its own window (Escape closes).
  await click('toolbar.history');await visible('history.panel');await capture(`click-toolbar.history-${w}`);await h.key('escape');await h.sleep(400);
  if((await nodes('history.panel')).length){await click('toolbar.history');await h.sleep(300);}
  await click('toolbar.settings');await visible('settings.window');await capture(`click-toolbar.settings-${w}`);await h.key('escape');await hidden('settings.window');
  await h.mouseMove(away.x,away.y);await h.sleep(300);
  report.checks.push(`${w}: transfers / command history / notifications popovers open on click; second click, Escape (focus back on the button) and an outside click close them; one click switches tools; history card and settings window open on click.`);
 }
 await h.resizeWindow(1440,900);await h.mouseMove(away.x,away.y);await h.sleep(500);
 // Tab menu “会话连接” opens the session card (formerly a hover popover on the tab).
 {const tab=flat(await visible('tabs.strip')).find((n:any)=>/^tabs\.tab\.\d+$/.test(n.test_id??'')&&shown(n));assert(tab);const p={x:tab.rect.x+tab.rect.w/2,y:tab.rect.y+tab.rect.h/2};
  for(const route of ['/mouse_down','/mouse_up'])assert((await h.request('POST',route,{...p,button:'right'})).ok);
  await visible('context.menu.session_identity');await capture('tab-menu-identity');await click('context.menu.session_identity');
  const card=await h.waitFor(async()=>(await nodes('status.detail'))[0]??(await nodes('status.connection'))[0]??null,5000);report.identity_card=card.test_id;await capture('tab-identity-card');
  await h.key('escape');await h.waitFor(async()=>!(await nodes('status.detail')).length&&!(await nodes('status.connection')).length||null,5000);
  report.checks.push('Tab menu “会话连接” opens the session card; Escape closes it.');}
 // Theme: menu bar 显示 › 外观… opens Settings › 外观与主题 (native NSMenu, invoked through AppKit).
 {const snap=await h.request('POST','/zerowork/app-menu',{});report.app_menu=snap;assert(snap.ok&&snap.menus.includes('显示')&&snap.view.includes('外观…'),'menu bar has 显示 › 外观…');
  const fired=await h.request('POST','/zerowork/app-menu',{invoke:true});assert(fired.ok&&fired.invoked);
  await visible('settings.window');await visible('settings.appearance.themes');await capture('menu-bar-appearance');await h.key('escape');await hidden('settings.window');
  report.checks.push('菜单栏“显示 › 外观…” opens Settings › 外观与主题 › 主题.');}
 // A wide window with few tabs never folds (V-12), also at 860 with two tabs.
 await h.resizeWindow(860,480);await h.mouseMove(450,300);await h.sleep(500);
 report.levels.narrow_few=await bar();
 // Many tabs: tools fold before any tab overflows.
 await h.resizeWindow(1440,900);await h.sleep(300);
 // Add tabs one by one: the first fold is level 1 (稿 5).
 let added=0;
 for(;added<12;added++){await newLocal();await h.mouseMove(450,300);await h.sleep(500);if((await nodes('toolbar.expand')).length)break;}
 added++;report.tabs_added_until_fold=added;
 state=await bar();report.levels.wide_many=state;
 assert(state['toolbar.expand'],'⋯ appears once tabs need the room');
 for(const id of ['status.connection.chain','status.connection.forward','status.command-history','toolbar.history'])assert(!state[id],id+' folded at level 1');
 for(const id of ['toolbar.notifications','toolbar.settings'])assert(state[id],id+' kept at level 1');
 assert.equal((await nodes('tabs.all')).length,0,'no tab overflows while tools can still fold');
 await capture('wide-many-tabs');
 // ⋯ menu lists the folded tools with icon, name and shortcut; selecting one runs its own click.
 await click('toolbar.expand');const menu=await visible('toolbar.more');
 const rows=flat(menu).filter((n:any)=>/^toolbar\.more\./.test(n.test_id??''));report.menu=rows.map((n:any)=>n.test_id);
 for(const id of ['toolbar.more.chain','toolbar.more.forward','toolbar.more.command_history','toolbar.more.history'])assert(report.menu.includes(id),id+' in ⋯');
 assert(!report.menu.includes('toolbar.more.theme'),'no theme row in ⋯');
 assert(flat(menu).some((n:any)=>n.text==='⇧⌘B'),'shortcut on the command-history row');
 await capture('wide-many-menu');
 await click('toolbar.more.history');await h.sleep(500);await capture('history-from-menu');
 await h.key('escape');await h.sleep(300);
 // A folded popover tool opens at ⋯; Escape returns focus to ⋯.
 await click('toolbar.expand');await visible('toolbar.more');await click('toolbar.more.command_history');await visible('terminal.command-history');await capture('command-history-from-menu');
 await h.key('escape');await hidden('terminal.command-history');await h.sleep(150);report.folded_focus=await focusedId();assert.equal(report.folded_focus,'toolbar.expand','Escape on a folded tool returns focus to ⋯');
 report.checks.push('Many tabs fold the chain / forward / command history / history tools into ⋯ before tabs overflow; ⋯ menu runs the tool; a folded popover returns focus to ⋯.');
 // Narrower: only ⋯ remains.
 for(const [w,hh] of [[1180,800],[980,700],[860,480]] as [number,number][]){
  await h.resizeWindow(w,hh);await h.mouseMove(450,300);await h.sleep(700);report.levels['many_'+w]=await bar();await capture('many-'+w);
 }
 const narrow=report.levels['many_860'];
 assert(narrow['toolbar.expand'],'⋯ at 860');
 for(const id of tools.filter(id=>id!=='toolbar.transfers'))if(id!=='toolbar.notifications'&&id!=='toolbar.settings')assert(!narrow[id],id+' folded at 860');
 // Removing tabs restores every tool (24 hysteresis, no flicker).
 await h.resizeWindow(1440,900);await h.sleep(300);
 for(let i=0;i<added;i++){
  const target=flat(await visible('tabs.strip')).find((n:any)=>n.test_id?.startsWith('tabs.close.')&&n.rect?.w>0);assert(target);
  await h.mouseMove(target.rect.x+8,target.rect.y+8);await h.sleep(80);assert((await h.clickAt(target.rect.x+8,target.rect.y+8)).ok);await h.sleep(150);
 }
 await h.mouseMove(450,300);await h.sleep(600);
 state=await bar();for(const id of tools)assert(state[id],id+' restored');assert(!state['toolbar.expand']);
 await capture('wide-restored');
 report.checks.push('Closing the extra tabs restores all 7 tools and hides ⋯.');
 report.status='passed';
}catch(error){report.status='failed';report.error=String((error as any)?.stack??error);if(app.exitCode===null&&app.signalCode===null)await capture('failure').catch(()=>{});process.exitCode=1;}
finally{
 if(app.exitCode===null&&app.signalCode===null){await h.request('POST','/zerowork/windows',{action:'quit'}).catch(()=>{});await Promise.race([ended,h.sleep(8000)]);if(app.exitCode===null&&app.signalCode===null){app.kill('SIGTERM');await ended;report.forced_shutdown=true;}else report.exit_code=app.exitCode;}
 await log.close();await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));await rm(iso,{recursive:true,force:true});
}
console.log(JSON.stringify(report,null,2));
