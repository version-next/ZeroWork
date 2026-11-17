//! r11 third review repros (scratch only).
const std = @import("std");
const ui = @import("../core.zig");
const raw_shadow = @import("render_engine/raw_shadow.zig");
const cx_render = @import("cx_render.zig");
const testing = std.testing;
const Node = ui.Node;
const Color = ui.Color;

fn frameNow() usize {
    const t = @import("render_engine/mod.zig").current_frame_time_ms;
    return @as(usize, @intFromFloat(t / 8.0)) -| 1;
}
fn colorOf(f: usize) Color {
    return Color.rgba(@intCast((f * 37) % 250), 40, 200, 255);
}

const S = struct {
    var root: ?*Node = null;
    var p: ?*Node = null;
    var k: ?*Node = null;
    var sib: ?*Node = null;
    var mode: enum { remove_abort, remove_ok, move_out, overlay_child, overlay_self, register_once } = .remove_abort;
    var disabled = false;
    var write_from: usize = 6;
    var clip = false;
    var k2: ?*Node = null;
};

fn hookP(node: *Node) void {
    const f = frameNow();
    switch (S.mode) {
        .remove_abort, .remove_ok => {
            if (f >= S.write_from and f <= 8) (S.k2 orelse S.k.?).setBackgroundRaw(colorOf(f));
            if (f == 8) node.removeBeforeRender(hookP);
        },
        .move_out => {
            if (f >= 6 and f <= 8) S.k.?.setBackgroundRaw(colorOf(f));
            if (f == 8) S.root.?.appendChild(testing.allocator, S.k.?) catch {};
        },
        else => {},
    }
}

fn hookOnce(node: *Node) void {
    (S.k2 orelse S.k.?).setBackgroundRaw(colorOf(99));
    node.removeBeforeRender(hookOnce);
}

fn overlayMain(node: *Node) void {
    const f = frameNow();
    node.setTranslateX(@floatFromInt(f % 3));
    if (f >= 5 and f <= 9) switch (S.mode) {
        .overlay_child => S.k2.?.setBackgroundRaw(colorOf(f)),
        .overlay_self => node.setBackgroundRaw(colorOf(f)),
        else => {},
    };
}

fn run(frames: usize, out: []u64) !void {
    cx_render.setVerifyIncrementalForTest(true);
    defer cx_render.setVerifyIncrementalForTest(null);
    raw_shadow.disabled_override = S.disabled;
    defer raw_shadow.disabled_override = null;
    const saved_cap = raw_shadow.max_nodes_per_pass;
    const saved_retry = raw_shadow.retry_after_passes;
    defer {
        raw_shadow.max_nodes_per_pass = saved_cap;
        raw_shadow.retry_after_passes = saved_retry;
    }
    raw_shadow.retry_after_passes = 2;

    var cx = try ui.Cx.init(testing.allocator, testing.io);
    defer cx.deinit();
    cx.setViewport(800, 400);
    const root = try ui.box(cx, .{ .width = .{ .px = 800 }, .height = .{ .px = 400 }, .background = Color.hex(0xf6f5f2) }, .{});
    cx.root = root;
    S.root = root;
    const overlay = S.mode == .overlay_child or S.mode == .overlay_self;
    const p = try ui.box(cx, .{ .position = .absolute, .z_index = if (overlay) 5 else 0, .overflow_hidden = overlay, .inset = .{ .left = .{ .px = 40 }, .top = .{ .px = 40 } }, .width = .{ .px = 220 }, .height = .{ .px = 120 }, .background = Color.hex(0xeeeeee) }, .{});
    S.k2 = null;
    const k = if (S.clip or overlay) blk: {
        const l = try ui.box(cx, .{ .width = .{ .px = 200 }, .height = .{ .px = 50 }, .overflow_hidden = true, .background = Color.hex(0xdddddd) }, .{});
        for (0..3) |_| _ = try @import("translate_render_tests.zig").makeCard(cx, l, 0, 0, "row");
        S.k2 = l.children.items[1];
        break :blk l;
    } else try ui.box(cx, .{ .width = .{ .px = 30 }, .height = .{ .px = 20 }, .background = Color.hex(0x2244aa) }, .{});
    try p.appendChild(cx.allocator, k);
    try root.appendChild(cx.allocator, p);
    const sib = try ui.box(cx, .{ .position = .absolute, .inset = .{ .left = .{ .px = 400 }, .top = .{ .px = 40 } }, .width = .{ .px = 50 }, .height = .{ .px = 50 }, .background = Color.hex(0x888888) }, .{});
    try root.appendChild(cx.allocator, sib);
    S.p = p;
    S.k = k;
    S.sib = sib;
    if (overlay) p.meta.per_frame.hooks.before_render.main = overlayMain else if (S.mode != .register_once) p.addBeforeRenderScoped(hookP, .subtree);
    _ = cx.render();
    cx.layout();
    for (0..frames) |f| {
        raw_shadow.max_nodes_per_pass = if (S.mode == .remove_abort and f == 8) 1 else 16 * 1024;
        sib.setBackground(Color.rgba(@intCast((f * 13) % 250), 80, 80, 255));
        if (S.mode == .register_once and f == 8) p.addBeforeRenderScoped(hookOnce, .subtree);
        cx.frame_time_ms = @as(f64, @floatFromInt(f + 1)) * 8.0;
        cx.incremental_verify_mismatch_total = 0;
        _ = cx.render();
        out[f] = cx.incremental_verify_mismatch_total;
        const pf = cx.perf;
        std.debug.print("[r3 {s}] frame {d}: mismatches={d} hv_nodes={d} hv_skipped={d} cache_hit={d}\n", .{ @tagName(S.mode), f, out[f], pf.hook_verify_nodes, pf.hook_verify_skipped_cap, pf.render_cache_hit });
        cx.layout();
    }
}

