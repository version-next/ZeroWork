/// Record Glass toolbar story first mount (in-app recording, one frame per render frame): the
/// glass is visible from its first frame in the appearance (light) family and switches to the
/// dark family ~150 ms later over the 0.37 s spring (native behavior, native_family_fresh.swift).
/// Usage: ZENIT_E2E_TEST_FILE=e2e/glass-mount-record.test.ts ZENIT_MOUNT_MP4=<dir> bash
/// scripts/run_storybook_e2e.sh
import { mkdirSync } from "node:fs";
import { resolve } from "node:path";
import { clickTestId, sleep, waitForServerReady, mouseMove, startWindowRecording, stopWindowRecording, query } from "./client";
import { test, run, assert, appendLog } from "./runner";
const out = resolve(process.env.ZENIT_MOUNT_MP4 ?? "/tmp/zenit-mount-mp4");
test("record glass toolbar first mount", async () => {
  await waitForServerReady();
  mkdirSync(out, { recursive: true });
  // ZENIT_MOUNT_STORY=<key>: record that story's first mount instead (default glasstoolbar)
  const story = process.env.ZENIT_MOUNT_STORY ?? "glasstoolbar";
  let share = null, lshare = null;
  if (story === "glasstoolbar") {
    await clickTestId("nav.glasstoolbar"); await sleep(800);
    share = (await query("story.glasstoolbar.dark.share"))[0]!.rect;
    lshare = (await query("story.glasstoolbar.share"))[0]!.rect;
  }
  await clickTestId("nav.glasssplit"); await sleep(600);
  await mouseMove(-10, -10);
  const r = await startWindowRecording(`${out}/mount.mp4`, { fps: 60 });
  assert((r as any).ok !== false, `recording start: ${JSON.stringify(r)}`);
  await sleep(400);
  await clickTestId(`nav.${story}`);
  await sleep(1200);
  appendLog(`  ${JSON.stringify(await stopWindowRecording())}`);
  Bun.write(`${out}/rects.json`, JSON.stringify({ share, lshare }));
});
await run();
