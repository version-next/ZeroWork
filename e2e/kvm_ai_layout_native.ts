/** KVM assistant geometry after a hidden Local assistant, using isolated data.
 * node e2e/kvm_ai_layout_native.ts BINARY OUTPUT_DIR [THEME]   (THEME: light | dark | sauber, default sauber)
 * The KVM endpoint is an intentionally closed loopback port; no device is used.
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdir,mkdtemp,open,writeFile,rm} from 'node:fs/promises';
import {dirname,join,resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {aiToggleId} from './ai_entry.ts';
const binary=resolve(process.argv[2]),out=resolve(process.argv[3]),theme=process.argv[4]??'sauber';
assert(['light','dark','sauber'].includes(theme),`unknown theme ${theme}`);
await mkdir(out,{recursive:true});
const isolated=await mkdtemp('/private/tmp/zw-kvm-ai-');
const data=join(isolated,'data'),rpc=join(isolated,'rpc'),shell=join(isolated,'shell');
await Promise.all([mkdir(data),mkdir(rpc),mkdir(shell)]);
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const h=await import(pathToFileURL(join(dirname(dirname(binary)),'share/zenit/harness/client.ts')).href);
await writeFile(join(shell,'.zshrc'),"PS1='layout%# '\n");
const payload={endpoint:{host:'127.0.0.1',https_port:1},username:'fixture',display:{scale:'fit',read_only_requested:true}};
await writeFile(join(data,'hosts.toml'),'[registry]\nschema_version=2\nrevision=1\nnext_connection_id=2\nnext_group_id=1\n[[hosts]]\nconnection_id=1\nrevision=1\nprotocol="bmc_ikvm"\nname="KVM Layout Fixture"\npayload='+JSON.stringify(JSON.stringify(payload))+'\n');
await writeFile(join(data,'config.toml'),'[meta]\nconfig_revision=1\n[ui]\ntheme="'+theme+'"\n[updates]\nauto_check=false\n');
const log=await open(join(out,'app.log'),'w');
const app=spawn(binary,[],{env:{...process.env,ZEROWORK_DATA_DIR:data,ZDOTDIR:shell,ZEROWORK_AUTOCONNECT:'0',ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1',ZENIT_E2E_ISOLATE_KEYBOARD:'1'},stdio:['ignore',log.fd,log.fd]});
const ended=new Promise(r=>app.once('close',r));
const shown=(n:any)=>n.visible!==false&&!n.hidden&&(n.effective_opacity??1)>0&&n.rect.w>0&&n.rect.h>0;
const visible=(id:string)=>h.waitFor(async()=>(await h.query(id)).find(shown)??null,10000);
const report:any={status:'running',checks:[],limits:['Offline KVM renderer; live device connectivity and physical input are outside this layout check.']};
async function click(id:string){await visible(id);assert((await h.clickTestId(id)).ok,`click ${id}`);await h.sleep(200)}
function inside(inner:any,outer:any,label:string){assert(inner.x>=outer.x-.5&&inner.y>=outer.y-.5&&inner.x+inner.w<=outer.x+outer.w+.5&&inner.y+inner.h<=outer.y+outer.h+.5,label)}
const clamp=(v:number,lo:number,hi:number)=>Math.min(hi,Math.max(lo,v));
// PLUGIN_ARCH_PLAN 2.5.7 / 4c-3 (#52, #59, #62): the panel floats in the window's floating region
// (sidebar right + 8, title bar 44 + 8, window − 8), not inside the KVM content; its first size is
// width clamp(tab content × 0.42, 320, 420) × height clamp(tab content − 24, 280, 640), unfolded at
// the launcher's corner; maximize fills the floating region.
let windowSize={w:1440,h:900};
async function resize(w:number,hh:number){windowSize={w,h:hh};assert((await h.resizeWindow(w,hh)).ok,'resize');}
async function region(){const side=(await h.query('workspace.sidebar')).find(shown);const left=(side?side.rect.x+side.rect.w:0)+8;return {x:left,y:52,w:windowSize.w-8-left,h:windowSize.h-8-52};}
let launcherAtOpen:any=null;
async function openAssistant(){const id=await aiToggleId();if(id==='ai.launcher')launcherAtOpen=(await visible('ai.launcher')).rect;await click(id);}
async function capture(name:string,maximized=false,atLauncher=true){
 await h.sleep(250);
 const content=(await visible('bmc.content')).rect,pane=(await visible('workspace.pane')).rect,area=await region(),panel=(await visible('ai.panel')).rect;
 inside(panel,area,`${name}: assistant stays in the floating region`);
 if(maximized){for(const k of ['x','y','w','h'] as const)assert(Math.abs(panel[k]-area[k])<1,`${name}: maximize fills the floating region (${k} ${panel[k]} vs ${area[k]})`)}
 else {
  assert(Math.abs(panel.w-clamp(pane.w*0.42,320,420))<1,`${name}: width ${panel.w} for pane ${pane.w}`);
  assert(Math.abs(panel.h-clamp(pane.h-24,280,640))<1,`${name}: height ${panel.h} for pane ${pane.h}`);
  if(atLauncher&&launcherAtOpen){const l=launcherAtOpen;assert(Math.abs(panel.x+panel.w-(l.x+l.w))<=4&&Math.abs(panel.y+panel.h-(l.y+l.h))<=4,`${name}: unfolds at the launcher corner ${JSON.stringify(l)} → ${JSON.stringify(panel)}`)}
 }
 for(const id of ['ai.close','ai.prompt','ai.composer.controls'])inside((await visible(id)).rect,panel,`${name}: ${id} stays in assistant`);
 // bugfix-2: every control of the composer row (model selector and send included) stays inside the
 // panel; narrow rows collapse permission / execution into icon buttons instead of overflowing.
 const row=(await visible('ai.composer.controls'));const controls=(row.children??[]).filter(shown);
 assert(controls.length>=5,`${name}: composer row children ${controls.length}`);
 for(const child of controls)inside(child.rect,panel,`${name}: composer control ${child.test_id??child.tag} ${JSON.stringify(child.rect)} stays in assistant`);
 for(const id of ['ai.composer.model','ai.send'])inside((await visible(id)).rect,panel,`${name}: ${id} stays in assistant`);
 const compact={permission:(await h.query('ai.composer.permission.compact')).some(shown),execution:(await h.query('ai.composer.execution.compact')).some(shown)};
 assert(compact.permission!==(await h.query('ai.composer.permission')).some(shown),`${name}: exactly one permission control`);
 assert(compact.execution!==(await h.query('ai.composer.execution')).some(shown),`${name}: exactly one execution control (always shown)`);
 if(compact.execution)assert(compact.permission,`${name}: execution collapses only after permission`);
 if(!maximized&&panel.w<=320.5)assert(compact.permission&&compact.execution,`${name}: 320 panel collapses permission and execution`);
 assert((await h.query('ai.float.resize.se')).some(shown)===!maximized,`${name}: resize state follows maximization`);
 await h.screenshot(join(out,`${name}-${Math.round(panel.w)}-${theme}.png`));
 report.checks.push({name,content,pane,area,panel,compact});
}
try{
 await h.waitForServerReady();await resize(1440,900);await h.sleep(350);
 // The hidden Local assistant is laid out at 100×14 before KVM becomes active.
 await click('workspace.empty.local');await visible('terminal.surface');await h.sleep(350);
 const row=await visible('sidebar.host');await h.clickAt(row.rect.x+65,row.rect.y+row.rect.h/2);await h.key('return');await visible('bmc.content');await h.sleep(600);
 await openAssistant();await capture('opened');
 await click('ai.maximize');await capture('maximized',true);
 await click('ai.maximize');await capture('restored');
 await click('ai.collapse');await openAssistant();await resize(1000,700);await capture('reopened-compact',false,false);
 // Narrow icon buttons carry a native Tooltip "名称 · 当前值".
 const texts=(n:any):string=>(n.text??'')+(n.children??[]).map(texts).join('');
 for(const [id,prefix] of [['ai.composer.permission.compact','执行权限 · '],['ai.composer.execution.compact','当前对话运行方式 · ']]){
  const b=(await visible(id)).rect;await h.mouseMove(b.x+b.w/2,b.y+b.h/2);
  const tip=await visible(id+'.tooltip');assert(texts(tip).startsWith(prefix),`${id} tooltip ${texts(tip)}`);
  report.checks.push({tooltip:id,text:texts(tip)});await h.screenshot(join(out,`tooltip-${id.split('.')[2]}-${theme}.png`));
  await h.mouseMove(b.x+b.w/2,b.y-200);await h.sleep(300);
 }
 const prompt=await visible('ai.prompt');await h.clickAt(prompt.rect.x+30,prompt.rect.y+20);await h.type_('KVM layout draft');assert.equal((await h.inputState('ai.prompt')).buffer,'KVM layout draft');
 await h.request('POST','/quit',{});await Promise.race([ended,h.sleep(700)]);
 if(app.exitCode===null&&app.signalCode===null)await click('local.close.accept');
 await h.waitFor(()=>app.exitCode!==null||app.signalCode!==null||null,10000);assert.equal(app.exitCode,0);
 report.status='passed';
}catch(error){report.status='failed';report.error=String(error);process.exitCode=1;if(app.exitCode===null)await h.screenshot(join(out,'failure.png')).catch(()=>{});console.error(error)}
finally{if(app.exitCode===null&&app.signalCode===null)app.kill('SIGTERM');await ended;await log.close();await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));await rm(isolated,{recursive:true,force:true})}
console.log(`${report.status}: ${out}`);
