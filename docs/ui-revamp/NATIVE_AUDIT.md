# ZeroWork 基础组件原生化盘点（NATIVE_AUDIT）

日期：2026-11-12。基于集成分支当前尖端（`7338c3b0`，分支 `feat/ui-arch-revamp`）。

**硬性规则**：ZeroWork 的基础组件一律只用 zenit 原生组件，不许手搓，不许用 inline / `paint*` / `tune*` 覆盖，不许用 Yss 模仿；外观以 zenit 默认 token 为准；缺能力补上游。本文件是按此规则对全仓库的盘点与替换清单。

**方法与精度**：全部为静态阅读（grep / 读源码）所得，未构建、未运行。所有计数为下限（跨行写法、宏生成代码、同名函数可能漏计）。统计均排除 tests / preview / fixture / acceptance。“状态”列：`待替换` 表示按规则必须替换；`待判定` 表示需产品或设计先确认定位。

---

## 最重要的发现

1. **Modal 遮罩被下游改成了全透明**（这就是“所有 modal 没有 backdrop 透明底铺垫”的原因）。
   - zenit `W.Modal` 自带遮罩：`overlay_stack.overlay(.barrier = .{ .color = p.overlay_color orelse t.tokens.color.overlay })`（`vendor/zenit/src/ui/components/modal/mod.zig` 约 L127）。
   - zenit 默认 `overlay` 为半透明黑：light `#09090b66`，dark `#00000099`（`vendor/zenit/src/tokens/default.json:114`）。
   - 下游 `src/shared/ui/theme/app_theme.zig:8` 定义 `pub const modal_barrier = ui.Color.TRANSPARENT`，`widgetTokensFrom` 的 L657 写了 `t.overlay = modal_barrier;`，于是 34 个 `W.Modal` 的遮罩 alpha 全为 0。
   - 这是明文规则：`docs/DESIGN/DESIGN_STANDARDS.md:415` 写“Modal 及自定义模态遮罩统一使用 `app_theme.modal_barrier`，保持全透明”。
   - 另外 Modal 的 `.background = ...overlay` 是对话框面板底色（zenit 默认 `bg-primary`），不是遮罩；没有任何调用点传过 `overlay_color`。
   - 修复核心：删除 L657 与 L8 常量，改 DESIGN_STANDARDS 该条规则；手工拼的 B 类遮罩改用 `W.Modal`。
2. **`W.Button` 约 300 处 `base_style` 覆盖**：非测试代码 363 处 `widgets.Button(` 挂载，其中 302 处同行带 `base_style`，343 处带 `variant`（按“同一行文本”估，跨行未计入，为下限）。外加 `stylePrimary` 41 处、`styleActionText` 4 处。原生 Button 的外观几乎全被重写。
3. **zenit 的 Glass 系列组件在应用里零引用**：`GlassBox`、`GlassGroup`、`GlassSlider`、`GlassToggle`、`GlassToolbar`、`GlassNavigationBar`、`GlassTabBar`、`GlassBottomToolbar`、`GlassButton` 在 `src/**/*.zig`、`*.yix`、`*.yss` 中无任何引用。下游全部用样式（半透明底 + 描边 + 阴影，或 `BoxStyle.glass = overlayGlass()`）模仿，约 45 个样式文件。
4. **覆盖面全局数字**：非测试 `setStyleInline` 共 1564 处；`children.items[` 按下标取子节点共 204 处（详见清单 4 末尾）。

---

## 清单 1：对话框 / 模态

### A 类：原生 `ui.widgets.Modal`（34 处）

共同特征：遮罩走 token `overlay`（即全透明）；带 zenit Esc 关闭与焦点陷阱（`trap=true, auto_focus, restore`）；挂窗口 portal；多数调用点还传 `.background = overlay` 并叠加各自 `S.panel()` 的 `.glass`（面板外观被覆盖）。

| # | 文件:行 | feature | 用途 | 点遮罩 | test_id 前缀 | e2e 引用 | 状态 |
|---|---|---|---|---|---|---|---|
| 1 | `src/features/ai/attachments/view/ai_attachments_view.zig:224` | ai | AI 附件预览 | 关 | `ai.attachment.preview` | ai_local_picker / ai_preview_recovery / ai_remote_picker | 已清理面板覆盖（H-modals-ws：不传 `.background`，dialog 不再覆盖底色 / 玻璃 / 描边 / 圆角 / 阴影、不叠窗口材质，面板回到 zenit 默认；尺寸与正文布局覆盖保留，内容控件覆盖留 P5） |
| 2 | `src/features/ai/attachments/view/ai_image_attachments_view.zig:108` | ai | 图片预览 | 关 | `ai.image.preview` | ai_local_picker / ai_preview_recovery / ai_v3_states | 已清理面板覆盖（H-modals-ws：不传 `.background`，dialog 不再覆盖底色 / 玻璃 / 描边 / 圆角 / 阴影、不叠窗口材质，面板回到 zenit 默认；尺寸与正文布局覆盖保留，内容控件覆盖留 P5） |
| 3 | `src/features/ai/attachments/view/ai_remote_picker.zig:85` | ai | 远程文件选择 | 关 | `ai.remote.*` | ai_remote_picker / ai_remote_vt | 已清理面板覆盖（H-modals-ws：不传 `.background`，dialog 不再覆盖底色 / 玻璃 / 描边 / 圆角 / 阴影、不叠窗口材质，面板回到 zenit 默认；尺寸与正文布局覆盖保留，内容控件覆盖留 P5） |
| 4 | `src/features/ai/host/child_dialog.zig:52` | ai | AI 子任务对话框 | 关 | `ai.child.dialog` | ai_child_dialog | 已清理面板覆盖（H-modals-ws：不传 `.background`，dialog 不再覆盖底色 / 玻璃 / 描边 / 圆角 / 阴影、不叠窗口材质，面板回到 zenit 默认；尺寸与正文布局覆盖保留，内容控件覆盖留 P5） |
| 5 | `src/features/ai/sessions/view/ai_sessions_view.zig:60` | ai | 会话相关确认 | 关 | `ai.history.*` | ai_child_dialog 等 | 已清理面板覆盖（H-modals-ws：不传 `.background`，dialog 不再覆盖底色 / 玻璃 / 描边 / 圆角 / 阴影、不叠窗口材质，面板回到 zenit 默认；尺寸与正文布局覆盖保留，内容控件覆盖留 P5） |
| 6 | `src/features/ai/sessions/view/ai_sessions_view.zig:87` | ai | 会话历史 | 关 | `ai.history` | ai_conversation_input / ai_history_performance | 已清理面板覆盖（H-modals-ws：不传 `.background`，dialog 不再覆盖底色 / 玻璃 / 描边 / 圆角 / 阴影、不叠窗口材质，面板回到 zenit 默认；尺寸与正文布局覆盖保留，内容控件覆盖留 P5） |
| 7 | `src/features/connections/auth/host/plugin_challenge_presenter.zig:75` | connections | 插件认证挑战 | 不关 | `plugin.challenge.*` | auth_challenge / connection_credentials 等 | 已清理面板覆盖（H-modals-ws：不传 `.background`，dialog 不再覆盖底色 / 玻璃 / 描边 / 圆角 / 阴影、不叠窗口材质，面板回到 zenit 默认；尺寸与正文布局覆盖保留，内容控件覆盖留 P5） |
| 8 | `src/features/connections/auth/view/auth_challenge_view.zig:407` | connections | 认证挑战、主机密钥（内联形态不挂 Modal） | 不关 | `auth.challenge.*` | auth_challenge_native 等 | 已清理面板覆盖（H-modals-ws：不传 `.background`，dialog 不再覆盖底色 / 玻璃 / 描边 / 圆角 / 阴影、不叠窗口材质，面板回到 zenit 默认；尺寸与正文布局覆盖保留，内容控件覆盖留 P5） |
| 9 | `src/features/connections/progress/view/connection_details_view.zig:433` | connections | 连接节点详情 | 关 | `connection.details` | remaining_connection / reported_connection | 已清理面板覆盖（H-modals-ws：不传 `.background`，dialog 不再覆盖底色 / 玻璃 / 描边 / 圆角 / 阴影、不叠窗口材质，面板回到 zenit 默认；尺寸与正文布局覆盖保留，内容控件覆盖留 P5） |
| 10 | `src/features/connections/progress/view/connection_logs_view.zig:82` | connections | 连接日志 | 关 | `connection.logs` | remaining_connection / top_toolbar_popovers | 已清理面板覆盖（H-modals-ws：不传 `.background`，dialog 不再覆盖底色 / 玻璃 / 描边 / 圆角 / 阴影、不叠窗口材质，面板回到 zenit 默认；尺寸与正文布局覆盖保留，内容控件覆盖留 P5） |
| 11 | `src/features/connections/socks/view/socks_config_view.zig:97` | connections | 端口转发配置 | 不关 | `socks.config` | forward_controls / reported_connection | 已清理面板覆盖（H-modals-ws：不传 `.background`，dialog 不再覆盖底色 / 玻璃 / 描边 / 圆角 / 阴影、不叠窗口材质，面板回到 zenit 默认；尺寸与正文布局覆盖保留，内容控件覆盖留 P5） |
| 12 | `src/features/connections/socks/view/socks_exposure_confirm.zig:64` | connections | 监听暴露确认（`0.0.0.0`） | 不关 | `forward.exposure` | forward_controls | 已清理面板覆盖（H-modals-ws：不传 `.background`，dialog 不再覆盖底色 / 玻璃 / 描边 / 圆角 / 阴影、不叠窗口材质，面板回到 zenit 默认；尺寸与正文布局覆盖保留，内容控件覆盖留 P5） |
| 13 | `src/features/connections/wizard/view/wizard.zig:296` | connections | 连接编辑器（有 `window` 时走独立窗口，见 C 类） | 不关 | `wizard.dialog` / `wizard.overlay` | compact_connection / connection_route_draft 等 | 已清理面板覆盖（H-modals-ws：不传 `.background`，dialog 不再覆盖底色 / 玻璃 / 描边 / 圆角 / 阴影、不叠窗口材质，面板回到 zenit 默认；尺寸与正文布局覆盖保留，内容控件覆盖留 P5） |
| 14 | `src/features/files/view/file_copy_view.zig:40` | files | 传输确认 | 不关 | `files.copy.*` / `transfer.confirmation` | sftp_conflict / mist_workspace 等 | 已清理面板覆盖（H-modals-ws：不传 `.background`，dialog 不再覆盖底色 / 玻璃 / 描边 / 圆角 / 阴影、不叠窗口材质，面板回到 zenit 默认；尺寸与正文布局覆盖保留，内容控件覆盖留 P5） |
| 15 | `src/features/history/view/record_cleanup_view.zig:41` | history | 清理记录确认 | 不关 | `settings.record-cleanup` | settings_confirmation_controls | 已清理面板覆盖（H-modals-ws：不传 `.background`，dialog 不再覆盖底色 / 玻璃 / 描边 / 圆角 / 阴影、不叠窗口材质，面板回到 zenit 默认；尺寸与正文布局覆盖保留，内容控件覆盖留 P5） |
| 16 | `src/features/settings/host/settings_host.zig:1237` | settings | 未保存更改、恢复默认确认 | 不关 | `settings.confirmation.*` | appearance / ai_extensions 等 | **已替换（H-save）**：`.yix` 窗口改为 `view/save_bar.yix` 的 `<W.Modal>` 默认外观（默认遮罩、默认不透明面板，原先 `.background = overlay` 让面板半透明）、原生按钮无覆盖；宿主命令式弹窗只剩 `.legacy` 外壳在用（3f 删除） |
| 17 | `src/features/settings/view/ai_model_editor.zig:64` | settings | 模型编辑器 | 关 | `settings.ai.model.*` | model_editor / ai_settings_catalog 等 | **已替换（F-set-ai）**：`.yix` 窗口改为 `view/panes/ai_dialogs.yix` 的 `<W.Modal>` 默认外观（只在打开时挂载、`autoFocus`）；旧文件只剩 `.legacy` 外壳在用（S-15） |
| 18 | `src/features/settings/view/application_data_cleanup_view.zig:42` | settings | 清除全部数据确认 | 不关 | `data.cleanup.*` | async_logging / v02_macos_data / settings_confirmation_controls | **已替换（set-modals）**：`.yix` 窗口改为 `view/data_cleanup.yix` 的 `<W.Modal>` 默认外观（默认遮罩、默认不透明面板与标题栏，原先 `.background = overlay` + 玻璃材质 + 自定圆角 / 阴影 / 固定高 300）、原生 secondary / danger 按钮无覆盖（原先 `base_style` 借记录清理的按钮样式）；流程状态归 view-model（`model/data_cleanup.zig`）。旧命令式对话框只剩 `.legacy` 外壳在用（S-15，3f 删除） |
| 19 | `src/features/settings/view/keybinding_picker.zig:14` | settings | 快捷键录制 | 不关 | `settings.keybinding.*` | keybinding_v3 / theme_auxiliary | 已替换（`.yix` 路径改为行内录制：原生 `W.Pressable` 键帽区 + 原生 `W.Kbd` 键帽（set-adopt 起；原为 `W.Tag`，G32），不再弹对话框；文件随 `.legacy` 外壳留到 3f 删除，S-15） |
| 20 | `src/features/settings/view/panes/settings_plugins.zig:308` | settings | 插件详情 / 信息 | 关 | `settings.plugins.*`（`mountDetails`） | 未搜到专属 id | **已替换（F-set-plugins）**：`.yix` 路径改为两级导航，不再弹对话框——版本是详情页的只读值，“插件随应用更新”在头部卡片下的管理说明里，权限全文是原生 `W.Tooltip`（“?” 原生 ghost 图标按钮）；旧文件随 `.legacy` 外壳留到 3f 删除（S-15） |
| 21 | `src/features/settings/view/provider_delete_dialog.zig:24` | settings | 删除服务提供方确认 | 关 | `settings.ai.delete.*` | provider_v3 | **已替换（F-set-ai）**：`ai_dialogs.yix` 的 `<W.Modal>` 默认外观，焦点在“取消”；旧文件只剩 `.legacy` 外壳（S-15） |
| 22 | `src/features/terminal/view/local_close_view.zig:34` | terminal | 本地终端关闭确认 | 关 | `local.close.*` | ai_auto_scope / ai_child_dialog 等 | 已清理面板覆盖（H-modals-ws：不传 `.background`，dialog 不再覆盖底色 / 玻璃 / 描边 / 圆角 / 阴影、不叠窗口材质，面板回到 zenit 默认；尺寸与正文布局覆盖保留，内容控件覆盖留 P5） |
| 23 | `src/features/terminal/view/terminal_surface_input.zig:571` | terminal | 粘贴确认 | 不关 | `terminal.paste.heading` | 无 | 无面板覆盖（H-modals-ws 核实：本来就是 zenit 默认面板） |
| 24 | `src/features/transfer/view/transfer_conflict_view.zig:143` | transfer | 传输冲突 | 不关 | `transfer.conflict.*` | sftp_conflict / sftp_upload 等 | 已清理面板覆盖（H-modals-ws：不传 `.background`，dialog 不再覆盖底色 / 玻璃 / 描边 / 圆角 / 阴影、不叠窗口材质，面板回到 zenit 默认；尺寸与正文布局覆盖保留，内容控件覆盖留 P5） |
| 25 | `src/features/transfer/view/transfer_panel.zig:332` | transfer | 新建传输确认 | 不关 | `transfer.confirmation.*` | sftp_retained 系列 | 已清理面板覆盖（H-modals-ws：不传 `.background`，dialog 不再覆盖底色 / 玻璃 / 描边 / 圆角 / 阴影、不叠窗口材质，面板回到 zenit 默认；尺寸与正文布局覆盖保留，内容控件覆盖留 P5） |
| 26 | `src/features/update/view/app_update_view.zig:87` | update | 应用更新 | 关 | `update.*` | app_update_check / app_update_full 等 | 已清理面板覆盖（H-modals-ws：不传 `.background`，dialog 不再覆盖底色 / 玻璃 / 描边 / 圆角 / 阴影、不叠窗口材质，面板回到 zenit 默认；尺寸与正文布局覆盖保留，内容控件覆盖留 P5） |
| 27 | `src/features/workspace/view/group_join_view.zig:19` | workspace | 加入会话组（唯一带 `.title` 的） | 关 | `groups.join.*` | context_menu_width / group_mixed_resize | 已清理面板覆盖（H-modals-ws：不传 `.background`，dialog 不再覆盖底色 / 玻璃 / 描边 / 圆角 / 阴影、不叠窗口材质，面板回到 zenit 默认；尺寸与正文布局覆盖保留，内容控件覆盖留 P5） |
| 28 | `src/features/workspace/view/workspace.zig:3876` | workspace | 关闭会话组确认 | 关 | `groups.close.confirm` / `groups.close.partial` | ai_auto_scope / ai_child_dialog 等 | 已清理面板覆盖（H-modals-ws：不传 `.background`，dialog 不再覆盖底色 / 玻璃 / 描边 / 圆角 / 阴影、不叠窗口材质，面板回到 zenit 默认；尺寸与正文布局覆盖保留，内容控件覆盖留 P5） |
| 29 | `src/plugins/bmc_ikvm/editor.zig:965` | plugin bmc | 管理测试日志 | 关 | `bmc.editor.log_*` | bmc_kvm 系列 | 已清理面板覆盖（H-modals-ws：不传 `.background`，dialog 不再覆盖底色 / 玻璃 / 描边 / 圆角 / 阴影、不叠窗口材质，面板回到 zenit 默认；尺寸与正文布局覆盖保留，内容控件覆盖留 P5） |
| 30 | `src/plugins/bmc_ikvm/views.zig:1951` | plugin bmc | 断开确认 | 关 | `bmc.*` | bmc_kvm 系列 | 已清理面板覆盖（H-modals-ws：不传 `.background`，dialog 不再覆盖底色 / 玻璃 / 描边 / 圆角 / 阴影、不叠窗口材质，面板回到 zenit 默认；尺寸与正文布局覆盖保留，内容控件覆盖留 P5） |
| 31 | `src/plugins/bmc_ikvm/views.zig:2122` | plugin bmc | 连接日志 | 关 | `bmc.connection_log` | bmc_kvm 系列 | 已清理面板覆盖（H-modals-ws：不传 `.background`，dialog 不再覆盖底色 / 玻璃 / 描边 / 圆角 / 阴影、不叠窗口材质，面板回到 zenit 默认；尺寸与正文布局覆盖保留，内容控件覆盖留 P5） |
| 32 | `src/plugins/bmc_ikvm/views.zig:2343` | plugin bmc | 启动顺序（只读） | 关 | `bmc.boot.order` | bmc_kvm 系列 | 已清理面板覆盖（H-modals-ws：不传 `.background`，dialog 不再覆盖底色 / 玻璃 / 描边 / 圆角 / 阴影、不叠窗口材质，面板回到 zenit 默认；尺寸与正文布局覆盖保留，内容控件覆盖留 P5） |
| 33 | `src/plugins/remote/editor.zig:745` | plugin remote | 连接编辑器壳 | 不关 | `wizard.*` | wizard / compact_connection | 已清理面板覆盖（H-modals-ws：不传 `.background`，dialog 不再覆盖底色 / 玻璃 / 描边 / 圆角 / 阴影、不叠窗口材质，面板回到 zenit 默认；尺寸与正文布局覆盖保留，内容控件覆盖留 P5） |
| 34 | `src/plugins/remote/editor.zig:3108` | plugin remote | 从已有主机复制 | 关 | `wizard.copy.dialog` | wizard_copy / ui_scroll_performance | 已清理面板覆盖（H-modals-ws：不传 `.background`，dialog 不再覆盖底色 / 玻璃 / 描边 / 圆角 / 阴影、不叠窗口材质，面板回到 zenit 默认；尺寸与正文布局覆盖保留，内容控件覆盖留 P5） |

