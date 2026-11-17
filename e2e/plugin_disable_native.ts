/**
 * 随应用插件的禁用开关（PLUGIN_ARCH_PLAN 6.2.1 Q5、Q5a–Q5c；Pencil XqqLV 稿 2）真实窗口全流程，用测试构建里的
 * `fixture_probe`（`-Dtest-mode=true -Dplugin-fixture=true`），不依赖真实 BMC：
 *   1. 第一次启动：经连接向导保存一台 fixture 主机；内置插件（local）没有开关；fixture 详情页开关打开（Jm2fZ）。
 *      拨动 → 改了未保存（SH1gb，保存栏）→ 撤销恢复；再拨动并保存 → 待重启（NHr2L：warning 标签、提示、“立即重启”），
 *      配置只多一条 `host.enabled = "false"`；列表行标“重启后停用”。
 *      “立即重启”走正常退出：开着本机终端时出现关闭确认，取消 → 应用不退出、状态保持“重启后生效”、再启动登记撤销；
 *      再点并确认 → 应用正常退出（exit 0），并登记了再启动（测试构建只打印 `ZW_RELAUNCH`，由本脚本用同一数据目录重启）。
 *   2. 第二次启动：列表行变淡、标“已禁用”（UuE31）；详情页显示已禁用提示（B0QXg6 / IeCzY）；侧栏主机留在原位、
 *      标“已禁用”、没有连接按钮、Tooltip 写明原因与恢复路径（qQaos）；右键菜单“新标签连接”置灰、“编辑”“删除”可用（RfJyL）；
 *      编辑只能改名称，协议载荷字节不变；新建连接的协议下拉里 fixture 是禁用选项（YWqSG）。打开开关并保存 → 待重启（重启后启用），
 *      “立即重启”无确认直接正常退出。
 *   3. 第三次启动：全部恢复——列表行与详情页回到已启用，侧栏主机可以连接（发起连接后出现插件内容或连接时的密钥提示）。
 * 每个状态截图（主题由第三个参数给出，亮 / 暗各跑一次）。
 * Usage: node e2e/plugin_disable_native.ts <zerowork binary (test-mode + plugin-fixture)> <out dir> [light|dark]
 */
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdtemp,mkdir,open,readFile,writeFile,realpath,rm} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import * as h from '../vendor/zenit/e2e/client.ts';
import {settingsNav,shown,textOf} from './settings_nav.ts';

const [binaryArg,outArg,themeArg]=process.argv.slice(2);assert(binaryArg&&outArg,'usage: plugin_disable_native.ts <binary> <out> [light|dark]');
const binary=resolve(binaryArg),out=resolve(outArg),theme=themeArg??'light';
await mkdir(out,{recursive:true});
const iso=await realpath(await mkdtemp('/private/tmp/zw-plugin-disable-e2e-')),data=join(iso,'data');await mkdir(data,{mode:0o700});
await writeFile(join(data,'config.toml'),`[meta]\nconfig_revision=1\n[updates]\nauto_check=false\n[ui]\ntheme="${theme}"\n`,{mode:0o600});
const config=join(data,'config.toml'),hostsPath=join(data,'hosts.toml');
const nav=settingsNav();
const report:any={status:'running',theme,checks:[],screenshots:[],launches:[]};
let app:any=null,ended:Promise<number|null>=Promise.resolve(null),phase=0,logPath='';

