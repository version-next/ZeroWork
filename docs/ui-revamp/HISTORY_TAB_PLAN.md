# 会话记录面板改为 tab content 的实现方案（NATIVE_AUDIT 清单 1 · B3）

状态：方案（只读调查，未改产品代码，未编译、未运行任何构建 / 测试 / e2e）。基点 `f4282769`。
文中 `file:line` 均指基点上的源码。

用户判定原话（2026-11-13）：“会话记录也是既可以 floating 也可以打开的，它就是 tab content 的一种，像 terminal、AI chat panel 一样。”
lead 转述：会话记录成为一种 tab content，支持“浮动”和“作为 tab 打开”两种方式，与终端、AI chat 走同一套机制；不做 Modal / Popover。
现有机制不够时，先登记缺口再给方案。

---

## 0. 结论摘要

1. **仓库里没有一套“tab content”通用机制。** 终端是工作区页签（`SessionTab`，以会话为中心、能力靠一堆可空字段区分）；AI chat 不是页签，
   而是挂在当前会话上的“停靠分栏 ⇄ 浮窗”两态面板，浮窗几何、拖动 / 缩放、停靠分栏、显隐状态机全部写死在 AI 代码和 `nav_host` 里。
   终端不能浮动，AI 不能成为页签。所以“和终端、AI 走同一套机制”需要先补机制，缺口见第 3 节 H-1…H-14。
2. 会话记录现在是**整窗透明拦截层 + 模拟停靠位置的 300 宽卡片**（`history_host.zig:66–74`，`:264–304`），焦点陷阱、点外面 / Esc 关闭，
   本质是一个模态拾取器。打开某条记录会新开一个**只读回放页签**（`workspace.zig:5574`、`:5630`）——“记录回放”已经是页签内容，
   要改的是“记录目录”。
3. 方案：在 core 层定义通用的**页签内容接口**与**浮动面板组件**，工作区支持非会话页签，会话记录作为第一个使用者；
   目录正文按 3e 样板改成 `.yix` + view-model，宿主只保留作业轮询与动作执行。AI 迁到共享浮动面板另行成包（不阻塞本方案）。
4. 拆成 4 个包（H-a 正文 Yix 化、H-b 浮动面板抽取、H-c 工作区非会话页签、H-d 接入两种形态），H-a 与 H-b 可并行，
   建议放在第一批之后、与 F-workspace / F-shell 错开单独成包。第 7 节。
5. 需要用户确认的交互选择 10 条（第 2.3 节），最关键的是 **Q1：“作为 tab 打开”指页签栏里的独立页签，还是 view island 里的停靠窗格**。

---

## 1. 现状与证据

### 1.1 容器与生命周期（`src/features/history/host/history_host.zig`，747 行，全部命令式）

| 项 | 证据 | 说明 |
|---|---|---|
| 整窗拦截层 | `:66` | `position=absolute`、四边 0、`z_index=500`、`hit_behavior=.opaque`；`:67` 初始 `display none` |
| 焦点陷阱 | `:68`、`:190`、`:198`、`:227` | `focus_scope = .{ .trap = true }`，打开时 `pushScope(panel)`，关闭时 `popScope` 并把焦点还给打开前的节点 |
| 卡片 | `:69–74` | `S.card()`（`history_styles.zig:8–11`：absolute、宽 `pane_width=300`、`surface_2` 底、圆角 8、阴影）；`test_id=history.panel`；`floating_input.protect` 两次 |
| 模拟停靠 | `:264–304` `resize()` | 有 island 时把卡片摆到 `workspace.terminal_area` 左上 inset 4、高度撑满 island（Pencil CC3v4 的“左侧 300 宽窗格”）；没有 island 时挂在触发按钮下方；列表高度按视口手算 |
| 点外面关闭 | `:644–650` | 拦截层 `on_event_capture` 收 `mouse_down`，落在卡片外就 `close()` |
| Esc | `:652–659` | 删除确认开着时先取消确认，否则关闭整个面板 |
| ↑/↓ | `:660–673` | 在各行“查看”按钮之间循环移焦并手动滚动 |
| 帧钩子 | `:176`、`:560–640` | `addAfterLayoutHook` 每帧 `poll()`：收后台作业、换肤遍历、补玻璃材质、视口变化重排、重建列表 |
| 换肤 | `:622–628`、`history_styles.zig:76–81` | `S.repaint` 递归 `setRetainedBackground` / `remapUiInk`，再 `setStyleInline(.glass)`；警告色 `historyWarningInk()`（`:693–700`）手工 `patchInk` |
| 材质 | `main_window.zig:456` | `background_view.isolate(scope, history_host.card)`：叠 overlay 材质（`background_layers.zig:239–247`） |
| 挂载位置 | `main_window.zig:304–307`、`:564`、`:749` | 每个主窗口一个 Host，`history_panel` 插在 `root` 的 `main_row` 之前；Mist 外壳 `chrome.ownPanel(history_host.panel)` |
| 回放条槽位 | `main_window.zig:325–328`、`workspace.zig:4043` | `workspace.history.slot` 现在恒为隐藏（回放条已移入回放窗格），是遗留槽位 |

### 1.2 入口

| 入口 | 证据 | 行为 |
|---|---|---|
| 标题栏工具栏按钮 `toolbar.history`（“回看日志”） | `chrome_mount.zig:76–80`，回调 `openGlobalHistory` `:23–27` → `Host.showAll()` | 每次点击都**重新打开并重置**（清空搜索、类型筛选回“全部”、重新读目录，`history_host.zig:197–218`）；不是开关 |
| Mist 外壳里同一个按钮 | `main_window.zig:742` | 只是挪位置，回调不变 |
| 侧栏主机右键“历史会话” / “查看历史会话日志” | `context_menus.zig:258`（标签 `menu_host.zig:385` 改写为“历史会话”）→ `menu_host.zig:684–691` | `history.show(主机名, .{ .saved_connection = id })`：按**稳定来源**过滤，但**界面上看不到这个过滤**（`show` 的主机名参数被忽略，`history_host.zig:183–184`） |
| 终端 / 页签菜单里的“当前会话历史 / 历史回溯 @log” | `context_menus.zig:170/182/232/247/279`、`menu_host.zig:692–694` | 走 `terminal.openHistory()`，是当前会话的 @log 回溯，**不是本面板**，不在本方案范围 |
| 快捷键 / 应用菜单 | `keybindings.zig:83`（`Action` 无 history）、`macos_app_menu.m` 无相关项 | **没有**快捷键与菜单入口 |
| 命令动作 `record.open_history` | `actions.zig:160` | 是“打开只读历史页”（当前页签的回放），不是目录 |

