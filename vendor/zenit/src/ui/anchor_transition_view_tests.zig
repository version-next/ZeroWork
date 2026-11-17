//! Anchor transitions through ui.view (`motion_anchor` / `anchor_collapsed` / `anchor_to` /
//! `anchor_rect` / `anchor_motion`, Yix motionAnchor / anchorCollapsed / anchorTo / anchorRect /
//! anchorMotion) without a window. Design: docs/ANCHOR_TRANSITION.md.
const std = @import("std");
const testing = std.testing;
const core = @import("core.zig");
const reactive = @import("reactive.zig");
const theme = @import("theme.zig");
const v = @import("view.zig");
const anchor_transition = @import("anchor_transition.zig");
const Node = core.Node;
const Cx = core.Cx;
const Scope = reactive.Scope;

const Env = struct {
    cx: *Cx,
    scope: *Scope,
    root: ?*Node = null,
    now: f64 = 0,

    fn init() !Env {
        const cx = try Cx.init(testing.allocator, std.testing.io);
        cx.tokens = &theme.light;
        cx.setViewport(400, 300);
        const scope = try Scope.init(testing.allocator, null, cx.owner);
        return .{ .cx = cx, .scope = scope };
    }

    fn mount(e: *Env, element: anytype) !*Node {
        const root = try v.render(e.scope, e.cx, element);
        e.root = root;
        e.cx.root = root;
        e.cx.content_root = root;
        e.frame(0);
        return root;
    }

    fn frame(e: *Env, ms: f64) void {
        e.now = ms;
        e.cx.frame_time_ms = ms;
        e.cx.frame_dt_ms = 16;
        e.cx.requestRedraw();
        _ = e.cx.render();
        _ = e.cx.drainDeferredWork(e.cx.deferredBudgetUs());
    }

    fn run(e: *Env, ms: f64) void {
        const end = e.now + ms;
        while (e.now < end) e.frame(e.now + 16);
    }

    fn layers(e: *Env) usize {
        var n: usize = 0;
        for (e.root.?.children.items) |c| {
            if (c.meta.ownership.meta.component_name) |name| {
                if (std.mem.eql(u8, name, "AnchorTransitionLayer")) n += 1;
            }
        }
        if (e.cx.root) |r| if (r != e.root.?) for (r.children.items) |c| {
            if (c.meta.ownership.meta.component_name) |name| {
                if (std.mem.eql(u8, name, "AnchorTransitionLayer")) n += 1;
            }
        };
        return n;
    }

    fn deinit(e: *Env) void {
        e.scope.dispose();
        e.cx.root = null;
        e.cx.content_root = null;
        if (e.root) |r| e.cx.freeNode(r);
        e.cx.deinit();
    }
};

fn findTestId(n: *Node, id: []const u8) ?*Node {
    if (n.meta.ownership.meta.test_id) |t| if (std.mem.eql(u8, t, id)) return n;
    for (n.children.items) |c| if (findTestId(c, id)) |r| return r;
    return null;
}

fn card(e: *Env) *Node {
    return findTestId(e.root.?, "card").?;
}

test "ui.view anchor_collapsed: collapses into a named motion_anchor and expands back" {
    var e = try Env.init();
    defer e.deinit();
    const away = try e.scope.createSignal(bool, false);
    _ = try e.mount(v.box(.{ .style = .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } } }, .{
        v.box(.{ .test_id = "tab", .motion_anchor = "tab-1", .style = .{ .position = .absolute, .width = .{ .px = 40 }, .height = .{ .px = 20 }, .translate_x = 20, .translate_y = 10 } }, .{}),
        v.box(.{ .test_id = "card", .anchor_collapsed = away, .anchor_to = "tab-1", .style = .{ .position = .absolute, .width = .{ .px = 120 }, .height = .{ .px = 80 }, .translate_x = 200, .translate_y = 150, .background = core.Color.rgb(200, 60, 60) } }, .{}),
    }));
    try testing.expect(e.cx.motion_anchors.lookup(e.cx, "tab-1") == findTestId(e.root.?, "tab").?);
    try testing.expectEqual(core.Display.flex, card(&e).style.display);

    away.set(true);
    e.frame(e.now + 16);
    try testing.expectEqual(@as(usize, 1), e.layers());
    try testing.expectEqual(@as(f32, 0), card(&e).getOpacity());
    e.run(500);
    try testing.expectEqual(core.Display.none, card(&e).style.display);
    try testing.expectEqual(@as(usize, 0), e.layers());

    away.set(false);
    e.frame(e.now + 16);
    e.frame(e.now + 16);
    // In flight only the texture is drawn: the out-of-flow card stays out of layout (after the
    // one-frame settle that renders it once more).
    try testing.expectEqual(core.Display.none, card(&e).style.display);
    try testing.expectEqual(@as(usize, 1), e.layers());
    e.run(500);
    try testing.expectEqual(core.Display.flex, card(&e).style.display);
    try testing.expectEqual(@as(f32, 1), card(&e).getOpacity());
    try testing.expectEqual(@as(usize, 0), e.layers());
}

