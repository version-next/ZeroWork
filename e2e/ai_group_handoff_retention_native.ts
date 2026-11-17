/** Real native handoff, window dismissal, owner switching and original wire-history retention. */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createHash} from 'node:crypto';
import {createServer} from 'node:http';
import {mkdtemp,mkdir,writeFile,readFile,open,realpath,readdir} from 'node:fs/promises';
import {join,resolve,dirname} from 'node:path';
import {aiToggleId} from './ai_entry.ts';
import {isTitleRequest,skipTitle} from './ai_title_fixture.ts';
import {readRequestJson,pollWithin} from './provider_fixture.ts';
const out=resolve(process.argv[2]??'/private/tmp/zw-ai-handoff-retention');
const binary=resolve(process.argv[3]??'/private/tmp/zw-handoff-retention-build/bin/zerowork');
const prefix=dirname(dirname(binary));
await mkdir(out,{recursive:true});
const h=await import(join(prefix,'share/zenit/harness/client.ts'));
const iso=await realpath(await mkdtemp('/private/tmp/zw-ai-handoff-retention-'));
const data=join(iso,'data'),rpc=join(iso,'rpc'),zdot=join(iso,'zdot');
const executionPidPath=join(iso,'foreground.pid'),executionSentinelPath=join(iso,'after-stop');
for(const path of[data,rpc,zdot])await mkdir(path);
await writeFile(join(zdot,'.zshrc'),"bindkey -e\nPS1='handoff-retention%# '\n");
const requests:any[]=[],calls:any[]=[],results:any={};
const report:any={status:'running',binary,binary_sha256:createHash('sha256').update(await readFile(binary)).digest('hex'),isolation:{iso,data,rpc,zdot},checks:[],approvals:[],limits:['Loopback only proposes provider calls; real native App, Local shell, host lifecycle, group and message retention are exercised.','One precisely approved Local sleep validates actual process stop/lease release; an unapproved sentinel command must never dispatch. Stop retains the existing conservative outcome_unknown receipt when exact completion is unavailable. No SSH, production App/configuration or reconstructed call.']};
const wire=(name:string)=>name.replaceAll('_','_u').replaceAll('.','__');
const frame=(delta:any)=>'data: '+JSON.stringify({choices:[{index:0,delta}]})+'\n\n';
// 绑定/环境变更（交接、恢复）后，下一任务把此前的历史消息投影成带前缀的“历史环境”记录（src/ai/session_runtime.zig Projection.chat）。
const HISTORICAL='[历史环境，仅作记录]\n';const unmark=(content:any)=>typeof content==='string'&&content.startsWith(HISTORICAL)?content.slice(HISTORICAL.length):content;
// rc16 起模型侧执行快照是精简投影（src/ai/execution_result_projection.zig modelContent）：不含 command_accepted / submit_sent / grant 等派发内部字段，
// 改为 has_input_grant；已提交并被本地 shell 接收体现为 state 越过 awaiting_start_boundary / awaiting_accept 进入 running，且带 execution_id。
const submitted=(body:any)=>body?.state==='running'&&body?.snapshot?.state==='running'&&typeof body?.snapshot?.execution_id==='string'&&body.snapshot.execution_id.length>0;
const payload=(envelope:any)=>{for(const block of envelope.content??[])try{return JSON.parse(block.text)}catch{}return envelope};
let draftWindow=false,releaseDraft:()=>void=()=>{};const draftTyped=new Promise<void>(done=>{releaseDraft=done});let second:any=null,secondDone=false,afterConflictDone=false;
let initial:any,group:any,initialMessages:any[]=[],fixtureFailure:string|null=null,currentCall:string|null=null,originalDone=false,continuedDone=false,holdClosed=0,pendingOffered=false,runStarted=false,executionRef:string|null=null,verifiedStop=false;
function get(map:Map<string,any>,id:string,success=true){const envelope=map.get(id);if(!envelope)return null;const body=payload(envelope);results[id]={envelope,body};if(success)assert.equal(envelope.status,'succeeded',id+': '+JSON.stringify(envelope));return body}
function emit(body:any,res:any,id:string,name:string,args:any){assert(body.tools.some((tool:any)=>tool.function.name===wire(name)),name+' unavailable');assert(!calls.some(call=>call.id===id),'tool call must not be reconstructed/reissued');calls.push({id,name,args});currentCall=id;res.end(frame({tool_calls:[{index:0,id,type:'function',function:{name:wire(name),arguments:JSON.stringify(args)}}]})+'data: [DONE]\n\n')}
const server=createServer(async(req,res)=>{try{
 if(req.method!=='POST'){res.writeHead(200,{'content-type':'application/json'});return res.end(JSON.stringify({data:[{id:'fixture-default'},{id:'fixture-retained'}]}))}
 const body=await readRequestJson(req);if(isTitleRequest(body))return skipTitle(res);requests.push(body);await writeFile(join(out,'provider-wire.json'),JSON.stringify(requests,null,2));
 res.writeHead(200,{'content-type':'text/event-stream'});res.flushHeaders();
 const map=new Map<string,any>(body.messages.filter((message:any)=>message.role==='tool').map((message:any)=>[message.tool_call_id,JSON.parse(unmark(message.content))]));
 const question=[...body.messages].reverse().find((message:any)=>message.role==='user')?.content??'';
 assert.equal(body.model,'fixture-retained','explicit conversation model must survive handoff/dismiss/reopen');
 if(String(question).includes('HOLD_CLOSE_STREAM')){currentCall=null;res.on('close',()=>holdClosed++);res.write(frame({content:'HOLD_STREAM_PARTIAL'}));return;}
 if(String(question).includes('AWAIT_CLOSE_APPROVAL')){
  const cancelled=get(map,'retention-pending-close',false);
  if(!cancelled){pendingOffered=true;return emit(body,res,'retention-pending-close','host.run_in_terminal',{session_ref:initial.binding_ref,command:'printf SHOULD_NOT_DISPATCH_CLOSE',request_key:'retention-unapproved-close'});}
  currentCall=null;return res.end(frame({content:'PENDING_CALL_SETTLED'})+'data: [DONE]\n\n');
 }
 if(String(question).includes('RUN_CLOSE_EXECUTION')){
  const ran=get(map,'retention-run-close');if(!ran)return emit(body,res,'retention-run-close','host.run_in_terminal',{session_ref:initial.binding_ref,command:`sh -c 'printf "%s" "$$" > "${executionPidPath}"; exec sleep 30'; printf SHOULD_NOT_RUN_AFTER_CLOSE > "${executionSentinelPath}"`,request_key:'retention-active-close'});
  executionRef=ran.execution_ref;let accepted=ran;
  // The local shell accepts the command after its prompt boundary; how long that takes depends on the machine. A wait that
  // returns early (a revision change that is not yet `running`) used up one of five attempts before, so a slow start (about
  // 4 s under load: preparing -> awaiting_start_boundary -> awaiting_accept) failed although the execution was progressing.
  // Bounded by time instead: 30 s from the first wait. The budget is asked only where another wait would be issued: the
  // next request of this turn (retention-run-wait, up to 30 s later) replays this loop and must still read the answers.
  for(let attempt=0;!submitted(accepted);attempt++){
   const next=get(map,'retention-run-started-'+attempt);if(!next){if(!pollWithin('retention-run-started',30000))break;return emit(body,res,'retention-run-started-'+attempt,'host.wait_execution',{execution_ref:executionRef,after_revision:accepted.source_revision,wait_ms:1000,max_bytes:4096})}accepted=next;
  }
  assert(submitted(accepted),'actual Local native submission/acceptance required before closing');runStarted=true;
  const waited=get(map,'retention-run-wait',false);if(!waited)return emit(body,res,'retention-run-wait','host.wait_execution',{execution_ref:executionRef,after_revision:ran.source_revision,wait_ms:30000,max_bytes:4096});
  currentCall=null;return res.end(frame({content:'RUN_CALL_SETTLED'})+'data: [DONE]\n\n');
 }
 if(String(question).includes('VERIFY_STOPPED_EXECUTION')){
  const context=get(map,'retention-stopped-context');if(!context)return emit(body,res,'retention-stopped-context','host.get_current_context',{});
  assert.equal(context.conversation_id,initial.conversation_id);assert.equal(context.binding_ref,group.group_ref);
  let observed:any=null;for(let attempt=0;;attempt++){
   observed=get(map,'retention-stopped-execution-'+attempt,false);if(!observed){assert(pollWithin('retention-stopped-execution',15000),'Original Local execution did not release after confirmed close');if(attempt)await new Promise(done=>setTimeout(done,100));return emit(body,res,'retention-stopped-execution-'+attempt,'host.get_execution',{execution_ref:executionRef,max_bytes:4096})}
   assert(['succeeded','outcome_unknown'].includes(map.get('retention-stopped-execution-'+attempt).status));
   if(observed.snapshot?.local_released&&observed.snapshot?.input_ready&&observed.snapshot?.has_input_grant===false&&['interval_recorded','sealed','recording_degraded','outcome_unknown'].includes(observed.state))break;
  }
  assert.equal(observed.snapshot.execution_id,executionRef!.slice(3),'stop receipt belongs to the exact submitted execution');assert.equal(observed.execution_ref,executionRef);assert(observed.snapshot.recording_settled);
  if(observed.state==='outcome_unknown'){assert.equal(observed.snapshot.failure,'Stopped');assert(observed.snapshot.remote_effect_unknown);assert.equal(observed.snapshot.process,null)}else assert(observed.snapshot.process&&observed.snapshot.process.exit_code!==0);
  report.stopped_execution=observed;verifiedStop=true;currentCall=null;return res.end(frame({content:'STOPPED_EXECUTION_VERIFIED'})+'data: [DONE]\n\n');
 }
 if(String(question).includes('SECOND_TAB_QUESTION')){
  second=get(map,'second-tab-context');if(!second)return emit(body,res,'second-tab-context','host.get_current_context',{});
  assert.notEqual(second.conversation_id,initial.conversation_id,'independent tab owns a separate conversation');assert('session' in second.current_binding,'independent tab conversation is bound to its own single-card tab');
  assert(!body.messages.some((message:any)=>String(message.content??'').includes('ORIGINAL_HANDOFF')),'group history must not leak into the independent tab conversation');
  secondDone=true;currentCall=null;return res.end(frame({content:'SECOND_TAB_ANSWER'})+'data: [DONE]\n\n');
 }
 if(String(question).includes('AFTER_CONFLICT_CONTINUE')){
  const ctx=get(map,'after-conflict-context');if(!ctx)return emit(body,res,'after-conflict-context','host.get_current_context',{});
  assert.equal(ctx.conversation_id,initial.conversation_id,'group tab keeps the handed-off conversation after another tab with its own conversation joins');assert('group' in ctx.current_binding);assert.equal(ctx.binding_ref,group.group_ref);
  assert(!body.messages.some((message:any)=>/SECOND_TAB_(QUESTION|ANSWER)/.test(String(message.content??''))),'joining tab history is never merged into the group conversation');
  assert(body.messages.some((message:any)=>message.role==='assistant'&&String(message.content).includes('ORIGINAL_HANDOFF_RESULT')),'group conversation history continues');
  afterConflictDone=true;currentCall=null;return res.end(frame({content:'AFTER_CONFLICT_OK'})+'data: [DONE]\n\n');
 }
 if(String(question).includes('CONTINUE_AFTER_REOPEN')){
  for(const original of initialMessages.filter((message:any)=>message.role==='tool'||message.tool_calls?.length)){
   const matches=body.messages.filter((message:any)=>original.role==='tool'?message.role==='tool'&&message.tool_call_id===original.tool_call_id:JSON.stringify(message.tool_calls)===JSON.stringify(original.tool_calls));
   assert.equal(matches.length,1,'original tool messages retained exactly once');assert.equal(matches[0].content,HISTORICAL+(original.content??''),'original wire message retained verbatim, only marked as historical environment');assert.deepEqual({...matches[0],content:unmark(matches[0].content)},{...original,content:original.content??''},'original wire message must remain otherwise unchanged');
  }
  assert(body.messages.some((message:any)=>message.role==='assistant'&&String(message.content).includes('ORIGINAL_HANDOFF_RESULT')));
  const after=get(map,'retention-next-context');if(!after)return emit(body,res,'retention-next-context','host.get_current_context',{});
  assert.equal(after.conversation_id,initial.conversation_id);assert.equal(after.binding_ref,group.group_ref);assert.notEqual(after.task_id,initial.task_id);
  continuedDone=true;currentCall=null;res.end(frame({content:'CONTINUE_AFTER_REOPEN_OK'})+'data: [DONE]\n\n');return;
 }
 initial=get(map,'retention-initial-context');if(!initial)return emit(body,res,'retention-initial-context','host.get_current_context',{});
 assert('session' in initial.current_binding,'conversation starts on the single-card tab');
 group=get(map,'retention-create-group');if(!group){if(!draftWindow){draftWindow=true;res.write(frame({content:'PRE_GROUP_DRAFT_WINDOW '}));await draftTyped}return emit(body,res,'retention-create-group','host.create_group',{initial_session_ref:initial.binding_ref,name:'Handoff retention group',request_key:'handoff-retention-create'});}
 const moved=get(map,'retention-group-context');if(!moved)return emit(body,res,'retention-group-context','host.get_current_context',{});
 assert.equal(moved.conversation_id,initial.conversation_id);assert.equal(moved.task_id,initial.task_id);assert.equal(moved.binding_ref,group.group_ref);assert('group' in moved.current_binding,'after AI create_group the conversation is bound to the group (container) tab');
 const failed=get(map,'retention-failed-read',false);if(!failed)return emit(body,res,'retention-failed-read','host.get_session',{session_ref:initial.binding_ref.slice(0,initial.binding_ref.lastIndexOf(':')+1)+'999999'});
 assert.notEqual(map.get('retention-failed-read').status,'succeeded');assert.equal(failed.error_code??failed.code,'StaleReference');
 initialMessages=structuredClone(body.messages);originalDone=true;currentCall=null;res.end(frame({content:'ORIGINAL_HANDOFF_RESULT — exact original host calls and failed read retained.'})+'data: [DONE]\n\n');
}catch(error){fixtureFailure=String(error);if(!res.headersSent)res.writeHead(500);res.end()}});
await new Promise<void>(done=>server.listen(0,'127.0.0.1',done));
const port=(server.address() as any).port;
await writeFile(join(data,'config.toml'),`[meta]\nconfig_revision=1\n[ui]\ntheme="dark"\n[ai]\ndefault_provider="retention-fixture"\npermission_mode="confirm"\nexecution_mode="auto"\nsession_retention="keep"\n[[ai.providers]]\nid="retention-fixture"\nkind="openai_compat"\nendpoint="http://127.0.0.1:${port}/v1/chat/completions"\nenabled=true\n[[ai.providers.models]]\nname="fixture-default"\ncontext_window=500000\ndefault=true\n[[ai.providers.models]]\nname="fixture-retained"\ncontext_window=500000\n`);
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const log=await open(join(out,'app.log'),'w');
const app=spawn(binary,[],{env:{...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1',ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',ZEROWORK_AI_TOOL_TRACE:'1',ZDOTDIR:zdot},stdio:['ignore',log.fd,log.fd]});
const ended=new Promise<void>(done=>app.once('close',()=>done()));
const alive=()=>app.exitCode===null&&app.signalCode===null;
const shown=(node:any)=>node&&node.hidden!==true&&node.visible!==false&&(node.effective_opacity??1)>0&&node.rect?.w>0&&node.rect?.h>0;
const flat=(node:any):any[]=>node?[node,...(node.children??[]).flatMap(flat)]:[];
const text=(node:any)=>flat(node).map((value:any)=>value.text??'').join('\n');
const visible=(id:string)=>h.waitFor(async()=>(await h.query(id)).find(shown)??null,15000);
const hidden=(id:string)=>h.waitFor(async()=>!(await h.query(id)).some(shown)||null,15000);
const click=async(id:string)=>{report.last_action=id;const node=await visible(id);const clicked=await h.clickTestId(id);report.last_click={id,rect:node.rect,result:clicked};assert(clicked.ok,id)};
const capture=async(name:string)=>{await h.mouseMove(10,10);assert((await h.screenshot(join(out,name+'.png'))).ok);await writeFile(join(out,name+'.json'),JSON.stringify({panel:await h.query('ai.panel'),tabs:await h.query('tabs.strip'),confirmation:await h.query('ai.close.confirmation'),destructive_confirmation:await h.query('ai.session.close.confirmation')},null,2))};
async function settle(done:()=>boolean){const start=performance.now();while(!done()&&performance.now()-start<45000){assert.equal(fixtureFailure,null);if((await h.query('ai.interaction.approve')).some(shown)){assert(['retention-create-group','retention-run-close'].includes(currentCall!));report.approvals.push(currentCall);await click('ai.interaction.approve')}await h.sleep(60)}assert.equal(fixtureFailure,null);assert(done());await h.waitFor(async()=>!(await h.query('ai.stop')).some(shown)||null,15000);await visible('ai.turn.complete')}
// rc18 起窗口 × 是"结束当前会话"（ai_close_confirmation_view.zig：结束并解绑 / 停止并结束；历史和草稿保留，完成后解绑），
// 只隐藏面板改由 − 收起（ai.collapse）。回到同一对话 = 在会话列表里"恢复"（conversation_commands.zig restore → resumeConversation，同一 CID）。
async function dismiss(expectedTitle='结束当前会话？'){await click('ai.close');await visible('ai.close.confirmation');assert.equal(text(await visible('ai.close.confirmation.title')),expectedTitle);await click('ai.close.confirmation.confirm');await h.mouseMove(20,300);await hidden('ai.panel');assert(!(await h.query('ai.session.close.confirmation')).some(shown),'window close must never use the destructive conversation dialog')}
async function collapse(){await click('ai.collapse');await h.mouseMove(20,300);await hidden('ai.panel')}
const chipShows=(chip:any,name:string)=>{const t=String(flat(chip).map((n:any)=>n.text??'').join('')).trim();const base=t.split(' · ')[0];if(base===name)return true;if(!base.endsWith('…'))return false;const p=base.slice(0,-1);return p.length>=3&&name.startsWith(p);};/* ai-redesign-a: the model chip is “model · effort”, ellipsized to the room left (Pencil ⑤). */
async function expectRetained(){assert(text(await visible('ai.panel')).includes('ORIGINAL_HANDOFF_RESULT'));assert(chipShows(await visible('ai.composer.model'),'fixture-retained'))}
async function relaunchRetained(){await click(await aiToggleId());await visible('ai.prompt');await expectRetained()}
async function sessionRows(){const rows:{index:number,text:string}[]=[];for(let index=1;index<=12;index++){const row=(await h.query('ai.session.row.'+index)).find(shown);if(row)rows.push({index,text:text(row)})}return rows}
async function reopen(){await click(await aiToggleId());await visible('ai.prompt');
 assert(!text(await visible('ai.panel')).includes('ORIGINAL_HANDOFF_RESULT'),'× ended the conversation: the tab no longer displays it');await visible('ai.session.unbound');assert(text(await visible('ai.empty.recent')).includes('ORIGINAL_HANDOFF_QUESTION'),'ended conversation stays in recent list');
 // 直接用欢迎页「最近会话」行上的恢复按钮（先开 ai.sessions 弹层的话，这次点击只会用来关闭弹层）。
 const row=await h.waitFor(async()=>(await sessionRows()).find(item=>item.text.includes('ORIGINAL_HANDOFF_QUESTION'))??null,10000);await click('ai.session.restore.'+row.index);await h.sleep(300);(report.restore_probe??=[]).push({feedback:(await h.query('ai.feedback.text')).map((node:any)=>text(node)),confirmation:(await h.query('ai.session.close.confirmation')).some(shown)});
 if(await h.waitFor(async()=>(await h.query('ai.session.close.confirmation')).some(shown)||null,1500).catch(()=>null))await click('ai.session.close.accept');
 await h.waitFor(async()=>text((await h.query('ai.panel')).find(shown)).includes('ORIGINAL_HANDOFF_RESULT')||null,15000);if((await h.query('ai.sessions.menu')).some(shown))await click('ai.sessions.close');await expectRetained()}
