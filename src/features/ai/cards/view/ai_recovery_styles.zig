//! V3 ap-card recovery: one 9px shell contains header, reason and action footer.
const ui = @import("ui");
const theme = @import("../../../../shared/ui/theme/app_theme.zig");
pub fn root(tokens: *const ui.ThemeTokens) ui.BoxStyle {
    var value = @import("ai_tool_results_styles.zig").card(tokens);
    value.min_width = 0;
    value.padding = ui.Padding.all(1);
    return value;
}
pub fn row(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .fit = .{} }, .min_height = 34, .direction = .row, .align_items = .center, .gap = 6, .padding = .{ .left = 12, .right = 10, .top = 4, .bottom = 4 }, .flex_shrink = 0 };
}
pub fn text(_: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 11, .line_height = 18.0 / 11.0, .color = theme.current().fg_2, .wrap = .word };
}
pub fn warning(_: *const ui.ThemeTokens) ui.TextStyle {
    var value = text(undefined);
    value.color = theme.current().danger_ink;
    value.font_size = 12;
    value.font_weight = 500;
    value.line_height = 1.65;
    return value;
}
pub fn statusRow(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = 32 }, .direction = .row, .align_items = .center, .gap = 6, .padding = .{ .left = 10, .right = 10 }, .flex_shrink = 0 };
}
pub fn body(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .fit = .{} }, .padding = .{ .left = 12, .right = 12, .top = 4, .bottom = 8 }, .flex_shrink = 0, .min_width = 0 };
}
pub fn title(_: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 11.5, .font_weight = 500, .line_height = 16.0 / 11.5, .color = theme.current().fg_1 };
}
pub fn summary(_: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 10.5, .line_height = 16.0 / 10.5, .color = theme.current().fg_2, .text_overflow = .ellipsis };
}
pub fn hint(_: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 10.5, .line_height = 16.0 / 10.5, .color = theme.current().fg_2, .wrap = .word };
}
pub fn details(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .min_width = 0, .height = .{ .fit = .{ .max = 120 } }, .flex_shrink = 0 };
}
pub fn attemptsRow(_: *const ui.ThemeTokens) ui.BoxStyle {
    var value = row(undefined);
    value.height = .{ .px = 26 };
    return value;
}
pub fn badge(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .{ .px = 126 }, .height = .{ .px = 22 }, .direction = .row, .align_items = .center, .padding = .{ .left = 8, .right = 8 }, .background = theme.popupAction(), .border = .{ .radius = 8 }, .flex_shrink = 0 };
}
pub fn icon() ui.Style {
    return .{ .width = .{ .px = 14 }, .height = .{ .px = 14 }, .flex_shrink = 0 };
}

// ── Pencil Kaf7E A9: inside the native danger Alert ──
/// Hints under the actions: 11 fg_tertiary.
pub fn recoveryHint(t: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 11, .line_height = 1.5, .wrap = .word, .color = t.tokens.color.fg_tertiary };
}
/// The folded raw diagnostic: mono 11 fg_secondary.
pub fn detailText(t: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 11, .line_height = 1.5, .wrap = .word_break, .use_monospace_font = true, .color = t.tokens.color.fg_secondary };
}
