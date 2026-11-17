/**
 * Full settings window in the isolated settings preview runner (F-set-preview;
 * docs/ui-revamp/YIX_SPIKE.md V-6 / V-7 / V-11). Read-only: in-memory default
 * config, isolated HOME and RPC dir per launch, background windows, no pointer.
 *
 *   zig build settings-preview -Dtest-mode=true [--prefix DIR]
 *   node e2e/settings_preview_windows_native.ts [--binary BIN] [--out DIR] [--label yix] [--parts selfcheck,geometry,v6]
 *
 * - selfcheck: runs the runner's in-process checks (`--self-check=v7`, `--self-check=v11`)
 *   and requires every PASS/FAIL line to be PASS.
 * - geometry (V-11): the settings window frame under the production window chrome: node rects against the
 *   design contract (window 960 × 780, navigation island, title row and page header centred on the traffic lights);
 *   minimum-size clamp after a Harness resize.
 * - v6: focus / text / mount behavior when the category changes while an input holds focus, uncommitted
 *   text or a (Harness-injected) IME composition. `--label` only names the report (the legacy view implementation was removed in P3 3f).
 * Harness input never goes through the macOS input method, a real window drag, the traffic lights or a
 * titlebar double-click; those stay manual (see YIX_SPIKE.md).
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from "node:assert/strict";
import { spawn, type ChildProcess } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdir, mkdtemp, open, readFile, realpath, rm, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import * as h from "../vendor/zenit/e2e/client.ts";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const args = process.argv.slice(2);
const options: Record<string, string> = {};
for (let index = 0; index < args.length; index += 2) {
  if (!["--out", "--binary", "--label", "--parts"].includes(args[index]) || !args[index + 1]) throw new Error(`Invalid option ${args[index]}`);
  options[args[index]] = args[index + 1];
}
const binary = resolve(options["--binary"] ?? join(root, "zig-out/bin/settings-preview-runner"));
const output = resolve(options["--out"] ?? join(root, `dist/ui-acceptance/settings-preview-windows-${Date.now()}`));
const label = options["--label"] ?? "yix";
const parts = new Set((options["--parts"] ?? "plugins,selfcheck,geometry,v6").split(","));
await mkdir(output, { recursive: true });

const report = {
  scope: "settings preview runner, full settings window (aux-window path); read-only; Harness input only",
  entry_point: "src/features/settings/preview/settings_preview_runner.zig",
  binary,
  binary_sha256: createHash("sha256").update(await readFile(binary)).digest("hex"),
  label,
  selfcheck: [] as Record<string, unknown>[],
  geometry: {} as Record<string, unknown>,
  v6: [] as Record<string, unknown>[],
  status: "running",
  error: undefined as string | undefined,
};
const log = (line: string) => console.log(line);

// ── process management ──
type Run = { child: ChildProcess; ended: Promise<number | null>; dir: string; logPath: string };
async function launch(name: string, runnerArgs: string[]): Promise<Run> {
  const dir = await realpath(await mkdtemp("/private/tmp/zw-settings-preview-win-"));
  process.env.ZENIT_E2E_FILE_RPC_DIR = dir;
  const logPath = join(output, `${name}.log`);
  const file = await open(logPath, "w");
  const child = spawn(binary, runnerArgs, {
    cwd: dir,
    env: { ...process.env, HOME: dir, CFFIXED_USER_HOME: dir, ZENIT_E2E_FILE_RPC_DIR: dir, ZENIT_E2E_ISOLATE_POINTER: "1", ZENIT_E2E_BACKGROUND: "1" },
    stdio: ["ignore", file.fd, file.fd],
  });
  const ended = new Promise<number | null>(done => child.once("close", code => { void file.close(); done(code); }));
  return { child, ended, dir, logPath };
}
async function stop(run: Run) {
  if (run.child.exitCode === null && run.child.signalCode === null) run.child.kill("SIGTERM");
  await run.ended;
  await rm(run.dir, { recursive: true, force: true });
}
async function withTimeout<T>(promise: Promise<T>, ms: number, what: string): Promise<T> {
  let timer: NodeJS.Timeout | undefined;
  const timeout = new Promise<never>((_, reject) => { timer = setTimeout(() => reject(new Error(`timeout: ${what}`)), ms); });
  try { return await Promise.race([promise, timeout]); } finally { clearTimeout(timer); }
}

// ── tree helpers ──
type Node = h.QueryNode & { effective_opacity?: number };
const shown = (n: Node | undefined) => !!n && n.visible !== false && n.rect.w > 0 && n.rect.h > 0 && (n.effective_opacity ?? 1) > 0;
const node = (id: string, ms = 10000) => h.waitFor(async () => ((await h.query(id)) as Node[]).find(shown) ?? null, ms);
const count = async (id: string) => ((await h.query(id)) as Node[]).filter(shown).length;
const textOf = (n: Node | undefined): string => [n?.text ?? "", ...(n?.children ?? []).map(c => textOf(c as Node))].join("");
const title = async () => textOf((await h.query("settings.page.title"))[0] as Node);
const waitTitle = (expected: string, ms = 8000) => h.waitFor(async () => ((await title()) === expected ? true : null), ms);
async function click(id: string) {
  const target = await node(id);
  await h.clickAt(target.rect.x + target.rect.w / 2, target.rect.y + target.rect.h / 2);
  await h.sleep(150);
}
/** The focused node and its nearest ancestor with a test id. */
async function focusInfo() {
  const focused = await h.focused();
  if (!focused || focused.id === undefined) return { id: null, owner: null, tag: null };
  const tree = (await h.tree()) as Node;
  const path: Node[] = [];
  const find = (n: Node): boolean => {
    path.push(n);
    if (n.id === focused.id) return true;
    for (const child of n.children ?? []) if (find(child as Node)) return true;
    path.pop();
    return false;
  };
  find(tree);
  const owner = [...path].reverse().find(n => n.test_id)?.test_id ?? null;
  return { id: focused.id, owner, tag: focused.tag ?? null };
}
async function buffer(id: string) {
  try { const state = await h.inputState(id); return { buffer: state.buffer, ime_preedit_len: state.ime_preedit_len, ime_phase: state.ime_phase }; } catch (error) { return { error: String(error) }; }
}

