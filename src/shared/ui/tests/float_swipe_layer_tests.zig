//! Swipe down to collapse on the generic floating layer (Pencil AveHg, `float_swipe.zig`): a fixture
//! card on a window-free Cx with real layout, drag bindings and node animations; time of the pointer
//! samples from an injected clock so velocities are exact.
const std = @import("std");
const ui = @import("ui");
const model = @import("../../base/float_card.zig");
const float_swipe = @import("../../base/float_swipe.zig");
const layer_mod = @import("../float_card/float_layer.zig");
const chrome_mod = @import("../float_card/float_chrome.zig");

fn fixtureSize(content: model.Rect) model.Size {
    return .{ .width = @min(400, content.width / 2), .height = 300 };
}
const fixture: model.Descriptor = .{
    .id = "fixture.card",
    .interactions = .initMany(&.{ .move, .resize, .maximize, .raise, .close, .minimize, .remember_position, .open_from_anchor }),
    .min_size = .{ .width = 200, .height = 120 },
    .default_size = fixtureSize,
    .first_open = .beside_anchor,
};
const region = model.floatRegion(1440, 900, 44, 240);
const anchor: model.Rect = .{ .x = 1368, .y = 796, .width = 48, .height = 48 };
const origin: model.Origin = .{ .content = .{ .x = 240, .y = 44, .width = 1200, .height = 820 }, .anchor = anchor, .corner = .bottom_right };
const ms: u64 = std.time.ns_per_ms;

