/**
 * F-set-ai 验收对照图（人工验收反馈 10 后半：AI 辅助改两级，`GV8pb` / `e2ys05`）。一次性采集脚本，基于 `settings_nav.ts`
 * 的隔离启动与导航；不发任何网络请求（提供方地址都是本机回环，不点“获取模型清单 / 测试模型 / 测试连接”）。
 * 每个主题采集：
 *   (a) 未配置：服务提供方页的空态；
 *   (b) 提供方列表（三个提供方：默认、已停用、Ollama）；
 *   (c) 提供方详情（连接 + 模型列表）；
 *   (d) 模型编辑器（原生 Modal）；
 *   (e) 删除确认（原生 Modal）；
 *   (f) 行为与权限；
 *   (g) 技能与 MCP；
 *   (h) 校验错误（API 地址无效：行内提示 + Save Bar“有设置需要修正”）；
 *   (i) 保存条（有效改动：Save Bar“未保存”）。
 *
 * Usage: node e2e/h_ai_capture.ts <zerowork binary (test-mode)> <out dir> [light|dark]
 */
import assert from 'node:assert/strict';
import {join,resolve} from 'node:path';
import {writeFile} from 'node:fs/promises';
import * as h from '../vendor/zenit/e2e/client.ts';
import {launchIsolated,settingsNav,shown,textOf} from './settings_nav.ts';

const [binaryArg,outArg,theme='light']=process.argv.slice(2);
if(!binaryArg||!outArg)throw new Error('usage: h_ai_capture.ts <binary> <out> [light|dark]');
const out=resolve(outArg);
const report:any={status:'running',theme,shots:[] as string[],checks:[] as string[]};
const extensions=JSON.stringify({skills:[{id:'a'.repeat(32),revision:'b'.repeat(64),name:'release-notes',description:'根据提交记录撰写发布说明',enabled:true}],servers:[{id:'local-tools',name:'本地工具',revision:1,enabled:false,transport:'stdio',program:'/usr/bin/true',args:[],cwd:'',environment:[],endpoint:'',headers:[],timeout_ms:30000,bindings:[],roots:[],oauth_client_id:'',oauth_scope:''},{id:'team-docs',name:'团队文档',revision:1,enabled:true,transport:'http',program:'',args:[],cwd:'',environment:[],endpoint:'http://127.0.0.1:9/mcp',headers:[],timeout_ms:30000,bindings:[],roots:[],oauth_client_id:'',oauth_scope:''}]});
const configured=`[ai]\ndefault_provider="团队模型网关"\nextensions=${JSON.stringify(extensions)}\n`+
 `[[ai.providers]]\nid="团队模型网关"\nkind="openai_compat"\nendpoint="http://127.0.0.1:3425/v1"\nenabled=true\n`+
 `[[ai.providers.models]]\nname="team/gpt-4.1"\ncontext_window=1000000\nvision=true\ndefault=true\n`+
 `[[ai.providers.models]]\nname="team/o3"\ncontext_window=200000\nreasoning=true\nefforts=["low","high"]\n`+
 `[[ai.providers.models]]\nname="team/embedding-small"\ncontext_window=8192\n`+
 `[[ai.providers]]\nid="本地开发服务"\nkind="ollama"\nendpoint="http://127.0.0.1:11434/api/chat"\nenabled=true\n`+
 `[[ai.providers.models]]\nname="qwen3:8b"\ncontext_window=32768\ndefault=true\n`+
 `[[ai.providers]]\nid="备用模型服务"\nkind="openai_compat"\nendpoint="http://127.0.0.1:3426/v1"\nenabled=false\n`+
 `[[ai.providers.models]]\nname="backup-model"\ncontext_window=128000\ndefault=true\n`;

let win:string|undefined;
const shot=async(name:string)=>{await h.mouseMove(2,2).catch(()=>{});await h.sleep(450);const path=join(out,`${theme}-${name}.png`);assert((await h.screenshot(path,win)).ok,name);report.shots.push(path);};
const footerText=async()=>textOf((await h.query('settings.footer.state')).find(shown)).trim();

async function session(config:string,body:(nav:ReturnType<typeof settingsNav>)=>Promise<void>,tag:string){
 const run=await launchIsolated({binary:resolve(binaryArg),out,prefix:'zw-h-ai-capture',theme,config,logName:`app-${theme}-${tag}.log`});
 try{
  const nav=settingsNav();
  await h.resizeWindow(1440,900);
  await nav.open();
  win=(await h.windows()).windows.find(w=>w.bound&&!w.closing)?.window_id;
  await body(nav);
 }finally{await run.stop();}
}