const tabIds=async()=>flat((await h.query('tabs.strip')).find(shown)).filter((node:any)=>/^tabs\.tab\.\d+$/.test(node.test_id??'')&&shown(node)).map((node:any)=>node.test_id as string);
const tabNum=(id:string)=>Number(id.slice('tabs.tab.'.length));
const promptText=async()=>String((await h.inputState('ai.prompt')).buffer??'');
async function selectModel(name:string){await click('ai.composer.model');await visible('ai.model.menu');const option=await h.waitFor(async()=>(await h.query('ai.model.option')).find((node:any)=>shown(node)&&text(node).includes(name))??null,15000);assert((await h.clickAt(option.rect.x+option.rect.w/2,option.rect.y+option.rect.h/2)).ok);
 // 新版模型选择器（ai_composer_controls_view.zig）选中后菜单保持打开（模型与推理强度同一弹层），再点模型按钮收起（ai-redesign-a：原生 Popover 无自带关闭钮）。
 await h.waitFor(async()=>(await h.query('ai.model.option')).some((node:any)=>shown(node)&&text(node).includes(name)&&flat(node).some((child:any)=>child.test_id==='ai.model.selected'))||null,15000);await click('ai.composer.model');await hidden('ai.model.menu');/* ai-redesign-a: the chip ellipsizes at 420 (Pencil ⑤); its native tooltip holds the full model name. */assert(chipShows(await visible('ai.composer.model'),name))}
