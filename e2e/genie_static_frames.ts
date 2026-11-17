/**
 * genie-static：浮动卡片过渡“只画一张静态纹理”的逐帧验收与取证（open-motion 的逐帧方法，见 ai_float_motion_frames_lib.ts）。
 *
 * 真实窗口、test-mode、隔离数据目录，锁定 zenit 动画时钟逐帧推进并截图。场景（AI 卡片）：
 *   open（点 launcher 展开）、close（收回 launcher）、tab-away（切走，收回所属 tab）、tab-back（切回，从 tab 展开）、
 *   dock（放入分屏：窗格从浮动矩形飞入）、float（窗格头部“浮动”：卡片从窗格矩形展开回浮动位置）。
 * 每个场景记录：
 *   - zenit `/stats.anchor_flight`（ZENIT_ANCHOR_FLIGHT_PROBE=1）：飞行帧里该子树的布局次数、绘制命令数（必须为 0）、私有渲染次数、落地次数；
 *   - 渲染端过渡纹理：复用 / 光栅化 / 不可缓存次数，genie 网格单元数；
 *   - 每帧 CPU / GPU 耗时（cpu_frame_us、gpu_execute_us、layout_us、render_gen_us、gpu_encode_us、total_frame_us）；
 *   - 像素判定：落地帧与上一帧最大通道差 ≤ 4；落地后 600ms 内相邻帧像素差为 0；没有空白帧（飞行中区域与“没有卡片”的参照完全相同），
 *     没有闪帧（A-B-A，同 ai_float_motion_frames_lib）。
 * 输出 <out>/<theme>-<mode>/<scene>/f_<k>.png、sheet-<scene>.png（逐帧对照条带图）、measure-<theme>-<mode>.json。
 * 旧构建（没有 anchor_flight / 过渡纹理计数）也能跑：这些字段记为 null，只出条带图、像素量与耗时，用作修复前对照。
 *
 * Usage: node e2e/genie_static_frames.ts <zerowork binary (test-mode)> <out dir> [light|dark] [anchor,fade,reduced] [--tail N] [--no-probe] [--scenes a,b]
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {join,resolve} from 'node:path';
import {writeFile,mkdir,mkdtemp,realpath,open,rm} from 'node:fs/promises';
import {spawn} from 'node:child_process';
import * as h from '../vendor/zenit/e2e/client.ts';
import {decodePng,writeRgbPng} from '../vendor/zenit/e2e/png.ts';
import {shown} from './settings_nav.ts';

type R={x:number,y:number,w:number,h:number};
const STEP=1000/60,LANDING_MAX=4,PAD=30,SCALE=2;
const args=process.argv.slice(2);
const remeasure=args[0]==='--remeasure'?args.splice(0,2)[1]:null;
const flag=(name:string)=>{const i=args.indexOf(name);if(i<0)return null;const v=args[i+1];args.splice(i,2);return v;};
const bool=(name:string)=>{const i=args.indexOf(name);if(i<0)return false;args.splice(i,1);return true;};
const tail=Number(flag('--tail')??36);
const onlyScenes=(flag('--scenes')??'').split(',').filter(Boolean);
const probe=!bool('--no-probe');
const [binaryArg,outArg,theme='light',modesArg='anchor,fade,reduced']=args;
if(!binaryArg||!outArg)throw new Error('usage: genie_static_frames.ts <binary> <out> [light|dark] [modes] [--tail N] [--no-probe] [--scenes a,b]');
const out=resolve(outArg);await mkdir(out,{recursive:true});
const server=createServer((req,res)=>{res.writeHead(200,{'Content-Type':'application/json'});res.end(JSON.stringify({data:[{id:'motion-model',object:'model',context_length:32768,reasoning:false,vision:false}]}));});
await new Promise<void>(r=>server.listen(0,'127.0.0.1',r));const port=(server.address() as any).port;
const node=(id:string,ms=12000)=>h.waitFor(async()=>(await h.query(id)).find(shown)??null,ms);
const one=async(id:string)=>(await h.query(id)).find(shown)??null;
const text=async(id:string)=>((await h.query(id))[0]?.text??'');
const TIMING=['cpu_frame_us','gpu_execute_us','layout_us','render_gen_us','gpu_encode_us','total_frame_us'];

const lock=async()=>{const r:any=await h.request('POST','/clock',{step_ms:STEP,locked:true});if(r?.error)throw new Error('clock: '+JSON.stringify(r));};
const unlock=async()=>{await h.request('POST','/clock',{step_ms:0});};
const advance=async()=>{const a:any=await h.request('POST','/clock/advance',{ms:STEP});if(a?.error)throw new Error('advance: '+JSON.stringify(a));
 for(let i=0;i<2000;i++){const s:any=await h.request('GET','/stats');if(!(s.clock_budget_ms>0))break;await h.sleep(4);}};

async function sample(dir:string,k:number){
 const st:any=await h.stats();
 const rect=async(id:string)=>{const n=await one(id);return n?n.rect as R:null;};
 let caret:R|null=null;try{const s=await h.inputState('ai.prompt');caret=(s as any).cursor_rect??null;}catch{}
 const rec:any={k,phase:await text('ai.panel.motion.phase'),motion:(await h.query('ai.panel.motion'))[0]?.rect??null,opacity:Number(await text('ai.panel.motion.opacity')),
  panel:await rect('ai.panel'),pane:await rect('ai.pane'),launcher:await rect('ai.launcher.anchor'),caret,
  flight:st.anchor_flight??null,tex:st.transition_texture_hits===undefined?null:{hits:st.transition_texture_hits,rasters:st.transition_texture_rasters,uncached:st.transition_texture_uncached,cells:st.genie_mesh_cells},
  timing:Object.fromEntries(TIMING.map(f=>[f,st[f]??null]))};
 const png=join(dir,`f_${String(k).padStart(3,'0')}.png`);const s=await h.screenshot(png);if(s.ok)rec.png=png;
 return rec;
}

/** One scene: act on the locked clock, then step frame by frame until the run rests plus `tail` frames. */
async function scene(name:string,base:string,act:()=>Promise<void>,anchorOf:()=>Promise<R|null>){
 const dir=join(base,name);await mkdir(dir,{recursive:true});
 const anchor=await anchorOf();
 const frames:any[]=[await sample(dir,0)];
 await act();await h.mouseMove(4,450);
 let restAt=-1,moved=false;
 const landings0=frames[0].flight?.landings??null;
 for(let k=1;k<=240;k++){
  await advance();const rec=await sample(dir,k);frames.push(rec);
  const landed=landings0!==null&&rec.flight&&rec.flight.landings>landings0;
  const animating=rec.flight?(rec.flight.flight_frames>frames[k-1].flight.flight_frames&&!landed):(rec.phase==='collapsing'||rec.phase==='expanding');
  if(animating)moved=true;
  if(restAt<0&&(landed||(moved&&!animating)))restAt=k;
  if(restAt<0&&!moved&&k>=24)restAt=k;
  if(restAt>=0&&k-restAt>=tail)break;
 }
 return {name,restAt,moved,anchor,frames};
}

