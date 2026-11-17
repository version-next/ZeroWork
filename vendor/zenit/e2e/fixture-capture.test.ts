// Generic fixture capture: screenshot the current story and dump the rects of the given test
// ids, for the offline native comparisons (scripts/glass_native_model/compare_region.py).
//   ZENIT_STORYBOOK_STORY=<key> ZENIT_E2E_TEST_FILE=e2e/fixture-capture.test.ts
//   ZENIT_FIXTURE_OUT=<dir> ZENIT_FIXTURE_IDS=id1,id2,...   [ZENIT_FIXTURE_SETTLE_MS=2500]
import { writeFileSync, mkdirSync } from "node:fs";
import { query, screenshot, waitForServerReady, sleep, stats, mouseMove } from "./client";
const out = process.env.ZENIT_FIXTURE_OUT!;
const ids = (process.env.ZENIT_FIXTURE_IDS ?? "").split(",").filter(Boolean);
mkdirSync(out, { recursive: true });
await waitForServerReady();
await mouseMove(-10, -10);
await sleep(Number(process.env.ZENIT_FIXTURE_SETTLE_MS ?? 2500));
const rects: Record<string, any> = {};
for (const id of ids) {
  const n = (await query(id))[0];
  if (!n) throw new Error(`fixture id ${id} missing`);
  rects[id] = n.rect;
}
const st = await stats();
const r = await screenshot(`${out}/fixture.png`);
if (r.ok !== true) throw new Error("capture failed");
writeFileSync(`${out}/rects.json`, JSON.stringify({ window_scale: st.window_scale, rects }, null, 2));
console.log(`captured ${out}/fixture.png`);
