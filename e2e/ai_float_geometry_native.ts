/**
 * AI 浮动面板的几何与 Z12 过渡（PLUGIN_ARCH_PLAN 2.5.7、4c-3；需求总账 #52 与 #59）。真实窗口、隔离数据目录、
 * 本机回环的假模型列表（不出网）。每个主题跑一遍：
 *   1. 就近展开：图标在四个角时点开面板，首次打开的面板贴着图标所在的角展开（面板的那个角与图标外角相距 ≤ 4），
 *      尺寸按 #52 公式（宽 = clamp(tab 内容宽 × 0.42, 320, 420)，高 = clamp(tab 内容高 − 24, 280, 640)），完全落在浮动区域里；
 *      过渡锚点是 launcher（探针 `ai.panel.motion`），收起时收回图标，落地后图标才出现。
 *   2. 记住位置：拖动过的面板关上再打开，回到上次放下的位置；只有没拖过的才就近展开。
 *   3. 拖动区域（#62，11-13 用户判定）：标题栏（页签所在的 header）以下全部可停，内缩 8，可压住展开的侧栏和状态栏；最大化仍铺满工作区（去掉标题栏与侧栏），
 *      越过所属终端窗格；最大化等于浮动区域；八个方向缩放仍可用，双击把手回到图标旁、保留尺寸。
 *   4. 切换 tab：面板收向所属 tab 在 tab 条上的锚点（探针阶段与结束矩形落在该 tab 里），切回从 tab 展开回原位；
 *      快速来回切换中途改向，最终停在原位。
 *   5. 最小窗口（860 × 480）：拖动过与没拖过的面板都完全可见；窗口放大后回到用户放下的位置。
 * 截图：<theme>-*.png（四个角、记住位置、压住状态栏、最大化、tab 切换收回的中间帧与结束帧、最小窗口）。
 *
 * Usage: node e2e/ai_float_geometry_native.ts <zerowork binary (test-mode)> <out dir> [light|dark]
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {join,resolve} from 'node:path';
import {writeFile,mkdir,mkdtemp,realpath,open,rm} from 'node:fs/promises';
import {spawn} from 'node:child_process';
import * as h from '../vendor/zenit/e2e/client.ts';
import {shown} from './settings_nav.ts';

const [binaryArg,outArg,theme='light']=process.argv.slice(2);
if(!binaryArg||!outArg)throw new Error('usage: ai_float_geometry_native.ts <binary> <out> [light|dark]');
const out=resolve(outArg);await mkdir(out,{recursive:true});
const report:any={status:'running',theme,checks:[] as string[],shots:[] as string[],samples:{} as any,limits:['No offline fixture shows the bottom status bar (local terminals and KVM keep status in the pane header); Q20 is checked as the bottom edge reaching window − 8 inside the 26 pt status bar band.','Default ui.float_card_transition (anchor); fade and reduce motion are covered by ai_float_motion_native.']};

// Model list only (no chat request is sent): discovery never leaves loopback.
const server=createServer((req,res)=>{res.writeHead(200,{'Content-Type':'application/json'});res.end(JSON.stringify({data:[{id:'geometry-model',object:'model',context_length:32768,reasoning:false,vision:false}]}));});
await new Promise<void>(r=>server.listen(0,'127.0.0.1',r));const port=(server.address() as any).port;
const iso=await realpath(await mkdtemp('/private/tmp/zw-ai-float-e2e-')),rpc=join(iso,'rpc'),data=join(iso,'data');
await mkdir(rpc);await mkdir(data);
await writeFile(join(data,'config.toml'),`[meta]\nconfig_revision=1\n[updates]\nauto_check=false\n[ui]\ntheme="${theme}"\n[ai]\ndefault_provider="local"\n[[ai.providers]]\nid="local"\nkind="openai_compat"\nendpoint="http://127.0.0.1:${port}/v1/chat/completions"\nenabled=true\n[[ai.providers.models]]\nname="geometry-model"\ncontext_window=32768\ndefault=true\n`,{mode:0o600});
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const log=await open(join(out,`${theme}-app.log`),'w');
const app=spawn(binaryArg,[],{env:{...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1',ZENIT_E2E_ISOLATE_KEYBOARD:'1',ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',OPENAI_API_KEY:'',ANTHROPIC_API_KEY:''},stdio:['ignore',log.fd,log.fd]});
const ended=new Promise<void>(r=>app.once('close',()=>r()));
await h.waitForServerReady();

type R={x:number,y:number,w:number,h:number};
const node=(id:string,ms=12000)=>h.waitFor(async()=>(await h.query(id)).find(shown)??null,ms);
const hidden=(id:string,ms=8000)=>h.waitFor(async()=>(await h.query(id)).some(shown)?null:true,ms);
const click=async(id:string)=>{const n=await node(id);if(!(await h.clickTestId(id)).ok)assert((await h.clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok,'click '+id);};
const shot=async(name:string)=>{const path=join(out,`${theme}-${name}.png`);assert((await h.screenshot(path)).ok,name);report.shots.push(path);};
const near=(a:number,b:number,label:string,tol=1)=>assert(Math.abs(a-b)<=tol,`${label}: ${a} vs ${b}`);
const sameRect=(a:R,b:R,label:string,tol=1)=>{near(a.x,b.x,label+' x',tol);near(a.y,b.y,label+' y',tol);near(a.w,b.w,label+' w',tol);near(a.h,b.h,label+' h',tol);};
const clamp=(v:number,lo:number,hi:number)=>Math.min(hi,Math.max(lo,v));
const drag=async(x0:number,y0:number,x1:number,y1:number,steps=12)=>{await h.mouseMove(x0,y0);await h.mouseDown(x0,y0);for(let i=1;i<=steps;i++){await h.mouseMove(x0+(x1-x0)*i/steps,y0+(y1-y0)*i/steps);await h.sleep(16);}await h.mouseUp(x1,y1);};
const probe=async()=>{const f=(await h.query('ai.panel.motion'))[0];const text=async(id:string)=>((await h.query(id))[0]?.text??'');return {rect:f?.rect as R,phase:await text('ai.panel.motion.phase'),anchor:await text('ai.panel.motion.anchor')};};
const atRest=async(phase:'expanded'|'collapsed',ms=6000)=>h.waitFor(async()=>{const p=await probe();return p.phase===phase?p:null;},ms);
const panel=async():Promise<R>=>{await atRest('expanded');await node('ai.panel');let last:R|null=null;return h.waitFor(async()=>{const r=(await node('ai.panel')).rect;const stable=last&&Math.abs(last.x-r.x)<0.5&&Math.abs(last.y-r.y)<0.5&&Math.abs(last.w-r.w)<0.5&&Math.abs(last.h-r.h)<0.5;last=r;return stable?r:null;},6000,80);};
let windowSize={w:1440,h:900};const resize=async(w:number,hh:number)=>{windowSize={w,h:hh};assert((await h.resizeWindow(w,hh)).ok,'resize');};
const viewport=async()=>windowSize;
// 2.5.7: window content − title bar (44) − expanded sidebar, inset 8; the status bar is inside.
const region=async():Promise<R>=>{const v=await viewport();const side=(await h.query('workspace.sidebar')).find(shown);const left=(side?side.rect.x+side.rect.w:0)+8;return {x:left,y:52,w:v.w-8-left,h:v.h-8-52};};
const inside=(p:R,g:R,label:string)=>assert(p.x>=g.x-0.5&&p.y>=g.y-0.5&&p.x+p.w<=g.x+g.w+0.5&&p.y+p.h<=g.y+g.h+0.5,`${label}: ${JSON.stringify(p)} outside ${JSON.stringify(g)}`);
const openPanel=async()=>{await click('ai.launcher');return panel();};
const closePanel=async()=>{await node('ai.panel');if(!(await h.clickTestId('ai.collapse')).ok)await h.key('j',{cmd:true});await atRest('collapsed');await node('ai.launcher');};
const grip=async()=>(await node('ai.float.drag')).rect;
const movePanel=async(dx:number,dy:number)=>{const g=await grip();await drag(g.x+g.w/2,g.y+g.h/2,g.x+g.w/2+dx,g.y+g.h/2+dy);await h.sleep(200);return panel();};
const tabCells=async()=>{const all:any[]=[];for(let id=1;id<=24;id++){const n=(await h.query('tabs.cell.'+id)).find(shown);if(n)all.push({...n,test_id:'tabs.cell.'+id});}return all.sort((a,b)=>a.rect.x-b.rect.x);};
const midShot=async(clickId:string,name:string)=>{const n=await node(clickId);assert((await h.clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok,'click '+clickId);const samples:any[]=[];const t0=Date.now();let shotTaken=false;while(Date.now()-t0<1500){const p=await probe();samples.push({ms:Date.now()-t0,...p});if(p.phase==='collapsing'||p.phase==='expanding'){if(!shotTaken){shotTaken=true;const path=join(out,`${theme}-${name}.png`);if((await h.screenshot(path)).ok)report.shots.push(path);samples.push({ms:Date.now()-t0,shot:true,...(await probe())});}}else if(samples.length>2)break;}return samples;};
// The probe is written once per frame after layout: wait for the resting frame to land in `target`.
const restIn=async(target:R,label:string,tol=1.5)=>{let last:any=null;try{return await h.waitFor(async()=>{const q=await probe();last=q;const r=q.rect;return q.phase==='collapsed'&&r&&r.x>=target.x-tol&&r.y>=target.y-tol&&r.x+r.w<=target.x+target.w+tol&&r.y+r.h<=target.y+target.h+tol?q:null;},4000);}catch{throw new Error(label+': '+JSON.stringify(last)+' not in '+JSON.stringify(target));}};
const cornerOf=(r:R,corner:string)=>({x:corner.endsWith('right')?r.x+r.w:r.x,y:corner.startsWith('bottom')?r.y+r.h:r.y});

try{
 await resize(1440,900);await h.sleep(300);
 await click(((await h.query('workspace.empty.local')).some(shown))?'workspace.empty.local':'toolbar.new_session');if(!(await h.query('terminal.surface')).some(shown)&&(await h.query('session.menu.local')).some(shown))await click('session.menu.local');await node('terminal.surface');await h.sleep(600);
 const pane=(await node('workspace.pane')).rect as R;const area=await region();report.pane=pane;report.region=area;

 // 1. Unfolds beside the launcher in every corner (the panel has never been moved).
 const expectW=clamp(pane.w*0.42,320,420),expectH=clamp(pane.h-24,280,640);
 const corners=[['bottom_right',0.8,0.8],['bottom_left',0.2,0.8],['top_left',0.2,0.25],['top_right',0.8,0.25]] as const;
 for(const [corner,fx,fy] of corners){
  if(corner!=='bottom_right'){const l=(await node('ai.launcher')).rect;await drag(l.x+24,l.y+24,pane.x+pane.w*fx,pane.y+pane.h*fy);await h.sleep(500);}
  const l=(await node('ai.launcher')).rect as R;
  if(corner==='bottom_right')report.samples.unfolding=await midShot('ai.launcher',`corner-${corner}-unfolding`);
  else await click('ai.launcher');
  const p=await panel();const pr=await probe();
  assert.equal(pr.anchor,'launcher',`${corner}: opens out of the launcher`);
  near(p.w,expectW,corner+' #52 width');near(p.h,expectH,corner+' #52 height');
  const pc=cornerOf(p,corner),lc=cornerOf(l,corner);const gap=Math.hypot(pc.x-lc.x,pc.y-lc.y);
  assert(gap<=4,`${corner}: panel corner ${JSON.stringify(pc)} is ${gap} from the launcher corner ${JSON.stringify(lc)}`);
  inside(p,area,corner+' inside the floating region');assert(!(await h.query('ai.launcher')).some(shown),'launcher hidden while open');
  report.samples[corner]={launcher:l,panel:p,gap};await shot(`corner-${corner}`);
  await click('ai.collapse');
  const flying=await h.waitFor(async()=>{const q=await probe();return q.phase==='collapsing'||q.phase==='collapsed'?q:null;},3000);
  assert.equal(flying.anchor,'launcher',corner+' folds into the launcher');
  // open-motion: the icon shows again as soon as the folding panel no longer covers it opaquely (it settles into the icon).
  if(flying.phase==='collapsing'&&(await h.query('ai.launcher')).some(shown)){const q=await probe();const op=Number(((await h.query('ai.panel.motion.opacity'))[0]?.text)??'0');
   const covers=q.rect&&q.rect.x<=l.x&&q.rect.y<=l.y&&q.rect.x+q.rect.w>=l.x+l.w&&q.rect.y+q.rect.h>=l.y+l.h;assert(q.phase!=='collapsing'||!(covers&&op>=0.98),'launcher only shows once the folding panel no longer covers it');}
  await restIn(l,corner+' fold ends in the launcher');await node('ai.launcher');
 }
 report.checks.push(`First open unfolds beside the launcher in all four corners (corner gap ≤ 4), #52 size ${expectW}×${expectH}, inside the floating region; closing folds back into the launcher, which shows again once the folding panel no longer covers it`);
 {const l=(await node('ai.launcher')).rect;await drag(l.x+24,l.y+24,pane.x+pane.w*0.8,pane.y+pane.h*0.8);await h.sleep(500);}

 // 2. A moved panel comes back where it was dropped.
 await openPanel();const dropped=await movePanel(-360,-180);
 await closePanel();const again=await openPanel();sameRect(again,dropped,'reopen at the dropped rectangle');await shot('remembered');
 report.checks.push('After a drag the tab reopens its panel at the dropped rectangle');

 // 3. Drag region (#62, 2026-11-13: everything below the title bar, sidebar included, inset 8); maximize fills the work area (4c-3).
 const left=await movePanel(-3000,0);near(left.x,8,'left edge = window + 8 (#62: covers the expanded sidebar)');assert(left.x<area.x-1,'panel goes over the expanded sidebar');
 const top=await movePanel(0,-3000);near(top.y,52,'top edge = title bar 44 + 8 (#62: the tab header stays clear)');
 const right=await movePanel(3000,0);near(right.x+right.w,area.x+area.w,'right edge = window − 8');
 const bottom=await movePanel(0,3000);const v=await viewport();near(bottom.y+bottom.h,v.h-8,'bottom edge = window − 8');
 // Q20: nothing reserves the status bar band (26 pt above the window bottom, SSH tabs). Offline fixtures
 // have no bottom status bar (local / KVM show status in the pane header), so the band is checked by geometry.
 assert(bottom.y+bottom.h>v.h-26+1,'panel reaches into the status bar band (Q20)');
 const surface=(await node('terminal.surface')).rect as R;assert(top.y<surface.y-1,'panel crosses the owner terminal surface (above its top edge)');
 report.samples.edges={left,top,right,bottom,pane,surface};await shot('edge-bottom');
 await click('ai.maximize');const max=await panel();sameRect(max,area,'maximize fills the floating region');await shot('maximized');
 await click('ai.maximize');const restored=await panel();sameRect(restored,bottom,'restore');
 report.checks.push('Drops reach the drag region edges (8 over the sidebar, 52 below the title bar, window − 8) into the status bar band and across the terminal surface; maximize equals the work area');
 await movePanel(-260,-100);
 for(const edge of ['n','s','w','e','nw','ne','sw','se']){const before=await panel();const n=(await node('ai.float.resize.'+edge)).rect,x=n.x+n.w/2,y=n.y+n.h/2,dx=edge.includes('w')?-24:edge.includes('e')?24:0,dy=edge.includes('n')?-16:edge.includes('s')?16:0;await drag(x,y,x+dx,y+dy,4);const after=await panel();assert(Math.abs(after.w-before.w)>1||Math.abs(after.h-before.h)>1,'resize '+edge);}
 {const before=await panel();const g=await grip();assert((await h.clickAt(g.x+g.w/2,g.y+g.h/2,2)).ok);const reset=await panel();near(reset.w,before.w,'reset keeps width');near(reset.h,before.h,'reset keeps height');const l=launcherRect(pane);const c=cornerOf(reset,'bottom_right');assert(Math.hypot(c.x-l.x-l.w,c.y-l.y-l.h)<=4,'double click returns beside the launcher');}
 report.checks.push('Eight resize directions still work; grip double click returns beside the launcher keeping the size');

 // 4. Tab switch: fold into the owner tab, unfold back to the same place.
 const home=await movePanel(-300,-160);
 await click('toolbar.new_session');await click('session.menu.local');await node('terminal.surface');
 const cells=await tabCells();assert(cells.length>=2,'two tabs');const first=cells[0],second=cells[1];const firstId=first.test_id.slice('tabs.cell.'.length);
 const cell=(await node(first.test_id)).rect as R;const folded=await restIn(cell,'fold ends on the owner tab');assert.equal(folded.anchor,'workspace.tab.'+firstId,'folds into the owner tab');
 await h.sleep(300);await shot('tab-switch-folded');
 // Mid flight while unfolding back into place, then the end frame.
 report.samples.unfolding_tab=await midShot(first.test_id,'tab-switch-unfolding');
 const back=await panel();sameRect(back,home,'switching back restores the dropped rectangle');assert.equal((await probe()).anchor,'workspace.tab.'+firstId);await shot('tab-switch-restored');
 const folding=await midShot(second.test_id,'tab-switch-folding');report.samples.folding_tab=folding;
 assert(folding.some((x:any)=>x.phase==='collapsing'&&x.anchor==='workspace.tab.'+firstId),'collapsing toward the owner tab was observed');
 await restIn((await node(first.test_id)).rect,'second fold ends on the owner tab');
 await h.sleep(300);await shot('tab-switch-folded-end');
 // Rapid back-and-forth: reverses mid flight, ends at home without queueing.
 await click(first.test_id);await h.sleep(60);await click(second.test_id);await h.sleep(60);await click(first.test_id);
 const settled=await panel();sameRect(settled,home,'rapid switching ends at home');
 report.checks.push('Switching tabs folds the panel into its own tab on the strip and unfolds it back to the dropped rectangle; rapid switching retargets and settles at home');

 // 5. Smallest window: both a moved and a never-moved panel stay fully visible; growing restores.
 await resize(860,480);await h.sleep(500);const v2=await viewport();const small={x:8,y:52,w:v2.w-16,h:v2.h-60};const clamped=await panel();inside(clamped,small,'moved panel in the smallest window');await shot('min-window-moved');
 await click(second.test_id);await atRest('collapsed');const fresh=await openPanel();inside(fresh,small,'default panel in the smallest window');
 const sl=(await h.query('workspace.pane')).find(shown)?.rect as R;report.samples.min={region:small,moved:clamped,fresh,pane:sl};await shot('min-window-default');
 await closePanel();await click(first.test_id);await resize(1440,900);await h.sleep(500);const grown=await panel();sameRect(grown,home,'growing the window returns to the dropped rectangle');
 report.checks.push('In the 860 × 480 window both panels are fully inside the floating region; growing the window restores the dropped rectangle');
 report.status='passed';
}catch(e){report.status='failed';report.error=String((e as any)?.stack??e);report.debug={probe:await probe().catch(()=>null),panel:await h.query('ai.panel').catch(()=>null),launcher:await h.query('ai.launcher.anchor').catch(()=>null)};await h.screenshot(join(out,`${theme}-failure.png`)).catch(()=>{});process.exitCode=1;}
finally{if(app.exitCode===null&&app.signalCode===null)app.kill('SIGTERM');await ended;await log.close().catch(()=>{});await rm(iso,{recursive:true,force:true}).catch(()=>{});server.closeAllConnections();await new Promise<void>(r=>server.close(()=>r()));await writeFile(join(out,`report-${theme}.json`),JSON.stringify(report,null,2));}
console.log(report.status+': '+out);

function launcherRect(p:R):R{return {x:p.x+p.w-24-48,y:p.y+p.h-20-48,w:48,h:48};}
