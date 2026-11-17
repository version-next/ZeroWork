/** Real welcome component (recent conversations), fabricated titles, isolated file RPC, no application data.
 *
 * Current contract (P7 empty state 355b4694, Pencil A2 `ZF1PS`; row = shared ai_session_row, Pencil O7 `cMKkE`):
 * - The welcome page is left-aligned and full width: the old 440 px centred column is gone, recent rows span the
 *   preview content (runner padding 14 each side: ai_empty_recent_preview_runner.zig).
 * - Row: column, padding 8, gap 4 (ai_sessions_styles.row); line 1 = title (12.5/500, ellipsis) in a 19 high box ·
 *   native W.Tag sm (phase); line 2 (24 high) = 已绑定/未绑定 · owner · native ghost xs icon Buttons. Row height
 *   `ai_sessions_styles.row_height` = 63 (8 + 19 + 4 + 24 + 8). Icon buttons are native zenit xs (square, same size, gap 6).
 * - A truncated title shows its full original text in a native Tooltip (open delay 500 ms, zenit tooltip/mod.zig);
 *   a complete title shows none (ai_session_row.TitleHint).
 * - 查看 (ai.session.jump.<id>) opens that conversation by pointer anywhere on the button and by Return.
 * Usage: node e2e/ai_empty_recent_component_native.ts <ai-empty-recent-preview> <out> <theme>
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdir,mkdtemp,open,readFile,writeFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import * as h from '../zig-out/share/zenit/harness/client.ts';
const binary=resolve(process.argv[2]??'zig-out/bin/ai-empty-recent-preview');
const out=resolve(process.argv[3]??'/private/tmp/zerowork-ai-recent-evidence/native');
const startTheme=process.argv[4]??'dark';
assert(['light','dark'].includes(startTheme),`theme must be light or dark, got ${startTheme}`);
await mkdir(out,{recursive:true});
const report:any={status:'running',binary,theme:startTheme,measurements:[],checks:[],shutdown:[]};
const shown=(n:any)=>n&&n.visible!==false&&n.hidden!==true&&(n.effective_opacity??1)>0.99&&n.rect?.w>0&&n.rect?.h>0;
const visible=(id:string)=>h.waitFor(async()=>(await h.query(id)).find(shown)??null,10000);
const near=(a:number,b:number,what='',eps=0.15)=>assert(Math.abs(a-b)<=eps,`${what} ${a} != ${b}`);
const text=(n:any):string=>n.text??(n.children??[]).map(text).join('');
const save=()=>writeFile(join(out,'report.json'),JSON.stringify(report,null,2));
const within=(n:any,r:any)=>n.rect.y>=r.rect.y-0.5&&n.rect.y+n.rect.h<=r.rect.y+r.rect.h+0.5;
const inRow=async(id:string,row:any)=>(await h.query(id)).filter((n:any)=>shown(n)&&within(n,row));
const result=async()=>text(await visible('ai.empty.preview.result'));
const resultIs=(value:string)=>h.waitFor(async()=>(await result())===value||null,3000).catch(async()=>assert.fail(`result ${JSON.stringify(await result())} != ${value}`));
const tipShown=async()=>(await h.query('ai.session.title.tooltip')).some(shown);
const ROW_H=63,PAD=8,LINE1=19,LINE2=24,CONTENT_PAD=14,ACTION_GAP=6,TOOLTIP_DELAY=500,TOOLTIP_MAX_LINES=3,TOOLTIP_LINE_HEIGHT=1.4;
/** The theme the preview's Replay button selects next: theme_presets.ids order (src/config/theme_presets.zig). */
const nextTheme:Record<string,string>={dark:'light',light:'sauber'};
try{
 for(const fixture of ['mixed','wide','unbroken']){
  const iso=await mkdtemp('/private/tmp/zw-recent-'),rpc=join(iso,'rpc');await mkdir(rpc);process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
  const log=await open(join(out,`${fixture}.log`),'w');
  const child=spawn(binary,[`--fixture=${fixture}`,`--theme=${startTheme}`],{env:{...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1'},stdio:['ignore',log.fd,log.fd]});
  const ended=new Promise<any>(done=>child.once('exit',(code,signal)=>done({code,signal})));
  try{
   await h.waitForServerReady(10000);assert.equal(Number(JSON.parse(await readFile(join(rpc,'owner.json'),'utf8')).pid),child.pid);
   // The variant's palette, then the live republish (Replay) into the next palette: geometry must not depend on it.
   for(const theme of [startTheme,nextTheme[startTheme]]){
    for(const width of [600,360,480]){
     await h.resizeWindow(width,460);await h.mouseMove(1,1);
     await h.waitFor(async()=>{const c=(await h.query('ai.empty.preview.content')).find(shown);return c&&Math.abs(c.rect.w-width)<0.5||null},5000);
     await h.waitFor(async()=>!(await tipShown())||null,3000);
     const content=await visible('ai.empty.preview.content'),group=await visible('ai.empty.recent'),row=await visible('ai.session.row.17'),shortRow=await visible('ai.session.row.29');
     const [title]=await inRow('ai.session.title',row),[tag]=await inRow('ai.session.phase_tag',row),[first]=await inRow('ai.session.first_line',row),[second]=await inRow('ai.session.second_line',row);
     assert(title&&tag&&first&&second,'row 17 parts');
     // Full-width rows inside the content padding, group and rows equally wide.
     near(row.rect.w,content.rect.w-2*CONTENT_PAD,'row spans the content');near(row.rect.w,group.rect.w,'row = recent group');near(shortRow.rect.w,row.rect.w,'rows equally wide');
     near(row.rect.x,content.rect.x+CONTENT_PAD,'row left edge');
     near(row.rect.h,ROW_H,'row height (ai_sessions_styles.row_height)');near(shortRow.rect.h,ROW_H,'short row height');
     near(first.rect.h,LINE1,'line 1');near(second.rect.h,LINE2,'line 2');near(title.rect.h,LINE1,'title box (titleBox 19)');
     near(first.rect.x,row.rect.x+PAD,'row padding left');near(first.rect.x+first.rect.w,row.rect.x+row.rect.w-PAD,'row padding right');near(first.rect.y,row.rect.y+PAD,'row padding top');
     // Long title ellipsized before the phase tag; tag on the row's inner right edge.
     assert(title.rect.x+title.rect.w<=tag.rect.x+0.1,'title ends before the tag');near(tag.rect.x+tag.rect.w,row.rect.x+row.rect.w-PAD,'tag at the inner right edge');
     assert(tag.rect.y>=first.rect.y-2&&tag.rect.y+tag.rect.h<=first.rect.y+first.rect.h+2,'tag centred on line 1');
     assert(Buffer.byteLength(text(title))>120,'the fixture title is long');
     // Native xs icon buttons on line 2: square, identical size, 6 apart, right-aligned, inside the line.
     const actionIds=['ai.session.jump.17','ai.session.locate.17','ai.session.copy_use.17'];
     const actions=[];for(const id of actionIds)actions.push((await h.query(id)).find(shown));
     assert(actions.every(Boolean),'row 17 actions visible (查看 · 定位 · 复制并使用; 删除 hidden: can_remove false)');
     assert(!(await h.query('ai.session.delete.17')).some(shown),'row 17 has no delete');
     for(const a of actions){near(a.rect.w,a.rect.h,'square icon button',0.01);near(a.rect.w,actions[0].rect.w,'same native size',0.01);assert(a.rect.y>=second.rect.y-0.5&&a.rect.y+a.rect.h<=second.rect.y+second.rect.h+0.5,'button inside line 2')}
     for(let i=1;i<actions.length;i++)near(actions[i].rect.x-(actions[i-1].rect.x+actions[i-1].rect.w),ACTION_GAP,'action gap (rowActions gap 6)');
     near(actions.at(-1).rect.x+actions.at(-1).rect.w,second.rect.x+second.rect.w,'actions right-aligned');
     const action=actions[0];
     report.measurements.push({fixture,theme,width,row:row.rect,title:title.rect,tag:tag.rect,action:action.rect});
     if(width!==480){assert((await h.screenshot(join(out,`${fixture}-${theme}-${width}.png`))).ok);if(theme===startTheme)await writeFile(join(out,`${fixture}-${width}-tree.json`),JSON.stringify(await h.query('ai.empty.configured'),null,2));}
     // A complete short title: no duplicate tooltip, even after twice the native open delay.
     const [shortTitle]=await inRow('ai.session.title',shortRow);
     await h.mouseMove(shortTitle.rect.x+20,shortTitle.rect.y+8);await h.sleep(2*TOOLTIP_DELAY);assert(!(await tipShown()),'complete short title must not show a duplicate tooltip');
     if(width===360)assert((await h.screenshot(join(out,`${fixture}-${theme}-short-no-tooltip-360.png`))).ok);
     // The truncated title: the native tooltip carries the full original text and stays inside the window.
     await h.mouseMove(title.rect.x+20,title.rect.y+8);
     const tip=await h.waitFor(async()=>(await h.query('ai.session.title.tooltip')).find(shown)??null,4000);
     assert.equal(text(tip),text(title));assert(tip.rect.x>=0&&tip.rect.x+tip.rect.w<=width+0.2,'tooltip inside the window');assert(tip.rect.h>20);
     if(width===360)assert((await h.screenshot(join(out,`${fixture}-${theme}-tooltip-360.png`))).ok);
     // Each fixture title needs more than three lines at 320 px. The expansion hint must lay out
     // the extra lines to reveal the title beyond the default tooltip limit.
     const tipText=(tip.children??[]).find((n:any)=>n.text);assert(tipText,'tooltip label');
     const shownLines=Math.round(tipText.rect.h/(tipText.font_size*TOOLTIP_LINE_HEIGHT));
     report.measurements.at(-1).tooltip={rect:tip.rect,label:tipText.rect,lines:shownLines};
     assert(shownLines>TOOLTIP_MAX_LINES,`title expansion tooltip shows only ${shownLines} lines (${JSON.stringify(tipText.rect)})`);
     // 查看 opens conversation 17 by pointer anywhere on the button (the pointer travels there first, which closes the
     // title tooltip as in real use) and by Return; 29's 查看 in between proves each press is fresh.
     for(const x of [action.rect.x+2,action.rect.x+action.rect.w/2,action.rect.x+action.rect.w-2]){
      const jump29=(await h.query('ai.session.jump.29')).find(shown);
      await h.mouseMove(jump29.rect.x+jump29.rect.w/2,jump29.rect.y+jump29.rect.h/2);await h.waitFor(async()=>!(await tipShown())||null,3000);
      await h.clickAt(jump29.rect.x+jump29.rect.w/2,jump29.rect.y+jump29.rect.h/2);await resultIs('selected 29');
      await h.mouseMove(x,action.rect.y+action.rect.h/2);await h.clickAt(x,action.rect.y+action.rect.h/2);await resultIs('selected 17');
     }
     assert.equal((await h.focused()).test_id,'ai.session.jump.17','the pressed icon button holds focus');
     const jump29=(await h.query('ai.session.jump.29')).find(shown);await h.mouseMove(jump29.rect.x+jump29.rect.w/2,jump29.rect.y+jump29.rect.h/2);await h.clickAt(jump29.rect.x+jump29.rect.w/2,jump29.rect.y+jump29.rect.h/2);await resultIs('selected 29');
     // Keyboard: walk focus back from 29's 查看 to 17's (bounded), then Return.
     for(let i=0;i<12&&(await h.focused()).test_id!=='ai.session.jump.17';i++)await h.key('tab',{shift:true});
     assert.equal((await h.focused()).test_id,'ai.session.jump.17','Shift+Tab reaches 17 查看');
     await h.key('return');await resultIs('selected 17');
     await h.mouseMove(1,1);
    }
    if(theme===startTheme){assert((await h.clickTestId('ai.empty.preview.replay')).ok);}
   }
   report.checks.push(`${fixture}: ${startTheme} → ${nextTheme[startTheme]} (live replay) at 600/360/480: full-width native rows 63 high, ellipsized title before the W.Tag, square xs icon buttons 6 apart right-aligned; short title has no tooltip; truncated title tooltip = full original text inside the window; 查看 opens 17 by pointer at both edges and centre and by Return`);
  }finally{
   let method='POST /quit';try{await h.request('POST','/quit');await h.waitFor(async()=>child.exitCode!==null||child.signalCode!==null||null,10000)}catch{method='SIGTERM fallback';child.kill('SIGTERM')}
   const status=await ended;report.shutdown.push({fixture,method,...status});await log.close();await save();assert.equal(method,'POST /quit');assert.equal(status.code,0);assert.equal(status.signal,null);
  }
 }
 report.status='passed';await save();console.log(`PASS ${report.measurements.length} recent title native layouts: ${out}`);
}catch(error){report.status='failed';report.error=String(error);await save();throw error}