### 1.3 面板功能

- 头部：history 图标、“会话记录”、计数 `history.count`（`:75–83`）、关闭按钮 `history.close` + 提示 `history.close.tooltip`（`:84–87`）。
- 搜索：原生 `W.Input`，但被 `theme.styleInput` 与 `setStyleInline` 覆盖高度 28、底色、圆角、字号（`:88–103`）；id：`history.query`（节点）/ `history.search`（输入容器）。
  `on_submit` 把焦点移到第一行的“查看”（`:241–244`）。
- 类型筛选：三个 `W.Button`（全部 / SSH / 本地），`base_style` 覆盖尺寸，选中态靠 `setBackground(popupSelection)`（`:105–121`、`:320`）。
- 清空：图标按钮 `history.clear`（需确认）（`:123–128`）。
- 列表：`W.ScrollArea`（关回弹 `rubber_band_y=false`，`:129`），每页 `page_size=100`（`history_list.zig:17`），每行 66 高（`history_styles.zig:5`）；
  行：标题（`history.record.title` + 提示）、时间、`user@endpoint · 时长`（`history.record.detail` + 提示）、状态标签（手搓 `statusTag`，`history.record.state`）、
  查看 / 导出 / 删除三个图标按钮（`history.record.view|export|delete` + 各自提示）（`:339–392`）；分页 `history.previous|next`（`:393–404`）。
  空态 `history.empty` / `history.empty.detail`（`:325–337`）。
- 消息与重试：`history.message`（加载中 / 错误 / 删除结果）、`history.retry`（`:136–146`、`:551–559`）。
- 删除确认：**原生 `W.Popover`**（锚在删除 / 清空按钮，宽 288），但 chrome 被 `setStyleInline(S.confirmationChrome)` 覆盖、每次换肤重写（`:147–171`、`:480–482`），
  id：`history.confirmation`、`history.delete.cancel|confirm`。删除走后台 `DeleteJob`（`:486–537`、`:561–577`）。
- 打开某条记录（`:418–447`、`:597–611`）：已有同一记录的回放页签就 `focusArchive` 选中它并关闭目录；否则后台 `Job` 解码，完成后
  `workspace.openArchiveDocument(document)` 新开**只读回放页签**（`workspace.zig:5574–5586` → `openArchivedContent` `:5630–5669`，
  `content_owner = .{ .history = HistoryId }`，挂只读 `TerminalViewNode`），然后关闭目录。加载中按 Esc 取消（实为关闭面板，`close()` 置取消标志，`:224`）。
- 导出（`:448–469`）：原生保存对话框 → `session_export_jobs.Manager` 后台导出。
- 清理记录确认（设置“数据与日志”里的“清理记录”）是另一个东西：`view/record_cleanup_view.zig`（原生 `W.Modal`，NATIVE_AUDIT 清单 1 #15），
  由 `settings_host.zig:2276` 使用，**不属于本面板**，本方案不动它。
- 死代码：`view/history_row.zig` 的 `mount`（`回放 / 导出` 文字按钮，含 `stylePrimary` 覆盖与 `history.record.replay` id）只在它自己的测试里用，宿主只取 `Action` 枚举（`history_host.zig:10`）；
  `history_styles.zig` 的 `chip()`、`button()` 只被该死代码或无人使用。

### 1.4 测试与 e2e

- 单元测试：宿主 `Host` **没有**任何单元 / 组件测试。model 层有（`history_list.zig:118–207`、`history_archive.zig:221`、`history_cast / reading / replay`），
  `history_row.zig:24`（死代码的测试）、`tests/record_cleanup_ui_tests.zig`（清理记录 Modal）。注册在 `src/tests_ui.zig:35/41/116/117`。
- 用到本面板 id 的 e2e / 工具（`grep` 结果）：

| 脚本 | 用到的 id | 依赖的语义 |
|---|---|---|
| `e2e/global_history_native.ts`（主验收） | 几乎全部 `history.*`、`toolbar.history`、`tabs.tab.3` | 宽 480（`:55`）、搜索框高 36（`:57`）、点记录内容不关闭（`:69`）、**Tab 不出面板（`:82–83`，依赖焦点陷阱）**、↑↓ 与 Enter 打开（`:76`、`:101`）、打开后目录消失（`:105`、`:119`）、Esc 关闭 / 只取消确认（`:52`、`:124`、`:178`）、确认气泡宽 288 且右缘对齐（`:186`）、失败时不新开页签 `tabs.tab.3`（`:173`） |
| `e2e/floating_input_native.ts:43` | `toolbar.history`、`history.panel`、`history.close` | 头部内边距量测 |
| `e2e/vanta_error_states_native.ts:47–51` | 侧栏右键 `context.menu.history`、`history.empty`、`history.panel`、`history.close` | 空态与关闭 |
| `e2e/patch_history_native.ts:31–33` | `context.menu.history`、`history.record`、`history.record.view` | 从主机菜单打开并回放 |
| `e2e/mist_workspace_native.ts:95`、`e2e/visual_audit_capture.ts:99/170`、`e2e/workspace.ts:174` | `toolbar.history`、`history.panel`、`history.record` | 截图 / 树快照 |
| `tools/ui_v4/generate_mist.py:166`、`verify_mist.py:11` | `toolbar.history` | 不运行（`scripts/`、工具脚本按安全规则不跑） |
| `e2e/global_history_theme_pixels.py` | 主验收的配套像素检查 | 同上 |

  注意：`global_history_native.ts` 断言宽 480、搜索框高 36，而源码是 300（`history_styles.zig:7`）与 28（`history_host.zig:102–103`）——这条脚本**很可能已与现状脱节**（未运行，未实证），改写时一并核对。
- test_id 基线：`tools/arch/test_ids.baseline.txt` 有 38 个 `history.*` / `toolbar.history` / `workspace.history.slot`；
  `test_ids.e2e_used.txt` 有其中 22 个（不可改名）。
