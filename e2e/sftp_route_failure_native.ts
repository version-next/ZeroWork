/** Production saved-route SFTP rejection must be visible without opening a live file workspace.
 * Endpoints use reserved invalid names: the supported failure occurs before network I/O.
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdir,mkdtemp,readFile,writeFile,copyFile,open,rm,realpath} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {createHash} from 'node:crypto';
import {query,clickAt,resizeWindow,screenshot,waitFor,waitForServerReady,sleep} from '../zig-out/share/zenit/harness/client.ts';
const binary=resolve(process.env.ZW_ROUTE_BINARY!),out=resolve(process.argv[2]??'/tmp/zw-sftp-route-failure');
const iso=await realpath(await mkdtemp(join(tmpdir(),'zw-route-rejection-')));
const data=join(iso,'data'),rpc=join(iso,'rpc');await mkdir(data);await mkdir(rpc);await mkdir(out,{recursive:true});
const executable=join(iso,'zerowork');await copyFile(binary,executable);await copyFile(join(binary,'..','zw_ipc.so'),join(iso,'zw_ipc.so'));
await writeFile(join(data,'hosts.toml'),`[registry]
schema_version=2
revision=1
next_connection_id=3
next_group_id=1
[[hosts]]
connection_id=1
revision=1
protocol="ssh"
auth_mode="password"
name="Fixture jump"
host="jump.invalid"
port=22
user="fixture"
[[hosts]]
connection_id=2
revision=1
protocol="sftp"
auth_mode="password"
name="Route SFTP rejection"
host="target.invalid"
port=22
user="fixture"
route=[1]
`,{mode:0o600});
await writeFile(join(data,'config.toml'),'[updates]\nauto_check=false\n',{mode:0o600});
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const env={...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1',ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0'};
const log=await open(join(out,'app.log'),'w'),app=spawn(executable,[],{cwd:process.cwd(),env,stdio:['ignore',log.fd,log.fd]});
const ended=new Promise<void>(r=>app.once('close',()=>r()));
const report:any={status:'running',binary_sha256:createHash('sha256').update(await readFile(binary)).digest('hex'),checks:[],screenshots:[]};
const shown=(n:any)=>n?.rect&&n.hidden!==true&&n.visible!==false&&(n.effective_opacity??1)>0&&n.rect.w>0&&n.rect.h>0;
const flat=(n:any):any[]=>shown(n)?[n,...(n.children??[]).flatMap(flat)]:[];
const text=(n:any)=>flat(n).map(x=>x.text??'').join('\n');
try{
 await waitForServerReady();assert.equal(Number(JSON.parse(await readFile(join(rpc,'owner.json'),'utf8')).pid),app.pid);
 await resizeWindow(1440,900);
 const row=await waitFor(async()=>(await query('sidebar.host')).find(n=>shown(n)&&text(n).includes('Route SFTP rejection'))??null,15000);
 assert((await clickAt(row.rect.x+row.rect.w/2,row.rect.y+row.rect.h/2)).ok);
 // Selecting a host only reveals its connection action. Use that same row's button to attempt the saved route.
 const connect=await waitFor(async()=>{
  const target=(await query('sidebar.host')).find(n=>shown(n)&&text(n).includes('Route SFTP rejection'));
  return flat(target).find(n=>n.test_id==='sidebar.host.connect_button'&&n.focusable)??null;
 },15000);
 assert((await clickAt(connect.rect.x+connect.rect.w/2,connect.rect.y+connect.rect.h/2)).ok);
 const failure=await waitFor(async()=>(await query('connection.progress.failure')).find(shown)??null,15000);
 assert.match(text(failure),/Route SFTP rejection/);
 assert.match(text(failure),/target\.invalid:22/);
 assert.match(text(failure),/配置检查/);
 assert.match(text(failure),/ProxyJumpTransportUnavailable/);
 assert(!(await query('files.workspace')).some(shown),'No live file workspace is opened');
 assert(!(await query('plugin.challenge.title')).some(shown),'The route is rejected before network authentication');
 report.checks.push('Saved SFTP route shows a configuration failure with the selected endpoint and the explicit unsupported-route code, before a file workspace or authentication');
 for(const [w,h]of[[1440,900],[860,480]]){await resizeWindow(w,h);const nodes=await query('connection.progress.failure');assert(nodes.some(shown));await writeFile(join(out,`error-${w}.json`),JSON.stringify(nodes,null,2));assert((await screenshot(join(out,`error-${w}.png`))).ok);report.screenshots.push(`error-${w}.png`);}
 report.status='passed';
}catch(error){report.status='failed';report.error=String(error);try{await writeFile(join(out,'failure-tree.json'),JSON.stringify(await query('sidebar.host'),null,2));await screenshot(join(out,'failure.png'));}catch{}}
finally{app.kill('SIGTERM');await Promise.race([ended,sleep(2000)]);if(app.exitCode===null&&app.signalCode===null){app.kill('SIGKILL');await ended;}await log.close();await rm(iso,{recursive:true,force:true});await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report));}
if(report.status!=='passed')process.exitCode=1;
