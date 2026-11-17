/** Save feedback regression with isolated data, no credentials or HTTP requests. */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdtemp,mkdir,writeFile,readFile,open,realpath} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import * as h from '../vendor/zenit/e2e/client.ts';
import {settingsNav} from './settings_nav.ts';
const binary=resolve(process.argv[2]),out=resolve(process.argv[3]),theme=process.argv[4]??'light';
await mkdir(out,{recursive:true});
const base=await realpath(await mkdtemp(join(tmpdir(),'zw-save-feedback-'))),data=join(base,'data'),rpc=join(base,'rpc');
await mkdir(data);await mkdir(rpc);await writeFile(join(data,'hosts.toml'),'');
const config=join(data,'config.toml');
const initial=`[meta]\nconfig_revision=1\n[updates]\nauto_check=false\n[ui]\ntheme="${theme}"\n[ai]\ndefault_provider="Magpie"\n[[ai.providers]]\nid="Magpie"\nkind="openai_compat"\nendpoint="http://127.0.0.1:3425/v1"\nenabled=true\n[[ai.providers.models]]\nname="existing-model"\ncontext_window=128000\ndefault=true\n[[ai.providers]]\nid="SCNetX"\nkind="openai_compat"\nendpoint="https://example.test/v1"\nenabled=true\n[[ai.providers.models]]\nname="other-model"\ncontext_window=128000\ndefault=true\n`;
await writeFile(config,initial);process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const log=await open(join(out,'app.log'),'w');
const app=spawn(binary,[],{env:{...process.env,ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1'},stdio:['ignore',log.fd,log.fd]});
const ended=new Promise(r=>app.once('close',r));
const shown=(n:any)=>!n.hidden&&n.visible!==false&&(n.effective_opacity??1)>0&&n.rect?.w>0&&n.rect?.h>0;
const flat=(n:any):any[]=>[n,...(n.children??[]).flatMap(flat)],text=(n:any)=>flat(n).map(n=>n.text??'').join(' ');
const node=(id:string)=>h.waitFor(async()=>(await h.query(id)).find(shown)??null);
async function reveal(id:string){const viewport=id.startsWith('settings.ai.model.')?'settings.ai.model.viewport':'settings.viewport';for(let i=0;i<30;i++){const n=await node(id),v=await node(viewport);if(n.rect.y>=v.rect.y&&n.rect.y+n.rect.h<=v.rect.y+v.rect.h)return n;await h.scrollAt(v.rect.x+v.rect.w-4,v.rect.y+v.rect.h/2,0,n.rect.y<v.rect.y?100:-100);await h.sleep(60);}throw Error('Cannot reveal '+id);}
async function click(id:string){if(id.startsWith('settings.ai.provider.')||['settings.ai.model.context','settings.ai.model.reasoning','settings.ai.model.vision'].includes(id))await reveal(id);await node(id);assert((await h.clickTestId(id)).ok,id);await h.sleep(100);}
async function fill(id:string,value:string){await click(id);await h.key('a',{cmd:true});await h.type_(value);}
// Let open / close transitions (the native Modal's scale-fade) finish: a mid-transition frame shows a see-through panel.
async function capture(name:string){await h.mouseMove(20,20);await h.sleep(400);await h.screenshot(join(out,name+'.png'));}
// Settings is its own preferences window now; the global toast (`notifications.toast.0`) is published to the
// main window, which the Harness cannot query while the preferences window is the bound automation window.
// In-window feedback is asserted instead: the exact inline field error, no raw error name, no legacy save banner.
async function feedback(){const n=await node('settings.ai.provider.1.api_key.error');assert(text(n).includes('请填写 API Key，或停用此服务提供方'));assert(!text(n).includes('InvalidDraft'));assert(!(await h.query('settings.save_feedback')).some(shown));assert.equal(text(await node('settings.footer.state')).trim(),'有设置需要修正');return n;}
const report:any={theme,checks:[],status:'running'};
try{
 await h.waitForServerReady();assert.equal(Number(JSON.parse(await readFile(join(rpc,'owner.json'),'utf8')).pid),app.pid);
 await h.resizeWindow(1440,900);await settingsNav().toSub('ai','providers');/* two-level settings (settings_nav.ts) */await click('settings.ai.provider.0.header');await click('settings.ai.provider.0.add_model');
 await fill('settings.ai.model.id','new-model');await fill('settings.ai.model.context','1000000');await click('settings.ai.model.reasoning');await click('settings.ai.model.reasoning.no');await click('settings.ai.model.vision');await click('settings.ai.model.vision.no');await click('settings.ai.model.save');
 await click('settings.save');await feedback();await capture('01-added-model-error');assert.equal(await readFile(config,'utf8'),initial);
 // F-set-ai: locating the problem opens provider 1's detail page (third level) and focuses its API Key field (focus sits inside the native W.Input).
 await click('settings.save');await h.waitFor(async()=>{const t=text((await h.query('settings.page.title')).find(shown)??{}).trim();return t==='SCNetX'||null;});await node('settings.ai.provider.1.api_key');
 await feedback();const inline=await node('settings.ai.provider.1.api_key.error');assert(text(inline).includes('请填写 API Key'));const pane=await node('settings.ai.providers'),viewport=await node('settings.viewport');// Two levels (F-set-ai): the located error is on the provider's detail page, inside the visible viewport.
 assert(inline.rect.y>=viewport.rect.y-.5&&inline.rect.y+inline.rect.h<=Math.min(pane.rect.y+pane.rect.h,viewport.rect.y+viewport.rect.h)+.5);await writeFile(join(out,'located-geometry.json'),JSON.stringify({inline,pane:pane.rect,viewport:viewport.rect},null,2));await capture('02-located-field');
 report.checks.push('Adding a valid model shows the other provider and exact missing field; Save stays clickable and reveals/focuses the collapsed provider without writing invalid data');
 // H-save: the draft belongs to the page it was made on; leaving it asks first (native Modal), and 继续编辑 stays put.
 await click('settings.nav.ssh');{const leave=await node('settings.confirmation');assert(text(leave).includes('SCNetX · API Key'));assert(text(leave).includes('返回修正'));}
 await click('settings.confirmation.cancel');await h.waitFor(async()=>!(await h.query('settings.confirmation')).some(shown)||null);await feedback();
 report.checks.push('Switching category with the invalid draft asks first (names the issue, 返回修正); 继续编辑 keeps the page, the draft and its inline error (Save Bar 有设置需要修正)');
 // The preferences window has no close button any more; Cmd+W is the close request.
 await h.key('w',{cmd:true});const confirmation=await node('settings.confirmation');assert(text(confirmation).includes('SCNetX · API Key'));assert(text(confirmation).includes('返回修正'));await capture('03-close-confirmation');await click('settings.confirmation.save');
 await h.waitFor(async()=>!(await h.query('settings.confirmation')).some(shown)||null);await feedback();assert.equal(await readFile(config,'utf8'),initial);
 report.checks.push('Close confirmation names the issue and returns to correction; no InvalidDraft and no draft loss');
 await h.resizeWindow(860,480);await feedback();const footer=await node('settings.footer'),panel=await node('settings.panel');assert(footer.rect.y+footer.rect.h<=panel.rect.y+panel.rect.h+.5);await capture('04-compact-error');
 await click('settings.ai.provider.1.enabled');await h.waitFor(async()=>!(await h.query('settings.ai.provider.1.api_key.error')).some(shown)||null);await click('settings.save');await h.waitFor(async()=>(await readFile(config,'utf8')).includes('new-model')||null);
 const saved=await readFile(config,'utf8');assert(saved.includes('1000000'));assert(/id\s*=\s*"SCNetX"[\s\S]*?enabled\s*=\s*false/.test(saved));
 // H-save: a committed save hides the Save Bar and confirms with a native toast in the preferences window.
 await h.waitFor(async()=>JSON.stringify(await h.tree()).includes('设置已保存')||null);await h.waitFor(async()=>!(await h.query('settings.footer')).some(shown)||null);await capture('05-saved');
 report.checks.push('Feedback stays visible in the compact preferences window; disabling incomplete non-default provider clears feedback and persists the newly added model; the save toast replaces the Save Bar');report.status='passed';
}catch(e){report.status='failed';report.error=String(e);await capture('failure').catch(()=>{});throw e;}
finally{await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));if(app.exitCode===null)app.kill('SIGTERM');await ended;await log.close();}
