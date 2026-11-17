/**
 * Yix spike（docs/ui-revamp/YIX_SPIKE.md）真实窗口取证：经 zenit Harness 在 mockup-yix_spike
 * 窗口里按 test_id 查询、点击、截图。补充自检（YIX_SPIKE_SELFCHECK=1）在无窗口 Cx 上的断言：
 *   V-3  真实指针路径点击 onClick={send(vm, .forward)} / @unionInit 载荷；
 *   V-5  旧命令式面板内部的 test_id 能被 Harness query 到；卸载后查不到、重挂后又能查到；
 *   V-1/V-2/V-4  文本随 view-model 更新。
 *
 * Usage: node e2e/yix_spike_native.ts <mockup-yix_spike (test-mode)> <evidence dir>
 * 隔离的 RPC 目录；不需要网络。
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdtemp,mkdir,realpath,open,writeFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import * as h from '../vendor/zenit/e2e/client.ts';

const [binaryArg,outArg]=process.argv.slice(2);
if(!binaryArg||!outArg)throw new Error('usage: yix_spike_native.ts <binary> <out>');
const binary=resolve(binaryArg),out=resolve(outArg);await mkdir(out,{recursive:true});
const iso=await realpath(await mkdtemp('/private/tmp/zw-yix-spike-')),rpc=join(iso,'rpc');
await mkdir(rpc);
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const log=await open(join(out,'app.log'),'w');
const app=spawn(binary,[],{env:{...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1',HOME:iso,CFFIXED_USER_HOME:iso},stdio:['ignore',log.fd,log.fd]});
const ended=new Promise(r=>app.once('close',r));

const text=(n:any):string=>[n?.text??'',...(n?.children??[]).map(text)].join('');
const shown=(n:any)=>n&&n.visible!==false&&n.rect?.w>0&&n.rect?.h>0;
const node=async(id:string,ms=10000)=>h.waitFor(async()=>(await h.query(id)).find(shown)??null,ms);
const textOf=async(id:string)=>text(await node(id));
const waitText=async(id:string,want:string)=>h.waitFor(async()=>(await textOf(id))===want?true:null,5000);
const click=async(id:string)=>{const n:any=await node(id);assert((await h.clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok,id);await h.sleep(150);};
const report:any={status:'running',checks:[] as string[]};
const pass=(s:string)=>{report.checks.push('PASS '+s);console.log('PASS '+s);};

try{
 await h.waitForServerReady();
 await node('spike.v2');
 await h.screenshot(join(out,'initial.png'));

 // V-5：旧面板内部 test_id 经 Harness query 可见
 const legacyIds=['spike.v5.legacy','spike.v5.legacy.title','spike.v5.legacy.badge','spike.v5.legacy.swatch','spike.v5.legacy.button'];
 for(const id of legacyIds) await node(id);
 pass(`V-5 harness query finds ${legacyIds.length} test_ids inside the embedded imperative panel`);

 // V-2 / V-4 初始文本
 assert.equal(await textOf('spike.v2.title'),'概览');
 assert.equal(await textOf('spike.v4.inline_get'),'101');
 assert.equal(await textOf('spike.v1.count'),'1');
 pass('V-1/V-2/V-4 initial text: v2.title=概览 v4.inline_get=101 v1.count=1');

 // V-3：真实指针点击（clickAt → 命中测试 → onClick）
 await click('spike.v3.forward');
 await waitText('spike.v2.title','子页面');
 assert.equal(await textOf('spike.v2.mode'),'panes');
 pass('V-3 pointer click on onClick={send(vm, .forward)} -> v2.title=子页面, v2.mode=panes');
 await click('spike.v3.add');
 await waitText('spike.v1.count','6');
 assert.equal(await textOf('spike.v4.inline_get'),'106');
 pass('V-3 pointer click on onClick={send(vm, @unionInit(m.Intent, "set_count", 5))} -> v1.count=6, v4.inline_get=106');
 await click('spike.v3.back');
 await waitText('spike.v2.title','概览');
 pass('V-3 back -> v2.title=概览');

 // V-5：卸载 / 重挂
 await click('spike.v5.toggle');
 await h.waitFor(async()=>(await h.query('spike.v5.legacy.button')).length===0?true:null,5000);
 pass('V-5 branch unmount -> legacy test_ids gone from harness query');
 await click('spike.v5.toggle');
 for(const id of legacyIds) await node(id);
 pass('V-5 remount -> legacy test_ids queryable again');
 await click('spike.v5.legacy.button');
 pass('V-5 pointer click on legacy W.Button (cx.on handler) dispatched without error');

 await h.mouseMove(2,2).catch(()=>{});await h.sleep(150);
 assert((await h.screenshot(join(out,'final.png'))).ok);
 report.status='passed';
}catch(err){report.status='failed';report.error=String((err as any)?.stack??err);console.error(err);process.exitCode=1;}
finally{
 await writeFile(join(out,'report.json'),JSON.stringify(report,null,1));
 app.kill('SIGTERM');
 await Promise.race([ended,h.sleep(5000)]);
 if(app.exitCode===null&&app.signalCode===null)app.kill('SIGKILL');
}
