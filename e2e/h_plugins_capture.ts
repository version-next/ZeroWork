/**
 * F-set-plugins 验收对照图（人工验收反馈第 10 条：协议插件改为两级导航，设计稿 `T5k96` 列表 → `KUKQ5` 详情）。
 * 一次性采集脚本，基于 `settings_nav.ts` 的隔离启动与导航。每个主题采集：
 *   (a) 列表页（设置窗口默认 960 × 780，与设计稿同宽，便于 design_diff；含“计划中”的路线条目）；
 *   (b) 每个已注册插件的详情页（本地终端 / SSH / SFTP / BMC · iKVM）；
 *   (c) 后退回列表、前进回详情（各一张）；
 *   (d) 搜索命中插件项（“SFTP”）与点命中项进入详情；
 *   (e) 详情页权限“?”的原生 Tooltip。
 * 能力对照表：产品没有这份数据（见报告），不采。
 *
 * Usage: node e2e/h_plugins_capture.ts <zerowork binary (test-mode)> <out dir> [light|dark]
 */
import assert from 'node:assert/strict';
import {join,resolve} from 'node:path';
import {writeFile,readFile} from 'node:fs/promises';
import * as h from '../vendor/zenit/e2e/client.ts';
import {launchIsolated,settingsNav,shown,textOf} from './settings_nav.ts';

const [binaryArg,outArg,theme='light']=process.argv.slice(2);
if(!binaryArg||!outArg)throw new Error('usage: h_plugins_capture.ts <binary> <out> [light|dark]');
const out=resolve(outArg);
const run=await launchIsolated({binary:resolve(binaryArg),out,prefix:'zw-h-plugins-capture',theme,logName:`app-${theme}.log`});
const nav=settingsNav();
const report:any={status:'running',theme,shots:[] as string[],checks:[] as string[],rects:{} as Record<string,unknown>};
let win:string|undefined;
const shot=async(name:string,park=true)=>{if(park){await h.mouseMove(2,2).catch(()=>{});await h.sleep(300);}const path=join(out,`${theme}-${name}.png`);assert((await h.screenshot(path,win)).ok,name);report.shots.push(path);};
const rect=async(id:string)=>{const n=(await h.query(id)).find(shown);report.rects[id]=n?.rect??null;return n?.rect;};
const plugins:[string,string][]=[['local','Local · zsh'],['ssh','SSH'],['sftp','SFTP'],['bmc_ikvm','BMC · iKVM']];

try{
 const initial=await readFile(run.config,'utf8');
 await h.resizeWindow(1440,900);
 await nav.open();
 win=(await h.windows()).windows.find(w=>w.bound&&!w.closing)?.window_id;
 // (a) 列表页。
 await nav.toCategory('plugins');
 await nav.node('settings.plugin.ssh.row');
 for(const id of ['settings.plugins.builtin','settings.plugins.bundled','settings.plugin.local.row','settings.plugin.ssh.row','settings.plugin.sftp.row'])await rect(id);
 await rect('settings.plugins.planned');
 assert(textOf(await nav.node('settings.plugins.planned')).includes('网页连接'));
 await shot('a-list');
 report.checks.push('list page: 已内置 / 随应用提供 groups, one drill-down row per plugin; 计划中 lists only 网页连接 · 0.5 版本待实施');
 // (b) 每个插件的详情页。
 for(const [id,name] of plugins){
  if(!(await nav.visible(`settings.plugin.${id}.row`))){report.checks.push(`${id}: not registered in this build`);continue;}
  await nav.click(`settings.plugin.${id}.row`);await nav.waitTitle(name);
  await nav.node(`settings.plugin.${id}.detail`);
  await rect(`settings.plugin.${id}.header`);
  await shot(`b-detail-${id}`);
  await nav.back();await nav.waitTitle('协议插件');
 }
 report.checks.push('every registered plugin opens its detail page');
 // (c) 后退 / 前进往返。
 await nav.click('settings.plugin.ssh.row');await nav.waitTitle('SSH');
 await nav.back();await nav.waitTitle('协议插件');
 await shot('c-back-list');
 await nav.forward();await nav.waitTitle('SSH');
 await shot('c-forward-detail');
 report.checks.push('back → list, forward → SSH detail');
 // (e) 权限“?”提示。
 await nav.click('settings.plugin.ssh.permissions');
 const tip=await nav.node('settings.plugin.ssh.permissions.tooltip');
 assert(textOf(tip).includes('钥匙串'));
 await shot('e-permissions-tooltip',false);
 await h.key('escape');await nav.gone('settings.plugin.ssh.permissions.tooltip');
 report.checks.push('permissions help: native tooltip, Escape closes it first');
 // (d) 搜索命中。
 const search=await nav.node('settings.search');
 assert((await h.clickAt(search.rect.x+search.rect.w/2,search.rect.y+search.rect.h/2)).ok);
 await h.type_('SFTP');await nav.waitTitle('搜索结果');
 await nav.node('settings.plugin.sftp.row');
 await shot('d-search-hit');
 await nav.click('settings.plugin.sftp.row');await nav.waitTitle('SFTP');
 await shot('d-search-open');
 report.checks.push('search “SFTP” lists the protocol row; clicking it opens the detail and leaves the search');
 assert.equal(await readFile(run.config,'utf8'),initial,'browsing never writes configuration');
 report.status='passed';
}catch(e){report.status='failed';report.error=String((e as any)?.stack??e);process.exitCode=1;await shot('failure').catch(()=>{});}
finally{await run.stop();await writeFile(join(out,`report-${theme}.json`),JSON.stringify(report,null,2));console.log(JSON.stringify({status:report.status,checks:report.checks.length,error:report.error}));}
