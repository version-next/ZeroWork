/** The private clipboard of an e2e run.
 *
 *  The application's clipboard is zenit's (`vendor/zenit/native/macos/clipboard_pasteboard.h`): with
 *  `ZENIT_E2E_PASTEBOARD=<name>` in its environment it copies to and pastes from a private named pasteboard instead of
 *  the system general pasteboard. The regression runner (`e2e/regression/run.ts`) gives every item its own name, and
 *  the app a script starts inherits it, so a copy assertion reads what the app really wrote without overwriting the
 *  person's clipboard, and items running in parallel cannot read each other's copies. The runner also fails an item
 *  during which the general pasteboard changed.
 *
 *  Scripts therefore never call `pbpaste` / `pbcopy` (they only reach the general pasteboard): they read and write the
 *  run's pasteboard here. Outside the runner a script that copies must be given a name itself
 *  (`ZENIT_E2E_PASTEBOARD=zw-e2e.manual.$$ node e2e/<script>.ts …`); `pasteboardName()` refuses to fall back to the
 *  general pasteboard.
 */
import {execFile, execFileSync} from 'node:child_process';
import {promisify} from 'node:util';

const run = promisify(execFile);
// JXA through the system osascript: AppKit's NSPasteboard, no third-party code. `argv[0]` is the pasteboard name.
// The result is JSON (null when there is no text), so the text comes back byte-exact whatever it contains.
const READ = 'ObjC.import("AppKit");function run(argv){const p=$.NSPasteboard.pasteboardWithName(argv[0]);const s=p.stringForType($.NSPasteboardTypeString);return JSON.stringify(s.isNil()?null:s.js)}';
const WRITE = 'ObjC.import("AppKit");function run(argv){const p=$.NSPasteboard.pasteboardWithName(argv[0]);p.clearContents;if(!p.setStringForType($(argv[1]),$.NSPasteboardTypeString))throw new Error("pasteboard write refused");return String(p.changeCount)}';
const COUNT = 'ObjC.import("AppKit");function run(){return String($.NSPasteboard.generalPasteboard.changeCount)}';
const RELEASE = 'ObjC.import("AppKit");function run(argv){$.NSPasteboard.pasteboardWithName(argv[0]).releaseGlobally;return ""}';

/** The run's private pasteboard name; throws when none is set (never the general pasteboard). */
export function pasteboardName(): string {
  const name = process.env.ZENIT_E2E_PASTEBOARD;
  if (!name) throw new Error('ZENIT_E2E_PASTEBOARD is not set: run through e2e/regression/run.ts, or set a private name (the general pasteboard is the person\'s clipboard)');
  if (/^(Apple|com\.apple\.)/.test(name)) throw new Error('refusing a system pasteboard name: ' + name);
  return name;
}

/** The plain text on the run's pasteboard, or null when it holds no text. Exact: no trailing newline is added or removed. */
export async function readPasteboardText(name = pasteboardName()): Promise<string | null> {
  const {stdout} = await run('/usr/bin/osascript', ['-l', 'JavaScript', '-e', READ, name], {encoding: 'utf8'});
  return JSON.parse(stdout);   // osascript appends one newline after the JSON; JSON.parse ignores it
}

/** Put `text` on the run's pasteboard (what a paste in the app will insert). */
export async function writePasteboardText(text: string, name = pasteboardName()): Promise<void> {
  await run('/usr/bin/osascript', ['-l', 'JavaScript', '-e', WRITE, name, text], {encoding: 'utf8'});
}

/** The general (system) pasteboard's change count: read only, its contents are never touched. */
export function generalPasteboardChangeCount(): number {
  const value = Number(execFileSync('/usr/bin/osascript', ['-l', 'JavaScript', '-e', COUNT], {encoding: 'utf8'}).trim());
  if (!Number.isInteger(value)) throw new Error('general pasteboard change count unreadable');
  return value;
}

/** Drop a private pasteboard from the pasteboard server (the app releases its own at exit; this covers a crash). */
export function releasePasteboard(name: string): void {
  if (/^(Apple|com\.apple\.)/.test(name)) throw new Error('refusing a system pasteboard name: ' + name);
  execFileSync('/usr/bin/osascript', ['-l', 'JavaScript', '-e', RELEASE, name], {encoding: 'utf8'});
}
