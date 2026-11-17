/** Whole production wizard flow, isolated config and own delayed SSH handshake peer. */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdir,mkdtemp,realpath,open,readFile,rm,writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {waitForServerReady,waitFor,query,clickAt,key,type_,resizeWindow,screenshot,screenPos,sleep,scrollAt,inputState} from '../zig-out/share/zenit/harness/client.ts';
const binary=resolve(process.argv[2]),out=resolve(process.argv[3]),theme=process.argv[4]??'dark';
assert(['dark','light','sauber'].includes(theme));
await mkdir(out,{recursive:true});
const isolated=await realpath(await mkdtemp(join(tmpdir(),'zw-wizard-advanced-'))),data=join(isolated,'data'),rpc=join(isolated,'rpc');
await mkdir(data);await mkdir(rpc);
await writeFile(join(data,'hosts.toml'),'');
await writeFile(join(data,'config.toml'),`[meta]\nconfig_revision=1\n[ui]\ntheme="${theme}"\nfont_family="Menlo"\nfont_size=14\n`);
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const log=await open(join(out,'app.log'),'w');
const child=spawn(binary,[],{env:{...process.env,ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1'},stdio:['ignore',log.fd,log.fd]});
const ended=new Promise<void>(r=>child.once('close',()=>r()));
const report:any={status:'running',binary,sha256:createHash('sha256').update(await readFile(binary)).digest('hex'),theme,checks:[],stages:[],limits:['Synthetic Harness input, not physical keyboard/IME verification','No connection test, remote action or save requested']};
const shown=(n:any)=>n.visible!==false&&n.hidden!==true&&(n.effective_opacity??1)>0&&n.rect?.w>0&&n.rect?.h>0;
const flatten=(n:any):any[]=>[n,...(n.children??[]).flatMap(flatten)];
const text=(n:any)=>flatten(n).map(x=>x.text??'').join(' ');
async function current(id:string){
 if(id==='wizard.dialog'){
  // Production opens the editor in its own native window (`wizard.window`; its close is the traffic light, so the
  // in-panel `wizard.close` is hidden there); the in-window Modal is the fallback.
  const win=(await query('wizard.window')).find(shown);if(win)return win;
  if(!(await query('wizard.close')).some(shown))return null;
  return {rect:await screenPos(id)};
 }
 return (await query(id)).find(shown)??null;
}
async function visible(id:string){return waitFor(()=>current(id));}
async function click(id:string){let prior='';let repeats=0;const n=await waitFor(async()=>{const n=await current(id);if(!n)return null;const at=JSON.stringify(n.rect);repeats=at===prior?repeats+1:0;prior=at;await sleep(80);return repeats>=2?n:null;});assert((await clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok);}
async function fill(id:string,value:string){await click(id);await key('a',{cmd:true});await type_(value);await waitFor(async()=>{const n=await current(id);return n&&text(n).includes(value)?true:null});}
async function closed(){await waitFor(async()=>!((await query('wizard.close')).some(shown)||(await query('wizard.window')).some(shown))||null);}
async function capture(name:string){await sleep(500);const dialog=await visible('wizard.dialog');await writeFile(join(out,name+'.json'),JSON.stringify(dialog,null,2));assert((await screenshot(join(out,name+'.png'))).ok);report.stages.push({name,rect:dialog.rect});}
async function scrollBottom(){const area=await visible('wizard.scroll.identity');await scrollAt(area.rect.x+area.rect.w-20,area.rect.y+area.rect.h/2,0,-1800);await sleep(300);}
async function scrollTop(){const area=await visible('wizard.scroll.identity');await scrollAt(area.rect.x+area.rect.w-20,area.rect.y+area.rect.h/2,0,2200);await sleep(300);}
async function editStartup(value:string){await scrollBottom();await click('wizard.startup');await key('a',{cmd:true});await type_(value);await sleep(200);}
// The editor's own layout (src/features/connections/wizard/view/wizard_styles.zig + src/plugins/remote/editor.zig):
// title bar 44 (header_height), Stage padding [0,6,6,6] + island padding 4 around the pane (frame_height 6+8),
// stepper row 40 (stepper_height), footer 56 (footer_height), field rows of two equal columns 16 apart (fieldRow gap 16),
// form sections 14 apart (formSection), field label 15 high (label_height) 4 above its control (L.cell gap 4).
// Body inset / top follow RemoteEditor.updateViewport (editor.zig): compact = viewport w <= 860 or h <= 480 → 20 / 14, else 28 / 20.
const G={header:44,stage:6,island:4,stepper:40,footer:56,column_gap:16,section_gap:14,label:15,label_gap:4,disclosure_row:39,disclosure:15,disclosure_pad:12,advanced_gap:12,group_gap:8};
const near=(a:number,b:number,what:string,eps=0.05)=>assert(Math.abs(a-b)<=eps,`${what}: ${a} vs ${b}`);
function bodyInset(win:any){const compact=win.w<=860||win.h<=480;return {inset:compact?20:28,top:compact?14:20};}
/** Pane, stepper and footer of the editor window at its current size: the window is the hb6dT frame itself. */
async function assertFrame(win:any){
 // The pane subtree is the whole form (too large for a direct query); read it from the window tree.
 const pane=flatten(await visible('wizard.dialog')).find(n=>n.test_id==='wizard.pane'&&shown(n))?.rect;assert(pane,'pane');
 const steps=(await visible('wizard.steps')).rect,footer=(await visible('wizard.footer')).rect,{inset,top}=bodyInset(win);
 const edge=G.stage+G.island;
 assert.deepEqual(pane,{x:win.x+edge,y:win.y+G.header+G.island,w:win.w-2*edge,h:win.h-G.header-G.stage-2*G.island},'pane inside title bar, Stage and island');
 assert.deepEqual(steps,{x:pane.x+inset,y:pane.y+top,w:pane.w-2*inset,h:G.stepper},'stepper row');
 assert.deepEqual(footer,{x:pane.x+inset,y:pane.y+pane.h-G.footer,w:pane.w-2*inset,h:G.footer},'footer pinned to the pane bottom');
 return {pane,steps,footer,content:{x:pane.x+inset,w:pane.w-2*inset}};
}
/** A form section's visible rows stack 14 apart and fill it. */
function assertStack(section:any,what:string){
 const rows=(section.children??[]).filter(shown);assert(rows.length>0,what+' has rows');
 let y=section.rect.y;for(const row of rows){near(row.rect.y,y,`${what} row top`);y=row.rect.y+row.rect.h+G.section_gap;}
 near(section.rect.y+section.rect.h,y-G.section_gap,`${what} bottom`);return rows;
}
const labelNode=(root:any,name:string)=>{const n=flatten(root).find(x=>x.text===name&&shown(x));assert(n,'label '+name);return n;};
const valueText=(control:any)=>{const n=flatten(control).find(x=>x.text&&shown(x)&&x!==control);assert(n,'value text in '+control.test_id);return n;};
const centred=(control:any,inner:any,what:string)=>near(inner.rect.y-control.rect.y,control.rect.y+control.rect.h-inner.rect.y-inner.rect.h,what+' value vertically centred',1);
try{
 await waitForServerReady(30000);assert.equal(Number(JSON.parse(await readFile(join(rpc,'owner.json'),'utf8')).pid),child.pid);
 await resizeWindow(1440,900);await click('sidebar.empty.new');
 await fill('wizard.name','Advanced contract');await fill('wizard.host','127.0.0.1');await fill('wizard.user','fixture');
 await click('wizard.group.pick');await visible('wizard.group.menu');await capture('01-group-select');await key('escape');
 await click('wizard.advanced.toggle');await scrollBottom();await click('wizard.strict_host_key');await click('wizard.strict.disabled');await capture('02-strict-policy');
 assert.match(text(await visible('wizard.strict_host_key')),/关闭严格验证/);assert.match(text(await visible('wizard.advanced.summary')),/严格验证已关闭/);
 await scrollBottom();await capture('03-advanced-expanded');
 // The editor window keeps window_spec 720×640 whatever the main window's size (wizard.zig window_spec).
 const win=(await visible('wizard.dialog')).rect;assert.deepEqual(win,{x:0,y:0,w:720,h:640});
 const frame=await assertFrame(win);report.frame=frame;
 const card=await visible('wizard.advanced.card'),advanced=await visible('wizard.advanced.body'),startup=await visible('wizard.startup'),startupField=await visible('wizard.startup.field');
 await writeFile(join(out,'advanced-tree.json'),JSON.stringify(card,null,2));
 const strict=await visible('wizard.strict_host_key'),compression=await visible('wizard.compression'),encoding=await visible('wizard.encoding'),scrollback=await visible('wizard.scrollback');
 const timeout=await visible('wizard.ssh.connect_timeout'),keepalive=await visible('wizard.ssh.keepalive'),info=await visible('wizard.command_info'),shell=await visible('wizard.shell_integration');
 // Disclosure row (hb6dT b7EPH): 39 = 12 + 15 + 12, title at its left edge; the body follows 12 below (advancedSection gap).
 const summary=await visible('wizard.advanced.toggle'),summaryText=flatten(summary).find(n=>n.text==='高级选项'),row=(card.children??[]).find(shown);assert(summaryText);assert(row);
 assert.equal(row.rect.h,G.disclosure_row);near(summary.rect.y-row.rect.y,G.disclosure_pad,'disclosure top padding');assert.equal(summary.rect.h,G.disclosure);assert.equal(summaryText.rect.x,summary.rect.x);
 near(advanced.rect.y-row.rect.y-row.rect.h,G.advanced_gap,'advanced body under the disclosure row');report.summary={row:row.rect,rect:summary.rect,text:summaryText.rect};
 // Grid: the body spans the content column; each field row is two equal columns 16 apart.
 assert.equal(advanced.rect.x,frame.content.x);assert.equal(advanced.rect.w,frame.content.w);
 const column=(advanced.rect.w-G.column_gap)/2,left=advanced.rect.x,right=advanced.rect.x+column+G.column_gap;
 for(const [l,r,what] of [[strict,compression,'policy'],[timeout,keepalive,'defaults'],[encoding,scrollback,'terminal'],[info,shell,'command info']] as const){
  assert.equal(l.rect.x,left,what+' left column');assert.equal(r.rect.x,right,what+' right column');assert.equal(l.rect.w,column,what+' left width');near(l.rect.y,r.rect.y,what+' row top');
  if(r!==compression)assert.equal(r.rect.w,column,what+' right width');
 }
 assert(compression.rect.w<=column,'compression radios inside their column');
 assert.equal(startup.rect.x,advanced.rect.x);assert.equal(startup.rect.w,advanced.rect.w);assert.equal(startupField.rect.w,advanced.rect.w);
 const rows=assertStack(advanced,'advanced body');assert.equal(rows.length,5);near(startup.rect.y+startup.rect.h,advanced.rect.y+advanced.rect.h,'startup commands close the advanced body');
 // Labels: the view's own field labels are 15 high, 4 above their control; native Input / Textarea labels are zenit's,
 // above their control at one native spacing.
 const appLabels:[string,any][]=[['主机密钥策略',strict],['SSH 传输压缩',compression],['连接超时（全局默认）',timeout],['保活间隔（全局默认）',keepalive]];
 const labels:any[]=[];
 for(const [name,control] of appLabels){const label=labelNode(advanced,name);labels.push(label);assert.equal(label.rect.h,G.label,name+' height');assert.equal(label.rect.x,control.rect.x,name+' x');near(control.rect.y-label.rect.y-label.rect.h,G.label_gap,name+' gap');}
 const nativeGaps:number[]=[];
 for(const [name,control] of [['字符编码',encoding],['终端最大显示行数',scrollback],['启动命令 · 每行一条，连接后依次执行',startup]] as [string,any][]){const label=labelNode(advanced,name);labels.push(label);assert(label.rect.h>0);assert.equal(label.rect.x,control.rect.x,name+' x');const gap=control.rect.y-label.rect.y-label.rect.h;assert(gap>=0,name+' above its control');nativeGaps.push(gap);}
 for(const gap of nativeGaps)near(gap,nativeGaps[0],'native label spacing');
 assert.equal(labels.length,7);
 // Native controls at zenit's default size: one height for every md Input and Select of the form.
 for(const control of [scrollback,strict,info,shell])assert.equal(control.rect.h,encoding.rect.h,control.test_id+' shares the native control height');
 const encodingText=valueText(encoding);assert.equal(encodingText.text,'UTF-8');centred(encoding,encodingText,'encoding');
 const strictText=valueText(strict),infoText=valueText(info);centred(strict,strictText,'strict policy');centred(info,infoText,'command info');
 assert.equal(encodingText.rect.x,strictText.rect.x,'left column values align (Input / Select)');assert.equal(infoText.rect.x,strictText.rect.x,'left column values align (Select / Select)');
 // Startup Textarea: rows 4 (editor.zig mountIdentity) at the native metrics it reports itself.
 const metrics=await inputState('wizard.startup');assert(metrics.line_height!>0&&metrics.padding_v!>=0&&metrics.padding_h!>=0);
 // zenit sizes a rows-N Textarea from its own default frame (styles.zig textareaMetrics), not rows × line: it shows
 // all four rows inside its padding and has no room for a fifth.
 const rowsHeight=(n:number)=>n*metrics.line_height!+2*metrics.padding_v!;
 assert(startup.rect.h>=rowsHeight(4)-0.05&&startup.rect.h<rowsHeight(5),`startup textarea shows four native rows: ${startup.rect.h} in [${rowsHeight(4)}, ${rowsHeight(5)})`);
 report.geometry={card:card.rect,advanced:advanced.rect,column,strict:strict.rect,compression:compression.rect,encoding:encoding.rect,scrollback:scrollback.rect,startup:startup.rect,labels:labels.map(n=>({text:n.text,rect:n.rect})),native_label_gap:nativeGaps[0],encoding_text:encodingText.rect,startup_metrics:metrics};
 // Compression is a native RadioGroup: switching it moves the selection.
 const dot=(radio:any)=>flatten(radio).some(n=>n!==radio&&shown(n)&&!n.text&&n.rect.w<12&&n.rect.h<12);
 assert(dot(await visible('wizard.compression.disabled'))&&!dot(await visible('wizard.compression.enabled')),'compression starts off');
 await click('wizard.compression.enabled');await waitFor(async()=>dot(await visible('wizard.compression.enabled'))&&!dot(await visible('wizard.compression.disabled'))||null);
 await editStartup('echo first');await key('return');await type_('echo second');await capture('04-startup-two-lines');
 const typed=await visible('wizard.startup'),lines=flatten(typed).filter(n=>n.text==='echo first'||n.text==='echo second');assert.equal(lines.length,2);
 const typedMetrics=await inputState('wizard.startup');assert.equal(typedMetrics.buffer,'echo first\necho second');assert.equal(typedMetrics.display_line_count,2);
 near(lines[1].rect.y-lines[0].rect.y,typedMetrics.line_height!,'startup line pitch');near(lines[0].rect.x-typed.rect.x,typedMetrics.padding_h!,'startup text inset x');near(lines[0].rect.y-typed.rect.y,typedMetrics.padding_v!,'startup text inset y');
 report.geometry.startup_lines=lines.map(n=>n.rect);assert.match(text(await visible('wizard.advanced.summary')),/启动命令 2 条/);
 await click('wizard.next.identity');await click('wizard.next.route');await visible('wizard.review.options');assert.match(text(await visible('wizard.review.options')),/启动命令 2 条/);await capture('05-review-preserves-options');
 await click('wizard.review.modify');await scrollBottom();assert.match(text(await visible('wizard.startup')),/echo first/);assert.match(text(await visible('wizard.startup')),/echo second/);
 assert(dot(await visible('wizard.compression.enabled')),'compression choice survives review and return');
 // The harness resizes the window it is bound to — the editor window while it is open (main window size is not its size).
 await resizeWindow(860,480);await scrollBottom();const compactDialog=await waitFor(async()=>{const d=await visible('wizard.dialog');return d.rect.w===860&&d.rect.h===480?d.rect:null;});
 assert.deepEqual(compactDialog,{x:0,y:0,w:860,h:480});const compact=await assertFrame(compactDialog);const footerBefore=compact.footer;report.compact={dialog:compactDialog,steps:compact.steps,footer:footerBefore,pane:compact.pane};
 await capture('06-advanced-compact');await editStartup('echo changed');assert.deepEqual((await visible('wizard.footer')).rect,footerBefore);
 const compactAdvanced=await visible('wizard.advanced.body');assert(compactAdvanced.rect.y+compactAdvanced.rect.h>footerBefore.y||compactAdvanced.rect.y<compact.steps.y+compact.steps.h,'advanced body taller than the compact viewport scrolls under a fixed footer');
 await scrollTop();const compactName=(await visible('wizard.name')).rect,compactGroup=(await visible('wizard.group')).rect,compactPick=(await visible('wizard.group.pick')).rect;
 const compactColumn=(compact.content.w-G.column_gap)/2;
 assert.equal(compactName.x,compact.content.x);assert.equal(compactName.w,compactColumn);assert.equal(compactGroup.x-compactName.x-compactName.w,G.column_gap);
 assert.equal(compactPick.x-compactGroup.x-compactGroup.w,G.group_gap);assert.equal(compactPick.x+compactPick.w,compact.content.x+compact.content.w,'group Select closes the right column');assert.equal(compactGroup.w+G.group_gap+compactPick.w,compactColumn);
 report.compact.columns={name:compactName,group:compactGroup,pick:compactPick};await capture('07-identity-compact');
 await click('wizard.protocol');await click('wizard.protocol.sftp');await scrollBottom();await click('wizard.advanced.toggle');await scrollBottom();await capture('08-sftp-advanced');
 assert(!(await current('wizard.startup')));assert(!(await current('wizard.command_info')));assert(!(await current('wizard.shell_integration')));
 const sftpAdvanced=await visible('wizard.advanced.body');assert.equal(assertStack(sftpAdvanced,'sftp advanced body').length,3);assert.equal(sftpAdvanced.rect.w,compact.content.w);report.geometry.sftp_advanced=sftpAdvanced.rect;
 await click('wizard.cancel');await closed();assert.equal((await readFile(join(data,'hosts.toml'),'utf8')).trim(),'');
 report.checks=['Native asset group Select opens and Escape dismisses','Native host-key Select switches policy (value and advanced summary)','Editor window 720x640: pane, stepper 40 and footer 56 at the body inset','Advanced disclosure row 39 expands to a 14-gap stack of two 16-apart equal columns: policy/compression, defaults, encoding/scrollback, command info; startup spans the row','Field labels 15 high 4 above their control; native labels at one native spacing','Native Inputs and Selects share one height, values vertically centred and left-aligned','Startup Textarea is four native rows with native line pitch and insets; independent multiline editing','Compression RadioGroup switches and survives review','Two command lines survive review and return','Editor window resized to 860x480 keeps the frame and fixed footer while advanced body scrolls','Compact identity columns: name / group Input + group Select','SFTP excludes startup commands and terminal command options','Cancel leaves isolated hosts empty and no network request'];report.status='passed';
}catch(e){report.status='failed';report.error=String(e);await screenshot(join(out,'failure.png')).catch(()=>{});throw e;}
finally{await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));child.kill('SIGTERM');await ended;await log.close();await rm(isolated,{recursive:true,force:true});}
console.log(JSON.stringify(report));
