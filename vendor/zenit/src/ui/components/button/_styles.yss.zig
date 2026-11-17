// GENERATED FILE, do not edit: generated from styles.yss; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! Button styles. Frame, tone, geometry and interaction states are ControlShell's
//! (control_shell/styles.yss, glyph icon fit); here: the root style Button merges into the shell's
//! tone (block sizing, centering, caller overrides), the label tier, the glyph and the loading ring.
//! Label, glyph and ring declare no color: they inherit the shell's foreground (currentColor)
//! through every state. View in button.yix.
const ui = @import("../../ui.zig");
const core = @import("../../core.zig");
const Color = core.Color;
const StyleOverride = core.StyleOverride;
const ConditionalStyle = core.ConditionalStyle;
const ThemeTokens = core.theme.ThemeTokens;
const shell = @import("../control_shell/mod.zig");
const spinner = @import("../spinner/_styles.yss.zig");

pub const ButtonVariant = shell.ControlVariant;
pub const ButtonSize = shell.ControlSize;

/// Which side of the label the glyph sits on (Button `iconPosition`).
pub const IconPosition = enum { leading, trailing };

/// Button's root on the shell, merged per state into the tone (ControlShell rootStyle): the
/// caller's base_style sits under the tone's :hover / :active / :disabled, hover_style /
/// pressed_style over the tone's. Content is centered; a block button fills the main axis (an
/// icon-only one stays square), any other keeps its own width in a stretching parent (centering a
/// stretched frame would push the label out of its visible box).
pub const Root = struct {
    block: bool,
    icon_only: bool,
    base: StyleOverride,
    hover: ?StyleOverride,
    pressed: ?StyleOverride,
};

pub fn rootStyle(r: Root) ConditionalStyle {
    var base = r.base;
    base.justify = .center;
    if (!r.block) base.no_cross_stretch = true;
    if (r.block and !r.icon_only) {
        base.width = .{ .grow = .{} };
        base.align_self = .stretch;
    }
    return .{ .base = base, .hover = r.hover, .active = r.pressed };
}

/// The label's text tier: the size tier's font size (base_style's when set) and line height.
/// Weight and color are left to inherit from the root (the tone's, base_style's, and per state
/// hover_style's / pressed_style's), so a state that changes the weight re-measures the label.
pub const Label = struct { size: ButtonSize, font_size: ?f32 };
pub const LabelText = struct { font_size: f32, line_height: f32 };

pub fn label(l: Label, t: *const ThemeTokens) LabelText {
    const m = shell.metrics(t, l.size);
    return .{ .font_size = l.font_size orelse m.font_size, .line_height = m.line_height };
}

/// Glyph stack in the icon slot (svg / texture / ring share one slot element; one of them shows at
/// a time). A row, so a chevron after a trailing glyph sits beside it (with one child shown the
/// direction does not matter).
pub const glyph_stack = ui.previewCss("src/ui/components/button/styles.yss", "glyph_stack", @embedFile("styles.yss"), .{ .direction = .row, .align_items = .center, .justify = .center, });

/// Glyph box: icon_size, else the size tier's glyph.
pub const glyph = ui.paramStyle(struct { size: ?f32, tier: ButtonSize, pub const declared = &[_][]const u8{ "width", "height", }; pub fn resolve(args: @This(), t: *const ui.theme.Values) ui.BoxStyle { return ui.boxFrom(.{ .width = args.size orelse shell.glyphSize(args.tier), .height = args.size orelse shell.glyphSize(args.tier), }, t); } });

/// Glyph tint: icon_tint when given, else the current color (the shell's foreground).
pub fn glyphTint(tint: ?Color, _: *const ThemeTokens) ?Color {
    return tint;
}

/// Dropdown chevron after the label (Button `chevron`): a design-icon size per tier (xs 10, sm / md
/// size-xs, lg size-sm), fg-tertiary in every state (the label's tone colors do not reach it).
pub const chevron = ui.paramStyle(struct { tier: ButtonSize, pub const declared = &[_][]const u8{ "width", "height", "flex_shrink", "icon_color", }; pub fn resolve(args: @This(), t: *const ui.theme.Values) ui.BoxStyle { return ui.boxFrom(.{ .width = chevronSize(t, args.tier), .height = chevronSize(t, args.tier), .flex_shrink = 0, .icon_color = ui.tokenRef(.color, "fg-tertiary"), }, t); } });

/// Chevron size per tier: one step under the tier's glyph (12 / 14 / 16 / 20 → 10 / 12 / 12 / 14).
/// sm / md / lg read the design-icon sizes; xs's 10 is below the icon scale (12 / 14 / 16 / 20).
pub fn chevronSize(t: *const ThemeTokens, size: ButtonSize) f32 {
    return switch (size) {
        .xs => 10,
        .sm, .md => t.tokens.size.xs,
        .lg => t.tokens.size.sm,
    };
}

/// A chevron after a trailing glyph (in the glyph stack): spaced from the glyph like the label is
/// (the shell's leading-glyph gap).
pub const chevron_after_glyph = ui.paramStyle(struct { tier: ButtonSize, pub const declared = &[_][]const u8{ "margin", }; pub fn resolve(args: @This(), t: *const ui.theme.Values) ui.BoxStyle { return ui.boxFrom(.{ .margin = .{ .top = 0, .right = 0, .bottom = 0, .left = shell.geometryGap(t, args.tier, true, .glyph) }, }, t); } });

/// Loading ring: a design-icon square, the canvas fills it.
pub const ring_box = ui.paramStyle(struct { pub const declared = &[_][]const u8{ "width", "height", "align_items", "justify", }; pub fn resolve(args: @This(), t: *const ui.theme.Values) ui.BoxStyle { _ = args; return ui.boxFrom(.{ .width = t.tokens.size.icon, .height = t.tokens.size.icon, .align_items = .center, .justify = .center, }, t); } }).of(.{});
pub const ring_canvas = ui.previewCss("src/ui/components/button/styles.yss", "ring_canvas", @embedFile("styles.yss"), .{ .width = .fill, .height = .fill, .align_self = .stretch, });

fn strokeOf(size: ButtonSize) f32 {
    return switch (size) {
        .xs, .sm => 1.5,
        .md => 2.0,
        .lg => 2.5,
    };
}

/// Loading ring arc (same keyframes as Spinner) in the current color.
/// The ring repeats with the Spinner's loop, so the compositor can run it.
pub const ring_loop_ms: f64 = spinner.loop_ms;

pub fn drawRing(ctx: ui.DrawContext, size: ButtonSize, frame: ui.view.Frame) anyerror!void {
    const dl = ctx.display_list orelse return;
    const header = ctx.display_header orelse return;
    const arc = if (core.render_engine.current_reduced_motion) spinner.reducedMotionArc() else spinner.arcAt(frame.now_ms);
    try dl.append(.{ .arc = .{
        .header = header,
        .cx = ctx.local_w / 2.0,
        .cy = ctx.local_h / 2.0,
        .outer_radius = frame.tokens.tokens.size.icon / 2.0,
        .stroke_width = strokeOf(size),
        .start_angle = arc.start,
        .end_angle = arc.end,
        .color = ctx.current_color orelse frame.tokens.tokens.color.fg_primary,
    } });
}

//# yix-map styles.yss
