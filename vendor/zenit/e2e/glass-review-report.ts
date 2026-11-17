// A reviewable report uses actual window captures and preserves source hashes.
// PNG comparisons are embedded, so the main report opens without a server.
import { readFileSync, writeFileSync, existsSync, cpSync } from "node:fs";
import { resolve } from "node:path";
import { createHash } from "node:crypto";
import { decodePng, writeRgbPng } from "./png";
const root=resolve(process.argv[2]??"reports/glass-native-fidelity");
const read=(file:string)=>{try{return JSON.parse(readFileSync(`${root}/${file}`,"utf8"));}catch{return null;}};
const contract=JSON.parse(readFileSync("e2e/glass-fidelity.contract.json","utf8"));
const comparison=read("comparison.json"),motion=read("native-motion/comparison.json"),gate=read("gate-status.json");
const pixelmatch=read("pixelmatch.json"),motionPixelmatch=read("native-motion/pixelmatch.json");
const image=(file:string)=>existsSync(`${root}/${file}`)?`data:image/png;base64,${readFileSync(`${root}/${file}`).toString("base64")}`:null;
const hash=(file:string)=>existsSync(`${root}/${file}`)?createHash("sha256").update(readFileSync(`${root}/${file}`)).digest("hex"):null;
for(const [log,destination] of [["storybook.log","storybook-regressions/window-results"],["flicker.log","storybook-flicker/window-results"]]) {
  if(!existsSync(`${root}/${log}`))continue;
  const source=readFileSync(`${root}/${log}`,"utf8").match(/Output:\s+(\/tmp\/zenit_e2e_test\/[a-zA-Z0-9-]+)/)?.[1];
  if(source&&existsSync(source))cpSync(source,`${root}/${destination}`,{recursive:true});
}
const storybookImages=[
  ["GlassEdge：实际侧栏文字","story-glassedge.png"],
  ["GlassMotion：实际 morph 与工具条前景","story-glassmotion-morphed.png"],
  ["GlassMotion：实际滚动后窗口","story-glassmotion-scrolled.png"],
  ["GlassBox：实际 Regular / Interactive / Clear","glassbox-rest.png"],
  ["GlassBox：实际按压态","glassbox-press.png"],
].map(([title,file])=>({title,file:`storybook-regressions/window-results/${file}`,image:image(`storybook-regressions/window-results/${file}`),sha256:hash(`storybook-regressions/window-results/${file}`)}));
function heatmap(native:string,actual:string,out:string) {
  const a=decodePng(`${root}/${native}`),b=decodePng(`${root}/${actual}`),heat=new Uint8Array(a.width*a.height*3);
  if(a.width!==b.width||a.height!==b.height)throw new Error("Motion dimensions mismatch");
  for(let i=0;i<a.width*a.height;i++)heat[i*3]=Math.min(255,Math.max(...[0,1,2].map(c=>Math.abs(a.pixels[i*a.channels+c]-b.pixels[i*b.channels+c])))*5);
  writeRgbPng(`${root}/${out}`,a.width,a.height,heat);
}
const cases:any[]=[];
for(const id of contract.required_cases) {
  const result=comparison?.results?.find((r:any)=>r.id===id);
  const pixel=pixelmatch?.results?.find((r:any)=>r.id===id);
  const native=`native/${id}.png`,actual=`zenit/${id}.png`;
  cases.push({id,group:"静态材质",status:result?.status==="PASS"&&pixel?.status==="PASS"?"PASS":result&&pixel?"FAIL":"MISSING",
    values:{...result?.values,...result?.structure,pixelmatch_diff_pixels:pixel?.diff_pixels},regional_status:result?.status,pixelmatch_status:pixel?.status,
    pixelmatch:pixel?{status:pixel.status,roi:pixel.roi,diff:image(`playwright/diff/${id}.png`)}:null,
    failures:[...(result?.failures??["缺少区域结果"]),...(pixel?.status==="PASS"?[]:[`Playwright ${pixel?.status??"MISSING"}: ${pixel?.diff_pixels??"未知"} differing pixels`])],
    native:image(native),actual:image(actual),diff:image(`diff/${id}.png`),
    source:{native,actual,native_sha256:hash(native),zenit_sha256:hash(actual)}});
}
for(const s of motion?.snapshots??[]) {
  const pixel=motionPixelmatch?.results?.find((r:any)=>r.id===s.id);
  const native=`native-motion/native/${s.id}.png`,actual=`native-motion/zenit/${s.id}.png`;
  const diff=`native-motion/${s.id}-review-diff.png`;
  heatmap(native,actual,diff);
  const action=s.action??(s.id.startsWith("morph-")?"morph":s.id.startsWith("scroll-")?"scroll":s.id.startsWith("drag-")?"drag":"hover_press_release");
  const fullNative=`native-motion/swiftui/${action}/${s.native_frame}`,fullActual=`native-motion/zenit/${action}/${s.zenit_frame}`;
  const fullDiff=`native-motion/${s.id}-full-review-diff.png`;
  if(s.mask)heatmap(fullNative,fullActual,fullDiff);
  cases.push({id:s.id,group:s.mask?"Morph 原始窗口帧（主体 mask＋原始边缘）":"交互检查点",status:s.failures.length||pixel?.status!=="PASS"?"FAIL":"PASS",
    values:{...s.values,...s.structure,pixelmatch_diff_pixels:pixel?.diff_pixels},
    pixelmatch:pixel?{status:pixel.status,roi:pixel.roi,diff:image(`native-motion/playwright/diff/${s.id}.png`)}:null,
    failures:[...s.failures,...(pixel?.status==="PASS"?[]:[`Playwright ${pixel?.status??"MISSING"}: ${pixel?.diff_pixels??"未知"} differing pixels`])],mask:s.mask,native:image(native),actual:image(actual),diff:image(diff),
    full:s.mask?{native:image(fullNative),actual:image(fullActual),diff:image(fullDiff)}:null,
    source:{native,actual,native_frame:s.native_frame,zenit_frame:s.zenit_frame,native_sha256:hash(native),zenit_sha256:hash(actual),
      original_native_frame:fullNative,original_zenit_frame:fullActual,original_native_sha256:s.native_sha256,original_zenit_sha256:s.zenit_sha256}});
}
const evidence={generated_at:new Date().toISOString(),status:gate?.status??"INCOMPLETE",gate,
  capture_retries:read("capture-retries.json"),
  native:read("native/metadata.json"),production:read("probe-run/manifest.json"),production_capture:read("zenit/metadata.json"),
  window:{storybook:read("storybook-regressions/window-results/summary.json"),flicker:read("storybook-flicker/window-results/summary.json"),images:storybookImages.map(({image,...rest})=>rest)},
  pixelmatch:read("pixelmatch.json"),motion_pixelmatch:read("native-motion/pixelmatch.json"),
  motion:motion?{status:motion.status,run_id:motion.run_id,results:motion.results,sources:motion.sources}:null,
  contract,comparison_source_sha256:hash("comparison.json")};
