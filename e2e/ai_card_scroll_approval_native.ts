/** Production pending approval and recovery details. All model output is a local fixture; commands are rejected. */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createServer} from 'node:http';
import {mkdtemp,mkdir,writeFile,readFile,open,realpath} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {aiToggleId} from './ai_entry.ts';
import {isTitleRequest,skipTitle} from './ai_title_fixture.ts';
import {readRequestJson} from './provider_fixture.ts';
import {pasteboardName,readPasteboardText,writePasteboardText} from './private_pasteboard.ts';
const prefix=resolve(process.env.ZW_AI_TEST_PREFIX??'dist/patch-card-scroll-candidate'),h=await import(join(prefix,'share/zenit/harness/client.ts'));
const out=resolve(process.argv[2]??'dist/ui-acceptance/patch-card-scroll-approval');await mkdir(out,{recursive:true});
const iso=await realpath(await mkdtemp('/tmp/zw-card-approval-')),data=join(iso,'data'),rpc=join(iso,'rpc');await mkdir(data);await mkdir(rpc);
const frame=(delta:any)=>'data: '+JSON.stringify({choices:[{index:0,delta}]})+'\n\n';
let mode='approval';const requests:any[]=[];
const command=Array.from({length:60},(_,i)=>`printf 'REJECTED_SCROLL_FIXTURE_LINE_${i}\\n'`).join('\n');
const reason='Owned long failure\n'+Array.from({length:35},(_,i)=>`Failure detail line ${i+1}: keep the complete original explanation.`).join('\n');
const server=createServer(async(req,res)=>{if(req.method!=='POST'){res.end(JSON.stringify({data:[{id:'approval-scroll-fixture',context_window:200000}]}));return}const body=await readRequestJson(req);if(isTitleRequest(body))return skipTitle(res);requests.push({mode});
 if(mode==='recovery'){res.writeHead(400,{'content-type':'application/json'});res.end(JSON.stringify({error:{message:reason}}));return}
 res.writeHead(200,{'content-type':'text/event-stream'});const lastUser=body.messages.findLastIndex((m:any)=>m.role==='user');if(!body.messages.slice(lastUser+1).some((m:any)=>m.role==='tool')){assert(body.tools.some((t:any)=>t.function.name==='run_command'));res.end(frame({tool_calls:[{index:0,id:'scroll-approval-only',type:'function',function:{name:'run_command',arguments:JSON.stringify({session_ids:[1],command})}}]})+'data: [DONE]\n\n')}else res.end(frame({content:'已拒绝，未执行命令。'})+'data: [DONE]\n\n')});
