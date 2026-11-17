/** Full e2e regression runner (no dependencies, no network).
 *
 *   zw-nonet.sh zig build install <preview steps> -Dtest-mode=true -j2 --prefix /private/tmp/zw-X
 *   zw-nonet.sh node e2e/regression/run.ts --binary /private/tmp/zw-X/bin/zerowork --out /abs/evidence
 *
 * Options:
 *   --binary PATH        test-mode zerowork; its prefix (PATH/../..) also provides preview binaries
 *   --out DIR            output root: SUMMARY.tsv, logs/<item>.log, <item>/ (script output + screenshots)
 *   --manifest PATH      default e2e/regression/manifest.json
 *   --only a,b           run only these names (name or name:variant)
 *   --from-failed TSV    rerun the items whose result is not PASS in an earlier SUMMARY.tsv
 *   --list               print the runnable items with their command lines and exit
 *   --jobs N             parallel items (default 1; see README: real windows share pointer/focus state)
 *   --timeout-scale K    multiply every per-item timeout
 *   --class C            run entries of another class instead of runnable. `manual` entries need a person
 *                        (real NSOpenPanel, CUA hand-off, authorization / Touch ID prompts) and are never in
 *                        the batch; `--class manual --list` prints them for a supervised run
 *   --tag T / --skip-tag T  only / all but the entries carrying manifest tag T
 *   --python PATH        audited Python for entries marked `"python": true` (loopback SSH/SFTP peers); default
 *                        $ZW_TEST_PYTHON. Such an entry gets ZW_TEST_PYTHON and `{python}`; a `.py` script is run
 *                        as `PATH -I script`. A run selecting these entries requires Python with Paramiko.
 *
 * Every item gets a private 0700 root /private/tmp/zw-e2e-home-* (home_guard.createIsolatedHome): HOME =
 * CFFIXED_USER_HOME, TMPDIR, ZDOTDIR, XDG_*, ZEROWORK_DATA_DIR, an empty ZEROWORK_E2E_DIALOG_DIR (any system
 * file dialog of a test-mode app is answered "cancel"), ZIG_GLOBAL_CACHE_DIR, SSH_AUTH_SOCK cleared; and a
 * timeout (manifest `timeout`, default 300 s, × --timeout-scale).
 * Every script is preloaded with exit_guard.mjs (children are SIGTERMed when it ends) and
 * isolation_guard.mjs (any config.toml it writes gets `[updates] auto_check=false`).
 * Every item also gets its own private pasteboard (ZENIT_E2E_PASTEBOARD, e2e/private_pasteboard.ts): the app's copy /
 * paste never reaches the person's clipboard, and an item during which the general pasteboard changed fails
 * (CLIPBOARD-TOUCHED).
 * Every item gets its own output directory and its own process group. After an item ends
 * (or times out) the runner sends SIGTERM to whatever is left in that group and to orphaned
 * (parent 1) processes started during the run whose executable is one of the prefix's
 * binaries (or a byte-identical copy). It never uses SIGKILL.
 * Crash reports that macOS ReportCrash writes into the real home for our own test binaries during this run
 * (home_guard.OWN_CRASH_PROCESS: unit-tests, ui-tests, zerowork, *-preview) are allowed: listed in
 * CRASH_REPORTS.tsv and the new ones deleted at the end of the run. Any other ZeroWork-related change in the
 * crash-report directories counts as a real-home touch (the run stops).
 */