const Fixture = struct {
    cx: *ui.Cx,
    scope: *ui.Scope,
    layer: *layer_mod.FloatLayer,
    card: *layer_mod.Card,
    frame_node: *ui.Node,
    grip: *ui.Node,
    placement: model.Placement = .{},
    shown: bool = true,
    now_ns: u64 = 0,
    minimized: usize = 0,
    rests: usize = 0,

    fn init(self: *Fixture, descriptor: model.Descriptor) !void {
        self.* = .{ .cx = try ui.Cx.init(std.testing.allocator, std.testing.io), .scope = undefined, .layer = undefined, .card = undefined, .frame_node = undefined, .grip = undefined };
        self.cx.setViewport(1440, 900);
        self.scope = try ui.Scope.init(std.testing.allocator, null, self.cx.owner);
        self.cx.root = try ui.box(self.cx, .{ .width = .fill(), .height = .fill() }, .{});
        self.layer = try layer_mod.FloatLayer.mount(self.cx, self.scope, self.cx.root.?);
        self.layer.setRegion(region);
        self.layer.clock = .{ .ctx = self, .now_ns = now };
        const node = try ui.box(self.cx, .{ .position = .absolute, .direction = .column }, .{});
        const visual = try ui.box(self.cx, .{ .direction = .column, .background = ui.Color.rgb(230, 236, 250), .hit_behavior = .@"opaque" }, .{});
        const grip = try ui.box(self.cx, .{ .width = .fill(), .height = .{ .px = 14 } }, .{});
        try visual.appendChild(self.cx.allocator, grip);
        try visual.appendChild(self.cx.allocator, try ui.box(self.cx, .{ .width = .fill(), .height = .{ .px = 40 } }, .{}));
        try node.appendChild(self.cx.allocator, visual);
        try self.cx.root.?.appendChild(self.cx.allocator, node);
        self.frame_node = visual;
        self.grip = grip;
        self.card = try self.layer.attach(self.scope, .{ .node = node, .frame = visual, .grip = grip, .descriptor = descriptor, .placement = &self.placement, .callbacks = .{ .ctx = self, .action = action, .rest = rest } });
        self.frame();
        self.card.present(.{ .shown = true, .tab = 1, .current_tab = 1 });
        self.settle();
    }
    fn deinit(self: *Fixture) void {
        self.scope.dispose();
        self.cx.deinit();
    }
    fn now(ctx: ?*anyopaque) u64 {
        const self: *Fixture = @ptrCast(@alignCast(ctx.?));
        return self.now_ns;
    }
    /// The owner's minimize (like the AI): hide the card, keep its content.
    fn action(ctx: ?*anyopaque, value: model.HeaderAction) bool {
        const self: *Fixture = @ptrCast(@alignCast(ctx.?));
        if (value != .minimize) return false;
        self.minimized += 1;
        self.shown = false;
        self.card.present(.{ .shown = false, .tab = 1, .current_tab = 1, .explicit = true, .anchor = anchor });
        return true;
    }
    fn rest(ctx: ?*anyopaque, _: ui.fx.anchor_transition.Phase) void {
        const self: *Fixture = @ptrCast(@alignCast(ctx.?));
        self.rests += 1;
    }
    fn frame(self: *Fixture) void {
        self.card.update(origin, self.shown);
        self.cx.frame_count += 1;
        self.cx.frame_time_ms += 16;
        _ = self.cx.render();
    }
    fn settle(self: *Fixture) void {
        for (0..40) |_| self.frame();
    }
    fn rect(self: *Fixture) model.Rect {
        const r = self.frame_node.globalRect();
        return .{ .x = r.x, .y = r.y, .width = r.w, .height = r.h };
    }
    /// Drop the card on the region bottom (an ordinary drag: it starts undocked).
    fn dock(self: *Fixture) void {
        self.gesture(0, 3000, 2, 200, 200, false);
        self.settle();
    }
    /// Press the grip, move by (dx, dy) in `steps` moves `step_ms` apart, wait `pause_ms`, release.
    fn gesture(self: *Fixture, dx: f32, dy: f32, steps: usize, step_ms: u64, pause_ms: u64, hold: bool) void {
        const g = self.grip.globalRect();
        const x = g.x + g.w / 2;
        const y = g.y + g.h / 2;
        self.cx.handleMouseDown(x, y, .{});
        self.frame();
        for (1..steps + 1) |i| {
            const f: f32 = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(steps));
            self.now_ns += step_ms * ms;
            self.cx.handleMouseMove(x + dx * f, y + dy * f);
            self.frame();
        }
        if (hold) return;
        self.now_ns += pause_ms * ms;
        self.cx.handleMouseUp(x + dx, y + dy);
        self.frame();
    }
    fn release(self: *Fixture, dx: f32, dy: f32) void {
        const g = self.grip.globalRect();
        self.cx.handleMouseUp(g.x + g.w / 2 + dx, g.y + g.h / 2 + dy);
        self.frame();
    }
    fn offsetY(self: *const Fixture) f32 {
        return self.card.node.style.translate_y;
    }
    /// Frames until the glide lands (at most 1 s); returns the frame count.
    fn glideOut(self: *Fixture) usize {
        var frames: usize = 0;
        while (self.card.gliding() and frames < 64) : (frames += 1) self.frame();
        self.frame();
        return frames;
    }
    fn presented(self: *const Fixture) model.Rect {
        const r = self.card.presentedRect();
        return .{ .x = r.x, .y = r.y, .width = r.w, .height = r.h };
    }
};

test "swipe layer: availability is derived from minimize when attached" {
    var f: Fixture = undefined;
    try f.init(fixture);
    defer f.deinit();
    try std.testing.expect(f.card.descriptor.supports(.swipe_collapse));
    // Not docked at first open (beside the anchor, 48 above the view bottom of 892).
    try std.testing.expect(!float_swipe.docked(float_swipe.tokens, f.rect(), f.card.viewBottom()));
    f.dock();
    try std.testing.expect(float_swipe.docked(float_swipe.tokens, f.rect(), f.card.viewBottom()));
}

