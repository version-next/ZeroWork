/**
 * 浮动卡片出入场的逐帧采样与判定（open-motion），供 ai_float_motion_native.ts（断言）与 ai_float_motion_frames.ts（取证）共用。
 *
 * 采样：锁定 zenit Harness 动画时钟（`/clock` locked + `/clock/advance`，每次推进一帧 1000/60 ms，等应用花完再采），
 * 每帧截图并记下 `ai.panel.motion`（阶段 / 快照矩形 / 锚点）、面板节点 `ai.panel` 的真实矩形、launcher、输入框光标矩形与焦点。
 *
 * 判定（checkScene），区域 = 面板静止矩形外扩 30pt（含阴影），光标矩形（本帧与上一帧，外扩 3pt）不计：
 *   - 落地前后矩形连续：最后一帧飞行矩形与落地后真实矩形、以及落地后各帧真实矩形之间差 < 0.5pt（展开）；
 *   - 落地帧不闪：落地帧与上一帧的像素差最大通道值 ≤ LANDING_MAX（快照与真实节点的光栅化差，实测 ≤ 4/255）；
 *   - 落地后 ≥ 500ms 静止：之后每对相邻帧像素差为 0；
 *   - 无闪烁帧：不存在“前后两帧彼此接近、中间这帧与两边都明显不同”的帧（A-B-A：两侧之间一致像素比例
 *     比中间帧与任一侧高出 5% 以上；两侧都正好是卡片自身底色的像素不计——同色背景上移动卡片的内部与背景无法区分，
 *     其边缘会被误判为 A-B-A，float-chrome 的原生 floating Card 亮色底 = 终端白底），覆盖点击帧到落地后一帧；
 *     且以 launcher 为锚点的展开 / 收回每一帧里，飞行快照（`ai.panel.motion.opacity`）与 launcher（`ai.launcher.anchor`
 *     的不透明度）之和 ≥ 0.6（没有“图标已经不见、面板还没出来”的空帧；减少动态效果下两者原地交叉淡变，和约为 1）。
 */
import {join} from 'node:path';
import {mkdir} from 'node:fs/promises';
import {decodePng,type DecodedPng} from '../vendor/zenit/e2e/png.ts';

export type R={x:number,y:number,w:number,h:number};
export const STEP=1000/60;
export const LANDING_MAX=8;
const PAD=30;

export function frameKit(h:any,shown:(n:any)=>boolean){
 const one=async(id:string)=>(await h.query(id))[0]??null;
 const text=async(id:string)=>((await h.query(id))[0]?.text??'');
 const lock=async()=>{const r:any=await h.request('POST','/clock',{step_ms:STEP,locked:true});if(r?.error)throw new Error('clock: '+JSON.stringify(r));};
 const unlock=async()=>{await h.request('POST','/clock',{step_ms:0});};
 // Grant one frame of clock and wait until the app has spent it (the frame rendered).
 const advance=async(ms=STEP)=>{const a:any=await h.request('POST','/clock/advance',{ms});if(a?.error)throw new Error('advance: '+JSON.stringify(a));
  for(let i=0;i<2000;i++){const s:any=await h.request('GET','/stats');if(!(s.clock_budget_ms>0))break;await h.sleep(4);}};
 const settle=async(n:number)=>{for(let i=0;i<n;i++)await advance();};
 async function sample(dir:string|null,k:number){
  const f=await one('ai.panel.motion');const panel=await one('ai.panel');const launcher=await one('ai.launcher.anchor');
  const focus=await h.focused().catch(()=>({} as any));
  let caret:R|null=null;try{const st=await h.inputState('ai.prompt');caret=(st as any).cursor_rect??null;}catch{}
  const rec:any={k,phase:await text('ai.panel.motion.phase'),anchor:await text('ai.panel.motion.anchor'),motion:f?.rect??null,opacity:Number(await text('ai.panel.motion.opacity')),
   panel:panel&&shown(panel)?{rect:panel.rect}:null,launcher:launcher?{rect:launcher.rect,visible:shown(launcher),opacity:launcher.effective_opacity??launcher.opacity??1}:null,caret,focus:focus?.test_id??null};
  if(dir){const png=join(dir,`f_${String(k).padStart(3,'0')}.png`);const s=await h.screenshot(png);if(s.ok)rec.png=png;}
  return rec;
 }
 // One scene: act (one UI turn on the locked clock), then step frame by frame until the run rests plus `tail` frames.
 // `park`: move the pointer off the card right after the click (pure motion); otherwise it stays where it clicked.
 async function scene(name:string,base:string,act:()=>Promise<void>,{park=true,tail=36}:{park?:boolean,tail?:number}={}){
  const dir=join(base,name);await mkdir(dir,{recursive:true});
  const frames:any[]=[await sample(dir,0)];
  await act();if(park)await h.mouseMove(4,450);
  let restAt=-1,moved=false;
  for(let k=1;k<=240;k++){
   await advance();const rec=await sample(dir,k);frames.push(rec);
   const animating=rec.phase==='collapsing'||rec.phase==='expanding';
   if(animating)moved=true;
   if(moved&&!animating&&restAt<0)restAt=k;
   if(restAt<0&&!moved&&k>=20)restAt=k;
   if(restAt>=0&&k-restAt>=tail)break;
  }
  return {name,restAt,moved,park,frames};
 }
 return {one,text,lock,unlock,advance,settle,sample,scene};
}