- `check-arch` 基线里与本面板相关：`ident:no-inline-style` `history_host.zig`（行 464）、`ident:no-widget-internals` `history_host.zig`、`history_styles.zig`（590–591）；
  cross-feature：`history_host → workspace/view/workspace.zig`、`→ session_export(_jobs).zig`（151–153）、`history_styles → ai_close_confirmation_styles / notification_styles`（158–159），
  以及 `chrome_mount / menu_host → history_host`（187、200）。

### 1.5 NATIVE_AUDIT 对照

`NATIVE_AUDIT.md:77`（B3）、`:308`（history：B3、Modal 1、Input、Chip）、`:173`（`styleInput` 含 history_host）、`:193`（`input_container.setStyleInline` history_host 4 处）、
`:246`（ScrollArea 关回弹 `history_host.zig:129`）、`:255`（`history_styles.zig:58 chip()`）。另：删除确认 Popover 的 chrome 覆盖（`:152`）与状态标签手搓（`statusTag`）审计表未单列，本方案一并清。

---

## 2. 目标交互

### 2.1 “tab content”的参照物：终端与 AI chat 现在各是什么样

**终端（页签内容）**

- 模型：`workspace_model.Tab`（`workspace_model.zig:7–31`）只存 `id / owner / title / container / details`；`owner` 是 `identity.ContentOwner = union { session, group, history }`（`host/identity.zig:82–90`）。
- 视图侧：`SessionTab`（`workspace.zig:106–160`）以会话为中心，用可空字段区分内容：`terminal`（终端）、`file_scope`（文件工作区）、`plugin_renderer`（插件渲染器，带 vtable `update / focus_changed / unmount / connection_status`，`plugin_ui_contract.zig:94–108`）、`archived + archive_document`（只读回放）。
- 选中：`presentActiveTab` 只切 `tab.root` 的 display 并把焦点给终端根或 `tab.root`（`workspace.zig:4020–4050`），这一段本身是通用的。
- 页签外观：`tabIcon`（`:1807`）、`tabStatus`（`:2005`，回放页签是“只读”）、`installTabModel` 的详情串（`:1541–1560`）。
- 关闭：`requestCloseTab`（`:4058`）先问 `close_bridge.risk`，有风险走确认（原生 Modal，H-modals-ws），否则 `forceCloseTab`；回放页签经 `ApplicationHost.closeForInput`（`application_host.zig:1844–1848`）的 `.history` 分支与 `history_closes`（`:2439`）收尾。
- 不能浮动；不跨窗口移动；**不持久化**（仓库里没有页签 / 会话恢复，`grep` 无结果；`OVERALL_ARCHITECTURE.md` §11 的“会话恢复”指断线后复原屏幕）。

**AI chat（停靠分栏 ⇄ 浮窗，挂在当前会话上）**

- 两态切换：`ai.dock` 按钮（`main_window.zig:143–147`）→ `AiHost.toggleDocked`（`ai_host.zig:3784–3798`），只翻 `pane.docked`（窗口级、内存、不落盘），会话、焦点、显隐都保留。
- 停靠分栏：`ai_pane_layout.zig:19–51`（宽 500、最小 340、给会话留 320、island 右侧 inset 4、4pt 分隔条拖宽），`apply()`（`:56–100`）在两种 chrome 之间改 inline 样式；
  island 右侧让位由 `nav_host.zig:630–638` 改 `terminal_area` 的 padding；底板由 `background_layers.zig:27–30, 68–102` 的 slot 5 画。
- 浮窗：几何模型 `src/ai/float_model.zig`（最小 520×354，`:6–7`；`safeBounds / clampRect / resized`），手势 `ai_float_gestures.zig`（拖动柄 `ai.float.drag`、8 个缩放柄 `ai.float.resize.<edge>`，`:7–8`；双击柄复位，e2e `ai_float_geometry_native.ts:16–19`），
  最大化 `ai.maximize`（仅浮窗）。几何**按会话 owner 各存一份**（`ai_float_gestures.zig:1` 注释、`AiHost.assistant_states`）。
- 显隐：`dock_state.zig:3` `Mode { hidden, preview, pinned }`（悬停 `ai.strip` 预览、点击钉住）；入口 `toolbar.ai`、`ai.strip`、`⌘J`（`nav_host.zig:846`，`keybindings.zig:83` 的 `.ai`）；
  收起 `ai.collapse`；`ai.close` 是“结束当前 AI 会话”并有关闭确认。**每个会话页签各自记住开合**（`ai_tab_presentation_native.ts:67–87`）。没有点外面关闭；Esc 只关附件 / 图片预览（`ai_host.zig:1509–1512`）。
- 布局驱动：几何与 chrome 每帧在 `nav_host.zig:585–628` 里算（`ai.panel` 的 inset / 宽高、视口高度、`background_view.ai_floating`），**全是 AI 专用代码**。
- 前提：必须有当前会话绑定，否则 `toggle()` 直接返回（`ai_host.zig:3040`）。

### 2.2 会话记录的目标交互（建议）

| 维度 | 浮动形态 | 页签形态 |
|---|---|---|
| 是什么 | 非模态浮动面板（与 AI 浮窗同一个共享组件）：可拖动（头部拖动柄）、8 向缩放、双击柄复位；不遮罩、不拦截窗口其余部分、无焦点陷阱 | 工作区页签栏里的一个独立页签（图标 history、标题“会话记录”、状态空），内容区就是目录正文，铺满页签内容区 |
| 入口 | `toolbar.history`、侧栏主机菜单“历史会话”：按“上次使用的形态”打开（默认见 Q3） | 同左；另：浮动面板头部“作为页签打开”按钮；页签存在时入口直接选中该页签 |
| 默认 | 见 Q3（建议：窗口内首次打开为浮动；初始几何 = 现在的停靠位置，island 左侧 inset 4、宽 300、高撑满 island） | — |
| 切换 | 头部按钮（位置与图标对齐 `ai.dock`：`panel-*` ↔ `picture-in-picture-2`） | 头部同一按钮“浮动显示”；页签右键菜单“浮动显示” |
| 切换时保留 | 搜索词、类型 / 来源筛选、页码、滚动位置、选中行、进行中的读取 / 打开 / 删除作业（都在 view-model / Host，不随容器重建） | 同左 |
| 关闭 | 头部 ×（`history.close`）、`toolbar.history` 再点一次（见 Q5）、焦点在面板内时 Esc（见 Q4）；点外面**不**关闭 | 页签 ×、中键、⌘W、“关闭其他页签”；无关闭确认（删除作业进行中时也直接关视图，作业由 Host 继续完成，见 H-11） |
| 多实例 | 每个窗口一个（单例）；浮动与页签互斥（同一时刻只在一种容器里） | 同左 |
| 跟随页签切换 | 浮动面板是窗口级的，切换会话页签时保持（与 AI“按会话记住”不同，见 Q6） | — |
| 打开某条记录 | 新开 / 选中只读回放页签；浮动面板自动收起（保持现行为，见 Q7） | 新开 / 选中回放页签；目录页签保留 |
| 来源过滤（主机菜单入口） | 头部下方显示可关闭的原生 `W.Tag`“仅：<主机名>”，关掉即回到全部（见 H-12、Q8） | 同左 |
| 会话恢复 | 不持久化：重启后不恢复目录页签，浮动几何与“上次形态”只在窗口内存里（与 AI `pane.docked` / 浮窗几何一致）（见 Q9） | 同左 |
| 键盘 | ↑↓ 在行间移动、Enter 打开、搜索框 Enter 跳到第一行（保持现行为）；Tab 正常离开面板 | 同左；⌘1..9 参与页签序号 |

