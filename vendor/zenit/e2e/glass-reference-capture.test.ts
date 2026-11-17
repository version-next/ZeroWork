import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { createHash } from "node:crypto";
import { resolve } from "node:path";
import { request, query, screenshot, stats, waitForServerReady, sleep } from "./client";
import type { GlassScene } from "./glass-fixtures";
import { distance } from "./glass-fidelity";
import { decodePng } from "./png";
const fixtures=process.env.ZENIT_GLASS_FIXTURES!;
const out=resolve(process.env.ZENIT_GLASS_ACTUAL??"reports/glass-native-fidelity/zenit");
const scenes: GlassScene[]=JSON.parse(readFileSync(`${fixtures}/scenes.json`,"utf8"));
mkdirSync(out,{recursive:true});
const captured_at=new Date().toISOString(),captures:any[]=[];
const hash=(path:string)=>createHash("sha256").update(readFileSync(path)).digest("hex");
await waitForServerReady();
for(const [index,scene] of scenes.entries()) {
  const res=await request("POST","/glass/setup",{index});
  if(res.ok!==true||res.case!==scene.id) throw new Error(`scene setup failed: ${JSON.stringify(res)}`);
  await sleep(1600);
  const measured=await request("GET","/glass/state");
  // A completed background readback must be consumed before the window idles.
  // These broad ranges detect the previous scene's stale light/dark value.
  const range=scene.background.includes("light")?[.4,1]:scene.background==="dark"?[0,.08]:[.05,.35];
  if(!Number.isFinite(measured.luminance)||measured.luminance<range[0]||measured.luminance>range[1])
    throw new Error(`stale backdrop measurement ${scene.id}: ${JSON.stringify(measured)}`);
  if(measured.glass_pipeline_failed||measured.blur_pipeline_failed||measured.calibration_active)
    throw new Error(`invalid production capture ${scene.id}: ${JSON.stringify(measured)}`);
  const node=(await query("glass.reference"))[0];
  if(!node)throw new Error("production glass missing");
  for(const [key,want] of Object.entries({x:scene.x,y:scene.y,w:scene.w,h:scene.h})) {
    if(Math.abs((node.rect as any)[key]-want)>0.25) throw new Error(`geometry mismatch ${scene.id}: ${JSON.stringify(node.rect)}`);
  }
  const r=await screenshot(`${out}/${scene.id}.png`);
  if(r.ok!==true) throw new Error(`capture failed ${scene.id}`);
  await sleep(100);
  const idle=await screenshot(`${out}/${scene.id}-idle.png`);
  if(idle.ok!==true) throw new Error(`idle capture failed ${scene.id}`);
  captures.push({id:scene.id,geometry:node.rect,state:measured,
    sha256:hash(`${out}/${scene.id}.png`),idle_sha256:hash(`${out}/${scene.id}-idle.png`)});
  console.log(`captured ${scene.id}`);
}
const settled=await stats();
await sleep(400);
const idle=await stats();
if(idle.frame_count-settled.frame_count>2)throw new Error("stable material kept the GPU frame loop awake");
// Fractional requested padding must not shift the physical blit's sampling
// origin. An unwarped sharp transmission reveals even a subpixel grid drift.
for (const id of ["mixed-clear-capsule", "mixed-clear-circle", "dark-clear-edge"]) {
  const index=scenes.findIndex(s=>s.id===id), scene=scenes[index];
  if (!(await request("POST","/glass/setup",{index})).ok) throw new Error("registration setup failed");
  if (!(await request("POST","/glass/tune",{glass_intensity:0,blur_level:0,backdrop_distance:0,backdrop_brightness:1})).ok) throw new Error("registration tune failed");
  await sleep(700);
  const path=`${out}/registration-${id}.png`;
  if (!(await screenshot(path)).ok) throw new Error("registration capture failed");
  const actual=decodePng(path), expected=decodePng(`${fixtures}/${scene.background}.png`);
  if(actual.width!==1280||actual.height!==960)throw new Error("registration dimensions invalid");
  let sse=0,n=0,max=0;
  for(let y=0;y<960;y++)for(let x=0;x<1280;x++)if(distance((x+.5)/2,(y+.5)/2,scene)<-8) {
    for(let c=0;c<3;c++) {
      const delta=actual.pixels[(y*1280+x)*actual.channels+c]-expected.pixels[(y*1280+x)*expected.channels+c];
      sse+=delta*delta;n++;max=Math.max(max,Math.abs(delta));
    }
  }
  const rmse=Math.sqrt(sse/n);
  if(max>2||rmse>1.2)throw new Error(`unwarped backdrop shifted ${id}: RMSE=${rmse}, max=${max}`);
  console.log(`PASS unwarped physical registration ${id}: RMSE=${rmse.toFixed(3)}, max=${max}`);
}
writeFileSync(`${out}/metadata.json`,JSON.stringify({renderer:"Zenit.production.Metal",run_id:process.env.ZENIT_GLASS_GATE_RUN_ID??null,
  captured_at,scale:2,viewport:[640,480],cases:captures},null,2));
