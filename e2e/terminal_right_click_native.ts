/**
 * Terminal right click (design-r3 B1, Pencil BZBAu): right click opens the native terminal menu at
 * the pointer; 设置 › 外观与主题 › 终端与工作区 ›“右键行为”switches back to direct paste.
 *
 * Per theme (isolated HOME / CFFIXED_USER_HOME / TMPDIR / ZDOTDIR / ZEROWORK_DATA_DIR, 0700, updates off):
 *   1. Local terminal and SSH terminal (loopback, see --ssh), each:
 *      a. right click with no selection → `terminal.menu` at the press point; rows 粘贴 / 查找… /
 *         复制 · 未选中内容/ 清屏 in that order, then 问 AI; screenshot `<theme>-<kind>-menu`.
 *      b. drag-select output, right click → 复制 is the first row; screenshot `<theme>-<kind>-menu-selection`.
 *      c. clipboard = a shell command; right click → click 粘贴 → Return: the command really ran
 *         (it writes a marker file), so the clipboard went into that terminal through the menu.
 *   2. Settings: 终端与工作区 › 右键行为 → 直接粘贴 → Save (config.toml `terminal_right_click = "paste"`);
 *      screenshot `<theme>-settings`.
 *   3. Local and SSH again: right click opens no menu and pastes directly (marker file again).
 *
 * --ssh=<ready.json> also checks an SSH terminal against a loopback peer {"port","user","password"|"key"},
 * e.g. `python3 e2e/ssh_nested_shell_peer.py --out <dir>` (Paramiko, real PTY zsh in an isolated HOME;
 * ZW_TEST_PYTHON must provide paramiko). Without it only the local terminal is checked.
 * The system pasteboard is used (as in other e2e scripts); its text is saved first and restored at the end.
 *
 * Usage: node e2e/terminal_right_click_native.ts <zerowork binary (test-mode)> <evidence dir> [light|dark|both] [--ssh=<fixture.json>]
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {chmod, mkdir, mkdtemp, open, readFile, realpath, rm, stat, writeFile} from 'node:fs/promises';
import {join, resolve} from 'node:path';
import * as h from '../vendor/zenit/e2e/client.ts';
import {settingsNav} from './settings_nav.ts';
import {pasteboardName, writePasteboardText} from './private_pasteboard.ts';

const args = process.argv.slice(2);
const sshArg = args.find(a => a.startsWith('--ssh='));
const withSsh = Boolean(sshArg);
const [binaryArg, outArg, which = 'both'] = args.filter(a => !a.startsWith('--'));
if (!binaryArg || !outArg) throw new Error('usage: terminal_right_click_native.ts <binary> <out> [light|dark|both] [--ssh=<fixture.json>]');
const binary = resolve(binaryArg), out = resolve(outArg);
await mkdir(out, {recursive: true});
const themes = which === 'both' ? ['light', 'dark'] : [which];

const shown = (n: any) => n && n.visible !== false && n.rect?.w > 0 && n.rect?.h > 0 && (n.effective_opacity ?? 1) > 0;
const node = async (id: string, ms = 15000) => h.waitFor(async () => (await h.query(id)).find(shown) ?? null, ms);
const gone = async (id: string, ms = 5000) => h.waitFor(async () => (await h.query(id)).some(shown) ? null : true, ms);
const click = async (id: string) => { const n: any = await node(id); assert((await h.clickAt(n.rect.x + n.rect.w / 2, n.rect.y + n.rect.h / 2)).ok, id); };
const press = async (x: number, y: number, button: 'left' | 'right') => {
  assert((await h.request('POST', '/mouse_down', {x, y, button})).ok);
  assert((await h.request('POST', '/mouse_up', {x, y, button})).ok);
};
const textOf = (n: any): string => !n || n.visible === false ? '' : (n.text ?? '') + (n.children ?? []).map(textOf).join('');
const exists = async (path: string) => { try { await stat(path); return true; } catch { return false; } };

// ── SSH loopback fixture ──
// sshd sandboxes its pre-auth child with sandbox_init, which cannot nest inside the offline
// sandbox-exec profile these runs use, so the peer is started outside it and described by a JSON
// file: {"port", "user", "password"} or {"port", "user", "key"} (client private key path) — e.g. the
// ready.json of e2e/ssh_nested_shell_peer.py (Paramiko, real PTY zsh in an isolated HOME).
let sshFixture: any = sshArg ? JSON.parse(await readFile(sshArg.slice('--ssh='.length), 'utf8')) : null;

const reports: any[] = [];
const root = await realpath(await mkdtemp(process.env.ZW_E2E_TMP_PREFIX ?? '/private/tmp/zw-right-click-'));
await chmod(root, 0o700);
// The app's clipboard is the run's private pasteboard (e2e/private_pasteboard.ts): the paste source is put there, the
// person's clipboard is never read or written.
const pasteboard = pasteboardName();
try {

for (const theme of themes) {
  const home = join(root, theme), tmp = join(home, 'tmp'), data = join(home, 'data'), rpc = join(home, 'rpc'), zdot = join(home, 'zdot'), marks = join(home, 'marks');
  for (const d of [home, tmp, data, rpc, zdot, marks]) await mkdir(d, {mode: 0o700});
  await writeFile(join(zdot, '.zshrc'), "PROMPT='local app $ '\nHISTFILE=/dev/null\nunsetopt BEEP\n", {mode: 0o600});
  await writeFile(join(data, 'config.toml'), `[meta]\nconfig_revision=1\n[ui]\ntheme="${theme}"\n[ssh]\nauto_reconnect=false\n[updates]\nauto_check=false\n`, {mode: 0o600});
  if (sshFixture) await writeFile(join(data, 'hosts.toml'), `[registry]\nschema_version=2\nrevision=1\nnext_connection_id=2\nnext_group_id=1\n[[hosts]]\nconnection_id=1\nrevision=1\nprotocol="ssh"\nauth_mode="${sshFixture.password ? 'password' : 'private_key'}"\noptions={strict_host_key=true}\nname="prod-web-01"\nhost="127.0.0.1"\nport=${sshFixture.port}\nuser="${sshFixture.user}"\nauth={${sshFixture.password ? `password=${JSON.stringify(sshFixture.password)}` : `key=${JSON.stringify(sshFixture.key)}`}}\n`, {mode: 0o600});
  process.env.ZENIT_E2E_FILE_RPC_DIR = rpc;
  const log = await open(join(out, `${theme}-app.log`), 'w');
  const app = spawn(binary, [], {env: {PATH: process.env.PATH ?? '/usr/bin:/bin', HOME: home, CFFIXED_USER_HOME: home, TMPDIR: tmp + '/', ZDOTDIR: zdot, ZEROWORK_DATA_DIR: data, ZEROWORK_AUTOCONNECT: '0', ZENIT_E2E_FILE_RPC_DIR: rpc, ZENIT_E2E_BACKGROUND: '1', ZENIT_E2E_ISOLATE_POINTER: '1', ZENIT_E2E_ISOLATE_KEYBOARD: '1', ZENIT_E2E_PASTEBOARD: pasteboard, OPENAI_API_KEY: '', ANTHROPIC_API_KEY: '', SSH_AUTH_SOCK: ''}, stdio: ['ignore', log.fd, log.fd]});
  const ended = new Promise(r => app.once('close', r));
  const report: any = {theme, status: 'running', ssh: Boolean(sshFixture), checks: [] as string[], shots: [] as string[], menus: {} as Record<string, any>};
  let main: any;
  const shot = async (name: string, win?: any) => {
    await h.sleep(350);
    const path = join(out, `${theme}-${name}.png`);
    assert((await h.screenshot(path, win)).ok, `screenshot ${name}`);
    report.shots.push(path);
  };
  /** The visible terminal of the active tab (Surface for Local, legacy view for SSH). */
  const terminal = async () => h.waitFor(async () => {
    for (const id of ['terminal.surface', 'terminal.input']) { const n = (await h.query(id)).find(shown); if (n && n.rect.w > 200 && n.rect.h > 100) return n; }
    return null;
  }, 20000);
  /** 问 AI lives only in the SSH terminal menu (the Local menu never had it); it must follow 清屏 there. */
  const menuRows = async (kind: string) => {
    const panel: any = await node('terminal.menu');
    const ids = kind === 'ssh' ? ['paste', 'search', 'copy', 'clear_screen', 'ask_ai'] : ['paste', 'search', 'copy', 'clear_screen', 'command_history'];
    const rows: Record<string, any> = {};
    for (const id of ids) rows[id] = await node('terminal.menu.' + id);
    return {panel, rows};
  };
  const runMarker = async (kind: string, step: string, how: 'menu' | 'direct') => {
    const marker = join(marks, `${kind}-${step}`);
    await writePasteboardText(`printf ok > ${marker}`, pasteboard);
    const t: any = await terminal();
    const x = t.rect.x + t.rect.w * 0.6, y = t.rect.y + t.rect.h * 0.6;
    await press(x, y, 'right');
    if (how === 'menu') {
      await node('terminal.menu');
      await click('terminal.menu.paste');
      await gone('terminal.menu');
    } else {
      await h.sleep(600);
      assert(!(await h.query('terminal.menu')).some(shown), `${kind}: direct paste mode must not open the menu`);
    }
    await h.sleep(300);
    assert((await h.key('return')).ok);
    await h.waitFor(async () => (await exists(marker)) || null, 15000);
    assert.equal(await readFile(marker, 'utf8'), 'ok');
    report.checks.push(`${kind}: right click (${how}) pasted the clipboard into this terminal and the shell ran it`);
  };
  const menuChecks = async (kind: string) => {
    const t: any = await terminal();
    // Some output to select.
    await h.clickAt(t.rect.x + t.rect.w / 2, t.rect.y + t.rect.h - 30);
    await h.type_("printf 'Last login: Sun Oct 25 10:18:32 2026 from 10.0.0.8\\ndrwxr-xr-x  4 deploy deploy 4.0K current/\\n'");
    await h.key('return');
    await h.sleep(800);
    // a. no selection
    const px = t.rect.x + Math.min(520, t.rect.w * 0.45), py = t.rect.y + Math.min(260, t.rect.h * 0.5);
    await h.clickAt(px, py);
    await h.sleep(200);
    await press(px, py, 'right');
    const empty = await menuRows(kind);
    assert(Math.abs(empty.panel.rect.x - px) <= 2, `${kind}: menu opens at the pointer x (${empty.panel.rect.x} vs ${px})`);
    assert(empty.panel.rect.y >= py - 1 && empty.panel.rect.y <= py + 12, `${kind}: menu opens at the pointer y (${empty.panel.rect.y} vs ${py})`);
    const r = empty.rows;
    assert(r.paste.rect.y < r.search.rect.y && r.search.rect.y < r.copy.rect.y && r.copy.rect.y < r.clear_screen.rect.y && r.clear_screen.rect.y < (r.ask_ai ?? r.command_history).rect.y, `${kind}: B1 order without a selection`);
    report.menus[kind] = {panel: empty.panel.rect, point: {x: px, y: py}};
    await h.mouseMove(px - 40, py - 40);
    await shot(`${kind}-menu`, main);
    assert((await h.key('escape')).ok);
    await gone('terminal.menu');
    report.checks.push(`${kind}: right click opens terminal.menu at the press point; 粘贴 / 查找… / 复制 · 未选中内容/ 清屏, then the other terminal-menu rows (问 AI on SSH)`);
    // b. selection: drag across the first output lines.
    const sx = t.rect.x + 40, sy = t.rect.y + 30;
    await h.mouseMove(sx, sy);
    assert((await h.request('POST', '/mouse_down', {x: sx, y: sy, button: 'left'})).ok);
    for (let i = 1; i <= 6; i++) await h.mouseMove(sx + i * 60, sy + i * 6);
    assert((await h.request('POST', '/mouse_up', {x: sx + 360, y: sy + 36, button: 'left'})).ok);
    await h.sleep(300);
    await press(px, py, 'right');
    const selected = await menuRows(kind);
    assert(selected.rows.copy.rect.y < selected.rows.paste.rect.y, `${kind}: 复制 leads with a selection`);
    await h.mouseMove(px - 40, py - 40);
    await shot(`${kind}-menu-selection`, main);
    assert((await h.key('escape')).ok);
    await gone('terminal.menu');
    report.checks.push(`${kind}: with a selection 复制 is the first row`);
    // c. paste through the menu.
    await h.clickAt(px, py);
    await runMarker(kind, 'menu', 'menu');
  };
  try {
    await h.waitForServerReady(30000);
    await h.resizeWindow(1440, 900);
    main = (await h.windows()).windows.find((w: any) => w.bound && !w.closing)?.window_id;
    await click('workspace.empty.local');
    await node('terminal.surface');
    await h.sleep(1500);
    await menuChecks('local');
    if (sshFixture) {
      // Single click selects the host; its row then shows the connect button (design-r3 A2).
      await click('sidebar.host');
      await h.sleep(300);
      if ((await h.query('sidebar.host.connect')).some(shown)) await click('sidebar.host.connect');
      // First connection: trust the throwaway loopback host key once.
      await h.waitFor(async () => {
        // Host-key prompt: 仅本次信任 (`plugin.challenge.choice.0` in the plugin presenter, or the legacy auth view).
        const trust = (await h.query('plugin.challenge.choice.0')).find(shown) ?? (await h.query('auth.challenge.trust_once')).find(shown);
        if (trust) { await h.clickAt(trust.rect.x + trust.rect.w / 2, trust.rect.y + trust.rect.h / 2); return null; }
        if ((await h.query('connection.progress')).some(shown) || (await h.query('auth.challenge.modal')).some(shown) || (await h.query('plugin.challenge.modal')).some(shown)) return null;
        return textOf((await h.query('workspace.pane')).find(shown)).includes('fixture>') || null;
      }, 45000, 150);
      await h.sleep(2000);
      await menuChecks('ssh');
    }
    // Settings: 终端与工作区 › 右键行为 → 直接粘贴.
    await click('toolbar.settings');
    await node('settings.panel');
    const settings = await h.waitFor(async () => (await h.windows()).windows.find((w: any) => !w.closing && w.window_id !== main)?.window_id ?? null, 10000);
    const nav = settingsNav();
    await nav.toSub('appearance', 'terminal');  // two-level settings (settings_nav.ts)
    await nav.reveal('settings.field.terminal_right_click');
    await click('settings.option.terminal_right_click.paste');
    await click('settings.save');
    await h.waitFor(async () => /terminal_right_click = "paste"/.test(await readFile(join(data, 'config.toml'), 'utf8')) || null, 10000);
    await h.mouseMove(4, 4);
    await shot('settings', settings);
    report.checks.push('settings: 右键行为 radio (弹出菜单 / 直接粘贴) saves terminal_right_click = "paste" to config.toml');
    // The preferences window closes on Escape (it has no close button of its own).
    assert((await h.key('escape')).ok);
    await h.waitFor(async () => (await h.windows()).windows.some((w: any) => !w.closing && w.window_id === settings) ? null : true, 10000).catch(() => {});
    await h.sleep(500);
    // Direct paste on both terminals.
    if (sshFixture) await runMarker('ssh', 'direct', 'direct');
    const localTab = (await h.query('tabs.title')).filter(shown)[0];
    await h.clickAt(localTab.rect.x + localTab.rect.w / 2, localTab.rect.y + localTab.rect.h / 2);
    await h.sleep(800);
    await runMarker('local', 'direct', 'direct');
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
await writeFile(join(out, 'report.json'), JSON.stringify({status: reports.every(r => r.status === 'passed') ? 'passed' : 'failed', ssh: withSsh, themes: reports}, null, 2));
console.log(JSON.stringify(reports.map(r => ({theme: r.theme, status: r.status, ssh: r.ssh, checks: r.checks.length, error: r.error}))));
