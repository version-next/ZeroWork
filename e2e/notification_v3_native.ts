/** Production Presenter/Coordinator in an isolated native Metal window.
 * Explicit fixture facts verify presentation, not SSH/LLM/OS delivery.
 *
 * Contract (features/notifications/model/view_model.zig, native stacks since 43c46538 / 53d90733):
 * - two native stacks per window: cards in the top-right corner (392 wide, 22 from the right edge, below the 40-point
 *   tab bar), plain hints at the bottom centre;
 * - a local acknowledgement is a bottom-centre hint that goes away by itself after about 2 s;
 * - the coordinator presents only facts that need the user (pending / actionable): an ordinary result without an
 *   action shows nothing in the window; one card per window, a newer fact replaces the shown one in place;
 * - a card with an action lives 8 s, its action reaches the original handler and dismisses it;
 * - while a host overlay covers the corner the card stack is hidden and its timers are held; uncovered, the card
 *   comes back where its life bar stopped;
 * - a long detail scrolls inside a bounded frame; up to three actions share one row. */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdir,mkdtemp,open,readFile,writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
const prefix=process.env.ZW_NOTIFICATION_PREFIX??'/private/tmp/zw-surfaces-prefix';
const h=await import(join(prefix,'share/zenit/harness/client.ts'));
const output=process.argv[2];assert(output);await mkdir(output,{recursive:true});
const base=await mkdtemp('/private/tmp/zw-feedback-'),rpc=join(base,'rpc');await mkdir(rpc);
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const binary=join(prefix,'bin/notification-preview'),log=await open(join(output,'app.log'),'w');
const app=spawn(binary,[],{env:{...process.env,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1'},stdio:['ignore',log.fd,log.fd]});const end=new Promise(r=>app.once('close',r));
const report:any={status:'running',binary,sha256:createHash('sha256').update(await readFile(binary)).digest('hex'),checks:[],scope:'Production native feedback presentation using explicit local fixture facts. No network or OS notification delivery.',screenshots:[]};
const shown=(n:any)=>n&&!n.hidden&&n.visible!==false&&(n.effective_opacity??1)>0&&n.rect?.w>0&&n.rect?.h>0;
const vis=(id:string)=>h.waitFor(async()=>(await h.query(id)).find(shown)??null,7000);
const hidden=(id:string)=>h.waitFor(async()=>!(await h.query(id)).some(shown)||null,7000);
async function click(id:string){await vis(id);assert((await h.clickTestId(id)).ok,id)}
async function capture(name:string){assert((await h.screenshot(join(output,name+'.png'))).ok);report.screenshots.push(name)}
const text=(n:any):string=>(n.text??'')+(n.children??[]).map(text).join('');
const scale=async(id:string)=>Number((await vis(id)).scale_x??1);
const rest=async(id:string)=>{let last='';return h.waitFor(async()=>{const n=(await h.query(id)).find(shown);const now=JSON.stringify(n?.rect);if(!n||now!==last){last=now;await h.sleep(120);return null;}return n;},7000);};
const corner=(card:any)=>[card.rect.x+card.rect.w,card.rect.y,card.rect.w].map(v=>Math.round(v*10)/10);
const unread=async()=>text((await h.query('notifications.unread'))[0]??{});
try{
 await h.waitForServerReady();assert.equal(Number(JSON.parse(await readFile(join(rpc,'owner.json'),'utf8')).pid),app.pid);
 for(const [w,ht] of [[1440,900],[860,480]]){
  await h.resizeWindow(w,ht);await h.sleep(250);
  await click('fixture.local');const local=await rest('notifications.local');
  assert(Math.abs(local.rect.x+local.rect.w/2-w/2)<1,'acknowledgement is centred horizontally');
  assert(local.rect.y>ht/2&&local.rect.y+local.rect.h<=ht-8,'acknowledgement sits near the bottom edge inside the window');
  assert(text(local).includes('已确认'));
  if(w===1440)await capture('local-acknowledgment');
  await h.sleep(900);await vis('notifications.local');await h.sleep(2600);await hidden('notifications.local');
 }
 report.checks.push('local acknowledgement: bottom-centre hint inside the window at 1440 and 860, gone by itself after about 2 seconds');
 await h.resizeWindow(1440,900);await h.sleep(250);
 for(const ordinary of ['fixture.normal','fixture.error']){
  const before=await unread();await click(ordinary);await h.sleep(900);
  assert(!(await h.query('notifications.toast.0')).some(shown)&&!(await h.query('notifications.local')).some(shown),ordinary+' shows nothing in the window');
  assert.equal(await unread(),before,ordinary+' does not add a pending reminder');
 }
 report.checks.push('ordinary results without an action (success or failure) are not presented in the window');
 await click('fixture.action');await h.mouseMove(5,5);let card=await rest('notifications.toast.0');
 assert.deepEqual(corner(card),[1418,62,392],'card docks in the top-right corner below the tab bar');
 await capture('action-standard');await h.sleep(4500);await vis('notifications.toast.0');await capture('action-after-four-seconds');
 await click('notifications.action');await hidden('notifications.toast.0');assert(JSON.stringify(await h.query('fixture.result')).includes('已打开结果'));
 report.checks.push('actionable card docks top-right (392 wide), lives beyond 4 seconds, its action opens the actual result handler and dismisses it');
 await click('fixture.action');await h.mouseMove(5,5);await rest('notifications.toast.0');await h.sleep(5500);await vis('notifications.toast.0');await h.sleep(3800);await hidden('notifications.toast.0');
 report.checks.push('actionable card expires after 8 seconds when not invoked');
 await click('fixture.action');await h.mouseMove(5,5);await rest('notifications.toast.0');await h.sleep(600);
 const beforeCover=await scale('notifications.countdown');
 await click('fixture.cover');await h.mouseMove(5,5);await hidden('notifications.toast.0');await capture('covered-hidden');
 await h.sleep(4500);await hidden('notifications.toast.0');
 await click('fixture.cover');await h.mouseMove(5,5);await vis('notifications.toast.0');
 const afterCover=await scale('notifications.countdown');
 // 4.5 s hidden would be more than half of the 8 s life: the bar is (almost) where it stopped.
 assert(afterCover<=beforeCover&&beforeCover-afterCover<.2,`timer held while covered: ${beforeCover} → ${afterCover}`);
 await capture('resumed-after-cover');await h.sleep(8500);await hidden('notifications.toast.0');
 report.checks.push('an overlay over the corner hides the card and holds its timer for more than 4 seconds; uncovered it resumes and then expires');
 await h.resizeWindow(860,480);await h.sleep(250);
 for(let i=0;i<3;i++){await click('fixture.long');await h.sleep(250);}await h.mouseMove(5,5);
 card=await rest('notifications.toast.0');
 assert.equal((await h.query('notifications.toast.0')).filter(shown).length,1,'one card per window: a newer fact replaces the shown one');
 assert.deepEqual(corner(card),[838,62,392],'compact window keeps the corner origin');
 assert(card.rect.y+card.rect.h<=480.5,'long card stays inside the minimum window');await capture('long-compact-top');
 const frame=await vis('notifications.message.viewport'),detail=await vis('notifications.detail');
 assert(frame.rect.h<=160.5&&detail.rect.h>frame.rect.h*2&&frame.rect.y>=card.rect.y&&frame.rect.y+frame.rect.h<=card.rect.y+card.rect.h,'long detail is in a bounded frame inside the card');
 assert((await h.scrollAt(frame.rect.x+20,frame.rect.y+60,0,-100000)).ok);await h.sleep(300);
 const scrolled=await vis('notifications.detail');
 // zenit 8a3202f9：详情滚动区有高度上限，长详情在外框内滚到底。
 assert(Math.abs(scrolled.rect.y+scrolled.rect.h-frame.rect.y-frame.rect.h)<1.5,'long detail scrolls to its end inside the bounded frame');
 report.checks.push('long detail scrolls to its end inside the bounded frame');
 const actions=(await h.query('notifications.action')).filter(shown),footer=await vis('notifications.footer');
 assert.equal(actions.length,3);
 for(const a of actions){assert.equal(a.rect.h,28);assert(a.rect.x>=footer.rect.x&&a.rect.x+a.rect.w<=footer.rect.x+footer.rect.w+.5&&Math.abs(a.rect.y-actions[0].rect.y)<.5,'three actions share one row inside the card');}
 await capture('long-compact-bottom');await writeFile(join(output,'long-geometry.json'),JSON.stringify({card:card.rect,frame:frame.rect,detail:scrolled.rect,actions:actions.map((a:any)=>a.rect)},null,2));
 const lastAction=actions.at(-1);assert((await h.clickAt(lastAction.rect.x+lastAction.rect.w/2,lastAction.rect.y+lastAction.rect.h/2)).ok);
 await hidden('notifications.toast.0');assert(JSON.stringify(await h.query('fixture.result')).includes('已打开结果'));
 report.checks.push('compact window: one long card at the corner origin, detail clipped to a bounded frame, three 28-point actions in one row, the last one reaches its handler and dismisses the card');report.status='passed';
}catch(e){report.status='failed';report.error=String(e);await capture('failure').catch(()=>{});process.exitCode=1}
finally{await writeFile(join(output,'report.json'),JSON.stringify(report,null,2));app.kill('SIGTERM');await Promise.race([end,h.sleep(3000)]);if(app.exitCode===null&&app.signalCode===null){app.kill('SIGKILL');await end}await log.close();console.log(JSON.stringify({status:report.status,error:report.error,output}))}
