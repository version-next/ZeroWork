//! V3 transfer confirmation: 480x398, explicit title/body/footer hierarchy.
const ui = @import("ui");
pub const theme = @import("../../../shared/ui/theme/app_theme.zig");
pub fn root() ui.BoxStyle {
    // Modal body layout only; the panel surface is zenit Modal's default.
    return .{ .width = .fill(), .height = .{ .px = 398 }, .direction = .column, .gap = 0, .padding = .ZERO, .flex_shrink = 0 };
}
pub fn row(height: f32, gap: f32) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = height }, .direction = .row, .align_items = .center, .gap = gap, .min_width = 0, .flex_shrink = 0 };
}
pub fn text(size: f32, weight: u16, secondary: bool) ui.TextStyle {
    return .{ .font_size = size, .font_weight = weight, .line_height = 1.4, .color = if (secondary) theme.current().fg_2 else theme.current().fg_1, .text_overflow = .ellipsis };
}
pub fn header() ui.BoxStyle {
    var s = row(72, 12);
    s.padding = .{ .left = 20, .right = 16, .top = 16, .bottom = 12 };
    return s;
}
pub fn body() ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = 264 }, .direction = .column, .gap = 12, .padding = .{ .left = 20, .right = 20, .bottom = 16 }, .flex_shrink = 0 };
}
pub fn summary() ui.BoxStyle {
    var s = row(56, 10);
    s.padding = ui.Padding.all(12);
    s.background = theme.popupInset();
    s.border = .{ .radius = 8 };
    return s;
}
pub fn field() ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = 52 }, .direction = .column, .gap = 4, .min_width = 0, .flex_shrink = 0 };
}
pub fn path() ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = 32 }, .padding = .{ .left = 10, .right = 10, .top = 8, .bottom = 8 }, .background = theme.popupInset(), .border = .{ .radius = 8 }, .min_width = 0, .flex_shrink = 0, .overflow = .hidden, .overflow_hidden = true };
}
pub fn footer() ui.BoxStyle {
    var s = row(62, 8);
    s.padding = .{ .left = 20, .right = 20, .top = 14, .bottom = 14 };
    return s;
}
