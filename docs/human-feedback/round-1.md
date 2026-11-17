# 人工验收反馈 · 第 1 轮（2026-11-12）

原件：`docs/human-feedback/round 1.zdoc`（截图在 `docs/human-feedback/assets/`）。全仓库对“手搓 / 覆盖基础组件”的盘点与替换清单见 [`docs/ui-revamp/NATIVE_AUDIT.md`](../ui-revamp/NATIVE_AUDIT.md)。设计稿导出：`ZeroWork-evidence/human-feedback-r1/design/`（`w3r3t`、`T5k96`、`KUKQ5`、`GV8pb`、`e2ys05`）。

总原则（用户反复强调）：**全部用 zenit 原生组件，外观以 zenit 默认为准；缺的能力补上游，不在下游模仿或覆盖。**

这些都是行为与视觉改动：与“行为不变的重构”分开提交；截图基线的预期变化逐张说明。优先级排在 P4 之前。

状态：`待开包` / `进行中` / `待验收`（已合入，等用户第 2 轮确认）/ `已确认`。

| # | 用户原话 | 解读 | 修复包 | 状态 | 证据 |
|---|---|---|---|---|---|
| 1 | 整个settings的floating panel 和body上header里的floating buttons都不是liquidGlass的组件！！这里请你用liquidGlass和liquidGlass的Menu Buttons | Settings Nav 浮层改用 zenit 的 liquid glass 组件；页头的后退 / 前进胶囊与帮助按钮改用 zenit 原生的玻璃按钮。不再用 Yss 模仿玻璃效果 | H-shell（外壳玻璃化） | 待验收（Settings Nav、Save Bar 是原生 `W.GlassBox`；页头后退 / 前进 / 帮助在 set-adopt 改为原生 macOS 工具栏按钮组 `W.GlassToolbarGroup` / `W.GlassToolbarButton`（上游 G27 补齐，S-17 收回），导航高度用 `fill`（G29）） | `ZeroWork-evidence/h-shell/`（对照：`review/`；元素说明见 H-shell 汇报） |
| 2 | 所有的siwtcher为什么 false的情况下不是和 zenit的原生视觉稿 Node ID: NvZFg 的样式？Radio也是，请你严格使用默认zenit的Radio样式。 | 删除 ZeroWork 主题对 `switch_*` / radio 角色 token 的发布（`app_theme.widgetTokensFrom` 里的映射），开关与单选回到 zenit 默认 token。设计稿数值：Switch off 轨道 `#D4D4D8`、滑块白色带阴影，on 轨道 `#4F5ED9`；Radio off 白底 + `#D4D4D8` 描边，on `#4F5ED9` 实心 + 白点 | H-tokens（删除主题对组件角色 token 的改写）；手工绘制与被改外观的单选见 NATIVE_AUDIT 清单 2，随 3e 与后续替换包改原生 | 待验收（开关 / 复选 / 单选等角色 token 已回到 zenit 默认；dark 族默认值与设计稿不一致、`button_primary_*` 暂留；外观页的手工单选已替换：主题卡片用原生 `W.Radio`、对齐九宫格用原生 `W.Radio`、应用图标原生 `W.RadioGroup`、光标形状原生 `W.Tabs`（F-set-appearance）；其余页面的手工单选见 NATIVE_AUDIT 清单 2） | `ZeroWork-evidence/h-tokens/before/` 与 `after/`；外观页：`ZeroWork-evidence/set-appearance/review/`（light / dark / sauber 各 5 张，文件名一一对应） |
| 3 | settings body的header是要和znote一样的磨砂玻璃渐变才对，现在是纯白底 | 参考 znote（只读）页头的磨砂玻璃渐变，用 zenit 原生能力实现；zenit 缺就补上游 | H-shell | 待验收（页头下垫原生 `titlebarEdge` 渐变，渐变延伸到视口上缘、内容滚近页头时被洗淡（视口不伸到页头底下，以免挡住标题栏拖动，见 S-10）——zenit 用来取代 znote 手写渐进磨砂条的原生能力，是“洗向窗口底色”的渐变，不含模糊；set-adopt：渐变改用原生 `<W.TitlebarEdge />`（S-16 收回），视口加原生 `scrollEdge`——滚到页头下方才出现的渐进磨砂，带子贴在视口上缘（S-10：不伸进标题栏拖动带）；第一批收尾：静止时第一行正文被 scroll edge 带整条磨砂的回归已修——根因是 zenit 的 `.blur_only` 带在强度 0 时仍按均匀模糊级 1 渲染，上游 e804139d 修复、vendor @666ea295，回归测试 `e2e/settings_scroll_edge_native.ts`） | `ZeroWork-evidence/h-shell/`（对照：`review/`；元素说明见 H-shell 汇报） |
| 4 | settings里应该每一块右边的界面 应该只管它当下的 变更情况，有变化才可点保存和恢复默认，没有变化或者已经保存了，就不要一直在说“所有更改已保存”，这个保存成功应该放在一个Toast/Notification就好了；总之settings的保存逻辑乱七八糟的。 | 保存逻辑重做：脏状态按右侧当前子页（或无子页的页面）计算；当前作用域有改动才出现保存条、保存与撤销才可点；“恢复默认”只在当前作用域的值与默认值不同时可点（“有变化才可点”按“相对默认值有变化”理解，实现说明里写明）；去掉常驻的“所有更改已保存”，保存成功用 zenit 原生 Notification / Toast；view-model 的保存状态机据此重写；切页时有未保存改动沿用确认对话框（换成原生 Modal，见 8） | H-save（保存状态机） | 待验收（作用域 = 右侧当前子页；Save Bar 只在有改动时出现，原生 `W.GlassBox` + 原生按钮；“恢复默认…”在正文底部、相对默认值有变化才可点、先确认、只改本页；保存成功 / 失败是原生 `W.Notifier` 提示；带着改动切页 / 清空搜索 / 关窗先确认（原生 `W.Modal` 默认外观，焦点在“继续编辑”）；搜索结果的作用域是全部字段（待用户判定，见 H-save 汇报）；设计与转移表见 `YIX_SPIKE.md`“保存状态机（H-save）”；新缺口 G36–G38） | `ZeroWork-evidence/h-save/review/`（`{light,dark}-{a-clean,b-dirty,c-saved-toast,d-reset-enabled,d-reset-confirm,e-leave-confirm,f-invalid,g-save-failed}.png`） |
| 5 | 为什么Settings 右边的滚动没有scrollArea一样的果冻bonus？这不是zenit在macos上有的吗？ | 右侧内容与导航的滚动用 zenit 原生 `W.ScrollArea` 并开启 RubberBand 回弹（现在显式关掉了 `rubberBandY`） | H-shell | 待验收（默认回弹；Harness 验证越界后回到边界，真实触控板手感未实证） | `ZeroWork-evidence/h-shell/`（对照：`review/`；元素说明见 H-shell 汇报） |
| 6 | settings好多配置里items之间缺少分割线，Node ID: w3r3t 设计稿是有的。 | 按 `w3r3t` 在设置行之间加分隔线，数值取自设计稿 | 3e（面板正文）：行组件统一带分隔线 | 待验收（设置九类面板正文都已带分隔线：3e 第一批、第二批、外观与主题、协议插件（F-set-plugins）、AI 辅助（F-set-ai：设置行同 `rows.yix`，提供方列表 / 模型 / 技能 / MCP 条目行用同样的发丝线，末行不画）） | 外观：`ZeroWork-evidence/set-appearance/review/`；协议插件：`ZeroWork-evidence/set-plugins/review/`；AI：采集脚本 `e2e/h_ai_capture.ts`（未运行，批末采集） |
| 7 | 快捷键的设置界面，没有给用户可编辑当前快捷键的直觉设计，请你优化。 | 重新设计快捷键行的编辑交互（悬停出现编辑提示 → 点击进入“按下新快捷键…”录制态 → Esc 取消；每行可单独恢复默认；冲突提示），用原生组件。做完截图给用户看 | 3e-keys（快捷键面板）→ F-set-panes-B | 待验收 | `~/work/ZeroWork-evidence/set-panes-b/review/keys/`（`{light,dark}-{rest,hover,recording,conflict,invalid,modified,reset}.png`；交互设计与状态机见 `docs/ui-revamp/YIX_SPIKE.md`“快捷键行的编辑交互”。备注：行内录制，键帽区原生 `W.Pressable` + `W.Tag` 键帽，冲突可一步“交换”，单行恢复默认；运行时没有“未绑定”值，所以冲突处理是交换而不是清除对方。set-adopt：键帽改原生 `W.Kbd`（G32），焦点离开键帽区即结束录制（G31 `onBlurWithin`）；键帽外观变了，第 2 轮验收以新截图为准） |
| 8 | 所有的modal为什么没有background drop的透明底铺垫？是没用我们的modal吗？ | 全应用的对话框改用 zenit 原生 `W.Modal`（带遮罩）。先清点：设置里的确认、清理数据、AI 子任务对话框等 | H-tokens（恢复默认遮罩：34 处原生 Modal 的遮罩被主题的 `t.overlay = modal_barrier` 改成了全透明）；H-modals（2 处手工拼的模态改原生 Modal；4 处覆盖层待判定，见 NATIVE_AUDIT 清单 1） | 待验收（34 处原生 Modal 与手工遮罩已恢复 zenit 默认遮罩；H-modals-ws：标签页关闭确认与主机密钥确认改原生 Modal，settings 以外 28 处 Modal 的面板回到 zenit 默认外观（不透明 bg-primary、默认圆角 / 描边 / 阴影，不再叠玻璃材质）；settings 里的 Modal 由设置包处理：未保存 / 恢复默认确认（H-save）、模型编辑器与删除服务提供方（F-set-ai）、清除全部数据确认（set-modals：`.yix` 原生 `W.Modal` 默认外观，原先半透明面板 + 玻璃材质）已改；会话记录面板待用户判定（D-4 改 tab content）；h-helpcard：命令帮助卡（B4）改原生 `W.Modal` 默认外观，硬编码浅绿底删除，Esc / 点遮罩 / 关闭都关、焦点回终端——隔离环境真实窗口触发不到，证据是组件测试 `command_help_tests.zig`，截图方法见 YIX_SPIKE“命令帮助卡（h-helpcard）”） | `ZeroWork-evidence/h-tokens/after/*-confirm-modal.png`（对照 `before/`）；`ZeroWork-evidence/h-modals-ws/review/*.png`（对照 `h-modals-ws/before/`） |
| 9 | 我们的Input不是有自己的浅色底吗？为什么在settings里它的底像是没有的，直接就是灰色的container card底色了。 | 删除 `styleInput`、`tuneInput`、`fieldControl` 等对 Input / Select 的覆盖，直接用 zenit 原生 Input / Select（设计稿 `W:rTb0Z`） | 3e（面板正文）：控件一律原生、无覆盖；共享的 `styleInput` 等随其余 feature 在 P4 / P5 清理 | 进行中（设置面板正文九类都已按此执行：3e 第一批、第二批、外观与主题、协议插件、AI 辅助（F-set-ai：提供方详情、模型编辑器、MCP 表单全是原生 `W.Input` / `W.Select` / `W.Textarea` 默认外观）；共享的 `styleInput` 等覆盖仍在旧文件与其余 feature 里，P4 / P5 清理） | 外观：`ZeroWork-evidence/set-appearance/review/`；AI：`e2e/h_ai_capture.ts`（未运行） |
| 10 | 协议插件，我们设计稿已经改了，你没更新事项，它把协议list和协议item detail做成stack panel了。Node IDs: T5k96, KUKQ5 。AI辅助的也改成2层了Node IDs: GV8pb, e2ys05； | 协议插件改两级：列表页 `T5k96` → 详情 `KUKQ5`，与其他分类一样 drill-down。AI 辅助的服务提供方按 `GV8pb`、行为与权限按 `e2ys05` 改两级。PENCIL_MAP 里“保持 master / detail”的偏差作废 | 3e-plugins（F-set-plugins）、3e-ai（F-set-ai） | 协议插件：待验收（列表页 → 详情页两级导航，后退 / 前进、搜索命中、滚动沿用设置窗口机制；行间分隔线、控件原生、“?” 是原生 `W.Tooltip`；插件偏好归详情页的保存作用域。能力对照表、“支持的能力 / 不支持”、“计划中”分组产品没有数据，未做，待用户判定）；AI 辅助：待验收（F-set-ai：服务提供方改为列表 → 提供方详情两级，详情是“服务提供方”子页下的动态第三级 `Location.ai_provider`；行为与权限是普通设置行（保留七个面板分组，`e2ys05` 的行样式）；模型编辑器 / 删除确认改原生 `W.Modal`；行间分隔线、控件原生、“?” 是原生 `W.Tooltip`） | 协议插件：`ZeroWork-evidence/set-plugins/review/`（`{light,dark}-{a-list,b-detail-<插件>,c-back-list,c-forward-detail,d-search-hit,d-search-open,e-permissions-tooltip}.png`）；AI 辅助：组件测试 `tests/ai_provider_settings_tests.zig`、`tests/ai_settings_yix_tests.zig`，采集脚本 `e2e/h_ai_capture.ts`（按“批量开发、批末统一回归”未运行，对照图待批末采集） |
| 11 | settings里所有“？” 的tooltip也不像是zenit原生的。 | 页头帮助、字段帮助等所有“?”提示改用 zenit 原生 `W.Tooltip` 默认外观，不做覆盖 | H-shell（页头帮助）；3e（字段帮助） | 页头帮助：待验收（原生 `W.Tooltip` 默认外观，触发器是原生玻璃圆钮）；字段帮助：进行中（3e；外观与主题已改原生 `W.Tooltip`，F-set-appearance；AI 辅助的设置行“?”与模型编辑器的来源标记改原生 `W.Tooltip`，F-set-ai） | `ZeroWork-evidence/h-shell/`（对照：`review/`；元素说明见 H-shell 汇报） |

