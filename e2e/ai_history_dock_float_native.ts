/** Long (virtualized) AI history across float -> docked split -> float: the conversation node is moved,
 * not rebuilt, so the reader's place must survive, the list must keep a bounded set of resident rows, and
 * user bubbles (inside recycled rows too) must follow the message column's width (85%, at most 560) without
 * leaving the column. Private data / RPC only.
 *   node e2e/ai_history_dock_float_native.ts <prefix> <out> [light|dark]
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdir,mkdtemp,open,writeFile,realpath} from 'node:fs/promises';
import {resolve,join} from 'node:path';
import {aiToggleId} from './ai_entry.ts';
const prefix=resolve(process.argv[2]),out=resolve(process.argv[3]),theme=process.argv[4]==='light'?'light':'dark';
await mkdir(out,{recursive:true});
const iso=await realpath(await mkdtemp('/tmp/zw-history-dock-'));
const data=join(iso,'data'),rpc=join(iso,'rpc'),zdot=join(iso,'zdot');
for(const p of [data,rpc,zdot])await mkdir(p);
await writeFile(join(zdot,'.zshrc'),"PS1='dock%# '\n");
await writeFile(join(data,'config.toml'),`[ui]\ntheme="${theme}"\n[ai]\ndefault_provider="perf"\n[[ai.providers]]\nid="perf"\nkind="openai_compat"\nendpoint="http://127.0.0.1:9/v1/chat/completions"\nenabled=true\n[[ai.providers.models]]\nname="perf"\ncontext_window=200000\ndefault=true\n`);
const messages:any[]=[],display:any[]=[];
const long='https://example.com/'+'averyveryverylongpathsegment'.repeat(10);
for(let i=0;i<300;i++){
 // Every third question is long enough to hit the bubble's width cap (an unbreakable run included).
 const text=`历史问题 ${i}：`+(i%3===0?`这一条问题很长，用来撑满用户气泡的宽度上限，并带一个不可断开的长串 ${long} 结束。`:'验证停靠与浮动切换。'),answer=`历史回答 ${i}：保留 **格式**。\n\n这里是第 ${i} 条记录的正文，停靠、浮动来回切换之后阅读位置应当还在这里。`;
 messages.push({role:'user',content:text},{role:'assistant',content:answer});
 const turn={id:i+1,task_id:null,sent_at_ms:i*1000,ended_at_ms:i*1000+100,started_mono_ms:0,elapsed_ms:100,input_tokens:10,output_tokens:20,request_count:1,thinking_started_ms:null,thinking_ended_ms:null,thinking_expanded:false,file_source:null,before:[],after:[],answer,prose:answer,thinking:'',steps:[],notices:[],timeline:[{message:{text:answer,started_ms:0,ended_ms:100,expanded:false,submission:null}}],groups:[]};
 display.push({user:true,text,wire_text:null,turn,attachments:null,images:null},{user:false,text:answer,wire_text:null,turn:null,attachments:null,images:null});
}
await writeFile(join(data,'ai-sessions.v4.jsonl'),JSON.stringify({schema:1,event:{kind:'migrate_closed',initial_origin:{session:987654},conversation:'11111111111111111111111111111111',revision:2,turn:300,presentation:JSON.stringify({schema:1,messages:display})},messages})+'\n');
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const h=await import(join(prefix,'share/zenit/harness/client.ts'));
const log=await open(join(out,'app.log'),'w');
const app=spawn(join(prefix,'bin/zerowork'),[],{env:{...process.env,ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',ZDOTDIR:zdot,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1'},stdio:['ignore',log.fd,log.fd]});
const ended=new Promise(r=>app.once('exit',(code,signal)=>r({code,signal})));
const shown=(n:any)=>n&&!n.hidden&&n.visible!==false&&(n.effective_opacity??1)>0&&n.rect?.w>0&&n.rect?.h>0;
const visible=(id:string)=>h.waitFor(async()=>(await h.query(id)).find(shown)||null,30000);
const click=async(id:string)=>{report.stage=id;await visible(id);await h.sleep(250);const n=await visible(id);assert((await h.clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok,id)};
const flat=(n:any):any[]=>Array.isArray(n)?n.flatMap(flat):n?[n,...(n.children??[]).flatMap(flat)]:[];
const report:any={prefix,theme,isolated:iso,history_messages:600,status:'running',stages:[]};
const shot=(name:string)=>h.screenshot(join(out,`${theme}-${name}.png`));
/** The questions on screen (index + rects), the resident row count and the list's geometry. */
/** Wait until the conversation's layout is at rest (two identical reads 150 ms apart); a list that keeps moving fails here. */
async function settled(stage:string){
 const read=async()=>JSON.stringify([(await h.query('ai.conversation.viewport')).map((n:any)=>n.rect),flat(await h.query('ai.history.virtual')).filter((n:any)=>n.test_id==='ai.message.user.row'||n.test_id==='ai.history.virtual').map((n:any)=>n.rect)]);
 let last=await read();
 for(let i=0;i<40;i++){await h.sleep(150);const now=await read();if(now===last)return;last=now;}
 assert.fail(`${stage}: the history layout does not come to rest`);
}
async function sample(stage:string){
 await settled(stage);
 const view=(await visible('ai.conversation.viewport')).rect;
 const rows=flat(await h.query('ai.message.user.row')).filter((n:any)=>n.test_id==='ai.message.user.row');
 assert(rows.length>0&&rows.length<40,`${stage}: resident user rows ${rows.length}`);
 const seen:any[]=[];
 for(const row of rows){
  const nodes=flat(row);
  const text=nodes.find((n:any)=>n.test_id==='ai.message.user.text');const bubble=nodes.find((n:any)=>n.test_id==='ai.message.user.bubble');
  if(!text||!bubble)continue;
  const index=Number(/历史问题 (\d+)：/.exec(text.text??'')?.[1]??-1);
  const inView=bubble.rect.y+bubble.rect.h>view.y+1&&bubble.rect.y<view.y+view.h-1;
  if(!(row.rect?.h>0))continue; // mounted in a slot that has not been laid out yet (reported as `unlaid` below)
  seen.push({index,inView,row:row.rect,bubble:bubble.rect,text:text.rect});
 }
 seen.sort((a,b)=>a.index-b.index);
 const onScreen=seen.filter(s=>s.inView);
 // Width contract (REQUESTS #91) for every resident bubble: at most 85% of the column and 560, inside the column, text inside the bubble.
 for(const s of seen){
  assert(s.bubble.w<=Math.min(view.w*0.85,560)+1,`${stage}: bubble ${s.index} is ${s.bubble.w} wide in a ${view.w} viewport`);
  assert(s.bubble.x>=view.x-0.5&&s.bubble.x+s.bubble.w<=view.x+view.w+0.5,`${stage}: bubble ${s.index} leaves the column ${JSON.stringify(s.bubble)} / ${JSON.stringify(view)}`);
  assert(s.text.x>=s.bubble.x-0.5&&s.text.x+s.text.w<=s.bubble.x+s.bubble.w+0.5,`${stage}: text ${s.index} leaves its bubble`);
 }
 // Resident rows in data order must not overlap (a stale row height would show here).
 let overlaps=0;for(let i=1;i<seen.length;i++)if(seen[i].index===seen[i-1].index+1&&seen[i].row.y<seen[i-1].row.y+seen[i-1].row.h-1)overlaps++;
 const list=(await h.query('ai.history.virtual')).find((n:any)=>n.rect?.h>0);
 // Every mounted row's slot is exactly as tall as the row laid out at the current width (a row measured
 // at another width and still locked to that height would leave a gap or overlap), and slots are contiguous.
 const slots=((list?.children??[])[0]?.children??[]).filter((n:any)=>(n.children??[]).length>0&&n.rect?.h>0);
 assert(slots.length>0,`${stage}: the list has mounted rows`);
 let stale=0;for(let i=0;i<slots.length;i++){
  if(Math.abs(slots[i].rect.h-slots[i].children[0].rect.h)>1)stale++;
  if(i>0&&Math.abs(slots[i].rect.y-(slots[i-1].rect.y+slots[i-1].rect.h))>1)stale++;
 }
 assert.equal(stale,0,`${stage}: ${stale} mounted row slot(s) do not match their row's height / are not contiguous`);
 // Every slot that holds a row is laid out (zenit: a node mounted while its subtree is held hidden by the dock flight is laid out on landing).
 const unlaid=((list?.children??[])[0]?.children??[]).filter((n:any)=>(n.children??[]).length>0&&!(n.rect?.h>0)).map((n:any)=>Number(/历史问题 (\d+)：/.exec(flat(n).map((x:any)=>x.text??'').join(' '))?.[1]??-1));
 assert.deepEqual(unlaid,[],`${stage}: rows mounted without a layout: ${JSON.stringify(unlaid)}`);
 const entry={stage,view,unlaid,resident:rows.length,on_screen:onScreen.map(s=>s.index),widest_bubble:Math.max(...seen.map(s=>s.bubble.w)),overlaps,rows:seen.map(s=>({index:s.index,y:s.row.y,h:s.row.h,bubble_h:s.bubble.h})),list_height:list?.rect.h};
 report.stages.push(entry);return entry;
}
try{
 await h.waitForServerReady(60000);await h.resizeWindow(1440,1000);
 await click('workspace.empty.local');await visible('terminal.surface');await click(await aiToggleId());await visible('ai.panel');
 await visible('ai.empty.recent');await click('ai.session.copy_use.1');
 if((await h.query('ai.session.close.accept')).some(shown))await click('ai.session.close.accept');
 report.stage='virtual history';await visible('ai.history.virtual');await h.sleep(500);
 const v=await h.screenPos('ai.conversation.viewport');
 // Read back into the middle of the history (never-measured rows above the reader).
 for(let i=0;i<30;i++)await h.scrollAt(v.x+v.w/2,v.y+v.h/2,0,700);
 await h.sleep(600);
 const floating=await sample('float');await shot('float');
 assert(floating.on_screen.length>0,'a question is on screen');assert.equal(floating.overlaps,0,'float: rows do not overlap');
 const anchor=floating.on_screen;
 const still=(s:any,name:string)=>assert(s.on_screen.some((i:number)=>anchor.some((a:number)=>Math.abs(a-i)<=2)),`${name}: the reader's place is kept (was ${JSON.stringify(anchor)}, now ${JSON.stringify(s.on_screen)})`);

 // Dock into the split: same conversation node, other width.
 const conversation=(await visible('ai.conversation')).id;
 await click('ai.dock_to_split');await visible('ai.pane');await h.sleep(1200);
 assert.equal((await visible('ai.conversation')).id,conversation,'the conversation node is moved, not rebuilt');
 const docked=await sample('docked');await shot('docked');
 still(docked,'docked');assert.equal(docked.overlaps,0,'docked: rows do not overlap');

 // Scroll while docked (rows recycle at the docked width), then back to the anchor.
 const dv=await h.screenPos('ai.conversation.viewport');
 for(let i=0;i<6;i++)await h.scrollAt(dv.x+dv.w/2,dv.y+dv.h/2,0,600);
 await h.sleep(400);const dockedUp=await sample('docked-scrolled');assert.equal(dockedUp.overlaps,0,'docked scrolled: rows do not overlap');
 assert(Math.max(...dockedUp.on_screen)<Math.max(...docked.on_screen),'scrolling up shows earlier questions');
 for(let i=0;i<6;i++)await h.scrollAt(dv.x+dv.w/2,dv.y+dv.h/2,0,-600);
 await h.sleep(400);const dockedBack=await sample('docked-back');still(dockedBack,'docked, scrolled up and back');

 // To the end while docked: the last questions are reachable, the list still holds few rows.
 await h.scrollAt(dv.x+dv.w/2,dv.y+dv.h/2,0,-10000000);await h.sleep(600);
 const end=await sample('docked-end');assert(end.on_screen.includes(299)||end.on_screen.includes(298),`the end shows the last questions (${JSON.stringify(end.on_screen)})`);
 assert.equal(end.overlaps,0,'docked end: rows do not overlap');await shot('docked-end');
 for(let i=0;i<40&&!(await sample('seek')).on_screen.some((x:number)=>anchor.includes(x));i++)await h.scrollAt(dv.x+dv.w/2,dv.y+dv.h/2,0,700);
 report.stages=report.stages.filter((s:any)=>s.stage!=='seek');

 // Float again: the same node, the reader's place, the floating width.
 await click('ai.pane.float');await visible('ai.panel');await h.sleep(1200);
 assert.equal((await visible('ai.conversation')).id,conversation,'floating again: still the same conversation node');
 const again=await sample('float-again');await shot('float-again');
 still(again,'floating again');assert.equal(again.overlaps,0,'float again: rows do not overlap');

 assert((await h.request('POST','/zerowork/windows',{action:'quit'})).ok);
 const deadline=performance.now()+20000;
 while(app.exitCode===null&&app.signalCode===null&&performance.now()<deadline){for(const id of ['local.close.accept','session.close.accept','groups.close.accept'])try{if((await h.query(id)).some(shown))await h.clickTestId(id)}catch{};await h.sleep(80)}
 assert.notEqual(app.exitCode,null,'normal Quit completes');assert.deepEqual(await ended,{code:0,signal:null});report.status='passed';
}catch(e){report.status='failed';report.error=String(e);process.exitCode=1;await h.screenshot(join(out,`${theme}-failure.png`)).catch(()=>{})}
finally{if(app.exitCode===null&&app.signalCode===null){app.kill('SIGTERM');await ended}await log.close();await writeFile(join(out,`report-${theme}.json`),JSON.stringify(report,null,2));}
console.log(JSON.stringify(report,null,2));
