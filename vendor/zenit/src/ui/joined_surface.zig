//! `W.JoinedSurface`: a box whose paint shape is a joined outline (docs/design/joined-surface.md
//! §4.3), for folder tabs joined to their panel, selection highlights and the like.
//!
//! The surface is its own layer: lay its box out over the union of its members (typically an
//! absolutely positioned box filling the members' common ancestor, under the content). Members
//! are other nodes, read from layout every frame, or explicit rectangles; both are mapped into the
//! box. The box paints its own style along the outline (`Node.setShapePath`): the background
//! fills it, a uniform border strokes it on the inside, an `.auto` hit shape follows it, and token
//! colors follow the theme like any box.
//!
//! Initial members appear at their laid-out rectangles on the first frame.
//! When a member's target changes (another node, another rectangle, appearing, leaving), the
//! member's rectangle moves from what is on screen to the new target over `motion`, and the
//! outline is solved again every frame, so every frame of the morph obeys the shrinking and
//! concentric rules. Layout changes of the same target are followed directly. A node target that
//! was released keeps its last rectangle until it is replaced, so a component that rebuilds its
//! nodes reads as one retarget rather than a collapse and an expansion.
const std = @import("std");
const core = @import("core.zig");
const joined = @import("joined.zig");
const easing_mod = @import("animation/easing.zig");
const render_engine = @import("core/render_engine/mod.zig");
const anchor_transition = @import("anchor_transition.zig");
const reactive = @import("reactive.zig");

const Node = core.Node;
const Cx = core.Cx;
const Scope = reactive.Scope;

pub const Rect = joined.Rect;
pub const Axis = joined.Axis;

/// Where a member's rectangle comes from.
pub const Target = union(enum) {
    /// Absent. A member turning absent shrinks into its join, then drops out.
    none,
    /// Another node's layout rectangle (see `targetOf`).
    node: core.NodeHandle,
    /// A rectangle in this box's local coordinates.
    rect: Rect,

    pub fn eql(a: Target, b: Target) bool {
        return switch (a) {
            .none => b == .none,
            .node => |h| b == .node and b.node.id == h.id and b.node.generation == h.generation,
            .rect => |r| b == .rect and joined.rectEql(b.rect, r),
        };
    }
};

pub const Member = struct {
    target: Target,
    /// Corner radii TL, TR, BR, BL of this member (see `joined.Member`).
    radii: [4]f32 = @splat(0),
};

pub const Motion = struct {
    /// Seconds; null takes the theme's `duration.slow`.
    duration_s: ?f32 = null,
    easing: easing_mod.Easing = .ease_out_cubic,
};

pub const Props = struct {
    axis: Axis = .vertical,
    members: []const Member = &.{},
    join_radius: f32 = 0,
    motion: Motion = .{},
};

/// `Target.node` for `node` (tracks its generation: a recycled node never matches).
pub fn targetOf(cx: *Cx, node: *Node) !Target {
    return .{ .node = .{ .id = node.id, .generation = try cx.node_registry.trackGeneration(node) } };
}

const MemberState = struct {
    target: Target,
    radii: [4]f32,
    /// Rectangle shown last frame (local coordinates); null while absent.
    shown: ?Rect = null,
    /// Running transition: start rectangle (null = grow out of the join) and start time (null =
    /// stamped by the next frame, on that window's clock).
    animating: bool = false,
    from: ?Rect = null,
    start_ms: ?f64 = null,
    /// Rectangle a leaving member shrinks from.
    leave_from: ?Rect = null,
};

