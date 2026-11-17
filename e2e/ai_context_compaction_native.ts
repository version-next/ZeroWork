/** Own native application + loopback HTTP model. Exercises actual host wiring;
 * generated fixture summaries establish transport/state semantics, not LLM quality. */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createServer } from 'node:http';
import { spawn } from 'node:child_process';
import { copyFile, mkdir, mkdtemp, open, readFile, writeFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { tmpdir } from 'node:os';
import { query, clickTestId, mouseMove, key, type_, screenshot, sleep, waitFor, waitForServerReady, resizeWindow } from '../zig-out/share/zenit/harness/client.ts';
import {aiToggleId} from './ai_entry.ts';
import {isTitleBody,skipTitle} from './ai_title_fixture.ts';
import {readRequestText} from './provider_fixture.ts';
const options: Record<string,string> = {};
for (let i=2; i<process.argv.length; i+=2) options[process.argv[i]] = process.argv[i+1];
assert(options['--binary'] && options['--out']);
const output=resolve(options['--out']), source=resolve(options['--binary']);
await mkdir(output,{recursive:true});
const iso=await mkdtemp('/private/tmp/zw-compaction-native-'), data=join(iso,'data'), rpc=join(iso,'rpc'), frozen=join(output,'frozen');
await Promise.all([mkdir(data),mkdir(rpc),mkdir(frozen,{recursive:true})]);
await copyFile(source,join(frozen,'zerowork')); await copyFile(join(dirname(source),'zw_ipc.so'),join(frozen,'zw_ipc.so'));
let mode='success', summaryCount=0, ordinaryCount=0;
const requests:any[]=[];
const server=createServer(async(req,res)=>{
  if(req.method==='GET') {res.setHeader('Content-Type','application/json');res.end(JSON.stringify({data:[{id:'compaction-native',context_window:32768,reasoning:false,vision:false}]}));return;}
  const raw=await readRequestText(req);if(isTitleBody(raw))return skipTitle(res);
  const body=JSON.parse(raw), summary=body.messages.some((m:any)=>m.role==='system' && m.content.includes('Create concise conversation memory'));
  const record:any={summary,mode,body};requests.push(record);
  res.once('close',()=>{if(!res.writableFinished)record.aborted=true;});
  let text:string;
  if(summary){
    summaryCount++;assert(!body.tools?.length);
    assert(JSON.stringify(body.messages).includes('OLD_NATIVE_MARKER'));
    assert(!JSON.stringify(body.messages).includes('RECENT_NATIVE_SECOND'));
    if(mode==='failure'){res.writeHead(400);res.end('summary failed');record.responded=400;return;}
    await sleep(mode==='cancel'?1800:550);
    text='MEMORY_NATIVE_BACKUP_TESTS_PASSED. Goal backup; constraint no deployment; pending review.';
  } else {ordinaryCount++;text='VISIBLE_NATIVE_ANSWER_'+ordinaryCount;}
  res.writeHead(200,{'Content-Type':'text/event-stream'});
  if(res.destroyed)return;
  res.end('data: '+JSON.stringify({choices:[{delta:{content:text}}]})+'\n\ndata: [DONE]\n\n');record.responded=200;
});
await new Promise<void>(done=>server.listen(0,'127.0.0.1',done));
const port=(server.address() as any).port;
await writeFile(join(data,'config.toml'),`[ai]\ndefault_provider = "local-summary"\npermission_mode = "confirm"\n[[ai.providers]]\nid = "local-summary"\nkind = "openai_compat"\nendpoint = "http://127.0.0.1:${port}/v1/chat/completions"\nenabled = true\n[[ai.providers.models]]\nname = "compaction-native"\ncontext_window = 32768\ndefault = true\nreasoning = false\nvision = false\nefforts = []\n`);
const env={...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1',ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0'};
for(const name of ['ZEROWORK_AI_MOCK','ZEROWORK_AI_ENDPOINT','ZEROWORK_AI_MODEL','ZEROWORK_AI_PROVIDER'])delete env[name];
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const log=await open(join(output,'app.log'),'w');
const app=spawn(join(frozen,'zerowork'),[],{cwd:process.cwd(),env,stdio:['ignore',log.fd,log.fd]});
const ended=new Promise<void>(done=>app.once('close',()=>done()));
const report:any={status:'running',isolated:iso,source,binary_sha256:createHash('sha256').update(await readFile(join(frozen,'zerowork'))).digest('hex'),stages:[],limits:['Synthetic Harness input in own background Metal window; no physical input claim','Loopback deterministic model fixture verifies real HTTP and native host wiring, not external LLM summary quality']};
function shown(n:any):boolean{return n?.rect&&n.hidden!==true&&n.visible!==false&&(n.effective_opacity??1)>0&&n.rect.w>0&&n.rect.h>0;}
function text(n:any):string{return (n.text??'')+(n.children??[]).map(text).join('');}
async function visible(id:string){return waitFor(async()=>(await query(id)).find(shown)??null,20000);}
async function click(id:string){await visible(id);const result=await clickTestId(id);assert(result.ok,`${id}: ${JSON.stringify(result)}`);}
async function cap(name:string){const path=join(output,name+'.png');assert((await screenshot(path)).ok);const usage=await query('ai.usage.menu');await writeFile(join(output,name+'.usage.json'),JSON.stringify(usage,null,2));assert(!JSON.stringify(usage).includes('清空上下文'));assert(!JSON.stringify(usage).includes('clear_context'));report.stages.push({name,screenshot:path,usage_rect:usage.find(shown)?.rect});}
// The usage menu no longer has an ai.usage.compaction.status card (removed in f668ebd7; unit test
// ai_composer_controls_view_tests asserts it is null). Compaction state is now only the single 24x24 action button:
// running => ai.usage.compaction.cancel; otherwise ai.usage.compaction.start whose a11y label/tooltip carries
// 压缩失败/已取消/已压缩 (ai_composer_controls_view.zig refreshUsage). The harness cannot read a11y labels, and the
// portaled tooltip is only reachable through /tree, which exceeds RESULT_BUF_SIZE for this window. Each terminal state is
// therefore verified from the real request it settled plus the visible button/usage state.
async function idleButton(){return waitFor(async()=>{if((await query('ai.usage.compaction.cancel')).some(shown))return null;const button=(await query('ai.usage.compaction.start')).find(shown);return button??null;},20000);}
async function status(fragment:string){
  if(fragment==='正在整理')return visible('ai.usage.compaction.cancel');
  const last=()=>requests.filter(r=>r.summary).at(-1);
  if(fragment==='压缩失败')await waitFor(async()=>last()?.mode==='failure'&&last()?.responded===400||null,20000);
  else if(fragment==='已取消')await waitFor(async()=>last()?.mode==='cancel'&&last()?.aborted===true||null,20000);
  else if(fragment==='已压缩')await waitFor(async()=>last()?.mode==='success'&&last()?.responded===200||null,20000);
  else assert.fail(fragment);
  return {button:await idleButton()};
}
async function partValue(name:string){const rows=(await query('ai.usage.menu')).filter(shown);let found:any=null;const walk=(n:any)=>{const kids=n.children??[];for(let i=0;i<kids.length;i++){if(kids[i].text===name){const v=kids.slice(i+1).find((k:any)=>k.test_id==='ai.usage.part.value');if(v)found=v;}walk(kids[i]);}};rows.forEach(walk);assert(found,name);return found;}
async function send(prompt:string,answer:number){await click('ai.prompt');assert((await key('a',{cmd:true})).ok);assert((await type_(prompt)).ok);await click('ai.send');await waitFor(async()=>{const responses=await query('ai.response');return responses.some(n=>text(n).includes('VISIBLE_NATIVE_ANSWER_'+answer))&&!(await query('ai.stop')).some(shown)||null;},20000);}
function parseTokens(s:string){const m=s.match(/~?([0-9.]+)([KM]?)/i);assert(m,s);return Number(m[1])*(m[2].toUpperCase()==='K'?1000:m[2].toUpperCase()==='M'?1000000:1);}
async function history(){return (await query('ai.message.user.bubble')).map(text);}
try{
  await waitForServerReady();assert.equal(Number(JSON.parse(await readFile(join(rpc,'owner.json'),'utf8')).pid),app.pid);
  await resizeWindow(1440,900);await click('workspace.empty.local');await visible('terminal.surface');await click(await aiToggleId());await visible('ai.prompt');
  await send('OLD_NATIVE_MARKER '+('Historical source data. '.repeat(65))+' Goal backup. No deployment. Tests passed. Pending review.',1);
  await send('RECENT_NATIVE_SECOND',2);await send('RECENT_NATIVE_LAST',3);
  const before=await history();assert.equal(before.length,3);
  await click('ai.composer.usage');await cap('01-ready');const conversationBefore=parseTokens(text(await partValue('对话')));
  mode='failure';await click('ai.usage.compaction.start');await status('压缩失败');await cap('02-failed');assert.deepEqual(await history(),before);assert.equal(parseTokens(text(await partValue('对话'))),conversationBefore,'an unpublished compaction must leave history usage unchanged');
  mode='cancel';const beforeCancel=summaryCount;await click('ai.usage.compaction.start');await status('正在整理');await waitFor(async()=>summaryCount>beforeCancel||null,10000);await cap('03-running');await click('ai.usage.compaction.cancel');await status('已取消');await cap('04-cancelled');assert.deepEqual(await history(),before);assert.equal(parseTokens(text(await partValue('对话'))),conversationBefore,'an unpublished compaction must leave history usage unchanged');
  mode='success';await waitFor(async()=>{const buttons=await query('ai.usage.compaction.start');return buttons.some(n=>shown(n)&&!n.disabled)||null;},20000);await sleep(200);
  await click('ai.usage.compaction.start');await status('正在整理');await status('已压缩');await cap('05-success');const success=await status('已压缩');const conversationAfter=parseTokens(text(await partValue('对话')));assert(conversationAfter<conversationBefore,`compacted history tokens ${conversationBefore} -> ${conversationAfter}`);report.conversation_tokens={before:conversationBefore,after:conversationAfter};const values=(await query('ai.usage.part.value')).filter(shown);assert.equal(values.length,4);/* ai-redesign-a (Pencil Kaf7E O6): legend values right-aligned in one column; the compaction control is a native secondary sm Button with a label, under the bar and the legend. */const right=values.map((n:any)=>n.rect.x+n.rect.w);assert(right.every((x:number)=>Math.abs(x-right[0])<=0.5),'legend values share one right edge');const track=(await query('ai.usage.track')).find(shown);assert(success.button.rect.h>=22&&success.button.rect.h<=28,'native sm button height');assert(success.button.rect.w>24,'labelled button');assert(success.button.rect.y>=track.rect.y+track.rect.h,'compaction action below the bar');const summaryText=text((await query('ai.usage.summary')).find(shown));const totalText=summaryText.match(/~[0-9.]+[KM]?\s*\//i)?.[0];assert(totalText,summaryText);{// Each figure is rounded independently for display (tokenText: one decimal for K/M), so the parts must sum to
 // a value whose display-rounding interval overlaps the total's interval rather than to the same rounded string.
 const span=(s:string)=>{const m=s.match(/~?([0-9.]+)([KM]?)/i)!;const unit=m[2].toUpperCase()==='K'?1000:m[2].toUpperCase()==='M'?1000000:1;const step=unit===1?1:(m[1].includes('.')?0.1:1)*unit;const v=Number(m[1])*unit;return unit===1?[v,v]:[v-step/2,v+step/2];};
 const parts=values.map(n=>span(text(n))),lo=parts.reduce((a,p)=>a+p[0],0),hi=parts.reduce((a,p)=>a+p[1],0),[tlo,thi]=span(totalText);
 assert(lo<=thi&&hi>=tlo,`parts ${values.map(n=>text(n)).join('+')} = [${lo},${hi}] must match total ${totalText} = [${tlo},${thi}]`);}report.status_rect=success.button.rect;report.usage_total_text=totalText;report.usage_parts=values.map(n=>({text:text(n),rect:n.rect}));assert.deepEqual(await history(),before);
  // Harness key names are lowercase ('Escape' is not a key and was silently ignored); assert the popover closes.
  // Clicking the compaction action leaves the pointer on it; its hover tooltip (zenit Tooltip, close_on_escape) would
  // be the topmost Escape layer, so leave the button before dismissing the usage popover.
  {/* ai-redesign-a: the usage popover has no title row (Pencil O6); its head row is ai.usage.summary. */const title=(await query('ai.usage.summary')).find(shown);await mouseMove(title.rect.x+title.rect.w/2,title.rect.y+title.rect.h/2);await sleep(300);}
  report.escape_result=await key('escape');await sleep(300);report.menu_after_escape=(await query('ai.usage.menu')).some(shown);
  await waitFor(async()=>!(await query('ai.usage.menu')).some(shown)||null,5000);await send('NEXT_NATIVE_REQUEST',4);
  const next=requests.filter(r=>!r.summary).at(-1).body;
  const wire=JSON.stringify(next.messages);assert(wire.includes('MEMORY_NATIVE_BACKUP_TESTS_PASSED'));assert(!wire.includes('OLD_NATIVE_MARKER'));assert(wire.includes('RECENT_NATIVE_SECOND')&&wire.includes('RECENT_NATIVE_LAST'));
  assert.equal((await history()).length,4);await cap('06-next-request');
  report.status='passed';report.visible_history_count_before=before.length;report.visible_history_count_after=(await history()).length;report.next_request_uses_summary=true;report.summary_requests=summaryCount;report.ordinary_requests=ordinaryCount;
}catch(e){report.status='failed';report.error=String(e);try{await cap('failure');}catch{}}
finally{
  report.requests=requests;report.finished_at=new Date().toISOString();if(app.exitCode===null&&app.signalCode===null)app.kill('SIGTERM');await Promise.race([ended,sleep(2000)]);if(app.exitCode===null&&app.signalCode===null){app.kill('SIGKILL');await ended;}server.close();await log.close();await writeFile(join(output,'report.json'),JSON.stringify(report,null,2));console.log(JSON.stringify({status:report.status,error:report.error,report:join(output,'report.json')}));
}
if(report.status!=='passed')process.exitCode=1;
