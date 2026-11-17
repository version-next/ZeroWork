/**
 * 浮动卡片普通拖动的惯性（drag-inertia，Pencil 规则帧 JmcNv：“面板不贴底时，下甩只是普通拖动 + 惯性，不收起”）。
 * 真实窗口、隔离数据目录、本机回环的假模型（不出网），harness 鼠标事件。每个主题跑一遍：
 *   1. 不贴底时快速甩动：松手后 AI 面板继续沿甩动方向滑行一段（逐帧采样：位置单调、越走越慢、不回头），
 *      然后停下；收起再从 launcher 打开，回到停下的位置（按“记住位置”保存）。截图 <theme>-1-glided.png。
 *   2. 甩向边缘：停在拖动区域边缘（标题栏以下整个窗口内缩 8：左边 x = 8），采样里从不越过边缘、停下后不回弹。
 *      截图 <theme>-2-edge.png。
 *   3. 慢拖松手（≈ 250 px/s，松手前停顿）：不滑行，停在松手处。
 *   4. 贴底时下甩：仍然走下滑收起（探针 anchor swipe），不滑行。
 * 减少动态效果另跑（reduced）：快速甩动也不滑行，停在松手处。
 *
 * Usage: node e2e/float_drag_inertia_native.ts <zerowork binary (test-mode)> <out dir> [light|dark] [motion|reduced]
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
if(!binaryArg||!outArg)throw new Error('usage: float_drag_inertia_native.ts <binary> <out> [light|dark] [motion|reduced]');
const out=resolve(outArg);await mkdir(out,{recursive:true});
const tag=mode==='reduced'?`${theme}-reduced`:theme;
const report:any={status:'running',theme,mode,checks:[] as string[],shots:[] as string[],samples:{} as any};

const server=createServer(async(req,res)=>{
 if(req.method!=='POST'){res.writeHead(200,{'Content-Type':'application/json'});res.end(JSON.stringify({data:[{id:'inertia-model',object:'model',context_length:32768}]}));return;}
 const request=await readRequestJson(req);if(isTitleRequest(request))return skipTitle(res);
 res.writeHead(200,{'Content-Type':'text/event-stream'});res.write('data: '+JSON.stringify({choices:[{index:0,delta:{content:'INERTIA_ANSWER'}}]})+'\n\n');res.end('data: [DONE]\n\n');
});
await new Promise<void>(r=>server.listen(0,'127.0.0.1',r));const port=(server.address() as any).port;
const iso=await realpath(await mkdtemp('/private/tmp/zw-drag-inertia-e2e-'));await chmod(iso,0o700);
const rpc=join(iso,'rpc'),data=join(iso,'data'),shell=join(iso,'shell');await mkdir(rpc);await mkdir(data);await mkdir(shell);
await writeFile(join(shell,'.zshenv'),"setopt NO_RCS\nPROMPT='in %% '\nRPROMPT=''\n");
await writeFile(join(data,'config.toml'),`[meta]\nconfig_revision=1\n[updates]\nauto_check=false\n[ui]\ntheme="${theme}"\n[ui.materials]\nblur_px=0\n[ai]\ndefault_provider="local"\n[[ai.providers]]\nid="local"\nkind="openai_compat"\nendpoint="http://127.0.0.1:${port}/v1/chat/completions"\napi_key="local-only"\nenabled=true\n[[ai.providers.models]]\nname="inertia-model"\ncontext_window=32768\ndefault=true\n`,{mode:0o600});
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const log=await open(join(out,`${tag}-app.log`),'w');
const env:any={...process.env,ZDOTDIR:shell,ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1',ZENIT_E2E_ISOLATE_KEYBOARD:'1',ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',OPENAI_API_KEY:'',ANTHROPIC_API_KEY:''};
for(const k of ['ZEROWORK_AI_MOCK','ZEROWORK_AI_ENDPOINT','ZEROWORK_AI_MODEL','ZEROWORK_AI_PROVIDER'])delete env[k];
if(mode==='reduced')env.ZENIT_A11Y_PREFS='reduce_motion';
const app=spawn(binaryArg,[],{env,stdio:['ignore',log.fd,log.fd]});
const ended=new Promise<void>(r=>app.once('close',()=>r()));
await h.waitForServerReady();

type R={x:number,y:number,w:number,h:number};
const W=1440,H=900;
// Drag region (float_card.dragRegion): everything below the title bar (44), inset 8.
const region={left:8,top:52,right:W-8,bottom:H-8};
const shown=(n:any)=>!!n&&n.hidden!==true&&n.visible!==false&&(n.effective_opacity??1)>0.02&&n.rect?.w>0&&n.rect?.h>0;
const node=(id:string,ms=12000)=>h.waitFor(async()=>(await h.query(id)).find(shown)??null,ms);
const isShown=async(id:string)=>(await h.query(id)).some(shown);
const center=(r:R)=>({x:r.x+r.w/2,y:r.y+r.h/2});
const click=async(id:string)=>{const n=await node(id);const c=center(n.rect);assert((await h.clickAt(c.x,c.y)).ok,'click '+id);};
const shot=async(name:string)=>{const path=join(out,`${tag}-${name}.png`);assert((await h.screenshot(path)).ok,name);report.shots.push(path);return path;};
const near=(a:number,b:number,label:string,tol=1.5)=>assert(Math.abs(a-b)<=tol,`${label}: ${a} vs ${b}`);
const probe=async()=>{const f=(await h.query('ai.panel.motion'))[0];const t=async(id:string)=>((await h.query(id))[0]?.text??'');return {rect:f?.rect as R,phase:await t('ai.panel.motion.phase'),anchor:await t('ai.panel.motion.anchor')};};
const atRest=async(phase:'expanded'|'collapsed',ms=6000)=>h.waitFor(async()=>{const p=await probe();return p.phase===phase?p:null;},ms);
const stable=async(id:string):Promise<R>=>{let last:R|null=null;return h.waitFor(async()=>{const r=(await node(id)).rect as R;const same=last&&Math.abs(last.x-r.x)<0.5&&Math.abs(last.y-r.y)<0.5&&Math.abs(last.w-r.w)<0.5&&Math.abs(last.h-r.h)<0.5;last=r;return same?r:null;},6000,120);};
const panel=async()=>{await atRest('expanded');return stable('ai.panel');};
const docked=(r:R)=>Math.max(r.y,0)+r.h>=region.bottom-24;
/** Press the AI grip, move by (dx, dy) in `steps` moves `stepMs` apart, release after `pauseMs`. Returns the
 *  pointer travel actually applied and the panel rect sampled right after the release, then every frame-ish
 *  for `watchMs` (the glide). */
