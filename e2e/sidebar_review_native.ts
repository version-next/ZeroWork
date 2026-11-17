/** Confirmed sidebar/home design: isolated native app, no remote connections.
 * node e2e/sidebar_review_native.ts OUTPUT   (launches zig-out/bin/zerowork)
 *
 * Contract:
 *  - home (src/app/main_window.zig, Pencil hmCmB): native md Buttons “本地终端” (primary) and the second action
 *    (secondary; “快速连接” with saved hosts, “新建主机” without — nav_host.zig), zenit default look, 8pt apart
 *    (shell_styles.zig `emptyActions`). The local terminal is offered here only: the sidebar has no such entry.
 *  - sidebar (sidebar_view.zig / sidebar_model.zig): 264 wide; a hovered row shows only the ▶ connect shortcut (copy /
 *    edit shortcuts removed in 7ec0492e); every routable host shows its hop count; groups collapse independently;
 *    opening a session keeps the sidebar; the title-bar toggle hides and restores it.
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdir,mkdtemp,open,writeFile,rm,realpath} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {waitForServerReady,waitFor,query,clickTestId,clickAt,mouseMove,key,resizeWindow,screenshot} from '../zig-out/share/zenit/harness/client.ts';
import {cleanupOwnedBridgeDirectories} from './native_owned_cleanup.ts';
const output=resolve(process.argv[2]||'artifacts/sidebar-review');
await mkdir(output,{recursive:true});
const shown=(n:any)=>n.visible!==false&&(n.effective_opacity??1)>0&&n.rect.w>0&&n.rect.h>0;
const flat=(n:any):any[]=>[n,...(n.children||[]).flatMap(flat)];
const label=(n:any)=>flat(n).map(x=>x.text||'').join('');
const hashes=['a5c5b0e542d38da7','8ce54dc4a087ff84','88d4d1363bbdb547','19e1705ea4cea828','16e5c76afcf3423c'];
const names=['prod-web-01','prod-db-02','assets','dev-api-02','dev-build-01'];
const os=['ubuntu','debian',process.env.ZW_REVIEW_OS||'linux','fedora','arch'];
const BUTTON_MD=32;        // vendor/zenit/src/ui/components/control_shell/styles.yss: outer heights 20/24/32/40, md = 32 (Button default size)
const HOME_GAP=8;          // shell_styles.zig emptyActions: gap
const SIDEBAR_WIDTH=264;   // sidebar_model.zig default_width
const ROW_BUTTONS=['sidebar.host.connect','sidebar.host.connect_button'];
const report:any={checks:[],captures:[],limitations:['Isolated fixtures; no real remote connection or physical keyboard/IME testing.']};
for(const theme of ['dark','light','empty']){
 const iso=await realpath(await mkdtemp(join(tmpdir(),'zw-sidebar-review-'))),rpc=join(iso,'rpc'),data=join(iso,'data');await mkdir(rpc);await mkdir(join(data,'cache'),{recursive:true});
 await writeFile(join(data,'config.toml'),`[meta]\nconfig_revision=1\n[ui]\ntheme="${theme==='empty'?'dark':theme}"\nfont_family="Menlo"\nfont_size=14\n`);
 let hosts='[registry]\nschema_version=2\nrevision=1\nnext_connection_id=6\nnext_group_id=3\n';
 if(theme!=='empty'){
  hosts+='[[groups]]\ngroup_id=1\nrevision=1\nname="Production"\nordered_connection_ids=[1,2,3]\n[[groups]]\ngroup_id=2\nrevision=1\nname="Development"\nordered_connection_ids=[4,5]\n';
  for(let i=0;i<5;i++){
   hosts+=`[[hosts]]\nconnection_id=${i+1}\nrevision=1\nprotocol="${i===2?'sftp':'ssh'}"\nauth_mode="password"\nname="${names[i]}"\nhost="192.0.2.${10+i}"\nport=22\nuser="demo"\nasset_group_id=${i<3?1:2}\nroute=${i===1?'[1]':i===2?'[1,2]':'[]'}\n`;
   await writeFile(join(data,'cache',`os-${hashes[i]}.txt`),os[i]);
  }
 }
 await writeFile(join(data,'hosts.toml'),hosts);
 process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
 const log=await open(join(output,`${theme}.log`),'w');const child=spawn(resolve('zig-out/bin/zerowork'),[],{env:{...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1'},stdio:['ignore',log.fd,log.fd]});
 const ended=new Promise<void>(done=>child.once('close',()=>done()));
 /** Waits (bounded) for a shown node with this id. */
 const visible=(id:string)=>waitFor(async()=>(await query(id)).find(shown)??null,8000).catch(()=>assert.fail(`${theme}: ${id} visible`));
 const gone=(id:string)=>waitFor(async()=>(await query(id)).some(shown)?null:true,8000).catch(()=>assert.fail(`${theme}: ${id} hidden`));
 const hostRows=async()=>(await query('sidebar.host')).filter(shown);
 const hostCount=(count:number)=>waitFor(async()=>(await hostRows()).length===count||null,8000).catch(async()=>assert.fail(`${theme}: ${count} host rows shown, got ${(await hostRows()).length}`));
 async function capture(name:string){await screenshot(join(output,name+'.png'));await writeFile(join(output,name+'.json'),JSON.stringify(Object.fromEntries(await Promise.all(['workspace.sidebar','sidebar.group.card','sidebar.host','sidebar.host.icon','sidebar.host.hops','workspace.empty.local','workspace.empty.choose'].map(async id=>[id,await query(id)]))),null,2));report.captures.push(name);}
 try{
  await waitForServerReady(15000);await resizeWindow(1440,900);
  const chooseLabel=theme==='empty'?'新建主机':'快速连接';
  // The second action's label follows the host registry once it has loaded.
  const connect=await waitFor(async()=>{const n=(await query('workspace.empty.choose')).find(shown);return n&&label(n).includes(chooseLabel)?n:null;},8000).catch(()=>assert.fail(`${theme}: home action reads ${chooseLabel}`));
  const local=await visible('workspace.empty.local');
  assert(label(local).includes('本地终端'));
  // Two native md buttons on one line: same height (zenit md), same top, 8pt apart, local first.
  assert.equal(local.rect.h,BUTTON_MD,'local is a native md button');assert.equal(connect.rect.h,BUTTON_MD,'second action is a native md button');
  assert.equal(local.rect.y,connect.rect.y,'home buttons share a line');
  assert(Math.abs(connect.rect.x-(local.rect.x+local.rect.w)-HOME_GAP)<.25,`home buttons are ${HOME_GAP}pt apart: ${local.rect.x+local.rect.w} → ${connect.rect.x}`);
  // The pair is centered in the workspace's empty state.
  const guide=await visible('workspace.empty');
  assert(Math.abs((local.rect.x+connect.rect.x+connect.rect.w)/2-(guide.rect.x+guide.rect.w/2))<.75,'home buttons are centered');
  // The local terminal has a single entry (home); the sidebar offers none.
  const sidebarLabels=(await query('workspace.sidebar')).filter(shown).flatMap(flat).filter(shown).map(n=>n.text||'');
  assert(!sidebarLabels.some(text=>text.includes('本地终端')),'the sidebar has no duplicate local-terminal entry');
  await capture(`${theme}-home`);report.checks.push(`${theme}: native md home buttons on one line with the correct action label; no duplicate local entry in the sidebar`);
  await clickTestId('workspace.empty.choose');await visible(theme==='empty'?'wizard.cancel':'quick.connect');
  await capture(`${theme}-home-action`);
  if(theme==='empty'){await clickTestId('wizard.cancel');}
  else{await key('escape');await gone('quick.connect');}
  report.checks.push(`${theme}: home action opens ${theme==='empty'?'new connection':'original quick connection'}`);
  if(theme==='empty')continue;
  const side=await visible('workspace.sidebar');assert.equal(side.rect.w,SIDEBAR_WIDTH);await hostCount(5);
  const row=(await hostRows())[1];await mouseMove(row.rect.x+40,row.rect.y+row.rect.h/2);
  const hovered=await waitFor(async()=>{const now=(await hostRows())[1];return flat(now).some(n=>n.test_id==='sidebar.host.connect'&&shown(n))?now:null;},8000).catch(()=>assert.fail(`${theme}: hover shows the connect shortcut`));
  // 7ec0492e removed the copy / edit shortcuts: connect is the only button a row shows, and only on the hovered row.
  for(const [index,item] of (await hostRows()).entries()){
   const buttons=flat(item).filter(n=>n!==item&&shown(n)&&n.tag==='button').map(n=>n.test_id);
   assert.deepEqual(buttons,index===1?['sidebar.host.connect']:[],`${theme}: row ${index} shortcuts`);
   assert(buttons.every(id=>ROW_BUTTONS.includes(id)));
  }
  assert.equal(hovered.rect.h,row.rect.h,'hover keeps the row height');
  assert.deepEqual((await query('sidebar.host.hops')).filter(shown).map(n=>n.text),['0','1','2','0','0']);await capture(`${theme}-hover`);
  // Groups collapse independently: the first header hides its three hosts only, and brings them back.
  // (The empty default group keeps a hidden header, so the header is picked by its label, not by id order.)
  const production=async()=>{const header=(await query('sidebar.group')).filter(shown).find(n=>label(n).includes('Production'));assert(header,`${theme}: Production group header`);return header;};
  const toggle=async()=>{const header=await production();assert((await clickAt(header.rect.x+header.rect.w/2,header.rect.y+header.rect.h/2)).ok);};
  assert.deepEqual((await query('sidebar.group')).filter(shown).map(n=>['Production','Development'].find(name=>label(n).includes(name))),['Production','Development'],'both groups are listed');
  await toggle();await hostCount(2);
  assert.deepEqual((await hostRows()).map(n=>names.find(name=>label(n).includes(name))),names.slice(3),'collapsing Production leaves Development');
  await toggle();await hostCount(5);
  await clickTestId('workspace.empty.local');await visible('terminal.surface');await visible('workspace.sidebar');await hostCount(5);await capture(`${theme}-local`);
  await clickTestId('sidebar.collapse');await gone('workspace.sidebar');await capture(`${theme}-collapsed`);
  await clickTestId('sidebar.restore');assert.equal((await visible('workspace.sidebar')).rect.w,SIDEBAR_WIDTH,'restore brings the sidebar back at its width');await hostCount(5);
  report.checks.push(`${theme}: colour host fixtures, connect hover action as the only row shortcut, independent groups, local session keeps sidebar, manual sidebar toggle`);
 }catch(e){await writeFile(join(output,'fixture-hosts.toml'),hosts);report.error=String(e);report.status='failed';report.process={exitCode:child.exitCode,signal:child.signalCode,pid:child.pid};await capture(`${theme}-failure`).catch(()=>{});throw e;}
 finally{if(child.exitCode===null)child.kill('SIGTERM');await ended;await log.close();await cleanupOwnedBridgeDirectories(child.pid!);await rm(iso,{recursive:true,force:true});await writeFile(join(output,'report.json'),JSON.stringify(report,null,2));}
}
report.status='passed';await writeFile(join(output,'report.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report,null,2));
