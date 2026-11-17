/** Public Harness, isolated real Local sessions. Root owns execution/native slot.
 * node e2e/workspace_v3_semantics_native.ts --binary PATH --expected-sha SHA --out EMPTY_DIR
 * --prepare-only 1 writes a plan without starting an app.
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createHash } from "node:crypto";
import { createServer } from "node:net";
import { copyFile, mkdir, mkdtemp, realpath, open, readFile, readdir, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { waitForServerReady, waitFor, query, clickAt, key, type_, screenshot, sleep, resizeWindow, mouseMove, screenPos } from "../zig-out/share/zenit/harness/client.ts";
import {aiToggleId} from './ai_entry.ts';
const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const args: Record<string,string> = {};
for(let i=2;i<process.argv.length;i+=2) { assert(["--binary","--expected-sha","--out","--prepare-only","--extended"].includes(process.argv[i]) && process.argv[i+1]); args[process.argv[i]]=process.argv[i+1]; }
assert(args["--out"]);
const output=resolve(args["--out"]); await mkdir(output,{recursive:true}); assert.equal((await readdir(output)).length,0);
const report:any={status:"prepared_not_run",checks:[],screenshots:[],input:"Synthetic public Harness only",visual_status:"not_reviewed",limits:["Physical pointer, IME, window blur, VoiceOver require separate native acceptance","Runner cleanup SIGTERM is not normal application shutdown proof","Local mixed-group paths only; SSH reconnect/offline and AI impacts require their own fixtures"]};
const save=()=>writeFile(join(output,"report.json"),JSON.stringify(report,null,2));
if(args["--prepare-only"]==="1") { report.plan=["Create two real zsh services via native session menu","@grp each original session into same stable group","Verify two panes exactly once and preserve original standalone tabs","Switch existing members side/stack through member menu and verify 4pt geometry","Write different files from each focused real pane","Return standalone tab and group tab","Group close cancel causes zero session loss","Approve group then per-member Local impact confirmations and observe all tabs retire"]; await save(); process.exit(0); }
assert(args["--binary"] && /^[a-f0-9]{64}$/.test(args["--expected-sha"]??""));
const sourceBinary=resolve(args["--binary"]), binary=join(output,"zerowork-frozen"); await copyFile(sourceBinary,binary); await copyFile(join(dirname(sourceBinary),"zw_ipc.so"),join(output,"zw_ipc.so")); assert.equal(createHash("sha256").update(await readFile(binary)).digest("hex"),args["--expected-sha"]);
const isolated=await realpath(await mkdtemp(join(tmpdir(),"zw-workspace-v3-"))), rpc=join(isolated,"rpc"),data=join(isolated,"data"); await Promise.all([mkdir(rpc),mkdir(data)]);
await writeFile(join(data,"config.toml"),'[meta]\nconfig_revision = 1\n[ui]\ntheme = "dark"\nfont_family = "Menlo"\nfont_size = 14\n[ssh]\nconnect_timeout_sec = 1\n');
const peer=createServer();
await new Promise<void>((done,fail)=>{peer.once("error",fail);peer.listen(0,"127.0.0.1",done)});
const address=peer.address();assert(address&&typeof address==="object");
await new Promise<void>((done,fail)=>peer.close(error=>error?fail(error):done()));
await writeFile(join(data,"hosts.toml"),`[[hosts]]\nname = "Saved loopback refusal"\nhost = "127.0.0.1"\nport = ${address.port}\nuser = "test"\n`);
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const log=await open(join(output,"app.log"),"w");
const child=spawn(binary,[],{cwd:root,env:{...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:"0",ZENIT_E2E_BACKGROUND:"1",ZENIT_E2E_ISOLATE_POINTER:"1",OPENAI_API_KEY:"",ANTHROPIC_API_KEY:""},stdio:["ignore",log.fd,log.fd]});
const ended=new Promise<void>(done=>child.once("close",()=>done()));
Object.assign(report,{status:"running",pid:child.pid,binary,sha256:args["--expected-sha"],isolated});
const shown=(n:any)=>n?.rect && !n.hidden && n.visible!==false && n.rect.w>0 && n.rect.h>0 && (n.effective_opacity??1)>0;
const flat=(n:any):any[]=>shown(n)?[n,...(n.children??[]).flatMap(flat)]:[];
const visible=async(id:string)=>{report.waiting_for={id,state:"visible"};await save();return waitFor(async()=> {if(id==="groups.workspace"||/^groups\.pane\.\d+$/.test(id)){const rect=await screenPos(id);return rect.w>0&&rect.h>0?{test_id:id,rect}:null} const result=await query(id);return Array.isArray(result)?result.find(shown)??null:null},15000)};
const hidden=async(id:string)=>{report.waiting_for={id,state:"hidden"};await save();return waitFor(async()=> {if(id==="groups.workspace"){const rect=await screenPos(id);return !(rect.w>0&&rect.h>0)||null}const result=await query(id);return Array.isArray(result)?!result.some(shown)||null:null},15000)};
const clickNode=async(n:any)=>{assert(shown(n));assert((await clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok)};
const click=async(id:string)=>{report.last_action={kind:"click",test_id:id,at:new Date().toISOString()};await save();await clickNode(await visible(id))};
const press=async(name:string,mods?:any)=>{report.last_action={kind:"key",name:name==="enter"?"return":name,mods,at:new Date().toISOString()};await save();assert((await key(name==="enter"?"return":name,mods)).ok)};
const type=async(text:string)=>{report.last_action={kind:"type",text,at:new Date().toISOString()};await save();assert((await type_(text)).ok)};
const menuItem=async(label:string)=>{
 const menu=await visible("groups.member_menu");const n=flat(menu).find(n=>n.text===label);assert(n,`Missing member menu item ${label}`);await clickNode(n);
};
const tabs=async()=>{const strip=(await query("tabs.strip")).find(shown);return strip?flat(strip).filter(n=>/^tabs\.tab\.\d+$/.test(n.test_id??"")&&!flat(n).some(c=>c.test_id==="groups.close"||c.test_id==="groups.tab.count")):[]};
const panes=async()=>{const result:any[]=[];const candidateCount=Math.max(0,...(await tabs()).map(t=>Number(t.test_id.split(".").at(-1))));for(let id=1;id<=candidateCount;id++){const rect=await screenPos(`groups.pane.${id}`);if(rect.w>0&&rect.h>0)result.push({test_id:`groups.pane.${id}`,rect})}return result};
const paneTerminal=async(id:string)=>{const pane=await visible(`groups.pane.${id}`);assert(pane.rect.h>72);return {rect:{x:pane.rect.x+12,y:pane.rect.y+48,w:pane.rect.w-24,h:pane.rect.h-60}}};
const capture=async(name:string)=>{await sleep(180);assert((await screenshot(join(output,`${name}.png`))).ok);const observed:any={};for(const id of ["tabs.strip","groups.workspace","workspace.sidebar","sidebar.restore","terminal.surface","groups.close.confirm","groups.close.partial","local.close.confirmation"])observed[id]=await query(id);await writeFile(join(output,`${name}.queries.json`),JSON.stringify(observed,null,2));report.screenshots.push(name);await save()};
const check=(name:string,detail:any)=>report.checks.push({name,status:"passed",detail});
async function joinTrustedGroup(label:string):Promise<void>{
 // Shell startup is async and user rc files may take seconds. A real shell
 // command, sent through the public terminal surface, establishes startup
 // completion; it does not set application/session state.
 await click("terminal.surface");await capture(`before-${label}-shell-readiness`);
 const readyFile=join(isolated,`shell-ready-${label}.txt`);
 await type(`printf 'ready-${label}' > ${JSON.stringify(readyFile)}`);await press("return");
 await waitFor(async()=>{try{return await readFile(readyFile,"utf8")===`ready-${label}`||null}catch{return null}},30000);
 // Only the production @ popup proves the trusted ZLE lease is usable. If @
 // raced the next prompt snapshot, cancel that unsubmitted shell draft and
 // retry; never send an untrusted @grp line to the shell.
 let ready=false;
 for(let attempt=1;attempt<=3;attempt++){
   await capture(`before-${label}-trusted-at-${attempt}`);await type("@");
   try{await waitFor(async()=>(await query("terminal.commands")).some(shown)||null,4000);ready=true;break}
   catch(error){report.readiness_attempt={label,attempt,result:"trusted-popup-unavailable"};await save();await press("c",{ctrl:true});await sleep(300)}
 }
 assert(ready,`Real shell ${label} started, but production trusted @ editor never became available`);
 await capture(`${label}-trusted-editor-ready`);await type("grp Acceptance");
 // Public production palette flow: Right explicitly adopts the selected @grp
 // including its arguments into the local editor. The next user Return then
 // requests trusted End and executes only after its real acknowledgement.
 await press("right");await hidden("terminal.commands");await capture(`${label}-group-command-adopted`);await press("return");
}

try {
 await waitForServerReady();assert.equal(Number(JSON.parse(await readFile(join(rpc,"owner.json"),"utf8")).pid),child.pid);
 await resizeWindow(1440,900);await visible("workspace.sidebar");
 const hostBefore=await visible("sidebar.host");assert.equal(hostBefore.rect.h,28);
 await mouseMove(hostBefore.rect.x+70,hostBefore.rect.y+12);await visible("sidebar.host.info");
 const side=await visible("workspace.sidebar");
 await waitFor(async()=>{const hint=(await query("sidebar.host.info")).find(shown);return hint&&Math.abs(hint.rect.x-side.rect.x-side.rect.w-8)<=1?hint:null},5000);
 await capture("saved-host-info-right-edge");
 await mouseMove(600,400);await click("sidebar.host");await click("sidebar.host.connect_button");
 const refusal=()=>waitFor(async()=>{
   const alert=(await query("connection.progress.failure.alert")).find(shown);
   return alert&&flat(alert).some(n=>n.text?.includes("拒绝连接"))?alert:null;
 },15000);
 await refusal();
 await waitFor(async()=>flat((await query("connection.progress.failure.badge")).find(shown)).some(n=>n.text==="已停止重试")||null,15000);
 await visible("workspace.sidebar");await hidden("sidebar.restore");
 const firstFailed=(await tabs())[0].test_id;
 await click("sidebar.host");await click("sidebar.host.connect_button");
 await waitFor(async()=>(await tabs()).length===2||null,15000);
 const secondFailed=(await tabs()).find(n=>n.test_id!==firstFailed).test_id;
 const failedLog = async(id:string)=> waitFor(async()=>{
   const session=id.split(".").at(-1);
   return (await readFile(join(output,"app.log"),"utf8")).includes(`connect FAILED session=${session}: ConnectionRefused`)||null;
 },15000);
 await failedLog(firstFailed);await failedLog(secondFailed);
 await capture("same-host-distinct-sessions");
 for(const id of [secondFailed,firstFailed]){
   await click(id);
   await waitFor(async()=>(await query("pane.status")).some(n=>shown(n)&&n.text==="连接失败")||null,10000);
   await press("w",{cmd:true});await hidden(id);
 }
 await visible("workspace.sidebar");
 for(let i=0;i<3;i++){const n=(await query("notifications.dismiss.0")).find(shown);if(n){await clickNode(n);await sleep(150)}}
 check("saved host single activation creates independent sessions; info sits 8px outside connection library",{});
 await click("workspace.empty.local");await visible("terminal.surface");
 await visible("workspace.sidebar");await hidden("sidebar.restore");
 await press("b",{cmd:true});await hidden("workspace.sidebar");await visible("sidebar.restore");await capture("sidebar-manually-hidden");
 await click("sidebar.restore");await visible("workspace.sidebar");await hidden("sidebar.restore");
 await resizeWindow(860,480);await visible("workspace.sidebar");await capture("sidebar-manual-compact");
 await press("b",{cmd:true});await hidden("workspace.sidebar");await visible("sidebar.restore");await resizeWindow(1440,900);await hidden("workspace.sidebar");
 check("sidebar remains visible across failed and Local session activation, restores from the toolbar, and preserves the manual choice across resize",{});
 const firstTab=(await tabs())[0].test_id;
 await joinTrustedGroup("first");await visible("groups.workspace"); /* 88529dc0: a one-member group shows its pane (no "waiting" placeholder) */
 const firstPane=(await panes())[0].test_id; assert.equal((await panes()).length,1);await capture("01-single-member-real-pane");
 await click("toolbar.new_session");await click("session.menu.local");await visible("terminal.surface");
 const secondTab=(await tabs()).find(n=>n.test_id!==firstTab).test_id;
 await joinTrustedGroup("second");await waitFor(async()=>(await panes()).length===2||null,15000);
 const ids=(await panes()).map(n=>n.test_id);assert(ids.includes(firstPane));assert.equal(new Set(ids).size,2);assert.equal((await tabs()).length,2);check("two actual sessions plus one group tab",{sessionTabs:[firstTab,secondTab],panes:ids});
 const firstId=firstPane.split(".").at(-1)!, secondId=ids.find(id=>id!==firstPane)!.split(".").at(-1)!;
 for(const id of [firstId,secondId]){
   await click(`groups.broadcast.${id}`);await hidden("group.broadcast.card");
 }
 await click("status.group.broadcast");
 await waitFor(async()=>(await query("group.broadcast.summary")).some(n=>shown(n)&&n.text?.includes("已开启")&&n.text.includes("2 个参与会话"))||null,10000);
 await capture("member-broadcast-enabled");
 await press("escape");await hidden("group.broadcast.card");
 await clickNode(await paneTerminal(firstId));
 const fanoutPath=join(isolated,"broadcast-recipients.txt");await type(`printf '%s\\n' "$$" >> ${JSON.stringify(fanoutPath)}`);await press("return");
 await waitFor(async()=>{try{return (await readFile(fanoutPath,"utf8")).trim().split(/\s+/).length===2||null}catch{return null}},15000);
 const fanoutPids=(await readFile(fanoutPath,"utf8")).trim().split(/\s+/);assert.equal(new Set(fanoutPids).size,2);
 for(const id of [firstId,secondId]){
   await click(`groups.broadcast.${id}`);await hidden("group.broadcast.card");
 }
 await click("status.group.broadcast");
 await waitFor(async()=>(await query("group.broadcast.summary")).some(n=>shown(n)&&n.text?.includes("已关闭")&&n.text.includes("0 个参与会话"))||null,10000);
 await press("escape");await hidden("group.broadcast.card");
 await resizeWindow(860,480);await capture("member-broadcast-compact-off");await resizeWindow(1440,900);
 check("member header toggles real broadcast directly without approval panel; two PTYs receive command",{shellPids:fanoutPids});
 let pp=await panes();assert(Math.abs(pp[0].rect.y-pp[1].rect.y)<1);assert(Math.abs(pp[1].rect.x-pp[0].rect.x-pp[0].rect.w-4)<=1);await capture("02-side-by-side");
 const firstMenu=await visible(`groups.menu.${firstId}`), assistantLauncher=await visible("ai.launcher");
 assert(assistantLauncher.rect.y>=firstMenu.rect.y+firstMenu.rect.h,"AI launcher must clear member controls");
 await click(await aiToggleId());await visible("ai.panel");await click("ai.sessions");await sleep(100);await click("ai.sessions");await click("ai.collapse");await hidden("ai.panel");
 check("group AI launcher clears member controls and opens pinned panel without stealing member menu",{});
 await click(`groups.menu.${firstId}`);await menuItem("全部改为上下排列");
 pp=await waitFor(async()=>{const current=await panes();return current.length===2&&Math.abs(current[0].rect.x-current[1].rect.x)<1?current:null},5000);
 assert(Math.abs(pp[1].rect.y-pp[0].rect.y-pp[0].rect.h-4)<=1);await capture("03-stacked");
 for(const [sessionId,marker] of [[firstId,"first"],[secondId,"second"]]) {
   await clickNode(await paneTerminal(sessionId));
   const path=join(isolated,`${marker}.txt`);await type(`printf '${marker}' > ${JSON.stringify(path)}`);await press("enter");await waitFor(async()=>{try{return await readFile(path,"utf8")===marker||null}catch{return null}},10000);
 }
 check("each focused pane writes through its own real zsh service",{first:firstId,second:secondId});
 await click(firstTab);await hidden("groups.workspace");await click("groups.tab");await visible("groups.workspace");check("standalone and group remain independent presentation owners",{});
 let standaloneTabs=[firstTab,secondTab].sort();
 if(args["--extended"]==="1"){
  const extendedPanes=async()=>{const out:any[]=[];for(let id=1;id<32;id++){const rect=await screenPos(`groups.pane.${id}`);if(rect.w>0&&rect.h>0)out.push({test_id:`groups.pane.${id}`,rect});}return out;};const original=await tabs(),originalPanes=await extendedPanes();await click(`groups.menu.${firstId}`);await menuItem("向右分屏");await waitFor(async()=>(await extendedPanes()).length===3||null,20000);
  const addedPane=(await extendedPanes()).find(t=>!originalPanes.some(o=>o.test_id===t.test_id));assert(addedPane);const addedId=addedPane.test_id.split(".").at(-1)!;await capture("03b-new-real-split");check("native split adds one real group member",{original:original.map(t=>t.test_id),added_pane:addedPane.test_id});
  // An explicit split folds its source into the group tab and retains its pane.
  await hidden(firstTab);
  assert((await extendedPanes()).some(n=>n.test_id===firstPane));
  standaloneTabs=[secondTab];
  await click(`groups.menu.${addedId}`);await menuItem("移出组，保留会话");
  await waitFor(async()=>(await extendedPanes()).length===2||null,15000);
  const added=(await tabs()).find(t=>!original.some(o=>o.test_id===t.test_id));assert(added);
  await click(added.test_id);await visible("terminal.surface");
  const receipt=join(isolated,"detached-still-live.pid");
  await type(`printf '%s' "$$" > ${JSON.stringify(receipt)}`);await press("return");
  const pid=await waitFor(async()=>{try{const value=await readFile(receipt,"utf8");return /^\d+$/.test(value)?value:null}catch{return null}},20000);
  check("leaving group preserves executable original Local owner",{tab:added.test_id,pid});await capture("03c-detached-owner-still-live");
  await press("w",{cmd:true});
  await waitFor(async()=>{
    if((await query("local.close.confirmation")).some(shown)) await click("local.close.accept");
    return !(await query(added.test_id)).some(shown)||null;
  },15000);
  assert.deepEqual((await tabs()).map(n=>n.test_id).sort(),standaloneTabs);
  await click("groups.tab");await visible("groups.workspace");
 }
 const openGroupClose=async()=>{
   if(args["--extended"]==="1") await press("w",{cmd:true});
   else await click("groups.close");
   await visible("groups.close.confirm");
 };
 await openGroupClose();await capture("04-group-close-confirm");await click("groups.close.cancel");await hidden("groups.close.confirm");assert.deepEqual((await tabs()).map(n=>n.test_id).sort(),standaloneTabs);assert.equal((await panes()).length,2);check("group-close cancel preserves both sessions",{});
 await openGroupClose();await click("groups.close.accept");
 let memberConfirmations=0;
 await waitFor(async()=>{
   if((await query("local.close.confirmation")).some(shown)){await click("local.close.accept");memberConfirmations++;return null}
   return (await tabs()).length===0||null;
 },20000);
 report.member_impact_confirmations=memberConfirmations;
 // Idle shells may have no extra dangerous impact; the mandatory group
 // approval already occurred. Only actual coordinator confirmations are accepted.
 await waitFor(async()=>(await tabs()).length===0||null,15000);await hidden("groups.workspace");check("approved group closes each real member via V0.1.1 coordinator",{});await capture("05-all-local-members-released");
 report.status="passed";
} catch(error) { report.status="failed";report.error=error instanceof Error?error.stack:String(error);await capture("failed").catch(()=>{});process.exitCode=1 }
finally {await save();if(child.exitCode===null)child.kill("SIGTERM");await Promise.race([ended,sleep(3000)]);await log.close()}
