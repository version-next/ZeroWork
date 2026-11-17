/** Preloaded into every e2e script (`node --import e2e/regression/isolation_guard.mjs …`; run.ts does it).
 *
 * 1. Private HOME: when ZW_E2E_ROOT is not provided by the runner, create one here
 *    (/private/tmp/zw-e2e-home-XXXXXX, 0700, fake HOME / TMPDIR / XDG_*), export it into
 *    process.env so every child inherits it, and delete it when the script exits.
 * 2. mkdtemp under /tmp or /private/tmp is redirected into <root>/tmp, so every per-script
 *    data / RPC directory lives inside the private root as well.
 * 3. Spawning the app (or a preview runner) asserts HOME, CFFIXED_USER_HOME, TMPDIR and
 *    ZEROWORK_DATA_DIR resolve below /private/tmp/zw-e2e-*; missing HOME-like variables are filled
 *    from the private root first. A violation throws before the process starts.
 * 4. Any config.toml the script writes without an [updates] table gets `auto_check=false`.
 */
import fs from 'node:fs';
import fsp from 'node:fs/promises';
import childProcess from 'node:child_process';
import {basename, join} from 'node:path';
import {syncBuiltinESMExports} from 'node:module';
// Refuses any non-test-mode ZeroWork binary before child_process starts it (installs on import).
import './build_mode_guard.mjs';
import {createIsolatedHome, assertIsolatedEnv, isAppCommand, isMainApp, buildProductOf, assertProductAllowed} from './home_guard.mjs';

// ---- 1. private root -------------------------------------------------------
let ownedRoot = null;
if (!process.env.ZW_E2E_ROOT) {
  const isolated = createIsolatedHome();
  Object.assign(process.env, isolated.env);
  ownedRoot = isolated.root;
  process.on('exit', () => { try { fs.rmSync(ownedRoot, {recursive: true, force: true}); } catch {} });
}
const root = process.env.ZW_E2E_ROOT;
const isolationKeys = ['HOME', 'CFFIXED_USER_HOME', 'TMPDIR', 'ZDOTDIR', 'XDG_CONFIG_HOME', 'XDG_DATA_HOME', 'XDG_CACHE_HOME', 'XDG_STATE_HOME', 'XDG_RUNTIME_DIR', 'SSH_AUTH_SOCK', 'HISTFILE', 'ZW_E2E_ROOT', 'ZEROWORK_E2E_DIALOG_DIR', 'ZIG_GLOBAL_CACHE_DIR'];

// ---- 2. mkdtemp redirect ---------------------------------------------------
function redirect(prefix) {
  const p = String(prefix);
  if (p.startsWith(root + '/')) return prefix;
  for (const base of ['/private/tmp/', '/tmp/']) if (p.startsWith(base)) return join(root, 'tmp', p.slice(base.length));
  return prefix;
}
const mkdtemp = fsp.mkdtemp;
fsp.mkdtemp = function guardedMkdtemp(prefix, ...rest) { return mkdtemp.call(this, redirect(prefix), ...rest); };
const mkdtempSync = fs.mkdtempSync;
fs.mkdtempSync = function guardedMkdtempSync(prefix, ...rest) { return mkdtempSync.call(this, redirect(prefix), ...rest); };
const mkdtempCb = fs.mkdtemp;
fs.mkdtemp = function guardedMkdtempCb(prefix, ...rest) { return mkdtempCb.call(this, redirect(prefix), ...rest); };

// ---- 3. spawn guard --------------------------------------------------------
const spawn = childProcess.spawn;
childProcess.spawn = function guardedSpawn(command, args, options) {
  let opts = options;
  if (!Array.isArray(args) && args && typeof args === 'object') { opts = args; args = []; }
  const product = buildProductOf(command);   // by content: copies under any name are still the app
  if (product || isAppCommand(command, opts?.env)) {
    const env = {...(opts?.env ?? process.env)};
    for (const key of isolationKeys) if (env[key] === undefined || key === 'SSH_AUTH_SOCK') env[key] = process.env[key];
    if (product) assertProductAllowed(product, env);
    assertIsolatedEnv(env, {requireDataDir: product === 'zerowork' || isMainApp(command)});
    opts = {...(opts ?? {}), env};
  }
  return spawn.call(this, command, args ?? [], opts);
};

// ---- 4. config.toml: never check for updates -------------------------------
const UPDATES = '[updates]\nauto_check=false\n';
function patchContent(file, data) {
  if (typeof file !== 'string' && !(file instanceof URL)) return data;
  if (basename(String(file instanceof URL ? file.pathname : file)) !== 'config.toml') return data;
  const text = typeof data === 'string' ? data : (data instanceof Uint8Array ? Buffer.from(data).toString('utf8') : null);
  if (text === null || /^\s*\[updates\]\s*$/m.test(text)) return data;
  return text + (text.endsWith('\n') || text.length === 0 ? '' : '\n') + UPDATES;
}
const writeFile = fsp.writeFile;
fsp.writeFile = function guardedWriteFile(file, data, ...rest) { return writeFile.call(this, file, patchContent(file, data), ...rest); };
const writeFileSync = fs.writeFileSync;
fs.writeFileSync = function guardedWriteFileSync(file, data, ...rest) { return writeFileSync.call(this, file, patchContent(file, data), ...rest); };
const writeFileCb = fs.writeFile;
fs.writeFile = function guardedWriteFileCb(file, data, ...rest) { return writeFileCb.call(this, file, patchContent(file, data), ...rest); };
if (fs.promises !== fsp) { fs.promises.writeFile = fsp.writeFile; fs.promises.mkdtemp = fsp.mkdtemp; }
syncBuiltinESMExports();
