/**
 * Real-window render smoke: the main window and the Settings window must actually paint their
 * content, not just hold it in the node tree. Guards the blank-window regression (43c46538: the
 * main window's material / input policies turned the native notification stack's transparent
 * full-window container into an opaque overlay surface — every pixel one colour, no clicks).
 *
 * Per theme: isolated HOME / CFFIXED_USER_HOME / TMPDIR / ZEROWORK_DATA_DIR (0700), updates off.
 *   1. Main window: sidebar, empty workspace and toolbar are queryable and visible; screenshot is
 *      not a flat colour (luminance variance and distinct colours above a floor).
 *   2. Clicking “本地终端” works (the window takes clicks) and shows a tab and a terminal.
 *   3. Clicking Settings opens the Settings window with its panel and navigation; its screenshot is
 *      not a flat colour either.
 *
 * Usage: node e2e/window_render_smoke_native.ts <zerowork binary (test-mode)> <evidence dir> [light|dark|both]
 * No network access is needed.
 */
// Refuses non-test-mode ZeroWork binaries before child_process starts them; checked up front below too.
// @ts-ignore -- plain ESM helper
import {assertTestModeBinary} from './regression/build_mode_guard.mjs';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {chmod,mkdir,mkdtemp,open,readFile,realpath,rm,writeFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {inflateSync} from 'node:zlib';
import * as h from '../vendor/zenit/e2e/client.ts';

const [binaryArg,outArg,which='both']=process.argv.slice(2);
if(!binaryArg||!outArg)throw new Error('usage: window_render_smoke_native.ts <binary> <out> [light|dark|both]');
// A formal build only reads the real home directory: refuse it before creating anything.
const binary=assertTestModeBinary(resolve(binaryArg)),out=resolve(outArg);await mkdir(out,{recursive:true});
const themes=which==='both'?['light','dark']:[which];

/** Luminance statistics of an 8-bit non-interlaced RGB(A) PNG (every 2nd pixel in each axis). */
export function pixelStats(png:Buffer){
 let o=8,w=0,ht=0,ct=0,bd=0;const idat:Buffer[]=[];
 while(o<png.length){const len=png.readUInt32BE(o),type=png.toString('ascii',o+4,o+8),d=png.subarray(o+8,o+8+len);
  if(type==='IHDR'){w=d.readUInt32BE(0);ht=d.readUInt32BE(4);bd=d[8];ct=d[9];assert.equal(d[12],0,'interlaced PNG');}
  else if(type==='IDAT')idat.push(d);else if(type==='IEND')break;o+=12+len;}
 assert(bd===8&&(ct===6||ct===2),`unsupported PNG colour type ${ct} / depth ${bd}`);
 const bpp=ct===6?4:3,stride=w*bpp,raw=inflateSync(Buffer.concat(idat)),px=Buffer.alloc(stride*ht);
 for(let y=0;y<ht;y++){const f=raw[y*(stride+1)],src=raw.subarray(y*(stride+1)+1,(y+1)*(stride+1)),row=px.subarray(y*stride,(y+1)*stride),prev=y?px.subarray((y-1)*stride,y*stride):null;
  for(let x=0;x<stride;x++){const a=x>=bpp?row[x-bpp]:0,up=prev?prev[x]:0,c=prev&&x>=bpp?prev[x-bpp]:0;let v=src[x];
   if(f===1)v+=a;else if(f===2)v+=up;else if(f===3)v+=(a+up)>>1;else if(f===4){const p=a+up-c,pa=Math.abs(p-a),pb=Math.abs(p-up),pc=Math.abs(p-c);v+=pa<=pb&&pa<=pc?a:pb<=pc?up:c;}
   row[x]=v&255;}}
 let n=0,sum=0,sq=0;const colours=new Set<number>();
 for(let y=0;y<ht;y+=2)for(let x=0;x<w;x+=2){const i=y*stride+x*bpp,l=0.2126*px[i]+0.7152*px[i+1]+0.0722*px[i+2];n++;sum+=l;sq+=l*l;if(colours.size<4096)colours.add((px[i]<<16)|(px[i+1]<<8)|px[i+2]);}
 const mean=sum/n;return {width:w,height:ht,mean,variance:Math.max(0,sq/n-mean*mean),distinct:colours.size};
}
// Healthy windows measure variance ≈ 250–600 and thousands of colours; the blank window measured
// variance 0 and a single colour. The floors leave room for theme / font differences.
const MIN_VARIANCE=20,MIN_DISTINCT=64;

const shown=(n:any)=>n&&n.visible!==false&&n.rect?.w>0&&n.rect?.h>0&&(n.effective_opacity??1)>0;
const node=async(id:string,ms=15000)=>h.waitFor(async()=>(await h.query(id)).find(shown)??null,ms);
const click=async(id:string)=>{const n:any=await node(id);assert((await h.clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok,id);};
const reports:any[]=[];

for(const theme of themes){
 const home=await realpath(await mkdtemp('/private/tmp/zw-render-smoke-'));await chmod(home,0o700);
 const tmp=join(home,'tmp'),data=join(home,'data'),rpc=join(home,'rpc'),zdot=join(home,'zdot');
 for(const d of [tmp,data,rpc,zdot])await mkdir(d,{mode:0o700});
 await writeFile(join(data,'config.toml'),`[meta]\nconfig_revision=1\n[ui]\ntheme="${theme}"\n[updates]\nauto_check=false\n`,{mode:0o600});
 process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
 const log=await open(join(out,`${theme}-app.log`),'w');
 const app=spawn(binary,[],{env:{PATH:process.env.PATH??'/usr/bin:/bin',HOME:home,CFFIXED_USER_HOME:home,TMPDIR:tmp+'/',ZDOTDIR:zdot,ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1',ZENIT_E2E_ISOLATE_KEYBOARD:'1',OPENAI_API_KEY:'',ANTHROPIC_API_KEY:''},stdio:['ignore',log.fd,log.fd]});
 const ended=new Promise(r=>app.once('close',r));
 const report:any={theme,status:'running',checks:[] as string[],shots:{} as Record<string,any>};
 const shot=async(name:string,win?:string)=>{
  await h.mouseMove(2,2).catch(()=>{});await h.sleep(300);
  const path=join(out,`${theme}-${name}.png`);assert((await h.screenshot(path,win)).ok,`screenshot ${name}`);
  const stats=pixelStats(await readFile(path));report.shots[name]={path,...stats};
  assert(stats.variance>=MIN_VARIANCE&&stats.distinct>=MIN_DISTINCT,`${theme} ${name}: flat screenshot (variance ${stats.variance.toFixed(2)}, ${stats.distinct} colours)`);
 };
 try{
  await h.waitForServerReady(30000);await h.resizeWindow(1440,900);
  for(const id of ['workspace.sidebar','sidebar.empty','workspace.empty','workspace.empty.local','toolbar.settings'])await node(id);
  const main=(await h.windows()).windows.find(w=>w.bound&&!w.closing)?.window_id;
  await h.sleep(800);await shot('main',main);
  report.checks.push('main window: sidebar, empty workspace and toolbar visible; screenshot not flat');

  await click('workspace.empty.local');
  await node('tabs.title');await node('terminal.surface');
  await h.sleep(800);await shot('main-terminal',main);
  report.checks.push('main window takes clicks: 本地终端 opens a tab and a terminal; screenshot not flat');

  await click('toolbar.settings');
  await node('settings.panel');await node('settings.navigation');await node('settings.page.title');
  const settings=await h.waitFor(async()=>(await h.windows()).windows.find(w=>!w.closing&&w.window_id!==main)?.window_id??null,10000);
  await h.sleep(800);await shot('settings',settings);
  report.checks.push('settings window opens with panel, navigation and title; screenshot not flat');
  report.status='passed';
 }catch(e){report.status='failed';report.error=String((e as any)?.stack??e);process.exitCode=1;}
 finally{app.kill('SIGTERM');await ended;await log.close();await rm(home,{recursive:true,force:true});reports.push(report);}
}
await writeFile(join(out,'report.json'),JSON.stringify({status:reports.length&&reports.every(r=>r.status==='passed')?'passed':'failed',themes:reports},null,2));
console.log(JSON.stringify(reports.map(r=>({theme:r.theme,status:r.status,checks:r.checks.length,shots:Object.fromEntries(Object.entries(r.shots).map(([k,v]:any)=>[k,{variance:+v.variance.toFixed(1),distinct:v.distinct}])),error:r.error}))));
