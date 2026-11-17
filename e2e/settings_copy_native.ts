/**
 * settings-copy: 字体与排版子页的紧凑实时预览、设置里的字节标签（chunk_kb / ring_mb 按 shared/base/format）。
 * - 外观 › 字体与排版：`settings.font.live_preview` 在本子页可见；改字号、行高后，预览命令行的高度随草稿实时变化。
 * - 文件传输 / 数据与日志的总览摘要写真实大小（“16 × 64 KiB”、“缓冲 64 MiB”），输入框后缀写 IEC 单位（“KiB”、“MiB”，units-iec）。
 * 亮、暗各截一组图。
 * Usage: node e2e/settings_copy_native.ts <zerowork binary> <output dir>
 */
import './regression/build_mode_guard.mjs';
import assert from 'node:assert/strict';
import {resolve,join} from 'node:path';
import {writeFile} from 'node:fs/promises';
import * as h from '../vendor/zenit/e2e/client.ts';
import {launchIsolated,settingsNav,textOf} from './settings_nav.ts';

const [binaryArg,outArg]=process.argv.slice(2);
assert(binaryArg&&outArg,'usage: node e2e/settings_copy_native.ts <binary> <out>');
const binary=resolve(binaryArg),out=resolve(outArg);
const report:any={status:'running',runs:[]};
try{
 for(const theme of ['light','dark']){
  const app=await launchIsolated({binary,out,prefix:'zw-settings-copy',theme,config:'[ui]\nfont_size=14\nline_height=1.5\n',logName:`${theme}.log`});
  const rec:any={theme,captures:[]};report.runs.push(rec);
  const nav=settingsNav();
  const capture=async(name:string)=>{await h.mouseMove(4,4);await h.sleep(350);const path=join(out,`${theme}-${name}.png`);assert((await h.screenshot(path)).ok,name);rec.captures.push(path);};
  try{
   await h.resizeWindow(1280,860);
   await nav.open();
   // ── 字节标签 ──
   await nav.toCategory('transfer');
   const engine=textOf(await nav.node('settings.overview.transfer.engine'));
   rec.engine_summary=engine;assert(engine.includes('16 × 64 KiB'),engine);
   const isolation=textOf(await nav.node('settings.overview.transfer.connection'));
   rec.isolation_summary=isolation;assert(isolation.includes('共享通道 2 MiB/s'),isolation);
   await nav.toSub('transfer','engine');
   const chunk=textOf(await nav.reveal('settings.field.chunk_kb'));
   rec.chunk_unit=chunk;assert(chunk.includes('KiB')&&!chunk.includes('× 1024'),chunk);
   await capture('transfer-engine');
   await nav.toCategory('data');
   const history=textOf(await nav.node('settings.overview.data.history'));
   rec.history_summary=history;assert(history.includes('缓冲 64 MiB'),history);
   await nav.toSub('data','history');
   const ring=textOf(await nav.reveal('settings.field.ring_mb'));
   rec.ring_unit=ring;assert(ring.includes('MiB')&&!ring.includes('× 1024'),ring);
   await capture('data-history');
   // ── 字体与排版：紧凑实时预览 ──
   await nav.toSub('appearance','font');
   await nav.reveal('settings.font.live_preview');
   const command=async()=>nav.node('settings.font.live_preview.command');
   const before=(await command()).rect.h;
   rec.command_height_before=before;
   assert.equal(textOf(await command()),'ssh prod-web-01');
   await capture('font-live-preview');
   await nav.edit('settings.field.font_size','22');await h.key('return');
   const grown=await h.waitFor(async()=>{const n=await command();return n.rect.h>before+4?n.rect.h:null;},5000);
   rec.command_height_after_font_size_22=grown;
   await nav.edit('settings.field.line_height','2.0');await h.key('return');
   await nav.reveal('settings.font.live_preview');
   await capture('font-live-preview-22pt');
   // 草稿没保存：预览只跟草稿，不要求保存。
   assert(await nav.dirty(),'font edits stay a draft');
   rec.status='passed';
  }catch(e){rec.status='failed';rec.error=String(e);await capture('failure').catch(()=>{});throw e;}
  finally{await app.stop();}
 }
 report.status='passed';
}catch(e){report.status='failed';report.error=String(e);process.exitCode=1;}
finally{await writeFile(join(out,'report.json'),JSON.stringify(report,null,1));console.log(JSON.stringify(report,null,1));}
