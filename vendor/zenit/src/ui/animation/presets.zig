/// Animation preset library: one-shot wrappers for common animation effects
///
/// Similar to GSAP registerEffect; each preset calls animateNode() internally.
///
/// Usage:
/// ```zig
/// const presets = @import("animation/presets.zig");
///
/// presets.fadeIn(node, allocator, .{});
/// presets.slideInUp(node, allocator, .{ .distance = 30, .duration = 0.4 });
/// presets.scaleIn(node, allocator, .{ .from_scale = 0.8 });
/// presets.shake(node, allocator, .{ .intensity = 10 });
/// ```
const std = @import("std");
const Allocator = std.mem.Allocator;
const node_animator = @import("node_animator.zig");
const animateNode = node_animator.animateNode;
const Easing = @import("easing.zig").Easing;

// ============ Fade ============

pub const FadeOpts = struct {
    duration: f32 = 0.3,
    easing: Easing = .ease_out_quad,
    delay: f32 = 0,
};

/// Fade in: opacity 0 -> 1
pub fn fadeIn(node: anytype, allocator: Allocator, opts: FadeOpts) void {
    animateNode(node, allocator, .{
        .prop = .opacity,
        .from = 0,
        .to = 1,
        .duration = opts.duration,
        .easing = opts.easing,
        .delay = opts.delay,
    });
}

// ============ Slide ============

pub const SlideOpts = struct {
    distance: f32 = 20,
    duration: f32 = 0.4,
    easing: Easing = .ease_out_cubic,
    delay: f32 = 0,
    fade: bool = true,
};

/// Slide up from bottom
pub fn slideInUp(node: anytype, allocator: Allocator, opts: SlideOpts) void {
    animateNode(node, allocator, .{
        .prop = .translate_y,
        .from = opts.distance,
        .to = 0,
        .duration = opts.duration,
        .easing = opts.easing,
        .delay = opts.delay,
    });
    if (opts.fade) {
        animateNode(node, allocator, .{
            .prop = .opacity,
            .from = 0,
            .to = 1,
            .duration = opts.duration * 0.6,
            .easing = opts.easing,
            .delay = opts.delay,
        });
    }
}

/// Slide down from top
pub fn slideInDown(node: anytype, allocator: Allocator, opts: SlideOpts) void {
    animateNode(node, allocator, .{
        .prop = .translate_y,
        .from = -opts.distance,
        .to = 0,
        .duration = opts.duration,
        .easing = opts.easing,
        .delay = opts.delay,
    });
    if (opts.fade) {
        animateNode(node, allocator, .{
            .prop = .opacity,
            .from = 0,
            .to = 1,
            .duration = opts.duration * 0.6,
            .easing = opts.easing,
            .delay = opts.delay,
        });
    }
}

// ============ Scale ============

pub const ScaleOpts = struct {
    from_scale: f32 = 0.8,
    duration: f32 = 0.3,
    easing: Easing = .ease_out_back,
    delay: f32 = 0,
    fade: bool = true,
};

/// Scale in (small to large)
pub fn scaleIn(node: anytype, allocator: Allocator, opts: ScaleOpts) void {
    animateNode(node, allocator, .{
        .prop = .scale_x,
        .from = opts.from_scale,
        .to = 1.0,
        .duration = opts.duration,
        .easing = opts.easing,
        .delay = opts.delay,
    });
    animateNode(node, allocator, .{
        .prop = .scale_y,
        .from = opts.from_scale,
        .to = 1.0,
        .duration = opts.duration,
        .easing = opts.easing,
        .delay = opts.delay,
    });
    if (opts.fade) {
        animateNode(node, allocator, .{
            .prop = .opacity,
            .from = 0,
            .to = 1,
            .duration = opts.duration * 0.5,
            .easing = .ease_out_quad,
            .delay = opts.delay,
        });
    }
}

// ============ Shake ============

pub const ShakeOpts = struct {
    intensity: f32 = 8,
    duration: f32 = 0.4,
    delay: f32 = 0,
};

