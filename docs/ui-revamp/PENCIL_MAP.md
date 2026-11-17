# UI revamp：Pencil 设计稿映射

设计稿：Pen 文档 `zeroWork Terminal.pen`（"Island B v3" 系列）。
原则：主布局与窗口 chrome 按设计稿还原；功能面板以 ZeroWork 现有功能为准，设计稿只作视觉与交互参考，不因设计稿删改功能。

## 设计语言

- 基础 token 就是 zenit 默认主题（设计稿变量 `W:zenit.color.*`、`space.*`、`radius.*`、`type.*`、`control.height.*`）。
  ZeroWork 主题应以 zenit 默认 light/dark 为底，只补下面的 zw 扩展 token，不再整份复制后逐字段覆盖。
- ZeroWork 专属 token：

| token | light | dark | 用途 |
|---|---|---|---|
| `zw.island.ground` | app_gray.200 `#EFEFF1` | `#08080B` | 窗口底（岛屿之间的地面） |
| `zw.island.rest` | `#F4F5F8` | `#131317` | 非焦点岛屿/窗格 |
| `zw.island.focus` | `#FFFFFF` | `#1D1D22` | 焦点岛屿（view island） |
| `zw.list.active` | `#FFFFFF` | `#1D1D22` | 侧栏激活行 |
| `zw.strip.bg/fg/fg_muted/segment` | app_gray.800 / `#F6F6F7` / app_gray.500 / `#FFFFFF14` | app_gray.950 / … | 深色状态条 |
| `zw.file.*` | = fg_secondary | | 文件类型图标色 |
| `zw.font.terminal` | = zenit font.mono | | 终端字体 |

## 主窗口骨架（`aPxql` 本地终端 1440×900）

- 根：圆角 18，背景 `zw.island.ground`，横向。
- Sidebar 264：纵向，gap 12，padding [12,8]，透明背景。
  - Sidebar top 28：红绿灯（52×12，位于侧栏内）· 侧栏开关（ghost sm icon 24）· 项目切换器（148×24）。
  - Search 28（Input/default）。
  - 实现差异：设计稿里 Search 常驻；ZeroWork 保留头部"搜索主机"开关（有主机时才显示），打开后在头部下方显示 fill×28、圆角 8 的搜索行（shell/styles.yss `sidebar_search`），关闭时清空过滤并把焦点还给开关。
  - Sections：标题行 24 + 环境列表（行 gap 1；行状态见 `RI5FN/gjAf6/NQngd/rQNox` Project Row normal/hover/press/active）。
  - Sidebar bottom 28：`plus` + "新增环境" + 操作按钮组。
- Content 1176：纵向。
  - View bar 44：padding [0,6,0,12]；Tabs（ZW4 Tab normal/hover/press/active/drag，Tab Overflow）· 新建页签 28×30 · Spacer · 工具按钮组（g8）。
  - Stage：padding [0,6,6,0]；View island 圆角 12，背景 `zw.island.focus`。
- 侧栏收起（`KBJoz`）：Content 占满 1440，红绿灯移入 view bar 左侧。
- 最小窗口 860×480（`o0vX11`）：侧栏隐藏。

现状对照：当前为顶部 36 标题栏 + 30 页签 + 26 状态栏 + 外边距 12 + 卡片圆角 16（`src/features/shell/view/shell_styles.zig`、`src/shared/ui/styles/v3_geometry.zig`），需改为上述结构。

## 画面 → ZeroWork 模块