“点遮罩”取自各调用点的 `close_on_overlay`：显式 `true`（#17、#20、#21）或未写（zenit 默认 `true`）为“关”，显式 `false` 为“不关”。

### B 类：手工拼的遮罩 / 全屏层（均没有半透明遮罩）

| # | 文件:行 | 用途 | 拼法 | 遮罩 | 点遮罩关闭 | Esc | 焦点陷阱 | 挂载位置 | 状态 |
|---|---|---|---|---|---|---|---|---|---|
| B1 | `src/features/workspace/view/workspace.zig:4322`（`mountHostKeyConfirm`，scrim L4326 `z_index=350`） | 主机密钥首连确认 | `ui.box` 绝对定位铺满 + 卡片（`overlay` 色 + `glass` + 手写阴影） | 有节点，背景 `modal_barrier`（全透明）；未设 `hit_behavior=.opaque`，是否拦截点击待确认 | 无 | 有（卡片 `on_key_down`，调 `rejectHostKey`） | 无 `focus_scope` | `terminal_area` 子节点，非窗口 portal | 已替换（H-modals-ws：原生 `W.Modal`，默认遮罩与面板、窗口 portal、焦点陷阱；Esc = 拒绝；生产窗口里主机密钥走认证挑战组件，此确认框只在没挂连接宿主的 runner 里出现） |
| B2 | `workspace.zig:4790`（`mountCloseConfirm`，scrim L4800 `z_index=300`） | 标签页关闭确认（SSH / 传输 / AI / SOCKS5 风险行） | 同 B1 | 全透明，同上 | 无 | 有（`onCloseConfirmKeyDown`） | 无 | `terminal_area` | 已替换（H-modals-ws：原生 `W.Modal`，默认遮罩与面板、窗口 portal、焦点陷阱；Esc = 取消，默认焦点在“取消”；“仍然关闭”改原生 danger 变体） |
| B3 | `src/features/history/host/history_host.zig:66`（`z_index=500`，`hit_behavior=.opaque`） | “会话记录”整窗面板 | 全覆盖 box + 卡片 | 无底色，实质为不透明遮挡层 | 未见 | 未核对 | 有（`focus_scope={trap=true}`） | 主窗口 root | 待用户判定（H-modals-ws 核实：左上角停靠的 300 宽面板 + 整窗透明拦截层，点面板外 / Esc 关闭，属轻量浮层而非模态；建议改原生 `W.Popover` 或 pane，见报告） |
| B4 | `src/app/main_window.zig:540-550`（`help_overlay`，`z_index=250`） | 命令帮助卡覆盖层 | box，背景硬编码 `rgba(236,255,244,102)`（浅绿半透明，不走主题） | 有可见底色但不是主题遮罩 | 无 | 有（nav_host 全局键：Esc 隐藏） | 无 | `terminal_area` | 已替换（h-helpcard：用户判定 D-5“改用原生 Modal”。`features/terminal/view/command_help.yix` 的原生 `W.Modal`：默认遮罩（主题 overlay token，硬编码浅绿删除）、默认面板（不传 background、不覆盖圆角 / 描边 / 阴影、不叠材质）、原生标题与关闭、窗口 portal、焦点陷阱；显隐是 `AppNavHost.help_open`（`*Signal(bool)`），触发条件不变；Esc / 点遮罩 / 标题栏关闭 / 脚注原生“关闭”按钮都关，关闭后焦点回终端。脚注“关闭”按钮是为了让只读 Modal 打开即有焦点目标（缺口 G43）。组件测试 `terminal/tests/command_help_tests.zig`；真实窗口仍触发不到，见 YIX_SPIKE“命令帮助卡（h-helpcard）”） |
| B5 | `main_window.zig:266`，样式 `src/features/shell/view/shell_styles.zig:99 settingsBackdrop`（`z_index=400`） | 设置面板占位 / 回退容器 | `display=.none`，背景 `modal_barrier` | 透明且隐藏 | 无 | 无 | 无 | 主窗口 root | 保留（H-modals-ws 核实为活路径：`settings.overlay` 节点是 SettingsHost 无设置窗口时的占位 panel / nav_list / content，由 retained_panel 托管、始终 `display=none`；只是背景样式从不可见。归设置包处理） |
| B6 | `src/features/connections/socks/view/socks_config_styles.zig:10`（`S.overlay()`，`z_index=80`） | 端口转发配置旧遮罩样式 | 样式函数 | 透明 | - | - | - | - | 已删除（H-tokens `61872142` 已随 `modal_barrier` 一并删掉） |

### C 类：独立原生窗口（不是模态）

- 设置窗口：`aux_window.Slot`，`src/app/process_state.zig:11`、`src/features/settings/view/settings_shell.zig:30`。
- 连接编辑器窗口形态：`src/features/connections/wizard/view/wizard.zig:59`（`window_spec`），`self.window != null` 时走窗口，否则走上面 A#13。
- 传输管理窗口：`src/features/transfer/view/transfer_manager_view.zig:457` 有 `native_window` 分支（待确认）。
- 插件窗口：`src/features/shell/host/plugin_window_host.zig`（待确认）。

### 非模态的锚定 Popover“对话”（供对照，不属遮罩问题）

`ai_close_confirmation_view.zig:41`（AI 关闭确认，`.a11y_role=.dialog`）、`connections/assets/host/asset_group_host.zig:87`、`connections/assets/view/asset_action_view.zig:202`、`shell/view/tab_rename.zig:52`、`connections/quick_connect/view/quick_connect_view.zig:113`、`connections/progress/view/connection_details_view.zig:110`、`ai/host/child_dialog.zig:97`。

