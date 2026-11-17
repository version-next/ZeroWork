/**
 * Fixture window frame (usage-b3-titlebar): every preview / fixture runner mounts its content in
 * `shared/ui/window/fixture_window.zig` — zenit window chrome with a `W.WindowHeader` title bar above the
 * fixture's content. Per runner and theme-independent (the frame has no theme of its own) this script checks,
 * in the real window:
 *   - the title bar `fixture.titlebar` spans the window width at the top, 40 high;
 *   - the title bar's own children (fixture controls placed there) start to the right of the traffic lights;
 *   - the fixture's content root starts at the title bar's bottom edge and fills the rest of the window, so
 *     nothing of the fixture sits under the traffic lights;
 *   - a screenshot of the window (`<runner>.png`).
 * The drag behaviour of the header itself (`windowRegionAt` = drag on empty space, client on its controls and
 * on the content) is covered by the unit test in `fixture_window.zig` and by zenit's own WindowHeader tests.
 *
 * Usage: node e2e/fixture_window_native.ts <prefix (bin/ holds the preview runners, test-mode)> <evidence dir> [runner…]
 * Without runner names all 15 are checked; that is what the batch regression runs (every one of them is an audited
 * build product in home_guard.PRODUCT_POLICY, see e2e/README.md).
 */
// @ts-ignore -- plain ESM helper
import {assertTestModeBinary} from './regression/build_mode_guard.mjs';
import assert from 'node:assert/strict';
import {existsSync} from 'node:fs';
import {mkdir,rm,writeFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import * as h from '../vendor/zenit/e2e/client.ts';
import {launchIsolated,shown} from './settings_nav.ts';

const [prefixArg,outArg,...only]=process.argv.slice(2);
if(!prefixArg||!outArg)throw new Error('usage: fixture_window_native.ts <prefix> <out> [runner…]');
const prefix=resolve(prefixArg),out=resolve(outArg);await mkdir(out,{recursive:true});
/** Runner → extra arguments (none needed for the default scene). */
const runners:Record<string,string[]>={
 'transfer-controls-preview':[],'connection-progress-preview':[],'auth-challenge-preview':[],'forward-config-preview':[],
 'ai-launcher-preview':[],'close-confirmation-preview':[],'ai-recovery-preview':[],'execution-result-preview':[],'task-finish-preview':[],
 'ai-empty-recent-preview':[],'inventory-grant-preview':[],'notification-preview':[],'button-policy-preview':[],
 'socks-info-preview':[],'composer-interaction-preview':[],
};
const TITLE=40,LIGHTS_RIGHT=7+2*20+14; // default inset: first light at x 7, 20 apart, 14 wide
const reports:any[]=[];
for(const name of only)assert(name in runners,`unknown runner ${name}`);
for(const [name,args] of Object.entries(runners).filter(([name])=>!only.length||only.includes(name))){
 const binary=join(prefix,'bin',name),report:any={runner:name,status:'running'};reports.push(report);
 if(!existsSync(binary)){report.status='missing';process.exitCode=1;continue;}
 assertTestModeBinary(binary);
 const run=await launchIsolated({binary,out,prefix:'zw-fixture-window',logName:`${name}.log`,args});
 try{
  await h.sleep(600);
  const root:any=await h.tree({visibleOnly:true} as any);
  const bar:any=await h.waitFor(async()=>(await h.query('fixture.titlebar')).find(shown)??null,10000);
  const width=root.rect.w,height=root.rect.h;
  report.window=[width,height];report.titlebar=bar.rect;
  assert.deepEqual([bar.rect.x,bar.rect.y,bar.rect.w,bar.rect.h],[0,0,width,TITLE],`${name}: title bar spans the window top, ${TITLE} high`);
  // frame → [title bar, body → slot → fixture content]
  const parentOf=(n:any):any=>{for(const c of n.children??[]){if(c.test_id==='fixture.titlebar')return n;const f=parentOf(c);if(f)return f;}return null;};
  const frame=parentOf(root);assert(frame,`${name}: fixture window frame`);
  const kids=(frame.children??[]).filter(shown);
  assert(kids.length===2&&kids[0].test_id==='fixture.titlebar',`${name}: the frame holds the title bar and the body`);
  assert.deepEqual([frame.rect.x,frame.rect.y,frame.rect.w,frame.rect.h],[0,0,width,height],`${name}: the frame fills the window`);
  const body=kids[1],slot=(body.children??[]).find(shown),content=(slot?.children??[]).find(shown);
  assert(slot&&content,`${name}: fixture content mounted`);
  report.slot=slot.rect;report.content=content.rect;
  assert.deepEqual([slot.rect.x,slot.rect.y,slot.rect.w,slot.rect.h],[0,TITLE,width,height-TITLE],`${name}: the content slot is the window below the title bar`);
  // The fixture root fills the slot; one taller than the window overflows inside it (clipped), as it would in a bare window.
  assert(content.rect.x===0&&content.rect.y===TITLE&&content.rect.w===width&&content.rect.h>=height-TITLE,`${name}: content starts at the title bar's bottom edge and fills the slot ${JSON.stringify(content.rect)}`);
  const controls=(bar.children??[]).filter(shown).flatMap((n:any)=>[n,...(n.children??[]).filter(shown)]).filter((n:any)=>n.rect.w>0&&n.rect.h>0);
  report.titlebar_controls=controls.length;
  for(const c of controls)assert(c.rect.x>=LIGHTS_RIGHT,`${name}: title-bar control at x ${c.rect.x} is right of the traffic lights (${LIGHTS_RIGHT})`);
  assert((await h.screenshot(join(out,`${name}.png`))).ok,`${name}: screenshot`);
  report.status='passed';
 }catch(e){report.status='failed';report.error=String((e as any)?.stack??e);process.exitCode=1;}
 finally{await run.stop();await rm(run.iso,{recursive:true,force:true});}
}
await writeFile(join(out,'report.json'),JSON.stringify({status:reports.every(r=>r.status==='passed')?'passed':'failed',runners:reports},null,2));
console.log(JSON.stringify(reports.map(r=>({runner:r.runner,status:r.status,window:r.window,controls:r.titlebar_controls,error:r.error?.slice(0,300)}))));
