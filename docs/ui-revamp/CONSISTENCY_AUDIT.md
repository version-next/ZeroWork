# ZeroWork 一致性审查：各自为政的重复实现与交互表达不一致

- 审查对象：`feat/ui-arch-revamp` @ `5e0bfe64`。只读审查，没有修改任何源码。
- 方法：
  - 代码层：按主题全仓检索，读实现确认确实是重复，不只看命名。下文的 `文件:行` 都相对 `src/`。
  - 体验层：用 test-mode 构建（`-Dtest-mode=true`，check-test-hooks 通过）在 `zw-nonet.sh` 断网和私有 HOME 下启动，用 e2e harness 驱动。脚本是 `tools/probe.ts`，连接本机 loopback SSH 夹具。
  - 截图在 `screens/`（`light-*` 和 `dark-*` 两套），逐步行为记录在 `screens/report-{light,dark}.json`。亮色和暗色的行为结果完全一致。
- 不重复报告的在途项：float-chrome（浮卡外框）、title-click（标题栏工具悬停与点击），以及已完成的 ToolDef 和 AI 绑定。凡是补充它们漏掉位置的条目，都已标明。

## 先说结论

1. **有些共享设施已经写好，却没有接入。** 这是性价比最高的一类问题：
   - `features/shell/model/overlay_model.zig` 的 `OverlayHost`：Esc 分层关闭加焦点归还，全仓只在 `application_host.zig:531` 被 init。
   - `features/shell/model/shortcut_router.zig`：只在 `root.zig:306` 被测试引用。
   - `features/workspace/model/context_menu_view.zig`：只在 `root.zig:132` 被引用。
   - 结果是各功能自己处理 Esc、焦点归还、菜单定位，各写一套。
2. **设置窗口的 `.legacy` 和 `.yix` 两套外壳并存。** 注释写明"3f 删除"（`features/settings/host/settings_host.zig:68/1025/1391/2155`），legacy 侧约 6 千行。下文 #2、#3、#6、#7 里相当一部分重复会随 3f 一起消失。**建议先做 3f，再做其他统一包**，否则同一处要改两遍。
3. **体验层最明显的问题：标题栏同一排、视觉权重相同的工具面板，打开后的行为各不相同。** 见 #1 的表：初始焦点、Esc 能否关闭、点外部是否关闭、焦点是否归还，四个方面各不一样。头部结构、计数写法和空状态也各不一样，见 #4。

## 条目一览

| # | 类 | 严重 | 主题 | 能否合包 |
|---|---|---|---|---|
| 1 | A+B | 高 | Esc 分层、焦点归还、面板互斥（OverlayHost 未接入） | 包 D |
| 2 | A+B | 高 | 确认对话框与危险操作：约 20 处、三种载体、文案和样式不一 | 包 C |
| 3 | A+B | 高 | 菜单：原生 Menu 和自绘 Popover 列表两条路线，页签菜单两套模型 | 包 C′ |
| 4 | B+A | 高 | 同级面板的头部、关闭按钮、计数、空状态各写一套 | 包 E（依赖 float-chrome） |
| 5 | A | 中 | 搜索匹配 9 份、列表键盘导航 5 份以上、加载/错误/重试各写一套 | 包 A、E |
| 6 | A+B | 中 | 字节、速率、时长、相对时间格式化至少 9 套，单位混用 | 包 A |
| 7 | A+B | 中 | 错误到文案的映射逐表复制，已经不同步；`@errorName` 直接展示给用户 | 包 B |
| 8 | A+B | 中 | 连接和 SOCKS 状态到颜色、文案的映射 8 套以上 | 包 B |
| 9 | A | 中 | 快捷键：硬编码绕过键位表，提示文字写死，格式化 4 份 | 包 F |
| 10 | A | 中 | 持久化：原子写约 20 份、fsync 不一致，`.lock` 4 份，坏行容错不一 | 包 G |
| 11 | A | 低 | 异步：重试退避 3 套，取消令牌 2 种，手写自旋锁约 10 处 | 包 G |
| 12 | A+B | 低 | Tooltip 延迟 450/500/600 三档，Popover 冒充 Tooltip，control_hint 改写颜色 | 包 A |
| 13 | A | 低 | 夹取边距 8/12/16/24、拖动阈值 0/1/4/5，常量重复定义 | 包 A |
| 14 | B | 中 | 术语与语气：关闭页签、断开并关闭、关闭会话；主机和连接；删除和移除 | 包 B |
| 15 | B | 低 | 删除和移除的图标 trash、trash_2、x 混用；筛选控件 Button 组和 Select 混用 | 包 E |

---

## 高优先级

### #1 Esc 分层、焦点归还、面板互斥　A+B · 高

**体验现状（实测）**

操作方式：点击触发按钮打开面板，按 3 次 Tab，再按 Esc。证据见 `screens/report-light.json` 和 `light-p-*.png`。

| 入口（同一排标题栏或状态栏） | 打开后焦点 | Tab 能否进入面板 | Esc 是否关闭 | 关闭后焦点 |
|---|---|---|---|---|
| 会话记录 `toolbar.history` | 搜索框 | 能 | 能 | 回到触发按钮 |
| 提醒 `toolbar.notifications` | 面板的 × | 能 | 能 | **丢失（null）** |
| 传输 `toolbar.transfers` | **停在触发按钮** | **不能**，Tab 在标题栏里循环 | **不能** | — |
| 命令历史 `status.command-history` | **停在触发按钮** | **不能** | **不能** | — |
| 通信链路、端口转发 | 停在触发按钮 | 不能 | 能 | 回到触发按钮，或跳到别处（forward 跳到了 `toolbar.history`） |
| 主题、新建会话菜单 | 第一项 | 能 | 能 | 回到触发按钮 |

