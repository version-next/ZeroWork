import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import {nativeThemeData} from './native_theme_data.mjs';
/** Retained production views/recipes in the isolated native button acceptance window (button-policy-preview).
 *
 * The preview cycles every built-in palette (light and dark) in one process, so this script has no theme variant.
 *
 * Disabled state: buttons are zenit native (user hard rule), so the disabled look is zenit's, not ours. zenit expresses it
 * without opacity (vendor/zenit/src/ui/components/control_shell/styles.yss tone `:disabled { background: disabled-bg;
 * color: fg-disabled; }`; button/button.yix `focusable = !disabled`, click suppressed). The old `effective_opacity < 1`
 * check described a hand-made disabled look that no longer exists. Asserted here instead, per palette:
 *   - the disabled secondary sm button paints the disabled tone: its background differs from the same button enabled,
 *     which equals an enabled secondary sm sibling (fixture.next); its painted label ink is dimmer (lower contrast against
 *     its own background) than that sibling's;
 *   - it is out of the focus order and a press dispatches nothing; once enabled it is focusable and dispatches.
 * The measured ink / background / contrast per palette are written to report.json (`disabled`) — whether that difference
 * is “sufficiently distinguishable” is a design judgment handed to the user, not a threshold asserted here.
 */
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdir, mkdtemp, realpath, readFile, writeFile, open, rm } from "node:fs/promises";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { inflateSync } from "node:zlib";

const prefix = resolve(process.argv[2]), out = resolve(process.argv[3]);
const h = await import(pathToFileURL(join(prefix, "share/zenit/harness/client.ts")).href);
const binary = join(prefix, "bin/button-policy-preview");
const themes = Object.keys(nativeThemeData.themes);
const selected = new Set(["dark", "light", "sauber", "mist", "nord", "solarized-light", "reference-light"]);
await mkdir(out, { recursive: true });
const iso = await realpath(await mkdtemp("/tmp/zw-button-policy-"));
const rpc = join(iso, "rpc");
await mkdir(rpc);
process.env.ZENIT_E2E_FILE_RPC_DIR = rpc;
const log = await open(join(out, "app.log"), "w");
const app = spawn(binary, [], { env: { ...process.env, ZENIT_E2E_FILE_RPC_DIR: rpc, ZENIT_E2E_ISOLATE_POINTER: "1", ZENIT_E2E_BACKGROUND: "1" }, stdio: ["ignore", log.fd, log.fd] });
const ended = new Promise<void>(done => app.once("close", () => done()));
const alive = () => app.exitCode === null && app.signalCode === null;
const report: any = { status: "running", binary, sha256: createHash("sha256").update(await readFile(binary)).digest("hex"), themes: [], captures: [], disabled: [], scope: "Production remote notice and recovery views, copy feedback, and production execution/transfer/notification button recipes. Synthetic receipts; no model, PTY, credentials or business IO." };
const shown = (n: any) => n?.rect && !n.hidden && n.visible !== false && (n.effective_opacity ?? 1) > 0 && n.rect.w > 0 && n.rect.h > 0;
const visible = async (id: string) => h.waitFor(async () => (await h.query(id)).find(shown) ?? null);
const click = async (id: string) => { await visible(id); assert((await h.clickTestId(id)).ok, id); };
const flat = (n: any): any[] => shown(n) ? [n, ...(n.children ?? []).flatMap(flat)] : [];
const text = (n: any) => flat(n).map((n: any) => n.text ?? "").join("");
const labelOf = (n: any) => flat(n).find((x: any) => x.text);
/** A node once its geometry, paint and focusability stop changing (tone transitions after a theme or state change), within a time limit. */
const stable = async (id: string, ms = 3000) => { let last = ""; return h.waitFor(async () => { const n = (await h.query(id)).find(shown); const k = n && JSON.stringify([n.rect, n.bg_rgba, n.focusable]); if (n && k === last) return n; last = k ?? ""; await h.sleep(80); return null; }, ms); };
const ids = ["fixture.theme", "remote.notice", "remote.notice.close", "remote.notice.reconnect", "sample.execution", "sample.transfer", "sample.notification", "sample.blocked", "sample.copy", "ai.recovery"];
function fits(button: any) {
  for (const n of flat(button).filter((n: any) => n.text)) {
    assert(n.rect.x >= button.rect.x - .5 && n.rect.x + n.rect.w <= button.rect.x + button.rect.w + .5, `Clipped action text: ${n.text}`);
    assert(n.rect.y >= button.rect.y - .5 && n.rect.y + n.rect.h <= button.rect.y + button.rect.h + .5);
  }
}
async function capture(theme: string, state: string) {
  await h.sleep(220);
  const nodes = Object.fromEntries(await Promise.all(ids.map(async id => [id, await h.query(id)])));
  const name = `${theme}-${state}`;
  await writeFile(join(out, `${name}.json`), JSON.stringify(nodes, null, 2));
  assert((await h.screenshot(join(out, `${name}.png`))).ok);
  report.captures.push(name);
}

