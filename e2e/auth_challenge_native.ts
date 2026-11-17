/** Actual main-app SFTP host-key + password challenge against an owned loopback peer; no transfer, no saved password.
 *
 * The main app's challenge UI is the plugin challenge presenter (`features/connections/auth/host/plugin_challenge_presenter.zig`,
 * test ids `plugin.challenge.*`, payload from `plugins/remote/challenge_bridge.zig`). The retained `auth.challenge.*`
 * view (`auth_challenge_view.zig`, with its eye toggle `auth.challenge.reveal.N`) is only mounted by
 * auth-challenge-preview and is covered by legacy_auth_native; this script no longer drives it.
 *
 * node e2e/auth_challenge_native.ts <zerowork> <out> [dark|light]     (ZW_TEST_PYTHON = audited interpreter with paramiko)
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdir,mkdtemp,open,readFile,rm,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {inflateSync} from 'node:zlib';
import {waitForServerReady,waitFor,query,clickAt,key,type_,resizeWindow,screenshot,sleep,mouseMove} from '../zig-out/share/zenit/harness/client.ts';
const binary=resolve(process.argv[2]),out=resolve(process.argv[3]),theme=process.argv[4]??'dark';
assert(['dark','light'].includes(theme));
assert(process.env.ZW_TEST_PYTHON,'ZW_TEST_PYTHON (audited interpreter with paramiko) is required; a bare python3 is never used');
await mkdir(out,{recursive:true});const isolated=await mkdtemp(join(tmpdir(),'zw-auth-align-')),data=join(isolated,'data'),rpc=join(isolated,'rpc');await mkdir(data);await mkdir(rpc);
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const log=await open(join(out,'app.log'),'w'),peerLog=await open(join(out,'peer.log'),'w'),peerOut=join(out,'peer');
const peer=spawn(process.env.ZW_TEST_PYTHON,['-I',resolve('e2e/sftp_upload_loopback.py'),'--out',peerOut],{stdio:['ignore',peerLog.fd,peerLog.fd]});
const peerEnded=new Promise<void>(r=>peer.once('close',()=>r()));let app:any,ended:any;
const report:any={status:'running',binary,sha256:createHash('sha256').update(await readFile(binary)).digest('hex'),theme,stages:[],checks:[],limits:['Harness synthetic input, no physical keyboard/IME claim','Own loopback host-key + password challenge and read-only SFTP attach; no file transfer or external hosts']};
const shown=(n:any)=>n?.visible!==false&&n?.hidden!==true&&(n?.effective_opacity??1)>0&&n?.rect?.w>0&&n?.rect?.h>0;
const nodes=(n:any):any[]=>!shown(n)?[]:[n,...(n.children??[]).flatMap(nodes)];const text=(n:any)=>nodes(n).map(x=>x.text??'').join(' ');
const within=(inner:any,outer:any)=>inner.x>=outer.x-0.5&&inner.y>=outer.y-0.5&&inner.x+inner.w<=outer.x+outer.w+0.5&&inner.y+inner.h<=outer.y+outer.h+0.5;
async function modal(){return (await query('plugin.challenge.modal')).find(shown);}
async function part(id:string){const m=await modal();return m?nodes(m).find(n=>n.test_id===id):null;}
async function visible(id:string,ms=15000){return waitFor(async()=>(await query(id)).find(shown)??null,ms);}
// Click once the node's rect has been stable for two polls (the modal animates in).
async function click(id:string,inModal=id.startsWith('plugin.challenge.')){let last='',count=0;const n=await waitFor(async()=>{const n=inModal?await part(id):(await query(id)).find(shown);if(!n)return null;const at=JSON.stringify(n.rect);count=at===last?count+1:0;last=at;await sleep(80);return count>=2?n:null;},15000);assert((await clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok);}
// 截图里实际画出来的标题图标颜色（节点的 icon_rgba 只是声明值）：PNG 解码同 button_policy_native。
type Image={width:number,height:number,channels:number,pixels:Buffer};
function paeth(a:number,b:number,c:number){const p=a+b-c,da=Math.abs(p-a),db=Math.abs(p-b),dc=Math.abs(p-c);return da<=db&&da<=dc?a:db<=dc?b:c}
function decodePng(bytes:Buffer):Image{
 assert(bytes.subarray(0,8).equals(Buffer.from('89504e470d0a1a0a','hex')),'Screenshot must be PNG');
 const chunks:Buffer[]=[];let width=0,height=0,channels=0,offset=8,done=false;
 while(offset+12<=bytes.length){const length=bytes.readUInt32BE(offset),kind=bytes.toString('ascii',offset+4,offset+8),data=bytes.subarray(offset+8,offset+8+length);
  if(kind==='IHDR'){width=data.readUInt32BE(0);height=data.readUInt32BE(4);assert.equal(data[8],8);assert(data[9]===6||data[9]===2);channels=data[9]===6?4:3;assert.equal(data[12],0,'Interlaced screenshot unsupported')}
  else if(kind==='IDAT')chunks.push(data);else if(kind==='IEND'){done=true;break}
  offset+=length+12}
 assert(done&&width&&channels&&chunks.length,'Incomplete PNG');
 const rowBytes=width*channels,raw=inflateSync(Buffer.concat(chunks),{maxOutputLength:(rowBytes+1)*height}),pixels=Buffer.alloc(rowBytes*height);
 for(let y=0;y<height;y++){const filter=raw[y*(rowBytes+1)];assert(filter<=4,'Unknown PNG filter '+filter);
  for(let x=0;x<rowBytes;x++){const i=y*rowBytes+x,a=x>=channels?pixels[i-channels]:0,b=y?pixels[i-rowBytes]:0,c=y&&x>=channels?pixels[i-rowBytes-channels]:0;
   pixels[i]=(raw[y*(rowBytes+1)+1+x]+(filter===0?0:filter===1?a:filter===2?b:filter===3?Math.floor((a+b)/2):paeth(a,b,c)))&255}}
 return {width,height,channels,pixels}}
/** The most saturated painted pixel inside `rect` (window points) — the icon's ink, away from anti-aliased edges. */
async function paintedInk(png:string,rect:any,windowWidth:number){const img=decodePng(await readFile(png)),k=img.width/windowWidth;let best=[0,0,0],sat=-1;
 for(let y=Math.floor(rect.y*k);y<Math.ceil((rect.y+rect.h)*k);y++)for(let x=Math.floor(rect.x*k);x<Math.ceil((rect.x+rect.w)*k);x++){const i=(y*img.width+x)*img.channels,px=[img.pixels[i],img.pixels[i+1],img.pixels[i+2]],v=Math.max(...px)-Math.min(...px);if(v>sat){sat=v;best=px}}
 return best}
