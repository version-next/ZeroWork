/** Metal/Harness acceptance of the isolated settings preview runner.
 * `--layout=window` mounts the full settings window (navigation, page intro, content, Save Bar;
 * the production aux-window path, 960 × 780) on the 协议插件 page. The `--layout=content` case
 * (the legacy settings_content_view page, 636 × 628) was removed with the legacy shell (P3 3f). The old hard-coded plans
 * (FTP / FTPS, VNC, RDP, KVM) and the fake preview states (`--preview-kind`) were deleted
 * (PLUGIN_ARCH_PLAN 6.2.1 Q1): none of their texts may render. The `.yix` window lists
 * "计划中" from the roadmap table only (网页连接 · 0.5 版本待实施). Rendering must leave settings clean.
 * This controlled runner is not an additional product entry or plugin loader.
 * zig build settings-preview -Dtest-mode=true [--prefix DIR]
 * node e2e/settings_previews.ts [--binary BIN] [--out DIR] [--theme sauber|dark|light]
 */
import './regression/build_mode_guard.mjs';  // refuses non-test-mode ZeroWork binaries before child_process starts them
import { spawn } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdir, mkdtemp, open, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { query, screenshot, sleep, stats, tree, waitForServerReady } from "../vendor/zenit/e2e/client.ts";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const args = process.argv.slice(2);
const options: Record<string, string> = {};
for (let index = 0; index < args.length; index += 2) {
  if (!["--out", "--theme", "--binary"].includes(args[index]) || !args[index + 1]) throw new Error(`Invalid option ${args[index]}`);
  options[args[index]] = args[index + 1];
}
const theme = options["--theme"] ?? "sauber";
if (!["sauber", "dark", "light"].includes(theme)) throw new Error("Invalid theme");
const output = resolve(options["--out"] ?? join(root, `dist/ui-acceptance/settings-previews-${Date.now()}`));
const binary = resolve(options["--binary"] ?? join(root, "zig-out/bin/settings-preview-runner"));
// Texts of the deleted planning projections and the retired hard-coded plans; none may render.
const planningTexts = ["校验示例", "兼容性示例", "等待会话结束 · 规划", "获取流程 · 规划", "加载中 · 规划", "未发布", "待定义", "未授权", "FTP / FTPS", "VNC", "RDP", "后续扩展"];
const planningIds = ["settings.plugin.detail", "settings.plugin.back", "settings.plugin.lifecycle.readonly", "settings.plugin.selected"];
await mkdir(output, { recursive: true });
const report = {
  scope: "isolated full production settings window on the plugin page; retired planning projections must not render; the window's 计划中 group lists only roadmap entries; settings stay clean; no product entry, installation, permission, or dynamic loading claim",
  entry_point: "src/features/settings/preview/settings_preview_runner.zig",
  binary,
  binary_sha256: createHash("sha256").update(await readFile(binary)).digest("hex"),
  theme,
  sizes: { window: { width: 960, height: 780 } },
  cases: [] as Record<string, unknown>[],
  status: "running",
};
function texts(node: Awaited<ReturnType<typeof tree>>): string[] {
  return [...(node.text ? [node.text] : []), ...(node.children ?? []).flatMap(texts)];
}
async function visible(id: string) {
  const node = (await query(id)).find(node => node.visible !== false && node.rect.w > 0 && node.rect.h > 0);
  if (!node) throw new Error(`Missing visible node: ${id}`);
  return node;
}
function expectText(node: Awaited<ReturnType<typeof tree>>, expected: string[]) {
  const actual = texts(node);
  for (const text of expected) if (!actual.includes(text)) throw new Error(`Missing text: ${text}`);
}
function expectNoText(node: Awaited<ReturnType<typeof tree>>, forbidden: string[]) {
  const actual = texts(node);
  for (const text of forbidden) if (actual.some(value => value.includes(text))) throw new Error(`Planning text leaked into production settings: ${text}`);
}
try {
  for (const layout of ["window"] as const) {
    const name = `${layout}-plugins`;
    const isolated = await mkdtemp(join(tmpdir(), "zerowork-settings-preview-"));
    process.env.ZENIT_E2E_FILE_RPC_DIR = isolated;
    const log = await open(join(output, `${name}.log`), "w");
    const child = spawn(binary, [`--layout=${layout}`, "--page=plugins", `--theme=${theme}`], {
      cwd: isolated,
      env: { ...process.env, HOME: isolated, CFFIXED_USER_HOME: isolated, ZENIT_E2E_ISOLATE_POINTER: "1", ZENIT_E2E_BACKGROUND: "1" },
      stdio: ["ignore", log.fd, log.fd],
    });
    const ended = new Promise<void>(done => child.once("close", () => done()));
    const result: Record<string, unknown> = { layout, status: "running" };
    report.cases.push(result);
    try {
      await waitForServerReady();
      const before = await tree();
      const component = await visible("settings.window");
      const size = { w: 960, h: 780 };
      if (component.rect.w !== size.w || component.rect.h !== size.h) throw new Error(`Incorrect content size: ${JSON.stringify(component.rect)}`);
      // Production content view: page intro, real plugin page, floating Save Bar.
      if ((await visible("settings.page.title")).text !== "协议插件") throw new Error("Preview is not on the plugin page");
      result.plugins_rect = (await visible("settings.plugins")).rect;
      result.intro_rect = (await visible("settings.page.intro")).rect;
      // H-save hides the Save Bar on a clean page (no standing “所有更改已保存”).
      // F-set-plugins：协议插件是两级导航，列表页只导航、没有可编辑字段，所以没有“恢复默认…”。
      for (const id of ["settings.history.back", "settings.history.forward", "settings.help"]) await visible(id);
      if ((await query("settings.reset")).some((node: any) => node.visible !== false && node.rect?.w > 0 && node.rect?.h > 0)) throw new Error("Plugin list page shows 恢复默认… without editable fields");
      const clean = async () => !(await query("settings.footer")).some((node: any) => node.visible !== false && node.rect?.w > 0 && node.rect?.h > 0);
      expectText(before, ["协议插件"]);
      // Retired planning projections never render; the window's 计划中 lists only the roadmap entry.
      expectNoText(before, planningTexts);
      expectText(await visible("settings.plugins.planned"), ["计划中", "网页连接", "0.5 版本待实施"]);
      result.planned_rect = (await visible("settings.plugins.planned.web.row")).rect;
      for (const id of planningIds) if ((await query(id)).length !== 0) throw new Error(`Planning node leaked into production settings: ${id}`);
      if (!(await clean())) throw new Error("Preview dirtied settings");
      await sleep(200);
      if (!(await screenshot(join(output, `${name}.png`))).ok) throw new Error("Screenshot failed");
      const after = await tree();
      await writeFile(join(output, `${name}.tree.json`), JSON.stringify(after, null, 2));
      expectNoText(after, planningTexts);
      if (!(await clean())) throw new Error("Preview dirtied settings after render");
      result.stats = await stats();
      result.status = "passed";
    } catch (error) {
      result.status = "failed";
      result.error = String(error);
      // Keep the failing frame for diagnosis; never mask the original error.
      await screenshot(join(output, `${name}-failed.png`)).catch(() => undefined);
      await tree().then(node => writeFile(join(output, `${name}-failed.tree.json`), JSON.stringify(node, null, 2))).catch(() => undefined);
      throw error;
    } finally {
      child.kill("SIGTERM");
      await ended;
      await log.close();
      await rm(isolated, { recursive: true, force: true });
    }
  }
  report.status = "passed";
} catch (error) {
  report.status = "failed";
  throw error;
} finally {
  await writeFile(join(output, "report.json"), JSON.stringify(report, null, 2));
}
console.log(`The full settings window renders the production plugin page: ${output}`);