// ── Painted label ink (the harness reports a label's own color, not the inherited currentColor that is painted) ──
type Image = { width: number; height: number; channels: number; pixels: Buffer };
function paeth(a: number, b: number, c: number) { const p = a + b - c, da = Math.abs(p - a), db = Math.abs(p - b), dc = Math.abs(p - c); return da <= db && da <= dc ? a : db <= dc ? b : c; }
function decodePng(bytes: Buffer): Image {
  assert(bytes.subarray(0, 8).equals(Buffer.from("89504e470d0a1a0a", "hex")), "Screenshot must be PNG");
  const chunks: Buffer[] = []; let width = 0, height = 0, channels = 0, offset = 8, done = false;
  while (offset + 12 <= bytes.length) {
    const length = bytes.readUInt32BE(offset), kind = bytes.toString("ascii", offset + 4, offset + 8), data = bytes.subarray(offset + 8, offset + 8 + length);
    if (kind === "IHDR") { width = data.readUInt32BE(0); height = data.readUInt32BE(4); assert.equal(data[8], 8); assert(data[9] === 6 || data[9] === 2); channels = data[9] === 6 ? 4 : 3; assert.equal(data[12], 0, "Interlaced screenshot unsupported"); }
    else if (kind === "IDAT") chunks.push(data); else if (kind === "IEND") { done = true; break; }
    offset += length + 12;
  }
  assert(done && width && channels && chunks.length, "Incomplete PNG");
  const rowBytes = width * channels, raw = inflateSync(Buffer.concat(chunks), { maxOutputLength: (rowBytes + 1) * height }), pixels = Buffer.alloc(rowBytes * height);
  for (let y = 0; y < height; y++) {
    const filter = raw[y * (rowBytes + 1)]; assert(filter <= 4, `Unknown PNG filter ${filter}`);
    for (let x = 0; x < rowBytes; x++) {
      const i = y * rowBytes + x, a = x >= channels ? pixels[i - channels] : 0, b = y ? pixels[i - rowBytes] : 0, c = y && x >= channels ? pixels[i - rowBytes - channels] : 0;
      pixels[i] = (raw[y * (rowBytes + 1) + 1 + x] + (filter === 0 ? 0 : filter === 1 ? a : filter === 2 ? b : filter === 3 ? Math.floor((a + b) / 2) : paeth(a, b, c))) & 255;
    }
  }
  return { width, height, channels, pixels };
}
const rgb = (s: string) => s.split(",").slice(0, 3).map(Number);
const lum = ([r, g, b]: number[]) => { const f = (v: number) => { v /= 255; return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; }; return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b); };
const contrast = (a: number[], b: number[]) => { const [x, y] = [lum(a), lum(b)].sort((p, q) => q - p); return (x + 0.05) / (y + 0.05); };
/** Background = the most common pixel in the button's padding strip (left of the label); ink = the label-rect pixel furthest from it. */
function paint(image: Image, scale: number, button: any, label: any) {
  const px = (x: number, y: number) => { const i = (Math.round(y * scale) * image.width + Math.round(x * scale)) * image.channels; return [image.pixels[i], image.pixels[i + 1], image.pixels[i + 2]]; };
  const counts = new Map<string, number>();
  for (let y = button.rect.y + 4; y < button.rect.y + button.rect.h - 4; y += 0.5) for (let x = button.rect.x + 3; x < label.rect.x - 2; x += 0.5) { const k = px(x, y).join(","); counts.set(k, (counts.get(k) ?? 0) + 1); }
  const bg = rgb([...counts.entries()].sort((a, b) => b[1] - a[1])[0][0]);
  let ink = bg, best = -1;
  for (let y = label.rect.y; y < label.rect.y + label.rect.h; y += 0.5) for (let x = label.rect.x; x < label.rect.x + label.rect.w; x += 0.5) { const p = px(x, y), d = Math.abs(p[0] - bg[0]) + Math.abs(p[1] - bg[1]) + Math.abs(p[2] - bg[2]); if (d > best) { best = d; ink = p; } }
  return { bg, ink, contrast: Math.round(contrast(ink, bg) * 100) / 100 };
}

