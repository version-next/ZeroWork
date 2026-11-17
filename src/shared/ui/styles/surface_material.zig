//! Material recipes a surface applies to itself, where it is created.
//!
//! Nothing here looks at the tree, at other surfaces or at the overlay stack: the creator knows
//! what its surface is painted on and says so (`Ground`). zenit's native surfaces (Popover, Menu,
//! Modal, Select panel, Tooltip, Notification, Glass controls) are not material surfaces of
//! ZeroWork: they keep zenit's own look and never go through this file.
//!
//! Theme and material changes arrive through the window's theme publication: a named style
//! function is replayed by zenit; a node styled once with a plain `BoxStyle` binds its fill with
//! `bindFill`.
const std = @import("std");
const ui = @import("ui");
const theme = @import("../theme/app_theme.zig");

/// What the surface is painted on.
pub const Ground = enum {
    /// The window canvas or a shell island: the wallpaper shows through them when the
    /// transparency setting is above zero. The surface is the first material layer (L1).
    canvas,
    /// One of ZeroWork's own floating L1 surfaces (a floating card, an in-pane floating panel).
    /// The surface is the second material layer (L2).
    float,
    /// A card that itself sits on a `float` (L3).
    card,
    /// An opaque surface: a zenit native panel (Popover / Menu / Modal / Select panel) or any
    /// other opaque fill. Nothing shows through it, so the fill is opaque at every setting.
    solid,
};

/// Fill opacity of a surface on `ground` (DESIGN_STANDARDS §3 "视觉层级": the fill over the
/// directly preceding material layer; opaque when the transparency setting is zero).
pub fn alpha(ground: Ground) u8 {
    return switch (ground) {
        .solid => 255,
        .canvas => theme.layerAlpha(1),
        .float => theme.layerAlpha(2),
        .card => theme.layerAlpha(3),
    };
}

/// A tonal fill (`current().well`, `popupInset()`, `popupAction()` …) for a card on `ground`.
/// Only the RGB of `role` is used.
pub fn fill(role: ui.Color, ground: Ground) ui.Color {
    return role.withAlpha(alpha(ground));
}

/// One of ZeroWork's own floating panels on `ground`: overlay tint, backdrop blur, the shared
/// floating shadow, no perimeter line. Merge it into the panel's own style.
pub fn floating(ground: Ground) ui.BoxStyle {
    return .{
        .background = fill(theme.baseColors().overlay, ground),
        .glass = theme.overlayGlass(),
        .shadows = ui.ShadowList.of(&.{theme.floatingShadow()}),
    };
}

/// Keeps the fill of a node styled with a plain `BoxStyle` on `paint()` across theme and
/// material publications. A node with a named style function needs nothing: zenit replays it.
pub fn bindFill(cx: *ui.Cx, scope: *ui.Scope, node: *ui.Node, comptime paint: fn () ui.Color) !void {
    try scope.createEffect(.{ .node = node, .publication = try cx.themeSignal() }, struct {
        fn apply(ctx: anytype) void {
            _ = ctx.publication.get();
            const color = paint();
            if (!ui.Color.eql(ctx.node.getBackground(), color)) ctx.node.setBackground(color);
        }
    }.apply);
}

test "a surface's fill follows what it is painted on, not where it sits in the tree" {
    const saved = theme.materialParameters();
    defer _ = theme.setMaterialParameters(saved.transparency, saved.blur);
    const well = ui.Color.rgba(10, 20, 30, 92);
    _ = theme.setMaterialParameters(0, 0);
    inline for (.{ Ground.canvas, Ground.float, Ground.card, Ground.solid }) |ground| try std.testing.expectEqual(well.withAlpha(255), fill(well, ground));
    for ([_]f32{ 1, 50, 100 }) |transparency| {
        _ = theme.setMaterialParameters(transparency, 0);
        try std.testing.expectEqual(@as(u8, 51), alpha(.canvas));
        try std.testing.expectEqual(@as(u8, 64), alpha(.float));
        try std.testing.expectEqual(@as(u8, 85), alpha(.card));
        try std.testing.expectEqual(@as(u8, 255), alpha(.solid));
    }
    _ = theme.setMaterialParameters(50, 30);
    const panel = floating(.canvas);
    try std.testing.expectEqual(theme.baseColors().overlay.withAlpha(51), panel.background.?);
    try std.testing.expectEqual(@as(f32, 30), panel.glass.?.backdrop_blur);
}

test "bindFill repaints a plainly styled node on theme and material publications" {
    const saved = theme.materialParameters();
    const previous = theme.currentName();
    defer {
        _ = theme.setMaterialParameters(saved.transparency, saved.blur);
        theme.select(previous);
    }
    const cx = try ui.Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    const scope = try ui.Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    const publication = try cx.bindState(@import("../theme/theme_publication.zig").ThemePublication, .{});
    theme.select(.light);
    _ = theme.setMaterialParameters(0, 0);
    publication.publish(cx, theme.widgetTheme(.light));
    const paint = struct {
        fn color() ui.Color {
            return fill(theme.current().well, .canvas);
        }
    }.color;
    const node = try ui.box(cx, .{ .width = .{ .px = 10 }, .height = .{ .px = 10 }, .background = paint() }, .{});
    cx.root = node;
    try bindFill(cx, scope, node, paint);
    try std.testing.expectEqual(theme.colors(.light).well.withAlpha(255), node.getBackground());
    theme.select(.dark);
    publication.publish(cx, theme.widgetTheme(.dark));
    _ = cx.render();
    try std.testing.expectEqual(theme.colors(.dark).well.withAlpha(255), node.getBackground());
    _ = theme.setMaterialParameters(40, 0);
    publication.publish(cx, theme.widgetTheme(.dark));
    _ = cx.render();
    try std.testing.expectEqual(theme.colors(.dark).well.withAlpha(51), node.getBackground());
}
