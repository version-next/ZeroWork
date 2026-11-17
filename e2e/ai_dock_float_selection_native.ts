/** What the reader is in the middle of must survive float -> docked split -> float: a text selection in a
 * message, and a message being edited (its unsaved text, the caret, keyboard focus). Private data / RPC only.
 *
 * Contract (docs/ui-revamp/LIFECYCLE.md §2): the AI content is a kept surface that changes host only through
 * `surface_migration.move` — focus, the text selection, an open editor and its caret are never dropped, and the
 * hand-over of the conversation to the split's tab does not rebuild the transcript. The dock / float buttons are
 * placement buttons: a pointer press on them leaves keyboard focus in the content.
 * Closing the panel releases the content view (LIFECYCLE.md §3, checked through `POST /zerowork/lifecycle`); reopening
 * builds it from the model and gives the reader back where the transcript was scrolled, the selection, the edited
 * question's text, caret and focus, and the composer's draft and caret — also when the panel is closed in the middle
 * of an IME composition (the composition is not committed into the draft and nothing is sent).
 * Every check runs and is recorded in the report (`checks`); the script fails at the end if any failed.
 *   node e2e/ai_dock_float_selection_native.ts <prefix> <out> [light|dark] [turns=300]
 * 300 turns = the virtualized history; 12 turns = the plain (non-virtual) transcript.
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdir,mkdtemp,open,writeFile,realpath} from 'node:fs/promises';
import {resolve,join} from 'node:path';
import {aiToggleId} from './ai_entry.ts';
const prefix=resolve(process.argv[2]),out=resolve(process.argv[3]),theme=process.argv[4]==='light'?'light':'dark';
await mkdir(out,{recursive:true});
const iso=await realpath(await mkdtemp('/tmp/zw-dock-selection-'));
const data=join(iso,'data'),rpc=join(iso,'rpc'),zdot=join(iso,'zdot');
for(const p of [data,rpc,zdot])await mkdir(p);
await writeFile(join(zdot,'.zshrc'),"PS1='dock%# '\n");
await writeFile(join(data,'config.toml'),`[ui]\ntheme="${theme}"\n[ai]\ndefault_provider="perf"\n[[ai.providers]]\nid="perf"\nkind="openai_compat"\nendpoint="http://127.0.0.1:9/v1/chat/completions"\nenabled=true\n[[ai.providers.models]]\nname="perf"\ncontext_window=200000\ndefault=true\n`);
const messages:any[]=[],display:any[]=[];
const long='https://example.com/'+'averyveryverylongpathsegment'.repeat(10);
const turns=Number(process.argv[5]??300);
for(let i=0;i<turns;i++){
 // Every third question is long enough to hit the bubble's width cap (an unbreakable run included).
 const text=`历史问题 ${i}：`+(i%3===0?`这一条问题很长，用来撑满用户气泡的宽度上限，并带一个不可断开的长串 ${long} 结束。`:'验证停靠与浮动切换。'),answer=`历史回答 ${i}：保留 **格式**。\n\n这里是第 ${i} 条记录的正文，停靠、浮动来回切换之后阅读位置应当还在这里。`;
 messages.push({role:'user',content:text},{role:'assistant',content:answer});
 const turn={id:i+1,task_id:null,sent_at_ms:i*1000,ended_at_ms:i*1000+100,started_mono_ms:0,elapsed_ms:100,input_tokens:10,output_tokens:20,request_count:1,thinking_started_ms:null,thinking_ended_ms:null,thinking_expanded:false,file_source:null,before:[],after:[],answer,prose:answer,thinking:'',steps:[],notices:[],timeline:[{message:{text:answer,started_ms:0,ended_ms:100,expanded:false,submission:null}}],groups:[]};
 display.push({user:true,text,wire_text:null,turn,attachments:null,images:null},{user:false,text:answer,wire_text:null,turn:null,attachments:null,images:null});
}
await writeFile(join(data,'ai-sessions.v4.jsonl'),JSON.stringify({schema:1,event:{kind:'migrate_closed',initial_origin:{session:987654},conversation:'11111111111111111111111111111111',revision:2,turn:turns,presentation:JSON.stringify({schema:1,messages:display})},messages})+'\n');
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const h=await import(join(prefix,'share/zenit/harness/client.ts'));
const log=await open(join(out,'app.log'),'w');
const app=spawn(join(prefix,'bin/zerowork'),[],{env:{...process.env,ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',ZDOTDIR:zdot,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1'},stdio:['ignore',log.fd,log.fd]});
const ended=new Promise(r=>app.once('exit',(code,signal)=>r({code,signal})));
const shown=(n:any)=>n&&!n.hidden&&n.visible!==false&&(n.effective_opacity??1)>0&&n.rect?.w>0&&n.rect?.h>0;
const visible=(id:string)=>h.waitFor(async()=>(await h.query(id)).find(shown)||null,30000);
const click=async(id:string)=>{report.stage=id;await visible(id);await h.sleep(250);const n=await visible(id);assert((await h.clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok,id)};
const flat=(n:any):any[]=>Array.isArray(n)?n.flatMap(flat):n?[n,...(n.children??[]).flatMap(flat)]:[];
const report:any={prefix,theme,turns,isolated:iso,status:'running',stages:[],checks:[]};
/** Soft assertion: recorded, the run continues. */
const check=(name:string,ok:boolean,detail?:any)=>{report.checks.push({name,ok:!!ok,...(ok?{}:{detail})});return !!ok;};
const shot=(name:string)=>h.screenshot(join(out,`${theme}-${turns}-${name}.png`));
const center=(r:any)=>({x:r.x+r.w/2,y:r.y+r.h/2});
const inView=(n:any,view:any)=>n.rect.y>=view.y+4&&n.rect.y+n.rect.h<=view.y+view.h-4;
/** The selection highlight inside the question `index`: its rects relative to the question's text. */
async function selection(index:number){
 const row=flat(await h.query('ai.message.user.row')).filter((n:any)=>n.test_id==='ai.message.user.row').find((r:any)=>flat(r).some((t:any)=>t.test_id==='ai.message.user.text'&&(t.text??'').includes(`历史问题 ${index}：`)));
 if(!row)return null;
 const text=flat(row).find((n:any)=>n.test_id==='ai.message.user.text');
 const marks=flat(row).filter((n:any)=>n.test_id==='ai.message.selection'&&shown(n));
 return {text:text.rect,marks:marks.map((m:any)=>({dx:m.rect.x-text.rect.x,dy:m.rect.y-text.rect.y,w:m.rect.w,h:m.rect.h}))};
}
const sameMarks=(a:any,b:any,name:string)=>{if(!check(`${name}: the selected question is still mounted`,!!b))return;
 if(!check(`${name}: the text selection is kept`,b.marks.length===a.marks.length,{before:a.marks,after:b.marks}))return;
 check(`${name}: the selection covers the same text`,a.marks.every((m:any,i:number)=>['dx','dy','w','h'].every(k=>Math.abs(m[k]-b.marks[i][k])<1.5)),{before:a.marks,after:b.marks});};
