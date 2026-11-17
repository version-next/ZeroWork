/** Message-flow width sweep (Pencil Kaf7E, ai-redesign-b): at every floating width 320…640 (step 20)
 * and docked 560 / 800, nothing in the conversation leaves the panel's content column — the user
 * bubble (with an unbreakable URL), Markdown headings / paragraphs / lists, a long code block, a
 * wide table, step groups and their rows (expanded, with a failure), the tool card, the recovery
 * Alert and the turn status row. Long code and wide tables scroll inside their own area and never
 * widen the panel; unbreakable runs break or ellipsize.
 * ZW_AI_TEST_PREFIX=<test-mode prefix> node e2e/ai_message_width_sweep_native.ts <out dir> [light|dark]
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createServer} from 'node:http';
import {mkdir,mkdtemp,open,writeFile,rm} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {isTitleBody,skipTitle} from './ai_title_fixture.ts';
import {readRequestText} from './provider_fixture.ts';

const prefix=resolve(process.env.ZW_AI_TEST_PREFIX??'zig-out');
const out=resolve(process.argv[2]??'/private/tmp/zw-ai-width-sweep-evidence');
const theme=process.argv[3]??'light';
await mkdir(out,{recursive:true});
const iso=await mkdtemp('/private/tmp/zw-ai-width-sweep-'),data=join(iso,'data'),rpc=join(iso,'rpc'),zdot=join(iso,'zdot');
await mkdir(data);await mkdir(rpc);await mkdir(zdot);await writeFile(join(zdot,'.zshrc'),"PS1='sweep%# '\n");
const frame=(delta:any)=>'data: '+JSON.stringify({choices:[{index:0,delta}]})+'\n\n';
const wire=(name:string)=>name.replaceAll('_','_u').replaceAll('.','__');
const url='https://bmc.example.internal/redfish/v1/Systems/compute-bmc-01/LogServices/SEL/Entries?$filter=Created_gt_2026-09-10T01:42:07Z&$top=200&$skip=0&verbose=true';
const path='/var/lib/zerowork/very/long/path/without/any/spaces/compute-bmc-01/sel/2026-09-10T01-42-07Z/export-full-0001.json';
const code='#!/usr/bin/env bash\nset -euo pipefail\nfor host in $(cat hosts.txt); do use=$(ssh -o ConnectTimeout=5 -o BatchMode=yes "$host" "df -hP / | awk \'NR==2 {print \\$5}\'" | tr -d %); echo "$use $host"; done | sort -rn\n'+Array.from({length:30},(_,i)=>`echo line-${i} ${'x'.repeat(i*4)}`).join('\n');
const answer=`# 断电原因核查 ${url}\n\n### 结论\n\n最近一次断电在 09/10 01:42，日志路径 ${path} ，参见 ${url} 。\n\n1. 第一项 ${path}\n2. 第二项\n\n\`\`\`bash\n${code}\n\`\`\`\n\n| 时间 | 传感器 | 事件 | 详细说明 | 来源 | 记录路径 |\n| --- | --- | --- | --- | --- | --- |\n| 09/10 01:42:07 | PSU 2 | AC lost | 输入电源中断，冗余失效 | SEL | ${path} |\n| 09/10 01:42:09 | System | Power off | 机箱掉电 | SEL | ${url} |\n\nSWEEP_COMPLETE`;
let requests=0;
const server=createServer(async(req,res)=>{
 const raw=await readRequestText(req);
 if(req.method!=='POST')return res.end('{"data":[{"id":"sweep-fixture"}]}');
 if(isTitleBody(raw))return skipTitle(res);
 requests++;const body=JSON.parse(raw);
 const user=String(body.messages.findLast((m:any)=>m.role==='user')?.content??'');
 const tools=body.messages.filter((m:any)=>m.role==='tool').map((m:any)=>m.tool_call_id);
 if(user.includes('FAIL_REQUEST')){res.writeHead(429,{'content-type':'application/json','retry-after':'1'});return res.end('{"error":{"message":"Too Many Requests '+url+'","type":"rate_limit"}}');}
 res.writeHead(200,{'content-type':'text/event-stream'});
 if(!tools.includes('sweep-1'))return res.end(frame({reasoning_content:'先读取当前会话 '+path})+frame({tool_calls:[{index:0,id:'sweep-1',type:'function',function:{name:wire('host.get_current_context'),arguments:'{}'}},{index:1,id:'sweep-2',type:'function',function:{name:wire('host.run_in_terminal'),arguments:'{}'}}]})+'data: [DONE]\n\n');
 return res.end(frame({content:answer})+'data: [DONE]\n\n');
});
await new Promise<void>(r=>server.listen(0,'127.0.0.1',r));
await writeFile(join(data,'config.toml'),`[meta]\nconfig_revision=1\n[ui]\ntheme="${theme}"\nfont_size=14\n[updates]\nauto_check=false\n[ai]\ndefault_provider="sweep"\nstep_display="expanded"\n[[ai.providers]]\nid="sweep"\nkind="openai_compat"\nendpoint="http://127.0.0.1:${(server.address()as any).port}/v1/chat/completions"\nenabled=true\n[[ai.providers.models]]\nname="sweep-fixture"\ncontext_window=200000\ndefault=true\nreasoning=true\n`);
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const h=await import(join(prefix,'share/zenit/harness/client.ts'));
const log=await open(join(out,'app.log'),'w');
const app=spawn(join(prefix,'bin/zerowork'),[],{env:{...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1',ZEROWORK_DATA_DIR:data,ZDOTDIR:zdot,ZEROWORK_AUTOCONNECT:'0',OPENAI_API_KEY:'',ANTHROPIC_API_KEY:''},stdio:['ignore',log.fd,log.fd]});
const ended=new Promise<void>(r=>app.once('close',()=>r()));
const shown=(n:any)=>n&&n.visible!==false&&!n.hidden&&(n.effective_opacity??1)>0&&n.rect?.w>0&&n.rect?.h>0;
const visible=(id:string,ms=20000)=>h.waitFor(async()=>(await h.query(id)).find(shown)??null,ms);
const click=async(id:string)=>{const n=await visible(id);assert((await h.clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok,id);await h.sleep(250);};
const report:any={status:'running',theme,widths:[],violations:[]};
// Parts of the flow that must stay inside the conversation column.
const parts=['ai.message.user.bubble','ai.message.user.row','ai.response','ai.message.code','ai.message.table','ai.step_group','ai.step.header','ai.tool.result.header','ai.recovery','ai.turn.complete'];
// Content that scrolls inside its own area (clipped by it), checked by its area instead.
const scrollers=new Set(['ai.message.code.scroll','ai.step.details','ai.tool.result.details','ai.tool.result.stdout_scroll','ai.tool.result.stderr_scroll','ai.recovery.details']);
const check=async(label:string)=>{
 await h.sleep(500);
 const column=await visible('ai.conversation');
 const viewport=await visible('ai.conversation.viewport');
 const left=Math.max(column.rect.x,viewport.rect.x)-0.5,right=Math.min(column.rect.x+column.rect.w,viewport.rect.x+viewport.rect.w)+0.5;
 const found:Record<string,number>={};const bad:any[]=[];
 const walk=(n:any,root:string,inScroller:boolean)=>{
  if(!shown(n))return;
  if(!inScroller&&(n.rect.x<left||n.rect.x+n.rect.w>right))bad.push({label,root,id:n.test_id??null,text:typeof n.text==='string'?n.text.slice(0,40):null,x:n.rect.x,w:n.rect.w,left,right});
  const scroller=scrollers.has(n.test_id);
  for(const c of n.children??[])walk(c,root,inScroller||scroller);
 };
 for(const id of parts){const nodes=(await h.query(id)).filter(shown);found[id]=nodes.length;for(const n of nodes)walk(n,id,false);}
 // A long code block and a wide table stay as wide as the column; their content scrolls inside.
 for(const n of (await h.query('ai.message.code.scroll')).filter(shown))assert(n.rect.x>=left&&n.rect.x+n.rect.w<=right,label+' code viewport inside the column');
 return {found,bad,column:{x:column.rect.x,w:column.rect.w}};
};
const shot=async(name:string)=>{await h.mouseMove(2,2);await h.sleep(200);assert((await h.screenshot(join(out,name+'.png'))).ok);};
const panelWidth=async()=>(await visible('ai.panel')).rect.w;
const setFloatWidth=async(target:number)=>{
 for(let i=0;i<8;i++){
  const w=await panelWidth();if(Math.abs(w-target)<1)return w;
  const n=(await visible('ai.float.resize.w')).rect,x=n.x+n.w/2,y=n.y+n.h/2,dx=w-target;
  await h.mouseMove(x,y);await h.mouseDown(x,y);await h.mouseMove(x+dx/2,y);await h.mouseMove(x+dx,y);await h.mouseUp(x+dx,y);await h.sleep(250);
 }
 return panelWidth();
};
const expandAll=async()=>{
 for(const id of ['ai.tool.result.header','ai.step.header']){
  for(const n of (await h.query(id)).filter(shown)){if(n.a11y?.expanded===true)continue;await h.clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2);await h.sleep(200);}
 }
};
try{
 await h.waitForServerReady(60000);await h.resizeWindow(1680,1000);
 await click('workspace.empty.local');await visible('terminal.surface');
 await h.key('j',{cmd:true});await visible('ai.panel');
 await click('ai.prompt');await h.type_('SWEEP 看下这个地址 '+url);await click('ai.send');
 await h.waitFor(async()=>JSON.stringify(await h.query('ai.conversation')).includes('SWEEP_COMPLETE')||null,30000);
 await visible('ai.turn.complete',30000);
 await click('ai.prompt');await h.type_('FAIL_REQUEST');await click('ai.send');await visible('ai.recovery',30000);
 await expandAll();
 const counts:Record<string,number>={};
 for(let target=320;target<=640;target+=20){
  const w=await setFloatWidth(target);report.widths.push({mode:'float',target,actual:w});
  assert(Math.abs(w-target)<1.5,`floating panel reached ${target} (got ${w})`);
  const result=await check('float-'+target);report.violations.push(...result.bad);
  for(const [k,v] of Object.entries(result.found))counts[k]=Math.max(counts[k]??0,v);
  if(target===320||target===420||target===640){
   // Scroll the flow through so the screenshots show every part at this width.
   const v=await visible('ai.conversation.viewport');
   await h.scrollAt(v.rect.x+v.rect.w/2,v.rect.y+v.rect.h/2,0,100000);await h.sleep(300);
   for(let s=0;s<4;s++){await shot(`float-${target}-${s}`);await h.scrollAt(v.rect.x+v.rect.w/2,v.rect.y+v.rect.h/2,0,-v.rect.h*0.8);await h.sleep(250);}
   await h.scrollAt(v.rect.x+v.rect.w/2,v.rect.y+v.rect.h/2,0,-100000);await h.sleep(300);
  }
 }
 for(const id of parts)assert((counts[id]??0)>0,'the flow shows '+id);
 await click('ai.dock_to_split');await h.sleep(1200);
 for(const target of [560,800]){
  let w=0;
  // The docked pane follows the window: step the window width until the pane is at the target.
  let win=1680;
  for(let i=0;i<10;i++){
   w=(await visible('ai.content')).rect.w;if(Math.abs(w-target)<2)break;
   win=Math.round(win+(target-w)*(i<3?1.6:1));await h.resizeWindow(win,1000);await h.sleep(700);
  }
  report.widths.push({mode:'dock',target,actual:w});
  assert(Math.abs(w-target)<4,`docked pane reached ${target} (got ${w})`);
  const result=await check('dock-'+target);report.violations.push(...result.bad);
  await shot(`dock-${target}`);
 }
 assert.equal(report.violations.length,0,'message-flow parts stay inside the column: '+JSON.stringify(report.violations.slice(0,8)));
 report.status='passed';
}catch(error){report.status='failed';report.error=String(error);process.exitCode=1;await h.screenshot(join(out,'failure.png')).catch(()=>{});}
finally{
 app.kill('SIGTERM');await Promise.race([ended,h.sleep(3000)]);
 if(app.exitCode===null&&app.signalCode===null){app.kill('SIGKILL');await ended;}
 await log.close();server.closeAllConnections();await new Promise<void>(r=>server.close(()=>r()));await rm(iso,{recursive:true,force:true});
 report.requests=requests;await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));
}
console.log(report.status+': '+join(out,'report.json'));