### 2.3 需要用户确认的选择

| # | 问题 | 选项 | 建议 | 依据 |
|---|---|---|---|---|
| Q1 | “作为 tab 打开”指什么 | A. 页签栏里的独立页签（与终端、只读回放页签并列）；B. view island 里的停靠窗格（Pencil CC3v4：island 左侧 300 宽，与 AI 的右侧停靠分栏对称）；C. 三态都要（浮动 / 停靠 / 页签） | **A**；B 作为后续可选（共享面板组件设计时预留“停靠”形态，AI 已用） | 用户原话“tab content 的一种，像 terminal”；lead 转述“作为 tab 打开”；打开记录本来就产生页签。B 更贴近 Pencil 与 AI 的“停靠”，若用户其实指 B，H-c 可以不做，改做 island 左侧让位（工作量更小，见 7.3） |
| Q2 | 页签形态下打开记录：替换目录页签内容，还是另开回放页签 | 另开 / 选中回放页签；在目录页签里就地回放 | **另开回放页签** | 回放页签已有完整生命周期（`.history` owner、关闭收尾、导出、主题 / 字体还原），就地回放要重做这些 |
| Q3 | 默认形态 | 浮动；页签；记住上次 | **窗口内首次打开为浮动，之后记住上次形态（内存）** | 最接近现行为（快速挑一条记录）；不打乱页签序号（e2e 大量用 `tabs.tab.N`）；AI 的“默认停靠”对应的是 island 内分栏，不是页签 |
| Q4 | 浮动形态下 Esc | 关闭面板；不处理（同 AI） | **焦点在面板内时 Esc：先取消删除确认，再关闭面板；焦点不在面板内不处理** | 现行为与规范 §12.1“Esc 关闭浮层”；AI 的 Esc 只关预览，但 AI 有会话内容要保护，目录没有 |
| Q5 | `toolbar.history` 是开关还是“打开并重置” | 开关；打开并聚焦；打开并重置（现状） | **开关**：未显示 → 按上次形态显示并聚焦搜索框；浮动已显示 → 收起；页签存在但未选中 → 选中 | 与 `toolbar.ai` 一致；现状“每次重置搜索与筛选”在常驻容器里会丢用户状态 |
| Q6 | 浮动面板是窗口级还是按会话记住 | 窗口级；按会话（同 AI） | **窗口级** | 目录是全局的，不属于任何会话；AI 按会话是因为对话归属会话 |
| Q7 | 浮动形态打开记录后是否自动收起 | 收起（现状）；保留 | **收起** | 保持现行为与 e2e（`global_history_native.ts:105/119`）；需要常驻对照时用页签形态 |
| Q8 | 主机菜单入口的来源过滤 | 显示为可关闭标签；保持隐式（现状） | **显示为原生 `W.Tag`（closable）** | 常驻容器里隐式过滤会让用户以为记录丢了；现状下面板一关就重置，问题不明显 |
| Q9 | 是否持久化形态 / 几何 / 目录页签 | 不持久化；写入配置 | **不持久化** | 仓库没有页签恢复；AI 的停靠 / 浮窗几何也不落盘；落盘要改配置 schema 与设置页 |
| Q10 | 浮动面板是否要“最大化”与快捷键 | 加最大化 / 加快捷键；都不加 | **都不加** | 需要大视图用页签形态；新增快捷键会进设置“快捷键”面板，属用户可见新功能 |

---

## 3. 机制差距（H-1…H-14）

