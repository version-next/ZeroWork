//! Message queue above the composer (Pencil Kaf7E A8 “Pending queue”): bg-secondary, radius 8,
//! padding 6 6 6 10, 2 apart; header 22 (list icon 12, 11/500 secondary), rows 24 (state 11
//! tertiary, text 12 primary). The buttons are native ghost xs icon Buttons.
const ui = @import("ui");
const T = @import("../../../../shared/ui/theme/app_theme.zig");
pub const row_height: f32 = 24;
/// Editing a queued message: the native Textarea (48) over a row of native xs Buttons.
pub const edit_height: f32 = 48 + 4 + 26;
pub fn root() ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .fit = .{} }, .direction = .column, .gap = 4, .flex_shrink = 0 };
}
pub fn surface() ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .fit = .{} }, .direction = .column, .gap = 2, .padding = .{ .top = 6, .bottom = 6, .left = 10, .right = 6 }, .background = T.current().surface_2, .border = .{ .width = 0, .radius = 8 }, .flex_shrink = 0 };
}
pub fn card() ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = row_height }, .direction = .row, .align_items = .center, .gap = 6, .flex_shrink = 0 };
}
pub fn row() ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = 22 }, .direction = .row, .align_items = .center, .gap = 6, .flex_shrink = 0 };
}
pub fn glyph() ui.Style {
    return .{ .width = .{ .px = 12 }, .height = .{ .px = 12 }, .flex_shrink = 0 };
}
pub fn headerText() ui.TextStyle {
    return .{ .font_size = 11, .line_height = 16.0 / 11.0, .font_weight = 500, .color = T.current().fg_2, .text_overflow = .ellipsis };
}
pub fn stateText() ui.TextStyle {
    return .{ .font_size = 11, .line_height = 16.0 / 11.0, .font_weight = 400, .color = T.current().fg_3, .text_overflow = .ellipsis };
}
/// Queue text (12 primary) and the error line (11 secondary).
pub fn queueText(secondary: bool) ui.TextStyle {
    return .{ .font_size = if (secondary) 11 else 12, .line_height = if (secondary) 16.0 / 11.0 else 18.0 / 12.0, .font_weight = 400, .color = if (secondary) T.current().fg_2 else T.current().fg_1, .text_overflow = .ellipsis };
}
// Existing consumers outside the queue retain their current style.
pub fn text(secondary: bool) ui.TextStyle {
    return .{ .font_size = if (secondary) 10 else 11.5, .line_height = if (secondary) 1.4 else 16.0 / 11.5, .font_weight = 400, .color = if (secondary) T.current().fg_2 else T.current().fg_1, .text_overflow = .ellipsis };
}
/// The transcript's “重新填写” action (ai_host; outside the queue) keeps its current look.
pub fn action() ui.StyleOverride {
    return .{ .width = .{ .fit = .{} }, .height = .{ .px = 20 }, .padding = .{ .left = 6, .right = 6 }, .font_size = 10, .corner_radius = 6, .background = ui.Color.TRANSPARENT, .text_color = T.current().fg_2, .flex_shrink = 0 };
}
