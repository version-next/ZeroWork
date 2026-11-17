/** Top toolbar click-only popovers, tab context arbitration and forwarding body.
 * Disposable configuration and owned loopback SSH; no saved hosts are used. */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdir,mkdtemp,realpath,readFile,writeFile,open,rm} from 'node:fs/promises';
import {resolve,join,dirname} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
const python=process.env.ZW_TEST_PYTHON;assert(python,'ZW_TEST_PYTHON (audited Python with paramiko, run with -I) is required');
const binary=resolve(process.argv[2]),out=resolve(process.argv[3]),theme=process.argv[4]??'light';assert(['dark','light'].includes(theme));
const h=await import(pathToFileURL(resolve(dirname(binary),'../share/zenit/harness/client.ts')).href);
const iso=await realpath(await mkdtemp('/tmp/zw-toolbar-popovers-')),data=join(iso,'data'),rpc=join(iso,'rpc');
for(const dir of [out,data,rpc])await mkdir(dir,{recursive:true});
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const log=await open(join(out,'app.log'),'w'),peerLog=await open(join(out,'peer.log'),'w');
const peer=spawn(python,['-I','e2e/builtin_records_ssh_peer.py','--out',join(out,'peer')],{stdio:['ignore',peerLog.fd,peerLog.fd]});
const peerEnded=new Promise(r=>peer.once('close',r));
let app:any,ended:Promise<any>;
const report:any={binary,sha256:createHash('sha256').update(await readFile(binary)).digest('hex'),checks:[],captures:[],geometry:[],limits:["This UI fixture uses in-memory credentials; no Keychain access or credential acceptance is tested."]};
const shown=(n:any)=>n&&n.rect?.w>0&&n.rect.h>0&&n.visible!==false&&n.hidden!==true&&(n.effective_opacity??1)>0.01;
const flat=(n:any):any[]=>n?[n,...(n.children??[]).flatMap(flat)]:[];
const text=(n:any)=>flat(n).map(x=>x.text??'').join(' ');
const nodes=async(id:string)=>(await h.query(id)).filter(shown);
const visible=(id:string)=>h.waitFor(async()=>(await nodes(id))[0]??null,12000).catch((e:any)=>{throw new Error(`${id} not shown: ${e}`)});
const hidden=(id:string)=>h.waitFor(async()=>!(await nodes(id)).length||null,6000).catch((e:any)=>{throw new Error(`${id} still shown: ${e}`)});
async function click(id:string){const n=await visible(id);await h.mouseMove(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2);assert((await h.clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok);await h.sleep(150);}
async function capture(name:string){assert((await h.screenshot(join(out,name+'.png'))).ok);report.captures.push(name);}
// design-r3 稿 5: a folded tool is reached through the ⋯ menu (its panel opens at the ⋯).
const menuRow:Record<string,string>={'status.connection.chain':'toolbar.more.chain','status.connection.forward':'toolbar.more.forward'};
// title-click: the theme is not a title bar tool (no button, no ⋯ row, no quick picker); 菜单栏“显示 › 外观…” opens 设置 › 外观与主题.
async function openAppearance(){const fired=await h.request('POST','/zerowork/app-menu',{invoke:true});assert(fired?.ok&&fired.invoked,'menu bar 显示 › 外观… is invoked');await visible('settings.window');return await visible('settings.appearance.themes');}
// title-click: the session card opens from the tab menu “会话详情” (context.menu.session_identity), never on hover. The user
// right-clicks the tab itself: the identity region over it is geometry-only and passes every pointer event through
// (workspace_chrome.zig identitiesAtTabs), so it is not used as a target here.
async function openIdentity(){const t=flat(await visible('tabs.strip')).find(n=>/^tabs\.tab\.\d+$/.test(n.test_id??'')&&shown(n));assert(t,'the SSH tab is shown');assert((await h.clickAt(t.rect.x+t.rect.w/2,t.rect.y+t.rect.h/2,1,'right')).ok);await visible('context.menu');await click('context.menu.session_identity');return t;}
async function tool(id:string){if((await nodes(id)).length){await click(id);return;}await click('toolbar.expand');await click(menuRow[id]);}
const panels=['connection.details','socks.info','status.connection'];
async function assertNone(){for(const id of panels)assert.equal((await nodes(id)).length,0,id+' remains closed');}
try{
 const ready=await h.waitFor(async()=>{assert(peer.exitCode===null,'SSH peer stays alive');try{return JSON.parse(await readFile(join(out,'peer/ready.json'),'utf8'))}catch{return null}},15000);
 await writeFile(join(data,'known_hosts'),ready.known_host);
 await writeFile(join(data,'config.toml'),`[meta]\nconfig_revision=1\n[ui]\ntheme="${theme}"\n`);
 await writeFile(join(data,'hosts.toml'),`[registry]\nschema_version=2\nrevision=1\nnext_connection_id=2\nnext_group_id=1\n[[hosts]]\nconnection_id=1\nrevision=1\nprotocol="ssh"\nauth_mode="password"\noptions={strict_host_key=true}\nname="Toolbar SSH"\nhost="127.0.0.1"\nport=${ready.port}\nuser="${ready.user}"\nauth={password="${ready.password}"}\nsocks_enabled=true\nsocks_port=1081\nsocks_bind="127.0.0.1"\nsocks_auto_start=false\n`);
 app=spawn(binary,[],{env:{...process.env,ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1'},stdio:['ignore',log.fd,log.fd]});ended=new Promise(r=>app.once('close',r));
 await Promise.race([h.waitForServerReady(60000),ended!.then(()=>{throw new Error('Native App exited before readiness');})]);await h.resizeWindow(1440,900);
 const host=await visible('sidebar.host');await h.mouseMove(host.rect.x+100,host.rect.y+host.rect.h/2);await click('sidebar.host.connect');
 await h.waitFor(async()=>{
  const secret=(await nodes('plugin.challenge.secret'))[0];
  if(secret){await click('plugin.challenge.secret');await h.type_(ready.password);await click('plugin.challenge.submit');}
  return text((await nodes('workspace.pane'))[0]).includes('sshrecords')||null;
 },30000);
 await h.mouseMove(700,300);await h.sleep(400);
 // Use the tab title, away from the overlaid session-identity icon and close.
 const tab=flat(await visible('tabs.strip')).find(n=>/^tabs\.tab\.\d+$/.test(n.test_id??''));assert(tab);
 if(!process.argv.includes("--session-only")){
 const point={x:tab.rect.x+tab.rect.w/2,y:tab.rect.y+tab.rect.h/2};
 await h.mouseMove(point.x,point.y);await visible('tabs.tooltip');
 for(const route of ['/mouse_down','/mouse_up'])assert((await h.request('POST',route,{...point,button:'right'})).ok);
 await visible('context.menu');await hidden('tabs.tooltip');await capture('tab-context-no-hover');
 await h.key('escape');await hidden('context.menu');await h.sleep(650);await hidden('tabs.tooltip');
 await h.mouseMove(700,300);await h.mouseMove(point.x,point.y);await visible('tabs.tooltip');await h.mouseMove(700,300);await hidden('tabs.tooltip');
 // Right-click before the hover delay expires must also cancel the pending hint.
 await h.mouseMove(point.x,point.y);
 for(const route of ['/mouse_down','/mouse_up'])await h.request('POST',route,{...point,button:'right'});
 await visible('context.menu');await h.sleep(650);await hidden('tabs.tooltip');await h.key('escape');await h.mouseMove(700,300);
 report.checks.push('Tab right-click closes visible and pending hints; Escape does not revive a stationary hint; leave/re-enter restores hover.');
 for(const [width,height]of [[1440,900],[860,480]]){
  await h.resizeWindow(width,height);await h.mouseMove(500,300);await h.sleep(400);
  // Every visible tool (and ⋯) uses clicks for actions; pointer movement opens no panel.
  const tools=flat(await visible('toolbar.tools')).filter(n=>n.role==='button'||/^(status\.|toolbar\.)/.test(n.test_id??'')).filter(n=>shown(n)&&n.rect.w===32);
  for(const button of tools){await h.mouseMove(button.rect.x+button.rect.w/2,button.rect.y+button.rect.h/2);await h.sleep(500);await assertNone();}
  report.checks.push(`${width}×${height}: hovering every visible title bar tool opens no functional panel.`);
  // title-click: no theme button and no theme row in ⋯ at this width.
  assert.equal((await nodes('status.connection.theme')).length,0,'no theme button in the title bar');
  for(const [triggerId,panelId]of [['status.connection.chain','connection.details'],['status.connection.forward','socks.info']]){
   await tool(triggerId);await h.sleep(300);const panel=await visible(panelId),trigger=(await nodes(triggerId))[0]??await visible('toolbar.expand'),r=panel.rect;
   assert(Math.abs(r.y-(trigger.rect.y+trigger.rect.h+6))<=1,panelId+' is below full trigger');
   assert(r.x>=7.9&&r.x+r.w<=width-7.9&&r.y+r.h<=height-7.9,panelId+' stays inside viewport');
   for(const other of panels)if(other!==panelId)assert.equal((await nodes(other)).length,0,'switch closes '+other);
   if(panelId==='socks.info'){
    const address=await visible('socks.info.address');
    assert(text(panel).includes('127.0.0.1:1081'));assert(text(panel).includes('下载'));assert(text(panel).includes('活跃连接'));
    assert(address.rect.y>r.y+35&&address.rect.y+address.rect.h<r.y+r.h-45,'forwarding details are between header and actions');
   }
   await capture(panelId.replaceAll('.','-')+'-'+width);report.geometry.push({width,height,triggerId,trigger:trigger.rect,panelId,panel:r});
  }
  // Clicking the same trigger closes; moving away leaves a clicked panel open.
  // title-click: the repeat-click check runs on the last opened tool (forwarding); the theme is 设置 › 外观与主题 (菜单栏“显示 › 外观…”).
  await tool('status.connection.forward');await hidden('socks.info');await tool('status.connection.forward');await visible('socks.info');await h.mouseMove(500,300);await h.sleep(300);await visible('socks.info');await click('socks.info.close');await hidden('socks.info');
  await openAppearance();await capture('settings-appearance-themes-'+width);await h.key('escape');await hidden('settings.window');await assertNone();
  report.checks.push(`${width}×${height}: chain → forwarding are exclusive, below triggers and bounded; forwarding body retained; repeat click and X close; no theme tool, 显示 › 外观… opens 设置 › 外观与主题.`);
 }
 }
 // Session card (status_connection_view.zig, Pencil lBTBA): opens from the tab menu “会话详情”, anchored to the active tab
 // (CardAnchor, cec07809). Size: width min(320, viewport − 2·8), height min(420, room below the tab − gap 6 − margin 8)
 // (status_connection_styles.zig width / height / margin / anchor_gap; status_connection_view.zig flush / alignedAnchor).
 const tabText=async()=>{const n=(await nodes(tab.test_id))[0];assert(n,'the SSH tab is shown');return n;};
 for(const [width,height]of [[1440,900],[860,480]]){
  await h.resizeWindow(width,height);await h.mouseMove(500,300);await h.sleep(200);
  // title-click: hovering the tab opens no card (900 ms > the native Tooltip delay); the tab menu “会话详情” does.
  {const t=await tabText();await h.mouseMove(t.rect.x+t.rect.w/2,t.rect.y+t.rect.h/2);await h.sleep(900);assert.equal((await nodes('status.connection')).length,0,'hovering the tab opens no session card');await h.mouseMove(500,300);}
  const trigger=await openIdentity();
  const panel=await visible('status.connection'),r=panel.rect;
  const expectedW=Math.min(320,width-16),expectedH=Math.min(420,height-(trigger.rect.y+trigger.rect.h)-6-8);
  assert(Math.abs(r.w-expectedW)<=0.5,`card width ${r.w} = min(320, viewport − 16) = ${expectedW}`);
  assert(Math.abs(r.h-expectedH)<=0.5,`card height ${r.h} = min(420, room below the tab) = ${expectedH}`);
  assert(Math.abs(r.y-trigger.rect.y-trigger.rect.h-6)<=1,'card sits 6 below the tab');
  const expectedX=trigger.rect.x+r.w<=width-8?trigger.rect.x:trigger.rect.x+trigger.rect.w-r.w;
  assert(Math.abs(r.x-Math.max(8,Math.min(expectedX,width-r.w-8)))<=1,'card aligns with the tab edge');
  // The compact card has no footer and no reconnect action (removed in b319da83; the old ids no longer exist).
  assert(!text(panel).includes('重新连接'),'no reconnect action in the session card');
  const name=await visible('status.connection.name'),health=await visible('status.connection.health'),address=await visible('status.connection.address'),copy=await visible('status.connection.copy'),logs=await visible('status.connection.logs');
  assert(text(name).includes('Toolbar SSH'),'card names the session');
  assert(health.rect.x>=name.rect.x+name.rect.w&&Math.abs(health.rect.y-name.rect.y)<1,'health is beside name');
  assert(copy.rect.x>=address.rect.x+address.rect.w&&logs.rect.x>copy.rect.x,'actions are beside endpoint');
  assert(Math.abs(copy.rect.y+copy.rect.h/2-address.rect.y-address.rect.h/2)<1);
  for(const n of [name,health,address,copy,logs])assert(n.rect.x>=r.x&&n.rect.x+n.rect.w<=r.x+r.w+0.5,'summary row stays inside the card');
  assert(r.x>=8&&r.x+r.w<=width-8&&r.y+r.h<=height-8);
  // The card's 网格 fact (status.connection.grid.detail, status_connection_view.zig) is the session's current terminal grid:
  // after the window resize it must match the pane header's live grid (pane.status), not the size captured earlier.
  const gridOf=(s:string)=>{const m=s.match(/(\d+)\s*×\s*(\d+)/);return m?`${m[1]}×${m[2]}`:null};
  const grids=await h.waitFor(async()=>{const pane=gridOf(text(await visible('pane.status'))),card=gridOf(text(await visible('status.connection.grid.detail')));return pane&&card&&pane===card?{pane,card}:null},3000).catch(async()=>({pane:gridOf(text((await nodes('pane.status'))[0]??{})),card:gridOf(text((await nodes('status.connection.grid.detail'))[0]??{}))}));
  report.geometry.push({width,height,grids});
  assert.equal(grids.card,grids.pane,`${width}×${height}: the session card grid matches the live pane grid`);
  await capture('session-identity-'+width);report.geometry.push({width,height,panelId:'status.connection',panel:r});
  await h.mouseMove(700,300);await h.sleep(300);await visible('status.connection');await h.key('escape');await hidden('status.connection');/* title-click: moving away keeps the clicked card; Escape closes */
 }
 await h.resizeWindow(1440,900);await openIdentity();await visible('status.connection');
 // “复制信息” writes the real system clipboard (connection_details_host.zig copy → platform_services.clipboardSetText;
 // zenit has no test clipboard): batch regression must not overwrite the user's clipboard, so only its hint is checked.
 for(const id of ['status.connection.copy','status.connection.logs']){const n=await visible(id);await h.mouseMove(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2);await h.sleep(650);await capture(id==='status.connection.copy'?'session-copy-tooltip':'session-logs-tooltip');} // native Tooltip after its delay (pixel review)
 await click('status.connection.logs');await hidden('status.connection');await visible('connection.logs');await capture('session-connection-logs');
 report.checks.push('Session card (tab menu 会话详情): width min(320, vw−16), height min(420, room below the tab), 6 below and edge-aligned with the tab, inline health and endpoint actions, no reconnect; logs opens 连接日志; copy not clicked (system clipboard).');report.status='passed';
}catch(error){report.status='failed';report.error=String(error);if(app){await capture('failure').catch(()=>{});
 // Diagnostics: “会话详情” opens through the identity region over the active tab (nav_host.zig openPendingIdentity).
 report.identity_regions=await Promise.all(['status.connection.identity','local.status.identity'].map(async id=>({id,nodes:(await h.query(id).catch(()=>[])).map((n:any)=>({rect:n.rect,hidden:n.hidden??false}))}))).catch(()=>null);}process.exitCode=1;}
finally{
 if(app&&app.exitCode===null&&app.signalCode===null){try{await h.request('POST','/zerowork/windows',{action:'quit'});await Promise.race([ended!,h.sleep(8000)]);}catch{}if(app.exitCode===null&&app.signalCode===null){app.kill('SIGTERM');await ended!;report.forced_shutdown=true;}else report.exit_code=app.exitCode;}
 peer.kill('SIGTERM');await Promise.race([peerEnded,h.sleep(3500)]);await peerLog.close();await log.close();await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));await rm(iso,{recursive:true,force:true});
}
console.log(JSON.stringify(report,null,2));