## 用户判定（2026-11-13，第一轮之后）

| # | 事项 | 用户原话 / 判定 | 落实 |
|---|---|---|---|
| D-1 | 主题库（搜索 / 筛选 / 收藏） | “以代码功能为准；功能没有，就没有。” 产品里没有入口，当作不存在 | 删除死代码（证据见提交 `62901310`），设计稿这部分不实现；包 set-adopt：已删除（`4e93ef5e`）；状态栏“管理主题”入口仍会写 `theme_library.open`，那部分没删、待判定（见 `YIX_SPIKE.md`“set-adopt”） |
| D-2 | 协议插件的“计划中”分组 | 另做一套正式的插件化方案（`docs/plugins/PLUGIN_ARCH_PLAN.md`，分支 `revamp/plugin-plan`，另一个 agent 负责，完成后交叉评审） | 在那之前设置页不做“计划中”分组，规划中的协议不进生产设置页 |
| D-3 | 协议插件的能力信息 | “以代码为准先” | 不编造能力，行尾继续显示真实版本号 |
| D-4 | 会话记录面板（NATIVE_AUDIT B3） | “会话记录也是既可以 floating 也可以打开的，它就是 tab content 的一种，像 terminal、AI chat panel 一样。” | 改成一种 tab content（浮动 / 作为 tab 打开，与终端、AI chat 同一套机制），不做 Modal / Popover；方案 `docs/ui-revamp/HISTORY_TAB_PLAN.md`（编写中），第一批之后单独成包 |
| D-5 | 命令帮助卡（NATIVE_AUDIT B4） | 改用原生 Modal | 包 h-helpcard：已改（`features/terminal/view/command_help.yix`），待合入与验收 |
| D-6 | T-1 主按钮 | 选 A：统一 zenit 默认 | P4 第一个包 |
| D-7 | G30 紧凑宽度 | 关闭，保持原生 180 | 已落实（`d0952bd1`） |