/// Shake effect (simulate spring with elastic easing)
pub fn shake(node: anytype, allocator: Allocator, opts: ShakeOpts) void {
    animateNode(node, allocator, .{
        .prop = .translate_x,
        .from = opts.intensity,
        .to = 0,
        .duration = opts.duration,
        .easing = .ease_out_elastic,
        .delay = opts.delay,
    });
}

// ============ Attention: ping / breathe ============

pub const PingOpts = struct {
    /// Rings in this burst.
    count: u32 = 1,
    /// Seconds per ring.
    duration: f32 = 1.0,
    /// Scale the ring grows to (an 8 pt dot ringing out to 16 pt is 2).
    to_scale: f32 = 2.0,
    /// Opacity a ring starts at; it fades to 0.
    from_opacity: f32 = 0.6,
    delay: f32 = 0,
};

/// Ping: a ring grows out of its resting size and fades away, `count` times in a row (an
/// attention mark around a status dot; the node is the ring, drawn behind the dot). Ends at
/// opacity 0 and the grown scale, so the ring is invisible at rest. Callers skip it when the
/// system asks for reduced motion.
pub fn ping(node: anytype, allocator: Allocator, opts: PingOpts) void {
    if (opts.count == 0) return;
    inline for (.{ .scale_x, .scale_y }) |prop| animateNode(node, allocator, .{
        .prop = prop,
        .from = 1.0,
        .to = opts.to_scale,
        .duration = opts.duration,
        .easing = .ease_out_quad,
        .delay = opts.delay,
        .loops = opts.count,
    });
    animateNode(node, allocator, .{
        .prop = .opacity,
        .from = opts.from_opacity,
        .to = 0,
        .duration = opts.duration,
        .easing = .ease_out_quad,
        .delay = opts.delay,
        .loops = opts.count,
    });
}

pub const BreatheOpts = struct {
    /// Lowest opacity of the cycle.
    min_opacity: f32 = 0.45,
    /// Seconds for a full 100% -> min -> 100% cycle.
    period: f32 = 1.6,
};

/// Breathe: opacity eases 1 -> min -> 1 and repeats until `breatheStop` (or any other opacity
/// animation) replaces it (an "in progress" symbol, like SF Symbols' pulse effect). Callers
/// skip it when the system asks for reduced motion.
pub fn breathe(node: anytype, allocator: Allocator, opts: BreatheOpts) void {
    animateNode(node, allocator, .{
        .prop = .opacity,
        .from = 1.0,
        .to = opts.min_opacity,
        .duration = opts.period / 2,
        .easing = .ease_in_out_sine,
        .loops = 0,
        .yoyo = true,
    });
}

/// Ends a `breathe` by easing back to full opacity.
pub fn breatheStop(node: anytype, allocator: Allocator) void {
    animateNode(node, allocator, .{ .prop = .opacity, .to = 1.0, .duration = 0.15, .easing = .ease_out_quad });
}

const TestStyle = struct {
    opacity: f32 = 1.0,
    translate_x: f32 = 0,
    translate_y: f32 = 0,
    width: union(enum) { px: f32, fit, grow: struct {} } = .fit,
    height: union(enum) { px: f32, fit, grow: struct {} } = .fit,
    margin: struct { top: f32 = 0, left: f32 = 0 } = .{},
    gap: f32 = 0,
    border: struct {
        width: f32 = 0,
        pub fn setUniformWidth(self: *@This(), w: f32) void {
            self.width = w;
        }
    } = .{},

    pub fn scale_x(_: *const TestStyle) f32 {
        return test_ext.scale_x;
    }
    pub fn scale_y(_: *const TestStyle) f32 {
        return test_ext.scale_y;
    }
    pub fn corner_radius(_: *const TestStyle) ?struct { all: f32 } {
        return .{ .all = 0 };
    }
    pub fn rotate(_: *const TestStyle) f32 {
        return 0;
    }
    pub fn ensureExtPanic(_: *TestStyle, _: Allocator) *TestStyleExt {
        return &test_ext;
    }
};

