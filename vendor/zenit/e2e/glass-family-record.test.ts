/// Record Glass adaptivity family flip transition (in-app recording, one frame per render frame),
/// compare with native
/// scripts/glass_native_model/native_family_transition.swift time curve.
/// Usage: ZENIT_E2E_TEST_FILE=e2e/glass-family-record.test.ts ZENIT_FAMILY_MP4=<dir> bash
/// scripts/run_storybook_e2e.sh
import { mkdirSync } from "node:fs";
import { resolve } from "node:path";
import { clickTestId, sleep, waitForServerReady, mouseMove, startWindowRecording, stopWindowRecording, query, scrollAt } from "./client";
import { test, run, assert, appendLog } from "./runner";
const out = resolve(process.env.ZENIT_FAMILY_MP4 ?? "/tmp/zenit-family-mp4");
test("record family flip in-app", async () => {
  await waitForServerReady();
  mkdirSync(out, { recursive: true });
  await clickTestId("nav.glassadapt"); await sleep(800);
  const st = (await query("story.glassadapt.stage"))[0]!.rect;
  const share = (await query("story.glassadapt.share"))[0]!.rect;
  const cx = st.x + st.w / 2, cy = st.y + st.h / 2;
  await mouseMove(-10, -10); await sleep(500);
  for (const [phase, dy] of [["to-dark", -20000], ["to-light", 20000]] as const) {
    const r = await startWindowRecording(`${out}/${phase}.mp4`, { fps: 60 });
    assert((r as any).ok !== false, `recording start: ${JSON.stringify(r)}`);
    await sleep(400);
    await scrollAt(cx, cy, 0, dy);
    await sleep(1600);
    const s = await stopWindowRecording();
    appendLog(`  ${phase}: ${JSON.stringify(s)}`);
    await sleep(500);
  }
  Bun.write(`${out}/rects.json`, JSON.stringify({ stage: st, share }));
});
await run();
