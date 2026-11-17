import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import {openSidebarHostMenu} from './sidebar_host_menu.ts';
/** Sidebar host row: hover exposes only the connect shortcut; route badges, identity and keyboard reach.
 * node e2e/sidebar_hover_native.ts OUTPUT [BINARY] [full|minimum|actions|double|status]
 * Owned /private/tmp data and synthetic public Harness input only.
 *
 * Contract (src/features/shell/view/sidebar_view.zig `HostRow`, sidebar_styles.zig):
 *  - row 28 high (`host_height`, Island B v3 `ZW4 / Project Row`); route badge (icon + hop count) always visible;
 *  - a hot (hovered / focused) unselected row adds one 24pt ▶ (`sidebar.host.connect`, `action_size`) after the route
 *    badge, 4pt from the row's trailing edge (`content()` padding.right); the name keeps its x and gives up exactly the
 *    width the trailing area gained (`updateTrailing`);
 *  - the selected row shows the native “连接” button instead of ▶ (design-r3 A2, `sidebar_host_connect.yix`);
 *  - a click selects, a double click does not connect (A2); clicks on the route badge do nothing (`captureStatusClick`);
 *  - the per-row copy / edit shortcuts were removed in 7ec0492e: the row's only buttons are the connect ones; copy /
 *    edit live in the right-click menu (`context.menu.clone_host` / `context.menu.edit_host`).
 */
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdir,mkdtemp,open,readFile,writeFile,realpath,rm} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import * as h from '../zig-out/share/zenit/harness/client.ts';
import {cleanupOwnedBridgeDirectories} from './native_owned_cleanup.ts';

const out=resolve(process.argv[2]??'/tmp/zerowork-followup-sidebar/native'),binary=resolve(process.argv[3]??'zig-out/bin/zerowork');
await mkdir(out,{recursive:true});
const base=await realpath(await mkdtemp('/private/tmp/zerowork-sidebar-hover-'));
const mode=process.argv[4]??'full';
assert(['full','minimum','actions','double','status'].includes(mode));
const themes=process.env.ZW_SIDEBAR_THEMES?.split(',')??['dark','light','sauber'];
const names=['X40-AI01','production-data-platform-primary-区域-01','files'];
let hosts='[registry]\nschema_version=2\nrevision=1\nnext_connection_id=4\nnext_group_id=1\n';
for(let i=0;i<3;i++)hosts+=`[[hosts]]\nconnection_id=${i+1}\nrevision=1\nprotocol="${i===2?'sftp':'ssh'}"\nauth_mode="password"\nname="${names[i]}"\nhost="127.0.0.1"\nport=1\nuser="fixture"\nroute=${i===1?'[1]':i===2?'[1,2]':'[]'}\n`;

// Design values, with their source.
const ROW_HEIGHT=28;        // sidebar_styles.zig host_height
const ACTION=24;            // sidebar_styles.zig action_size (▶ hit box)
const CONTENT_GAP=8;        // sidebar_styles.zig content(): gap (name → trailing)
const CONTENT_RIGHT=4;      // sidebar_styles.zig content(): padding.right
const TRAILING_GAP=4;       // sidebar_view.zig HostRow trailing box: gap (route badge → ▶)
const SIDEBAR_DEFAULT=264;  // sidebar_model.zig default_width
const SIDEBAR_MINIMUM=220;  // sidebar_model.zig minimum_width
const ROW_BUTTONS=['sidebar.host.connect','sidebar.host.connect_button'];