// ── parts ──
async function selfcheck() {
  for (const [name, runnerArgs] of [["v7", ["--self-check=v7"]], ["v11", ["--self-check=v11"]]] as const) {
    const run = await launch(`selfcheck-${name}`, [...runnerArgs]);
    const code = await withTimeout(run.ended, 120000, name).catch(async error => { await stop(run); throw error; });
    await rm(run.dir, { recursive: true, force: true });
    const lines = (await readFile(run.logPath, "utf8")).split("\n").filter(line => /^(PASS|FAIL|INFO|SELF-CHECK) /.test(line));
    const failed = lines.filter(line => line.startsWith("FAIL "));
    const passed = lines.filter(line => line.startsWith("PASS "));
    report.selfcheck.push({ name, exit: code, passed: passed.length, failed: failed.length, lines });
    for (const line of lines) log(`[${name}] ${line}`);
    assert.equal(code, 0, `${name}: self-check exit code`);
    assert.equal(failed.length, 0, `${name}: ${failed.join(" | ")}`);
    assert(passed.length > 0, `${name}: no PASS lines`);
  }
}

const geometryIds = ["settings.window", "settings.panel", "settings.navigation", "settings.header", "settings.header.traffic_lights", "settings.search", "settings.island", "settings.content", "settings.page.intro", "settings.page.title", "settings.history.back", "settings.history.forward", "settings.help", "settings.viewport", "settings.field.keepalive_sec"];
async function geometry() {
  const run = await launch("geometry", ["--page=ssh", "--sub=0", "--theme=light"]);
  let rects: Record<string, Rect | null> = {}, min: Rect | null = null;
  try {
    await h.waitForServerReady();
    await waitTitle("连接");
    await node("settings.field.keepalive_sec");
    await h.sleep(400);
    for (const id of geometryIds) rects[id] = ((await h.query(id)) as Node[]).find(shown)?.rect ?? null;
    assert((await h.screenshot(join(output, "geometry.png"))).ok, "screenshot");
    // Minimum size: a Harness resize below 760 × 480 must clamp.
    await h.resizeWindow(600, 400);
    await h.sleep(500);
    min = ((await h.query("settings.window")) as Node[])[0]?.rect ?? null;
    await h.screenshot(join(output, "geometry-min.png"));
  } finally { await stop(run); }
  report.geometry = { rects, min_size: min };
  log(`[geometry] ${JSON.stringify(report.geometry)}`);
  const missing = geometryIds.filter(id => !rects[id]);
  assert.deepEqual(missing, [], "settings window nodes missing");
  // Window frame contract (settings_shell.window, Pencil p6ZVS): 960 × 780; the navigation island is 216 wide, 8 from the
  // window's left / top / bottom edges; its top row (traffic-light placeholder) and the floating page header (64 high from
  // the window top) are both centred on the traffic lights' y = 32.
  const win = rects["settings.window"]!, nav = rects["settings.navigation"]!, top = rects["settings.header"]!, lights = rects["settings.header.traffic_lights"]!, intro = rects["settings.page.intro"]!;
  assert.deepEqual([win.x, win.y, win.w, win.h], [0, 0, 960, 780], "settings.window");
  assert.deepEqual([nav.x, nav.y, nav.w, nav.h], [8, 8, 216, 764], "settings.navigation");
  assert.equal(top.y + top.h / 2, 32, "navigation top row centre");
  assert.equal(lights.y + lights.h / 2, 32, "traffic-light placeholder centre");
  assert.deepEqual([lights.x, lights.w], [22, 52], "traffic-light placeholder: starts 6 before the first light's centre (28), 52 wide");
  assert.deepEqual([intro.y, intro.h], [0, 64], "page header");
  assert.equal(intro.y + intro.h / 2, 32, "page header centre");
  assert(min && min.w >= 760 && min.h >= 480, `minimum size not enforced ${JSON.stringify(min)}`);
}