| 设计稿 | 节点 | ZeroWork 现有模块（待逐项核对） |
|---|---|---|
| 本地终端 / 分屏 / 侧栏收起 | aPxql, Tc5cZ, KBJoz | main.zig 外壳、sidebar_view、workspace / split |
| SSH（浅/深）+ 连接详情浮层 | k6UQlc, lBTBA | 终端视图、status_detail |
| 混合会话组 | UjYQq | 会话组 |
| 新建连接 Stack 1/1a/2/3 | hb6dT, LCs7p, kiUlJ, zp7WE | wizard |
| 连接进度（多跳/失败） | i7VdGA, ybb2B | connection_progress_view |
| AI 执行 询问审批 / 批处理 / PTY | w1mAz5, g0gO7, N9ryVa | ai_host_approval_view 等 |
| AI 助手 | kuRaJ | ai_* |
| Split 1–4 + 交互规范 | yWDDh, N2MYc, s7Mau, gOViF, f2GULK | 分屏/卡片 |
| SFTP 列表/分栏/快速查看/多选右键/拖放上传/传输弹层/同名冲突/位置下拉/规范 | c0vKlM, s5BIc, Gwaz8, OQD5Y, O52ucD, Gq5xg, R028P, S0ImAK, aeI5n | file_workspace_view、transfer_* |
| 传输窗口 任务列表/空状态 | R3LCmV, VlICC | transfer_manager_view |
| 只读历史 | CC3v4 | 历史视图 |
| 远程 BMC iKVM | TcJSa | plugins/bmc_ikvm |
| 空状态 | hmCmB | 空工作区 |
| 设置窗口：外观与主题/快捷键/SSH 与网络/文件传输/AI 辅助/协议插件/通知/数据与日志/关于与更新/更新确认 | p6ZVS, SxSpD, lVMiW, ClNai, M9sJf, T5k96, wrTdG, L28sw, Vbefc, irIDr | config/settings_* |
| 公共组件规范：输入与校验/选择与下拉/按钮与开关/主机 OS 图标/对话框与浮层/工具栏与提示/状态与容器/列表与导航/进度与异步/通知与追溯 | PLHqT, baIJG, G7OSX, Q0nyv0, mPB7g, QJ8N7, zPQAS, Z1SX6, M4eWZ, kx2nq | 共用组件，优先用 zenit widgets |
| Tab 栏交互规范 | SHfTh | 页签栏 |
| 环境行状态 | F0U1j | 侧栏行 |

可复用组件：`JrTg7` Sidebar · `qmwXi` View Tools · `D8dPB` Window Chrome · `EHLGD` Save Bar · `zs86y` AI Composer · `Bt1FV` Settings Nav · `Che9A/GW9no/tVVKV/PLfO1` Files Row/Header/Toolbar/Location Menu · `quc7S/oi6f6/H3SQK` Card Type · `QGtx5` Pane Header · `X8B7E` Tab active · `T04Ei` 主机 OS 图标。

## 实现方式（用户指定）

- 新 UI 用 **Yix + Yss** 编写：`.yix` 写结构/状态/事件，`.yss` 写样式/recipe/slots；生成的 `_x.yix.zig` / `_styles.yss.zig` 双胞胎与源文件一起提交，不手改。
- 构建：ZeroWork `build.zig` 通过 `zenit_dep.artifact("yix")` 建 `gen-yix` / `check-yix` 步骤（扫描 `src` 与 `tools/mockups`），应用编译依赖 check。
- 主题：ZeroWork 主题 JSON 经 zenit `generateTheme` + `attachWithOptions(.theme_provider)` 绑定，内容 = zenit 默认 light/dark + `zw.*` 扩展 token；yss 直接引用 token 名。运行期不再整份复制主题逐字段覆盖。
- 组件优先用 `ui.widgets`，必要的 ZeroWork 定制走 zenit 扩展点（见 vendor/zenit.lock.json 对应的 feat/app-extension-points）。

## 实现差异 · AI 助手 / AI 执行 / BMC iKVM（rv-ai）

