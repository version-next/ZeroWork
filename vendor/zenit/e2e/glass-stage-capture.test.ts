/// Generic stage capture: scroll each ZENIT_STAGE_IDS (comma-separated test id) into view,
/// capture the full window and record stage bounds for pixel-by-pixel comparison with a native
/// same-geometry screenshot. With ZENIT_STAGE_INACTIVE=1, capture inactive state.
/// Usage: ZENIT_E2E_TEST_FILE=e2e/glass-stage-capture.test.ts ZENIT_STAGE_NAV=glassunion \
///        ZENIT_STAGE_IDS=story.glassunion.stage ZENIT_STAGE_OUT=<dir> bash
///        scripts/run_storybook_e2e.sh
import { mkdirSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import { query, clickTestId, sleep, waitForServerReady, mouseMove, screenshot, scrollAt, getRpcDir } from "./client";
import { test, run, assert, appendLog } from "./runner";
const out = resolve(process.env.ZENIT_STAGE_OUT ?? "/tmp/zenit-stage-capture");
const nav = process.env.ZENIT_STAGE_NAV ?? "glassunion";
const ids = (process.env.ZENIT_STAGE_IDS ?? "story.glassunion.stage").split(",");
test("capture stages", async () => {
  await waitForServerReady();
  mkdirSync(out, { recursive: true });
  await clickTestId(`nav.${nav}`); await sleep(900); await mouseMove(-10, -10);
  for (const id of ids) {
    const name = id.split(".").pop()!;
    for (let i = 0; i < 12; i++) {
      const r = (await query(id))[0]?.rect;
      assert(r, `${id} missing`);
      if (r!.y >= 0 && r!.y + r!.h <= 980) break;
      await scrollAt(r!.x + 20, 400, 0, r!.y < 0 ? 120 : -120);
      await sleep(200);
    }
    await sleep(900);
    const r = (await query(id))[0]!.rect;
    if (process.env.ZENIT_STAGE_INACTIVE) {
      // Real activation (app must start with ZENIT_E2E_REAL_ACTIVATION=1): bring tested app to
      // foreground first
      const pid = Number(JSON.parse(readFileSync(`${getRpcDir()}/owner.json`, "utf8")).pid);
      Bun.spawnSync(["osascript", "-e", `tell application "System Events" to set frontmost of (first process whose unix id is ${pid}) to true`]);
      await sleep(1500);
    }
    assert((await screenshot(`${out}/${name}-window.png`)).ok === true, "screenshot");
    if (process.env.ZENIT_STAGE_INACTIVE) {
      // Hand activation to Finder: tested window still visible but not active (in native,
      // Glass.tint desaturates when inactive)
      Bun.spawnSync(["osascript", "-e", 'tell application "Finder" to activate']);
      await sleep(1500);
      assert((await screenshot(`${out}/${name}-inactive-window.png`)).ok === true, "inactive screenshot");
    }
    await Bun.write(`${out}/${name}-rect.json`, JSON.stringify(r));
    appendLog(`  ${name}: rect ${JSON.stringify(r)}`);
  }
});
await run();
