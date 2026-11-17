/** Real background window acceptance using the current installed Harness binary.
 * node e2e/tab_shortcuts.ts --out DIR [--fixture-dir DIR]
 * Uses only public Harness APIs. Harness has no key_up command, so physical
 * modifier release, window blur and real IME require separate CUA acceptance.
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createHash } from "node:crypto";
import { cp, mkdir, mkdtemp, open, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { waitForServerReady, waitFor, query, clickTestId, clickAt, mouseMove, key, resizeWindow, screenshot, stats, sleep } from "../zig-out/share/zenit/harness/client.ts";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const args = process.argv.slice(2), options: Record<string, string> = {};
for (let i = 0; i < args.length; i += 2) {
  assert(["--out", "--binary", "--fixture-dir"].includes(args[i]) && args[i + 1], `Invalid option ${args[i]}`);
  options[args[i]] = args[i + 1];
}
const binary = resolve(options["--binary"] ?? join(root, "zig-out/bin/zerowork"));
const output = resolve(options["--out"] ?? join(root, "dist/ui-acceptance/20261018/tab-shortcuts"));
const isolated = await mkdtemp(join(tmpdir(), "zerowork-tab-shortcuts-"));
// Fixture: one saved SSH connection to a refused loopback port and a 1 s connect timeout. Without
// --fixture-dir it is written into this run's private temporary directory (the former default under
// dist/ was never checked in).
let fixture = options["--fixture-dir"] ? resolve(options["--fixture-dir"]) : join(isolated, "fixture");
if (!options["--fixture-dir"]) {
  await mkdir(fixture);
  await writeFile(join(fixture, "config.toml"), "[meta]\nconfig_revision=1\n[ssh]\nconnect_timeout_sec=1\n[updates]\nauto_check=false\n");
  await writeFile(join(fixture, "hosts.toml"), '[registry]\nschema_version=2\nrevision=1\nnext_connection_id=2\nnext_group_id=1\n[[hosts]]\nconnection_id=1\nrevision=1\nprotocol="ssh"\nname="Refused local fixture"\nhost="127.0.0.1"\nport=1\nuser="fixture"\n');
}
const rpc = join(isolated, "rpc"), data = join(isolated, "data");
await mkdir(output, { recursive: true });
await mkdir(rpc); await cp(fixture, data, { recursive: true });
process.env.ZENIT_E2E_FILE_RPC_DIR = rpc;
const log = await open(join(output, "app.log"), "w");
const child = spawn(binary, [], { cwd: root, stdio: ["ignore", log.fd, log.fd], env: {
  ...process.env, ZENIT_E2E_FILE_RPC_DIR: rpc, ZEROWORK_DATA_DIR: data,
  ZENIT_E2E_BACKGROUND: "1", ZENIT_E2E_ISOLATE_POINTER: "1", ZEROWORK_AUTOCONNECT: "0",
} });
const ended = new Promise<void>((done) => child.once("close", () => done()));
const report: any = { started_at: new Date().toISOString(), binary, binary_sha256: createHash("sha256").update(await readFile(binary)).digest("hex"), pid: child.pid,
  storage: "isolated temporary data and file RPC", background: true, source: "src/main.zig", checks: [], status: "running",
  limits: ["Only public Harness APIs are used. Harness has no key_up command: physical modifier release, window blur, and real IME require separate CUA acceptance.", "Runner SIGTERM cleanup is not evidence of normal application shutdown."] };
type Node = any;
function flatten(node: Node): Node[] { return [node, ...(node.children ?? []).flatMap(flatten)]; }
function shown(node: Node): boolean { return !node.hidden && node.visible !== false && node.rect.w > 0 && node.rect.h > 0 && (node.opacity ?? 1) > 0; }
async function strip(): Promise<Node> { const nodes = await query("tabs.strip"); assert.equal(nodes.length, 1); return nodes[0]; }
async function active(): Promise<number> {
  // 稿 3 / ZW4 Tab: only the active surface is 33 high (it joins the island); inactive ones are 30.
  const matches = flatten(await strip()).filter(n => /^tabs\.tab\.\d+$/.test(n.test_id ?? "") && Math.abs((n.rect?.h ?? 0) - 33) < 0.5);
  assert.equal(matches.length, 1, "Exactly one tab surface must be the active (33-high) one");
  return Number(matches[0].test_id.split(".").at(-1));
}
// Activation history, most recent first (the order Ctrl+Tab freezes and walks).
const mru: number[] = [];
async function expectActive(id: number) {
  try { await waitFor(async () => await active() === id || null); }
  catch (cause) { throw new Error(`Expected active tab ${id}, actual ${await active()}`, { cause }); }
  const at = mru.indexOf(id); if (at >= 0) mru.splice(at, 1); mru.unshift(id);
}
// 稿 3 (tab_naming.commandOrdinal / ordinalTarget): ⌘1–⌘8 are the first eight tabs and ⌘9 is the last one.
const ordinalTarget = (digit: number, count: number) => digit < 9 ? Math.min(digit, count) : count;
async function press(name: string, mods?: { cmd?: boolean; ctrl?: boolean; shift?: boolean }) { assert((await key(name, mods)).ok); }
async function click(id: string) { assert((await clickTestId(id)).ok, `Click ${id}`); }
async function tab(id: number) { const nodes = await query(`tabs.tab.${id}`); assert.equal(nodes.length, 1); return nodes[0]; }
// While ⌘ is held (300 ms) each tab shows its “⌘N” ordinal (tabs.ordinal) next to the title; the type icon stays.
function digit(node: Node): string | null {
  const walk = (n: Node): string | null => {
    if (!shown(n)) return null;
    if (n.test_id === "tabs.ordinal") return (n.text ?? "").match(/[1-9]/)?.[0] ?? null;
    for (const c of n.children ?? []) { const d = walk(c); if (d) return d; }
    return null;
  };
  return walk(node);
}
async function numbers(expected: boolean) {
  const values = await Promise.all(Array.from({ length: 10 }, (_, i) => tab(i + 1).then(digit)));
  // Ten tabs: tabs 1–8 show ⌘1–⌘8, tab 9 none, the last tab ⌘9.
  assert.deepEqual(values, Array.from({ length: 10 }, (_, i) => !expected ? null : i < 8 ? String(i + 1) : i === 9 ? "9" : null));
  return values;
}
async function capture(name: string) {
  await sleep(150); assert((await screenshot(join(output, `${name}.png`))).ok);
  await writeFile(join(output, `${name}.strip.json`), JSON.stringify(await strip(), null, 2));
}
async function check(name: string, fn: () => Promise<any>) {
  const result: any = { name, status: "running" }; report.checks.push(result);
  try { result.observed = await fn(); result.status = "passed"; }
  catch (error) {
    result.status = "failed"; result.error = String(error); failure ??= error;
    await capture(`failed-check-${report.checks.length}`).catch(() => {});
  }
}
let failure: unknown;
try {
  await waitForServerReady();
  const owner = JSON.parse(await readFile(join(rpc, "owner.json"), "utf8"));
  assert.equal(Number(owner.pid), child.pid, "Never attach to a different process");
  for (let i = 1; i <= 10; i++) {
    // 83a600af: saved connections are in the + menu's “更多” flyout (quick connect left the menu).
    await click("toolbar.new_session");
    const more = await waitFor(async () => (await query("session.menu.more")).find(shown) ?? null);
    await mouseMove(more.rect.x + more.rect.w / 2, more.rect.y + more.rect.h / 2);
    const row = await waitFor(async () => (await query("session.menu.more.host")).find(shown) ?? null);
    assert((await clickAt(row.rect.x + row.rect.w / 2, row.rect.y + row.rect.h / 2)).ok);
    await expectActive(i);
  }
  report.tab_count = 10;
  await check("Command shows ⌘1–⌘8 on the first eight tabs and ⌘9 on the last (稿 3)", async () => {
    await press("1", { cmd: true }); await expectActive(1);
    await waitFor(async () => digit(await tab(1)) === "1" || null);
    const values = await numbers(true); await capture("command-held-first-nine"); return values;
  });
  await check("⌘1–⌘8 activate those tabs and ⌘9 the last tab", async () => {
    const actual = [];
    for (let i = 1; i <= 9; i++) { await press(String(i), { cmd: true }); await expectActive(ordinalTarget(i, 10)); actual.push(await active()); }
    return actual;
  });
  await check("A key event without Command restores all type icons (not a native key-up test)", async () => {
    await press("escape");
    await waitFor(async () => digit(await tab(1)) === null || null);
    const values = await numbers(false); await capture("command-released"); return values;
  });
  await check("稿 3 overflow: least recently used tabs go into ⌄ n; ⌘N on a hidden tab brings it back", async () => {
    assert((await resizeWindow(860, 480)).ok);
    await waitFor(async () => (await query("tabs.all")).length === 1 || null);
    const shown = async () => { const out: number[] = []; for (let i = 1; i <= 10; i++) if ((await query(`tabs.tab.${i}`)).length) out.push(i); return out; };
    const visible = await shown();
    assert(visible.includes(await active()), "The active tab is always in the strip");
    const hidden = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10].filter((i) => !visible.includes(i));
    assert(hidden.length > 0, "860 × 480 with ten tabs must overflow");
    const target = hidden[0];
    await press(String(Math.min(target, 9)), { cmd: true });
    const picked = target <= 8 ? target : 10;
    await expectActive(picked);
    assert((await shown()).includes(picked), "A tab activated by ⌘N is shown in the strip");
    await capture("overflow-active-visible"); return { visible, hidden, picked };
  });
  await check("Ctrl+Tab uses frozen MRU order and Shift reverses the preview", async () => {
    for (const id of [2, 5, 3]) { await press(String(id), { cmd: true }); await expectActive(id); }
    // Ctrl+Tab walks the activation history frozen at the first press and wraps back to the current tab.
    const frozen = [...mru], observed = [], expected = [...frozen.slice(1), frozen[0]];
    for (const target of expected) {
      await press("tab", { ctrl: true });
      await expectActive(target); observed.push(await active());
    }
    await press("tab", { ctrl: true, shift: true }); await expectActive(frozen.at(-1)!);
    const reverse = await active();
    await capture("mru-frozen-preview"); return { established: [2, 5, 3], frozen, expected, observed, reverse };
  });
  report.stats = await stats(); report.status = failure ? "failed" : "passed";
} catch (error) {
  failure = error; report.status = "failed"; report.error = String(error);
  if (child.exitCode === null && child.signalCode === null) {
    const diagnostics = await Promise.allSettled([capture("failure"), query("tabs.all"), query("tabs.viewport")]);
    report.diagnostics = diagnostics.map(result => result.status === "fulfilled" ? result.value : String(result.reason));
  }
} finally {
  if (child.exitCode === null && child.signalCode === null) child.kill("SIGTERM");
  await Promise.race([ended, sleep(2000)]);
  if (child.exitCode === null && child.signalCode === null) { child.kill("SIGKILL"); await ended; }
  report.process_cleanup = { exit_code: child.exitCode, signal: child.signalCode };
  report.finished_at = new Date().toISOString();
  await writeFile(join(output, "harness-report.json"), JSON.stringify(report, null, 2));
  await log.close(); await rm(isolated, { recursive: true, force: true });
}
console.log(`${report.status}: ${join(output, "harness-report.json")}`);
if (failure) throw failure;
