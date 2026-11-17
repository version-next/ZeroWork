/** Reusable assertion for a real visible notification and already-open detail
 * card. Caller owns its private app/RPC/fixture and captures each required
 * global/session, standard/minimum and sidebar state before closing the card.
 * No notification records or UI results are injected.
 */
import assert from 'node:assert/strict';
import {mkdir, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {query, clickAt, screenshot, waitFor, sleep, mouseMove} from '../zig-out/share/zenit/harness/client.ts';
const shown=(n:any)=>n&&n.hidden!==true&&n.visible!==false&&(n.effective_opacity??1)>0&&n.rect?.w>0&&n.rect?.h>0;
const flat=(n:any):any[]=>n?[n,...(n.children??[]).flatMap(flat)]:[];
const separated=(a:any,b:any)=>a.x+a.w<=b.x-8||a.x>=b.x+b.w+8||a.y+a.h<=b.y-8||a.y>=b.y+b.h+8;
export async function verifyNotificationAvoidance(out:string,name:string,options:{close?:boolean,width:number,height:number,cardId?:string,operationError?:boolean}) {
 await mkdir(out,{recursive:true});
 const cardId=options.cardId??'transfer.manager';
 const sample=await waitFor(async()=>{
  const cards=(await query(cardId)).filter(shown);
  const toasts=(await query('notifications.toast.0')).filter(shown);
  return cards.length===1&&toasts.length===1?{card:cards[0],toast:toasts[0]}:null;
 },10000);
 // Hold the existing fact through its supported hover pause while inspecting.
 await mouseMove(sample.toast.rect.x+20,sample.toast.rect.y+20);await sleep(180);
 const card=(await query(cardId)).find(shown)!;
 const toast=(await query('notifications.toast.0')).find(shown)!;
 const close=flat(card).find(n=>n.test_id==='transfer.window.close'&&shown(n));
 assert(close,'actual manager close control');
 const expected={x:options.width-392-22,y:62};
 assert(Math.abs(toast.rect.x-expected.x)<1&&Math.abs(toast.rect.y-expected.y)<1,'native notification retains fixed app-relative origin');
 assert.equal(toast.rect.w,392);
 assert(toast.rect.y>=8&&toast.rect.y+toast.rect.h<=options.height-8,'toast within app vertical bounds');
 const evidence:any={name,fixed_origin:true,card:card.rect,toast:toast.rect,close:close.rect,width:options.width,height:options.height,synthetic_harness_input:true};
 assert((await screenshot(join(out,name+'.png'))).ok);
 if(options.close){
  if(!separated(toast.rect,close.rect)){
   // Operation errors are intentionally visible above workspace overlays.
   // Dismissing the notification exposes the transfer manager's real close control.
   assert(options.operationError,'Ordinary notifications must not obscure the manager control');
   const dismiss=flat(toast).find(n=>n.test_id==='notifications.dismiss.0'&&shown(n));
   assert(dismiss,'Native operation error remains dismissible above the transfer manager');
   assert((await clickAt(dismiss.rect.x+dismiss.rect.w/2,dismiss.rect.y+dismiss.rect.h/2)).ok);
   await waitFor(async()=>!(await query('notifications.toast.0')).some(shown)||null,8000);
   assert((await query(cardId)).some(shown),'Dismissing the error keeps the transfer manager open');
   evidence.dismissed_overlaying_error=true;
  }
  const x=close.rect.x+close.rect.w/2,y=close.rect.y+close.rect.h/2;
  evidence.click={x,y,result:await clickAt(x,y)};assert(evidence.click.result.ok);
  await waitFor(async()=>!(await query(cardId)).some(shown)||null,8000);
  evidence.manager_closed=true;
 }
 await writeFile(join(out,name+'.json'),JSON.stringify(evidence,null,2));
 return evidence;
}