import assert from 'node:assert/strict';
import {spawn, execFile, execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {existsSync, readFileSync, statSync, lstatSync, readlinkSync, realpathSync, symlinkSync, unlinkSync, readdirSync} from 'node:fs';
import {mkdir, open, readFile, writeFile, appendFile, rm} from 'node:fs/promises';
import {dirname, join, resolve, basename} from 'node:path';
import {fileURLToPath} from 'node:url';
// @ts-ignore -- plain ESM helper: refuses non-test-mode ZeroWork binaries (installs on import)
import {assertTestModeBinary, isZeroWorkBinary} from './build_mode_guard.mjs';
// @ts-ignore -- plain ESM helper shared with the preload
import {createIsolatedHome, snapshotRealHome, diffSnapshots, snapshotCrashReports, classifyCrashChanges, cleanupCrashReports} from './home_guard.mjs';
import {generalPasteboardChangeCount, releasePasteboard} from '../private_pasteboard.ts';

type Entry = {name: string, script: string, class: string, args?: string[], env?: Record<string, string>, variants?: string[],
  preview?: string[], foreground?: boolean, tags?: string[], timeout?: number, pass?: string[], note?: string, reason?: string, zigOut?: boolean,
  python?: boolean};
type Item = {entry: Entry, variant: string | null, id: string};

const repo = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const argv = process.argv.slice(2), opt: Record<string, string> = Object.create(null), flags = new Set<string>();
const valueOptions = new Set(['--binary', '--out', '--manifest', '--only', '--from-failed', '--jobs', '--timeout-scale', '--class', '--tag', '--skip-tag', '--python']);
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (a === '--list') { flags.add(a); continue; }
  assert(valueOptions.has(a), `unknown option ${a}`);
  assert(opt[a] === undefined, `duplicate option ${a}`);
  assert(argv[i + 1] && !argv[i + 1].startsWith('--'), `missing value for ${a}`);
  opt[a] = argv[++i];
}
const manifestPath = resolve(opt['--manifest'] ?? join(repo, 'e2e/regression/manifest.json'));
const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
const wantClass = opt['--class'] ?? 'runnable';
const items: Item[] = [];
for (const entry of manifest.entries as Entry[]) {
  if (entry.class !== wantClass) continue;
  for (const variant of entry.variants ?? [null]) items.push({entry, variant, id: variant ? `${entry.name}:${variant}` : entry.name});
}
let selected = items;
if (opt['--only']) {
  const want = new Set(opt['--only'].split(',').map(s => s.trim()).filter(Boolean));
  selected = items.filter(i => want.has(i.id) || want.has(i.entry.name));
  const known = new Set(items.flatMap(i => [i.id, i.entry.name]));
  for (const w of want) assert(known.has(w), `--only: unknown item ${w}`);
}
if (opt['--tag']) selected = selected.filter(i => (i.entry.tags ?? []).includes(opt['--tag']));
if (opt['--skip-tag']) selected = selected.filter(i => !(i.entry.tags ?? []).includes(opt['--skip-tag']));
if (opt['--from-failed']) {
  const rows = readFileSync(resolve(opt['--from-failed']), 'utf8').trim().split('\n').slice(1).map(l => l.split('\t'));
  const failed = new Set(rows.filter(r => r[7] !== 'PASS').map(r => r[1] ? `${r[0]}:${r[1]}` : r[0]));
  selected = selected.filter(i => failed.has(i.id));
}

const binary = opt['--binary'] ? resolve(opt['--binary']) : '';
const prefix = binary ? dirname(dirname(binary)) : '<prefix>';
const fixtures = join(repo, 'e2e/regression/fixtures');
const python = opt['--python'] ?? process.env.ZW_TEST_PYTHON ?? '';
const expand = (s: string, out: string, variant: string | null, sha: string) => s
  .replaceAll('{python}', python || '<python>').replaceAll('{bin}', binary || '<binary>').replaceAll('{prefix}', prefix).replaceAll('{out}', out).replaceAll('{sha}', sha)
  .replaceAll('{repo}', repo).replaceAll('{fixtures}', fixtures).replaceAll('{variant}', variant ?? '');
const fileName = (id: string) => id.replace(/[^A-Za-z0-9_.-]+/g, '-');
const jobs = Number(opt['--jobs'] ?? 1);
assert(Number.isSafeInteger(jobs) && jobs > 0, '--jobs must be a positive integer');
const timeoutScale = Number(opt['--timeout-scale'] ?? 1);
assert(Number.isFinite(timeoutScale) && timeoutScale > 0, '--timeout-scale must be a positive finite number');

if (flags.has('--list')) {
  for (const i of selected) {
    const out = `<out>/${fileName(i.id)}`;
    const env = Object.entries(i.entry.env ?? {}).map(([k, v]) => `${k}=${expand(v, out, i.variant, '<sha>')} `).join('');
    console.log(`${i.id.padEnd(48)} ${String(i.entry.timeout ?? 300).padStart(4)}s  ${env}${i.entry.script.endsWith('.py') ? '{python} -I' : 'node'} ${i.entry.script} ${(i.entry.args ?? []).map(a => expand(a, out, i.variant, '<sha>')).join(' ')}`);
  }
  console.log(`${selected.length} item(s)`);
  process.exit(0);
}

