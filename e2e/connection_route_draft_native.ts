/** Connection route draft survives direct/routed toggling in the production wizard. */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdir,mkdtemp,realpath,open,readFile,rm,writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {waitForServerReady,waitFor,query,tree,clickAt,mouseMove,key,type_,inputState,resizeWindow,screenshot,scrollAt} from '../zig-out/share/zenit/harness/client.ts';
const binary=resolve(process.argv[2]),out=resolve(process.argv[3]),theme=process.argv[4]??'dark';
assert(['dark','light','sauber'].includes(theme));
await mkdir(out,{recursive:true});
const isolated=await realpath(await mkdtemp(join(tmpdir(),'zw-wizard-advanced-'))),data=join(isolated,'data'),rpc=join(isolated,'rpc');
await mkdir(data);await mkdir(rpc);
await writeFile(join(data,'hosts.toml'),`[registry]
schema_version=2
revision=1
next_connection_id=3
next_group_id=1
[[hosts]]
connection_id=1
revision=1
protocol="ssh"
name="Jump A"
host="192.0.2.1"
port=22
user="fixture"
auth_mode="password"
[[hosts]]
connection_id=2
revision=1
protocol="ssh"
name="Jump B"
host="192.0.2.2"
port=22
user="fixture"
auth_mode="password"
`);
await writeFile(join(data,'config.toml'),`[meta]\nconfig_revision=1\n[ui]\ntheme="${theme}"\nfont_family="Menlo"\nfont_size=14\n`);
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const log=await open(join(out,'app.log'),'w');
const child=spawn(binary,[],{env:{...process.env,ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1'},stdio:['ignore',log.fd,log.fd]});
const ended=new Promise<void>(r=>child.once('close',()=>r()));
const report:any={status:'running',binary,sha256:createHash('sha256').update(await readFile(binary)).digest('hex'),theme,checks:[],stages:[],limits:['Synthetic Harness input, not physical keyboard/IME verification','No connection test, remote action or save requested']};
// Island B v3 (e1372d88): the connection editor is its own native window (wizard.zig window_spec: 720×640, minimum
// 600×420), not a modal over the main window. While it is open the Harness is bound to that window, so
// `resizeWindow` / `screenshot` / `query` address the editor; `wizard.dialog` exists only in the non-windowed
// (preview) mount and `wizard.close` is hidden (the window closes through its traffic light / Escape / 取消).
const WINDOW={w:720,h:640},MINIMUM={w:600,h:420}; // src/features/connections/wizard/view/wizard.zig window_spec
const CONTROL=32; // wizard_styles.zig control_height (native md Input / Select height)
const CHECKBOX=16; // src/plugins/remote/editor.zig mountIdentity: Checkbox .size = 16
const shown=(n:any)=>n&&n.visible!==false&&n.hidden!==true&&(n.effective_opacity??1)>0&&n.rect?.w>0&&n.rect?.h>0;
const flatten=(n:any):any[]=>[n,...(n.children??[]).flatMap(flatten)];
const text=(n:any)=>flatten(n).map(x=>x.text??'').join(' ');
// A closing aux window can answer a query with an error object instead of a list.
async function nodes(id:string):Promise<any[]>{const q=await query(id);return Array.isArray(q)?q:[];}
async function current(id:string){return (await nodes(id)).find(shown)??null;}
async function visible(id:string){return waitFor(()=>current(id));}
const SCROLLS=['wizard.scroll.identity','wizard.scroll.route','wizard.scroll.review'];
/** The node, scrolled fully into its step's scroll viewport when it lives in one (footer / header nodes do not). */
async function reveal(id:string){
 return waitFor(async()=>{
  const n=await current(id);if(!n)return null;
  let area:any=null;for(const s of SCROLLS){const a=await current(s);if(a&&flatten(a).some(x=>x.id===n.id)){area=a;break;}}
  if(!area)return n;
  const top=area.rect.y,bottom=area.rect.y+area.rect.h;
  if(n.rect.y>=top-0.5&&n.rect.y+n.rect.h<=bottom+0.5)return n;
  await scrollAt(area.rect.x+area.rect.w/2,area.rect.y+area.rect.h/2,0,n.rect.y<top?Math.min(400,top-n.rect.y+12):-Math.min(400,n.rect.y+n.rect.h-bottom+12));
  return null;
 });
}
/** Click the centre of a node once it is revealed and its rect has stopped moving (step / disclosure transitions). */
async function click(id:string){let prior='';const n=await waitFor(async()=>{const n=await reveal(id);const at=JSON.stringify(n.rect);const still=at===prior;prior=at;return still?n:null;});assert((await clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok,id);}
async function fill(id:string,value:string){await click(id);await key('a',{cmd:true});await type_(value);await waitFor(async()=>(await inputState(id)).buffer===value||null);assert(text(await visible(id)).includes(value),id+' shows the typed text');}
async function closed(){await waitFor(async()=>!(await nodes('wizard.window')).some(shown)||null);}
/** The editor window frame; it must fill the bound window exactly (origin 0,0). */
async function frame(expect:{w:number,h:number}){return waitFor(async()=>{const n=await current('wizard.window');return n&&n.rect.x===0&&n.rect.y===0&&n.rect.w===expect.w&&n.rect.h===expect.h?n:null;});}
async function resize(size:{w:number,h:number}){assert((await resizeWindow(size.w,size.h)).ok);await frame(size);}
async function capture(name:string,size:{w:number,h:number}){
 const win=await frame(size),foot=await visible('wizard.footer'),steps=await visible('wizard.steps');
 // Fixed chrome in every stage: stepper on top, footer at the bottom, both inside the window; the step's scroll
 // viewport sits between them (content scrolls, the footer never leaves the window).
 assert(steps.rect.y>=0&&foot.rect.y+foot.rect.h<=win.rect.h,name+': footer inside the window');
 assert(foot.rect.x>=0&&foot.rect.x+foot.rect.w<=win.rect.w,name+': footer inside the window horizontally');
 const area=(await Promise.all(SCROLLS.map(current))).find(Boolean);assert(area,name+': a step scroll viewport is shown');
 assert(area.rect.y>=steps.rect.y+steps.rect.h-0.5&&area.rect.y+area.rect.h<=foot.rect.y+0.5,name+': scroll viewport between stepper and footer');
 await mouseMove(win.rect.w-40,20); // park the pointer on the empty right end of the title bar: no hover state in the screenshot
 await writeFile(join(out,name+'.json'),JSON.stringify({window:win.rect,steps:steps.rect,scroll:area.rect,footer:foot.rect},null,2));assert((await screenshot(join(out,name+'.png'))).ok);report.stages.push({name,rect:win.rect});
}
/** A Select popup is open once one of its option labels is shown outside every Select trigger. */
async function popupOption(label:string){
 return waitFor(async()=>{
  const found:any[]=[];const walk=(n:any,inTrigger:boolean)=>{const t=inTrigger||/^wizard\.(route\.hop\.\d+|strict_host_key)$/.test(n.test_id??'');if(!t&&n.text===label&&shown(n))found.push(n);for(const c of n.children??[])walk(c,t);};
  walk(await tree({visibleOnly:true}),false);return found[0]??null;
 });
}
const checkboxState=async()=>{const n=await visible('wizard.password.remember');const box=n.children[0],check=box.children[0];return {node:n,box,checked:shown(check)};};
/** Selected choices of a native RadioGroup: the ones whose radio dot (choice › circle › dot) is not hidden. */
const radioChoice=async(id:string)=>(await visible(id)).children.filter((c:any)=>c.component==='RadioChoice'&&c.children?.[0]?.children?.[0]?.visible!==false).map((c:any)=>c.test_id);
const hopNames=async()=>{const out:string[]=[];for(let i=0;i<8;i++){const n=await current('wizard.route.hop.'+i);if(!n)break;out.push(text(n).trim());}return out;};
try{
 await waitForServerReady(30000);assert.equal(Number(JSON.parse(await readFile(join(rpc,'owner.json'),'utf8')).pid),child.pid);
 // Island B v3 (e1372d88): 侧栏头部的“+”菜单（sidebar.new › sidebar.new.host）已删，新建主机在侧栏底部（空态是 sidebar.empty.new）。
 await resizeWindow(1440,900);await click('sidebar.footer.new');
 await frame(WINDOW);assert.match(text(await visible('wizard.title')),/新建主机/);
 assert(!(await current('wizard.close')),'the native editor window has no in-window close button');
 await fill('wizard.name','V3 revision target');await fill('wizard.host','127.0.0.1');await fill('wizard.user','fixture');
 assert(!(await current('wizard.strict_host_key')),'Host key policy is hidden with Advanced');
 // The password row centres the native Checkbox and Password Input, which use their own heights.
 // The Checkbox has the requested 16pt box and still toggles through its native control.
 {
  const before=await checkboxState(),password=await visible('wizard.password');
  assert.equal(before.node.component,'Checkbox');assert.deepEqual([before.box.rect.w,before.box.rect.h],[CHECKBOX,CHECKBOX],'Password checkbox box is the 16pt native box');
  assert(Math.abs(password.rect.h-CONTROL)<0.5,'the password field retains its control height');
  assert(Math.abs(before.node.rect.y+before.node.rect.h/2-(password.rect.y+password.rect.h/2))<0.5,
    'the native checkbox centres on the password field');
  assert(Math.abs(before.box.rect.y+before.box.rect.h/2-(password.rect.y+password.rect.h/2))<0.5,'checkbox box centred on the password field');
  assert(before.node.rect.x>=password.rect.x+password.rect.w,'checkbox right of the password field');assert.match(text(before.node),/保存密码/);
  assert.equal(before.checked,true,'保存密码 defaults to checked');
  await click('wizard.password.remember');await waitFor(async()=>(await checkboxState()).checked===false||null);
  await click('wizard.password.remember');await waitFor(async()=>(await checkboxState()).checked===true||null);
 }
 await capture('01-identity-standard',WINDOW);
 await click('wizard.advanced.toggle');
 // Host key policy is a native Select inside the advanced section; choose an option through its popup.
 await click('wizard.strict_host_key');await click('wizard.strict.disabled');await waitFor(async()=>/关闭严格验证/.test(text(await visible('wizard.strict_host_key')))||null);
 await click('wizard.strict_host_key');await click('wizard.strict.enabled');await waitFor(async()=>/严格验证主机密钥/.test(text(await visible('wizard.strict_host_key')))||null);
 await waitFor(async()=>!(await current('wizard.strict.enabled'))||null);
 await capture('02-advanced-standard',WINDOW);
 const advanced=await visible('wizard.advanced.body');await writeFile(join(out,'advanced-tree.json'),JSON.stringify(advanced,null,2));
 assert(flatten(advanced).some(n=>n.test_id==='wizard.strict_host_key'),'Host key policy belongs to advanced subtree');
 {
  const policy=await visible('wizard.strict_host_key');assert.equal(policy.rect.h,CONTROL);
 }
 // SSH 传输压缩 is a two-choice native RadioGroup (关闭 / 开启); exactly one choice carries the radio dot.
 assert.deepEqual(await radioChoice('wizard.compression'),['wizard.compression.disabled']);
 await click('wizard.compression.enabled');await waitFor(async()=>(await radioChoice('wizard.compression')).join()==='wizard.compression.enabled'||null);
 await click('wizard.startup');await key('a',{cmd:true});await type_('echo first');await key('return');await type_('echo second');
 await waitFor(async()=>(await inputState('wizard.startup')).buffer==='echo first\necho second'||null);
 // The disclosure's summary line reports the startup commands (editor.zig refreshAdvancedSummary).
 await waitFor(async()=>/严格验证主机密钥/.test(text(await visible('wizard.advanced.summary')))&&/启动命令 2 条/.test(text(await visible('wizard.advanced.summary')))||null);
 // Minimum editor window: the advanced section scrolls inside the step viewport, the footer stays in the window.
 await resize(MINIMUM);await reveal('wizard.startup');await capture('03-advanced-compact',MINIMUM);
 {
  const foot=(await visible('wizard.footer')).rect,area=(await visible('wizard.scroll.identity')).rect,card=(await visible('wizard.advanced.card')).rect;
  assert(foot.y+foot.h<=MINIMUM.h);assert(card.h>area.h,'expanded advanced section is taller than the viewport and scrolls');
 }
 await click('wizard.next.identity');await click('wizard.access.jump');
 await click('wizard.route.hop.0');await popupOption('Jump A');await key('home');await key('return');
 await waitFor(async()=>/Jump A/.test(text(await visible('wizard.route.hop.0')))||null);
 await click('wizard.route.add');await click('wizard.route.hop.1');await popupOption('Jump B');await key('end');await key('return');
 await waitFor(async()=>/Jump B/.test(text(await visible('wizard.route.hop.1')))||null);
 await capture('04-route-compact',MINIMUM);
 assert.deepEqual(await hopNames(),['Jump A','Jump B']);
 {
  // Hop selectors are native Selects at the editor's control height, equally wide, left-aligned, stacked in order.
  const a=(await reveal('wizard.route.hop.0')).rect,b=(await current('wizard.route.hop.1'))!.rect;
  assert.equal(a.h,CONTROL);assert.equal(b.h,CONTROL);assert(Math.abs(a.w-b.w)<0.5&&Math.abs(a.x-b.x)<0.5,'hop selectors share one column');assert(b.y>=a.y+a.h,'hop rows do not overlap');
  assert(a.x>=0&&a.x+a.w<=MINIMUM.w,'hop selector inside the minimum window');
 }
 await click('wizard.access.direct');
 await waitFor(async()=>!(await current('wizard.route.hop.0'))||null);assert(!(await current('wizard.route.hop.1')),'Direct access hides jump selectors');
 await click('wizard.next.route');await capture('05-direct-review-compact',MINIMUM);
 {
  const route=text(await reveal('wizard.review.route'));assert(!route.includes('Jump A')&&!route.includes('Jump B'),'Direct review excludes dormant hops');assert.match(route,/127\.0\.0\.1/);
 }
 await click('wizard.back');await click('wizard.access.jump');
 await waitFor(async()=>(await hopNames()).length===2||null);assert.deepEqual(await hopNames(),['Jump A','Jump B']);
 await capture('06-restored-route-compact',MINIMUM);
 await resize(WINDOW);await capture('07-restored-route-standard',WINDOW);assert.deepEqual(await hopNames(),['Jump A','Jump B']);
 await click('wizard.next.route');await capture('08-restored-review-standard',WINDOW);
 {
  const route=text(await reveal('wizard.review.route')),a=route.indexOf('Jump A'),b=route.indexOf('Jump B'),target=route.indexOf('127.0.0.1');
  assert(a>=0&&b>a&&target>b,'Restored review lists Jump A, Jump B, target in order: '+route);
 }
 await click('wizard.cancel');await closed();
 // Cancel wrote nothing: the fixture registry still holds exactly its two jump hosts.
 assert.equal(((await readFile(join(data,'hosts.toml'),'utf8')).match(/\[\[hosts\]\]/g)??[]).length,2);
 report.checks=['Fresh production editor window opens at 720×640 and stays usable at its 600×420 minimum','Native 16pt 保存密码 checkbox toggles; advanced host-key policy retained inside the advanced section','Two independent jump selections by keyboard in 32pt native selectors','Direct access hides the route and excludes it from review','Switching back restores both hops and their order','Restored route review and fixed footer remain usable at both sizes'];report.status='passed';
}catch(e){report.status='failed';report.error=String(e);await screenshot(join(out,'failure.png')).catch(()=>{});throw e;}
finally{await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));child.kill('SIGTERM');await ended;await log.close();await rm(isolated,{recursive:true,force:true});}
console.log(JSON.stringify(report));
