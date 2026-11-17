/** Session cards float, AI goes into the split (cards-float; user ruling "ssh类的也是可以floating的啊，AI chat也是
 * 可以放回cards layout的。"; Pencil MSg5W next to the unified chrome spec b2ghJ).
 *
 * One real Local terminal (a background ticker keeps printing) walks the whole round trip:
 *  1. Single-card tab: the pane header's 浮动 moves the same terminal into the unified floating chrome; the tab stays
 *     on the strip and its body shows "卡片已浮动". Input typed before the move is kept (the command completes after
 *     it), output keeps arriving, keyboard focus is in the floating terminal; ⌘F search, IME commit, drag selection
 *     and the right-click menu work inside the floating card; Escape does not close the card.
 *  2. Chrome buttons: 作为标签页打开 · 放入分屏 · 收起 · 放大 · 关闭 always shown; 收起 native disabled with
 *     "终端不支持收起"; 放入分屏 puts it back into its tab body (the ticker still runs, input still works).
 *  3. Split: 向右分屏 makes a two-terminal group; a member floats out of it (one pane left, the group stays), folds
 *     away when another tab is current and comes back (Z12), then 放入分屏 puts it back (two panes).
 *  4. AI: in a single-card tab the AI chrome shows 放入分屏 enabled and 作为标签页打开 disabled ("AI 助手不支持作为标签页
 *     打开"); docking makes the tab a split with the AI pane (the session pane header: grip · 浮动 · 更多), the draft
 *     is kept, the launcher stays and focuses the docked AI; the pane's 浮动 brings it back floating and the split
 *     dissolves back into the original single-card tab.
 *
 * Usage: node e2e/cards_float_native.ts <zerowork binary (test-mode)> <out dir> [light|dark] [anchor|fade|reduced]
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {join,resolve} from 'node:path';
import {writeFile,readFile,mkdir,mkdtemp,realpath,open,rm,chmod} from 'node:fs/promises';
import {spawn} from 'node:child_process';
import * as h from '../vendor/zenit/e2e/client.ts';

const [binaryArg,outArg,theme='light',mode='anchor']=process.argv.slice(2);
if(!binaryArg||!outArg)throw new Error('usage: cards_float_native.ts <binary> <out> [light|dark] [anchor|fade|reduced]');
const out=resolve(outArg);await mkdir(out,{recursive:true});
const tag=`${theme}-${mode}`;
const report:any={status:'running',theme,mode,checks:[] as string[],shots:[] as string[],samples:{} as any,limits:['KVM and SSH/SFTP floating are covered by unit tests (card type registry) and the shared content-node move; this run drives a real Local terminal (no offline streaming KVM in the full app).']};
const iso=await realpath(await mkdtemp('/private/tmp/zw-cards-float-e2e-'));await chmod(iso,0o700);
const rpc=join(iso,'rpc'),data=join(iso,'data'),shell=join(iso,'shell');
await mkdir(rpc);await mkdir(join(data,'logs/history'),{recursive:true});await mkdir(shell);
await writeFile(join(shell,'.zshenv'),"setopt NO_RCS\nPROMPT='cf %% '\nRPROMPT=''\n");
await writeFile(join(data,'config.toml'),`[meta]\nconfig_revision=1\n[updates]\nauto_check=false\n[ui]\ntheme="${theme}"\nfloat_card_transition="${mode==='fade'?'fade':'anchor'}"\n[ui.materials]\nblur_px=0\n`);
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const logPath=join(out,`${tag}-app.log`);
const log=await open(logPath,'w');
const env:any={...process.env,ZDOTDIR:shell,ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1',ZENIT_E2E_ISOLATE_KEYBOARD:'1',ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',OPENAI_API_KEY:'',ANTHROPIC_API_KEY:''};
if(mode==='reduced')env.ZENIT_A11Y_PREFS='reduce_motion';
const app=spawn(binaryArg,[],{env,stdio:['ignore',log.fd,log.fd]});
const ended=new Promise<void>(r=>app.once('close',()=>r()));
await h.waitForServerReady();

type R={x:number,y:number,w:number,h:number};
const shown=(n:any)=>!!n&&n.hidden!==true&&n.visible!==false&&(n.effective_opacity??1)>0.02&&n.rect?.w>0&&n.rect?.h>0;
const node=(id:string,ms=12000)=>h.waitFor(async()=>(await h.query(id)).find(shown)??null,ms);
const gone=(id:string,ms=8000)=>h.waitFor(async()=>(await h.query(id)).some(shown)?null:true,ms);
const isShown=async(id:string)=>(await h.query(id)).some(shown);
const center=(r:R)=>({x:r.x+r.w/2,y:r.y+r.h/2});
const click=async(id:string)=>{const n=await node(id);const c=center(n.rect);assert((await h.clickAt(c.x,c.y)).ok,'click '+id);};
const within=(inner:R,outer:R,label:string)=>assert(inner.x>=outer.x-1&&inner.y>=outer.y-1&&inner.x+inner.w<=outer.x+outer.w+1&&inner.y+inner.h<=outer.y+outer.h+1,`${label}: ${JSON.stringify(inner)} not inside ${JSON.stringify(outer)}`);
const texts=(n:any):string[]=>!shown(n)?[]:[...(n.text?[n.text]:[]),...(n.children??[]).flatMap(texts)];
const flat=(n:any):any[]=>n?[n,...(n.children??[]).flatMap(flat)]:[];
const shot=async(name:string,park=true)=>{if(park){await h.mouseMove(4,500);await h.sleep(700);}const path=join(out,`${tag}-${name}.png`);assert((await h.screenshot(path)).ok,name);report.shots.push(path);return path;};
const disabled=async(id:string)=>{const n:any=(await h.query(id)).find(shown);assert(n,'button '+id);return n.disabled===true||n.focusable!==true;};
async function tooltip(id:string){
 const b=(await node(id)).rect;await h.mouseMove(4,500);await h.sleep(250);await h.mouseMove(b.x+b.w/2,b.y+b.h/2);await h.sleep(60);await h.mouseMove(b.x+b.w/2+1,b.y+b.h/2);
 const tip=await node(id+'.tooltip',4000);return texts(tip).join('');
}
/** Every visible terminal surface's text, in the order found. */
async function surfaces(){return (await h.query('terminal.surface')).filter(shown).map((n:any)=>({rect:n.rect as R,text:texts(n).join('\n')}));}
const surfaceIn=async(box:R)=>(await surfaces()).find(s=>s.rect.x>=box.x-1&&s.rect.y>=box.y-1&&s.rect.x+s.rect.w<=box.x+box.w+1&&s.rect.y+s.rect.h<=box.y+box.h+1)??null;
const outputIn=async(box:()=>Promise<R>,value:string|RegExp,ms=12000)=>h.waitFor(async()=>{const s=await surfaceIn(await box());return s&&(typeof value==='string'?s.text.includes(value):value.test(s.text))?s:null;},ms);
const lastTick=async(box:R)=>{const s=await surfaceIn(box);const m=[...(s?.text??'').matchAll(/TICK_(\d+)/g)].map(x=>+x[1]);return m.length?Math.max(...m):0;};
async function ticking(box:()=>Promise<R>,label:string){const a=await lastTick(await box());await h.sleep(1600);const b=await lastTick(await box());assert(b>a&&a>0,`${label}: output keeps arriving (${a} → ${b})`);return [a,b];}
const tabCount=async()=>{const strip=(await h.query('tabs.strip')).find(shown);return strip?flat(strip).filter((n:any)=>/^tabs\.tab\.\d+$/.test(n.test_id??'')&&shown(n)).length:0;};
const stripTabs=async()=>{const strip=(await h.query('tabs.strip')).find(shown);return strip?flat(strip).filter((n:any)=>/^tabs\.tab\.\d+$/.test(n.test_id??'')&&shown(n)).map((n:any)=>({n,text:texts(n).join('')})):[];};
const clickTab=async(match:(text:string)=>boolean)=>{const t=(await stripTabs()).find(x=>match(x.text));assert(t,'tab '+JSON.stringify((await stripTabs()).map(x=>x.text)));const c=center(t.n.rect);assert((await h.clickAt(c.x,c.y)).ok);await h.sleep(300);};
async function dismissToasts(){for(let i=0;i<3;i++){const t=(await h.query('notifications.toast.0')).find(shown);if(!t)return;const c=center(t.rect);await h.mouseMove(c.x,c.y);await h.sleep(200);const d=(await h.query('notifications.dismiss.0')).find(shown);if(d){const dc=center(d.rect);await h.clickAt(dc.x,dc.y);}await h.sleep(500);}}
const panesShown=async()=>{const root=(await h.query('groups.workspace')).find(shown);return root?flat(root).filter((n:any)=>/^groups\.pane\.\d+$/.test(n.test_id??'')&&shown(n)):[];};
const menuItem=async(menuId:string,label:string)=>{const menu=await node(menuId);const n=flat(menu).find((x:any)=>x.text===label&&shown(x));assert(n,`menu ${menuId} has ${label}`);const c=center(n.rect);assert((await h.clickAt(c.x,c.y)).ok);};
const panelRect=async()=>(await node('session.float.panel')).rect as R;
const bodyRect=async()=>{const panes=await panesShown();if(panes.length)return (await node('groups.workspace')).rect as R;return (await node('terminal.surface')).rect as R;};

