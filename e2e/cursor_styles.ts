/** Save real Local cursor styles through production settings and capture Metal.
 * node e2e/cursor_styles.ts --out DIR [--binary PATH]
 * Uses an existing test-mode binary and isolated background Harness/data.
 * No native GUI, OS preference change, build, or test-only production entry.
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
import { waitForServerReady, waitFor, query, clickTestId, key, type_, resizeWindow, screenshot, sleep, type QueryNode } from "../zig-out/share/zenit/harness/client.ts";
import { decodePng } from "../vendor/zenit/e2e/png.ts";
import { settingsNav, clickLabel } from "./settings_nav.ts";
const nav = settingsNav();
// Cursor shape is a native Tabs (settings.field.cursor_style) on 外观与主题 › 字体与排版; its items have no own test id.
const cursorLabel: Record<string, string> = { block: "方块", bar: "竖线", underline: "下划线" };

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const args = process.argv.slice(2), options: Record<string, string> = {};
for (let i = 0; i < args.length; i += 2) {
  assert(["--binary", "--out"].includes(args[i]) && args[i + 1], `Invalid option ${args[i]}`);
  options[args[i]] = args[i + 1];
}
assert(options["--out"], "--out is required");
const output = resolve(options["--out"]), binary = resolve(options["--binary"] ?? join(root, "zig-out/bin/zerowork"));
const binaryHash = createHash("sha256").update(await readFile(binary)).digest("hex");
const isolated = await mkdtemp(join(tmpdir(), "zerowork-cursor-ui-"));
const rpc = join(isolated, "rpc"), data = join(isolated, "data"), release = join(isolated, "producer.release");
await Promise.all([mkdir(output, { recursive: true }), mkdir(rpc), mkdir(data)]);
const configPath = join(data, "config.toml");
const baseline = `[meta]
config_revision = 1
[ui]
theme = "dark"
font_family = "Menlo"
font_size = 14
font_weight = "regular"
line_height = 1.5714285714285714
cursor_style = "block"
timestamp_gutter = false
input_line_highlight = false
[completion]
enabled = false
`;
await writeFile(configPath, baseline);
await writeFile(join(output, "config-before.toml"), baseline);
const marker = "CURSOR_STYLE_";
const quote = (value: string): string => `'${value.replaceAll("'", "'\\''")}'`;
const producerPath = join(isolated, "producer.zsh");
// Only the owned PTY is affected: cursor blink off, visible, clean primary
// screen with a known insertion point. The OS reduce-motion setting is untouched.
const payload = "\x1b[0m\x1b[?1049l\x1b[?12l\x1b[?25h\x1b[3J\x1b[2J\x1b[H" + marker;
const producer = `#!/bin/zsh\nset -eu\nprintf '%s' ${quote(payload)}\nwhile [[ ! -e ${quote(release)} ]]; do /bin/sleep 0.1; done\n`;
await writeFile(producerPath, producer);
await writeFile(join(output, "producer.zsh"), producer);
process.env.ZENIT_E2E_FILE_RPC_DIR = rpc;
const log = await open(join(output, "app.log"), "w");
const child = spawn(binary, [], { cwd: root, env: {
  ...process.env, ZENIT_E2E_FILE_RPC_DIR: rpc, ZENIT_E2E_ISOLATE_POINTER: "1", ZENIT_E2E_BACKGROUND: "1",
  ZEROWORK_DATA_DIR: data, ZEROWORK_AUTOCONNECT: "0",
}, stdio: ["ignore", log.fd, log.fd] });
const ended = new Promise<void>((done) => child.once("close", () => done()));
let launchError: Error | undefined;
child.once("error", (error) => { launchError = error; });
const report: Record<string, unknown> = {
  status: "running", binary, binary_sha256: binaryHash, pid: child.pid, started_at: new Date().toISOString(),
  isolation: { rpc, data, background: true }, checks: [], captures: [], geometries: [], visual_review: "pending",
  expected_geometry: {
    source: "V0.1.2 §7.1 saved cursor styles; TerminalSurface.renderCaret uses bar width 2pt and underline height 2pt at the row bottom. Other axis keeps the actual cell width / 14pt × 11/7 = 22pt row height.",
    fixture: { text: marker, row: 0, cursor_column: marker.length, font: "Menlo 14 regular", row_height: 22, window: [1440, 900] },
  },
  limits: [
    "Public Harness input verifies application wiring; no physical key, native IME or OS preference claim.",
    "The query is the small terminal.surface subtree for a one-row fixture, never the complete app tree.",
    "Functional geometry/config checks and screenshot visual review are recorded separately.",
    "The public macOS Harness has no native-window-close endpoint; own-process termination is cleanup, not normal app shutdown proof.",
  ],
};
const checks = report.checks as string[];
type Node = QueryNode & { hidden?: boolean; effective_opacity?: number };
type Style = "block" | "bar" | "underline";
function shown(node: Node): boolean {
  return node.hidden !== true && node.visible !== false && (node.effective_opacity ?? 1) > 0 && node.rect.w > 0 && node.rect.h > 0;
}
async function visible(id: string): Promise<Node> {
  return waitFor(async () => (await query(id)).find(shown) ?? null);
}
async function hidden(id: string): Promise<void> {
  await waitFor(async () => !(await query(id)).some(shown) || null);
}
async function click(id: string): Promise<void> {
  await visible(id);
  assert((await clickTestId(id)).ok, `Click ${id}`);
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
function text(node: Node): string {
  if (!shown(node)) return "";
  return (node.text ?? "") + (node.children ?? []).map(text).join("");
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
function near(actual: number, expected: number, label: string): void {
  assert(Math.abs(actual - expected) <= 0.15, `${label}: expected ${expected}, actual ${actual}`);
}
let caretId: number | undefined;
async function geometry(style: Style): Promise<Record<string, unknown>> {
  return waitFor(async () => {
    const surface = await visible("terminal.surface"), row = await visible("terminal.surface.row.0");
    assert.equal(text(row), marker, "The same real PTY output must survive every settings save");
    const glyphs = (row.children ?? []).filter((node) => shown(node) && node.text && node.text.trim().length > 0);
    assert.equal(glyphs.map((node) => node.text).join(""), marker);
    assert(glyphs.length > 0);
    const caret = (await query("terminal.surface.caret")).find(shown);
    assert(caret && caret.tag === "box" && (caret.children?.length ?? 0) === 0, "Expected the public Surface caret leaf");
    assert(caret.rect.x >= surface.rect.x && caret.rect.x + caret.rect.w <= surface.rect.x + surface.rect.w);
    if (!shown(caret)) return null;
    if (caretId === undefined) caretId = caret.id;
    assert.equal(caret.id, caretId, "Saving appearance must retain the Local caret/client node");
    // TerminalSurface may merge adjacent cells with the same styling into one span.
    const cellWidth = glyphs.reduce((width, glyph) => width + glyph.rect.w, 0) / marker.length;
    const rowHeight = row.rect.h;
    near(rowHeight, 22, "Actual default row height");
    near(caret.rect.x, glyphs[0].rect.x + marker.length * cellWidth, "Caret column");
    near(caret.rect.y, row.rect.y + (style === "underline" ? rowHeight - 2 : 0), "Caret row/bottom alignment");
    near(caret.rect.w, style === "bar" ? 2 : cellWidth, "Caret width");
    near(caret.rect.h, style === "underline" ? 2 : rowHeight, "Caret height");
    return { style, caret, row: { id: row.id, rect: row.rect }, cell_width: cellWidth, row_height: rowHeight };
  });
}
async function capture(name: string, observed: Record<string, unknown>): Promise<void> {
  const path = join(output, `${name}.png`);
  const painted = await waitFor(async () => {
    assert((await screenshot(path)).ok, `Screenshot ${name}`);
    return caretPixels(path, observed);
  }, 3000);
  observed.painted_caret = painted;
  await writeFile(join(output, `${name}.geometry.json`), JSON.stringify(observed, null, 2));
  await writeFile(join(output, `${name}.queries.json`), JSON.stringify({
    surface: await query("terminal.surface"), first_row: await query("terminal.surface.row.0"), tabs: await query("tabs.strip"),
  }, null, 2));
  (report.captures as string[]).push(`${name}.png`);
  (report.geometries as Record<string, unknown>[]).push(observed);
}
function caretPixels(path: string, observed: Record<string, unknown>) {
  const image = decodePng(path), scale = image.width / 1440;
  const caret = (observed.caret as Node).rect;
  const row = observed.row as { rect: Node["rect"] };
  const rgb = (x: number, y: number) => {
    const offset = (y * image.width + x) * image.channels;
    return image.pixels.subarray(offset, offset + 3).join(",");
  };
  const ink = rgb(Math.floor((caret.x + caret.w / 2) * scale), Math.floor((caret.y + caret.h / 2) * scale));
  const background = rgb(Math.ceil((caret.x + 12) * scale), Math.floor((caret.y + caret.h / 2) * scale));
  if (ink === background) return null;
  const xs: number[] = [], ys: number[] = [];
  for (let y = Math.floor(row.rect.y * scale); y < Math.ceil((row.rect.y + row.rect.h) * scale); y++) {
    for (let x = Math.floor(caret.x * scale); x < Math.ceil((caret.x + 12) * scale); x++) {
      if (rgb(x, y) === ink) { xs.push(x); ys.push(y); }
    }
  }
  const painted = { x: Math.min(...xs), y: Math.min(...ys), w: Math.max(...xs) - Math.min(...xs) + 1, h: Math.max(...ys) - Math.min(...ys) + 1 };
  const matches = (["x", "y", "w", "h"] as const).every((axis) => Math.abs(painted[axis] - caret[axis] * scale) <= 2);
  return matches ? { ...painted, scale } : null;
}
let revision = 1;
async function saveStyle(style: Style): Promise<void> {
  await nav.toField("cursor_style");
  await clickLabel("settings.field.cursor_style", cursorLabel[style]);
  await waitFor(async () => (await nav.dirty()) || null);
  await click("settings.save");
  // Saved: the floating Save Bar hides (was the persistent footer state "已保存").
  await nav.saved();
  const saved = await readFile(configPath, "utf8");
  assert.equal(configValue(saved, "ui", "cursor_style"), style);
  const nextRevision = Number(configValue(saved, "meta", "config_revision"));
  assert(nextRevision > revision, "Each production save must publish a newer real config revision");
  revision = nextRevision;
  for (const [section, field, expected] of [
    ["ui", "theme", "dark"], ["ui", "font_family", "Menlo"], ["ui", "font_size", 14], ["ui", "font_weight", "regular"],
    ["ui", "timestamp_gutter", false], ["ui", "input_line_highlight", false], ["completion", "enabled", false],
  ] as const) assert.equal(configValue(saved, section, field), expected, `Unrelated ${section}.${field} stays unchanged`);
  near(Number(configValue(saved, "ui", "line_height")), 11 / 7, "Saved line-height precision");
  await writeFile(join(output, `config-${style}.toml`), saved);
  await nav.close();
  await hidden("settings.panel");
  await click("terminal.surface");
  await capture(`cursor-${style}`, await geometry(style));
  checks.push(`Production settings saved ${style} at revision ${revision}; actual Local caret geometry matched without rebuilding the node`);
}
let failure: unknown;
try {
  await waitForServerReady();
  const owner = JSON.parse(await readFile(join(rpc, "owner.json"), "utf8"));
  assert.equal(Number(owner.pid), child.pid, "The Harness must belong to this owned isolated process");
  assert((await resizeWindow(1440, 900)).ok);
  await click("workspace.empty.local");
  await visible("terminal.surface");
  const shell = await waitFor(async () => descendants().find((process) => /(^|\/)zsh$/.test(process.command)) ?? null);
  report.shell_pid = shell.pid;
  await type_(`/bin/zsh -df ${quote(producerPath)}`);
  await key("enter");
  await waitFor(async () => text(await visible("terminal.surface.row.0")) === marker || null);
  await capture("cursor-original-block", await geometry("block"));
  for (const style of ["bar", "underline", "block"] as const) {
    await saveStyle(style);
    assert(descendants().some((process) => process.pid === shell.pid), "Saving cursor style must not replace the real Local shell");
  }
  report.restored_original_cursor = true;
  checks.push("Original block style and unrelated original settings were restored through the same production Save entry");
  await writeFile(release, "finish\n");
  await sleep(250);
  await type_("exit");
  await key("enter");
  await waitFor(async () => !descendants().some((process) => process.pid === shell.pid) || null);
  await visible("local.ended.reconnect");
  assert.match(text(await visible("local.notice.detail")), /退出码 0/);
  await click("local.ended.close");
  await visible("workspace.empty.local");
  assert.equal(descendants().filter((process) => /(^|\/)(zsh|sleep)$/.test(process.command)).length, 0);
  report.local_shell_exit = "normal shell exit; captured original PID absent and closed tab returns to empty workspace";
  report.visual_review = "pixel_geometry_verified";
  report.status = "passed";
} catch (error) {
  failure = launchError ?? error;
  report.status = "failed";
  report.error = String(failure);
  if (child.exitCode === null && child.signalCode === null) await Promise.allSettled([
    screenshot(join(output, "failure.png")),
    writeFile(join(output, "remaining-processes.json"), JSON.stringify(descendants(), null, 2)),
    (async () => { await writeFile(join(output, "failure-queries.json"), JSON.stringify({
      settings: await query("settings.footer.state"), cursor: await query("settings.field.cursor_style"), surface: await query("terminal.surface"),
    }, null, 2)); })(),
  ]);
} finally {
  await writeFile(release, "finish\n");
  if (child.exitCode === null && child.signalCode === null) {
    const remaining = descendants();
    report.forced_child_cleanup = remaining.map((value) => value.pid);
    for (const value of remaining.reverse()) { try { process.kill(value.pid, "SIGHUP"); } catch (error) { if ((error as NodeJS.ErrnoException).code !== "ESRCH") throw error; } }
    child.kill("SIGTERM");
  }
  await Promise.race([ended, sleep(2000)]);
  if (child.exitCode === null && child.signalCode === null) { child.kill("SIGKILL"); await ended; }
  report.process_cleanup = { exit_code: child.exitCode, signal: child.signalCode, normal_app_shutdown: false };
  report.finished_at = new Date().toISOString();
  await writeFile(join(output, "report.json"), JSON.stringify(report, null, 2));
  await log.close();
  await rm(isolated, { recursive: true, force: true });
}
console.log(`${report.status}: ${join(output, "report.json")}`);
if (failure) throw failure;