## 第二轮验收时请用户确认的设计选择

H-save（反馈 4）实现时有三处是实现者按自己的理解定的，第二轮验收时请逐条看：

1. **搜索结果页的保存作用域**：搜索跨分类，所以搜索结果页的作用域是“全部字段”——在搜索结果里改任何字段都能就地保存 / 撤销；进入或改变搜索不弹确认；清空搜索回到原页时，按原页的作用域判定是否要先确认。备选：搜索结果里的改动按字段所属子页归属，离开搜索时逐页确认（更严格但更啰嗦）。
2. **“服务提供方”页的“恢复默认…”**：该页的作用域是提供方表连同 `ai.default_provider`。按统一规则，只要它与默认值不同（即配置过任何提供方）“恢复默认…”就可点，确认后会把本页恢复成默认值——也就是清空已配置的提供方（仍是草稿，保存后才生效、可撤销）。请确认这一页是否应该有“恢复默认…”；备选：这一页不显示“恢复默认…”（提供方只能逐个删除）。
3. **保存提示的位置**：有改动时 Save Bar 是右下角浮动的原生玻璃胶囊（状态文字 + 撤销 + 保存）；保存成功 / 失败的 Toast 是原生通知，位置在设置窗口底部居中。请确认两者的位置；备选：Toast 放右上 / 右下（与主窗口通知一致）。

