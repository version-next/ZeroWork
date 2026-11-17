# ZeroWork UI 架构 Revamp 技术方案

状态：方案稿（只调研、未改代码）。基线提交 `936166e1`（分支 `feat/zenit-app-extensions-ui-revamp`，调研期间 HEAD 由 `e1372d88` 前进到此，工作区干净）；文中行号均以该提交为准。
配套文档：[PENCIL_MAP.md](PENCIL_MAP.md)（设计稿 → 模块映射与实现差异）；[YIX_SPIKE.md](YIX_SPIKE.md)（P0 技术验证结论）；[baselines/](baselines/)（测试计数与截图基线）。
修订记录：2026-11-11 并入 P0 验证结论（V-1/2/3/4/5/9/10/11、zenit 缺口 G1–G7、check-arch 落地情况与已定决策），涉及 §2.2、§2.4、§3.1–§3.5、§4.3–§4.5、§5.1、§5.3、§5.4、§6.2、§7.2、§8.1、§8.2、§9.2。

约定：
- “（推测）”表示没有直接证据、由旁证推断的结论；“待验证”表示必须实际编译或运行才能确认，本阶段按安全约束没有执行任何构建、测试、脚本或二进制。
- 统计数字来自只读命令（`wc`、`grep`、`find`、`git log`），计数口径写在表注里。

## 目录