H-modals-ws 核实（2026-11-13）：7 处都是原生 `W.Popover`，没有整窗遮罩、没被改成全透明；但浮层外壳都有外观覆盖（`chrome` / `dialog` 的 `setStyleInline(S.panel/chrome/renameDialog…)`，`tab_rename` 的 `bindMaterial(overlay)`，`connection_details` 的 `material.isolate(chrome)`，`asset_group_host` 的阴影 / 内阴影），留给各 feature 的 P5 处理。

### 统计

A：34；B：6（没有遮罩：B1、B2、B3、B5、B6；B4 有硬编码浅绿底）；C：3 到 4。

最值得先改的 5 处：
1. `app_theme.zig:657` / `:8` 的 `modal_barrier`，一处修好 34 个 Modal 遮罩。
2. 同步改 `DESIGN_STANDARDS.md:415`，并检查依赖透明遮罩的 e2e / 像素基线。
3. B1 主机密钥确认改 `W.Modal`。
4. B2 关闭确认改 `W.Modal`。
5. B3 / B4 / B5 / B6 先确认定位再改；B4 的硬编码浅绿去掉（h-helpcard 已改原生 Modal、删掉浅绿底）。

---

## 清单 2：单选 / 复选 / 分段选择，与 `widgetTokensFrom` 映射

zenit 提供 `Checkbox`、`Radio`、`RadioGroup`、`Switch`、`Tabs`，没有 `Segmented`。原生使用：`W.Switch` 约 15 处、`W.Checkbox` 约 17 处、`W.RadioGroup` 6 处（均含 yix 之外的 zig 挂载）。下表只列手工拼的或外观被下游改写的。

### 2.1 完全手工拼的

| 文件:行 | 用途 | 拼法 | 颜色来源 | 调用点 | 对应 zenit 原生 | 状态 |
|---|---|---|---|---|---|---|
| `src/features/ai/composer/view/ai_composer_controls_view.zig:439`（`mountPermissions`，圆点 L449，切换 L1181） | AI 权限模式单选（确认 / 自动） | `W.Button` ghost 整行 + `ui.icons.circle`，选中 `setAsset("check")` | `fg_2` | 2 项 | `W.RadioGroup` | 已替换（ai-redesign-a）：权限 / 运行方式改为 menus 包的原生 `W.Menu`（单选勾、说明、Tag） |
| 同文件 `:478-526`（执行模式，圆点 L485，切换 L526） | 执行模式单选（auto / ask / isolated_exec / attached_pty / new_pty） | 同上，`accent` 色 | `S.theme.current().accent` | 5 项 | `W.RadioGroup` | 已替换（ai-redesign-a）：权限 / 运行方式改为 menus 包的原生 `W.Menu`（单选勾、说明、Tag） |
| `src/features/settings/view/panes/appearance_view.zig:263`（`themeStrip`）及 `:560-585`（主题网格 tile） | 主题选择：卡片式单选 | `W.Button` ghost + 色板 box + 选中 `icons.check` + `a11y.selected/pressed`，选中 accent 2pt 描边 | `accent_ink`、`record.ui_tokens.*` | 2 种布局，每主题 1 个 | zenit 无“卡片式单选” → 需补上游（或 `Card selected` + RadioGroup 语义） | 已替换（F-set-appearance，`.yix` 路径）：卡片是 `W.Pressable`（自定义内容：色板 + 名称），选中标记是原生 `W.Radio`，选中描边是数据色板的一部分；网格 tile 是死代码，未移植；旧文件随 `.legacy` 留到 3f（S-15） |
| 同文件 `:1436-1450` | 背景对齐 3x3 九宫格单选 | 9 个 `W.Button`，`ui.icons.circle` | `S.plainButton(…, chosen)` | 9 个 | zenit 无二维单选 → 需补上游 | 已替换（F-set-appearance）：`W.Popover` 里 3 × 3 的 `W.Pressable` + 原生 `W.Radio`，test_id `settings.alignment.<名字>` 不变 |
| `src/features/ai/approvals/view/ai_host_approval_route_styles.zig:1-30`（用于 `ai_host_approval_view.zig`） | 主机审批运行方式分段 | box 轨道 `fg_1.withAlpha(18)` 半径 8 + `W.Button`，选中段抬起 | `fg_1` | 3 段 | `W.Tabs`；zenit 无 Segmented → 需补上游 | 已删除（ai-redesign-a：`ai_host_approval_view` / `ai_tool_approval_view` 在生产路径上恒为 null，随死代码一起删除） |
| `src/features/ai/composer/view/ai_composer_interaction_view.zig:144-150`（`S.routeTrack/routeSegment`） | AI 交互卡运行方式分段 | 同上 | `S` 系列 | 3 段 | 同上 | 已替换（ai-redesign-a）：原生 `W.Group` + sm `W.Button`（选中项 primary）；zenit `Tabs` 无 segmented 变体 |
| `src/features/connections/wizard/view/wizard_styles.zig:515-533`（`segmentTrack/segment/segmentLabel`） | 向导分段样式函数 | 纯样式函数 | `bg_active`、`bg_primary`、`fg_1/fg_2` | 见 2.2 | 同上 | 待替换 |
| `src/plugins/bmc_ikvm/styles.zig:264`（`segment`，用于 `views.zig:1191,1431,1777`） | BMC 画面“适应 / 原始”分段 | `W.Button` + `fit_style/original_style` 两个 `BoxStyle` signal | `accent_ink`、`fg_*` | 2 段 | 同上 | 已替换（usage-b5c-native-controls：`W.Tabs` segmented，`S.segment` 与两个样式信号删除） |

### 2.2 原生组件但外观被下游改写

| 文件:行 | 组件 | 覆盖方式 | 状态 |
|---|---|---|---|
| `src/plugins/remote/editor.zig:3790-3818`（`paintAuthLabels`，5 处调用；RadioGroup 在 L3176 / L3280） | `W.RadioGroup`（认证方式 / 压缩） | 画成分段轨道（`S.segmentTrack/segment/segmentLabel`），隐藏圆圈 `circle.setDisplay(.none)`，每帧改选中段背景和字色 | 待替换 |
| `src/features/transfer/view/transfer_conflict_view.zig:182-194`（样式 `transfer_conflict_styles.zig:59 radioGlyph`） | `W.RadioGroup`（传输冲突） | 隐藏原生圆点子节点，换 16px `ui.icons.circle` 自绘选中态；行样式 `choice(selected)` 用 `popupSelection()` | 已替换（usage-b5c-native-controls：原生 `W.RadioGroup` 默认外观，“覆盖”的后果写在原生选项说明里，见 `transfer_conflict.yix`） |
| `src/features/ai/composer/view/ai_composer_interaction_view.zig:153-170` | `W.RadioGroup`（AI 提问选项，7 个） | 行 `setStyleInline(S.option)`，圆圈改 12px 并描边 `fg_3`，隐藏 label 子节点，手涂选中行底色（L314） | 待替换 |
| `src/features/settings/view/panes/appearance_view.zig:1494-1531` | `W.RadioGroup`（应用图标） | 行高 40，去按钮底 | 已替换（F-set-appearance）：原生默认外观，无覆盖 |
| `src/features/files/view/file_workspace_view.zig:1688`（`styleFileCheckbox`，2 处） | `W.Checkbox` | 每次主题发布重涂方框：背景 `action_accent` 或 `checkbox_bg`，圆角 2，边框 0 | 待替换 |
| `src/plugins/remote/editor.zig:3819`（`paintCheckboxLabels`，4 处）、`src/plugins/bmc_ikvm/editor.zig:1105`（`paintCheckboxTypography`） | `W.Checkbox` | 标签字号与颜色 | 待替换 |
| `src/features/settings/view/settings_styles.zig:600 paintControlText`（调用：`ai_model_editor.zig`、`settings_styles.zig`） | 通用 | 递归把控件文字改 `fg_1` | 待替换 |
| `src/features/settings/view/panes/appearance_view.zig:1093` | `W.Tabs`（光标形状） | 用 zenit `Tabs`，外观覆盖待确认 | 已替换（F-set-appearance）：`.yix` 里 `<W.Tabs variant={.pill} size={.sm}>`，只用组件参数，无覆盖 |

### 2.3 `widgetTokensFrom` 对 zenit 角色 token 的全部映射

位置：`src/shared/ui/theme/app_theme.zig:720-809`（H-opaque-popups 时的行号；原表写于 653-790）。入参 `c: Colors`，`s = stateColors(c)`（`theme_states.zig`），`dark` 选 `ui.theme.dark/light` 为基底；辅助 `insetColor(c)=stateColors(c).control`、`actionColor(c)=stateColors(c).action`、`actionForeground(…)`、`selectionColor(c)`。

| 分组 | token ← 来源表达式（原文） |
|---|---|
| overlay、基础 | `overlay = modal_barrier`（**现状**：已回到 zenit 默认，见清单 1）；`bg_base = c.app`；`bg_primary = c.surface_1`；`bg_secondary = c.surface_2`；`bg_tertiary = c.overlay`；`bg_hover = s.hover`；`bg_active = s.pressed`；`bg_focus = s.focus`；`bg_inset = c.well` **现状（H-opaque-popups 之后）**：`bg_base / bg_primary / bg_secondary / bg_tertiary / bg_inset` 改为同一调色板 RGB 的 `.withAlpha(255)`（不透明，与 zenit 默认一致），`bg_hover / bg_active / bg_focus` 不变；见下方“2.3.1 表面 token 的 alpha” |
| 前景 | `fg_primary = c.fg_1`；`fg_secondary = c.fg_2`；`fg_tertiary = s.muted_ink`；`fg_disabled = c.fg_3`；`fg_inverse = actionForeground(c.action_accent)` |
| accent | `accent = c.action_accent`；`accent_hover = s.primary_hover`；`accent_muted = selectionColor(c)`；`accent_subtle = selectionColor(c)` |
| border、focus | `border = c.border.withAlpha(255)`；`border_strong = lerp(hairline, c.fg_3.withAlpha(255), 0.25)`；`border_focus = TRANSPARENT`；`focus_ring = TRANSPARENT`；`separator = hairline`；`selection_bg = selectionColor(c)` |
| 状态色 | `success = c.ok_ink`；`success_subtle = s.feedback_ok`；`warning = c.warn_ink`；`warning_subtle = s.feedback_warn`；`danger = c.danger_ink`；`danger_subtle = s.feedback_danger`；`danger_hover = c.action_danger`；`info = c.accent_ink`；`info_subtle = s.feedback_info`；`success_alert_bg / warning_alert_bg / danger_alert_bg / info_alert_bg = s.feedback_ok / feedback_warn / feedback_danger / feedback_info` |
| button | `button_primary_bg = c.action_accent`；`button_primary_fg = actionForeground(c.action_accent)`；`button_primary_hover = s.primary_hover`；`button_primary_pressed = s.primary_pressed`；`button_danger_bg = s.danger`；`button_danger_fg = s.danger_ink`；`button_danger_hover = s.danger_hover`；`button_danger_pressed = s.danger_pressed`；`button_secondary_bg = actionColor(c)`；`button_secondary_fg = if (dark) c.fg_2 else c.fg_1` **现状（H-tokens 之后）**：`button_danger_*` / `button_secondary_*` 已回到 zenit 默认；`button_primary_*` 四个**已删除（native-buttons，用户判定 A）**：button 全部角色 token 都是 zenit 默认（例外表 T-1 已收回） |
| input | `input_bg = insetColor(c)`；`input_border = strong_hairline` |
| checkbox（Radio 复用，无 `radio_*` token） | `checkbox_bg = s.choice_off`；`checkbox_fg = s.choice_ink`；`checkbox_disabled_fg = s.choice_disabled_ink`；`checkbox_border = TRANSPARENT`；`checkbox_disabled_bg = s.choice_disabled_off`；`checkbox_disabled_border = TRANSPARENT`；`checkbox_disabled_checked_bg = s.choice_disabled_on`；`checkbox_checked_bg = s.choice_on` |
| switch | `switch_thumb_on = s.choice_ink`；`switch_thumb = s.choice_thumb_off`；`switch_track_on = s.choice_on`；`switch_track_off = s.choice_off`；`switch_disabled_thumb_off = s.choice_disabled_thumb_off`；`switch_disabled_track_on = s.choice_disabled_on`；`switch_disabled_thumb_on = s.choice_disabled_ink`；`switch_disabled_track_off = s.choice_disabled_off` |
| range | `range_track / range_fill / range_hover / range_drag / range_thumb / range_disabled / range_disabled_thumb = s.range_*` |
| progress | `progress_track = s.range_track`；`progress_fill = s.range_fill`；`progress_success = s.progress_ok`；`progress_warning = s.progress_warn`；`progress_error = s.progress_danger` |
| list / table | `list_hover_bg = s.hover`；`list_selection_bg = selectionColor(c)`；`list_selection_hover_bg = s.selected_hover`；`table_header_bg = c.surface_2` |
| tooltip | `tooltip_bg = c.overlay`；`tooltip_fg = c.fg_1` |
| 下游自定 `zw_*`（非 zenit 角色） | `zw_island_ground = c.app`；`zw_island_focus = c.surface_1`；`zw_island_rest = c.surface_2`；`zw_list_active = c.surface_1`；`zw_window_surface = c.surface_1.withAlpha(255)`；`zw_window_rest = c.surface_2.withAlpha(255)`；`zw_window_glass_hover / _pressed = lerp(window_surface, c.fg_1, 0.04 / 0.08)`；`zw_fg_faint = c.fg_3`；`zw_fg_supporting = lerp(c.fg_2, c.fg_1, min(1, transparency/50))`；`zw_primary / _to / _hover / _hover_to / _pressed / _pressed_to = s.primary*` |

