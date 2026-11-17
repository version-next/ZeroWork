//! Bridge V2 configuration panels: 358:1367616 / 358:1368844 / 358:1369644.
const ui = @import("ui");
pub const theme = @import("../../../../shared/ui/theme/app_theme.zig");
pub const width: f32 = 480;
pub const panel_height: f32 = 650;
// Header30 + footer30 + two 12px gaps + top18/bottom18.
pub const chrome_height: f32 = 120;
pub const inset: f32 = 22;
/// Modal dialog geometry only: the panel surface is zenit Modal's default.
pub fn panel() ui.BoxStyle {
    return .{ .width = .{ .px = width }, .direction = .column, .gap = 0, .flex_shrink = 0 };
}
pub fn row(height: f32) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = height }, .direction = .row, .gap = 6, .align_items = .center, .flex_shrink = 0 };
}
pub fn column() ui.BoxStyle {
    return .{ .width = .fill(), .direction = .column, .gap = 6, .flex_shrink = 0, .min_width = 0 };
}
pub fn field() ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = 52 }, .direction = .column, .gap = 4, .flex_shrink = 0, .min_width = 0 };
}
pub fn input() ui.BoxStyle {
    // Island B v3: the field frame (border, focus, invalid) belongs to zenit's
    // ControlShell (Pencil Input/focus `W:AdAHY`); only geometry and the inset fill are set.
    return .{ .width = .fill(), .height = .{ .px = 32 }, .padding = .{ .left = 10, .right = 10 }, .background = theme.popupInset(), .corner_radius = 8, .flex_shrink = 0 };
}
pub fn action(w: f32) ui.BoxStyle {
    return .{ .width = .{ .px = w }, .height = .{ .px = 30 }, .padding = .{}, .background = theme.popupAction(), .border = .{ .radius = 8 }, .text_color = theme.current().fg_2, .font_size = 12, .font_weight = 500, .flex_shrink = 0 };
}
pub fn text(size: f32, weight: u16, secondary: bool) ui.TextStyle {
    return .{ .font_size = size, .font_weight = weight, .line_height = (if (size == 13) @as(f32, 20) else @as(f32, 16)) / size, .color = if (secondary) theme.current().fg_2 else theme.current().fg_1, .selectable = false, .text_overflow = .ellipsis };
}
pub const repaint = @import("../../quick_connect/view/quick_connect_styles.zig").repaint;

pub fn modeCard(selected: bool) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = 54 }, .padding = ui.Padding.all(10), .background = if (selected) theme.popupSelection() else theme.popupInset(), .border = .{ .radius = 9 }, .flex_shrink = 0, .gap = 0 };
}
