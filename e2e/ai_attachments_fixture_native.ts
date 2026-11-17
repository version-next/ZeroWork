/** AI 本地附件：用测试注入的系统文件对话框（ZEROWORK_E2E_DIALOG_DIR，仅 test-mode 构建）逐类验证。
 *
 * node e2e/ai_attachments_fixture_native.ts <binary> <out>
 *
 * 不弹真实 NSOpenPanel：脚本在临时目录生成一套附件夹具，把“下一次对话框返回的路径”写进
 * <dialog>/queue，应用的 dialog_port 逐行消费并把每次请求记到 <dialog>/requests.jsonl。
 * 表驱动：每一类文件给出入口（本地文件 / 图片）、期望的结果（文本卡 / 路径引用卡 / 图片卡 / 拒绝提示）
 * 与预览或提示里必须出现的说明文字。大文件（16 GiB 稀疏 ISO、超大图片）由脚本临时生成，不入库。
 *
 * 产品的系统文件对话框一次只返回一个路径（DialogKind.open_file，没有多选）；“多选”一类按连续两次选择、
 * 两张卡片并存来验证。真实对话框的手动用例仍是 e2e/ai_local_picker_native.ts（需人在场，已从批量回归排除）。
 */
import assert from 'node:assert/strict';
import {chmod, mkdir, open, readFile, symlink, writeFile, appendFile} from 'node:fs/promises';
import {join, resolve, basename} from 'node:path';
import * as h from '../vendor/zenit/e2e/client.ts';
import {launchIsolated, shown, textOf} from './settings_nav.ts';
import {aiToggleId} from './ai_entry.ts';

const [binaryArg, outArg] = process.argv.slice(2);
if (!binaryArg || !outArg) throw new Error('usage: ai_attachments_fixture_native.ts <binary> <out>');
const out = resolve(outArg);
await mkdir(out, {recursive: true});
const report: any = {status: 'running', cases: [], limits: [
  '系统对话框由 test-mode 注入器应答，不覆盖 NSOpenPanel 本身的交互（手动用例 ai_local_picker_native.ts）。',
  '产品对话框单选：多选按连续两次选择验证。',
]};

// ---- fixture folder -------------------------------------------------------
const png1x1 = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==', 'base64');
// 9000×1 RGBA PNG: over the image pixel/size limits while the file itself stays tiny.
const pngWide = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAIygAAAABCAYAAACzIwVFAAAAPUlEQVR4nO3DQQ0AAAwDofNvurOxByS0mqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqr64wFXfA3LIKy7pwAAAABJRU5ErkJggg==', 'base64');

async function buildFixtures(root: string) {
  const f = (name: string) => join(root, name);
  await mkdir(root, {recursive: true});
  await writeFile(f('plain.txt'), '附件夹具：普通 UTF-8 文本。\nsecond line\n');
  await writeFile(f('long.txt'), 't'.repeat(64 * 1024 + 1));
  await writeFile(f('small.png'), png1x1);
  await writeFile(f('wide.png'), pngWide);
  // > 10 MiB (10 485 760 B) image: the wide PNG header followed by a sparse tail (truncate, nothing written).
  await writeFile(f('huge.png'), pngWide);
  {const handle = await open(f('huge.png'), 'r+'); await handle.truncate(12 * 1024 * 1024); await handle.close();}
  // 16 GiB sparse ISO: binary and far over the content size limit, costs no disk blocks.
  {const handle = await open(f('disk.iso'), 'w'); await handle.truncate(16 * 1024 * 1024 * 1024); await handle.close();}
  await writeFile(f('中文 文件名 😀.txt'), '文件名带中文、空格与 emoji。\n');
  await mkdir(f('nested/level-1/level-2'), {recursive: true});
  await writeFile(f('nested/level-1/level-2/deep.txt'), 'nested fixture\n');
  await symlink(f('plain.txt'), f('link-to-plain.txt'));
  await writeFile(f('no-permission.txt'), 'unreadable\n');
  await chmod(f('no-permission.txt'), 0o000);
  await writeFile(f('empty.txt'), '');
  await writeFile(f('multi-a.txt'), 'multi A\n');
  await writeFile(f('multi-b.txt'), 'multi B\n');
  return f;
}

