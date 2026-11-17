/** Lifecycle budget (docs/ui-revamp/LIFECYCLE.md §6): node / Scope / after-layout hook counts of the main window
 * per state, how often the heavy things happen, and what a closed AI panel costs. Reads the test-mode diagnostic
 * `POST /zerowork/lifecycle`. A binary without that route (a baseline build, for the before / after table) is
 * measured with `POST /zerowork/windows` (`tree_nodes`, `frame_count`) and nothing is asserted.
 *   node e2e/lifecycle_budget_native.ts <prefix> <out> [light|dark]
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdir,mkdtemp,open,writeFile,realpath} from 'node:fs/promises';
import {resolve,join} from 'node:path';
import {aiToggleId} from './ai_entry.ts';
const prefix=resolve(process.argv[2]),out=resolve(process.argv[3]),theme=process.argv[4]==='light'?'light':'dark';
await mkdir(out,{recursive:true});
const iso=await realpath(await mkdtemp('/tmp/zw-lifecycle-budget-'));
const data=join(iso,'data'),rpc=join(iso,'rpc'),zdot=join(iso,'zdot');
for(const p of [data,rpc,zdot])await mkdir(p);
await writeFile(join(zdot,'.zshrc'),"PS1='budget%# '\n");
await writeFile(join(data,'config.toml'),`[ui]\ntheme="${theme}"\n[ai]\ndefault_provider="perf"\n[[ai.providers]]\nid="perf"\nkind="openai_compat"\nendpoint="http://127.0.0.1:9/v1/chat/completions"\nenabled=true\n[[ai.providers.models]]\nname="perf"\ncontext_window=200000\ndefault=true\n`);
// A short (non-virtual) conversation, so the transcript is real nodes and "not rebuilt by a move" means something.
const turns=12,messages:any[]=[],display:any[]=[];
for(let i=0;i<turns;i++){
 const text=`预算问题 ${i}：停靠与浮动来回切换。`,answer=`预算回答 ${i}：保留 **格式**。\n\n第 ${i} 条记录的正文。`;
 messages.push({role:'user',content:text},{role:'assistant',content:answer});
 const turn={id:i+1,task_id:null,sent_at_ms:i*1000,ended_at_ms:i*1000+100,started_mono_ms:0,elapsed_ms:100,input_tokens:10,output_tokens:20,request_count:1,thinking_started_ms:null,thinking_ended_ms:null,thinking_expanded:false,file_source:null,before:[],after:[],answer,prose:answer,thinking:'',steps:[],notices:[],timeline:[{message:{text:answer,started_ms:0,ended_ms:100,expanded:false,submission:null}}],groups:[]};
 display.push({user:true,text,wire_text:null,turn,attachments:null,images:null},{user:false,text:answer,wire_text:null,turn:null,attachments:null,images:null});
}
await writeFile(join(data,'ai-sessions.v4.jsonl'),JSON.stringify({schema:1,event:{kind:'migrate_closed',initial_origin:{session:987654},conversation:'22222222222222222222222222222222',revision:2,turn:turns,presentation:JSON.stringify({schema:1,messages:display})},messages})+'\n');
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const h=await import(join(prefix,'share/zenit/harness/client.ts'));
const log=await open(join(out,'app.log'),'w');
const app=spawn(join(prefix,'bin/zerowork'),[],{env:{...process.env,ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',ZDOTDIR:zdot,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1'},stdio:['ignore',log.fd,log.fd]});
const ended=new Promise(r=>app.once('exit',(code,signal)=>r({code,signal})));
const shown=(n:any)=>n&&!n.hidden&&n.visible!==false&&(n.effective_opacity??1)>0&&n.rect?.w>0&&n.rect?.h>0;
const visible=(id:string)=>h.waitFor(async()=>(await h.query(id)).find(shown)||null,30000);
const gone=(id:string)=>h.waitFor(async()=>(await h.query(id)).some(shown)?null:true,30000);
const report:any={prefix,theme,isolated:iso,status:'running',states:{},checks:[]};
const click=async(id:string)=>{report.stage=id;await visible(id);await h.sleep(250);const n=await visible(id);assert((await h.clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok,id)};
const check=(name:string,ok:boolean,detail?:any)=>{report.checks.push({name,ok:!!ok,...(ok?{}:{detail})});return !!ok;};

/** Ceilings per state: measured after this package (LIFECYCLE.md §6) plus about 10 %. */
const BUDGET:Record<string,{nodes:number,hooks:number,scopes:number}>={
 shell_one_terminal:{nodes:2140,hooks:56,scopes:2090},   // measured 1946 / 51 / 1897 (the AI content view does not exist)
 ai_open:{nodes:3730,hooks:74,scopes:3530},              // measured 3393 / 67 / 3209 (12-turn transcript)
 ai_docked:{nodes:3830,hooks:74,scopes:3710},            // measured 3477 / 67 / 3372
 ai_closed_again:{nodes:2140,hooks:56,scopes:2090},      // measured 1947 / 51 / 1897 (the content view is released)
};
let hasRoute=true;
const read=async()=>{
 if(hasRoute){const r=await h.request('POST','/zerowork/lifecycle',{}).catch(()=>null);if(r?.ok)return {...r.windows[0],counters:r.counters};hasRoute=false;}
 const w=(await h.request('POST','/zerowork/windows',{})).windows[0];return {frame_count:w.frame_count,tree_nodes:w.tree_nodes};
};
/** At most this many idle windows per state; a window that saw an input event is not a rest window and is measured again. */
const MAX_WINDOWS=3,REST_TIMEOUT_MS=20000,WINDOW_MS=2000,SELFTEST_INPUT=process.env.ZW_LIFECYCLE_SELFTEST_INPUT==='1';
/** The floating card's transition phase (motion probe; absent until the AI panel was first built). */
const motionPhase=async()=>String((await h.query('ai.panel.motion.phase'))[0]?.text??'');
/** A deadline later than this cannot fall inside the window that starts now (the window plus the reads around it). A
 *  step's far deadline (the model list's next refresh, minutes away) is not a reason to wait; a nearer one is waited out. */