assert(selected.length > 0, 'no regression items selected');
const names = new Set<string>();
for (const item of selected) {
  const {id, entry} = item;
  const name = fileName(id);
  assert(name && name !== '.' && name !== '..' && !names.has(name), `invalid or duplicate artifact name: ${id}`);
  names.add(name);
  const timeoutMs = (entry.timeout ?? 300) * timeoutScale * 1000;
  assert(Number.isFinite(timeoutMs) && timeoutMs >= 1 && timeoutMs <= 0x7fffffff, `invalid timeout for ${id}: ${timeoutMs}ms`);
}
if (selected.some(({entry}) => entry.python || entry.script.endsWith('.py'))) {
  assert(python, 'selected regression items need --python (audited Python with Paramiko)');
  try {
    execFileSync(python, ['-I', '-c', 'import paramiko'], {stdio: 'ignore', timeout: 10_000});
  } catch {
    throw new Error(`--python must run and import Paramiko in isolated mode: ${python}`);
  }
}
assert(binary && existsSync(binary), '--binary must name an existing test-mode zerowork');
assert(opt['--out'], '--out is required');
const outRoot = resolve(opt['--out']);
await mkdir(join(outRoot, 'logs'), {recursive: true});
const sha256 = (path: string) => createHash('sha256').update(readFileSync(path)).digest('hex');
const binarySha = sha256(binary);
// Only a -Dtest-mode=true build honours ZEROWORK_DATA_DIR; a formal build only reads the real home.
// The same marker check guards every launch in the item scripts (isolation_guard → build_mode_guard).
assertTestModeBinary(binary, 'run the regression batch with');
const prefixBins = readdirSync(join(prefix, 'bin')).map(n => join(prefix, 'bin', n)).filter(p => statSync(p).isFile());
// A prefix mixes builds only by mistake (an install of a formal build over a test-mode one): refuse it whole.
for (const p of prefixBins) if (isZeroWorkBinary(p)) assertTestModeBinary(p, 'run the regression batch with the prefix product');
const binHashes = new Map<number, Set<string>>(); // size → hashes, for copies made by scripts
for (const p of prefixBins) { const size = statSync(p).size; if (!binHashes.has(size)) binHashes.set(size, new Set()); binHashes.get(size)!.add(sha256(p)); }

// Many scripts import ../zig-out/share/zenit/harness/client.ts or fall back to zig-out/bin/*.
// zig-out must therefore be this prefix (absent → linked for the run, removed afterwards).
const zigOut = join(repo, 'zig-out');
let linkedZigOut = false, restoreLink: string | null = null;
const isLink = () => { try { return lstatSync(zigOut).isSymbolicLink(); } catch { return false; } };
if (!existsSync(zigOut) && !isLink()) {
  symlinkSync(prefix, zigOut); linkedZigOut = true;
} else if (isLink() && realpathSync(zigOut) !== realpathSync(prefix)) {
  // A symlink (e.g. left by an earlier run for another build) is only a pointer: retarget it for this run.
  restoreLink = readlinkSync(zigOut); unlinkSync(zigOut); symlinkSync(prefix, zigOut); linkedZigOut = true;
} else {
  const same = (() => { try { return realpathSync(zigOut) === realpathSync(prefix) || sha256(join(zigOut, 'bin/zerowork')) === binarySha; } catch { return false; } })();
  assert(same, `${zigOut} exists and is not this test-mode prefix; remove it (or point it at ${prefix}) so scripts that fall back to zig-out cannot start another build`);
}
const cleanupLink = () => {
  if (!linkedZigOut) return;
  try { if (readlinkSync(zigOut) === prefix) { unlinkSync(zigOut); if (restoreLink) symlinkSync(restoreLink, zigOut); } } catch {}
  linkedZigOut = false;
};
process.on('exit', cleanupLink);
const activeGroups = new Set<number>();
for (const signal of ['SIGINT', 'SIGTERM', 'SIGHUP'] as const) process.once(signal, () => {
  console.log(`\n${signal}: stopping ${activeGroups.size} running item(s)`);
  for (const pgid of activeGroups) { try { process.kill(pgid, 'SIGTERM'); } catch {} }   // exit_guard stops each app
  setTimeout(() => { for (const pgid of activeGroups) { try { process.kill(-pgid, 'SIGTERM'); } catch {} } cleanupLink(); process.exit(130); }, 5000);
});