pub const Surface = struct {
    node: *Node,
    node_handle: core.NodeHandle,
    cx: *Cx,
    allocator: std.mem.Allocator,
    axis: Axis,
    join_radius: f32,
    motion: Motion,
    members: std.ArrayList(MemberState) = .empty,
    chain: std.ArrayList(joined.Member) = .empty,
    anchors: std.ArrayList(?Rect) = .empty,
    outline: joined.Outline = .{},
    border: joined.Outline = .{},
    shown_outline: joined.Outline = .{},
    shown_border_width: f32 = -1,
    needs_solve: bool = true,
    fill_commands: std.ArrayList(core.PathCommand) = .empty,
    border_commands: std.ArrayList(core.PathCommand) = .empty,
    /// A transition is running (the frame hook keeps requesting frames).
    active: bool = false,
    warned_bounds: bool = false,

    /// Replace the members. A member whose target changed moves from what is on screen to the new
    /// target; members beyond the old count appear (grow out of their join).
    pub fn setMembers(self: *Surface, members: []const Member) !void {
        const old_len = self.members.items.len;
        try self.members.resize(self.allocator, members.len);
        for (members, 0..) |m, i| {
            const st = &self.members.items[i];
            if (i >= old_len) {
                st.* = .{ .target = m.target, .radii = m.radii, .animating = m.target != .none };
                continue;
            }
            st.radii = m.radii;
            if (st.target.eql(m.target)) continue;
            st.target = m.target;
            if (m.target == .none) {
                st.leave_from = st.shown;
                st.from = st.shown;
                st.animating = st.shown != null;
            } else {
                st.leave_from = null;
                st.from = st.shown; // null: grow out of the join
                st.animating = true;
            }
            st.start_ms = null;
        }
        self.needs_solve = true;
        self.node.markRenderDirty();
    }

    pub fn setJoinRadius(self: *Surface, radius: f32) void {
        if (self.join_radius == radius) return;
        self.join_radius = radius;
        self.needs_solve = true;
        self.node.markRenderDirty();
    }

    pub fn setMotion(self: *Surface, motion: Motion) void {
        self.motion = motion;
    }

    /// The outline painted last frame (local coordinates).
    pub fn shownOutline(self: *const Surface) *const joined.Outline {
        return &self.shown_outline;
    }

    /// Member `index`'s rectangle as painted last frame (null while absent).
    pub fn shownRect(self: *const Surface, index: usize) ?Rect {
        if (index >= self.members.items.len) return null;
        return self.members.items[index].shown;
    }

    /// A transition is running.
    pub fn animating(self: *const Surface) bool {
        return self.active;
    }

    fn liveRect(self: *Surface, target: Target, origin: core.ComputedRect) ?Rect {
        return switch (target) {
            .none => null,
            .rect => |r| r,
            .node => |h| blk: {
                const n = self.cx.node_registry.resolveTracked(h) orelse break :blk null;
                if (!n.isDisplayedInTree()) break :blk null;
                const g = n.globalRect();
                break :blk .{ .x = g.x - origin.x, .y = g.y - origin.y, .w = g.w, .h = g.h };
            },
        };
    }

    /// The zero-extent rectangle a member grows out of / shrinks into: its span on the line where
    /// it joins the next member (the previous one for the last member).
    fn collapsed(self: *const Surface, index: usize, r: Rect) Rect {
        const anchors = self.anchors.items;
        var next: ?Rect = null;
        for (anchors[index + 1 ..]) |a| if (a) |rect| {
            next = rect;
            break;
        };
        return switch (self.axis) {
            .vertical => if (next) |n| .{ .x = r.x, .y = n.y, .w = r.w, .h = 0 } else .{ .x = r.x, .y = r.y, .w = r.w, .h = 0 },
            .horizontal => if (next) |n| .{ .x = n.x, .y = r.y, .w = 0, .h = r.h } else .{ .x = r.x, .y = r.y, .w = 0, .h = r.h },
        };
    }

    fn durationMs(self: *const Surface) f64 {
        const s = self.motion.duration_s orelse self.cx.tokensFor(self.node).tokens.duration.slow;
        return @as(f64, @max(0, s)) * 1000;
    }

    /// One frame: advance transitions, solve, publish the shape when it changed.
    pub fn step(self: *Surface) !void {
        const origin = self.node.globalRect();
        if (origin.w <= 0 or origin.h <= 0) {
            self.active = false;
            return;
        }
        const now = render_engine.current_frame_time_ms;
        const instant = anchor_transition.reducedMotion(self.cx);
        const duration = self.durationMs();
        const members = self.members.items;
        try self.anchors.resize(self.allocator, members.len);
        // Where each member is now (a released node holds its last rectangle).
        for (members, self.anchors.items) |st, *a| {
            a.* = self.liveRect(st.target, origin) orelse if (st.target == .node) st.shown else null;
        }
        self.chain.clearRetainingCapacity();
        self.active = false;
        for (members, 0..) |*st, i| {
            const goal: ?Rect = if (st.target == .none)
                (if (st.leave_from) |r| self.collapsed(i, r) else null)
            else
                self.anchors.items[i];
            var shown: ?Rect = if (st.target == .none) null else goal;
            if (st.animating) if (goal) |g| {
                const start = st.start_ms orelse now;
                st.start_ms = start;
                const t: f32 = if (instant or duration <= 0) 1 else @floatCast(std.math.clamp((now - start) / duration, 0, 1));
                const from = st.from orelse self.collapsed(i, g);
                shown = joined.rectLerp(from, g, self.motion.easing.apply(t));
                if (t >= 1) {
                    st.animating = false;
                    if (st.target == .none) {
                        shown = null;
                        st.leave_from = null;
                    }
                } else self.active = true;
            };
            if (!std.meta.eql(st.shown, shown)) self.needs_solve = true;
            st.shown = shown;
            if (shown) |r| try self.chain.append(self.allocator, .{ .rect = r, .radii = st.radii });
        }
        const bw = self.borderWidth();
        if (!self.needs_solve and bw == self.shown_border_width) return;
        try self.outline.solve(self.allocator, .{ .axis = self.axis, .members = self.chain.items, .join_radius = self.join_radius }, 0);
        if (self.outline.eql(&self.shown_outline) and bw == self.shown_border_width) {
            self.needs_solve = false;
            return;
        }
        self.checkBounds(origin);
        self.fill_commands.clearRetainingCapacity();
        try self.outline.appendPath(self.allocator, &self.fill_commands);
        self.border_commands.clearRetainingCapacity();
        var border: ?core.PathGeometry = null;
        if (bw > 0) {
            try self.border.solve(self.allocator, .{ .axis = self.axis, .members = self.chain.items, .join_radius = self.join_radius }, bw / 2);
            try self.border.appendPath(self.allocator, &self.border_commands);
            border = joined.geometry(self.border_commands.items, &self.border);
        }
        try self.node.setShapePath(self.allocator, joined.geometry(self.fill_commands.items, &self.outline), border);
        std.mem.swap(joined.Outline, &self.outline, &self.shown_outline);
        self.shown_border_width = bw;
        self.needs_solve = false;
    }

    fn checkBounds(self: *Surface, origin: core.ComputedRect) void {
        if (self.warned_bounds or self.outline.vertices.items.len == 0) return;
        const b = self.outline.bounds();
        const slack: f32 = 0.5;
        if (b.x < -slack or b.y < -slack or b.x + b.w > origin.w + slack or b.y + b.h > origin.h + slack) {
            self.warned_bounds = true;
            std.log.warn("[JoinedSurface] outline ({d:.1},{d:.1} {d:.1}x{d:.1}) exceeds the surface box ({d:.1}x{d:.1}): lay the box out over all members, or parts are culled and miss hits", .{ b.x, b.y, b.w, b.h, origin.w, origin.h });
        }
    }

    fn borderWidth(self: *const Surface) f32 {
        const b = self.node.style.border;
        if (b.color.a == 0) return 0;
        return @max(0, b.resolvedWidths()[core.Border.SIDE_TOP]);
    }

    fn deinit(self: *Surface) void {
        self.members.deinit(self.allocator);
        self.chain.deinit(self.allocator);
        self.anchors.deinit(self.allocator);
        self.outline.deinit(self.allocator);
        self.border.deinit(self.allocator);
        self.shown_outline.deinit(self.allocator);
        self.fill_commands.deinit(self.allocator);
        self.border_commands.deinit(self.allocator);
    }
};

