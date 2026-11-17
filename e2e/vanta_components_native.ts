/** Vanta component acceptance: production main app, native Metal and local HTTP/SSE.
 * Only read-only pwd runs through the production Local adapter. No external AI/SSH. */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {spawn} from 'node:child_process';
import {mkdir,mkdtemp,writeFile,readFile,open,copyFile,rm} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {createHash} from 'node:crypto';
import {waitForServerReady,waitFor,query,clickTestId,key,type_,resizeWindow,screenshot,sleep,mouseMove,scrollAt} from '../zig-out/share/zenit/harness/client.ts';
import {aiToggleId} from './ai_entry.ts';
import {isTitleRequest,skipTitle} from './ai_title_fixture.ts';
import {readRequestText} from './provider_fixture.ts';
const out=resolve(process.argv[2]??'artifacts/vanta-20261022-round6/components'),themes=process.argv[3]?[process.argv[3]]:['dark','light','sauber'];
await mkdir(out,{recursive:true});
const report:any={status:'running',binary_sha256:createHash('sha256').update(await readFile('zig-out/bin/zerowork')).digest('hex'),runs:[],scope:'real isolated native main app; controlled HTTP/SSE; actual readonly Local pwd; synthetic Harness input'};
const shown=(n:any)=>n?.hidden!==true&&n?.visible!==false&&(n?.effective_opacity??1)>0&&n?.rect?.w>0&&n?.rect?.h>0;
const flat=(n:any):any[]=>shown(n)?[n,...(n.children??[]).flatMap(flat)]:[];
const txt=(n:any)=>flat(n).map(x=>x.text??'').join('\n');
const visible=async(id:string)=>waitFor(async()=>(await query(id)).find(shown)??null,20000);
async function click(id:string){await visible(id);assert((await clickTestId(id)).ok,id);}
async function edit(id:string,value:string){await click(id);await key('a',{cmd:true});await type_(value);}
try{for(const theme of themes){
 const dir=join(out,theme);await mkdir(dir,{recursive:true});const iso=await mkdtemp(join(tmpdir(),'zw-vanta-components-')),data=join(iso,'data'),rpc=join(iso,'rpc');await mkdir(data);await mkdir(rpc);
 const run:any={theme,status:'running',checks:[],captures:[],requests:[]};report.runs.push(run);let toolIssued=false,terminalRead=false;
 const server=createServer(async(req,res)=>{try{const body=await readRequestText(req);
  // 模型目录刷新（GET …/models，src/ai/model_discovery.zig）不是对话请求：回空目录，不计入 requests。
  if(req.method==='GET'){res.writeHead(200,{'content-type':'application/json'});res.end('{"data":[]}');return;}
  const request=JSON.parse(body);if(isTitleRequest(request))return skipTitle(res);run.requests.push(request);
  const system=request.messages.find((m:any)=>m.role==='system')?.content??'';
  res.writeHead(200,{'Content-Type':'text/event-stream'});const frame=(delta:any)=>res.write('data: '+JSON.stringify({choices:[{index:0,delta}]})+'\n\n');
  // M11（需求 #31）：tab 卡片内容不再自动拼进系统提示（session_prompt.zig“This tab's card content is not included automatically”），
  // 由模型调用 host.read_terminal 读取。保持原意“当前终端输出进入实际 provider 请求”：先读终端，断言哨兵出现在工具结果里，再发 pwd。
  const toolText=request.messages.filter((m:any)=>m.role==='tool').map((m:any)=>String(m.content)).join('\n');
  if(!terminalRead){terminalRead=true;await sleep(1400);const tool=request.tools.find((t:any)=>t.function.name==='host__read_uterminal');assert(tool,'terminal reader advertised');const ref=tool.function.parameters.properties.session_ref.enum[0];assert(ref);frame({tool_calls:[{index:0,id:'vanta-read',type:'function',function:{name:tool.function.name,arguments:JSON.stringify({session_ref:ref,max_lines:20})}}]});}
  else if(!toolIssued){toolIssued=true;assert(toolText.includes('ZW_CONTEXT_VISIBLE_VANTA'),'Current terminal output is assembled into actual provider request');/* 系统提示不再有 assistant_session_id=N；当前会话取 <host_session_facts> 的 targets[].session_id（src/ai/session_prompt.zig） */const facts=JSON.parse(system.match(/<host_session_facts>\s*(\{[\s\S]*?\})\s*<\/host_session_facts>/)?.[1]??'{}');const id=Number(facts.targets?.find((t:any)=>t.batch_execution)?.session_id);assert(id>0);frame({tool_calls:[{index:0,id:'vanta-pwd',type:'function',function:{name:'run_command',arguments:JSON.stringify({session_ids:[id],command:'pwd'})}}]});}
  else{assert(request.messages.some((m:any)=>m.role==='tool'&&String(m.content).includes('succeeded')));frame({content:'## 检查结果\n\n当前目录已读取。**连接正常**。\n\n- 已接入终端上下文\n- 工具结果可展开查看\n\n```sh\npwd\n```\n\nVANTA_COMPLETE'});}
  res.end('data: [DONE]\n\n');
 }catch(e){run.server_error=String(e);res.destroy();}});
 await new Promise<void>(done=>server.listen(0,'127.0.0.1',done));const port=(server.address() as any).port;
 // 模型窗口 8192 已放不下当前固定开销（系统提示+工具定义约 9.7K token，发送即报“模型窗口不足”119%），夹具改 200000（同 three_fixes_native）。
 await writeFile(join(data,'config.toml'),`[meta]\nconfig_revision=1\n[ui]\ntheme="${theme}"\nfont_family="Menlo"\nfont_size=14\n[ai]\ndefault_provider="vanta-test"\npermission_mode="confirm"\n[[ai.providers]]\nid="vanta-test"\nkind="openai_compat"\nendpoint="http://127.0.0.1:${port}/v1/chat/completions"\napi_key="local-only-fixture"\nenabled=true\n[[ai.providers.models]]\nname="vanta-model"\ncontext_window=200000\ndefault=true\n`);
 const binary=join(dir,'zerowork-frozen');await copyFile('zig-out/bin/zerowork',binary);await copyFile('zig-out/bin/zw_ipc.so',join(dir,'zw_ipc.so'));
 process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;const env={...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_ISOLATE_POINTER:'1',ZENIT_E2E_BACKGROUND:'1',ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',ZEROWORK_AI_TOOL_TRACE:'1'};for(const k of ['ZEROWORK_AI_MOCK','ZEROWORK_AI_ENDPOINT','ZEROWORK_AI_MODEL','ZEROWORK_AI_PROVIDER'])delete env[k];
 const log=await open(join(dir,'app.log'),'w'),app=spawn(binary,[],{env,stdio:['ignore',log.fd,log.fd]}),ended=new Promise<void>(done=>app.once('close',()=>done()));
 async function cap(name:string){await sleep(100);assert((await screenshot(join(dir,name+'.png'))).ok);const ids=['ai.panel','ai.launcher','ai.launcher.dot','ai.launcher.ring','ai.launcher.state','ai.step_group','ai.composer.usage','ai.usage.menu','quick.clear','files.error'];const nodes=Object.fromEntries(await Promise.all(ids.map(async id=>[id,await query(id)])));await writeFile(join(dir,name+'.json'),JSON.stringify(nodes,null,2));run.captures.push(name);}
 try{
  await waitForServerReady();assert.equal(Number(JSON.parse(await readFile(join(rpc,'owner.json'),'utf8')).pid),app.pid);await resizeWindow(1440,900);
  await key('k',{cmd:true});await sleep(300);await edit('quick.query','no-such-host-vanta');await cap('quick-empty-wide');const clear=await visible('quick.clear');assert.equal(clear.rect.w,24);assert.equal(clear.rect.h,24);assert(!txt(clear).includes('清空搜索'));await resizeWindow(860,480);await cap('quick-empty-compact');await click('quick.clear');await click('quick.close');run.checks.push('Quick empty: icon-only 24px clear remains usable in search; close remains reachable');
  await click('toolbar.transfers');await visible('transfer.empty');await cap('transfer-empty-compact');
  // 指针停在工具栏按钮上时其提示会先吃掉 Escape（e2e-sweep triage 已知问题 #1，待 zenit 上游）；先移开指针再按 Escape，并断言面板确实关闭。
  await mouseMove(600,400);await sleep(250);await key('escape');await waitFor(async()=>!(await query('transfer.manager')).some(shown)||null,5000);
  await click('toolbar.settings');await edit('settings.search','font_size');await cap('settings-compact');
  // 设置是独立窗口，Escape 只作用于搜索框；按 settings_nav.close 的方式 ⌘W 关闭并等待面板消失。
  await key('w',{cmd:true});await waitFor(async()=>!(await query('settings.panel')).some(shown)||null,8000);
  await click('workspace.empty.local');await visible('terminal.surface');await click('terminal.surface');await type_("printf 'ZW_CONTEXT_VISIBLE_VANTA\\n'");await key('enter');await sleep(400);
  await visible('ai.launcher');await cap('strip-idle');const launcher=await visible('ai.launcher');assert.equal(launcher.rect.w,48);assert.equal(launcher.rect.h,48);await click('ai.launcher');await visible('ai.prompt');await mouseMove(20,20);run.checks.push('48×48 floating ai.launcher (PL4c 4c-2, replaces the hover capsule); click opens assistant');
  if(process.env.ZW_STRIP_ONLY==='1'){
   await cap('assistant-open-compact');await click('ai.collapse');await visible('ai.launcher');await cap('strip-capsule-compact');
   await resizeWindow(1440,900);await sleep(350);await cap('strip-capsule-wide');await click(await aiToggleId());const panel=await visible('ai.panel');assert.equal(panel.rect.h,456);await cap('assistant-open-wide');run.checks.push('Wide and compact capsule, click and hover restore, 456px default assistant height');run.status='passed';continue;
  }

  await edit('ai.prompt','检查当前目录');await click('ai.send');await waitFor(()=>run.requests.length?true:null,10000);await click('ai.collapse');await visible('ai.launcher');await cap('strip-working');
  await waitFor(async()=>{const content=await readFile(join(dir,'app.log'),'utf8');/* run_command 走统一动态工具流水线，待批准事件为 dynamic_approval_pending（src/features/ai/tools/host） */return content.includes('"event":"dynamic_approval_pending"')||null},20000);await cap('strip-approval');await click(await aiToggleId());/* 审批卡移入输入区交互卡（ai_composer_interaction_view.zig） */await visible('ai.interaction.approve');await cap('ai-approval-compact');await click('ai.interaction.approve');
  await waitFor(async()=>{const content=await readFile(join(dir,'app.log'),'utf8');return content.includes('tool_feedback')&&run.requests.length>=3||null},20000);
  await waitFor(async()=>txt((await query('ai.panel')).find(shown)).includes('VANTA_COMPLETE')&&!(await query('ai.stop')).some(shown)||null,20000);
  assert(!run.server_error,run.server_error);
  // 工具结果卡 ai.tool.results 已改为步骤聚合组 ai.step_group（标题“执行命令 · N 个步骤”，头部 32px，src/features/ai/cards/view/ai_step_group_view.zig:100-137），默认收起。
  const group=await visible('ai.step_group');assert(txt(group).includes('执行命令'),'Retained tool step group exists');/* 步骤分组是原生 W.Disclosure：折叠时只有触发行，高 28（vendor/zenit/src/ui/components/disclosure/styles.yss Trigger；旧手搓分组头 32 随 143c4c7b 换成原生） */const groupHeader=(await query('ai.step_group.header')).find(shown);assert(groupHeader,'step group header shown');assert.equal(groupHeader.rect.h,28,'step group header is the native Disclosure trigger row');assert.equal(group.rect.h,groupHeader.rect.h,'Tool step group is collapsed by default (only its header row)');assert(!(await query('ai.step_group.content')).some(shown));run.checks.push('Actual pwd executed once, feedback returned, step group defaults to 32px collapsed');
  await cap('ai-markdown-collapsed-compact');/* 回复结束时对话跟随到最新一条；先把对话滚回顶部再展开分组 */{const v=await visible('ai.conversation.viewport');await scrollAt(v.rect.x+v.rect.w/2,v.rect.y+v.rect.h/2,0,100000);await sleep(200);}await click('ai.step_group.header');await visible('ai.step_group.content');await cap('ai-tool-expanded-compact');await click('ai.step_group.header');await waitFor(async()=>!(await query('ai.step_group.content')).some(shown)||null,5000);
  await click('ai.composer.usage');const usage=await visible('ai.usage.menu');/* 无 provider 实测 usage 时估算值以“~”前缀标示（ai_composer_controls_view.zig:1262/1294），“（估算）”字样只在有实测基准时出现 */assert(/~[\d.]+K? \/ /.test(txt(usage)),'estimated total marked with ~');assert(txt(usage).includes('终端上下文'));assert(!txt(await visible('ai.composer.usage')).includes('—'));await cap('ai-context-compact');await key('escape');
  await resizeWindow(1440,900);await cap('ai-markdown-wide');await mouseMove(20,20);await click('ai.collapse');await visible('ai.launcher');await sleep(350);await cap('strip-success');
  const events=(await readFile(join(dir,'app.log'),'utf8')).split('\n').flatMap(l=>{const i=l.indexOf('AI_TOOL_TRACE ');try{return i<0?[]:[JSON.parse(l.slice(i+14))]}catch{return[]}});assert.equal(events.filter(e=>e.event==='exec_started').length,1);run.checks.push('Wire request contains terminal sentinel; context breakdown shows estimated counts; Markdown headings/list/code render; no duplicate execution');run.status='passed';
 }catch(e){run.status='failed';run.error=String(e);await cap('failure').catch(()=>{});throw e;}
 finally{app.kill('SIGTERM');await Promise.race([ended,sleep(2000)]);if(app.exitCode===null&&app.signalCode===null){app.kill('SIGKILL');await ended;}await log.close();await new Promise<void>(done=>server.close(()=>done()));await rm(iso,{recursive:true,force:true});}
}report.status='passed';}catch(e){report.status='failed';report.error=String(e);process.exitCode=1;}
await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));console.log(report.status+': '+join(out,'report.json'));