- **命令历史面板点外部也不会关闭。** 截图 `light-p-chain.png`、`light-tab-context.png`、`light-terminal-context.png`、`light-ai-open.png`、`light-history-clear-confirm.png` 里，它一直留在右上角，并和通信链路、页签菜单、AI 面板、会话记录同时叠在屏幕上。其他同级面板点外部都会关闭。
- **本地会话关闭确认框：代码要把焦点放在"取消"上（`features/terminal/view/local_close_view.zig:131`），实测焦点却落在标题栏的 ×（`local.close.dismiss`）上，并且自动弹出了 Tooltip。** 见 `light-local-close-confirm.png`。

**代码现状**

- 统一设施已经写好但没有接入：`features/shell/model/overlay_model.zig` 的 `OverlayHost` 有 `escape`、`outside`、`focus_return`、`DismissPolicy` 和 IME 判断，只在 `features/shell/host/application_host.zig:531` init、`:586` deinit。
- 实际的 Esc 顺序是 `features/shell/host/nav_host.zig` 里的两串 if：`:835-862` 和 `:871-917`。其中菜单检查了两次（`:839` 和 `:902`）；`asset_action_view` 和 `conflict_view` 在 `:815-824` 直接返回 `.ignored`。设置窗口另有一套：`features/settings/host/settings_host.zig:1038` `windowEscape`。
- 焦点归还至少 8 套：
  - `settings_host.zig:87/1129`
  - `features/connections/quick_connect/view/quick_connect_view.zig:97/245/588`
  - `features/shell/model/status_controller.zig:31/86/121`
  - `features/shell/view/status_theme_view.zig:388`
  - `features/workspace/view/session_menu.zig:371`
  - `features/workspace/view/workspace.zig:5067`
  - `features/connections/progress/view/connection_progress_view.zig:164`
  - `features/ai/pane/view/ai_return_focus.zig`

**为什么本该是同一个东西**：这些都是"当前窗口里的一层浮层"，打开、Esc 关闭、点外部关闭、焦点归还的规则应当由层级决定，不应由各功能自己决定。用户分不清哪个面板会自己消失。

**建议的统一抽象**（放在 src/shared 或 shell model 层，复用现成的 `OverlayHost`）
- 接口草案：

  ```zig
  overlay.open(.{ .owner, .trigger = .button, .anchor, .focus_return = .{ .control = trigger_id },
                  .dismiss_policy = .{ .escape = true, .outside = true }, .initial_focus = .first_control })
  // nav_host 的按键分发只剩一句：
  if (overlay.escape()) |d| restore(d.focus)
  ```

- 每种面板只在注册时声明 `DismissPolicy` 和 `initial_focus`，不再自己写 Esc 处理。
- 迁移步骤：
  1. 让 `OverlayHost` 驱动 nav_host 那串 if，行为不变，逐个面板登记（行为不变的重构单独提交）。
  2. 再按用户拍板的规则统一传输、命令历史的 Esc、外部点击和初始焦点（行为修复单独提交）。
  3. 删掉各处的 `restoreFocus` 和 `previous_focus`。
- 规模：中到大，约 15 个视图文件加 nav_host。风险在于焦点与 IME、终端输入抢焦点之间的相互作用，需要现有 e2e 加上本审查的 probe 做回归。
- 冲突：title-click 正在改同一批触发器（含 `features/shell/view/status_hover_preview.zig`），float-chrome 改浮卡。**必须在这两个包合入后再做。**
- **需要用户拍板**：同级面板是否一律"Esc 和点外部都关闭、焦点进入面板第一个控件、关闭后回到触发按钮"？命令历史和传输是否有意设计成常驻？

### #2 确认对话框与危险操作　A+B · 高

**现状**：约 20 处，没有共享组件，各自挂 `W.Modal` 或 `W.Popover`，各自设焦点、处理 Esc。

| 语义 | 位置 | 载体 | 主按钮原文 | 危险样式 |
|---|---|---|---|---|
| 关闭远程会话 | `features/workspace/view/workspace.zig:4877-4975` | Modal（命令式，红字自绘标题，`close_on_overlay=false`） | 仍然关闭 | danger |
| 关闭本地会话 | `features/terminal/view/local_close_view.zig:34-80`（截图 `light-local-close-confirm.png`） | Modal（自绘图标标题加自绘 ×，**没设** `close_on_overlay`） | 结束并关闭 | danger |
| 关闭会话组 | `workspace.zig:3881`、`features/workspace/view/group_close_view.zig:71-75` | Modal | 关闭全部 N 个会话 | danger；部分完成那一步用 primary |
| 结束 AI 会话 | `features/ai/pane/view/ai_close_confirmation_view.zig:41-66` | **Popover** | 结束会话 | **primary**（`:65`） |
| 删除 AI 会话 | `features/ai/sessions/view/ai_sessions_view.zig:62-85` | Modal | 删除会话 | danger |
| 删除或清空会话记录 | `features/history/view/history_card.yix:169,211-219` | **Popover 行内** | **确认删除** | danger |
| 删除主机配置 | `features/connections/assets/view/asset_action_view.zig:429-510` | Popover 多步 | 删除主机配置；取消按钮叫"**保留主机**" | 动态 |
| 删除 provider 或模型 | `features/settings/view/panes/ai_dialogs.yix:166-172`；legacy 在 `features/settings/view/provider_delete_dialog.zig:24-57` | Modal | 删除 | yix 用 danger；**legacy 用 secondary 加手刷红底**（违反原生规则） |
| 清除全部数据 | `features/settings/view/data_cleanup.yix:27-39`；legacy 在 `application_data_cleanup_view.zig`；启动时在 `platform/macos_data_alert.m:12-44` | Modal 或 **NSAlert** | 动态 | danger 或系统样式 |
| 放弃设置更改 | `features/settings/view/save_bar.yix:90-101`；legacy 在 `settings_host.zig:1409-1480` | Modal | yix 写"放弃更改 / 保存 / 恢复默认"，legacy 写"**放弃 / 保存关闭 / 恢复**" | 放弃用 secondary |
| 替换主机密钥 | `workspace.zig:4337-4420` 用 secondary；`features/connections/progress/view/connection_failure.yix:149` 用 **danger** | Modal | 替换密钥并继续 / 信任新密钥并连接 | 同一件事两种样式 |
| 断开 KVM | `plugins/bmc_ikvm/views.zig:2081-2101` | Modal（原生 title），取消按钮叫"**返回**" | 动态 | danger |
| 清除已结束的通知 | `features/notifications/view/notification_history.yix:94` | **无确认、无撤销** | 清除已结束 | — |
| 移除 MCP 或技能、删除导入主题 | `ai_extensions.yix:83-86`、`appearance.yix:238` | 菜单项直接执行 | 移除 / 删除导入主题 | 菜单项 danger |
| 会话记录清理（另一处） | `features/history/view/record_cleanup_view.zig:105-165`，和 `application_data_cleanup_view.zig:95-140` 同构 | Modal 状态机：确认、进行中、失败重试 | — | 失败标题直接拼 `@errorName`（`:119/:142`） |