### 2.3.1 表面 token 的 alpha（H-opaque-popups 清点，2026-11-13）

材质参数：`current()` 给六个材质角色按全局透明度 T（0–100）改 alpha（`app_theme.zig` 的 `material_transparency_base / _span / material_ratio`），
`app` 与 `terminal` 恒为 0。T=0 时 `surface_1 = 255`、`surface_2 = 71`、`well = 92`、`overlay = 255`、`hover = 46`、`tab_on = 82`；
T=100 时 `surface_1 = 0`、`overlay = 128`。状态色 `s.*` 的 alpha 再按 `theme_states.material_roles` 跟随对应角色。

| 发布的 token | 修前来源 → alpha | zenit 默认 | 修后 |
|---|---|---|---|
| `bg_base` | `c.app` → 恒 0 | 不透明 | `c.app.withAlpha(255)`（zenit 原生组件不读它；只有 `ui_kit` 测试记录它） |
| `bg_primary` | `c.surface_1` → 255·(1−T/100) | 不透明 | `withAlpha(255)` |
| `bg_secondary` | `c.surface_2` → 71…26，**T=0 也半透明** | 不透明 | `withAlpha(255)` |
| `bg_tertiary` | `c.overlay` → 255…128 | 不透明 | `withAlpha(255)` |
| `bg_inset` | `c.well` → 92…41 | 不透明 | `withAlpha(255)`（zenit 组件不读它） |
| `bg_hover` / `bg_active` / `bg_focus` | `s.hover`（hover）/ `s.pressed`（well）/ `s.focus`（tab_on） | **本来就半透明**（`#ffffff0d` 之类，叠在表面上的色调） | 不变 |
| `accent_muted` / `accent_subtle` / `selection_bg` | `selectionColor(c)` = `s.selected`（tab_on 82…） | 不透明（blue 色阶） | 不变，待判定（见 H-opaque-popups 报告） |
| `success_subtle` / `warning_subtle` / `danger_subtle` / `info_subtle`、`*_alert_bg` | `s.feedback_*`（well 92…） | 不透明 | 不变，待判定 |
| `zw_island_focus` / `zw_island_rest` / `zw_list_active` / `zw_island_ground` | `surface_1` / `surface_2` / `surface_1` / `app`（带材质 alpha） | — 下游自定 | 不变：这是主窗口“透出壁纸”的表面 |
| 角色 token（`input_bg`、`tooltip_bg`、`list_selection_bg`、`checkbox_*`、`switch_*`、`button_secondary_*`…） | 生成期由 zenit 解析，`widgetTokensFrom` 不再改写 | 不透明 | 不变 |

zenit 原生组件用这些语义 token 画浮层 / 面板 / 控件底（`vendor/zenit/src/ui/components/**`）：
- 浮层面板：`popover/styles.zig popoverContentBackground = bg_primary`（Menu 基于 Popover，同一块 chrome）；`select/styles.zig palette()` 的 `bg / panel = bg_primary`、`inset = bg_secondary`；
  `select_headless/mount.zig`、`combo_box/styles.zig` 面板 `bg_primary`；`modal/styles.yss dialog` 默认 `bg-primary`；`sheet/styles.zig` `bg_primary`；
  `notification/styles.zig` 次按钮 `bg_primary`。Tooltip 用 `tooltip_bg`（角色 token，本来不透明）。
- 控件 / 面板底：Select 触发器（`bg_primary`）、Tabs（`bg_primary / bg_secondary`）、Card（`bg-primary / bg-secondary`）、Chip、Tag、Checkbox、Steps、Table / DataTable、
  NumberStepper、TagsInput、Calendar / DatePicker、Accordion、Alert、ControlShell、Skeleton、Progress、GlassBox（`bg_primary`）、ScrollArea 与 Slider（`bg_tertiary`）。

ZeroWork 自己的样式里读语义表面 token 的地方（无一处依赖它们半透明）：
- `settings/view/styles.yss`（`bg-primary` ×4：快捷键 / 开关药丸、keycap）、`panes/keys.yss`（×6）、`panes/updates.yss`（×1）：都在不透明的设置窗口里；
- `connections/wizard/view/wizard_styles.zig`（输入框 / 次按钮 / 分段选中项 `bg_primary`）、`connections/progress/view/connection_progress_styles.zig`（次按钮 `bg_primary`）：设计稿 W:jHqcg / W:rTb0Z 本就是不透明填充；
- `shared/ui/zenit_ext/focus_fill.zig`：已删除（native-buttons：焦点改用 zenit 原生焦点环，`bg_focus` / `border_focus` / `focus_ring` 回到 zenit 默认）；
- `shared/ui/theme/design.zig`（设计预览自己的 token 集）、`config/theme_presets.zig`（注释）。
主窗口“透出壁纸”的表面都直接读 `current().surface_* / overlay`、`layerBackground` 或 `zw_island_*`，不经语义 token；所以不需要新增 `zw-surface-*`。

`theme_states.zig:117-171` 中 `choice_off = separate(lerp(overlay, c.fg_2, 0.4), …, 1.5)`、`choice_on = c.action_accent`、`choice_ink = primary_ink`、`choice_thumb_off = separate(overlay, {choice_off}, …)` 是带对比度保证的计算色，已偏离 zenit 默认色阶。

### 统计

完全手工 8 项，原生被覆盖 8 项。最值得先改的 5 处：权限 / 执行模式（7 个选项）改 `W.RadioGroup`；主题选择卡（需上游“卡片式单选”）；三处分段（两处路由 + BMC）；`plugins/remote/editor.zig` 的 `paintAuthLabels`；`transfer_conflict_view` 与 `ai_composer_interaction_view` 里隐藏原生圆点再自绘。

---

## 清单 3：Input / Select / Tooltip / Button 覆盖与玻璃

### 3.1 函数覆盖

| 函数 | 定义位置 | 覆盖了什么 | 调用点（不含测试） | 状态 |
|---|---|---|---|---|
| `styleInput` | `src/shared/ui/theme/app_theme.zig:324` | 给 `input_container` 挂 `paintInputChrome`（选区色与 tokens 刷新；边框与焦点由 ControlShell 负责） | 24 处：remote editor 3、ai_remote_picker 2、plugin_challenge 2、ai_model_editor 2、appearance 2，settings（controls / extensions / provider / plugins / picker）各 1，auth_challenge、socks_config、history_host、tab_picker、tab_rename、transfer_conflict、group_join、bmc editor 各 1，`design.zig` 1 | 已删除（usage-b4-materials）：16 处调用全部去掉，选区颜色改由主题 token `selection_bg` 给出 |
| `paintInputChrome` | `app_theme.zig:345`（私有） | 选区背景 / 前景色、tokens 脏标记 | 被 `styleInput`、`paintInputValidation` 调用 | 已删除（usage-b4-materials） |
| `paintInputValidation` | `app_theme.zig:328` | `has_error`、a11y `invalid`、重绘 | ai_provider_settings、appearance_view、settings_controls 各 1 | 待替换 |
| `tuneInput`（settings） | `src/features/settings/view/settings_styles.zig:253` | 字号 13、行高 18、文字色 `fg_1`、后缀单位 11 号 `fg_2` | 13 个文件：ai_remote_picker 2、asset_group_host 2、plugin_challenge 2、auth_challenge 1、ai_extensions 1、ai_model_editor 2、ai_provider 1、appearance 2、settings_controls 1、settings_plugins 1、tab_picker 1、tab_rename 1、terminal_search 1 | 待替换 |
| `tuneInputUnit` | `settings_styles.zig:283` | 单位文字 11 号 400 `fg_2` | 内部递归 | 待替换 |
| 各 feature 自带 `tuneInput` | `workspace_tab_styles.zig:109`（12 / 18 / `char_width` 7.2）；`terminal_search_styles.zig:54`（12、`padding_h=12`，覆盖 `input_container` 尺寸与边框）；`auth_challenge_styles.zig:119`（12）；`asset_group_styles.zig:47`（12、`fg_1`）；`ai_composer_controls_styles.zig:222`（11.5、`fg_1`）；`file_mkdir_styles.zig:38 tune`（11.5，重写 `node` 与 `input_container` 样式） | 字号、行高、`char_width`、文字色、容器 padding / 边框 | 各自 feature，每个 1 到 2 处 | 待替换 |
| `paintSearch` | `settings_styles.zig:8` | 设置搜索框：`bg_active` 底、14 圆角、聚焦 accent 边框、占位色 `fg_2` | `settings_host.zig`、`nav_host.zig` 各 1 | 待替换 |
| `terminal_search_styles.paintInput` | `terminal_search_styles.zig:72` | 聚焦 `states().focus` / `control` 背景、边框透明、聚焦环圆角 8 | `terminal_search.zig` 3 处 | 待替换 |
| `fieldControl` | `settings_styles.zig:216` | 宽高、padding 12，不画边框（保留 ControlShell） | appearance 1、settings_controls 2、settings_plugins 2、本文件 1 | 待替换 |
| `fieldButton` / `actionControl` | `settings_styles.zig` 约 L222-234 | Button 当 Select 触发器：`surface_1` 底、13 号 | 设置页若干 | 待替换 |
| `tuneSelect` | `settings_styles.zig:239` | 触发器文字 13 号 400 行高 18/13 `fg_1` | ai_provider、appearance、settings_controls、settings_plugins 各 1 | 待替换 |
| `paintControlText` | `settings_styles.zig:600` | 递归文字色 `fg_1` | ai_model_editor、settings_styles 各 1 | 待替换 |
| `stylePrimary` | `app_theme.zig:211` | Button 主操作：渐变 `primary*`（含悬停 / 按下）、阴影、`inset_shadow`，禁用时清除 | 41 处（workspace.zig 3、settings_host 2、ai_host 2、ai_tool_approval 2、ai_empty_view 2、connection_details 2，其余 ai / connections / files / history / settings / shell / terminal / transfer / workspace 各 1） | **已替换（native-buttons）**：函数与全部调用已删除；这些主按钮（以及顺带的同一页脚次按钮）只用 variant / size / label，无底色 / 字色 / 几何覆盖 |
| `styleActionText` | `plugin_challenge_presenter.zig:453`；`certificate_trust_view.zig:171` | Button 文字 12 / 500 / 行高 1.5 / `actionColor`（后者加 `wrap=.none`、居中） | 各 2 处 | **已替换（native-buttons）**：两处函数删除，相关按钮的 `S.button` 尺寸 / 底色覆盖一并删除 |
| `titleToolbarButton` | `src/features/shell/view/shell_styles.zig:166` | 标题栏 ghost 图标按钮：先调 `toolbarButton` 覆盖宽高 / 圆角 / 内边距 / 边框，再改成 24×24、圆角 6 | 7 处：`chrome_mount.zig` 4、`workspace_chrome.zig` 2、`app/main_window.zig` 1 | **用户判定：改用 zenit 原生 ghost 图标按钮的默认尺寸**（定稿 p773F9：md，32×32、图标 16、圆角 6），**已替换（native-buttons）**：函数删除，原生图标按钮用 zenit 默认 md（32×32）；标题栏工具组高度改为 32（`shell/styles.yss`）；由状态栏折叠进来的图标控件（链路 / 转发 / 主题 / 广播 / 命令历史）不是原生 icon-only Button，用同尺寸方框 `shell_styles.toolbar_icon_size` |
| `styleFileCheckbox` | `file_workspace_view.zig:1688` | 见清单 2 | 2 处 | 待替换 |
| `tuneProviderText` | `ai_provider_settings.zig:1142` | 递归 12 / 400 / 行高 1.5 / `fg_1` | 同文件 3 处 | 待替换 |
| bmc `paintInputTypography` / `paintFieldTypography` / `paintActionTypography` / `paintLogActionTypography` / `paintCheckboxTypography` | `src/plugins/bmc_ikvm/editor.zig:1068-1115` | 输入、字段、按钮、日志按钮（accent 色）、复选框字号行高，`addBeforeRender` 每帧重设 | 同文件 | 待替换 |
| remote `paintInputTypography` / `paintSelectTypography` / `paintTypography` / `paintSelectContent` / `paintSelectMenu` / `paintButtons` / `paintAuthLabels` / `paintCheckboxLabels` | `src/plugins/remote/editor.zig:3735-3830`、`2699` | Select 菜单行高 32、内边距、圆角 7、悬停 / 选中色、chevron 着色；按钮宽高 / 底 / 边框 / 透明度；输入字号行高 | 分别 5、2、3、1、4、2 处 | 待替换 |
| `bmc_ikvm/select_surface.styles` | `src/plugins/bmc_ikvm/select_surface.zig:15` | 通过 zenit 公开 `panel_style` / `option_style` 提供样式（覆盖面板底与行高） | `editor.zig`、`views.zig` 的 Select | 已删除（usage-b5c-native-controls：`select_surface.zig` 删除，KVM 弹层里的 Select 用原生默认面板与行，不再传 `panel_style` / `option_style`） |
| `paintInputFocus` | `src/features/connections/quick_connect/view/quick_connect_view.zig:568` | 输入聚焦绘制 | 同文件 | 待替换 |
| `input_container.setStyleInline` 等直接覆盖 | settings_styles 6、terminal_search_styles 8、remote editor 19、sidebar_view 4、transfer_conflict 5、settings_picker 4、history_host 4、file_workspace 4、socks_config 4、quick_connect 5、bmc editor 5 等约 30 个文件 | 容器宽高、背景、圆角、边框 | 约 120 处 | 待替换 |

