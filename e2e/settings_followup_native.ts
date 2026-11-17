import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import {nativeThemeData} from './native_theme_data.mjs';
/** Settings and themes in a real isolated native application using file RPC. */
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {spawn} from 'node:child_process';
import {mkdtemp,mkdir,writeFile,readFile,realpath,open} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {resolve,join} from 'node:path';
import {waitForServerReady,waitFor,query,clickTestId,resizeWindow,screenshot,sleep,scrollAt,request} from '../vendor/zenit/e2e/client.ts';
import {settingsNav} from './settings_nav.ts';
// Two-level settings (settings_nav.ts): category overview → subpage; no close button (Cmd+W); the Save Bar only shows with a draft.
const nav=settingsNav();
const [argBinary,argOutput]=process.argv.slice(2);assert(argBinary&&argOutput);
const binary=resolve(argBinary),output=resolve(argOutput);await mkdir(output,{recursive:true});
const root=await realpath(await mkdtemp(join(tmpdir(),'zw-settings-followup-'))),rpc=join(root,'rpc'),data=join(root,'data');await mkdir(rpc);await mkdir(data);
await writeFile(join(data,'config.toml'),'[ui]\ntheme = "dark"\n');
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const log=await open(join(output,'app.log'),'w');
const app=spawn(binary,[],{env:{...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_ISOLATE_POINTER:'1',ZENIT_E2E_BACKGROUND:'1',ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0'},stdio:['ignore',log.fd,log.fd]});const ended=new Promise(r=>app.once('close',r));
const report:any={status:'running',binary,binary_sha256:createHash('sha256').update(await readFile(binary)).digest('hex'),pid:app.pid,checks:[],captures:[],limits:['Harness interactions do not verify physical keyboard/IME or native OS pickers.','ANSI mapping is validated by theme registry test; these screenshots verify application of UI palettes.']};
const shown=(n:any)=>n.visible!==false&&n.hidden!==true&&n.rect.w>0&&n.rect.h>0&&(n.effective_opacity??1)>0;
const node=async(id:string)=>waitFor(async()=> (await query(id)).find(shown)??null);
const click=async(id:string)=>{
 if(id.startsWith('settings.theme.')&&!['settings.theme.remove.current'].includes(id)){
  for(let i=0;i<12;i++){const n=await node(id),v=await node('settings.theme.strip');if(n.rect.x>=v.rect.x&&n.rect.x+n.rect.w<=v.rect.x+v.rect.w)break;await scrollAt(v.rect.x+v.rect.w/2,v.rect.y+v.rect.h/2,n.rect.x<v.rect.x?400:-400,0);await sleep(100);}
 }
 await node(id);assert((await clickTestId(id)).ok,id);
};
const capture=async(name:string)=>{await sleep(250);await screenshot(join(output,name+'.png'));report.captures.push(name);};
try{
 await waitForServerReady();await nav.toSub('appearance','theme');
 const preset=nativeThemeData;
 for(const id of Object.keys(preset.themes)){
  await nav.pickTheme(id);await nav.saveIfDirty(); // the already-current theme makes no draft (no Save Bar)
  await waitFor(async()=> (await readFile(join(data,'config.toml'),'utf8')).includes('theme = "'+id+'"')?true:null,10000);
  const remove=await node('settings.theme.remove.current');assert.notEqual(remove.focusable,true,'builtin remove disabled');
  await capture('theme-'+id);report.checks.push('select/save/protected '+id);
 }
 await nav.close();await nav.toSub('appearance','theme');await node('settings.theme.ice');report.checks.push('saved ice theme reopens');
 await nav.toSub('data','location');assert.equal((await query('settings.data.open_config_dir')).filter(shown).length,0);await capture('data-readonly');report.checks.push('configuration directory action removed');
 await resizeWindow(860,480);await nav.toCategory('appearance');await capture('appearance-compact');
 await nav.toCategory('data');await capture('data-compact');report.checks.push('860x480 appearance/data visible');
 for(const [width,height] of [[860,480],[1440,900]]){
  await resizeWindow(width,height);await nav.toPane('settings.appearance.materials');await nav.reveal('settings.materials.preview.open');
  // The material preview hides the Settings window and previews over the main window: follow it there (as appearance.ts does).
  await click('settings.materials.preview.open');{const snap=await request('POST','/zerowork/windows',{action:'snapshot'});assert((await request('POST','/zerowork/windows',{action:'select',window:snap.windows[0].window})).ok,'bind main window');}const save=await node('settings.materials.preview.save'),bar=await node('settings.materials.preview.actions');
  assert.equal(save.rect.w,120); // native auto-width W.Button “保存全部设置” + icon (material_preview_bar.yix), was 128
 assert(save.rect.x+save.rect.w<=bar.rect.x+bar.rect.w,'save label fits preview bar');await capture('preview-save-'+width);await click('settings.materials.preview.return');await waitFor(async()=>!(await query('settings.materials.preview.actions')).some(shown)||null,10000);
  {const bound=async()=>(await request('GET','/windows')).windows.find((w:any)=>w.bound)?.window_id;const main=await bound();await clickTestId('toolbar.settings');await waitFor(async()=>(await bound())!==main||null,10000);await node('settings.panel');}
 }
 report.checks.push('preview save 128px and inside bar at860/1440');
 report.status='passed_pending_pixel_review';
}catch(e){report.status='failed';report.error=String(e);await capture('failure').catch(()=>{});throw e;}
finally{await writeFile(join(output,'report.json'),JSON.stringify(report,null,2));if(app.exitCode===null)app.kill('SIGTERM');await ended;await log.close();}