- AI 助手面板（kuRaJ/w1mAz5/g0gO7/N9ryVa）：默认是 view island 内右侧的分栏 Pane（src/features/ai/pane/view/ai_pane_layout.zig）：宽 500（可拖动 4pt 分隔条调整，最小 340，会话窗格至少保留 320）、island 内边距/间距 4、圆角 8；会话窗格让出该列（island padding-right = 宽度 + 8）。焦点/非焦点 plate 由 background_layers 槽位 5（bindAiPane）绘制：焦点 = focus 面 + accent 1pt 描边，非焦点 = rest 面。头部用 QGtx5（30 高、padding [0,4,0,12]、图标 14、标题 12/600、附着信息 11 在 spacer 右侧、24 按钮）。打开/关闭、钉住、快捷键、会话切换不变；原浮动窗口作为第二种模式保留（头部「浮动显示 / 停靠到右侧分栏」按钮切换），浮动模式下才显示放大按钮与拖拽/缩放手柄。停靠时不响应 strip 悬停预览（避免悬停导致会话窗格反复重排），点击 strip / 工具栏仍打开。单会话（无分组）时会话窗格内缩 4、圆角 8，由 background_layers 的 session plate 绘制焦点/非焦点（AI 有焦点 = rest 面；焦点回到终端 = focus 面 + accent 描边），终端内容背景透明露出 plate；分组时沿用分组窗格 plate。
- 审批（w1mAz5 Approval）：设计稿把审批卡放在消息流里；ZeroWork 的命令审批在 Composer 内展开（ai_composer_interaction_view，保留"稍后处理"与待办胶囊），本机审批卡（ai_host_approval_view）在消息流中。两处都采用设计的三段式运行方式 Tabs（32 轨道 / 28 段 / 圆角 8·6）、⚠ 标题 12.5/600、主按钮 accent；Composer 内按钮按设计 32 高，在 28pt 控制行中居中（上下各借 2pt 间距/内边距，不裁切）。本机旧版命令审批卡（ai_tool_approval_view，固定 167.625 高度契约）按钮仍为 26.5。运行方式文案保留 ZeroWork 原有"批处理 / 当前终端 / 新工作终端"。
- 步骤（kuRaJ Step）：改为 24 高平铺行（无卡片底、无圆点分隔：图标 · 标题 12/600 · 摘要 11 · 耗时 mono 11）；点击行仍展开详情，详情为 Evidence 样式的 well（圆角 7、padding [6,10]）。步骤组（多步折叠头）保留原分组外观。
- Composer（zs86y）：去掉内嵌卡片底色，改为顶部 1pt 分隔线、无底色选择器、Send 改 ghost；保留 90pt 两行编辑区与权限/执行方式图标（hand/shield-check、terminal 表示状态），设计稿只有文字。Composer 纵向 padding 仍为 6/6（设计 10/8），避免改动审批展开高度契约。
- 用户气泡：由渐变改为设计的浅 accent 平涂（accent 12%）+ 圆角 10；文字保留 11.5→12 号。
- 回合脚注（Turn footer）：保留模型品牌 logo（14），设计为 sparkles/hand 图标。
- 批处理结果（g0gO7）：操作按钮改为设计的无底色 accent 文字按钮（12），墨色经 patchInk 保证在执行卡上对比度 ≥ 4.5（button_policy_tests 同步）。
- PTY 运行中"AI 控制中 · 只读"条（N9ryVa QT5FH）属于 terminal_surface，由 rv-shell 还原（见下节）。
- BMC iKVM（TcJSa）：工具栏改为 40 高、贴在 island 上（无浮动卡/阴影），菜单按钮 76×28（图标 14 + 文本 12 + chevron 11），视频紧贴工具栏下方（无 16 间距、无独立圆角，由 island 圆角裁剪）；连接状态仍是可点击断开的按钮（✓ 已连接 / hover 断开），设计稿为状态点 + "已连接 · 8 FPS" 文字。FPS 浮层保留右上角与深色底（设计在右下、白 10% 底）：右下与输入提示条重叠，且白 10% 底在亮画面上可读性不足。电源等菜单保留现有 296 面板（含标题/关闭），设计稿为 200 宽简单菜单。

## 实现差异 · 终端主界面细节（rv-shell）

