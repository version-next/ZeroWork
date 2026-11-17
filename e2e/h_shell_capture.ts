/**
 * H-shell 第二轮验收对照图（人工验收反馈 1、3、5、11：设置外壳的原生 liquid glass、页头渐变、回弹、帮助提示）。
 * 一次性采集脚本，基于 `settings_nav.ts` 的隔离启动与导航。每个主题采集：
 *   (a) 概览页；(b) 内容较长的子页面（AI 辅助 › 行为与权限）滚到中部——页头渐变压在内容上；
 *   (c) 帮助提示展开；(d) 后退 / 前进的可用与禁用态；(e) 开关一半滚到页头下方时，页头高度内的点击不落到开关（S-10）。
 * 另外断言：滚动越过顶端后偏移回到 0（回弹本身的手感 Harness 测不到，未实证）。
 *
 * Usage: node e2e/h_shell_capture.ts <zerowork binary (test-mode)> <out dir> [light|dark]
 */
import assert from 'node:assert/strict';
import {join,resolve} from 'node:path';
import {writeFile} from 'node:fs/promises';
import * as h from '../vendor/zenit/e2e/client.ts';
import {launchIsolated,settingsNav,shown,textOf} from './settings_nav.ts';

const [binaryArg,outArg,theme='light']=process.argv.slice(2);
if(!binaryArg||!outArg)throw new Error('usage: h_shell_capture.ts <binary> <out> [light|dark]');
const out=resolve(outArg);
const run=await launchIsolated({binary:resolve(binaryArg),out,prefix:'zw-h-shell-capture',theme,logName:`app-${theme}.log`});
const nav=settingsNav();
const report:any={status:'running',theme,shots:[] as string[],checks:[] as string[]};
let win:string|undefined;
const shot=async(name:string,park=true)=>{if(park){await h.mouseMove(2,2).catch(()=>{});await h.sleep(200);}const path=join(out,`${theme}-${name}.png`);assert((await h.screenshot(path,win)).ok,name);report.shots.push(path);};
const offsetOf=async(id:string)=>{const v:any=(await h.query('settings.viewport')).find(shown),n:any=(await h.query(id)).find(shown);return n.rect.y-v.rect.y;};