const unite=(a:R|null,b:R|null):R|null=>{if(!a)return b;if(!b)return a;const x=Math.min(a.x,b.x),y=Math.min(a.y,b.y);return {x,y,w:Math.max(a.x+a.w,b.x+b.w)-x,h:Math.max(a.y+a.h,b.y+b.h)-y};};

/** Pixel and probe measurements of one scene (reads the PNGs it wrote). */
function measure(s:any,img:{w:number,h:number}){
 const fr=s.frames,R=s.restAt;
 let region:R|null=s.anchor;for(const f of fr){region=unite(region,f.panel);region=unite(region,f.pane);}
 region=region??{x:0,y:0,w:img.w/SCALE,h:img.h/SCALE};
 const x0=Math.max(0,Math.floor((region.x-PAD)*SCALE)),y0=Math.max(0,Math.floor((region.y-PAD)*SCALE));
 const x1=Math.min(img.w,Math.ceil((region.x+region.w+PAD)*SCALE)),y1=Math.min(img.h,Math.ceil((region.y+region.h+PAD)*SCALE));
 const RW=x1-x0,RH=y1-y0;
 const imgs:Uint8Array[]=fr.map((f:any)=>{const p=decodePng(f.png);const o=new Uint8Array(RW*RH*3);
  for(let y=y0;y<y1;y++)for(let x=x0;x<x1;x++){const i=(y*p.width+x)*p.channels,j=((y-y0)*RW+(x-x0))*3;o[j]=p.pixels[i];o[j+1]=p.pixels[i+1];o[j+2]=p.pixels[i+2];}
  return o;});
 const masks=fr.map((f:any)=>{const c=f.caret;return c&&c.w>0?{x0:(c.x-3)*SCALE,x1:(c.x+c.w+3)*SCALE,y0:(c.y-3)*SCALE,y1:(c.y+c.h+3)*SCALE}:null;});
 const masked=(i:number,x:number,y:number)=>{for(const j of [i,i-1]){const c=j>=0?masks[j]:null;if(c&&x>=c.x0&&x<c.x1&&y>=c.y0&&y<c.y1)return true;}return false;};
 const diff=(i:number,j:number)=>{let n=0,mx=0;const a=imgs[i],b=imgs[j];
  for(let y=y0;y<y1;y++)for(let x=x0;x<x1;x++){if(masked(i,x,y)||masked(j,x,y))continue;const o=((y-y0)*RW+(x-x0))*3;
   const d=Math.max(Math.abs(a[o]-b[o]),Math.abs(a[o+1]-b[o+1]),Math.abs(a[o+2]-b[o+2]));if(d>0){n++;if(d>mx)mx=d;}}
  return {n,max:mx};};
 const landing=R>0?diff(R,R-1):{n:0,max:0};
 // After the landing, the card's own rect (expand) or the anchor (collapse), shadow included: a terminal caret elsewhere
 // in the region (the tab body under the strip) blinks on its own and is not part of the card.
 const last=fr.at(-1);const subject:R|null=last.pane??last.panel??s.anchor;
 const inSubject=(x:number,y:number)=>!subject||(x>=(subject.x-PAD)*SCALE&&x<(subject.x+subject.w+PAD)*SCALE&&y>=(subject.y-PAD)*SCALE&&y<(subject.y+subject.h+PAD)*SCALE);
 const diffIn=(i:number,j:number)=>{let n=0,mx=0;const a=imgs[i],b=imgs[j];
  for(let y=y0;y<y1;y++)for(let x=x0;x<x1;x++){if(!inSubject(x,y)||masked(i,x,y)||masked(j,x,y))continue;const o=((y-y0)*RW+(x-x0))*3;
   const d=Math.max(Math.abs(a[o]-b[o]),Math.abs(a[o+1]-b[o+1]),Math.abs(a[o+2]-b[o+2]));if(d>0){n++;if(d>mx)mx=d;}}
  return {n,max:mx};};
 const tailDiffs:any[]=[];for(let i=R+1;i<fr.length;i++){const d=diffIn(i,i-1);if(d.n)tailDiffs.push({k:fr[i].k,...d});}
 const tailMs=(fr.length-1-R)*STEP;
 // Blank frames: a flight frame identical to "no card here" (the rest frame without the card).
 const collapse=fr[0].panel&&!fr.at(-1).panel&&!fr.at(-1).pane;
 const expand=!fr[0].panel&&!fr[0].pane&&(fr.at(-1).panel||fr.at(-1).pane);
 const bare=collapse?fr.length-1:expand?0:-1;
 // A frame whose run has faded the picture out (probe opacity < 0.05, the end of a fade) shows nothing by design.
 const blanks:number[]=[];if(bare>=0)for(let i=1;i<R;i++){if(Number.isFinite(fr[i].opacity)&&fr[i].opacity<0.05)continue;if(diff(i,bare).n===0)blanks.push(fr[i].k);}
 // Flash frames (A-B-A), as in ai_float_motion_frames_lib.
 const aba=(i:number)=>{const a=imgs[i-1],b=imgs[i],c=imgs[i+1];let total=0,around=0,prev=0,next=0;
  for(let y=y0;y<y1;y+=2)for(let x=x0;x<x1;x+=2){if(masked(i,x,y)||masked(i+1,x,y))continue;const o=((y-y0)*RW+(x-x0))*3;total++;
   const d=(p:Uint8Array,q:Uint8Array)=>Math.max(Math.abs(p[o]-q[o]),Math.abs(p[o+1]-q[o+1]),Math.abs(p[o+2]-q[o+2]))<=2;
   if(d(a,c))around++;if(d(b,a))prev++;if(d(b,c))next++;}
  return total?{around:around/total,mid:Math.min(prev,next)/total}:{around:1,mid:1};};
 const drops:any[]=[];for(let i=1;i<=Math.min(R+1,fr.length-2);i++){const {around,mid}=aba(i);if(around-mid>0.05)drops.push({k:fr[i].k,spike:+(around-mid).toFixed(3)});}
 // Probe deltas over the run (frame 0 -> landing frame).
 const delta=(key:string)=>{const a=fr[0].flight,b=fr[Math.max(R,0)]?.flight;return a&&b?b[key]-a[key]:null;};
 const tdelta=(key:string)=>{const a=fr[0].tex,b=fr[Math.max(R,0)]?.tex;return a&&b?b[key]-a[key]:null;};
 let redrawsAfterFirst=0;for(let i=2;i<=Math.max(R,1)&&i<fr.length;i++){const a=fr[i-1].tex,b=fr[i].tex;if(a&&b)redrawsAfterFirst+=(b.rasters-a.rasters)+(b.uncached-a.uncached);}
 const flight={redraws_after_first:redrawsAfterFirst,flight_frames:delta('flight_frames'),subtree_layout_frames:delta('subtree_layout_frames'),subtree_layouts:delta('subtree_layouts'),subtree_paint_items:delta('subtree_paint_items'),
  captures:delta('captures'),retargets:delta('retargets'),landings:delta('landings'),
  texture_hits:tdelta('hits'),texture_rasters:tdelta('rasters'),texture_uncached:tdelta('uncached'),mesh_cells:tdelta('cells')};
 // Per-frame timings of the flight frames (1..R-1).
 const timing:any={};for(const f of TIMING){const v=fr.slice(1,Math.max(R,1)).map((x:any)=>x.timing[f]).filter((x:any)=>typeof x==='number').sort((a:number,b:number)=>a-b);
  timing[f]=v.length?{n:v.length,mean:Math.round(v.reduce((a:number,b:number)=>a+b,0)/v.length),p50:v[Math.floor(v.length/2)],p95:v[Math.min(v.length-1,Math.floor(v.length*0.95))],max:v.at(-1)}:null;}
 return {scene:s.name,restAt:R,frames:fr.length,region,landing,tailMs,tail:tailDiffs,blanks,drops,flight,timing,crop:{x0,y0,RW,RH}};
}

