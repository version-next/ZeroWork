/** Retained editor backgrounds after real theme settings changes. Offline,
 * isolated data, synthetic input and Metal screenshots; never connects hosts.
 * node e2e/ui_background_refresh_native.ts [build-prefix] [evidence-directory]
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdir,mkdtemp,open,writeFile,rm} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {cleanupOwnedBridgeDirectories} from './native_owned_cleanup.ts';

const prefix=resolve(process.argv[2]??'zig-out');
const out=resolve(process.argv[3]??'/tmp/zw-ui-background-evidence');
await mkdir(out,{recursive:true});
const h=await import(join(prefix,'share/zenit/harness/client.ts'));
const {settingsNav}=await import('./settings_nav.ts');
// Two-level settings (settings_nav.ts). Saved = the floating Save Bar hides (was the persistent footer state "已保存"); Cmd+W closes.
// Island B v3 (e1372d88): the connection editor is its own native window (wizard.zig window_spec). It has no in-window
// close button (`wizard.close` is display:none there, "The native window closes through its traffic light (= cancel)");
// Escape is the same cancel (wizard.zig windowKey) and the window "goes away with its draft" (wizard.zig hide()), so the
// editor is no longer a retained node that survives a theme change: every open is a new window that must paint the
// theme saved meanwhile. The script therefore asserts the editor surfaces' actual colors per theme instead of node ids.
const nav=settingsNav();
const shown=(n:any)=>n.visible!==false&&(n.effective_opacity??n.opacity??1)>.99&&n.rect?.w>0&&n.rect?.h>0;
const visible=(id:string)=>h.waitFor(async()=>(await h.query(id)).find(shown)??null,10000);
const click=async(id:string)=>{await visible(id);assert((await h.clickTestId(id)).ok,id);await h.sleep(120);};
const cases:any[]=[];

for(const transparency of [0,75]){
 const dir=await mkdtemp('/private/tmp/zw-ui-background-');
 const data=join(dir,'data'),rpc=join(dir,'rpc');await mkdir(data);await mkdir(rpc);
 const wallpaper=join(data,'background.png');
 await writeFile(wallpaper,Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAJ0lEQVR4nGPQcksBoiq3aUCEzGbAKVFVkQJEWhXTgAiZjVuCDnYAAMasS4GfPJd/AAAAAElFTkSuQmCC','base64'));
 await writeFile(join(data,'config.toml'),`[ui]\ntheme="gruvbox-dark"\n[ui.materials]\nblur_px=24\n[ui.materials.background]\nenabled=true\npath="${wallpaper}"\ntransparency=${transparency}\n[updates]\nauto_check=false\n`);
 process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
 const log=await open(join(out,`T${transparency}.log`),'w');
 const app=spawn(join(prefix,'bin/zerowork'),[],{env:{...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1',ZENIT_E2E_ISOLATE_KEYBOARD:'1'},stdio:['ignore',log.fd,log.fd]});
 const ended=new Promise<void>(done=>app.once('close',()=>done()));
 const record:any={transparency,status:'running',captures:[]};cases.push(record);
 const capture=async(name:string)=>{
  const frame=await visible('wizard.window');
  const nodes={window:{rect:frame.rect,bg_rgba:frame.bg_rgba},steps:await visible('wizard.steps')};
  const stem=`T${transparency}-${name}`;
  assert((await h.screenshot(join(out,stem+'.png'))).ok);
  await writeFile(join(out,stem+'.json'),JSON.stringify(nodes,null,2));
  record.captures.push(stem);
 };
 const openEditor=async()=>{
  await h.key('t',{cmd:true});await click('session.menu.new_profile');await visible('wizard.name');
  const id=await editorWindow();assert(id&&!seenEditors.has(id),'each open creates a new native editor window');seenEditors.add(id);
 };
 const seenEditors=new Set<string>();
 // The Harness binds to the editor window while it is open (it is the second native window).
 const editorWindow=async()=>{const all=(await h.windows()).windows.filter((w:any)=>!w.closing);return all.length===2?all.find((w:any)=>w.bound)?.window_id??null:null;};
 const closeEditor=async()=>{
  assert(!(await h.query('wizard.close')).some(shown),'native editor window has no in-window close button');
  await h.key('escape');
  // Gone = one native window left, bound again, and the main window answers queries.
  await h.waitFor(async()=>{const all=(await h.windows()).windows;if(all.length!==1||!all[0].bound||all[0].closing)return null;const gone=await h.query('wizard.window');return Array.isArray(gone)&&gone.length===0||null;},10000);
  await visible('toolbar.settings');
 };
 // Themed surfaces of the editor window: window ground, the header's native protocol Select, a stepper hairline.
 // Native controls ease their colors in after mount (the Select trigger takes a few frames): read until two
 // consecutive samples 150 ms apart agree.
 const sample=async()=>{const out:any={};for(const id of ['wizard.window','wizard.protocol','wizard.steps.connector.0']){const n=await visible(id);assert(typeof n.bg_rgba==='string'&&n.bg_rgba.length>0,id+' paints a background');out[id]=n.bg_rgba;}return out;};
 const surfaces=async()=>{let last='';return h.waitFor(async()=>{const now=await sample(),key=JSON.stringify(now);if(key!==last){last=key;await h.sleep(150);return null;}return now;},5000);};
 const changeTheme=async(id:string)=>{
  await closeEditor();await nav.toPane('settings.appearance.themes');await nav.reveal('settings.theme.strip');
  for(let i=0;i<16;i++){
   const strip=await visible('settings.theme.strip');
   const tile=(await h.query('settings.theme.'+id)).find(shown);
   assert(tile,'theme tile '+id);
   if(tile.rect.x>=strip.rect.x&&tile.rect.x+tile.rect.w<=strip.rect.x+strip.rect.w+1)break;
   // Scroll the tile toward the strip's center (1 scroll unit = 1 pt), then let the strip come to rest.
   const off=(strip.rect.x+strip.rect.w/2)-(tile.rect.x+tile.rect.w/2);
   await h.scrollAt(strip.rect.x+strip.rect.w/2,strip.rect.y+strip.rect.h/2,Math.sign(off)*Math.min(700,Math.abs(off)),0);await h.sleep(150);
  }
  {let last:any=null;const tile=await h.waitFor(async()=>{const n=(await h.query('settings.theme.'+id)).find(shown);if(!n)return null;const same=last&&Math.abs(last.rect.x-n.rect.x)<.01;last=n;if(!same){await h.sleep(80);return null;}return n;},5000);const strip=await visible('settings.theme.strip');assert(tile.rect.x>=strip.rect.x&&tile.rect.x+tile.rect.w<=strip.rect.x+strip.rect.w+1,'theme tile '+id+' scrolled into the strip');}
  await click('settings.theme.'+id);await click('settings.save');
  await nav.saved();
  await nav.close();await openEditor();
 };
 try{
  await h.waitForServerReady(60000);await h.resizeWindow(1440,900);await openEditor();
  {const frame=await visible('wizard.window');assert.equal(frame.rect.w,720);assert.equal(frame.rect.h,640);} // wizard.zig window_spec
  const initial=await surfaces();
  await capture('gruvbox-initial');
  await changeTheme('light');const light=await surfaces();
  for(const id of Object.keys(initial))assert.notEqual(light[id],initial[id],id+' repaints for the light theme');
  await capture('light-refreshed');
  await changeTheme('gruvbox-dark');assert.deepEqual(await surfaces(),initial,'editor surfaces return to the gruvbox-dark colors');
  record.surfaces={'gruvbox-dark':initial,light};
  await capture('gruvbox-refreshed');
  await click('wizard.group.pick');await h.sleep(250);await capture('gruvbox-group-menu');
  await h.key('escape');
  // The Harness is bound to the editor window here, so this resizes the editor itself (window_spec min 600×420).
  await h.resizeWindow(860,480);await h.sleep(250);{const frame=await visible('wizard.window');assert.equal(frame.rect.w,860);assert.equal(frame.rect.h,480);}await capture('gruvbox-compact');
  await click('wizard.protocol');await click('wizard.protocol.sftp');await visible('wizard.name');
  await capture('sftp-compact');
  await click('wizard.protocol');await click('wizard.protocol.bmc_ikvm');await visible('bmc.editor.name');
  await capture('bmc-compact');
  record.status='passed';
 }catch(error){record.status='failed';record.error=String(error);await h.screenshot(join(out,`T${transparency}-failure.png`)).catch(()=>{});throw error;}
 finally{
  if(app.exitCode===null&&app.signalCode===null)app.kill('SIGTERM');await ended;
  if(app.pid)await cleanupOwnedBridgeDirectories(app.pid);
  await log.close();await rm(dir,{recursive:true,force:true});
  // regression/run.ts reads the top-level `status`.
  await writeFile(join(out,'report.json'),JSON.stringify({status:cases.length===2&&cases.every(c=>c.status==='passed')?'passed':cases.some(c=>c.status==='failed')?'failed':'running',cases},null,2));
 }
}
console.log(JSON.stringify({cases}));
