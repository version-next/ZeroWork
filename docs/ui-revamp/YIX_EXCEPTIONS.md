# Yix / Yss 例外登记

目标（2026-11-12 起）：ZeroWork 的视图层全部用 `.yix` + `.yss` 编写，Zig 只负责 model、view-model、host 与逻辑。
凡是视图仍留在 Zig 里的地方——自定义组件、样式覆盖、命令式挂载——都算**例外**，必须在本文件登记，不默认放过。

## 总则：基础组件只用 zenit 原生（硬性规则，无例外）

用户原话（2026-11-12）：“请所有基础组件！！都只用！！我们zenit的！！”

- ZeroWork 里所有基础组件一律只用 zenit 原生的：Button、Input、Select、Switch、Radio、Checkbox、Tooltip、Modal、Menu、ScrollArea、Notification / Toast、Glass 系列、Divider、Tabs、Popover、Card 等。
- 不许手搓；不许用 inline / `paint*` / `tune*` 覆盖它们的外观和行为；不许用 Yss 模仿原生组件。外观以 zenit 默认 token 为准，ZeroWork 主题不再改写这些组件的角色 token。
- zenit 缺某个基础组件或能力：补上游，不在下游自造。
- **这一条不接受“例外登记”**：本文件登记的是“视图暂时写不成 yix / yss”的例外；手搓或覆盖基础组件不属于可登记的例外，只能列入 [NATIVE_AUDIT.md](NATIVE_AUDIT.md) 的替换清单并限期替换。
- 护栏：`check-arch` 的 `no-inline-style` 与 `no-widget-internals` 规则（基线只能缩短）。

类别：

- **(a)** Yix / Yss 能力缺失（zenit 缺口，写 G 编号，编号定义见 `YIX_SPIKE.md`）。默认处理：补 zenit 上游，然后收回到 `.yix` / `.yss`。
- **(b)** 本质是命令式，或渲染到原生 / GPU 的部分（终端表面、KVM 画面、虚拟列表容器等）。
- **(c)** 其他。

(b)、(c) 以及“倾向 (a) 但需要给 zenit 增加较大的新公开能力”的条目，由用户判定；判定前只登记，不自行定为永久保留。

状态：`待补上游` / `上游已补待收回` / `待用户判定` / `过渡（随某步骤消失）` / `已收回`（保留记录，注明提交）。

## 设置窗口（`src/features/settings/`）

范围说明：外壳（窗口、导航、页头、概览、Save Bar）已是 `.yix`；面板正文 3e 起逐个分类改写：通知、SSH 与网络、文件传输、数据与日志已是 `.yix`（F-set-panes-A，`view/panes/{notify,ssh,transfer,data}.yix` + `components/rows.yix`），快捷键、关于与更新（F-set-panes-B），外观与主题（F-set-appearance，`view/panes/appearance.yix`）；协议插件（F-set-plugins，两级导航：`view/panes/plugins.yix` + `plugins.yss`，列表行是 `components/rows.yix` 的 `DrillRow`），AI 辅助（F-set-ai，`view/panes/ai*.yix`）；面板正文已全部是 `.yix`；3f（settings-3f）删除了 `.legacy` 外壳与全部旧命令式面板（S-7、S-13、S-15），设置窗口里留在 Zig 的只有 S-8（`Frame` / `Page` 接口）、S-16、S-18。

