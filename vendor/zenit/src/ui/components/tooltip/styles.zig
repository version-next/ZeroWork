/// Tooltip, style layer
///
/// Content bubble style constants and coloring functions; overlay lifecycle and mount logic in
/// mod.zig.
const core = @import("../../core.zig");
const theme = core.theme;
const Color = core.Color;
const Padding = core.Padding;

pub const max_width: f32 = 240;

/// Bubble corner radius, border.radius and hit/clip shape share same scalar
pub fn tooltipRadius(t: *const theme.ThemeTokens) f32 {
    return t.tokens.radius.control;
}

pub fn tooltipPadding(t: *const theme.ThemeTokens) Padding {
    return Padding.symmetric(t.tokens.space.space150, t.tokens.space.space200);
}

/// Bubble background, props override priority, default tooltip_bg token
pub fn tooltipContentBackground(override: ?Color, t: *const theme.ThemeTokens) Color {
    return override orelse t.tokens.color.tooltip_bg;
}

/// Bubble text, font_size parameterized by props. At most three lines; longer text ends the third
/// line in an ellipsis (a cut without one reads as the whole text).
pub fn tooltipLabelStyle(text_color_override: ?Color, font_size: f32, t: *const theme.ThemeTokens) core.TextStyle {
    return .{
        .font_size = font_size,
        .line_height = 1.4,
        .color = tooltipLabelColor(text_color_override, t),
        .wrap = .word_break,
        .max_lines = 3,
        .text_overflow = .ellipsis,
        .selectable = false,
    };
}

pub fn tooltipLabelColor(override: ?Color, t: *const theme.ThemeTokens) Color {
    return override orelse t.tokens.color.tooltip_fg;
}
