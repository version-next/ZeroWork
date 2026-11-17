/** Native floating surfaces keep zenit's own look (usage-b4-materials, ZENIT_USAGE_AUDIT 应用层发现 4).
 *
 * Material belongs to whoever creates a surface: nothing walks the window or its overlay layers to repaint them.
 * A native Menu / Popover / Modal panel therefore paints zenit's own opaque surface at every material setting.
 * The app starts with background transparency 50 (ZeroWork's own surfaces are translucent there) and checks:
 *  - every native panel it opens (terminal context menu, new-session menu and its nested “更多” submenu, tab
 *    context menu) has an opaque fill (`bg_rgba` alpha 255), and all menu
 *    panels share one fill;
 *  - two windows, theme switch: with the main window and the preferences window both open, the theme is switched
 *    in preferences (saved); every surface is reopened and must be opaque again with the other theme's fill
 *    (different from the first), menus still sharing one fill — nested submenu included (rebuilt after the switch);
 *  - switching back restores the first fills exactly.
 * Screenshots: `<variant>-<stage>-<surface>.png` (main window) and `<variant>-<stage>-settings.png`.
 *
 * Usage: node e2e/native_surfaces_theme_native.ts <binary> <out> [light|dark]
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {chmod,mkdir,mkdtemp,open,writeFile,realpath} from 'node:fs/promises';
import {dirname,resolve,join} from 'node:path';
import {pathToFileURL} from 'node:url';
const binary=resolve(process.argv[2]),out=resolve(process.argv[3]),variant=process.argv[4]??'light';
const theme=variant==='dark'?'dark':'light',other=theme==='dark'?'light':'dark';
const h=await import(pathToFileURL(resolve(dirname(binary),'../share/zenit/harness/client.ts')).href);
const {settingsNav}=await import('./settings_nav.ts');
const iso=await realpath(await mkdtemp('/private/tmp/zw-native-surfaces-'));await chmod(iso,0o700);
const data=join(iso,'data'),rpc=join(iso,'rpc'),tmp=join(iso,'tmp'),zdot=join(iso,'zdot');
for(const p of [out,data,rpc,tmp,zdot])await mkdir(p,{recursive:true,mode:0o700});
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
await writeFile(join(data,'hosts.toml'),`[registry]\nschema_version=2\nrevision=1\nnext_connection_id=2\nnext_group_id=2\n[[groups]]\ngroup_id=1\nrevision=1\nname="Contract"\ncollapsed=false\nordered_connection_ids=[1]\n[[hosts]]\nasset_group_id=1\nconnection_id=1\nrevision=1\nprotocol="ssh"\nauth_mode="password"\noptions={strict_host_key=true}\nname="Menu SSH (offline)"\nhost="127.0.0.1"\nport=9\nuser="contract"\n`);
await writeFile(join(data,'config.toml'),`[meta]\nconfig_revision=1\n[updates]\nauto_check=false\n[ui]\ntheme="${theme}"\n[ui.materials]\nblur_px=0\n[ui.materials.background]\ntransparency=50\n`);
const log=await open(join(out,`${variant}-app.log`),'w');
const app=spawn(binary,[],{env:{PATH:process.env.PATH??'/usr/bin:/bin',HOME:iso,CFFIXED_USER_HOME:iso,TMPDIR:tmp+'/',ZDOTDIR:zdot,ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1',OPENAI_API_KEY:'',ANTHROPIC_API_KEY:''},stdio:['ignore',log.fd,log.fd]});
const ended=new Promise(r=>app.once('close',r));
const report:any={status:'running',variant,stages:[]};
const shown=(n:any)=>n&&n.hidden!==true&&n.visible!==false&&(n.effective_opacity??1)>.98&&n.rect?.w>0&&n.rect?.h>0;
const visible=(id:string,ms=10000)=>h.waitFor(async()=>(await h.query(id)).find(shown)??null,ms);
const gone=(id:string)=>h.waitFor(async()=>!(await h.query(id)).some(shown)||null,6000);
const click=async(id:string)=>{await visible(id);assert((await h.clickTestId(id)).ok,id);};
const rgba=(n:any)=>String(n.bg_rgba).split(',').map(Number);
const nav=settingsNav();
/** Opens each native surface of the main window, checks it and returns `{surface: 'r,g,b'}`. */
/** The harness follows the key window; the tour drives the main window (preferences stays open beside it). */
const mainWindow=async()=>{await h.sleep(300);const state:any=await h.request('POST','/zerowork/windows',{action:'snapshot'});assert(state.windows?.length>=1,'main window');assert((await h.request('POST','/zerowork/windows',{action:'select',window:state.windows[0].window}) as any).ok);await h.sleep(300);};
async function tour(stage:string){
 const fills:Record<string,string>={};
 await mainWindow();
 const check=async(name:string,id:string,component:string[])=>{
  const n=await visible(id);await h.sleep(250);
  const node=(await h.query(id)).find(shown) as any;
  assert(component.includes(node.component),`${stage} ${name}: ${id} is a native ${component.join(' / ')} panel, got ${node.component}`);
  const c=rgba(node);assert.equal(c[3],255,`${stage} ${name}: native panel is opaque at transparency 50 (bg_rgba ${node.bg_rgba})`);
  fills[name]=c.slice(0,3).join(',');
  assert((await h.screenshot(join(out,`${variant}-${stage}-${name}.png`))).ok);
  return n;
 };
 // Terminal context menu.
 {const t=await visible('terminal.surface');assert((await h.clickAt(t.rect.x+t.rect.w/2,t.rect.y+t.rect.h/2,1,'right')).ok);}
 await check('context-menu','terminal.menu',['PopoverContent']);await h.key('escape');await gone('terminal.menu');
 // New-session menu and its nested submenu (a layer opened from a layer).
 await click('toolbar.new_session');await check('session-menu','session.menu',['PopoverContent']);
 {const more=await visible('session.menu.more');await h.mouseMove(more.rect.x+more.rect.w/2,more.rect.y+more.rect.h/2);}
 await check('session-submenu','session.menu.more.panel',['PopoverContent']);
 await h.key('escape');await h.key('escape');await gone('session.menu');
 // Tab context menu.
 {const flat=(n:any):any[]=>n?[n,...(n.children??[]).flatMap(flat)]:[];const tab=flat(await visible('tabs.strip')).find((n:any)=>/^tabs\.tab\.\d+$/.test(n.test_id??'')&&shown(n));assert(tab,'a tab is shown');assert((await h.clickAt(tab.rect.x+tab.rect.w/2,tab.rect.y+tab.rect.h/2,1,'right')).ok);}
 await check('tab-menu','context.menu',['PopoverContent']);await h.key('escape');await gone('context.menu');
 const menus=['context-menu','session-menu','session-submenu','tab-menu'].map(k=>fills[k]);
 assert(menus.every(v=>v===menus[0]),`${stage}: every menu panel (nested submenu included) shares one native fill: ${JSON.stringify(fills)}`);
 report.stages.push({stage,fills});
 return fills;
}
try{
 await h.waitForServerReady();await h.resizeWindow(1440,900);
 await click('workspace.empty.local');await visible('terminal.surface');
 const first=await tour('start-'+theme);
 // Two windows: preferences opens as its own native window; switch the theme there and save.
 await nav.pickTheme(other);await nav.save();
 assert((await h.windows()).windows.length>=2,'main window and preferences window are both open');
 await h.sleep(400);
 {const wins=(await h.windows()).windows;for(const w of wins)await h.screenshot(join(out,`${variant}-switched-${other}-window-${w.window_id}.png`),w.window_id).catch(()=>{});}
 const second=await tour('switched-'+other);
 for(const k of Object.keys(first))if(second[k]!==undefined)assert.notEqual(second[k],first[k],`${k}: the panel follows the theme switch (${first[k]} → ${second[k]})`);
 // And back: the first fills exactly, with both windows still open.
 await nav.pickTheme(theme);await nav.save();await h.sleep(400);
 assert((await h.windows()).windows.length>=2,'both windows still open after the second switch');
 const third=await tour('back-'+theme);
 assert.deepEqual(third,first,'switching back restores every native fill');
 report.status='passed';console.log(`${variant} passed: ${JSON.stringify(report.stages.map((s:any)=>s.fills))}`);
}catch(e){report.status='failed';report.error=String(e);await h.screenshot(join(out,`${variant}-failure.png`)).catch(()=>{});console.error(e);process.exitCode=1;}
finally{await writeFile(join(out,`${variant}-report.json`),JSON.stringify(report,null,2));if(app.exitCode===null&&app.signalCode===null)app.kill('SIGTERM');await ended;await log.close();}
