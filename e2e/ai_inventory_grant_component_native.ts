/** Production on-demand inventory approval; fabricated requests, no host IO.
 *
 * Current contract (src/features/ai/approvals/view/ai_inventory_grant_view.zig + ai_inventory_grant_styles.zig):
 * - The approval card (approval.panel: padding 11) carries a 16 px icon centred on the title row, the target, the
 *   explanation, the duration hint, an optional feedback line, then an end-aligned actions row (approval.footer: gap 6,
 *   min height 26.5) of three native zenit sm Buttons — 拒绝 (secondary) · 仅此一次 (primary) · 持续允许 (secondary).
 *   Native sm buttons are 24 high (vendor/zenit/src/ui/components/control_shell/styles.yss SizeRecipe sm: 4.2 + 13×1.2 + 4.2);
 *   the old hand-made 26.5 / ≥76 px buttons are gone (native buttons: 7065c2eb, 672a9a90).
 * - Disabled is the native disabled tone (control_shell/styles.yss `:disabled`: disabled-bg, fg-disabled) and the
 *   buttons leave the focus order (button.yix `focusable = !disabled`); a press dispatches nothing.
 * - Revoke lives in the composer's 执行权限 menu, a native Menu (372c5a87): item 撤销会话列表授权 (danger) inside the
 *   menu panel; with the composer not editable, 确认后执行 / 自动执行 are not focusable.
 * Usage: node e2e/ai_inventory_grant_component_native.ts <inventory-grant-preview> <out> <theme>
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdtemp,mkdir,writeFile,readFile,open} from 'node:fs/promises';
import {join,resolve} from 'node:path';
import * as h from '../zig-out/share/zenit/harness/client.ts';
const binary=resolve(process.argv[2]??'zig-out/bin/inventory-grant-preview');
const out=resolve(process.argv[3]??'/tmp/zw-inventory-ondemand-ui/native');await mkdir(out,{recursive:true});
const theme=process.argv[4]??'dark';assert(['light','dark'].includes(theme),`theme must be light or dark, got ${theme}`);
const report:any={status:'running',binary,theme,checks:[],measurements:[],shutdown:[],limitations:['Isolated production view and approval broker, fabricated requests only. Workspace/provider integration is validated separately.']};
const shown=(n:any)=>n&&n.visible!==false&&n.hidden!==true&&(n.effective_opacity??1)>0&&n.rect?.w>0&&n.rect?.h>0;
const text=(n:any):string=>n.text??(n.children??[]).map(text).join('');
const visible=(id:string)=>h.waitFor(async()=>(await h.query(id)).find(shown)??null,10000);
const absent=(id:string)=>h.waitFor(async()=>!(await h.query(id)).some(shown)||null,10000);
const result=async()=>text(await visible('inventory_grant.preview.result'));
const resultHas=(needle:string)=>h.waitFor(async()=>(await result()).includes(needle)||null,5000).catch(async()=>assert.fail(`result lacks ${JSON.stringify(needle)}: ${await result()}`));
const click=async(id:string)=>assert((await h.clickTestId(id)).ok,id);
const save=()=>writeFile(join(out,'report.json'),JSON.stringify(report,null,2));
const near=(a:number,b:number,what:string,eps=0.5)=>assert(Math.abs(a-b)<=eps,`${what}: ${a} vs ${b}`);
const inside=(inner:any,outer:any,what:string)=>assert(inner.x>=outer.x-0.5&&inner.y>=outer.y-0.5&&inner.x+inner.w<=outer.x+outer.w+0.5&&inner.y+inner.h<=outer.y+outer.h+0.5,`${what} ${JSON.stringify(inner)} outside ${JSON.stringify(outer)}`);
/** The node once its geometry and paint stop changing (menu entrance / tone transitions), within a time limit. */
const stable=async(id:string,ms=3000)=>{let last='';return h.waitFor(async()=>{const n=(await h.query(id)).find(shown);const key=n&&JSON.stringify([n.rect,n.bg_rgba,n.focusable]);if(n&&key===last)return n;last=key??'';await h.sleep(80);return null},ms)};
const labelOf=(n:any):any=>n.text?n:(n.children??[]).map(labelOf).find(Boolean);
const CARD_PAD=11,ACTION_GAP=6,SM_HEIGHT=24,ICON=16,ACTIONS=['deny','allow_once','allow_conversation'],LABELS=['拒绝','仅此一次','持续允许'];
const runs=theme==='dark'?[[0,600],[0,320],[100,600]]:[[75,600],[75,320],[100,600]];
try{
for(const [transparency,width] of runs){
  const name=`${theme}-t${transparency}-${width}`,iso=await mkdtemp('/tmp/zw-inventory-ondemand-'),rpc=join(iso,'rpc'),data=join(iso,'data');await mkdir(rpc);await mkdir(data);process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
  const log=await open(join(out,`${name}.log`),'w');
  const child=spawn(binary,[`--theme=${theme}`,`--transparency=${transparency}`],{env:{...process.env,ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1',ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0'},stdio:['ignore',log.fd,log.fd]});
  const ended=new Promise<any>(done=>child.once('exit',(code,signal)=>done({code,signal})));
  try{
   await h.waitForServerReady(10000);assert.equal(Number(JSON.parse(await readFile(join(rpc,'owner.json'),'utf8')).pid),child.pid);
   await h.resizeWindow(width,420);await h.waitFor(async()=>Math.abs((await visible('inventory_grant.preview')).rect.w-width)<0.5||null,5000);
   await absent('ai.inventory_grant');assert.equal(await result(),'尚无读取请求');
   assert((await h.screenshot(join(out,`${name}-idle.png`))).ok);
   await click('inventory_grant.preview.request');
   const card=await visible('ai.inventory_grant'),title=await visible('ai.inventory_grant.title'),icon=await visible('ai.inventory_grant.icon'),copy=await visible('ai.inventory_grant.explanation'),target=await visible('ai.inventory_grant.target'),hint=await visible('ai.inventory_grant.hint'),actions=await visible('ai.inventory_grant.actions');
   assert(Math.abs(icon.rect.y+icon.rect.h/2-title.rect.y-title.rect.h/2)<.5,'icon centred on the title');assert.equal(icon.rect.w,ICON);assert.equal(icon.rect.h,ICON);assert(icon.rect.x+icon.rect.w<title.rect.x,'icon before title');
   assert.equal(text(title),'查看其他会话');assert(text(copy).includes('名称、连接状态与分组'));assert(text(copy).includes('不会读取终端内容或执行命令'));assert(text(hint).includes('持续允许仅当前对话'));
   assert(!(await h.query('ai.inventory_grant.feedback')).some(shown),'no feedback line before a failure');
   // Card content inset 11 on both sides; copy stacked header → target → explanation → hint → actions, nothing overlapping.
   for(const [n,what] of [[target,'target'],[copy,'explanation'],[hint,'hint'],[actions,'actions']] as const){near(n.rect.x,card.rect.x+CARD_PAD,`${what} left inset`);near(n.rect.x+n.rect.w,card.rect.x+card.rect.w-CARD_PAD,`${what} right inset`)}
   const stack=[title,target,copy,hint,actions];for(let i=1;i<stack.length;i++)assert(stack[i-1].rect.y+stack[i-1].rect.h<=stack[i].rect.y+0.5,`stack order ${i}`);
   inside(actions.rect,card.rect,'actions row');
   const buttons:any[]=[];
   for(const [i,id] of ACTIONS.entries()){
    const node=await stable(`ai.inventory_grant.${id}`);assert.equal(node.component,'Button');assert.equal(text(node),LABELS[i]);
    near(node.rect.h,SM_HEIGHT,`${id} native sm height`,0.01);assert.equal(node.focusable,true,`${id} focusable while enabled`);
    inside(node.rect,actions.rect,id);inside(labelOf(node).rect,node.rect,`${id} label`);
    near(node.rect.y+node.rect.h/2,actions.rect.y+actions.rect.h/2,`${id} centred in the actions row`);
    assert.equal(node.effective_opacity??1,1);buttons.push({id,rect:node.rect,bg:node.bg_rgba});
   }
   for(let i=1;i<buttons.length;i++)near(buttons[i].rect.x-(buttons[i-1].rect.x+buttons[i-1].rect.w),ACTION_GAP,`gap ${buttons[i-1].id}→${buttons[i].id}`);
   near(buttons[2].rect.x+buttons[2].rect.w,actions.rect.x+actions.rect.w,'actions end-aligned (approval.footer justify end)');
   near(buttons[0].rect.y,buttons[1].rect.y,'one row',0.01);near(buttons[1].rect.y,buttons[2].rect.y,'one row',0.01);
   near(buttons[1].rect.w,buttons[2].rect.w,'equal-length labels → equal native widths',0.01);
   assert.notEqual(buttons[1].bg,buttons[0].bg,'仅此一次 is the primary tone, distinct from the secondary ones');assert.equal(buttons[0].bg,buttons[2].bg,'both secondary buttons share the tone');
   for(const node of [title,icon,copy,target,hint])assert.equal(node.effective_opacity??1,1);
   await h.mouseMove(1,1);assert((await h.screenshot(join(out,`${name}-pending.png`))).ok);
   await writeFile(join(out,`${name}-pending.json`),JSON.stringify(await h.query('inventory_grant.preview'),null,2));
   await click('ai.inventory_grant.deny');await absent('ai.inventory_grant');await resultHas('deny · decisions 1');await resultHas('stopped false');
   await click('inventory_grant.preview.request');await visible('ai.inventory_grant');await click('ai.inventory_grant.allow_once');await absent('ai.inventory_grant');await resultHas('allow_once · decisions 2');
   await click('inventory_grant.preview.request');await visible('ai.inventory_grant');await click('ai.inventory_grant.allow_conversation');await absent('ai.inventory_grant');await resultHas('allow_conversation · decisions 3');
   await click('inventory_grant.preview.request');await resultHas('当前对话已持续允许，无需再次审批');assert(!(await h.query('ai.inventory_grant')).some(shown),'no approval while continuously allowed');
   // Revoke through the composer's native permission menu.
   // Narrow composer rows collapse 执行权限 into a native icon-only button (ai_composer_controls_view.zig permission_compact).
   const chip=(await h.query('ai.composer.permission')).find(shown),compact=(await h.query('ai.composer.permission.compact')).find(shown);
   assert(Boolean(chip)!==Boolean(compact),'exactly one 执行权限 control is shown');report.measurements.push({width,permission_control:chip?'chip':'compact'});
   await click(chip?'ai.composer.permission':'ai.composer.permission.compact');const menu=await stable('ai.permission.menu'),revoke=await stable('ai.permission.revoke_inventory');
   assert.equal(text(revoke),'撤销会话列表授权');inside(revoke.rect,menu.rect,'revoke item');inside(menu.rect,{x:0,y:0,w:width,h:420},'permission menu');
   const confirm=await stable('ai.permission.confirm'),automatic=await stable('ai.permission.auto');
   for(const item of [confirm,automatic,revoke]){assert.equal(item.component,'MenuItem');inside(item.rect,menu.rect,item.test_id);near(item.rect.x,revoke.rect.x,'menu items share the left edge',0.01);near(item.rect.w,revoke.rect.w,'menu items share the width',0.01)}
   assert(confirm.rect.y+confirm.rect.h<=automatic.rect.y+0.5&&automatic.rect.y+automatic.rect.h<=revoke.rect.y+0.5,'permission modes above the revoke item');
   assert.equal(confirm.focusable??false,false);assert.equal(automatic.focusable??false,false);
   await h.mouseMove(1,1);assert((await h.screenshot(join(out,`${name}-revoke-menu.png`))).ok);await writeFile(join(out,`${name}-revoke-menu.json`),JSON.stringify(await h.query('ai.permission.menu'),null,2));
   await click('ai.permission.revoke_inventory');await absent('ai.permission.menu');assert.equal(await result(),'已撤销当前对话的持续允许');
   await click('inventory_grant.preview.request');await visible('ai.inventory_grant');
   // Native disabled: no dispatch, out of the focus order, the disabled tone, feedback line.
   const enabledOnce=await stable('ai.inventory_grant.allow_once');
   await click('inventory_grant.preview.disable');assert.equal(text(await visible('ai.inventory_grant.feedback')),'请求暂时不可用');
   const before=await result();
   for(const id of ACTIONS){const n=await h.waitFor(async()=>{const x=(await h.query(`ai.inventory_grant.${id}`)).find(shown);return x&&!x.focusable?x:null},3000);assert.equal(n.focusable??false,false,`${id} leaves the focus order`)}
   const disabled=await stable('ai.inventory_grant.allow_once');assert.notEqual(disabled.bg_rgba,enabledOnce.bg_rgba,'disabled primary leaves the primary tone (control_shell :disabled)');
   const disabledDeny=await stable('ai.inventory_grant.deny'),disabledConv=await stable('ai.inventory_grant.allow_conversation');
   assert.equal(disabled.bg_rgba,disabledDeny.bg_rgba,'all disabled buttons share disabled-bg');assert.equal(disabledConv.bg_rgba,disabledDeny.bg_rgba,'all disabled buttons share disabled-bg');
   await h.mouseDown(disabled.rect.x+disabled.rect.w/2,disabled.rect.y+disabled.rect.h/2);await h.mouseUp(disabled.rect.x+disabled.rect.w/2,disabled.rect.y+disabled.rect.h/2);
   await h.sleep(200);assert.equal(await result(),before,'a press on a disabled button dispatches nothing');
   await h.mouseMove(1,1);assert((await h.screenshot(join(out,`${name}-disabled.png`))).ok);
   await click('inventory_grant.preview.disable');await h.waitFor(async()=>(await h.query('ai.inventory_grant.allow_once')).find(shown)?.focusable||null,3000);
   assert(!(await h.query('ai.inventory_grant.feedback')).some(shown),'feedback clears when the request is available again');
   await click('inventory_grant.preview.expire');await click('ai.inventory_grant.allow_once');
   await h.waitFor(async()=>text((await h.query('ai.inventory_grant.feedback')).find(shown)??{})==='请求已失效，请等待新的请求'||null,5000);assert.equal(await result(),'本次请求已失效');
   for(const id of ACTIONS)assert.equal((await h.query(`ai.inventory_grant.${id}`)).find(shown).focusable??false,false,`${id} disabled after expiry`);
   await h.mouseMove(1,1);assert((await h.screenshot(join(out,`${name}-expired.png`))).ok);
   report.measurements.push({width,theme,transparency,card:card.rect,title:title.rect,icon:icon.rect,target:target.rect,copy:copy.rect,hint:hint.rect,actions:actions.rect,buttons,menu:menu.rect});
   report.checks.push(`${name}: absent before request; native sm actions (24 high, gap 6, end-aligned, primary distinct); deny/once/current-conversation; repeat request skips approval only after continuous choice; native menu revoke; native disabled (no dispatch, unfocusable, disabled-bg); stale safe feedback; inline icon/title; foreground opacity 1`);
  }finally{
   let method='POST /quit';try{await h.request('POST','/quit');await h.waitFor(async()=>child.exitCode!==null||child.signalCode!==null||null,10000)}catch{method='SIGTERM fallback';child.kill('SIGTERM')}
   const status=await ended;report.shutdown.push({name,method,...status});await log.close();await save();assert.equal(method,'POST /quit');assert.equal(status.code,0);assert.equal(status.signal,null);
  }
}
report.status='passed';await save();console.log(`PASS ${report.checks.length} on-demand inventory fixtures: ${out}`);
}catch(e){report.status='failed';report.error=String(e);await save();throw e}
