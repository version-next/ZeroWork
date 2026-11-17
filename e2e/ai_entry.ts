/**
 * 当前 tab 的 AI 入口（PL4c 4c-2）：取代标题栏的 `toolbar.ai` 与 tab 条下的 `ai.strip`。
 *
 * 旧入口是一个开关：面板收起时点它打开，打开时再点它收起。新入口 `ai.launcher` 在面板打开时隐藏，所以
 * "再点一次关闭"改为点面板自己的收起按钮 `ai.collapse`。`aiToggleId()` 返回此刻能起到同样开关作用的 test_id：
 * 图标可见时是 `ai.launcher`，面板打开时是 `ai.collapse`。
 */
import * as h from '../vendor/zenit/e2e/client.ts';

const shown=(n:any)=>n&&!n.hidden&&n.visible!==false&&(n.effective_opacity??1)>0&&n.rect?.w>0&&n.rect?.h>0;

export async function aiToggleId(ms=12000):Promise<string>{
 return h.waitFor(async()=>{
  if((await h.query('ai.launcher')).some(shown))return 'ai.launcher';
  if((await h.query('ai.panel')).some(shown))return 'ai.collapse';
  return null;
 },ms);
}

/** 只打开（面板已开时什么也不做）。 */
export async function aiOpenId(ms=12000):Promise<string|null>{
 const id=await aiToggleId(ms);
 return id==='ai.launcher'?id:null;
}