| # | 文件 / 组件 | 为什么现在写不成 yix / yss | 类别 | 建议 | 状态 |
|---|---|---|---|---|---|
| S-1 | `view/components/shell/mod.zig` · `SaveButton`（“保存更改”） | 渐变随悬停 / 按下 / 主题发布逐帧写入；YSS 的 `gradient` 没有 token 写法，读主题的样式不能带 `:hover` / `:active` 条件块，渐变端点也不是 token | (a) G17、G15 | 补上游：渐变支持 token 与状态条件；Button 状态样式接受配方 / token | **已收回**（`657e8874`）：`save_bar.yix` 的 `W.Button look={S.save_fill}`，新增 token `zw-primary*`；Zig 组件删除；H-save 再去掉 `look` 覆盖，改为原生 primary `W.Button`（`size=.sm`），删除 `save_fill` 与 `zw-primary-hover*` / `zw-primary-pressed*` |
| S-2 | `view/components/shell/mod.zig` · `HelpButton` | Tooltip 的 trigger 插槽只有 Zig 视图 API，Yix 没有写法；`settings.help.content` 所在节点不在 `viewParts`，`parts` 够不到；玻璃外观是只收具体颜色的 Button 状态样式 | (a) G16、G15 | 补上游：Tooltip 的 Yix 形态（children 进 trigger、`parts` 暴露 content） | **已收回**（`5c2db63e`）：`header.yix` 的 `<W.Tooltip … parts={.{ .content = … }}><W.Button … look={S.glass_icon} /></W.Tooltip>`；Zig 组件删除 |
| S-3 | `view/*.yix` 里为绕开限制而拆出的行组件 / `computed` 中转 | 配方维度值里不能写行变量的字段访问或带参调用（`S.R.of(.{ .on = x.on })` 编译错误） | (a) G14 | 补上游：维度值按普通属性表达式处理 | **已收回**（`b7df4a0a`）：`NavEntry` / `OverviewEntry` 并回 `{for}`，`computed` 中转删除；后退 / 前进改用 look（`:disabled` 写在 look 里）。内联后发现 G21（行内派生先于列表协调重算），以行数据自带分类绕开 |
| S-4 | `view/components/shell/mod.zig` · `SearchField` | 宿主要拿输入框的挂载句柄：清空文字、主题发布后重绘（`paintSearch` 写的是输入框状态而非节点样式） | (a) G18：缺受控输入值（`value` 绑定信号，宿主改信号即清空，重绘由框架负责） | 补上游后收回 yix（用户已定：补上游） | **已收回**（`4a170ae9`，vendor @ed8e829e）：`nav.yix` 的 `W.Input value={searchField(vm)} onChange=…`，view-model 的 `search_field` 信号同步写回、导航清空；删除 `SearchField`、`Effect.clear_search_field`、`Frame.search`。旧搜索框“首次聚焦后圆角 14→4”的隐性行为曾按原样保留（`search_focused` + `styleBy`，G24 绕法）；H-shell 已删除，搜索框是原生 `W.Input` 默认外观 |
| S-5 | `view/components/shell/mod.zig` · `NavScroll`、`Viewport` | 宿主要拿 `ScrollState`，切换页面时记住并在 after-layout 钩子里恢复滚动位置 | (a) G19：缺可绑定到信号的滚动位置 | 补上游后收回 yix，滚动位置进 view-model（用户已定：补上游） | **已收回**（`d1eac26c`）：`page.yix` / `nav.yix` 的 `W.ScrollArea`；view-model 每个位置一个偏移信号（`ScrollSlot`，33 个，规则同原 `mountedScrollOffset`），`scrollY={pageScroll(vm)}` + `onScrollYChange` 同步存档；删除两个 Zig 组件（`components/shell` 整个目录）、`.yix` 路径的滚动记忆与 after-layout 恢复 |
| S-6 | `host/settings_host.zig` 对 `settings.panel` 的按键捕获（Escape / ⌘W）与可聚焦设置；焦点快照与恢复、`setFocus` | 用的是捕获阶段的按键处理，Yix 的 `onKeyDown` 不等价；没有声明式的焦点 API | (a) G20：缺捕获阶段事件属性与声明式焦点 API（快照与恢复） | 补上游后收回 yix；先在 zenit 写设计说明再实现（用户已定：补上游） | **已收回**（`28a30d33`）：模板根 `onKeyDownCapture` → `ViewModel.windowKey`（纯函数键位 + `Gate.window_keys` + `Intent.window`），`focusRequest`；内容列 `focusRestore`；卡片不再可聚焦。宿主保留：Escape 的分层收起（旧正文 / 提供方 / 选择器 / 材质预览是宿主与 S-7 的状态）、关窗、跨窗口回焦主窗口、重挂前 `Page.releaseFocus`（S-7 过渡，见下） |
| S-7 | `view/components/legacy_body/mod.zig` · `LegacyBody`（未改写分类的面板正文——外观与主题、快捷键、AI 辅助、协议插件、关于与更新；一个分类一份，经 `panes/registry.yix` 登记表挂载：`settings_content_view.zig`、`panes/*`、`ai_provider_settings.zig`、`ai_extensions_settings.zig`、`ai_model_editor.zig`、`settings_picker.zig`、`keybinding_picker.zig`、`provider_delete_dialog.zig`、`application_data_cleanup_view.zig`、`settings_styles.zig` 等旧命令式视图与样式） | 尚未改写；经 `ComponentOf` 嵌入 | 过渡 | 3e 按分类逐个改成 `.yix`，改写时遇到的具体例外逐条登记 | 过渡（3e）：F-set-panes-A 已拆出通知 / SSH / 传输 / 数据四类，F-set-panes-B 拆出快捷键、关于与更新，F-set-appearance 拆出外观与主题（旧文件只剩 `.legacy` 外壳在用，见 S-15）；F-set-plugins 拆出协议插件（两级导航）；F-set-ai 拆出 AI 辅助（`view/panes/ai*.yix`）——九类已全部拆出：`.yix` 窗口里 `registry.yix` 的 `<Legacy.LegacyBody>` 兜底分支已不可达（0–8 类都有自己的 `.yix` 面板），`LegacyBody` 与 S-8 的旧正文句柄可以随 3f 删除（本包未删，避免与在途包冲突）；`settings_window_yix_tests` 的 V-5 用例已改为守住“不再挂旧正文”；**已删除**（settings-3f）：`components/legacy_body` 与它嵌入的全部旧命令式视图、样式与只测它们的用例删除；`registry.yix` 的兜底分支随之删除，九个分类都直接挂 `.yix` 面板。 |
| S-8 | `view/window_frame.zig` · `Frame`（窗口级句柄：旧正文、重挂纪元的宿主侧容器） | 承接旧正文（S-7）的句柄与两阶段重挂 | 随 S-7 | S-7 解决后删除 | 过渡（已缩到最小，随 S-7 删除）：S-4 – S-6 收回后 `Frame` 只剩 `vm`、`hooks`、`body`、`body_scope` 与 `page(window)`；`Page` 只剩旧正文的 `binding`（输入法组合判定、Escape、`releaseFocus`）与旧外壳的滚动区。两阶段重挂（纪元）保留：面板正文仍是旧命令式实现，只能整页重挂；**已缩到最小**（settings-3f）：`Frame` 只剩 `vm` 与外观上下文 `appearance`（S-18 的材质图层挂载要用）；旧正文句柄、`attachBody` / `hasLegacy` / `ownsScope` 删除；`Page` 只剩内容页根与 `releaseFocus`（`Page.of(window)`）。两阶段重挂（纪元）保留。usage-b1-contract：宿主不再按 test_id 在窗口树里找节点——卡片、内容岛、内容页根由窗口模板的 `ref()` 经 `Frame.handles` 交出（live Ref，内容页重挂时自动换新、窗口卸载时收回），`Page.of(frame)`。 |
| S-9 | `src/features/shell/host/nav_host.zig` 在主题发布时改写设置页头标题颜色 | 历史代码；写进去的值与 `.yss` 相同，属于冗余的命令式样式写入 | (c) | 冗余，直接删除（行为不变；不需要用户确认） | **已清理**（`de17126b`）：删除写入及只为它服务的 `SettingsHost.header_title`；组件测试证明标题墨色随主题发布自行变化 |
| S-10 | 生产设置窗口的标题栏拖动带（`titlebar = .custom_inset` + `titlebar_height`，由 `aux_window.Spec` / `process_windows.zig` 配置） | 不是 Yix 写法；此前因 `settings.panel` 可聚焦，拖动带内推断没有可拖点（见 `YIX_SPIKE.md` “P3 实证” V-11） | (c)：Yix 已有能力（`windowRegion`），尚未采用 | 切到 `chrome = .custom` + `windowRegion={.drag}`；原生拖动需人工验证 | 待用户判定：S-6 后卡片不可聚焦，runner 自检里拖动带恢复 4693 个可拖点（此前 0，`3d69435d`）。**不切** `chrome = .custom`：要给共用的 `aux_window.Spec` 加字段、在 `process_windows.zig` 分支（向导等共用这条路径），换来的只是 Yix 写法；原生拖动 / 双击缩放 / 红绿灯都无法实证。拖动带本身的真实拖动也未实证（手工步骤见 `YIX_SPIKE.md`）。**H-shell 补充**：页头改成玻璃外观后，视口从页头下方开始、不伸到页头（标题栏拖动带）底下——曾让视口占满整列、页头浮在上面，结果页头空白处底下是滚动区的命中目标，`.custom_inset` 下不再能拖窗口、V-11 自检报 4002 个冲突点，已改回。生产窗口实证（`e2e/h_shell_capture.ts` 的 (e)，明 / 暗）：把开关滚到一半在视口上缘之外时，点它在页头高度范围内的部分不会切换开关（草稿不变），点它在视口里露出的部分照常切换——滚上来的控件不会被拖动带“抢走”点击，因为它们在页头范围内根本不显示、不可命中。**settings-header（第 2 轮验收，照 znote 画板详情页 header）**：视口改为占满整列、正文从浮动页头底下滚过（znote 的做法）；页头整条 `windowRegion={.drag}` 且 `hit-behavior: opaque`，上游让 `.custom_inset` 的拖动判定（`Cx.legacyWindowControlAt`）先认 `windowRegion=.drag`：页头空白处仍拖动窗口，胶囊按钮仍是控件，滚到页头下的正文点不到；仍**不切** `chrome = .custom`。 **usage-b3-titlebar（zenit 用法整改批次 3）：已收回。** 所有生产窗口（主窗口两处入口、`aux_window.Spec.chrome` → 设置窗口与连接向导窗口）改用 `WindowConfig.chrome = .custom`，拖动区全部由视图声明：设置窗口 = 导航列顶边 8 + 导航标题带（`nav.yix` 的 `windowRegion={.drag}`）+ 页头（`header.yix`，原有）；主窗口 = 视图栏 + 侧栏标题带，页签条与工具组是 `.client`；向导 = 标题行。上游 `.custom_inset` 认 `windowRegion` 的桥接（`c48c9de4`）随之剥离。迁移前后主窗口 / 设置 / 向导亮暗截图逐像素相同，拖动判定网格对照见 `e2e/window_chrome_regions_native.ts`；真实鼠标拖动 / 双击缩放仍需人工确认（原生层两条路径共用同一段 `zenitArmTitlebarMouseDown` → `performWindowDragWithEvent:` / 双击处理，差别只在命中回调）。 |
| S-11 | `view/panes/appearance_view.zig`：外观页切换开关时宿主重建整块面板（`draft_changed` → `pending_rebuild`），开关成为新节点出现，没有滑动动画 | 面板正文是旧命令式实现，状态变化靠整页重建而不是按信号局部更新（S-7 的具体表现；用户可感知，且违背“行为以 zenit 原生为准”） | 过渡 | 3e 重写外观面板时改为按信号局部更新；修好后把 `e2e/switch_initial_state_native.ts` 里外观页开关的断言改回“同一节点必须滑动” | **已修**（F-set-appearance）：外观面板正文改成 `.yix`（`view/panes/appearance.yix`），草稿变化按信号局部更新、不重挂；组件测试 `settings appearance yix: switches slide in place …` 断言整个分类的节点指针不变且滑块在走过渡；`e2e/switch_initial_state_native.ts` 的外观页断言改回 `expectSlide`（同一节点必须滑动），light / dark / `--material` 实测通过 |
| S-12 | `view/application_data_cleanup_view.zig`（数据与日志 ›“清除全部数据…”的确认流程，宿主 `showDataCleanup` 挂的模态） | 面板本身已是 `.yix`（`panes/data.yix` 的按钮只发 `Command.clear_all`）；确认流程是宿主持有的命令式模态，体量大（阻塞复查、进行中、失败重试 / 退出、结果回焦），本包没有改写 | 过渡 | 并入 Modal 收回的后续包（未保存 / 恢复默认确认弹窗已由 H-save 改成 `.yix` + view-model 状态，本条剩数据清理流程） | **已收回**（set-modals）：`view/data_cleanup.yix` 的窗口级原生 `W.Modal`（默认遮罩 / 面板 / 标题栏，内容控件原生无覆盖），流程状态机与文案在 `model/data_cleanup.zig`（单元测试），view-model 持有状态（`Intent.cleanup` / `Effect.data_cleanup`），宿主只做检查、清除、失败回报与回焦；test_id 不变。旧文件只剩 `.legacy` 外壳在用（S-15） |
| S-13 | `view/settings_picker.zig`（“自定义 TERM 声明…”的原地编辑、下载目录的系统目录面板转发）与 `keybinding_picker.zig`，由宿主 `requestContentEdit` 挂到卡片上 | `.yix` 面板经 `Intent.choose` → `Effect.request_edit` 请求，宿主按 `settings.field.<key>` 找锚点、挂到自己的 `picker_scope`；选择器本身仍是命令式浮层（锚定定位、高度翻转、外部点击收起归宿主） | 过渡（倾向 (c)：Yix 已有 `W.Popover`，未改写） | 自定义 TERM 改成 `.yix` 的 `W.Popover` + 受控 `W.Input`（view-model 持有草稿）；目录面板直接走 `Effect`（不需要浮层）；快捷键录制器随快捷键包 | **`.yix` 面板已收回**（set-modals）：自定义 TERM 是 `rows.CustomSelectRow` 里选择框下方的原生 `W.Popover`（受控开合）+ 原生 `W.Input`（草稿与校验问题归 view-model：`Intent.custom_text` / `custom_submit`）；下载目录走 `Effect.pick_directory`；`Effect.request_edit` 与宿主 `requestYixEdit` 删除；快捷键录制器已由 F-set-panes-B 改行内录制。`settings_picker.zig` 与宿主 `requestContentEdit` / `picker_scope` 在 `.yix` 窗口里已没有调用点（F-set-ai 合入后九个分类全是 `.yix`，`registry.yix` 的 `LegacyBody` 兜底分支不再有分类走到），只剩 `.legacy` 外壳在用：随 3f 删除（S-15）。锚定写法见缺口 G45；**已删除**（settings-3f）：`settings_picker.zig`、`keybinding_picker.zig`、宿主 `requestContentEdit` / `picker_scope` / `picker_nodes` / 录制状态删除。 |
| S-14 | `view/components/rows.yix` · `InputRow` 的单位后缀写在输入框外（`input_slot` + `input_unit`），不是原生 `W.Input` 的 `appendText` | `W.Input` 的 `append_text` 是普通值字段（`?[]const u8`），行组件里的单位来自参数（`Source`），传不进去（编译错误） | (a) G25 | 补上游：builder 组件的普通值字段收到 `Source` 时挂载期取值（同 `testId`），或 `append_text` 改为 `Source(?[]const u8)`；补上后改回原生后缀 | **已收回**（本包 F-set-panes-A-fix）：`InputRow` 用原生 `<W.Input appendText={unit(row)} …/>`，删去 `input_slot` / `input_unit`；输入框右缘回到卡片右内边距 14 |
| S-15 | `view/panes/settings_{notify,ssh,transfer,data}.zig` 与 `settings_controls.zig` 中只为它们服务的部分（`directory`、`readonly`、`iconAction`、通知授权行）；F-set-panes-B 追加：`panes/settings_keys.zig`、`panes/settings_updates.zig`、`panes/settings_updates_styles.zig`、`view/keybinding_picker.zig`（`.yix` 路径不再引用；宿主 `requestContentEdit` 的 `keys` 分支只剩旧正文会走到）与 `tests/keybinding_recorder_tests.zig`、`settings_picker_tests` 的录制对话框用例；F-set-appearance 追加：`panes/appearance_view.zig`、`panes/appearance_styles.zig`、`panes/settings.zig`、`view/appearance_ui_context.zig`（`.yix` 路径只剩宿主仍经 `Context` 持有外观状态、`Frame.hooks.appearance` 给 S-18 的材质图层挂载函数）与 `settings_content_tests` 的外观用例；F-set-plugins 追加：`panes/settings_plugins.zig`（主从布局与版本 / 权限对话框；`.yix` 路径不再引用，说明 / 权限文案已搬到 `model/plugin_pane.zig`，旧文件委托过去）与只测它的 `tests/plugin_settings_v3_tests.zig` 首个用例、`settings_content_tests` 的 "plugin design previews never become production settings"；F-set-ai 追加：`panes/settings_ai.zig`、`view/ai_provider_settings.zig`、`view/ai_model_editor.zig`、`view/provider_delete_dialog.zig`、`view/ai_extensions_settings.zig`、`view/settings_mcp_styles.zig`（`.yix` 外壳不再挂；宿主的 `mountProviders` / `mountExtensions` / `mountProviderAction` 与 `providers` / `extensions_view` 句柄只剩 `.legacy` 外壳会走到）；set-modals 追加：`view/application_data_cleanup_view.zig`、`view/application_data_cleanup_styles.zig` 与 `tests/application_data_cleanup_ui_tests.zig`（`.yix` 路径改用 `data_cleanup.yix`，旧命令式对话框只剩 `.legacy` 外壳的 `showDataCleanup` 在挂）、`view/settings_picker.zig` 与 `tests/settings_picker_tests.zig`、宿主 `requestContentEdit` / `picker_scope`（`.yix` 窗口已无调用点） | `.yix` 外壳已不再挂它们；`.legacy` 外壳（`settings_view_mode` 的回滚开关）与旧面板的组件测试（`settings_transfer_budget_tests`、`settings_notification_permission_view_tests`、`settings_content_tests` 的部分用例）仍经 `mountPage` 挂它们 | 过渡 | 3f 删除 `.legacy` 外壳时一并删除（建议提前：`.legacy` 已不代表生产行为） | 过渡（3f）；**已删除**（settings-3f）：`.legacy` 外壳与开关（`settings_view_mode.zig`）、`settings_shell.mount`、`settings_content_view.zig`、`settings_vm_adapter.zig`、`settings_accordion.zig`、`settings_styles.zig`、`panes/settings*.zig`、`panes/appearance_view.zig` / `appearance_styles.zig`、AI 旧视图、旧数据清理对话框与选择器全部删除；只测旧视图的组件测试删除，仍有意义的用例（搜索别名、长目录、传输预算修复、通知授权回执）迁到 `.yix` 夹具。 |
| S-16 | `view/titlebar_edge.zig` · `TitlebarEdge`（页头下的标题栏边缘渐变，人工验收反馈 3） | 原生 `W.glass_toolbar.titlebarEdge` 是普通函数，没有 Yix 组件形态；能做“滚到页头下面才出现的渐进磨砂”的 `GlassBox.scroll_edge` 要同级 `W.ScrollArea` 的 `*ScrollState`，Yix 里拿不到 | (a) G28 | 补上游：`W.TitlebarEdge` 组件、`W.ScrollArea` 的 `scrollEdge` 参数；补上后删本文件，在 `page.yix` 里直接写 | **已收回**（`4dc5b27b`、`9badf52d`，vendor @bc57f042 带入上游 G28）：`page.yix` 直接写 `<W.TitlebarEdge />`，删除 `view/titlebar_edge.zig`；视口加原生 `scrollEdge`（滚到页头下方才出现的渐进磨砂，带子贴视口上缘、不伸进标题栏拖动带，S-10 约束不变） |
| S-17 | `view/header.yix` 页头浮动按钮用“`W.GlassBox` 胶囊 + 原生 ghost `W.Button`”，`view/nav.yix` 的 `W.GlassBox` 写 `height={0}` + 根 `style` 填满 | 原生的 macOS 工具栏按钮组 `W.GlassToolbar` 没有 Yix 形态、按钮没有禁用态（G27）；`W.GlassBox` 不能按父容器拉伸高度（G29） | (a) G27、G29 | 补上游后换成 `GlassToolbar` 按钮组、去掉 `height={0}` | **已收回**（`eded65de`、`4ccc0ed9`，上游 G27、G29）：页头后退 / 前进是一颗 `W.GlassToolbarGroup` 里的两个 `W.GlassToolbarButton`（禁用态用按钮自己的），帮助是单按钮胶囊（外面仍是原生 `W.Tooltip`）；`nav.yix` 的 `height={0}` 换成 `fill={.height}`。工具栏按钮不进 Tab 顺序（同 macOS 原生） |
| S-18 | `view/components/material_preview.zig` · `MaterialPreview`（外观与主题 › 背景图片的行内材质预览图层，`settings.background.preview.image`） | 复用宿主的窗口材质图层（`shell/view/background_layers.zig`：背景图片纹理、平铺 / 对齐几何、模糊与透明度的合成层，after-layout 钩子按实际尺寸更新）——与主窗口真实背景同一套绘制，预览不漂移；纹理归宿主（`draft_texture` / `committed_texture`），经 `Frame.appearance.mount_material_preview` 挂载 | (b) 渲染到原生材质 / GPU 纹理 | 保留为最薄的 `ui.view.component` 适配（不改外观、不碰内部节点）；若要收回 yix，需要 shell 把 `background_layers` 做成 Yix 组件（输入：纹理 + 材质参数），属 P5 shell 波次 | 待用户判定（建议随 P5 shell 的背景图层一起改，不单独补上游）。set-modals 修了它与缩略图共同的空白缺陷：背景纹理原先进主窗口自己的纹理表，设置窗口解析不到；现在进进程共享纹理表（`shell/model/background_texture.zig`），适配本身未改 |
| S-19 | `host/settings_host.zig` · `toast`：设置窗口的保存成功 / 失败提示由宿主命令式 `W.Notifier.init(scope, cx, …)` + `hint(…)` 弹出（H-save） | `W.Notifier` 只有命令式 API，没有 Yix 形态（缺口 G38）；view-model 发 `Effect.saved` / `.save_failed`，宿主调原生 API，不画任何节点 | (a) G38 | 补上游：`<W.Notifier>` 组件或窗口级通知服务；补上后宿主不再持有 Notifier 指针 | **已收回**（`85923922`，上游 G38）：`save_bar.yix` 挂 `<W.NotificationHost post=… />`，请求来自 view-model 的 `toast` 信号（`ToastAsk`，模板换成 `NotificationPost`）；宿主删掉 `notifier` 与 `toast()` |