- 另外两点：
  - `toast_stack.yix:33` 定义了"撤销"动作，但没有任何删除流程在用。
  - 全仓没有"不再提示"。

**为什么本该统一**：这些都是"不可逆操作前的一次确认"，按钮语义、危险色、默认焦点、Esc 行为和遮罩策略应当一致。目前用户在不同地方看到的是三种载体和五种确认文案。

**建议的统一抽象**
- 加一个 zenit 上游 Modal 预设，或在 `src/shared/ui/components/confirm/` 放共享 yix 组件，二选一：

  ```zig
  ConfirmSpec{ title, body, risks: []Risk = &.{}, confirm_label, cancel_label = "取消",
               tone: enum{ danger, normal }, carrier: enum{ modal, inline } = .modal,
               initial_focus = .cancel, close_on_overlay = false }
  ```

- danger 只走原生 `variant=.danger`；Esc 等同于取消；焦点默认放在取消上。
- 再定一条与 `laneFor` 对称的纯函数规则 `confirmFor(op)`：
  - 不可逆，或涉及多个对象 → modal。
  - 单行、可恢复 → 不确认，改用轻提示加"撤销"（即接上 toast 的撤销动作）。
- 迁移步骤：
  1. 先出组件和规则函数。
  2. 逐处替换。会话关闭三处（A、B、C）的风险描述合成一个数据源。
  3. 删掉 legacy 对话框（随 3f）。
- 规模：中，约 15 个文件。风险在于 e2e 依赖现有的 test_id，迁移时必须保留全部 test_id。
- 能和 #14（文案）一起做。
- **需要用户拍板**：
  1. 行内 Popover 确认（会话记录、主机删除）是否保留？
  2. 哪些操作改成"撤销"而不是"确认"？
  3. 统一按钮文案：用"删除"还是"确认删除"，用"关闭"、"仍然关闭"还是"结束并关闭"。

### #3 菜单与右键菜单　A+B · 高

**体验现状**：侧栏主机右键（`light-sidebar-context.png`）和页签右键（`light-tab-context.png`）、终端右键（`light-terminal-context.png`）在同一个界面里风格不同。
- 前者是自绘的：有一个"主机 · …"头部，行更高，危险项"删除主机资产"只有图标是红色、文字是黑色，快捷键列写的是"双击"。
- 后两者是原生 Menu，危险项"关闭页签"的整行文字都是红色。
- **侧栏右键菜单打开时，主机的悬停 Tooltip 仍然盖在菜单上方。**
- 新建会话菜单（`light-p-new-session.png`）也是自绘的分组列表。

**代码现状**
- 原生 `W.Menu` 用在：终端（`features/shell/view/terminal_menu.yix:20`）、页签（`features/workspace/view/tab_menu.yix:12`）、溢出（`tab_strip.yix:97`）、标题栏"⋯"、窗格头"更多"（`workspace.zig:3343-3390`）、设置。
- 自绘的"Popover 加 Button 行"有 6 处，各自写行样式、分隔线、danger 色和键盘导航：
  - 中键和侧栏右键：`features/shell/host/menu_host.zig:454-560`、`app/main_window.zig:268-285`
  - 侧栏分组"更多"：`features/shell/view/sidebar_view.zig:588-610`，自带 `MenuKeyboard`
  - 新建会话：`features/workspace/view/session_menu.zig:145-200`，自写方向键
  - 文件右键：`features/files/view/file_actions_view.zig:129-190`
  - 传输任务"⋯"：`features/transfer/view/transfer_manager_view.zig:1259-1280`
  - KVM：`plugins/bmc_ikvm/views.zig:1956`
- 共享模型 `features/workspace/model/context_menus.zig`（`rightClickEntries :159`、`tabMenuItems :298`）存在，但会话组页签菜单在 `workspace.zig:2718-2749` 里硬编码了同类项（重命名… F2、颜色、关闭页签 ⌘W），并用 `std.mem.eql` 链分发。
- 同一个模型里图标有两种写法：`context_menus.zig:291/487/488` 用 "⏻"、"⧉"、"📋" 字符，其余用图标名，宿主再兜底。
- 命令分发有三种：`stringToEnum`、`eql` 链、每项 `on_click`。

**建议**
- 所有列表式菜单都只用原生 `W.Menu`。它已有 shortcut、danger、disabled、separator 和子菜单；分组标题如果原生没有，就补上游 `MenuItem.kind=.header`。
- 菜单数据一律来自 `context_menus` 风格的 Descriptor：

  ```zig
  MenuEntry{ action: Action, label, icon: ui.SvgAsset, danger, separator_before }
  ```

  快捷键文字不写在条目里，从 #9 的键位表派生。