fn total(xs: []const u64, from: usize) u64 {
    var s: u64 = 0;
    for (xs[from..]) |x| s += x;
    return s;
}

test "r3 control: self-removing hook without abort" {
    S.mode = .remove_ok;
    var out: [20]u64 = undefined;
    try run(20, &out);
    try testing.expectEqual(@as(u64, 0), total(&out, 0));
}

test "r3 A: self-removing hook in an aborted pass, never re-walked" {
    S.mode = .remove_abort;
    var out: [20]u64 = undefined;
    try run(20, &out);
    std.debug.print("[r3 A] mismatches frame 8: {d}, frames 12..19 (after retry window): {d}\n", .{ out[8], total(&out, 12) });
    try testing.expectEqual(@as(u64, 0), total(&out, 0));
}

test "r3 C: hook writes a child raw and moves it out of its subtree in the same tick" {
    S.mode = .move_out;
    var out: [14]u64 = undefined;
    try run(14, &out);
    try testing.expectEqual(@as(u64, 0), total(&out, 0));
}

test "r3 D1: overlay root main hook writes a child raw (overlay root keeps its caches)" {
    S.mode = .overlay_child;
    var out: [14]u64 = undefined;
    try run(14, &out);
    try testing.expectEqual(@as(u64, 0), total(&out, 0));
}

test "r3 D2: overlay root main hook writes its own background raw" {
    S.mode = .overlay_self;
    var out: [14]u64 = undefined;
    try run(14, &out);
    try testing.expectEqual(@as(u64, 0), total(&out, 0));
}

test "r3 A2: aborted pass + self-removing hook, clipped container (legacy overflow cache)" {
    S.mode = .remove_abort;
    S.clip = true;
    defer S.clip = false;
    var out: [20]u64 = undefined;
    try run(20, &out);
    std.debug.print("[r3 A2] mismatches frame 8: {d}, frames 12..19: {d}\n", .{ out[8], total(&out, 12) });
    try testing.expectEqual(@as(u64, 0), total(&out, 0));
}

test "r3 A2 control: no abort, clipped container" {
    S.mode = .remove_ok;
    S.clip = true;
    defer S.clip = false;
    var out: [20]u64 = undefined;
    try run(20, &out);
    try testing.expectEqual(@as(u64, 0), total(&out, 0));
}

test "r3 C-disabled: move out with the verification disabled (pre-existing?)" {
    S.mode = .move_out;
    S.disabled = true;
    defer S.disabled = false;
    var out: [14]u64 = undefined;
    try run(14, &out);
    try testing.expectEqual(@as(u64, 0), total(&out, 0));
}

test "r3 D1-disabled: overlay child raw, verification disabled" {
    S.mode = .overlay_child;
    S.disabled = true;
    defer S.disabled = false;
    var out: [14]u64 = undefined;
    try run(14, &out);
    try testing.expectEqual(@as(u64, 0), total(&out, 0));
}

test "r3 A3: aborted pass + self-removing hook, clipped container, single raw write in the abort frame" {
    S.mode = .remove_abort;
    S.clip = true;
    S.write_from = 8;
    defer {
        S.clip = false;
        S.write_from = 6;
    }
    var out: [20]u64 = undefined;
    try run(20, &out);
    std.debug.print("[r3 A3] mismatches frame 8: {d}, frames 12..19: {d}\n", .{ out[8], total(&out, 12) });
    try testing.expectEqual(@as(u64, 0), total(&out, 0));
}