对照截图：`ZeroWork-evidence/h-save/review/`；设计与转移表：`docs/ui-revamp/YIX_SPIKE.md`“保存状态机（H-save）”。

## 第 2 轮验收材料（第一批收尾，2026-11-13）

验收指南：[`round-2-guide.md`](round-2-guide.md)（含启动验收版本的命令）。截图全部来自集成分支 `feat/ui-arch-revamp` 第一批收尾后的 test-mode 构建（vendor zenit @666ea295），由 e2e 采集脚本在隔离环境抓取，目录 `~/work/ZeroWork-evidence/round-2/`（下表简写为 `round-2/`）。文件名前缀 `light-` / `dark-` 是主题；每条都有亮色，关键的加了暗色。

| # | 状态 | 做了什么（摘要） | 修复后截图 |
|---|---|---|---|
| 1 | 待验收 | 左侧导航浮层、Save Bar 是原生 `W.GlassBox`；页头后退 / 前进 / 帮助是原生工具栏按钮组 `W.GlassToolbarGroup` / `W.GlassToolbarButton` | `round-2/01-glass/`（`{light,dark}-overview`、`{light,dark}-toolbar-back-enabled`、`light-savebar-glass`） |
| 2 | 待验收 | 删掉主题对开关 / 单选 / 复选角色 token 的改写，回到 zenit 默认；外观页主题卡片、对齐九宫格用原生 `W.Radio`，应用图标原生 `W.RadioGroup`，光标形状原生 `W.Tabs`；开关首帧不再从轨道外滑入 | `round-2/02-controls/`（`{light,dark}-switch-on`、`{light,dark}-switch-off-dependents-disabled`、`light-theme-radio-cards`、`light-app-icon-radiogroup`、`light-alignment-radio`、`light-font-cursor-tabs`） |
| 3 | 待验收 | 页头下垫原生 `W.TitlebarEdge` 渐变；视口原生 `scrollEdge`：静止时不出现、内容滚到页头下方才渐进磨砂。本轮修了“静止时第一行被磨砂”的回归（zenit e804139d，回归测试 `settings_scroll_edge_native`，亮 / 暗都过） | `round-2/03-header/`（`{light,dark}-rest-ssh-reconnect-first-line-sharp`、`{light,dark}-keys-at-top`、`{light,dark}-keys-scrolled-under-header-frosted`、`light-scrolled-mid`） |
| 4 | 待验收 | 保存作用域 = 右侧当前子页；有改动才出现 Save Bar；“恢复默认…”相对默认值有变化才可点、先确认；保存成功 / 失败用原生 Toast；带改动切页 / 关窗先确认 | `round-2/04-save/`（`light-{a-clean,b-dirty,c-saved-toast,d-reset-enabled,d-reset-confirm,e-leave-confirm,f-invalid,g-save-failed}`，`dark-{b-dirty,c-saved-toast,e-leave-confirm}`） |
| 5 | 待验收（需手感） | 右侧内容与导航用原生 `W.ScrollArea` 默认回弹 | `round-2/05-rubberband/`（只能给出滚动后的静态画面；回弹手感需真机触控板） |
| 6 | 待验收 | 设置九类面板的行间分隔线（`w3r3t`），末行不画 | `round-2/06-dividers/`（`light-{ssh-connection,transfer-engine,notifications-events,ai-behavior,keys,plugins-list}`、`dark-ssh-connection`） |
| 7 | 待验收 | 快捷键行：悬停提示 → 点击原地录制 → Esc 取消 / 失焦结束；冲突可“交换”；每行单独恢复默认；键帽原生 `W.Kbd` | `round-2/07-keys/`（`light-{rest,hover,recording,conflict,invalid,modified,reset}`、`dark-{rest,recording,conflict}`） |
| 8 | 待验收 | 对话框统一原生 `W.Modal`（默认遮罩、不透明默认面板）：设置的未保存 / 恢复默认确认、主窗口关闭标签页、AI 模型编辑器 / 删除服务提供方、清除全部数据、命令帮助卡 | `round-2/08-modals/`（`light-settings-reset-confirm`、`{light,dark}-settings-unsaved-confirm`、`{light,dark}-tab-close-confirm`、`light-ai-model-editor`、`light-ai-delete-provider`） |
| 9 | 设置窗口内待验收；设置以外进行中 | 设置面板里 Input / Select / Textarea 都是原生默认外观；共享的 `styleInput` 等覆盖还在设置以外的旧文件，P4 / P5 清理 | `round-2/09-inputs/`（`light-{ssh-connection,transfer-defaults,ai-provider-detail}`、`dark-ssh-connection`） |
| 10 | 待验收 | 协议插件：列表 → 详情两级；AI 辅助：服务提供方列表 → 提供方详情两级，行为与权限是普通设置行 | `round-2/10-two-level/`（`light-plugins-{a-list,b-detail-ssh,c-back-list,d-search-open}`、`light-ai-{b-provider-list,c-provider-detail,f-behavior}`、`dark-plugins-b-detail-ssh`、`dark-ai-c-provider-detail`） |
| 11 | 设置窗口内待验收；设置以外进行中 | 页头帮助、字段“?”是原生 `W.Tooltip` 默认外观；设置以外的面板随 P4 / P5 替换 | `round-2/11-tooltips/`（`{light,dark}-header-help`、`light-plugins-field-help`、`light-appearance-field-help`、`light-keys-edit-hint`） |

