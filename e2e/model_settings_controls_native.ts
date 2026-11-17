// 迁移说明（F-set-ai 之后）
// 删除推理等级选项高 30、等宽、4+3 网格和行距 36 的断言：原生 Checkbox 保留默认几何，仍检查全部等级与持久化映射。
// 删除来源槽固定高 18 与按子节点索引判定图标的断言：原生来源标记只有一个随来源变化的图标，改验 Tooltip 的来源语义。
// 删除弹窗固定 480×416 的断言：原生 Modal 使用默认几何，保留紧凑窗口内边界与底部内容可达性检查。
/** Isolated model settings regression: default state, provenance and compact layout. */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createServer} from 'node:http';
import {mkdir,mkdtemp,realpath,open,readFile,writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import * as h from '../vendor/zenit/e2e/client.ts';

import {settingsNav,textOf} from './settings_nav.ts';
const binary=resolve(process.argv[2]),out=resolve(process.argv[3]),theme=process.argv[4]??'dark';
assert(['dark','light'].includes(theme));await mkdir(out,{recursive:true});
const base=await realpath(await mkdtemp(join(tmpdir(),'zw-model-controls-'))),data=join(base,'data'),rpc=join(base,'rpc');
await mkdir(data);await mkdir(rpc);await writeFile(join(data,'hosts.toml'),'');
const requests:string[]=[];
const server=createServer((req,res)=>{requests.push(req.url??'');res.writeHead(200,{'content-type':'application/json'});res.end(JSON.stringify({data:[{id:'api-model',context_window:128000,reasoning:true,vision:true,thinking:{values:['low','medium','high','xhigh','max','none','ultra']}}]}));});
await new Promise<void>(r=>server.listen(0,'127.0.0.1',r));
const port=(server.address() as any).port,config=join(data,'config.toml');
const initial=`[meta]\nconfig_revision=1\n[updates]\nauto_check=false\n[ui]\ntheme="${theme}"\n[ai]\ndefault_provider="Fixture"\n[[ai.providers]]\nid="Fixture"\nkind="openai_compat"\nendpoint="http://127.0.0.1:${port}/v1/chat/completions"\nenabled=true\n`+[true,false].map((v,i)=>`[[ai.providers.models]]\nname="model-${i}"\ncontext_window=128000\ndefault=${v}\nreasoning=true\nvision=true\nefforts=["low","high","max"]\n`).join('');
await writeFile(config,initial);process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const log=await open(join(out,'app.log'),'w');
const app=spawn(binary,[],{env:{...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_ISOLATE_POINTER:'1',ZENIT_E2E_BACKGROUND:'1',ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0'},stdio:['ignore',log.fd,log.fd]});
const ended=new Promise(r=>app.once('close',r));
const started=new Promise<void>((ready,fail)=>{app.once('spawn',()=>ready());app.once('error',fail);});
const nav=settingsNav(),node=nav.node,text=textOf;
async function reveal(id:string){
 if(!id.startsWith('settings.ai.model.'))return nav.reveal(id);
 if(/\.(dialog|footer|save|cancel|yes|no)$/.test(id)||id.includes('.catalog.option.'))return node(id);
 for(let i=0;i<24;i++){
  const n=await node(id),v=await node('settings.ai.model.viewport');
  if(n.rect.y>=v.rect.y-0.5&&n.rect.y+n.rect.h<=v.rect.y+v.rect.h+0.5)return n; // sub-point tolerance: the last row ends at a fractional y at full scroll
  await h.scrollAt(v.rect.x+v.rect.w-4,v.rect.y+v.rect.h/2,0,n.rect.y<v.rect.y?140:-140);await h.sleep(100);
 }
 throw Error('Cannot reveal '+id+': node '+JSON.stringify((await node(id)).rect)+' viewport '+JSON.stringify((await node('settings.ai.model.viewport')).rect));
}
async function click(id:string){
 if(!id.startsWith('settings.ai.model.'))return nav.click(id);
 const n=await reveal(id);assert((await h.clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok,id);await h.sleep(200);
}
async function capture(name:string){await h.sleep(400);assert((await h.screenshot(join(out,name+'.png'))).ok);}
async function source(kind:string,label:string){
 const id='settings.ai.model.'+kind+'.source',n=await reveal(id);// The native W.Tooltip adds two invisible zero-size `anchor` nodes beside the glyph: count the painted children.
 const painted=(n.children??[]).filter((c:any)=>c.visible!==false&&c.rect?.w>0&&c.rect?.h>0);assert.equal(painted.length,1,'One source glyph with a semantic tooltip');
 await h.mouseMove(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2);
 await h.waitFor(async()=>text(await node(id+'.tooltip')).includes(label)||null);await h.mouseMove(20,20);await nav.gone(id+'.tooltip');
}
// The app's dialog id marks its body. Modal's component root owns the full native panel
// (components/modal/mod.zig); include the title bar when checking compact-window bounds.
async function modalInside(id:string,w:number,height:number){ // `height`, not `h`: `h` is the Harness client used below
 const contains=(n:any):boolean=>n?.test_id===id||(n?.children??[]).some(contains);
 const panel=(n:any):any=>{
  if(n?.component==='Modal'){const child=(n.children??[]).find(contains);if(child)return child;}
  for(const child of n?.children??[]){const found=panel(child);if(found)return found;}
  return null;
 };
 const native=panel(await h.tree());assert(native,'Native Modal panel for '+id);inside(native,w,height);
}
function inside(n:any,w:number,h:number){assert(n.rect.x>=0&&n.rect.y>=0&&n.rect.x+n.rect.w<=w+.5&&n.rect.y+n.rect.h<=h+.5);}
const blocks=(s:string)=>s.split('[[ai.providers.models]]').slice(1);
function defaults(s:string,selected:number){const models=blocks(s);assert.equal(models.length,2);models.forEach((m,i)=>assert(new RegExp('default\\s*=\\s*'+(i===selected?'true':'false')).test(m)));}
async function save(expect:(s:string)=>boolean){await node('settings.footer');await click('settings.save');await h.waitFor(async()=>expect(await readFile(config,'utf8'))||null,15000);await nav.gone('settings.footer');}
async function commitDefault(selected:number,before:string){
 await click('settings.ai.model.save');await nav.gone('settings.ai.model.dialog');assert.equal(await readFile(config,'utf8'),before);
 await save(s=>new RegExp('default\\s*=\\s*true').test(blocks(s)[selected]??''));const saved=await readFile(config,'utf8');defaults(saved,selected);return saved;
}
// Checkbox/Switch a11y.checked is set by components/checkbox/*.yix, but tree_serializer.zig
// does not export a11y. Verify click/Space and reopening via committed config (never glyph opacity).
const report:any={theme,status:'running',requests,checks:[],limits:['Isolated temporary configuration and local HTTP fixture.','Harness keyboard input and Metal screenshots; no physical IME or VoiceOver verification.','Harness does not serialize a11y.checked; checkbox state is verified through config.toml and Save Bar effects.']};
report.limits.push('删除推理等级选项高 30、等宽、4+3 网格和行距 36 的断言：原生 Checkbox 保留默认几何，仍检查全部等级与持久化映射。','删除来源槽固定高 18 与按子节点索引判定图标的断言：原生来源标记只有一个随来源变化的图标，改验 Tooltip 的来源语义。','删除弹窗固定 480×416 的断言：原生 Modal 使用默认几何，保留紧凑窗口内边界与底部内容可达性检查。');
try{
 await started;await h.waitForServerReady();assert.equal(Number(JSON.parse(await readFile(join(rpc,'owner.json'),'utf8')).pid),app.pid);
 await h.resizeWindow(1440,900);await nav.open();await nav.toSub('ai','providers');await click('settings.ai.provider.0.header');await nav.waitTitle('Fixture');await click('settings.ai.provider.0.model.1.edit_model');
 const strengths=['none','low','medium','high','xhigh','max','ultra'];
 const ranks=await Promise.all(strengths.map(e=>node('settings.ai.model.effort.'+e)));
 ranks.forEach((n,i)=>assert(text(n).includes(strengths[i])));
 const flat=(n:any):any[]=>[n,...(n.children??[]).flatMap(flat)];
 assert.deepEqual(flat(await node('settings.ai.model.efforts')).map(n=>n.test_id).filter(id=>id?.startsWith('settings.ai.model.effort.')),strengths.map(e=>'settings.ai.model.effort.'+e));
 // Keep the geometry artifact for manual comparison, without enforcing obsolete chip dimensions.
 await writeFile(join(out,'geometry.json'),JSON.stringify(ranks.map(n=>({id:n.test_id,rect:n.rect})),null,2));await reveal('settings.ai.model.efforts');await capture('01-capabilities');
 await source('reasoning','手动设置');await source('vision','手动设置');report.checks.push('All seven native effort checkboxes have their strength labels; manual capability provenance has working tooltips');
 defaults(initial,0);await click('settings.ai.model.default');await click('settings.ai.model.effort.low');await click('settings.ai.model.effort.none');await reveal('settings.ai.model.default');await capture('02-default-selected');
 let saved=await commitDefault(1,initial);assert(/"none"/.test(blocks(saved)[1]));assert(!/"low"/.test(blocks(saved)[1]));assert(/"high"/.test(blocks(saved)[1])&&/"max"/.test(blocks(saved)[1]));
 // Restore model 0 as default so an unchecked model 1 can be committed legally.
 await click('settings.ai.provider.0.model.0.default_model');await save(s=>/default\s*=\s*true/.test(blocks(s)[0]??''));saved=await readFile(config,'utf8');defaults(saved,0);
 await click('settings.ai.provider.0.model.1.edit_model');await click('settings.ai.model.default');await h.key('space');await click('settings.ai.model.save');await nav.gone('settings.ai.model.dialog');await nav.gone('settings.footer');assert.equal(await readFile(config,'utf8'),saved);
 // The click was independently verified above; Space must undo it and leave a clean draft.
 await click('settings.ai.provider.0.model.1.edit_model');await reveal('settings.ai.model.default');for(let i=0;;i++){if((await h.focused()).id===(await node('settings.ai.model.default')).id)break;assert(i<40,'Tab reaches native default checkbox');await h.key('tab');}await h.key('space');saved=await commitDefault(1,saved);
 await click('settings.ai.provider.0.model.1.edit_model');
 // Reopening must retain the effort selection: invert both, then save and verify the result.
 await click('settings.ai.model.effort.none');await click('settings.ai.model.effort.low');saved=await commitDefault(1,saved);assert(!/"none"/.test(blocks(saved)[1]));assert(/"low"/.test(blocks(saved)[1]));
 await click('settings.ai.provider.0.model.1.edit_model');await click('settings.ai.model.effort.none');await click('settings.ai.model.effort.low');saved=await commitDefault(1,saved);assert(/"none"/.test(blocks(saved)[1])&&!/"low"/.test(blocks(saved)[1]));
 await click('settings.ai.provider.0.model.1.edit_model');
 report.checks.push('Default click and Space on/off verified by exclusive persisted defaults and clean draft; model Save stays local; reopening retains default and effort selections');
 await h.resizeWindow(860,480);await reveal('settings.ai.model.default');const dialog=await node('settings.ai.model.dialog'),footer=await node('settings.ai.model.footer');await modalInside('settings.ai.model.dialog',860,480);inside(dialog,860,480);inside(footer,860,480);assert(footer.rect.y+footer.rect.h<=dialog.rect.y+dialog.rect.h+.5);await capture('03-compact');await click('settings.ai.model.cancel');await nav.gone('settings.ai.model.dialog');
 report.checks.push('Compact 860 × 480 window retains reachable lower content and a dialog/footer inside the window');
 await h.resizeWindow(1440,900);await click('settings.ai.provider.0.add_model');await source('reasoning','接口未返回');assert(!(await node('settings.ai.model.catalog')).focusable,'Catalog Select is disabled until models are fetched');await capture('04-missing');await click('settings.ai.model.fetch_models');
 await h.waitFor(async()=>text(await node('settings.ai.model.catalog_status')).includes('已获取')||null,15000);assert(requests.length>0&&requests.every(url=>url==='/v1/models'),'All catalog requests use /v1/models');await click('settings.ai.model.catalog');await click('settings.ai.model.catalog.option.0');
 await source('context','接口已返回');await source('reasoning','接口已返回');await source('vision','接口已返回');await capture('05-api-metadata');
 await click('settings.ai.model.vision');await click('settings.ai.model.vision.no');await source('vision','手动设置');assert(text(await node('settings.ai.model.vision')).includes('不支持'));await capture('06-manual-override');await click('settings.ai.model.cancel');await nav.gone('settings.ai.model.dialog');assert.equal(await readFile(config,'utf8'),saved);await nav.gone('settings.footer');
 report.checks.push('Missing/API/manual metadata retain native provenance tooltips; manual override replaces API provenance and Cancel preserves config');report.status='passed';
}catch(e){report.status='failed';report.error=String(e);await capture('failure').catch(()=>{});throw e;}
finally{try{if(app.exitCode===null&&app.signalCode===null)app.kill('SIGTERM');await ended;}finally{server.closeAllConnections();await new Promise<void>(r=>server.close(()=>r()));await log.close();await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));}}
