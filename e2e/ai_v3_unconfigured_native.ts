/** Real unconfigured production assistant and its existing settings entry points. */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdtemp,mkdir,writeFile,open,realpath} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {aiToggleId} from './ai_entry.ts';
const prefix=process.env.ZW_AI_TEST_PREFIX??'/tmp/zw-v3-ai-prefix',h=await import(join(prefix,'share/zenit/harness/client.ts'));
const out=resolve(process.argv[2]??'/tmp/zw-v3-ai-unconfigured');await mkdir(out,{recursive:true});
const iso=await realpath(await mkdtemp('/tmp/zw-ai-v3-unconfigured-')),data=join(iso,'data'),rpc=join(iso,'rpc');await mkdir(data);await mkdir(rpc);
await writeFile(join(data,'config.toml'),'[meta]\nconfig_revision=1\n[ui]\ntheme="dark"\nfont_family="Menlo"\nfont_size=14\n');process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const log=await open(join(out,'app.log'),'w'),app=spawn(join(prefix,'bin/zerowork'),[],{env:{...process.env,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1',ZENIT_E2E_FILE_RPC_DIR:rpc,ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',OPENAI_API_KEY:'',ANTHROPIC_API_KEY:''},stdio:['ignore',log.fd,log.fd]});
const shown=(n:any)=>n&&n.hidden!==true&&n.visible!==false&&(n.effective_opacity??1)>0&&n.rect?.w>0&&n.rect?.h>0;
const visible=(id:string)=>h.waitFor(async()=>(await h.query(id)).find(shown)??null,15000);
const click=async(id:string)=>{await visible(id);assert((await h.clickTestId(id)).ok,id)};
const capture=async(name:string)=>{await h.sleep(160);await h.screenshot(join(out,name+'.png'));await writeFile(join(out,name+'.json'),JSON.stringify(await h.query('ai.panel'),null,2))};
const report:any={status:'running',checks:[],isolatedData:iso};
try{
 await h.waitForServerReady(60000);await h.resizeWindow(860,480);await click('workspace.empty.local');await visible('terminal.surface');await click(await aiToggleId());await visible('ai.empty.unconfigured');await visible('ai.empty.title');await capture('01-unconfigured-compact');const panelRect=(await visible('ai.panel')).rect;assert.equal(panelRect.w,320,'#52 floating panel width clamp(content*0.42,320,420) hits the 320 minimum at 860x480');assert.equal((await visible('ai.prompt')).rect.w,panelRect.w-16,'prompt spans the panel minus the 8 composer margins of a 320 panel (Pencil Kaf7E ⑤; the native compound field)');/* ai-redesign-a: Send keeps the native primary sm disabled look (the old 0.45 fade was an override); disabled = not focusable. */assert.notEqual((await visible('ai.send')).focusable,true,'send is disabled without a configured model');
 await click('ai.empty.settings');await visible('settings.panel');await visible('settings.ai.providers');await capture('02-ai-settings');await h.key('w',{cmd:true});await h.waitFor(async()=>!(await h.query('settings.panel')).some(shown)||null,15000);await visible('ai.empty.unconfigured');assert(!(await h.query('ai.empty.ollama')).some(shown),'V3 setup (ai_empty_view.mountSetup) has a single "配置 AI 服务" entry');report.checks.push('Unconfigured V3 setup is visible; its single real AI settings entry point opens settings');
 await h.resizeWindow(1440,900);await capture('03-unconfigured-wide');report.status='passed';
}catch(e){report.status='failed';report.error=String(e);await capture('failure').catch(()=>{});process.exitCode=1;}
finally{app.kill('SIGTERM');if(app.exitCode===null&&app.signalCode===null)await new Promise(r=>app.once('close',r));await log.close();await writeFile(join(out,'report.json'),JSON.stringify(report,null,2))}
console.log(JSON.stringify(report));
