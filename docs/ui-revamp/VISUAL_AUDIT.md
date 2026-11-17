# ZeroWork 视觉与 UI/UX 审查（2026-11-12）

分支 `revamp/visual-audit`（基于 `feat/ui-arch-revamp` @ `8f070845`），本轮只审查，不改产品代码。

## 1. 方法

1. **采集**：`e2e/visual_audit_capture.ts`，走 zenit 文件 RPC（`vendor/zenit/e2e/client.ts`），设置 `ZENIT_E2E_BACKGROUND=1`、`ZENIT_E2E_ISOLATE_POINTER=1`。全部通过 `zw-nonet.sh` 在断网沙箱里运行。每次运行都用临时的 `ZEROWORK_DATA_DIR`，并写入 `[updates] auto_check=false`。已保存连接全部指向 `127.0.0.1:65530`（无监听，连接立即被拒）。
   - 场景：`empty`（无已保存连接）、`wizard`（向导是独立原生窗口，关闭后 Harness 不会回绑主窗口，所以单独起一个进程）、`populated`（4 个已保存连接和 1 个资产分组）、`auth`（`auth-challenge-preview` 夹具）、`files`（`file-workspace-preview` 夹具）、`transfer`（`transfer-events-preview` 夹具）。
   - 每个场景都跑 light/dark × 1440×900/最小窗口（主程序 860×480；文件夹具沿用其 e2e 的 1194×794/790×374）。
   - 产物在 `~/work/ZeroWork-evidence/visual-audit/`，文件名为 `<theme>-<wide|min>-<screen>.png`（2x Retina）。`manifest.json` 记录每张图对应的界面和状态，以及采不到的界面和原因。
2. **审查**：24 批，每批 6–10 张同一功能区的图，light/dark 成对送入 `codex exec -m gpt-6.1-terra -s read-only --ephemeral`。提示词见 `codex/context.txt` 和 `codex/prompts/*.txt`，输出 schema 见 `codex/schema.json`，原始输出见 `codex/b*.json`。
3. **核实**：Codex 的每条结论都当作未验证。按结论裁剪截图逐条核对，必要时读源码（下文「源码」一栏），然后合并重复项。误报、审美偏好、夹具伪影一律否决，并写明理由。

## 2. 覆盖面

- 采集到 **280 张截图，覆盖 70 个界面/状态**（同一界面在 2 主题 × 2 尺寸下分别计张）。送审 **163 张，24 批**。
- Codex 共给出 **82 条**结论。核实后**否决 8 条**；其余 74 条**合并为 34 项确认问题**。核实过程中另外发现 **3 项**，单独标注「核实中发现」。合计 37 项（V-01–V-37）：P1 8 项、P2 16 项、P3 13 项，无确认的 P0。

| 功能区 | 已采集的界面/状态 |
|---|---|
| 工作区 | 空工作区（侧栏展开/⌘B 收起）、工具栏悬停、「新建会话」菜单、带已保存连接的空工作区、最小窗口 |
| 侧栏 | 分组 + 主机列表、主机行悬停与提示、主机右键菜单、分组菜单 |
| 新建连接向导 | 第 1 步空白 / 失焦校验错误 / 私钥路径错误 / 高级选项展开；第 2 步直连 / 点「跳板」；第 3 步核对（未执行测试） |
| 快速连接 | ⌘K 空态、输入 `user@host:port` |
| 连接 | 已保存 SSH 拒连后的重试进度视图、关闭进度视图后的状态 |
| 终端 | 单会话（含侧栏）、⌘F 搜索有匹配/无匹配、中键菜单、`@` 本地指令面板 |
| 页签/分组 | 多页签、页签悬停提示、页签右键菜单、⌘D 分屏组（左右 / 上下）、成员菜单、分组页签菜单、最小窗口页签 |
| AI 助手 | 未配置 provider 的空态、Composer 已输入、模型/权限/执行方式菜单（宽与最小窗口） |
| 通知 / 记录 / 传输 | 通知中心空态、会话记录面板、传输面板空态；传输夹具：任务详情、事件弹层 |
| 文件工作区（夹具） | 正常两栏、远端空目录、远端读取失败 |
| 认证对话框（夹具） | 密码（空/已输入）、私钥口令、keyboard-interactive、未知主机密钥、主机密钥已变更 |
| 设置窗口 | 6 个分类总览页、主题 / SSH 连接 / AI 服务提供方 / AI 行为与权限子页、快捷键、协议插件、关于与更新、搜索有结果/无结果、子页未保存、未保存时回到总览 |

