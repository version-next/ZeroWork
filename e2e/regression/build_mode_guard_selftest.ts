/** Negative tests for the test-mode launch guard (build_mode_guard.mjs / .py).
 *
 *   node e2e/regression/build_mode_guard_selftest.ts --formal <formal zerowork> --binary <test-mode zerowork> --out <dir> [--zig-test <zig test binary>]
 *
 * --formal must be a build WITHOUT -Dtest-mode=true, installed with `--prefix /private/tmp/zw-<pkg>-formal`
 * (never zig-out). It is never executed: every check expects the guard to refuse before a process exists,
 * and a watchdog fails the test if a process for that path appears anyway.
 * Checks:
 *   1. assertTestModeBinary refuses the formal build (and copies of it under another name / in an .app);
 *      it accepts the test-mode build and copies of it (checked, not launched).
 *   2. Every child_process entry point (spawn, spawnSync, execFile, execFileSync, promisify(execFile),
 *      exec, execSync, `open <bundle>`) throws for the formal build before starting anything.
 *   3. run.ts, window_render_smoke_native.ts (started standalone, without the preload — the path of the
 *      incident) and terminal_search_teardown_native.ts refuse the formal build with the guard's message.
 *   4. The Python guard refuses it as well.
 *   5. Inventory: every e2e script that imports node:child_process also imports the guard, so a script
 *      started without run.ts is still covered; every Python e2e that takes a `--runner` / `--binary`
 *      (acceptance runner or exported Zig test binary) calls build_mode_guard.py on it before starting it.
 */
import './build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import childProcess from 'node:child_process';
import {copyFile, mkdir, mkdtemp, readdir, readFile, rm, writeFile, chmod} from 'node:fs/promises';
import {join, resolve, dirname} from 'node:path';
import {promisify} from 'node:util';
// @ts-ignore -- plain ESM helper
import {assertTestModeBinary, BuildModeError, TEST_MODE_MARKER, launchTargets} from './build_mode_guard.mjs';

const argv = process.argv.slice(2), opt: Record<string, string> = {};
for (let i = 0; i < argv.length; i += 2) opt[argv[i]] = argv[i + 1];
assert(opt['--formal'] && opt['--binary'] && opt['--out'], 'usage: --formal <formal zerowork> --binary <test-mode zerowork> --out <dir>');
const formal = resolve(opt['--formal']), testMode = resolve(opt['--binary']), out = resolve(opt['--out']);
const repo = resolve(dirname(new URL(import.meta.url).pathname), '../..');
await mkdir(out, {recursive: true});
const report: any = {status: 'running', formal, binary: testMode, checks: [] as string[]};

