//! Figma 321:878950: four rows yield 520x162, viewport 496x104 at (12,46).
//! Event rows are at least 20px high with 8px gaps; long content caps at 184px.
const ui = @import("ui");
const theme = @import("../../../shared/ui/theme/app_theme.zig");
/// Native Popover geometry (props): 520 wide, never taller than 242.
pub const width: f32 = 520;
pub const max_height: f32 = 242;
/// Event rows scroll past 184; reserved = header row 28 + gap 6 + the content column's 12 + 12 inset.
pub const viewport_max: f32 = 184;
pub const reserved: f32 = 58;
/// Own zero-size box holding the manual popover's trigger wrapper.
pub fn anchor(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .position = .absolute, .width = .{ .px = 0 }, .height = .{ .px = 0 } };
}
/// The panel's content column. zenit's Popover panel has no padding of its own (its content decides),
/// so this own column keeps the 12 point inset of the design.
pub fn body(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .fit = .{} }, .direction = .column, .gap = 0, .padding = ui.Padding.all(12) };
}
pub fn row(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = 28 }, .direction = .row, .align_items = .center, .gap = 6, .flex_shrink = 0 };
}
pub fn viewport(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = 184 }, .margin = .{ .top = 6 }, .flex_shrink = 0 };
}
pub fn title(_: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 13, .font_weight = 700, .line_height = 20.0 / 13.0, .color = theme.current().fg_1 };
}
pub fn entries(_: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 10.5, .line_height = 16.0 / 10.5, .use_monospace_font = true, .wrap = .char, .color = theme.current().fg_1 };
}
pub fn eventList(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .fit = .{} }, .direction = .column, .gap = 8, .flex_shrink = 0 };
}
pub fn eventRow(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .fit = .{} }, .min_height = 20, .flex_shrink = 0 };
}