type Proc = {pid: number, cmd: string};
// ps is setuid and cannot be exec'd inside the zw-nonet sandbox; pgrep can.
function pgrep(args: string[]): Proc[] {
  let text = '';
  try { text = execFileSync('pgrep', [...args, '-lf'], {encoding: 'utf8'}); } catch (e: any) { if (e.status !== 1) throw e; }
  const out: Proc[] = [];
  for (const line of text.split('\n')) {   // arguments may contain newlines: continuation lines belong to the previous process
    const m = line.match(/^(\d+) (.*)$/);
    if (m) out.push({pid: Number(m[1]), cmd: m[2]}); else if (out.length) out[out.length - 1].cmd += '\n' + line;
  }
  return out;
}
/** Every process; same parsing as pgrep() (the pattern must follow the flags). */
function pgrepAll(): Proc[] {
  let text = '';
  try { text = execFileSync('pgrep', ['-lf', '.'], {encoding: 'utf8'}); } catch (e: any) { if (e.status !== 1) throw e; }
  const out: Proc[] = [];
  for (const line of text.split('\n')) {
    const m = line.match(/^(\d+) (.*)$/);
    if (m) out.push({pid: Number(m[1]), cmd: m[2]}); else if (out.length) out[out.length - 1].cmd += '\n' + line;
  }
  return out;
}
/** Executable path from a command line whose path may itself contain spaces (app bundles). */
const exePath = (cmd: string) => { const parts = cmd.split(' '); for (let n = 1; n <= parts.length; n++) { const p = parts.slice(0, n).join(' '); try { if (statSync(p).isFile()) return p; } catch {} } return parts[0]; };
const ownBinary = (path: string) => {
  if (path.startsWith(prefix + '/bin/')) return true;
  try { const st = statSync(path); return binHashes.get(st.size)?.has(sha256(path)) ?? false; } catch { return false; }
};
const alive = (pid: number) => { try { process.kill(pid, 0); return true; } catch { return false; } };
const sleep = (ms: number) => new Promise(r => setTimeout(r, ms));
const orphanSnapshot = () => new Set(pgrep(['-P', '1']).map(p => p.pid));

/** SIGTERM leftovers of one item: its process group, plus new orphaned (parent 1) processes of an own binary. */
async function sweep(pgid: number, before: Set<number>, log: string): Promise<string[]> {
  const found: Proc[] = [];
  for (let round = 0; round < 3; round++) {
    const left = [...pgrep(['-g', String(pgid)]), ...pgrep(['-P', '1']).filter(p => !before.has(p.pid) && ownBinary(exePath(p.cmd)))]
      .filter(p => p.pid !== process.pid && alive(p.pid));
    if (!left.length) break;
    for (const p of left) {
      if (!found.some(f => f.pid === p.pid)) found.push(p);
      try { process.kill(p.pid, 'SIGTERM'); } catch {}
    }
    for (let t = 0; t < 50 && left.some(p => alive(p.pid)); t++) await sleep(100);
  }
  const survivors = found.filter(p => alive(p.pid));
  if (found.length) await appendFile(log, `\n[run.ts] leaked processes sent SIGTERM: ${found.map(p => `${p.pid} ${p.cmd}`).join('; ')}${survivors.length ? ` — STILL ALIVE: ${survivors.map(p => p.pid).join(', ')}` : ''}\n`);
  return found.map(p => basename(exePath(p.cmd)).replace(/[\t,]/g, '_') + (survivors.includes(p) ? '(alive)' : ''));
}

/** Scripts often freeze a copy of the binary (zerowork-frozen, bundles, zw_ipc.so) into their output
 * directory. Evidence keeps logs, screenshots and reports only: delete byte-identical copies of
 * {prefix}/bin/* after the item (they are hundreds of MB each). */
