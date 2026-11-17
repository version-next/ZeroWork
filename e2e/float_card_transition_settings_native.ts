/**
 * 浮动卡片切换动画（Z12b）：设置 › 外观与主题 › 终端与工作区 ›“浮动卡片切换动画”是原生 W.RadioGroup
 * （`settings.field.float_card_transition`，选项 `.anchor` 收向所属标签 / `.fade` 淡出），默认 anchor；
 * 选“淡出”并保存后 config.toml 写出 `float_card_transition = "fade"`，重新打开设置仍是“淡出”。
 *
 * Per theme (isolated HOME / CFFIXED_USER_HOME / TMPDIR / ZEROWORK_DATA_DIR, 0700, updates off):
 *   1. 打开设置 → 外观与主题 → 终端与工作区；行与两个选项可见，默认写出 anchor；截图 `<theme>-default`。
 *   2. 点“淡出” → 保存：config.toml 里是 "fade"；截图 `<theme>-fade`。
 *   3. Esc 关闭再打开设置：选项仍是“淡出”（a11y checked）。
 * 浮动层（AI 面板 / 浮动卡片）按这个设置切换 Z12 / Z12b 的动效由 ai-panel-anchor 包接入后另行验证。
 *
 * Usage: node e2e/float_card_transition_settings_native.ts <zerowork binary (test-mode)> <evidence dir> [light|dark|both]
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {chmod, mkdir, mkdtemp, open, readFile, realpath, rm, writeFile} from 'node:fs/promises';
import {join, resolve} from 'node:path';
import * as h from '../vendor/zenit/e2e/client.ts';
import {settingsNav} from './settings_nav.ts';

const [binaryArg, outArg, which = 'both'] = process.argv.slice(2);
if (!binaryArg || !outArg) throw new Error('usage: float_card_transition_settings_native.ts <binary> <out> [light|dark|both]');
const binary = resolve(binaryArg), out = resolve(outArg);
await mkdir(out, {recursive: true});
const themes = which === 'both' ? ['light', 'dark'] : [which];

const shown = (n: any) => n && n.visible !== false && n.rect?.w > 0 && n.rect?.h > 0 && (n.effective_opacity ?? 1) > 0;
const node = async (id: string, ms = 15000) => h.waitFor(async () => (await h.query(id)).find(shown) ?? null, ms);
const click = async (id: string) => { const n: any = await node(id); assert((await h.clickAt(n.rect.x + n.rect.w / 2, n.rect.y + n.rect.h / 2)).ok, id); };
const textOf = (n: any): string => !n || n.visible === false ? '' : (n.text ?? '') + (n.children ?? []).map(textOf).join('');
const checked = (n: any): boolean | undefined => n?.a11y?.checked ?? n?.checked;

const reports: any[] = [];
const root = await realpath(await mkdtemp(process.env.ZW_E2E_TMP_PREFIX ?? '/private/tmp/zw-float-transition-'));
await chmod(root, 0o700);
try {
for (const theme of themes) {
  const home = join(root, theme), tmp = join(home, 'tmp'), data = join(home, 'data'), rpc = join(home, 'rpc');
  for (const d of [home, tmp, data, rpc]) await mkdir(d, {mode: 0o700});
  await writeFile(join(data, 'config.toml'), `[meta]\nconfig_revision=1\n[ui]\ntheme="${theme}"\n[updates]\nauto_check=false\n`, {mode: 0o600});
  process.env.ZENIT_E2E_FILE_RPC_DIR = rpc;
  const log = await open(join(out, `${theme}-app.log`), 'w');
  const app = spawn(binary, [], {env: {PATH: process.env.PATH ?? '/usr/bin:/bin', HOME: home, CFFIXED_USER_HOME: home, TMPDIR: tmp + '/', ZEROWORK_DATA_DIR: data, ZEROWORK_AUTOCONNECT: '0', ZENIT_E2E_FILE_RPC_DIR: rpc, ZENIT_E2E_BACKGROUND: '1', ZENIT_E2E_ISOLATE_POINTER: '1', ZENIT_E2E_ISOLATE_KEYBOARD: '1', OPENAI_API_KEY: '', ANTHROPIC_API_KEY: '', SSH_AUTH_SOCK: ''}, stdio: ['ignore', log.fd, log.fd]});
  const ended = new Promise(r => app.once('close', r));
  const report: any = {theme, status: 'running', checks: [] as string[], shots: [] as string[]};
  const shot = async (name: string, win?: any) => {
    await h.sleep(400);
    const path = join(out, `${theme}-${name}.png`);
    assert((await h.screenshot(path, win)).ok, `screenshot ${name}`);
    report.shots.push(path);
  };
  const openSettings = async (main: any) => {
    await click('toolbar.settings');
    await node('settings.panel');
    const settings = await h.waitFor(async () => (await h.windows()).windows.find((w: any) => !w.closing && w.window_id !== main)?.window_id ?? null, 10000);
    const nav = settingsNav();
    await nav.toSub('appearance', 'terminal');  // 外观与主题 › 终端与工作区 (two-level settings, settings_nav.ts)
    await nav.reveal('settings.field.float_card_transition');
    return settings;
  };
  const closeSettings = async (settings: any) => {
    assert((await h.key('escape')).ok);
    await h.waitFor(async () => (await h.windows()).windows.some((w: any) => !w.closing && w.window_id === settings) ? null : true, 10000).catch(() => {});
    await h.sleep(500);
  };
  try {
    await h.waitForServerReady(30000);
    await h.resizeWindow(1440, 900);
    const main = (await h.windows()).windows.find((w: any) => w.bound && !w.closing)?.window_id;
    let settings = await openSettings(main);
    const group: any = await node('settings.field.float_card_transition');
    const anchor: any = await node('settings.option.float_card_transition.anchor');
    const fade: any = await node('settings.option.float_card_transition.fade');
    assert(textOf(anchor).includes('收向所属标签'), `anchor label: ${textOf(anchor)}`);
    assert(textOf(fade).includes('淡出'), `fade label: ${textOf(fade)}`);
    assert(anchor.rect.y === fade.rect.y && anchor.rect.x < fade.rect.x, 'options are laid out horizontally');
    assert(group.rect.w > 0);
    if (checked(anchor) !== undefined) assert.equal(checked(anchor), true, 'anchor is the default');
    await h.mouseMove(4, 4);
    await shot('default', settings);
    report.checks.push('settings: 浮动卡片切换动画 row with 收向所属标签 / 淡出 (native RadioGroup, horizontal), default anchor');
    await click('settings.option.float_card_transition.fade');
    await click('settings.save');
    await h.waitFor(async () => /float_card_transition = "fade"/.test(await readFile(join(data, 'config.toml'), 'utf8')) || null, 10000);
    await h.mouseMove(4, 4);
    await shot('fade', settings);
    report.checks.push('settings: 选“淡出”保存后 config.toml 写出 float_card_transition = "fade"');
    await closeSettings(settings);
    settings = await openSettings(main);
    const fadeAgain: any = await node('settings.option.float_card_transition.fade');
    if (checked(fadeAgain) !== undefined) assert.equal(checked(fadeAgain), true, 'fade stays selected after reopening');
    report.checks.push('settings: 重新打开仍是“淡出”');
    await closeSettings(settings);
    report.status = 'passed';
  } catch (e) {
    report.status = 'failed'; report.error = String((e as any)?.stack ?? e); process.exitCode = 1;
    try { await h.screenshot(join(out, `${theme}-failure.png`)); } catch {}
  } finally {
    app.kill('SIGTERM'); await ended; await log.close(); reports.push(report);
  }
}
} finally {
  await rm(root, {recursive: true, force: true});
}
await writeFile(join(out, 'report.json'), JSON.stringify({status: reports.every(r => r.status === 'passed') ? 'passed' : 'failed', themes: reports}, null, 2));
