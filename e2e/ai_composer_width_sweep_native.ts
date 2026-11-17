/** AI composer width sweep (ai-redesign-a; user feedback “AI chat的内容UI元素都溢出了”).
 * Floating panel 320 → 640 in steps of 20, docked pane 560 and 800, in the given theme. At every
 * width each child of the composer (the tool row and the text field) lies inside the panel's content
 * rect; the shrink order holds (model text first, then permission, then run mode into native icon
 * Buttons); usage and send stay; hint tooltips stay inside the window.
 * node e2e/ai_composer_width_sweep_native.ts <test-mode zerowork> <out> <light|dark>
 * Local loopback model fixture only; isolated data dir. */
import './regression/build_mode_guard.mjs';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createServer} from 'node:http';
import {mkdtemp,mkdir,writeFile,open,realpath} from 'node:fs/promises';
import {join,resolve,dirname} from 'node:path';
import {isTitleRequest,skipTitle} from './ai_title_fixture.ts';
import {readRequestJson} from './provider_fixture.ts';
const binary=resolve(process.argv[2]??'zig-out/bin/zerowork');
const out=resolve(process.argv[3]??'/tmp/zw-ai-composer-width-sweep');
const theme=process.argv[4]==='dark'?'dark':'light';
await mkdir(out,{recursive:true});
const h=await import(join(dirname(dirname(binary)),'share/zenit/harness/client.ts'));
const report:any={theme,status:'running',widths:[],checks:[]};
const save=()=>writeFile(join(out,'report.json'),JSON.stringify(report,null,2));
const shown=(n:any)=>n&&n.hidden!==true&&n.visible!==false&&(n.effective_opacity??1)>0&&n.rect?.w>0&&n.rect?.h>0;
const flat=(n:any):any[]=>n?[n,...(n.children??[]).flatMap(flat)]:[];
const text=(n:any)=>flat(n).map((x:any)=>x.text??'').join('');
const visible=(id:string,ms=15000)=>h.waitFor(async()=>(await h.query(id)).find(shown)??null,ms);
const click=async(id:string)=>{const n=await visible(id);assert((await h.clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok,id);};
const inside=(r:any,box:any,what:string)=>assert(r.x>=box.x-.5&&r.y>=box.y-.5&&r.x+r.w<=box.x+box.w+.5&&r.y+r.h<=box.y+box.h+.5,`${what} ${JSON.stringify(r)} inside ${JSON.stringify(box)}`);
const server=createServer(async(req,res)=>{
 if(req.method!=='POST'){res.writeHead(200,{'content-type':'application/json'});res.end(JSON.stringify({data:[{id:'claude-sonnet-4-20250514-extended-thinking'}]}));return;}
 const body=await readRequestJson(req);if(isTitleRequest(body))return skipTitle(res);
 res.writeHead(200,{'content-type':'text/event-stream'});res.end('data: '+JSON.stringify({choices:[{index:0,delta:{content:'好的。'}}]})+'\n\ndata: [DONE]\n\n');
});
await new Promise<void>(r=>server.listen(0,'127.0.0.1',r));const port=(server.address() as any).port;
const iso=await realpath(await mkdtemp('/tmp/zw-ai-width-sweep-')),data=join(iso,'data'),rpc=join(iso,'rpc');await mkdir(data);await mkdir(rpc);
await writeFile(join(data,'config.toml'),`[meta]\nconfig_revision=1\n[updates]\nauto_check=false\n[ui]\ntheme="${theme}"\nfont_family="Menlo"\nfont_size=14\n[ai]\ndefault_provider="sweep"\npermission_mode="confirm"\n[[ai.providers]]\nid="sweep"\nkind="openai_compat"\nendpoint="http://127.0.0.1:${port}/v1/chat/completions"\napi_key="local-only"\nenabled=true\n[[ai.providers.models]]\nname="claude-sonnet-4-20250514-extended-thinking"\ncontext_window=200000\ndefault=true\nreasoning=true\nefforts=["low","medium","high"]\n`);
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const log=await open(join(out,'app.log'),'w');
const app=spawn(binary,[],{env:{...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1',ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0'},stdio:['ignore',log.fd,log.fd]});
const ended=new Promise<void>(r=>app.once('close',()=>r()));
let windowW=1440,windowH=900;
const resize=async(w:number,hh:number)=>{windowW=w;windowH=hh;await h.resizeWindow(w,hh);await h.sleep(500);};
const drag=async(x0:number,y0:number,x1:number,y1:number)=>{await h.mouseMove(x0,y0);await h.mouseDown(x0,y0);for(let i=1;i<=10;i++){await h.mouseMove(x0+(x1-x0)*i/10,y0+(y1-y0)*i/10);await h.sleep(16);}await h.mouseUp(x1,y1);await h.mouseMove(20,300);};
/** Every composer child inside the container's content rect, the shrink order, usage + send present. */
async function checkComposer(name:string,containerId:string){
 await h.sleep(500);
 const container=await visible(containerId);const box={x:container.rect.x+1,y:container.rect.y+1,w:container.rect.w-2,h:container.rect.h-2};
 const composer=await visible('ai.composer');inside(composer.rect,container.rect,`${name}: composer area`);
 const row=await visible('ai.composer.controls');const controls=(row.children??[]).filter(shown);
 for(const child of controls)inside(child.rect,box,`${name}: tool row child ${child.test_id??child.component??child.tag}`);
 for(const child of flat(row).filter(shown))inside(child.rect,box,`${name}: tool row node ${child.test_id??child.component??child.tag}`);
 for(const id of ['ai.prompt','ai.composer.attachment','ai.composer.usage','ai.composer.model','ai.send'])inside((await visible(id)).rect,box,`${name}: ${id}`);
 const compact={permission:(await h.query('ai.composer.permission.compact')).some(shown),execution:(await h.query('ai.composer.execution.compact')).some(shown)};
 assert(compact.permission!==(await h.query('ai.composer.permission')).some(shown),`${name}: exactly one permission control`);
 assert(compact.execution!==(await h.query('ai.composer.execution')).some(shown),`${name}: exactly one run mode control`);
 if(compact.execution)assert(compact.permission,`${name}: run mode collapses only after permission`);
 const model=text(await visible('ai.composer.model'));
 if(compact.permission)assert(model.includes('…'),`${name}: permission collapses only after the model text is cut (${model})`);
 // Controls never overlap one another.
 const rects=controls.map((c:any)=>c.rect).sort((a:any,b:any)=>a.x-b.x);for(let i=1;i<rects.length;i++)assert(rects[i].x>=rects[i-1].x+rects[i-1].w-.5,`${name}: tool row controls overlap`);
 await h.screenshot(join(out,`${theme}-${name}.png`));
 report.widths.push({name,container:container.rect,compact,model});await save();
 return compact;
}
/** A native hint Tooltip shown by hovering `trigger` stays inside the window. */
async function checkTooltip(name:string,trigger:string,tooltip:string){
 const t=(await h.query(trigger)).find(shown);if(!t)return;
 await h.mouseMove(t.rect.x+t.rect.w/2,t.rect.y+t.rect.h/2);
 const tip=await visible(tooltip,4000).catch(()=>null);
 if(tip)inside(tip.rect,{x:0,y:0,w:windowW,h:windowH},`${name}: ${tooltip} inside the window`);
 report.checks.push({name,tooltip,rect:tip?.rect??null});
 await h.mouseMove(20,300);await h.sleep(200);
}
try{
 await h.waitForServerReady(60000);
 await resize(1440,900);await click('workspace.empty.local');await visible('terminal.surface');await h.mouseMove(20,300);await h.sleep(300);
 await click('ai.launcher');await visible('ai.panel');await h.sleep(600);
 await click('ai.prompt');await h.type_('宽度扫描草稿');await h.sleep(300);
 const widths:number[]=[];for(let w=320;w<=640;w+=20)widths.push(w);
 let collapsedAt320:any=null;
 for(const target of widths){
  for(let attempt=0;attempt<3;attempt++){
   const panel=(await visible('ai.panel')).rect;if(Math.abs(panel.w-target)<1)break;
   const handle=await visible('ai.float.resize.w');const x=handle.rect.x+handle.rect.w/2,y=handle.rect.y+handle.rect.h/2;
   await drag(x,y,x+(panel.w-target),y);await h.sleep(300);
  }
  const panel=(await visible('ai.panel')).rect;
  assert(Math.abs(panel.w-target)<1.5,`floating panel width ${panel.w} for ${target}`);
  const compact=await checkComposer(`float-${target}`,'ai.panel');
  if(target===320)collapsedAt320=compact;
  if(target===320||target===640){await checkTooltip(`float-${target}`,'ai.send','ai.send.tooltip');await checkTooltip(`float-${target}`,'ai.composer.permission.compact','ai.composer.permission.compact.tooltip');}
 }
 assert(collapsedAt320.permission&&collapsedAt320.execution,'320: permission and run mode are icon Buttons');
 report.checks.push('floating 320-640 every 20: composer inside the panel, shrink order holds');
 await click('ai.dock_to_split');await visible('ai.pane');
 for(const target of [560,800]){
  let w=1440;for(let i=0;i<5;i++){await resize(w,900);const p=await visible('ai.pane');if(Math.abs(p.rect.w-target)<2)break;w=Math.round(w+(target-p.rect.w)*(i===0?2:1.5));}
  const pane=(await visible('ai.pane')).rect;assert(Math.abs(pane.w-target)<3,`docked pane width ${pane.w} for ${target}`);
  const compact=await checkComposer(`docked-${target}`,'ai.pane');
  assert(!compact.permission&&!compact.execution,`docked ${target}: every control shows its text`);
  await checkTooltip(`docked-${target}`,'ai.send','ai.send.tooltip');
 }
 report.checks.push('docked 560 / 800: composer inside the pane, all controls with text');
 report.status='passed';
}catch(e){report.status='failed';report.error=String((e as any)?.stack??e);process.exitCode=1;await h.screenshot(join(out,'failure.png')).catch(()=>{});}
finally{await save();if(app.exitCode===null&&app.signalCode===null)app.kill('SIGTERM');await Promise.race([ended,h.sleep(4000)]);if(app.exitCode===null)app.kill('SIGKILL');server.closeAllConnections();server.close();console.log(JSON.stringify({status:report.status,error:report.error}));}
