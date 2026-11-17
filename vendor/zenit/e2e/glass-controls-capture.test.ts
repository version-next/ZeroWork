/// Record GlassSlider / GlassToggle press-drag-release real window frames for frame-by-frame
/// comparison
/// with native native_slider_toggle.swift (slider / toggle / toggle-drag).
/// Usage: ZENIT_E2E_TEST_FILE=e2e/glass-controls-capture.test.ts ZENIT_CONTROLS_OUT=<dir> bash
/// scripts/run_storybook_e2e.sh
/// outputs <dir>/<mode>/{frame-XXXX.png, timeline.json, ready.json, inputs.json}
import { readFileSync, writeFileSync, mkdirSync, rmSync, existsSync } from "node:fs";
import { resolve } from "node:path";
import { query, clickTestId, sleep, waitForServerReady, getRpcDir, mouseMove, mouseDown, mouseUp } from "./client";
import { test, run, assert, appendLog } from "./runner";
const out_root = resolve(process.env.ZENIT_CONTROLS_OUT ?? "/tmp/zenit-controls-capture");
const capture_bin = resolve(process.env.ZENIT_CAPTURE_BIN ?? "/tmp/window-record");
// Same timeline as native script (seconds relative to recording start)
const modes: Array<{ name: string; knob: [number, number]; down: number; drag?: [number, number]; up: number }> = [
  { name: "slider", knob: [320, 80], down: 0.25, drag: [0.85, 60], up: 1.65 },
  { name: "toggle", knob: [311, 170], down: 0.25, up: 0.95 },
  { name: "toggle-drag", knob: [311, 170], down: 0.25, drag: [0.75, 16], up: 1.35 },
];
test("record glass controls", async () => {
  await waitForServerReady();
  await clickTestId("nav.glasscontrols"); await sleep(800); await mouseMove(-10, -10); await sleep(300);
  const pid = Number(JSON.parse(readFileSync(`${getRpcDir()}/owner.json`, "utf8")).pid);
  const stage = (await query("story.glasscontrols.stage"))[0]?.rect;
  assert(stage, "stage must exist");
  for (const m of modes) {
    // Start fresh each time: re-enter story
    await clickTestId("nav.glasspopover"); await sleep(300); await clickTestId("nav.glasscontrols"); await sleep(700);
    const out = `${out_root}/${m.name}`; rmSync(out, { recursive: true, force: true }); mkdirSync(out, { recursive: true });
    const rect = [stage!.x, stage!.y, 640, 240];
    const capture = Bun.spawn([capture_bin, String(pid), "2.6", out, ...rect.map((v) => String(v))], { stdout: "pipe", stderr: "pipe" });
    const deadline = Date.now() + 6000;
    while (!existsSync(`${out}/ready.json`)) { if (capture.exitCode !== null || Date.now() > deadline) throw new Error(`capture did not start: ${await new Response(capture.stderr).text()}`); await sleep(20); }
    const clock = JSON.parse(readFileSync(`${out}/ready.json`, "utf8"));
    const t0 = Date.now() / 1000;
    const at = async (t: number) => { const w = t0 + t - Date.now() / 1000; if (w > 0) await sleep(w * 1000); };
    const x0 = stage!.x + m.knob[0], y0 = stage!.y + m.knob[1];
    const ev: Record<string, number> = {};
    await mouseMove(x0, y0);
    await at(m.down); ev.down = Date.now() / 1000; await mouseDown(x0, y0);
    let x = x0;
    if (m.drag) {
      await at(m.drag[0]); ev.drag = Date.now() / 1000;
      const steps = 15;
      for (let k = 1; k <= steps; k++) { x = x0 + (m.drag[1] * k) / steps; await mouseMove(x, y0); await sleep(500 / steps); }
    }
    await at(m.up); ev.up = Date.now() / 1000; await mouseUp(x, y0);
    await mouseMove(-10, -10);
    const code = await capture.exited;
    if (code !== 0) throw new Error(`capture failed: ${await new Response(capture.stderr).text()}`);
    writeFileSync(`${out}/inputs.json`, JSON.stringify({ mode: m.name, clock, events: ev, stage, rect }, null, 2));
    appendLog(`  ${m.name}: recorded`);
  }
  assert(true, "");
});
await run();
