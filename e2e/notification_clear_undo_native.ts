/** 提醒“清除已结束”是可撤销操作（CONSISTENCY_AUDIT #2）：生产通知历史视图 + 本地夹具事实（notification-preview），亮暗各一遍。
 * 已结束的记录立即消失并弹出带“撤销”的原生 Toast（中下方），Toast 在时协调器里的记录还在；点“撤销”记录回来；
 * 再清除并等 Toast 离场，关掉重开后仍是空的。
 * node e2e/notification_clear_undo_native.ts [output] [light|dark]
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdir,mkdtemp,open,writeFile,rm,realpath} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import * as h from '../zig-out/share/zenit/harness/client.ts';
const out=resolve(process.argv[2]??'/tmp/zw-notification-clear-undo'),theme=process.argv[3]??'light';
assert(['light','dark'].includes(theme));
await mkdir(out,{recursive:true});
const iso=await realpath(await mkdtemp(join(tmpdir(),'zw-notification-clear-'))),rpc=join(iso,'rpc'),data=join(iso,'data');
await mkdir(rpc);await mkdir(data);process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const log=await open(join(out,`${theme}.log`),'w');
const app=spawn(resolve('zig-out/bin/notification-preview'),[],{env:{...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1',ZEROWORK_DATA_DIR:data},stdio:['ignore',log.fd,log.fd]});
const ended=new Promise(r=>app.once('close',r));
const shown=(n:any)=>n?.rect&&n.hidden!==true&&n.visible!==false&&(n.effective_opacity??1)>0&&n.rect.w>0&&n.rect.h>0;
const text=(n:any):string=>(n.text??'')+(n.children??[]).map(text).join('');
const visible=(id:string,ms=10000)=>h.waitFor(async()=>(await h.query(id)).find(shown)??null,ms);
const absent=(id:string,ms=10000)=>h.waitFor(async()=>!(await h.query(id)).some(shown)||null,ms);
const click=async(id:string)=>{const n=await visible(id);assert((await h.clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok,id);await h.sleep(150);};
const records=async()=>(await h.query('notifications.history.record')).filter(shown).length;
const report:any={status:'running',theme,checks:[],captures:[]};
try{
 await h.waitForServerReady(30000);await h.resizeWindow(1280,800);
 await click(`fixture.theme.${theme}`);
 await click('fixture.action');await click('fixture.action');await click('fixture.outcomes');
 await h.mouseMove(20,700);await h.waitFor(async()=>!(await h.query('notifications.toast.0')).some(shown)||null,15000).catch(()=>{});
 await click('toolbar.notifications');await click('notifications.history.recent');
 await h.waitFor(async()=>(await records())>=1||null,5000);
 const before=await records();
 await click('notifications.history.clear');
 await h.waitFor(async()=>(await records())===0||null,5000);
 const toast=await visible('notifications.undo');assert(text(toast).includes('已清除已结束的提醒'),'toast text: '+text(toast));
 assert(text(await visible('notifications.undo.action')).includes('撤销'));
 await h.mouseMove(20,700);await h.sleep(300);assert((await h.screenshot(join(out,`${theme}-clear-ended-undo-toast.png`))).ok);report.captures.push(`${theme}-clear-ended-undo-toast`);
 await click('notifications.undo.action');
 // The toast sits outside the panel: the click also closes the panel (outside click); reopen to look.
 if(!(await h.query('notifications.history')).some(shown)){await click('toolbar.notifications');await click('notifications.history.recent');}
 await h.waitFor(async()=>(await records())===before||null,5000);
 await absent('notifications.undo',15000);
 report.checks.push('清除已结束: hidden at once, native toast with 撤销, 撤销 restores every record');
 if(!(await h.query('notifications.history')).some(shown)){await click('toolbar.notifications');await click('notifications.history.recent');}
 await click('notifications.history.clear');await visible('notifications.undo');
 await h.mouseMove(20,700);await absent('notifications.undo',20000);
 await h.key('escape');await absent('notifications.history');
 await click('toolbar.notifications');await click('notifications.history.recent');await h.sleep(300);
 assert.equal(await records(),0,'the toast leaving clears the ended records');
 report.checks.push('清除已结束: the toast leaving clears them for good');
 report.status='passed';
}catch(error){report.status='failed';report.error=String(error);process.exitCode=1;await h.screenshot(join(out,`${theme}-failure.png`)).catch(()=>{});}
finally{app.kill('SIGTERM');await Promise.race([ended,new Promise(r=>setTimeout(r,3000))]);await log.close();await rm(iso,{recursive:true,force:true});await writeFile(join(out,`report-${theme}.json`),JSON.stringify(report,null,2));console.log(JSON.stringify(report));}
