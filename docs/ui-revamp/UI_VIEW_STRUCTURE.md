# UI View 结构梳理（现状地图）

> **文档定位**：本文是对当前 UI 代码结构的一次**现状梳理（as-is）**，供快速建立全局认知；目标架构与整改计划见 [ARCHITECTURE_PLAN.md](ARCHITECTURE_PLAN.md)，zenit 用法审计见 [ZENIT_USAGE_AUDIT.md](ZENIT_USAGE_AUDIT.md)。代码持续演进，引用行号以快照为准。
>
> **快照**：分支 `feat/ui-arch-revamp`，commit `67e82f01`，2026-11-15。

## 一、技术底座：zenit（vendored 自研 GUI 框架）

整个 UI 建立在 `vendor/zenit` 上——Zig 0.17 原生桌面 GUI 框架（独立上游 `github.com/version-next/zenit`，锁在 `feat/app-extension-points` 分支，revision 记录于 `vendor/zenit.lock.json`）。接入方式：`build.zig` 经 `zenit.attach` 把平台桥挂到 exe，`zenit_dep.module("ui")` 作为 `ui` import；主题 token 用 `generateThemeLayers` 将 `src/shared/ui/theme/zerowork.tokens.json` 叠加在 zenit 默认 token 之上（`build.zig:27-51`）。

核心模型（SolidJS 风格）：

- **保留节点树（retained node tree）**：元素是值，`render` 一次性挂载，之后只有细粒度 effect 运行；**无虚拟 DOM、无 diff/reconcile**。动态属性经 `Signal` / `Source(T)`（`vendor/zenit/src/ui/bind.zig`）绑定：静态值零成本一次应用，相等值跳过，slice 记内容哈希。
- **Scope 契约**：组件在调用方 scope 下开子 scope 并绑定到根节点，节点被 `freeNode` 时 signal/memo/effect 一并销毁；宿主把组件换根/重挂即"重绑"（rebind）。Popover/Tooltip 等浮层在重绑下的存活判定是近期上游修复重点。
- **Yix/Yss DSL**：`.yix`（组件模板）与 `.yss`（样式配方）在构建期编译成普通 Zig（生成 `_NAME.yix.zig` / `_styles.yss.zig` 入库），零运行时。参考 `vendor/zenit/docs/YIX_REFERENCE.md`、`YSS.md`。
- **布局**：Taffy 风格约束传递 + flex + layout islands 隔离重排；样式分层存储、位域 dirty flag 冒泡。
- **事件**：DOM 式 capture → target → bubble；焦点/按键捕获有专门设计（`vendor/zenit/docs/FOCUS_AND_KEY_CAPTURE_DESIGN.md`）。
- **内置组件库**（`vendor/zenit/src/ui/components/`，统一基座 `control_shell`）：Button、Input/Textarea、Checkbox、Select/ComboBox、DatePicker、Tabs、Accordion、Modal、Popover、Tooltip、Menu、Notification、VirtualList、Table/DataTable、Tree、Markdown、Glass 系列、WindowChrome（WindowHeader/WindowControls/DragRegion）等。

平台后端：`native/macos/`（NSWindow/Metal/CoreText 桥）+ `src/gpu/`（metal/d3d12/vulkan 多后端 RHI）+ `src/render/`（glyph atlas、SDF、glass material 等）。

## 二、整体分层（revamp 后的静态架构）

依赖方向由 [ARCHITECTURE_PLAN.md](ARCHITECTURE_PLAN.md) 钉死，`zig build check-arch` 按 `tools/arch/rules.zon` 的 import 矩阵强制：

```
platform ← core(proto/vt/transfer/local/host/ai/config/update)
        ← features/<f>/model ← features/<f>/view ← features/<f>/host ← app
        + 横切 shared/ui（设计系统）、shared/base（非 UI 公共逻辑）
```

