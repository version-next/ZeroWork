/** Real app idle audit: owned local AI, failed TCP connection and loopback SFTP. */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import {psCompat} from './ps_compat.ts';
import assert from 'node:assert/strict';
import {spawn, execFileSync} from 'node:child_process';
import {createServer} from 'node:http';
import {createServer as tcpServer} from 'node:net';
import {createHash} from 'node:crypto';
import {mkdir, mkdtemp, realpath, open, readFile, writeFile, rm} from 'node:fs/promises';
import {resolve, join} from 'node:path';
import {aiToggleId} from './ai_entry.ts';
import {readRequestJson} from './provider_fixture.ts';

const prefix = resolve(process.env.ZW_AI_TEST_PREFIX ?? 'zig-out');
const h = await import(join(prefix, 'share/zenit/harness/client.ts'));
const out = resolve(process.argv[2] ?? '/tmp/zw-ended-idle-results');
await mkdir(out, {recursive: true});
const iso = await realpath(await mkdtemp('/tmp/zw-ended-idle-'));
const data = join(iso, 'data'), rpc = join(iso, 'rpc'), peerOut = join(iso, 'peer');
await mkdir(data); await mkdir(rpc);
const pause = (ms: number) => new Promise(done => setTimeout(done, ms));
const shown = (n: any) => n && !n.hidden && n.visible !== false && (n.effective_opacity ?? 1) > 0 && n.rect?.w > 0 && n.rect?.h > 0;
const flat = (n: any): any[] => n ? [n, ...(n.children ?? []).flatMap(flat)] : [];
const text = (n: any) => flat(n).map(n => n.text ?? '').join(' ');
const visible = (id: string) => h.waitFor(async () => (await h.query(id)).find(shown) ?? null, 20000);
const click = async (id: string) => { const n = await visible(id); assert((await h.clickAt(n.rect.x + n.rect.w / 2, n.rect.y + n.rect.h / 2)).ok, id); };
const frame = (content: string) => 'data: ' + JSON.stringify({choices: [{index: 0, delta: {content}}]}) + '\n\n';
let mode = 'complete', held: any = null, stopStarted = false;
const server = createServer(async (req, res) => {
    if (req.method !== 'POST') { res.end(JSON.stringify({data: [{id: 'idle-model'}]})); return; }
    const body = await readRequestJson(req);
    if (body.messages[0]?.content?.startsWith('将用户的问题概括')) {
        res.writeHead(200, {'content-type': 'text/event-stream'}); res.end(frame('闲置检查') + 'data: [DONE]\n\n'); return;
    }
    if (mode === 'failed') { res.writeHead(400, {'content-type': 'application/json'}); res.end(JSON.stringify({error: {message: 'Idle audit rejected this request'}})); return; }
    res.writeHead(200, {'content-type': 'text/event-stream'});
    if (mode === 'stopped') { held = res; stopStarted = true; res.write(frame('部分答复，等待用户停止。')); return; }
    res.end(frame('答复完成，中文与 emoji 正常。🙂') + 'data: [DONE]\n\n');
});
await new Promise<void>(done => server.listen(0, '127.0.0.1', done));
const httpPort = (server.address() as any).port;
const unused = tcpServer(); await new Promise<void>(done => unused.listen(0, '127.0.0.1', done));
const failedPort = (unused.address() as any).port; await new Promise<void>(done => unused.close(() => done()));
const peerLog = await open(join(out, 'peer.log'), 'w');
// Audited interpreter only (runner passes it for `python: true` entries); -I keeps cwd / user site out of sys.path.
assert(process.env.ZW_TEST_PYTHON, 'ZW_TEST_PYTHON (audited Python with paramiko) is required');
const peer = spawn(process.env.ZW_TEST_PYTHON, ['-I', 'e2e/sftp_v3_peer.py', '--out', peerOut], {stdio: ['ignore', peerLog.fd, peerLog.fd]});
const peerExited = new Promise(done => peer.once('exit', done));
let app: any = null, appExited: Promise<any> | null = null;
const log = await open(join(out, 'app.log'), 'w');
const report: any = {status: 'running', checks: [], samples: [], limits: ['Owned loopback connections only; no existing SSH sessions or user data accessed', 'CPU is diagnostic; node identity and rendered frame deltas detect continuous refresh']};
try {
    const ready: any = await h.waitFor(async () => {
        assert(peer.exitCode === null, 'Owned SFTP peer exited');
        try { return JSON.parse(await readFile(join(peerOut, 'ready.json'), 'utf8')); } catch { return null; }
    }, 15000);
    const host = (id: number, name: string, protocol: string, port: number) => `[[hosts]]\nconnection_id=${id}\nrevision=1\nprotocol="${protocol}"\nauth_mode="password"\noptions={strict_host_key=true}\nname="${name}"\nhost="127.0.0.1"\nport=${port}\nuser="fixture"\nauth={password="fixture-only"}\n`;
    await writeFile(join(data, 'hosts.toml'), '[registry]\nschema_version=2\nrevision=1\nnext_connection_id=3\nnext_group_id=1\n' + host(1, 'Idle SFTP', 'sftp', ready.port) + host(2, 'Idle failed SSH', 'ssh', failedPort));
    await writeFile(join(data, 'config.toml'), `[meta]
config_revision=1
[ui]
theme="dark"
font_family="Menlo"
font_size=14
[ssh]
auto_reconnect=false
connect_timeout_sec=2
[transfer]
dedicated_connection=true
window_chunks=1
chunk_kb=32
max_tasks=1
verify_md5=false
[ai]
default_provider="idle"
[[ai.providers]]
id="idle"
kind="openai_compat"
endpoint="http://127.0.0.1:${httpPort}/v1/chat/completions"
enabled=true
[[ai.providers.models]]
name="idle-model"
context_window=200000
default=true
`);
    process.env.ZENIT_E2E_FILE_RPC_DIR = rpc;
    const env = {...process.env, ZENIT_E2E_FILE_RPC_DIR: rpc, ZEROWORK_DATA_DIR: data, ZEROWORK_AUTOCONNECT: '0', ZENIT_E2E_BACKGROUND: '1', ZENIT_E2E_ISOLATE_POINTER: '1', OPENAI_API_KEY: '', ANTHROPIC_API_KEY: ''};
    for (const name of ['ZEROWORK_AI_MOCK', 'ZEROWORK_AI_ENDPOINT', 'ZEROWORK_AI_MODEL', 'ZEROWORK_AI_PROVIDER']) delete env[name];
    app = spawn(join(prefix, 'bin/zerowork'), [], {env, stdio: ['ignore', log.fd, log.fd]});
    appExited = new Promise(done => app.once('exit', done));
    await h.waitForServerReady(60000);
    assert.equal(Number(JSON.parse(await readFile(join(rpc, 'owner.json'), 'utf8')).pid), app.pid);
    await h.resizeWindow(1440, 900);
    const cpuMs = () => psCompat(['-p', String(app.pid), '-o', 'time=']).trim().split(':').map(Number).reduce((sum, part) => sum * 60 + part, 0) * 1000;
    /** True once no frame has been rendered for `quietMs`; false if that never happens within `limitMs`. */
    async function framesQuiet(quietMs: number, limitMs: number): Promise<boolean> {
        let last = (await h.stats()).frame_count, since = performance.now();
        const end = since + limitMs;
        while (performance.now() < end) {
            await pause(100);
            const frames = (await h.stats()).frame_count;
            if (frames !== last) { last = frames; since = performance.now(); } else if (performance.now() - since >= quietMs) return true;
        }
        return false;
    }
    async function measure(name: string, id: string) {
        await h.mouseMove(4, 4);
        // Let completion receipts, discovery and transient overlays settle: wait (time bounded) until no frame has been rendered for
        // 1.5 s. A view that never goes quiet is exactly what the measurement below records, so the settle wait does not throw.
        report.settle = report.settle ?? {};
        report.settle[name] = await framesQuiet(1500, 15000);
        // The measured node set must have been unchanged for 1.25 s before sampling (time-bounded, not a poll count).
        let previous = '', since = performance.now();
        await h.waitFor(async () => {
            const current = JSON.stringify((await h.query(id)).filter(shown).map((n: any) => n.id));
            if (current !== previous) { previous = current; since = performance.now(); }
            return performance.now() - since >= 1250 || null;
        }, 10000);
        const nodes = (await h.query(id)).filter(shown).map((n: any) => n.id);
        assert(nodes.length > 0, `${name}: terminal state is visible`);
        const before = await h.stats(), start = performance.now(), cpu = cpuMs();
        await pause(3000); // Deliberately no harness traffic/frame waits.
        const cpuDeltaMs = cpuMs() - cpu, elapsedMs = performance.now() - start;
        const after = await h.stats(), afterNodes = (await h.query(id)).filter(shown).map((n: any) => n.id);
        const sample = {name, cpuPercent: 100 * cpuDeltaMs / elapsedMs, frameDelta: after.frame_count - before.frame_count, stableNodes: JSON.stringify(nodes) === JSON.stringify(afterNodes)};
        // Caret evidence (zenit runtime: a blinking caret is drawn by native caret flips once admitted, otherwise by ordinary frames).
        const caret = (st: any) => Object.fromEntries(['caret_flipping', 'caret_visible', 'caret_rect_count', 'caret_entries', 'caret_flips', 'caret_attempts', 'caret_gate_blocked', 'caret_admission_failures', 'caret_rejections'].map(k => [k, st[k]]));
        (sample as any).caret = {before: caret(before), after: caret(after)};
        report.samples.push(sample);
        if (sample.frameDelta > 2) {
            // Evidence for a failing sample: what holds focus and whether the redraw is periodic (per-second frame deltas).
            // Windows are silent (no harness traffic inside them): a periodic redraw scales with the window length.
            const diagnostic: any = {focused: await h.focused().catch((e: any) => String(e)), silentWindows: [], changed: []};
            // tree({visibleOnly}) — the full tree exceeds the harness result buffer.
            const leaves = async () => new Map<number, string>(flat(await h.tree({visibleOnly: true})).map((n: any) => [n.id, JSON.stringify([n.test_id, n.component, n.text, n.rect, n.effective_opacity, n.bg_rgba, n.world_transform])]));
            const first = await leaves();
            for (const ms of [1000, 6000]) { const a = (await h.stats()).frame_count; await pause(ms); diagnostic.silentWindows.push({ms, frames: (await h.stats()).frame_count - a}); }
            const second = await leaves();
            for (const [nodeId, value] of second) if (first.get(nodeId) !== value) diagnostic.changed.push({before: first.get(nodeId) ?? null, after: value});
            (sample as any).diagnostic = diagnostic;
        }
        if (sample.frameDelta > 2) execFileSync('/usr/bin/sample', [String(app.pid), '1', '1', '-file', join(out, name + '-sample.txt')], {stdio: 'ignore'});
        await h.screenshot(join(out, name + '.png'));
        if (sample.frameDelta <= 2 && sample.stableNodes && sample.cpuPercent < 40) report.checks.push(name);
    }
    const connect = async (name: string) => {
        const row = await h.waitFor(async () => (await h.query('sidebar.host')).find((n: any) => shown(n) && text(n).includes(name)) ?? null, 15000);
        // design-r3 A2 (src/features/shell/view/sidebar_host_connect.yix): a row click only selects; the selected row's native “连接” connects.
        assert((await h.clickAt(row.rect.x + 60, row.rect.y + row.rect.h / 2)).ok); await click('sidebar.host.connect_button');
    };
    if (!process.env.ZW_IDLE_TRANSFER_ONLY) {
        // Local terminal only: no user-owned SSH connection is selected.
        await click('toolbar.new_session'); await click('session.menu.local'); await visible('terminal.surface'); await click(await aiToggleId());
        let turns = 0;
        for (const state of ['complete', 'failed', 'stopped']) {
            mode = state;
            await click('ai.prompt'); await h.type_('检查结束状态 ' + state + ' 🙂'); await click('ai.send');
            if (state === 'stopped') { await h.waitFor(() => stopStarted || null, 15000); await click('ai.stop'); }
            turns += 1;
            await h.waitFor(async () => !(await h.query('ai.stop')).some(shown) && (await h.query('ai.turn.complete')).filter(shown).length === turns || null, 20000);
            if (state === 'failed') await visible('ai.recovery');
            await measure('ai-' + state, 'ai.message.user.row');
        }
        await click('ai.collapse');
        await connect('Idle failed SSH');
        // design-r3 稿 1 (connection_failure.yix): a failed attempt replaces the progress card with the failure view in the
        // session pane; auto_reconnect=false ⇒ no pending retry, “立即重试” is the terminal action. There is no 关闭 button
        // any more: Escape inside the pane closes the result (connection_progress_view.zig paneKey).
        await h.waitFor(async () => (await h.query('connection.progress.failure.retry_now')).find((n: any) => shown(n) && !n.disabled) ?? null, 30000);
        await measure('connection-failed-visible', 'connection.progress.failure');
        await click('connection.progress.failure.title'); await h.key('escape');
        await h.waitFor(async () => !(await h.query('connection.progress')).some(shown) || null, 10000);
    }
    await connect('Idle SFTP');
    await h.waitFor(async () => {
        if ((await h.query('files.workspace')).some(shown)) return true;
        const title = (await h.query('plugin.challenge.title')).find(shown);
        if (title) {
            if (text(title).includes('核对主机密钥')) await click('plugin.challenge.choice.0');
            else if (text(title).includes('SSH 密码认证')) {
                const input = (await h.query('plugin.challenge.answer.0')).find(shown) ?? await visible('plugin.challenge.secret');
                await h.clickAt(input.rect.x + 10, input.rect.y + 10); await h.type_(ready.password); await click('plugin.challenge.submit');
            } else throw Error('Unexpected challenge: ' + text(title));
        }
        return null;
    }, 30000);
    const payload = Buffer.from('Idle completion actual SFTP bytes.\n'.repeat(300)), path = join(iso, 'idle-upload.bin');
    await writeFile(path, payload);
    const remote = await visible('files.remote'), x = remote.rect.x + remote.rect.w / 2, y = remote.rect.y + remote.rect.h - 65;
    await h.dragAt(x, y, 0); await h.dragAt(x, y, 3, 'file://' + encodeURI(path)); await click('files.copy.submit');
    const sha256 = createHash('sha256').update(payload).digest('hex');
    await h.waitFor(async () => { try { const s = JSON.parse(await readFile(join(peerOut, 'state.json'), 'utf8')); return s.files['/fixture/idle-upload.bin']?.sha256 === sha256 || null; } catch { return null; } }, 30000);
    // Island B v3 has no bottom status bar (status.transfer stays unmounted from view): a finished upload's terminal state is its row
    // in the session's upload tray (transfer.session.tray, transfer_manager_view.zig), status "已完成 100%".
    const doneRow = async () => { const tray = (await h.query('transfer.session.tray')).find(shown); return tray && flat(tray).find((n: any) => n.test_id === 'transfer.task' && shown(n) && text(n).includes('idle-upload.bin') && /已完成 100%/.test(text(n))); };
    try { await h.waitFor(async () => await doneRow() ?? null, 15000); }
    catch (error) {
        // Evidence for the failure: does the row only catch up once unrelated input wakes the window?
        const tray = (await h.query('transfer.session.tray')).find(shown);
        report.stale_tray = {before_input: tray ? text(tray) : null};
        await h.mouseMove(700, 500); await h.mouseMove(720, 520);
        await h.waitFor(async () => await doneRow() ?? null, 3000).then(() => { report.stale_tray.after_input = 'completed row shown after pointer input'; }, () => { report.stale_tray.after_input = null; });
        throw new Error(`The completed upload (peer SHA-256 matched) never shows as 已完成 in the session tray: ${JSON.stringify(report.stale_tray)} (${error})`);
    }
    report.transfer = {bytes: payload.length, sha256, actualLoopbackUpload: true};
    const completed: any = await h.waitFor(async () => {
        const snapshot = await h.request('POST', '/zerowork/windows', {});
        return snapshot.tasks?.find((task: any) => task.state === 'succeeded' && task.cleanup === 'released') ?? null;
    }, 15000);
    report.transfer.cleanup = completed.cleanup;
    await measure('transfer-complete', 'transfer.session.tray');
    assert(await doneRow(), 'The completed upload row is still shown after the idle window');
    await click('toolbar.transfers'); await visible('transfer.manager');
    await measure('transfer-complete-list-open', 'transfer.task');
    assert.equal(report.samples.length, process.env.ZW_IDLE_TRANSFER_ONLY ? 2 : 6);
    report.status = report.checks.length === report.samples.length ? 'passed' : 'failed';
} catch (error) {
    report.status = 'failed'; report.error = String(error);
    await h.screenshot(join(out, 'failure.png')).catch(() => {});
} finally {
    if (held) held.end();
    server.closeAllConnections(); await new Promise<void>(done => server.close(() => done()));
    if (app && app.exitCode === null && app.signalCode === null) app.kill('SIGTERM');
    if (appExited) await appExited;
    if (peer.exitCode === null && peer.signalCode === null) peer.kill('SIGTERM');
    await peerExited;
    await log.close(); await peerLog.close(); await rm(iso, {recursive: true, force: true});
    await writeFile(join(out, 'report.json'), JSON.stringify(report, null, 2));
}
console.log(JSON.stringify(report, null, 2));
if (report.status !== 'passed') process.exitCode = 1;
