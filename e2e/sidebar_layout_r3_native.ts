/**
 * design-r3 sidebar and minimum-window layout (Pencil RDiob: A2 YbvR2, C2 Uzjl7, 稿 2 UNXlN).
 *
 * Real test-mode window, isolated HOME/data/RPC, two saved hosts on a refused loopback port
 * (no transport is opened by these checks):
 * - A2: a row click only selects; the selected row shows the native “连接” button, an unselected
 *   hovered row shows ▶; double click never creates a Tab.
 * - C2: the sidebar stays expanded at 860 × 480 (never collapses by width); the first narrow
 *   frame posts one native info Notification “窗口较窄，可以收起侧栏”, closable; it is not posted
 *   again after a restart on the same data directory; the main window's manual collapse survives
 *   a restart.
 * - 稿 2 split: a left-right split of two Local terminals shares the width equally at 1440 × 900
 *   and is presented top-bottom at 860 × 480 (each card would be < 320), and returns to a row.
 *
 * Usage: node e2e/sidebar_layout_r3_native.ts <build prefix> <out dir> [light|dark]
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdir,mkdtemp,open,readFile,realpath,rm,writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';

const prefix=resolve(process.argv[2]??'zig-out');
const out=resolve(process.argv[3]??'/tmp/zerowork-sidebar-layout-r3');
const theme=process.argv[4]??'light';
assert(['light','dark'].includes(theme));
await mkdir(out,{recursive:true});
const base=await realpath(await mkdtemp(join(tmpdir(),'zw-sidebar-layout-r3-')));
const data=join(base,'data'),rpc=join(base,'rpc');
await mkdir(data,{mode:0o700});await mkdir(rpc,{mode:0o700});
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const h=await import(join(prefix,'share/zenit/harness/client.ts'));
await writeFile(join(data,'config.toml'),`[meta]\nconfig_revision=1\n[updates]\nauto_check=false\n[ui]\ntheme="${theme}"\nfont_family="Menlo"\nfont_size=14\n[ssh]\nreconnect_max=0\nconnect_timeout_sec=2\n`);
await writeFile(join(data,'hosts.toml'),`[registry]\nschema_version=2\nrevision=1\nnext_connection_id=3\nnext_group_id=1\n[[hosts]]\nconnection_id=1\nrevision=1\nprotocol="ssh"\nauth_mode="password"\nname="prod-web-01"\nhost="127.0.0.1"\nport=9\nuser="fixture"\n[[hosts]]\nconnection_id=2\nrevision=1\nprotocol="ssh"\nauth_mode="password"\nname="prod-db-primary"\nhost="127.0.0.1"\nport=9\nuser="fixture"\n`);

const shown=(n:any)=>n&&n.visible!==false&&n.hidden!==true&&(n.effective_opacity??1)>0&&n.rect?.w>0&&n.rect?.h>0;
const flat=(n:any):any[]=>[n,...(n.children??[]).flatMap(flat)];
const current=async(id:string)=>(await h.query(id)).find(shown)??null;
const visible=(id:string,ms=10000)=>h.waitFor(()=>current(id),ms);
const hidden=(id:string,ms=10000)=>h.waitFor(async()=>(await current(id))?null:true,ms);
const report:any={status:'running',theme,checks:[],captures:[],rects:{}};
const save=()=>writeFile(join(out,'report.json'),JSON.stringify(report,null,2));
async function settle(id:string){let prior='',same=0;return h.waitFor(async()=>{const n=await current(id);if(!n)return null;const at=JSON.stringify(n.rect);same=at===prior?same+1:0;prior=at;await h.sleep(60);return same>=2?n:null;});}
async function click(id:string){const n=await settle(id);assert((await h.clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok);await h.sleep(160);}
async function capture(name:string){await h.sleep(400);assert((await h.screenshot(join(out,name+'.png'))).ok);report.captures.push(name);await save();}
const tabs=async()=>flat((await h.query('tabs.strip'))[0]??{}).filter((n:any)=>/^tabs\.tab\.\d+$/.test(n.test_id??'')&&shown(n));
const panes=async()=>flat((await h.query('groups.workspace')).find(shown)??{}).filter((n:any)=>/^groups\.pane\.\d+$/.test(n.test_id??'')&&shown(n));
const hostRows=async()=>(await h.query('sidebar.host')).filter(shown);

let app:any,ended:Promise<void>,log:any;
async function launch(run:string){
 log=await open(join(out,`app-${run}.log`),'w');
 app=spawn(join(prefix,'bin/zerowork'),[],{env:{...process.env,ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1'},stdio:['ignore',log.fd,log.fd]});
 ended=new Promise<void>(r=>app.once('close',()=>r()));
 await h.waitForServerReady(30000);
}
async function quit(){if(app.exitCode===null&&app.signalCode===null)app.kill('SIGTERM');await ended;await log.close();await rm(join(rpc),{recursive:true,force:true});await mkdir(rpc,{mode:0o700});}
const uiState=async()=>{try{return JSON.parse(await readFile(join(data,'ui-state.json'),'utf8'));}catch{return {};}};

try{
 // ---- Run 1: wide window, A2 host connect, left-right split ----
 await launch('1');await h.resizeWindow(1440,900);
 const sidebar=await visible('workspace.sidebar');
 report.rects.sidebar_1440=sidebar.rect;
 const rows=await h.waitFor(async()=>{const r=await hostRows();return r.length>=2?r:null;});
 const nameOf=(row:any)=>flat(row).find((n:any)=>n.test_id==='sidebar.host.name')??row;
 // A2: single and double clicks only select.
 for(const count of [1,2]){const target=nameOf(rows[0]);assert((await h.clickAt(target.rect.x+10,target.rect.y+target.rect.h/2,count)).ok);await h.sleep(250);assert.equal((await tabs()).length,0,'row click must not open a Tab');}
 const connect=await visible('sidebar.host.connect_button');
 assert(connect.rect.y>=rows[0].rect.y&&connect.rect.y+connect.rect.h<=rows[0].rect.y+rows[0].rect.h+0.5,'connect button sits on the selected row');
 assert.equal((await h.query('sidebar.host.connect_button')).filter(shown).length,1,'only the selected row shows 连接');
 report.checks.push('A2: single and double row clicks only select; the selected row shows the native 连接 button');
 // Hovering the unselected row shows ▶ there, not 连接.
 await h.mouseMove(rows[1].rect.x+40,rows[1].rect.y+rows[1].rect.h/2);await h.sleep(300);
 const play=(await h.query('sidebar.host.connect')).filter(shown);
 assert(play.length===1&&play[0].rect.y>=rows[1].rect.y&&play[0].rect.y<rows[1].rect.y+rows[1].rect.h,'hover ▶ on the unselected row');
 report.checks.push('A2: hovering an unselected row shows ▶ in its trailing slot');
 await h.mouseMove(connect.rect.x+connect.rect.w/2,connect.rect.y+connect.rect.h/2);await h.sleep(700);
 await capture(`01-a2-connect-1440-${theme}`);
 // Split: Local terminal + ⌘D.
 await click('workspace.empty.local');await visible('terminal.surface');
 await click('terminal.surface');await h.key('d',{cmd:true});
 const two=await h.waitFor(async()=>{const p=await panes();return p.length===2?p:null;},20000);
 await h.sleep(500);
 const wide=await panes();report.rects.panes_1440=wide.map((p:any)=>p.rect);
 assert(Math.abs(wide[0].rect.y-wide[1].rect.y)<1,'1440: cards in one row');
 assert(Math.abs(wide[0].rect.w-wide[1].rect.w)<=2,'1440: the row shares width equally');
 assert(two.length===2);
 report.checks.push('split: two cards share one row equally at 1440 × 900');
 const before=await uiState();assert(!before.narrow_sidebar_hint_shown,'no hint at a wide window');
 await capture(`02-split-1440-${theme}`);

 // ---- 860 × 480: sidebar stays, split stacks, first-narrow hint ----
 await h.resizeWindow(860,480);await h.sleep(600);
 const narrowSidebar=await visible('workspace.sidebar');report.rects.sidebar_860=narrowSidebar.rect;
 assert(narrowSidebar.rect.w>=200,'C2: sidebar stays expanded at 860 × 480');
 const tip=await visible('notifications.tip',8000);report.rects.tip=tip.rect;
 const tipText=flat(tip).map((n:any)=>n.text??'').join(' ');
 assert(tipText.includes('窗口较窄，可以收起侧栏'),'hint title');
 const narrow=await h.waitFor(async()=>{const p=await panes();return p.length===2&&Math.abs(p[0].rect.x-p[1].rect.x)<1?p:null;},8000);
 report.rects.panes_860=narrow.map((p:any)=>p.rect);
 assert(narrow[0].rect.w>=320&&Math.abs(narrow[0].rect.w-narrow[1].rect.w)<1,'860: stacked cards keep the full width');
 // laneFor: an info message without actions is a bottom-centre native toast, not a top-right card.
 assert(tip.rect.y>480/2,'hint sits in the lower half (bottom-centre toast stack)');
 assert(!(await current('notifications.viewport'))||!flat(await current('notifications.viewport')).some((n:any)=>n.test_id==='notifications.tip'),'hint is not in the top-right card stack');
 report.checks.push('C2: the sidebar stays expanded at 860 × 480 and one native info toast (bottom centre) suggests collapsing it');
 report.checks.push('split: a row that cannot give each card 320 is presented top-bottom');
 await capture(`03-min-window-860-${theme}`);
 assert((await uiState()).narrow_sidebar_hint_shown===true,'hint remembered in the private data directory');
 // A native text toast has no close button: it leaves by itself (8 s).
 await h.mouseMove(20,80);await h.waitFor(async()=>!(await current('notifications.tip'))||null,15000);
 report.checks.push('the hint leaves by itself after its duration');
 // Widening restores the row.
 await h.resizeWindow(1440,900);await h.sleep(600);
 await h.waitFor(async()=>{const p=await panes();return p.length===2&&Math.abs(p[0].rect.y-p[1].rect.y)<1?p:null;},8000);
 report.checks.push('split: widening the window restores the left-right row');
 // Manual collapse is the only way the sidebar hides; it is remembered.
 await h.key('b',{cmd:true});await hidden('workspace.sidebar');
 await h.resizeWindow(860,480);await h.sleep(400);
 assert(!(await current('notifications.tip')),'no second hint');
 await capture(`04-collapsed-860-${theme}`);
 assert.equal((await uiState()).main_sidebar_collapsed,true);
 await quit();

 // ---- Run 2: restart keeps the collapsed sidebar and posts no hint ----
 await launch('2');await h.resizeWindow(860,480);await h.sleep(900);
 assert(!(await current('workspace.sidebar')),'restart keeps the main window sidebar collapsed');
 assert(!(await current('notifications.tip')),'hint is once per device');
 await h.key('b',{cmd:true});await visible('workspace.sidebar');await h.sleep(600);
 assert(!(await current('notifications.tip')),'no hint after the user has collapsed a sidebar');
 assert.equal((await uiState()).main_sidebar_collapsed,false);
 report.checks.push('C2: the main window restores its manual sidebar state after restart; the hint never repeats');
 await quit();
 report.status='passed';
}catch(e){report.status='failed';report.error=String(e);await h.screenshot(join(out,'failure.png')).catch(()=>{});throw e;}
finally{
 await save();
 if(app&&app.exitCode===null&&app.signalCode===null){app.kill('SIGTERM');await ended;}
 await rm(base,{recursive:true,force:true});
}
console.log(JSON.stringify({status:report.status,checks:report.checks.length,out}));
