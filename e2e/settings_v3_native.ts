/**
 * V3 settings contract in an isolated real native app, on the two-level
 * Settings window (category overview → subpage; `settings_nav.ts`).
 * Covers: standard pane/row/field geometry, invalid-draft handling, Revert,
 * Save + reopen, every page renders, background toggle independence, font
 * editing/revert, cursor-shape save/restore, compact window field width and
 * the fixed Save Bar while the content scrolls.
 *
 * Usage: node e2e/settings_v3_native.ts <binary> <out> [host]
 */
import assert from 'node:assert/strict';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {resolve,join} from 'node:path';
import {waitFor,key,resizeWindow,screenshot,sleep,scrollAt,inputState} from '../vendor/zenit/e2e/client.ts';
import {settingsNav,launchIsolated,clickLabel,textOf,CATEGORIES,DIRECT} from './settings_nav.ts';
const [argBinary,argOutput]=process.argv.slice(2); assert(argBinary&&argOutput);
const hostOnly=process.argv[4]==='host';
const binary=resolve(argBinary), output=resolve(argOutput);await mkdir(output,{recursive:true});
const report:any={status:'running',runs:[]};
const near=(a:number,b:number,what='')=>assert(Math.abs(a-b)<.6,`${what} ${a} != ${b}`);
for(const theme of ['dark','light']){
 const run=await launchIsolated({binary,out:output,prefix:'zw-settings-v3',theme,config:'font_family="Menlo"\nfont_size=14\n',logName:theme+'.log'});
 const rec:any={theme,pages:[],checks:[],captures:[]};report.runs.push(rec);
 const nav=settingsNav();
 const capture=async(name:string)=>{await sleep(180);const path=join(output,theme+'-'+name+'.png');assert((await screenshot(path)).ok);rec.captures.push(path);};
 const config=()=>readFile(run.config,'utf8');
 try{
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
  for(const page of ['keys','transfer','ai','plugins','notifications','data','appearance']){await nav.toCategory(page);await capture(page+'-standard');rec.pages.push(page);}
  for(const [cat,,subs] of CATEGORIES)for(const [sub,,panes] of subs){await nav.toSub(cat,sub);for(const p of panes)await nav.node(p);}
  for(const [cat,,panes] of DIRECT){await nav.toCategory(cat);for(const p of panes)await nav.node(p);}
  rec.checks.push('every category and subpage renders its panes');
  await nav.toSub('data','actions');await nav.reveal('settings.data.clear_all');await capture('data-actions');
  await nav.toSub('appearance','theme');await nav.reveal('settings.field.fit');await capture('background-off');
  await nav.click('settings.toggle.enabled');await nav.node('settings.field.fit');assert(textOf(await nav.node('settings.appearance.materials.summary')).startsWith('已开启'));
  await nav.click('settings.toggle.enabled');await nav.node('settings.field.fit');assert(textOf(await nav.node('settings.appearance.materials.summary')).startsWith('已关闭'));rec.checks.push('background controls independent of enable; disabled background remains editable');
  await nav.click('settings.field.fit');await nav.click('settings.option.fit.fit');await nav.node('settings.field.fit');await nav.click('settings.revert');
  await nav.toSub('appearance','font');await nav.node('settings.field.font_size');await capture('font');await nav.edit('settings.field.font_size','18');await nav.click('settings.revert');await sleep(200);assert.equal((await inputState('settings.field.font_size')).buffer,'14');rec.checks.push('font inline editing and revert');
  await nav.reveal('settings.field.cursor_style');// The default shape is 竖线 (bar): pick 下划线 so the draft really changes (H-save: no Save Bar without a change).
  await clickLabel('settings.field.cursor_style','下划线');await nav.click('settings.save');await waitFor(async()=> (await config()).includes('cursor_style = "underline"')?true:null,10000);
  await nav.toSub('appearance','theme');await nav.reveal('settings.font.preview');await capture('cursor-underline-preview');
  await nav.toSub('appearance','font');await clickLabel('settings.field.cursor_style','方块');await nav.click('settings.save');await waitFor(async()=> (await config()).includes('cursor_style = "block"')?true:null,10000);rec.checks.push('cursor Tabs selection/save/restore and preview reachable');
  await nav.toSub('ssh','connection');await resizeWindow(860,480);await sleep(300);
  const compact=await nav.node('settings.field.keepalive_sec');rec.compact={field:compact.rect};
  // Compact windows keep the native control width (180): the legacy 168 tweak was dropped by user decision (G30).
  near(compact.rect.w,180,'compact field w');near(compact.rect.h,32,'compact field h');
  // H-save: the Save Bar only exists with unsaved changes; make one, check it stays put while scrolling, revert.
  await nav.edit('settings.field.keepalive_sec','46');
  const footer=(await nav.node('settings.footer')).rect;await capture('ssh-compact');const v=await nav.node('settings.viewport');await scrollAt(v.rect.x+v.rect.w/2,v.rect.y+v.rect.h/2,0,-650);await sleep(250);near((await nav.node('settings.footer')).rect.y,footer.y,'footer y');await capture('ssh-compact-scrolled');
  await nav.click('settings.revert');await waitFor(async()=>(await nav.visible('settings.footer'))?null:true,5000);rec.checks.push('compact field keeps 180, content scroll and fixed Save Bar (dirty page; reverted)');
  await resizeWindow(1440,900);await sleep(250);await nav.toSub('ssh','connection');near((await nav.node('settings.field.keepalive_sec')).rect.w,180,'restored field w');rec.checks.push('resize restores standard field width');
  rec.status='passed_pending_pixel_review';
 }catch(e){rec.status='failed';rec.error=String(e);await capture('failure').catch(()=>{});throw e;}finally{await writeFile(join(output,'report.json'),JSON.stringify(report,null,2));await run.stop();}
}
report.status='passed_pending_pixel_review';await writeFile(join(output,'report.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report));
