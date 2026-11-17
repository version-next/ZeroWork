/**
 * H-modals-ws 第二轮验收对照图（人工验收反馈 8：对话框用 zenit 原生 Modal 的默认遮罩与默认面板）。
 * 一次性采集脚本，隔离启动照 `settings_nav.ts` 的 `launchIsolated`（临时数据目录、关闭自动检查更新；本脚本要在启动前写 hosts.toml，所以内联了一份）。
 *
 * 主程序模式（默认）每个主题采集：
 *   (a) 本地终端关闭确认（`local.close.confirmation`，前台跑着 `sleep`）；并验证 Esc 取消、标签页还在；
 *   (b) 加入会话组（`groups.join.dialog`，标签页右键菜单）；
 *   (c) 连接编辑器里的“从已有主机复制”（`wizard.copy.dialog`，夹具 hosts.toml 里放一台不可达的 192.0.2.1；放最后，关闭编辑器窗口后 Harness 查询不稳）。
 * 设置窗口里的“清理记录”确认在全新数据目录下按钮不可用（没有已结束的记录），不采集。
 * 每张图同时把对话框节点写成 JSON，便于核对面板尺寸。
 *
 * `--auth <auth-challenge-preview 二进制>` 模式：用现有的认证组件预览窗口采集“主机密钥首连确认 / 主机密钥已变化”
 * （生产里的主机密钥确认走这个组件；workspace 自己那份旧确认框只在没有挂连接宿主的无窗口 runner 里出现，见报告）。
 *
 * 会话标签页关闭确认（`session.close.confirm`）只在 SSH 标签页有传输 / AI 写命令 / SOCKS 风险时出现，
 * 隔离环境不连真实主机触发不了，由 test-ui 组件测试覆盖（见报告）。
 *
 * Usage:
 *   node e2e/h_modals_capture.ts <zerowork binary (test-mode)> <out dir> [light|dark]
 *   node e2e/h_modals_capture.ts --auth <auth-challenge-preview binary> <out dir> [light|dark]
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {join,resolve} from 'node:path';
import {writeFile} from 'node:fs/promises';
import * as h from '../vendor/zenit/e2e/client.ts';
import {shown} from './settings_nav.ts';

const argv=process.argv.slice(2);
const authMode=argv[0]==='--auth';
const [binaryArg,outArg,theme='light']=authMode?argv.slice(1):argv;
if(!binaryArg||!outArg)throw new Error('usage: h_modals_capture.ts [--auth] <binary> <out> [light|dark]');
const out=resolve(outArg);
const hosts=`[registry]
schema_version=2
revision=1
next_connection_id=2
next_group_id=2
[[groups]]
group_id=1
revision=1
name="Fixture group"
[[hosts]]
connection_id=1
revision=1
protocol="ssh"
name="Fixture host"
host="192.0.2.1"
port=2222
user="fixture"
asset_group_id=1
auth_mode="password"
`;
// launchIsolated 的隔离启动（临时数据目录、关闭自动检查更新），另外在启动前写入 hosts.toml 夹具。
async function launch(o:{prefix:string,logName:string,args?:string[],hosts?:string}){
 const {mkdtemp,mkdir,realpath,open}=await import('node:fs/promises');
 const {spawn}=await import('node:child_process');
 const iso=await realpath(await mkdtemp(`/private/tmp/${o.prefix}-`)),rpc=join(iso,'rpc'),data=join(iso,'data');
 await mkdir(rpc);await mkdir(data);await mkdir(out,{recursive:true});
 await writeFile(join(data,'config.toml'),`[meta]\nconfig_revision=1\n[updates]\nauto_check=false\n[ui]\ntheme="${theme}"\n`,{mode:0o600});
 if(o.hosts)await writeFile(join(data,'hosts.toml'),o.hosts,{mode:0o600});
 process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
 const log=await open(join(out,o.logName),'w');
 const app=spawn(resolve(binaryArg),o.args??[],{env:{...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1',ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',OPENAI_API_KEY:'',ANTHROPIC_API_KEY:''},stdio:['ignore',log.fd,log.fd]});
 const ended=new Promise<void>(r=>app.once('close',()=>r()));
 const stop=async()=>{if(app.exitCode===null&&app.signalCode===null)app.kill('SIGTERM');await ended;await log.close().catch(()=>{});};
 try{await h.waitForServerReady();}catch(e){await stop();throw e;}
 return {stop};
}
const run=authMode
 ?await launch({prefix:'zw-h-modals-auth',logName:`auth-app-${theme}.log`,args:[theme]})
 :await launch({prefix:'zw-h-modals-capture',logName:`app-${theme}.log`,hosts});
const report:any={status:'running',mode:authMode?'auth-preview':'app',theme,shots:[] as string[],checks:[] as string[]};
const node=async(id:string,ms=12000):Promise<any>=>h.waitFor(async()=>(await h.query(id)).find(shown)??null,ms);
const gone=async(id:string,ms=6000)=>h.waitFor(async()=>(await h.query(id)).some(shown)?null:true,ms);
const click=async(id:string)=>{const n=await node(id);assert((await h.clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok,id);await h.sleep(200);};
const rightClick=async(id:string)=>{const n=await node(id),p={x:n.rect.x+10,y:n.rect.y+n.rect.h/2,button:'right'};await h.request('POST','/mouse_down',p);await h.request('POST','/mouse_up',p);await h.sleep(200);};
const ids=async()=>new Set((await h.windows()).windows.filter(w=>w.bound&&!w.closing).map(w=>w.window_id));
const shot=async(name:string,dialogId:string,win?:string)=>{
 await h.mouseMove(2,2).catch(()=>{});await h.sleep(500);
 const d=await node(dialogId);
 const base=join(out,`${theme}-${name}`);
 await writeFile(base+'.json',JSON.stringify({test_id:d.test_id,rect:d.rect},null,2));
 assert((await h.screenshot(base+'.png',win)).ok,name);report.shots.push(base+'.png');
};

try{
 if(authMode){
  await h.resizeWindow(1100,720);
  for(const kind of ['host_key_unknown','host_key_changed']){
   await click('legacy.auth.'+kind);await node('auth.challenge.modal');await node('auth.challenge.title.icon');
   await shot('auth-'+kind,'auth.challenge.modal');
   await click('auth.challenge.cancel');await gone('auth.challenge.modal');
  }
  report.checks.push('auth-challenge-preview: unknown / changed host-key confirmations captured, Cancel closes');
 }else{
  await h.resizeWindow(1440,900);
  const main=[...(await ids())][0];
  // (a) 本地终端关闭确认。
  await click('workspace.empty.local');await click('terminal.surface');
  // 等 shell 起来再输入，并给 sleep 留时间成为前台进程（否则关闭时没有风险，不弹确认）。
  await h.sleep(1500);await h.type_('sleep 600\n');await h.sleep(2500);
  const tab:any=await h.waitFor(async()=>{for(const n of await h.query('tabs.strip')){const f=(x:any):any=>/^tabs\.tab\.\d+$/.test(x?.test_id??'')&&shown(x)?x:(x?.children??[]).map(f).find(Boolean);const t=f(n);if(t)return t;}return null;},8000);
  {const t=await node(tab.test_id);await h.mouseMove(t.rect.x+t.rect.w/2,t.rect.y+t.rect.h/2);await h.sleep(300);}
  await click(tab.test_id.replace('tabs.tab.','tabs.close.'));
  await node('local.close.confirmation');
  await shot('a-local-close','local.close.confirmation',main);
  await h.key('escape');await gone('local.close.confirmation');await node(tab.test_id);
  report.checks.push('local close confirmation: captured; Esc cancels and keeps the tab');
  // (b) 加入会话组。
  await rightClick(tab.test_id);await click('context.menu.join_session_group');
  await node('groups.join.dialog');
  await shot('b-group-join','groups.join.dialog',main);
  await h.key('escape');await gone('groups.join.dialog');
  report.checks.push('group join dialog: captured; Esc closes');
  // (c) 连接编辑器 › 从已有主机复制。
  const before=await ids();
  await click('sidebar.footer.new');
  await node('wizard.copy.open');
  const wizardWin=[...(await ids())].find(w=>!before.has(w))??main;
  await click('wizard.copy.open');await node('wizard.copy.dialog');
  await shot('c-wizard-copy','wizard.copy.dialog',wizardWin);
  await click('wizard.copy.cancel');await gone('wizard.copy.dialog');
  report.checks.push('connection editor copy-from-host dialog: captured; Cancel closes');
 }
 report.status='passed';
}catch(e){report.status='failed';report.error=String((e as any)?.stack??e);process.exitCode=1;await h.screenshot(join(out,`${theme}-${authMode?'auth-':''}failure.png`)).catch(()=>{});}
finally{await run.stop();await writeFile(join(out,`report-${authMode?'auth-':''}${theme}.json`),JSON.stringify(report,null,2));console.log(JSON.stringify({status:report.status,shots:report.shots.length,error:report.error}));}
