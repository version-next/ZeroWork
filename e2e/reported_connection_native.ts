/** Reported connection regressions against an owned loopback SSH + real ZSH PTY. */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import net from 'node:net';
import {spawn} from 'node:child_process';
import {mkdir,mkdtemp,realpath,copyFile,readFile,writeFile,open,readdir,rm} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {createHash} from 'node:crypto';
import {waitForServerReady,waitFor,query,clickAt,key,type_,resizeWindow,screenshot,sleep,scrollAt,mouseDown,mouseMove,mouseUp} from '../zig-out/share/zenit/harness/client.ts';
const out=resolve(process.argv[2]),source=resolve(process.argv[3]);await mkdir(out,{recursive:false});
const iso=await realpath(await mkdtemp(join(tmpdir(),'zw-builtin-records-'))),rpc=join(iso,'rpc'),data=join(iso,'data'),shell=join(iso,'shell');
// Always remove this run's sandbox, including setup and reporting failures.
try {
await Promise.all([mkdir(rpc),mkdir(data),mkdir(shell)]);
await writeFile(join(shell,'.zshrc'),"bindkey -e\nPS1='records%# '\n");
await writeFile(join(data,'config.toml'),'[meta]\nconfig_revision=1\n[ui]\ntheme="dark"\nfont_family="Menlo"\nfont_size=14\n');
await copyFile(source,join(iso,'zerowork'));await copyFile(join(source,'..','zw_ipc.so'),join(iso,'zw_ipc.so'));
const peerLog=await open(join(out,'peer.log'),'w');const peerOut=join(out,'peer');assert(process.env.ZW_TEST_PYTHON,'ZW_TEST_PYTHON (audited interpreter with paramiko) is required; a bare python3 is never used');const peer=spawn(process.env.ZW_TEST_PYTHON,['-I','e2e/builtin_records_ssh_peer.py','--out',peerOut],{stdio:['ignore',peerLog.fd,peerLog.fd]});const peerEnded=new Promise(r=>peer.once('close',r));
const ready=await waitFor(async()=>{try{return JSON.parse(await readFile(join(peerOut,'ready.json'),'utf8'))}catch{return null}},15000);
await writeFile(join(data,'known_hosts'),ready.known_host);
await writeFile(join(data,'hosts.toml'),`[registry]\nschema_version=2\nrevision=1\nnext_connection_id=2\nnext_group_id=1\n[[hosts]]\nconnection_id=1\nrevision=1\nprotocol="ssh"\nauth_mode="password"\noptions={strict_host_key=true}\nname="Owned records SSH"\ngroup="QA hosts"\nhost="127.0.0.1"\nport=${ready.port}\nuser="${ready.user}"\nauth={password="${ready.password}"}\n`);
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;const log=await open(join(out,'app.log'),'w');const app=spawn(join(iso,'zerowork'),[],{env:{...process.env,ZDOTDIR:shell,ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1'},stdio:['ignore',log.fd,log.fd]});const ended=new Promise(r=>app.once('close',r));
const report:any={status:'running',pid:app.pid,isolated:iso,sha256:createHash('sha256').update(await readFile(source)).digest('hex'),checks:[],captures:[],limits:['Public synthetic Harness on actual Metal window; no physical CUA/IME/VoiceOver acceptance.','The owned loopback SSH peer runs an actual ZSH PTY; no external host is accessed. Physical CUA/IME/VoiceOver remain separate.']};
const flat=(n:any):any[]=>[n,...(n.children??[]).flatMap(flat)];
const content=(n:any):string=>!shown(n)?'':(n.text??'')+(n.children??[]).map(content).join('');
const shown=(n:any)=>n&&n.hidden!==true&&n.visible!==false&&(n.effective_opacity??1)>0&&n.rect?.w>0&&n.rect?.h>0;
const vis=(id:string)=>waitFor(async()=>(await query(id)).find(shown)??null,12000),hidden=(id:string)=>waitFor(async()=>!(await query(id)).some(shown)||null,12000);
async function click(id:string){const n=await vis(id);assert((await clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok);await sleep(160)}
async function press(name:string,mods?:any){assert((await key(name,mods)).ok)}
async function type(text:string){assert((await type_(text)).ok)}
async function capture(name:string){await sleep(180);assert((await screenshot(join(out,name+'.png'))).ok);report.captures.push(name)}
async function palette(){await type('@');await vis('terminal.commands')}
async function command(value:string){await palette();await type(value);await press('right');await hidden('terminal.commands');await press('return');await sleep(350)}
async function outputs(){return (await query('terminal.command.output')).filter(shown).map(content).join('\n')}
async function records(){return (await query('terminal.command.record')).filter(shown).map(content)}
try{
 await waitForServerReady(60000);await resizeWindow(1440,900);
 // 侧栏契约（design-r3 A2，fe28ab5b；sidebar_view.zig HostRow.onEvent）：单击主机行只选中，重复点击不连接；
 // 选中行行尾的原生“连接”按钮（sidebar.host.connect_button）或 Return 才发起连接。
 await click('sidebar.host');await click('sidebar.host.connect_button');await waitFor(async()=>content(await vis('workspace.pane')).includes('sshrecords')||null,30000);
 await click('status.connection.forward');await click('socks.info.config');await vis('socks.config');const probe=net.createServer();await new Promise<void>(r=>probe.listen(0,'127.0.0.1',r));const socksPort=(probe.address()as net.AddressInfo).port;await new Promise<void>(r=>probe.close(()=>r()));await click('socks.config.port');await key('a',{cmd:true});await type(String(socksPort));await click('socks.config.save');await hidden('socks.config');const saved=await readFile(join(data,'hosts.toml'),'utf8');assert(saved.includes('[[groups]]'));assert(saved.includes('password_ref')&&!saved.includes(ready.password),'The fixture password is kept as a credential reference, never rewritten as plaintext');assert(saved.includes('QA hosts'));assert(saved.includes('socks_enabled = true'));report.checks.push('Saving forwarding for a grouped host preserves durable asset groups and succeeds');await capture('01-forwarding-saved');await click('status.connection.forward');await click('socks.info.control');await waitFor(async()=>content(await vis('socks.info.status')).includes('监听中')||null,12000);const socket=net.createConnection({host:'127.0.0.1',port:socksPort});await new Promise<void>((r,j)=>{socket.once('connect',r);socket.once('error',j)});const greeting=new Promise<Buffer>((r,j)=>{socket.once('data',r);socket.once('error',j);socket.setTimeout(5000,()=>j(new Error('SOCKS greeting timeout')))});socket.write(Buffer.from([5,1,0]));assert.deepEqual(await greeting,Buffer.from([5,0]));socket.destroy();await click('socks.info.control');await waitFor(async()=>content(await vis('socks.info.status')).includes('未开启')||null,12000);await press('escape');report.checks.push('Saved SOCKS rule starts a real listener, completes SOCKS5 negotiation, and stops');
 for(let i=0;i<3;i++){await click('status.connection.chain');await vis('connection.details');await click('connection.details.sample');await sleep(250);await press('escape');await hidden('connection.details');}report.checks.push('Chain details reopen three times after RTT testing without stale view failure');await capture('02-chain-reopen');
 const terminal=await vis('terminal.input');await clickAt(terminal.rect.x+80,terminal.rect.y+80);await command('grp SSH-QA');await vis('groups.pane.header');await command('new');
 // 窗格头部（pane_header.yix，150a83a4 起分屏成员与单会话共用）：连接状态是标题后的圆点 groups.pane.status_dot，
 // 颜色 = status_tone.dot(connection_presenter.present(phase).tone)，与页签圆点 tabs.connection.state 同一映射
 // （已连接 = ok 绿，连接中 / 认证中 = warn 琥珀，失败 / 断开 = danger 红，未连接 = 灰）；groups.pane.status 现在是
 // 右侧的路径 / 尺寸文字（如 “65 × 38”）在首个终端帧到达后替换“已连接”。
 const rgba=(n:any)=>String(n.bg_rgba??'').split(',').map(Number);const okTone=(n:any)=>{const [r,g,b,a]=rgba(n);return a===255&&g>r&&g>b};
 await waitFor(async()=>(await query('groups.pane.header')).filter(shown).length===2||null,20000);
 await waitFor(async()=>{const dots=(await query('groups.pane.status_dot')).filter(shown);return dots.length===2&&dots.every(okTone)||null},20000);
 // 主机保存了密码（加载时迁移成 password_ref）：同一主机的新会话直接复用，不再弹认证框
 // （与 connection_credentials_native 的“New session reuses credentials without a second prompt”同一契约）。
 assert(!(await query('plugin.challenge.modal')).some(shown),'A new session of a host with a saved password must not prompt again');
 const dots=(await query('groups.pane.status_dot')).filter(shown);assert.equal(dots[0].bg_rgba,dots[1].bg_rgba,'Both members show the same connected tone');
 const tabs=flat(await vis('tabs.strip')).filter(n=>/^tabs\.tab\.\d+$/.test(n.test_id??'')&&shown(n)).map(n=>{const parts=flat(n);return {id:n.test_id,title:content(parts.find(p=>p.test_id==='tabs.title')),group:parts.some(p=>p.test_id==='groups.tab.count'),dot:parts.find(p=>p.test_id==='tabs.connection.state')?.bg_rgba}});
 const sessionTabs=tabs.filter(t=>!t.group);assert(sessionTabs.length>=1,'A session tab is present: '+JSON.stringify(tabs));
 // 组页签（groups.tab.count）不参与：它不是会话，tabConnectionColor 对组 id 取不到页签，恒为“已结束”的灰点（待用户判定，见回报）。
 sessionTabs.forEach(t=>assert.equal(t.dot,dots[0].bg_rgba,'A connected session tab dot and the pane header dots share one phase → tone mapping: '+JSON.stringify(tabs)));
 const sizes=await waitFor(async()=>{
   const metas=(await query('groups.pane.status')).filter(shown).map(content);
   return metas.length===2&&metas.every(value=>/(?:^| · )[1-9]\d* × [1-9]\d*$/.test(value))?metas:null;
 },10000);
 report.member_sizes=sizes;
 // workspace.pane 是整个终端区（main_window.zig），不是单个窗格：逐个成员的终端表面各自显示远端提示符，
 // 对端也确实开了两个交互 Shell（received-1 / received-2）。
 const surfaces=(await query('terminal.surface')).filter(shown);assert.equal(surfaces.length,2,'Both members mount a terminal surface');surfaces.forEach(n=>assert(content(n).includes('sshrecords'),'Each member shows its own remote prompt'));
 assert.deepEqual((await readdir(peerOut)).filter(n=>/^received-\d+\.bin$/.test(n)).sort(),['received-1.bin','received-2.bin'],'Both members run a real remote shell on the peer');
 report.member_dots=dots.map(n=>n.bg_rgba);report.tabs=tabs;
 report.checks.push('A new SSH session created inside a group connects without a second prompt; both member dots show the connected tone shared with the tab dots');await capture('03-ssh-group-online');
 report.status='passed';
}catch(e){report.status='failed';report.error=String(e);await capture('failure').catch(()=>{});process.exitCode=1}
finally{if(app.exitCode===null&&app.signalCode===null){app.kill('SIGTERM');await Promise.race([ended,sleep(3000)]);if(app.exitCode===null&&app.signalCode===null){app.kill('SIGKILL');await ended}}peer.kill('SIGTERM');await Promise.race([peerEnded,sleep(3500)]);await peerLog.close();await log.close();await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));}
console.log(JSON.stringify({status:report.status,checks:report.checks,error:report.error,out}));
} finally {
 await rm(iso,{recursive:true,force:true});
}
