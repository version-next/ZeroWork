/** Isolated production AI close confirmation (shared confirm(spec) → zenit ConfirmDialog); fixture state only, no provider or app data.
 *
 * Current contract (cabb8e5a, CONSISTENCY_AUDIT #2 / user decision 2): the old anchored 288×106 Popover card is gone; the AI pane's ×
 * opens the shared native confirmation (src/shared/ui/confirm/confirm.zig → vendor/zenit/src/ui/components/modal/confirm.zig):
 * native title bar carrying the question, the consequence as its message, actions row [取消 (secondary)] [结束 AI 会话 (danger)],
 * focus on 取消, Esc / × / mask = 取消, a mask press never reaches what is underneath.
 * Copy: src/features/ai/pane/view/ai_close_confirmation_view.zig (title follows running, confirm label is always `label(.end, " AI 会话")`).
 * Width: ai_close_confirmation_styles.zig `width = 320`. Geometry is asserted as native self-consistency, not hand-made pixels.
 * Usage: node e2e/ai_close_confirmation_component_native.ts <close-confirmation-preview> <out> <theme>
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdir,mkdtemp,open,readFile,writeFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import * as h from '../zig-out/share/zenit/harness/client.ts';
const binary=resolve(process.argv[2]??'zig-out/bin/close-confirmation-preview');
const out=resolve(process.argv[3]??'/private/tmp/zerowork-close-confirmation-evidence/native');
const theme=process.argv[4]??'dark';
assert(['light','dark'].includes(theme),`theme must be light or dark, got ${theme}`);
await mkdir(out,{recursive:true});
const report:any={status:'running',binary,theme,checks:[],measurements:[],shutdown:[],limitations:['Isolated production close component; main app validates stop/history retention separately.']};
// A closed zenit Modal keeps its nodes (suspended layer): the harness reports effective_opacity 0 for them.
const shown=(n:any)=>n&&n.visible!==false&&n.hidden!==true&&(n.effective_opacity??1)>0&&n.rect?.w>0&&n.rect?.h>0;
const visible=(id:string)=>h.waitFor(async()=>(await h.query(id)).find(shown)??null,10000);
const absent=(id:string)=>h.waitFor(async()=>!(await h.query(id)).some(shown)||null,10000);
const click=async(id:string)=>assert((await h.clickTestId(id)).ok,id);
const text=(n:any):string=>n.text??(n.children??[]).map(text).join('');
const result=async()=>text(await visible('ai.close.preview.result'));
const resultHas=(needle:string)=>h.waitFor(async()=>(await result()).includes(needle)||null,5000).catch(async()=>assert.fail(`result lacks ${JSON.stringify(needle)}: ${await result()}`));
const focusedId=async()=>(await h.focused()).test_id;
const save=()=>writeFile(join(out,'report.json'),JSON.stringify(report,null,2));
const near=(a:number,b:number,what:string,eps=0.5)=>assert(Math.abs(a-b)<=eps,`${what}: ${a} vs ${b}`);
const inside=(inner:any,outer:any,what:string)=>assert(inner.x>=outer.x-0.5&&inner.y>=outer.y-0.5&&inner.x+inner.w<=outer.x+outer.w+0.5&&inner.y+inner.h<=outer.y+outer.h+0.5,`${what} ${JSON.stringify(inner)} outside ${JSON.stringify(outer)}`);
const labelsFit=(button:any,what:string)=>{const walk=(n:any)=>{if(n.text&&shown(n))inside(n.rect,button.rect,`${what} label`);(n.children??[]).forEach(walk)};walk(button)};
const RUNNING_TITLE='停止并结束当前会话？',IDLE_TITLE='结束当前会话？',MESSAGE='历史和草稿保留，待处理消息暂停。完成后解绑，连接保持打开。',ACTION='结束 AI 会话',CANCEL='取消',WIDTH=320;
/** Opens the confirmation from the pane's × and checks the native dialog's copy, focus and geometry. */
async function openAndMeasure(window:{w:number,h:number},running:boolean){
 await click('ai.close');
 const panel=await visible('ai.close.confirmation'),title=await visible('ai.close.confirmation.title'),detail=await visible('ai.close.confirmation.detail'),confirm=await visible('ai.close.confirmation.confirm'),cancel=await visible('ai.close.confirmation.cancel');
 assert.equal(panel.component,'ConfirmDialog');
 assert.equal(text(title),running?RUNNING_TITLE:IDLE_TITLE);assert.equal(text(detail),MESSAGE);
 assert.equal(text(confirm),ACTION,'confirm keeps 动词 + 对象 in both states (confirm_label.label(.end, " AI 会话"))');assert.equal(text(cancel),CANCEL);
 assert.equal(await focusedId(),'ai.close.confirmation.cancel','dialog opens on the safe button (initial_focus = .cancel)');
 // Native modal: S.width wide (clamped by the window), centred, entirely inside the window below nothing else.
 near(panel.rect.w,Math.min(WIDTH,window.w),'dialog width = ai_close_confirmation_styles.width');
 near(panel.rect.x+panel.rect.w/2,window.w/2,'dialog centred horizontally');
 inside(panel.rect,{x:0,y:0,w:window.w,h:window.h},'dialog');
 // Parts stack inside the panel: title (native title bar) above the message above the actions row.
 for(const [n,what] of [[title,'title'],[detail,'message'],[confirm,'confirm'],[cancel,'cancel']] as const)inside(n.rect,panel.rect,what);
 assert(title.rect.y+title.rect.h<=detail.rect.y+0.5,'title above message');assert(detail.rect.y+detail.rect.h<=cancel.rect.y+0.5,'message above actions');
 // Actions row (zenit confirm.zig actionsStyle: end-aligned, same row): equal native height, cancel left of confirm,
 // confirm's right edge on the content's right edge (= the message's), labels not clipped.
 near(confirm.rect.h,cancel.rect.h,'native secondary / danger buttons share a height');near(confirm.rect.y,cancel.rect.y,'buttons on one row');
 assert(cancel.rect.x+cancel.rect.w<confirm.rect.x,'cancel before confirm');
 near(confirm.rect.x+confirm.rect.w,detail.rect.x+detail.rect.w,'actions end-aligned with the content edge');
 near(panel.rect.x+panel.rect.w-(confirm.rect.x+confirm.rect.w),detail.rect.x-panel.rect.x,'symmetric content inset');
 labelsFit(confirm,'confirm');labelsFit(cancel,'cancel');
 return {panel,title,detail,confirm,cancel};
}
try{
 const iso=await mkdtemp('/private/tmp/zw-close-popover-'),rpc=join(iso,'rpc');await mkdir(rpc);process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
 const log=await open(join(out,`${theme}.log`),'w');
 const child=spawn(binary,[`--theme=${theme}`],{env:{...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1'},stdio:['ignore',log.fd,log.fd]});
 const ended=new Promise<any>(done=>child.once('exit',(code,signal)=>done({code,signal})));
 try{
  await h.waitForServerReady(10000);assert.equal(Number(JSON.parse(await readFile(join(rpc,'owner.json'),'utf8')).pid),child.pid);
  const window={w:320,h:360};await h.resizeWindow(window.w,window.h);
  await absent('ai.close.confirmation');assert.equal(await result(),'任务正在运行');
  const running=await openAndMeasure(window,true);
  await h.mouseMove(1,1);assert((await h.screenshot(join(out,`${theme}-320-running.png`))).ok);
  await writeFile(join(out,`${theme}-320-running.json`),JSON.stringify(await h.query('ai.close.confirmation'),null,2));
  report.measurements.push({theme,width:window.w,panel:running.panel.rect,title:running.title.rect,detail:running.detail.rect,confirm:running.confirm.rect,cancel:running.cancel.rect});
  // Cancel paths keep the task running: Esc, the 取消 button, a press on the mask (it must not reach the control underneath).
  await h.key('escape');await absent('ai.close.confirmation');await resultHas('confirm 0 · cancel 1');await resultHas('running true');
  await click('ai.close');await visible('ai.close.confirmation');await click('ai.close.confirmation.cancel');await absent('ai.close.confirmation');await resultHas('confirm 0 · cancel 2');await resultHas('running true');
  await click('ai.close');await visible('ai.close.confirmation');
  const toggle=(await h.query('ai.close.preview.toggle')).find((n:any)=>n.rect?.w>0)!;
  assert(toggle.rect.y+toggle.rect.h<=window.h&&(toggle.rect.y>running.panel.rect.y+running.panel.rect.h||toggle.rect.y+toggle.rect.h<running.panel.rect.y),'the toggle under the mask lies outside the dialog');
  await h.clickAt(toggle.rect.x+toggle.rect.w/2,toggle.rect.y+toggle.rect.h/2);await absent('ai.close.confirmation');
  await resultHas('confirm 0 · cancel 3');await resultHas('running true');assert(!(await result()).startsWith('助手已就绪'),'mask press must not toggle the fixture underneath');
  // The pane's minimize does not end anything.
  await click('ai.minimize');await resultHas('minimize 1 · running true');
  // Confirm once: the host receives exactly one confirmation and the task stops.
  await click('ai.close');await visible('ai.close.confirmation');await click('ai.close.confirmation.confirm');await absent('ai.close.confirmation');await resultHas('confirm 1 · cancel 3');await resultHas('running false');
  // Idle copy: the question drops 停止并, the action label stays 动词 + 对象.
  await openAndMeasure(window,false);
  await h.mouseMove(1,1);assert((await h.screenshot(join(out,`${theme}-320-idle.png`))).ok);
  await click('ai.close.confirmation.cancel');await absent('ai.close.confirmation');await resultHas('confirm 1 · cancel 4');
  // A changed conversation revokes the old ticket; the next request is fresh and usable from the keyboard (Tab → confirm, Return).
  await click('ai.close.preview.replace');await resultHas('旧确认已撤销');
  await click('ai.close');await visible('ai.close.confirmation');assert.equal(await focusedId(),'ai.close.confirmation.cancel');
  await h.key('tab');await h.waitFor(async()=>(await focusedId())==='ai.close.confirmation.confirm'||null,3000);
  await h.key('return');await absent('ai.close.confirmation');await resultHas('confirm 2');
  report.checks.push(`${theme}: native ConfirmDialog ${WIDTH}px centred; running/idle question, fixed 动词+对象 action; cancel autofocus; Escape / 取消 / mask press keep running and the mask press is consumed; minimize retains running; confirm once; changed conversation then Tab/Return confirms`);
 }finally{
  let method='POST /quit';try{await h.request('POST','/quit');await h.waitFor(async()=>child.exitCode!==null||child.signalCode!==null||null,10000)}catch{method='SIGTERM fallback';child.kill('SIGTERM')}
  const status=await ended;report.shutdown.push({theme,method,...status});await log.close();await save();assert.equal(method,'POST /quit');assert.equal(status.code,0);assert.equal(status.signal,null);
 }
 report.status='passed';await save();console.log(`PASS ${report.checks.length} native close confirmation fixture (${theme}): ${out}`);
}catch(error){report.status='failed';report.error=String(error);await save();throw error}
