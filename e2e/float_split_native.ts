/** Floating card "放入分屏" (float-split; user feedback "floating window 都要有的通用 shell/chrome … 切换到 tab body 里的
 * card split view …有些 card 如果配了不支持 split view，还是要出这个 button，但 disable 的样式"; Pencil b2ghJ).
 *
 * A test-mode-only card type `fixture.float` (float + split, no standalone tab; opened by ZEROWORK_TEST_FLOAT_FIXTURE)
 * walks the whole round trip with a non-session card (AI and session cards: cards_float_native):
 *  1. Every floating card's chrome shows 作为标签页打开 · 放入分屏 · 收起 · 放大 · 关闭 in the fixed order (cards-float: all
 *     five on every card); refused ones are the native disabled Button (not focusable) and their Tooltip says why:
 *     fixture open-as-tab and 收起, AI open-as-tab, history split.
 *  2. Fixture: type text, select row 7, scroll the list; 放入分屏 → the standalone local tab becomes a two-card split,
 *     the pane sits on the nearest side (right by default), the same content keeps text, selection and scroll.
 *     anchor mode: the pane's flight starts at the floating rectangle and lands on the pane; fade mode / reduced
 *     motion: it stays in place and only fades.
 *  3. The pane header's 浮动 → back at the floating rectangle it left, state intact; anchor mode unfolds from the pane;
 *     the split made for the dock dissolves back into the single-card tab.
 *
 * Usage: node e2e/float_split_native.ts <zerowork binary (test-mode)> <out dir> [light|dark] [anchor|fade|reduced]
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {join,resolve} from 'node:path';
import {writeFile,readFile,mkdir,mkdtemp,realpath,open,rm} from 'node:fs/promises';
import {spawn} from 'node:child_process';
import * as h from '../vendor/zenit/e2e/client.ts';
import {shown} from './settings_nav.ts';

const [binaryArg,outArg,theme='light',mode='anchor']=process.argv.slice(2);
if(!binaryArg||!outArg)throw new Error('usage: float_split_native.ts <binary> <out> [light|dark] [anchor|fade|reduced]');
const out=resolve(outArg);await mkdir(out,{recursive:true});
const tag=`${theme}-${mode}`;
const report:any={status:'running',theme,mode,checks:[] as string[],shots:[] as string[],samples:{} as any,limits:['The fixture card is a test-mode-only non-session card type (float + split, no standalone tab); AI and session cards are covered by cards_float_native.']};
const iso=await realpath(await mkdtemp('/private/tmp/zw-float-split-e2e-')),rpc=join(iso,'rpc'),data=join(iso,'data');
await mkdir(rpc);await mkdir(join(data,'logs/history'),{recursive:true});
await writeFile(join(data,'config.toml'),`[meta]\nconfig_revision=1\n[updates]\nauto_check=false\n[ui]\ntheme="${theme}"\nfloat_card_transition="${mode==='fade'?'fade':'anchor'}"\n[ui.materials]\nblur_px=0\n`);
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const logPath=join(out,`${tag}-app.log`);
const log=await open(logPath,'w');
const env:any={...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1',ZENIT_E2E_ISOLATE_KEYBOARD:'1',ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',ZEROWORK_TEST_FLOAT_FIXTURE:'1',OPENAI_API_KEY:'',ANTHROPIC_API_KEY:''};
if(mode==='reduced')env.ZENIT_A11Y_PREFS='reduce_motion';
const app=spawn(binaryArg,[],{env,stdio:['ignore',log.fd,log.fd]});
const ended=new Promise<void>(r=>app.once('close',()=>r()));
await h.waitForServerReady();

type R={x:number,y:number,w:number,h:number};
const node=(id:string,ms=12000)=>h.waitFor(async()=>(await h.query(id)).find(shown)??null,ms);
const gone=(id:string,ms=6000)=>h.waitFor(async()=>(await h.query(id)).some(shown)?null:true,ms);
const click=async(id:string)=>{const n=await node(id);assert((await h.clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok,'click '+id);};
const shot=async(name:string,park=true)=>{if(park){await h.mouseMove(4,500);await h.sleep(700);}const path=join(out,`${tag}-${name}.png`);assert((await h.screenshot(path)).ok,name);report.shots.push(path);return path;};
const near=(a:number,b:number,label:string,tol=1)=>assert(Math.abs(a-b)<=tol,`${label}: ${a} vs ${b}`);
const settled=async(id:string):Promise<R>=>{let last:R|null=null;return h.waitFor(async()=>{const r=(await node(id)).rect;const stable=last&&Math.abs(last.x-r.x)<0.5&&Math.abs(last.y-r.y)<0.5&&Math.abs(last.w-r.w)<0.5&&Math.abs(last.h-r.h)<0.5;last=r;return stable?r:null;},6000,80);};
const texts=(n:any):string[]=>[...(n.text?[n.text]:[]),...(n.children??[]).flatMap(texts)];
const disabled=async(id:string)=>{const n:any=(await h.query(id)).find(shown);assert(n,'button '+id);return n.disabled===true||n.focusable!==true;};
/** Hover a header button and read its Tooltip text. */
async function tooltip(id:string){
 const b=(await node(id)).rect;await h.mouseMove(4,500);await h.sleep(250);await h.mouseMove(b.x+b.w/2,b.y+b.h/2);await h.sleep(60);await h.mouseMove(b.x+b.w/2+1,b.y+b.h/2);
 const tip=await node(id+'.tooltip',4000);return texts(tip).join('');
}
async function traces(){const text=await readFile(logPath,'utf8');return {
 events:text.split('\n').filter(l=>l.startsWith('ZW_FLOAT_SPLIT {')).map(l=>JSON.parse(l.slice('ZW_FLOAT_SPLIT '.length))),
 frames:text.split('\n').filter(l=>l.startsWith('ZW_FLOAT_SPLIT_FRAME ')).map(l=>JSON.parse(l.slice('ZW_FLOAT_SPLIT_FRAME '.length)))};}