已收回（F-set-shell、F-set-thin、F-set-recover、F-set-handles）：“保存更改”（S-1）、页头帮助（S-2）、为绕开 G14 拆出的行组件（S-3）、搜索框（S-4）、滚动容器（S-5）、整窗按键与焦点（S-6）；外壳颜色覆盖 → `zw_*` token + `.yss`；`NavRow`、`OverviewRow` → `W.Pressable`；`FieldInput`、`FieldSelect` → `W.Input` / `W.Select` + `parts`；Save Bar 的“恢复默认 / 撤销”；`StatusLine` → view-model 投影；概览行的 G21 绕法（`0f586202`）。设置外壳里 Zig 写的视图只剩旧正文（S-7）及其桥接（S-8）。

## 通知与反馈（`src/features/notifications/`，终端命令失败提示，AI 反馈条；native-notify）

每个应用窗口两个原生通知栈（`view/toast_stack.yix` 的两个 `<W.NotificationHost>`，用户判定）。分流规则只有一处，`model/view_model.zig` 的纯函数 `laneFor`：不带动作的成功或信息类消息走中下方标准 Toast（zenit 默认位置：本地回执、插件 / 内置内容的无动作反馈），带动作或需要处理的走右上角卡片栈（全局提醒、命令失败提示、操作失败）。中下方 Toast 永远在最上层（zenit toast 层高于宿主菜单、面板、对话框），被浮层盖住时既不隐藏也不暂停计时；右上角卡片栈仍按宿主遮挡规则隐藏并暂停（操作失败例外）。通知历史与 AI 反馈条改 `.yix` 原生组件，外观全部 zenit 默认、没有覆盖。上游补了 G49–G54（见 `YIX_SPIKE.md`“窗口通知栈”）。下列是原生组件承载方式与旧实现不同、需要用户判定的地方（功能都在，位置 / 语义有变）：

| # | 文件 / 组件 | 与旧实现的差别 | 类别 | 建议 | 状态 |
|---|---|---|---|---|---|
| N-1 | `host/notification_presenter.zig` · `acknowledgeAt`（已复制选中内容、路径已复制、目录已刷新） | 旧实现贴在触发点旁（复制按钮、菜单项、刷新按钮上方）；native-notify 时放进了右上角通知栈；现在是窗口中下方原生标准 Toast（第二个 `<W.NotificationHost>`，zenit 默认 `.bottom_center`，容器 `notifications.toasts`）里的一条成功文字提示 | (b) 原生组件的位置模型不同 | 用户判定：本地回执用中下方标准 Toast，与右上角卡片栈分开 | **已收回**（notify-two-hosts：view-model 分 `cards` / `toasts` 两条通道，回执只进 `toasts`；不贴近触发点，不需要补上游“锚定的单条提示”） |
| N-2 | 全局提醒、命令失败提示的计时 | 旧实现悬停 / 聚焦 / 展开结束后重新给满时长（4 / 8 秒）；原生栈从冻结的剩余时间继续（悬停暂停、焦点暂停 G51、用户展开详情暂停 G49 都是冻结）。窗口失焦、面板离屏时卡片收起，回来时给满（与旧实现一致） | (b) 原生计时语义 | 接受原生语义 | 待用户判定 |
| N-3 | `terminal/view/command_error_hint_view.zig` | 旧实现在所属终端面板右上角内；现在在窗口通知栈（标题含退出码，命令行一行，输出预览是展开的详情）。面板不在屏幕上时收起（不在别的标签页弹出），回来后重新弹出 | (b) | 接受 | 待用户判定 |
| N-4 | `ai/pane/view/ai_feedback.yix`（AI 反馈条） | 原生 `W.Alert` 不暴露部件：`ai.feedback.dismiss` 是 Alert 外侧单独一颗原生 ghost `W.Button`（没用 Alert 自带关闭钮），`ai.feedback.text` 在 Alert 根上，`ai.feedback.rollback` / `.warning` 挂在外层行（旧实现挂在图标上） | (a) 候选：Alert 的 parts（close / message 的 test_id） | 补上游 Alert parts 后改用自带关闭钮；或接受现状 | 待用户判定 |
| N-5 | `view/notification_history.yix`（通知历史弹层） | 列表高度固定 152–320，不再随窗口高度（旧实现 窗口高 − 140）收缩，很矮的窗口交给原生 Popover 自身约束 | (a) 候选：同 G44（浮层高度上限随视口） | 随 G44 一起补上游 | 待用户判定 |
| N-6 | `notifications/mod.zig`（门面） | 新增导出 `NotificationPresenter`、`NotificationPlacement`、`acknowledgeAt`、`toast`、`windowToasts`，让终端 / 文件 / 传输 / 菜单 / 窗口宿主经门面接入（替代 6 条跨 feature 直引）。notify-two-hosts 后签名不变：`windowToasts` 返回的 view-model 内含两条通道（`showCommand` 进右上角卡片栈），名字沿用（签名冻结，toast-top 也不改名）。toast-top 没有新增导出：窗口宿主经已有的 `toast` 命名空间用 `toast.laneFor` 分流，经 `NotificationPresenter` 的 view-model 发无动作反馈 | 流程 | 门面签名冻结（ARCHITECTURE_PLAN §5.1），需主干泳道确认 | 待确认 |
| N-7 | test_id `notifications.toast.1` / `.toast.2` / `.dismiss.1` / `.dismiss.2` | 删除：旧三槽位里从未显示的两格（协调器每窗口只给一条）；原生栈没有固定槽位。`e2e/global_notification_content_native.ts`、`notification_policy_native.ts`、`ai_v3_states_native.ts`、`notification_v3_native.ts` 引用了它们 | 接口变更 | 接受，同步改这几个 e2e | 待用户判定 |

