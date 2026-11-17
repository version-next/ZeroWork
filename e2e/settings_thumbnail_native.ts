/**
 * set-modals：设置窗口里“外观与主题 › 背景图片”的缩略图（`settings.materials.preview.open`）与行内材质预览
 * （`settings.background.preview`）要真的画出背景图片的像素。
 * 根因：背景纹理原先进主窗口自己的纹理表（`app.renderer.image_renderer.loadTexture`），设置窗口是另一个原生窗口、
 * 另一套渲染器，同一个 id 在那里解析不到——两处都是空白（`ZeroWork-evidence/set-appearance/review/*-theme-3-background.png`）。
 * 修复后纹理进进程共享的纹理表（`App.sharedImageStore`）。
 * 断言：缩略图内部 ≥ 40% 的像素接近棋盘格的黄 / 蓝两色；行内预览的亮度标准差 > 4（不是一块均匀底色）。
 * Usage: node e2e/settings_thumbnail_native.ts <zerowork binary (-Dtest-mode=true)> <output dir>
 * 隔离运行（临时 ZEROWORK_DATA_DIR，[updates] auto_check=false，后台 / 隔离指针）；结束时停止自己启动的应用。
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {resolve,join} from 'node:path';
import {writeFile,mkdtemp,realpath} from 'node:fs/promises';
import {execFileSync} from 'node:child_process';
import {deflateSync} from 'node:zlib';
import * as h from '../vendor/zenit/e2e/client.ts';
import {launchIsolated,settingsNav} from './settings_nav.ts';

const [binaryArg,outArg]=process.argv.slice(2);
assert(binaryArg&&outArg,'usage: node e2e/settings_thumbnail_native.ts <binary> <out>');
const binary=resolve(binaryArg),out=resolve(outArg);

function crc32(buf:Buffer){let c=~0;for(const b of buf){c^=b;for(let k=0;k<8;k++)c=c&1?(c>>>1)^0xedb88320:c>>>1;}return ~c>>>0;}
function chunk(type:string,data:Buffer){const len=Buffer.alloc(4);len.writeUInt32BE(data.length);const body=Buffer.concat([Buffer.from(type,'ascii'),data]);const crc=Buffer.alloc(4);crc.writeUInt32BE(crc32(body));return Buffer.concat([len,body,crc]);}
function checkerPng(){const width=240,height=160,raw=Buffer.alloc(height*(1+width*4));for(let y=0;y<height;y++)for(let x=0;x<width;x++){const color=((x/20|0)+(y/20|0))%2?[242,192,65]:[71,129,232];raw.set([...color,255],y*(1+width*4)+1+x*4);}const header=Buffer.alloc(13);header.writeUInt32BE(width);header.writeUInt32BE(height,4);header[8]=8;header[9]=6;return Buffer.concat([Buffer.from('89504e470d0a1a0a','hex'),chunk('IHDR',header),chunk('IDAT',deflateSync(raw)),chunk('IEND',Buffer.alloc(0))]);}

const dir=await realpath(await mkdtemp('/private/tmp/zw-thumbnail-'));
const image=join(dir,'checker.png');await writeFile(image,checkerPng());
const config=`[ui.materials]\nblur_px=0\n[ui.materials.background]\nenabled=true\npath=${JSON.stringify(image)}\nfit="tile"\ntransparency=30\n`;
const report:any={binary,status:'running',runs:[]};
const W=1280,H=860;
try{
 for(const theme of ['light','dark']){
  const app=await launchIsolated({binary,out,prefix:'zw-thumbnail',theme,config,logName:`${theme}.log`});
  const run:any={theme,status:'running',checks:[]};report.runs.push(run);
  const nav=settingsNav();
  try{
   await h.resizeWindow(W,H);
   for(let i=0;i<4&&!(await nav.visible('settings.panel'));i++){const n=await nav.node('toolbar.settings');assert((await h.clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok);await nav.node('settings.panel',3000).catch(()=>null);}
   await nav.toSub('appearance','theme');
   const thumb=await nav.reveal('settings.materials.preview.open');
   const preview=await nav.reveal('settings.background.preview');
   const thumbAgain=(await h.query('settings.materials.preview.open')).find((n:any)=>n.rect?.w>0)??thumb;
   await h.mouseMove(4,4);await h.pointerLeave();await h.sleep(600);
   const shot=join(out,`${theme}-thumbnail.png`);assert((await h.screenshot(shot)).ok,'screenshot');
   const result=JSON.parse(execFileSync('python3',['-I',resolve('e2e/settings_thumbnail_pixels.py'),shot,String(W),String(H),JSON.stringify(thumbAgain.rect),JSON.stringify(preview.rect)],{encoding:'utf8'}));
   run.pixels=result;
   assert(result.thumbnail.checker_ratio>=0.4,`thumbnail shows the checker (ratio ${result.thumbnail.checker_ratio})`);
   assert(result.preview.spread>4,`inline material preview is not a flat fill (spread ${result.preview.spread})`);
   run.checks.push('thumbnail draws the wallpaper texture in the preferences window','inline material preview draws the wallpaper texture');
   run.status='passed';
  }catch(e){run.status='failed';run.error=String(e);await h.screenshot(join(out,`${theme}-failure.png`)).catch(()=>{});throw e;}
  finally{await app.stop();}
 }
 report.status='passed';
}catch(e){report.status='failed';report.error=String(e);process.exitCode=1;}
finally{await writeFile(join(out,'report.json'),JSON.stringify(report,null,1));console.log(JSON.stringify(report,null,1));}
