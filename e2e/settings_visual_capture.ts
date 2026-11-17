/** Isolated settings visual captures; synthetic public Harness, no OS permission action.
 * Two-level Settings window: categories with an overview are captured on the
 * overview and on every subpage (`settings_nav.ts`); the others directly. */
import assert from 'node:assert/strict';
import {mkdir,writeFile,readFile} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {waitFor,query,resizeWindow,screenshot,sleep,screenPos,stats,key} from '../vendor/zenit/e2e/client.ts';
import {settingsNav,launchIsolated,CATEGORIES} from './settings_nav.ts';
/** Visible text only (hidden prompts / keycap slots skipped). */
const visText=(n:any):string=>n?.visible===false?'':[typeof n?.text==='string'?n.text:n?.text?.content??'',...(n?.children??[]).map(visText)].join('');
const [binaryArg,outArg]=process.argv.slice(2),binary=resolve(binaryArg),out=resolve(outArg);await mkdir(out,{recursive:true});
const report:any={status:'running',input:'public synthetic Harness',captures:[]};
const ids=['settings.content','settings.viewport','settings.footer','settings.save','settings.ssh.connection','settings.ssh.connection.header','settings.row.keepalive_sec','settings.field.keepalive_sec','settings.keys.tabs','settings.keys.terminal','settings.key.row.new_tab','settings.key.new_tab','settings.plugins.builtin','settings.notifications.events','settings.notifications.permission','settings.data.location','settings.data.credential_help','settings.overview','settings.page.title'];
const shownNode=(n:any)=>n.visible!==false&&n.rect.w>0&&n.rect.h>0&&(n.effective_opacity??1)>0;
for(const theme of ['dark','light']){
 const run=await launchIsolated({binary,out,prefix:'zw-settings-visual',theme,config:'font_family="Menlo"\nfont_size=14\n',logName:theme+'.log'});
 const nav=settingsNav({timeout:10000});
 try{assert.equal(Number(JSON.parse(await readFile(join(run.rpc,'owner.json'),'utf8')).pid),run.app.pid);await resizeWindow(1440,900);await nav.open();
 for(const width of [1440,860]){await resizeWindow(width,width===1440?900:480);
  for(const page of (process.env.ZW_SETTINGS_PAGES?.split(',')??['appearance','keys','ssh','transfer','plugins','notifications','data'])){
   const subs=CATEGORIES.find(([c])=>c===page)?.[2]??[];
   const targets:[string|null,string][]=[[null,page],...subs.map(([s]):[string,string]=>[s,`${page}-${s}`])];
   for(const [sub,label] of targets){
    if(sub===null)await nav.toCategory(page);else await nav.toSub(page,sub);
    await sleep(180);const name=`${theme}-${width}-${label}`;assert((await screenshot(join(out,name+'.png'))).ok);
    report.captures.push({name,root:await screenPos('workspace.shell').catch(()=>null),panel:await screenPos('settings.panel'),stats:await stats()});
    const geometry=Object.fromEntries(await Promise.all(ids.map(async id=>[id,await query(id)])));
    await writeFile(join(out,name+'.json'),JSON.stringify(Object.fromEntries(Object.entries(geometry).map(([id,nodes]:any)=>[id,nodes.map((n:any)=>({id:n.id,rect:n.rect,text:n.text,effective_opacity:n.effective_opacity,disabled:n.disabled,children:n.children}))])),null,2));
   }
   if(page==='keys'&&width===1440&&theme==='dark'){await nav.toCategory('keys');// Inline recording (F-set-panes-B; the recorder dialog is gone): the key area shows the prompt, Escape cancels.
    await nav.click('settings.key.new_tab');await waitFor(async()=>visText(await nav.node('settings.key.new_tab')).includes('按下新快捷键')?true:null,5000);await screenshot(join(out,'shortcut-recorder.png'));await key('escape');await waitFor(async()=>visText(await nav.node('settings.key.new_tab')).includes('按下新快捷键')?null:true,5000);await nav.node('settings.panel');}
   if(page==='data'&&width===1440&&theme==='dark'){await nav.toSub('data','location');await nav.click('settings.data.credential_help');await sleep(150);await screenshot(join(out,'credential-help.png'));await writeFile(join(out,'credential-help.json'),JSON.stringify(await query('settings.data'),null,2));await nav.toCategory('ssh');}
  }}
 }catch(e){report.error=String(e);throw e;}finally{await run.stop();await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));}
}
report.status='captured_pending_visual_review';await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));console.log(report.status);
