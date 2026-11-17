/** Actual application + owned loopback SSH PTY/SFTP: every builtin's editing keys, parameter / path Tab completion,
 * an inline @dl into the configured download directory (no system chooser: `[transfer] download_dir`), shell input
 * during and after the download, the transfer panel and the task details popover.
 * The app and SSH peer always use disposable data, ports, and directories.
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdir,mkdtemp,realpath,copyFile,readFile,writeFile,open,readdir,rm} from 'node:fs/promises';
import {join,resolve,dirname} from 'node:path';
import {tmpdir} from 'node:os';
import {createHash} from 'node:crypto';
import * as h from '../zig-out/share/zenit/harness/client.ts';
const binary=resolve(process.argv[2]),out=resolve(process.argv[3]);await mkdir(out,{recursive:false});
const iso=await realpath(await mkdtemp(join(tmpdir(),'zw-builtin-full-'))),rpc=join(iso,'rpc'),data=join(iso,'data'),download=join(out,'downloads'),remote=join(out,'remote');
await Promise.all([mkdir(rpc),mkdir(data),mkdir(download)]);
const peerLog=await open(join(out,'peer.log'),'w');
assert(process.env.ZW_TEST_PYTHON,'ZW_TEST_PYTHON (audited interpreter with paramiko) is required; a bare python3 is never used');
const peer=spawn(process.env.ZW_TEST_PYTHON,['-I','e2e/builtin_records_ssh_peer.py','--out',join(out,'peer'),'--sftp-root',remote,'--allow-path-completion',...(process.env.ZW_TEST_BASH==='1'?['--plain-bash']:[])],{stdio:['ignore',peerLog.fd,peerLog.fd]});
const peerEnd=new Promise(r=>peer.once('close',r));
const ready=await h.waitFor(async()=>{try{return JSON.parse(await readFile(join(out,'peer','ready.json'),'utf8'))}catch{return null}},15000);
await mkdir(join(remote,'sub'));const payload=Buffer.alloc(6*1024*1024);for(let i=0;i<payload.length;i++)payload[i]=(i*29+17)%251;
await writeFile(join(remote,'sub','payload 中文.bin'),payload);await writeFile(join(remote,'sub','path-one.txt'),'one');await writeFile(join(remote,'sub','path-two.txt'),'two');
await writeFile(join(out,'local-file.txt'),'local-completion');await mkdir(join(remote,'sub','only-dir'));await writeFile(join(remote,'sub','only-dir','nested.bin'),'nested');
await writeFile(join(data,'config.toml'),`[meta]\nconfig_revision=1\n[ui]\ntheme="dark"\nfont_family="Menlo"\nfont_size=14\n[transfer]\ndedicated_connection=false\nshared_pacing_kbps=512\ndownload_dir="${download}"\n`);
await writeFile(join(data,'known_hosts'),ready.known_host);
await writeFile(join(data,'hosts.toml'),`[registry]\nschema_version=2\nrevision=1\nnext_connection_id=2\nnext_group_id=1\n[[hosts]]\nconnection_id=1\nrevision=1\nprotocol="ssh"\nauth_mode="password"\noptions={strict_host_key=true}\nname="Owned full flow"\nhost="127.0.0.1"\nport=${ready.port}\nuser="${ready.user}"\nauth={password="${ready.password}"}\n`);
const bundle=join(out,'Builtin-Full-Flow.app'),mac=join(bundle,'Contents','MacOS');await mkdir(mac,{recursive:true});
await writeFile(join(bundle,'Contents','Info.plist'),`<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>zerowork</string><key>CFBundleIdentifier</key><string>local.zerowork.fullflow.${process.pid}</string><key>CFBundleName</key><string>Builtin Full Flow</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleVersion</key><string>1</string></dict></plist>`);
await copyFile(binary,join(mac,'zerowork'));for(const name of ['zw_ipc.so','zw_execution.so','zw_execution_guard','zw_secret_consume.so'])await copyFile(join(dirname(binary),name),join(mac,name));
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;const log=await open(join(out,'app.log'),'w');
const app=spawn(join(mac,'zerowork'),[],{env:{...process.env,ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1'},stdio:['ignore',log.fd,log.fd]});
const appEnd=new Promise(r=>app.once('close',r));
const report:any={status:'running',pid:app.pid,bundle,rpc,out,binary_sha256:createHash('sha256').update(await readFile(binary)).digest('hex'),checks:[],captures:[],shell:process.env.ZW_TEST_BASH==='1'?'bash without OSC 133':'zsh with OSC 133',transfer:{dedicated_connection:false,pacing_kbps:512,payload_bytes:payload.length,source:join(remote,'sub','payload 中文.bin'),destination:join(download,'payload 中文.bin'),source_sha256:createHash('sha256').update(payload).digest('hex')}};
await writeFile(join(out,'session.json'),JSON.stringify(report,null,2));
const shown=(n:any)=>n&&n.rect?.w>0&&n.rect.h>0&&n.hidden!==true&&n.visible!==false&&(n.effective_opacity??1)>0;
const text=(n:any):string=>(n.text??'')+(n.children??[]).map(text).join('');
const visible=async(id:string)=>h.waitFor(async()=>(await h.query(id)).find(shown)||null,12000);
async function click(id:string){
 let n:any;
 if(id==='transfer.window.close'){
  const panels=(await h.query('transfer.manager')).filter(shown);
  function find(node:any):any{return node.test_id===id?node:(node.children??[]).map(find).find(Boolean)}
  n=panels.map(find).find(shown);
 }
 n??=await visible(id);assert((await h.clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok)
}
// 面板契约（e2e/README.md「面板契约」，overlay-focus）：关闭弹层后焦点还给触发按钮；要回终端打字由用户点终端。
// 旧脚本假定关闭后焦点直接回终端——那样打字的空格会激活仍有焦点的触发按钮、把面板重新打开。
async function focusReturnsTo(id:string){await h.waitFor(async()=>(await h.focused())?.test_id===id||null,5000).catch(async()=>{throw new Error('Closing the panel returns focus to its trigger '+id+'; focused '+JSON.stringify(await h.focused()))})}
async function type(s:string){assert((await h.type_(s)).ok)}
async function key(s:string,mods?:any){assert((await h.key(s,mods)).ok)}
async function draft(){return (await h.query('terminal.command.input')).filter(shown).map(text).join('')}
async function expectDraft(s:string){await h.waitFor(async()=>(await draft())===s||null,10000)}
async function outputs(){return (await h.query('terminal.command.output')).filter(shown).map(text).join('\n').replaceAll('✓','')}
async function capture(name:string){assert((await h.screenshot(join(out,name+'.png'))).ok);const tree:any={};for(const id of ['terminal.command.input','terminal.command.record','terminal.command.output','terminal.surface','transfer.manager','transfer.task.status','transfer.task.rate','transfer.window.close','transfer.task.detail_popup'])tree[id]=await h.query(id);await writeFile(join(out,name+'.json'),JSON.stringify(tree,null,2));report.captures.push(name)}
function check(name:string){report.checks.push(name);console.log(name)}
async function begin(name:string){await type('@');await visible('terminal.commands');await type(name);await key('tab');await h.waitFor(async()=>(await draft()).startsWith('@'+name)||null);}
async function cancel(){await key('escape');await h.waitFor(async()=>(await draft())===''||null)}
async function shell(s:string,marker:string){await type(s);await key('return');await h.waitFor(async()=>{const bytes=Buffer.concat(await Promise.all((await readdir(join(out,'peer'))).filter(n=>n.startsWith('received-')).map(n=>readFile(join(out,'peer',n)))));return bytes.includes(Buffer.from(marker))||null},30000)}
try{
 await h.waitForServerReady();assert.equal(Number(JSON.parse(await readFile(join(rpc,'owner.json'),'utf8')).pid),app.pid);await h.resizeWindow(1280,820);
 const host=await visible('sidebar.host');await h.mouseMove(host.rect.x+host.rect.w-22,host.rect.y+host.rect.h/2);await click('sidebar.host.connect');
 await h.waitFor(async()=>(await h.query('workspace.pane')).some(n=>text(n).includes('sshrecords'))||null,30000);await click('terminal.surface');
 await shell(`cd '${remote}/sub'`,remote+'/sub');
 for(const name of ['up','dl','ai','new','dup','grp','pin','sync','ts','history','log','socks','theme','shell','help','dots']){
  await begin(name);await type(' alpha 中文 tail');const value=await draft();assert(value.endsWith(' alpha 中文 tail'));
  await key('w',{ctrl:true});await expectDraft(value.slice(0,-4));
  await key('a',{ctrl:true});await type('X');await expectDraft('X'+value.slice(0,-4));
  await key('e',{ctrl:true});await type('Y');await key('b',{ctrl:true});await key('d',{ctrl:true});await expectDraft('X'+value.slice(0,-4));
  await key('a',{ctrl:true});await key('f',{ctrl:true});await key('k',{ctrl:true});await expectDraft('X');
  await key('u',{ctrl:true});await expectDraft('');await cancel();
  // Type directly into the initial command palette, without adopting first.
  await type('@'+name+' alpha 中文 tail');await key('w',{ctrl:true});await expectDraft('@'+name+' alpha 中文 ');
  await key('delete',{alt:true});await expectDraft('@'+name+' alpha ');
  await key('h',{ctrl:true});await expectDraft('@'+name+' alpha');
  await key('left',{alt:true});await type('X');await expectDraft('@'+name+' Xalpha');
  await key('right',{alt:true});await type('Y');await expectDraft('@'+name+' XalphaY');
  await key('home');await key('forward_delete');await expectDraft(name+' XalphaY');
  await key('end');await key('delete');await expectDraft(name+' Xalpha');
  await key('c',{ctrl:true});await expectDraft('');check('keyboard:'+name);
 }
 for(const [name,prefix,expected] of [['ts','of','off'],['history','of','off'],['sync','o','on'],['socks','of','off'],['shell','a','attach'],['new','Owned','"Owned full flow"'],['grp','lea','leave']]){
  await begin(name);if(!(await draft()).endsWith(' '))await type(' ');await type(prefix);await key('tab');await expectDraft('@'+name+' '+expected);await cancel();check('parameter-tab:'+name);
 }
 // 18a4b06a：@theme 只打开 设置 › 外观，主题名补全已删除——Tab 不改草稿（也不发给远端，见末尾的输入审计）。
 await begin('theme');if(!(await draft()).endsWith(' '))await type(' ');await type('dar');await expectDraft('@theme dar');await key('tab');
 {const until=Date.now()+500;while(Date.now()<until){assert.equal(await draft(),'@theme dar','@theme has no parameter completion (18a4b06a)');await h.sleep(80)}}
 await cancel();check('parameter-tab:theme-has-no-candidates');
 await begin('up');await type(' '+out+'/local-fi');await key('tab');await expectDraft('@up "'+out+'/local-file.txt"');await cancel();check('parameter-tab:up-local');
 await type('@dl path-');await key('tab',{shift:true});await expectDraft('@dl "path-two.txt"');await key('tab');await expectDraft('@dl "path-one.txt"');await cancel();check('remote-tab-and-shift-tab-cycle');
 await type('@dl only');await key('tab');await expectDraft('@dl "only-dir/"');await type('nest');await key('tab');await expectDraft('@dl "only-dir/nested.bin"');await cancel();check('remote-tab-descends-directory');
 await type('@dl pay');await key('tab');await expectDraft('@dl "payload 中文.bin"');check('parameter-tab:dl-remote');
 await capture('01-completed-remote-path');
 // @dl 让用户选保存位置（transfer_host.zig runCommandPicker → 系统选目录对话框；取消时“已取消选择，未添加传输任务”）。
 // test-mode 的对话框注入（platform/test_dialog_injection.zig，运行器给每个条目一个空的 ZEROWORK_E2E_DIALOG_DIR）：
 // 队列里放下载目录 = 用户选中它；requests.jsonl 记录恰好一次 pick_folder 请求。
 const dialogDir=process.env.ZEROWORK_E2E_DIALOG_DIR;assert(dialogDir,'ZEROWORK_E2E_DIALOG_DIR (test-mode dialog injection) is required: run through e2e/regression/run.ts');
 await writeFile(join(dialogDir,'queue'),download+'\n');
 await key('return');
 await h.waitFor(async()=>(outputs()).then(s=>s.includes('已加入下载队列')||null),120000);
 await capture('02-download-started');check('inline-download-queue-result');
 const requests=(await readFile(join(dialogDir,'requests.jsonl'),'utf8')).trim().split('\n').map(l=>JSON.parse(l));
 assert.equal(requests.length,1,'@dl asks for the destination exactly once: '+JSON.stringify(requests));assert.equal(requests[0].kind,'pick_folder');assert.equal(requests[0].answer,download);check('download-destination-picked-once');
 for(let i=0;i<4;i++){
  const marker='DURING_'+i;const receipt=join(remote,'during-'+i);await type(`printf ${marker} > '${receipt}'`);await key('return');await h.waitFor(async()=>{try{return (await readFile(receipt,'utf8'))===marker||null}catch{return null}},5000);
 }
 check('four-shell-commands-during-download');
 await click('toolbar.transfers');await h.waitFor(async()=>(await h.query('transfer.task.rate')).some(n=>shown(n)&&/[1-9]/.test(text(n)))||null,15000);await capture('03-download-live-progress');
 const beforeProgress=JSON.stringify(await h.query('transfer.task.progress'));
 await h.waitFor(async()=>JSON.stringify(await h.query('transfer.task.progress'))!==beforeProgress||null,5000).catch(()=>{throw new Error('Visible transfer progress changes during download')});check('changing-visible-progress-and-nonzero-rate');
 await click('transfer.window.close');await h.waitFor(async()=>!(await h.query('transfer.manager')).some(shown)||null,5000);await focusReturnsTo('toolbar.transfers');await click('terminal.surface');
 const result=join(download,'payload 中文.bin');await h.waitFor(async()=>{try{return createHash('sha256').update(await readFile(result)).digest('hex')===createHash('sha256').update(payload).digest('hex')||null}catch{return null}},60000);
 report.transfer.destination_sha256=createHash('sha256').update(await readFile(result)).digest('hex');
 for(let i=0;i<3;i++){const file=join(remote,'after-'+i);await type(`printf AFTER_${i} > '${file}'`);await key('return');await h.waitFor(async()=>{try{return (await readFile(file,'utf8'))==='AFTER_'+i||null}catch{return null}},5000)}
 await begin('ts');await type(' on');await key('return');await h.waitFor(async()=>(outputs()).then(s=>s.includes('已开启时间戳')||null));
 await capture('04-download-finished-terminal-responsive');for(const name of ['three-shell-commands-after-download','builtin-after-download','download-sha256-matches'])check(name);
 // 任务详情现在是任务名上的点击 Popover（transfer_manager_view.zig：Popover trigger = .click，transfer.task.detail_popup；
 // 悬停详情 transfer.task.hover_detail 已删除，同 sftp_v3_native / transfer_controls_native 的契约）：悬停不开；点名称打开，
 // 详情给出真实的本地目标与远程源路径；再点名称关闭，传输面板保持打开。
 await click('toolbar.transfers');await visible('transfer.manager');const card=await visible('transfer.task');const inCard=(id:string)=>{const f=(n:any):any=>n.test_id===id&&shown(n)?n:(n.children??[]).map(f).find(Boolean);return f(card)};
 const name=inCard('transfer.task.name');assert(name,'The task row shows its file name');await h.mouseMove(name.rect.x+20,name.rect.y+name.rect.h/2);
 {const until=Date.now()+650;while(Date.now()<until){assert(!(await h.query('transfer.task.detail_popup')).some(shown),'Hovering the task name does not open its details');await h.sleep(80)}}
 assert((await h.clickAt(name.rect.x+20,name.rect.y+name.rect.h/2)).ok);const detail=await visible('transfer.task.detail_popup');
 assert.equal(text(await visible('transfer.detail.local')),join(download,'payload 中文.bin'),'Details show the actual local destination');
 assert.equal(text(await visible('transfer.detail.remote')),join(remote,'sub','payload 中文.bin'),'Details show the actual remote source');
 const win={w:1280,h:820};assert(detail.rect.x>=0&&detail.rect.y>=0&&detail.rect.x+detail.rect.w<=win.w&&detail.rect.y+detail.rect.h<=win.h,'Details stay inside the window');
 await capture('03a-real-task-detail');assert((await h.clickAt(name.rect.x+20,name.rect.y+name.rect.h/2)).ok);
 await h.waitFor(async()=>!(await h.query('transfer.task.detail_popup')).some(shown)||null,5000);assert((await h.query('transfer.manager')).some(shown),'Closing the details keeps the transfer panel open');check('real-download-task-details-click-popover');
 await click('transfer.window.close');await h.waitFor(async()=>!(await h.query('transfer.manager')).some(shown)||null,5000);
 // 旧的“底栏传输入口 status.transfer → 会话传输托盘 transfer.session”一段已删除：transfer.session 不再是独立面板（04750679，
 // 底栏入口与标题栏共用 transfer.manager），而且旧状态栏在 mist 外壳下被 workspace_chrome.zig retainLegacy 收成 0×0
 // （b319da83 起），status.transfer 在界面上不可见。传输浮窗唯一可见入口是标题栏 toolbar.transfers，下面覆盖它的开关关闭。
 await click('toolbar.transfers');await visible('transfer.manager');await click('toolbar.transfers');await h.waitFor(async()=>!(await h.query('transfer.manager')).some(shown)||null,5000);await focusReturnsTo('toolbar.transfers');await click('terminal.surface');
 const toggleReceipt=join(remote,'after-toggle-close');await type(`printf TOGGLE_OK > '${toggleReceipt}'`);await key('return');await h.waitFor(async()=>{try{return (await readFile(toggleReceipt,'utf8'))==='TOGGLE_OK'||null}catch{return null}},5000);check('toolbar-transfer-toggle-close-keeps-focus-on-toggle-and-terminal-accepts-input');
 const audit=Buffer.concat(await Promise.all((await readdir(join(out,'peer'))).filter(n=>n.startsWith('received-')).map(n=>readFile(join(out,'peer',n))))).toString();
 assert(!/@(?:up|dl|ai|new|dup|grp|pin|sync|ts|history|log|socks|theme|shell|help|dots)\b/.test(audit),'Builtin drafts never reach interactive SSH');check('all-builtin-input-stays-local');
 report.status='passed';
}catch(error){report.status='failed';report.error=String(error);await capture('failure').catch(()=>{});process.exitCode=1}
finally{await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));if(app.exitCode===null)app.kill('SIGTERM');await Promise.race([appEnd,h.sleep(2500)]);if(app.exitCode===null)app.kill('SIGKILL');if(peer.exitCode===null)peer.kill('SIGTERM');await Promise.race([peerEnd,h.sleep(2500)]);await log.close();await peerLog.close();console.log(JSON.stringify(report))}
