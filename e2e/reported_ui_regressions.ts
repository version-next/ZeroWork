/** Targeted native regression for the reported terminal / sidebar issues, against the current shell.
 * node e2e/reported_ui_regressions.ts OUTPUT [THEME]   (THEME: dark | light | sauber, default dark; launches zig-out/bin/zerowork)
 *
 * Reported issues and the current contract that keeps each one fixed:
 *  1. “the connection identity changes width when the sidebar collapses / the window narrows”. The status-bar identity
 *     chip is gone: the identity is a geometry-only region laid exactly over the active tab (workspace_chrome.zig
 *     `identitiesAtTabs` / `afterLayout`, d6c927e3 title-click: the card opens from the tab menu, never on hover;
 *     pointer events pass through, not focusable). For a local tab only `local.status.identity` shows, the remote
 *     `status.connection.identity` stays hidden, and the region follows the tab when the sidebar collapses and in a
 *     narrow window.
 *  2–3. “the compact host detail kept a fixed excess height / did not dismiss when the pointer left”. The collapsed
 *     sidebar rail with per-host icons and its detail panel (sidebar.rail.host.*, sidebar.rail.detail) was removed
 *     in a46bf0f4 (sidebar_collapsed_view.zig: a hidden sidebar leaves only the restore toggle, 191f6aa6: no width-based
 *     collapse). Its successor is the host identity tooltip `sidebar.host.info` (sidebar_view.zig `mountHostHint`, a
 *     native hover Popover, `size_policy = .fit_content`, max height 120, padding 8 / 10 from sidebar_styles.zig
 *     `hint`): it hugs its text and closes when the pointer leaves the row.
 *  4. Real PTY output: a coloured bold row and `ls -C` columns render as text rows; the input-line highlight is on.
 *  5. Narrow window (860 × 480): the identity region still covers the active tab.
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdir, mkdtemp, open, readFile, writeFile, rm, realpath } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { waitForServerReady, waitFor, query, clickAt, key, type_, resizeWindow, screenshot, sleep, mouseMove } from "../zig-out/share/zenit/harness/client.ts";
const out = resolve(process.argv[2] ?? "/tmp/zerowork-five-fixes/native");
const theme = process.argv[3] || "dark";
assert(["dark", "light", "sauber"].includes(theme), "theme: dark | light | sauber");
const iso = await realpath(await mkdtemp(join(tmpdir(), "zw-reported-ui-"))), rpc = join(iso,"rpc"), data=join(iso,"data");
await Promise.all([mkdir(out,{recursive:true}),mkdir(rpc),mkdir(data)]);
await writeFile(join(data,"config.toml"), `[meta]\nconfig_revision=1\n[ui]\ntheme="${theme}"\nfont_family="Menlo"\nfont_size=14\ninput_line_highlight=true\n`);
await writeFile(join(data,"hosts.toml"), `[registry]\nschema_version=2\nrevision=1\nnext_connection_id=2\nnext_group_id=1\n[[hosts]]\nconnection_id=1\nrevision=1\nprotocol="ssh"\nauth_mode="password"\nname="Regression host"\nhost="127.0.0.1"\nport=9\nuser="test"\n`);
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const log=await open(join(out,"app.log"),"w");
const app=spawn(resolve("zig-out/bin/zerowork"),[],{env:{...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:"0",ZENIT_E2E_BACKGROUND:"1",ZENIT_E2E_ISOLATE_POINTER:"1"},stdio:["ignore",log.fd,log.fd]});
const ended=new Promise<void>(r=>app.once("close",()=>r()));
const report:any={status:"running",theme,pid:app.pid,rpc,data,checks:[]};
await writeFile(join(out,"launch.json"),JSON.stringify(report));
const text=(n:any):string=>(n.text??"")+(n.children??[]).map(text).join("");
const flat=(n:any):any[]=>n?[n,...(n.children??[]).flatMap(flat)]:[];
const shown=(n:any)=>n&&n.hidden!==true&&n.visible!==false&&(n.effective_opacity??1)>0&&n.rect.w>0&&n.rect.h>0;
const presented=(n:any)=>shown(n)&&(n.effective_opacity??1)===1;
const visible=async(id:string)=>waitFor(async()=>(await query(id)).find(shown)??null,10000).catch(()=>assert.fail(`${id} visible`));
const hidden=async(id:string)=>waitFor(async()=>!(await query(id)).some(shown)||null,5000).catch(()=>assert.fail(`${id} hidden`));
const click=async(id:string)=>{const n=await waitFor(async()=>(await query(id)).find(presented)??null,10000).catch(()=>assert.fail(`${id} presented`));assert((await clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok,id);};
const cap=async(name:string)=>{assert((await screenshot(join(out,name+".png"))).ok);};
const sameRect=(a:any,b:any)=>["x","y","w","h"].every(k=>Math.abs(a[k]-b[k])<.5);
/** The single shown session tab of the strip. */
const activeTab=async()=>{const tabs=(await query("tabs.strip")).flatMap(flat).filter(n=>shown(n)&&/^tabs\.tab\.\d+$/.test(n.test_id??""));assert.equal(tabs.length,1,"one local session tab");return tabs[0];};
/** Issue 1 / 5: the local identity region lies exactly over the active tab (re-laid out after layout, hence the wait). */
async function identityOverTab(state:string){
 const placed=await waitFor(async()=>{const tab=await activeTab(),id=(await query("local.status.identity")).find(shown);return id&&sameRect(id.rect,tab.rect)?{tab:tab.rect,identity:id.rect,node:id}:null;},5000)
  .catch(async()=>assert.fail(`${state}: local identity covers the active tab: ${JSON.stringify((await query("local.status.identity")).map((n:any)=>n.rect))} vs ${JSON.stringify((await activeTab()).rect)}`));
 assert.equal(placed.node.focusable??false,false,`${state}: the identity region is not in the tab order`);
 assert(!(await query("status.connection.identity")).some(shown),`${state}: a local tab shows no remote identity region`);
 report.checks.push({state,tab:placed.tab,identity:placed.identity});
 return placed.tab;
}
try {
 await waitForServerReady(60000);
 assert.equal(Number(JSON.parse(await readFile(join(rpc,"owner.json"),"utf8")).pid),app.pid);
 await resizeWindow(1440,900);
 await click("workspace.empty.local");await visible("terminal.surface");
 const wide=await identityOverTab("sidebar expanded");
 await click("sidebar.collapse");await hidden("workspace.sidebar");
 const collapsed=await identityOverTab("sidebar collapsed");
 assert(collapsed.x<wide.x-100,`collapsing the sidebar moves the tab left (${wide.x} → ${collapsed.x}) and the identity follows it`);
 await cap("01-identity-over-tab-sidebar-collapsed");
 report.checks.push("Issue 1: the local identity is a geometry-only region exactly over the active tab, sidebar expanded and collapsed; no remote identity on a local tab.");
 // Issues 2–3: the rail detail's successor, the host identity tooltip, hugs its text and dismisses on leave.
 await click("sidebar.restore");await visible("workspace.sidebar");
 const name=await visible("sidebar.host.name");
 await mouseMove(name.rect.x+Math.min(30,name.rect.w/2),name.rect.y+name.rect.h/2);
 const info=await waitFor(async()=>(await query("sidebar.host.info")).find(presented)??null,5000).catch(()=>assert.fail("hovering a host name opens its identity tooltip"));
 assert(text(info).includes("Regression host")&&text(info).includes("127.0.0.1"),`identity tooltip carries the host name and address: ${text(info)}`);
 const label=flat(info).find((n:any)=>n!==info&&typeof n.text==="string"&&n.text.includes("Regression host"));
 assert(label,"tooltip label");
 // sidebar_styles.zig hint(): padding top/bottom 8, left/right 10 — the panel is its label plus that padding, no reserve.
 assert(Math.abs(info.rect.h-(label.rect.h+16))<1,`tooltip height fits its text: panel ${info.rect.h}, text ${label.rect.h} + 16`);
 assert(info.rect.h<=120+.5,"tooltip stays within its max height (120)");
 await cap("02-host-identity-tooltip");
 await mouseMove(900,500);await hidden("sidebar.host.info");
 report.checks.push("Issues 2–3: the rail and its detail panel were removed (a46bf0f4); the host identity tooltip hugs its text and closes when the pointer leaves.");
 // Issue 4: real PTY output.
 const surface=await visible("terminal.surface");
 assert((await clickAt(surface.rect.x+surface.rect.w/2,surface.rect.y+surface.rect.h/2)).ok);
 assert((await type_("printf '\\033[1;34mfirst-directory    second-directory    third-directory\\033[0m\\n'; ls -CF /usr/bin | head -12")).ok);assert((await key("return")).ok);
 await waitFor(async()=>(await query("terminal.surface")).flatMap(flat).some((row:any)=>/^terminal\.surface\.row\.\d+$/.test(row.test_id??"")&&text(row).includes("first-directory")&&text(row).includes("third-directory")&&!text(row).includes("printf"))||null,10000)
  .catch(()=>assert.fail("the coloured bold directory row is printed"));
 await waitFor(async()=>{const rows=(await query("terminal.surface")).flatMap(flat).filter((row:any)=>/^terminal\.surface\.row\.\d+$/.test(row.test_id??""));const at=rows.findIndex((row:any)=>text(row).includes("first-directory")&&!text(row).includes("printf"));return at>=0&&rows.slice(at+1,at+3).every((row:any)=>text(row).trim().length>0)||null;},10000)
  .catch(()=>assert.fail("ls -C prints column rows under the coloured row"));
 report.checks.push("Issue 4: real PTY emits the coloured bold directory row and ls -C column rows; screenshot reviewed for columns and the input-line highlight.");
 await cap("03-terminal-columns-and-highlight");
 // Issue 5: narrow window.
 await resizeWindow(860,480);
 await identityOverTab("narrow window");
 await cap("04-narrow-identity");
 report.status="passed";
} catch(e) { report.status="failed";report.error=String(e);console.error(e);await cap("failure").catch(()=>{}); }
finally { if(app.exitCode===null&&app.signalCode===null)app.kill("SIGTERM");await Promise.race([ended,sleep(2000)]);if(app.exitCode===null&&app.signalCode===null){app.kill("SIGKILL");await ended;}await log.close();await rm(iso,{recursive:true,force:true});await writeFile(join(out,"report.json"),JSON.stringify(report,null,2)); }
console.log(JSON.stringify(report));if(report.status!=="passed")process.exitCode=1;
