/** SSH, transfer, notification and data settings transactions in real native windows,
 * on the two-level Settings window (category overview → subpage; `settings_nav.ts`).
 * Pane folding no longer exists, so the former collapse/expand steps are gone. */
import assert from 'node:assert/strict';
import {mkdir,writeFile,readFile} from 'node:fs/promises';
import {resolve,join} from 'node:path';
import {waitFor,key,resizeWindow,screenshot,sleep,scrollAt,inputState} from '../vendor/zenit/e2e/client.ts';
import {settingsNav,launchIsolated,textOf} from './settings_nav.ts';
const [argBinary,argOutput]=process.argv.slice(2); assert(argBinary&&argOutput);
const hostOnly=process.argv[4]==='host';
const binary=resolve(argBinary), output=resolve(argOutput);await mkdir(output,{recursive:true});
const report:any={status:'running',runs:[]};
const near=(a:number,b:number,what='')=>assert(Math.abs(a-b)<.6,`${what} ${a} != ${b}`);
for(const theme of ['dark','light']){
 const run=await launchIsolated({binary,out:output,prefix:'zw-settings-other-v3',theme,config:'font_family="Menlo"\nfont_size=14\n',logName:theme+'.log'});
 const rec:any={theme,pages:[],checks:[],captures:[]};report.runs.push(rec);
 const nav=settingsNav();
 const capture=async(name:string)=>{await sleep(180);const path=join(output,theme+'-'+name+'.png');assert((await screenshot(path)).ok);rec.captures.push(path);};
 const config=()=>readFile(run.config,'utf8');
 try{
  assert.equal(Number(JSON.parse(await readFile(join(run.rpc,'owner.json'),'utf8')).pid),run.app.pid);
  await resizeWindow(1440,900);await nav.open();await nav.toSub('ssh','connection');
  const header=await nav.node('settings.ssh.connection.header'), row=await nav.node('settings.row.keepalive_sec'), field=await nav.node('settings.field.keepalive_sec'),card=await nav.node('settings.ssh.connection');
  rec.geometry={header:header.rect,row:row.rect,field:field.rect,card:card.rect};
  // Pane header 22 (`pane_header`), row 52 + divider, Select 180 × 32 (`s4goQb`), pane body inset 14.
  near(header.rect.h,22,'pane header');near(row.rect.h,53,'row');near(field.rect.w,180,'field w');near(field.rect.h,32,'field h');near(field.rect.x+field.rect.w,card.rect.x+card.rect.w-14,'field right inset');
  assert.equal(textOf(await nav.node('settings.ssh.connection.summary')),'连接保活、超时与终端类型');await capture('ssh-standard');rec.checks.push('standard pane/header/row/field contract');
  if(hostOnly){const content=(await nav.node('settings.viewport')).rect;assert(card.rect.x>=content.x&&card.rect.x+card.rect.w<=content.x+content.w,'pane inside content');rec.status='passed_pending_pixel_review';continue;}
  await nav.edit('settings.field.keepalive_sec','70000');assert.equal((await inputState('settings.field.keepalive_sec')).buffer,'70000');await nav.node('settings.error.keepalive_sec');await key('escape');await sleep(200);assert.equal((await inputState('settings.field.keepalive_sec')).buffer,'30');rec.checks.push('invalid raw retained and Escape restores valid draft');
  await nav.edit('settings.field.keepalive_sec','44');await nav.click('settings.revert');await sleep(300);assert.equal((await inputState('settings.field.keepalive_sec')).buffer,'30');rec.checks.push('outer revert');
  await nav.edit('settings.field.keepalive_sec','44');await nav.click('settings.save');await waitFor(async()=> (await config()).includes('keepalive_sec = 44')?true:null,10000);
  await nav.close();await nav.open();await nav.toSub('ssh','connection');assert.equal((await inputState('settings.field.keepalive_sec')).buffer,'44');rec.checks.push('save and reopen actual config');
  await nav.toField('reconnect_backoff');await nav.edit('settings.field.reconnect_backoff','1, 3, 5, 8, 13');
  await nav.click('settings.save');await waitFor(async()=> (await config()).includes('reconnect_backoff = [1,3,5,8,13]')?true:null,10000);
  await capture('ssh-backoff-comma-list');rec.checks.push('prototype comma-list backoff edits and persists legacy TOML array');
  for(const [page,field,value] of [['transfer','shared_pacing_kbps','4096'],['notifications','quiet_hours','23:00-07:00'],['data','retention_days','21']]){
   await nav.toCategory(page);await capture(page+'-standard');
   await nav.toField(field);
   const initial=(await inputState('settings.field.'+field)).buffer;
   await nav.edit('settings.field.'+field,value);await capture(page+'-edited');
   await nav.click('settings.revert');await nav.reveal('settings.field.'+field);
   assert.equal((await inputState('settings.field.'+field)).buffer,initial);
   await nav.edit('settings.field.'+field,value);await nav.click('settings.save');
   await waitFor(async()=> (await config()).includes(field+' = '+(field==='quiet_hours'?'"'+value+'"':value))?true:null,10000);
   // H-save: saved → no Save Bar; dirty the page again so the floating Save Bar exists for the compact-scroll check, then revert.
   await waitFor(async()=>(await nav.visible('settings.footer'))?null:true,5000);
   await resizeWindow(860,480);await sleep(250);await nav.edit('settings.field.'+field,initial);await capture(page+'-compact');
   const viewport=(await nav.node('settings.viewport')).rect,footerY=(await nav.node('settings.footer')).rect.y;
   await scrollAt(viewport.x+viewport.w/2,viewport.y+viewport.h/2,0,-900);await sleep(200);near((await nav.node('settings.footer')).rect.y,footerY,'footer y');await capture(page+'-compact-scrolled');
   await nav.click('settings.revert');await waitFor(async()=>(await nav.visible('settings.footer'))?null:true,5000);
   await resizeWindow(1440,900);await sleep(250);rec.checks.push(page+' edit/revert/save/compact scroll');
  }
  await nav.toCategory('keys');await capture('keys-standard');await resizeWindow(860,480);await capture('keys-compact');await resizeWindow(1440,900);
  await nav.toCategory('plugins');await capture('plugins-standard');await resizeWindow(860,480);await capture('plugins-compact');await resizeWindow(1440,900);
  await nav.toSub('ssh','connection');await resizeWindow(860,480);await sleep(300);const compact=await nav.node('settings.field.keepalive_sec');
  // Compact windows keep the native control width (180): the legacy 168 tweak was dropped by user decision (G30).
  near(compact.rect.w,180,'compact field w');near(compact.rect.h,32,'compact field h');await nav.edit('settings.field.keepalive_sec','46');const footer=(await nav.node('settings.footer')).rect;await capture('ssh-compact');const v=await nav.node('settings.viewport');await scrollAt(v.rect.x+v.rect.w/2,v.rect.y+v.rect.h/2,0,-650);await sleep(250);near((await nav.node('settings.footer')).rect.y,footer.y,'footer y');await capture('ssh-compact-scrolled');await nav.click('settings.revert');await waitFor(async()=>(await nav.visible('settings.footer'))?null:true,5000);rec.checks.push('compact field keeps 180, content scroll and fixed Save Bar (dirty page; H-save: clean pages have none)');
  await resizeWindow(1440,900);await sleep(250);await nav.toSub('ssh','connection');near((await nav.node('settings.field.keepalive_sec')).rect.w,180,'restored field w');rec.checks.push('resize restores standard field width');
  rec.status='passed_pending_pixel_review';
 }catch(e){rec.status='failed';rec.error=String(e);await capture('failure').catch(()=>{});throw e;}finally{await writeFile(join(output,'report.json'),JSON.stringify(report,null,2));await run.stop();}
}
report.status='passed_pending_pixel_review';await writeFile(join(output,'report.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report));
