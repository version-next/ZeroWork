//! Native terminal grid values. Timestamp text uses its measured font width
//! plus a 12px gap, with 11px text on the terminal row baseline.
const ui = @import("ui");
const theme = @import("../../../shared/ui/theme/app_theme.zig");
// Final workspace CSS: .terminal-scroll and .pane-group .terminal-scroll.
/// Island B v3 terminal insets (Pencil `hMIT7` / `i3Zme8`): a terminal that
/// fills the island uses [10, 16, 12, 16]; a split pane under its header uses
/// [2, 12, 10, 12].
pub fn contentPadding(grouped: bool) ui.Padding {
    return if (grouped) .{ .top = 2, .right = 12, .bottom = 10, .left = 12 } else .{ .top = 10, .right = 16, .bottom = 12, .left = 16 };
}
/// Pencil CC3v4 只读历史 timestamp gutter: 9.5px fg_secondary, gap 8 before the line.
pub const timestamp_gap: f32 = 8;
pub const timestamp_x: f32 = 0;
pub const timestamp_y: f32 = 0;
pub const timestamp_size: f32 = 9.5;
pub const timestamp_height: f32 = 22;
pub const body_size: f32 = 14;
pub const body_height: f32 = 22;

/// Match the timestamp painter: regular 9.5px text in the selected terminal
/// family, without the terminal body's forced cell advance. Digits are tabular.
pub fn timestampWidth(cx: *ui.Cx, family_id: u16) f32 {
    const sample = "00:00:00";
    if (cx.text.font_props_measure_fn) |measure| if (cx.text.font_resolve_ctx) |context| {
        if (measure(context, sample, timestamp_size, 400, false, family_id == 0, family_id, false, 0)) |width| return width;
    };
    const run = cx.text.shapeText(.{ .text = sample, .font_family = "system", .font_family_id = family_id, .font_size = timestamp_size, .font_weight = 400, .use_monospace = family_id == 0 }) catch return sample.len * timestamp_size * 0.6;
    return run.total_advance;
}

pub fn surface(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .fill(), .direction = .column, .overflow = .hidden, .cursor = .text };
}
/// Pencil N9ryVa "AI control" (QT5FH): a 40 high bar across the foot of the
/// exact terminal pane, 1pt hairline on top, padding [0, 12], gap 8. It overlays
/// the canvas so taking control never resizes the PTY grid.
pub const ai_control_height: f32 = 40;
pub fn aiControlTag(_: *const ui.ThemeTokens) ui.BoxStyle {
    const c = theme.current();
    return .{ .position = .absolute, .inset = .{ .left = .{ .px = 0 }, .bottom = .{ .px = 0 } }, .width = .fill(), .height = .{ .px = ai_control_height }, .direction = .row, .align_items = .center, .gap = 8, .padding = .{ .left = 12, .right = 12 }, .background = c.surface_1, .border = .{ .width = 0, .color = c.border, .side_widths = .{ 1, 0, 0, 0 } }, .z_index = 9, .hit_behavior = .@"opaque", .flex_shrink = 0 };
}
/// "AI 控制中 · 只读" 12/500 accent.
pub fn aiControlText(_: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 12, .font_weight = 500, .line_height = 18.0 / 12.0, .color = theme.current().accent, .selectable = false };
}
/// "你的输入不会发送到这个终端" 11.5 fg_secondary.
pub fn aiControlDetail(_: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 11.5, .line_height = 18.0 / 11.5, .color = theme.current().fg_2, .selectable = false, .text_overflow = .ellipsis };
}
/// 接管: zenit Button secondary sm (W:JTyJu): 24 high, padding [0, 12], radius 6, hairline border, label 13/500.
pub fn aiControlButton() ui.StyleOverride {
    return .{ .height = .{ .px = 24 }, .padding = .{ .left = 12, .right = 12 }, .font_size = 13, .font_weight = 500, .corner_radius = 6, .flex_shrink = 0 };
}
pub fn row(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .position = .absolute, .height = .{ .px = body_height }, .flex_shrink = 0 };
}
pub fn timestamp(t: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = ui.arb.px(timestamp_size), .line_height = timestamp_height / timestamp_size, .color = t.tokens.color.fg_secondary, .use_monospace_font = true, .text_align = .start };
}
pub fn inputHighlight(t: *const ui.ThemeTokens) ui.Color {
    return t.tokens.color.accent.withAlpha(15);
}
pub fn selection(t: *const ui.ThemeTokens) ui.Color {
    return t.tokens.color.accent.withAlpha(55);
}

