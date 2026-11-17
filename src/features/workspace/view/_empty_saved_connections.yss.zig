// GENERATED FILE, do not edit: generated from empty_saved_connections.yss; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! 空工作区“已保存的连接”的布局与字号（hmCmB `vDyAK`；行同环境行 ZW4 / Project Row）。行本身是原生 `W.Pressable`，
//! 这里只给它排版与悬停 / 按下底色（Project Row 的 hover gjAf6 = bg-hover、press NQngd = bg-active）。
const ui = @import("ui");

/// 列表：宽 440，行间 1。
pub const root = ui.previewCss("src/features/workspace/view/empty_saved_connections.yss", "root", @embedFile("empty_saved_connections.yss"), .{ .width = 440, .height = .fit, .direction = .column, .align_items = .stretch, .gap = 1, .flex_shrink = 0, });
/// 标题行：24 高，左右 8。
pub const heading = ui.previewCss("src/features/workspace/view/empty_saved_connections.yss", "heading", @embedFile("empty_saved_connections.yss"), .{ .width = .fill, .height = 24, .direction = .row, .align_items = .center, .padding = .{ .y = 0, .x = 8 }, .flex_shrink = 0, });
pub const heading_text = ui.previewCss("src/features/workspace/view/empty_saved_connections.yss", "heading_text", @embedFile("empty_saved_connections.yss"), .{ .font_size = 12, .font_weight = 400, .line_height = 1.5, .color = ui.tokenRef(.color, "fg-secondary"), .wrap = .none, });
pub const rows = ui.previewCss("src/features/workspace/view/empty_saved_connections.yss", "rows", @embedFile("empty_saved_connections.yss"), .{ .width = .fill, .height = .fit, .direction = .column, .align_items = .stretch, .gap = 1, });
/// 一行：28 高、圆角 6、左右 8、gap 8。被禁用协议的主机不给悬停 / 按下底色（不可连接）。
pub const Row = ui.previewCva("src/features/workspace/view/empty_saved_connections.yss", "Row", @embedFile("empty_saved_connections.yss"), .{ .base = .{ .width = .fill, .height = 28, .flex_shrink = 0, .min_width = 0, .direction = .row, .align_items = .center, .gap = 8, .padding = .{ .y = 0, .x = 8 }, .corner_radius = 6, .background = ui.Color.TRANSPARENT, ._hover = .{ .background = ui.tokenRef(.color, "bg-hover"), }, ._active = .{ .background = ui.tokenRef(.color, "bg-active"), }, }, .variants = .{ .unavailable = .{ .false = .{ }, .true = .{ ._hover = .{ .background = ui.Color.TRANSPARENT, }, ._active = .{ .background = ui.Color.TRANSPARENT, }, }, }, }, .defaults = .{ .unavailable = false, }, });
/// 图标：次要墨色；已禁用（qQaos）降为淡墨。
pub const Icon = ui.previewCva("src/features/workspace/view/empty_saved_connections.yss", "Icon", @embedFile("empty_saved_connections.yss"), .{ .base = .{ .width = 16, .height = 16, .flex_shrink = 0, .icon_color = ui.tokenRef(.color, "fg-secondary"), }, .variants = .{ .unavailable = .{ .false = .{ }, .true = .{ .icon_color = ui.tokenRef(.color, "zw-fg-faint"), }, }, }, .defaults = .{ .unavailable = false, }, });
/// 名称：13 / 400 主墨色，单行省略，占满剩余宽度；已禁用降为淡墨（同侧栏名称）。
pub const Name = ui.previewCva("src/features/workspace/view/empty_saved_connections.yss", "Name", @embedFile("empty_saved_connections.yss"), .{ .base = .{ .font_size = 13, .font_weight = 400, .line_height = 20.0 / 13.0, .color = ui.tokenRef(.color, "fg-primary"), .wrap = .none, .text_overflow = .ellipsis, }, .variants = .{ .unavailable = .{ .false = .{ }, .true = .{ .color = ui.tokenRef(.color, "zw-fg-faint"), }, }, }, .defaults = .{ .unavailable = false, }, });
pub const name_box = ui.previewCss("src/features/workspace/view/empty_saved_connections.yss", "name_box", @embedFile("empty_saved_connections.yss"), .{ .width = .fill, .flex = 1, .min_width = 0, .flex_shrink = 1, });
/// 路由（或“已禁用”）：11 / 400 次要墨色，不收缩。
pub const meta = ui.previewCss("src/features/workspace/view/empty_saved_connections.yss", "meta", @embedFile("empty_saved_connections.yss"), .{ .font_size = 11, .font_weight = 400, .line_height = 16.0 / 11.0, .color = ui.tokenRef(.color, "fg-secondary"), .wrap = .none, });
pub const meta_box = ui.previewCss("src/features/workspace/view/empty_saved_connections.yss", "meta_box", @embedFile("empty_saved_connections.yss"), .{ .flex_shrink = 0, });

//# yix-map empty_saved_connections.yss