async function fling(dx:number,dy:number,steps:number,stepMs:number,pauseMs:number,watchMs=1300){
 const g=(await node('ai.float.drag')).rect as R;const x=g.x+g.w/2,y=g.y+g.h/2;
 const before=(await node('ai.panel')).rect as R;
 await h.mouseMove(x,y);await h.mouseDown(x,y);
 for(let i=1;i<=steps;i++){await h.mouseMove(x+dx*i/steps,y+dy*i/steps);if(stepMs)await h.sleep(stepMs);}
 if(pauseMs)await h.sleep(pauseMs);
 await h.mouseUp(x+dx,y+dy);
 const t0=Date.now();const samples:{ms:number,x:number,y:number,w:number,h:number}[]=[];
 while(Date.now()-t0<watchMs){const n=(await h.query('ai.panel')).find(shown);if(n)samples.push({ms:Date.now()-t0,...(n.rect as R)});}
 return {before,released:{x:before.x+dx,y:before.y+dy},samples};
}
const openPanel=async()=>{await click('ai.launcher');return panel();};
/** Slow move (no glide in any mode): ≈ 200 px/s, a pause before the release. */
async function place(dx:number,dy:number){const steps=Math.max(4,Math.ceil(Math.hypot(dx,dy)/10));await fling(dx,dy,steps,50,200,0);return panel();}