try{
 await h.resizeWindow(1440,900);await h.sleep(400);
 await click(((await h.query('workspace.empty.local')).some(shown))?'workspace.empty.local':'toolbar.new_session');
 if(!(await isShown('terminal.surface'))&&(await isShown('session.menu.local')))await click('session.menu.local');
 await node('terminal.surface');await outputIn(async()=>(await node('terminal.surface')).rect,'cf %');
 await h.type_('(i=0; while [ $i -lt 4000 ]; do i=$((i+1)); echo TICK_$i; sleep 0.3; done) &');await h.key('return');
 await outputIn(async()=>(await node('terminal.surface')).rect,'TICK_2');
 const tabsBefore=await tabCount();

 // 1. Single-card tab → floating.
 assert(!(await disabled('pane.float')),'pane header 浮动 is enabled');
 assert.equal(await tooltip('pane.float'),'浮动');
 await click('terminal.surface');await h.type_('echo FLOAT_A');await h.sleep(200);
 const docked=(await node('terminal.surface')).rect as R;
 await click('pane.float');
 const panel=await panelRect();await node('workspace.card_floated');
 assert.equal(await tabCount(),tabsBefore,'the tab stays on the strip');
 assert((await texts(await node('workspace.card_floated.detail'))).join('').includes('浮在窗口上'));
 within((await surfaceIn(panel))!.rect,panel,'the terminal is inside the floating card');
 await h.sleep(700);
 await h.type_('_B');await h.key('return');
 await outputIn(panelRect,'FLOAT_A_B');
 report.checks.push('Single tab → float: same terminal in the unified chrome; input typed before the move completes after it (FLOAT_A_B); tab stays with "卡片已浮动"');
 report.samples.ticks_floating=await ticking(panelRect,'floating');

 // Chrome buttons: all five, minimize refused for a session card.
 const order=['session.float.open_as_tab','session.float.dock_to_split','session.float.minimize','session.float.maximize','session.float.close'];
 const xs:number[]=[];for(const id of order)xs.push((await node(id)).rect.x);
 for(let i=1;i<xs.length;i++)assert(xs[i]>xs[i-1],`fixed order ${order[i-1]} < ${order[i]}`);
 assert(await disabled('session.float.minimize'),'收起 disabled');report.samples.minimize_tooltip=await tooltip('session.float.minimize');assert.match(report.samples.minimize_tooltip,/^(本地)?终端不支持收起$/);
 for(const id of ['session.float.open_as_tab','session.float.dock_to_split','session.float.maximize','session.float.close'])assert(!(await disabled(id)),id+' enabled');
 assert.equal(await tooltip('session.float.dock_to_split'),'放入分屏');
 report.checks.push(`Chrome: 作为标签页打开 · 放入分屏 · 收起 · 放大 · 关闭 in order; 收起 native disabled ("${report.samples.minimize_tooltip}"); the rest enabled`);
 await shot('floating-terminal');
 // Move the card aside to show the tab body's "卡片已浮动" under it.
 {const g=(await node('session.float.drag')).rect;await h.mouseDown(g.x+g.w/2,g.y+g.h/2);for(let i=1;i<=8;i++){await h.mouseMove(g.x+g.w/2-120*i,g.y+g.h/2+20*i);await h.sleep(30);}await h.sleep(150);await h.mouseUp(g.x+g.w/2-960,g.y+g.h/2+160);await h.sleep(400);
  const p=await panelRect();const ph=(await node('workspace.card_floated.put_back')).rect;assert(ph.x>p.x+p.w||ph.y+ph.h<p.y,`the placeholder button is visible beside the moved card (${JSON.stringify(ph)} / ${JSON.stringify(p)})`);await shot('floating-terminal-placeholder');}
 // IME commit goes to the floating terminal.
 await click('terminal.surface');assert.equal((await h.focused()).test_id,'terminal.input','the floating terminal has the keyboard');await h.type_('echo IME_');await h.imePreedit('zhong');await h.sleep(100);await h.imeCommit('中文');await h.key('return');
 // Each wide cell is its own text node in the surface tree.
 await outputIn(panelRect,/IME_\s*中\s*文/);
 // Drag selection, then the right-click menu offers 复制 first.
 {const s=(await surfaceIn(await panelRect()))!.rect;const y=s.y+14;await h.mouseDown(s.x+8,y);await h.mouseMove(s.x+120,y);await h.mouseMove(s.x+200,y);await h.mouseUp(s.x+200,y);await h.sleep(200);
  assert((await h.request('POST','/mouse_down',{x:s.x+60,y,button:'right'})).ok);assert((await h.request('POST','/mouse_up',{x:s.x+60,y,button:'right'})).ok);
  const menu=await node('terminal.menu');const rows=flat(menu).filter((n:any)=>/^terminal\.menu\./.test(n.test_id??'')&&shown(n)).sort((a:any,b:any)=>a.rect.y-b.rect.y);
  report.samples.menu_rows=rows.map((n:any)=>n.test_id);assert(rows.length>0&&rows[0].test_id==='terminal.menu.copy',`selection menu starts with 复制 (${report.samples.menu_rows})`);
  await shot('floating-terminal-menu',false);
  await h.key('escape');await gone('terminal.menu');assert(await isShown('session.float.panel'));}
 // Search inside the floating card; Escape closes the search, never the card.
 await click('terminal.surface');
 assert((await h.key('f',{cmd:true})).ok);await node('terminal.search');
 within((await node('terminal.search')).rect,await panelRect(),'search bar inside the floating card');
 await h.type_('FLOAT_A_B');
 const count=await h.waitFor(async()=>{const n:any=(await h.query('terminal.search.count')).find(shown);const t=n?.text??n?.label??texts(n??{}).join('');return /^[1-9]\d*\/\d+$/.test(t)?t:null;},10000);
 report.samples.search_count=count;
 // Escape first returns the query to its value at focus (overlay-focus rule for native Inputs), then closes the bar.
 await h.key('escape');if(await isShown('terminal.search')){await h.sleep(150);await h.key('escape');}
 await gone('terminal.search');assert(await isShown('session.float.panel'),'Escape closed the search, not the card');
 report.checks.push(`Floating terminal: ⌘F search (${count}), IME commit (IME_中文), drag selection + right-click menu (复制 first) all inside the card; Escape never closes it`);

 // 2. 放入分屏 → back into its tab body.
 await click('session.float.dock_to_split');await gone('session.float.panel');await gone('workspace.card_floated');
 const back=(await node('terminal.surface')).rect as R;
 assert(Math.abs(back.x-docked.x)<2&&Math.abs(back.w-docked.w)<2,`back in the tab body (${JSON.stringify(back)} vs ${JSON.stringify(docked)})`);
 // The search left the view at its match; typing follows the output to the bottom again.
 await click('terminal.surface');await h.type_('echo BACK_OK');await h.key('return');await outputIn(async()=>(await node('terminal.surface')).rect,'BACK_OK');
 report.samples.ticks_back=await ticking(async()=>(await node('terminal.surface')).rect,'back in the tab');
 report.checks.push('放入分屏 from a single-card tab: back in its tab body at the same size; the ticker kept running; input works (BACK_OK)');

 // 3. Split member floats out and back; folds away on another tab.
 await click('pane.more');await menuItem('pane.menu','向右分屏');
 await h.waitFor(async()=>(await panesShown()).length===2||null,20000);
 const members=(await panesShown()).map((n:any)=>+n.test_id.split('.').at(-1)).sort((a:number,b:number)=>a-b);
 const first=members[0];
 await outputIn(async()=>(await node(`groups.pane.${first}`)).rect,'TICK_');
 assert.equal(await tooltip(`groups.float.${first}`),'浮动');
 await click(`groups.float.${first}`);await panelRect();
 await h.waitFor(async()=>(await panesShown()).length===1||null,8000);
 assert(await isShown('groups.workspace'),'the split stays with the other member');
 report.samples.ticks_member=await ticking(panelRect,'floating member');
 await shot('floating-member');
 // Another tab: the floating card folds into its tab, and comes back with it.
 await click('toolbar.new_session');await click('session.menu.local');
 await gone('session.float.panel');
 await clickTab(t=>t.startsWith('组'));await panelRect();
 report.checks.push('Split member floats out (one pane left, the group stays), output keeps arriving, folds away on another tab and comes back');
 await click('session.float.dock_to_split');await gone('session.float.panel');
 await h.waitFor(async()=>(await panesShown()).length===2||null,8000);
 await outputIn(async()=>(await node(`groups.pane.${first}`)).rect,'TICK_');
 report.checks.push('放入分屏 puts the member back: two panes again');

 // 4. AI into the split of a single-card tab and back.
 // The new single-card Local tab (the last one on the strip).
 {const all=await stripTabs();const c=center(all.at(-1)!.n.rect);await h.clickAt(c.x,c.y);}await node('terminal.surface');await h.sleep(500);
 assert(!(await isShown('groups.workspace')),'a single-card tab');
 const singleTabs=await tabCount();
 await click('ai.launcher');await node('ai.panel');await h.sleep(500);
 assert(await disabled('ai.open_as_tab'),'AI 作为标签页打开 disabled');assert.equal(await tooltip('ai.open_as_tab'),'AI 助手不支持作为标签页打开');
 assert(!(await disabled('ai.dock_to_split')),'AI 放入分屏 enabled');
 // The AI content node (conversation + composer) is moved, never rebuilt: its node id stays.
 const aiContent=(await node('ai.content')).id;const aiConversation=(await node('ai.conversation')).id;report.samples.ai_nodes={aiContent,aiConversation};
 await dismissToasts();await click('ai.dock_to_split');await node('ai.pane');await gone('ai.panel');
 assert(await isShown('groups.workspace'),'the single-card tab became a split');
 assert.equal(await tabCount(),singleTabs,'still one tab for it on the strip');
 for(const id of ['ai.pane.drag','ai.pane.float','ai.pane.more'])assert(await isShown(id),id+' in the docked pane header');
 assert.equal((await node('ai.content')).id,aiContent,'same AI content node in the pane');assert.equal((await node('ai.conversation')).id,aiConversation,'same conversation node');
 within((await node('ai.prompt')).rect,(await node('ai.pane')).rect,'composer inside the pane');
 assert(await isShown('ai.launcher'),'the launcher stays while the AI is docked');
 await click('terminal.surface');await click('ai.launcher');await h.sleep(300);
 const focusedNode=await h.focused();report.samples.launcher_focus=focusedNode.test_id;assert.equal(focusedNode.test_id,'ai.prompt','the launcher focuses the docked AI');
 report.samples.ai_geometry={pane:(await node('ai.pane')).rect,content:(await node('ai.content')).rect,viewport:(await node('ai.conversation.viewport')).rect,prompt:(await node('ai.prompt')).rect,conversation:(await node('ai.conversation')).rect};await dismissToasts();await shot('ai-docked');{const pane=(await node('ai.pane')).rect,view=(await node('ai.conversation.viewport')).rect;const bars=flat(await node('ai.pane')).filter((n:any)=>n.rect&&n.rect.w>0&&n.rect.w<10&&n.rect.h>100);report.samples.thumbs=bars.map((n:any)=>n.rect);
  for(const b of bars)assert(b.rect.x+b.rect.w<=view.x+view.w+0.5&&b.rect.x>=view.x+view.w-12&&b.rect.y+b.rect.h<=view.y+view.h+0.5,`the transcript scroll bar follows the pane (${JSON.stringify(b.rect)} in ${JSON.stringify(view)})`);}
 await dismissToasts();await click('ai.pane.more');const menu=await node('ai.pane.menu');const labels=flat(menu).filter((n:any)=>shown(n)&&n.text).map((n:any)=>n.text);
 report.samples.ai_menu=labels;for(const l of ['浮动','子智能体','AI 会话列表','新建 AI 会话','关闭'])assert(labels.includes(l),'更多 has '+l);
 await shot('ai-docked-menu',false);
 await h.key('escape');await gone('ai.pane.menu');
 // The chrome's 子智能体 / 会话列表 are the same entries while docked; their popovers open beside 更多.
 {const more=(await node('ai.pane.more')).rect as R;
  for(const [label,id] of [['子智能体','ai.children.list'],['AI 会话列表','ai.sessions.menu']] as const){
   await dismissToasts();await click('ai.pane.more');await menuItem('ai.pane.menu',label);
   const pop=await h.waitFor(async()=>{const n=(await h.query(id)).find(shown);return n?n.rect:null;},8000) as R;
   report.samples['docked_'+id]=pop;
   assert(pop.y>=more.y+more.h-1,`${label}: opens below 更多 (${JSON.stringify(pop)} / ${JSON.stringify(more)})`);
   assert(Math.abs((pop.x+pop.w)-(more.x+more.w))<40&&pop.x<more.x,`${label}: right-aligned with 更多`);
   if(label==='子智能体')await shot('ai-docked-children',false);
   // The popover opens under the pointer (更多's menu sat there): a row's hover hint is up, and the
   // first Escape belongs to the hint (zenit: a hint inside the topmost overlay takes Escape itself).
   // Move the pointer into the workspace (not onto the window corner, which leaves the hover where it
   // was) and let the hint go before Escape closes the popover.
   {const term=(await node('groups.workspace')).rect as R;await h.mouseMove(term.x+40,term.y+term.h/2);await h.sleep(150);await h.mouseMove(term.x+60,term.y+term.h/2+20);await h.sleep(500);}
   await h.key('escape');await gone(id);
  }}
 report.checks.push('AI docked: 更多 offers 子智能体 / AI 会话列表 / 新建 AI 会话 like the floating header; their popovers open below 更多, right-aligned');
 report.checks.push('AI → 放入分屏: the single-card tab becomes a split with the AI pane (session pane header: grip · 浮动 · 更多 = 浮动 / 新建 AI 会话 / 关闭); same content node (conversation, composer); launcher stays and focuses the composer');
 await dismissToasts();await click('ai.pane.float');await node('ai.panel');await gone('ai.pane');
 await gone('groups.workspace');
 assert.equal(await tabCount(),singleTabs,'the split dissolved back into the single-card tab');
 assert.equal((await node('ai.content')).id,aiContent,'same AI content node floating again');
 await shot('ai-floated-back');
 // Floating again: the popovers are back beside their chrome buttons.
 {await dismissToasts();const b=(await node('ai.sessions')).rect as R;await click('ai.sessions');const pop=await h.waitFor(async()=>{const n=(await h.query('ai.sessions.menu')).find(shown);return n?n.rect:null;},8000) as R;
  assert(pop.y>=b.y+b.h-1&&pop.y<b.y+b.h+40&&pop.x<=b.x+1&&pop.x+pop.w>=b.x+b.w-1,`会话列表 opens below its chrome button again (shifted into the window) (${JSON.stringify(pop)} / ${JSON.stringify(b)})`);await h.key('escape');await gone('ai.sessions.menu');}
 report.checks.push('AI pane 浮动: floating again, the split dissolved back into the original single-card tab, same content node');
 report.status='passed';
}catch(error){report.status='failed';report.error=String((error as any)?.stack??error);await h.screenshot(join(out,`${tag}-failure.png`)).catch(()=>{});process.exitCode=1;}
finally{
 await writeFile(join(out,`report-${tag}.json`),JSON.stringify(report,null,1));
 if(app.exitCode===null&&app.signalCode===null)app.kill('SIGTERM');await ended;
 await log.close().catch(()=>{});await rm(iso,{recursive:true,force:true}).catch(()=>{});
}
console.log(report.status, out);