function failures(m:any,expectProbe:boolean):string[]{
 const f:string[]=[];
 if(m.restAt<1)f.push(`${m.scene}: never came to rest`);
 if(m.landing.max>LANDING_MAX)f.push(`${m.scene}: landing frame differs from the frame before by ${m.landing.max} (> ${LANDING_MAX}, ${m.landing.n} px)`);
 if(m.tailMs<590)f.push(`${m.scene}: only ${m.tailMs.toFixed(0)}ms sampled after landing`);
 if(m.tail.length)f.push(`${m.scene}: redraw after landing at ${m.tail.map((t:any)=>`${t.k}(${t.n}px,max ${t.max})`).join(' ')}`);
 if(m.blanks.length)f.push(`${m.scene}: blank frames ${m.blanks.join(',')}`);
 if(m.drops.length)f.push(`${m.scene}: flash frames ${JSON.stringify(m.drops)}`);
 if(expectProbe){
  if(m.flight.subtree_layouts!==0||m.flight.subtree_layout_frames!==0)f.push(`${m.scene}: subtree laid out in flight (${m.flight.subtree_layouts} layouts in ${m.flight.subtree_layout_frames} frames)`);
  if(m.flight.subtree_paint_items!==0)f.push(`${m.scene}: subtree painted in flight (${m.flight.subtree_paint_items} items)`);
  if(m.flight.landings===0&&m.flight.flight_frames)f.push(`${m.scene}: no landing recorded`);
  // The picture is one cached texture: only composited after it is rasterized (the content's own animated images may
  // re-rasterize it now and then); a texture that is redrawn on most steps is not cached.
  // After the first step (where the picture is rasterized) the texture is composited only; a few re-rasters (outer surface
  // re-alignment, content images) are tolerated, a texture redrawn on a third of the steps or more is not cached.
  if(m.flight.texture_hits!==null&&m.flight.redraws_after_first>Math.max(2,m.restAt/3))f.push(`${m.scene}: transition texture redrawn ${m.flight.redraws_after_first} times after the first step (not cached)`);
 }
 return f;
}