用量：`W.Input` 约 41 个 zig 挂载加 8 个 yix；`W.Select` 22 处（ai_remote_picker、ai_composer_controls、socks_config、wizard、ai_model_editor、ai_provider、appearance、settings_controls、settings_plugins、transfer_manager 2、bmc editor 3、bmc views、remote editor 7）；`W.Button` 363 处（302 带 `base_style`）。

### 3.2 Tooltip

原生 `W.Tooltip`：37 处挂载（含 `_header.yix.zig:96`，来自 `header.yix:44`，及共享封装 `shared/ui/components/control_hint/control_hint.zig:64`）。按 feature：ai 11（approvals 2、attachments 1、composer 3、ai_host 1、sessions 4）、connections 4、files 3、settings 13、shell 1、terminal 1、transfer 1、workspace 1、plugin remote 1、control_hint 1。

对提示框外观做了覆盖（传 `.background` / `.text_color` / `.font_size`）的 12 处：
`connection_details_view.zig:636`、`connection_progress_view.zig:349 / 765 / 807`、`ai_model_editor.zig:607`、`ai_provider_settings.zig:811`（另 `tip.content.setStyleInline(S.fieldHelp(...))`）、`settings_controls.zig:437 / 623`、`status_connection_view.zig:280`、`command_history_view.zig:253`、`workspace.zig:1679`、`control_hint.zig:64`。覆盖值：`overlay`（半透明玻璃材质）/ `popupInset()` / `overlay.withAlpha(255)` 作底，`fg_1` 作字色，字号 11 或 12。状态：待替换。

手工拼的提示浮层（用 Popover 当 Tooltip）：

| 文件:行 | 用途 | 说明 | 状态 |
|---|---|---|---|
| `src/features/ai/composer/view/ai_composer_controls_view.zig:620` | 模型详情提示（`ai.model.details`） | `Popover` hover + `.tier=.tooltip`，宽 284，`chrome.setStyleInline` 自画；注释称 zenit Tooltip 无固定宽度契约（实际 Tooltip 已有 `width` 属性，需核实是否足够） | 待替换 |
| `src/features/shell/view/sidebar_view.zig:744`（`mountHintAnchored`） | 侧栏悬停提示 | Popover hover + `S.hint()`，a11y `.tooltip` | 待替换 |
| `src/features/transfer/view/transfer_panel.zig:760` | 传输源文件路径提示 | Popover hover + `S.sourceHint()` | 待替换 |
| `ai_provider_settings.zig:399`（`tooltipOnly`）、`settings_controls.zig`（`inlineHint`） | 设置页问号帮助 | 内部仍调原生 Tooltip，样式覆盖 | 待替换 |

### 3.3 玻璃 / 毛玻璃

- zenit 玻璃组件：`GlassBox`、`GlassGroup`、`GlassSlider`、`GlassToggle`、`GlassToolbar`、`GlassNavigationBar`、`GlassTabBar`、`GlassBottomToolbar`、`GlassButton`。应用中零引用。（盘点时的状态。之后：设置窗口的 Settings Nav / Save Bar 用 `W.GlassBox`（H-shell / H-save），页头用 `W.GlassToolbarGroup` / `W.GlassToolbarButton` 与 `W.TitlebarEdge`、视口用 `W.ScrollArea scrollEdge`（set-adopt）。）
- 下游模仿，三类：
  1. `BoxStyle.glass = theme.overlayGlass()`（`app_theme.zig:418`，仅 `backdrop_blur = max(12, material_blur)`，其余 0）+ `overlay` 半透明色 + 手写阴影，约 45 个样式文件（zenit 底层能力，不是 `GlassBox` 组件）。
  2. 设置窗口 `src/features/settings/view/styles.yss`：`nav`（L13，“Settings Nav 216 宽浮动玻璃侧栏”，`zw-window-rest` + 1px `bg-hover` + 阴影 `0 5 18`）；`glass_nav`（L34，后退 / 前进 36 高药丸，由 `header.yix:34-38` 的 `<box>` + `S.GlassNavButton` look 拼成）；`glass_icon`（L192，页头帮助 `W.Button` 的 `look`，`header.yix:44`）；`save_bar`（L66，22 圆角浮动保存条，`save_bar.yix:49`）；`nav.yix:51` 的 `<box style={S.nav}>`。这些是“实心不透明表面 + 描边 + 阴影”，`zw-window-surface = c.surface_1.withAlpha(255)`，不是玻璃。**状态：已替换（H-shell）**——`.yix` 外壳的 `nav`、`glass_nav`（含 `glass_nav_divider`、`GlassNavButton`）、`glass_icon` 改为原生 `W.GlassBox`（导航浮层；页头后退 / 前进胶囊与帮助圆钮里是原生 ghost `W.Button`），样式与 token `zw-window-glass-*` 删除；旧外壳（`.legacy`，3f 删除）仍用的 `nav` / `glass_nav*` 搬到 `settings_shell.zig` / `settings_styles.zig`；`save_bar` **已替换（H-save）**：Save Bar 是原生 `W.GlassBox` 胶囊 + 原生 `W.Button`（只用 variant / size），删除 `save_bar` / `save_status` / `save_fill` / `FooterLink` / `footer_ghost` 与 token `zw-primary-hover*` / `zw-primary-pressed*`；旧外壳仍用的 `save_bar` / `save_status` 搬到 `settings_styles.zig`（随 3f 删除）。
  3. `src/shared/ui/styles/layer_materials.zig` 与 `src/features/shell/view/background_layers.zig:305`：自建材质系统，带 `capture_source=.current_surface` 的背景模糊。（usage-b4-materials：`layer_materials.zig` 已删除，材质改为创建者声明，见 DESIGN_STANDARDS §3“材质归属”；背景层的图片模糊保留。）
- 另有手写玻璃卡片：`notification_presenter.zig:369`、`terminal_overlay_styles.zig:21`、`command_history_styles.zig:5` 等。状态：待替换（`notification_presenter.zig` 的玻璃卡片已随 native-notify 删除，改原生通知栈；其余待替换）。

### 统计与优先级

覆盖函数约 30 个，调用约 280 处；`W.Button` `base_style` 约 300 处。先改：1) Button 大面积 `base_style`；2) 重复的 `tuneInput`（约 7 套，字号 11.5 / 12 / 13 不统一）；3) `stylePrimary`（41 处）；4) Tooltip 12 处覆盖与 3 处手拼；5) 设置窗口 Glass Nav / `glass_icon` / `save_bar` / `nav`。

---

## 清单 4：其余基础组件的手搓与覆盖

### 4.0 zenit 原生组件（`vendor/zenit/src/ui/components/`）与应用使用情况

zenit 提供：Button、Pressable、Menu、Popover、Tooltip、Modal、Sheet、NotificationCard / Hint（`notification/`）、ScrollArea、Divider、Tabs / TabPanel、Card、Checkbox / Radio / RadioGroup / Switch、Slider、Progress、Spinner、Skeleton、Badge / StatusBadge、Tag、Chip、Breadcrumb、Accordion、Steps、Tree、Alert、Select、ComboBox、Input / Textarea、NumberStepper、TagsInput、DataTable / Table、VirtualList、Calendar / DatePicker、Rate、Slider、Glass 系列。**zenit 无对应组件**：Avatar、独立 ContextMenu（`Menu` 支持 `trigger`，需核实是否覆盖右键菜单）、Segmented、卡片式单选。

应用内 `widgets.X(` 非测试挂载次数（zig）：Button 363、Pressable 0、Menu 6、Popover 40、ScrollArea 99、Divider 0、Tabs 1、Card 0、Checkbox 17、Radio 1、RadioGroup 6、Switch 14、Slider 3、Progress 2、Spinner 4、Skeleton 0、Badge 0、Tag 0、Chip 1、Breadcrumb 0、Accordion 0、Steps 0、Tree 0、Alert 1、Tooltip 36、Modal 34、Sheet 0、Select 22、Input 41。yix 内 `<W.*`：Button 20、ControlShell 16、Input 8、ScrollArea 5、Checkbox 5、Switch 4、Radio 3、Tooltip 2、Pressable 2、Popover 1、Menu 1、Select 1、Textarea 1。

### 4.1 逐类清单（每类最多详列，其余计数）

