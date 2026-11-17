/** Blank welcome × regression, plus the existing bound-conversation End path.
 * Build: zig build -Dtest-mode=true -j2
 * Run: node e2e/ai_welcome_close_native.ts /tmp/zw-welcome-close
 * Uses an isolated Local terminal and an owned loopback streaming provider.
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createServer} from 'node:http';
import {mkdir,mkdtemp,open,readFile,writeFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {aiToggleId} from './ai_entry.ts';

import {isTitleRequest,skipTitle} from './ai_title_fixture.ts';
import {readRequestJson} from './provider_fixture.ts';
const prefix=resolve(process.env.ZW_AI_TEST_PREFIX??'zig-out');
const h=await import(join(prefix,'share/zenit/harness/client.ts'));
const out=resolve(process.argv[2]??'/tmp/zw-welcome-close');
await mkdir(out,{recursive:true});
const isolated=await mkdtemp('/private/tmp/zw-welcome-close-');
const data=join(isolated,'data'),rpc=join(isolated,'rpc'),zdot=join(isolated,'zdot');
for(const dir of [data,rpc,zdot])await mkdir(dir);
await writeFile(join(zdot,'.zshrc'),"PS1='welcome-close%# '\n");
let streams=0,closed=0;
const frame=(content:string)=>'data: '+JSON.stringify({choices:[{index:0,delta:{content}}]})+'\n\n';
const server=createServer(async(req,res)=>{
 if(req.method!=='POST'){res.end('{"data":[{"id":"close-fixture"}]}');return;}
 const body=await readRequestJson(req);if(isTitleRequest(body))return skipTitle(res);
 res.writeHead(200,{'content-type':'text/event-stream'});
 if(body.messages.some((m:any)=>m.role==='system'&&String(m.content).startsWith('将用户的问题概括为简短的会话标题'))){res.end(frame('关闭测试')+'data: [DONE]\n\n');return;}
 streams++;res.on('close',()=>closed++);res.write(frame('CLOSE_STREAM_ACTIVE'));
});
await new Promise<void>(done=>server.listen(0,'127.0.0.1',done));
await writeFile(join(data,'config.toml'),`[meta]\nconfig_revision=1\n[ui]\ntheme="dark"\nfont_size=14\n[ai]\ndefault_provider="close-fixture"\npermission_mode="confirm"\n[[ai.providers]]\nid="close-fixture"\nkind="openai_compat"\nendpoint="http://127.0.0.1:${(server.address() as any).port}/v1/chat/completions"\nenabled=true\n[[ai.providers.models]]\nname="close-fixture"\ncontext_window=32768\ndefault=true\n`);
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const log=await open(join(out,'app.log'),'w');
const app=spawn(join(prefix,'bin/zerowork'),[],{env:{...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1',ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',ZDOTDIR:zdot,OPENAI_API_KEY:'',ANTHROPIC_API_KEY:''},stdio:['ignore',log.fd,log.fd]});
const ended=new Promise(done=>app.once('close',done));
const alive=()=>app.exitCode===null&&app.signalCode===null;
const shown=(n:any)=>n&&n.hidden!==true&&n.visible!==false&&(n.effective_opacity??1)>0&&n.rect?.w>0&&n.rect?.h>0;
const text=(n:any):string=>Array.isArray(n)?n.map(text).join(' '):[n?.text??'',...(n?.children??[]).map(text)].join(' ');
const visible=(id:string)=>h.waitFor(async()=>(await h.query(id)).find(shown)??null,15000);
const hidden=(id:string)=>h.waitFor(async()=>!(await h.query(id)).some(shown)||null,15000);
const click=async(id:string)=>{await visible(id);assert((await h.clickTestId(id)).ok,id);};
const report:any={status:'running',isolated,checks:[]};
const capture=async(name:string)=>{await h.mouseMove(1,1);assert((await h.screenshot(join(out,name+'.png'))).ok);};
// Ending a streaming request publishes an "AI 操作未完成 · AI 已停止" error toast (ai_host.zig refresh("AI 已停止") → setFeedback);
// at 860×480 it covers the panel header, so clear it while no popover is open (hover reveals notifications.dismiss.0).
const dismissNotices=async()=>{for(let round=0;round<5;round++){const toast=(await h.query('notifications.toast.0')).find(shown);if(!toast)return;await h.mouseMove(toast.rect.x+toast.rect.w/2,toast.rect.y+toast.rect.h/2);const n=await h.waitFor(async()=>(await h.query('notifications.dismiss.0')).find(shown)??null,3000);report.dismissed_notice=(report.dismissed_notice??0)+1;await h.clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2);await h.sleep(300)}};
const closeWelcome=async()=>{
 await visible('ai.panel');assert.equal((await h.inputState('ai.prompt')).buffer,'');
 assert(!text(await h.query('ai.panel')).includes('BindingConflict'));
 await click('ai.close');await h.mouseMove(1,1);await hidden('ai.panel');
 assert(!(await h.query('ai.close.confirmation')).some(shown));
};
try{
 await h.waitForServerReady(60000);
 assert.equal(Number(JSON.parse(await readFile(join(rpc,'owner.json'),'utf8')).pid),app.pid);
 await h.resizeWindow(1440,900);await click('workspace.empty.local');await visible('terminal.surface');await click(await aiToggleId());
 await capture('01-welcome');await closeWelcome();await visible('terminal.surface');await capture('02-welcome-closed');
 await click(await aiToggleId());await closeWelcome();assert.equal(streams,0);
 report.checks.push('Blank welcome closes without confirmation or provider requests, including after reopening');
 await click(await aiToggleId());await click('ai.prompt');await h.type_('保留关闭测试草稿');
 assert.equal((await h.inputState('ai.prompt')).buffer,'保留关闭测试草稿');
 // v0.3.0+ (src/features/ai/host/ai_host.zig processLifecycleAction, kind == .end): an unsent welcome draft has no submitted
 // work, so × hides the panel without End confirmation and keeps the persisted draft (same rule as ai_sessions_popover_native).
 await click('ai.close');await h.mouseMove(1,1);await hidden('ai.panel');assert(!(await h.query('ai.close.confirmation')).some(shown),'an unsent draft must not require End confirmation');
 await click(await aiToggleId());await visible('ai.panel');assert.equal((await h.inputState('ai.prompt')).buffer,'保留关闭测试草稿');assert.equal(streams,0);
 report.checks.push('An unsent draft closes without End confirmation or provider requests and is preserved on reopen');
 await click('ai.send');await h.waitFor(async()=>streams===1&&text(await h.query('ai.panel')).includes('CLOSE_STREAM_ACTIVE')||null,15000);
 await click('ai.close');await visible('ai.close.confirmation');await click('ai.close.confirmation.cancel');assert.equal(closed,0);
 await click('ai.close');await visible('ai.close.confirmation');await capture('03-existing-confirmation');
 await click('ai.close.confirmation.confirm');await h.mouseMove(1,1);await hidden('ai.panel');await h.waitFor(()=>closed===1||null,15000);
 await visible('terminal.surface');await dismissNotices();
 report.checks.push('Existing streaming conversation: Cancel keeps the request alive; confirmed End releases it and preserves the terminal');
 await click(await aiToggleId());await click('ai.sessions');await visible('ai.session.row.1');await visible('ai.session.restore.1');await click('ai.sessions.close');
 await closeWelcome();await h.resizeWindow(860,480);await click(await aiToggleId());await closeWelcome();await capture('04-compact-closed');
 assert.equal(streams,1);assert.equal(closed,1);
 report.checks.push('Ended history remains restorable; the fresh welcome closes at both window sizes without another request');
 report.status='passed';
}catch(error){report.status='failed';report.error=String(error);process.exitCode=1;await capture('failure').catch(()=>{});await writeFile(join(out,'failure-tree.json'),JSON.stringify(await h.query('ai.panel').catch(()=>[]),null,2));}
finally{
 try{if(alive()){
  await h.request('POST','/quit');const start=performance.now();
  while(alive()&&performance.now()-start<15000){
   for(const id of ['local.close.accept','session.close.accept'])try{if((await h.query(id)).some(shown))await h.clickTestId(id);}catch{}
   await Promise.race([ended,h.sleep(80)]);
  }
 }}catch(error){report.quit_error=String(error);}
 if(alive()){report.forced=true;app.kill('SIGTERM');await ended;}
 report.exit_code=app.exitCode;report.signal=app.signalCode;
 if(report.forced||app.exitCode!==0){report.status='failed';process.exitCode=1;}
 server.closeAllConnections();await new Promise<void>(done=>server.close(()=>done()));await log.close();
 await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));console.log(JSON.stringify({status:report.status,error:report.error,out}));
}
