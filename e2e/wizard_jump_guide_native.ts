/** design-r3 稿 4 · 跳板引导：真实应用（test-mode），隔离数据目录里没有任何已保存主机。
 * 第 2 步点“经 SSH 跳板连接”→ 空态（新建跳板主机 / 改为直连，“下一步”禁用并写明原因）→ 新建跳板主机子流程
 * （标题“新建连接 › 新建跳板主机”，只问名称、地址、端口、用户名、认证方式）→ 保存后回到第 2 步，新主机成为第 1 跳并弹右下角通知。
 * 只做离线保存，不建立任何连接。
 * node e2e/wizard_jump_guide_native.ts [binary] [output] [theme]
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdir,mkdtemp,open,readFile,writeFile,rm,realpath} from 'node:fs/promises';
import {join,resolve,dirname} from 'node:path';
import {tmpdir} from 'node:os';
const binary=resolve(process.argv[2]??'zig-out/bin/zerowork'),out=resolve(process.argv[3]??'/tmp/zw-wizard-jump-guide'),theme=process.argv[4]??'light';
assert(['dark','light','sauber'].includes(theme));
await mkdir(out,{recursive:true});
const h=await import(join(dirname(dirname(binary)),'share/zenit/harness/client.ts'));
const isolated=await realpath(await mkdtemp(join(tmpdir(),'zw-wizard-jump-'))),data=join(isolated,'data'),rpc=join(isolated,'rpc');
await mkdir(data);await mkdir(rpc);
await writeFile(join(data,'config.toml'),`[meta]\nconfig_revision=1\n[ui]\ntheme="${theme}"\n[updates]\nauto_check=false\n`);
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const log=await open(join(out,`app-${theme}.log`),'w');
const child=spawn(binary,[],{env:{...process.env,ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',ZENIT_E2E_FILE_RPC_DIR:rpc,ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1'},stdio:['ignore',log.fd,log.fd]});
const ended=new Promise<void>(r=>child.once('close',()=>r()));
const report:any={status:'running',theme,checks:[],captures:[],limits:['Synthetic Harness input, not physical keyboard/IME verification','Offline save only; no connection test or remote action']};
const shown=(n:any)=>n.visible!==false&&n.hidden!==true&&(n.effective_opacity??1)>0&&n.rect?.w>0&&n.rect?.h>0;
const flatten=(n:any):any[]=>[n,...(n.children??[]).flatMap(flatten)];
const text=(n:any)=>flatten(n).map(x=>x.text??'').join(' ');
const current=async(id:string)=>(await h.query(id)).find(shown)??null;
const visible=(id:string)=>h.waitFor(()=>current(id),10000);
const gone=(id:string)=>h.waitFor(async()=>!(await current(id))||null,10000);
async function click(id:string){let prior='';let repeats=0;const n=await h.waitFor(async()=>{const n=await current(id);if(!n)return null;const at=JSON.stringify(n.rect);repeats=at===prior?repeats+1:0;prior=at;await h.sleep(80);return repeats>=2?n:null;},10000);assert((await h.clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok,id);await h.sleep(150);}
async function fill(id:string,value:string){await click(id);await h.key('a',{cmd:true});await h.type_(value);await h.waitFor(async()=>{const n=await current(id);return n&&text(n).includes(value)?true:null},10000);}
async function capture(name:string){await h.mouseMove(4,4);await h.sleep(500);const file=`${name}-${theme}`;assert((await h.screenshot(join(out,file+'.png'))).ok);report.captures.push(file);}
try{
 await h.waitForServerReady(30000);await h.resizeWindow(1440,900);
 await click((await current('sidebar.empty.new'))?'sidebar.empty.new':'sidebar.footer.new');
 await fill('wizard.name','prod-web-02');await fill('wizard.host','10.0.1.24');await fill('wizard.user','root');
 await click('wizard.next.identity');
 await click('wizard.access.jump');
 const empty=await visible('wizard.route.jump_empty');
 assert.match(text(empty),/还没有可以作跳板的主机/);
 await visible('wizard.route.jump_empty.new');await visible('wizard.route.jump_empty.direct');
 assert.equal(text(await visible('wizard.footer.hint')).trim(),'至少需要 1 个跳板才能继续');
 await capture('01-jump-empty');
 // 下一步 is disabled: clicking it keeps the route step and its empty state.
 const next=await visible('wizard.next.route');assert((await h.clickAt(next.rect.x+next.rect.w/2,next.rect.y+next.rect.h/2)).ok);await h.sleep(400);
 await visible('wizard.route.jump_empty');assert(!(await current('wizard.review.summary')),'still on step 2');report.checks.push('跳板 always reacts: empty state, two actions, next disabled with the reason');
 await click('wizard.route.jump_empty.direct');await gone('wizard.route.jump_empty');
 assert.equal(text(await visible('wizard.footer.hint')).trim(),'下一步：核对与测试');
 await click('wizard.access.jump');await visible('wizard.route.jump_empty');
 report.checks.push('改为直连 leaves the empty state and unblocks the step');
 await click('wizard.route.jump_empty.new');
 const banner=await visible('wizard.jump_child.banner');
 assert.match(text(banner),/保存后会自动作为 prod-web-02 的第 1 跳/);
 await visible('wizard.jump_child.footer');
 assert(!(await current('wizard.group')),'child hides the group field');
 await fill('wizard.name','bastion-01');await fill('wizard.host','b1.example.com');await fill('wizard.user','admin');
 await capture('02-jump-child');
 await click('wizard.jump_child.save');await gone('wizard.jump_child.banner');
 const hop=await visible('wizard.route.hop.0');assert.match(text(hop),/bastion-01/);
 assert(!(await current('wizard.route.jump_empty')),'empty state left');
 assert.equal(text(await visible('wizard.footer.hint')).trim(),'下一步：核对与测试');
 const toast=await h.waitFor(async()=>(await h.query('wizard.route.jump_toasts')).find((n:any)=>text(n).includes('已保存 bastion-01'))??null,10000);
 assert.match(text(toast),/已作为第 1 跳加入/);
 await capture('03-jump-saved');
 const hosts=await readFile(join(data,'hosts.toml'),'utf8');assert.match(hosts,/name = "bastion-01"|name="bastion-01"/);assert(!/prod-web-02/.test(hosts),'parent draft is not saved by the child');
 report.checks.push('child saves only the jump host, returns to step 2 with it as hop 1 and a bottom-right notification');
 await click('wizard.cancel');
 report.status='passed';
}catch(e){report.status='failed';report.error=String(e);process.exitCode=1;await h.screenshot(join(out,`failure-${theme}.png`)).catch(()=>{});}
finally{await writeFile(join(out,`report-${theme}.json`),JSON.stringify(report,null,2));child.kill('SIGTERM');await Promise.race([ended,new Promise(r=>setTimeout(r,5000))]);await log.close();await rm(isolated,{recursive:true,force:true});}
console.log(JSON.stringify(report));