| 编号 | 现状（证据） | 缺什么 | 建议 |
|---|---|---|---|
| H-1 | 没有“内容种类”的统一概念：终端 / 文件 / 插件 / 回放靠 `SessionTab` 的可空字段区分（`workspace.zig:106–160`）；AI 不是页签 | 一个“页签内容”接口：挂载根、焦点变化、标题 / 图标 / 状态投影、关闭风险、Esc、卸载 | 在 `src/host/` 定义 `TabContent`（vtable，形同 `plugin_ui.RendererInstance` 的超集），`SessionTab` 增加 `content: ?TabContent`；先只给新内容用，不改终端 / 插件现有路径 |
| H-2 | `ContentOwner` 只有 `session / group / history`（`identity.zig:82–90`），`.history` 已被回放页签占用并有关闭收尾（`application_host.zig:1844–1848`、`:2439`） | 非会话、非回放的页签 owner | 新增变体 `panel: PanelId`（`PanelId` 由 core 分配）。需要补的穷举 `switch`：`workspace_model.zig:193`、`application_host.zig:1844`、`:2439`、`notification_coordinator.zig:673`、`platform/notifications.zig:302/328`（编码）、`host/command.zig:129`；其余用 `else` 的（`menu_host.zig:266`、`nav_host.zig:1046/1266`、`transfer_host.zig:136`、`status_detail_view.zig:228`）逐个核对语义 |
| H-3 | 关闭路径以会话 / 回放为中心（`requestCloseTab` `:4058`、`forceCloseTab` `:4208`、`ApplicationHost.history_closes`） | 面板页签的关闭：无确认、直接卸载内容、不走会话释放回执 | `panel` owner 在 `closeForInput` 直接 `forceClose`；`TabContent.close_risk` 预留（会话记录恒为无风险） |
| H-4 | 页签菜单按会话种类出项（`context_menus.zig` 的 `items(kind, …)`，`menu_host.zig:375–390`） | 面板页签的右键菜单 | 新增 kind `panel_tab`：浮动显示 / 关闭其他页签 / 关闭 |
| H-5 | 页签图标 / 状态 / 详情（`tabIcon:1807`、`tabStatus:2005`、`installTabModel:1541–1560`）对无 `host_snapshot`、非 local 的页签回落到标题 | 由内容自己提供图标、状态、详情 | `TabContent.presentation()` 投影；`tabPresentation`（`:1817`）同步给菜单栏 / 通知 |
| H-6 | 大量能力判断写成 `content_owner != .session or archived`（`workspace.zig` 约 20 处，如 `:2184`、`:3367`、`:3405`）；分组、广播、分屏、传输锚点（`nav_host.zig:581–584` 用 `tabs[active].root`）、状态条都默认活动页签是会话 | 非会话页签被选中时，这些功能要“无当前会话”而不是误用 `tab.terminal.?` | H-c 包里逐处审计（以回放页签与文件页签为先例：前者非会话 owner、后者无终端）；`active_tab` 指向面板页签时，状态条显示“会话记录”、传输 / AI 入口按“无会话”处理 |
| H-7 | AI 入口在“有活动页签”时显示（`nav_host.zig:570–571`），但 `AiHost.toggle` 无会话绑定时直接返回（`ai_host.zig:3040`） | 面板页签激活时 AI 入口状态正确 | `has_session` 改为“活动页签是会话”；AI 浮窗在面板页签激活时按“无绑定”收起（与切到空工作区同） |
| H-8 | 浮窗几何、手势、停靠分栏、显隐状态机全部在 AI 代码里：`src/ai/float_model.zig`（最小尺寸写死 520×354）、`ai_float_gestures.zig`（id 写死 `ai.float.*`）、`ai_pane_layout.zig`（右侧、宽 500）、`dock_state.zig`、`nav_host.zig:585–638`（每帧布局与 island 让位） | 一个可复用的“浮动 / 停靠面板”组件：几何模型、拖动 / 缩放 / 复位、边界（island ∩ 窗口）、两态 chrome、可参数化的 id 前缀与最小尺寸 | 抽到 `src/shared/ui/components/float_panel/`（model 纯逻辑 + gestures + 组件）；参数：`id_prefix`、`min_size`、`default_rect(island)`、`dock_side`；**AI 迁移另行成包**，迁移时 `ai.float.*` id 不变。先确认 H-14 |
| H-9 | 没有浮层层级管理：AI 浮窗 `ai_panel` `z_index=200`（`main_window.zig:93–97`），会话记录拦截层 500，各自写死 | 两个浮动面板同时存在时“后激活者在上”，且都低于 Popover / Modal / 通知 | 在主窗口建一个“浮动面板层”容器（`src/app/main_window.zig`，T 泳道接线），组件内按激活顺序排 `z_index`（层内相对值） |
| H-10 | 目录 Host 与容器耦合：`panel/card` 节点、`resize()` 手算高度、焦点陷阱、点外关闭都写在 Host 里（`history_host.zig:66–74`、`:264–304`、`:641–678`） | 容器无关的正文：同一个正文挂在浮动面板或页签根里 | 正文改 `.yix`（`HistoryCatalog(vm)`），Host 只负责作业与动作；切换形态时把正文根节点在两个容器间**改挂**（`detachChild` + `appendChild`），不重建，保住焦点与滚动——需实证 yix 组件子树改挂后信号与 scope 正常（H-c 前做一个小验证，失败则回落为“重建 + view-model 恢复状态 + `focusId` 恢复焦点”） |
| H-11 | 关闭即取消：`close()` 取消读取 / 打开作业、`cancelDelete`（`:220–230`）；`poll` 里很多分支要求 `panel.display != none`（`:581`、`:600`、`:613`、`:621`） | 容器关闭时作业语义：删除作业必须完成并提交索引；读取 / 打开可以取消 | Host 常驻（每窗口一个，现状如此），`visible` 从“节点 display”改成 view-model 的状态；容器关闭 = 取消读取 / 打开、取消未确认的删除；已确认的删除继续，结果在下次显示时呈现 |
| H-12 | 主机菜单入口的来源过滤在界面上不可见（`history_host.zig:183–184`） | 常驻容器下可见、可撤销的过滤 | view-model 增加 `source_label`，正文显示 closable `W.Tag`；新 id `history.source`（追加，不改名） |
| H-13 | 正文是命令式 Zig，含 Input / Button / Popover 覆盖、手搓状态标签、换肤遍历（第 1.3、1.5 节） | 100% `.yix` + 原生组件默认外观 | 第 4.3 节；清掉 `history_host.zig` 的 `no-inline-style`、`no-widget-internals` 与 `history_styles.zig` 的 `no-widget-internals` 基线条目，以及 `history_styles → ai_close_confirmation_styles / notification_styles` 两条 cross-feature |
| H-14 | zenit 没有可拖动 / 可缩放的浮动面板（组件目录 `vendor/zenit/src/ui/components/` 只有 `popover / sheet / modal / window_chrome` 等），AI 浮窗是 ZeroWork 手搓 + `overlayGlass()` 模仿（`NATIVE_AUDIT.md:245`、`:287`） | 判定“浮动面板”算不算基础组件 | **由 lead 判定**：(i) 当作 zenit 缺口（建议下一个空闲 G 编号，`W.FloatPanel`：拖动柄、8 向缩放、边界夹取、双击复位、可选停靠），补上游后 H-b 只做接线；(ii) 当作 ZeroWork 共享组件，登记 `YIX_EXCEPTIONS.md`（b/c 类），面板 chrome 用原生 `W.Card` / Glass 系列、不覆盖外观。本方案按 (ii) 写 H-b，(i) 成立时 H-b 改为“上游接线” |

---

## 4. 实现方案

### 4.1 数据 / 模型

