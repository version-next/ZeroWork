// GENERATED FILE, do not edit: generated from command_help.yss; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! 命令帮助卡（`@help`，NATIVE_AUDIT B4）的正文样式。面板、遮罩、标题栏、关闭按钮都是原生 `W.Modal` 默认外观，
//! 这里只排正文：指令列表（原生 `W.ScrollArea`，窗口矮时在面板内滚动）与两行脚注。颜色只用 token。
const ui = @import("ui");

/// 原生 Modal 的挂载点：Modal 自己挂到窗口浮层根（portal），模板根不能为空，留一个不占位的 box。
pub const anchor = ui.previewCss("src/features/terminal/view/command_help.yss", "anchor", @embedFile("command_help.yss"), .{ .position = .absolute, .width = 0, .height = 0, });
/// 正文：列表在上、脚注在下；列表吃掉面板剩余高度，脚注不收缩。
pub const body = ui.previewCss("src/features/terminal/view/command_help.yss", "body", @embedFile("command_help.yss"), .{ .width = .fill, .height = .{ .grow = .{} }, .min_height = 0, .direction = .column, .gap = 8, });
pub const list_scroll = ui.previewCss("src/features/terminal/view/command_help.yss", "list_scroll", @embedFile("command_help.yss"), .{ .width = .fill, .flex = 1, .flex_shrink = 1, .min_height = 0, });
pub const list = ui.previewCss("src/features/terminal/view/command_help.yss", "list", @embedFile("command_help.yss"), .{ .width = .fill, .direction = .column, });
/// 一行：图标列 20、用法列 150（等宽、强调色）、说明。
pub const row = ui.previewCss("src/features/terminal/view/command_help.yss", "row", @embedFile("command_help.yss"), .{ .width = .fill, .height = 28, .direction = .row, .align_items = .center, .gap = 11, .flex_shrink = 0, });
pub const icon_cell = ui.previewCss("src/features/terminal/view/command_help.yss", "icon_cell", @embedFile("command_help.yss"), .{ .width = 20, .align_items = .center, .flex_shrink = 0, });
pub const usage_cell = ui.previewCss("src/features/terminal/view/command_help.yss", "usage_cell", @embedFile("command_help.yss"), .{ .width = 150, .flex_shrink = 0, });
pub const icon = ui.previewCss("src/features/terminal/view/command_help.yss", "icon", @embedFile("command_help.yss"), .{ .font_size = 12, .color = ui.tokenRef(.color, "fg-primary"), });
pub const usage = ui.previewCss("src/features/terminal/view/command_help.yss", "usage", @embedFile("command_help.yss"), .{ .font_size = 11, .font_weight = 600, .color = ui.tokenRef(.color, "accent"), .use_monospace_font = true, });
pub const description = ui.previewCss("src/features/terminal/view/command_help.yss", "description", @embedFile("command_help.yss"), .{ .font_size = 11.5, .color = ui.tokenRef(.color, "fg-secondary"), });
pub const footer = ui.previewCss("src/features/terminal/view/command_help.yss", "footer", @embedFile("command_help.yss"), .{ .width = .fill, .direction = .row, .align_items = .end, .gap = 12, .flex_shrink = 0, });
pub const notes = ui.previewCss("src/features/terminal/view/command_help.yss", "notes", @embedFile("command_help.yss"), .{ .flex = 1, .direction = .column, });
pub const note = ui.previewCss("src/features/terminal/view/command_help.yss", "note", @embedFile("command_help.yss"), .{ .font_size = 10, .line_height = 1.6, .color = ui.tokenRef(.color, "zw-fg-supporting"), });

//# yix-map command_help.yss