- Tab 栏（SHfTh）：normal / hover / press / active / drag 五态按规范实现（normal 隐藏关闭、hover 胶囊 bg_hover + 文字 fg_primary、press bg_active、拖动时页签抬起为 island 底色卡片 + 1pt 边框 + 0/12/32 阴影）。类型图标保留 ZeroWork 主机 OS 图标与连接状态点（设计为 square-terminal + fg_tertiary/accent）；关闭按钮 80ms 淡入未做。溢出控件（n2sBDu）为 chevron-down + 页签总数，左右滚动箭头保留。
- 新建页签按钮：图标 14，点击仍打开 ZeroWork 的新建会话菜单（设计为直接新建终端，右键开菜单）。
- 分屏卡片（Tc5cZ）：Pane Header 加类型图标（焦点 accent / 其余 fg_secondary）、标题 12（焦点 600 fg_primary / 其余 500 fg_secondary）、状态点、spacer、右侧 meta 11；保留拖动手柄（设计中 Grip 关闭）、"标题 · #id" 文本、广播按钮与成员菜单。meta 按设计显示「路径 · 列 × 行」：路径来自 shell 的 OSC 7 上报（本地经 ApplicationHost 的进程服务、SSH 经 runtime），主目录缩写为 ~，未上报时只显示尺寸；连接未在线时仍显示连接状态文本。每 500ms 原地刷新，不重建分组。
- 空状态（hmCmB）：按设计 mascot 88 · 文案（18/600 + 13 fg_secondary，gap 6）· 按钮（md 32 高、圆角 6、图标 16、13/500）· 「已保存的连接」，gap 20。列表取自主机注册表，最多 3 条，先按本次运行的最近连接（RecentList，仅内存）再按注册表顺序；行复用 ZW4 Project Row（28 高、hover/press 色），点击与侧栏行「连接」同一路径（newSession）；无主机时隐藏。设计中的「⌘K」提示未加（ZeroWork 快速连接无 ⌘K 绑定）。主按钮保留 ZeroWork 的渐变主色（全局 stylePrimary），文案保留 ZeroWork 现有文本。
- 侧栏收起（KBJoz / D8dPB）：恢复按钮改为红绿灯后 6pt 的 24 ghost 图标按钮（不再是浮动胶囊）；最小窗口（o0vX11）工具溢出"…"同样改为平铺 ghost 按钮。ZeroWork 工具按钮多于设计（传输、AI、历史、设置等），最小窗口下继续收进"…"。
- 连接详情浮层（lBTBA）：宽 320、padding 12、圆角 10、1pt 边框、阴影 0/8/24、标题 13/600；保留 ZeroWork 的摘要与事实行。新增「连接链路」芯片（本机 › 跳板 › 目标，22 高、目标为 accent 底），文本「路径」行保留给复制/无障碍但隐藏；新增「端口转发」行（SOCKS 后端实时 phase，运行时显示「SOCKS5 · 127.0.0.1:端口」，开关打开现有 SOCKS 面板）和「输入广播」行（仅分组成员显示，开关走现有成员广播切换）。设计中的「本会话传输」行未加（浮层拿不到会话级传输状态）。浮层高度上限 300 → 420。
- 只读历史（CC3v4）：时间戳列 9.5 号、与正文间距 8。会话记录（PL4b，history-card）：目录与回放合成一张 `history` 卡片（设计稿「ZW · 会话记录卡片补稿 2026-11-13（PL4b）」稿 A / B / C，CC3v4 里“停靠在 view island 左侧”的目录即卡片内部的列表栏）：头部 36（history 图标 · 12/500 标题 · 11 条数，浮动时右侧“作为 tab 打开 / 关闭”）· 原生 Divider · 左列表 320 ｜ 竖向 Divider ｜ 右详情（标题 · 元信息 · 状态 Tag，回放表面，回放条在详情底部）；列表与回放同时常驻，原“目录是模态窗格、打开记录时关闭”的保留差异已消除。浮动默认约 820 × 600、最小 360 × 320，宽度 < 600 时列表 / 详情二选一（详情头“返回”）。记录行保留状态标签与查看/导出/删除操作，56 高两行（设计 46）；回放条保留现有「标题 · 轨道 · 位置」，设计中的播放/上一标记/倍速/复制选区控件 ZeroWork 没有对应能力，未伪造。
- AI 控制中 · 只读（N9ryVa QT5FH，terminal_surface）：由右下角浮动胶囊改为贯穿窗格底部的 40 高条（顶部 1pt 分隔线、padding [0,12]、gap 8）：sparkles 14 · 「AI 控制中 · 只读」12/500 accent · 「你的输入不会发送到这个终端」11.5 fg_secondary · spacer · 「接管」（secondary，24 高、padding [0,12]、圆角 6、13/500）。条以覆盖层方式绘制，接管控制时不改变终端网格尺寸；接管行为不变。

## 实现差异 · 页签与窗格头（rv-tabs：gtZi3 / nCMeb / ZW4 Tab / tOrT3）