- 删除未使用的 `context_menu_view.zig`，或者让它成为唯一的投影层。
- 迁移步骤：组页签菜单并入 `tabMenuItems`，自绘菜单逐个换成原生，emoji 图标换成 `ui.icons`。
- 规模：中，约 8 个文件，用户可见。和 #2 都会碰 `workspace.zig`，但区域不同，可以并行。

### #4 同级面板的头部、关闭按钮、计数、空状态　B+A · 高（补充 float-chrome）

**体验现状**：标题栏同一组的四个面板，截图见 `light-p-history.png`、`light-p-notifications.png`、`light-p-transfers.png`、`light-p-command-history.png`。

| 面板 | 头部结构 | 计数写法 | 空状态 |
|---|---|---|---|
| 会话记录 | 灰色图标，标题，"0 条记录"，右侧"最大化"和 × | "0 条记录" | 居中，有图标、标题、说明 |
| 提醒 | 强调色图标，标题，徽标"0"，× | 徽标 "0" | 居中，图标是**强调色**，有标题和说明 |
| 传输 | 顶部拖动条，强调色图标，标题，锁图标，Select，× | 无 | 居中，有图标和标题，**没有说明** |
| 命令历史 | 灰色图标，标题，×；第二行是主机名和"0 条" | "0 条" | **左对齐的一行纯文字** |

AI 面板头部（`light-ai-open.png`）又是另一套：一组窗口控制按钮，包括 ⧉、+、−、⤢、×。

**代码现状**：关闭按钮约 40 处各写一份。按钮框尺寸有 20、22、24、28、30、32，图标尺寸有 12、14、16、18。很多处是"原生 Button 加 `base_style` 覆盖，再 `appendChild(iconTint(x))`"，这违反"只用原生、不覆盖"的规则。例如：
- `features/terminal/view/command_history_view.zig:66-68`（借用了 socks 的样式）
- `features/connections/progress/view/connection_logs_view.zig:212-213`
- `features/update/view/app_update_view.zig:100-103`
- `features/connections/wizard/view/wizard.zig:379`
- `features/settings/view/ai_model_editor.zig:78`
- `features/transfer/view/transfer_events_view.zig:48`
- `features/connections/socks/view/socks_background_view.zig:46`（图标 18）
- `features/ai/host/child_dialog.zig:86/108`（图标 14 和 12）

只有 yix 侧的写法基本一致：`history_card.yix:102` 是 sm/14，`notification_history.yix:84` 是 xs 且没有 iconSize。

Tooltip 文案格式也不统一："关闭会话记录（Esc）"（`history_card.yix:101`）、"关闭搜索 · Esc"（`terminal_search.zig:164`），其余没有 Tooltip。

空状态实现：
- `history_card.yix:197`、`notification_history.yix:103`：结构相同，各写一份。
- `transfer_manager_view.zig:543-575`：手搓。
- `command_history_view.zig:83`、`features/ai/sessions/view/ai_sessions_view.zig:343`：单行文字。
- "没有匹配的设置"重复写了 4 次（`settings_controls.zig:255`、`appearance_view.zig:188`、`settings_plugins.zig:36`、`settings_content_view.zig:415`），而且 `settings_content_view.zig:276/411` 用这段**文案字符串**来判断页面是否为空。

**建议**
- float-chrome 统一外框后，在卡片注册表里给每种面板加一份**头部 Descriptor**：

  ```zig
  Header{ icon, title, count: ?CountFormat = null /* 统一 "N 条" */, actions: []HeaderAction /* 顺序固定：辅助动作…, 最大化, 关闭 */,
          close_hint = "关闭{title}（Esc）" }
  ```

  由 float-chrome 的 chrome 统一渲染；关闭按钮固定为原生 `Button(variant=.ghost,size=.sm,iconOnly,icons.x)`，不加 `base_style`。
- 空状态抽成一个共享 yix 组件 `EmptyState{icon, title, hint?, action?}`，并作为上游 zenit `Empty` 组件的候选（zenit 目前没有）。
- 规模：大，触及约 40 个文件，但每处改动小。风险是视觉回归，需要亮、暗两套截图。
- **必须在 float-chrome 之后做**，最好由同一个负责人接手。
- **需要用户拍板**：计数用"N 条"还是徽标；空状态是否一律带说明文字；AI 面板的窗口控制组算不算例外。

---

## 中优先级

### #5 搜索、列表导航、加载、错误重试　A · 中
- 匹配函数有 9 份，全部是"只对 ASCII 忽略大小写的子串匹配"：
  - `features/history/model/history_list.zig:111`
  - `features/shell/model/sidebar_model.zig:79`
  - `features/workspace/view/workspace.zig:6422`（与上一份逐字相同）
  - `features/files/view/file_workspace_view.zig:1676`
  - `features/transfer/view/transfer_manager_view.zig:1720`（同一文件的过滤条件在 `:751` 和 `:1598` 写了两遍）
  - `features/settings/model/settings_search.zig:16` 和 `features/settings/view/settings_content_view.zig:442`（逐字相同）
  - `features/settings/view/ai_model_editor.zig:417`
  - `features/connections/quick_connect/view/quick_connect_view.zig:635`
- 行为差异：只有设置里的匹配会去掉首尾空白，其余不去（按代码推断，末尾多一个空格就搜不到）；全部不支持拼音。
- 列表键盘导航：循环和夹取两种行为混用。
  - `history/list/model/view_model.zig:282` 循环，固定行高 58 手算滚动。
  - `files/view/file_workspace_view.zig:1461` 夹取，用 `ensureVisible`。
  - `session_menu.zig:146`、`ai_model_editor.zig:336`、`quick_connect_view.zig:302` 各写一次 `(i±1)%n`。
