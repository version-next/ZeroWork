/** Notification UX review in isolated production and fixture windows. */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdir,mkdtemp,open,readFile,writeFile,rm,realpath} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import * as h from '../zig-out/share/zenit/harness/client.ts';
const out=resolve(process.argv[2]??'/tmp/zerowork-notification-review/native');
const fixture=process.argv[3]==='fixture';
await mkdir(out,{recursive:true});
const iso=await realpath(await mkdtemp('/tmp/zw-notification-ux-')),rpc=join(iso,'rpc'),data=join(iso,'data');
await mkdir(rpc);await mkdir(data);process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const binary=resolve('zig-out/bin/'+(fixture?'notification-preview':'zerowork'));
const log=await open(join(out,'app.log'),'w');
const app=spawn(binary,[],{env:{...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1',ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0'},stdio:['ignore',log.fd,log.fd]});
const ended=new Promise(r=>app.once('close',r));
const shown=(n:any)=>n?.rect&&n.hidden!==true&&n.visible!==false&&(n.effective_opacity??1)>0&&n.rect.w>0&&n.rect.h>0;
const text=(n:any):string=>(n.text??'')+(n.children??[]).map(text).join('\n');
const visible=(id:string)=>h.waitFor(async()=>(await h.query(id)).find(shown)??null,10000);
const absent=(id:string)=>h.waitFor(async()=>!(await h.query(id)).some(shown)||null,10000);
const click=async(id:string)=>{const n=await visible(id);assert((await h.clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok);};
const capture=async(name:string)=>{await h.sleep(250);await writeFile(join(out,name+'.json'),JSON.stringify({history:await h.query('notifications.history'),presenter:await h.query('notifications.presenter'),cards:await h.query('notifications.viewport'),commandHint:await h.query('terminal.ai-error-hint'),quick:await h.query('quick.query'),focused:await h.focused()},null,2));assert((await h.screenshot(join(out,name+'.png'))).ok);};
const report:any={status:'running',binary,checks:[]};
try {
 await h.waitForServerReady();assert.equal(Number(JSON.parse(await readFile(join(rpc,'owner.json'),'utf8')).pid),app.pid);
 await h.resizeWindow(1280,720);
 await click('toolbar.notifications');await visible('notifications.history.empty');await capture('empty-history');
 await h.key('escape');await absent('notifications.history');
 if(fixture){
  await click('fixture.action');const countdown=await visible('notifications.countdown');assert(text(countdown).includes('秒后关闭'));
  const initial=text(countdown);await h.sleep(2100);assert.notEqual(text(await visible('notifications.countdown')),initial);await capture('countdown');
  await h.sleep(6300);await absent('notifications.toast.0');
  await visible('notifications.unread');await click('toolbar.notifications');
  const retained=await visible('notifications.history.record');assert.equal(retained.rect.h,68);await absent('notifications.unread');await absent('notifications.history.details');await capture('retained-after-expiry');
  await click('notifications.history.expand');const detailsText=text(await visible('notifications.history.details'));assert(detailsText.includes('仅验证原生展示'));assert(!detailsText.includes('有结果可查看')&&!detailsText.includes('prod-web-01'));await capture('expanded-details');
  assert.equal((await h.focused()).test_id,'notifications.history.expand');
  await click('notifications.history.expand');await absent('notifications.history.details');assert.equal((await visible('notifications.history.record')).rect.h,68);
  await click('notifications.history.action');await absent('notifications.history');assert(text(await visible('fixture.result')).includes('已打开结果'));
  await click('fixture.error');await visible('notifications.toast.0');await absent('notifications.countdown');
  await click('notifications.dismiss.0');await click('toolbar.notifications');
  await h.resizeWindow(860,480);await capture('history-compact');
  const panel=(await visible('notifications.history')).rect;assert(panel.x>=0&&panel.y>=0&&panel.x+panel.w<=861&&panel.y+panel.h<=481);
  assert.equal((await h.query('notifications.history.record')).filter(shown).length,2);
  for(const row of (await h.query('notifications.history.record')).filter(shown))assert.equal(row.rect.h,68);
  await click('notifications.history.clear');await visible('notifications.history.empty');
  await click('notifications.history.close');await click('fixture.scenes');await click('toolbar.notifications');
  await h.waitFor(async()=>(await h.query('notifications.history.record')).filter(shown).length===3||null);
  for(const row of (await h.query('notifications.history.record')).filter(shown))assert.equal(row.rect.h,68);
  await absent('notifications.toast.0');await capture('dense-list');await click('notifications.history.clear');await visible('notifications.history.empty');await click('notifications.history.close');
  await click('fixture.long');await click('toolbar.notifications');assert.equal((await visible('notifications.history.record')).rect.h,68);
  await click('notifications.history.expand');const longDetails=await visible('notifications.history.details');assert(text(longDetails).includes('Long notification content for native scroll verification.'));const longViewport=await visible('notifications.history.viewport');assert(longDetails.rect.h>longViewport.rect.h);
  const expandedPanel=(await visible('notifications.history')).rect;assert(expandedPanel.y+expandedPanel.h<=481);await capture('long-details-bounded');await h.scrollAt(longViewport.rect.x+20,longViewport.rect.y+80,0,-100000);await h.sleep(150);const lastAction=(await h.query('notifications.history.action')).filter(shown).at(-1);assert(lastAction.rect.y>=longViewport.rect.y&&lastAction.rect.y+lastAction.rect.h<=longViewport.rect.y+longViewport.rect.h+0.5);await capture('long-details-bottom');await h.scrollAt(longViewport.rect.x+20,longViewport.rect.y+80,0,100000);await h.sleep(150);
  await click('notifications.history.expand');assert.equal((await visible('notifications.history.record')).rect.h,68);
  await click('notifications.history.clear');await click('notifications.history.close');await click('fixture.connection-failure');await click('toolbar.notifications');await visible('notifications.history.record');await absent('notifications.history.expand');await absent('notifications.history.details');await capture('no-extra-details');
  report.checks.push('no expansion control without independent details; expanded details omit title and owner');
  report.checks.push('8-second actionable countdown decreases and expires','expired and dismissed records remain in history','bell unread dot clears on opening','history action dispatches original fact','persistent error has no countdown','history fits minimum window and clear works','68-point collapsed rows, inline actions, full details expand and collapse with keyboard focus','three compact rows and 4000-character details remain bounded');
 }else{
  // Quick Connect now always lists 本地终端 (quick.local) as a result, so the initial state is that result list
  // (the "输入 SSH 地址，直接连接" empty card only shows when nothing is listed); still distinct from the
  // no-match state and without a clear button.
  await h.key('k',{cmd:true});await h.sleep(300);assert(text(await visible('quick.local')).includes('本地终端'));await absent('quick.empty.title');await absent('quick.clear');await capture('quick-initial');
  await h.type_('missing-host');assert(text(await visible('quick.empty.title')).includes('未找到匹配的主机'));await visible('quick.clear');await click('quick.clear');
  assert(text(await visible('quick.local')).includes('本地终端'));await absent('quick.empty.title');await absent('quick.clear');await h.key('escape');await absent('quick.query');
  await click('workspace.empty.local');await visible('terminal.surface');await h.sleep(1000);
  const terminal=await visible('terminal.surface');await h.clickAt(terminal.rect.x+30,terminal.rect.y+30);
  await h.type_('zerowork_missing_command_review');await h.key('return');const hint=await visible('terminal.ai-error-hint');
  // The command-failure card is a native zenit Notification on the terminal (exit code title, command, output as
  // the expandable detail); its close button shows while the card is hovered. Since 2cab3389 (统一异常通知) a
  // failure in the visible local session is not an "important" notification (Coordinator.qualifies: the
  // host.command_error event is local and source-visible), so it is no longer listed in the history after
  // dismiss: the retained real failure facts are checked on the card itself, and the history's 最近提醒 is
  // checked to stay free of it (see the report: needs a product decision if history retention is still wanted).
  assert(text(await visible('terminal.ai-error-hint.exit')).includes('127'));assert(text(await visible('terminal.ai-error-hint.command')).includes('zerowork_missing_command_review'));
  await h.mouseMove(hint.rect.x+hint.rect.w-24,hint.rect.y+16);await h.sleep(300);
  assert(text(await visible('terminal.ai-error-hint.output')).includes('zsh: command not found'));await capture('command-error-card');
  await visible('terminal.ai-error-hint.dismiss');await h.sleep(500);await click('terminal.ai-error-hint.dismiss');await absent('terminal.ai-error-hint');await click('toolbar.notifications');
  // History opens on 待处理; dismissed and ended records are under 最近提醒 (notifications.history.recent).
  await click('notifications.history.recent');await visible('notifications.history.empty');
  assert(!(await h.query('notifications.history.record')).some(shown),'local visible command failure is not an important history record');await capture('command-error-history');
  await click('notifications.history.close');await h.key('w',{cmd:true});await click('toolbar.notifications');await click('notifications.history.recent');
  // "会话已结束" was the ended state of the listed command-failure record; with local visible failures no longer
  // listed (above) there is no record to end, so closing the session must leave 最近提醒 in its readable empty
  // state rather than a stale row (same product decision as above).
  await visible('notifications.history.empty');assert(!(await h.query('notifications.history.record')).some(shown),'no stale record after the session ends');await capture('ended-session-history');
  report.checks.push('initial quick-connect empty state, query, and clear are distinct','real local shell failure card shows exit code, command and output (history no longer lists local visible failures)','closed session leaves the history readable (no stale record)');
 }
 report.status='passed';
}catch(e){report.status='failed';report.error=String(e);report.stack=(e as Error)?.stack;await capture('failure').catch(()=>{});process.exitCode=1;}
finally{await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));app.kill('SIGTERM');await Promise.race([ended,h.sleep(2000)]);if(app.exitCode===null&&app.signalCode===null){app.kill('SIGKILL');await ended;}await log.close();await rm(iso,{recursive:true,force:true});console.log(JSON.stringify(report));}