await new Promise<void>(done=>server.listen(0,'127.0.0.1',done));const port=(server.address() as any).port;
await writeFile(join(data,'config.toml'),`[meta]\nconfig_revision=1\n[ui]\ntheme="dark"\n[ai]\ndefault_provider="approval-scroll-fixture"\npermission_mode="confirm"\n[[ai.providers]]\nid="approval-scroll-fixture"\nkind="openai_compat"\nendpoint="http://127.0.0.1:${port}/v1/chat/completions"\nenabled=true\n[[ai.providers.models]]\nname="approval-scroll-fixture"\ncontext_window=200000\ndefault=true\n`);
pasteboardName();
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;const log=await open(join(out,'app.log'),'w');const app=spawn(join(prefix,'bin/zerowork'),[],{env:{...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1',ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',OPENAI_API_KEY:'',ANTHROPIC_API_KEY:''},stdio:['ignore',log.fd,log.fd]});const ended=new Promise<any>(done=>app.once('exit',(code,signal)=>done({code,signal})));
// zenit ScrollArea 子节点顺序：content / track_v / track_h / bar_v / bar_h（vendor/zenit/src/ui/components/scroll_area/mod.zig 新增 track 节点），纵向 thumb 是 children[3]。
const vThumb=(n:any)=>n.children[3];
const shown=(n:any)=>n&&!n.hidden&&n.visible!==false&&(n.effective_opacity??1)>0&&n.rect?.w>0&&n.rect?.h>0;
const visible=(id:string)=>h.waitFor(async()=>(await h.query(id)).find(shown)??null,15000);
const click=async(id:string)=>{await visible(id);assert((await h.clickTestId(id)).ok,id)};
const send=async(text:string)=>{await click('ai.prompt');await h.type_(text);await click('ai.send')};
const cap=async(name:string)=>{assert((await h.screenshot(join(out,name+'.png'))).ok);await writeFile(join(out,name+'.json'),JSON.stringify(await h.query('ai.panel'),null,2))};
const report:any={status:'running',binary:join(prefix,'bin/zerowork'),checks:[],thumbs:[],limits:['Uses a local deterministic SSE/HTTP error fixture; the pending command is rejected and never approved.','Native synthetic input does not drive physical touchpad hardware.']};
try{
 await h.waitForServerReady(60000);assert.equal(Number(JSON.parse(await readFile(join(rpc,'owner.json'),'utf8')).pid),app.pid);await h.resizeWindow(1200,900);await click('workspace.empty.local');await visible('terminal.surface');await click(await aiToggleId());await send('显示待审批长命令，随后拒绝。');// 审批已移入输入区交互卡（ai_composer_interaction_view.zig）：ai.interaction.panel 自身是有界纵向 ScrollArea
 // （max_body_height=180，containVertical 留住边界滚轮），命令在其中；操作行 ai.interaction.actions 在滚动区之外固定。
 const inner=await visible('ai.interaction.panel');await h.mouseMove(2,850);await h.sleep(3000);let n=await visible('ai.interaction.panel'),thumb=vThumb(n);assert(thumb.rect.w>0&&(thumb.opacity??1)>0);report.thumbs.push({kind:'approval-command',rect:thumb.rect,opacity:thumb.opacity??1});await cap('01-approval-idle');const card=await visible('ai.interaction.panel'),feedback=await visible('ai.interaction.actions'),before=await visible('ai.interaction.command');const r=inner.rect;
 const copyRect=(await visible('ai.interaction.copy')).rect;
 await writePasteboardText('approval-copy-not-yet-clicked');
 const copyX=copyRect.x+copyRect.w/2,copyY=copyRect.y+copyRect.h/2;
 await h.mouseMove(copyX,copyY);
 assert((await h.clickAt(copyX,copyY)).ok);
 await h.waitFor(async()=>await readPasteboardText()===command||null,5000);
 report.checks.push('Hovered copy control beside the scrollbar copies the full pending command');
 await h.scrollAt(r.x+25,r.y+r.h/2,0,-100000);await h.scrollAt(r.x+25,r.y+r.h/2,0,-30);await h.waitFor(async()=>(await visible('ai.interaction.command')).rect.y<before.rect.y-20||null,3000);assert.equal((await visible('ai.interaction.panel')).rect.y,card.rect.y);assert.equal((await visible('ai.interaction.actions')).rect.y,feedback.rect.y);report.checks.push('Pending long command has an idle thumb and contains repeated boundary wheel input inside the bounded composer interaction viewport; actions stay fixed');await cap('02-approval-boundary');await click('ai.interaction.reject');await h.waitFor(async()=>!(await h.query('ai.stop')).some(shown)||null,15000);report.checks.push('Reject remains available and no command is approved');
 mode='recovery';await send('显示长错误详情。');await visible('ai.recovery');await click('ai.recovery.details.toggle');
 // 恢复卡是原生 danger Alert（Kaf7E A9，143c4c7b）：ai.recovery.details 是 Alert 的详情槽，诊断全文在其中的纵向 ScrollArea
 // ai.recovery.details.scroll（src/features/ai/cards/view/ai_recovery_view.zig detailsNode；高度 fit max 120，ai_recovery_styles.zig details；containVertical 留住边界滚轮）。
 const detailsMax=120;
 n=await h.waitFor(async()=>{const d=(await h.query('ai.recovery.details.scroll')).find(shown);return d&&Math.abs(d.rect.h-detailsMax)<.5?d:null},5000);
 // The stable scrollbar gutter inserts a viewport wrapper the size of the
 // ScrollArea. Measure the diagnostic itself, not the first child.
 assert((await visible('ai.recovery.diagnostic')).rect.h>n.rect.h,'Fixture must overflow recovery details');
 const slot=await visible('ai.recovery.details');assert(slot.rect.y<=n.rect.y+.5&&slot.rect.y+slot.rect.h>=n.rect.y+n.rect.h-.5,'scroll viewport lies inside the Alert details slot');
 await h.mouseMove(2,850);await h.sleep(3000);n=await visible('ai.recovery.details.scroll');thumb=vThumb(n);assert(thumb.rect.w>0&&(thumb.opacity??1)>0);report.thumbs.push({kind:'recovery',rect:thumb.rect,opacity:thumb.opacity??1});await cap('03-recovery-idle');
 const recovery=await visible('ai.recovery'),detailBefore=(await visible('ai.recovery.diagnostic')).rect;
 await h.scrollAt(n.rect.x+25,n.rect.y+n.rect.h/2,0,-100000);
 await h.scrollAt(n.rect.x+25,n.rect.y+n.rect.h/2,0,-30);
 const after=await h.waitFor(async()=>{const d=(await h.query('ai.recovery.diagnostic')).find(shown);return d&&d.rect.y<detailBefore.y-20?d.rect:null},3000);
 assert(Math.abs(after.y+after.h-(n.rect.y+n.rect.h))<1,'boundary wheel reaches the diagnostic end');
 assert.equal((await visible('ai.recovery')).rect.y,recovery.rect.y);
 report.checks.push('Expanded long recovery details have an idle thumb and contain repeated boundary input');await cap('04-recovery-boundary');report.status='passed';
}catch(error){report.status='failed';report.error=String(error);process.exitCode=1;await cap('failure').catch(()=>{})}
finally{server.closeAllConnections();await new Promise<void>(done=>server.close(()=>done()));if(app.exitCode===null&&app.signalCode===null){try{await h.request('POST','/quit');await h.waitFor(async()=>app.exitCode!==null||app.signalCode!==null||null,10000)}catch(error){report.shutdown_error=String(error);app.kill('SIGTERM')}}report.shutdown=await ended;await log.close();report.requests=requests;await writeFile(join(out,'report.json'),JSON.stringify(report,null,2))}
console.log(JSON.stringify(report,null,2));
