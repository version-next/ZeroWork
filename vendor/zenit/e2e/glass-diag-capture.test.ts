// Diagnostic capture: render every scene of a fixture set through the production
// GlassBox probe and save raw window captures. No thresholds; this feeds the
// optical measurement scripts (phase/MTF/veil) that compare against the native
// captures of the same fixtures. Optional tune patch for pipeline calibration.
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { resolve } from "node:path";
import { request, query, screenshot, waitForServerReady, sleep } from "./client";
const fixtures=process.env.ZENIT_GLASS_FIXTURES!;
const out=resolve(process.env.ZENIT_GLASS_ACTUAL!);
const tune=process.env.ZENIT_GLASS_TUNE?JSON.parse(process.env.ZENIT_GLASS_TUNE):null;
const filter=process.env.ZENIT_GLASS_SCENE_FILTER?new RegExp(process.env.ZENIT_GLASS_SCENE_FILTER):null;
const scenes:any[]=JSON.parse(readFileSync(`${fixtures}/scenes.json`,"utf8"));
mkdirSync(out,{recursive:true});
await waitForServerReady();
const captured:any[]=[];
for(const [index,scene] of scenes.entries()) {
  if(filter&&!filter.test(scene.id)) continue;
  const res=await request("POST","/glass/setup",{index});
  if(res.ok!==true||res.case!==scene.id) throw new Error(`scene setup failed: ${JSON.stringify(res)}`);
  if(tune) { const t=await request("POST","/glass/tune",tune); if(t.ok!==true) throw new Error("tune failed"); }
  await sleep(tune?700:1300);
  // The first scene after launch can precede the first backdrop luminance readback (srgb -1):
  // the adaptive family has not been evaluated yet. Wait for it, then for the family crossfade.
  let st=await request("GET","/glass/state");
  let waited=false;
  for(let i=0;i<30&&!(st.luminance_srgb>=0);i++){ waited=true; await sleep(100); st=await request("GET","/glass/state"); }
  if(waited){ await sleep(800); st=await request("GET","/glass/state"); }
  console.log(`state ${scene.id} lum=${st.luminance} srgb=${st.luminance_srgb} dark=${st.family_dark}`);
  const node=(await query("glass.reference"))[0];
  if(!node) throw new Error("production glass missing");
  for(const [key,want] of Object.entries({x:scene.x,y:scene.y,w:scene.w,h:scene.h}))
    if(Math.abs((node.rect as any)[key]-want)>0.25) throw new Error(`geometry mismatch ${scene.id}: ${JSON.stringify(node.rect)}`);
  const r=await screenshot(`${out}/${scene.id}.png`);
  if(r.ok!==true) throw new Error(`capture failed ${scene.id}`);
  captured.push(scene.id);
  console.log(`captured ${scene.id}`);
}
writeFileSync(`${out}/metadata.json`,JSON.stringify({renderer:"Zenit.production.Metal",tune,captured_at:new Date().toISOString(),cases:captured},null,2));
