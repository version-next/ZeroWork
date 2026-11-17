/// Record Glass Split & Merge story real window frames (SCStream 60 fps) for frame-by-frame
/// comparison.
/// Usage: ZENIT_E2E_TEST_FILE=e2e/glass-split-capture.test.ts ZENIT_SPLIT_OUT=<dir> bash
/// scripts/run_storybook_e2e.sh
/// outputs <dir>/<phase>/{frame-XXXX.png, timeline.json, ready.json, inputs.json}
import { readFileSync, writeFileSync, mkdirSync, rmSync, existsSync } from "node:fs";
import { resolve } from "node:path";
import { query, clickTestId, sleep, waitForServerReady, getRpcDir, mouseMove } from "./client";
import { test, run, assert, appendLog } from "./runner";
const out_root = resolve(process.env.ZENIT_SPLIT_OUT ?? "/tmp/zenit-split-capture");
const capture_bin = resolve(process.env.ZENIT_CAPTURE_BIN ?? "/tmp/window-record");
const phases: Array<[string, string]> = [["bar-split", "story.glasssplit.splitbtn"], ["bar-merge", "story.glasssplit.splitbtn"], ["card-split", "story.glasssplit.cardbtn"], ["card-merge", "story.glasssplit.cardbtn"]];
test("record split/merge phases", async () => {
  await waitForServerReady();
  await clickTestId("nav.glasssplit"); await sleep(800); await mouseMove(-10, -10); await sleep(300);
  const pid = Number(JSON.parse(readFileSync(`${getRpcDir()}/owner.json`, "utf8")).pid);
  const stage1 = (await query("story.glasssplit.stage1"))[0]?.rect, stage2 = (await query("story.glasssplit.stage2"))[0]?.rect;
  assert(stage1 && stage2, "stages must exist");
  for (const [phase, btn] of phases) {
    const out = `${out_root}/${phase}`; rmSync(out, { recursive: true, force: true }); mkdirSync(out, { recursive: true });
    const st = phase.startsWith("bar") ? stage1! : stage2!;
    // Window has title bar: record extra margin ring, compare script positions stage by gray 128
    // background within frame
    const rect = [st.x - 20, st.y - 10, 680, st.h + 110];
    const capture = Bun.spawn([capture_bin, String(pid), "1.8", out, ...rect.map((v) => String(v))], { stdout: "pipe", stderr: "pipe" });
    const deadline = Date.now() + 6000;
    while (!existsSync(`${out}/ready.json`)) { if (capture.exitCode !== null || Date.now() > deadline) throw new Error(`capture did not start: ${await new Response(capture.stderr).text()}`); await sleep(20); }
    const clock = JSON.parse(readFileSync(`${out}/ready.json`, "utf8"));
    await sleep(350);
    const click_unix = Date.now() / 1000;
    await clickTestId(btn);
    const click_done_unix = Date.now() / 1000;
    await mouseMove(-10, -10);
    const code = await capture.exited;
    if (code !== 0) throw new Error(`capture failed: ${await new Response(capture.stderr).text()}`);
    writeFileSync(`${out}/inputs.json`, JSON.stringify({ phase, clock, click_unix, click_done_unix, stage1, stage2, rect }, null, 2));
    appendLog(`  ${phase}: recorded (${await new Response(capture.stdout).text()}`.trim() + ")");
    await sleep(900);
  }
  assert(true, "");
});
await run();