1. [结论摘要](#1-结论摘要)
2. [现状审计](#2-现状审计)
3. [Yix / Yss 能力评估](#3-yix--yss-能力评估)
4. [目标架构](#4-目标架构)
5. [目标目录树与规范](#5-目标目录树与规范)
6. [迁移计划](#6-迁移计划)
7. [子 agent 工作分解](#7-子-agent-工作分解)
8. [风险、开放问题与需要拍板的决策](#8-风险开放问题与需要拍板的决策)
9. [附录](#9-附录)

---

## 1. 结论摘要

1. **问题的根不在“没用 Yix”，而在没有层**。`src/ui` 的 322 个平铺文件里有 102 个根本不 import zenit（纯逻辑），而 `host`、`vt`、`ai`、`config` 又反过来 import `ui/` 下的文件；`main.zig` 17,666 行里装着 6 个巨型宿主。先分层、再换写法，否则 `.yix` 只会变成新的混杂载体。
2. **目标分层**：`platform ← core（现有 proto/vt/transfer/local/host/ai/config/update）← features/<f>/model ← features/<f>/view（.yix/.yss + 自定义 Zig 组件）← features/<f>/host ← app`，另有 `shared/ui`（设计系统）与 `shared/testing`。依赖只能指向左侧，用一个 `zig build check-arch` 步骤做 import 方向和标识符级检查，带基线、只降不升。
3. **View 与逻辑的契约**：数据下行用 view-model 上的 `ui.Signal` 加“选择器函数”，动作上行用 `Intent`（`vm.dispatch`），副作用由 feature 的 `host/` 通过 `Ports` 执行、结果以 Intent 回流。设置窗口已有的 `Controller`（无 UI 依赖）和 `beginSave → completeSave/failSave` 请求—完成模式正好是这个契约的雏形。
4. **Yix 的定位与两条硬性规则**（2026-11-12 用户定，覆盖本方案早先“不设 100% Yix 目标”的说法）：
   - **视图层全部用 `.yix` + `.yss`**，Zig 只负责 model、view-model、host 与逻辑。视图里任何留在 Zig 的部分（自定义组件、样式覆盖、命令式挂载）都是例外，逐条登记在 [YIX_EXCEPTIONS.md](YIX_EXCEPTIONS.md)；属于 Yix / Yss 能力缺失的补 zenit 上游后收回，本质命令式或原生渲染的（终端表面、KVM 画面、虚拟列表容器等）由用户判定。
   - **基础组件一律只用 zenit 原生的，没有例外**：Button、Input、Select、Switch、Radio、Checkbox、Tooltip、Modal、Menu、ScrollArea、Notification / Toast、Glass 系列、Divider、Tabs、Popover、Card 等。不许手搓，不许用 inline / `paint*` / `tune*` 覆盖它们的外观和行为，不许用 Yss 模仿原生组件；外观以 zenit 默认 token 为准，ZeroWork 主题不再改写这些组件的角色 token。zenit 缺某个基础组件或能力就补上游，不在下游自造。现存的手搓与覆盖清点在 [NATIVE_AUDIT.md](NATIVE_AUDIT.md)，按清单逐项替换；`check-arch` 的 `no-inline-style`、`no-widget-internals` 两条规则防止新增（4.3）。
5. **目录**：`src/` 根目录从 273 个文件降到约 10 个（入口、库门面、测试聚合根、预览/验收多路复用根）；`src/ui` 解散进 `features/*` 与 `shared/ui`；`config/settings_*` 迁到 `features/settings`。core 各目录本轮不动位置（e2e 与脚本里有硬编码路径）。
6. **顺序**：P0 护栏与技术验证 → P1 目录搬迁（脚本化、纯搬迁）→ P2 `main.zig` 机械拆分 → P3 设置窗口 Yix 样板 → P4 设计系统收敛 → P5 其余 feature 分波迁移 → P6 收尾。P1、P2 全局串行并需要冻结窗口；P3 之后按 feature 目录并行。
7. **稳定性抓手**：test_id 清单基线 + 检查步骤；迁移前先把组件测试改成按 test_id 的语义断言（目前有 119 处 `children.items[i]` 下标断言）；迁移前后同状态截图逐像素对比；pencil `design_diff` 分数不退化。
8. **需要 zenit 上游配合**的最小集合：Yix/Yss 参考文档进包、虚拟列表行的 render prop、宿主元素 `onDrop`、`<portal>` 标签。每项一个 commit、附测试，落在 `feat/app-extension-points`。

---

## 2. 现状审计

### 2.1 规模

| 位置 | .zig 文件数 | 行数 | 说明 |
|---|---:|---:|---|
| `src/`（合计） | 1,061 | 371,994 | 不含 vendor |
| `src/` 根目录 | 273 | 107,349 | 其中 `main.zig` 17,666 行 |
| ├ `*_tests.zig` | 218 | 77,164 | 测试文件平铺在根目录 |
| ├ `*_preview_runner.zig` | 16 | — | 组件预览入口 |
| ├ 其他 `*_runner.zig` | 30 | — | SSH/转发/BMC 等验收 runner |
| ├ `*fixture.zig` | 4 | — | 原生验收夹具 |
| └ 其他 | 5 | — | `main.zig` `root.zig` `ssh_session_smoke.zig` `ui_theme_test_support.zig` `application_environment_contract.zig` |
| `src/ui` | 325 | 110,546 | 322 个平铺文件 + 3 个 `_styles.yss.zig` |
| `src/ai` | 125 | 39,299 | |
| `src/plugins` | 61 | 25,734 | `bmc_ikvm` 已自带 model / view_model / views / styles / controller 分文件 |
| `src/host` | 58 | 20,657 | |
| `src/config` | 64 | 20,415 | 其中设置界面相关约 11,948 行 |
| `src/vt` | 60 | 16,778 | |
| `src/proto` | 46 | 11,690 | |
| `src/transfer` | 8 | 9,769 | |
| `src/local` | 10 | 6,216 | |
| `src/platform` | 22 | 2,688 | 另有 `.m` / `.c` |
| `src/update` | 8 | 846 | |
| `e2e/` | 430 个条目 | — | 328 个 `.ts`、91 个 `.py`，全部平铺 |

Yix/Yss 现状：0 个 `.yix`；3 个 `.yss`（`src/ui/{settings,shell,files}/styles.yss`，共 143 行生成物）。`ui.view.` 声明式 API 全仓库只出现 3 次（3 个文件），`ui.on.` 出现 0 次。

命令式 UI API 的使用量（全 `src`，排除 `_tests.zig`；`main.zig` 单列）：

| API | 全仓库 | 其中 main.zig |
|---|---:|---:|
| `appendChild(` | 3,221 | 210 |
| `setStyleInline(` | 1,593 | 68 |
| `setDisplay(` | 1,064 | 69 |
| `ui.box(` / `ui.boxStyled(` | 955 / 331 | 41 / 24 |
| `cx.requestRedraw` | 618 | 139 |
| `cx.on(` | 575 | 55 |
| `.mount(scope, cx)` | 398 | 33 |
| `meta.ownership.meta.test_id` | 1,567 | — |

按功能前缀看 `src/ui` 的体量（文件名前缀粗分，供排期参考）：

| 前缀 | ui 文件 | ui 行数 | 根目录测试文件 | e2e 脚本 |
|---|---:|---:|---:|---:|
| `ai_*` | 88 | 26,358 | 42 | 97 |
| `terminal_*` | 18 | 17,399 | 8 | 21 |
| `workspace*` | 4 | 9,886 | 0 | 2 |
| `file_*` | 14 | 5,492 | 14 | 2（另 `sftp_*` 21） |
| `transfer_*` | 8 | 4,426 | 6 | 9 |
| `connection_*` | 9 | 3,786 | 5 | 6 |
| `session_*` | 12 | 3,170 | 5 | 6 |
| `socks_*` | 11 | 2,879 | 5 | 2 |
| `history_*` | 9 | 2,729 | 0 | 1 |
| `status_*` | 11 | 2,676 | 3 | 2 |
| `wizard*` | 4 | 2,466 | 3 | 5 |
| 设置界面（在 `src/config`） | 约 37 | 11,948 | 9 | 17 |

### 2.2 目录结构的问题

1. **`src/` 根目录是测试与 runner 的堆放处**。原因是 Zig 的模块根约束：一个模块只能 `@import` 根源文件所在目录之内的文件，而 `build.zig` 里所有测试与 runner 的根源文件都直接指向 `src/*.zig`（字面写出的就有 22 个，另有一批经数组循环注册，`build.zig:618`；例如 `src/transfer_panel_tests.zig` 是 `test-ui` 的根，`build.zig:701`；`src/settings_preview_runner.zig`，`build.zig:315`）。`tools/mockups/runner.zig` 不能相对 import `src/`，只能由 build 层把 `src/ui/design_tokens.zig` 装成命名模块传进去（`build.zig:280-285`），是同一约束的旁证。V-1 已验证该约束在 Zig 0.17 下成立（越出模块根报 `import of file outside module path`，见 YIX_SPIKE.md §V-1）。
   - 推论：只有“聚合根”必须留在 `src/`，被聚合的测试文件可以放在任意子目录。`src/transfer_panel_tests.zig` 现在就是这样用的：170 行里有 111 条 `_ = @import("…_tests.zig")`。
2. **`src/ui` 不是 view 层**。322 个文件里只有 223 个 import zenit 的 `ui` 模块；另外 102 个（26,446 行）是纯逻辑，例如 `ui/ai_tools.zig`（2,182 行）、`ui/session_runtime.zig`（1,092 行）、`ui/ai_execution_backend.zig`（860 行）、`ui/wizard_probe.zig`（727 行）、`ui/workspace_model.zig`（625 行）。其中 12 个文件直接使用线程、POSIX 或目录 I/O（如 `ui/terminal_file_job.zig`、`ui/history_archive.zig`、`ui/session_export_jobs.zig`）。
3. **`src/config` 既是配置模型又是设置界面**。64 个文件里有 26 个 import zenit `ui`；`config/settings_parts/appearance_view.zig` 一个文件 1,532 行。
4. **`src/root.zig` 把一切都导出成一个库**。415 行的 `pub const x = @import(...)`，同时导出 `ui/*` 与 `config/settings_*`（`root.zig:84-122`），“core 模块”实际包含 UI。
5. **后缀没有约束力**。`src/ui` 中带 `_view` 后缀 66 个、`_styles` 70 个、`_host` 14 个、`_controller` 7 个、`_model` 6 个，其余 114 个没有角色后缀；`_host` 既出现在 `src/host` 也出现在 `src/ui`（`ui/application_host.zig` 4,456 行）。

### 2.3 View 与逻辑耦合的热点

**A. `main.zig` 的巨型宿主**（节点指针、业务状态、I/O、原生窗口状态混在同一个结构体）

| 结构 | 行范围 | 规模 | 证据 |
|---|---|---|---|
| `AiHost` | `main.zig:445-7711` | 7,267 行、284 个方法 | 字段同时有 `cx`、`*ui.Node`、`sessions_view`、`controller: AiController`、`manager: AiManager`、`provider`、`native_client`、`endpoint`、`model`（`main.zig:470-520`） |
| `SettingsHost` | `main.zig:9196-11430` | 2,235 行、99 个方法 | 30 多个 `*ui.Node` 字段与 `controller`、`std.Io.Dir`、`resource_worker`、三份 `BackgroundTexture`、`native_closing` 并列（`main.zig:9196-9305`） |
| `AppNavHost` | `main.zig:11484-13726` | 2,243 行、78 个方法 | 既发布主题（`main.zig:12587-12628`）又注册本地终端文件拖放（`main.zig:12639-12640`） |
| `TransferHost` | `main.zig:15500-17274` | 1,775 行、66 个方法 | |
| `MenuHost` | `main.zig:8212-9195` | 约 980 行 | |
| `mountUI` | `main.zig:14159-14904` | 746 行 | 同一个函数里加载配置（`:14177`）、设置 Dock 图标（`:14186`）、选主题（`:14189-14190`），再手工逐个创建 AI 面板头部按钮（`:14219-14254`） |

`main.zig` 共有 1,060 处 `@import`、312 个不同目标：`ui/` 138、`ai/` 75、`config/` 38、`host/` 26。

**B. 下层反向依赖 `ui/`**（一级相对 import 计数）

| 方向 | 处数 | 例子 |
|---|---:|---|
| `host → ui` | 18 | `host/file_workspace_controller.zig:10` 直接 `pub const View = @import("../ui/file_workspace_view.zig")`；`host/runtime_service.zig:129` 的 `mountTerminal` 参数是 `*TerminalViewNode` 与 `*ui.Node` |
| `config → ui` | 24 | `config/transfer_defaults.zig:5` import `ui/transfer_panel.zig` |
| `vt → ui` | 7 | `vt/snapshot.zig:50`、`vt/search_snapshot.zig:73` 依赖 `ui/terminal_record_geometry.zig`；`vt/ssh_shell_execution.zig:19` 依赖 `ui/command_palette.zig` |
| `ai → ui` | 5 | `ai/turn_manager.zig:1242` 依赖 `ui/ai_tools.zig`；`ai/session_prompt.zig:31` 依赖 `ui/command_catalog.zig` |
| `update → ui` | 2 | `update/app_host.zig:8-9` |
| `local → ui` | 1 | `local/recording.zig:1410` |

其中 `ui/session_lifecycle.zig` 的 `Snapshot` 被 `host`（8 处）、`vt/reconnect.zig:100`、`config/hosts.zig:1121` 共用，说明它本来就不属于 UI。

**C. View 内部的“读节点树当数据源”**

- 子页面过滤靠遍历子节点、按 test_id 隐藏：`config/settings_content_view.zig:355-363`（`showSubpage`）。
- 搜索靠递归读节点文本：`settings_content_view.zig:426-430`（`matchesText`）。
- 旧页面靠匹配像素高度 622 / 568 来“归一化”：`settings_content_view.zig:434-444`。
- 通知权限状态靠嗅探中文帮助文案得出：`config/settings_parts/settings_notify.zig:59-67`（`permissionStatus`）。
- `ui/workspace.zig` 的 `Workspace` 结构体从第 372 行延续到约第 6360 行，状态、节点和交互都在里面。

**D. 双主题通道**

- 应用主题是全局可变状态 `app_theme.current()`（`ui/app_theme.zig:588`），非测试代码里直读 1,432 处，226 个文件 import `app_theme.zig`。
- zenit token 由 `widgetTokensFrom`（`app_theme.zig:665`）从同一调色板映射出来，其中包含 `zw_island_*`（`:673-676`），所以 `.yss` 里的 token 引用会跟随用户主题。
- 但现有 Yss 样板并没有直接用 `.yss` 的结果：`config/settings_shell.zig:60-66` 先 `@TypeOf(Y.shell).box(t)` 取出结构体，再用 `theme.current().surface_1.withAlpha(255)` 覆盖背景。也就是说，“不透明窗面”这类角色还没有对应的 token。

### 2.4 测试与 e2e 的组织

- **Zig 测试**：`*_tests.zig` 里共约 2,096 个 `test` 块；另有就地测试 `src/ui` 599 个、`src/config` 120 个。聚合根有 6 个：`src/root.zig`（`zig build test`，`build.zig:387`）、`src/transfer_panel_tests.zig`（`test-ui`，`build.zig:701`）、`src/appearance_tests.zig`、`src/bmc_tests.zig`、`src/update_tests.zig`、`src/plugin_fixture_tests.zig`，再加 `src/appearance_font_tests.zig`。`test` 用 `-Dtest-filter`、`test-ui` 用 `-Dui-test-filter` 按测试名过滤，e2e README 里大量引用这些过滤串，所以测试名必须保持不变。
- **组件测试对结构敏感**：测试文件里有 119 处 `children.items[...]` 下标访问（例：`config/settings_shell.zig:246-258`）；52 个文件里共有 56 份各自实现的按 test_id 查找节点的辅助函数（如 `settings_content_tests.zig:146`、`sidebar_view_tests.zig:183`）。
- **预览 runner**：16 个 `*_preview_runner.zig` + 4 个 `*fixture.zig`，每个都在 `build.zig` 里单独建 exe（`build.zig:315-379`、`:618-632`、`:906`）。
- **e2e**：`e2e/*.ts` 通过 `vendor/zenit/e2e/client.ts` 的 Harness，用 `h.query(test_id)` 取节点，再断言 `rect`、`text`（含子节点文本拼接）、`disabled`、`visible`、`effective_opacity`（见 `e2e/settings_revamp_native.ts:37-44`）。脚本按前缀平铺：`ai_*` 97、`ssh_*` 38、`terminal_*` 21、`sftp_*` 21、`settings_*` 17、`theme_*` 16。
- **test_id**：源码里 `test_id = "…"` 形式的字面量有 1,231 个不同取值，全部是点分命名空间（`settings.nav.appearance`、`ai.execution.result.summary`）；一级前缀 40 个，最大的是 `ai`（381）、`settings`（148）、`wizard`（76）、`bmc`（73）、`transfer`（70）。另有运行期拼接的 id（设置字段用 `settings.field.<key>`、`settings.row.<key>`、`settings.error.<key>`，`settings_controls.zig:315-499`）。
- **构建门禁**：`gen-yix` / `check-yix` 只扫描 `src/ui`（`build.zig:125`、`:130`），只有主程序依赖 `check-yix`（`build.zig:144`），测试步骤不依赖。
- **有硬编码源码路径的外部引用**：24 个 e2e 文件、13 个脚本、22 份文档引用了 `src/<目录>/…`（例：`e2e/tab_icon_states_native.ts:14` 读取 `src/ui/host_os_assets.zig`；`e2e/sftp_conflict_native.ts:214` 读取 `src/host/file_route_factory.zig`）；`build.zig` 里有 46 个非 UI 的 `src/…` 路径。目录搬迁必须同步这些引用。

---

## 3. Yix / Yss 能力评估

资料来源：`vendor/zenit/src/yix/compiler.zig`、`style_compiler.zig`、`vendor/zenit/tests/yix/*.yix|*.yss`、`examples/{yix_counter,hello_button,virtual_list_perf,text_input,template_probe}`、zenit 内置组件的 `.yix`（`src/ui/components/{modal,menu,…}`），以及 zenit 上游同一分支的 `docs/YIX_REFERENCE.md`、`docs/YIX_COMPONENTS.md`。后两份文档**没有进 vendor 快照**（zenit 的 `build.zig.zon` `.paths` 逐个列文件，未包含它们），是从 `~/work/fe/zenit` 的 `feat/app-extension-points` 分支只读取得的。

### 3.1 今天能表达什么

| 能力 | 结论 | 证据 |
|---|---|---|
| 宿主元素 | `box` `row` `col` `grid` `text` `icon` `image` `canvas` `spacer` | `compiler.zig:351` |
| 组件与参数 | Zig 风格签名；默认值、必填、`Text` 参数、`Model(T)` 受控值、`Handler(T)` 回调；`pub fn X` 生成 `XProps` | `tests/yix/doc_chip.yix`、`stories.yix`（`Toggle`、`Required`、`Picker`） |
| 指针类参数 | 可以把 `?*State` 这类指针当参数传入 | `tests/yix/equivalence_sequence.yix:17` |
| 局部状态与生命周期 | `signal` `computed` `effect` `ref` `onMount` `onUnmount` `onViewAttach` `onViewDetach` `parts` | `compiler.zig:1112`、`:1412` |
| 条件渲染 | `if / else if / else`、可选值与错误联合捕获、`switch`（含载荷捕获），分支惰性构造 | `stories.yix`（`PickedName`、`ShapeLabel`、`Parsed`、`LazyBranch`） |
| 列表渲染 | `for (xs) \|x, i\|`、`else` 空态、`key=`、`for (0..n)`、嵌套；同 key 原地更新，保住焦点与局部状态 | `stories.yix`（`EditableRows`、`Groups`）；YIX_REFERENCE §2.7 |
| 插槽 | `children: View`、具名插槽、可选具名插槽 `?View`；最多 4 个具名插槽 | `stories.yix`（`Frame`、`Field`）；YIX_REFERENCE §2.9 |
| 事件 | `onClick` `onFocus` `onBlur` `onHover` `onLeave`；类型化 `onKeyDown/Up`、`onPointerDown/Move/Up`、`onScroll`；语句可为赋值、调用、`if`、块、`try` | `compiler.zig:305-333`、`:2675`；`stories.yix`（`KeyPad`、`TryEvent`） |
| 读取外部信号 | 模板里调用的函数内部 `.get()` 会被跟踪；返回 `*ui.Signal` 的调用原样作为源。组件参数形式（`vm: *ViewModel` + 选择器）已验证；经参数取信号字段必须写 `vm.field.get()`，不能写裸的 `vm.field` | `tests/yix/review_reactive.yix`（`ExternalOnly`、`ReturnedSource`）；`view.zig:2045-2062`；YIX_SPIKE.md §V-2、§V-4 |
| 可访问性 | `a11y={.{ .role, .label, .selected, … }}`，字段可为源；`focusable`、`focusRing`、`tag` | `compiler.zig:306`、`:318-319`；`doc_chip.yix` |
| test_id | `testId="…"` 或表达式；组件根也可加；内部部件用 `parts` | `compiler.zig:305`、`:1599`；`examples/template_probe/remount.yix` |
| 窗口区域 | `windowRegion`（拖动、缩放、标题栏按钮语义）。仅在 `WindowConfig.chrome = .custom / .frameless` 下被原生层读取；旧的 `titlebar = .custom_inset` + `titlebar_height` 路径完全忽略它，两者二选一 | `compiler.zig:312`；YIX_SPIKE.md §V-11 |
| 样式接入 | `style={S.x}`、元组合并、`S.Recipe.of(.{…})`（维度可为源）、参数化样式 `S.name.of(.{ .p = 源 })`、`ui.view.styleBy` 逃生口 | `hello_button/view.yix`、`tests/yix/params.yss`；YIX_REFERENCE §2.10 |
| Yss | `style` / `recipe`（`base`、`variant`、`flag`、`when`、`slots`）/ `mixin`；条件 `:hover :active :focus :focus-visible :selected :expanded :invalid :disabled`；`transition`、`shadow`、`mix()`、`{zig}` 内嵌 | `style_compiler.zig:1-40`、`:138` |
| 主题 token | 按字段类别解析 token 名，拼错是编译错误；应用可叠加自己的 token 层（ZeroWork 已接 `zerowork.tokens.json`，`build.zig:37-38`） | `examples/yix_counter/styles.yss`；`src/ui/theme/zerowork.tokens.json` |
| 嵌入手写 Zig 组件 | `fn mountX(props, scope, cx) !*ui.Node` + `fn X(props) ui.view.ComponentOf(mountX)`，在模板里当标签用 | `examples/text_input/*.yix`；YIX_REFERENCE §2.3 末尾 |
| 从 Zig 挂载 Yix 组件 | `ui.view.render(scope, cx, Comp(.{ … }))` 返回 `*ui.Node` | `examples/yix_counter/main.zig:6` |

最后两行决定了迁移可以渐进：旧的命令式视图能包成标签嵌进新 `.yix`，新的 `.yix` 组件也能被旧代码 `appendChild`。

### 3.2 今天不能表达什么

| 限制 | 证据 | 对 ZeroWork 的影响 |
|---|---|---|
| 没有 render prop | `examples/virtual_list_perf/view.yix:23`；YIX_REFERENCE §2.13 | `VirtualList` / `Table` / `Grid` 的行函数必须经 Zig 包一层 |
| 单根，无片段，无局部组件 | YIX_REFERENCE §2.13 | 随形态变结构的组件写成“根固定 + 条件子项” |
| 组件体内不能用 `cx` / `scope` | YIX_REFERENCE §2.3 | 需要命令式建状态的部分写成手写 Zig 组件 |
| 事件里不能写字段（`vm.x = 1`），只能写信号赋值与函数调用；实参里也不能写结构体字面量（`.{ .x = 1 }`、`T{ .x = 1 }`），yix gen 当作字段写入拒绝 | YIX_REFERENCE §2.8 “未实现：字段写入”；YIX_SPIKE.md §V-3（缺口 G2） | 动作统一走函数：`onClick={save(vm)}`；带载荷的 Intent 用构造函数或 `@unionInit` |
| 经组件参数取信号字段不展开：`{vm.field}` 插值能编译但静默输出 Signal 结构体转储，`visible`、`if`、`switch`、`for`、组件属性处直接编译失败 | YIX_SPIKE.md §V-4（缺口 G1） | 模板里一律写 `vm.field.get()` 或选择器函数；`check-arch` 待加拦截（4.3） |
| `{switch}` 不支持多值分支 `.a, .b => …`（报 `unexpected token`） | YIX_SPIKE.md §V-2（缺口 G3） | 拆成多个分支，或用 `else =>` |
| `signal`、`computed`、`ref`、`parts` 是保留字，不能用作顶层 `const` / `var` / `fn` 的名字 | `compiler.zig:1105-1112`；YIX_SPIKE.md §V-1 | 子目录可以叫 `parts/`，但 import 出来的常量要另起名 |
| 标签内部的 `//` 注释会变成文本节点 | YIX_SPIKE.md §V-2（缺口 G4） | 注释只写在模板之外 |
| 宿主属性没有拖放 | 属性表（`compiler.zig:311-333`）无 `onDrop`；节点事件里有 `on_drop`（`vendor/zenit/src/ui/core/types.zig:3475`） | 文件拖入、跨容器拖拽留在 Zig |
| 没有 `<portal>` 标签 | `host_tags` 不含；测试里靠 Zig 包装 `ui.view.portal`（`equivalence_sequence.yix:12-15`） | 自定义浮层由 Zig 组件承载，或直接用 `W.Modal` / `W.Popover` 等现成组件 |
| 没有上下文注入语法 | `reactive/context.zig` 有 `provide/consume`，但 Yix 无对应内建 | view-model 以参数逐层传递 |
| `testId` 为源时只在挂载时取值 | `compiler.zig:305` 注释 | 随数据变化的 id 必须和 `key` 绑定 |
| 无 `:first-child`、`:group-hover`、富文本 `<span>` | YIX_REFERENCE §6 | 分隔线、首末圆角用数据（下标）驱动的 variant |
| 借用字符串的生命周期由调用方保证；`Signal.set` 按内容判等 | YIX_REFERENCE §2.13 | view-model 必须拥有传给视图的字符串，列表换数据时整体换切片 |

还没有答案、需要实测的点见 [9.2 待验证清单](#92-待验证清单)。

### 3.3 ZeroWork 的界面模式该放哪

| 界面模式 | 现状位置 | 归属 | 理由 |
|---|---|---|---|
| 设置各面板、向导表单、认证表单 | `config/settings_parts/*`、`ui/wizard.zig`、`ui/auth_challenge_view.zig` | `.yix` | 结构稳定、数据驱动，全是现成控件 |
| 卡片类（连接进度、审批、执行结果、同名冲突、空状态） | `ui/connection_progress_view.zig`、`ui/ai_host_approval_view.zig`、`ui/transfer_*` | `.yix` | 有限状态 → recipe variant |
| 外壳 chrome（view bar、侧栏骨架、Pane Header、工具组、Save Bar） | `main.zig:13895-14050`、`ui/sidebar_view.zig`、`ui/shell_styles.zig` | `.yix` | 设计稿里的可复用组件（`JrTg7`、`QGtx5`、`EHLGD`） |
| 虚拟列表（文件行、传输任务、AI 历史、模型选择） | `ui/file_workspace_view.zig:686`、`ui/transfer_manager_view.zig:605`、`ui/ai_history_view.zig:21` | 容器在 Zig，**行内容在 `.yix`** | 没有 render prop；行组件写成 Yix，由 Zig 的行函数返回 |
| 终端表面 | `ui/terminal_view.zig`（8,469 行；行池上限 300、选区覆盖块 300，`:29`、`:48`）、`ui/terminal_surface.zig` | Zig 自定义组件 | 节点池、逐帧更新、IME 预编辑（两文件共 85 处 preedit/composing 相关代码） |
| 终端上的锚定浮层（命令面板、补全、搜索条） | `ui/terminal_view.zig`、`ui/completion_*` | 定位在 Zig，内容可为 `.yix` | 位置依赖字符网格几何 |
| 模态、弹出、菜单、提示 | 29 个文件用 `Modal(`、33 个用 `Popover(`，多处手工 `root.appendChild(modal.overlay)`（如 `ui/ai_sessions_view.zig:61`） | `.yix` 里直接用 `W.Modal` / `W.Popover` / `W.Menu` / `W.Tooltip` 标签 | 组件自带 portal 与焦点陷阱 |
| 拖拽（页签重排、分屏拖放、分隔条、AI 面板拉宽） | `ui/workspace.zig:2214`、`:3082-3176`、`ui/ai_pane_layout.zig` | 控制器在 Zig；拖影、落点提示在 `.yix` | 需要指针捕获、阈值、取消；简单分隔条可用类型化指针事件 |
| 系统文件拖入 | `main.zig:12639-12640` | Zig | 无 `onDrop` 属性 |
| IME 文本输入（表单） | `W.Input` / `W.Textarea` | `.yix` | 组件内建 IME |
| 原生 aux 窗口（设置、新建连接） | `ui/aux_window.zig` + `main.zig` 里的 Runtime 适配 | 窗口生命周期在 `host/`，窗口内容是 `.yix` 根组件 | `Client.mount` 回调里 `ui.view.render` 即可。标题栏若改用 `windowRegion={.drag}`，`aux_window.Spec` 与 `main.zig:92` 的窗口配置须从 `titlebar = .custom_inset` + `titlebar_height` 改为 `.chrome = .{ .custom = … }`（二者二选一，V-11），放在 P3 |
| KVM 画面、背景材质层 | `plugins/bmc_ikvm/views.zig:178`、`ui/background_layers.zig` | Zig | GPU 纹理与逐帧 |

### 3.4 取舍原则

1. **默认写 `.yix`，满足下面任一条才留在 Zig**：需要节点池或逐帧写节点；需要 `cx` / `scope` 做命令式初始化；需要指针捕获式拖拽或系统拖放；需要 GPU 纹理或自绘且与数据帧同步；位置由非布局数据决定（字符网格、锚点跟随）。
2. **留在 Zig 的部分一律做成“自定义组件”**：对外只有一个 props 结构和一个 `ComponentOf(mountX)` 包装，放在 `view/components/<name>/mod.zig`，在 `.yix` 里当标签用。例：`<TerminalSurface session={…} />`、`<FileTable vm={vm} />`。组件内部可以继续用 `setStyleInline`，feature 的其他视图代码不可以。旧命令式视图包成组件时，适配函数必须把 `ComponentOf` 传入的子 scope 交给旧代码（如 `Binding.scope`），否则分支卸载时 cleanup 不执行、钩子与 effect 一直挂着（V-5 反例，示例见 YIX_SPIKE.md §V-5）。
3. **虚拟列表拆两半**：容器、滚动与行池用 Zig；行写成 Yix 组件。照 `examples/virtual_list_perf/view.yix` 的写法：
   ```zig
   fn Row(index: usize) View { return <row style={S.Row.of(.{ .odd = odd })}>…</row>; }
   fn row(i: usize) @TypeOf(Row(.{ .index = 0 })) { return Row(.{ .index = i }); }
   fn ItemList(props: struct { count: usize }) @TypeOf(W.VirtualList(.{}).rows({}, row)) { … }
   ```
4. **动态样式的优先级**：token → recipe 的 `variant` / `flag`（由 view-model 的枚举或布尔驱动）→ 参数化样式 `style name($p: T)`（由 view-model 的数值驱动，如 AI 面板宽度）→ `ui.view.styleBy`（只有 Zig 才算得出来）。前一级能表达就不用后一级。
5. **缺 token 就补 token，不在 Zig 里覆盖**。例：`settings_shell.zig:60-71` 用 `surface_1.withAlpha(255)` 盖掉 `.yss` 的背景，应改为在 `zerowork.tokens.json` 增加不透明窗面角色（如 `zw_window_surface`、`zw_window_rest`），由 `widgetTokensFrom` 赋值，`.yss` 直接引用。
6. **视图不做业务判断**。`.yix` 顶层的 Zig 只放视图辅助（文案格式化、a11y 语义、行 key、读 view-model 的选择器）。像 `permissionStatus` 这种从文案反推状态的逻辑，改成 view-model 给出枚举。
7. **业务状态放 view-model，只有纯视觉的瞬时状态用 Yix 局部 `signal`**（悬停、某个提示是否展开）。判断标准：窗口关掉重开后这个状态该不该还在、测试要不要断言它。

### 3.5 需要在 zenit 上游补的扩展点

落在 `~/work/fe/zenit` 的 `feat/app-extension-points`，每项一个 commit 并附测试，之后用快照脚本同步 `vendor/zenit`。

| 编号 | 内容 | 动机 | 测试 |
|---|---|---|---|
| Z1 | 把 `docs/YIX_REFERENCE.md`、`YIX_YSS_GUIDE.md`、`YSS.md`、`VIEW_DSL.md`、`YIX_COMPONENTS.md` 加进 `build.zig.zon` 的 `.paths` | vendor 快照里缺语言参考，子 agent 只能读编译器源码（P0 再次遇到，即缺口 G7） | 包清单校验 |
| Z2 | Yix render prop：`<W.VirtualList itemCount={n} itemHeight={26} row={\|i\| <FileRow index={i} />} />`（语法以 zenit 设计为准） | ZeroWork 有 7 个文件、13 处虚拟列表 | `tests/yix` 新增 fixture + 等价性清单 |
| Z3 | 宿主属性 `onDrop`（载荷为现有 `DropPayload`） | 本地终端文件拖入、SFTP 拖放上传 | 编译器属性表与 `view.zig` 的逐项比对测试、运行期用例 |
| Z4 | `<portal>` 宿主标签，或公开的 `W.Portal` 组件 | 连接进度卡片、拖影等挂在窗口 portal 的自定义浮层 | 运行期用例（挂载、卸载、主题重放） |
| Z5（可选） | Yix 内建的上下文读取 | 省去 view-model 逐层传参 | 等有两个以上 feature 明确需要再排 |
| Z6（G1） | 经组件参数取响应式字段时展开一层（`{vm.field}`）；至少让 `yixFormat` 遇到响应式指针时 `@compileError`，不再静默转储 | V-4：插值静默输出结构体转储 | `tests/yix` 回归用例（以 spike 反例为样本）。**仅登记，待用户确认后再做** |
| Z7（G2） | 事件实参允许结构体字面量（`containsAssignment` 跳过初始化列表里的 `=`） | V-3：`send(vm, .{ .x = 1 })` 被拒 | `tests/yix` 回归用例（以 spike 反例为样本）。**仅登记，待用户确认后再做** |
| Z8（G3） | `{switch}` 支持逗号分隔的多值分支 | V-2：`.a, .b => …` 报 `unexpected token` | `tests/yix` 回归用例（以 spike 反例为样本）。**仅登记，待用户确认后再做** |
| Z9（G4） | 模板内的 `//` 行注释丢弃或报错，不再变成文本节点 | V-2 | `tests/yix` 回归用例（以 spike 反例为样本）。**仅登记，待用户确认后再做** |
| Z10（G5） | 旧 `titlebar = .custom_inset` 路径遇到非 `.inherit` 的 `window_region` 时警告，或让旧路径也读 `windowRegionAt` | V-11：旧路径静默忽略 `windowRegion` | `tests/yix` 回归用例（以 spike 反例为样本）。**仅登记，待用户确认后再做** |
| Z11（G6，可选） | `ui.view.componentFromLegacy(f)` 之类的适配助手，免去逐个手写 `(Props, *Scope, *Cx)` 适配 | V-5：旧代码签名普遍是 `(cx, bound)` | 运行期用例（主题、卸载清理）。**仅登记，待用户确认后再做**；不阻塞 |
| Z12 | 原生的"收向锚点 / 从锚点展开"过渡：对一个节点发起收回或展开，输入为节点、目标锚点的全局矩形、方向；可中途改向；遵守系统"减少动态效果"；有完成回调。分两级：① 基于现有快照层（`snapshot_transition`），沿曲线路径收向锚点并缩放、淡出；② 真正的 genie：对快照纹理做网格形变，需要渲染层支持顶点形变绘制。现有 `node_animator`、`transition`、`snapshot_transition`（只有 `dissolve`）、`overlay_transition`（锚点附近的进出预设）、`tab_motion`、`ContentWarp`（玻璃透镜形变）都承载不了 | 插件化方案 2.5.7：浮动卡片在切换顶部 tab 时收回到所属 tab、切回时展开，效果类似 macOS Dock 最小化（用户判定）。不允许下游用 `animateNode` 手写近似 | 运行期用例：收回与展开、中途改向、减少动态效果、锚点矩形为零或在屏幕外。**不阻塞**：落地前浮动卡片切换 tab 时直接显隐。**状态（2026-11-13）：第一级已在上游完成**（`feat/app-extension-points` @ `db1fdd26`，设计说明 `docs/ANCHOR_TRANSITION.md`；Yix `motionAnchor` / `anchorCollapsed` / `anchorTo` / `anchorRect` / `anchorMotion`，Zig `ui.fx.AnchorTransition`；token 收回 0.28s、展开 0.32s、`ease_in_out_cubic`，减少动态效果时默认原地淡入淡出），待同步进 `vendor/zenit`；第二级 genie 暂不做 |
| Z12b | `AnchorTransition` 增加原地"淡出加轻微缩小"模式（例如 `anchorMotion` 的 `mode = .fade_scale`，缩放比例作为新 token，默认约 0.97），复用同一套快照、改向、减少动态效果与完成回调 | 插件化方案 2.5.7：浮动卡片切换 tab 的动画可在设置里选 `anchor` / `fade`（用户判定，第九批），`fade` 需要这个模式；不在下游用 `anchorRect` 拼 | 运行期用例：原地缩放淡出与反向、中途改向、减少动态效果。**不阻塞**：落地前 `fade` 按纯淡入淡出执行 |
| Z13 | 设计系统的 Card Type 组件补禁用样式（不可选、带原因的视觉状态） | 插件化方案 6.2.1 Q5：被禁用的协议插件在需要以 Card Type 呈现时要有禁用态（Pencil XqqLV 稿 2 的说明稿 Pzzo6 登记）。连接向导目前用 `Select` 的禁用选项（`SelectOption.disabled`，zenit 已支持），不依赖它 | 组件的禁用态快照与 a11y 断言。**不阻塞** |

Z1 应最先做；Z2–Z4 不阻塞迁移（都有 Zig 包装的绕行办法），按 P5 的实际需要排期。Z6–Z11 来自 P0 验证登记的缺口（YIX_SPIKE.md “zenit 缺口”一节的 G1–G6，G7 即 Z1），都有绕行写法，只登记，待用户确认后再做；其中 Z6 未落地前由 `check-arch` 拦截裸的 `vm.field`（4.3 第 7 条）。Z12 来自插件化方案（`docs/plugins/PLUGIN_ARCH_PLAN.md` 2.5.7）的浮动卡片收回动效，不阻塞任何阶段，落地前直接显隐。

---

## 4. 目标架构

### 4.1 分层与依赖方向

```
platform  ←  core  ←  features/<f>/model  ←  features/<f>/view  ←  features/<f>/host  ←  app
                              ↑                      ↑
                       shared/base（纯工具）     shared/ui（设计系统）
```

箭头指向被依赖的一方。各层职责：

| 层 | 位置 | 职责 | 不做什么 |
|---|---|---|---|
| platform | `src/platform` | macOS 桥（`.m` / `.c` 及其 Zig 包装） | 不知道 UI 与业务 |
| core | 现有 `src/{proto,vt,transfer,local,host,ai,config,update}` 与 `plugins` 的非 UI 部分 | 领域模型与服务：会话、SSH、SFTP 引擎、AI 回合、配置存储 | 不 import zenit `ui`，不 import `features` |
| model | `features/<f>/model` | feature 的状态、规则、view-model、Intent、Ports 接口、test_id 表 | 不碰节点、不直接做 I/O |
| view | `features/<f>/view` | `.yix` / `.yss`、生成物、自定义 Zig 组件 | 不 import core 与 platform，不开线程、不做 I/O |
| host | `features/<f>/host` | 实现 Ports：调用 core 服务、持有原生窗口、纹理、worker；把异步结果转成 Intent | 不被 model / view import |
| app | `src/app` | 组合根：进程与窗口管理、把各 feature 装进主窗口 | 不写 feature 逻辑 |
| shared/ui | `src/shared/ui` | 主题运行时、token、跨 feature 组件与样式、资源 | 不 import core、features |

### 4.2 import 规则

| 来源 ↓ / 目标 → | std | zenit `ui` | platform | core | shared/base | shared/ui | 本 feature model | 本 feature view | 本 feature host | 其他 feature | app |
|---|---|---|---|---|---|---|---|---|---|---|---|
| core | 可 | **否** | 可 | 可 | 可 | 否 | 否 | 否 | 否 | 否 | 否 |
| model（纯） | 可 | **否** | 否 | 可（类型与纯函数） | 可 | 否 | 可 | 否 | 否 | 仅 `mod.zig` | 否 |
| model 的 `view_model.zig` | 可 | 仅响应式子集 | 否 | 可 | 可 | 否 | 可 | 否 | 否 | 仅 `mod.zig` | 否 |
| view | 可 | 可 | **否** | **否** | 可 | 可 | 可 | 可 | 否 | 仅 `mod.zig` | 否 |
| host | 可 | 可 | 可 | 可 | 可 | 可 | 可 | 可 | 可 | 仅 `mod.zig` | 否 |
| shared/ui | 可 | 可 | 否 | 否 | 可 | 可 | 否 | 否 | 否 | 否 | 否 |
| app | 可 | 可 | 可 | 可 | 可 | 可 | — | — | — | 仅 `mod.zig` | 可 |

补充规则：
- “响应式子集”指 `ui.Signal`、`ui.Memo`、`ui.Scope`、`ui.Source`、`ui.Handler`。`view_model.zig` 里出现 `ui.Node`、`ui.Cx`、`ui.box`、`ui.widgets`、`ui.view`、`appendChild`、`setStyleInline` 即违规。
- view 需要的 core 类型（如 `SessionHandle`）由本 feature 的 model 重新导出，view 不直接 import core。
- view 里出现 `std.Thread`、`std.Io.Dir`、`std.posix` 即违规。
- 测试文件（`*_tests.zig` 与 `test` 块）放宽：可以 import 本 feature 的任意层、`shared/testing`、core；仍不能 import 其他 feature 的内部文件。
- `plugins/*` 遵守同样的规则，把自身当作一个 feature（`bmc_ikvm` 已有 `non_ui.zig` 门面）。

### 4.3 静态检查

新增构建步骤 `zig build check-arch`，实现为 `tools/arch/check_arch.zig`（Zig 程序，不引入新的脚本运行时）：

1. 遍历 `src/**/*.zig` 与 `src/**/*.yix`，跳过生成物 `_*.yix.zig`、`_*.yss.zig`。
2. 用 `std.zig.Tokenizer` 找 `@import("…")`，把相对路径归一成仓库路径。`.yix` 里的 Zig 部分同样能被分词，标签语法只会产生无关 token；V-9 已验证（`vendor/zenit` 全部 40 个 `.yix` 提取 101 处，与 grep 逐条一致），所以直接扫 `.yix` 源文件，不扫生成物。
3. 按 `tools/arch/rules.zon` 的“路径前缀 → 层”表给来源与目标定层，查 4.2 的矩阵。
4. 标识符级规则：在指定层里搜索禁用 token 序列（上面的 `ui.Node` 等）。
5. 基线文件 `tools/arch/baseline.txt`：每行一条已知违规（`规则 来源文件 → 目标`，不含行号，避免无关改动造成抖动）。出现基线之外的违规即失败；基线只能缩短，`--prune` 模式删除已消失的条目。
6. test_id 检查并入同一工具的第二个子命令（见 6.3）。
7. （待办，尚未实现）拦截 `.yix` 模板表达式里裸的 `<参数>.<信号字段>`：组件参数名后接字段、其后既没有 `.get()` / `.peek()` 也不是函数调用时报错（V-4；可在 V-9 的分词扫描上实现），直到上游 Z6（G1）修复。
8. 基础组件护栏（2026-11-12 新增）：标识符规则 `no-inline-style`（视图、宿主、插件、`shared/ui`、`app` 的非测试代码里出现 `setStyleInline` 即违规）与 `no-widget-internals`（出现 `children.items`，即按下标伸手取子节点）。现存调用进基线（新增时 141 + 105 个文件级条目），只能缩短；新代码一处都不许加。

接线：P0 先作为独立步骤；P2 完成后让主程序与各测试步骤依赖它，与 `check-yix` 并列。

P0 落地情况（详见 `tools/arch/README.md`）：
- 步骤 `zig build check-arch`（默认 `all` = `imports` + `test-ids`）与 `zig build test-arch`（工具自身单测）；子命令经 `-Darch-args="…"` 传入，另有 `count-tests`（V-10 的后备计数口径）与 `list-imports`（调试、V-9 核对）。
- 目标目录尚未存在，`rules.zon` 在目标分层之外加了一组标为 `.transitional` 的过渡层（`legacy_ui`、`legacy_shared_ui`、`legacy_tests`、`legacy_plugin`、`plugin_registry`），P1 搬迁时按 README 的步骤删除，并在搬迁合并提交里一次性重建基线。
- `baseline.txt` 现为 122 条（P0 结束时）；`test_ids.baseline.txt` 与 `test_ids.e2e_used.txt` 已生成。

### 4.4 View-model 与 View 的契约

**数据下行**
- view-model 持有状态，对外提供两种读法：粗粒度的 `*ui.Signal(T)` 字段；以及“选择器”函数（内部对信号 `.get()`，返回普通值）。模板里调用选择器，依赖由运行期实际读取建立，这是 `tests/yix/review_reactive.yix` 明确覆盖的路径，组件参数形式由 V-2 验证。
- 模板里**禁止裸写 `vm.field`**（V-4：插值静默输出结构体转储，其余位置编译失败）。合法写法只有两种：选择器函数，或内联 `vm.field.get()`；两者都建 memo，开销相同。`vm` 参数本身是静态源，信号依赖只来自选择器内部的 `.get()`。
- 选择器必须是纯函数且便宜：挂载时实测会被求值 2 次（`derive` 先探测依赖再建 memo），不能有副作用、不能做重活。
- 列表以“拥有型不可变切片”下发，元素是只含基本类型与字符串切片的视图数据结构，带稳定的 `id` 字段（Yix 的默认行 key）。换数据时整体换切片，不原地改元素。
- 传给视图的字符串由 view-model 拥有，生命周期不短于使用它的那一版数据。

**动作上行**
- 视图只调用 `vm.dispatch(intent)`，或 `.yix` 顶层的一行转发函数。`Intent` 是带载荷的 tagged union，可记录、可在单测里直接喂。
- 事件实参里不能写结构体字面量（V-3）：带载荷的 Intent 用 `Intent` 上的构造函数（`m.Intent.editValue(key, value)`、`m.Intent.openAt(loc)`；名字不能与变体重名）或 `@unionInit(m.Intent, "tag", payload)`，也可以写 `.yix` 顶层的一行转发函数（顶层是普通 Zig，不受此限）。无载荷的写枚举字面量：`onClick={send(vm, .back)}`。
- 处理器挂载时不求值、每次点击重新求值；处理器里读信号是 peek 语义，不建立订阅，可直接调用 `dispatch`。
- 表单控件用“只读值 + onChange”的受控形式：`<W.Switch checked={boolOf(vm, key)} onChange={|v| setBool(vm, key, v)} />`，由 view-model 裁决是否采纳。

**副作用**
- `dispatch` 同步更新状态；需要 I/O、线程、原生面板或窗口操作时，通过 `Ports`（函数指针表）交给 host。
- host 完成后在主线程以 Intent 回流（`.save_finished`、`.permission_changed`）。worker 线程不直接碰 view-model。
- 原生资源（aux 窗口、纹理、文件选择面板、NSAlert）只由 host 持有。

**所有权与窗口**
- 每个窗口有自己的 `Cx` 与 scope；view-model 的信号建在所属窗口的 scope 上。跨窗口共享的是 core 里的数据，窗口之间通过 host 通知各自的 view-model，不共享信号（推测信号图按窗口的 owner 划分，见 V-7）。

**测试**
- model：无窗口单测，喂 Intent，断言状态与发出的 Effect。
- view：无窗口挂载 `ui.view.render`，喂一个假的 view-model，按 test_id 做语义断言（文本、可见性、样式值、禁用态），不依赖节点层级。
- host：契约测试，假的 core 服务 + 真的 view-model。

### 4.5 完整示例：设置窗口

现有零件与去向：

| 现有 | 行数 | 性质 | 去向 |
|---|---:|---|---|
| `config/settings_controller.zig` | 1,269 | 无 UI 依赖的草稿、校验、保存、历史、搜索 | `features/settings/model/controller.zig` |
| `config/settings_model.zig`、`settings_values.zig`、`settings_schema.zig`、`settings_pages.zig`、`settings_history.zig`、`settings_search.zig`、`settings_ai_draft.zig`、`settings_view.zig` | — | 纯数据 | `features/settings/model/` |
| `config/settings_subpages.zig` | 205 | 数据表，但为图标 import 了 `ui` | 数据进 `model/catalog.zig`（图标改成枚举 id），图标映射进 view |
| `config/settings_shell.zig`、`settings_content_view.zig`、`settings_styles.zig`、`settings_parts/*`、`ui/settings/styles.yss` | 约 5,600 | 命令式视图与样式 | `features/settings/view/*.yix` + `styles.yss` |
| `main.zig` 的 `SettingsHost`（`:9196-11483`） | 约 2,290 | 窗口、worker、纹理、清理流程 | `features/settings/host/` |
| `settings_content_view.Hooks`（`:15`）、`Action`（`:12`）、`Navigation`（`:263`） | — | 已有的“动作上行”雏形（`*anyopaque` + 函数指针） | 收敛为 `Intent` |
| `Controller.beginSave / completeSave / failSave`（`:632`、`:676`、`:727`），`requestThemeImport / completeThemeImport`（`:350`、`:375`） | — | 已有的“请求—完成”副作用模式 | 收敛为 `Effect` + 回流 Intent |

**view-model 接口草图**（未编译；Yix 侧写法已按 P0 验证结论修正，见 YIX_SPIKE.md）

```zig
// src/features/settings/model/view_model.zig
const std = @import("std");
const ui = @import("ui"); // 只允许 Signal / Memo / Scope / Source / Handler
const Controller = @import("controller.zig").Controller;
pub const catalog = @import("catalog.zig"); // 分类、子页面、面板、字段的静态表（无 ui 依赖）；视图经 m.catalog 引用
const values = @import("values.zig");
pub const ids = @import("ids.zig"); // 所有 test_id 的 comptime 表

pub const Location = @import("history.zig").Location;
pub const Key = catalog.Key;
pub const Mode = enum { overview, panes, search };
pub const SaveState = enum { clean, dirty_valid, dirty_invalid, saving, save_failed };
pub const Permission = enum { unavailable, querying, not_determined, denied, provisional, authorized, hidden_by_system };
pub const Command = enum { save, revert, reset_defaults, import_theme, export_logs, clear_logs, clear_all, open_config_dir, credential_help, check_updates, open_update_release, notification_permission };

pub const Intent = union(enum) {
    select_category: u8,
    open: Location,
    back,
    forward,
    search: []const u8,
    edit: struct { key: Key, value: values.Value },
    edit_raw: struct { key: Key, text: []const u8 },
    command: Command,
    close_requested,
    decide: enum { save, discard, cancel },
    // 由 host 在主线程回流
    save_finished: struct { ticket: u64, err: ?anyerror },
    permission_changed: Permission,

    // 构造函数：.yix 的事件实参里不能写结构体字面量（V-3），带载荷的 Intent 一律经这里构造。
    // 名字不能与变体同名（Zig 不允许字段与声明重名），所以不叫 open / edit。
    pub fn openAt(loc: Location) Intent { return .{ .open = loc }; }
    pub fn searchFor(text: []const u8) Intent { return .{ .search = text }; }
    pub fn editValue(key: Key, value: values.Value) Intent { return .{ .edit = .{ .key = key, .value = value } }; }
    pub fn editText(key: Key, text: []const u8) Intent { return .{ .edit_raw = .{ .key = key, .text = text } }; }
    pub fn runCommand(c: Command) Intent { return .{ .command = c }; }
};

pub const Effect = union(enum) {
    save: struct { ticket: u64, close_after: bool },
    pick_theme_file,
    export_logs,
    open_config_dir,
    request_notification_permission,
    close_window,
};

pub const Ports = struct {
    context: *anyopaque,
    run: *const fn (*anyopaque, Effect) void,
};

pub const OverviewRow = struct { id: u32, test_id: []const u8, summary_test_id: []const u8, title: []const u8, summary: []const u8, icon: catalog.IconId, target: Location };
pub const Footer = struct { visible: bool, state: SaveState, can_save: bool, can_revert: bool };

pub const ViewModel = struct {
    // 数据下行
    mode: *ui.Signal(Mode),
    location: *ui.Signal(Location),
    title: *ui.Signal([]const u8),
    can_back: *ui.Signal(bool),
    can_forward: *ui.Signal(bool),
    query: *ui.Signal([]const u8),
    overview: *ui.Signal([]const OverviewRow),
    footer: *ui.Signal(Footer),
    permission: *ui.Signal(Permission),
    /// 草稿修订号：每次编辑后加一，字段选择器读它来建立依赖。
    revision: *ui.Signal(u64),

    controller: Controller,
    ports: Ports,

    pub fn init(scope: *ui.Scope, allocator: std.mem.Allocator, config: anytype, ports: Ports) !*ViewModel { … }

    // 动作上行
    pub fn dispatch(self: *ViewModel, intent: Intent) void { … }

    // 选择器
    pub fn boolOf(self: *ViewModel, key: Key) bool { _ = self.revision.get(); … }
    pub fn textOf(self: *ViewModel, key: Key) []const u8 { _ = self.revision.get(); … }
    pub fn problemOf(self: *ViewModel, key: Key) ?[]const u8 { … }
    /// 子页面过滤 + 搜索过滤；取代 showSubpage 与 matchesText。
    pub fn paneVisible(self: *ViewModel, pane: catalog.PaneId) bool { … }
};
```

**`.yix` 草图**（未编译；已按 P0 验证结论修正：信号只经选择器读取，不写裸 `vm.field`；`switch` 每个分支一个值；带载荷的 Intent 经构造函数或顶层转发函数；注释只写在模板外）

```zig
// src/features/settings/view/settings_window.yix
const ui = @import("ui");
const W = ui.widgets;
const S = @import("styles.yss");
const m = @import("../model/view_model.zig");
const Nav = @import("nav.yix");
const Overview = @import("overview.yix");
const Panes = @import("panes/panes.yix");
const SaveBar = @import("save_bar.yix");

fn mode(vm: *m.ViewModel) m.Mode { return vm.mode.get(); }
fn title(vm: *m.ViewModel) []const u8 { return vm.title.get(); }
fn cannotBack(vm: *m.ViewModel) bool { return !vm.can_back.get(); }
fn cannotForward(vm: *m.ViewModel) bool { return !vm.can_forward.get(); }
fn send(vm: *m.ViewModel, intent: m.Intent) void { vm.dispatch(intent); }

pub fn SettingsWindow(vm: *m.ViewModel) View {
    return (
        <row testId="settings.panel" style={S.shell}>
            <Nav.SettingsNav vm={vm} />
            <col style={S.stage}>
                <col testId="settings.island" style={S.island}>
                    <row testId="settings.page.intro" style={S.page_intro}>
                        <row testId="settings.history" style={S.glass_nav}>
                            <W.Button testId="settings.history.back" variant={.ghost} iconOnly iconAsset={ui.icons.chevron_left}
                                a11yLabel="后退" disabled={cannotBack(vm)} onClick={send(vm, .back)} />
                            <box style={S.glass_nav_divider} />
                            <W.Button testId="settings.history.forward" variant={.ghost} iconOnly iconAsset={ui.icons.chevron_right}
                                a11yLabel="前进" disabled={cannotForward(vm)} onClick={send(vm, .forward)} />
                        </row>
                        <col style={S.page_heading}>
                            <text testId="settings.page.title" style={S.page_title}>{title(vm)}</text>
                        </col>
                        <spacer />
                    </row>
                    <W.ScrollArea testId="settings.viewport" style={S.viewport}>
                        {switch (mode(vm)) {
                            .overview => <Overview.Overview vm={vm} />,
                            .panes => <Panes.Panes vm={vm} />,
                            .search => <Panes.Panes vm={vm} />,
                        }}
                    </W.ScrollArea>
                    <SaveBar.SaveBar vm={vm} />
                </col>
            </col>
        </row>
    );
}
```

```zig
// src/features/settings/view/panes/notifications.yix
const ui = @import("ui");
const m = @import("../../model/view_model.zig");
const C = @import("../components/rows.yix"); // Pane / ToggleRow / InputRow / ActionRow

fn shown(vm: *m.ViewModel, pane: m.catalog.PaneId) bool { return vm.paneVisible(pane); }

pub fn Notifications(vm: *m.ViewModel) View {
    return (
        <col testId="settings.notifications">
            <C.Pane testId="settings.notifications.events" title="事件提醒" meta="后台事件与终端声音"
                visible={shown(vm, .notifications_events)}>
                <C.ToggleRow vm={vm} field={.notify_transfer_done} label="后台传输完成" hint="仅离开应用时提醒。" />
                <C.ToggleRow vm={vm} field={.notify_reconnect} label="持续连接故障" hint="断线后自动重连停止并影响工作时提醒。" />
                <C.ToggleRow vm={vm} field={.notify_ai_ready} label="后台 AI 任务完成" hint="默认关闭；仅最终答复完成且离开应用时提醒。" />
                <C.ToggleRow vm={vm} field={.notify_bell} label="终端 Bell 声音" />
                <C.PermissionRow vm={vm} />
            </C.Pane>
            <C.Pane testId="settings.notifications.attention" title="注意标记与勿扰" meta="标签圆点与勿扰时段"
                visible={shown(vm, .notifications_attention)}>
                <C.ToggleRow vm={vm} field={.notify_tab_dot} label="非活跃标签圆点" />
                <C.InputRow vm={vm} field={.notify_quiet_hours} label="勿扰时段"
                    hint="24 小时制，如 22:00-08:00；留空关闭勿扰，不影响后台任务。" />
            </C.Pane>
        </col>
    );
}
```

```zig
// src/features/settings/view/components/rows.yix（节选）
fn on(vm: *m.ViewModel, field: m.catalog.FieldId) bool { return vm.boolOf(m.catalog.key(field)); }
// 一行转发函数：位于模板之外，是普通 Zig，可以写结构体字面量
fn set(vm: *m.ViewModel, field: m.catalog.FieldId, v: bool) void {
    vm.dispatch(m.Intent.editValue(m.catalog.key(field), .{ .boolean = v }));
}

pub fn ToggleRow(vm: *m.ViewModel, field: m.catalog.FieldId, label: []const u8, hint: []const u8 = "") View {
    return (
        <row testId={m.ids.row(field)} style={S.setting_row}>
            <col style={S.setting_copy}>
                <text style={S.setting_label}>{label}</text>
                {if (hint.len != 0) <text style={S.setting_hint}>{hint}</text>}
            </col>
            <W.Switch testId={m.ids.field(field)} checked={on(vm, field)} onChange={|v| set(vm, field, v)} />
        </row>
    );
}
```

**host 侧**：`features/settings/host/settings_host.zig` 保留 `aux_window.Slot`，`Client.mount` 回调里创建 view-model 并 `ui.view.render(scope, cx, SettingsWindow(.{ .vm = vm }))`；`Ports.run` 分派到现有的保存、主题导入、清理流程。

这个例子里要注意的四点：
1. test_id 全部沿用现值（`settings.panel`、`settings.history.back`、`settings.field.<key>` 等），由 `model/ids.zig` 在编译期按现有规则生成（`settings_controls.zig:315`、`:497`）。
2. 子页面切换不再是“建完整页面再隐藏不相关面板”，而是 `paneVisible` 决定各面板的 `visible`。e2e 断言的是“不属于该子页面的面板不可见”（`e2e/settings_revamp_native.ts` 的 `visible()` 判定），两种做法都满足。
3. 切换分类不再整页重建，输入框实例得以保留。现在“输入法组合期间推迟重建”的逻辑（`Mounted.isComposing`，`settings_content_view.zig:122-140`）有望随之删除，需实测（V-6）。
4. 外观页的主题卡片横向滚动、背景预览纹理、服务提供方主从布局先保留为 Zig 自定义组件，以标签嵌入；它们依赖纹理与较重的命令式状态。嵌入时适配函数必须把 `ComponentOf` 传入的子 scope 交给旧代码的 `Binding.scope`，否则卸载不清理（V-5，见 YIX_SPIKE.md §V-5）。

---

## 5. 目标目录树与规范

### 5.1 目录树

```
src/
  main.zig                    入口，只调用 app/main.zig
  root.zig                    zerowork 库门面 + `zig build test` 的聚合根（保留，瘦身）
  tests_ui.zig                test-ui 聚合根（接替 transfer_panel_tests.zig 的聚合职责）
  tests_appearance.zig        test-appearance 聚合根
  tests_bmc.zig  tests_update.zig  tests_font.zig  tests_plugin_fixture.zig
  preview.zig                 预览 runner 与原生夹具的多路复用根（build.zig 给每个产物注入具名模块 root_select，name = 产物名）
  acceptance.zig              验收 runner 与单独运行的测试入口的多路复用根（同上，root_select）
  tests_local.zig             test-local 五个测试二进制的多路复用根（同上，root_select）
                              以上构建根源文件必须留在 src/ 根目录：模块根不能 import 根目录之外的文件（V-1）
  app/
    main.zig                  进程启动、字体、数据目录、MultiWindowApp 主循环
    process_windows.zig       ProcessWindows
    main_window.zig           主窗口组合根（原 mountUI）
    aux_window_runtime.zig    aux_window.Runtime 适配
    startup.zig               启动告警、环境契约
  features/
    shell/                    窗口外壳：view bar、页签条外观、侧栏骨架、岛屿、状态条、工具组
    workspace/                会话 / 分组 / 分屏模型与窗格容器
    terminal/                 终端表面、搜索、补全、命令面板、内置命令
    connections/              主机资产、新建连接向导、连接进度、认证、主机密钥、SOCKS/转发、快速连接
    files/                    SFTP 文件工作区
    transfer/                 传输面板、管理器、冲突与确认
    ai/                       助手面板、Composer、卡片、会话列表、附件
    history/                  会话记录目录与回放
    notifications/            应用内通知与原生通知窗口钩子
    settings/                 偏好设置窗口
    update/                   应用更新界面
  shared/
    ui/
      theme/                  app_theme、theme_states、zerowork.tokens.json、design 常量
      styles/                 跨 feature 的 .yss（表面、排版、发丝线）
      components/<name>/      跨 feature 组件：pane_header、icon_button、copy_button、list_row、segmented、keycap、empty_state…
      assets/                 SVG 与生成的资源注册表（host_os_assets 等）
      window/                 aux_window、窗口 chrome 辅助
      zenit_ext/              挂到 zenit 公开扩展点的适配（焦点指示、原生事件过滤等）
    base/                     与 UI 无关的纯工具
    testing/                  测试夹具：无窗口 Cx、按 test_id 查找、主题矩阵、数据目录覆盖
  platform/                   不变
  plugins/                    不变；内部逐步对齐 model / view / host
  ai/ config/ host/ local/ proto/ transfer/ update/ vt/     core 层，位置不变，清出 UI 文件
tools/
  arch/                       check_arch.zig、rules.zon、baseline.txt、test_ids.baseline.txt
  revamp/                     一次性搬迁工具（P6 删除）
  mockups/                    不变
```

单个 feature 的内部结构：

```
features/settings/
  mod.zig                     唯一对外门面（app 与其他 feature 只能 import 它）
  model/
    controller.zig  state.zig  catalog.zig  values.zig  history.zig
    view_model.zig            信号 + dispatch + 选择器
    ports.zig                 Effect / Ports
    ids.zig                   test_id 表
  view/
    settings_window.yix  _settings_window.yix.zig
    nav.yix  overview.yix  save_bar.yix
    styles.yss  _styles.yss.zig
    panes/                    notifications.yix  ssh.yix  transfer.yix …
    components/               rows.yix；theme_gallery/mod.zig（Zig 自定义组件）
  host/
    settings_host.zig  appearance_host.zig  cleanup_host.zig
  tests/
    all.zig                   本 feature 的测试索引（聚合根只 import 这一个文件）
    controller_tests.zig  view_model_tests.zig  window_view_tests.zig …
  preview.zig                 预览入口（只导出预览函数，不做模块根，由 src/preview.zig 引入）
```

体量大的 feature 先分子域，每个子域再用同样的四目录，例如 `features/connections/{wizard,progress,auth,socks,assets,quick_connect}/`、`features/ai/{pane,composer,cards,sessions,attachments,approvals,tools}/`。门槛：超过约 8,000 行，或有两个以上互相独立的界面。

理由：
- **按 feature 切而不是按技术角色切**。现在的问题正是“所有 view 在一个目录、所有测试在另一个目录”，改一个功能要在三处找文件。feature 目录也是并行开发时天然的所有权边界。
- **feature 内再按层切**，import 方向可以只凭路径判断，检查工具才写得出来。
- **`mod.zig` 门面**沿用 zenit 内置组件与 `plugins/bmc_ikvm/non_ui.zig` 的既有做法。
- **core 目录不动**：它们已按领域划分；e2e 与脚本对其有硬编码路径（见 2.4）；本轮目标是 UI 架构。是否收进 `src/core/` 列为决策 D1。

### 5.2 现有文件的归属规则

精确的逐文件映射由 P1 的调研包产出（`docs/ui-revamp/move-map/<feature>.tsv`）。认领按前缀：

| 现有前缀 / 位置 | 目标 feature |
|---|---|
| `ui/ai_*`、根目录 `ai_*_view_tests.zig`、`main.zig` 的 `AiHost` / `ChildDialog` | `ai` |
| `ui/terminal_*`、`completion_*`、`command_*`、`builtin_*`、`paste_policy`、`timestamp_gutter`、`local_*` | `terminal`（被 core import 的下沉到 core，见下） |
| `ui/workspace*`、`group_*`、`pane_*`、`broadcast_*`、`session_*`、`context_menu*` | `workspace` |
| `ui/sidebar_*`、`tab_*`、`shell_styles`、`v3_geometry`、`status_*`、`background_layers`、`main.zig` 的标题栏 / 侧栏 / 状态条挂载、`MenuHost`、`AppNavHost` | `shell` |
| `ui/wizard*`、`connection_*`、`auth_*`、`host_key_*`、`certificate_*`、`socks_*`、`asset_*`、`quick_connect*`、`main.zig` 的 `WizardHost` / `QuickConnectHost` | `connections` |
| `ui/file_*` | `files` |
| `ui/transfer_*`、`main.zig` 的 `TransferHost` | `transfer` |
| `ui/history_*`、`record_cleanup_view` | `history` |
| `ui/notification_*`、`main.zig` 的 `NotificationWindowHook` | `notifications` |
| `config/settings_*`、`config/settings_parts/*`、`appearance_ui_*`、`ai_provider_settings`、`ai_extensions_settings`、`ai_model_editor`、`keybinding_picker`、`provider_delete_dialog`、`ui/settings/*`、`main.zig` 的 `SettingsHost` | `settings` |
| `ui/app_update_view`、`update/app_host.zig` | `update` |
| `ui/app_theme`、`theme*`、`design*`、`*_assets.zig`、`assets/`、`aux_window`、`copy_button`、`icon_button_feedback`、`control_hint` 等通用件 | `shared/ui` |

层内归类（P1 只搬不改）：
- 不 import zenit `ui` → `model/`。
- import `ui` 且主要在建节点 → `view/`；`*_styles.zig` 跟随所属视图。
- `*_host.zig`、带 `ui` 依赖的 `*_controller.zig`、`*_backend.zig`、`*_bridge.zig` → `host/`。
- 被 core 目录 import 的 `ui/` 文件不进 feature，下沉到它的最低使用层：`session_lifecycle.zig` → `host/`；`terminal_record_geometry.zig`、`timestamp_gutter.zig`、`history_cast.zig` → `vt/`；`command_catalog.zig`、`ai_tools.zig` 的 `Bridge` 类型 → `ai/`；`paste_policy.zig` → `host/`。
  （P1 实际下沉 13 个：`session_lifecycle`、`paste_policy`、`builtin_completion`、`file_authentication`、`group_close_controller`、`host_key_confirmation`、`socks_background_model`、`terminal_document_source` → `host/`；`terminal_record_geometry`、`timestamp_gutter`、`builtin_commands`、`command_palette` → `vt/`；`command_catalog` → `ai/`。`history_cast`、`ai_tools`（含 `Bridge`）、`transfer_panel`、`terminal_document`、`v3_geometry` 不满足下沉条件（闭包里有 `import ui` 的文件，或没有被 core 直接 import），留在 feature 或 `shared/ui`，core 对它们的 import 记在 check-arch 基线；裁决与理由见 `move-map/_overrides.tsv`。）
- 混合型巨型文件（`workspace.zig`、`terminal_view.zig`、`application_host.zig`）先整体放进 `view/` 或 `host/`，它们的违规进入 `check-arch` 基线，留到 P5 拆。

### 5.3 命名规范

| 对象 | 规则 | 例 |
|---|---|---|
| Zig 文件 | `snake_case.zig`；层由目录表达，文件名不再重复 `_view` / `_model`；`host/` 下保留 `_host` 后缀 | `model/controller.zig`、`host/settings_host.zig` |
| Yix 文件 | `snake_case.yix`，主组件为对应的 `PascalCase`；一个文件一个主 `pub fn`，辅助组件可同文件 | `save_bar.yix` → `SaveBar` |
| Yss 文件 | 每个视图目录一个 `styles.yss`；确需拆分时按子区域命名 | `view/styles.yss`、`view/panes/appearance.yss` |
| 生成物 | `_` + 源文件名 + `.zig`，与源文件同目录、一起提交，不手改 | `_save_bar.yix.zig` |
| Yss 名字 | `style`、插槽、维度用 `snake_case`；`recipe` 用 `PascalCase`；不加 `Style` 后缀（Yss 编译器会检查） | `style pane_header`、`recipe NavRow` |
| Yix 参数与属性 | `camelCase`（编译器强制） | `iconOnly`、`testId` |
| Yix 顶层声明名 | 不用 `signal`、`computed`、`ref`、`parts`（Yix 保留字，编译器报错，V-1）；import 子目录 `parts/` 时另起常量名 | `const Rows = @import("parts/rows.yix");` |
| 自定义 Zig 组件 | `view/components/<name>/mod.zig`，导出一个 `PascalCase` 组件函数与 `<Name>Props` | `components/file_table/mod.zig` → `FileTable` |
| test_id | `<feature 前缀>.<区域>.<元素>[.<部件>]`，小写、段内用下划线、段间用点；现有 id 全部冻结；字面量或 `model/ids.zig` 里的 comptime 表，不在视图里拼字符串 | `settings.footer.state` |
| test_id 前缀归属 | 每个一级前缀归一个 feature，新增 id 只能用本 feature 的前缀；映射表放在 `tools/arch/rules.zon` | `wizard.*`、`connection.*`、`socks.*` → `connections` |
| 测试文件 | `<主题>_tests.zig`（沿用现有复数后缀，减少改名）；测试名不改 | `tests/controller_tests.zig` |
| Intent / Effect | 变体用 `snake_case` 动词短语；回流事件用 `*_finished`、`*_changed` | `.open`、`.save_finished` |
| 提交前缀 | 纯搬迁 `refactor(move): …`；行为不变的重构 `refactor(<feature>): …`；本工作流内不混入 `feat` / `fix` | |

### 5.4 测试、预览与生成文件放在哪

- **纯逻辑单测**：就地 `test` 块（Zig 惯例），或 `features/<f>/tests/*_tests.zig`。
- **组件测试**（挂载视图做断言）：`features/<f>/tests/`，每个 feature 一个 `tests/all.zig` 索引。聚合根（`src/root.zig`、`src/tests_ui.zig` 等）只 import 各 feature 的 `all.zig`，新增测试不必碰聚合根。
- **测试归属哪个步骤保持不变**：搬迁时每个测试文件仍由原来的聚合根收集，`-Dtest-filter` / `-Dui-test-filter` 的行为不变。
- **共用夹具**：`shared/testing/ui_kit.zig`（无窗口 `Cx`、`findByTestId`、主题矩阵遍历），替换 52 个文件里的 56 份重复查找函数。
- **预览 runner**：每个 feature 一个 `preview.zig`，只导出若干预览入口，不做模块根；`src/preview.zig` 是多路复用根，由 `build.zig` 给每个产物注入具名模块 `root_select`（`name` = 产物名，见 `selectRoot()`），根文件在 comptime 选出实现文件并转发根级声明（P1 实做；未用 `-Dpreview=<name>` 选项）。P1 只把各 runner 文件原样搬进 `features/<f>/[<子域>/]preview/`（跨 feature 的按钮策略预览进 `shared/ui/preview/`），聚合成 feature 级 `preview.zig` 留到 P3/P5。现有步骤名（`settings-preview`、`connection-progress-preview` 等）保持不变，仍各自产出独立 exe，只是根源文件相同、选项不同。构建根源文件必须位于 `src/` 根目录，预览与验收 runner 只能走多路复用根（`src/preview.zig`、`src/acceptance.zig`）：V-1 已证实子目录里的根文件 import `../` 会报错，而把上层文件做成命名模块也绕不开——一个文件只能属于一个模块，view 文件之间又全靠相对路径互相 import。
- **非 UI 验收 runner 与夹具**（30 + 4 个）：同样的办法收到 `src/acceptance.zig` 之后，实体文件放进所属 core 目录的 `acceptance/` 子目录。（P1 已完成：`src/{ai,host,platform,vt,proto/ssh}/acceptance/`、`plugins/bmc_ikvm/acceptance/`；依赖 UI feature 的放 `features/<f>/tests/acceptance/`。test-local 的五个二进制同样经 `src/tests_local.zig` 选择；原来用 `zig test <文件>` 单独运行的入口补了 `test-builtin-records`、`test-compaction-e2e`、`test-applog` 步骤。）
- **根目录测试的去向（P1 实做）**：被测对象在 core 的测试进所属 core 目录的 `tests/`（`src/{ai,config,host,local,platform,transfer,vt,proto/ssh}/tests/`，按测试代码放宽）；跨 feature 的主题/材质/按钮测试进 `src/shared/ui/tests/`（`shared_ui_tests` 层，不受跨 feature 限制）；插件测试进 `src/plugins/<p>/tests/`。逐文件归属与理由见 `move-map/_final.tsv`、`move-map/_overrides.tsv`。
- **Yix / Yss 生成物**：与源文件同目录提交；`gen-yix` / `check-yix` 的扫描范围从 `src/ui` 改为 `src`（`yix gen` / `check` 接受多个目录并递归遍历，`vendor/zenit/tools/yix.zig:26-36`）；`.gitattributes` 把 `_*.yix.zig`、`_*.yss.zig` 标为 `linguist-generated`。
- **资源生成物**（`host_os_assets.zig` 等，由 `scripts/generate_*_assets.py` 写出）：搬到 `shared/ui/assets/` 时同步改脚本里的输出路径和两个读取它的 e2e 脚本。

### 5.5 `main.zig` 怎么拆

目标：`src/main.zig` 不超过约 80 行，`src/app/` 合计不超过约 1,500 行，其余进各 feature 的 `host/`。

| `main.zig` 行范围（拆分前） | 内容 | 去向（P2 实做） |
|---|---|---|
| 1–7、文件级别名 | import 与别名 | 各目标文件自带所需别名；`src/main.zig` 只剩 `application_test_mode` 与 `main` 转发（4 行） |
| 360–366、431 | 进程级全局变量（`process_windows`、设置窗口槽位与所有者、字体注册表、通知宿主） | `app/process_state.zig`（`pub var`；引用处改为 `process_state.<名字>`） |
| 8–359 | `ProcessWindows` | `app/process_windows.zig` |
| 367–444 | 终端排版、命令信息应用、清理辅助 | `features/terminal/host/typography.zig`（3 个函数）、`app/startup.zig`（2 个清理函数 + `dataStartupAlert`） |
| 445–7711 | `AiHost` | `features/ai/host/ai_host.zig`（整体一个文件，P5 再按回合、附件、审批、停靠、会话列表、关闭确认拆） |
| 7712–8197 | `ChildDialog` | `features/ai/host/child_dialog.zig` |
| 8198–9195 | `RenameTabCtx`、`MenuHost` | `features/shell/host/menu_host.zig` |
| 9196–11483 | `SettingsHost` 及点击辅助 | `features/settings/host/settings_host.zig` |
| 11484–13746 | `AppNavHost`、`NavClick` | `features/shell/host/nav_host.zig` |
| 13747–13863 | `QuickConnectHost`、`SearchHost` | `features/connections/quick_connect/host/quick_connect_host.zig`、`features/terminal/host/search_host.zig` |
| 13864–14064 | AI 点击辅助 | `features/ai/host/ai_host.zig` |
| 〃 | `mountTitleBar`、`mountSidebar`、`mountStatusBar` 及其辅助 | `features/shell/host/chrome_mount.zig`（会创建宿主、接线回调，不只建节点，故放 host；P5 改 `.yix` + 宿主接线） |
| 〃 | `PresentationWindow` | `app/main_window.zig` |
| 14065–14158 | `mountAssistantConversation` | `features/ai/host/ai_host.zig` |
| 14159–14904 | `mountUI` | `app/main_window.zig`（整体；配置加载、图标、菜单、主题选择与后续步骤共享局部变量，原样剪切做不到，未提到 `app/startup.zig`） |
| 14905–15241 | `WizardHost` 及草稿辅助 | `features/connections/wizard/host/wizard_host.zig` |
| 15242–15499 | `NotificationWindowHook` | `features/notifications/host/notification_window_hook.zig` |
| 15500–17304 | `TransferHost` 及回调 | `features/transfer/host/transfer_host.zig`（`onSocksChipClick` 只被 `mountUI` 用，随 `mountUI` 进 `app/main_window.zig`） |
| 17305–17622 | `main`、字体校验与安装 | `app/main.zig`、`app/fonts.zig` |
| 17623– | 设置相关的 1 个测试 | `features/settings/tests/settings_host_decision_tests.zig`（原在可执行文件根，从未被任何测试步骤编译；搬迁后仍未接入聚合根） |

P2 实做结果：`src/main.zig` 4 行；`src/app/` 6 个文件合计 1,554 行（`main_window.zig` 806 行，其中 `mountUI` 本体 745 行，是超出约 1,500 行目标的原因）。各 feature 新增 `mod.zig` 门面，`src/app/**` 只经门面引用 feature；`check-arch` 已挂到主程序与各测试编译步骤上。

P2 只做机械拆分：结构体原样搬到新文件并加 `pub`，互相引用靠文件间 import（Zig 允许文件循环 import）；不改字段、不改方法体。宿主之间通过具体指针类型互相调用的现状先保留，登记进 `check-arch` 基线（跨 feature import 了非 `mod.zig`），P5 再用 Ports 解开。

---

## 6. 迁移计划

### 6.1 总览

| 阶段 | 内容 | 性质 | 并行度 | 前置 |
|---|---|---|---|---|
| P0 | 护栏、基线、技术验证 | 不改行为 | 可并行（互不重叠的新文件） | D11（执行白名单） |
| P1 | 目录搬迁 | 纯搬迁 | 调研并行、执行串行 | P0；冻结窗口 |
| P2 | `main.zig` 机械拆分 | 纯搬迁 | 串行 | P1 |
| P3 | 设置窗口 Yix 样板 | 行为不变的重构 | 内部可并行 | P2；P0 的验证结论 |
| P4 | 设计系统收敛（token、共享组件） | 行为不变 | 与 P3、P5 并行 | P1 |
| P5 | 其余 feature 分波迁移 | 行为不变 | 按 feature 并行 | P3 的规范定稿 |
| P6 | 收尾 | 清理 | 串行 | P5 |

通用规则：
- **搬迁与行为改动分开提交**。`refactor(move)` 提交必须满足：`git show -M --stat` 中文件变化全是重命名；非重命名的改动行只出现在 `@import(...)`、`build.zig` 路径、e2e / 脚本 / 文档里的路径字符串。
- **每个阶段、每个任务包都可独立合并、可回滚**：回滚即 `git revert` 该包的合并提交；包与包之间靠目录所有权隔离，不互相依赖未合并的改动。
- **所有命令在用户已审计的无网络沙箱包装内执行**（仓库是第三方代码，见 D11）。下文写的是包装内的原始命令。

通用退出门禁（每个阶段、每个包都要过）：

```sh
zig build check-yix
zig build check-arch          # P0 之后
zig build -j2
zig build test -j2            # 可先用 -Dtest-filter 跑本包相关，合并前跑全量
zig build test-ui -j2         # 同上，-Dui-test-filter
```

### 6.2 各阶段

**P0 护栏、基线与技术验证**（已完成，2026-11-11）

结果：技术验证结论见 [YIX_SPIKE.md](YIX_SPIKE.md)（V-1/2/3/4/5/11，并汇总 V-9/V-10）；测试计数与截图基线见 [baselines/](baselines/)（`tests.md`、`screenshots.md`）；`check-arch` 的现状见 `tools/arch/README.md` 与 4.3。本文相关各节已按结论修订。

1. `build.zig`：`gen-yix` / `check-yix` 扫描范围改为 `src`；各测试步骤也依赖 `check-yix`。
2. `tools/arch/`：`check_arch.zig`、`rules.zon`、初始基线；新增步骤 `check-arch`（此阶段不挂到主构建上）。
3. test_id 基线：`tools/arch/test_ids.baseline.txt`（见 6.3）。
4. 测试清单基线：记录各测试步骤的用例总数，写入 `docs/ui-revamp/baselines/tests.md`。口径为“测试二进制统计行 + `count-tests` 静态上界”：`--summary all` 不显示用例数（V-10 不成立），改读测试二进制自己输出的 `N passed; M skipped; K failed.` 与逐用例行，后备为 `zig build check-arch -Darch-args="count-tests <根文件>"`。P0 结束时的有效基线：`test` 2,536（静态上界 2,560）、`test-ui` 2,763（静态上界 2,787）。
5. `shared/testing/ui_kit.zig`（新文件，暂不替换旧辅助函数）。
6. 截图基线：选定每个 feature 的代表状态（来自 PENCIL_MAP 的节点），用现有 e2e 脚本产出的截图作为“迁移前”基线，存到仓库外的证据目录。
7. 技术验证（V-1 至 V-9），用现成的隔离预览通道 `zig build mockup -Dmockup=<name>`（`build.zig:262-307`，独立模块、只依赖 `ui`）搭一个 `tools/mockups/yix_spike`（需把 `tools/mockups` 加进 yix 的扫描目录；该通道是单窗口，V-7 的多窗口项改在 P3 的设置预览 runner 上验证），结论写入 `docs/ui-revamp/YIX_SPIKE.md`。mockup 通道的模块根在 `tools/mockups/`，无法 import `src/**`（V-1），所以 V-5 用的是仿制旧面板；用真实旧面板复验放到 P3 的设置预览 runner 上。
8. zenit 上游 Z1（文档进包）并重新同步 vendor。

退出标准：通用门禁全绿；`check-arch` 输出基线且无新增；app 行为与截图无变化；V-1 至 V-5、V-9 至 V-11 各有结论（V-6、V-7、V-8 在 P3 样板阶段给出，V-12 在 P5 波次 B 之前给出）；设置与主窗口的冒烟 e2e（`e2e/settings_revamp_native.ts`、`e2e/workspace.ts`）通过。

**P1 目录搬迁**

1. 并行调研：每个 feature 一个只读包，按 5.2 的规则产出 `docs/ui-revamp/move-map/<feature>.tsv`（旧路径、新路径、层、备注），并列出该 feature 的测试文件、预览 runner、e2e 脚本与 test_id 前缀。
2. 写一次性工具 `tools/revamp/relocate.zig`：读 move-map，执行 `git mv`，重写所有受影响的相对 `@import` 路径与 `.yix` / `.yss` 引用；输出仓库内其余对旧路径的引用清单（`build.zig`、`e2e/`、`scripts/`、`docs/`）。
3. 串行执行，每个 feature 一个 `refactor(move)` 提交，顺序：`shared/ui` → `settings` → 其余 feature → 根目录测试与 runner（改 `build.zig` 的根源文件与聚合根）。
4. 手工同步非 Zig 引用；`PENCIL_MAP.md` 里的模块路径一并更新。
5. 把 `ThemePublication` 从 `ui/shell_styles.zig` 搬到 `shared/ui/theme`，删掉基线里对应的一条（`layer:shared_testing->legacy_ui src/shared/testing/ui_kit.zig → src/ui/shell_styles.zig`）。这一步要拆文件，不是纯搬迁，单独一个 `refactor(shared-ui)` 提交，不混进 `refactor(move)`。

实做（2026-11-12，T1）：
- 搬迁前先把所有构建根收拢到 `src/` 根目录的三个多路复用根 `src/preview.zig`、`src/acceptance.zig`、`src/tests_local.zig`（`build.zig` 的 `selectRoot()` 注入 `root_select`），再按 `shared-ui → settings → shell → workspace → terminal → connections → files → transfer → ai → history → notifications → update → root-core` 13 个 `refactor(move)` 提交执行；聚合根随所属包改名：`tests_appearance`、`tests_font`（settings）、`tests_ui`（transfer）、`tests_update`（update）、`tests_bmc`、`tests_plugin_fixture`（root-core）。
- `check-arch`：每个搬迁提交都用 `--update-baseline` 重建基线并在提交说明里写明按规则的增减；搬迁前另有一个规则提交（测试代码 import `platform` 放行、插件自己的 tests/runner 可 import 本插件未分层文件）；非插件的过渡条目在 root-core 提交里删除，插件过渡条目留到 P5。
- 第 5 条实际提交前缀为 `refactor(theme)`；`shell_styles.zig` 保留一行再导出，`shared/**` 直接 import `shared/ui/theme/theme_publication.zig`。
- 原来以 `zig test <文件>` 单独运行的入口补了构建步骤（另一个 `build:` 提交）；测试计数复核见 `baselines/tests.md` “阶段 P1 复核”。

退出标准：通用门禁全绿；测试用例数与 P0 基线逐步骤相等（口径同 P0 第 4 条：测试二进制统计行 + `count-tests` 静态上界，以 `baselines/tests.md` “阶段 P0 复核”一节的数字为准）；test_id 基线检查通过；提交满足“纯搬迁”判据；`src/` 根目录文件数不超过约 12；各 feature 的冒烟 e2e 各跑一条通过；截图与基线逐像素一致；全量 e2e 回归一次（时间长，放在该阶段末）。

**P2 `main.zig` 机械拆分**

按 5.5 的表，一个宿主一个提交。每次提交后跑通用门禁与该宿主对应的 e2e 子集。

退出标准：`src/main.zig` 不超过约 80 行、`src/app/` 不超过约 1,500 行；通用门禁全绿；全量 e2e 回归；截图逐像素一致；`check-arch` 挂到主程序与测试步骤上（此后新增违规会让构建失败）；各 feature 的 `mod.zig` 门面就位并冻结签名。

**P3 设置窗口 Yix 样板**

| 步 | 内容 | 可回滚点 |
|---|---|---|
| 3a | 先把设置相关的组件测试改成按 test_id 的语义断言，在旧实现上通过 | 独立提交 |
| 3b | `model/view_model.zig`、`ports.zig`、`ids.zig`、`catalog.zig`；`SettingsHost` 实现 Ports；旧视图通过适配层（`Hooks` → `dispatch`）继续工作 | 独立提交 |
| 3c | 共享组件与设置专用行组件（Pane、ToggleRow、InputRow、SelectRow、ActionRow、SaveBar、NavRow、OverviewRow） | 新增文件，未接入 |
| 3d | 外壳、导航、页头、概览、Save Bar 改为 `.yix`；面板正文暂用旧实现，经 `ComponentOf` 包装嵌入。前置小改（V-5）：适配函数把组件传入的子 scope 交给 `Binding.scope`，否则卸载不清理；真实 `Binding.init` 不是 `pub`（`settings_content_view.zig:486`），嵌入粒度优先按 `mountPage`（它本就用传入的 scope 建 `Binding`），单独嵌某个面板则先把 `Binding.init` 改为 `pub` 或新增公开构造函数；`mountPage` 返回的 `Mounted` 句柄经 props 里的输出指针（如 `out: *?Mounted`）交还 host，并在 scope cleanup 里清空。用真实旧面板复验 V-5 | comptime 开关 `settings_view = .legacy / .yix` |
| 3e | 9 个分类的面板逐个改 `.yix`（通知、SSH、传输、数据、快捷键、更新、AI 行为、插件、外观），每个分类一个提交 | 每个分类独立 |
| 3f | 删除旧实现与开关：`showSubpage`、`matchesText`、`normalizeLegacy`、`settings_shell.mount`、`settings_parts/*` | 独立提交 |

实做（3f，settings-3f，2026-11-14）：先逐页对照旧界面与 `.yix`，在新界面补齐缺口（通知授权回执、光标分段锁定、删除主题危险色、AI 辅助的必填标记 / 新增聚焦 / 扩展提示位置 / 读屏文字 / 手输模型 ID 带出元数据），再删除旧实现与开关：`settings_view_mode.zig`、`settings_shell.mount`（文件只留窗口参数与分类图标）、`settings_content_view.zig`（含 `showSubpage`、`matchesText`、`normalizeLegacy`）、`settings_vm_adapter.zig`、`settings_accordion.zig`、`settings_styles.zig`、`panes/settings*.zig`、`panes/appearance_view.zig`、AI 旧视图、旧数据清理对话框、选择器与快捷键录制器、`components/legacy_body`；宿主的旧外壳分支、旧确认弹窗、选择器与录制状态随之删除，`navigateSettings` 改收 `Location`；预览 runner 删除 `--layout=content`。只给旧界面用的 test_id 从基线删除（报告里列出），`check-arch` 基线 −58。

标题栏改用 `windowRegion={.drag}`（V-11）随 3d 一起做：`windowRegion` 只在 `WindowConfig.chrome = .custom` 下生效，与现有 `titlebar = .custom_inset` + `titlebar_height` 二选一，所以 `aux_window.Spec` 要增加 `chrome` 字段（或直接改为 `.chrome = .{ .custom = .{} }`），`main.zig:92` 的窗口配置随之改，删掉对 `titlebar_height` 拖动带的依赖。红绿灯布局（`main.zig:101` 的 `setTrafficLightsLayout` 与 `chrome_backend.configure`）、原生拖动与双击缩放只有源码结论，在设置预览 runner（chrome = .custom）上实证；向导窗口在 P5 照此处理。

退出标准：通用门禁全绿；`e2e/settings_*`（17 个脚本）全部通过，重点是 `settings_revamp_native.ts`；设置窗口截图在明暗两套主题、概览与各子页面上与迁移前逐像素一致（确有差异的逐项说明并得到认可）；PENCIL_MAP 设置窗口一节列出的节点（`p6ZVS` 等）`design_diff` 分数不低于迁移前；`features/settings` 在 `check-arch` 基线里没有条目；本文第 4、5 节的规范按实做情况修订一次并定稿。

**P4 设计系统收敛**（独立包，与 P3、P5 并行）

1. 为已 Yix 化的视图补 `zw_*` token（不透明窗面、动作强调色等），去掉 Zig 里的背景覆盖。
2. 把 PENCIL_MAP “可复用组件”里跨 feature 的几个做成 `shared/ui/components`：Pane Header（`QGtx5`）、列表行（`RI5FN` 系列）、Glass 图标按钮、分段切换、Keycap、空状态。
3. `*_styles.zig`（70 个）随各 feature 迁移逐步并入 `.yss`，不单独做一轮全仓替换。
4. 标题栏的工具按钮一律使用 zenit 原生 ghost 图标按钮的默认尺寸（定稿 Pencil p773F9：zenit 默认的 md 图标按钮，32×32、图标 16、圆角 6）：删除 `shell_styles.titleToolbarButton`（`src/features/shell/view/shell_styles.zig:166-170`，把按钮改成 24×24、圆角 6）对尺寸与圆角的覆盖，7 个调用点（`chrome_mount.zig:77`、`:92`、`:110`、`:119`，`workspace_chrome.zig:47`、`:238`，`app/main_window.zig:733`）改为直接使用原生按钮（用户判定，2026-11-13，见 `docs/plugins/PLUGIN_ARCH_PLAN.md` 6.2.1 第七批）。这一项改变标题栏像素，不受本阶段"截图逐像素一致"约束，截图基线随包重采并注明原因；`ssh_status_host.zig:11` 的注释与 `ssh_status_host_tests.zig:508` 一带依赖 24×24 的断言随之更新。标题栏的 `toolbar.ai` 由插件化方案 PL4c-2 删除，两者若同期执行，以先合并者为准、后者 rebase。

退出标准：通用门禁全绿；使用了共享组件的界面截图逐像素一致；`shared/ui` 在 `check-arch` 基线里没有条目。 基础组件护栏规则（`ident:no-inline-style`、`ident:no-widget-internals`）在基线里的条目只减不增：`shared/ui` 与 9 处保留式换肤遍历的条目在 P4 清零，其余按 `NATIVE_AUDIT.md` 逐项替换、随 P5 各 feature 波次清零（P6 收尾时两条规则的基线条目为 0）；每个包的报告写明本包清掉的条数。

**P5 其余 feature 分波迁移**

每个 feature 两步，各自可合并：**(1) 分层**——抽出 view-model 与 Ports，视图仍是命令式但只和 view-model 打交道；**(2) Yix 化**——把视图改写为 `.yix` / `.yss`，按 3.3 的归属保留自定义 Zig 组件。

| 波次 | feature | 说明 |
|---|---|---|
| A（表单与卡片） | `connections`（向导、进度、认证、SOCKS、资产）、`transfer`、`notifications`、`update`、`history` | 与设置窗口同类，直接套样板 |
| B（外壳） | `shell`（view bar、侧栏、页签外观、状态条）、`files`、`ai` 的面板外壳 / Composer 外壳 / 卡片 | 页签拖拽、文件表格、AI 消息流保持 Zig 自定义组件 |
| C（重构为主） | `workspace`（拆 `Workspace` 结构体）、`terminal`（浮层内容 Yix 化，表面不动）、`ai` 的 `AiHost` 拆分 | 只要求分层达标，Yix 化程度按 3.4 原则 |

每个 feature 的退出标准：通用门禁全绿；该 feature 的 e2e 全部通过（按前缀取脚本集合，见 2.1 的表）；代表状态截图逐像素一致；对应 pencil 节点 `design_diff` 不退化；该 feature 在 `check-arch` 基线里的条目清零（波次 C 允许保留列明的自定义组件内部例外）；test_id 基线检查通过。

**P6 收尾**

删除 `tools/revamp/`；替换 56 份重复的测试查找函数（52 个文件）；非 UI runner 收到 `src/acceptance.zig`；`src/root.zig` 瘦身（去掉 UI 导出）；更新 `docs/GUIDES/DEVELOPMENT.md` 与 PENCIL_MAP；`check-arch` 基线清空或只剩书面认可的例外。

退出标准：通用门禁全绿；全量 e2e 回归；按 AGENTS.md 的打包与安装一致性流程做一次本地 DMG 验证（该流程需要用户明确要求才执行）。

### 6.3 怎样保持 test_id 稳定

1. **源码级基线**。工具扫描 `src` 中所有 `test_id = "…"`、`testId="…"` 字面量，以及 `stableId` 这类前缀拼接点的前缀，生成 `tools/arch/test_ids.baseline.txt`。`check-arch` 的子命令校验：基线里的每个 id 仍能在源码中找到。确需删除或改名时，在同一个提交里改基线并写明理由。
2. **e2e 交叉引用**。同一工具从 `e2e/*.ts` 提取形如 test_id 的字符串（e2e 里约有 2,000 个去重后的点分字符串，含非 id 的误报），与源码清单求交，得到“被 e2e 使用的 id”清单并标记为不可改。
3. **id 是公开接口，定义在 model**。动态 id 由 `model/ids.zig` 用 comptime 表生成，视图只引用；view 层不拼字符串。
4. **id 所在节点的语义不变**。e2e 读取的不只是“节点存在”，还有 `rect`、子树文本、`disabled`、可见性。Yix 化时带 id 的节点必须仍是同一个语义节点：按钮的 id 在可点击的根上、文本 id 在承载文字的节点上（zenit 自己把 Badge 改成 Yix 时就在这一点上出过回归，见 YIX_COMPONENTS 进度表）。组件内部部件的 id 用 `parts` 传。
5. **运行期快照对比**。为每个 feature 的代表状态写一个 Harness 脚本，导出“基线 id → 是否可见、rect、文本”的快照，迁移前后对比（rect 允许 0.5pt 误差）。脚本放 `e2e/revamp/`。
6. **先改测试再改实现**。Zig 组件测试里 119 处 `children.items[i]` 先改成按 id 查找，在旧实现上跑通，再换实现。
7. **本工作流内不改名**。发现命名不一致只登记，不顺手改（决策 D12）。

---

## 7. 子 agent 工作分解

调度方式：Fable 5.2 主 agent 负责拆包、发契约、验收与合并；Opus 5.5 子 agent 写代码；只读调研与清单类任务可以用 Sonnet；纯机械的清点可以用 Haiku。每个包的简报必须包含：本文件的相关章节、所有权清单、输入输出契约、验收命令，以及“不得运行未列入白名单的脚本或二进制、不得访问网络”的约束。

### 7.1 泳道

| 泳道 | 含义 | 并行 | 工作树 |
|---|---|---|---|
| T（主干） | 触碰全局文件的改动 | 严格串行，同一时刻只有一个包 | 集成分支的主工作树 |
| M（调研） | 只读分类，只写自己的 move-map 文件 | 并行 | 不需要独立工作树 |
| Z（上游） | zenit 仓库里的扩展点 | 与本仓库并行 | zenit 仓库自己的工作树 |
| V（验证） | P0 的技术验证 | 并行 | 独立工作树 |
| F（feature） | 单个 feature 目录内的改动 | 并行 | 每包一个独立工作树 |

**只允许 T 泳道修改的文件**（其他泳道一律不碰）：`build.zig`、`build.zig.zon`、`src/main.zig`、`src/root.zig`、`src/tests_*.zig`、`src/preview.zig`、`src/acceptance.zig`、`src/app/**`、`vendor/**`、`tools/arch/**`（基线除自动缩减外）、`.gitattributes`、本文件。feature 包需要改这些文件时，向主 agent 提“接线请求”，由 T 泳道在合并时处理。

### 7.2 任务包

| 包 | 泳道 / 模型 | 负责的文件与目录 | 输入 | 输出契约 | 验收 | 依赖 |
|---|---|---|---|---|---|---|
| T0 护栏 | T / Opus | `build.zig`（yix 范围、`check-arch` 步骤）、`tools/arch/**`、`docs/ui-revamp/baselines/**`、`.gitattributes` | 本文 4.2、4.3、6.3 | `check-arch` 可运行并产出基线；test_id 基线；测试计数基线 | 通用门禁；对工具本身的单测 | D11 |
| V1 Yix 验证 | V / Opus | `tools/mockups/yix_spike*`、`docs/ui-revamp/YIX_SPIKE.md` | 9.2 清单 | 每项“成立 / 不成立 / 替代写法”，附最小示例 | `zig build mockup -Dmockup=yix_spike` | T0 中 yix 范围的改动 |
| S1 testing kit | F / Opus | `src/shared/testing/**` | 现有 56 份查找函数（52 个文件） | `ui_kit.zig`：`headless()`、`findByTestId`、`forEachTheme` | 自带单测 | 无 |
| Z1–Z4 | Z / Opus | zenit 仓库对应文件 | 3.5 表 | 每项一个 commit + 测试 + review 摘要条目 | zenit 自己的测试步骤 | Z1 先行 |
| M-`<feature>` ×12 | M / Sonnet | `docs/ui-revamp/move-map/<feature>.tsv`（每包一个文件） | 5.2 认领表 | 每行：旧路径、新路径、层、是否混合、备注；附测试 / runner / e2e / id 前缀清单 | 主 agent 校验：认领无重叠、无遗漏（与 `find src` 全量比对） | T0 |
| T1 搬迁执行 | T / Opus | 全仓库（按 move-map） | 12 份 move-map | 每 feature 一个 `refactor(move)` 提交；非 Zig 引用同步 | P1 退出标准 | 全部 M 包；冻结窗口 |
| T2 main 拆分 | T / Opus | `src/main.zig`、`src/app/**`、各 `features/*/host/` 的新文件、各 `features/*/mod.zig` | 5.5 表 | 一个宿主一个提交；门面签名冻结 | P2 退出标准 | T1 |
| F-set-model | F / Opus | `features/settings/model/**`、`features/settings/tests/{controller,view_model,catalog}_tests.zig` | 4.5 草图 | `ViewModel`、`Intent`、`Effect`、`Ports`、`ids`；旧视图经适配层照常工作 | `-Dtest-filter='settings'`；`settings_*` e2e | T2 |
| F-shared-ui | F / Opus | `src/shared/ui/{components,styles,theme}/**`（含 `zerowork.tokens.json`） | PENCIL_MAP 可复用组件；P4 清单 | 组件 API 文档写在各 `mod.zig` 头部；新增 token 清单 | 组件单测；预览截图 | T1 |
| F-set-shell | F / Opus | `features/settings/view/{settings_window,nav,overview,save_bar}.yix`、`view/styles.yss`、`view/components/**`、`features/settings/host/**`、对应测试 | F-set-model 的契约 | `SettingsWindow(vm)`；行组件；开关 `.legacy / .yix` | P3 退出标准中外壳相关部分 | F-set-model、F-shared-ui |
| F-set-pane-`<x>` ×9 | F / Opus | `features/settings/view/panes/<x>.yix`、`panes/<x>.yss`、`tests/pane_<x>_tests.zig` | 行组件 API；旧 `settings_parts/settings_<x>.zig` | 一个分类一个组件，test_id 不变 | 该分类的组件测试与 e2e | F-set-shell |
| T3 规范定稿 | T / Fable | 本文件第 4、5 节；`tools/arch/rules.zon` | P3 的经验 | 修订后的规范；删除设置旧实现的提交 | P3 退出标准 | 全部 F-set 包 |
| F-conn-`<sub>` ×5 | F / Opus | `features/connections/<sub>/**`（wizard、progress、auth、socks、assets+quick_connect） | 定稿规范 | 分层提交 + Yix 化提交 | P5 退出标准 | T3 |
| F-transfer | F / Opus | `features/transfer/**` | 同上 | 同上；任务行为 Yix 行组件，列表容器保留 Zig | 同上 | T3 |
| F-files | F / Opus | `features/files/**` | 同上 | 文件表格为自定义组件，工具栏 / 路径栏 / 窗格头为 `.yix` | 同上 | T3 |
| F-notif、F-update、F-history | F / Opus | 各自 feature 目录 | 同上 | 同上 | 同上 | T3 |
| F-shell | F / Opus | `features/shell/**` | 同上 | view bar、侧栏、状态条为 `.yix`；页签拖拽控制器保留 Zig | 同上 | T3、F-shared-ui |
| F-ai-`<sub>` ×5 | F / Opus | `features/ai/<sub>/**`（pane、composer、cards、sessions、attachments） | 同上 | 同上；消息流虚拟列表保留 Zig | `ai_*` e2e 按子域取子集 | T3 |
| F-ai-host | F / Opus | `features/ai/host/**` | `AiHost` 现状 | 按职责拆成多个文件，引入 Ports | `-Dtest-filter` 的 AI 相关集合；`ai_*` e2e | F-ai-`<sub>` 全部合并后（串行） |
| F-workspace | F / Opus | `features/workspace/**` | `Workspace` 结构体现状 | model / host / view 三分；门面签名不变 | `workspace*`、`group_*`、`tab_*`、`session_*` e2e | T3；与 F-shell 之间只通过门面 |
| F-terminal | F / Opus | `features/terminal/**` | 同上 | 表面保持 Zig；命令面板、搜索条、补全内容 Yix 化 | `terminal_*`、`builtin_*` e2e；`vt-perf` 不退化 | T3 |
| T9 收尾 | T / Opus | P6 列出的全局文件 | — | P6 退出标准 | 全量回归 | 全部 F 包 |

所有权不重叠的保证：
- F 包的所有权以目录为界，目录在 T1、T2 之后才存在，且各包目录互不包含。
- 同一 feature 内的多个包（如设置的 9 个面板包）以文件为界，共享的 `view/styles.yss` 与 `view/components/**` 归 `F-set-shell` 一个包；面板包需要新行组件时向它提请求。
- 新增测试只登记到本 feature 的 `tests/all.zig`；同一 feature 的并行包对 `all.zig` 的追加由主 agent 在合并时按行合并（只增不改）。
- 生成物只由拥有源文件的包重新生成：在自己的工作树里跑 `zig build gen-yix`，只提交自己目录下的 `_*.zig`。

### 7.3 哪些必须串行

1. T 泳道内部全部串行：T0 → T1 → T2 → T3 → T9。
2. T1、T2 期间不合并任何 F 包（搬迁会改全仓库的 import 行）。
3. vendor 同步（Z 包落地后）是 T 泳道操作，不与 T1、T2 交叉。
4. 改变某个 feature 门面（`mod.zig`）签名的改动：先由 T 泳道合入“新旧签名并存”的过渡提交，再由 F 包切换，最后 T 泳道删旧签名。
5. `F-ai-host`、`F-workspace` 各自内部串行（单文件巨型结构体，无法再拆所有权）。
6. 同一个 feature 的“分层”提交先于“Yix 化”提交。

### 7.4 工作树与合并

- **用 git worktree 隔离**，每个 F / V 包一个：分支 `revamp/<包名>`，目录放在仓库之外（如 `../ZeroWork-wt/<包名>`），避免 `yix gen src`、检查工具和 Zig 缓存互相扫描。
- **集成分支**：从 `936166e1` 切 `feat/ui-arch-revamp`（决策 D14）。工作树从集成分支当时的尖端创建。注意工作树只包含已提交的内容，开工前主工作区必须干净。
- **工作树的额外准备**：`vendor/libssh2/src/.libs` 与 `vendor/mbedtls/library` 是构建产物、不入库（`build.zig:95-96`、`.gitignore`），新工作树里没有。需要从主工作区复制或重建（重建要跑 `scripts/build_ssh_deps.sh`，属于需审计的脚本），方式由用户确认（D11）。每个工作树各有一份 `.zig-cache`，注意磁盘占用。
- **合并流程**：子 agent 交付分支与验收记录 → 主 agent 在该工作树里 rebase 到集成分支尖端 → 重跑通用门禁与该包的 e2e 子集 → `git merge --no-ff` 进集成分支（保留包内“搬迁 / 重构”分开的提交结构）→ 若基线缩短则更新基线 → 删除工作树。
- **冲突处理**：按所有权划分不应出现冲突；出现即说明有包越界，退回该包重做，不手工消解。
- **回滚**：`git revert -m 1 <合并提交>`；包之间无未合并依赖，回滚一个包不影响其他已合并的包。
- **并发上限**：建议同时不超过 4 个 F 包（每个都要完整编译并跑原生 e2e；e2e 需要各自独立的 RPC 目录与数据目录，现有脚本已按临时目录隔离）。

---

## 8. 风险、开放问题与需要拍板的决策

### 8.1 风险

| 编号 | 风险 | 影响 | 缓解 |
|---|---|---|---|
| R1 | Zig 0.17 的模块根约束与本文假设不符 | 影响 5.4 的聚合根与多路复用设计（只会让方案更简单） | 已消除：V-1 证实约束成立，5.4 的多路复用根必须保留 |
| R2 | ZeroWork 会是 Yix 的第一个大型消费方（现在 0 个 `.yix`），可能撞上编译器缺陷或编译时间膨胀 | 迁移节奏 | P0 做验证；样板先行；自定义 Zig 组件随时可作退路；记录编译时间与二进制体积基线（V-8） |
| R3 | 双主题通道：`app_theme.current()` 直读 1,432 处，材质透明度作用在调色板上 | `.yss` 里拿不到某些角色，出现“Yss 加 Zig 覆盖”的半成品 | 3.4 第 5 条：缺什么补什么 token；不做全仓替换（D9） |
| R4 | 借用字符串与内容判等的语义 | 悬垂引用或界面不更新 | 4.4 的所有权规则；view-model 单测覆盖“换数据后视图读到新值” |
| R5 | 热路径被粗粒度信号拖慢（终端输出、AI 流式输出、大目录） | 性能退化 | 这些路径保持自定义 Zig 组件；`revision` 式粗信号只用于表单类界面；`vt-perf` 与现有性能测试作门禁 |
| R6 | 现有代码依赖命令式句柄（恢复滚动位置、焦点归还、输入法组合期间推迟重建） | 行为回归 | 样板阶段逐项对照 `settings_content_view.Mounted` 的能力；用 `ref` + Zig 辅助函数保留必要句柄 |
| R7 | e2e 是原生窗口测试，328 个脚本无法每个包都全跑 | 回归漏检 | 按前缀取子集做包级门禁；P1、P2、P6 末尾各做一次全量 |
| R8 | 第三方仓库的执行安全 | 子 agent 误跑未审计脚本 | 简报写明白名单；统一经沙箱包装；仓库内的 Python / shell 脚本默认不跑 |
| R9 | 搬迁期间其他分支无法合入 | 并行工作受阻 | 冻结窗口尽量短（P1、P2 连续完成）；提供 move-map 让外部分支自行 rebase |
| R10 | 资源生成脚本与 e2e 对源码路径的硬编码 | 搬迁后脚本写错位置、e2e 读不到文件 | 搬迁工具输出全部非 Zig 引用清单，逐条处理；core 目录本轮不动 |
| R11 | 纯机械拆分 `main.zig` 时文件级别名与进程级全局变量的解析变化 | 编译错误或初始化顺序变化 | 一个宿主一个提交；全局状态集中到 `app/process_state.zig`；每步跑全量测试 |
| R12 | 多窗口下 view-model 的信号归属 | 跨窗口更新丢失或崩溃 | 4.4 的窗口规则；V-7 验证；`multiwindow_*` e2e 作门禁 |
| R13 | 视觉上“逐像素一致”在个别界面做不到（Yix 组件与手写节点的层级差一层导致亚像素差） | 验收卡住 | 允许逐项书面豁免，前提是 `design_diff` 不退化且用户认可 |

### 8.2 需要用户拍板的决策

| 编号 | 决策 | 选项 | 推荐 |
|---|---|---|---|
| D1 | core 各目录是否物理收进 `src/core/` | A 本轮不动，逻辑上视为 core；B 在 P6 之后单独做一轮搬迁 | **A**。e2e、脚本、`build.zig` 对这些路径有硬编码，收益只是顶层目录数从 13 降到 5 |
| D2 | feature 划分 | 5.1 的 11 个；或合并 `shell` + `workspace`，或拆 `connections` | **按 5.1**，大 feature 用子域 |
| D3 | view-model 能否依赖 zenit 的响应式类型 | A 允许 `view_model.zig` 用响应式子集，其余 model 禁止；B model 完全不碰 `ui`，另设绑定层 | **A**。少一层样板，无窗口测试仍可行 |
| D4 | Yix 覆盖范围 | A 按 3.3 / 3.4：表单、面板、卡片、外壳用 Yix，其余为自定义 Zig 组件；B 追求全部 Yix 并等上游补齐 | **A** |
| D5 | 测试放置 | A 就近（feature 内 `tests/`，聚合根留 `src/`）；B 集中到 `src/tests/` 镜像目录 | **A** |
| D6 | 根目录 runner 的归并方式 | A 多路复用根（`src/preview.zig`、`src/acceptance.zig`）；B 把 `src` 做成命名模块，runner 放 `dev/`；C 维持现状 | **A**（V-1 已证实模块根约束成立，runner 不能直接放进 feature 目录做根） |
| D7 | 迁移期是否保留新旧双实现开关 | A 只有设置样板在 3d–3f 期间保留一个 comptime 开关；B 每个 feature 都保留；C 都不保留 | **A**。其余 feature 靠合并提交回滚 |
| D8 | zenit 上游扩展点的排期 | A 先 Z1，Z2–Z4 按 P5 实际需要；B 先全部做完再开始 P5 | **A** |
| D9 | `app_theme.current()` 直读的收敛范围 | A 只在被 Yix 化的视图内收敛到 token；B 全仓替换 | **A** |
| D10 | P1、P2 期间是否冻结其他分支合入 | A 冻结；B 不冻结，由外部分支承担 rebase | **A** |
| D11 | 子 agent 的执行白名单与沙箱 | 需确认：`zig build` 的哪些步骤（`test`、`test-ui`、`check-yix`、`gen-yix`、`mockup`、各 `*-preview`）、哪些 e2e 脚本、是否允许 `scripts/test_isolated.sh` 与 `scripts/build_ssh_deps.sh`、工作树里 SSH 依赖产物用复制还是重建 | 沿用现有无网络沙箱包装；先放行 `zig build` 的上述步骤与 `node e2e/*.ts`；SSH 产物从主工作区**复制**，不在工作树里重跑脚本 |
| D12 | test_id 改名政策 | A 本工作流内零改名；B 允许顺手规范化 | **A** |
| D13 | `plugins/bmc_ikvm` 是否纳入本轮 | A 不纳入，只要求遵守 import 规则；B 一并迁移 | **A**（2,538 行的 `views.zig` 以视频纹理为主，Yix 收益低） |
| D14 | 集成分支 | A 从 `936166e1` 新切 `feat/ui-arch-revamp`；B 直接在当前分支上做 | **A** |
| D15 | 逐像素一致做不到时的豁免流程 | A 逐项书面说明并由用户认可；B 设统一阈值自动放行 | **A** |

P0 期间已定的决策（已落进 `tools/arch/rules.zon` 与基线）：

| 编号 | 决策 | 结论 |
|---|---|---|
| D16 | `plugins/` 下的 `ssh`、`sftp`、`local`、`remote` 是否合并成一个 feature | **已定**：各算独立 feature（`src/plugins/{feature}/**`），彼此只能经门面 import |
| D17 | 插件门面是哪个文件 | **已定**：`plugins/<p>/plugin.zig` 与 `non_ui.zig` 都算门面（过渡期；P1 后按 `mod.zig` 规范收敛） |
| D18 | core 能否 import `zenit_app` | **已定**：允许（字体解析等本身需要原生能力），不算违规 |
| D19 | `host/session_host.zig → plugins/linked_plugins.zig` 与 `platform → core` | **已定**：算违规，留在 `check-arch` 基线，后续消除 |
| D20 | `shared/testing` 能否 import core | **已定**：允许 |

### 8.3 开放问题

1. `Workspace`（约 6,000 行的单个结构体）与 `AiHost`（7,267 行）怎么切，需要各自做一次专项设计；本文只给了落点与“先分层后 Yix”的顺序。
2. 设置窗口之外，连接进度卡片挂在窗口 portal 并对齐到页签内容区（PENCIL_MAP “rv-wizard” 一节），在没有 `<portal>` 标签时由谁承载，等 Z4 的结论。
3. zenit 的 `-Ddev-preview=true` 模板与样式热重载是否值得接到 ZeroWork 的预览 runner 上，属于开发体验增强，不在本轮范围内。
4. `scripts/sync_vendor_zenit.py` 的文档提到“产品定制放在 `src/zenit_ext/`”，但该目录当前不存在；本文把它落在 `shared/ui/zenit_ext/`，需确认是否与原意一致。

---

## 9. 附录

### 9.1 调研中实际读过的关键文件

ZeroWork：
- `docs/ui-revamp/PENCIL_MAP.md`、`AGENTS.md`、`docs/GUIDES/DEVELOPMENT.md`、`e2e/README.md`（节选）
- `build.zig`（全文）、`build.zig.zon`、`vendor/zenit.lock.json`、`scripts/sync_vendor_zenit.py`（头部）、`scripts/audit_ui_constraints.py`（头部）、`scripts/verify_all.sh`、`scripts/verify_source_gate.sh`
- `src/main.zig`（顶层声明清单；`AiHost`、`SettingsHost` 字段区；`mountUI` 开头）、`src/root.zig`、`src/transfer_panel_tests.zig`
- `src/config/settings_shell.zig`（全文）、`settings_content_view.zig`（结构与 `mountPage`、`showSubpage` 等）、`settings_controller.zig`（接口清单与头部）、`settings_model.zig`、`settings_history.zig`、`settings_subpages.zig`、`settings_pages.zig`、`settings_view.zig`、`settings_parts/settings_notify.zig`、`settings_parts/settings_controls.zig`（接口清单）
- `src/ui/settings/styles.yss`、`src/ui/shell/styles.yss`、`src/ui/files/styles.yss`、`src/ui/theme/zerowork.tokens.json`
- `src/ui/app_theme.zig`（接口清单与 token 映射）、`src/ui/aux_window.zig`（头部）、`src/ui/sidebar_view.zig`（头部）、`src/ui/terminal_view.zig`（头部）、`src/ui/workspace.zig`（顶层声明清单）、`src/ui/application_host.zig`（头部）
- `e2e/settings_revamp_native.ts`（前 70 行）

zenit（`vendor/zenit` 快照）：
- `src/yix/compiler.zig`（文件头、宿主属性表、内建识别）、`src/yix/style_compiler.zig`（文件头与词法）
- `tests/yix/*.yix`、`tests/yix/*.yss`（全部）
- `examples/yix_counter`、`examples/hello_button`、`examples/virtual_list_perf/view.yix`、`examples/text_input`、`examples/template_probe/*.yix`、`examples/multi_window`、`examples/storybook/controls/controls.yix`
- `src/ui/components/{modal,menu}/*.yix`、`src/ui/view.zig`（公开接口清单、`yixValue` 一段）、`src/ui/reactive/context.zig`、`src/ui/reactive/props.zig`（`coerce`）
- `docs/STYLING.md`（前半）、`docs/UI_FRAMEWORK_CORE.md`（大纲）、`docs/YIX_EDITOR.md`、`docs/HARNESS.md`（前 80 行）、`tools/yix.zig`

zenit 上游仓库（`~/work/fe/zenit`，分支 `feat/app-extension-points`，只读）：
- `docs/YIX_REFERENCE.md`（§1、§2.2–§2.13、§4–§6）、`docs/YIX_COMPONENTS.md`、`docs/DRAG_INTERACTION_DESIGN.md`（摘要）、`build.zig.zon`（`.paths` 说明）、扩展点提交 `523d53ac`、`8d5fbf24`、`c9c31d2e` 的说明

技能手册：`~/ai-skills/zenit-styling-revamp/SKILL.md`、`~/ai-skills/zenit-ui-components/SKILL.md`、`~/ai-skills/pencil-to-zenit/SKILL.md`（前 300 行）。

没有读的：`.pen` 设计稿本体（需经 pencil 工具访问，本阶段未打开）；`src/ai`、`src/proto`、`src/vt` 的实现细节；绝大多数 e2e 脚本正文。

### 9.2 待验证清单

| 编号 | 待验证的假设 | 影响 | 验证方式 | 状态 / 结论 |
|---|---|---|---|---|
| V-1 | Zig 0.17 下，模块根源文件位于子目录时不能 `@import("../…")` | 5.4 聚合根与多路复用根是否必要 | 最小构建实验 | **成立**：多路复用根必须保留，命名模块绕不开“一文件一模块”（YIX_SPIKE.md §V-1） |
| V-2 | 组件参数可以是 `*ViewModel`，模板里 `helper(vm)` 形式的选择器会跟随其内部读取的信号 | 4.4、4.5 的核心写法 | spike；依据是 `review_reactive.yix` 的 `ExternalOnly`，但那里读的是全局而非参数 | **成立**：选择器挂载时求值 2 次，须纯且便宜；`switch` 不支持多值分支（§V-2） |
| V-3 | 事件里 `onClick={send(vm, .back)}`（带参数的函数调用、枚举字面量实参）可编译且读取的是 `peek` | 动作上行写法 | spike | **成立**，限制：实参不能含结构体字面量，用构造函数或 `@unionInit`（§V-3） |
| V-4 | 模板里直接写 `vm.title`（字段是 `*ui.Signal`）是否被当作响应式源 | 能否省掉选择器函数 | spike；`view.zig:2045-2057` 的 `yixValue` 按类型判定，推测可行 | **不成立**：插值静默转储、其余位置编译失败；改写 `vm.field.get()` 或选择器（§V-4） |
| V-5 | 旧的命令式视图经 `ComponentOf(mountX)` 嵌入 Yix 后，主题切换、卸载清理、test_id 查询都正常 | P3 的 3d 过渡步骤 | spike，用设置的一个旧面板 | **成立**，前提是适配层把组件的子 scope 交给旧代码；spike 用仿制面板，真实面板在 P3 复验（§V-5） |
| V-6 | 切换分类不再重建输入框后，输入法组合状态与焦点行为正确，可以去掉“组合期间推迟重建” | 设置样板的简化程度 | 样板阶段手工 + e2e | 待 P3 |
| V-7 | aux 窗口各自的 scope 上创建的信号互不可见；view-model 建在窗口 scope 上随窗口销毁 | 4.4 的窗口规则 | P3 的设置预览 runner 上开主窗口 + 设置窗口 | 待 P3 |
| V-8 | Yix 生成物对编译时间与二进制体积的影响（生成物含模板元数据与预览用的源码字节串，后者受 `preview_enabled` 门控） | R2 | 记录样板前后的构建耗时与产物大小 | 待 P3 |
| V-9 | `std.zig.Tokenizer` 能稳定地从 `.yix` 中提取 `@import` | `check-arch` 是否要改为扫描生成物 | 工具单测，以 zenit 的 `.yix` 为样本 | **成立**：直接扫 `.yix` 源文件（YIX_SPIKE.md §V-9、`tools/arch/README.md`） |
| V-10 | `zig build test --summary all` 的输出足以得到各步骤的用例总数 | P1 的“用例数不变”判据 | P0 记录基线时确认；不行则改为静态统计聚合闭包内的 `test` 块 | **不成立，有替代**：测试二进制统计行 + `count-tests` 静态上界（§V-10、`baselines/tests.md`） |
| V-11 | `windowRegion` 属性能替代 aux 窗口现在的 `titlebar_height` 拖动带 | 设置窗口与向导的标题栏写法 | spike 给出 headless 语义；原生拖动在 P3 设置预览 runner（chrome = .custom）上实证 | **有条件成立**：须改用 `chrome = .custom`，与旧拖动带二选一；原生行为仅源码结论（§V-11） |
| V-12 | `W.Textarea` 根上的 `onKeyDown` 捕获能实现 Composer 的 Enter 发送 / Shift+Enter 换行，且不干扰输入法 | AI Composer 是否能 Yix 化 | P5 波次 B 开始前 spike | 待 P5 |