type Expect = {card: 'local_text' | 'local_reference' | 'image'} | {toast: string} | {none: true};
type Case = {name: string, entry: 'local_text' | 'image', files: string[], expect: Expect, preview?: string, filename?: string};
const cases: Case[] = [
  {name: 'utf8-text', entry: 'local_text', files: ['plain.txt'], expect: {card: 'local_text'}, preview: '普通 UTF-8 文本'},
  {name: 'text-over-64KiB', entry: 'local_text', files: ['long.txt'], expect: {card: 'local_reference'}, preview: '64 KiB'},
  {name: 'small-png', entry: 'image', files: ['small.png'], expect: {card: 'image'}},
  {name: 'png-over-pixel-limit', entry: 'local_text', files: ['wide.png'], expect: {card: 'local_reference'}, preview: '像素限制'},
  {name: 'png-over-size-limit', entry: 'local_text', files: ['huge.png'], expect: {card: 'local_reference'}, preview: '限制'},
  {name: 'binary-16GiB-sparse-iso', entry: 'local_text', files: ['disk.iso'], expect: {card: 'local_reference'}, preview: '大小限制'},
  {name: 'cjk-space-emoji-name', entry: 'local_text', files: ['中文 文件名 😀.txt'], expect: {card: 'local_text'}, filename: '中文 文件名 😀.txt'},
  {name: 'nested-directory', entry: 'local_text', files: ['nested/level-1/level-2/deep.txt'], expect: {card: 'local_text'}, filename: 'deep.txt'},
  {name: 'symlink', entry: 'local_text', files: ['link-to-plain.txt'], expect: {toast: '不是普通文件'}},
  {name: 'no-read-permission', entry: 'local_text', files: ['no-permission.txt'], expect: {toast: '没有权限'}},
  {name: 'empty-file', entry: 'local_text', files: ['empty.txt'], expect: {card: 'local_text'}},
  {name: 'multi-select-sequential', entry: 'local_text', files: ['multi-a.txt', 'multi-b.txt'], expect: {card: 'local_text'}},
  {name: 'cancel', entry: 'local_text', files: ['cancel'], expect: {none: true}},
];

const dialogDir = join(out, 'dialog');
await mkdir(dialogDir, {recursive: true});
await writeFile(join(dialogDir, 'queue'), '');
const run = await launchIsolated({binary: resolve(binaryArg), out, prefix: 'zw-ai-attach-fixture', theme: 'dark', env: {ZEROWORK_E2E_DIALOG_DIR: dialogDir}});
const fixture = await buildFixtures(join(run.iso, 'attachments'));
report.fixture = join(run.iso, 'attachments');

const visibleAll = async (id: string) => (await h.query(id)).filter(shown);
const node = (id: string, ms = 15000) => h.waitFor(async () => (await visibleAll(id))[0] ?? null, ms);
async function click(id: string) {
  const n = await node(id);
  assert((await h.clickAt(n.rect.x + n.rect.w / 2, n.rect.y + n.rect.h / 2)).ok, id);
  await h.sleep(200);
}
const cardIds = ['ai.attachment.local_text', 'ai.attachment.local_reference', 'ai.image'];
async function cards() {
  const counts: Record<string, number> = {};
  for (const id of cardIds) counts[id] = (await visibleAll(id)).length;
  return counts;
}
async function clearCards() {
  for (let i = 0; i < 12; i++) {
    const remove = (await visibleAll('ai.attachment.remove'))[0] ?? (await visibleAll('ai.image.remove'))[0];
    if (!remove) return;
    await h.clickAt(remove.rect.x + remove.rect.w / 2, remove.rect.y + remove.rect.h / 2);
    await h.sleep(250);
  }
}
async function historyMessages(): Promise<string[]> {
  await click('toolbar.notifications');
  await node('notifications.history', 5000);
  await h.sleep(200);
  // The history panel now has 待处理 / 最近提醒 tabs and closes through its own close button (Escape does not
  // dismiss it; cf. notification_policy_app_native.ts). Ended operation errors live under 最近提醒.
  const list = (await visibleAll('notifications.history.message')).map(n => textOf(n));
  await click('notifications.history.recent');
  await h.sleep(200);
  list.push(...(await visibleAll('notifications.history.message')).map(n => textOf(n)));
  await click('notifications.history.close');
  await h.waitFor(async () => (await visibleAll('notifications.history')).length === 0 || null, 5000);
  return list;
}
let answered = 0;
async function choose(entry: Case['entry'], file: string) {
  await appendFile(join(dialogDir, 'queue'), (file === 'cancel' ? 'cancel' : fixture(file)) + '\n');
  await click('ai.composer.attachment');
  // The menu item shares its test_id with the attachment card it creates; pick the one inside the menu.
  const itemId = entry === 'image' ? 'ai.attachment.image' : 'ai.attachment.local_text';
  const item = await h.waitFor(async () => {
    const find = (n: any): any => n?.test_id === itemId && shown(n) ? n : (n?.children ?? []).map(find).find(Boolean);
    for (const menu of await visibleAll('ai.attachment.menu')) { const hit = find(menu); if (hit) return hit; }
    return null;
  }, 10000);
  assert((await h.clickAt(item.rect.x + item.rect.w / 2, item.rect.y + item.rect.h / 2)).ok, itemId);
  answered++;
  await h.waitFor(async () => {
    const lines = (await readFile(join(dialogDir, 'requests.jsonl'), 'utf8').catch(() => '')).trim().split('\n').filter(Boolean);
    return lines.length >= answered || null;
  }, 10000);
}