- 页签状态与关闭逻辑按用户要求参照 zeditor file tab：关闭按钮只在指针悬停于页签（含 2pt 侧边与非活动页签下方 3pt 的整格）或键盘焦点在页签内时显示，**活动页签静止时也隐藏**（设计 I1ajLU 活动态画的是可见关闭按钮）；隐藏时 opacity 0 且保留 16pt 槽位，标题宽度不因关闭按钮出现而变化。标题按 600 字重测宽，激活后不截断。
- 页签格之间无间距（hvc0K gap 0），surface 在格内左右各缩进 2（ZW4 / Tab padding [0,2,3,2]），关闭按钮距格右缘 6、距 surface 右缘 4。
- 活动页签悬停与按下不改变底色（仍是 island）；按下底色只用于非活动页签。
- 关闭活动页签后激活最近使用（MRU）的页签，没有使用记录时取左侧相邻页签（原规则为右侧优先）。关闭非活动页签不改变当前页签；点击关闭按钮不会激活该页签；中键在按下时关闭。
- 悬停提示：每个页签只出一个。非活动页签显示合并去重后的提示（名称 · 连接详情 · 状态，500ms）；活动页签的提示就是「会话连接」卡片，触发区从图标扩大到整个页签，延迟 500ms，在页签上按下鼠标后关闭，直到指针离开再进入。卡片里的名称是连接名称，不显示用户改过的页签名。
- zeditor 中这些能力 ZeroWork 没有对应功能，未实现：dirty 圆点、固定页签、Cmd+Shift+T 恢复已关闭页签、页签获得焦点时用 ←/→ 切换。页签获得焦点时 Enter/Space 激活已实现。
- 新建页签「+」（nCMeb）：24 ghost 按钮，圆角 6，plus 14 fg_secondary，hover/press 使用状态色；距最后一个页签 4，底边距 island 6。点击行为不变，仍打开新建会话菜单。
- 单会话 Pane Header（tOrT3）：未分组的终端会话在 island 顶部显示，与分组窗格使用同一个 `mountPaneHeader` 组件。内容依次为类型图标、标题 12/500、状态点、meta「路径 · 列 × 行」（复用 rv-shell 的 paneMeta）、More。没有 Grip（设计中为 disabled）。Pin 不显示：ZeroWork 的置顶只有「组内置顶」，没有单会话的固定语义。More 菜单包含：向右分屏 / 向下分屏（与 ⌘D / ⇧⌘D 相同的 splitGroup 路径）、关闭会话。单会话没有广播功能，因此菜单里没有广播项。
- 分组窗格头：保留 grip、广播按钮、置顶按钮。More 菜单统一为：向右分屏 / 向下分屏、开启或关闭广播、全部改为左右或上下排列、移出组保留会话、断开并关闭会话。原菜单里的「新建左右/上下分栏」改名为「向右/向下分屏」，e2e/workspace_v3_semantics_native.ts 已同步。设计中的「广播中」胶囊未加，广播状态继续由广播按钮的着色表示。

## SFTP 文件工作区 / 传输（rv-sftp）实现差异

- 列表视图 `c0vKlM`：结构样式在 `src/features/files/view/styles.yss`。窗格岛内 padding 4 / gap 4，窗格圆角 8 + bg-active 描边；Pane Header 30、Files Toolbar 44、表头 26、行 26（内缩 6、圆角 6）、路径栏 28。
- 保留 ZeroWork 的"上级目录"按钮（设计稿是"前进"，ZeroWork 没有前进历史）；保留每行复选框与全选列。
- 列只有 名称 / 大小 / 修改时间，宽度沿用按内容分配的算法（设计稿是固定的 日期 124 / 大小 68 / 种类 / 权限 列，ZeroWork 没有种类和权限数据，也没有树形展开箭头）。表头内容与行内容对齐在 16（设计稿表头 padding 是 10）。
- Location 按钮（文件夹图标 + 当前目录名 + ▾）打开的是 ZeroWork 现有的"路径历史"菜单，不是设计稿 `PLfO1` 的 位置/个人收藏/服务器 分区；菜单行、标题和内边距沿用 `PLfO1` 的数值，宽度保留 340，以便显示较长的远程路径。
- 路径栏里的面包屑仍可点击跳转，点击空白处可编辑路径；读取失败时路径栏保留，只隐藏状态文字，错误框插在表格和路径栏之间。
- 视图切换（列表/分栏/图标）、快速查看 `Gwaz8`、分栏 `s5BIc`、Inspector、"可用空间"统计：ZeroWork 没有这些功能，未新增。
- 右键菜单 `OQD5Y`：只保留 ZeroWork 现有的 4 个动作，"复制完整路径"后加一条分隔线。
- 同名冲突 `R028P`：480 宽、圆角 12、padding 20、标题 15/600、32pt 按钮。新增"上传的文件 / 服务器上的文件"（下载时是"下载的文件 / 本地已有的文件"）对比卡片，内容是 名称 · 目录、修改时间、大小，修改时间较新的一侧显示"较新"徽标；拿不到的字段显示"—"。
  - 和设计稿不同的地方：保留 ZeroWork 的单选 + 应用流程（覆盖仍要二次确认），没有改成 跳过 / 保留两者 / 替换 直达按钮；标题行仍是"同名文件处理"，文件名放在说明行。
  - 为了在 860×480 最小窗口里不出现滚动：卡片 padding 10、gap 6（设计 12 / 8），KV 行 20 高（设计 22），图标 24（设计 28），选项行 32 高。
  - "另存为"步骤需要输入框的空间，这一步不显示卡片，改回一行"来源 → 现有目标"摘要和目标路径。