try{
 await h.resizeWindow(1440,900);
 await nav.open();
 win=(await h.windows()).windows.find(w=>w.bound&&!w.closing)?.window_id;
 // (d1) 刚打开：后退、前进都不可用。
 await nav.node('settings.overview');await nav.waitTitle('外观与主题');
 await shot('a-overview');
 report.checks.push('overview captured (fresh window: no history, back and forward disabled)');
 // (b) 长子页面滚到中部。
 await nav.toSub('ai','behavior');
 const v:any=(await h.query('settings.viewport')).find(shown);
 const anchor='settings.ai.permissions';
 const before=await offsetOf(anchor);
 for(let i=0;i<4;i++){await h.scrollAt(v.rect.x+v.rect.w/2,v.rect.y+v.rect.h/2,0,-120);await h.sleep(120);}
 await h.sleep(600);
 const after=await offsetOf(anchor);
 assert(after<before-200,`scrolled (${before} → ${after})`);
 await shot('b-scrolled-mid');
 report.checks.push(`long subpage scrolled under the header (${before} → ${after})`);
 // (d2) 子页面：后退可用、前进不可用；后退一次后前进可用。
 await shot('d-back-enabled-forward-disabled');
 await nav.back();await nav.node('settings.overview');
 await shot('d-forward-enabled');
 report.checks.push('history states captured: subpage (back enabled, forward disabled), after Back (forward enabled); Harness query has no disabled field, states are covered by the component tests');
 // 回弹（Harness 只能验证结果）：在顶端继续往下拉，偏移回到边界。
 await nav.forward();await nav.waitTitle('行为与权限');
 for(let i=0;i<6;i++){await h.scrollAt(v.rect.x+v.rect.w/2,v.rect.y+v.rect.h/2,0,200);await h.sleep(60);}
 await h.sleep(900);
 const top=await offsetOf(anchor),rest=await offsetOf(anchor);
 assert.equal(Math.round(top),Math.round(rest));
 assert(top>=before-1&&top<=before+1,`back at the top edge (${top} vs ${before})`);
 report.checks.push('overscroll at the top settles back at the edge (trackpad feel: not verified)');
 // 标题栏拖动带与滚上来的控件（生产窗口用 window chrome，页头是拖动区，S-10）：把一个开关滚到“一半在页头下方”，
 // 点它在页头高度范围内的部分——第 2 轮起视口伸到浮动页头底下（照 znote），页头拦截命中，点击不落到开关（草稿不变）；
 // 再点它在页头下方露出的部分，开关照常切换。
 {
  {const s:any=(await h.query('settings.search')).find(shown);await h.clickAt(s.rect.x+s.rect.w/2,s.rect.y+s.rect.h/2);await h.type_('s');await nav.waitTitle('搜索结果');await h.mouseMove(2,2);await h.sleep(400);}
  const sw='settings.field.compression';
  await nav.reveal(sw);
  // The all-fields search result exceeds the Harness query limit for the viewport subtree: read its screen rectangle instead.
  const vq:any=await h.query('settings.viewport');const vp:any=Array.isArray(vq)?vq.find(shown):{rect:await h.screenPos('settings.viewport')},intro:any=(await h.query('settings.page.intro')).find(shown);
  assert(vp.rect.y<=intro.rect.y+0.5,`viewport runs under the floating header (${vp.rect.y} vs ${intro.rect.y})`);
  const top=intro.rect.y+intro.rect.h;
  let n:any=(await h.query(sw)).find(shown);
  for(let i=0;i<60&&!(n.rect.y<top&&n.rect.y+n.rect.h>top+4);i++){
   const want=n.rect.y-(top-n.rect.h/2);await h.scrollAt(vp.rect.x+vp.rect.w/2,vp.rect.y+vp.rect.h/2,0,-Math.max(-40,Math.min(40,want)));await h.sleep(250);
   n=(await h.query(sw)).find(shown);
  }
  assert(n.rect.y<top&&n.rect.y+n.rect.h>top+4,`switch straddles the header bottom (${n.rect.y}..${n.rect.y+n.rect.h} vs ${top})`);
  await shot('e-switch-under-header');
  // H-save：干净时没有 Save Bar（不再有常驻的“所有更改已保存”）；有改动时 Save Bar 显示“未保存”。
  const state=async()=>{const f=(await h.query('settings.footer')).find(shown);return f?textOf((await h.query('settings.footer.state')).find(shown)):'';};
  assert.equal(await state(),'');
  const cx=n.rect.x+n.rect.w/2;
  assert((await h.clickAt(cx,Math.max(intro.rect.y+2,n.rect.y+1))).ok);await h.sleep(400);
  assert.equal(await state(),'','a click in the header band does not reach the switch under it');
  assert((await h.clickAt(cx,top+(n.rect.y+n.rect.h-top)/2)).ok);await h.sleep(400);
  assert.equal(await state(),'未保存','the visible part of the switch still toggles');
  assert((await h.clickAt(cx,top+(n.rect.y+n.rect.h-top)/2)).ok);await h.sleep(400);
  report.checks.push('production window: a switch half under the header ignores clicks in the header band, toggles from its visible part');
  await nav.back();await nav.waitTitle('行为与权限');
 }
 // (c) 帮助提示展开。
 const help:any=await nav.node('settings.help');
 await h.mouseMove(help.rect.x+help.rect.w/2,help.rect.y+help.rect.h/2);
 await h.waitFor(async()=>(await h.query('settings.help.content')).some(shown)||null,5000);
 await h.sleep(400);
 await shot('c-help-tooltip',false);
 report.checks.push('help tooltip opens on hover');
 report.status='passed';
}catch(e){report.status='failed';report.error=String((e as any)?.stack??e);process.exitCode=1;await shot('failure').catch(()=>{});}
finally{await run.stop();await writeFile(join(out,`report-${theme}.json`),JSON.stringify(report,null,2));console.log(JSON.stringify({status:report.status,checks:report.checks.length,error:report.error}));}