async function clearPrompt(){await click('ai.prompt');await h.key('a',{cmd:true});await h.key('backspace');await h.waitFor(async()=>!(await promptText()).includes('HANDOFF_DRAFT')||null,5000)}
async function launchersShown(){return h.waitFor(async()=>{if((await h.query('ai.panel')).some(shown)){await click('ai.collapse');await h.mouseMove(20,300)}await h.sleep(250);if((await h.query('ai.panel')).some(shown))return null;const count=(await h.query('ai.launcher')).filter(shown).length;return count>0?count:null},10000)}
async function lifecycleRecords(){const path=join(data,'ai','lifecycle.v4.json');return JSON.parse(await readFile(path,'utf8')).records as any[]}
async function quit(){const start=performance.now();const response=await h.request('POST','/quit');const confirmations:string[]=[];while(alive()&&performance.now()-start<20000){try{for(const id of['groups.close.accept','local.close.accept','session.close.accept'])if((await h.query(id)).some(shown)){confirmations.push(id);await h.clickTestId(id)}}catch{}if(alive())await Promise.race([ended,h.sleep(70)])}report.normal_quit={response,confirmations,exit_code:app.exitCode,signal:app.signalCode};assert.equal(app.exitCode,0);assert.equal(app.signalCode,null)}
try{
 await h.waitForServerReady(60000);assert.equal(Number(JSON.parse(await readFile(join(rpc,'owner.json'),'utf8')).pid),app.pid);await h.resizeWindow(1440,900);
 await click('workspace.empty.local');await visible('terminal.surface');
 const before=await tabIds();assert.equal(before.length,1,'one single-card Local tab before AI grouping');const originalTab=before[0];report.original_tab_id=originalTab;
 await click(await aiToggleId());await selectModel('fixture-retained');
 await click('ai.prompt');await h.type_('ORIGINAL_HANDOFF_QUESTION: create a group from this current terminal, then inspect one stale generation without executing commands.');await click('ai.send');
 // 草稿随交接：模型发出建组工具调用前，在同一对话里写一段未发送的草稿。
 await h.waitFor(async()=>{assert.equal(fixtureFailure,null);return draftWindow&&text(await visible('ai.panel')).includes('PRE_GROUP_DRAFT_WINDOW')||null},20000);await click('ai.prompt');await h.type_('HANDOFF_DRAFT_RETAINED');await h.waitFor(async()=>(await promptText()).includes('HANDOFF_DRAFT_RETAINED')||null,5000);releaseDraft();
 await settle(()=>originalDone);assert.deepEqual(report.approvals,['retention-create-group'],'AI create_group dispatched only after explicit approval');await capture('01-original-handoff');
 // 交接后：组 tab 激活，原单卡 tab 已并入组（不再是独立 tab），对话（历史、草稿、显式模型）在组 tab 上继续可见。
 const groupTab=flat((await h.query('groups.tab')).find(shown)).find((node:any)=>/^tabs\.tab\.\d+$/.test(node.test_id??''));assert(groupTab,'group tab published');report.group_tab_id=groupTab.test_id;
 assert.notEqual(groupTab.test_id,originalTab,'conversation moved to a new container tab');assert.deepEqual(await tabIds(),[groupTab.test_id],'original single-card tab is absorbed into the group and no longer a standalone tab');
 assert(text(await visible('ai.panel')).includes('ORIGINAL_HANDOFF_QUESTION'));assert((await promptText()).includes('HANDOFF_DRAFT_RETAINED'),'unsent draft survives handoff to the group tab');assert(chipShows(await visible('ai.composer.model'),'fixture-retained'));
 const handoffRecord=(await lifecycleRecords()).find((record:any)=>record.tool_id==='host.create_group'&&record.request_key==='handoff-retention-create');report.handoff_record=handoffRecord;assert(handoffRecord,'create_group lifecycle record persisted');
 assert.equal(handoffRecord.stage,'succeeded','create_group lifecycle finished');assert.equal(handoffRecord.context.conversation_id,initial.conversation_id);assert.equal(handoffRecord.context.binding.tab,tabNum(originalTab),'conversation was bound to the original single-card tab');assert.equal(handoffRecord.committed_binding.tab,tabNum(groupTab.test_id),'conversation binding committed to the group container tab');assert.notEqual(handoffRecord.committed_binding.tab,handoffRecord.context.binding.tab);
 report.checks.push('AI create_group (approved) hands the single-card tab conversation to the new group container tab: same CID/TaskId, binding tab changes from the original tab to the group tab, history, unsent draft and explicit model stay visible; the original tab is no longer a standalone tab.');
 await click('ai.close');await visible('ai.close.confirmation');await capture('01b-completed-close-confirmation');await click('ai.close.confirmation.cancel');await visible('ai.prompt');assert(text(await visible('ai.panel')).includes('ORIGINAL_HANDOFF_RESULT'));
 await dismiss();assert.equal(await launchersShown(),1,'group tab exposes exactly one conversation entry');await reopen();assert((await promptText()).includes('HANDOFF_DRAFT_RETAINED'));await capture('02-close-reopen');report.checks.push('Completed AI window × ends and unbinds the group-tab conversation (history and draft kept, listed as unbound); restoring it on the group tab brings back the original transcript, draft and explicit model; the group tab has exactly one AI entry.');
 await collapse();await click('toolbar.new_session');await click('session.menu.local');await visible('terminal.surface');const independentTab=(await tabIds()).find(id=>id!==groupTab.test_id)!;assert(independentTab);report.independent_tab_id=independentTab;await click(await aiToggleId());await visible('ai.prompt');assert(!text(await visible('ai.panel')).includes('ORIGINAL_HANDOFF_RESULT'),'independent tab does not display the group conversation');for(const row of (await sessionRows()).filter(row=>row.text.includes('ORIGINAL_HANDOFF_QUESTION')))assert(row.text.includes('已绑定')&&row.text.includes('Handoff retention group'),'recent list shows the conversation bound to the group tab, not this tab: '+row.text);assert(!(await promptText()).includes('HANDOFF_DRAFT_RETAINED'));await collapse();
 await click(groupTab.test_id);await relaunchRetained();assert((await promptText()).includes('HANDOFF_DRAFT_RETAINED'),'draft remains with the group tab conversation');await click('ai.sessions');await visible('ai.session.jump.1');
 const rows=(await sessionRows()).map(row=>row.text);report.session_rows=rows;assert.equal(rows.filter(row=>row.includes('ORIGINAL_HANDOFF_QUESTION')).length,1,'handed-off conversation listed exactly once (not duplicated for the old tab)');assert(text(await visible('ai.session.row.1')).includes('ORIGINAL_HANDOFF_QUESTION'));await capture('03-group-restored-in-list');await click('ai.sessions.close');
 report.checks.push('Switching to an independent real Local and back restores the group conversation with its single listed original row, history, draft and selected model.');
 await clearPrompt();
  await click('ai.prompt');await h.type_('CONTINUE_AFTER_REOPEN');await click('ai.send');await settle(()=>continuedDone);await capture('04-next-task-same-conversation');
 report.checks.push('Next Task has the same CID/group, a new TaskId, and every original tool-call/result wire message unchanged and present exactly once.');
 // 冲突：另一个已有自己对话的独立 tab 并入组 tab（目标组 tab 已有对话）——src/ai/tab_grouping.zig：被拖入 tab 的对话结束（历史保留），组 tab 的对话不变，两段历史不合并。
 await click(independentTab);await visible('terminal.surface');await click(await aiToggleId());await visible('ai.prompt');await selectModel('fixture-retained');await click('ai.prompt');await h.type_('SECOND_TAB_QUESTION');await click('ai.send');await settle(()=>secondDone);assert(text(await visible('ai.panel')).includes('SECOND_TAB_ANSWER'));assert(!text(await visible('ai.panel')).includes('ORIGINAL_HANDOFF'));await capture('10-independent-conversation');
 await click('ai.collapse');await h.mouseMove(20,300);await hidden('ai.panel');
 {const source=(await h.query(independentTab)).find(shown),target=(await h.query(groupTab.test_id)).find(shown);assert(source&&target);const sx=source.rect.x+source.rect.w/2,sy=source.rect.y+source.rect.h/2,tx=target.rect.x+target.rect.w/2,ty=target.rect.y+target.rect.h/2;await h.mouseDown(sx,sy);for(let step=1;step<=8;step++){await h.mouseMove(sx+(tx-sx)*step/8,sy+(ty-sy)*step/8);await h.sleep(40)}await h.sleep(200);await h.mouseUp(tx,ty)}
 await h.waitFor(async()=>{const ids=await tabIds();return ids.length===1&&ids[0]===groupTab.test_id||null},15000);report.checks_conflict_tabs=await tabIds();
 assert.equal(await launchersShown(),1,'group tab with two cards still exposes exactly one conversation entry');
 await click(await aiToggleId());const merged=text(await visible('ai.panel'));assert(merged.includes('ORIGINAL_HANDOFF_RESULT'),'group tab keeps its conversation');assert(!merged.includes('SECOND_TAB_ANSWER'),'joining tab conversation is not shown in the group tab');await capture('11-after-conflict-join');
 await click('ai.sessions');await visible('ai.session.jump.1');{const rows=(await sessionRows()).map(row=>row.text);report.session_rows_after_conflict=rows;assert.equal(rows.filter(row=>row.includes('ORIGINAL_HANDOFF_QUESTION')).length,1);assert.equal(rows.filter(row=>row.includes('SECOND_TAB_QUESTION')).length,1,'ended joining conversation keeps its history in the list')}await capture('12-after-conflict-list');await click('ai.sessions.close');
 await click('ai.prompt');await h.type_('AFTER_CONFLICT_CONTINUE');await click('ai.send');await settle(()=>afterConflictDone);await capture('13-after-conflict-continue');
 report.checks.push('Conflict: a tab owning its own conversation joins the group tab that already has one — the group keeps the handed-off CID and history (no merge), the joining conversation ends with history retained and listed, and the group tab still has a single AI entry.');
 // 冲突验证放在执行停止段之前：组 tab 面板保持打开，继续下面的运行中关闭验证。
 await click('ai.prompt');await h.type_('HOLD_CLOSE_STREAM');await click('ai.send');await h.waitFor(async()=>text(await visible('ai.panel')).includes('HOLD_STREAM_PARTIAL')||null,15000);
 await click('ai.close');await visible('ai.close.confirmation');assert.equal(text(await visible('ai.close.confirmation.title')),'停止并结束当前会话？');assert.equal(holdClosed,0);await capture('05-running-close-confirmation');await click('ai.close.confirmation.cancel');await visible('ai.prompt');assert.equal(holdClosed,0);
 await click('ai.collapse');await h.mouseMove(20,300);await hidden('ai.panel');assert.equal(holdClosed,0,'collapse continues provider');await relaunchRetained();assert(text(await visible('ai.panel')).includes('HOLD_STREAM_PARTIAL'));await dismiss('停止并结束当前会话？');await h.waitFor(()=>holdClosed===1||null,15000);await reopen();await visible('ai.turn.complete');
 report.checks.push('Running × asks 停止并结束 confirmation: cancel preserves provider/window, minus hides while provider continues, confirm cancels provider and ends the conversation; restore returns the same conversation.');
 await click('ai.prompt');await h.type_('AWAIT_CLOSE_APPROVAL');await click('ai.send');await visible('ai.interaction.approve');assert(pendingOffered);await click('ai.close');await visible('ai.close.confirmation');await click('ai.close.confirmation.cancel');await visible('ai.interaction.approve');await dismiss('停止并结束当前会话？');await reopen();await h.waitFor(async()=>!(await h.query('ai.interaction.panel')).some(shown)&&!(await h.query('ai.stop')).some(shown)||null,15000);await visible('ai.turn.complete');await capture('06-unapproved-call-stopped');
 report.checks.push('Confirmed close while an original host tool awaits approval cancels that call; cancel leaves the approval pending and no command is dispatched.');
 await click('ai.prompt');await h.type_('RUN_CLOSE_EXECUTION');await click('ai.send');const started=performance.now();while(!runStarted&&performance.now()-started<20000){assert.equal(fixtureFailure,null);if((await h.query('ai.interaction.approve')).some(shown)){assert.equal(currentCall,'retention-run-close');report.approvals.push(currentCall);await click('ai.interaction.approve')}await h.sleep(60)}assert(runStarted);const foregroundPid=await h.waitFor(async()=>{try{const pid=Number(await readFile(executionPidPath,'utf8'));return pid>0?pid:null}catch{return null}},15000);process.kill(foregroundPid,0);report.foreground_pid=foregroundPid;await visible('terminal.ai_control.takeover');await click('ai.close');await visible('ai.close.confirmation');await capture('07-active-execution-close');await click('ai.close.confirmation.confirm');await h.mouseMove(20,300);await hidden('ai.panel');await h.waitFor(()=>{try{process.kill(foregroundPid,0);return null}catch{return true}},10000);assert.equal(await readFile(executionSentinelPath,'utf8').catch(()=>null),null,'post-sleep effect never ran');report.foreground_stopped=true;await reopen();await h.waitFor(async()=>!(await h.query('ai.stop')).some(shown)||null,15000);
 await click('ai.prompt');await h.type_('VERIFY_STOPPED_EXECUTION');await click('ai.send');
 const stoppedEnvelope=await h.waitFor(async()=>{const trace=await readFile(join(out,'app.log'),'utf8');for(const line of trace.split('\n').reverse()){const at=line.indexOf('AI_TOOL_TRACE ');if(at<0)continue;try{const event=JSON.parse(line.slice(at+14));if(event.event==='tool_feedback'&&event.call_id==='retention-stopped-execution-0')return JSON.parse(event.content)}catch{}}return null},15000);
 assert(['succeeded','outcome_unknown'].includes(stoppedEnvelope.status));const stopped=payload(stoppedEnvelope);assert.equal(stopped.execution_ref,executionRef);assert.equal(stopped.snapshot.execution_id,executionRef!.slice(3));assert(stopped.snapshot.local_released&&stopped.snapshot.input_ready&&stopped.snapshot.has_input_grant===false&&stopped.snapshot.recording_settled);if(stopped.state==='outcome_unknown'){assert.equal(stopped.snapshot.failure,'Stopped');assert(stopped.snapshot.remote_effect_unknown);assert.equal(stopped.snapshot.process,null)}else assert(stopped.snapshot.process&&stopped.snapshot.process.exit_code!==0);report.stopped_execution=stopped;report.stopped_envelope=stoppedEnvelope;verifiedStop=true;
 await h.waitFor(async()=>!(await h.query('ai.stop')).some(shown)||null,15000);await visible('ai.turn.complete');await capture('08-stop-receipt-retained');
 report.checks.push('Confirmed close interrupts the exact real Local foreground execution and releases its input grant; a later Task reads its original settled stop receipt in the same CID, preserving unknown outcome when exact completion is unavailable.');
 await click('ai.collapse');await h.mouseMove(10,10);await hidden('ai.panel');await capture('09-stopped-terminal');report.command_annotations={ai:await h.query('terminal.command.metadata.ai'),state:await h.query('terminal.command.state')};
 await quit();const casts=(await readdir(data,{recursive:true})).filter(path=>String(path).endsWith('.cast'));assert(casts.length>0,'real terminal recordings required');for(const path of casts)assert(!(await readFile(join(data,String(path)),'utf8')).includes('SHOULD_NOT_DISPATCH_CLOSE'),'unapproved command absent from every real terminal recording');report.recordings_checked=casts;report.status='passed';
}catch(error){report.status='failed';report.error=String(error);report.fixture_failure=fixtureFailure;process.exitCode=1;await capture('failure').catch(()=>{})}
finally{report.requests=requests.length;report.calls=calls;report.results=results;let forced=false;if(alive()){forced=true;app.kill('SIGTERM')}await ended;report.cleanup={forced,exit_code:app.exitCode,signal:app.signalCode};server.closeAllConnections();await new Promise<void>(done=>server.close(()=>done()));await log.close();await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));console.log(JSON.stringify({status:report.status,error:report.error,out}))}
