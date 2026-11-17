/**
 * 浮动卡片出入场的三种表现（PLUGIN_ARCH_PLAN 2.5.7；Z12 / Z12b；`ui.float_card_transition`）。真实窗口、隔离数据目录、
 * 本机回环的假模型列表（不出网）。每个主题分三次启动：
 *   anchor（默认）：点 launcher 从图标展开（genie：锁时钟逐帧，开头帧窄、逐帧单调变宽）、收起收回图标；切 tab 收回到所属 tab、切回从 tab 展开。
 *   fade（设置为 "fade"）：所有出入场都在原位淡出 / 淡入并轻微缩放（Z12b fade_scale，约 0.97），不飞向锚点。
 *   reduced（ZENIT_A11Y_PREFS=reduce_motion，等同系统“减少动态效果”，模式仍为 anchor）：原位纯淡入淡出，矩形不变。
 * 判定读过渡探针 `ai.panel.motion`（本帧快照矩形 / 阶段 / 锚点名）；每种表现截取开、关、切 tab 的中间帧与结束帧。
 * 逐帧（open-motion，ai_float_motion_frames_lib.ts）：最后锁定动画时钟，逐帧截图走一遍切回 tab、收起、展开、切走，断言
 * 落地前后面板矩形变化 < 0.5pt、落地帧不闪、落地后 ≥ 500ms 面板区域像素不变（光标除外）、飞行中没有空白 / 闪烁帧、
 * anchor 展开时 launcher 在面板盖住它之前一直在。逐帧截图在 <out>/<theme>-<mode>-frames/<scene>/。
 *
 * Usage: node e2e/ai_float_motion_native.ts <zerowork binary (test-mode)> <out dir> [light|dark]
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {join,resolve} from 'node:path';
import {writeFile,mkdir,mkdtemp,realpath,open,rm} from 'node:fs/promises';
import {spawn} from 'node:child_process';
import * as h from '../vendor/zenit/e2e/client.ts';
import {shown} from './settings_nav.ts';
import {frameKit,measureScene,sceneFailures} from './ai_float_motion_frames_lib.ts';

const [binaryArg,outArg,theme='light']=process.argv.slice(2);
if(!binaryArg||!outArg)throw new Error('usage: ai_float_motion_native.ts <binary> <out> [light|dark]');
const out=resolve(outArg);await mkdir(out,{recursive:true});
const report:any={status:'running',theme,checks:[] as string[],shots:[] as string[],samples:{} as any};
const server=createServer((req,res)=>{res.writeHead(200,{'Content-Type':'application/json'});res.end(JSON.stringify({data:[{id:'motion-model',object:'model',context_length:32768,reasoning:false,vision:false}]}));});
await new Promise<void>(r=>server.listen(0,'127.0.0.1',r));const port=(server.address() as any).port;

type R={x:number,y:number,w:number,h:number};
const node=(id:string,ms=12000)=>h.waitFor(async()=>(await h.query(id)).find(shown)??null,ms);
const click=async(id:string)=>{const n=await node(id);if(!(await h.clickTestId(id)).ok)assert((await h.clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok,'click '+id);};
const probe=async()=>{const f=(await h.query('ai.panel.motion'))[0];const text=async(id:string)=>((await h.query(id))[0]?.text??'');return {rect:f?.rect as R,phase:await text('ai.panel.motion.phase'),anchor:await text('ai.panel.motion.anchor')};};
const atRest=async(phase:string,ms=6000)=>h.waitFor(async()=>{const p=await probe();return p.phase===phase?p:null;},ms);
const center=(r:R)=>({x:r.x+r.w/2,y:r.y+r.h/2});
const drag=async(x0:number,y0:number,x1:number,y1:number)=>{await h.mouseMove(x0,y0);await h.mouseDown(x0,y0);for(let i=1;i<=10;i++){await h.mouseMove(x0+(x1-x0)*i/10,y0+(y1-y0)*i/10);await h.sleep(16);}await h.mouseUp(x1,y1);};
// Click (by pointer, so it is one UI turn), then sample the probe while it is in flight; one screenshot mid flight.
const flight=async(id:string,name:string)=>{const n=await node(id);assert((await h.clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok,'click '+id);const samples:any[]=[];const t0=Date.now();let shot=false;
 while(Date.now()-t0<2000){const p=await probe();samples.push({ms:Date.now()-t0,...p});if(p.phase==='collapsing'||p.phase==='expanding'){if(!shot){shot=true;const path=join(out,`${theme}-${name}-mid.png`);if((await h.screenshot(path)).ok)report.shots.push(path);}}else if(samples.length>2)break;}
 await h.sleep(250);const end=join(out,`${theme}-${name}-end.png`);if((await h.screenshot(end)).ok)report.shots.push(end);return samples;};
const moving=(s:any[])=>s.filter(x=>x.phase==='collapsing'||x.phase==='expanding');

async function run(mode:'anchor'|'fade'|'reduced'){
 const iso=await realpath(await mkdtemp('/private/tmp/zw-ai-motion-e2e-')),rpc=join(iso,'rpc'),data=join(iso,'data');await mkdir(rpc);await mkdir(data);
 const transition=mode==='fade'?'fade':'anchor';
 await writeFile(join(data,'config.toml'),`[meta]\nconfig_revision=1\n[updates]\nauto_check=false\n[ui]\ntheme="${theme}"\nfloat_card_transition="${transition}"\n[ai]\ndefault_provider="local"\n[[ai.providers]]\nid="local"\nkind="openai_compat"\nendpoint="http://127.0.0.1:${port}/v1/chat/completions"\nenabled=true\n[[ai.providers.models]]\nname="motion-model"\ncontext_window=32768\ndefault=true\n`,{mode:0o600});
 process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
 const log=await open(join(out,`${theme}-${mode}-app.log`),'w');
 const env:any={...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1',ZENIT_E2E_ISOLATE_KEYBOARD:'1',ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',OPENAI_API_KEY:'',ANTHROPIC_API_KEY:''};
 if(mode==='reduced')env.ZENIT_A11Y_PREFS='reduce_motion';
 const app=spawn(binaryArg,[],{env,stdio:['ignore',log.fd,log.fd]});const ended=new Promise<void>(r=>app.once('close',()=>r()));
 const result:any={};
 try{
  await h.waitForServerReady();await h.resizeWindow(1440,900);await h.sleep(300);
  await click('workspace.empty.local');await node('terminal.surface');await h.sleep(600);
  const launcher=(await node('ai.launcher')).rect as R;
  // Open from the launcher.
  const open1=await flight('ai.launcher',`${mode}-open`);const home=(await atRest('expanded')).rect;result.open=open1;
  // The pointer clicked the launcher and stays put: the send button lands under it. Content an
  // AnchorTransition lands under a resting pointer is not hovered until the pointer moves (zenit
  // Cx.holdHoverOutsideLanded), so no tooltip opens; the first move hovers it again.
  {const c=center(launcher),hint=(await node('ai.send.hint')).rect as R;assert(c.x>=hint.x&&c.x<=hint.x+hint.w&&c.y>=hint.y&&c.y<=hint.y+hint.h,mode+': the send button lands under the resting pointer');
   await h.sleep(1200);assert(!(await h.query('ai.send.tooltip')).some(shown),mode+': no hover tooltip on content landed under a resting pointer');
   await h.mouseMove(c.x+2,c.y);await node('ai.send.tooltip',4000);await h.mouseMove(4,450);await h.waitFor(async()=>!(await h.query('ai.send.tooltip')).some(shown)||null,4000);
   report.checks.push(`${mode}: open under a resting pointer shows no send tooltip until the pointer moves`);}
  const m1=moving(open1);assert(m1.length>0,mode+': open is animated');
  // anchor: the genie picture's shape is checked frame by frame on the locked clock below (real-clock samples miss its first frames).
  if(mode==='anchor'){assert.equal(m1[0].anchor,'launcher');}
  else{if(mode==='fade')assert.equal(m1[0].anchor,'none');for(const s of m1){const c=center(s.rect),hc=center(home);assert(Math.abs(c.x-hc.x)<1.5&&Math.abs(c.y-hc.y)<1.5,mode+': stays centred in place');assert(s.rect.w>=home.w*(mode==='fade'?0.95:0.999)-0.5,mode+': at most a slight scale');}}
  // fade: the slight scale (Z12b fade_scale) is checked frame by frame on the locked clock below (real-clock samples can miss it).
  // Close into the launcher (or in place).
  const close1=await flight('ai.collapse',`${mode}-close`);result.close=close1;const rest=await atRest('collapsed');await node('ai.launcher');
  if(mode==='anchor'){const r=rest.rect;assert(Math.abs(r.x-launcher.x)<1.5&&Math.abs(r.w-launcher.w)<1.5,'anchor: folds into the launcher');}
  else for(const s of moving(close1)){const c=center(s.rect),hc=center(home);assert(Math.abs(c.x-hc.x)<1.5,mode+': closes in place');}
  // Tab switch: fold away from tab 1, unfold back.
  await click('ai.launcher');await atRest('expanded');
  await click('toolbar.new_session');await click('session.menu.local');await node('terminal.surface');
  const away=await atRest('collapsed');result.away=away;
  let cell:R|null=null;for(let id=1;id<=24&&!cell;id++){const n=(await h.query('tabs.cell.'+id)).find(shown);if(n)cell=n.rect;}
  if(mode==='anchor'){assert(away.anchor.startsWith('workspace.tab.'),'anchor: folds into the owner tab');assert(cell&&away.rect.x>=cell.x-1&&away.rect.x+away.rect.w<=cell.x+cell.w+1,'anchor: ends on the owner tab');}
  else if(mode==='fade')assert.equal(away.anchor,'none','fade: tab switch fades in place');
  // Reduced motion keeps the anchor mode but zenit fades in place: the resting frame is the card itself.
  let first:string|null=null;for(let id=1;id<=24&&!first;id++)if((await h.query('tabs.cell.'+id)).some(shown))first='tabs.cell.'+id;
  const back=await flight(first!,`${mode}-tab-back`);result.back=back;const restored=(await atRest('expanded')).rect;
  assert(Math.abs(restored.x-home.x)<1&&Math.abs(restored.y-home.y)<1,mode+': back at the same place');
  if(mode==='anchor')assert(moving(back).some(s=>s.anchor.startsWith('workspace.tab.')),'anchor: unfolds from the tab');
  let second:string|null=null;for(let id=24;id>=1&&!second;id--)if((await h.query('tabs.cell.'+id)).some(shown))second='tabs.cell.'+id;
  result.fold=await flight(second!,`${mode}-tab-away`);
  // Frame by frame on a locked clock: back to the owner tab, close, open, away again.
  await atRest('collapsed');await h.mouseMove(4,450);
  const fk=frameKit(h,shown);await fk.lock();
  try{
   await fk.settle(6);
   const fdir=join(out,`${theme}-${mode}-frames`);
   const press=async(id:string)=>{const n=await node(id,4000);assert((await h.clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok,'click '+id);};
   const scenes=[await fk.scene('tab-back',fdir,()=>press(first!)),await fk.scene('close',fdir,()=>press('ai.collapse')),
    await fk.scene('open',fdir,()=>press('ai.launcher')),await fk.scene('tab-away',fdir,()=>press(second!))];
   const measured=scenes.map(s=>measureScene(s));
   result.frames=measured.map(m=>({scene:m.scene,restAt:m.restAt,landing:m.landing,rectJump:m.rectJump,tail:m.tail,drops:m.drops,gaps:m.gaps}));
   await writeFile(join(fdir,'frames.json'),JSON.stringify(scenes.map((s:any)=>({name:s.name,restAt:s.restAt,frames:s.frames.map((f:any)=>({...f,png:undefined}))})),null,1));
   const failures=measured.flatMap(m=>sceneFailures(m));
   assert.deepEqual(failures,[],`${mode}: frame by frame`);
   if(mode==='fade'){const open=scenes[2];const finalW=(open.frames.at(-1).panel?.rect??open.frames.at(-1).motion).w;
    assert(open.frames.some((f:any)=>f.phase==='expanding'&&f.motion&&f.motion.w<finalW-1),'fade: scales slightly (Z12b fade_scale)');}
   if(mode==='anchor'){
    // genie (locked clock, every frame): the picture comes out of the launcher as a narrow strip and only widens until it
    // lands — the first moving frames are much narrower than the panel and no frame is narrower than the one before.
    const open=scenes[2];const widths=open.frames.filter((f:any)=>f.phase==='expanding'&&f.motion).map((f:any)=>f.motion.w as number);
    const finalW=(open.frames.at(-1).panel?.rect??open.frames.at(-1).motion).w;
    assert(widths.length>=6,'anchor: open is animated frame by frame');
    assert(widths[0]<finalW*0.3,`anchor: the first frame comes out of the launcher narrow (${widths[0].toFixed(1)} of ${finalW})`);
    for(let i=1;i<widths.length;i++)assert(widths[i]>=widths[i-1]-0.5,`anchor: the picture only widens (frame ${i}: ${widths[i-1].toFixed(1)} -> ${widths[i].toFixed(1)})`);
    result.open_widths=widths.map((w:number)=>+w.toFixed(1));
    report.checks.push('anchor: open is a genie out of the launcher — first frame narrow, widening monotonically every frame (locked clock)');
   }
  }finally{await fk.unlock();}
  report.checks.push(`${mode}: frame by frame — rect continuous at landing (< 0.5pt), no flash, still ≥ 500ms after landing, no blank frames`);
  report.checks.push(`${mode}: open, close and tab switch behave as ${mode==='anchor'?'flights into the launcher / owner tab':mode==='fade'?'in-place fade with a slight scale':'in-place plain fades'}`);
 }finally{if(app.exitCode===null&&app.signalCode===null)app.kill('SIGTERM');await ended;await log.close().catch(()=>{});await rm(iso,{recursive:true,force:true}).catch(()=>{});}
 return result;
}

try{
 for(const mode of ['anchor','fade','reduced'] as const)report.samples[mode]=await run(mode);
 report.status='passed';
}catch(e){report.status='failed';report.error=String((e as any)?.stack??e);await h.screenshot(join(out,`${theme}-failure.png`)).catch(()=>{});process.exitCode=1;}
finally{server.closeAllConnections();await new Promise<void>(r=>server.close(()=>r()));await writeFile(join(out,`report-${theme}.json`),JSON.stringify(report,null,2));}
console.log(report.status+': '+out);