/// Mount a joined surface box with `style` (its background / border paint the outline). Lay it
/// out over the union of its members.
pub fn JoinedSurface(scope: *Scope, cx: *Cx, style: core.BoxStyle, props: Props) !*Surface {
    const node = try core.box(cx, style, .{});
    errdefer cx.freeNode(node);
    return attach(scope, cx, node, props);
}

/// Turn a box into a joined surface owned by `scope`. An empty chain paints nothing.
pub fn attach(scope: *Scope, cx: *Cx, node: *Node, props: Props) !*Surface {
    if (node.meta.per_frame.hooks.slots.anim_state != null) return error.SurfaceNodeAlreadyAnimated;
    const handle = (try targetOf(cx, node)).node;
    const self = try scope.allocator.create(Surface);
    self.* = .{ .node = node, .node_handle = handle, .cx = cx, .allocator = cx.allocator, .axis = props.axis, .join_radius = props.join_radius, .motion = props.motion };
    errdefer scope.allocator.destroy(self);
    errdefer self.deinit();
    try self.setMembers(props.members);
    for (self.members.items) |*member| member.animating = false;
    // Empty until the first frame solves it: never paint the plain rectangle.
    try node.setShapePath(cx.allocator, .{}, null);
    errdefer node.clearShapePath(cx.allocator);
    try scope.adoptResource(@ptrCast(self), struct {
        fn destroy(ptr: *anyopaque, alloc: std.mem.Allocator) void {
            const s: *Surface = @ptrCast(@alignCast(ptr));
            if (s.cx.node_registry.resolveTracked(s.node_handle)) |live| {
                if (live.meta.per_frame.hooks.slots.anim_state == @as(?*anyopaque, @ptrCast(s))) {
                    live.meta.per_frame.hooks.slots.anim_state = null;
                    live.removeBeforeRender(beforeRender);
                    live.clearShapePath(s.allocator);
                }
            }
            s.deinit();
            alloc.destroy(s);
        }
    }.destroy);
    node.meta.per_frame.hooks.slots.anim_state = @ptrCast(self);
    node.addBeforeRenderScoped(beforeRender, .dirty_marking);
    node.meta.ownership.meta.component_name = "JoinedSurface";
    return self;
}