- **feature 之间只允许经 `mod.zig` 门面互引**（11 个 feature 均已建立，头注释统一声明"唯一对外门面，签名自 P2 起冻结"）。
- **跨层/跨 feature 接线用 C 风格 bridge 结构体**（函数指针 + `?*anyopaque` context），由 app 组合根装配，view/model 不 import 其他 feature。例：`Workspace` 的 `MenuBridge`/`CloseBridge`/`SessionBridge`（`features/workspace/view/workspace.zig:299/328/364`）。
- 已知例外登记在 `tools/arch/baseline.txt`（只降不升）：6 个 host 文件反向引用 `app/process_state` / `app/process_windows`（进程级全局：设置窗口槽、字体注册表、进程窗口表）。

## 三、窗口体系（app 层）

| 窗口 | 机制 | 关键位置 |
|---|---|---|
| 主窗口（可多开） | 统一 `mountUI(cx, scope)` 组合根挂载；第一个在启动时创建，后续经 `ProcessWindows.queue` → 主循环 `drain` 在 tick 边界开出 | `src/app/main.zig:122-136`、`src/app/main_window.zig:59`、`src/app/process_windows.zig:104-201` |
| 偏好设置 | 进程唯一槽 `settings_window_slot`，走 `shared/ui/window/aux_window.zig` 辅助窗口协议（44pt 自定义标题栏） | `src/app/process_state.zig:9-12`、`features/settings/view/settings_shell.zig:27`、`features/settings/host/settings_host.zig:782-849` |
| 新建连接向导 | 同为 aux window，owner 归属主窗口 | `features/connections/wizard/view/wizard.zig:60/128-148` |
| 预览/验收窗口 | `src/preview.zig` 是 comptime 多路复用构建根（按 `root_select` 编出独立 exe），复用生产 view + stub host | `src/preview.zig:14-53`、各 feature `preview/` 目录 |
| 原生通知/菜单栏 | 进程级 NotificationHost + NSMenu 菜单栏（菜单声明来自 `shortcut_router`） | `src/app/app_menu_model.zig:29`、`platform/menu_bar.zig` |

进程级共享域：`Domain`（`features/shell/host/application_host.zig:209-241`）进程唯一，持有 windows/sessions/dispatcher/plugin_security/tasks/ai 等；`ApplicationHost`（`:446`）每主窗口一个。

## 四、主窗口 view 树（`mountUI`）

根节点 `root`（test_id `workspace.shell`，`src/app/main_window.zig:248`）：

```
root (workspace.shell)
├─ background_layers.View                  背景材质层（:388）
├─ main_row (workspace.body, :255)
│  ├─ 侧栏 Sidebar (mountSidebar, :448) + 拖宽把手 / 折叠侧栏
│  └─ content_stack (:261)
│     ├─ title_bar (mountTitleBar, :495)
│     │   ├─ 页签条胶囊 workspace.tab_bar（chrome_mount.zig:47）
│     │   ├─ title_tools 工具组（chain/forward/broadcast/command_history/
│     │   │   transfers/notifications/history/settings，title_tools_view.zig）
│     │   └─ MistChrome（Mist 外观适配，workspace_chrome.zig）
│     ├─ history_card_host (:262)          会话记录卡槽，默认隐藏
│     └─ terminal_area (workspace.pane, :266)
│        ├─ status_bar (:523)              Island B v3 页眉头行
│        ├─ local_status (:533)
│        ├─ empty_state (:272-309)         空态 + 本地终端/快速连接
│        └─ 各 SessionTab.root             每个终端/文件/插件 tab 一个
└─ 直挂浮层：settings_panel(:478)、quick_panel(:511)、AI 浮动卡(:497, z200,
   经 float_layer.attach)、float_layer(:484)、传输面板(:561/:575)、
   SOCKS 三视图(:597)、status_detail(:541)、启动闪屏(:709)
```

**视图切换没有路由/状态机**，是「页签模型 + display 切换 + 浮动卡片」：

