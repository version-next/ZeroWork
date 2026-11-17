/**
 * Shortcut text has one source (一致性审查 #9, shortcuts 包): for every entry of the shortcut router's registry
 * (`/zerowork/shortcuts`), the text shown in the Tooltip, in menus (the native menu bar, the terminal right-click
 * menu, the tab menu) and on Settings › 快捷键 is the router's current hint — which follows config.toml [keys].
 *
 * The app starts with remapped keys so a hard-coded default would show up as a mismatch:
 *   search ⌘E · close_tab ⇧⌘E · sidebar ⌥⌘B · new_tab ⇧⌘B (takes ⇧⌘B away from 命令历史, which then shows no key).
 * Also checked: every key equivalent in the menu bar belongs to a registry entry with the same text, and choosing a
 * menu bar item runs the same command as its key (新建页签 opens the session chooser).
 *
 * Usage: node e2e/shortcut_text_consistency_native.ts <zerowork binary> <output dir> [dark|light]
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {writeFile} from 'node:fs/promises';
import {resolve,join} from 'node:path';
import * as h from '../vendor/zenit/e2e/client.ts';
import {launchIsolated,settingsNav,shown,textOf} from './settings_nav.ts';

const [binaryArg,outputArg,themeArg]=process.argv.slice(2);
const theme=themeArg==='light'?'light':'dark';
assert(binaryArg&&outputArg,'usage: node e2e/shortcut_text_consistency_native.ts BINARY OUTPUT');
const binary=resolve(binaryArg),output=resolve(outputArg);
const keys='[keys]\nsearch="cmd+e"\nclose_tab="cmd+shift+e"\nsidebar="cmd+alt+b"\nnew_tab="cmd+shift+b"\n';
/** What config.toml asks for, formatted independently of the app (macOS menu order ⌃⌥⇧⌘). */
const remapped:Record<string,string>={search:'⌘E',close_tab:'⇧⌘E',sidebar:'⌥⌘B',new_tab:'⇧⌘B',command_history:''};

type Entry={id:string,kind:string,label:string,hint:string,menu:string,menu_key:boolean};
type Seen={surface:string,text:string};
const report:any={status:'running',checks:[],entries:[],captures:[]};
const app=await launchIsolated({binary,out:output,prefix:'zw-shortcut-text',theme,config:keys});
const visible=async(id:string)=>(await h.query(id)).filter(shown);
const node=async(id:string,ms=12000):Promise<any>=>h.waitFor(async()=>(await visible(id))[0]??null,ms);
const gone=async(id:string)=>h.waitFor(async()=>(await visible(id)).length===0||null,6000);
const centre=(n:any)=>[n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2] as const;
const click=async(id:string)=>{const [x,y]=centre(await node(id));assert((await h.clickAt(x,y)).ok,id);await h.sleep(150);};
const capture=async(name:string)=>{await h.sleep(200);const path=join(output,theme+'-'+name+'.png');assert((await h.screenshot(path)).ok);report.captures.push(path);};
const away={x:720,y:620};
/** Visible text only (hidden keycap slots and recording prompts are skipped), as in keybinding_v3_native. */
const visibleText=(n:any):string=>n?.visible===false?'':[typeof n?.text==='string'?n.text:n?.text?.content??'',...(n?.children??[]).map(visibleText)].join('');
/** Shown text nodes (with their rectangles) under the nodes with test id `root`. Read by id, not from `/tree`: the
 *  whole main-window tree (hidden dialogs and panels stay mounted) no longer fits the harness result buffer
 *  (256 KB; “tree too large for RESULT_BUF_SIZE” since confirm-undo's dialogs joined menus' paint facts). */
const textNodes=async(root:string):Promise<{text:string,rect:any}[]>=>{const out:any[]=[];const walk=(n:any)=>{if(!n||n.visible===false||(n.effective_opacity??1)<=0)return;const t=typeof n.text==='string'?n.text:n.text?.content;if(t&&n.rect?.w>0&&n.rect?.h>0)out.push({text:t,rect:n.rect});for(const c of n.children??[])walk(c);};for(const n of await h.query(root))walk(n);return out;};
/** The Tooltip shown for `name` (“名称” or “名称 · 快捷键”) after hovering `id`: the matching text that appears next to it,
 *  in the hint panel `<id>.tooltip`. */
