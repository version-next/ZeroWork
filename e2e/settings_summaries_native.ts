/** Real production settings pages: pane summaries, overview live summaries, units, editing and scroll.
 * Two-level Settings window (`settings_nav.ts`): panes no longer fold; the live draft summary that
 * used to appear on a collapsed pane is now the category overview row summary. */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdtemp, mkdir, writeFile, readFile, open, rm, realpath} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join, resolve} from 'node:path';
import {createHash} from 'node:crypto';
import {waitForServerReady, waitFor, query, clickAt, key, type_, resizeWindow, screenshot, sleep, scrollAt, request} from '../vendor/zenit/e2e/client.ts';
import {settingsNav, CATEGORIES, DIRECT} from './settings_nav.ts';

const args = process.argv.slice(2);
assert(args.length === 2 || args.length === 3, 'settings_summaries_native.ts BINARY OUTPUT [storage]');
const mode = args[2] ?? 'full'; assert(['full', 'storage'].includes(mode));
const binary = resolve(args[0]), output = resolve(args[1]);
await mkdir(output, {recursive: true});
const report: any = {binary, sha256: createHash('sha256').update(await readFile(binary)).digest('hex'), runs: []};
const pages = ['appearance', 'keys', 'ssh', 'transfer', 'ai', 'plugins', 'notifications', 'data'];
const flat = (n: any): any[] => [n, ...(n.children ?? []).flatMap(flat)];
const shown = (n: any) => n?.visible !== false && n?.rect?.w > 0 && n?.rect?.h > 0 && (n.effective_opacity ?? 1) > 0;
const text = (n: any) => typeof n.text === 'string' ? n.text : (n.text?.content ?? '');
let failure: unknown;

