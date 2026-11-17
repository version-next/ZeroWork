/** Saved-host row hover geometry at the default and a dragged-wider sidebar, then caret positioning and CJK insertion in
 * the host editor's native name Input. Isolated test-mode App, synthetic pointer/keys, no connection.
 * node e2e/input_host_geometry_native.ts OUT [light|dark]   (binary: $ZW_GEOMETRY_BINARY, default zig-out/bin/zerowork)
 *
 * Current contract (re-checked against source):
 * - Host row `sidebar.host` (native Button): name `sidebar.host.name`, right-side `sidebar.host.trailing` (route badge /
 *   hop count `sidebar.host.hops`). Hovering reveals the quick-connect Button `sidebar.host.connect` inside the trailing
 *   area; the name shrinks to make room. The row's hover edit button `sidebar.host.edit` and protocol label
 *   `sidebar.host.protocol` were removed in 7ec0492e: editing is the right-click menu `context.menu.edit_host`.
 * - Sidebar width is dragged on `sidebar.resize`; config.zig accepts 220…480 px.
 * - The editor is its own native window (`wizard.window`, wizard.zig window_spec).
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdir,mkdtemp,open,readFile,writeFile,rm,realpath} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import * as h from '../zig-out/share/zenit/harness/client.ts';
import {openSidebarHostMenu} from './sidebar_host_menu.ts';
const out=resolve(process.argv[2]||'/tmp/zw-input-host'),theme=process.argv[3]||'dark';await mkdir(out,{recursive:true});
assert(['light','dark'].includes(theme),'theme must be light or dark');
const iso=await realpath(await mkdtemp(join(tmpdir(),'zw-input-host-'))),rpc=join(iso,'rpc'),data=join(iso,'data');await mkdir(rpc);await mkdir(data);
await writeFile(join(data,'config.toml'),`[meta]\nconfig_revision=1\n[ui]\ntheme="${theme}"\n`);
await writeFile(join(data,'hosts.toml'),'[registry]\nschema_version=2\nrevision=1\nnext_connection_id=2\nnext_group_id=1\n[[hosts]]\nconnection_id=1\nrevision=1\nprotocol="ssh"\nauth_mode="password"\nname="X40-AI01-long-host"\nhost="192.0.2.1"\nport=22\nuser="root"\nroute=[]\n');
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const log=await open(join(out,'app.log'),'w');
const app=spawn(resolve(process.env.ZW_GEOMETRY_BINARY||'zig-out/bin/zerowork'),[],{env:{...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1'},stdio:['ignore',log.fd,log.fd]});
const ended=new Promise<number|null>(r=>app.once('close',code=>r(code)));
const report:any={status:'running',theme,checks:[],geometry:{}};
const shown=(n:any)=>n&&n.hidden!==true&&n.visible!==false&&(n.effective_opacity??1)>0&&n.rect?.w>0&&n.rect?.h>0;
const get=async(id:string,ms=10000)=>h.waitFor(async()=>(await h.query(id)).find(shown)??null,ms);
const gone=async(id:string)=>h.waitFor(async()=>!(await h.query(id)).some(shown)||null,8000);
const inside=(a:any,b:any)=>a.x>=b.x-.5&&a.y>=b.y-.5&&a.x+a.w<=b.x+b.w+.5&&a.y+a.h<=b.y+b.h+.5;
const ids=['sidebar.host','sidebar.host.name','sidebar.host.trailing','sidebar.host.hops','sidebar.host.connect','sidebar.resize','wizard.name'];
const cap=async(name:string)=>{await h.sleep(150);assert((await h.screenshot(join(out,name+'.png'))).ok);await writeFile(join(out,name+'.json'),JSON.stringify(await Promise.all(ids.map(async id=>({id,nodes:await h.query(id)}))),null,2));};
/** Hover the row and check the revealed quick-connect Button against the row, the name and the trailing area. */
async function hoverRow(label:string){
 await h.mouseMove(600,450);await gone('sidebar.host.connect');
 const rest=await get('sidebar.host'),restName=await get('sidebar.host.name');
 await h.mouseMove(rest.rect.x+10,rest.rect.y+rest.rect.h/2);
 const connect=await get('sidebar.host.connect'),row=await get('sidebar.host'),name=await get('sidebar.host.name'),trailing=await get('sidebar.host.trailing'),hops=await get('sidebar.host.hops');
 assert(inside(connect.rect,row.rect)&&inside(trailing.rect,row.rect)&&inside(name.rect,row.rect),`${label}: name, trailing and the connect button stay inside the row`);
 assert(inside(connect.rect,trailing.rect),`${label}: the connect button belongs to the trailing area`);
 assert(Math.abs(connect.rect.y+connect.rect.h/2-(row.rect.y+row.rect.h/2))<.5,`${label}: connect button is vertically centered in the row`);
 assert(connect.rect.x>=hops.rect.x+hops.rect.w-.5,`${label}: connect button follows the hop badge without overlapping it`);
 assert(name.rect.x+name.rect.w<=trailing.rect.x+.5,`${label}: the name ends before the trailing area (no overlap)`);
 assert(name.rect.w<restName.rect.w-.5,`${label}: the name gives up width for the revealed button`);
 assert(Math.abs(row.rect.w-rest.rect.w)<.5&&Math.abs(row.rect.h-rest.rect.h)<.5,`${label}: hover does not resize the row`);
 report.geometry[label]={row:row.rect,name:name.rect,rest_name:restName.rect,trailing:trailing.rect,hops:hops.rect,connect:connect.rect};
 await cap(label);
 return row;
}
try {
  await h.waitForServerReady(60000);
  await h.resizeWindow(1440,900);
  const narrow=await hoverRow('narrow-hover');
  const grip=await get('sidebar.resize');
  await h.mouseDown(grip.rect.x+4,grip.rect.y+100);
  await h.mouseMove(grip.rect.x+80,grip.rect.y+100);
  await h.mouseMove(grip.rect.x+150,grip.rect.y+100);
  await h.mouseUp(grip.rect.x+150,grip.rect.y+100);
  // Dragged by 146 px: 264 + 146 = 410 is inside config.zig's 220…480 range, so the grip follows the pointer exactly.
  const moved=await h.waitFor(async()=>{const g=(await h.query('sidebar.resize')).find(shown);return g&&Math.abs(g.rect.x-(grip.rect.x+146))<1?g:null},5000);
  const wide=await hoverRow('wide-hover');
  assert(Math.abs(wide.rect.w-narrow.rect.w-(moved.rect.x-grip.rect.x))<1,'the host row widens with the sidebar');
  report.checks.push('Hovered host row reveals its quick-connect button inside the trailing area, centered, with the name shrinking instead of overlapping — at the default and at a dragged-wider sidebar');
  await openSidebarHostMenu();
  await get('context.menu.edit_host');assert((await h.clickTestId('context.menu.edit_host')).ok);
  await get('wizard.window');await get('wizard.name');
  assert((await h.clickTestId('wizard.name')).ok);
  await h.key('a',{cmd:true});
  await h.type_('X40-AI01');
  await h.waitFor(async()=>(await h.inputState('wizard.name')).buffer==='X40-AI01'||null,5000);
  assert.equal((await h.inputState('wizard.name')).cursor_pos,8);
  await cap('input-end');
  await h.key('left');await h.key('left');
  assert.equal((await h.inputState('wizard.name')).cursor_pos,6);
  await cap('input-middle');
  await h.type_('中');
  const inserted=await h.inputState('wizard.name');
  assert.equal(inserted.buffer,'X40-AI中01');assert.equal(inserted.cursor_pos,6+Buffer.byteLength('中'),'caret follows the inserted character');
  await cap('input-insert');
  report.checks.push('Host editor name Input: caret at end and middle (UTF-8 byte offsets), Chinese insertion at the caret');
  // Leave the editor through its own cancel (Escape = the window's close/cancel, wizard.zig windowKey) before quitting the App.
  await h.key('escape');await gone('wizard.window');
  assert(!(await readFile(join(data,'hosts.toml'),'utf8')).includes('X40-AI中01'),'cancelled edit is not saved');
  assert((await h.request('POST','/quit')).ok);report.exit=await Promise.race([ended,h.sleep(20000).then(()=>'timeout')]);assert.equal(report.exit,0,'isolated App quits cleanly');
  report.status='passed';
} catch (error) {
  report.status='failed';report.error=String(error);process.exitCode=1;
  await writeFile(join(out,'failure-tree.json'),JSON.stringify(await h.tree({visibleOnly:true}),null,2)).catch(()=>{});await h.screenshot(join(out,'failure.png')).catch(()=>{});
} finally {
  if(app.exitCode===null&&app.signalCode===null){app.kill('SIGTERM');await Promise.race([ended,h.sleep(3000)]);if(app.exitCode===null&&app.signalCode===null){app.kill('SIGKILL');await ended}}
  await log.close();await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));await rm(iso,{recursive:true,force:true});
}
console.log(JSON.stringify({status:report.status,error:report.error,out}));