- `src/host/identity.zig`：`ContentOwner` 增加 `panel: PanelId`；`PanelId` 分配器同 `history_ids`（H-2）。
- `src/host/tab_content.zig`（新，core，无 `ui` 以外依赖）：
  ```
  pub const Presentation = struct { title: []const u8, icon: ui.SvgAsset, status: []const u8 = "", details: []const u8 = "" };
  pub const TabContent = struct {
      context: *anyopaque,
      vtable: *const struct {
          root: fn (*anyopaque) *ui.Node,              // 页签形态下挂到 tab.root 的正文根
          focus_changed: fn (*anyopaque, bool) void,
          presentation: fn (*anyopaque) Presentation,
          close_risk: ?fn (*anyopaque) bool = null,
          request_float: ?fn (*anyopaque) void = null, // 页签菜单“浮动显示”
          detached: fn (*anyopaque) void,              // 页签关闭：内容回收到宿主，不销毁 Host
      },
  };
  ```
  `TabContent` 放 core 是为了让 workspace 不 import history（并借此清掉基线 `history_host → workspace.zig` 一条）。若 `check-arch` 的层规则不允许 core 依赖 `ui`，改成只放 `Presentation` 的纯数据部分、`root` 用不透明句柄——H-c 动手前用 `check-arch` 核对。
- `features/workspace/model/workspace_model.zig`：`append` 的 owner 校验加 `panel`（`:193`）；其余逻辑以 `TabId` 为主，无需改。
- `features/history/model/catalog_vm.zig`（新）：view-model，信号字段：`visible`、`mode: enum { floating, tab }`、`query`、`type_filter`、`source_label`、`page`、`rows`（当前页的投影：标题、时间、详情、状态枚举、`can_open / can_export`）、`loading`、`failure`、`message`（文本 + 级别）、`confirm: ?{ count, anchor: row|clear }`、`busy`（`actions_disabled`）、`selected`；
  `Intent`：`query_changed / submit / filter / clear_source / page / open(row) / export(row) / delete(row) / clear_all / confirm_delete / cancel_delete / retry / close / toggle_mode / key_up / key_down / escape`；
  `Effect`：`start_catalog / start_open / start_export / start_delete / focus(id) / close_container / switch_container`。
  状态标签的文案与色调从 `history_host.zig:714–743` 搬进 model（纯函数，可单测）。

### 4.2 宿主

- `features/history/host/history_host.zig` 瘦身为 `CatalogHost`：持有 `archive`、`catalog.Model`、三类作业（`CatalogJob / Job / DeleteJob`），每帧 `poll` 把作业结果写进 view-model；执行 `Effect`；
  对外：`toggle()`、`show(source?)`、`showAs(mode)`、`focus()`、`asTabContent()`。删除：拦截层、`resize()`、焦点陷阱、点外关闭、换肤遍历、`historyWarningInk`、`setStyleInline` 全部。
- 打开记录仍调 `Workspace.openArchiveDocument / focusArchive`，但改经一个 Port（`OpenArchive` 回调，由 app 层接线），去掉 history → workspace 的直接 import。导出同理经 `session_export_jobs` 的 Port。
- 两种容器：
  - 浮动：`shared/ui/components/float_panel` 实例（H-8），`id_prefix = "history.float"`、`min_size = 260×240`、初始几何 = island 左侧 inset 4、宽 300、高 `island.h − 8`（即现在的“模拟停靠”位置，视觉上与现状一致），挂在主窗口的浮动面板层（H-9）。
  - 页签：`Workspace.openPanelTab(TabContent)`（H-c 新增）；Host 记住 `tab_id`，入口发现页签存在就 `selectTab`。
  - 切换（`toggle_mode`）：从一个容器摘下正文根挂到另一个（H-10），失败回落到重建。
- 入口改造：`chrome_mount.zig:23–27` `openGlobalHistory` → `history.toggle()`；`menu_host.zig:684–691` → `history.show(.{ .saved_connection = … }, 主机名)`（主机名用于 `source_label`）。

### 4.3 视图（`.yix` / `.yss`，基础组件全部原生、不覆盖外观）

`features/history/view/catalog.yix`，根 `<col testId="history.panel">`（id 落在正文根，两种容器下都是同一个语义节点）：

| 部分 | 写法 | id |
|---|---|---|
| 头部 | Pane Header：history 图标、“会话记录”、计数文本；形态切换 `W.Button ghost iconOnly`（新）；关闭 `W.Button ghost iconOnly` 包 `W.Tooltip` | `history.count`、`history.mode`（新增）、`history.close`、`history.close.tooltip` |
| 来源过滤 | `{if (source_label)}` `W.Tag closable` | `history.source`（新增） |
| 搜索 | `W.Input`（`leadingIconAsset`、`placeholder`，**不改高度 / 底色 / 字号**），`parts.input_container` | `history.query`、`history.search` |
| 类型筛选 | 三个 `W.Button`，选中用 `variant`（如 `.secondary` vs `.ghost`）表达，不 `setBackground` | `history.filter.all|ssh|local` |
| 清空 | `W.Button ghost iconOnly` + `W.Tooltip` | `history.clear`、`history.clear.tooltip` |
| 列表 | `W.ScrollArea`（默认回弹）里 `{for (rows)}` 行组件 `HistoryRow(vm, row)`；一页 100 行直接展开（与现状相同），不上虚拟列表 | `history.viewport`、`history.record` |
| 行 | 图标；标题 / 详情各包 `W.Tooltip`；时间；状态 `W.Tag`（色调 → `TagColor`：正常结束 success、异常 / 不可用 danger、部分 / 保留 warning、未录制 neutral）；三个 `W.Button ghost iconOnly` + `W.Tooltip` | `history.record.title|detail|state|view|export|delete` 及各 `.tooltip` |
| 空态 | 图标 + 两行文本（`.yss`） | `history.empty`、`history.empty.detail` |
| 消息 | `W.Alert`（`variant` = info / warning），根节点带 id；重试单独 `W.Button`（`W.Alert` 的动作按钮没有 `parts` / id 落点，不能承载 `history.retry`；若 lead 希望用 Alert 自带动作，登记缺口） | `history.message`、`history.retry` |
| 分页 | 两个 `W.Button ghost iconOnly` + `W.Tooltip` | `history.previous|next` 及 `.tooltip` |
| 删除确认 | 原生 `W.Popover`（`width=288`、锚点 = 删除 / 清空按钮，`placement bottom_end`，Esc / 点外取消），**默认 chrome**，正文 `.yss`；按钮 `W.Button secondary / danger` 默认尺寸 | `history.confirmation`、`history.delete.cancel|confirm` |

