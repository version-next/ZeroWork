/** Production Store → native step rows with synthetic input receipts; no PTY/provider.
 *
 * Current contract (AI Chat redesign 143c4c7b, Pencil Kaf7E A6; output wells 43eada2b):
 * - A host execution result is a step row on the rail, not a card: the collapsed row is `row_height` = 24 high
 *   (src/features/ai/cards/view/ai_tool_results_styles.zig), the whole row toggles the disclosed details; expanded =
 *   row + details body (fit, max 150: ai_execution_result_styles.body) + footer (28 when it has controls; hidden on an
 *   input result without controls or output: ai_execution_result_view.zig).
 * - The input receipt row shows 输入结果 · <stage>, the input type and a limit note; it never shows the input/wait
 *   sequence numbers (the old input-sequence node was removed in 04750679, whose unit tests assert it stays absent) nor any execution output or control of the command it fed.
 * Usage: node e2e/ai_execution_input_result_component_native.ts <prefix> <out> <theme>
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdir, mkdtemp, open, readFile, writeFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import * as h from '../zig-out/share/zenit/harness/client.ts';
const prefix = resolve(process.argv[2] ?? 'zig-out');
const out = resolve(process.argv[3] ?? '/tmp/zw-execution-input-projection-native');
const theme = process.argv[4] ?? 'dark';
assert(['light', 'dark'].includes(theme), `theme must be light or dark, got ${theme}`);
const binary = join(prefix, 'bin/execution-result-preview');
await mkdir(out, { recursive: true });
const ROW = 24, BODY_MAX = 150, HEIGHT = 560;
const text = (n: any): string => n.text ?? (n.children ?? []).map(text).join('');
const find = (n: any, id: string): any => n.test_id === id ? n : (n.children ?? []).map((c: any) => find(c, id)).find(Boolean);
const all = (n: any): any[] => [n, ...(n.children ?? []).flatMap(all)];
const visible = (n: any) => n && n.visible !== false && n.hidden !== true && (n.effective_opacity ?? 1) > 0 && n.rect?.w > 0 && n.rect?.h > 0;
const card = (id: string) => h.waitFor(async () => (await h.query(id)).find(visible) ?? null, 10000);
const near = (a: number, b: number, what: string, eps = 0.1) => assert(Math.abs(a - b) <= eps, `${what}: ${a} vs ${b}`);
const report: any = { status: 'running', binary, theme, sha256: createHash('sha256').update(await readFile(binary)).digest('hex'), checks: [], shutdown: [], limits: ['Isolated production projection/Store/view with synthetic immutable receipts. No command, secret, PTY, provider, or main App was exercised.'] };
try {
    const runs = [{ width: 600, state: 'input_consumed' }, { width: 600, state: 'input_unknown' }, { width: 360, state: 'input_consumed' }];
    for (const { width, state } of runs) {
        const name = `${theme}-${width}-${state}`;
        const rpc = await mkdtemp('/tmp/zw-input-result-rpc-');
        process.env.ZENIT_E2E_FILE_RPC_DIR = rpc;
        const log = await open(join(out, `${name}.log`), 'w');
        const app = spawn(binary, [`--theme=${theme}`, `--state=${state}`], { env: { ...process.env, ZENIT_E2E_FILE_RPC_DIR: rpc, ZENIT_E2E_BACKGROUND: '1', ZENIT_E2E_ISOLATE_POINTER: '1' }, stdio: ['ignore', log.fd, log.fd] });
        const ended = new Promise<any>(done => app.once('exit', (code, signal) => done({ code, signal })));
        try {
            await h.waitForServerReady(10000);
            assert.equal(Number(JSON.parse(await readFile(join(rpc, 'owner.json'), 'utf8')).pid), app.pid);
            await h.resizeWindow(width, HEIGHT);
            await h.waitFor(async () => Math.abs((await card('execution_result.preview')).rect.w - width) < 0.5 || null, 5000);
            // The execution row starts collapsed: just its 24 row; elapsed time only shows when open.
            const collapsed = await card('execution_result.preview.card');
            near(collapsed.rect.h, ROW, 'collapsed execution row (ai_tool_results_styles.row_height)');
            near(find(collapsed, 'ai.execution.result.header').rect.h, ROW, 'row header');
            assert(!visible(find(collapsed, 'ai.execution.result.elapsed')), 'elapsed hidden while collapsed');
            const executionHeader = find(collapsed, 'ai.execution.result.header').rect;
            await h.clickAt(executionHeader.x + 20, executionHeader.y + executionHeader.h / 2);
            await h.waitFor(async () => (await card('execution_result.preview.card')).rect.h > ROW + 1 || null, 5000);
            const execution = await h.waitFor(async () => { const c = await card('execution_result.preview.card'), b = find(c, 'ai.execution.result.details'), f = find(c, 'ai.execution.result.footer'); return b && f && Math.abs(c.rect.h - (ROW + b.rect.h + f.rect.h)) < 0.1 ? c : null; }, 5000);
            const body = find(execution, 'ai.execution.result.details').rect;
            near(body.h, BODY_MAX, 'execution details body is bounded (ai_execution_result_styles.body max 150)');
            assert(visible(find(execution, 'ai.execution.result.elapsed')), 'elapsed shown while open');
            assert.equal(text(find(execution, 'ai.execution.result.summary')), '命令已结束');
            assert.equal(text(find(execution, 'ai.execution.result.process')), '退出码 0');
            assert(!visible(find(execution, 'ai.execution.result.collection_details')));
            const details = find(execution, 'ai.execution.result.details_toggle').rect;
            await h.clickAt(details.x + details.w / 2, details.y + details.h / 2);
            const opened = await h.waitFor(async () => { const c = await card('execution_result.preview.card'); return visible(find(c, 'ai.execution.result.collection_details')) ? c : null; }, 5000);
            assert.equal(text(find(opened, 'ai.execution.result.output_scope')), '本次终端输出 · 已保存');
            const closeDetails = find(opened, 'ai.execution.result.details_toggle').rect;
            await h.clickAt(closeDetails.x + closeDetails.w / 2, closeDetails.y + closeDetails.h / 2);
            await h.waitFor(async () => !visible(find(await card('execution_result.preview.card'), 'ai.execution.result.collection_details')) || null, 5000);
            assert(text(find(execution, 'ai.execution.result.terminal_output')).includes('ACTUAL_TERMINAL_OUTPUT'));
            // The input receipt row (mounted expanded by the preview).
            const input = await card('execution_result.preview.input_card');
            assert.equal(text(find(input, 'ai.execution.result.summary')), state === 'input_unknown' ? '输入结果 · 输入结果待核实' : '输入结果 · 输入已消费');
            assert.equal(text(find(input, 'ai.execution.result.input_type')), '输入类型 · 安全输入');
            assert.equal(text(find(input, 'ai.execution.result.input_limit')), '此处仅确认本次输入的处理状态；命令执行结果请查看执行记录。');
            const inputTexts = all(input).filter(n => typeof n.text === 'string').map(n => n.text);
            assert(!inputTexts.some(t => /序号|sequence/i.test(t)), `input row must not show input / wait sequence numbers: ${inputTexts.join(' | ')}`);
            assert.equal(Boolean(find(input, 'ai.execution.result.failure')), state === 'input_unknown');
            for (const id of ['process', 'terminal_output', 'output_label', 'copy_output', 'copy_command', 'stop', 'takeover', 'view_terminal']) assert(!find(input, `ai.execution.result.${id}`), id);
            const title = find(input, 'ai.execution.result.title').rect, icon = find(input, 'ai.execution.result.icon').rect, inputHeader = find(input, 'ai.execution.result.header').rect;
            assert(Math.abs(icon.y + icon.h / 2 - title.y - title.h / 2) < .5 && icon.x + icon.w < title.x, 'status glyph and title on one row');
            assert(Math.abs(icon.y + icon.h / 2 - inputHeader.y - inputHeader.h / 2) < .5, 'glyph centred in the row');
            assert(input.rect.x >= 0 && input.rect.x + input.rect.w <= width + .1 && input.rect.y + input.rect.h <= HEIGHT, 'input row inside the window');
            assert(input.rect.y >= execution.rect.y + execution.rect.h - .1, 'input row below the execution row');
            const inputBody = find(input, 'ai.execution.result.details').rect;
            assert(!visible(find(input, 'ai.execution.result.footer')), 'no footer without controls or output');
            near(input.rect.h, ROW + inputBody.h, 'open input row = row + details');
            // Disclosure: collapse to the bare row, reopen to row + details.
            await h.clickAt(inputHeader.x + 20, inputHeader.y + inputHeader.h / 2);
            await h.waitFor(async () => Math.abs((await card('execution_result.preview.input_card')).rect.h - ROW) < .1 || null, 5000);
            await h.clickAt(inputHeader.x + 20, inputHeader.y + inputHeader.h / 2);
            await h.waitFor(async () => {
                const current = await card('execution_result.preview.input_card');
                return Math.abs(current.rect.h - ROW - find(current, 'ai.execution.result.details').rect.h) < .1 && current.rect.h > ROW + 1 || null;
            }, 5000);
            await h.mouseMove(1, HEIGHT - 1);
            assert((await h.screenshot(join(out, `${name}.png`))).ok);
            await writeFile(join(out, `${name}.json`), JSON.stringify(await h.tree(), null, 2));
            report.checks.push({ name, execution_summary: text(find(execution, 'ai.execution.result.summary')), input_summary: text(find(input, 'ai.execution.result.summary')), icon_title_same_row: true, disclosure: 'collapsed/reopened', unrelated_execution_output_on_input: false, sequence_numbers_hidden: true });
        } finally {
            const shutdown: any = { name, route: 'POST /quit' };
            if (app.exitCode === null && app.signalCode === null) {
                try { await h.request('POST', '/quit'); await h.waitFor(async () => app.exitCode !== null || app.signalCode !== null || null, 10000); }
                catch (error) { shutdown.error = String(error); shutdown.route = 'SIGTERM fallback'; app.kill('SIGTERM'); }
            }
            Object.assign(shutdown, await ended);
            report.shutdown.push(shutdown);
            await log.close();
            await writeFile(join(out, 'report.json'), JSON.stringify(report, null, 2));
            assert.equal(shutdown.route, 'POST /quit');
            assert.equal(shutdown.code, 0);
            assert.equal(shutdown.signal, null);
        }
    }
    report.status = 'passed';
} catch (error) { report.status = 'failed'; report.error = String(error); process.exitCode = 1; }
await writeFile(join(out, 'report.json'), JSON.stringify(report, null, 2));
console.log(JSON.stringify({ status: report.status, checks: report.checks.length, out, error: report.error }, null, 2));
