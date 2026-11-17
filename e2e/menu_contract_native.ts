/** Menu contract (menus 包, CONSISTENCY_AUDIT #3): every menu of the main window is the native zenit Menu, built
 * through the one entry (`shell/view/app_menu.zig`) from declared entries, and looks and behaves the same.
 *
 * For each menu (sidebar host right click, tab right click, session-group tab, terminal right click, terminal
 * middle click, new session (+ its “更多” submenu), pane “更多”, group member “更多”, title-bar “⋯”, tab overflow
 * “⌄ n”, sidebar group “⋯”):
 *  - style: the rows under the panel are native `MenuItem` / `MenuHeader` / `MenuSeparator` nodes (component
 *    names written by zenit), no `Button` look-alikes; every item row has the same height and label size, and every
 *    panel the same background, in every menu;
 *  - order: the one rule (common first, danger items last after a separator, headers never selectable);
 *  - shortcuts: the text on every row with a shortcut command equals the router's hint for it
 *    (`/zerowork/menus` rows vs `/zerowork/shortcuts`); the app starts with remapped keys so a hard-coded
 *    default shows up as a mismatch;
 *  - no Tooltip covers the menu: the sidebar host row's hint is up (pointer resting on the row) when its menu opens;
 *    no tooltip-tier layer may paint above (z) and overlap any open menu;
 *  - keyboard: Down moves the native highlight to another enabled row, Escape closes the menu.
 * Screenshots: `<theme>-<menu>.png` for every menu, light and dark runs side by side.
 *
 * Usage: node e2e/menu_contract_native.ts <binary> <out> [light|dark]
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {chmod,mkdir,mkdtemp,open,writeFile,realpath} from 'node:fs/promises';
import {dirname,resolve,join} from 'node:path';
import {pathToFileURL} from 'node:url';
const binary=resolve(process.argv[2]),out=resolve(process.argv[3]),variant=process.argv[4]??'light';
const theme=variant==='dark'?'dark':'light';
const h=await import(pathToFileURL(resolve(dirname(binary),'../share/zenit/harness/client.ts')).href);
const iso=await realpath(await mkdtemp('/private/tmp/zw-menu-contract-'));await chmod(iso,0o700);
const data=join(iso,'data'),rpc=join(iso,'rpc'),tmp=join(iso,'tmp'),zdot=join(iso,'zdot');
for(const p of [out,data,rpc,tmp,zdot])await mkdir(p,{recursive:true,mode:0o700});
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
// One offline saved host in one asset group (sidebar host and group menus); never connected (ZEROWORK_AUTOCONNECT=0).
await writeFile(join(data,'hosts.toml'),`[registry]\nschema_version=2\nrevision=1\nnext_connection_id=2\nnext_group_id=2\n[[groups]]\ngroup_id=1\nrevision=1\nname="Contract"\ncollapsed=false\nordered_connection_ids=[1]\n[[hosts]]\nasset_group_id=1\nconnection_id=1\nrevision=1\nprotocol="ssh"\nauth_mode="password"\noptions={strict_host_key=true}\nname="Menu SSH (offline)"\nhost="127.0.0.1"\nport=9\nuser="contract"\n`);
// Remapped keys: a hard-coded default shortcut text would not match the router.
await writeFile(join(data,'config.toml'),`[meta]\nconfig_revision=1\n[updates]\nauto_check=false\n[ui]\ntheme="${theme}"\n[keys]\nsearch="cmd+e"\nclose_tab="cmd+shift+e"\nrename_tab="cmd+alt+r"\n`);
const log=await open(join(out,`${variant}-app.log`),'w');
const app=spawn(binary,[],{env:{PATH:process.env.PATH??'/usr/bin:/bin',HOME:iso,CFFIXED_USER_HOME:iso,TMPDIR:tmp+'/',ZDOTDIR:zdot,ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1',OPENAI_API_KEY:'',ANTHROPIC_API_KEY:''},stdio:['ignore',log.fd,log.fd]});
const ended=new Promise(r=>app.once('close',r));
const report:any={variant,menus:{},style:{},failures:[] as string[],captures:[] as string[]};
const shown=(n:any)=>n?.rect?.w>0&&n.rect.h>0&&n.visible!==false&&n.hidden!==true&&(n.effective_opacity??n.opacity??1)>0.5;
const flat=(n:any):any[]=>n?[n,...(n.children??[]).flatMap(flat)]:[];
const alive=()=>assert(app.exitCode===null&&app.signalCode===null,'native app stays alive');
const nodes=async(id:string)=>{alive();const r=await h.query(id);assert(Array.isArray(r),id+': '+JSON.stringify(r));return r.filter(shown);};
const visible=(id:string,ms=8000)=>h.waitFor(async()=>(await nodes(id))[0]??null,ms);
const hidden=(id:string,ms=5000)=>h.waitFor(async()=>!(await nodes(id)).length||null,ms);
const sleep=(ms:number)=>h.sleep(ms);
const away={x:700,y:560};
const centre=async(id:string)=>{const n=await visible(id);return {x:n.rect.x+n.rect.w/2,y:n.rect.y+n.rect.h/2};};
async function clickId(id:string){const c=await centre(id);await h.mouseMove(c.x,c.y);assert((await h.clickAt(c.x,c.y)).ok,id);await sleep(250);}
async function press(x:number,y:number,button:'right'|'middle'){await h.mouseMove(x,y);for(const route of ['/mouse_down','/mouse_up'])assert((await h.request('POST',route,{x,y,button})).ok);await sleep(350);}
async function shot(name:string){await sleep(250);const path=join(out,`${variant}-${name}.png`);await h.screenshot(path).catch(()=>{});report.captures.push(path);}
const fail=(menu:string,what:string,detail:any)=>{report.failures.push(`${menu}: ${what} ${JSON.stringify(detail)}`);};
async function settle(){for(let i=0;i<3;i++){await h.key('escape');await sleep(120);}await h.mouseMove(away.x,away.y);await sleep(200);}

let registry:Map<string,string>;let registryEntries:any[]=[];
const rowHeights=new Set<number>(),labelSizes=new Set<number>(),labelInks=new Set<string>(),dangerInks=new Set<string>(),panelBgs=new Set<string>();

/** The panel chrome node (with its subtree) of the open menu `panel`. */
async function panelNode(panel:string){const all=await nodes(panel);return all.sort((a:any,b:any)=>b.rect.w*b.rect.h-a.rect.w*a.rect.h)[0];}
/** One contract for every menu. Failures are collected, not thrown. */
async function contract(name:string,panel:string,open:()=>Promise<void>,opts:{expectHeader?:boolean,expectDanger?:boolean,keyboard?:boolean,tooltipCheck?:boolean,submenuOf?:string,rendered?:boolean}={}){
 const entry:any=report.menus[name]={panel};
 try{
  await open();
  const chrome=await visible(panel);
  await sleep(350);
  await shot(name);
  // ── model (the one projection): order rule and shortcut text ──
  const snap=await h.request('POST','/zerowork/menus',{});
  let rows:any[];
  if(opts.submenuOf){
   // A native submenu: its rows are the parent row's children in the same projection.
   const parent=(snap.menus??[]).find((m:any)=>m.panel===opts.submenuOf);
   const row=parent?.rows?.find((r:any)=>r.submenu===panel);
   if(!row){fail(name,'submenu not found under its parent menu',parent?.rows);return;}
   rows=row.children;
  }else if(opts.rendered){
   // Menus mounted in .yix whose rows come from app_menu.build (title “⋯”, tab overflow): read the rendered rows.
   rows=[];
   for(const n of flat(await panelNode(panel)))if(['MenuItem','MenuHeader','MenuSeparator'].includes(n.component)&&shown(n)){
    const texts=flat(n).filter((c:any)=>typeof c.text==='string'&&c.text.length).map((c:any)=>c.text);
    const chord=texts.length>1&&/^[⌃⌥⇧⌘]*([A-Z0-9,]|F\d+|↩|Tab|Space|Esc|[↑↓←→])$/.test(texts.at(-1))?texts.at(-1):'';
    rows.push({kind:n.component==='MenuItem'?'item':n.component==='MenuHeader'?'header':'separator',label:texts[0]??'',shortcut:chord,danger:false,disabled:false,rendered:true});
   }
  }else{
   const menu=(snap.menus??[]).find((m:any)=>m.panel===panel);
   if(!menu){fail(name,'not an app_menu panel (one menu entry)',snap.menus?.map((m:any)=>m.panel));return;}
   rows=menu.rows as any[];
  }entry.rows=rows.map((r:any)=>r.kind==='item'?`${r.label}${r.reason?' 〔'+r.reason+'〕':''}${r.shortcut?' ['+r.shortcut+']':''}${r.danger?' (danger)':''}${r.disabled?' (disabled)':''}`:r.kind==='header'?`# ${r.label}`:'---');
  const items=rows.filter((r:any)=>r.kind==='item');
  if(!items.length)fail(name,'no items',rows);
  const firstDanger=rows.findIndex((r:any)=>r.kind==='item'&&r.danger);
  if(firstDanger>=0){
   if(rows.slice(firstDanger).some((r:any)=>r.kind!=='item'||!r.danger))fail(name,'danger items are not last',entry.rows);
   if(firstDanger===0||rows[firstDanger-1].kind!=='separator')fail(name,'no separator before the danger group',entry.rows);
  }else if(opts.expectDanger)fail(name,'expected a danger item',entry.rows);
  if(opts.expectHeader&&!rows.some((r:any)=>r.kind==='header'))fail(name,'expected a group header',entry.rows);
  if(rows[0]?.kind==='separator'||rows.at(-1)?.kind==='separator')fail(name,'separator at an edge',entry.rows);
  for(let i=1;i<rows.length;i++)if(rows[i].kind==='separator'&&rows[i-1].kind==='separator')fail(name,'double separator',entry.rows);
  for(const r of items){
   if(r.command){const want=registry.get(r.command)??'';if((r.shortcut??'')!==want)fail(name,`shortcut text of “${r.label}” is not the router's`,{command:r.command,shown:r.shortcut,router:want});}
   else if(r.rendered&&r.shortcut){
    // Rendered rows: the chord must be the router's hint of the command with this label (or a tab ordinal).
    const byLabel=[...registryEntries].find((e:any)=>e.label===r.label);
    const ok=byLabel?byLabel.hint===r.shortcut:[...registryEntries].some((e:any)=>/^tab_\d$/.test(e.id)&&e.hint===r.shortcut);
    if(!ok)fail(name,`rendered shortcut of “${r.label}” is not the router's`,{shown:r.shortcut,router:byLabel?.hint});
    r.command=byLabel?.id??'tab_n';
   }
  }
  entry.shortcuts=items.filter((r:any)=>r.command).map((r:any)=>`${r.label}=${r.shortcut||'∅'}(${r.command})`);
  // ── rendered rows: native components, one look ──
  const tree=flat(await panelNode(panel));
  const itemNodes=tree.filter((n:any)=>n.component==='MenuItem'&&shown(n));
  const headerNodes=tree.filter((n:any)=>n.component==='MenuHeader'&&shown(n));
  const looks=tree.filter((n:any)=>n.component==='Button'&&shown(n));
  if(looks.length)fail(name,'hand-drawn Button rows inside the menu',looks.map((n:any)=>n.test_id??n.text));
  if(itemNodes.length!==items.length)fail(name,'rendered MenuItem rows != model items',{rendered:itemNodes.length,model:items.length});
  if(headerNodes.length!==rows.filter((r:any)=>r.kind==='header').length)fail(name,'rendered MenuHeader rows != model headers',{rendered:headerNodes.length});
  const modelItems=items;
  itemNodes.forEach((n:any,i:number)=>{
   rowHeights.add(Math.round(n.rect.h));
   const label=flat(n).find((c:any)=>typeof c.text==='string'&&c.text.length);
   if(!label)return;
   labelSizes.add(label.font_size);
   const r=modelItems[i];
   // Enabled rows only (rendered-only menus do not know which rows are disabled).
   if(r&&!r.disabled&&!r.rendered)(r.danger?dangerInks:labelInks).add(label.text_rgba);
  });
  const panelWithBg=tree.find((n:any)=>n.bg_rgba&&n.component!=='MenuItem');if(panelWithBg)panelBgs.add(panelWithBg.bg_rgba);
  entry.style={rows:itemNodes.length,heights:[...new Set(itemNodes.map((n:any)=>Math.round(n.rect.h)))],label_sizes:[...new Set(itemNodes.map((n:any)=>flat(n).find((c:any)=>c.font_size)?.font_size))],panel_bg:panelWithBg?.bg_rgba,components:[...new Set(tree.map((n:any)=>n.component).filter(Boolean))]};
  // ── no tooltip over the menu ──
  const layers=(snap.layers??[]) as any[];
  const rect=chrome.rect;
  const overlap=(l:any)=>l.x<rect.x+rect.w&&l.x+l.w>rect.x&&l.y<rect.y+rect.h&&l.y+l.h>rect.y;
  const menuLayer=layers.filter((l:any)=>l.tier==='overlay'&&overlap(l)).sort((a:any,b:any)=>b.z-a.z)[0];
  const above=layers.filter((l:any)=>l.tier==='tooltip'&&l.w>0&&l.h>0&&overlap(l)&&(!menuLayer||l.z>menuLayer.z));
  entry.tooltip={menu_z:menuLayer?.z,tooltips:layers.filter((l:any)=>l.tier==='tooltip').map((l:any)=>({z:l.z,x:l.x,y:l.y,w:l.w,h:l.h}))};
  if(above.length)fail(name,'a tooltip paints over the menu',above);
  if(opts.tooltipCheck){
   // The hint was up before the menu opened; a frame later it must be gone entirely.
   const later=await h.request('POST','/zerowork/menus',{});
   const tips=(later.layers??[]).filter((l:any)=>l.tier==='tooltip'&&l.w>0);
   entry.tooltip.after=tips;
   if(tips.some((l:any)=>!menuLayer||l.z>menuLayer.z))fail(name,'tooltip still above after the menu opened',tips);
  }
  // ── keyboard ──
  if(opts.keyboard!==false){
   const lit=async()=>flat(await panelNode(panel)).filter((n:any)=>n.component==='MenuItem'&&n.bg_rgba&&!n.bg_rgba.endsWith(',0')).map((n:any)=>Math.round(n.rect.y));
   await h.mouseMove(away.x,away.y);await sleep(150);
   await h.key('down');await sleep(150);const first=await lit();
   await h.key('down');await sleep(150);const second=await lit();
   entry.keyboard={first,second};
   const enabled=items.filter((r:any)=>!r.disabled).length;
   if(enabled>1&&(first.length!==1||second.length!==1||first[0]===second[0]))fail(name,'Down does not move the native highlight',{first,second});
   await h.key('escape');
   try{await hidden(panel);}catch{fail(name,'Escape does not close the menu',{});}
  }
 }catch(e:any){fail(name,'error',String(e?.stack??e));await shot(name+'-failure');}
 finally{await settle();}
}

