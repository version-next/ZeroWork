import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {existsSync, mkdtempSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {test} from 'node:test';
import {fileURLToPath} from 'node:url';

const runner = fileURLToPath(new URL('./run.ts', import.meta.url));

test('execution rejects incomplete runs before creating evidence', () => {
  const dir = mkdtempSync(join(tmpdir(), 'zw-runner-gate-'));
  const out = join(dir, 'evidence');
  try {
    const noPython = {...process.env};
    delete noPython.ZW_TEST_PYTHON;
    for (const [args, expected] of [
      [['--job', '2'], /unknown option --job/],
      [['--jobs', 'NaN'], /--jobs must be a positive integer/],
      [['--jobs', '1.5'], /--jobs must be a positive integer/],
      [['--timeout-scale', 'Infinity'], /--timeout-scale must be a positive finite number/],
      [['--timeout-scale', '10000000'], /invalid timeout for window_render_smoke_native/],
      [['--tag', 'nonexistent-tag'], /no regression items selected/],
    ] as const) {
      const run = spawnSync(process.execPath, [runner, '--only', 'window_render_smoke_native', '--out', out, ...args], {encoding: 'utf8', env: noPython});
      assert.equal(run.status, 1, run.stderr);
      assert.match(run.stderr, expected);
      assert(!existsSync(out));
    }
    const ssh = spawnSync(process.execPath, [runner, '--only', 'ended_states_idle_native', '--out', out], {encoding: 'utf8', env: noPython});
    assert.equal(ssh.status, 1, ssh.stderr);
    assert.match(ssh.stderr, /selected regression items need --python/);
    assert(!existsSync(out));

    const list = spawnSync(process.execPath, [runner, '--tag', 'nonexistent-tag', '--list'], {encoding: 'utf8', env: noPython});
    assert.equal(list.status, 0, list.stderr);
    assert.match(list.stdout, /^0 item\(s\)$/m);
  } finally {
    rmSync(dir, {recursive: true, force: true});
  }
});