## 连接（`src/features/connections/`，r3-connections：design-r3 稿 1、稿 4）

连接失败 / 重试视图（`progress/view/connection_failure.yix` + `.yss`，投影 `progress/model/failure_view.zig`）与跳板引导
（`wizard/view/jump_guide.yix` + `.yss`）是 `.yix`，基础组件全部原生（`W.Alert`、`W.StatusBadge`、`W.Progress`、`W.Button`、
`W.NotificationHost`），外观无覆盖。它们挂在仍是命令式的旧视图里：

| # | 文件 / 组件 | 为什么现在还在 Zig | 类别 | 建议 | 状态 |
|---|---|---|---|---|---|
| C-1 | `progress/view/connection_progress_view.zig` · 进度卡片（连接中、等待认证、取消、协议就绪等非失败态；日志折叠、节点 Tooltip、诊断浮层） | 本包只按稿 1 改写失败 / 重试 / 主机密钥变更三态；卡片其余状态体量大（1400 行命令式，含手写按钮皮肤），不在稿 1 范围 | 过渡 | 进度卡片整体按 `.yix` 重写时一并收回；失败视图已是独立 `.yix`，届时直接复用 | 过渡（待排包） |
| C-2 | `plugins/remote/editor.zig` · RemoteEditor（连接向导三步表单，命令式 Zig） | 视图仍由 Zig 装配（约 200 个保留节点句柄由三步状态机直接改写：显隐、文字、路径预览、检测日志行），模板化要先把这套状态机改成 view-model（信号 / 列表源），属于 P5 插件分层的重写。usage-b5c 已把其中的**基础组件全部恢复原生用法**：Button / Select / Input / Textarea / Checkbox / RadioGroup / Tooltip / Modal / ScrollArea 只经公开 props、插槽与结果部件使用，默认外观，无内联样式、无逐帧重绘、无内部子节点 / parent / `event_context` 访问、无 test_id 字符串判断；自带内容的可点行是 `W.Pressable`，外观是 `plugins/remote/editor_rows.yss` 的 YSS `look`（高级选项开关、检测节点卡片的选中底色 `selection-bg`、核对页返回行、检测卡片标题行；随主题由 zenit 按行自身状态解析，不再在挂载时取定值）；密码显示走原生 `Input.revealed`（字段始终是密码字段）；本视图只保留布局盒与文字。稿 4 的空态与“新建跳板主机”子流程是 `.yix`，经 connections 门面 `jump_guide_view` 挂进来 | 过渡（P5 插件分层） | 向导 `.yix` 化时把 `JumpEmpty` / `JumpChildBanner` / `JumpChildFooter` 直接放进新模板；届时 `L`（布局盒）与 `wizard_styles.zig` 里只剩布局的函数改成 `.yss` | 过渡（待 P5；原生控件用法已整改，usage-b5c） |
| C-3 | `wizard/view/connection_stepper.zig` · 步骤条（SSH / SFTP 与 BMC 两个编辑器共用） | 步骤是“序号徽标 + 标题”的可点行：usage-b5c 起根是 `W.Pressable`（原先是隐藏了内部子节点的 `W.Button`），外观是 `connection_stepper.yss` 的 YSS `look`（各状态相同；删去两个编辑器的样式信号与对 Pressable 根的内联样式）；仍是 Zig 因为两个命令式编辑器按节点句柄重绘当前 / 完成 / 出错三态 | 过渡 | 随 C-2 一起模板化（或评估 zenit 原生 `W.Steps` 是否满足“可点回退 + 出错态”） | 过渡（待 P5） |

## 页签条与标题栏工具组（r3-tabs-toolbar：design-r3 稿 3、稿 5）

标题栏工具组（`shell/view/title_tools.yix` + `.yss`，规则 `shell/model/title_tools.zig`）是 `.yix`，基础组件全部原生
（`W.Button` ghost / md / icon only、`W.Tooltip`、`W.Divider`、`W.Menu`、`W.Badge`），外观无覆盖；页签命名规则在纯模型
`workspace/model/tab_naming.zig`。仍留在 Zig 的：

| # | 文件 / 组件 | 为什么现在还在 Zig | 类别 | 建议 | 状态 |
|---|---|---|---|---|---|
| W-1 | `workspace/view/workspace.zig` · 页签条 | 稿 3 时页签条是约 400 行命令式代码 | 过渡 | 页签条按 `.yix` 重写 | **已收回（r3-tabs-2）**：页签条是 `workspace/view/tab_strip.yix` + `tab_strip.yss`（挂一次、按页签 id keyed 原地更新），关闭钮 = 原生 ghost xs 图标 `W.Button`、“+” = 原生 ghost sm 图标 `W.Button`、溢出 = 原生“⌄ n” `W.Button` + `W.Menu`、提示 = 原生 `W.Tooltip`，全部去掉 `base_style` / 悬停覆盖；页签面外观由 yss 样式函数按信号算出，workspace 不再写节点样式。留在 Zig 的只有 `tab_strip_view.zig` 的手写组件 `TabCell`（页签单元外层盒子 + zenit 拖动绑定：绑定占用节点事件槽、要行自己的 scope，模板写不出；这是 YIX_REFERENCE 推荐的“手写 Zig 组件当标签用”的写法），以及每次渲染给我们自己的 `tab_bar` 盒子设定确定宽度（让标题栏不被内容撑宽） |
| W-2 | `shell/view/tab_color_picker.zig`（页签颜色） | 手搓色板 | (c) | 改成原生 `W.Menu` 子菜单 | **已收回（r3-tabs-2）**：页签菜单（会话页签、会话组页签）改原生 `W.Menu`（`workspace/view/tab_menu.yix`；menus 包后并入 `shell/view/app_menu.yix`），“颜色：当前值 ›”是原生子菜单（跟随环境 · 红橙琥珀绿蓝紫 · 无），色块用上游补的 `MenuItem.icon_tint`；`tab_color_picker.zig` 删除。`shared/ui/components/color_palette` 仍由资产分组颜色（`asset_group_host`）使用，不在本条范围 |
| W-3 | `connections/progress/host/ssh_status_host.zig` · 状态栏旧标签 / 图标 | 标题栏的链路 / 转发 / 主题 / 广播是原生按钮后，旧状态栏的标签与图标（`chain_label`、`forward_label`、`theme_label`、`broadcast_label` 等）只留作投影，放在隐藏的状态栏里一个零尺寸容器中 | 过渡 | 状态栏整体删除（`workspace_chrome` 已常开）时一并删除 | 过渡 |
| W-4 | `title_tools.yss` · `Slot` 的 `folded` 变体 | 收起的按钮不卸载：自己的槽位 box 绝对定位叠在“⋯”下、透明、不可命中，宿主弹层（连接详情、主题、转发、命令历史）仍锚在这颗原生按钮上，所以从“⋯”处弹出。只改我们自己的布局 box，不碰原生按钮 | (c) | 若 zenit 补“菜单项触发后锚在菜单触发器上”的弹层能力，可改为真正卸载 | **焦点问题已修（r3-tabs-2）**：槽位 box 加上游补的 `inert`，收起的按钮不再进 Tab 序、辅助技术不读；叠放本身仍待用户判定 |
| W-5 | `workspace/view/pane_header_view.zig` · `PaneDrag`（窗格头部的拖动把手 / 标题外层盒子） | 窗格头部已是 `workspace/view/pane_header.yix` + `pane_header.yss`（会话窗格与放进分屏的卡片同一个模板，按事实推出部件：把手 · 类型图标 · 标题 · 状态点 · 路径 · 广播 · 置顶 · 浮动 · 更多）；留在 Zig 的只有手写组件 `PaneDrag`：zenit 拖动绑定占用节点事件槽、要行自己的 scope，模板写不出——同 TabCell 的写法（YIX_REFERENCE 推荐的“手写 Zig 组件当标签用”），只建外层盒子（把手 13 宽 / 标题随宽、grab 光标）并挂绑定，子元素都在模板里 | (c) | 若 zenit 补“声明式拖动绑定”（如 `onDrag` 属性），`PaneDrag` 收回到 `.yix` | **已收回（panel-heads）**，只余 `PaneDrag` 最小例外（“更多”的 `PaneMore` 见 W-6）：按钮全部原生默认外观（ghost sm 图标按钮 + 原生 Tooltip，广播 / 置顶开启时换 `secondary`，去掉 `base_style = group_styles.control()` / `icon_tint`），“更多”是原生 `W.Menu`；聚焦与路径刷新改为写 Vm 信号，不再按 test_id 遍历子节点改样式 |
| W-6 | `shell/view/app_menu.zig` · 菜单唯一入口（menus 包） | 右键 / 快捷键打开的菜单挂 `app_menu.yix`（`ContextMenu`）；按钮触发的菜单（窗格“更多”、传输任务“⋯”、分组“⋯”、KVM“更多”、AI 待发消息“⋯”）经 `AppMenu.mountTrigger` 在 Zig 里挂一次原生 `W.Menu`（不写任何样式，触发按钮放进它的 trigger 槽）；传输 / 分组 / KVM / AI 的触发按钮仍由各调用方在 Zig 里建。窗格头部改 `.yix` 后（panel-heads），“更多”用手写组件 `PaneMore`（`pane_header_view.zig`）当标签包住模板里的原生按钮，内部仍走 `mountTrigger`，菜单的排列、快捷键文字与测试路由不变 | (c) | 调用方的头部 / 行改 `.yix` 后，改用 yix `<W.Menu items={…}>` 包住按钮，`mountTrigger` 删除 | 过渡（随窗格头部 W-5、传输面板、侧栏分组行改 yix） |

## 主题（`src/shared/ui/theme/`）

| # | 文件 / 组件 | 为什么现在还在 | 类别 | 建议 | 状态 |
|---|---|---|---|---|---|
| T-1 | `app_theme.zig` · `widgetTokensFrom` 仍改写 `button_primary_bg / fg / hover / pressed`（4 个角色 token；其余组件角色 token 已在 H-tokens 回到 zenit 默认） | 不是 zenit 能力缺失，是 ZeroWork 的用法：Save Bar 的保存按钮（`save_fill` → `zw-primary*`）与 37 处 `app_theme.stylePrimary(...)` 调用（连接向导、快速连接、SOCKS、传输、AI 审批 / 关闭确认、会话记录等约 30 个文件）把按钮底色覆盖成调色板的主操作渐变，文字颜色却取 `button_primary_fg`。只删这 4 个 token 而覆盖还在时，深色调色板上是“调色板渐变底 + zenit 默认深色字 `#09090b`”，24 个深色调色板上对比度只有 2.2–3.1:1（如 nord `#355f79`、solarized-dark `#176e76`），主按钮文字难以辨认 | (c)：重复定制原生组件 | 改 ZeroWork 用法：P4 第一个包删除 `stylePrimary` 与 `save_fill` 覆盖，主按钮改用原生 `W.Button` primary 的默认外观，同一提交删除这 4 个 token。代价：主按钮不再跟随各调色板的主操作色（dark 族为 zenit 默认的浅底深字）。若要保留“主按钮跟随调色板”，那是另一件事，需要 zenit 提供由品牌色派生整组 primary 角色的入口（补上游），不能由 ZeroWork 主题改写 | **已收回（native-buttons）**：`stylePrimary` 与全部调用、Save 的底色 / 渐变覆盖、其余主按钮的底色 / 字色覆盖已删除，主按钮一律是原生 `W.Button` primary 默认外观；同一提交删除 `widgetTokensFrom` 对 `button_primary_*` 四个 token 的改写。截图核对：`ZeroWork-evidence/native-buttons/` |

