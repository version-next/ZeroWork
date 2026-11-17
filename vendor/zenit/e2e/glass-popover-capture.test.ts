/// Record Glass popover story open / close real window frames (SCStream 60 fps) for frame-by-frame
/// comparison
/// with native native_menu_morph.swift popover (scale, opacity, arrow shape).
/// Usage: [ZENIT_POPOVER_KIND=menu] ZENIT_E2E_TEST_FILE=e2e/glass-popover-capture.test.ts
/// ZENIT_POPOVER_OUT=<dir> bash scripts/run_storybook_e2e.sh
/// outputs <dir>/{open,close}/{frame-XXXX.png, timeline.json, ready.json, inputs.json}
import { readFileSync, writeFileSync, mkdirSync, rmSync, existsSync } from "node:fs";
import { resolve } from "node:path";
import { query, clickTestId, sleep, waitForServerReady, getRpcDir, mouseMove, key, scrollAt } from "./client";
import { test, run, assert, appendLog } from "./runner";
const out_root = resolve(process.env.ZENIT_POPOVER_OUT ?? "/tmp/zenit-popover-capture");
const capture_bin = resolve(process.env.ZENIT_CAPTURE_BIN ?? "/tmp/window-record");
// ZENIT_POPOVER_KIND=menu records menu scenario (story.glassmenu.*)
const kind = process.env.ZENIT_POPOVER_KIND === "menu" ? "glassmenu" : "glasspopover";
test("record popover open/close", async () => {
  await waitForServerReady();
  await clickTestId("nav.glasspopover"); await sleep(800); await mouseMove(-10, -10); await sleep(300);
  const pid = Number(JSON.parse(readFileSync(`${getRpcDir()}/owner.json`, "utf8")).pid);
  let stage = (await query(`story.${kind}.stage`))[0]?.rect;
  assert(stage, "stage must exist");
  // Scroll stage into viewport when below window: menu scenario is below popover scenario
  for (let k = 0; k < 20 && stage!.y > 160; k++) {
    await scrollAt(500, 500, 0, -Math.min(120, stage!.y - 120));
    await sleep(120);
    stage = (await query(`story.${kind}.stage`))[0]?.rect;
  }
  await sleep(400);
  for (const phase of ["open", "close"]) {
    const out = `${out_root}/${phase}`; rmSync(out, { recursive: true, force: true }); mkdirSync(out, { recursive: true });
    const rect = [stage!.x, stage!.y, 400, 240];
    const capture = Bun.spawn([capture_bin, String(pid), "1.2", out, ...rect.map((v) => String(v))], { stdout: "pipe", stderr: "pipe" });
    const deadline = Date.now() + 6000;
    while (!existsSync(`${out}/ready.json`)) { if (capture.exitCode !== null || Date.now() > deadline) throw new Error(`capture did not start: ${await new Response(capture.stderr).text()}`); await sleep(20); }
    const clock = JSON.parse(readFileSync(`${out}/ready.json`, "utf8"));
    await sleep(300);
    const click_unix = Date.now() / 1000;
    if (phase === "open") await clickTestId(`story.${kind}.button`); else await key("escape");
    const click_done_unix = Date.now() / 1000;
    await mouseMove(-10, -10);
    const code = await capture.exited;
    if (code !== 0) throw new Error(`capture failed: ${await new Response(capture.stderr).text()}`);
    writeFileSync(`${out}/inputs.json`, JSON.stringify({ phase, clock, click_unix, click_done_unix, stage, rect }, null, 2));
    appendLog(`  ${phase}: recorded`);
    await sleep(600);
  }
  assert(true, "");
});
await run();
