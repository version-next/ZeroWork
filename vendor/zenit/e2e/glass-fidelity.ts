import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { resolve } from "node:path";
import { decodePng, type DecodedPng } from "./png";
import { writeRgbPng, type GlassScene } from "./glass-fixtures";
import { validateProductionCapture } from "./glass-provenance";
import { structuralMetrics, materialStructureMetrics, structuralFailures } from "./glass-structure";
type Region = "background"|"body"|"rim"|"shadow";
export function distance(x:number,y:number,s:GlassScene) {
  const r=Math.min(s.radius,s.w/2,s.h/2);
  const qx=Math.abs(x-s.x-s.w/2)-(s.w/2-r),qy=Math.abs(y-s.y-s.h/2)-(s.h/2-r);
  return Math.hypot(Math.max(qx,0),Math.max(qy,0))+Math.min(Math.max(qx,qy),0)-r;
}
function rgb(p:DecodedPng,x:number,y:number) {const i=(y*p.width+x)*p.channels;return [p.pixels[i],p.pixels[i+1],p.pixels[i+2]];}
export function metrics(a:DecodedPng,b:DecodedPng,s:GlassScene) {
  if(a.width!==1280||a.height!==960||b.width!==1280||b.height!==960) throw new Error("Captures must be exactly 1280x960; resizing/registration repair is forbidden");
  const regions:Record<Region,{sse:number,n:number,errors:number[],different:number}>={background:{sse:0,n:0,errors:[],different:0},body:{sse:0,n:0,errors:[],different:0},rim:{sse:0,n:0,errors:[],different:0},shadow:{sse:0,n:0,errors:[],different:0}};
  const heat=new Uint8Array(a.width*a.height*3);
  let ssim=0,blocks=0;
  for(let y=0;y<a.height;y++)for(let x=0;x<a.width;x++) {
    const d=distance((x+.5)/2,(y+.5)/2,s);
    const region:Region|null=d< -6?"body":d<0?"rim":d<=16?"shadow":d>40 && !(x<200&&y<100)?"background":null;
    const ca=rgb(a,x,y),cb=rgb(b,x,y),err=ca.map((v,c)=>v-cb[c]);
    const max=Math.max(...err.map(Math.abs));heat.set([Math.min(255,max*5),0,0],(y*a.width+x)*3);
    if(region){const m=regions[region];m.sse+=err.reduce((v,e)=>v+e*e,0);m.n++;m.errors.push(max);if(max>0)m.different++;}
  }
  // Local SSIM, over luminance in complete 8x8 body blocks only.
  for(let y=0;y<a.height-7;y+=8)for(let x=0;x<a.width-7;x+=8) {
    if([[x,y],[x+7,y],[x,y+7],[x+7,y+7]].some(([xx,yy])=>distance((xx+.5)/2,(yy+.5)/2,s)>=-6))continue;
    let ma=0,mb=0,va=0,vb=0,cov=0;const aa:number[]=[],bb:number[]=[];
    for(let yy=y;yy<y+8;yy++)for(let xx=x;xx<x+8;xx++) {const l=(p:DecodedPng)=>rgb(p,xx,yy).reduce((v,c,i)=>v+c*[.2126,.7152,.0722][i],0);aa.push(l(a));bb.push(l(b));}
    ma=aa.reduce((v,c)=>v+c,0)/64;mb=bb.reduce((v,c)=>v+c,0)/64;
    for(let i=0;i<64;i++){va+=(aa[i]-ma)**2/64;vb+=(bb[i]-mb)**2/64;cov+=(aa[i]-ma)*(bb[i]-mb)/64;}
    ssim+=((2*ma*mb+6.5025)*(2*cov+58.5225))/((ma*ma+mb*mb+6.5025)*(va+vb+58.5225));blocks++;
  }
  const rmse=(r:Region)=>{if(regions[r].n<100)throw new Error(`${s.id} has insufficient ${r} coverage`);return Math.sqrt(regions[r].sse/(regions[r].n*3));};
  const errors=regions.body.errors.sort((a,b)=>a-b);
  return {background_rmse:rmse("background"),body_rmse:rmse("body"),body_p95_rgb_error:errors[Math.floor(errors.length*.95)],body_ssim:ssim/blocks,rim_rmse:rmse("rim"),shadow_rmse:rmse("shadow"),
    exact_rgb_body_different_pixels:regions.body.different,exact_rgb_body_measured_pixels:regions.body.n,
    exact_rgb_rim_different_pixels:regions.rim.different,exact_rgb_rim_measured_pixels:regions.rim.n,heat};
}
export function compareGlass(root:string) {
  const contract=JSON.parse(readFileSync("e2e/glass-fidelity.contract.json","utf8"));
  const scenes:GlassScene[]=JSON.parse(readFileSync(`${root}/fixtures/scenes.json`,"utf8"));
  const metadata=JSON.parse(readFileSync(`${root}/native/metadata.json`,"utf8"));
  if(metadata.renderer!=="SwiftUI.glassEffect"||metadata.scale!==2)throw new Error("Invalid native provenance");
  if(metadata.fixture_isolation!==contract.static_reference.fixture_isolation)throw new Error("Native scenes must use independent effect hosts");
  if(process.env.ZENIT_GLASS_GATE_RUN_ID&&metadata.run_id!==process.env.ZENIT_GLASS_GATE_RUN_ID)throw new Error("Stale static native reference");
  const production=validateProductionCapture(root,metadata.run_id,contract.required_cases);
  for(const [key,want] of Object.entries(contract.preconditions))if(metadata[key]!==want)throw new Error(`Reference precondition ${key} violated`);
  const results=[];
  mkdirSync(`${root}/diff`,{recursive:true});
  for(const id of contract.required_cases) {
    const scene=scenes.find(s=>s.id===id);if(!scene||!metadata.cases.includes(id))throw new Error(`Missing reference ${id}`);
    if(!Number.isFinite(metadata.native_idle_rmse?.[id])||metadata.native_idle_rmse[id]>contract.static_reference.native_idle_rmse_max)throw new Error(`Native reference did not settle: ${id}`);
    const a=decodePng(`${root}/native/${id}.png`),b=decodePng(`${root}/zenit/${id}.png`),idle=decodePng(`${root}/zenit/${id}-idle.png`);
    const {heat,...m}=metrics(a,b,scene);const idleMetrics=metrics(b,idle,scene);
    const values={...m,idle_frame_rmse:Math.max(idleMetrics.body_rmse,idleMetrics.rim_rmse)};
    const failures=Object.entries(contract.thresholds).filter(([k,limit])=>{
      const value=(values as Record<string,number>)[k];
      return !Number.isFinite(value)||(k==="body_ssim"?value<(limit as number):value>(limit as number));
    }).map(([k,limit])=>`${k}=${(values as Record<string,number>)[k]?.toFixed(3)} (limit ${limit})`);
    const structure=materialStructureMetrics(a,b,scene,scene.foreground?decodePng(`${root}/fixtures/${scene.foreground}.png`):undefined);
    failures.push(...structuralFailures(structure,contract.structure));
    writeRgbPng(`${root}/diff/${id}.png`,1280,960,heat);
    results.push({id,values,structure,failures,status:failures.length?"FAIL":"PASS"});
    console.log(`${failures.length?"FAIL":"PASS"} ${id}: body=${m.body_rmse.toFixed(2)} rim=${m.rim_rmse.toFixed(2)} SSIM=${m.body_ssim.toFixed(4)} background=${m.background_rmse.toFixed(3)}`);
  }
  const report={schema_version:1,status:results.every(r=>r.status==="PASS")?"PASS":"FAIL",scope:"static native material fidelity only; dynamic native equivalence is a separate required gate",reference:metadata,production,contract,results};
  writeFileSync(`${root}/comparison.json`,JSON.stringify(report,null,2));
  const rows=results.map(r=>`<section><h2>${r.id}: ${r.status}</h2><p>${r.failures.join("; ")}</p><div>${["native","zenit","diff"].map(d=>`<figure><figcaption>${d}</figcaption><img src="${d}/${r.id}.png"></figure>`).join("")}</div></section>`).join("");
  writeFileSync(`${root}/report.html`,`<!doctype html><meta charset="utf-8"><title>Native Liquid Glass comparison</title><style>body{font:14px system-ui;background:#181818;color:white;padding:20px}div{display:flex;gap:10px}figure{margin:0;flex:1}img{width:100%}p{color:#ffaaaa}</style><h1>Static material fidelity: ${report.status}</h1><p>Source: live SwiftUI.glassEffect. Red heatmap = absolute RGB error × 5. Dynamic native equivalence is not established by this report.</p>${rows}`);
  return report;
}
function selfTest() {
  const scene:GlassScene={id:"self-test",background:"mixed",variant:"regular",x:160,y:208,w:320,h:64,radius:32};
  const pixels=new Uint8Array(1280*960*3).fill(240);
  const a:DecodedPng={width:1280,height:960,channels:3,pixels};
  const same=metrics(a,a,scene);
  if(same.body_rmse!==0||Math.abs(same.body_ssim-1)>1e-8)throw new Error("identity must pass");
  const b:DecodedPng={...a,pixels:pixels.slice()};
  for(let y=0;y<960;y++)for(let x=0;x<1280;x++)if(distance((x+.5)/2,(y+.5)/2,scene)<0)b.pixels.fill(30,(y*1280+x)*3,(y*1280+x)*3+3);
  const missing=metrics(a,b,scene);
  if(missing.background_rmse!==0||missing.body_rmse<200)throw new Error("identical background must not mask missing material");
  let rejected=false;try{metrics(a,{...a,width:1279},scene)}catch{rejected=true}
  if(!rejected)throw new Error("mismatched dimensions must fail closed");
  // A faint transmitted grid can disappear while ordinary RGB error remains
  // small. Exercise that failure independently of the current glass shader.
  const grid:DecodedPng={...a,pixels:pixels.slice()},flat:DecodedPng={...a,pixels:pixels.slice()};
  for(let y=0;y<960;y++)for(let x=0;x<1280;x++)if(distance((x+.5)/2,(y+.5)/2,scene)<0) {
    const level=(x%70<5||y%70<5)?234:240;
    grid.pixels.fill(level,(y*1280+x)*3,(y*1280+x)*3+3);
  }
  const limits={contrast_ratio_min:.8,contrast_ratio_max:1.25,error_ratio_max:.5,correlation_min:.9};
  if(structuralFailures(structuralMetrics(grid,grid,scene),limits).length)throw new Error("identical faint structure must pass");
  if(metrics(grid,flat,scene).body_rmse>3)throw new Error("faint-grid regression must have small absolute RGB error");
  if(!structuralFailures(structuralMetrics(grid,flat,scene),limits).some(f=>f.startsWith("body structure")))
    throw new Error("missing faint transmission must fail even with small RGB error");
  const softText:DecodedPng={...a,pixels:pixels.slice()};
  for(let y=420;y<540;y++)for(let x=380;x<900;x++) {
    const amount=8*Math.exp(-(((y-480)/18)**2))*Math.exp(-(((x-600)/130)**4));
    softText.pixels.fill(240-Math.round(amount),(y*1280+x)*3,(y*1280+x)*3+3);
  }
  if(structuralFailures(materialStructureMetrics(softText,softText,scene),limits).length)throw new Error("identical blurred text must pass");
  if(!structuralFailures(materialStructureMetrics(softText,flat,scene),limits).some(f=>f.startsWith("body broad structure")))
    throw new Error("missing broad blurred text must fail independently of fine detail");
  console.log("PASS: fidelity identity, material-only masking, dimension rejection, missing faint grid and missing blurred text");
}
if(import.meta.main) {try{if(process.argv[2]==="--self-test")selfTest();else{const r=compareGlass(resolve(process.argv[2]??"reports/glass-native-fidelity"));process.exit(r.status==="PASS"?0:1);}}catch(e){console.error(e);process.exit(1);}}
