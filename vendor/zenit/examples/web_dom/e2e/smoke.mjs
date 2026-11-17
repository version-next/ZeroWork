// Web DOM host smoke: serve zig-out/web, load the demo in Chrome, click "+1",
// scroll the list, and screenshot. Usage: node smoke.mjs <zig-out/web> <out-dir>
import { createServer } from 'node:http';
import { readFile, mkdir } from 'node:fs/promises';
import { extname, join, resolve } from 'node:path';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const pw = require(process.env.PLAYWRIGHT_CORE || 'playwright-core');

const [root = 'zig-out/web', out = 'zig-out/web-e2e'] = process.argv.slice(2);
await mkdir(out, { recursive: true });
const types = { '.html': 'text/html', '.mjs': 'text/javascript', '.js': 'text/javascript', '.wasm': 'application/wasm', '.json': 'application/json' };
const server = createServer(async (req, res) => {
  try {
    const p = resolve(root, '.' + decodeURIComponent(new URL(req.url, 'http://x').pathname));
    if (!p.startsWith(resolve(root))) throw new Error('outside');
    const body = await readFile(p);
    res.writeHead(200, { 'content-type': types[extname(p)] || 'application/octet-stream' });
    res.end(body);
  } catch { res.writeHead(404); res.end(); }
}).listen(0, '127.0.0.1');
await new Promise((r) => server.once('listening', r));
const url = `http://127.0.0.1:${server.address().port}/web_dom/index.html`;

