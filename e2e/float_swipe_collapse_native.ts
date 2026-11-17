/**
 * 浮动窗口下滑收起（swipe-collapse，Pencil AveHg「Row · 下滑收起」，规则帧 JmcNv）。真实窗口、隔离数据目录、
 * 本机回环的假模型（不出网），harness 鼠标事件。每个主题跑一遍：
 *   1. 按住：AI 面板贴底（默认锚右下），在把手上按下 → 把手整条 hover 底色、Grabber 变强调色并加宽到 48（`ai.float.grabber`）。
 *      截图 <theme>-1-held.png（对照 n2C379）。
 *   2. 快速下甩：面板继承速度继续下滑出视图、同时淡出（探针 `ai.panel.motion`：phase collapsing、anchor swipe、矩形下移、
 *      透明度下降，不走 Z12 锚点飞行）；收起后 ai.launcher 在锚角淡入（effective_opacity 0 → 1）。截图下滑中
 *      <theme>-2-sliding.png（对照 wrTsk）、收起完成 <theme>-3-collapsed.png（对照 bXcyv）。点图标恢复：对话（一轮
 *      问答）与草稿都还在，面板回到原位。
 *   3. 慢拖超过自身高度 1/3（速度 < 900 px/s）→ 收起；慢拖不到 1/3 → 弹回贴底位置，不收起。
 *   4. 不贴底时下甩 → 只是普通拖动 + 惯性（drag-inertia：松手后继续滑行，至多停在拖动区域底边），不收起。
 *   5. 终端卡片（不支持收起）贴底下甩 → 跟手拖出视图底，松手弹回贴底位置，不收起、不隐藏。
 *
 * Usage: node e2e/float_swipe_collapse_native.ts <zerowork binary (test-mode)> <out dir> [light|dark] [motion|reduced]
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {join,resolve} from 'node:path';
import {writeFile,mkdir,mkdtemp,realpath,open,rm,chmod} from 'node:fs/promises';
import {spawn} from 'node:child_process';
import * as h from '../vendor/zenit/e2e/client.ts';
import {isTitleRequest,skipTitle} from './ai_title_fixture.ts';
import {readRequestJson} from './provider_fixture.ts';

const [binaryArg,outArg,theme='light',mode='motion']=process.argv.slice(2);
if(!binaryArg||!outArg)throw new Error('usage: float_swipe_collapse_native.ts <binary> <out> [light|dark] [motion|reduced]');
const out=resolve(outArg);await mkdir(out,{recursive:true});
const tag=mode==='reduced'?`${theme}-reduced`:theme;
const report:any={status:'running',theme,mode,checks:[] as string[],shots:[] as string[],samples:{} as any};

const server=createServer(async(req,res)=>{
 if(req.method!=='POST'){res.writeHead(200,{'Content-Type':'application/json'});res.end(JSON.stringify({data:[{id:'swipe-model',object:'model',context_length:32768}]}));return;}
 const request=await readRequestJson(req);if(isTitleRequest(request))return skipTitle(res);
 const prompt=[...request.messages].reverse().find((m:any)=>m.role==='user')?.content??'';
 res.writeHead(200,{'Content-Type':'text/event-stream'});res.write('data: '+JSON.stringify({choices:[{index:0,delta:{content:'SWIPE_ANSWER_'+String(prompt).replace(/\W/g,'')}}]})+'\n\n');res.end('data: [DONE]\n\n');
});
await new Promise<void>(r=>server.listen(0,'127.0.0.1',r));const port=(server.address() as any).port;
const iso=await realpath(await mkdtemp('/private/tmp/zw-swipe-collapse-e2e-'));await chmod(iso,0o700);
const rpc=join(iso,'rpc'),data=join(iso,'data'),shell=join(iso,'shell');await mkdir(rpc);await mkdir(data);await mkdir(shell);
await writeFile(join(shell,'.zshenv'),"setopt NO_RCS\nPROMPT='sw %% '\nRPROMPT=''\n");
await writeFile(join(data,'config.toml'),`[meta]\nconfig_revision=1\n[updates]\nauto_check=false\n[ui]\ntheme="${theme}"\n[ui.materials]\nblur_px=0\n[ai]\ndefault_provider="local"\n[[ai.providers]]\nid="local"\nkind="openai_compat"\nendpoint="http://127.0.0.1:${port}/v1/chat/completions"\napi_key="local-only"\nenabled=true\n[[ai.providers.models]]\nname="swipe-model"\ncontext_window=32768\ndefault=true\n`,{mode:0o600});
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const log=await open(join(out,`${tag}-app.log`),'w');
const env:any={...process.env,ZDOTDIR:shell,ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1',ZENIT_E2E_ISOLATE_KEYBOARD:'1',ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',OPENAI_API_KEY:'',ANTHROPIC_API_KEY:''};
for(const k of ['ZEROWORK_AI_MOCK','ZEROWORK_AI_ENDPOINT','ZEROWORK_AI_MODEL','ZEROWORK_AI_PROVIDER'])delete env[k];
if(mode==='reduced')env.ZENIT_A11Y_PREFS='reduce_motion';
const app=spawn(binaryArg,[],{env,stdio:['ignore',log.fd,log.fd]});
const ended=new Promise<void>(r=>app.once('close',()=>r()));
await h.waitForServerReady();

type R={x:number,y:number,w:number,h:number};
const shown=(n:any)=>!!n&&n.hidden!==true&&n.visible!==false&&(n.effective_opacity??1)>0.02&&n.rect?.w>0&&n.rect?.h>0;
const flat=(n:any):any[]=>n?[n,...(n.children??[]).flatMap(flat)]:[];
const texts=(n:any)=>flat(n).map((x:any)=>x.text??'').join('\n');
const node=(id:string,ms=12000)=>h.waitFor(async()=>(await h.query(id)).find(shown)??null,ms);
const hidden=(id:string,ms=8000)=>h.waitFor(async()=>(await h.query(id)).some(shown)?null:true,ms);
const isShown=async(id:string)=>(await h.query(id)).some(shown);
const center=(r:R)=>({x:r.x+r.w/2,y:r.y+r.h/2});
const click=async(id:string)=>{const n=await node(id);const c=center(n.rect);assert((await h.clickAt(c.x,c.y)).ok,'click '+id);};
const shot=async(name:string)=>{const path=join(out,`${tag}-${name}.png`);assert((await h.screenshot(path)).ok,name);report.shots.push(path);return path;};
const near=(a:number,b:number,label:string,tol=1.5)=>assert(Math.abs(a-b)<=tol,`${label}: ${a} vs ${b}`);
const probe=async()=>{const f=(await h.query('ai.panel.motion'))[0];const t=async(id:string)=>((await h.query(id))[0]?.text??'');return {rect:f?.rect as R,phase:await t('ai.panel.motion.phase'),anchor:await t('ai.panel.motion.anchor'),opacity:Number(await t('ai.panel.motion.opacity'))};};
const atRest=async(phase:'expanded'|'collapsed',ms=6000)=>h.waitFor(async()=>{const p=await probe();return p.phase===phase?p:null;},ms);
const stable=async(id:string):Promise<R>=>{let last:R|null=null;return h.waitFor(async()=>{const r=(await node(id)).rect as R;const same=last&&Math.abs(last.x-r.x)<0.5&&Math.abs(last.y-r.y)<0.5&&Math.abs(last.w-r.w)<0.5&&Math.abs(last.h-r.h)<0.5;last=r;return same?r:null;},6000,80);};
const panel=async()=>{await atRest('expanded');return stable('ai.panel');};
const viewBottom=async()=>{const pane=(await node('workspace.pane')).rect as R;return Math.max(pane.y+pane.h,900-8);};
/** Press on `grip`, move by (dx, dy) in `steps` moves `stepMs` apart; release after `pauseMs` unless `hold`. */
async function gesture(grip:string,dx:number,dy:number,steps:number,stepMs:number,pauseMs=0,hold=false){
 const g=(await node(grip)).rect as R;const x=g.x+g.w/2,y=g.y+g.h/2;
 await h.mouseMove(x,y);await h.mouseDown(x,y);
 for(let i=1;i<=steps;i++){await h.mouseMove(x+dx*i/steps,y+dy*i/steps);if(stepMs)await h.sleep(stepMs);}
 if(hold)return {x:x+dx,y:y+dy};
 if(pauseMs)await h.sleep(pauseMs);
 await h.mouseUp(x+dx,y+dy);return {x:x+dx,y:y+dy};
}
const openPanel=async()=>{await click('ai.launcher');return panel();};
/** Watch the probe after a release until the card rests; returns the samples. */
async function watch(ms=1500){const samples:any[]=[];const t0=Date.now();while(Date.now()-t0<ms){const p=await probe();const l:any=(await h.query('ai.launcher'))[0];samples.push({ms:Date.now()-t0,...p,launcher_opacity:l?.effective_opacity??0});if(p.phase==='collapsed'&&samples.length>2&&(l?.effective_opacity??0)>=0.99)break;}return samples;}

