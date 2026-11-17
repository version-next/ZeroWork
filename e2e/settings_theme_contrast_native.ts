import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import {nativeThemeData} from './native_theme_data.mjs';
/** Settings card and selection feedback in isolated native windows.
 * node e2e/settings_theme_contrast_native.ts BINARY OUTPUT_DIR
 */
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdir, mkdtemp, open, readFile, writeFile} from 'node:fs/promises';
import {join, resolve} from 'node:path';
import * as h from '../vendor/zenit/e2e/client.ts';
import {decodePng, writeRgbPng, type DecodedPng} from '../vendor/zenit/e2e/png.ts';
// Two-level Settings window: AI › 行为与权限 subpage, Appearance › 主题 subpage; the Settings window is its own
// 960 pt wide native window, so screenshots (of the bound Settings window) scale by 960, not the 1440 main window.
import {settingsNav} from './settings_nav.ts';
const SETTINGS_WIDTH = 960;

const binary = resolve(process.argv[2]), out = resolve(process.argv[3]);
await mkdir(out, {recursive: true});
const cases = [
  ['gruvbox-dark', 0], ['gruvbox-dark', 50], ['gruvbox-dark', 100],
  ['dark', 0], ['light', 0], ['light', 50], ['light', 100], ['sauber', 0],
] as const;
const requestedCase = process.argv[4];
const report: any = {status: 'running', cases: []};
const palettes = nativeThemeData.themes;
const shown = (node: any) => node && node.visible !== false && !node.hidden && node.rect?.w > 0 && node.rect?.h > 0;
const descendants = (node: any): any[] => [node, ...(node.children ?? []).flatMap(descendants)];

type Rgb = [number, number, number];
type Rect = {x: number; y: number; w: number; h: number};

function writeBackground(path: string) {
  const width = 360, height = 240;
  const pixels = new Uint8Array(width * height * 3);
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const inEllipse = ((x - 180) / 120) ** 2 + ((y - 120) / 90) ** 2 <= 1;
      const color = inEllipse ? [102, 138, 143] : x < 180 ? [29, 48, 73] : [210, 180, 125];
      pixels.set(color, (y * width + x) * 3);
    }
  }
  writeRgbPng(path, width, height, pixels);
}

function pixel(image: DecodedPng, x: number, y: number): Rgb {
  const scale = image.width / SETTINGS_WIDTH;
  const offset = (Math.round(y * scale) * image.width + Math.round(x * scale)) * image.channels;
  return [image.pixels[offset], image.pixels[offset + 1], image.pixels[offset + 2]];
}

function sample(image: DecodedPng, rect: Rect, x: number, y: number): Rgb {
  return pixel(image, rect.x + rect.w * x, rect.y + rect.h * y);
}

function distance(a: Rgb, b: Rgb): number {
  return Math.hypot(a[0] - b[0], a[1] - b[1], a[2] - b[2]);
}

function luminance(color: Rgb): number {
  const weights = [.2126, .7152, .0722];
  return color.reduce((sum, channel, index) => {
    const value = channel / 255;
    const linear = value <= .04045 ? value / 12.92 : ((value + .055) / 1.055) ** 2.4;
    return sum + linear * weights[index];
  }, 0);
}

function round2(number: number): number {
  return Math.round(number * 100) / 100;
}

