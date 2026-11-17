/**
 * 原生组件默认外观对照采集（修复包 H-tokens：Switch / Checkbox / Radio / Modal 遮罩回到 zenit 默认）。
 *
 * 只截图、不做断言以外的产品改动：独立数据目录与 RPC 目录（settings_nav.launchIsolated），
 * `[updates] auto_check=false`，后台 + 隔离指针模式。须在断网沙箱里运行：
 *   zw-nonet.sh node e2e/h_tokens_capture.ts <zerowork binary (test-mode)> <outDir> <light|dark|sauber>
 * 产出（<theme>-<screen>.png）：
 *   ssh-reconnect-on     设置 › SSH 与网络 › 断线重连（默认：自动重连开启，依赖项可用）
 *   ssh-reconnect-off    同页关闭“自动重连”后（开关关闭态 + 依赖开关的禁用态）
 *   appearance-theme     设置 › 外观与主题 › 主题（应用图标单选、材质开关）
 *   appearance-terminal  设置 › 外观与主题 › 终端与工作区（开关）
 *   confirm-modal        未保存改动时 Cmd+W 弹出的确认对话框（原生 Modal 遮罩）
 * 修复前 / 修复后各用对应构建跑一遍，文件名一一对应。退出前放弃改动，不写回配置。
 */
import assert from 'node:assert/strict';
import {join,resolve} from 'node:path';
import {rm,writeFile} from 'node:fs/promises';
import * as h from '../vendor/zenit/e2e/client.ts';
import {launchIsolated,settingsNav,shown} from './settings_nav.ts';

const [binaryArg,outArg,theme='light']=process.argv.slice(2);
if(!binaryArg||!outArg||!['light','dark','sauber'].includes(theme))throw new Error('usage: h_tokens_capture.ts <binary> <outDir> <light|dark|sauber>');
const out=resolve(outArg);
const run=await launchIsolated({binary:resolve(binaryArg),out,prefix:'zw-h-tokens',theme,logName:`app-${theme}.log`});
const nav=settingsNav();
let win:string|undefined;
const shot=async(name:string)=>{await h.mouseMove(2,2).catch(()=>{});await h.sleep(400);assert((await h.screenshot(join(out,`${theme}-${name}.png`),win)).ok,name);};
try{
 await h.resizeWindow(1440,900);
 await nav.open();
 win=(await h.windows()).windows.find(w=>w.bound&&!w.closing)?.window_id;
 await nav.toSub('ssh','reconnect');await nav.reveal('settings.field.auto_reconnect');await shot('ssh-reconnect-on');
 await nav.click('settings.field.auto_reconnect');await shot('ssh-reconnect-off');
 // The reconnect toggle above left an unsaved change on this subpage: leaving it asks first (H-save,
 // native Modal). Capture the dialog, discard, then continue on a clean draft.
 await nav.click('settings.nav.appearance');
 await nav.node('settings.confirmation');await shot('confirm-modal');
 await nav.click('settings.confirmation.discard');
 await nav.gone('settings.confirmation');
 await nav.toSub('appearance','theme');await nav.reveal('settings.appearance.app_icon');await shot('appearance-theme');
 await nav.toSub('appearance','terminal');await shot('appearance-terminal');
 // Nothing unsaved now: closing does not ask.
 await h.key('w',{cmd:true});
 await nav.gone('settings.panel');
 console.log(JSON.stringify({status:'passed',theme,out}));
 await writeFile(join(out,'report.json'),JSON.stringify({status:'captured',theme},null,1));
}catch(e){
 console.log(JSON.stringify({status:'failed',theme,error:String(e)}));process.exitCode=1;
 await writeFile(join(out,'report.json'),JSON.stringify({status:'failed',theme,error:String(e)},null,1)).catch(()=>{});
}finally{
 try{for(const id of ['settings.confirmation.discard'])if((await h.query(id)).some(shown))await h.clickTestId(id);}catch{}
 await run.stop();
 await rm(run.iso,{recursive:true,force:true});
}
