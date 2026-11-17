/**
 * Window chrome of every production native window (usage-b3-titlebar): main window, Settings
 * window, connection wizard window.
 *
 * The windows use zenit's window chrome (`WindowConfig.chrome = .custom`): a native mouseDown drags
 * the window exactly where `Cx.windowRegionAt` answers `.drag` (native traffic lights excepted).
 * The test-mode route `/zerowork/window-chrome` returns that answer for a grid over the window and
 * can send native events / requests to it. Per theme this script runs two phases.
 *
 * Phase 1, regions (harness pointer isolated, as every other e2e): per window
 *   - the chrome mode (custom, native controls) and the traffic-light geometry;
 *   - the semantic points: empty title-bar space drags, title-bar buttons / tabs / inputs / content
 *     do not, nothing below the title bar drags;
 *   - the drag map (`<theme>-<window>.map.txt`) and a screenshot;
 *   - sidebar hidden (⌘B): the view bar around the traffic lights is still a drag region;
 *   - with the main window and the Settings window both open, switch the theme in Settings: both
 *     windows repaint and keep their drag regions (skip with `--no-theme-switch`).
 *
 * Phase 2, native path (`--no-native` skips it; the app runs in the foreground for it): real NSEvents posted to the app's own queue and
 * routed by the real event pump (zenit test entry; no global event, the physical pointer is not
 * moved), so the title-bar policy itself is exercised:
 *   - a press on empty title-bar space is claimed by the title bar (a window drag starts) and is
 *     not delivered to the UI; a press on a title-bar button / navigation row is delivered (the
 *     button acts) and not claimed — main window, Settings window, wizard window;
 *   - a double click on empty title-bar space zooms the window and a second one restores the exact
 *     frame (main, Settings); the wizard window is not maximizable: claimed, frame unchanged;
 *   - native fullscreen (main window; `--no-fullscreen` skips it): chrome state reports fullscreen,
 *     the traffic lights leave the client header, the hidden-sidebar view bar drops their inset,
 *     title-bar presses are no longer claimed (no drag / zoom in fullscreen) while buttons still
 *     act; leaving fullscreen restores the frame, the lights and the drag behaviour.
 * What it cannot show: the window following the pointer during a drag. The window server moves a
 * window inside `performWindowDragWithEvent:` only while a physical button is held; that needs a
 * global HID event (moves the user's real pointer, needs Accessibility permission).
 *
 * Usage: node e2e/window_chrome_regions_native.ts <zerowork binary (test-mode)> <evidence dir> [light|dark|both]
 *        [--hosts] (one saved host: sidebar header / search / list instead of the empty guide)
 *        [--no-theme-switch] [--no-native] [--no-fullscreen]
 * No network access is needed.
 */
// @ts-ignore -- plain ESM helper
import {assertTestModeBinary} from './regression/build_mode_guard.mjs';
import assert from 'node:assert/strict';
import {chmod,mkdtemp,readFile,realpath,writeFile,rm,mkdir} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import * as h from '../vendor/zenit/e2e/client.ts';
import {launchIsolated,settingsNav,shown} from './settings_nav.ts';
import {inflateSync} from 'node:zlib';

const [binaryArg,outArg,which='both',...flags]=process.argv.slice(2);
if(!binaryArg||!outArg)throw new Error('usage: window_chrome_regions_native.ts <binary> <out> [light|dark|both] [--hosts] [--no-theme-switch] [--no-native] [--no-fullscreen]');
const binary=assertTestModeBinary(resolve(binaryArg)),out=resolve(outArg);await mkdir(out,{recursive:true});
const themes=which==='both'?['light','dark']:[which];
const STEP=4,withHosts=flags.includes('--hosts');

