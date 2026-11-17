/** KVM card overlays (Pencil j8WXoF「ZW · KVM 卡片浮层 2026-11-13」, requests #58) on the real renderer.
 * node e2e/kvm_overlays_native.ts /absolute/bmc-kvm-preview /tmp/evidence [dark,light]
 * Local typed services only (synthetic frames, input counter, synthetic AI activity and power phase);
 * the AI launcher is the real ai_launcher view placed with the real launcher model.
 * Checks: O1 single highest-priority status (power > AI operating > captured > AI observing) and the
 * takeover button reaching the typed AI stop; O2 HUD right-top 12 from the picture, one line, compact
 * < 640 / hidden < 480, fades 150 ms after the pointer enters, returns after 600 ms, hidden while
 * captured / waiting; O3 hint keeps 84 per side and fades after 3 s; O4 waiting-for-picture alert
 * (power running, no signal) with the old picture kept; O5 AI frame in the 8 pt black edge; O6 launcher
 * top corners at toolbar + 12, the four-corner avoidance table, capture yield (opacity 0, pass-through).
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdir, mkdtemp, open, writeFile, rm} from 'node:fs/promises';
import {join, resolve} from 'node:path';
import * as h from '../vendor/zenit/e2e/client.ts';

const binary=resolve(process.argv[2]), out=resolve(process.argv[3]);
const themes=(process.argv[4]??'dark,light').split(',');
await mkdir(out,{recursive:true});
const report:any={status:'running',binary,checks:[] as string[],shots:[] as string[],limits:['Isolated preview: synthetic frames / AI activity / power phase; split states are emulated by narrowing the KVM content slot (the full app has no offline streaming KVM).']};
const shown=(n:any)=>n?.rect?.w>0&&n.rect.h>0&&n.hidden!==true&&n.visible!==false&&(n.effective_opacity??1)>.02;
const near=(a:number,b:number,label:string,eps=1.01)=>assert(Math.abs(a-b)<=eps,`${label}: ${a} vs ${b}`);
const node=async(id:string,ms=8000)=>h.waitFor(async()=>(await h.query(id)).find(shown)??null,ms);
const gone=async(id:string,ms=8000)=>h.waitFor(async()=>(await h.query(id)).some(shown)?null:true,ms);
const opacityOf=async(id:string)=>((await h.query(id))[0]?.effective_opacity??1);
async function post(path:string,body:any){const r=await h.request('POST',path,body);assert(!r.error,`${path}: ${JSON.stringify(r)}`);return r;}
async function stats(){const r=await h.request('GET','/app/bmc-fixture/overlay-stats');assert(!r.error,JSON.stringify(r));return r;}
async function state(name:string){await post('/app/bmc-fixture/state',{state:name});await h.sleep(200);}
async function corner(c:string|null){await post('/app/bmc-fixture/launcher',{corner:c});await h.sleep(250);}
async function ai(a:string){await post('/app/bmc-fixture/ai',{activity:a});await h.sleep(250);}
async function width(w:number|null){if(w===null)return;await post('/app/bmc-fixture/content-width',{width:w});await h.sleep(300);}
let theme='dark';
async function shot(name:string){await h.sleep(250);const p=join(out,`${name}-${theme}.png`);assert((await h.screenshot(p)).ok);report.shots.push(p);}
async function tag(){const t=(await h.query('bmc.status.tag'))[0];return shown(t)?(t.text??(t.children??[]).map((c:any)=>c.text).join('')):'';}
async function textOf(id:string){const flat=(n:any):string[]=>n?[n.text??'',...(n.children??[]).flatMap(flat)]:[];return flat((await h.query(id))[0]).join('');}

async function startPower(){
  await state('management');
  const overflow=!(await h.query('bmc.power')).some(shown);
  if(overflow){await h.clickTestId('bmc.more');await h.sleep(300);await h.clickTestId('bmc.more.power');}else await h.clickTestId('bmc.power');
  await h.sleep(400);await h.clickTestId('bmc.power.action.trigger');await h.sleep(300);await h.clickTestId('bmc.power.option.restart');await h.sleep(300);
  await h.clickTestId('bmc.power.execute');await h.sleep(400);await h.clickTestId('bmc.power.close').catch(()=>null);await h.sleep(300);
}
async function runTheme(name:string,W:number,H:number){
  theme=name;
  const base=await mkdtemp('/private/tmp/zw-kvm-overlays-e2e-'),rpc=join(base,'rpc');await mkdir(rpc);
  process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
  const log=await open(join(out,`app-${name}-${W}.log`),'w');
  const app=spawn(binary,[`--theme=${name}`,'--state=controlled',`--size=${W}x${H}`],{env:{...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1',ZENIT_E2E_ISOLATE_KEYBOARD:'1'},stdio:['ignore',log.fd,log.fd]});
  const ended=new Promise<void>(done=>app.once('close',()=>done()));
  try{
    await h.waitForServerReady();
    {
      const tagSize=W===1440?'':'-min';
      await h.sleep(400);await state('controlled');await ai('none');await corner('bottom_right');await h.mouseMove(4,4);
      const vp=(await node('bmc.viewport')).rect,card=(await node('bmc.video_card')).rect,bar=(await node('bmc.toolbar')).rect;
      // B1 / F1: HUD right-top 12 from the picture (20 from the card), launcher bottom-right 24 / 20, no status.
      const hud=await h.waitFor(async()=>(await h.query('bmc.fps.display')).find(shown)??null,8000);
      if(vp.w>=480){near(hud.rect.x+hud.rect.w,vp.x+vp.w-12,'HUD right = picture right - 12');near(hud.rect.y,vp.y+12,'HUD top = picture top + 12');}
      const hudText=await textOf('bmc.fps.display');assert(vp.w<640?/^\S+ FPS$/.test(hudText):/^\d+ × \d+ · 显示 .* · 解码 .* FPS$/.test(hudText),`HUD text ${hudText}`);
      const l=(await node('ai.launcher')).rect,slot=(await node('fixture.content_slot')).rect;
      near(l.x+l.w,slot.x+slot.w-24,'launcher right 24');near(l.y+l.h,slot.y+slot.h-20,'launcher bottom 20');
      assert.equal(await tag(),'','no status by default');assert(!(await h.query('bmc.ai_frame')).some(shown),'no AI frame by default');
      await shot(`B1-default${tagSize}`);report.checks.push(`${W}x${H} default: HUD right-top (one line "${hudText}"), launcher bottom-right, nothing in O1`);
      // B2: pointer over the picture -> HUD fades after 150 ms; leaving restores after 600 ms.
      await h.mouseMove(vp.x+vp.w/2,vp.y+vp.h/2);await h.sleep(500);
      assert((await opacityOf('bmc.fps'))<0.05,'HUD faded while the pointer is over the picture');
      await shot(`B2-immersive${tagSize}`);
      await h.mouseMove(4,4);await h.sleep(250);assert((await opacityOf('bmc.fps'))<0.05,'HUD still faded 250 ms after leaving');
      await h.sleep(800);assert((await opacityOf('bmc.fps'))>0.95,'HUD back 600 ms after leaving');
      report.checks.push(`${W}x${H} HUD fades on pointer enter (150 ms) and returns after leave (600 ms)`);
      // B3 / F2: AI operating -> accent Tag + takeover, AI frame in the black edge.
      await ai('operating');
      assert.match(await tag(),/^AI 操作/);await node('bmc.status.takeover');
      const frame=(await node('bmc.ai_frame')).rect;near(frame.x,card.x+6,'AI frame left in the 8pt edge');near(frame.x+frame.w,card.x+card.w-6,'AI frame right');
      assert(frame.x+2<=vp.x+0.5,'AI frame stroke stays outside the remote pixels');
      await shot(`B3-ai-operating${tagSize}`);
      // AI operating outranks AI observing; takeover reaches the typed stop.
      await h.clickTestId('bmc.status.takeover');await h.sleep(300);
      const afterStop=await stats();assert(afterStop.ai_stops>=1,'takeover called the AI stop');assert.equal(afterStop.ai,'none');
      await gone('bmc.status');await gone('bmc.ai_frame');
      await ai('observing');assert.match(await tag(),/^AI 观察/);assert(!(await h.query('bmc.ai_frame')).some(shown),'observing draws no frame');
      await shot(`O1-ai-observing${tagSize}`);
      report.checks.push(`${W}x${H} AI operating: accent tag + 接管 (typed stop) + 2px frame in the black edge; observing: neutral tag only`);
      // B4 / F3: capture -> info Tag outranks observing, hint centred with 84 per side, HUD hidden, launcher yields.
      await h.clickAt(vp.x+vp.w/3,vp.y+vp.h/3);await h.sleep(250);
      assert((await stats()).captured,'captured');assert.match(await tag(),/捕获/);
      const hint=(await node('bmc.input_hint')).rect;near(hint.x,vp.x+84,'hint band left = picture + 84');near(hint.w,Math.max(0,vp.w-168),'hint band width = picture - 168');
      near(hint.y+hint.h,vp.y+vp.h-12,'hint band bottom = picture bottom - 12');
      assert(!(await h.query('bmc.fps')).some(shown),'HUD hidden while captured');
      await h.waitFor(async()=>(await opacityOf('ai.launcher.anchor'))<0.05||null,3000);
      assert((await stats()).launcher_yielded,'launcher yields over the captured picture');
      await shot(`B4-captured${tagSize}`);
      await h.sleep(3300);assert(!(await h.query('bmc.input_hint')).some(shown),'transient hint gone after 3 s');
      await ai('operating');assert.match(await tag(),/^AI 操作/,'AI operating outranks capture');await ai('none');
      await h.key('escape',{ctrl:true,alt:true});await h.request('POST','/key_up',{key:'escape',ctrl:true,alt:true});await h.sleep(400);
      assert(!(await stats()).captured);assert((await opacityOf('ai.launcher.anchor'))>0.95,'launcher restored after release');
      report.checks.push(`${W}x${H} capture: info tag, hint band 84/side fading after 3 s, HUD hidden, launcher opacity 0 + pass-through, restored on ⌃⌥Esc`);
      // B5 / F4: power running -> warning Tag outranks everything, waiting alert over the old picture, HUD hidden.
      await startPower();
      if(!(await stats()).management_phase){report.limits.push(`${W}x${H}: power request not reachable through the fixture menu; skipped B5`);}
      else{
        await post('/app/bmc-fixture/management',{phase:'tracking_task',dispatched:true});await h.sleep(2600);
        await ai('operating');
        assert.match(await tag(),/^(正在|重启|关机|开机|断电)/,'power outranks AI operating');
        const alert=(await node('bmc.waiting')).rect;near(alert.x+alert.w/2,vp.x+vp.w/2,'waiting alert centred',1.5);
        assert(!(await h.query('bmc.fps')).some(shown),'HUD hidden while waiting for picture');
        assert((await h.query('bmc.frame')).some(shown),'old picture kept under the waiting alert');
        await ai('none');await h.mouseMove(4,4);await shot(`B5-power${tagSize}`);
        await post('/app/bmc-fixture/management',{phase:'succeeded'});await h.sleep(1300);await gone('bmc.waiting');
        report.checks.push(`${W}x${H} power running: warning tag with elapsed seconds outranks AI, waiting alert centred over the kept picture`);
      }
      await state('no_signal');await node('bmc.waiting');assert((await h.query('bmc.frame')).some(shown),'no signal keeps the old picture');
      assert(!(await h.query('bmc.progress')).some(shown),'the connection card yields to the waiting alert');
      await shot(`O4-no-signal${tagSize}`);await state('controlled');
      report.checks.push(`${W}x${H} no signal: waiting alert, old picture kept, connection card not shown`);
      if(W===1440){
      // D: the four corners. Top corners rest at toolbar bottom + 12; the HUD gives way to a top-right icon.
      for(const c of ['bottom_right','bottom_left','top_right','top_left']){
        await corner(c);await h.mouseMove(4,4);await h.sleep(300);
        const li=(await node('ai.launcher')).rect,hu=(await node('bmc.fps.display')).rect;
        if(c.startsWith('top'))near(li.y,bar.y+bar.h+12,`${c}: launcher top = toolbar + 12`);
        if(c==='top_right'){near(hu.x+hu.w,li.x-12,'HUD right = launcher left - 12');near(hu.y+hu.h/2,li.y+li.h/2,'HUD centred on the launcher',1.5);}
        else{near(hu.x+hu.w,vp.x+vp.w-12,`${c}: HUD stays`);}
        const overlap=li.x<hu.x+hu.w&&li.x+li.w>hu.x&&li.y<hu.y+hu.h&&li.y+li.h>hu.y;assert(!overlap,`${c}: launcher and HUD do not overlap`);
        assert(li.y>=bar.y+bar.h,`${c}: launcher never covers the toolbar`);
        await shot(`D-${c}`);
      }
      report.checks.push('Four corners: top anchor toolbar + 12, HUD gives way sideways only to a top-right icon, no overlap, toolbar never covered');
      // O4 corner rules on the connection card (bottom: height - 80).
      await corner('bottom_right');
      await post('/app/bmc-fixture/progress',{stage:'public_script',revision:12,elapsed_ms:9900,stage_elapsed_ms:900,log_generation:1});await h.sleep(400);
      const pc=(await node('bmc.progress')).rect;assert(pc.h<=Math.min(vp.h-24,441)-80+1,`progress card height ${pc.h} leaves 80 for a bottom icon`);
      await shot('O4-progress-bottom-icon');await state('controlled');
      // C: emulated split (narrow KVM card), same states.
      await width(720);const nvp=(await node('bmc.viewport')).rect;
      await h.mouseMove(4,4);await shot('C1-split-default');
      await h.mouseMove(nvp.x+nvp.w/2,nvp.y+nvp.h/2);await h.sleep(500);await shot('C2-split-immersive');await h.mouseMove(4,4);await h.sleep(900);
      await ai('operating');await shot('C3-split-ai-operating');await ai('none');
      await h.clickAt(nvp.x+nvp.w/3,nvp.y+nvp.h/3);await h.sleep(250);await shot('C4-split-captured');
      await h.key('escape',{ctrl:true,alt:true});await h.request('POST','/key_up',{key:'escape',ctrl:true,alt:true});await h.sleep(300);
      await startPower();
      if((await stats()).management_phase){await post('/app/bmc-fixture/management',{phase:'tracking_task',dispatched:true});await h.sleep(2600);await node('bmc.waiting');await h.mouseMove(4,4);await shot('C5-split-power');await post('/app/bmc-fixture/management',{phase:'succeeded'});await h.sleep(1300);}
      await state('controlled');
      await width(560);assert(/^\S+ FPS$/.test(await textOf('bmc.fps.display')),'compact HUD under 640');await shot('O2-compact');
      await width(420);await h.sleep(200);assert(!(await h.query('bmc.fps')).some(shown),'HUD hidden under 480');await shot('O2-hidden');
      await width(1100);
      report.checks.push('Narrow card: compact HUD < 640, hidden < 480');
      }
    }
    await post('/app/bmc-fixture/quit',{});
  }finally{
    await Promise.race([ended,h.sleep(3000)]);if(app.exitCode===null&&app.signalCode===null)app.kill('SIGTERM');await ended;await log.close();await rm(base,{recursive:true,force:true});
  }
}
try{for(const t of themes)for(const [W,H] of [[1440,900],[860,480]])await runTheme(t,W,H);report.status='passed';}
catch(e){report.status='failed';report.error=String((e as any)?.stack??e);process.exitCode=1;}
finally{await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));}
console.log(report.status+': '+out);
