/** V3 builtin composite document acceptance through the real Local PTY and native Surface. */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdir,mkdtemp,realpath,copyFile,readFile,writeFile,open,readdir,rm} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {createHash} from 'node:crypto';
import {readPasteboardText} from './private_pasteboard.ts';
import {waitForServerReady,waitFor,query,clickAt,key,type_,resizeWindow,screenshot,sleep,scrollAt,mouseDown,mouseMove,mouseUp} from '../zig-out/share/zenit/harness/client.ts';
const out=resolve(process.argv[2]),source=resolve(process.argv[3]);await mkdir(out,{recursive:false});
const iso=await realpath(await mkdtemp(join(tmpdir(),'zw-builtin-records-'))),rpc=join(iso,'rpc'),data=join(iso,'data'),shell=join(iso,'shell');
// Always remove this run's sandbox, including setup and reporting failures.
try {
await Promise.all([mkdir(rpc),mkdir(data),mkdir(shell)]);
await writeFile(join(shell,'.zshrc'),"bindkey -e\nPS1='records%# '\n");
await writeFile(join(data,'config.toml'),'[meta]\nconfig_revision=1\n[ui]\ntheme="dark"\nfont_family="Menlo"\nfont_size=14\n');
await copyFile(source,join(iso,'zerowork'));await copyFile(join(source,'..','zw_ipc.so'),join(iso,'zw_ipc.so'));
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;const log=await open(join(out,'app.log'),'w');const app=spawn(join(iso,'zerowork'),[],{env:{...process.env,ZDOTDIR:shell,ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1'},stdio:['ignore',log.fd,log.fd]});const ended=new Promise(r=>app.once('close',r));
const report:any={status:'running',pid:app.pid,isolated:iso,sha256:createHash('sha256').update(await readFile(source)).digest('hex'),checks:[],captures:[],limits:['Public synthetic Harness on actual Metal window; no physical CUA/IME/VoiceOver acceptance.','Physical CUA middle-click menu/IME/VoiceOver and SSH transport acceptance are separate checks.']};
const flat=(n:any):any[]=>[n,...(n.children??[]).flatMap(flat)];
const content=(n:any):string=>!shown(n)?'':(n.text??'')+(n.children??[]).map(content).join('');
const shown=(n:any)=>n&&n.hidden!==true&&n.visible!==false&&(n.effective_opacity??1)>0&&n.rect?.w>0&&n.rect?.h>0;
const vis=(id:string)=>waitFor(async()=>(await query(id)).find(shown)??null,12000),hidden=(id:string)=>waitFor(async()=>!(await query(id)).some(shown)||null,12000);
async function click(id:string){const n=await vis(id);assert((await clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok)}
async function press(name:string,mods?:any){assert((await key(name,mods)).ok)}
async function type(text:string){assert((await type_(text)).ok)}
async function capture(name:string){await sleep(180);assert((await screenshot(join(out,name+'.png'))).ok);const nodes:any={};for(const id of ['terminal.surface','terminal.commands','terminal.command.input','terminal.command.record','terminal.command.output','terminal.command.source','terminal.command.article','terminal.command.state','terminal.search.count','terminal.search.query','tabs.strip'])nodes[id]=await query(id);await writeFile(join(out,name+'.json'),JSON.stringify(nodes,null,2));report.captures.push(name)}
async function palette(){await type('@');await vis('terminal.commands')}
async function command(value:string){await palette();await type(value);await press('right');await hidden('terminal.commands');await press('return');await sleep(350)}
async function outputs(){return (await query('terminal.command.output')).filter(shown).map(content).join('\n')}
async function records(){return (await query('terminal.command.record')).filter(shown).map(content)}
try{
 await waitForServerReady();assert.equal(Number(JSON.parse(await readFile(join(rpc,'owner.json'),'utf8')).pid),app.pid);await resizeWindow(1100,760);await click('workspace.empty.local');await vis('terminal.surface');await sleep(1500);
 const before=join(iso,'before.txt');await type(`printf '%s' ready > ${JSON.stringify(before)}`);await press('return');await waitFor(async()=>{try{return await readFile(before,'utf8')==='ready'||null}catch{return null}},15000);await sleep(300);
 await palette();await type('ts invalid');await press('right');await hidden('terminal.commands');await capture('01-adopted-invalid-command');await press('return');await waitFor(async()=>(await outputs()).includes('开关只接受 on/off')||null);await capture('02-error-document-record');
 const geometryRow=(await query('terminal.command.record')).find(shown),geometryBadge=(await query('terminal.command.source')).find(shown),geometryCard=(await query('terminal.command.article')).find(shown),geometrySurface=await vis('terminal.surface');
 // Ungrouped terminal insets [top 10, right 16, bottom 12, left 16]: src/features/terminal/view/terminal_styles.zig contentPadding(false),
 // Island B v3 (Pencil hMIT7 / i3Zme8), set by e1372d88 (the earlier 4px / 8px values were replaced there). Rows span exactly the padded width.
 assert(Math.abs(geometryRow.rect.x-geometrySurface.rect.x-16)<.6,`Single terminal content uses the 16px left inset: ${JSON.stringify({row:geometryRow.rect,surface:geometrySurface.rect})}`);
 assert(Math.abs(geometrySurface.rect.x+geometrySurface.rect.w-16-(geometryRow.rect.x+geometryRow.rect.w))<.6,`Single terminal content uses the 16px right inset: ${JSON.stringify({row:geometryRow.rect,surface:geometrySurface.rect})}`);
 assert(Math.abs(geometryBadge.rect.w-56.5390625)<.6,'Source marker uses the final natural system-font width');
 assert(Math.abs(geometryCard.rect.x-geometryRow.rect.x)<.6&&Math.abs(geometryCard.rect.w-geometryRow.rect.w)<.6,'Application card stays inside the terminal content edges');
 report.checks.push('Single-pane content uses the 16px horizontal insets, preserves natural marker width and keeps cards inside the content edges');
 const initial=await records();assert(initial.some(v=>v.includes('@ts invalid')));await press('escape');assert((await outputs()).includes('开关只接受 on/off'));await capture('03-escape-retains-record');report.checks.push('Concrete error and command remain ordered document rows after cancelling editable draft');
 const after=join(iso,'after.txt');await type(`printf '%s' shell-continues > ${JSON.stringify(after)}`);await press('return');await waitFor(async()=>{try{return await readFile(after,'utf8')==='shell-continues'||null}catch{return null}},10000);await capture('04-following-real-shell');
 const surface=await vis('terminal.surface');const all=flat(surface).filter(shown),error=(await query('terminal.command.output')).find(shown);// Adjacent ASCII cells of one style are one native text run on the fixed terminal grid (terminal_surface.zig renderGlyphs:
 // "Adjacent ASCII cells share one native text run"), so the shell prompt is a run starting with PS1, not a lone 'r' glyph.
 const later=all.filter(n=>typeof n.text==='string'&&n.text.startsWith('records% ')&&n.rect.y>=error.rect.y+error.rect.h).sort((a,b)=>a.rect.y-b.rect.y);
 assert(later.some(n=>n.text.includes('shell-continues')),`the following real shell command line is below the retained app record: ${JSON.stringify(later.map(n=>[n.rect.y,n.text]))}`);assert(later.at(-1).text.trim()==='records%','a fresh real shell prompt follows it');report.checks.push('Subsequent real Shell command executes and its prompt is below the retained app record');
 const commandRow=(await query('terminal.command.record')).find(shown);const first=flat(commandRow).find(n=>shown(n)&&n.text==='@ts invalid');assert(first,'the app command is one native ASCII run in its record row');
 // One run spans text.length grid columns; the app record must sit on the same cell advance as the real shell prompt run.
 const width=first.rect.w/first.text.length,promptRun=later.at(-1),promptWidth=promptRun.rect.w/promptRun.text.length,y=first.rect.y+first.rect.h/2;assert(width>0&&Math.abs(width-promptWidth)<.01,`app record and shell share the terminal cell advance: ${width} vs ${promptWidth}`);await mouseDown(first.rect.x+1,y);await mouseMove(first.rect.x+11*width-1,y);await mouseUp(first.rect.x+11*width-1,y);await sleep(180);assert.equal((await readPasteboardText()),'@ts invalid');report.checks.push('Actual native clipboard from composite selection contains pure command without timestamps/status/control bytes');
 await click('terminal.surface');await sleep(100);assert(!(await query('terminal.message')).some(shown),'Blank grid click must not report a terminal error');await command('ts');await waitFor(async()=>(await outputs()).includes('已开启时间戳')||null);assert.equal((await records()).length,2);await capture('05-success-record-with-timestamps');report.checks.push('Success creates a second command/result record and toggles actual timestamp gutter');
 await type("printf 'line%02d\\n' {1..55}");await press('return');await sleep(500);const sc=await vis('terminal.surface');await scrollAt(sc.rect.x+sc.rect.w/2,sc.rect.y+sc.rect.h/2,0,2500);await waitFor(async()=>(await records()).some(v=>v.includes('@ts invalid'))||null);await capture('06-records-scrolled-back');report.checks.push('Native wheel scroll returns to application records above later shell output');
 await press('f',{cmd:true});await vis('terminal.search.query');await type('@ts invalid');await waitFor(async()=>content(await vis('terminal.search.count')).includes('1')||null);await capture('07-search-locates-record');await click('terminal.search.close');report.checks.push('Production Cmd+F searches and locates the retained application command');
 // 06 / 07 left the view on the older records (wheel scroll back, search locate). Typing at the prompt returns the view to
 // the live prompt (terminal_document.zig write / key / commitPaste set follow=true); the line-start '@' that opens the
 // palette is typed input too, so the palette must open visibly at the live prompt and not anchor to an off-screen caret.
 await type('@');await waitFor(async()=>(await query('terminal.commands')).find(shown)??null,12000).catch(async(error:any)=>{throw new Error(`typing @ after scrolling back must show the command palette at the live prompt: ${JSON.stringify({input:(await query('terminal.command.input')).map((n:any)=>n.rect),surface:(await vis('terminal.surface')).rect})} ${error}`)});
 await type('log');await press('right');await hidden('terminal.commands');await press('return');await sleep(350);await capture('08-history-records');
 // In frozen history the record row is one grid text run: the command after blank cells covering the source marker
 // ("        @log"), so the command starts that many cell advances into the row.
 const logRow=(await query('terminal.command.record')).filter(shown).find(n=>content(n).trim()==='@log');assert(logRow,'@log history record row');const badges=(await query('terminal.command.source')).filter(shown);const badge=badges.find(n=>Math.abs(n.rect.y-logRow.rect.y-2)<.5);const hx=logRow.rect.x+(logRow.text.length-logRow.text.trimStart().length)*width,hy=logRow.rect.y+logRow.rect.h/2;assert(badge&&Math.abs(badge.rect.x+56.5390625+10-hx)<.6,'History badge and command must preserve the measured natural marker width plus 10px gap');await mouseDown(hx+1,hy);await mouseMove(hx+3.9*width,hy);await mouseUp(hx+3.9*width,hy);await sleep(120);assert.equal((await readPasteboardText()),'@log');await press('f',{cmd:true});await vis('terminal.search.query');await press('a',{cmd:true});await type('@ts invalid');await waitFor(async()=>content(await vis('terminal.search.count')).includes('1')||null);await waitFor(async()=>(await records()).some(v=>v.includes('@ts invalid'))||null);await capture('08b-history-search-record');await click('terminal.search.close');await press('escape');await sleep(250);report.checks.push('Actual @log history retains final app records; native history copy returns pure @log; frozen history search locates older app records; Escape returns to live');
 await type("printf '\\033[2J\\033[Hclear-ok\\n'");await press('return');await sleep(450);await capture('09-clear-native-screen');assert(!(await records()).some(v=>v.includes('@ts invalid')));report.checks.push('Real VT screen clear invalidates live insertion anchors; app records do not float over the cleared screen');
 await type('exit');await press('return');await vis('local.ended.close');await click('local.ended.close');await sleep(800);
 const history=join(data,'logs','history');const files=await readdir(history);const casts=await Promise.all(files.filter(v=>v.endsWith('.cast')).map(v=>readFile(join(history,v),'utf8')));assert(casts.some(v=>v.includes('"a"')&&v.includes('@ts invalid')&&v.includes('已开启时间戳')));for(const cast of casts){const events=cast.trim().split('\n').slice(1).map(l=>JSON.parse(l));assert(events.every(e=>e[0]<120),'Application wallclock metadata must not corrupt stream-relative replay time');}report.checks.push('Normal shell exit/tab close persists separate application a events in actual owned Local archive');
 await click('workspace.empty.local');await vis('terminal.surface');await sleep(1600);await command('grp Geometry');await vis('groups.workspace'); /* 88529dc0: one-member group shows its pane */
 await click('toolbar.new_session');await click('session.menu.local');await vis('terminal.surface');await sleep(1600);await command('grp Geometry');
 await waitFor(async()=>(await query('terminal.surface')).filter(shown).length===2||null,15000);await sleep(250);
 const groupedSurfaces=(await query('terminal.surface')).filter(shown);const groupedGeometry=[];
 for(const pane of groupedSurfaces){const viewport=flat(pane).find((n:any)=>shown(n)&&n.test_id==='terminal.surface.viewport');assert(viewport);const rows=(viewport.children??[]).filter((n:any)=>shown(n)&&/^terminal\.(surface\.row\.|command\.(record|output))/.test(n.test_id??''));assert(rows.length>0);
  // A split pane under its header uses [top 2, right 12, bottom 10, left 12] (terminal_styles.zig contentPadding(true), Island B v3 e1372d88).
  assert(rows.every((n:any)=>Math.abs(n.rect.x-pane.rect.x-12)<.6&&Math.abs(pane.rect.x+pane.rect.w-n.rect.x-n.rect.w-12)<.6),`Grouped terminal rows use the 12px horizontal inset: ${JSON.stringify({pane:pane.rect,rows:rows.map((n:any)=>n.rect)})}`);
  assert(Math.abs(viewport.rect.y-pane.rect.y-2)<.6&&Math.abs(pane.rect.y+pane.rect.h-viewport.rect.y-viewport.rect.h-10)<.6,`Grouped terminal reserves 2px above and 10px below its viewport: ${JSON.stringify({pane:pane.rect,viewport:viewport.rect})}`);groupedGeometry.push({surface:pane.rect,rows:rows.map((n:any)=>({test_id:n.test_id,rect:n.rect}))})}
 await writeFile(join(out,'group-geometry.json'),JSON.stringify(groupedGeometry,null,2));await capture('10-group-padding');report.checks.push('Both real grouped Local panes use the grouped content insets [2, 12, 10, 12]');
 report.status='passed';
}catch(e){report.status='failed';report.error=String(e);await capture('failure').catch(()=>{});process.exitCode=1}
finally{if(app.exitCode===null&&app.signalCode===null){app.kill('SIGTERM');await Promise.race([ended,sleep(3000)]);if(app.exitCode===null&&app.signalCode===null){app.kill('SIGKILL');await ended}}await log.close();await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));console.log(JSON.stringify({status:report.status,error:report.error,out}))}
} finally {
 await rm(iso,{recursive:true,force:true});
}
