/// Record Glass Split expand / collapse with in-app recording (one frame per rendered frame, with
/// timestamps), profile animation smoothness.
/// Usage: ZENIT_E2E_TEST_FILE=e2e/glass-split-record.test.ts ZENIT_SPLIT_MP4=<dir> bash
/// scripts/run_storybook_e2e.sh
/// ZENIT_SPLIT_REVERSE_MS=150: instead record 'click split -> wait 150ms -> click again
/// (mid-reverse)', match
/// scripts/glass_native_model/native_glass_scenarios.swift toolbar "1@0,0@0.15".
import { mkdirSync } from "node:fs";
import { resolve } from "node:path";
import { clickTestId, sleep, waitForServerReady, mouseMove, startWindowRecording, stopWindowRecording, query } from "./client";
import { test, run, assert, appendLog } from "./runner";
const out = resolve(process.env.ZENIT_SPLIT_MP4 ?? "/tmp/zenit-split-mp4");
test("record split/merge in-app", async () => {
  await waitForServerReady();
  mkdirSync(out, { recursive: true });
  await clickTestId("nav.glasssplit"); await sleep(800); await mouseMove(-10, -10); await sleep(500);
  const st = (await query("story.glasssplit.stage1"))[0]?.rect;
  appendLog(`  stage1 ${JSON.stringify(st)}`);
  const reverseMs = process.env.ZENIT_SPLIT_REVERSE_MS;
  const phases = reverseMs ? [`rev-${reverseMs}`] : ["bar-split", "bar-merge"];
  for (const phase of phases) {
    const r = await startWindowRecording(`${out}/${phase}.mp4`, { fps: 60 });
    assert((r as any).ok !== false, `recording start: ${JSON.stringify(r)}`);
    await sleep(300);
    const t0 = performance.now();
    await clickTestId("story.glasssplit.splitbtn");
    if (reverseMs) {
      await sleep(Math.max(0, Number(reverseMs) - (performance.now() - t0)));
      await clickTestId("story.glasssplit.splitbtn");
      appendLog(`  reverse after ${(performance.now() - t0).toFixed(0)}ms`);
    }
    await sleep(1400);
    const s = await stopWindowRecording();
    appendLog(`  ${phase}: ${JSON.stringify(s)}`);
    await sleep(500);
  }
  Bun.write(`${out}/stage.json`, JSON.stringify(st));
});
await run();