**未覆盖**（详见 `manifest.json` 的 `not_captured`）：

- 依赖网络或远端：真实 SSH 登录后的会话、SFTP 文件工作区接入主程序、真实传输、AI 对话/审批/子任务/附件（需要 provider）、BMC/iKVM（本轮没有构建 `bmc-kvm-preview`）、会话回放（需要已结束且有记录的会话）。
- 脚本未到达：通知 toast（拒连重试期间不产生通知）、状态条主题弹层（`local.status.theme` 触发器在 Harness 下没出现）、10 页签溢出与「全部页签」选择器（打开 AI 面板后 `newLocal` 超时）、会话记录行悬停（没有记录）。
- 不存在：全局命令面板，用终端 `@` 本地指令面板代替。
- **暗色认证对话框**：夹具在 dark 下整窗背景仍是浅色（夹具自身的标题和按钮也一样），无法据此判断产品暗色表现。见「否决」R1 和「阻塞」。

## 3. 确认的问题（按严重度）

范围：**DS** 表示样式 token / 共享组件层，**F** 表示单个功能。截图路径都相对 `ZeroWork-evidence/visual-audit/`。

### P1

**V-01 禁用态主按钮标签几乎不可读，且各处实现不一致** · DS
- 截图：`light-wide-auth-password.png`（底部右侧「认证并继续」）、`dark-wide-wizard-identity-pristine.png`（右下「下一步」）、`light-wide-wizard-identity-key-error.png`、`light-min-quick-connect-empty.png`（「连接所选主机」）
- 问题：认证对话框把 `fg_3` 灰字直接放在满饱和 accent 底上；向导和快速连接是浅紫底 + 白字（暗色下是暗紫底 + 黑字）。三处禁用态各不相同，文字都接近背景色。
- 建议：在共享 Button 的 `:disabled` 统一一套禁用配色（降低底色饱和度，同时保证标签对比度 ≥3:1），删除各功能自定义的 disabled 颜色。
- 源码：`src/features/connections/auth/view/auth_challenge_styles.zig:116-118`（`actionColor` disabled→`fg_3`）、`src/plugins/remote/editor.zig:841`、`src/features/connections/quick_connect/view/quick_connect_view.zig:399`、`vendor/zenit/src/ui/components/button/styles.yss`

**V-02 终端命令结果徽标「EXIT 0 7 ms」盖住命令文字** · F（终端）
- 截图：`light-min-terminal-single.png`、`dark-min-terminal-single.png`（第 2 行行尾 `head -12` 的 `12` 被盖住）
- 问题：徽标叠在终端网格上，窄宽度时直接遮住命令内容。
- 建议：行尾空间不够时把徽标移到 gutter 或下一行，或者只显示一个状态点、悬停再展开。终端网格内容任何时候都不能被遮挡。
- 源码：`src/features/terminal/view/terminal_surface.zig:888`、`src/features/terminal/view/terminal_view.zig:5329`

**V-03 连接失败的重试视图不显示失败原因** · F（连接进度）
- 截图：`light-wide-connection-failed.png`、`dark-wide-connection-failed.png`
- 问题：只显示「正在准备重试连接 / 上次连接未完成 / 第 2 次尝试」，目标主机状态写「已释放」。拒连（ECONNREFUSED）这一关键原因要展开「查看连接日志」才能看到；「已释放」对用户也没有意义。
- 建议：在标题下用一行显示上一轮失败原因（如「127.0.0.1:65530 拒绝连接」），并给出「立即重试 / 编辑连接」按钮；状态文案改成用户能理解的说法。
- 源码：`src/features/connections/progress/view/connection_progress_view.zig:962`