## 浮动卡片层（`src/shared/ui/float_card/`，ai-panel-anchor）

| # | 文件 / 组件 | 为什么现在还在 Zig | 类别 | 建议 | 状态 |
|---|---|---|---|---|---|
| F-1 | `float_layer.zig` · `FloatLayer` / `Card`（窗口的浮动卡片层：层根 `float.layer`、八个透明缩放热区 `<前缀>.resize.<edge>`、卡片节点的位置 / 尺寸写入、拖动 / 缩放 / 置顶 / 最大化与 Z12 出入场） | 本质是命令式行为层：热区尺寸与位置随卡片矩形逐帧计算，拖动用 `ui.interaction.drag.Binding`，出入场用 `ui.fx.AnchorTransition.create`；不画任何外观（热区透明、层根 pass-through），卡片内容仍归各 feature 的视图。原 `features/ai/pane/view/ai_float_gestures.zig` 的同类逻辑已并入这里并删除 | (b) | 保留为最薄的行为层；若以后要 Yix 化，需要 zenit 提供“可拖动 / 可缩放的浮动容器”组件（属较大的新公开能力，待用户判定） | 待用户判定 |
| F-2 | `float_chrome.zig` · `Chrome`（浮动卡片统一窗口外观的宿主侧：挂载 `float_chrome.yix`、副标题收缩钩子、按钮锚点 / 无障碍名的读写；AI 面板的对话内容由 `ai_host.zig` 命令式挂进外观的内容插槽 `S.body`：`AiHost.mountContent` 按需挂载、关闭静止后释放，LIFECYCLE.md §3） | 外观本身是 `.yix`（原生 `W.Card` floating + `W.Grabber` + ghost `W.Button` + `W.Tooltip`）；留在 Zig 的是逐帧版式判断（副标题让位，同 bugfix-1 规则）与“内容由各卡片挂进插槽”——AI 面板正文仍是命令式视图（`ai_host.zig`，既有状况，不是本包新增） | (b) 插槽宿主同 HC-1 | AI 正文随 AI feature 的 Yix 化一起收回；外观不需要再动 | 保留（外观已是 `.yix`） |

## 会话记录卡片（`src/features/history/`，history-card：PL4b）

卡片视图本身（作为 tab 时的卡片框与头部 `TabFrame`、列表栏、详情头、空态 / 加载态、删除确认）已是 `view/history_card.yix` + `.yss`；浮动时的外框与头部是统一窗口外观（F-2），全部原生组件（`W.Card`、`W.Input`、`W.Button`、`W.Tag`、`W.Tooltip`、`W.Popover`、`W.ScrollArea`、`W.Divider`、`W.Spinner`）。剩下的命令式部分如下。

| # | 文件 / 组件 | 为什么现在还在 Zig | 类别 | 建议 | 状态 |
|---|---|---|---|---|---|
| HC-1 | 详情区的只读回放表面（`features/terminal/view/replay_surface.zig` · `ReplaySurface`，经 `features/terminal/mod.zig` 导出；`history/host/history_host.zig` 把它的根节点放进 `history_card.yix` 的插槽 `S.surface`） | 它就是终端表面（归档模式的 `TerminalViewNode`：GPU 文字、选择、搜索、回放条 `terminal.history.*` 与拖动跳转），与原归档 tab 是同一个视图；不是 Yix 节点 | (b) 终端表面（与终端卡片同一类，不新增例外种类，PLUGIN_ARCH_PLAN PL4b） | 随终端表面一起处理（P5 terminal 波次）；接口已冻结，见 `replay_surface.zig` 的契约单测 | 保留（同终端表面） |
| HC-2 | `host/history_host.zig` · 浮动定位节点（统一窗口外观外面的一个透明 `position: absolute` box，交给 `FloatLayer.attach` 作为定位 / 尺寸节点；`floating_input.protect` 让它挡住下面的终端输入） | 浮动层的定位与缩放热区写在节点上（见 F-1）；外框与头部是统一窗口外观（F-2），卡片内容根留给 Yix 视图，搬进 tab 时只把内容根从外观内容区挪进 `TabFrame` | (b) 同 F-1 | 随 F-1 一起：若 zenit 提供“可拖动 / 可缩放的浮动容器”组件，这个节点改为该组件 | 待用户判定（随 F-1） |

## AI 助手（`src/features/ai/`，ai-redesign-c 登记）

AI 面板正文仍是命令式视图（F-2 已说明，既有状况）。ai-redesign-c 按 AI Chat 重设计 P6 / P7 改了下列命令式视图的版式，全部换成原生组件（`W.Popover` 默认面板、`W.Tag`、ghost `W.Button`、`W.Pressable`、`W.Empty`、`W.Modal`），去掉了对原生组件的底色 / 圆角 / 阴影 / 尺寸覆盖；新增的“新消息”提示是 `.yix`（`pane/view/ai_new_messages.yix`）。这些文件仍在 Zig 里，登记如下，随 AI feature 的 Yix 化（P5）一起收回。

| # | 文件 / 组件 | 为什么现在还在 Zig | 类别 | 建议 | 状态 |
|---|---|---|---|---|---|
| AI-1 | `sessions/view/ai_sessions_view.zig`、`ai_session_row.zig`、`ai_sessions_styles.zig`（会话列表弹层、会话行、只读历史） | 行按宿主每次 `show(entries)` 整体重建；阶段标签由行在 effect 里订阅窗口的阶段板（`sessions/model/view_model.zig` SessionPhases，assistant_store `setPhase` 发布；usage-b5f-ai-testid 起不再由宿主逐帧逐行写），按钮角标跟随 BoundSessions；宿主的确认 / 历史 / 进度流程直接调用视图方法 | (c) 既有命令式视图 | 随 P5：行数据进 view-model，弹层与行改 `.yix` | 过渡（P5） |
| AI-2 | `sessions/view/ai_children_view.zig`、`ai_children_styles.zig`、`ai_child_logo.zig`（子智能体弹层） | 打开期间保留行节点与顺序（防止点到别的子智能体），按指纹局部更新 | (c) | 同 AI-1 | 过渡（P5） |
| AI-3 | `sessions/view/ai_empty_view.zig`、`ai_empty_styles.zig`（欢迎页 / 未配置空状态） | 宿主在对话重建时挂载；最近会话复用 AI-1 的行（“过渡后补布局”的钩子已删：上游修好了隐藏子树内的布局变更重新显示后不生效，usage-b5-lifecycle） | (c) | 同 AI-1 | 过渡（P5） |
| AI-4 | `host/child_dialog.zig` 头部、`pane/view/ai_assistant_header.zig`、`ai_child_header_styles.zig`（子对话框头部） | 子对话框由宿主命令式挂载，头部按钮与状态标签由宿主写信号 | (c) | 同 AI-1 | 过渡（P5） |
| AI-5 | `attachments/view/ai_image_attachments_view.zig` 预览对话框、`ai_image_preview_styles.zig` | 纹理加载 / 释放与图片缩放几何由宿主按 after-layout 计算 | (b) 原生纹理 | 随 P5 附件视图 | 过渡（P5） |

## AI 消息流（`src/features/ai/pane/view/`、`cards/view/`，ai-redesign-b：P2 / P3 / P5）

AI 面板正文仍由 `ai_host.zig` 命令式挂进外观插槽（F-2 既有状况）。本包按 Pencil Kaf7E 把消息流里的视觉部件全部换成 zenit 原生组件，外观不覆盖：用户气泡 `W.Card` bubble、Markdown `W.Markdown`（`.rules` 表格、`heading_sizes`）、代码块 `W.CodeBlock`（上游新组件）、步骤组 `W.Disclosure`（状态槽放 `W.Spinner` / 图标）、被拒绝 `W.Tag`、错误恢复 `W.Alert` danger（actions / details 槽）、悬停操作与回合状态行 `W.Button` ghost xs。下列视图仍留在 Zig：

| # | 文件 / 组件 | 为什么现在还在 Zig | 类别 | 建议 | 状态 |
|---|---|---|---|---|---|
| A-1 | `pane/view/ai_message_view.zig` · `Retained`（流式 Markdown：已完成块稳定、只更新末块；代码块的代码是信号，`W.CodeBlock` 原位更新文字节点） | 流式分块与节点保留（`ai_stream_performance_native` 断言前缀节点不重建）由宿主逐帧驱动，Yix 没有“按块复用子树”的写法 | (b) | 保留为最薄的分块层；Yix 化需要 `W.Markdown` 自身支持增量追加（上游能力，待判定） | 保留 |
| A-2 | `pane/view/ai_user_message_view.zig`（`W.Card` bubble 的挂载、悬停 / 焦点显隐操作行） | 由 `ai_host.zig` 的对话重建命令式挂载。显隐只读原生状态：行的 `useHover`（对话重建后静止指针的悬停由 zenit 重新命中）与行的 `on_focus_within` / `on_blur_within`；无逐帧检查、无鼠标矩形判断（usage-b2-single-writer） | (b) | 随 AI 正文 Yix 化收回（F-2） | 保留（缩小） |
| A-3 | `cards/view/ai_step_group_view.zig`、`ai_step_view.zig`、`ai_step_status.zig`、`ai_step_disclosure.zig`、`ai_tool_results_view.zig`、`ai_execution_result_view.zig` | 时间线保留视图（`ai_timeline_view.zig`）按行复用并原位更新（计时、状态、展开状态与滚动位置），子行由宿主追加进 `W.Disclosure` 的轨道 | (b) | 随 AI 正文 Yix 化收回；工具卡 / 执行卡的输出井已改用 `W.CodeBlock`（ai-redesign-d：上游补了 `scroll_x` / `scroll_y` 模型，阅读位置照旧保留）；usage-b5g-native-gaps 起表头行 / 目标行是原生 `W.Pressable` + `ai_step_row.yss` 的 `look`（随主题），详情的嵌套滚动与常显滚动条用 ScrollArea 的 `overscroll_y` / `scrollbars`，阅读位置走原生受控偏移（`ai_card_scroll.Offsets`），不再访问原生组件内部 | 保留（缩小） |
| A-4 | `cards/view/ai_recovery_view.zig`、`pane/view/ai_turn_status_view.zig` | 由对话重建命令式挂载（恢复卡在 `rebuildConversation`，回合状态行带逐秒计时与活动波浪字钩子） | (b) | 随 AI 正文 Yix 化收回 | 保留 |
| A-5 | `pane/view/ai_history_view.zig`（长历史的虚拟行：原生 `W.VirtualList` 嵌入会话 `W.ScrollArea`） | 行内容由 `ai_host.zig` 的对话重建命令式挂载（`HistoryRows.render`，同 A-2 / A-3）；本文件只是“会话滚动区 + 虚拟列表”的适配器，只用列表的公开接口（`scroll_owner`、`mountScoped`、`observe_item_resize`、`on_item_measured` / `seedItemEstimate` / `remeasureAll`），不读写列表内部节点、钩子与状态；行高持续跟随内容与消息列宽（宽度是宿主的模型信号） | (b) 虚拟列表容器 | 随 AI 正文 Yix 化收回（`VirtualList(...).rows(ctx, row)` 的行函数换成 `.yix` 行组件） | 保留（usage-b1-contract 登记） |