try{
 await h.resizeWindow(W,H);await h.sleep(300);
 await click((await isShown('workspace.empty.local'))?'workspace.empty.local':'toolbar.new_session');
 if(!(await isShown('terminal.surface'))&&(await isShown('session.menu.local')))await click('session.menu.local');
 await node('terminal.surface');await h.sleep(500);

 const home=await openPanel();report.samples.home=home;
 assert(docked(home),'the default AI panel is bottom-docked');

 // ── 1. Not docked: a fast fling glides on, decelerates, stops; the landing place is remembered ──
 const lifted=await place(-500,-110);report.samples.lifted=lifted;
 assert(!docked(lifted),`lifted off the bottom (${JSON.stringify(lifted)})`);
 const f1=await fling(160,0,4,0,0);report.samples.fling=f1.samples;
 const landed=await panel();report.samples.landed=landed;
 assert.equal((await probe()).phase,'expanded','not docked: no collapse');
 near(landed.y,lifted.y,'a horizontal fling keeps y',1);
 if(mode==='reduced'){
  near(landed.x,f1.released.x,'reduce motion: no glide, rests where let go');
  assert(f1.samples.every(s=>s.x<=f1.released.x+0.5),'reduce motion: never drawn past the release point');
  report.checks.push('Reduce motion: a fast fling of the undocked panel rests where it is let go (no inertia)');
 }else{
  const past=landed.x-f1.released.x;report.samples.glide_distance=past;
  assert(past>=30,`glides on past the release point (${past} px)`);
  assert(landed.x+landed.w<=region.right+0.5,'inside the drag region');
  const xs=f1.samples.map(s=>s.x);
  for(let i=1;i<xs.length;i++)assert(xs[i]>=xs[i-1]-0.5,`never moves back (${xs[i-1]} → ${xs[i]})`);
  assert(xs.every(x=>x<=landed.x+0.5),'never past the landing point (no overshoot)');
  const moving=f1.samples.filter(s=>s.x>f1.released.x+1&&s.x<landed.x-1);
  assert(moving.length>=3,`animated, not a jump (${moving.length} intermediate samples)`);
  // Decelerates: the first 120 ms of the glide cover more than the 120 ms after 240 ms.
  const at=(ms:number)=>{const s=f1.samples.find(s=>s.ms>=ms);return s?s.x:landed.x;};
  assert(at(120)-at(0)>at(360)-at(240),`decelerates (${at(0)}, ${at(120)}, ${at(240)}, ${at(360)})`);
  report.checks.push(`Undocked fast fling: the panel glides ${Math.round(past)} px past the release point, decelerating, without overshoot`);
 }
 await h.mouseMove(600,400);await h.sleep(200);await shot('1-glided');
 await click('ai.collapse');await atRest('collapsed');
 const again=await openPanel();
 near(again.x,landed.x,'reopened at the landing x');near(again.y,landed.y,'reopened at the landing y');
 report.checks.push('The landing place is remembered: collapsed and reopened, the panel comes back there');

 // ── 2. Flung at the left edge: stops on the drag region edge, never past it, no bounce ──
 {const near_edge=await place(340-again.x,0);report.samples.near_edge=near_edge;
  // 240 px left fast: released ≈ 92 px from the edge, which any glide over ≈ 925 px/s reaches.
  const f2=await fling(-240,0,6,0,0);report.samples.edge=f2.samples;
  const r=await panel();report.samples.edge_rest=r;
  assert.equal((await probe()).phase,'expanded','no collapse');
  if(mode==='reduced'){near(r.x,f2.released.x,'reduce motion: rests where let go');}
  else{
   near(r.x,region.left,'stops on the left edge of the drag region (x = 8)',0.5);
   assert(f2.samples.every(s=>s.x>=region.left-0.5),'never past the edge (no overshoot)');
   const first=f2.samples.findIndex(s=>Math.abs(s.x-region.left)<0.5);
   assert(first>=0&&f2.samples.slice(first).every(s=>Math.abs(s.x-region.left)<0.5),'stays on the edge once there (no bounce)');
   report.checks.push('Flung at the left edge: the glide stops on the drag region edge (x = 8), never past it, no bounce');
  }
  await h.mouseMove(800,400);await h.sleep(200);await shot('2-edge');}

 // ── 3. Slow drag: no glide ──
 {const start=(await panel());
  const f3=await fling(200,0,20,40,0,900);report.samples.slow=f3.samples.slice(0,8);
  const r=await panel();near(r.x,f3.released.x,'slow drag: rests where let go (no glide)');
  assert(f3.samples.every(s=>s.x<=f3.released.x+1),'slow drag: never drawn past the release point');
  near(r.x,start.x+200,'moved by the pointer travel');
  report.checks.push('A slow drag (≈ 250 px/s) rests where it is let go, no glide');}

 // ── 4. Docked: a downward fling still collapses (swipe first) ──
 {const g=(await node('ai.float.drag')).rect as R;assert((await h.clickAt(g.x+g.w/2,g.y+g.h/2,2)).ok);await h.sleep(500);
  const d=await panel();assert(docked(d),'double click on the grip: back to the docked default');
  const f4=await fling(0,260,4,0,0,0);
  const s=await h.waitFor(async()=>{const p=await probe();return p.phase==='collapsing'||p.phase==='collapsed'?p:null;},3000,10);
  assert.equal(s.anchor,'swipe','docked downward fling collapses by swipe');
  await atRest('collapsed');await node('ai.launcher');report.samples.docked_fling=f4.released;
  report.checks.push('Docked: a downward fling still collapses by swipe (the swipe decision comes first)');
  await openPanel();}
 report.status='passed';
}catch(error){report.status='failed';report.error=String((error as any)?.stack??error);try{await shot('failure');}catch{}}
finally{
 await writeFile(join(out,`${tag}-report.json`),JSON.stringify(report,null,2));
 if(app.exitCode===null&&app.signalCode===null)app.kill('SIGTERM');await ended;
 await log.close().catch(()=>{});server.close();await rm(iso,{recursive:true,force:true}).catch(()=>{});
}
console.log(JSON.stringify({status:report.status,checks:report.checks.length,error:report.error},null,1));
if(report.status!=='passed')process.exit(1);
