/** Native horizontal output and vertical containment on the production execution step row (execution-result-preview).
 *
 * Current contract:
 * - The execution result is a collapsed 24 step row (Kaf7E A6, 143c4c7b); its details body is a native ScrollArea bounded at
 *   150 (ai_execution_result_styles.body) that captures vertical input (ai_card_scroll.containVertical) and keeps its
 *   overflowing vertical thumb discoverable while idle (ai_card_scroll.showOverflowScrollbar: fade_speed 0).
 * - The terminal output is a native W.CodeBlock well (43eada2b): long lines scroll sideways inside the well
 *   (`ai.execution.result.terminal_output_scroll`, text `ai.execution.result.terminal_output`). Horizontal wheel and phased
 *   trackpad / momentum input move the output, not the body; vertical input over the well scrolls the surrounding body.
 *   The well's horizontal thumb is the native ScrollArea's own (shown on horizontal activity, inside the clipped body).
 * Usage: ZW_AI_TEST_PREFIX=<prefix> node e2e/ai_card_scroll_controls_native.ts <out> <theme>
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdtemp,mkdir,writeFile,readFile,open} from 'node:fs/promises';
import {join,resolve} from 'node:path';
const prefix=resolve(process.env.ZW_AI_TEST_PREFIX??'zig-out');
const h=await import(join(prefix,'share/zenit/harness/client.ts'));
const out=resolve(process.argv[2]??'dist/ui-acceptance/patch-card-scroll-controls');await mkdir(out,{recursive:true});
const theme=process.argv[3]??'dark';assert(['light','dark'].includes(theme),`theme must be light or dark, got ${theme}`);
const rpc=await mkdtemp('/tmp/zw-card-scroll-controls-');process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const binary=join(prefix,'bin/execution-result-preview'),log=await open(join(out,'app.log'),'w');
const app=spawn(binary,[`--theme=${theme}`,'--state=running','--long-output'],{env:{...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1'},stdio:['ignore',log.fd,log.fd]});
const ended=new Promise<any>(done=>app.once('exit',(code,signal)=>done({code,signal})));
const shown=(n:any)=>n&&n.hidden!==true&&n.visible!==false&&(n.effective_opacity??1)>0&&n.rect?.w>0&&n.rect?.h>0;
const visible=(id:string)=>h.waitFor(async()=>(await h.query(id)).find(shown)??null,10000);
const rect=async(id:string)=>(await visible(id)).rect;
const ROW=24,BODY_MAX=150;
/** A native ScrollArea's scrollbar parts are its direct children after the content (vendor/zenit/src/ui/components/scroll_area:
 *  content + two thumbs + two hover tracks); a thumb is the drawn bar: vertical = taller than wide, horizontal = wider than tall. */