test "swipe layer: a fast downward fling slides the docked card out, fades it and hands it to minimize" {
    var f: Fixture = undefined;
    try f.init(fixture);
    defer f.deinit();
    f.dock();
    const docked = f.rect();
    const kept = f.placement.desired.?;
    // Held: grip press shows the held state; the card follows the pointer past the bottom.
    f.gesture(0, 120, 6, 5, 0, true);
    try std.testing.expect(f.card.gripHeld());
    try std.testing.expectApproxEqAbs(@as(f32, 120), f.offsetY(), 0.5);
    try std.testing.expectApproxEqAbs(docked.y + 120, f.card.presentedRect().y, 0.5);
    f.release(0, 120);
    try std.testing.expect(!f.card.gripHeld());
    try std.testing.expectEqual(@as(usize, 1), f.minimized);
    try std.testing.expectEqual(ui.fx.anchor_transition.Phase.collapsing, f.card.phase());
    try std.testing.expectEqualStrings("swipe", f.card.anchorLabel());
    try std.testing.expect(f.card.takeSwipeArrival());
    try std.testing.expect(!f.card.takeSwipeArrival());
    // Slides on downward (no Z12 flight) while fading out.
    var last_y = f.card.presentedRect().y;
    var last_opacity: f32 = 1.01;
    var frames: usize = 0;
    while (f.card.phase() == .collapsing and frames < 40) : (frames += 1) {
        f.frame();
        if (f.card.phase() != .collapsing) break;
        const r = f.card.presentedRect();
        try std.testing.expect(r.y >= last_y - 0.01);
        try std.testing.expect(f.card.presentedOpacity() <= last_opacity);
        last_y = r.y;
        last_opacity = f.card.presentedOpacity();
    }
    // 220 ms at 16 ms frames.
    try std.testing.expect(frames >= 12 and frames <= 17);
    try std.testing.expect(f.card.transition == null or f.card.transition.?.currentFrame() == null);
    f.settle();
    try std.testing.expectEqual(ui.fx.anchor_transition.Phase.collapsed, f.card.phase());
    try std.testing.expect(!f.card.node.isDisplayedInTree());
    try std.testing.expect(f.rests >= 1);
    // Reset for the restore: no leftover transform or fade, placement exactly as before the swipe.
    try std.testing.expectEqual(@as(f32, 0), f.offsetY());
    try std.testing.expectEqual(@as(f32, 1), f.card.node.getOpacity());
    try std.testing.expectEqualDeep(kept, f.placement.desired.?);
    // Restore (existing transition): back where it was docked.
    f.shown = true;
    f.card.present(.{ .shown = true, .tab = 1, .current_tab = 1, .explicit = true, .anchor = anchor });
    try std.testing.expectEqualStrings("anchor", f.card.anchorLabel());
    f.settle();
    try std.testing.expectEqual(ui.fx.anchor_transition.Phase.expanded, f.card.phase());
    try std.testing.expectEqualDeep(docked, f.rect());
}

test "swipe layer: a slow drag a third past the bottom collapses; less springs back in 180 ms" {
    var f: Fixture = undefined;
    try f.init(fixture);
    defer f.deinit();
    f.dock();
    const docked = f.rect();
    // 60 px slowly (100 px/s), pause: < 1/3 of 300 → spring back.
    f.gesture(0, 60, 6, 100, 100, false);
    try std.testing.expectEqual(@as(usize, 0), f.minimized);
    try std.testing.expectEqual(ui.fx.anchor_transition.Phase.expanded, f.card.phase());
    var frames: usize = 0;
    var last = f.offsetY();
    try std.testing.expect(last > 50);
    while (f.offsetY() > 0.01 and frames < 30) : (frames += 1) {
        f.frame();
        try std.testing.expect(f.offsetY() <= last);
        last = f.offsetY();
    }
    try std.testing.expect(frames >= 9 and frames <= 14);
    f.settle();
    try std.testing.expectEqualDeep(docked, f.rect());
    try std.testing.expectEqual(@as(f32, 0), f.offsetY());
    // 110 px slowly: ≥ 1/3 → collapse although slow.
    f.gesture(0, 110, 11, 100, 100, false);
    try std.testing.expectEqual(@as(usize, 1), f.minimized);
    f.settle();
    try std.testing.expectEqual(ui.fx.anchor_transition.Phase.collapsed, f.card.phase());
}

