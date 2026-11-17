//! Slider style layer, track / fill / thumb style declaration (geometry parameterized by props).
//! Colors are the range_* role tokens: track, fill (thumb outline), hover, drag, thumb, disabled
//! (fill and outline) and disabled_thumb. The stepped look (SliderLook.stepped) paints a solid
//! accent thumb over a translucent fg-tertiary track, with fg-tertiary for every disabled part.
const core = @import("../../core.zig");
const Color = core.Color;
const mod = @import("mod.zig");
const SliderProps = mod.SliderProps;
const SliderLook = mod.SliderLook;

pub fn trackStyle(p: SliderProps, t: *const core.ThemeTokens) core.BoxStyle {
    return .{
        .width = .{ .grow = .{} },
        .height = .{ .px = p.track_height },
        .background = trackBackground(p.look, t),
        .border = .{ .radius = p.track_height / 2 },
    };
}

/// Stepped track: fg-tertiary at alpha 110 / 255.
pub const stepped_track_alpha: u8 = 110;

pub fn trackBackground(look: SliderLook, t: *const core.ThemeTokens) Color {
    return switch (look) {
        .default => t.tokens.color.range_track,
        .stepped => t.tokens.color.fg_tertiary.withAlpha(stepped_track_alpha),
    };
}

/// Fill (and, for the stepped look, thumb and mark dots): the accent, or the disabled color.
pub fn fillBackground(look: SliderLook, disabled: bool, accent: Color, t: *const core.ThemeTokens) Color {
    if (!disabled) return accent;
    return switch (look) {
        .default => t.tokens.color.range_disabled,
        .stepped => t.tokens.color.fg_tertiary,
    };
}

/// Mark dot (SliderProps.marks): a 4px dot centered on the mark's x (left = the value's percentage
/// of the track area, margin-left -2), 4px from the track area's top. Color applied by the runtime
/// (fillBackground).
pub fn markDotStyle(percent: f32, color: Color) core.BoxStyle {
    return .{
        .position = .absolute,
        .inset = .{ .left = .{ .percent = percent }, .top = .{ .px = 4 } },
        .margin = .{ .left = -2 },
        .width = .{ .px = 4 },
        .height = .{ .px = 4 },
        .background = color,
        .border = .{ .radius = 2 },
    };
}

/// Mark label box: 32 x 12 centered on the mark's x (margin-left -16), 12px from the track
/// area's top.
pub fn markLabelBox(percent: f32) core.BoxStyle {
    return .{
        .position = .absolute,
        .inset = .{ .left = .{ .percent = percent }, .top = .{ .px = 12 } },
        .margin = .{ .left = -16 },
        .width = .{ .px = 32 },
        .height = .{ .px = 12 },
    };
}

/// Mark label text: 9 / 12, centered, fg-tertiary, not selectable.
pub fn markLabelText(t: *const core.ThemeTokens) core.TextStyle {
    return .{
        .font_size = 9,
        .line_height = 12.0 / 9.0,
        .color = markLabelColor(t),
        .text_align = .center,
        .selectable = false,
    };
}

pub fn markLabelColor(t: *const core.ThemeTokens) Color {
    return t.tokens.color.fg_tertiary;
}

pub fn fillStyle(p: SliderProps, accent: Color, ratio: f32) core.BoxStyle {
    return .{
        .width = .{ .percent = ratio * 100 },
        .height = .{ .px = p.track_height },
        .background = accent,
        .border = .{ .radius = p.track_height / 2 },
    };
}

pub fn thumbBackground(look: SliderLook, disabled: bool, accent: Color, t: *const core.ThemeTokens) Color {
    return switch (look) {
        .default => if (disabled) t.tokens.color.range_disabled_thumb else t.tokens.color.range_thumb,
        .stepped => fillBackground(.stepped, disabled, accent, t),
    };
}

pub fn thumbStyle(p: SliderProps, disabled: bool, accent: Color, t: *const core.ThemeTokens) core.BoxStyle {
    // Stepped: a solid accent disc, no light face, no outline, no shadow.
    if (p.look == .stepped) return .{
        .position = .absolute,
        .width = .{ .px = p.thumb_size },
        .height = .{ .px = p.thumb_size },
        .background = thumbBackground(.stepped, disabled, accent, t),
        .border = .{ .overlay = true, .radius = p.thumb_size / 2, .width = 0, .color = accent },
        .shadow = null,
    };
    return .{
        .position = .absolute,
        .width = .{ .px = p.thumb_size },
        .height = .{ .px = p.thumb_size },
        .background = thumbBackground(.default, disabled, accent, t),
        .border = .{ .overlay = true, .radius = p.thumb_size / 2, .width = 1, .color = accent },
        // COMPONENTS Slider / 60: flat thumb, 1px accent outline.
        .shadow = null,
    };
}
