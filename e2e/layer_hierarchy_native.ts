import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import {nativeThemeData} from './native_theme_data.mjs';
/** Paint regression through actual UI entry points, isolated data and no remote connections. */
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdir,mkdtemp,writeFile,readFile,open,rm} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import * as h from '../vendor/zenit/e2e/client.ts';
import {aiToggleId} from './ai_entry.ts';
import {settingsNav} from './settings_nav.ts';
const nav=settingsNav();
const binary=resolve(process.argv[2]),out=resolve(process.argv[3]);
const themes=process.argv[4]?.split(',')??Object.keys(nativeThemeData.themes);await mkdir(out,{recursive:true});
const shown=(n:any)=>n?.rect&&n.hidden!==true&&n.visible!==false&&n.rect.w>0&&n.rect.h>0;
const visible=(id:string)=>h.waitFor(async()=>(await h.query(id)).find(shown)??null,10000);
// A control can be laid out before it takes clicks (a float card still landing): retry until the click is accepted.
const click=async(id:string)=>{await visible(id);await h.waitFor(async()=>(await h.clickTestId(id)).ok||null,8000).catch(()=>assert.fail(id));};
// The permission control has two forms (chip / compact icon button on narrow tool rows); exactly one is shown.
const permissionControl=async()=>h.waitFor(async()=>{for(const id of ['ai.composer.permission','ai.composer.permission.compact'])if((await h.query(id)).some(shown))return id;return null;},10000);
const report:any={status:'running',binary,binary_sha256:createHash('sha256').update(await readFile(binary)).digest('hex'),cases:[],limits:['Public synthetic Harness input, actual Metal pixels; physical IME and VoiceOver not covered.','Only temporary app data and loopback fixture endpoints; no remote connections are submitted.']};
try{for(const theme of themes){
 const iso=await mkdtemp('/private/tmp/zw-layers-'),data=join(iso,'data'),rpc=join(iso,'rpc');await mkdir(data);await mkdir(rpc);process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
 await writeFile(join(data,'config.toml'),`[ui]\ntheme="${theme}"\n[ui.materials]\nblur_px=0\n[ui.materials.background]\ntransparency=100\n`);
 await writeFile(join(data,'hosts.toml'),'[[hosts]]\nname="Layer hierarchy host"\nhost="192.0.2.20"\nuser="deploy"\n');
 const log=await open(join(out,theme+'.log'),'w');const app=spawn(binary,[],{env:{...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1'},stdio:['ignore',log.fd,log.fd]});const ended=new Promise<void>(r=>app.once('close',()=>r()));
 const item:any={theme,status:'running',surfaces:[]};report.cases.push(item);
 const capture=async(name:string,id:string)=>{const n=await h.waitFor(async()=>{const v=(await h.query(id)).find(shown) as any;return v&&(v.effective_opacity??1)===1&&(v.scale_x??1)===1&&(v.scale_y??1)===1?v:null},15000);await h.screenshot(join(out,`${theme}-${name}.png`));await writeFile(join(out,`${theme}-${name}.json`),JSON.stringify(await h.query(id),null,2));item.surfaces.push({name,id,rect:n.rect});};
 try{
  await h.waitForServerReady();assert.equal(Number(JSON.parse(await readFile(join(rpc,'owner.json'),'utf8')).pid),app.pid);await h.resizeWindow(1440,900);
  await click('toolbar.new_session');await capture('session-menu','session.menu');await h.key('escape');
  await click('toolbar.notifications');await capture('notifications','notifications.history');await h.key('escape');
  await click('sidebar.new.group');await capture('group-create','asset.group.dialog');await click('asset.group.input');await h.type_('Layer hierarchy draft');assert.equal((await h.inputState('asset.group.input')).buffer,'Layer hierarchy draft');await capture('group-input','asset.group.dialog');await h.key('escape');await h.key('escape');await h.waitFor(async()=>!(await h.query('asset.group.dialog')).some(shown)||null,6000); // an edited input takes the first Escape (reverts its value); the second closes the dialog

  await nav.toCategory('appearance');await capture('settings','settings.panel');await nav.close(); // two-level settings; no close button: Cmd+W (settings_nav.ts)
  await click('workspace.empty.local');await visible('terminal.surface');await h.key('f',{cmd:true});await capture('terminal-search','terminal.search');await h.type_('search draft');await capture('terminal-search-query','terminal.search');await h.key('escape');
  {const tab=await visible('tabs.tab.1');assert((await h.clickAt(tab.rect.x+tab.rect.w/2,tab.rect.y+tab.rect.h/2,1,'right')).ok);await click('context.menu.rename_tab');}await capture('rename','tabs.rename'); // 页签菜单“重命名”（与 compact_popovers_native 同一入口）
  await h.key('escape');
  // title-click: the theme left the title bar — 菜单栏“显示 › 外观…” opens Settings › 外观与主题.
  assert((await h.request('POST','/zerowork/app-menu',{invoke:true})).ok);await capture('theme-settings','settings.appearance.themes');await h.key('escape');await h.waitFor(async()=>!(await h.query('settings.window')).some(shown)||null,6000);
  // The session card opens from the tab menu's “会话连接” (no hover card).
  {const tab=await visible('local.status.identity');assert((await h.clickAt(tab.rect.x+tab.rect.w/2,tab.rect.y+tab.rect.h/2,1,'right')).ok);await click('context.menu.session_identity');}
  await capture('local-status','status.detail');await h.key('escape');
  await click(await aiToggleId());await click(await permissionControl());await capture('ai-permission','ai.permission.menu');await h.key('escape');
  await click('ai.sessions');await capture('ai-sessions','ai.sessions.menu');await h.key('escape');
  await h.resizeWindow(860,480);
  // The one-time narrow-window tip sits over part of the composer. Move the
  // pointer out before waiting so the Toast's hover pause cannot keep it open.
  await h.mouseMove(20,80);
  await visible('notifications.tip');
  await h.waitFor(async()=>!(await h.query('notifications.tip')).some(shown)||null,15000);
  await click(await permissionControl());
  await capture('ai-permission-minimum','ai.permission.menu');await h.key('escape');
  item.status='passed';console.log(theme+' passed: '+item.surfaces.length+' surfaces');
 }catch(e){item.status='failed';item.error=String(e);await h.screenshot(join(out,theme+'-failure.png')).catch(()=>{});throw e;}
 finally{if(app.exitCode===null&&app.signalCode===null)app.kill('SIGTERM');await ended;await log.close();await rm(iso,{recursive:true,force:true});}
}report.status='passed';}catch(e){report.status='failed';report.error=String(e);console.error(e);process.exitCode=1;}finally{await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));}
