//! The host PTY execution row on a step-group rail (Pencil Kaf7E A6): the same 24 row and one
//! output well (bg_secondary, radius 8, mono 12 / 1.55) as every step; no card plate.
const ui = @import("ui");
const theme = @import("../../../../shared/ui/theme/app_theme.zig");
pub const ButtonStyle = ui.StyleOverride;
pub fn card(t: *const ui.ThemeTokens) ui.BoxStyle {
    return @import("ai_tool_results_styles.zig").card(t);
}
pub fn title(t: *const ui.ThemeTokens) ui.TextStyle {
    return @import("ai_tool_results_styles.zig").title(t);
}
pub fn body(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .fit = .{ .max = 150 } }, .min_width = 0, .flex_shrink = 0 };
}
pub fn content(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .fit = .{} }, .direction = .column, .gap = 6, .padding = .{ .left = @import("ai_tool_results_styles.zig").detail_inset, .top = 2, .bottom = 4 }, .flex_shrink = 0 };
}
pub fn text(t: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 12, .line_height = 1.5, .wrap = .word, .color = t.tokens.color.fg_secondary };
}
pub fn metadata(t: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 11, .line_height = 1.5, .wrap = .word, .color = t.tokens.color.fg_tertiary };
}
pub fn summary(t: *const ui.ThemeTokens) ui.TextStyle {
    return @import("ai_tool_results_styles.zig").stepArgs(t);
}
pub fn warning(t: *const ui.ThemeTokens) ui.TextStyle {
    var style = text(t);
    style.color = t.tokens.color.warning;
    return style;
}
pub fn identity(tokens: *const ui.ThemeTokens) ui.TextStyle {
    var style = metadata(tokens);
    style.use_monospace_font = true;
    return style;
}
pub fn mono(t: *const ui.ThemeTokens) ui.TextStyle {
    // The code-block spec: mono 12 / 1.55.
    return .{ .font_size = 12, .line_height = 1.55, .wrap = .word, .use_monospace_font = true, .color = t.tokens.color.fg_primary };
}
pub fn output(t: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .min_width = 0, .flex_shrink = 0, .background = t.tokens.color.bg_secondary, .corner_radius = 8 };
}
pub fn footer(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .fit = .{} }, .min_height = 28, .direction = .row, .align_items = .center, .flex_wrap = .wrap, .gap = 6, .padding = .{ .left = @import("ai_tool_results_styles.zig").detail_inset }, .flex_shrink = 0 };
}
pub fn action() ButtonStyle {
    // Pencil g0gO7 "Actions" (itWiC): 复制输出 / 复制命令 are bare accent text links
    // (12pt, no fill); a 28pt hit row and 6pt radius keep the hover state.
    return .{ .width = .{ .fit = .{} }, .height = .{ .px = 28 }, .padding = .{ .left = 6, .right = 6, .top = 4, .bottom = 4 }, .font_size = 12, .font_weight = 400, .background = ui.Color.TRANSPARENT, .text_color = actionInk(), .border_width = 0, .corner_radius = 6, .flex_shrink = 0 };
}
/// Accent link ink, nudged to stay >= 4.5:1 on the execution card on every palette.
pub fn actionInk() ui.Color {
    const c = theme.current();
    return theme.patchInk(c.accent_ink, &.{theme.patchPaint(theme.popupAction(), c.overlay.withAlpha(255))});
}
pub fn iconButton() ButtonStyle {
    return .{ .width = .{ .px = 24 }, .height = .{ .px = 24 }, .padding = .{}, .background = ui.Color.TRANSPARENT, .corner_radius = 7, .flex_shrink = 0 };
}
