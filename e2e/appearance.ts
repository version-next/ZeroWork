/** Actual appearance settings acceptance using an existing test-mode binary.
 * node e2e/appearance.ts --out DIR [--binary PATH]
 * Seeds ordinary isolated config + a valid PNG; this does NOT test a native picker.
 * Uses public Harness input/query APIs and real Metal screenshots, never the full tree.
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import {psCompat} from './ps_compat.ts';
import assert from "node:assert/strict";
import { spawn, execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdir, mkdtemp, open, readFile, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { waitForServerReady, waitFor, query, inputState, clickTestId, key, type_, resizeWindow, screenshot, sleep, request } from "../zig-out/share/zenit/harness/client.ts";
// Two-level Settings window (overview → subpage; no close button, Cmd+W closes): shared navigation.
import { settingsNav } from "./settings_nav.ts";
const nav = settingsNav();

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const args = process.argv.slice(2), options: Record<string, string> = {};
for (let i = 0; i < args.length; i += 2) {
  assert(["--binary", "--out"].includes(args[i]) && args[i + 1], `Invalid option ${args[i]}`);
  options[args[i]] = args[i + 1];
}
assert(options["--out"], "--out is required");
const output = resolve(options["--out"]);
const binary = resolve(options["--binary"] ?? join(root, "zig-out/bin/zerowork"));
const binaryHash = createHash("sha256").update(await readFile(binary)).digest("hex");
const isolated = await mkdtemp(join(tmpdir(), "zerowork-appearance-ui-"));
const rpc = join(isolated, "rpc"), data = join(isolated, "data");
await Promise.all([mkdir(output, { recursive: true }), mkdir(rpc), mkdir(data)]);
const image = join(data, "background.png"), configPath = join(data, "config.toml");
// Same valid, opaque-red 1x1 PNG exercised by background_asset_tests.zig.
await writeFile(image, Buffer.from(
  "89504e470d0a1a0a0000000d49484452" + "000000010000000108060000001f15c489" +
  "0000000d49444154789c63f8cfc0f01f00050001ff89993d1d" + "0000000049454e44ae426082", "hex"));
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
await writeFile(join(output, "config-before.toml"), baseline);
// The regression runner's isolation guard appends `[updates] auto_check=false` to any config.toml it
// sees written: the committed file is what is actually on disk.
const committedBaseline = await readFile(configPath, "utf8");
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
  checks: [], captures: [], limits: [
    "Native image/theme file picker, cancellation and replacement require separate native UI acceptance; no picker success is claimed.",
    "Harness synthetic text/key events do not prove real IME or physical modifier release.",
    "Screenshots are captured for visual review; this script does not assert pixel parity with Figma.",
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
async function openSettings(): Promise<void> {
  await nav.toSub("appearance", "font");
  await visible("settings.appearance.font");
}
/** Cmd+W asks to close the Settings window (the old settings.close button). */
async function requestClose(): Promise<void> {
  assert((await key("w", { cmd: true })).ok, "Cmd+W");
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
  "settings.panel", "settings.page.title", "settings.footer.state", "settings.appearance.font",
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
  const owner = JSON.parse(await readFile(join(rpc, "owner.json"), "utf8"));
  assert.equal(Number(owner.pid), child.pid, "Harness must belong to this isolated process");
  report.descendants_at_start = descendants();
  assert((await resizeWindow(1440, 900)).ok);
  // Panes no longer fold: the font fields live on the 字体与排版 subpage and are absent from the 主题 subpage.
  await nav.toSub("appearance", "theme");
  await waitFor(async () => (await visible("settings.background.state")).text?.includes("本地 · 1 × 1") || null);
  await hidden("settings.field.font_size");
  await openSettings();
  await expectInput("settings.field.font_size", "14");
  await capture("appearance-entry");
  checks.push("Production toolbar and Appearance overview open the real subpages; the font subpage shows the font fields; saved PNG is prepared by the real worker");

  // The family Select is now searchable and virtualized: filter to 自定义字体… before choosing it.
  await click("settings.field.font_family");
  assert((await key("a", { cmd: true })).ok && (await key("backspace")).ok); // the search text starts as the current family
  assert((await type_("自定义")).ok);
  await click("settings.option.font_family.custom");
  await edit("settings.field.font_family", "Monaco");
  await edit("settings.field.font_size", "18");
  await edit("settings.field.line_height", "1.8");
  await footer("未保存");
  // Was: fold and unfold the font pane. Panes no longer fold; a draft belongs to its subpage, and leaving
  // the subpage asks first. Continue Editing keeps the subpage and its draft.
  await click("settings.nav.appearance");
  await visible("settings.confirmation");
  await click("settings.confirmation.cancel");
  await hidden("settings.confirmation");
  await nav.waitTitle("字体与排版");
  await footer("未保存");
  await expectInput("settings.field.font_size", "18");
  assert.equal(await readFile(configPath, "utf8"), committedBaseline, "Editing must not publish config");
  await capture("appearance-font-draft");
  await requestClose();
  await click("settings.confirmation.cancel");
  await hidden("settings.confirmation");
  await expectInput("settings.field.font_size", "18");
  await requestClose();
  await click("settings.confirmation.discard");
  await hidden("settings.panel");
  // The preferences window retires at the runtime's next safe boundary: reopen only after it is gone.
  await waitFor(async () => (await request("GET", "/windows")).windows.length === 1 || null);
  assert.equal(await readFile(configPath, "utf8"), committedBaseline, "Discard must preserve the committed file");
  await openSettings();
  await expectInput("settings.field.font_family", "Menlo");
  await expectInput("settings.field.font_size", "14");
  await expectInput("settings.field.line_height", "1.5");
  await nav.toSub("appearance", "theme");
  await waitFor(async () => (await visible("settings.background.state")).text?.includes("本地 · 1 × 1") || null);
  await footer("已保存");
  await nav.toSub("appearance", "font");
  checks.push("Real custom-family, size and line-height edits survive the leave-subpage prompt and Continue Editing; Discard reopens the previous committed values without writing config");

  await edit("settings.field.font_family", "Monaco");
  await edit("settings.field.font_size", "16");
  await edit("settings.field.line_height", "1.75");
  // Typography and materials are separate subpages: leaving the font subpage saves its draft from the prompt.
  await click("settings.nav.appearance");
  await click("settings.confirmation.save");
  await hidden("settings.confirmation");
  const typography = await readFile(configPath, "utf8");
  for (const [field, expected] of [["font_family", "Monaco"], ["font_size", 16], ["line_height", 1.75]] as const) assert.equal(configValue(typography, "ui", field), expected, `Prompt Save persisted ui.${field}`);
  assert.equal(configValue(typography, "ui.materials.background", "transparency"), 25, "Typography save leaves materials untouched");
  await nav.toSub("appearance", "theme");
  await nav.reveal("settings.field.transparency");
  await edit("settings.field.transparency", "42");
  await edit("settings.field.blur_px", "12");
  await nav.reveal("settings.materials.preview.open");
  await click("settings.materials.preview.open");
  await bindMainWindow();
  await visible("settings.materials.preview.actions");
  await hidden("settings.panel");
  await capture("appearance-material-preview");
  await click("settings.materials.preview.return");
  await hidden("settings.materials.preview.actions");
  await bindSettingsWindow();
  await expectInput("settings.field.transparency", "42");
  await expectInput("settings.field.blur_px", "12");
  // Typography (16) was saved from the leave-subpage prompt before the preview; reaching the font subpage now
  // would ask about the material draft. Its value is held by the file, checked unchanged right below.
  assert.equal(configValue(await readFile(configPath, "utf8"), "ui", "font_size"), 16, "Typography survives the material preview");
  await expectInput("settings.field.blur_px", "12");
  await footer("未保存");
  assert.equal(await readFile(configPath, "utf8"), typography, "Material preview must not publish config");
  await capture("appearance-preview-return");
  checks.push("Material preview opens against the prepared image and returns with typography and material drafts intact, without changing the committed file");

  await click("settings.save");
  await footer("已保存");
  const saved = await readFile(configPath, "utf8");
  for (const [section, field, expected] of [
    ["ui", "font_family", "Monaco"], ["ui", "font_size", 16], ["ui", "line_height", 1.75],
    ["ui", "theme", "dark"], ["ui.materials", "blur_px", 12],
    ["ui.materials.background", "enabled", true], ["ui.materials.background", "path", image],
    ["ui.materials.background", "transparency", 42],
  ] as const) assert.equal(configValue(saved, section, field), expected, `Persisted ${section}.${field}`);
  assert(Number(configValue(saved, "meta", "config_revision")) > 1, "Save must advance the real configuration revision");
  assert(Number(configValue(saved, "meta", "config_revision")) > Number(configValue(typography, "meta", "config_revision")), "Material Save advances past the typography save");
  await writeFile(join(output, "config-after.toml"), saved);
  await capture("appearance-saved");
  checks.push("Save completes the production configuration transaction; actual config.toml contains Monaco/16/1.75, blur 12, transparency 42 and a newer revision");
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