type Rect={x:number,y:number,w:number,h:number};
type Probe={ok:boolean,active:boolean,width:number,height:number,requested_mode:string,effective_mode:string,controls_owner:string,fullscreen:boolean,fullscreen_transitioning:boolean,maximized:boolean,titlebar_presses:number,frame:number[],step:number,cols:number,rows:number,native_controls:Rect[],region:string};
const node=async(id:string,ms=15000):Promise<any>=>h.waitFor(async()=>(await h.query(id)).find(shown)??null,ms);
const click=async(id:string)=>{const n=await node(id);assert((await h.clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok,id);};
const centre=(r:Rect)=>({x:r.x+r.w/2,y:r.y+r.h/2});
/** `window` is a harness window token; the route addresses the native window id behind it. */
const probe=async(window:string):Promise<Probe>=>{const native=(await h.windows()).windows.find(w=>w.window_id===window)?.native_id;assert(native,`window ${window} is gone`);const p=await h.request('POST','/zerowork/window-chrome',{window:Number(native),step:STEP});assert(p?.ok,`window-chrome probe ${window}: ${JSON.stringify(p).slice(0,200)}`);return p;};
const cell=(p:Probe,x:number,y:number)=>Math.min(p.rows-1,Math.max(0,Math.floor(y/p.step)))*p.cols+Math.min(p.cols-1,Math.max(0,Math.floor(x/p.step)));
const inNative=(p:Probe,x:number,y:number)=>p.native_controls.some(r=>x>=r.x&&x<r.x+r.w&&y>=r.y&&y<r.y+r.h);
/** Does a native mouseDown at (x, y) drag the window under the chrome hit callback? */
const drags=(p:Probe,x:number,y:number)=>p.region[cell(p,x,y)]==='d'&&!inNative(p,x,y);
function summarize(p:Probe){
 let drag=0;const b={x0:Infinity,y0:Infinity,x1:-Infinity,y1:-Infinity},lines:string[]=[];
 for(let r=0;r<p.rows;r++){let line='';for(let c=0;c<p.cols;c++){const x=(c+.5)*p.step,y=(r+.5)*p.step,n=drags(p,x,y);
   if(n){drag++;b.x0=Math.min(b.x0,x);b.y0=Math.min(b.y0,y);b.x1=Math.max(b.x1,x);b.y1=Math.max(b.y1,y);}
   line+=n?'#':inNative(p,x,y)?'o':'.';}lines.push(line);}
 return {drag_cells:drag,drag_bounds:drag?b:null,map:lines.join('\n')};
}
/** Native request to one window (see the route): returns once the route answered. */
const native=async(window:string,body:Record<string,unknown>)=>{const id=(await h.windows()).windows.find(w=>w.window_id===window)?.native_id;assert(id,`window ${window} is gone`);const r=await h.request('POST','/zerowork/window-chrome',{window:Number(id),...body});assert(r?.ok,`${JSON.stringify(body)}: ${JSON.stringify(r)}`);};
/** Chrome state without the grid (one cell). */
const stateOf=async(window:string):Promise<Probe>=>{const id=(await h.windows()).windows.find(w=>w.window_id===window)?.native_id;assert(id,`window ${window} is gone`);const p=await h.request('POST','/zerowork/window-chrome',{window:Number(id),step:4096});assert(p?.ok);return p;};
const sameFrame=(a:number[],b:number[])=>a.every((v,i)=>Math.abs(v-b[i])<0.5);

const reports:any[]=[];
for(const [index,theme] of themes.entries()){
 // --hosts: one saved host, so the sidebar shows its header, search field and list instead of the empty guide.
 const seeded=withHosts?await realpath(await mkdtemp('/private/tmp/zw-chrome-regions-data-')):null;
 if(seeded){await chmod(seeded,0o700);
  await writeFile(join(seeded,'config.toml'),`[meta]\nconfig_revision=1\n[updates]\nauto_check=false\n[ui]\ntheme="${theme}"\n`,{mode:0o600});
  await writeFile(join(seeded,'hosts.toml'),'[registry]\nschema_version=2\nrevision=1\nnext_connection_id=2\nnext_group_id=1\n[[hosts]]\nconnection_id=1\nrevision=1\nprotocol="ssh"\nauth_mode="agent"\nname="Chrome region host"\nhost="127.0.0.1"\nport=1\nuser="review"\n',{mode:0o600});}
 const run=await launchIsolated({binary,out,prefix:'zw-chrome-regions',theme,logName:`${theme}-app.log`,env:{ZDOTDIR:'',...(seeded?{ZEROWORK_DATA_DIR:seeded}:{})}});
 const report:any={theme,status:'running',checks:[] as string[],windows:{} as Record<string,any>,shots:{} as Record<string,any>};
 const check=(ok:any,text:string)=>{assert(ok,`${theme}: ${text}`);report.checks.push(text);};
 const shot=async(name:string,win?:string)=>{await h.mouseMove(2,2).catch(()=>{});await h.sleep(300);const path=join(out,`${theme}-${name}.png`);assert((await h.screenshot(path,win)).ok,`screenshot ${name}`);const stats=pixelStats(await readFile(path));report.shots[name]={path,variance:stats.variance,distinct:stats.distinct,mean:stats.mean};assert(stats.variance>=20&&stats.distinct>=64,`${theme} ${name}: flat screenshot`);return stats;};
 /** Probe one window, record its map, and check the chrome state shared by every production window. */
 const inspect=async(name:string,win:string,lights:{x:number,y:number,d:number})=>{
  const p=await probe(win),s=summarize(p);
  await writeFile(join(out,`${theme}-${name}.map.txt`),`# ${name} ${p.width}x${p.height}, step ${p.step}: # drags the window, o native control, . client\n${s.map}\n`);
  report.windows[name]={width:p.width,height:p.height,requested_mode:p.requested_mode,effective_mode:p.effective_mode,controls_owner:p.controls_owner,native_controls:p.native_controls,drag_cells:s.drag_cells,drag_bounds:s.drag_bounds};
  check(p.requested_mode==='custom'&&p.effective_mode==='custom'&&p.controls_owner==='native',`${name}: chrome custom, native controls (${p.requested_mode}/${p.effective_mode}/${p.controls_owner})`);
  check(p.native_controls.length===3,`${name}: three native traffic lights reported`);
  const first=[...p.native_controls].sort((a,b)=>a.x-b.x)[0],c=centre(first);
  check(Math.abs(c.x-lights.x)<=1&&Math.abs(c.y-lights.y)<=1&&Math.abs(first.w-lights.d)<=1,`${name}: close button centre (${c.x},${c.y}) ⌀${first.w} = layout (${lights.x},${lights.y}) ⌀${lights.d}`);
  for(const r of p.native_controls){const q=centre(r);check(!drags(p,q.x,q.y),`${name}: native control at (${q.x},${q.y}) is not a drag point`);}
  return p;
 };
 const expectDrag=(p:Probe,name:string,what:string,x:number,y:number,want:boolean)=>check(drags(p,x,y)===want,`${name}: ${what} (${Math.round(x)},${Math.round(y)}) ${want?'drags the window':'does not drag'}`);
 const below=(p:Probe,fromY:number)=>{let n=0;for(let r=0;r<p.rows;r++)for(let c=0;c<p.cols;c++){const x=(c+.5)*p.step,y=(r+.5)*p.step;if(y>=fromY&&drags(p,x,y))n++;}return n;};
 try{
  await h.resizeWindow(1440,900);
  for(const id of ['workspace.sidebar','workspace.titlebar','workspace.empty.local','toolbar.settings'])await node(id);
  const main=(await h.windows()).windows.find(w=>w.bound&&!w.closing)!.window_id;
  await click('workspace.empty.local');await node('tabs.title');await node('terminal.surface');await h.sleep(600);
  // ── main window ──
  {
   const TITLE=44,p=await inspect('main',main,{x:20,y:26,d:12});
   const bar=(await node('workspace.titlebar')).rect,tab=(await node('tabs.title')).rect,settings=(await node('toolbar.settings')).rect,terminal=(await node('terminal.surface')).rect,side=(await node('workspace.sidebar')).rect;
   const add=(await h.query('toolbar.new_session')).find(shown)?.rect;
   // Empty view-bar space: between the tab strip and the tool group.
   const gapX=((add?add.x+add.w:tab.x+tab.w)+(await toolsLeft()))/2;
   expectDrag(p,'main','empty view bar between tabs and tools',gapX,bar.y+bar.h/2,true);
   expectDrag(p,'main','tab title',tab.x+tab.w/2,tab.y+tab.h/2,false);
   expectDrag(p,'main','settings tool button',settings.x+settings.w/2,settings.y+settings.h/2,false);
   for(const id of ['toolbar.history','toolbar.transfers','toolbar.notifications']){const n=(await h.query(id)).find(shown);if(n)expectDrag(p,'main',id,n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2,false);}
   expectDrag(p,'main','terminal',terminal.x+terminal.w/2,terminal.y+terminal.h/2,false);
   expectDrag(p,'main','sidebar header right of the traffic lights',side.x+side.w-60,8,true);
   if(withHosts){
    const head=(await node('sidebar.header')).rect,search=(await node('sidebar.search')).rect,host=(await node('sidebar.host')).rect,collapse=(await node('sidebar.collapse')).rect;
    expectDrag(p,'main','sidebar header blank space',head.x+head.w-12,head.y+head.h/2,true);
    expectDrag(p,'main','sidebar collapse button',collapse.x+collapse.w/2,collapse.y+collapse.h/2,false);
    expectDrag(p,'main','sidebar search field',search.x+search.w/2,search.y+search.h/2,false);
    expectDrag(p,'main','sidebar host row',host.x+host.w/2,host.y+host.h/2,false);
   }
   check(below(p,TITLE+STEP)===0,`main: no drag point below the ${TITLE}pt title bar`);
   await shot('main',main);
   // Sidebar hidden (⌘B): the traffic lights sit in the view bar start, which stays a drag region around them.
   await h.key('b',{cmd:true});await h.waitFor(async()=>((await h.query('workspace.sidebar')).find(shown)?.rect?.w??0)<1||null,8000);await h.sleep(500);
   {const q=await probe(main),b=(await node('workspace.titlebar')).rect,l=[...q.native_controls].sort((a,c)=>c.x-a.x)[0];
    check(q.native_controls.length===3,'main, sidebar hidden: three native traffic lights');
    expectDrag(q,'main, sidebar hidden','view bar left edge beside the traffic lights',l.x+l.w+3,3,true);
    expectDrag(q,'main, sidebar hidden','empty view bar',gapX,b.y+b.h/2,true);
    expectDrag(q,'main, sidebar hidden','settings tool button',settings.x+settings.w/2,settings.y+settings.h/2,false);
    check(below(q,TITLE+STEP)===0,'main, sidebar hidden: no drag point below the title bar');}
   await h.key('b',{cmd:true});await h.waitFor(async()=>((await h.query('workspace.sidebar')).find(shown)?.rect?.w??0)>200||null,8000);await h.sleep(500);
  }
  // ── Settings window ──
  await click('toolbar.settings');await node('settings.panel');await node('settings.page.title');
  const settingsWin=await h.waitFor(async()=>(await h.windows()).windows.find(w=>!w.closing&&w.window_id!==main)?.window_id??null,10000);
  await h.sleep(600);
  const inspectSettings=async(tag:string)=>{
   const p=await inspect(tag,settingsWin,{x:28,y:32,d:12});
   const intro=(await node('settings.page.intro')).rect,back=(await node('settings.history.back')).rect,title=(await node('settings.page.title')).rect,search=(await node('settings.search')).rect,head=(await node('settings.header')).rect,nav=(await node('settings.nav.appearance')).rect,view=(await node('settings.viewport')).rect;
   expectDrag(p,tag,'navigation top row right of the traffic lights',head.x+head.w-20,head.y+head.h/2,true);
   expectDrag(p,tag,'window top edge above the navigation',head.x+head.w-20,3,true);
   expectDrag(p,tag,'page header blank space',intro.x+intro.w*0.7,intro.y+intro.h/2,true);
   expectDrag(p,tag,'page title text',title.x+title.w/2,title.y+title.h/2,true);
   expectDrag(p,tag,'history back button',back.x+back.w/2,back.y+back.h/2,false);
   expectDrag(p,tag,'search field',search.x+search.w/2,search.y+search.h/2,false);
   expectDrag(p,tag,'navigation row',nav.x+nav.w/2,nav.y+nav.h/2,false);
   expectDrag(p,tag,'page content',view.x+view.w/2,view.y+view.h*0.6,false);
   check(below(p,intro.y+intro.h+STEP)===0,`${tag}: no drag point below the page header`);
   return p;
  };
  await inspectSettings('settings');await shot('settings',settingsWin);
  // ── double-window theme switch ──
  if(index===0&&!flags.includes('--no-theme-switch')){
   const other=theme==='dark'?'light':'dark',nav=settingsNav({timeout:15000});
   const before={main:await shot('switch-before-main',main),settings:await shot('switch-before-settings',settingsWin)};
   await nav.pickTheme(other);await nav.saveIfDirty();await h.sleep(900);
   const after={main:await shot('switch-after-main',main),settings:await shot('switch-after-settings',settingsWin)};
   for(const w of ['main','settings'] as const)check(Math.abs(after[w].mean-before[w].mean)>20,`theme switch ${theme}→${other}: ${w} window repainted (mean luminance ${before[w].mean.toFixed(1)} → ${after[w].mean.toFixed(1)})`);
   await inspectSettings('settings-after-switch');
   const p=await probe(main),bar=(await h.query('workspace.titlebar')).find(shown)?.rect;
   // The harness is bound to the Settings window; the main window's map is addressed by window id.
   check(p.region.includes('d'),'theme switch: main window keeps its drag region');report.windows['main-after-switch']={bar,drag_cells:summarize(p).drag_cells};
   await nav.pickTheme(theme);await nav.saveIfDirty();await h.sleep(600);
  }
  await h.key('w',{cmd:true});await h.waitFor(async()=>(await h.query('settings.panel')).some(shown)?null:true,8000);await h.sleep(400);
  await h.waitFor(async()=>(await h.query('toolbar.settings')).some(shown)||null,8000);
  // ── connection wizard window ──
  await click((await h.query('sidebar.empty.new')).some(shown)?'sidebar.empty.new':'sidebar.footer.new');await node('wizard.title');
  const wizardWin=await h.waitFor(async()=>(await h.windows()).windows.find(w=>!w.closing&&w.window_id!==main)?.window_id??null,10000);
  await h.sleep(600);
  {
   const TITLE=44,p=await inspect('wizard',wizardWin,{x:20,y:22,d:12});
   const title=(await node('wizard.title')).rect,name=(await node('wizard.name')).rect;
   expectDrag(p,'wizard','title bar blank space',p.width-40,22,true);
   expectDrag(p,'wizard','title text',title.x+title.w/2,title.y+title.h/2,true);
   expectDrag(p,'wizard','name field',name.x+name.w/2,name.y+name.h/2,false);
   check(below(p,TITLE+STEP)===0,`wizard: no drag point below the ${TITLE}pt title bar`);
   await shot('wizard',wizardWin);
  }
  await run.stop();
  if(!flags.includes('--no-native'))await nativePhase(theme,index,report,check);
  report.status='passed';
 }catch(e){report.status='failed';report.error=String((e as any)?.stack??e);process.exitCode=1;}
 finally{await run.stop();await rm(run.iso,{recursive:true,force:true});if(seeded)await rm(seeded,{recursive:true,force:true});reports.push(report);}
}
await writeFile(join(out,'report.json'),JSON.stringify({status:reports.length&&reports.every(r=>r.status==='passed')?'passed':'failed',themes:reports},null,2));
console.log(JSON.stringify(reports.map(r=>({theme:r.theme,status:r.status,checks:r.checks.length,windows:Object.fromEntries(Object.entries(r.windows).map(([k,v]:any)=>[k,v.drag_cells??v])),error:r.error}))));

/** Phase 2: native events through the real pump (see the header). Its own app, in the foreground: AppKit only delivers
 *  a press to the content view of a key window (a background e2e app is an accessory that never becomes key), and OS pointer
 *  events must reach the UI. The physical keyboard is isolated so a person typing elsewhere cannot type into it. */
async function nativePhase(theme:string,index:number,report:any,check:(ok:any,text:string)=>void){
 const run=await launchIsolated({binary,out,prefix:'zw-chrome-native',theme,logName:`${theme}-native-app.log`,env:{ZDOTDIR:'',ZENIT_E2E_BACKGROUND:'0',ZENIT_E2E_ISOLATE_POINTER:'0',ZENIT_E2E_ISOLATE_KEYBOARD:'1',...(process.env.ZW_CHROME_DEBUG?{ZENIT_DEBUG_MOUSEEV:'1'}:{})}});
 const settle=async(win:string,ms=6000)=>{let last:number[]=[];return h.waitFor(async()=>{const p=await stateOf(win);const same=last.length&&sameFrame(last,p.frame)&&!p.fullscreen_transitioning;last=p.frame;return same?p:null;},ms,150);};
 // AppKit delivers a press to the content view only in the active (key) window of the active application. Someone
 // using the machine can take activation away at any moment, so every native press first makes sure the window is
 // the active one (re-activating if needed) — the same precondition a person's click on it would establish.
 const ensureActive=async(win:string)=>h.waitFor(async()=>{if((await stateOf(win)).active)return true;await native(win,{action:'activate'});await h.sleep(250);return (await stateOf(win)).active||null;},10000,100);
 const click=async(win:string,x:number,y:number,count=1)=>{await ensureActive(win);await native(win,{action:'native_click',x,y,count});};
 /** A press the title bar must claim: the claim counter advances, the UI sees nothing. */
 const claimed=async(win:string,name:string,x:number,y:number)=>{const before=(await stateOf(win)).titlebar_presses;await click(win,x,y);const after=await h.waitFor(async()=>{const p=await stateOf(win);return p.titlebar_presses>before?p:null;},5000).catch(()=>null);check(after&&after.titlebar_presses===before+1,`native press on ${name} (${Math.round(x)},${Math.round(y)}) is claimed by the title bar (a window drag starts)`);};
 /** A press that must reach the UI: `acted` becomes true, the claim counter does not move. */
 const delivered=async(win:string,name:string,x:number,y:number,acted:()=>Promise<any>)=>{const before=(await stateOf(win)).titlebar_presses;await click(win,x,y);check(await h.waitFor(acted,8000).catch(()=>null),`native press on ${name} (${Math.round(x)},${Math.round(y)}) reaches the control (it acts)`);check((await stateOf(win)).titlebar_presses===before,`native press on ${name} is not claimed by the title bar`);};
 /** A double click on empty title-bar space: zoom, then restore the exact frame. */
 const zoomAndRestore=async(win:string,name:string,x:number,y:number)=>{
  const original=(await settle(win)).frame;
  await click(win,x,y,2);const zoomed=await h.waitFor(async()=>{const p=await stateOf(win);return p.maximized&&!sameFrame(p.frame,original)?p:null;},8000).catch(()=>null);
  check(zoomed,`${name}: native double click on empty title-bar space zooms the window (frame ${JSON.stringify(original)} → ${JSON.stringify(zoomed?.frame)})`);
  await settle(win);
  // The window is larger now: address the same title-bar point again through fresh geometry.
  await click(win,x,y,2);const restored=await h.waitFor(async()=>{const p=await stateOf(win);return sameFrame(p.frame,original)?p:null;},8000).catch(()=>null);
  check(restored&&!restored.maximized,`${name}: a second double click restores the exact frame`);await settle(win);
 };
 try{
  await h.resizeWindow(1200,760);
  for(const id of ['workspace.titlebar','workspace.empty.local','toolbar.settings'])await node(id);
  const main=(await h.windows()).windows.find(w=>w.bound&&!w.closing)!.window_id;
  await click0('workspace.empty.local');await node('tabs.title');await h.sleep(500);
  const blank=async()=>{const bar=(await node('workspace.titlebar')).rect,tab=(await node('tabs.title')).rect,add=(await h.query('toolbar.new_session')).find(shown)?.rect;return {x:((add?add.x+add.w:tab.x+tab.w)+(await toolsLeft()))/2,y:bar.y+bar.h-8};};
  // ── main window: claim vs delivery ──
  {const b=await blank(),start=(await settle(main)).frame;
   await claimed(main,'main: empty view bar',b.x,b.y);
   check(sameFrame((await settle(main)).frame,start),'main: the window did not move (no physical button is held; the drag was started, nothing dragged it)');
   check(!(await h.query('settings.panel')).some(shown)&&(await h.query('tabs.title')).filter(shown).length===1,'main: the claimed press changed nothing in the UI');
   const side=(await node('workspace.sidebar')).rect;await claimed(main,'main: sidebar title band',side.x+side.w-60,30);
   const tabs0=(await h.query('tabs.title')).filter(shown).length,add=(await node('toolbar.new_session')).rect;
   await delivered(main,'main: new-tab button in the tab strip',add.x+add.w/2,add.y+add.h/2,async()=>(await h.query('session.menu.new_profile')).some(shown)||(await h.query('tabs.title')).filter(shown).length>tabs0||null);
   await h.key('escape');await h.sleep(300);
  }
  // ── main window: double click zooms / restores ──
  {const b=await blank();await zoomAndRestore(main,'main',b.x,b.y);}
  // ── fullscreen (main window) ──
  if(index===0&&!flags.includes('--no-fullscreen')){
   const windowed=await settle(main);
   await h.key('b',{cmd:true});await h.waitFor(async()=>((await h.query('workspace.sidebar')).find(shown)?.rect?.w??0)<1||null,8000);await h.sleep(400);
   const restoreWindowed=(await node('sidebar.restore')).rect;
   check(restoreWindowed.x>=72,`windowed, sidebar hidden: the restore button sits after the traffic lights (x ${restoreWindowed.x})`);
   await native(main,{action:'fullscreen',enabled:true});
   const full=await h.waitFor(async()=>{const p=await stateOf(main);return p.fullscreen&&!p.fullscreen_transitioning?p:null;},20000);await settle(main,10000);
   check(full.fullscreen&&!sameFrame(full.frame,windowed.frame),`fullscreen entered (frame ${JSON.stringify(full.frame)})`);
   check((await stateOf(main)).native_controls.length===0,'fullscreen: no native traffic lights in the client header');
   const restoreFull=await h.waitFor(async()=>{const r=(await h.query('sidebar.restore')).find(shown)?.rect;return r&&r.x<40?r:null;},8000).catch(()=>null);
   check(restoreFull,`fullscreen, sidebar hidden: the view bar drops the traffic-light inset (restore button x ${restoreWindowed.x} → ${restoreFull?.x})`);
   const q=await probe(main),fb=await blank();
   check(q.region[cell(q,fb.x,fb.y)]==='d','fullscreen: the view bar is still declared a drag region');
   {const before=(await stateOf(main)).titlebar_presses;await click(main,fb.x,fb.y);await click(main,fb.x,fb.y,2);await h.sleep(900);const after=await stateOf(main);
    check(after.titlebar_presses===before&&after.fullscreen&&sameFrame(after.frame,full.frame),'fullscreen: presses and double clicks on the view bar are not claimed (no drag, no zoom)');}
   const settings=(await node('toolbar.settings')).rect;
   await delivered(main,'fullscreen: settings tool button',settings.x+settings.w/2,settings.y+settings.h/2,async()=>(await h.query('settings.panel')).some(shown)||null);
   await shot0(join(out,`${theme}-fullscreen-main.png`),main);
   await h.key('w',{cmd:true});await h.waitFor(async()=>(await h.query('settings.panel')).some(shown)?null:true,8000);await h.waitFor(async()=>(await h.query('toolbar.settings')).some(shown)||null,8000);
   await native(main,{action:'fullscreen',enabled:false});
   const back=await h.waitFor(async()=>{const p=await stateOf(main);return !p.fullscreen&&!p.fullscreen_transitioning&&sameFrame(p.frame,windowed.frame)?p:null;},20000).catch(()=>null);
   check(back,'fullscreen left: the windowed frame is restored');await settle(main,10000);
   check((await stateOf(main)).native_controls.length===3,'fullscreen left: three native traffic lights again');
   const restoreBack=await h.waitFor(async()=>{const r=(await h.query('sidebar.restore')).find(shown)?.rect;return r&&r.x>=72?r:null;},8000).catch(()=>null);
   check(restoreBack,'fullscreen left, sidebar hidden: the traffic-light inset is back');
   await h.key('b',{cmd:true});await h.waitFor(async()=>((await h.query('workspace.sidebar')).find(shown)?.rect?.w??0)>200||null,8000);await h.sleep(400);
   const b=await blank();await claimed(main,'main after fullscreen: empty view bar',b.x,b.y);
  }
  // ── Settings window ──
  {const settings=(await node('toolbar.settings')).rect;
   await delivered(main,'main: settings tool button',settings.x+settings.w/2,settings.y+settings.h/2,async()=>(await h.query('settings.panel')).some(shown)||null);
   await node('settings.page.title');
   const win=await h.waitFor(async()=>(await h.windows()).windows.find(w=>!w.closing&&w.window_id!==main)?.window_id??null,10000);await h.sleep(500);
   const intro=(await node('settings.page.intro')).rect,head=(await node('settings.header')).rect;
   await claimed(win,'settings: page header blank space',intro.x+intro.w*0.7,intro.y+intro.h-10);
   await claimed(win,'settings: navigation title band',head.x+head.w-20,head.y+head.h-4);
   const keys=(await node('settings.nav.keys')).rect,title=async()=>((await h.query('settings.page.title')).find(shown) as any)?.text;
   const before=JSON.stringify(await title());
   await delivered(win,'settings: navigation row',keys.x+keys.w/2,keys.y+keys.h/2,async()=>JSON.stringify(await title())!==before||null);
   const intro2=(await node('settings.page.intro')).rect;await zoomAndRestore(win,'settings',intro2.x+intro2.w*0.7,intro2.y+intro2.h-10);
   await h.key('w',{cmd:true});await h.waitFor(async()=>(await h.query('settings.panel')).some(shown)?null:true,8000);await h.waitFor(async()=>(await h.query('toolbar.settings')).some(shown)||null,8000);
  }
  // ── wizard window (not maximizable) ──
  // Addressed by window id and coordinates only: in the foreground the harness tree follows the key window, which
  // stays the main window after a harness-injected click opened the wizard. Delivery to controls is covered above.
  {await click0((await h.query('sidebar.empty.new')).some(shown)?'sidebar.empty.new':'sidebar.footer.new');
   const win=await h.waitFor(async()=>(await h.windows()).windows.find(w=>!w.closing&&w.window_id!==main)?.window_id??null,10000);
   // Mounted and laid out: its title row is published as a drag region.
   await h.waitFor(async()=>{const q=await probe(win);return drags(q,q.width-40,34)||null;},10000,200);await h.sleep(500);
   const p=await stateOf(win),start=(await settle(win)).frame;
   check(p.width===720&&p.requested_mode==='custom'&&p.native_controls.length===3,'wizard window opened (720 wide, chrome custom, three traffic lights)');
   await claimed(win,'wizard: title bar blank space',p.width-40,34);
   const presses=(await stateOf(win)).titlebar_presses;await click(win,p.width-40,34,2);
   const after=await h.waitFor(async()=>{const q=await stateOf(win);return q.titlebar_presses>presses?q:null;},5000).catch(()=>null);await h.sleep(700);
   check(after&&sameFrame((await stateOf(win)).frame,start)&&!(await stateOf(win)).maximized,'wizard: a double click on the title bar is claimed and does not zoom (window is not maximizable)');
  }
  report.native='passed';
 }finally{await run.stop();await rm(run.iso,{recursive:true,force:true});}
}
async function click0(id:string){const n=await node(id);assert((await h.clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok,id);}
async function shot0(path:string,win:string){await h.sleep(300);assert((await h.screenshot(path,win)).ok,'screenshot');}

/** Left edge of the title-bar tool group: the leftmost visible `toolbar.*` button. */
async function toolsLeft(){
 let left=Infinity;for(const id of ['toolbar.history','toolbar.transfers','toolbar.notifications','toolbar.settings','toolbar.more']){for(const n of await h.query(id))if(shown(n))left=Math.min(left,n.rect.x);}
 assert(Number.isFinite(left),'title-bar tools');return left;
}

/** Luminance statistics of an 8-bit non-interlaced RGB(A) PNG (every 2nd pixel in each axis); same measure as window_render_smoke_native. */
function pixelStats(png:Buffer){
 let o=8,w=0,ht=0,ct=0,bd=0;const idat:Buffer[]=[];
 while(o<png.length){const len=png.readUInt32BE(o),type=png.toString('ascii',o+4,o+8),d=png.subarray(o+8,o+8+len);
  if(type==='IHDR'){w=d.readUInt32BE(0);ht=d.readUInt32BE(4);bd=d[8];ct=d[9];assert.equal(d[12],0,'interlaced PNG');}
  else if(type==='IDAT')idat.push(d);else if(type==='IEND')break;o+=12+len;}
 assert(bd===8&&(ct===6||ct===2),`unsupported PNG colour type ${ct} / depth ${bd}`);
 const bpp=ct===6?4:3,stride=w*bpp,raw=inflateSync(Buffer.concat(idat)),px=Buffer.alloc(stride*ht);
 for(let y=0;y<ht;y++){const f=raw[y*(stride+1)],src=raw.subarray(y*(stride+1)+1,(y+1)*(stride+1)),row=px.subarray(y*stride,(y+1)*stride),prev=y?px.subarray((y-1)*stride,y*stride):null;
  for(let x=0;x<stride;x++){const a=x>=bpp?row[x-bpp]:0,up=prev?prev[x]:0,c=prev&&x>=bpp?prev[x-bpp]:0;let v=src[x];
   if(f===1)v+=a;else if(f===2)v+=up;else if(f===3)v+=(a+up)>>1;else if(f===4){const q=a+up-c,pa=Math.abs(q-a),pb=Math.abs(q-up),pc=Math.abs(q-c);v+=pa<=pb&&pa<=pc?a:pb<=pc?up:c;}
   row[x]=v&255;}}
 let n=0,sum=0,sq=0;const colours=new Set<number>();
 for(let y=0;y<ht;y+=2)for(let x=0;x<w;x+=2){const i=y*stride+x*bpp,l=0.2126*px[i]+0.7152*px[i+1]+0.0722*px[i+2];n++;sum+=l;sq+=l*l;if(colours.size<4096)colours.add((px[i]<<16)|(px[i+1]<<8)|px[i+2]);}
 const mean=sum/n;return {width:w,height:ht,mean,variance:Math.max(0,sq/n-mean*mean),distinct:colours.size};
}
