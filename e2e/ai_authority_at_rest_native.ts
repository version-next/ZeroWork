/** AI authority at rest (docs/ui-revamp/LIFECYCLE.md §5.2): while a command waits for the reader's approval the AI is
 * at rest — its frame hook runs no pass, nothing polls — and the authority checks still act on the frame the
 * environment changes: closing the tab the conversation is bound to withdraws the pending approval at once, and the
 * command never reaches the PTY. The passes that do it are opened by events (the close and what follows it), never by
 * a timer, read from `POST /zerowork/lifecycle`. Real Local zsh; only the model replies are a fixture.
 *   node e2e/ai_authority_at_rest_native.ts <prefix> <out> [light|dark]
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createServer} from 'node:http';
import {mkdir,mkdtemp,writeFile,readFile,open,rm} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {aiToggleId} from './ai_entry.ts';
import {isTitleRequest,skipTitle} from './ai_title_fixture.ts';
const prefix=resolve(process.argv[2]),out=resolve(process.argv[3]),theme=process.argv[4]==='light'?'light':'dark';await mkdir(out,{recursive:true});
const iso=await mkdtemp('/private/tmp/zw-authority-at-rest-'),data=join(iso,'data'),rpc=join(iso,'rpc'),zdot=join(iso,'zdot');for(const d of[data,rpc,zdot])await mkdir(d);
await writeFile(join(zdot,'.zshrc'),"bindkey -e\nPS1='authority%# '\n");
const wire=(name:string)=>name.replaceAll('_','_u').replaceAll('.','__');
const frame=(delta:any)=>'data: '+JSON.stringify({choices:[{index:0,delta}]})+'\n\n';
const payload=(envelope:any)=>{for(const b of envelope.content??[])try{return JSON.parse(b.text)}catch{}return envelope};
let failed:string|null=null;let requests=0;const marker=join(iso,"approved-command");
const server=createServer(async(req,res)=>{try{
 if(req.method!=='POST')return res.end('{"data":[{"id":"approval-fixture"}]}');
 requests++;let raw='';for await(const b of req)raw+=b;const body=JSON.parse(raw);if(isTitleRequest(body))return skipTitle(res);
 const results=new Map(body.messages.filter((m:any)=>m.role==='tool').map((m:any)=>[m.tool_call_id,payload(JSON.parse(m.content))]));
 const emit=(id:string,name:string,args:any)=>res.end((id==='approval-run'?frame({content:'APPROVAL_PREFACE：我会先请求确认，再执行这条命令。'}):'')+frame({tool_calls:[{index:0,id,type:'function',function:{name:wire(name),arguments:JSON.stringify(args)}}]})+'data: [DONE]\n\n');
 res.writeHead(200,{'content-type':'text/event-stream'});
 const context:any=results.get('approval-context');if(!context)return emit('approval-context','host.get_current_context',{});
 let ready=false;
 for(let i=0;i<8;i++){
  const facts:any=results.get('approval-ready-'+i);
  if(!facts){if(i)await new Promise(r=>setTimeout(r,350));return emit('approval-ready-'+i,'host.get_session',{session_ref:context.binding_ref});}
  if(facts.session?.capabilities?.trusted_pty_execution){ready=true;break}
 }
 assert(ready,'Local PTY did not report ready');
 const run:any=results.get('approval-run');if(!run)return emit('approval-run','host.run_in_terminal',{session_ref:context.binding_ref,command:`printf APPROVAL_NATIVE_OK; printf once >> '${marker}'`,request_key:'approval-native-once'});
 let observed:any=run;
 for(let i=0;observed.state!=='interval_recorded'&&i<8;i++){
  const next:any=results.get('approval-wait-'+i);
  if(!next)return emit('approval-wait-'+i,'host.wait_execution',{execution_ref:run.execution_ref,after_revision:observed.source_revision,wait_ms:30000,max_bytes:4096});
  observed=next;
 }
 assert.equal(observed.state,'interval_recorded');assert.equal(observed.snapshot.process.exit_code,0);
 res.end(frame({content:'APPROVAL_NATIVE_FINISHED'})+'data: [DONE]\n\n');
}catch(err){failed=String(err);res.end(frame({content:'FIXTURE_ERROR'})+'data: [DONE]\n\n')}});await new Promise<void>(r=>server.listen(0,'127.0.0.1',r));
await writeFile(join(data,'config.toml'),`[meta]\nconfig_revision=1\n[ui]\ntheme="${theme}"\nfont_size=14\n[ai]\ndefault_provider="approval-fixture"\npermission_mode="confirm"\n[[ai.providers]]\nid="approval-fixture"\nkind="openai_compat"\nendpoint="http://127.0.0.1:${(server.address()as any).port}/v1/chat/completions"\nenabled=true\n[[ai.providers.models]]\nname="approval-fixture"\ncontext_window=200000\ndefault=true\n`);
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;const h=await import(join(prefix,'share/zenit/harness/client.ts'));const log=await open(join(out,`app-${theme}.log`),'w');
const app=spawn(join(prefix,'bin/zerowork'),[],{env:{...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZEROWORK_DATA_DIR:data,ZDOTDIR:zdot,ZEROWORK_AUTOCONNECT:'0',ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1'},stdio:['ignore',log.fd,log.fd]});
const shown=(n:any)=>n&&n.hidden!==true&&n.visible!==false&&(n.effective_opacity??1)>0&&n.rect?.w>0&&n.rect?.h>0;
const visible=(id:string)=>h.waitFor(async()=>(await h.query(id)).find(shown)??null,15000);
const click=async(id:string)=>{await visible(id);assert((await h.clickTestId(id)).ok)};
const life=async()=>(await h.request('POST','/zerowork/lifecycle',{})).counters;
const report:any={theme,status:'running',checks:[]};
const check=(name:string,ok:boolean,detail?:any)=>{report.checks.push({name,ok:!!ok,...(ok?{}:{detail})});return !!ok};
try{
 await h.waitForServerReady(60000);await h.resizeWindow(1200,900);await click('workspace.empty.local');await visible('terminal.surface');
 await click(await aiToggleId());await click('ai.prompt');await h.type_('在当前终端执行审批阶段验证');await click('ai.send');
 await visible('ai.interaction.card');await h.sleep(800);
 // 1. Waiting for the reader is rest: no pass in two seconds, the provider is not called, the request stays shown.
 const waitingRequests=requests,before=await life();await h.sleep(2000);const after=await life();
 report.waiting={passes:after.ai_passes-before.ai_passes,hook_runs:after.ai_hook_runs-before.ai_hook_runs,frame_steps:after.ai_frame_steps-before.ai_frame_steps,reasons:Object.fromEntries(Object.keys(after.ai_pass_reasons).map((r:string)=>[r,after.ai_pass_reasons[r]-before.ai_pass_reasons[r]]).filter(([,v]:any)=>v>0))};
 check('waiting for approval: no AI host pass while at rest',after.ai_passes===before.ai_passes,report.waiting);
 check('waiting for approval: the provider is not polled',requests===waitingRequests,{before:waitingRequests,after:requests});
 check('waiting for approval: the request is still shown',(await h.query('ai.interaction.card')).some(shown));
 await h.screenshot(join(out,`${theme}-waiting-approval.png`));
 // 2. The environment changes at rest: the tab the conversation is bound to is closed.
 const closing=await life();const env0=closing.ai_pass_reasons.environment;
 await click('terminal.surface');assert((await h.key('w',{cmd:true})).ok);await h.key('modifiers_released').catch(()=>{});
 await h.waitFor(async()=>{for(const id of ['local.close.accept','session.close.accept'])if((await h.query(id)).some(shown)){await click(id);return true}return (await h.query('terminal.surface')).some(shown)?null:true},8000).catch(()=>null);
 const gone=await h.waitFor(async()=>(await h.query('ai.interaction.card')).some(shown)?null:true,3000).catch(()=>false);
 check('tab closed: the pending approval is withdrawn',gone===true);
 const closed=await life();report.closed={environment_passes:closed.ai_pass_reasons.environment-env0,passes:closed.ai_passes-closing.ai_passes,reasons:Object.fromEntries(Object.keys(closed.ai_pass_reasons).map((r:string)=>[r,closed.ai_pass_reasons[r]-closing.ai_pass_reasons[r]]).filter(([,v]:any)=>v>0))};
 // The passes that withdrew it were opened by events (the close, its focus change, the rerun after them), never by a timer.
 check('tab closed: no deadline (poll) opened a pass',!report.closed.reasons.deadline,report.closed);
 await h.sleep(2500);
 check('tab closed: the command never reached the PTY',(await readFile(marker,'utf8').catch(()=>null))===null);
 check('no fixture error',failed===null,failed);
 await h.screenshot(join(out,`${theme}-after-close.png`));
 const bad=report.checks.filter((c:any)=>!c.ok);assert.equal(bad.length,0,`${bad.length} check(s) failed: ${bad.map((c:any)=>c.name).join('; ')}`);
 report.status='passed';
}catch(err){report.status='failed';report.error=String(err);await h.screenshot(join(out,`${theme}-failure.png`)).catch(()=>{});process.exitCode=1}
finally{app.kill('SIGTERM');await new Promise<void>(r=>{if(app.exitCode!==null||app.signalCode!==null)return r();app.once('close',()=>r());setTimeout(()=>{app.kill('SIGKILL');r()},3000)});server.closeAllConnections();await new Promise<void>(r=>server.close(()=>r()));await log.close();await rm(iso,{recursive:true,force:true});await writeFile(join(out,`report-${theme}.json`),JSON.stringify(report,null,2));console.log(JSON.stringify(report))}