/** Evidence for the report: which node holds the question's text and what has keyboard focus. */
const evidence=async(index:number)=>{const t=flat(await h.query('ai.message.user.text')).find((n:any)=>(n.text??'').includes(`历史问题 ${index}：`));const f=await h.focused().catch(()=>null);return {text_node_id:t?.id??null,conversation_id:(await visible('ai.conversation')).id,focused:f?.test_id??null};};
try{
 await h.waitForServerReady(60000);await h.resizeWindow(1440,1000);
 await click('workspace.empty.local');await visible('terminal.surface');await click(await aiToggleId());await visible('ai.panel');
 await visible('ai.empty.recent');await click('ai.session.copy_use.1');
 if((await h.query('ai.session.close.accept')).some(shown))await click('ai.session.close.accept');
 report.stage='history';await visible('ai.message.user.row');await h.sleep(600);
 report.virtual=(await h.query('ai.history.virtual')).some(shown);assert.equal(report.virtual,turns>24,'virtual history exactly for the long transcript');
 const v=await h.screenPos('ai.conversation.viewport');
 for(let i=0;i<(turns>24?4:1);i++)await h.scrollAt(v.x+v.w/2,v.y+v.h/2,0,turns>24?500:120);
 await h.sleep(600);

 // 1. A text selection inside a question (a short, single-line one fully in view).
 const view=(await visible('ai.conversation.viewport')).rect;
 const texts=flat(await h.query('ai.message.user.text')).filter((n:any)=>n.test_id==='ai.message.user.text'&&shown(n)&&inView(n,view)&&n.rect.h<30);
 assert(texts.length>0,'a single-line question is in view');
 const target=texts[0];const index=Number(/历史问题 (\d+)：/.exec(target.text)![1]);report.selected_index=index;
 const y=target.rect.y+target.rect.h/2;
 await h.mouseDown(target.rect.x+2,y);for(let i=1;i<=6;i++){await h.mouseMove(target.rect.x+2+(target.rect.w-4)*i/6,y);await h.sleep(30);}await h.mouseUp(target.rect.x+target.rect.w-2,y);await h.sleep(300);
 const selected=await selection(index);assert(selected&&selected.marks.length>0,'dragging over the question selects its text');
 assert(selected.marks[0].w>target.rect.w*0.6,`most of the line is selected (${JSON.stringify(selected.marks)} of ${target.rect.w})`);
 const before=await evidence(index);
 report.stages.push({stage:'float',selection:selected,...before});await shot('selected-float');

 await click('ai.dock_to_split');await visible('ai.pane');await h.sleep(1500);
 const docked=await selection(index);const dockedEvidence=await evidence(index);report.stages.push({stage:'docked',selection:docked,...dockedEvidence});await shot('selected-docked');
 sameMarks(selected,docked,'docked');
 check('docked: the conversation node is moved, not rebuilt',dockedEvidence.conversation_id===before.conversation_id,{before,after:dockedEvidence});
 check('docked: the selected message is the same node (the transcript is not rebuilt by the move)',dockedEvidence.text_node_id===before.text_node_id,{before,after:dockedEvidence});
 // Select again where the selection was lost, so the way back is checked on its own.
 if(docked&&docked.marks.length===0){const t=flat(await h.query('ai.message.user.text')).find((n:any)=>(n.text??'').includes(`历史问题 ${index}：`));const ty=t.rect.y+t.rect.h/2;await h.mouseDown(t.rect.x+2,ty);for(let i=1;i<=6;i++){await h.mouseMove(t.rect.x+2+(t.rect.w-4)*i/6,ty);await h.sleep(30);}await h.mouseUp(t.rect.x+t.rect.w-2,ty);await h.sleep(300);}
 const dockedAgain=await selection(index);const beforeBack=await evidence(index);assert(dockedAgain&&dockedAgain.marks.length>0,'a selection exists while docked');
 await click('ai.pane.float');await visible('ai.panel');await h.sleep(1500);
 const floated=await selection(index);const floatedEvidence=await evidence(index);report.stages.push({stage:'float-again',selection:floated,...floatedEvidence});await shot('selected-float-again');
 sameMarks(dockedAgain,floated,'floating again');
 check('floating again: the selected message is the same node',floatedEvidence.text_node_id===beforeBack.text_node_id,{before:beforeBack,after:floatedEvidence});

 // 2. A question being edited: unsaved text, caret and focus.
 const row=flat(await h.query('ai.message.user.row')).filter((n:any)=>n.test_id==='ai.message.user.row').find((r:any)=>flat(r).some((t:any)=>t.test_id==='ai.message.user.text'&&(t.text??'').includes(`历史问题 ${index}：`)));assert(row,'the question is still mounted');
 const edit=flat(row).find((n:any)=>n.test_id==='ai.message.edit');assert(edit,'the question has an edit action');
 await h.mouseMove(center(edit.rect).x,center(edit.rect).y);await h.waitFor(async()=>flat(await h.query('ai.message.edit')).some((n:any)=>(n.effective_opacity??1)>0&&Math.abs(n.rect.y-edit.rect.y)<2)||null,5000);
 assert((await h.clickAt(center(edit.rect).x,center(edit.rect).y)).ok);await visible('ai.message.edit.input');
 await click('ai.message.edit.input');await h.key('a',{cmd:true});await h.type_('尚未保存的草稿 ABCDEF');for(let i=0;i<3;i++)await h.key('left');await h.sleep(200);
 const editing=await h.inputState('ai.message.edit.input');assert.equal(editing.buffer,'尚未保存的草稿 ABCDEF');assert.equal(editing.cursor_pos,editing.buffer_len-3,'caret three characters before the end');
 assert.equal((await h.focused()).test_id,'ai.message.edit.input');
 report.stages.push({stage:'edit-float',buffer:editing.buffer,cursor:editing.cursor_pos});await shot('editing-float');
 const sameEdit=async(name:string)=>{const now=await h.inputState('ai.message.edit.input');const focus=(await h.focused().catch(()=>null))?.test_id??null;report.stages.push({stage:name,buffer:now.buffer,cursor:now.cursor_pos,focused:focus});
  check(`${name}: the unsaved text is kept`,now.buffer===editing.buffer,{buffer:now.buffer});
  check(`${name}: the caret is kept`,now.cursor_pos===editing.cursor_pos,{cursor:now.cursor_pos,expected:editing.cursor_pos});
  check(`${name}: the editor still has keyboard focus`,focus==='ai.message.edit.input',{focused:focus});
  // Put the editor back into the checked state for the next leg (focus it, caret three before the end).
  await click('ai.message.edit.input');await h.key('a',{cmd:true});await h.type_(editing.buffer);for(let i=0;i<3;i++)await h.key('left');await h.sleep(200);};
 await click('ai.dock_to_split');await visible('ai.pane');await h.sleep(1500);await visible('ai.message.edit.input');await shot('editing-docked');
 await sameEdit('edit-docked');
 await click('ai.pane.float');await visible('ai.panel');await h.sleep(1500);await visible('ai.message.edit.input');await shot('editing-float-again');
 await sameEdit('edit-float-again');

 // 3. Close -> reopen: the content view is released while closed and rebuilt from the model on reopen.
 const life=async()=>(await h.request('POST','/zerowork/lifecycle',{})).counters;
 const rowTop=async()=>{const vp=(await visible('ai.conversation.viewport')).rect;const t=flat(await h.query('ai.message.user.row')).filter((n:any)=>n.test_id==='ai.message.user.row').find((r:any)=>flat(r).some((x:any)=>(x.test_id==='ai.message.user.text'&&(x.text??'').includes(`历史问题 ${index}：`))||x.test_id==='ai.message.edit.input'));return t?t.rect.y-vp.y:null;};
 const closeAndReopen=async(name:string)=>{const before=await life();await click('ai.collapse');await h.waitFor(async()=>(await h.query('ai.panel')).some(shown)?null:true,15000);
  const closed=await h.waitFor(async()=>{const c=await life();return c.content_unmounts>before.content_unmounts?c:null},5000).catch(()=>null);
  check(`${name}: closing released the content view`,!!closed,{before,after:await life()});
  check(`${name}: nothing of the content view is left in the window`,(await h.query('ai.conversation.viewport')).length===0&&(await h.query('ai.prompt')).length===0);
  await click(await aiToggleId());await visible('ai.panel');await h.sleep(1500);const reopened=await life();
  check(`${name}: reopening mounted the view once and rebuilt the transcript once`,reopened.content_mounts-before.content_mounts===1&&reopened.conversation_rebuilds-before.conversation_rebuilds===1,{before,reopened});
  report.stages.push({stage:name,mount_ms:reopened.last_content_mount_ns/1e6,rebuilds:reopened.conversation_rebuilds-before.conversation_rebuilds});};
 // 3a. The question being edited (focus, caret three before the end) and the scroll position.
 const editTop=await rowTop();report.edit_top=editTop;
 await closeAndReopen('close-reopen-editing');await visible('ai.message.edit.input');await shot('editing-reopened');
 const editTopAfter=await rowTop();check('close-reopen-editing: the transcript is scrolled where it was',editTop!==null&&editTopAfter!==null&&Math.abs(editTop-editTopAfter)<2,{before:editTop,after:editTopAfter});
 await sameEdit('close-reopen-editing');
 await click('ai.message.edit.cancel');await h.sleep(300);
 // 3b. A selection in the question.
 {const t=flat(await h.query('ai.message.user.text')).find((n:any)=>(n.text??'').includes(`历史问题 ${index}：`));const ty=t.rect.y+t.rect.h/2;await h.mouseDown(t.rect.x+2,ty);for(let i=1;i<=6;i++){await h.mouseMove(t.rect.x+2+(t.rect.w-4)*i/6,ty);await h.sleep(30);}await h.mouseUp(t.rect.x+t.rect.w-2,ty);await h.sleep(300);}
 const beforeClose=await selection(index);assert(beforeClose&&beforeClose.marks.length>0,'a selection exists before closing');const selectTop=await rowTop();
 await closeAndReopen('close-reopen-selection');await shot('selection-reopened');
 sameMarks(beforeClose,await selection(index),'close-reopen-selection');
 const selectTopAfter=await rowTop();check('close-reopen-selection: the transcript is scrolled where it was',selectTop!==null&&selectTopAfter!==null&&Math.abs(selectTop-selectTopAfter)<2,{before:selectTop,after:selectTopAfter});
 // 3c. The composer: a draft, the caret inside it, and an IME composition in progress when the panel closes.
 await click('ai.prompt');await h.key('a',{cmd:true});await h.type_('草稿 DRAFT');await h.key('left');await h.key('left');await h.sleep(150);
 const composing=await h.inputState('ai.prompt');assert.equal(composing.buffer,'草稿 DRAFT');
 await h.imePreedit('zhong',5);await h.sleep(150);const preedit=await h.inputState('ai.prompt');report.stages.push({stage:'ime-before-close',ime_phase:preedit.ime_phase,preedit_len:preedit.ime_preedit_len});
 const requests_before=(await life()).conversation_rebuilds;
 await closeAndReopen('close-reopen-composer');await shot('composer-reopened');
 const reopenedPrompt=await h.inputState('ai.prompt');const promptFocus=(await h.focused().catch(()=>null))?.test_id??null;report.stages.push({stage:'composer-after-reopen',buffer:reopenedPrompt.buffer,cursor:reopenedPrompt.cursor_pos,ime_phase:reopenedPrompt.ime_phase,focused:promptFocus});
 check('close-reopen-composer: the draft is kept and the composition was not committed into it',reopenedPrompt.buffer==='草稿 DRAFT',{buffer:reopenedPrompt.buffer});
 check('close-reopen-composer: the caret is where it was',reopenedPrompt.cursor_pos===composing.cursor_pos,{cursor:reopenedPrompt.cursor_pos,expected:composing.cursor_pos});
 check('close-reopen-composer: no composition is left open',reopenedPrompt.ime_preedit_len===0,{ime:reopenedPrompt.ime_phase});
 check('close-reopen-composer: the composer has the keyboard',promptFocus==='ai.prompt',{focused:promptFocus});
 check('close-reopen-composer: nothing was sent',(await h.query('ai.message.user.text')).every((n:any)=>!(n.text??'').includes('DRAFT')),{requests_before});
 const failed=report.checks.filter((c:any)=>!c.ok);
 assert.equal(failed.length,0,`${failed.length} check(s) failed: ${failed.map((c:any)=>c.name).join('; ')}`);

 assert((await h.request('POST','/zerowork/windows',{action:'quit'})).ok);
 const deadline=performance.now()+20000;
 while(app.exitCode===null&&app.signalCode===null&&performance.now()<deadline){for(const id of ['local.close.accept','session.close.accept','groups.close.accept'])try{if((await h.query(id)).some(shown))await h.clickTestId(id)}catch{};await h.sleep(80)}
 assert.notEqual(app.exitCode,null,'normal Quit completes');assert.deepEqual(await ended,{code:0,signal:null});report.status='passed';
}catch(e){report.status='failed';report.error=String(e);process.exitCode=1;await h.screenshot(join(out,`${theme}-${turns}-failure.png`)).catch(()=>{})}
finally{if(app.exitCode===null&&app.signalCode===null){app.kill('SIGTERM');await ended}await log.close();await writeFile(join(out,`report-${theme}-${turns}.json`),JSON.stringify(report,null,2));}
console.log(JSON.stringify(report,null,2));
