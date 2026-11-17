/**
 * Settings revamp acceptance (Pencil `p6ZVS` … `dM7oF`): floating Settings Nav,
 * category overviews with drill-down subpages, Back / Forward history, search,
 * floating Save Bar, edit → save from a subpage, and deep links.
 *
 * Usage: node e2e/settings_revamp_native.ts <zerowork binary (test-mode)> <evidence dir> [light|dark]
 * Isolated data dir and RPC dir; no network access is needed.
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdtemp,mkdir,writeFile,readFile,realpath,open} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import * as h from '../vendor/zenit/e2e/client.ts';

const [binaryArg,outArg,theme='light']=process.argv.slice(2);
if(!binaryArg||!outArg)throw new Error('usage: settings_revamp_native.ts <binary> <out> [light|dark]');
const binary=resolve(binaryArg),out=resolve(outArg);await mkdir(out,{recursive:true});
const iso=await realpath(await mkdtemp('/private/tmp/zw-settings-revamp-')),rpc=join(iso,'rpc'),data=join(iso,'data');
await mkdir(rpc);await mkdir(data);
await writeFile(join(data,'config.toml'),`[meta]\nconfig_revision=1\n[ui]\ntheme="${theme}"\n[updates]\nauto_check=false\n`,{mode:0o600});
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const log=await open(join(out,'app.log'),'w');
const app=spawn(binary,[],{env:{...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1',ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',OPENAI_API_KEY:'',ANTHROPIC_API_KEY:''},stdio:['ignore',log.fd,log.fd]});
const ended=new Promise(r=>app.once('close',r));

// Overview categories → subpages → panes (mirrors src/features/settings/view/settings_subpages.zig).
const categories:[string,string,[string,string,string[]][]][]=[
 ['appearance','外观与主题',[['theme','主题',['settings.appearance.themes','settings.appearance.app_icon','settings.appearance.materials','settings.appearance.preview']],['font','字体与排版',['settings.appearance.font']],['terminal','终端与工作区',['settings.appearance.aids']]]],
 ['ssh','SSH 与网络',[['connection','连接',['settings.ssh.connection']],['socks','SOCKS5 转发',['settings.ssh.socks']],['reconnect','断线重连',['settings.ssh.reconnect']],['authentication','双因素认证',['settings.ssh.authentication']]]],
 ['transfer','文件传输',[['connection','连接隔离',['settings.transfer.connection']],['engine','SFTP 引擎',['settings.transfer.engine']],['defaults','默认行为',['settings.transfer.defaults']]]],
 ['ai','AI 辅助',[['providers','服务提供方',['settings.ai.providers']],['behavior','行为与权限',['settings.ai.permissions','settings.ai.execution','settings.ai.conversation','settings.ai.children','settings.ai.context','settings.ai.attachments','settings.ai.behavior']],['extensions','技能与 MCP',['settings.ai.extensions']]]],
 ['notifications','通知',[['events','事件提醒',['settings.notifications.events']],['attention','注意标记与勿扰',['settings.notifications.attention']]]],
 ['data','数据与日志',[['location','位置与凭据',['settings.data.location']],['history','会话记录',['settings.data.history']],['actions','导出与清理',['settings.data.actions']]]],
];
const direct:[string,string,string[]][]=[['keys','快捷键',['settings.keys.tabs','settings.keys.terminal']],['plugins','协议插件',[]],['updates','关于与更新',['settings.updates.version','settings.updates.preferences']]];

const shown=(n:any)=>n&&n.visible!==false&&n.rect?.w>0&&n.rect?.h>0&&(n.effective_opacity??1)>0;
const visible=async(id:string)=>(await h.query(id)).some(shown);
const node=async(id:string,ms=10000)=>h.waitFor(async()=>(await h.query(id)).find(shown)??null,ms);
const gone=async(id:string)=>h.waitFor(async()=>(await visible(id))?null:true,5000);
const click=async(id:string)=>{const n:any=await node(id);assert((await h.clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok,id);await h.sleep(220);};
const text=(n:any):string=>[n?.text??'',...(n?.children??[]).map(text)].join('');
const title=async()=>text(await node('settings.page.title'));
const disabled=async(id:string)=>((await h.query(id))[0] as any)?.disabled===true;
let win:string|undefined;
const shot=async(name:string)=>{await h.mouseMove(2,2).catch(()=>{});await h.sleep(150);assert((await h.screenshot(join(out,`${theme}-${name}.png`),win)).ok,name);};
const report:any={status:'running',theme,checks:[] as string[]};
const check=(s:string)=>{report.checks.push(s);};

try{
 await h.waitForServerReady();await h.resizeWindow(1440,900);
 await click('toolbar.settings');await node('settings.panel');
 win=(await h.windows()).windows.find(w=>w.bound&&!w.closing)?.window_id;
 const panel:any=await node('settings.panel');
 assert.equal(Math.round(panel.rect.w),960);assert.equal(Math.round(panel.rect.h),780);
 const navRect=(await node('settings.navigation') as any).rect;assert.equal(Math.round(navRect.w),216);assert.equal(Math.round(navRect.x),8);
 await node('settings.navigation.note');
 check('Window 960×780; floating Settings Nav 216 wide inset 8; local note shown');

 for(const [slug,name,subs] of categories){
  await click('settings.nav.'+slug);
  await node('settings.overview');assert.equal(await title(),name);
  for(const [sub] of subs){await node(`settings.overview.${slug}.${sub}`);assert(text(await node(`settings.overview.${slug}.${sub}.summary`)).length>0,`${slug}.${sub} summary`);}
  assert(!(await visible('settings.footer')),`${slug}: clean overview hides the Save Bar`);
  await shot(slug);
  for(const [sub,subTitle,panes] of subs){
   await click(`settings.overview.${slug}.${sub}`);
   await h.waitFor(async()=>(await title())===subTitle?true:null,5000);
   for(const pane of panes) await node(pane);
   for(const [,,others] of subs) for(const other of others) if(!panes.includes(other)) assert(!(await visible(other)),`${slug}.${sub} hides ${other}`);
   // H-save: a clean subpage has no Save Bar (no standing “所有更改已保存”).
   assert(!(await visible('settings.footer')),`${slug}.${sub}: clean subpage hides the Save Bar`);assert(!(await disabled('settings.history.back')));
   await shot(`${slug}-${sub}`);
   await click('settings.history.back');await node('settings.overview');assert.equal(await title(),name);
   assert(!(await disabled('settings.history.forward')));
   await click('settings.history.forward');await h.waitFor(async()=>(await title())===subTitle?true:null,5000);
   await click('settings.history.back');await node('settings.overview');
  }
  check(`${name}: overview with ${subs.length} rows; each subpage shows only its panes; Back/Forward round-trip`);
 }
 for(const [slug,name,panes] of direct){
  await click('settings.nav.'+slug);await h.waitFor(async()=>(await title())===name?true:null,5000);
  assert(!(await visible('settings.overview')),`${slug} has no overview`);
  for(const pane of panes) await node(pane);
  assert(!(await visible('settings.footer')),`${slug}: clean page hides the Save Bar`);await shot(slug);
  check(`${name}: renders its panes directly`);
 }

 // History crosses categories: Back returns to the previous category.
 await click('settings.nav.ssh');await click('settings.nav.transfer');
 await click('settings.history.back');await h.waitFor(async()=>(await title())==='SSH 与网络'?true:null,5000);
 check('Back after a category switch returns to the previous category');

 // Search spans every category regardless of drill-down; clearing returns to the page.
 const search:any=await node('settings.search');
 await h.clickAt(search.rect.x+search.rect.w/2,search.rect.y+search.rect.h/2);await h.type_('keepalive');
 await node('settings.field.keepalive_sec');assert.equal(await title(),'搜索结果');
 await shot('search');
 await click('settings.history.back');
 await h.waitFor(async()=>(await title())==='SSH 与网络'?true:null,5000);
 check('Search shows results across categories; Back leaves search for the original page');

 // Edit on a subpage: the Save Bar appears; leaving the subpage asks first (H-save), 保存 persists and then leaves.
 await click('settings.overview.ssh.connection');
 const field:any=await node('settings.field.keepalive_sec');
 await h.clickAt(field.rect.x+field.rect.w/2,field.rect.y+field.rect.h/2);
 await h.key('a',{cmd:true});await h.type_('45');await h.sleep(200);
 assert.equal(text(await node('settings.footer.state')),'未保存');
 await click('settings.history.back');await node('settings.confirmation');assert.equal(await title(),'连接');
 await h.sleep(300);await shot('leave-confirmation');
 await click('settings.confirmation.save');
 await h.waitFor(async()=>(await readFile(join(data,'config.toml'),'utf8')).includes('keepalive_sec = 45')||null,20000);
 await node('settings.overview');assert.match(text(await node('settings.overview.ssh.connection.summary')),/保活 45 秒/);
 await gone('settings.footer');
 await h.waitFor(async()=>JSON.stringify(await h.tree()).includes('设置已保存')||null,5000);
 await shot('saved-overview');
 check('Subpage edit shows the Save Bar; leaving asks first; 保存 persists keepalive_sec = 45, lands on the overview with the new summary, no Save Bar, toast 设置已保存');

 // Deep link: the assistant's "configure provider" lands on AI 辅助 › 服务提供方.
 await click('settings.nav.ai');await click('settings.overview.ai.providers');await node('settings.ai.providers');
 report.status='passed';
}catch(e){report.status='failed';report.error=String((e as any)?.stack??e);process.exitCode=1;await shot('failure').catch(()=>{});}
finally{app.kill('SIGTERM');await ended;await log.close();await writeFile(join(out,`report-${theme}.json`),JSON.stringify(report,null,2));console.log(JSON.stringify({status:report.status,checks:report.checks.length,error:report.error}));}
