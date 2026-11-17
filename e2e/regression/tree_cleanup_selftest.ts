/** Runner test: the private root of an item is removed only after every descendant of the item has exited.
 * The app's shells run in their own sessions (outside the item's process group); after the app ends zsh still
 * writes `.zsh_history` into the private HOME. A runner that deletes the root first races that write and can
 * leave an empty private HOME behind.
 *
 *   node e2e/regression/tree_cleanup_selftest.ts --binary <test-mode zerowork> --out <dir>
 *
 * Runs run.ts on a one-item manifest (fixtures/late_writer_item.mjs). Starts no app.
 */
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {existsSync} from 'node:fs';
import {mkdir, readFile, writeFile} from 'node:fs/promises';
import {dirname, join, resolve} from 'node:path';

const opts: Record<string, string> = {};
for (let i = 2; i < process.argv.length; i += 2) { assert(['--binary', '--out'].includes(process.argv[i]) && process.argv[i + 1]); opts[process.argv[i]] = process.argv[i + 1]; }
assert(opts['--binary'] && opts['--out']);
const repo = resolve(dirname(new URL(import.meta.url).pathname), '../..');
const out = resolve(opts['--out']);
await mkdir(out, {recursive: true});
const report: any = {status: 'running', checks: []};
try {
  const manifest = join(out, 'manifest.json'), inner = join(out, 'inner');
  await writeFile(manifest, JSON.stringify({version: 1, entries: [
    {name: 'late_writer', script: 'e2e/regression/fixtures/late_writer_item.mjs', class: 'runnable', args: ['{out}'], timeout: 60},
  ]}));
  const code = await new Promise(done => spawn(process.execPath, [join(repo, 'e2e/regression/run.ts'), '--binary', resolve(opts['--binary']), '--out', inner, '--manifest', manifest],
    {cwd: repo, stdio: 'inherit'}).once('close', (c, s) => done(c ?? s)));
  assert.equal(code, 0, 'inner run.ts failed');
  const summary = await readFile(join(inner, 'SUMMARY.tsv'), 'utf8');
  assert.match(summary, /^late_writer\t.*\tPASS$/m, summary);
  const root = (await readFile(join(inner, 'logs', 'late_writer.log'), 'utf8')).match(/^# private root (.+)$/m)?.[1];
  assert(root && root.includes('zw-e2e-home-'), 'the item log names its private root');
  report.checks.push('the one-item batch passed');
  const done = join(inner, 'late_writer', 'late-writer.done');
  for (let t = 0; t < 50 && !existsSync(done); t++) await new Promise(r => setTimeout(r, 100));   // a runner that did not wait
  assert.equal((await readFile(done, 'utf8')).trim(), 'wrote',
    'the descendant that writes after the item ended found its private HOME (the runner waited for it)');
  report.checks.push('a descendant in its own session wrote into the private HOME after the item ended');
  assert(!existsSync(root), `private root ${root} is gone after the run`);
  report.checks.push('the private root was removed after that write');
  report.status = 'passed';
} catch (e) {
  report.status = 'failed'; report.error = String((e as Error)?.stack ?? e);
  process.exitCode = 1;
} finally {
  await writeFile(join(out, 'report.json'), JSON.stringify(report, null, 2));
}
