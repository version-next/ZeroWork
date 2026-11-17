const ui = @import("ui");
const theme = @import("../../../shared/ui/theme/app_theme.zig");
pub const gap: f32 = 4;
/// Island B v3 split panes (Pencil `i3Zme8`): radius 8 inside the island's 4pt inset.
pub const pane_radius: f32 = 8;
pub fn root(vertical: bool) ui.BoxStyle {
    return .{ .width = .fill(), .height = .fill(), .direction = if (vertical) .column else .row, .gap = gap, .flex_shrink = 0 };
}
pub fn pane() ui.BoxStyle {
    return .{ .width = .fill(), .height = .fill(), .direction = .column, .background = theme.current().terminal, .border = .{ .radius = pane_radius }, .overflow_hidden = true };
}
pub fn tab(active: bool) ui.BoxStyle {
    return .{ .width = .{ .px = 148 }, .height = .{ .px = 32 }, .flex_shrink = 0, .direction = .row, .align_items = .center, .gap = 6, .padding = .{ .left = 10, .right = 4 }, .background = if (active) theme.current().surface_2 else theme.current().surface_1, .border = .{ .radius = 8 } };
}

// The existing 4pt gutter becomes an interactive native separator.
pub fn separator(vertical: bool) ui.BoxStyle {
    return .{ .width = if (vertical) .fill() else .{ .px = gap }, .height = if (vertical) .{ .px = gap } else .fill(), .flex_shrink = 0, .cursor = if (vertical) .ns_resize else .ew_resize, .hit_behavior = .@"opaque" };
}
// The pane header itself is `pane_header.yix` / `pane_header.yss` (W-5 收回).