test "swipe layer: not docked, under 8 px, horizontal-dominant: an ordinary drag, never a collapse" {
    var f: Fixture = undefined;
    try f.init(fixture);
    defer f.deinit();
    // Not docked: a fast downward fling is an ordinary drag + inertia (JmcNv), no overshoot, no collapse.
    f.gesture(0, -300, 6, 50, 100, false);
    f.settle();
    const start = f.rect();
    try std.testing.expect(!float_swipe.docked(float_swipe.tokens, start, f.card.viewBottom()));
    f.gesture(0, 30, 3, 5, 0, false);
    try std.testing.expectEqual(@as(usize, 0), f.minimized);
    try std.testing.expect(f.card.gliding());
    // Drawn from the release point on (one frame in), never past the landing rectangle.
    try std.testing.expect(f.card.presentedRect().y > start.y + 30 and f.card.presentedRect().y < f.placement.desired.?.y);
    _ = f.glideOut();
    try std.testing.expectEqual(@as(usize, 0), f.minimized);
    try std.testing.expectApproxEqAbs(start.y + 30 + float_swipe.decayDistance(float_swipe.tokens, 2000, 0.7), f.rect().y, 0.5);
    try std.testing.expectEqual(@as(f32, 0), f.offsetY());
    try std.testing.expect(!float_swipe.docked(float_swipe.tokens, f.rect(), f.card.viewBottom()));
    f.dock();
    const docked = f.rect();
    // A 6 px flick (fast) is no decision.
    f.gesture(0, 6, 2, 2, 0, false);
    try std.testing.expectEqual(@as(usize, 0), f.minimized);
    f.settle();
    try std.testing.expectEqualDeep(docked, f.rect());
    // Mostly sideways (fast): moves sideways, springs back down, no collapse.
    f.gesture(-200, 120, 6, 5, 0, false);
    try std.testing.expectEqual(@as(usize, 0), f.minimized);
    f.settle();
    try std.testing.expectApproxEqAbs(docked.x - 200, f.rect().x, 0.5);
    try std.testing.expectApproxEqAbs(docked.y, f.rect().y, 0.5);
    try std.testing.expectEqual(@as(f32, 0), f.offsetY());
}

test "swipe layer: a card without minimize (terminal session card) springs back from a fling" {
    var plain = fixture;
    plain.interactions.remove(.minimize);
    var f: Fixture = undefined;
    try f.init(plain);
    defer f.deinit();
    try std.testing.expect(!f.card.descriptor.supports(.swipe_collapse));
    f.dock();
    const docked = f.rect();
    f.gesture(0, 200, 4, 5, 0, true);
    // Follows the pointer past the bottom like every grip card…
    try std.testing.expectApproxEqAbs(@as(f32, 200), f.offsetY(), 0.5);
    f.release(0, 200);
    // …and springs back.
    try std.testing.expectEqual(@as(usize, 0), f.minimized);
    try std.testing.expect(f.offsetY() > 100);
    f.settle();
    try std.testing.expectEqual(@as(f32, 0), f.offsetY());
    try std.testing.expectEqualDeep(docked, f.rect());
    try std.testing.expectEqual(ui.fx.anchor_transition.Phase.expanded, f.card.phase());
}

test "swipe layer reduce motion: no displacement animation, a 120 ms fade out; spring back is immediate" {
    var f: Fixture = undefined;
    try f.init(fixture);
    defer f.deinit();
    f.cx.reduced_motion = true;
    f.dock();
    const docked = f.rect();
    // Spring back: no animation.
    f.gesture(0, 50, 5, 100, 100, false);
    try std.testing.expectEqual(@as(usize, 0), f.minimized);
    f.frame();
    try std.testing.expectEqual(@as(f32, 0), f.offsetY());
    try std.testing.expectEqualDeep(docked, f.rect());
    // Collapse: the card stays where it was let go and only fades (120 ms).
    f.gesture(0, 120, 6, 5, 0, false);
    try std.testing.expectEqual(@as(usize, 1), f.minimized);
    try std.testing.expect(f.card.swipeReduced());
    const held_y = f.card.presentedRect().y;
    var frames: usize = 0;
    var faded = false;
    while (f.card.phase() == .collapsing and frames < 30) : (frames += 1) {
        f.frame();
        if (f.card.phase() != .collapsing) break;
        try std.testing.expectApproxEqAbs(held_y, f.card.presentedRect().y, 0.5);
        if (f.card.presentedOpacity() < 0.9) faded = true;
    }
    try std.testing.expect(faded);
    try std.testing.expect(frames >= 6 and frames <= 10);
    f.settle();
    try std.testing.expectEqual(ui.fx.anchor_transition.Phase.collapsed, f.card.phase());
}