const data=JSON.stringify({evidence,cases}).replaceAll("<","\\u003c");
const html=`<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>SwiftUI 原生 / Zenit — Liquid Glass 视觉差异报告</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#111315;color:#edf0f4;font:14px/1.65 system-ui}header,main{max-width:1440px;margin:auto;padding:24px}header{padding-bottom:8px}h1{font-size:25px;margin:0 0 8px}h2{font-size:18px;margin:0}p{margin:8px 0;color:#aeb7c4}button,select,input{font:inherit}button,select{background:#20252c;border:1px solid #3e4956;border-radius:7px;color:inherit;padding:7px 12px}button{cursor:pointer}button[aria-pressed=true]{border-color:#8bbfff;background:#234265}a{color:#9ac5ff}code{font:12px ui-monospace;overflow-wrap:anywhere}.badge{padding:3px 10px;border-radius:5px;background:#663e1b;display:inline-block}.pass{background:#185938}.fail{background:#742d31}.toolbar{display:flex;flex-wrap:wrap;align-items:center;gap:8px;margin:16px 0}.toolbar select{min-width:270px}.viewer{background:#090a0b;border:1px solid #3a424d;overflow:auto;border-radius:8px}.stack{position:relative;width:100%;aspect-ratio:4/3;overflow:hidden}.stack img{position:absolute;inset:0;width:100%;height:100%;object-fit:contain}.stack .actual{clip-path:inset(0 50% 0 0)}.divider{position:absolute;top:0;bottom:0;left:50%;border-left:2px solid #ffdf6b;pointer-events:none}.name{position:absolute;top:8px;padding:3px 8px;background:#111d;border-radius:4px;z-index:3}.name.native{right:8px}.name.zenit{left:8px}#pixel-view{display:none;max-width:100%;height:auto;margin:auto}.counts{display:flex;flex-wrap:wrap;gap:8px;margin:12px 0}.counts span{background:#20252c;border:1px solid #3e4956;padding:6px 12px;border-radius:6px}.side{display:none;grid-template-columns:1fr 1fr;gap:8px}.side img{width:100%;display:block}.side figcaption{padding:8px}.side figure{margin:0}.details{display:grid;grid-template-columns:1fr 1fr;gap:20px;margin:20px 0}pre{white-space:pre-wrap;overflow-wrap:anywhere;font:12px/1.6 ui-monospace;color:#becbdb}.panel{background:#1b2026;border:1px solid #323b47;border-radius:8px;padding:16px}table{width:100%;border-collapse:collapse;font-variant-numeric:tabular-nums}th,td{padding:8px;text-align:left;border-bottom:1px solid #333c48}tbody tr{cursor:pointer}tbody tr:hover{background:#283342}.failtext{color:#ffb3b3}.meta{font:12px ui-monospace;color:#aeb7c4}details{margin:20px 0}summary{cursor:pointer}#failures{color:#ffb8a9}#position{flex:1;max-width:360px}button:focus-visible,select:focus-visible{outline:2px solid #aad3ff;outline-offset:3px}@media(max-width:800px){.details{grid-template-columns:1fr}header,main{padding:16px}}
</style>
<header><h1>SwiftUI 原生 / Zenit — Liquid Glass 视觉差异报告</h1><span id="overall" class="badge"></span><div id="counts" class="counts"></div><p id="environment"></p><p class="meta" id="run"></p><p id="failure-summary" class="failtext"></p>
<p>原生图来自真实 SwiftUI <code>glassEffect</code> 窗口；Zenit 图来自生产 Metal 渲染窗口。比较使用原始 1280 × 960 PNG，不进行平移、缩放或颜色配准。网页缩放仅用于查看。</p>
<p>Playwright 使用感知色差阈值 0.2 和零超限像素；其 PASS 不代表 RGB 完全相同，也不能单独证明材质一致。RGB 热图显示所有通道差异，数值另列零容差的逐像素不同数量。综合状态还要求主体透射和边缘折射的结构检查通过。</p>
<p>文字场景同时覆盖玻璃背后的细字与玻璃前的内容。材质对照的前景使用同一文字位图，以隔离字形栅格化差异；Storybook 真实文本的前景对比度另做窗口验收。</p></header>
<main><div class="toolbar"><label for="scene">场景</label><select id="scene"></select><button data-mode="wipe" aria-pressed="true">滑块叠图</button><button data-mode="side" aria-pressed="false">并排</button><button data-mode="diff" aria-pressed="false">RGB 差异 × 5</button><button id="pixel-button" data-mode="pixel" aria-pressed="false">Playwright 差异像素</button><label for="zoom">查看比例</label><select id="zoom"><option value="fit">适应窗口</option><option value="1280">100% 原始像素</option><option value="2560">200%</option></select></div>
<div class="toolbar"><span>左 Zenit / 右 SwiftUI</span><input id="position" aria-label="叠图分界位置" type="range" min="0" max="100" value="50"><label><input id="original" type="checkbox" checked>查看原始完整帧</label><span id="state" class="badge"></span></div>
<p id="comparison-note"></p><div class="viewer"><img id="pixel-view" alt="原始 Playwright pixelmatch 差异图"><div id="stack" class="stack"><img id="native" alt="真实 SwiftUI 原生窗口"><img id="actual" class="actual" alt="真实 Zenit Metal 窗口"><img id="diff" alt="绝对 RGB 误差乘五" hidden><div id="line" class="divider"></div><span class="name zenit">Zenit</span><span class="name native">SwiftUI 原生</span></div><div id="side" class="side"><figure><figcaption>SwiftUI 原生</figcaption><img id="side-native" alt="原生并排图"></figure><figure><figcaption>Zenit 生产实现</figcaption><img id="side-actual" alt="Zenit 并排图"></figure></div></div>
<div class="details"><section class="panel"><h2 id="title"></h2><p id="failures"></p><p id="exact-summary"></p><pre id="metrics"></pre></section><section class="panel"><h2>截图来源与完整性</h2><p id="mask"></p><pre id="source"></pre><a id="save-native" download>下载原生 PNG</a> · <a id="save-actual" download>下载 Zenit PNG</a></section></div>
<section class="panel"><h2>全部场景与失败项</h2><p>点击任一行查看。区域数值、低对比度结构与 Playwright pixelmatch 分别验收，整体状态同时要求窗口交互和动态验收完整通过。<label><input id="only-fail" type="checkbox">仅显示失败 / 缺失</label></p><table><thead><tr><th>场景</th><th>综合状态</th><th>主体 RMSE</th><th>边缘 RMSE</th><th>主体 SSIM</th></tr></thead><tbody id="rows"></tbody></table></section>
<details class="panel"><summary>原生动态验收、输入和帧时钟证据</summary><pre id="motion"></pre><p><a href="native-motion/report.html">打开完整动态检查点报告</a> · <a href="native-motion/pixelmatch.html">动态 Playwright 报告</a></p></details>
<details class="panel"><summary>Storybook 实际窗口：你指出的文字、工具条和交互面板</summary><p>以下是同次窗口回归的实际截图，包含 Storybook 布局与真实文本。原生材质 diff 使用上面的共同背景、相同几何和共同前景；这些窗口截图用于检查实际使用场景。</p>${storybookImages.filter(s=>s.image).map(s=>`<figure style="margin:20px 0"><figcaption>${s.title} · <code>${s.sha256}</code></figcaption><img style="width:100%;height:auto" src="${s.image}" alt="${s.title}"></figure>`).join("")}<pre id="window-evidence"></pre></details>
<details class="panel"><summary>环境、固定阈值与 gate 证据</summary><pre id="evidence"></pre><p><a href="pixelmatch.html">Playwright pixelmatch 结果</a> · <a href="comparison.json">原始区域数值</a> · <a href="gate-status.json">全部验收状态</a></p></details>
<p class="meta">主对照 PNG 已嵌入此 HTML，可离线打开。完整时钟、原始帧和 JSON 通过同目录链接查看。缺失或失败的验收不会被显示为完成。</p></main>
<script type="application/json" id="data">${data}</script><script>
const {cases,evidence}=JSON.parse(document.getElementById('data').textContent);const el=id=>document.getElementById(id);let mode='wipe';
const fmt=n=>typeof n==='number'?n.toFixed(4):'—';const badge=(e,status)=>{e.textContent=status;e.className='badge '+(status==='PASS'?'pass':status==='FAIL'?'fail':'')};
badge(el('overall'),evidence.status);el('overall').textContent=evidence.status==='PASS'?'PASS · 已列场景通过':'验收未全部通过：'+evidence.status;
const count=(rs)=>String(rs?.filter(r=>r.status==='PASS').length??0)+' / '+String(rs?.length??0);for(const title of ['静态区域与结构：'+count(cases.filter(c=>c.group==='静态材质').map(c=>({status:c.regional_status}))), '静态 Playwright：'+count(evidence.pixelmatch?.results),'原生动态综合：'+count(evidence.motion?.results),'动态 Playwright：'+count(evidence.motion_pixelmatch?.results),'窗口回归：'+(evidence.window?.storybook?String(evidence.window.storybook.passed)+' / '+String(evidence.window.storybook.total):String(evidence.gate?.checks?.find(c=>c.name==='storybook_interactions')?.status??'MISSING')), '滚动稳定性：'+(evidence.window?.flicker?String(evidence.window.flicker.passed)+' / '+String(evidence.window.flicker.total):'MISSING')]){const span=document.createElement('span');span.textContent=title;el('counts').append(span)}el('run').textContent='Run ID：'+String(evidence.gate?.run_id??'缺失')+' · HTML：'+evidence.generated_at;
el('environment').textContent=(evidence.native?.os??'原生环境缺失')+' · 2× / sRGB · '+(evidence.native?.captured_at??'')+' · diffusion 环境偏好记录：'+String(evidence.native?.glass_diffusion_preference??'未记录');
el('failure-summary').textContent=cases.some(c=>c.status!=='PASS')?'未通过 / 缺失：'+cases.filter(c=>c.status!=='PASS').map(c=>c.id).join('、'):'全部已列截图通过当前阈值；结果仅覆盖本报告记录的场景与环境。';el('evidence').textContent=JSON.stringify(evidence,null,2);el('motion').textContent=JSON.stringify(evidence.motion,null,2);el('window-evidence').textContent=JSON.stringify(evidence.window,null,2);
for(const [i,c]of cases.entries()){const option=document.createElement('option');option.value=i;option.textContent=c.group+' / '+c.id+' — '+c.status;el('scene').append(option);const tr=document.createElement('tr');for(const value of [c.id,c.status,fmt(c.values?.body_rmse),fmt(c.values?.rim_rmse),fmt(c.values?.body_ssim)]){const td=document.createElement('td');td.textContent=value;tr.append(td)}tr.dataset.status=c.status;if(c.status!=='PASS')tr.className='failtext';tr.onclick=()=>{el('scene').value=i;render();el('scene').scrollIntoView({behavior:'smooth',block:'center'})};el('rows').append(tr)}
function render(){const c=cases[Number(el('scene').value)];const images=c.full&&el('original').checked?c.full:c;el('original').disabled=!c.full;el('title').textContent=c.group+' / '+c.id;badge(el('state'),c.status);el('failures').textContent=c.failures.join('; ')||'区域指标通过；整体结果见上方 gate。';el('exact-summary').textContent='零容差 RGB 不同像素：主体 '+String(c.values?.exact_rgb_body_different_pixels??'未记录')+' / '+String(c.values?.exact_rgb_body_measured_pixels??'未记录')+'；边缘 '+String(c.values?.exact_rgb_rim_different_pixels??'未记录')+' / '+String(c.values?.exact_rgb_rim_measured_pixels??'未记录')+'。结构 significant=false / null 表示原生信号不足，不代表完全一致。';el('metrics').textContent=JSON.stringify(c.values??{},null,2);el('source').textContent=JSON.stringify(c.source,null,2);el('mask').textContent=c.mask?'数值使用 '+c.mask+'。完整帧视图保留原始几何差异与系统窗口元素；取消勾选可查看验收 mask。':'完整窗口原始 PNG；指标按固定几何划分主体、边缘、阴影和背景。';el('native').src=el('side-native').src=images.native??'';el('actual').src=el('side-actual').src=images.actual??'';el('save-native').href=images.native??'';el('save-native').download=c.id+'-swiftui.png';el('save-actual').href=images.actual??'';el('save-actual').download=c.id+'-zenit.png';el('diff').src=images.diff??'';el('pixel-view').src=c.pixelmatch?.diff??'';el('pixel-button').disabled=!c.pixelmatch?.diff;if(mode==='pixel'&&!c.pixelmatch?.diff)mode='wipe';setMode(mode);el('zoom').onchange()}
function setMode(value){mode=value;el('stack').style.display=value==='side'||value==='pixel'?'none':'block';el('pixel-view').style.display=value==='pixel'?'block':'none';const c=cases[Number(el('scene').value)];el('comparison-note').textContent=value==='pixel'?'Playwright 原始裁剪图：红色为超出感知阈值的像素；黄色为算法排除的抗锯齿像素。ROI '+JSON.stringify(c.pixelmatch?.roi??{})+'。':value==='diff'?'此热图显示所有绝对 RGB 误差 × 5；它与 Playwright 的感知判定是两种独立视图。':'滑块 / 并排视图保留原始窗口内容；完整帧的可见差异不等于 mask 指标全部覆盖。';el('side').style.display=value==='side'?'grid':'none';el('diff').hidden=value!=='diff';el('actual').hidden=value==='diff';el('line').hidden=value!=='wipe';for(const b of document.querySelectorAll('[data-mode]'))b.setAttribute('aria-pressed',String(b.dataset.mode===value));for(const label of document.querySelectorAll('.name'))label.hidden=value!=='wipe'}
el('position').oninput=()=>{const v=el('position').value;el('actual').style.clipPath='inset(0 '+(100-v)+'% 0 0)';el('line').style.left=v+'%'};
el('zoom').onchange=()=>{const z=el('zoom').value;el('stack').style.width=z==='fit'?'100%':z+'px';el('side').style.width=z==='fit'?'100%':Number(z)*2+'px';const c=cases[Number(el('scene').value)];el('pixel-view').style.maxWidth=z==='fit'?'100%':'none';el('pixel-view').style.width=z==='fit'?'auto':((c.pixelmatch?.roi?.w??1280)*Number(z)/1280)+'px'};
el('only-fail').onchange=()=>{for(const row of el('rows').children)row.hidden=el('only-fail').checked&&row.dataset.status==='PASS'};el('scene').onchange=el('original').onchange=render;for(const b of document.querySelectorAll('[data-mode]'))b.onclick=()=>setMode(b.dataset.mode);
const requested=decodeURIComponent(location.hash.slice(1))||'mixed-regular-capsule';const preferred=cases.findIndex(c=>c.id===requested);el('scene').value=preferred<0?0:preferred;render();
</script></html>`;
writeFileSync(`${root}/review.html`,html);
console.log(`Review HTML: ${root}/review.html (${(Buffer.byteLength(html)/1024/1024).toFixed(1)} MiB), status=${evidence.status}`);
