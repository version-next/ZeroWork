import { readFileSync } from "node:fs";
import { createHash } from "node:crypto";

// Both sides must come from the same run. A stale PNG or a calibration capture
// cannot become acceptance evidence merely because it has the expected name.
export function validateProductionCapture(root:string, runId:string, requiredCases:string[]) {
  const metadata=JSON.parse(readFileSync(`${root}/zenit/metadata.json`,"utf8"));
  if(metadata.renderer!=="Zenit.production.Metal"||metadata.scale!==2||JSON.stringify(metadata.viewport)!=="[640,480]")
    throw new Error("Invalid production capture provenance");
  if(!runId||metadata.run_id!==runId||(process.env.ZENIT_GLASS_GATE_RUN_ID&&runId!==process.env.ZENIT_GLASS_GATE_RUN_ID))
    throw new Error("Static native and production captures must belong to the same run");
  const hash=(path:string)=>createHash("sha256").update(readFileSync(path)).digest("hex");
  for(const id of requiredCases) {
    const capture=metadata.cases?.find((c:any)=>c.id===id);
    if(!capture||capture.state.calibration_active||capture.state.glass_pipeline_failed||capture.state.blur_pipeline_failed)
      throw new Error(`Missing or invalid production state: ${id}`);
    if(hash(`${root}/zenit/${id}.png`)!==capture.sha256||hash(`${root}/zenit/${id}-idle.png`)!==capture.idle_sha256)
      throw new Error(`Production PNG changed after capture: ${id}`);
  }
  return metadata;
}
