/**
 * 浮动卡片出入场的逐帧取证（open-motion）：真实窗口、test-mode、隔离数据目录，锁定动画时钟逐帧截图（见 ai_float_motion_frames_lib.ts）。
 * 场景：open（点 launcher 展开，点击后指针移开）、close（收回 launcher）、reopen（再次展开，指针留在点击处）、
 * tab-back（切回所属 tab，从 tab 展开）、tab-away（切走，收回所属 tab）；每段采到落地后 `--tail` 帧（默认 36 帧 ≈ 600ms）。
 * 输出 frames-<theme>-<mode>.json 与 measure-<theme>-<mode>.json（判定量），截图在 <out>/<theme>-<mode>/<scene>/f_<k>.png。
 * 本脚本只取证不断言；断言在 ai_float_motion_native.ts。
 *
 * Usage: node e2e/ai_float_motion_frames.ts <zerowork binary (test-mode)> <out dir> [light|dark] [anchor,fade,reduced] [--tail N]
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

const args=process.argv.slice(2);
const flag=(name:string)=>{const i=args.indexOf(name);if(i<0)return null;const v=args[i+1];args.splice(i,2);return v;};
const tail=Number(flag('--tail')??36);
const [binaryArg,outArg,theme='light',modesArg='anchor,fade,reduced']=args;
if(!binaryArg||!outArg)throw new Error('usage: ai_float_motion_frames.ts <binary> <out> [light|dark] [modes] [--tail N]');
const out=resolve(outArg);await mkdir(out,{recursive:true});
const server=createServer((req,res)=>{res.writeHead(200,{'Content-Type':'application/json'});res.end(JSON.stringify({data:[{id:'motion-model',object:'model',context_length:32768,reasoning:false,vision:false}]}));});
await new Promise<void>(r=>server.listen(0,'127.0.0.1',r));const port=(server.address() as any).port;
const node=(id:string,ms=12000)=>h.waitFor(async()=>(await h.query(id)).find(shown)??null,ms);
const k=frameKit(h,shown);

async function run(mode:'anchor'|'fade'|'reduced'){
 const iso=await realpath(await mkdtemp('/private/tmp/zw-open-motion-e2e-')),rpc=join(iso,'rpc'),data=join(iso,'data');await mkdir(rpc);await mkdir(data);
 const transition=mode==='fade'?'fade':'anchor';
 await writeFile(join(data,'config.toml'),`[meta]\nconfig_revision=1\n[updates]\nauto_check=false\n[ui]\ntheme="${theme}"\nfloat_card_transition="${transition}"\n[ai]\ndefault_provider="local"\n[[ai.providers]]\nid="local"\nkind="openai_compat"\nendpoint="http://127.0.0.1:${port}/v1/chat/completions"\nenabled=true\n[[ai.providers.models]]\nname="motion-model"\ncontext_window=32768\ndefault=true\n`,{mode:0o600});
 process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
 const log=await open(join(out,`${theme}-${mode}-app.log`),'w');
 const env:any={...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1',ZENIT_E2E_ISOLATE_KEYBOARD:'1',ZENIT_E2E_HIDE_VIRTUAL_CURSOR:'1',ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',OPENAI_API_KEY:'',ANTHROPIC_API_KEY:''};
 if(mode==='reduced')env.ZENIT_A11Y_PREFS='reduce_motion';
 const app=spawn(binaryArg,[],{env,stdio:['ignore',log.fd,log.fd]});const ended=new Promise<void>(r=>app.once('close',()=>r()));
 const base=join(out,`${theme}-${mode}`);await mkdir(base,{recursive:true});
 const scenes:any[]=[];
 try{
  await h.waitForServerReady();await h.resizeWindow(1440,900);await h.sleep(300);
  await h.clickTestId('workspace.empty.local');await node('terminal.surface');await h.sleep(800);
  // Warm the panel once (first mount, model list) on the real clock, so the measured runs are steady-state opens.
  const l0=await node('ai.launcher');await h.clickAt(l0.rect.x+l0.rect.w/2,l0.rect.y+l0.rect.h/2);
  await h.waitFor(async()=>(await k.text('ai.panel.motion.phase'))==='expanded',8000);await h.sleep(500);
  const c0=await node('ai.collapse');await h.clickAt(c0.rect.x+c0.rect.w/2,c0.rect.y+c0.rect.h/2);
  await h.waitFor(async()=>(await k.text('ai.panel.motion.phase'))==='collapsed',8000);await node('ai.launcher');await h.sleep(500);
  await h.mouseMove(4,450);
  await k.lock();await k.settle(6);
  const clickNode=async(id:string)=>{const n=await node(id,4000);assert((await h.clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok,'click '+id);};
  scenes.push(await k.scene('open',base,()=>clickNode('ai.launcher'),{tail}));
  scenes.push(await k.scene('close',base,()=>clickNode('ai.collapse'),{tail}));
  scenes.push(await k.scene('reopen',base,()=>clickNode('ai.launcher'),{tail,park:false}));
  await k.unlock();
  await clickNode('toolbar.new_session');await clickNode('session.menu.local');await node('terminal.surface');
  await h.waitFor(async()=>(await k.text('ai.panel.motion.phase'))==='collapsed',8000);await h.sleep(400);
  let first:string|null=null,second:string|null=null;
  for(let id=1;id<=24;id++)if((await h.query('tabs.cell.'+id)).some(shown)){if(!first)first='tabs.cell.'+id;second='tabs.cell.'+id;}
  await h.mouseMove(4,450);await k.lock();await k.settle(6);
  scenes.push(await k.scene('tab-back',base,()=>clickNode(first!),{tail}));
  scenes.push(await k.scene('tab-away',base,()=>clickNode(second!),{tail}));
  await k.unlock();
 }finally{await k.unlock().catch(()=>{});if(app.exitCode===null&&app.signalCode===null)app.kill('SIGTERM');await ended;await log.close().catch(()=>{});await rm(iso,{recursive:true,force:true}).catch(()=>{});}
 await writeFile(join(out,`frames-${theme}-${mode}.json`),JSON.stringify({theme,mode,step_ms:1000/60,scenes},null,1));
 const measures=scenes.map(s=>{const m=measureScene(s);return {...m,failures:sceneFailures(m,s.park)};});
 await writeFile(join(out,`measure-${theme}-${mode}.json`),JSON.stringify(measures,null,1));
 return measures.map(m=>({scene:m.scene,restAt:m.restAt,failures:m.failures}));
}

let status='passed';const summary:any={};
try{for(const m of modesArg.split(',') as any[])summary[m]=await run(m);}
catch(e){status='failed';summary.error=String((e as any)?.stack??e);process.exitCode=1;}
finally{server.closeAllConnections();await new Promise<void>(r=>server.close(()=>r()));await writeFile(join(out,`frames-${theme}-summary.json`),JSON.stringify({status,summary},null,2));}
console.log(status+': '+out+' '+JSON.stringify(summary));
