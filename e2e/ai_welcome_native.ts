/** Isolated native welcome/transcript transition and recent-session regression. */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {spawn} from 'node:child_process';
import {writeFile,mkdir,open,mkdtemp,realpath,rm} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {aiToggleId} from './ai_entry.ts';
import {readRequestJson} from './provider_fixture.ts';
import {isTitleRequest,skipTitle} from './ai_title_fixture.ts';
// 运行器给出 test-mode 前缀（ZW_AI_TEST_PREFIX={prefix}）与主题变体（argv[3]）；不再读 scripts/build_ui_check.sh 的 dist/ui-check-build.json。
const prefix=resolve(process.env.ZW_AI_TEST_PREFIX??'zig-out');
const {waitForServerReady,waitFor,query,clickTestId,key,type_,resizeWindow,screenshot,sleep,mouseMove,inputState,scrollAt}=await import(join(prefix,'share/zenit/harness/client.ts'));
const out=resolve(process.argv[2]??'/private/tmp/zw-ai-welcome'),theme=process.argv[3]??'dark';assert(['light','dark','sauber'].includes(theme),'theme '+theme);await mkdir(out,{recursive:true});
const iso=await realpath(await mkdtemp(join(tmpdir(),'zw-welcome-'))),data=join(iso,'data'),rpc=join(iso,'rpc');await mkdir(data);await mkdir(rpc);
const requests:any[]=[];
const server=createServer(async(req,res)=>{
 if(req.method==='GET'){res.writeHead(200,{'Content-Type':'application/json'});res.end(JSON.stringify({data:[{id:'welcome-model',object:'model'}]}));return;}
 const request=await readRequestJson(req);if(isTitleRequest(request))return skipTitle(res);requests.push(request);
 const text=request.messages.filter((m:any)=>m.role==='user').at(-1)?.content??'';
 res.writeHead(200,{'Content-Type':'text/event-stream'});res.write('data: '+JSON.stringify({choices:[{index:0,delta:{content:'正在分析 '+text+'\n\n'}}]})+'\n\n');
 setTimeout(()=>res.end('data: '+JSON.stringify({choices:[{index:0,delta:{content:('这是保留在 transcript 中的分析结果。\n\n').repeat(String(text).includes('LONG')?35:2)}}]})+'\n\ndata: [DONE]\n\n'),700);
});
await new Promise<void>(r=>server.listen(0,'127.0.0.1',r));
// 模型窗口 200000：工具定义 + 系统提示的固定开销已超过 8192（旧夹具值会让首问直接落到“模型窗口不足”恢复卡）。
await writeFile(join(data,'config.toml'),`[meta]\nconfig_revision=1\n[ui]\ntheme="${theme}"\n[ai]\ndefault_provider="welcome"\n[[ai.providers]]\nid="welcome"\nkind="openai_compat"\nendpoint="http://127.0.0.1:${(server.address() as any).port}/v1/chat/completions"\napi_key="local-only"\nenabled=true\n[[ai.providers.models]]\nname="welcome-model"\ncontext_window=200000\ndefault=true\n`);
// 860×480 会触发一次性的“窗口较窄，可以收起侧栏”提示（src/features/shell/host/sidebar_memory.zig，底部居中 8 s，盖住面板输入区）；它有自己的用例（sidebar_layout_r3_native），这里预置为已提示过。
await writeFile(join(data,'ui-state.json'),JSON.stringify({narrow_sidebar_hint_shown:true}));
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;const log=await open(join(out,'native.log'),'w');
const app=spawn(join(prefix,'bin/zerowork'),[],{env:{...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1',ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',OPENAI_API_KEY:'',ANTHROPIC_API_KEY:''},stdio:['ignore',log.fd,log.fd]});
const ended=new Promise<void>(r=>app.once('close',()=>r()));
const shown=(n:any)=>n&&n.hidden!==true&&n.visible!==false&&(n.effective_opacity??1)>0&&n.rect?.w>0&&n.rect?.h>0;
const flat=(n:any):any[]=>Array.isArray(n)?n.flatMap(flat):n?[n,...(n.children??[]).flatMap(flat)]:[];const text=(n:any)=>flat(n).map(n=>n.text??'').join('\n');
const visible=(id:string)=>waitFor(async()=>(await query(id)).find(shown)??null,12000);const click=async(id:string)=>{await visible(id);assert((await clickTestId(id)).ok,id)};
const absent=(id:string)=>waitFor(async()=>!(await query(id)).some(shown)||null,10000).catch(()=>{throw new Error(id+' should be absent')});
const capture=async(name:string)=>{await mouseMove(2,2);await sleep(120);assert((await screenshot(join(out,name+'.png'))).ok);await writeFile(join(out,name+'.json'),JSON.stringify(await query('ai.panel'),null,2))};
const idle=()=>waitFor(async()=>!(await query('ai.stop')).some(shown)||null,10000);
const send=async(prompt:string)=>{await click('ai.prompt');await type_(prompt);await click('ai.send');await waitFor(async()=>text((await query('ai.panel')).find(shown)).includes('正在分析 '+prompt)||null,10000);await absent('ai.empty.configured');await idle()};
const recentRows=async()=>((await query('ai.empty.recent')).find(shown)?.children??[]).filter((n:any)=>/^ai\.session\.row\.\d+$/.test(n.test_id??'')&&shown(n));
// 行标题是会话标题（ai_session_row.zig ai.session.title）；标题生成请求被夹具跳过（ai_title_fixture.ts），标题即该会话的第一问。
const rowTitle=(row:any)=>flat(row).find((n:any)=>n.test_id==='ai.session.title')?.text??'';
const recentAction=(row:any,action:string)=>'ai.session.'+action+'.'+row.test_id.split('.').at(-1);
// M10：一个页签绑定一个对话，“新建对话”先确认结束当前对话（ai_sessions_view.zig ai.session.close.confirmation）。
const newConversation=async()=>{await click('ai.session.new');await click('ai.session.close.accept');await absent('ai.session.close.confirmation')};
// 欢迎页（Pencil A2 ZF1PS / ai-redesign-c，src/features/ai/sessions/view/ai_empty_view.zig + ai_empty_styles.zig）：sparkles 20（welcomeIcon）、
// 标题 16/600「有什么可以帮你？」、两个各占半行的原生 secondary block 按钮（row gap 8）、最多两条最近会话（ai_session_row）。各宽度一致，没有旧的 88 / 56 大图标。
const logoSize=20,starterGap=8;
async function checkWelcome(label:string){
 const panel=await visible('ai.panel'),header=await visible('ai.header'),logo=await visible('ai.empty.logo'),title=await visible('ai.empty.title');
 assert.equal(logo.rect.w,logoSize,label+' logo width');assert.equal(logo.rect.h,logoSize,label+' logo height');
 assert.equal(text(title),'有什么可以帮你？');assert(title.rect.y>=logo.rect.y+logo.rect.h-.5,label+' title under the logo');
 assert(logo.rect.y>=header.rect.y+header.rect.h,label+' welcome entirely below the panel header');
 const a=await visible('ai.empty.summarize'),b=await visible('ai.empty.logs');
 assert(Math.abs(a.rect.w-b.rect.w)<.5,label+' starters share the row equally');assert(Math.abs(a.rect.y-b.rect.y)<.5&&Math.abs(a.rect.h-b.rect.h)<.5,label+' starters on one line');
 assert(Math.abs(b.rect.x-(a.rect.x+a.rect.w)-starterGap)<.5,label+' starters 8 apart');
 for(const n of [logo,title,a,b])assert(n.rect.x>=panel.rect.x&&n.rect.x+n.rect.w<=panel.rect.x+panel.rect.w+.5,label+' welcome inside the panel');
 const prompt=await visible('ai.prompt'),sendButton=await visible('ai.send');
 for(const n of [prompt,sendButton])assert(n.rect.y+n.rect.h<=panel.rect.y+panel.rect.h+.5&&n.rect.x+n.rect.w<=panel.rect.x+panel.rect.w+.5,label+' composer reachable inside the panel');
}
const report:any={checks:[],status:'running',theme};
try{
 await waitForServerReady(60000);await resizeWindow(1440,900);await click('workspace.empty.local');await visible('terminal.surface');await click(await aiToggleId());await mouseMove(2,2);
 await visible('ai.empty.configured');await checkWelcome('1440×900');assert.equal((await query('ai.empty.recent')).filter(shown).length,0);await capture('01-empty');report.checks.push('Empty state: 20px sparkles, 16/600 title and two equal starters; no fabricated recent conversations');
 await click('ai.empty.summarize');await waitFor(async()=>String((await inputState('ai.prompt')).buffer).includes('概括')||null,5000);await key('a',{cmd:true});await type_('FIRST');await click('ai.send');
 await waitFor(async()=>text((await query('ai.panel')).find(shown)).includes('正在分析 FIRST')||null,10000);await absent('ai.empty.logo');await capture('02-stream');await idle();
 await send('SECOND_LONG');await capture('03-transcript');await absent('ai.empty.title');report.checks.push('Starter fills the prompt; first send removes the entire welcome group; second streamed turn keeps transcript and composer');
 await newConversation();await visible('ai.empty.configured');let links=await recentRows();assert.equal(links.length,1);assert.equal(rowTitle(links[0]),'FIRST');
 await send('OTHER_SESSION');await newConversation();await visible('ai.empty.configured');links=await recentRows();assert.equal(links.length,2);assert.deepEqual(links.map(rowTitle),['OTHER_SESSION','FIRST']);await checkWelcome('with recent');await capture('04-two-recent');report.checks.push('New conversation restores welcome; recent rows are real conversations, newest first, capped at two');
 await click(recentAction(links[0],'jump'));await visible('ai.history');await click('ai.history.close');await absent('ai.history');
 await click(recentAction(links[0],'restore'));await waitFor(async()=>text((await query('ai.panel')).find(shown)).includes('OTHER_SESSION')||null,10000);await absent('ai.empty.logo');report.checks.push('Recent View opens read-only history; Restore switches to the original transcript');
 await newConversation();links=await recentRows();assert.equal(links.length,2);assert.deepEqual(links.map(rowTitle),['OTHER_SESSION','FIRST']);await click(recentAction(links[1],'restore'));await waitFor(async()=>text((await query('ai.panel')).find(shown)).includes('正在分析 SECOND_LONG')||null,10000);await send('RESUMED_OLDER');await newConversation();links=await recentRows();assert.equal(links.length,2);assert.deepEqual(links.map(rowTitle),['FIRST','OTHER_SESSION'],'the continued older conversation moves to the top');report.checks.push('Continuing an older conversation moves it above newer-created conversations');
 await resizeWindow(860,480);await visible('ai.empty.configured');await waitFor(async()=>{const p=(await query('ai.panel')).find(shown);return p&&p.rect.x+p.rect.w<=860.5&&p.rect.y+p.rect.h<=480.5||null},5000);
 // 窄窗里欢迎页高于对话视口时可滚动：对话视口在缩窗后贴底（顶部的图标被视口裁掉一部分，见回报），滚回顶部后整组欢迎内容都在标题栏下方。
 {const v=await visible('ai.conversation.viewport');await scrollAt(v.rect.x+v.rect.w/2,v.rect.y+v.rect.h/2,0,100000);await waitFor(async()=>{const l=(await query('ai.empty.logo')).find(shown),vp=(await query('ai.conversation.viewport')).find(shown);return l&&vp&&l.rect.y>=vp.rect.y?l:null},5000);}
 await checkWelcome('860×480');await capture('05-compact');report.checks.push('Compact window keeps the same welcome geometry below the header and the composer reachable');
 report.status='passed';
}catch(e){report.status='failed';report.error=String(e);await capture('failure').catch(()=>{});}
finally{
 await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));
 if(app.exitCode===null&&app.signalCode===null)app.kill('SIGTERM');await ended;server.closeAllConnections();server.close();await log.close();await rm(iso,{recursive:true,force:true});
}
console.log(JSON.stringify(report));if(report.status!=='passed')process.exitCode=1;
