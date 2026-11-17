/** Panel contract (overlay-focus, CONSISTENCY_AUDIT #1, 用户拍板 1 / 4): one set of assertions for every
 * panel, popover, menu, card and confirmation the main window and the settings window can open.
 *
 * Every entry:
 *  - open → keyboard focus is inside the panel (its first control, or the declared safe control);
 *  - Tab / Shift+Tab several times → focus never leaves the panel;
 *  - Escape → only the top layer closes; focus returns to the trigger (the button, or for a shortcut /
 *    right click what had focus before);
 *  - reopen, click outside on a focusable control → the panel closes and focus stays on what was clicked.
 * Floating cards (AI, 会话记录) are non-modal: an outside click does not close them (focus moves to what
 * was clicked); Escape closes them only while focus is inside the card.
 * Stacking: Escape with a layer opened over another closes only the upper one.
 *
 * Usage: node e2e/panel_contract_native.ts <binary> <out> [light|dark]
 * Optional ZW_TEST_PYTHON (paramiko) adds the SSH-only panels (通信链路 / 端口转发 / 关闭 SSH 会话确认).
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {chmod,mkdir,mkdtemp,open,readFile,writeFile,realpath,rm} from 'node:fs/promises';
import {dirname,resolve,join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {settingsNav,textOf} from './settings_nav.ts';
const binary=resolve(process.argv[2]),out=resolve(process.argv[3]),variant=process.argv[4]??'light';
const theme=variant==='dark'?'dark':'light';
const h=await import(pathToFileURL(resolve(dirname(binary),'../share/zenit/harness/client.ts')).href);
const iso=await realpath(await mkdtemp('/private/tmp/zw-panel-contract-'));await chmod(iso,0o700);
const data=join(iso,'data'),rpc=join(iso,'rpc'),tmp=join(iso,'tmp'),zdot=join(iso,'zdot');
for(const p of [out,data,rpc,tmp,zdot])await mkdir(p,{recursive:true,mode:0o700});
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const python=process.env.ZW_TEST_PYTHON;
let peer:any=null,peerLog:any=null,ready:any=null;
if(python){
 peerLog=await open(join(out,'peer.log'),'w');
 peer=spawn(python,['-I',resolve(dirname(new URL(import.meta.url).pathname),'builtin_records_ssh_peer.py'),'--out',join(iso,'peer')],{stdio:['ignore',peerLog.fd,peerLog.fd]});
 ready=await h.waitFor(async()=>{try{return JSON.parse(await readFile(join(iso,'peer/ready.json'),'utf8'))}catch{return null}},20000);
 await writeFile(join(data,'known_hosts'),ready.known_host);
 await writeFile(join(data,'hosts.toml'),`[registry]\nschema_version=2\nrevision=1\nnext_connection_id=2\nnext_group_id=1\n[[hosts]]\nconnection_id=1\nrevision=1\nprotocol="ssh"\nauth_mode="password"\noptions={strict_host_key=true}\nname="Contract SSH"\nhost="127.0.0.1"\nport=${ready.port}\nuser="${ready.user}"\nauth={password="${ready.password}"}\nsocks_enabled=true\nsocks_port=1081\nsocks_bind="127.0.0.1"\nsocks_auto_start=false\n`);
}else{
 // Without the SSH peer the sidebar still needs one saved host for the 'sidebar-menu' entry (right click on
 // sidebar.host). It is never connected: ZEROWORK_AUTOCONNECT=0 and the contract only opens its context menu.
 await writeFile(join(data,'hosts.toml'),`[registry]\nschema_version=2\nrevision=1\nnext_connection_id=2\nnext_group_id=1\n[[hosts]]\nconnection_id=1\nrevision=1\nprotocol="ssh"\nauth_mode="password"\noptions={strict_host_key=true}\nname="Contract SSH (offline)"\nhost="127.0.0.1"\nport=9\nuser="contract"\n`);
}
await writeFile(join(data,'config.toml'),`[meta]\nconfig_revision=1\n[updates]\nauto_check=false\n[ui]\ntheme="${theme}"\n`);
const log=await open(join(out,`${variant}-app.log`),'w');
const app=spawn(binary,[],{env:{PATH:process.env.PATH??'/usr/bin:/bin',HOME:iso,CFFIXED_USER_HOME:iso,TMPDIR:tmp+'/',ZDOTDIR:zdot,ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1',OPENAI_API_KEY:'',ANTHROPIC_API_KEY:''},stdio:['ignore',log.fd,log.fd]});
const ended=new Promise(r=>app.once('close',r));
const report:any={variant,ssh:!!python,panels:{},stacking:{},failures:[] as string[]};
const shown=(n:any)=>n?.rect?.w>0&&n.rect.h>0&&n.visible!==false&&n.hidden!==true&&(n.effective_opacity??n.opacity??1)>0.5;
const flat=(n:any):any[]=>n?[n,...(n.children??[]).flatMap(flat)]:[];
const alive=()=>assert(app.exitCode===null&&app.signalCode===null,'native app stays alive');
const nodes=async(id:string)=>{alive();const r=await h.query(id);assert(Array.isArray(r),id+': '+JSON.stringify(r));return r.filter(shown);};
const visible=(id:string,ms=8000)=>h.waitFor(async()=>(await nodes(id))[0]??null,ms);
const hidden=(id:string,ms=5000)=>h.waitFor(async()=>!(await nodes(id)).length||null,ms);
const sleep=(ms:number)=>h.sleep(ms);
const away={x:700,y:560};
async function centre(id:string){const n=await visible(id);return {x:n.rect.x+n.rect.w/2,y:n.rect.y+n.rect.h/2};}
async function clickId(id:string,button?:string){const c=await centre(id);await h.mouseMove(c.x,c.y);assert((await h.clickAt(c.x,c.y,1,button)).ok);await sleep(200);}
async function rightClick(id:string){const c=await centre(id);await h.mouseMove(c.x,c.y);for(const route of ['/mouse_down','/mouse_up'])assert((await h.request('POST',route,{...c,button:'right'})).ok);await sleep(300);}
const focused=async()=>{try{return await h.focused()}catch{return {}}};
const focusId=async()=>(await focused()).test_id??null;
async function inside(root:string){const f:any=await focused();if(f.id==null)return {inside:false,f:null};const panel=(await nodes(root))[0];const ids=new Set(flat(panel).map((n:any)=>n.id));return {inside:ids.has(f.id),f:f.test_id??`#${f.id}(${f.component??f.tag})`};}
async function shot(name:string,win?:string){await sleep(250);await h.screenshot(join(out,`${variant}-${name}.png`),win).catch(()=>{});}
async function settle(){for(let i=0;i<3;i++){await h.key('escape');await sleep(150);}
 for(const close of ['ai.close','history.close']){try{if((await nodes(close)).length){await clickId(close);await sleep(300);}}catch{}}
 await h.mouseMove(away.x,away.y);await sleep(200);}
/** A point inside the active terminal away from every panel and card (its lower-left corner). */
async function terminalPoint(){const all=(await nodes('terminal.surface')).sort((a:any,b:any)=>b.rect.w*b.rect.h-a.rect.w*a.rect.h);const n=all[0];assert(n,'terminal surface');return {x:n.rect.x+60,y:n.rect.y+n.rect.h-60};}
async function clickOutside(target:string){if(target==='terminal'){const p=await terminalPoint();await h.mouseMove(p.x,p.y);assert((await h.clickAt(p.x,p.y)).ok);await sleep(250);}else await clickId(target);}