function pruneBinaryCopies(dir: string): string[] {
  const removed: string[] = [];
  const walk = (d: string, depth: number) => {
    let names: string[] = [];
    try { names = readdirSync(d); } catch { return; }
    for (const n of names) {
      const p = join(d, n);
      let st; try { st = lstatSync(p); } catch { continue; }
      if (st.isDirectory()) { if (depth < 6) walk(p, depth + 1); continue; }
      if (!st.isFile() || !binHashes.get(st.size)?.has(sha256(p))) continue;
      try { unlinkSync(p); removed.push(p.slice(dir.length + 1)); } catch {}
    }
  };
  walk(dir, 0);
  return removed;
}

/** Read the script's own verdict: report*.json / harness-report.json / *-report.json at top level or one level down. */
async function reportStatus(dir: string): Promise<string> {
  const found: string[] = [];
  const visit = (d: string, depth: number) => {
    let names: string[] = [];
    try { names = readdirSync(d); } catch { return; }
    for (const n of names) {
      const p = join(d, n);
      let st; try { st = statSync(p); } catch { continue; }
      if (st.isDirectory()) { if (depth < 1) visit(p, depth + 1); continue; }
      if (!/^(report.*|harness-report|native-report|.*-report)\.json$/.test(n) || /^peer-report/.test(n)) continue;
      try {
        const j = JSON.parse(readFileSync(p, 'utf8'));
        const s = typeof j.status === 'string' ? j.status : j.ok === true ? 'passed' : j.ok === false ? 'failed' : typeof j.result === 'string' ? j.result : null;
        if (s) found.push(s);
      } catch { found.push('unreadable'); }
    }
  };
  visit(dir, 0);
  if (!found.length) return 'none';
  const bad = found.find(s => !/^(passed|captured|ok)$/.test(s));  // the worst verdict wins
  return bad ?? found[0];
}

const realHomeTouched: string[] = [];
// Crash reports: everything ReportCrash writes for our own binaries from now on is inside this run's window.
const runStartMs = Date.now();
const crashAtStart = snapshotCrashReports();
const productNames = new Set(prefixBins.map(p => basename(p)));
const crashRelated = (proc: string) => productNames.has(proc);
const crashAllowedSeen = new Map<string, string>();   // path → item that first saw it
let aborted = false;
const summaryPath = join(outRoot, 'SUMMARY.tsv');
const header = 'name\tvariant\texit\treport_status\tseconds\tleaks\tlog\tresult\n';
await writeFile(summaryPath, header);
const started = Date.now();
let pass = 0, fail = 0;
console.log(`binary ${binary}\nsha256 ${binarySha}\nprefix ${prefix}\nitems ${selected.length}, jobs ${jobs}${linkedZigOut ? `\nlinked ${zigOut} -> ${prefix} for this run` : ''}`);

// The app's private ZLE directories (src/local/trusted_edit_native.c): isolated builds create
// <TMPDIR>/zw-edit-<uid>-XXXXXX, or /tmp/zw-edit-<uid>-t<fnv32(realpath TMPDIR)>-XXXXXX when the
// socket path would not fit. After the item every one of them must be gone; tagged /tmp leftovers
// are removed here because they are outside the item root that is deleted below.
async function trustedEditLeftovers(tmpdir: string | undefined): Promise<string[]> {
  if (!tmpdir) return [];
  const {readdir, realpath} = await import('node:fs/promises');
  const root = await realpath(tmpdir).catch(() => tmpdir);
  let tag = 2166136261;
  for (const b of Buffer.from(root)) tag = Math.imul(tag ^ b, 16777619) >>> 0;
  const uid = process.getuid!();
  const found: string[] = [];
  for (const name of await readdir(root).catch(() => [] as string[])) if (name.startsWith(`zw-edit-${uid}-`)) found.push(join(root, name));
  const shortPrefix = `zw-edit-${uid}-t${tag.toString(16).padStart(8, '0')}-`;
  for (const name of await readdir('/private/tmp').catch(() => [] as string[])) if (name.startsWith(shortPrefix)) {
    found.push(join('/private/tmp', name));
    await rm(join('/private/tmp', name), {recursive: true, force: true}).catch(() => {});
  }
  return found;
}

