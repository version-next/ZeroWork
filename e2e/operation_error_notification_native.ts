/** Existing global notifications for actual AI failure and blocked model configuration. */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createServer} from 'node:http';
import {mkdtemp,mkdir,writeFile,readFile,open,realpath} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import * as h from '../vendor/zenit/e2e/client.ts';
import {aiToggleId} from './ai_entry.ts';
const binary=resolve(process.argv[2]),out=resolve(process.argv[3]);await mkdir(out,{recursive:true});
const shown=(n:any)=>!n.hidden&&n.visible!==false&&(n.effective_opacity??1)>0&&n.rect?.w>0&&n.rect?.h>0;
const flat=(n:any):any[]=>[n,...(n.children??[]).flatMap(flat)],text=(n:any)=>flat(n).map(n=>n.text??'').join(' ');
const node=(id:string)=>h.waitFor(async()=>(await h.query(id)).find(shown)??null,15000);
async function click(id:string){await node(id);assert((await h.clickTestId(id)).ok,id);await h.sleep(120);}
let requests=0;
// Keep the whole diagnostic inside Harness's per-node text preview. Explicit
// line breaks still make it taller than the native detail viewport.
const diagnostic=['Request failure details.', ...Array.from({length:20},(_,i)=>`#${i+1}`),'FULL_ERROR_END'].join('\n');
const server=createServer(async(req,res)=>{for await(const _ of req){} requests++;res.writeHead(400,{'content-type':'application/json'});res.end(JSON.stringify({error:{message:diagnostic,type:'invalid_request_error'}}));});
await new Promise<void>(r=>server.listen(0,'127.0.0.1',r));
const report:any={status:'running',checks:[]};
async function run(mode:'http-failure'|'missing-key'){
 const base=await realpath(await mkdtemp(join(tmpdir(),'zw-global-error-'))),data=join(base,'data'),rpc=join(base,'rpc');await mkdir(data);await mkdir(rpc);await writeFile(join(data,'hosts.toml'),'');
 const endpoint=mode==='http-failure'?`http://127.0.0.1:${(server.address()as any).port}/v1/chat/completions`:'https://example.test/v1';
 await writeFile(join(data,'config.toml'),`[meta]\nconfig_revision=1\n[ui]\ntheme="dark"\n[ai]\ndefault_provider="Fixture"\n[[ai.providers]]\nid="Fixture"\nkind="openai_compat"\nendpoint="${endpoint}"\nenabled=true\n[[ai.providers.models]]\nname="test-model"\ncontext_window=128000\ndefault=true\n`);
 process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;const log=await open(join(out,mode+'.log'),'w');
 const app=spawn(binary,[],{env:{...process.env,ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1'},stdio:['ignore',log.fd,log.fd]});const ended=new Promise(r=>app.once('close',r));
 try{
  await h.waitForServerReady();assert.equal(Number(JSON.parse(await readFile(join(rpc,'owner.json'),'utf8')).pid),app.pid);await h.resizeWindow(1440,900);await click('workspace.empty.local');await click(await aiToggleId());await click('ai.prompt');await h.type_('检查统一错误通知。');
  if(mode==='http-failure'){
   await click('ai.send');await node('ai.recovery');
   const toast=await node('notifications.toast.0');assert(text(toast).includes('AI 请求失败'));assert(text(toast).includes('400'));
   await h.mouseMove(toast.rect.x+20,toast.rect.y+20);
   const viewport=await node('notifications.message.viewport'),title=await node('notifications.title'),detail=await node('notifications.detail');
   assert(detail.rect.h>viewport.rect.h);assert(title.rect.y+title.rect.h<=viewport.rect.y);
   await h.screenshot(join(out,'01-http-failure.png'));
   assert((await h.scrollAt(viewport.rect.x+viewport.rect.w/2,viewport.rect.y+viewport.rect.h/2,0,-10000)).ok);
   const scrolled=await h.waitFor(async()=>{
    const detail=(await h.query('notifications.detail')).find(shown);
    return detail&&Math.abs(detail.rect.y+detail.rect.h-viewport.rect.y-viewport.rect.h)<1.5?detail:null;
   },5000);
   const settledTitle=(await node('notifications.title')).rect;
   for(const axis of ['x','y','w','h'] as const) assert(Math.abs(settledTitle[axis]-title.rect[axis])<0.2,'scroll does not move the header');
   assert(scrolled.rect.y<detail.rect.y);
   await writeFile(join(out,'long-error-geometry.json'),JSON.stringify({viewport,detail,scrolled,title},null,2));
   await h.screenshot(join(out,'01b-full-error-scrolled.png'));
   assert(text(scrolled).includes('FULL_ERROR_END'));
   assert(!(await h.query('ai.feedback')).some(shown));assert(requests>0);
   report.checks.push('The local HTTP 400 keeps AI recovery controls and publishes its cause through the global notification, with a fixed title and scrollable detail');
  }else{
   const before=requests;
   await node('ai.empty.unconfigured');
   assert.notEqual((await node('ai.send')).focusable,true,'An unconfigured model cannot send');
   await h.screenshot(join(out,'02-model-gate.png'));
   await h.resizeWindow(860,480);await node('ai.empty.settings');
   await h.screenshot(join(out,'03-model-gate-compact.png'));
   await click('ai.empty.settings');await node('settings.ai.providers');
   await h.screenshot(join(out,'04-model-settings.png'));
   assert.equal(requests,before);
   report.checks.push('A missing model key blocks the prompt and the compact unconfigured state routes to AI provider settings');
  }
 }catch(e){await h.screenshot(join(out,mode+'-failure.png')).catch(()=>{});throw e;}
 finally{if(app.exitCode===null)app.kill('SIGTERM');await ended;await log.close();}
}
try{await run('http-failure');await run('missing-key');report.status='passed';}catch(e){report.status='failed';report.error=String(e);throw e;}finally{server.closeAllConnections();server.close();await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));}
