/** PATCH scroll ownership in the production window, using an owned deterministic SSE fixture. */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createServer} from 'node:http';
import {mkdtemp,mkdir,writeFile,readFile,open,realpath} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {aiToggleId} from './ai_entry.ts';
import {isTitleRequest,skipTitle} from './ai_title_fixture.ts';
import {readRequestJson} from './provider_fixture.ts';
import {pasteboardName,readPasteboardText} from './private_pasteboard.ts';
const prefix=resolve(process.env.ZW_AI_TEST_PREFIX??'dist/patch-card-scroll-candidate');
const h=await import(join(prefix,'share/zenit/harness/client.ts'));
const out=resolve(process.argv[2]??'dist/ui-acceptance/patch-card-scroll');await mkdir(out,{recursive:true});
const isolated=await realpath(await mkdtemp('/tmp/zw-card-scroll-')),data=join(isolated,'data'),rpc=join(isolated,'rpc');await mkdir(data);await mkdir(rpc);
const frame=(delta:any)=>'data: '+JSON.stringify({choices:[{index:0,delta}]})+'\n\n';
let held:any=null,requests=0;
const server=createServer(async(req,res)=>{
 if(req.method!=='POST'){res.writeHead(200,{'content-type':'application/json'});res.end(JSON.stringify({data:[{id:'card-scroll-fixture',context_window:200000}]}));return}
 const body=await readRequestJson(req);if(isTitleRequest(body))return skipTitle(res);requests++;
 res.writeHead(200,{'content-type':'text/event-stream'});
 if(!body.messages.some((m:any)=>m.role==='tool')){
  const name='host__get_ucurrent_ucontext';assert(body.tools.some((t:any)=>t.function.name===name));
  res.end(frame({reasoning_content:'短思考。',tool_calls:[{index:0,id:'card-scroll-context',type:'function',function:{name,arguments:'{}'}}]})+'data: [DONE]\n\n');return;
 }
 res.write(frame({content:'检查结果。\n\n'+Array.from({length:45},(_,i)=>`- 对话正文第 ${i+1} 行：保留外层阅读位置。`).join('\n')}));held=res;
});
await new Promise<void>(done=>server.listen(0,'127.0.0.1',done));const port=(server.address() as any).port;
await writeFile(join(data,'config.toml'),`[meta]\nconfig_revision=1\n[ui]\ntheme="dark"\nfont_family="Menlo"\nfont_size=14\n[ai]\ndefault_provider="card-scroll-fixture"\npermission_mode="confirm"\n[[ai.providers]]\nid="card-scroll-fixture"\nkind="openai_compat"\nendpoint="http://127.0.0.1:${port}/v1/chat/completions"\nenabled=true\n[[ai.providers.models]]\nname="card-scroll-fixture"\ncontext_window=200000\ndefault=true\nreasoning=true\n`);
pasteboardName();  // refuses to run without a private pasteboard (the copy check must not reach the system clipboard)
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const log=await open(join(out,'app.log'),'w');
const app=spawn(join(prefix,'bin/zerowork'),[],{env:{...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1',ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',OPENAI_API_KEY:'',ANTHROPIC_API_KEY:''},stdio:['ignore',log.fd,log.fd]});
const ended=new Promise<any>(done=>app.once('exit',(code,signal)=>done({code,signal})));
// zenit ScrollArea 子节点顺序：content / track_v / track_h / bar_v / bar_h（vendor/zenit/src/ui/components/scroll_area/mod.zig），纵向 thumb 是 children[3]。
const shown=(n:any)=>n&&n.hidden!==true&&n.visible!==false&&(n.effective_opacity??1)>0&&n.rect?.w>0&&n.rect?.h>0;
const visible=(id:string)=>h.waitFor(async()=>(await h.query(id)).find(shown)??null,15000);
const click=async(id:string)=>{await visible(id);assert((await h.clickTestId(id)).ok,id)};
const allText=(n:any):string=>Array.isArray(n)?n.map(allText).join(' '):n?[n.text??'',...(n.children??[]).map(allText)].join(' '):'';
const rect=async(id:string)=>(await visible(id)).rect;
const flat=(n:any):any[]=>Array.isArray(n)?n.flatMap(flat):n?[n,...(n.children??[]).flatMap(flat)]:[];
// 工具卡几何（src/features/ai/cards/view/ai_tool_results_styles.zig，Kaf7E A6 / 143c4c7b）：头部 row_height 24、正文 fit max 150、页脚 footer 28；
// 卡片根（S.card，无 gap）= 头部 + 正文展开区 + 页脚展开区，展开区由 layout_motion.Disclosure 收成 0 高。卡片 test_id 是 ai.tool.result.<turn>.<hash>（src/ai/tool_results.zig）。
const headerH=24,bodyMax=150,footerH=28;
const resultCard=()=>h.waitFor(async()=>flat(await h.query('ai.panel')).find((n:any)=>/^ai\.tool\.result\.\d+\.[0-9a-f]+$/.test(n.test_id??'')&&shown(n))??null,15000);
const cardHeight=(want:number)=>h.waitFor(async()=>{const c=await resultCard();return Math.abs(c.rect.h-want)<.5?c:null},5000);
// 思考卡展开完成：展开区动画结束时卡片底边包住整个 ai.step.details（展开区 overflow_hidden，动画中卡片底边在正文底边之上）。
const thinkingOpened=()=>h.waitFor(async()=>{const t=(await h.query('ai.thinking')).find(shown),d=(await h.query('ai.step.details')).find(shown);return t&&d&&t.rect.y+t.rect.h>=d.rect.y+d.rect.h-.5?d:null},5000);
const snapshot=async()=>({outer:await rect('ai.conversation.viewport'),card:await rect('ai.tool.result.details'),content:await rect('ai.tool.result.stdout'),user:await rect('ai.message.user.bubble')});
const cap=async(name:string)=>{assert((await h.screenshot(join(out,`${name}.png`))).ok);await writeFile(join(out,`${name}.json`),JSON.stringify(await h.query('ai.panel'),null,2))};
// 浮动面板（#52）左缘有 6px 的 ai.float.resize.w 缩放热区盖住视口 x..x+5；取左侧 14px 留白内、热区之外的 x+10。
const scrollOuter=async(dy:number)=>{const r=await rect('ai.conversation.viewport');await h.scrollAt(r.x+10,r.y+20,0,dy)};
const sendBody=async(dy:number,mods:any={})=>{const r=await rect('ai.tool.result.details');await h.scrollAt(r.x+40,r.y+r.h/2,0,dy,mods)};
// 期望移动的断言按时限等条件成立；期望“不动”的断言（推边界、外层不随动）要给滚轮一个处理窗口再看，窗口固定为 holdMs（不是等待条件，是观察期）。
const holdMs=150;
const moved=(cond:(s:any)=>boolean)=>h.waitFor(async()=>{const s=await snapshot();return cond(s)?s:null},3000);
const settledSnapshot=async()=>{await h.sleep(holdMs);return snapshot()};
const sameOuter=async(before:any)=>{const now=await snapshot();assert(Math.abs(now.card.y-before.card.y)<.1,'Card moved with outer conversation');assert(Math.abs(now.user.y-before.user.y)<.1,'User bubble moved with outer conversation');return now};
const report:any={status:'running',binary:join(prefix,'bin/zerowork'),isolated,checks:[],limits:['Owned local SSE fixture; no external model or user conversation was used.','Wheel and phased trackpad packets go through the native window harness; physical touchpad hardware was not driven.']};
try{
 await h.waitForServerReady(60000);assert.equal(Number(JSON.parse(await readFile(join(rpc,'owner.json'),'utf8')).pid),app.pid);
 await h.resizeWindow(1200,900);await click('workspace.empty.local');await visible('terminal.surface');await click(await aiToggleId());await click('ai.prompt');await h.type_('检查展开卡片的滚动。');await click('ai.send');await visible('ai.step_group.header');await visible('ai.response');assert(held);
 // 步骤聚合（ai_step_group_view.zig）：思考与工具结果收在 ai.step_group 里，默认折叠；先展开分组再测卡片。
 // 回复结束时对话跟随到最新一条（tail-follow）；读者先把对话滚回顶部再展开分组（主动上翻即停止跟随）。
 {const v=await visible('ai.conversation.viewport');await h.scrollAt(v.rect.x+v.rect.w/2,v.rect.y+v.rect.h/2,0,100000);await h.waitFor(async()=>(await h.query('ai.message.user.bubble')).some((n:any)=>shown(n)&&n.rect.y>=v.rect.y)||null,3000);}
 if(!(await h.query('ai.thinking')).some(shown))await click('ai.step_group.header');await visible('ai.tool.result.header');
 await scrollOuter(100000);let thinking=await rect('ai.thinking');assert((await h.clickAt(thinking.x+90,thinking.y+16)).ok);
 const shortNode=await thinkingOpened(),short=shortNode.rect,shortBefore=await rect('ai.thinking');assert(short.h<150);assert.equal(shortNode.children[3].rect.w,0,'Short card must not show a fake vertical scrollbar');await h.scrollAt(short.x+40,short.y+short.h/2,0,-35);await h.waitFor(async()=>(await rect('ai.thinking')).y<shortBefore.y-20||null,5000);report.checks.push('Short expanded thinking passes wheel input to the conversation');
 await scrollOuter(100000);await click('ai.tool.result.header');await cardHeight(headerH+bodyMax+footerH);let before=await snapshot();assert.equal(before.card.h,bodyMax);await cap('01-expanded-long-card');const initialThumb=(await visible('ai.tool.result.details')).children[3];assert(initialThumb.rect.w>0&&initialThumb.rect.h>0,'Overflow thumb must be visible before any scrolling');await h.mouseMove(2,850);await h.sleep(3000);const idleThumb=(await visible('ai.tool.result.details')).children[3];assert(idleThumb.rect.w>0&&idleThumb.rect.h>0,'Overflow thumb must remain visible while idle');assert((idleThumb.opacity??1)>0);report.idle_thumb={node_id:idleThumb.id,rect:idleThumb.rect,opacity:idleThumb.opacity??1};await cap('01-idle-long-card');report.checks.push('Initial expanded long-card thumb stays visible after three idle seconds; short card has no fake thumb');
 await sendBody(-45);let now=await moved(s=>s.content.y<before.content.y-20);now=await sameOuter(before);report.checks.push('Wheel over a long expanded host-result body moves the inner content only');
 const heldOffset=now.card.y-now.content.y;
 held.write(frame({reasoning_content:'\n补充思考触发对话重建。'}));// 正文之后的新思考进入新的步骤分组（ai_step_group_view.zig，折叠态在分组摘要里投影），不再追加到首个思考卡的 ai.step.detail。
 await h.waitFor(async()=>allText(await h.query('ai.conversation')).includes('补充思考')||null,5000);now=await settledSnapshot();assert(Math.abs(now.card.y-now.content.y-heldOffset)<.5,'Result body lost its reading offset during streamed conversation rebuild');await cap('02-remounted-reader-position');report.checks.push('Streamed thinking remount preserves tool-result and outer reading offsets');
 before=now;await sendBody(-100000);now=await moved(s=>s.content.y<before.content.y-20);await settledSnapshot();now=await sameOuter(before);const bottom=now.content.y;await sendBody(-50);await settledSnapshot();now=await sameOuter(before);assert(Math.abs(now.content.y-bottom)<.1);report.checks.push('Wheel crossing and pushing the bottom boundary stays contained');
 await sendBody(100000);now=await moved(s=>s.content.y>bottom+20);await settledSnapshot();now=await sameOuter(before);const top=now.content.y;await sendBody(50);await settledSnapshot();now=await sameOuter(before);assert(Math.abs(now.content.y-top)<.1);report.checks.push('Wheel crossing and pushing the top boundary stays contained');
 await sendBody(-1);const detailNode=await visible('ai.tool.result.details'),bar=detailNode.children[3].rect;assert(bar.w>0&&bar.h>0,'Native vertical scrollbar should be available');const dragBefore=await snapshot();await h.mouseDown(bar.x+bar.w/2,bar.y+bar.h/2);await h.mouseMove(bar.x+bar.w/2,bar.y+bar.h/2+20);await h.mouseUp(bar.x+bar.w/2,bar.y+bar.h/2+20);now=await moved(s=>s.content.y<dragBefore.content.y-20);now=await sameOuter(dragBefore);report.checks.push('Native scrollbar drag moves the inner card and leaves the conversation fixed');
 await click('ai.tool.result.copy_stdout');/* 复制写的是本条目的私有 pasteboard（ZENIT_E2E_PASTEBOARD，应用继承 process.env），不碰系统剪贴板 */const copied=await h.waitFor(async()=>{const t=await readPasteboardText();return t&&t.includes('binding_ref')&&t.includes('conversation_id')?t:null},5000);assert(copied);report.checks.push('Result copy preserves the full original structured result');before=await snapshot();

 await sendBody(0,{phase:'may_begin'});await sendBody(-40,{phase:'began'});await sendBody(-1000,{phase:'changed'});await sendBody(-30,{phase:'changed'});await sendBody(0,{phase:'ended'});await sendBody(-30,{momentum:'began'});await sendBody(-15,{momentum:'changed'});await sendBody(0,{momentum:'ended'});await h.sleep(700);/* 观察期：惯性包处理完后外层仍不动 */await sameOuter(before);await cap('03-trackpad-bottom');report.checks.push('Phased trackpad and momentum stay in the long body at the boundary');
 await scrollOuter(-45);now=await moved(s=>s.card.y<before.card.y-20);report.checks.push('Pointer outside the card still scrolls the conversation');await cap('04-outer-scroll');
 // 折叠 / 展开：头部保持 24 且不移位，折叠后卡片只剩头部（正文与页脚收成 0 高），再展开恢复 150 正文与页脚。
 await scrollOuter(100000);const headerBefore=await rect('ai.tool.result.header');assert.equal(headerBefore.h,headerH);await click('ai.tool.result.header');await cardHeight(headerH);const collapsed=await rect('ai.tool.result.header');assert.equal(collapsed.h,headerH);assert.equal(collapsed.x,headerBefore.x);assert.equal(collapsed.w,headerBefore.w);
 await click('ai.tool.result.header');await cardHeight(headerH+bodyMax+footerH);assert.equal((await rect('ai.tool.result.details')).h,bodyMax);assert.equal((await rect('ai.tool.result.header')).h,headerH);report.checks.push('Collapse leaves only the 24px header; expand restores the 150px bounded body and the 28px footer');
 held.end('data: [DONE]\n\n');held=null;await visible('ai.turn.complete');await cap('05-completed');report.status='passed';
}catch(error){report.status='failed';report.error=String(error);process.exitCode=1;await cap('failure').catch(()=>{})}
finally{
 if(held)held.end();server.closeAllConnections();await new Promise<void>(done=>server.close(()=>done()));
 if(app.exitCode===null&&app.signalCode===null){try{await h.request('POST','/quit');await h.waitFor(async()=>app.exitCode!==null||app.signalCode!==null||null,10000)}catch(error){report.shutdown_error=String(error);app.kill('SIGTERM')}}
 report.shutdown=await ended;await log.close();report.requests=requests;await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));
}
console.log(JSON.stringify(report,null,2));
