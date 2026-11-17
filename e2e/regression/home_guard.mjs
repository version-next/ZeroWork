/** Private-HOME isolation for e2e runs (used by run.ts and isolation_guard.mjs).
 *
 * Every run gets a private 0700 root /private/tmp/zw-e2e-home-XXXXXX with a fake HOME
 * (Library/{Application Support,Preferences,Caches}, Downloads, Documents, minimal shell rc
 * files), its own TMPDIR and XDG_* directories. The app must never see the real home:
 * HOME / CFFIXED_USER_HOME / TMPDIR / ZEROWORK_DATA_DIR of every app process have to resolve
 * below /private/tmp/zw-e2e-*. After each item the runner compares a snapshot of the places
 * where ZeroWork could leave traces in the REAL home and fails the item on any change.
 */
import {mkdtempSync, mkdirSync, writeFileSync, chmodSync, readdirSync, lstatSync, realpathSync, existsSync, unlinkSync} from 'node:fs';
import {join, resolve, basename} from 'node:path';
import {createHash} from 'node:crypto';
import {readFileSync, statSync} from 'node:fs';
import {userInfo} from 'node:os';

export const ROOT_PREFIX = '/private/tmp/zw-e2e-';

/** The real home directory from the user database, independent of $HOME. */
export function realHome() {
  return process.env.ZW_E2E_REAL_HOME_FOR_TEST ?? userInfo().homedir;
}

const RC = 'export PATH=/usr/bin:/bin:/usr/sbin:/sbin\nPS1="e2e %# "\nunsetopt BEEP 2>/dev/null\n';

/** Create the private root and return the environment that points everything into it. */
export function createIsolatedHome() {
  const root = mkdtempSync('/private/tmp/zw-e2e-home-');
  chmodSync(root, 0o700);
  const home = join(root, 'home'), tmp = join(root, 'tmp'), xdg = join(root, 'xdg');
  for (const d of ['Library/Application Support', 'Library/Preferences', 'Library/Caches', 'Downloads', 'Documents', 'Desktop'])
    mkdirSync(join(home, d), {recursive: true});
  for (const d of ['config', 'data', 'cache', 'state', 'runtime']) mkdirSync(join(xdg, d), {recursive: true, mode: 0o700});
  mkdirSync(tmp, {recursive: true, mode: 0o700});
  // Default data directory and an empty dialog-injection queue for the whole item: a script that
  // forgets its own ZEROWORK_DATA_DIR still stays private, and any system file dialog a test-mode
  // app opens is answered "cancel" instead of blocking the batch on a real NSOpenPanel.
  const data = join(root, 'data'), dialog = join(root, 'dialog');
  mkdirSync(data, {mode: 0o700});
  mkdirSync(dialog, {mode: 0o700});
  writeFileSync(join(home, '.zshrc'), RC);
  writeFileSync(join(home, '.zprofile'), 'export PATH=/usr/bin:/bin:/usr/sbin:/sbin\n');
  writeFileSync(join(home, '.zshenv'), '');
  writeFileSync(join(home, '.bash_profile'), 'export PATH=/usr/bin:/bin:/usr/sbin:/sbin\nPS1="e2e \\$ "\n');
  writeFileSync(join(home, '.bashrc'), 'PS1="e2e \\$ "\n');
  const env = {
    ZW_E2E_ROOT: root,
    HOME: home,
    CFFIXED_USER_HOME: home,
    TMPDIR: tmp + '/',
    ZDOTDIR: home,
    XDG_CONFIG_HOME: join(xdg, 'config'),
    XDG_DATA_HOME: join(xdg, 'data'),
    XDG_CACHE_HOME: join(xdg, 'cache'),
    XDG_STATE_HOME: join(xdg, 'state'),
    XDG_RUNTIME_DIR: join(xdg, 'runtime'),
    SSH_AUTH_SOCK: '',
    HISTFILE: join(home, '.zsh_history'),
    ZEROWORK_DATA_DIR: data,
    ZEROWORK_E2E_DIALOG_DIR: dialog,
    // Zig keeps its global cache under HOME; point it back at the shared one so a moved HOME never
    // starts a cold dependency fetch (scripts must not build anyway — see run.ts zig-out check).
    ZIG_GLOBAL_CACHE_DIR: join(realHome(), '.cache/zig'),
  };
  return {root, home, tmp, env};
}

