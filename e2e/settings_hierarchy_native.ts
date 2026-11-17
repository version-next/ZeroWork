/**
 * All settings pages: pane hierarchy, contextual help and protected notices,
 * on the two-level Settings window (each pane is reached on its subpage via
 * `settings_nav.ts`). Pane folding no longer exists (every pane is always
 * open on its subpage), so the former "expanded hides summary" checks are
 * replaced by "every pane header renders on its subpage".
 */
import assert from 'node:assert/strict';
import {mkdir,readFile,writeFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import * as h from '../vendor/zenit/e2e/client.ts';
import {settingsNav,launchIsolated,locatePane,textOf} from './settings_nav.ts';
const binary=resolve(process.argv[2]),out=resolve(process.argv[3]);await mkdir(out,{recursive:true});
const pages:any={appearance:['settings.appearance.app_icon.header','settings.appearance.themes.header','settings.materials.header','settings.appearance.font.header','settings.appearance.aids.header'],keys:['settings.keys.tabs.header','settings.keys.terminal.header'],ssh:['settings.ssh.connection.header','settings.ssh.reconnect.header','settings.ssh.socks.header','settings.ssh.authentication.header'],transfer:['settings.transfer.connection.header','settings.transfer.engine.header','settings.transfer.defaults.header'],ai:['settings.ai.permissions.header','settings.ai.context.header','settings.ai.attachments.header','settings.ai.behavior.header'],plugins:['settings.plugins.builtin','settings.plugins.bundled'],notifications:['settings.notifications.events.header','settings.notifications.attention.header'],data:['settings.data.location.header','settings.data.history.header','settings.data.actions.header']};
const markers:any={appearance:['settings.appearance.font','settings.appearance.help.cursor_style'],keys:['settings.keys.terminal','settings.key.fixed.accept_completion'],ssh:['settings.ssh.connection','settings.help.keepalive_sec'],transfer:['settings.transfer.connection','settings.help.shared_pacing_kbps'],ai:['settings.ai.behavior','settings.help.error_hint'],notifications:['settings.notifications.events','settings.notifications.permission.info'],data:['settings.data.location','settings.path.配置文件']};
const paneOf=(header:string)=>header==='settings.materials.header'?'settings.appearance.materials':header.replace(/\.header$/,'');
const flat=(n:any):any[]=>[n,...(n.children??[]).flatMap(flat)];
const report:any={status:'running',runs:[],limits:['Temporary isolated config; no real credentials, permission requests or destructive actions.','No physical IME or VoiceOver verification.']};
for(const theme of ['dark','light']){
 const initialExtra=`[ai]\ndefault_provider="Fixture"\n[[ai.providers]]\nid="Fixture"\nkind="openai_compat"\nendpoint="http://127.0.0.1:9/v1/chat/completions"\nenabled=true\n[[ai.providers.models]]\nname="model"\ndefault=true\ncontext_window=128000\n`;
 const app=await launchIsolated({binary,out,prefix:'zw-hierarchy',theme,config:initialExtra,logName:theme+'.log'});
 await writeFile(join(app.data,'hosts.toml'),'');const initial=await readFile(app.config,'utf8');
 const nav=settingsNav();
 async function top(){const v=await nav.node('settings.viewport');await h.scrollAt(v.rect.x+v.rect.w/2,v.rect.y+v.rect.h/2,0,4000);await h.sleep(70);}
 async function capture(name:string){assert((await h.screenshot(join(out,name+'.png'))).ok);}
 const run:any={theme,pages:[],hints:[]};report.runs.push(run);
 try{
  assert.equal(Number(JSON.parse(await readFile(join(app.rpc,'owner.json'),'utf8')).pid),app.app.pid);await h.resizeWindow(1440,900);await nav.open();
  for(const [page,headers] of Object.entries(pages) as any){
   if(page==='plugins'){await nav.toCategory('plugins');assert(textOf(await nav.node('settings.plugins.builtin')).includes('已内置'));await nav.node('settings.plugins.bundled');}
   else for(const id of headers){await nav.toPane(paneOf(id));await nav.reveal(id);}
   await top();await capture(theme+'-'+page+'-top');
   if(page==='ai'){await nav.toSub('ai','providers');await nav.click('settings.ai.provider.0.header');const m=await nav.reveal('settings.ai.provider.0.keychain');await h.mouseMove(m.rect.x+m.rect.w/2,m.rect.y+m.rect.h/2);assert(textOf(await nav.node('settings.ai.provider.0.keychain.tooltip')).includes('钥匙串'));await h.mouseMove(10,10);run.hints.push('settings.ai.provider.0.keychain');}
   const marker=markers[page];if(marker){const [pane,id]=marker;await nav.toPane(pane);const m=await nav.reveal(id);assert(m.rect.h<=32);await h.mouseMove(m.rect.x+m.rect.w/2,m.rect.y+m.rect.h/2);assert(textOf(await nav.node(id+'.tooltip')).trim().length>0);await capture(theme+'-'+page+'-hint');await nav.click(id);await h.key('escape');await h.sleep(200);await nav.node('settings.panel');await h.mouseMove(10,10);run.hints.push(id);}
   if(page==='ssh')for(const key of ['buffer_input','socks_bind']){await nav.toField(key);const n=await nav.node('settings.help.content.'+key);assert(textOf(n).trim().length>0);}
   if(page==='ai'){await nav.toSub('ai','behavior');const n=await nav.reveal('settings.help.content.redact_ip');assert(textOf(n).includes('终端正文与附件'));}
   if(page==='plugins')assert(!textOf(await nav.node('settings.content')).includes('内置协议随应用管理。'));
   const v=await nav.node('settings.viewport');await h.scrollAt(v.rect.x+v.rect.w/2,v.rect.y+v.rect.h/2,0,-4000);await h.sleep(100);await capture(theme+'-'+page+'-bottom');
   await h.resizeWindow(860,480);await top();assert(!(await nav.visible('settings.footer')),'clean page: no Save Bar (H-save)');await capture(theme+'-'+page+'-compact-top');
   await h.scrollAt((await nav.node('settings.viewport')).rect.x+100,300,0,-4000);await h.sleep(100);assert(!(await nav.visible('settings.footer')));await capture(theme+'-'+page+'-compact-bottom');
   if(page==='appearance'){await nav.toSub('appearance','font');const group=await nav.reveal('settings.field.cursor_style');await capture(theme+'-appearance-cursor-compact');const opts=flat(group).filter(n=>['方块','竖线','下划线'].includes(n.text));assert.equal(new Set(opts.map(n=>n.text)).size,3,'three cursor options');for(const n of opts)assert(n.rect.x>=group.rect.x-.5&&n.rect.x+n.rect.w<=group.rect.x+group.rect.w+.5,'cursor option inside group');const view=(await nav.node('settings.viewport')).rect;assert(group.rect.x+group.rect.w<=view.x+view.w,'cursor group not clipped');}
   run.pages.push(page);await h.resizeWindow(1440,900);
  }
  await nav.toSub('ssh','connection');await top();assert(textOf(await nav.node('settings.ssh.connection.summary')).length>0);await nav.node('settings.help.keepalive_sec');
  assert.equal(await readFile(app.config,'utf8'),initial);run.status='passed';
 }catch(e){run.status='failed';run.error=String(e);report.status='failed';await capture(theme+'-failure').catch(()=>{});throw e;}
 finally{await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));await app.stop();}
}
report.status='passed';await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));console.log(JSON.stringify({status:report.status}));
