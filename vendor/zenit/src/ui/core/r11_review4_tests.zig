//! r11 fourth review repros (scratch only).
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

const Mode = enum { overlay_abort, overlay_abort_ctrl, ov_static_abort, ov_static_ctrl, ov_promoted_abort, ov_promoted_ctrl, rco_move_out, append_move_out, scale, opacity, opacity_zero, rotate, overlay_self_composite, promoted_opacity, clip_scale };

const S = struct {
    var mode: Mode = .scale;
    var root: ?*Node = null;
    var p: ?*Node = null;
    var k: ?*Node = null;
    var k2: ?*Node = null;
};

fn hookP(node: *Node) void {
    _ = node;
    const f = frameNow();
    const k = S.k.?;
    switch (S.mode) {
        .rco_move_out => {
            if (f >= 6 and f <= 8) k.setBackgroundRaw(colorOf(f));
            if (f == 8) {
                S.p.?.replaceChildOrder(testing.allocator, &.{}) catch {};
                S.root.?.appendChild(testing.allocator, k) catch {};
            }
        },
        .append_move_out => {
            if (f >= 6 and f <= 8) k.setBackgroundRaw(colorOf(f));
            if (f == 8) S.root.?.appendChild(testing.allocator, k) catch {};
        },
        .scale, .clip_scale => {
            k.setTranslateX(@floatFromInt(f % 4));
            const e = k.style.ext.?;
            e.scale_x = switch (f) {
                5, 6 => 1.5,
                7 => 0.5,
                else => 1.0,
            };
            if (f == 6) S.k2.?.setBackgroundRaw(colorOf(f));
        },
        .rotate => {
            k.setTranslateX(@floatFromInt(f % 4));
            k.style.ext.?.rotate = switch (f) {
                5, 6 => 0.3,
                else => 0,
            };
        },
        .opacity => {
            k.setTranslateX(@floatFromInt(f % 4));
            k.setOpacityRaw(switch (f) {
                5, 6 => 0.5,
                9 => 0.2,
                else => 1.0,
            });
            if (f == 6 or f == 9) S.k2.?.setBackgroundRaw(colorOf(f));
        },
        .opacity_zero => {
            k.setOpacityRaw(switch (f) {
                5, 6, 7 => 0.0,
                else => 1.0,
            });
            if (f == 6) S.k2.?.setBackgroundRaw(colorOf(f));
        },
        .promoted_opacity => {
            k.setOpacityRaw(if (f % 2 == 0) 0.6 else 0.9);
            if (f == 7) S.k2.?.setBackgroundRaw(colorOf(f));
        },
        else => {},
    }
}

fn overlayMain(node: *Node) void {
    const f = frameNow();
    switch (S.mode) {
        .ov_static_abort, .ov_static_ctrl, .ov_promoted_abort, .ov_promoted_ctrl => {
            node.setTranslateX(2);
            if (f >= 5 and f <= 12) S.k2.?.setBackgroundRaw(colorOf(f));
            return;
        },
        else => {},
    }
    node.setTranslateX(@floatFromInt(f % 3));
    switch (S.mode) {
        .overlay_abort, .overlay_abort_ctrl => if (f >= 5 and f <= 12) S.k2.?.setBackgroundRaw(colorOf(f)),
        .overlay_self_composite => {
            node.setOpacityRaw(if (f % 2 == 0) 0.7 else 1.0);
            node.style.ext.?.scale_x = if (f % 3 == 0) 0.9 else 1.0;
            if (f == 7) S.k2.?.setBackgroundRaw(colorOf(f));
        },
        else => {},
    }
}