const inside = (p) => {
  if (!p) return false;
  let r = resolve(String(p));
  try { r = realpathSync(r); } catch {}
  return r.startsWith(ROOT_PREFIX);
};

/** Throws when an app process would see anything outside the private root. */
export function assertIsolatedEnv(env, {requireDataDir}) {
  const problems = [];
  for (const key of ['HOME', 'CFFIXED_USER_HOME', 'TMPDIR']) if (!inside(env[key])) problems.push(`${key}=${env[key] ?? '(unset)'}`);
  if (requireDataDir || env.ZEROWORK_DATA_DIR !== undefined) if (!inside(env.ZEROWORK_DATA_DIR)) problems.push(`ZEROWORK_DATA_DIR=${env.ZEROWORK_DATA_DIR ?? '(unset)'}`);
  if (env.SSH_AUTH_SOCK) problems.push('SSH_AUTH_SOCK is set');
  if (problems.length) throw new Error(`[home_guard] refusing to start the app outside the private e2e root: ${problems.join(', ')}`);
}

/** Places in the REAL home that ZeroWork could touch. Paths are relative to the real home. */
const WATCHED = [
  {dir: 'Library/Application Support', match: (n) => /zerowork/i.test(n), depth: 2},
  {dir: 'Library/Preferences', match: (n) => /zerowork/i.test(n), depth: 1},
  {dir: 'Library/Caches', match: (n) => /zerowork/i.test(n), depth: 2},
  {dir: 'Library/HTTPStorages', match: (n) => /zerowork/i.test(n), depth: 2},
  {dir: 'Library/Saved Application State', match: (n) => /zerowork/i.test(n), depth: 2},
  {dir: 'Library/Logs', match: (n) => /zerowork/i.test(n), depth: 2},
  {dir: 'Downloads', match: () => true, depth: 0},
  {dir: 'Documents', match: () => true, depth: 0},
  {dir: 'Desktop', match: () => true, depth: 0},
  {dir: '.', match: (n) => /^\.(zsh_history|bash_history|zerowork.*)$/.test(n), depth: 0},
];

/** path → "mtimeMs:size" for the watched entries (and, to `depth`, below them). */
export function snapshotRealHome(home = realHome()) {
  const snap = new Map();
  const walk = (p, depth) => {
    let st; try { st = lstatSync(p); } catch { return; }
    snap.set(p, `${st.mtimeMs}:${st.size}`);
    if (depth <= 0 || !st.isDirectory()) return;
    let names = []; try { names = readdirSync(p); } catch { return; }
    for (const n of names) walk(join(p, n), depth - 1);
  };
  for (const w of WATCHED) {
    const base = join(home, w.dir);
    if (!existsSync(base)) continue;
    let names = []; try { names = readdirSync(base); } catch { continue; }
    for (const n of names) if (w.match(n)) walk(join(base, n), w.depth);
  }
  return snap;
}

export function diffSnapshots(before, after) {
  const changes = [];
  for (const [p, v] of after) if (!before.has(p)) changes.push(`new ${p}`); else if (before.get(p) !== v) changes.push(`modified ${p}`);
  for (const p of before.keys()) if (!after.has(p)) changes.push(`removed ${p}`);
  return changes;
}

export const isAppCommand = (command, env) =>
  env?.ZEROWORK_DATA_DIR !== undefined || /(^|\/)(zerowork[^/]*|ZeroWork|PreviewCheck|[a-z-]+-(preview|runner))$/.test(String(command));
export const isMainApp = (command) => ['zerowork', 'zerowork-frozen', 'ZeroWork', 'PreviewCheck'].includes(basename(String(command)));

/** The fake HOME of this run. Scripts compute every home-relative path from this, never from the real
 * home; throws when the script was started without the private root (run it through run.ts or
 * `node --import ./e2e/regression/isolation_guard.mjs`). */
export function isolatedHome() {
  const home = process.env.HOME;
  if (!process.env.ZW_E2E_ROOT || !home || !resolve(home).startsWith(ROOT_PREFIX)) throw new Error('[home_guard] no private e2e HOME: run through e2e/regression/run.ts or node --import ./e2e/regression/isolation_guard.mjs');
  return home;
}

