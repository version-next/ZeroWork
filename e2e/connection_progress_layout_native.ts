/** Real production widgets with explicit local journal facts; no SSH is opened. */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdir,mkdtemp,open,writeFile,rm} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import * as h from '../zig-out/share/zenit/harness/client.ts';
const out=resolve(process.argv[2]??'artifacts/connection-progress-20261028/native');
await mkdir(out,{recursive:true});
const checks:string[]=[];
// 卡片嵌在会话窗格里（e1372d88）：收起时被隐藏的是外层 connection.progress.pane，卡片自身只剩 effective_opacity = 0。
const shown=(n:any)=>n&&!n.hidden&&n.visible!==false&&(n.effective_opacity??1)>0&&n.rect?.w>0&&n.rect?.h>0;
const text=(n:any):string=>(n.text??'')+(n.children??[]).map(text).join('');
const visible=(id:string)=>h.waitFor(async()=>(await h.query(id)).find(shown)??null,10000);
const absent=(id:string)=>h.waitFor(async()=>!(await h.query(id)).some(shown)||null,10000);
// `--theme=<light|dark>` (connection_progress_preview_runner.zig: second argument, default dark); the rest are scenes.
const theme=process.argv.slice(3).find(a=>a.startsWith('--theme='))?.slice(8)??'dark';assert(['light','dark'].includes(theme),'theme '+theme);
const scenes=process.argv.slice(3).filter(a=>!a.startsWith('--theme='));
for(const scene of (scenes.length?scenes:['direct','failed','releasing','long'])){
 const rpc=await mkdtemp('/tmp/zw-progress-layout-');
 process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
 const log=await open(join(out,scene+'.log'),'w');
 const app=spawn(resolve('zig-out/bin/connection-progress-preview'),[scene,theme],{env:{...process.env,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1'},stdio:['ignore',log.fd,log.fd]});
 const ended=new Promise(r=>app.once('close',r));
 try{
  await h.waitForServerReady();
  await h.resizeWindow(1280,720);
  if(scene==='failed'||scene==='releasing'){
   // design-r3 稿 1: a failed attempt is the failure view, not the progress card.
   const view=await visible('connection.progress.failure');
   assert(!(await h.query('connection.progress')).some(shown),'card replaced by failure view');
   assert.equal(text(await visible('connection.progress.failure.title')),'Bastion-02 拒绝了认证');
   assert(text(await visible('connection.progress.failure.alert')).includes('服务器不接受 admin 的认证信息'));
   assert(!(await h.query('connection.progress.failure.retry')).some(shown),'authentication never retries automatically');
   assert(!text(view).includes('释放'),'no 已释放 wording');
   await h.mouseMove(20,80);await h.sleep(250);
   await h.screenshot(join(out,scene+'.png'));
   await writeFile(join(out,scene+'.json'),JSON.stringify(await h.query('connection.progress.failure'),null,2));
   const retry=await visible('connection.progress.failure.retry_now');
   if(scene==='failed'){
    const rx=retry.rect.x+retry.rect.w/2,ry=retry.rect.y+retry.rect.h/2;
    await h.mouseMove(rx,ry);await h.sleep(200);await h.screenshot(join(out,'failed-retry-hover.png'));
    await h.clickTestId('connection.progress.failure.retry_now');
    await h.waitFor(async()=>text(await visible('connection.progress.attempt'))==='第 2 次尝试'||null);
    assert(text(await visible('fixture.result')).includes('已调用原连接的重试操作'));
    await h.screenshot(join(out,'retry.png'));
    checks.push('failed attempt shows the failure view; 立即重试 reaches the original retry callback and the next attempt returns to the progress card');
   }else{
    await h.clickTestId('connection.progress.failure.retry_now');await h.sleep(300);
    assert(!text(await visible('fixture.result')).includes('已调用原连接的重试操作'),'unreleased resources keep retry disabled');
    checks.push('unreleased resources keep 立即重试 disabled in the failure view');
   }
   continue;
  }
  const panel=await visible('connection.progress');
  assert.equal(panel.rect.w,580); // Island B v3（e1372d88）：连接进度卡片宽 580（connection_progress_styles.width，Pencil iY0Iz / eZpyL），原来是 640
  const name=scene==='long'?'ScaleX40-AI01 · production-east-primary-cluster':'ScaleX40-AI01';
  const address=scene==='long'?'operations-administrator@[2001:db8:1234:5678:abcd:ef01:2345:6789]:2222':'root@10.2.209.201:22';
  assert.equal(text(await visible('connection.progress.target')),name);
  const title=await visible('connection.progress.target'),endpoint=await visible('connection.progress.endpoint');
  assert.equal(text(endpoint),address);
  // Island B v3（e1372d88，connection_progress_styles.attemptHeader / identity）：身份行高 28，名称（13 号、行高 18）在行内垂直居中；
  // 等宽小号地址（11 号、行高 16）与名称底边对齐（identity 是 align_items = end），所以地址顶边比名称低 2，间距 8。
  const headMid=panel.rect.y+14,mid=(n:any)=>n.rect.y+n.rect.h/2,bottom=(n:any)=>n.rect.y+n.rect.h;
  assert.equal(title.rect.h,18);assert.equal(endpoint.rect.h,16);
  assert(Math.abs(mid(title)-headMid)<=.5,'name is centred on the 28-point identity line');
  assert(Math.abs(bottom(endpoint)-bottom(title))<=.5&&endpoint.rect.y>title.rect.y,'small endpoint sits low beside the larger name, on its bottom edge');
  assert(Math.abs(endpoint.rect.x-title.rect.x-title.rect.w-8)<.5,'endpoint follows name with an 8-point gap');
  assert.equal(text(panel).split(address).length-1,1);
  // 关闭按钮是全应用同一颗原生 ghost sm 图标按钮（shared/ui/components/panel_header.mountClose，尺寸由 zenit 决定，
  // panel_heads_native 核对各面板一致）：这里只要求它是正方形、在身份行内垂直居中、贴卡片右缘。
  const close=await visible('connection.progress.close');
  assert(Math.abs(close.rect.w-close.rect.h)<.5&&close.rect.h<=28,'close is the square native icon button');
  assert(Math.abs(mid(close)-headMid)<=.5,'close is centred on the identity line');
  assert(panel.rect.x+panel.rect.w-close.rect.x-close.rect.w<=2,'close sits at the card\'s right edge');
  const summary=await visible('connection.progress.summary.title');
  const chain=await visible('connection.progress.chain');
  assert(summary.rect.y<chain.rect.y,'current phase precedes connection path');
  await h.mouseMove(20,80);
  await h.sleep(250);
  await h.screenshot(join(out,scene+'.png'));
  await writeFile(join(out,scene+'.json'),JSON.stringify(await h.query('connection.progress'),null,2));
  if(scene==='long'){
   await h.mouseMove(endpoint.rect.x+endpoint.rect.w/2,endpoint.rect.y+endpoint.rect.h/2);
   const tip=await visible('connection.progress.identity.tooltip');
   assert.equal(text(tip),name+'\n'+address);
   assert(tip.rect.w<=420&&tip.rect.x>=0&&tip.rect.x+tip.rect.w<=1280);
   await h.sleep(250);
   await h.screenshot(join(out,'long-header-tooltip.png'));
   await h.mouseMove(20,80);
   await absent('connection.progress.identity.tooltip');
   for(let i=0;i<12&&(await h.focused()).test_id!=='connection.progress.hop.1';i++)await h.key('tab');
   assert.equal((await h.focused()).test_id,'connection.progress.hop.1');
   assert.equal(text(await visible('connection.progress.hop.tooltip.1')),name+'\n'+address);
   await h.sleep(250);
   await h.screenshot(join(out,'long-keyboard-tooltip.png'));
   await h.key('return');
   await visible('connection.progress.logs');
   // 焦点行的提示还开着：它是被动的说明，不占用 Escape（三处提示都是 `close_on_escape = false`，
   // connection_progress_view.zig）。第一次 Escape 就取消连接，第二次关闭已取消的结果；提示随焦点行一直可见，
   // 卡片关闭时一并消失。
   await visible('connection.progress.hop.tooltip.1');
   assert.equal(text(await visible('connection.progress.state')),'正在连接');
   await h.key('escape');
   await h.waitFor(async()=>text(await visible('connection.progress.state'))==='已取消'||null);
   await h.key('escape');
   await absent('connection.progress');
   await absent('connection.progress.hop.tooltip.1');
   assert(text(await visible('fixture.result')).includes('已关闭连接结果'));
   checks.push('long name and bracketed IPv6: full header tooltip on hover, full row tooltip on Tab focus, Enter opens logs; with the row tooltip still open one Escape cancels the connection and the next closes the released result');
  }else if(scene==='direct'){
   assert.equal(text(summary),'正在准备终端');
   const toggle=await visible('connection.progress.logs.toggle');
   await h.mouseMove(toggle.rect.x+20,toggle.rect.y+14);await h.sleep(200);
   await h.screenshot(join(out,'direct-log-hover.png'));
   const cancel=await visible('connection.progress.cancel');
   // 底栏按钮是原生 secondary Button（高 32、宽随文字），靠卡片右缘（connection_progress_styles.footer，Pencil G4OTn）。
   assert.equal(cancel.rect.h,32);
   assert(Math.abs(panel.rect.x+panel.rect.w-cancel.rect.x-cancel.rect.w)<.5,'cancel is right-aligned in the actions row');
   await h.mouseMove(cancel.rect.x+30,cancel.rect.y+16);await h.sleep(200);
   await h.screenshot(join(out,'direct-cancel-hover.png'));
   await h.mouseMove(20,80);await h.sleep(200);
   await h.clickTestId('connection.progress.hop.1');
   await visible('connection.progress.logs');
   await h.clickTestId('connection.progress.logs.copy');
   assert(text(await visible('fixture.result')).includes('已收到本次连接日志'));
   assert(text(await visible('connection.progress')).includes('已复制连接日志')); // 术语表：“阶段日志”统一成“连接日志”
   await h.resizeWindow(860,480);
   const compact=await visible('connection.progress');
   const footer=await visible('connection.progress.actions');
   assert(compact.rect.y>=0&&compact.rect.y+compact.rect.h<=480.5);
   assert(footer.rect.y+footer.rect.h<=compact.rect.y+compact.rect.h+.5);
   assert.equal(footer.rect.h,46); // connection_progress_styles.footer_height：与日志相隔 14 + 按钮 32（原 54）
   await h.screenshot(join(out,'direct-logs-860.png'));
   await h.clickTestId('connection.progress.cancel');
   await h.waitFor(async()=>text(await visible('connection.progress.state'))==='已取消'||null);
   await h.clickTestId('connection.progress.dismiss');
   await absent('connection.progress');
   checks.push('direct target, phase hierarchy, one endpoint, node opens filtered logs, copy callback, compact footer, cancel and close');
  }
 }finally{
  app.kill('SIGTERM');
  await Promise.race([ended,new Promise(r=>setTimeout(r,2000))]);
  if(app.exitCode===null&&app.signalCode===null){app.kill('SIGKILL');await ended;}
  await log.close();await rm(rpc,{recursive:true,force:true});
 }
}
await writeFile(join(out,'report.json'),JSON.stringify({status:'passed',scope:'production view with local fixture facts, no networking',checks},null,2));
console.log(JSON.stringify({status:'passed',checks,out}));
