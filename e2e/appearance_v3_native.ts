/** Frozen V3 appearance acceptance using a privately prefixed test-mode binary.
 * node e2e/appearance.ts --out DIR [--binary PATH]
 * Seeds ordinary isolated config + a valid PNG; this does NOT test a native picker.
 * Uses public Harness input/query APIs and real Metal screenshots, never the full tree.
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import {psCompat} from './ps_compat.ts';
import assert from "node:assert/strict";
import { spawn, execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdir, mkdtemp, open, readFile, writeFile, rm, realpath } from "node:fs/promises";
import { deflateSync } from "node:zlib";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
const prefix = process.env.ZW_APPEARANCE_TEST_PREFIX ?? "/tmp/zw-appearance-v3";
const { waitForServerReady, waitFor, query, inputState, clickTestId, key, type_, resizeWindow, screenshot, sleep, scrollAt, request } = await import(join(prefix, "share/zenit/harness/client.ts"));
// Two-level Settings window (overview → subpage; panes no longer fold; Cmd+W closes; leaving a subpage
// with a draft asks first): shared navigation.
import { settingsNav, clickLabel } from "./settings_nav.ts";
const nav = settingsNav();

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const args = process.argv.slice(2), options: Record<string, string> = {};
for (let i = 0; i < args.length; i += 2) {
  assert(["--binary", "--out"].includes(args[i]) && args[i + 1], `Invalid option ${args[i]}`);
  options[args[i]] = args[i + 1];
}
assert(options["--out"], "--out is required");
const output = resolve(options["--out"]);
const binary = resolve(options["--binary"] ?? join(prefix,"bin/zerowork"));
const binaryHash = createHash("sha256").update(await readFile(binary)).digest("hex");
const isolated = await realpath(await mkdtemp(join(tmpdir(), "zerowork-appearance-v3-")));
const rpc = join(isolated, "rpc"), data = join(isolated, "data");
await Promise.all([mkdir(output, { recursive: true }), mkdir(rpc), mkdir(data)]);
const image = join(data, "background.png"), configPath = join(data, "config.toml");
// Geometric, non-photographic 240×160 quadrants expose fit/alignment/blur.
function crc32(bytes: Buffer): number { let crc=0xffffffff;for(const byte of bytes){crc^=byte;for(let i=0;i<8;i++)crc=(crc>>>1)^((crc&1)?0xedb88320:0);}return (crc^0xffffffff)>>>0; }
function chunk(kind: string, body: Buffer): Buffer {const type=Buffer.from(kind),len=Buffer.alloc(4),crc=Buffer.alloc(4);len.writeUInt32BE(body.length);crc.writeUInt32BE(crc32(Buffer.concat([type,body])));return Buffer.concat([len,type,body,crc]);}
const raw=Buffer.alloc(160*(1+240*4));for(let y=0;y<160;y++)for(let x=0;x<240;x++){const at=y*961+1+x*4;const color=y<80?(x<120?[235,74,67]:[68,190,105]):(x<120?[71,129,232]:[242,192,65]);raw.set([...color,255],at);}
const ihdr=Buffer.alloc(13);ihdr.writeUInt32BE(240);ihdr.writeUInt32BE(160,4);ihdr[8]=8;ihdr[9]=6;
const fixtureBytes=Buffer.concat([Buffer.from('89504e470d0a1a0a','hex'),chunk('IHDR',ihdr),chunk('IDAT',deflateSync(raw)),chunk('IEND',Buffer.alloc(0))]);
await writeFile(image,fixtureBytes);
const fixtureHash=createHash('sha256').update(fixtureBytes).digest('hex');
const baseline = `[meta]
config_revision = 1
[ui]
theme = "dark"
font_family = "Menlo"
font_size = 14
font_weight = "regular"
line_height = 1.5
[ui.materials]
blur_px = 4
[ui.materials.background]
enabled = true
path = ${JSON.stringify(image)}
fit = "fill"
alignment_x = "center"
alignment_y = "center"
transparency = 25
`;
await writeFile(configPath, baseline);
// The regression runner's isolation guard appends `[updates] auto_check=false` to any config.toml it
// sees written: the committed file is what is actually on disk.
const committedBaseline = await readFile(configPath, "utf8");
await writeFile(join(output, "config-before.toml"), baseline);
process.env.ZENIT_E2E_FILE_RPC_DIR = rpc;
const log = await open(join(output, "app.log"), "w");
const child = spawn(binary, [], { cwd: root, env: {
  ...process.env, ZENIT_E2E_FILE_RPC_DIR: rpc, ZENIT_E2E_ISOLATE_POINTER: "1",
  ZENIT_E2E_BACKGROUND: "1", ZEROWORK_DATA_DIR: data, ZEROWORK_AUTOCONNECT: "0",
}, stdio: ["ignore", log.fd, log.fd] });
const ended = new Promise<void>((done) => child.once("close", () => done()));
let launchError: Error | undefined;
child.once("error", (error) => { launchError = error; });
const report: Record<string, unknown> = {
  status: "running", binary, binary_sha256: binaryHash, pid: child.pid,
  started_at: new Date().toISOString(), storage: "isolated temporary config, image and file RPC",
  background_source: "normal saved config fixture; real application worker decodes and prepares it",
  checks: [], captures: [], fixture_sha256: fixtureHash, limits: [
    "Native image/theme file picker, cancellation and replacement require separate native UI acceptance; no picker success is claimed.",
    "Harness synthetic text/key events do not prove real IME or physical modifier release.",
    "Screenshots are captured for visual review; this script does not assert pixel parity with the frozen HTML.",
    "Own-process SIGTERM cleanup is not evidence of normal application shutdown.",
  ],
};
const checks = report.checks as string[];
type Node = Awaited<ReturnType<typeof query>>[number] & { hidden?: boolean; effective_opacity?: number };
function shown(node: Node): boolean {
  return node.hidden !== true && node.visible !== false && (node.effective_opacity ?? 1) > 0 && node.rect.w > 0 && node.rect.h > 0;
}
async function visible(id: string): Promise<Node> {
  return await waitFor(async () => (await query(id)).find(shown) ?? null);
}
async function hidden(id: string): Promise<void> {
  await waitFor(async () => !(await query(id)).some(shown) || null);
}
async function click(id: string): Promise<void> {
  await visible(id);
  // The public click API brings the target into its real ScrollArea viewport.
  assert((await clickTestId(id)).ok, `Click ${id}`);
}
// Committed numeric fields are now shown in their canonical format (line height "1.80"): compare numbers.
const sameValue = (buffer: string, value: string) => buffer === value || (/^-?[0-9.]+$/.test(value) && /^-?[0-9.]+$/.test(buffer) && Number(buffer) === Number(value));
async function expectInput(id: string, value: string): Promise<void> {
  await waitFor(async () => sameValue((await inputState(id)).buffer, value) || null);
}
async function edit(id: string, value: string): Promise<void> {
  await click(id);
  assert((await key("a", { cmd: true })).ok);
  assert((await type_(value)).ok);
  assert((await key("return")).ok);
  await expectInput(id, value);
}
// Floating Save Bar (H-save): it shows "未保存" / "有设置需要修正" (was "请修正设置中的错误") while a draft exists
// and hides once the draft is saved or there is none (was a persistent "已保存" footer).
const footerText: Record<string, string> = { "请修正设置中的错误": "有设置需要修正" };
async function footer(value: string): Promise<void> {
  if (value === "已保存") { await waitFor(async () => !(await query("settings.footer")).some(shown) || null); return; }
  const want = footerText[value] ?? value;
  await waitFor(async () => (await visible("settings.footer.state")).text === want || null);
}
async function openSettings(sub: "theme" | "font" = "theme"): Promise<void> {
  await nav.toSub("appearance", sub);
  await visible(sub === "theme" ? "settings.appearance.materials" : "settings.appearance.font");
}
/** Cmd+W asks to close the Settings window (the old settings.close button). */
async function requestClose(): Promise<void> { assert((await key("w", { cmd: true })).ok, "Cmd+W"); }
/** Leave the current subpage with a draft: the prompt decides (`cancel` keeps editing). */
async function leaveWith(choice: "cancel" | "discard" | "save"): Promise<void> {
  await click("settings.nav.appearance"); await visible("settings.confirmation");
  await click(`settings.confirmation.${choice}`); await hidden("settings.confirmation");
}
function descendants(): { pid: number; parent: number; command: string }[] {
  const all = psCompat(["-axo", "pid=,ppid=,comm="]).trim().split("\n").flatMap((line) => {
    const match = line.trim().match(/^(\d+)\s+(\d+)\s+(.+)$/);
    return match ? [{ pid: Number(match[1]), parent: Number(match[2]), command: match[3] }] : [];
  });
  const owned = new Set([child.pid]);
  for (let i = 0; i < all.length; i++) {
    let changed = false;
    for (const process of all) if (owned.has(process.parent) && !owned.has(process.pid)) { owned.add(process.pid); changed = true; }
    if (!changed) break;
  }
  return all.filter((process) => process.pid !== child.pid && owned.has(process.pid));
}
const evidenceIds = [
  "settings.page.title", "settings.panel", "settings.footer.state", "settings.appearance.font", "settings.background.preview", "settings.background.material.surface", "settings.background.material.layer", "settings.font.preview.caret", "settings.theme.remove.current", "settings.theme.import",
  "settings.field.font_family", "settings.field.font_size", "settings.field.line_height",
  "settings.font.status", "settings.background.state", "settings.field.transparency",
  "settings.field.blur_px", "settings.materials.preview.actions", "settings.confirmation",
];
async function capture(name: string): Promise<void> {
  await sleep(250);
  const path = join(output, `${name}.png`);
  assert((await screenshot(path)).ok, `Screenshot ${name}`);
  const queries = Object.fromEntries(await Promise.all(evidenceIds.map(async (id) => [id, await query(id)])));
  await writeFile(join(output, `${name}.queries.json`), JSON.stringify(queries, null, 2));
  (report.captures as string[]).push(path);
}
function configValue(source: string, section: string, field: string): unknown {
  let current = "";
  for (const raw of source.split("\n")) {
    const line = raw.trim();
    if (line.startsWith("[")) { current = line.slice(1, -1); continue; }
    if (current !== section) continue;
    const match = line.match(/^([a-z_]+)\s*=\s*(.+)$/);
    if (match?.[1] === field) return JSON.parse(match[2]);
  }
  throw new Error(`Missing persisted ${section}.${field}`);
}
// The full-window material preview is shown in the owning main window (SettingsHost.setMaterialPreview activates
// it), but test-mode automation stays bound to the preferences window. Bind the harness to the main window for
// the preview, then reopen Settings from its toolbar (presentWindow rebinds the harness to the preferences window).
async function bindMainWindow(): Promise<void> {
  const snapshot = await request("POST", "/zerowork/windows", { action: "snapshot" });
  assert((await request("POST", "/zerowork/windows", { action: "select", window: snapshot.windows[0].window })).ok, "bind main window");
}
async function boundWindow(): Promise<string | undefined> { return (await request("GET", "/windows")).windows.find((w: any) => w.bound)?.window_id; }
async function bindSettingsWindow(): Promise<void> {
  const main = await boundWindow();
  await click("toolbar.settings");
  await waitFor(async () => (await boundWindow()) !== main || null);
  const panel = await visible("settings.panel"), viewport = await visible("settings.viewport");
  // Returning from the preview keeps the Settings layout inside its 960×780 window (Save Bar reachable).
  assert(panel.rect.h <= 780.5 && viewport.rect.y + viewport.rect.h <= panel.rect.y + panel.rect.h + 0.5, `settings layout fits its window after the material preview: panel ${JSON.stringify(panel.rect)} viewport ${JSON.stringify(viewport.rect)}`);
}
let failure: unknown;
try {
  await waitForServerReady();
  const owner = JSON.parse(await readFile(join(rpc,"owner.json"),"utf8"));assert.equal(Number(owner.pid),child.pid);
  // Panes no longer fold: the materials pane is on the 主题 subpage and is open on arrival.
  assert((await resizeWindow(1440,900)).ok);await openSettings("theme");await nav.reveal("settings.background.state");
  await waitFor(async()=>(await visible("settings.background.state")).text?.includes("240 × 160")||null);
  const initialPreview=await nav.reveal("settings.background.preview");assert.equal(initialPreview.rect.h,116);
  const protectedDelete=await nav.reveal("settings.theme.remove.current");assert.notEqual(protectedDelete.focusable,true);
  await capture("01-dark-inline");checks.push("Prepared normal-config PNG and inline preview116; builtin current delete protected; text itermcolors entry");
  await nav.reveal("settings.field.fit");
  await click("settings.field.fit");await click("settings.option.fit.fit");await click("settings.field.alignment");await click("settings.alignment.右下");
  await edit("settings.field.transparency","0");await edit("settings.field.blur_px","0");await click("settings.background.preview");await capture("02-fit-bottom-right");
  await click("settings.field.fit");await click("settings.option.fit.tile");await edit("settings.field.blur_px","12");await edit("settings.field.transparency","42");await click("settings.background.preview");await capture("03-tile-blurred");
  assert.equal(await readFile(configPath,"utf8"),committedBaseline);assert.equal(createHash('sha256').update(await readFile(image)).digest('hex'),fixtureHash);
  await click("settings.toggle.enabled");await visible("settings.field.transparency");await capture("04-background-off-editable");await click("settings.toggle.enabled");
  await nav.reveal("settings.materials.preview.full");
  await click("settings.materials.preview.full");await bindMainWindow();await visible("settings.materials.preview.actions");await click("settings.materials.preview.return");await hidden("settings.materials.preview.actions");await bindSettingsWindow();
  // The material draft belongs to the 主题 subpage: leaving it to reach the font subpage asks; Discard keeps the file.
  // The terminal preview (settings.font.preview, caret) is now the 预览 pane of the 主题 subpage.
  await nav.reveal("settings.font.preview.prompt");await nav.reveal("settings.font.preview.command");await click("settings.font.preview.command");const caretStates=new Set<number>();for(let i=0;i<12;i++){const n=(await query("settings.font.preview.caret"))[0] as any;caretStates.add(n?.opacity??n?.effective_opacity??1);await sleep(120);}assert(caretStates.size>1,"caret must blink");await click("settings.font.preview");await capture("05-preview-caret");
  await leaveWith("discard");assert.equal(await readFile(configPath,"utf8"),committedBaseline);
  // Cursor shape is a native Tabs (settings.field.cursor_style) on the 字体与排版 subpage.
  await nav.toSub("appearance","font");await edit("settings.field.font_size","18");await clickLabel("settings.field.cursor_style","下划线");await footer("未保存");await capture("05-font-cursor");
  await requestClose();await click("settings.confirmation.cancel");await expectInput("settings.field.font_size","18");await requestClose();await click("settings.confirmation.discard");await hidden("settings.panel");/* the preferences window retires at the next safe boundary: reopen after it is gone */await waitFor(async()=>(await request("GET","/windows")).windows.length===1||null);assert.equal(await readFile(configPath,"utf8"),committedBaseline);
  await openSettings("font");await expectInput("settings.field.font_size","14");await nav.toSub("appearance","theme");await nav.reveal("settings.field.transparency");await edit("settings.field.transparency","42");await click("settings.save");await footer("已保存");const saved=await readFile(configPath,"utf8");assert.equal(configValue(saved,"ui.materials.background","transparency"),42);checks.push("Fit, bottom-right, tile, blur12, transparency42, disabled-editability, full-window return, cursor selection/blink, leave-subpage Discard, Cancel/Discard and Save checked via real native actions");
  await nav.reveal("settings.theme.light");await click("settings.theme.light");await click("settings.save");await footer("已保存");await nav.reveal("settings.toggle.enabled");await click("settings.toggle.enabled");await click("settings.save");await footer("已保存");await nav.reveal("settings.background.preview");await click("settings.background.preview");await capture("06-light");
  // Was: fold / unfold the materials pane at the minimum size. Now: scroll the real settings viewport to it.
  assert((await resizeWindow(860,480)).ok);await sleep(300);await nav.reveal("settings.background.preview");await click("settings.background.preview");await capture("07-minimum-scrolled");assert.equal((await visible("settings.background.preview")).rect.h,116);
  assert.equal(createHash('sha256').update(await readFile(image)).digest('hex'),fixtureHash);checks.push("Saved Light with background off, minimum860×480 native scroll/preview116 and source fixture unchanged");
  report.status = "passed";
} catch (error) {
  failure = launchError ?? error;
  report.status = "failed";
  report.error = String(failure);
  if (child.exitCode === null && child.signalCode === null) {
    await Promise.allSettled([capture("failure"), writeFile(join(output, "remaining-processes.json"), JSON.stringify(descendants(), null, 2))]);
  }
} finally {
  // Only this runner's process tree; termination is cleanup, not normal-close proof.
  if (child.exitCode === null && child.signalCode === null) {
    const remaining = descendants();
    report.forced_child_cleanup = remaining.map((value) => value.pid);
    for (const value of remaining.reverse()) { try { process.kill(value.pid, "SIGHUP"); } catch (error) { if ((error as NodeJS.ErrnoException).code !== "ESRCH") throw error; } }
    child.kill("SIGTERM");
  }
  await Promise.race([ended, sleep(2000)]);
  if (child.exitCode === null && child.signalCode === null) { child.kill("SIGKILL"); await ended; }
  report.process_cleanup = { exit_code: child.exitCode, signal: child.signalCode };
  report.finished_at = new Date().toISOString();
  await writeFile(join(output, "report.json"), JSON.stringify(report, null, 2));
  await log.close();
  await rm(isolated, { recursive: true, force: true });
}
console.log(`${report.status}: ${join(output, "report.json")}`);
if (failure) throw failure;
