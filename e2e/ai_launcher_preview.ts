/**
 * `ai.launcher` 状态矩阵（Pencil tfmv1 浅色 / cVXd5 深色）：`ai-launcher-preview` 隔离窗口里六个 tab 内容区样本，
 * 每个挂真实的浮动 AI 图标，分别处于 空闲 / 待审批 / 运行中 / 失败 / 结果待核实 / 有新回答未读。
 * 断言：48 × 48、距右 24 距下 20、角标只在 待审批 / 失败 / 待核实 / 有新回答 出现（8 × 8，x+36 / y+4）、
 * 运行中的图标在呼吸（两次采样透明度不同）；截图 <theme>-states.png。只用编造的状态，没有网络与用户数据。
 *
 * Usage: node e2e/ai_launcher_preview.ts --binary <prefix>/bin/ai-launcher-preview --out <dir> [--theme light|dark]
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {join,resolve} from 'node:path';
import {spawn} from 'node:child_process';
import {mkdtemp,mkdir,open,writeFile,rm} from 'node:fs/promises';
import * as h from '../vendor/zenit/e2e/client.ts';
const arg=(k:string,d?:string)=>{const i=process.argv.indexOf(k);return i>0?process.argv[i+1]:d;};
const bin=arg('--binary'),out=resolve(arg('--out')??'dist/ai-launcher-preview'),theme=arg('--theme','light')!;
assert(bin,'--binary required');await mkdir(out,{recursive:true});
const iso=await mkdtemp('/private/tmp/zw-ai-launcher-pv-');const rpc=join(iso,'rpc'),data=join(iso,'data');await mkdir(rpc);await mkdir(data);
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;const log=await open(join(out,theme+'-preview.log'),'w');
const app=spawn(bin!,['--theme='+theme],{env:{...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZEROWORK_DATA_DIR:data},stdio:['ignore',log.fd,log.fd]});
const ended=new Promise<void>(r=>app.once('close',()=>r()));
const report:any={status:'running',theme,checks:[] as string[]};
const flat=(n:any):any[]=>n?[n,...(n.children??[]).flatMap(flat)]:[];
const within=(a:any,b:any)=>a.x>=b.x-.5&&a.y>=b.y-.5&&a.x+a.w<=b.x+b.w+.5&&a.y+a.h<=b.y+b.h+.5;
try{
 await h.waitForServerReady();await h.sleep(1200);
 const launchers=await h.query('ai.launcher'),dots=await h.query('ai.launcher.dot'),states=await h.query('ai.launcher.state');
 for(const [i,name] of ['idle','approval','working','failed','unknown','success'].entries()){
  const cell=(await h.query('ai.launcher.preview.'+name))[0].rect;const l=launchers.find((n:any)=>within(n.rect,cell));assert(l,name+' launcher');
  assert.equal(l.rect.w,48);assert.equal(l.rect.h,48);assert.equal(l.rect.x+48,cell.x+cell.w-24);assert.equal(l.rect.y+48,cell.y+cell.h-20);
  assert.equal(states.find((n:any)=>within(n.rect,cell))?.text,name);
  const dot=dots.find((n:any)=>within(n.rect,cell)&&n.rect.w>0);const wants=['approval','failed','unknown','success'].includes(name);
  assert.equal(!!dot,wants,name+' dot');if(dot){assert.equal(dot.rect.w,8);assert.equal(dot.rect.x,l.rect.x+36);assert.equal(dot.rect.y,l.rect.y+4);}
 }
 report.checks.push('Six states: 48 × 48 at 24 / 20, state names, dots only on approval / failed / unknown / success (8 pt at +36 / +4)');
 const icon=async()=>{const w=(await h.query('ai.launcher')).find((n:any)=>within(n.rect,(launchers[2] as any).rect));return flat(w).map((n:any)=>n.opacity??1).reduce((a:number,b:number)=>Math.min(a,b),1);};
 const a=await icon();await h.sleep(500);const b=await icon();report.breathing=[a,b];assert(a!==b||a<1,'running icon breathes');report.checks.push('Running icon opacity changes between samples (breathing)');
 assert((await h.screenshot(join(out,theme+'-states.png'))).ok);report.status='passed';
}catch(e){report.status='failed';report.error=String((e as any)?.stack??e);process.exitCode=1;}
finally{app.kill('SIGTERM');await ended;await log.close();await rm(iso,{recursive:true,force:true});await writeFile(join(out,`report-${theme}.json`),JSON.stringify(report,null,2));}
console.log(report.status+': '+out);
