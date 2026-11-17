/**
 * Window teardown with a live Local terminal whose search bar was opened (teardown-guard).
 *
 * Regression: closing the window disposed the Cx scope tree children-first, so the search bar's
 * scope was gone before the root-scope cleanup shut the Local session down; that shutdown unbound
 * the terminal and repainted the search bar through a disposed signal (panic "Signal(bool) used
 * after its scope was disposed"). Once the order was fixed the same shutdown spun forever: the
 * Local worker is only joined by the application drain, which no longer ran.
 *
 * Steps: isolated HOME / CFFIXED_USER_HOME / TMPDIR / ZEROWORK_DATA_DIR (0700), updates off;
 * open 本地终端, wait for the shell, ⌘F, type a query that matches; then the normal Quit route
 * (POST /quit, accepting any close confirmation). The app must exit 0 on its own, without a panic
 * in its log; it is never killed on the success path.
 *
 * Usage: node e2e/terminal_search_teardown_native.ts <zerowork binary (test-mode)> <evidence dir>
 * No network access is needed.
 */
// Refuses non-test-mode ZeroWork binaries before child_process starts them; checked up front below too.
// @ts-ignore -- plain ESM helper
import {assertTestModeBinary} from './regression/build_mode_guard.mjs';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {chmod,mkdir,mkdtemp,open,readFile,realpath,rm,writeFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import * as h from '../vendor/zenit/e2e/client.ts';

const [binaryArg,outArg]=process.argv.slice(2);
if(!binaryArg||!outArg)throw new Error('usage: terminal_search_teardown_native.ts <binary> <out>');
const binary=assertTestModeBinary(resolve(binaryArg)),out=resolve(outArg);await mkdir(out,{recursive:true});

const shown=(n:any)=>n&&n.visible!==false&&n.rect?.w>0&&n.rect?.h>0&&(n.effective_opacity??1)>0;
const node=async(id:string,ms=15000)=>h.waitFor(async()=>(await h.query(id)).find(shown)??null,ms);
const click=async(id:string)=>{const n:any=await node(id);assert((await h.clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok,id);};

const home=await realpath(await mkdtemp('/private/tmp/zw-search-teardown-'));await chmod(home,0o700);
const tmp=join(home,'tmp'),data=join(home,'data'),rpc=join(home,'rpc'),zdot=join(home,'zdot');
for(const d of [tmp,data,rpc,zdot])await mkdir(d,{mode:0o700});
await writeFile(join(data,'config.toml'),'[meta]\nconfig_revision=1\n[updates]\nauto_check=false\n',{mode:0o600});
await writeFile(join(zdot,'.zshrc'),'PS1="e2e %# "\nunsetopt BEEP 2>/dev/null\n');
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const logPath=join(out,'app.log'),log=await open(logPath,'w');
const app=spawn(binary,[],{env:{PATH:'/usr/bin:/bin:/usr/sbin:/sbin',HOME:home,CFFIXED_USER_HOME:home,TMPDIR:tmp+'/',ZDOTDIR:zdot,ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1',ZENIT_E2E_ISOLATE_KEYBOARD:'1',SSH_AUTH_SOCK:''},stdio:['ignore',log.fd,log.fd]});
const ended=new Promise<void>(r=>app.once('close',()=>r()));
const report:any={status:'running',checks:[] as string[]};
try{
 await h.waitForServerReady(30000);await h.resizeWindow(1200,800);
 await click('workspace.empty.local');
 await node('tabs.title');await node('terminal.surface');
 await h.type_('echo teardown-needle\n');await h.sleep(1200);
 await click('terminal.surface');
 assert((await h.key('f',{cmd:true})).ok);await node('terminal.search');await node('terminal.search.query');
 await h.type_('teardown-needle');
 const count=await h.waitFor(async()=>{const n:any=(await h.query('terminal.search.count')).find(shown);const t=n?.text??n?.label??'';return /^[1-9]\d*\/\d+$/.test(t)?t:null;},10000);
 report.checks.push(`local terminal search open with matches (${count})`);
 await h.screenshot(join(out,'search-open.png')).catch(()=>{});

 const at=performance.now();assert((await h.request('POST','/quit')).ok);report.close_confirmations=[] as string[];let unbound=false;
 while(app.exitCode===null&&app.signalCode===null&&performance.now()-at<20000){
  if(unbound){await Promise.race([ended,h.sleep(100)]);continue;}
  try{for(const id of ['local.close.accept','session.close.accept','groups.close.accept']){const nodes=await h.query(id);if(!Array.isArray(nodes)){unbound=true;break;}if(nodes.some(shown)){report.close_confirmations.push(id);await click(id);}}}catch{unbound=true;}
  if(app.exitCode===null&&app.signalCode===null)await h.sleep(100);
 }
 await Promise.race([ended,h.sleep(1000)]);
 report.quit={exit_code:app.exitCode,signal:app.signalCode,elapsed_ms:Math.round(performance.now()-at)};
 assert.equal(app.signalCode,null,'the app must not die from a signal (crash or kill) during teardown');
 assert.equal(app.exitCode,0,'normal Quit with a live Local terminal and its search bar must exit 0');
 const text=await readFile(logPath,'utf8');
 assert(!/panic|used after its scope was disposed|Segmentation fault/.test(text),'teardown panicked (see app.log)');
 report.checks.push('normal Quit tears the window down with the Local session and search bar alive: exit 0, no panic');
 report.status='passed';
}catch(e){report.status='failed';report.error=String((e as any)?.stack??e);process.exitCode=1;}
finally{
 if(app.exitCode===null&&app.signalCode===null){report.forced=true;app.kill('SIGTERM');await Promise.race([ended,h.sleep(5000)]);}
 await log.close();await rm(home,{recursive:true,force:true});
 await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));
 console.log(JSON.stringify({status:report.status,checks:report.checks,quit:report.quit,error:report.error}));
}
