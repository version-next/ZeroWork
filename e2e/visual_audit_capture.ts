/**
 * 视觉审查截图采集（docs/ui-revamp/VISUAL_AUDIT.md）。
 *
 * 只读采集：不改产品状态以外的任何东西，每次运行用独立的数据目录与 RPC 目录，
 * config.toml 固定 `[updates] auto_check=false`。须在断网沙箱里运行：
 *   zw-nonet.sh node e2e/visual_audit_capture.ts <scenario> <theme> <wide|min> <outDir>
 * scenario:
 *   empty      主程序，无已保存连接：空工作区、侧栏、向导、快速连接、AI、通知、记录、传输、设置
 *   populated  主程序，带已保存连接（指向本机拒连端口）：终端、页签、分组分屏、菜单、搜索、失败连接
 *   auth       auth-challenge-preview 组件夹具：五类认证对话框
 *   files      file-workspace-preview 组件夹具：正常 / 空 / 失败
 *   transfer   transfer-events-preview 组件夹具：任务详情与事件弹层
 * 截图名为 <theme>-<size>-<screen>.png；同目录写 manifest-<scenario>-<theme>-<size>.json。
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import {spawn} from 'node:child_process';
import {mkdtemp,mkdir,writeFile,realpath,open,rm} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import * as h from '../vendor/zenit/e2e/client.ts';
import {aiToggleId} from './ai_entry.ts';
import {settingsNav} from './settings_nav.ts';
const nav=settingsNav();

const [scenario,theme,sizeName,outArg]=process.argv.slice(2);
if(!scenario||!['light','dark'].includes(theme)||!['wide','min'].includes(sizeName)||!outArg)
 throw new Error('usage: visual_audit_capture.ts <empty|populated|auth|files|transfer> <light|dark> <wide|min> <outDir>');
const out=resolve(outArg);await mkdir(out,{recursive:true});
const root=resolve(new URL('..',import.meta.url).pathname);
const bin=(name:string)=>join(root,'zig-out/bin',name);
// 主程序最小窗口 860×480（README「默认步骤」）；组件夹具沿用各自 e2e 的尺寸。
const sizes:Record<string,Record<string,[number,number]>>={
 app:{wide:[1440,900],min:[860,480]},auth:{wide:[1440,900],min:[860,480]},
 files:{wide:[1194,794],min:[790,374]},transfer:{wide:[1440,900],min:[860,480]},
};
const [W,H]=sizes[['empty','wizard','populated'].includes(scenario)?'app':scenario][sizeName];
const iso=await realpath(await mkdtemp('/private/tmp/zw-visual-audit-')),rpc=join(iso,'rpc'),data=join(iso,'data');
await mkdir(rpc);await mkdir(data);
await writeFile(join(data,'config.toml'),`[meta]\nconfig_revision=1\n[ui]\ntheme="${theme}"\n[updates]\nauto_check=false\n`,{mode:0o600});
// 已保存连接全部指向 127.0.0.1 上无人监听的端口，连接会立即被拒，不访问任何外部网络。
if(scenario==='populated')await writeFile(join(data,'hosts.toml'),[
 '[registry]','schema_version=2','revision=1','next_connection_id=5','next_group_id=2',
 '[[groups]]','group_id=1','revision=1','name="生产环境"','collapsed=false','ordered_connection_ids=[1,2]',
 ...[[1,'prod-web-01','deploy',1],[2,'prod-db-primary','dba',1],[3,'staging-api','developer',0],[4,'build-agent-mac','ci',0]].flatMap(([id,name,user,g])=>
  ['[[hosts]]',`connection_id=${id}`,'revision=1','protocol="ssh"','auth_mode="password"',`name="${name}"`,'host="127.0.0.1"','port=65530',`user="${user}"`,...(g?['asset_group_id=1']:[])]),
 ''].join('\n'),{mode:0o600});
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const env={...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1',ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',OPENAI_API_KEY:'',ANTHROPIC_API_KEY:''};
const fixtureArgs:Record<string,[string,string[]]>={
 empty:['zerowork',[]],wizard:['zerowork',[]],populated:['zerowork',[]],auth:['auth-challenge-preview',[theme]],
 transfer:['transfer-events-preview',['--theme',theme]],
};

type Entry={file:string,screen:string,area:string,state:string,theme:string,size:string,window:[number,number],scenario:string,status:'captured'|'failed'|'skipped',error?:string};
const manifest:Entry[]=[];
const shown=(n:any)=>n&&!n.hidden&&n.visible!==false&&n.rect?.w>0&&n.rect?.h>0&&(n.effective_opacity??1)>0;
const flat=(n:any):any[]=>n?[n,...(n.children??[]).flatMap(flat)]:[];
const text=(n:any)=>flat(n).map(x=>x.text??'').join('');
const q=async(id:string):Promise<any[]>=>{try{const r=await h.query(id);return Array.isArray(r)?r:[];}catch{return [];}};
const node=(id:string,ms=8000)=>h.waitFor(async()=>(await q(id)).find(shown)??null,ms);
const present=async(id:string)=>(await q(id)).some(shown);
const gone=(id:string,ms=5000)=>h.waitFor(async()=>(await present(id))?null:true,ms);
const clickNode=async(n:any,button?:'left'|'right'|'middle')=>{
 const x=n.rect.x+Math.min(n.rect.w/2,Math.max(10,n.rect.w/2)),y=n.rect.y+n.rect.h/2;
 if(button&&button!=='left'){await h.mouseMove(x,y);await h.request('POST','/mouse_down',{x,y,button});await h.request('POST','/mouse_up',{x,y,button});}
 else if(!(await h.clickAt(x,y)).ok)throw new Error('click failed');
 await h.sleep(220);
};
const click=async(id:string,button?:'left'|'right'|'middle')=>clickNode(await node(id),button);
const hover=async(id:string,ms=900)=>{const n:any=await node(id);await h.mouseMove(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2);await h.sleep(ms);};
const esc=async(times=2)=>{for(let i=0;i<times;i++){await h.key('escape').catch(()=>{});await h.sleep(120);}};
const parkPointer=async()=>{await h.mouseMove(W-4,H-4).catch(()=>{});await h.sleep(120);};
let windowId:string|undefined;
const shot=async(screen:string,area:string,state:string,opts:{keepPointer?:boolean}={})=>{
 if(!opts.keepPointer)await parkPointer();
 await h.sleep(320);
 const file=`${theme}-${sizeName}-${screen}.png`;
 const res=await h.screenshot(join(out,file));
 if(!res.ok)throw new Error('screenshot failed '+screen);
 manifest.push({file,screen,area,state,theme,size:sizeName,window:[W,H],scenario,status:'captured'});
};
// 每个界面独立 try：失败只记录，不中断后续采集。
const step=async(screen:string,area:string,state:string,run:()=>Promise<void>)=>{
 try{await run();}
 catch(e){manifest.push({file:'',screen,area,state,theme,size:sizeName,window:[W,H],scenario,status:'failed',error:String((e as any)?.message??e).slice(0,400)});await esc(3);}
};
const skip=(screen:string,area:string,state:string,why:string)=>manifest.push({file:'',screen,area,state,theme,size:sizeName,window:[W,H],scenario,status:'skipped',error:why});
const typeInto=async(id:string,value:string)=>{await click(id);await h.key('a',{cmd:true});await h.type_(value);await h.sleep(150);};
const tabIds=async()=>{const strip=(await q('tabs.strip')).find(shown);return strip?flat(strip).filter(n=>shown(n)&&/^tabs\.tab\.\d+$/.test(n.test_id??'')).map(n=>n.test_id as string):[];};
const newLocal=async()=>{const before=(await tabIds()).length;await click('toolbar.new_session');await click('session.menu.local').catch(async()=>{await esc(1);await h.key('t',{cmd:true});});await h.waitFor(async()=>(await tabIds()).length>before||null,10000);await node('terminal.surface');await h.sleep(600);};
// design-r3 稿 5: folded tools are rows of the ⋯ menu (toolbar.more.<tool>).
const moreRow:Record<string,string>={'status.connection.chain':'toolbar.more.chain','status.connection.forward':'toolbar.more.forward','toolbar.transfers':'toolbar.more.transfers','status.command-history':'toolbar.more.command_history','toolbar.history':'toolbar.more.history','toolbar.notifications':'toolbar.more.notifications','toolbar.settings':'toolbar.more.settings'};
const toolbar=async(id:string)=>{if(!(await present(id))&&(await present('toolbar.expand'))&&moreRow[id]){await click('toolbar.expand');await h.sleep(400);await click(moreRow[id]);return;}await click(id);};
const ensureSidebar=async()=>{if(!(await present('workspace.sidebar'))||(await present('sidebar.restore'))){if(await present('sidebar.restore'))await click('sidebar.restore');else{await h.key('b',{cmd:true});await h.sleep(300);}}};

async function emptyScenario(){
 await step('workspace-empty','工作区','启动后空工作区，侧栏展开，无已保存连接',async()=>{await node('workspace.empty');await shot('workspace-empty','工作区','启动后空工作区，侧栏展开，无已保存连接');});
 await step('workspace-empty-sidebar-collapsed','工作区','空工作区，⌘B 收起侧栏',async()=>{await h.key('b',{cmd:true});await h.sleep(400);await shot('workspace-empty-sidebar-collapsed','工作区','空工作区，⌘B 收起侧栏');await h.key('b',{cmd:true});await h.sleep(400);});
 await step('toolbar-tooltip','工作区','悬停工具栏「设置」按钮显示提示',async()=>{await hover((await present('toolbar.settings'))?'toolbar.settings':'toolbar.expand',1200);await shot('toolbar-tooltip','工作区','悬停工具栏「设置」按钮显示提示',{keepPointer:true});});
 await step('session-menu','工作区','工具栏「新建会话」下拉菜单（无已保存连接）',async()=>{await click('toolbar.new_session');await node('session.menu');await shot('session-menu','工作区','工具栏「新建会话」下拉菜单（无已保存连接）');await esc();});

 await step('quick-connect-empty','快速连接','快速连接面板空态',async()=>{await h.key('k',{cmd:true});await node('quick.query');await shot('quick-connect-empty','快速连接','快速连接面板空态');});
 await step('quick-connect-typed','快速连接','快速连接输入 user@host:port',async()=>{await click('quick.query');await h.type_('deploy@10.0.1.24:2222');await h.sleep(300);await shot('quick-connect-typed','快速连接','快速连接输入 user@host:port');await esc(3);});

 await step('notifications-empty','通知','通知中心空态',async()=>{await toolbar('toolbar.notifications');await node('notifications.history');await shot('notifications-empty','通知','通知中心空态');await esc(2);});
 await step('history-empty','会话记录','会话记录面板空态',async()=>{await toolbar('toolbar.history');await node('history.panel');await shot('history-empty','会话记录','会话记录面板空态');await esc(2);});
 await step('transfers-empty','传输','传输面板空态',async()=>{await toolbar('toolbar.transfers');await h.sleep(500);await shot('transfers-empty','传输','传输面板空态');await esc(2);});

 // 设置窗口：总览 → 子页
 const st=async(screen:string,state:string,fn:()=>Promise<void>)=>step(screen,'设置',state,async()=>{await fn();await shot(screen,'设置',state);});
 await step('settings-open','设置','打开设置',async()=>{await toolbar('toolbar.settings');await node('settings.panel');await h.resizeWindow(W,H);await h.sleep(500);});
 for(const [slug,name] of [['appearance','外观与主题'],['ssh','SSH 与网络'],['transfer','文件传输'],['ai','AI 辅助'],['notifications','通知'],['data','数据与日志']])
  await st(`settings-${slug}-overview`,`设置「${name}」总览页`,async()=>{await nav.toCategory(slug);await node('settings.overview');});
 await st('settings-appearance-theme','设置子页「外观与主题 › 主题」',async()=>{await nav.toSub('appearance','theme');await node('settings.appearance.themes');});
 await st('settings-ssh-connection','设置子页「SSH 与网络 › 连接」',async()=>{await nav.toSub('ssh','connection');await node('settings.ssh.connection');});
 await st('settings-ai-providers','设置子页「AI 辅助 › 服务提供方」',async()=>{await nav.toSub('ai','providers');await node('settings.ai.providers');});
 await st('settings-ai-behavior','设置子页「AI 辅助 › 行为与权限」（长页）',async()=>{await click('settings.history.back');await click('settings.overview.ai.behavior');await node('settings.ai.permissions');});
 await st('settings-keys','设置直达页「快捷键」',async()=>{await nav.toCategory('keys');await node('settings.keys.tabs');});
 await st('settings-plugins','设置直达页「协议插件」',async()=>{await nav.toCategory('plugins');await h.sleep(300);});
 await st('settings-updates','设置直达页「关于与更新」',async()=>{await nav.toCategory('updates');await node('settings.updates.version');});
 await st('settings-search','设置搜索 keepalive 的结果',async()=>{await click('settings.search');await h.type_('keepalive');await node('settings.field.keepalive_sec');});
 await st('settings-search-empty','设置搜索无结果',async()=>{await click('settings.search');await h.key('a',{cmd:true});await h.type_('zzqqxx');await h.sleep(400);});
 await st('settings-dirty-subpage','子页修改字段后出现未保存保存条',async()=>{
  await click('settings.search');await h.key('a',{cmd:true});await h.key('backspace');await h.sleep(200);
  await nav.toSub('ssh','connection');const f:any=await node('settings.field.keepalive_sec');
  await h.clickAt(f.rect.x+f.rect.w/2,f.rect.y+f.rect.h/2);await h.key('a',{cmd:true});await h.type_('45');await h.sleep(300);await node('settings.footer');});
 await st('settings-dirty-overview','未保存时返回总览页',async()=>{await click('settings.history.back');await node('settings.overview');});
}

// 向导是独立原生窗口；关闭后 Harness 不会回绑主窗口，所以单独一个进程采集。
async function wizardScenario(){
 // 新建连接向导
 await step('wizard-identity-pristine','连接向导','第 1 步「身份」初始空白表单',async()=>{await click('sidebar.empty.new');await node('wizard.name',12000);await h.resizeWindow(W,H);await h.sleep(600);await shot('wizard-identity-pristine','连接向导','第 1 步「身份」初始空白表单');});
 await step('wizard-identity-errors','连接向导','第 1 步失焦后的字段校验错误（名称/主机/用户/端口 +22）',async()=>{
  await click('wizard.name');await click('wizard.host');await click('wizard.user');await click('wizard.port');await h.key('a',{cmd:true});await h.type_('+22');await click('wizard.group');
  await node('wizard.host.error');await shot('wizard-identity-errors','连接向导','第 1 步失焦后的字段校验错误（名称/主机/用户/端口 +22）');});
 await step('wizard-identity-key-error','连接向导','第 1 步切到「密钥」认证、密钥路径为空的错误',async()=>{
  await typeInto('wizard.name','prod-web-01');await typeInto('wizard.host','10.0.1.24');await typeInto('wizard.user','deploy');await typeInto('wizard.port','22');
  await click('wizard.auth');await click('wizard.auth.key');await click('wizard.key_path');await click('wizard.name');await node('wizard.key_path.error');
  await shot('wizard-identity-key-error','连接向导','第 1 步切到「密钥」认证、密钥路径为空的错误');
  await click('wizard.auth');await click('wizard.auth.password');});
 await step('wizard-identity-advanced','连接向导','第 1 步展开「高级选项」',async()=>{await click('wizard.advanced.toggle');await h.sleep(400);await shot('wizard-identity-advanced','连接向导','第 1 步展开「高级选项」');await click('wizard.advanced.toggle');await h.sleep(300);});
 await step('wizard-route','连接向导','第 2 步「连接路径」直连',async()=>{await click('wizard.next.identity');await node('wizard.access.direct');await h.sleep(300);await shot('wizard-route','连接向导','第 2 步「连接路径」直连');});
 await step('wizard-route-jump','连接向导','第 2 步切到「跳板」路径，未填跳板',async()=>{await click('wizard.access.jump');await h.sleep(400);await shot('wizard-route-jump','连接向导','第 2 步切到「跳板」路径，未填跳板');await click('wizard.access.direct');await h.sleep(300);});
 await step('wizard-review','连接向导','第 3 步「核对与测试」摘要（未执行测试）',async()=>{await click('wizard.next.route');await node('wizard.review.name');await h.sleep(300);await shot('wizard-review','连接向导','第 3 步「核对与测试」摘要（未执行测试）');});
 await step('wizard-close','连接向导','关闭向导',async()=>{for(let i=0;i<4&&(await present('wizard.name')||await present('wizard.review.name'));i++){if(await present('wizard.cancel'))await click('wizard.cancel');else if(await present('wizard.close'))await click('wizard.close');else await esc(1);await h.sleep(600);}
  await h.waitFor(async()=>(await h.windows()).windows.filter(w=>!w.closing).length===1||null,8000);await h.sleep(400);});

}

async function populatedScenario(){
 await step('sidebar-hosts','侧栏','侧栏含分组与已保存连接，空工作区',async()=>{await node('sidebar.host');await shot('sidebar-hosts','侧栏','侧栏含分组与已保存连接，空工作区');});
 await step('sidebar-host-hover','侧栏','悬停已保存连接行',async()=>{const n:any=(await q('sidebar.host')).filter(shown)[1]??await node('sidebar.host');await h.mouseMove(n.rect.x+40,n.rect.y+n.rect.h/2);await h.sleep(900);await shot('sidebar-host-hover','侧栏','悬停已保存连接行',{keepPointer:true});});
 await step('sidebar-host-menu','侧栏','已保存连接右键菜单',async()=>{await click('sidebar.host','right');await node('context.menu');await shot('sidebar-host-menu','侧栏','已保存连接右键菜单');await esc();});
 await step('sidebar-group-menu','侧栏','资产分组右键菜单',async()=>{await click('sidebar.group','right');await h.sleep(300);await shot('sidebar-group-menu','侧栏','资产分组右键菜单');await esc();});

 await step('connection-failed','连接','已保存 SSH 连接（拒连端口）连接失败的进度/错误视图',async()=>{
  const host:any=await node('sidebar.host');await clickNode(host);await h.key('return');
  await h.waitFor(async()=>{const n=(await q('connection.progress.summary.detail')).find(shown);return n&&text(n).length>0?true:null;},30000);await h.sleep(800);
  await shot('connection-failed','连接','已保存 SSH 连接（拒连端口）连接失败的进度/错误视图');});
 await step('notification-toast','通知','连接失败后的通知（若出现）',async()=>{if(!(await present('notifications.presenter'))&&!(await present('notifications.toast.0')))throw new Error('no toast');await shot('notification-toast','通知','连接失败后弹出的通知');});
 await step('connection-failed-closed','连接','关闭失败进度后的页签/工作区状态',async()=>{if(await present('connection.progress.close'))await click('connection.progress.close');await h.sleep(600);await shot('connection-failed-closed','连接','关闭失败进度后的页签/工作区状态');});
 await step('terminal-single','终端','单个本地终端会话，执行过几条命令，含页签栏与状态条',async()=>{
  await newLocal();await h.sleep(1500);await click('terminal.surface');
  await h.type_('echo "ZeroWork visual audit"; ls -la /usr | head -12');await h.key('return');await h.sleep(900);
  await shot('terminal-single','终端','单个本地终端会话，执行过几条命令，含页签栏与状态条');});
 await step('terminal-single-sidebar','终端','单会话 + 侧栏展开',async()=>{await ensureSidebar();await h.sleep(300);await shot('terminal-single-sidebar','终端','单会话 + 侧栏展开');await h.key('b',{cmd:true});await h.sleep(300);});
 await step('terminal-search','终端','⌘F 终端内搜索，有匹配',async()=>{await click('terminal.surface');await h.key('f',{cmd:true});await node('terminal.search.query');await h.type_('visual');await h.sleep(400);await shot('terminal-search','终端','⌘F 终端内搜索，有匹配');});
 await step('terminal-search-none','终端','终端内搜索无匹配',async()=>{await h.key('a',{cmd:true});await h.type_('nomatch-zzqq');await h.sleep(400);await shot('terminal-search-none','终端','终端内搜索无匹配');await click('terminal.search.close').catch(()=>esc());});
 await step('terminal-context-menu','终端','终端区中键菜单（右键为弹出菜单，见 terminal_right_click_native）',async()=>{const n:any=await node('terminal.surface');const x=n.rect.x+120,y=n.rect.y+80;await h.request('POST','/mouse_down',{x,y,button:'middle'});await h.request('POST','/mouse_up',{x,y,button:'middle'});await node('context.menu');await shot('terminal-context-menu','终端','终端区中键菜单（右键为弹出菜单，见 terminal_right_click_native）');await esc();});
 await step('terminal-at-commands','终端','终端内输入 @ 弹出内建命令面板',async()=>{
  let ok=false;for(let i=0;i<3&&!ok;i++){await click('terminal.surface');await h.type_('@');try{await node('terminal.commands',4000);ok=true;}catch{await h.key('c',{ctrl:true});await h.sleep(400);}}
  if(!ok)throw new Error('@ command popup did not appear');await shot('terminal-at-commands','终端','终端内输入 @ 弹出内建命令面板');await esc();await h.key('c',{ctrl:true});});

 await step('notifications-history','通知','通知中心含记录',async()=>{await toolbar('toolbar.notifications');await node('notifications.history');await h.sleep(300);await shot('notifications-history','通知','通知中心含记录');await esc(2);});
 await step('history-records','会话记录','会话记录面板（有本地与失败 SSH 记录）',async()=>{await toolbar('toolbar.history');await node('history.panel');await h.sleep(400);await shot('history-records','会话记录','会话记录面板（有本地与失败 SSH 记录）');});
 await step('history-record-hover','会话记录','悬停一条会话记录',async()=>{await hover('history.record',1000);await shot('history-record-hover','会话记录','悬停一条会话记录',{keepPointer:true});await esc(2);});
 await step('tabs-multi','页签','4 个本地会话页签，第 2 个重命名为长标题',async()=>{for(let i=0;i<3;i++)await newLocal();await shot('tabs-multi','页签','4 个本地会话页签');});
 await step('tab-hover','页签','悬停页签显示提示',async()=>{const ids=await tabIds();await hover(ids[0],1200);await shot('tab-hover','页签','悬停页签显示提示',{keepPointer:true});});
 await step('tab-context-menu','页签','页签右键菜单',async()=>{const ids=await tabIds();await click(ids[0],'right');await node('context.menu');await shot('tab-context-menu','页签','页签右键菜单');await esc();});
 await step('group-split-side','分组','⌘D 分屏成会话分组（左右 2 成员）',async()=>{await click('terminal.surface');await h.key('d',{cmd:true});await node('groups.workspace');await h.sleep(1500);await shot('group-split-side','分组','⌘D 分屏成会话分组（左右 2 成员）');});
 await step('group-member-menu','分组','分组成员「⋯」菜单',async()=>{const ws=(await q('groups.workspace')).find(shown);const m=flat(ws).find(n=>shown(n)&&/^groups\.menu\.\d+$/.test(n.test_id??''));if(!m)throw new Error('no member menu');await clickNode(m);await node('groups.member_menu');await shot('group-member-menu','分组','分组成员「⋯」菜单');
  const item=flat(await node('groups.member_menu')).find(n=>n.text==='全部改为上下排列');if(item){await clickNode(item);await h.sleep(600);await shot('group-split-stacked','分组','会话分组上下排列');}else await esc();});
 await step('group-tab-menu','分组','分组页签右键菜单',async()=>{const strip=(await q('tabs.strip')).find(shown);const g=flat(strip).filter(n=>shown(n)&&/^tabs\.tab\.\d+$/.test(n.test_id??'')).find(n=>text(n).includes('组'));if(!g)throw new Error('no group tab');await clickNode(g,'right');await h.sleep(400);await shot('group-tab-menu','分组','分组页签右键菜单');await esc();});
 await step('ai-empty','AI 助手','AI 面板，未配置 provider 的空态',async()=>{await click('terminal.surface');await h.key('j',{cmd:true});await node('ai.panel');await h.sleep(500);await shot('ai-empty','AI 助手','AI 面板，未配置 provider 的空态');});
 await step('ai-composer-typed','AI 助手','Composer 输入了一段多行文字',async()=>{await click('ai.prompt');await h.type_('帮我检查 prod-web-01 上 nginx 的错误日志，并总结最近一小时的 5xx 原因');await h.sleep(300);await shot('ai-composer-typed','AI 助手','Composer 输入了一段文字');});
 await step('ai-model-menu','AI 助手','Composer 模型选择菜单',async()=>{await click('ai.composer.model');await node('ai.model.menu');await shot('ai-model-menu','AI 助手','Composer 模型选择菜单');await esc();});
 await step('ai-permission-menu','AI 助手','Composer 权限模式菜单',async()=>{await click('ai.composer.permission');await h.sleep(300);await shot('ai-permission-menu','AI 助手','Composer 权限模式菜单');await esc();});
 await step('ai-execution-menu','AI 助手','Composer 执行方式菜单',async()=>{await click('ai.composer.execution');await h.sleep(300);await shot('ai-execution-menu','AI 助手','Composer 执行方式菜单');await esc();});
 await esc(2);if(await present('ai.panel')){await h.key('j',{cmd:true});await h.sleep(500);}if(await present('ai.panel'))await click(await aiToggleId()).catch(()=>{});

 await step('menu-bar-appearance','外观','菜单栏“显示 › 外观…”打开设置 › 外观与主题（主题不在标题栏，title-click）',async()=>{if(!(await h.request('POST','/zerowork/app-menu',{invoke:true})).ok)throw new Error('app-menu route');await node('settings.appearance.themes');await h.sleep(400);await shot('menu-bar-appearance','外观','设置 › 外观与主题（菜单栏“显示 › 外观…”）');await esc();});
 await step('tabs-overflow','页签','10 个页签时的溢出与全部页签入口',async()=>{for(let i=0;i<6;i++)await newLocal();await h.sleep(300);await shot('tabs-overflow','页签','10 个页签时的溢出');});
 await step('tabs-picker','页签','「⌄ n」溢出菜单',async()=>{if(!(await present('tabs.all')))throw new Error('tabs.all not visible at this width');await click('tabs.all');await node('tabs.all.menu');await shot('tabs-picker','页签','「⌄ n」溢出菜单');await esc();});

}

async function authScenario(){
 for(const kind of ['password','private_key_passphrase','keyboard_interactive','host_key_unknown','host_key_changed']){
  await step('auth-'+kind,'认证对话框',`认证对话框：${kind}`,async()=>{await click('legacy.auth.'+kind);await node('auth.challenge.modal');await h.sleep(250);await shot('auth-'+kind,'认证对话框',`认证对话框：${kind}（组件夹具窗口，背景为夹具按钮）`);
   if(kind==='password'){await click('auth.challenge.answer.0');await h.type_('secret');await h.sleep(200);await shot('auth-password-filled','认证对话框','密码对话框已输入（掩码）');}
   await click('auth.challenge.cancel');await gone('auth.challenge.modal');});
 }
}

async function filesScenario(){
 // 该夹具每个状态一个进程，这里只采当前进程的状态（由外层循环传入）。
}

async function transferScenario(){
 await step('transfer-task-detail','传输','传输任务详情（夹具：确定性引擎）',async()=>{await node('transfer.task.events');await h.sleep(300);await shot('transfer-task-detail','传输','传输任务详情（夹具：确定性引擎）');});
 await step('transfer-events-popover','传输','传输任务事件弹层',async()=>{await click('transfer.task.events');await h.sleep(400);await shot('transfer-events-popover','传输','传输任务事件弹层');await esc();});
}

async function runApp(binary:string,args:string[],body:()=>Promise<void>,label:string){
 const log=await open(join(out,`app-${scenario}-${label}-${theme}-${sizeName}.log`),'w');
 const app=spawn(binary,args,{env,stdio:['ignore',log.fd,log.fd]});
 const ended=new Promise(r=>app.once('close',r));
 try{
  await h.waitForServerReady(30000);await h.resizeWindow(W,H);await h.sleep(500);
  windowId=(await h.windows()).windows.find(w=>w.bound&&!w.closing)?.window_id;
  await body();
 }finally{app.kill('SIGTERM');await Promise.race([ended,h.sleep(4000)]);if(app.exitCode===null&&app.signalCode===null){app.kill('SIGKILL');await ended;}await log.close();}
}

try{
 if(scenario==='files'){
  for(const state of ['normal','empty','failed']){
   const sub=join(iso,'rpc-'+state);await mkdir(sub);process.env.ZENIT_E2E_FILE_RPC_DIR=sub;(env as any).ZENIT_E2E_FILE_RPC_DIR=sub;
   await runApp(bin('file-workspace-preview'),[`--state=${state}`,`--theme=${theme}`],async()=>{
    await step('files-'+state,'文件工作区',`文件工作区组件夹具：${state}`,async()=>{await node('files.workspace',20000);await h.sleep(400);await shot('files-'+state,'文件工作区',`文件工作区组件夹具：${state==='normal'?'正常列表（本地/远端两栏）':state==='empty'?'远端目录为空':'远端加载失败（保留旧内容）'}`);});
   },state);
  }
 }else{
  const [b,args]=fixtureArgs[scenario];
  await runApp(bin(b),args,{empty:emptyScenario,wizard:wizardScenario,populated:populatedScenario,auth:authScenario,transfer:transferScenario,files:filesScenario}[scenario]!,'main');
 }
}catch(e){manifest.push({file:'',screen:'(run)',area:scenario,state:'runner',theme,size:sizeName,window:[W,H],scenario,status:'failed',error:String((e as any)?.stack??e).slice(0,600)});process.exitCode=1;}
finally{
 await writeFile(join(out,`manifest-${scenario}-${theme}-${sizeName}.json`),JSON.stringify(manifest,null,2));
 await rm(iso,{recursive:true,force:true}).catch(()=>{});
 const c=manifest.filter(m=>m.status==='captured').length;
 console.log(JSON.stringify({scenario,theme,size:sizeName,captured:c,failed:manifest.filter(m=>m.status!=='captured').map(m=>`${m.screen}: ${m.error}`)}));
}