const browser = await pw.chromium.launch({ executablePath: process.env.CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', headless: true, args: ['--enable-unsafe-webgpu', '--enable-gpu', '--use-angle=metal'] });
const page = await browser.newPage({ viewport: { width: 900, height: 700 }, deviceScaleFactor: 2 });
const logs = [];
page.on('console', (m) => logs.push(`[${m.type()}] ${m.text()}`));
page.on('pageerror', (e) => logs.push(`[pageerror] ${e.message}`));
let failures = 0;
const check = (ok, msg) => { console.log(`${ok ? 'PASS' : 'FAIL'} ${msg}`); if (!ok) failures++; };
try {
  await page.goto(url);
  await page.waitForFunction(() => window.__zenit && window.__zenit.perf.frames > 0, null, { timeout: 15000 });
  await page.waitForTimeout(300);
  const textOf = () => page.evaluate(() => [...document.querySelectorAll('#app [data-zid]')].filter((e) => e.childElementCount === 0 && e.textContent).map((e) => e.textContent));
  let texts = await textOf();
  check(texts.includes('count = 0'), 'initial count text rendered as DOM text');
  check(texts.includes('Row 199: zenit node mirrored into the DOM'), 'v.each rows mirrored (200 rows)');
  await page.screenshot({ path: join(out, '01_initial.png') });
  // Semantics: native HTML elements first (<button>, <nav>, ...), explicit ARIA roles only where
  // no element carries the role implicitly.
  const roles = await page.evaluate(() => [
    ...[...document.querySelectorAll('#app [role]')].map((e) => e.getAttribute('role')),
    ...[...document.querySelectorAll('#app button')].map(() => 'button'),
    ...[...document.querySelectorAll('#app input, #app textarea')].map(() => 'textbox'),
  ]);
  const nativeButtons = await page.evaluate(() => document.querySelectorAll('#app button[data-zid]').length);
  check(roles.includes('button') && roles.includes('textbox') && nativeButtons > 0, `zenit a11y semantics as native elements + ARIA (${[...new Set(roles)].join(',')}; ${nativeButtons} <button>)`);

  // WebGPU canvas island.
  await page.waitForFunction(() => window.__zenit.gpu.device || window.__zenit.gpu.failed, null, { timeout: 15000 }).catch(() => {});
  await page.waitForTimeout(300);
  const isl = await page.evaluate(() => ({ gpu: !!window.__zenit.gpu.device, islands: window.__zenit.islands.size, words: window.__zenit.perf.islandWords || 0, ms: window.__zenit.perf.islandMs || 0, canvas: document.querySelectorAll('.z-island canvas').length }));
  console.log('island', JSON.stringify(isl));
  check(isl.canvas >= 1 && isl.gpu && isl.words > 0, `canvas islands painted via WebGPU (${isl.islands} islands: ${isl.words} words, ${isl.ms.toFixed(2)} ms)`);
  await page.screenshot({ path: join(out, '00_island.png') });

  // Find "+1" button center from DOM geometry (DOM = zenit layout).
  const box = await page.evaluate(() => {
    const t = [...document.querySelectorAll('#app .z-text')].find((e) => e.textContent === '+1');
    const r = t.parentElement.getBoundingClientRect();
    return { x: r.x + r.width / 2, y: r.y + r.height / 2 };
  });
  for (let i = 0; i < 3; i++) { await page.mouse.click(box.x, box.y); await page.waitForTimeout(60); }
  await page.waitForTimeout(200);
  texts = await textOf();
  check(texts.includes('count = 3'), 'clicking +1 three times through zenit hit testing -> count = 3');
  check(texts.includes('doubled = 6'), 'memo propagated -> doubled = 6');
  check(texts.includes('odd'), 'v.show fallback switched (odd)');
  await page.screenshot({ path: join(out, '02_clicked.png') });

  // Text input: click the Input, type ASCII, then an IME composition (CDP).
  const inputBox = await page.evaluate(() => {
    const t = [...document.querySelectorAll('#app [data-zid]')].find((e) => e.childElementCount === 0 && e.textContent.startsWith('输入中文'));
    const r = t.getBoundingClientRect(); return { x: r.x + 10, y: r.y + r.height / 2 };
  });
  await page.mouse.click(inputBox.x, inputBox.y);
  await page.waitForTimeout(100);
  await page.keyboard.type('hi ');
  const cdp = await page.context().newCDPSession(page);
  await cdp.send('Input.imeSetComposition', { text: 'ni', selectionStart: 2, selectionEnd: 2 });
  await page.waitForTimeout(50);
  await cdp.send('Input.insertText', { text: '你好' });
  await page.waitForTimeout(300);
  texts = await textOf();
  const typed = texts.find((t) => t.startsWith('typed: ')) || '';
  check(typed.includes('hi 你好'), `typing + IME commit reach the zenit Input (${JSON.stringify(typed)})`);
  await page.screenshot({ path: join(out, '02b_input.png') });

  // Scroll the list.
  const listPos = await page.evaluate(() => {
    const t = [...document.querySelectorAll('#app .z-text')].find((e) => e.textContent.startsWith('Row 0:'));
    const r = t.getBoundingClientRect();
    return { x: r.x + 40, y: r.y + 5, top: r.y };
  });
  await page.mouse.move(listPos.x, listPos.y);
  for (let i = 0; i < 6; i++) { await page.mouse.wheel(0, 120); await page.waitForTimeout(30); }
  await page.waitForTimeout(800);
  const top2 = await page.evaluate(() => [...document.querySelectorAll('#app .z-text')].find((e) => e.textContent.startsWith('Row 0:')).getBoundingClientRect().y);
  check(top2 < listPos.top - 100, `wheel scrolled the ScrollArea content (Row 0 y ${listPos.top.toFixed(0)} -> ${top2.toFixed(0)})`);
  // Native scrolling: the ScrollArea is an overflow:auto scroller the browser moved
  // (scrollTop), zenit followed (layout rects agree), and the content carries no transform.
  const sc = await page.evaluate(() => {
    const el = document.querySelector('#app [data-z-scroll]');
    if (!el) return null;
    const content = el.firstElementChild;
    // Browser layout agrees with zenit's rects page-wide, scrolled list and the Input
    // with its scrolled text included (200 rows x 19.6px accumulate LayoutUnit rounding).
    return { top: el.scrollTop, overflowY: getComputedStyle(el).overflowY, transform: content ? getComputedStyle(content).transform : '', drift: window.__zenit.layoutDrift({ tol: 2 }) };
  });
  check(sc && sc.top > 100 && sc.overflowY === 'auto' && sc.transform === 'none' && sc.drift.over === 0,
    `ScrollArea scrolls natively (scrollTop ${sc && sc.top}, overflow-y ${sc && sc.overflowY}, content transform ${sc && sc.transform}, drift ${sc && sc.drift.maxErr}px)`);
  if (sc && sc.drift.over) console.log(JSON.stringify(sc.drift.worst.slice(0, 3)));
  await page.screenshot({ path: join(out, '03_scrolled.png') });

  // Overlay scrollbar: its parts live in the scroller's non-scrolling rail, so a wheel
  // never drags them along with the content, and a thumb drag keeps the thumb under the
  // pointer while the hover track stays put every frame (no flicker).
  await page.mouse.wheel(0, -120); await page.waitForTimeout(150);
  const bar = await page.evaluate(() => {
    const sc = document.querySelector('#app [data-z-scroll]');
    const parts = [...(sc._zRail ? sc._zRail.children : [])];
    const t = parts.filter((c) => { const b = c.getBoundingClientRect(); return b.height > 10 && b.width < 12; }).sort((a, b) => a.getBoundingClientRect().height - b.getBoundingClientRect().height)[0];
    if (!t) return null;
    t.id = 'smoke-thumb';
    const b = t.getBoundingClientRect();
    window.__bar = [];
    const tick = () => {
      const tb = document.getElementById('smoke-thumb').getBoundingClientRect();
      window.__bar.push([tb.top, parts.map((p) => { const r = p.getBoundingClientRect(); return `${r.width}x${r.height}`; }).join(',')]);
      if (window.__bar.length < 400) requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);
    return { inRail: !!sc._zRail && t.parentElement === sc._zRail, x: b.x + b.width / 2, y: b.y + b.height / 2 };
  });
  let followErr = Infinity, trackStates = 0;
  if (bar) {
    await page.mouse.move(bar.x, bar.y); await page.waitForTimeout(150);
    await page.mouse.down();
    await page.mouse.move(bar.x, bar.y + 2); await page.waitForTimeout(100);
    const t0 = await page.evaluate(() => document.getElementById('smoke-thumb').getBoundingClientRect().top);
    await page.evaluate(() => { window.__bar.length = 0; });
    followErr = 0;
    for (let i = 1; i <= 10; i++) {
      await page.mouse.move(bar.x, bar.y + 2 + i * 4); await page.waitForTimeout(50);
      const top = await page.evaluate(() => document.getElementById('smoke-thumb').getBoundingClientRect().top);
      followErr = Math.max(followErr, Math.abs(top - t0 - i * 4));
    }
    const frames = await page.evaluate(() => window.__bar.slice());
    await page.mouse.up();
    // track/thumb sizes per frame: the hover track must not toggle while dragging
    trackStates = new Set(frames.map((f) => f[1].split(',').filter((s) => s !== '0x0').length)).size;
  }
  check(bar && bar.inRail && followErr < 1 && trackStates === 1, `scrollbar thumb in the non-scrolling rail, follows the pointer (max ${followErr.toFixed(2)}px off), track stable while dragging (${trackStates} visible-part state)`);

  // Browser shortcuts zenit does not handle keep their default (reload, find, print...);
  // keys zenit handles (Tab focus traversal) are stopped.
  await page.evaluate(() => { window.__kp = []; window.addEventListener('keydown', (e) => { if (!['Meta', 'Shift'].includes(e.key)) window.__kp.push([e.key, e.defaultPrevented]); e.preventDefault(); }); });
  for (const c of ['Meta+r', 'Meta+Shift+r', 'Meta+f', 'Meta+p', 'Tab']) await page.keyboard.press(c);
  const kp = await page.evaluate(() => window.__kp);
  check(kp.length === 5 && kp.slice(0, 4).every((k) => !k[1]) && kp[4][1], `browser shortcuts pass through, zenit keys are stopped (${kp.map((k) => k[0] + (k[1] ? ':stopped' : ':browser')).join(' ')})`);

  // Resize.
  await page.setViewportSize({ width: 640, height: 560 });
  await page.waitForTimeout(300);
  const rootW = await page.evaluate(() => document.querySelector('#app > div').getBoundingClientRect().width);
  check(Math.abs(rootW - 640) < 1, `resize relayout: root width ${rootW}`);
  await page.screenshot({ path: join(out, '04_resized.png') });

  // Canvas2D fallback renderer for islands (no WebGPU).
  const p2 = await browser.newPage();
  await p2.setViewportSize({ width: 900, height: 700 });
  p2.on('pageerror', (e) => logs.push(`[pageerror] ${e.message}`));
  await p2.goto(url + '?renderer=canvas2d');
  await p2.waitForFunction(() => window.__zenit && window.__zenit.gpu.backend && (window.__zenit.perf.islandWords || 0) > 0, null, { timeout: 15000 }).catch(() => {});
  const c2 = await p2.evaluate(() => ({ backend: window.__zenit.gpu.backend, words: window.__zenit.perf.islandWords || 0 }));
  check(c2.backend === 'canvas2d' && c2.words > 0, `Canvas2D fallback paints the island (${c2.backend}, ${c2.words} words)`);
  await p2.screenshot({ path: join(out, '05_canvas2d.png') });
  await p2.close();

  const perf = await page.evaluate(() => ({ nodes: window.__zenit.perf.nodes(), frames: window.__zenit.perf.frames, last: window.__zenit.perf.lastFrameMs }));
  console.log('perf', JSON.stringify(perf));

  // Persistent filesystem: the app writes /demo/count.txt (on +1) and
  // /demo/visits.txt (on mount) via std.Io.Dir.cwd().writeFile; both must
  // survive a reload through IndexedDB.
  check(texts.includes('visits = 1'), 'first visit counted through std.Io.Dir (visits = 1)');
  const storage = await page.evaluate(() => window.__zenit.vfs && window.__zenit.vfs.storage);
  check(typeof storage === 'string' && storage.length > 0, `VFS backed by IndexedDB (${storage})`);
  await page.waitForTimeout(700); // > 300 ms debounce
  await page.reload();
  await page.waitForFunction(() => window.__zenit && window.__zenit.perf.frames > 0, null, { timeout: 15000 });
  await page.waitForTimeout(300);
  texts = await textOf();
  check(texts.includes('count = 3') && texts.includes('visits = 2'), `files survive reload (${texts.filter((t) => /^(count|visits) =/.test(t)).join(', ')})`);
  const rec = await page.evaluate(async (name) => {
    const db = await new Promise((res, rej) => { const r = indexedDB.open(name); r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error); });
    const v = await new Promise((res) => { const r = db.transaction('files').objectStore('files').get('/demo/count.txt'); r.onsuccess = () => res(r.result); });
    return v && { kind: v.kind, text: new TextDecoder().decode(v.data), mtime: v.mtime };
  }, storage);
  check(rec && rec.kind === 1 && rec.text === '3' && rec.mtime > 1.6e12, `IndexedDB record /demo/count.txt = ${JSON.stringify(rec)}`);
} finally {
  const bad = logs.filter((l) => /error|panic/i.test(l));
  for (const l of logs) console.log(l);
  check(bad.length === 0, 'no console errors / panics');
  await browser.close();
  server.close();
}
console.log(failures ? `FAILED ${failures}` : 'ALL PASS');
process.exit(failures ? 1 : 0);
