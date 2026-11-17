/** 确认与撤销（CONSISTENCY_AUDIT #2，用户拍板 2）：真实 test-mode 应用、私有数据目录、不建立任何 SSH 连接。
 * - 可撤销：侧栏菜单“删除主机”直接执行——主机从侧栏消失并弹出带“撤销”的原生 Toast；Toast 在时 hosts.toml 不变，
 *   点“撤销”主机回来；再删一次并等 Toast 离场，hosts.toml 里才没有它。
 * - 不可逆：本地会话按 ⌘W 弹共享原生确认框（标题“关闭页签？”、后果写在说明里、焦点在“取消”、危险的“关闭页签”），
 *   Esc 取消、页签保留。
 * - 可撤销：会话记录卡片的“清空历史列表”——记录立即消失并弹带“撤销”的 Toast，Toast 在时 index.tsv 不变，撤销后回来；
 *   再清空并等 Toast 离场才删除。
 * 亮、暗两种主题各跑一遍，截 Toast 与 Modal。
 * node e2e/confirm_undo_native.ts [output] [light|dark]
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdir,mkdtemp,open,readFile,writeFile,rm,realpath} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import * as h from '../zig-out/share/zenit/harness/client.ts';
import {openSidebarHostMenu} from './sidebar_host_menu.ts';

const out=resolve(process.argv[2]??'/tmp/zw-confirm-undo');
const theme=process.argv[3]??'light';
assert(['light','dark'].includes(theme));
await mkdir(out,{recursive:true});
const iso=await realpath(await mkdtemp(join(tmpdir(),'zw-confirm-undo-'))),rpc=join(iso,'rpc'),data=join(iso,'data');
await mkdir(rpc);await mkdir(data);
await writeFile(join(data,'config.toml'),`[meta]\nconfig_revision=1\n[ui]\ntheme="${theme}"\nfont_family="Menlo"\nfont_size=14\n[updates]\nauto_check=false\n`);
let hosts='[registry]\nschema_version=2\nrevision=1\nnext_connection_id=3\nnext_group_id=2\n[[groups]]\ngroup_id=1\nrevision=1\nname="Production"\nordered_connection_ids=[1,2]\n';
for(const [i,name] of ['db-primary','web-01'].entries())hosts+=`[[hosts]]\nconnection_id=${i+1}\nrevision=1\nprotocol="ssh"\nauth_mode="password"\nname="${name}"\nhost="192.0.2.${10+i}"\nport=22\nuser="demo"\nasset_group_id=1\nroute=[]\n`;
await writeFile(join(data,'hosts.toml'),hosts);
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const log=await open(join(out,`${theme}.log`),'w');
const app=spawn(resolve('zig-out/bin/zerowork'),[],{env:{...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1'},stdio:['ignore',log.fd,log.fd]});
const ended=new Promise(r=>app.once('close',r));
const shown=(n:any)=>n?.rect&&n.hidden!==true&&n.visible!==false&&(n.effective_opacity??1)>0&&n.rect.w>0&&n.rect.h>0;
const text=(n:any):string=>(n.text??'')+(n.children??[]).map(text).join('');
const flat=(n:any):any[]=>[n,...(n.children??[]).flatMap(flat)];
const visible=(id:string,ms=10000)=>h.waitFor(async()=>(await h.query(id)).find(shown)??null,ms);
const absent=(id:string,ms=10000)=>h.waitFor(async()=>!(await h.query(id)).some(shown)||null,ms);
const click=async(id:string)=>{const n=await visible(id);assert((await h.clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok,id);await h.sleep(150);};
const hostNames=async()=>(await h.query('sidebar.host')).filter(shown).map(text);
const report:any={status:'running',theme,checks:[],captures:[]};
const capture=async(name:string,ids:string[])=>{await h.sleep(250);const observed:any={};for(const id of ids)observed[id]=await h.query(id);await writeFile(join(out,`${theme}-${name}.json`),JSON.stringify(observed,null,2));assert((await h.screenshot(join(out,`${theme}-${name}.png`))).ok);report.captures.push(`${theme}-${name}`);};
try{
 await h.waitForServerReady(30000);await h.resizeWindow(1280,800);
 await h.waitFor(async()=>(await hostNames()).length===2||null,15000);
 // ── 可撤销：删除主机 ──
 const target=(await h.query('sidebar.host')).filter(shown).find((n:any)=>text(n).includes('web-01'));assert(target,'web-01 row');
 await openSidebarHostMenu(target);
 const item=await visible('context.menu.delete_host');assert(text(item).includes('删除主机'));
 assert((await h.clickAt(item.rect.x+item.rect.w/2,item.rect.y+item.rect.h/2)).ok);
 await h.waitFor(async()=>!(await hostNames()).some(t=>t.includes('web-01'))||null,5000);
 assert.equal((await h.query('asset.action')).filter(shown).length,0,'no inline confirmation popover');
 const toast=await visible('notifications.undo');assert(text(toast).includes('已删除主机 web-01'),'undo toast text: '+text(toast));
 assert(text(await visible('notifications.undo.action')).includes('撤销'));
 assert((await readFile(join(data,'hosts.toml'),'utf8')).includes('web-01'),'nothing is deleted while the toast is up');
 await h.mouseMove(640,780);await capture('host-delete-undo-toast',['notifications.undo','sidebar.host']);
 await click('notifications.undo.action');
 await h.waitFor(async()=>(await hostNames()).some(t=>t.includes('web-01'))||null,5000);
 await h.mouseMove(20,400);await absent('notifications.undo',15000);
 assert((await readFile(join(data,'hosts.toml'),'utf8')).includes('web-01'),'撤销 keeps the host');
 report.checks.push('删除主机: hidden at once, toast 已删除主机 web-01 with 撤销, hosts.toml untouched, 撤销 brings it back');
 await openSidebarHostMenu((await h.query('sidebar.host')).filter(shown).find((n:any)=>text(n).includes('web-01')));
 await click('context.menu.delete_host');await visible('notifications.undo');
 await h.mouseMove(20,400);await absent('notifications.undo',20000);
 await h.waitFor(async()=>!(await readFile(join(data,'hosts.toml'),'utf8')).includes('web-01')||null,10000);
 assert((await readFile(join(data,'hosts.toml'),'utf8')).includes('db-primary'),'the other host stays');
 assert(!(await hostNames()).some(t=>t.includes('web-01')));
 report.checks.push('删除主机: the toast leaving deletes the host from hosts.toml (the other host stays)');
 // ── 不可逆：关闭页签（本地会话） ──
 await click('workspace.empty.local');await visible('terminal.surface');await h.sleep(1200);
 await click('terminal.surface');await h.type_('sleep 120\n');await h.sleep(800);
 assert((await h.key('w',{cmd:true})).ok);
 const dialog=await visible('local.close.confirmation');
 assert(text(dialog).includes('关闭页签？'),'title');
 assert(text(await visible('local.close.notice')).includes('关闭页签会结束该本地会话及其进程'),'consequence in the message');
 assert.equal(text(await visible('local.close.accept')),'关闭页签');assert.equal(text(await visible('local.close.cancel')),'取消');
 await h.waitFor(async()=>(await h.focused() as any)?.test_id==='local.close.cancel'||null,5000);
 await h.mouseMove(20,780);await capture('close-tab-confirm',['local.close.confirmation']);
 assert((await h.key('escape')).ok);await absent('local.close.confirmation');await visible('terminal.surface');
 report.checks.push('关闭页签: native ConfirmDialog, consequence in the message, focus on 取消, danger 关闭页签, Esc keeps the tab');
 assert((await h.key('w',{cmd:true})).ok);await visible('local.close.confirmation');await click('local.close.accept');await absent('local.close.confirmation');
 await h.waitFor(async()=>(await h.query('terminal.surface')).filter(shown).length===0||null,10000);
 report.checks.push('关闭页签: 关闭页签 closes the tab');
 // ── 可撤销：清空会话记录（会话记录卡片的“清空历史列表”） ──
 const index=async()=>{try{return await readFile(join(data,'logs/history/index.tsv'),'utf8')}catch{return ''}};
 await h.waitFor(async()=>(await index()).trim().length>0||null,15000);
 await click('toolbar.history');await visible('history.panel');
 await h.waitFor(async()=>(await h.query('history.record')).filter(shown).length>0||null,10000);
 const before=await index();
 await click('history.clear');
 await h.waitFor(async()=>(await h.query('history.record')).filter(shown).length===0||null,5000);
 assert.equal((await h.query('history.confirmation')).filter(shown).length,0,'no inline confirmation bubble');
 const cleared=await visible('notifications.undo');assert(text(cleared).includes('已清空会话记录'),'undo toast text: '+text(cleared));
 assert.equal(await index(),before,'nothing is deleted while the toast is up');
 await h.mouseMove(640,780);await capture('history-clear-undo-toast',['notifications.undo','history.panel']);
 await click('notifications.undo.action');
 await h.waitFor(async()=>(await h.query('history.record')).filter(shown).length>0||null,5000);
 await h.mouseMove(20,400);await absent('notifications.undo',15000);
 assert.equal(await index(),before,'撤销 keeps every record');
 await click('history.clear');await visible('notifications.undo');await h.mouseMove(20,400);await absent('notifications.undo',20000);
 await h.waitFor(async()=>(await h.query('history.record')).filter(shown).length===0||null,10000);
 await h.waitFor(async()=>!(await index()).includes('local')||(await index()).trim().split('\n').length<before.trim().split('\n').length||null,10000);
 report.checks.push('清空会话记录: hidden at once, toast with 撤销, index untouched while it is up, 撤销 restores, the toast leaving deletes');
 report.status='passed';
}catch(error){report.status='failed';report.error=String(error);process.exitCode=1;await h.screenshot(join(out,`${theme}-failure.png`)).catch(()=>{});}
finally{
 await h.request('POST','/zerowork/windows',{action:'quit'}).catch(()=>{});
 await Promise.race([ended,new Promise(r=>setTimeout(r,8000))]);if(app.exitCode===null&&app.signalCode===null)app.kill('SIGTERM');await ended;
 await log.close();await rm(iso,{recursive:true,force:true});
 await writeFile(join(out,`report-${theme}.json`),JSON.stringify(report,null,2));console.log(JSON.stringify(report));
}