test "swipe layer: reopening mid slide ends the slide and unfolds as usual" {
    var f: Fixture = undefined;
    try f.init(fixture);
    defer f.deinit();
    f.dock();
    const docked = f.rect();
    f.gesture(0, 120, 6, 5, 0, false);
    f.frame();
    try std.testing.expectEqual(ui.fx.anchor_transition.Phase.collapsing, f.card.phase());
    f.shown = true;
    f.card.present(.{ .shown = true, .tab = 1, .current_tab = 1, .explicit = true, .anchor = anchor });
    f.settle();
    try std.testing.expectEqual(ui.fx.anchor_transition.Phase.expanded, f.card.phase());
    try std.testing.expectEqual(@as(f32, 0), f.offsetY());
    try std.testing.expectEqual(@as(f32, 1), f.card.node.getOpacity());
    try std.testing.expectEqualDeep(docked, f.rect());
}

test "swipe chrome: the held grip fills with bg-hover and its native Grabber turns accent and 48 wide" {
    const cx = try ui.Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    cx.setViewport(800, 600);
    const scope = try ui.Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    const chrome = try chrome_mod.Chrome.mount(cx, scope, .{ .title = "AI 助手", .icon = ui.icons.sparkles, .descriptor = fixture, .ids = .{} });
    const holder = try ui.box(cx, .{ .position = .absolute, .width = .{ .px = 420 }, .height = .{ .px = 300 }, .direction = .column }, .{});
    try holder.appendChild(cx.allocator, chrome.root);
    try cx.root.?.appendChild(cx.allocator, holder);
    for (0..4) |_| {
        cx.layout();
        _ = cx.render();
    }
    const grabber = chrome.grip.children.items[0];
    try std.testing.expectEqualStrings("float.grabber", grabber.meta.ownership.meta.test_id.?);
    try std.testing.expectEqual(@as(f32, 36), grabber.globalRect().w);
    try std.testing.expect(ui.Color.eql(cx.tokens.tokens.color.fg_tertiary, grabber.getBackground()));
    chrome.setGripHeld(true);
    cx.layout();
    _ = cx.render();
    try std.testing.expectEqual(@as(f32, 48), grabber.globalRect().w);
    try std.testing.expect(ui.Color.eql(cx.tokens.tokens.color.accent, grabber.getBackground()));
    try std.testing.expect(ui.Color.eql(cx.tokens.tokens.color.bg_hover, chrome.grip.getBackground()));
    chrome.setGripHeld(false);
    cx.layout();
    _ = cx.render();
    try std.testing.expectEqual(@as(f32, 36), grabber.globalRect().w);
    try std.testing.expect(!ui.Color.eql(cx.tokens.tokens.color.bg_hover, chrome.grip.getBackground()));
}

// ── Inertia of an ordinary drag (JmcNv: "not docked: an ordinary drag + inertia") ──────────────

/// Lift the card off the bottom with a slow drag (no fling), so it is not docked.
fn lift(f: *Fixture) model.Rect {
    f.gesture(-300, -250, 5, 60, 100, false);
    f.settle();
    const r = f.rect();
    std.debug.assert(!float_swipe.docked(float_swipe.tokens, r, f.card.viewBottom()));
    return r;
}

