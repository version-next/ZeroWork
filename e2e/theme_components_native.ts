import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import {nativeThemeData} from './native_theme_data.mjs';
/** Built-in palette acceptance through production UI; only isolated local fixtures.
 * node e2e/theme_components_native.ts BINARY OUTPUT [THEME[,THEME…]]   (default: every built-in palette)
 *
 * Per palette: sidebar host row at rest and hovered, connection wizard and its field error, four settings categories,
 * the terminal's @ command popup and the busy-process close confirmation — each captured once fully presented.
 * Sidebar row contract (sidebar_view.zig `HostRow.updateTrailing`, sidebar_styles.zig): the route badge (icon + hop
 * count) is always shown for SSH hosts; hovering an unselected row adds the 24pt ▶ (`action_size`) one 4pt trailing gap
 * after it, and the name gives up exactly that slot. The protocol label (sidebar.host.protocol) was removed in
 * 04750679 — the protocol is the row's session icon (`sidebar.host.icon`).
 */
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdir,mkdtemp,writeFile,readFile,open,rm} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import * as h from '../vendor/zenit/e2e/client.ts';
import {settingsNav} from './settings_nav.ts';
const nav=settingsNav();
const binary=resolve(process.argv[2]),out=resolve(process.argv[3]);await mkdir(out,{recursive:true});
const themes=process.argv[4]?.split(',')??Object.keys(nativeThemeData.themes);
const report:any={status:'running',binary,binary_sha256:createHash('sha256').update(await readFile(binary)).digest('hex'),cases:[],limits:['Production native components with synthetic Harness input; physical IME and VoiceOver not covered.','No saved configuration, remote connection or notification permission action. The local PTY writes runner-owned readiness data and runs a bounded sleep to exercise busy-process close confirmation; cancellation preserves the session and Ctrl+C stops the fixture.']};
const shown=(n:any)=>n?.rect&&n.visible!==false&&n.hidden!==true&&n.rect.w>0&&n.rect.h>0;
const ACTION=24,TRAILING_GAP=4; // sidebar_styles.zig action_size; sidebar_view.zig HostRow trailing gap
const presented=(n:any)=>shown(n)&&(n.effective_opacity??1)===1&&(n.world_transform?.[0]??1)===1&&(n.world_transform?.[3]??1)===1;
const flat=(n:any):any[]=>n?[n,...(n.children??[]).flatMap(flat)]:[];
const part=(r:any,id:string)=>flat(r).find((n:any)=>n.test_id===id&&shown(n));
const vis=async(id:string)=>h.waitFor(async()=>{const a=await h.query(id);return Array.isArray(a)?a.find(shown)??null:null},10000);
/** Click the presented instance (dialogs fade / scale in) at its centre. */
const click=async(id:string)=>{const n=await h.waitFor(async()=>{const a=await h.query(id);return Array.isArray(a)?a.find(presented)??null:null},10000);assert((await h.clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok,id)};
try{for(const theme of themes){
 const iso=await mkdtemp('/private/tmp/zw-theme-components-'),data=join(iso,'data'),rpc=join(iso,'rpc'),shell=join(iso,'shell');for(const p of [data,rpc,shell])await mkdir(p);process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
 await writeFile(join(shell,'.zshrc'),"bindkey -e\nPS1='audit%# '\n");
 await writeFile(join(data,'config.toml'),`[meta]\nconfig_revision=1\n[ui]\ntheme="${theme}"\n[ui.materials]\nblur_px=0\n[ui.materials.background]\ntransparency=100\n`);
 await writeFile(join(data,'hosts.toml'),'[registry]\nschema_version=2\nrevision=1\nnext_connection_id=2\nnext_group_id=1\n[[hosts]]\nconnection_id=1\nrevision=1\nprotocol="ssh"\nauth_mode="agent"\nname="Audit database"\nhost="192.0.2.20"\nport=22\nuser="deploy"\n');
 const log=await open(join(out,theme+'.log'),'w');const app=spawn(binary,[],{env:{...process.env,ZDOTDIR:shell,ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1'},stdio:['ignore',log.fd,log.fd]});const ended=new Promise(r=>app.once('close',r));const item:any={theme,captures:[]};report.cases.push(item);
 const nodes=async(id:string):Promise<any[]>=>await h.query(id);
 const capture=async(name:string,id:string)=>{const n=await h.waitFor(async()=>{const a=await nodes(id);const v=Array.isArray(a)?a.find(presented)as any:null;return v??null},15000);await h.screenshot(join(out,theme+'-'+name+'.png'));await writeFile(join(out,theme+'-'+name+'.json'),JSON.stringify(await nodes(id),null,2));item.captures.push({name,id,rect:n.rect})};
 try{await h.waitForServerReady();assert.equal(Number(JSON.parse(await readFile(join(rpc,'owner.json'),'utf8')).pid),app.pid);await h.resizeWindow(1440,900);
 const host=await vis('sidebar.host');await h.mouseMove(700,800);
 const rest=await h.waitFor(async()=>{const r=(await h.query('sidebar.host')).find(shown);return r&&!part(r,'sidebar.host.connect')?r:null},5000);
 const resting=part(rest,'sidebar.host.name').rect;
 assert(part(rest,'sidebar.host.icon'),'the session icon carries the protocol');
 assert.equal(part(rest,'sidebar.host.hops')?.text,'0','an SSH host shows its route badge (0 hops) at rest');
 await h.mouseMove(host.rect.x+100,host.rect.y+host.rect.h/2);
 const hot=await h.waitFor(async()=>{const r=(await h.query('sidebar.host')).find(shown);return r&&part(r,'sidebar.host.connect')?r:null},5000);
 await capture('sidebar-hover','workspace.sidebar');
 const hover=part(hot,'sidebar.host.name').rect,connect=part(hot,'sidebar.host.connect').rect,route=part(hot,'sidebar.host.route').rect;
 assert.equal(part(hot,'sidebar.host.hops')?.text,'0','the route badge stays while hovered');
 assert(Math.abs(hover.x-resting.x)<.25,'hover keeps the name in place');
 assert(Math.abs(resting.w-hover.w-(ACTION+TRAILING_GAP))<.25,`hover takes exactly the ▶ slot from the name: ${resting.w} → ${hover.w}`);
 assert(Math.abs(connect.w-ACTION)<.25&&Math.abs(route.x+route.w+TRAILING_GAP-connect.x)<.25,'▶ is 24 wide, one trailing gap after the route badge');
 assert(hover.w>=80,'identity keeps a readable width');
 await h.mouseMove(700,800);
 // Island B v3 (e1372d88): new hosts start from the sidebar bottom row and the wizard is its own native window
 // (`wizard.window`; its close is the traffic light, so the in-panel `wizard.close` is hidden — cancel is the footer's).
 await click('sidebar.footer.new');await capture('wizard','wizard.window');assert(!(await h.query('wizard.close')).some(shown),'the window wizard has no in-panel close');
 await click('wizard.name');await click('wizard.host');await vis('wizard.name.error');await capture('wizard-error','wizard.window');
 await click('wizard.cancel');await h.waitFor(async()=>!(await h.query('wizard.window')).some(shown)||null,10000);
 await nav.open();for(const page of ['ssh','transfer','keys','notifications']){await nav.toCategory(page);await capture('settings-'+page,'settings.panel')};await nav.close(); // two-level settings; Cmd+W closes (settings_nav.ts)
 await click('workspace.empty.local');const surface=await vis('terminal.surface');await h.clickAt(surface.rect.x+40,surface.rect.y+surface.rect.h-40);
 const ready=join(iso,'ready');await h.type_(`printf ready > '${ready}'`);await h.key('return');await h.waitFor(async()=>{try{return await readFile(ready,'utf8')==='ready'||null}catch{return null}},15000);
 // The @ popup needs the trusted line editor, which arms with the next prompt after the readiness command: retry a
 // bounded number of times, clearing the unsubmitted draft (never submitting it) between attempts.
 let popup=false;
 for(let attempt=0;attempt<3&&!popup;attempt++){
  assert((await h.type_('@')).ok);
  popup=await h.waitFor(async()=>(await h.query('terminal.commands')).some(shown)||null,4000).then(()=>true,()=>false);
  if(!popup)assert((await h.key('u',{ctrl:true})).ok);
 }
 assert(popup,'the @ command popup opens');
 await capture('commands','terminal.commands');assert((await h.key('escape')).ok);
 await h.waitFor(async()=>!(await h.query('terminal.commands')).some(shown)||null,5000);assert((await h.key('u',{ctrl:true})).ok);
 // A busy foreground process. Ready once the app has identified it: the tab title follows the foreground process
 // (tab_naming.zig, “sleep · ~”). Right after the exec the inspection is transitional and the confirmation (correctly,
 // fail-safe) says “无法核实本地进程状态”; the identified state names the process.
 await h.type_('/bin/sleep 20');await h.key('return');
 const tabText=async()=>{const t=await h.tree({root:'tabs.strip',visibleOnly:true});return flat(t).map((n:any)=>typeof n.text==='string'?n.text:'').join('');};
 await h.waitFor(async()=>(await tabText()).includes('sleep')||null,10000).catch(async()=>assert.fail(`the tab names the foreground sleep: ${await tabText()}`));
 await h.key('w',{cmd:true});await capture('danger-confirmation','local.close.confirmation');
 const confirmText=flat((await h.query('local.close.confirmation')).find(shown)).map((n:any)=>typeof n.text==='string'?n.text:'').join('');
 assert(confirmText.includes('仍有前台进程')&&/sleep · PID \d+/.test(confirmText),`the confirmation names the busy foreground process: ${confirmText}`);await click('local.close.cancel');await h.waitFor(async()=>!(await h.query('local.close.confirmation')).some(shown)||null,5000);await vis('terminal.surface');assert.equal((await h.query('tabs.strip')).flatMap(flat).filter((n:any)=>shown(n)&&/^tabs\.tab\.\d+$/.test(n.test_id??'')).length,1,'cancel keeps the busy session');await h.key('c',{ctrl:true});item.status='passed';console.log(theme+' passed: '+item.captures.length+' states');
 }catch(e){item.error=String(e);item.status='failed';await h.screenshot(join(out,theme+'-failure.png')).catch(()=>{});await writeFile(join(out,theme+'-failure-tree.json'),JSON.stringify(await h.tree({visibleOnly:true}),null,2)).catch(()=>{});throw e;}
 finally{if(app.exitCode===null&&app.signalCode===null)app.kill('SIGTERM');await ended;await log.close();await rm(iso,{recursive:true,force:true});}
}report.status='passed';}catch(e){report.status='failed';report.error=String(e);console.error(e);process.exitCode=1;}finally{await writeFile(join(out,'report.json'),JSON.stringify(report,null,2))}
