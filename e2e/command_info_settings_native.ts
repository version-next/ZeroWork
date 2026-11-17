/** Command metadata settings: isolated production settings/editor, no SSH connection.
 * node e2e/command_info_settings_native.ts OUT BINARY [light|dark]   (default dark)
 *
 * Current contract (re-checked against source):
 * - Global switch: Settings › 外观与主题 › 终端与工作区 `settings.toggle.command_info` (zenit Switch; its state is the knob
 *   position inside the track — on = knob on the right half, off = left half). Saving goes through the floating Save Bar
 *   (settings_nav.ts save()); the preferences window closes with Cmd+W.
 * - Host override: the connection editor is its own native window (`wizard.window`, wizard.zig window_spec 720×640,
 *   min 600×420). New hosts start from `sidebar.empty.new` (empty sidebar); an existing host is edited from its
 *   right-click menu `context.menu.edit_host` (the row's hover edit button `sidebar.host.edit` was removed in 7ec0492e).
 *   In 高级选项 the `wizard.command_info` and `wizard.shell_integration` Selects share one row (`wizard.command_info.row`).
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdir,mkdtemp,readFile,writeFile,open,realpath,rm} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {createHash} from 'node:crypto';
import * as h from '../zig-out/share/zenit/harness/client.ts';
import {settingsNav} from './settings_nav.ts';
import {openSidebarHostMenu} from './sidebar_host_menu.ts';
const nav=settingsNav();
const out=resolve(process.argv[2]),binary=resolve(process.argv[3]),theme=process.argv[4]||'dark';await mkdir(out,{recursive:true});
assert(['light','dark'].includes(theme),'theme must be light or dark');
const base=await realpath(await mkdtemp(join(tmpdir(),'zw-command-info-native-'))),data=join(base,'data'),rpc=join(base,'rpc');await mkdir(data);await mkdir(rpc);
await writeFile(join(data,'config.toml'),`[meta]\nconfig_revision=1\n[ui]\ntheme="${theme}"\ncommand_info=true\n`);
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const log=await open(join(out,'app.log'),'w');const app=spawn(binary,[],{env:{...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1',ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0'},stdio:['ignore',log.fd,log.fd]});const ended=new Promise(r=>app.once('close',r));
const report:any={status:'running',theme,binary,sha256:createHash('sha256').update(await readFile(binary)).digest('hex'),checks:[],geometry:[],captures:[],limits:['Uses actual native controls in an isolated test-mode App; no external connection or production user data.','The live effect of command_info on terminal metadata is covered by command_annotations_native.']};
const shown=(n:any)=>n&&n.hidden!==true&&n.visible!==false&&(n.effective_opacity??1)>0&&n.rect?.w>0&&n.rect?.h>0;
const text=(n:any):string=>(n.text??'')+(n.children??[]).map(text).join('');
async function vis(id:string){return h.waitFor(async()=>(await h.query(id)).find(shown)??null,12000)}
async function gone(id:string){await h.waitFor(async()=>!(await h.query(id)).some(shown)||null,12000)}
async function click(id:string){await vis(id);assert((await h.clickTestId(id)).ok,id)}
async function edit(id:string,value:string){await click(id);await h.key('a',{cmd:true});await h.type_(value);await h.waitFor(async()=>(await h.inputState(id)).buffer===value||null,5000)}
async function capture(name:string){await h.sleep(180);assert((await h.screenshot(join(out,name+'.png'))).ok);report.captures.push(name)}
const fileHas=(file:string,re:RegExp)=>h.waitFor(async()=>re.test(await readFile(join(data,file),'utf8').catch(()=>''))||null,10000);
/** zenit Switch: track box with the knob box inside; the knob sits in the right half when on. */
async function switchOn(id:string){
 const sw=await vis(id),track=(sw.children??[]).find(shown),knob=(track?.children??[]).find(shown);assert(track&&knob,`${id} has a track and a knob`);
 assert(knob.rect.x>=track.rect.x-0.5&&knob.rect.x+knob.rect.w<=track.rect.x+track.rect.w+0.5,'knob stays inside its track');
 return knob.rect.x+knob.rect.w/2>track.rect.x+track.rect.w/2;
}
async function waitSwitch(id:string,on:boolean){await h.waitFor(async()=>(await switchOn(id))===on||null,5000)}
async function settings(){await nav.toField('command_info');await vis('settings.toggle.command_info')}
/** Scroll the identity step's body until the command-info row is fully inside it (高级选项 is the last card; while its
 * body is still expanding the scroll range grows, so keep scrolling until the condition holds, bounded by time). */
