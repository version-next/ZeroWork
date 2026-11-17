/**
 * 协议插件（F-set-plugins，人工验收反馈第 10 条）真实窗口契约：两级导航——列表页（`T5k96`）→ 每个已注册插件的详情页（`KUKQ5`）。
 * 隔离启动（`settings_nav.ts` 的 `launchIsolated`），真实注册表（本地终端 / SSH / SFTP 内置，BMC · iKVM 随应用提供）。
 *   - 列表：每个插件一行（名称、清单说明、版本尾注），按来源分组；BMC · iKVM 是“随应用提供”的已注册插件；
 *     “计划中”只有路线条目“网页连接 · 0.5 版本待实施”（旧的 FTP / VNC / RDP / KVM 计划已删除）；没有详情 / 对话框；
 *   - 点一行进详情：页头标题是插件名，版本值、权限值 + 原生“?”提示（悬停 / 点击打开，Escape 先收起它、不关窗）；
 *   - 页头后退回列表、前进回详情；
 *   - 紧凑窗口（860 × 480）：列表可滚动、行可点；
 *   - 浏览插件页不改配置。
 * Usage: node e2e/plugin_settings_v3_native.ts <zerowork binary (test-mode)> <out dir>
 */
import assert from 'node:assert/strict';
import {join,resolve} from 'node:path';
import {readFile,writeFile} from 'node:fs/promises';
import * as h from '../vendor/zenit/e2e/client.ts';
import {launchIsolated,settingsNav,shown,textOf} from './settings_nav.ts';