async function tooltip(id:string,name:string):Promise<string>{
 const anchor=await node(id);const [x,y]=centre(anchor);
 const near=(r:any)=>Math.abs((r.y+r.h/2)-y)<anchor.rect.h/2+60&&r.x<anchor.rect.x+anchor.rect.w+260&&r.x+r.w>anchor.rect.x-260&&!(r.x===anchor.rect.x&&r.y===anchor.rect.y);
 await h.mouseMove(x,y);
 report.last_tooltip={id,name,anchor:anchor.rect};
 const found=await h.waitFor(async()=>{const hits=(await textNodes(id+'.tooltip')).filter(n=>(n.text===name||n.text.startsWith(name+' · '))&&near(n.rect)&&(n.rect.y>anchor.rect.y+anchor.rect.h-2||n.rect.y+n.rect.h<anchor.rect.y+2||n.rect.x>anchor.rect.x+anchor.rect.w-2));return hits.length?hits.map(n=>n.text):null;},4000);
 await h.mouseMove(away.x,away.y);await h.sleep(250);
 assert.equal(new Set(found).size,1,`one tooltip text for ${name}: ${JSON.stringify(found)}`);
 return found[0];
}
const shortcutOf=(text:string,name:string)=>text===name?'':text.slice(name.length+3);
/** NSMenu key equivalent → text, formatted here (not by the app) in the macOS menu order. */
const special:Record<string,string>={'\r':'↩','\t':'Tab',' ':'Space','\b':'⌫','\x1b':'Esc','\x7f':'⌦','':'↑','':'↓','':'←','':'→','':'Home','':'End','':'PageUp','':'PageDown'};
const menuText=(i:any)=>{
 if(!i.key)return '';
 const code=i.key.charCodeAt(0);
 const key=special[i.key]??(code>=0xF704&&code<=0xF70F?'F'+(code-0xF703):i.key.toUpperCase());
 return (i.control?'⌃':'')+(i.option?'⌥':'')+(i.shift?'⇧':'')+(i.command?'⌘':'')+key;
};