键盘：↑↓ 由正文根的 `onKeyDown` 发 `Intent.key_up/down`，view-model 算目标行，`Effect.focus(focusId)`；滚动到可见用 `W.ScrollArea` 的声明式滚动（若没有“滚到某行可见”的写法，复用 G42 的登记，不另开号）。
换肤：全部走 token，删除 `S.repaint`、`theme.overlayGlass()` 补丁、`historyWarningInk`。
`history_styles.zig` 只留 `dateLabel / durationLabel`（纯函数，挪到 model），文件删除；`history_row.zig` 删除 `mount` 与其测试，`Action` 挪进 model——这会让源码里不再出现 `history.record.replay`，**需要同一提交改 test_id 基线**（该 id 不在 `e2e_used`，属死代码；按规则在报告里列出，由 lead 认可）。

### 4.4 迁移步骤（每步可单独合入、行为可回退）

1. **H-a**：建 view-model 与 `catalog.yix`；Host 改为驱动 view-model；**容器暂不变**（仍是现在的拦截层 + 卡片，`history.panel` 移到正文根，卡片只做定位）——行为不变的重构，与“外观回到 zenit 默认”的视觉变化分两个提交。
2. **H-b**：抽 `float_panel`（model + gestures + 组件 + 单测），AI 暂不迁移；`float_model` 的测试随之复制一份参数化版本。
3. **H-c**：`ContentOwner.panel`、`TabContent`、`Workspace.openPanelTab`、关闭 / 菜单 / 图标 / 状态 / 能力判断审计（H-1…H-7）；用一个测试用假内容做组件测试，不接会话记录。
4. **H-d**：会话记录接入两种容器、删拦截层、改入口、来源标签、浮动面板层接线（`main_window.zig`），改写 e2e，新增 `e2e/history_tab_native.ts`。
5. （另行成包，P5 F-ai-pane 波次）AI 迁到 `float_panel`；之后可选做 Q1-B 的停靠形态。

---

## 5. test_id 与 e2e 的影响

### 5.1 test_id

- **保留且语义不变**：`history.count / query / search / filter.* / clear(.tooltip) / viewport / record / record.title|detail|state|view|export|delete(.tooltip) / empty(.detail) / previous|next(.tooltip) / confirmation / delete.cancel|confirm / message / retry / close(.tooltip)`。
- **保留但语义变化**：
  - `history.panel`：从“覆盖层里的卡片”变成“正文根”，两种形态下 `rect` 不同（浮动 = 面板内容区；页签 = 页签内容区），不再是模态。
  - `toolbar.history`：从“打开并重置”变成开关（Q5）。
  - `history.close`：页签形态下是否显示待定——建议页签形态隐藏（关闭走页签 ×），则该 id 在页签形态不可见。
  - `history.search` 高度、`history.filter.*` 尺寸、`history.confirmation` chrome 回到 zenit 默认（宽 288 保留）。
- **新增**：`history.mode`、`history.source`、`history.float.drag`、`history.float.resize.<edge>`（来自共享浮动面板的 `id_prefix`）；页签形态用现有 `tabs.tab.<N>`。
- **删除**：`history.record.replay`（死代码，见 4.3）；`workspace.history.slot` 属 workspace，不在本方案删。

### 5.2 e2e（全部未运行；按 COMMON_BRIEF 由 lead 批末统一跑）

| 脚本 | 影响 | 处理 |
|---|---|---|
| `global_history_native.ts` | Tab 不出面板（`:82–83`）不再成立；点外面不关闭；宽 480 / 高 36 断言与现状已不符（未实证）；Esc 语义按 Q4 保留；打开记录后目录消失（`:105/119`）按 Q7 保留 | 改写：删焦点陷阱断言，改为“Tab 能离开面板、Shift+Tab 回来”；尺寸断言改为相对 island / 默认几何；补一段页签形态（打开、⌘W、切换形态保留搜索词） |
| `floating_input_native.ts:43` | 头部量测随 Pane Header 原生化变化 | 改阈值或改量测节点 |
| `vanta_error_states_native.ts:47–51`、`patch_history_native.ts:31–33` | 主机菜单入口多一个 `history.source` 标签；关闭仍是 `history.close` | 轻改 |
| `mist_workspace_native.ts:95`、`visual_audit_capture.ts:99/170`、`workspace.ts:174` | 截图 / 树快照变化 | 重采基线 |
| `ai_float_geometry_native.ts` | H-b 不改 AI；AI 迁移包才影响 | 迁移包里跑 |
| 新增 `e2e/history_tab_native.ts` | 浮动拖动 / 缩放 / 复位、浮动 ↔ 页签切换保留状态、单例、`toolbar.history` 开关、页签序号、页签菜单“浮动显示”、来源标签 | 照 `settings_nav.ts` 的 `launchIsolated` 写 |
| `tools/ui_v4/*.py` | 只引用 `toolbar.history` | 不运行，不改 |

页签形态会让 `tabs.tab.N` 序号后移——默认浮动（Q3）可避免老脚本受影响；新脚本里显式测页签形态。

### 5.3 单元 / 组件测试（新增）

- `catalog_vm` 的 Intent → 状态 / Effect 表测试（筛选、分页、确认、↑↓、Esc 分层、形态切换保留状态）。
- `catalog.yix` 的 headless 组件测试（`kit.headless`）：id 落点、禁用态、空态 / 错误态、`forEachTheme` 下无覆盖。
- `float_panel` 几何与手势测试（由 `float_model` 测试参数化而来）。
- workspace：假 `TabContent` 的打开 / 选中 / 关闭 / 菜单 / ⌘1..9 / 分组拒绝。

---

## 6. 与 100% yix / 原生组件目标的关系

