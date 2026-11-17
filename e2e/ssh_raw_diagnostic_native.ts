/** Raw SSH diagnostics of a failed handshake, in the real window (connection-progress-preview, scene `handshake`).
 *
 * Contract since design-r3 稿 1 (7cdc072f): a failed attempt is shown by the failure view
 * (`connection.progress.failure`), not by the progress card. Its "查看日志" lists the attempt's log lines without
 * the raw library text. The raw text of a failed step stays where it was: hovering that failed row in the
 * progress card's log (`connection.progress.logs.failure`) opens the native bubble
 * `connection.progress.logs.raw-popover` — which the user reaches while the next attempt is running, because the
 * card keeps the rows of the earlier attempts (`connection_host.zig` passes every attempt's records). There is no
 * separate "raw log" button anywhere.
 *
 * node e2e/ssh_raw_diagnostic_native.ts <output-directory>
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdir,mkdtemp,open,writeFile,rm} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import * as h from '../vendor/zenit/e2e/client.ts';
const out=resolve(process.argv[2]??'artifacts/ssh-raw-diagnostic');
await mkdir(out,{recursive:true});
const rpc=await mkdtemp('/tmp/zw-ssh-raw-');
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const log=await open(join(out,'native.log'),'w');
const app=spawn(resolve('zig-out/bin/connection-progress-preview'),['handshake'],{env:{...process.env,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1'},stdio:['ignore',log.fd,log.fd]});
const ended=new Promise(r=>app.once('close',r));
const shown=(n:any)=>n&&!n.hidden&&n.visible!==false&&n.opacity!==0&&(n.effective_opacity??1)>.9&&n.rect?.w>0&&n.rect?.h>0;
const text=(n:any):string=>(n.text??'')+(n.children??[]).map(text).join('');
const visible=(id:string)=>h.waitFor(async()=>(await h.query(id)).find(shown)??null,10000);
const absent=(id:string)=>h.waitFor(async()=>!(await h.query(id)).some(shown)||null,10000);
/** The log follows its newest row: wait until the rows stop moving, then return the failed row and an ordinary row,
 * both fully inside the log viewport (a row scrolled out of it is clipped and cannot be hovered). */
