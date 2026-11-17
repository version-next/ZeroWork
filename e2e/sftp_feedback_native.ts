/** Owned loopback acceptance for SFTP feedback, radio authentication and bidirectional drag.
 *
 * Current contract (usage-e2e-debt2 r2h):
 * - A saved host connects from the selected row's native “连接” (design-r3 A2, fe28ab5b: a row click only selects).
 * - A refused attempt shows the design-r3 稿 1 failure view (connection_failure.yix, 7cdc072f): title, Alert with the exact
 *   address, logs toggle, “立即重试”; Escape inside the view closes it (connection_progress_view.zig paneKey).
 * - The new-host editor opens from the sidebar footer (sidebar.footer.new, Island B v3 e1372d88) in its own native window;
 *   authentication is a native RadioGroup (wizard.auth) and the window is left with “取消” (no in-window close button).
 * - File cards: breadcrumb path whose blank end opens the path Input (4811ee5a); rows are virtual (row_height 26).
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { copyFile, mkdir, mkdtemp, open, readFile, realpath, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import * as h from '../zig-out/share/zenit/harness/client.ts';
const out = resolve(process.argv[2]);
await mkdir(out, { recursive: true });
const isolated = await realpath(await mkdtemp(join(tmpdir(), 'zerowork-sftp-feedback-')));
const data = join(isolated, 'data'), rpc = join(isolated, 'rpc'), local = join(isolated, 'local'), peerOut = join(out, 'peer');
await Promise.all([mkdir(data), mkdir(rpc), mkdir(local)]);
process.env.ZENIT_E2E_FILE_RPC_DIR = rpc;
const peerLog = await open(join(out, 'peer.log'), 'w'), appLog = await open(join(out, 'app.log'), 'w');
// Audited interpreter only (runner passes it for `python: true` entries); -I keeps cwd / user site out of sys.path.
assert(process.env.ZW_TEST_PYTHON, 'ZW_TEST_PYTHON (audited Python with paramiko) is required');
const peer = spawn(process.env.ZW_TEST_PYTHON, ['-I', resolve('e2e/sftp_v3_peer.py'), '--out', peerOut], { stdio: ['ignore', peerLog.fd, peerLog.fd] });
let app: ReturnType<typeof spawn> | undefined;
const report: any = { status: 'running', decisions: 0, checks: [], isolated, screenshots: [], external_hosts: 0 };
function shown(n: any) { return n?.rect?.w > 0 && n.rect.h > 0 && n.hidden !== true && n.visible !== false && (n.effective_opacity ?? 1) > 0; }
function nodes(n: any): any[] { return shown(n) ? [n, ...(n.children ?? []).flatMap(nodes)] : []; }
function text(n: any) { return nodes(n).map(n => n.text ?? '').join(' '); }
function inside(n: any, id: string) { return nodes(n).find(n => n.test_id === id); }
function alive() { assert(app && app.exitCode === null && app.signalCode === null, 'Owned app stays alive'); }
async function visible(id: string, ms = 15000) { return h.waitFor(async () => { alive(); return (await h.query(id)).find(shown) ?? null; }, ms); }
async function gone(id: string, ms = 10000) { return h.waitFor(async () => !(await h.query(id)).some(shown) || null, ms); }
async function clickNode(n: any) { assert(shown(n)); assert((await h.clickAt(n.rect.x + n.rect.w / 2, n.rect.y + n.rect.h / 2)).ok); }
async function click(id: string) { await clickNode(await visible(id)); }
async function capture(name: string) { await h.sleep(120); await h.screenshot(join(out, name + '.png')); report.screenshots.push(name + '.png'); }
/** A negative condition has to hold for the whole dwell window, not a single sample. */
async function stays(what: string, cond: () => Promise<boolean>, ms: number) { const t = Date.now(); do { assert(await cond(), what); await h.sleep(50); } while (Date.now() - t < ms); }
/** Real in-app mouse drag of a file row: the drag ghost must appear before moving on, the drop target preview before release. */
async function drag(from: any, x: number, y: number) {
  const handle = inside(from, 'files.row.drag') ?? from;
  const sx = handle.rect.x + Math.min(50, handle.rect.w / 2), sy = handle.rect.y + handle.rect.h / 2;
  assert((await h.mouseDown(sx, sy)).ok); assert((await h.mouseMove(sx + 12, sy)).ok);
  await visible('files.drag.ghost');
  assert((await h.mouseMove(x, y)).ok); await visible('files.drag.preview');
  assert((await h.mouseUp(x, y)).ok);
}
async function confirm() { const modal = await visible('files.copy.confirmation'); await capture('transfer-confirm-' + report.screenshots.length); const button = inside(modal, 'files.copy.submit'); assert(button, text(modal)); await clickNode(button); await gone('files.copy.confirmation'); }
/** Select a saved host row (click only selects), then connect it from the row's native “连接” button. */
async function connect(name: string) {
  const row = await h.waitFor(async () => (await h.query('sidebar.host')).find(n => shown(n) && text(n).includes(name)) ?? null, 15000);
  await h.clickAt(row.rect.x + 60, row.rect.y + row.rect.h / 2);
  const button = await h.waitFor(async () => inside((await h.query('sidebar.host')).find(n => n.id === row.id), 'sidebar.host.connect_button') ?? null, 10000);
  await clickNode(button);
}
/** Opens a file card's path Input (files.path). The path bar is a breadcrumb (files.path.edit › files.breadcrumb, file_workspace_view.zig):
 * its parts are buttons that navigate, any other point of the field starts editing. Click the blank end when the breadcrumb leaves one,
 * otherwise the separator between two visible parts. */
