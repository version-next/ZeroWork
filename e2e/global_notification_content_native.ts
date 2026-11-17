/** Content of the global reminders: production notification presenter and reminder list with local lifecycle facts;
 * no remote transfer, SSH or AI request is executed.
 *
 * Contract (host/notification_coordinator.zig policy since rc16, native stacks since 43c46538):
 * - only facts that need the user are presented; an ordinary failure such as a failed connection raises no global
 *   reminder and leaves no record (it is shown where it happened);
 * - one card per window; its title is the event, the line below is "source · object" with the source named once;
 * - the card's action reaches the original locate handler and the fact stays pending in the reminder list;
 * - facts from several sources on one shared link are one record ("… 等 3 个来源") whose expansion lists each
 *   source with its own locate action;
 * - when the sources recover the records leave "待处理" and are kept under "最近提醒" with the outcome as title.
 *
 * node e2e/global_notification_content_native.ts <output-directory> <notification-preview-binary>
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdir,mkdtemp,open,writeFile,rm} from 'node:fs/promises';
import * as h from '../zig-out/share/zenit/harness/client.ts';
const dir=process.argv[2]??await mkdtemp('/private/tmp/zw-global-notify-');await mkdir(dir,{recursive:true});const rpc=await mkdtemp('/private/tmp/zw-global-notify-rpc-');process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;const log=await open(dir+'/app.log','w');
const p=spawn(process.argv[3]??'./zig-out/bin/notification-preview',[],{env:{...process.env,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1'},stdio:['ignore',log.fd,log.fd]});
const ended=new Promise(r=>p.once('close',r));
const shown=(n:any)=>n&&!n.hidden&&n.visible!==false&&(n.effective_opacity??1)>0&&n.rect?.w>0&&n.rect?.h>0;
const text=(n:any):string=>(n.text??'')+(n.children??[]).map(text).join('');
const visible=(id:string)=>h.waitFor(async()=>(await h.query(id)).find(shown)??null,12000);
const absent=(id:string)=>h.waitFor(async()=>!(await h.query(id)).some(shown)||null,12000);
const all=async(id:string)=>(await h.query(id)).filter(shown);
const within=(root:any,id:string):any[]=>{const out:any[]=[];const walk=(n:any)=>{if(n.test_id===id&&shown(n))out.push(n);for(const c of n.children??[])walk(c);};walk(root);return out;};
const clickNode=async(n:any,what:string)=>assert((await h.clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok,what);
const click=async(id:string)=>clickNode(await visible(id),id);
const count=(haystack:string,needle:string)=>haystack.split(needle).length-1;
const result=(expected:string)=>h.waitFor(async()=>text(await visible('fixture.result')).includes(expected)||null,6000);
/** The card slides in: wait until it rests. */
const card=async()=>{let last='';return h.waitFor(async()=>{const n=(await h.query('notifications.toast.0')).find(shown);const now=JSON.stringify(n?.rect);if(!n||now!==last){last=now;await h.sleep(120);return null;}return n;},12000);};
const records=async()=>h.waitFor(async()=>{const r=await all('notifications.history.record');return r.length?r:null;},12000);
const checks:string[]=[];let stage='startup';
try{
 await h.waitForServerReady(30000);await h.resizeWindow(1280,720);
 stage='ordinary connection failure';
 for(let i=0;i<2;i++){await click('fixture.connection-failure');await h.mouseMove(5,5);await h.sleep(700);}
 assert(!(await h.query('notifications.toast.0')).some(shown),'a failed connection raises no global card');
 assert(!(await h.query('notifications.unread')).some(shown),'a failed connection adds no pending reminder');
 await click('toolbar.notifications');await visible('notifications.history.empty');
 await click('notifications.history.recent');await h.sleep(300);await visible('notifications.history.empty');
 assert.equal((await all('notifications.history.record')).length,0,'a failed connection leaves no record');
 await h.screenshot(dir+'/connection-failure-history.png');
 await click('notifications.history.pending');await click('notifications.history.close');await absent('notifications.history');
 checks.push('an ordinary connection failure raises no global reminder and leaves no record');

 stage='typical reminders: card';
 await h.resizeWindow(1000,700);await click('fixture.scenes');await h.mouseMove(5,5);
 const banner=await card();await h.screenshot(dir+'/scenes.png');
 assert.equal((await all('notifications.toast.0')).length,1,'one card per window');
 const title=await visible('notifications.title'),meta=await visible('notifications.metadata');
 assert.equal(text(title),'后台传输批次已停止','the title is the event only');
 assert.equal(text(meta),'prod-web-01 · reports 等 3 项','source · object below the title');
 assert.equal(count(text(banner),'prod-web-01'),1,'the source is named once');
 assert(Math.abs(title.rect.x-meta.rect.x)<.5&&meta.rect.y>=title.rect.y+title.rect.h-.5,'title and source line share the left edge');
 const actions=await all('notifications.action');
 assert.deepEqual(actions.map(text),['查看传输']);assert.equal(actions[0].rect.h,28);
 await writeFile(dir+'/scenes.json',JSON.stringify(banner,null,2));
 await clickNode(actions[0],'查看传输');await result('已定位传输任务');await absent('notifications.toast.0');
 assert.equal(text(await visible('notifications.unread')),'2','locating keeps both facts pending');
 checks.push('one card: event-only title, "source · object" with the source once, aligned left edges, 28-point action reaching the original transfer');

 stage='typical reminders: list';
 await click('toolbar.notifications');let rows=await records();
 assert.equal(rows.length,2);
 const titles=rows.map((r:any)=>text(within(r,'notifications.history.title')[0])),summaries=rows.map((r:any)=>text(within(r,'notifications.history.summary')[0]));
 assert.deepEqual(titles,['后台传输批次已停止','SSH 自动恢复已停止']);
 assert.deepEqual(summaries,['prod-web-01 · reports 等 3 项','prod-web-01 等 3 个来源'],'object and shared sources are merged into one line');
 for(const r of rows){assert.equal(count(text(r),'prod-web-01'),1,'session name appears once in a record');const t=within(r,'notifications.history.title')[0],s=within(r,'notifications.history.summary')[0];assert(Math.abs(t.rect.x-s.rect.x)<.5,'record title and summary share the left edge');}
 assert.deepEqual(rows.map((r:any)=>within(r,'notifications.history.action').map(text)),[['查看传输'],['查看来源']]);
 await h.screenshot(dir+'/scenes-history.png');
 stage='typical reminders: shared incident';
 await clickNode(within(rows[1],'notifications.history.expand')[0],'expand the shared incident');
 const incident=await h.waitFor(async()=>{const r=(await all('notifications.history.record'))[1];return r&&count(text(within(r,'notifications.history.details')[0]??{}),'待处理')===3?r:null;},8000);
 const details=within(incident,'notifications.history.details')[0];
 assert(text(details).includes('prod-web-01')&&text(details).includes('prod-api-02'),'the expansion names each source: '+text(details));
 const locate=within(incident,'notifications.history.action').filter((n:any)=>n.rect.y>=details.rect.y&&n.rect.y<details.rect.y+details.rect.h);
 assert.equal(locate.length,3,'each source has its own locate action');
 await h.screenshot(dir+'/scenes-history-expanded.png');
 await clickNode(locate[0],'locate one source');await result('已定位 SSH 连接');await absent('notifications.history');
 checks.push('reminder list: two records, shared-link sources merged into one ("等 3 个来源"); its expansion lists three pending sources, each locating its own SSH connection');

 stage='outcomes';
 await click('fixture.outcomes');await h.mouseMove(5,5);await h.sleep(800);
 assert(!(await h.query('notifications.toast.0')).some(shown),'recovery raises no card');
 await click('toolbar.notifications');await visible('notifications.history.empty');
 await click('notifications.history.recent');rows=await records();
 assert.deepEqual(rows.map((r:any)=>text(within(r,'notifications.history.title')[0])),['来源已恢复','来源已恢复'],'recovered records carry the outcome as their title');
 assert.deepEqual(rows.map((r:any)=>text(within(r,'notifications.history.summary')[0])),['prod-web-01 · reports 等 3 项','prod-web-01 等 3 个来源']);
 await h.screenshot(dir+'/outcomes.png');
 await click('notifications.history.pending');await click('notifications.history.close');await absent('notifications.history');
 checks.push('recovered sources leave 待处理 and stay under 最近提醒 with the outcome as title; no card');

 stage='long content at the minimum window';
 await h.resizeWindow(860,480);await click('fixture.long');await h.mouseMove(5,5);
 const long=await card();await h.screenshot(dir+'/long.png');
 assert(long.rect.x>=0&&long.rect.x+long.rect.w<=860.5&&long.rect.y+long.rect.h<=480.5,'long card stays inside the minimum window');
 const buttons=await all('notifications.action');assert.equal(buttons.length,3);
 for(const b of buttons){assert.equal(b.rect.h,28);assert(b.rect.x>=long.rect.x&&b.rect.x+b.rect.w<=long.rect.x+long.rect.w+.5,'long action labels truncate inside the card');}
 await h.mouseMove(long.rect.x+long.rect.w/2,long.rect.y+12);await click('notifications.dismiss.0');await h.mouseMove(5,5);await absent('notifications.toast.0');
 checks.push('long content at 860x480: card inside the window, three 28-point actions truncated inside it, dismissed with the hover close button');
 await writeFile(dir+'/report.json',JSON.stringify({status:'passed',checks},null,2));console.log(JSON.stringify({status:'passed',checks}));
}catch(error){
 await h.screenshot(dir+'/failure.png').catch(()=>{});
 await writeFile(dir+'/failure-tree.json',JSON.stringify(await h.tree().catch(()=>null),null,2)).catch(()=>{});
 await writeFile(dir+'/report.json',JSON.stringify({status:'failed',stage,error:String((error as any)?.stack??error),checks},null,2));
 console.error(stage,error);process.exitCode=1;
}finally{p.kill('SIGTERM');await ended;await log.close();await rm(rpc,{recursive:true,force:true});}
