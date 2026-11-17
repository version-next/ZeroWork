/** Full application: real loopback SSH handshake failure -> actual controller journal -> failure view and hovered log row.
 *
 * Contract since design-r3 稿 1 (7cdc072f): when the attempts are exhausted the session pane shows the failure view
 * (`connection.progress.failure`); its "查看日志" lists the steps without the raw library text. The raw text of a
 * failed step is the hover bubble of that row in the progress card's log, which is on screen while a later attempt
 * runs (the card keeps the rows of the earlier attempts). So: the loopback peer first drops every connection right
 * after the client's identification (real libssh2 failures), then — once the failure view is up — holds the next
 * connection open without answering, "立即重试" starts an attempt that stays in progress, and the failed rows of
 * the earlier attempts are hovered in the card. */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createServer} from 'node:net';
import {mkdtemp,mkdir,writeFile,open,rm,readFile,realpath} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {resolve,join} from 'node:path';
import * as h from '../vendor/zenit/e2e/client.ts';
const executable=resolve(process.argv[2]??'/tmp/zerowork-ssh-hover-production/bin/zerowork');
const out=resolve(process.argv[3]??'artifacts/ssh-raw-diagnostic/production');
await mkdir(out,{recursive:true});
const temp=await realpath(await mkdtemp(join(tmpdir(),'zw-ssh-hover-production-')));
const data=join(temp,'data'),rpc=join(temp,'rpc');await mkdir(data);await mkdir(rpc);
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
let connections=0,clientBanners=0,hold=false;
const peers=new Set<any>();
const server=createServer(socket=>{connections++;peers.add(socket);socket.once('data',bytes=>{assert(bytes.toString().startsWith('SSH-2.0-'));clientBanners++;if(!hold)socket.end();});socket.on('error',()=>{});socket.on('close',()=>peers.delete(socket));});
await new Promise<void>(r=>server.listen(0,'127.0.0.1',r));const port=(server.address() as any).port;
await writeFile(join(data,'hosts.toml'),`[registry]\nschema_version=2\nrevision=1\nnext_connection_id=2\nnext_group_id=1\n[[hosts]]\nconnection_id=1\nrevision=1\nprotocol="ssh"\nauth_mode="password"\noptions={strict_host_key=true}\nname="SSH 日志验证"\nhost="127.0.0.1"\nport=${port}\nuser="fixture"\n`);
await writeFile(join(data,'config.toml'),'[ui]\ntheme="dark"\n[ssh]\nconnect_timeout_sec=60\n');
const log=await open(join(out,'app.log'),'w');
const app=spawn(executable,[],{env:{...process.env,ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1'},stdio:['ignore',log.fd,log.fd]});
const ended=new Promise(r=>app.once('close',r));
const shown=(n:any)=>n&&!n.hidden&&n.visible!==false&&(n.effective_opacity??1)>.9&&n.rect?.w>0&&n.rect?.h>0;
const text=(n:any):string=>(n.text??'')+(n.children??[]).map(text).join('');
const visible=(id:string)=>h.waitFor(async()=>(await h.query(id)).find(shown)??null,15000);
const absent=(id:string)=>h.waitFor(async()=>!(await h.query(id)).some(shown)||null,10000);
const report:any={status:'running',entry:'src/main.zig',executable,checks:[],connections:0};
try{
 await h.waitForServerReady();
 assert.equal(Number(JSON.parse(await readFile(join(rpc,'owner.json'),'utf8')).pid),app.pid);
 await h.resizeWindow(1280,800);
 await visible('workspace.titlebar');
 // design-r3 A2：单击只选中主机，连接用行内的原生“连接”按钮。
 const host=await visible('sidebar.host');await h.mouseMove(host.rect.x+100,host.rect.y+host.rect.h/2);
 assert((await h.clickTestId('sidebar.host.connect')).ok,'sidebar.host.connect');
 // Every automatic attempt fails in the handshake; when none is pending any more the failure view stays.
 await h.waitFor(async()=>(await h.query('connection.progress.failure')).some(shown)&&!(await h.query('connection.progress.failure.retry')).some(shown)&&(await h.query('connection.progress.failure.retry_now')).some(shown)||null,60000);
 assert(clientBanners>0,'actual libssh2 client sent its SSH identification');
 const failedAttempts=connections;
 assert(!(await h.query('connection.progress')).some(shown),'the failed connection is the failure view, not the progress card');
 assert.equal(text(await visible('pane.status')),'连接失败','pane header names the failed connection');
 assert.equal((await h.query('connection.progress.logs.raw')).length,0,'no separate raw-log button in main application');
 await h.clickTestId('connection.progress.failure.logs.toggle');
 const lines=text(await visible('connection.progress.failure.logs'));
 assert(lines.includes('SSH 握手'),'failure view lists the failed handshake step: '+lines);
 assert(!lines.includes('rc=')&&!lines.includes('handshake transport'),'failure view log carries no raw library text');
 await absent('connection.progress.logs.raw-popover');
 assert((await h.screenshot(join(out,'main-app-failure-view.png'))).ok);
 await writeFile(join(out,'main-app-failure-view.json'),JSON.stringify(await h.query('connection.progress.failure'),null,2));
 // Next attempt stays in progress: the peer accepts and keeps silent.
 hold=true;
 assert((await h.clickTestId('connection.progress.failure.retry_now')).ok,'retry_now');
 await visible('connection.progress');await absent('connection.progress.failure');
 await h.waitFor(async()=>connections>failedAttempts||null,15000);
 // 新一次尝试还在握手：窗格头部的状态必须是“连接中”——不能因为会话提示条处于缺省态就写成“已连接”
 // （cdf2933b4 引入的回归，usage-e2e-debt 修复）。
 await h.waitFor(async()=>text(await visible('pane.status'))==='连接中'||null,5000).catch(async()=>assert.fail('pane header while the attempt is in progress: '+text(await visible('pane.status'))));
 await h.clickTestId('connection.progress.logs.toggle');await h.sleep(250);
 for(const [width,height] of [[1280,800],[860,480]]){
  await h.resizeWindow(width,height);await h.sleep(250);
  // 第一次变窄时窗口会弹一次性提示“可以收起侧栏”（中下方轻提示，永远在最上层），正好盖在日志上：指针停在别处等它自己消失。
  await h.mouseMove(20,80);await h.waitFor(async()=>!(await h.query('notifications.tip')).some(shown)||null,20000);
  // 卡片正文是滚动区：窗口矮时日志在折叠线以下，先把正文滚到底让日志区完整露出来。日志自己跟随最新一行，
  // 等各行停稳后，取一条同时落在日志区与正文可视范围内的失败行。
  const body=await visible('connection.progress.body');
  assert((await h.scrollAt(body.rect.x+body.rect.w/2,body.rect.y+body.rect.h/2,0,-2000)).ok);
  let last='';
  const row=await h.waitFor(async()=>{
   const well=(await h.query('connection.progress.logs')).find(shown);if(!well)return null;
   const top=Math.max(well.rect.y,body.rect.y),bottom=Math.min(well.rect.y+well.rect.h,body.rect.y+body.rect.h);
   const hit=(await h.query('connection.progress.logs.failure')).filter(shown).find((n:any)=>n.rect.y>=top&&n.rect.y+n.rect.h<=bottom+.5);
   const now=JSON.stringify(hit?.rect);if(!hit||now!==last){last=now;await h.sleep(120);return null;}
   return hit;
  },15000);
  assert(row,'controller delivered the earlier attempts\' handshake diagnostics to the production card');
  await h.mouseMove(row.rect.x+40,row.rect.y+8);
  const bubble=await visible('connection.progress.logs.raw-popover');
  const raw=text(await visible('connection.progress.logs.raw-text'));
  assert(raw.includes('handshake transport host=127.0.0.1:')&&raw.includes('rc='));
  assert(/\d{2}:\d{2}:\d{2}\.\d{3} - handshake/.test(raw));
  assert(bubble.rect.x>=0&&bubble.rect.y>=0&&bubble.rect.x+bubble.rect.w<=width+1&&bubble.rect.y+bubble.rect.h<=height+1);
  assert((await h.screenshot(join(out,`main-app-${width}.png`))).ok);
  await writeFile(join(out,`main-app-${width}.json`),JSON.stringify({progress:await h.query('connection.progress'),raw:await h.query('connection.progress.logs.raw-text'),bubble:await h.query('connection.progress.logs.raw-popover')},null,2));
  await h.mouseMove(20,80);await absent('connection.progress.logs.raw-popover');
 }
 report.failedAttempts=failedAttempts;
 report.connections=connections;report.clientBanners=clientBanners;
 report.checks=['real libssh2 handshake failures through full production controller end in the failure view','failure view log lists the failed step without raw library text','while the next attempt runs the pane header says 连接中 and hovering a failed row of an earlier attempt displays its native raw diagnostic','no separate raw-log button','timestamp-message-duration retained','main app 1280/860 screenshot and viewport bounds','pointer leave closes popup'];
 report.status='passed';console.log('PASS: full ZeroWork main application, real SSH failure, row-hover raw log');
}catch(error){report.status='failed';report.error=String((error as any)?.stack??error);await h.screenshot(join(out,'failure.png')).catch(()=>{});await writeFile(join(out,'failure-tree.json'),JSON.stringify(await h.tree().catch(()=>null),null,2)).catch(()=>{});throw error;}
finally{
 if(app.exitCode===null&&app.signalCode===null)app.kill('SIGTERM');await ended;
 for(const socket of peers)socket.destroy();await new Promise<void>(r=>server.close(()=>r()));
 await log.close();await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));await rm(temp,{recursive:true,force:true});
}
