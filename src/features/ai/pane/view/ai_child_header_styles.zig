//! 子智能体对话框头部（Pencil O9 `b0PqnJ` / `z99eF`，ai-redesign-c）：与统一外框 float_chrome 同规格——
//! 图标 14（accent）· 标题 12/600 fg-primary · 状态原生 `W.Tag` sm · 副标题 11 fg-secondary（先截断）· 弹性空白 ·
//! 原生 ghost sm 图标按钮 24。对话框里没有拖动把手，头部 36 高、内边距 0 8 0 16（O9 Header）。这里只写布局与
//! 正文文字，按钮 / 标签都是原生默认外观。
const ui = @import("ui");

pub const height: f32 = 36;

pub fn bar(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .min_width = 0, .height = .{ .px = height }, .flex_shrink = 0, .direction = .row, .align_items = .center, .gap = 6, .padding = .{ .left = 16, .right = 8 } };
}
pub fn icon() ui.Style {
    return .{ .width = .{ .px = 14 }, .height = .{ .px = 14 }, .flex_shrink = 0 };
}
/// Title: the last to give way (float_chrome `title_box`: almost no shrink weight).
pub fn title(t: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 12, .font_weight = 600, .line_height = 1.5, .color = t.tokens.color.fg_primary, .wrap = .none, .text_overflow = .ellipsis, .selectable = false };
}
pub fn titleBox() ui.BoxStyle {
    return .{ .width = .{ .fit = .{} }, .min_width = 0, .flex_shrink = 0.01, .overflow_hidden = true };
}
/// Subtitle (父对话 · 上下文): gives way first.
pub fn subtitle(t: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 11, .line_height = 1.5, .color = t.tokens.color.fg_secondary, .wrap = .none, .text_overflow = .ellipsis, .selectable = false };
}
pub fn subtitleBox() ui.BoxStyle {
    return .{ .width = .{ .fit = .{} }, .max_width = 240, .min_width = 0, .flex_shrink = 1, .overflow_hidden = true };
}
/// The meta group (status Tag · subtitle) the narrow-header rule hides last-but-one.
pub fn meta(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .{ .fit = .{} }, .min_width = 0, .max_width = 320, .flex_shrink = 1, .direction = .row, .align_items = .center, .gap = 6, .overflow = .hidden };
}