**V-04 最小窗口下向导第 2 步看不到底部操作栏** · F（向导）
- 截图：`light-min-wizard-route.png`、`dark-min-wizard-route.png`
- 问题：860×480 时内容区一直延伸到窗口底，「上一步/下一步」都不可见，也没有滚动提示。第 1 步有对应的回归测试，第 2 步没有覆盖。
- 建议：footer 固定在底部，中间内容区滚动（与第 1 步保持一致）。补上第 2、3 步在最小窗口下的 e2e 断言。
- 源码：`src/plugins/remote/editor.zig:1809`

**V-05 没有已保存主机时，「经 SSH 跳板连接」点了没有任何反应** · F（向导）
- 截图：`light-wide-wizard-route-jump.png`（点击后仍是直连，没有任何提示）
- 问题：`onAddJump` 在 `assets.len == 0` 时直接 return。首次使用的用户无法知道为什么跳板不可选。
- 建议：没有可用跳板时把该选项显示为禁用，并说明「需要先保存一台可作跳板的主机」，同时给出新建入口。
- 源码：`src/plugins/remote/editor.zig:1422-1446`

**V-06 文件列表中，长文件名被硬截断后紧贴大小列** · F（文件）
- 截图：`light-min-files-normal.png`（`deployment-fixture-with-a-long-nan0 B`）；宽窗口的同一行也能看到
- 问题：名称列没有省略号，也没有右侧留白，文件名和大小读起来连成一串，容易误读。
- 建议：名称列加 `min_width:0` + 省略号截断 + 列间距，悬停时显示完整名称。
- 源码：`src/features/files/view/file_workspace_view.zig:1292-1326`

**V-07 标题栏 8 个纯图标按钮都没有悬停提示** · DS（工具栏）
- 截图：`light-wide-toolbar-tooltip.png`（悬停「设置」1.2 秒，仍没有提示）
- 问题：`titleIcon` 和各个 toolbar Button 只设置了 `a11y_label`，没有包 Tooltip。图标中「网络拓扑」「插头」两个含义不明，而且没有任何文字入口。
- 建议：标题栏图标统一包一层 Tooltip，内容为「名称 + 快捷键」（例如「快速连接 ⌘K」「AI 助手 ⌘J」）。
- 源码：`src/main.zig:12476-12515`、`src/main.zig:12503`（`titleIcon`）

**V-08 「主机密钥已变更」对话框的两条指纹没有标明新旧** · F（认证）
- 截图：`light-wide-auth-host_key_changed.png`、`light-min-auth-host_key_changed.png`
- 问题：两张卡片的标题都是「ssh-ed25519」，只能靠上灰下红的颜色区分。这里关系到「替换密钥并继续」这个危险决策，不应只依赖颜色。
- 建议：卡片标题改为「已保存的密钥」和「服务器当前提供的密钥」。在指纹上标出差异；如果做不到，至少给出明确标签。
- 源码：`src/features/connections/auth/view/auth_challenge_view.zig:489`、`:607`

### P2