| 类别 | 文件:行 | feature | 用途 | 做法 | 对应 zenit 原生 | 调用点 | 难度 | 状态 |
|---|---|---|---|---|---|---|---|---|
| Button 整体重写外观 | 全局，见清单 3：`stylePrimary`（`app_theme.zig:211`）、`styleActionText`（`plugin_challenge_presenter.zig:453`、`certificate_trust_view.zig:171`）、`base_style` | 全部 | 主 / 次 / ghost / 图标按钮 | 覆盖原生 | `W.Button`（variant、size、`look`） | `base_style` 约 302、`stylePrimary` 41、`styleActionText` 4 | 高（量大；先确认 zenit 变体能否满足，缺则补 variant） | 部分替换（native-buttons）：`stylePrimary` / `styleActionText` 全部删除；所有主按钮（含插件编辑器主操作）及其同一页脚的次按钮去掉底色 / 字色 / 尺寸覆盖；按钮的焦点环抑制（`sidebar_view.setFocusRing`、`connection_progress_styles.focusRing`、`icon_button_feedback` 的轮廓改写、侧栏新建连接 / BMC 进度与动作按钮的零宽焦点环）删除。**剩余**：其余次 / ghost / 图标按钮的 `base_style`（约 250 处，含设置旧外壳 `fieldButton` / `actionControl`、remote `paintButtons`、bmc `paintActionTypography`）、`record_cleanup` / `application_data_cleanup` 的危险按钮底色、`ai_pending_view` 手做的焦点槽 |
| 手拼“按钮”（box + 点击） | `src/features/workspace/view/workspace.zig`（点击处理 12 处，如 L1700 tab cell 的 `on_click`）、`connections/progress/host/ssh_status_host.zig`（5）、`settings/view/settings_content_view.zig`（4）、`ai/cards/view/ai_execution_result_view.zig`（4）、`ai_tool_results_view.zig`（3）、`app/main_window.zig`（3）、`shell/view/status_hover_preview.zig`（2）等，共约 60 处非 Button 节点绑 `on_click` | workspace / connections / settings / ai / shell | 可点击行、状态条、卡片头 | 手搓 | `W.Button` / `W.Pressable` | 约 60 | 中（需逐个判语义） | 待替换（native-buttons 未处理） |
| 行 / 列表项按钮 | `session_menu.zig:87-236`、`settings_picker.zig`、`tab_picker.zig`、`ai_children_view.zig:149`、`ai_sessions_view.zig`、`transfer_manager_view.zig`、`connection_progress_view.zig`（`S.rowContent`、`S.highlight`）等；应用 zig 内 `W.Pressable` 0 处，yix 内 2 处（`nav.yix:61` 等） | shell / settings / ai / transfer / workspace | 菜单行、选择行、会话行、任务行 | 手搓 + 覆盖 | `W.Pressable` / `W.Menu` / `W.VirtualList` | 估计 40+ | 中 | 待替换 |
| Menu / 下拉 / 右键菜单 | 原生 `W.Menu` 6 处：`ai_pending_view.zig:183`、`ai_task_finish.zig:750`、`ai_extensions_settings.zig:356/419`、`appearance_view.zig:306`、`workspace.zig:3376`。手拼：`src/features/shell/host/menu_host.zig`（1015 行，popover 内手拼头部、分隔线、内容）、`workspace/view/session_menu.zig`（Popover 内手拼行 / 高亮 / 分隔线，L66-236）、`workspace/model/context_menu*.zig`（4 个文件，约 590 行，右键菜单状态机）、`settings/view/settings_picker.zig:59`（手拼浮层 + glass + 阴影） | shell / workspace / settings | 主菜单、新建会话菜单、右键菜单、设置选择器 | 手搓 | `W.Menu` | 4 个手拼实现 | 高（菜单项带图标 / 分区 / 搜索；需确认 `Menu` 能力，可能补上游） | 待替换 |
| Notification / Toast | `src/features/notifications/view/notification_presenter.zig`（`z_index=150`，`glass`，手拼三槽位）、`notification_history.zig`（22 个 box / text）、`notification_styles.zig:9`（`z_index=2000`）、`notification_countdown.zig`；`src/features/ai/pane/view/ai_feedback_view.zig` 等（设置窗口的保存成功 / 失败提示已改用 zenit 原生 `W.Notifier` 文字提示，H-save） | notifications / ai | toast、通知历史、反馈条 | 手搓 | `notification.NotificationCard` / `Hint`（`vendor/zenit/src/ui/components/notification/`），下游零引用 | 2 个主文件 | 高（需核对 NotificationCard 能否承载倒计时、动作、进度） | **已替换（native-notify；notify-two-hosts 分两栈）**：每个应用窗口两个原生 `<W.NotificationHost>`（`view/toast_stack.yix`，外观全部 zenit 默认）：右上角卡片栈（`notifications.viewport`）放全局提醒与终端命令失败提示（`command_error_hint_view.zig`，原生卡片），中下方标准 Toast（`notifications.toasts`，zenit 默认 `.bottom_center`）放本地回执（`acknowledgeAt`，原生成功文字提示）与插件 / 内置内容的无动作反馈（`publishFeedback`，原生信息文字提示）；分流规则是 `model/view_model.zig` 的纯函数 `laneFor`（无动作的成功 / 信息 → Toast，带动作或需要处理 → 卡片），请求 / 事件归同文件的 `cards` / `toasts` 两条通道，宿主胶水 `host/notification_presenter.zig`；只有右上角卡片栈按宿主浮层遮挡隐藏、暂停（操作失败例外），中下方 Toast 永远在最上层（zenit toast tier 高于 overlay / dialog tier），被遮挡时既不隐藏也不暂停计时（toast-top）；设置窗口的保存提示是它自己的中下方原生 Toast（`save_bar.yix`）；倒计时是原生生命条；上游补 G49（详情展开）、G50（三个动作）、G51（焦点暂停）、G52（遮挡隐藏）、G53（部件 test_id）、G54（短窗口详情收缩）及两处换行修复。删除 `notification_styles.zig`、`notification_countdown.zig`、`command_error_hint_styles.zig`。通知历史改 `.yix` + view-model（原生 `W.Popover` / `W.ScrollArea` / `W.Card` / `W.Button` / `W.Badge` / `W.Alert`）；AI 反馈条改原生 `W.Alert`（`ai_feedback.yix`）。剩余：`notification_history_styles.zig` 仍被 `ai_recovery_view.zig`（展开按钮的 `base_style` 覆盖）与几处测试引用，归 AI 卡片 / Button 覆盖清单；判定项见 `YIX_EXCEPTIONS.md` N-1 – N-7（N-1 已收回） |
| Popover / 浮层卡片 | 原生 `W.Popover` 40 处。手工定位（`position = .absolute`）集中在：`terminal/view/terminal_view.zig`（12，如 L3212 面板 208x88）、`shell/view/background_layers.zig`（12）、`workspace/view/workspace.zig`（11）、`settings/view/panes/appearance_view.zig`（9）、`workspace_tab_styles.zig`（6）、`sidebar_styles.zig`（6）；浮层卡片：`terminal/view/terminal_overlay_styles.zig:21`（补全目录卡，`z_index=30`）、`command_history_styles.zig:5`（`z_index=60`）、`ai/pane/view/ai_assistant_styles.zig:6`、`shell/view/status_hover_preview.zig`、`status_theme_styles.zig`、`status_detail_styles.zig`、`shell/view/tab_color_picker.zig`、`terminal/view/command_help_view.zig`（`z_index=20`） | terminal / shell / workspace / settings / ai | 补全、命令历史、状态悬浮预览、取色、AI 浮窗 | 手搓（含 glass 模仿） | `W.Popover` / `W.Sheet` | 约 12 个独立浮层 | 中到高（锚点、翻转、层级需走 OverlayStack） | 待替换 |
| ScrollArea | 原生 `W.ScrollArea` 99 处 zig + 5 处 yix。显式关闭回弹 `rubber_band*` 出现在 38 个文件（如 `ai_host_approval_view.zig:129`、`ai_card_scroll.zig:337`、`connection_progress_view.zig:374/392/446/459`、`notification_history.zig:119/257`、`history_host.zig:129`；设置外壳 `_page.yix.zig:46/51` 两处已由 H-shell 恢复默认回弹）。手工滚动 / 滚动条：`ai/cards/view/ai_card_scroll.zig`（35 处滚动相关、12 处 scrollbar）、`terminal/view/terminal_view.zig`（18）、`terminal_surface.zig` / `terminal_scrollbar.zig`（自画滚动条，`z_index=9`）、`bmc_ikvm/views.zig`（15）、`bmc_ikvm/remote_input.zig`（9） | ai / terminal / bmc / connections | 内容滚动、终端滚动条、AI 卡片滚动 | 覆盖 + 手搓 | `W.ScrollArea` | 38 个文件关回弹；3 个手搓滚动实现 | 中（终端滚动条与终端渲染强相关，待判定） | 待替换；终端部分待判定 |
| Divider | 原生 `W.Divider` 0 处。手画 1px 线（`height/width = 1px` 或 `height: 1;`）分布在 19 个文件：`settings/view/styles.yss`（4）、`workspace/view/workspace.zig`（3）、`bmc_ikvm/styles.zig`（2）、`settings_updates_styles.zig`（2）、`files/view/styles.yss`（2）、`file_actions_styles.zig`（2）、`wizard_styles.zig`（2）、`ai_children_styles.zig`（2），其余 `session_menu_styles`、`group_workspace_styles`、`sidebar_styles`、`shell/styles.yss`、`menu_host.zig`、`settings_styles`、`settings_shell`、`file_actions_view`、`connection_stepper`、`connection_progress_styles`、`ai_tool_results_view` 各 1 | settings / workspace / files / wizard 等 | 分隔线 | 手搓 / Yss 模仿 | `W.Divider` | 约 30 | 低 | 待替换 |
| Tabs / 页签条 | 原生 `W.Tabs` 仅 `appearance_view.zig:1093`。手拼：主窗口会话页签条（`app/main_window.zig:323`、`workspace/view/workspace.zig:1700-1725` 的 `tabs.cell.*`，含拖拽、悬停、`tab_strip_layout.zig`、`workspace_chrome.zig`、`workspace_tab_styles.zig`）；分段切换见清单 2（审批路由、交互路由、BMC、向导、remote editor） | workspace / shell / ai / connections / plugins | 会话页签、分段 | 手搓 | `W.Tabs`；zenit 无 Segmented → 需补上游 | 会话页签 1 套 + 分段 6 套 | 会话页签高（**复杂控件，待判定**：拖拽排序、关闭按钮、颜色标记）；分段中 | 待判定（会话页签条）/ 待替换（分段） |
| Card / 面板容器 / Pane Header | 原生 `W.Card` 0 处。手写 `card / panel / pane / paneHeader` 样式函数分布：`settings_updates_styles.zig`（3）、`wizard_styles.zig`（3）、`file_workspace_styles.zig`（2）、`connection_progress_styles.zig`（2）、`connection_details_styles.zig`（2）、`ai_assistant_styles.zig`（2），另 `workspace_tab_styles`、`session_menu_styles`、`group_workspace_styles`、`broadcast_styles`、`transfer_styles`、`transfer_conflict_styles` 各 1；设置窗口 `styles.yss` 的 `pane`、`pane_header`、`pane_body`、`overview_list`、`hero_tile` | settings / connections / files / ai / transfer | 卡片、窗格、窗格头 | 手搓 / Yss 模仿 | `W.Card` / `W.Group` | 约 30 | 中（先确认 Card 能否表达 pane header） | 待替换 |
| Checkbox / Radio / Switch | 见清单 2；原生使用 Switch 14、Checkbox 17、RadioGroup 6 | - | - | 手搓 8 + 覆盖 8 | `W.Checkbox` / `W.Radio` / `W.Switch` | 见清单 2 | 见清单 2 | 待替换 |
| Slider(Range) | 原生 `W.Slider` 3 处：`appearance_view.zig:1398`、`ai_composer_controls_view.zig:711`（待核）等；手工滑块待确认（未在 `src/**/*.zig` 中找到独立手搓实现） | settings / ai | 透明度 / 模糊 / 范围 | 原生 | `W.Slider` | 3 | - | 待判定（是否有覆盖需核） |
| Progress | 原生 `W.Progress` 2 处：`app_update_view.zig:119`、`connection_progress_view.zig`（待核）。手搓进度条（`.width = .percent`）：`shell/view/status_transfer_view.zig`（3）、`transfer/view/transfer_styles.zig`（2）、`terminal_view.zig`（2）、`ai_empty_styles.zig`（2）、`ai_composer_controls_styles.zig`（2）、`update/view/app_update_styles.zig:40 progress()` | shell / transfer / update / ai | 传输进度、更新进度 | 手搓 | `W.Progress` | 约 6 个 | 低到中 | 待替换 |
| Spinner | 原生 `W.Spinner` 4 处：`status_theme_view.zig:129`、`remote_session_notice.zig:112`、`workspace.zig:5344`、`connection_progress_view.zig`。手搓旋转 / 加载（`rotate`、`ui.view.loop`）：`connection_progress_view.zig`（9 处相关）、`remote_session_notice.zig`（8）、`status_theme_view.zig`（5）、`sidebar_view.zig`（2）、`workspace.zig`（4） | connections / workspace / shell | 加载态 | 混用 | `W.Spinner` | 约 5 | 低 | 待替换 |
| Skeleton | 原生 0 处；手搓占位需核（`ai` 流式占位等） | - | - | 待核 | `W.Skeleton` | 未统计 | 低 | 待判定 |
| Badge / Tag / Chip | 原生 `W.Chip` 1 处，`W.Badge` / `W.Tag` 0 处。手写样式函数：`badge()` 在 `ai_recovery_styles.zig:52`、`file_workspace_styles.zig:97`、`settings_updates_styles.zig:43`、`sidebar_styles.zig:157`、`status_transfer_styles.zig:28`、`transfer_styles.zig:41`；`chip()` 在 `ai_composer_controls_styles.zig:34`、`connection_details_styles.zig:156`、`connection_progress_styles.zig:107`、`history_styles.zig:58`、`local_status_styles.zig:25`；`tag()` 在 `ai_sessions_styles.zig:76`、`status_theme_styles.zig:49`；另 `connection_details_view.zig:522 chip` | ai / files / settings / shell / transfer / connections / history / terminal | 状态标签、数量角标、芯片 | 手搓 | `W.Badge` / `W.StatusBadge` / `W.Tag` / `W.Chip` | 13 个样式函数 | 低 | 待替换（F-set-panes-B：`settings_updates_styles.zig:43` 的徽标在 `.yix` 路径已换成原生 `W.Tag`，快捷键的手搓键帽换成原生 `W.Tag`；旧文件随 `.legacy` 留到 3f） |
| Avatar | 无手搓头像确认；会话图标 `shared/ui/components/session_icon`（自有组件） | shell | 会话图标 | - | zenit 无 Avatar → 需补上游（若确属头像类） | 1 | - | 待判定 |
| Breadcrumb | 原生 0 处。手搓路径面包屑：`files/view/file_workspace_view.zig`（24 处相关）、`file_workspace_styles.zig`（3）、`files/view/styles.yss` | files | 文件路径栏 | 手搓 | `W.Breadcrumb` | 1 套 | 中（需支持可编辑路径输入） | 待替换 |
| Accordion | 原生 0 处。`settings/view/settings_accordion.zig`（自称 Native Accordion semantics + 自有动效）、`ai/cards/view/ai_step_disclosure.zig`、`ai_step_group_view.zig` | settings / ai | 折叠区 | 手搓（含自有动效） | `W.Accordion` | 3 | 中 | 待替换 |
| Steps | 原生 0 处。`connections/wizard/view/connection_stepper.zig`、`connection_progress_view.zig` 跳点链 | connections | 向导步骤 / 跳点链 | 手搓 | `W.Steps` | 2 | 中 | 待替换 |
| Tree | 原生 0 处；文件树 / 列表待核（仅 `multiwindow_test_routes.zig` 命中） | files | - | 待核 | `W.Tree` | 未统计 | - | 待判定 |
| Alert | 原生 `W.Alert` 仅 `app_theme.zig:1242`（测试块）。手搓提示条：`ai_host_notice_view.zig`、`ai_recovery_view.zig`、`remote_session_notice.zig`、`command_error_hint_view.zig`、`settings` 的 `inlineHint` 等 | ai / workspace / terminal / settings | 提示条 / 警示条 | 手搓 | `W.Alert` | 约 6 | 低到中 | 待替换 |

