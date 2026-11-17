/** Item for tree_cleanup_selftest.ts: behaves like the app's login shell at the end of an item. It leaves a
 * descendant in its own session (outside the item's process group, like a forkpty shell) that ignores
 * SIGTERM / SIGHUP and writes into the private HOME two seconds after the item has ended (zsh writing
 * `.zsh_history` back). The descendant records whether that write still found its HOME.
 * Usage: node late_writer_item.mjs <out>
 */
import {spawn} from 'node:child_process';
import {mkdir, writeFile} from 'node:fs/promises';
import {join} from 'node:path';

const out = process.argv[2];
await mkdir(out, {recursive: true});
spawn('/bin/sh', ['-c', 'trap "" TERM HUP; sleep 2; if printf x >> "$HOME/.zsh_history"; then echo wrote; else echo failed; fi > "$1"', 'late-writer', join(out, 'late-writer.done')],
  {detached: true, stdio: 'ignore'}).unref();
await new Promise(r => setTimeout(r, 1000));   // the app runs a while after its shell started
await writeFile(join(out, 'report.json'), JSON.stringify({status: 'passed'}));