- 加载和错误：会话记录（`history/detail/model/view_model.zig:14`）和文件浏览（`file_workspace_view.zig:13`）各有一套几乎相同的 `{loading, ready, empty, failed}` 枚举。"重新读取"按钮也各写一遍（`history_card.yix:190`、`files/view/file_workspace_presentation.zig:290-305`）。
- 建议：
  - `src/shared/base/text_match.zig`：`pub fn matches(query, fields: []const []const u8) bool`，统一去空白和大小写处理，以后在这里加拼音。
  - `src/shared/base/list_cursor.zig`：`move(i, n, dir, .wrap|.clamp)`。
  - `ListPhase` 枚举加上 #4 的 EmptyState。
- 规模：匹配和导航是纯函数，小、风险低，能先做（包 A）；状态和空状态并入包 E。

### #6 格式化（字节、速率、时长、相对时间）　A+B · 中
- 字节：
  - `files/view/file_workspace_view.zig:1659`：最大到 GiB。
  - `transfer/view/transfer_manager_view.zig:1828` 和 `connections/socks/view/socks_info_view.zig:529`：**最大只到 MiB**，大文件会显示成几千 MiB。
  - `transfer/view/transfer_conflict_view.zig:720/735/807`：只在整 MiB 时用 MiB，否则输出原始字节数。
  - `ai/extension_sizes.zig:2`：到 EiB。
  - `features/update/host/app_host.zig:536`：按十进制计算。
- 速率：两个同名 `formatSpeed` 实现不同。
  - `shell/view/status_transfer_view.zig:15` 显示 KiB/s、MiB/s，0 时显示"— MiB/s"。
  - `transfer/view/transfer_panel.zig:135` 按 1024 计算，却标成 **KB/s、MB/s**，0 时显示"0 KB/s"。
  - 结果是同一速度在状态栏和传输面板的单位不同。
- 设置里同一个分块大小：`settings_content_view.zig:671` 写 "KB"，`model/pane_fields.zig:192`、`model/catalog.zig:187`、`panes/settings_transfer.zig:36` 写 "KiB"（后三处是同一段文案复制了三遍）。
- 相对时间：
  - `notifications/history/model/view_model.zig:290` 没有"天前"这一档，会出现"30 小时前"。
  - `connections/quick_connect/model/quick_connect.zig:104` 有"天前"。
- 时长：
  - `history/model/record_labels.zig:51`
  - `terminal/model/command_annotations.zig:21`（写成"1.2 s"）
  - `ai/cards/view/ai_step_group_view.zig:95`（写成"1.2s"，只差一个空格）
  - `plugins/bmc_ikvm/view_model.zig:394/535`（同一文件里"秒"和"s"混用）
- 正面例子：`history/model/record_labels.zig:43` 的 `dateLabel` 已被命令历史复用。
- 建议：新建 `src/shared/base/format.zig`，提供 `bytes(buf, n)`（IEC，一直到 TiB）、`rate(buf, bps)`、`duration(buf, ms, .short|.long)`、`relative(buf, now, then)`。现在跨功能直接 import 的地方（如 transfer 引用 `status_transfer_view.formatSpeed`）都改为引用 shared。
- 规模：小，纯函数加单测。用户可见的变化是单位统一。
- **需要用户拍板**：KiB（二进制）还是 KB（十进制）。

### #7 错误到用户文案　A+B · 中
- 逐表复制：
  - MCP 和技能的错误表，约 30 条：`features/settings/model/ai_pane.zig` 约 1730-1770 行，和 `features/settings/view/ai_extensions_settings.zig:839-884` 相同。
  - 主题导入错误表：`features/settings/model/view_model.zig:2948-2957` 和 `features/settings/view/panes/appearance_view.zig:360` 相同。
  - 以上两组的 legacy 一侧会随 3f 删除。
- **已经不同步**：SSH 失败文案 `connections/progress/view/connection_progress_view.zig:1545` 覆盖了超时、主机密钥变更等错误，而 `connection_logs_view.zig:384` 是精简复制，缺这些错误。同一个错误，进度页显示中文，日志页显示 `@errorName`。
- `@errorName` 直接给用户看的位置：
  - `plugins/bmc_ikvm/views.zig:368/571/881/1336/...`（`showMessage(@errorName(err))`）
  - `features/workspace/host/session_export_jobs.zig:202`（以通知弹出）
  - `features/settings/host/settings_host.zig:2095/2104/2297`
  - `history/view/record_cleanup_view.zig:119/142`
  - `ai/provider_http.zig:51`
- 同一个错误多种说法：
  - `AccessDenied` 至少 5 种。
  - 认证和鉴权混用：`ai/provider_http.zig:44` 用"鉴权失败"，`plugins/bmc_ikvm/view_model.zig:543` 和 `features/connections/progress/model/failure_view.zig:291` 用"认证失败"。
- 建议：
  - 每个领域一张 `ErrorCatalog`，形如 `fn describe(err: anyerror) ?Text{title, hint}`，放在该领域的 model 层。另设 `src/shared/base/error_text.zig` 提供系统错误（AccessDenied、FileNotFound、Timeout）的统一兜底。
  - 加一条护栏：视图层禁止把 `@errorName` 拼进可见文字，用 check-arch 规则约束。
- 规模：中。和 #8、#14 合成一个文案包（包 B）。

### #8 连接和 SOCKS 状态映射　A+B · 中
- 颜色：
  - 同一个页签上，圆点用 `workspace.zig:1929 tabConnectionColor`，connecting 是 warn 色；图标用 `shared/ui/components/session_icon/session_icon.zig:36 tabTint`，connecting 是 `fg_3`。所以连接中时**圆点是黄色、图标是灰色**。
  - `workspace.zig:2882` 的组页签又用另一个调色源。
  - `connections/progress/host/ssh_status_host.zig:388/447/476` 失败时不显示红色。
