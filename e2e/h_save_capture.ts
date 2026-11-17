/**
 * H-save 第二轮验收对照图（人工验收反馈 4：设置的保存逻辑）。一次性采集脚本，基于 `settings_nav.ts` 的隔离启动与导航。
 * 每个主题采集（SSH 与网络 › 连接）：
 *   (a) 干净页：没有 Save Bar，“恢复默认…”在正文底部、不可点（值都是默认值）；
 *   (b) 改一个字段后：Save Bar 出现（“未保存”，撤销 / 保存可点）；
 *   (c) 保存成功：Save Bar 消失，原生 Toast“设置已保存”；
 *   (d) 非默认页：“恢复默认…”可点；点了先弹“恢复默认设置？”（原生 Modal）；
 *   (e) 带着改动切页：弹“未保存的设置”（原生 Modal，焦点在“继续编辑”上）；
 *   (f) 校验无效：Save Bar 显示“有设置需要修正”，字段下有行内提示；
 *   (g) 保存失败（数据目录临时只读）：Save Bar 显示“保存失败，草稿已保留”，原生错误 Toast 给原因。
 *
 * Usage: node e2e/h_save_capture.ts <zerowork binary (test-mode)> <out dir> [light|dark]
 */
import assert from 'node:assert/strict';
import {join,resolve} from 'node:path';
import {writeFile,readFile,chmod} from 'node:fs/promises';
import * as h from '../vendor/zenit/e2e/client.ts';
import {launchIsolated,settingsNav,shown,textOf} from './settings_nav.ts';

const [binaryArg,outArg,theme='light']=process.argv.slice(2);
if(!binaryArg||!outArg)throw new Error('usage: h_save_capture.ts <binary> <out> [light|dark]');
const out=resolve(outArg);
const run=await launchIsolated({binary:resolve(binaryArg),out,prefix:'zw-h-save-capture',theme,logName:`app-${theme}.log`});
const nav=settingsNav();
const report:any={status:'running',theme,shots:[] as string[],checks:[] as string[]};
let win:string|undefined;
const shot=async(name:string,park=true)=>{if(park){await h.mouseMove(2,2).catch(()=>{});await h.sleep(250);}const path=join(out,`${theme}-${name}.png`);assert((await h.screenshot(path,win)).ok,name);report.shots.push(path);};
const footerShown=async()=>(await h.query('settings.footer')).some(shown);
const footerText=async()=>textOf((await h.query('settings.footer.state')).find(shown)).trim();
const treeHas=async(text:string)=>JSON.stringify(await h.tree()).includes(text);
/** Harness 的 query 没有 disabled 字段：按钮的可用性看 tree 里的 a11y（找不到时返回 null，不断言）。 */
const disabledOf=async(id:string):Promise<boolean|null>=>{const find=(n:any):any=>{if(n?.test_id===id)return n;for(const c of n?.children??[]){const f=find(c);if(f)return f;}return null;};const n=find(await h.tree());if(!n)return null;const d=n.disabled??n.a11y?.disabled;return typeof d==='boolean'?d:null;};
const confirmation=()=>nav.node('settings.confirmation',6000);
const noConfirmation=()=>h.waitFor(async()=>(await h.query('settings.confirmation')).some(shown)?null:true,6000);

