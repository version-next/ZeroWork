// Capture the macOS slider / switch knobs (story glasscontrols) at rest and held, for comparison
// with scripts/glass_native_model/native_controls_probe.swift (same 640 x 240 layout). Launch with
// ZENIT_STORYBOOK_STORY=glasscontrols ZENIT_E2E_TEST_FILE=e2e/mac-knob-capture.test.ts
// ZENIT_KNOB_OUT=<dir>. No thresholds: the comparison is offline.
import { writeFileSync, mkdirSync } from "node:fs";
import { query, screenshot, waitForServerReady, sleep, stats, mouseDown, mouseUp } from "./client";
const out = process.env.ZENIT_KNOB_OUT!;
mkdirSync(out, { recursive: true });
await waitForServerReady();
await sleep(2000);
const stage = (await query("story.glasscontrols.stage"))[0];
if (!stage) throw new Error("stage missing");
const st = await stats();
const shots: Record<string, string> = {};
const knobs: Record<string, unknown> = {};
async function shot(name: string) {
  const path = `${out}/${name}.png`;
  const r = await screenshot(path);
  if (r.ok !== true) throw new Error(`capture ${name} failed`);
  shots[name] = path;
}
await shot("rest");
// held: stage-local knob centres (slider thumb 320,80; off switch knob 311,170)
for (const [name, x, y] of [["slider", 320, 80], ["switch", 311, 170]] as const) {
  await mouseDown(stage.rect.x + x, stage.rect.y + y);
  await sleep(1000);
  await shot(`held_${name}`);
  knobs[name] = (await query(name === "switch" ? "story.glasscontrols.toggle.knob" : "story.glasscontrols.slider.knob"))[0]?.rect;
  await mouseUp(stage.rect.x + x, stage.rect.y + y);
  await sleep(1000);
}
writeFileSync(`${out}/meta.json`, JSON.stringify({ window_scale: st.window_scale, stage: stage.rect, shots, knobs }, null, 2));
console.log(`captured ${out}`);
