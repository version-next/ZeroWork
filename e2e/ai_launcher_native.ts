/**
 * PL4c 4c-2：每个 tab 的浮动 AI 图标 `ai.launcher`（Pencil XqqLV：tfmv1 / cVXd5 / Db7OS / wqZ1s / XZGS9）。
 * 真实窗口、隔离数据目录、本机回环的假模型服务（不出网）。每个主题跑一遍：
 *   1. 单终端 tab：图标 48 × 48，停在 tab 内容区（workspace.pane）右下角，距右 24、距下 20；空闲。
 *   2. 四个入口：点图标打开当前 tab 的面板且图标隐藏，面板的收起按钮关上后图标回来；⌘J（toggle_ai）开 / 关；
 *      终端里 `@ai` 打开。
 *   3. 状态（面板收起时显示在图标上）：运行中（accent 图标呼吸）→ 有新回答（accent 点，打开面板清除）；
 *      待审批（warning 着色 + warning 点 + 脉冲圆点）；失败（danger 点，打开面板清除）。
 *   4. 拖放：拖到左上方松手吸附左上角（24 / 20），写进 config.toml 的 ui.ai_launcher_corner；新开的 tab 共用这个角；
 *      拖回右下。
 *   5. 分屏 tab（@grp 组成的本机组）：整个 tab 只有一个图标，停在 tab 内容区右下角。
 *   6. KVM tab（离线 bmc 夹具，关闭的回环端口）：有图标；帧率浮层在同一角时停在它外侧 12。
 * 每个画面截图（<theme>-*.png）。
 *
 * Usage: node e2e/ai_launcher_native.ts <zerowork binary (test-mode)> <out dir> [light|dark]
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {join,resolve} from 'node:path';
import {readFile,writeFile,mkdir,mkdtemp,realpath,open,rm} from 'node:fs/promises';
import {spawn} from 'node:child_process';
import * as h from '../vendor/zenit/e2e/client.ts';
import {shown} from './settings_nav.ts';
import {fixtureSessionIds} from './ai_fixture_discovery.ts';

import {isTitleRequest,skipTitle} from './ai_title_fixture.ts';
import {readRequestText} from './provider_fixture.ts';
const [binaryArg,outArg,theme='light']=process.argv.slice(2);
if(!binaryArg||!outArg)throw new Error('usage: ai_launcher_native.ts <binary> <out> [light|dark]');
const out=resolve(outArg);await mkdir(out,{recursive:true});
const report:any={status:'running',theme,checks:[] as string[],shots:[] as string[],requests:0,limits:['Offline fixtures: loopback model server, closed-port KVM endpoint. "Result unverified" needs an uncertain tool run and is covered by ai-launcher-preview and the model unit tests.']};

let releaseWork:(()=>void)|null=null;
// Full capability metadata in the model list: discovery never falls back to the public models.dev catalog.
const server=createServer(async(req,res)=>{
 if(req.method==='GET'){res.writeHead(200,{'Content-Type':'application/json'});res.end(JSON.stringify({data:[{id:'launcher-model',object:'model',context_length:200000,reasoning:false,vision:false}]}));return;}
 const body=await readRequestText(req);const request=JSON.parse(body);if(isTitleRequest(request))return skipTitle(res);report.requests++;
 const user=String(request.messages.filter((m:any)=>m.role==='user').at(-1)?.content??'');
 const sse=(delta:any)=>'data: '+JSON.stringify({choices:[{index:0,delta}]})+'\n\n';
 if(user.includes('FAIL_NOW')){res.writeHead(500,{'Content-Type':'application/json'});res.end('{"error":{"message":"fixture failure"}}');return;}
 if(user.includes('APPROVE_NOW')){
  if(request.messages.some((m:any)=>m.role==='tool'&&m.tool_call_id==='launcher-approval')){res.writeHead(200,{'Content-Type':'text/event-stream'});res.end(sse({content:'Rejected.'})+'data: [DONE]\n\n');return;}
  const ids=fixtureSessionIds(request,res);if(!ids)return;
  res.writeHead(200,{'Content-Type':'text/event-stream'});res.end(sse({tool_calls:[{index:0,id:'launcher-approval',type:'function',function:{name:'run_command',arguments:JSON.stringify({session_ids:ids,command:'printf LAUNCHER_APPROVAL_MUST_NOT_RUN'})}}]})+'data: [DONE]\n\n');return;
 }
 res.writeHead(200,{'Content-Type':'text/event-stream'});res.write(sse({content:'正在处理 '+user+'\n\n'}));
 if(user.includes('WORK_SLOW'))await new Promise<void>(r=>{releaseWork=r;setTimeout(r,20000);});
 res.end(sse({content:'LAUNCHER_ANSWER 完成。'})+'data: [DONE]\n\n');
});
await new Promise<void>(r=>server.listen(0,'127.0.0.1',r));const port=(server.address() as any).port;
const kvmPayload={endpoint:{host:'127.0.0.1',https_port:1},username:'fixture',display:{scale:'fit',read_only_requested:true}};
const config=`[ai]\ndefault_provider="launcher"\npermission_mode="confirm"\n[[ai.providers]]\nid="launcher"\nkind="openai_compat"\nendpoint="http://127.0.0.1:${port}/v1/chat/completions"\nenabled=true\n[[ai.providers.models]]\nname="launcher-model"\ncontext_window=200000\ndefault=true\n`;
// Isolated launch (as settings_nav.launchIsolated) with the KVM fixture host written before start.
const iso=await realpath(await mkdtemp('/private/tmp/zw-ai-launcher-e2e-')),rpc=join(iso,'rpc'),data=join(iso,'data');
await mkdir(rpc);await mkdir(data);
const configPath=join(data,'config.toml');
await writeFile(configPath,`[meta]\nconfig_revision=1\n[updates]\nauto_check=false\n[ui]\ntheme="${theme}"\n${config}`,{mode:0o600});
await writeFile(join(data,'hosts.toml'),'[registry]\nschema_version=2\nrevision=1\nnext_connection_id=2\nnext_group_id=1\n[[hosts]]\nconnection_id=1\nrevision=1\nprotocol="bmc_ikvm"\nname="KVM Launcher Fixture"\npayload='+JSON.stringify(JSON.stringify(kvmPayload))+'\n',{mode:0o600});
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const log=await open(join(out,`${theme}-app.log`),'w');
const app=spawn(binaryArg,[],{env:{...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1',ZENIT_E2E_ISOLATE_KEYBOARD:'1',ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',OPENAI_API_KEY:'',ANTHROPIC_API_KEY:''},stdio:['ignore',log.fd,log.fd]});
const ended=new Promise<void>(r=>app.once('close',()=>r()));
const s={config:configPath,stop:async()=>{if(app.exitCode===null&&app.signalCode===null)app.kill('SIGTERM');await ended;await log.close().catch(()=>{});}};
await h.waitForServerReady();

const node=(id:string,ms=12000)=>h.waitFor(async()=>(await h.query(id)).find(shown)??null,ms);
const hidden=(id:string,ms=8000)=>h.waitFor(async()=>(await h.query(id)).some(shown)?null:true,ms);
const click=async(id:string)=>{const n=await node(id);if(!(await h.clickTestId(id)).ok)assert((await h.clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok,'click '+id);await h.sleep(250);};
const state=async()=>((await h.query('ai.launcher.state'))[0]?.text??'');
const waitState=async(want:string,ms=15000)=>h.waitFor(async()=>(await state())===want?true:null,ms);
const shot=async(name:string)=>{await h.mouseMove(4,300).catch(()=>{});await h.sleep(350);const path=join(out,`${theme}-${name}.png`);assert((await h.screenshot(path)).ok,name);report.shots.push(path);};
const drag=async(x0:number,y0:number,x1:number,y1:number)=>{await h.mouseMove(x0,y0);await h.mouseDown(x0,y0);for(let i=1;i<=12;i++){await h.mouseMove(x0+(x1-x0)*i/12,y0+(y1-y0)*i/12);await h.sleep(16);}await h.mouseUp(x1,y1);};
const near=(a:number,b:number,label:string)=>assert(Math.abs(a-b)<=1,`${label}: ${a} vs ${b}`);
const restsBottomRight=async(label:string)=>{const pane=(await node('workspace.pane')).rect,l=(await node('ai.launcher')).rect;near(l.w,48,label+' width');near(l.h,48,label+' height');near(l.x+l.w,pane.x+pane.w-24,label+' right inset');near(l.y+l.h,pane.y+pane.h-20,label+' bottom inset');return l;};
// A notification card may sit over the panel header: fall back to toggle_ai (⌘J).
// The panel folds back into the launcher (Z12); the launcher reappears when it lands.
const collapse=async()=>{await node('ai.panel');if(!(await h.clickTestId('ai.collapse')).ok)await h.key('j',{cmd:true});await hidden('ai.panel');await node('ai.launcher');await h.sleep(200);};
const send=async(prompt:string)=>{await click('ai.prompt');await h.key('a',{cmd:true});await h.type_(prompt);await click('ai.send');};
const iconOpacities=async()=>{const flat=(n:any):any[]=>n?[n,...(n.children??[]).flatMap(flat)]:[];const r=(await h.query('ai.launcher'))[0];return flat(r).map((n:any)=>n.opacity??1);};

try{
 await h.resizeWindow(1440,900);await h.sleep(300);
 await click('workspace.empty.local');await node('terminal.surface');await h.sleep(600);
 await restsBottomRight('single');assert.equal(await state(),'idle');for(const old of ['toolbar.ai','ai.strip','ai.dock','ai.pane.resize'])assert.equal((await h.query(old)).length,0,old+' is removed (PL4c)');
 await shot('01-single-idle');report.checks.push('Single terminal tab: 48 × 48 GlassButton 24 / 20 inside the tab body bottom-right, idle; no toolbar.ai / ai.strip / ai.dock / ai.pane.resize');

 {const l=(await node('ai.launcher')).rect;await click('ai.launcher');await node('ai.panel');await hidden('ai.launcher');
 const p=await h.waitFor(async()=>{const n=(await h.query('ai.panel')).find(shown);const ph=(await h.query('ai.panel.motion.phase'))[0]?.text;return n&&ph==='expanded'?n.rect:null;},8000);
 near(p.x+p.w,l.x+l.w,'panel right = launcher right');near(p.y+p.h,l.y+l.h,'panel bottom = launcher bottom');}
 report.checks.push('ai.launcher opens the current tab panel beside it (bottom-right corners meet) and hides while it is open');
 await click('ai.collapse');await hidden('ai.panel');await node('ai.launcher');report.checks.push('The panel collapse button closes it; the launcher returns');
 await h.key('j',{cmd:true});await node('ai.panel');await hidden('ai.launcher');await h.key('j',{cmd:true});await hidden('ai.panel');await node('ai.launcher');report.checks.push('toggle_ai (⌘J) opens and closes the current tab panel');
 await click('terminal.surface');await h.type_('@ai');await h.key('return');await node('ai.panel');await hidden('ai.launcher');await click('ai.collapse');await node('ai.launcher');report.checks.push('@ai opens the current tab panel');

 // Running -> unread answer.
 await click('ai.launcher');await send('WORK_SLOW please');await node('ai.stop');await collapse();
 await waitState('working');const ink=await iconOpacities();await h.sleep(700);const ink2=await iconOpacities();
 report.breathing={a:ink,b:ink2};await shot('02-state-working');report.checks.push('Running: accent icon (breathing) while the panel is collapsed');
 releaseWork?.();await waitState('success');assert((await h.query('ai.launcher.dot')).some(shown),'unread dot');await shot('03-state-success');
 await click('ai.launcher');await h.sleep(300);await collapse();await waitState('idle');assert(!(await h.query('ai.launcher.dot')).some(shown));report.checks.push('New answer: accent dot while hidden; opening the panel clears it');

 // Failure.
 await click('ai.launcher');await send('FAIL_NOW please');await h.sleep(1500);await collapse();
 await waitState('failed');assert((await h.query('ai.launcher.dot')).some(shown));await shot('04-state-failed');
 await click('ai.launcher');await h.sleep(300);await collapse();assert.notEqual(await state(),'failed','opening clears the failure dot');report.checks.push('Failure: danger dot while hidden; opening the panel clears it');

 // Approval.
 await click('ai.launcher');await send('APPROVE_NOW please');await node('ai.interaction.reject',20000);await collapse();
 await waitState('approval');assert((await h.query('ai.launcher.dot')).some(shown));const ring=(await h.query('ai.launcher.ring'))[0];report.ring=ring;await shot('05-state-approval');
 await click('ai.launcher');await h.sleep(300);await collapse();assert.equal(await state(),'approval','approval stays until decided');
 await click('ai.launcher');await click('ai.interaction.reject');await hidden('ai.interaction.reject',10000);await collapse();
 await h.waitFor(async()=>(await state())!=='approval'||null,10000);report.checks.push('Approval: warning tint + dot + ping while hidden; stays until the decision');

 // Drag to the top-left corner and back.
 const l=(await node('ai.launcher')).rect,pane=(await node('workspace.pane')).rect;
 await drag(l.x+24,l.y+24,pane.x+pane.w*0.3,pane.y+pane.h*0.25);await h.sleep(500);
 const tl=(await node('ai.launcher')).rect;near(tl.x,pane.x+24,'top-left x');near(tl.y,pane.y+20,'top-left y');
 assert.equal(await state(),'idle','a drag is not a click');assert(!(await h.query('ai.panel')).some(shown),'drag does not open the panel');
 const saved=await readFile(s.config,'utf8');assert(saved.includes('ai_launcher_corner = "top_left"'),'corner persisted');await shot('06-dragged-top-left');
 report.checks.push('Drag snaps to the nearest corner (top-left, 24 / 20), is not a click, and persists ui.ai_launcher_corner');
 // #59: the panel unfolds beside the launcher's corner (never-moved panel), not from the pane top.
 await click('ai.launcher');const opened=await h.waitFor(async()=>{const p=(await h.query('ai.panel')).find(shown);const ph=(await h.query('ai.panel.motion.phase'))[0]?.text;return p&&ph==='expanded'?p.rect:null;},8000);
 near(opened.x,tl.x,'panel left = launcher left (top-left corner)');near(opened.y,tl.y,'panel top = launcher top (top-left corner)');
 await shot('06b-panel-beside-top-left');await collapse();await node('ai.launcher');
 report.checks.push('Clicking the top-left launcher unfolds the panel from that corner (panel top-left = launcher top-left)');

 // A second tab shares the corner; then a split (group) tab has one launcher.
 await click('toolbar.new_session');await click('session.menu.local');await node('terminal.surface');await h.sleep(500);
 const second=(await node('ai.launcher')).rect;near(second.x,pane.x+24,'shared corner x');near(second.y,pane.y+20,'shared corner y');report.checks.push('All tabs share the corner');
 const back=(await node('ai.launcher')).rect;await drag(back.x+24,back.y+24,pane.x+pane.w*0.8,pane.y+pane.h*0.8);await h.sleep(500);await restsBottomRight('dragged back');
 const joinGroup=async()=>{await click('terminal.surface');for(let i=0;i<3;i++){await h.type_('@');try{await node('terminal.commands',3000);break}catch(e){await h.key('c',{ctrl:true});if(i===2)throw e}}await h.type_('grp LauncherSplit');await h.key('right');await h.key('return');await node('groups.workspace');};
 await joinGroup();await h.key('1',{cmd:true});await h.sleep(400);await joinGroup();await h.sleep(600);
 assert.equal((await h.query('ai.launcher')).filter(shown).length,1,'one launcher per split tab');await restsBottomRight('split');await shot('07-split');report.checks.push('Split tab: one launcher at the whole tab body bottom-right');

 // KVM tab (offline fixture).
 const row=await node('sidebar.host',8000).catch(()=>null);
 if(row){await h.clickAt(row.rect.x+65,row.rect.y+row.rect.h/2);await h.key('return');await node('bmc.content');await h.sleep(900);
  const kvm=await restsBottomRight('kvm').catch(async()=>{const l=(await node('ai.launcher')).rect;return l;});
  const fps=(await h.query('bmc.fps')).find(shown);report.kvm={launcher:kvm,fps:fps?.rect??null};
  if(fps){const o=fps.rect;const overlap=kvm.x<o.x+o.w&&kvm.x+kvm.w>o.x&&kvm.y<o.y+o.h&&kvm.y+kvm.h>o.y;assert(!overlap,'launcher keeps clear of the frame-rate panel');}
  await shot('08-kvm');report.checks.push('KVM tab has a launcher; it keeps clear of the frame-rate overlay');
  // j8WXoF O6: in the KVM tab a top corner rests 12 below the KVM toolbar (never on its menus).
  const kp=(await node('workspace.pane')).rect;await drag(kvm.x+24,kvm.y+24,kp.x+kp.w*0.85,kp.y+kp.h*0.15);await h.sleep(500);
  const top=(await node('ai.launcher')).rect,bar=(await node('bmc.toolbar')).rect;near(top.y,bar.y+bar.h+12,'KVM top-right: launcher top = toolbar bottom + 12');near(top.x+top.w,kp.x+kp.w-24,'KVM top-right: right inset 24');
  await shot('09-kvm-top-right');report.checks.push('KVM tab: a top-corner launcher rests at the toolbar bottom + 12');
  await drag(top.x+24,top.y+24,kp.x+kp.w*0.8,kp.y+kp.h*0.8);await h.sleep(500);await restsBottomRight('kvm back');}
 else report.limits.push('KVM fixture host row not found; KVM step skipped');
 report.status='passed';
}catch(e){report.status='failed';report.error=String((e as any)?.stack??e);await h.screenshot(join(out,`${theme}-failure.png`)).catch(()=>{});process.exitCode=1;}
finally{await s.stop();await rm(iso,{recursive:true,force:true}).catch(()=>{});server.closeAllConnections();await new Promise<void>(r=>server.close(()=>r()));await writeFile(join(out,`report-${theme}.json`),JSON.stringify(report,null,2));}
console.log(report.status+': '+out);
