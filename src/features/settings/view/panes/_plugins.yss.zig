// GENERATED FILE, do not edit: generated from plugins.yss; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! 协议插件（F-set-plugins，人工验收反馈第 10 条）的样式：列表页（`T5k96`）与详情页（`KUKQ5`）的面板列、详情页头部卡片。
//! 列表行是 `components/rows.yix` 的 `DrillRow`（样式在 `../styles.yss`）；来源标签是原生 `W.Tag`、偏好控件是原生
//! `W.Switch` / `W.Input` / `W.Select`、“?”是原生 `W.Tooltip` + ghost 图标按钮（默认外观，不覆盖）。颜色全部是 token。
const ui = @import("ui");

/// 面板列（`upC2F` / `l3IbX`）：面板之间 18（内边距由内容页的 `PageBody` 给）。
pub const panes = ui.previewCss("src/features/settings/view/panes/plugins.yss", "panes", @embedFile("plugins.yss"), .{ .width = .fill, .height = .fit, .direction = .column, .gap = 18, .flex_shrink = 0, .min_width = 0, });
/// 详情页的概要面板（`B57vb`）：卡片 + 下方说明，gap 6。
pub const summary_pane = ui.previewCss("src/features/settings/view/panes/plugins.yss", "summary_pane", @embedFile("plugins.yss"), .{ .width = .fill, .direction = .column, .gap = ui.tokenRef(.space, "space150"), .flex_shrink = 0, .min_width = 0, });
/// 头部卡片（`Y01lz` › `E3vPk2`）：padding [12, 14]、圆角 12，窗面静止底色（同其它面板的正文卡片）；图标底 + 名称 / 说明 + 来源标签，gap 12。
pub const head_card = ui.previewCss("src/features/settings/view/panes/plugins.yss", "head_card", @embedFile("plugins.yss"), .{ .width = .fill, .direction = .row, .align_items = .center, .gap = ui.tokenRef(.space, "space300"), .padding = .{ .y = 12, .x = 14 }, .corner_radius = 12, .background = ui.tokenRef(.color, "zw-window-rest"), .flex_shrink = 0, .min_width = 0, });
/// 图标底（`vWhvc`）：40、圆角 10、发丝描边，窗面底色；图标 20 次要墨色。
pub const head_tile = ui.previewCss("src/features/settings/view/panes/plugins.yss", "head_tile", @embedFile("plugins.yss"), .{ .width = 40, .height = 40, .flex_shrink = 0, .direction = .row, .align_items = .center, .justify = .center, .corner_radius = 10, .background = ui.tokenRef(.color, "zw-window-surface"), .border_overlay = true, .border_width = 1, .border_color = ui.tokenRef(.color, "border"), });
pub const head_icon = ui.previewCss("src/features/settings/view/panes/plugins.yss", "head_icon", @embedFile("plugins.yss"), .{ .width = 20, .height = 20, .icon_color = ui.tokenRef(.color, "fg-secondary"), });
pub const head_copy = ui.previewCss("src/features/settings/view/panes/plugins.yss", "head_copy", @embedFile("plugins.yss"), .{ .width = .fill, .flex = 1, .min_width = 0, .direction = .column, .align_items = .start, .gap = 2, });
/// 名称（`oydWb`）15 / 600；说明（`s4bhsc`）11.5 次要墨色。
pub const head_name = ui.previewCss("src/features/settings/view/panes/plugins.yss", "head_name", @embedFile("plugins.yss"), .{ .font_size = 15, .font_weight = 600, .line_height = 20.0 / 15.0, .color = ui.tokenRef(.color, "fg-primary"), .wrap = .none, .text_overflow = .ellipsis, });
pub const head_summary = ui.previewCss("src/features/settings/view/panes/plugins.yss", "head_summary", @embedFile("plugins.yss"), .{ .font_size = 11.5, .font_weight = 400, .line_height = 16.0 / 11.5, .color = ui.tokenRef(.color, "zw-fg-supporting"), .wrap = .word, });
pub const head_text_box = ui.previewCss("src/features/settings/view/panes/plugins.yss", "head_text_box", @embedFile("plugins.yss"), .{ .width = .fill, .min_width = 0, });
/// 卡片下的说明（`cP48r` / `Xz83P`）：padding [0, 10]，11、行高 1.4，次要墨色。
pub const note_wrap = ui.previewCss("src/features/settings/view/panes/plugins.yss", "note_wrap", @embedFile("plugins.yss"), .{ .width = .fill, .direction = .row, .padding = .{ .y = 0, .x = 10 }, .flex_shrink = 0, });
pub const note = ui.previewCss("src/features/settings/view/panes/plugins.yss", "note", @embedFile("plugins.yss"), .{ .font_size = 11, .font_weight = 400, .line_height = 1.4, .color = ui.tokenRef(.color, "zw-fg-supporting"), .wrap = .word, });
pub const note_box = ui.previewCss("src/features/settings/view/panes/plugins.yss", "note_box", @embedFile("plugins.yss"), .{ .width = .fill, .min_width = 0, });
/// 只读值（版本、权限）右侧一组：值 + “?”，gap 4。
pub const value_group = ui.previewCss("src/features/settings/view/panes/plugins.yss", "value_group", @embedFile("plugins.yss"), .{ .flex_shrink = 0, .direction = .row, .align_items = .center, .gap = 4, });

// ── 计划中（路线条目，`T5k96` › `g3bxO3`） ──

/// 计划行（`Wlmxe`）：结构同 `DrillRow`（图标底 + 行内 gap 12），但不可点击：没有悬停 / 按下态、尾注与箭头。
pub const planned_row = ui.previewCss("src/features/settings/view/panes/plugins.yss", "planned_row", @embedFile("plugins.yss"), .{ .width = .fill, .height = .fit, .flex_shrink = 0, .direction = .row, .align_items = .center, .gap = ui.tokenRef(.space, "space300"), .padding = 0, .background = ui.Color.TRANSPARENT, });
/// 图标（`l04y41`）16，三级墨色。
pub const planned_icon = ui.previewCss("src/features/settings/view/panes/plugins.yss", "planned_icon", @embedFile("plugins.yss"), .{ .width = 16, .height = 16, .icon_color = ui.tokenRef(.color, "zw-fg-supporting"), });
/// 名称（`Nz8ue`）13 / 400，次要墨色（未实现的条目比已注册插件弱一级）。
pub const planned_title = ui.previewCss("src/features/settings/view/panes/plugins.yss", "planned_title", @embedFile("plugins.yss"), .{ .font_size = 13, .font_weight = 400, .line_height = 18.0 / 13.0, .color = ui.tokenRef(.color, "fg-secondary"), .wrap = .none, .text_overflow = .ellipsis, });

// ── 状态（Q5，Pencil XqqLV 稿 2） ──

/// 待重启 / 已禁用提示（原生 `W.Alert`）的外框：撑满面板宽度，只负责布局，不改 Alert 外观。
pub const notice = ui.previewCss("src/features/settings/view/panes/plugins.yss", "notice", @embedFile("plugins.yss"), .{ .width = .fill, .direction = .column, .flex_shrink = 0, .min_width = 0, });
/// 开关下方的说明（Jm2fZ）：随行宽展开（设计稿里是一行），窄窗口时折行。
pub const toggle_hint_box = ui.previewCss("src/features/settings/view/panes/plugins.yss", "toggle_hint_box", @embedFile("plugins.yss"), .{ .width = .fill, .min_width = 0, });

//# yix-map plugins.yss
