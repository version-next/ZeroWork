/** Hover-open conversation remains listed after fork; branches keep independent history. */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createServer} from 'node:http';
import {mkdtemp,mkdir,writeFile,open,realpath} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import * as h from '../zig-out/share/zenit/harness/client.ts';
import {isTitleRequest,skipTitle} from './ai_title_fixture.ts';
import {readRequestJson} from './provider_fixture.ts';
const out=resolve(process.argv[2]??'/tmp/zw-ai-fork-retention');await mkdir(out,{recursive:true});
const dataRoot=await realpath(await mkdtemp('/tmp/zw-ai-fork-')),data=join(dataRoot,'data'),rpc=join(dataRoot,'rpc');await mkdir(data);await mkdir(rpc);
const requests=[];
const server=createServer(async(req,res)=>{if(req.method==='GET'){res.writeHead(200,{'content-type':'application/json'});res.end(JSON.stringify({data:[{id:'grok/grok-4.7',context_window:256000,reasoning:false,vision:false}]}));return}const body=await readRequestJson(req);if(isTitleRequest(body))return skipTitle(res);requests.push(body);const q=body.messages.findLast(m=>m.role==='user').content;res.writeHead(200,{'content-type':'text/event-stream'});res.end('data: '+JSON.stringify({choices:[{index:0,delta:{content:'Answer '+q}}]})+'\n\ndata: [DONE]\n\n')});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
await writeFile(join(data,'config.toml'),`[meta]\nconfig_revision=1\n[ui]\ntheme="dark"\n[ai]\ndefault_provider="fixture"\n[[ai.providers]]\nid="fixture"\nkind="openai_compat"\nendpoint="http://127.0.0.1:${server.address().port}/v1"\nenabled=true\n[[ai.providers.models]]\nname="grok/grok-4.7"\ncontext_window=256000\ndefault=true\n[[ai.providers.models]]\nname="team/claude-sonnet-4-5"\ncontext_window=200000\n`);
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;const log=await open(join(out,'app.log'),'w');const app=spawn(resolve('zig-out/bin/zerowork'),[],{env:{...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1',ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0'},stdio:['ignore',log.fd,log.fd]});
const shown=n=>n&&n.hidden!==true&&n.visible!==false&&(n.effective_opacity??1)>0&&n.rect?.w>0&&n.rect?.h>0;
const visible=id=>h.waitFor(async()=>(await h.query(id)).find(shown)??null,12000);
const click=async id=>{await visible(id);assert((await h.clickTestId(id)).ok,id)};
const flat=n=>n?[n,...(n.children??[]).flatMap(flat)]:[];const text=n=>flat(n).map(n=>n.text??'').join(' ');
const chipShows=(chip:any,name:string)=>{const t=String(flat(chip).map((n:any)=>n.text??'').join('')).trim();const base=t.split(' · ')[0];if(base===name)return true;if(!base.endsWith('…'))return false;const p=base.slice(0,-1);return p.length>=3&&name.startsWith(p);};/* ai-redesign-a: the model chip is “model · effort”, ellipsized to the room left (Pencil ⑤). */
const send=async q=>{const count=requests.length;await click('ai.prompt');await h.type_(q);await click('ai.send');await h.waitFor(async()=>requests.length>count&&text(await visible('ai.panel')).includes('Answer '+q)&&!(await h.query('ai.stop')).some(shown)||null,20000)};
// Fork (ai.turn.fork) is copy_use from a turn checkpoint (ai_host.zig forkThrough): with a bound conversation it asks
// "结束当前会话并使用副本？" and, once accepted, ends+unbinds the original and binds the fork. Switching between the two is
// Restore (ai.session.restore.N, also End-confirmed); ai.session.jump.N now opens the read-only history dialog.
const accept=async()=>{await h.sleep(150);if((await h.query('ai.session.close.accept')).some(shown))await click('ai.session.close.accept');await h.waitFor(async()=>!(await h.query('ai.session.close.confirmation')).some(shown)||null,12000)};
const restore=async n=>{await click('ai.sessions');await visible('ai.sessions.menu');await click('ai.session.restore.'+n);await accept();await h.waitFor(async()=>!(await h.query('ai.sessions.menu')).some(shown)||null,12000)};
const cap=async name=>{await h.screenshot(join(out,name+'.png'));await writeFile(join(out,name+'.json'),JSON.stringify(await h.query('ai.panel'),null,2))};
const report={status:'running',checks:[]};
try{
 await h.waitForServerReady();await h.resizeWindow(1440,1000);await click('workspace.empty.local');await click('ai.launcher');await visible('ai.prompt');
 await send('ORIGINAL_ONE');await send('ORIGINAL_TWO');await click('ai.turn.fork');await visible('ai.session.close.confirmation');await accept();await click('ai.sessions');await visible('ai.sessions.menu');
 assert.equal((await h.query('ai.session.row.1')).filter(shown).length,1,'original conversation remains listed');assert.equal((await h.query('ai.session.row.2')).filter(shown).length,1,'fork remains listed');await cap('01-both-sessions');report.checks.push('Hover-open original and fork both remain listed');
 await click('ai.sessions.close');assert(!text(await visible('ai.panel')).includes('ORIGINAL_TWO'),'fork from first turn excludes second turn');await send('BRANCH_ONLY');const branch=requests.at(-1);assert(branch.messages.some(m=>m.role==='user'&&m.content.includes('ORIGINAL_ONE')));assert(!branch.messages.some(m=>m.role==='user'&&m.content.includes('ORIGINAL_TWO')));await restore(1);await h.waitFor(async()=>text(await visible('ai.panel')).includes('ORIGINAL_TWO')||null,12000);assert(!text(await visible('ai.panel')).includes('BRANCH_ONLY'));await send('ORIGINAL_CONTINUE');const original=requests.at(-1);assert(original.messages.some(m=>m.role==='user'&&m.content.includes('ORIGINAL_TWO')));assert(!original.messages.some(m=>m.role==='user'&&m.content.includes('BRANCH_ONLY')));await restore(2);await h.waitFor(async()=>text(await visible('ai.panel')).includes('BRANCH_ONLY')||null,12000);assert(!text(await visible('ai.panel')).includes('ORIGINAL_CONTINUE'));report.checks.push('Switching between original and fork preserves independent transcript and wire context');await cap('02-branch-retained');
 const claude='team/claude-sonnet-4-5';
 await click('ai.composer.model');
 const claudeRow=async()=>(await h.query('ai.model.option')).find(n=>shown(n)&&flat(n).some(c=>c.test_id==='ai.model.name'&&c.text===claude));
 const option=await h.waitFor(async()=>await claudeRow()??null,10000);
 assert((await h.clickAt(option.rect.x+option.rect.w/2,option.rect.y+option.rect.h/2)).ok);
 await h.waitFor(async()=>flat(await claudeRow()).some(c=>c.test_id==='ai.model.selected')||null,10000);
 await h.waitFor(async()=>chipShows(await visible('ai.composer.model'),claude)||null,10000);
 await cap('03-composer-claude');
 // The model picker remains open for reasoning controls. Close it before opening the sessions list.
 assert((await h.key('escape')).ok);
 await h.waitFor(async()=>!(await h.query('ai.model.menu')).some(shown)||null,10000);
 await restore(1);
 await h.waitFor(async()=>chipShows(await visible('ai.composer.model'),'grok/grok-4.7')||null,10000);
 await cap('04-composer-grok');report.checks.push('Composer brand follows model selection and restores original model when switching conversations');
 report.status='passed';
}catch(e){report.status='failed';report.error=e instanceof Error?e.stack??e.message:String(e);await cap('failure').catch(()=>{});process.exitCode=1}finally{app.kill('SIGTERM');if(app.exitCode===null&&app.signalCode===null)await new Promise(r=>app.once('close',r));server.closeAllConnections();server.close();await log.close();await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report))}
