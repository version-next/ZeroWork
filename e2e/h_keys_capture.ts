/**
 * One-off review capture for human feedback round 1, item 7 (shortcut editing; F-set-panes-B).
 * Captures the Settings › 快捷键 page in each interaction state, light and dark:
 *   rest · hover (tooltip) · recording (⌘ held) · conflict (⌘C → 复制) · invalid (⌃⌘X) · modified (⌘⇧K, 未保存 + reset)
 *   · reset (tooltip on the per-row reset button) · and the 关于与更新 page for reference.
 * Usage: node e2e/h_keys_capture.ts <zerowork binary> <output dir>
 * Runs isolated (temp ZEROWORK_DATA_DIR, [updates] auto_check=false, background / isolated pointer).
 */
import assert from 'node:assert/strict';
import {resolve,join} from 'node:path';
import {writeFile} from 'node:fs/promises';
import * as h from '../vendor/zenit/e2e/client.ts';
import {launchIsolated,settingsNav,textOf,shown} from './settings_nav.ts';

const [binaryArg,outArg]=process.argv.slice(2);
assert(binaryArg&&outArg,'usage: node e2e/h_keys_capture.ts <binary> <out>');
const binary=resolve(binaryArg),out=resolve(outArg);
const report:any={runs:[]};
for(const theme of ['light','dark']){
 const app=await launchIsolated({binary,out,prefix:'zw-h-keys',theme,logName:`${theme}.log`});
 const rec:any={theme,captures:[]};report.runs.push(rec);
 const nav=settingsNav();
 const capture=async(name:string)=>{await h.sleep(260);const path=join(out,`${theme}-${name}.png`);assert((await h.screenshot(path)).ok,name);rec.captures.push(path);};
 const center=async(id:string)=>{const n=await nav.node(id);return [n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2];};
 const away=async()=>{await h.mouseMove(4,4);await h.pointerLeave();await h.sleep(200);};
 try{
  await h.resizeWindow(1280,860);
  await nav.toCategory('keys');
  await nav.node('settings.key.new_tab');
  await away();await capture('rest');
  const [x,y]=await center('settings.key.new_tab');
  await h.mouseMove(x,y);await h.sleep(750);await nav.node('settings.key.tooltip.new_tab');await capture('hover');
  await nav.click('settings.key.new_tab');await away();
  await h.key('left_super',{cmd:true});await h.sleep(120);
  assert(textOf(await nav.node('settings.key.row.new_tab')).includes('按下新快捷键'));await capture('recording');
  await h.key('c',{cmd:true});
  assert(textOf(await nav.node('settings.key.error.new_tab')).includes('复制'));await nav.node('settings.key.swap.new_tab');await capture('conflict');
  await h.key('x',{cmd:true,ctrl:true});
  assert(textOf(await nav.node('settings.key.error.new_tab')).includes('Control'));await capture('invalid');
  await h.key('k',{cmd:true,shift:true});
  await nav.node('settings.key.unsaved.new_tab');await nav.node('settings.key.reset.new_tab');
  assert(textOf(await nav.node('settings.key.new_tab')).includes('K'));await away();await capture('modified');
  const [rx,ry]=await center('settings.key.reset.new_tab');
  await h.mouseMove(rx,ry);await h.sleep(750);await nav.node('settings.key.reset.new_tab.tooltip');await capture('reset');
  // The modified binding is an unsaved change on this page: leaving asks first (H-save); discard it.
  await away();await nav.click('settings.nav.updates');
  await nav.node('settings.confirmation');await nav.click('settings.confirmation.discard');await nav.gone('settings.confirmation');
  await nav.waitTitle('关于与更新');await nav.node('settings.updates.version');await capture('updates');
  rec.status='captured';
 }catch(e){rec.status='failed';rec.error=String(e);await capture('failure').catch(()=>{});throw e;}
 finally{await app.stop();}
}
report.status=report.runs.every((r:any)=>r.status==='captured')?'captured':'failed';
await writeFile(join(out,'report.json'),JSON.stringify(report,null,1));
console.log(JSON.stringify(report,null,1));
