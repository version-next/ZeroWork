/** Every settings category: default pane state, page remount and reopening.
 * Two-level Settings window (`settings_nav.ts`): panes never fold any more
 * (settings_controls.zig / appearance_view.zig "panes never fold"), so the
 * former "default collapsed / manual toggle" contract becomes "every pane on
 * every subpage renders open, also after remount, reopen and in a compact
 * window"; reopen-clears-search, static About card, untouched config and the
 * normal Quit exit are kept as before. */
import assert from 'node:assert/strict';
import {mkdir, readFile, writeFile} from 'node:fs/promises';
import {join, resolve} from 'node:path';
import * as h from '../vendor/zenit/e2e/client.ts';
import {settingsNav, launchIsolated, titleOf, CATEGORIES, DIRECT} from './settings_nav.ts';

const [binaryArg, outputArg] = process.argv.slice(2);
assert(binaryArg && outputArg, 'settings_default_folds_native.ts BINARY OUTPUT');
const out = resolve(outputArg); await mkdir(out, {recursive: true});
const providers = `[[ai.providers]]
id="First fixture"
kind="openai_compat"
endpoint="http://127.0.0.1:9/v1"
enabled=false
[[ai.providers]]
id="Second fixture"
kind="ollama"
endpoint="http://127.0.0.1:9"
enabled=false
`;
const run = await launchIsolated({binary: resolve(binaryArg), out, prefix: 'zw-default-folds', theme: 'dark', config: providers});
await writeFile(join(run.data, 'hosts.toml'), '');
const initial = await readFile(run.config, 'utf8');
const nav = settingsNav();
const report: any = {status: 'running', pages: [], checks: []};
// A pane is open when its body extends below its header row.
async function expectOpen(panes: string[], where: string) {
  for (const pane of panes) {
    const n = await nav.reveal(pane), header = (await h.query(pane === 'settings.appearance.materials' ? 'settings.materials.header' : pane + '.header')).find((x: any) => x.rect?.h > 0);
    assert(n.rect.h > (header?.rect.h ?? 0) + 1, `${pane} renders open (${where})`);
  }
}
try {
  assert.equal(Number(JSON.parse(await readFile(join(run.rpc, 'owner.json'), 'utf8')).pid), run.app.pid);
  await h.resizeWindow(1440, 1000); await nav.open();
  for (const [cat, , subs] of CATEGORIES) {
    for (const [sub, , panes] of subs) {
      await nav.toSub(cat, sub); await expectOpen(panes, 'default');
      // Remount: leave for another category and come back via Back.
      await nav.toCategory(cat === 'ssh' ? 'keys' : 'ssh'); await nav.back(); await nav.waitTitle(titleOf(cat, sub)); // Back returns to the subpage itself
      await nav.toSub(cat, sub); await expectOpen(panes, 'remount');
      await h.screenshot(join(out, `${cat}-${sub}.png`));
    }
    const last = subs.at(-1)!;
    await nav.close(); await nav.open(); await nav.toSub(cat, last[0]); await expectOpen(last[2], 'reopened');
    report.pages.push({page: cat, subpages: subs.map(([s]) => s), open: true, remountPreserved: true, reopenedOpen: true});
  }
  for (const [cat, , panes] of DIRECT) if (panes.length) {await nav.toCategory(cat); await expectOpen(panes, 'direct');}
  await nav.toCategory('updates');
  await expectOpen(['settings.updates.preferences'], 'About static card');
  await h.screenshot(join(out, 'updates-static.png'));
  report.checks.push('About/update information and its static preferences remain visible');
  await nav.toCategory('ssh'); await nav.click('settings.search'); await h.type_('keepalive_sec');
  await nav.node('settings.search.results');
  await nav.node('settings.field.keepalive_sec');
  await nav.close(); await nav.open();
  assert.equal((await h.inputState('settings.search')).buffer, '');
  assert.equal((await h.query('settings.search.results')).length, 0);
  await nav.toSub('ssh', 'connection'); await expectOpen(['settings.ssh.connection'], 'after search');
  report.checks.push('Reopening clears a previous search; searching still reveals matching settings');
  await h.resizeWindow(860, 600);
  await nav.toSub('appearance', 'theme'); await expectOpen(CATEGORIES[0][2][0][2], 'compact');
  await h.screenshot(join(out, 'compact-open.png'));
  assert.equal(await readFile(run.config, 'utf8'), initial, 'Navigation does not save configuration');
  report.checks.push('Compact window panes remain open; configuration file is unchanged');
  await nav.close();
  await h.request('POST', '/zerowork/windows', {action: 'quit'});
  await h.waitFor(async () => run.app.exitCode !== null || run.app.signalCode !== null || null, 10000).catch(() => {});
  assert.equal(run.app.exitCode, 0, 'Normal application exit');
  report.status = 'passed';
} catch (error) {
  report.status = 'failed'; report.error = String(error);
  await h.screenshot(join(out, 'failure.png')).catch(() => {});
  throw error;
} finally {
  await run.stop();
  await writeFile(join(out, 'report.json'), JSON.stringify(report, null, 2));
  console.log(JSON.stringify(report));
}
