// 迁移说明（F-set-ai 之后）
// 删除折叠提供方卡高 64、模型行高 60 及元数据相对名称的像素位置断言：提供方改为列表/详情导航，模型改用原生设置行；保留名称和上下文/能力文本。
/** Isolated settings -> assistant refresh, local brand marks, and model row layout. */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdtemp,mkdir,writeFile,readFile,open,realpath} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import * as h from '../vendor/zenit/e2e/client.ts';
import {settingsNav,shown,textOf} from './settings_nav.ts';
import {aiToggleId} from './ai_entry.ts';
const out=resolve(process.argv[2]??'/tmp/zw-ai-settings-refresh');await mkdir(out,{recursive:true});
const iso=await realpath(await mkdtemp('/tmp/zw-ai-refresh-')),data=join(iso,'data'),rpc=join(iso,'rpc');await mkdir(data);await mkdir(rpc);
await writeFile(join(data,'config.toml'),`[meta]\nconfig_revision=1\n[updates]\nauto_check=false\n[ui]\ntheme="dark"\n[ai]\ndefault_provider="Magpie"\n[[ai.providers]]\nid="Magpie"\nkind="openai_compat"\nendpoint="http://127.0.0.1:1/v1"\nenabled=false\n[[ai.providers.models]]\nname="grok/grok-4.7"\ncontext_window=256000\nreasoning=true\nvision=true\nefforts=["low","high"]\ndefault=true\n[[ai.providers.models]]\nname="team/claude-sonnet-4-5"\ncontext_window=200000\nreasoning=true\nvision=true\nefforts=["high"]\n[[ai.providers.models]]\nname="团队自建模型"\ncontext_window=32000\n`);
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;const log=await open(join(out,'app.log'),'w');const app=spawn(resolve('zig-out/bin/zerowork'),[],{env:{...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1',ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0'},stdio:['ignore',log.fd,log.fd]});
const ended=new Promise<void>(r=>app.once('close',()=>r()));
const started=new Promise<void>((ready,fail)=>{app.once('spawn',()=>ready());app.once('error',fail);});
const nav=settingsNav(),visible=nav.node,click=nav.click,text=textOf;
const flat=(n:any):any[]=>n?[n,...(n.children??[]).flatMap(flat)]:[];
const capture=async(name:string)=>{await h.mouseMove(20,300);await h.sleep(400);assert((await h.screenshot(join(out,name+'.png'))).ok);};
const report:any={status:'running',checks:[],data,limits:[]};
report.limits.push('删除折叠提供方卡高 64、模型行高 60 及元数据相对名称的像素位置断言：提供方改为列表/详情导航，模型改用原生设置行；保留名称和上下文/能力文本。');
try{
 await started;await h.waitForServerReady();assert.equal(Number(JSON.parse(await readFile(join(rpc,'owner.json'),'utf8')).pid),app.pid);await h.resizeWindow(1440,1000);await click('workspace.empty.local');await click(await aiToggleId());await visible('ai.empty.unconfigured');
 await click('ai.empty.settings');await nav.toSub('ai','providers');await visible('settings.ai.provider.0.header');
 assert(!(await h.query('settings.ai.provider.0.endpoint')).some(shown));assert(text(await visible('settings.ai.provider.0.header')).includes('Magpie'));await capture('00-default-collapsed');
 // 头像字：非 Ollama 提供方固定显示“AI”（src/features/settings/model/ai_pane.zig providerInitial）。
 const logo=await visible('settings.ai.provider.0.logo');assert.equal(text(logo).trim(),'AI');
 await click('settings.ai.provider.0.header');await nav.waitTitle('Magpie');await click('settings.ai.provider.0.enabled');
 await nav.reveal('settings.ai.provider.0.model.0.card');
 assert.equal(text(await visible('settings.ai.provider.0.model.0.name.text')).trim(),'grok/grok-4.7');
 const meta=await visible('settings.ai.provider.0.model.0.metadata');assert(text(meta).includes('256K 上下文'));assert(text(meta).includes('推理'));assert(text(meta).includes('识图'));
 await capture('01-settings');report.checks.push('Custom provider shows the AI avatar in list; detail exposes model name and readable context/reasoning/vision');
 await visible('settings.footer');await click('settings.save');await h.waitFor(async()=>(await readFile(join(data,'config.toml'),'utf8')).includes('enabled = true')||null,20000);await nav.gone('settings.footer');report.stage='close-after-save';await nav.close();report.stage='welcome-configured';await visible('ai.empty.configured');assert(!(await h.query('ai.empty.unconfigured')).some(shown));await capture('02-refreshed');report.checks.push('Saving enabled provider refreshes the already-open assistant welcome');
 report.stage='model-menu';await click('ai.composer.model');await visible('ai.model.logo');
 // Native settings model rows no longer contain brand marks; verify the bundled Grok mark in the assistant chooser.
 const grok=(await h.query('ai.model.option')).find(n=>shown(n)&&text(n).includes('grok/grok-4.7'));assert(grok);assert(flat(grok).some(n=>n.test_id==='ai.model.logo'&&flat(n).some(c=>c.tag==='image')));
 await capture('03-model-menu');report.checks.push('Assistant model chooser displays the bundled Grok brand mark');await h.key('escape');
 report.stage='menu-escape';await nav.gone('ai.model.menu');
 report.stage='reopen-settings';await nav.open();await nav.toSub('ai','providers');await visible('settings.ai.provider.0.header');assert(!(await h.query('settings.ai.provider.0.endpoint')).some(shown));report.checks.push('Initial settings open and explicit navigation after reopening show the list before provider fields');await click('settings.ai.provider.0.header');await nav.waitTitle('Magpie');await h.resizeWindow(860,600);await nav.reveal('settings.ai.provider.0.model.0.card');await capture('04-compact');
 assert.equal(text(await visible('settings.ai.provider.0.model.0.name.text')).trim(),'grok/grok-4.7');const compactMeta=text(await visible('settings.ai.provider.0.model.0.metadata'));for(const label of ['256K 上下文','推理','识图'])assert(compactMeta.includes(label));await nav.close();report.status='passed';
}catch(e){report.status='failed';report.error=String(e);await capture('failure').catch(()=>{});process.exitCode=1}finally{try{if(app.exitCode===null&&app.signalCode===null)app.kill('SIGTERM');await ended;}finally{await log.close();await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report));}}