async function v6() {
  const scenario = async (name: string, body: (record: Record<string, unknown>) => Promise<void>) => {
    const run = await launch(`v6-${label}-${name}`, ["--page=ssh", "--sub=0", "--theme=light"]);
    const record: Record<string, unknown> = { name, label };
    report.v6.push(record);
    try {
      await h.waitForServerReady();
      await waitTitle("连接");
      await node("settings.field.keepalive_sec");
      await body(record);
      record.alive = run.child.exitCode === null;
      assert(record.alive, "runner exited");
      record.status = "passed";
    } catch (error) {
      record.status = "failed";
      record.error = String((error as Error)?.stack ?? error);
      await h.screenshot(join(output, `v6-${label}-${name}-failed.png`)).catch(() => undefined);
      throw error;
    } finally {
      await stop(run);
      log(`[v6:${label}] ${JSON.stringify(record)}`);
    }
  };
  const mounts = async () => ({ content: await count("settings.content"), search: await count("settings.search"), field: await count("settings.field.keepalive_sec"), navigation: await count("settings.navigation") });

  // 1. Uncommitted text in a field, then a category switch, then Back.
  await scenario("field-then-category", async record => {
    await click("settings.field.keepalive_sec");
    await h.key("a", { cmd: true });
    await h.type_("47");
    await h.sleep(200);
    record.before = { focus: await focusInfo(), field: await buffer("settings.field.keepalive_sec"), footer: textOf((await h.query("settings.footer.state"))[0] as Node), mounts: await mounts() };
    // H-save: the draft belongs to this subpage; leaving it asks first (native Modal, focus on 继续编辑),
    // and 继续编辑 keeps the page, the typed text and one content page.
    await click("settings.nav.transfer");
    await h.waitFor(async () => (await h.query("settings.confirmation")).some(n => shown(n as Node)) || null, 8000);
    await h.sleep(300);
    record.asked = { title: await title(), focus: await focusInfo(), footer: textOf((await h.query("settings.footer.state"))[0] as Node), mounts: await mounts() };
    assert.equal((record.asked as { title: string }).title, "连接", "the switch waits for the decision");
    await click("settings.confirmation.cancel");
    await h.waitFor(async () => !(await h.query("settings.confirmation")).some(n => shown(n as Node)) || null, 8000);
    await h.sleep(300);
    record.after_cancel = { title: await title(), focus: await focusInfo(), field: await buffer("settings.field.keepalive_sec"), mounts: await mounts() };
    const after = record.after_cancel as { title: string; field: { buffer?: string }; mounts: { content: number } };
    assert.equal(after.title, "连接", "继续编辑 stays on the subpage");
    assert.equal(after.field.buffer, "47", "typed text is kept in the draft");
    assert.equal(after.mounts.content, 1, "one content page after the dialog");
  });

  // 2. Typing keeps focus and text while the Save Bar follows the draft (same page re-render).
  await scenario("typing-stays-focused", async record => {
    await click("settings.field.keepalive_sec");
    await h.key("a", { cmd: true });
    const steps: unknown[] = [];
    for (const ch of ["4", "6"]) {
      await h.type_(ch);
      await h.sleep(250);
      steps.push({ focus: await focusInfo(), field: await buffer("settings.field.keepalive_sec"), footer: textOf((await h.query("settings.footer.state"))[0] as Node), mounts: await mounts() });
    }
    record.steps = steps;
    const last = steps.at(-1) as { focus: { owner: string | null }; field: { buffer?: string } };
    assert.equal(last.field.buffer, "46", "both keystrokes landed");
    assert.equal(last.focus.owner, "settings.field.keepalive_sec", "focus stays in the field while the draft changes");
  });

  // 3. Harness IME composition in a field, then a category switch, then commit.
  await scenario("ime-then-category", async record => {
    await click("settings.field.keepalive_sec");
    await h.key("a", { cmd: true });
    await h.imePreedit("12", 2);
    await h.sleep(200);
    record.composing = { focus: await focusInfo(), field: await buffer("settings.field.keepalive_sec"), title: await title() };
    await click("settings.nav.transfer");
    await h.sleep(600);
    record.after_switch_while_composing = { title: await title(), focus: await focusInfo(), field: await buffer("settings.field.keepalive_sec"), mounts: await mounts() };
    await h.imeCommit("12");
    await h.sleep(600);
    record.after_commit = { title: await title(), focus: await focusInfo(), field: await buffer("settings.field.keepalive_sec"), mounts: await mounts() };
    if ((await title()) === "文件传输") {
      await click("settings.history.back");
      await waitTitle("连接").catch(() => undefined);
      await h.sleep(300);
      record.after_back = { title: await title(), field: await buffer("settings.field.keepalive_sec"), mounts: await mounts() };
    }
  });

  // 4. Uncommitted text in the search field, then a category switch (navigation clears search by design).
  await scenario("search-then-category", async record => {
    await click("settings.search");
    await h.type_("超时");
    await waitTitle("搜索结果");
    await h.sleep(200);
    record.searching = { focus: await focusInfo(), search: await buffer("settings.search"), mounts: await mounts() };
    await click("settings.nav.transfer");
    await waitTitle("文件传输");
    await h.sleep(300);
    record.after_switch = { focus: await focusInfo(), search: await buffer("settings.search"), mounts: await mounts() };
    const after = record.after_switch as { search: { buffer?: string }; mounts: { search: number } };
    assert.equal(after.search.buffer, "", "navigation clears the search field");
    assert.equal(after.mounts.search, 1, "one search field");
  });

  // 5. Search field keeps focus and text while results re-render on each keystroke.
  await scenario("search-typing", async record => {
    await click("settings.search");
    const steps: unknown[] = [];
    for (const text of ["保", "活"]) {
      await h.type_(text);
      await h.sleep(300);
      steps.push({ title: await title(), focus: await focusInfo(), search: await buffer("settings.search"), mounts: await mounts() });
    }
    record.steps = steps;
    const last = steps.at(-1) as { focus: { owner: string | null }; search: { buffer?: string } };
    assert.equal(last.search.buffer, "保活");
    assert.equal(last.focus.owner, "settings.search", "focus stays in the search field across result re-renders");
  });
}