| # | 问题 | 截图（代表） | 建议 | 源码 | 范围 |
|---|---|---|---|---|---|
| V-09 | 暗色主题下，菜单、提示、终端搜索、通知面板、会话菜单与背景明度几乎相同，弹层边界难以辨认 | `dark-wide-sidebar-host-hover.png`、`dark-wide-session-menu.png`、`dark-wide-terminal-search.png`、`dark-wide-notifications-empty.png` | 暗色 overlay 提高一档明度，再加一条 1px 低对比描边，统一放进 popover token | `src/features/terminal/view/terminal_overlay_styles.zig:19`、`src/features/shell/view/sidebar_styles.zig:173`、`app_theme.zig` overlay | DS |
| V-10 | 三类菜单样式不统一：页签菜单左对齐带图标；分组页签菜单文字居中、无图标，危险项也不标红；成员菜单左对齐、无图标。同一动作文案不同（「全部左右排列」与「全部改为左右排列」），排列项也不显示当前状态 | `light-wide-group-tab-menu.png`、`light-wide-group-member-menu.png`、`light-wide-tab-context-menu.png` | 统一使用一个 ContextMenu 组件（图标位、分隔、危险色、勾选态） | `src/features/workspace/view/workspace.zig:2729-2732`、`:3336-3356` | DS |
| V-11 | 页签不可区分：多个页签都叫「Local Terminal」；中文界面下仍显示英文名；分组页签在宽窗口也被截断（「组 · Local Terminal 终…」）；最小窗口下所有页签都显示成「Local ...」 | `light-wide-tabs-multi.png`、`light-wide-group-split-side.png`、`light-min-ai-empty.png` | 本地终端默认名改为「本地终端」，同名时加编号或 cwd；分组页签按可用空间分配宽度 | `src/features/workspace/view/workspace.zig:2496`、`:5494` | F |
| V-12 | 会话分组状态下，宽窗口的工具栏也被折叠成「⋯」（右侧明明还有约 400pt 空白） | `light-wide-group-split-side.png` | 只在空间真的不足时折叠 | `src/features/workspace/view/workspace_chrome.zig:45` | F |
| V-13 | 页签栏下方的「•••」胶囊与活动页签底边重叠，含义不明 | `light-min-terminal-single.png`、`light-wide-group-tab-menu.png` | 明确这个元素的用途（拖拽把手还是溢出入口），调整锚点并留出间距，或改为悬停时出现 | `src/features/workspace/view/workspace_chrome.zig` | F |
| V-14 | 侧栏主机行：悬停时出现「连接」按钮，原有的路由图标被挤向左移；每台直连主机都挂着「路由 0」徽标 | `light-wide-sidebar-host-hover.png`、`light-wide-sidebar-hosts.png` | 尾部给悬停操作预留固定槽位；直连主机不显示路由徽标 | `src/features/shell/view/sidebar_view.zig:356`、`:417` | F |
| V-15 | 快速连接：唯一的结果「本地终端」未选中，提示却写「Enter 连接」，主按钮处于禁用态；弹层没有遮罩，背后的空态插画被切成残片 | `light-wide-quick-connect-empty.png`、`light-wide-quick-connect-typed.png` | 默认选中第一项，主按钮文案跟随所选项；加遮罩或弱化背景 | `src/features/connections/quick_connect/view/quick_connect_view.zig:187`、`:392-402` | F |
| V-16 | 设置搜索：搜索期间左侧仍高亮原分类（「关于与更新」）；结果只显示子页名，缺少「SSH 与网络 › 连接」这样的路径；无结果时只有一行小字，搜索框也没有清除按钮 | `light-min-settings-search.png`、`light-wide-settings-search-empty.png` | 搜索时取消分类选中态，结果分组显示完整路径，无结果空态给出清除操作 | `src/features/settings/view/settings_content_view.zig:197`、`:382`、`:392` | F |
| V-17 | AI：未配置 provider 的提示 toast 盖住 AI 面板标题栏（最小窗口下还盖住模型菜单）；模型菜单空态下半部是大块空白；空态输入框占位文字写「继续提问…」 | `light-wide-ai-composer-typed.png`、`light-wide-ai-model-menu.png`、`light-min-ai-model-menu.png`、`light-wide-ai-empty.png` | toast 避开面板 header（或改成面板内的 inline 提示）；空菜单按内容收缩高度；占位文字按会话状态切换 | `src/features/ai/composer/view/ai_composer_controls_view.zig:565`、`src/main.zig:12634`、`src/features/notifications/view/notification_presenter.zig` | F |
| V-18 | 最小窗口 860×480 时侧栏仍然展开（PENCIL_MAP 规定此时隐藏侧栏）；分屏 + AI 面板时 AI 占了一半以上宽度，两个终端只剩 36×7 | `light-min-terminal-single.png`、`light-min-ai-empty.png` | 按设计在最小宽度下自动收起侧栏（保留用户显式偏好）；AI 面板宽度改为按比例并设上限 | `docs/ui-revamp/PENCIL_MAP.md:35` | F |
| V-19 | 认证对话框中按钮文字贴着按钮左侧，没有居中 | `light-wide-auth-password-filled.png`、`light-wide-auth-host_key_changed.png` | 标签在按钮内居中（改用共享 Button） | `src/features/connections/auth/view/auth_challenge_view.zig:585`、`auth_challenge_styles.zig:106` | F |
| V-20 | 向导「高级选项」展开后箭头仍朝右；展开后「启动命令」多行输入框底边被 footer 盖住 | `light-wide-wizard-identity-advanced.png` | 展开时箭头旋转 90°；滚动区底部预留 footer 高度 | `src/plugins/remote/editor.zig:2901`、`:3253`、`:3354` | F |
| V-21 | 输入框占位文字与已填写的值几乎同色（例如私钥路径占位 `~/.ssh/id_ed25519` 像是已经填好，旁边却报「请选择或输入私钥文件」） | `light-wide-wizard-identity-key-error.png` | Input placeholder 改用 `fg_3` 并加「例如：」前缀 | `src/plugins/remote/editor.zig:3208`；Input placeholder token | DS |
| V-22 | 设置 › AI 服务提供方空态：两个「新增服务提供方」入口都是灰字，看起来像禁用 | `dark-wide-settings-ai-providers.png` | 空态中央的入口改为 primary 按钮 | `src/features/settings/view/ai_provider_settings.zig:260`、`:317` | F |
| V-23 | 传输任务：总大小未知时显示一条空进度条（像是 0%）；行内操作全是纯图标，取消按钮紧挨着「事件」，没有区分 | `dark-wide-transfer-task-detail.png` | 大小未知时用不定进度样式；取消与其他操作拉开间距，或做成危险样式，并加上提示 | `src/features/transfer/view/transfer_manager_view.zig:1082`、`:1104`、`:1163` | F |
| V-24 | 术语不统一：「终端组」（`@grp` 说明、AI 面板标题「Local Terminal 终端组 #5」）、「会话组」（页签菜单）、「会话分组」（文档）、「组 ·」（页签）混用 —— **核实中发现** | `light-wide-terminal-at-commands.png`、`light-min-ai-empty.png`、`light-wide-group-tab-menu.png` | 统一为一个术语，并写进 DESIGN_STANDARDS | `src/main.zig`、`src/features/workspace/view/workspace.zig`、`src/features/ai/cards/view/ai_tool_results_view.zig` | DS（文案） |