const TestStyleExt = struct {
    scale_x: f32 = 1.0,
    scale_y: f32 = 1.0,
    corner_radius: struct { all: f32 } = .{ .all = 0 },
    rotate: f32 = 0,
};

var test_ext = TestStyleExt{};

const TestNode = struct {
    style: TestStyle = .{},
    frame_state: struct {
        rect: struct { w: f32 = 100, h: f32 = 40 } = .{},
        frame_local: struct {
            runtime: struct { commands: ?*node_animator.NodeAnimations = null, transitions: ?*anyopaque = null } = .{},
        } = .{},
    } = .{},
    render_dirty: bool = false,
    layout_dirty: bool = false,
    dirty: struct {
        pipeline: struct {
            order: bool = false,
            subtree_order: bool = false,
            interaction: bool = false,
            subtree_interaction: bool = false,
            composite: bool = false,
            subtree_composite: bool = false,
        } = .{},
    } = .{},

    pub fn markRenderDirty(self: *TestNode) void {
        self.render_dirty = true;
    }
    pub fn markCompositeDirty(self: *TestNode) void {
        self.render_dirty = true;
    }
    pub fn markInteractionDirty(self: *TestNode) void {
        self.dirty.pipeline.interaction = true;
    }
    pub fn markLayoutDirty(self: *TestNode) void {
        self.layout_dirty = true;
    }
    pub fn markSizingDirty(self: *TestNode) void {
        self.layout_dirty = true;
    }
    pub fn invalidateRenderCache(_: *TestNode) void {}
    pub fn requestCompositeAnimationLinger(self: *TestNode, _: bool, _: bool) void {
        self.render_dirty = true;
    }
    pub fn setMarginTop(self: *TestNode, v: f32) void {
        self.style.margin.top = v;
        self.markLayoutDirty();
    }
    pub fn setMarginLeft(self: *TestNode, v: f32) void {
        self.style.margin.left = v;
        self.markLayoutDirty();
    }
};

test "presets.fadeIn starts from transparent and ramps over first frames" {
    var node = TestNode{};
    fadeIn(&node, std.testing.allocator, .{ .duration = 0.3 });
    defer if (node.frame_state.frame_local.runtime.commands) |anims| std.testing.allocator.destroy(anims);

    try std.testing.expectApproxEqAbs(@as(f32, 0.0), node.style.opacity, 0.0001);

    var last = node.style.opacity;
    for (0..10) |_| {
        _ = node.frame_state.frame_local.runtime.commands.?.tick(&node, std.testing.allocator, 1.0 / 60.0);
        try std.testing.expect(node.style.opacity + 0.0001 >= last);
        last = node.style.opacity;
    }
    try std.testing.expect(node.style.opacity < 1.0);
}

test "presets.slideInUp starts below and does not flash at final position" {
    var node = TestNode{};
    slideInUp(&node, std.testing.allocator, .{ .distance = 20, .duration = 0.3 });
    defer if (node.frame_state.frame_local.runtime.commands) |anims| std.testing.allocator.destroy(anims);

    try std.testing.expectApproxEqAbs(@as(f32, 20.0), node.style.translate_y, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), node.style.opacity, 0.0001);

    var last_translate = node.style.translate_y;
    var last_opacity = node.style.opacity;
    for (0..10) |_| {
        _ = node.frame_state.frame_local.runtime.commands.?.tick(&node, std.testing.allocator, 1.0 / 60.0);
        try std.testing.expect(node.style.translate_y <= last_translate + 0.0001);
        try std.testing.expect(node.style.opacity + 0.0001 >= last_opacity);
        last_translate = node.style.translate_y;
        last_opacity = node.style.opacity;
    }
    try std.testing.expect(node.style.translate_y > 0);
}