- 文案：
  - `ssh_status_host.zig:375/424/459` 有三个 switch，未知状态分别叫"状态未知"和"连接异常"。
  - `shell/view/status_connection_view.zig:421` 写"在线"，其他地方写"已连接"。
  - SOCKS 有 4 套：`socks/host/socks_application_host.zig:503`、`shell/model/status_connection_extras.zig:54`（与前者逐字复制）、`socks/view/socks_info_view.zig:302`（暂停叫"连接已断开"）、`host/socks_background_model.zig:185`（启动叫"连接中"）。
- 建议：新建 `src/shared/base/connection_presenter.zig`，`fn present(phase) struct{ tone: Tone, label, icon }`，全部状态显示只从这里取。
- 规模：小到中。**需要用户拍板**：用"在线"还是"已连接"；连接中显示黄色还是灰色。

### #9 快捷键注册与提示　A · 中
- 唯一可配置的键位表是 `config/keybindings.zig`，有冲突检查（`:122/131/163`）。以下硬编码绕过了它：
  - `features/terminal/view/terminal_view.zig:791/4731/4820` 的 ⌘F。用户改了"搜索"的键位后，⌘F 仍然能打开搜索，等于注册了两次。
  - `terminal_view.zig:2350/4719/4824` 的 ⌘C，`features/ai/host/ai_host.zig:4343` 的 ⌘V。
  - `features/shell/host/nav_host.zig:866` 的 Ctrl+Tab 和 F2。
- 快捷键提示文字写死：`features/workspace/model/context_menus.zig:162-164/291/433-510`、`workspace.zig:2721`、`features/shell/model/title_tools.zig:100`。用户改键位后，菜单里的提示不会跟着变（按代码推断）。
- 按键组合转符号的格式化有 4 份：`config/keybindings.zig:186`、`features/settings/view/keybinding_picker.zig:159`、`features/settings/model/keybinding_edit.zig:166`、`features/settings/view/panes/settings_keys.zig:152`。动作名称表有 3 份。
- `features/shell/model/shortcut_router.zig` 只被测试引用。
- 建议：`keybindings` 成为唯一来源，提供 `hint(action) []const u8`，菜单和 Tooltip 都从这里取。终端里写死的键改为查表。`shortcut_router` 要么接入，要么删除。
- 规模：中。和 #3 有依赖，菜单提示要用 `hint()`，应在 #3 之前或与 #3 同包。

### #10 持久化　A · 中（数据安全，用户感知低）
- 原子写约 20 份，收尾方式不一致：
  - 先 sync 再 replace：`config/ui_state.zig:40-47`、`config/store.zig:95-106` 等约 14 处。
  - **只 flush、不 sync**：`vt/raw_stream_tap.zig:72-81`、`config/imported_theme.zig:64-67`、`features/terminal/host/terminal_export.zig:10-19`、`features/workspace/host/session_export_jobs.zig:139-149`。
  - 对目录 fsync 的只有 `plugins/bmc_ikvm/management_journal.zig:85` 和 `config/data_lifecycle.zig:207` 两处，各自手写了 EINTR 循环。
- `.lock` 文件锁 4 份逐字相同：`config/store.zig:191`、`proto/ssh/host_key_store.zig:750`、`ai/session_journal.zig:95`、`ai/lifecycle_journal.zig:94`。
- 坏行容错不一致：
  - `vt/session_archive.zig:288-320` 跳过坏行。
  - `ai/session_journal.zig:146-155` 只要有一行坏掉（包括写到一半的末行）就整份失败，返回 `InvalidSessionJournal`。
- 版本校验和迁移各写一套：
  - `ui_state` 从不校验 version。
  - `vt/recording_manifest.zig:140` 返回错误。
  - "legacy 文件迁移一次"有两份：`ai/session_journal.zig:116-130` 和 `ai/lifecycle_journal.zig:112`。
- 直接改环境变量 `ZEROWORK_DATA_DIR`、绕开 `shared/testing/data_directory.zig` 的：`features/shell/host/application_host.zig:3505-3516`、`features/ai/tools/host/ai_lifecycle_controller.zig:624-676`。
- 建议：`src/config/atomic_file.zig`（或 `src/shared/base/`）提供：

  ```zig
  writeAtomic(dir, path, bytes, .{ .perms = 0o600, .durable = true, .sync_dir = false })
  acquireLock(dir, path)
  JsonlReader{ .on_bad_line = .skip | .fail | .truncate_tail }
  VersionedJson(T, current, migrate)
  ```

- 规模：中，但对 UI 零依赖，可以完全独立并行。风险在于 sync 会带来性能变化，导出类可以保留不 sync，需要显式声明 `.durable=false`。

---

## 低优先级（一行一条）

- **#11 异步**　A · 低
  - 重试退避 3 套：SSH 用秒数组 `{1,2,4,8,16}`，在 `config/config.zig:505`、`vt/ssh_worker.zig:42`、`host/socks_background_runtime.zig:28` 重复定义；SFTP 是 `transfer/manager.zig:176` 按毫秒的指数退避；AI 是 `ai/retry.zig:2` 的固定数组。
  - Retry-After 解析了两次：`ai/provider_http.zig:224`、`plugins/bmc_ikvm/native_driver.zig:1227`。
  - 取消令牌两种形态：`ai/provider.zig:113` 的 `CancelToken`，以及 SSH 和 BMC 用的裸 `*const atomic.Value(bool)`。
  - 已有 `vt/native_mutex.zig`，但仍有约 10 处手写自旋锁，例如 `proto/ssh/session.zig:110`、`update/admission.zig:3`。
  - 建议在 shared 里放 `Backoff`、`CancelToken`，统一用 `native_mutex`。与 #10 同包。