const report:any={status:'running',mode,binary,sha256:createHash('sha256').update(await readFile(binary)).digest('hex'),themes:[],checks:[],captures:[],limits:['Actual native Metal rendering; public synthetic keyboard/pointer only. Physical keyboard/IME and VoiceOver were not tested.','Connection click uses a runner-owned loopback target on closed port 1 to prove dispatch; SSH authentication is covered separately.']};
let child:any,ended:Promise<unknown>,log:any;
const shown=(n:any)=>n&&n.visible!==false&&n.hidden!==true&&(n.effective_opacity??1)>0&&n.rect.w>0&&n.rect.h>0;
const flat=(n:any):any[]=>n?[n,...(n.children??[]).flatMap(flat)]:[];
const label=(n:any)=>flat(n).map(v=>v.text??'').join('');
const node=async(id:string)=>h.waitFor(async()=>(await h.query(id)).find(shown)??null,15000);
const row=async(index:number)=>(await h.query('sidebar.host')).filter(shown).find(n=>label(n).includes(names[index]))!;
/** The shown descendant (or the node itself) carrying `id`; hidden subtrees do not count. */
const part=(r:any,id:string):any=>{if(!shown(r))return;return r.test_id===id?r:(r.children??[]).map((n:any)=>part(n,id)).find(Boolean);};
const near=(a:number,b:number,s:string)=>assert(Math.abs(a-b)<.25,`${s}: ${a} vs ${b}`);
const right=(r:{x:number,w:number})=>r.x+r.w;