其余第一批改动的截图：`round-2/extra-switch/`（开关首帧）、`extra-render/`（主窗口 / 本地终端 / 设置正常渲染）、`extra-opaque/`（浮层不随材质透明）、`extra-notify/`（设置保存 Toast / 失败提示）、`extra-workspace/`（主窗口工作区，与 P2 基线逐像素一致）。

本轮回归（断网 + 私有 HOME，test-mode）：截图采集与设置相关 e2e 32/32 通过（`ZeroWork-evidence/batch1-close/captures/SUMMARY.tsv`）；主窗口 workspace 截图与 P2 基线、第一批门禁三张逐像素一致；设置 30 张整页截图与第一批门禁相比，差异只在页头下 28 pt 的 scroll edge 带（本次修复的预期变化）以及“位置与凭据”“关于与更新”里随环境变化的路径 / 时间文字。

## 变更记录

| 日期 | 变更 |
|---|---|
| 2026-11-12 | 建立跟踪表；11 条登记 |
| 2026-11-12 | H-shell：第 1、3、5 条与第 11 条（页头帮助）改为 `待验收`；新登记 zenit 缺口 G27（GlassToolbar 的 Yix 形态与禁用态）、G28（titlebarEdge / scroll-edge 的 Yix 形态）、G29（GlassBox 填满父容器高度） |
| 2026-11-13 | H-save：第 4 条改为 `待验收`；新登记 zenit 缺口 G36（关着的 Modal 仍在 Tab 顺序里）、G37（Modal 首次打开自动聚焦落空）、G38（Notifier 没有 Yix 形态）；第 8 条相关：设置的未保存 / 恢复默认确认改为原生 `W.Modal` 默认外观 |
| 2026-11-13 | set-adopt（vendor @bc57f042）：第 1 条页头按钮改原生工具栏按钮组（G27），第 3 条渐变改原生 `W.TitlebarEdge` 并加视口 scroll edge 渐进磨砂（G28），第 7 条键帽改原生 `W.Kbd`（G32）、失焦结束录制（G31）；状态仍为 `待验收`（外观有变化，等第 2 轮确认）；D-1 主题库死代码已删除 |
| 2026-11-13 | F-set-appearance：外观与主题面板落实第 2（外观页单选 / 分段原生化）、6（分隔线）、9（Input / Select 原生）、11（字段“?”原生 Tooltip）条 |
| 2026-11-13 | h-helpcard：第 8 条相关——命令帮助卡（B4）改原生 `W.Modal`；新登记 zenit 缺口 G43（Modal 标题栏关闭按钮不可聚焦，只读 Modal 打开后焦点落空）、G44（Modal 高度上限不随窗口高度收缩） |
| 2026-11-13 | F-set-ai：第 10 条 AI 部分改为 `待验收`（服务提供方两级、对话框原生 Modal）；AI 辅助面板落实第 6（行间分隔线；设置九类都已带，第 6 条改为 `待验收`）、9（Input / Select 原生）、11（字段“?”原生 Tooltip）条；新缺口 G46–G48 |
| 2026-11-13 | set-modals：第 8 条相关——“清除全部数据…”确认改为原生 `W.Modal` 默认外观；“自定义 TERM 声明…”的手拼浮层改原生 `W.Popover` + `W.Input`；另修设置窗口里背景缩略图与行内材质预览空白（纹理归属，第一轮验收后发现） |
| 2026-11-13 | 第一批收尾：第 3 条修复“静止时第一行正文被 scroll edge 磨砂”（zenit e804139d，vendor @666ea295，回归测试 `e2e/settings_scroll_edge_native.ts`）；新增“第 2 轮验收材料”一节（逐条状态、修复后截图 `ZeroWork-evidence/round-2/`），验收指南 `round-2-guide.md` |
