/** Statusbar hover previews and click pinning against an isolated SSH + Local session. */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdir,mkdtemp,realpath,copyFile,readFile,writeFile,open,rm} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {createHash} from 'node:crypto';
import {waitForServerReady,waitFor,query,focused,clickAt,key,type_,resizeWindow,screenshot,sleep,scrollAt,mouseDown,mouseMove,mouseUp,request} from '../zig-out/share/zenit/harness/client.ts';
const python=process.env.ZW_TEST_PYTHON;assert(python,'ZW_TEST_PYTHON (audited Python with paramiko, run with -I) is required');
const out=resolve(process.argv[2]),source=resolve(process.argv[3]),theme=process.argv[4]??'dark';assert(['dark','light'].includes(theme));await mkdir(out,{recursive:false});
const iso=await realpath(await mkdtemp(join(tmpdir(),'zw-builtin-records-'))),rpc=join(iso,'rpc'),data=join(iso,'data'),shell=join(iso,'shell');
// Always remove this run's sandbox, including setup and reporting failures.
try {
await Promise.all([mkdir(rpc),mkdir(data),mkdir(shell)]);
await writeFile(join(shell,'.zshrc'),"bindkey -e\nPS1='records%# '\n");
await writeFile(join(data,'config.toml'),`[meta]\nconfig_revision=1\n[ui]\ntheme="${theme}"\nfont_family="Menlo"\nfont_size=14\n`);
await copyFile(source,join(iso,'zerowork'));await copyFile(join(source,'..','zw_ipc.so'),join(iso,'zw_ipc.so'));
const peerLog=await open(join(out,'peer.log'),'w');const peerOut=join(out,'peer');const peer=spawn(python,['-I','e2e/builtin_records_ssh_peer.py','--out',peerOut],{stdio:['ignore',peerLog.fd,peerLog.fd]});const peerEnded=new Promise(r=>peer.once('close',r));
const ready=await waitFor(async()=>{try{return JSON.parse(await readFile(join(peerOut,'ready.json'),'utf8'))}catch{return null}},15000);
await writeFile(join(data,'known_hosts'),ready.known_host);
await writeFile(join(data,'hosts.toml'),`[registry]\nschema_version=2\nrevision=1\nnext_connection_id=2\nnext_group_id=1\n[[hosts]]\nconnection_id=1\nrevision=1\nprotocol="ssh"\nauth_mode="password"\noptions={strict_host_key=true}\nname="Owned records SSH"\ngroup="QA hosts"\nhost="127.0.0.1"\nport=${ready.port}\nuser="${ready.user}"\nauth={password="${ready.password}"}\n`);
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;const log=await open(join(out,'app.log'),'w');const app=spawn(join(iso,'zerowork'),[],{env:{...process.env,ZDOTDIR:shell,ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1'},stdio:['ignore',log.fd,log.fd]});const ended=new Promise(r=>app.once('close',r));
const report:any={status:'running',pid:app.pid,isolated:iso,sha256:createHash('sha256').update(await readFile(source)).digest('hex'),checks:[],captures:[],limits:['Public synthetic Harness on actual Metal window; no physical CUA/IME/VoiceOver acceptance.','The owned loopback SSH peer runs an actual ZSH PTY; no external host is accessed. Physical CUA/IME/VoiceOver remain separate.']};
const content=(n:any):string=>!shown(n)?'':(n.text??'')+(n.children??[]).map(content).join('');
const shown=(n:any)=>n&&n.hidden!==true&&n.visible!==false&&(n.effective_opacity??1)>0&&n.rect?.w>0&&n.rect?.h>0;
const vis=(id:string)=>waitFor(async()=>(await query(id)).find(shown)??null,12000).catch((e:any)=>{throw new Error(`${id} not shown: ${e}`)}),hidden=(id:string)=>waitFor(async()=>!(await query(id)).some(shown)||null,12000).catch((e:any)=>{throw new Error(`${id} still shown: ${e}`)});
async function click(id:string){const n=await vis(id);assert((await clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok);await sleep(160)}
async function press(name:string,mods?:any){assert((await key(name,mods)).ok)}
async function type(text:string){assert((await type_(text)).ok)}
async function capture(name:string){await sleep(180);assert((await screenshot(join(out,name+'.png'))).ok);report.captures.push(name)}
// title-click: the title bar theme button and its quick picker are gone. The reference entry is now the menu bar
// “显示 › 外观…” (harness `/zerowork/app-menu`), and `@theme` must land on the same 设置 › 外观与主题 page.
async function checkThemeCommand(entry:string,width:number,height:number){
 await resizeWindow(width,height);await mouseMove(400,200);await sleep(200);
 assert(!(await query('status.connection.theme')).some(shown),'no theme button in the title bar (title-click)');
 const fired=await request('POST','/zerowork/app-menu',{invoke:true});assert(fired?.ok&&fired.invoked,'menu bar 显示 › 外观… is invoked');
 await vis('settings.window');const expected=(await vis('settings.appearance.themes')).rect;
 await press('escape');await hidden('settings.window');await click('terminal.surface');
 await type('@');await vis('terminal.commands');await type('theme');await press('right');await hidden('terminal.commands');await press('return');
 await vis('settings.window');await vis('settings.appearance.themes');await mouseMove(400,200);await sleep(350);
 const actual=(await vis('settings.appearance.themes')).rect;
 for(const axis of ['x','y','w','h'])assert(Math.abs(actual[axis]-expected[axis])<=1,`@theme ${entry} ${width}: ${axis} differs from menu bar 显示 › 外观…`);
 assert(actual.w>0&&actual.h>0,'@theme shows 设置 › 外观与主题 › 主题');
 await capture(entry.replaceAll('.','-')+'-command-'+width);
 await press('escape');await hidden('settings.window');await mouseMove(400,200);
 report.checks.push(`@theme ${entry} ${width}x${height}: opens the same 设置 › 外观与主题 as 菜单栏“显示 › 外观…”, stays open after pointer leaves, Escape closes`);
}
try{
 await waitForServerReady(60000);await resizeWindow(1440,900);const host=await vis('sidebar.host');await mouseMove(host.rect.x+host.rect.w/2,host.rect.y+host.rect.h/2);await click('sidebar.host.connect');await waitFor(async()=>{
  const secret=(await query('plugin.challenge.secret')).find(shown);
  if(secret){await clickAt(secret.rect.x+secret.rect.w/2,secret.rect.y+secret.rect.h/2);await key('a',{cmd:true});await type_(ready.password);const submit=(await query('plugin.challenge.submit')).find(shown);if(submit)await clickAt(submit.rect.x+submit.rect.w/2,submit.rect.y+submit.rect.h/2);}
  return content(await vis('workspace.pane')).includes('sshrecords')||null;
 },30000);
 await mouseMove(700,300);
 // Workspace chrome (current contract): there is no bottom status bar. The session identity regions
 // (status.connection.identity / local.status.identity) are geometry-only, pass-through regions over the active tab
 // (workspace_chrome.zig identitiesAtTabs/afterLayout); the user acts on the tab itself, and the session card opens
 // from the tab menu “会话详情” (context.menu.session_identity, menu_host.zig .session_identity), never on hover.
 // Title bar tools (chain / forward) open on click (title_tools.yix); the theme is not a title bar tool (18a4b06a).
 const activeTab=async()=>{
  const strip=await vis('tabs.strip');
  const identities=[...await query('status.connection.identity'),...await query('local.status.identity')].filter(shown);
  const flatten=(n:any):any[]=>[n,...(n.children??[]).flatMap(flatten)];
  return flatten(strip).find((n:any)=>/^tabs\.tab\.\d+$/.test(n.test_id??'')&&shown(n)&&n.focusable&&identities.some(({rect})=>{
   const x=rect.x+rect.w/2,y=rect.y+rect.h/2;
   return x>=n.rect.x&&x<n.rect.x+n.rect.w&&y>=n.rect.y&&y<n.rect.y+n.rect.h;
  }));
 };
 type Case={label:string,trigger:()=>Promise<any>,panelId:string,viaTabMenu:boolean,names?:string};
 const tool=(id:string):Case=>({label:id,trigger:()=>vis(id),panelId:id==='status.connection.chain'?'connection.details':'socks.info',viaTabMenu:false});
 const sessionCard=(label:string,panelId:string,names:string):Case=>({label,names,trigger:async()=>{const t=await activeTab();assert(t,'an active tab exists');return t},panelId,viaTabMenu:true});
 // The hover dwell (900 ms) is longer than the native Tooltip delay: proving that nothing opens needs the full delay.
 async function checkEntries(cases:Case[]){
 for(const c of cases){
  const t=await c.trigger();const x=t.rect.x+t.rect.w/2,y=t.rect.y+t.rect.h/2;
  const focusBefore=(await focused()).id;
  await mouseMove(x,y);await sleep(900);
  assert(!(await query(c.panelId)).some(shown),'Hovering '+c.label+' opens no card (title-click)');
  assert.equal((await focused()).id,focusBefore,'Hover must preserve keyboard focus for '+c.label);
  await capture(c.label.replaceAll('.','-')+'-hover');
  await mouseMove(700,300);
  assert.equal((await focused()).id,focusBefore,'Leaving '+c.label+' must not move focus');
  if(c.viaTabMenu){assert((await clickAt(x,y,1,'right')).ok);await vis('context.menu');await click('context.menu.session_identity');}else assert((await clickAt(x,y)).ok);
  const panel=await vis(c.panelId);
  if(c.names)assert(content(panel).includes(c.names),c.panelId+' describes the active session '+c.names);
  // Pointer into the card, then away: a clicked card stays open (no hover dismissal).
  await mouseMove(panel.rect.x+panel.rect.w/2,panel.rect.y+25);await vis(c.panelId);
  await mouseMove(700,300);await sleep(350);await vis(c.panelId);
  await capture(c.label.replaceAll('.','-')+'-clicked');
  const other=await vis('toolbar.settings');await mouseMove(other.rect.x+other.rect.w/2,other.rect.y+other.rect.h/2);await sleep(350);await vis(c.panelId);
  if(!c.viaTabMenu){
   assert((await clickAt(x,y)).ok);await hidden(c.panelId);
   assert((await clickAt(x,y)).ok);await vis(c.panelId);await mouseMove(700,300);assert((await clickAt(700,300)).ok);await hidden(c.panelId);
   assert((await clickAt(x,y)).ok);await vis(c.panelId);
  }
  await press('escape');await hidden(c.panelId);await mouseMove(700,300);
  report.checks.push(c.label+': hover opens nothing and keeps focus, '+(c.viaTabMenu?'tab menu “会话详情” opens '+c.panelId:'click opens, second click and outside click close')+', card stays open after leave and while another tool is hovered, Escape closes');
 }
 }
 const sshTab=(await activeTab()).test_id;
 await checkEntries([sessionCard('ssh-tab','status.connection','Owned records SSH'),tool('status.connection.chain'),tool('status.connection.forward')]);
 await checkThemeCommand('ssh',1440,900);await checkThemeCommand('ssh',860,480);await resizeWindow(1440,900);
 // Transfers: the bottom ticker (status.transfer) is not presented in workspace chrome; the title bar entry is
 // toolbar.transfers (same contract as transfer_entrypoints_native). Hover opens no list and focuses nothing.
 assert(!(await query('status.transfer')).some(shown),'the bottom transfer ticker is not presented in workspace chrome');
 {const transfers=await vis('toolbar.transfers');const focusBefore=(await focused()).id;
  await mouseMove(transfers.rect.x+transfers.rect.w/2,transfers.rect.y+transfers.rect.h/2);await sleep(900);
  assert(!(await query('transfer.manager')).some(shown),'hovering 传输 opens no list');
  await mouseMove(700,300);assert(!(await query('transfer.manager')).some(shown));
  assert.equal((await focused()).id,focusBefore,'Transfer hover must not move focus');
  await capture('toolbar-transfers-hover-dismissed');}
 report.checks.push('toolbar.transfers: idle hover and leave open no list and keep focus; the bottom ticker is not presented');
 await click('toolbar.new_session');await click('session.menu.local');await vis('terminal.surface');
 const localTab=await waitFor(async()=>{const t=await activeTab();return t&&t.test_id!==sshTab?t:null},12000);await mouseMove(700,300);
 await checkEntries([sessionCard('local-tab','status.detail','本地终端')]);
 await checkThemeCommand('local',1440,900);await checkThemeCommand('local',860,480);await resizeWindow(1440,900);
 // Cmd+D turns the focused local tab into a terminal group (one tab, two panes); the group's broadcast tool is a title bar
 // button (status.group.broadcast) that exists only while the group tab is active.
 assert(!(await query('status.group.broadcast')).some(shown),'no broadcast tool for a single local session');
 await click('terminal.surface');await press('d',{cmd:true});
 const group=await vis('groups.tab');assert(content(group).startsWith('组 · '),'the tab becomes a terminal group');
 const panes=async()=>{const flatten=(n:any):any[]=>[n,...(n.children??[]).flatMap(flatten)];return flatten(await vis('groups.workspace')).filter((n:any)=>/^groups\.pane\.\d+$/.test(n.test_id??'')&&shown(n))};
 await waitFor(async()=>(await panes()).length===2||null,15000);
 assert(!(await query(localTab.test_id)).some(shown)||content((await query(localTab.test_id)).find(shown)).startsWith('组 · '),'the local tab is now the group tab');
 const toolbar=await vis('toolbar.tools');let broadcast=await vis('status.group.broadcast');
 assert(broadcast.rect.x>=toolbar.rect.x&&broadcast.rect.x+broadcast.rect.w<=toolbar.rect.x+toolbar.rect.w,'broadcast sits in the title bar tools');
 await capture('local-group-status-wide');await resizeWindow(860,480);
 // 860×480 folds the connection tools into “⋯” (model/title_tools.zig inBar/inMenu: compact keeps notifications and
 // settings; a present broadcast moves to the menu row toolbar.more.broadcast).
 await hidden('status.group.broadcast');await click('toolbar.expand');const row=await vis('toolbar.more.broadcast');
 assert(row.rect.x>=0&&row.rect.x+row.rect.w<=860&&row.rect.y+row.rect.h<=480,'the broadcast row stays inside the compact window');
 await capture('local-group-status-compact');await press('escape');await hidden('toolbar.more.broadcast');await resizeWindow(1440,900);
 const sshNode=(await query(sshTab)).find(shown);assert(sshNode);assert((await clickAt(sshNode.rect.x+sshNode.rect.w/2,sshNode.rect.y+sshNode.rect.h/2)).ok);
 await waitFor(async()=>content(await vis('workspace.pane')).includes('sshrecords')||null,12000);await hidden('status.group.broadcast');
 await click('groups.tab');await waitFor(async()=>(await panes()).length===2||null,12000);await vis('status.group.broadcast');
 report.checks.push('Cmd+D groups the local session (one 组 tab, two panes); the broadcast tool shows only while the group tab is active, moves into the ⋯ menu inside the 860×480 window, and SSH ↔ group tab switches restore each one');
 report.status='passed';
}catch(e){report.status='failed';report.error=String(e);await capture('failure').catch(()=>{});
 // Diagnostics: the tab menu “会话详情” opens the card through the identity region over the active tab (nav_host.zig
 // openPendingIdentity), so record whether that region was displayed when a card failed to open.
 report.identity_regions=await Promise.all(['status.connection.identity','local.status.identity'].map(async id=>({id,nodes:(await query(id).catch(()=>[])).map((n:any)=>({rect:n.rect,hidden:n.hidden??false}))}))).catch(()=>null);process.exitCode=1}
finally{if(app.exitCode===null&&app.signalCode===null){app.kill('SIGTERM');await Promise.race([ended,sleep(3000)]);if(app.exitCode===null&&app.signalCode===null){app.kill('SIGKILL');await ended}}peer.kill('SIGTERM');await Promise.race([peerEnded,sleep(3500)]);await peerLog.close();await log.close();await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));}
console.log(JSON.stringify({status:report.status,checks:report.checks,error:report.error,out}));
} finally {
 await rm(iso,{recursive:true,force:true});
}