### 4.2 全局数字

`setStyleInline`（非测试 `src/**/*.zig`，含 yix 生成文件）：**1564 处**。
按文件前 10：`plugins/remote/editor.zig` 96、`plugins/bmc_ikvm/views.zig` 56、`features/connections/progress/view/connection_progress_view.zig` 53、`features/transfer/view/transfer_manager_view.zig` 52、`features/files/view/file_workspace_view.zig` 46、`features/ai/composer/view/ai_composer_controls_view.zig` 41、`features/settings/view/panes/appearance_view.zig` 37、`features/workspace/view/workspace.zig` 32、`features/settings/view/ai_provider_settings.zig` 32、`features/settings/view/ai_model_editor.zig` 31。
按 feature：ai 386、connections 265、settings 201、shell 127、transfer 109、plugins/remote 96、terminal 82、workspace 79、plugins/bmc_ikvm 74、files 59、notifications 26、history 23。

`children.items[` 按下标取子节点（非测试）：**204 处**。
按文件前 10：`features/terminal/view/terminal_view.zig` 42、`features/workspace/view/workspace.zig` 15、`plugins/remote/editor.zig` 14、`shared/ui/theme/app_theme.zig` 12（含测试块之外的辅助）、`plugins/bmc_ikvm/views.zig` 9、`ai_composer_controls_view.zig` 8、`shell/view/status_connection_view.zig` 5、`files/view/file_workspace_view.zig` 5、`connections/progress/view/connection_progress_view.zig` 5、`ai/composer/view/ai_composer_interaction_view.zig` 5。
按 feature：terminal 44、ai 36、workspace 20、shared/ui 17、shell 15、settings 15、plugins/remote 14、plugins/bmc_ikvm 11、transfer 10、connections 10。
这类写法依赖原生组件的内部子节点结构（如 RadioGroup 的 `row.children.items[0]` 是圆圈），升级 zenit 即可能失效，是“覆盖原生”的直接证据。

### 4.3 清单 4 要点摘要

- Button：覆盖为主，约 300 处 `base_style`；另有约 60 处非 Button 节点绑 `on_click` 的手拼按钮。
- 行 / 列表项：`W.Pressable` 在 zig 中零使用，yix 2 处；手拼行 40+。
- Menu：原生 6 处，手拼 4 套（`menu_host`、`session_menu`、`context_menu*`、`settings_picker`）。
- Notification：下游整套手拼，zenit 的 `NotificationCard` / `Hint` 零引用。
- Popover：原生 40 处，另有约 12 个手工定位浮层（补全、命令历史、状态预览、取色、AI 浮窗）。
- ScrollArea：原生 99 处，38 个文件关回弹，3 处手搓滚动（AI 卡片、终端、BMC）。
- Divider：原生 0 处，约 30 处手画 1px 线。
- Tabs：会话页签条为复杂控件（待判定），6 套分段手拼，zenit 无 Segmented。
- Card：原生 0 处，约 30 个手写卡片 / 窗格样式。
- Badge / Tag / Chip：13 个手写样式函数，原生仅 1 处 Chip。
- Progress / Spinner / Alert / Breadcrumb / Accordion / Steps：各有手搓，原生使用极少或为 0。
- Glass：Glass 组件零引用，非设置窗口的 island / 工具栏 / 状态条 / AI 浮窗用 `overlayGlass()` + 样式模仿。

---

## 按 feature 的替换工作量

条目数为各清单中涉及该 feature 的手搓 / 覆盖条目的粗略计数（下限）。

| feature | 手搓 / 覆盖条目数（约） | 涉及的基础组件种类 | 需要上游补的能力 |
|---|---|---|---|
| ai | 60+（Modal 6、手拼分段 2、权限 / 执行单选 2、Tooltip 手拼 1、Popover 浮层、`setStyleInline` 386） | Modal、RadioGroup、Tabs / Segmented、Button、Input、Popover、ScrollArea、Alert、Accordion | Segmented；RadioGroup 的自定义行内容 |
| connections | 45+（Modal 8、Tooltip 覆盖 4、Steps、Progress、Spinner、Badge / Chip、Breadcrumb 之外） | Modal、Button、Input、Select、Tooltip、Steps、Progress、Spinner、Chip | Steps 的跳点链样式；Modal 内联形态 |
| settings | 45+（Modal 7、主题卡 / 九宫格、Input / Select 覆盖、Glass 模仿 4、Accordion、Card / pane） | Modal、RadioGroup / 卡片式单选、Input、Select、Tooltip、Card、Glass 系列、Accordion、Tabs | 卡片式单选；Glass Nav / Save Bar 的组合 |
| shell | 25+（`menu_host`、手拼提示、页签条、Badge、状态条、Popover 浮层） | Menu、Tabs、Tooltip、Popover、Badge、Progress | 会话页签条（拖拽、关闭、颜色）；Menu 的分区 / 搜索 |
| transfer | 20+（Modal 2、RadioGroup 覆盖、Tooltip 手拼、Progress、Badge） | Modal、RadioGroup、Checkbox、Progress、Tooltip | 无 |
| plugins/remote | 30+（Modal 2、`paint*` 8 个、分段 RadioGroup、Select 菜单、`setStyleInline` 96） | Modal、Input、Select、RadioGroup、Checkbox、Button | Segmented；Select 的菜单行样式 props |
| plugins/bmc_ikvm | 20+（Modal 4、`paint*Typography` 5、分段、Select 样式） | Modal、Input、Select、Checkbox、Switch、Tabs | Segmented |
| terminal | 15+（Modal 2、搜索框覆盖、补全浮层、自画滚动条、`children.items[` 44） | Modal、Input、Popover、ScrollArea | 终端滚动条与自绘内容的结合（待判定） |
| workspace | 20+（Modal 2、B1 / B2、会话页签条、Menu、Card、Button 手拼 12） | Modal、Tabs、Menu、Button、Pressable、Card | 会话页签条；右键菜单 |
| files | 15+（Modal 1、`styleFileCheckbox`、Breadcrumb、Tooltip、Input） | Modal、Checkbox、Breadcrumb、Input、Card | 可编辑路径的 Breadcrumb |
| notifications | 5+（toast / 历史整套手拼） | NotificationCard、ScrollArea | NotificationCard 对倒计时、动作、进度的支持（待核） |
| history | 5+（B3、Modal 1、Input、Chip） | Modal、Input、Chip | 无 |
| update | 3（Modal 1、手搓进度） | Modal、Progress | 无 |
| shared/ui | 20+（`app_theme` 覆盖函数、`control_hint`、`icon_button_feedback`、`layer_materials`） | Input、Button、Tooltip、Glass | token 映射收敛 |

---

## zenit 缺的基础组件 / 能力（需补上游）

1. **Segmented（分段控件）**。依据：`vendor/zenit/src/ui/components/` 下无 `segmented`；`grep -i segment` 在 `components/mod.zig` 与 `YIX_COMPONENTS.md` 均无结果；应用中有 6 套手拼分段（审批路由、交互路由、BMC 适应 / 原始、向导、remote editor 认证 / 压缩）。`Tabs` 是页签语义，不等同。
2. **卡片式单选（Option Card / 带内容的 Radio 行）**。依据：主题选择卡、权限 / 执行模式行、传输冲突选项、AI 提问选项都需要“Radio 语义 + 自定义行内容 + 选中态”；当前被迫隐藏原生圆点再自绘（`transfer_conflict_view.zig:182-194`、`ai_composer_interaction_view.zig:153-170`）。需要 RadioGroup 开放行内容插槽或提供 Option Card。
3. **二维单选（九宫格对齐选择）**。依据：`appearance_view.zig:1436-1450` 用 9 个 Button 手拼；如不作为通用能力，可用 9 个 Radio 的网格布局替代，需确认。
4. **Avatar**。依据：`mod.zig` 无 avatar；会话图标为下游自有 `session_icon`（待判定是否属头像类）。
5. **Tooltip 固定宽度 / 富内容**。依据：`ai_composer_controls_view.zig:620` 注释称 Tooltip 无固定宽度契约；但 `TooltipProps` 已有 `width` / `wrap` / `font_size`（`tooltip/mod.zig`），需核实是否真不满足（待确认，可能无需补）。
6. **Menu 的复杂内容 / 右键触发**。依据：`menu_host.zig`（1015 行）与 `session_menu.zig`、`context_menu*.zig` 手拼，原因疑为分区头、图标、搜索、快捷键提示、右键定位；需逐项对照 `W.Menu` 的 `MenuItem` 能力（待确认）。
7. **会话页签条（可拖拽、可关闭、带颜色 / 状态标记）**。依据：`workspace.zig:1700-1725` 与 `tab_strip_layout.zig`；zenit `Tabs` 无拖拽排序（待确认）。属复杂控件，待判定。
8. **Button 的 variant 覆盖面**。依据：约 300 处 `base_style`，需统计这些覆盖实际在表达哪几类变体（主操作渐变、次要、危险、图标、链接、药丸），缺的补成 variant，而不是在下游覆盖。
9. **NotificationCard 的倒计时 / 动作 / 进度**。依据：下游 `notification_presenter.zig` 有 `notification_countdown.zig`；zenit `Card` 导出 `Action`、`Progress`、`Strings`，疑似覆盖（待核）。
10. **Select 菜单行 / 面板样式 props**。依据：remote editor `paintSelectMenu` 手改行高、圆角、悬停色；`bmc select_surface.zig` 说明 Select 已有 `panel_style` / `option_style`，需统一走 token，不再手改。

---

## 补充：保留式换肤遍历（2026-11-12，G23 调查发现）

主题变化时遍历子树、对每个节点 `setBackground` 重新上色的“保留式换肤”写法，会把颜色写进 zenit 原生组件节点的 inline 层并压过组件配方（表现：转发配置里的开关切换后轨道颜色不变）。已用 `app_theme.setRetainedBackground` 止血（只接受真正的颜色重映射），但这类遍历本身就是对原生组件外观的覆盖，按硬性规则应整体删除，让组件靠主题 token 自己跟随。

| 位置 | 用途 | 状态 |
|---|---|---|
| `quick_connect_styles.repaint`（快速连接；SOCKS 配置视图也在用） | 换肤重绘 | 待替换 |
| 侧栏、传输、会话记录、文件工作区、AI 会话、AI 输入区（两处）、页签重命名里的同类遍历（共 9 处，`git grep -n setRetainedBackground -- src`） | 换肤重绘 | 待替换 |

残留风险（2026-11-12 更新，G26）：

- **已修掉**：“原生组件的配方色恰好等于旧调色板某个角色色”。组件角色 token 回到 zenit 默认后这一点被系统性命中——zenit 默认开关“开”色 `#4F5ED9` 等于 light 调色板的 `accent` / `action_accent`，light 下挂载转发配置视图再切到 `forest` 等调色板，遍历把开关轨道当成旧 accent 重映射成新 accent 写进 inline 层，轨道变错色且不再跟随 `checked`。现在 `setRetainedBackground` 先判 `app_theme.nativeOwned(node)`：凡属 zenit 原生组件的节点一律不写，不论颜色是否碰巧相等（9 处遍历都经过它，无需逐处改）。
- **判据**：zenit 没有公开查询能回答“这个节点的 inline 层是否声明了背景”（只有测试用的 `styleHostStateForTest`），于是按结构判断——读 zenit 在每个组件根上写入的 `component_name`：自成一体的控件（`Switch`、`Checkbox`、`Radio`、`Input`、`Textarea`、`Select`、`Slider`、`Badge`、`Tag`、`Chip` 等，`native_controls`）整棵子树都算原生；带插槽、会装 ZeroWork 内容的容器（`Button`、`ControlShell`、`Card`、`ModalPanel`、`PopoverContent`、`ScrollArea`、`Tabs`、`Menu` 等，`native_containers`）只算根节点本身，后代照常（例如文件行是原生 `Button`，行内 ZeroWork 自己的 `files.row.columns` 仍会重映射）。纯布局原语（`HStack`、`VStack`、`Group`、`Grid`、`VirtualList` 等）不画填充，不列入。
- **仍未覆盖**：
  1. 名单是 ZeroWork 手工维护的 zenit 组件名单，zenit 新增组件或改名需同步；ZeroWork 若把某个原生组件根的 `component_name` 改写（如 `layer_materials.card` 改成 `MaterialSurface.*`），该节点不再被识别。
  2. 容器的内部节点（如 `ScrollArea` 的滚动条、`Button` 的内容框）与插槽内容无法区分，仍按 ZeroWork 节点处理；配方色碰巧等于旧角色色时仍会被写。
  3. 遍历对原生组件的文字色 / 图标着色（`setTextColor` / `setTint`）仍会重映射，本次只处理背景。
  4. ZeroWork 自己写进原生组件 inline 层的覆盖（如 SOCKS 配置的按钮 `S.action`、输入框 `S.input()`、文件行勾选框 `styleFileCheckbox`）不再由遍历跟随调色板，只靠各视图 `retheme` 里的显式重写；这些覆盖本身违反硬性规则，应随各自的包删除。
  5. 换肤发生在主题发布之前时，ZeroWork 自有 inline 色的重映射仍可能落后一拍。