const maxd=(a:R,b:R)=>Math.max(Math.abs(a.x-b.x),Math.abs(a.y-b.y),Math.abs(a.w-b.w),Math.abs(a.h-b.h));

/** Measurements of one scene (see the header). Pure: reads the PNGs the scene wrote. */
export function measureScene(s:any,scale=2){
 const fr=s.frames,R=s.restAt;const expand=fr[R]?.phase==='expanded';
 const home:R=[...fr].reverse().find((f:any)=>f.panel)?.panel.rect??fr.find((f:any)=>f.motion)?.motion;
 const x0=Math.max(0,Math.floor((home.x-PAD)*scale)),y0=Math.max(0,Math.floor((home.y-PAD)*scale));
 // Keep only the region of each frame (RGB), one decode at a time.
 let x1=0,y1=0,RW=0;
 const imgs:Uint8Array[]=fr.map((f:any)=>{const p:DecodedPng=decodePng(f.png);
  if(!RW){x1=Math.min(p.width,Math.ceil((home.x+home.w+PAD)*scale));y1=Math.min(p.height,Math.ceil((home.y+home.h+PAD)*scale));RW=x1-x0;}
  const out=new Uint8Array(RW*(y1-y0)*3);
  for(let y=y0;y<y1;y++)for(let x=x0;x<x1;x++){const i=(y*p.width+x)*p.channels,o=((y-y0)*RW+(x-x0))*3;out[o]=p.pixels[i];out[o+1]=p.pixels[i+1];out[o+2]=p.pixels[i+2];}
  return out;});
 const masks=fr.map((f:any)=>{const c=f.caret;return c&&c.w>0?{x0:(c.x-3)*scale,x1:(c.x+c.w+3)*scale,y0:(c.y-3)*scale,y1:(c.y+c.h+3)*scale}:null;});
 const masked=(i:number,x:number,y:number)=>{for(const j of [i,i-1]){const c=j>=0?masks[j]:null;if(c&&x>=c.x0&&x<c.x1&&y>=c.y0&&y<c.y1)return true;}return false;};
 const diff=(i:number,j:number,tol=0)=>{let n=0,mx=0,same=0,total=0;const a=imgs[i],b=imgs[j];
  for(let y=y0;y<y1;y++)for(let x=x0;x<x1;x++){if(masked(i,x,y)||masked(j,x,y))continue;const o=((y-y0)*RW+(x-x0))*3;
   const d=Math.max(Math.abs(a[o]-b[o]),Math.abs(a[o+1]-b[o+1]),Math.abs(a[o+2]-b[o+2]));total++;if(d>0){n++;if(d>mx)mx=d;}if(d<=tol)same++;}
  return {n,max:mx,same:total?same/total:1};};
 const landing=diff(R,R-1);
 const tail:any[]=[];for(let i=R+1;i<fr.length;i++){const d=diff(i,i-1);if(d.n)tail.push({k:fr[i].k,...d});}
 const tailMs=(fr.length-1-R)*STEP;
 let rectJump=0;
 if(expand){rectJump=maxd(fr[R-1].motion,fr[R].panel.rect);for(let i=R;i<fr.length;i++)if(fr[i].panel)rectJump=Math.max(rectJump,maxd(fr[i].panel.rect,fr[R].panel.rect));}
 // Flash: frame k unlike both neighbours while they agree with each other (A-B-A).
 // Pixels where both neighbours show exactly the card's own surface colour say nothing: over a backdrop of the same
 // colour (the light theme's bg-primary card over the white terminal) the moving card's interior and the backdrop are
 // indistinguishable, so its moving edge would read as A-B-A. The surface colour is read off the resting card's grip
 // strip (float-chrome: native floating Card, bg-primary).
 const restIdx=expand?fr.length-1:0;const fx=Math.round((home.x+home.w-40)*scale)-x0,fy=Math.round((home.y+7)*scale)-y0;
 const fo=(fy*RW+fx)*3;const surface=[imgs[restIdx][fo],imgs[restIdx][fo+1],imgs[restIdx][fo+2]];
 const isSurface=(img:Uint8Array,o:number)=>Math.abs(img[o]-surface[0])<=2&&Math.abs(img[o+1]-surface[1])<=2&&Math.abs(img[o+2]-surface[2])<=2;
 const aba=(i:number)=>{const a=imgs[i-1],b=imgs[i],c=imgs[i+1];let total=0,around=0,prev=0,next=0;
  for(let y=y0;y<y1;y++)for(let x=x0;x<x1;x++){if(masked(i,x,y)||masked(i+1,x,y))continue;const o=((y-y0)*RW+(x-x0))*3;
   if(isSurface(a,o)&&isSurface(c,o))continue;total++;
   const d=(p:Uint8Array,q:Uint8Array)=>Math.max(Math.abs(p[o]-q[o]),Math.abs(p[o+1]-q[o+1]),Math.abs(p[o+2]-q[o+2]))<=2;
   if(d(a,c))around++;if(d(b,a))prev++;if(d(b,c))next++;}
  return total?{around:around/total,mid:Math.min(prev,next)/total}:{around:1,mid:1};};
 const drops:any[]=[];for(let i=1;i<=Math.min(R+1,fr.length-2);i++){const {around,mid}=aba(i);if(around-mid>0.05)drops.push({k:fr[i].k,spike:+(around-mid).toFixed(3)});}
 // Launcher runs: in every frame the flying panel and the launcher together are well visible (no empty frames).
 const gaps:number[]=[];
 if(fr[1]?.anchor==='launcher')for(let i=1;i<=R;i++){const f=fr[i];const lo=f.launcher?.visible?f.launcher.opacity:0;if(f.opacity+lo<0.6)gaps.push(f.k);}
 return {scene:s.name,restAt:R,dir:expand?'expand':'collapse',landing,rectJump,tailMs,tail,drops,gaps};
}

/** Assertion failures of a measured scene (empty = passes). `still`: require a still picture after landing. */
export function sceneFailures(m:any,still=true):string[]{
 const out:string[]=[];
 if(m.dir==='expand'&&m.rectJump>=0.5)out.push(`${m.scene}: panel rect moves ${m.rectJump.toFixed(2)}pt around landing`);
 if(m.landing.max>LANDING_MAX)out.push(`${m.scene}: landing frame flashes (max channel delta ${m.landing.max}, ${m.landing.n} px)`);
 if(m.tailMs<500)out.push(`${m.scene}: only ${m.tailMs.toFixed(0)}ms sampled after landing`);
 if(still&&m.tail.length)out.push(`${m.scene}: redraw after landing at frames ${m.tail.map((t:any)=>`${t.k}(${t.n}px,max ${t.max})`).join(' ')}`);
 if(m.drops.length)out.push(`${m.scene}: flash frames (unlike both neighbours) at ${JSON.stringify(m.drops)}`);
 if(m.gaps.length)out.push(`${m.scene}: empty frames (panel + launcher opacity < 0.6) at ${m.gaps.join(',')}`);
 return out;
}
