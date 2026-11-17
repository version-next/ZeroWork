/// Grabber Component.
/// The drag indicator of a movable surface: a 36 × 4 capsule in the tertiary ink (floating panels,
/// sheets); while the host's drag region is held (`active`) it takes the accent ink and widens to
/// 48. Visual only and hit-transparent; the host owns the drag region. View in grabber.yix;
/// style in styles.yss.
const std = @import("std");
const core = @import("../../core.zig");
const Cx = core.Cx;
const Color = core.Color;
const reactive = @import("../../reactive.zig");
const Scope = reactive.Scope;

pub const Grabber = @import("_grabber.yix.zig").Grabber;

// ========== Tests ==========

const view = @import("../../view.zig");

test "Grabber: 36 × 4 capsule in the tertiary ink, hit-transparent, follows the theme" {
    const cx = try Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    cx.root = try core.box(cx, .{ .width = .{ .px = 200 }, .height = .{ .px = 40 } }, .{});
    const scope = try Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    const grabber = try view.render(scope, cx, Grabber(.{}));
    try cx.root.?.appendChild(std.testing.allocator, grabber);
    cx.layout();
    const r = grabber.rectFromWorldOrFallback();
    try std.testing.expectEqual(@as(f32, 36), r.w);
    try std.testing.expectEqual(@as(f32, 4), r.h);
    try std.testing.expect(std.meta.eql(@import("../../core/types.zig").CornerRadius.uniform(2), grabber.style.corner_radius().?));
    try std.testing.expect(Color.eql(cx.tokens.tokens.color.fg_tertiary, grabber.getBackground()));
    try std.testing.expectEqual(core.HitBehavior.pass_through, grabber.style.hit_behavior().?);
    const wide = try Grabber(.{ .width = 48 }).mount(scope, cx);
    defer cx.freeNode(wide);
    try std.testing.expectEqual(@as(f32, 48), wide.style.width.px);
}

test "Grabber: active (a signal the host sets while its drag region is held) widens to 48 in the accent ink and back" {
    const cx = try Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    cx.root = try core.box(cx, .{ .width = .{ .px = 200 }, .height = .{ .px = 40 } }, .{});
    const scope = try Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    const held = try scope.createSignal(bool, false);
    const grabber = try view.render(scope, cx, Grabber(.{ .active = held }));
    try cx.root.?.appendChild(std.testing.allocator, grabber);
    cx.layout();
    try std.testing.expectEqual(@as(f32, 36), grabber.rectFromWorldOrFallback().w);
    try std.testing.expect(Color.eql(cx.tokens.tokens.color.fg_tertiary, grabber.getBackground()));
    held.set(true);
    cx.layout();
    try std.testing.expectEqual(@as(f32, 48), grabber.rectFromWorldOrFallback().w);
    try std.testing.expectEqual(@as(f32, 4), grabber.rectFromWorldOrFallback().h);
    try std.testing.expect(Color.eql(cx.tokens.tokens.color.accent, grabber.getBackground()));
    try std.testing.expectEqual(core.HitBehavior.pass_through, grabber.style.hit_behavior().?);
    held.set(false);
    cx.layout();
    try std.testing.expectEqual(@as(f32, 36), grabber.rectFromWorldOrFallback().w);
    try std.testing.expect(Color.eql(cx.tokens.tokens.color.fg_tertiary, grabber.getBackground()));
    // A custom held width; a static `active` works too.
    const wide = try Grabber(.{ .active = true, .active_width = 56 }).mount(scope, cx);
    defer cx.freeNode(wide);
    try std.testing.expectEqual(@as(f32, 56), wide.style.width.px);
}

test {
    _ = @import("_styles.yss.zig");
}

// Per-allocation OOM sweep; see src/ui/components/oom_sweep.zig.
test "grabber: mount 在任意分配点失败时不泄漏（sweep）" {
    try @import("../oom_sweep.zig").sweepMount("grabber", struct {
        fn m(scope: *Scope, cx: *Cx) anyerror!?*core.Node {
            return try Grabber(.{}).mount(scope, cx);
        }
    }.m);
}