- 根治：zenit 提供公开查询（G26），或直接删除这些遍历。

另：有测试改了进程级主题后不恢复原值（`socks_background_ui` 等用 `defer select(.dark)`），共享测试夹具应负责恢复，待处理。

## 未覆盖与不确定之处

1. 全部为静态阅读：未构建、未运行、未截图；计数为下限。
2. `W.Button` 的 363 / 302 / 343 按“同一行文本”grep，跨行写法未计入。
3. B1、B2 的 scrim 未设 `hit_behavior=.opaque`，其是否拦截点击未追到 zenit 默认行为。
4. 清单 1 的 e2e 引用只对 id 前缀做 `git grep -l -F`，前缀较宽的有间接命中；`wizard.window`、`terminal.paste`、主机密钥确认、`settings.plugins.info` 未搜到专属脚本。
5. C 类中的传输管理窗口与插件窗口是否独立窗口只看了名字和标志位。
6. Tooltip 37 处里是否另有通过 `tip.content.*` 间接覆盖外观的，仅确认 `ai_provider_settings.zig:812` 一处。
7. 清单 4：Slider、Skeleton、Tree、Avatar、Spinner / Progress 的个别调用点（标“待核”）未逐个读源码；ScrollArea 的 38 个关回弹文件只列了代表；手拼按钮的约 60 处只按 `on_click` 绑定统计，未逐个判定语义；`Divider` 的 30 处含 `.yss` 与 `.zig`，可能含非分隔线的 1px 元素。
8. zenit `Hint` / `NotificationCard` / `Sheet` / `Menu` 能否替换下游实现未做评估。
9. 未核对 `widgetTokensFrom` 各映射与 zenit 默认值的逐项差异。
10. 未触碰 `~/work/ZeroWork-wt/**`；本文件为唯一新增文件，未 `git add` / commit。

## 变更：F-set-appearance（2026-11-13）

外观与主题面板的 `.yix` 路径不再使用 `styleInput`、`tuneInput`、`S.field` / `fieldControl`、`tuneSelect`、`panel_style`、`paintInputValidation`、
`controls.inlineHint` 的 Tooltip 覆盖、`plainButton` / `menuRow` / `control` 等 Button `base_style`：输入框 / 选择框 / 滑块 / Tabs / RadioGroup / Tooltip / Menu /
Popover / Button / Tag 全部是原生默认外观（只用 `size` / `variant` / `width` / `fill` 等组件参数）。这些覆盖在旧文件里仍存在（`.legacy` 外壳与旧组件测试在用，
S-15，随 3f 删除），所以上面清单 3 的调用点计数与 `check-arch` 基线本包没有减少。

## F-set-ai（2026-11-13）

AI 辅助面板的 `.yix` 路径上不再有 `styleInput` / `tuneInput` / `tuneSelect` / `paintInputValidation` / `paintControlText` / `tuneProviderText` / `stylePrimary` / 覆盖外观的 Tooltip（`tooltipOnly`、`S.fieldHelp`）/ 手工着色的状态徽标与默认徽标：全部换成原生 `W.Input` / `W.Select` / `W.Switch` / `W.Checkbox` / `W.Button` / `W.Tag` / `W.Badge` / `W.Tooltip` / `W.Menu` / `W.Textarea` / `W.Modal` 默认外观。上表与第 2 节里列出的 `ai_provider_settings.zig`、`ai_model_editor.zig`、`ai_extensions_settings.zig`、`provider_delete_dialog.zig` 调用点仍在源码里，只剩 `.legacy` 外壳会挂（S-15，随 3f 删除）；`check-arch` 基线没有缩短。头像（`W:y0dYR`）zenit 没有组件，用 `.yss` 圆形盒近似，待 G46 补上游后替换。

## 变更：set-modals（2026-11-13）

- 清单 1 第 18 行（清除全部数据确认）：`.yix` 路径已替换为原生 `W.Modal` 默认外观，见上表。第 16、19 行此前已由 H-save、F-set-panes-B 替换；
  第 17、20、21 行已由 F-set-ai、F-set-plugins 处理。
- 清单 2 / 4 中 `settings_picker.zig` 的手拼浮层（Menu 行、行按钮、`styleInput` 与 `input_container.setStyleInline`）：`.yix` 面板不再使用——“自定义 TERM 声明…”
  改为选择框下方的原生 `W.Popover`（默认面板）+ 原生 `W.Input`（无覆盖，校验用 `invalid` / `errorMsg`），内置 TERM 只在原生 `W.Select` 里列出；
  下载目录直接弹系统目录面板。旧文件只剩 `.legacy` 外壳在用（S-13、S-15，随 3f 删除），所以调用点计数与 `check-arch` 基线本包没有减少。

## 变更：native-buttons（2026-11-13）

- T-1 收回：删除 `stylePrimary`（全部调用）、Save 按钮底色 / 渐变覆盖与其余主按钮的底色 / 字色覆盖，同提交删除 `button_primary_*` 四个 token 的改写；主按钮一律原生 `W.Button` primary 默认外观。品牌应用图标的墨色改用新增的 `zw-primary-fg`（不是按钮角色）。
- 标题栏工具按钮改用 zenit 原生默认 md（32×32），删除 `titleToolbarButton`。
- 焦点：删除下游扩展 `zenit_ext/focus_fill` 与主题对 `bg_focus` / `border_focus` / `focus_ring` 的改写，改用 zenit 原生焦点环（键盘焦点描边、指针焦点不改底色）；按钮上的焦点环抑制一并删除。失焦停在悬停色的问题随之消失。
- 设置导航选中行（`nav_row_active`、`settings_shell.navRow`）读 `button-primary-*`，现在随 zenit 默认 primary（不再跟随调色板主操作色）。

## 变更：r3-tabs-toolbar（2026-11-13，design-r3 稿 3、稿 5）

- native-buttons 留下的一项已完成：标题栏的通信链路、端口转发、主题、组广播、命令历史不再是“原生 Button + `base_style` / `hover_style` +
  手工追加图标与标签”的拼装件，改为 `title_tools.yix` 里的原生 `W.Button`（ghost / md / icon only，32 × 32，图标 16），
  宿主只接点击与弹层锚点；`ssh_status_host` 在原生模式下不再写这些按钮的宽度、底色和图标着色。
- 传输管理：删除按钮里自绘的进度环、百分比文字与（一直隐藏的）计数徽标盒子；按钮是原生 icon-only，按阶段换 lucide 图标，
  进度写进原生 Tooltip / “⋯”菜单（“传输管理 · 传输进行中 · 42%”）。
- 每个工具包原生 `W.Tooltip`（600 ms，“名称 · 快捷键”，有状态写状态、不可用写原因）；“⋯”是原生 `W.Menu`，组间是原生 `W.Divider`，
  未读通知点是原生 `W.Badge`。删除 `icon_button_feedback` 对标题栏工具的自绘悬停反馈。
- 页签 Tooltip 改原生默认外观（删除 `background` / `text_color` / `font_size`、`tab_styles.tooltip()` 内联样式、材质绑定与换行改写）。
- 主窗口材质策略（`shared/ui/styles/layer_materials.zig`）原本给每个浮层根刷 overlay 底色与玻璃，原生 Tooltip 因此变成浅底浅字的空白气泡；
  现在跳过 `tier = .tooltip` 的层，Tooltip 用 zenit 自己的 `tooltip_bg` / `tooltip_fg`（单测：`material_popup_tests` “native Tooltip keeps …”）。
- 仍未替换（登记在 YIX_EXCEPTIONS W-1、W-2）：页签关闭钮、新建页签按钮、溢出箭头 / “全部页签”按钮的 `base_style` 覆盖；页签颜色色板。

## 变更：r3-tabs-2（2026-11-13，design-r3 稿 3 遗留）

- 会话页签条（清单“Tabs / 页签条”“手拼按钮”里 `workspace.zig` 的 `tabs.cell.*`）：改为 `workspace/view/tab_strip.yix`。关闭钮、“+”、“⌄ n”都是原生 `W.Button`（ghost，xs / sm），默认外观，删掉 `base_style` / `hover_style` / `pressed_style`；“⌄ n”菜单是原生 `W.Menu`；每个页签的提示是原生 `W.Tooltip`。左右滚动箭头与“全部页签”搜索选择器（`tab_picker.zig`）按稿 3 删除。页签面本身不是基础组件（Island B v3 的页签形状），由我们自己的 box + `tab_strip.yss` 画。
- 页签右键菜单（`menu_host` 手拼行）与会话组页签菜单（带 `base_style` 的 Button 列）：改原生 `W.Menu`（`workspace/view/tab_menu.yix`），颜色是原生子菜单；`tab_color_picker.zig`（手搓色板浮层）删除。终端中键菜单、主机菜单仍走旧的手拼面板（不在本包范围）。
- 收起的标题栏按钮：槽位 box `inert`（上游），不再能被 Tab 聚焦（W-4）。
- 首页“已保存的连接”：行改原生 `W.Pressable`，禁用原因用原生 `W.Tooltip`（r3-tabs-2-side）。


## 变更：settings-3f（2026-11-14，P3 3f）

- 设置窗口的 `.legacy` 外壳与旧命令式面板删除：上表与第 2 节里列在 `ai_provider_settings.zig`、`ai_model_editor.zig`、`ai_extensions_settings.zig`、`provider_delete_dialog.zig`、`application_data_cleanup_view.zig`、`keybinding_picker.zig`、`settings_picker.zig`、`panes/settings_*.zig`、`panes/appearance_view.zig`、`settings_content_view.zig`、`settings_styles.zig` 的调用点随文件一起消失（这些行此前已标“只剩 `.legacy` 外壳”）。`check-arch` 基线里这批文件的 `ident:no-inline-style` 16 条、`ident:no-widget-internals` 12 条随之删除（基线合计 −58：另有 `layer:view->core` 24、`cross-feature` 4、`ident:view-no-io` 2）。
- 新界面补齐时只用原生组件：通知授权回执是纯文本行；光标分段锁定用原生 `W.Tabs` 的逐项 `disabled`；删除导入主题用原生 `W.Button` danger；AI 的扩展提示、读屏文字只改文案与挂载位置，没有覆盖原生外观。

## 变更：panel-heads（2026-11-14 ~ 11-15，CONSISTENCY_AUDIT #4）

- 关闭按钮全应用一颗：`shared/ui/components/panel_header` 的 `PanelClose`（原生 `W.Button` ghost · sm · iconOnly · x 14 + 原生 `W.Tooltip`“关闭 · Esc”，Esc 不归它管的地方写“关闭”），删掉各处 `base_style` / `hover_style` / `icon_tint` / `appendChild(iconTint(x))`；命令式视图经 `mountClose`，要按钮节点时用出参 `button`（不再按 test_id 遍历）。新建文件夹的取消按钮也换成 `PanelClose`（去掉 `paintSignal` 的 `base_style` 与 control_hint）。原提示里的后果（“关闭窗口将取消本次连接”“收起后广播继续”“收起后创建继续”）改写在说明行与无障碍名里。
- 同级面板头部：共享 `PanelHeader`（图标 · 标题 · “N 条” · 动作区 · 关闭），与浮动外框头部同一规格；提醒的计数徽标改为“N 条”。
- 空状态：上游原生 `W.Empty`（图标 · 标题 · 说明 · 可选一个 secondary 按钮），各列表空状态改用它，原来的手搓空状态（图标 + 两行文字）删除。AI 的空状态不在本包（归 ai-redesign-a/b/c）。
- 窗格头部（W-5 收回）：`workspace/view/pane_header.yix`，广播 / 置顶 / 更多去掉 `base_style = group_styles.control()` 与 `icon_tint`，开启状态改为原生 `secondary` variant；“更多”仍经菜单唯一入口 `AppMenu.mountTrigger`（手写组件 `PaneMore` 当标签用）。
- 不在本包：确认框（confirm-undo 改为共享 `confirm(spec)`）、终端操作菜单（menus 包已改原生 Menu）的关闭按钮随集成分支，由 `ConfirmDialog` / 原生 Menu 提供。
