// Optional developer tool; these overrides never enter the fidelity gate.
// The gate uses /glass/setup, which clears every calibration override.
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { resolve } from "node:path";
import { request, screenshot, waitForServerReady, sleep } from "./client";
import { metrics } from "./glass-fidelity";
import { decodePng } from "./png";
import type { GlassScene } from "./glass-fixtures";
const root=resolve(process.env.ZENIT_GLASS_ROOT??"reports/glass-native-fidelity");
const plan=JSON.parse(readFileSync(process.env.ZENIT_GLASS_CALIBRATION_PLAN!,"utf8"));
const out=resolve(`${root}/calibration/${plan.id}`);mkdirSync(out,{recursive:true});
const scenes:GlassScene[]=JSON.parse(readFileSync(`${root}/fixtures/scenes.json`,"utf8"));
await waitForServerReady();
const results=[];
const indices=plan.scene_ids?.map((id:string)=>{
  const i=scenes.findIndex(s=>s.id===id);if(i<0)throw new Error(`unknown scene ${id}`);return i;
})??plan.scenes;
for(const index of indices) {
  const scene=scenes[index];
  if(plan.variant&&scene.variant!==plan.variant)throw new Error(`wrong variant ${scene.id}`);
  const setup=await request("POST","/glass/setup",{index});
  if(!setup.ok)throw new Error("setup failed");
  await sleep(1600);
  console.log(scene.id,await request("GET","/glass/state"));
  const native=decodePng(`${root}/native/${scene.id}.png`);
  for(const [i,tune] of (plan.candidates_by_scene?.[scene.id]??plan.candidates).entries()) {
    const tuned=await request("POST","/glass/tune",tune);
    if(!tuned.ok)throw new Error(`invalid calibration ${JSON.stringify(tune)}`);
    await sleep(700);
    const path=`${out}/${scene.id}-${i}.png`;
    const capture=await screenshot(path);
    if(!capture.ok)throw new Error("capture failed");
    const {heat,...values}=metrics(native,decodePng(path),scene);
    results.push({scene:scene.id,i,tune,values});
    console.log(`${scene.id} ${i}: body=${values.body_rmse.toFixed(2)} rim=${values.rim_rmse.toFixed(2)} SSIM=${values.body_ssim.toFixed(4)}`);
  }
}
writeFileSync(`${out}/results.json`,JSON.stringify(results,null,2));
