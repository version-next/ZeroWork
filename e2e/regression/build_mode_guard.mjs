/** Test-mode launch guard for every e2e path (teardown-guard).
 *
 * A formal build (no -Dtest-mode=true) reads only the real home directory: HOME / CFFIXED_USER_HOME
 * overrides do not apply to it, so an e2e that starts one writes into ~/Library. Before any ZeroWork
 * binary (the app, a preview / fixture / acceptance runner, a copy of one under another name, or an
 * .app bundle that wraps one) is started through node:child_process, this guard reads the file and
 * requires the marker that only -Dtest-mode=true builds contain (src/platform/build_mode_marker.zig;
 * check-test-hooks enforces it at install). It never executes the binary to ask: a formal build
 * would ignore any probe argument and start against the real home.
 *
 * Importing this module installs the hook once per process (idempotent). Every e2e script that
 * imports node:child_process imports it first; run.ts and isolation_guard.mjs import it too.
 * There is no opt-out.
 */
import childProcess from 'node:child_process';
import fs from 'node:fs';
import {basename, dirname, isAbsolute, join, resolve} from 'node:path';
import {syncBuiltinESMExports} from 'node:module';
import {promisify} from 'node:util';

export const TEST_MODE_MARKER = 'ZEROWORK_BUILD_MODE=test-mode';
const MARKER = Buffer.from(TEST_MODE_MARKER);
/** Bytes that identify a ZeroWork product, formal or test-mode: the bundle-id domain (app, updater),
 * the isolated-home refusal (every preview / fixture / runner) and the Zenit harness (test builds). */
const IDENTITY = [Buffer.from('com.zerowork.'), Buffer.from('ZeroWork test build refuses to start'), Buffer.from('[test_harness] File RPC server listening')];
/** Names that must be ZeroWork products (home_guard.isAppCommand plus the updater). */
const APP_NAME = /(^|\/)(zerowork[^/]*|ZeroWork[^/]*|PreviewCheck|[a-z0-9-]+-(preview|runner|fixture)|mockup-[A-Za-z0-9_-]+)$/;
/** System and toolchain locations never hold a ZeroWork product. */
const SYSTEM = ['/usr/', '/bin/', '/sbin/', '/System/', '/Library/Developer/', '/Applications/Xcode', '/opt/homebrew/', '/usr/local/'];

export class BuildModeError extends Error {}

const cache = new Map();   // realpath → {key, verdict}
function scan(path) {
  let real = path, st;
  try { real = fs.realpathSync(path); st = fs.statSync(real); } catch { return {kind: 'missing'}; }
  if (!st.isFile()) return {kind: 'not-file'};
  const key = `${st.size}:${st.mtimeMs}:${st.ino}`;
  const hit = cache.get(real);
  if (hit && hit.key === key) return hit.verdict;
  let verdict;
  const fd = fs.openSync(real, 'r');
  try {
    const head = Buffer.alloc(4);
    fs.readSync(fd, head, 0, 4, 0);
    const magic = head.readUInt32BE(0);
    // Mach-O 64 (LE on disk: cffaedfe), fat/universal (cafebabe / cafebabf).
    const macho = magic === 0xcffaedfe || magic === 0xcefaedfe || magic === 0xcafebabe || magic === 0xcafebabf;
    if (!macho) verdict = {kind: 'not-binary'};
    else {
      const bytes = fs.readFileSync(real);
      verdict = {kind: 'binary', testMode: bytes.includes(MARKER), zerowork: IDENTITY.some(id => bytes.includes(id))};
    }
  } finally { fs.closeSync(fd); }
  cache.set(real, {key, verdict});
  return verdict;
}

/** Executables inside an .app bundle (Contents/MacOS/*). */
function bundleExecutables(bundle) {
  const dir = join(bundle, 'Contents/MacOS');
  try { return fs.readdirSync(dir).map(n => join(dir, n)).filter(p => { try { return fs.statSync(p).isFile(); } catch { return false; } }); } catch { return []; }
}
const bundleOf = (p) => { const m = String(p).match(/^(.*?\.app)(\/|$)/); return m ? m[1] : null; };