const rectOf=(a:number[]):R=>({x:a[0],y:a[1],w:a[2],h:a[3]});
const centre=(r:R)=>({x:r.x+r.w/2,y:r.y+r.h/2});

/** Fixture state: input text, selected row (secondary variant), the row-7 offset inside the list viewport. */
async function state(){
 const input=await h.inputState('fixture.float.input');
 const list=(await node('fixture.float.list')).rect;
 const sel=(await h.query('fixture.float.selection'))[0] as any;const row1=(await h.query('fixture.float.row.1'))[0] as any;
 return {text:input.buffer,row7_variant:texts(sel??{}).join(''),scroll:+(row1.rect.y-list.y).toFixed(1),list:list as R};
}

try{
 await h.resizeWindow(1440,900);await h.sleep(400);
 await click(((await h.query('workspace.empty.local')).some(shown))?'workspace.empty.local':'toolbar.new_session');
 if(!(await h.query('terminal.surface')).some(shown)&&(await h.query('session.menu.local')).some(shown))await click('session.menu.local');
 await node('terminal.surface');await h.sleep(600);
 const body=(await node('terminal.surface')).rect as R;

 // 1. The fixture card floats with both placement actions; its order and disabled state.
 const panel=await settled('fixture.float.panel');
 const order=['fixture.float.open_as_tab','fixture.float.dock_to_split','fixture.float.minimize','fixture.float.maximize','fixture.float.close'];
 const xs=[];for(const id of order)xs.push((await node(id)).rect.x);
 for(let i=1;i<xs.length;i++)assert(xs[i]>xs[i-1],`fixed order ${order[i-1]} < ${order[i]}`);
 assert(await disabled('fixture.float.open_as_tab'),'fixture: open as tab is disabled (no standalone tab)');
 assert(await disabled('fixture.float.minimize'),'fixture: 收起 is shown disabled (cards-float: every action on every card)');assert.equal(await tooltip('fixture.float.minimize'),'测试卡片不支持收起');
 assert(!(await disabled('fixture.float.dock_to_split')),'fixture: dock to split is enabled');
 assert.equal(await tooltip('fixture.float.open_as_tab'),'测试卡片不支持作为标签页打开');
 assert.equal(await tooltip('fixture.float.dock_to_split'),'放入分屏');
 report.checks.push('Fixture chrome: 作为标签页打开 · 放入分屏 · 收起 · 放大 · 关闭 in order; open-as-tab native disabled with "测试卡片不支持作为标签页打开", 收起 disabled with "测试卡片不支持收起", 放入分屏 enabled');
 // Pressing the disabled button changes nothing.
 await click('fixture.float.open_as_tab');await h.sleep(300);assert((await h.query('fixture.float.panel')).some(shown),'disabled open-as-tab does nothing');

 // State to keep: text, selection, scroll.
 await click('fixture.float.input');await h.type_('保留的文字');await h.sleep(200);
 await click('fixture.float.row.7');await h.sleep(200);
 {const l=(await node('fixture.float.list')).rect;await h.scrollAt(l.x+l.w/2,l.y+l.h/2,0,-120);await h.sleep(500);}
 const before=await state();
 assert.equal(before.text,'保留的文字');assert.equal(before.row7_variant,'已选：第 7 行');assert(before.scroll<-20,`list scrolled (${before.scroll})`);
 const floatRect=(await node('fixture.float.panel')).rect as R;
 await shot('floating');
 // AI (both refused) and history (split refused) next to it.
 await click('ai.launcher');await settled('ai.panel');
 assert(await disabled('ai.open_as_tab'),'AI open as tab disabled');assert(!(await disabled('ai.dock_to_split')),'AI dock to split enabled (cards-float)');
 assert.equal(await tooltip('ai.dock_to_split'),'放入分屏');
 report.samples.ai_tooltip_open_as_tab=await tooltip('ai.open_as_tab');assert.equal(report.samples.ai_tooltip_open_as_tab,'AI 助手不支持作为标签页打开');
 await shot('ai-disabled-tooltip',false);
 await click('ai.collapse');await h.sleep(700);
 await click('toolbar.history');await settled('history.panel');
 assert(!(await disabled('history.open_as_tab')),'history open as tab stays enabled');assert(await disabled('history.dock_to_split'),'history dock to split disabled');
 assert.equal(await tooltip('history.dock_to_split'),'会话记录不支持分屏');
 await shot('history-disabled-tooltip',false);
 await click('history.close');await gone('history.panel');
 report.checks.push('AI: 作为标签页打开 native disabled ("AI 助手不支持作为标签页打开"), 放入分屏 enabled (cards-float); history: 放入分屏 disabled with "会话记录不支持分屏", 作为标签页打开 enabled');

 // 2. Dock: the pane appears, the floating frame goes, the content keeps its state.
 await click('fixture.float.dock_to_split');await h.sleep(90);await shot('dock-mid',false);
 const pane=await settled('fixture.float.pane');await gone('fixture.float.panel');
 await h.sleep(600);
 const tr=await traces();const dock=tr.events.find(e=>e.action==='dock');assert(dock,'dock traced');
 assert.equal(dock.mode,mode==='fade'?'fade':'anchor');
 near(dock.from[0],floatRect.x,'flight starts at the floating card x',1.5);near(dock.from[1],floatRect.y,'flight starts at the floating card y',1.5);
 const paneFrames=tr.frames.filter(f=>f.kind==='pane');
 assert(paneFrames.length>0||mode==='reduced','the pane flight was drawn');
 report.samples.dock={from:dock.from,pane,frames:paneFrames.length,first:paneFrames[0],last:paneFrames.at(-1)};
 if(mode==='anchor'&&paneFrames.length){
  const f0=rectOf(paneFrames[0].rect),c0=centre(f0),cf=centre(floatRect),cp=centre(pane);
  assert(Math.hypot(c0.x-cf.x,c0.y-cf.y)<Math.hypot(c0.x-cp.x,c0.y-cp.y),`anchor: the first frame is nearer the floating card (${JSON.stringify(f0)}) than the pane`);
 }else for(const f of paneFrames){const c=centre(rectOf(f.rect)),cp=centre(pane);assert(Math.abs(c.x-cp.x)<2&&Math.abs(c.y-cp.y)<2,`${mode}: the pane fades in place`);}
 // Right of the terminal (default / nearest side for a centred card), a two-card split.
 const term=(await node('terminal.surface')).rect as R;
 assert(pane.x>term.x+term.w-1,`pane right of the terminal (${JSON.stringify(pane)} / ${JSON.stringify(term)})`);
 assert((await h.query('groups.workspace')).some(shown),'the tab body is a split');
 const after=await state();
 assert.equal(after.text,before.text,'text kept');assert.equal(after.row7_variant,before.row7_variant,'selection kept');near(after.scroll,before.scroll,'scroll kept',1);
 assert.equal(await tooltip('fixture.float.pane.float'),'浮动');
 await shot('docked');
 report.checks.push(`Dock (${mode}): pane right of the terminal in a two-card split; flight ${mode==='anchor'?'starts at the floating rectangle':'stays in place (fade)'}; text, selection and scroll kept`);

 // 3. Float again: back at the same rectangle, state intact.
 await click('fixture.float.pane.float');await h.sleep(90);await shot('float-mid',false);
 const again=await settled('fixture.float.panel');await gone('fixture.float.pane');await h.sleep(600);
 near(again.x,floatRect.x,'back at the floating x',1);near(again.y,floatRect.y,'back at the floating y',1);near(again.w,floatRect.w,'same width',1);
 const tr2=await traces();const back=tr2.events.find(e=>e.action==='float');assert(back,'float traced');
 near(back.from[0],pane.x,'unfolds from the pane x',1.5);
 // Expand from rest waits one layout pass before the snapshot: those frames report the home rect and draw nothing.
 const allFloat=tr2.frames.filter(f=>f.kind==='float');const lead=allFloat.findIndex(f=>Math.abs(f.rect[0]-again.x)>0.5||Math.abs(f.rect[1]-again.y)>0.5||f.opacity<0.999);
 const floatFrames=lead<0?[]:allFloat.slice(lead);
 if(mode==='anchor'&&floatFrames.length){const f0=centre(rectOf(floatFrames[0].rect)),cp=centre(pane),ca=centre(again);assert(Math.hypot(f0.x-cp.x,f0.y-cp.y)<Math.hypot(f0.x-ca.x,f0.y-ca.y),'anchor: unfolds out of the pane');}
 else for(const f of floatFrames){const c=centre(rectOf(f.rect)),ca=centre(again);assert(Math.abs(c.x-ca.x)<2&&Math.abs(c.y-ca.y)<2,`${mode}: fades in place`);}
 const restored=await state();
 assert.equal(restored.text,before.text);assert.equal(restored.row7_variant,before.row7_variant);near(restored.scroll,before.scroll,'scroll kept after floating back',1);
 report.samples.float={from:back.from,to:again,frames:floatFrames.length};
 await shot('floated-back');
 assert(!(await h.query('groups.workspace')).some(shown),'the split made for the dock dissolved back into the single-card tab');
 report.checks.push('Float back: same rectangle as before docking, state intact; pane gone; the two-card split went back to the single-card tab');
 report.samples.body=body;
 report.status='passed';
}catch(error){report.status='failed';report.error=String((error as any)?.stack??error);await h.screenshot(join(out,`${tag}-failure.png`)).catch(()=>{});process.exitCode=1;}
finally{
 await writeFile(join(out,`report-${tag}.json`),JSON.stringify(report,null,1));
 if(app.exitCode===null&&app.signalCode===null)app.kill('SIGTERM');await ended;
 await log.close().catch(()=>{});await rm(iso,{recursive:true,force:true}).catch(()=>{});
}
console.log(report.status, out);
