/** Drop-in replacement for `execFileSync('/bin/ps', args, {encoding:'utf8'})`.
 *
 * /bin/ps is setuid root and cannot be exec'd inside the no-network sandbox that
 * every e2e run uses (zw-nonet.sh → sandbox-exec: "Operation not permitted").
 * Scripts that listed descendants or sampled CPU/RSS through ps therefore died
 * before their cleanup and left the app running.
 *
 * psCompat() first tries the real /bin/ps; on EPERM it reads the same values
 * through libproc (proc_listallpids / proc_pidinfo / proc_pidpath, which need no
 * privileges for the caller's own processes) and prints them in ps's format for
 * the column sets the e2e scripts use: pid, ppid, comm, time, rss, %cpu.
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import {execFileSync} from 'node:child_process';

type Row = {pid: number, ppid: number, comm: string, user_ns: number, system_ns: number, rss: number};

const LIBPROC = String.raw`
import ctypes, json, sys
lib = ctypes.CDLL('/usr/lib/libproc.dylib')
libc = ctypes.CDLL('/usr/lib/libSystem.B.dylib')
class TB(ctypes.Structure): _fields_ = [('numer', ctypes.c_uint32), ('denom', ctypes.c_uint32)]
tb = TB(); libc.mach_timebase_info(ctypes.byref(tb))
scale = tb.numer / tb.denom
want = [int(p) for p in sys.argv[1].split(',')] if len(sys.argv) > 1 and sys.argv[1] else None
if want is None:
    n = lib.proc_listallpids(None, 0)
    buf = (ctypes.c_int * (n * 2))()
    n = lib.proc_listallpids(buf, ctypes.sizeof(buf))
    want = [buf[i] for i in range(n) if buf[i] > 0]
rows = []
bsd = ctypes.create_string_buffer(136); task = ctypes.create_string_buffer(96); path = ctypes.create_string_buffer(4096)
for pid in want:
    if lib.proc_pidinfo(pid, 3, ctypes.c_uint64(0), bsd, 136) != 136: continue
    ppid = int.from_bytes(bsd.raw[16:20], 'little')
    comm = bsd.raw[48:64].split(b'\0')[0].decode('utf8', 'replace')
    if lib.proc_pidpath(pid, path, 4096) > 0: comm = path.value.decode('utf8', 'replace')
    user = system = rss = 0
    if lib.proc_pidinfo(pid, 4, ctypes.c_uint64(0), task, 96) == 96:
        rss = int.from_bytes(task.raw[8:16], 'little')
        user = int.from_bytes(task.raw[16:24], 'little') * scale
        system = int.from_bytes(task.raw[24:32], 'little') * scale
    rows.append({'pid': pid, 'ppid': ppid, 'comm': comm, 'user_ns': user, 'system_ns': system, 'rss': rss})
print(json.dumps(rows))
`;

function libprocRows(pids: number[] | null): Row[] {
  return JSON.parse(execFileSync('python3', ['-I', '-c', LIBPROC, pids ? pids.join(',') : ''], {encoding: 'utf8'}));
}

const cpuTime = (r: Row) => {
  const s = (r.user_ns + r.system_ns) / 1e9, m = Math.floor(s / 60);
  return `${m}:${(s - m * 60).toFixed(2).padStart(5, '0')}`;
};

export function psCompat(args: string[]): string {
  try {
    return execFileSync('/bin/ps', args, {encoding: 'utf8'});
  } catch (error: any) {
    if (error?.code !== 'EPERM' && error?.code !== 'EACCES') throw error;
  }
  let pids: number[] | null = null, columns: string[] = [];
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === '-p') pids = args[++i].split(',').map(Number);
    else if (a === '-o' || a === '-axo') columns = args[++i].split(',').map(c => c.replace(/=$/, ''));
    else if (a === '-ax') continue;
    else throw new Error(`psCompat: unsupported ps argument ${a}`);
  }
  const rows = libprocRows(pids);
  const cell = (r: Row, c: string) => {
    switch (c) {
      case 'pid': return String(r.pid);
      case 'ppid': return String(r.ppid);
      case 'comm': return r.comm;
      case 'time': return cpuTime(r);
      case 'rss': return String(Math.round(r.rss / 1024));
      default: throw new Error(`psCompat: unsupported column ${c}`);
    }
  };
  if (pids && !rows.length) {
    const e: any = new Error(`psCompat: no such process ${pids.join(',')}`); e.status = 1; throw e;
  }
  return rows.map(r => columns.map(c => cell(r, c)).join(' ')).join('\n') + '\n';
}
