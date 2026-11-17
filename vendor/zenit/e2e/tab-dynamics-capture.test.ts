// Replay a native iOS tab-bar gesture (the touches of a GlassProbe trace, run_uitest.sh gesture
// `tabbar`) on the storybook tab bar (story glassiosbars) on a locked 60 Hz animation clock, and
// capture every frame: a screenshot plus the layer state (lens, plate, portal, platter, accent
// copies: rect / opacity / scale). Feeds scripts/glass_native_model/ios/compare_tab_dynamics.py.
//   ZENIT_STORYBOOK_STORY=glassiosbars ZENIT_E2E_HIDE_VIRTUAL_CURSOR=1
//   ZENIT_E2E_TEST_FILE=e2e/tab-dynamics-capture.test.ts
//   ZENIT_DYN_TRACE=<native trace.json> ZENIT_DYN_OUT=<dir>
// Frames are captured inside the gesture windows only (each touch-down - 0.1 s to its touch-up +
// 1.2 s); the clock runs through the gaps.
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { query, screenshot, waitForServerReady, sleep, mouseMove, mouseDown, mouseUp, request } from "./client";

const out = process.env.ZENIT_DYN_OUT!;
const trace = JSON.parse(readFileSync(process.env.ZENIT_DYN_TRACE!, "utf8"));
mkdirSync(out, { recursive: true });
await waitForServerReady();
await mouseMove(-10, -10);
await sleep(2500);

const tb = "story.iosbars.tb";
const home = (await query("story.iosbars.tab.home"))[0];
if (!home) throw new Error("tab bar missing");
// native window pt -> ours: the Home tab button is at (25, 795) natively
const ox = home.rect.x - 25, oy = home.rect.y - 795;

type Touch = { t: number; phase: number; x: number; y: number };
const touches: Touch[] = trace.touches.map((t: any) => ({ t: t.t, phase: t.phase, x: t.x, y: t.y }));
const downs = touches.filter((t) => t.phase === 0).map((t) => t.t);
const ups = touches.filter((t) => t.phase === 3).map((t) => t.t);
const windows = downs.map((d, i) => [d - 0.1, (ups[i] ?? d) + 1.2]);
const inWindow = (t: number) => windows.some(([a, b]) => t >= a && t <= b);

const STEP = 1000 / 60;
let r = await request("POST", "/clock", { step_ms: STEP, locked: true });
if (r.error) throw new Error(`clock: ${JSON.stringify(r)}`);
const advance = async (ms: number) => {
  const a = await request("POST", "/clock/advance", { ms });
  if (a.error) throw new Error(`advance: ${JSON.stringify(a)}`);
  for (let i = 0; i < 2000 && ((await request("GET", "/stats")) as any).clock_budget_ms > 0; i++) await sleep(5);
};

const T0 = downs[0] - 0.3;
const T1 = (ups[ups.length - 1] ?? downs[downs.length - 1]) + 1.3;
const ids = ["lens", "plate", "portal", "platter", "accent.0", "accent.1", "accent.2"];
const frames: any[] = [];
let next = 0;
let down = false;
await advance(STEP * 6);
for (let k = 0; T0 + k / 60 <= T1; k++) {
  const t = T0 + k / 60;
  // inject the touches due by this frame
  while (next < touches.length && touches[next].t <= t) {
    const e = touches[next++];
    const x = e.x + ox, y = e.y + oy;
    if (e.phase === 0) { await mouseMove(x, y); await mouseDown(x, y); down = true; }
    else if (e.phase === 3) { await mouseUp(x, y); down = false; }
    else if (down) await mouseMove(x, y);
  }
  await advance(STEP);
  if (!inWindow(t)) continue;
  const rec: any = { t, k };
  for (const id of ids) {
    const n = (await query(`${tb}.${id}`))[0];
    if (n) rec[id] = { rect: n.rect, opacity: n.opacity ?? 1, scale_x: n.scale_x ?? 1, scale_y: n.scale_y ?? 1 };
  }
  const png = `${out}/f_${String(k).padStart(5, "0")}.png`;
  const s = await screenshot(png);
  if (s.ok !== true) throw new Error(`screenshot ${k}`);
  rec.png = png;
  frames.push(rec);
}
await request("POST", "/clock", { step_ms: 0 });
writeFileSync(`${out}/frames.json`, JSON.stringify({ offset: [ox, oy], touches, frames }, null, 1));
console.log(`captured ${frames.length} frames`);
