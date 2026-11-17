/** Isolated native Metal acceptance of the v0.2 compact UI corrections, against the current shell.
 * node e2e/v02_ui_fixes_native.ts --binary BIN --sha SHA --out DIR [--scope full|sidebar|settings] [--themes dark,light,sauber]
 *
 * Each theme runs twice: an empty registry and five saved hosts (written inline; the old evidence-directory fixture
 * docs/DESIGN/evidence/2026-10-24-v02-ui-fixes/quick-connect/fixture-hosts.toml was never tracked).
 * Contract (values with their source):
 *  - sidebar bottom: the new-host action is 34 high (sidebar_styles.zig `footer` / `footerSlot`). Saved hosts: it sits in
 *    `sidebar.bottom` and ends at the sidebar column's bottom padding, 12 (shell/styles.yss `sidebar_full`: padding
 *    space300 space200). Empty: `sidebar.empty` pads 12 at the bottom (sidebar_view.zig `empty_style`) and the slot adds
 *    a 2pt bottom margin (sidebar_styles.zig `footerSlot(true)`), so 14. The sidebar stays expanded in a narrow window
 *    (191f6aa6), so both window sizes check it. The old decorative sidebar.footer.frame (removed in b319da83) must stay gone.
 *  - settings is its own window (its size does not follow the main window). The page header `settings.page.intro` floats
 *    over the content (64 high, settings/view/styles.yss `page_bar`); the viewport fills the page (`page.yix`); the body's
 *    top padding keeps the first pane below the header at rest (`PageBody`: 72 for panes, 68 for an overview). A clean
 *    page shows no Save Bar, also after scrolling. 外观与主题 › 主题 overflows and scrolls. The font family chooser is the
 *    native searchable Select panel `settings.font.options`.
 *  - quick connect (quick_connect_styles.zig): panel 520 wide; header 48 + body padding 8 put the 488 × 40 query at
 *    (16, 56); the clear button (24 × 24, `clearPlacement` top 8 / right 16) shows whenever the query is not blank
 *    (quick_connect_view.zig `clear.setDisplay(searching)`); saved rows are 44 high; the footer's actions are native md
 *    Buttons (32 high, control_shell/styles.yss), the primary flush with the body's right padding 16, and the panel
 *    ends 16 below the footer. No match: the save action hides and the panel stays inside the window. Clear refocuses
 *    the query.
 *  - closing the window hides it and keeps the app (and the window) alive; an application quit then exits with 0.
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdir,mkdtemp,open,readFile,writeFile,rm,chmod} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {request,waitForServerReady,waitFor,query,clickAt,key,type_,resizeWindow,screenshot,sleep,scrollAt,focused,tree,screenPos} from '../vendor/zenit/e2e/client.ts';
import {settingsNav} from './settings_nav.ts';
const nav=settingsNav();
const opts:Record<string,string>={};for(let i=2;i<process.argv.length;i+=2){assert(['--binary','--sha','--out','--scope','--themes'].includes(process.argv[i])&&process.argv[i+1]);opts[process.argv[i]]=process.argv[i+1];}
const scope=opts['--scope']??'full';assert(['full','sidebar','settings'].includes(scope));const binary=resolve(opts['--binary']),out=resolve(opts['--out']);await mkdir(out,{recursive:true});
const themes=(opts['--themes']??'dark,light,sauber').split(',');assert(themes.every(t=>['dark','light','sauber'].includes(t)),'--themes: dark,light,sauber');
assert.equal(createHash('sha256').update(await readFile(binary)).digest('hex'),opts['--sha']);
const report:any={status:'running',scope,themes,binary,sha256:opts['--sha'],runs:[],limits:['Real Metal window pixels; public synthetic Harness input, no physical keyboard/IME claim.','Display-only saved host fixtures; no asset connection or AI requests.']};
const shown=(n:any)=>n?.rect&&n.visible!==false&&n.hidden!==true&&(n.effective_opacity??1)>0&&n.rect.w>0&&n.rect.h>0;
const presented=(n:any)=>shown(n)&&(n.effective_opacity??1)===1&&(n.world_transform?.[0]??1)===1&&(n.world_transform?.[3]??1)===1;
function flat(n:any):any[]{return n?[n,...(n.children??[]).flatMap(flat)]:[];}
const textOf=(n:any)=>flat(n).map((v:any)=>typeof v.text==='string'?v.text:'').join('');
const near=(a:number,b:number,label:string)=>assert(Math.abs(a-b)<=0.6,`${label}: ${a} != ${b}`);
const right=(r:any)=>r.x+r.w,bottom=(r:any)=>r.y+r.h;
// Five saved hosts; three match “Production”.
const savedNames=['Production web','Production db','Production files','Staging api','Dev box'];
let fixture='[registry]\nschema_version=2\nrevision=1\nnext_connection_id=6\nnext_group_id=1\n';
savedNames.forEach((name,i)=>fixture+=`[[hosts]]\nconnection_id=${i+1}\nrevision=1\nprotocol="${i===2?'sftp':'ssh'}"\nauth_mode="password"\nname="${name}"\nhost="192.0.2.${11+i}"\nport=22\nuser="deploy"\n`);
const SIDEBAR_BUTTON=34,SIDEBAR_BOTTOM_SAVED=12,SIDEBAR_BOTTOM_EMPTY=12+2;
const QUICK_WIDTH=520,QUICK_INPUT={x:16,y:56,w:488,h:40},QUICK_CLEAR={x:464,y:64,w:24,h:24},QUICK_ROW=44,BUTTON_MD=32,QUICK_PAD=16;
const PAGE_BAR=64,PANES_TOP=72,OVERVIEW_TOP=68;
let failure:any;
runs: for(const theme of themes)for(const empty of (scope==='settings'?[false]:[true,false])){
 const iso=await mkdtemp(join(tmpdir(),'zw-ui-fixes-'));await chmod(iso,0o700);const rpc=join(iso,'rpc'),data=join(iso,'data');await mkdir(rpc,{mode:0o700});await mkdir(data,{mode:0o700});
 await writeFile(join(data,'config.toml'),`[meta]\nconfig_revision=1\n[ui]\ntheme="${theme}"\nfont_family="Menlo"\nfont_size=14\n`,{mode:0o600});
 if(!empty)await writeFile(join(data,'hosts.toml'),fixture,{mode:0o600});
 process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;const label=`${theme}-${empty?'empty':'saved'}`,log=await open(join(out,label+'.app.log'),'w');
 const app=spawn(binary,[],{env:{...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1',ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',OPENAI_API_KEY:'',ANTHROPIC_API_KEY:''},stdio:['ignore',log.fd,log.fd]});
 const ended=new Promise<void>(done=>app.once('close',()=>done()));const rec:any={theme,empty,pid:app.pid,status:'running',captures:[],checks:[]};report.runs.push(rec);
 async function visible(id:string){return waitFor(async()=>(await query(id)).find(shown)??null,12000).catch(()=>assert.fail(`${label}: ${id} visible`));}
 async function click(id:string){const n=await waitFor(async()=>(await query(id)).find(presented)??null,12000).catch(()=>assert.fail(`${label}: ${id} presented`));assert((await clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok);}
 async function absent(id:string){await waitFor(async()=>!(await query(id)).some(shown)||null,10000).catch(()=>assert.fail(`${label}: ${id} absent`));}
 /** Replace the field's text and wait (bounded) until the field shows it. */
 async function set(id:string,value:string){await click(id);assert((await key('a',{cmd:true})).ok);assert((await type_(value)).ok);await waitFor(async()=>textOf((await query(id)).find(shown)).includes(value)||null,5000).catch(()=>assert.fail(`${id} reads ${value}`));}
 async function capture(name:string,ids:string[]){const nodes=Object.fromEntries(await Promise.all(ids.map(async id=>[id,await query(id)])));await writeFile(join(out,name+'.json'),JSON.stringify(nodes,null,2));assert((await screenshot(join(out,name+'.png'))).ok);rec.captures.push(name);console.log(name);}
 async function shellSize(w:number,h:number){assert((await resizeWindow(w,h)).ok);await waitFor(async()=>{const r=await screenPos('workspace.shell');return Math.abs(r.w-w)<1&&Math.abs(r.h-h)<1||null},5000);}
 async function sidebar(size:string){
  const root=await visible('workspace.sidebar'),button=await visible(empty?'sidebar.empty.new':'sidebar.footer.new');
  near(button.rect.h,SIDEBAR_BUTTON,`${size} sidebar button height`);
  near(bottom(root.rect)-bottom(button.rect),empty?SIDEBAR_BOTTOM_EMPTY:SIDEBAR_BOTTOM_SAVED,`${size} sidebar bottom`);
  assert(!(await query(empty?'sidebar.footer.new':'sidebar.empty.new')).some(shown),'only the matching new-host action shows');
  // Regression (tools/arch/test_ids.e2e_ignore.txt): the new-host action has no separate bordered container around it
  // any more (1a02cc05; the decorative node was removed in b319da83) — it must not come back.
  assert.equal((await query('sidebar.footer.frame')).filter(shown).length,0,'no bordered frame around the sidebar footer action');
  rec.checks.push({sidebar:{size,root:root.rect,button:button.rect}});
 }
 async function settings(){
  // Settings is a separate window: one pass, whatever the main window's size.
  await nav.toCategory('ai');
  const content=await visible('settings.content'),vp=await visible('settings.viewport'),intro=await visible('settings.page.intro');
  near(vp.rect.y,content.rect.y,'viewport starts at the page top (header floats over it)');near(vp.rect.h,content.rect.h,'viewport fills the page');
  near(intro.rect.y,content.rect.y,'page header at the page top');near(intro.rect.h,PAGE_BAR,'page header height');
  const overview=(await tree({root:'settings.viewport',visibleOnly:true})).children?.[0];assert(overview?.rect,'overview body');
  assert.equal((await query('settings.footer')).filter(shown).length,0,'clean settings show no Save Bar');
  await capture(`${theme}-settings-ai`,['settings.content','settings.viewport','settings.page.intro','settings.footer']);
  // 外观与主题 › 主题 overflows the settings window: the body really scrolls and still shows no Save Bar.
  await nav.toSub('appearance','theme');await visible('settings.appearance.app_icon');
  const body=async()=>(await tree({root:'settings.viewport',visibleOnly:true})).children[0].rect;
  const start=await body(),view=(await visible('settings.viewport')).rect;
  assert(start.h>view.h+20,`theme page overflows the viewport: ${start.h} vs ${view.h}`);
  assert((await scrollAt(view.x+view.w/2,view.y+view.h/2,0,-1500)).ok);
  const scrolled=await waitFor(async()=>{const r=await body();return r.y<start.y-20?r:null},5000).catch(()=>assert.fail('Settings body actually scrolls'));
  assert.equal((await query('settings.footer')).filter(shown).length,0,'scrolling does not show a Save Bar');
  rec.checks.push({scroll_before:start,scroll_after:scrolled});
  await capture(`${theme}-settings-theme-scrolled`,['settings.content','settings.viewport','settings.footer']);
  await nav.toSub('appearance','font');const section=await visible('settings.appearance.font');await visible('settings.field.font_family');
  near(section.rect.y-(await visible('settings.viewport')).rect.y,PANES_TOP,'the first pane starts below the floating header');
  await capture(`${theme}-settings-font`,['settings.appearance.font','settings.field.font_family','settings.footer']);
  await click('settings.field.font_family');await visible('settings.font.options');await capture(`${theme}-settings-font-chooser`,['settings.font.options']);
  assert((await key('escape')).ok);await absent('settings.font.options');
  assert((await key('escape')).ok);await absent('settings.panel');
  rec.checks.push({settings:{content:content.rect,viewport:vp.rect,intro:intro.rect,overview_top:overview.rect.y,font_pane:section.rect}});
  const firstBlock=overview.children?.find((n:any)=>shown(n));assert(firstBlock,'overview has content');
  near(firstBlock.rect.y-vp.rect.y,OVERVIEW_TOP,'the overview starts below the floating header');
 }
 async function quick(size:string){
  assert((await key('k',{cmd:true})).ok);await visible('quick.connect');await set('quick.query','Production');
  await waitFor(async()=>(await query('quick.saved.row')).filter(shown).length===3||null,5000).catch(()=>assert.fail('three saved rows match Production'));
  let panel=await visible('quick.connect'),input=await visible('quick.query');
  near(panel.rect.w,QUICK_WIDTH,'quick width');
  near(input.rect.x-panel.rect.x,QUICK_INPUT.x,'quick input x');near(input.rect.y-panel.rect.y,QUICK_INPUT.y,'quick input y');near(input.rect.w,QUICK_INPUT.w,'quick input width');near(input.rect.h,QUICK_INPUT.h,'quick input height');
  let clear=await visible('quick.clear');
  near(clear.rect.x-panel.rect.x,QUICK_CLEAR.x,'clear x');near(clear.rect.y-panel.rect.y,QUICK_CLEAR.y,'clear y');near(clear.rect.w,QUICK_CLEAR.w,'clear width');near(clear.rect.h,QUICK_CLEAR.h,'clear height');
  for(const row of (await query('quick.saved.row')).filter(shown))near(row.rect.h,QUICK_ROW,'saved row height');
  let save=await visible('quick.save'),submit=await visible('quick.submit');
  near(save.rect.h,BUTTON_MD,'save is a native md button');near(submit.rect.h,BUTTON_MD,'submit is a native md button');near(save.rect.y,submit.rect.y,'footer actions share a line');
  near(right(submit.rect),right(panel.rect)-QUICK_PAD,'submit flush with the body padding');near(save.rect.x,panel.rect.x+QUICK_PAD,'save flush with the body padding');
  const footer=await visible('quick.footer');near(bottom(panel.rect)-bottom(footer.rect),QUICK_PAD,'panel ends one body padding below the footer');
  await capture(`${theme}-quick-saved-${size}`,['quick.connect','quick.query','quick.clear','quick.saved.row','quick.save','quick.submit']);
  await set('quick.query','no-such-host');await absent('quick.save');await waitFor(async()=>(await query('quick.saved.row')).filter(shown).length===0||null,5000);
  panel=await visible('quick.connect');clear=await visible('quick.clear');submit=await visible('quick.submit');
  near(clear.rect.x-panel.rect.x,QUICK_CLEAR.x,'no-match clear x');near(clear.rect.y-panel.rect.y,QUICK_CLEAR.y,'no-match clear y');
  near(submit.rect.h,BUTTON_MD,'no-match submit height');near(right(submit.rect),right(panel.rect)-QUICK_PAD,'no-match submit flush right');
  near(bottom(panel.rect)-bottom((await visible('quick.footer')).rect),QUICK_PAD,'no-match panel ends one padding below the footer');
  const root=await visible('workspace.shell');assert(panel.rect.x>=0&&panel.rect.y>=0&&right(panel.rect)<=root.rect.w&&bottom(panel.rect)<=root.rect.h,'quick connect stays inside the window');
  await capture(`${theme}-quick-no-match-${size}`,['quick.connect','quick.query','quick.clear','quick.save','quick.submit']);
  await click('quick.clear');await waitFor(async()=>(await query('quick.saved.row')).filter(shown).length===savedNames.length||null,5000).catch(()=>assert.fail('clear restores every saved host'));
  const focus=await focused(),queryNode=await visible('quick.query');assert(flat(queryNode).some(n=>n.id===focus.id),'Clear returns focus to query');
  await absent('quick.clear');assert((await key('escape')).ok);await absent('quick.connect');rec.checks.push({quick_size:size,clear_focus:focus});
 }
 try{
  await waitForServerReady();rec.rpc_owner=JSON.parse(await readFile(join(rpc,'owner.json'),'utf8'));assert.equal(Number(rec.rpc_owner.pid),app.pid);
  await shellSize(1440,900);if(!empty)await visible('sidebar.host');
  if(scope!=='settings'){await sidebar('1440');await capture(label+'-sidebar-1440',['workspace.sidebar','sidebar.empty.new','sidebar.footer.new']);}
  if(!empty&&scope!=='sidebar'){await settings();if(scope==='full')await quick('1440');}
  await shellSize(860,480);
  if(scope!=='settings'){await sidebar('860');await capture(label+'-sidebar-860',['workspace.sidebar','sidebar.empty.new','sidebar.footer.new']);}
  if(!empty&&scope==='full')await quick('860');
  // Window close only hides the window — sessions and the process stay (nav_host.zig `nativeWindowCloseRequest`,
  // e1372d88); the app ends through an application quit (`beginApplicationClose`), which must exit normally.
  const state=await request('POST','/zerowork/windows',{action:'snapshot'});assert.equal(state.windows.length,1);assert((await request('POST','/zerowork/windows',{action:'close',window:state.windows[0].window})).ok);
  await Promise.race([ended,sleep(1000)]); // 1 s observation window: closing the window must not end the process
  assert.equal(app.exitCode,null,'closing the window keeps the app running');
  assert.equal((await request('POST','/zerowork/windows',{action:'snapshot'})).windows.length,1,'the hidden window is kept');
  assert((await request('POST','/zerowork/windows',{action:'quit'})).ok);
  await Promise.race([ended,sleep(10000)]);assert.equal(app.exitCode,0,'application quit exits normally');assert.equal(app.signalCode,null);rec.normal_close=true;rec.status='passed_pending_pixel_review';
 }
 catch(e){failure=e;rec.status='failed';rec.error=String(e);try{await capture(label+'-failure',['workspace.shell','settings.panel','quick.connect']);}catch{}}
 finally{if(app.exitCode===null&&app.signalCode===null){rec.forced_cleanup=true;app.kill('SIGTERM');await Promise.race([ended,sleep(2000)]);if(app.exitCode===null&&app.signalCode===null){app.kill('SIGKILL');await ended;}}await log.close();rec.exit={code:app.exitCode,signal:app.signalCode};await rm(iso,{recursive:true,force:true});await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));}
 if(failure)break runs;
}report.status=failure?'failed':'passed_pending_pixel_review';await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));if(failure)throw failure;
