/** Execution/retention controls through the actual main window; isolated data only. */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {spawn} from 'node:child_process';
import {mkdtemp,mkdir,writeFile,readFile,open,realpath} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {aiToggleId} from './ai_entry.ts';
import {settingsNav} from './settings_nav.ts';
const prefix=resolve(process.env.ZW_EXECUTION_TEST_PREFIX??'/tmp/zw-execution-settings-native');
const h=await import(join(prefix,'share/zenit/harness/client.ts'));
const out=resolve(process.argv[2]??'/tmp/zw-execution-settings-evidence');await mkdir(out,{recursive:true});
const report:any={status:'running',binary:join(prefix,'bin/zerowork'),binary_sha256:createHash('sha256').update(await readFile(join(prefix,'bin/zerowork'))).digest('hex'),cases:[],checks:[],limits:['File-RPC synthetic input with real Metal screenshots; physical IME and VoiceOver are not covered.','No command/send actions are invoked; startup model discovery may run. Runtime execution policy enforcement is tested separately.']};
const modes=[['auto','自行判断'],['ask','每次询问'],['isolated_exec','批处理'],['attached_pty','附加现有 PTY'],['new_pty','新建 PTY']];
const transparencies=(process.env.ZW_EXECUTION_TRANSPARENCIES??'0').split(',').map(Number);
assert(transparencies.length>0&&transparencies.every(value=>Number.isFinite(value)&&value>=0&&value<=100),'valid material transparency matrix');
const flat=(n:any):any[]=>Array.isArray(n)?n.flatMap(flat):n?[n,...(n.children??[]).flatMap(flat)]:[];
const shown=(n:any)=>n&&n.hidden!==true&&n.visible!==false&&(n.effective_opacity??1)>0&&n.rect?.w>0&&n.rect?.h>0;
const visible=(id:string)=>h.waitFor(async()=>(await h.query(id)).find(shown)??null,12000);
// The menu's entry transition has finished: fully opaque (checkMenu then asserts exactly 1; a tolerance here let an
// animation tail of 0.9997 through to that assertion).
const settled=(id:string)=>h.waitFor(async()=>(await h.query(id)).find((node:any)=>shown(node)&&(node.effective_opacity??1)===1)??null,5000);
const click=async(id:string)=>{await visible(id);assert((await h.clickTestId(id)).ok,id);await h.sleep(100)};
const text=async(id:string)=>flat(await visible(id)).map(n=>n.text??'').join('');
async function edit(id:string,value:string){await click(id);await h.key('a',{cmd:true});if(value)await h.type_(value);else await h.key('backspace');await h.sleep(150)}
async function capture(item:any,name:string){await h.sleep(150);const file=join(out,name+'.png');assert((await h.screenshot(file)).ok);const png=await readFile(file);item.captures.push({file,pixels:[png.readUInt32BE(16),png.readUInt32BE(20)]});await writeFile(join(out,name+'.json'),JSON.stringify({panel:await h.query('ai.panel'),controls:await h.query('ai.composer.controls'),menu:await h.query('ai.execution.menu'),retention:await h.query('ai.retention.menu'),permission:await h.query('ai.permission.menu'),attachment:await h.query('ai.attachment.menu'),model:await h.query('ai.model.menu'),usage:await h.query('ai.usage.menu')},null,2))}
// 设置窗口是两级导航（settings_nav.ts）：字段在「AI 辅助 → 行为与权限」子页，用 toField 到达；窗口无关闭按钮，nav.close() 用 Cmd+W。
const nav=settingsNav();
async function chooseSetting(key:string,index:number){await nav.click('settings.field.'+key);await h.key('home');for(let i=0;i<index;i++)await h.key('down');await h.key('return');await h.sleep(150)}
// ── 现行契约（cfbcdf60「输入区按 AI Chat 重设计还原」之后）──────────────────────────────────────────────
// 工具行 src/features/ai/composer/view/ai_composer_controls.yix：附件（图标按钮）· 执行权限 · 运行方式 | 用量 · 模型 · 发送/停止，全是原生 ghost sm Button。
// 收缩规则（ai_composer_controls_view.zig 的 keepRow 布局钩子，bugfix-2 / Pencil ⑤）：行宽不够时先截断模型名，再把“执行权限”收成图标按钮
// ai.composer.permission.compact，再把“运行方式”收成 ai.composer.execution.compact（Tooltip 写“名称 · 当前值”）；同一时刻每组只显示一个。
// 三个选择菜单是原生 ContextMenu（无自绘标题 / 关闭按钮 / 视口 / 效果说明——旧 ai.execution.title、.header.icon、.close、.viewport、.effect、
// 「跟随全局」运行方式行均已删除）：组标题是 MenuHeader，“任务会话处理”是带说明行（全局值 · 只影响之后的执行）的子菜单行。
// 菜单宽度：ai_composer_controls_styles.zig width()：附件 240、权限 280、运行方式 300、模型 320、用量 288。
const executionRows=['ai.execution.auto','ai.execution.ask','ai.execution.isolated_exec','ai.execution.attached_pty','ai.execution.new_pty','ai.execution.retention'];
const retentionRows=['ai.retention.inherit','ai.retention.auto_idle','ai.retention.ask','ai.retention.keep'];
const menuWidth:Record<string,number>={attachment:240,permission:280,execution:300,model:320,usage:288};
// 只看真正显示的节点：收起的按钮在隐藏的 Tooltip 包装里，/query 仍返回它上一次布局的矩形，所以显隐以 visibleOnly 的树为准。
const visibleIds=async(root:string)=>new Set(flat(await h.tree({root,visibleOnly:true})).map((n:any)=>n.test_id).filter(Boolean));
async function control(kind:'permission'|'execution'){const ids=await visibleIds('ai.composer.controls'),full='ai.composer.'+kind,compact=full+'.compact';assert.notEqual(ids.has(full),ids.has(compact),kind+' shows exactly one of its full / icon-only control');return ids.has(full)?full:compact}
async function controlValue(kind:'permission'|'execution'){
 const id=await control(kind);if(!id.endsWith('.compact'))return text(id);
 const button=await visible(id);await h.mouseMove(button.rect.x+button.rect.w/2,button.rect.y+button.rect.h/2);
 const value=await h.waitFor(async()=>{const tip=flat(await h.tree({root:id+'.tooltip',visibleOnly:true}).catch(()=>null)).map((n:any)=>n.text??'').join('');return tip.includes(' · ')?tip:null},5000);
 await h.mouseMove(2,2);return value;
}
async function openMenu(kind:string){const anchor=kind==='permission'||kind==='execution'?await control(kind as any):'ai.composer.'+kind;await click(anchor);return settled('ai.'+kind+'.menu')}
async function closeMenus(){for(const id of ['ai.retention.menu','ai.execution.menu','ai.permission.menu','ai.attachment.menu','ai.model.menu','ai.usage.menu'])if((await h.query(id)).some(shown)){await h.key('escape');await h.waitFor(async()=>!(await h.query(id)).some(shown)||null,5000)}}
const inside=(r:any,box:any,label:string)=>assert(r.x>=box.x-.5&&r.y>=box.y-.5&&r.x+r.w<=box.x+box.w+.5&&r.y+r.h<=box.y+box.h+.5,label+` ${JSON.stringify(r)} outside ${JSON.stringify(box)}`);
// 原生菜单的自洽性：在窗口内、不透明、行都在面板内且左缘 / 宽度一致（同类行等宽、对齐、不溢出）。
function checkMenu(surface:any,w:number,height:number,label:string,expectRows?:string[]){
 inside(surface.rect,{x:0,y:0,w,h:height},label+' menu bounds');assert.equal(surface.effective_opacity??1,1,label+' menu opaque');
 const rows=flat(surface).filter((n:any)=>n.component==='MenuItem'&&shown(n));assert(rows.length>0,label+' has rows');
 if(expectRows)assert.deepEqual(rows.map((n:any)=>n.test_id),expectRows,label+' rows');
 for(const row of rows){inside(row.rect,surface.rect,label+' row '+row.test_id+' inside its panel');assert(Math.abs(row.rect.x-rows[0].rect.x)<.5&&Math.abs(row.rect.w-rows[0].rect.w)<.5,label+' row '+row.test_id+' shares the panel column '+JSON.stringify([row.rect,rows[0].rect]));for(const t of flat(row).filter((n:any)=>n.tag==='text'&&shown(n)))inside(t.rect,row.rect,label+' text "'+t.text+'" inside row '+row.test_id)}
 return rows;
}
const headers=(surface:any)=>flat(surface).filter((n:any)=>n.component==='MenuHeader'&&shown(n)).map((n:any)=>flat(n).map((c:any)=>c.text??'').join(''));
matrix:for(const theme of ['dark','light','sauber'])for(const transparency of transparencies){
 const caseName=transparencies.length===1&&transparency===0?theme:`${theme}-t${transparency}`;
 const modelName=transparency===75?'provider/longest-supported-model-identifier':'policy-fixture';
 const iso=await realpath(await mkdtemp('/tmp/zw-execution-settings-')),data=join(iso,'data'),rpc=join(iso,'rpc');await mkdir(data);await mkdir(rpc);process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
 const configPath=join(data,'config.toml');await writeFile(configPath,`[meta]\nconfig_revision=1\n[ui]\ntheme="${theme}"\nfont_family="Menlo"\nfont_size=14\n[ui.materials]\nblur_px=0\n[ui.materials.background]\ntransparency=${transparency}\n[ai]\ndefault_provider="fixture"\npermission_mode="confirm"\n[[ai.providers]]\nid="fixture"\nkind="openai_compat"\nendpoint="http://127.0.0.1:9/v1/chat/completions"\nenabled=true\n[[ai.providers.models]]\nname="${modelName}"\ncontext_window=200000\ndefault=true\n`);
 // 860×480 会触发一次性的“窗口较窄，可以收起侧栏”提示（sidebar_memory.zig，底部居中 8 s，盖住浮动面板的工具行）；它有自己的用例（sidebar_layout_r3_native），这里预置为已提示过。
 await writeFile(join(data,'ui-state.json'),JSON.stringify({narrow_sidebar_hint_shown:true}));
 const environment={...process.env,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1',ZENIT_E2E_FILE_RPC_DIR:rpc,ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',OPENAI_API_KEY:'',ANTHROPIC_API_KEY:''};
 for(const name of ['ZEROWORK_AI_MOCK','ZEROWORK_AI_ENDPOINT','ZEROWORK_AI_MODEL','ZEROWORK_AI_PROVIDER'])delete environment[name];
 const log=await open(join(out,caseName+'.log'),'w');const app=spawn(join(prefix,'bin/zerowork'),[],{env:environment,stdio:['ignore',log.fd,log.fd]});
 const ended=new Promise<void>(r=>app.once('close',()=>r()));const item:any={theme,transparency,status:'running',isolated:iso,captures:[],geometry:[]};report.cases.push(item);
 try{
  await h.waitForServerReady(60000);await h.resizeWindow(1440,900);await click('workspace.empty.local');await visible('terminal.surface');await click(await aiToggleId());await visible('ai.composer.controls');await h.mouseMove(2,2);
  for(const [mode,label]of modes){await openMenu('execution');await click('ai.execution.'+mode);await h.waitFor(async()=>!(await h.query('ai.execution.menu')).some(shown)||null,5000);await h.waitFor(async()=>(await controlValue('execution')).includes(label)||null,8000);}
  assert((await controlValue('permission')).includes('确认后执行'),'run mode choices never change the permission');
  {const menu=await openMenu('execution');await click('ai.execution.retention');await settled('ai.retention.menu');await click('ai.retention.keep');await h.waitFor(async()=>!(await h.query('ai.retention.menu')).some(shown)||null,5000);await closeMenus();}
  await openMenu('execution');assert((await text('ai.execution.retention')).includes('保留任务会话'),'retention row notes the chosen value');await capture(item,caseName+'-menu-wide');await closeMenus();
  await openMenu('execution');await click('ai.execution.attached_pty');await h.waitFor(async()=>!(await h.query('ai.execution.menu')).some(shown)||null,5000);
  // 浮动面板在 1440×900 与 860×480，以及最大化面板在 1440×900（宽行：两个选择都是完整按钮）。
  for(const [w,height,maximized] of [[1440,900,false],[860,480,false],[1440,900,true]] as [number,number,boolean][]){
   await h.resizeWindow(w,height);if(maximized){await click('ai.maximize');}await h.mouseMove(2,2);
   const sizeName=`${w}${maximized?'-max':''}`;
   const row=await h.waitFor(async()=>{const r=(await h.query('ai.composer.controls')).find(shown);return r&&r.rect.x+r.rect.w<=w+.5&&r.rect.y+r.rect.h<=height+.5?r:null},5000);
   const ids=['ai.composer.attachment',await control('permission'),await control('execution'),'ai.composer.usage','ai.composer.model','ai.composer.trailing'];const nodes=await Promise.all(ids.map(visible));
   const center=row.rect.y+row.rect.h/2;
   for(let i=0;i<nodes.length;i++){const r=nodes[i].rect;inside(r,row.rect,ids[i]+' inside the tool row');assert(Math.abs(r.y+r.h/2-center)<.5,ids[i]+' centred on the tool row');if(i)assert(nodes[i-1].rect.x+nodes[i-1].rect.w<=r.x+.5,'controls overlap: '+ids[i-1]+' / '+ids[i]);}
   // 收缩顺序：运行方式收起时执行权限必已收起。
   if(ids[2].endsWith('.compact'))assert(ids[1].endsWith('.compact'),'permission collapses before run mode');
   if(maximized){assert.equal(ids[1],'ai.composer.permission','a wide row shows the full permission control');assert.equal(ids[2],'ai.composer.execution','a wide row shows the full run mode control');}
   item.geometry.push({size:[w,height],maximized,controls:nodes.map((n:any,i:number)=>({id:ids[i],rect:n.rect}))});
   assert((await controlValue('execution')).includes('附加现有 PTY'),'run mode value survives the resize');
   if(transparency===transparencies[0]){
    {const s=await openMenu('attachment');assert.equal(s.rect.w,menuWidth.attachment);checkMenu(s,w,height,'attachment',['ai.attachment.image','ai.attachment.local_text','ai.attachment.remote_file','ai.attachment.paste_image']);await capture(item,caseName+'-attachment-'+sizeName);await closeMenus();}
    {const s=await openMenu('permission');assert.equal(s.rect.w,menuWidth.permission);checkMenu(s,w,height,'permission',['ai.permission.confirm','ai.permission.auto']);assert.equal(headers(s)[0],'执行权限');await capture(item,caseName+'-permission-'+sizeName);await closeMenus();}
    {const s=await openMenu('model');assert.equal(s.rect.w,menuWidth.model);inside(s.rect,{x:0,y:0,w,h:height},'model popover bounds');assert.equal(s.effective_opacity??1,1);inside((await visible('ai.model.option')).rect,s.rect,'model option inside its popover');await capture(item,caseName+'-model-'+sizeName);await closeMenus();}
    {const s=await openMenu('usage');assert.equal(s.rect.w,menuWidth.usage);inside(s.rect,{x:0,y:0,w,h:height},'usage popover bounds');assert.equal(s.effective_opacity??1,1);for(const id of ['ai.usage.summary','ai.usage.track','ai.usage.compaction.start'])inside((await visible(id)).rect,s.rect,id+' inside the usage popover');await capture(item,caseName+'-usage-'+sizeName);await closeMenus();}
   }
   await capture(item,caseName+'-composer-'+sizeName);
   const menu=await openMenu('execution');assert.equal(menu.rect.w,menuWidth.execution);checkMenu(menu,w,height,'execution',executionRows);assert.equal(headers(menu)[0],'当前对话运行方式');
   // 原“效果说明”现为“任务会话处理”行的说明行：全局值 · 只影响之后的执行（ai_composer_controls_view.zig menuRows .execution）。
   assert(/全局：.+ · 只影响之后的执行/.test(await text('ai.execution.retention')),'retention row explains its scope');
   await capture(item,caseName+'-menu-'+sizeName);
   await click('ai.execution.retention');const retention=await settled('ai.retention.menu');const subRows=checkMenu(retention,w,height,'retention',retentionRows);
   // 原生子菜单贴着父行展开（zenit Menu 子菜单以父行为锚，可压住父面板 4px 内边距），不能盖住父菜单的任何行。
   {const parentRow=(await visible('ai.execution.retention')).rect;assert(retention.rect.x+retention.rect.w<=parentRow.x+.5||retention.rect.x>=parentRow.x+parentRow.w-.5,'nested retention menu opens beside its row, not over the parent rows');}
   assert.equal(subRows.length,4);await capture(item,caseName+'-retention-layer-'+sizeName);await closeMenus();
   if(maximized)await click('ai.maximize');
  }
  await h.resizeWindow(1440,900);await h.mouseMove(2,2);
  await openMenu('execution');await click('ai.execution.new_pty');await h.waitFor(async()=>!(await h.query('ai.execution.menu')).some(shown)||null,5000);
  // Global draft save affects inherit and preserves an explicit conversation override.
  await nav.toField('execution_mode');await chooseSetting('execution_mode',2);await nav.click('settings.save');await h.waitFor(async()=>/execution_mode\s*=\s*"isolated_exec"/.test(await readFile(configPath,'utf8'))||null,10000);await capture(item,caseName+'-settings-mode-saved');await nav.close();
  assert((await controlValue('execution')).includes('新建 PTY'),'explicit override preserved after global save');
  // v0.3.0（3cc4a699）删除了运行方式的「跟随全局」项（菜单行恰为五种模式 + 任务会话处理，checkMenu 已逐项比对）；菜单默认勾选全局值，这里按同样方式显式选回全局保存的批处理。
  {const s=await openMenu('execution');checkMenu(s,1440,900,'execution',executionRows);await click('ai.execution.isolated_exec');await h.waitFor(async()=>(await controlValue('execution')).includes('批处理')||null,8000);}
  await nav.toField('session_retention');await chooseSetting('session_retention',2);await nav.click('settings.save');await h.waitFor(async()=>/session_retention\s*=\s*"keep"/.test(await readFile(configPath,'utf8'))||null,10000);await capture(item,caseName+'-settings-retention-saved');await nav.close();
  await nav.toField('execution_mode');assert((await text('settings.field.execution_mode')).includes('批处理'));await nav.toField('session_retention');assert((await text('settings.field.session_retention')).includes('保留任务会话'));await nav.close();
  {await openMenu('execution');assert((await text('ai.execution.retention')).includes('全局：保留任务会话'),'retention row reflects the saved global value');await closeMenus();}
  const saved=await readFile(configPath,'utf8');assert(/permission_mode\s*=\s*"confirm"/.test(saved));assert.equal(/name\s*=\s*"([^"]+)"/.exec(saved)?.[1],modelName);assert.equal(/theme\s*=\s*"([^"]+)"/.exec(saved)?.[1],theme);
  assert((await h.request('POST','/zerowork/windows',{action:'quit'})).ok,'normal App Quit request');
  await Promise.race([ended,new Promise((_,reject)=>setTimeout(()=>reject(new Error('normal App Quit timed out')),15000))]);
  item.exit={code:app.exitCode,signal:app.signalCode,normal:app.exitCode===0&&app.signalCode===null};assert(item.exit.normal,'normal App Quit exits 0');item.status='passed';
 }catch(error){item.status='failed';item.error=String(error);await capture(item,caseName+'-failure').catch(()=>{});report.status='failed';process.exitCode=1;break matrix}
 finally{if(app.exitCode===null&&app.signalCode===null){app.kill('SIGTERM');item.cleanup_signal='SIGTERM';}await ended;await log.close();await writeFile(join(out,'report.json'),JSON.stringify(report,null,2))}
}
if(report.status!=='failed'){report.status='passed_pending_pixel_review';report.checks=['All five modes are acknowledged independently from permissions; retention is acknowledged; the removed execution inherit row stays absent and an explicit mode follows the saved global value.','Composer ordering, menu bounds and fixed original controls remain reachable in all three themes at 1440×900 and 860×480.','Global mode and retention save/reopen through the native Settings transaction; explicit mode override survives global changes.']}
await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));console.log(JSON.stringify({status:report.status,report:join(out,'report.json')}));
