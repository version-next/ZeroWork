/**
 * Shared navigation for the two-level Settings window (category overview →
 * subpage, Back / Forward, search, floating Save Bar), distilled from
 * `settings_revamp_native.ts`. The page map mirrors
 * `src/features/settings/view/settings_subpages.zig`; keep them in sync.
 *
 * Usage:
 *   import {settingsNav} from './settings_nav.ts';
 *   const nav=settingsNav();            // default 12 s waits
 *   await nav.open();                   // toolbar.settings → settings.panel
 *   await nav.toPane('settings.ssh.connection');
 *   await nav.toField('keepalive_sec'); // subpage that edits ssh.keepalive_sec
 *
 * This module does not start the app; scripts keep their own isolated
 * ZEROWORK_DATA_DIR / RPC dir setup.
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import * as h from '../vendor/zenit/e2e/client.ts';

/** [category slug, overview title, [subpage slug, subpage title, pane ids, setting keys][]] */
export type Sub=[string,string,string[],string[]];
export const CATEGORIES:[string,string,Sub[]][]=[
 ['appearance','外观与主题',[
  ['theme','主题',['settings.appearance.themes','settings.appearance.app_icon','settings.appearance.materials','settings.appearance.preview'],['theme','icon_background','blur_px','enabled','path','source','order','interval_minutes','fit','alignment_x','alignment_y','transparency']],
  ['font','字体与排版',['settings.appearance.font'],['font_family','font_size','font_weight','line_height','cursor_style']],
  ['terminal','终端与工作区',['settings.appearance.aids'],['scrollback_limit','timestamp_gutter','sidebar_collapsed','input_line_highlight','command_info']],
 ]],
 ['ssh','SSH 与网络',[
  ['connection','连接',['settings.ssh.connection'],['keepalive_sec','connect_timeout_sec','term','compression','auto_shell_integration']],
  ['socks','SOCKS5 转发',['settings.ssh.socks'],['socks_port','socks_bind']],
  ['reconnect','断线重连',['settings.ssh.reconnect'],['auto_reconnect','reconnect_max','reconnect_backoff','buffer_input']],
  ['authentication','双因素认证',['settings.ssh.authentication'],['otp_modal','totp_autofill']],
 ]],
 ['transfer','文件传输',[
  ['connection','连接隔离',['settings.transfer.connection'],['dedicated_connection','shared_pacing_kbps']],
  ['engine','SFTP 引擎',['settings.transfer.engine'],['window_chunks','chunk_kb','max_tasks','resume','verify_md5']],
  ['defaults','默认行为',['settings.transfer.defaults'],['download_dir','conflict_policy']],
 ]],
 ['ai','AI 辅助',[
  ['providers','服务提供方',['settings.ai.providers'],[]],
  ['behavior','行为与权限',['settings.ai.permissions','settings.ai.execution','settings.ai.conversation','settings.ai.children','settings.ai.context','settings.ai.attachments','settings.ai.behavior'],['permission_mode','execution_mode','session_retention','follow_up_mode','child_context_mode','child_reuse_policy','redact_ip','default_provider','step_display','error_hint']],
  ['extensions','技能与 MCP',['settings.ai.extensions'],[]],
 ]],
 ['notifications','通知',[
  ['events','事件提醒',['settings.notifications.events'],['transfer_done','reconnect','ai_ready','bell']],
  ['attention','注意标记与勿扰',['settings.notifications.attention'],['tab_dot','quiet_hours']],
 ]],
 ['data','数据与日志',[
  ['location','位置与凭据',['settings.data.location'],[]],
  ['history','会话记录',['settings.data.history'],['ring_mb','checkpoint_sec','retention_days','export_format']],
  ['actions','导出与清理',['settings.data.actions'],[]],
 ]],
];
/** Categories without an overview render all their panes directly. */
export const DIRECT:[string,string,string[]][]=[['keys','快捷键',['settings.keys.tabs','settings.keys.terminal']],['plugins','协议插件',[]],['updates','关于与更新',['settings.updates.version','settings.updates.preferences']]];

export const shown=(n:any)=>!!n&&n.visible!==false&&n.rect?.w>0&&n.rect?.h>0&&(n.effective_opacity??1)>0;
export const textOf=(n:any):string=>[typeof n?.text==='string'?n.text:n?.text?.content??'',...(n?.children??[]).map(textOf)].join('');