try{
 await h.resizeWindow(1440,900);
 await nav.open();
 win=(await h.windows()).windows.find(w=>w.bound&&!w.closing)?.window_id;
 await nav.toSub('ssh','connection');
 // (a) 干净页。
 await nav.node('settings.field.keepalive_sec');
 assert(!(await footerShown()),'clean page has no Save Bar');
 assert(!(await treeHas('所有更改已保存')),'no standing “all changes saved”');
 await nav.reveal('settings.reset');
 const resetClean=await disabledOf('settings.reset');
 if(resetClean!==null)assert.equal(resetClean,true,'reset defaults disabled on a page at its defaults');
 await shot('a-clean');
 report.checks.push(`clean page: no Save Bar, no “所有更改已保存”; reset defaults shown${resetClean===null?' (disabled state: see component test)':', disabled'}`);
 // (b) 改一个字段。
 await nav.edit('settings.field.keepalive_sec','45');
 await h.key('tab');
 await h.waitFor(async()=>(await footerShown())||null,5000);
 assert.equal(await footerText(),'未保存');
 await shot('b-dirty');
 report.checks.push('one edit: Save Bar appears with 未保存');
 // (c) 保存成功：Save Bar 消失，Toast。
 await nav.click('settings.save');
 await h.waitFor(async()=>(await treeHas('设置已保存'))||null,5000);
 await h.waitFor(async()=>(await footerShown())?null:true,5000);
 await shot('c-saved-toast');
 assert((await readFile(run.config,'utf8')).includes('keepalive_sec = 45'));
 report.checks.push('save: config written, Save Bar gone, native toast “设置已保存”');
 await h.sleep(2600);
 // (d) 非默认页：恢复默认可点，先确认。
 await nav.reveal('settings.reset');
 const resetDirty=await disabledOf('settings.reset');
 if(resetDirty!==null)assert.equal(resetDirty,false,'reset defaults enabled when the page differs from defaults');
 await shot('d-reset-enabled');
 await nav.click('settings.reset');
 const resetBox=await confirmation();
 assert(textOf(resetBox).includes('恢复默认'),'reset confirmation');
 await h.sleep(400);
 await shot('d-reset-confirm');
 await nav.click('settings.confirmation.cancel');await noConfirmation();
 assert(!(await footerShown()),'cancel keeps the page clean');
 report.checks.push('non-default page: reset defaults enabled and asks first (native Modal); cancel changes nothing');
 // (e) 带着改动切页：未保存确认，焦点在“继续编辑”。
 await nav.edit('settings.field.keepalive_sec','50');
 await h.key('tab');
 await h.waitFor(async()=>(await footerShown())||null,5000);
 await nav.click('settings.nav.notifications');
 const leave=await confirmation();
 assert(textOf(leave).includes('离开前要保存吗'),'leave confirmation text');
 await h.sleep(400);
 const focus:any=await h.focused();
 report.focused_in_confirmation=focus?.test_id??null;
 assert.equal(focus?.test_id,'settings.confirmation.cancel','focus is inside the dialog on 继续编辑');
 await shot('e-leave-confirm');
 await nav.click('settings.confirmation.cancel');await noConfirmation();
 await nav.waitTitle('连接');
 report.checks.push('leaving with unsaved changes asks (native Modal), focus on 继续编辑, cancel stays on the page');
 // (f) 校验无效。
 await nav.edit('settings.field.keepalive_sec','abc');
 await h.key('tab');
 await h.waitFor(async()=>(await footerText())==='有设置需要修正'||null,5000);
 await nav.node('settings.error.keepalive_sec');
 await shot('f-invalid');
 report.checks.push('invalid input: Save Bar says 有设置需要修正, inline field error');
 // (g) 保存失败：数据目录临时只读。
 await nav.edit('settings.field.keepalive_sec','55');
 await h.key('tab');
 await h.waitFor(async()=>(await footerText())==='未保存'||null,5000);
 await chmod(run.data,0o500);
 try{
  await nav.click('settings.save');
  await h.waitFor(async()=>(await footerText())==='保存失败，草稿已保留'||null,8000);
  await h.waitFor(async()=>(await treeHas('保存失败：'))||null,5000);
  await shot('g-save-failed');
 }finally{await chmod(run.data,0o700);}
 assert(!(await readFile(run.config,'utf8')).includes('keepalive_sec = 55'));
 report.checks.push('save failure: Save Bar says 保存失败，草稿已保留, native error toast with the reason, config unchanged');
 // 收尾：撤销，回到干净。
 await nav.click('settings.revert');
 await h.waitFor(async()=>(await footerShown())?null:true,5000);
 report.status='passed';
}catch(e){report.status='failed';report.error=String((e as any)?.stack??e);process.exitCode=1;await shot('failure').catch(()=>{});}
finally{await chmod(run.data,0o700).catch(()=>{});await run.stop();await writeFile(join(out,`report-${theme}.json`),JSON.stringify(report,null,2));console.log(JSON.stringify({status:report.status,checks:report.checks.length,error:report.error}));}