### P3

| # | 问题 | 截图 | 源码 | 范围 |
|---|---|---|---|---|
| V-25 | 暗色主题下 primary 按钮标签是黑字（`actionForeground` 按对比度算出），空态按钮里的图标却硬编码为白色，图标与文字颜色不一致 | `dark-wide-workspace-empty.png` | `src/shared/ui/theme/app_theme.zig:481`、`src/main.zig:12999` | DS |
| V-26 | 中文排版：逗号落到行首（「，请检查敏感内容」），通知末尾只有一个「型。」被折到下一行 | `light-wide-settings-ai-behavior.png`、`light-wide-ai-composer-typed.png` | `src/features/settings/view/panes/settings_ai.zig:53`；zenit 文本换行 | DS |
| V-27 | 设置保存条中的「恢复默认…」被截断；页面干净时仍显示「撤销更改 / 保存更改」 —— **核实中发现** | `light-min-settings-search.png`、`light-wide-settings-keys.png` | `src/features/settings/view/settings_content_view.zig:233-240` | F |
| V-28 | 设置细节：ANSI 色块没有描边（首尾色块与底色融在一起）；浅色主题下「图片适配/对齐」选择器没有边界；SSH 连接页的下拉框比数值框宽；搜索框圆角在胶囊形与圆角矩形之间不一致；SFTP 说明在宽窗口下也被截断；总览摘要显示「light」，子页却显示「Vanta Light」；「已选中」的 ✓ 位置靠近下一张主题卡 | `light-wide-settings-appearance-theme.png`、`light-min-settings-ssh-connection.png`、`light-min-settings-dirty-subpage.png`、`light-wide-settings-plugins.png`、`light-wide-settings-appearance-overview.png` | `appearance_view.zig:247`、`:1330`；`settings_subpages.zig:113`；`settings_plugins.zig:83` | F |
| V-29 | 「关于与更新」：自动检查已关闭，说明仍写「启动后检查」 | `light-wide-settings-updates.png` | `src/features/settings/view/panes/settings_updates.zig:164-168` | F |
| V-30 | 向导文案：「连接名称」字段的错误提示写成「请输入主机名称」；必填项没有标记 | `light-wide-wizard-identity-errors.png` | `src/plugins/remote/editor.zig:3000` | F |
| V-31 | 侧栏分组菜单：禁用的「删除空分组」文字是灰色，图标仍是红色 | `light-wide-sidebar-group-menu.png` | `src/features/shell/view/sidebar_view.zig:558-563` | F |
| V-32 | 空工作区「已保存的连接」最多显示 3 条（4 台中缺 build-agent-mac），标题没有说明 | `light-wide-sidebar-hosts.png` | `src/features/workspace/view/empty_saved_connections.zig:12`（`max_rows = 3`） | F |
| V-33 | 「新建会话」菜单中，「快捷连接」分组下列的是「新建主机 / 新建 SFTP / 新建 KVM」，分组名与内容不符 —— **核实中发现** | `dark-wide-session-menu.png` | `src/features/workspace/view/session_menu.zig` | F |
| V-34 | 终端搜索无匹配时，上下箭头仍是可用样式 | `light-wide-terminal-search-none.png` | `src/features/terminal/view/terminal_search.zig:118`、`:163` | F |
| V-35 | `@` 本地指令面板底部显示「共14项」，只露出 6 项，没有滚动提示 | `light-wide-terminal-at-commands.png` | `src/features/terminal/view/terminal_view.zig:1921` | F |
| V-36 | 空态缺少下一步：传输面板只写「没有传输任务」；远端空目录只写「目录为空」；会话记录为空时，「清空」图标没有禁用态 | `light-wide-transfers-empty.png`、`light-wide-files-empty.png`、`light-wide-history-empty.png` | `transfer_manager_view.zig:826`、`file_workspace_view.zig:702`、`history_host.zig:125` | F |
| V-37 | 文件工作区：失败后的恢复操作只有插头和刷新两个纯图标；最小宽度下修改时间列被隐藏且没有提示；`local⌄`/`remote⌄` 的箭头紧贴文字 | `light-wide-files-failed.png`、`light-min-files-normal.png` | `file_workspace_view.zig:681`、`:749-757` | F |

