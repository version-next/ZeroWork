// GENERATED FILE, do not edit: generated from history_card.yss; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! 会话记录卡片的排版（设计稿 Pencil「ZW · 会话记录卡片补稿 2026-11-13（PL4b）」）。卡片框、按钮、
//! 输入框、标签、分隔线、弹层、滚动区都是原生组件默认外观；这里只写布局、正文文字（字号 / 换行 /
//! token 墨色）与选中行的列表选中底色，不写原生组件的背景、圆角、阴影、玻璃。
const ui = @import("ui");

/// 卡片根 / 内容根：填满宿主给的槽（统一窗口外观的内容区，或 tab 的内容区）。
pub const root = ui.previewCss("src/features/history/view/history_card.yss", "root", @embedFile("history_card.yss"), .{ .width = .fill, .height = .fill, .min_width = 0, .min_height = 0, .direction = .column, });

pub const header_action = ui.previewCss("src/features/history/view/history_card.yss", "header_action", @embedFile("history_card.yss"), .{ .width = .fit, .height = .fit, .flex_shrink = 0, });

pub const body = ui.previewCss("src/features/history/view/history_card.yss", "body", @embedFile("history_card.yss"), .{ .width = .fill, .min_width = 0, .height = .fill, .min_height = 0, .direction = .row, });
pub const vertical_divider = ui.previewCss("src/features/history/view/history_card.yss", "vertical_divider", @embedFile("history_card.yss"), .{ .width = .fit, .height = .fill, .flex_shrink = 0, });
pub const horizontal_divider = ui.previewCss("src/features/history/view/history_card.yss", "horizontal_divider", @embedFile("history_card.yss"), .{ .width = .fill, .height = .fit, .flex_shrink = 0, });

/// 列表栏：并排时宽 320；窄卡片只显示列表时填满。
pub const List = ui.previewCva("src/features/history/view/history_card.yss", "List", @embedFile("history_card.yss"), .{ .base = .{ .height = .fill, .min_width = 0, .min_height = 0, .direction = .column, .flex_shrink = 0, }, .variants = .{ .alone = .{ .false = .{ .width = 320, }, .true = .{ .width = .{ .grow = .{} }, .flex_shrink = 1, }, }, }, .defaults = .{ .alone = false, }, });
pub const list_body = ui.previewCss("src/features/history/view/history_card.yss", "list_body", @embedFile("history_card.yss"), .{ .width = .fill, .min_width = 0, .height = .fill, .min_height = 0, .direction = .column, .gap = 8, .padding = 8, });
pub const filters = ui.previewCss("src/features/history/view/history_card.yss", "filters", @embedFile("history_card.yss"), .{ .width = .fill, .min_width = 0, .height = 28, .direction = .row, .align_items = .center, .gap = 4, .flex_shrink = 0, });
pub const anchor = ui.previewCss("src/features/history/view/history_card.yss", "anchor", @embedFile("history_card.yss"), .{ .direction = .column, .align_items = .end, .flex_shrink = 0, });
pub const viewport = ui.previewCss("src/features/history/view/history_card.yss", "viewport", @embedFile("history_card.yss"), .{ .width = .fill, .min_width = 0, .height = .fill, .min_height = 0, .direction = .column, });
pub const scroll = ui.previewCss("src/features/history/view/history_card.yss", "scroll", @embedFile("history_card.yss"), .{ .width = .fill, .min_width = 0, .height = .fill, .min_height = 0, });
pub const rows = ui.previewCss("src/features/history/view/history_card.yss", "rows", @embedFile("history_card.yss"), .{ .width = .fill, .min_width = 0, .direction = .column, .gap = 2, });
pub const paging = ui.previewCss("src/features/history/view/history_card.yss", "paging", @embedFile("history_card.yss"), .{ .width = .fill, .height = 28, .direction = .row, .justify = .end, .align_items = .center, .gap = 8, .flex_shrink = 0, });
pub const message_row = ui.previewCss("src/features/history/view/history_card.yss", "message_row", @embedFile("history_card.yss"), .{ .width = .fill, .direction = .row, .flex_shrink = 0, });
pub const Message = ui.previewCva("src/features/history/view/history_card.yss", "Message", @embedFile("history_card.yss"), .{ .base = .{ .font_size = 12, .line_height = 1.4, .wrap = .word, .selectable = false, }, .variants = .{ .warning = .{ .false = .{ .color = ui.tokenRef(.color, "fg-secondary"), }, .true = .{ .color = ui.tokenRef(.color, "warning"), }, }, }, .defaults = .{ .warning = false, }, });
pub const retry = ui.previewCss("src/features/history/view/history_card.yss", "retry", @embedFile("history_card.yss"), .{ .width = .fill, .direction = .row, .flex_shrink = 0, });