/** Collects every process descended from `root` while the item runs. The app's shells live in their own
 *  sessions (forkpty), outside the item's process group: when the app ends they get SIGHUP and still write
 *  back into the private home (zsh: `.zsh_history`), so the private root may only go once they are gone. */
function trackTree(root: number) {
  const tree = new Map<number, string>();   // pid → command line, to tell a reused pid from ours
  let stopped = false;
  const children = (pids: number[]) => new Promise<Proc[]>(done => execFile('pgrep', ['-P', pids.join(','), '-lf'], {encoding: 'utf8'}, (_e, text) => {
    const out: Proc[] = [];
    for (const line of String(text ?? '').split('\n')) { const m = line.match(/^(\d+) (.*)$/); if (m) out.push({pid: Number(m[1]), cmd: m[2]}); }
    done(out);
  }));
  const scan = async () => {
    for (let frontier = [root, ...[...tree.keys()].filter(alive)]; frontier.length;) {
      const fresh = (await children(frontier)).filter(p => !tree.has(p.pid));
      for (const p of fresh) tree.set(p.pid, p.cmd);
      frontier = fresh.map(p => p.pid);
    }
  };
  const loop = (async () => { while (!stopped) { await scan().catch(() => {}); await sleep(250); } })();
  return {
    /** Stops polling, then waits for the collected processes to exit (SIGTERM after `graceMs`, never SIGKILL). */
    async settle(log: string, graceMs = 10_000): Promise<string[]> {
      stopped = true; await loop; await scan().catch(() => {});
      // Ours = still running with the command line we saw (pid reuse would show a different one).
      const running = () => { const now = new Map(pgrepAll().map(p => [p.pid, p.cmd])); return [...tree.keys()].filter(p => alive(p) && now.get(p) === tree.get(p)); };
      const waitGone = async (ms: number) => { for (let t = 0; t < ms / 100 && running().length; t++) await sleep(100); };
      await waitGone(graceMs);
      let left = running();
      if (left.length) {
        for (const p of left) { try { process.kill(p, 'SIGTERM'); } catch {} }
        await waitGone(5_000);
        const now = running(), survivors = left.filter(p => now.includes(p));
        await appendFile(log, `\n[run.ts] descendants still running ${graceMs / 1000}s after the item ended, sent SIGTERM: ${left.map(p => `${p} ${tree.get(p)}`).join('; ')}${survivors.length ? ` — STILL ALIVE: ${survivors.join(', ')}` : ''}\n`);
        left = survivors;
      }
      return left.map(p => basename(exePath(tree.get(p)!)).replace(/[\t,]/g, '_') + '(alive)');
    },
  };
}