type Kind='panel'|'menu'|'dialog'|'card';
type Entry={name:string,root:string,kind:Kind,open:()=>Promise<void>,trigger?:string,initial?:string,outside?:string,expectOutsideFocus?:string,tabs?:number,skipOutside?:boolean,before?:()=>Promise<void>};
const record=(name:string,key:string,ok:boolean,detail:any)=>{report.panels[name]??={};report.panels[name][key]={ok,detail};if(!ok)report.failures.push(`${name}: ${key} ${JSON.stringify(detail)}`);};

/** The same contract for every entry. Records every assertion; failures are collected, not thrown. */
async function contract(e:Entry){
 try{
  if(e.before)await e.before();
  const before=await focusId();
  await e.open();
  await visible(e.root);await sleep(350);
  await shot(e.name);
  const entry=await inside(e.root);
  record(e.name,'focus_enters',entry.inside&&(!e.initial||entry.f===e.initial),{focused:entry.f,expected:e.initial??'inside '+e.root});
  const seq:any[]=[];let stays=true;
  for(let i=0;i<(e.tabs??4);i++){await h.key('tab');await sleep(110);const s=await inside(e.root);seq.push(s.f);if(!s.inside)stays=false;}
  await h.key('tab',{shift:true});await sleep(110);{const s=await inside(e.root);seq.push('⇧'+s.f);if(!s.inside)stays=false;}
  record(e.name,'tab_contained',stays,seq);
  // Escape: closes (the top layer is this one) and focus returns to the trigger.
  // A focus tooltip on the focused control is itself the top layer (zenit: a hint on a control inside the
  // topmost layer takes Escape first); then the next Escape closes the panel.
  await h.key('escape');let closed=await hidden(e.root,1500).then(()=>true).catch(()=>false);let presses=1;
  if(!closed&&(await inside(e.root)).inside){await h.key('escape');presses=2;closed=await hidden(e.root,3000).then(()=>true).catch(()=>false);}
  report.panels[e.name]??={};report.panels[e.name].escape_presses=presses;await sleep(200);
  const back=await focusId();const want=e.trigger??before;
  record(e.name,'escape_closes',closed,{});
  record(e.name,'focus_returns',closed&&back===want,{focused:back,expected:want});
  if(!closed){await settle();}
  // Outside click on a focusable control.
  if(!e.skipOutside){
   await e.open();await visible(e.root);await sleep(350);
   const target=e.outside??'terminal';
   await clickOutside(target);await sleep(300);
   const stillOpen=(await nodes(e.root)).length>0;
   const f=await focusId();
   if(e.kind==='card'){
    record(e.name,'outside_keeps_card',stillOpen,{});
    record(e.name,'outside_focus_stays',f===(e.expectOutsideFocus??(target==='terminal'?'terminal.input':target)),{focused:f,expected:e.expectOutsideFocus??(target==='terminal'?'terminal.input':target)});
    // Focus is outside the card now: Escape must not close it.
    await h.key('escape');await sleep(300);
    record(e.name,'escape_needs_focus_inside',(await nodes(e.root)).length>0,{});
   }else{
    record(e.name,'outside_closes',!stillOpen,{});
    record(e.name,'outside_focus_stays',f===(e.expectOutsideFocus??(target==='terminal'?'terminal.input':target)),{focused:f,expected:e.expectOutsideFocus??(target==='terminal'?'terminal.input':target)});
   }
  }
 }catch(err){record(e.name,'error',false,String((err as any)?.message??err));await shot(e.name+'-error');}
 await settle();
}

