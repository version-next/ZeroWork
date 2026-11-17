/** Native notification life bar (countdown), hover / focus pause and expiry; isolated data and production presenter.
 *
 * Since 43c46538 the cards are zenit's native NotificationHost: the countdown is the card's life bar (a bar along the
 * card's bottom edge that shrinks — `scale_x` 1 → 0 over the card's lifetime, 8 s for a card with an action), not a
 * "N 秒后关闭" text. Hovering the card or keeping keyboard focus inside it holds the bar; leaving resumes it. The close
 * button appears only while the card is hovered or focused.
 * node e2e/notification_countdown_native.ts BUILD_PREFIX OUTPUT_DIRECTORY
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdir,mkdtemp,open,readFile,writeFile,rm} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
const prefix=resolve(process.argv[2]),out=resolve(process.argv[3]);
const h=await import('../vendor/zenit/e2e/client.ts');
await mkdir(out,{recursive:true});
const base=await mkdtemp('/private/tmp/zw-countdown-'),rpc=join(base,'rpc'),data=join(base,'data');
await mkdir(rpc);await mkdir(data);process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const binary=join(prefix,'bin/notification-preview'),log=await open(join(out,'app.log'),'w');
const app=spawn(binary,[],{env:{...process.env,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1',ZEROWORK_DATA_DIR:data},stdio:['ignore',log.fd,log.fd]});
const ended=new Promise(r=>app.once('close',r));
const shown=(n:any)=>n&&!n.hidden&&n.visible!==false&&(n.effective_opacity??1)>0&&n.rect?.w>0&&n.rect?.h>0;
const text=(n:any):string=>(n.text??'')+(n.children??[]).map(text).join('');
const visible=(id:string)=>h.waitFor(async()=>(await h.query(id)).find(shown)??null,10000);
const absent=(id:string)=>h.waitFor(async()=>!(await h.query(id)).some(shown)||null,10000);
const click=async(id:string)=>{const n=await visible(id);assert((await h.clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok,id);};
const checks:string[]=[],shots:string[]=[];let stage='startup';
async function capture(name:string){const file=join(out,name+'.png');assert((await h.screenshot(file)).ok);shots.push(file);}
const scale=async(id:string)=>Number((await visible(id)).scale_x??1);
/** The life bar spans the card along its bottom edge, below the action. */
async function lifeBar(cardId:string,barId:string,actionId:string){
 // The card slides in: measure once it rests.
 let last='';await h.waitFor(async()=>{const n=(await h.query(cardId)).find(shown);const now=JSON.stringify(n?.rect);if(!n||now!==last){last=now;await h.sleep(120);return null;}return n;},10000);
 const card=await visible(cardId),bar=await visible(barId),action=await visible(actionId);
 assert(Math.abs(bar.rect.x-card.rect.x)<.5&&Math.abs(bar.rect.w-card.rect.w)<.5,'life bar spans the card');
 assert(Math.abs(bar.rect.y+bar.rect.h-card.rect.y-card.rect.h)<=1&&bar.rect.h<=3,'life bar is a thin bar on the card\'s bottom edge');
 assert(action.rect.y+action.rect.h<=bar.rect.y+.5&&action.rect.x>=card.rect.x&&action.rect.x+action.rect.w<=card.rect.x+card.rect.w+.5,'action sits inside the card above the life bar');
}
/** The bar shrinks by about elapsed / 8 s of its width. */
async function runs(barId:string){
 const a=await scale(barId),t=Date.now();await h.sleep(1200);const b=await scale(barId),expected=(Date.now()-t)/8000;
 assert(a<=1&&b<a&&Math.abs((a-b)-expected)<.08,`life bar runs: ${a} → ${b} in ${Date.now()-t} ms`);
}
async function holds(barId:string,why:string){
 const a=await scale(barId);await h.sleep(1200);const b=await scale(barId);
 assert(Math.abs(a-b)<.01,`life bar holds while ${why}: ${a} → ${b}`);
}
const hoverCard=async(id:string)=>{const card=await visible(id);await h.mouseMove(card.rect.x+card.rect.w/2,card.rect.y+12);await h.sleep(300);};
try{
 await h.waitForServerReady();assert.equal(Number(JSON.parse(await readFile(join(rpc,'owner.json'),'utf8')).pid),app.pid);
 for(const theme of ['light','dark','sauber']){
  stage=theme+' command';await click('fixture.theme.'+theme);await h.resizeWindow(1440,900);
  await click('fixture.command-error');await h.mouseMove(5,5);
  await visible('terminal.ai-error-hint');
  await lifeBar('terminal.ai-error-hint','terminal.ai-error-hint.countdown','terminal.ai-error-hint.open');
  await runs('terminal.ai-error-hint.countdown');await capture(theme+'-command');
  stage=theme+' command hover';await hoverCard('terminal.ai-error-hint');
  await holds('terminal.ai-error-hint.countdown','the card is hovered');
  await visible('terminal.ai-error-hint.dismiss');
  await capture(theme+'-command-interacting');
  if(theme==='light'){await h.sleep(8200);await visible('terminal.ai-error-hint');}
  stage=theme+' command resume';await h.mouseMove(5,5);await h.sleep(300);await runs('terminal.ai-error-hint.countdown');
  if(theme==='light'){
   stage='command idle expiration';await absent('terminal.ai-error-hint');
  }else{
   await click('terminal.ai-error-hint.open');await absent('terminal.ai-error-hint');assert(text(await visible('fixture.result')).includes('已打开命令分析'));
  }
  checks.push(theme+': command card life bar runs, holds on hover (close button appears), resumes, and the card expires or opens the original analysis');
  stage=theme+' application risk';await click('fixture.application-risk');await h.mouseMove(5,5);
  await visible('notifications.toast.0');
  await lifeBar('notifications.toast.0','notifications.countdown','notifications.action');
  await runs('notifications.countdown');await capture(theme+'-risk');
  await hoverCard('notifications.toast.0');await holds('notifications.countdown','the banner is hovered');
  await h.mouseMove(5,5);await h.sleep(300);await runs('notifications.countdown');
  // 应用级风险的详情默认展开；“收起详情 / 展开详情”是原生开关，点它之后键盘焦点留在卡片里，生命条随之停住。
  stage=theme+' risk details';await visible('notifications.detail');
  await click('notifications.expand');await h.mouseMove(5,5);await absent('notifications.detail');
  await click('notifications.expand');await h.mouseMove(5,5);await visible('notifications.detail');await capture(theme+'-risk-expanded');
  assert(JSON.stringify(await h.focused()).includes('notifications.expand'),'the details toggle keeps keyboard focus');
  await holds('notifications.countdown','keyboard focus is inside the banner');
  if(theme==='light'){await h.sleep(8200);await visible('notifications.toast.0');}
  stage=theme+' risk dismiss';await hoverCard('notifications.toast.0');await click('notifications.dismiss.0');await h.mouseMove(5,5);await absent('notifications.toast.0');
  checks.push(theme+': risk banner life bar runs, holds on hover and while focus is inside; details collapse and expand; dismissed with the hover close button');
 }
 stage='minimum window long content';await h.resizeWindow(860,480);await click('fixture.long');await h.mouseMove(5,5);
 await visible('notifications.toast.0');await lifeBar('notifications.toast.0','notifications.countdown','notifications.action');
 let card=await visible('notifications.toast.0');
 assert(card.rect.x>=0&&card.rect.y>=0&&card.rect.x+card.rect.w<=860.5&&card.rect.y+card.rect.h<=480.5);
 for(const id of ['notifications.countdown','notifications.action','notifications.expand']){
  const n=await visible(id);assert(n.rect.x>=card.rect.x&&n.rect.x+n.rect.w<=card.rect.x+card.rect.w+.5,id+' fits card');
 }
 await capture('minimum-long');
 if(!(await h.query('notifications.detail')).some(shown)){await click('notifications.expand');await h.mouseMove(5,5);}
 // 长详情在有界滚动框里：框和卡片都留在最小窗口内。
 const frame=await visible('notifications.message.viewport');card=await visible('notifications.toast.0');
 assert(frame.rect.y>=card.rect.y&&frame.rect.y+frame.rect.h<=card.rect.y+card.rect.h+.5&&card.rect.y+card.rect.h<=480.5,'long detail stays in a bounded frame inside the card and the window');
 await capture('minimum-long-expanded');
 await hoverCard('notifications.toast.0');await click('notifications.dismiss.0');await h.mouseMove(5,5);await absent('notifications.toast.0');
 stage='risk expiration and history';await click('fixture.application-risk');await h.mouseMove(5,5);await visible('notifications.countdown');
 await h.sleep(8300);await absent('notifications.toast.0');await click('toolbar.notifications');await visible('notifications.history.record');
 await capture('retained-history');checks.push('minimum-width long content and all actions fit; expired risks remain in history');
 await writeFile(join(out,'report.json'),JSON.stringify({status:'passed',binary,sha256:createHash('sha256').update(await readFile(binary)).digest('hex'),checks,screenshots:shots,scope:'Production native renderers with synthetic notification facts, isolated app/data and Harness input. No remote sessions or OS notification delivery.'},null,2));
 console.log(JSON.stringify({status:'passed',out,checks}));
}catch(error){
 await h.screenshot(join(out,'failure.png')).catch(()=>{});
 await writeFile(join(out,'failure-tree.json'),JSON.stringify(await h.tree().catch(()=>null),null,2));
 await writeFile(join(out,'report.json'),JSON.stringify({status:'failed',stage,error:String(error),checks,screenshots:shots},null,2));
 console.error(stage,error);process.exitCode=1;
}finally{
 if(app.exitCode===null&&app.signalCode===null)app.kill('SIGTERM');await ended;await log.close();await rm(base,{recursive:true,force:true});
}
