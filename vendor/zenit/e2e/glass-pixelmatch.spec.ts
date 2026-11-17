// The public Playwright matcher compares native app PNGs. No browser rendering
// substitutes for SwiftUI or Metal, and Zenit can never update the native baseline.
import { test, expect } from "@playwright/test";
import { readFileSync, mkdirSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { createHash } from "node:crypto";
import { decodePng, writeRgbPng, type DecodedPng } from "./png";
import type { GlassScene } from "./glass-fixtures";
import { validateProductionCapture } from "./glass-provenance";

const root = resolve(process.env.ZENIT_GLASS_EVIDENCE_DIR ?? resolve(__dirname, "../reports/glass-native-fidelity"));
const contract = JSON.parse(readFileSync(process.env.ZENIT_GLASS_COMPARISON_CONTRACT ?? resolve(__dirname, "glass-fidelity.contract.json"), "utf8"));
const scenes: GlassScene[] = JSON.parse(readFileSync(`${root}/fixtures/scenes.json`, "utf8"));
function crop(p: DecodedPng, scene: GlassScene) {
  if (p.width !== 1280 || p.height !== 960) throw new Error("Invalid window dimensions; resizing and registration repair are forbidden");
  // Identical, geometry-defined crop in both captures, including 16 logical
  // pixels of shadow. Native window controls are outside these material ROIs.
  const x = Math.max(0, Math.floor((scene.x - 16) * 2));
  const y = Math.max(0, Math.floor((scene.y - 16) * 2));
  const w = Math.min(1280, Math.ceil((scene.x + scene.w + 16) * 2)) - x;
  const h = Math.min(960, Math.ceil((scene.y + scene.h + 16) * 2)) - y;
  const rgb = new Uint8Array(w * h * 3);
  for (let yy = 0; yy < h; yy++) for (let xx = 0; xx < w; xx++) {
    const i = ((y + yy) * p.width + x + xx) * p.channels;
    rgb.set(p.pixels.subarray(i, i + 3), (yy * w + xx) * 3);
  }
  return { x, y, w, h, rgb };
}
test.beforeAll(() => {
  const metadata = JSON.parse(readFileSync(`${root}/native/metadata.json`, "utf8"));
  if (metadata.renderer !== "SwiftUI.glassEffect" || metadata.scale !== 2) throw new Error("Invalid native provenance");
  if(!metadata.capture&&metadata.fixture_isolation!==contract.static_reference.fixture_isolation)throw new Error("Native scenes must use independent effect hosts");
  if(!metadata.capture)validateProductionCapture(root,metadata.run_id,contract.required_cases);
  for (const [key, want] of Object.entries(contract.preconditions))
    if (metadata[key] !== want) throw new Error(`Native reference precondition ${key} violated`);
  mkdirSync(`${root}/playwright/reference`, { recursive: true });
  mkdirSync(`${root}/playwright/actual`, { recursive: true });
  const provenance = [];
  for (const id of contract.required_cases) {
    const scene = scenes.find(s => s.id === id);
    if (!scene || !metadata.cases.includes(id)) throw new Error(`Missing native case ${id}`);
    if(!metadata.capture&&(!Number.isFinite(metadata.native_idle_rmse?.[id])||metadata.native_idle_rmse[id]>contract.static_reference.native_idle_rmse_max))throw new Error(`Native reference did not settle: ${id}`);
    const nativePath = `${root}/native/${id}.png`;
    const c = crop(decodePng(nativePath), scene);
    writeRgbPng(`${root}/playwright/reference/${id}.png`, c.w, c.h, c.rgb);
    provenance.push({ id, source: `native/${id}.png`, source_sha256: createHash("sha256").update(readFileSync(nativePath)).digest("hex"), roi: { x: c.x, y: c.y, w: c.w, h: c.h } });
  }
  writeFileSync(`${root}/playwright/provenance.json`, JSON.stringify({ algorithm: "Playwright.toMatchSnapshot/pixelmatch", playwright_version: "1.63.0", threshold: 0.2, maxDiffPixels: 0, reference: metadata, cases: provenance }, null, 2));
});
for (const id of contract.required_cases) test(`native glass ${id}`, async ({}, info) => {
  if (info.config.updateSnapshots !== "none") throw new Error("Native reference updates from Zenit are forbidden");
  const scene = scenes.find(s => s.id === id)!;
  const nativePath = `${root}/native/${id}.png`, actualPath = `${root}/zenit/${id}.png`;
  const c = crop(decodePng(actualPath), scene);
  const croppedPath = `${root}/playwright/actual/${id}.png`;
  writeRgbPng(croppedPath, c.w, c.h, c.rgb);
  await info.attach("SwiftUI native window", { path: nativePath, contentType: "image/png" });
  await info.attach("Zenit production window", { path: actualPath, contentType: "image/png" });
  expect(readFileSync(croppedPath)).toMatchSnapshot(`${id}.png`);
});
