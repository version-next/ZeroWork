/** Production connection editor: copy-from-existing child dialog, group choice, save and edit read-back. */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdir,mkdtemp,realpath,open,readFile,rm,writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {waitForServerReady,waitFor,query,tree,clickAt,key,type_,inputState,resizeWindow,screenshot,screenPos,scrollAt,mouseMove,windows} from '../zig-out/share/zenit/harness/client.ts';
const binary=resolve(process.argv[2]),out=resolve(process.argv[3]),theme=process.argv[4]??'dark';
assert(['dark','light','sauber'].includes(theme));
await mkdir(out,{recursive:true});
const isolated=await realpath(await mkdtemp(join(tmpdir(),'zw-wizard-copy-'))),data=join(isolated,'data'),rpc=join(isolated,'rpc');
await mkdir(data);await mkdir(rpc);
await writeFile(join(data,'hosts.toml'),`[registry]
schema_version=2
revision=1
next_connection_id=2
next_group_id=3
[[groups]]
group_id=1
revision=1
name="Source group"
[[groups]]
group_id=2
revision=1
name="Empty group"
[[hosts]]
connection_id=1
revision=1
protocol="ssh"
name="Copy source"
host="192.0.2.1"
port=2222
user="fixture"
asset_group_id=1
auth_mode="password"
startup_commands=["echo fixture"]
`);
await writeFile(join(data,'config.toml'),`[meta]\nconfig_revision=1\n[ui]\ntheme="${theme}"\nfont_family="Menlo"\nfont_size=14\n`);
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const log=await open(join(out,'app.log'),'w');
const child=spawn(binary,[],{env:{...process.env,ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1'},stdio:['ignore',log.fd,log.fd]});
const ended=new Promise<void>(r=>child.once('close',()=>r()));
const report:any={status:'running',binary,sha256:createHash('sha256').update(await readFile(binary)).digest('hex'),theme,checks:[],stages:[],limits:['Synthetic Harness input, not physical keyboard/IME verification','Only Save writes the isolated fixture registry; no network or remote action']};
// Island B v3 (e1372d88): the connection editor is its own native window (wizard.zig window_spec 720×640, minimum
// 600×420). While it is open the Harness is bound to it; there is no in-window close button (`wizard.close` /
// `wizard.dialog` exist only in the preview mount). The copy child is a native zenit Modal inside that window
// (editor.zig: `Modal(.{ .width = 440, .max_height = 320 })`, test id wizard.copy.dialog).
const WINDOW={w:720,h:640},MINIMUM={w:600,h:420},COPY_WIDTH=440;
const shown=(n:any)=>n&&n.visible!==false&&n.hidden!==true&&(n.effective_opacity??1)>0&&n.rect?.w>0&&n.rect?.h>0;
const flatten=(n:any):any[]=>[n,...(n.children??[]).flatMap(flatten)];
const text=(n:any)=>flatten(n).map(x=>x.text??'').join(' ');
async function nodes(id:string):Promise<any[]>{const q=await query(id);return Array.isArray(q)?q:[];}
async function current(id:string){return (await nodes(id)).find(shown)??null;}
async function visible(id:string){return waitFor(()=>current(id));}
const SCROLLS=['wizard.scroll.identity','wizard.scroll.route','wizard.scroll.review'];
/** The node, scrolled fully into its step's scroll viewport when it lives in one. */
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
/** Click the centre of a node once it is revealed and its rect has stopped moving. */
async function click(id:string){let prior='';const n=await waitFor(async()=>{const n=await reveal(id);const at=JSON.stringify(n.rect);const still=at===prior;prior=at;return still?n:null;});assert((await clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok,id);}
async function value(id:string){return (await inputState(id)).buffer;}
async function fill(id:string,v:string){await click(id);await key('a',{cmd:true});await type_(v);await waitFor(async()=>await value(id)===v||null);}
/** The editor window is open (bound) and its frame fills it. */
/** The editor window is open and bound, its frame filling it. `screenPos` answers with the rect only: a query for
 *  the window root would serialise the whole editor tree (too large once the test logs are expanded). */
async function editorOpen(size=WINDOW){return waitFor(async()=>{const w=(await windows()).windows;if(w.length!==2||!w[1].bound)return null;const r:any=await screenPos('wizard.window');return r&&r.x===0&&r.y===0&&r.w===size.w&&r.h===size.h?{rect:r}:null;});}
/** Back to the main window only. */
async function closed(){await waitFor(async()=>{const w=(await windows()).windows;return w.length===1&&w[0].bound&&!(await nodes('wizard.window')).some(shown)?true:null;});}
async function copyClosed(){await waitFor(async()=>!(await current('wizard.copy.dialog'))||null);}
async function capture(name:string){await mouseMove(2,2);const w:any=await screenPos('wizard.window'),d=await current('wizard.copy.dialog');await writeFile(join(out,name+'.json'),JSON.stringify({window:w?.w?w:null,copy:d?.rect??null},null,2));assert((await screenshot(join(out,name+'.png'))).ok);report.stages.push({name,window:w?.w?w:null,copy:d?.rect??null});}
/** Copy child: 440 wide, centred in the editor window, inside it; its footer actions inside the dialog. */
async function copyDialog(size:{w:number,h:number}){
 const d=await visible('wizard.copy.dialog'),src=await visible('wizard.copy.source'),cancel=await visible('wizard.copy.cancel'),apply=await visible('wizard.copy.apply');
 assert.equal(d.rect.w,COPY_WIDTH);assert(Math.abs(d.rect.x+d.rect.w/2-size.w/2)<.5&&Math.abs(d.rect.y+d.rect.h/2-size.h/2)<.5,'copy dialog centred in the editor window: '+JSON.stringify(d.rect));
 assert(d.rect.y>=0&&d.rect.y+d.rect.h<=size.h,'copy dialog inside the window');
 for(const n of [src,cancel,apply])assert(n.rect.x>=d.rect.x&&n.rect.x+n.rect.w<=d.rect.x+d.rect.w&&n.rect.y>=d.rect.y&&n.rect.y+n.rect.h<=d.rect.y+d.rect.h,n.test_id+' inside the copy dialog');
 // The parent editor stays open underneath (one editor window, its draft fields still mounted).
 assert.equal((await windows()).windows.length,2);await visible('wizard.name');
 return d;
}
/** Option rows of an open Select popup (the panel's text rows, in order), outside the trigger. */
async function popupOptions(panelId:string){const p=await visible(panelId);return flatten(p).filter((n:any)=>n.text&&shown(n));}
async function pickOption(panelId:string,label:string){const row=await waitFor(async()=>(await popupOptions(panelId)).find((n:any)=>n.text===label)??null);assert((await clickAt(row.rect.x+row.rect.w/2,row.rect.y+row.rect.h/2)).ok,label);await waitFor(async()=>!(await current(panelId))||null);}
/** Searchable copy-source Select: open, first option by keyboard, Return. */
async function chooseSource(){
 await click('wizard.copy.source');
 // The popup lists the saved host outside the trigger.
 await waitFor(async()=>{const t=await tree({visibleOnly:true});const trig=(await current('wizard.copy.source'))!;return flatten(t).some((n:any)=>n.text==='Copy source'&&shown(n)&&!(n.rect.y>=trig.rect.y&&n.rect.y<trig.rect.y+trig.rect.h))||null;});
 await key('down');await key('return');
 await waitFor(async()=>/Copy source/.test(text(await visible('wizard.copy.source')))||null);
}
try{
 await waitForServerReady(30000);assert.equal(Number(JSON.parse(await readFile(join(rpc,'owner.json'),'utf8')).pid),child.pid);
 await resizeWindow(1440,900);await click('sidebar.footer.new');await editorOpen();assert.match(text(await visible('wizard.title')),/新建主机/);
 await fill('wizard.name','Original draft');await fill('wizard.host','127.0.0.1');await fill('wizard.user','unchanged');
 const originalNameId=(await visible('wizard.name')).id;
 await click('wizard.copy.open');const modal=await copyDialog(WINDOW);await capture('01-copy-modal');
 // Choosing a source and cancelling leaves the draft untouched (same field node, same text).
 await chooseSource();await click('wizard.copy.cancel');await copyClosed();
 assert.equal((await visible('wizard.name')).id,originalNameId);assert.equal(await value('wizard.name'),'Original draft');assert.equal(await value('wizard.host'),'127.0.0.1');assert.equal(await value('wizard.user'),'unchanged');await capture('02-copy-cancel');
 // Escape dismisses only the child: the editor window stays with its draft.
 await click('wizard.copy.open');await copyDialog(WINDOW);await chooseSource();await key('escape');await copyClosed();
 await editorOpen();assert.equal(await value('wizard.name'),'Original draft');
 // Explicit apply copies the source fields; the copy gets a new identity (“-副本”) and the source's group.
 await click('wizard.copy.open');await copyDialog(WINDOW);await chooseSource();await click('wizard.copy.apply');await copyClosed();
 assert.equal(await value('wizard.name'),'Copy source-副本');assert.equal(await value('wizard.host'),'192.0.2.1');assert.equal(await value('wizard.port'),'2222');assert.equal(await value('wizard.user'),'fixture');assert.equal(await value('wizard.group'),'Source group');
 await capture('03-copy-applied');
 // 资产分组 is a combo box (editor.zig: Input wizard.group + Select wizard.group.pick, menu wizard.group.menu): its
 // menu lists 未分组 and every registry group, including the empty one; picking fills the input.
 await click('wizard.group.pick');
 assert.deepEqual((await popupOptions('wizard.group.menu')).map((n:any)=>n.text),['未分组','Source group','Empty group']);
 await pickOption('wizard.group.menu','Empty group');
 await waitFor(async()=>await value('wizard.group')==='Empty group'||null);assert.match(text(await visible('wizard.group')),/Empty group/);await capture('04-group-selected');
 // Advanced: SSH 传输压缩 is a native RadioGroup (关闭 / 开启); 启动命令 is a Textarea, one command per line.
 await click('wizard.advanced.toggle');await visible('wizard.advanced.body');
 await click('wizard.compression.enabled');
 await waitFor(async()=>(await visible('wizard.compression')).children.filter((c:any)=>c.component==='RadioChoice'&&c.children?.[0]?.children?.[0]?.visible!==false).map((c:any)=>c.test_id).join()==='wizard.compression.enabled'||null);
 await click('wizard.startup');await key('a',{cmd:true});await type_('echo saved first');await key('return');await type_('echo saved second');
 await waitFor(async()=>await value('wizard.startup')==='echo saved first\necho saved second'||null);
 await click('wizard.next.identity');await click('wizard.next.route');await visible('wizard.review.name');assert.match(text(await visible('wizard.review.name')),/Copy source-副本/);
 await capture('05-copy-review');await click('wizard.save_only');await closed();
 // Only Save writes: one new host with the copied fields, both commands, compression and the empty group's id.
 const saved=await readFile(join(data,'hosts.toml'),'utf8');assert.equal((saved.match(/\[\[hosts\]\]/g)??[]).length,2);
 const added=saved.slice(saved.lastIndexOf('[[hosts]]'));
 assert.match(added,/name\s*=\s*"Copy source-副本"/);assert.match(added,/host\s*=\s*"192\.0\.2\.1"/);assert.match(added,/port\s*=\s*2222/);
 assert(added.includes('echo saved first')&&added.includes('echo saved second'));assert.match(added,/compression\s*=\s*true/);assert.match(added,/asset_group_id\s*=\s*2/);
 assert.match(saved.slice(0,saved.lastIndexOf('[[hosts]]')),/name\s*=\s*"Copy source"/,'source host unchanged');
 await capture('06-copy-saved');
 // Edit read-back: the sidebar row's context menu → 编辑主机配置 (context_menus.zig .edit_host, test id
 // context.menu.edit_host; the hover-only sidebar.host.edit button is gone since Island B v3).
 const host=await waitFor(async()=>(await nodes('sidebar.host')).find(n=>shown(n)&&text(n).includes('副本'))??null);
 assert((await clickAt(host.rect.x+host.rect.w/2,host.rect.y+host.rect.h/2,1,'right')).ok);await visible('context.menu');
 await click('context.menu.edit_host');await editorOpen();
 await waitFor(async()=>await value('wizard.name')==='Copy source-副本'||null);assert.equal(await value('wizard.group'),'Empty group');assert.equal(await value('wizard.host'),'192.0.2.1');
 await click('wizard.advanced.toggle');await visible('wizard.advanced.body');
 assert.equal(await value('wizard.startup'),'echo saved first\necho saved second');
 assert.deepEqual((await visible('wizard.compression')).children.filter((c:any)=>c.component==='RadioChoice'&&c.children?.[0]?.children?.[0]?.visible!==false).map((c:any)=>c.test_id),['wizard.compression.enabled']);
 await reveal('wizard.startup');await capture('06b-copy-reloaded');await click('wizard.cancel');await closed();
 assert.equal(await readFile(join(data,'hosts.toml'),'utf8'),saved,'cancelling the edit writes nothing');
 // Minimum editor window: the copy child keeps its width, stays centred and inside the window.
 await click('sidebar.footer.new');await editorOpen();assert.match(text(await visible('wizard.title')),/新建主机/);
 assert((await resizeWindow(MINIMUM.w,MINIMUM.h)).ok);await editorOpen(MINIMUM);
 await click('wizard.copy.open');const compact=await copyDialog(MINIMUM);await capture('07-copy-compact');
 await click('wizard.copy.close');await copyClosed();await click('wizard.cancel');await closed();
 report.checks=['Copy dialog opens at 440 pt, centred in the editor window','Selection then cancel preserves current draft','Escape dismisses only the child','Explicit apply copies source fields and gives the copy a new identity','Group combo box lists the empty registry group; its choice persists as the durable group id','Textarea commands and compression persist only on Save and read back through the context-menu edit','Minimum editor window keeps the child centred and within bounds'];report.geometry={copy:modal.rect,compact:compact.rect};report.status='passed';
}catch(e){report.status='failed';report.error=String(e);await screenshot(join(out,'failure.png')).catch(()=>{});throw e;}
finally{await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));child.kill('SIGTERM');await ended;await log.close();await rm(isolated,{recursive:true,force:true});}
console.log(JSON.stringify(report));