async function runItem(item: Item) {
  const {entry, variant, id} = item;
  const out = join(outRoot, fileName(id)), log = join(outRoot, 'logs', fileName(id) + '.log');
  await rm(out, {recursive: true, force: true});
  // Some scripts insist on creating the directory themselves (mkdir recursive:false); give them the parent only.
  await mkdir(dirname(out), {recursive: true});
  const missing = (entry.preview ?? []).filter(p => !existsSync(join(prefix, 'bin', p)));
  const t0 = Date.now();
  let exit = 'missing-binary', status = 'none', leaks: string[] = [];
  let itemRoot: string | null = null, homeBefore: Map<string, string> | null = null, homeChanges: string[] = [];
  let crashBefore: Map<string, string> | null = null;
  let editLeftovers: string[] = [];
  let generalBefore = 0, clipboardTouched = false;
  if (missing.length) {
    await writeFile(log, `missing preview binaries under ${prefix}/bin: ${missing.join(', ')}\n`);
  } else {
    const args = (entry.args ?? []).map(a => expand(a, out, variant, binarySha));
    // Private root per item (/private/tmp/zw-e2e-home-*): fake HOME, TMPDIR (symlink-free: the app refuses
    // data directories reached through /var → /private/var), ZDOTDIR, XDG_*; deleted after the item.
    const isolated = createIsolatedHome();
    itemRoot = isolated.root;
    const env: Record<string, string> = {...process.env as Record<string, string>, ...isolated.env, ZW_E2E_PREFIX: prefix};
    // Batch runs never wait for a person: drop opt-in human hand-off switches (e.g. ZW_SKILLS_PICKER_HANDOFF,
    // which makes a script wait for a real NSOpenPanel) unless the manifest entry sets them itself.
    for (const k of Object.keys(env)) if (/HANDOFF/.test(k)) delete env[k];
    if (entry.python) env.ZW_TEST_PYTHON = python;
    // Clipboard isolation (e2e/private_pasteboard.ts): the app copies to / pastes from this item's own named pasteboard
    // (zenit `ZENIT_E2E_PASTEBOARD`), never the person's general pasteboard; scripts read it through the helper.
    env.ZENIT_E2E_PASTEBOARD = `zw-e2e.${process.pid}.${id.replace(/[^A-Za-z0-9._-]/g, '_')}`;
    for (const [k, v] of Object.entries(entry.env ?? {})) env[k] = expand(v, out, variant, binarySha);
    const fh = await open(log, 'w');
    await fh.write(`# ${id}\n# cwd ${repo}\n# private root ${isolated.root}\n# ${Object.entries(entry.env ?? {}).map(([k, v]) => `${k}=${expand(v, out, variant, binarySha)}`).join(' ')} node ${entry.script} ${args.join(' ')}\n\n`);
    const before = orphanSnapshot();
    homeBefore = snapshotRealHome();
    crashBefore = snapshotCrashReports();
    generalBefore = generalPasteboardChangeCount();
    // A Python driver (it starts the app itself through build_mode_guard.py) runs isolated (-I); node scripts get the guards preloaded.
    const child = entry.script.endsWith('.py')
      ? spawn(python, ['-I', join(repo, entry.script), ...args], {cwd: repo, env, detached: true, stdio: ['ignore', fh.fd, fh.fd]})
      : spawn(process.execPath, ['--import', join(repo, 'e2e/regression/exit_guard.mjs'), '--import', join(repo, 'e2e/regression/isolation_guard.mjs'), join(repo, entry.script), ...args],
      {cwd: repo, env, detached: true, stdio: ['ignore', fh.fd, fh.fd]});
    const pgid = child.pid!;
    activeGroups.add(pgid);
    const tree = trackTree(pgid);
    const limit = (entry.timeout ?? 300) * timeoutScale * 1000;
    let timedOut = false;
    const code: number | string = await new Promise(done => {
      const timer = setTimeout(async () => {
        timedOut = true;
        try { process.kill(pgid, 'SIGTERM'); } catch {}      // node first: exit_guard stops its children
        await sleep(10_000);
        try { process.kill(-pgid, 'SIGTERM'); } catch {}     // then the whole group
      }, limit);
      child.once('close', (c, s) => { clearTimeout(timer); done(c ?? s ?? 'signal'); });
    });
    await fh.close();
    activeGroups.delete(pgid);
    exit = timedOut ? 'timeout' : String(code);
    leaks = await sweep(pgid, before, log);
    leaks.push(...await tree.settle(log));
    status = await reportStatus(out);
    homeChanges = diffSnapshots(homeBefore!, snapshotRealHome());
    const crash = classifyCrashChanges(crashBefore!, snapshotCrashReports(), runStartMs, crashRelated);
    homeChanges.push(...crash.alarms);
    for (const a of crash.allowed) if (!crashAllowedSeen.has(a.path)) crashAllowedSeen.set(a.path, id);
    if (crash.allowed.length) await appendFile(log, `\n[run.ts] crash report(s) of own test binaries (allowed, deleted at the end of the run): ${crash.allowed.map((a: any) => `${a.change} ${a.path}`).join('; ')}\n`);
    if (homeChanges.length) await appendFile(log, `\n[run.ts] REAL HOME TOUCHED during this item (item fails): ${homeChanges.join('; ')}\n`);
    // The general pasteboard is the person's clipboard: an item must not change it. (A copy made by the person during
    // the item also shows up here — rerun then.)
    const generalAfter = generalPasteboardChangeCount();
    if (generalAfter !== generalBefore) {
      clipboardTouched = true;
      await appendFile(log, `\n[run.ts] SYSTEM CLIPBOARD CHANGED during this item (item fails): general pasteboard changeCount ${generalBefore} -> ${generalAfter}; the app and the script must use ZENIT_E2E_PASTEBOARD=${env.ZENIT_E2E_PASTEBOARD} (e2e/private_pasteboard.ts)\n`);
    }
    try { releasePasteboard(env.ZENIT_E2E_PASTEBOARD); } catch {}
    editLeftovers = await trustedEditLeftovers(isolated.env.TMPDIR);
    const pruned = pruneBinaryCopies(out);
    if (pruned.length) await appendFile(log, `\n[run.ts] removed ${pruned.length} copied build binaries from the output directory: ${pruned.join(', ')}\n`);
  }
  const seconds = Math.round((Date.now() - t0) / 1000);
  const passSet = entry.pass ?? ['passed'];
  // `passed_pending_<x>_review`: the script's automated checks passed and it leaves screenshots for a human look.
  const ok = homeChanges.length === 0 && editLeftovers.length === 0 && !clipboardTouched && exit === '0' && (passSet.includes(status) || /^(passed|captured)_pending_[a-z]+_review$/.test(status));
  if (clipboardTouched && !homeChanges.length) status = 'CLIPBOARD-TOUCHED';
  if (homeChanges.length) {
    status = 'REAL-HOME-TOUCHED';
    realHomeTouched.push(`${id}: ${homeChanges.join('; ')}`);
    // Hard stop: no further item starts, running ones are terminated (exit_guard stops their apps).
    aborted = true;
    queue.length = 0; alone.length = 0;
    for (const pgid of activeGroups) { try { process.kill(pgid, 'SIGTERM'); } catch {} }
  }
  ok ? pass++ : fail++;
  if (editLeftovers.length) await appendFile(log, `\n[run.ts] trusted-edit temp directories left behind (item fails, removed now): ${editLeftovers.join(', ')}\n`);
  if (itemRoot) await rm(itemRoot, {recursive: true, force: true}).catch(() => {});
  await appendFile(summaryPath, [entry.name, variant ?? '', exit, status, seconds, leaks.join(',') || '-', log, ok ? 'PASS' : 'FAIL'].join('\t') + '\n');
  console.log(`${ok ? 'PASS' : 'FAIL'} ${id} exit=${exit} status=${status} ${seconds}s${leaks.length ? ' leaks=' + leaks.join(',') : ''}`);
}