/** Where a pane (section test id) lives: [category, subpage|null]. */
export function locatePane(pane:string):[string,string|null]{
 for(const [cat,,subs] of CATEGORIES) for(const [sub,,panes] of subs) if(panes.some(p=>pane===p||pane.startsWith(p+'.')))return [cat,sub];
 for(const [cat,,panes] of DIRECT) if(panes.some(p=>pane===p||pane.startsWith(p+'.'))||pane.startsWith(`settings.${cat}.`))return [cat,null];
 throw new Error(`settings_nav: unknown pane ${pane}`);
}
/** The subpage that edits `<section>.<key>` (field ids use the bare key). */
export function locateKey(key:string,category?:string):[string,string]{
 for(const [cat,,subs] of CATEGORIES){if(category&&cat!==category)continue;for(const [sub,,,keys] of subs) if(keys.includes(key))return [cat,sub];}
 throw new Error(`settings_nav: unknown setting key ${key}`);
}
export function titleOf(cat:string,sub:string|null):string{
 const c=CATEGORIES.find(([s])=>s===cat);if(c){if(sub===null)return c[1];const s=c[2].find(([x])=>x===sub);if(s)return s[1];}
 const d=DIRECT.find(([s])=>s===cat);if(d&&sub===null)return d[1];
 throw new Error(`settings_nav: unknown page ${cat}/${sub}`);
}

/**
 * Start the app in an isolated data dir (mkdtemp) with update checks off,
 * in background / isolated-pointer mode. `config` is appended to the
 * generated config.toml (must not repeat the [meta]/[updates] tables).
 */
export async function launchIsolated(o:{binary:string,out:string,prefix:string,theme?:string,config?:string,logName?:string,env?:Record<string,string>,args?:string[]}){
 const {mkdtemp,mkdir,writeFile,realpath,open}=await import('node:fs/promises');
 const {spawn}=await import('node:child_process');
 const {join}=await import('node:path');
 const iso=await realpath(await mkdtemp(`/private/tmp/${o.prefix}-`)),rpc=join(iso,'rpc'),data=join(iso,'data');
 await mkdir(rpc);await mkdir(data);await mkdir(o.out,{recursive:true});
 const ui=o.theme?`[ui]\ntheme="${o.theme}"\n`:'';
 await writeFile(join(data,'config.toml'),`[meta]\nconfig_revision=1\n[updates]\nauto_check=false\n${ui}${o.config??''}`,{mode:0o600});
 process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
 const log=await open(join(o.out,o.logName??'app.log'),'w');
 const app=spawn(o.binary,o.args??[],{env:{...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1',ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',OPENAI_API_KEY:'',ANTHROPIC_API_KEY:'',...(o.env??{})},stdio:['ignore',log.fd,log.fd]});
 const ended=new Promise<void>(r=>app.once('close',()=>r()));
 const stop=async()=>{if(app.exitCode===null&&app.signalCode===null)app.kill('SIGTERM');await ended;await log.close().catch(()=>{});};
 try{await h.waitForServerReady();}catch(e){await stop();throw e;}
 return {iso,rpc,data,config:join(data,'config.toml'),app,stop};
}

