/**
 * Settings › 快捷键: inline shortcut recording (human feedback round 1, item 7; F-set-panes-B).
 * Same intent as the old recorder-dialog script, rewritten for the inline interaction:
 *   - click a key area → it records in place ("按下新快捷键…"); the window's Escape / ⌘W do not fire while recording;
 *   - Control combos are rejected with a reason; a conflict names the other action and offers 交换 / 取消;
 *   - Escape and 取消 discard the candidate (draft untouched); Tab leaves recording; fixed rows never record;
 *   - a recorded combo changes only the draft (config untouched) until Save; Save persists it, a reopened window shows it;
 *   - per-row 恢复默认 and 交换 persist as well.
 * Usage: node e2e/keybinding_v3_native.ts <zerowork binary> <output dir>
 */
import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {resolve,join} from 'node:path';
import * as h from '../vendor/zenit/e2e/client.ts';
import {launchIsolated,settingsNav,shown} from './settings_nav.ts';
/** Visible text only (hidden keycap slots and prompts are skipped). */
const textOf=(n:any):string=>n?.visible===false?'':[typeof n?.text==='string'?n.text:n?.text?.content??'',...(n?.children??[]).map(textOf)].join('');

const [binaryArg,outputArg]=process.argv.slice(2);assert(binaryArg&&outputArg);
const binary=resolve(binaryArg),output=resolve(outputArg);
const report:any={runs:[],status:'running'};
for(const theme of ['dark','light']){
 const app=await launchIsolated({binary,out:output,prefix:'zw-keybinding-v3',theme,logName:theme+'.log'});
 const rec:any={theme,checks:[],captures:[]};report.runs.push(rec);
 const nav=settingsNav();
 const config=()=>readFile(app.config,'utf8');
 const text=async(id:string)=>textOf(await nav.node(id));
 const visible=async(id:string)=>(await h.query(id)).some(shown);
 const capture=async(name:string)=>{await h.sleep(220);const path=join(output,theme+'-'+name+'.png');assert((await h.screenshot(path)).ok);rec.captures.push(path);};
 const persisted=async(line:string)=>h.waitFor(async()=>(await config()).includes(line)?true:null,10000);
 try{
  await h.resizeWindow(1440,900);
  await nav.toCategory('keys');
  assert.equal(await text('settings.key.new_tab'),'⌘T');
  assert(!(await visible('settings.key.reset.new_tab')));
  // Click → inline recording; the window's Escape / ⌘W stay quiet while recording.
  await nav.click('settings.key.new_tab');
  assert((await text('settings.key.row.new_tab')).includes('按下新快捷键'));await capture('recording');
  rec.checks.push('clicking the key area records in place');
  await h.key('x',{cmd:true,ctrl:true});
  assert((await text('settings.key.error.new_tab')).includes('Control'));await capture('reserved-error');
  await h.key('c',{cmd:true});
  assert((await text('settings.key.error.new_tab')).includes('“复制”'));await nav.node('settings.key.swap.new_tab');await capture('conflict-error');
  await nav.click('settings.key.cancel.new_tab');
  assert.equal(await text('settings.key.new_tab'),'⌘T');assert(!(await visible('settings.key.error.new_tab')));
  rec.checks.push('Control reserved with a reason, conflict names 复制 and offers 交换 / 取消, 取消 discards');
  await nav.click('settings.key.new_tab');await h.key('w',{cmd:true});await h.sleep(200);
  assert(await visible('settings.panel'),'⌘W must not close the window while recording');
  assert((await text('settings.key.error.new_tab')).includes('“关闭页签”'));
  await h.key('escape');await h.sleep(200);
  assert(await visible('settings.panel'),'Escape must not close the window while recording');
  assert.equal(await text('settings.key.new_tab'),'⌘T');assert(!(await visible('settings.key.error.new_tab')));
  rec.checks.push('⌘W is recorded (conflict with 关闭页签), Escape cancels; neither closes the window');
  // Tab leaves recording; fixed rows never record.
  await nav.click('settings.key.new_tab');await h.key('tab');await h.sleep(150);
  assert(!(await text('settings.key.row.new_tab')).includes('按下新快捷键'));rec.tabFocus=await h.focused();
  await nav.click('settings.key.recent_tab');
  assert(!(await text('settings.key.row.recent_tab')).includes('按下新快捷键'));await nav.node('settings.key.fixed.recent_tab');
  rec.checks.push('Tab leaves recording; the fixed row does not record');
  // Record ⇧⌘X (shortcut text follows the macOS menu order ⌃⌥⇧⌘): draft only until Save; Save persists.
  const before=await config();
  await nav.click('settings.key.new_tab');await h.key('x',{cmd:true,shift:true});await h.sleep(150);
  assert.equal(await text('settings.key.new_tab'),'⇧⌘X');await nav.node('settings.key.unsaved.new_tab');await nav.node('settings.key.reset.new_tab');
  assert.equal(await config(),before);await capture('recorded');
  await nav.click('settings.save');await persisted('new_tab = "cmd+shift+x"');
  await h.waitFor(async()=>(await visible('settings.key.unsaved.new_tab'))?null:true,5000);
  rec.checks.push('recording changes the draft only; Save persists new_tab = cmd+shift+x');
  // Per-row reset (back to ⌘T) and a swap (new_tab ⌘C ↔ copy ⌘T), then Save.
  await nav.click('settings.key.reset.new_tab');assert.equal(await text('settings.key.new_tab'),'⌘T');await capture('reset');
  await nav.click('settings.key.new_tab');await h.key('c',{cmd:true});await nav.click('settings.key.swap.new_tab');
  assert.equal(await text('settings.key.new_tab'),'⌘C');assert.equal(await text('settings.key.copy'),'⌘T');await capture('swapped');
  await nav.click('settings.save');await persisted('new_tab = "cmd+c"');assert((await config()).includes('copy = "cmd+t"'));
  rec.checks.push('per-row reset and swap persist after Save');
  // Reopen: the saved map is shown.
  await nav.close();await nav.toCategory('keys');
  assert.equal(await text('settings.key.new_tab'),'⌘C');assert.equal(await text('settings.key.copy'),'⌘T');
  rec.checks.push('reopened settings show the saved shortcuts');
  rec.status='passed';
 }catch(e){rec.status='failed';rec.error=String(e);await capture('failure').catch(()=>{});throw e;}
 finally{await writeFile(join(output,'report.json'),JSON.stringify(report,null,2));await app.stop();}
}
report.status='passed';await writeFile(join(output,'report.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report));
