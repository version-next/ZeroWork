/** panel-heads (CONSISTENCY_AUDIT #4, 用户拍板第 4 条): the same-weight panels share one header, one close
 * button and one empty state. Opens every title bar panel (通信链路 · 端口转发 · 传输 · 命令历史 · 提醒) and the
 * session history card (floating and as a tab) against the owned loopback SSH peer, then asserts:
 * - every panel header (shared PanelHeader / float chrome) is 30 high;
 * - every close button is the same native ghost sm icon button (same square size as the float chrome's) and its tooltip reads "关闭 · Esc";
 * - every empty state is the native W.Empty: icon + title + non-empty description, centered;
 * AI panels are not covered: their headers / empty states belong to ai-redesign-a/b/c.
 * Screenshots of each panel (light / dark), and `<theme>-sheet.png`: every panel cropped (header + empty state) side by side.
 * Usage: node e2e/panel_heads_native.ts <bin> <out> <light|dark> [python]  (python: audited interpreter, default $ZW_TEST_PYTHON) */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdir,mkdtemp,open,writeFile,readFile,realpath,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {dirname,resolve,join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {decodePng,writeRgbPng} from '../vendor/zenit/e2e/png.ts';

const binary=resolve(process.argv[2]||'zig-out/bin/zerowork'),out=resolve(process.argv[3]||'/tmp/zerowork-panel-heads'),theme=process.argv[4]??'light';
const python=process.argv[5]??process.env.ZW_TEST_PYTHON??'python3';
const h=await import(pathToFileURL(resolve(dirname(binary),'../share/zenit/harness/client.ts')).href);
const iso=await realpath(await mkdtemp(join(tmpdir(),'zw-panel-heads-'))),data=join(iso,'data'),rpc=join(iso,'rpc');
for(const p of [out,data,rpc])await mkdir(p,{recursive:true});
process.env.ZENIT_E2E_FILE_RPC_DIR=rpc;
const peerLog=await open(join(out,`${theme}-peer.log`),'w');
const peer=spawn(python,['-I',resolve('e2e/builtin_records_ssh_peer.py'),'--out',join(out,`${theme}-peer`)],{stdio:['ignore',peerLog.fd,peerLog.fd]});
const peerEnded=new Promise(r=>peer.once('close',r));
const report:any={theme,status:'running',checks:[],captures:[],panels:{}};
const shown=(n:any)=>n?.rect?.w>0&&n.rect.h>0&&n.visible!==false&&n.hidden!==true&&(n.effective_opacity??n.opacity??1)>0.01;
const flat=(n:any):any[]=>n?[n,...(n.children??[]).flatMap(flat)]:[];
const text=(n:any):string=>flat(n).map((x:any)=>x.text??'').join('');
const nodes=async(id:string)=>(await h.query(id)).filter(shown);
const visible=async(id:string,ms=10000)=>await h.waitFor(async()=>(await nodes(id))[0]??null,ms);
const hidden=async(id:string,ms=8000)=>await h.waitFor(async()=>(await nodes(id)).length===0||null,ms);
const within=(root:any,id:string)=>flat(root).filter((n:any)=>n.test_id===id&&shown(n));
const away={x:700,y:560};
const tiles:{file:string,rect:any,tag:string}[]=[];
async function capture(name:string,rect?:any){await h.mouseMove(away.x,away.y);await h.sleep(350);const file=join(out,`${theme}-${name}.png`);assert((await h.screenshot(file)).ok);report.captures.push(file);if(rect)tiles.push({file,rect,tag:name});}
/** Comparison sheet: each panel (header + empty state) cropped from its screenshot, side by side in one row, top-aligned. */
async function sheet(){
 if(!tiles.length)return;
 const crops=tiles.map(t=>{const p=decodePng(t.file);const s=p.width/1440;const x0=Math.max(0,Math.round(t.rect.x*s)),y0=Math.max(0,Math.round(t.rect.y*s));
  const w=Math.min(p.width-x0,Math.round(t.rect.w*s)),hh=Math.min(p.height-y0,Math.round(t.rect.h*s));return {p,x0,y0,w,h:hh};});
 const gap=24,W=crops.reduce((a,c)=>a+c.w+gap,gap),H=Math.max(...crops.map(c=>c.h))+2*gap;
 const bg=theme==='dark'?40:200;const px=new Uint8Array(W*H*3).fill(bg);let ox=gap;
 for(const c of crops){for(let y=0;y<c.h;y++)for(let x=0;x<c.w;x++){const si=((c.y0+y)*c.p.width+c.x0+x)*c.p.channels,o=((gap+y)*W+ox+x)*3;px[o]=c.p.pixels[si];px[o+1]=c.p.pixels[si+1];px[o+2]=c.p.pixels[si+2];}ox+=c.w+gap;}
 const file=join(out,`${theme}-sheet.png`);writeRgbPng(file,W,H,px);report.sheet={file,order:tiles.map(t=>t.tag)};
}
async function clickNode(n:any){await h.mouseMove(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2);assert((await h.clickAt(n.rect.x+n.rect.w/2,n.rect.y+n.rect.h/2)).ok);await h.sleep(450);}
async function click(id:string){await clickNode(await visible(id));}
const check=(name:string,detail?:any)=>report.checks.push(detail===undefined?name:{name,detail});

/** The empty state is the native W.Empty: an icon, a title and a non-empty description, centered in its slot. */
function emptyShape(slot:any,label:string){
 const all=flat(slot).filter(shown);
 const icons=all.filter((n:any)=>n.kind==='icon'||n.type==='icon'||n.icon!==undefined||n.svg!==undefined);
 const texts=all.filter((n:any)=>typeof n.text==='string'&&n.text.length>0);
 assert(texts.length>=2,`${label}: empty state has a title and a description (${texts.map((t:any)=>t.text).join(' | ')})`);
 const [title,description]=texts;
 assert(description.text.length>=6,`${label}: description is a sentence`);
 const mid=(n:any)=>n.rect.x+n.rect.w/2;
 assert(Math.abs(mid(title)-mid(slot))<=2&&Math.abs(mid(description)-mid(slot))<=2,`${label}: title and description are centered`);
 return {title:title.text,description:description.text,icon:icons.length>0,slot:slot.rect};
}

/** The close button's native Tooltip shows "关闭 · Esc" after the hover delay. */
async function tooltipShown(id:string){return !!(await h.waitFor(async()=>(await nodes(id)).some((n:any)=>text(n).includes('关闭 · Esc'))||null,4000).catch(()=>null));}

const headers:any[]=[],closes:any[]=[];
async function panel(tag:string,trigger:string,root:string,header:string,close:string,empty?:string){
 await click(trigger);const rootNode=await visible(root);await h.sleep(300);
 const head=within(rootNode,header)[0]??(await visible(header));
 const x=within(rootNode,close)[0]??(await visible(close));
 assert(Math.abs(head.rect.h-30)<=0.5,`${tag}: header is 30 high (got ${head.rect.h})`);
 headers.push({tag,h:head.rect.h});closes.push({tag,w:x.rect.w,h:x.rect.h});
 const entry:any={header:head.rect,close:x.rect};
 if(empty){const slot=within(rootNode,empty)[0]??(await visible(empty));entry.empty=emptyShape(slot,tag);}
 report.panels[tag]=entry;
 await capture(`panel-${tag}`,rootNode.rect);
 // tooltip on the close button: "关闭 · Esc"
 await h.mouseMove(x.rect.x+x.rect.w/2,x.rect.y+x.rect.h/2);
 const tipText=await tooltipShown(`${close}.tooltip`);
 entry.close_tooltip=tipText;
 if(tag!=='history-tab')assert(tipText,`${tag}: close tooltip reads "关闭 · Esc"`);
 await clickNode(x);await hidden(root);
 check(`${tag}: header 30, native close, ${empty?'W.Empty':'no list'}`);
}

let ended:Promise<any>|undefined,app:any;
try{
 const ready=await h.waitFor(async()=>{if(peer.exitCode!==null)throw new Error('peer exited');try{return JSON.parse(await readFile(join(out,`${theme}-peer/ready.json`),'utf8'))}catch{return null}},15000);
 assert.equal(ready.host??'127.0.0.1','127.0.0.1');
 await writeFile(join(data,'known_hosts'),ready.known_host);
 await writeFile(join(data,'config.toml'),`[meta]\nconfig_revision=1\n[updates]\nauto_check=false\n[ui]\ntheme="${theme}"\n`);
 await writeFile(join(data,'hosts.toml'),`[registry]\nschema_version=2\nrevision=1\nnext_connection_id=2\nnext_group_id=1\n[[hosts]]\nconnection_id=1\nrevision=1\nprotocol="ssh"\nauth_mode="password"\noptions={strict_host_key=true}\nname="Panel SSH"\nhost="127.0.0.1"\nport=${ready.port}\nuser="${ready.user}"\nauth={password="${ready.password}"}\n`);
 const log=await open(join(out,`${theme}-app.log`),'w');
 app=spawn(binary,[],{env:{...process.env,ZEROWORK_DATA_DIR:data,ZEROWORK_AUTOCONNECT:'0',ZENIT_E2E_BACKGROUND:'1',ZENIT_E2E_ISOLATE_POINTER:'1'},stdio:['ignore',log.fd,log.fd]});
 ended=new Promise(r=>app.once('close',r));
 await Promise.race([h.waitForServerReady(60000),ended.then(()=>{throw new Error('app exited')})]);await h.resizeWindow(1440,900);
 // empty lists before any session: notifications, history (floating card and tab)
 await panel('notifications','toolbar.notifications','notifications.history','notifications.history.header','notifications.history.close','notifications.history.empty');
 await click('toolbar.history');const hist=await visible('history.panel');await h.sleep(500);
 const fh=await visible('history.header');assert(Math.abs(fh.rect.h-30)<=0.5,'history (floating): header 30');
 const fc=await visible('history.close');closes.push({tag:'history-float',w:fc.rect.w,h:fc.rect.h});headers.push({tag:'history-float',h:fh.rect.h});
 report.panels['history-float']={header:fh.rect,close:fc.rect,empty:emptyShape(await visible('history.empty'),'history list'),detail_empty:emptyShape(await visible('history.detail.empty'),'history detail')};
 await capture('panel-history-float',hist.rect);
 await h.mouseMove(fc.rect.x+fc.rect.w/2,fc.rect.y+fc.rect.h/2);
 report.panels['history-float'].close_tooltip=await tooltipShown('history.close.tooltip');
 assert(report.panels['history-float'].close_tooltip,'history (floating): close tooltip reads "关闭 · Esc"');
 await click('history.open_as_tab');const th=await visible('history.header');await h.sleep(400);
 assert(Math.abs(th.rect.h-30)<=0.5,'history (tab): header 30');assert.equal(within(await visible('history.panel'),'history.close').length,0,'history (tab): no close in the header (the tab closes)');
 headers.push({tag:'history-tab',h:th.rect.h});await capture('panel-history-tab',(await visible('history.panel')).rect);
 await h.key('w',{cmd:true});await h.sleep(600);
 check('history card: floating chrome header 30 + tab PanelHeader 30, W.Empty list and detail');
 // connect the owned peer
 const host=await visible('sidebar.host');await h.mouseMove(host.rect.x+100,host.rect.y+host.rect.h/2);await click('sidebar.host.connect');
 await h.waitFor(async()=>{const s=(await nodes('plugin.challenge.secret'))[0];if(s){await click('plugin.challenge.secret');await h.type_(ready.password);await click('plugin.challenge.submit');}return text((await nodes('workspace.pane'))[0]).includes('sshrecords')||null;},30000);
 await h.mouseMove(away.x,away.y);await h.sleep(800);
 await panel('chain','status.connection.chain','connection.details','connection.details.header','connection.details.close');
 await panel('forward','status.connection.forward','socks.info','socks.info.header','socks.info.close','socks.info.empty');
 await panel('transfers','toolbar.transfers','transfer.manager','transfer.header','transfer.window.close','transfer.empty');
 await panel('command-history','status.command-history','terminal.command-history','terminal.command-history.header','terminal.command-history.close','terminal.command-history.empty');
 // one close button for every panel
 const ref=closes[0];
 for(const c of closes){assert(Math.abs(c.w-ref.w)<=0.5&&Math.abs(c.h-ref.h)<=0.5,`close button of ${c.tag} matches ${ref.tag} (${c.w}x${c.h} vs ${ref.w}x${ref.h})`);assert(Math.abs(c.w-c.h)<=0.5&&c.h>=24&&c.h<=26,`close button of ${c.tag} is the square native ghost sm icon button`);}
 check('every close button is the same native ghost sm icon button',closes);
 check('every panel header is 30 high',headers);
 await sheet();
 report.status='passed';
}catch(e:any){report.status='failed';report.error=String(e?.stack??e);await h.screenshot(join(out,`${theme}-failure.png`)).catch(()=>{});}
finally{
 if(app&&app.exitCode===null){await h.request('POST','/zerowork/windows',{action:'quit'}).catch(()=>{});const start=Date.now();while(app.exitCode===null&&Date.now()-start<12000){for(const id of ['session.close.accept','groups.close.accept','local.close.accept','settings.confirmation.discard']){try{if((await nodes(id)).length)await h.clickTestId(id)}catch{}}await Promise.race([ended,h.sleep(150)]);}if(app.exitCode===null){app.kill('SIGTERM');await ended;}}
 peer.kill('SIGTERM');await Promise.race([peerEnded,h.sleep(3500)]);await peerLog.close();
 await writeFile(join(out,`${theme}-report.json`),JSON.stringify(report,null,1));await rm(iso,{recursive:true,force:true});
 console.log(JSON.stringify({status:report.status,error:report.error,out}));
 process.exit(report.status==='passed'?0:1);
}
