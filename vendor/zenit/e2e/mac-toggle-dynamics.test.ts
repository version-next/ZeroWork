// Per-frame knob timeline of the macOS GlassToggle (story glasscontrols) on a locked 60 Hz clock,
// for scripts/glass_native_model/compare_toggle_dynamics.py against native_controls_probe
// `anim-switch` (NSSwitch layer model values). Press the off switch's knob, release after
// ZENIT_TOGGLE_UP_MS (default 70: the probe's tap; 1000: its hold), then read the knob's frame and
// opacity every frame for 1.2 s after the release. Launch with ZENIT_STORYBOOK_STORY=glasscontrols
// ZENIT_E2E_TEST_FILE=e2e/mac-toggle-dynamics.test.ts ZENIT_TOGGLE_OUT=<file.json>. No thresholds.
import { writeFileSync } from "node:fs";
import { query, waitForServerReady, sleep, mouseMove, mouseDown, mouseUp, request } from "./client";
const out = process.env.ZENIT_TOGGLE_OUT!;
const upMs = Number(process.env.ZENIT_TOGGLE_UP_MS ?? "70");
await waitForServerReady();
await sleep(1500);
const toggle = (await query("story.glasscontrols.toggle"))[0];
if (!toggle) throw new Error("toggle missing");
const STEP = 1000 / 60;
const r = await request("POST", "/clock", { step_ms: STEP, locked: true });
if (r.error) throw new Error(`clock: ${JSON.stringify(r)}`);
const advance = async (ms: number) => {
  const a = await request("POST", "/clock/advance", { ms });
  if (a.error) throw new Error(`advance: ${JSON.stringify(a)}`);
  for (let i = 0; i < 2000 && ((await request("GET", "/stats")) as any).clock_budget_ms > 0; i++) await sleep(5);
};
const rows: Array<{ t: number; x: number; y: number; w: number; h: number; white: number }> = [];
const sample = async (t: number) => {
  const k = (await query("story.glasscontrols.toggle.knob"))[0];
  if (!k) throw new Error("knob missing");
  rows.push({ t, x: k.rect.x - toggle.rect.x, y: k.rect.y - toggle.rect.y, w: k.rect.w, h: k.rect.h, white: k.opacity ?? 1 });
};
await advance(STEP * 6);
// the off knob's centre: inset 2 + half its 32 pt width
const x = toggle.rect.x + 2 + 16, y = toggle.rect.y + toggle.rect.h / 2;
await mouseMove(x, y);
await mouseDown(x, y);
let t = 0;
await sample(t);
while (t + STEP <= upMs) {
  await advance(STEP);
  t += STEP;
  await sample(t);
}
await mouseUp(x, y);
const up = t;
for (let k = 0; k < 72; k++) {
  await advance(STEP);
  t += STEP;
  await sample(t);
}
writeFileSync(out, JSON.stringify({ up, rows }, null, 2));
console.log(`captured ${out}`);