try {
  await h.waitForServerReady();
  assert.equal(Number(JSON.parse(await readFile(join(rpc, "owner.json"), "utf8")).pid), app.pid);
  await h.resizeWindow(1100, 600);
  const identity = (await visible("remote.notice.close")).id;
  for (let i = 0; i < themes.length; i++) {
    const theme = text(await visible("fixture.theme"));
    assert(themes.includes(theme) && !report.themes.includes(theme), `Unexpected/repeated palette: ${theme}`);
    report.themes.push(theme);
    const close = await visible("remote.notice.close"), reconnect = await visible("remote.notice.reconnect");
    assert.equal(close.id, identity, "Theme changes must retain the original native control");
    fits(close); fits(reconnect);
    assert.equal(close.rect.h, reconnect.rect.h);
    for (const id of ["sample.execution", "sample.notification", "sample.blocked"]) fits(await visible(id));
    const transfer = await visible("sample.transfer");
    assert(Math.abs(transfer.rect.w - transfer.rect.h) < 0.1, "the native transfer icon button stays square");
    // Native disabled (secondary sm) next to an enabled secondary sm sibling, both settled in this palette.
    await h.mouseMove(1090, 580);
    const blocked = await stable("sample.blocked"), sibling = await stable("fixture.next");
    assert.equal(blocked.component, "Button"); assert.equal(blocked.effective_opacity ?? 1, 1, "zenit's disabled tone is not an opacity");
    assert.equal(blocked.focusable ?? false, false, "Disabled action leaves the focus order");
    assert.equal(sibling.focusable, true);
    assert.equal(blocked.rect.h, sibling.rect.h, "same native size tier");
    assert.notEqual(blocked.bg_rgba, sibling.bg_rgba, "Disabled action paints the disabled background, not the secondary tone");
    const before = text(await visible("fixture.outcome"));
    await h.clickAt(blocked.rect.x + blocked.rect.w / 2, blocked.rect.y + blocked.rect.h / 2);
    await h.mouseMove(1090, 580);
    assert.equal(text(await visible("fixture.outcome")), before, "Disabled action must not invoke the handler");
    const probe = join(out, `${theme}-disabled-probe.png`);
    assert((await h.screenshot(probe)).ok);
    const image = decodePng(await readFile(probe)), scale = image.width / 1100;
    const disabledPaint = paint(image, scale, blocked, labelOf(blocked)), enabledPaint = paint(image, scale, sibling, labelOf(sibling));
    await rm(probe); // the measurement is in report.json; selected palettes keep their normal / hover / pressed / compact captures
    report.disabled.push({ theme, disabled: { bg_rgba: blocked.bg_rgba, ...disabledPaint }, enabled_sibling: { bg_rgba: sibling.bg_rgba, ...enabledPaint }, disabled_bg_vs_enabled_bg: Math.round(contrast(rgb(blocked.bg_rgba), rgb(sibling.bg_rgba)) * 100) / 100 });
    assert(disabledPaint.contrast < enabledPaint.contrast, `${theme}: disabled label ink (${disabledPaint.ink} on ${disabledPaint.bg}, ${disabledPaint.contrast}:1) must be dimmer than the enabled secondary label (${enabledPaint.ink} on ${enabledPaint.bg}, ${enabledPaint.contrast}:1)`);
    // Enabled, the same button is the secondary tone again and focusable; disable it back.
    await click("fixture.disabled");
    const enabled = await h.waitFor(async () => { const n = await stable("sample.blocked"); return n.focusable ? n : null; }, 3000);
    assert.equal(enabled.bg_rgba, sibling.bg_rgba, "Enabled it paints the same secondary tone as its sibling");
    await click("fixture.disabled");
    await h.waitFor(async () => !(await stable("sample.blocked")).focusable || null, 3000);
    await click("fixture.copy-ok");
    if (selected.has(theme)) {
      await h.mouseMove(1090, 580);
      await capture(theme, "normal");
      await h.mouseMove(close.rect.x + close.rect.w / 2, close.rect.y + close.rect.h / 2);
      await capture(theme, "hover");
      await h.mouseDown(close.rect.x + close.rect.w / 2, close.rect.y + close.rect.h / 2);
      await capture(theme, "pressed");
      await h.mouseMove(1090, 580);
      await h.mouseUp(1090, 580);
      await click("fixture.copy-failed");
      await h.resizeWindow(600, 400);
      fits(await visible("remote.notice.close")); fits(await visible("remote.notice.reconnect"));
      await capture(theme, "compact");
      await h.resizeWindow(1100, 600);
    }
    await click("fixture.next");
    await h.waitFor(async () => text(await visible("fixture.theme")) !== theme || null);
  }
  assert.deepEqual(new Set(report.themes), new Set(themes));
  // The handler is wired: enabled, the same button dispatches (checked last, the outcome text is not reset).
  assert.equal(text(await visible("fixture.outcome")), "idle", "No disabled press or press-cancel reached the handler in any palette");
  await click("fixture.disabled");
  await h.waitFor(async () => (await stable("sample.blocked")).focusable || null, 3000);
  await click("sample.blocked");
  await h.waitFor(async () => text(await visible("fixture.outcome")) === "clicked" || null, 3000);
  const contrasts = report.disabled.map((d: any) => d.disabled.contrast);
  report.disabled_summary = { palettes: report.disabled.length, disabled_label_contrast_min: Math.min(...contrasts), disabled_label_contrast_max: Math.max(...contrasts), lowest: report.disabled.filter((d: any) => d.disabled.contrast === Math.min(...contrasts)).map((d: any) => d.theme) };
  await click("fixture.quit");
  await Promise.race([ended, h.sleep(8000)]);
  assert(!alive() && app.exitCode === 0, "Normal native window shutdown required");
  report.status = "passed";
} catch (error) {
  report.status = "failed";
  report.error = String(error);
  if (alive()) await capture("failure", "state").catch(() => {});
  process.exitCode = 1;
} finally {
  if (alive()) {
    await click("fixture.quit").catch(() => {});
    await Promise.race([ended, h.sleep(2000)]);
  }
  if (alive()) { report.forced_cleanup = true; app.kill("SIGTERM"); await ended; }
  report.exit_code = app.exitCode;
  await log.close();
  await rm(iso, { recursive: true, force: true });
  await writeFile(join(out, "report.json"), JSON.stringify(report, null, 2));
  console.log(`${report.status}: ${join(out, "report.json")}`);
}
