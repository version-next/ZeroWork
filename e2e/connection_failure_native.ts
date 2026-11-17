/** design-r3 稿 1 · 连接失败 / 重试视图：生产视图 + 本地夹具事实（connection-progress-preview），不建立任何 SSH 连接。
 * 四种失败原因（拒连自动重试、认证失败不重试、超时经跳板退避、主机密钥变更待确认）各截一张图，并核对文案、
 * 只有自动重试时才出现重试行与倒计时条、按钮集合与主按钮、点击回到原连接的回调。
 * node e2e/connection_failure_native.ts [prefix] [output] [theme]
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdir,mkdtemp,open,writeFile,rm,realpath} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
const prefix=resolve(process.argv[2]??'zig-out'),out=resolve(process.argv[3]??'/tmp/zw-connection-failure'),theme=process.argv[4]??'light';
assert(['light','dark'].includes(theme));
await mkdir(out,{recursive:true});
const h=await import(join(prefix,'share/zenit/harness/client.ts'));
const shown=(n:any)=>n&&!n.hidden&&n.visible!==false&&(n.effective_opacity??1)>0&&n.rect?.w>0&&n.rect?.h>0;
const text=(n:any):string=>(n.text??'')+(n.children??[]).map(text).join('');
const visible=(id:string)=>h.waitFor(async()=>(await h.query(id)).find(shown)??null,10000);
const absent=async(id:string)=>!(await h.query(id)).some(shown);
const click=async(id:string)=>{await visible(id);assert((await h.clickTestId(id)).ok,id);await h.sleep(150);};
const result=async(expected:string)=>h.waitFor(async()=>text(await visible('fixture.result')).includes(expected)||null,5000);
const report:any={status:'running',theme,scope:'production failure view with local fixture facts; no networking',checks:[],captures:[]};
const expectations:any={
 refused:{title:'无法连接到 staging-api',alert:'127.0.0.1:65530 拒绝连接',retry:true,hop:'拒绝连接',primary:'connection.progress.failure.retry_now',buttons:['edit','logs.toggle','stop','retry_now'],missing:['credentials','trust','disconnect'],clickId:'connection.progress.failure.stop',clickResult:'已停止自动重试'},
 auth:{title:'prod-web-01 拒绝了认证',alert:'服务器不接受 deploy 的认证信息',retry:false,hold:'不自动重试：请先修改认证方式或重新输入凭据',hop:'认证失败',primary:'connection.progress.failure.credentials',buttons:['edit','logs.toggle','retry_now','credentials'],missing:['stop','trust','disconnect'],clickId:'connection.progress.failure.credentials',clickResult:'已请求重新输入凭据'},
 timeout:{title:'连接 build-agent-mac 超时',alert:'10.0.3.8:22 在 15 秒内没有响应',retry:true,hop:'超时',route:'连接路径 · 1 级跳板',primary:'connection.progress.failure.retry_now',buttons:['edit','logs.toggle','stop','retry_now'],missing:['credentials','trust','disconnect'],clickId:'connection.progress.failure.retry_now',clickResult:'已立即开始自动重试'},
 hostkey:{title:'prod-db-primary 的主机密钥变了',alert:'服务器提供的密钥与已保存的不一致',retry:false,hop:'密钥不符',primary:'connection.progress.failure.trust',buttons:['edit','logs.toggle','disconnect','trust'],missing:['stop','retry_now','credentials'],clickId:'connection.progress.failure.trust',clickResult:'已信任新密钥'},
};
try{
 for(const scene of Object.keys(expectations)){
  const e=expectations[scene];
  const base=await realpath(await mkdtemp(join(tmpdir(),'zw-failure-view-'))),rpc=join(base,'rpc');await mkdir(rpc);
  process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
  const log=await open(join(out,`${scene}-${theme}.log`),'w');
  const app=spawn(join(prefix,'bin/connection-progress-preview'),[scene,theme],{env:{...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1'},stdio:['ignore',log.fd,log.fd]});
  const ended=new Promise(r=>app.once('close',r));
  try{
   await h.waitForServerReady(30000);await h.resizeWindow(1280,800);
   const root=await visible('connection.progress.failure');
   assert(await absent('connection.progress'),'progress card is replaced by the failure view');
   assert(root.rect.w>0);
   assert.equal(text(await visible('connection.progress.failure.title')),e.title);
   assert(text(await visible('connection.progress.failure.alert')).includes(e.alert),scene+' alert names the endpoint');
   assert.equal(!(await absent('connection.progress.failure.retry')),e.retry,scene+' retry row only while an automatic retry waits');
   if(e.retry){assert(text(await visible('connection.progress.failure.retry')).includes('共 3 次'),'real attempt limit');assert((await visible('connection.progress.failure.retry.bar')).rect.w>0);}
   if(e.hold)assert(text(await visible('connection.progress.failure.hold')).includes(e.hold));
   if(e.route)assert(text(await visible('connection.progress.failure.route')).includes(e.route));
   const route=text(await visible('connection.progress.failure.route'));
   assert(route.includes(e.hop),scene+' failed hop status');assert(!route.includes('释放'),'no 已释放 wording');
   if(scene==='hostkey'){assert(text(await visible('connection.progress.failure.key.saved')).includes('已保存的密钥'));assert(text(await visible('connection.progress.failure.key.offered')).includes('服务器当前提供的密钥'));}
   for(const id of e.buttons)await visible('connection.progress.failure.'+id);
   for(const id of e.missing)assert(await absent('connection.progress.failure.'+id),scene+' hides '+id);
   const primary=await visible(e.primary),edit=await visible('connection.progress.failure.edit'),logs=await visible('connection.progress.failure.logs.toggle');
   assert(edit.rect.x<logs.rect.x&&logs.rect.x<primary.rect.x,'edit / logs lead, primary trails');
   for(const id of e.buttons){const n=await visible('connection.progress.failure.'+id);assert(n.rect.x+n.rect.w<=primary.rect.x+primary.rect.w+.5,'primary is rightmost');}
   await h.mouseMove(20,20);await h.sleep(400);
   const name=`${scene}-${theme}`;assert((await h.screenshot(join(out,name+'.png'))).ok);report.captures.push(name);
   await writeFile(join(out,name+'.json'),JSON.stringify(await h.query('connection.progress.failure'),null,2));
   if(scene==='refused'){await click('connection.progress.failure.logs.toggle');await visible('connection.progress.failure.logs');assert.equal(text(await visible('connection.progress.failure.logs.toggle')),'收起日志');await h.mouseMove(20,20);await h.sleep(300);assert((await h.screenshot(join(out,name+'-logs.png'))).ok);report.captures.push(name+'-logs');}
   if(scene==='hostkey'){
    // 替换主机密钥 is irreversible: the shared native confirmation (W.ConfirmDialog) first — focus on 取消, Esc cancels,
    // the danger button says 动词 + 对象 (CONSISTENCY_AUDIT #2).
    assert.equal(text(await visible('connection.progress.failure.trust')),'替换主机密钥');
    await click(e.clickId);
    const dialog=await visible('connection.progress.failure.trust.confirm');
    assert(text(dialog).includes('替换主机密钥？'),'confirmation title');
    assert.equal(text(await visible('connection.progress.failure.trust.accept')),'替换主机密钥');
    assert.equal(text(await visible('connection.progress.failure.trust.cancel')),'取消');
    assert(!text(await visible('fixture.result')).includes(e.clickResult),'nothing replaced before the confirmation');
    await h.mouseMove(20,20);await h.sleep(400);
    assert((await h.screenshot(join(out,name+'-confirm.png'))).ok);report.captures.push(name+'-confirm');
    await h.key('escape');await h.waitFor(async()=>(await absent('connection.progress.failure.trust.confirm'))||null,5000);
    assert(!text(await visible('fixture.result')).includes(e.clickResult),'Escape cancels the replacement');
    await click(e.clickId);await click('connection.progress.failure.trust.accept');
    await result(e.clickResult);
    report.checks.push(`${scene}: 替换主机密钥 opens the native confirmation (danger, 取消 first, Esc cancels) before the key is replaced`);
   }else{await click(e.clickId);await result(e.clickResult);}
   report.checks.push(`${scene}: title, alert endpoint, retry row ${e.retry?'shown':'absent'}, hop status, button set, primary rightmost, ${e.clickId} reaches the original callback`);
  }finally{app.kill('SIGTERM');await Promise.race([ended,new Promise(r=>setTimeout(r,3000))]);await log.close();await rm(base,{recursive:true,force:true});}
 }
 report.status='passed';
}catch(error){report.status='failed';report.error=String(error);process.exitCode=1;await h.screenshot(join(out,'failure.png')).catch(()=>{});}
finally{await writeFile(join(out,`report-${theme}.json`),JSON.stringify(report,null,2));console.log(JSON.stringify(report));}