for (const theme of (mode === 'storage' ? ['dark'] : ['dark', 'light', 'sauber'])) {
  const iso = await realpath(await mkdtemp(join(tmpdir(), 'zerowork-settings-summary-')));
  const rpc = join(iso, 'rpc'), data = join(iso, 'data');
  await mkdir(rpc, {mode: 0o700}); await mkdir(data, {mode: 0o700});
  await writeFile(join(data, 'config.toml'), `[meta]\nconfig_revision=1\n[updates]\nauto_check=false\n[ui]\ntheme="${theme}"\nfont_family="Menlo"\nfont_size=14\n`, {mode: 0o600});
  process.env.ZENIT_E2E_FILE_RPC_DIR = rpc;
  const log = await open(join(output, `${theme}.app.log`), 'w');
  const app = spawn(binary, [], {env: {...process.env, ZENIT_E2E_FILE_RPC_DIR: rpc, ZENIT_E2E_BACKGROUND: '1', ZENIT_E2E_ISOLATE_POINTER: '1', ZEROWORK_DATA_DIR: data, ZEROWORK_AUTOCONNECT: '0', OPENAI_API_KEY: '', ANTHROPIC_API_KEY: ''}, stdio: ['ignore', log.fd, log.fd]});
  const ended = new Promise<void>(done => app.once('close', () => done()));
  const rec: any = {theme, pages: [], captures: []}; report.runs.push(rec);
  const visible = async (id: string): Promise<any> => waitFor(async () => (await query(id)).find(shown) ?? null, 12000);
  async function click(id: string) {const n = await visible(id); assert((await clickAt(n.rect.x + n.rect.w / 2, n.rect.y + n.rect.h / 2)).ok); await sleep(180);}
  async function capture(name: string) {await sleep(240); assert((await screenshot(join(output, name + '.png'))).ok); rec.captures.push(name); console.log(name);}
  async function content() {return flat(await visible('settings.content'));}
  async function scrollTop() {const v = await visible('settings.viewport'); await scrollAt(v.rect.x + v.rect.w / 2, v.rect.y + 12, 0, 3000); await sleep(150);}
  async function scrollTo(id: string) {
    for (let i = 0; i < 12; i++) {
      const v = await visible('settings.viewport'), n = (await query(id)).find(shown);
      if (n && n.rect.y >= v.rect.y && n.rect.y + n.rect.h <= v.rect.y + v.rect.h) return n;
      await scrollAt(v.rect.x + v.rect.w / 2, v.rect.y + v.rect.h / 2, 0, n && n.rect.y < v.rect.y ? 200 : -200); await sleep(120);
    }
    throw new Error('Could not scroll into view: ' + id);
  }
  try {
    await waitForServerReady();
    const owner = JSON.parse(await readFile(join(rpc, 'owner.json'), 'utf8')); assert.equal(Number(owner.pid), app.pid);
    await resizeWindow(1440, 900); await click('toolbar.settings');
    const nav = settingsNav();
    if (mode === 'storage') {
      await nav.toSub('ai', 'providers'); await click('settings.ai.provider.0.header'); // F-set-ai: the provider list opens the provider's detail page
      const nodes = await content();
      assert(nodes.some(n => text(n) === 'API Key 存储于 macOS 钥匙串'));
      assert(!nodes.some(n => text(n).includes('明文保存')));
      await capture('dark-provider-keychain');
      rec.provider_storage_contract = 'macOS Keychain';
      await nav.toSub('appearance', 'theme'); await scrollTop();
      const currentNames = flat(await visible('settings.theme.current')).map(text).filter(Boolean);
      assert(currentNames.length > 0);
      assert.equal(text(await visible('settings.appearance.themes.summary')), currentNames[0]);
      assert(!(await query('settings.appearance.aids.summary')).some(shown));
      await capture('dark-appearance-current-theme');
      rec.selected_theme_summary = currentNames[0];
      await nav.close();
      const windows = await request('POST', '/zerowork/windows', {action: 'snapshot'});
      assert(windows.windows.length >= 1); await request('POST', '/zerowork/windows', {action: 'quit'}); // closing the last window now retains it (window_hide_native.ts); Quit is the normal exit
      await Promise.race([ended, sleep(10000)]); assert.equal(app.exitCode, 0);
      rec.normal_close = true; rec.status = 'passed_pending_visual_review';
      continue;
    }
    // Every subpage (or direct page): each visible pane summary sits inside its header row,
    // to the right of the pane title without overlapping it (header meta in the v3 revamp).
    for (const page of pages) {
      const subs = CATEGORIES.find(([c]) => c === page)?.[2].map(([s]) => s) ?? [null];
      for (const sub of subs) {
        if (sub === null) await nav.toCategory(page); else await nav.toSub(page, sub);
        await scrollTop();
        const nodes = await content();
        const summaries = nodes.filter(n => n.test_id?.endsWith('.summary') && !n.test_id.startsWith('settings.overview.'));
        const checks: any[] = [];
        for (const s of summaries) {
          const headerId = s.test_id === 'settings.appearance.materials.summary' ? 'settings.materials.header' : s.test_id.slice(0, -'.summary'.length) + '.header';
          const h = nodes.find(n => n.test_id === headerId); if (!h || !shown(h)) continue;
          if (shown(s) && text(s)) {
            const labels = flat(h).filter(n => text(n) && n.test_id !== s.test_id && shown(n));
            assert(labels.length > 0); const title = labels[0];
            assert(s.rect.y >= h.rect.y - .5 && s.rect.y + s.rect.h <= h.rect.y + h.rect.h + .5, 'Summary sits inside its header row ' + s.test_id);
            assert(s.rect.x >= title.rect.x + title.rect.w, 'Summary is right of the title, not overlapping ' + s.test_id);
            assert(s.rect.x + s.rect.w <= h.rect.x + h.rect.w + .5, 'Summary is not clipped by the header ' + s.test_id);
          }
          checks.push({id: s.test_id, text: text(s), shown: shown(s), rect: s.rect});
        }
        rec.pages.push({page, sub, summaries: checks});
      }
      if (theme === 'dark' && ['ssh', 'appearance', 'ai', 'plugins'].includes(page)) await capture(`${theme}-${page}`);
    }
    await nav.toSub('data', 'history'); await scrollTop();
    await capture(`${theme}-data-history`);
    const input = await scrollTo('settings.field.ring_mb'); await clickAt(input.rect.x + 20, input.rect.y + input.rect.h / 2);
    await key('a', {cmd: true}); assert((await type_('128')).ok); await sleep(180);
    // H-save: the draft belongs to this subpage (leaving it asks first), so save here; the category overview row then
    // shows the saved value.
    await click('settings.save'); await sleep(250);
    await waitFor(async () => /ring_mb\s*=\s*128/.test(await readFile(join(data, 'config.toml'), 'utf8')) || null, 10000);
    rec.numeric_value_saved_without_unit = true;
    await nav.back(); await visible('settings.overview');
    const collapsed = await visible('settings.overview.data.history.summary');
    assert.equal(text(collapsed), '缓冲 128 MiB · 每 30 秒快照 · 保留 14 天'); // ring_mb 按 MiB 计，显示走 shared/base/format（units-iec）
    rec.edited_summary = {text: text(collapsed), rect: collapsed.rect};
    await capture(`${theme}-data-overview-saved`);
    // Keep the Save Bar fixed while the settings body scrolls on a small window.
    // H-save: the Save Bar only shows with unsaved changes, so make one first and revert it afterwards.
    await resizeWindow(860, 480); await nav.toSub('data', 'history'); await sleep(200);
    {const n = await scrollTo('settings.field.ring_mb'); await clickAt(n.rect.x + 20, n.rect.y + n.rect.h / 2); await key('a', {cmd: true}); assert((await type_('256')).ok); await sleep(200);}
    const footer = (await visible('settings.footer')).rect, viewport = (await visible('settings.viewport')).rect;
    await scrollAt(viewport.x + viewport.w / 2, viewport.y + viewport.h / 2, 0, -1500); await sleep(250);
    assert.deepEqual((await visible('settings.footer')).rect, footer);
    await capture(`${theme}-data-small-scrolled`);
    await click('settings.revert'); await waitFor(async () => (await query('settings.footer')).some(shown) ? null : true, 5000);
    // Search reaches a field on a subpage without drilling down.
    await click('settings.search'); await key('a', {cmd: true}); await type_('checkpoint_sec'); await sleep(200);
    await scrollTop(); assert((await query('settings.field.checkpoint_sec')).some(shown));
    rec.search_reaches_field = true;
    await nav.close(); // the preferences window closes first; closing the main window then quits normally
    const windows = await request('POST', '/zerowork/windows', {action: 'snapshot'});
    assert(windows.windows.length >= 1); await request('POST', '/zerowork/windows', {action: 'quit'}); // closing the last window now retains it (window_hide_native.ts); Quit is the normal exit
    await Promise.race([ended, sleep(10000)]); assert.equal(app.exitCode, 0); rec.normal_close = true;
    rec.status = 'passed_pending_visual_review';
  } catch (e) {
    failure = e; rec.status = 'failed'; rec.error = String(e);
    try {await capture(theme + '-failure'); await writeFile(join(output, theme + '-failure-tree.json'), JSON.stringify(await query('settings.content'), null, 2));} catch {}
  } finally {
    if (app.exitCode === null && app.signalCode === null) {app.kill('SIGTERM'); await Promise.race([ended, sleep(2000)]); if (app.exitCode === null && app.signalCode === null) app.kill('SIGKILL');}
    rec.exit = {code: app.exitCode, signal: app.signalCode};
    await log.close(); await rm(iso, {recursive: true, force: true});
    await writeFile(join(output, 'report.json'), JSON.stringify(report, null, 2));
  }
  if (failure) break;
}
report.status = failure ? 'failed' : 'passed_pending_visual_review';
await writeFile(join(output, 'report.json'), JSON.stringify(report, null, 2));
if (failure) throw failure;
