// 迁移说明（F-set-ai 之后）
// 删除单模型行高 44 的断言：模型使用原生设置行，保留模型名称与操作检查。
// 删除模型弹窗固定 480×416、精确居中和面板边距 8 的断言：原生 Modal 使用默认几何；保留 860×480 窗口内对话框、页脚边界与正文滚动检查。
/** Real V3 model dialog: independent draft, validation, persistence and compact layout. */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdir,mkdtemp,realpath,open,readFile,writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {waitForServerReady,waitFor,clickAt,key,type_,resizeWindow,screenshot,sleep,tree,scrollAt,mouseMove,inputState} from '../vendor/zenit/e2e/client.ts';
import {settingsNav,textOf} from './settings_nav.ts';
const binary=resolve(process.argv[2]),out=resolve(process.argv[3]),theme=process.argv[4]??'dark';
assert(['dark','light'].includes(theme));await mkdir(out,{recursive:true});
const base=await realpath(await mkdtemp(join(tmpdir(),'zw-model-editor-'))),data=join(base,'data'),rpc=join(base,'rpc');await mkdir(data);await mkdir(rpc);
const config=join(data,'config.toml');
await writeFile(join(data,'hosts.toml'),'');
const initial=`[meta]\nconfig_revision=1\n[updates]\nauto_check=false\n[ui]\ntheme="${theme}"\nfont_family="Menlo"\nfont_size=14\n[ai]\ndefault_provider="local-fixture"\n[[ai.providers]]\nid="local-fixture"\nkind="openai_compat"\nendpoint="http://127.0.0.1:9/v1/chat/completions"\nenabled=true\n[[ai.providers.models]]\nname="fixture-model"\ncontext_window=1000000\ndefault=true\nreasoning=true\nvision=true\nefforts=["low","high","max"]\n`;
await writeFile(config,initial);process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const log=await open(join(out,'app.log'),'w'),app=spawn(binary,[],{env:{...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_ISOLATE_POINTER:'1',ZENIT_E2E_BACKGROUND:'1',ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0'},stdio:['ignore',log.fd,log.fd]});const ended=new Promise<void>(r=>app.once('close',()=>r()));
const started=new Promise<void>((ready,fail)=>{app.once('spawn',()=>ready());app.once('error',fail);});
const nav=settingsNav(),visible=nav.node,hidden=nav.gone,text=textOf;
async function reveal(id:string){
 if(!id.startsWith('settings.ai.model.'))return nav.reveal(id);
 if(/\.(dialog|footer|save|cancel|yes|no)$/.test(id))return visible(id);
 for(let i=0;i<24;i++){
  const n=await visible(id),v=await visible('settings.ai.model.viewport');
  // Scrolled to the end the last row can sit a fraction of a point past the viewport (521.2 + 16 vs 537): same .5 tolerance as the other bounds checks.
 if(n.rect.y>=v.rect.y-.5&&n.rect.y+n.rect.h<=v.rect.y+v.rect.h+.5)return n;
  await scrollAt(v.rect.x+v.rect.w-4,v.rect.y+v.rect.h/2,0,n.rect.y<v.rect.y?140:-140);await sleep(100);
 }
 throw Error('Cannot reveal '+id);
}
async function click(id:string){
 if(!id.startsWith('settings.ai.model.'))return nav.click(id);
 const n=await reveal(id);assert((await clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok,id);await sleep(200);
}
async function fill(id:string,value:string){await click(id);await key('a',{cmd:true});await key('backspace');await type_(value);await waitFor(async()=>(await inputState(id)).buffer===value||null);}
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
const report:any={theme,status:'running',checks:[],limits:['Harness input and live Metal pixels; no physical IME or VoiceOver claim.','Synthetic provider configuration; no network request or real credentials.']};
report.limits.push('删除单模型行高 44 的断言：模型使用原生设置行，保留模型名称与操作检查。','删除模型弹窗固定 480×416、精确居中和面板边距 8 的断言：原生 Modal 使用默认几何；保留 860×480 窗口内对话框、页脚边界与正文滚动检查。');
async function capture(name:string){await sleep(400);assert((await screenshot(join(out,name+'.png'))).ok);}
try{
 await started;await waitForServerReady();assert.equal(Number(JSON.parse(await readFile(join(rpc,'owner.json'),'utf8')).pid),app.pid);
 await resizeWindow(1440,900);await nav.open();await nav.toSub('ai','providers');await click('settings.ai.provider.0.header');await nav.waitTitle('local-fixture');
 await reveal('settings.ai.provider.0.model.0.card');assert(text(await visible('settings.ai.provider.0.model.0.header')).includes('fixture-model'));await capture('01-single-row');
 await fill('settings.ai.provider.0.name','Outer draft');await click('settings.ai.provider.0.model.0.edit_model');
 await fill('settings.ai.model.id','cancelled-model');await key('s',{cmd:true});await sleep(200);assert.equal(await readFile(config,'utf8'),initial);
 await click('settings.ai.model.cancel');await hidden('settings.ai.model.dialog');assert.equal((await inputState('settings.ai.provider.0.name')).buffer,'Outer draft');assert(text(await visible('settings.ai.provider.0.model.0.header')).includes('fixture-model'));
 await click('settings.revert');await hidden('settings.footer');await click('settings.ai.provider.0.model.0.edit_model');await fill('settings.ai.model.id','outside-cancelled');await clickAt(12,450);await hidden('settings.ai.model.dialog');assert(text(await visible('settings.ai.provider.0.model.0.header')).includes('fixture-model'));assert.equal(await readFile(config,'utf8'),initial);await visible('settings.panel');await click('settings.ai.provider.0.model.0.edit_model');await key('comma',{cmd:true});await visible('settings.ai.model.dialog');await visible('settings.panel');await click('settings.ai.model.cancel');await click('settings.ai.provider.0.model.0.edit_model');await fill('settings.ai.model.context','0');await click('settings.ai.model.save');assert(text(await reveal('settings.ai.model.error')).includes('1–4294967295'));assert.equal(await readFile(config,'utf8'),initial);await capture('02-validation');
 await fill('settings.ai.model.context','1048576');await click('settings.ai.model.vision');await click('settings.ai.model.vision.no');await click('settings.ai.model.effort.low');await click('settings.ai.model.save');await hidden('settings.ai.model.dialog');assert.equal(await readFile(config,'utf8'),initial);
 await click('settings.save');await waitFor(async()=>/context_window\s*=\s*1048576/.test(await readFile(config,'utf8'))||null,15000);await hidden('settings.footer');const saved=await readFile(config,'utf8');assert(/vision\s*=\s*false/.test(saved));const efforts=/efforts\s*=\s*\[([^\]]*)\]/.exec(saved);assert(efforts&&!efforts[1].includes('low')&&efforts[1].includes('high')&&efforts[1].includes('max'));await capture('03-parent-saved');
 await click('settings.ai.provider.0.model.0.edit_model');assert.equal((await inputState('settings.ai.model.context')).buffer,'1048576');assert(text(await visible('settings.ai.model.vision')).includes('不支持'));
 await resizeWindow(860,480);await sleep(300);const dialog=await visible('settings.ai.model.dialog'),footer=await visible('settings.ai.model.footer');await modalInside('settings.ai.model.dialog',860,480);inside(dialog,860,480);inside(footer,860,480);assert(footer.rect.y+footer.rect.h<=dialog.rect.y+dialog.rect.h+.5);await capture('04-minimum-editor');
 await click('settings.ai.model.reasoning');await capture('05-capability-menu');await key('escape');await hidden('settings.ai.model.reasoning.yes');await visible('settings.ai.model.dialog');assert.equal(await readFile(config,'utf8'),saved);await key('escape');await hidden('settings.ai.model.dialog');assert.equal(await readFile(config,'utf8'),saved);
 await click('settings.ai.provider.0.model.0.edit_model');const long='organization/very-long-custom-model-name-for-truncation-2026-10-25';await fill('settings.ai.model.id',long);await click('settings.ai.model.save');await hidden('settings.ai.model.dialog');const compact=await reveal('settings.ai.provider.0.model.0.card');for(const suffix of ['default_model','edit_model','delete_model']){const n=await visible('settings.ai.provider.0.model.0.'+suffix);assert(n.rect.x>=compact.rect.x&&n.rect.x+n.rect.w<=compact.rect.x+compact.rect.w+0.5)}await capture('06-long-name-row');const name=await reveal('settings.ai.provider.0.model.0.header');await mouseMove(name.rect.x+name.rect.w/2,name.rect.y+name.rect.h/2);await sleep(650);const tip=await visible('settings.ai.provider.0.model.0.name.tooltip');assert(text(tip).includes(long));assert(tip.rect.x>=0&&tip.rect.y>=0&&tip.rect.x+tip.rect.w<=860&&tip.rect.y+tip.rect.h<=480);await capture('06b-full-name-hover');await mouseMove(20,20);await click('settings.revert');await hidden('settings.footer');assert.equal(await readFile(config,'utf8'),saved);
 await click('settings.ai.provider.0.model.0.edit_model');const v=await visible('settings.ai.model.viewport');await scrollAt(v.rect.x+v.rect.w/2,v.rect.y+v.rect.h/2,0,-500);const lower=await reveal('settings.ai.model.default');assert(lower.rect.y>=v.rect.y&&lower.rect.y+lower.rect.h<=v.rect.y+v.rect.h+.5);inside(await visible('settings.ai.model.footer'),860,480);await capture('07-minimum-scrolled');await click('settings.ai.model.cancel');await hidden('settings.ai.model.dialog');
 report.status='passed';report.checks=['Single model row exposes the configured model name','Local edit and Cancel preserve both model and unrelated outer draft','Parent Cmd-S cannot persist while model dialog is open; Cmd-comma does not close or hide the parent while the child is active','Invalid capacity stays in dialog without changing config','Model Save only changes outer draft; outer Save writes actual file','Reopen reads committed capacity and vision selection; reasoning effort checkbox is saved','Native model dialog and fixed footer stay inside the compact 860x480 window','Outside click cancels only the model dialog; Escape closes capability menu before model dialog','Long model ID does not displace action buttons and has a full-name hover tooltip','Body scroll exposes lower capabilities in minimum window'];
}catch(e){report.status='failed';report.error=String(e);await capture('failure').catch(()=>{});throw e;}
finally{try{if(app.exitCode===null&&app.signalCode===null)app.kill('SIGTERM');await ended;}finally{await log.close();await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));}}