/** Click the descendant of `id` whose own text is `label` (e.g. a Tabs item without its own test id). */
export async function clickLabel(id:string,label:string){
 const find=(n:any):any=>{if((typeof n?.text==='string'?n.text:'')===label&&shown(n))return n;for(const c of n?.children??[]){const f=find(c);if(f)return f;}return null;};
 const n=await h.waitFor(async()=>{for(const root of await h.query(id)){const f=find(root);if(f)return f;}return null;},8000);
 assert((await h.clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok,`${id} › ${label}`);await h.sleep(200);
}

/** The shown descendant of `id` whose own text is `label` (e.g. a Tabs / segmented item without its own test id). */
export async function labelNode(id:string,label:string,ms=8000):Promise<any>{
 const find=(n:any):any=>{if((typeof n?.text==='string'?n.text:'')===label&&shown(n))return n;for(const c of n?.children??[]){const f=find(c);if(f)return f;}return null;};
 return h.waitFor(async()=>{for(const root of await h.query(id)){const f=find(root);if(f)return f;}return null;},ms);
}

export function settingsNav(opts:{timeout?:number,settle?:number}={}){
 const timeout=opts.timeout??12000,settle=opts.settle??200;
 const visible=async(id:string)=>(await h.query(id)).some(shown);
 const node=async(id:string,ms=timeout):Promise<any>=>h.waitFor(async()=>(await h.query(id)).find(shown)??null,ms);
 const gone=async(id:string,ms=5000)=>h.waitFor(async()=>(await visible(id))?null:true,ms);
 const title=async()=>textOf((await h.query('settings.page.title')).find(shown));
 const waitTitle=async(want:string,ms=5000)=>h.waitFor(async()=>(await title())===want?true:null,ms);
 /** Scroll the settings content viewport until `id` lies fully inside its visible part (below the floating page header). */
 const reveal=async(id:string)=>{
  for(let i=0;i<16;i++){
   // A search listing every field makes the viewport subtree exceed the Harness query limit (no node array comes back):
   // fall back to its screen rectangle.
   const vq:any=await h.query('settings.viewport');
   const n=await node(id),v=Array.isArray(vq)?vq.find(shown):{rect:await h.screenPos('settings.viewport')};
   if(!v)return n;
   // The page header floats over the top of the viewport (H-shell, feedback 3): content under it is covered.
   const intro=(await h.query('settings.page.intro')).find(shown);
   const top=Math.max(v.rect.y,intro?intro.rect.y+intro.rect.h:v.rect.y),bottom=v.rect.y+v.rect.h;
   if(n.rect.y>=top&&n.rect.y+n.rect.h<=bottom)return n;
   await h.scrollAt(v.rect.x+v.rect.w/2,v.rect.y+v.rect.h/2,0,n.rect.y<top?180:-180);await h.sleep(120);
  }
  return node(id);
 };
 const click=async(id:string)=>{const n=/^settings\.(field|toggle|option|row|materials|font|appearance|ai|ssh|transfer|data|notifications|keys|updates|plugins|plugin)\./.test(id)?await reveal(id):await node(id);assert((await h.clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok,id);await h.sleep(settle);};
 const open=async()=>{if(!(await visible('settings.panel')))await click('toolbar.settings');return node('settings.panel');};
 /** Category page: an overview for categories with subpages, else its panes. */
 const toCategory=async(cat:string)=>{await open();await click('settings.nav.'+cat);await waitTitle(titleOf(cat,null));return title();};
 const toSub=async(cat:string,sub:string)=>{
  const want=titleOf(cat,sub);
  if((await title())===want)return;
  await toCategory(cat);
  await click(`settings.overview.${cat}.${sub}`);await waitTitle(want);
 };
 const toPane=async(pane:string)=>{const [cat,sub]=locatePane(pane);if(sub===null)await toCategory(cat);else await toSub(cat,sub);return reveal(pane);};
 /** Field controls are `settings.field.<key>`; switches in Appearance are `settings.toggle.<key>`. */
 const toField=async(key:string,category?:string)=>{const [cat,sub]=locateKey(key,category);await toSub(cat,sub);const id=await h.waitFor(async()=>(await visible(`settings.field.${key}`))?`settings.field.${key}`:(await visible(`settings.toggle.${key}`))?`settings.toggle.${key}`:null,timeout);return reveal(id);};
 const back=async()=>click('settings.history.back');
 const forward=async()=>click('settings.history.forward');
 /** The preferences window has no close button: Cmd+W closes it (Escape may be consumed by the page). */
 const close=async()=>{await h.key('w',{cmd:true});await gone('settings.panel');await h.waitFor(async()=>{const r:any=await h.query('toolbar.settings').catch(()=>null);return Array.isArray(r)&&r.some(shown)||null;},timeout);await h.sleep(settle);};
 /** Select-all + replace inside a text field. */
 const edit=async(id:string,value:string)=>{await click(id);await h.key('a',{cmd:true});await h.key('backspace');await h.type_(value);await h.sleep(120);};
 /** Save Bar (`settings.footer`) only shows while the current subpage has a draft: "saved / clean" is the bar being hidden
  *  (the old persistent "已保存" footer state is gone; a successful save posts the Toast "设置已保存" instead). */
 const dirty=async()=>visible('settings.footer');
 const saved=async(ms=timeout)=>h.waitFor(async()=>(await visible('settings.footer'))?null:true,ms);
 /** Click Save on the floating Save Bar and wait until it hides (saved). */
 const save=async()=>{await click('settings.save');await saved();};
 /** Save only when a draft exists (the old `if(footer.state!=='已保存'){save}`). */
 const saveIfDirty=async()=>{if(await dirty())await save();};
 /** Appearance › 主题: scroll the horizontal theme strip until `settings.theme.<id>` is inside it, then click it (a draft until saved). */
 const pickTheme=async(id:string)=>{
  await toPane('settings.appearance.themes');await reveal('settings.theme.strip');
  const strip=await node('settings.theme.strip');let tile=await node('settings.theme.'+id);
  for(let i=0;i<30&&(tile.rect.x<strip.rect.x||tile.rect.x+tile.rect.w>strip.rect.x+strip.rect.w);i++){
   await h.scrollAt(strip.rect.x+strip.rect.w/2,strip.rect.y+strip.rect.h/2,tile.rect.x<strip.rect.x?strip.rect.x-tile.rect.x+5:strip.rect.x+strip.rect.w-tile.rect.x-tile.rect.w-5,0);await h.sleep(60);tile=await node('settings.theme.'+id);
  }
  await click('settings.theme.'+id);
 };
 return {node,visible,gone,title,waitTitle,reveal,click,open,close,edit,toCategory,toSub,toPane,toField,back,forward,dirty,saved,save,saveIfDirty,pickTheme};
}