async function scrollBottom(){
 await h.waitFor(async()=>{
  const row=(await h.query('wizard.command_info.row')).find(shown),v=(await h.query('wizard.scroll.identity')).find(shown);
  if(row&&v&&row.rect.y+row.rect.h<=v.rect.y+v.rect.h+0.5&&row.rect.y>=v.rect.y-0.5)return true;
  if(v)await h.scrollAt(v.rect.x+v.rect.w-8,v.rect.y+v.rect.h/2,0,-1800);return null;
 },8000);
}
async function advancedOpen(){if(!(await h.query('wizard.advanced.body')).some(shown))await click('wizard.advanced.toggle');await vis('wizard.advanced.body');await scrollBottom()}
async function pick(select:string,option:string,label:string){await click(select);await click(option);await h.waitFor(async()=>text((await h.query(select)).find(shown)??{}).includes(label)||null,5000)}
async function saveHost(){await click('wizard.next.identity');await vis('wizard.scroll.route');await click('wizard.next.route');await vis('wizard.scroll.review');await click('wizard.save_only');await gone('wizard.window')}
async function editHost(){await openSidebarHostMenu();await click('context.menu.edit_host');await vis('wizard.name')}
try{
 await h.waitForServerReady(60000);await h.resizeWindow(1440,900);
 await settings();assert.equal(await switchOn('settings.toggle.command_info'),true,'command_info=true in config shows the switch on');
 await nav.click('settings.toggle.command_info');await waitSwitch('settings.toggle.command_info',false);await nav.save();await fileHas('config.toml',/command_info = false/);await capture('global-hidden');
 report.checks.push('Global command_info is edited and saved through the actual native Settings transaction');await nav.close();
 await settings();assert.equal(await switchOn('settings.toggle.command_info'),false,'reopened Settings shows the saved off state');await capture('global-hidden-reopened');await nav.close();
 report.checks.push('The saved global setting is retained after closing and reopening Settings');

 await click('sidebar.empty.new');await vis('wizard.window');
 await edit('wizard.name','Command info QA');await edit('wizard.host','annotation.invalid');await edit('wizard.user','ops');await advancedOpen();
 // The editor window's own size range (wizard.zig window_spec: 720×640, min 600×420); resizeWindow acts on the key window.
 for(const [w,height] of [[720,640],[600,420]]){
  assert((await h.resizeWindow(w,height)).ok);await h.waitFor(async()=>{const win=(await h.query('wizard.window')).find(shown);return win&&Math.abs(win.rect.w-w)<0.5&&Math.abs(win.rect.h-height)<0.5||null},5000);await scrollBottom();
  const info=await vis('wizard.command_info'),shell=await vis('wizard.shell_integration'),viewport=await vis('wizard.scroll.identity'),encoding=await vis('wizard.encoding'),scrollback=await vis('wizard.scrollback');
  // Same row, same native Select size (zenit ControlShell; same class as the other advanced Selects in the form, e.g. 编码 / 回滚),
  // the same column gap as the 编码 | 回滚 row above (form two-column grid), fully inside the scroll viewport.
  assert(Math.abs(info.rect.y-shell.rect.y)<.5,'both Selects share a row');assert(Math.abs(info.rect.w-shell.rect.w)<.5,'equal column widths');
  assert(Math.abs(info.rect.h-shell.rect.h)<.5&&Math.abs(info.rect.h-encoding.rect.h)<.5,`native Select height is consistent (${info.rect.h} / ${shell.rect.h} / ${encoding.rect.h})`);
  assert(Math.abs(info.rect.x-encoding.rect.x)<.5&&Math.abs(shell.rect.x-scrollback.rect.x)<.5,'columns align with the row above');
  assert(Math.abs((shell.rect.x-info.rect.x-info.rect.w)-(scrollback.rect.x-encoding.rect.x-encoding.rect.w))<.5,'same column gap as the row above');
  assert(info.rect.y>=viewport.rect.y-.5&&info.rect.y+info.rect.h<=viewport.rect.y+viewport.rect.h+.5,'row is inside the viewport');
  assert(info.rect.x>=viewport.rect.x-.5&&shell.rect.x+shell.rect.w<=viewport.rect.x+viewport.rect.w+.5,'row fits the viewport width');
  assert(text(info).includes('继承全局设置'));assert(text(shell).includes('继承全局设置'));
  report.geometry.push({window:[w,height],info:info.rect,shell:shell.rect,encoding:encoding.rect,scrollback:scrollback.rect,viewport:viewport.rect});await capture('host-inherit-'+w);
 }
 assert((await h.resizeWindow(720,640)).ok);await scrollBottom();
 await pick('wizard.command_info','wizard.command_info.off','隐藏');assert(text(await vis('wizard.shell_integration')).includes('继承全局设置'));await capture('host-hidden');
 await saveHost();await fileHas('hosts.toml',/command_info = false/);
 report.checks.push('Host override saves false without modifying the independent shell-initialization inheritance');
 await editHost();await advancedOpen();assert(text(await vis('wizard.command_info')).includes('隐藏'),'reopened host keeps Hide');assert(text(await vis('wizard.shell_integration')).includes('继承全局设置'));await capture('host-hidden-reloaded');
 await pick('wizard.command_info','wizard.command_info.inherit','继承全局设置');await saveHost();
 await h.waitFor(async()=>!(await readFile(join(data,'hosts.toml'),'utf8')).includes('command_info')||null,10000);
 report.checks.push('Reopening the saved host (right-click › 编辑主机配置) restores Hide; saving Inherit removes the host override instead of freezing the current global value');
 await settings();await nav.click('settings.toggle.command_info');await waitSwitch('settings.toggle.command_info',true);await nav.save();await fileHas('config.toml',/command_info = true/);await capture('global-shown');await nav.close();
 report.checks.push('Global display can be restored without touching execution or recording configuration');
 assert((await h.request('POST','/quit')).ok);report.exit=await Promise.race([ended,h.sleep(20000).then(()=>null)]);assert.equal(report.exit,0,'isolated App quits cleanly');
 report.status='passed';
}catch(e){report.status='failed';report.error=String(e);await writeFile(join(out,'failure-tree.json'),JSON.stringify(await h.tree({visibleOnly:true}),null,2)).catch(()=>{});await capture('failure').catch(()=>{});process.exitCode=1}
finally{if(app.exitCode===null&&app.signalCode===null){app.kill('SIGTERM');await Promise.race([ended,h.sleep(3000)]);if(app.exitCode===null&&app.signalCode===null){app.kill('SIGKILL');await ended}}await log.close();await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));await rm(base,{recursive:true,force:true})}
console.log(JSON.stringify({status:report.status,error:report.error,out}));
