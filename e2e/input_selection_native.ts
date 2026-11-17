/** Text selection on production SSH/BMC editor fields, using isolated native windows.
 * node e2e/input_selection_native.ts BINARY OUT [theme[,theme…]]   (default: light,dark)
 *
 * Current contract (re-checked against source):
 * - A new host starts from `sidebar.empty.new` (empty sidebar); the connection editor is its own native window
 *   (`wizard.window`, wizard.zig window_spec 720×640). The protocol is the native Select `wizard.protocol` with options
 *   `wizard.protocol.<plugin id>` (wizard.zig protocol options: ssh, sftp, bmc_ikvm); SSH edits `wizard.name`, BMC · iKVM
 *   edits `bmc.editor.name`.
 * - Harness screenshots capture the key window, so pixels are mapped with the editor window's own scale
 *   (PNG width / `wizard.window` width), not the main window's.
 * - Pixels are decoded in-process (8-bit RGB(A) PNG; no Python / PIL dependency).
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdir, mkdtemp, open, readFile, realpath, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join, resolve} from 'node:path';
import {inflateSync} from 'node:zlib';
import * as h from '../vendor/zenit/e2e/client.ts';

const binary = resolve(process.argv[2]), out = resolve(process.argv[3]);
const themes = process.argv[4]?.split(',').filter(Boolean) ?? ['light', 'dark'];
for (const theme of themes) assert(['light', 'dark'].includes(theme), `unsupported theme ${theme}`);
await mkdir(out, {recursive: true});
const report: any = {status: 'running', binary, themes, cases: [], limits: 'Isolated storage and synthetic pointer/keys on real Metal windows; no network or real input method.'};
const shown = (n: any) => n && n.visible !== false && n.hidden !== true && (n.effective_opacity ?? 1) > 0 && n.rect?.w > 0 && n.rect?.h > 0;
const text = (n: any): string => (n?.text ?? '') + (n?.children ?? []).map(text).join('');
const visible = (id: string, ms = 10000) => h.waitFor(async () => (await h.query(id)).find(shown) ?? null, ms);
const gone = (id: string) => h.waitFor(async () => !(await h.query(id)).some(shown) || null, 8000);
async function click(id: string) { await visible(id); assert((await h.clickTestId(id)).ok, id); }

/** Decode an 8-bit non-interlaced RGB(A) PNG into {width, height, bpp, px}. */
function decodePng(png: Buffer) {
  let o = 8, w = 0, ht = 0, ct = 0, bd = 0; const idat: Buffer[] = [];
  while (o < png.length) {
    const len = png.readUInt32BE(o), type = png.toString('ascii', o + 4, o + 8), d = png.subarray(o + 8, o + 8 + len);
    if (type === 'IHDR') { w = d.readUInt32BE(0); ht = d.readUInt32BE(4); bd = d[8]; ct = d[9]; assert.equal(d[12], 0, 'interlaced PNG'); }
    else if (type === 'IDAT') idat.push(d); else if (type === 'IEND') break;
    o += 12 + len;
  }
  assert(bd === 8 && (ct === 6 || ct === 2), `unsupported PNG colour type ${ct} / depth ${bd}`);
  const bpp = ct === 6 ? 4 : 3, stride = w * bpp, raw = inflateSync(Buffer.concat(idat)), px = Buffer.alloc(stride * ht);
  for (let y = 0; y < ht; y++) {
    const f = raw[y * (stride + 1)], src = raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1)), row = px.subarray(y * stride, (y + 1) * stride), prev = y ? px.subarray((y - 1) * stride, y * stride) : null;
    for (let x = 0; x < stride; x++) {
      const a = x >= bpp ? row[x - bpp] : 0, up = prev ? prev[x] : 0, c = prev && x >= bpp ? prev[x - bpp] : 0; let v = src[x];
      if (f === 1) v += a; else if (f === 2) v += up; else if (f === 3) v += (a + up) >> 1;
      else if (f === 4) { const p = a + up - c, pa = Math.abs(p - a), pb = Math.abs(p - up), pc = Math.abs(p - c); v += pa <= pb && pa <= pc ? a : pb <= pc ? up : c; }
      row[x] = v & 255;
    }
  }
  return {width: w, height: ht, bpp, px, stride};
}
/** Pixels on a horizontal band 6 px above the field's text centre (above the glyph x-height) that changed by more than 24
 * in any channel between the focused-unselected and the selected capture, over the dragged span. Text and caret changes
 * alone cannot satisfy this: it proves the selection background was painted. */
function selectionBand(before: Buffer, after: Buffer, rect: any, windowWidth: number) {
  const a = decodePng(before), b = decodePng(after);
  assert(a.width === b.width && a.height === b.height, 'captures of the same window have the same size');
  const s = a.width / windowWidth, y = Math.round((rect.y + rect.h / 2 - 6) * s);
  let changed = 0;
  for (let x = Math.round((rect.x + 14) * s); x < Math.round((rect.x + 88) * s); x++) {
    const i = y * a.stride + x * a.bpp; let d = 0;
    for (let k = 0; k < 3; k++) d = Math.max(d, Math.abs(a.px[i + k] - b.px[i + k]));
    if (d > 24) changed++;
  }
  return {changed_background_pixels: changed, scale: s};
}

