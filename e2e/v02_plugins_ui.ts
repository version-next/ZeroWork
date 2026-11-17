/** Real native plugin settings at the approved standard/minimum sizes.
 * Each theme has its own PID/data/RPC. Public Harness input; real Metal pixels.
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createHash} from 'node:crypto';
import {realpath,mkdir,mkdtemp,open,readFile,writeFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {waitForServerReady,waitFor,query,clickAt,resizeWindow,screenshot,sleep} from '../vendor/zenit/e2e/client.ts';
import {settingsNav} from './settings_nav.ts';
const opts:Record<string,string>={};for(let i=2;i<process.argv.length;i+=2){assert(['--binary','--out','--fixture'].includes(process.argv[i])&&process.argv[i+1]);opts[process.argv[i]]=process.argv[i+1];}
assert(opts['--binary']&&opts['--out']);
const binary=resolve(opts['--binary']),out=resolve(opts['--out']);await mkdir(out,{recursive:true});
const report:any={status:'running',binary,binary_sha256:createHash('sha256').update(await readFile(binary)).digest('hex'),themes:[],limits:['Public synthetic Harness input; physical keyboard/IME not claimed.','Actual Metal PNGs require visual review; node geometry alone is not pixel verification.','Each final SIGTERM is own-process cleanup, not window-close evidence.']};
function shown(n:any){return n?.rect&&n.visible!==false&&n.hidden!==true&&(n.effective_opacity??1)>0&&n.rect.w>0&&n.rect.h>0;}
function nodes(n:any):any[]{return !n?[]:[n,...(n.children??[]).flatMap(nodes)];}
function visibleNodes(n:any):any[]{return !shown(n)?[]:[n,...(n.children??[]).flatMap(visibleNodes)];}
async function visible(id:string){return waitFor(async()=>(await query(id)).find(shown)??null,12000);}
async function click(id:string){const n=await visible(id);assert((await clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok);await sleep(100);}
let failure:any;
for(const theme of ['dark','light','sauber']){
 const iso=await realpath(await mkdtemp('/private/tmp/zw-v02-plugins-')),rpc=join(iso,'rpc'),data=join(iso,'data');await mkdir(rpc);await mkdir(data);
 await writeFile(join(data,'config.toml'),`[meta]\nconfig_revision=1\n[updates]\nauto_check=false\n[ui]\ntheme="${theme}"\nfont_family="Menlo"\nfont_size=14\n`);
 process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;const log=await open(join(out,`${theme}.app.log`),'w');
 const app=spawn(binary,[],{cwd:process.cwd(),env:{...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1',ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0'},stdio:['ignore',log.fd,log.fd]});
 const ended=new Promise<void>(done=>app.once('close',()=>done()));const record:any={theme,pid:app.pid,status:'running',captures:[]};report.themes.push(record);
 async function capture(name:string){await sleep(300);const state=Object.fromEntries(await Promise.all(['workspace.shell','settings.panel','settings.plugins','settings.content','settings.footer'].map(async id=>[id,await query(id)])));await writeFile(join(out,name+'.json'),JSON.stringify(state,null,2));assert((await screenshot(join(out,name+'.png'))).ok);record.captures.push(name);}
 try{
  await waitForServerReady();assert.equal(Number(JSON.parse(await readFile(join(rpc,'owner.json'),'utf8')).pid),app.pid);await resizeWindow(1440,900);
  await settingsNav().toCategory('plugins');const plugins=await visible('settings.plugins'); // 协议插件 is a direct page (settings_nav.ts)
  // 协议插件两级导航（F-set-plugins）：列表页每个插件一行 `settings.plugin.<id>.row`（`DrillRow`），按来源分组。
  record.rows=visibleNodes(plugins).filter(n=>/^settings\.plugin\.(local|ssh|sftp|bmc_ikvm)\.row$/.test(n.test_id??'')).map(n=>({id:n.test_id.split('.')[2],rect:n.rect}));
  for(const id of ['local','ssh','sftp','bmc_ikvm'])assert(record.rows.some(n=>n.id===id),`Registry contribution ${id} visible`);
  // “计划中”只有路线条目（网页连接），排在已注册插件之后；没有插件行 id。
  const planned=visibleNodes(plugins).find(n=>n.test_id==='settings.plugins.planned.web.row');
  assert(planned,'Roadmap entry web visible under 计划中');
  record.planned={id:'web',rect:planned.rect};
  assert(record.rows.every(n=>planned.rect.y>n.rect.y),'Roadmap entries follow registered plugins');
  for(let i=1;i<record.rows.length;i++)assert(record.rows[i].rect.y>record.rows[i-1].rect.y,'Protocol rows stack vertically');
  await capture(`plugins-${theme}-1440`);
  if(opts['--fixture']==='1'){
   const fixture=await waitFor(async()=>visibleNodes(await visible('settings.plugins.bundled')).find(n=>/^settings\.plugin\..*fixture.*\.row$/.test(n.test_id??''))??null,12000);
   record.fixture_row={id:fixture.test_id,rect:fixture.rect};
   await click(fixture.test_id);await visible(fixture.test_id.replace(/\.row$/,'.detail'));
   await capture(`plugins-${theme}-fixture-detail`);await click('settings.history.back');await visible('settings.plugins.bundled');
  }
  await resizeWindow(860,480);await waitFor(async()=>{const root=await visible('settings.panel');return root.rect.w===860&&root.rect.h===480||null;});// the preferences window is the resized automation window
  await capture(`plugins-${theme}-860`);
  record.status='passed_pending_pixel_review';
 }catch(e){failure=e;record.status='failed';record.error=String(e);try{await capture(`plugins-${theme}-failure`);}catch{}}
 finally{if(app.exitCode===null&&app.signalCode===null)app.kill('SIGTERM');await Promise.race([ended,sleep(2000)]);if(app.exitCode===null&&app.signalCode===null){app.kill('SIGKILL');await ended;}record.cleanup={exit_code:app.exitCode,signal:app.signalCode};await log.close();await rm(iso,{recursive:true,force:true});}
 if(failure)break;
}
report.status=failure?'failed':'passed_pending_pixel_review';await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));console.log(report.status);if(failure)throw failure;
