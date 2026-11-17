/** Negative tests for the private-HOME guard (run through run.ts or with
 * `node --import ./e2e/regression/isolation_guard.mjs e2e/regression/guard_selftest.ts <out>`).
 * Proves that starting the app with a real HOME / data dir is refused before the process exists,
 * that writes into the real home are detected, that crash reports of our own test binaries inside the
 * run window are allowed and cleaned up while any other ZeroWork crash report is an alarm, and that
 * temp directories land in the private root.
 * Starts no app; touches the real home only by reading.
 */
import './build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdtemp, mkdir, writeFile} from 'node:fs/promises';
import {tmpdir, userInfo} from 'node:os';
import {join, resolve} from 'node:path';
// @ts-ignore -- plain ESM helper
import {snapshotRealHome, diffSnapshots, ROOT_PREFIX, snapshotCrashReports, classifyCrashChanges, cleanupCrashReports} from './home_guard.mjs';

const out = resolve(process.argv[2] ?? '.');
await mkdir(out, {recursive: true});
const report: any = {status: 'running', checks: []};
const realHome = userInfo().homedir;
try {
  const root = process.env.ZW_E2E_ROOT!;
  assert(root && root.startsWith(ROOT_PREFIX), 'the guard must provide a private root');
  assert.notEqual(process.env.HOME, realHome);
  assert(process.env.HOME!.startsWith(root) && process.env.CFFIXED_USER_HOME === process.env.HOME);
  assert(tmpdir().startsWith(root));
  report.checks.push('HOME / CFFIXED_USER_HOME / TMPDIR point into the private root');

  const temp = await mkdtemp('/tmp/zw-selftest-');
  assert(temp.startsWith(join(root, 'tmp')), temp);
  const temp2 = await mkdtemp('/private/tmp/zw-selftest-');
  assert(temp2.startsWith(join(root, 'tmp')), temp2);
  report.checks.push('mkdtemp under /tmp and /private/tmp is redirected into the private root');

  const fakeApp = join(root, 'not-built', 'zerowork');   // never exists: the guard must throw before exec
  const refused = (env: Record<string, string | undefined>) => {
    try { spawn(fakeApp, [], {env: env as any}); } catch (e) { return String(e).includes('[home_guard]'); }
    return false;
  };
  const dataDir = join(root, 'tmp', 'data');
  assert(refused({...process.env, HOME: realHome, ZEROWORK_DATA_DIR: dataDir}), 'real HOME must be refused');
  assert(refused({...process.env, CFFIXED_USER_HOME: realHome, ZEROWORK_DATA_DIR: dataDir}), 'real CFFIXED_USER_HOME must be refused');
  assert(refused({...process.env, TMPDIR: '/tmp/', ZEROWORK_DATA_DIR: dataDir}), 'shared /tmp TMPDIR must be refused');
  assert(refused({...process.env, ZEROWORK_DATA_DIR: join(realHome, 'Library/Application Support/ZeroWork')}), 'real data dir must be refused');
  const {ZEROWORK_DATA_DIR: _drop, ...noData} = process.env;
  assert(refused(noData), 'the main app without ZEROWORK_DATA_DIR (would fall back to the real data dir) must be refused');
  // A copy of the real binary under an unrelated name is still recognised by content.
  if (process.env.ZW_E2E_PREFIX) {
    const {copyFile} = await import('node:fs/promises');
    const disguised = join(root, 'tmp', 'innocent-name');
    await copyFile(join(process.env.ZW_E2E_PREFIX, 'bin', 'zerowork'), disguised);
    let threw = false;
    try { spawn(disguised, [], {env: {...process.env, ZEROWORK_DATA_DIR: undefined} as any}); } catch (e) { threw = String(e).includes('[home_guard]'); }
    assert(threw, 'a renamed copy of the main binary without ZEROWORK_DATA_DIR must be refused');
    report.checks.push('a renamed copy of the main binary is identified by content and refused without a private data dir');
  }
  report.checks.push('spawning the app with a real HOME / CFFIXED_USER_HOME / TMPDIR / data dir, or without a data dir, throws before exec');

  const fakeReal = join(root, 'pretend-real-home');
  await mkdir(join(fakeReal, 'Library/Application Support/com.zerowork.updater'), {recursive: true});
  await mkdir(join(fakeReal, 'Downloads'), {recursive: true});
  process.env.ZW_E2E_REAL_HOME_FOR_TEST = fakeReal;
  const before = snapshotRealHome();
  await writeFile(join(fakeReal, 'Library/Application Support/com.zerowork.updater/stray.json'), '{}');
  await writeFile(join(fakeReal, 'Downloads/stray.txt'), 'x');
  const changes = diffSnapshots(before, snapshotRealHome());
  delete process.env.ZW_E2E_REAL_HOME_FOR_TEST;
  assert(changes.some((c: string) => c.includes('com.zerowork.updater/stray.json')), JSON.stringify(changes));
  assert(changes.some((c: string) => c.includes('Downloads/stray.txt')), JSON.stringify(changes));
  report.checks.push('writes under <home>/Library/Application Support/com.zerowork.* and <home>/Downloads are detected');

  // Crash reports (macOS ReportCrash writes them into the real home, not the app): own test binaries inside
  // the window are allowed and the new ones deleted; others that are ZeroWork-related alarm; other apps ignored.
  const fakeHome2 = join(root, 'pretend-real-home-crash');
  const diag = join(fakeHome2, 'Library/Logs/DiagnosticReports'), cr = join(fakeHome2, 'Library/Application Support/CrashReporter');
  await mkdir(diag, {recursive: true}); await mkdir(cr, {recursive: true});
  const uuid = 'D6C0D5F8-4533-5647-BFDB-05F0B92DA194';
  await writeFile(join(cr, `zerowork_${uuid}.plist`), 'old');                       // pre-existing, gets rewritten
  await writeFile(join(diag, 'zerowork-2020-01-01-000000.ips'), 'old');             // old report, untouched
  const crashBefore = snapshotCrashReports(fakeHome2);
  const windowStart = Date.now() - 1000;
  const pad = (n: number) => String(n).padStart(2, '0');
  const d = new Date(); const stamp = `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}-${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}`;
  await new Promise(r => setTimeout(r, 20));
  for (const n of [`unit-tests-${stamp}.ips`, `ui-tests-${stamp}.ips`, `zerowork-${stamp}.ips`, `settings-preview-${stamp}.ips`, `Safari-${stamp}.ips`])
    await writeFile(join(diag, n), 'x');
  await writeFile(join(cr, `unit-tests_${uuid}.plist`), 'x');
  await writeFile(join(cr, `zerowork_${uuid}.plist`), 'rewritten');
  const allowedOnly = classifyCrashChanges(crashBefore, snapshotCrashReports(fakeHome2), windowStart);
  assert.equal(allowedOnly.alarms.length, 0, JSON.stringify(allowedOnly.alarms));
  assert.equal(allowedOnly.allowed.length, 6, JSON.stringify(allowedOnly.allowed));   // 4 own .ips + new plist + rewritten plist (Safari ignored)
  // Outside the window (stamp before the run) or an unknown ZeroWork-ish process: alarm.
  await writeFile(join(diag, 'zerowork-2021-01-01-000000.ips'), 'x');
  await writeFile(join(diag, `zerowork-helper-${stamp}.ips`), 'x');
  await writeFile(join(diag, `settings-preview-runner-${stamp}.ips`), 'x');
  const mixed = classifyCrashChanges(crashBefore, snapshotCrashReports(fakeHome2), windowStart, (p: string) => p === 'settings-preview-runner');
  assert.equal(mixed.alarms.length, 3, JSON.stringify(mixed.alarms));
  assert(mixed.alarms.some((a: string) => a.includes('zerowork-2021-01-01')) && mixed.alarms.some((a: string) => a.includes('zerowork-helper-')) && mixed.alarms.some((a: string) => a.includes('settings-preview-runner-')));
  const cleaned = cleanupCrashReports(allowedOnly.allowed);
  assert.equal(cleaned.filter((c: any) => c.action === 'deleted').length, 5);
  assert.equal(cleaned.filter((c: any) => c.action.startsWith('kept')).length, 1);
  const left = snapshotCrashReports(fakeHome2);
  assert(left.has(join(diag, 'zerowork-2020-01-01-000000.ips')) && left.has(join(cr, `zerowork_${uuid}.plist`)) && left.has(join(diag, `Safari-${stamp}.ips`)));
  assert(!left.has(join(diag, `zerowork-${stamp}.ips`)) && !left.has(join(cr, `unit-tests_${uuid}.plist`)));
  report.checks.push('crash reports: own test binaries inside the run window are allowed and new ones deleted (pre-existing per-process plist kept); out-of-window or unknown ZeroWork-related reports alarm; other apps ignored');
  report.status = 'passed';
} catch (e) {
  report.status = 'failed';
  report.error = String((e as any)?.stack ?? e);
  process.exitCode = 1;
} finally {
  await writeFile(join(out, 'report.json'), JSON.stringify(report, null, 2));
  console.log(JSON.stringify(report));
}
