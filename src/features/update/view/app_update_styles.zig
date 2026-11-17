//! Application update styles. Island B v3 更新确认 (`irIDr` › `FGZW3`):
//! 460 wide, padding 20, gap 12, radius 12, hairline frame; work list on the
//! rest surface (padding [4, 12], radius 8, rows 34); md buttons (32, radius 6).
const ui = @import("ui");
pub const theme = @import("../../../shared/ui/theme/app_theme.zig");
pub const width: f32 = 460;
pub fn dialog(viewport_width: f32, height: f32, target: f32) ui.BoxStyle {
    // Geometry only: the panel surface (background, border, radius, shadow)
    // is zenit Modal's default.
    return .{ .width = .{ .px = @min(width, @max(1, viewport_width - 32)) }, .height = .{ .px = @min(target, @max(1, height - 32)) }, .padding = .ZERO };
}
pub const Metrics = struct { padding: f32, body_top: f32, summary_gap: f32, summary_padding: f32, row_height: f32, footer_gap: f32 };
pub fn metrics(height: f32) Metrics {
    return if (height <= 600)
        .{ .padding = 16, .body_top = 10, .summary_gap = 10, .summary_padding = 12, .row_height = 30, .footer_gap = 12 }
    else
        .{ .padding = 20, .body_top = 12, .summary_gap = 12, .summary_padding = 12, .row_height = 34, .footer_gap = 12 };
}
pub fn body(height: f32) ui.BoxStyle {
    // The zenit Modal body declares gap 16; spacing here comes from the explicit margins.
    return .{ .width = .fill(), .height = .fill(), .direction = .column, .gap = 0, .padding = .all(metrics(height).padding) };
}
pub fn text(size: f32, line: f32, weight: u16) ui.TextStyle {
    return .{ .font_size = size, .line_height = line / size, .font_weight = weight, .color = theme.current().fg_1, .wrap = .word, .selectable = false };
}
/// Buttons: primary/danger md (`W:nVR8K`) or ghost md with a hairline (`W:Gpz48`).
pub fn button(primary: bool, danger: bool, button_width: f32) ui.BoxStyle {
    const c = theme.current();
    return .{ .width = .{ .px = button_width }, .height = .{ .px = 32 }, .padding = .{ .left = 12, .right = 12 }, .gap = 0, .font_size = 13, .font_weight = 500, .text_color = if (primary) ui.Color.WHITE else c.fg_1, .background = if (danger) c.action_danger else if (primary) c.action_accent else ui.Color.TRANSPARENT, .border = .{ .width = if (primary) 0 else 1, .color = c.border, .radius = 6 }, .flex_shrink = 0 };
}
/// Work list (`kHUsn`): padding [4, 12], radius 8, rest surface.
pub fn summary(height: f32) ui.BoxStyle {
    const m = metrics(height);
    return .{ .width = .fill(), .height = .{ .fit = .{} }, .direction = .column, .margin = .{ .top = m.summary_gap, .bottom = m.summary_gap }, .padding = .{ .left = m.summary_padding, .right = m.summary_padding, .top = 4, .bottom = 4 }, .background = theme.current().surface_2, .border = .{ .width = 0, .radius = 8 }, .flex_shrink = 0 };
}

pub fn helpButton() ui.BoxStyle {
    return .{ .width = .{ .px = 24 }, .height = .{ .px = 24 }, .padding = .ZERO, .flex_shrink = 0 };
}
pub fn progress() ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = 18 }, .margin = .{ .top = 8 }, .flex_shrink = 0 };
}
