/** Actual Local zsh terminal: command overlays and retained history interactions.
 * Run with an already-built shared test-mode binary; no production config/SSH.
 * node e2e/command_annotations_native.ts OUT BINARY [light|dark]   (default dark)
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdir,mkdtemp,open,readFile,realpath,rm,writeFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {createHash} from 'node:crypto';
import * as h from '../zig-out/share/zenit/harness/client.ts';
import {settingsNav} from './settings_nav.ts';
const nav=settingsNav();
const out=resolve(process.argv[2]),binary=resolve(process.argv[3]),theme=process.argv[4]||'dark';await mkdir(out,{recursive:true});
assert(['light','dark'].includes(theme),'theme must be light or dark');
const base=await realpath(await mkdtemp(join(tmpdir(),'zw-command-annotations-'))),data=join(base,'data'),rpc=join(base,'rpc'),zdot=join(base,'zsh');await mkdir(data);await mkdir(rpc);await mkdir(zdot);await writeFile(join(zdot,'.zshrc'),'PS1="qa % "\n');
// [ai] error_hint=false: the failed-command hint toast (notifications toast stack, top right) would sit on top of the right-aligned
// metadata tags this script measures and captures; the hint itself is covered by notification_policy_app_native / notification_countdown_native.
await writeFile(join(data,'config.toml'),'[meta]\nconfig_revision=1\n[ui]\ntheme="'+theme+'"\ncommand_info=true\n[ai]\nerror_hint=false\n');process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const log=await open(join(out,'app.log'),'w');
const app=spawn(binary,[],{env:{...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1',ZEROWORK_DATA_DIR:data,ZDOTDIR:zdot,ZEROWORK_AUTOCONNECT:'0'},stdio:['ignore',log.fd,log.fd]});
const ended=new Promise(resolve=>app.once('close',(code,signal)=>resolve({code,signal})));
const report:any={status:'running',theme,binary,sha256:createHash('sha256').update(await readFile(binary)).digest('hex'),checks:[],captures:[],limits:['Actual production Local zsh and native App in isolated test-mode paths. Does not validate an external SSH endpoint or AI model provenance; those have separate production execution tests.']};
const shown=(n:any)=>n&&n.hidden!==true&&n.visible!==false&&(n.effective_opacity??1)>0&&n.rect?.w>0&&n.rect?.h>0;
const text=(n:any):string=>(n?.text??'')+(n?.children??[]).map(text).join('');
async function visible(id:string){return h.waitFor(async()=>(await h.query(id)).find(shown)??null,15000)}
async function hidden(id:string){await h.waitFor(async()=>!(await h.query(id)).some(shown)||null,8000)}
/** Negative-over-time check: the node must stay shown for the whole observation window. */
async function stays(id:string,ms:number,message:string){const end=Date.now()+ms;do{assert((await h.query(id)).some(shown),message);await h.sleep(40)}while(Date.now()<end)}
/** Negative-over-time check: the number of shown `id` nodes must stay `count` for the whole observation window. */
async function keepsCount(id:string,count:number,ms:number,message:string){const end=Date.now()+ms;do{assert.equal((await h.query(id)).filter(shown).length,count,message);await h.sleep(40)}while(Date.now()<end)}
async function click(id:string){const n=await visible(id);assert((await h.clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok)}
async function rows(){const all=[];for(let index=0;index<40;index++){const r=(await h.query(`terminal.surface.row.${index}`)).filter(shown);if(!r.length&&index>0)break;all.push(...r)}return all}
/** The shell prompt is on screen: the PTY is live and accepting input. PS1="qa % " (.zshrc above) renders as "qa "
 * because zsh expands "% " to nothing. */
async function promptReady(){await h.waitFor(async()=>(await rows()).find((r:any)=>text(r).startsWith('qa '))??null,15000)}
/** No left status gutter (removed in 04750679, which deleted the old left status icon node): on every row that
 * carries a metadata tag, the command text is the row's first visible text and starts at the row's own left edge. */
async function noLeftGutter(){
 const all=await rows();let tagged=0;
 for(const row of all){
  const kids=(row.children??[]).filter(shown);if(!kids.some((n:any)=>n.test_id==='terminal.command.metadata'))continue;tagged++;
  const first=kids.find((n:any)=>n.tag==='text');assert(first,'tagged row has its command text');
  assert(Math.abs(first.rect.x-row.rect.x)<0.5,`command text starts at the row edge, no left gutter (row x ${row.rect.x}, text x ${first.rect.x})`);
 }
 return tagged;
}
async function capture(name:string){await h.sleep(200);assert((await h.screenshot(join(out,name+'.png'))).ok);report.captures.push(name)}
async function submit(command:string){const n=await visible('terminal.surface');await h.clickAt(n.rect.x+60,n.rect.y+n.rect.h-45);assert((await h.type_(command)).ok);assert((await h.key('enter')).ok);await h.mouseMove(10,10)}
try{
 await h.waitForServerReady(60000);await h.resizeWindow(1280,800);await click('workspace.empty.local');await visible('terminal.surface');await promptReady();
 await submit("printf 'ZW_NATIVE_ANNOTATION_OK\\n'; false");
 await h.waitFor(async()=>(await h.query('terminal.command.metadata.code')).find((n:any)=>shown(n)&&text(n).includes('1'))??null,15000);
 assert.equal(await noLeftGutter(),1,'exactly the completed command row carries a tag');assert(!(await h.query('terminal.command.metadata.ai')).some(shown));await capture('manual-command-complete');
 report.checks.push('Actual Local command completion exposes one metadata tag with EXIT 1 and elapsed, without a left status icon; manual source has no AI badge');
 const code=await visible('terminal.command.metadata.code'),surface=await visible('terminal.surface'),tag=await visible('terminal.command.metadata');
 assert.equal(text(code),'EXIT 1','right metadata must label the exit code with EXIT');
 assert.equal(tag.rect.h,18,'the complete metadata tag stays compact'); // command_annotation_styles.zig metadata_height = 18, metadata_padding = 6
 assert(tag.rect.x>=surface.rect.x&&tag.rect.x+tag.rect.w<=surface.rect.x+surface.rect.w+0.5,'the tag stays inside the terminal surface, right aligned');
 assert(code.rect.x>=tag.rect.x+6&&code.rect.x+code.rect.w<=tag.rect.x+tag.rect.w-6,'EXIT is enclosed by the tag padding');
 assert(Math.abs(code.rect.y+code.rect.h/2-(tag.rect.y+tag.rect.h/2))<0.5,'metadata is centered inside the tag');
 await h.mouseMove(surface.rect.x+80,code.rect.y+code.rect.h/2);await hidden('terminal.command.metadata');await capture('command-hover-hidden');
 await h.mouseMove(10,10);await visible('terminal.command.metadata');report.checks.push('Pointer over command hides complete right metadata; leaving restores it');
 await submit('false');await h.waitFor(async()=>(await h.query('terminal.command.metadata.code')).filter((n:any)=>shown(n)&&text(n).includes('1')).length>=2||null,15000);
 await submit('false');await h.waitFor(async()=>(await h.query('terminal.command.metadata.code')).filter((n:any)=>shown(n)&&text(n).includes('1')).length>=3||null,15000);

 const metadataBeforeClick=(await h.query('terminal.command.metadata')).filter(shown).length;
 const emptyPoint={x:surface.rect.x+80,y:surface.rect.y+surface.rect.h-30};
 await h.mouseDown(emptyPoint.x,emptyPoint.y);
 await keepsCount('terminal.command.metadata',metadataBeforeClick,250,'holding a focus click on an empty row must preserve other command tags');
 await capture('empty-row-mouse-down');
 await h.mouseUp(emptyPoint.x,emptyPoint.y);
 await keepsCount('terminal.command.metadata',metadataBeforeClick,250,'releasing an empty-row click must preserve other command tags');
 await capture('empty-row-click');await h.mouseMove(10,10);
 report.checks.push('Pressing, holding and releasing a focus click on an empty terminal row preserves all existing command metadata tags');
 // Command history trigger (d6c927e3 title-click): the Local status bar button is gone from view; the trigger is the title
 // bar tool `status.command-history` (title_tools.zig buttonId). It opens on click only — hovering shows its Tooltip
 // (`status.command-history.tooltip`) and nothing else; there is no hover preview and no mouse-leave close any more
 // (command_history_view.zig header: "opens on click only … A second click, Escape or an outside click closes it").
 const button=await visible('status.command-history'),buttonCenter={x:button.rect.x+button.rect.w/2,y:button.rect.y+button.rect.h/2};
 await h.mouseMove(buttonCenter.x,buttonCenter.y);const tip=await visible('status.command-history.tooltip');assert(text(tip).includes('命令历史'),'trigger tooltip names the tool');
 assert(!(await h.query('terminal.command-history')).some(shown),'hovering the trigger must not open the history panel');await capture('history-hover-tooltip-only');
 assert((await h.clickAt(buttonCenter.x,buttonCenter.y)).ok);const panel=await visible('terminal.command-history');
 await h.waitFor(async()=>(await h.query('terminal.command-history.record')).filter(shown).length>=3||null,10000);
 // Record cards fill the list column: command_history_styles.zig row() is `.width = .fill()` inside panel() (width 336,
 // padding 12), so every card has the header's content width (312) whatever its command length, and the command text
 // (wrap .char, max_height 54, ellipsis) stays inside its card instead of widening it past the panel.
 {
  const header=await visible('terminal.command-history.header'),records=(await h.query('terminal.command-history.record')).filter(shown),texts=(await h.query('terminal.command-history.command')).filter(shown);
  report.history_geometry={panel:panel.rect,header:header.rect,records:records.map((n:any)=>n.rect),commands:texts.map((n:any)=>n.rect)};
  for(const r of records)assert(Math.abs(r.rect.x-header.rect.x)<0.5&&Math.abs(r.rect.w-header.rect.w)<0.5,`history record spans the list column (record x ${r.rect.x} w ${r.rect.w}, header x ${header.rect.x} w ${header.rect.w})`);
  for(const c of texts)assert(records.some((r:any)=>c.rect.x>=r.rect.x-0.5&&c.rect.x+c.rect.w<=r.rect.x+r.rect.w+0.5&&c.rect.y>=r.rect.y-0.5&&c.rect.y+c.rect.h<=r.rect.y+r.rect.h+0.5),'history command text stays inside its card');
 }
 const commands=(await h.query('terminal.command-history.command')).filter(shown).map(text);assert(commands.filter((s:string)=>s==='false').length>=2);report.checks.push('Repeated human command executions remain separate native cards with real completion metadata');
 // Pointer entering the card and then leaving both the card and the trigger keeps the click-opened panel (no mouse-leave close).
 await h.mouseMove(panel.rect.x+30,panel.rect.y+30);await hidden('status.command-history.tooltip');await visible('terminal.command-history');
 await h.mouseMove(10,10);await stays('terminal.command-history',700,'leaving the panel must not close it');await capture('history-pinned');
 // Escape closes the click-opened panel. (Opened with ⇧⌘B instead, keyboard focus lands on the close button and shows its
 // focus Tooltip, so the first Escape dismisses that Tooltip and the second closes the panel — zenit's topmost-overlay-first
 // Escape; that layering is not asserted here.)
 await h.key('escape');await hidden('terminal.command-history');
 await h.key('b',{shift:true,cmd:true});await visible('terminal.command-history');await h.key('b',{shift:true,cmd:true});await hidden('terminal.command-history');
 await h.clickAt(buttonCenter.x,buttonCenter.y);await visible('terminal.command-history');await h.clickAt(buttonCenter.x,buttonCenter.y);await hidden('terminal.command-history');
 await h.key('b',{shift:true,cmd:true});await visible('terminal.command-history');
 report.checks.push('History trigger hover shows only its tooltip; click opens the panel, pointer leave keeps it; ShiftCmdB, Escape and a second trigger click close it');
 await click('terminal.command-history.close');await hidden('terminal.command-history');await h.mouseMove(10,10);
 await submit('sleep 2; true');
 await h.waitFor(async()=>(await h.query('terminal.command.metadata.code')).find((n:any)=>shown(n)&&text(n)==='—')??null,10000);await capture('command-running');
 await h.waitFor(async()=>!(await h.query('terminal.command.metadata.code')).some((n:any)=>shown(n)&&text(n)==='—')||null,10000);report.checks.push('Actual running Local command has unknown exit placeholder until its real completion; elapsed updates without a fabricated exit');
 const longCommand="printf '%s\\n' 'ZW_LONG_WRAP_"+'abcdefghijklmnopqrstuvwxyz0123456789'.repeat(5)+"'; true";
 await submit(longCommand);await h.waitFor(async()=>(await h.query('terminal.command.metadata.code')).filter((n:any)=>shown(n)&&text(n).includes('0')).length>=2||null,15000);await capture('long-command-first-row');
 const groups=(await h.query('terminal.command.metadata')).filter(shown).sort((a:any,b:any)=>a.rect.y-b.rect.y),last=groups.at(-1);assert(last);const countBefore=groups.length;
 await h.mouseMove(surface.rect.x+80,last.rect.y+last.rect.h+2);await h.waitFor(async()=>(await h.query('terminal.command.metadata')).filter(shown).length===countBefore-1||null,8000);await capture('long-command-continuation-hover');await h.mouseMove(10,10);await h.waitFor(async()=>(await h.query('terminal.command.metadata')).filter(shown).length===countBefore||null,8000);report.checks.push('Actual wrapped long command has a single first-row group; hover on its continuation hides only that command metadata and leaving restores it');

 await submit('clear');await hidden('terminal.command.metadata');await capture('clear-removes-old-markers');
 await submit("printf 'ZW_AFTER_CLEAR_A\\nZW_OUTPUT_A\\n'; true");
 await h.waitFor(async()=>(await h.query('terminal.command.metadata.code')).find((n:any)=>shown(n)&&text(n)==='EXIT 0')??null,15000);
 await submit("printf 'ZW_AFTER_CLEAR_B\\nZW_OUTPUT_B\\n'; false");
 await h.waitFor(async()=>(await h.query('terminal.command.metadata.code')).find((n:any)=>shown(n)&&text(n)==='EXIT 1')??null,15000);
 async function alignedAfterClear(){
  const codes=(await h.query('terminal.command.metadata.code')).filter(shown).sort((a:any,b:any)=>a.rect.y-b.rect.y);
  assert.deepEqual(codes.map(text),['EXIT 0','EXIT 1']);assert.equal(await noLeftGutter(),2,'both new commands are tagged, without a left gutter');
  const gridRows=await rows();
  for(const [i,marker]of codes.entries()){
   const row=gridRows.find((r:any)=>Math.abs(r.rect.y+r.rect.h/2-(marker.rect.y+marker.rect.h/2))<0.5);assert(row,'marker must align with an actual grid row');
   const body=(row.children??[]).filter((n:any)=>shown(n)&&n.tag==='text'&&!n.test_id?.startsWith('terminal.command.')).map(text).join('');
   assert(body.includes(i===0?'ZW_AFTER_CLEAR_A':'ZW_AFTER_CLEAR_B'),'marker must be on the submitted command, not its output or an empty row');
  }
  report.clear_geometry={codes:codes.map((n:any)=>({text:text(n),rect:n.rect}))};
 }
 await alignedAfterClear();await capture('new-commands-after-clear');await h.resizeWindow(1000,700);await h.sleep(250);await alignedAfterClear();await capture('new-commands-resized');await h.resizeWindow(1280,800);
 report.checks.push('Clear removes both old decorations while retained history remains; subsequent success/failure tags align with their actual submitted command rows before and after resize');

 await nav.toField('command_info');await nav.click('settings.toggle.command_info');await nav.save();await nav.close();await h.mouseMove(10,10);await hidden('terminal.command.metadata');assert.equal(await noLeftGutter(),0,'no row keeps a tag');report.checks.push('Saving global command_info=false immediately hides right metadata on the existing Local session');await capture('right-tag-hidden');
 assert((await h.request('POST','/quit')).ok);report.exit=await Promise.race([ended,h.sleep(20000).then(()=>null)]);assert(report.exit&&report.exit.code===0&&report.exit.signal===null,'isolated App did not quit cleanly');report.status='passed';
}catch(error){report.status='failed';report.error=String(error);await writeFile(join(out,'failure-tree.json'),JSON.stringify(await h.tree({visibleOnly:true}),null,2)).catch(()=>{});await capture('failure').catch(()=>{});process.exitCode=1}
finally{if(app.exitCode===null&&app.signalCode===null){app.kill('SIGTERM');await Promise.race([ended,h.sleep(3000)]);if(app.exitCode===null&&app.signalCode===null){app.kill('SIGKILL');await ended}}await log.close();await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));await rm(base,{recursive:true,force:true})}
console.log(JSON.stringify({status:report.status,error:report.error,out}));
