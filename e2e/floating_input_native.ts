/** Floating surface pointer/wheel regression in an isolated native window.
 * node e2e/floating_input_native.ts BINARY OUTPUT_DIR
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdir,mkdtemp,open,readFile,writeFile,rm,realpath} from 'node:fs/promises';
import {join} from 'node:path';
import * as h from '../vendor/zenit/e2e/client.ts';
import {aiToggleId} from './ai_entry.ts';
import {settingsNav} from './settings_nav.ts';
const nav=settingsNav();
const out=process.argv[3]??'/tmp/zerowork-floating-input-evidence';await mkdir(out,{recursive:true});
const iso=await realpath(await mkdtemp('/private/tmp/zw-overlay-audit-')),data=join(iso,'data'),rpc=join(iso,'rpc'),shell=join(iso,'shell');
await Promise.all([mkdir(data),mkdir(rpc),mkdir(shell)]);process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
await writeFile(join(shell,'.zshrc'),"PS1='audit%# '\nbindkey -e\n");
await writeFile(join(data,'config.toml'),'[meta]\nconfig_revision=1\n[ui]\ntheme="dark"\nfont_family="Menlo"\n');
const logPath=join(out,'app.log'),log=await open(logPath,'w');
const app=spawn(process.argv[2],[],{env:{...process.env,ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',ZDOTDIR:shell,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1',ZENIT_DEVTOOLS_HIT_DEBUG:'1'},stdio:['ignore',log.fd,log.fd]});
const ended=new Promise(r=>app.once('close',r));const report={status:'running',cases:[]};
const shown=n=>n.visible!==false&&(n.effective_opacity??1)>0&&n.rect.w>0&&n.rect.h>0;
const vis=id=>h.waitFor(async()=>(await h.query(id)).find(shown)??null,10000);
async function click(id){const n=await vis(id);await h.clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2);await h.sleep(130);}
// The permission control has two forms (chip / compact icon button on narrow tool rows); exactly one is shown.
const permissionControl=()=>h.waitFor(async()=>{for(const id of ['ai.composer.permission','ai.composer.permission.compact'])if((await h.query(id)).some(shown))return id;return null;},10000);
// The application's own Quit (ProcessWindows.requestQuit → each window's close pipeline, which asks first). The
// harness /quit ends the App directly and never shows the close confirmation.
const quit=()=>h.request('POST','/zerowork/windows',{action:'quit'});
const flat=n=>[n,...(n.children??[]).flatMap(flat)];
const hitRect=l=>{const m=/rect=\(([-\d.]+),([-\d.]+),([-\d.]+),([-\d.]+)\)/.exec(l);return m?{x:+m[1],y:+m[2],w:+m[3],h:+m[4]}:null;};
const contains=(a,b)=>a&&a.x<=b.x+0.5&&a.y<=b.y+0.5&&a.x+a.w>=b.x+b.w-0.5&&a.y+a.h>=b.y+b.h-0.5;
const hitId=l=>Number(/(?:pointer_hit|dispatch_scroll_target)=id=(\d+)/.exec(l)?.[1]);
// wheelOwner: the surface's own scroll content that legitimately owns a wheel at this point (default: the surface;
// null: any node of the surface, for a surface whose content scrolls under the point).
async function trace(name,id,dx=5,dy=8,wheelOwner=id){
 const n=await vis(id),point={x:n.rect.x+dx,y:n.rect.y+dy};
 const inside=new Set(flat(n).map(c=>c.id));
 // The native panel around the surface (its own padding takes input): a PopoverContent whose rect holds the surface.
 const panel=l=>/component=PopoverContent /.test(l)&&contains(hitRect(l),n.rect);
 const offset=(await readFile(logPath,'utf8')).length;
 await h.scrollAt(point.x,point.y,0,-18);await h.sleep(100);
 await h.clickAt(point.x,point.y);await h.sleep(130);
 const lines=(await readFile(logPath,'utf8')).slice(offset).split('\n').filter(l=>l.includes('[devtools-hit]'));
 const hits=lines.filter(l=>/pointer_hit=|dispatch_scroll_target=/.test(l));
 assert(hits.some(l=>l.includes('dispatch_scroll_target=')),name+': wheel dispatch captured');
 assert(hits.some(l=>l.includes('pointer_hit=')),name+': pointer hit captured');
 const scrim=name==='local-close-scrim';
 // Every pointer and wheel hit lands in the surface's own subtree or its native panel (the scrim case: on the Modal's scrim).
 // A wheel the layer contains has no target at all (zenit: a wheel aimed at a layer goes to a scroller inside it or
 // to nothing, never below), logged as dispatch_scroll_target=<none>.
 const contained=l=>l.includes('dispatch_scroll_target=<none>');
 for(const l of hits)assert(inside.has(hitId(l))||panel(l)||contained(l)||(scrim&&l.includes('component=Modal ')),name+': input must remain in floating surface: '+l);
 const wheel=hits.find(l=>l.includes('dispatch_scroll_target='));
 assert(wheelOwner===null||wheel.includes('test_id='+wheelOwner+' ')||(wheelOwner===id&&(panel(wheel)||contained(wheel)))||(scrim&&(wheel.includes('component=Modal ')||contained(wheel))),name+': wheel must stop on the expected surface');
 const item={name,id,rect:n.rect,point,focus:await h.focused(),lines};report.cases.push(item);
 await h.screenshot(join(out,name+'.png'));await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));
 console.log(name,lines.filter(l=>/pointer_hit=|dispatch_scroll_target=/.test(l)).join('\n'));
}
try{
 await h.waitForServerReady();await h.resizeWindow(1440,900);await click('workspace.empty.local');await click('terminal.surface');await h.sleep(250);
 await h.type_("printf 'overlay audit\\n'");await h.key('return');await h.sleep(300);
 await click('toolbar.transfers');await trace('transfer-header','transfer.manager',240,8);await trace('transfer-footer','transfer.manager',240,(await vis('transfer.manager')).rect.h-8);await click('transfer.window.close');
 await h.key('k',{cmd:true});await trace('quick-connect-padding','quick.connect',4,80);await h.key('escape');await h.sleep(200);
 await click(await aiToggleId());await trace('ai-side-edge','ai.panel',4,150,'ai.conversation.viewport'); // the conversation runs edge to edge in the floating card
 await click(await permissionControl());await trace('ai-permission-header','ai.permission.menu',8,6);await h.key('escape');await click('ai.collapse');
 await click('toolbar.history');await trace('global-history-header','history.panel',130,8);await click('history.close');await h.sleep(200);
 // Settings is its own window now (its top strip is the native title bar, where no node takes input): the check is
 // that pointer and wheel stay in the settings surface, at a point in its content.
 await nav.open();await trace('settings-window-content','settings.panel',150,(await vis('settings.panel')).rect.h/2,null);await nav.close(); // no close button: Cmd+W (settings_nav.ts)
 await click('toolbar.notifications');await trace('notifications-header','notifications.history',120,8);await click('notifications.history.close');
 await click('terminal.surface');await h.type_('@');await h.sleep(250);await trace('command-catalogue-header','terminal.commands',100,10);await h.key('escape');await h.key('backspace');
 // The close confirmation asks only while a process runs in the local terminal (an idle prompt closes at once).
 await h.type_('/bin/sleep 30');await h.key('return');await h.sleep(500);
 await quit();await trace('local-close-header','local.close.confirmation',180,8);
 // This point is in the modal scrim above the isolated terminal.
 await trace('local-close-scrim','local.close.confirmation',-210,70);
 // Outside click dismisses this dialog. A repeated window-close request may
 // complete the retained close transaction without showing another dialog.
 await quit();await h.sleep(700);
 if(app.exitCode===null&&app.signalCode===null)await click('local.close.accept');
 await h.waitFor(()=>app.exitCode!==null||app.signalCode!==null||null,10000);report.exitCode=await ended;assert.equal(report.exitCode,0);
 report.status='passed';
}catch(e){report.status='failed';report.error=String(e);process.exitCode=1;console.error(e);await h.screenshot(join(out,'failure.png')).catch(()=>{});}
finally{if(app.exitCode===null&&app.signalCode===null)app.kill('SIGTERM');await ended;await log.close();await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));await rm(iso,{recursive:true,force:true});}