- **#12 Tooltip**　A+B · 低（补充 title-click）
  - 延迟三档：设置等约 50 处写字面量 450；`history_card.yix` 10 处写 600；`title_tools.yix:43/74` 和 `tab_strip.yix:58` 写 600；zenit 默认 500。
  - 有两处用 `Popover(.trigger=.hover,.tier=.tooltip)` 冒充 Tooltip：`shell/view/sidebar_view.zig:776`、`transfer/view/transfer_panel.zig:757`。
  - `shared/ui/components/control_hint/control_hint.zig:25` 改写了 Tooltip 的 `background`、`text_color`、`font_size`，违反原生外观规则。
  - `app/main_window.zig:729-732` 的注释写"500 ms"，实际取值是 600。
  - 悬停预览自管计时器（`shell/view/status_hover_preview.zig:132-164`，离开宽限写死 150ms）。原因是 zenit Popover 没有 `close_delay_ms`，**建议补到上游**。
  - 建议在 shared 设两个常量 `hint_delay_ms`、`preview_delay_ms`。**需要用户拍板**取 450 还是 600。
- **#13 夹取几何**　A · 低
  - "把矩形夹在窗口内留 N px"有 5 处：`shared/base/overlay_anchor.zig:18`（8）、`shared/base/float_card.zig:104`（8）、`shell/model/status_controller.zig:156`（手写，没调 `place`）、`shell/view/status_connection_view.zig:206`、`plugins/bmc_ikvm/overlay_model.zig:14`（12/16/24）。
  - 拖动阈值 4 重复定义两次：`workspace/view/tab_strip_view.zig:449`、`workspace/view/workspace_tab_styles.zig:22`。`workspace.zig:1238/3292/3311` 用的是 5。
  - 主窗口最小尺寸 860×480 写了两处：`app/main.zig:124`、`app/process_windows.zig:167`。
  - 建议统一到 `overlay_anchor.place` 和具名常量。
- **#14 术语与语气**　B · 中
  - 同一个"关闭"动作：`host/actions.zig:121` 叫"断开并关闭"；快捷键设置里叫"关闭页签"；`workspace.zig:3352` 叫"断开并关闭会话"；`shell/view/status_connection_view.zig:266` 叫"关闭会话连接"。
  - 确认框标题："关闭会话?"（`workspace.zig:4895`，半角问号）和"关闭本地会话？"（`terminal/view/local_close_view.zig:44`，全角问号）。
  - 新建入口："新建主机"（`workspace/view/session_menu.zig:18`，截图 `light-p-new-session.png`）和"新建连接"（`shell/view/sidebar_new_button.zig:11`）。
  - 删除和移除：主题菜单写"删除导入主题"，错误提示却写"再移除此主题"（`settings/model/view_model.zig:2953`）。
  - 放弃：yix 写"放弃更改"，legacy 写"放弃"。
  - 建议写一份 `docs/ui-revamp/GLOSSARY.md`，并在 `tools/arch` 加禁用词检查。**需要用户拍板术语表。**
- **#15 图标和筛选控件**　B · 低
  - 删除和移除的图标：
    - `trash`：`ai_extensions.yix:83-86`、`appearance.yix:238`
    - `trash_2`：`history_card.yix:252`、`ai_providers.yix:277`
    - `x`：`transfer/view/transfer_panel.zig:778`"移除此文件"、`ai/attachments/view/ai_attachments_view.zig:291`"移除附件"、`plugins/bmc_ikvm/editor.zig:867`"删除跳板"
  - 筛选控件：会话记录和提醒都用 Button 组加各自定义的 `filterVariant`（`history_card.yix:44`、`notification_history.yix:29`）；传输用 Select。可考虑统一为原生 Tabs 或分段控件。
  - 并入包 E。

---

## 打包建议

依赖顺序：**3f（删除设置 legacy 外壳）、float-chrome、title-click 先合入**，然后按下表执行。

| 包 | 条目 | 层 | 可并行 | 冲突与依赖 | 需要用户拍板 |
|---|---|---|---|---|---|
| 0 `settings-3f` | 清掉 legacy 外壳（#2、#3、#6、#7 的设置部分） | 视图 | — | 其他包的前置条件 | 无（已计划） |
| A `shared-format` | #5 匹配与导航、#6、#12 常量、#13 常量 | `src/shared/base` 纯函数 | **立即可做** | 每处只换调用点，冲突小 | KiB 还是 KB；Tooltip 450 还是 600；是否支持拼音 |
| G `persist-io` | #10、#11 | config、vt、ai、proto | **立即可做** | 与 UI 包没有交集 | 无 |
| B `copy-catalog` | #7、#8、#14 | 领域 catalog 加 glossary 加 check-arch 护栏 | 与 A、G 并行 | 和 C 都会改文案，C 采用 B 的术语表 | 术语表；"在线"还是"已连接"；连接中的颜色 |
| F `keymap` | #9 | config 加 shell | 与 A、B、G 并行 | C 的菜单提示依赖 `hint()` | 是否去掉终端里写死的 ⌘F、⌘C、⌘V |
| C `confirm` | #2（加撤销规则） | shared 组件或 zenit Modal 预设，加 `confirmFor` 纯函数 | 在 0 和 B 之后 | 与 C′ 都改 `workspace.zig`，但区域不同 | 载体规则；哪些操作改成撤销；按钮文案 |
| C′ `menu-model` | #3 | 原生 Menu 加菜单 Descriptor；上游补 header 项 | 在 0 和 F 之后，与 C 并行 | 同上 | 无（技术统一） |
| D `dismiss-stack` | #1 | 接入 `OverlayHost` | 在 title-click 和 float-chrome 之后 | 触及所有浮层，最好单独做 | 同级面板的 Esc、外部点击、初始焦点规则 |
| E `panel-header` | #4、#5 的空状态和加载部分、#15 | 卡片注册表头部 Descriptor 加 EmptyState；上游候选 `Empty` | 在 float-chrome 之后，可与 D 并行（D 管行为，E 管结构） | 视觉回归面最大 | 计数格式；空状态是否带说明；AI 头部是否算例外 |