- 页签模型 `SessionTab`（`features/workspace/view/workspace.zig:115-211`），`Workspace.tabs` 列表持有；切换 = `selectTab` → `presentActiveTab`（`:4739`）对各 tab root 做 `setDisplay(.flex/.none)`；无页签时显示 empty_state。
- 新建/关闭：`newSession` / `newLocalSession` / `requestCloseTab`（`:5808/:5843/:4779`，关闭经 `close_bridge` 风险确认）。
- 会话卡浮动（`SessionFloatHost`）、卡片 dock/undock（`card_dock`/`card_placement`）、群组视图（`group_views`）。
- 窗口级浮层互斥：`OverlayHost`（`main_window.zig:361`）管规则；标题栏同级面板由 `status_previews.add`（`:683`）注册点击互斥。
- 快捷键：`AppNavHost` 挂在 runtime root 的 `capture_context`（`:442-445`），统一经 `shortcut_router` 分发。

## 五、feature 的 view 层模式

每个 feature 目录固定为 `host/ model/ view/ preview/ tests/`。view 层**两种写法并存**（revamp 中间态，见 ARCHITECTURE_PLAN "Yix 化"路线；例外登记在 [YIX_EXCEPTIONS.md](YIX_EXCEPTIONS.md)）：

1. **命令式 Zig 视图**（多数 feature）：`View` struct（`cx: *ui.Cx` / `scope: *ui.Scope` / `root: *ui.Node` + retained 子节点）+ `mount()`（`scope.createState` + 建节点 + `scope.onCleanup`）+ `update/flush` + `retheme()`；样式走 `*_styles.zig` 包装层。
2. **声明式 Yix/Yss**（settings 为主，ai/terminal/shell/workspace 局部）：`.yix` 模板 + view-model（`ui.Signal` 驱动）+ `ui.view.render` 挂载。

**view ↔ model/host 通信**三种机制常组合：

- **Callbacks 结构体**（函数指针 + context，最普遍）：files 的 `View.Callbacks`（`file_workspace_view.zig:69-79`）、shell 的 `Bridge`+`Actions`（`sidebar_view.zig:12-25`）。
- **Action union / 冻结信封**：view 不直接改 model，发 `Action`（`union(enum)`）+ 带 revision/stamp 的 `Envelope`，防陈旧应用。
- **Projection 投影发布**：host 产出不可变快照，view `update()` 入队、`flush()` 在 after-layout 布局安全点应用（`file_workspace_view.zig:276-305`，含 `error.StaleFileProjection` 校验）。

代表性 feature 谱系（两个端点 + 特殊形态）：

| feature | view 形态 | 特点 |
|---|---|---|
| **terminal** | 命令式重镇（`terminal_view.zig` 约 8600 行） | `TerminalViewNode` 常驻 + 300 行文本节点池脏行跳写 + `TerminalSurface`（PTY 绑定/输入路由）+ 搜索/命令面板/回放子视图；无传统 host 目录，会话编排宿主在 workspace 与 shell 的 `application_host` |
| **files** | model/view 严格分离 | Controller（model）在 `src/host/file_workspace_controller.zig:178`，经粘合层 `file_workspace_presentation.zig` 发布投影；SFTP 引擎属插件（`plugins/sftp/provider_host.zig`），经 `workspace.createFileSessionDirect` 交给 tab |
| **settings** | 全 Yix（窗口 + 9 个分类 pane 模板） | host（1958 行）→ view-model → yix 模板三层契约，头注释明确分工 |
| **ai** | 子域集合（pane/composer/cards/sessions/approvals/attachments/tools/host/shared） | `ai_host.zig`（约 8000 行）持所有子域 view 可选指针统一编排；AI 面板外壳在 app 层用 `shared/ui/float_card/float_chrome` 装配（`main_window.zig:108-206`） |
| **workspace** | `Workspace`（约 9900 行）是**主内容区中枢** | 既是 view（tab/页签/分组）又是编排宿主（tab 生命周期、卡片 dock/浮动、关闭确认）；是其他 feature view 的挂载父；与 shell 分工 = shell 管 chrome 与会话域、workspace 管内容区与 tab |
| **shell** | 应用外框（侧栏/状态栏/菜单/title_tools） | 宿主 `application_host.zig`（约 4500 行）是全会话插件域（Domain/ApplicationHost 所在地） |
| **transfer** | 面板 + 全局 popover + 冲突/事件视图 | 宿主 `transfer_host.zig` 集中持有各 view，app 层装配 |
| **update / notifications / history / connections** | 各自小 View + Callbacks；history 卡内嵌 terminal 的 `ReplaySurface`；notifications 以 presenter + yix 模板为主 | 遵循同一 mount/Callbacks 模式 |

