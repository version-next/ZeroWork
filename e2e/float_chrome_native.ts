/** Floating cards' unified window chrome (float-chrome, user feedback "card 在 floating window 的时候没有用统一的
 * window 样式"; Pencil「ZW · 浮动卡片统一窗口外观 2026-11-14」). The AI chat panel and the session history card
 * float side by side; both must wear the same frame (native floating Card: radius 12, border, shadow lg), the same
 * `*.float.drag` grip with the native Grabber (14 high, 36 × 4 capsule) and the same 30-high header with
 * 24 × 24 native ghost icon buttons. Checked from the node tree (geometry, component) and by pixel sampling the
 * screenshot (corner radius profile, Grabber capsule width, shadow falloff below the card). Then the AI panel at
 * its 420 (#52 default) and 320 (narrow window) widths: every header button inside, the owner subtitle gives way.
 *
 * Usage: node e2e/float_chrome_native.ts <zerowork binary (test-mode)> <out dir> [light|dark]
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {join,resolve} from 'node:path';
import {writeFile,mkdir,mkdtemp,realpath,open,rm} from 'node:fs/promises';
import {spawn} from 'node:child_process';
import * as h from '../vendor/zenit/e2e/client.ts';
import {decodePng} from '../vendor/zenit/e2e/png.ts';
import {shown} from './settings_nav.ts';

const [binaryArg,outArg,theme='light']=process.argv.slice(2);
if(!binaryArg||!outArg)throw new Error('usage: float_chrome_native.ts <binary> <out> [light|dark]');
const out=resolve(outArg);await mkdir(out,{recursive:true});
const report:any={status:'running',theme,checks:[] as string[],shots:[] as string[],samples:{} as any,limits:['No AI provider is configured (the empty welcome state is enough: only the chrome is checked).']};
const iso=await realpath(await mkdtemp('/private/tmp/zw-float-chrome-e2e-')),rpc=join(iso,'rpc'),data=join(iso,'data');
await mkdir(rpc);await mkdir(join(data,'logs/history'),{recursive:true});
await writeFile(join(data,'config.toml'),`[meta]\nconfig_revision=1\n[updates]\nauto_check=false\n[ui]\ntheme="${theme}"\n[ui.materials]\nblur_px=0\n`);
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const log=await open(join(out,`${theme}-app.log`),'w');
const app=spawn(binaryArg,[],{env:{...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1',ZENIT_E2E_ISOLATE_KEYBOARD:'1',ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',OPENAI_API_KEY:'',ANTHROPIC_API_KEY:''},stdio:['ignore',log.fd,log.fd]});
const ended=new Promise<void>(r=>app.once('close',()=>r()));
await h.waitForServerReady();

type R={x:number,y:number,w:number,h:number};
const node=(id:string,ms=12000)=>h.waitFor(async()=>(await h.query(id)).find(shown)??null,ms);
const click=async(id:string)=>{const n=await node(id);if(!(await h.clickTestId(id)).ok)assert((await h.clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok,'click '+id);};
const shot=async(name:string)=>{await h.mouseMove(4,500);await h.sleep(700);const path=join(out,`${theme}-${name}.png`);assert((await h.screenshot(path)).ok,name);report.shots.push(path);return path;};
const near=(a:number,b:number,label:string,tol=1)=>assert(Math.abs(a-b)<=tol,`${label}: ${a} vs ${b}`);
const drag=async(x0:number,y0:number,x1:number,y1:number,steps=12)=>{await h.mouseMove(x0,y0);await h.mouseDown(x0,y0);for(let i=1;i<=steps;i++){await h.mouseMove(x0+(x1-x0)*i/steps,y0+(y1-y0)*i/steps);await h.sleep(16);}await h.sleep(150);await h.mouseUp(x1,y1);await h.sleep(300);};  // pause before the release: a placement, not a fling (drag-inertia)
const settled=async(id:string):Promise<R>=>{let last:R|null=null;return h.waitFor(async()=>{const r=(await node(id)).rect;const stable=last&&Math.abs(last.x-r.x)<0.5&&Math.abs(last.y-r.y)<0.5&&Math.abs(last.w-r.w)<0.5&&Math.abs(last.h-r.h)<0.5;last=r;return stable?r:null;},6000,80);};
const moveBy=async(grip:string,dx:number,dy:number)=>{const g=(await node(grip)).rect;await drag(g.x+g.w/2,g.y+g.h/2,g.x+g.w/2+dx,g.y+g.h/2+dy);};
const component=(n:any):string[]=>[n.component??'',...(n.children??[]).flatMap(component)];

// One card's chrome, read from the tree.
const CARDS={ai:{root:'ai.panel',grip:'ai.float.drag',header:'ai.header',close:'ai.close',actions:['ai.children','ai.sessions','ai.session.new','ai.collapse','ai.maximize','ai.close']},history:{root:'history.panel',grip:'history.float.drag',header:'history.header',close:'history.close',actions:['history.open_as_tab','history.maximize','history.close']}} as const;
async function chrome(kind:keyof typeof CARDS){
 const c=CARDS[kind];const root=await node(c.root),grip=await node(c.grip),header=await node(c.header);
 const buttons=[];for(const id of c.actions)buttons.push((await node(id)).rect);
 return {root:root.rect as R,grip:grip.rect as R,header:header.rect as R,buttons,components:component(root)};
}

// Pixels (the screenshot is in device pixels; `scale` = device / logical).
type Img={w:number,h:number,ch:number,px:Uint8Array,scale:number};
const load=(path:string,logicalWidth:number):Img=>{const p=decodePng(path);return {w:p.width,h:p.height,ch:p.channels,px:p.pixels,scale:p.width/logicalWidth};};
const at=(img:Img,x:number,y:number)=>{const X=Math.round(x*img.scale),Y=Math.round(y*img.scale);const i=(Y*img.w+X)*img.ch;return [img.px[i],img.px[i+1],img.px[i+2]];};
const luma=(c:number[])=>0.2126*c[0]+0.7152*c[1]+0.0722*c[2];
const dist=(a:number[],b:number[])=>Math.max(Math.abs(a[0]-b[0]),Math.abs(a[1]-b[1]),Math.abs(a[2]-b[2]));
/** Where the 1 px border crosses the corner diagonal (logical, 0.5 pt steps): r·(1 − 1/√2) for radius r,
 * 0 for a square corner. Both cards sit over the same backdrop (the terminal). */