另外两项**需要产品决策**，不作为缺陷计入：

- 侧栏主机行单击只选中、双击也不连接，必须点行尾 ▶ 或按 Return（`sidebar_view.zig:464`，属于有意设计）。这与多数 SSH 客户端「双击连接」的习惯不同。
- 终端区右键直接粘贴剪贴板，菜单要用中键打开（`terminal_view.zig:4137`）。在远端 shell 里误触右键会把剪贴板内容送进去，建议评估是否改为「右键出菜单、可选右键粘贴」。（已按 design-r3 B1 改：右键弹出原生菜单，设置 › 终端与工作区 ›“右键行为”可切回直接粘贴，r3-terminal-menu。）

## 4. 否决的条目

| # | Codex 条目 | 理由 |
|---|---|---|
| R1 | b16-auth-a-1、b17-01（P0：暗色主题下认证对话框白底白字） | **夹具伪影**：`auth-challenge-preview` 在 dark 下整窗都是浅色背景，夹具自己的标题和按钮行同样是白字白底，说明夹具没有正确应用暗色 app/surface 色，不能据此判断生产界面。暗色认证对话框需在真实 SSH 流程（例如 `ssh_auth_loopback.py` 沙箱夹具）中复核，见「阻塞」。 |
| R2 | b13-01（会话记录面板显示 0 条，与状态描述不符） | 采集时所有会话仍在运行，失败的 SSH 也还在自动重试；面板文案本身写明「会话结束后可在这里查看」。是 manifest 的状态描述不准确，不是产品缺陷。 |
| R3 | b13-02（会话记录面板盖住终端左侧） | 这是临时弹出面板，可随时关闭，属于正常的浮层交互。改成挤压布局属于设计偏好。 |
| R4 | b19-01、b20-01（P1：浮动保存条遮挡设置内容） | 保存条按 Pencil `EHLGD` 设计为浮动胶囊；`panes` 底部预留了 76pt（`settings/view/styles.yss:37`），滚到底时不会遮挡任何行。截图只是滚动中途的状态。 |
| R5 | b05-02（向导宽窗口下「下一步」离内容太远） | 向导底部固定 footer 是常规做法，属于审美偏好。 |
| R6 | b23-04（最小窗口下终端搜索浮层遮住首行右半） | 搜索浮层是临时的，可关闭，匹配项会自动滚到可见区，属于常规做法。 |

