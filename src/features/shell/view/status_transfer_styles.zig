//! Bottom-bar transfer display. The existing popover is owned by its host.
const ui = @import("ui");
pub const theme = @import("../../../shared/ui/theme/app_theme.zig");
pub const ButtonStyle = ui.StyleOverride;
pub const preferred_width: f32 = 280;
pub const completed_width: f32 = 220;
/// Narrowest the running ticker gets when the status bar runs out of room.
pub const minimum_width: f32 = 200;
/// Idle: as wide as its label. Running / finished: its preferred width, giving way (down to
/// `minimum_width`) when the status bar is too narrow for everything in it.
pub fn button(phase: anytype) ButtonStyle {
    const idle = phase == .idle;
    const width: f32 = if (phase == .running) preferred_width else completed_width;
    return .{ .width = if (idle) .{ .fit = .{} } else .{ .px = width }, .min_width = if (idle) null else @min(minimum_width, width), .height = .{ .px = 26 }, .padding = .{}, .gap = 0, .background = if (idle) ui.Color.TRANSPARENT else theme.popupInset(), .corner_radius = 7, .border_width = 0, .flex_shrink = if (idle) 0 else 1 };
}
pub fn hover() ButtonStyle {
    return .{ .background = theme.states().hover };
}
pub fn row(idle: bool) ui.BoxStyle {
    return .{ .width = if (idle) .{ .fit = .{} } else .fill(), .height = .{ .px = 26 }, .direction = .row, .align_items = .center, .gap = 4, .padding = .{ .left = 7, .right = 7 }, .min_width = 0 };
}
pub fn icon() ui.Style {
    return .{ .width = .{ .px = 14 }, .height = .{ .px = 14 }, .flex_shrink = 0 };
}
pub fn label(w: f32) ui.BoxStyle {
    return .{ .width = .{ .px = w }, .height = .{ .px = 16 }, .flex_shrink = 0, .overflow_hidden = true };
}
pub fn rateLabel() ui.BoxStyle {
    return .{ .width = .{ .fit = .{} }, .height = .{ .px = 16 }, .flex_shrink = 0 };
}
pub fn text(primary: bool) ui.TextStyle {
    return .{ .font_size = if (primary) 10.5 else 10, .font_weight = 400, .line_height = if (primary) 16.0 / 10.5 else 1.6, .color = if (primary) theme.current().fg_1 else theme.current().fg_2, .text_overflow = if (primary) .ellipsis_smart else .ellipsis, .selectable = false, .use_monospace_font = !primary, .text_align = if (primary) .start else .end };
}
pub fn badge() ui.BoxStyle {
    return .{ .width = .{ .px = 18 }, .height = .{ .px = 18 }, .direction = .row, .align_items = .center, .justify = .center, .flex_shrink = 0, .background = theme.current().accent.withAlpha(32), .border = .{ .radius = 9 } };
}
/// Positions the track under the row across the whole button, 7 in from each side.
pub fn rail() ui.BoxStyle {
    return .{ .position = .absolute, .inset = .{ .left = .{ .px = 0 }, .top = .{ .px = 23 } }, .width = .fill(), .height = .{ .px = 2 }, .padding = .{ .left = 7, .right = 7 }, .hit_behavior = .pass_through };
}
pub fn track() ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = 2 }, .background = theme.current().fg_2.withAlpha(46), .border = .{ .radius = 1 } };
}
pub fn fill(fraction: f32) ui.BoxStyle {
    return .{ .width = .{ .percent = fraction * 100 }, .height = .{ .px = 2 }, .background = theme.current().accent, .border = .{ .radius = 1 } };
}