**preview/ 子目录**：显式视觉验收入口，非产品路径。`*_preview_runner.zig` 是独立原生窗口程序，import 生产 view 文件 + stub host 挂载，配 CLI 切主题/场景（如 `settings/preview/settings_preview_runner.zig`）；`*_native_fixture.zig` 是原生夹具。构建上由 `src/preview.zig` 在 comptime 按 `root_select` 选出实现。view 层因此有四种消费者：产品 / preview / tests / e2e。

## 六、共享 UI 层 `src/shared/ui`

唯一合法的跨 feature UI 共享层（不 import core、不 import features）：

- **`theme/`**：`app_theme.zig`（产品色彩语义槽位 surface_1/well/terminal/overlay 等）、`zerowork.tokens.json`（构建期叠加）、`theme_publication.zig`（主线程全局主题发布）。
- **`components/`**：每组件一目录（copy_button、panel_header、color_palette、control_hint、floating_input、icon_button_feedback、session_icon、compact_overlay_layout）；声明式用 `.yix`+`.yss`+生成双胞胎，命令式留在 Zig 并登记 YIX_EXCEPTIONS。
- **`overlay/overlay_host.zig`**：窗口内一切浮层的唯一入口，panel/menu/dialog/card 四类语义（焦点、Tab、Esc、点外部、关闭后焦点），机制复用 zenit 原生浮层。
- **`float_card/`**：非模态浮动卡 Chrome（float_chrome.yix）+ FloatLayer（AI 卡与 history 卡共用）。
- **`window/aux_window.zig`**：辅助原生窗口生命周期协议。
- **`interaction.zig`**：列表/浮层交互常量唯一出处，直接取自 zenit 组件默认值。
- **`styles/`**：layer_materials、float_card_motion、layout_motion、v3_geometry 等运动/材质样式。

另存在少量遗留例外直连（方向仍为 host→view，不构成 view↔view 横向依赖）：`ai_host.zig` 直 import workspace、`settings_host` import shell 样式等，详见 `tools/arch/baseline.txt`。

## 七、平台层与测试

- **`src/platform/`**：macOS 桥（CoreText 字体注册 `ui_fonts`、系统对话框 `dialog_port`、菜单栏、通知、file_promises 等），按分层规则不知道 UI 与业务；zenit 自己的 Metal/NSWindow 桥不经这层，由 `zenit.attach` 直接挂。
- **`src/tests_ui.zig`**：`test-ui` 步骤聚合根（约 180 条 import），单独放 src/ 根是模块根约束（coretext C 源重复链接问题）。
- **`zig build mockup`**：设计稿 HTML 预览（`build.zig:375-421`）。

## 八、当前进行中的整改（截至快照）

P2（main.zig 拆分 + feature 门面 + check-arch 门禁）已完成。最新 [ZENIT_USAGE_AUDIT.md](ZENIT_USAGE_AUDIT.md)（含 2026-11-15 拍板）将上游 174 个实现 commit 分类为 A 通用能力 101 / B 框架缺陷 67 / C 应用用法补丁 1 / D 产品定制 5，八大应用层发现包括：AI 虚拟列表违反 Scope 契约（应改 `mountScoped`）、retained detach/reparent 散落四处（应收敛为单一迁移适配器）、跨边界用 test_id 改组件内部结构、`layer_materials` 应用自建第二套材质系统、逐帧轮询与样式所有权冲突、hover/Esc 双裁决来源等。整改按 6 批执行（批次 1-3 并行），每批门禁 = 空窗口黑盒验证 + 相关 e2e。

## 九、一句话总结

**zenit 提供组件与响应式底座 → `shared/ui` 做设计系统 → 11 个 feature 按 model/view/host 分层、经 mod.zig 门面互引 → app 层 `mountUI` 把 shell 外框 + workspace 内容区 + 各浮层组装成主窗口**。整体正从命令式 Zig 视图向 Yix/Yss 声明式迁移：terminal/files 是命令式端点代表，settings 是 Yix 化目标形态。
