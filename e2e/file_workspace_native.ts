/** Production file-workspace View in a dedicated native component fixture.
 * This run proves real Metal rendering and public synthetic Harness events.
 * It deliberately does not claim filesystem, SFTP, main-app or physical-input acceptance.
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createHash } from "node:crypto";
import { copyFile, mkdir, mkdtemp, open, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { waitForServerReady, waitFor, query, resizeWindow, screenshot, scrollAt, sleep } from "../vendor/zenit/e2e/client.ts";

const options: Record<string, string> = {}, args = process.argv.slice(2);
for (let i = 0; i < args.length; i += 2) {
  assert(["--binary", "--out", "--theme"].includes(args[i]) && args[i + 1], `Invalid option ${args[i]}`);
  options[args[i]] = args[i + 1];
}
assert(options["--binary"] && options["--out"], "--binary component-fixture and --out are required");
const output = resolve(options["--out"]), sourceBinary = resolve(options["--binary"]);
// `--theme light|dark` (file_workspace_native_fixture.zig `--theme=`, default dark).
const theme = options["--theme"] ?? "dark"; assert(["light", "dark"].includes(theme), `theme ${theme}`);
await mkdir(output, { recursive: true });
const binary = join(output, "file-workspace-fixture-frozen");
await copyFile(sourceBinary, binary);
const report: Record<string, any> = {
  status: "running", started_at: new Date().toISOString(), source_binary: sourceBinary, binary,
  binary_sha256: createHash("sha256").update(await readFile(binary)).digest("hex"), stages: [], checks: [], runs: [],
  scope: "Independent production-View component fixture; no actual directory-service or main-application wiring",
  limits: ["All data are explicit bounded UI fixtures, not filesystem or remote directory results.",
    "Background native-window screenshots and synthetic Harness input do not establish physical input/IME correctness.",
    "The component is captured at the Figma workspace rectangle size; application chrome is outside this fixture.",
    "Own-process SIGTERM cleanup is separate from normal application close lifecycle evidence."],
};
function shown(n: any): boolean { return !!n?.rect && n.hidden !== true && n.visible !== false && (n.effective_opacity ?? 1) > 0 && n.rect.w > 0 && n.rect.h > 0; }
function flatten(n: any): any[] { return !n || n.hidden === true || n.visible === false ? [] : [n, ...(n.children ?? []).flatMap(flatten)]; }
async function visible(id: string): Promise<any> { return waitFor(async () => (await query(id)).find(shown) ?? null, 20000); }
async function capture(name: string): Promise<Record<string, any>> {
  await sleep(120);
  const nodes = Object.fromEntries(await Promise.all(["files.workspace", "files.local", "files.remote", "files.breadcrumb", "files.rows", "files.data_clip", "files.columns", "files.error", "files.transfer", "files.new_folder"].map(async id => [id, await query(id)])));
  const path = join(output, `${name}.png`);
  assert((await screenshot(path)).ok, `Native capture ${name}`);
  await writeFile(join(output, `${name}.tree.json`), JSON.stringify(nodes["files.workspace"], null, 2));
  await writeFile(join(output, `${name}.queries.json`), JSON.stringify(nodes, null, 2));
  report.stages.push({ name, at: new Date().toISOString(), screenshot: path, tree: join(output, `${name}.tree.json`) });
  return nodes;
}
async function run(state: "normal" | "empty" | "failed", inspect: () => Promise<void>): Promise<void> {
  const isolated = await mkdtemp(join(tmpdir(), "zerowork-files-fixture-")), rpc = join(isolated, "rpc");
  await mkdir(rpc);
  process.env.ZENIT_E2E_FILE_RPC_DIR = rpc;
  const log = await open(join(output, `${state}.app.log`), "w");
  const child = spawn(binary, [`--state=${state}`, `--theme=${theme}`], { cwd: process.cwd(), env: {
    ...process.env, ZENIT_E2E_FILE_RPC_DIR: rpc, ZENIT_E2E_BACKGROUND: "1", ZENIT_E2E_ISOLATE_POINTER: "1",
  }, stdio: ["ignore", log.fd, log.fd] });
  const ended = new Promise<void>(done => child.once("close", () => done()));
  const record: Record<string, any> = { state, pid: child.pid, isolated };
  report.runs.push(record);
  try {
    await waitForServerReady();
    const owner = JSON.parse(await readFile(join(rpc, "owner.json"), "utf8"));
    assert.equal(Number(owner.pid), child.pid, "Only this owned background fixture may receive input");
    await visible("files.workspace");
    await inspect();
  } catch (error) {
    record.error = String(error);
    if (child.exitCode === null && child.signalCode === null) {
      try { await capture(`failure-${state}`); } catch (captureError) { record.capture_error = String(captureError); }
    }
    throw error;
  } finally {
    if (child.exitCode === null && child.signalCode === null) child.kill("SIGTERM");
    await Promise.race([ended, sleep(2000)]);
    if (child.exitCode === null && child.signalCode === null) { child.kill("SIGKILL"); await ended; }
    record.cleanup = { exit_code: child.exitCode, signal: child.signalCode };
    await log.close();
  }
}
let failure: unknown;
try {
  await run("normal", async () => {
    assert((await resizeWindow(1194, 794)).ok);
    const normal = await capture("00-normal-wide");
    const left = normal["files.local"].find(shown), right = normal["files.remote"].find(shown);
    // Island B v3（e1372d88，features/files/view/styles.yss `root`）：工作区内边距 4、两栏间距 4（原先是 12 / 6）。
    const INSET = 4, GAP = 4, near = (a: number, b: number) => Math.abs(a - b) < 0.6;
    assert.equal(left.rect.x, INSET); assert.equal(left.rect.y, INSET);
    assert(near(left.rect.h, 794 - 2 * INSET)); assert.equal(right.rect.y, left.rect.y); assert(near(right.rect.h, left.rect.h));
    assert(near(right.rect.x - left.rect.x - left.rect.w, GAP), "panes are 4 apart");
    assert(near(right.rect.x + right.rect.w, 1194 - INSET), "panes fill the workspace width");
    // 两栏等宽：两侧的 `column_stack` 都是 `flex: 1; flex-basis: 0`（src/features/files/view/styles.yss），所以各占
    // (1194 - 2×4 - 4) / 2 = 591，与各自内容的宽度无关。（basis 取默认的 auto 时两栏会相差内容宽度之差：583.4 / 598.6。）
    assert(near(left.rect.w, right.rect.w), `file panes are equal width: local ${left.rect.w} vs remote ${right.rect.w}`);
    assert(near(left.rect.w, (1194 - 2 * INSET - GAP) / 2), `each file pane takes half of the workspace: ${left.rect.w}`);
    assert(flatten(left).filter(n => n.test_id === "files.row" && shown(n)).length > 0, "Actual native file rows");
    report.checks.push("Native wide cards fill the workspace inside its 4 point inset with a 4 point gap; production file rows render");
    // File names stay inside their name column (files.row.drag: the name cell, 4 point right padding — file_workspace_view.zig
    // `row.name_cell`): the filled native Tooltip trigger (zenit `Tooltip.fill`) hands the label the cell's width, so a
    // long name ellipsizes (S.filename `text_overflow = .ellipsis`) instead of keeping its content width and being cut
    // off against the size column (before: label 382 wide in a 245 cell).
    for (const pane of [left, right]) for (const row of flatten(pane).filter(n => n.test_id === "files.row" && shown(n))) {
      const cell = flatten(row).find(n => n.test_id === "files.row.drag"), name = flatten(row).find(n => n.test_id === "files.row.name");
      assert(cell && name, "every file row has its name cell and name");
      assert(name.rect.x >= cell.rect.x - 0.5 && name.rect.x + name.rect.w <= cell.rect.x + cell.rect.w - 4 + 0.5, `file name ${JSON.stringify(name.text)} stays inside its column: name ${name.rect.x}+${name.rect.w}, cell ${cell.rect.x}+${cell.rect.w}`);
    }
    const longName = flatten(left).find(n => n.test_id === "files.row.name" && String(n.text ?? "").startsWith("deployment-fixture-with-a-long-name"));
    assert(longName, "the long-name fixture row is on screen");
    report.checks.push("File names stay inside their name column; the long fixture name is ellipsized within it");
    assert((await resizeWindow(790, 374)).ok);
    const compact = await capture("01-normal-compact");
    const compactLeft = compact["files.local"].find(shown);
    const compactRight = compact["files.remote"].find(shown);
    assert.equal(compactLeft.rect.x, 4); assert.equal(compactLeft.rect.y, 4);
    assert(Math.abs(compactLeft.rect.h - (374 - 8)) < 0.6); assert(Math.abs(compactRight.rect.x + compactRight.rect.w - (790 - 4)) < 0.6);
    const bodies = compact["files.rows"].filter(shown), columns = compact["files.columns"].filter(shown);
    const clips = compact["files.data_clip"].filter(shown);
    // 列头与行一样左右各缩进 6（file_workspace_styles.row_inset），两栏的数据区等高。
    assert(Math.abs(columns[0].rect.w - (compactLeft.rect.w - 12)) < 0.6); assert(Math.abs(columns[1].rect.w - (compactRight.rect.w - 12)) < 0.6);
    assert(clips[0].rect.h > 0 && Math.abs(clips[0].rect.h - clips[1].rect.h) < 0.6);
    assert.equal(clips[0].rect.y + clips[0].rect.h, bodies[0].rect.y + bodies[0].rect.h);
    const x = bodies[0].rect.x + 60, y = bodies[0].rect.y + 45;
    assert((await scrollAt(x, y, -1000, -200)).ok);
    const scrolled = await capture("02-compact-left-scrolled");
    const moved = scrolled["files.columns"].filter(shown);
    assert.equal(moved[0].rect.x, columns[0].rect.x, "Compact columns fit without horizontal drift");
    assert.equal(moved[1].rect.x, columns[1].rect.x, "Right card scroll remains independent");
    assert.equal(scrolled["files.breadcrumb"].filter(shown)[0].rect.y, compact["files.breadcrumb"].filter(shown)[0].rect.y);
    report.checks.push("Compact cards keep the 4 point inset, their columns span the card, hide the date column and retain fixed headers and paths while rows scroll");
  });
  await run("empty", async () => {
    const nodes = await capture("03-empty-remote");
    const remote = nodes["files.remote"].find(shown), all = flatten(remote);
    assert(all.some(n => n.text === "目录为空" && shown(n)));
    assert.equal(all.filter(n => n.test_id === "files.row" && shown(n)).length, 0);
    assert.equal(nodes["files.error"].filter(shown).length, 0);
    report.checks.push("Actual native empty remote has zero rows and a distinct empty state without error");
  });
  await run("failed", async () => {
    const nodes = await capture("04-failed-stale-remote");
    const remote = nodes["files.remote"].find(shown), all = flatten(remote);
    assert(all.some(n => n.test_id === "files.row" && shown(n)), "Original rows remain after read failure");
    const error = nodes["files.error"].find(shown);
    // 恢复区高度随内容（错误文案 + “上次列表 · 已过期” + 恢复按钮行，file_workspace_styles.errorBox 是 fit），不是固定的 68：
    // 要求它是一条紧凑的区域、完整落在远程卡片内。
    assert(error.rect.h > 40 && error.rect.h < 100 && error.rect.y >= remote.rect.y && error.rect.y + error.rect.h <= remote.rect.y + remote.rect.h + 0.6, `recovery region ${JSON.stringify(error.rect)}`);
    assert(flatten(error).some(n => (n.text ?? "").includes("Connection lost")));
    report.checks.push("Actual native failed remote preserves old rows and renders the compact Connection lost recovery region inside the remote card");
  });
  report.status = "passed";
} catch (error) { failure = error; report.status = "failed"; report.error = String(error); }
finally { report.finished_at = new Date().toISOString(); await writeFile(join(output, "report.json"), JSON.stringify(report, null, 2)); }
console.log(`${report.status}: ${join(output, "report.json")}`);
if (failure) throw failure;
