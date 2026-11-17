const ui = @import("ui");
pub const theme = @import("../../../shared/ui/theme/app_theme.zig");
pub const width: f32 = 344;
pub const maximum_height: f32 = 360;
pub const fixed_height: f32 = 108;
pub fn panel() ui.BoxStyle {
    return .{ .position = .absolute, .width = .{ .px = width }, .height = .{ .px = maximum_height }, .direction = .column, .padding = ui.Padding.all(14), .gap = 10, .hit_behavior = .@"opaque" };
}
pub fn row() ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = 32 }, .direction = .row, .align_items = .center, .gap = 8, .flex_shrink = 0 };
}
pub fn header() ui.BoxStyle {
    var style = row();
    style.height = .{ .px = 28 };
    return style;
}
pub fn body() ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .fit = .{} }, .direction = .column, .gap = 10, .flex_shrink = 0 };
}
pub fn member() ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = 52 }, .direction = .row, .align_items = .center, .gap = 9, .padding = ui.Padding.all(10), .background = theme.popupInset(), .border = .{ .radius = 8 }, .flex_shrink = 0 };
}
pub fn text(strong: bool) ui.TextStyle {
    return .{ .font_size = if (strong) 12 else 10, .font_weight = if (strong) 500 else 400, .line_height = if (strong) 1.5 else 1.6, .color = if (strong) theme.current().fg_1 else theme.current().fg_2, .text_overflow = .ellipsis };
}
pub fn note() ui.TextStyle {
    var style = text(false);
    style.wrap = .word;
    style.text_overflow = .clip;
    return style;
}
pub fn close() ui.StyleOverride {
    return .{ .width = .{ .px = 22 }, .height = .{ .px = 22 }, .padding = .{}, .background = ui.Color.TRANSPARENT, .text_color = theme.current().fg_1, .font_size = 11, .corner_radius = 8, .border_width = 0 };
}
pub fn controlHover() ui.StyleOverride {
    return .{ .background = theme.states().hover, .text_color = theme.current().fg_1 };
}

pub fn titleText(_: *const ui.ThemeTokens) ui.TextStyle {
    return text(true);
}
pub fn secondaryText(_: *const ui.ThemeTokens) ui.TextStyle {
    return text(false);
}
pub fn noteText(_: *const ui.ThemeTokens) ui.TextStyle {
    return note();
}
pub fn memberPaint(_: *const ui.ThemeTokens) ui.BoxStyle {
    return member();
}
pub fn memberName(_: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 11, .line_height = 1.5, .font_weight = 500, .color = theme.current().fg_1, .text_overflow = .ellipsis };
}
pub fn memberEndpoint(_: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 9, .line_height = 1.5, .color = theme.current().fg_2, .text_overflow = .ellipsis };
}
pub fn memberState(_: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 8, .color = theme.current().fg_2 };
}
pub fn notePaint(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .fit = .{} }, .padding = .{ .left = 10, .right = 10, .top = 9, .bottom = 9 }, .background = theme.popupInset(), .border = .{ .radius = 8 }, .flex_shrink = 0 };
}