- 传输窗口 `R3LCmV`：任务改成 48pt 表格行（圆角 6，padding [0,10]，gap 12）。表头 26 高带底线，列为 文件（24 图标 + 文件名 12.5/500 + "上传到 / 下载到 目录"）· 连接（会话名 12 + 路由 11，没有路由时显示"—"；宽度从 148 起，按会话名长度伸缩）· 进度 168（传输中显示字节数，其余状态显示阶段文字，下面是 4pt 进度条）· 速度 84（速率 + "剩余约 Ns"，没有数据时显示"—"，失败时显示红色错误）· 操作。
  - 设计稿的"环境"字段 ZeroWork 没有，用传输路由代替。
  - 操作列保留全部 4 个按钮（主操作、复制路径、事件、取消），宽 102（设计稿 50，只有两个按钮）。
  - 行背景透明，只有选中时上色；行没有悬停底色（ZeroWork 的任务行不是按钮）。
  - 窗口顶部的计数徽标、搜索、筛选、批量操作没有改成设计稿的分段过滤器 + 全部暂停 / 清除已结束。
- 传输弹层 `Gq5xg`（全局弹层、会话弹层、SFTP 托盘）：任务改成 54pt 行（padding [7,8]，gap 10）。24 图标 + 文件名 12.5/500；下面一行是 字节数 · 速率 · 状态（11）；再下面是 4pt 进度条；右边是操作按钮。全局弹层在文件名行末显示会话名。弹层的标题栏和底栏（"清除已完成 / 全部传输"）沿用 ZeroWork 现有的。
- 传输空状态 `VlICC`：arrow-down-up 28 图标 + 13/600 标题，没有新增描述文字。
- 拖放上传 `O52ucD`：拖拽跟随框改成设计稿的样子：两个文件图标叠放（40 / 42）、强调色 20pt 数量圆标，下面是深色提示框（padding [6,8]，圆角 6）"上传 N 项到 <目录>"。投放目标行用 accent-subtle 底色 + 1px 强调色描边（圆角 6），目标窗格描边换成 accent-border。ZeroWork 原有的窗格底部"松开上传"信息卡保留。

## 实现差异 · 新建连接 / 连接进度（rv-wizard）

- 新建连接（hb6dT / LCs7p / kiUlJ / zp7WE）是主窗口拥有的独立原生窗口（`src/shared/ui/window/aux_window.zig` + `Wizard.attachWindow`）：720×640（最小 600×420），44 自绘标题栏、红绿灯中心 (20,22)、Stage [0,6,6,6] → View island r12 p4 → Pane r8 accent_border；Body [20,28,0,28]，Footer 56 顶部 bg_active 发丝线 + 「下一步：…」提示。重复打开只激活；关闭/Esc = 取消；保存后回传主窗口并关窗；随主窗口关闭。
  - 窗口高度固定 640、内容滚动（未按每屏自适应窗口高度：每屏高度取决于展开态与跳板数，且需要运行时改窗口尺寸，收益低）。
  - 保留可点击的三步步骤条（40 高、发丝线连接），设计稿是标题栏后退/前进 + 步骤点；标题栏保留协议选择与插件图标。
  - Stack 1 的「协议 + 地址」合并输入（粘贴 ssh 命令自动拆分）未做；保留标签在上、两列等宽字段（取 LCs7p：标签 12/15、间距 6、控件 32、列距 16）。
  - 认证方式、SSH 传输压缩：RadioGroup 的语义/键盘/测试 id 不变，呈现为 Tabs/segmented（bg_active 轨道 r8 p2、28 段 r6、选中段抬起）。
  - 高级选项（Stack 1a）为页内展开，入口行按 b7EPH（标题 + 摘要 + chevron，顶部发丝线）。
  - Stack 2：跳板行 52 高、zw.island.rest r8、序号徽标 bg_active；行内操作为无边框图标按钮（上移/下移/删除 trash-2）。ZeroWork 没有拖动排序，未加 grip；没有单独的「编辑跳板」功能，跳板通过行内选择框更换。直连/跳板两张选择卡保留。
  - Stack 3：保留身份卡与两列字段；新增「连接与认证 / 连接路径 / 高级选项」返回行（复用步骤导航，高级选项会展开并聚焦主机密钥策略）；路径卡改为横向逐跳链（9 点 · 名称 12.5/500 · meta 11 · 发丝线连接）。