## 其余 feature

尚未开始 Yix 化（P5）。预计的例外类型在 `reports/P3.md` 的重估一节按 feature 列出；实际条目在各波次改写时逐条登记到本文件。

### AI 输入区（`src/features/ai/composer/`、`approvals/view/ai_pending_view.zig`、`attachments/view/ai_attachments_view.zig`；ai-redesign-a，Pencil Kaf7E P1 / P4）

AI 正文仍是宿主命令式挂载（F-2 已登记的既有状况）。本包把输入区重写为全原生组件，但视图仍在 Zig 里：

| # | 文件 / 组件 | 为什么现在还在 Zig | 类别 | 建议 | 状态 |
|---|---|---|---|---|---|
| AI-1 | `ai_host.mountAssistantConversation` 的输入区：一个原生复合 `W.Textarea`（`mountCompound` header = 附件条、footer = 工具行），审批 / 提问面板、排队队列、“稍后处理”胶囊同在输入区列里 | 宿主命令式持有 `TextareaState`（IME、粘贴图片、拖放、↑↓ 历史、发送路由都挂在它的事件捕获上）、按草稿行数调整文字高度（1–6 行）、按面板宽度调整外边距（⑤ 宽度规则）；主窗口与子对话框共用这一挂载 | (c) | 随 AI feature 的 Yix 化（P5 AI 波次）改写为 `.yix`：需要 yix 能表达“宿主持有的 TextareaState 事件捕获” | **已收回**（ai-redesign-e）：输入区是 `composer/view/ai_composer.yix` + `.yss`（原生复合 `W.Textarea`：header 行放附件条插槽、footer 行放 `Controls.ToolRow`，Send / Stop 是工具行里的原生 primary sm 图标 `W.Button` + `W.Tooltip`；审批 / 提问面板与“稍后处理”胶囊直接放 `ai_composer_interaction.yix` 的组件）；宽度规则的外边距 / 高度、可见性、Send / Stop 状态是 view-model（`ai_composer_view.zig`）的信号。宿主经上游新增的“结果句柄参数”（`ref={note}`，`*ui.view.Ref(W.input.TextareaResult)` 作为模板参数）拿到 `TextareaResult`，IME、粘贴图片、拖放、↑↓ 历史、发送路由仍挂在它的编辑状态与输入节点的事件捕获上（行为不变）。队列视图与附件条仍是命令式视图，挂进模板的插槽，见 AI-1a / AI-1b |
| AI-1a | `approvals/view/ai_pending_view.zig`（排队队列卡片，挂进输入区模板的 `queue` 插槽） | 队列行由宿主按队列快照整体重建、行内操作经宿主回调；本包只收回输入区本身 | (c) | 随 P5 改为 `.yix`（行数据进 view-model） | 过渡（P5） |
| AI-1b | `attachments/view/ai_attachments_view.zig`、`ai_image_attachments_view.zig` 的附件条（挂进复合 Textarea header 行的 `chips` 插槽） | 附件条与预览弹层共用宿主的附件状态与纹理（AI-5）；本包只收回输入区本身 | (c) | 随 P5 附件视图 | 过渡（P5）；**已缩小**（zenit-small）：header 行显隐改为原生参数 `W.Textarea headerVisible`（上游 `TextareaProps.header_visible`），值是 view-model 信号 `header_shown`，宿主只经 `setHeaderShown` 设值，不再写 `TextareaResult.header` 的 display；只剩附件条本身仍是命令式视图 |
| AI-2 | `ai_composer_controls_view.zig`（工具行：原生 ghost sm `W.Button` + chevron、`W.Tooltip`、menus 包的原生 `W.Menu`、模型 / 用量原生 `W.Popover`） | 收缩规则（先截断模型名，再收权限、再收运行方式）按实测宽度逐帧判定；菜单打开时捕获的快照修订号决定动作是否生效 | (c) | 同 AI-1；收缩判定可留在 view-model | **已收回**（ai-redesign-e）：视图是 `ai_composer_controls.yix` + `.yss`（原生 ghost sm `W.Button`、`W.Tooltip`、menus 包的模板菜单 `ContextMenu`、模型 / 用量 `W.Popover`、模型列表 `W.VirtualList` + `W.Pressable` 行、推理档位 `W.Slider` stepped + marks、用量 `W.ProgressSegments` 与按钮内 `progress` 环）；`ai_composer_controls_view.zig` 只剩 view-model（投影、捕获、收缩判定、动作），收缩规则逐帧按实测宽度判定不变。上游补了 Slider 刻度 / 阶梯外观、Button `progress`、Pressable `a11y_description`、Tooltip `close_on_escape` |

ai-redesign-d 对 AI-1 / AI-2 的核实（未收回的原因，供主会话判定）：
- AI-1（ai-redesign-e 已收回，见上表；以下为 d 包当时的核实）：输入区若改成 `.yix`，宿主仍要拿到复合 `W.Textarea` 的 `TextareaResult`（`state`、`input`、`header` / `footer` 槽行），因为 IME、粘贴图片、拖放、↑↓ 历史、发送路由都挂在宿主持有的 `TextareaState` 与输入节点的事件捕获上（`ai_host.zig` 约 30 处）。Yix 模板里的 `ref()` 只给宿主元素的 `*Node`，组件的结果类型（`TextareaResult`）要 Zig 侧 `createRef`，模板拿不到；能做的只是按 test_id 回查节点、从节点的 `event_context` 取回状态，这等于把例外换个位置。要收回，需要先定：上游给 Yix 组件元素一个“结果句柄”（类似 `ref(W.TextareaResult)`），或把这些宿主逻辑改成声明式事件（`onKeyDownCapture` 已有，粘贴图片 / 拖放 / IME 还没有）。
- AI-2：ai-redesign-e 已收回（见上表）；单测改为读 view-model 信号或按 test_id 取节点，断言不变。
- 本包完成的部分：AI-3（审批 / 提问面板）已收回；AI-4（用量环 / 分段条）已收回。

### 文件传输（`src/features/transfer/view/`；usage-b5c-native-controls）

对原生控件的改写已清零（Modal / Popover / ScrollArea / Input / Select / Checkbox / Button / Tooltip / VirtualList 一律默认外观，只用公开 props、
Result 公开部件与自有盒子；逐条取证见 `ZeroWork-evidence/usage-b5c-native-controls/transfer/INVENTORY.md`）。视图本身仍在 Zig：

| 编号 | 文件 | 留在 Zig 的原因 | 类别 | 状态 |
|---|---|---|---|---|
| T-1 | `transfer_manager_view.zig` | 虚拟列表行由 `mountScoped` 的命令式回调逐行构建；面板随托盘 / 弹层 / 窗口三种放置切换布局 | (b) | 待用户判定 |
| T-2 | `transfer_panel.zig`（传输确认对话框） | 来源行随选择动态重建；确认框属于发起的文件窗格：原生 Modal 的 `within`（`Signal(?ui.widgets.modal.Anchor)`，切换窗格处 `set(.{ .node = pane })`，`within_padding = 12`；居中于该窗格并由 Modal 按区域约束宽高，视图只按窗口给出自然宽高，表单填满 Modal body），“保存到”只读走原生 Input 的 `readonly` 源（同一个输入框，不再双份） | (b) | 过渡（随传输视图 `.yix` 化收回） |
| T-3 | `transfer_events_view.zig`（任务事件弹层） | 手动锚定到虚拟列表里的行按钮（按节点 id 重新定位），事件行命令式重建 | (b) | 过渡（随锚点整改包收回） |

## 变更记录