try{
 await h.resizeWindow(1440,900);
 const registry:Entry[]=(await h.request('POST','/zerowork/shortcuts',{})).commands;
 assert(Array.isArray(registry)&&registry.length>=40,'registry route lists every command');
 const byId=new Map(registry.map(e=>[e.id,e]));
 const seen=new Map<string,Seen[]>(registry.map(e=>[e.id,[]]));
 const record=(id:string,surface:string,text:string)=>seen.get(id)!.push({surface,text});
 for(const [id,want] of Object.entries(remapped))assert.equal(byId.get(id)!.hint,want,`registry follows [keys] for ${id}`);
 report.checks.push('the registry hints follow config.toml [keys] (remapped keys, and 命令历史 yields ⇧⌘B to 新建页签)');

 // ── 1. Menu bar (NSMenu) ──
 const bar=await h.request('POST','/zerowork/app-menu',{});
 assert(bar.ok&&Array.isArray(bar.items),'menu bar snapshot');report.menu_bar=bar;
 for(const e of registry)if(e.menu){
  const item=bar.items.find((i:any)=>i.menu===e.menu&&i.title===e.label);
  assert(item,`menu bar ${e.menu} › ${e.label}`);
  record(e.id,'menu bar',menuText(item));
 }
 for(const item of bar.items)if(item.key){
  const owner=registry.find(e=>e.menu===item.menu&&e.label===item.title);
  assert(owner,`menu bar key ${menuText(item)} on ${item.menu} › ${item.title} belongs to a registry entry`);
 }
 report.checks.push('every menu bar key equivalent belongs to a registry entry; registry entries in the menu bar are listed');

 // ── 2. Tooltips in the main window (read before a terminal opens: the harness tree of a live terminal is too
 //       large for /tree; the tab Tooltip has its own test id) ──
 const settingsTip=await tooltip('toolbar.settings','设置');record('open_settings','tooltip',shortcutOf(settingsTip,'设置'));
 // Without a terminal the tool explains why it is unavailable: “命令历史 · <reason>[ · <key>]”.
 {const tip=await tooltip('status.command-history','命令历史');const parts=tip.split(' · ').slice(1);
  const last=parts.at(-1)??'';record('command_history','tooltip',/[⌘⌃⌥⇧]|^F\d+$/.test(last)?last:'');}
 const collapseTip=await tooltip('sidebar.collapse','隐藏侧栏');record('sidebar','tooltip',shortcutOf(collapseTip,'隐藏侧栏'));
 await capture('tooltip-sidebar');
 // The remapped sidebar key collapses the sidebar; the restore button's Tooltip follows too.
 await h.key('b',{cmd:true,alt:true});await node('sidebar.restore');
 const restoreTip=await tooltip('sidebar.restore','显示主机列表');record('sidebar','tooltip (restore)',shortcutOf(restoreTip,'显示主机列表'));
 await capture('tooltip-sidebar-restore');
 await h.key('b',{cmd:true,alt:true});await node('sidebar.collapse');
 await click('workspace.empty.local');await node('terminal.surface');await h.sleep(400);
 {const [x,y]=centre(await node('tabs.tab.1'));await h.mouseMove(x,y);const tip=textOf(await node('tabs.tooltip'));await h.mouseMove(away.x,away.y);
  const ordinal=tip.split(' · ').at(-1)!;record('tab_1','tooltip',ordinal);}
 report.checks.push('Tooltips: 设置, 命令历史, 隐藏侧栏 / 显示主机列表 (⌥⌘B toggles the sidebar), the tab (第 1 个页签)');

 // ── 3. Terminal right-click menu and the tab menu ──
 const menuShortcut=async(id:string,label:string)=>{const t=textOf(await node(id));return t.startsWith(label)?t.slice(label.length):t;};
 {const [x,y]=centre(await node('terminal.surface'));assert((await h.clickAt(x,y,1,'right')).ok);await node('terminal.menu');
  await capture('terminal-menu');
  record('paste','terminal menu',await menuShortcut('terminal.menu.paste','粘贴'));
  record('search','terminal menu',await menuShortcut('terminal.menu.search','查找…'));
  // menus 包：the reason is its own text after the label (“复制 · 未选中内容”), not part of the label.
  record('copy','terminal menu',await menuShortcut('terminal.menu.copy','复制未选中内容'));
  record('clear_screen','terminal menu',await menuShortcut('terminal.menu.clear_screen','清屏'));
  if((await visible('terminal.menu.command_history')).length)record('command_history','terminal menu',await menuShortcut('terminal.menu.command_history','命令历史'));
  await h.key('escape');await gone('terminal.menu');}
 {const [x,y]=centre(await node('tabs.tab.1'));assert((await h.clickAt(x,y,1,'right')).ok);await node('context.menu.rename_tab');
  await capture('tab-menu');
  record('rename_tab','tab menu',await menuShortcut('context.menu.rename_tab','重命名…'));
  record('close_tab','tab menu',await menuShortcut('context.menu.close_session','关闭页签'));
  if((await visible('context.menu.search')).length)record('search','tab menu',await menuShortcut('context.menu.search','搜索终端'));
  await h.key('escape');await gone('context.menu.rename_tab');}
 report.checks.push('menus: terminal right-click (粘贴 / 查找 / 复制 / 清屏 / 命令历史) and the tab menu (重命名 / 关闭页签)');

 // ── 5. A menu bar item runs the same command as its key ──
 {const fired=await h.request('POST','/zerowork/app-menu',{title:byId.get('new_tab')!.label});assert(fired.ok&&fired.invoked,'menu bar 会话 › 新建页签');
  await node('session.menu');await capture('menu-bar-new-tab');await h.key('escape');await gone('session.menu');}
 report.checks.push('choosing 会话 › 新建页签 in the menu bar opens the session chooser, like its key');

 // ── 6. Settings › 快捷键 ──
 const nav=settingsNav();await nav.toCategory('keys');await capture('settings-keys');
 for(const e of registry)if(e.kind==='configurable'){const t=visibleText(await nav.node('settings.key.'+e.id));record(e.id,'settings',t);}
 report.checks.push('Settings › 快捷键 rows for all configurable commands');
 // Conflict with a fixed / system shortcut: recording names its owner and keeps the draft unchanged.
 for(const [key,mods,owner] of [['h',{cmd:true},'隐藏 ZeroWork'],['q',{cmd:true},'退出 ZeroWork'],['n',{cmd:true},'新建主机']] as const){
  await nav.click('settings.key.new_tab');await h.key(key,mods);await h.sleep(150);
  const problem=visibleText(await nav.node('settings.key.error.new_tab'));
  assert(problem.includes(`“${owner}”`),`recording ${key} names ${owner}: ${problem}`);
  assert.equal(visibleText(await nav.node('settings.key.new_tab')).replace(/[^⌘⌃⌥⇧A-Z,]/g,'').length>0,true);
  await h.key('escape');await h.sleep(150);
  assert.equal(visibleText(await nav.node('settings.key.new_tab')),byId.get('new_tab')!.hint,'the draft keeps the old key');
  report.checks.push(`recording ${key} on 新建页签 says it is used by “${owner}” and changes nothing`);
 }
 await capture('settings-keys-after');

 // ── Verdict: every surface shows the registry's text ──
 const mismatches:string[]=[];
 for(const e of registry){
  const where=seen.get(e.id)!;
  report.entries.push({id:e.id,kind:e.kind,label:e.label,hint:e.hint,seen:where});
  for(const s of where){
   const want=s.surface==='menu bar'&&!e.menu_key?'':e.hint;
   if(s.text!==want)mismatches.push(`${e.id} (${e.label}) on ${s.surface}: ${JSON.stringify(s.text)} ≠ ${JSON.stringify(want)}`);
  }
 }
 const covered=report.entries.filter((e:any)=>e.seen.length).length;
 report.coverage={entries:registry.length,shown_somewhere:covered,not_shown:report.entries.filter((e:any)=>!e.seen.length).map((e:any)=>e.id)};
 assert.deepEqual(mismatches,[],'shortcut text differs from the router:\n'+mismatches.join('\n'));
 for(const e of registry)if(e.kind==='configurable')assert(seen.get(e.id)!.some(s=>s.surface==='settings'),`${e.id} is on the settings page`);
 report.status='passed';
}catch(error){report.status='failed';report.error=String(error);await h.screenshot(join(output,'failure.png')).catch(()=>{});throw error;}
finally{
 await writeFile(join(output,'report.json'),JSON.stringify(report,null,2));
 await app.stop();
}
console.log(JSON.stringify({status:report.status,coverage:report.coverage,report:join(output,'report.json')}));