// Bridge copied states 236:563266 / 236:563499 / 236:563732. Insets are
// relative to the owning terminal pane, not the window or the active tab.
pub const message_duration_ns = 3 * @import("std").time.ns_per_s;
pub const message_inset: f32 = 12;
pub const message_width: f32 = 340;
pub const message_height: f32 = 48;
pub const message_icon_size: f32 = 16;
pub const message_close_size: f32 = 20;

pub fn copiedMessage(_: *const ui.ThemeTokens) ui.BoxStyle {
    const c = theme.current();
    return .{ .position = .absolute, .inset = .{ .right = .{ .px = message_inset }, .top = .{ .px = message_inset } }, .width = .{ .px = message_width }, .height = .{ .px = message_height }, .direction = .row, .align_items = .center, .gap = 4, .padding = ui.Padding.all(message_inset), .background = c.overlay, .border = .{ .radius = 14 }, .hit_behavior = .@"opaque", .z_index = 8, .flex_shrink = 0 };
}
pub fn errorMessage(x: f32, width: f32, y: f32, height: f32, background: ui.Color) ui.BoxStyle {
    return .{ .position = .absolute, .inset = .{ .left = .{ .px = x }, .top = .{ .px = y } }, .width = .{ .px = width }, .height = .{ .px = height }, .direction = .row, .align_items = .center, .gap = 0, .padding = .ZERO, .background = background.withAlpha(@min(background.a, 64)), .border = .{ .radius = 0 }, .hit_behavior = .pass_through, .z_index = 8, .flex_shrink = 0 };
}
pub fn copiedText(_: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 11.5, .font_weight = 500, .line_height = 18.0 / 11.5, .color = theme.current().fg_1, .selectable = false };
}
pub fn messageTextBox(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .position = .relative, .width = .fill(), .height = .{ .px = 18 }, .flex = 1, .min_width = 0, .overflow = .hidden };
}
pub fn messageClose(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .{ .px = message_close_size }, .height = .{ .px = message_close_size }, .padding = .ZERO, .gap = 0, .align_items = .center, .justify = .center, .background = ui.Color.TRANSPARENT, .border = .{ .radius = 7 }, .flex_shrink = 0 };
}
pub fn messageCloseHover() ui.BoxStyle {
    return .{ .background = theme.states().hover };
}
pub fn messageIcon() ui.Style {
    return .{ .width = .{ .px = message_icon_size }, .height = .{ .px = message_icon_size }, .flex_shrink = 0 };
}

/// In-flow history controls. Pencil CC3v4 "Playback": a 44 high bar at the
/// foot of the replay pane, padding [0, 12], gap 10, 1pt hairline on top.
pub fn historyCard(_: *const ui.ThemeTokens) ui.BoxStyle {
    const c = theme.current();
    return .{
        .height = .{ .px = 44 },
        .width = .fill(),
        .flex_shrink = 0,
        .direction = .row,
        .align_items = .center,
        .gap = 10,
        .padding = .{ .left = 12, .right = 12 },
        // On the pane island: a first-layer card.
        .background = @import("../../../shared/ui/styles/surface_material.zig").fill(c.surface_1, .canvas),
        .border = .{ .width = 0, .color = c.border, .radius = 0, .side_widths = .{ 1, 0, 0, 0 } },
    };
}
