/// glasslab-real-scroll-probe.ts: sampling probe paired with CGEvent real scroll wheel (not a test)
/// Usage:
///   bun e2e/glasslab-real-scroll-probe.ts setup   -> navigate to glasslab, print glass rect
///   bun e2e/glasslab-real-scroll-probe.ts capture <outdir> <n> <interval_ms> <rect_json>
///       -> burst n frames and output glass region mean RGB and frame-to-frame delta
import { health, query, clickTestId, screenshot, waitForServerReady, waitFor, sleep } from "./client";
import { decodePng } from "./png";

function meanRGB(pngPath: string, rect: { x: number; y: number; w: number; h: number }): [number, number, number] {
  const png = decodePng(pngPath);
  const scale = png.width / 1100;
  const x0 = Math.max(0, Math.round(rect.x * scale));
  const y0 = Math.max(0, Math.round(rect.y * scale));
  const x1 = Math.min(png.width, Math.round((rect.x + rect.w) * scale));
  const y1 = Math.min(png.height, Math.round((rect.y + rect.h) * scale));
  let r = 0, g = 0, b = 0, n = 0;
  for (let y = y0; y < y1; y += 2) {
    for (let x = x0; x < x1; x += 2) {
      const i = (y * png.width + x) * png.channels;
      r += png.pixels[i]; g += png.pixels[i + 1]; b += png.pixels[i + 2]; n++;
    }
  }
  return [r / n, g / n, b / n];
}

const mode = process.argv[2];
await waitForServerReady(15000);
await health();

if (mode === "setup") {
  await clickTestId("nav.glasslab");
  const q = await waitFor(async () => {
    const r = await query("story.glasslab.drag");
    return r.length === 1 && r[0].rect.w > 0 ? r : null;
  }, 6000, 50);
  await sleep(800);
  console.log(JSON.stringify(q[0].rect));
} else if (mode === "capture") {
  const outdir = process.argv[3];
  const n = parseInt(process.argv[4], 10);
  const interval = parseInt(process.argv[5], 10);
  const rect = JSON.parse(process.argv[6]);
  const means: [number, number, number][] = [];
  for (let i = 0; i < n; i++) {
    const p = `${outdir}/frame-${String(i).padStart(3, "0")}.png`;
    await screenshot(p);
    means.push(meanRGB(p, rect));
    await sleep(interval);
  }
  let max = 0;
  for (let i = 1; i < means.length; i++) {
    const d = Math.max(
      Math.abs(means[i][0] - means[i - 1][0]),
      Math.abs(means[i][1] - means[i - 1][1]),
      Math.abs(means[i][2] - means[i - 1][2]),
    );
    if (d > max) max = d;
  }
  for (let i = 0; i < means.length; i++) {
    console.log(`frame ${i}: ${means[i].map(v => v.toFixed(1)).join(",")}`);
  }
  console.log(`MAX_DELTA ${max.toFixed(2)}`);
}
