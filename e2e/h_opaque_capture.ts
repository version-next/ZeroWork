/**
 * H-opaque-popups 验收对照图（zenit 原生浮层面板在 ZeroWork 里不得半透明）。一次性采集脚本，
 * 隔离启动与设置导航照 `settings_nav.ts`（`launchIsolated`：临时数据目录、关闭自动检查更新）。
 *
 * 每个主题采集：
 *   (1) main         主窗口（本地终端已打开）。`--material` 时开着平铺背景图片 + 全局透明度 70，
 *                    用来证明主窗口自己的半透明表面（透出壁纸）没有被改坏；
 *   (2) main-menu    主窗口里的原生 `W.Menu`（窗格标题栏“…”，`pane.menu`）；
 *   (3) select       设置 › SSH 与网络 › 连接 里打开的原生 `W.Select` 下拉（“默认终端类型”）；
 *   (4) modal        设置里“未保存的设置”确认框（原生 Modal，流程同 `h_save_capture.ts` 的 (e)）。
 * 每张图同时把浮层节点的矩形写进 report，便于在图上定位面板。
 *
 * Usage: node e2e/h_opaque_capture.ts <zerowork binary (test-mode)> <out dir> [light|dark] [--material]
 */
import assert from 'node:assert/strict';
import {join,resolve} from 'node:path';
import {writeFile,mkdtemp,realpath} from 'node:fs/promises';
import {deflateSync} from 'node:zlib';
import * as h from '../vendor/zenit/e2e/client.ts';
import {launchIsolated,settingsNav,shown} from './settings_nav.ts';

const args=process.argv.slice(2);
const material=args.includes('--material');
const [binaryArg,outArg,theme='light']=args.filter(a=>a!=='--material');
if(!binaryArg||!outArg)throw new Error('usage: h_opaque_capture.ts <binary> <out> [light|dark] [--material]');
const out=resolve(outArg);
const tag=`${theme}${material?'-material':''}`;

function crc32(bytes:Buffer){let c=~0;for(const b of bytes){c^=b;for(let k=0;k<8;k++)c=(c>>>1)^(0xedb88320&-(c&1));}return ~c>>>0;}
function chunk(kind:string,bytes:Buffer){const type=Buffer.from(kind),size=Buffer.alloc(4),crc=Buffer.alloc(4);size.writeUInt32BE(bytes.length);crc.writeUInt32BE(crc32(Buffer.concat([type,bytes])));return Buffer.concat([size,type,bytes,crc]);}
/** 蓝 / 黄棋盘格：面板若半透明，格子会从面板底下透出来。 */
function checkerPng(){
 const width=240,height=160,raw=Buffer.alloc(height*(1+width*4));
 for(let y=0;y<height;y++)for(let x=0;x<width;x++){const color=((x/20|0)+(y/20|0))%2?[242,192,65]:[71,129,232];raw.set([...color,255],y*(1+width*4)+1+x*4);}
 const header=Buffer.alloc(13);header.writeUInt32BE(width);header.writeUInt32BE(height,4);header[8]=8;header[9]=6;
 return Buffer.concat([Buffer.from('89504e470d0a1a0a','hex'),chunk('IHDR',header),chunk('IDAT',deflateSync(raw)),chunk('IEND',Buffer.alloc(0))]);
}

let config='';
if(material){
 const dir=await realpath(await mkdtemp('/private/tmp/zw-h-opaque-wallpaper-'));
 const image=join(dir,'checker.png');await writeFile(image,checkerPng());
 config=`[ui.materials]\nblur_px=0\n[ui.materials.background]\nenabled=true\npath=${JSON.stringify(image)}\nfit="tile"\ntransparency=70\n`;
}
const run=await launchIsolated({binary:resolve(binaryArg),out,prefix:'zw-h-opaque-capture',theme,config,logName:`app-${tag}.log`});
const nav=settingsNav();
const report:any={status:'running',theme,material,shots:[] as string[],rects:{} as Record<string,unknown>,checks:[] as string[]};
const node=async(id:string,ms=12000):Promise<any>=>h.waitFor(async()=>(await h.query(id)).find(shown)??null,ms);
const gone=async(id:string,ms=6000)=>h.waitFor(async()=>(await h.query(id)).some(shown)?null:true,ms);
const click=async(id:string)=>{const n=await node(id);assert((await h.clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok,id);await h.sleep(200);};
const ids=async()=>(await h.windows()).windows.filter(w=>w.bound&&!w.closing).map(w=>w.window_id);
const shot=async(name:string,panelId:string|null,win?:string,park=true)=>{
 if(park){await h.mouseMove(2,2).catch(()=>{});}
 await h.sleep(500);
 if(panelId){const p=await node(panelId);report.rects[name]={test_id:panelId,rect:p.rect};}
 const path=join(out,`${tag}-${name}.png`);
 assert((await h.screenshot(path,win)).ok,name);report.shots.push(path);
};

try{
 await h.resizeWindow(1440,900);
 const main=(await ids())[0];
 // (1) 主窗口：打开一个本地终端，让窗格、标题栏和侧栏都在。
 // 开着背景图片时首帧要等纹理加载，过早的点击可能落空：重试几次。
 for(let i=0;i<4&&!(await h.query('terminal.surface')).some(shown);i++){await h.sleep(600);await click('workspace.empty.local');await node('terminal.surface',4000).catch(()=>null);}
 await node('terminal.surface');await h.sleep(800);
 await shot('main',null,main);
 // (2) 原生 Menu：窗格标题栏“…”。
 await click('pane.more');await node('pane.menu');
 await shot('main-menu','pane.menu',main,false);
 await h.key('escape');await gone('pane.menu');
 report.checks.push('main window: local pane open; native pane Menu captured, Esc closes');
 // (3) 设置窗口里的原生 Select 下拉。
 const before=new Set(await ids());
 await nav.open();
 const settingsWin=(await ids()).find(id=>!before.has(id));
 await nav.toSub('ssh','connection');
 await nav.click('settings.field.term');await node('settings.term.option.custom');
 await shot('select','settings.term.option.custom',settingsWin,false);
 await h.key('escape');await gone('settings.term.option.custom');
 report.checks.push('settings: native Select panel (默认终端类型) captured, Esc closes');
 // (4) 带着改动切页：“未保存的设置”原生 Modal。
 await nav.edit('settings.field.keepalive_sec','45');
 await h.key('tab');
 await h.waitFor(async()=>(await h.query('settings.footer')).some(shown)||null,5000);
 await nav.click('settings.nav.notifications');
 await node('settings.confirmation',6000);
 await shot('modal','settings.confirmation',settingsWin);
 await nav.click('settings.confirmation.cancel');await gone('settings.confirmation');
 await nav.click('settings.revert');
 await h.waitFor(async()=>(await h.query('settings.footer')).some(shown)?null:true,5000);
 report.checks.push('settings: unsaved-changes native Modal captured, cancel + revert leave the page clean');
 report.status='passed';
}catch(e){report.status='failed';report.error=String((e as any)?.stack??e);process.exitCode=1;await shot('failure',null).catch(()=>{});}
finally{await run.stop();await writeFile(join(out,`report-${tag}.json`),JSON.stringify(report,null,2));console.log(JSON.stringify({status:report.status,shots:report.shots.length,error:report.error}));}