fn run(frames: usize, out: []u64) !void {
    cx_render.setVerifyIncrementalForTest(true);
    defer cx_render.setVerifyIncrementalForTest(null);
    raw_shadow.disabled_override = false;
    defer raw_shadow.disabled_override = null;
    const saved_cap = raw_shadow.max_nodes_per_pass;
    const saved_retry = raw_shadow.retry_after_passes;
    defer {
        raw_shadow.max_nodes_per_pass = saved_cap;
        raw_shadow.retry_after_passes = saved_retry;
    }
    raw_shadow.retry_after_passes = 10;

    var cx = try ui.Cx.init(testing.allocator, testing.io);
    defer cx.deinit();
    cx.setViewport(800, 400);
    const root = try ui.box(cx, .{ .width = .{ .px = 800 }, .height = .{ .px = 400 }, .background = Color.hex(0xf6f5f2) }, .{});
    cx.root = root;
    S.root = root;
    const overlay = switch (S.mode) {
        .overlay_abort, .overlay_abort_ctrl, .overlay_self_composite, .ov_static_abort, .ov_static_ctrl, .ov_promoted_abort, .ov_promoted_ctrl => true,
        else => false,
    };
    const p = try ui.box(cx, .{ .position = .absolute, .z_index = if (overlay) 5 else 0, .overflow_hidden = overlay or S.mode == .clip_scale, .corner_radius = 3, .will_change_transform = S.mode == .ov_promoted_abort or S.mode == .ov_promoted_ctrl, .inset = .{ .left = .{ .px = 40 }, .top = .{ .px = 40 } }, .width = .{ .px = 220 }, .height = .{ .px = 120 }, .background = Color.hex(0xeeeeee) }, .{});
    const k = try ui.box(cx, .{ .width = .{ .px = 200 }, .height = .{ .px = 50 }, .corner_radius = 2, .will_change_opacity = S.mode == .promoted_opacity, .overflow_hidden = overlay, .background = Color.hex(0xdddddd) }, .{});
    for (0..3) |_| _ = try @import("translate_render_tests.zig").makeCard(cx, k, 0, 0, "row");
    S.k2 = k.children.items[1];
    try p.appendChild(cx.allocator, k);
    try root.appendChild(cx.allocator, p);
    const sib = try ui.box(cx, .{ .position = .absolute, .inset = .{ .left = .{ .px = 400 }, .top = .{ .px = 40 } }, .width = .{ .px = 50 }, .height = .{ .px = 50 }, .background = Color.hex(0x888888) }, .{});
    try root.appendChild(cx.allocator, sib);
    S.p = p;
    S.k = k;
    if (overlay) {
        if (S.mode == .overlay_self_composite) _ = p.style.ensureExtPanic(cx.allocator);
        p.meta.per_frame.hooks.before_render.main = overlayMain;
    } else p.addBeforeRenderScoped(hookP, .subtree);
    _ = cx.render();
    cx.layout();
    for (0..frames) |f| {
        raw_shadow.max_nodes_per_pass = if ((S.mode == .overlay_abort or S.mode == .ov_static_abort or S.mode == .ov_promoted_abort) and f == 4) 1 else 16 * 1024;
        sib.setBackground(Color.rgba(@intCast((f * 13) % 250), 80, 80, 255));
        cx.frame_time_ms = @as(f64, @floatFromInt(f + 1)) * 8.0;
        cx.incremental_verify_mismatch_total = 0;
        _ = cx.render();
        out[f] = cx.incremental_verify_mismatch_total;
        const pf = cx.perf;
        if (cx.scene_runtime.get(p.id)) |rt| std.debug.print("[r4dbg] p reused={} k2reused={}\n", .{ rt.promoted_surface_flags.reused_this_frame, if (cx.scene_runtime.get(S.k2.?.id)) |r2| r2.promoted_surface_flags.reused_this_frame else false });
        std.debug.print("[r4 {s}] frame {d}: mismatches={d} hv_nodes={d} hv_skipped={d} cache_hit={d}\n", .{ @tagName(S.mode), f, out[f], pf.hook_verify_nodes, pf.hook_verify_skipped_cap, pf.render_cache_hit });
        cx.layout();
    }
}

fn total(xs: []const u64) u64 {
    var s: u64 = 0;
    for (xs) |x| s += x;
    return s;
}

