/** V3 inline theme card acceptance; ordinary isolated config, real Metal pixels. */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdir, mkdtemp, open, readFile, writeFile, rm, realpath } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
const prefix=process.env.ZW_APPEARANCE_TEST_PREFIX??'/tmp/zw-appearance-align-build';
const {waitForServerReady,waitFor,query,clickTestId,resizeWindow,screenshot,sleep,scrollAt,key,request}=await import(join(prefix,'share/zenit/harness/client.ts'));
const {settingsNav}=await import('./settings_nav.ts');
// Two-level settings (settings_nav.ts): 外观与主题 › 主题; no close button (Cmd+W asks first while a draft exists).
const nav=settingsNav();
const out=process.argv[2];assert(out,'output directory required');await mkdir(out,{recursive:true});
const isolated=await realpath(await mkdtemp(join(tmpdir(),'zw-theme-inline-'))),rpc=join(isolated,'rpc'),data=join(isolated,'data');await mkdir(rpc);await mkdir(data);
const config=join(data,'config.toml');await writeFile(config,'[meta]\nconfig_revision = 1\n[ui]\ntheme = "dark"\n');
// The regression runner's isolation guard appends [updates] auto_check=false to configs a script writes: compare with the file as written.
const baseline=await readFile(config,'utf8');
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const log=await open(join(out,'app.log'),'w');
const child=spawn(join(prefix,'bin/zerowork'),[],{env:{...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_ISOLATE_POINTER:'1',ZENIT_E2E_BACKGROUND:'1',ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0'},stdio:['ignore',log.fd,log.fd]});
child.once('error',e=>console.error('app launch error',e));child.once('exit',(code,signal)=>console.log('app exit',code,signal));const ended=new Promise<void>(r=>child.once('close',()=>r()));
const report:{status:string;checks:string[];captures:string[];error?:string;limits:string[]}={status:'running',checks:[],captures:[],limits:['Native file picker and imported theme deletion are not covered.','Synthetic harness events do not establish real IME or physical keyboard support.']};
const shown=(n:any)=>n.hidden!==true&&n.visible!==false&&(n.effective_opacity??1)>0&&n.rect.w>0&&n.rect.h>0;
const node=async(id:string)=>await waitFor(async()=>(await query(id)).find(shown)??null);
const click=async(id:string)=>{assert((await clickTestId(id)).ok,id);await sleep(80);};
// Saved / clean = the floating Save Bar hides (was the persistent footer state "已保存").
const clean=async()=>await nav.saved();
const requestClose=async()=>{await nav.node('settings.panel');await key('w',{cmd:true});await sleep(150);};
const capture=async(name:string)=>{const path=join(out,name+'.png');await screenshot(path);report.captures.push(path);const ids=['settings.viewport','settings.footer','settings.appearance.themes','settings.theme.strip','settings.theme.dark','settings.theme.light','settings.theme.sauber','settings.theme.ayu-dark'];await writeFile(join(out,name+'.json'),JSON.stringify(Object.fromEntries(await Promise.all(ids.map(async id=>[id,await query(id)]))),null,2));};
let failure:unknown;
try{
 await waitForServerReady();assert((await resizeWindow(1440,900)).ok);await nav.toSub('appearance','theme');
 for(const id of ['settings.theme.library.open','settings.theme.library.close','settings.theme.grid'])assert.equal((await query(id)).filter(shown).length,0,id);
 // Theme card (J91kn, appearance.yss theme_strip / ThemeCard / swatch): strip 81 high, card 150×81, swatch full card width × 58 (was 75 / 150×75 / 138×42).
 let strip=await node('settings.theme.strip');assert.equal(strip.rect.h,81);let tile=await node('settings.theme.dark');assert.equal(tile.rect.w,150);assert.equal(tile.rect.h,81);assert(tile.children?.some((n:any)=>n.rect?.h===58&&n.rect?.w===150),'150×58 swatch');await capture('01-dark-standard');
 await click('settings.theme.light');assert.equal(await readFile(config,'utf8'),baseline);await requestClose();await click('settings.confirmation.cancel');await node('settings.theme.strip');await requestClose();await click('settings.confirmation.discard');await nav.gone('settings.panel');assert.equal(await readFile(config,'utf8'),baseline);
 // The preferences window retires at the runtime's next safe boundary: reopen only after it is gone (as appearance.ts).
 await waitFor(async()=>(await request('GET','/windows')).windows.length===1||null);await nav.toSub('appearance','theme');await click('settings.theme.light');await click('settings.save');await clean();assert.match(await readFile(config,'utf8'),/theme = "light"/);await capture('02-light-standard');
 await click('settings.theme.sauber');await click('settings.save');await clean();assert.match(await readFile(config,'utf8'),/theme = "sauber"/);await capture('03-sauber-standard');
 assert((await resizeWindow(860,480)).ok);await sleep(180);strip=await node('settings.theme.strip');tile=await node('settings.theme.dark');assert.equal(tile.rect.w,150);assert.equal(tile.rect.h,81);const compactViewport=await node('settings.viewport');await capture('04-sauber-minimum');
 await scrollAt(strip.rect.x+strip.rect.w/2,strip.rect.y+strip.rect.h/2,-6000,0);await sleep(180);let last=await node('settings.theme.ayu-dark');assert(last.rect.x>=strip.rect.x&&last.rect.x+last.rect.w<=strip.rect.x+strip.rect.w+1,'last theme in strip viewport');await click('settings.theme.ayu-dark');const footer=await node('settings.footer');assert(footer.rect.y+footer.rect.h<=compactViewport.rect.y+compactViewport.rect.h+1,'Save Bar floats inside the minimum viewport');await click('settings.save');await clean();assert.match(await readFile(config,'utf8'),/theme = "ayu-dark"/);assert.equal((await query('settings.footer')).filter(shown).length,0,'Save Bar hides after Save (H-save; was: the persistent footer keeps its y)');await capture('05-last-theme-minimum');assert.equal((await node('settings.viewport')).rect.w,compactViewport.rect.w,'theme Save preserves minimum viewport width');assert.equal((await node('settings.viewport')).rect.x,compactViewport.rect.x,'theme Save preserves minimum viewport position');strip=await node('settings.theme.strip');last=await node('settings.theme.ayu-dark');assert(last.rect.x>=strip.rect.x&&last.rect.x+last.rect.w<=strip.rect.x+strip.rect.w+1,'saved selected theme remains visible');await scrollAt(strip.rect.x+strip.rect.w/2,strip.rect.y+strip.rect.h/2,6000,0);await sleep(200);const dark=await node('settings.theme.dark');assert(dark.rect.x>=strip.rect.x&&dark.rect.x+dark.rect.w<=strip.rect.x+strip.rect.w+1,'user can browse away without selection snapping back');await capture('06-manual-browse-away');
 report.checks.push('No legacy library entry/grid; 150×81 tiles, 58px swatch and 81px horizontal viewport','Light draft does not persist; close/cancel/discard preserves saved Dark','Light and Sauber saved through actual settings controls','860×480 retains 150×81 tiles; wheel reaches the last theme; Ayu Dark saves; footer stays fixed');report.status='passed';
}catch(e){failure=e;report.status='failed';report.error=String(e);await capture('failure').catch(()=>{});}finally{if(child.exitCode===null&&child.signalCode===null)child.kill('SIGTERM');await ended;await log.close();await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));await rm(isolated,{recursive:true,force:true});}
console.log(report.status+': '+join(out,'report.json'));if(failure)throw failure;