const distance=(a:number[],b:number[])=>Math.hypot(a[0]-b[0],a[1]-b[1],a[2]-b[2]);
let windowWidth=1440;
// 每种认证标题图标按 plugin_challenge_presenter.zig:210 着色：核对主机密钥 = warn_ink（shield_question），密码 = accent（lock_keyhole）。
// 同一个 presenter 先后展示两种请求时，画面上的图标必须跟着换——只比较节点声明值看不出画面没刷新。
async function iconPainted(name:string){const icon=await part('plugin.challenge.title_icon');assert(icon?.icon_rgba,'Title icon declares its tint');const want=String(icon.icon_rgba).split(',').slice(0,3).map(Number);
 const ink=await paintedInk(join(out,name+'.png'),icon.rect,windowWidth);report.icons=[...(report.icons??[]),{name,declared:want,painted:ink}];
 assert(distance(ink,want)<=48,`${name}: the painted title icon (${ink}) matches its declared tint (${want})`);return want}
async function capture(name:string){
 // 等弹窗入场动画结束（world_transform 缩放回到 1、不透明），截图才是静止画面。
 await waitFor(async()=>{const m=await modal();return m&&(m.effective_opacity??1)>=0.999&&(!m.world_transform||Math.abs(m.world_transform[0]-1)<1e-3)||null},5000);
 const m=await modal();assert(m);await writeFile(join(out,name+'.json'),JSON.stringify(m,null,2));assert((await screenshot(join(out,name+'.png'))).ok);report.stages.push({name,rect:m.rect});}