pub const Record = ui.previewCva("src/features/history/view/history_card.yss", "Record", @embedFile("history_card.yss"), .{ .base = .{ .width = .fill, .min_width = 0, .height = 56, .direction = .row, .align_items = .start, .gap = 8, .padding = .{ .top = 6, .right = 6, .bottom = 6, .left = 8 }, .corner_radius = 6, .flex_shrink = 0, }, .variants = .{ .selected = .{ .false = .{ }, .true = .{ .background = ui.tokenRef(.color, "list-selection-bg"), }, }, }, .defaults = .{ .selected = false, }, });
pub const record_icon = ui.previewCss("src/features/history/view/history_card.yss", "record_icon", @embedFile("history_card.yss"), .{ .width = 16, .height = 16, .flex_shrink = 0, .margin = .{ .top = 2, .right = 0, .bottom = 0, .left = 0 }, .icon_color = ui.tokenRef(.color, "fg-secondary"), });
pub const record_main = ui.previewCss("src/features/history/view/history_card.yss", "record_main", @embedFile("history_card.yss"), .{ .width = .{ .grow = .{} }, .min_width = 0, .direction = .column, .gap = 2, });
pub const record_meta = ui.previewCss("src/features/history/view/history_card.yss", "record_meta", @embedFile("history_card.yss"), .{ .width = .fill, .min_width = 0, .height = 18, .direction = .row, .align_items = .center, .gap = 8, });
pub const record_tail = ui.previewCss("src/features/history/view/history_card.yss", "record_tail", @embedFile("history_card.yss"), .{ .width = .fill, .min_width = 0, .height = 26, .direction = .row, .align_items = .center, .gap = 4, });
pub const grow = ui.previewCss("src/features/history/view/history_card.yss", "grow", @embedFile("history_card.yss"), .{ .width = .{ .grow = .{} }, .min_width = 0, .direction = .row, });
/// 记录标题 / 详情文字节点自身的盒：填满、可收缩到 0，文字单行省略号截断（与设置窗口扩展列表同一写法）。
pub const text_box = ui.previewCss("src/features/history/view/history_card.yss", "text_box", @embedFile("history_card.yss"), .{ .width = .fill, .min_width = 0, });
pub const record_title = ui.previewCss("src/features/history/view/history_card.yss", "record_title", @embedFile("history_card.yss"), .{ .font_size = 12.5, .font_weight = 500, .color = ui.tokenRef(.color, "fg-primary"), .wrap = .none, .text_overflow = .ellipsis, .selectable = false, });
pub const record_date = ui.previewCss("src/features/history/view/history_card.yss", "record_date", @embedFile("history_card.yss"), .{ .flex_shrink = 0, .font_size = 11, .color = ui.tokenRef(.color, "fg-secondary"), .selectable = false, });
pub const record_detail = ui.previewCss("src/features/history/view/history_card.yss", "record_detail", @embedFile("history_card.yss"), .{ .font_size = 11, .color = ui.tokenRef(.color, "fg-secondary"), .wrap = .none, .text_overflow = .ellipsis, .selectable = false, });

/// 空状态的槽：原生 `W.Empty` 填满它。
pub const empty = ui.previewCss("src/features/history/view/history_card.yss", "empty", @embedFile("history_card.yss"), .{ .width = .fill, .height = 240, .direction = .column, });
pub const placeholder = ui.previewCss("src/features/history/view/history_card.yss", "placeholder", @embedFile("history_card.yss"), .{ .width = .fill, .height = .fill, .direction = .column, .align_items = .center, .justify = .center, .gap = 6, .padding = 16, });
pub const placeholder_hint = ui.previewCss("src/features/history/view/history_card.yss", "placeholder_hint", @embedFile("history_card.yss"), .{ .font_size = 12, .color = ui.tokenRef(.color, "fg-secondary"), .wrap = .word, .selectable = false, });

pub const confirmation = ui.previewCss("src/features/history/view/history_card.yss", "confirmation", @embedFile("history_card.yss"), .{ .width = .fill, .direction = .column, .gap = 6, .padding = 12, });
pub const confirmation_title = ui.previewCss("src/features/history/view/history_card.yss", "confirmation_title", @embedFile("history_card.yss"), .{ .font_size = 13, .font_weight = 500, .color = ui.tokenRef(.color, "fg-primary"), .wrap = .word, .selectable = false, });
pub const confirmation_actions = ui.previewCss("src/features/history/view/history_card.yss", "confirmation_actions", @embedFile("history_card.yss"), .{ .width = .fill, .direction = .row, .align_items = .center, .gap = 8, .padding = .{ .top = 6, .right = 0, .bottom = 0, .left = 0 }, });

pub const detail = ui.previewCss("src/features/history/view/history_card.yss", "detail", @embedFile("history_card.yss"), .{ .width = .{ .grow = .{} }, .min_width = 0, .height = .fill, .min_height = 0, .direction = .column, });
pub const detail_header = ui.previewCss("src/features/history/view/history_card.yss", "detail_header", @embedFile("history_card.yss"), .{ .width = .fill, .height = 36, .direction = .row, .align_items = .center, .gap = 8, .padding = .{ .top = 0, .right = 8, .bottom = 0, .left = 12 }, .flex_shrink = 0, });
pub const detail_title = ui.previewCss("src/features/history/view/history_card.yss", "detail_title", @embedFile("history_card.yss"), .{ .flex_shrink = 0, .max_width = 240, .font_size = 12.5, .font_weight = 500, .color = ui.tokenRef(.color, "fg-primary"), .text_overflow = .ellipsis, .selectable = false, });
pub const detail_meta = ui.previewCss("src/features/history/view/history_card.yss", "detail_meta", @embedFile("history_card.yss"), .{ .width = .{ .grow = .{} }, .min_width = 0, .font_size = 11, .color = ui.tokenRef(.color, "fg-secondary"), .text_overflow = .ellipsis, .selectable = false, });
/// 只读回放表面的插槽（终端视图由宿主放进来，填满）。
pub const surface = ui.previewCss("src/features/history/view/history_card.yss", "surface", @embedFile("history_card.yss"), .{ .width = .fill, .height = .fill, .min_height = 0, .direction = .column, });

//# yix-map history_card.yss