/** Contact sheet: frames 0..rest+2 of the scene, cropped to the measured region. */
function sheet(path:string,s:any,m:any){
 const frames=s.frames.slice(0,Math.min(s.frames.length,m.restAt+3));
 const {x0,y0,RW,RH}=m.crop;const tw=360,scale=tw/RW,th=Math.max(1,Math.round(RH*scale));
 const cols=Math.min(8,frames.length),rows=Math.ceil(frames.length/cols),gap=6;
 const W=cols*tw+(cols+1)*gap,H=rows*th+(rows+1)*gap;const px=new Uint8Array(W*H*3).fill(48);
 frames.forEach((f:any,i:number)=>{const p=decodePng(f.png);const ox=gap+(i%cols)*(tw+gap),oy=gap+Math.floor(i/cols)*(th+gap);
  for(let y=0;y<th;y++)for(let x=0;x<tw;x++){const sx=x0+Math.floor(x/scale),sy=y0+Math.floor(y/scale);if(sx>=p.width||sy>=p.height)continue;
   const si=(sy*p.width+sx)*p.channels,o=((oy+y)*W+ox+x)*3;px[o]=p.pixels[si];px[o+1]=p.pixels[si+1];px[o+2]=p.pixels[si+2];}
  // landing frame marker: a 4px bar under the tile
  if(f.k===m.restAt)for(let y=th-4;y<th;y++)for(let x=0;x<tw;x++){const o=((oy+y)*W+ox+x)*3;px[o]=230;px[o+1]=60;px[o+2]=60;}
 });
 writeRgbPng(path,W,H,px);
}