const [binaryArg,outArg]=process.argv.slice(2);assert(binaryArg&&outArg,'usage: plugin_settings_v3_native.ts <binary> <out>');
const out=resolve(outArg);
const run=await launchIsolated({binary:resolve(binaryArg),out,prefix:'zw-plugin-v3',theme:'dark',config:'font_size=14\n'});
const nav=settingsNav();
const report:any={status:'running',checks:[],screenshots:[],geometry:{}};
const shot=async(name:string,keepPointer=false)=>{if(!keepPointer)await h.mouseMove(2,2).catch(()=>{});await h.sleep(350);const path=join(out,name+'.png');assert((await h.screenshot(path)).ok,name);report.screenshots.push(path);};
const text=async(id:string)=>textOf(await nav.node(id)).trim();
const builtins:[string,string,string][]=[['local','Local · zsh','本机 Shell 与终端会话'],['ssh','SSH','远程终端、认证与端口转发'],['sftp','SFTP','目录浏览、文件读写与文件传输']];
try{
 const initial=await readFile(run.config,'utf8');
 await h.resizeWindow(1440,900);
 await nav.toCategory('plugins');
 // 列表页：分组 + 每个插件一行。
 assert((await text('settings.plugins.builtin')).includes('已内置'));
 assert.match(await text('settings.plugins.builtin.summary'),/^3 个协议 · 随应用管理$/);
 for(const [id,,desc] of builtins){
  await nav.node(`settings.plugin.${id}.row`);
  assert.equal(await text(`settings.plugin.${id}.description`),desc,`${id} description`);
  assert((await text(`settings.plugin.${id}.trail`)).length>0,`${id} version trail`);
 }
 const rows=await Promise.all(builtins.map(([id])=>nav.node(`settings.plugin.${id}.row`)));
 for(let i=1;i<rows.length;i++)assert(rows[i].rect.y>rows[i-1].rect.y,'rows stack vertically');
 report.geometry.rows=rows.map((r:any)=>r.rect);
 assert(!(await nav.visible('settings.plugins.list')),'no master/detail list pane');
 assert(!(await nav.visible('settings.reset')),'list page has no editable fields');
 // KVM 由已注册的 bmc_ikvm 实现：随应用提供分组里的一行，说明来自清单、尾注是真实版本号。
 await nav.node('settings.plugin.bmc_ikvm.row');
 assert((await text('settings.plugins.bundled')).includes('随应用提供'));
 assert.equal(await text('settings.plugin.bmc_ikvm.description'),'远程画面、键鼠输入、电源与启动管理','bmc description');
 assert.match(await text('settings.plugin.bmc_ikvm.trail'),/^\d+\.\d+\.\d+$/,'bmc version trail');
 report.checks.push('bundled BMC · iKVM listed under 随应用提供 with its manifest summary and version');
 // 计划中：只有路线条目（网页连接），没有尾注与箭头，在已注册分组之后。
 const planned=await nav.node('settings.plugins.planned');
 assert(textOf(planned).includes('计划中'));
 assert.equal(await text('settings.plugins.planned.web.name'),'网页连接');
 assert.equal(await text('settings.plugins.planned.web.summary'),'0.5 版本待实施');
 for(const old of ['FTP','VNC','RDP','KVM','未发布','待定义'])assert(!textOf(planned).includes(old),`planned has no ${old}`);
 assert(planned.rect.y>(await nav.node('settings.plugins.bundled')).rect.y,'planned after registered groups');
 report.checks.push('planned group lists only the roadmap entry 网页连接 · 0.5 版本待实施');
 await shot('plugins-list');
 report.checks.push('list: grouped rows with names, descriptions and version trails; no detail pane, no reset row');
 // 详情页。
 for(const [id,name] of builtins){
  await nav.click(`settings.plugin.${id}.row`);
  await nav.waitTitle(name);
  await nav.node(`settings.plugin.${id}.detail`);
  assert((await text(`settings.plugin.${id}.version`)).length>0);
  assert.equal(await text(`settings.plugin.${id}.permissions.value`),'连接时按需请求');
  assert((await text(`settings.plugin.${id}.version.message`)).includes('插件随应用更新'));
  if(id==='ssh')await shot('ssh-detail');
  await nav.back();await nav.waitTitle('协议插件');await nav.node(`settings.plugin.${id}.row`);
 }
 report.checks.push('each builtin row opens its detail page (title = plugin name, version, permissions, managed note); back returns to the list');
 // BMC · iKVM 详情：真实版本、清单说明、随应用提供。
 await nav.click('settings.plugin.bmc_ikvm.row');await nav.waitTitle('BMC · iKVM');
 await nav.node('settings.plugin.bmc_ikvm.detail');
 assert.equal(await text('settings.plugin.bmc_ikvm.summary'),'远程画面、键鼠输入、电源与启动管理');
 assert.match(await text('settings.plugin.bmc_ikvm.version'),/^\d+\.\d+\.\d+$/);
 assert((await text('settings.plugin.bmc_ikvm.version.message')).includes('随应用提供'));
 await shot('bmc-detail');
 await nav.back();await nav.waitTitle('协议插件');
 report.checks.push('BMC · iKVM detail: manifest summary, real version, bundled note');
 // 权限“?”：原生 Tooltip；Escape 先收起它，不关窗。
 await nav.click('settings.plugin.sftp.row');await nav.waitTitle('SFTP');
 await nav.click('settings.plugin.sftp.permissions');
 const tip=await nav.node('settings.plugin.sftp.permissions.tooltip');
 assert(textOf(tip).includes('按用户选择的路径访问本地文件'));
 await shot('sftp-permissions-tooltip',true);
 assert(await nav.visible('settings.plugin.sftp.permissions.tooltip'),'tooltip is open when Escape is pressed');
 await h.key('escape');await nav.gone('settings.plugin.sftp.permissions.tooltip');await h.sleep(200);
 await nav.node('settings.panel');await nav.node('settings.plugin.sftp.detail');
 report.checks.push('permissions help is a native tooltip; Escape closes it first and keeps the window open');
 // 后退 / 前进。
 await nav.back();await nav.waitTitle('协议插件');
 await nav.forward();await nav.waitTitle('SFTP');
 report.checks.push('history back / forward between list and detail');
 // 紧凑窗口。
 await nav.back();await nav.waitTitle('协议插件');
 await h.resizeWindow(860,480);await h.sleep(300);
 await shot('plugins-compact');
 const v=await nav.node('settings.viewport');
 await h.scrollAt(v.rect.x+v.rect.w/2,v.rect.y+v.rect.h/2,0,-500);await h.sleep(200);
 await shot('plugins-compact-scrolled');
 await nav.click('settings.plugin.local.row');await nav.waitTitle('Local · zsh');
 await shot('local-detail-compact');
 report.checks.push('compact window: list scrolls, rows still open details');
 assert.equal(await readFile(run.config,'utf8'),initial,'browsing plugin pages never writes configuration');
 assert(!(await nav.visible('settings.footer')),'browsing keeps the draft clean');
 report.status='passed';
}catch(e){report.status='failed';report.error=String((e as any)?.stack??e);process.exitCode=1;await shot('failure').catch(()=>{});}
finally{await run.stop();await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));console.log(JSON.stringify({status:report.status,checks:report.checks.length,error:report.error}));}
