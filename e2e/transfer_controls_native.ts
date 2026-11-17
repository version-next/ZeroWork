/** Production transfer task rows and panel controls in an isolated process.
 *
 *   node e2e/transfer_controls_native.ts <binary> <out> [fixture|session|tray|main] [dark|light]
 *
 * `fixture` / `session` / `tray` run `transfer-controls-preview` built with
 * `-Dtransfer-preview-presentation=global_popover` (the default) / `session_popover` / `session_tray`:
 * the production renderer (`src/features/transfer/view/transfer_manager_view.zig`) over eight frozen
 * tasks (`src/features/transfer/preview/transfer_controls_preview_runner.zig`); task actions only
 * print `TRANSFER_CONTROLS_FIXTURE action=… job=…`. `main` runs the real application and checks the
 * title bar entry and the three ways to close the popover.
 *
 * Contract (Island B v3, e1372d88; Pencil `Gq5xg` 传输弹层): popover / tray rows are
 * `transfer_styles.popover_row_height` = 54 with no gap between rows (name 16 / gap 3 / meta 14 /
 * gap 3 / 4pt progress), the direct actions sit in a right aligned cell, the checkbox only exists
 * while "管理任务" is on, the details are a click Popover on the file name.
 *
 * Not exercised on purpose: the copy buttons (`transfer.task.copy_path`, `transfer.detail.copy_*`)
 * write the system clipboard (zenit has no test clipboard), so they are checked for presence only.
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdtemp,mkdir,open,readFile,writeFile,realpath} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import {createHash} from 'node:crypto';
import {waitForServerReady,waitFor,query,clickAt,mouseMove,key,scrollAt,resizeWindow,screenshot,sleep} from '../zig-out/share/zenit/harness/client.ts';

const binary=resolve(process.argv[2]),out=resolve(process.argv[3]),mode=process.argv[4]??'fixture',theme=process.argv[5]??'dark';
assert(['fixture','session','tray','main'].includes(mode),'mode');assert(['dark','light'].includes(theme),'theme');
await mkdir(out,{recursive:true});
const iso=await realpath(await mkdtemp('/tmp/zw-transfer-controls-')),rpc=join(iso,'rpc'),data=join(iso,'data');
await mkdir(rpc);await mkdir(data);
if(mode==='main')await writeFile(join(data,'config.toml'),'[updates]\nauto_check=false\n',{mode:0o600});   // main keeps its default theme
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const logPath=join(out,'app.log'),log=await open(logPath,'w');
const app=spawn(binary,mode==='main'?[]:[`--theme=${theme}`],{env:{...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1'},stdio:['ignore',log.fd,log.fd]});
const end=new Promise(r=>app.once('close',r));

// ---- design constants (src/features/transfer/view/transfer_styles.zig) ----
const ROW_H=54;        // popover_row_height (Gq5xg); the list pitch is the same value (rowPitch), rows touch
const NAME_LINE=16;    // name_line
const META_LINE=14;    // meta_line
const TRACK_H=4;       // track(): W:hl4YW progress, 4pt
const STATUS_MAX=96;   // status_max: fitLabel cap, a label at the cap is ellipsized
const RATE_MAX=120;    // rate_max
const DETAIL_W=420;    // hoverDetail() / the name Popover width and max_width
const EPS=0.6;

// ---- the frozen tasks of the preview (transfer_controls_preview_runner.zig: names / phases / jobs 1042+i) ----
// primary = primaryAction(phase) (null: a passive clock slot, or nothing for a finished upload);
// cancel = allows(phase, .cancel).
type Expect={job:number,status:string,primary:string|null,cancel:boolean,error?:string};
const EXPECT:Record<string,Expect>={
 'release.tar.gz':{job:1042,status:'传输中',primary:'pause',cancel:true},
 'worker.stdout.log':{job:1043,status:'传输中',primary:'pause',cancel:true},
 'production-database-backup-with-a-very-long-filename-20261104.tar.gz':{job:1044,status:'排队中',primary:null,cancel:true},
 'config.production.json':{job:1045,status:'已暂停',primary:'resume_transfer',cancel:true},
 'db-backup.sql.gz':{job:1046,status:'传输失败',primary:'retry',cancel:false,error:'连接中断'},
 'checksums.txt':{job:1047,status:'已完成',primary:null,cancel:false},   // finished upload: no local reveal
 'healthcheck.txt':{job:1048,status:'已完成',primary:'reveal',cancel:false},
 'release-second-session.tar.gz':{job:1049,status:'排队中',primary:null,cancel:true},
};
const LONG_NAME='production-database-backup-with-a-very-long-filename-20261104.tar.gz';
const FIRST_LOCAL='/private/var/folders/zz/000000000000000000000000000000/T/zerowork-native-transfer-fixture-long-directory/local/release.tar.gz';

// ---- helpers ----
const shown=(n:any)=>n?.rect?.w>0&&n.rect.h>0&&n.hidden!==true&&n.visible!==false&&(n.effective_opacity??1)>0;
const flat=(n:any):any[]=>!n?[]:[n,...(n.children??[]).flatMap(flat)];
const textOf=(n:any):string=>flat(n).filter(shown).map(x=>typeof x.text==='string'?x.text:'').join('');
const right=(r:any)=>r.x+r.w,bottom=(r:any)=>r.y+r.h;
const inside=(a:any,b:any,e=EPS)=>a.x>=b.x-e&&a.y>=b.y-e&&right(a)<=right(b)+e&&bottom(a)<=bottom(b)+e;
const near=(a:number,b:number,e=EPS)=>Math.abs(a-b)<=e;
const all=async(id:string)=>(await query(id)).filter(shown);
const visible=(id:string,ms=10000)=>waitFor(async()=>(await query(id)).find(shown)??null,ms);
const gone=(id:string,ms=10000)=>waitFor(async()=>!(await query(id)).some(shown)||null,ms);
const part=(row:any,id:string)=>flat(row).find(n=>n.test_id===id&&shown(n));
/** The condition has to hold for the whole window (a negative check needs a dwell, not a single sample). */
const stays=async(what:string,cond:()=>Promise<boolean>,ms:number)=>{const t=Date.now();do{assert(await cond(),what);await sleep(50);}while(Date.now()-t<ms);};
const clickNode=async(n:any)=>{assert(shown(n),'click target is shown');assert((await clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok);};
const click=async(id:string)=>clickNode(await visible(id));
const managerShown=async()=>(await query('transfer.manager')).some(shown);
/** A click on a control of the panel: the panel is not "outside" of itself, it must stay open. */
const clickInPanel=async(n:any,what:string)=>{await clickNode(n);await stays(`The transfer panel stays open after a click on ${what}`,managerShown,300);};
const logText=()=>readFile(logPath,'utf8');
const logCount=async(line:string)=>(await logText()).split('\n').filter(l=>l.trim()===line).length;
/** Rows settle after a resize / state change: two identical consecutive samples. */
const rows=async()=>waitFor(async()=>{const a=JSON.stringify((await all('transfer.task')).map(r=>r.rect));await sleep(60);const b=await all('transfer.task');return b.length>0&&JSON.stringify(b.map(r=>r.rect))===a?b:null;},10000);
const rowNamed=async(name:string)=>waitFor(async()=>(await rows()).find(r=>part(r,'transfer.task.name')?.text===name)??null,10000);
const UNIT:Record<string,number>={B:1,KiB:1024,MiB:1024**2,GiB:1024**3,TiB:1024**4};
const bytes=(s:string)=>{const m=/^([\d.]+) (B|KiB|MiB|GiB|TiB)$/.exec(s.trim());assert(m,'IEC byte text: '+s);return Number(m[1])*UNIT[m[2]];};

const report:any={mode,theme,binary,sha256:createHash('sha256').update(await readFile(binary)).digest('hex'),pid:app.pid,isolated:iso,network:false,captures:[],checks:[]};

/** Geometry and content of every mounted row; `window` is the logical window size. */
async function checkRows(window:[number,number]){
 const manager=(await visible('transfer.manager')).rect,list=await rows();
 assert(manager.x>=-EPS&&right(manager)<=window[0]+EPS,'The panel is horizontally inside the window');
 let previous:any=null;
 const columns:{owner:number[],status:number[],track:number[],actions:number[]}={owner:[],status:[],track:[],actions:[]};
 const sizes=new Set<string>();
 for(const row of list){
  const r=row.rect,name=part(row,'transfer.task.name');assert(name,'Row has a file name');
  const expect=EXPECT[name.text];assert(expect,'Known fixture task: '+name.text);
  // one row height for every state, rows touch and share the column
  assert.equal(r.h,ROW_H,`Row height (${name.text})`);
  if(previous){assert(near(r.y,bottom(previous)),`Rows are contiguous at pitch ${ROW_H} (${name.text})`);assert(near(r.x,previous.x)&&near(r.w,previous.w),'Rows share one column');}
  previous=r;
  assert(r.x>=manager.x-EPS&&right(r)<=right(manager)+EPS,'Row is horizontally inside the panel');
  for(const id of ['transfer.task.file','transfer.task.icon','transfer.task.head','transfer.task.meta','transfer.task.progress','transfer.task.actions','transfer.task.name','transfer.task.bytes','transfer.task.status']){const n=part(row,id);assert(n,`${id} is shown (${name.text})`);assert(inside(n.rect,r),`${id} stays inside its row (${name.text})`);}
  const file=part(row,'transfer.task.file').rect,icon=part(row,'transfer.task.icon').rect,head=part(row,'transfer.task.head').rect,meta=part(row,'transfer.task.meta').rect,track=part(row,'transfer.task.progress'),actions=part(row,'transfer.task.actions');
  // name line / meta line / progress stack without overlap, in one column right of the icon
  assert.equal(head.h,NAME_LINE);assert.equal(meta.h,META_LINE);assert.equal(track.rect.h,TRACK_H);
  assert(bottom(head)<=meta.y+EPS&&bottom(meta)<=track.rect.y+EPS,'Name, meta and progress do not overlap');
  assert(near(head.x,meta.x)&&near(meta.x,track.rect.x)&&near(right(head),right(meta))&&near(right(meta),right(track.rect)),'Name, meta and progress share both edges');
  assert(right(icon)<=head.x+EPS,'Icon is left of the text column');assert(near(icon.y+icon.h/2,r.y+r.h/2),'Icon is vertically centred in the row');
  assert(near(right(file),right(track.rect)),'Progress ends with the file cell');
  // texts of one line do not overlap; fit labels below their cap are not ellipsized
  const owner=part(row,'transfer.task.owner'),bytesNode=part(row,'transfer.task.bytes'),status=part(row,'transfer.task.status'),rate=part(row,'transfer.task.rate'),error=part(row,'transfer.task.error');
  if(mode==='fixture'){assert(owner,'The global popover shows the owning session');assert(right(name.rect)<=owner.rect.x+EPS,'Name does not run into the owner');assert(near(right(owner.rect),right(head)),'Owner is right aligned in the name line');columns.owner.push(owner.rect.w);}
  else assert(!owner,'Session presentations do not repeat the owner');
  const middle=error??rate;
  if(middle){assert(inside(middle.rect,r));assert(right(bytesNode.rect)<=middle.rect.x+EPS&&right(middle.rect)<=status.rect.x+EPS,'Bytes, rate and status do not overlap');assert(middle.rect.w<RATE_MAX,`Rate / detail text is not cut (${middle.text})`);}
  else assert(right(bytesNode.rect)<=status.rect.x+EPS,'Bytes and status do not overlap');
  assert(status.rect.w<STATUS_MAX,`Status text is not cut (${status.text})`);assert(near(right(status.rect),right(meta)),'Status is right aligned in the meta line');
  if(expect.error){assert.equal(error?.text,expect.error,'A failed task shows its reason');}else assert(!error,'Only failed tasks show an error text');
  // state, bytes and bar agree
  const m=/^(.+) (\d+)%$/.exec(status.text);assert(m,'Status reads "<phase> <n>%": '+status.text);
  assert.equal(m[1],expect.status,`Phase label (${name.text})`);
  const percent=Number(m[2]),fill=(track.children??[]).find(shown),fraction=fill?fill.rect.w/track.rect.w:0;
  if(fill)assert(near(fill.rect.x,track.rect.x)&&fill.rect.h===TRACK_H&&right(fill.rect)<=right(track.rect)+EPS,'The fill starts with and stays inside the track');
  assert(Math.abs(fraction*100-percent)<=0.6,`Bar matches the percentage (${name.text}: ${(fraction*100).toFixed(2)} vs ${percent})`);
  const b=/^(.+?) \/ (.+?)(?: · 约 .+)?$/.exec(bytesNode.text);assert(b,'Bytes read "<done> / <total>": '+bytesNode.text);
  // both numbers are printed with one decimal at most, hence 1.5 points of slack
  const total=bytes(b[2]);assert(total>0);assert(Math.abs(bytes(b[1])/total*100-percent)<=1.5,`Bytes match the percentage (${bytesNode.text} vs ${percent}%)`);
  if(expect.status==='传输中')assert(/ · 约 /.test(bytesNode.text)&&/\/s$/.test(rate?.text??''),'A running task shows remaining time and rate');
  if(expect.status==='已完成')assert.equal(percent,100);
  // direct actions: one right aligned cell, equal buttons in a row, never outside the row
  assert(near(actions.rect.y+actions.rect.h/2,r.y+r.h/2),'Actions are vertically centred in the row');
  assert(right(file)<=actions.rect.x+EPS,'Actions do not overlap the file cell');
  columns.status.push(right(status.rect));columns.track.push(right(track.rect));columns.actions.push(actions.rect.x,right(actions.rect));
  const buttons=['transfer.task.primary','transfer.task.copy_path','transfer.task.events','transfer.task.cancel'].map(id=>part(row,id)).filter(Boolean);
  assert.equal(Boolean(part(row,'transfer.task.primary')),expect.primary!==null,`Primary action presence (${name.text})`);
  assert.equal(Boolean(part(row,'transfer.task.cancel')),expect.cancel,`Cancel presence (${name.text})`);
  assert(part(row,'transfer.task.copy_path')&&part(row,'transfer.task.events'),'Copy path and events are always offered');
  for(const [i,button] of buttons.entries()){
   assert(inside(button.rect,actions.rect),`Action button ${button.test_id} stays inside the actions cell (${name.text}): ${JSON.stringify({button:button.rect,cell:actions.rect})}`);assert(near(button.rect.w,button.rect.h),'Action buttons are square');sizes.add(`${button.rect.w}x${button.rect.h}`);
   assert(near(button.rect.y,buttons[0].rect.y),'Action buttons share one line');
   if(i>0)assert(button.rect.x>=right(buttons[i-1].rect)-EPS,'Action buttons do not overlap');
  }
  assert(near(right(buttons.at(-1).rect),right(actions.rect)),'Actions are right aligned');
  assert(!part(row,'transfer.task.select'),'No checkbox outside task management');
 }
 assert.equal(sizes.size,1,'Every action button has the same size: '+[...sizes].join(' '));
 for(const [column,values] of Object.entries(columns))for(let i=column==='actions'?2:1;i<values.length;i++)assert(near(values[i],values[i-(column==='actions'?2:1)]),'Shared column across rows: '+column);
 return list;
}

try {
 await waitForServerReady();assert.equal(Number(JSON.parse(await readFile(join(rpc,'owner.json'),'utf8')).pid),app.pid);
 if(mode==='main'){
  // Real application, no tasks: entry, empty state and the ways out.
  await resizeWindow(1440,900);await click('toolbar.transfers');
  const manager=await visible('transfer.manager');assert(inside(manager.rect,{x:0,y:0,w:1440,h:900}),'The popover is inside the window');
  // Native Popover anchored to its title bar trigger (transfer_manager_view.zig mountProjection: bottom_end, offset 8, viewport_padding 12).
  // The open transition slides it in, so wait (time bounded) for the settled placement.
  {const trigger=(await visible('toolbar.transfers')).rect;const placed=await waitFor(async()=>{const m=(await query('transfer.manager')).find(shown);return m&&near(m.rect.y,bottom(trigger)+8)?m:null;},3000);
   assert(near(right(placed.rect),Math.min(right(trigger),1440-12)),'The popover is end-aligned to its trigger inside the 12pt viewport padding');}
  assert.equal((await visible('transfer.empty.title')).text,'没有传输任务');assert(!(await query('transfer.task')).some(shown));
  assert((await screenshot(join(out,'main-empty.png'))).ok);report.captures.push({name:'main-empty',manager:manager.rect});
  report.checks.push('Title bar entry opens the empty transfer popover inside the window');
 } else {
  for(const window of [[860,480],[1440,900]] as [number,number][]){
   await resizeWindow(...window);const card=await visible('transfer.manager');
   // global_popover without a trigger: the Popover anchors to popoverAnchor()'s fallback point (viewport width − 12, 38), bottom_end with
   // offset 8 ⇒ the panel's right edge is 12 from the window edge and its top is at 46 (transfer_manager_view.zig).
   if(mode==='fixture')await waitFor(async()=>{const m=(await query('transfer.manager')).find(shown);return m&&near(right(m.rect),window[0]-12)&&near(m.rect.y,46)||null;},3000).catch(async()=>assert.fail('The global popover is anchored at the window top-right fallback point: '+JSON.stringify((await query('transfer.manager')).find(shown)?.rect)));
   const list=await checkRows(window);
   await writeFile(join(out,`${window[0]}.json`),JSON.stringify(await query('transfer.manager'),null,2));assert((await screenshot(join(out,`${window[0]}.png`))).ok);
   report.captures.push({window,card:card.rect,rows:list.length});
   if(mode==='tray'){const first=list[0],progress=part(first,'transfer.task.progress');assert(inside(first.rect,card.rect),'First tray row fully fits');assert(bottom(progress.rect)<=bottom(card.rect)+EPS,'Tray progress fully fits');}
  }
  report.checks.push(`${ROW_H}px rows at one pitch in every state, aligned columns, texts not cut, bar = percentage = bytes, direct right aligned actions`);
  assert(!(await query('transfer.task.more')).some(shown),'No overflow menu: actions are direct');
  assert(!(await query('transfer.task.detail')).some(shown),'No inline expansion by default');
  if(mode==='session')assert(!(await query('transfer.scope.select')).some(shown),'The session popover has no scope picker');

  // ---- counts (global popover: all eight tasks) ----
  if(mode==='fixture'){
   assert.equal((await visible('transfer.header.count')).text,`${Object.keys(EXPECT).length} 条`);
   const badges=flat(await visible('transfer.states.toolbar')).filter(n=>shown(n)&&typeof n.text==='string'&&/^\S+ \d+$/.test(n.text)).map(n=>n.text);
   assert.deepEqual(badges,['进行中 2','等待 2','暂停 1','失败 1','结束 2']);   // running×2, queued×2, paused, failed, succeeded×2
   assert.equal((await rows()).length,8,'All eight rows are mounted at 1440×900');
   assert((await visible('transfer.scope.select')).rect.w>0);
   report.checks.push('Header count and state counts match the eight frozen tasks');
  }

  // ---- task management: opt-in checkboxes, anchor unchanged ----
  const before=(await visible('transfer.manager')).rect,plain=await rows(),actionsRight=right(part(plain[0],'transfer.task.actions').rect);
  await clickInPanel(await visible('transfer.batch'),'管理任务');
  const managed=await waitFor(async()=>{const list=await rows();return list.every(r=>part(r,'transfer.task.select'))?list:null;},5000);
  const boxes=managed.map(r=>part(r,'transfer.task.select').rect);
  for(const [i,row] of managed.entries()){
   const box=boxes[i],file=part(row,'transfer.task.file').rect;
   assert.equal(row.rect.h,ROW_H,'Row height is unchanged while managing');
   assert(inside(box,row.rect)&&near(box.w,box.h)&&near(box.w,boxes[0].w)&&near(box.x,boxes[0].x),'Checkboxes are square, equal and in one column');
   assert(near(box.y+box.h/2,row.rect.y+row.rect.h/2),'Checkbox is vertically centred');assert(right(box)<=file.x+EPS,'Checkbox does not overlap the file cell');
   assert(near(right(part(row,'transfer.task.actions').rect),actionsRight),'Actions keep their right edge while managing');
   const name=part(row,'transfer.task.name'),status=part(row,'transfer.task.status');assert(name.rect.w>0&&status.rect.w<STATUS_MAX,'Name and status remain readable while managing');
  }
  for(const id of ['transfer.batch.pause','transfer.batch.resume','transfer.batch.cancel'])await visible(id);
  const selectedLabel=async(n:number)=>waitFor(async()=>textOf((await query('transfer.manager')).find(shown)).includes(`已选择 ${n} 项`)||null,5000);
  await selectedLabel(0);
  await clickInPanel(part((await rows())[0],'transfer.task.select'),'a task checkbox');await selectedLabel(1);
  assert((await screenshot(join(out,'selected.png'))).ok);
  if(mode!=='main'){const n=await logCount('TRANSFER_CONTROLS_FIXTURE batch=pause count=1');await clickInPanel(await visible('transfer.batch.pause'),'暂停所选任务');await waitFor(async()=>(await logCount('TRANSFER_CONTROLS_FIXTURE batch=pause count=1'))===n+1||null,5000);}
  await clickInPanel(await visible('transfer.batch'),'完成管理');
  await gone('transfer.task.select');await gone('transfer.batch.pause');
  const after=(await visible('transfer.manager')).rect;assert.equal(before.x,after.x);assert.equal(before.y,after.y);
  await clickInPanel(await visible('transfer.batch'),'管理任务');await selectedLabel(0);   // leaving management clears the selection
  await clickInPanel(await visible('transfer.batch'),'完成管理');await gone('transfer.task.select');
  report.checks.push('Checkboxes only while managing; selection count, batch action and anchor are correct; leaving clears the selection');

  // ---- details: click Popover on the file name ----
  const windowRect={x:0,y:0,w:1440,h:900};
  const first=await rowNamed('release.tar.gz'),name=part(first,'transfer.task.name');
  await mouseMove(name.rect.x+20,name.rect.y+name.rect.h/2);
  await stays('Hover does not open details',async()=>!(await query('transfer.task.detail_popup')).some(shown),650);
  await clickInPanel(name,'a file name');
  const detail=await visible('transfer.task.detail_popup');
  assert(detail.rect.w<=DETAIL_W+0.5&&inside(detail.rect,windowRect),'Details are at most 420 wide and inside the window');
  const field=async(id:string)=>{const n=await visible(id);assert(inside(n.rect,(await visible('transfer.task.detail_popup')).rect),'Detail field stays inside the popup: '+id);return n;};
  assert.equal((await field('transfer.detail.identity')).text,'任务 #1042 · K8s-Node01 #101');
  assert.equal((await field('transfer.detail.name')).text,'release.tar.gz');
  const local=await field('transfer.detail.local');assert.equal(local.text,FIRST_LOCAL,'The complete local path is shown');assert(local.rect.h>16+EPS,'The long local path wraps instead of being cut');
  assert.equal((await field('transfer.detail.remote')).text,'/srv/releases/release.tar.gz');
  assert.deepEqual(flat(await field('transfer.detail.options')).filter(n=>shown(n)&&typeof n.text==='string'&&n.text).map(n=>n.text),['断点续传 开','MD5 关']);
  // copy buttons write the system clipboard: presence and placement only
  const copies=[await field('transfer.detail.copy_local'),await field('transfer.detail.copy_remote')];
  assert(near(copies[0].rect.w,copies[1].rect.w)&&near(copies[0].rect.h,copies[1].rect.h)&&near(right(copies[0].rect),right(copies[1].rect)),'Detail copy buttons are equal and share a column');
  await mouseMove(local.rect.x+20,local.rect.y+local.rect.h/2);
  await stays('Details stay while the pointer is over them',async()=>(await query('transfer.task.detail_popup')).some(shown),350);
  assert((await screenshot(join(out,'detail.png'))).ok);
  await mouseMove(5,5);
  await stays('Details stay after the pointer leaves',async()=>(await query('transfer.task.detail_popup')).some(shown),350);
  await key('escape');await gone('transfer.task.detail_popup',3000);
  await stays('Escape closes the details only, the panel stays',managerShown,300);
  report.checks.push('Details open on file name click only, show complete wrapped values, persist after the pointer leaves, close on Escape');
  // the long file name is ellipsized in its row and complete in the details
  const long=await rowNamed(LONG_NAME);await clickInPanel(part(long,'transfer.task.name'),'the long file name');
  const longName=await field('transfer.detail.name');assert.equal(longName.text,LONG_NAME,'The details show the complete file name');   // detailLabel: wrap = .word, never ellipsized
  const header=await visible('transfer.header.title');await clickInPanel(header,'the panel header');await gone('transfer.task.detail_popup',3000);
  report.checks.push('A click elsewhere in the panel closes the details and keeps the panel');

  // ---- direct actions reach the host with the task they belong to ----
  for(const [task,expect] of Object.entries(EXPECT)){
   const present=(await rows()).find(r=>part(r,'transfer.task.name')?.text===task);if(!present){assert(mode!=='fixture','Every task is listed in the global popover: '+task);continue;}
   for(const [id,action] of [['transfer.task.primary',expect.primary],['transfer.task.cancel',expect.cancel?'cancel':null]] as [string,string|null][]){
    if(!action)continue;
    const line=`TRANSFER_CONTROLS_FIXTURE action=${action} job=${expect.job}`,n=await logCount(line);
    await clickInPanel(part(await rowNamed(task),id),`${id} of ${task}`);
    await waitFor(async()=>(await logCount(line))===n+1||null,5000);
   }
  }
  const actionLines=(await logText()).split('\n').filter(l=>l.startsWith('TRANSFER_CONTROLS_FIXTURE action='));
  assert.equal(new Set(actionLines).size,actionLines.length,'Each click produced exactly one action for its own task');
  await checkRows([1440,900]);   // the frozen list is unchanged by the requests
  report.checks.push('Pause / resume / retry / reveal / cancel are offered by phase and reach the host once with the right job: '+actionLines.length);

  // ---- short window: the list scrolls to the last task ----
  await resizeWindow(860,480);await rows();
  const top=(await rows())[0],lastName=mode==='fixture'?'release-second-session.tar.gz':null;
  if(lastName){
   await scrollAt(top.rect.x+top.rect.w/2,top.rect.y+35,0,-600);
   const last=await rowNamed(lastName),card=(await visible('transfer.manager')).rect;
   assert(bottom(last.rect)<=Math.min(bottom(card),480)+EPS,'The last task is fully visible after scrolling');assert.equal(last.rect.h,ROW_H);
   assert((await screenshot(join(out,'scrolled.png'))).ok);report.checks.push('The list scrolls to the last task in a 480 high window');
  }
  await resizeWindow(1440,900);await rows();
 }

 // ---- closing ----
 if(mode!=='tray'){
  const reopen=mode==='main'?'toolbar.transfers':'transfer.preview.reopen';
  await click('transfer.window.close');await gone('transfer.manager');assert.equal(app.exitCode,null);
  report.checks.push('X hides the panel while the owning process stays alive');assert((await screenshot(join(out,'closed.png'))).ok);
  await click(reopen);await visible('transfer.manager');await click('transfer.window.close');await gone('transfer.manager');
  report.checks.push('Reopen and second X also hide the panel');
  if(mode!=='session'){
   // title-click (d6c927e3): the title bar presentation is a native Popover, Escape and an outside click close it like X.
   await click(reopen);await visible('transfer.manager');await key('escape');await gone('transfer.manager');
   await click(reopen);const card=(await visible('transfer.manager')).rect;
   // The outside point must be inert: in the main window the bottom-left corner holds the sidebar's “添加主机” (sidebar.empty.new),
   // so use the inner bottom-left corner of the empty workspace island; the preview has nothing in its window corners.
   let candidates=[{x:20,y:880},{x:1420,y:880}];
   if(mode==='main'){const pane=(await visible('workspace.pane')).rect;candidates=[{x:pane.x+24,y:bottom(pane)-24}];}
   const outside=candidates.find(p=>!(p.x>=card.x&&p.x<=right(card)&&p.y>=card.y&&p.y<=bottom(card)));
   assert(outside,'An inert point outside the panel');
   assert((await clickAt(outside.x,outside.y)).ok);await gone('transfer.manager');assert.equal(app.exitCode,null);
   await click(reopen);await visible('transfer.manager');
   report.checks.push('Escape and an outside click close the popover; it reopens afterwards');
  }
 }
 report.status='passed';
} catch(e){report.status='failed';report.error=String(e);report.error_stack=(e as Error).stack;process.exitCode=1;try{await screenshot(join(out,'failure.png'));}catch{}}
finally {if(app.exitCode===null)app.kill('SIGTERM');await end;await log.close();await writeFile(join(out,'report.json'),JSON.stringify(report,null,2));console.log(JSON.stringify({status:report.status,mode,theme,error:report.error}));}
