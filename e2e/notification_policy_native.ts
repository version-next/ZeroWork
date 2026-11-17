/** Structured global notification policy, through the production native views. */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdir,mkdtemp,open,readFile,writeFile,rm,realpath} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import * as h from '../zig-out/share/zenit/harness/client.ts';
const out=resolve(process.argv[2]??'/tmp/zw-notification-policy-native');await mkdir(out,{recursive:true});
const iso=await realpath(await mkdtemp('/tmp/zw-notify-policy-')),rpc=join(iso,'rpc'),data=join(iso,'data');await mkdir(rpc);await mkdir(data);
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const binary=resolve('zig-out/bin/notification-preview'),log=await open(join(out,'app.log'),'w');
const app=spawn(binary,[],{env:{...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1',ZEROWORK_DATA_DIR:data},stdio:['ignore',log.fd,log.fd]});
const ended=new Promise(r=>app.once('close',r));
const shown=(n:any)=>n?.rect&&n.hidden!==true&&n.visible!==false&&(n.effective_opacity??1)>0&&n.rect.w>0&&n.rect.h>0;
const text=(n:any):string=>(n.text??'')+(n.children??[]).map(text).join('\n');
const visible=(id:string)=>h.waitFor(async()=>(await h.query(id)).find(shown)??null,10000);
const absent=(id:string)=>h.waitFor(async()=>!(await h.query(id)).some(shown)||null,10000);
/** Shown descendants of `root` carrying `id`. */
const within=(root:any,id:string):any[]=>{const out:any[]=[];const walk=(n:any)=>{if(n.test_id===id&&shown(n))out.push(n);for(const c of n.children??[])walk(c);};walk(root);return out;};
/** The shown history record (a native Card) whose summary contains `needle`. */
const record=async(needle:string)=>h.waitFor(async()=>(await h.query('notifications.history.record')).filter(shown).find((r:any)=>within(r,'notifications.history.summary').some((n:any)=>text(n).includes(needle)))??null,10000);
const clickNode=async(n:any,what:string)=>assert((await h.clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok,what);
const click=async(id:string)=>{const n=await visible(id);assert((await h.clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok,id);};
// 原生通知卡片（43c46538 起是 zenit NotificationHost）的关闭按钮只在悬停 / 聚焦卡片时出现：先把指针移到卡片上再点。
const dismissCard=async()=>{const card=await visible('notifications.toast.0');await h.mouseMove(card.rect.x+card.rect.w/2,card.rect.y+12);await click('notifications.dismiss.0');await h.mouseMove(5,5);await absent('notifications.toast.0');};
let stage='startup';
const report:any={status:'running',binary,sha256:createHash('sha256').update(await readFile(binary)).digest('hex'),cases:[],limits:['Synthetic business events and Harness input; real source lifecycle is covered by controller tests. No remote action or OS notification permission change.']};
async function capture(name:string){await h.waitFor(async()=>{const n=(await h.query('notifications.history')).find(shown);return n&&(n.effective_opacity??1)===1&&(n.scale_x??1)===1&&(n.scale_y??1)===1?n:null},10000);await h.sleep(100);await writeFile(join(out,name+'.json'),JSON.stringify({history:await h.query('notifications.history'),presenter:await h.query('notifications.presenter')},null,2));assert((await h.screenshot(join(out,name+'.png'))).ok);}
try{
 await h.waitForServerReady();assert.equal(Number(JSON.parse(await readFile(join(rpc,'owner.json'),'utf8')).pid),app.pid);
 await click('toolbar.notifications');await visible('notifications.history.empty');
 await absent('notifications.history.clear');await absent('notifications.history.footer');
 assert(!text(await visible('notifications.history')).includes('只保留重要提醒'));
 await capture('empty');await click('notifications.history.close');
 for(const theme of ['dark','light','sauber']){
  stage=theme+' banner';await click('fixture.theme.'+theme);await h.resizeWindow(1440,900);
  await click('fixture.error');await absent('notifications.toast.0');await absent('notifications.unread');
  await click('fixture.scenes');await visible('notifications.toast.0');await h.sleep(400);
  // 协调器每个窗口只给一条提醒：四条待处理事实只有一张卡片（旧实现的 .toast.1 / .toast.2 槽位已删除）。
  assert.equal((await h.query('notifications.viewport')).flatMap((v:any)=>within(v,'notifications.toast.0')).length,1,'one banner per window');
  stage=theme+' dismiss banner';await dismissCard();await visible('notifications.unread');
  await click('toolbar.notifications');await visible('notifications.history.record');await absent('notifications.toast.0');
  // 头部（共享 PanelHeader）写的是待处理数“N 条”。
  assert.equal(text(await visible('notifications.history.count')),'2 条');
  const rows=(await h.query('notifications.history.record')).filter(shown);assert.equal(rows.length,2);
  // 每条记录是一张原生 Card：占满列表宽度、自上而下排列、互不重叠（高度随内容，不再是固定 68）。
  const list=await visible('notifications.history.viewport');
  for(const [i,row] of rows.entries()){assert(Math.abs(row.rect.x-list.rect.x)<.5&&Math.abs(row.rect.w-list.rect.w)<.5,'record spans the list');if(i)assert(row.rect.y>=rows[i-1].rect.y+rows[i-1].rect.h,'records do not overlap');}
  await absent('notifications.history.clear');await absent('notifications.history.footer');await capture(theme+'-standard');
  let incident=await record('3 个来源');
  const expand=within(incident,'notifications.history.expand')[0];
  assert(expand,'shared incident has an expansion control');await clickNode(expand,'expand shared incident');
  const details=await h.waitFor(async()=>within(await record('3 个来源'),'notifications.history.details').find((n:any)=>(text(n).match(/待处理/g)??[]).length===3)??null,10000);
  await capture(theme+'-expanded');
  stage=theme+' locate expanded source';incident=await record('3 个来源');
  const locate=within(incident,'notifications.history.action').find((n:any)=>n.rect.y>=details.rect.y&&n.rect.y<details.rect.y+details.rect.h);
  assert(locate,'each source of the expanded incident has its own locate action');await clickNode(locate,'locate source');stage=theme+' history closes after locate';await absent('notifications.history');
  assert(text(await visible('fixture.result')).includes('已定位 SSH 连接'));await click('toolbar.notifications');
  assert.equal(text(await visible('notifications.history.count')),'2 条');
  incident=await record('3 个来源');
  if(within(incident,'notifications.history.details').some((n:any)=>text(n).includes('待处理'))){await clickNode(within(incident,'notifications.history.expand')[0],'collapse shared incident');}
  stage=theme+' compact';await h.resizeWindow(860,480);await h.sleep(250);const panel=await visible('notifications.history');
  assert(panel.rect.x>=0&&panel.rect.y>=0&&panel.rect.x+panel.rect.w<=860.5&&panel.rect.y+panel.rect.h<=480.5);
  await capture(theme+'-compact');await click('notifications.history.close');await visible('notifications.unread');
  stage=theme+' outcomes';await click('fixture.outcomes');await absent('notifications.toast.0');
  await click('toolbar.notifications');await visible('notifications.history.empty');assert.equal(text(await visible('notifications.history.count')),'0 条');
  await click('notifications.history.recent');await visible('notifications.history.record');
  assert.equal((await h.query('notifications.history.record')).filter(shown).length,2);
  await visible('notifications.history.clear');await visible('notifications.history.footer');
  await capture(theme+'-resolved');await click('notifications.history.clear');await visible('notifications.history.empty');
  await absent('notifications.history.clear');await absent('notifications.history.footer');
  await click('notifications.history.pending');await click('notifications.history.close');await absent('notifications.unread');
  report.cases.push({theme,status:'passed',checks:['ordinary errors stay local','one banner','three shared sources form one incident','two pending incidents','dismiss and view preserve pending','empty and pending-only histories hide the clear button and footer','resolved history shows clear; clearing hides the footer again','source recovery updates in place','recent filter and clear resolved','records are full-width native cards; panel bounded in the minimum window']});
 }
 stage='hover timeout';await h.resizeWindow(1440,900);await click('fixture.application-risk');
 const toast=await visible('notifications.toast.0');await h.mouseMove(toast.rect.x+20,toast.rect.y+20);await h.sleep(8500);await visible('notifications.toast.0');
 await h.mouseMove(5,5);await h.sleep(8500);await absent('notifications.toast.0');
 await click('toolbar.notifications');await visible('notifications.history.record');await click('notifications.history.close');
 report.cases.push({status:'passed',checks:['application-risk toast pauses on actual hover, expires after pointer leaves, and retains its pending history']});
 report.status='passed';
}catch(e){report.status='failed';report.error=stage+': '+String(e);await h.screenshot(join(out,'failure.png')).catch(()=>{});await writeFile(join(out,'failure-tree.json'),JSON.stringify(await h.tree(),null,2)).catch(()=>{});process.exitCode=1;}
finally{await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));if(app.exitCode===null&&app.signalCode===null)app.kill('SIGTERM');await ended;await log.close();await rm(iso,{recursive:true,force:true});}
console.log(JSON.stringify({status:report.status,out,error:report.error}));