/** Identify build products by content, not by name: scripts copy binaries under arbitrary names
 * (zerowork-frozen, file-workspace-fixture-frozen, bundles). ZW_E2E_PREFIX names the build prefix. */
let known = null;
function knownBinaries() {
  if (known) return known;
  known = new Map();   // size -> Map(hash -> name)
  const prefix = process.env.ZW_E2E_PREFIX;
  if (!prefix) return known;
  let names = [];
  try { names = readdirSync(join(prefix, 'bin')); } catch { return known; }
  for (const n of names) {
    const p = join(prefix, 'bin', n);
    try {
      const st = statSync(p);
      if (!st.isFile() || st.size < 1024 * 1024) continue;
      if (!known.has(st.size)) known.set(st.size, new Map());
      known.get(st.size).set(createHash('sha256').update(readFileSync(p)).digest('hex'), n);
    } catch {}
  }
  return known;
}
/** Name of the build product this executable is a copy of, or null. */
export function buildProductOf(command) {
  try {
    const p = resolve(String(command));
    const st = statSync(p);
    const bySize = knownBinaries().get(st.size);
    if (!bySize) return null;
    return bySize.get(createHash('sha256').update(readFileSync(p)).digest('hex')) ?? null;
  } catch { return null; }
}

/** Audited launchable build products and how they treat the data directory (see e2e/README.md).
 * `data`: honours ZEROWORK_DATA_DIR (must be set to a private dir); `none`: keeps no on-disk state and
 * was observed not to touch the real home; anything else (or unknown) is refused. */
export const PRODUCT_POLICY = {
  'zerowork': 'data',
  'settings-preview-runner': 'none',
  'file-workspace-preview': 'none',
  'auth-challenge-preview': 'none',
  'connection-progress-preview': 'none',
  'transfer-events-preview': 'none',
  'transfer-conflict-preview': 'none',
  'notification-preview': 'none',
  'bmc-kvm-preview': 'none',
  // Design-mockup preview (`zig build mockup -Dmockup=yix_spike`): pure UI, links no ghostty/libssh2, no data dir.
  'mockup-yix_spike': 'none',
  // home-isolation (docs/ui-revamp/HOME_ISOLATION.md): previews are isolated builds — they honour
  // ZEROWORK_DATA_DIR and refuse to start without a private HOME, so applog / AI-session locks stay private.
  'transfer-controls-preview': 'data',
  'forward-config-preview': 'data',
  // PL4c ai.launcher state matrix (src/features/ai/pane/preview): fabricated states, no AI service; isolated build.
  'ai-launcher-preview': 'data',
  // usage-e2e-debt audit (e2e/README.md「预览产物审计」): component previews built through src/preview.zig — isolated
  // builds (refuse to start without a private HOME, honour ZEROWORK_DATA_DIR), fabricated in-memory facts only, no
  // applog / session store / SSH or ghostty linked; observed to leave no file in HOME, TMPDIR or the data directory.
  'close-confirmation-preview': 'none',
  'ai-recovery-preview': 'none',
  'execution-result-preview': 'none',
  'task-finish-preview': 'none',
  'ai-empty-recent-preview': 'none',
  'inventory-grant-preview': 'none',
  'button-policy-preview': 'none',
  'socks-info-preview': 'none',
  // Production composer area (Composer.View) with fabricated requests and the in-memory question broker.
  'composer-interaction-preview': 'none',
};
export function assertProductAllowed(product, env) {
  const policy = PRODUCT_POLICY[product];
  if (policy === undefined) throw new Error(`[home_guard] refusing to start unaudited build product ${product}`);
  if (policy.startsWith('refuse')) throw new Error(`[home_guard] refusing to start ${product}: ${policy.slice(8)}`);
  if (policy === 'data' && !env.ZEROWORK_DATA_DIR) throw new Error(`[home_guard] refusing to start ${product} without ZEROWORK_DATA_DIR`);
}

/* ---- Crash reports (macOS ReportCrash) ------------------------------------------------------------
 * When a test binary crashes, ReportCrash (an OS daemon, not the app) writes
 *   <real home>/Library/Logs/DiagnosticReports/<process>-YYYY-MM-DD-HHMMSS[.N].ips
 *   <real home>/Library/Application Support/CrashReporter/<process>_<UUID>.plist   (per-process, rewritten)
 * These are allowed — recorded, then the new ones of this run are deleted — only when the process is one
 * of our own test binaries (OWN_CRASH_PROCESS) and the report falls in this run's time window. Any other
 * ZeroWork-related change there (unknown own-ish name, outside the window) is a real-home touch as before.
 * Reports of unrelated processes (other apps) are ignored. */
