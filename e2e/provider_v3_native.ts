// 迁移说明（F-set-ai 之后）
// 删除提供方行高 46、名称/协议等宽并排与间距 12、地址横跨两列的断言：原生连接设置改为独立行。
// 删除模型行高 44、模型列表固定高 190 及内部滚动断言：模型使用原生设置行并随详情页滚动。
// 删除删除弹窗宽 390 与保存条跨页面固定 y 的断言：原生 Modal 保留默认几何，保存条仅在有草稿时存在；保留紧凑窗口边界与滚动可达性检查。
/** Real native Provider configuration; isolated files and no network requests. */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdtemp,mkdir,realpath,writeFile,readFile,open} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {resolve,join} from 'node:path';
import {waitForServerReady,waitFor,query,clickAt,key,type_,inputState,resizeWindow,scrollAt,screenshot,sleep,tree} from '../vendor/zenit/e2e/client.ts';
import {settingsNav,shown,textOf} from './settings_nav.ts';
const [bin,dest,theme='dark',mode='flows']=process.argv.slice(2);assert(bin&&dest&&['dark','light'].includes(theme));
const binary=resolve(bin),out=resolve(dest),iso=await realpath(await mkdtemp(join(tmpdir(),'zw-provider-v3-'))),data=join(iso,'data'),rpc=join(iso,'rpc');await mkdir(out,{recursive:true});await mkdir(data);await mkdir(rpc);process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const config=join(data,'config.toml'),baseInitial=`[meta]\nconfig_revision=1\n[updates]\nauto_check=false\n[ui]\ntheme="${theme}"\nfont_family="Menlo"\nfont_size=14\n[ai]\ndefault_provider="first"\n[[ai.providers]]\nid="first"\nkind="openai_compat"\nendpoint="http://127.0.0.1:9/v1/chat/completions"\nenabled=true\n[[ai.providers.models]]\nname="first-model"\ncontext_window=8192\ndefault=true\n[[ai.providers]]\nid="second"\nkind="ollama"\nendpoint="http://127.0.0.1:9/api/chat"\nenabled=false\n[[ai.providers.models]]\nname="second-model"\ncontext_window=16384\ndefault=true\n`;
const initial=mode==='empty'?baseInitial.slice(0,baseInitial.indexOf('[ai]')):mode==='stress'?baseInitial.replace('[[ai.providers]]\nid="second"',Array.from({length:8},(_,i)=>`[[ai.providers.models]]\nname="additional-${i+1}"\ncontext_window=128000\ndefault=false\nreasoning=true\nvision=true\n`).join('')+'[[ai.providers]]\nid="second"'):baseInitial;
await writeFile(config,initial,{mode:0o600});const log=await open(join(out,'app.log'),'w');const app=spawn(binary,[],{env:{...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1',ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',OPENAI_API_KEY:'',ANTHROPIC_API_KEY:''},stdio:['ignore',log.fd,log.fd]});const ended=new Promise<void>(done=>app.once('close',()=>done()));
const started=new Promise<void>((ready,fail)=>{app.once('spawn',()=>ready());app.once('error',fail);});
const report:any={theme,status:'running',checks:[],geometry:{},limits:['No network request or real credential; public Harness synthetic input and actual Metal pixels.','Physical IME and VoiceOver are not covered.']};
report.limits.push('删除提供方行高 46、名称/协议等宽并排与间距 12、地址横跨两列的断言：原生连接设置改为独立行。','删除模型行高 44、模型列表固定高 190 及内部滚动断言：模型使用原生设置行并随详情页滚动。','删除删除弹窗宽 390 与保存条跨页面固定 y 的断言：原生 Modal 保留默认几何，保存条仅在有草稿时存在；保留紧凑窗口边界与滚动可达性检查。');
const nav=settingsNav(),found=nav.node,reveal=nav.reveal;
async function click(id:string){
 if(id.startsWith('settings.ai.model.')||id.startsWith('settings.ai.delete.')){
  const n=id.startsWith('settings.ai.model.')&&!/\.(save|cancel|dialog)$/.test(id)?await modelReveal(id):await found(id);
  assert((await clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok,id);await sleep(220);
 }else await nav.click(id);
}
async function modelReveal(id:string){
 if(/\.(yes|no)$/.test(id))return found(id);
 for(let i=0;i<24;i++){
  const n=await found(id),v=await found('settings.ai.model.viewport');
  if(n.rect.y>=v.rect.y&&n.rect.y+n.rect.h<=v.rect.y+v.rect.h)return n;
  await scrollAt(v.rect.x+v.rect.w-4,v.rect.y+v.rect.h/2,0,n.rect.y<v.rect.y?140:-140);await sleep(100);
 }
 throw Error('Cannot reveal '+id);
}
async function edit(id:string,value:string){await click(id);await key('a',{cmd:true});await key('backspace');if(value)await type_(value);await sleep(120);assert.equal((await inputState(id)).buffer,value);}
async function capture(name:string){await sleep(400);assert((await screenshot(join(out,name+'.png'))).ok);}
async function save(expect:(s:string)=>boolean){
 await found('settings.footer');await click('settings.save');
 await waitFor(async()=>expect(await readFile(config,'utf8'))||null,15000);await nav.gone('settings.footer');
}
async function list(){await nav.back();await nav.waitTitle('服务提供方');}
async function provider(index:number,name:string){await click(`settings.ai.provider.${index}.header`);await nav.waitTitle(name);await found(`settings.ai.provider.${index}.endpoint`);}
async function addModel(name:string,context:string){
 await edit('settings.ai.model.id',name);await edit('settings.ai.model.context',context);
 for(const capability of ['reasoning','vision']){await click('settings.ai.model.'+capability);await click('settings.ai.model.'+capability+'.no');}
 await click('settings.ai.model.save');await nav.gone('settings.ai.model.dialog');await found('settings.footer');
}
// The app's dialog id marks its body. Modal's component root owns the full native panel
// (components/modal/mod.zig); include the title bar when checking compact-window bounds.
async function modalInside(id:string,w:number,h:number){
 const contains=(n:any):boolean=>n?.test_id===id||(n?.children??[]).some(contains);
 const panel=(n:any):any=>{
  if(n?.component==='Modal'){const child=(n.children??[]).find(contains);if(child)return child;}
  for(const child of n?.children??[]){const found=panel(child);if(found)return found;}
  return null;
 };
 const native=panel(await tree());assert(native,'Native Modal panel for '+id);inside(native,w,h);
}
function inside(n:any,w:number,h:number){assert(n.rect.x>=0&&n.rect.y>=0&&n.rect.x+n.rect.w<=w+.5&&n.rect.y+n.rect.h<=h+.5);}
const enabledProviders=(source:string)=>source.split('[[ai.providers]]').slice(1).map(block=>/enabled\s*=\s*true/.test(block.split('[[ai.providers.models]]')[0]));
try{
 await started;await waitForServerReady();assert.equal(Number(JSON.parse(await readFile(join(rpc,'owner.json'),'utf8')).pid),app.pid);
 await resizeWindow(1440,900);await nav.open();await nav.toSub('ai','providers');
 if(mode==='empty'){
  await found('settings.ai.providers.empty');assert(!(await query('settings.ai.provider.0.header')).some(shown));await capture('10-empty-standard');
  await click('settings.ai.providers.empty.add');await edit('settings.ai.provider.0.name','local gateway');await edit('settings.ai.provider.0.endpoint','http://127.0.0.1:9/v1/chat/completions');
  await click('settings.ai.provider.0.add_model');await addModel('first-manual-model','128000');assert.equal(await readFile(config,'utf8'),initial);await save(s=>s.includes('first-manual-model'));
  const firstSaved=await readFile(config,'utf8');assert(firstSaved.includes('local gateway'));await list();await click('settings.ai.add_provider');
  await edit('settings.ai.provider.1.name','second gateway');await edit('settings.ai.provider.1.endpoint','http://127.0.0.1:9/v1/chat/completions');await click('settings.ai.provider.1.add_model');await addModel('second-manual-model','64000');assert.equal(await readFile(config,'utf8'),firstSaved);
  await save(s=>s.includes('second-manual-model'));const twoSaved=await readFile(config,'utf8');assert.equal((twoSaved.match(/kind = "openai_compat"/g)||[]).length,2);assert(twoSaved.includes('local gateway')&&twoSaved.includes('second gateway')&&twoSaved.includes('first-manual-model'));
  report.checks.push('Fresh install empty list; two same-protocol providers keep separate names/models; child Save changes draft only and outer Save persists');
  await list();await provider(1,'second gateway');await list();await provider(0,'local gateway');await list();await resizeWindow(860,480);await capture('11-two-providers-compact');
  await click('settings.ai.add_provider');await edit('settings.ai.provider.2.name','uncommitted');await click('settings.revert');await nav.gone('settings.footer');assert.equal(await readFile(config,'utf8'),twoSaved);
  await nav.toSub('ai','providers');assert(!(await query('settings.ai.provider.2.header')).some(shown));await found('settings.ai.provider.0.header');await found('settings.ai.provider.1.header');report.checks.push('Third provider outer Revert removes draft and preserves both saved entries');
 }else{
  const header=await found('settings.ai.provider.0.header');assert(textOf(header).includes('first'));await provider(0,'first');
  for(const suffix of ['enabled','name','kind','endpoint','api_key'])await found('settings.ai.provider.0.'+suffix);
  assert.equal((await inputState('settings.ai.provider.0.name')).buffer,'first');await capture('01-provider-standard');report.checks.push('Provider list opens a named detail page with native connection fields');
  if(mode==='stress'){
   for(let i=0;i<9;i++)assert(textOf(await found(`settings.ai.provider.0.model.${i}.header`)).includes(i===0?'first-model':`additional-${i}`));
   await reveal('settings.ai.provider.0.model.0.card');await capture('06-many-models-standard');await reveal('settings.ai.provider.0.model.8.card');await capture('07-many-models-scrolled');
   await resizeWindow(860,480);const last=await reveal('settings.ai.provider.0.model.8.card');inside(last,860,480);await capture('08-many-models-compact');report.checks.push('All nine models exist and the last model is reachable through the page scroll in standard and compact windows');
  }else{
   // Native Button exports focusability; protected default provider deletion is disabled.
   assert(!(await found('settings.ai.provider.0.delete_provider')).focusable);await click('settings.ai.provider.0.enabled');assert.equal(await readFile(config,'utf8'),initial);assert(textOf(await found('settings.ai.provider_error')).includes('默认替代项'));await nav.gone('settings.footer');await capture('02-last-default-protected');report.checks.push('Last enabled default cannot be disabled or deleted');
   await list();await provider(1,'second');await click('settings.ai.provider.1.enabled');assert.equal(await readFile(config,'utf8'),initial);await save(s=>enabledProviders(s).filter(Boolean).length===2);let saved=await readFile(config,'utf8');assert(/default_provider\s*=\s*"first"/.test(saved));
   await list();await provider(0,'first');await click('settings.ai.provider.0.enabled');await save(s=>/default_provider\s*=\s*"second"/.test(s)&&enabledProviders(s).filter(Boolean).length===1);saved=await readFile(config,'utf8');report.checks.push('Enable persists; disabling default selects an eligible replacement');
   await edit('settings.ai.provider.0.endpoint','not-a-url');await found('settings.ai.provider.0.endpoint.error');await key('escape');await waitFor(async()=>{const st=await inputState('settings.ai.provider.0.endpoint').catch(()=>null);const shownText=textOf(await found('settings.ai.provider.0.endpoint'));return (st?.buffer==='http://127.0.0.1:9/v1/chat/completions'||shownText.includes('http://127.0.0.1:9/v1/chat/completions'))||null;},5000).catch(async()=>{throw new Error('Escape did not restore the committed endpoint: buffer='+JSON.stringify((await inputState('settings.ai.provider.0.endpoint').catch(()=>({}))))+' text='+textOf(await found('settings.ai.provider.0.endpoint')))});await nav.gone('settings.ai.provider.0.endpoint.error');
   await edit('settings.ai.provider.0.name','first draft');await found('settings.footer');await click('settings.revert');await nav.gone('settings.footer');assert.equal((await inputState('settings.ai.provider.0.name')).buffer,'first');assert.equal(await readFile(config,'utf8'),saved);report.checks.push('Inline endpoint validation and Escape restore input; outer Revert restores name without changing persisted disabled provider');
   assert.equal((await inputState('settings.ai.provider.0.api_key')).input_type,'password');await click('settings.ai.provider.0.reveal_key');assert.equal((await inputState('settings.ai.provider.0.api_key')).input_type,'text');assert.equal(await readFile(config,'utf8'),saved);await click('settings.ai.provider.0.reveal_key');assert.equal((await inputState('settings.ai.provider.0.api_key')).input_type,'password');assert.equal(await readFile(config,'utf8'),saved);await nav.gone('settings.footer');report.checks.push('Key reveal/hide does not mutate config or dirty the page');
   await click('settings.ai.provider.0.model.0.delete_model');await found('settings.ai.delete.dialog');await capture('03-delete-cancel');await click('settings.ai.delete.cancel');await nav.gone('settings.ai.delete.dialog');await found('settings.ai.provider.0.model.0.card');assert.equal(await readFile(config,'utf8'),saved);
   await click('settings.ai.provider.0.model.0.delete_model');await key('s',{cmd:true});assert.equal(await readFile(config,'utf8'),saved);await click('settings.ai.delete.confirm');await nav.gone('settings.ai.delete.dialog');assert.equal(await readFile(config,'utf8'),saved);await save(s=>!s.includes('name = "first-model"'));report.checks.push('Delete Cancel preserves model; Cmd-S is blocked; confirm changes draft only, then outer Save deletes inactive model');
   await list();await resizeWindow(860,480);await capture('04-provider-compact');await provider(1,'second');await reveal('settings.ai.provider.1.endpoint');await capture('05-provider-compact-fields');
   // A clean page has no Save Bar. Make a draft to verify the floating bar remains usable while scrolling.
   await edit('settings.ai.provider.1.endpoint','http://127.0.0.1:9/api/chat?compact=1');const footer=await found('settings.footer');inside(footer,860,480);await reveal('settings.ai.provider.1.add_model');const scrolledFooter=await found('settings.footer');inside(scrolledFooter,860,480);assert(Math.abs(scrolledFooter.rect.y-footer.rect.y)<.5,'Save Bar remains fixed while the dirty detail scrolls');await click('settings.revert');await nav.gone('settings.footer');report.checks.push('Compact detail fields are reachable; dirty Save Bar stays fixed inside the window across page scroll');
   await list();await provider(0,'first');await click('settings.ai.provider.0.delete_provider');await modalInside('settings.ai.delete.dialog',860,480);inside(await found('settings.ai.delete.dialog'),860,480);inside(await found('settings.ai.delete.footer'),860,480);await capture('09-provider-delete-compact');const beforeDelete=await readFile(config,'utf8');await click('settings.ai.delete.cancel');await nav.gone('settings.ai.delete.dialog');assert.equal(await readFile(config,'utf8'),beforeDelete);
   await click('settings.ai.provider.0.delete_provider');await click('settings.ai.delete.confirm');await nav.gone('settings.ai.delete.dialog');await nav.waitTitle('服务提供方');assert.equal(await readFile(config,'utf8'),beforeDelete);await save(s=>!s.includes('id = "first"'));report.checks.push('Compact native provider delete stays inside window; Cancel preserves file; confirm returns to list and outer Save persists removal');
  }
 }
 report.status='passed_pending_pixel_review';
}catch(e){report.status='failed';report.error=String(e);await capture('failure').catch(()=>{});throw e;}
finally{try{if(app.exitCode===null&&app.signalCode===null)app.kill('SIGTERM');await ended;}finally{await log.close();await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));}}
console.log(JSON.stringify(report));
