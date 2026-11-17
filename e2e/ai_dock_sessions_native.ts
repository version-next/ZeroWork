/** Native AI floating panel: launcher, per-tab conversation lifecycle (new = end + new, × = end + unbind, restore), and explicit list deletion.
 * Full current-CID/group/history stop coverage: ai_group_handoff_retention_native.ts.
 * × uses ai.close.confirmation and ends the conversation (listed, restorable); only list trash removes it.
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import {fixtureSessionIds} from './ai_fixture_discovery.ts';
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {spawn} from 'node:child_process';
import {mkdir,mkdtemp,readFile,writeFile,copyFile,open,rm} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {waitForServerReady,waitFor,query,clickTestId,key,type_,resizeWindow,screenshot,sleep,mouseMove,clickAt} from '../zig-out/share/zenit/harness/client.ts';
import {aiToggleId} from './ai_entry.ts';
import {isTitleRequest,skipTitle} from './ai_title_fixture.ts';
const out=resolve(process.argv[2]??'artifacts/vanta-20261022-round10/native');await mkdir(out,{recursive:true});
const themes=process.argv[3]?[process.argv[3]]:['dark','light','sauber'];
const shown=(n:any)=>n&&n.hidden!==true&&n.visible!==false&&(n.effective_opacity??1)>0&&n.rect?.w>0&&n.rect?.h>0;
const flat=(n:any):any[]=>n?[n,...(n.children??[]).flatMap(flat)]:[];
const text=(n:any)=>flat(n).map(x=>x.text??'').join('\n');
const visible=async(id:string)=>waitFor(async()=>(await query(id)).find(shown)??null,15000);
const hidden=async(id:string)=>waitFor(async()=>!(await query(id)).some(shown)||null,10000);
const click=async(id:string)=>{await visible(id);assert((await clickTestId(id)).ok,id);};
const edit=async(id:string,value:string)=>{await click(id);await key('a',{cmd:true});await type_(value);};
const report:any={status:'running',runs:[]};
for(const theme of themes){
 const dir=join(out,theme);await mkdir(dir,{recursive:true});const iso=await mkdtemp(join(tmpdir(),'zw-r10-')),data=join(iso,'data'),rpc=join(iso,'rpc');await mkdir(data);await mkdir(rpc);
 const run:any={theme,checks:[],captures:[],requests:[],status:'running'};report.runs.push(run);let closed=0;
 const server=createServer(async(req,res)=>{if(req.method!=='POST'){res.writeHead(200,{'Content-Type':'application/json'});res.end(JSON.stringify({data:[{id:'r10-model'}]}));return;}// 模型发现会发 GET /models
 let body='';for await(const chunk of req)body+=chunk;const request=JSON.parse(body);if(isTitleRequest(request))return skipTitle(res);run.requests.push(request);const prompt=[...request.messages].reverse().find((x:any)=>x.role==='user')?.content??'';res.writeHead(200,{'Content-Type':'text/event-stream'});
 if(prompt.includes('TOOL_LONG')&&!request.messages.some((m:any)=>m.role==='tool'&&m.tool_call_id==='r10-long-tool')){
  const ids=fixtureSessionIds(request,res);if(!ids)return;const id=ids[0];
  const command="printf '%s' $$ > '"+join(iso,'tool.pid')+"'; exec sleep 30";
  res.end('data: '+JSON.stringify({choices:[{index:0,delta:{tool_calls:[{index:0,id:'r10-long-tool',type:'function',function:{name:'run_command',arguments:JSON.stringify({session_ids:[id],command})}}]}}]})+'\n\ndata: [DONE]\n\n');return;
 }
 res.write('data: '+JSON.stringify({choices:[{index:0,delta:{content:prompt.includes('HOLD')?'HOLD_STREAM_ACTIVE':prompt.includes('QUESTION_WAIT')?'请确认要检查哪个目录？':'R10_ANSWER_'+prompt}}]})+'\n\n');if(prompt.includes('HOLD')){res.on('close',()=>closed++);return;}res.end('data: [DONE]\n\n');});
 await new Promise<void>(r=>server.listen(0,'127.0.0.1',r));const port=(server.address() as any).port;
 await writeFile(join(data,'config.toml'),`[meta]\nconfig_revision=1\n[ui]\ntheme="${theme}"\nfont_family="Menlo"\nfont_size=14\n[ai]\ndefault_provider="r10"\npermission_mode="confirm"\n[[ai.providers]]\nid="r10"\nkind="openai_compat"\nendpoint="http://127.0.0.1:${port}/v1/chat/completions"\napi_key="local-only"\nenabled=true\n[[ai.providers.models]]\nname="r10-model"\ncontext_window=200000\ndefault=true\n`);
 await copyFile('zig-out/bin/zerowork',join(iso,'zerowork'));await copyFile('zig-out/bin/zw_ipc.so',join(iso,'zw_ipc.so'));
 process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;const env={...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1',ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',ZEROWORK_AI_TOOL_TRACE:'1'};for(const k of ['ZEROWORK_AI_MOCK','ZEROWORK_AI_ENDPOINT','ZEROWORK_AI_MODEL','ZEROWORK_AI_PROVIDER'])delete env[k];
 const log=await open(join(dir,'app.log'),'w'),app=spawn(join(iso,'zerowork'),[],{env,stdio:['ignore',log.fd,log.fd]}),ended=new Promise<void>(r=>app.once('close',()=>r()));
 const cap=async(name:string)=>{if(name.includes('confirm')){const modal=await waitFor(async()=>(await query('ai.close.confirmation')).find((n:any)=>shown(n)&&(n.effective_opacity??1)>=0.99)??null,5000);assert.equal(modal.rect.w,320,'O11 (ai-redesign-c): ConfirmDialog 320');// 672a9a90 起按钮改为 zenit 原生 secondary/primary .sm（去掉了自定义 padding 10 / 高 28 覆盖）：宽度 = 文案宽 + 原生内边距，两颗按钮内边距与高度一致。
 {const cancel=await visible('ai.close.confirmation.cancel'),confirm=await visible('ai.close.confirmation.confirm');run.confirmation_buttons={cancel:cancel.rect,confirm:confirm.rect};assert.equal(cancel.rect.h,confirm.rect.h);assert(cancel.rect.h<=32,'native ConfirmDialog buttons (confirm-undo: zenit ConfirmDialog default size)');const glyph=(confirm.rect.w-cancel.rect.w)/(text(confirm).replace(/\s/g,'').length-2);run.confirmation_buttons.glyph=glyph;assert(glyph>=10&&glyph<=14,'both buttons share the native horizontal padding (width differs only by label glyphs; “结束 AI 会话” mixes CJK with the narrower “AI”)');assert(confirm.rect.x+confirm.rect.w<=modal.rect.x+modal.rect.w,'actions stay inside the bubble')}
 // 确认气泡是 size_policy=fit_content 的 Popover（ai_close_confirmation_view.zig），rc18 起说明文案（历史和草稿保留…完成后解绑…）在 288 宽内折成两行，高度随内容；断言上下内边距对称地包住内容，而不是旧的固定 106。
 {const title=await visible('ai.close.confirmation.title'),confirm=await visible('ai.close.confirmation.confirm');const top=title.rect.y-modal.rect.y,row=Math.max(28,confirm.rect.h),bottom=modal.rect.y+modal.rect.h-(confirm.rect.y+confirm.rect.h+(row-confirm.rect.h)/2);// 按钮在操作行里垂直居中（confirm-undo 起是原生 ConfirmDialog，按钮为原生尺寸 32）
 run.confirmation_geometry={modal:modal.rect,top,bottom};assert(Math.abs(top-bottom)<=1.5,'confirmation hugs its content with symmetric padding');assert(modal.rect.h<=160,'compact two-line confirmation (O11: ConfirmDialog 320 × ~151, native 32 buttons)')}await writeFile(join(dir,name+'.confirmation.json'),JSON.stringify(modal,null,2));}await sleep(120);assert((await screenshot(join(dir,name+'.png'))).ok);await writeFile(join(dir,name+'.json'),JSON.stringify(await query('ai.panel'),null,2));run.captures.push(name);};
 try{
  await waitForServerReady();await resizeWindow(1440,900);await click('workspace.empty.local');await visible('terminal.surface');await mouseMove(20,300);
  // PL4c 4c-2: the floating ai.launcher rests 24 / 20 inside the tab body (was the strip under the title bar).
  const launcher=await visible('ai.launcher'),pane=await visible('workspace.pane');assert.equal(launcher.rect.w,48);assert.equal(launcher.rect.h,48);assert(Math.abs(launcher.rect.x+48-(pane.rect.x+pane.rect.w-24))<1);assert(Math.abs(launcher.rect.y+48-(pane.rect.y+pane.rect.h-20))<1);await cap('01-dock-wide');
  // 466ed589（PL4c 4c-2）删除了 AI 条、悬停预览与“钉住”：悬停浮动图标不再预览面板，只有点击才打开。
  await mouseMove(launcher.rect.x+24,launcher.rect.y+24);await sleep(400);assert(!(await query('ai.panel')).some(shown),'hovering the launcher must not preview the panel');await cap('02-launcher-hover-no-preview');await mouseMove(20,300);run.checks.push('Floating ai.launcher rests 24/20 inside the tab body; hover no longer previews the panel (PL4c)');
  await click(await aiToggleId());await visible('ai.panel');await mouseMove(20,300);await sleep(300);await visible('ai.panel');
  // M10 起每个 tab 只绑定一个 AI 对话：“新建”= 结束当前并新建（ai.session.close.confirmation），× = 结束并解绑（ai.close.confirmation），
  // 结束的对话留在列表里（未绑定）可“恢复”；不再有同一 tab 里并行切换多个已绑定对话（ai_host.zig conversationAction / conversation_commands.zig）。
  const listRows=async()=>flat((await query('ai.sessions.menu')).find(shown)).filter((n:any)=>/^ai\.session\.row\.\d+$/.test(n.test_id??'')).map((n:any)=>({id:Number(n.test_id.split('.').at(-1)),text:text(n),node:n}));
  // 欢迎页「最近会话」与 ai.sessions 弹层里有同名的行按钮；clickTestId 取树中第一个（欢迎页那颗，被弹层盖住，点击只会关掉弹层），弹层里的按钮按坐标点击。
  const menuClick=async(id:string)=>{const node=await waitFor(async()=>flat((await query('ai.sessions.menu')).find(shown)).find((n:any)=>n.test_id===id&&shown(n))??null,10000);assert((await clickAt(node.rect.x+node.rect.w/2,node.rect.y+node.rect.h/2)).ok,id);};
  const prompt=async()=>text((await query('ai.prompt')).find(shown));
  assert(!(await query('ai.empty.recent')).some(shown),'empty state has no recent list before any conversation');await edit('ai.prompt','FIRST_DRAFT');
  await click('ai.session.new');await visible('ai.session.close.confirmation');await click('ai.session.close.cancel');await hidden('ai.session.close.confirmation');assert((await prompt()).includes('FIRST_DRAFT'),'cancel keeps the current conversation and draft');
  await click('ai.session.new');await click('ai.session.close.accept');await waitFor(async()=>!(await prompt()).includes('FIRST_DRAFT')||null,5000);
  // cfbcdf60（AI Chat 重设计 P1）起输入框是原生 W.Textarea（md，autoRows 1–6），空草稿是一行高（旧的固定 46 最小高度已删除）：断言弹层打开前后输入框高度不变，而不是 ≥46。
  const promptIdle=(await visible('ai.prompt')).rect;run.prompt_idle=promptIdle;assert(promptIdle.h>=28&&promptIdle.h<46,'empty draft is one native md Textarea row');
  await click('ai.sessions');await visible('ai.sessions.menu');await cap('03-sessions-list');assert(text(await visible('ai.sessions.heading')).includes('会话'));// 会话列表是挂在 ai.sessions 按钮下的原生 Popover（ai_sessions_view.zig：bottom_start、偏移 6；ai-redesign-c O7：宽 min(360, 面板宽 − 16)、夹在面板左右各 8 以内，高度随行数、不超出面板）。
  const listRect=(await visible('ai.sessions.menu')).rect,anchorRect=(await visible('ai.sessions')).rect;run.list_geometry={list:listRect,anchor:anchorRect};{const panelRect=(await visible('ai.panel')).rect;assert.equal(Math.round(listRect.w),Math.round(Math.min(360,panelRect.w-16)),'O7 (ai-redesign-c): min(360, panel − 16) wide');assert(listRect.x>=panelRect.x-0.5&&listRect.x+listRect.w<=panelRect.x+panelRect.w+0.5,'list stays inside the AI panel');}assert(Math.abs(listRect.y-(anchorRect.y+anchorRect.h+6))<1.5,'list opens 6px below the sessions button');assert(listRect.x+listRect.w<=1440-8+0.5,'list kept inside the viewport padding');assert(listRect.h<240,'two rows should hug content below the 240 cap');const hoverRow=await visible('ai.session.row.1');await mouseMove(hoverRow.rect.x+100,hoverRow.rect.y+15);await cap('03b-session-row-hover');await mouseMove(20,300);const promptBefore=(await visible('ai.prompt')).rect;assert.deepEqual(promptBefore,promptIdle,'the session list popover overlays the panel; it must not squeeze or move the editor');assert((await visible('ai.sessions.menu')).rect.h<=240);run.checks.push('Composer keeps its one-row native editor unchanged while the session list popover is open');
  const rows=await listRows();assert.equal(rows.length,2,'ended draft conversation plus the new one');const first=rows.find((row:any)=>(row.node&&flat(row.node).some((c:any)=>c.test_id==='ai.session.restore.'+row.id)));assert(first,'ended conversation is listed as restorable');for(const row of rows){const menuRect=(await visible('ai.sessions.menu')).rect;assert(Math.abs(row.node.rect.x-menuRect.x-6)<1,'row inset 6');assert(Math.abs(row.node.rect.w-menuRect.w+12)<1,'row width = list − 12')}
  {const restore=flat(first.node).find((c:any)=>c.test_id==='ai.session.restore.'+first.id);assert((await clickAt(restore.rect.x+restore.rect.w/2,restore.rect.y+restore.rect.h/2)).ok)}if(await waitFor(async()=>(await query('ai.session.close.confirmation')).some(shown)||null,1500).catch(()=>null))await click('ai.session.close.accept');await waitFor(async()=>(await prompt()).includes('FIRST_DRAFT')||null,10000);await mouseMove(20,300);await cap('03c-restored-draft');run.checks.push('New asks to end the current conversation (cancel keeps draft); the ended conversation stays listed and Restore brings back its draft');
  // 只有未发送草稿、没有提交过任务的对话：× 直接收起，不弹结束确认，草稿保留（ai_host.zig processLifecycleAction 的 no_submissions 分支）。
  await click('ai.close');await mouseMove(20,300);await hidden('ai.panel');assert(!(await query('ai.close.confirmation')).some(shown));await click(await aiToggleId());await waitFor(async()=>(await prompt()).includes('FIRST_DRAFT')||null,5000);
  await edit('ai.prompt','HOLD_REQUEST');await click('ai.send');await waitFor(()=>run.requests.length?true:null,10000);await waitFor(async()=>text((await query('ai.panel')).find(shown)).includes('HOLD_STREAM_ACTIVE')||null,10000);
  await click('ai.collapse');await hidden('ai.panel');assert.equal(closed,0);await mouseMove(20,300);await click(await aiToggleId());await visible('ai.panel');assert(text((await query('ai.panel')).find(shown)).includes('HOLD_STREAM_ACTIVE'));
  await click('ai.close');await visible('ai.close.confirmation');await cap('04-close-confirm');assert.equal(closed,0);await click('ai.close.confirmation.cancel');await sleep(150);assert.equal(closed,0);await click('ai.close');await click('ai.close.confirmation.confirm');await mouseMove(20,300);await hidden('ai.panel');await waitFor(()=>closed>0||null,10000);run.checks.push('Collapse keeps the stream active; × cancel leaves it active; × confirm aborts the stream and ends the conversation');
  await click(await aiToggleId());await hidden('ai.stop');await click('ai.sessions');await visible('ai.sessions.menu');const ended=(await listRows()).find((row:any)=>row.text.includes('HOLD_REQUEST'));assert(ended&&ended.text.includes('未绑定'),'the ended conversation remains listed, unbound, after confirmed window close');run.checks.push('The original conversation remains listed (unbound) after confirmed window close');
  // 删除只走列表垃圾桶：已绑定的当前对话不能直接删（ai_host.zig requestConversationClose：“请先结束并解绑此 AI 会话”），未绑定的可删。
  await menuClick('ai.session.delete.'+ended.id);if(await waitFor(async()=>(await query('ai.session.close.confirmation')).some(shown)||null,1500).catch(()=>null)){await click('ai.session.close.cancel');await visible('ai.session.row.'+ended.id);if(!(await query('ai.sessions.menu')).some(shown))await click('ai.sessions');await menuClick('ai.session.delete.'+ended.id);await click('ai.session.close.accept')}await hidden('ai.session.row.'+ended.id);assert(!(await query('ai.session.row.'+ended.id)).some(shown));run.checks.push('Explicit list trash removes an ended (unbound) conversation');
  await key('escape');if((await query('ai.sessions.menu')).some(shown))await click('ai.sessions');if((await query('ai.collapse')).some(shown))await click('ai.collapse');await mouseMove(20,300);await hidden('ai.panel');await key('j',{cmd:true});await visible('ai.panel');await mouseMove(20,300);await sleep(300);await visible('ai.panel');await key('j',{cmd:true});await hidden('ai.panel');
  await click(await aiToggleId());await edit('ai.prompt','TOOL_LONG');await click('ai.send');await visible('ai.interaction.approve');await cap('10-await-approval');await click('ai.collapse');await hidden('ai.panel');await mouseMove(20,300);await click(await aiToggleId());await visible('ai.interaction.approve');await cap('11-await-approval-restored');await click('ai.interaction.approve');run.checks.push('Pending tool approval survives collapsing and reopening the panel, then resumes normally');
  const pid=await waitFor(async()=>{try{const p=Number(await readFile(join(iso,'tool.pid'),'utf8'));return p>0?p:null}catch{return null}},12000);
  process.kill(pid,0);await click('ai.close');await click('ai.close.confirmation.cancel');process.kill(pid,0);await click('ai.close');await click('ai.close.confirmation.confirm');await mouseMove(20,300);await hidden('ai.panel');await waitFor(()=>{try{process.kill(pid,0);return null}catch{return true}},12000);run.checks.push('Confirmed × stops the actual native Local sleep and ends its conversation; cancel leaves the process running');
  await click(await aiToggleId());await edit('ai.prompt','QUESTION_WAIT');await click('ai.send');await waitFor(async()=>text((await query('ai.panel')).find(shown)).includes('请确认要检查哪个目录')&&!(await query('ai.stop')).some(shown)||null,10000);await edit('ai.prompt','MY_DIRECTORY_ANSWER');await click('ai.collapse');await hidden('ai.panel');await mouseMove(20,300);await click(await aiToggleId());await waitFor(async()=>(await prompt()).includes('MY_DIRECTORY_ANSWER')||null,5000);await click('ai.send');await waitFor(()=>run.requests.some((r:any)=>r.messages.some((m:any)=>m.role==='user'&&m.content==='MY_DIRECTORY_ANSWER'))||null,10000);const continued=run.requests.find((r:any)=>r.messages.some((m:any)=>m.role==='user'&&m.content==='MY_DIRECTORY_ANSWER'));assert(continued.messages.some((m:any)=>m.role==='assistant'&&m.content.includes('请确认要检查哪个目录')));run.checks.push('Assistant question and unsent reply survive collapsing; continuing sends original assistant question in conversation history');
  await click('toolbar.new_session');await click('session.menu.local');await visible('terminal.surface');await click(await aiToggleId());await edit('ai.prompt','NARROW_TURN');await click('ai.send');await waitFor(async()=>text((await query('ai.panel')).find(shown)).includes('R10_ANSWER_NARROW_TURN')&&!(await query('ai.stop')).some(shown)||null,10000);await click('ai.sessions');const menu=await visible('ai.sessions.menu');const labels=text(menu);assert(labels.includes('·'));await cap('09-owner-tabs-list');await click('ai.sessions');await click('ai.collapse');await mouseMove(20,300);
  await resizeWindow(860,480);await cap('05-launcher-narrow');await click(await aiToggleId());await cap('06-open-narrow');const narrowIdle=(await visible('ai.prompt')).rect;await click('ai.sessions');await cap('07-sessions-narrow');assert.deepEqual((await visible('ai.prompt')).rect,narrowIdle,'compact: the list must not squeeze the editor');assert(narrowIdle.h>=28);{const list=(await visible('ai.sessions.menu')).rect;{const p=(await visible('ai.panel')).rect;assert(list.y+list.h<=p.y+p.h+0.5,'O7 (ai-redesign-c): the list ends inside the AI panel (it was a fixed 240 cap)');}{const panelRect=(await visible('ai.panel')).rect;assert.equal(Math.round(list.w),Math.round(Math.min(360,panelRect.w-16)),'O7: never wider than the panel');assert(list.x>=panelRect.x-0.5&&list.x+list.w<=panelRect.x+panelRect.w+0.5,'compact list stays inside the AI panel');}assert(list.x>=8-0.5&&list.x+list.w<=860-8+0.5,'compact list fits the viewport')}await click('ai.sessions');await click('ai.close');await cap('08-confirm-narrow');await click('ai.close.confirmation.cancel');run.checks.push('⌘J toggles the panel; compact launcher/header/list/confirmation fit native window');
  // 停靠在分屏里时从会话列表操作（LIFECYCLE.md §1“AI 显示在哪属于所属 tab”）：定位别的 tab 的对话 = 切到那个 tab、按那里的形态（浮动）显示，回来时窗格里仍是本 tab 的对话；
  // 查看历史只开历史对话框；恢复 / 使用副本 / 新建 = 本 tab 换对话：窗格留在原处显示新的当前对话、浮动面板不出现、内容节点仍是同一个且在窗格里，之后“浮动”把它浮回、窗格消失。
  {const dock:any={steps:[]};run.dock_sessions=dock;
   const q=async(id:string)=>{const v=await query(id);return Array.isArray(v)?v:[]};
   const isShown=async(id:string)=>(await q(id)).some(shown);
   const transcript=async()=>text((await q('ai.conversation')).find(shown));
   const contentIn=async(host:string)=>flat((await q(host)).find(shown)).some((n:any)=>n.test_id==='ai.content'&&shown(n));
   const inside=(a:any,b:any)=>a&&b&&a.x>=b.x-1&&a.y>=b.y-1&&a.x+a.w<=b.x+b.w+1&&a.y+a.h<=b.y+b.h+1;
   const stripTabs=async()=>flat((await q('tabs.strip')).find(shown)).filter((n:any)=>/^tabs\.tab\.\d+$/.test(n.test_id??'')&&shown(n)).map((n:any)=>n.test_id as string);
   const dockLog=async()=>(await readFile(join(dir,'app.log'),'utf8')).split('\n').filter(l=>l.startsWith('ZW_AI_DOCK ')).map(l=>JSON.parse(l.slice(11)).action);
   const shot=async(name:string)=>{await sleep(150);assert((await screenshot(join(dir,name+'.png'))).ok);run.captures.push(name)};
   // 停靠形态：窗格在、浮动面板不在、同一个内容节点在窗格里、输入框在窗格里、窗格显示 expect 这段对话。
   const docked=async(label:string,expect:string|null,absent:string|null=null)=>{
    const ok=await waitFor(async()=>{if(!(await isShown('ai.pane'))||(await isShown('ai.panel'))||!(await contentIn('ai.pane')))return null;const t=await transcript();if(expect&&!t.includes(expect))return null;if(absent&&t.includes(absent))return null;return true},10000).catch(()=>null);
    const pane=(await q('ai.pane')).find(shown),panel=(await q('ai.panel')).find(shown),t=await transcript();
    dock.steps.push({label,pane:pane?.rect??null,panel:panel?.rect??null,content_in_pane:await contentIn('ai.pane'),transcript:t.replace(/\n+/g,' | ').slice(0,200)});
    assert(ok,`${label}: docked pane shows ${expect??'the new conversation'} (pane ${JSON.stringify(pane?.rect??null)}, floating panel ${JSON.stringify(panel?.rect??null)}, transcript ${JSON.stringify(t.slice(0,160))})`);
    assert.equal((await visible('ai.content')).id,content,`${label}: the same AI content node (no remount)`);
    assert(inside((await visible('ai.prompt')).rect,pane.rect),`${label}: composer inside the pane`);};
   // 浮动形态：面板在、窗格不在、内容节点在面板里。
   const floating=async(label:string,expect:string)=>{
    const ok=await waitFor(async()=>(await isShown('ai.panel'))&&!(await isShown('ai.pane'))&&(await contentIn('ai.panel'))&&(await transcript()).includes(expect)||null,10000).catch(()=>null);
    const pane=(await q('ai.pane')).find(shown),panel=(await q('ai.panel')).find(shown),t=await transcript();
    dock.steps.push({label,pane:pane?.rect??null,panel:panel?.rect??null,content_in_panel:await contentIn('ai.panel'),transcript:t.replace(/\n+/g,' | ').slice(0,200)});
    assert(ok,`${label}: floating panel shows ${expect} and no pane remains (pane ${JSON.stringify(pane?.rect??null)}, panel ${JSON.stringify(panel?.rect??null)})`);};
   // 换对话的那一段里浮动面板一帧也不出现（采样到形态稳定为止）。
   const neverFloats=async(label:string,ms=1500)=>{const until=Date.now()+ms;let samples=0;while(Date.now()<until){assert(!(await isShown('ai.panel')),`${label}: the floating panel must not appear while the AI is docked`);samples++;await sleep(30)}dock.steps.push({label:label+' (no float samples)',samples})};
   const paneMenu=async(label:string)=>{await click('ai.pane.more');const menu=await visible('ai.pane.menu');const item=flat(menu).find((x:any)=>x.text===label&&shown(x));assert(item,'pane menu item '+label);assert((await clickAt(item.rect.x+item.rect.w/2,item.rect.y+item.rect.h/2)).ok)};
   const openList=async()=>{if((await q('ai.sessions.menu')).some(shown))return listRows();await paneMenu('AI 会话列表');await visible('ai.sessions.menu');await sleep(300);return listRows()};
   const actions=(row:any)=>flat(row.node).map((c:any)=>c.test_id??'').filter((t:string)=>/^ai\.session\.(jump|locate|restore|copy_use|delete)\./.test(t));
   const accept=async(label:string)=>{await visible('ai.session.close.confirmation');await click('ai.session.close.accept');await neverFloats(label)};
   await hidden('ai.close.confirmation');await resizeWindow(1440,900);await sleep(500);if(!(await isShown('ai.panel')))await click(await aiToggleId());await visible('ai.panel');await mouseMove(20,300);
   const content=(await visible('ai.content')).id;const before=await stripTabs();
   await click('ai.dock_to_split');await docked('docked on its tab','NARROW_TURN');await shot('12-docked');
   const dockTab=(await stripTabs()).find((id:string)=>!before.includes(id));assert(dockTab,'the split made for the dock has its own tab: '+JSON.stringify(await stripTabs()));
   // 1. 定位别的 tab 的对话：切到那个 tab、在那里浮动显示；回到停靠的 tab，窗格里仍是这个 tab 自己的对话。
   let rows=await openList();const sibling=rows.find((r:any)=>r.text.includes('QUESTION_WAIT'));assert(sibling&&actions(sibling).includes('ai.session.locate.'+sibling.id),'the other tab’s bound conversation offers 定位');
   await menuClick('ai.session.locate.'+sibling.id);await floating('located the other tab’s conversation','QUESTION_WAIT');await shot('13-docked-locate-sibling');
   {const tab=(await q(dockTab)).find(shown);assert((await clickAt(tab.rect.x+tab.rect.w/2,tab.rect.y+tab.rect.h/2)).ok,dockTab)}await mouseMove(20,300);await docked('back on the docked tab','NARROW_TURN','QUESTION_WAIT');
   run.checks.push('Docked: 定位 another tab’s conversation switches to that tab and floats it there; back on the docked tab the pane still shows its own conversation');
   // 2. 查看兄弟会话的历史：历史对话框打开、内容是那段对话；停靠形态不变。
   rows=await openList();await menuClick('ai.session.jump.'+sibling.id);{const history=await visible('ai.history');assert(text(history).includes('QUESTION_WAIT'),'history dialog shows the sibling conversation');assert(await isShown('ai.pane')&&!(await isShown('ai.panel')),'history leaves the AI docked')}await shot('14-docked-sibling-history');
   await click('ai.history.close');await hidden('ai.history');if((await q('ai.sessions.menu')).some(shown)){await key('escape');await hidden('ai.sessions.menu')}await docked('after the history dialog','NARROW_TURN');
   run.checks.push('Docked: 查看历史 of a sibling opens the history dialog and keeps the AI docked');
   // 3. 恢复已结束的会话：窗格显示恢复的会话、浮动面板不出现；“浮动”把它浮回、窗格消失。
   rows=await openList();const ended=rows.find((r:any)=>r.text.includes('TOOL_LONG'));assert(ended&&actions(ended).includes('ai.session.restore.'+ended.id),'the ended conversation offers 恢复');
   await menuClick('ai.session.restore.'+ended.id);await accept('restore while docked');await docked('restored while docked','TOOL_LONG','NARROW_TURN');await mouseMove(20,300);await shot('15-docked-restored');
   await click('ai.pane.float');await floating('restored conversation floated back','TOOL_LONG');await shot('16-restored-floated-back');
   run.checks.push('Docked: 恢复 an ended conversation keeps the AI docked (pane shows it, no floating panel, same content node); 浮动 floats it back and the pane goes');
   // 4. 使用副本、5. 新建：同样是本 tab 换对话，停靠形态保持。
   await click('ai.dock_to_split');await docked('docked again','TOOL_LONG');
   rows=await openList();{const copy=rows.find((r:any)=>r.text.includes('QUESTION_WAIT'));assert(copy&&actions(copy).includes('ai.session.copy_use.'+copy.id),'the sibling offers 使用副本');await menuClick('ai.session.copy_use.'+copy.id)}await accept('use a copy while docked');await docked('copy in use while docked','QUESTION_WAIT','TOOL_LONG');
   // 新对话是欢迎页（它的“最近会话”会列出别的对话的标题，所以按欢迎页标题判定，不按文字缺席判定）。
   const welcomeIn=async(host:string)=>{const title=(await q('ai.empty.title')).find(shown),box=(await q(host)).find(shown);return !!title&&!!box&&inside(title.rect,box.rect)};
   await paneMenu('新建 AI 会话');await accept('new while docked');await docked('new conversation while docked',null);assert(await waitFor(async()=>(await welcomeIn('ai.pane'))||null,10000).catch(()=>null),'the pane shows the new conversation’s welcome page');await mouseMove(20,300);await shot('17-docked-new');
   await click('ai.pane.float');await waitFor(async()=>(await isShown('ai.panel'))&&!(await isShown('ai.pane'))&&(await contentIn('ai.panel'))&&(await welcomeIn('ai.panel'))||null,10000);dock.steps.push({label:'new conversation floated back',panel:(await visible('ai.panel')).rect});
   run.checks.push('Docked: 使用副本 and 新建 keep the AI docked with the new current conversation in the pane; 浮动 floats it back');
   assert.deepEqual(await dockLog(),['dock','float','dock','float'],'only the explicit 放入分屏 / 浮动 change where the AI is shown');
  }
  run.status='passed';
 }catch(e){run.status='failed';run.error=String(e);await cap('failure').catch(()=>{});report.status='failed';}
 finally{app.kill('SIGTERM');await Promise.race([ended,sleep(2000)]);if(app.exitCode===null&&app.signalCode===null){app.kill('SIGKILL');await ended;}server.closeAllConnections();await new Promise<void>(r=>server.close(()=>r()));await log.close();await rm(iso,{recursive:true,force:true});}
 await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));if(run.status!=='passed')break;
}
if(report.runs.every((r:any)=>r.status==='passed'))report.status='passed';await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));console.log(report.status+': '+out);if(report.status!=='passed')process.exitCode=1;
