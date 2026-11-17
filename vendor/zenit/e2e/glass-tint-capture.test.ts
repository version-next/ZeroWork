/// Capture GlassEffectContainer tint blend reference page's two stages (white / gray 128), crop to
/// same size as
/// native native_tint_merge.swift (1280x960 @2x) PNG for pixel-by-pixel comparison.
/// Usage: ZENIT_E2E_TEST_FILE=e2e/glass-tint-capture.test.ts ZENIT_TINT_OUT=<dir> bash
/// scripts/run_storybook_e2e.sh
import { mkdirSync } from "node:fs";
import { resolve } from "node:path";
import { query, clickTestId, sleep, waitForServerReady, mouseMove, screenshot, scrollAt } from "./client";
import { test, run, assert, appendLog } from "./runner";
const out = resolve(process.env.ZENIT_TINT_OUT ?? "/tmp/zenit-tint-capture");
test("capture tint fusion stages", async () => {
  await waitForServerReady();
  mkdirSync(out, { recursive: true });
  await clickTestId("nav.glasstint"); await sleep(900); await mouseMove(-10, -10);
  for (const [id, name] of [["story.glasstint.white", "white"], ["story.glasstint.gray", "gray"], ["story.glasstint.overlap", "overlap"]] as const) {
    for (let i = 0; i < 12; i++) {
      const r = (await query(id))[0]?.rect;
      assert(r, `${id} missing`);
      if (r!.y >= 0 && r!.y + r!.h <= 980) break;
      await scrollAt(r!.x + 20, 400, 0, r!.y < 0 ? 120 : -120);
      await sleep(200);
    }
    await sleep(900);
    const r = (await query(id))[0]!.rect;
    const path = `${out}/zenit-${name}-window.png`;
    assert((await screenshot(path)).ok === true, "screenshot");
    await Bun.write(`${out}/zenit-${name}-rect.json`, JSON.stringify(r));
    appendLog(`  ${name}: stage rect ${JSON.stringify(r)}`);
  }
});
await run();
