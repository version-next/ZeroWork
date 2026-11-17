/// Record in-app GlassControls toggle press: press -> hold ZENIT_CTRL_HOLD_MS -> release, matching
/// scripts/glass_native_model/native_appkit_controls.swift tap_switch / hold_switch.
/// Usage: ZENIT_E2E_TEST_FILE=e2e/glass-controls-record.test.ts ZENIT_CTRL_MP4=<dir>
/// ZENIT_CTRL_HOLD_MS=70 bash scripts/run_storybook_e2e.sh
import { mkdirSync } from "node:fs";
import { resolve } from "node:path";
import { clickTestId, sleep, waitForServerReady, mouseMove, mouseDown, mouseUp, startWindowRecording, stopWindowRecording, query, screenshot } from "./client";
import { test, run, assert, appendLog } from "./runner";
const out = resolve(process.env.ZENIT_CTRL_MP4 ?? "/tmp/zenit-ctrl-mp4");
const holdMs = Number(process.env.ZENIT_CTRL_HOLD_MS ?? "70");
// toggle (default) or slider: slider knob center at stage (320, 80), same as storybook.test.ts
// GlassControls case
const target = process.env.ZENIT_CTRL_TARGET ?? "toggle";
test("record toggle press in-app", async () => {
  await waitForServerReady();
  mkdirSync(out, { recursive: true });
  await clickTestId("nav.glasscontrols"); await sleep(800); await mouseMove(-10, -10); await sleep(500);
  const t = (await query("story.glasscontrols.toggle"))[0]?.rect;
  const st = (await query("story.glasscontrols.stage"))[0]?.rect;
  assert(t && st, "toggle / stage missing");
  Bun.write(`${out}/toggle.json`, JSON.stringify(t));
  Bun.write(`${out}/stage.json`, JSON.stringify(st));
  const r = await startWindowRecording(`${out}/hold-${holdMs}.mp4`, { fps: 60 });
  assert((r as any).ok !== false, `recording start: ${JSON.stringify(r)}`);
  const [x, y] = target === "slider" ? [st!.x + 320, st!.y + 80] : [t!.x + t!.w * 0.25, t!.y + t!.h / 2];
  await mouseMove(x, y); await sleep(300);
  const t0 = performance.now();
  await mouseDown(x, y);
  // Hold long enough to capture PNG before release: MP4's YUV 4:2:0 shifts saturated colors (track
  // blue (0,119,249) recorded as (9,123,242)),
  // use PNG for color reference
  if (holdMs >= 500) { await sleep(holdMs - 200); await screenshot(`${out}/held.png`); }
  await sleep(Math.max(0, holdMs - (performance.now() - t0)));
  await mouseUp(x, y);
  appendLog(`  held ${(performance.now() - t0).toFixed(0)}ms`);
  await sleep(1200);
  appendLog(`  ${JSON.stringify(await stopWindowRecording())}`);
});
await run();