async function peerState(){return JSON.parse(await readFile(join(peerOut,'state.json'),'utf8'));}
let ready:any,fixture='';
// 侧栏契约（design-r3 A2，fe28ab5b）：单击主机行只选中；选中行行尾的原生“连接”按钮（sidebar.host.connect_button）发起连接。
async function connect(){await click('sidebar.host');await click('sidebar.host.connect_button');}
// 未知主机密钥（challenge_bridge.zig host_key_unknown）：标题“核对主机密钥”，material 给出算法与 SHA256 指纹，来源行带端口；
// 两个动作“仅本次信任”（plugin.challenge.choice.0 = trust_once）/“保存并继续”。本脚本只选“仅本次信任”，所以 known_hosts 不写。
// 文件工作区会为目录列表另开连接，每条连接各自核对一次——同一个指纹，次数有上限。
let trusted=0;
async function trustOnce(m:any){
 assert.equal(nodes(m).find(n=>n.test_id==='plugin.challenge.title')?.text,'核对主机密钥');
 assert(text(m).includes(ready.fingerprint),'The host-key prompt shows the actual SHA256 fingerprint');assert(text(m).includes(':'+ready.port),'The host-key prompt names the actual endpoint port');
 assert(++trusted<=6,'Host-key confirmation repeats without bound');if(trusted===1){await capture('00-host-key');await iconPainted('00-host-key');}
 await click('plugin.challenge.choice.0');
}
async function passwordPrompt(){
 return waitFor(async()=>{
  const m=await modal();if(!m)return null;
  if(nodes(m).some(n=>n.test_id==='plugin.challenge.choice.0'&&n.focusable)){await trustOnce(m);return null;}
  return (await part('plugin.challenge.answer.0'))?m:null;
 },30000);
}
try{
 ready=await waitFor(async()=>{try{return JSON.parse(await readFile(join(peerOut,'ready.json'),'utf8'));}catch{return null;}},15000);
 fixture=`[registry]\nschema_version=2\nrevision=1\nnext_connection_id=2\nnext_group_id=1\n[[hosts]]\nconnection_id=1\nrevision=1\nprotocol="sftp"\nauth_mode="password"\noptions={strict_host_key=true}\nname="Loopback Auth"\nhost="127.0.0.1"\nport=${ready.port}\nuser="${ready.user}"\n`;
 await writeFile(join(data,'hosts.toml'),fixture);await writeFile(join(data,'config.toml'),`[meta]\nconfig_revision=1\n[ui]\ntheme="${theme}"\nfont_family="Menlo"\nfont_size=14\n`);
 app=spawn(binary,[],{env:{...process.env,ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1'},stdio:['ignore',log.fd,log.fd]});ended=new Promise<void>(r=>app.once('close',()=>r()));
 await waitForServerReady(30000);assert.equal(Number(JSON.parse(await readFile(join(rpc,'owner.json'),'utf8')).pid),app.pid);await resizeWindow(1440,900);

 await connect();await passwordPrompt();await capture('01-password-empty');const first=await modal();await iconPainted('01-password-empty');
 // 宽度 = auth_challenge_styles.width(.password) = 430（presenter Modal .width）；高度按内容（fit，最大 视口高 − 16），
 // 密码表单的内容高度不超过 auth_challenge_styles.height(.password) = 380。
 assert.equal(Math.round(first.rect.w),430,'Password dialog is 430 wide');assert(first.rect.h<=380,'Password dialog fits its content within 380: '+first.rect.h);
 assert.equal((await part('plugin.challenge.title'))?.text,'SSH 密码认证');
 // 来源行 = “<显示名> · user@host:port · 第 N 跳”（challenge_bridge.zig:87）。文件路由给最后一跳的显示名是空串
 // （host/file_route_factory.zig:301 option(..., "", ...)），于是退回成主机地址——与 SSH 终端路由（显示保存的主机名）不一致，见回报；这里断言端点与跳数。
 const source=(await part('plugin.challenge.source'))?.text??'';assert(source.endsWith(` · ${ready.user}@127.0.0.1:${ready.port} · 第 1 跳`),'Source names the endpoint and hop: '+source);report.source_line=source;
 // 只有一条凭据说明（challenge_bridge.zig：允许保存密码时“可选择保存密码供下次连接使用；取消会停止本次认证。”）。
 assert.equal((await part('plugin.challenge.detail'))?.text,'可选择保存密码供下次连接使用；取消会停止本次认证。');
 assert.equal(nodes(first).filter(n=>/取消会停止本次/.test(n.text??'')).length,1,'Exactly one credential notice');
 const field=await part('plugin.challenge.answer.0'),remember=await part('plugin.challenge.remember');assert(field&&remember);assert(remember.rect.y>=field.rect.y+field.rect.h,'Save option sits below the field');
 assert(!(await part('plugin.challenge.error')),'No error row before the first answer');
 report.checks.push('430-wide password dialog fits its content; one credential notice; source names host and endpoint');
 await click('plugin.challenge.answer.0');await type_(ready.password);
 assert(!text(await modal()).includes(ready.password),'The password is masked');await capture('02-password-masked');
 report.checks.push('Typed password stays masked (the main-app presenter has no reveal control; the eye toggle belongs to the preview-only auth.challenge view)');
 await click('plugin.challenge.cancel');await waitFor(async()=>!(await modal())||null,10000);
 await waitFor(async()=>(await peerState()).active_connections===0||null,15000);
 // 取消认证后连接进度卡片停在“已取消”终态（connection.progress.*）：标题“连接已取消”、说明“本次链路资源已释放”，
 // 需要用户点“关闭”（connection.progress.dismiss）收起，页签不保留。
 const cancelled=await visible('connection.progress');assert.equal(nodes(cancelled).find(n=>n.test_id==='connection.progress.summary.title')?.text,'连接已取消');
 assert.equal(nodes(cancelled).find(n=>n.test_id==='connection.progress.summary.detail')?.text,'本次链路资源已释放');assert.equal(nodes(cancelled).find(n=>n.test_id==='connection.progress.state')?.text,'已取消');
 assert((await screenshot(join(out,'02b-cancelled.png'))).ok);
 // 进度卡片是会话窗格自己的内容（connection_progress_view.zig:323-325 注释“the host places it over the session's pane”）：
 // 它不能盖住侧栏和标题栏。产品现状：取消后页签已移除，connection.progress.pane 退成整窗 0,0,1440×900，侧栏 / 标题栏被盖住（见回报）。
 {const pane=(await query('connection.progress.pane')).find(shown),area=(await query('workspace.pane')).find(shown);report.cancelled_geometry={pane:pane?.rect,workspace_pane:area?.rect};
  assert(pane&&area&&within(pane.rect,area.rect),'The cancelled progress card stays inside the workspace pane (sidebar and title bar stay visible): '+JSON.stringify(report.cancelled_geometry))}await click('connection.progress.dismiss');await waitFor(async()=>!(await query('connection.progress')).some(shown)||null,10000);
 report.checks.push('Cancel closes the original connection, releases the peer and leaves a dismissible “连接已取消” card');

 trusted=0;await connect();await passwordPrompt();await resizeWindow(860,480);windowWidth=860;
 const compact=await waitFor(async()=>{const m=await modal();return m&&m.rect.y>=0&&m.rect.y+m.rect.h<=480?m:null},10000);await capture('03-password-compact');await iconPainted('03-password-compact');
 for(const id of ['plugin.challenge.answer.0','plugin.challenge.cancel','plugin.challenge.submit']){const n=await part(id);assert(n&&within(n.rect,compact.rect)&&n.rect.y+n.rect.h<=480,'Reachable at 860×480: '+id)}
 report.checks.push('860×480 dialog, field and both actions stay inside the window');
 await click('plugin.challenge.answer.0');await type_(ready.password);await click('plugin.challenge.submit');
 let subsequent=0;
 await waitFor(async()=>{
  if((await query('files.workspace')).some(shown)&&!(await modal()))return true;
  const m=await modal();if(!m)return null;
  if(nodes(m).some(n=>n.test_id==='plugin.challenge.choice.0'&&n.focusable)){await trustOnce(m);return null;}
  if(await part('plugin.challenge.answer.0')){
   // 文件工作区的目录连接是独立的认证：同一主机、同一端点，未勾选保存时再问一次密码。
   assert(++subsequent<=6,'Password prompts repeat without bound');assert(text(m).includes(':'+ready.port));
   await click('plugin.challenge.answer.0');await key('a',{cmd:true});await type_(ready.password);await click('plugin.challenge.submit');
   // 提交后这一问要么关闭，要么换成下一问（新一问的输入框是空的）；同一问不会被提交两次。
   await waitFor(async()=>{const now=await modal();return !now||!(await part('plugin.challenge.answer.0'))||(await inputEmpty())||null},10000);
  }
  return null;
 },45000);assert(!(await modal()));report.prompts={host_key:trusted,password_after_submit:subsequent};
 report.checks.push('Explicit password submit attaches the actual SFTP file workspace');
 const strip=(await query('tabs.strip')).find(shown);const tabs=nodes(strip).filter(n=>/^tabs\.tab\.\d+$/.test(n.test_id??''));assert(tabs.length>=1);const fileTab=tabs.at(-1).test_id;
 // 关闭钮跟随指针出现（tab_strip_view.zig closeShown）：先悬停页签再点它。
 const last=tabs.at(-1);await mouseMove(last.rect.x+last.rect.w/2,last.rect.y+last.rect.h/2);await click(fileTab.replace('tabs.tab.','tabs.close.'),false);
 await waitFor(async()=>(await peerState()).active_connections===0||null,15000);
 const state=await peerState();assert.equal(state.upload,null);assert.equal(state.forbidden_operations.length,0);assert(!state.calls.some((c:any)=>c.operation==='WRITE'));
 assert.equal(await readFile(join(data,'hosts.toml'),'utf8'),fixture,'An unchecked save option leaves hosts.toml untouched (no password_ref)');
 report.peer={connections:state.connections.length,active_connections:state.active_connections,upload:state.upload};
 report.checks.push('Closing the tab releases every connection; no write or transfer; no password or host key saved');report.status='passed';
}catch(e){report.status='failed';report.error=String(e);await screenshot(join(out,'failure.png')).catch(()=>{});process.exitCode=1;}
finally{if(app&&app.exitCode===null&&app.signalCode===null){app.kill('SIGTERM');await Promise.race([ended,sleep(5000)]);}peer.kill('SIGTERM');await peerEnded;await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));await log.close();await peerLog.close();await rm(isolated,{recursive:true,force:true});console.log(JSON.stringify({status:report.status,error:report.error,out}));}
async function inputEmpty(){const n=await part('plugin.challenge.answer.0');return n&&!text(n).trim();}