const DEADLINE_CLEAR_MS=WINDOW_MS+1000;
/** Rest, by condition (LIFECYCLE.md §5.5), not by waiting a fixed time: the floating card is not in flight, no AI frame
 *  hook would run a pass on its next frame (nothing published, no environment change, no rerun asked — each hook's own
 *  gate in `ai_hooks`), and no hook's deadline falls inside the coming window. */
async function waitRest(name:string){
 const started=performance.now();let last:any=null;
 for(;;){
  const phase=await motionPhase();const r=await read();
  const hooks:any[]=r.counters.ai_hooks;
  last={phase,ai_hooks:hooks};
  if(phase!=='expanding'&&phase!=='collapsing'&&hooks.every((k:any)=>k.due===null&&(k.deadline_in_ms===null||k.deadline_in_ms>DEADLINE_CLEAR_MS)))return {waited_ms:Math.round(performance.now()-started),phase};
  if(performance.now()-started>REST_TIMEOUT_MS)throw new Error(`${name}: not at rest after ${REST_TIMEOUT_MS} ms: ${JSON.stringify(last)}`);
  await h.sleep(50);
 }
}
/** One window's numbers once the window is at rest, and what it does in a two-second idle window. An idle window is
 *  valid only if no input event reached the window during it (`input_epoch`: activation / deactivation, pointer,
 *  keyboard, scroll, resize, system theme — each is a legitimate AI input); otherwise it is measured again. */