async function logRows(){
 let last='';
 return h.waitFor(async()=>{
  const well=(await h.query('connection.progress.logs')).find(shown);if(!well)return null;
  const inside=(n:any)=>shown(n)&&n.rect.y>=well.rect.y&&n.rect.y+n.rect.h<=well.rect.y+well.rect.h+.5;
  const failures=(await h.query('connection.progress.logs.failure')).filter(shown),failed=failures.find(inside);
  const ordinary=(await h.query('connection.progress.logs.row')).filter(inside).at(-1);
  const now=JSON.stringify([failed?.rect,ordinary?.rect]);
  if(!failed||!ordinary||now!==last){last=now;await h.sleep(120);return null;}
  return {failed,ordinary,failures};
 },10000);
}
const checks:string[]=[];let stage='startup';
try{
 await h.waitForServerReady();await h.resizeWindow(1280,720);
 stage='failed handshake: failure view';
 const failure=await visible('connection.progress.failure');
 assert(!(await h.query('connection.progress')).some(shown),'the failed attempt is the failure view, not the progress card');
 assert.equal((await h.query('connection.progress.logs.raw')).length,0,'no separate raw-log button');
 assert(!(await h.query('connection.progress.failure.logs')).some(shown),'failure log starts collapsed');
 await h.clickTestId('connection.progress.failure.logs.toggle');
 const lines=text(await visible('connection.progress.failure.logs'));
 assert(/\d{2}:\d{2}:\d{2}\.\d{3} - TCP/.test(lines)&&!lines.includes('+0.'),'failure log lines carry wall-clock timestamps: '+lines);
 assert(lines.includes('SSH 握手'),'failure log names the failed step: '+lines);
 assert(!lines.includes('rc=-13')&&!lines.includes('handshake transport'),'the failure view lists the steps without the raw library text');
 await absent('connection.progress.logs.raw-popover');
 await h.sleep(150);assert((await h.screenshot(join(out,'failure-logs.png'))).ok);
 await writeFile(join(out,'failure.json'),JSON.stringify(failure,null,2));
 checks.push('failed handshake shows the failure view; its log lists timestamped steps without raw library text; no raw-log button');

 stage='retry: card keeps the failed row of attempt 1';
 await h.clickTestId('connection.progress.failure.retry_now');
 await h.waitFor(async()=>text(await visible('connection.progress.attempt'))==='第 2 次尝试'||null);
 await absent('connection.progress.failure');
 await h.clickTestId('connection.progress.logs.toggle');
 for(const [w,ht] of [[1280,720],[860,480]]){
  stage=`raw bubble at ${w}x${ht}`;
  await h.resizeWindow(w,ht);
  const {failed,ordinary,failures}=await logRows();
  assert.equal(failures.length,1,'exactly the failed handshake row of attempt 1 carries a diagnostic');
  assert(text(failed).includes('尝试 1')&&text(failed).includes('SSH 握手'),'failed row belongs to attempt 1: '+text(failed));
  await h.mouseMove(ordinary.rect.x+40,ordinary.rect.y+8);
  await h.sleep(450);
  await absent('connection.progress.logs.raw-popover');
  await h.mouseMove(failed.rect.x+40,failed.rect.y+8);
  const bubble=await visible('connection.progress.logs.raw-popover');
  assert.equal(bubble.rect.w,520);
  assert(bubble.rect.x>=0&&bubble.rect.y>=0&&bubble.rect.x+bubble.rect.w<=w+1&&bubble.rect.y+bubble.rect.h<=ht+1,'bubble stays inside viewport');
  const raw=text(await visible('connection.progress.logs.raw-text'));
  await writeFile(join(out,`raw-${w}.json`),JSON.stringify(await h.query('connection.progress.logs.raw-text'),null,2));
  // Harness query truncates each text node to 200 bytes; complete values and
  // elapsed suffixes are covered by the production view/journal tests.
  assert(raw.startsWith('尝试 1 · 第 1 跳 · SSH 握手'),'bubble names the attempt, hop and step: '+raw);
  assert(raw.includes('handshake transport')&&raw.includes('rc=-13'));
  assert(/\n\d{2}:\d{2}:\d{2}\.\d{3} - handshake transport/.test(raw));
  const phase=text(await visible('connection.progress.logs'));
  assert(/\d{2}:\d{2}:\d{2}\.\d{3} - TCP/.test(phase)&&!phase.includes('+0.'));
  await h.sleep(150);
  assert((await h.screenshot(join(out,`native-${w}.png`))).ok);
  await writeFile(join(out,`native-${w}.json`),JSON.stringify({progress:await h.query('connection.progress'),bubble:await h.query('connection.progress.logs.raw-popover')},null,2));
  await h.mouseMove(ordinary.rect.x+40,ordinary.rect.y+8);
  await absent('connection.progress.logs.raw-popover');
  await h.mouseMove(failed.rect.x+40,failed.rect.y+8);
  await visible('connection.progress.logs.raw-popover');
  await h.key('escape');
  await absent('connection.progress.logs.raw-popover');
  await visible('connection.progress');
  await h.mouseMove(20,80);
 }
 checks.push('attempt 2 running: hovering the failed row of attempt 1 opens the 520-wide raw bubble inside the viewport at 1280 and 860; ordinary rows open nothing; leaving the row and Escape close the bubble only');

 stage='collapsing the log closes the bubble';
 const {failed}=await logRows();
 await h.mouseMove(failed.rect.x+40,failed.rect.y+8);
 await visible('connection.progress.logs.raw-popover');
 await h.clickTestId('connection.progress.logs.toggle');
 await absent('connection.progress.logs.raw-popover');
 await absent('connection.progress.logs.failure');
 await visible('connection.progress');
 checks.push('collapsing the connection log dismisses the bubble with its row');
 await writeFile(join(out,'report.json'),JSON.stringify({status:'passed',checks,scope:'Production progress card and failure view with local journal facts; no SSH is opened.'},null,2));
 console.log(JSON.stringify({status:'passed',checks}));
}catch(error){
 await h.screenshot(join(out,'failure.png')).catch(()=>{});
 await writeFile(join(out,'failure-tree.json'),JSON.stringify(await h.tree().catch(()=>null),null,2)).catch(()=>{});
 await writeFile(join(out,'report.json'),JSON.stringify({status:'failed',stage,error:String((error as any)?.stack??error),checks},null,2));
 console.error(stage,error);process.exitCode=1;
}finally{app.kill('SIGTERM');await ended;await log.close();await rm(rpc,{recursive:true,force:true});}