async function launch(){
 const rpc=join(iso,'rpc-'+ ++phase);await mkdir(rpc);process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
 logPath=join(out,`app-${theme}-${phase}.log`);const log=await open(logPath,'w');
 app=spawn(binary,[],{env:{...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1',ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',OPENAI_API_KEY:'',ANTHROPIC_API_KEY:''},stdio:['ignore',log.fd,log.fd]});
 ended=new Promise(r=>app.once('close',(code:number|null)=>{log.close().catch(()=>{});r(code);}));
 await h.waitForServerReady();await h.resizeWindow(1280,860);await h.sleep(400);
 report.launches.push({phase,pid:app.pid});
}
async function kill(){if(app&&app.exitCode===null&&app.signalCode===null){app.kill('SIGTERM');await ended;}}
const text=async(id:string)=>textOf(await nav.node(id)).trim();
const visible=async(id:string,ms=12000)=>nav.node(id,ms);
const absent=async(id:string)=>{const r:any=await h.query(id).catch(()=>[]);return !Array.isArray(r)||!r.some(shown);};
const click=async(id:string)=>{const n=await visible(id);assert((await h.clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok,id);await h.sleep(250);};
const shot=async(name:string)=>{await h.mouseMove(2,2).catch(()=>{});await h.sleep(400);const path=join(out,`${theme}-${name}.png`);assert((await h.screenshot(path)).ok,name);report.screenshots.push(path);};
const log=async()=>readFile(logPath,'utf8');
/** 连接向导是独立窗口，挂载时 harness 绑定到它；它关闭后把 harness 绑回主窗口。 */
const mainWindow=async()=>{await h.sleep(400);const state:any=await h.request('POST','/zerowork/windows',{action:'snapshot'});assert(state.windows?.length>=1,'main window');assert((await h.request('POST','/zerowork/windows',{action:'select',window:state.windows[0].window}) as any).ok);await h.sleep(300);};
const preference=(s:string)=>/plugin_id\s*=\s*"fixture_probe"\s*\nkey\s*=\s*"host\.enabled"\s*\nvalue\s*=\s*"false"/.test(s);
const hostRow=async()=>h.waitFor(async()=>(await h.query('sidebar.host')).find((n:any)=>shown(n)&&textOf(n).includes('Q5 fixture host'))??null,12000);
const fixturePayload=(s:string)=>{const m=/^payload\s*=\s*(".*")$/m.exec(s);return m?.[1]??'';};

async function toFixtureDetail(){
 await nav.toCategory('plugins');await click('settings.plugin.fixture_probe.row');await nav.waitTitle('Fixture · 合成画面');
 return nav.reveal('settings.plugin.fixture_probe.status');
}
async function save(){await click('settings.save');await h.waitFor(async()=>(await absent('settings.footer'))||null,10000);await h.sleep(300);}

try{
 // ── 1. 第一次启动：建主机，关开关，待重启，“立即重启”（先取消、再确认） ──
 await launch();
 await click('sidebar.empty.new');await click('wizard.protocol');await click('wizard.protocol.fixture_probe');await visible('fixture.editor');
 await click('fixture.name');await h.key('a',{cmd:true});await h.type_('Q5 fixture host');
 await click('fixture.destination');await h.key('a',{cmd:true});await h.type_('synthetic.invalid');
 await click('wizard.save_only');await h.waitFor(async()=>(await absent('fixture.editor'))||null,10000);await mainWindow();
 const savedHosts=await readFile(hostsPath,'utf8');assert(savedHosts.includes('Q5 fixture host')&&savedHosts.includes('fixture_probe'));
 const payload=fixturePayload(savedHosts);assert(payload.length>0,'fixture payload is persisted');
 await hostRow();assert(await absent('sidebar.host.unavailable'),'enabled plugin hosts are not marked unavailable');
 report.checks.push('saved a fixture host through the connection wizard');
 await click('workspace.empty.local').catch(async()=>{await click('toolbar.new_session');await click('session.menu.local');});
 await visible('terminal.surface');
 // 本机终端里有前台进程：退出时出现关闭确认（用来验证“立即重启”走的是正常退出流程）。
 await click('terminal.surface');await h.type_('sleep 600');await h.key('return');await h.sleep(800);
 // 内置插件没有开关（Q5a）。
 await nav.toCategory('plugins');await click('settings.plugin.local.row');await h.sleep(400);
 assert(await absent('settings.plugin.local.enabled'),'builtin plugin has no enable switch');
 assert(await absent('settings.plugin.local.status'));
 await nav.back();await nav.waitTitle('协议插件');
 report.checks.push('builtin protocols (local) have no enable switch');
 // 已启用（Jm2fZ）。
 await toFixtureDetail();
 assert((await text('settings.plugin.fixture_probe.enabled.hint')).includes('插件代码仍随应用分发'));
 assert(await absent('settings.plugin.fixture_probe.notice'));
 await shot('01-detail-enabled');
 // 改了未保存（SH1gb）→ 撤销。
 await click('settings.plugin.fixture_probe.enabled');await visible('settings.footer');
 assert(!preference(await readFile(config,'utf8')),'toggling only edits the draft');
 await shot('02-detail-draft');
 await click('settings.revert');await h.waitFor(async()=>(await absent('settings.footer'))||null,8000);
 report.checks.push('toggle edits the draft through the Save Bar; revert restores the saved value');
 // 保存 → 待重启（NHr2L）。
 await click('settings.plugin.fixture_probe.enabled');await save();
 assert(preference(await readFile(config,'utf8')),'host.enabled = "false" is written to [[plugin_preferences]]');
 await visible('settings.plugin.fixture_probe.notice');await visible('settings.plugin.fixture_probe.restart');
 assert.equal(await text('settings.plugin.fixture_probe.state'),'重启后停用');
 assert((await text('settings.plugin.fixture_probe.notice')).includes('重启 ZeroWork 后停用'));
 await shot('03-detail-pending-disable');
 await nav.back();await nav.waitTitle('协议插件');
 assert.equal(await text('settings.plugin.fixture_probe.disabled'),'重启后停用');
 await shot('04-list-pending-disable');
 report.checks.push('save → pending restart: warning tag, notice, restart action; list row marked 重启后停用');
 // 本次运行内不受影响：fixture 主机仍可用（开关在下次启动生效）。
 assert(await absent('sidebar.host.unavailable'));
 // “立即重启”：有运行中的本机终端 → 关闭确认 → 取消。
 await click('settings.plugin.fixture_probe.row');await nav.waitTitle('Fixture · 合成画面');
 await click('settings.plugin.fixture_probe.restart');
 await visible('local.close.confirmation',15000);await shot('05-restart-close-confirmation');
 await click('local.close.cancel');await h.sleep(1200);
 assert.equal(app.exitCode,null,'cancelling the close confirmation keeps the app running');
 await h.waitFor(async()=>(await log()).includes('ZW_RELAUNCH {"requested":false}')||null,8000);
 assert(!(await log()).includes('ZW_RELAUNCH {"scheduled"'));
 report.checks.push('立即重启 goes through the normal close confirmation; cancelling keeps the app and withdraws the relaunch');
 // 再点并确认：正常退出（exit 0），登记了再启动。
 await nav.open();await toFixtureDetail();await click('settings.plugin.fixture_probe.restart');
 await visible('local.close.confirmation',15000);await click('local.close.accept');
 const code=await Promise.race([ended,h.sleep(20000).then(()=>'timeout')]);
 assert.equal(code,0,'restart quits normally (exit 0), no forced termination');
 const first=await log();assert(first.includes('ZW_RELAUNCH {"requested":true}')&&first.includes('ZW_RELAUNCH {"scheduled":true'),'relaunch registered after a completed quit');
 report.checks.push('confirmed restart exits normally and registers the relaunch');

 // ── 2. 第二次启动：已禁用 ──
 await launch();
 assert((await log()).includes('ZW_PLUGIN_LAUNCH {"id":"fixture_probe","enabled":false'),'the disabled plugin is not initialized or registered');
 // 侧栏（qQaos）：留在原位、标“已禁用”、没有连接按钮。
 const row=await hostRow();
 assert.equal(await text('sidebar.host.unavailable'),'已禁用');
 await h.clickAt(row.rect.x+row.rect.w/2,row.rect.y+row.rect.h/2);await h.sleep(300);
 assert(await absent('sidebar.host.connect_button'),'a disabled host has no connect button even when selected');
 const label=await visible('sidebar.host.unavailable');await h.mouseMove(label.rect.x+label.rect.w/2,label.rect.y+label.rect.h/2);
 const tip=await visible('sidebar.host.unavailable.tooltip',6000);
 assert(textOf(tip).includes('已禁用，不可连接')&&textOf(tip).includes('偏好设置 › 协议插件'));
 await h.sleep(1200);report.tooltip_debug={tip:(await h.query('sidebar.host.unavailable.tooltip')).map((n:any)=>({rect:n.rect,o:n.effective_opacity,text:textOf(n)})),info:(await h.query('sidebar.host.info')).map((n:any)=>({rect:n.rect,o:n.effective_opacity,text:textOf(n)}))};assert((await h.screenshot(join(out,`${theme}-06-sidebar-disabled-tooltip.png`))).ok);report.screenshots.push(join(out,`${theme}-06-sidebar-disabled-tooltip.png`));
 // Return 不发起连接（只打开同一个提示）。
 await h.key('return');await h.sleep(600);assert(await absent('workspace.plugin.content'),'Return does not connect a disabled host');
 report.checks.push('sidebar: disabled host stays in place, 已禁用 instead of connect, tooltip names the reason and the way back; Return does not connect');
 // 首页“已保存的连接”：同侧栏规则——行留在原位、变淡、标“已禁用”（Tooltip 写原因）、点击不连接。
 await h.mouseMove(700,300);await h.sleep(400);
 const saved=await h.waitFor(async()=>(await h.query('workspace.empty.saved.row')).find((n:any)=>shown(n)&&textOf(n).includes('Q5 fixture host'))??null,8000);
 assert.equal(await text('workspace.empty.saved.unavailable'),'已禁用');
 assert(!textOf(saved).includes('FIXTURE_PROBE'),'a disabled saved connection shows 已禁用 instead of its route');
 const savedLabel=await visible('workspace.empty.saved.unavailable');await h.mouseMove(savedLabel.rect.x+savedLabel.rect.w/2,savedLabel.rect.y+savedLabel.rect.h/2);
 const savedTip=await visible('workspace.empty.saved.unavailable.tooltip',6000);
 assert(textOf(savedTip).includes('已禁用，不可连接')&&textOf(savedTip).includes('偏好设置 › 协议插件'));
 await h.sleep(900);assert((await h.screenshot(join(out,`${theme}-06b-saved-disabled-tooltip.png`))).ok);report.screenshots.push(join(out,`${theme}-06b-saved-disabled-tooltip.png`));
 await h.clickAt(saved.rect.x+40,saved.rect.y+saved.rect.h/2);await h.sleep(800);
 assert(await absent('workspace.plugin.content'),'clicking a disabled saved connection does not connect');
 assert(await absent('plugin.challenge.modal'));
 await h.mouseMove(700,300);await h.sleep(300);
 report.checks.push('home saved connections: disabled host dimmed, 已禁用 with the same reason tooltip, click does not connect');
 // 右键菜单（RfJyL）。
 await h.clickAt(row.rect.x+row.rect.w/2,row.rect.y+row.rect.h/2,1,'right');await visible('context.menu.new_tab');
 const menu=async(id:string)=>(await h.query(id)).find(shown);
 // 原生 Button 的禁用态（harness 没有 disabled 字段，用原生禁用的不透明度判断）。
 await h.sleep(500);
 // harness 没有 disabled 字段：记录原生禁用态的不透明度，并用行为断言——点“新标签连接”不发起连接。
 const opacity=async(id:string)=>((await menu(id)) as any)?.effective_opacity??1;
 report.menu_opacity={new_tab:await opacity('context.menu.new_tab'),edit_host:await opacity('context.menu.edit_host'),delete_host:await opacity('context.menu.delete_host')};
 assert(textOf(await menu('context.menu.new_tab')).includes('已禁用'));
 await shot('07-sidebar-context-menu');
 {const n=await menu('context.menu.new_tab');await h.clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2);await h.sleep(800);}
 assert(await absent('workspace.plugin.content'),'新标签连接 is disabled: clicking it does not connect');
 assert(!(await log()).includes('PluginDisabled'),'the disabled item is not even dispatched');
 await h.key('escape');await h.sleep(200);
 await h.clickAt(row.rect.x+row.rect.w/2,row.rect.y+row.rect.h/2,1,'right');await visible('context.menu.edit_host');
 report.checks.push('context menu: 新标签连接 disabled and marked 已禁用; 编辑 / 删除 available');
 // 编辑：只改名称，载荷字节不变。
 await click('context.menu.edit_host');await visible('wizard.plugin.disabled',12000);
 await shot('08-wizard-edit-disabled');
 await click('wizard.plugin.disabled.name');await h.key('a',{cmd:true});await h.type_('Q5 fixture host renamed');
 assert(await absent('wizard.save'),'no save-and-open for a disabled plugin host');
 await click('wizard.save_only');await h.waitFor(async()=>(await absent('wizard.plugin.disabled'))||null,10000);await mainWindow();
 const renamed=await readFile(hostsPath,'utf8');
 assert(renamed.includes('Q5 fixture host renamed'),'general field saved');assert.equal(fixturePayload(renamed),payload,'protocol payload bytes unchanged');
 report.checks.push('edit keeps general fields only: rename saved, protocol payload unchanged');
 // 新建连接的协议下拉（YWqSG）：fixture 是禁用选项。
 await click('toolbar.new_session');await h.sleep(300);
 await click('session.menu.new_profile');await visible('wizard.protocol');await click('wizard.protocol');
 const option=await visible('wizard.protocol.fixture_probe');
 assert(textOf(option).includes('已禁用'),'disabled plugin listed as a disabled option');
 await shot('09-wizard-protocol-disabled-option');
 await h.clickAt(option.rect.x+option.rect.w/2,option.rect.y+option.rect.h/2);await h.sleep(300);
 assert(await absent('fixture.editor'),'the disabled option cannot be chosen');
 await h.key('escape');await h.sleep(200);await click('wizard.close').catch(async()=>{await h.key('w',{cmd:true});});await mainWindow();
 report.checks.push('new-connection protocol dropdown lists the disabled plugin as a disabled option');
 // 设置：列表行变淡、标“已禁用”；详情页已禁用提示（B0QXg6 / IeCzY）。
 await nav.toCategory('plugins');
 assert.equal(await text('settings.plugin.fixture_probe.disabled'),'已禁用');
 await shot('10-list-disabled');
 await click('settings.plugin.fixture_probe.row');await nav.waitTitle('Fixture · 合成画面');
 await nav.reveal('settings.plugin.fixture_probe.disabled');
 assert((await text('settings.plugin.fixture_probe.disabled')).includes('已禁用'));
 assert(await absent('settings.plugin.fixture_probe.restart'));
 await shot('11-detail-disabled');
 report.checks.push('settings: list row 已禁用; detail shows the disabled notice');
 // 打开开关并保存 → 待重启（重启后启用），“立即重启”无确认直接退出。
 await click('settings.plugin.fixture_probe.enabled');await save();
 assert(!preference(await readFile(config,'utf8')),'re-enabling deletes the host.enabled entry');
 assert.equal(await text('settings.plugin.fixture_probe.state'),'重启后启用');
 await shot('12-detail-pending-enable');
 await click('settings.plugin.fixture_probe.restart');
 assert.equal(await Promise.race([ended,h.sleep(20000).then(()=>'timeout')]),0,'restart quits normally');
 report.checks.push('re-enable → pending (重启后启用) → restart exits normally');

 // ── 3. 第三次启动：恢复 ──
 await launch();
 assert((await log()).includes('ZW_PLUGIN_LAUNCH {"id":"fixture_probe","enabled":true'));
 const back=await hostRow();assert(await absent('sidebar.host.unavailable'));
 assert(await absent('workspace.empty.saved.unavailable'),'re-enabled: the saved connection shows its route again');
 await nav.toCategory('plugins');assert(await absent('settings.plugin.fixture_probe.disabled'));
 await click('settings.plugin.fixture_probe.row');await nav.waitTitle('Fixture · 合成画面');
 assert(await absent('settings.plugin.fixture_probe.notice'));assert(await absent('settings.plugin.fixture_probe.disabled'));
 await shot('13-detail-restored');
 await nav.close();
 await h.clickAt(back.rect.x+back.rect.w/2,back.rect.y+back.rect.h/2);await h.sleep(300);
 await click('sidebar.host.connect_button');
 await h.waitFor(async()=>{for(const id of ['workspace.plugin.content','plugin.challenge.modal','fixture.canvas'])if((await h.query(id)).some(shown))return id;return null;},15000);
 await shot('14-restored-connect');
 report.checks.push('after re-enabling and restarting, everything is restored and the saved host connects');
 report.status='passed';
}catch(e){report.status='failed';report.error=String((e as any)?.stack??e);process.exitCode=1;await shot('failure').catch(()=>{});await writeFile(join(out,`${theme}-failure-tree.json`),JSON.stringify(await h.tree({visibleOnly:true}).catch(()=>null),null,1)).catch(()=>{});}
finally{await kill();await rm(iso,{recursive:true,force:true});report.private_data_removed=true;await writeFile(join(out,`report-${theme}.json`),JSON.stringify(report,null,2));console.log(JSON.stringify({status:report.status,checks:report.checks.length,error:report.error}));}