## 5. 修复分组建议

**P4 设计系统（统一修）**
- V-01 禁用态按钮、V-25 primary 按钮前景/图标一致、V-21 placeholder 色、V-09 暗色 overlay 层级与描边、V-10 ContextMenu 统一（图标位 / 分隔 / 危险色 / 勾选态）、V-07 工具栏图标 Tooltip 规范（名称 + 快捷键）、V-26 中文换行禁则、V-24 术语表（写进 DESIGN_STANDARDS）。
- 同一套 token 也会顺带解决 V-31（禁用危险项的图标色）、V-34（禁用态图标）和 V-36 中「清空」图标的禁用态。

**P5 各功能波次**
- 终端：V-02（结果徽标）、V-34、V-35。
- 连接与向导：V-03、V-04、V-05、V-20、V-30；认证：V-08、V-19。
- 工作区与页签：V-11、V-12、V-13、V-14、V-32、V-33。
- 快速连接：V-15。
- AI：V-17。
- 设置：V-16、V-22、V-27、V-28、V-29。
- 文件与传输：V-06、V-23、V-36、V-37。

**先在 Pencil 出设计稿再实现（较大的 UX 调整）**
1. **连接失败 / 重试视图**（V-03）：失败原因的展示、重试与编辑入口、各跳状态文案。
2. **最小窗口布局策略**（V-18、V-04）：860×480 下侧栏自动收起、AI 面板与分屏的宽度分配、向导各步的滚动与 footer。
3. **页签标识方案**（V-11、V-13）：同名会话如何区分、分组页签宽度、「•••」胶囊的定位与用途。
4. **向导第 2 步的跳板空态**（V-05）：无可用主机时如何引导。
5. **标题栏工具组**（V-07、V-12）：图标含义、提示、何时折叠。
6. **右键 / 单击交互的产品决策**（第 3 节末尾两项）。

## 6. 阻塞与限制

- **暗色认证对话框未验证**：夹具在 dark 下没有正确应用暗色背景（R1）。需要修好夹具，或者在沙箱里用本地 loopback SSH 夹具走真实认证流程后补拍。
- 向导是独立原生窗口，关闭后 Harness 不会自动回绑主窗口（设置窗口关闭时会调用 `rebindTestHarness`，向导 host 不会），所以采集脚本把向导拆成了单独的进程。
- 认证 / 文件 / 传输是组件夹具，不是主程序内的真实接入；Harness 合成输入不代表物理键盘 / 输入法的表现。
- 截图不包含 macOS 原生红绿灯。
- 本轮没有修改任何产品代码，也没有提交；新增文件只有 `e2e/visual_audit_capture.ts` 和本文档。
