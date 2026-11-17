import { readFileSync, writeFileSync, mkdirSync, copyFileSync } from "node:fs";
import { resolve } from "node:path";
import { createHash } from "node:crypto";
import { decodePng, writeRgbPng, type DecodedPng } from "./png";
import { metrics, distance } from "./glass-fidelity";
import { materialStructureMetrics, structuralFailures } from "./glass-structure";
import type { GlassScene } from "./glass-fixtures";
type Rect = { x: number; y: number; w: number; h: number };
type Frame = { file: string; display_time: number; scale: number; content_scale: number; status: number };
const edges = (r: Rect) => [r.x, r.y, r.x+r.w, r.y+r.h];
const rectError = (a: Rect, b: Rect) => Math.max(...edges(a).map((v, i) => Math.abs(v-edges(b)[i])));
const rectTotalError = (a: Rect, b: Rect) => edges(a).reduce((sum,v,i)=>sum+Math.abs(v-edges(b)[i]),0);

export function selectMorphPresentation<T extends { display_time: number; rect?: Rect }>(
  frames: readonly T[], relative: number, eventTime: number, endTime: number,
  nativeRect: Rect, target: Rect, presentationWindowMs: number, endpointError: number,
): { frame: T; held: boolean; visibleInterval?: [number, number] } | undefined {
  const checkpoint=eventTime+relative;
  if(checkpoint>endTime)return;
  const candidates=frames.filter(g=>Math.abs((g.display_time-eventTime)-relative)*1000<=presentationWindowMs);
  const frame=candidates.sort((a,b)=>
    rectError(a.rect!,nativeRect)-rectError(b.rect!,nativeRect)||
    rectTotalError(a.rect!,nativeRect)-rectTotalError(b.rect!,nativeRect)||
    Math.abs(a.display_time-checkpoint)-Math.abs(b.display_time-checkpoint))[0];
  if(frame)return {frame,held:false};

  // A settled complete frame remains visible until another presentation or
  // capture end. Reuse that original frame only at the endpoint; a stale moving
  // pose must still fail the frozen presentation window, even if geometrically
  // close. This does not create frames or change their presentation timestamps.
  if(rectError(nativeRect,target)>endpointError)return;
  const index=frames.findLastIndex(f=>f.display_time<=checkpoint);
  if(index<0)return;
  const current=frames[index];
  if(!current.rect||rectError(current.rect,target)>endpointError)return;
  const visibleEnd=index+1<frames.length?frames[index+1].display_time:endTime;
  if(checkpoint>=visibleEnd&&visibleEnd!==endTime)return;
  return {frame:current,held:true,visibleInterval:[current.display_time,visibleEnd]};
}