async function clickNode(n:any){assert(shown(n));assert((await h.clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok);}
/** Move the pointer onto a row and wait until that row is hot: an unselected row shows ▶, a selected one keeps “连接”. */
async function hover(index:number){
 const r=await row(index);assert(r,names[index]);
 await h.mouseMove(r.rect.x+12,r.rect.y+r.rect.h/2);
 return h.waitFor(async()=>{const now=await row(index);return part(now,'sidebar.host.connect')||part(now,'sidebar.host.connect_button')?now:null;},5000);
}
/** Move the pointer off the sidebar and wait until no row shows ▶. */
async function leave(){
 await h.mouseMove(700,400);
 await h.waitFor(async()=>(await h.query('sidebar.host.connect')).some(shown)?null:true,5000);
}
async function sessionCount(){return (await h.query('tabs.strip')).flatMap(flat).filter(n=>shown(n)&&/^tabs\.tab\.\d+$/.test(n.test_id??'')).length;}
/** Fails if `happened` turns true within `ms`: the observation window for “nothing else happens”. */
async function never(happened:()=>Promise<boolean>,ms:number,message:string){
 const until=Date.now()+ms;
 while(Date.now()<until){assert(!await happened(),message);await h.sleep(40);}
 assert(!await happened(),message);
}
/** Exactly one new session: the count reaches `before + 1` and stays there. */
async function oneNewSession(before:number,message:string){
 await h.waitFor(async()=>await sessionCount()===before+1||null,15000);
 await never(async()=>await sessionCount()!==before+1,600,message);
}
/** Tab from wherever focus is until it lands on `id` (at most one full cycle of the window's focus ring). */
async function keyboardReach(id:string){
 let focus=await h.focused();
 for(let i=0;i<60&&focus.test_id!==id;i++){assert((await h.key('tab')).ok);focus=await h.focused();}
 assert.equal(focus.test_id,id,'Tab reaches the connect shortcut');
 return focus;
}
async function clean(){
 assert(!(await h.query('connection.progress')).some(shown),'no connection overlay may cover a menu acceptance');
 assert(!(await h.query('plugin.challenge.modal')).some(shown),'no challenge may cover a menu acceptance');
}
/** Hover an unselected row and click its ▶. */
async function connectByShortcut(index:number){
 await clean();
 const r=await hover(index),connect=part(r,'sidebar.host.connect');
 assert(connect,'hover exposes the connect shortcut on an unselected row');
 await clickNode(connect);
}
async function cap(theme:string,state:string){
 const name=theme+'-'+state;
 const ids=['workspace.sidebar','sidebar.host','sidebar.host.name','sidebar.host.hops','sidebar.host.connect','sidebar.host.connect_slot','sidebar.host.info','context.menu','wizard.name','connection.progress'];
 const snapshot=Object.fromEntries(await Promise.all(ids.map(async id=>[id,await h.query(id)])));
 await writeFile(join(out,name+'.json'),JSON.stringify(snapshot,null,2));
 assert((await h.screenshot(join(out,name+'.png'))).ok);
 report.captures.push(name);
}
function identity(r:any){const n=part(r,'sidebar.host.name');assert(n,'host name is visible');return n.rect;}
/** Selected row (design-r3 A2): the native “连接” replaces ▶ at the trailing end, the route badge stays one trailing gap
 * before it, and the name gives up exactly that button's slot. `restingWidth` is the name width while unselected. */
function selectedGeometry(r:any,index:number,restingWidth:number,state:string){
 const n=identity(r),trailing=part(r,'sidebar.host.trailing'),route=part(r,'sidebar.host.route'),slot=part(r,'sidebar.host.connect_slot'),button=part(r,'sidebar.host.connect_button');
 assert(trailing&&route&&slot&&button,state+': the selected row shows its route badge and “连接”');
 assert(!part(r,'sidebar.host.connect'),state+': the selected row shows “连接” instead of ▶');
 assert.equal(part(r,'sidebar.host.hops')?.text,String(index),state+': route count stays visible on the selected row');
 near(right(slot.rect),right(trailing.rect),state+' “连接” closes the trailing area');
 near(right(route.rect)+TRAILING_GAP,slot.rect.x,state+' route badge sits one trailing gap before “连接”');
 near(right(n)+CONTENT_GAP,trailing.rect.x,state+' selected name ends at the trailing area');
 near(right(trailing.rect),right(r.rect)-CONTENT_RIGHT,state+' selected trailing area ends at the row inset');
 assert(button.rect.y>=r.rect.y-.25&&button.rect.y+button.rect.h<=r.rect.y+r.rect.h+.25,state+': “连接” fits the row height');
 near(restingWidth-n.w,slot.rect.w+TRAILING_GAP,state+' identity yields only the “连接” slot');
}

/** Row invariants in any state. `hot` is the index of the hovered row, or null when the pointer is off the list. */
async function stable(before:any[],state:string,hot:number|null){
 const rows=await Promise.all(names.map((_,i)=>row(i)));
 for(let i=0;i<rows.length;i++){
  const r=rows[i];assert(r,names[i]);
  near(r.rect.h,ROW_HEIGHT,state+' row height');
  const n=identity(r);
  near(n.x,before[i].x,state+' name x');
  assert(n.w>0,state+': identity retains visible space');
  const trailing=part(r,'sidebar.host.trailing'),route=part(r,'sidebar.host.route'),hops=part(r,'sidebar.host.hops'),connect=part(r,'sidebar.host.connect');
  assert(trailing&&route&&hops,state+': route badge remains visible');
  assert.equal(hops.text,String(i),'route count matches fixture');
  // The name ends exactly one content gap before the trailing area: no overlap and no hole, whatever the trailing area shows.
  near(right(n)+CONTENT_GAP,trailing.rect.x,state+' name ends at the trailing area');
  near(right(trailing.rect),right(r.rect)-CONTENT_RIGHT,state+' trailing area ends at the row inset');
  // 7ec0492e removed the copy / edit shortcuts: the only buttons a row may show are the connect ones.
  const buttons=flat(r).filter(v=>v!==r&&shown(v)&&v.tag==='button').map(v=>v.test_id);
  assert.deepEqual(buttons.filter(id=>!ROW_BUTTONS.includes(id)),[],state+': the row exposes no shortcut besides connect');
  if(i===hot){
   assert(connect,state+': the hovered row exposes connect');
   near(connect.rect.w,ACTION,'connect hit width');near(connect.rect.h,ACTION,'connect hit height');
   assert(connect.rect.x>=right(n)-.25,'connect never overlaps identity');
   near(right(connect.rect),right(r.rect)-CONTENT_RIGHT,'connect sits at the row inset');
   near(right(route.rect)+TRAILING_GAP,connect.rect.x,'route remains beside connect');
   // The identity gives up exactly the ▶ slot (action + gap) while hot, nothing more.
   near(before[i].w-n.w,ACTION+TRAILING_GAP,state+' identity yields only the connect slot');
  }else{
   assert(!connect,state+': only the hovered row exposes connect');
   near(n.w,before[i].w,state+' resting identity width');
  }
 }
}
async function launch(theme:string){
 const data=join(base,'data-'+theme);await mkdir(data);await writeFile(join(data,'hosts.toml'),hosts);
 const rpc=join(base,'rpc-'+theme);await mkdir(rpc);process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
 await writeFile(join(data,'config.toml'),`[meta]\nconfig_revision=1\n[ui]\ntheme="${theme}"\nfont_family="Menlo"\nfont_size=14\n`);
 log=await open(join(out,theme+'.log'),'w');
 child=spawn(binary,[],{env:{...process.env,ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1'},stdio:['ignore',log.fd,log.fd]});
 ended=new Promise(r=>child.once('close',r));
 await h.waitForServerReady(20000);
 assert.equal(Number(JSON.parse(await readFile(join(rpc,'owner.json'),'utf8')).pid),child.pid);
 await h.resizeWindow(1280,720);
 await h.waitFor(async()=>(await h.query('sidebar.host')).filter(shown).length===names.length||null,15000);
}
async function stop(){if(child?.exitCode===null){child.kill('SIGTERM');await ended;}if(child)await cleanupOwnedBridgeDirectories(child.pid);await log?.close();}
try{
 for(const theme of themes){
  if(mode==='actions'&&!['dark','light','sauber'].includes(theme))continue;
  await launch(theme);
  if(mode==='status'){
   // Clicks on the route badge (icon, count, the gap before ▶) are swallowed: no session and no selection.
   const sessions=await sessionCount();
   for(const area of ['icon','count','gap']){
    const r=await hover(0),route=part(r,'sidebar.host.route'),count=part(r,'sidebar.host.hops'),connect=part(r,'sidebar.host.connect');
    assert(route&&count&&connect);
    const x=area==='icon'?route.rect.x+4:area==='count'?count.rect.x+count.rect.w/2:(right(route.rect)+connect.rect.x)/2;
    assert((await h.clickAt(x,route.rect.y+route.rect.h/2)).ok);
    await never(async()=>await sessionCount()!==sessions,300,area+' status click must not create a session');
    assert(!part(await row(0),'sidebar.host.connect_button'),area+' status click must not select the row');
    await clean();
   }
   await cap(theme,'status-clicks-no-connection');
   await connectByShortcut(0);
   await oneNewSession(sessions,'connect opens exactly one session');
   await cap(theme,'status-then-connect');
   report.checks.push(theme+': route icon, count and gap create no session; explicit connect creates exactly one');
   report.themes.push({theme});await stop();continue;
  }
  if(mode==='double'){
   // design-r3 A2: a double click only selects (no session); the selected row's “连接” then opens exactly one.
   await leave();
   const sessions=await sessionCount(),r=await row(0),resting=identity(r).w; // unselected, pointer off the list
   assert((await h.clickAt(r.rect.x+50,r.rect.y+r.rect.h/2,2)).ok);
   const button=await h.waitFor(async()=>part(await row(0),'sidebar.host.connect_button')??null,5000);
   await never(async()=>await sessionCount()!==sessions,700,'a native double click selects the host and opens no session');
   await leave();
   selectedGeometry(await row(0),0,resting,'double click');
   await cap(theme,'double-click-selects');
   await clickNode(button);
   await oneNewSession(sessions,'“连接” on the selected row opens exactly one session');
   await cap(theme,'double-click-then-connect');
   report.themes.push({theme,sessions:1});await stop();console.log('PASS double-click sidebar',theme);continue;
  }
  if(mode==='minimum'){
   const grip=await node('sidebar.resize');
   await h.mouseDown(grip.rect.x+grip.rect.w/2,grip.rect.y+60);await h.mouseMove(grip.rect.x-120,grip.rect.y+60);await h.mouseUp(grip.rect.x-120,grip.rect.y+60);
   await h.waitFor(async()=>Math.abs((await node('workspace.sidebar')).rect.w-SIDEBAR_MINIMUM)<.25||null,5000);
  }
  await leave();
  const before=await Promise.all(names.map(async(_,i)=>identity(await row(i))));
  assert.deepEqual(await Promise.all(names.map(async(_,i)=>part(await row(i),'sidebar.host.hops')?.text)),['0','1','2'],'all route badges visible at rest');
  near((await node('workspace.sidebar')).rect.w,mode==='minimum'?SIDEBAR_MINIMUM:SIDEBAR_DEFAULT,'sidebar width');
  await stable(before,'idle',null);await cap(theme,'idle');
  await hover(0);await stable(before,'short hover',0);await cap(theme,'short-hover');
  await hover(1);await stable(before,'long hover',1);await cap(theme,'long-hover');
  // The full identity (name, address, route) stays reachable: hovering the name opens the host tooltip.
  const long=await row(1),name=part(long,'sidebar.host.name');
  await h.mouseMove(name.rect.x+Math.min(30,name.rect.w/2),name.rect.y+name.rect.h/2);
  const info=await node('sidebar.host.info');
  assert(label(info).includes(names[1]),'identity tooltip carries the full host name: '+label(info));
  assert(label(info).includes('127.0.0.1'),'identity tooltip carries the address: '+label(info));
  await cap(theme,'identity-tooltip');
  // design-r3 C2 (191f6aa6): the sidebar stays expanded in a narrow window, with the same row layout.
  await h.resizeWindow(860,480);
  await h.waitFor(async()=>Math.abs((await node('workspace.sidebar')).rect.h-480)<1||null,5000); // the sidebar spans the window height
  near((await node('workspace.sidebar')).rect.w,mode==='minimum'?SIDEBAR_MINIMUM:SIDEBAR_DEFAULT,'sidebar keeps its width in a narrow window');
  await hover(1);await stable(before,'compact hover',1);await cap(theme,'compact-hover');
  if(['dark','light','sauber'].includes(theme)){
   const sessions=await sessionCount();
   await hover(0);
   const focus=await keyboardReach('sidebar.host.connect');
   const reached=part(await row(0),'sidebar.host.connect');
   assert(reached&&reached.id===focus.id,'keyboard focus is on the hovered row’s connect shortcut');
   // Copy / edit moved to the right-click menu (7ec0492e). A right click also selects its row (workspace.zig
   // `onSidebarMenu`), so the menu is opened on another row and row 0 keeps its ▶.
   await openSidebarHostMenu(await row(1));
   for(const id of ['context.menu.new_tab','context.menu.clone_host','context.menu.edit_host'])await node(id);
   assert((await h.key('escape')).ok);
   await h.waitFor(async()=>(await h.query('context.menu')).some(shown)?null:true,5000);
   assert.equal(await sessionCount(),sessions,'opening and dismissing the host menu creates no session');
   const picked=await row(1);
   selectedGeometry(picked,1,before[1].w,'right-click selection');
   assert(!part(await row(0),'sidebar.host.connect_button'),'the other rows stay unselected');
   await connectByShortcut(0);
   await oneNewSession(sessions,'connect shortcut opens exactly one session');
   await cap(theme,'connect-dispatched');
   report.checks.push(theme+': independent connect shortcut creates exactly one target session');
  }
  report.themes.push({theme,nameWidths:before.map(r=>r.w),states:['idle','short-hover','long-hover','identity-tooltip','compact-hover']});
  await stop();console.log('PASS sidebar',theme);
 }
 report.status='passed';
 if(mode!=='status'&&mode!=='double')report.checks.push('All route badges remain visible, the row exposes no shortcut besides connect and the full identity tooltip is retained.');
}catch(error){report.status='failed';report.error=String(error);console.error(error);await h.screenshot(join(out,'failure.png')).catch(()=>{});}
finally{await stop().catch(()=>{});await rm(base,{recursive:true,force:true});report.cleanup={isolated_removed:true};await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));}
if(report.status!=='passed')process.exitCode=1;