async function editPath(side: "local" | "remote"): Promise<any> {
  const card = await visible("files." + side), edit = inside(card, "files.path.edit"); assert(edit, "files.path.edit");
  const frame = inside(edit, "files.breadcrumb") ?? edit;
  const parts = nodes(edit).filter((n: any) => n.test_id === "files.path.part").sort((a: any, b: any) => a.rect.x - b.rect.x);
  const xs: number[] = [], last = parts.at(-1);
  if (!last || last.rect.x + last.rect.w < edit.rect.x + edit.rect.w - 12) xs.push(edit.rect.x + edit.rect.w - 6);
  for (let i = 1; i < parts.length; i++) { const m = (parts[i - 1].rect.x + parts[i - 1].rect.w + parts[i].rect.x) / 2; if (m > frame.rect.x + 2 && m < frame.rect.x + frame.rect.w - 2) xs.push(m); }
  assert(xs.length, "The path bar has a non-part point to start editing");
  assert((await h.clickAt(xs[0], edit.rect.y + edit.rect.h / 2)).ok, "Start editing the " + side + " path");
  const field = await h.waitFor(async () => inside(await visible("files." + side), "files.path") ?? null, 10000);
  await clickNode(field); return field;
}
/** Navigates a file card by typing into its path Input. */
async function goPath(side: "local" | "remote", path: string): Promise<void> {
  await editPath(side); assert((await h.key("a", { cmd: true })).ok); assert((await h.type_(path)).ok); assert((await h.key("return")).ok);
}
/** The card's location as the user reads it: “/” + the breadcrumb parts. */
async function location(side: "local" | "remote"): Promise<string> {
  const edit = inside(await visible("files." + side), "files.path.edit");
  return "/" + nodes(edit).filter((n: any) => n.test_id === "files.path.part").sort((a: any, b: any) => a.rect.x - b.rect.x).map((n: any) => text(n).trim()).join("/");
}
const failureView = async () => (await h.query('connection.progress.failure')).find(shown);
const retryReady = async () => (await h.query('connection.progress.failure.retry_now')).find(n => shown(n) && n.disabled !== true) ?? null;
const all = (n: any): any[] => n ? [n, ...(n.children ?? []).flatMap(all)] : [];
/** Selected choices of the native RadioGroup (zenit checkbox/radio.yix): the choices whose dot (the small square box inside
 * the circle) is not hidden. The dot follows the selection on the next frame, so callers wait for the expected set. */