async function run(mode:'anchor'|'fade'|'reduced'){
 const iso=await realpath(await mkdtemp(join(process.env.TMPDIR??'/private/tmp','zw-genie-static-e2e-'))),rpc=join(iso,'rpc'),data=join(iso,'data');await mkdir(rpc);await mkdir(data);
 await writeFile(join(data,'config.toml'),`[meta]\nconfig_revision=1\n[updates]\nauto_check=false\n[ui]\ntheme="${theme}"\nfloat_card_transition="${mode==='fade'?'fade':'anchor'}"\n[ai]\ndefault_provider="local"\n[[ai.providers]]\nid="local"\nkind="openai_compat"\nendpoint="http://127.0.0.1:${port}/v1/chat/completions"\nenabled=true\n[[ai.providers.models]]\nname="motion-model"\ncontext_window=32768\ndefault=true\n`,{mode:0o600});
 process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
 const log=await open(join(out,`${theme}-${mode}-app.log`),'w');
 const env:any={...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1',ZENIT_E2E_ISOLATE_KEYBOARD:'1',ZENIT_E2E_HIDE_VIRTUAL_CURSOR:'1',ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',OPENAI_API_KEY:'',ANTHROPIC_API_KEY:''};
 if(probe)env.ZENIT_ANCHOR_FLIGHT_PROBE='1';
 if(mode==='reduced')env.ZENIT_A11Y_PREFS='reduce_motion';
 const app=spawn(binaryArg,[],{env,stdio:['ignore',log.fd,log.fd]});const ended=new Promise<void>(r=>app.once('close',()=>r()));
 const base=join(out,`${theme}-${mode}`);await mkdir(base,{recursive:true});
 const scenes:any[]=[];
 const want=(n:string)=>!onlyScenes.length||onlyScenes.includes(n);
 const clickNode=async(id:string)=>{const n=await node(id,4000);assert((await h.clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok,'click '+id);};
 const launcher=async()=>(await one('ai.launcher.anchor'))?.rect??(await one('ai.launcher'))?.rect??null;
 try{
  await h.waitForServerReady();await h.resizeWindow(1440,900);await h.sleep(300);
  await h.clickTestId('workspace.empty.local');await node('terminal.surface');await h.sleep(800);
  // Warm the panel once on the real clock (first mount, model list).
  await clickNode('ai.launcher');await h.waitFor(async()=>(await text('ai.panel.motion.phase'))==='expanded',8000);await h.sleep(500);
  await clickNode('ai.collapse');await h.waitFor(async()=>(await text('ai.panel.motion.phase'))==='collapsed',8000);await node('ai.launcher');await h.sleep(500);
  await h.mouseMove(4,450);await lock();for(let i=0;i<6;i++)await advance();
  if(want('open'))scenes.push(await scene('open',base,()=>clickNode('ai.launcher'),launcher));
  else{await unlock();await clickNode('ai.launcher');await h.sleep(800);await lock();}
  if(want('close'))scenes.push(await scene('close',base,()=>clickNode('ai.collapse'),launcher));
  await unlock();
  if((await text('ai.panel.motion.phase'))!=='expanded'){await clickNode('ai.launcher');await h.waitFor(async()=>(await text('ai.panel.motion.phase'))==='expanded',8000);}
  await h.sleep(500);
  await clickNode('toolbar.new_session');await clickNode('session.menu.local');await node('terminal.surface');
  await h.waitFor(async()=>(await text('ai.panel.motion.phase'))==='collapsed',8000);await h.sleep(400);
  let first:string|null=null,second:string|null=null;
  for(let id=1;id<=24;id++)if((await h.query('tabs.cell.'+id)).some(shown)){if(!first)first='tabs.cell.'+id;second='tabs.cell.'+id;}
  const tabRect=async(id:string)=>(await one(id))?.rect??null;
  await h.mouseMove(4,450);await lock();for(let i=0;i<6;i++)await advance();
  scenes.push(await scene('tab-back',base,()=>clickNode(first!),()=>tabRect(first!)));
  scenes.push(await scene('tab-away',base,()=>clickNode(second!),()=>tabRect(first!)));
  await unlock();await clickNode(first!);await h.waitFor(async()=>(await text('ai.panel.motion.phase'))==='expanded',8000);await h.sleep(600);
  if(want('dock')||want('float')){
   const panelRect=(await node('ai.panel')).rect as R;
   await h.mouseMove(4,450);await lock();for(let i=0;i<6;i++)await advance();
   scenes.push(await scene('dock',base,()=>clickNode('ai.dock_to_split'),async()=>panelRect));
   await unlock();await node('ai.pane');await h.sleep(600);
   const paneRect=(await node('ai.pane')).rect as R;
   await h.mouseMove(4,450);await lock();for(let i=0;i<6;i++)await advance();
   scenes.push(await scene('float',base,()=>clickNode('ai.pane.float'),async()=>paneRect));
   await unlock();
  }
 }finally{await unlock().catch(()=>{});if(app.exitCode===null&&app.signalCode===null)app.kill('SIGTERM');await ended;await log.close().catch(()=>{});await rm(iso,{recursive:true,force:true}).catch(()=>{});}
 const p0=decodePng(scenes[0].frames[0].png);const img={w:p0.width,h:p0.height};
 const expectProbe=probe&&scenes[0].frames[0].flight!==null;
 const measures=scenes.map(s=>{const m=measure(s,img);sheet(join(base,`sheet-${s.name}.png`),s,m);return {...m,failures:failures(m,expectProbe)};});
 await writeFile(join(out,`frames-${theme}-${mode}.json`),JSON.stringify({theme,mode,probe,scenes:scenes.map(s=>({...s,frames:s.frames.map((f:any)=>({...f}))}))},null,1));
 await writeFile(join(out,`measure-${theme}-${mode}.json`),JSON.stringify(measures,null,1));
 return measures.map(m=>({scene:m.scene,restAt:m.restAt,flight:m.flight,landing:m.landing.max,failures:m.failures}));
}

if(remeasure){
 const {readFile}=await import('node:fs/promises');const d=JSON.parse(await readFile(remeasure,'utf8'));
 const p0=decodePng(d.scenes[0].frames[0].png);const img={w:p0.width,h:p0.height};const base=join(out,`${d.theme}-${d.mode}`);
 const ms=d.scenes.map((s:any)=>{const m=measure(s,img);sheet(join(base,`sheet-${s.name}.png`),s,m);return {...m,failures:failures(m,d.probe&&d.scenes[0].frames[0].flight!==null)};});
 await writeFile(join(out,`measure-${d.theme}-${d.mode}.json`),JSON.stringify(ms,null,1));
 console.log(JSON.stringify(ms.map((m:any)=>({scene:m.scene,landing:m.landing.max,flight:m.flight,failures:m.failures}))));
 server.close();process.exit(0);
}
let status='passed';const summary:any={};
try{for(const m of modesArg.split(',') as any[]){summary[m]=await run(m);if(summary[m].some((s:any)=>s.failures.length))status='failed';}}
catch(e){status='failed';summary.error=String((e as any)?.stack??e);}
finally{server.closeAllConnections();await new Promise<void>(r=>server.close(()=>r()));await writeFile(join(out,`summary-${theme}.json`),JSON.stringify({status,summary},null,2));}
if(status!=='passed')process.exitCode=1;
console.log(status+': '+out+' '+JSON.stringify(summary));