- 连接进度（i7VdGA / ybb2B）不再是模态：卡片挂在窗口 portal，由 connection_host 对齐到发起连接的会话页签内容区（另一个页签激活时隐藏、连接仍保持打开），无遮罩、无焦点陷阱；卡片 580 宽居中、无卡片底。Status 20/600（失败为 danger）+ 13 描述；路径标题 24；跳点行 44（22 圆底标记 + 13 图标：完成 check / 当前 loader / 失败 x / 等待 circle-dashed，名称 13/500 叠地址 11 mono，状态 12 右侧）；跳点之间 10 高连线；日志井 zw.island.rest r8 [8,10]；操作按钮 32。
  - 保留顶部身份行（主机名 13/600 · endpoint · 状态徽标 · 关闭），设计稿没有（页签已显示主机名）；保留取消/重试/关闭/复制诊断/日志跟随等全部操作。设计中的「编辑连接」按钮 ZeroWork 进度视图没有对应回调，未加。
  - Esc：认证表单内由表单自己处理（先结束输入法组合再取消请求），卡片其余位置 Esc 等同关闭/取消；显示时焦点移到卡片。进度显示期间不再屏蔽全局快捷键（只有认证挑战会屏蔽）。

## 实现差异 · 设置窗口（rv-settings 第二版：p6ZVS, SxSpD, lVMiW, ClNai, z6LzX, X58OgN, fKIHi, M9sJf, T5k96, M4yFIw, mTcWN, Xe0mv, GV8pb, e2ys05, ibeKI, KUKQ5, wrTdG, GcXZO, g94EBU, hOk58, P98ZbT, ISt3k, O7gUj, L28sw, YDddt, kj0Da, IOvS7, Vbefc, MVxZ3, dM7oF）

- 窗口 960×780（最小 760×480），白色窗面，padding [8,0,8,8]；红绿灯中心 (28,32)，拖动带 46。
- Settings Nav（`Bt1FV`）：216 宽悬浮侧栏，圆角 14、padding [10,8]、阴影 0/5/18；选中分类为应用强调色底 + 对比前景（深色主题自动用深色字）；搜索为胶囊（bg-active）；底部「配置与凭据保留在本机」。设计稿的玻璃 shader 以不透明 rest 面近似。
- 页头（`zCQxN`）：Glass Nav 返回/前进（34×30，不可用时 35%）+ 标题 15/600 + 帮助（36 圆）。历史记录分类与子页面的每一步；搜索中按返回只退出搜索。
  - 第 2 轮验收（用户：页头要学 znote 画板详情页 chrome 上的 header）：页头浮在内容上（高 64、中线与红绿灯同高），正文从它底下滚过、原生 scroll edge 渐进磨砂（znote `progressiveBlurEdge` 的数值）；标题改为 znote 的两行身份块（上一级 12.5 › 标题 13/600，下一行分类说明 10.5），取代 `oJtXe` 的 15/600；按钮仍是原生 `W.GlassToolbarGroup`（36pt，不照 znote 手搓的 40pt 磨砂胶囊）。
