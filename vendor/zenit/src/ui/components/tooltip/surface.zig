//! TooltipSurface: the Tooltip bubble drawn in place, without the hover popover.
//!
//!   root (box: tooltip padding / radius / background / shadow, hit-transparent)
//!   +-- label (tooltip label style)
//!
//! For persistent, noninteractive readouts that sit on top of content (a video frame-rate HUD,
//! a status readout over a canvas): same colours, radius, padding and shadow as `W.Tooltip`'s
//! panel, but laid out by the caller in its own tree (no portal, no trigger, no delay), so the
//! caller owns its position, visibility and stacking.
//!
//! - `text`: the label (a source);
//! - `fixed_dark`: always the dark bubble (the light scheme's tooltip colours: dark ground, light
//!   ink) whatever the app theme. For surfaces over content that never follows the app theme
//!   (remote video, photos): the dark theme's light bubble would glare on a dark frame;
//! - `font_size` (default 12, like Tooltip), `wrap` (default the tooltip's word breaking; `.none`
//!   keeps one line).
//!
//! Zig: `W.TooltipSurface(.{ .text = fps, .fixed_dark = true, .wrap = .none })`.
//! Yix: `<W.TooltipSurface text={fps} fixedDark={true} />`.
const std = @import("std");
const core = @import("../../core.zig");
const v = @import("../../view.zig");
const reactive = @import("../../reactive.zig");
const Scope = reactive.Scope;
const Source = reactive.Source;
const Cx = core.Cx;
const Node = core.Node;
const theme = core.theme;
const styles = @import("styles.zig");

pub const TooltipSurfaceProps = struct {
    text: Source([]const u8) = .{ .value = "" },
    /// Read at mount.
    fixed_dark: bool = false,
    /// Read at mount.
    font_size: f32 = 12,
    /// Read at mount; null = the tooltip's word breaking.
    wrap: ?core.TextWrap = null,
};

/// `W.TooltipSurface(.{ .text = "Copied", .fixed_dark = true })`.
pub fn TooltipSurface(args: anytype) v.ComponentOf(mountSurface) {
    return v.component(mountSurface, reactive.props.coerce(TooltipSurfaceProps, args));
}

/// The tokens the bubble paints with: the app theme, or the light scheme for `fixed_dark`.
pub fn surfaceTokens(fixed_dark: bool, current: *const theme.ThemeTokens) *const theme.ThemeTokens {
    return if (fixed_dark) &theme.light else current;
}

fn labelStyle(props: TooltipSurfaceProps, t: *const theme.ThemeTokens) core.TextStyle {
    var style = styles.tooltipLabelStyle(null, props.font_size, surfaceTokens(props.fixed_dark, t));
    if (props.wrap) |wrap| style.wrap = wrap;
    return style;
}

fn mountSurface(props: TooltipSurfaceProps, scope: *Scope, cx: *Cx) anyerror!*Node {
    const t = cx.tokens;
    const radius = styles.tooltipRadius(t);
    var label: *Node = undefined;
    const root = try v.render(scope, cx, v.box(.{ .style = core.BoxStyle{
        .width = .{ .fit = .{} },
        .height = .{ .fit = .{} },
        .padding = styles.tooltipPadding(t),
        .border = .{ .width = 0, .radius = radius },
        .flex_shrink = 0,
        .hit_behavior = .pass_through,
    } }, v.capture(&label, v.text(.{ .style = labelStyle(props, t) }, props.text))));
    errdefer cx.freeNode(root);
    root.meta.ownership.meta.component_name = "TooltipSurface";
    root.setHitTestVisible(false);
    const ext = try root.style.ensureExtFallible(cx.allocator);
    ext.clip_shape = .{ .rounded_rect = radius };
    try scope.createEffect(.{ .theme_source = try cx.themeSignal(), .root = root, .label = label, .props = props }, struct {
        fn paint(c: anytype) void {
            const tokens = surfaceTokens(c.props.fixed_dark, c.theme_source.get());
            c.root.setBackgroundRaw(styles.tooltipContentBackground(null, tokens));
            if (c.root.style.ext) |e| e.setShadow(tokens.tokens.shadow.sm);
            c.root.markRenderDirty();
            if (c.label.getText()) |old| {
                var next = old;
                next.color = styles.tooltipLabelColor(null, tokens);
                c.label.setText(next);
            }
        }
    }.paint);
    return root;
}

// ===== Tests =====

const testing = std.testing;

fn mounted(scope: *Scope, cx: *Cx, element: anytype) !*Node {
    const root = try v.render(scope, cx, v.col(.{}, .{element}));
    cx.root = root;
    cx.layout();
    return root.children.items[0];
}

test "TooltipSurface: the tooltip panel's colours, in place and hit-transparent" {
    const cx = try Cx.init(testing.allocator, testing.io);
    defer cx.deinit();
    cx.setTheme(&theme.light);
    const scope = try Scope.init(testing.allocator, null, cx.owner);
    defer scope.dispose();
    const surface = try mounted(scope, cx, TooltipSurface(.{ .text = "8.0 FPS" }));
    try testing.expectEqualStrings("TooltipSurface", surface.meta.ownership.meta.component_name.?);
    try testing.expectEqual(theme.light.tokens.color.tooltip_bg, surface.getBackground());
    const label = surface.children.items[0];
    try testing.expectEqualStrings("8.0 FPS", label.getText().?.content);
    try testing.expectEqual(theme.light.tokens.color.tooltip_fg, label.getText().?.color);
    try testing.expectEqual(styles.tooltipRadius(cx.tokens), surface.style.border.radius);
    try testing.expect(!surface.frame_state.state_bits.flags.hit_test_visible);
    try testing.expect(surface.rectFromWorldOrFallback().w > 0);
    // Follows the app theme by default.
    cx.setTheme(&theme.dark);
    try testing.expectEqual(theme.dark.tokens.color.tooltip_bg, surface.getBackground());
    try testing.expectEqual(theme.dark.tokens.color.tooltip_fg, label.getText().?.color);
}

test "TooltipSurface: fixed_dark keeps the dark bubble in every theme; text follows its source" {
    const cx = try Cx.init(testing.allocator, testing.io);
    defer cx.deinit();
    cx.setTheme(&theme.dark);
    const scope = try Scope.init(testing.allocator, null, cx.owner);
    defer scope.dispose();
    const text = try scope.createSignal([]const u8, "显示 8.0 FPS");
    const surface = try mounted(scope, cx, TooltipSurface(.{ .text = text, .fixed_dark = true, .wrap = .none, .font_size = 11 }));
    const label = surface.children.items[0];
    try testing.expectEqual(theme.light.tokens.color.tooltip_bg, surface.getBackground());
    try testing.expectEqual(theme.light.tokens.color.tooltip_fg, label.getText().?.color);
    try testing.expectEqual(@as(f32, 11), label.getText().?.font_size);
    cx.setTheme(&theme.light);
    try testing.expectEqual(theme.light.tokens.color.tooltip_bg, surface.getBackground());
    text.set("显示 9.5 FPS");
    try testing.expectEqualStrings("显示 9.5 FPS", label.getText().?.content);
}

test "TooltipSurface: mount 在任意分配点失败时不泄漏（sweep）" {
    try @import("../oom_sweep.zig").sweepMount("tooltip_surface", struct {
        fn m(scope: *Scope, cx: *Cx) anyerror!?*Node {
            return try v.render(scope, cx, TooltipSurface(.{ .text = "HUD", .fixed_dark = true }));
        }
    }.m);
}