// Never run the formal build from here: refuse a formal path outside a private -formal prefix.
assert(/^\/private\/tmp\/zw-[^/]+-formal\/bin\//.test(formal), `--formal must be installed under /private/tmp/zw-<pkg>-formal (got ${formal})`);
const formalBytes = await readFile(formal);
assert(!formalBytes.includes(Buffer.from(TEST_MODE_MARKER)), `${formal} carries the test-mode marker: not a formal build`);
assert((await readFile(testMode)).includes(Buffer.from(TEST_MODE_MARKER)), `${testMode} lacks the test-mode marker`);

// Watchdog: no process of the formal path (or its copies) may ever exist while this test runs.
const work = await mkdtemp('/private/tmp/zw-bmg-selftest-');
const watched = [formal];
let started: string[] = [];
const watch = setInterval(() => {
  for (const p of watched) {
    try {
      const text = childProcess.execFileSync('pgrep', ['-lf', '--', p], {encoding: 'utf8'});
      // Only a process whose executable is the watched file counts (the scripts above take it as an argument).
      for (const line of text.split('\n')) { const m = line.match(/^(\d+) (.*)$/); if (m && (m[2] === p || m[2].startsWith(p + ' '))) started.push(line); }
    } catch {}
  }
}, 50);
const refused = async (what: string, fn: () => unknown) => {
  let error: any = null;
  try { await fn(); } catch (e) { error = e; }
  assert(error, `${what}: the guard let the formal build through`);
  assert(error instanceof BuildModeError || /\[build_mode_guard\] refusing/.test(String(error?.message)), `${what}: unexpected error ${error}`);
  return String(error.message);
};

try {
  // 1. Direct checks, copies under other names and inside a bundle.
  const message = await refused('assertTestModeBinary(formal)', () => assertTestModeBinary(formal));
  assert(message.includes(TEST_MODE_MARKER) && message.includes('formal build'), message);
  const renamed = join(work, 'zerowork-frozen'), anonymous = join(work, 'plain-copy');
  const bundle = join(work, 'Candidate.app');
  await mkdir(join(bundle, 'Contents/MacOS'), {recursive: true});
  for (const p of [renamed, anonymous, join(bundle, 'Contents/MacOS/ZeroWork')]) { await copyFile(formal, p); await chmod(p, 0o755); watched.push(p); }
  for (const p of [renamed, anonymous, join(bundle, 'Contents/MacOS/ZeroWork')]) await refused(`copy ${p}`, () => assertTestModeBinary(p));
  assert.deepEqual(launchTargets('/usr/bin/open', ['-n', bundle]), [join(bundle, 'Contents/MacOS/ZeroWork')]);
  assert.equal(assertTestModeBinary(testMode), testMode);
  const goodCopy = join(work, 'test-mode-copy');
  await copyFile(testMode, goodCopy);
  assert.equal(assertTestModeBinary(goodCopy), goodCopy);
  report.checks.push('assertTestModeBinary: formal build and its copies (other name, anonymous name, .app) refused; test-mode build and copy accepted');

  // 2. Every child_process entry point refuses before a process exists.
  const cp: any = childProcess;
  await refused('spawn', () => cp.spawn(formal, []));
  await refused('spawn(copy)', () => cp.spawn(anonymous, ['--print-build-mode']));
  await refused('spawnSync', () => cp.spawnSync(formal, []));
  await refused('execFile', () => cp.execFile(formal, [], () => {}));
  await refused('execFileSync', () => cp.execFileSync(formal, []));
  await refused('promisify(execFile)', () => promisify(cp.execFile)(formal, []));
  await refused('exec', () => cp.exec(`"${formal}" --version`, () => {}));
  await refused('execSync', () => cp.execSync(`'${renamed}'`));
  await refused('open bundle', () => cp.spawn('/usr/bin/open', ['-n', bundle]));
  await refused('execFileSync(open)', () => cp.execFileSync('/usr/bin/open', [bundle]));
  // The hook stays out of the way for everything else.
  assert.equal(cp.execFileSync('/bin/echo', ['ok'], {encoding: 'utf8'}).trim(), 'ok');
  assert.equal((await promisify(cp.execFile)('/bin/echo', ['ok'])).stdout.trim(), 'ok');
  report.checks.push('child_process spawn / spawnSync / execFile / execFileSync / promisify(execFile) / exec / execSync / open <bundle>: formal build refused before start; other programs unaffected');

  // 3. Runner and standalone scripts refuse the formal build (each starts no app).
  const node = (args: string[], extraEnv: Record<string, string> = {}) => new Promise<{code: number | null, text: string}>(done => {
    const child = childProcess.spawn(process.execPath, args, {cwd: repo, env: {...process.env, ...extraEnv}, stdio: ['ignore', 'pipe', 'pipe']});
    let text = '';
    child.stdout.on('data', d => text += d); child.stderr.on('data', d => text += d);
    child.once('close', code => done({code, text}));
  });
  const runOut = join(work, 'run-out');
  const run = await node(['e2e/regression/run.ts', '--binary', formal, '--out', runOut, '--only', 'window_render_smoke_native']);
  assert.notEqual(run.code, 0, 'run.ts accepted a formal build');
  assert(/\[build_mode_guard\] refusing to run the regression batch with/.test(run.text), run.text.slice(0, 600));
  const smoke = await node(['e2e/window_render_smoke_native.ts', formal, join(work, 'smoke-out'), 'light']);
  assert.notEqual(smoke.code, 0, 'window_render_smoke_native.ts started a formal build');
  assert(/\[build_mode_guard\] refusing to start/.test(smoke.text), smoke.text.slice(0, 600));
  const teardown = await node(['e2e/terminal_search_teardown_native.ts', formal, join(work, 'teardown-out')]);
  assert.notEqual(teardown.code, 0, 'terminal_search_teardown_native.ts started a formal build');
  assert(/\[build_mode_guard\] refusing to start/.test(teardown.text), teardown.text.slice(0, 600));
  report.checks.push('run.ts, window_render_smoke_native.ts (standalone, no preload) and terminal_search_teardown_native.ts refuse the formal build');

  // 4. Python guard.
  const py = childProcess.spawnSync('python3', ['-I', '-c', `import importlib.util,sys
spec=importlib.util.spec_from_file_location('g',sys.argv[1]);g=importlib.util.module_from_spec(spec);spec.loader.exec_module(g)
try:
    g.assert_test_mode_binary(sys.argv[2]); print('ACCEPTED-FORMAL')
except g.BuildModeError as e:
    print('REFUSED', e)
for p in sys.argv[3:]:
    try:
        g.assert_test_mode_binary(p); print('ACCEPTED')
    except g.BuildModeError as e:
        print('REFUSED', e)
for p in sys.argv[2:4]:
    try:
        g.assert_runner_binary(p); print('RUNNER-ACCEPTED')
    except g.BuildModeError as e:
        print('RUNNER-REFUSED', e)`, join(repo, 'e2e/regression/build_mode_guard.py'), formal, testMode, bundle], {encoding: 'utf8'});
  assert.equal(py.status, 0, py.stderr);
  const lines = py.stdout.trim().split('\n');
  assert(lines[0].startsWith('REFUSED') && lines[0].includes('formal build'), py.stdout);
  assert.equal(lines[1], 'ACCEPTED', py.stdout);
  assert(lines[2].startsWith('REFUSED'), py.stdout);
  // assert_runner_binary (runner / exported Zig test binary scripts) is just as strict about formal builds.
  assert(lines[3].startsWith('RUNNER-REFUSED') && lines[3].includes('formal build'), py.stdout);
  assert.equal(lines[4], 'RUNNER-ACCEPTED', py.stdout);
  report.checks.push('build_mode_guard.py (assert_test_mode_binary and assert_runner_binary) refuses the formal build and its .app wrapper, accepts the test-mode build');
  if (opt['--zig-test']) {
    // Optional: an exported Zig test binary (e.g. .zig-cache/o/<hash>/unit-tests). Only assert_runner_binary accepts it.
    const zigTest = childProcess.spawnSync('python3', ['-I', '-c', `import importlib.util,sys
spec=importlib.util.spec_from_file_location('g',sys.argv[1]);g=importlib.util.module_from_spec(spec);spec.loader.exec_module(g)
for check in (g.assert_runner_binary, g.assert_test_mode_binary):
    try:
        check(sys.argv[2]); print('ACCEPTED')
    except g.BuildModeError as e:
        print('REFUSED', e)`, join(repo, 'e2e/regression/build_mode_guard.py'), resolve(opt['--zig-test'])], {encoding: 'utf8'});
    assert.equal(zigTest.status, 0, zigTest.stderr);
    const [runner, app] = zigTest.stdout.trim().split('\n');
    assert.equal(runner, 'ACCEPTED', zigTest.stdout);
    assert(app.startsWith('REFUSED'), zigTest.stdout);
    report.checks.push('build_mode_guard.py: an exported Zig test binary passes assert_runner_binary but not assert_test_mode_binary');
  }

  // 5. Inventory: every script that can start a process imports the guard.
  const missing: string[] = [];
  const scan = async (dir: string) => {
    for (const name of await readdir(join(repo, dir))) {
      if (!/\.(ts|mts|mjs)$/.test(name)) continue;
      const rel = join(dir, name);
      if (['e2e/regression/build_mode_guard.mjs', 'e2e/regression/exit_guard.mjs'].includes(rel)) continue;
      const text = await readFile(join(repo, rel), 'utf8');
      if (/['"](node:)?child_process['"]/.test(text) && !/build_mode_guard\.mjs/.test(text)) missing.push(rel);
    }
  };
  await scan('e2e'); await scan('e2e/regression');
  assert.deepEqual(missing, [], `scripts that can start processes without the build-mode guard: ${missing.join(', ')}`);
  report.checks.push('every e2e script importing node:child_process imports build_mode_guard.mjs');
  const pyMissing: string[] = [];
  let pyCovered = 0;
  for (const name of await readdir(join(repo, 'e2e'))) {
    if (!name.endsWith('.py')) continue;
    const text = await readFile(join(repo, 'e2e', name), 'utf8');
    if (!/add_argument\((['"])--(runner|binary)\1/.test(text)) continue;
    if (/build_mode_guard\.assert_(runner|test_mode)_binary\(/.test(text)) pyCovered++; else pyMissing.push(`e2e/${name}`);
  }
  assert.deepEqual(pyMissing, [], `Python e2e scripts that start a --runner / --binary without build_mode_guard.py: ${pyMissing.join(', ')}`);
  report.checks.push(`every Python e2e taking --runner / --binary calls build_mode_guard.py before starting it (${pyCovered} scripts)`);

  await new Promise(r => setTimeout(r, 200));
  assert.deepEqual(started, [], `a formal-build process existed during the test: ${started.join(' | ')}`);
  report.checks.push('watchdog: no process of the formal build or its copies ever existed');
  report.status = 'passed';
} catch (e) {
  report.status = 'failed'; report.error = String((e as any)?.stack ?? e); process.exitCode = 1;
} finally {
  clearInterval(watch);
  await rm(work, {recursive: true, force: true});
  await writeFile(join(out, 'report.json'), JSON.stringify(report, null, 2));
  console.log(JSON.stringify({status: report.status, checks: report.checks, error: report.error}));
}