- 两级导航：外观与主题 / SSH 与网络 / 文件传输 / AI 辅助 / 通知 / 数据与日志先进入概览（Hero 56 图标 + 20/700 标题 + 12.5 说明；列表行 30 图标 + 标题 13 + 实时摘要 11.5 + chevron），点进子页面只显示对应面板。映射表在 `src/features/settings/view/settings_subpages.zig`（每个设置键恰属一个子页面，有单测）；校验错误跳到所在子页面。快捷键 / 关于与更新仍为单页。协议插件（F-set-plugins，人工验收反馈第 10 条）是两级：列表页 `T5k96`（按来源分组，每个已注册插件一行：30 图标底 + 名称 13 + 说明 11.5 + 版本尾注 + chevron，行间发丝线）→ 该插件的详情页 `KUKQ5`（头部卡片 40 图标底 + 名称 15/600 + 说明 + 原生 `W.Tag` 来源；插件信息：版本、权限 + 原生“?”提示；插件自带的偏好字段）；子页是运行时数据（`Location.sub` = 注册表下标，`settings_history.isDynamic`），后退 / 前进、搜索、滚动沿用两级导航机制。
- 随应用插件的启用开关（plugin-disable，PLUGIN_ARCH_PLAN 6.2.1 Q5；定稿 XqqLV 稿 2：Jm2fZ / SH1gb / NHr2L / B0QXg6 / DzPbO / IeCzY / UuE31 / gTZVO / qQaos / RfJyL / YWqSG / Pzzo6）：详情页在概要卡片下加“状态”分组（标题 + “重启后生效”，一行原生 `W.Switch`，只给随应用提供的插件）；改了未保存沿用保存栏；待重启是原生 warning `W.Alert`（动作行“立即重启”）+ 头部卡片 warning `W.Tag`“重启后停用 / 启用”；已禁用是原生 info `W.Alert` + 中性 `W.Tag`“已禁用”。列表行被禁用时图标 / 标题降为次要色、尾注换成 `W.Tag`。侧栏被禁用协议的主机：图标淡、名称三级墨色、行尾“已禁用”+ 原生 `W.Tooltip`；右键“新标签连接”等连接项置灰并标“已禁用”。向导协议下拉里是原生禁用选项“{名称} · 已禁用”。与定稿的差异：① 代码里还没有能力列表（“支持的能力 / 不支持”属 PL2 能力目录，未做），所以“已禁用时能力列表变淡”没有对象，详情页仍是“插件信息”与偏好设置；② 已禁用提示不写主机台数（设置窗口拿不到主机表，不编造数字）；③ 编辑已禁用插件的主机时向导只给名称一栏（插件没有初始化，协议编辑器不可用；分组用右键“移动到分组”），而 YWqSG 说明稿写的是“可改可存”；④ 下拉的禁用选项没有悬停 Tooltip（`SelectOption` 不带提示），原因写在选项文字里。
- 面板（`v8NDZM`）：22 高标题行（标题 12/600、右侧 meta 11）在卡片外，卡片 rest 面、圆角 12、padding [0,14]，面板间距 20；面板不再折叠（设计无折叠）。
- Save Bar（`EHLGD`）：右下悬浮胶囊（44 高，距右 12、下 14）：✓ 所有更改已保存 / 未保存 · 恢复默认… · 撤销更改 · 保存更改；概览页在草稿干净时隐藏。
- 与设计的差异（保留 ZeroWork 现有功能，不虚构）：子页面内容仍是 ZeroWork 现有设置项，设计稿中 ZeroWork 没有的项（保活失败次数、主机密钥默认策略、选中即复制、保留文件权限、通知矩阵、配置同步、导出连接配置等）未加；AI 增加第三个子页面「技能与 MCP」；AI 服务提供方仍为列表 + 详情的主从布局（未拆成 GV8pb→O7gUj 两级）；协议插件已改两级（上条；原“保持主从布局”的偏差作废），但能力对照表（`ibeKI`）、详情页的“支持的能力 / 不支持”两组与列表行的“N 项能力”尾注未做——清单不声明能力（PL1 推导），行尾显示真实版本号；列表的“计划中”分组已按 6.2.1 Q1 做出（plugin-truth）：只列路线条目（`host/plugin_roadmap.zig`，目前只有“网页连接 · 0.5 版本待实施”），说明文字取自清单的 `summary`；设计稿“随应用提供”里的 Ansible 代码里没有，不显示；主题卡仍为可横向滚动的全部主题；设计稿的主题库（搜索 / 筛选 / 收藏）不实现（用户 2026-11-13 判定：以代码功能为准，旧实现里没有入口的主题库死代码已在 set-adopt 删除）。
- 组件测试与预览 runner 默认整类渲染（`Controller.drill_down = false`），偏好设置窗口启用钻取。验收脚本：`e2e/settings_revamp_native.ts`。

- F-set-ai（人工验收反馈 10）：AI 辅助 › 服务提供方按 `GV8pb`（Content `lxZqv`）改两级——列表页（行：头像 + 名称 13 / 摘要 11.5 + 默认徽标 / 未启用 + chevron，padding [9, 0]，行间发丝线；列表下右对齐“添加服务提供方…”）→ 点一行进入提供方详情（第三级，设计稿没有详情页，布局沿用设置面板：连接 / 模型两个面板 + 删除）。行为与权限按 `e2ys05` 的单卡行样式做成普通设置行，但保留旧实现的七个面板分组与页头（设计稿把它们压成一张卡、只留六行；功能以现有为准，见 F-set-ai 汇报的差异说明）。原“保持 master / detail”的偏差作废。
