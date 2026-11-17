import type { DecodedPng } from "./png";
import type { GlassScene } from "./glass-fixtures";

function sdf(x:number,y:number,s:GlassScene) {
  const r=Math.min(s.radius,s.w/2,s.h/2),qx=Math.abs(x-s.x-s.w/2)-(s.w/2-r),qy=Math.abs(y-s.y-s.h/2)-(s.h/2-r);
  return Math.hypot(Math.max(qx,0),Math.max(qy,0))+Math.min(Math.max(qx,qy),0)-r;
}
function gaussian(input:Float64Array,w:number,h:number,sigma:number) {
  const radius=Math.ceil(sigma*3),kernel=[];let sum=0;
  for(let i=-radius;i<=radius;i++){const v=Math.exp(-i*i/(2*sigma*sigma));kernel.push(v);sum+=v;}
  for(let i=0;i<kernel.length;i++)kernel[i]/=sum;
  const tmp=new Float64Array(input.length),out=new Float64Array(input.length);
  for(let y=0;y<h;y++)for(let x=0;x<w;x++)for(let k=-radius;k<=radius;k++)tmp[y*w+x]+=input[y*w+Math.max(0,Math.min(w-1,x+k))]*kernel[k+radius];
  for(let y=0;y<h;y++)for(let x=0;x<w;x++)for(let k=-radius;k<=radius;k++)out[y*w+x]+=tmp[Math.max(0,Math.min(h-1,y+k))*w+x]*kernel[k+radius];
  return out;
}
// Compare low-contrast structure independently of mean color. Masked Gaussian
// bands cannot borrow the identical outside grid or silhouette to hide a flat
// material. The images themselves are never altered for the pixel matcher.
export function structuralMetrics(a:DecodedPng,b:DecodedPng,s:GlassScene,foreground?:DecodedPng,interiorInset=.5,scales:readonly [number,number]=[1,4]) {
  if(a.width!==1280||a.height!==960||b.width!==a.width||b.height!==a.height)
    throw new Error("Structural comparison requires original 1280x960 captures; resampling is forbidden");
  const x0=Math.max(0,Math.floor(s.x*2)),y0=Math.max(0,Math.floor(s.y*2));
  const w=Math.min(a.width,Math.ceil((s.x+s.w)*2))-x0,h=Math.min(a.height,Math.ceil((s.y+s.h)*2))-y0;
  const mask=new Float64Array(w*h),aa=new Float64Array(w*h),bb=new Float64Array(w*h),ds=new Float64Array(w*h);
  for(let y=0;y<h;y++)for(let x=0;x<w;x++) {
    const i=y*w+x,d=sdf((x+x0+.5)/2,(y+y0+.5)/2,s);ds[i]=d;
    let keep=d<-interiorInset;
    if(keep&&foreground?.channels===4) {
      // Shared foreground is already tested separately. Exclude its filter
      // footprint so strong text cannot conceal missing backdrop structure.
      const fx=x+x0-Math.round(s.x*2),fy=y+y0-Math.round(s.y*2);
      outer:for(let yy=Math.max(0,fy-12);yy<Math.min(foreground.height,fy+13);yy++)for(let xx=Math.max(0,fx-12);xx<Math.min(foreground.width,fx+13);xx++)
        if(foreground.pixels[(yy*foreground.width+xx)*4+3]>8){keep=false;break outer;}
    }
    mask[i]=keep?1:0;
    for(const [p,out] of [[a,aa],[b,bb]] as const) {
      const off=((y+y0)*p.width+x+x0)*p.channels;
      out[i]=(p.pixels[off]*.2126+p.pixels[off+1]*.7152+p.pixels[off+2]*.0722)*mask[i];
    }
  }
  const bands=[aa,bb].map(p=>new Float64Array(p.length));
  for(const [sigma,sign] of [[scales[0],1],[scales[1],-1]]) {
    const weight=gaussian(mask,w,h,sigma);
    for(const [index,p] of [aa,bb].entries()) {
      const filtered=gaussian(p,w,h,sigma);
      for(let i=0;i<p.length;i++)bands[index][i]+=sign*filtered[i]/Math.max(weight[i],1e-10);
    }
  }
  const totals={body:{n:0,aa:0,bb:0,ab:0,error:0},rim:{n:0,aa:0,bb:0,ab:0,error:0},curved_rim:{n:0,aa:0,bb:0,ab:0,error:0}};
  for(let i=0;i<mask.length;i++)if(mask[i]) {
    const region=ds[i]<-6?totals.body:totals.rim;
    const av=bands[0][i],bv=bands[1][i];region.n++;region.aa+=av*av;region.bb+=bv*bv;region.ab+=av*bv;region.error+=(av-bv)**2;
    const x=(i%w+x0+.5)/2,y=(Math.floor(i/w)+y0+.5)/2,r=Math.min(s.radius,s.w/2,s.h/2);
    if(ds[i]>=-6&&Math.abs(x-s.x-s.w/2)>s.w/2-r&&Math.abs(y-s.y-s.h/2)>s.h/2-r) {
      const c=totals.curved_rim;c.n++;c.aa+=av*av;c.bb+=bv*bv;c.ab+=av*bv;c.error+=(av-bv)**2;
    }
  }
  const result:any={};
  for(const [name,t] of Object.entries(totals)) {
    const native=Math.sqrt(t.aa/Math.max(t.n,1)),actual=Math.sqrt(t.bb/Math.max(t.n,1));
    const meaningful=t.n>=100&&native>=.15;
    result[`${name}_structure_native_rms`]=native;
    result[`${name}_structure_zenit_rms`]=actual;
    result[`${name}_structure_contrast_ratio`]=meaningful?actual/native:null;
    result[`${name}_structure_error_ratio`]=meaningful?Math.sqrt(t.error/t.aa):null;
    result[`${name}_structure_correlation`]=meaningful?t.ab/Math.sqrt(Math.max(t.aa*t.bb,1e-20)):null;
    result[`${name}_structure_measured_pixels`]=t.n;
    result[`${name}_structure_significant`]=meaningful;
  }
  return result;
}

