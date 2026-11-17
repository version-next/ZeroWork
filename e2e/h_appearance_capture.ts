/**
 * Review capture for human feedback round 1 on the 外观与主题 page (P3 3e appearance package; items 2, 6, 9, 11):
 * the three subpages scrolled to each pane, with a tiled wallpaper selected so the background row shows its
 * thumbnail and inline material preview, plus the native controls opened (fit Select, alignment Popover,
 * font family Select, cursor Tabs) and a field “?” tooltip. Light and dark.
 * Usage: node e2e/h_appearance_capture.ts <zerowork binary> <output dir>
 * Runs isolated (temp ZEROWORK_DATA_DIR, [updates] auto_check=false, background / isolated pointer).
 */
import assert from 'node:assert/strict';
import {resolve,join} from 'node:path';
import {writeFile,mkdtemp,realpath} from 'node:fs/promises';
import {deflateSync} from 'node:zlib';
import * as h from '../vendor/zenit/e2e/client.ts';
import {launchIsolated,settingsNav} from './settings_nav.ts';

const [binaryArg,outArg]=process.argv.slice(2);
assert(binaryArg&&outArg,'usage: node e2e/h_appearance_capture.ts <binary> <out>');
const binary=resolve(binaryArg),out=resolve(outArg);

function crc32(buf:Buffer){let c=~0;for(const b of buf){c^=b;for(let k=0;k<8;k++)c=c&1?(c>>>1)^0xedb88320:c>>>1;}return ~c>>>0;}
function chunk(type:string,data:Buffer){const len=Buffer.alloc(4);len.writeUInt32BE(data.length);const body=Buffer.concat([Buffer.from(type,'ascii'),data]);const crc=Buffer.alloc(4);crc.writeUInt32BE(crc32(body));return Buffer.concat([len,body,crc]);}
function checkerPng(){const width=240,height=160,raw=Buffer.alloc(height*(1+width*4));for(let y=0;y<height;y++)for(let x=0;x<width;x++){const color=((x/20|0)+(y/20|0))%2?[242,192,65]:[71,129,232];raw.set([...color,255],y*(1+width*4)+1+x*4);}const header=Buffer.alloc(13);header.writeUInt32BE(width);header.writeUInt32BE(height,4);header[8]=8;header[9]=6;return Buffer.concat([Buffer.from('89504e470d0a1a0a','hex'),chunk('IHDR',header),chunk('IDAT',deflateSync(raw)),chunk('IEND',Buffer.alloc(0))]);}

const dir=await realpath(await mkdtemp('/private/tmp/zw-appearance-review-'));
const image=join(dir,'checker.png');await writeFile(image,checkerPng());
const config=`[ui.materials]\nblur_px=0\n[ui.materials.background]\nenabled=true\npath=${JSON.stringify(image)}\nfit="tile"\ntransparency=30\n`;
const report:any={runs:[]};
for(const theme of ['light','dark']){
 const app=await launchIsolated({binary,out,prefix:'zw-h-appearance',theme,config,logName:`${theme}.log`});
 const rec:any={theme,captures:[]};report.runs.push(rec);
 const nav=settingsNav();
 const capture=async(name:string)=>{await h.sleep(300);const path=join(out,`${theme}-${name}.png`);assert((await h.screenshot(path)).ok,name);rec.captures.push(path);};
 const center=async(id:string)=>{const n=await nav.node(id);return [n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2];};
 const away=async()=>{await h.mouseMove(4,4);await h.pointerLeave();await h.sleep(200);};
 const escape=async()=>{await h.key('escape');await h.sleep(200);};
 try{
  await h.resizeWindow(1280,860);
  // The first toolbar click can land before the wallpaper layers settle; retry opening the window (as switch_initial_state_native).
  const tap=async(target:string)=>{const n=await nav.node(target);assert((await h.clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok,target);};
  for(let i=0;i<4&&!(await nav.visible('settings.panel'));i++){await tap('toolbar.settings');await nav.node('settings.panel',3000).catch(()=>null);}
  await nav.toSub('appearance','theme');await nav.node('settings.theme.strip');await away();await capture('theme-1-themes');
  await nav.reveal('settings.field.icon_background');await capture('theme-2-app-icon');
  await nav.reveal('settings.background.identity');await capture('theme-3-background');
  await nav.reveal('settings.field.transparency');await capture('theme-4-sliders');
  await nav.click('settings.field.fit');await nav.node('settings.option.fit.fit');await capture('theme-5-fit-select');await escape();
  await nav.click('settings.field.alignment');await nav.node('settings.alignment.居中');await capture('theme-6-alignment');await escape();
  const [tx,ty]=await center('settings.appearance.help.transparency');await h.mouseMove(tx,ty);await h.sleep(750);await nav.node('settings.appearance.help.transparency.tooltip');await capture('theme-7-help-tooltip');await away();
  await nav.reveal('settings.background.preview');await capture('theme-8-inline-preview');
  await nav.reveal('settings.font.preview');await capture('theme-9-font-preview');
  await nav.toSub('appearance','font');await nav.node('settings.field.font_size');await away();await capture('font-1');
  await nav.click('settings.field.font_family');await nav.node('settings.font.options');await capture('font-2-family-select');await escape();
  await nav.toSub('appearance','terminal');await nav.node('settings.toggle.command_info');await away();await capture('terminal-1');
  await nav.reveal('settings.appearance.mini_preview');await capture('terminal-2-mini-preview');
  rec.status='captured';
 }catch(e){rec.status='failed';rec.error=String(e);await capture('failure').catch(()=>{});throw e;}
 finally{await app.stop();}
}
await writeFile(join(out,'report.json'),JSON.stringify(report,null,1));
console.log(JSON.stringify(report,null,1));
