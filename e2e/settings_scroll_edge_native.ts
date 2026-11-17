/**
 * Settings content viewport scroll edge (human feedback round 1 #3): the native `W.ScrollArea scrollEdge`
 * band under the page header must be invisible while the page rests at the top — the first line of the
 * body (group title, right-hand summary) is sharp — and the progressive blur must appear once content
 * scrolls under the header.
 *
 *   zig build -Dtest-mode=true [--prefix DIR]
 *   node e2e/settings_scroll_edge_native.ts --binary <test-mode zerowork> --out DIR [--theme light|dark]
 *
 * The real app (settings window opened from the toolbar), isolated data dir (settings_nav.launchIsolated),
 * background window, Harness input only. Not the settings preview runner: there the content viewport of a
 * long page is laid out at its content height (no scrolling), unlike the app.
 *
 * Measure: node tree gives the scroll-edge band (`ScrollEdgeEffect`, top of `settings.viewport`) and the
 * text nodes under it; the screenshot gives each text's "strong edge" count — adjacent-pixel luminance
 * steps ≥ 48 inside the text rect. Sharp glyphs have many, glyphs under a backdrop blur have almost none.
 * 1. At rest, on several subpages, every text that intersects the band is sharp: ≥ MIN_SHARP strong edges
 *    (without the fix these texts measure 0; with the band removed or fixed, hundreds to thousands).
 * 2. On a long page, after scrolling, a text that now sits in the top half of the band has lost most of
 *    its strong edges compared with the same text at rest (≤ 40 %): the blur is there.
 *
 * Round 2 (header modelled on znote's board detail): the viewport starts at the window's top edge, the band
 * (76 pt, full blur over the top 30 %) lies under the floating page header, so the scrolled text is picked
 * from a column the header leaves empty (no glass capsule, title or subtitle above it) — otherwise the
 * header's own sharp glyphs and icons would be measured instead of the content under the band.
 */
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { inflateSync } from "node:zlib";
import * as h from "../vendor/zenit/e2e/client.ts";
import { launchIsolated, settingsNav } from "./settings_nav.ts";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const args = process.argv.slice(2);
const options: Record<string, string> = {};
for (let index = 0; index < args.length; index += 2) {
  if (!["--out", "--binary", "--theme"].includes(args[index]) || !args[index + 1]) throw new Error(`Invalid option ${args[index]}`);
  options[args[index]] = args[index + 1];
}
const binary = resolve(options["--binary"] ?? join(root, "zig-out/bin/zerowork"));
const output = resolve(options["--out"] ?? join(root, `dist/ui-acceptance/settings-scroll-edge-${Date.now()}`));
const theme = options["--theme"] ?? "light";
await mkdir(output, { recursive: true });

/** Strong edges a sharp line of settings text has at 2x (measured ≥ 150 for short labels). */
const MIN_SHARP = 40;
const report = {
  scope: "settings viewport scroll edge: invisible at rest, progressive blur after scrolling",
  binary,
  binary_sha256: createHash("sha256").update(await readFile(binary)).digest("hex"),
  theme,
  rest: [] as Record<string, unknown>[],
  scrolled: {} as Record<string, unknown>,
  status: "running",
  error: undefined as string | undefined,
};

type Rect = { x: number; y: number; w: number; h: number };
type Node = h.QueryNode & { effective_opacity?: number; component?: string; type?: string };
const shown = (n: Node | undefined) => !!n && n.visible !== false && n.rect.w > 0 && n.rect.h > 0 && (n.effective_opacity ?? 1) > 0;
const node = (id: string, ms = 10000) => h.waitFor(async () => ((await h.query(id)) as Node[]).find(shown) ?? null, ms);
const intersects = (a: Rect, b: Rect) => a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;
function walk(n: Node, visit: (n: Node) => void) { visit(n); for (const c of n.children ?? []) walk(c as Node, visit); }
/** Leaf text nodes (non-empty own text) inside `within`. */
function texts(tree: Node, within: Rect): Node[] {
  const out: Node[] = [];
  walk(tree, n => { if (shown(n) && (n.text ?? "").trim() && !(n.children ?? []).length && intersects(n.rect, within)) out.push(n); });
  return out;
}
function findBand(tree: Node): Node | null {
  let band: Node | null = null;
  walk(tree, n => { if (!band && JSON.stringify([n.component, n.type, (n as any).name, (n as any).tag]).includes("ScrollEdgeEffect")) band = n; });
  return band;
}