建议补到 zenit 上游的能力：
- Popover 的 `close_delay_ms`（悬停离开宽限，#12）
- `Empty` 空状态组件（#4、#5）
- Menu 的分组标题项（#3）
- 可选：Modal 的确认预设（#2）

## 取证与安全记录
- 截图：`screens/light-*.png` 和 `screens/dark-*.png`；行为记录在 `screens/report-*.json`；运行日志在 `e2e/`；探针脚本在 `tools/probe.ts`。
- 采集限制：
  - "关闭 SSH 会话"的确认这一步没有取到：探针按 ⌘W 时作用在了本地页签上，`ssh-close-confirm.png` 实际是本地确认框。远程会话的确认结论以代码为准（`workspace.zig:4877`）。
  - "清空会话记录"按钮在没有记录时是禁用的，截图里只看到禁用光标。行内确认的结论以代码为准。
  - 设置的"清理记录"弹窗没有定位到（legacy 和 yix 的 test_id 不同），结论以代码为准。
- 每轮前后检查真实钥匙串 `com.zerowork` 计数，结果始终为 0（`keychain.log`）。真实家目录的比对结果见交付说明。

---

## 用户拍板（2026-11-14）
1. **同级面板**：一律统一。Esc 和点击外部都关闭；打开后焦点进入面板，关闭后回到触发按钮。需要常驻查看的（例如传输），另外提供"作为浮动卡片打开"。
2. **确认框**：
   - 可撤销的操作直接执行，并弹带"撤销"的 Toast。
   - 不可逆的操作弹原生 Modal 确认，按钮文案写成"动词 + 对象"，用危险样式。
   - 取消按钮旁弹出的小确认框。
3. **术语表**：
   - 保存的配置叫"主机"，已连上的叫"会话"，不再用"连接"指这两者；
   - 永久去掉叫"删除"，从列表或组里拿出叫"移除"；
   - 统一用"认证"和"已连接"；
   - 统一用"关闭页签"，会断开连接时在确认框里说明。
4. **机制与细节**：
   - OverlayHost 和 shortcut_router 接入，作为唯一入口；
   - 字节单位用 1024 进制、IEC 写法：B / KiB / MiB / GiB / TiB，速率写 KiB/s、MiB/s；保留 1 位小数，整数值不带 ".0"（"64 KiB"、"1.5 MiB"、"2 MiB"）。（2026-11-14 改判，用户原话"那你用KiB/MiB吧"，取代此前的"KB/MB、1000 进制"；units-iec）；
   - 提示延迟用 zenit 默认值；
   - 搜索支持拼音首字母；
   - 面板计数统一写"N 条"；
   - 空状态一律带说明文字。

### confirm-undo 之后的补充判定（主会话，2026-11-14）
- **设置窗口里的草稿删除**（移除 MCP/技能、删除服务提供方/模型、移除背景图片）：保存前都可以用保存栏的"撤销"恢复，所以直接执行，不弹确认，也不弹撤销 Toast，由保存栏负责撤销。服务提供方/模型现有的确认框去掉。
- **AI 的"回退本回合"和"移除排队消息"**：走 `undoable`，直接执行并弹出撤销 Toast。
- **多按钮对话框**（设置的放弃/保存、主机密钥首连四选一、传输冲突、更新流程）：保留原生 Modal，只统一文案和危险样式。

### 拍板附录：菜单项顺序与分组（menus 包，2026-11-14）

规则只定一处：`src/features/shell/model/menu_spec.zig` 的 `arrange`。每个菜单只声明条目（`menu_spec.Entry`），
排列、分隔线、快捷键文字都由它和投影 `src/features/shell/view/app_menu.zig` 的 `build` 给出；菜单只经 `app_menu`
挂载（原生 `W.Menu`），不再有手画的菜单列表。

1. **常用操作在前**：声明顺序就是常用程度。`group` 从 0 开始，0 是常用组（触发这个菜单的人最可能要做的事：连接、
   复制粘贴、重命名、颜色……），组号越大越靠后。
2. **组内保持声明顺序，组与组之间一条分隔线**；分组标题（`kind = .header`，原生 `MenuItem.kind = .header`，上游补）
   开启一组，标题前也有分隔线（第一行除外）。分隔线不出现在首尾，不连续出现。
3. **危险操作一律放最后**：`danger = true` 的条目不论声明在哪一组，都排到最后单独成组，前面一条分隔线；危险样式只用
   原生 `danger`（整行红色）。
4. **快捷键文字只从快捷键路由取**：条目写 `command`（`shortcut_router.Command`），右侧文字是路由按当前 `[keys]` 给的
   组合，没有组合就不显示；手势、“@ts”这类不是按键组合的说明写在 `note`。
5. **不可用要写原因**：说得出原因的写 `disabled_reason`（原生显示在标题后，也是无障碍描述），不再把原因拼进标题
   （“复制（未选中内容）”改为标题“复制”、后面以次要色写“未选中内容”）。
6. **菜单只发出动作**：选中只把条目 id 交回宿主；危险项选中后是弹确认还是做完给“撤销”，由动作的执行方决定
   （confirm-undo 包），菜单不自己确认。
7. **Tooltip 不盖菜单**：zenit 上游层级规则（`OverlayStack.tooltipBeneathOverlay`）——触发控件在菜单之下的提示，
   在菜单打开的同一帧降到菜单下面、下一帧关闭；菜单行自己的提示不受影响。