// Background items may share the pool; items that take the foreground / real activation run alone afterwards.
const queue = selected.filter(i => !i.entry.foreground), alone = selected.filter(i => i.entry.foreground);
await Promise.all(Array.from({length: Math.min(jobs, queue.length)}, async () => { for (let it = queue.shift(); it; it = queue.shift()) await runItem(it); }));
for (const it of alone) await runItem(it);
cleanupLink();
// ReportCrash writes asynchronously: give it a moment, then settle the whole run against the start snapshot.
await sleep(5000);
{
  const crash = classifyCrashChanges(crashAtStart, snapshotCrashReports(), runStartMs, crashRelated);
  const done = cleanupCrashReports(crash.allowed);
  const rows = done.map((d: any) => [d.process, d.kind, d.change, d.path, d.action, crashAllowedSeen.get(d.path) ?? '-'].join('\t'));
  await writeFile(join(outRoot, 'CRASH_REPORTS.tsv'), 'process\tkind\tchange\tpath\taction\tfirst_seen_by\n' + rows.map(r => r + '\n').join(''));
  if (done.length) console.log(`\n${done.length} crash report(s) of own test binaries in this run (see CRASH_REPORTS.tsv):\n  ${rows.join('\n  ')}`);
  if (crash.alarms.length) {
    realHomeTouched.push(`end of run (crash-report directories): ${crash.alarms.join('; ')}`);
    aborted = true; fail++;
  }
}
const total = Math.round((Date.now() - started) / 1000);
if (aborted) await appendFile(summaryPath, `!!! ABORTED\tREAL HOME TOUCHED\t-\t-\t-\t-\t${realHomeTouched.join(' | ').replace(/\t/g, ' ')}\tFAIL\n`);
if (realHomeTouched.length) console.log(`\nREAL HOME TOUCHED by ${realHomeTouched.length} item(s):\n  ${realHomeTouched.join('\n  ')}`);
console.log(`\n${pass} passed, ${fail} failed, ${total}s → ${summaryPath}`);
process.exitCode = fail || pass !== selected.length ? 1 : 0;