async function authChoice() { return nodes(await visible('wizard.auth')).filter((c: any) => c.component === 'RadioChoice' && all(c).some(d => d !== c && d.rect?.w > 0 && d.rect.w === d.rect.h && d.rect.w < 12 && d.visible !== false)).map((c: any) => c.test_id); }
async function expectAuth(id: string) { await h.waitFor(async () => JSON.stringify(await authChoice()) === JSON.stringify([id]) || null, 5000).catch(async () => assert.deepEqual(await authChoice(), [id], 'Exactly one authentication radio is selected')); }
async function rememberChecked() { const n = await visible('wizard.password.remember'); const box = n.children?.[0], check = box?.children?.[0]; return shown(check); }
try {
  const ready = await h.waitFor(async () => { try { return JSON.parse(await readFile(join(peerOut, 'ready.json'), 'utf8')); } catch { return null; } }, 15000);
  const host = (id: number, name: string, port: number) => `\n[[hosts]]\nconnection_id=${id}\nrevision=1\nprotocol="sftp"\nauth_mode="password"\noptions={strict_host_key=true}\nname="${name}"\nhost="127.0.0.1"\nport=${port}\nuser="${ready.user}"\nauth={password="${ready.password}"}\n`;
  await writeFile(join(data, 'hosts.toml'), '[registry]\nschema_version=2\nrevision=1\nnext_connection_id=3\nnext_group_id=1\n' + host(1, 'SFTP Refused', 1) + host(2, 'SFTP Owned Peer', ready.port));
  await writeFile(join(data, 'config.toml'), '[meta]\nconfig_revision=1\n[ui]\ntheme="dark"\n');
  const payload = Buffer.from('SFTP drag upload verification\n');
  await writeFile(join(local, 'upload.txt'), payload);
  await mkdir(join(local, 'downloads'));
  for (let i = 0; i < 150; i++) await writeFile(join(local, `scroll-${String(i).padStart(3, '0')}.txt`), 'scroll fixture');
  const bundle = join(out, 'SFTP Feedback.app', 'Contents');
  await mkdir(join(bundle, 'MacOS'), { recursive: true });
  await writeFile(join(bundle, 'Info.plist'), '<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>zerowork</string><key>CFBundleIdentifier</key><string>local.zerowork.sftp.feedback</string><key>CFBundleName</key><string>SFTP Feedback</string><key>NSHighResolutionCapable</key><true/></dict></plist>');
  await copyFile(resolve(process.argv[3] ?? 'zig-out/bin/zerowork'), join(bundle, 'MacOS', 'zerowork'));
  await copyFile(resolve('zig-out/bin/zw_ipc.so'), join(out, 'zw_ipc.so'));
  app = spawn(join(bundle, 'MacOS', 'zerowork'), [], { env: { ...process.env, ZEROWORK_DATA_DIR: data, ZEROWORK_AUTOCONNECT: '0', ZENIT_E2E_BACKGROUND: '1', ZENIT_E2E_ISOLATE_POINTER: '1' }, stdio: ['ignore', appLog.fd, appLog.fd] });
  await h.waitForServerReady(); await h.resizeWindow(1440, 900);
  console.log('app ready');
  assert.equal((await h.query('sidebar.host')).filter(shown).length, 2);

  // 1. Refused TCP connection: failure view with the exact address, logs of the real attempt, explicit retry, Escape dismisses.
  await connect('SFTP Refused');
  const failed = await h.waitFor(async () => { const v = await failureView(); return v && await retryReady() ? v : null; }, 20000);
  assert.equal(text(inside(failed, 'connection.progress.failure.title')).trim(), '无法连接到 SFTP Refused');
  assert(text(inside(failed, 'connection.progress.failure.alert')).includes('127.0.0.1:1 拒绝连接'), 'The Alert names the refused address and port');
  assert(text(failed).includes(`${ready.user}@127.0.0.1:1`), 'Header shows user@host:port');
  // config.toml leaves auto reconnect at its default, but a refused SFTP open has no pending retry: the terminal action is 立即重试.
  assert(!inside(failed, 'connection.progress.failure.retry'), 'No automatic retry countdown is pending');
  await capture('connection-failed');
  await clickNode(inside(failed, 'connection.progress.failure.logs.toggle'));
  const logs1 = await h.waitFor(async () => { const l = inside(await failureView(), 'connection.progress.failure.logs'); return l && text(l).includes('连接被拒绝') ? l : null; }, 10000);
  assert(text(logs1).includes('尝试 1') && text(logs1).includes('127.0.0.1:1'), 'Logs are the real first attempt: ' + text(logs1));
  assert.equal(text(inside(await failureView(), 'connection.progress.failure.logs.toggle')).trim(), '收起日志');
  await capture('connection-failed-logs');
  await clickNode(await retryReady());
  // The retry is a second attempt of the same connection: its logs record 尝试 2 and it fails the same way.
  await h.waitFor(async () => {
    const v = await failureView(); if (!v || !(await retryReady())) return null;
    const l = inside(v, 'connection.progress.failure.logs');
    if (!l) { const toggle = inside(v, 'connection.progress.failure.logs.toggle'); if (toggle && text(toggle).includes('查看日志')) await clickNode(toggle); return null; }
    return text(l).includes('尝试 2') && text(l).includes('连接被拒绝') || null;
  }, 20000);
  assert.equal(text(inside(await failureView(), 'connection.progress.failure.title')).trim(), '无法连接到 SFTP Refused');
  await capture('connection-retry-failed');
  assert((await h.key('escape')).ok);
  await gone('connection.progress.failure');
  await stays('A dismissed failure stays dismissed', async () => !(await h.query('connection.progress')).some(shown) && !(await h.query('connection.progress.failure')).some(shown), 1000);
  console.log('checkpoint', report.checks.length + 1);
  report.checks.push('Actual refused TCP connection exposes failure address/logs of attempt 1; explicit retry is attempt 2 of the same connection; Escape dismisses and it stays dismissed');

  // 2. New-host editor: native authentication radios switch password / key / agent fields; 保存密码 starts checked.
  await click('sidebar.footer.new');
  assert.match(text(await visible('wizard.title')), /新建主机/);
  await visible('wizard.password');
  await expectAuth('wizard.auth.password');
  assert.equal(await rememberChecked(), true, '保存密码 defaults to checked');
  await capture('authentication-default-password');
  await click('wizard.auth.key'); await visible('wizard.key_path'); await gone('wizard.password');
  await expectAuth('wizard.auth.key');
  await click('wizard.auth.agent'); await visible('wizard.auth.agent_notice'); await gone('wizard.key_path');
  await expectAuth('wizard.auth.agent');
  await click('wizard.auth.password'); await visible('wizard.password'); await gone('wizard.auth.agent_notice');
  await expectAuth('wizard.auth.password');
  await capture('authentication-radios');
  await click('wizard.cancel'); await gone('wizard.title');
  assert.equal(await readFile(join(data, 'hosts.toml'), 'utf8').then(s => (s.match(/\[\[hosts\]\]/g) ?? []).length), 2, 'Cancelling the editor saves nothing');
  console.log('checkpoint', report.checks.length + 1);
  report.checks.push('Native radio choices switch password/key/agent fields; save password starts checked; cancel saves nothing');

  // 3. Owned peer: 150-file virtual list scrolls; real cross-pane drag uploads the exact bytes.
  await connect('SFTP Owned Peer');
  await h.waitFor(async () => {
    alive();
    if ((await h.query('files.workspace')).some(shown)) return true;
    const title = (await h.query('plugin.challenge.title')).find(shown), modal = (await h.query('plugin.challenge.modal')).find(shown);
    if (title && modal && (modal.effective_opacity ?? 1) >= 0.999) {
      if (text(title).includes('核对主机密钥')) { assert(text(await visible('plugin.challenge.material')).includes(ready.fingerprint)); await click('plugin.challenge.choice.0'); }
      else if (text(title).includes('SSH 密码认证')) { const field = (await h.query('plugin.challenge.answer.0')).find(shown) ?? await visible('plugin.challenge.secret'); await clickNode(field); await h.type_(ready.password); await click('plugin.challenge.submit'); }
      else throw new Error('Unexpected owned-peer challenge: ' + text(title));
      // Consecutive identical prompts (directory + transfer connection) reuse one modal; the loop re-reads it on every poll.
      assert(++report.decisions <= 6, 'Bound owned-peer trust/password decisions');
    }
    return null;
  }, 30000);
  await capture('sftp-connected');
  await goPath("local", local);
  await h.waitFor(async () => await location('local') === local && text(await visible('files.local')).includes('scroll-000.txt') || null, 15000);
  const pane = await visible('files.local');
  assert(!nodes(pane).some(n => n.test_id === 'files.row.name' && n.text === 'upload.txt'), 'The last row starts below the fold');
  // Scroll the virtual list until its last row (upload.txt sorts after scroll-149.txt) is mounted and visible inside the card.
  const upload = await h.waitFor(async () => {
    const card = await visible('files.local');
    const row = nodes(card).find(n => n.test_id === 'files.row.name' && n.text === 'upload.txt');
    if (row && row.rect.y >= card.rect.y && row.rect.y + row.rect.h <= card.rect.y + card.rect.h) return row;
    assert((await h.scrollAt(card.rect.x + card.rect.w / 2, card.rect.y + card.rect.h / 2, 0, -600)).ok);
    return null;
  }, 15000);
  assert(!nodes(await visible('files.local')).some(n => n.test_id === 'files.row.name' && n.text === 'scroll-000.txt'), 'Scrolled-out rows are recycled');
  await capture('file-list-scrolled');
  const remote = await visible('files.remote');
  await drag(nodes(await visible('files.local')).find(n => n.test_id === 'files.row' && inside(n, 'files.row.name')?.text === 'upload.txt') ?? upload, remote.rect.x + remote.rect.w / 2, remote.rect.y + remote.rect.h - 80);
  await confirm();
  await h.waitFor(async () => { const state = JSON.parse(await readFile(join(peerOut, 'state.json'), 'utf8')); return state.files['/fixture/upload.txt']?.bytes === payload.length || null; }, 15000);
  console.log('checkpoint', report.checks.length + 1);
  report.checks.push('150-file list scrolls through virtual rows and real cross-pane drag uploads exact source length');

  // 4. Real cross-pane drag download into an empty local directory.
  await goPath("local", join(local, 'downloads'));
  await h.waitFor(async () => await location('local') === join(local, 'downloads') && text(await visible('files.local')).includes('目录为空') || null, 15000);
  const download = await h.waitFor(async () => nodes(await visible('files.remote')).find(n => n.test_id === 'files.row' && inside(n, 'files.row.name')?.text === 'export.yaml') ?? null, 15000);
  const destination = await visible('files.local');
  await drag(download, destination.rect.x + destination.rect.w / 2, destination.rect.y + destination.rect.h - 80);
  await confirm();
  await h.waitFor(async () => { try { return (await readFile(join(local, 'downloads', 'export.yaml'), 'utf8')) === 'real: downloaded\n' || null; } catch { return null; } }, 15000);
  await h.waitFor(async () => nodes(await visible('files.local')).some(n => n.test_id === 'files.row.name' && n.text === 'export.yaml') || null, 15000);
  await capture('bidirectional-drag-complete');
  console.log('checkpoint', report.checks.length + 1);
  report.checks.push('Real cross-pane drag downloads exact remote bytes into the original local directory without crashing');
  alive();
  report.status = 'passed';
} catch (error) { report.status = 'failed'; report.error = String(error); try { await capture('failure'); } catch {} throw error; }
finally { if (app?.exitCode === null) app.kill('SIGTERM'); peer.kill('SIGTERM'); await h.sleep(300); await appLog.close(); await peerLog.close(); await writeFile(join(out, 'report.json'), JSON.stringify(report, null, 2)); }
