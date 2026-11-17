/// Single story screenshot: GlassChrome (app header glass).
/// Glass is eyeball validation, pixel assertions can't catch 'using wrong shader', this script only
/// delivers
/// image for eyeball verification, incidentally assert click actually hits + screenshot non-empty.
import { mkdir, stat } from "node:fs/promises";
import { clickTestId, query, screenshot, sleep, waitFor, waitForServerReady } from "./client";

const OUT = process.env.GLASSCHROME_OUT ?? "/tmp/glasschrome";
await mkdir(OUT, { recursive: true });

async function shot(name: string) {
  const path = `${OUT}/${name}.png`;
  const r = await screenshot(path);
  if (r.ok !== true) throw new Error(`screenshot rpc not ok for ${name}: ${JSON.stringify(r)}`);
  const size = (await stat(path)).size;
  if (size < 3000) throw new Error(`screenshot ${name} suspiciously small (${size} bytes)`);
  console.log(`shot ${name} -> ${path} (${size} bytes)`);
}

async function click(testId: string) {
  const r = await clickTestId(testId);
  if (!r || (r as any).ok === false || (r as any).hit === false) {
    throw new Error(`click ${testId} did not hit: ${JSON.stringify(r)}`);
  }
  await sleep(400);
}

await waitForServerReady();
await sleep(1500); // First frame + first story built before clicking, else nav click misses (RPC still returns ok)
await click("nav.glasschrome");

// Don't trust click return value: verify story actually switched (ladder pill exists)
const marker = await waitFor(async () => {
  const n = await query("story.glasschrome.scrolldown");
  return n.length > 0 ? n : null;
}, 15000);
console.log(`story active, marker rect=${JSON.stringify(marker[0].rect)}`);
await sleep(500);
await shot("01-initial");

for (let i = 1; i <= 2; i++) {
  await click("story.glasschrome.scrolldown");
  await shot(`0${i + 1}-scrolled-${i}`);
}

console.log("done");