fn expectClean(mode: Mode) !void {
    S.mode = mode;
    var out: [16]u64 = undefined;
    try run(16, &out);
    try testing.expectEqual(@as(u64, 0), total(&out));
}

test "r4 C: overlay main hook, verified then aborted pass, raw child writes in the retry window" {
    try expectClean(.overlay_abort);
}
test "r4 C ctrl: overlay main hook, no abort" {
    try expectClean(.overlay_abort_ctrl);
}
test "r4 D: replaceChildOrder drops a raw-written child, re-appended outside the hook subtree" {
    try expectClean(.rco_move_out);
}
test "r4 D ctrl: appendChild move-out" {
    try expectClean(.append_move_out);
}
test "r4 A scale" {
    try expectClean(.scale);
}
test "r4 A clip scale" {
    try expectClean(.clip_scale);
}
test "r4 A rotate" {
    try expectClean(.rotate);
}
test "r4 A opacity" {
    try expectClean(.opacity);
}
test "r4 A opacity zero" {
    try expectClean(.opacity_zero);
}
test "r4 A promoted opacity" {
    try expectClean(.promoted_opacity);
}
test "r4 A overlay self composite" {
    try expectClean(.overlay_self_composite);
}

test "r4 C2 static overlay abort" {
    try expectClean(.ov_static_abort);
}
test "r4 C2 static overlay ctrl" {
    try expectClean(.ov_static_ctrl);
}
test "r4 C3 promoted overlay abort" {
    try expectClean(.ov_promoted_abort);
}
test "r4 C3 promoted overlay ctrl" {
    try expectClean(.ov_promoted_ctrl);
}

const PopoverMod = @import("../components/popover/mod.zig");
const PO = struct {
    var orig: ?*const fn (*Node) void = null;
    var child: ?*Node = null;
    var n: usize = 0;
    var write: bool = true;
};
fn wrappedPopoverHook(node: *Node) void {
    PO.orig.?(node);
    PO.n += 1;
    if (PO.write) PO.child.?.setBackgroundRaw(Color.rgba(@intCast((PO.n * 37) % 250), 40, 200, 255));
}

var po_disabled = false;
fn runPopoverAbort(abort_at: ?usize) !u64 {
    cx_render.setVerifyIncrementalForTest(true);
    defer cx_render.setVerifyIncrementalForTest(null);
    raw_shadow.disabled_override = po_disabled;
    defer raw_shadow.disabled_override = null;
    const saved_cap = raw_shadow.max_nodes_per_pass;
    defer raw_shadow.max_nodes_per_pass = saved_cap;
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
    for (0..20) |f| {
        raw_shadow.max_nodes_per_pass = if (abort_at != null and f == abort_at.?) 1 else 16 * 1024;
        ctx.frame_time_ms += 16;
        ctx.incremental_verify_mismatch_total = 0;
        ctx.layout();
        _ = ctx.render();
        const rt = ctx.scene_runtime.get(result.content.id).?;
        std.debug.print("[r4 popover abort={any}] frame {d}: mismatches={d} promoted_reused={} rebuilt={} hv_skipped={d}\n", .{ abort_at, f, ctx.incremental_verify_mismatch_total, rt.promoted_surface_flags.reused_this_frame, rt.promoted_surface_flags.rebuilt_this_frame, ctx.perf.hook_verify_skipped_cap });
        mism += ctx.incremental_verify_mismatch_total;
    }
    return mism;
}

test "r4 C4: Popover main hook writes a child raw; verification aborts once (retry window)" {
    try testing.expectEqual(@as(u64, 0), try runPopoverAbort(3));
}
test "r4 C4 ctrl: Popover, no abort" {
    try testing.expectEqual(@as(u64, 0), try runPopoverAbort(null));
}

test "r4 C4 disabled: Popover main hook writes a child raw, verification off (pre-existing?)" {
    po_disabled = true;
    defer po_disabled = false;
    try testing.expectEqual(@as(u64, 0), try runPopoverAbort(null));
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
