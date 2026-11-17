//! 图片预览对话框（Pencil O10 `mk6IS` / `qf2nQ`，ai-redesign-c）：原生 `W.Modal`（工作区 78%），正文三段——
//! 头部 36（标题 13/600 · 原生 ghost sm 关闭）、图片区（bg-secondary，图片按比例缩放居中）、底栏（12 16：来源
//! 说明 11 fg-secondary · 原生 secondary sm “移除图片” · 原生 primary sm “保留图片”）。这里只写布局与正文文字。
const ui = @import("ui");

pub const header_height: f32 = 36;
pub const footer_height: f32 = 48;

pub fn body() ui.BoxStyle {
    return .{ .width = .fill(), .height = .fill(), .padding = .{}, .gap = 0, .direction = .column, .min_height = 0 };
}
pub fn header(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = header_height }, .flex_shrink = 0, .direction = .row, .align_items = .center, .gap = 6, .padding = .{ .left = 16, .right = 8 } };
}
pub fn title(t: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 13, .font_weight = 600, .line_height = 1.5, .color = t.tokens.color.fg_primary, .text_overflow = .ellipsis, .selectable = false };
}
pub fn fill() ui.BoxStyle {
    return .{ .width = .fill(), .min_width = 0, .flex = 1 };
}
/// The image well: bg-secondary, the raster centered.
pub fn well(t: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .fill(), .flex = 1, .min_width = 0, .min_height = 0, .align_items = .center, .justify = .center, .overflow = .hidden, .background = t.tokens.color.bg_secondary };
}
pub fn footer(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = footer_height }, .flex_shrink = 0, .direction = .row, .align_items = .center, .gap = 8, .padding = .{ .left = 16, .right = 16, .top = 12, .bottom = 12 } };
}
pub fn meta(t: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 11, .line_height = 1.5, .color = t.tokens.color.fg_secondary, .text_overflow = .ellipsis, .wrap = .none };
}
