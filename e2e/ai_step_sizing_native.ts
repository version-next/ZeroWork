/** Step disclosure sizing against a local SSE fixture and real Local commands. */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import {fixtureSessionIds} from './ai_fixture_discovery.ts';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createServer} from 'node:http';
import {mkdtemp,mkdir,writeFile,readFile,open,realpath} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {aiToggleId} from './ai_entry.ts';
import {readRequestJson} from './provider_fixture.ts';
import {isTitleRequest,skipTitle} from './ai_title_fixture.ts';
import {pasteboardName,readPasteboardText} from './private_pasteboard.ts';
// 运行器给出 test-mode 前缀（ZW_AI_TEST_PREFIX={prefix}）与主题变体（argv[3]）；不再读 scripts/build_ui_check.sh 的 dist/ui-check-build.json。
const prefix=resolve(process.env.ZW_AI_TEST_PREFIX??'zig-out'),binary=join(prefix,'bin/zerowork');
const h=await import(join(prefix,'share/zenit/harness/client.ts'));
const out=resolve(process.argv[2]??'/private/tmp/zw-step-sizing'),theme=process.argv[3]??'dark';assert(['light','dark','sauber'].includes(theme),'theme '+theme);await mkdir(out,{recursive:true});
const iso=await realpath(await mkdtemp('/tmp/zw-step-sizing-')),data=join(iso,'data'),rpc=join(iso,'rpc');await mkdir(data);await mkdir(rpc);
let mode='thinking',held:any=null;
const frame=(delta:any)=>'data: '+JSON.stringify({choices:[{index:0,delta}]})+'\n\n';
const server=createServer(async(req,res)=>{
 if(req.method!=='POST'){res.end(JSON.stringify({data:[{id:'step-fixture',context_window:200000}]}));return}
 const body=await readRequestJson(req);if(isTitleRequest(body))return skipTitle(res);
 res.writeHead(200,{'content-type':'text/event-stream'});
 if(mode==='thinking'){res.write(frame({reasoning_content:'用户用中文询问我的身份。'}));held=res;return}
 if(!body.messages.slice(body.messages.findLastIndex((m:any)=>m.role==='user')+1).some((m:any)=>m.role==='tool'&&m.tool_call_id?.startsWith('sizing-'))){
  const ids=fixtureSessionIds(body,res);if(!ids)return;const id=ids[0];
  const command=mode==='empty'?'true':mode==='long'?"printf 'OUTPUT_LINE\\n%.0s' {1..30}":'printf SHORT_OUTPUT';
  res.end(frame({tool_calls:[{index:0,id:'sizing-'+mode,type:'function',function:{name:'run_command',arguments:JSON.stringify({session_ids:[id],command})}}]})+'data: [DONE]\n\n');return;
 }
 res.end(frame({content:'验证完成。'})+'data: [DONE]\n\n');
});
await new Promise<void>(r=>server.listen(0,'127.0.0.1',r));const port=(server.address() as any).port;
await writeFile(join(data,'config.toml'),`[meta]\nconfig_revision=1\n[ui]\ntheme="${theme}"\nfont_family="Menlo"\nfont_size=14\n[ai]\ndefault_provider="fixture"\npermission_mode="confirm"\n[[ai.providers]]\nid="fixture"\nkind="openai_compat"\nendpoint="http://127.0.0.1:${port}/v1/chat/completions"\nenabled=true\n[[ai.providers.models]]\nname="step-fixture"\ncontext_window=200000\ndefault=true\n`);
pasteboardName();  // refuses to run without a private pasteboard: the copy / paste checks must not reach the system clipboard
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const log=await open(join(out,'app.log'),'w');
const app=spawn(binary,[],{env:{...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1',ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',OPENAI_API_KEY:'',ANTHROPIC_API_KEY:''},stdio:['ignore',log.fd,log.fd]});
const shown=(n:any)=>n&&n.hidden!==true&&n.visible!==false&&(n.effective_opacity??1)>0&&n.rect?.w>0&&n.rect?.h>0;
const visible=(id:string)=>h.waitFor(async()=>(await h.query(id)).find(shown)??null,15000);
const click=async(id:string)=>{await visible(id);assert((await h.clickTestId(id)).ok,id)};
// 行头点击：步骤行（思考 / 工具结果）头部 24 高，点头部中线。
const header=async(id:string)=>{const n=await visible(id);assert((await h.clickAt(n.rect.x+100,n.rect.y+12)).ok)};
const absent=(id:string)=>h.waitFor(async()=>!(await h.query(id)).some(shown)||null,15000);
const cap=async(name:string)=>{await h.sleep(200);assert((await h.screenshot(join(out,name+'.png'))).ok);await writeFile(join(out,name+'.json'),JSON.stringify(await h.query('ai.panel'),null,2))};
const send=async()=>{await click('ai.prompt');await h.key('a',{cmd:true});await h.type_('检查步骤展开布局');await click('ai.send')};
const flat=(n:any):any[]=>Array.isArray(n)?n.flatMap(flat):n?[n,...(n.children??[]).flatMap(flat)]:[];
const resultCard=()=>h.waitFor(async()=>flat(await h.query('ai.panel')).find((n:any)=>/^ai\.tool\.result\.\d+\.[0-9a-f]+$/.test(n.test_id??'')&&shown(n))??null,15000);
// 现行几何（Pencil Kaf7E A6，143c4c7b；src/features/ai/cards/view/ai_tool_results_styles.zig、ai_step_view.zig）：
// 步骤行（思考也是步骤行）头部 row_height 24；展开的说明井 stepDetail 上边距 2、高度 fit max 150（ai_step_view.zig ScrollArea .fit max 150），不显示复制（copy_detail=false）；
// 工具结果卡 = 头部 24 + 正文 fit max 150 + 页脚 28，折叠后只剩头部 24。旧版 58 / 182 / 32 / 216 的手搓尺寸已不存在。
const rowH=24,detailTop=2,bodyMax=150,footerH=28;
const thinkingSettled=(want:(t:any,d:any)=>boolean)=>h.waitFor(async()=>{const t=(await h.query('ai.thinking')).find(shown),d=(await h.query('ai.step.details')).find(shown);return t&&d&&Math.abs(t.rect.h-(rowH+detailTop+d.rect.h))<.5&&want(t,d)?{t,d}:null},5000);
const cardHeight=(want:number)=>h.waitFor(async()=>{const c=await resultCard();return Math.abs(c.rect.h-want)<.5?c:null},5000);
const expandGroups=async()=>{for(const g of (await h.query('ai.step_group.header')).filter(shown))if(!(await h.query('ai.step_group.content')).some(shown)){assert((await h.clickAt(g.rect.x+60,g.rect.y+g.rect.h/2)).ok);await h.waitFor(async()=>(await h.query('ai.step_group.content')).some(shown)||null,5000)}};
const report:any={status:'running',checks:[],heights:{},isolated:iso};
try{
 await h.waitForServerReady(60000);await h.resizeWindow(1200,900);await click('workspace.empty.local');await visible('terminal.surface');await click(await aiToggleId());await click('ai.maximize');
 await send();await visible('ai.step_group.header');await expandGroups();await visible('ai.thinking');await header('ai.thinking');
 let {t:thinking,d:details}=await thinkingSettled((t,d)=>d.rect.h<bodyMax);
 assert.equal((await h.query('ai.step.copy')).length,0,'thinking has no copy action');report.heights.shortThought=thinking.rect.h;await cap('01-short-thinking');
 held.write(frame({reasoning_content:'\n'+Array.from({length:30},(_,i)=>`思考内容第 ${i+1} 行`).join('\n')}));
 ({t:thinking,d:details}=await thinkingSettled((t,d)=>Math.abs(d.rect.h-bodyMax)<.5));assert.equal(thinking.rect.h,rowH+detailTop+bodyMax);
 assert((await visible('ai.step.detail')).rect.h>bodyMax,'long thinking overflows its bounded well');report.heights.longThought=thinking.rect.h;await cap('02-long-thinking');
 const body=await visible('ai.step.details'),before=(await visible('ai.step.detail')).rect.y;
 // 展开的思考跟随流式尾部（ai_thinking_scroll_native 覆盖跟随细节），这里验证有界井可以向上滚回开头。
 await h.scrollAt(body.rect.x+body.rect.w/2,body.rect.y+body.rect.h/2,0,1000);
 await h.waitFor(async()=>{const d=await visible('ai.step.detail');return d.rect.y>before+20&&Math.abs(d.rect.y-body.rect.y)<12?d:null},5000);
 assert.equal((await visible('ai.thinking')).rect.h,rowH+detailTop+bodyMax,'scrolling the well never changes the row height');
 held.end(frame({content:'验证完成。'})+'data: [DONE]\n\n');held=null;await absent('ai.stop');
 await header('ai.thinking');await h.waitFor(async()=>Math.abs((await visible('ai.thinking')).rect.h-rowH)<.5||null,5000);report.checks.push('Thought: short well fits its text, long well capped at 150 (row 176) and scrolls, collapses to the 24 row, no Copy node');
 // 每种结果开一个新对话（M10：一个页签绑定一个对话，“新建对话”先确认结束当前对话），审批在输入区交互卡（ai_composer_interaction.yix：ai.interaction.approve）。
 // 夹具先经产品工具 host.list_sessions 发现会话（ai_fixture_discovery.ts），所以一个回合里有两张工具卡；只看命令就是本轮命令的那一张，卡内节点按卡取。
 const commands:Record<string,string>={empty:'true',long:"printf 'OUTPUT_LINE\\n%.0s' {1..30}",short:'printf SHORT_OUTPUT'};
 const node=(card:any,id:string)=>flat(card).find((n:any)=>n.test_id===id);
 const runCard=(command:string)=>h.waitFor(async()=>flat(await h.query('ai.panel')).find((n:any)=>/^ai\.tool\.result\.\d+\.[0-9a-f]+$/.test(n.test_id??'')&&shown(n)&&node(n,'ai.tool.result.command')?.text===command)??null,15000);
 const clickNode=async(n:any)=>assert((await h.clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok);
 for(const kind of ['short','empty','long']){
  mode=kind;const command=commands[kind];await click('ai.session.new');await click('ai.session.close.accept');await absent('ai.session.close.confirmation');
  await send();await visible('ai.interaction.panel');assert(flat(await visible('ai.interaction.command')).map((n:any)=>n.text??'').join('').includes(command),'approval shows the exact command');await click('ai.interaction.approve');await absent('ai.stop');await expandGroups();
  let card=await runCard(command);assert.equal(card.rect.h,rowH,'a result card starts collapsed to its 24 row');
  await clickNode(node(card,'ai.tool.result.header'));
  card=await h.waitFor(async()=>{const c=await runCard(command),d=node(c,'ai.tool.result.details');return d&&shown(d)&&Math.abs(c.rect.h-(rowH+d.rect.h+footerH))<.5?c:null},5000);
  const details=node(card,'ai.tool.result.details');report.heights[kind]={card:card.rect.h,body:details.rect.h};assert(details.rect.h<=bodyMax+.5);assert(card.rect.h<=rowH+bodyMax+footerH+.5);
  const visibleIn=(id:string)=>{const n=node(card,id);return !!n&&shown(n)};
  if(kind==='empty'){assert(details.rect.h<bodyMax,'an empty result shrinks its body');for(const id of ['ai.tool.result.copy_stdout','ai.tool.result.copy_stderr','ai.tool.result.output_label'])assert(!visibleIn(id),id+' hidden for an empty result')}
  if(kind==='short'){assert.equal(node(card,'ai.tool.result.stdout').text,'SHORT_OUTPUT');await clickNode(node(card,'ai.tool.result.copy_stdout'));await click('ai.prompt');await h.key('a',{cmd:true});await h.key('v',{cmd:true});await h.waitFor(async()=>(await h.inputState('ai.prompt')).buffer==='SHORT_OUTPUT'||null,5000)}
  if(kind==='long'){
   assert(Math.abs(details.rect.h-bodyMax)<.5,'a long result body is capped at 150');
   const output=node(card,'ai.tool.result.stdout_scroll');assert(output.rect.h>details.rect.h);/* 输出井是原生 W.CodeBlock（43eada2b），文本节点只排可见行；完整内容用“复制结果内容”核对（写本条目的私有 pasteboard） */await clickNode(node(card,'ai.tool.result.copy_stdout'));assert.equal(await h.waitFor(async()=>{const t=await readPasteboardText();return t?.startsWith('OUTPUT_LINE')?t:null},5000),'OUTPUT_LINE\n'.repeat(30));
   const y=output.rect.y;await h.scrollAt(details.rect.x+details.rect.w/2,details.rect.y+details.rect.h/2,0,-1000);
   await h.waitFor(async()=>node(await runCard(command),'ai.tool.result.stdout_scroll').rect.y<y||null,5000);
  }
  await cap('03-tool-'+kind);await clickNode(node(await runCard(command),'ai.tool.result.header'));await h.waitFor(async()=>Math.abs((await runCard(command)).rect.h-rowH)<.5||null,5000);
 }
 report.checks.push('Real Local short/empty/30-line results: collapsed 24 row, body capped at 150 (+24 header +28 footer); empty result shrinks and hides output label and copy actions; stdout copy pastes back exactly (private pasteboard); long output scrolls in the bounded body');report.status='passed';
}catch(e){report.status='failed';report.error=String(e);await cap('failure').catch(()=>{});process.exitCode=1}
finally{if(held)held.end();server.closeAllConnections();await new Promise<void>(r=>server.close(()=>r()));app.kill('SIGTERM');if(app.exitCode===null&&app.signalCode===null)await new Promise(r=>app.once('close',r));await log.close();await writeFile(join(out,'report.json'),JSON.stringify(report,null,2))}
console.log(JSON.stringify(report));