export const CRASH_DIRS = ['Library/Logs/DiagnosticReports', 'Library/Application Support/CrashReporter'];
export const OWN_CRASH_PROCESS = /^(unit-tests|ui-tests|zerowork|[A-Za-z0-9_.]+(?:-[A-Za-z0-9_.]+)*-preview)$/;
const IPS = /^(.+)-(\d{4})-(\d\d)-(\d\d)-(\d\d)(\d\d)(\d\d)(?:\.\d+)?\.ips$/;
const CRASH_PLIST = /^(.+)_[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\.plist$/;

/** {process, kind, stampMs} of a crash-report file name, or null for anything else. */
export function parseCrashName(name) {
  let m = IPS.exec(name);
  if (m) return {process: m[1], kind: 'ips', stampMs: new Date(+m[2], +m[3] - 1, +m[4], +m[5], +m[6], +m[7]).getTime()};
  m = CRASH_PLIST.exec(name);
  if (m) return {process: m[1], kind: 'plist', stampMs: null};
  return null;
}

/** path → "mtimeMs:size" for the files directly in the crash-report directories of the (real) home. */
export function snapshotCrashReports(home = realHome()) {
  const snap = new Map();
  for (const d of CRASH_DIRS) {
    const base = join(home, d);
    let names = []; try { names = readdirSync(base); } catch { continue; }
    for (const n of names) {
      try { const st = lstatSync(join(base, n)); if (st.isFile()) snap.set(join(base, n), `${st.mtimeMs}:${st.size}`); } catch {}
    }
  }
  return snap;
}

/** Split crash-directory changes between two snapshots into allowed (own test binary, inside the window)
 * and alarms (ZeroWork-related otherwise). `related(process)` widens what counts as ZeroWork-related
 * (e.g. names of the build products); unrelated processes are ignored. Removals of own reports are
 * ignored (they are this guard's own cleanup, possibly from a parallel item). */
export function classifyCrashChanges(before, after, windowStartMs, related = () => false) {
  const allowed = [], alarms = [];
  const slackMs = 2000;   // file-name stamps have 1 s resolution
  const isRelated = (p) => /zerowork/i.test(p) || OWN_CRASH_PROCESS.test(p) || related(p);
  const consider = (path, change) => {
    const parsed = parseCrashName(basename(path));
    if (!parsed) { if (/zerowork/i.test(basename(path))) alarms.push(`${change} ${path}`); return; }
    if (!isRelated(parsed.process)) return;
    if (change === 'removed') { if (!OWN_CRASH_PROCESS.test(parsed.process)) alarms.push(`${change} ${path}`); return; }
    let mtime = 0; try { mtime = statSync(path).mtimeMs; } catch {}
    const inWindow = mtime >= windowStartMs - slackMs && (parsed.stampMs === null || parsed.stampMs >= windowStartMs - slackMs);
    if (OWN_CRASH_PROCESS.test(parsed.process) && inWindow) allowed.push({path, change, process: parsed.process, kind: parsed.kind});
    else alarms.push(`${change} ${path}`);
  };
  for (const [p, v] of after) if (!before.has(p)) consider(p, 'new'); else if (before.get(p) !== v) consider(p, 'modified');
  for (const p of before.keys()) if (!after.has(p)) consider(p, 'removed');
  return {allowed, alarms};
}

/** Delete the allowed crash reports this run created (`new`); per-process CrashReporter plists that
 * existed before the run are only rewritten by the OS and are kept (recorded as `kept`). */
export function cleanupCrashReports(allowed) {
  const done = [];
  for (const a of allowed) {
    if (a.change !== 'new') { done.push({...a, action: 'kept (pre-existing, rewritten by ReportCrash)'}); continue; }
    try { unlinkSync(a.path); done.push({...a, action: 'deleted'}); } catch (e) { done.push({...a, action: `delete failed: ${e?.code ?? e}`}); }
  }
  return done;
}