try{
 // (a) 未配置。
 await session('',async nav=>{
  await nav.toSub('ai','providers');
  await nav.node('settings.ai.providers.empty');
  await shot('a-unconfigured');
  report.checks.push('unconfigured: providers page shows the empty state with 新增服务提供方');
 },'empty');
 await session(configured,async nav=>{
  // (b) 列表。
  await nav.toSub('ai','providers');
  const row=await nav.node('settings.ai.provider.0.header');
  assert(textOf(row).includes('团队模型网关')&&textOf(row).includes('3 个模型'),'list row copy');
  assert((await h.query('settings.ai.provider.0.default')).some(shown),'default badge on the default provider');
  await nav.node('settings.ai.add_provider');
  await shot('b-provider-list');
  report.checks.push('list: one row per provider (name, protocol · model count, 默认 / 已停用, chevron) and 添加服务提供方…');
  // (c) 详情：第三级，标题是提供方名称。
  await nav.click('settings.ai.provider.0.header');
  await nav.waitTitle('团队模型网关');
  await nav.node('settings.ai.provider.0.endpoint');
  await nav.node('settings.ai.provider.0.model.2.card');
  assert(!(await h.query('settings.reset')).some(shown),'no reset defaults on a provider detail page');
  await shot('c-provider-detail');
  report.checks.push('detail: header title is the provider name, connection rows and model rows; no 恢复默认… on the detail page');
  // (d) 模型编辑器。
  await nav.click('settings.ai.provider.0.model.1.edit_model');
  await nav.node('settings.ai.model.dialog');
  await h.sleep(500);
  await shot('d-model-editor');
  await h.key('escape');
  await h.waitFor(async()=>(await h.query('settings.ai.model.dialog')).some(shown)?null:true,5000);
  report.checks.push('model editor: native Modal, Escape cancels');
  // (h) 校验错误 / (i) 保存条。
  await nav.edit('settings.ai.provider.0.endpoint','gateway-without-scheme');
  await h.key('tab');
  await nav.node('settings.ai.provider.0.endpoint.error');
  await h.waitFor(async()=>(await footerText())==='有设置需要修正'||null,5000);
  await shot('h-invalid');
  report.checks.push('invalid endpoint: inline error under the field, Save Bar 有设置需要修正');
  await nav.edit('settings.ai.provider.0.endpoint','http://127.0.0.1:3427/v1');
  await h.key('tab');
  await h.waitFor(async()=>(await footerText())==='未保存'||null,5000);
  await shot('i-save-bar');
  report.checks.push('valid edit: Save Bar 未保存');
  await nav.click('settings.revert');
  await h.waitFor(async()=>(await h.query('settings.footer')).some(shown)?null:true,5000);
  // (e) 删除确认（非默认提供方）。
  await nav.back();
  await nav.waitTitle('服务提供方');
  await nav.click('settings.ai.provider.2.header');
  await nav.waitTitle('备用模型服务');
  await nav.click('settings.ai.provider.2.delete_provider');
  await nav.node('settings.ai.delete.dialog');
  await h.sleep(500);
  await shot('e-delete-confirm');
  await nav.click('settings.ai.delete.cancel');
  report.checks.push('delete confirmation: native Modal, cancel keeps the provider');
  // (f) 行为与权限。
  await nav.toSub('ai','behavior');
  await nav.node('settings.field.permission_mode');
  await shot('f-behavior');
  report.checks.push('behavior: native rows with dividers');
  // (g) 技能与 MCP。
  await nav.toSub('ai','extensions');
  await nav.node('settings.skill.0.row');
  await nav.node('settings.mcp.1.row');
  await shot('g-extensions');
  report.checks.push('extensions: skills and MCP rows with native switches, buttons and menus');
 },'configured');
 report.status='passed';
}catch(e){report.status='failed';report.error=String((e as any)?.stack??e);process.exitCode=1;await shot('failure').catch(()=>{});}
finally{await writeFile(join(out,`report-${theme}.json`),JSON.stringify(report,null,2));console.log(JSON.stringify({status:report.status,checks:report.checks.length,error:report.error}));}