try{
 await h.resizeWindow(1440,900);await h.sleep(300);
 await click((await isShown('workspace.empty.local'))?'workspace.empty.local':'toolbar.new_session');
 if(!(await isShown('terminal.surface'))&&(await isShown('session.menu.local')))await click('session.menu.local');
 await node('terminal.surface');await h.sleep(500);
 const vb=await viewBottom();report.view_bottom=vb;

 // ── 1. Held: press on the grip of the docked panel ───────────────────────────────────────
 const home=await openPanel();report.samples.home=home;
 assert(vb-(home.y+home.h)<=24,`default panel is bottom-docked (gap ${vb-(home.y+home.h)})`);
 // A conversation round and a draft, kept through the collapse.
 await click('ai.prompt');await h.type_('hello swipe');await click('ai.send');
 await h.waitFor(async()=>texts((await h.query('ai.panel')).find(shown)).includes('SWIPE_ANSWER_helloswipe')||null,12000);
 await click('ai.prompt');await h.type_('DRAFT_KEPT');await h.sleep(200);
 const restGrabber=(await node('ai.float.grabber')).rect as R;near(restGrabber.w,36,'Grabber at rest 36 wide');
 {const g=(await node('ai.float.drag')).rect as R;const c=center(g);await h.mouseMove(c.x,c.y);await h.mouseDown(c.x,c.y);await h.sleep(250);
  const held=(await node('ai.float.grabber')).rect as R;near(held.w,48,'held Grabber widens to 48');near(held.y,restGrabber.y,'held Grabber stays in the strip');
  report.samples.held_grabber=held;await shot('1-held');
  await h.mouseUp(c.x,c.y);await h.sleep(250);near(((await node('ai.float.grabber')).rect as R).w,36,'released Grabber back to 36');
  assert.equal((await probe()).phase,'expanded','a press without a drag changes nothing');}
 report.checks.push('Pressing the grip of the docked AI panel shows the held state (Grabber 36 → 48, accent; strip hover fill); release restores it, no move');

 // ── 2. Fast fling → slides out, fades, launcher fades in; restore keeps conversation and draft ──
 await gesture('ai.float.drag',0,260,4,0);
 if(mode!=='reduced'){const path=join(out,`${tag}-2-sliding.png`);if((await h.screenshot(path)).ok)report.shots.push(path);}
 const fling=await watch();report.samples.fling=fling;
 const sliding=fling.filter((s:any)=>s.phase==='collapsing');
 assert(sliding.length>0&&sliding.every((s:any)=>s.anchor==='swipe'),'collapse by swipe (anchor swipe, no Z12 flight into the launcher): '+JSON.stringify(fling.slice(0,4)));
 if(mode!=='reduced')assert(sliding.some((s:any)=>s.rect&&s.rect.y>home.y+40&&s.rect.w>home.w-1),'the panel slides down at full size while collapsing');
 else assert(sliding.every((s:any)=>!s.rect||Math.abs(s.rect.w-home.w)<1),'reduce motion: no scaling');
 assert(sliding.some((s:any)=>s.opacity<0.95),'the panel fades while sliding');
 await atRest('collapsed');await hidden('ai.panel');
 const launcher=await h.waitFor(async()=>{const l:any=(await h.query('ai.launcher')).find(shown);return l&&l.effective_opacity>=0.99?l:null;},3000);
 assert(fling.some((s:any)=>s.launcher_opacity>0.02&&s.launcher_opacity<0.98)||mode==='reduced','the launcher fades in (not popping in at full opacity)');
 near(launcher.rect.x+launcher.rect.w,home.x+home.w,'launcher in the anchor corner (right)',4);near(launcher.rect.y+launcher.rect.h,home.y+home.h,'launcher in the anchor corner (bottom)',4);
 await h.mouseMove(600,400);await h.sleep(300);await shot('3-collapsed');
 report.checks.push('Fast downward fling: the panel slides out downward and fades (probe phase collapsing, anchor swipe), the launcher fades in at the anchor corner');
 const restored=await openPanel();
 near(restored.x,home.x,'restored x');near(restored.y,home.y,'restored y');near(restored.w,home.w,'restored w');near(restored.h,home.h,'restored h');
 const after=texts((await h.query('ai.panel')).find(shown));
 assert(after.includes('SWIPE_ANSWER_helloswipe'),'conversation kept');assert(texts((await h.query('ai.prompt')).find(shown)).includes('DRAFT_KEPT'),'draft kept');
 await shot('4-restored');
 report.checks.push('Clicking the launcher restores the panel in place with its conversation and draft');

 // ── 3. Slow drags: past a third collapses; less springs back ───────────────────────────────
 {const g=await gesture('ai.float.drag',0,120,12,70,150);await h.sleep(500);
  // Springs back docked: the ordinary-drag part of the move stays (the panel may settle on the region bottom).
  const p=await panel();near(p.y+p.h,Math.min(home.y+home.h+120,892),'slow drag under a third springs back docked at the bottom');assert(vb-(p.y+p.h)<=24,'still docked');assert.equal((await probe()).phase,'expanded','no collapse under a third');
  assert(!(await isShown('ai.launcher')),'launcher stays hidden');report.samples.slow_short=g;}
 report.checks.push('Slow drag under a third of the height springs back to the docked position');
 {const third=home.h/3+50;const steps=Math.ceil(third/15);
  await gesture('ai.float.drag',0,third,steps,70,0,true);await h.sleep(200);
  const p=await probe();assert(p.rect.y>home.y+third-20,`the panel follows the pointer past the view bottom (${p.rect.y} vs ${home.y}+${third})`);await shot('2b-dragged-past');
  await h.sleep(150);const g=(await node('ai.float.drag')).rect as R;await h.mouseUp(g.x+g.w/2,g.y+g.h/2+third);
  const s=await watch();report.samples.slow_third=s;assert(s.some((x:any)=>x.phase==='collapsing'&&x.anchor==='swipe'),'slow drag past a third collapses');
  await atRest('collapsed');await node('ai.launcher');}
 report.checks.push(`Slow drag (≈ 200 px/s) a third past the bottom (${Math.round(home.h/3)}+) collapses by swipe`);

 // ── 4. Not docked: a fling is an ordinary drag ───────────────────────────────────────────
 await openPanel();
 {const g=(await node('ai.float.drag')).rect as R;await h.mouseMove(g.x+g.w/2,g.y+g.h/2);await h.mouseDown(g.x+g.w/2,g.y+g.h/2);for(let i=1;i<=10;i++){await h.mouseMove(g.x+g.w/2-20*i,g.y+g.h/2-30*i);await h.sleep(30);}await h.sleep(200);await h.mouseUp(g.x+g.w/2-200,g.y+g.h/2-300);await h.sleep(500);}
 const lifted=await panel();assert(vb-(lifted.y+lifted.h)>24,'moved up: no longer docked');
 await gesture('ai.float.drag',0,150,3,0);await h.sleep(600);
 const moved=await panel();assert.equal((await probe()).phase,'expanded','not docked: a fling does not collapse');
 // An ordinary drag + inertia: it glides on past the pointer travel (up to the drag region bottom).
 assert(moved.y>=Math.min(lifted.y+150,892-moved.h)-1,`it is an ordinary drag + inertia (${moved.y} vs ${lifted.y}+150)`);assert(moved.y+moved.h<=892.5,'inside the drag region');
 assert(!(await isShown('ai.launcher')),'launcher stays hidden');await shot('5-undocked-fling');
 report.checks.push('Not docked: a downward fling moves the panel (ordinary drag + inertia), no collapse');
 // Back to the corner for the next run state.
 {const g=(await node('ai.float.drag')).rect as R;assert((await h.clickAt(g.x+g.w/2,g.y+g.h/2,2)).ok);await h.sleep(400);}
 await click('ai.collapse');await atRest('collapsed');

 // ── 5. Terminal card (no minimize): a fling springs back ───────────────────────────────────
 await click('terminal.surface');await click('pane.float');await node('session.float.panel');await h.sleep(600);
 await gesture('session.float.drag',0,3000,6,20);await h.sleep(600);
 const tdock=await stable('session.float.panel');assert(vb-(tdock.y+tdock.h)<=24,'terminal card docked at the bottom');
 await gesture('session.float.drag',0,220,4,0,0,true);await h.sleep(150);
 const over=((await node('session.float.panel')).rect as R).y-tdock.y;report.samples.terminal_overshoot=over;
 assert(over>150,`the terminal card follows the pointer past the bottom (offset ${over})`);await shot('6-terminal-dragged-past');
 {const g=(await node('session.float.drag')).rect as R;await h.mouseUp(g.x+g.w/2,g.y+g.h/2+220);}
 await h.sleep(600);
 assert(await isShown('session.float.panel'),'terminal card stays open'); const tback=await stable('session.float.panel');near(tback.y,tdock.y,'back at the docked y');
 await shot('7-terminal-sprung-back');
 report.checks.push('A terminal card (no minimize) follows a downward fling past the bottom and springs back docked, never collapses');
 report.status='passed';
}catch(error){report.status='failed';report.error=String((error as any)?.stack??error);try{await shot('failure');}catch{}}
finally{
 await writeFile(join(out,`${tag}-report.json`),JSON.stringify(report,null,2));
 if(app.exitCode===null&&app.signalCode===null)app.kill('SIGTERM');await ended;
 await log.close().catch(()=>{});server.close();await rm(iso,{recursive:true,force:true}).catch(()=>{});
}
console.log(JSON.stringify({status:report.status,checks:report.checks.length,error:report.error},null,1));
if(report.status!=='passed')process.exit(1);