test "glide layer: a fast release glides on, decelerating, lands where the decay ends and is remembered" {
    var f: Fixture = undefined;
    try f.init(fixture);
    defer f.deinit();
    const start = lift(&f);
    try std.testing.expect(!f.card.gliding());
    // 120 px left in 40 ms (3000 px/s over the last 80 ms), released without a pause.
    f.gesture(-120, 0, 4, 10, 0, false);
    try std.testing.expect(f.card.gliding());
    try std.testing.expectEqual(@as(usize, 0), f.minimized);
    const expected = start.x - 120 - float_swipe.decayDistance(float_swipe.tokens, 3000, 0.7);
    // Placement is already the landing rectangle (remembered); the card is drawn from where it was
    // let go (one 16 ms frame at ≈ 3000 px/s into the glide: ≈ 45 px on).
    try std.testing.expectApproxEqAbs(expected, f.placement.desired.?.x, 0.5);
    const first_step = start.x - 120 - f.presented().x;
    try std.testing.expect(first_step > 30 and first_step < 60);
    var xs: [64]f32 = undefined;
    var last = f.presented().x;
    var frames: usize = 0;
    while (f.card.gliding() and frames < 64) : (frames += 1) {
        f.frame();
        const x = f.presented().x;
        try std.testing.expect(last - x >= -0.01); // keeps going left, never back
        try std.testing.expect(x >= expected - 0.5); // never past the landing point
        xs[frames] = x;
        last = x;
    }
    // 700 ms at 16 ms frames.
    try std.testing.expect(frames >= 40 and frames <= 48);
    // Decelerates: each 80 ms window covers less than the one before (exponential: ≈ ×0.45).
    var prev_span: f32 = std.math.inf(f32);
    var i: usize = 0;
    while (i + 5 < frames) : (i += 5) {
        const span = xs[i] - xs[i + 5];
        try std.testing.expect(span <= prev_span + 0.01);
        prev_span = span;
    }
    try std.testing.expect(xs[0] - xs[5] > 6 * (xs[15] - xs[20]));
    f.frame();
    try std.testing.expect(!f.card.gliding());
    try std.testing.expectApproxEqAbs(expected, f.rect().x, 0.5);
    try std.testing.expectApproxEqAbs(start.y, f.rect().y, 0.5);
    try std.testing.expectEqual(@as(f32, 0), f.card.node.style.translate_x);
    try std.testing.expectEqualDeep(f.rect(), f.placement.desired.?);
    // Remembered like any drop: closed and reopened, it comes back there.
    const kept = f.placement.desired.?;
    f.placement.closed(f.card.descriptor);
    try std.testing.expectEqualDeep(kept, f.placement.desired.?);
}

test "glide layer: flung at the region edge it stops on the edge, never past it, no bounce" {
    var f: Fixture = undefined;
    try f.init(fixture);
    defer f.deinit();
    _ = lift(&f);
    // Up and left, far faster than the cap: both axes run into the region's top-left.
    f.gesture(-100, -60, 2, 5, 0, false);
    try std.testing.expect(f.card.gliding());
    var frames: usize = 0;
    var min_x: f32 = std.math.inf(f32);
    var min_y: f32 = std.math.inf(f32);
    while (f.card.gliding() and frames < 64) : (frames += 1) {
        f.frame();
        min_x = @min(min_x, f.presented().x);
        min_y = @min(min_y, f.presented().y);
    }
    f.frame();
    try std.testing.expect(frames < 44); // reached the edges before the full 700 ms
    try std.testing.expectApproxEqAbs(region.x, f.rect().x, 0.01);
    try std.testing.expectApproxEqAbs(region.y, f.rect().y, 0.01);
    try std.testing.expect(min_x >= region.x - 0.01 and min_y >= region.y - 0.01);
    for (0..10) |_| f.frame();
    try std.testing.expectApproxEqAbs(region.x, f.presented().x, 0.01);
    try std.testing.expectApproxEqAbs(region.y, f.presented().y, 0.01);
}

