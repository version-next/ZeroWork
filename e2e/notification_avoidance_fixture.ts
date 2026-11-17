/** Real operation failure from an owned loopback HTTP provider.
 * Private app/data/RPC, synthetic Harness input only. Session transfer coverage
 * belongs to the real SFTP upload acceptance, which reuses the same assertion.
 * node e2e/notification_avoidance_fixture.ts --binary PATH --out EMPTY_DIR
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {mkdir,mkdtemp,writeFile,open,readFile,copyFile,realpath,rm} from 'node:fs/promises';
import {spawn} from 'node:child_process';
import {createServer} from 'node:http';
import {createHash} from 'node:crypto';
import {dirname,join,resolve} from 'node:path';
import {waitForServerReady,waitFor,query,clickTestId,sleep,resizeWindow,key,mouseMove,type_,screenshot} from '../zig-out/share/zenit/harness/client.ts';
import {verifyNotificationAvoidance} from './notification_avoidance_native.ts';
import {aiToggleId} from './ai_entry.ts';
const options:Record<string,string>={};
for(let i=2;i<process.argv.length;i+=2){assert(['--binary','--out'].includes(process.argv[i])&&process.argv[i+1]);options[process.argv[i]]=process.argv[i+1];}
assert(options['--binary']&&options['--out']);
const out=resolve(options['--out']);await mkdir(out,{recursive:false});
const base=await realpath(await mkdtemp('/private/tmp/zw-notification-avoidance-')),rpc=join(base,'rpc'),data=join(base,'data');await mkdir(rpc);await mkdir(data);
const requests:Array<{method?:string,url?:string}>=[];
const server=createServer(async(req,res)=>{
 for await(const _ of req){}
 requests.push({method:req.method,url:req.url});
 res.writeHead(400,{'content-type':'application/json'});
 res.end(JSON.stringify({error:{message:'Owned fixture refused this request.'}}));
});
await new Promise<void>(r=>server.listen(0,'127.0.0.1',r));const port=(server.address() as any).port;
await writeFile(join(data,'config.toml'),`[meta]\nconfig_revision=1\n[ui]\ntheme="dark"\n[ai]\ndefault_provider="Fixture"\n[[ai.providers]]\nid="Fixture"\nkind="openai_compat"\nendpoint="http://127.0.0.1:${port}/v1/chat/completions"\nenabled=true\n[[ai.providers.models]]\nname="test-model"\ncontext_window=128000\ndefault=true\n`);
await writeFile(join(data,'hosts.toml'),'');
const source=resolve(options['--binary']),binary=join(out,'zerowork-frozen');await copyFile(source,binary);await copyFile(join(dirname(source),'zw_ipc.so'),join(out,'zw_ipc.so'));
const sha=createHash('sha256').update(await readFile(binary)).digest('hex');
const log=await open(join(out,'app.log'),'w');process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const app=spawn(binary,[],{env:{...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1',ZENIT_DEVTOOLS_HIT_DEBUG:'1'},stdio:['ignore',log.fd,log.fd]});
const ended=new Promise<void>(r=>app.once('close',()=>r()));
const report:any={status:'running',base,rpc,data,binary,binary_sha256:sha,pid:app.pid,synthetic_harness_input:true,real_transfer:false,checks:[],limits:['Session/global upload evidence must also run through the real SFTP fixture.','Synthetic Harness input does not prove physical mouse input.']};
const shown=(n:any)=>n&&n.visible!==false&&n.hidden!==true&&(n.effective_opacity??1)>0&&n.rect?.w>0&&n.rect?.h>0;
async function click(id:string){assert((await clickTestId(id)).ok,id);}
const visible=(id:string)=>waitFor(async()=>(await query(id)).find(shown)??null);
try{
 await waitForServerReady();assert.equal(Number(JSON.parse(await readFile(join(rpc,'owner.json'),'utf8')).pid),app.pid);
 await resizeWindow(1440,900);await click('workspace.empty.local');await visible('terminal.surface');
 await click(await aiToggleId());await visible('ai.prompt');await click('ai.prompt');await type_('Produce one owned diagnostic');await click('ai.send');
 const toast=await visible('notifications.toast.0');
 assert(requests.some(r=>r.method==='POST'&&r.url?.endsWith('/chat/completions')));
 report.requests=requests;
 const title=await visible('notifications.title'),body=await visible('notifications.detail');
 assert.equal(title.text,'AI 请求失败');
 assert(body.text?.includes('HTTP 400')&&body.text.includes('Owned fixture refused this request.'));
 assert(title.rect.y+title.rect.h<=body.rect.y&&body.rect.y+body.rect.h<=toast.rect.y+toast.rect.h);
 report.toast_contract={card:toast.rect,title:title.rect,body:body.rect};
 await writeFile(join(out,'two-line-toast.json'),JSON.stringify(toast,null,2));
 await mouseMove(toast.rect.x+20,toast.rect.y+20);
 await click('toolbar.transfers');await sleep(200);
 report.checks.push(await verifyNotificationAvoidance(out,'global-standard',{width:1440,height:900,operationError:true}));
 const before=(await query('workspace.sidebar')).find(shown)!.rect.w;
 await key('b',{cmd:true});await sleep(200);
 const after=(await query('workspace.sidebar')).find(shown)?.rect.w??0;assert.notEqual(before,after,'sidebar actually changes width');report.sidebar={before,after};
 report.checks.push(await verifyNotificationAvoidance(out,'global-standard-sidebar',{width:1440,height:900,operationError:true}));
 await resizeWindow(860,480);await sleep(250);
 report.checks.push(await verifyNotificationAvoidance(out,'global-minimum',{width:860,height:480,close:true,operationError:true}));
 const logs=await readFile(join(out,'app.log'),'utf8');assert(/pointer_hit=.*test_id=transfer\.window\.close/.test(logs),'actual close hit target in native log');
 report.status='passed';
}catch(e){report.status='failed';report.error=e instanceof Error?e.stack:String(e);await screenshot(join(out,'failure.png')).catch(()=>{});throw e;}
finally{await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));app.kill('SIGTERM');await ended;await log.close();server.closeAllConnections();server.close();await rm(base,{recursive:true,force:true});}
console.log(JSON.stringify({status:report.status,out,binary_sha256:sha}));