try {
  for (const theme of themes) {
    const iso = await realpath(await mkdtemp(join(tmpdir(), 'zw-input-selection-')));
    const data = join(iso, 'data'), rpc = join(iso, 'rpc');
    await mkdir(data); await mkdir(rpc); process.env.ZENIT_E2E_FILE_RPC_DIR = rpc;
    await writeFile(join(data, 'config.toml'), `[meta]\nconfig_revision=1\n[ui]\ntheme="${theme}"\n`);
    const log = await open(join(out, `${theme}.log`), 'w');
    const app = spawn(binary, [], {env: {...process.env, ZENIT_E2E_FILE_RPC_DIR: rpc, ZEROWORK_DATA_DIR: data, ZEROWORK_AUTOCONNECT: '0', ZENIT_E2E_BACKGROUND: '1', ZENIT_E2E_ISOLATE_POINTER: '1', ZENIT_E2E_ISOLATE_KEYBOARD: '1'}, stdio: ['ignore', log.fd, log.fd]});
    const ended = new Promise<number | null>(done => app.once('close', code => done(code)));
    try {
      await h.waitForServerReady(); await h.resizeWindow(1440, 900);
      await click('sidebar.empty.new');
      const frame = await visible('wizard.window');
      for (const protocol of ['ssh', 'bmc_ikvm']) {
        await click('wizard.protocol'); await click(`wizard.protocol.${protocol}`);
        await h.waitFor(async () => text((await h.query('wizard.protocol')).find(shown)).includes(protocol === 'ssh' ? 'SSH' : 'BMC') || null, 5000);
        const id = protocol === 'ssh' ? 'wizard.name' : 'bmc.editor.name';
        const value = 'https://172.20.3.225';
        await click(id); await h.key('a', {cmd: true}); await h.type_(value);
        await h.waitFor(async () => (await h.inputState(id)).buffer === value || null, 5000);
        // Collapse to a caret at the end (no selection) and move the pointer off the field so hover paint is out of both captures.
        await h.key('right'); await h.mouseMove(3, 3);
        await h.waitFor(async () => { const s = await h.inputState(id); return (s.anchor ?? -1) < 0 || s.anchor === s.cursor_pos || null; }, 3000);
        const field = await visible(id), rect = field.rect;
        const prefix = join(out, `${theme}-${protocol}`);
        await h.sleep(150);  // let the frame for the settled state present before capturing (paint settle; the state itself was waited for above)
        assert((await h.screenshot(prefix + '-before.png')).ok);
        const x = rect.x + 12, y = rect.y + rect.h / 2;
        assert((await h.mouseDown(x, y)).ok);
        for (let i = 1; i <= 12; i++) { await h.mouseMove(x + i * 7, y); }
        assert((await h.mouseUp(x + 84, y)).ok); await h.mouseMove(3, 3);
        const selection = await h.waitFor(async () => { const s = await h.inputState(id); return (s.anchor ?? -1) >= 0 && s.anchor !== s.cursor_pos ? s : null; }, 3000);
        assert.equal(selection.buffer, value, 'dragging does not edit the text');
        await h.sleep(150);
        assert((await h.screenshot(prefix + '-selected.png')).ok);
        const pixels = selectionBand(await readFile(prefix + '-before.png'), await readFile(prefix + '-selected.png'), rect, frame.rect.w);
        const result = {theme, protocol, rect, window: frame.rect, selection, pixels};
        report.cases.push(result); await writeFile(prefix + '.json', JSON.stringify(result, null, 2));
        assert(pixels.changed_background_pixels > 40 * pixels.scale, `Selected text background is indistinguishable from the focused field (${JSON.stringify(pixels)})`);
        // Replacing precisely the dragged range still uses the widget's editing path.
        const lo = Math.min(selection.anchor!, selection.cursor_pos), hi = Math.max(selection.anchor!, selection.cursor_pos);
        await h.type_('X');
        await h.waitFor(async () => (await h.inputState(id)).buffer === selection.buffer.slice(0, lo) + 'X' + selection.buffer.slice(hi) || null, 3000);
      }
      // Leave the editor through its own cancel (Escape = the window's close/cancel, wizard.zig windowKey); nothing is saved.
      await h.key('escape'); await gone('wizard.window');
      assert((await h.request('POST', '/quit')).ok);
      assert.equal(await Promise.race([ended, h.sleep(20000).then(() => 'timeout')]), 0, 'isolated App quits cleanly');
    } catch (error) {
      await h.screenshot(join(out, `${theme}-failure.png`)).catch(() => {});
      for (const id of ['sidebar.empty.new', 'wizard.window', 'wizard.protocol', 'bmc.editor'])
        await writeFile(join(out, `${theme}-${id}.json`), JSON.stringify(await h.query(id), null, 2)).catch(() => {});
      throw error;
    } finally {
      if (app.exitCode === null && app.signalCode === null) { app.kill('SIGTERM'); await Promise.race([ended, h.sleep(3000)]); if (app.exitCode === null && app.signalCode === null) { app.kill('SIGKILL'); await ended; } }
      await log.close(); await rm(iso, {recursive: true, force: true});
    }
  }
  report.status = 'passed';
} catch (error) { report.status = 'failed'; report.error = String(error); process.exitCode = 1; }
finally { await writeFile(join(out, 'report.json'), JSON.stringify(report, null, 2)); }
console.log(JSON.stringify({status: report.status, report: join(out, 'report.json'), error: report.error}));
