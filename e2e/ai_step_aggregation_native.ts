/** Aggregation on the production native transcript, with a held local provider.
 * ZW_AI_TEST_PREFIX=/private/tmp/zw-step-aggregation-build node e2e/ai_step_aggregation_native.ts /tmp/evidence
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createServer} from 'node:http';
import {mkdtemp,mkdir,writeFile,readFile,open,rm} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {aiToggleId} from './ai_entry.ts';
import {isTitleRequest,skipTitle} from './ai_title_fixture.ts';
import {settingsNav} from './settings_nav.ts';
import {readRequestText} from './provider_fixture.ts';
const nav=settingsNav();
const prefix=resolve(process.env.ZW_AI_TEST_PREFIX??'/private/tmp/zw-step-aggregation-build');
const out=resolve(process.argv[2]??'/private/tmp/zw-step-aggregation-evidence');
await mkdir(out,{recursive:true});
const iso=await mkdtemp('/private/tmp/zw-step-aggregation-'),data=join(iso,'data'),rpc=join(iso,'rpc'),zdot=join(iso,'zdot');
await mkdir(data);await mkdir(rpc);await mkdir(zdot);await writeFile(join(zdot,'.zshrc'),"PS1='aggregation-test%# '\n");
const frame=(delta:any)=>'data: '+JSON.stringify({choices:[{index:0,delta}]})+'\n\n';
const wire=(name:string)=>name.replaceAll('_','_u').replaceAll('.','__');
let held:any=null,fixtureFailure:string|null=null,requests=0;
const server=createServer(async(req,res)=>{
 try{
  if(req.method!=='POST')return res.end('{"data":[{"id":"aggregation-fixture"}]}');
  const raw=await readRequestText(req);const body=JSON.parse(raw);if(isTitleRequest(body))return skipTitle(res);requests++;
  res.writeHead(200,{'content-type':'text/event-stream'});res.flushHeaders();
  const user=body.messages.findLast((m:any)=>m.role==='user')?.content;
  if(user==='SCROLL_STABILITY'){
   const turn=body.messages.slice(body.messages.findLastIndex((m:any)=>m.role==='user')+1);
   if(!turn.some((m:any)=>m.role==='tool'&&m.tool_call_id?.startsWith('stability-'))){
    return res.end(frame({content:('用于检查阅读位置的已有对话内容。\n\n').repeat(15)})+frame({reasoning_content:('展开后继续阅读这一条思考详情。\n').repeat(30)})+frame({tool_calls:[{index:0,id:'stability-0',type:'function',function:{name:wire('host.get_current_context'),arguments:'{}'}}]})+'data: [DONE]\n\n');
   }
   held=res;return;
  }
  if(user==='SECOND_TURN')return res.end(frame({reasoning_content:'新回合独立思考。'})+frame({content:'SECOND_TURN_COMPLETE'})+'data: [DONE]\n\n');
  if(!body.messages.some((m:any)=>m.role==='tool'&&m.tool_call_id==='aggregation-read')){
   return res.end(frame({content:'先核对当前会话，再检查问题。'})+frame({tool_calls:[{index:0,id:'aggregation-read',type:'function',function:{name:wire('host.get_current_context'),arguments:'{}'}}]})+'data: [DONE]\n\n');
  }
  if(body.messages.some((m:any)=>m.role==='tool'&&m.tool_call_id==='aggregation-fail-2'))return res.end(frame({content:'AGGREGATION_COMPLETE'})+'data: [DONE]\n\n');
  held=res;
 }catch(error){fixtureFailure=String(error);res.end();}
});
await new Promise<void>(r=>server.listen(0,'127.0.0.1',r));
await writeFile(join(data,'config.toml'),`[meta]\nconfig_revision=1\n[ui]\ntheme="sauber"\nfont_size=14\n[ai]\ndefault_provider="aggregation-fixture"\nstep_display="collapsed"\n[[ai.providers]]\nid="aggregation-fixture"\nkind="openai_compat"\nendpoint="http://127.0.0.1:${(server.address()as any).port}/v1/chat/completions"\nenabled=true\n[[ai.providers.models]]\nname="aggregation-fixture"\ncontext_window=200000\ndefault=true\nreasoning=true\n`);
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const h=await import(join(prefix,'share/zenit/harness/client.ts'));
const log=await open(join(out,'app.log'),'w');
const app=spawn(join(prefix,'bin/zerowork'),[],{env:{...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1',ZEROWORK_DATA_DIR:data,ZDOTDIR:zdot,ZEROWORK_AUTOCONNECT:'0',OPENAI_API_KEY:'',ANTHROPIC_API_KEY:''},stdio:['ignore',log.fd,log.fd]});
const ended=new Promise<void>(r=>app.once('close',()=>r()));
const report:any={status:'running',checks:[],requests:0};
const flat=(n:any):any[]=>Array.isArray(n)?n.flatMap(flat):n?[n,...(n.children??[]).flatMap(flat)]:[];
const text=(n:any)=>flat(n).map(n=>typeof n.text==='string'?n.text:'').join(' ');
const shown=(n:any)=>n&&n.visible!==false&&!n.hidden&&(n.effective_opacity??1)>0&&n.rect?.w>0&&n.rect?.h>0;
const visible=(id:string)=>h.waitFor(async()=>{assert.equal(fixtureFailure,null);return(await h.query(id)).find(shown)??null},15000);
const click=async(id:string)=>{report.last_action=id;await visible(id);assert((await h.clickTestId(id)).ok,id)};
const groups=async()=>await h.query('ai.step_group');
const groupHeaders=async()=>await h.query('ai.step_group.header');
const waitGroups=async(count:number)=>h.waitFor(async()=>{const found=await groups();return found.length===count?found:null},10000);
const clickHeader=async(index:number)=>{
 for(let attempt=0;attempt<12;attempt++){
  const n=(await groupHeaders())[index],viewport=await visible('ai.conversation.viewport');assert(n);
  if(n.rect.y>=viewport.rect.y+1&&n.rect.y+n.rect.h<=viewport.rect.y+viewport.rect.h-1){assert((await h.clickAt(n.rect.x+n.rect.w/2,n.rect.y+14)).ok);return}
  await h.scrollAt(viewport.rect.x+viewport.rect.w/2,viewport.rect.y+viewport.rect.h/2,0,n.rect.y<viewport.rect.y?160:-160);await h.sleep(80);
 }
 throw Error('group header did not scroll into view');
};
const capture=async(name:string)=>{assert((await h.screenshot(join(out,name+'.png'))).ok);await writeFile(join(out,name+'.json'),JSON.stringify(await h.query('ai.panel'),null,2))};
const leaveHeader=async()=>{const prompt=await visible('ai.prompt');await h.mouseMove(prompt.rect.x+4,prompt.rect.y+4)};
const send=async(value:string)=>{await click('ai.prompt');await h.type_(value);await click('ai.send')};
const resizePanel=async(delta:number)=>{
 const before=await visible('ai.panel'),handle=await visible('ai.float.resize.w');
 const x=handle.rect.x+handle.rect.w/2,y=handle.rect.y+handle.rect.h/2;
 await h.mouseMove(x,y);await h.mouseDown(x,y);await h.mouseMove(x+delta,y);await h.mouseUp(x+delta,y);
 await h.waitFor(async()=>Math.abs((await visible('ai.panel')).rect.w-(before.rect.w-delta))<1||null,5000);
};
const checkWidths=async(expanded:boolean)=>{
 await h.waitFor(async()=>{
  const conversation=await visible('ai.conversation'),group=(await groups())[0];
  return Math.abs(group.rect.w-(conversation.rect.w-32))<1||null; // Kaf7E: one 16 inset each side
 },5000);
 const group=(await groups())[0],header=(await groupHeaders())[0];
 assert(Math.abs(header.rect.w-group.rect.w)<1,'group header fills the group');
 if(expanded)for(const id of ['ai.tool.result.header','ai.step.header']){
  const cards=await h.query(id);assert(cards.length>0,id);
  // Rows hang on the Disclosure rail: the group width less the rail (1px line + 12 in).
  for(const card of cards)assert(Math.abs(card.rect.w-(group.rect.w-13))<1,id+' follows the group width on the rail');
 }
 return group.rect.w;
};
try{
 await h.waitForServerReady(60000);await h.resizeWindow(1440,1000);await click('workspace.empty.local');await visible('terminal.surface');await click(await aiToggleId());
 await send('请检查当前会话');await h.waitFor(async()=>held||null,20000);await waitGroups(1);
 assert.equal((await groups())[0].rect.h,28,'singleton begins collapsed: one 28 row (W.Disclosure)');
 const header=(await groupHeaders())[0];
 // Kaf7E A5: the chevron and the status glyph are both shown at rest (no hover swap).
 const indicator=async()=>({activity:(await h.query('ai.step_group.status'))[0],arrow:(await h.query('ai.step_group.disclosure'))[0]});
 await leaveHeader();
 let icons=await indicator();assert(shown(icons.activity)&&shown(icons.arrow),'status and chevron both shown');
 const originalTitle=(await h.query('ai.step_group.title'))[0].rect;
 assert(icons.arrow.rect.x<icons.activity.rect.x&&icons.arrow.rect.x<header.rect.x+20,'chevron leads the row, the status follows');
 await h.mouseMove(header.rect.x+header.rect.w/2,header.rect.y+14);await h.sleep(200);
 assert(shown((await indicator()).arrow)&&shown((await indicator()).activity),'hover keeps both glyphs');
 assert.equal((await h.query('ai.step_group.title'))[0].rect.x,originalTitle.x,'hover does not move the title');
 await capture('00-collapsed-hover');
 // Keep the pointer stationary while live steps update the transcript.
 for(let i=0;i<4;i++){
  held.write(frame({reasoning_content:`正在核对当前会话 ${i}。`}));
  await h.waitFor(async()=>text(await h.query('ai.step_group.summary')).includes(`当前会话 ${i}`)||null,5000);
  assert(shown((await indicator()).arrow)&&shown((await indicator()).activity),'glyphs survive live transcript updates');
  // The title text follows the latest step (its width may change); its position does not.
  assert.equal((await h.query('ai.step_group.title'))[0].rect.x,originalTitle.x,'live updates do not move the title');
 }
 await capture('00-live-stationary-hover');await leaveHeader();
 await capture('01-single-collapsed');
 const originalWidth=await checkWidths(false);
 await resizePanel(-240);assert((await checkWidths(false))>originalWidth+230);
 await capture('01-wide-collapsed');
 await clickHeader(0);await h.waitFor(async()=>(await groups())[0].rect.h>28||null,5000);
 await leaveHeader();
 assert.equal((await groupHeaders())[0].a11y?.expanded??true,true,'expanded group reports expanded');
 assert(shown((await indicator()).arrow)&&shown((await indicator()).activity),'expanded group keeps chevron and status');
 report.checks.push('Collapsed group shows chevron + status glyph at rest (W.Disclosure, Kaf7E A5), hover does not move the title, expanded group keeps both after pointer leaves');
 const child=(await h.query('ai.tool.result.header'))[0];assert(child&&child.rect.h===24,'tool card is a 24 step row on the rail (Kaf7E A6)');
 assert.equal((await h.query('ai.tool.result.separator')).length,0,'no dot separator in a step row');
 held.write(frame({reasoning_content:'正在分析代码与终端信息。'}));
 await h.waitFor(async()=>text(await h.query('ai.step_group.summary')).includes('正在分析代码与终端信息')||null,5000);
 assert((await groups())[0].rect.h>28,'append keeps manual expansion');
 assert(text(await h.query('ai.step_group.title')).includes('思考中'));
 held.write(frame({reasoning_content:' 核对错误来源。'}));
 await h.waitFor(async()=>text(await h.query('ai.step.projection')).includes('核对错误来源')||null,5000);
 assert.equal((await h.query('ai.thinking')).length,1,'streamed reasoning updates one step');
 held.write(frame({reasoning_content:'\n最新判断：需要核对命令所在的节点。'}));
 await h.waitFor(async()=>text((await h.query('ai.step_group.summary'))[0]).includes('最新判断：需要核对命令所在的节点')||null,5000);
 assert(text((await h.query('ai.step_group.summary'))[0]).startsWith('· 2 个步骤'),'the count leads the detail');
 assert(text((await h.query('ai.step_group.summary'))[0]).endsWith(text((await h.query('ai.step.projection')).at(-1))),'the latest thought follows the fixed count');
 // 28 trigger + 2 + the rail (2 + 24 tool row + 6 + 24 thinking row + 2): no edges, no card.
 const rail=(await h.query('ai.step_group.content'))[0],lastCard=(await h.query('ai.thinking'))[0],g0=(await groups())[0];
 assert(rail&&lastCard.rect.y+lastCard.rect.h<=rail.rect.y+rail.rect.h+.1,'rows sit on the rail');
 assert(Math.abs(g0.rect.h-(28+2+rail.rect.h))<1,'the group is its trigger plus its rail');
 assert.equal((await h.query('ai.step_group.edge.bottom')).length+(await h.query('ai.step_group.edge.top')).length,0,'no soft edges');
 await capture('02-expanded-latest-cards');
 await checkWidths(true);await capture('02-wide-expanded');
 await resizePanel(280);assert((await checkWidths(true))<originalWidth-30);
 await capture('02-narrow-expanded');
 await resizePanel(-40);await checkWidths(true);
 await clickHeader(0);await h.waitFor(async()=>(await groups())[0].rect.h===28||null,5000);
 held.write(frame({reasoning_content:'\n最新线索：终端命令在内层 Shell 中执行。'}));
 await h.waitFor(async()=>text((await h.query('ai.step_group.summary'))[0]).includes('最新线索：终端命令在内层 Shell 中执行')||null,5000);
 assert(text((await h.query('ai.step_group.summary'))[0]).startsWith('· 2 个步骤'),'collapsed streaming retains the step count');
 assert.equal((await groups())[0].rect.h,28,'live projection does not expand the group');await capture('02-live-thinking-collapsed');
 // The live elapsed clock keeps ticking ("3.9 s", "4.1 s", and "4 s" on a whole second) and its digits are proportional (a "1" is ~3pt narrower than the
 // other digits, which agree within 0.3pt): compare its width only between two samples of the same glyph shape, so the check measures the layout (the clock is
 // never squeezed by the detail; a squeeze takes it far below its text), not which instant each sample was taken at.
 const clockShape=(t:string)=>String(t??'').replace(/[02-9]/g,'0');
 const clockSample=(shape?:string)=>h.waitFor(async()=>{const n=(await h.query('ai.step_group.elapsed'))[0];return n&&/\d\.\d s$/.test(n.text??'')&&(shape===undefined||clockShape(n.text)===shape)?n:null},5000);
 const clockBefore=await clockSample();
 const fixedBefore={title:(await h.query('ai.step_group.title'))[0].rect,elapsed:clockBefore.rect,clock:clockShape(clockBefore.text)};
 held.write(frame({reasoning_content:'\n'+('最新线索：正在核对内层 Shell 的节点、目录和执行结果。'.repeat(30))}));
 await h.waitFor(async()=>text((await h.query('ai.step_group.summary'))[0]).includes('目录和执行结果')||null,5000);
 const panelWidth=(await visible('ai.panel')).rect.w;
 await resizePanel(panelWidth-520);
 const fixedClock=await clockSample(fixedBefore.clock);
 const fixedTitle=(await h.query('ai.step_group.title'))[0],shrinking=(await h.query('ai.step_group.summary'))[0],fixedHeader=(await groupHeaders())[0];
 assert(Math.abs(fixedTitle.rect.w-fixedBefore.title.w)<.1,'the title keeps its full intrinsic width');
 assert(Math.abs(fixedClock.rect.w-fixedBefore.elapsed.w)<2,'elapsed keeps its width '+JSON.stringify({before:fixedBefore.elapsed,after:fixedClock.rect,text:fixedClock.text}));
 assert(shrinking.rect.w>0&&shrinking.rect.x>=fixedTitle.rect.x+fixedTitle.rect.w,'only the detail uses the remaining middle space');
 assert(shrinking.rect.x+shrinking.rect.w<=fixedClock.rect.x,'the detail never overlaps elapsed');
 assert(fixedClock.rect.x+fixedClock.rect.w<=fixedHeader.rect.x+fixedHeader.rect.w-5,'elapsed stays inside the header (0 6 padding)');
 assert.equal((await groups())[0].rect.h,28);
 await capture('02-fixed-count-long-thinking');
 await resizePanel(520-panelWidth);
 report.checks.push('At the supported 520px minimum with a very long thought, the title and elapsed keep their widths and only the detail (count + latest thought) gives way between them');
 await clickHeader(0);await h.waitFor(async()=>(await groups())[0].rect.h>28||null,5000);
 report.checks.push('Dragging the assistant wider and narrower resizes collapsed group headers and expanded tool/thinking cards to the conversation content width');
 report.checks.push('singletons aggregate immediately; appended tools and thinking share one group; stream updates keep count and manual expansion; current native card separator and geometry retained');
 held.write(frame({content:'第一段检查结束，继续检查下一部分。'}));
 held.write(frame({reasoning_content:'第二组的独立思考。'}));
 await waitGroups(2);assert.equal((await groups())[1].rect.h,28,'new group uses collapsed default');
 assert(text((await h.query('ai.step_group.summary'))[0]).includes('2 个步骤'),'completed thinking restores the existing group summary');
 assert(!text((await h.query('ai.step_group.summary'))[0]).includes('最新线索'),'completed thought does not remain projected');
 report.checks.push('live thinking retains the step count beside the thinking card latest line; collapsed streaming stays collapsed; no active thinking restores the original count/tool projection');
 await capture('03-message-boundary');
 // Search reveals exactly the existing AI settings page and the new field.
 await nav.toCategory('ai');await click('settings.search');await h.type_('步骤默认显示');
 await click('settings.field.step_display');await click('settings.step_display.expanded');await click('settings.save');
 await h.waitFor(async()=>(await readFile(join(data,'config.toml'),'utf8')).includes('step_display = "expanded"')||null,10000);
 await capture('04-default-setting');await nav.close(); // the preferences window has no close button: Cmd+W (settings_nav.ts)
 // Settings application must not change groups already created.
 assert.equal((await groups())[1].rect.h,28);
 held.write(frame({content:'现在进入第三部分。'}));held.write(frame({reasoning_content:'第三组按新设置默认展开。'}));
 await waitGroups(3);await h.waitFor(async()=>(await groups())[2].rect.h>28||null,5000);
 assert(text((await h.query('ai.step_group.summary'))[2]).startsWith('· 1 个步骤'),'singleton thinking also retains its step count');
 assert.equal((await groups())[1].rect.h,28,'old group stays collapsed after changing default');
 await capture('05-new-default-expanded');
 await clickHeader(2);await h.waitFor(async()=>(await groups())[2].rect.h===28||null,5000);
 held.write(frame({reasoning_content:' 追加文本仍然保持手动收起。'}));
 await h.waitFor(async()=>text(await h.query('ai.step_group.summary')).includes('追加文本')||null,5000);
 assert.equal((await groups())[2].rect.h,28);
 held.end(frame({tool_calls:[{index:0,id:'aggregation-fail-1',type:'function',function:{name:wire('host.run_in_terminal'),arguments:'{}'}},{index:1,id:'aggregation-fail-2',type:'function',function:{name:wire('host.read_terminal'),arguments:'{}'}}]})+'data: [DONE]\n\n');held=null;await visible('ai.turn.complete');
 await waitGroups(3);
 // Collapsed details are created only when disclosed.
 await clickHeader(2);await h.waitFor(async()=>(await groups())[2].rect.h>28||null,5000);
 const failures=await h.query('ai.request.unsent');assert.equal(failures.length,2,'both unsent failures retained');
 const descendants=flat((await groups())[2]);
 assert.equal(descendants.filter((n:any)=>n.test_id==='ai.request.unsent').length,2,'all failures belong to the existing third group');
 assert(text(await h.query('ai.step_group.summary')).includes('3 个步骤'),'failures counted alongside thinking');
 assert(/· 2 个失败/.test(text((await h.query('ai.step_group.summary'))[2])),'the group detail counts the failures (failed and rejected apart)');
 for(const failure of await h.query('ai.request.unsent')){
  assert(text(failure).includes('未执行'),'failure summary states dispatch outcome');
  // Kaf7E A6: the reason sits under the row (11.5 danger), the row's arguments stay plain.
  const reason=flat(failure).find((n:any)=>n.test_id==='ai.step.error');
  assert(text(reason).includes('未执行'),'preprojected unsent error stays visible under the row');
  assert(!text(reason).includes('已批准'),'approval cannot replace the final error status');
  assert(text(failure).includes('错误码：'),'failure detail includes diagnostic code');
  assert(text(failure).includes('工具：'),'failure detail identifies tool');
  assert(text(failure).includes('原因：'),'failure detail includes readable reason');
 }
 for(let attempt=0;attempt<12;attempt++){
  const failedCard=(await h.query('ai.request.unsent'))[0];
  const failedHeader=flat(failedCard).find((n:any)=>n.test_id==='ai.step.header'),viewport=await visible('ai.conversation.viewport');assert(failedHeader);
  if(failedHeader.rect.y>=viewport.rect.y+1&&failedHeader.rect.y+24<=viewport.rect.y+viewport.rect.h-1){
   await h.clickAt(failedHeader.rect.x+failedHeader.rect.w/2,failedHeader.rect.y+12);break;
  }
  await h.scrollAt(viewport.rect.x+viewport.rect.w-6,viewport.rect.y+viewport.rect.h/2,0,failedHeader.rect.y<viewport.rect.y?160:-160);await h.sleep(80);
 }
 await h.waitFor(async()=>(await h.query('ai.request.unsent'))[0].rect.h>60||null,5000);
 await capture('06-grouped-failures');
 report.checks.push('two unsent tool failures stay inside the consecutive step group; count and warning status retained; diagnostics include tool, parameters, error code and raw error');
 await clickHeader(2);await h.waitFor(async()=>(await groups())[2].rect.h===28||null,5000);
 assert.equal((await groups())[2].rect.h,28,'completion preserves manual collapse');
 report.checks.push('ordinary model messages end groups; setting saves in existing AI page; current groups keep state; subsequent groups use new default; completion does not recollapse or reopen');
 await send('SECOND_TURN');await h.waitFor(async()=>text(await h.query('ai.conversation')).includes('SECOND_TURN_COMPLETE')||null,15000);
 await waitGroups(4);assert((await groups())[3].rect.h>28,'turn boundary always creates a fresh group');
 assert.equal((await groups())[2].rect.h,28,'history clone retains disclosure');
 report.checks.push('new user turn does not merge with the previous group; history preserves disclosure');
 // UI save is persisted and shows the same value when reopening.
 await nav.toCategory('ai');await click('settings.search');await h.key('a',{cmd:true});await h.type_('步骤默认显示');
 assert(text(await h.query('settings.field.step_display')).includes('展开'));
 await nav.close();
 await capture('06-history-state');
 // Recreate the reported combination: an expanded group, open thought/tool
 // details, a scrolled transcript, and new cards appended below the reader.
 await h.resizeWindow(1440,720);
 await send('SCROLL_STABILITY');await h.waitFor(async()=>held||null,20000);await waitGroups(5);
 const clickLastHeader=async(id:string)=>{
  for(let attempt=0;attempt<20;attempt++){
   const card=(await h.query(id)).at(-1),viewport=await visible('ai.conversation.viewport');assert(card);
   if(card.rect.y>=viewport.rect.y+1&&card.rect.y+24<=viewport.rect.y+viewport.rect.h-1){
    await h.clickAt(card.rect.x+card.rect.w/2,card.rect.y+12);return;
   }
   await h.scrollAt(viewport.rect.x+viewport.rect.w-6,viewport.rect.y+viewport.rect.h/2,0,card.rect.y<viewport.rect.y?100:-100);await h.sleep(50);
  }
  throw Error('detail header did not scroll into view: '+id);
 };
 await clickLastHeader('ai.step.header');
 await h.waitFor(async()=>(await h.query('ai.thinking')).at(-1).rect.h>170||null,5000);
 await clickLastHeader('ai.tool.result.header');
 await h.waitFor(async()=>(await groups()).at(-1).rect.h>400||null,5000);
 await h.sleep(300);
 const anchor=async()=>(await h.query('ai.thinking')).at(-1).rect.y;
 const savedY=await anchor(),resultCount=(await h.query('ai.tool.result.header')).length;
 const positions:number[]=[];
 for(let i=1;i<=4;i++){
  const response=held;held=null;
  response.end(frame({tool_calls:[{index:0,id:`stability-${i}`,type:'function',function:{name:wire('host.get_current_context'),arguments:'{}'}}]})+'data: [DONE]\n\n');
  await h.waitFor(async()=>{
   const y=await anchor();positions.push(y);
   assert(Math.abs(y-savedY)<1,`open detail stays at ${savedY}, got ${y} while appending card ${i}`);
   return held&&(await h.query('ai.tool.result.header')).length===resultCount+i?true:null;
  },15000);
  await h.sleep(100);positions.push(await anchor());
  assert(Math.abs(positions.at(-1)!-savedY)<1,'settled reader position stays fixed');
 }
 report.reader_positions=positions;
 await capture('07-expanded-details-new-cards');
 held.end(frame({content:'SCROLL_STABILITY_COMPLETE'})+'data: [DONE]\n\n');held=null;
 await visible('ai.turn.complete');
 report.checks.push('Stationary hover survives repeated live updates; with thought and tool details open, four newly executed cards preserve the scrolled transcript position within 1px');
 report.status='passed';report.requests=requests;
}catch(error){report.status='failed';report.error=String(error);await h.screenshot(join(out,'failure.png')).catch(()=>{});await writeFile(join(out,'failure.json'),JSON.stringify(await h.query('ai.panel'),null,2)).catch(()=>{});process.exitCode=1;}
finally{
 if(held)held.end();server.closeAllConnections();await new Promise<void>(r=>server.close(()=>r()));
 app.kill('SIGTERM');await Promise.race([ended,new Promise<void>(r=>setTimeout(()=>{app.kill('SIGKILL');r()},3000))]);
 await log.close();await rm(iso,{recursive:true,force:true});await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report));
}
