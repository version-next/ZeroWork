/** Isolated native layout-motion regression; no connection or user data. */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdtemp,mkdir,writeFile,readFile,open,realpath} from 'node:fs/promises';
import {resolve,join} from 'node:path';
import {tmpdir} from 'node:os';
import {inflateSync} from 'node:zlib';
import * as h from '../zig-out/share/zenit/harness/client.ts';
const binary=resolve(process.argv[2]??'zig-out/bin/zerowork');
const out=resolve(process.argv[3]??'dist/ui-acceptance/layout-motion');await mkdir(out,{recursive:true});
// Flags after <bin> <out>, any order: light | dark (theme, default dark), reduced, persisted.
const flags=process.argv.slice(4);for(const f of flags)assert(['light','dark','reduced','persisted'].includes(f),'unknown flag '+f);
const reduced=flags.includes('reduced');
const persisted=flags.includes('persisted');
const theme=flags.includes('light')?'light':'dark';
const dir=await realpath(await mkdtemp(join(tmpdir(),'zw-layout-motion-')));
await mkdir(dir+'/data');await mkdir(dir+'/rpc');process.env.ZENIT_E2E_FILE_RPC_DIR=dir+'/rpc';
await writeFile(dir+'/data/config.toml',`[meta]\nconfig_revision=1\n[ui]\ntheme="${theme}"\n`);
await writeFile(dir+'/data/hosts.toml','[registry]\nschema_version=2\nrevision=1\nnext_connection_id=2\nnext_group_id=1\n[[hosts]]\nconnection_id=1\nrevision=1\nprotocol="ssh"\nname="Fixture"\nhost="192.0.2.1"\nport=22\nuser="fixture"\nauth_mode="password"\n');
if(persisted){const file=dir+'/data/hosts.toml';let text=await readFile(file,'utf8');text=text.replace('next_group_id=1','next_group_id=2').replace('[[hosts]]','[[groups]]\ngroup_id=1\nrevision=1\nname="Persisted group"\ncollapsed=false\nordered_connection_ids=[1]\n[[hosts]]\nasset_group_id=1');await writeFile(file,text);}
const log=await open(out+'/app.log','w');
const app=spawn(binary,[],{env:{...process.env,ZEROWORK_DATA_DIR:dir+'/data',ZEROWORK_AUTOCONNECT:'0',ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1',ZENIT_A11Y_PREFS:reduced?'reduce_motion':''},stdio:['ignore',log.fd,log.fd]});
const ended=new Promise<void>(r=>app.once('close',()=>r()));
const report:any={binary,theme,reduced,persisted,dir,status:'running',checks:[],tracks:{}};
// Island B v3 (e1372d88): the connection editor is its own native window (wizard.zig window_spec 720×640, minimum
// 600×420). The window frame no longer grows with its content — the old dialog-height motion
// (editor.zig preferredModalHeight / height_motion) only runs in the non-windowed modal mount, and `wizard.dialog`
// does not exist in the window. What moves now is the content inside the step's scroll viewport:
//  · 高级选项 is a layout_motion.Disclosure (src/shared/ui/styles/layout_motion.zig): the section's height follows a
//    200 ms ease-out between "toggle row only" and "toggle row + body", reverses from its current height, and
//    snaps under reduced motion. `wizard.advanced.card` (toggle row + disclosure root) is the node that shows it.
//  · Switching 认证方式 swaps the credential rows; the card takes its new natural height (no frame to animate).
// While the editor window is open the Harness is bound to it (query / resize / track address the editor).
const WINDOW={w:720,h:640},MINIMUM={w:600,h:420}; // wizard.zig window_spec
const shown=(n:any)=>n&&!n.hidden&&n.visible!==false&&(n.effective_opacity??1)>0&&n.rect?.w>0&&n.rect?.h>0;
const flatten=(n:any):any[]=>[n,...(n.children??[]).flatMap(flatten)];
async function nodes(id:string):Promise<any[]>{const q=await h.query(id);return Array.isArray(q)?q:[];}
async function current(id:string){return (await nodes(id)).find(shown)??null;}
async function visible(id:string){return h.waitFor(()=>current(id));}
/** The node, scrolled fully into the identity step's scroll viewport when it lives in it. */
async function reveal(id:string){
 return h.waitFor(async()=>{
  const n=await current(id);if(!n)return null;
  const area=await current('wizard.scroll.identity');if(!area||!flatten(area).some(x=>x.id===n.id))return n;
  const top=area.rect.y,bottom=area.rect.y+area.rect.h;
  if(n.rect.y>=top-0.5&&n.rect.y+n.rect.h<=bottom+0.5)return n;
  await h.scrollAt(area.rect.x+area.rect.w/2,area.rect.y+area.rect.h/2,0,n.rect.y<top?Math.min(400,top-n.rect.y+12):-Math.min(400,n.rect.y+n.rect.h-bottom+12));
  return null;
 });
}
/** Rect of a node once it has stopped changing (three equal polls) and satisfies `accept`. */
async function settled(id:string,accept:(r:any)=>boolean=()=>true){
 let prior='',same=0;
 return h.waitFor(async()=>{const n=await current(id);if(!n)return null;const at=JSON.stringify(n.rect);same=at===prior?same+1:0;prior=at;return same>=2&&accept(n.rect)?n.rect:null;});
}
async function press(id:string){const n=await reveal(id);assert((await h.clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok,id);}
async function click(id:string){await settled(id);await press(id);}
async function frame(size:{w:number,h:number}){return h.waitFor(async()=>{const n=await current('wizard.window');return n&&n.rect.x===0&&n.rect.y===0&&n.rect.w===size.w&&n.rect.h===size.h?n.rect:null;});}
async function closed(){await h.waitFor(async()=>!(await nodes('wizard.window')).some(shown)||null);}
/** Island B v3（e1372d88）：侧栏头部的“+”菜单（sidebar.new › sidebar.new.host）已删，新建主机在侧栏底部（空态是 sidebar.empty.new），直接打开连接向导窗口。 */
async function openWizard(){const id=(await nodes('sidebar.empty.new')).some(shown)?'sidebar.empty.new':'sidebar.footer.new';await click(id);await frame(WINDOW);await visible('wizard.name');}
/** Track `tracked` per frame while `trigger` is pressed and until `settle` (default: the tracked node) rests. */
async function track(name:string,tracked:string,trigger:string,settleId=tracked,accept:(r:any)=>boolean=()=>true){
 await settled(tracked);await reveal(trigger);await settled(tracked);
 await h.trackStart(tracked);await press(trigger);await settled(settleId,accept);
 const samples=(await h.trackStop()).filter(n=>n.found);assert(samples.length>1,name+': tracked frames');report.tracks[name]=samples;return samples;
}
/** One user toggle of the advanced disclosure, tracked on the section card: a continuous height transition. */
async function disclose(name:string){
 const start=(await settled('wizard.advanced.card')).h;
 const samples=await track(name,'wizard.advanced.card','wizard.advanced.toggle','wizard.advanced.card',r=>Math.abs(r.h-start)>10);
 const first=samples[0].h,last=samples.at(-1)!.h,delta=Math.abs(last-first),low=Math.min(first,last),high=Math.max(first,last),grow=last>first;
 assert(Math.abs(first-start)<.2,name+' starts from the resting height');
 assert(delta>10,name+' changes height');
 // The section keeps its place: nothing above it moves, so its top edge is fixed for every frame.
 assert(samples.every(n=>Math.abs(n.y-samples[0].y)<.2&&Math.abs(n.x-samples[0].x)<.2&&Math.abs(n.w-samples[0].w)<.2),name+' keeps its origin and width');
 assert(samples.every(n=>n.h>=low-.2&&n.h<=high+.2),name+' never leaves the range between its two resting heights');
 if(!reduced){
  const inner=samples.filter(n=>n.h>low+1&&n.h<high-1);
  assert(inner.length>=3,name+' has intermediate frames ('+inner.length+')');
  // Monotonic, and no single frame covers half of the distance: a continuous transition, not a jump.
  for(let i=1;i<samples.length;i++){const step=samples[i].h-samples[i-1].h;assert(grow?step>=-.2:step<=.2,name+' is monotonic at frame '+i);assert(Math.abs(step)<delta/2,name+' frame '+i+' steps '+step+' of '+delta);}
  const moving=samples.filter(n=>Math.abs(n.h-first)>.2&&Math.abs(n.h-last)>.2),span=moving.at(-1)!.t-moving[0].t;
  assert(span>=60&&span<=600,name+' transition lasts about 200 ms (layout_motion.Height), got '+span);
 }else assert(samples.every(n=>Math.abs(n.h-first)<.2||Math.abs(n.h-last)<.2),name+' skips geometry interpolation');
 return last;
}
/** Toggle the disclosure while tracking a node that must not move at all. */
async function still(name:string,tracked:string){
 const start=(await settled('wizard.advanced.card')).h;
 const samples=await track(name,tracked,'wizard.advanced.toggle','wizard.advanced.card',r=>Math.abs(r.h-start)>10);
 const a=samples[0];assert(samples.every(n=>Math.abs(n.x-a.x)<.2&&Math.abs(n.y-a.y)<.2&&Math.abs(n.w-a.w)<.2&&Math.abs(n.h-a.h)<.2),name+': '+tracked+' does not move while the section animates');
}
/** Switch the authentication mode: the credential card takes its new natural height without leaving the range. */
async function authenticate(name:string,trigger:string){
 const before=await settled('wizard.auth.card'),gap=(await settled('wizard.advanced.card')).y-before.y-before.h;
 const samples=await track(name,'wizard.auth.card',trigger,'wizard.auth.card',r=>Math.abs(r.h-before.h)>10);
 const first=samples[0].h,last=samples.at(-1)!.h,low=Math.min(first,last),high=Math.max(first,last);
 assert(Math.abs(first-last)>10,name+' changes height');
 assert(samples.every(n=>Math.abs(n.y-samples[0].y)<.2&&n.h>=low-.2&&n.h<=high+.2),name+' keeps its origin and stays between its two heights');
 if(reduced)assert(samples.every(n=>Math.abs(n.h-first)<.2||Math.abs(n.h-last)<.2),name+' skips geometry interpolation');
 // The section below follows at the same distance; the window frame and the footer are untouched.
 const after=await settled('wizard.auth.card'),below=await settled('wizard.advanced.card');
 assert(Math.abs(below.y-after.y-after.h-gap)<.2,name+': the advanced section follows the credential card');
 return last;
}
// ── disclosure chevron direction, read from the screenshot (the Harness tree carries no icon identity) ──
/** Minimal PNG decoder (8-bit RGB/RGBA, non-interlaced) → luminance. */
function decodePng(bytes:Buffer){
 let offset=8,width=0,height=0,colorType=0;const idat:Buffer[]=[];
 while(offset<bytes.length){const length=bytes.readUInt32BE(offset),type=bytes.toString('latin1',offset+4,offset+8),data=bytes.subarray(offset+8,offset+8+length);
  if(type==='IHDR'){width=data.readUInt32BE(0);height=data.readUInt32BE(4);colorType=data[9];if(data[8]!==8||data[12]!==0||(colorType!==6&&colorType!==2))throw new Error('unsupported PNG');}
  else if(type==='IDAT')idat.push(data);else if(type==='IEND')break;offset+=12+length;}
 const channels=colorType===6?4:3,raw=inflateSync(Buffer.concat(idat)),stride=width*channels,luma=new Float32Array(width*height),previous=Buffer.alloc(stride),line=Buffer.alloc(stride);
 for(let y=0;y<height;y++){const filter=raw[y*(stride+1)],source=raw.subarray(y*(stride+1)+1,(y+1)*(stride+1));
  for(let x=0;x<stride;x++){const a=x>=channels?line[x-channels]:0,b=previous[x],c=x>=channels?previous[x-channels]:0;let v=source[x];
   if(filter===1)v+=a;else if(filter===2)v+=b;else if(filter===3)v+=(a+b)>>1;else if(filter===4){const p=a+b-c,pa=Math.abs(p-a),pb=Math.abs(p-b),pc=Math.abs(p-c);v+=pa<=pb&&pa<=pc?a:pb<=pc?b:c;}line[x]=v&0xff;}
  for(let x=0;x<width;x++)luma[y*width+x]=0.2126*line[x*channels]+0.7152*line[x*channels+1]+0.0722*line[x*channels+2];line.copy(previous);}
 return {width,height,luma};
}
/** The advanced row's chevron: the 14 pt icon at the end of wizard.advanced.toggle (editor.zig `disclosure`). */
async function chevronRect(){const t=await visible('wizard.advanced.toggle');const icons=flatten(t).filter((n:any)=>n.rect&&n.rect.w===14&&n.rect.h===14&&!(n.children?.length));assert.equal(icons.length,1,'one 14 pt chevron in the advanced row');return icons[0].rect;}
/** Ink bounding box of the glyph inside `r` (logical pt) of a window screenshot: wide = pointing down, tall = right. */
async function glyph(path:string,r:any,windowWidth:number){
 const img=decodePng(await readFile(path)),k=img.width/windowWidth,x0=Math.floor(r.x*k),y0=Math.floor(r.y*k),x1=Math.ceil((r.x+r.w)*k),y1=Math.ceil((r.y+r.h)*k);
 const ring:number[]=[];for(let x=x0-2;x<=x1+1;x++)ring.push(img.luma[(y0-2)*img.width+x],img.luma[(y1+1)*img.width+x]);ring.sort((a,b)=>a-b);const bg=ring[ring.length>>1];
 let minX=1e9,minY=1e9,maxX=-1,maxY=-1;for(let y=y0;y<y1;y++)for(let x=x0;x<x1;x++)if(Math.abs(img.luma[y*img.width+x]-bg)>40){minX=Math.min(minX,x);maxX=Math.max(maxX,x);minY=Math.min(minY,y);maxY=Math.max(maxY,y);}
 assert(maxX>=0,'chevron has ink in '+path);const w=(maxX-minX+1)/k,h=(maxY-minY+1)/k;return {w,h,direction:w>h*1.3?'down':h>w*1.3?'right':'unclear'};
}
const chevrons:any={};
try{
 await h.waitForServerReady(30000);await h.resizeWindow(1440,900);await openWizard();
 const initial={window:await frame(WINDOW),footer:await settled('wizard.footer'),auth:await settled('wizard.auth.card'),card:await settled('wizard.advanced.card')};
 assert(!(await current('wizard.advanced.body')),'advanced body is hidden while collapsed');
 const expanded=await disclose('expand');await h.screenshot(out+'/expanded.png');chevrons.expanded=await glyph(out+'/expanded.png',await chevronRect(),WINDOW.w);
 {
  const body=await visible('wizard.advanced.body'),card=await settled('wizard.advanced.card');
  assert(Math.abs(card.y+card.h-body.rect.y-body.rect.h)<.5&&body.rect.h>100,'expanded section ends with its whole body');assert(expanded>initial.card.h+100);
 }
 assert(Math.abs(await disclose('collapse')-initial.card.h)<.2,'collapse returns to the resting height');await h.screenshot(out+'/collapsed.png');chevrons.collapsed=await glyph(out+'/collapsed.png',await chevronRect(),WINDOW.w);
 assert(!(await current('wizard.advanced.body')),'advanced body is hidden again');
 // Nothing else jumps while the section moves: the card above it, the footer and the window frame stay put.
 await still('expand-footer','wizard.footer');await still('collapse-auth','wizard.auth.card');
 await still('expand-window','wizard.window');await still('collapse-toggle','wizard.advanced.toggle');
 const key=await authenticate('key','wizard.auth.key'),agent=await authenticate('agent','wizard.auth.agent'),password=await authenticate('password','wizard.auth.password');
 assert(key>password&&password>agent,'key › password › agent credential heights: '+[key,password,agent]);
 for(const [id,rect] of [['wizard.footer',initial.footer],['wizard.auth.card',initial.auth],['wizard.advanced.card',initial.card]] as const)assert.deepEqual(await settled(id),rect,id+' restored');
 assert.deepEqual(await frame(WINDOW),initial.window);
 {
  // Six rapid reversals (25 ms apart, input pacing — shorter than the 200 ms transition): each reversal continues
  // from the current height, and the even count settles back at the collapsed height.
  const toggle=await reveal('wizard.advanced.toggle');await h.trackStart('wizard.advanced.card');
  for(let i=0;i<6;i++){assert((await h.clickAt(toggle.rect.x+toggle.rect.w/2,toggle.rect.y+toggle.rect.h/2)).ok);await h.sleep(25);}
  const rest=await settled('wizard.advanced.card',r=>Math.abs(r.h-initial.card.h)<.2);const samples=(await h.trackStop()).filter(n=>n.found);report.tracks.rapid=samples;
  assert.deepEqual(rest,initial.card);assert(samples.every(n=>n.h>=initial.card.h-.2&&n.h<=expanded+.2&&Math.abs(n.y-initial.card.y)<.2),'rapid reversals stay within the two resting heights');
  if(!reduced){assert(samples.some(n=>n.h>initial.card.h+1&&n.h<expanded-1),'rapid reversals pass through intermediate heights');for(let i=1;i<samples.length;i++)assert(Math.abs(samples[i].h-samples[i-1].h)<(expanded-initial.card.h)/2,'rapid reversal frame '+i+' does not jump');}
  assert(!(await current('wizard.advanced.body')));assert.deepEqual(await settled('wizard.footer'),initial.footer);
 }
 report.checks.push('Disclosure expansion/collapse, authentication changes, and six rapid reversals settle correctly.');
 // Minimum editor window: the frame stays bounded, the footer stays inside it and the expanded section scrolls
 // inside the step viewport.
 assert((await h.resizeWindow(MINIMUM.w,MINIMUM.h)).ok);await frame(MINIMUM);
 await disclose('compact-expand');
 {
  const win=await frame(MINIMUM),foot=await settled('wizard.footer'),area=await settled('wizard.scroll.identity'),card=await settled('wizard.advanced.card');
  assert(foot.y+foot.h<=win.h&&foot.x>=0&&foot.x+foot.w<=win.w,'footer inside the minimum window');assert(area.y+area.h<=foot.y+.5,'scroll viewport ends above the footer');
  assert(card.h>area.h,'expanded section is taller than the viewport and scrolls inside it');
  await reveal('wizard.startup');await h.screenshot(out+'/compact.png');assert.deepEqual(await settled('wizard.footer'),foot);
 }
 report.checks.push('Compact layout stays bounded with internally scrolling expanded content.');
 // Close in the middle of a collapse transition (Escape = cancel, wizard.zig windowKey), then reopen: the new
 // editor starts collapsed at the default size and its disclosure animates again.
 await press('wizard.advanced.toggle');assert((await h.key('escape')).ok);await closed();
 await openWizard();assert.deepEqual(await settled('wizard.advanced.card'),initial.card);assert(!(await current('wizard.advanced.body')));
 assert(Math.abs(await disclose('reopened-expand')-expanded)<.2);
 await click('wizard.cancel');await closed();
 report.checks.push('Closing during a disclosure transition and reopening safely releases scoped animation hooks.');
 // Back on the main window (the editor window is gone): the sidebar host group folds with the same motion.
 {
  const open=await settled('sidebar.group.card');
  await h.trackStart('sidebar.group.card');await click('sidebar.group');const folded=await settled('sidebar.group.card',r=>Math.abs(r.h-open.h)>10);
  const group=(await h.trackStop()).filter(n=>n.found);report.tracks.group=group;
  assert(folded.h<open.h&&group.every(n=>n.h>=folded.h-.2&&n.h<=open.h+.2&&Math.abs(n.y-open.y)<.2),'group folds within its two heights');
  if(!reduced)assert(group.some(n=>n.h>folded.h+.2&&n.h<open.h-.2),'group has intermediate frames');
  else assert(group.every(n=>Math.abs(n.h-open.h)<.2||Math.abs(n.h-folded.h)<.2),'group skips geometry interpolation');
  if(persisted)await h.waitFor(async()=>/collapsed\s*=\s*true/.test(await readFile(dir+'/data/hosts.toml','utf8'))||null);
  await click('sidebar.group');assert.deepEqual(await settled('sidebar.group.card',r=>Math.abs(r.h-open.h)<.2),open);
  if(persisted)await h.waitFor(async()=>!/collapsed\s*=\s*true/.test(await readFile(dir+'/data/hosts.toml','utf8'))||null);
  report.checks.push(persisted?'Persisted group preserves motion across committed list rebuilds.':'Default host group folds and reopens without a list rebuild.');
 }
 // The advanced row's chevron shows the section state: chevron_right collapsed, chevron_down expanded
 // (editor.zig refreshEditorRows: `paintIcon(advanced_chevron, if (advanced_expanded) chevron_down else chevron_right)`).
 report.chevrons=chevrons;
 assert.equal(chevrons.collapsed.direction,'right','collapsed advanced section shows chevron_right: '+JSON.stringify(chevrons));
 assert.equal(chevrons.expanded.direction,'down','expanded advanced section shows chevron_down: '+JSON.stringify(chevrons));
 report.checks.push('Advanced disclosure chevron follows the section state.');
 report.status='passed';
}catch(e){report.status='failed';report.error=String((e as any)?.stack??e);await h.screenshot(out+'/failure.png').catch(()=>{});process.exitCode=1;}
finally{app.kill('SIGTERM');await Promise.race([ended,h.sleep(2000)]);await log.close();await writeFile(out+'/report.json',JSON.stringify(report,null,2));}
console.log(JSON.stringify({status:report.status,reduced,checks:report.checks,error:report.error,out}));
