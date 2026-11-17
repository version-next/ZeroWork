//! On-demand inventory approval, reusing the native host approval surface.
const ui = @import("ui");
const theme = @import("../../../../shared/ui/theme/app_theme.zig");
const approval = @import("ai_tool_approval_styles.zig");
pub const ButtonStyle = approval.ButtonStyle;
pub fn root(tokens: *const ui.ThemeTokens) ui.BoxStyle {
    var value = approval.panel(tokens);
    value.height = .{ .fit = .{} };
    value.min_width = 0;
    value.gap = 8;
    // The grant card declares its own fill: a first-layer card on the assistant pane.
    value.background = @import("../../../../shared/ui/styles/surface_material.zig").fill(theme.popupAction(), .canvas);
    return value;
}
pub fn header(tokens: *const ui.ThemeTokens) ui.BoxStyle {
    var value = approval.header(tokens);
    value.margin = .{};
    return value;
}
pub const title = approval.title;
pub fn text(_: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 12, .line_height = 18.0 / 12.0, .color = theme.current().fg_2, .wrap = .word };
}
pub fn secondary(_: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 11, .line_height = 16.0 / 11.0, .color = theme.current().fg_2, .wrap = .word };
}
pub fn actions(tokens: *const ui.ThemeTokens) ui.BoxStyle {
    var value = approval.footer(tokens);
    value.height = .{ .fit = .{} };
    value.min_height = 26.5;
    value.flex_wrap = .no_wrap;
    return value;
}

pub fn hover() ?ButtonStyle {
    return .{ .background = theme.popupSelection() };
}
