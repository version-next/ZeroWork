/**
 * host.tab_context（PLUGIN_ARCH_PLAN 2.5.8 M11）：模拟模型调用内置工具，断言返回的卡片条目与当前 tab 一致。
 *
 * - 单卡本机终端 tab：概览只有一张 terminal 卡片，card_ref 就是系统提示里该会话的 session_ref，
 *   摘要含刚在终端里打印的标记，detail_tools 列出终端的细节工具；
 * - card_refs 含不属于本 tab 的引用时返回可操作的 CardNotInTab 错误；未知参数被拒绝；
 * - 只读免审批：整个过程不出现审批卡片；
 * - 不自动注入：首个请求的系统提示里没有终端内容（标记只在模型调用工具之后出现）。
 * - 查询参数（ai-followup）：schema 有保留参数 max_lines / limit / cursor、没有 next_cursor；终端卡片按
 *   max_lines 取最近 N 行、按 limit 列最近 N 条命令；终端不支持 cursor，返回 Unsupported 并在提示里说明；
 *   不属于本 tab 的游标返回 InvalidArguments。
 *
 * 另把首个请求的 system 与 tools 写进 request-1.json，供 M10 前后逐字对照（ZW_TAB_CONTEXT_CAPTURE_ONLY=1
 * 时不要求工具存在，只采集，用于基线二进制）。
 *
 * 用法：ZW_AI_TEST_PREFIX=<prefix> node e2e/ai_tab_context_native.ts <out>
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createServer} from 'node:http';
import {mkdtemp, mkdir, writeFile, open, realpath, rm, chmod} from 'node:fs/promises';
import {join, resolve} from 'node:path';
import {createHash} from 'node:crypto';
import {aiToggleId} from './ai_entry.ts';

import {isTitleRequest,skipTitle} from './ai_title_fixture.ts';
import {readRequestJson} from './provider_fixture.ts';
const prefix = resolve(process.env.ZW_AI_TEST_PREFIX ?? 'zig-out');
const captureOnly = process.env.ZW_TAB_CONTEXT_CAPTURE_ONLY === '1';
const h = await import(join(prefix, 'share/zenit/harness/client.ts'));
const out = resolve(process.argv[2] ?? '/private/tmp/zw-tab-context-results');
await mkdir(out, {recursive: true});
const home = await realpath(await mkdtemp('/private/tmp/zw-tab-context-'));
await chmod(home, 0o700);
const data = join(home, 'data'), rpc = join(home, 'rpc'), tmp = join(home, 'tmp'), zdot = join(home, 'zdot');
for (const d of [data, rpc, tmp, zdot]) await mkdir(d, {mode: 0o700});
await writeFile(join(zdot, '.zshrc'), 'PS1="e2e %# "\nunsetopt BEEP 2>/dev/null\n');
const marker = 'TABCTX_MARKER_7319';
const frame = (delta: any) => 'data: ' + JSON.stringify({choices: [{index: 0, delta}]}) + '\n\n';
const wireName = (name: string) => name.replaceAll('_', '_u').replaceAll('.', '__');
const toolName = wireName('host.tab_context');
const payload = (raw: string) => { const envelope = JSON.parse(raw); for (const block of envelope.content ?? []) try { return JSON.parse(block.text); } catch {} return envelope; };
const requests: any[] = [];
const results = new Map<string, any>();
let failure: string | null = null;
const server = createServer(async (req, res) => {
    if (req.method !== 'POST') return res.end(JSON.stringify({data: [{id: 'tab-context-fixture'}]}));
    const body = await readRequestJson(req);if(isTitleRequest(body))return skipTitle(res);
    res.writeHead(200, {'content-type': 'text/event-stream'});
    if (body.messages[0]?.content?.startsWith('将用户的问题概括')) return res.end(frame({content: 'tab 上下文'}) + 'data: [DONE]\n\n');
    try {
        requests.push(body);
        for (const m of body.messages) if (m.role === 'tool') results.set(m.tool_call_id, m.content);
        const defs = (body.tools ?? []).map((t: any) => t.function.name);
        if (requests.length === 1) {
            await writeFile(join(out, 'request-1.json'), JSON.stringify({system: body.messages[0]?.role === 'system' ? body.messages[0].content : null, tools: body.tools}, null, 2));
            if (captureOnly) return res.end(frame({content: '已采集。'}) + 'data: [DONE]\n\n');
            assert(defs.includes(toolName), 'host.tab_context must be advertised');
            const system = body.messages[0].content as string;
            assert(!system.includes(marker), 'card content must not be injected into the system prompt');
            const schema = (body.tools ?? []).find((t: any) => t.function.name === toolName)?.function?.parameters ?? {};
            for (const key of ['card_refs', 'max_bytes', 'max_lines', 'limit', 'cursor']) assert(schema.properties?.[key], 'schema has ' + key);
            assert(!schema.properties?.next_cursor, 'next_cursor only appears in results');
            const ref = /"session_ref":"(s1:[0-9a-f]+:\d+:\d+)"/.exec(system)?.[1] ?? '';
            const ownCursor = 'tc1.' + createHash('sha256').update(ref).digest('hex').slice(0, 16) + '.0.1';
            return res.end(frame({tool_calls: [
                {index: 0, id: 'ctx-all', type: 'function', function: {name: toolName, arguments: '{}'}},
                {index: 1, id: 'ctx-outside', type: 'function', function: {name: toolName, arguments: JSON.stringify({card_refs: ['s1:outside:1:1']})}},
                {index: 2, id: 'ctx-unknown', type: 'function', function: {name: toolName, arguments: JSON.stringify({history: 10})}},
                {index: 3, id: 'ctx-query', type: 'function', function: {name: toolName, arguments: JSON.stringify({max_lines: 20, limit: 3})}},
                {index: 4, id: 'ctx-unsupported', type: 'function', function: {name: toolName, arguments: JSON.stringify({cursor: ownCursor})}},
                {index: 5, id: 'ctx-foreign-cursor', type: 'function', function: {name: toolName, arguments: JSON.stringify({cursor: 'tc1.0000000000000000.0.1'})}},
            ]}) + 'data: [DONE]\n\n');
        }
        return res.end(frame({content: '上下文检查完成。'}) + 'data: [DONE]\n\n');
    } catch (error) {
        failure = String(error);
        return res.end(frame({content: 'fixture failure'}) + 'data: [DONE]\n\n');
    }
});
await new Promise<void>(done => server.listen(0, '127.0.0.1', done));
const port = (server.address() as any).port;
await writeFile(join(data, 'config.toml'), `[meta]
config_revision=1
[updates]
auto_check=false
[ui]
theme="dark"
[ai]
default_provider="tab-context-fixture"
permission_mode="confirm"
[[ai.providers]]
id="tab-context-fixture"
kind="openai_compat"
endpoint="http://127.0.0.1:${port}/v1/chat/completions"
enabled=true
[[ai.providers.models]]
name="tab-context-fixture"
context_window=200000
default=true
`, {mode: 0o600});
process.env.ZENIT_E2E_FILE_RPC_DIR = rpc;
const log = await open(join(out, 'app.log'), 'w');
const environment: any = {PATH: '/usr/bin:/bin:/usr/sbin:/sbin', HOME: home, CFFIXED_USER_HOME: home, TMPDIR: tmp + '/', ZDOTDIR: zdot, ZEROWORK_DATA_DIR: data, ZEROWORK_AUTOCONNECT: '0', ZENIT_E2E_FILE_RPC_DIR: rpc, ZENIT_E2E_BACKGROUND: '1', ZENIT_E2E_ISOLATE_POINTER: '1', ZENIT_E2E_ISOLATE_KEYBOARD: '1', SSH_AUTH_SOCK: '', OPENAI_API_KEY: '', ANTHROPIC_API_KEY: ''};
const app = spawn(join(prefix, 'bin/zerowork'), [], {env: environment, stdio: ['ignore', log.fd, log.fd]});
const exited = new Promise(done => app.once('exit', (code, signal) => done({code, signal})));
const shown = (n: any) => n && n.hidden !== true && n.visible !== false && (n.effective_opacity ?? 1) > 0 && n.rect?.w > 0 && n.rect?.h > 0;
const visible = (id: string, ms = 15000) => h.waitFor(async () => (await h.query(id)).find(shown) ?? null, ms);
const click = async (id: string) => { await visible(id); assert((await h.clickTestId(id)).ok, id); };
const report: any = {status: 'running', checks: [], captureOnly};
try {
    await h.waitForServerReady(60000);
    await h.resizeWindow(1440, 900);
    await click('workspace.empty.local');
    await visible('terminal.surface');
    await h.sleep(800);
    await click('terminal.surface');
    await h.type_(`echo ${marker}\n`);
    await h.sleep(1200);
    await click(await aiToggleId());
    await click('ai.prompt');
    await h.type_('当前终端里刚打印了什么？');
    await click('ai.send');
    await h.waitFor(async () => (await h.query('ai.turn.complete')).some(shown) || failure !== null || null, 30000);
    if (failure) throw new Error(failure);
    if (!captureOnly) {
        assert.equal(requests.length, 2, 'one tool round then the final answer');
        assert.equal((await h.query('ai.interaction.panel')).filter(shown).length, 0, 'read-only tool needs no approval');
        const system = requests[0].messages[0].content as string;
        const facts = system.slice(system.indexOf('<host_session_facts>'));
        const sessionRef = /"session_ref":"(s1:[0-9a-f]+:\d+:\d+)"/.exec(facts)?.[1];
        assert(sessionRef, 'system facts advertise the session_ref');
        const overview = payload(results.get('ctx-all'));
        report.overview = overview;
        assert.equal(overview.tab.kind, 'single');
        assert.equal(overview.cards.length, 1);
        const card = overview.cards[0];
        assert.equal(card.card_ref, sessionRef, 'card_ref is the exact session_ref of the current tab');
        assert.equal(card.card_type, 'terminal');
        assert.equal(card.placement, 'standalone_tab');
        assert.equal(card.available, true);
        assert(card.summary.includes(marker), 'summary carries the current terminal output');
        assert(card.detail_tools.includes('host.read_terminal'), 'detail tools for the terminal card');
        report.checks.push('single tab overview lists exactly the current terminal card with its session_ref, summary and detail tools');
        const outside = payload(results.get('ctx-outside'));
        assert.equal(outside.error?.code ?? outside.code, 'CardNotInTab');
        assert(String(outside.error?.hint ?? '').includes('host.tab_context'));
        report.checks.push('card_refs outside the tab return actionable CardNotInTab');
        const unknown = results.get('ctx-unknown');
        assert(/Invalid|InvalidArguments|additional/i.test(unknown), 'unknown parameter is rejected: ' + unknown);
        report.checks.push('unknown parameters are rejected by the fixed schema');
        assert.deepEqual(card.params, ['max_lines', 'limit'], 'terminal cards declare max_lines and limit');
        assert.equal(card.next_cursor, null);
        const queried = payload(results.get('ctx-query'));
        report.queried = queried;
        const qcard = queried.cards[0];
        const outputPart = qcard.summary.split('shell commands (oldest first)')[0];
        assert(qcard.summary.includes('(requested 20)') && outputPart.includes(marker), 'max_lines: the most recent output lines (not trailing blank rows), implemented by the terminal card');
        assert(/shell commands \(oldest first\)|Shell command history unavailable/.test(qcard.summary), 'limit: the most recent shell commands');
        report.checks.push('terminal card implements max_lines (recent lines) and limit (recent commands)');
        const unsupported = payload(results.get('ctx-unsupported'));
        assert.equal(unsupported.error?.code, 'Unsupported', 'terminal card does not support cursor: ' + JSON.stringify(unsupported));
        assert(String(unsupported.error?.hint ?? '').includes('does not support cursor'), 'actionable hint names the unsupported parameter');
        report.checks.push('an unsupported parameter returns Unsupported with an actionable hint');
        const foreign = payload(results.get('ctx-foreign-cursor'));
        assert.equal(foreign.error?.code, 'InvalidArguments', 'cursor of no card in this tab');
        report.checks.push('a cursor that belongs to no card in this tab is rejected');
        report.checks.push('read-only: no approval card; no terminal content in the system prompt');
    }
    assert((await h.screenshot(join(out, 'tab-context.png'))).ok);
    report.status = 'passed';
} catch (error) {
    report.status = 'failed'; report.error = String(error); process.exitCode = 1;
    await h.screenshot(join(out, 'failure.png')).catch(() => {});
} finally {
    if (app.exitCode === null && app.signalCode === null) app.kill('SIGTERM');
    await exited;
    server.closeAllConnections(); await new Promise<void>(done => server.close(() => done()));
    await log.close();
    await rm(home, {recursive: true, force: true});
    report.requests = requests.length;
    await writeFile(join(out, 'report.json'), JSON.stringify(report, null, 2));
}
console.log(JSON.stringify({status: report.status, error: report.error, checks: report.checks}));