function compareMotion() {
const root = resolve(process.argv[2] ?? "reports/glass-native-fidelity");
const contract = JSON.parse(readFileSync("e2e/glass-fidelity.contract.json", "utf8"));
const limits = contract.motion, motionRoot = `${root}/native-motion`;
const json = (p: string) => JSON.parse(readFileSync(p, "utf8"));
const hash = (p: string) => createHash("sha256").update(readFileSync(p)).digest("hex");
const base = decodePng(`${root}/fixtures/mixed.png`);
const snapshots: any[] = [], results: any[] = [], sourceProof: any[] = [];
const snapshotScenes: GlassScene[] = [];
for (const dir of ["native", "zenit", "fixtures"]) mkdirSync(`${motionRoot}/${dir}`, { recursive: true });
const px = (p: DecodedPng, x: number, y: number, c: number) => p.pixels[(y*p.width+x)*p.channels+c];
function bounds(p: DecodedPng): Rect {
  let x0=1280,y0=960,x1=-1,y1=-1,count=0;
  // These test controls all remain within this scan region; window chrome is
  // excluded. Opaque regular glass is segmented against the shared fixture.
  for(let y=280;y<680;y++)for(let x=280;x<1140;x++) {
    if(Math.max(...[0,1,2].map(c=>px(p,x,y,c)-px(base,x,y,c)))>30) {
      x0=Math.min(x0,x);x1=Math.max(x1,x);y0=Math.min(y0,y);y1=Math.max(y1,y);count++;
    }
  }
  if(count<10000)throw new Error("Missing rendered glass silhouette");
  return {x:x0/2,y:y0/2,w:(x1-x0+1)/2,h:(y1-y0+1)/2};
}
function scrollOffset(p: DecodedPng) {
  let best=Infinity,offset=-1;
  for(let shift=0;shift<=128;shift++) {
    let sse=0,n=0;
    for(let y=180;y<860;y+=34)for(const x of [80,132,200,1060,1124,1190])for(let c=0;c<3;c++) {
      sse+=(px(p,x,y,c)-px(base,x,(y+shift)%960,c))**2;n++;
    }
    const rmse=Math.sqrt(sse/n);if(rmse<best){best=rmse;offset=shift/2;}
  }
  if(best>contract.thresholds.background_rmse)throw new Error(`Unregistered scroll background: RMSE=${best}`);
  return offset;
}
function load(action: string, native: boolean) {
  const folder=`${motionRoot}/${native?"swiftui":"zenit"}/${action}`;
  const timeline=json(`${folder}/timeline.json`);
  if(timeline.renderer!==(native?"SwiftUI.glassEffect.interactive":"Zenit.production.Metal")||timeline.scale!==2||
     JSON.stringify(timeline.viewport)!=="[640,480]"||!Number.isFinite(timeline.end_time))throw new Error("Invalid lossless capture provenance");
  for(const [key,want] of Object.entries(contract.preconditions))if(timeline[key]!==want)throw new Error(`Motion precondition ${key} violated`);
  if(!process.env.ZENIT_GLASS_GATE_RUN_ID||timeline.run_id!==process.env.ZENIT_GLASS_GATE_RUN_ID)throw new Error("Stale motion run");
  const inputs=native?timeline:json(`${folder}/inputs.json`);
  if(!native&&(inputs.run_id!==timeline.run_id||inputs.before.calibration_active||inputs.before.glass_pipeline_failed||inputs.before.blur_pipeline_failed))throw new Error("Invalid production input provenance");
  if(!Array.isArray(timeline.frames)||!timeline.frames.length||!Array.isArray(inputs.events)||!inputs.events.length)throw new Error("Missing frames or input events");
  if(native&&action==="hover_press_release") {
    if(timeline.clicks!==1||timeline.hover_detected!==false||
       !["hover","leave"].every(name=>timeline.transitions.some((t:any)=>t.name===name)))throw new Error("Native tracking/click delivery missing");
  }
  const cache=new Map<string,DecodedPng>();
  let previous=-Infinity;
  const frames: (Frame&{png:DecodedPng;sha256:string;rect?:Rect;offset?:number})[]=timeline.frames.map((f:Frame)=>{
    if(!Number.isFinite(f.display_time)||f.display_time<previous||f.scale!==2||f.content_scale!==1||f.status!==0)throw new Error("Invalid presentation timestamp or frame geometry");
    previous=f.display_time;
    if(!/^frame-[0-9]+\.png$/.test(f.file))throw new Error("Invalid frame path");
    const path=`${folder}/${f.file}`,sha256=hash(path);let png=cache.get(sha256);
    if(!png){png=decodePng(path);cache.set(sha256,png);}
    if(png.width!==1280||png.height!==960)throw new Error("Motion image resizing is forbidden");
    return {...f,png,sha256};
  });
  const geomCache=new Map<string,Rect|number>();
  for(const frame of frames) {
    let value=geomCache.get(frame.sha256);
    if(value===undefined){value=action==="scroll"?scrollOffset(frame.png):bounds(frame.png);geomCache.set(frame.sha256,value);}
    if(action==="scroll")frame.offset=value as number;else frame.rect=value as Rect;
  }
  sourceProof.push({action,renderer:timeline.renderer,timeline_sha256:hash(`${folder}/timeline.json`),frame_count:frames.length,
    unique_images:cache.size,end_time:timeline.end_time,events:inputs.events,frames:frames.map(({png,...f})=>f)});
  function held(time:number) {
    if(time>timeline.end_time)throw new Error("Checkpoint falls beyond recorded capture");
    const f=frames.findLast(f=>f.display_time<=time);if(!f)throw new Error("No frame was presented by this checkpoint");return f;
  }
  return {folder,timeline,events:inputs.events,frames,held};
}
function checkMaterial(id:string,native:any,actual:any,scene:GlassScene,deepBody=false,action="") {
  let a=native.png,b=actual.png;
  if(deepBody) {
    // The fixed native body mask includes neither moving rims nor pose error.
    // It is derived solely from the native silhouette and never resizes or
    // translates either image. Original full-window frames remain in evidence.
    const aa=new Uint8Array(1280*960*3),bb=new Uint8Array(aa.length);
    let n=0;for(let y=0;y<960;y++)for(let x=0;x<1280;x++)if(distance((x+.5)/2,(y+.5)/2,scene)<-limits.moving_body_inset_logical_pixels) {
      for(let c=0;c<3;c++){aa[(y*1280+x)*3+c]=px(a,x,y,c);bb[(y*1280+x)*3+c]=px(b,x,y,c);}n++;
    }
    if(n<10000)throw new Error("Insufficient native moving-body coverage");
    writeRgbPng(`${motionRoot}/native/${id}.png`,1280,960,aa);
    writeRgbPng(`${motionRoot}/zenit/${id}.png`,1280,960,bb);
    a=decodePng(`${motionRoot}/native/${id}.png`);b=decodePng(`${motionRoot}/zenit/${id}.png`);
  } else {
    copyFileSync(`${native.folder}/${native.file}`,`${motionRoot}/native/${id}.png`);
    copyFileSync(`${actual.folder}/${actual.file}`,`${motionRoot}/zenit/${id}.png`);
  }
  // metrics() excludes another six logical pixels from its body. Eroding the
  // native geometry by six therefore measures exactly the native 12 px mask,
  // without diluting RMSE/SSIM with the zeroed pixels outside that mask.
  const metricScene=deepBody?{...scene,x:scene.x+6,y:scene.y+6,w:scene.w-12,h:scene.h-12,radius:Math.max(scene.radius-6,0)}:scene;
  const {heat,...m}=metrics(a,b,metricScene);
  if(deepBody) {
    // A deep body mask cannot establish rounded-edge fidelity. Measure the
    // original native rim too, without warping away geometry or optical errors.
    const full=metrics(native.png,actual.png,scene);
    m.rim_rmse=full.rim_rmse;
    m.exact_rgb_rim_different_pixels=full.exact_rgb_rim_different_pixels;
    m.exact_rgb_rim_measured_pixels=full.exact_rgb_rim_measured_pixels;
    m.shadow_rmse=full.shadow_rmse;
    m.background_rmse=full.background_rmse;
  }
  const thresholds=deepBody?{body_rmse:limits.moving_body_rmse,body_p95_rgb_error:limits.moving_body_p95_rgb_error,body_ssim:limits.moving_body_ssim,rim_rmse:contract.thresholds.rim_rmse}:Object.fromEntries(Object.entries(contract.thresholds).filter(([k])=>k!=="idle_frame_rmse"));
  const failures=Object.entries(thresholds).filter(([k,v])=>!Number.isFinite((m as any)[k])||(k==="body_ssim"?(m as any)[k]<(v as number):(m as any)[k]>(v as number))).map(([k,v])=>`${k}=${(m as any)[k]} limit=${v}`);
  const structure=materialStructureMetrics(native.png,actual.png,scene,scene.foreground?decodePng(`${root}/fixtures/${scene.foreground}.png`):undefined,deepBody?limits.moving_body_inset_logical_pixels:.5);
  if(deepBody) {
    const full=materialStructureMetrics(native.png,actual.png,scene);
    for(const [key,value] of Object.entries(full))if(key.startsWith("rim_")||key.startsWith("curved_rim_"))structure[key]=value;
  }
  failures.push(...structuralFailures(structure,contract.structure));
  snapshotScenes.push({...scene,id});
  snapshots.push({id,action,native_frame:native.file,zenit_frame:actual.file,native_sha256:native.sha256,zenit_sha256:actual.sha256,
    mask:deepBody?`body: native SDF interior > ${limits.moving_body_inset_logical_pixels} logical pixels; rim RGB and structure: original frame, outermost 6 inside logical pixels`:null,values:m,structure,failures});
  return failures;
}
const capsule={x:160,y:208,w:320,h:64},target={x:200,y:160,w:240,h:160};
for(const action of contract.required_native_motion_actions) {
  const baseline=action==="hover_press_release"?{x:160,y:140,w:240,h:104}:capsule;
  const failures:string[]=[],pairs:any[]=[];
  try {
    const n=load(action,true),z=load(action,false);
    const scene=(r:Rect,id=""):GlassScene=>({...r,id,background:"mixed",variant:"regular",radius:action==="hover_press_release"?18:32,foreground:action==="hover_press_release"?"foreground-regular-panel":undefined});
    const check=(ok:boolean,message:string)=>{if(!ok)failures.push(message);};
    const material=(id:string,nf:any,zf:any,r:Rect,mask=false)=>failures.push(...checkMaterial(id,{...nf,folder:n.folder},{...zf,folder:z.folder},scene(r,id),mask,action));
    if(action==="morph") {
      const nt=n.events[0].time,zt=z.events[0].time;
      const endN=n.held(nt+limits.settled_checkpoint_delay_ms/1000),endZ=z.held(zt+limits.settled_checkpoint_delay_ms/1000);
      check(rectError(endN.rect!,target)<=limits.geometry_endpoint_error_logical_pixels,"Native morph endpoint mismatch");
      check(rectError(endZ.rect!,target)<=limits.geometry_endpoint_error_logical_pixels,"Production morph endpoint mismatch");
      const firstTarget=z.frames.find(f=>f.display_time>=zt&&rectError(f.rect!,target)<=limits.geometry_endpoint_error_logical_pixels);
      check(!!firstTarget&&(firstTarget.display_time-zt)*1000<=limits.morph_completion_deadline_ms,"Morph missed completion deadline");
      let previous=baseline;
      for(const [i,f] of n.frames.filter(f=>f.display_time>=nt).entries()) {
        const relative=f.display_time-nt;
        if(relative>limits.morph_completion_deadline_ms/1000)continue;
        const selected=selectMorphPresentation(z.frames,relative,zt,z.timeline.end_time,f.rect!,target,
          limits.trajectory_presentation_window_ms,limits.geometry_endpoint_error_logical_pixels);
        const g=selected?.frame;
        check(!!g&&rectError(g.rect!,f.rect!)<=limits.trajectory_edge_error_logical_pixels,`Morph pose ${i} exceeded geometry/presentation tolerance`);
        check(f.rect!.x>=previous.x-1&&f.rect!.y<=previous.y+1&&f.rect!.h>=previous.h-1,"Native morph trajectory reversed");previous=f.rect!;
        if(g) {
          pairs.push({native_time:relative,zenit_time:g.display_time-zt,edge_error:rectError(g.rect!,f.rect!),
            pairing:selected!.held?"held-settled":"presentation",
            ...(selected!.visibleInterval?{zenit_visible_interval:selected!.visibleInterval.map(t=>t-zt)}:{})});
          material(`morph-body-${String(i).padStart(2,"0")}`,f,g,f.rect!,true);
        }
      }
      material("morph-final",endN,endZ,target);
    } else if(action==="drag"||action==="scroll") {
      for(let i=1;i<=8;i++)for(const capture of [n,z]) {
        const name=`${action}_${i}`,event=capture.events.find((e:any)=>e.name===name);if(!event)throw new Error(`Missing ${name}`);
        const want={...baseline,x:160+i*10,y:208+i*3};
        const seen=capture.frames.find(f=>f.display_time>=event.time&&
          (action==="scroll"?Math.abs(f.offset!-i*8)<=limits.scroll_offset_error_logical_pixels:rectError(f.rect!,want)<=limits.geometry_endpoint_error_logical_pixels));
        check(!!seen&&(seen.display_time-event.time)*1000<=limits.input_response_deadline_ms,`${capture===n?"Native":"Production"} ${name} missed its rendered input response`);
        pairs.push({renderer:capture.timeline.renderer,name,response_ms:seen?(seen.display_time-event.time)*1000:null,rect:seen?.rect,scroll_offset:seen?.offset});
      }
      const nf=n.held(n.events.at(-1).time+limits.settled_checkpoint_delay_ms/1000),zf=z.held(z.events.at(-1).time+limits.settled_checkpoint_delay_ms/1000);
      material(`${action}-final`,nf,zf,action==="drag"?{...baseline,x:240,y:232}:baseline);
    } else {
      for(const name of ["hover","press","release","leave"]) {
        const ne=n.events.find((e:any)=>e.name===name),ze=z.events.find((e:any)=>e.name===name);if(!ne||!ze)throw new Error(`Missing ${name} input`);
        const nf=n.held(ne.time+limits.settled_checkpoint_delay_ms/1000),zf=z.held(ze.time+limits.settled_checkpoint_delay_ms/1000);
        check(rectError(nf.rect!,baseline)<=limits.geometry_endpoint_error_logical_pixels&&rectError(zf.rect!,baseline)<=limits.geometry_endpoint_error_logical_pixels,`${name} geometry mismatch`);
        material(name,nf,zf,baseline);
      }
    }
    results.push({action,status:failures.length?"FAIL":"PASS",failures,pairs});
  } catch(error) {results.push({action,status:"ERROR",failures:[String(error)],pairs});}
}
writeFileSync(`${motionRoot}/fixtures/scenes.json`,JSON.stringify(snapshotScenes,null,2));
writeFileSync(`${motionRoot}/snapshots.contract.json`,JSON.stringify({...contract,required_cases:snapshotScenes.map(s=>s.id),
  comparison_scope:"Timestamped native material snapshots: fixed native deep-body masks for morph body metrics, original moving rims for RGB and fine/broad curved-rim structure, and full material at settled checkpoints. Presentation and geometry are checked separately; a passing image matcher does not establish exact 1:1 reproduction."},null,2));
writeFileSync(`${motionRoot}/native/metadata.json`,JSON.stringify({renderer:"SwiftUI.glassEffect",capture:"SCStream.lossless.sRGB",scale:2,
  ...contract.preconditions,cases:snapshotScenes.map(s=>s.id),sources:sourceProof.filter(p=>p.renderer.startsWith("SwiftUI"))},null,2));
const report={schema_version:1,run_id:process.env.ZENIT_GLASS_GATE_RUN_ID??null,status:results.every(r=>r.status==="PASS")?"PASS":"FAIL",
  scope:limits.scope,contract:limits,results,snapshots,sources:sourceProof};
writeFileSync(`${motionRoot}/comparison.json`,JSON.stringify(report,null,2));
writeFileSync(`${motionRoot}/report.html`,`<!doctype html><meta charset="utf-8"><title>Native motion comparison</title><style>body{font:14px system-ui;background:#181818;color:#eee;padding:24px}img{width:48%}pre{white-space:pre-wrap}a{color:#9bc6ff}</style><h1>Timestamped native motion: ${report.status}</h1><p>${limits.scope}</p><p><a href="pixelmatch.html">Actual Playwright pixelmatch results</a> · <a href="comparison.json">Timestamps, source hashes and metrics</a></p>${results.map(r=>`<h2>${r.action}: ${r.status}</h2><pre>${r.failures.join("\n")}</pre>`).join("")}${snapshots.map(s=>`<h3>${s.id}</h3><p>${s.failures.join("; ")}</p><img src="native/${s.id}.png"><img src="zenit/${s.id}.png">`).join("")}`);
for(const r of results)console.log(`${r.status} ${r.action}: ${r.failures.join("; ")}`);
process.exit(report.status==="PASS"?0:1);
}
if(import.meta.main)compareMotion();