fn beforeRender(node: *Node) void {
    const self: *Surface = @ptrCast(@alignCast(node.meta.per_frame.hooks.slots.anim_state orelse return));
    self.step() catch |err| std.log.err("[JoinedSurface] frame failed: {}", .{err});
    if (self.active) node.markRenderDirty();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = std.testing;

const Fixture = struct {
    cx: *Cx,
    scope: *Scope,
    root: *Node,
    tabs: [2]*Node,
    panel: *Node,
    surface: *Surface,

    fn at(cx: *Cx, x: f32, y: f32, w: f32, h: f32) !*Node {
        return core.box(cx, .{ .position = .absolute, .inset = .{ .left = .{ .px = x }, .top = .{ .px = y } }, .width = .{ .px = w }, .height = .{ .px = h } }, .{});
    }

    fn init() !Fixture {
        const cx = try Cx.init(testing.allocator, testing.io);
        errdefer cx.deinit();
        cx.setViewport(400, 300);
        const scope = try Scope.init(testing.allocator, null, cx.owner);
        const root = try core.box(cx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
        cx.root = root;
        const tab_a = try at(cx, 40, 0, 100, 30);
        const tab_b = try at(cx, 200, 0, 100, 30);
        const panel = try at(cx, 0, 30, 400, 270);
        const surface = try JoinedSurface(scope, cx, .{ .position = .absolute, .inset = .{ .left = .{ .px = 0 }, .top = .{ .px = 0 } }, .width = .{ .px = 400 }, .height = .{ .px = 300 }, .background = core.Color.rgba(250, 250, 250, 255), .hit_behavior = .@"opaque" }, .{
            .members = &.{ .{ .target = try targetOf(cx, tab_a), .radii = @splat(10) }, .{ .target = try targetOf(cx, panel), .radii = @splat(12) } },
            .join_radius = 10,
            .motion = .{ .duration_s = 0.2, .easing = .linear },
        });
        try root.appendChild(cx.allocator, surface.node);
        for ([_]*Node{ tab_a, tab_b, panel }) |n| try root.appendChild(cx.allocator, n);
        return .{ .cx = cx, .scope = scope, .root = root, .tabs = .{ tab_a, tab_b }, .panel = panel, .surface = surface };
    }

    fn deinit(self: *Fixture) void {
        self.scope.dispose();
        self.cx.deinit();
    }

    fn frame(self: *Fixture, now_ms: f64) !void {
        render_engine.current_frame_time_ms = now_ms;
        self.cx.layout();
        try self.surface.step();
    }
};

fn expectRect(expected: Rect, actual: ?Rect) !void {
    const a = actual orelse return error.TestExpectedRect;
    try testing.expectApproxEqAbs(expected.x, a.x, 1e-3);
    try testing.expectApproxEqAbs(expected.y, a.y, 1e-3);
    try testing.expectApproxEqAbs(expected.w, a.w, 1e-3);
    try testing.expectApproxEqAbs(expected.h, a.h, 1e-3);
}

test "joined surface: members follow layout without animating, and the box paints and hits the outline" {
    const saved = render_engine.saveFrameClock();
    defer render_engine.restoreFrameClock(saved);
    var f = try Fixture.init();
    defer f.deinit();
    try f.surface.step();
    try testing.expect(f.surface.shownRect(0) == null);
    try f.frame(0);
    // Existing content is visible on the first laid-out frame.
    try expectRect(.{ .x = 40, .y = 0, .w = 100, .h = 30 }, f.surface.shownRect(0));
    try expectRect(.{ .x = 0, .y = 30, .w = 400, .h = 270 }, f.surface.shownRect(1));
    try testing.expect(!f.surface.animating());
    try testing.expect(f.surface.node.shapePath() != null);
    // Same target moved by layout: followed in the same frame.
    f.tabs[0].setStyleInline(f.cx.allocator, .{ .inset = .{ .left = .{ .px = 60 }, .top = .{ .px = 0 } } });
    try f.frame(210);
    try expectRect(.{ .x = 60, .y = 0, .w = 100, .h = 30 }, f.surface.shownRect(0));
    try testing.expect(!f.surface.animating());
    // Hits follow the outline: on the tab yes, beside it (above the panel) no.
    _ = f.cx.render();
    try testing.expect(f.cx.hitTest(100, 15) == f.surface.node);
    try testing.expect(f.cx.hitTest(10, 15) != f.surface.node);
}

test "joined surface: a new target morphs from what is on screen, every frame a solved outline" {
    const saved = render_engine.saveFrameClock();
    defer render_engine.restoreFrameClock(saved);
    var f = try Fixture.init();
    defer f.deinit();
    try f.frame(0);
    try f.frame(500);
    try f.surface.setMembers(&.{ .{ .target = try targetOf(f.cx, f.tabs[1]), .radii = @splat(10) }, .{ .target = try targetOf(f.cx, f.panel), .radii = @splat(12) } });
    try f.frame(1000); // stamps the start on this frame's clock
    try expectRect(.{ .x = 40, .y = 0, .w = 100, .h = 30 }, f.surface.shownRect(0));
    var last_x: f32 = 40;
    var t: f64 = 1020;
    while (t < 1200) : (t += 20) {
        try f.frame(t);
        const x = f.surface.shownRect(0).?.x;
        try testing.expect(x > last_x and x < 200);
        last_x = x;
        try testing.expect(f.surface.animating());
        // Mid-morph the outline is still one contour with both joins.
        try testing.expectEqual(@as(usize, 1), f.surface.shownOutline().contours.items.len);
        try testing.expectEqual(@as(usize, 8), f.surface.shownOutline().vertices.items.len);
    }
    try f.frame(1200);
    try expectRect(.{ .x = 200, .y = 0, .w = 100, .h = 30 }, f.surface.shownRect(0));
    try testing.expect(!f.surface.animating());
    // Retarget mid-way back: continues from the current rectangle, no jump.
    try f.surface.setMembers(&.{ .{ .target = try targetOf(f.cx, f.tabs[0]), .radii = @splat(10) }, .{ .target = try targetOf(f.cx, f.panel), .radii = @splat(12) } });
    try f.frame(2000);
    try f.frame(2100);
    const mid = f.surface.shownRect(0).?.x;
    try f.surface.setMembers(&.{ .{ .target = try targetOf(f.cx, f.tabs[1]), .radii = @splat(10) }, .{ .target = try targetOf(f.cx, f.panel), .radii = @splat(12) } });
    try f.frame(2110);
    try testing.expectApproxEqAbs(mid, f.surface.shownRect(0).?.x, 1e-3);
}

test "joined surface: reduced motion lands at once; a leaving member shrinks into its join" {
    const saved = render_engine.saveFrameClock();
    defer render_engine.restoreFrameClock(saved);
    var f = try Fixture.init();
    defer f.deinit();
    try f.frame(0);
    try f.frame(500);
    f.cx.reduced_motion = true;
    try f.surface.setMembers(&.{ .{ .target = try targetOf(f.cx, f.tabs[1]), .radii = @splat(10) }, .{ .target = try targetOf(f.cx, f.panel), .radii = @splat(12) } });
    try f.frame(510);
    try expectRect(.{ .x = 200, .y = 0, .w = 100, .h = 30 }, f.surface.shownRect(0));
    f.cx.reduced_motion = false;
    try f.surface.setMembers(&.{ .{ .target = .none, .radii = @splat(10) }, .{ .target = try targetOf(f.cx, f.panel), .radii = @splat(12) } });
    try f.frame(1000);
    try f.frame(1100);
    const half = f.surface.shownRect(0).?;
    try testing.expectApproxEqAbs(@as(f32, 15), half.h, 1e-3);
    try testing.expectApproxEqAbs(@as(f32, 30), half.y + half.h, 1e-3); // bottom stays on the join
    try f.frame(1200);
    try testing.expect(f.surface.shownRect(0) == null);
    // Only the panel is left: a plain rounded rectangle.
    try testing.expectEqual(@as(usize, 4), f.surface.shownOutline().vertices.items.len);
}

test "joined surface: a released node holds its rectangle until replaced, then retargets" {
    const saved = render_engine.saveFrameClock();
    defer render_engine.restoreFrameClock(saved);
    var f = try Fixture.init();
    defer f.deinit();
    try f.frame(0);
    try f.frame(500);
    f.root.removeChild(f.tabs[0]);
    f.cx.freeNode(f.tabs[0]);
    try f.frame(600);
    try expectRect(.{ .x = 40, .y = 0, .w = 100, .h = 30 }, f.surface.shownRect(0));
    try testing.expect(!f.surface.animating());
    try f.surface.setMembers(&.{ .{ .target = try targetOf(f.cx, f.tabs[1]), .radii = @splat(10) }, .{ .target = try targetOf(f.cx, f.panel), .radii = @splat(12) } });
    try f.frame(700);
    try expectRect(.{ .x = 40, .y = 0, .w = 100, .h = 30 }, f.surface.shownRect(0));
    try f.frame(900);
    try expectRect(.{ .x = 200, .y = 0, .w = 100, .h = 30 }, f.surface.shownRect(0));
}

test "joined surface: its paint box can be freed before the owning scope" {
    var f = try Fixture.init();
    defer f.deinit();
    f.root.removeChild(f.surface.node);
    f.cx.freeNode(f.surface.node);
}
