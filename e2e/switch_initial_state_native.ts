/**
 * Regression: a Switch that is already on must appear at rest in the "on" position, and a toggle
 * must slide the thumb smoothly (translate only, no layout jump).
 *
 *   node e2e/switch_initial_state_native.ts BINARY OUTPUT_DIR [light|dark] [--material]
 *
 * Bug: the settings rows re-pinned the zenit Switch thumb with an inline `inset.left` plus
 * `translate_x = 0`; the recipe's 200 ms translate-x transition then ran 20 → 0 while the layout
 * jumped to inset 20, so a default-on switch slid in from 40 → 20 on first paint and every toggle
 * snapped the layout instead of sliding.
 *
 * Samples the thumb offset (thumb x − track x, i.e. layout + translate) of
 * `settings.field.auto_reconnect` (SSH › 断线重连, default on) from the first frame the page is
 * visible for ≥ 400 ms, then toggles it off and on again, and checks a default-off switch
 * (`settings.field.compression`, SSH › 连接). Then the appearance pane (外观与主题 › 终端与工作区,
 * zenit sm Switch): `settings.toggle.command_info` (default on) appears at rest at 16; toggled off
 * and on the same node must slide (S-11 fixed: the `.yix` pane updates by signal, no remount);
 * `settings.toggle.timestamp_gutter` (default off)
 * rests at 2. `--material` starts with a tiled wallpaper and
 * material transparency 50 so the same checks run with the material layers on.
 * Isolated data dir, `[updates] auto_check=false`, background window + isolated pointer.
 */
import assert from 'node:assert/strict';
import {writeFile} from 'node:fs/promises';
import {join, resolve} from 'node:path';
import {deflateSync} from 'node:zlib';
import * as h from '../vendor/zenit/e2e/client.ts';
import {launchIsolated, settingsNav, shown} from './settings_nav.ts';

const args = process.argv.slice(2);
const material = args.includes('--material');
const [binaryArg, outArg, themeArg] = args.filter(a => !a.startsWith('--'));
if (!binaryArg || !outArg) throw new Error('usage: switch_initial_state_native.ts BINARY OUTPUT_DIR [light|dark] [--material]');
const binary = resolve(binaryArg), out = resolve(outArg), theme = themeArg ?? 'light';

// md Switch: track 40, thumb 18, 2 px inset at both ends.
const ON = 20, OFF = 2, EPS = 0.5;
// sm Switch (appearance pane): track 32, thumb 14 → on rest 16.
const SM_ON = 16;

