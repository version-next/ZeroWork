/** AI 重设计 P6 / P7（ai-redesign-c）在真实原生窗口里的验收：
 *  - 未配置模型：空对话只在空状态里引导（W.Empty + 配置 AI 服务），输入区上方的 Alert 不出现（即使在输入）；
 *    已有对话历史时输入区上方出现原生 Alert（ai.unconfigured），空状态不出现；两者从不同时出现（主会话判定）。
 *  - 会话列表 / 子智能体弹层（O7 / O8）宽 min(360, 面板宽 − 16)，不超出面板左右缘。
 *  - “新消息”提示（用户拍板新增）：上翻后来了新回复 → 视口底部居中、离下缘 8 显示；点它平滑回到底部并消失、恢复
 *    跟随；读者自己滚回底部时提示消失。
 *  - 宽度规则：停靠宽 ≥ 760 时对话视口与输入区共用 720 宽的居中列；浮动 320 / 420 宽时标题“AI 助手”不被截断。
 *  - 停靠时 launcher 不压在 AI 窗格上（让位到窗格之外）。
 *  另外截下 A1 / A2 / O5 / O7 / O8 / O11 / W560 / W800 的界面供 design_diff。
 *  Usage: node e2e/ai_redesign_c_native.ts <out> <light|dark>
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {spawn,type ChildProcess} from 'node:child_process';
import {mkdir,mkdtemp,writeFile,copyFile,open,readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {waitForServerReady,waitFor,query,clickTestId,key,type_,resizeWindow,screenshot,sleep,mouseMove,scrollAt,clickAt,focused} from '../zig-out/share/zenit/harness/client.ts';
import {aiToggleId} from './ai_entry.ts';
import {isTitleRequest,skipTitle} from './ai_title_fixture.ts';
import {readRequestJson} from './provider_fixture.ts';

const out=resolve(process.argv[2]??'/tmp/zw-ai-redesign-c');const theme=process.argv[3]??'light';
const dir=join(out,theme);await mkdir(dir,{recursive:true});
type R={x:number;y:number;w:number;h:number};
const shown=(n:any)=>n&&n.hidden!==true&&n.visible!==false&&(n.effective_opacity??1)>0&&n.rect?.w>0&&n.rect?.h>0;
const flat=(n:any):any[]=>n?[n,...(n.children??[]).flatMap(flat)]:[];
const text=(n:any)=>flat(n).map(x=>x.text??'').join('');
const visible=async(id:string,ms=15000)=>waitFor(async()=>(await query(id)).find(shown)??null,ms);
const hidden=async(id:string,ms=10000)=>waitFor(async()=>!(await query(id)).some(shown)||null,ms);
const isShown=async(id:string)=>(await query(id)).some(shown);
const report:any={status:'running',theme,checks:[],captures:{},samples:{}};
let lastAction='';
const click=async(id:string)=>{lastAction=id;await visible(id);assert((await clickTestId(id)).ok,id);};
const capture=async(name:string,ids:string[]=['ai.panel']):Promise<void>=>{
 await mouseMove(1,1);await sleep(260);const path=join(dir,name+'.png');assert((await screenshot(path)).ok);
 const rects:any={};for(const id of ids)rects[id]=(await query(id)).filter(shown).map((n:any)=>n.rect);
 report.captures[name]={path,rects};await writeFile(join(dir,name+'.json'),JSON.stringify(rects,null,1));
};
const inside=(inner:R,outer:R,label:string)=>{assert(inner.x>=outer.x-0.5&&inner.x+inner.w<=outer.x+outer.w+0.5,`${label}: ${JSON.stringify(inner)} inside ${JSON.stringify(outer)}`);};

const iso=await mkdtemp(join(tmpdir(),'zw-ai-redesign-c-')),data=join(iso,'data'),rpc=join(iso,'rpc');await mkdir(data);await mkdir(rpc);
let slow:{res:any}|null=null;
// Wheel deltas in the harness: positive dy scrolls the content up (toward older messages).
const UP=1200,DOWN=-1200;const requests:any[]=[];
const server=createServer(async(req,res)=>{
 if(req.method!=='POST'){res.writeHead(200,{'Content-Type':'application/json'});res.end(JSON.stringify({data:[{id:'c-model'}]}));return;}
 const request=await readRequestJson(req);if(isTitleRequest(request))return skipTitle(res);requests.push(request);
 const prompt=[...request.messages].reverse().find((x:any)=>x.role==='user')?.content??'';
 res.writeHead(200,{'Content-Type':'text/event-stream'});
 const say=(s:string)=>res.write('data: '+JSON.stringify({choices:[{index:0,delta:{content:s}}]})+'\n\n');
 if(String(prompt).includes('SLOW_REPLY')){say('慢速回复开始。\n\n');slow={res};return;}
 say('ANSWER_'+String(prompt).split('\n')[0]+'\n\n'+Array.from({length:18},(_,i)=>`第 ${i+1} 行：用于制造足够长的对话历史，让视口可以上翻。`).join('\n\n'));res.end('data: [DONE]\n\n');
});
await new Promise<void>(r=>server.listen(0,'127.0.0.1',r));const port=(server.address() as any).port;
const baseConfig=`[meta]\nconfig_revision=1\n[ui]\ntheme="${theme}"\nfont_family="Menlo"\nfont_size=14\n`;
const aiConfig=`[ai]\ndefault_provider="c"\npermission_mode="confirm"\n[[ai.providers]]\nid="c"\nkind="openai_compat"\nendpoint="http://127.0.0.1:${port}/v1/chat/completions"\napi_key="local-only"\nenabled=true\n[[ai.providers.models]]\nname="c-model"\ncontext_window=200000\ndefault=true\n`;
await copyFile('zig-out/bin/zerowork',join(iso,'zerowork'));await copyFile('zig-out/bin/zw_ipc.so',join(iso,'zw_ipc.so'));
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const env:any={...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1',ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',OPENAI_API_KEY:'',ANTHROPIC_API_KEY:''};
for(const k of ['ZEROWORK_AI_MOCK','ZEROWORK_AI_ENDPOINT','ZEROWORK_AI_MODEL','ZEROWORK_AI_PROVIDER'])delete env[k];
let app:ChildProcess|null=null;let launches=0;const logs:any[]=[];
async function launch(configured:boolean){
 await writeFile(join(data,'config.toml'),baseConfig+(configured?aiConfig:''));
 const log=await open(join(dir,`app-${++launches}.log`),'w');logs.push(log);
 app=spawn(join(iso,'zerowork'),[],{env,stdio:['ignore',log.fd,log.fd]});
 await waitForServerReady(60000);
 const owner=JSON.parse(await readFile(join(rpc,'owner.json'),'utf8'));assert.equal(Number(owner.pid),app.pid,'address only this isolated process');
}
async function quit(){if(!app)return;const p=app;app=null;const ended=new Promise<void>(r=>p.once('close',()=>r()));p.kill('SIGTERM');await Promise.race([ended,sleep(4000)]);if(p.exitCode===null&&p.signalCode===null){p.kill('SIGKILL');await ended;}}
async function openAi(){await click('workspace.empty.local');await visible('terminal.surface');await click(await aiToggleId());await visible('ai.prompt');}
async function send(prompt:string){await click('ai.prompt');await key('a',{cmd:true});await type_(prompt);await click('ai.send');}
async function idle(){await waitFor(async()=>!(await query('ai.stop')).some(shown)||null,20000);}
async function viewportState(){const v=(await query('ai.conversation.viewport')).find(shown);const content=v.children?.find((c:any)=>c.rect)?.rect;return {v:v.rect as R,content:content as R};}
try{
 // ── 1. 未配置，空对话：只有空状态引导 ──────────────────────────────────────────────
 await launch(false);await resizeWindow(1440,900);await openAi();
 await visible('ai.empty.unconfigured');assert(text(await visible('ai.empty.title')).includes('配置模型'));await visible('ai.empty.settings');
 assert(!(await isShown('ai.unconfigured')),'empty conversation: no Alert above the composer');
 await click('ai.prompt');await type_('typing without a model');await sleep(400);
 assert(!(await isShown('ai.unconfigured')),'typing in an empty conversation without a model: still only the empty state');
 assert(await isShown('ai.empty.unconfigured'));
 await key('a',{cmd:true});await key('backspace');
 await capture('a1-unconfigured',['ai.panel','ai.empty.unconfigured']);
 report.checks.push('Unconfigured + empty conversation: the empty state (W.Empty · 配置 AI 服务) is the only guide; no Alert, even while typing');
 await quit();

 // ── 2. 已配置：欢迎页、对话、弹层、新消息提示 ─────────────────────────────────────
 await launch(true);await resizeWindow(1440,900);await openAi();
 await visible('ai.empty.configured');await capture('a2-welcome',['ai.panel','ai.empty.configured']);
 for(const round of [1,2]){await send(`ROUND_${round}`);await waitFor(async()=>text(await visible('ai.panel')).includes(`ANSWER_ROUND_${round}`)||null,15000);await idle();}
 const panel=(await visible('ai.panel')).rect as R;report.samples.panel=panel;
 // O7 / O8: inside the panel.
 await click('ai.sessions');const sessions=(await visible('ai.sessions.menu')).rect as R;report.samples.sessions=sessions;
 assert.equal(Math.round(sessions.w),Math.round(Math.min(360,panel.w-16)),'O7 width = min(360, panel − 16)');inside(sessions,panel,'O7 sessions popover');
 assert(text(await visible('ai.sessions.heading')).includes('AI 会话'));await visible('ai.sessions.total');
 await capture('o7-sessions',['ai.panel','ai.sessions.menu']);await key('escape');await hidden('ai.sessions.menu');
 await click('ai.children');const children=(await visible('ai.children.list')).rect as R;
 const childPanel=(await query('ai.children.heading')).find(shown).rect as R;report.samples.children={list:children,heading:childPanel};
 inside(children,panel,'O8 children list');inside(childPanel,panel,'O8 heading');await visible('ai.children.close');
 await capture('o8-children',['ai.panel','ai.children.heading','ai.children.list']);await click('ai.children.close');await hidden('ai.children.list');
 report.checks.push('O7 / O8 popovers are min(360, panel − 16) wide and stay inside the floating panel');
 // 新消息：上翻后来了新回复。
 await send('SLOW_REPLY');await waitFor(()=>slow||null,10000);await visible('ai.stop');
 let vs=await viewportState();
 await scrollAt(vs.v.x+vs.v.w/2,vs.v.y+vs.v.h/2,0,UP);await sleep(300);await scrollAt(vs.v.x+vs.v.w/2,vs.v.y+vs.v.h/2,0,UP);await sleep(300);
 assert(!(await isShown('ai.new_messages')),'no hint before a new reply');
 const say=(s:string)=>slow!.res.write('data: '+JSON.stringify({choices:[{index:0,delta:{content:s}}]})+'\n\n');
 for(let i=0;i<6;i++){say(`新的回复段落 ${i+1}：`+'内容'.repeat(30)+'\n\n');await sleep(120);}
 const hint=(await visible('ai.new_messages.jump')).rect as R;vs=await viewportState();report.samples.hint={hint,viewport:vs.v};
 assert(Math.abs((hint.x+hint.w/2)-(vs.v.x+vs.v.w/2))<=1.5,'hint centered in the transcript viewport');
 assert(Math.abs((vs.v.y+vs.v.h)-(hint.y+hint.h)-8)<=1.5,'hint 8 above the viewport bottom (the composer)');
 assert(text(await visible('ai.new_messages')).includes('新消息'));
 await capture('p7-new-messages',['ai.panel','ai.new_messages','ai.conversation.viewport']);
 await click('ai.new_messages.jump');await hidden('ai.new_messages');
 await waitFor(async()=>{const s=await viewportState();return Math.abs((s.content.y+s.content.h)-(s.v.y+s.v.h))<=2||null;},5000);
 say('跟随中的追加内容。\n\n');await sleep(400);
 vs=await viewportState();assert(Math.abs((vs.content.y+vs.content.h)-(vs.v.y+vs.v.h))<=2,'after the jump the transcript follows new output again');
 assert(!(await isShown('ai.new_messages')),'following: no hint');
 // 读者自己滚回底部：提示消失。
 await scrollAt(vs.v.x+vs.v.w/2,vs.v.y+vs.v.h/2,0,UP);await sleep(300);say('再来一段新回复。\n\n');await visible('ai.new_messages');
 for(let i=0;i<8&&(await isShown('ai.new_messages'));i++){await scrollAt(vs.v.x+vs.v.w/2,vs.v.y+vs.v.h/2,0,DOWN);await sleep(250);}
 await hidden('ai.new_messages',5000);
 slow!.res.end('data: [DONE]\n\n');slow=null;await idle();
 report.checks.push('新消息: shown centered 8 above the composer when a reply arrives while scrolled up; click glides to the end and follows again; scrolling back down hides it');
 // O11 关闭确认（不结束）。
 await click('ai.close');await visible('ai.close.confirmation');await capture('o11-close',['ai.close.confirmation']);await click('ai.close.confirmation.cancel');await hidden('ai.close.confirmation');
 // 浮动 320 / 420：标题完整。
 const titleWidth=async()=>{const header=(await visible('ai.header'));const t=flat(header).find((n:any)=>n.text==='AI 助手'&&shown(n));assert(t,'title node');return t.rect.w as number;};
 const wide=await titleWidth();
 for(const w of [860,1000]){await resizeWindow(w,700);await sleep(500);const p=(await visible('ai.panel')).rect;const tw=await titleWidth();report.samples['title_'+Math.round(p.w)]={panel:p,title:tw,wide};
  assert(Math.abs(tw-wide)<=0.5,`panel ${p.w}: the title 'AI 助手' keeps its full width (${tw} vs ${wide})`);}
 report.checks.push('Floating 320 / 420: the title keeps its full width (the subtitle gives way first)');
 await capture('w320-float',['ai.panel']);
 // ── 3. 停靠：标题、launcher 让位、720 列 ─────────────────────────────────────────
 await resizeWindow(1440,900);await sleep(400);await click('ai.dock_to_split');const pane=(await visible('ai.pane')).rect as R;await hidden('ai.panel');
 const launcher=(await query('ai.launcher')).find(shown);if(launcher){const l=launcher.rect as R;report.samples.launcher={launcher:l,pane};
  assert(l.x+l.w<=pane.x+0.5||l.x>=pane.x+pane.w-0.5||l.y+l.h<=pane.y+0.5||l.y>=pane.y+pane.h-0.5,'docked: the launcher does not sit on the AI pane');}
 report.checks.push('Docked in the split: the launcher rests outside the AI pane (it no longer covers the composer)');
 await click('ai.pane.more');await visible('ai.pane.menu');await capture('o5-more',['ai.pane.menu','ai.pane.more']);await key('escape');await hidden('ai.pane.menu');
 for(const [label,id] of [['AI 会话列表','ai.sessions.menu'],['子智能体','ai.children.list']] as const){
  await click('ai.pane.more');const menu=await visible('ai.pane.menu');const item=flat(menu).find((n:any)=>n.text===label&&shown(n));assert(item,label);
  await clickAt(item.rect.x+item.rect.w/2,item.rect.y+item.rect.h/2);
  const pop=await waitFor(async()=>{const all=await query(id);report.samples['docked_query_'+id]=all.map((n:any)=>({rect:n.rect,hidden:n.hidden,visible:n.visible,op:n.effective_opacity}));return all.find(shown)?.rect??null;},8000).catch(()=>null);
  assert(pop,`docked: ${label} popover shows (${JSON.stringify(report.samples['docked_query_'+id])})`);inside(pop,(await visible('ai.pane')).rect,`docked ${label} popover`);
  await mouseMove(200,500);await sleep(150);await mouseMove(180,520);await sleep(600);report.samples['focus_'+id]=(await focused())?.test_id??null;await key('escape');await hidden(id);}
 report.checks.push('Docked: 子智能体 / AI 会话列表 open from 更多 inside the AI pane');
 await capture('w-docked-'+Math.round(pane.w),['ai.pane','ai.conversation.viewport']);
 const columnCheck=async(label:string)=>{
  const p=(await visible('ai.pane')).rect as R;const v=(await visible('ai.conversation.viewport')).rect as R;const prompt=(await visible('ai.prompt')).rect as R;const controls=(await visible('ai.composer.controls')).rect as R;
  report.samples['column_'+label]={pane:p,viewport:v,prompt,controls};
  if(p.w>=760){
   assert(Math.abs(v.w-720)<=1,`${label}: transcript column 720 (${v.w})`);
   assert(Math.abs((v.x+v.w/2)-(p.x+p.w/2))<=1.5,`${label}: column centered in the pane`);
   inside(prompt,v,`${label}: composer in the same column`);inside(controls,v,`${label}: composer controls in the column`);
  }else assert(v.w>=p.w-2,`${label}: below 760 the transcript spans the pane (${v.w} / ${p.w})`);
  return p.w;};
 const w1=await columnCheck('1440');
 await resizeWindow(2200,1000);await sleep(600);const w2=await columnCheck('2200');
 assert(w2>=760,`a 2200 wide window docks the AI ≥ 760 wide (${w2})`);await capture('w-docked-'+Math.round(w2),['ai.pane','ai.conversation.viewport','ai.composer.controls']);
 report.checks.push(`Docked ≥ 760 (${Math.round(w2)}): transcript and composer share one centered 720 column; ${Math.round(w1)}: full width`);
  await quit();

 // ── 4. 未配置，已有对话历史：输入区上方 Alert，空状态不出现 ────────────────────────
 await launch(false);await resizeWindow(1440,900);await openAi();await visible('ai.empty.unconfigured');
 await click('ai.sessions');await visible('ai.sessions.menu');
 const row=await waitFor(async()=>{const rows=flat((await query('ai.sessions.menu')).find(shown)).filter((n:any)=>/^ai\.session\.row\.\d+$/.test(n.test_id??'')&&text(n).includes('ROUND_1'));const r=rows[0];return r?flat(r).find((n:any)=>/^ai\.session\.restore\.\d+$/.test(n.test_id??'')&&shown(n))??null:null;},10000);
 report.samples.restore=row.test_id;
 await clickAt(row.rect.x+row.rect.w/2,row.rect.y+row.rect.h/2);await waitFor(async()=>text(await visible('ai.panel')).includes('ANSWER_ROUND_1')||null,15000);
 await visible('ai.unconfigured');assert(!(await isShown('ai.empty.unconfigured')),'history: no empty-state guide');await visible('ai.unconfigured.configure');
 await capture('p7-unconfigured-history',['ai.panel','ai.unconfigured']);
 await click('ai.session.new');if(await waitFor(async()=>(await isShown('ai.session.close.confirmation'))||null,1500).catch(()=>null))await click('ai.session.close.accept');
 await visible('ai.empty.unconfigured');await hidden('ai.unconfigured');
 report.checks.push('Unconfigured + history: the native Alert above the composer; a new (empty) conversation switches back to the empty-state guide; never both');
 report.status='passed';
}catch(error){
 report.status='failed';report.error=String(error);report.lastAction=lastAction;
 try{await screenshot(join(dir,'failure.png'));report.debug={hint:await query('ai.new_messages'),jump:await query('ai.new_messages.jump'),viewport:(await query('ai.conversation.viewport')).map((n:any)=>({rect:n.rect,content:n.children?.map((c:any)=>({id:c.test_id,rect:c.rect,hidden:c.hidden}))}))};}catch{}
}finally{
 await quit();for(const l of logs)await l.close().catch(()=>{});report.requests=requests.length;await writeFile(join(dir,'report.json'),JSON.stringify(report,null,2));
 server.closeAllConnections();server.close();
}
console.log(report.status+': '+join(dir,'report.json'));
if(report.status!=='passed'){console.error(report.error);process.exit(1);}