| 日期 | 变更 |
|---|---|
| 2026-11-16 | usage-b5c-native-controls：同名文件处理对话框改成 `.yix` + `.yss`（`features/transfer/view/transfer_conflict.yix`、`transfer_conflict_styles.yss`），`transfer_conflict_view.zig` 只剩信号与裁决（不再持有任何节点样式）；RadioGroup / Input / Checkbox / Modal / ScrollArea / Button 全部回到原生默认外观，覆盖确认的提示改用原生 `W.Alert`，“较新”改用原生 `W.Tag`；删除按 test_id 找单选行、替换圆点、行底色与红字、直接写 `input.state.*`、`styleInput`、Modal 面板上的渐变与假把手 |
| 2026-11-16 | usage-b5g-native-gaps（zenit 用法整改批次 5）：A-3 缩小——卡片表头 / 工具卡目标行由“原生 Button 当容器（隐藏其子节点、直写 a11y）”改为原生 `W.Pressable`（`look` 来自 `cards/view/ai_step_row.yss`，随主题；名称 / 展开状态走 `a11y_label` / `expanded` 源）；`ai_card_scroll.zig` 不再读 ScrollArea 的 event_context、不再接管其事件捕获与淡出状态（改用上游 `overscroll_y = .contain`、`scrollbars = .always` 与受控 `scroll_y` / `scroll_x`）；输入区审批面板的嵌套滚动改在 `.yix` 里声明（`overscrollY={.contain} scrollbars={.always}`），view-model 不再按节点调用；子智能体行与“任务记录”行的外观改为 YSS `look`（删除按主题重设外观的信号）；会话行标题提示改用原生 `Tooltip.show = .if_truncated`（删除每行布局钩子与悬停处理器替换）；控件提示 `control_hint` 改用原生 Tooltip 默认外观与 `disabled` 状态（删除对 Tooltip 内部标签 / 悬停处理器的访问与每帧可见性钩子） |
| 2026-11-16 | usage-b5f-ai-testid（zenit 用法整改批次 5）：AI-1 缩小（会话行阶段 / 已绑定数改为 store 发布、行订阅，删除宿主逐帧逐行按 test_id 更新与行状态塞 event_context）；AI-3 欢迎页最近会话行同样订阅阶段板（删除逐帧递归整棵对话树的 `updateRecentPhase`）；AI-4 子对话框不再逐帧改 test_id 前缀（IdSpace：挂载处命名）、几何改由原生 Modal 的 width / height / max_height 源给出、主题着色改为订阅主题信号、“任务记录”改原生 Pressable；AI-1b / AI-5 附件条与远程选择器不再读写 Tooltip / Button 内部节点（文字 / 无障碍名称改信号，上游补 `Tooltip.text_test_id`） |
| 2026-11-15 | usage-b5-lifecycle（zenit 用法整改批次 5）：AI-3 的欢迎页“过渡后补布局”钩子（`WelcomeSettle`）删除——上游 zenit 5ec77389 已修“隐藏子树内的布局变更重新显示后不生效”，单测“AI welcome rebuilt while its panel's open flight is in the air …”覆盖原场景；`shell/view/retained_panel.zig` 删除（AI 面板内容改由 `shared/ui/surface/surface_migration.zig` 停放 / 迁移，见 `LIFECYCLE.md`） |
| 2026-11-15 | usage-b2-single-writer：A-2 缩小（用户消息操作行的显隐只用原生 hover + focus-within，删除 after-layout 逐帧矩形判断）；工具行 `ai_composer_controls.yix` 删除三处 Esc 捕获（Esc 归原生浮层栈） |
| 2026-11-15 | usage-b1-contract（zenit 用法整改批次 1）：登记 A-5（AI 历史虚拟列表适配器；上游补 `VirtualListProps.scroll_owner`、`observe_item_resize`、`on_item_measured` / `seedItemEstimate` / `remeasureAll`，不再改写列表内部）；A-2 的用户气泡与已发送附件栏改为跟随宿主的消息宽度模型（`ai_user_message_view.ContentWidth`），宿主不再按 test_id 找气泡内部列；S-8 的 `Frame` 增加 `handles`（窗口模板 `ref()` 交出的卡片 / 内容岛 / 内容页根），`Page.of(frame)` 不再按 test_id 查找；整窗 Escape 与重挂前的焦点交接改按控件的 focus id 认字段（上游 `FocusTargets.targetName`），不再读焦点节点的 test_id |
| 2026-11-15 | zenit-small：AI-1b 缩小（上游 `TextareaProps.header_visible`，宿主不再写 header 行）；上游修好组件根为 Popover / Tooltip 时重绑作用域使存活判定失效的问题（`NodeScopeBinding` 重绑改为遮蔽），工具行 `ai_composer_controls.yix` 里为此加的外包 box（Compact、ModelPopover、UsagePopover、ModelRow）删除 |
| 2026-11-15 | ai-redesign-e：收回输入区 AI-1（`ai_composer.yix`，上游补结果句柄参数 `ref={param}`）与工具行 AI-2（`ai_composer_controls.yix`，上游补 Slider marks / stepped、Button progress、Pressable a11y_description、Tooltip close_on_escape）；新登记 AI-1a（队列视图）、AI-1b（附件条） |
| 2026-11-15 | ai-redesign-d：输入区 AI-3（审批 / 提问面板）收回——视图改为 `composer/view/ai_composer_interaction.yix` + `.yss`（原生 `W.Card` outlined、`W.ScrollArea`、`W.Tabs` segmented、`W.RadioGroup`、`W.Input`、`W.Tooltip`、`W.Button`），`ai_composer_interaction_view.zig` 只留 view-model（票据、防重放、动作回调）；嵌套滚动策略（`ai_card_scroll.containVerticalNode`）与按下 / 焦点释放仍在 view-model 里按节点调用，不是视图（嵌套滚动部分已由 usage-b5g-native-gaps 改为模板声明） |
| 2026-11-15 | ai-redesign-d：输入区 AI-4（用量环 `drawRing` 与用量分段条）收回——上游补了 `W.ProgressRing` / `W.ProgressSegments`，工具行用量按钮里的环与用量弹层的分段条改用原生组件，自绘删除 |
| 2026-11-15 | ai-redesign-c：登记 AI-1 – AI-5（AI 助手的既有命令式视图按 P6 / P7 改为原生组件，仍在 Zig，随 P5 收回）；新增 `.yix` 视图 `ai_new_messages`；统一外框 `float_chrome.yix` 增加标题文字与图标的 ref（最窄宽度时副标题、空白占位、图标依次让位于标题） |
| 2026-11-14 | menus 包：所有菜单只经 `shell/view/app_menu.zig`（声明 `model/menu_spec.zig`）；删去 `workspace/view/tab_menu.yix`、`shell/view/terminal_menu.yix`（并入 `app_menu.yix`）；新登记 W-6 |
| 2026-11-12 | 建立本文件；登记设置窗口 S-1 – S-10 |
| 2026-11-12 | 用户判定 S-4、S-5、S-6 均为“补上游”，归入 (a) 类，缺口编号 G18（受控输入）、G19（可绑定滚动位置）、G20（捕获阶段事件与声明式焦点）；S-9 确认为冗余、直接清理 |
| 2026-11-12 | F-set-recover（vendor @9e97b7a6，上游补 G14–G17）：S-1、S-2、S-3 已收回，S-9 已清理；`components/shell` 只剩 `NavScroll`、`Viewport`、`SearchField`（S-4、S-5）。新登记 G21（见 `YIX_SPIKE.md`） |
| 2026-11-12 | F-set-handles（vendor @ed8e829e，上游补 G18–G21）：S-4、S-5、S-6 已收回；S-8 缩到只剩旧正文的桥接；S-10 卡片不再可聚焦后拖动带恢复，未切 `chrome = .custom`，待用户判定；新登记 G24（见 `YIX_SPIKE.md`） |
| 2026-11-12 | 开关改用 zenit 原生（用户指示）：设置面板、SOCKS、外观页、服务提供方、BMC 启动菜单的开关不再有几何 / 位置覆盖；登记 S-11（外观页开关无滑动动画，3e 修）与 B-1（BMC “显示 FPS”开关的根节点覆盖） |
| 2026-11-12 | F-set-panes-A（3e 第一批）：通知、SSH 与网络、文件传输、数据与日志的面板正文改成 `.yix`（S-7 拆出这四类）；面板里草稿变化按信号局部更新，S-11 的同类问题在这四类不再出现；新登记 S-12（数据清理确认流程）、S-13（选择器浮层）、S-14（单位后缀，G25）、S-15（`.legacy` 外壳仍用的旧面板文件） |
| 2026-11-12 | 登记 T-1（主题仍改写 `button_primary_*` 四个角色 token，待用户判定） |
| 2026-11-12 | F-set-panes-A-fix（vendor 带入上游 G25）：S-14 已收回，单位后缀改回原生 `appendText` |
| 2026-11-12 | F-set-panes-B（3e 第二批）：快捷键（行内录制，人工验收反馈第 7 条）、关于与更新的面板正文改成 `.yix`（S-7 拆出这两类）；S-15 追加旧快捷键 / 更新面板与录制对话框文件；没有新增例外（这两类视图里没有留在 Zig 的部分） |
| 2026-11-13 | F-set-appearance（3e：外观与主题）：外观面板正文改成 `.yix`（S-7 拆出外观；S-11 已修：开关原地滑动）；材质预览条改 `.yix`；S-15 追加旧外观文件；新登记 S-18（行内材质预览复用宿主材质图层，b 类）与缺口 G35（Slider 的 test_id 在 Yix 里够不到）、G42（ScrollArea 没有声明式的末端对齐 / 滚到可见）；rebase 到 H-save 后新坑编号顺延为 45–48 |
| 2026-11-12 | H-shell（人工验收反馈 1、3、5、11）：设置外壳的浮层 / 浮动按钮改用原生 `W.GlassBox`，删除 `styles.yss` 的 Yss 玻璃模仿（`nav`、`glass_nav`、`glass_nav_divider`、`glass_icon`、`GlassNavButton`、`search_pill`）与 token `zw-window-glass-*`；旧外壳仍用的 `nav` / `glass_nav*` 搬进 `settings_shell.zig` / `settings_styles.zig`（随 S-15 / 3f 删除）；G24 两处绕法删除；新登记 S-16（标题栏边缘渐变的 Zig 适配，G28）、S-17（G27、G29 的近似写法） |
| 2026-11-13 | H-save（人工验收反馈 4）：Save Bar 改原生 `W.GlassBox` + 原生 `W.Button`（S-1 的 `look` 覆盖去掉）；未保存 / 恢复默认确认改 `.yix` 原生 `W.Modal`（view-model 持有）；新登记 S-19（设置窗口 Toast 的命令式 `W.Notifier`，G38）；新缺口 G36、G37（见 `YIX_SPIKE.md`） |
| 2026-11-13 | set-adopt（vendor @bc57f042 带入上游 G27–G29、G31–G38）：S-16、S-17、S-19 已收回；没有新增例外 |
| 2026-11-13 | F-set-plugins（人工验收反馈第 10 条前半）：协议插件的面板正文改成 `.yix` 两级导航（S-7 拆出协议插件）；S-15 追加旧 `settings_plugins.zig` 与只测它的用例；没有新增例外（这一类视图里没有留在 Zig 的部分）、没有新缺口 |
| 2026-11-13 | F-set-ai（人工验收反馈 10 后半）：AI 辅助的面板正文改成 `.yix`（S-7 拆出 AI 辅助），服务提供方两级；S-15 追加旧 AI 视图文件；没有新增例外（视图里没有留在 Zig 的部分；后台任务在宿主 `host/ai_settings_host.zig`）；新缺口 G46–G48（见 `YIX_SPIKE.md`“AI 辅助面板”）；rebase 到 F-set-appearance / F-set-plugins / H-opaque-popups / h-helpcard 之后新坑编号顺延为 53–58；面板正文九类已全部是 `.yix`（S-7 只剩不可达的兜底分支，随 3f 删除） |
| 2026-11-13 | set-modals：S-12 已收回（数据清理确认改 `.yix` 原生 `W.Modal`，状态机进 `model/data_cleanup.zig`）；S-13 的 `.yix` 面板部分已收回（自定义 TERM 改原生 `W.Popover` + 受控 `W.Input`，下载目录走 `Effect.pick_directory`）；S-15 追加旧数据清理对话框与 `settings_picker.zig`；S-18 备注背景纹理改进共享纹理表（修复设置窗口缩略图 / 行内预览空白）；新缺口 G45（Popover 的锚点与手动触发在 Yix 里不能同时表达） |
| 2026-11-13 | native-notify：全局提醒 / 本地回执 / 命令失败提示改窗口级原生通知栈（vendor 带入上游 G49–G54），通知历史与 AI 反馈条改 `.yix` 原生组件；新登记 N-1 – N-7（待用户判定 / 确认） |
| 2026-11-13 | notify-two-hosts（用户判定：一个右上角，一个标准 Toast 在中下方）：每个窗口两个原生 `<W.NotificationHost>`，卡片（全局提醒、命令失败提示）→ 右上角，本地回执 → 中下方 zenit 默认位置；view-model / Ports 分 `cards` / `toasts` 两条通道，两栈的遮挡隐藏各算各的停靠区；N-1 已收回；新增 test_id `notifications.toasts`；没有新缺口（zenit 一个窗口挂两个 NotificationHost 无需改动） |
| 2026-11-13 | toast-top（用户判定）：中下方 Toast 永远在最上层，被浮层遮挡时不隐藏、不停表（不再接 `suppressed`，宿主不再为它算遮挡；右上角卡片栈的遮挡规则不变）；分流统一成 view-model 纯函数 `laneFor`（无动作的成功 / 信息 → Toast，带动作或需要处理 → 卡片），窗口宿主的 `publishFeedback`（无动作）改走中下方 Toast（此前信息类反馈被丢弃），`publishFailure` 仍走卡片；没有新例外、没有新缺口（zenit toast tier 已高于 overlay / dialog tier，无需补上游）；门面签名不变 |
| 2026-11-13 | settings-header（第 2 轮验收：页头照 znote 画板详情页 chrome 的 header）：上游补 scroll edge `hold`（满糊段）与 `.custom_inset` 认 `windowRegion=.drag`；视口伸到页头底下、删除 `<W.TitlebarEdge />` 洗白渐变；S-10 补记，没有新增例外 |
| 2026-11-13 | r3-connections（design-r3 稿 1、稿 4）：连接失败 / 重试视图与跳板引导改 `.yix` 原生组件；新登记 C-1（进度卡片其余状态仍命令式）、C-2（向导表单仍命令式，挂载新 `.yix` 片段）；connections 门面追加 `jump_guide_view` 导出；没有新缺口 |
| 2026-11-13 | native-buttons：T-1 已收回（删除 `stylePrimary` 与 Save / 主按钮底色覆盖，同提交删除 `button_primary_*` 四个 token） |
| 2026-11-13 | r3-tabs-toolbar（design-r3 稿 3、稿 5）：标题栏工具组改 `.yix` 原生组件（8 个 icon-only Button + Tooltip + Divider + ⋯ Menu），旧的盒子拼装链路 / 转发 / 主题 / 广播 / 命令历史控件退出标题栏；新登记 W-1（页签条仍命令式）、W-2（页签颜色色板手搓）、W-3（状态栏旧标签留作投影）、W-4（收起按钮叠放在 ⋯ 下）；主窗口材质策略不再给原生 Tooltip 刷底色（修复空白气泡）；没有新缺口 |
| 2026-11-13 | ai-panel-anchor（4c-3 + 卡片浮动层）：新登记 F-1（通用浮动卡片层的命令式行为层，替代并删除 AI 专属的 `ai_float_gestures.zig`）；AI 面板过渡探针 `ai_panel_motion.yix` 是 `.yix`，不登记 |
| 2026-11-13 | r3-tabs-2（design-r3 稿 3 遗留）：W-1、W-2 收回（页签条 `.yix` + 原生组件；页签菜单原生 `W.Menu` + 颜色子菜单）；W-4 焦点修复（上游补 `inert`）；上游另补 `MenuItem.icon_tint`；首页“已保存的连接”改 `.yix`（r3-tabs-2-side，没有新增例外） |
| 2026-11-14 | float-chrome（浮动卡片统一窗口外观）：新增 `shared/ui/float_card/float_chrome.yix` + `.yss`（原生 `W.Card` floating、`W.Grabber`、ghost `W.Button` + `W.Tooltip`，上游补 Card `floating` 变体与 `W.Grabber`）；新登记 F-2（宿主侧与内容插槽）；删除 AI 面板手画外框 `ai_assistant_styles.panel` / `gripRow` / `grip` 与手画头部按钮（`windowControl` 覆盖 + 悬停染色），AI 浮动面板不再叠 `background_view.isolate` 的覆盖底色；会话记录卡片浮动时不再用自带 `W.Card` 标题行 |
| 2026-11-14 | settings-3f（P3 3f）：删除设置窗口的 `.legacy` 外壳、开关与全部旧命令式面板 / 对话框 / 选择器（S-7、S-13、S-15 已删除，S-8 缩到 `vm` + `appearance`）；删除前逐页对照补齐了新界面缺的通知授权回执、光标分段锁定、删除主题危险色与 AI 辅助的几处细节（见 docs/human-feedback/REQUESTS.md 本包一行）；没有新增例外 |
| 2026-11-14 | panel-heads（CONSISTENCY_AUDIT #4）：W-5 收回——窗格头部改 `pane_header.yix`，只留 `PaneDrag` 拖动绑定最小例外（同 TabCell）；同级面板头部 / 关闭按钮 / 空状态改共享 `PanelHeader` / `PanelClose`（`shared/ui/components/panel_header`）与上游新增的原生 `W.Empty`；没有新增例外 |
| 2026-11-15 | ai-redesign-a（AI 输入区 P1 + 审批 P4）：新登记 AI-1 – AI-4（输入区 / 工具行 / 审批面板仍是宿主命令式 Zig，全部原生组件；用量环与分段条待上游 Progress ring / segments）；删除 `ai_tool_approval_view` / `ai_host_approval_view` 死代码 |
| 2026-11-15 | ai-redesign-b（AI 重设计 P2 / P3 / P5）：消息流换成 zenit 原生组件（`W.Card` bubble、`W.Markdown` `.rules`、上游新 `W.CodeBlock`、`W.Disclosure`、`W.Tag`、`W.Alert` danger + actions / details、`W.Button` ghost xs），删去手画代码块 / 表格 / 步骤组头与渐变软边 / 恢复卡；新登记 A-1 – A-4 |
| 2026-11-15 | usage-b3-titlebar：S-10 收回——生产窗口全部切到 `chrome = .custom` + 视图声明的 `windowRegion`，上游 `c48c9de4` 桥接剥离；没有新增例外（侧栏标题带、向导标题行在已登记的 Zig 视图里直接设 `window_region`，与 `W.DragRegion` 同一写法） |
| 2026-11-15 | usage-b3-titlebar（第二轮）：15 个预览 / 夹具 runner 与 `tools/mockups/runner.zig` 也迁到 window chrome，仓库不再有 `.custom_inset` 调用；夹具共用 `shared/ui/window/fixture_window.zig`（原生 `W.WindowHeader` 标题栏 + 内容槽，Zig：它是窗口宿主的组装，不是产品视图），mockup runner 用原生 `W.DragRegion` 包住整页；设置预览 runner 去掉 `--chrome=inset` 对照模式 |
| 2026-11-16 | usage-b5c-native-controls（bmc_ikvm）：B-1 收回；`bmc_ikvm` 目录对原生控件的改写清零（隐藏 Button 子节点、挖 Modal 标题栏、cast ScrollArea `event_context`、Select / Switch / Popover / Checkbox / Input 内联样式、`base_style` 换肤、按 test_id 分支），`select_surface.zig` 删除；新登记 B-2 / B-3（视图仍是命令式 Zig） |
| 2026-11-16 | usage-b5c-native-controls（收尾，随上游 zw/usage-b5c-native-controls 修订）：T-2 改为原生 Modal `within`（删除找节点 / 读矩形 / 写 `center_in` 的布局后逻辑）；B-3 与 KVM 视图的三个 Modal 关闭按钮经结果部件 `close_button` 挂 test id（`close_test_id` 已删除）；C-2 / C-3 与 B-2 的 `W.Pressable` `look` 改 YSS（`plugins/remote/editor_rows.yss`、`wizard/view/connection_stepper.yss`、`plugins/bmc_ikvm/progress_rows.yss`），连接编辑器密码显示改原生 `Input.revealed`；没有新增例外 |
| 2026-11-16 | usage-b5e-ai-host：AI 面板正文（对话视口、输入区、排队区、附件栏、两个头部弹层）从 `main_window.zig` 移到 `AiHost.mountContent`，有自己的 Scope、按需挂载 / 释放（F-2 的挂载点变化；仍是既有的命令式视图，不新增例外）；头部计数徽标归视图 Scope 所有 |