try {
  for (const [theme, transparency] of cases) {
    const name = `${theme}-t${transparency}`;
    if (requestedCase && name !== requestedCase) continue;
    const iso = await mkdtemp('/private/tmp/zw-settings-colors-');
    const data = join(iso, 'data'), rpc = join(iso, 'rpc'), image = join(iso, 'background.png');
    await Promise.all([mkdir(data), mkdir(rpc)]);
    writeBackground(image);
    await writeFile(join(data, 'config.toml'), `[ui]\ntheme="${theme}"\n[ui.materials]\nblur_px=0\n[ui.materials.background]\nenabled=true\npath=${JSON.stringify(image)}\nfit="fill"\ntransparency=${transparency}\n[ai]\ndefault_provider="Fixture"\n[[ai.providers]]\nid="Fixture"\nkind="openai_compat"\nendpoint="http://127.0.0.1:9/v1/chat/completions"\nenabled=true\n[[ai.providers.models]]\nname="model"\ndefault=true\ncontext_window=128000\n`);
    process.env.ZENIT_E2E_FILE_RPC_DIR = rpc;
    const log = await open(join(out, `${name}.log`), 'w');
    const app = spawn(binary, [], {env: {...process.env, ZEROWORK_DATA_DIR: data, ZEROWORK_AUTOCONNECT: '0', ZENIT_E2E_BACKGROUND: '1', ZENIT_E2E_ISOLATE_POINTER: '1'}, stdio: ['ignore', log.fd, log.fd]});
    const ended = new Promise(done => app.once('close', done));
    const visible = (id: string) => h.waitFor(async () => (await h.query(id)).find(shown) ?? null, 15000);
    const click = async (id: string) => { await visible(id); assert((await h.clickTestId(id)).ok, id); };
    const item: any = {theme, transparency}; report.cases.push(item);
    try {
      await h.waitForServerReady();
      assert.equal(Number(JSON.parse(await readFile(join(rpc, 'owner.json'), 'utf8')).pid), app.pid);
      await h.resizeWindow(1440, 900);
      const settings = settingsNav();
      // Pane headers no longer fold, so they have no hover state. The clickable cards of the two-level Settings
      // window are the category overview rows (Pencil sxDUF: transparent row inside the zw-window-rest list,
      // hover recolours the row content, no fill). Card hover = largest change inside the hovered row away from
      // the drawn pointer; card edge = the list surface against the page 5 pt above the list.
      await settings.toCategory('ai');
      const card = await visible('settings.overview.ai.behavior'), listTop = await visible('settings.overview.ai.providers');
      await h.mouseMove(5, 5); await h.sleep(350);
      assert((await h.screenshot(join(out, `${name}-overview-rest.png`))).ok);
      await h.mouseMove(card.rect.x + card.rect.w * .75, card.rect.y + card.rect.h * .5);
      await h.sleep(250); assert((await h.screenshot(join(out, `${name}-card-hover.png`))).ok);
      await settings.toSub('ai', 'behavior');
      if ((await h.query('settings.ai.provider.0.endpoint')).some(shown)) await click('settings.ai.provider.0.header');
      const headerId = 'settings.ai.permissions.header', summaryId = 'settings.ai.permissions.summary';
      await visible(headerId);
      if (!(await h.query(summaryId)).some(shown)) await click(headerId);
      const summary = await visible(summaryId);
      await h.mouseMove(5, 5); await h.sleep(350);
      // The selected nav row deliberately keeps its fill on hover (styles.yss NavRow selected :hover), so
      // selection-hover feedback is measured on an unselected row.
      const nav = await visible('settings.nav.ai'), hoverRow = await visible('settings.nav.keys');
      const geometry = Object.fromEntries(await Promise.all(['settings.viewport', 'settings.footer', 'settings.ai.attachments'].map(async id => [id, await h.query(id)])));
      const attachments = geometry['settings.ai.attachments'].find(shown);
      assert(attachments, 'the attachment card stays visible below the collapsed provider');
      if (process.env.ZW_SETTINGS_CONTRAST_DEBUG) await writeFile(join(out, `${name}-tree.json`), JSON.stringify(await h.tree()));
      assert((await h.screenshot(join(out, `${name}-rest.png`))).ok);
      await h.mouseMove(hoverRow.rect.x + hoverRow.rect.w * .8, hoverRow.rect.y + hoverRow.rect.h * .5);
      await h.sleep(250); assert((await h.screenshot(join(out, `${name}-selection-hover.png`))).ok);
      await click('settings.nav.keys'); await h.mouseMove(5, 5); await h.sleep(200);
      assert((await h.screenshot(join(out, `${name}-unselected.png`))).ok);
      await writeFile(join(out, `${name}.json`), JSON.stringify({card: card.rect, nav: nav.rect, geometry}, null, 2));
      const screenshot = (state: string) => decodePng(join(out, `${name}-${state}.png`));
      const rest = screenshot('rest'), overview = screenshot('overview-rest');
      const hoveredCard = screenshot('card-hover'), hoveredSelection = screenshot('selection-hover');
      const unselected = screenshot('unselected');
      const rect = card.rect;
      const pointerX = rect.x + rect.w * .75, pointerY = rect.y + rect.h * .5;
      let cardHover = 0;
      for (let x = Math.trunc(rect.x); x < Math.trunc(rect.x + rect.w); x++) {
        for (let y = Math.trunc(rect.y); y < Math.trunc(rect.y + rect.h); y++) {
          if (Math.abs(x - pointerX) <= 32 && Math.abs(y - pointerY) <= 32) continue;
          cardHover = Math.max(cardHover, distance(pixel(overview, x, y), pixel(hoveredCard, x, y)));
        }
      }
      const list = listTop.rect;
      const edge = distance(sample(hoveredCard, list, .65, .5), sample(hoveredCard, list, .65, -5 / list.h));
      const selection = distance(sample(rest, hoverRow.rect, .65, .7), sample(hoveredSelection, hoverRow.rect, .65, .7));
      const chosen = distance(sample(rest, nav.rect, .65, .7), sample(unselected, nav.rect, .65, .7));
      item.pixels = {
        card_hover_rgb_distance: round2(cardHover),
        hover_edge_rgb_distance: round2(edge),
        selected_hover_rgb_distance: round2(selection),
        selection_rgb_distance: round2(chosen),
      };
      assert(cardHover >= 5 && edge >= 5 && selection >= 3 && chosen >= 5, JSON.stringify(item.pixels));
      if (name === 'light-t50') {
        const {x, y, w, h: height} = summary.rect;
        const inkHex = palettes[theme]['--fg-1'];
        const ink: Rgb = [1, 3, 5].map(index => parseInt(inkHex.slice(index, index + 2), 16)) as Rgb;
        const scale = rest.width / SETTINGS_WIDTH;
        const left = Math.round(x * scale), right = Math.round((x + Math.min(w, 200)) * scale);
        const top = Math.round(y * scale), bottom = Math.round((y + height) * scale);
        let inkCount = 0;
        for (let row = top; row < bottom; row++) {
          for (let col = left; col < right; col++) {
            const offset = (row * rest.width + col) * rest.channels;
            if (rest.pixels[offset] === ink[0] && rest.pixels[offset + 1] === ink[1] && rest.pixels[offset + 2] === ink[2]) {
              inkCount++;
            }
          }
        }
        const bg = pixel(rest, x + Math.min(w, 190), y + height / 2);
        const dark = Math.min(luminance(ink), luminance(bg));
        const light = Math.max(luminance(ink), luminance(bg));
        const contrast = (light + .05) / (dark + .05);
        item.pixels.summary_contrast = round2(contrast);
        assert(inkCount >= 3 && contrast >= 4.5, JSON.stringify({inkCount, contrast}));
      }
      // Panes no longer fold (two-level Settings): instead of collapse / expand, coming back to the subpage
      // shows the same header summary again.
      await settings.toSub('ai', 'behavior'); await visible(headerId); await visible(summaryId);
      if (theme === 'dark' && transparency === 0) {
        await settings.toSub('appearance', 'theme');
        // Theme tiles are now a preview card (56 pt) above a label/radio row; hover recolours the tile frame,
        // so the samples sit on the right frame edge of the preview card.
        const tile = await settings.reveal('settings.theme.dark');
        await h.mouseMove(5, 5); await h.sleep(200);
        assert((await h.screenshot(join(out, `${name}-theme-selected.png`))).ok);
        await h.mouseMove(tile.rect.x + tile.rect.w * .5, tile.rect.y + tile.rect.h * .5);
        await h.sleep(250); assert((await h.screenshot(join(out, `${name}-theme-selected-hover.png`))).ok);
        const selected = screenshot('theme-selected');
        const tileX = tile.rect.x + tile.rect.w - 1.5, tileY = tile.rect.y + 28;
        const tileChange = distance(pixel(selected, tileX, tileY), pixel(screenshot('theme-selected-hover'), tileX, tileY));
        item.theme_selected_hover_rgb_distance = round2(tileChange);
        assert(tileChange >= 3, JSON.stringify({tileChange}));
        const otherTile = await visible('settings.theme.light');
        await h.mouseMove(otherTile.rect.x + otherTile.rect.w * .5, otherTile.rect.y + otherTile.rect.h * .5);
        await h.sleep(250); assert((await h.screenshot(join(out, `${name}-theme-unselected-hover.png`))).ok);
        const otherHovered = screenshot('theme-unselected-hover');
        const otherX = otherTile.rect.x + otherTile.rect.w - 1.5, otherY = otherTile.rect.y + 28;
        const otherEdge = otherTile.rect.x + otherTile.rect.w + 2;
        const change = distance(pixel(selected, otherX, otherY), pixel(otherHovered, otherX, otherY));
        const boundary = distance(pixel(otherHovered, otherX, otherY), pixel(otherHovered, otherEdge, otherY));
        item.theme_unselected_hover = {change: round2(change), boundary: round2(boundary)};
        assert(change >= 5 && boundary >= 5, JSON.stringify(item.theme_unselected_hover));
      }
      item.status = 'passed'; console.log(`${name} passed`);
    } catch (error) {
      item.status = 'failed'; item.error = String(error);
      await h.screenshot(join(out, `${name}-failure.png`)).catch(() => {});
      throw error;
    } finally {
      if (app.exitCode === null && app.signalCode === null) app.kill('SIGTERM');
      await ended; await log.close();
    }
  }
  assert(report.cases.length > 0, `Unknown case: ${requestedCase}`);
  report.status = 'passed';
} catch (error) {
  report.status = 'failed'; report.error = String(error); console.error(error); process.exitCode = 1;
} finally {
  await writeFile(join(out, 'report.json'), JSON.stringify(report, null, 2));
}
