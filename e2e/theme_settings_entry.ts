/** title-click: the theme is not a title bar tool any more (the 主题 button and its quick picker were removed).
 * Every theme entry opens 设置 › 外观与主题: the native menu bar item “显示 › 外观…” (invoked through AppKit by the
 * harness-only `/zerowork/app-menu` route) and `@theme`; the tab menu has no theme item (bugfix-4). These helpers drive that real
 * entry for scripts that used to pick a theme from `status.connection.theme` / `status.theme`.
 * `h` is the zenit harness client module (`import * as h from …/client.ts`). */
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';

const shown=(n:any)=>n?.rect?.w>0&&n.rect.h>0&&n.visible!==false&&n.hidden!==true&&(n.effective_opacity??1)>0.01;
const visible=(h:any,id:string,ms=10000)=>h.waitFor(async()=>(await h.query(id)).find(shown)??null,ms);

/** 菜单栏“显示 › 外观…” → 设置 › 外观与主题 › 主题 is on screen. */
export async function openAppearance(h:any):Promise<any>{
 const result=await h.request('POST','/zerowork/app-menu',{invoke:true});
 assert(result?.ok&&result.invoked,'menu bar 显示 › 外观… is invoked: '+JSON.stringify(result));
 await visible(h,'settings.window');
 return await visible(h,'settings.appearance.themes');
}

/** Scrolls the horizontal theme strip until `settings.theme.<id>` lies inside it. */
async function revealCard(h:any,theme:string):Promise<any>{
 const id=`settings.theme.${theme}`;
 for(const direction of [-1,1])for(let step=0;step<24;step++){
  const strip=await visible(h,'settings.theme.strip');const card=(await h.query(id)).find(shown);
  if(card&&card.rect.x>=strip.rect.x-0.5&&card.rect.x+card.rect.w<=strip.rect.x+strip.rect.w+0.5)return card;
  await h.scrollAt(strip.rect.x+strip.rect.w/2,strip.rect.y+strip.rect.h/2,direction*-240,0);await h.sleep(120);
 }
 throw new Error(id+' never scrolled into the theme strip');
}

/** Picks `theme` in 设置 › 外观与主题, saves, waits until config.toml has it, closes the settings window. */
export async function chooseTheme(h:any,theme:string,configPath:string):Promise<void>{
 await openAppearance(h);
 const card=await revealCard(h,theme);
 assert((await h.clickAt(card.rect.x+card.rect.w/2,card.rect.y+card.rect.h/2)).ok);
 const save=(await h.query('settings.save')).find(shown);
 if(save&&save.focusable!==false)assert((await h.clickTestId('settings.save')).ok);
 await h.waitFor(async()=>new RegExp(`theme\\s*=\\s*"${theme}"`).test(await readFile(configPath,'utf8'))||null,10000);
 await closeSettings(h);
}

export async function closeSettings(h:any):Promise<void>{
 if((await h.query('settings.window')).some(shown))await h.key('escape');
 await h.waitFor(async()=>!(await h.query('settings.window')).some(shown)||null,8000);
}
