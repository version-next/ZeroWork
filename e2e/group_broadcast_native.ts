/** Public Harness, isolated real Local sessions. Root owns execution/native slot.
 * node e2e/group_workspace_native.ts --binary PATH --expected-sha SHA --out EMPTY_DIR
 * --prepare-only 1 writes a plan without starting an app.
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createHash } from "node:crypto";
import { copyFile, mkdir, mkdtemp, realpath, open, readFile, readdir, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { waitForServerReady, waitFor, query, clickAt, key, type_, screenshot, sleep, resizeWindow, screenPos, scrollAt } from "../zig-out/share/zenit/harness/client.ts";
const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const args: Record<string,string> = {};
for(let i=2;i<process.argv.length;i+=2) { assert(["--binary","--expected-sha","--out","--prepare-only","--theme"].includes(process.argv[i]) && process.argv[i+1]); args[process.argv[i]]=process.argv[i+1]; }
assert(args["--out"]);
const output=resolve(args["--out"]); await mkdir(output,{recursive:true}); assert.equal((await readdir(output)).length,0);
const report:any={theme:args["--theme"]??"dark",status:"prepared_not_run",checks:[],screenshots:[],input:"Synthetic public Harness only",visual_status:"not_reviewed",limits:["Physical pointer, IME, window blur, VoiceOver require separate native acceptance","Runner cleanup SIGTERM is not normal application shutdown proof","Local mixed-group paths only; SSH reconnect/offline and AI impacts require their own fixtures"]};
const save=()=>writeFile(join(output,"report.json"),JSON.stringify(report,null,2));
if(args["--prepare-only"]==="1") { report.plan=["Create real source and receiver Local PTYs, record distinct shell PIDs, join same group", "Trusted @sync on enables only the current session without a confirmation card; repeating it is idempotent (status card count and member states unchanged, no duplicate input)", "Enable the receiver from its member checkbox: each enabled shell gets the source input exactly once", "Join a third real Local PTY and prove it is not enabled until selected", "@sync off disables only the current session: no card, no terminal closes, other members keep fanning out"]; await save(); process.exit(0); }
assert(args["--binary"] && /^[a-f0-9]{64}$/.test(args["--expected-sha"]??""));
const sourceBinary=resolve(args["--binary"]), binary=join(output,"zerowork-frozen"); await copyFile(sourceBinary,binary); await copyFile(join(dirname(sourceBinary),"zw_ipc.so"),join(output,"zw_ipc.so")); assert.equal(createHash("sha256").update(await readFile(binary)).digest("hex"),args["--expected-sha"]);
assert(["dark","light"].includes(args["--theme"]??"dark"));
const isolated=await realpath(await mkdtemp(join(process.env.ZW_BROADCAST_DEFAULT_SHELL?tmpdir():"/private/tmp","zw-group-broadcast-"))), rpc=join(isolated,"rpc"),data=join(isolated,"data"); await Promise.all([mkdir(rpc),mkdir(data)]);
await writeFile(join(data,"config.toml"),`[meta]\nconfig_revision = 1\n[ui]\ntheme = "${args["--theme"]??"dark"}"\nfont_family = "Menlo"\nfont_size = 14\n`);
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const shellConfig=join(isolated,"shell-config");await mkdir(shellConfig);await writeFile(join(shellConfig,".zshrc"),"bindkey -e\nPS1='ZeroWork-broadcast%# '\n");
const log=await open(join(output,"app.log"),"w");
const child=spawn(binary,[],{cwd:root,env:{...process.env,...(process.env.ZW_BROADCAST_DEFAULT_SHELL?{}:{ZDOTDIR:shellConfig}),ZENIT_E2E_FILE_RPC_DIR:rpc,ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:"0",ZENIT_E2E_BACKGROUND:"1",ZENIT_E2E_ISOLATE_POINTER:"1",OPENAI_API_KEY:"",ANTHROPIC_API_KEY:""},stdio:["ignore",log.fd,log.fd]});
const ended=new Promise<void>(done=>child.once("close",()=>done()));
Object.assign(report,{status:"running",pid:child.pid,binary,sha256:args["--expected-sha"],isolated});
const shown=(n:any)=>n?.rect && !n.hidden && n.visible!==false && n.rect.w>0 && n.rect.h>0 && (n.effective_opacity??1)>0;
const flat=(n:any):any[]=>shown(n)?[n,...(n.children??[]).flatMap(flat)]:[];
const visible=async(id:string)=>waitFor(async()=> (await query(id)).find(shown)??null,15000);
const hidden=async(id:string)=>waitFor(async()=> !(await query(id)).some(shown)||null,15000);
const clickNode=async(n:any)=>{assert(shown(n));assert((await clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok)};
const click=async(id:string)=>{report.last_action={kind:"click",test_id:id,at:new Date().toISOString()};await save();await clickNode(await visible(id))};
const press=async(name:string,mods?:any)=>{report.last_action={kind:"key",name:name==="enter"?"return":name,mods,at:new Date().toISOString()};await save();assert((await key(name==="enter"?"return":name,mods)).ok)};
const type=async(text:string)=>{report.last_action={kind:"type",text,at:new Date().toISOString()};await save();assert((await type_(text)).ok)};
const menuItem=async(label:string)=>{
 const menu=await visible("groups.member_menu");const n=flat(menu).find(n=>n.text===label);assert(n,`Missing member menu item ${label}`);await clickNode(n);
};
const tabs=async()=>{const strip=(await query("tabs.strip")).find(shown);return strip?flat(strip).filter(n=>/^tabs\.tab\.\d+$/.test(n.test_id??"")):[]};
const panes=async()=>{
 const result:any[]=[];
 for(const tab of await tabs()) { const id=tab.test_id.split(".").at(-1); const rect=await screenPos(`groups.pane.${id}`);if(rect.w>0&&rect.h>0)result.push({test_id:`groups.pane.${id}`,rect}); }
 return result;
};
const capture=async(name:string)=>{await sleep(180);assert((await screenshot(join(output,`${name}.png`))).ok);const observed:any={};for(const id of ["tabs.strip","groups.workspace","groups.close.confirm","groups.close.partial","local.close.confirmation","group.broadcast.card","group.broadcast.footer","status.group.broadcast","toolbar.expand"])observed[id]=await query(id);await writeFile(join(output,`${name}.queries.json`),JSON.stringify(observed,null,2));report.screenshots.push(name);await save()};
const check=(name:string,detail:any)=>report.checks.push({name,status:"passed",detail});
async function joinTrustedGroup(label:string):Promise<void>{
 // Shell startup is async and user rc files may take seconds. A real shell
 // command, sent through the public terminal surface, establishes startup
 // completion; it does not set application/session state.
 await sleep(1600);await capture(`before-${label}-shell-readiness`);
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

async function trustedCommand(command:string):Promise<void>{
 let opened=false;
 for(let attempt=0;attempt<3;attempt++){
   await type("@");try{await waitFor(async()=>(await query("terminal.commands")).some(shown)||null,4000);opened=true;break}
   catch{await press("c",{ctrl:true});await sleep(300)}
 }
 assert(opened,"trusted command palette must be available");
 await type(command);await press("right");await hidden("terminal.commands");await press("return");
}
async function focusPane(id:string):Promise<void>{
 const rect=await screenPos(`groups.pane.${id}`);assert(rect.w>0&&rect.h>0);assert((await clickAt(rect.x+rect.w/2,rect.y+Math.max(70,rect.h/2))).ok);
}
const fileValue=async(path:string)=>{try{return await readFile(path,"utf8")}catch{return ""}};
async function recordPid(id:string,label:string):Promise<string>{
 await focusPane(id);const path=join(isolated,`pid-${label}.txt`);await type(`printf '%s' "$$" > ${JSON.stringify(path)}`);await press("return");
 return await waitFor(async()=>{const value=await fileValue(path);return /^\d+$/.test(value)?value:null},10000);
}
async function sendMarker(source:string,label:string,expected:string[]):Promise<void>{
 const path=join(isolated,`broadcast-${label}.txt`);await focusPane(source);await type(`printf '%s\\n' "$$" >> ${JSON.stringify(path)}`);await sleep(180);await press("return");
 await waitFor(async()=>{const lines=(await fileValue(path)).trim().split("\n").filter(Boolean);return lines.length>=expected.length?lines:null},10000);
 await sleep(350);const lines=(await fileValue(path)).trim().split("\n").filter(Boolean);
 assert.deepEqual(lines.sort(),[...expected].sort(),`${label}: exactly once per approved real shell; no source double-send or unapproved target`);
 report.checks.push({name:label,status:"passed",pids:lines});await save();
}
try {
 await waitForServerReady();assert.equal(Number(JSON.parse(await readFile(join(rpc,"owner.json"),"utf8")).pid),child.pid);await resizeWindow(1440,900);
 await click("workspace.empty.local");await visible("terminal.surface");await joinTrustedGroup("source");await visible("groups.workspace"); /* 88529dc0: one-member group shows its pane */
 const source=(await panes())[0].test_id.split(".").at(-1)!;
 await click("toolbar.new_session");await click("session.menu.local");await joinTrustedGroup("receiver");
 await waitFor(async()=>(await panes()).length===2||null,15000);
 const receiver=(await panes()).find(n=>n.test_id!==`groups.pane.${source}`)!.test_id.split(".").at(-1)!;
 const sourcePid=await recordPid(source,"source"),receiverPid=await recordPid(receiver,"receiver");assert.notEqual(sourcePid,receiverPid);
 // V0.1.6 §2.4 (04750679): `@sync on` idempotently enables only the current session, with no
 // confirmation card; `off` disables only that session; other members keep their state.
 const texts=(n:any)=>flat(n).map(x=>x.text).filter(Boolean) as string[];
 const openStatus=async(name:string,expect:{count:number,running:boolean,states:Record<string,string>})=>{
  await click("status.group.broadcast");const card=await visible("group.broadcast.card");
  const want=`${expect.running?"已开启":"已关闭"} · ${expect.count} 个参与会话`;
  await waitFor(async()=>texts(await visible("group.broadcast.summary")).some(t=>t.includes(want))||null,8000).catch(async()=>{throw new Error(`${name}: summary ${JSON.stringify(texts(await visible("group.broadcast.summary")))} lacks ${want}`)});
  for(const [member,state] of Object.entries(expect.states)){
   const row=texts(await visible(`group.broadcast.member.${member}`));
   assert(row.includes(state),`${name}: member ${member} state ${JSON.stringify(row)} lacks ${state}`);
  }
  await capture(name);check(name,{summary:texts(await visible("group.broadcast.summary")),card:card.rect});
 };
 const closeStatus=async()=>{await press("escape");await hidden("group.broadcast.card")};
 const noCard=async(label:string)=>{await sleep(500);assert(!(await query("group.broadcast.card")).some(shown),`${label}: @sync opens no confirmation card`)};
 await focusPane(source);await trustedCommand("sync on");await noCard("sync-on");
 // A single enabled member is allowed; it has no other target.
 await sendMarker(source,"sync-on-source-alone-no-targets",[sourcePid]);
 await openStatus("01-sync-on-status",{count:1,running:true,states:{[source]:"当前 · 参与",[receiver]:"未参与"}});await closeStatus();
 await focusPane(source);await trustedCommand("sync on");await noCard("sync-on-again");
 await openStatus("02-sync-on-idempotent",{count:1,running:true,states:{[source]:"当前 · 参与",[receiver]:"未参与"}});await closeStatus();
 await sendMarker(source,"idempotent-on-no-duplicate",[sourcePid]);
 // The receiver joins from its own member checkbox; the next source input reaches each enabled shell once.
 await click("status.group.broadcast");await visible("group.broadcast.card");await click(`group.broadcast.member.${receiver}.select`);
 await waitFor(async()=>texts(await visible("group.broadcast.summary")).some(t=>t.includes("2 个参与会话"))||null,8000);await closeStatus();
 await sendMarker(source,"source-and-receiver-once",[sourcePid,receiverPid]);
 await focusPane(source);await trustedCommand("sync on");await noCard("sync-on-both");
 await sendMarker(source,"repeated-on-delivers-once",[sourcePid,receiverPid]);
 await openStatus("03-both-enabled",{count:2,running:true,states:{[source]:"当前 · 参与",[receiver]:"参与"}});
 await resizeWindow(860,480);await sleep(350);
 // The broadcast entry is a title-bar tool; in a narrow window it moves into the "⋯" menu.
 const broadcastAnchor=async()=>(await query("status.group.broadcast")).find(shown)??await visible("toolbar.expand");
 const openBroadcast=async()=>{if((await query("status.group.broadcast")).some(shown))await click("status.group.broadcast");else{await click("toolbar.expand");await click("toolbar.more.broadcast");}await visible("group.broadcast.card")};
 const card=await visible("group.broadcast.card"),anchor=await broadcastAnchor();assert(card.rect.x>=0&&card.rect.y>=0&&card.rect.x+card.rect.w<=860&&card.rect.y+card.rect.h<=480);
 assert(card.rect.y+card.rect.h<=anchor.rect.y+0.5||card.rect.y>=anchor.rect.y+anchor.rect.h-0.5,`card ${JSON.stringify(card.rect)} must not cover its anchor ${JSON.stringify(anchor.rect)}`);await capture("03b-compact-anchored");
 if((await query("sidebar.collapse")).some(shown)){await click("sidebar.collapse");await hidden("group.broadcast.card");await openBroadcast();}await sleep(200);const folded=await visible("group.broadcast.card");assert(folded.rect.x>=0&&folded.rect.y>=0&&folded.rect.x+folded.rect.w<=860&&folded.rect.y+folded.rect.h<=480);await capture("03c-compact-sidebar-folded");
 await closeStatus();await resizeWindow(1440,900); // 侧栏不再随窗口宽度自动收成窄条（191f6aa6），不需要再展开

 // A new member never inherits an earlier enablement.
 await click("toolbar.new_session");await click("session.menu.local");await joinTrustedGroup("unapproved-third");
 await waitFor(async()=>(await panes()).length===3||null,15000);
 const third=(await panes()).find(n=>![`groups.pane.${source}`,`groups.pane.${receiver}`].includes(n.test_id))!.test_id.split(".").at(-1)!;
 const thirdPid=await recordPid(third,"third");assert(![sourcePid,receiverPid].includes(thirdPid));
 await sendMarker(source,"new-member-excluded",[sourcePid,receiverPid]);await capture("04-third-excluded");
 await click("status.group.broadcast");await visible("group.broadcast.card");await sleep(300);
 const viewport=await visible("group.broadcast.viewport"), footerBefore=(await visible("group.broadcast.footer")).rect;
 const thirdBefore=(await visible(`group.broadcast.member.${third}.select`)).rect;
 assert((await scrollAt(viewport.rect.x+viewport.rect.w/2,viewport.rect.y+viewport.rect.h/2,0,-200)).ok);await sleep(200);
 const footerAfter=(await visible("group.broadcast.footer")).rect, thirdAfter=(await visible(`group.broadcast.member.${third}.select`)).rect;
 for(const k of ["x","y","w","h"] as const)assert(Math.abs(footerAfter[k]-footerBefore[k])<=0.5,`broadcast actions must stay fixed while body scrolls (${k} ${footerBefore[k]} → ${footerAfter[k]})`);assert(thirdAfter.y<thirdBefore.y,"overflow body must actually scroll");
 await capture("05-members-scrolled");check("overflow-scroll-keeps-footer-fixed",{footer:footerAfter,member_before:thirdBefore,member_after:thirdAfter});
 await click(`group.broadcast.member.${third}.select`);await waitFor(async()=>texts(await visible("group.broadcast.summary")).some(t=>t.includes("3 个参与会话"))||null,8000);await closeStatus();
 await sendMarker(source,"third-selected-once",[sourcePid,receiverPid,thirdPid]);
 // `@sync off` disables only the current session: no card, no terminal closes, the others stay enabled.
 await focusPane(source);await trustedCommand("sync off");await noCard("sync-off");
 await openStatus("06-sync-off-current-only",{count:2,running:true,states:{[source]:"当前 · 未参与",[receiver]:"参与",[third]:"参与"}});await closeStatus();
 assert.equal((await panes()).length,3,"@sync off closes no terminal");
 await sendMarker(source,"off-source-no-fanout",[sourcePid]);
 await sendMarker(receiver,"others-keep-their-state",[receiverPid,thirdPid]);
 await focusPane(source);await trustedCommand("sync off");await noCard("sync-off-again");
 await openStatus("07-sync-off-idempotent",{count:2,running:true,states:{[receiver]:"参与",[third]:"参与"}});await closeStatus();
 report.status="passed";
 report.limits.push("Real target-generation reconnect and zero-target running detail are covered by controller contract tests; this Local runner proves real shell IO for idempotent @sync on (no confirmation), member checkbox enablement, new-member exclusion and current-session-only @sync off; status display via the group broadcast card; minimum-window anchoring and overflow scrolling use actual native layout.");
} catch(error) { report.status="failed";report.error=String(error);await capture("failed").catch(()=>{});process.exitCode=1 }
finally {await save();if(child.exitCode===null)child.kill("SIGTERM");await Promise.race([ended,sleep(3000)]);await log.close()}