- 正文改 `.yix` 后，history 在 NATIVE_AUDIT 第 308 行列出的 Input、Chip（`history_styles.zig:58`，实为死代码）覆盖随之清零；B3 由“待用户判定”变为“改为 tab content（本方案）”。
- 删除确认 Popover 的 chrome 覆盖（`history_host.zig:152–153`）、状态标签手搓、`ScrollArea` 关回弹、`styleInput`、`setRetainedBackground` 换肤遍历一并清掉。
- 清理记录确认（`record_cleanup_view.zig`，原生 `W.Modal`）由设置包使用，内容控件覆盖“留 P5”——建议归 F-history 波次的单独小包，不放进本方案的 4 个包。
- 浮动面板本身是不是“基础组件”见 H-14，需 lead 判定；判定为 (ii) 时，`float_panel` 只负责几何 / 手势，外观用原生 `W.Card` / Glass 默认，不模仿玻璃。
- 预计清理的护栏基线：`ident:no-inline-style history_host.zig`、`ident:no-widget-internals history_host.zig`、`history_styles.zig`（共 3 条）；cross-feature：`history_host → workspace.zig / session_export / session_export_jobs`、`history_styles → ai_close_confirmation_styles / notification_styles`、`ai_transcript_images / ai_host / command_history_view → history_styles`（后三条需要这三个文件改为从 model 取 `dateLabel`，属对方 feature，记为跟进项）。

---

## 7. 拆包建议

### 7.1 包与文件所有权

| 包 | 泳道 | 文件所有权 | 依赖 | 规模（估） |
|---|---|---|---|---|
| **H-a** 正文 Yix 化（容器不变） | F | `src/features/history/**`（不含 `record_cleanup_*`） | 无（可在第一批后立即开） | Zig −600 / +350，`.yix` +250，`.yss` +120，测试 +300 |
| **H-b** 浮动面板抽取 | F | `src/shared/ui/components/float_panel/**`（新） | H-14 判定 | +500（含测试），AI 不动 |
| **H-c** 工作区非会话页签 | T（触 `src/host/identity.zig`、`src/host/tab_content.zig`、`features/workspace/**`、`features/shell/host/{application_host,menu_host,nav_host}.zig`、`features/workspace/model/context_menus.zig`、`features/transfer/host/transfer_host.zig`、`platform/notifications.zig`、`host/notification_coordinator.zig`、`host/command.zig`） | 与 F-workspace / F-shell 串行（`workspace.zig` 8.7k 行、两包都要拆它） | +400 / −50，测试 +250 |
| **H-d** 接入两种形态 | T（触 `src/app/main_window.zig`、`features/shell/host/chrome_mount.zig`、`menu_host.zig`）+ `features/history/host/**` | H-a、H-b、H-c | +300 / −200，e2e 改写 6 个 + 新增 1 个 |

- **可并行**：H-a 与 H-b（目录不相交）；H-c 可与二者并行开发，但合入时机要避开 F-workspace / F-shell。
- **与 P5 波次的关系**：ARCHITECTURE_PLAN §6.2 把 history 放在波次 A（表单与卡片）、workspace 在波次 C。H-a 就是 F-history 的“分层 + Yix 化”，可以直接顶替 F-history；
  H-c 本质是 workspace 的扩展点，放在 F-workspace（波次 C）**之前**做，F-workspace 拆 `Workspace` 结构体时把 `TabContent` 当作既有门面；反过来放之后则要等很久，且拆分后再加一类页签更容易。
- **建议排期**：第一批合入后，H-a ∥ H-b 并行一轮；随后 H-c 单独占 T 泳道一轮；最后 H-d。AI 迁到 `float_panel` 归 F-ai-pane。

### 7.2 每包的最小门禁（按 COMMON_BRIEF 新规）

`gen-yix`（H-a、H-d）、`check-yix`、`check-arch`、`zig build -j2`、`compile-tests -j2`、本包过滤串的 `test` / `test-ui`（建议过滤串：H-a `history`，H-b `float_panel`，H-c `workspace`，H-d `history`）；e2e 只改写不运行，报告列出受影响脚本（第 5.2 节）。

### 7.3 若 Q1 选 B（停靠窗格）

H-c 不需要；改为在 `float_panel` 里实现 `dock_side = .left` 的停靠形态（island 左侧让位，参照 `nav_host.zig:630–638` 的右侧让位与 `background_layers` slot 5），并把 island 让位逻辑从 `nav_host` 抽成通用的“island 两侧预留”——总规模约为方案 A 的 60%，但仍要处理与 AI 右侧停靠同时存在时的最小会话宽度。

---

## 8. 风险

1. **非会话页签的空指针**：`workspace.zig` 里不少路径对活动页签做 `tab.terminal.?` 或默认它是会话；H-c 必须逐处审计（先例：回放页签 owner 非会话，文件页签无终端），并为假内容页签写选中 / 关闭 / 菜单 / 分组 / 广播 / 传输的组件测试。
2. **与 F-workspace / F-shell 的文件冲突**：H-c / H-d 触 `workspace.zig`、`nav_host.zig`、`menu_host.zig`、`application_host.zig`、`main_window.zig`，必须在 T 泳道串行。
3. **yix 子树改挂**（H-10）未实证；失败时回落为重建 + view-model 恢复，焦点用 `focusId` 恢复，滚动位置要进 view-model（G19 已补的滚动信号）。
4. **作业生命周期**：常驻 Host 下“容器关闭”不再等于“Host 停止轮询”；删除作业的提交、读取作业的取消、`generation` 判定要按 view-model 的 `visible` 重写，否则会出现关闭后仍弹消息或打开记录。
5. **焦点陷阱移除**改变键盘行为（Tab 会离开面板），e2e 与无障碍预期都要改；浮动面板与终端同时可见时，终端的 ⌘ 快捷键与面板输入框的焦点路由需复核（`floating_input.protect` 的用途要先查清再决定是否保留）。
6. **视觉变化**：搜索框、筛选按钮、确认气泡、状态标签回到 zenit 默认，与 Pencil CC3v4 的 28 高搜索框等会有差异——按总则以 zenit 默认为准，截图逐张说明。
7. **e2e 现状脱节**：`global_history_native.ts` 的 480 / 36 断言与源码不符（未实证），改写前需要 lead 在批末先跑一次基线确认它现在是否通过。
8. **H-14 未判定**会卡住 H-b；判定为补上游时，H-b 依赖 zenit 发布周期。
9. **多窗口**：每个窗口一个 Host、各自读写同一个 `logs/history/index.tsv`；一个窗口删除时另一个窗口的目录不会自动刷新（现状如此），常驻形态下更容易被看到——建议 H-d 在显示 / 选中时触发一次 `pending_reload`。