const PopoverMod = @import("../components/popover/mod.zig");
const PO = struct {
    var orig: ?*const fn (*Node) void = null;
    var target: enum { self_bg, child_bg, none } = .self_bg;
    var child: ?*Node = null;
    var n: usize = 0;
};
fn wrappedPopoverHook(node: *Node) void {
    PO.orig.?(node);
    PO.n += 1;
    const c = Color.rgba(@intCast((PO.n * 37) % 250), 40, 200, 255);
    switch (PO.target) {
        .self_bg => node.setBackgroundRaw(c),
        .child_bg => PO.child.?.setBackgroundRaw(c),
        .none => {},
    }
}

fn runPopover(target: @TypeOf(PO.target)) !u64 {
    cx_render.setVerifyIncrementalForTest(true);
    defer cx_render.setVerifyIncrementalForTest(null);
    raw_shadow.disabled_override = false;
    defer raw_shadow.disabled_override = null;
    PO.target = target;
    PO.n = 0;
    var ctx = try ui.Cx.init(testing.allocator, testing.io);
    defer ctx.deinit();
    ctx.setViewport(640, 480);
    const root = try ui.box(ctx, .{ .width = .{ .px = 640 }, .height = .{ .px = 480 } }, .{});
    ctx.root = root;
    const Scope = @import("../reactive.zig").Scope;
    const scope = try Scope.init(testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const result = try PopoverMod.Popover(.{ .position = .bottom_start, .trigger = .click }).mount(scope, ctx);
    try root.appendChild(testing.allocator, result.wrapper);
    const trigger_box = try ui.box(ctx, .{ .width = .{ .px = 120 }, .height = .{ .px = 32 } }, .{});
    try result.trigger.appendChild(testing.allocator, trigger_box);
    const child = try ui.box(ctx, .{ .width = .{ .px = 60 }, .height = .{ .px = 20 }, .background = Color.hex(0x2244aa) }, .{});
    try result.content.appendChild(testing.allocator, child);
    try result.content.appendChild(testing.allocator, try ui.text(ctx, "Stable popover text", .{}));
    PO.child = child;
    ctx.layout();
    _ = ctx.render();
    result.open.?.set(true);
    var settle: usize = 0;
    while (settle < 10) : (settle += 1) {
        ctx.frame_time_ms += 16;
        ctx.layout();
        _ = ctx.render();
        if (ctx.scene_runtime.get(result.content.id) != null) break;
    }
    // Popover registers its positioning hook `.dirty_marking`; this scenario needs it as the
    // overlay root's undeclared `main` hook (raw writes on top), as it used to be.
    PO.orig = popoverAsMainHook(result.content);
    try testing.expect(PO.orig != null);
    result.content.meta.per_frame.hooks.before_render.main = wrappedPopoverHook;
    var mism: u64 = 0;
    for (0..6) |f| {
        ctx.frame_time_ms += 16;
        ctx.incremental_verify_mismatch_total = 0;
        ctx.layout();
        _ = ctx.render();
        const rt = ctx.scene_runtime.get(result.content.id).?;
        std.debug.print("[r3 popover {s}] frame {d}: mismatches={d} promoted_reused={} rebuilt={} anim={}\n", .{ @tagName(target), f, ctx.incremental_verify_mismatch_total, rt.promoted_surface_flags.reused_this_frame, rt.promoted_surface_flags.rebuilt_this_frame, rt.has_active_transform_animation });
        mism += ctx.incremental_verify_mismatch_total;
    }
    return mism;
}

test "r3 D3: Popover content main hook writes its own background raw while its promoted surface is kept" {
    try testing.expectEqual(@as(u64, 0), try runPopover(.self_bg));
}
test "r3 D4: Popover content main hook writes a child raw while its promoted surface is kept" {
    try testing.expectEqual(@as(u64, 0), try runPopover(.child_bg));
}

test "r3 D0: Popover control, wrapper hook without raw writes" {
    try testing.expectEqual(@as(u64, 0), try runPopover(.none));
}

test "r3 E: hook registered and self-removed in the same frame" {
    S.mode = .register_once;
    var out: [14]u64 = undefined;
    try run(14, &out);
    try testing.expectEqual(@as(u64, 0), total(&out, 0));
}
test "r3 E2: hook registered and self-removed in the same frame, clipped container" {
    S.mode = .register_once;
    S.clip = true;
    defer S.clip = false;
    var out: [14]u64 = undefined;
    try run(14, &out);
    try testing.expectEqual(@as(u64, 0), total(&out, 0));
}

/// Moves Popover's `.dirty_marking` positioning hook back to the content's undeclared `main`
/// slot (the setup these raw-write scenarios were written against) and returns it.
fn popoverAsMainHook(content: *Node) ?*const fn (*Node) void {
    if (content.meta.per_frame.hooks.before_render.main) |existing| return existing;
    const hook = @import("../components/popover/mod.zig").popoverBeforeRender;
    if (!content.hasScopedBeforeRender(hook)) return null;
    content.removeBeforeRender(hook);
    content.meta.per_frame.hooks.before_render.main = hook;
    return hook;
}