## 插件（`src/plugins/`）

插件界面的 Yix 化排在 P5；这里先登记已发现的条目。

| # | 文件 / 组件 | 为什么现在写不成 yix / yss | 类别 | 建议 | 状态 |
|---|---|---|---|---|---|
| B-1 | `bmc_ikvm/views.zig` · “显示 FPS”开关的 `S.displaySwitch`：对原生 `W.Switch` 的根节点做覆盖（`row_reverse`、宽度 `fill`） | 不是能力缺失：为了让整行可点、标签在左而改了原生组件的根布局 | (c)：重复定制原生组件 | 按“直接用原生”去掉覆盖（行的可点区域用外层 `W.Pressable` 或标签点击表达）；同步 `e2e/bmc_material_layers_native.ts` 里依赖整行宽度的悬停坐标 | 已收回（usage-b5c-native-controls：`W.Switch` 回到原生默认布局，放在视图自己的行盒里；`S.displaySwitch` 删除） |
| B-2 | `bmc_ikvm/views.zig` · KVM 会话视图（工具栏、五个菜单弹层、连接进度卡、连接日志 / 启动顺序对话框、画面视口） | 画面是渲染到 GPU 纹理的远程视频，输入捕获、画面几何、滚动定位、按实测宽度折叠工具栏都是命令式的；浮层内容随控制器快照整体投影 | (b) | 基础组件已全部是 zenit 原生默认外观（Button / Tabs segmented / Switch / Select / Modal / Popover / ScrollArea / Pressable），几何只写在视图自己的盒子上；静态结构（菜单内容、日志对话框骨架）可在 P5 拆成 `.yix`，画面与输入部分保留 Zig | 待用户判定（P5 BMC 波次） |
| B-3 | `bmc_ikvm/editor.zig` · KVM 连接编辑器（三步表单） | 表单由草稿模型逐字段命令式投影（跳板行池、探测日志、分步显隐） | (c) | 基础组件已是原生默认外观（访问方式 = `W.RadioGroup` + `description`，按钮只用原生 variant / size，Modal 关闭按钮是原生 `Button`，可访问名走 `close_label`，test id 挂在 Modal 结果的公开部件 `close_button` 上）；随连接向导一起 `.yix` 化 | 过渡（P5 插件分层） |