try{
 await h.waitForServerReady(60000);await h.resizeWindow(1440,900);await h.mouseMove(away.x,away.y);
 // A local terminal tab.
 await clickId('workspace.empty.local');await visible('terminal.surface');await sleep(600);
 if(ready){
  const host=await visible('sidebar.host');await h.mouseMove(host.rect.x+100,host.rect.y+host.rect.h/2);await clickId('sidebar.host.connect');
  await h.waitFor(async()=>{if((await nodes('plugin.challenge.secret')).length){await clickId('plugin.challenge.secret');await h.type_(ready.password);await clickId('plugin.challenge.submit');}return (await nodes('status.connection.chain')).length>0||null;},30000);
  await sleep(800);
 }
 const terminal=async()=>{await clickOutside('terminal');await sleep(150);};
 const outsideTerminal='terminal',terminalFocus='terminal.input';
 const entries:Entry[]=[
  {name:'notifications',root:'notifications.history',kind:'panel',trigger:'toolbar.notifications',open:()=>clickId('toolbar.notifications')},
  {name:'transfers',root:'transfer.manager',kind:'panel',trigger:'toolbar.transfers',open:()=>clickId('toolbar.transfers')},
  {name:'command-history',root:'terminal.command-history',kind:'panel',trigger:'status.command-history',before:terminal,open:()=>clickId('status.command-history')},
  {name:'command-history-shortcut',root:'terminal.command-history',kind:'panel',trigger:terminalFocus,before:terminal,open:async()=>{await h.key('b',{cmd:true,shift:true});await sleep(300);}},
  {name:'new-session',root:'session.menu',kind:'menu',trigger:'toolbar.new_session',open:()=>clickId('toolbar.new_session')},
  {name:'tab-menu',root:'context.menu',kind:'menu',before:terminal,trigger:terminalFocus,open:async()=>{const tab=flat(await visible('tabs.strip')).find((n:any)=>/^tabs\.tab\.\d+$/.test(n.test_id??'')&&shown(n));const c={x:tab.rect.x+tab.rect.w/2,y:tab.rect.y+tab.rect.h/2};for(const r of ['/mouse_down','/mouse_up'])await h.request('POST',r,{...c,button:'right'});await sleep(300);}},
  {name:'terminal-menu',root:'terminal.menu',kind:'menu',before:terminal,trigger:terminalFocus,open:()=>rightClick('terminal.surface')},
  {name:'sidebar-menu',root:'context.menu',kind:'menu',before:terminal,trigger:terminalFocus,outside:outsideTerminal,expectOutsideFocus:terminalFocus,open:()=>rightClick('sidebar.host')},
  {name:'history-card',root:'history.panel',kind:'card',trigger:'toolbar.history',outside:outsideTerminal,expectOutsideFocus:terminalFocus,open:()=>clickId('toolbar.history')},
  // The launcher is a native GlassButton that does not take focus on click: focus returns to where it was (the terminal).
  {name:'ai-card',root:'ai.panel',kind:'card',before:terminal,trigger:terminalFocus,outside:outsideTerminal,expectOutsideFocus:terminalFocus,open:()=>clickId('ai.launcher')},
 ];
 if(ready)entries.push(
  {name:'chain',root:'connection.details',kind:'panel',trigger:'status.connection.chain',open:()=>clickId('status.connection.chain')},
  {name:'forward',root:'socks.info',kind:'panel',trigger:'status.connection.forward',open:()=>clickId('status.connection.forward')},
 );
 for(const e of entries)await contract(e);

 // Stacking: a panel opened over the AI card (focus inside the card first) — Escape closes only the panel.
 try{
  await clickId('ai.launcher');await visible('ai.panel');await sleep(400);
  await clickId('toolbar.notifications');await visible('notifications.history');await sleep(300);
  await h.key('escape');await sleep(400);
  const r={panel_closed:!(await nodes('notifications.history')).length,card_open:(await nodes('ai.panel')).length>0};
  report.stacking['panel-over-card']=r;if(!r.panel_closed||!r.card_open)report.failures.push('stacking panel-over-card '+JSON.stringify(r));
 }catch(err){report.failures.push('stacking panel-over-card '+String(err));}
 await settle();
 // Stacking: deleting a history record is undoable (CONSISTENCY_AUDIT #2) — no inline confirmation; the card stays open,
 // a native toast offers 撤销 and 撤销 brings the record back.
 try{
  // A finished local session leaves a record to delete.
  await clickId('toolbar.new_session');await clickId('session.menu.local');await sleep(1200);await h.type_('exit\n');await sleep(1500);await settle();
  await clickId('toolbar.history');await visible('history.panel');await sleep(600);
  const before=(await nodes('history.record')).length;
  const del=(await nodes('history.record.delete'))[0];
  if(del){await clickId('history.record.delete');await sleep(300);await visible('notifications.undo');await shot('history-delete-undo');
   const r:any={confirmation:(await nodes('history.confirmation')).length,card_open:(await nodes('history.panel')).length>0,hidden:(await nodes('history.record')).length===before-1};
   await clickId('notifications.undo.action');await sleep(600);
   r.restored=(await nodes('history.record')).length===before;
   report.stacking['undo-in-card']=r;if(r.confirmation||!r.card_open||!r.hidden||!r.restored)report.failures.push('stacking undo-in-card '+JSON.stringify(r));}
  else report.failures.push('stacking undo-in-card: no record to delete');
 }catch(err){report.failures.push('stacking undo-in-card '+String(err));}
 await settle();

 // Local close confirmation: focus on 取消 (the safe button), no tooltip pops up, Escape cancels.
 await contract({name:'local-close-confirm',root:'local.close.confirmation',kind:'dialog',initial:'local.close.cancel',trigger:terminalFocus,skipOutside:true,
  before:async()=>{const tab=flat(await visible('tabs.strip')).find((n:any)=>/^tabs\.tab\.\d+$/.test(n.test_id??'')&&shown(n)&&flat(n).some((c:any)=>(c.text??'').includes('本地')));if(tab){await h.mouseMove(tab.rect.x+tab.rect.w/2,tab.rect.y+tab.rect.h/2);await h.clickAt(tab.rect.x+tab.rect.w/2,tab.rect.y+tab.rect.h/2);await sleep(500);}await terminal();await h.type_('sleep 120\n');await sleep(700);},
  open:async()=>{await h.key('w',{cmd:true});await sleep(500);}});
 report.panels['local-close-confirm']??={};
 {await h.key('w',{cmd:true});await sleep(900);report.panels['local-close-confirm'].tooltip_shown=(await nodes('local.close.dismiss.tooltip')).length>0;if(report.panels['local-close-confirm'].tooltip_shown)report.failures.push('local-close-confirm: a tooltip pops up on open');
  // Outside click (the scrim) cancels: the tab stays.
  await h.mouseMove(40,860);await h.clickAt(40,860);await sleep(500);report.panels['local-close-confirm'].outside_closes=!(await nodes('local.close.confirmation')).length;
  if(!report.panels['local-close-confirm'].outside_closes)report.failures.push('local-close-confirm: outside click does not cancel');}
 await settle();
 await terminal();await h.key('c',{ctrl:true});await sleep(300);

 // SSH close confirmation (when the session has something to lose): same dialog contract.
 if(ready){
  await settle();
  const tab=flat(await visible('tabs.strip')).find((n:any)=>/^tabs\.tab\.\d+$/.test(n.test_id??'')&&shown(n)&&flat(n).some((c:any)=>(c.text??'').includes('Contract SSH')));
  if(tab){await h.mouseMove(tab.rect.x+tab.rect.w/2,tab.rect.y+tab.rect.h/2);await h.clickAt(tab.rect.x+tab.rect.w/2,tab.rect.y+tab.rect.h/2);await sleep(500);}
  await terminal();await h.key('w',{cmd:true});await sleep(700);
  if((await nodes('session.close.confirm')).length){
   await h.key('escape');await sleep(300);
   await contract({name:'ssh-close-confirm',root:'session.close.confirm',kind:'dialog',initial:'session.close.cancel',trigger:terminalFocus,skipOutside:true,before:terminal,open:async()=>{await h.key('w',{cmd:true});await sleep(600);}});
  }else report.panels['ssh-close-confirm']={skipped:'no confirmation for this session (nothing at risk)'};
 }
 await settle();
 // Settings window: text field Escape returns to the focus-time value (one rule for every native Input), and Escape
 // closes only the top layer (the unsaved-changes confirmation, not the window).
 try{
  const nav=settingsNav();
  await nav.open();await nav.toSub('ssh','connection');
  const field='settings.field.keepalive_sec';
  const valueOf=async()=>textOf(await nav.node(field)).trim();
  const original=await valueOf();
  const ws=(await h.windows()).windows;const win=ws[ws.length-1]?.window_id;
  // Edit twice in one focus (an intermediate valid draft), then Escape: back to the value at focus time.
  await nav.click(field);await h.key('a',{cmd:true});await h.key('backspace');await h.type_('45');await sleep(200);await h.type_('6');await sleep(200);
  const typed=await valueOf();
  await h.key('escape');await sleep(400);
  const r:any={original,typed,after_escape:await valueOf(),window_open:await nav.visible('settings.panel'),dirty:await nav.dirty()};
  report.panels['settings-input-escape']=r;
  if(r.after_escape!==original||!r.window_open||r.dirty)report.failures.push('settings-input-escape '+JSON.stringify(r));
  // Unsaved change, then Escape at window level: the confirmation opens with focus on its safe button; Tab stays in it;
  // Escape closes the confirmation only.
  await nav.edit(field,'47');await nav.click('settings.page.title').catch(()=>{});await sleep(200);
  await h.key('escape');const confirm=await nav.node('settings.confirmation',6000).catch(()=>null);
  const c:any={opened:!!confirm};
  if(confirm){await sleep(300);await shot('settings-confirmation',win);c.focus=(await inside('settings.confirmation')).f;
   // Tab cycles through the dialog's own controls: its buttons (inside the settings.confirmation body) and the native
   // Modal's title-bar close button (after the body in focus order, named settings.confirmation.close).
   c.tab_order=[];
   c.tab_contained=true;
   for(let i=0;i<4;i++){
    await h.key('tab');await sleep(110);
    const s=await inside('settings.confirmation');
    c.tab_order.push(s.f);
    if(!s.inside&&s.f!=='settings.confirmation.close')c.tab_contained=false;
   }
   await h.key('escape');await sleep(500);c.confirmation_closed=!(await nav.visible('settings.confirmation'));c.window_open=await nav.visible('settings.panel');}
  report.panels['settings-confirmation']=c;
  if(!c.opened||c.focus!=='settings.confirmation.cancel'||!c.tab_contained||
    !c.tab_order.includes('settings.confirmation.close')||c.tab_order.at(-1)!==c.focus||
    !c.confirmation_closed||!c.window_open)report.failures.push('settings-confirmation '+JSON.stringify(c));
  await h.key('w',{cmd:true});await sleep(600);
  for(const id of ['settings.confirmation.discard']){if(await nav.visible(id))await nav.click(id);}
  await nav.gone('settings.panel').catch(()=>{});
 }catch(err){report.failures.push('settings '+String((err as any)?.message??err));await shot('settings-error');}
 await settle();
 report.status=report.failures.length?'failed':'passed';
 if(report.failures.length)process.exitCode=1;
}catch(error){report.status='error';report.error=String((error as any)?.stack??error);process.exitCode=1;await shot('failure').catch(()=>{});}
finally{
 if(app.exitCode===null&&app.signalCode===null){await h.request('POST','/zerowork/windows',{action:'quit'}).catch(()=>{});const start=Date.now();
  while(app.exitCode===null&&Date.now()-start<12000){for(const id of ['settings.confirmation.discard','groups.close.accept','local.close.accept','session.close.accept']){try{if((await h.query(id)).filter(shown).length)await h.clickTestId(id)}catch{}}await Promise.race([ended,sleep(150)]);}
  if(app.exitCode===null&&app.signalCode===null){app.kill('SIGTERM');await ended;report.forced_shutdown=true;}}
 if(peer){peer.kill('SIGTERM');await peerLog.close();}
 await log.close();await writeFile(join(out,`report-${variant}.json`),JSON.stringify(report,null,1));await rm(iso,{recursive:true,force:true});
}
console.log(JSON.stringify(report,null,1));