try{
 await h.waitForServerReady();
 await h.resizeWindow(1440,900);
 await sleep(800);
 registryEntries=(await h.request('POST','/zerowork/shortcuts',{})).commands as any[];
 registry=new Map(registryEntries.map((c:any)=>[c.id,c.hint]));
 assert.equal(registry.get('close_tab'),'⇧⌘E','registry follows [keys]');
 // Sidebar host: the pointer rests on the row until its hint is up, then right click there.
 await contract('sidebar-host','context.menu',async()=>{const c=await centre('sidebar.host');await h.mouseMove(c.x,c.y);await sleep(1200);report.hint_before=(await h.request('POST','/zerowork/menus',{})).layers;await press(c.x,c.y,'right');},{expectHeader:true,expectDanger:true,tooltipCheck:true});
 await contract('sidebar-group','sidebar.group.menu',async()=>{const c=await centre('sidebar.group');await press(c.x,c.y,'right');},{expectHeader:true,expectDanger:true});
 // A local terminal for the session menus.
 await clickId('workspace.empty.local');await visible('terminal.surface',15000);await sleep(600);
 const tab=async()=>{const strip=flat(await visible('tabs.strip'));return strip.find((n:any)=>/^tabs\.tab\.\d+$/.test(n.test_id??'')&&shown(n));};
 await contract('tab','context.menu',async()=>{const t=await tab();await press(t.rect.x+t.rect.w/2,t.rect.y+t.rect.h/2,'right');},{expectDanger:true});
 await contract('terminal-right-click','terminal.menu',async()=>{const c=await centre('terminal.surface');await press(c.x,c.y,'right');});
 await contract('terminal-middle-click','context.menu',async()=>{const c=await centre('terminal.surface');await press(c.x-80,c.y-40,'middle');},{expectHeader:false});
 await contract('new-session','session.menu',()=>clickId('toolbar.new_session'),{expectHeader:true});
 await contract('new-session-more','session.menu.more.panel',async()=>{await clickId('toolbar.new_session');await visible('session.menu');const c=await centre('session.menu.more');await h.mouseMove(c.x,c.y);await sleep(500);},{keyboard:false,submenuOf:'session.menu'});
 await contract('pane-more','pane.menu',()=>clickId('pane.more'),{expectDanger:true});
 // Title-bar “⋯” and tab overflow “⌄ n”: a narrow window with more local tabs than fit folds both.
 await h.resizeWindow(860,600);await sleep(700);
 for(let i=0;i<12;i++){
  if((await nodes('toolbar.expand')).length&&(await nodes('tabs.all')).length)break;
  await h.key('t',{cmd:true});await sleep(500);await h.key('return');await sleep(700);await h.mouseMove(450,300);await sleep(300);
 }
 await settle();
 if((await nodes('toolbar.expand')).length)await contract('title-more','toolbar.more',()=>clickId('toolbar.expand'),{rendered:true});
 else report.failures.push('title-more: “⋯” never appeared');
 if((await nodes('tabs.all')).length)await contract('tab-overflow','tabs.all.menu',()=>clickId('tabs.all'),{rendered:true});
 else report.failures.push('tab-overflow: “⌄ n” never appeared');
 await h.resizeWindow(1440,900);await sleep(900);
 // Session group: split the active terminal, then the group tab menu and the member “更多”.
 await clickId('pane.more');await visible('pane.menu');
 {const split=(await nodes('pane.menu'))[0];const row=flat(split).find((n:any)=>n.component==='MenuItem'&&flat(n).some((c:any)=>c.text==='向右分屏'));if(row){await h.clickAt(row.rect.x+row.rect.w/2,row.rect.y+row.rect.h/2);await sleep(1500);}}
 await settle();
 // The group tab: right click each tab until the group tab menu opens.
 {let found=false;
  for(const t of flat(await visible('tabs.strip')).filter((n:any)=>/^tabs\.tab\.\d+$/.test(n.test_id??'')&&shown(n))){
   await press(t.rect.x+20,t.rect.y+t.rect.h/2,'right');
   const isGroup=(await nodes('groups.tab.menu')).length>0;
   await settle();
   if(isGroup){found=true;await contract('group-tab','groups.tab.menu',async()=>{await press(t.rect.x+20,t.rect.y+t.rect.h/2,'right');},{expectDanger:true});break;}
  }
  if(!found)report.failures.push('group-tab: no tab opened the session-group tab menu');}
 const member=(await nodes('groups.member_menu')).length?null:flat(await visible('workspace.pane')).find((n:any)=>/^groups\.menu\.\d+$/.test(n.test_id??'')&&shown(n));
 if(member)await contract('group-member-more','groups.member_menu',()=>clickId(member.test_id),{expectDanger:true});
 else report.failures.push('group-member-more: no member “更多” button');
 // One look across every menu.
 report.style={row_heights:[...rowHeights],label_sizes:[...labelSizes],label_inks:[...labelInks],danger_inks:[...dangerInks],panel_backgrounds:[...panelBgs]};
 if(rowHeights.size!==1)report.failures.push(`style: item rows differ in height across menus ${JSON.stringify([...rowHeights])}`);
 if(labelSizes.size!==1)report.failures.push(`style: labels differ in size across menus ${JSON.stringify([...labelSizes])}`);
 if(panelBgs.size>1)report.failures.push(`style: panels differ in background ${JSON.stringify([...panelBgs])}`);
 if(labelInks.size!==1)report.failures.push(`style: enabled labels differ in colour ${JSON.stringify([...labelInks])}`);
 if(dangerInks.size!==1)report.failures.push(`style: danger labels differ in colour ${JSON.stringify([...dangerInks])}`);
 if([...dangerInks].some(c=>labelInks.has(c)))report.failures.push('style: danger rows are not drawn in the danger colour');
 report.status=report.failures.length?'failed':'passed';
}catch(e:any){report.status='error';report.error=String(e?.stack??e);}
finally{
 await writeFile(join(out,`report-${variant}.json`),JSON.stringify(report,null,1));
 if(app.exitCode===null&&app.signalCode===null)app.kill('SIGTERM');await ended;await log.close().catch(()=>{});
}
console.log(variant,report.status,report.failures.length);for(const f of report.failures)console.log('  ',f);if(report.error)console.log(report.error);
process.exitCode=report.status==='passed'?0:1;