/** True when `path` is a file this guard treats as a ZeroWork product. */
export function isZeroWorkBinary(path) {
  const v = scan(path);
  if (v.kind !== 'binary') return APP_NAME.test(String(path)) && v.kind !== 'missing' && v.kind !== 'not-file';
  return v.zerowork || v.testMode || APP_NAME.test(String(path));
}

/** Throws unless `path` is a -Dtest-mode=true build. `how` names the launch for the message. */
export function assertTestModeBinary(path, how = 'start') {
  const abs = resolve(String(path));
  const v = scan(abs);
  if (v.kind === 'binary' && v.testMode) return abs;
  const why = v.kind === 'missing' ? 'the file does not exist'
    : v.kind === 'binary' ? `the build-mode marker "${TEST_MODE_MARKER}" is missing — this is a formal build`
    : 'it is not a Mach-O executable';
  throw new BuildModeError(`[build_mode_guard] refusing to ${how} ${abs}: ${why}. Formal builds only read the real home directory `
    + '(HOME overrides do not apply). Build with `zig build -Dtest-mode=true --prefix <private dir>` and pass that binary; '
    + 'never launch zig-out or a --prefix …-formal install from an e2e.');
}

/** Every ZeroWork executable a child_process call would start (empty when none). */
export function launchTargets(command, args = []) {
  const cmd = String(command ?? '');
  const out = new Set();
  const consider = (p) => {
    if (!p) return;
    const abs = isAbsolute(p) ? p : resolve(p);
    const bundle = bundleOf(abs);
    if (bundle && fs.existsSync(bundle)) {
      if (abs === bundle || abs === bundle + '/') { for (const e of bundleExecutables(bundle)) if (isZeroWorkBinary(e)) out.add(e); return; }
    }
    if (SYSTEM.some(s => abs.startsWith(s)) && !bundle) return;
    if (abs === process.execPath) return;
    if (isZeroWorkBinary(abs) || APP_NAME.test(abs)) out.add(abs);
  };
  if (basename(cmd) === 'open') {
    // `open [-n|-a App|…] path…`: every bundle / executable argument is a launch.
    for (const a of args ?? []) { const s = String(a); if (s.startsWith('-')) continue; if (/\.app\/?$/.test(s) || fs.existsSync(s)) consider(s); }
  } else if (!cmd.includes('/') ) {
    // Bare names resolve through PATH: only a ZeroWork name matters (PATH never holds one in e2e).
    if (APP_NAME.test(cmd)) out.add(cmd);
  } else consider(cmd);
  return [...out];
}

/** Throws before a child_process call that would start a non-test-mode ZeroWork build. */
export function guardLaunch(command, args) {
  for (const target of launchTargets(command, Array.isArray(args) ? args : [])) assertTestModeBinary(target);
}

const INSTALLED = Symbol.for('zerowork.e2e.build_mode_guard');
if (!globalThis[INSTALLED]) {
  globalThis[INSTALLED] = true;
  const wrap = (name, shell) => {
    const original = childProcess[name];
    if (typeof original !== 'function') return;
    const check = (command, rest) => {
      if (shell) {
        // exec/execSync: shell string; check its first word (the program).
        const first = String(command).trim().match(/^(?:"([^"]+)"|'([^']+)'|(\S+))/);
        if (first) guardLaunch(first[1] ?? first[2] ?? first[3], []);
      } else guardLaunch(command, Array.isArray(rest[0]) ? rest[0] : []);
    };
    const guarded = function buildModeGuarded(command, ...rest) {
      check(command, rest);
      return original.call(this, command, ...rest);
    };
    // execFile / exec carry a custom promisify ({stdout, stderr}); keep it, guarded.
    const custom = original[promisify.custom];
    if (typeof custom === 'function') guarded[promisify.custom] = function buildModeGuardedPromise(command, ...rest) {
      check(command, rest);
      return custom.call(this, command, ...rest);
    };
    childProcess[name] = guarded;
  };
  for (const name of ['spawn', 'spawnSync', 'execFile', 'execFileSync']) wrap(name, false);
  for (const name of ['exec', 'execSync']) wrap(name, true);
  syncBuiltinESMExports();
}