/** `--plugin-fixture`: metadata-only manifests make the plugin page non-empty (no factory, no loading). */
async function pluginFixture() {
  const run = await launch("plugin-fixture", ["--page=plugins", "--plugin-fixture", "--theme=light"]);
  try {
    await h.waitForServerReady();
    await waitTitle("协议插件");
    await node("settings.plugins");
    await h.sleep(300);
    const text = textOf((await h.tree()) as Node);
    const listed = ["预览夹具 · 终端", "预览夹具 · 内容页"].filter(name => text.includes(name));
    assert((await h.screenshot(join(output, "plugin-fixture.png"))).ok, "screenshot");
    (report.geometry as Record<string, unknown>).plugin_fixture = { listed, empty_notice: text.includes("没有已注册的插件") };
    log(`[plugin-fixture] ${JSON.stringify((report.geometry as Record<string, unknown>).plugin_fixture)}`);
    assert.equal(listed.length, 2, "both fixture manifests are listed");
  } finally { await stop(run); }
}

try {
  if (parts.has("plugins")) await pluginFixture();
  if (parts.has("selfcheck")) await selfcheck();
  if (parts.has("geometry")) await geometry();
  if (parts.has("v6")) await v6();
  report.status = "passed";
} catch (error) {
  report.status = "failed";
  report.error = String((error as Error)?.stack ?? error);
  process.exitCode = 1;
} finally {
  await writeFile(join(output, `report-${label}.json`), JSON.stringify(report, null, 2));
  console.log(JSON.stringify({ status: report.status, label, output, error: report.error }));
}
