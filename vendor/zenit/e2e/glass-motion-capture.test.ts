// Capture the production app with the same lossless SCStream path as SwiftUI.
// Input timestamps come from the main-thread route which dispatches real Cx
// events, rather than from the controller's file-RPC request send time.
import { readFileSync, writeFileSync, mkdirSync, rmSync, existsSync } from "node:fs";
import { resolve } from "node:path";
import { request, waitForServerReady, getRpcDir, sleep } from "./client";
const root = resolve(process.env.ZENIT_GLASS_ROOT ?? "reports/glass-native-fidelity");
const actions: string[] = (process.env.ZENIT_GLASS_MOTION_ACTIONS ?? "scroll,drag,morph,hover_press_release").split(",");
await waitForServerReady();
const pid = Number(JSON.parse(readFileSync(`${getRpcDir()}/owner.json`, "utf8")).pid);
if (!Number.isSafeInteger(pid) || pid <= 0) throw new Error("Invalid production owner PID");
for (const action of actions) {
  const out = `${root}/native-motion/zenit/${action}`;
  rmSync(out, { recursive: true, force: true }); mkdirSync(out, { recursive: true });
  if (!(await request("POST", "/glass/motion/setup", { action })).ok) throw new Error(`Motion setup failed: ${action}`);
  await sleep(1600);
  const before = await request("GET", "/glass/state");
  if (before.calibration_active || before.glass_pipeline_failed || before.blur_pipeline_failed) throw new Error("Motion production fallback");
  const capture = Bun.spawn([`${root}/native-motion-capture`, "window", String(pid), "5", out], { stdout: "pipe", stderr: "pipe" });
  try {
    const deadline = Date.now() + 6000;
    while (!existsSync(`${out}/ready.json`)) {
      if (capture.exitCode !== null || Date.now() > deadline)
        throw new Error(`SCStream did not start: ${await new Response(capture.stderr).text()}`);
      await sleep(20);
    }
    const clock = JSON.parse(readFileSync(`${out}/ready.json`, "utf8"));
    if (clock.pid !== pid) throw new Error("Captured wrong production process");
    await sleep(300);
    const events: any[] = [];
    async function input(label: string, payload: object) {
      const received = await request("POST", "/glass/motion/event", payload);
      if (!received.ok || !Number.isFinite(received.unix_time)) throw new Error(`Input not dispatched: ${label}`);
      events.push({ name: label, time: clock.host_time + received.unix_time - clock.unix_time, ...received });
      // Keep dispatched input evidence even when a subsequent state assertion
      // fails; otherwise the failed action loses its useful diagnostics.
      writeFileSync(`${out}/inputs.json`, JSON.stringify({ run_id: process.env.ZENIT_GLASS_GATE_RUN_ID ?? null, clock, before, events }, null, 2));
    }
    if (action === "morph") {
      await input("morph", { name: "morph" });
    } else if (action === "hover_press_release") {
      await input("hover", { name: "move", x: 280, y: 192 }); await sleep(500);
      await input("press", { name: "down", x: 280, y: 192 }); await sleep(500);
      await input("release", { name: "up", x: 280, y: 192 }); await sleep(500);
      await input("leave", { name: "move", x: 60, y: 60 });
      if (!events[0].hovered || !events[1].pressed || events[2].pressed || events[3].hovered) throw new Error(`Production interaction did not reach its required states: ${JSON.stringify(events)}`);
    } else if (action === "drag") {
      await input("drag_start", { name: "down" });
      for (let i = 1; i <= 8; i++) {
        await sleep(40);
        await input(`drag_${i}`, { name: "move", x: 320+i*10, y: 240+i*3 });
      }
      await input("drag_end", { name: "up", x: 400, y: 264 });
      if (events.at(-1).drag_moves < 8) throw new Error("Drag binding did not receive movement");
    } else if (action === "scroll") {
      for (let i = 1; i <= 8; i++) {
        await sleep(40);
        await input(`scroll_${i}`, { name: "scroll", x: 100, y: 100, dy: -8 });
      }
      if (Math.abs(events.at(-1).scroll_y - 64) > 0.25) throw new Error("ScrollArea did not move by 64 logical pixels");
    } else throw new Error(`Unknown action ${action}`);
    writeFileSync(`${out}/inputs.json`, JSON.stringify({ run_id: process.env.ZENIT_GLASS_GATE_RUN_ID ?? null, clock, before, events }, null, 2));
    const code = await capture.exited;
    if (code !== 0) throw new Error(`Window capture failed (${code}): ${await new Response(capture.stderr).text()}`);
    const timeline=JSON.parse(readFileSync(`${out}/timeline.json`,"utf8"));
    if(timeline.active_key_window!==true)throw new Error("Production window lost activation; reject this motion capture");
    console.log(`${action}: ${await new Response(capture.stdout).text()}`);
  } finally {
    if (capture.exitCode === null) { capture.kill("SIGTERM"); await capture.exited; }
  }
}
