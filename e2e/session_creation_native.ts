/** Production V3 creation menu and its existing quick-connect/wizard destinations. */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdir,mkdtemp,realpath,copyFile,readFile,writeFile,open} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import net from 'node:net';
import {waitForServerReady,waitFor,query,clickAt,mouseMove,key,type_,resizeWindow,screenshot,sleep,focused,windows} from '../zig-out/share/zenit/harness/client.ts';
import {settingsNav} from './settings_nav.ts';
const nav=settingsNav();
const themeCycle=process.argv[4]==='--theme-cycle',menuOnly=process.argv[4]==='--menu-only'||themeCycle;assert(!process.argv[4]||menuOnly);
const out=resolve(process.argv[2]),theme=process.argv[3]??'dark';assert(['dark','light'].includes(theme));await mkdir(out,{recursive:false});
const iso=await realpath(await mkdtemp(join(tmpdir(),'zw-v3-creation-'))),data=join(iso,'data'),rpc=join(iso,'rpc'),shell=join(iso,'shell');await Promise.all([mkdir(data),mkdir(rpc),mkdir(shell)]);
await writeFile(join(shell,'.zshrc'),"bindkey -e\nPS1='V3-create%# '\n");
const reserve=net.createServer();await new Promise<void>(r=>reserve.listen(0,'127.0.0.1',r));const port=(reserve.address() as net.AddressInfo).port;await new Promise<void>(r=>reserve.close(()=>r()));
await writeFile(join(data,'config.toml'),`[meta]\nconfig_revision=1\n[ui]\ntheme="${theme}"\nfont_family="Menlo"\nfont_size=14\n`);
await writeFile(join(data,'hosts.toml'),`[registry]\nschema_version=2\nrevision=1\nnext_connection_id=3\nnext_group_id=1\n[[hosts]]\nconnection_id=1\nrevision=1\nprotocol="ssh"\nauth_mode="password"\nname="Owned SSH search"\nhost="127.0.0.1"\nport=${port}\nuser="fixture"\n[[hosts]]\nconnection_id=2\nrevision=1\nprotocol="sftp"\nauth_mode="password"\nname="Owned SFTP search"\nhost="127.0.0.1"\nport=${port}\nuser="fixture"\n`);
await copyFile('zig-out/bin/zerowork',join(iso,'zerowork'));await copyFile('zig-out/bin/zw_ipc.so',join(iso,'zw_ipc.so'));
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;const log=await open(join(out,'app.log'),'w');const app=spawn(join(iso,'zerowork'),[],{env:{...process.env,ZDOTDIR:shell,ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1'},stdio:['ignore',log.fd,log.fd]});const ended=new Promise(r=>app.once('close',r));
const report:any={status:'running',theme,pid:app.pid,isolated:iso,sha256:createHash('sha256').update(await readFile(join(iso,'zerowork'))).digest('hex'),checks:[],captures:[],menus:[],limits:['Actual native Metal window with public Harness input.','Own loopback refusal only; no external authentication.']};
const shown=(n:any)=>n&&n.hidden!==true&&n.visible!==false&&(n.effective_opacity??1)>0&&n.rect?.w>0&&n.rect?.h>0;
const flat=(n:any):any[]=>[n,...(n.children??[]).flatMap(flat)];const text=(n:any)=>flat(n).map(x=>x.text??'').join(' ');
// While an editor window is open the Harness is bound to it; a query for an id of a window that has just closed
// can answer with an error object instead of a list.
const nodes=async(id:string):Promise<any[]>=>{const q=await query(id);return Array.isArray(q)?q:[]};
const current=async(id:string)=>(await nodes(id)).find(shown)??null;
const vis=(id:string)=>{report.awaiting='visible '+id;return waitFor(()=>current(id),12000)};
const hidden=(id:string)=>{report.awaiting='hidden '+id;return waitFor(async()=>!(await nodes(id)).some(shown)||null,12000)};
/** Centre of a node once its rect is the same on two consecutive polls (menus / windows still settling). */
async function settled(id:string){let prior='';report.awaiting='settled '+id;return waitFor(async()=>{const n=await current(id);if(!n)return null;const at=JSON.stringify(n.rect);const same=at===prior;prior=at;return same?n:null},12000)}
async function click(id:string){const n=await settled(id);await mouseMove(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2);assert((await clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok,id)}
async function edit(id:string,value:string){await click(id);await key('a',{cmd:true});await type_(value)}
async function count(){const strips=await nodes('tabs.strip');return strips.filter(shown).flatMap(flat).filter(n=>/^tabs\.tab\.\d+$/.test(n.test_id??'')).length}
/** Only the main window is left (every editor window closed). */
async function mainOnly(){report.awaiting='editor window closed';await waitFor(async()=>{const w=(await windows()).windows;return w.length===1&&w[0].bound?true:null},12000)}
async function capture(name:string,keepPointer=false){if(!keepPointer){await mouseMove(20,80);await sleep(180);}assert((await screenshot(join(out,name+'.png'))).ok);const observed:any={};for(const id of ['workspace.empty','workspace.empty.icon','workspace.empty.local','workspace.empty.choose','workspace.titlebar','workspace.pane','toolbar.new_session','session.menu','session.menu.local','session.menu.empty','session.menu.saved','session.menu.more','session.menu.new_profile','session.menu.new_sftp','session.menu.new_kvm','quick.query','quick.saved.row','wizard.window','wizard.cancel'])observed[id]=await nodes(id);await writeFile(join(out,name+'.json'),JSON.stringify(observed,null,2));report.captures.push(name)}

// 新建会话菜单 (src/features/workspace/view/session_menu.zig, 372c5a87 “every menu is the native Menu through
// app_menu”): a native zenit Menu, so its width follows its content (no fixed 240 any more) and its rows are the
// zenit MenuRow recipe (vendor/zenit/src/ui/components/menu/styles.yss): item 28, header 24, separator 4+1+4,
// list padding 4, row padding 8. Panel at `bottom_start` of the “+” anchor with the menu offset 4
// (menu/mod.zig `.offset = 4`); session_menu.zig anchorRect stretches the anchor down to the title bar's bottom.
const ROW=28,HEADER=24,SEPARATOR=9,LIST_PAD=4,ROW_PAD=8,OFFSET=4;
/** Declared order (session_menu.zig declare): 本地终端 · 最近（≤3，或“暂无…”）· 更多 › | 快捷连接 · 新建主机 · 新建 SFTP · 新建 KVM. */
function expectedRows(recent:string[]){return [['MenuItem','本地终端'],...(recent.length?recent.map(n=>['MenuItem',n]):[['MenuItem','暂无最近使用的主机']]),['MenuItem','更多'],['MenuSeparator',''],['MenuHeader','快捷连接'],['MenuItem','新建主机'],['MenuItem','新建 SFTP'],['MenuItem','新建 KVM']]}
const HEIGHT:Record<string,number>={MenuItem:ROW,MenuHeader:HEADER,MenuSeparator:SEPARATOR};
/** The menu's rows, in order. The “更多” row is the nested Menu's trigger, wrapped in a host box: report its MenuItem. */
function menuRows(panel:any){
 return panel.children[0].children.map((row:any)=>{
  const item=row.component?row:flat(row).find((n:any)=>n.component==='MenuItem');
  return {component:item.component,label:text(item).replace(/\s+/g,' ').trim(),row:row.rect,item:item.rect,test_id:item.test_id,content:item.children?.[0]?.rect};
 });
}
let menuWidth=0;
async function menu(width:number,height:number,recent:string[]=[]){
 await resizeWindow(width,height);await click('toolbar.new_session');
 const anchor=await vis('toolbar.new_session'),bar=await vis('workspace.titlebar');const panel=await settled('session.menu');
 assert.equal(panel.component,'PopoverContent');
 // Keyboard focus moves into the native menu (session_menu.zig show: “焦点进入菜单”).
 report.awaiting='menu focus';await waitFor(async()=>(await focused()).test_id==='session.menu'||null,12000);
 // Placement: bottom_start of the “+” button, one menu offset below the title bar, wholly inside the window.
 assert(Math.abs(panel.rect.x-anchor.rect.x)<.5,'menu left edge on the + button: '+JSON.stringify([panel.rect,anchor.rect]));
 assert(Math.abs(panel.rect.y-(bar.rect.y+bar.rect.h+OFFSET))<.5,'menu one offset below the title bar');
 assert(panel.rect.x>=0&&panel.rect.x+panel.rect.w<=width&&panel.rect.y+panel.rect.h<=height,'menu inside the window');
 const rows=menuRows(panel);report.menus.push({width,height,panel:panel.rect,rows});
 assert.deepEqual(rows.map((r:any)=>[r.component,r.label]),expectedRows(recent));
 // Rows stack without gaps inside the list padding; every row has its recipe height and the panel's inner width.
 let y=panel.rect.y+LIST_PAD;
 for(const r of rows){
  assert(Math.abs(r.row.y-y)<.5,r.label+' row starts where the previous ended');assert.equal(r.row.h,HEIGHT[r.component],r.label+' row height');
  assert(Math.abs(r.row.x-(panel.rect.x+LIST_PAD))<.5&&Math.abs(r.row.w-(panel.rect.w-2*LIST_PAD))<.5,r.label+' row spans the panel');
  // Content-sized: the label (and icon) fits inside the row's padding, nothing is clipped.
  if(r.component==='MenuItem')assert(r.content&&r.content.x>=r.item.x+ROW_PAD-.5&&r.content.x+r.content.w<=r.item.x+r.item.w-ROW_PAD+.5,r.label+' label fits its row');
  y+=r.row.h;
 }
 assert(Math.abs(panel.rect.y+panel.rect.h-(y+LIST_PAD))<.5,'panel height = rows + list padding');
 // Width follows the content, not the window: the same at every window size for the same rows.
 if(!recent.length){if(menuWidth)assert.equal(panel.rect.w,menuWidth,'menu width does not depend on the window');else menuWidth=panel.rect.w;}
 for(const id of ['local','new_profile','new_sftp','new_kvm'])assert.equal((await vis('session.menu.'+id)).rect.h,ROW);
 if(await count()===0){
  // Empty workspace (src/app/main_window.zig, shell_styles.emptyGuide / emptyIcon / emptyActions): 88 pt mascot,
  // a 520 pt guide centred in the pane, two native md Buttons (32 high, zenit default) 8 apart, centred.
  const icon=await vis('workspace.empty.icon'),primary=await vis('workspace.empty.local'),secondary=await vis('workspace.empty.choose'),guide=await vis('workspace.empty'),pane=await vis('workspace.pane');
  assert.deepEqual([icon.rect.w,icon.rect.h],[88,88]);assert.equal(guide.rect.w,520);
  assert.equal(primary.component,'Button');assert.equal(secondary.component,'Button');assert.equal(primary.rect.h,32);assert.equal(secondary.rect.h,32);assert.equal(primary.rect.y,secondary.rect.y);
  assert(Math.abs((primary.rect.x+primary.rect.w+8)-secondary.rect.x)<.5,'empty-state actions 8 apart');
  assert(Math.abs((primary.rect.x+secondary.rect.x+secondary.rect.w)/2-(guide.rect.x+guide.rect.w/2))<.5,'empty-state actions centred');
  assert(Math.abs(icon.rect.x+icon.rect.w/2-guide.rect.x-guide.rect.w/2)<.5,'mascot centred');
  assert(Math.abs(guide.rect.x+guide.rect.w/2-pane.rect.x-pane.rect.w/2)<.5);assert(Math.abs(guide.rect.y+guide.rect.h/2-pane.rect.y-pane.rect.h/2)<.5);
  // Saved hosts exist, so the second action is 快速连接 (nav_host.zig syncHomeConnect).
  assert.match(text(primary),/本地终端/);assert.match(text(secondary),/快速连接/);
  const ids={local:primary.id,choose:secondary.id,icon:icon.id};if(report.empty_ids)assert.deepEqual(ids,report.empty_ids);else report.empty_ids=ids;
 }
 return panel;
}
try{
 await waitForServerReady();assert.equal(Number(JSON.parse(await readFile(join(rpc,'owner.json'),'utf8')).pid),app.pid);await menu(1440,900);assert.equal(await count(),0);await capture('01-menu-default');await key('escape');await hidden('session.menu');assert.equal(await count(),0);
 await menu(860,480);await capture('02-menu-minimum');if(!menuOnly){await key('escape');await hidden('session.menu');await click('workspace.empty.choose');await vis('quick.query');assert.equal(await count(),0);await click('quick.close');await hidden('quick.connect');report.checks.push('empty workspace 快速连接 opens the quick selector directly');
 // The + menu has no quick-connect row (83a600af): quick connect is ⌘K / the empty-state action.
 await resizeWindow(860,480);await key('k',{cmd:true});await vis('quick.query');assert.equal(await count(),0);await edit('quick.query','SFTP');await waitFor(async()=>{const rows=(await nodes('quick.saved.row')).filter(shown);return rows.length===1&&text(rows[0]).includes('Owned SFTP search')?true:null});await capture('03-existing-sftp-search');await click('quick.close');await hidden('quick.connect');assert.equal(await count(),0);report.checks.push('quick entry reuses actual saved SFTP search without creating a connection');
 // 新建主机 opens the connection editor window (Island B v3, wizard.zig window_spec); 取消 closes it, no session.
 await menu(1440,900);await click('session.menu.new_profile');await hidden('session.menu');await vis('wizard.window');await vis('wizard.cancel');assert.match(text(await vis('wizard.title')),/新建主机/);await capture('04-existing-wizard');await click('wizard.cancel');await mainOnly();await vis('workspace.titlebar');assert.equal(await count(),0);report.checks.push('new saved connection opens the editor window and cancel creates no session');
 // ⌘K opens the quick selector with keyboard focus; an explicit submit of the saved SSH host makes one attempt.
 await resizeWindow(860,480);await key('k',{cmd:true});await vis('quick.query');report.awaiting='quick selector focus';report.quick_focus=await waitFor(async()=>{const f=await focused();return flat(await vis('quick.query')).some(n=>n.id===f.id)?f:null},12000);await edit('quick.query','SSH');await waitFor(async()=>{const rows=(await nodes('quick.saved.row')).filter(shown);return rows.length===1&&text(rows[0]).includes('Owned SSH search')?true:null});assert.equal(await count(),0);await click('quick.submit');await waitFor(async()=>await count()===1||null,12000);
 // design-r3 稿 1: the refused attempt becomes the tab's failure view (no dismiss button; the tab stays).
 await waitFor(async()=>{const n=await current('connection.progress.failure.alert');return n&&/127\.0\.0\.1/.test(text(n))?true:null},45000);
 // The failure view first counts down its automatic retries (3 attempts); each retry re-presents the card. Continue
 // once it has stopped retrying (“已停止重试”), so the menus below meet the settled view.
 report.awaiting='retries stopped';await waitFor(async()=>{const n=await current('connection.progress.failure');return n&&/已停止重试/.test(text(n))?true:null},45000);report.checks.push('keyboard quick selection and explicit saved submit create exactly one owned SSH attempt');
 // The host just used is now listed under 最近 (session_menu.zig setSaved, at most 3).
 await menu(860,480,['Owned SSH search']);await capture('05-menu-recent');await click('session.menu.local');await hidden('session.menu');await waitFor(async()=>await count()===2||null,12000);await vis('terminal.surface');report.checks.push('recent host listed; local creation opens real PTY in one new tab');
 // Keyboard: Up from the unhighlighted menu wraps to the last action (新建 KVM, the registered BMC editor);
 // Escape cancels that editor window without creating a session.
 await menu(860,480,['Owned SSH search']);await key('up');await key('return');await hidden('session.menu');await vis('bmc.editor');await key('escape');await mainOnly();await vis('workspace.titlebar');assert.equal(await count(),2);report.checks.push('keyboard wraps to the last action (新建 KVM) and cancels without duplicate sessions');
 await menu(860,480,['Owned SSH search']);await mouseMove(450,300);assert((await clickAt(450,300)).ok);await hidden('session.menu');assert.equal(await count(),2);report.checks.push('outside dismissal preserves sessions');
 await menu(860,480,['Owned SSH search']);await key('return');await hidden('session.menu');await waitFor(async()=>await count()===3||null,12000);await capture('06-created-local');report.checks.push('default Enter creates one local session');
 }else{report.checks.push('standard and minimum menu geometry, labels and native icon screenshot');}
 if(themeCycle){
  await key('escape');await hidden('session.menu');
  for(const target of ['light','sauber','dark']){
   await nav.pickTheme(target);await nav.click('settings.save'); // two-level settings (settings_nav.ts): 外观与主题 › 主题
   await waitFor(async()=>new RegExp('theme\\s*=\\s*"'+target+'"').test(await readFile(join(data,'config.toml'),'utf8'))||null,12000);
   await nav.close();await hidden('settings.panel');await menu(860,480);await capture('03-live-theme-'+target);await key('escape');await hidden('session.menu');
  }
  report.checks.push('same running application saves light, Sauber and dark through real settings and reopens creation menu');
 }
 {
  // 更多 › is a native nested Menu. Its row must be a full menu row like its siblings (zenit menu/mod.zig: “Nested
  // rows fill the panel”), and its submenu opens at `right_start` of that row — beside the parent panel, not over it.
  if(await current('session.menu')){await key('escape');await hidden('session.menu');}const panel=await menu(1440,900,menuOnly?[]:['Owned SSH search']);
  const more=menuRows(panel).find((r:any)=>r.test_id==='session.menu.more');
  await mouseMove(more.item.x+12,more.item.y+more.item.h/2);const sub=await settled('session.menu.more.panel');await capture('07-more-submenu',true);
  assert.deepEqual(menuRows(sub).map((r:any)=>r.label),['Owned SSH search','Owned SFTP search']);
  report.more={row:more.row,item:more.item,submenu:sub.rect};
  assert(Math.abs(more.item.w-more.row.w)<.5,'更多 row fills the menu like its sibling rows: '+JSON.stringify(report.more));
  assert(sub.rect.x>=panel.rect.x+panel.rect.w-LIST_PAD-.5,'更多 submenu opens beside the menu, not over it: '+JSON.stringify(report.more));
  report.checks.push('更多 › is a full menu row and its submenu lists every saved host beside the menu');
 }
 report.status='passed';
}catch(e){report.status='failed';report.error=String(e);report.failed_await=report.awaiting;await capture('failure').catch(()=>{});process.exitCode=1}
finally{if(app.exitCode===null&&app.signalCode===null){app.kill('SIGTERM');await Promise.race([ended,sleep(3000)]);if(app.exitCode===null&&app.signalCode===null){app.kill('SIGKILL');await ended}}await log.close();await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));console.log(JSON.stringify({status:report.status,error:report.error,out}))}
