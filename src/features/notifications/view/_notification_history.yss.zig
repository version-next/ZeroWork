// GENERATED FILE, do not edit: generated from notification_history.yss; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! 通知历史弹层的排版。弹层面板、卡片、按钮、角标、提示都是原生组件默认外观；这里只写布局与正文文字
//! （字号 / 换行 / token 墨色），不写背景、圆角、阴影、玻璃。
const ui = @import("ui");

/// 原生 Popover 的挂载点：弹层自己挂到窗口浮层根（portal），模板根不能为空，留一个不占位的 box。
pub const popover_anchor = ui.previewCss("src/features/notifications/view/notification_history.yss", "popover_anchor", @embedFile("notification_history.yss"), .{ .position = .absolute, .width = 0, .height = 0, });
/// 铃铛右上角的角标位置（铃铛按钮是原生 W.Button，角标绝对定位在它里面）。
pub const badge_slot = ui.previewCss("src/features/notifications/view/notification_history.yss", "badge_slot", @embedFile("notification_history.yss"), .{ .position = .absolute, .inset = ui.Inset{ .right = .{ .px = 0 }, .top = .{ .px = 0 } }, .width = .fit, .height = .fit, });

pub const panel = ui.previewCss("src/features/notifications/view/notification_history.yss", "panel", @embedFile("notification_history.yss"), .{ .width = .fill, .height = .fit, .direction = .column, .gap = 8, });
pub const filters = ui.previewCss("src/features/notifications/view/notification_history.yss", "filters", @embedFile("notification_history.yss"), .{ .width = .fill, .direction = .row, .gap = 6, .flex_shrink = 0, });
/// 列表视口：随内容长高，最高 320；空态 152。
pub const viewport = ui.previewCss("src/features/notifications/view/notification_history.yss", "viewport", @embedFile("notification_history.yss"), .{ .width = .fill, .height = .fit, .min_height = 152, .max_height = 320, .flex_shrink = 0, });
pub const list = ui.previewCss("src/features/notifications/view/notification_history.yss", "list", @embedFile("notification_history.yss"), .{ .width = .fill, .direction = .column, .gap = 6, });
pub const footer = ui.previewCss("src/features/notifications/view/notification_history.yss", "footer", @embedFile("notification_history.yss"), .{ .width = .fill, .direction = .row, .justify = .end, .flex_shrink = 0, });

/// 空状态的槽：原生 `W.Empty` 填满它（与列表视口的空态高度一致）。
pub const empty = ui.previewCss("src/features/notifications/view/notification_history.yss", "empty", @embedFile("notification_history.yss"), .{ .width = .fill, .height = 152, .direction = .column, });
pub const secondary = ui.previewCss("src/features/notifications/view/notification_history.yss", "secondary", @embedFile("notification_history.yss"), .{ .font_size = 11, .line_height = 1.6, .color = ui.tokenRef(.color, "fg-secondary"), .text_overflow = .ellipsis, .selectable = false, });

pub const record = ui.previewCss("src/features/notifications/view/notification_history.yss", "record", @embedFile("notification_history.yss"), .{ .width = .fill, .direction = .column, .gap = 4, });
pub const record_main = ui.previewCss("src/features/notifications/view/notification_history.yss", "record_main", @embedFile("notification_history.yss"), .{ .width = .fill, .direction = .row, .align_items = .start, .gap = 8, });
pub const Severity = ui.previewCva("src/features/notifications/view/notification_history.yss", "Severity", @embedFile("notification_history.yss"), .{ .base = .{ .width = 14, .height = 14, .flex_shrink = 0, .margin = .{ .top = 2, .right = 0, .bottom = 0, .left = 0 }, }, .variants = .{ .tone = .{ .info = .{ .icon_color = ui.tokenRef(.color, "fg-secondary"), }, .success = .{ .icon_color = ui.tokenRef(.color, "success"), }, .warning = .{ .icon_color = ui.tokenRef(.color, "warning"), }, .danger = .{ .icon_color = ui.tokenRef(.color, "danger"), }, }, }, .defaults = .{ .tone = .info, }, });
pub const Tone = Severity.Dim(.tone);
pub const record_title = ui.previewCss("src/features/notifications/view/notification_history.yss", "record_title", @embedFile("notification_history.yss"), .{ .flex = 1, .min_width = 0, .font_size = 12, .font_weight = 500, .line_height = 1.5, .color = ui.tokenRef(.color, "fg-primary"), .wrap = .word, .selectable = false, });
pub const age = ui.previewCss("src/features/notifications/view/notification_history.yss", "age", @embedFile("notification_history.yss"), .{ .flex_shrink = 0, .max_width = 76, .font_size = 10.5, .line_height = 1.7, .color = ui.tokenRef(.color, "fg-secondary"), .selectable = false, });
pub const indented = ui.previewCss("src/features/notifications/view/notification_history.yss", "indented", @embedFile("notification_history.yss"), .{ .width = .fill, .padding = .{ .top = 0, .right = 0, .bottom = 0, .left = 22 }, });
/// 详情：完整原因在有界滚动区里（最高 240）。
pub const details = ui.previewCss("src/features/notifications/view/notification_history.yss", "details", @embedFile("notification_history.yss"), .{ .width = .fill, .height = .fit, .max_height = 240, .min_height = 0, });
pub const details_content = ui.previewCss("src/features/notifications/view/notification_history.yss", "details_content", @embedFile("notification_history.yss"), .{ .width = .fill, .direction = .column, .gap = 4, .padding = .{ .top = 4, .right = 0, .bottom = 2, .left = 22 }, });
pub const Detail = ui.previewCva("src/features/notifications/view/notification_history.yss", "Detail", @embedFile("notification_history.yss"), .{ .base = .{ .font_size = 12, .line_height = 1.5, .wrap = .word, .selectable = false, }, .variants = .{ .failure = .{ .false = .{ .color = ui.tokenRef(.color, "fg-secondary"), }, .true = .{ .color = ui.tokenRef(.color, "danger"), }, }, }, .defaults = .{ .failure = false, }, });
pub const source = ui.previewCss("src/features/notifications/view/notification_history.yss", "source", @embedFile("notification_history.yss"), .{ .width = .fill, .direction = .row, .align_items = .center, .gap = 6, });
pub const source_label = ui.previewCss("src/features/notifications/view/notification_history.yss", "source_label", @embedFile("notification_history.yss"), .{ .flex = 1, .min_width = 0, .font_size = 11, .color = ui.tokenRef(.color, "fg-secondary"), .text_overflow = .ellipsis, });
pub const actions = ui.previewCss("src/features/notifications/view/notification_history.yss", "actions", @embedFile("notification_history.yss"), .{ .width = .fill, .direction = .row, .flex_wrap = .wrap, .align_items = .center, .justify = .end, .gap = 6, .padding = .{ .top = 4, .right = 0, .bottom = 0, .left = 22 }, });

//# yix-map notification_history.yss