// ── minimal PNG decoder (8-bit RGB/RGBA, non-interlaced) ──
function decodePng(bytes: Buffer) {
  let offset = 8, width = 0, height = 0, colorType = 0;
  const idat: Buffer[] = [];
  while (offset < bytes.length) {
    const length = bytes.readUInt32BE(offset);
    const type = bytes.toString("latin1", offset + 4, offset + 8);
    const data = bytes.subarray(offset + 8, offset + 8 + length);
    if (type === "IHDR") {
      width = data.readUInt32BE(0); height = data.readUInt32BE(4); colorType = data[9];
      if (data[8] !== 8 || data[12] !== 0 || (colorType !== 6 && colorType !== 2)) throw new Error(`unsupported PNG ${data[8]}/${colorType}/${data[12]}`);
    } else if (type === "IDAT") idat.push(data);
    else if (type === "IEND") break;
    offset += 12 + length;
  }
  const channels = colorType === 6 ? 4 : 3;
  const raw = inflateSync(Buffer.concat(idat));
  const stride = width * channels;
  const luma = new Float32Array(width * height);
  const previous = Buffer.alloc(stride), line = Buffer.alloc(stride);
  for (let y = 0; y < height; y++) {
    const filter = raw[y * (stride + 1)];
    const source = raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1));
    for (let x = 0; x < stride; x++) {
      const a = x >= channels ? line[x - channels] : 0, b = previous[x], c = x >= channels ? previous[x - channels] : 0;
      let value = source[x];
      if (filter === 1) value += a; else if (filter === 2) value += b; else if (filter === 3) value += (a + b) >> 1;
      else if (filter === 4) { const p = a + b - c, pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c); value += pa <= pb && pa <= pc ? a : pb <= pc ? b : c; }
      line[x] = value & 0xff;
    }
    for (let x = 0; x < width; x++) luma[y * width + x] = 0.2126 * line[x * channels] + 0.7152 * line[x * channels + 1] + 0.0722 * line[x * channels + 2];
    line.copy(previous);
  }
  return { width, height, luma };
}
type Image = ReturnType<typeof decodePng>;
/** Adjacent-pixel luminance steps ≥ 48 inside `r` (logical px, image at `scale`). */
function strongEdges(img: Image, r: Rect, scale: number) {
  const x0 = Math.max(0, Math.floor(r.x * scale)), y0 = Math.max(0, Math.floor(r.y * scale));
  const x1 = Math.min(img.width - 1, Math.ceil((r.x + r.w) * scale)), y1 = Math.min(img.height - 1, Math.ceil((r.y + r.h) * scale));
  let n = 0;
  for (let y = y0; y < y1; y++) for (let x = x0; x < x1; x++) {
    const v = img.luma[y * img.width + x];
    if (Math.abs(v - img.luma[y * img.width + x + 1]) >= 48) n++;
    if (Math.abs(v - img.luma[(y + 1) * img.width + x]) >= 48) n++;
  }
  return n;
}
async function shot(name: string) {
  const path = join(output, `${name}.png`);
  assert((await h.screenshot(path)).ok, `screenshot ${name}`);
  return decodePng(await readFile(path));
}
const settle = async () => { await h.mouseMove(2, 2).catch(() => undefined); await h.sleep(600); };

const nav = settingsNav();

/** One subpage at rest: every text under the band stays sharp. */
async function rest(cat: string, sub: string | null) {
  const name = `rest-${cat}-${sub ?? "page"}`;
  const record: Record<string, unknown> = { page: cat, sub };
  report.rest.push(record);
  try {
    if (sub === null) await nav.toCategory(cat); else await nav.toSub(cat, sub);
    const viewport = await node("settings.viewport");
    await settle();
    const tree = (await h.tree()) as Node;
    // The strip right under the header: the band when mounted (its absence is caught by `scrolled`).
    const band = findBand(tree);
    const strip = band?.rect ?? { x: viewport.rect.x, y: viewport.rect.y, w: viewport.rect.w, h: 28 };
    record.band = band?.rect ?? null;
    const img = await shot(name);
    const scale = img.width / tree.rect.w;
    const under = texts(tree, strip);
    record.texts = under.map(t => ({ text: t.text, rect: t.rect, edges: strongEdges(img, t.rect, scale) }));
    assert(under.length > 0, "some body text sits under the band at rest (first line of the page)");
    for (const t of record.texts as { text: string; edges: number }[]) assert(t.edges >= MIN_SHARP, `"${t.text}" under the band at rest is blurred (strong edges ${t.edges} < ${MIN_SHARP})`);
    record.status = "passed";
  } catch (error) {
    record.status = "failed";
    record.error = String((error as Error)?.stack ?? error);
    throw error;
  }
}