export function structuralFailures(values:any,limits:any) {
  const failures:string[]=[];
  for(const band of ["","broad_"])for(const area of ["body","rim","curved_rim"]) {
    const region=`${area}_${band}`;
    const label=`${area}${band?" broad":""}`;
    if(!values[`${region}structure_significant`])continue;
    const ratio=values[`${region}structure_contrast_ratio`],error=values[`${region}structure_error_ratio`],correlation=values[`${region}structure_correlation`];
    if(!Number.isFinite(ratio)||ratio<limits.contrast_ratio_min||ratio>limits.contrast_ratio_max)
      failures.push(`${label} structure contrast=${ratio.toFixed(3)} (range ${limits.contrast_ratio_min}–${limits.contrast_ratio_max})`);
    if(!Number.isFinite(error)||error>limits.error_ratio_max)failures.push(`${label} structure error=${error.toFixed(3)} (max ${limits.error_ratio_max})`);
    if(!Number.isFinite(correlation)||correlation<limits.correlation_min)failures.push(`${label} structure correlation=${correlation.toFixed(3)} (min ${limits.correlation_min})`);
  }
  return failures;
}

export function materialStructureMetrics(a:DecodedPng,b:DecodedPng,s:GlassScene,foreground?:DecodedPng,interiorInset=.5) {
  const fine=structuralMetrics(a,b,s,foreground,interiorInset);
  const broad=structuralMetrics(a,b,s,foreground,interiorInset,[4,12]);
  return {...fine,...Object.fromEntries(Object.entries(broad).map(([k,v])=>[k.replace("_structure_","_broad_structure_"),v]))};
}