test "presets.slideInDown starts above and does not flash at final position" {
    var node = TestNode{};
    slideInDown(&node, std.testing.allocator, .{ .distance = 20, .duration = 0.3 });
    defer if (node.frame_state.frame_local.runtime.commands) |anims| std.testing.allocator.destroy(anims);

    try std.testing.expectApproxEqAbs(@as(f32, -20.0), node.style.translate_y, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), node.style.opacity, 0.0001);

    var last_translate = node.style.translate_y;
    var last_opacity = node.style.opacity;
    for (0..10) |_| {
        _ = node.frame_state.frame_local.runtime.commands.?.tick(&node, std.testing.allocator, 1.0 / 60.0);
        try std.testing.expect(node.style.translate_y >= last_translate - 0.0001);
        try std.testing.expect(node.style.opacity + 0.0001 >= last_opacity);
        last_translate = node.style.translate_y;
        last_opacity = node.style.opacity;
    }
    try std.testing.expect(node.style.translate_y < 0);
}

fn tickAt(node: *TestNode, ms: f64) bool {
    return node.frame_state.frame_local.runtime.commands.?.tick(node, std.testing.allocator, ms);
}

test "presets.ping rings count times then rests invisible" {
    const render_engine = @import("../core/render_engine/mod.zig");
    const saved = render_engine.current_frame_time_ms;
    defer render_engine.current_frame_time_ms = saved;
    render_engine.current_frame_time_ms = 1000;
    test_ext = .{};
    defer test_ext = .{};
    var node = TestNode{};
    ping(&node, std.testing.allocator, .{ .count = 2, .duration = 1.0 });
    defer if (node.frame_state.frame_local.runtime.commands) |anims| std.testing.allocator.destroy(anims);
    try std.testing.expectApproxEqAbs(@as(f32, 0.6), node.style.opacity, 0.0001);
    _ = tickAt(&node, 1000);
    _ = tickAt(&node, 1500);
    try std.testing.expect(node.style.opacity > 0 and node.style.opacity < 0.6);
    try std.testing.expect(test_ext.scale_x > 1 and test_ext.scale_x < 2);
    // Second ring starts over from the dot.
    _ = tickAt(&node, 2050);
    try std.testing.expect(node.style.opacity > 0.5);
    try std.testing.expect(test_ext.scale_x < 1.2);
    _ = tickAt(&node, 3200);
    try std.testing.expect(!tickAt(&node, 3216));
    try std.testing.expectApproxEqAbs(@as(f32, 0), node.style.opacity, 0.0001);
}

test "presets.breathe cycles between full and min opacity until stopped" {
    const render_engine = @import("../core/render_engine/mod.zig");
    const saved = render_engine.current_frame_time_ms;
    defer render_engine.current_frame_time_ms = saved;
    render_engine.current_frame_time_ms = 1000;
    var node = TestNode{};
    breathe(&node, std.testing.allocator, .{ .min_opacity = 0.45, .period = 1.6 });
    defer if (node.frame_state.frame_local.runtime.commands) |anims| std.testing.allocator.destroy(anims);
    _ = tickAt(&node, 1000);
    _ = tickAt(&node, 1800);
    try std.testing.expectApproxEqAbs(@as(f32, 0.45), node.style.opacity, 0.02);
    _ = tickAt(&node, 2600);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), node.style.opacity, 0.02);
    // Still running many cycles later.
    try std.testing.expect(tickAt(&node, 1000 + 1600 * 10 + 800));
    try std.testing.expectApproxEqAbs(@as(f32, 0.45), node.style.opacity, 0.02);
    render_engine.current_frame_time_ms = 1000 + 1600 * 11;
    breatheStop(&node, std.testing.allocator);
    _ = tickAt(&node, 1000 + 1600 * 11);
    _ = tickAt(&node, 1000 + 1600 * 11 + 400);
    try std.testing.expect(!tickAt(&node, 1000 + 1600 * 11 + 416));
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), node.style.opacity, 0.0001);
}
