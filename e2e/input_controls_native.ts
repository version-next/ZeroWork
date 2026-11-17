/** Native text-input paths in an isolated test-mode App: terminal IME preedit on the fixed grid, AI composer multi-line
 * IME preedit/commit, and the host editor's startup-commands Textarea (multi-line caret, CJK insertion, wrapping and
 * vertical scrolling). Synthetic Harness IME/keys; no real input method, no connection.
 * node e2e/input_controls_native.ts OUT [light|dark]   (binary: $ZW_INPUT_BINARY, default zig-out/bin/zerowork)
 *
 * Current contract (re-checked against source):
 * - Terminal preedit (terminal_surface.zig setPreedit): one text node in the surface viewport, shown only while a preedit
 *   exists, placed at the caret cell on the caret row with the grid row height; it carries no test_id, so it is found by
 *   its text inside `terminal.surface`.
 * - AI entry: `ai.launcher` opens the panel, `ai.collapse` collapses it back to the launcher (ai_entry.ts).
 * - Host editing is the right-click menu `context.menu.edit_host` (the row's hover edit button `sidebar.host.edit` and
 *   protocol label `sidebar.host.protocol` were removed in 7ec0492e); the editor is its own native window and the
 *   startup commands are the native Textarea `wizard.startup` at the end of 高级选项.
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdir,mkdtemp,open,readFile,writeFile,rm,realpath} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import * as h from '../zig-out/share/zenit/harness/client.ts';
import {aiToggleId} from './ai_entry.ts';
import {openSidebarHostMenu} from './sidebar_host_menu.ts';
const out=resolve(process.argv[2]||'/tmp/zw-input-controls'),theme=process.argv[3]||'dark';await mkdir(out,{recursive:true});
assert(['light','dark'].includes(theme),'theme must be light or dark');
const iso=await realpath(await mkdtemp(join(tmpdir(),'zw-input-host-'))),rpc=join(iso,'rpc'),data=join(iso,'data');await mkdir(rpc);await mkdir(data);
await writeFile(join(data,'config.toml'),`[meta]\nconfig_revision=1\n[ui]\ntheme="${theme}"\n`);
await writeFile(join(data,'hosts.toml'),'[registry]\nschema_version=2\nrevision=1\nnext_connection_id=2\nnext_group_id=1\n[[hosts]]\nconnection_id=1\nrevision=1\nprotocol="ssh"\nauth_mode="password"\nname="X40-AI01-long-host"\nhost="192.0.2.1"\nport=22\nuser="root"\nroute=[]\n');
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const log=await open(join(out,'app.log'),'w');
const app=spawn(resolve(process.env.ZW_INPUT_BINARY||'zig-out/bin/zerowork'),[],{env:{...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1'},stdio:['ignore',log.fd,log.fd]});
const ended=new Promise<number|null>(r=>app.once('close',code=>r(code)));
const report:any={status:'running',theme,checks:[]};
const shown=(n:any)=>n&&n.hidden!==true&&n.visible!==false&&(n.effective_opacity??1)>0&&n.rect?.w>0&&n.rect?.h>0;
const text=(n:any):string=>(n?.text??'')+(n?.children??[]).map(text).join('');
const get=async(id:string,ms=10000)=>h.waitFor(async()=>(await h.query(id)).find(shown)??null,ms);
const gone=async(id:string)=>h.waitFor(async()=>!(await h.query(id)).some(shown)||null,8000);
const click=async(id:string)=>{await get(id);assert((await h.clickTestId(id)).ok,id)};
const inside=(a:any,b:any)=>a.x>=b.x-.5&&a.y>=b.y-.5&&a.x+a.w<=b.x+b.w+.5&&a.y+a.h<=b.y+b.h+.5;
const cap=async(name:string)=>{await h.sleep(150);assert((await h.screenshot(join(out,name+'.png'))).ok);await writeFile(join(out,name+'.json'),JSON.stringify(await Promise.all(['sidebar.host','sidebar.host.hops','wizard.name','wizard.startup','ai.prompt'].map(async id=>({id,nodes:await h.query(id)}))),null,2));};
/** Shown text node inside `terminal.surface` whose own text is exactly `value` (the preedit node has no test id). */
async function surfaceText(value:string){const find=(n:any):any=>{if(shown(n)&&n.text===value)return n;for(const c of n.children??[]){const f=find(c);if(f)return f}return null};for(const s of await h.query('terminal.surface')){const f=find(s);if(f)return f}return null}
async function rows(){const all=[];for(let i=0;i<60;i++){const r=(await h.query(`terminal.surface.row.${i}`)).filter(shown);if(!r.length&&i>0)break;all.push(...r)}return all}
const bytes=(s:string)=>Buffer.byteLength(s);
const spliceBytes=(s:string,at:number,insert:string)=>{const b=Buffer.from(s);return Buffer.concat([b.subarray(0,at),Buffer.from(insert),b.subarray(at)]).toString()};
try {
  await h.waitForServerReady(60000);
  await h.resizeWindow(1440,900);
  await click('workspace.empty.local');
  const surface=await get('terminal.surface');
  // The shell prompt is on screen (PTY live): a non-empty row exists.
  const promptRow=await h.waitFor(async()=>(await rows()).filter((r:any)=>text(r).trim().length>0).at(-1)??null,15000);
  assert((await h.clickTestId('terminal.surface')).ok);
  const preeditText='Wi中😀';
  await h.imePreedit(preeditText,bytes('Wi中'));
  const pre=await h.waitFor(()=>surfaceText(preeditText),5000);
  // Fixed grid: the preedit sits on the caret (prompt) row with the row height, after the prompt text, inside the surface.
  assert(Math.abs(pre.rect.y-promptRow.rect.y)<.5&&Math.abs(pre.rect.h-promptRow.rect.h)<.5,`preedit occupies the caret row (preedit ${JSON.stringify(pre.rect)}, row ${JSON.stringify(promptRow.rect)})`);
  const promptText=(promptRow.children??[]).filter((n:any)=>shown(n)&&n.tag==='text');
  assert(promptText.length&&pre.rect.x>=Math.max(...promptText.map((n:any)=>n.rect.x+n.rect.w))-.5,'preedit starts after the prompt text');
  assert(inside(pre.rect,surface.rect),'preedit stays inside the terminal surface');
  report.terminal_preedit={preedit:pre.rect,row:promptRow.rect};
  await cap('terminal-preedit');
  await h.imePreedit('',0);
  await h.waitFor(async()=>!(await surfaceText(preeditText))||null,5000);
  report.checks.push('Terminal IME preedit is drawn on the caret row of the fixed grid after the prompt and disappears when cleared');

  await click(await aiToggleId());
  await get('ai.prompt');
  assert((await h.clickTestId('ai.prompt')).ok);
  const prompt='Wi中😀 first line\nsecond line\nthird line';
  await h.type_(prompt);
  await h.waitFor(async()=>(await h.inputState('ai.prompt')).buffer===prompt||null,5000);
  await h.key('left'); await h.key('left');
  const before=await h.inputState('ai.prompt');
  assert.equal(before.cursor_pos,bytes(prompt)-2,'two Left presses move the caret two characters back');
  await h.imePreedit('候选',bytes('候选'));
  await h.waitFor(async()=>(await h.inputState('ai.prompt')).ime_preedit_len===bytes('候选')||null,5000);
  await cap('ai-multiline-preedit');
  await h.imeCommit('候选');
  const after=await h.waitFor(async()=>{const s=await h.inputState('ai.prompt');return s.ime_preedit_len===0&&s.buffer!==prompt?s:null},5000);
  assert.equal(after.cursor_pos,before.cursor_pos+bytes('候选'));
  assert.equal(after.buffer,spliceBytes(prompt,before.cursor_pos,'候选'),'commit inserts exactly at the caret');
  await cap('ai-multiline-commit');
  report.checks.push('AI composer multi-line: IME preedit then commit inserts at the caret and advances it by the committed bytes');
  await click('ai.collapse');await get('ai.launcher');

  await openSidebarHostMenu();
  await click('context.menu.edit_host');
  await get('wizard.window');
  await click('wizard.advanced.toggle');
  await get('wizard.advanced.body');
  // Scroll the identity body until the startup Textarea is fully visible (the expanding card grows the scroll range).
  await h.waitFor(async()=>{
   const f=(await h.query('wizard.startup')).find(shown),v=(await h.query('wizard.scroll.identity')).find(shown);
   if(f&&v&&inside(f.rect,v.rect))return true;
   if(v)await h.scrollAt(v.rect.x+v.rect.w-20,v.rect.y+v.rect.h/2,0,-1800);return null;
  },8000);
  assert((await h.clickTestId('wizard.startup')).ok);
  const content='Wi中😀 first line\nsecond line\nthird line';
  await h.type_(content);
  await h.waitFor(async()=>(await h.inputState('wizard.startup')).buffer===content||null,5000);
  await h.key('left');await h.key('left');
  const startup=await h.inputState('wizard.startup');
  assert.equal(startup.cursor_pos,bytes(content)-2);
  await h.type_('中');
  const midInsert=await h.inputState('wizard.startup');
  assert.equal(midInsert.buffer,content.slice(0,-2)+'中'+content.slice(-2));
  assert.equal(midInsert.cursor_pos,bytes(content)-2+bytes('中'));
  assert.equal(midInsert.display_line_count,3,'three explicit lines, none wrapped');
  await cap('startup-multiline');
  await h.key('a',{cmd:true});
  const long='Wi中😀 wrapping content '.repeat(80);
  await h.type_(long);
  const wrapped=await h.waitFor(async()=>{const s=await h.inputState('wizard.startup');return s.buffer===long&&(s.scroll_y??0)>0?s:null},5000);
  assert((wrapped.display_line_count??0)>4,'one long line wraps into many display lines');
  // The Textarea keeps its height and scrolls (caret at the end stays in view): its box is unchanged.
  const field=await get('wizard.startup');
  report.startup_field=field.rect;
  await cap('startup-wrapped-scroll');
  // Document start is Cmd+↑ (macOS convention; zenit textarea.zig handleKeyDown: `.up` with super → moveToDocStart;
  // Home alone is line start, Ctrl+Home is document start).
  await h.key('up',{cmd:true});
  const start=await h.waitFor(async()=>{const s=await h.inputState('wizard.startup');return s.cursor_pos===0&&(s.scroll_y??0)===0?s:null},5000);
  const fieldAtStart=await get('wizard.startup');
  assert(Math.abs(fieldAtStart.rect.h-field.rect.h)<.5,'the Textarea height does not grow with its content');
  await cap('startup-wrapped-start');
  report.checks.push('Startup Textarea: multi-line caret, Chinese insertion, automatic wrapping with vertical scrolling, Cmd+Up back to the top');
  Object.assign(report,{before,after,startup,midInsert,wrapped,start});
  // Leave the editor through its own cancel (Escape = the window's close/cancel, wizard.zig windowKey); nothing is saved.
  await h.key('escape');await gone('wizard.window');
  assert(!(await readFile(join(data,'hosts.toml'),'utf8')).includes('wrapping content'),'cancelled edit is not saved');
  assert((await h.request('POST','/quit')).ok);report.exit=await Promise.race([ended,h.sleep(20000).then(()=>'timeout')]);assert.equal(report.exit,0,'isolated App quits cleanly');
  report.status='passed';
} catch (error) {
  report.status='failed';report.error=String(error);process.exitCode=1;
  await writeFile(join(out,'failure-tree.json'),JSON.stringify(await h.tree({visibleOnly:true}),null,2)).catch(()=>{});await h.screenshot(join(out,'failure.png')).catch(()=>{});
} finally {
  if(app.exitCode===null&&app.signalCode===null){app.kill('SIGTERM');await Promise.race([ended,h.sleep(3000)]);if(app.exitCode===null&&app.signalCode===null){app.kill('SIGKILL');await ended}}
  await log.close();await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));await rm(iso,{recursive:true,force:true});
}
console.log(JSON.stringify({status:report.status,error:report.error,out}));