test "glide layer: a slow drag, a pause before release, under 8 px or reduce motion: no glide" {
    var f: Fixture = undefined;
    try f.init(fixture);
    defer f.deinit();
    const start = lift(&f);
    // 100 px at 200 px/s.
    f.gesture(-100, 0, 10, 50, 0, false);
    try std.testing.expect(!f.card.gliding());
    try std.testing.expectApproxEqAbs(start.x - 100, f.rect().x, 0.5);
    // Fast, but held still for longer than the 80 ms window before letting go.
    f.gesture(-100, 0, 4, 5, 100, false);
    try std.testing.expect(!f.card.gliding());
    try std.testing.expectApproxEqAbs(start.x - 200, f.rect().x, 0.5);
    // A 6 px flick.
    f.gesture(-6, 0, 2, 2, 0, false);
    try std.testing.expect(!f.card.gliding());
    // Reduce motion: the fastest release stays where it is let go.
    f.cx.reduced_motion = true;
    const before = f.rect();
    f.gesture(-120, 0, 4, 10, 0, false);
    try std.testing.expect(!f.card.gliding());
    f.settle();
    try std.testing.expectApproxEqAbs(before.x - 120, f.rect().x, 0.5);
    try std.testing.expectEqualDeep(f.rect(), f.placement.desired.?);
}

test "glide layer: a press mid glide takes over where the card is drawn, without a jump" {
    var f: Fixture = undefined;
    try f.init(fixture);
    defer f.deinit();
    const start = lift(&f);
    f.gesture(-120, 0, 4, 10, 0, false);
    for (0..6) |_| f.frame();
    try std.testing.expect(f.card.gliding());
    const caught = f.presented();
    try std.testing.expect(caught.x < start.x - 125);
    // Press on the grip where it is drawn now: the glide stops there; layout and drawing agree.
    const g = f.grip.globalRect();
    f.cx.handleMouseDown(g.x + g.w / 2, g.y + g.h / 2, .{});
    try std.testing.expect(!f.card.gliding());
    f.frame();
    try std.testing.expectApproxEqAbs(caught.x, f.presented().x, 0.01);
    try std.testing.expectApproxEqAbs(caught.x, f.rect().x, 0.01);
    try std.testing.expectEqual(@as(f32, 0), f.card.node.style.translate_x);
    try std.testing.expectApproxEqAbs(caught.x, f.placement.desired.?.x, 0.01);
    // The drag that follows moves from there (slowly, then a pause: no new glide).
    for (1..6) |i| {
        f.now_ns += 50 * ms;
        f.cx.handleMouseMove(g.x + g.w / 2 + 8 * @as(f32, @floatFromInt(i)), g.y + g.h / 2);
        f.frame();
        try std.testing.expectApproxEqAbs(caught.x + 8 * @as(f32, @floatFromInt(i)), f.presented().x, 0.01);
    }
    f.now_ns += 100 * ms;
    f.cx.handleMouseUp(g.x + g.w / 2 + 40, g.y + g.h / 2);
    f.frame();
    try std.testing.expect(!f.card.gliding());
    try std.testing.expectApproxEqAbs(caught.x + 40, f.rect().x, 0.01);
}

test "glide layer: a docked downward fling still collapses (swipe first); a docked sideways fling glides" {
    var f: Fixture = undefined;
    try f.init(fixture);
    defer f.deinit();
    f.dock();
    const docked = f.rect();
    // Sideways along the bottom (nothing past the bottom to spring back): an ordinary drag + inertia.
    f.gesture(-120, 0, 4, 10, 0, false);
    try std.testing.expect(f.card.gliding());
    _ = f.glideOut();
    try std.testing.expectApproxEqAbs(docked.x - 120 - float_swipe.decayDistance(float_swipe.tokens, 3000, 0.7), f.rect().x, 0.5);
    try std.testing.expectApproxEqAbs(docked.y, f.rect().y, 0.5);
    // Downward fling from docked: collapse, no glide.
    f.gesture(0, 120, 6, 5, 0, false);
    try std.testing.expect(!f.card.gliding());
    try std.testing.expectEqual(@as(usize, 1), f.minimized);
    try std.testing.expectEqual(ui.fx.anchor_transition.Phase.collapsing, f.card.phase());
}
