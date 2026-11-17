/** Narrow appearance/status acceptance using an existing test-mode binary.
 * node e2e/appearance_edges.ts --out DIR [--binary PATH]
 * Public Harness only: raw recovery, reference removal and status Escape focus.
 * Native replacement/bad-image picker paths are deliberately left to native_input.
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
import { waitForServerReady, waitFor, query, focused, inputState, clickTestId, clickAt, key, type_, resizeWindow, screenshot, sleep, mouseMove } from "../zig-out/share/zenit/harness/client.ts";
// Two-level Settings window (overview → subpage, Cmd+W closes): shared navigation.
import { settingsNav } from "./settings_nav.ts";

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
const isolated = await mkdtemp(join(tmpdir(), "zerowork-appearance-edges-"));
const rpc = join(isolated, "rpc"), data = join(isolated, "data");
await Promise.all([mkdir(output, { recursive: true }), mkdir(rpc), mkdir(data)]);
const image = join(data, "background.png"), configPath = join(data, "config.toml");
const imageBytes = Buffer.from(
  "89504e470d0a1a0a0000000d49484452" + "000000010000000108060000001f15c489" +
  "0000000d49444154789c63f8cfc0f01f00050001ff89993d1d" + "0000000049454e44ae426082", "hex");
await writeFile(image, imageBytes);
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
await Promise.all([writeFile(configPath, baseline), writeFile(join(output, "config-before.toml"), baseline)]);
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
const checks: string[] = [], captures: string[] = [];
const report: Record<string, unknown> = {
  status: "running", binary, binary_sha256: binaryHash, pid: child.pid,
  started_at: new Date().toISOString(), storage: "isolated data and file RPC",
  checks, captures, visual_review: "pending", limits: [
    "Background replacement, bad-image last-good retention and disabling a bad selected image require the native picker and are not covered. No injection or picker success is claimed.",
    "Removing an enabled image leaves an unprepared empty reference; the resulting Save gate is a separate case from decode failure.",
    "Synthetic Harness keys do not prove real IME; screenshots require visual review.",
    "Own-process termination is cleanup, not evidence of normal application shutdown.",
  ],
};
type Node = Awaited<ReturnType<typeof query>>[number] & { hidden?: boolean; effective_opacity?: number };
function shown(node: Node): boolean {
  return node.hidden !== true && node.visible !== false && (node.effective_opacity ?? 1) > 0 && node.rect.w > 0 && node.rect.h > 0;
}
function text(node: Node): string { return (node.text ?? "") + (node.children ?? []).map((child) => text(child)).join(""); }
async function visible(id: string): Promise<Node> { return await waitFor(async () => (await query(id)).find(shown) ?? null); }
async function hidden(id: string): Promise<void> { await waitFor(async () => !(await query(id)).some(shown) || null); }
async function click(id: string): Promise<void> { await visible(id); assert((await clickTestId(id)).ok, `Click ${id}`); }
// Committed numeric fields are now shown in their canonical format (line height "1.80"): compare numbers.
const sameValue = (buffer: string, value: string) => buffer === value || (/^-?[0-9.]+$/.test(value) && /^-?[0-9.]+$/.test(buffer) && Number(buffer) === Number(value));
async function expectInput(id: string, value: string): Promise<void> {
  await waitFor(async () => sameValue((await inputState(id)).buffer, value) || null);
}
async function edit(id: string, value: string, commit = true): Promise<void> {
  await click(id);
  assert((await key("a", { cmd: true })).ok);
  assert((await key("backspace")).ok);
  if (value) assert((await type_(value)).ok);
  if (commit) assert((await key("return")).ok);
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
// H-save (save_flow.zig): Save stays clickable on an invalid draft; pressing it locates the problem and writes
// nothing. "Save is blocked" is therefore checked by pressing it: the error and danger state stay, the file does not change.
async function saveBlocked(): Promise<void> {
  const before = await readFile(configPath, "utf8");
  await saveEnabled(true); await click("settings.save"); await sleep(400);
  await footer("请修正设置中的错误");
  assert.equal(await readFile(configPath, "utf8"), before, "Save on an invalid draft must not write configuration");
}
async function saveEnabled(expected: boolean): Promise<void> {
  await waitFor(async () => ((await visible("settings.save")).focusable === true) === expected || null);
}
function configValue(source: string, section: string, field: string): unknown {
  let current = "";
  for (const raw of source.split("\n")) {
    const line = raw.trim();
    if (line.startsWith("[")) { current = line.slice(1, -1); continue; }
    const match = line.match(/^([a-z_]+)\s*=\s*(.+)$/);
    if (current === section && match?.[1] === field) return JSON.parse(match[2]);
  }
  throw new Error(`Missing persisted ${section}.${field}`);
}
const evidenceIds = [
  "status.detail", "status.detail.title", "local.status.identity", "local.status.encoding", "local.status.more",
  "settings.panel", "settings.page.title", "settings.footer.state", "settings.save", "settings.field.font_size", "settings.error.font_size",
  "settings.field.line_height", "settings.error.line_height", "settings.background.filename", "settings.background.state",
  "settings.background.remove", "settings.toggle.enabled",
];
async function capture(name: string): Promise<void> {
  await sleep(250);
  const path = join(output, `${name}.png`);
  assert((await screenshot(path)).ok, `Screenshot ${name}`);
  const queries = Object.fromEntries(await Promise.all(evidenceIds.map(async (id) => [id, await query(id)])));
  await writeFile(join(output, `${name}.queries.json`), JSON.stringify({ focused: await focused(), queries }, null, 2));
  captures.push(path);
}
function descendants(): { pid: number; parent: number; command: string }[] {
  const all = psCompat(["-axo", "pid=,ppid=,comm="]).trim().split("\n").flatMap((line) => {
    const match = line.trim().match(/^(\d+)\s+(\d+)\s+(.+)$/);
    return match ? [{ pid: Number(match[1]), parent: Number(match[2]), command: match[3] }] : [];
  });
  const owned = new Set([child.pid]);
  for (let i = 0; i < all.length; i++) {
    let changed = false;
    for (const value of all) if (owned.has(value.parent) && !owned.has(value.pid)) { owned.add(value.pid); changed = true; }
    if (!changed) break;
  }
  return all.filter((value) => value.pid !== child.pid && owned.has(value.pid));
}
let failure: unknown;
try {
  await waitForServerReady();
  const owner = JSON.parse(await readFile(join(rpc, "owner.json"), "utf8"));
  assert.equal(Number(owner.pid), child.pid);
  assert((await resizeWindow(1440, 900)).ok);
  await click("workspace.empty.local");
  await visible("terminal.surface");
  const detailFocus: Record<string, unknown>[] = [];
  report.status_detail_focus = detailFocus;
  // Workspace chrome (稿 5, main_window.zig identitiesAtTabs): the Local status bar is hidden; its identity
  // trigger is a pass-through, non-focusable anchor region over the active tab. title-click: the session card
  // no longer opens on hover — hovering the tab shows its native hint only; the card opens from the tab menu's
  // “会话连接”. Encoding and grid are rows of that same card. The real card shows the actual Local facts,
  // never RTT, and Escape closes it without leaving focus in the card.
  const before = await focused();
  const trigger = await visible("local.status.identity");
  assert(trigger.focusable !== true, "Tab identity region is an anchor, not a focus stop");
  assert((await mouseMove(trigger.rect.x + trigger.rect.w / 2, trigger.rect.y + trigger.rect.h / 2)).ok);
  await sleep(900);
  assert(!(await query("status.detail")).some(shown), "Hovering the active tab opens no session card (title-click)");
  assert((await clickAt(trigger.rect.x + trigger.rect.w / 2, trigger.rect.y + trigger.rect.h / 2, 1, "right")).ok);
  await click("context.menu.session_identity");
  const card = await visible("status.detail");
  assert.equal((await visible("status.detail.title")).text, "会话详情");
  assert(Math.abs(card.rect.w - 380) <= 0.5, `session card width ${card.rect.w}`);
  for (const value of ["本地终端", "本机 · macOS", "/bin/zsh", "本地 · 交互式 Shell", "编码", "UTF-8", "网格"]) assert(text(card).includes(value), `会话连接: missing ${value}`);
  assert(!text(card).includes("往返延迟"), "Local session card must not expose RTT");
  await capture("local-status-identity");
  assert((await key("escape")).ok);
  await hidden("status.detail");
  const after = await focused();
  detailFocus.push({ trigger: "local.status.identity", title: "会话详情", card_rect: card.rect, focused_before: before, focused_after_escape: after });
  assert(!String(after.test_id ?? "").startsWith("status.detail"), "Escape must not leave focus in the closed card");
  assert.equal(after.test_id, before.test_id, "Escape returns to the focus the user had before the card");
  assert((await mouseMove(700, 600)).ok);
  checks.push("Production Local session card (tab menu “会话连接”; hover opens nothing) shows identity, shell, encoding and grid; no RTT; Escape closes it and keeps the prior focus");

  const nav = settingsNav();
  await nav.toSub("appearance", "theme");
  await waitFor(async () => (await visible("settings.background.state")).text?.includes("本地 · 1 × 1") || null);
  await nav.toSub("appearance", "font");
  await nav.reveal("settings.field.font_size");
  await edit("settings.field.font_size", "18");
  await footer("未保存");
  for (const [field, invalid, recovered] of [["font_size", "999", "18"], ["line_height", "NaN", "1.5"]] as const) {
    const input = `settings.field.${field}`;
    const error = `settings.error.${field}`;
    await edit(input, invalid, false);
    await visible(error);
    await footer("请修正设置中的错误");
    await saveBlocked();
    await waitFor(async () => (await focused()).test_id === input || null);
    await expectInput(input, invalid);
    assert.equal(await readFile(configPath, "utf8"), committedBaseline, "Invalid raw must not publish configuration");
    await capture(`raw-invalid-${field}`);

    // Save returns focus to an already-invalid field. Start a fresh focus session with a valid value before testing Escape.
    await edit(input, recovered);
    await hidden(error);
    const otherInput = field === "font_size" ? "settings.field.line_height" : "settings.field.font_size";
    await click(otherInput);
    await waitFor(async () => (await focused()).test_id === otherInput || null);
    await edit(input, invalid, false);
    await visible(error);
    await footer("请修正设置中的错误");
    assert.equal((await focused()).test_id, input, "Escape starts inside the original edit");
    assert((await key("escape")).ok);
    await expectInput(input, recovered);
    await hidden(error);
    await visible("settings.panel");
    await footer("未保存");
    await saveEnabled(true);
  }
  await click("settings.save");
  await footer("已保存");
  const valid = await readFile(configPath, "utf8");
  assert.equal(configValue(valid, "ui", "font_size"), 18);
  assert.equal(configValue(valid, "ui", "line_height"), 1.5);
  await writeFile(join(output, "raw-recovered.config.toml"), valid);
  await capture("raw-recovered-saved");
  checks.push("Invalid Save returns focus to the failing field and leaves the file unchanged; Escape in a separate edit restores the focus-time value (18/1.5), and both valid drafts can be saved");

  await nav.toSub("appearance", "theme");
  await nav.reveal("settings.background.remove");
  await click("settings.background.remove");
  await waitFor(async () => (await visible("settings.background.filename")).text === "尚未选择图片" || null);
  await footer("请修正设置中的错误");
  await saveBlocked();
  assert.equal(await readFile(configPath, "utf8"), valid, "Remove is only a draft until Save");
  assert.deepEqual(await readFile(image), imageBytes, "Remove must not delete or change the source image");
  await capture("background-removed-enabled-invalid");
  await nav.reveal("settings.toggle.enabled");
  await click("settings.toggle.enabled");
  // The image identity row now stays visible (with a "背景图片已关闭" note) while the background is off;
  // the off state is read from the pane summary instead of the hidden filename.
  await waitFor(async () => text(await visible("settings.appearance.materials.summary")).startsWith("已关闭") || null);
  await footer("未保存");
  await saveEnabled(true);
  await click("settings.save");
  await footer("已保存");
  const removed = await readFile(configPath, "utf8");
  assert.equal(configValue(removed, "ui.materials.background", "enabled"), false);
  assert.equal(configValue(removed, "ui.materials.background", "path"), "");
  assert.equal(configValue(removed, "ui", "font_size"), 18);
  assert(Number(configValue(removed, "meta", "config_revision")) > Number(configValue(valid, "meta", "config_revision")));
  assert.deepEqual(await readFile(image), imageBytes, "Only the reference may be removed");
  await writeFile(join(output, "background-removed.config.toml"), removed);
  await capture("background-removed-disabled-saved");
  checks.push("Removing the image changes only its draft reference and blocks Save while enabled; disabling allows actual Save of the empty reference, and source PNG bytes remain unchanged");
  report.status = "functional_checks_passed";
} catch (error) {
  failure = launchError ?? error;
  report.status = "failed";
  report.error = String(failure);
  if (child.exitCode === null && child.signalCode === null) await Promise.allSettled([
    capture("failure"), writeFile(join(output, "remaining-processes.json"), JSON.stringify(descendants(), null, 2)),
    readFile(configPath).then((value) => writeFile(join(output, "failure.config.toml"), value)),
  ]);
} finally {
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
console.log(`${report.status}; visual review ${report.visual_review}: ${join(output, "report.json")}`);
if (failure) throw failure;