function crc32(bytes: Buffer) {
  let crc = 0xffffffff;
  for (const byte of bytes) { crc ^= byte; for (let i = 0; i < 8; i++) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0); }
  return (crc ^ 0xffffffff) >>> 0;
}
function chunk(kind: string, bytes: Buffer) {
  const type = Buffer.from(kind), size = Buffer.alloc(4), crc = Buffer.alloc(4);
  size.writeUInt32BE(bytes.length); crc.writeUInt32BE(crc32(Buffer.concat([type, bytes])));
  return Buffer.concat([size, type, bytes, crc]);
}
function checkerPng() {
  const width = 240, height = 160, raw = Buffer.alloc(height * (1 + width * 4));
  for (let y = 0; y < height; y++) for (let x = 0; x < width; x++) {
    const color = ((x / 20 | 0) + (y / 20 | 0)) % 2 ? [242, 192, 65] : [71, 129, 232];
    raw.set([...color, 255], y * (1 + width * 4) + 1 + x * 4);
  }
  const header = Buffer.alloc(13); header.writeUInt32BE(width); header.writeUInt32BE(height, 4); header[8] = 8; header[9] = 6;
  return Buffer.concat([Buffer.from('89504e470d0a1a0a', 'hex'), chunk('IHDR', header), chunk('IDAT', deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]);
}

type Sample = {t: number, offset: number, translate: number, layout: number, width: number, node: number};
const thumbOf = (n: any): Sample | null => {
  const track = n?.children?.[0], thumb = track?.children?.[0];
  if (!shown(n) || !track?.rect || !thumb?.rect) return null;
  const offset = thumb.rect.x - track.rect.x, translate = thumb.translate_x ?? 0;
  return {t: 0, offset, translate, layout: offset - translate, width: track.rect.w, node: n.id};
};
/** Query `id` back to back for `ms` after its first visible sample; `withPrior` keeps the state seen just before `before`. */
async function sample(id: string, ms: number, before?: () => Promise<unknown>, withPrior = false) {
  const rows: Sample[] = [];
  if (withPrior) { const prior = thumbOf((await h.query(id)).find(shown)); assert(prior, `${id}: not visible before the action`); rows.push({...prior, t: -1}); }
  if (before) await before();
  const start = Date.now();
  let first = -1;
  while (Date.now() - start < 8000) {
    const s = thumbOf((await h.query(id)).find(shown));
    const now = Date.now();
    if (!s) { if (first < 0) continue; else break; }
    if (first < 0) first = now;
    rows.push({...s, t: now - first});
    if (now - first >= ms) break;
  }
  assert(rows.length > 0, `${id}: never visible`);
  return rows;
}
const fmt = (rows: Sample[]) => rows.map(r => `#${r.node} ${r.t}ms:${r.offset.toFixed(2)}(layout ${r.layout.toFixed(2)} + tx ${r.translate.toFixed(2)})`).join(' ');

function expectRest(label: string, rows: Sample[], rest: number) {
  const bad = rows.filter(r => Math.abs(r.offset - rest) > EPS);
  assert.equal(bad.length, 0, `${label}: thumb must sit at rest offset ${rest} from the first sample; got ${fmt(rows)}`);
  assert(rows[rows.length - 1].t >= 400, `${label}: sampling covered only ${rows[rows.length - 1].t} ms`);
}
function expectSlide(label: string, rows: Sample[], from: number, to: number) {
  const layouts = rows.map(r => r.layout);
  assert(Math.max(...layouts) - Math.min(...layouts) <= EPS, `${label}: layout position must not jump (translate only); got ${fmt(rows)}`);
  const dir = Math.sign(to - from);
  for (let i = 1; i < rows.length; i++) assert((rows[i].offset - rows[i - 1].offset) * dir >= -EPS, `${label}: offset must move monotonically ${from} → ${to}; got ${fmt(rows)}`);
  const mids = new Set(rows.filter(r => (r.offset - Math.min(from, to)) > EPS && (Math.max(from, to) - r.offset) > EPS).map(r => r.offset.toFixed(1)));
  assert(mids.size >= 2, `${label}: expected ≥ 2 intermediate positions between ${from} and ${to}; got ${fmt(rows)}`);
  assert(Math.abs(rows[rows.length - 1].offset - to) <= EPS, `${label}: must settle at ${to}; got ${fmt(rows)}`);
}

let config = '';
if (material) {
  const {mkdtemp, realpath} = await import('node:fs/promises');
  const dir = await realpath(await mkdtemp('/private/tmp/zw-switch-wallpaper-'));
  const image = join(dir, 'checker.png');
  await writeFile(image, checkerPng());
  config = `[ui.materials]\nblur_px=0\n[ui.materials.background]\nenabled=true\npath=${JSON.stringify(image)}\nfit="tile"\ntransparency=50\n`;
}
const session = await launchIsolated({binary, out, prefix: 'zw-switch-initial', theme, config});
const report: Record<string, unknown> = {theme, material};
const failures: string[] = [];
const check = (name: string, fn: () => void) => { try { fn(); report[name + '.ok'] = true; } catch (e: any) { report[name + '.ok'] = false; failures.push(e.message); console.error('FAIL', e.message); } };
try {
  await h.resizeWindow(1440, 900);
  const nav = settingsNav();
  // Raw click (no settle sleep) so sampling starts on the first visible frame.
  const tap = async (target: string) => { const n = await nav.node(target); assert((await h.clickAt(n.rect.x + n.rect.w / 2, n.rect.y + n.rect.h / 2)).ok, target); };
  // The first toolbar click can land before the wallpaper layers settle; retry opening the window.
  for (let i = 0; i < 4 && !(await nav.visible('settings.panel')); i++) { await tap('toolbar.settings'); await nav.node('settings.panel', 3000).catch(() => null); }
  await nav.toCategory('ssh');
  // First appearance of a default-on switch.
  const id = 'settings.field.auto_reconnect';
  const appear = await sample(id, 450, () => tap('settings.overview.ssh.reconnect'));
  report.appear = appear;
  check('appear', () => expectRest('first appearance (on)', appear, ON));
  await h.sleep(300);
  const node = await nav.reveal(id);
  check('geometry', () => { assert.equal(Math.round(node.rect.w), 40); assert.equal(Math.round(node.rect.h), 22); });
  const cx = node.rect.x + node.rect.w / 2, cy = node.rect.y + node.rect.h / 2;
  // A user reaches the switch with the pointer before pressing it: hover, then click.
  const press = async () => { await h.mouseMove(cx, cy); await h.sleep(60); assert((await h.clickAt(cx, cy)).ok); };
  const off = await sample(id, 450, press, true);
  report.toggleOff = off;
  check('toggle-off', () => expectSlide('toggle on → off', off, ON, OFF));
  await h.screenshot(join(out, `reconnect-off-${theme}${material ? '-material' : ''}.png`));
  await h.sleep(200);
  const on = await sample(id, 450, press, true);
  report.toggleOn = on;
  check('toggle-on', () => expectSlide('toggle off → on', on, OFF, ON));
  // A click that lands after the window has been idle ≥ ~1 s with no pointer movement must still
  // animate (zenit G22, fixed upstream in 92e8f8e1: the event-time hit refresh keeps the event clock).
  for (const [label, from, to] of [['idle toggle on → off', ON, OFF], ['idle toggle off → on', OFF, ON]] as const) {
    await h.sleep(1500);
    const rows = await sample(id, 450, async () => { assert((await h.clickAt(cx, cy)).ok); }, true);
    (report.idleClick ??= {} as any)[label] = rows;
    try { expectSlide(label, rows, from, to); (report as any).idleClickAnimates = true; }
    catch (e: any) {
      (report as any).idleClickAnimates = false;
      failures.push(e.message); console.error('FAIL', e.message);
    }
  }
  await h.screenshot(join(out, `reconnect-${theme}${material ? '-material' : ''}.png`));
  // Remount: leave and come back; still at rest from the first frame.
  await nav.back(); await nav.node('settings.overview');
  const again = await sample(id, 450, () => tap('settings.overview.ssh.reconnect'));
  report.remount = again;
  check('remount', () => expectRest('remount (on)', again, ON));
  // A default-off switch.
  await nav.back(); await nav.node('settings.overview');
  const offId = 'settings.field.compression';
  const offAppear = await sample(offId, 450, () => tap('settings.overview.ssh.connection'));
  report.offAppear = offAppear;
  check('appear-off', () => expectRest('first appearance (off)', offAppear, OFF));
  // 外观与主题 › 终端与工作区: the appearance pane's switches are zenit sm Switches (track 32 × 18,
  // thumb 14): 命令信息 (default on) appears at rest, slides off and on; 时间戳侧栏 (default off) rests at 2.
  // S-11 fixed (P3 3e appearance pane in .yix): a draft change no longer remounts the pane, so the same node must slide.
  await nav.toCategory('appearance');
  const apId = 'settings.toggle.command_info';
  const apAppear = await sample(apId, 450, () => tap('settings.overview.appearance.terminal'));
  report.appearanceAppear = apAppear;
  check('appearance-appear', () => expectRest('appearance first appearance (on)', apAppear, SM_ON));
  await h.sleep(300);
  const apNode = await nav.reveal(apId);
  check('appearance-geometry', () => { assert.equal(Math.round(apNode.rect.w), 32); assert.equal(Math.round(apNode.rect.h), 18); });
  const ax = apNode.rect.x + apNode.rect.w / 2, ay = apNode.rect.y + apNode.rect.h / 2;
  const apPress = async () => { await h.mouseMove(ax, ay); await h.sleep(60); assert((await h.clickAt(ax, ay)).ok); };
  const apOff = await sample(apId, 450, apPress, true);
  report.appearanceToggleOff = apOff;
  check('appearance-toggle-off', () => expectSlide('appearance toggle on → off', apOff, SM_ON, OFF));
  await h.screenshot(join(out, `appearance-off-${theme}${material ? '-material' : ''}.png`));
  await h.sleep(200);
  const apOn = await sample(apId, 450, apPress, true);
  report.appearanceToggleOn = apOn;
  check('appearance-toggle-on', () => expectSlide('appearance toggle off → on', apOn, OFF, SM_ON));
  const gutter = await sample('settings.toggle.timestamp_gutter', 450);
  report.appearanceOff = gutter;
  check('appearance-off', () => expectRest('appearance default-off', gutter, OFF));
} catch (e) {
  await writeFile(join(out, "tree.json"), JSON.stringify(await h.tree({ visibleOnly: true }).catch(err => String(err)), null, 1)).catch(() => {});
  await h.screenshot(join(out, "failure.png")).catch(() => {});
  await writeFile(join(out, "windows.json"), JSON.stringify(await h.windows().catch(err => String(err)))).catch(() => {});
  throw e;
} finally {
  await writeFile(join(out, 'report.json'), JSON.stringify(report, null, 1));
  await session.stop();
}
if (failures.length) { console.error(`switch_initial_state_native: ${failures.length} failure(s)`); process.exit(1); }
console.log(`switch_initial_state_native: ok (${theme}${material ? ', material' : ''})`);