try {
  await h.resizeWindow(1440, 900);
  await click('workspace.empty.local');
  await click(await aiToggleId());
  for (const c of cases) {
    const record: any = {name: c.name, files: c.files, expect: c.expect};
    await clearCards();
    const before = await cards();
    const historyBefore = 'toast' in c.expect ? await historyMessages() : [];
    for (const file of c.files) await choose(c.entry, file);
    if ('card' in c.expect) {
      const id = c.expect.card === 'image' ? 'ai.image' : `ai.attachment.${c.expect.card}`;
      const want = (before[id] ?? 0) + c.files.length;
      await h.waitFor(async () => ((await cards())[id] >= want) || null, 30000);
      record.cards = await cards();
      if (c.filename) {
        // ai-redesign-a: native W.AttachmentChip (ai.attachment.open) shows the name, then its size / origin.
        const names = (await visibleAll('ai.attachment.open')).map(n => textOf(n));
        assert(names.some(t => t.includes(c.filename!)), `${c.name}: filename ${c.filename} not in ${JSON.stringify(names)}`);
      }
      if (c.preview) {
        const cardsOfKind = await visibleAll(id);
        const card = cardsOfKind[cardsOfKind.length - 1];
        const open = (await visibleAll('ai.attachment.open')).find(n => n.rect.y >= card.rect.y - 1 && n.rect.y <= card.rect.y + card.rect.h) ?? (await visibleAll('ai.attachment.open'))[0];
        assert((await h.clickAt(open.rect.x + open.rect.w / 2, open.rect.y + open.rect.h / 2)).ok);
        const text = textOf(await node('ai.attachment.preview.text', 10000));
        record.preview = text.slice(0, 200);
        assert(text.includes(c.preview), `${c.name}: preview lacks "${c.preview}": ${text.slice(0, 200)}`);
        await click('ai.attachment.preview.keep');
        await h.waitFor(async () => (await visibleAll('ai.attachment.preview')).length === 0 || null, 5000);
      }
    } else if ('toast' in c.expect) {
      // Rejections are published as an operation-error notification; read them from the history panel
      // (the toast itself auto-dismisses after a few seconds).
      const want = c.expect.toast;
      const messages = await h.waitFor(async () => {
        const list = await historyMessages();
        return list.length > historyBefore.length ? list : null;
      }, 15000);
      // History order is presentation order (newest first); compare per-message counts instead of positions.
      const count = (list: string[]) => list.filter(m => m.includes(want)).length;
      record.message = messages.filter(m => m.includes(want))[0] ?? messages.join(' | ');
      assert(count(messages) > count(historyBefore), `${c.name}: expected a new notification containing "${want}", history now: ${messages.join(' | ')}`);
      record.cards = await cards();
      for (const id of cardIds) assert.equal(record.cards[id], before[id], `${c.name}: rejected file must not add a ${id} card`);
    } else {
      // Cancel: the dialog was answered and nothing was attached.
      await h.sleep(1500);
      record.cards = await cards();
      record.added = cardIds.filter(id => record.cards[id] > before[id]);
      assert.deepEqual(record.added, [], `${c.name}: cancelling must not attach anything`);
    }
    await h.screenshot(join(out, `${String(report.cases.length + 1).padStart(2, '0')}-${c.name}.png`));
    record.status = 'passed';
    report.cases.push(record);
  }
  const requests = (await readFile(join(dialogDir, 'requests.jsonl'), 'utf8')).trim().split('\n').map(l => JSON.parse(l));
  assert.equal(requests.length, answered, 'every attachment click opened exactly one (injected) dialog');
  assert(requests.every((r: any) => r.kind === 'open_file'));
  // 图片对话框标题写出真实上限：单张 10 MiB（10 485 760 B，1024 进制），不是十进制 10 000 000 B 的 “9.5 MiB”。
  const imageTitles = requests.filter((r: any) => r.title.startsWith('选择图片')).map((r: any) => r.title);
  assert(imageTitles.length > 0, 'at least one image dialog was opened');
  for (const t of imageTitles) assert.equal(t, '选择图片（最多 4 张，单张 10 MiB）', `image dialog title states the 10 MiB limit: ${t}`);
  report.image_dialog_titles = imageTitles;
  report.requests = requests;
  report.status = 'passed';
} catch (e) {
  report.status = 'failed';
  report.error = String((e as any)?.stack ?? e);
  process.exitCode = 1;
  await h.screenshot(join(out, 'failure.png')).catch(() => {});
} finally {
  await chmod(fixture('no-permission.txt'), 0o600).catch(() => {});
  await run.stop();
  await writeFile(join(out, 'report.json'), JSON.stringify(report, null, 2));
  console.log(JSON.stringify({status: report.status, cases: report.cases.map((c: any) => c.name + ':' + c.status), error: report.error}));
}
