import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import {nativeThemeData} from './native_theme_data.mjs';
/** Own Metal windows + loopback model; no user storage, hosts or external AI. */
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {spawn} from 'node:child_process';
import {mkdir,mkdtemp,open,writeFile,readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {aiToggleId} from './ai_entry.ts';
const prefix=process.env.ZW_THEME_MATERIAL_PREFIX??'/tmp/zw-theme-material-build';
const h=await import(join(prefix,'share/zenit/harness/client.ts'));
const {settingsNav}=await import('./settings_nav.ts');
// Two-level settings (settings_nav.ts): AI 辅助 › 服务提供方, 外观与主题 › 字体与排版; Cmd+W closes (no close button).
const nav=settingsNav();
const out=resolve(process.argv[2]??'/tmp/zw-theme-material-evidence');await mkdir(out,{recursive:true});
const model=createServer(async(req,res)=>{
 if(req.method==='GET'){res.setHeader('Content-Type','application/json');res.end(JSON.stringify({data:[{id:'material-fixture',context_window:32768}]}));return;}
 for await(const _ of req){};
 res.writeHead(200,{'Content-Type':'text/event-stream'});
 res.end('data: '+JSON.stringify({choices:[{delta:{content:'材质验证答复：这是一条本地测试消息。'}}]})+'\n\ndata: [DONE]\n\n');
});
await new Promise<void>(done=>model.listen(0,'127.0.0.1',done));
const port=(model.address() as any).port;
const report:any={status:'running',cases:[],limits:['Synthetic Harness input in isolated native windows; no physical keyboard or IME claim.','Loopback responses only; validates native transcript rendering, not remote models.']};
// Float cards open with the genie-static transition (deccd08b): while the snapshot texture flies, the real card subtree
// stays at effective_opacity 0 and is not hit-testable. "Shown" therefore means landed (opaque), not merely laid out.
const shown=(n:any)=>n&&n.hidden!==true&&n.visible!==false&&(n.effective_opacity??1)>.98&&n.rect?.w>0&&n.rect?.h>0;
const visible=(id:string)=>h.waitFor(async()=>(await h.query(id)).find(shown)??null,15000);
const click=async(id:string)=>{await visible(id);assert((await h.clickTestId(id)).ok,id);};
try{
 const themes=process.env.ZW_THEME_IDS?.split(',')??Object.keys(nativeThemeData.themes);
 const transparencies=process.env.ZW_THEME_MATERIAL_TRANSPARENCIES?.split(',').map(Number)??[0,50,100];
 for(const theme of themes){for(const t of transparencies){const b=0;
  const name=`${theme}-t${t}`,iso=await mkdtemp('/private/tmp/zw-theme-material-'),data=join(iso,'data'),rpc=join(iso,'rpc');await mkdir(data);await mkdir(rpc);
  await writeFile(join(data,'config.toml'),`[ui]\ntheme = "${theme}"\n[ui.materials]\nblur_px = ${b}\n[ui.materials.background]\ntransparency = ${t}\n[ai]\ndefault_provider = "fixture"\n[[ai.providers]]\nid = "fixture"\nkind = "openai_compat"\nendpoint = "http://127.0.0.1:${port}/v1/chat/completions"\nenabled = true\n[[ai.providers.models]]\nname = "material-fixture"\ncontext_window = 32768\ndefault = true\nefforts = []\n`);
  process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
  const log=await open(join(out,name+'.log'),'w');
  const env={...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1',ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0'};
  for(const key of ['ZEROWORK_AI_MOCK','ZEROWORK_AI_ENDPOINT','ZEROWORK_AI_MODEL','ZEROWORK_AI_PROVIDER'])delete env[key];
  const app=spawn(join(prefix,'bin/zerowork'),[],{cwd:process.cwd(),env,stdio:['ignore',log.fd,log.fd]});
  const ended=new Promise<void>(done=>app.once('close',()=>done()));
  const item:any={name,theme,transparency:t,blur:b,captures:[],status:'running'};report.cases.push(item);
  async function capture(stage:string,ids:string[]){await h.sleep(250);const path=join(out,name+'-'+stage+'.png');assert((await h.screenshot(path)).ok);await writeFile(path.replace('.png','.json'),JSON.stringify(Object.fromEntries(await Promise.all(ids.map(async id=>[id,await h.query(id)]))),null,2));item.captures.push(path);}
  try{
   await h.waitForServerReady();await h.resizeWindow(1440,900);
   await click('workspace.empty.local');await visible('terminal.surface');await click(await aiToggleId());await visible('ai.prompt');
   await capture('recent',['ai.panel','ai.empty.recent','ai.launcher']);
   await click('ai.prompt');await h.type_('请检查主题和全局透明度。');await click('ai.send');
   await visible('ai.message.user.bubble');await h.waitFor(async()=>!(await h.query('ai.stop')).some(shown)||null,15000);
   await capture('bubble',['ai.panel','ai.message.user.bubble','ai.response','ai.launcher']);
   const bubble=await visible('ai.message.user.bubble');assert(bubble.rect.w>0&&bubble.rect.w<=429.5,'bubble preserves 75% width limit');
   // 3f2f07f2: on narrow tool rows (the default 420 float) permission gives way to its native icon-button form
   // `ai.composer.permission.compact`; exactly one of the two forms is shown (ai_composer_controls_view.zig chipShown).
   {const forms=(await Promise.all(['ai.composer.permission','ai.composer.permission.compact'].map(async id=>(await h.query(id)).some(shown)?id:null))).filter(Boolean) as string[];assert.equal(forms.length,1,'exactly one permission control form is shown: '+forms.join(','));await click(forms[0]);}
   await visible('ai.permission.menu');await capture('popover',['ai.permission.menu']);await h.key('Escape');
   await click('ai.collapse');await nav.toPane('settings.ai.providers');
   await visible('settings.ai.provider.0.header');
   if(!(await h.query('settings.ai.provider.0.endpoint')).some(shown))await click('settings.ai.provider.0.header');
   await visible('settings.ai.provider.0.endpoint');
   await capture('provider',['settings.panel','settings.ai.provider.0.header','settings.ai.provider.0.endpoint','settings.save']);
   await nav.toField('font_size');await click('settings.field.font_size');await capture('picker',['settings.panel','settings.field.font_size','settings.save']);await h.key('Escape');if(await nav.visible('settings.panel'))await nav.close();
   await click('terminal.surface');await h.type_('/bin/sleep 30');await h.key('return');
   // The close confirmation is for a tab whose shell runs a foreground command; the product shows that as the tab title
   // "sleep · ~". Wait for it instead of a fixed 350 ms (the command may not have started yet, then the tab closes at once).
   await h.waitFor(async()=>{const flat=(n:any):any[]=>n?[n,...(n.children??[]).flatMap(flat)]:[];return (await h.query('tabs.tab.1')).flatMap(flat).some((n:any)=>n.test_id==='tabs.title'&&typeof n.text==='string'&&n.text.startsWith('sleep'))||null;},15000);
   // 3a81589d: a tab's close chip follows the pointer or keyboard focus (tab_strip_view.zig closeShown); hover the tab first.
   {const tab=await visible('tabs.tab.1');await h.mouseMove(tab.rect.x+tab.rect.w/2,tab.rect.y+tab.rect.h/2);}
   await click('tabs.close.1');await visible('local.close.confirmation');await capture('danger',['local.close.confirmation','local.close.accept']);await click('local.close.cancel');await visible('terminal.surface');await h.key('c',{ctrl:true});
   item.status='passed';console.log(name+' passed');
  }catch(e){item.status='failed';item.error=String(e);await capture('failure',['settings.panel','ai.panel','tabs.strip']).catch(()=>{});throw e;}
  finally{if(app.exitCode===null&&app.signalCode===null)app.kill('SIGTERM');await ended;await log.close();}
 }}
 report.status='passed';
}catch(e){report.status='failed';report.error=String(e);console.error(e);process.exitCode=1;}
finally{model.close();await writeFile(join(out,'native-report.json'),JSON.stringify(report,null,2));}