/** A long page: a text sharp at rest loses its edges once scrolled under the band. */
async function scrolled(cat: string) {
  const name = `scroll-${cat}`;
  const record = report.scrolled = { page: cat } as Record<string, unknown>;
  try {
    await nav.toCategory(cat);
    const viewport = await node("settings.viewport");
    await settle();
    const tree0 = (await h.tree()) as Node;
    const band = findBand(tree0);
    assert(band, "viewport has a ScrollEdgeEffect band");
    record.band = band.rect;
    const img0 = await shot(`${name}-0`);
    const scale = img0.width / tree0.rect.w;
    // A text well below the band at rest (sharp there), scrolled until its top sits just under the band's top edge.
    // Columns the floating header paints over (capsules with a little glass margin, its texts).
    const intro = await node("settings.page.intro");
    const occupied: Rect[] = [];
    for (const id of ["settings.history", "settings.help"]) for (const n of (await h.query(id)) as Node[]) if (shown(n)) occupied.push({ ...n.rect, x: n.rect.x - 8, w: n.rect.w + 16 });
    occupied.push(...texts(tree0, intro.rect).map(t => ({ ...t.rect, x: t.rect.x - 8, w: t.rect.w + 16 })));
    record.header_columns = occupied;
    const clear = (r: Rect) => !occupied.some(o => r.x < o.x + o.w && o.x < r.x + r.w);
    const below = texts(tree0, { x: viewport.rect.x, y: band.rect.y + band.rect.h + 40, w: viewport.rect.w, h: 200 })
      .filter(t => clear(t.rect))
      .map(t => ({ t, edges: strongEdges(img0, t.rect, scale) })).filter(c => c.edges >= MIN_SHARP);
    assert(below.length, "a sharp text below the band at rest, in a column the header leaves empty");
    const pick = below[0];
    const target = band.rect.y + 2;
    record.text = pick.t.text;
    record.rest = { rect: pick.t.rect, edges: pick.edges };
    const same = (t: Node) => t.text === pick.t.text && Math.abs(t.rect.x - pick.t.rect.x) < 1;
    let rect = pick.t.rect;
    for (let i = 0; i < 40 && Math.abs(rect.y - target) > 2; i++) {
      const step = Math.max(-60, Math.min(60, rect.y - target));
      await h.scrollAt(viewport.rect.x + viewport.rect.w / 2, viewport.rect.y + Math.min(viewport.rect.h, tree0.rect.h - viewport.rect.y) / 2, 0, -step);
      await h.sleep(200);
      const again = texts((await h.tree()) as Node, { ...viewport.rect, y: viewport.rect.y - 200, h: viewport.rect.h + 200 }).find(same);
      if (!again) break;
      rect = again.rect;
    }
    await settle();
    const now = texts((await h.tree()) as Node, { ...viewport.rect, y: viewport.rect.y - 200, h: viewport.rect.h + 200 }).find(same);
    assert(now, "picked text still in the tree after scrolling");
    const img1 = await shot(`${name}-1`);
    const top = { x: now.rect.x, y: Math.max(now.rect.y, band.rect.y), w: now.rect.w, h: Math.min(now.rect.y + now.rect.h, band.rect.y + band.rect.h / 2) - Math.max(now.rect.y, band.rect.y) };
    assert(top.h > 4, `picked text overlaps the band's top half (text ${JSON.stringify(now.rect)}, band ${JSON.stringify(band.rect)})`);
    const restSlice = { ...top, y: pick.t.rect.y + (top.y - now.rect.y) };
    const edgesRest = strongEdges(img0, restSlice, scale), edgesNow = strongEdges(img1, top, scale);
    record.under_band = { rect: now.rect, compared: top, edges_rest: edgesRest, edges_scrolled: edgesNow };
    assert(edgesRest >= 10, `reference slice is sharp at rest (${edgesRest})`);
    assert(edgesNow <= edgesRest * 0.4, `"${pick.t.text}" under the band after scrolling keeps ${edgesNow}/${edgesRest} strong edges: no progressive blur`);
    record.status = "passed";
  } catch (error) {
    record.status = "failed";
    record.error = String((error as Error)?.stack ?? error);
    throw error;
  }
}

const app = await launchIsolated({ binary, out: output, prefix: "zw-settings-scroll-edge", theme, logName: "app.log" });
try {
  // Short subpages whose first line sits right under the header (round-1 report: SSH › 断线重连).
  await nav.open();
  for (const [cat, sub] of [["ssh", "reconnect"], ["ssh", "connection"], ["transfer", "connection"], ["notifications", "events"], ["keys", null]] as [string, string | null][]) await rest(cat, sub);
  await scrolled("keys");
  report.status = "passed";
} catch (error) {
  report.status = "failed";
  report.error = String((error as Error)?.stack ?? error);
  process.exitCode = 1;
} finally {
  await app.stop();
  await writeFile(join(output, "report.json"), JSON.stringify(report, null, 2));
  console.log(JSON.stringify({ status: report.status, error: report.error }));
}
