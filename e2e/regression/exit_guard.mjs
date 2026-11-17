/** Preloaded into every e2e script started by run.ts (`node --import`).
 *
 * Many runners spawn the app (or a copy of it) and only stop it on the happy
 * path. This guard records every child started through child_process.spawn and
 * sends it SIGTERM when the script ends for any reason: normal exit, a thrown
 * assertion (uncaught exception / rejection → exit 1) or the runner's timeout
 * (SIGTERM / SIGINT to the script). It never escalates to SIGKILL.
 *
 * Only children of this node process are touched; nothing is matched by name.
 */
import childProcess from 'node:child_process';
import {syncBuiltinESMExports} from 'node:module';

const children = new Set();
const originalSpawn = childProcess.spawn;
childProcess.spawn = function guardedSpawn(...args) {
  const child = originalSpawn.apply(this, args);
  if (child && child.pid) {
    children.add(child);
    child.once('exit', () => children.delete(child));
  }
  return child;
};
syncBuiltinESMExports();

function terminateChildren() {
  for (const child of children) {
    if (child.exitCode === null && child.signalCode === null) {
      try { process.kill(child.pid, 'SIGTERM'); } catch {}
    }
  }
}

process.on('exit', terminateChildren);
for (const signal of ['SIGTERM', 'SIGINT', 'SIGHUP']) {
  process.once(signal, () => {
    process.stderr.write(`[exit_guard] ${signal}: stopping ${children.size} child process(es)\n`);
    terminateChildren();
    process.exit(signal === 'SIGINT' ? 130 : 143);
  });
}
