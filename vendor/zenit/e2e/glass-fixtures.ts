// One scene description and identical, deterministic pixels for both renderers.
import { mkdirSync, writeFileSync } from "node:fs";
import { writeRgbPng } from "./png";
export { writeRgbPng } from "./png";
export interface GlassScene { id: string; background: string; variant: string; x: number; y: number; w: number; h: number; radius: number; tint?: number[]; foreground?: string; }
export function makeFixtures(dir: string): GlassScene[] {
  mkdirSync(dir,{recursive:true});
  for(const mode of ["light","dark","mixed"]) {
    const rgb=new Uint8Array(1280*960*3),rgba=new Uint8Array(1280*960*4);
    for(let y=0;y<960;y++) for(let x=0;x<1280;x++) {
      let c=[40+190*x/1280,60+150*y/960,225-140*x/1280];
      if(mode==="light") c=c.map(v=>180+v*.29);
      if(mode==="dark") c=c.map(v=>10+v*.23);
      // A multiscale grid reveals both blur and sampling/registration errors.
      const grid=(x%64<4||y%64<4)?0.58:1;
      c=c.map(v=>Math.round(v*grid));
      const p=y*1280+x;rgb.set(c,p*3);rgba.set([...c,255],p*4);
    }
    writeRgbPng(`${dir}/${mode}.png`,1280,960,rgb);writeFileSync(`${dir}/${mode}.rgba`,rgba);
  }
  const scenes: GlassScene[]=[];
  for(const background of ["light","dark","mixed"]) for(const variant of ["regular","clear"]) {
    scenes.push({id:`${background}-${variant}-capsule`,background,variant,x:160,y:208,w:320,h:64,radius:32});
    scenes.push({id:`${background}-${variant}-panel`,background,variant,x:160,y:140,w:320,h:200,radius:28});
  }
  for(const variant of ["regular","clear"]) scenes.push({id:`mixed-${variant}-circle`,background:"mixed",variant,x:272,y:192,w:96,h:96,radius:48});
  for(const background of ["light","dark"]) scenes.push({id:`${background}-regular-tint`,background,variant:"regular",x:160,y:208,w:320,h:64,radius:32,tint:[0,122,255]});
  scenes.push({id:"light-regular-edge",background:"light",variant:"regular",x:0,y:140,w:240,h:200,radius:28});
  scenes.push({id:"dark-clear-edge",background:"dark",variant:"clear",x:400,y:140,w:240,h:200,radius:28});
  scenes.push({id:"text-regular-left-edge",background:"text-light",variant:"regular",x:0,y:0,w:240,h:480,radius:16});
  scenes.push({id:"text-regular-right-edge",background:"text-light",variant:"regular",x:400,y:0,w:240,h:480,radius:16});
  scenes.push({id:"text-regular-toolbar",background:"text-light",variant:"regular",x:160,y:140,w:420,h:44,radius:18});
  scenes.push({id:"text-regular-panel",background:"text-mixed",variant:"regular",x:160,y:140,w:240,h:104,radius:18});
  scenes.push({id:"text-clear-panel",background:"text-mixed",variant:"clear",x:160,y:140,w:240,h:104,radius:18});
  scenes.push({id:"content-regular-panel",background:"text-mixed",variant:"regular",x:160,y:140,w:240,h:104,radius:18,foreground:"foreground-regular-panel"});
  scenes.push({id:"content-clear-panel",background:"text-mixed",variant:"clear",x:160,y:140,w:240,h:104,radius:18,foreground:"foreground-clear-panel"});
  scenes.push({id:"content-regular-toolbar",background:"text-light",variant:"regular",x:160,y:140,w:420,h:44,radius:18,foreground:"foreground-toolbar"});
  writeFileSync(`${dir}/scenes.json`,JSON.stringify(scenes,null,2));return scenes;
}
if(import.meta.main) makeFixtures(process.argv[2]??"reports/glass-native-fidelity/fixtures");
