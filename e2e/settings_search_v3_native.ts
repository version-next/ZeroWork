/** Real native Provider configuration; isolated files and no network requests. */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdtemp,mkdir,realpath,writeFile,readFile,open} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {resolve,join} from 'node:path';
import {waitForServerReady,waitFor,query,clickAt,key,type_,inputState,resizeWindow,scrollAt,screenshot,sleep} from '../vendor/zenit/e2e/client.ts';
import {settingsNav,shown as onScreen} from './settings_nav.ts';
const nav=settingsNav();
const [bin,dest,theme='dark']=process.argv.slice(2);assert(bin&&dest&&['dark','light'].includes(theme));
const binary=resolve(bin),out=resolve(dest),iso=await realpath(await mkdtemp(join(tmpdir(),'zw-provider-v3-'))),data=join(iso,'data'),rpc=join(iso,'rpc');await mkdir(out,{recursive:true});await mkdir(data);await mkdir(rpc);process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const config=join(data,'config.toml'),initial=`[meta]\nconfig_revision=1\n[updates]\nauto_check=false\n[ui]\ntheme="${theme}"\nfont_family="Menlo"\nfont_size=14\n[ai]\ndefault_provider="first"\n[[ai.providers]]\nid="first"\nkind="openai_compat"\nendpoint="http://127.0.0.1:9/v1/chat/completions"\nenabled=true\n[[ai.providers.models]]\nname="first-model"\ncontext_window=8192\ndefault=true\n[[ai.providers]]\nid="second"\nkind="ollama"\nendpoint="http://127.0.0.1:9/api/chat"\nenabled=false\n[[ai.providers.models]]\nname="second-model"\ncontext_window=16384\ndefault=true\n`;
await writeFile(config,initial,{mode:0o600});const log=await open(join(out,'app.log'),'w');const app=spawn(binary,[],{env:{...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1',ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',OPENAI_API_KEY:'',ANTHROPIC_API_KEY:''},stdio:['ignore',log.fd,log.fd]});const ended=new Promise<void>(done=>app.once('close',()=>done()));
const report:any={theme,status:'running',checks:[],geometry:{},limits:['No network request or real credential; public Harness synthetic input and actual Metal pixels.','Physical IME and VoiceOver are not covered.']};
const found=async(id:string)=>waitFor(async()=> (await query(id)).find((n:any)=>n.rect.w>0&&n.rect.h>0)??null,10000);
const shown=(n:any)=>n.visible!==false&&(n.effective_opacity??1)>0;
async function reveal(id:string){
 for(let i=0;i<20;i++){
  const n=await found(id),v=await found('settings.viewport');let clip=v.rect;
  const list=(await query('settings.ai.provider_list')).find((x:any)=>x.rect.w>0&&x.rect.h>0);
  if(id.startsWith('settings.ai.provider.')&&list){const top=Math.max(v.rect.y,list.rect.y),bottom=Math.min(v.rect.y+v.rect.h,list.rect.y+list.rect.h);clip={...list.rect,y:top,h:bottom-top};}
  if(n.rect.y>=clip.y&&n.rect.y+n.rect.h<=clip.y+clip.h&&shown(n))return n;
  const direction=n.rect.y<clip.y?180:-180;
  const y=Math.max(v.rect.y+6,Math.min(v.rect.y+v.rect.h-6,clip.y+Math.max(10,clip.h/2)));
  await scrollAt(clip.x+clip.w/2,y,0,direction);await sleep(120);
  const next=await found(id);
  if(Math.abs(next.rect.y-n.rect.y)<.2){await scrollAt(v.rect.x+v.rect.w-6,v.rect.y+v.rect.h/2,0,direction);await sleep(120);}
 }
 throw new Error('Cannot reveal '+id);
}
async function click(id:string){const n=id.startsWith('settings.ai.provider.')?await reveal(id):await found(id);assert((await clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok);await sleep(220);}
async function edit(id:string,value:string){await click(id);await key('a',{cmd:true});if(value)await type_(value);else await key('backspace');await sleep(120);assert.equal((await inputState(id)).buffer,value);}
async function capture(name:string){await sleep(200);assert((await screenshot(join(out,name+'.png'))).ok);}
// H-save: a committed save hides the Save Bar (no standing “所有更改已保存”).
async function save(){await click('settings.save');await waitFor(async()=>(await query('settings.footer')).some(shown)?null:true,10000);}
const enabledProviders=(source:string)=>source.split('[[ai.providers]]').slice(1).map(block=>/enabled\s*=\s*true/.test(block.split('[[ai.providers.models]]')[0]));
const near=(a:number,b:number)=>assert(Math.abs(a-b)<.6,`${a} != ${b}`);
try{
 await waitForServerReady();await resizeWindow(1440,900);await nav.toCategory('appearance'); // two-level settings (settings_nav.ts)
 await edit('settings.search','重连');await found('settings.search.results');await found('settings.ssh.reconnect');await found('settings.notifications.events');await capture('01-cross-category');report.checks.push('one search simultaneously mounts SSH reconnect and notification events');
 await edit('settings.search','error_hint');await found('settings.field.error_hint');assert.equal((await query('settings.field.default_provider')).filter(onScreen).length,0);assert.equal((await query('settings.field.redact_ip')).filter(onScreen).length,0);await capture('02-field-only');report.checks.push('schema search filters unmatched fields in matched section');
 await click('settings.nav.ssh');assert.equal((await inputState('settings.search')).buffer,'');await found('settings.overview.ssh.connection');assert.equal((await query('settings.search.results')).filter(onScreen).length,0);report.checks.push('category navigation clears both controller query and visible search input');
 await click('settings.nav.appearance');assert(!(await query('settings.field.font_size')).some(shown));
 await edit('settings.search','font_size');await found('settings.field.font_size');for(const id of ['font_family','font_weight','line_height'])assert.equal((await query('settings.field.'+id)).filter(onScreen).length,0);await found('settings.field.cursor_style');await found('settings.font.preview');await capture('05-font-field-only');
 // Panes no longer fold (two-level navigation): leaving search via the category nav returns to the overview without the field.
 await click('settings.nav.appearance');assert.equal((await inputState('settings.search')).buffer,'');await found('settings.overview');assert(!(await query('settings.field.font_size')).some(shown));assert.equal(await readFile(config,'utf8'),initial);report.checks.push('custom appearance font_size shows only matching regular field plus source cursor/preview; category nav clears search back to the overview');
 await resizeWindow(860,480);await edit('settings.search','重连');await capture('03-cross-compact');
 // H-save: the Save Bar only exists with unsaved changes; make one in the results (search scope = every field), check it stays put, revert.
 {const f=await found('settings.field.reconnect_max');const v=(await found('settings.viewport')).rect;if(f.rect.y+f.rect.h>v.y+v.h)await scrollAt(v.x+v.w/2,v.y+v.h/2,0,-(f.rect.y-v.y-60));}
 await edit('settings.field.reconnect_max','4');const footer=(await found('settings.footer')).rect;const viewport=(await found('settings.viewport')).rect;await scrollAt(viewport.x+viewport.w/2,viewport.y+viewport.h/2,0,-650);await sleep(160);near((await found('settings.footer')).rect.y,footer.y);await capture('04-cross-compact-scrolled');await click('settings.revert');await waitFor(async()=>(await query('settings.footer')).some(shown)?null:true,5000);report.checks.push('minimum window scroll keeps fixed footer (dirty results; reverted)');
 await click('settings.nav.ai');assert.equal((await inputState('settings.search')).buffer,'');await click('settings.overview.ai.providers');await found('settings.ai.provider_list');report.status='passed_pending_pixel_review';
}catch(e){report.status='failed';report.error=String(e);await capture('failure').catch(()=>{});throw e;}finally{await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));if(app.exitCode===null)app.kill('SIGTERM');await ended;await log.close();}
console.log(JSON.stringify(report));