test "ui.view anchor_collapsed: mount value is the initial state, no run" {
    var e = try Env.init();
    defer e.deinit();
    const away = try e.scope.createSignal(bool, true);
    const rect = try e.scope.createSignal(?v.AnchorRect, v.AnchorRect{ .x = 10, .y = 4, .w = 60, .h = 24 });
    var motion = anchor_transition.default_tokens;
    motion.reduced = .instant;
    _ = try e.mount(v.box(.{ .style = .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } } }, .{
        v.box(.{ .test_id = "card", .anchor_collapsed = away, .anchor_rect = rect, .anchor_motion = motion, .style = .{ .width = .{ .px = 120 }, .height = .{ .px = 80 } } }, .{}),
    }));
    try testing.expectEqual(core.Display.none, card(&e).style.display);
    try testing.expectEqual(@as(usize, 0), e.layers());
    // Tokens from anchor_motion reach the transition: reduce motion + .instant switches at once.
    e.cx.reduced_motion = true;
    away.set(false);
    try testing.expectEqual(core.Display.flex, card(&e).style.display);
    e.frame(e.now + 16);
    try testing.expectEqual(@as(usize, 0), e.layers());
}

test "ui.view anchor_collapsed: scope disposal mid-run frees the layer and gives the node back" {
    var e = try Env.init();
    defer e.deinit();
    const inner = try e.scope.childScope();
    const away = try inner.createSignal(bool, false);
    const name = try inner.createSignal([]const u8, "a");
    const root = try v.render(e.scope, e.cx, v.box(.{ .style = .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } } }, .{
        v.box(.{ .test_id = "tab", .motion_anchor = name, .style = .{ .position = .absolute, .width = .{ .px = 40 }, .height = .{ .px = 20 } } }, .{}),
    }));
    e.root = root;
    e.cx.root = root;
    e.cx.content_root = root;
    const host = try v.render(inner, e.cx, v.box(.{ .test_id = "card", .anchor_collapsed = away, .anchor_to = "b", .style = .{ .position = .absolute, .width = .{ .px = 120 }, .height = .{ .px = 80 }, .translate_x = 200, .translate_y = 150, .background = core.Color.rgb(60, 60, 200) } }, .{}));
    try root.appendChild(e.cx.allocator, host);
    e.frame(0);
    // A motion_anchor bound to a source follows it.
    try testing.expect(e.cx.motion_anchors.lookup(e.cx, "b") == null);
    name.set("b");
    try testing.expect(e.cx.motion_anchors.lookup(e.cx, "b") == findTestId(root, "tab").?);

    away.set(true);
    e.frame(16);
    e.frame(32);
    try testing.expectEqual(@as(usize, 1), e.layers());
    inner.dispose();
    try testing.expectEqual(@as(usize, 0), e.layers());
    try testing.expectEqual(core.Display.flex, host.style.display);
    try testing.expectEqual(@as(f32, 1), host.getOpacity());
    e.frame(48);
    e.cx.detachChild(root, host);
    e.cx.freeNode(host);
    e.frame(64);
    // Only the tab's registration (owned by the outer scope) is left.
    try testing.expectEqual(@as(usize, 1), e.cx.motion_anchors.entries.items.len);
}

test "ui.view anchor_motion: a source switches anchor <-> fade_scale for the next run" {
    var e = try Env.init();
    defer e.deinit();
    const away = try e.scope.createSignal(bool, false);
    const motion = try e.scope.createSignal(v.AnchorMotion, anchor_transition.default_tokens);
    _ = try e.mount(v.box(.{ .style = .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } } }, .{
        v.box(.{ .test_id = "tab", .motion_anchor = "tab-1", .style = .{ .position = .absolute, .width = .{ .px = 40 }, .height = .{ .px = 20 }, .translate_x = 20, .translate_y = 10 } }, .{}),
        v.box(.{ .test_id = "card", .anchor_collapsed = away, .anchor_to = "tab-1", .anchor_motion = motion, .style = .{ .position = .absolute, .width = .{ .px = 120 }, .height = .{ .px = 80 }, .translate_x = 200, .translate_y = 150, .background = core.Color.rgb(200, 60, 60) } }, .{}),
    }));
    // Switched to fade_scale at rest: the collapse stays in place (centered on the card's home).
    motion.set(anchor_transition.fade_scale_tokens);
    away.set(true);
    e.frame(e.now + 16);
    e.frame(e.now + 16);
    e.frame(e.now + 40);
    const t = findTransitionFrame(&e) orelse return error.NoFrame;
    try testing.expectApproxEqAbs(@as(f32, 260), t.rect.centerX(), 0.01);
    try testing.expectApproxEqAbs(@as(f32, 190), t.rect.centerY(), 0.01);
    try testing.expect(t.opacity < 1);
    e.run(500);
    try testing.expectEqual(core.Display.none, card(&e).style.display);
    try testing.expectEqual(@as(usize, 0), e.layers());
    // Back to anchor: the expand comes out of the tab again.
    motion.set(anchor_transition.default_tokens);
    away.set(false);
    e.frame(e.now + 16);
    e.frame(e.now + 16);
    e.frame(e.now + 40);
    const f = findTransitionFrame(&e) orelse return error.NoFrame;
    // Genie out of the tab: the mesh still reaches up toward the tab.
    try testing.expect(f.genie != null);
    try testing.expect(f.rect.y < 150);
    e.run(500);
    try testing.expectEqual(@as(f32, 1), card(&e).getOpacity());
}

/// The frame of the (single) transition in flight, read from its overlay layer's draw context.
fn findTransitionFrame(e: *Env) ?anchor_transition.Frame {
    const root = e.cx.root orelse return null;
    for (root.children.items) |c| {
        const name = c.meta.ownership.meta.component_name orelse continue;
        if (!std.mem.eql(u8, name, "AnchorTransitionLayer")) continue;
        const hook = c.meta.per_frame.custom_hooks.draw orelse continue;
        const ctx = hook.context orelse continue;
        const t: *anchor_transition.AnchorTransition = @ptrCast(@alignCast(ctx));
        return t.currentFrame();
    }
    return null;
}