async function measure(name:string){
 if(!hasRoute){await h.sleep(1500);const first=await read();await h.sleep(WINDOW_MS);const second=await read();
  const state:any={...second,idle_frames_2s:second.frame_count-first.frame_count};report.states[name]=state;return state;}
 const windows:any[]=[];
 for(let attempt=1;attempt<=MAX_WINDOWS;attempt++){
  const rest=await waitRest(name);
  const first=await read();
  // Self-test of the invalid-window path (ZW_LIFECYCLE_SELFTEST_INPUT=1): a pointer move in the first window of every
  // state must make that window invalid and the state be measured again.
  if(SELFTEST_INPUT&&attempt===1){await h.sleep(WINDOW_MS/4);assert((await h.mouseMove(4,4)).ok,'self-test pointer move');await h.sleep(WINDOW_MS*3/4);}
  else await h.sleep(WINDOW_MS);
  const second=await read();
  const inputs=second.input_epoch-first.input_epoch;
  const d=(k:string)=>second.counters[k]-first.counters[k];
  // AI frame hook work in the idle window (LIFECYCLE.md §5.5): how often the hook ran, how many of those runs were a
  // host pass (the whole step list), and how many per-frame steps ran without a pass.
  const idle_ai={hook_runs:d('ai_hook_runs'),passes:d('ai_passes'),pass_rounds:d('ai_pass_rounds'),frame_steps:d('ai_frame_steps'),reasons:Object.fromEntries(Object.keys(second.counters.ai_pass_reasons).map((r:string)=>[r,second.counters.ai_pass_reasons[r]-first.counters.ai_pass_reasons[r]]).filter(([,v]:any)=>v>0))};
  windows.push({attempt,rest,input_events:inputs,idle_ai});
  if(inputs!==0)continue;
  const state:any={...second,idle_frames_2s:second.frame_count-first.frame_count,idle_ai,rest_windows:windows};
  report.states[name]=state;return state;
 }
 // Every window saw input: there was no rest window to judge (reported as such, not as idle AI work).
 const state:any={...(await read()),rest_windows:windows,no_rest_window:true};
 report.states[name]=state;return state;
}
try{
 await h.waitForServerReady(60000);await h.resizeWindow(1440,1000);
 await click('workspace.empty.local');await visible('terminal.surface');
 const shell=await measure('shell_one_terminal');

 await click(await aiToggleId());await visible('ai.panel');await visible('ai.empty.recent');await click('ai.session.copy_use.1');
 if((await h.query('ai.session.close.accept')).some(shown))await click('ai.session.close.accept');
 await visible('ai.message.user.row');
 const opened=await measure('ai_open');

 await click('ai.dock_to_split');await visible('ai.pane');
 const docked=await measure('ai_docked');
 await click('ai.pane.float');await visible('ai.panel');
 const floated=await measure('ai_float_again');

 await click('ai.collapse');await gone('ai.panel');
 const closed=await measure('ai_closed_again');
 await click(await aiToggleId());await visible('ai.panel');await visible('ai.message.user.row');
 const reopened=await measure('ai_reopened');
 report.has_lifecycle_route=hasRoute;
 // Cost per AI hook run (LIFECYCLE.md §5.5): a run with the host pass (before this package every run was one) and a run
 // without (the gate's comparisons, the per-frame steps).
 if(hasRoute){const c=reopened.counters;report.ai_cost={pass_runs:c.ai_pass_rounds,pass_us_per_run:c.ai_pass_rounds?c.ai_pass_ns/c.ai_pass_rounds/1000:null,idle_runs:c.ai_hook_runs-c.ai_pass_rounds,idle_us_per_run:(c.ai_hook_runs-c.ai_pass_rounds)?c.ai_idle_ns/(c.ai_hook_runs-c.ai_pass_rounds)/1000:null};}

 if(hasRoute){
  // 1. A closed AI panel releases its content view (LIFECYCLE.md §3): only the empty frame stays in the window, and the
  //    window's nodes, after-layout hooks and Scopes are back to what they were before the panel was ever opened.
  check('closed panel: nothing is parked outside the window (the content view is released, not kept)',closed.parked_surfaces===0&&closed.parked_nodes===0,closed);
  check('open panel: nothing is parked',opened.parked_surfaces===0&&reopened.parked_surfaces===0,{opened,reopened});
  check('closed panel: the content view was released',closed.counters.content_unmounts>floated.counters.content_unmounts,{floated:floated.counters,closed:closed.counters});
  check('closed panel: the window tree is back to the size it had before the panel was ever opened (± 8)',Math.abs(closed.tree_nodes-shell.tree_nodes)<=8,{closed:closed.tree_nodes,shell:shell.tree_nodes});
  check('closed panel: after-layout hooks are back to the never-opened count',closed.after_layout_hooks<=shell.after_layout_hooks,{closed:closed.after_layout_hooks,shell:shell.after_layout_hooks});
  check('closed panel: Scopes are back to the never-opened count (± 4)',closed.scopes<=shell.scopes+4,{closed:closed.scopes,shell:shell.scopes});
  check('never opened: the content view does not exist',shell.counters.content_mounts===0,shell.counters);
  check('close: the transcript is not rebuilt',closed.counters.conversation_rebuilds===floated.counters.conversation_rebuilds,{floated:floated.counters,closed:closed.counters});
  check('reopen: the view is mounted once and the transcript built once',reopened.counters.content_mounts-closed.counters.content_mounts===1&&reopened.counters.conversation_rebuilds-closed.counters.conversation_rebuilds===1,{reopened:reopened.counters,closed:closed.counters});
  report.reopen_mount_ms=reopened.counters.last_content_mount_ns/1e6;
  // 1b. The session views follow the shared conversations by subscription (phases, bound count; usage-b5f), and the
  //     subscription belongs to the content view: it exists while the view is mounted, goes with it, and comes back with
  //     a view mounted again after the window bound the shared conversations (no frame walks the rows instead).
  const obs=(s:any)=>({phase:s.counters.ai_phase_observers,binding:s.counters.ai_binding_observers});
  report.observers=Object.fromEntries(Object.entries(report.states).map(([n,s]:any)=>[n,obs(s)]));
  check('open panel: its session list follows the shared conversations (phase and bound-count observers)',obs(opened).phase>=1&&obs(opened).binding>=1,report.observers);
  check('dock / float: moving the view does not add or drop observers',JSON.stringify(obs(docked))===JSON.stringify(obs(opened))&&JSON.stringify(obs(floated))===JSON.stringify(obs(opened)),report.observers);
  check('closed panel: the released view stopped listening (observers back to the never-opened count)',JSON.stringify(obs(closed))===JSON.stringify(obs(shell)),report.observers);
  check('reopen: the view mounted again follows again (same observers as the first open)',JSON.stringify(obs(reopened))===JSON.stringify(obs(opened)),report.observers);
  // 4. At rest the AI frame hook does no AI work (LIFECYCLE.md §5): no host pass in any idle window, whatever frames the
  //    window draws for other reasons (the terminal's caret, its own hooks).
  report.selftest_input=SELFTEST_INPUT;
  if(SELFTEST_INPUT)for(const [name,s] of Object.entries(report.states) as any)check(`self-test ${name}: the window with an injected pointer move was discarded and a later one measured`,!s.no_rest_window&&s.rest_windows.length>=2&&s.rest_windows[0].input_events>0&&s.rest_windows.at(-1).input_events===0,s.rest_windows);
  for(const [name,s] of Object.entries(report.states) as any){
   if(!check(`idle ${name}: a rest window without input events (of ${MAX_WINDOWS})`,!s.no_rest_window,s.rest_windows))continue;
   check(`idle ${name}: no AI host pass while at rest`,s.idle_ai.passes===0,s.rest_windows);
  }
  // 2. Dock and float move the one content node: the transcript is not rebuilt, each way is a bounded number of moves.
  check('dock: the transcript is not rebuilt',docked.counters.conversation_rebuilds===opened.counters.conversation_rebuilds,{opened:opened.counters,docked:docked.counters});
  check('float again: the transcript is not rebuilt',floated.counters.conversation_rebuilds===docked.counters.conversation_rebuilds,{docked:docked.counters,floated:floated.counters});
  check('dock: at most 4 surface moves (the AI content and the terminal into their panes, per presentation)',docked.counters.surface_moves-opened.counters.surface_moves<=4,{opened:opened.counters,docked:docked.counters});
  check('float again: at most 4 surface moves',floated.counters.surface_moves-docked.counters.surface_moves<=4,{docked:docked.counters,floated:floated.counters});
  check('float again: the window tree is the size it had before docking (± 8)',Math.abs(floated.tree_nodes-opened.tree_nodes)<=8,{floated:floated.tree_nodes,opened:opened.tree_nodes});
  // 3. Absolute ceilings.
  for(const [name,limit] of Object.entries(BUDGET)){const s=report.states[name];
   if(limit.nodes===0){check(`budget ${name}: ceilings are set`,false,{measured:{nodes:s.tree_nodes,hooks:s.after_layout_hooks,scopes:s.scopes}});continue;}
   check(`budget ${name}: nodes ${s.tree_nodes} <= ${limit.nodes}`,s.tree_nodes<=limit.nodes);
   check(`budget ${name}: after-layout hooks ${s.after_layout_hooks} <= ${limit.hooks}`,s.after_layout_hooks<=limit.hooks);
   check(`budget ${name}: scopes ${s.scopes} <= ${limit.scopes}`,s.scopes<=limit.scopes);}
  const failed=report.checks.filter((c:any)=>!c.ok);
  assert.equal(failed.length,0,`${failed.length} check(s) failed: ${failed.map((c:any)=>c.name).join('; ')}`);
 }
 assert((await h.request('POST','/zerowork/windows',{action:'quit'})).ok);
 const deadline=performance.now()+20000;
 while(app.exitCode===null&&app.signalCode===null&&performance.now()<deadline){for(const id of ['local.close.accept','session.close.accept','groups.close.accept'])try{if((await h.query(id)).some(shown))await h.clickTestId(id)}catch{};await h.sleep(80)}
 assert.notEqual(app.exitCode,null,'normal Quit completes');assert.deepEqual(await ended,{code:0,signal:null});report.status='passed';
}catch(e){report.status='failed';report.error=String(e);process.exitCode=1;await h.screenshot(join(out,`${theme}-failure.png`)).catch(()=>{})}
finally{if(app.exitCode===null&&app.signalCode===null){app.kill('SIGTERM');await ended}await log.close();await writeFile(join(out,`report-${theme}.json`),JSON.stringify(report,null,2));}
console.log(JSON.stringify(report,null,2));
