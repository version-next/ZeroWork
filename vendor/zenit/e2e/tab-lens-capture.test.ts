// Capture the iOS tab-lens fixtures (story glassioslens) with their node rects, for
// scripts/glass_native_model/ios/compare_tab_lens.py. Launch with
// ZENIT_STORYBOOK_STORY=glassioslens ZENIT_E2E_TEST_FILE=e2e/tab-lens-capture.test.ts
// ZENIT_LENS_OUT=<dir>. No thresholds: the comparison is numeric and visual, offline.
import { writeFileSync, mkdirSync } from "node:fs";
import { query, screenshot, waitForServerReady, sleep, stats } from "./client";
const out = process.env.ZENIT_LENS_OUT!;
mkdirSync(out, { recursive: true });
await waitForServerReady();
await sleep(2500);
const rects: Record<string, any> = {};
for (const id of ["rest", "held", "straddle", "home"]) {
  const strip = (await query(`story.ioslens.${id}`))[0];
  const lens = (await query(`story.ioslens.${id}.lens`))[0];
  if (!strip || !lens) throw new Error(`fixture ${id} missing`);
  rects[id] = { strip: strip.rect, lens: lens.rect };
}
const st = await stats();
const r = await screenshot(`${out}/lens.png`);
if (r.ok !== true) throw new Error("capture failed");
writeFileSync(`${out}/rects.json`, JSON.stringify({ window_scale: st.window_scale, rects }, null, 2));
console.log(`captured ${out}/lens.png`);