function cornerDepth(img:Img,r:R,fill:number[]){let best=0,peak=-1;for(let d=0;d<=8;d+=0.5){const v=dist(at(img,r.x+d,r.y+d),fill);if(v>peak+1){peak=v;best=d;}}return best;}
/** Width of the Grabber capsule (logical) on the grip's middle row. */
function grabberWidth(img:Img,g:R,fill:number[]){const y=g.y+g.h/2;let n=0;for(let x=g.x;x<g.x+g.w;x+=0.5)if(dist(at(img,x,y),fill)>40)n++;return n/2;}
/** Shadow under the card: luma drop vs. the backdrop 140 pt below, at 4 / 16 / 32 pt (relative). */
function shadowProfile(img:Img,r:R){const x=r.x+r.w/2;const ref=luma(at(img,x,r.y+r.h+140));return [4,16,32].map(d=>+((ref-luma(at(img,x,r.y+r.h+d)))/Math.max(1,ref)).toFixed(3));}

try{
 await h.resizeWindow(1440,1000);await h.sleep(400);
 await click(((await h.query('workspace.empty.local')).some(shown))?'workspace.empty.local':'toolbar.new_session');
 if(!(await h.query('terminal.surface')).some(shown)&&(await h.query('session.menu.local')).some(shown))await click('session.menu.local');
 await node('terminal.surface');await h.sleep(600);
 // AI panel (#52 default 420 wide) to the top right; history card to the top left of the floating region.
 await click('ai.launcher');await settled('ai.panel');
 await moveBy('ai.float.drag',3000,-3000);
 await click('toolbar.history');await settled('history.panel');
 await moveBy('history.float.drag',0,-3000);
 // Narrow the history card from its left edge so both cards sit over the terminal, side by side.
 {const w=(await node('history.float.resize.w')).rect;await drag(w.x+w.w/2,w.y+w.h/2,w.x+w.w/2+300,w.y+w.h/2);}
 const pane=(await node('terminal.surface')).rect as R;
 // Tops 140 pt below the title bar: the corners sit over plain terminal background, not the pane header.
 {const r=await settled('history.panel');await moveBy('history.float.drag',pane.x+16-r.x,140);}
 await moveBy('ai.float.drag',0,140);
 const ai=await chrome('ai'),hist=await chrome('history');
 assert(hist.root.x>=pane.x&&ai.root.x+ai.root.w<=pane.x+pane.w+1,`both cards over the terminal: ${JSON.stringify(pane)} ${JSON.stringify(hist.root)} ${JSON.stringify(ai.root)}`);
 report.samples.tree={ai,history:hist};
 assert(ai.root.x>=hist.root.x+hist.root.w,`cards overlap: ${JSON.stringify(ai.root)} / ${JSON.stringify(hist.root)}`);
 // 1. Tree: same frame component, grip and header geometry, same button size.
 for(const [name,c] of [['ai',ai],['history',hist]] as const){
  assert(c.components.includes('Card'),`${name}: chrome frame is the native Card (${c.components.slice(0,4)})`);
  near(c.grip.h,14,name+' grip height');near(c.grip.y,c.root.y,name+' grip at the top',0.6);near(c.grip.w,c.root.w,name+' grip spans the card',1.5);
  near(c.header.h,30,name+' header height');near(c.header.y-c.root.y,14,name+' header under the grip',0.6);
  for(const b of c.buttons){near(b.w,hist.buttons[0].w,name+' button width = native ghost sm icon button');near(b.h,hist.buttons[0].h,name+' button height');assert(b.x+b.w<=c.root.x+c.root.w+0.5&&b.x>=c.root.x,name+' button inside');near(b.y+b.h/2,c.header.y+c.header.h/2,name+' button centred in the header',0.6);}
  near(c.root.x+c.root.w-(c.buttons.at(-1)!.x+c.buttons.at(-1)!.w),c.header.x+c.header.w-(c.buttons.at(-1)!.x+c.buttons.at(-1)!.w),name+' close at the header end (padding 4)',0.6);
 }
 near(ai.root.x+ai.root.w-(ai.buttons.at(-1)!.x+ai.buttons.at(-1)!.w),hist.root.x+hist.root.w-(hist.buttons.at(-1)!.x+hist.buttons.at(-1)!.w),'close button inset from the right edge is the same',0.6);
 report.checks.push(`Tree: both floating cards are a native Card frame with a 14-high grip on top, a 30-high header under it and equal native ghost sm icon buttons (${hist.buttons[0].w} × ${hist.buttons[0].h}) ending 4 pt from the right edge`);
 // 2. Pixels: corner radius profile, Grabber capsule, shadow falloff, fill.
 const both=await shot('both-floating');const img=load(both,1440);
 const fill=(r:R)=>at(img,r.x+r.w/2,r.y+r.h-20);
 const sample:any={};
 for(const [name,c] of [['ai',ai],['history',hist]] as const){
  const f=at(img,c.root.x+c.root.w-40,c.grip.y+c.grip.h/2);
  sample[name]={fill:f,corner_tl:cornerDepth(img,c.root,f),grabber:grabberWidth(img,c.grip,f),shadow:shadowProfile(img,c.root)};
 }
 report.samples.pixels=sample;
 assert(dist(sample.ai.fill,sample.history.fill)<=2,`same frame fill ${sample.ai.fill} / ${sample.history.fill}`);
 near(sample.ai.corner_tl,sample.history.corner_tl,'same corner radius profile',0.5);
 assert(sample.ai.corner_tl>=2&&sample.ai.corner_tl<=5,`corner depth ${sample.ai.corner_tl} fits radius 12`);
 near(sample.ai.grabber,36,'AI Grabber 36 wide',2);near(sample.history.grabber,36,'history Grabber 36 wide',2);
 for(let i=0;i<3;i++)near(sample.ai.shadow[i],sample.history.shadow[i],`same shadow falloff at ${[4,16,32][i]} pt`,0.02);
 assert(sample.ai.shadow[0]>0.005,`a shadow is drawn under the card (${sample.ai.shadow})`);
 report.checks.push(`Pixels: same fill, corner radius profile (${sample.ai.corner_tl} pt diagonal), Grabber capsule (${sample.ai.grabber} / ${sample.history.grabber} pt) and shadow falloff (${sample.ai.shadow} / ${sample.history.shadow})`);
 // Header strips for design_diff (top 44 pt of each card).
 report.samples.strips={ai:ai.root,history:hist.root};
 // 3. AI at 420 (default) and at 320 (narrow window): buttons inside, the owner subtitle gives way.
 await click('history.close');await h.sleep(500);
 await click('ai.collapse');await h.sleep(800);await click('ai.launcher');await settled('ai.panel');
 const at420=await chrome('ai');near(at420.root.w,420,'#52 default width 420');
 const owner420=(await h.query('ai.owner')).some(shown);assert(owner420,'420: owner subtitle shown');
 await shot('ai-420');report.samples.ai420=at420.root;
 // The minimum width (320, #52's narrow default): resize from the west edge.
 {const w=(await node('ai.float.resize.w')).rect;await drag(w.x+w.w/2,w.y+w.h/2,w.x+w.w/2+200,w.y+w.h/2);}
 await settled('ai.panel');
 const at320=await chrome('ai');near(at320.root.w,320,'minimum width 320');
 for(const b of at320.buttons)assert(b.x>=at320.root.x&&b.x+b.w<=at320.root.x+at320.root.w-4+0.5,`320: header buttons stay inside (${JSON.stringify(b)} in ${JSON.stringify(at320.root)}; header ${JSON.stringify(((function f(n:any):any[]{return n?[n,...(n.children??[]).flatMap(f)]:[]})((await h.query('ai.header'))[0])).filter((n:any)=>n.rect).slice(0,14).map((n:any)=>[n.tag,n.text??'',n.hidden??'',Math.round(n.rect.x),Math.round(n.rect.w)]))})`);
 assert(!(await h.query('ai.owner')).some(shown),'320: the owner subtitle gives way (hidden) before any button');
 await shot('ai-320');report.samples.ai320=at320.root;
 report.checks.push('AI panel at 420 shows the owner subtitle; at 320 all six header buttons stay inside and the subtitle is hidden (bugfix-1 rule, now the chrome\'s)');
 report.status='passed';
}catch(error){report.status='failed';report.error=String(error?.stack??error);process.exitCode=1;}
finally{
 await writeFile(join(out,`report-${theme}.json`),JSON.stringify(report,null,1));
 if(app.exitCode===null&&app.signalCode===null)app.kill('SIGTERM');await ended;
 await log.close().catch(()=>{});await rm(iso,{recursive:true,force:true}).catch(()=>{});
}
console.log(report.status, out);
