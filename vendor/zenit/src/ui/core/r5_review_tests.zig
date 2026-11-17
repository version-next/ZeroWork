//! r5 review repro (scratch only).
const std = @import("std");
const ui = @import("../core.zig");
const raw_shadow = @import("render_engine/raw_shadow.zig");
const testing = std.testing;
const Node = ui.Node;
const Color = ui.Color;

var g_f: usize = 0;
fn selfOnlyHook(node: *Node) void {
    node.setBackground(Color.rgba(@intCast((g_f * 7) % 250), 20, 30, 255));
}

fn runSelfOnly(verify_off: bool) !u64 {
    raw_shadow.disabled_override = verify_off;
    defer raw_shadow.disabled_override = null;
    var cx = try ui.Cx.init(testing.allocator, testing.io);
    defer cx.deinit();
    cx.setViewport(800, 600);
    const root = try ui.box(cx, .{ .width = .{ .px = 800 }, .height = .{ .px = 600 } }, .{});
    cx.root = root;
    const hooked = try ui.box(cx, .{ .width = .{ .px = 400 }, .height = .{ .px = 400 }, .background = Color.hex(0x111111) }, .{});
    hooked.meta.per_frame.hooks.before_render.main = selfOnlyHook;
    hooked.frame_state.state_bits.flags.before_render_hook_affects_self_only = true;
    try root.appendChild(cx.allocator, hooked);
    for (0..20) |i| {
        const c = try ui.box(cx, .{ .width = .{ .px = 30 }, .height = .{ .px = 10 }, .background = Color.rgba(@intCast(i * 10), 80, 120, 255) }, .{});
        const g = try ui.box(cx, .{ .width = .{ .px = 4 }, .height = .{ .px = 4 }, .background = Color.rgba(200, @intCast(i * 10), 60, 255) }, .{});
        try c.appendChild(cx.allocator, g);
        try hooked.appendChild(cx.allocator, c);
    }
    const sib = try ui.box(cx, .{ .width = .{ .px = 20 }, .height = .{ .px = 20 }, .background = Color.hex(0x888888) }, .{});
    try root.appendChild(cx.allocator, sib);
    var reuse: u64 = 0;
    for (0..16) |f| {
        g_f = f;
        sib.setBackground(Color.rgba(@intCast((f * 13) % 250), 80, 80, 255));
        cx.frame_time_ms = @as(f64, @floatFromInt(f + 1)) * 16.0;
        cx.layout();
        _ = cx.render();
        const p = cx.perf;
        if (f >= 4) reuse += p.own_payload_cache_hit_count + p.subtree_payload_paint_resume_count + p.subtree_payload_splice_count;
        std.debug.print("[r5 selfonly off={}] f={d} own_hit={d} resume={d} splice={d} hv_hooks={d} hv_nodes={d}\n", .{ verify_off, f, p.own_payload_cache_hit_count, p.subtree_payload_paint_resume_count, p.subtree_payload_splice_count, p.hook_verify_hooks, p.hook_verify_nodes });
    }
    return reuse;
}

test "r5 self-only main hook: children reuse with verification on equals verification off" {
    const off = try runSelfOnly(true);
    const on = try runSelfOnly(false);
    std.debug.print("[r5 selfonly] reuse off={d} on={d}\n", .{ off, on });
    try testing.expectEqual(off, on);
}