const bars=(area:any)=>(area.children??[]).slice(1).filter((n:any)=>n.rect?.w>0&&n.rect?.h>0);
const vThumb=(area:any)=>bars(area).find((n:any)=>n.rect.h>n.rect.w);
const hThumb=(area:any)=>bars(area).find((n:any)=>n.rect.w>n.rect.h);
const settled=async(id:string,ms=3000)=>{let last='';return h.waitFor(async()=>{const r=JSON.stringify((await h.query(id))[0]?.rect);if(r===last)return (await h.query(id))[0].rect;last=r;await h.sleep(60);return null},ms)};
const report:any={status:'running',binary,theme,checks:[],limits:['Uses the existing production execution-row native fixture with immutable synthetic receipts.','Synthetic input exercises native dispatch and rendering; no physical touchpad hardware was driven.']};
try{
 await h.waitForServerReady(15000);assert.equal(Number(JSON.parse(await readFile(join(rpc,'owner.json'),'utf8')).pid),app.pid);await h.resizeWindow(360,420);
 // Collapsed step row; the whole row opens the details.
 const row=await visible('execution_result.preview.card');assert(Math.abs(row.rect.h-ROW)<0.1,`collapsed row ${row.rect.h}`);
 assert(!(await h.query('ai.execution.result.details')).some(shown),'details hidden while collapsed');
 const header=await rect('ai.execution.result.header');await h.clickAt(header.x+20,header.y+header.h/2);
 const body=await h.waitFor(async()=>{const b=(await h.query('ai.execution.result.details')).find(shown);return b&&Math.abs(b.rect.h-BODY_MAX)<0.1?b.rect:null},5000);
 report.checks.push('Collapsed 24 row opens to a details body bounded at 150');
 // Idle discoverability: the body's overflowing vertical thumb stays drawn after three idle seconds.
 await h.mouseMove(2,400);await h.sleep(3000);
 const idleBody=(await h.query('ai.execution.result.details'))[0],idleV=vThumb(idleBody);
 assert(idleV,'overflowing details body keeps its vertical thumb while idle');assert(idleV.rect.x>=body.x&&idleV.rect.x+idleV.rect.w<=body.x+body.w+.1&&idleV.rect.y>=body.y-.1&&idleV.rect.y+idleV.rect.h<=body.y+body.h+.1,'vertical thumb inside the body');
 report.idle_vertical_thumb={node_id:idleV.id,rect:idleV.rect};
 assert((await h.screenshot(join(out,'idle-vertical-thumb.png'))).ok);report.checks.push('Overflowing details body keeps its native vertical thumb after three idle seconds');
 // Output end: scroll the body to its end and check the well's horizontal thumb appears inside the clipped body on horizontal input.
 await h.scrollAt(body.x+40,body.y+body.h/2,0,-100000);await settled('ai.execution.result.terminal_output');
 let well=(await h.query('ai.execution.result.terminal_output_scroll'))[0];assert.equal(well.component,'ScrollArea');
 const endText=await rect('ai.execution.result.terminal_output');assert(endText.w>well.rect.w,'long output overflows the well sideways');
 const ey=Math.min(body.y+body.h-10,Math.max(body.y+10,endText.y+endText.h-20));
 // Idle discoverability of the well's horizontal overflow (user requirement c2bdb28c / V0.2.6: an overflowing inner
 // scroll area shows its scrollbar at rest; the AI cards use ScrollArea's public `scrollbars = .always`, usage-b5g):
 // the thumb is drawn before any horizontal input and is still drawn after three idle seconds.
 const restingH=hThumb(well);assert(restingH,'overflowing horizontal output shows its native thumb before any horizontal input');
 await h.mouseMove(2,400);await h.sleep(3000);well=(await h.query('ai.execution.result.terminal_output_scroll'))[0];
 assert(hThumb(well),'horizontal thumb still shown after three idle seconds');report.checks.push('Overflowing output well keeps its horizontal thumb at rest (before input and after 3 s idle)');
 await h.scrollAt(body.x+40,ey,-20,0);await settled('ai.execution.result.terminal_output');
 well=(await h.query('ai.execution.result.terminal_output_scroll'))[0];const activeH=hThumb(well);
 assert(activeH,'horizontal input shows the well\'s native horizontal thumb');
 assert(activeH.rect.y>=body.y&&activeH.rect.y+activeH.rect.h<=body.y+body.h+.1,'Horizontal thumb must be inside the clipped body viewport at the output end');
 assert(activeH.rect.x>=well.rect.x-.1&&activeH.rect.x+activeH.rect.w<=well.rect.x+well.rect.w+.1,'horizontal thumb inside the well');
 report.active_horizontal_thumb={node_id:activeH.id,rect:activeH.rect};
 assert((await h.screenshot(join(out,'output-end-horizontal-thumb.png'))).ok);report.checks.push('At the output end, horizontal input shows the well\'s native horizontal thumb inside the clipped body');
 await h.scrollAt(body.x+40,ey,20,0);
 // Back to the top, then 110 down so the output well is under the pointer.
 await h.scrollAt(body.x+40,body.y+body.h/2,0,100000);await settled('ai.execution.result.terminal_output');
 await h.scrollAt(body.x+40,body.y+body.h/2,0,-110);await settled('ai.execution.result.terminal_output');
 const text=await rect('ai.execution.result.terminal_output');assert(text.w>body.w);
 const x=body.x+40,y=Math.min(body.y+body.h-10,Math.max(body.y+10,text.y+10));assert(y>=text.y&&y<text.y+text.h,'pointer over the output');
 await h.scrollAt(x,y,-45,0);let now=await settled('ai.execution.result.terminal_output');assert(now.x<text.x-30,`horizontal wheel moved output ${text.x}→${now.x}`);assert.equal(now.y,text.y);report.checks.push('Horizontal wheel moves the long execution output without moving its vertical body');
 const initial=now;await h.scrollAt(x,y,0,0,{phase:'began'});await h.scrollAt(x,y,-30,0,{phase:'changed'});await h.scrollAt(x,y,-20,0,{phase:'changed'});await h.scrollAt(x,y,0,0,{phase:'ended'});await h.scrollAt(x,y,-20,0,{momentum:'began'});await h.scrollAt(x,y,-10,0,{momentum:'changed'});await h.scrollAt(x,y,0,0,{momentum:'ended'});
 now=await settled('ai.execution.result.terminal_output');assert(now.x<initial.x-40,`trackpad moved output ${initial.x}→${now.x}`);assert.equal(now.y,initial.y);report.checks.push('Horizontal phased trackpad and momentum pass through the vertical body capture');
 const beforeVertical=now;await h.scrollAt(x,y,0,-40);now=await settled('ai.execution.result.terminal_output');assert(now.y<beforeVertical.y-20,`vertical over output scrolled body ${beforeVertical.y}→${now.y}`);assert.equal(now.x,beforeVertical.x);report.checks.push('Vertical input over the horizontal output scrolls the surrounding bounded body');
 assert((await h.screenshot(join(out,'horizontal-and-vertical.png'))).ok);await writeFile(join(out,'tree.json'),JSON.stringify(await h.tree(),null,2));report.status='passed';
}catch(error){report.status='failed';report.error=String(error);process.exitCode=1;await h.screenshot(join(out,'failure.png')).catch(()=>{})}
finally{
 if(app.exitCode===null&&app.signalCode===null){try{await h.request('POST','/quit');await h.waitFor(async()=>app.exitCode!==null||app.signalCode!==null||null,10000)}catch(error){report.shutdown_error=String(error);app.kill('SIGTERM')}}
 report.shutdown=await ended;await log.close();await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));
}
console.log(JSON.stringify(report,null,2));
