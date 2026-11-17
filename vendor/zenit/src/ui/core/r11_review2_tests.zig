//! r11 second review repros (scratch only).
const std = @import("std");
const ui = @import("../core.zig");
const raw_shadow = @import("render_engine/raw_shadow.zig");
const h = @import("translate_render_tests.zig");
const testing = std.testing;

const Node = ui.Node;
const Color = ui.Color;
const World = h.World;
const Config = h.Config;

fn applyVerify(cfg: Config) void {
    h.applyBase(cfg);
    raw_shadow.disabled_override = !cfg.extra;
}

fn runEachScoped(tag: []const u8, build: h.BuildFn, move: h.MoveFn, frames: usize, scope: ui.BeforeRenderScope) ![2]u64 {
    const cfgs = [_]Config{
        .{ .name = "hookverify+check", .verify = true, .extra = true },
        .{ .name = "disabled+check", .verify = true, .extra = false },
    };
    var out: [2]u64 = .{ 0, 0 };
    for (cfgs, 0..) |cfg, i| {
        const one = [_]Config{cfg};
        const t = h.runLockstep(&one, build, move, .{ .frames = frames, .hook_scope = scope, .apply = applyVerify }) catch |e| {
            std.debug.print("[{s}] {s}: {s}\n", .{ tag, cfg.name, @errorName(e) });
            out[i] = 1;
            continue;
        };
        defer testing.allocator.free(t);
        out[i] = t[0].mismatches;
    }
    raw_shadow.disabled_override = null;
    std.debug.print("[{s}] mismatches: hookverify={d} disabled={d}\n", .{ tag, out[0], out[1] });
    return out;
}

fn frameNow() usize {
    const t = @import("render_engine/mod.zig").current_frame_time_ms;
    return @as(usize, @intFromFloat(t / 8.0)) -| 1;
}

fn colorOf(f: usize) Color {
    return Color.rgba(@intCast((f * 37) % 250), 40, 200, 255);
}

// ------------------------------------------------------------------------------------------
// N1: an undeclared `.subtree` hook writes its subtree raw and unregisters itself in the same
// tick (one-shot / "animation done" pattern). The paint pass of that frame no longer sees an
// untrusted hook at P, so nothing walks P's subtree, while the caches recorded the frame before
// (under verified trust) are still there and replay.

const N1 = struct {
    var p: ?*Node = null;
    var k: ?*Node = null;
    var sibling: ?*Node = null;
    var keep_trusted_hook = false;
};

fn hookP1(node: *Node) void {
    const f = frameNow();
    if (f >= 6) N1.k.?.setBackgroundRaw(colorOf(f));
    if (f == 8) node.removeBeforeRender(hookP1);
}
fn noopDirtyMarking(_: *Node) void {}

fn buildN1(w: *World) !void {
    try h.makeRoot(w);
    const cx = w.cx;
    const p = try ui.box(cx, .{ .position = .absolute, .inset = .{ .left = .{ .px = 40 }, .top = .{ .px = 40 } }, .width = .{ .px = 220 }, .height = .{ .px = 120 }, .background = Color.hex(0xeeeeee) }, .{});
    const k = try ui.box(cx, .{ .width = .{ .px = 30 }, .height = .{ .px = 20 }, .background = Color.hex(0x2244aa) }, .{});
    try p.appendChild(cx.allocator, k);
    try w.root.appendChild(cx.allocator, p);
    N1.sibling = try h.makeHostedCard(w.scope, cx, w.root, 400, 40, "dirty sibling");
    p.addBeforeRenderScoped(hookP1, .subtree);
    if (N1.keep_trusted_hook) p.addBeforeRenderScoped(noopDirtyMarking, .dirty_marking);
    N1.p = p;
    N1.k = k;
}

fn moveN1(w: *World, frame: usize) void {
    _ = w;
    N1.sibling.?.setBackground(Color.rgba(@intCast((frame * 13) % 250), 80, 80, 255));
    std.debug.print("[N1] frame {d}: prev splices/memo={d}/{d} hv_nodes={d} hv_hooks={d}\n", .{ frame, h.last_perf.subtree_payload_splice_count, h.last_perf.rn_memo_replays, h.last_perf.hook_verify_nodes, h.last_perf.hook_verify_hooks });
}

test "r11b N1: self-unregistering .subtree hook, last raw write never verified" {
    const m = try runEachScoped("N1", buildN1, moveN1, 14, .dirty_marking);
    try testing.expectEqual(@as(u64, 0), m[1]);
    try testing.expectEqual(@as(u64, 0), m[0]);
}

test "r11b N1b: .subtree hook removed, a .dirty_marking hook stays (node becomes cache-trusted)" {
    N1.keep_trusted_hook = true;
    defer N1.keep_trusted_hook = false;
    const m = try runEachScoped("N1b", buildN1, moveN1, 14, .dirty_marking);
    try testing.expectEqual(@as(u64, 0), m[1]);
    try testing.expectEqual(@as(u64, 0), m[0]);
}

// ------------------------------------------------------------------------------------------
// N3: inside_hook_owned stops replaying AND writing a legacy overflow cache inside a hook-owned
// subtree, but does not drop the one recorded before. When the `main` hook goes away the cache
// recorded before it was installed replays over the raw writes made meanwhile.

const N3 = struct {
    var m: ?*Node = null;
    var l: ?*Node = null;
    var k: ?*Node = null;
    var sibling: ?*Node = null;
};

fn mainHook3(node: *Node) void {
    const f = frameNow();
    N3.k.?.setBackgroundRaw(colorOf(f));
    if (f >= 9) node.meta.per_frame.hooks.before_render.main = null;
}

fn buildN3(w: *World) !void {
    try h.makeRoot(w);
    const cx = w.cx;
    const m = try ui.box(cx, .{ .position = .absolute, .inset = .{ .left = .{ .px = 40 }, .top = .{ .px = 40 } }, .width = .{ .px = 220 }, .height = .{ .px = 120 }, .background = Color.hex(0xeeeeee) }, .{});
    const l = try ui.box(cx, .{ .width = .{ .px = 120 }, .height = .{ .px = 60 }, .overflow_hidden = true, .background = Color.hex(0xdddddd) }, .{});
    const k = try ui.box(cx, .{ .width = .{ .px = 30 }, .height = .{ .px = 20 }, .background = Color.hex(0x2244aa) }, .{});
    try l.appendChild(cx.allocator, k);
    try m.appendChild(cx.allocator, l);
    try w.root.appendChild(cx.allocator, m);
    N3.sibling = try h.makeHostedCard(w.scope, cx, w.root, 400, 40, "dirty sibling");
    N3.m = m;
    N3.l = l;
    N3.k = k;
}

fn moveN3(w: *World, frame: usize) void {
    _ = w;
    N3.sibling.?.setBackground(Color.rgba(@intCast((frame * 13) % 250), 80, 80, 255));
    if (frame == 4) {
        N3.m.?.meta.per_frame.hooks.before_render.main = mainHook3;
        N3.m.?.invalidateTickQuietChain();
    }
    std.debug.print("[N3] frame {d}: prev cache_hit={d} miss={d} hv_nodes={d}\n", .{ frame, h.last_perf.render_cache_hit, h.last_perf.render_cache_miss, h.last_perf.hook_verify_nodes });
}

test "r11b N3: legacy overflow cache recorded before a main hook replays after it is removed" {
    const m = try runEachScoped("N3", buildN3, moveN3, 14, .dirty_marking);
    try testing.expectEqual(@as(u64, 0), m[1]);
    try testing.expectEqual(@as(u64, 0), m[0]);
}

// ------------------------------------------------------------------------------------------
// N4 (perf probe): overlay-like root (z_index > 0) with a root-only positioning hook, a clipped
// child (legacy overflow cache candidate). Counts cache hits per configuration.

const N4 = struct {
    var o: ?*Node = null;
    var sibling: ?*Node = null;
    var hits: [2]u64 = .{ 0, 0 };
    var cur: usize = 0;
    var main_hook = true;
    var z: i16 = 5;
    var no_hook = false;
};

fn overlayHook(node: *Node) void {
    const f = frameNow();
    node.setTranslateX(@floatFromInt(f % 3));
}

fn buildN4(w: *World) !void {
    try h.makeRoot(w);
    const cx = w.cx;
    const o = try ui.box(cx, .{ .position = .absolute, .z_index = N4.z, .inset = .{ .left = .{ .px = 40 }, .top = .{ .px = 40 } }, .width = .{ .px = 300 }, .height = .{ .px = 300 }, .background = Color.hex(0xeeeeee), .direction = .column }, .{});
    for (0..4) |_| {
        const l = try ui.box(cx, .{ .width = .{ .px = 200 }, .height = .{ .px = 50 }, .overflow_hidden = true, .background = Color.hex(0xdddddd) }, .{});
        for (0..3) |_| try l.appendChild(cx.allocator, try h.makeCard(cx, l, 0, 0, "row"));
        try o.appendChild(cx.allocator, l);
    }
    try w.root.appendChild(cx.allocator, o);
    N4.sibling = try h.makeHostedCard(w.scope, cx, w.root, 600, 40, "dirty sibling");
    if (N4.no_hook) {} else if (N4.main_hook) o.meta.per_frame.hooks.before_render.main = overlayHook else o.addBeforeRenderScoped(overlayHook, .dirty_marking);
    N4.o = o;
}

fn moveN4(w: *World, frame: usize) void {
    _ = w;
    N4.sibling.?.setBackground(Color.rgba(@intCast((frame * 13) % 250), 80, 80, 255));
    if (frame >= 3) N4.hits[N4.cur] += h.last_perf.render_cache_hit;
}

test "r11b N4: cache hits under an overlay root with a hook" {
    inline for (.{ .{ true, 5, false }, .{ false, 5, false }, .{ false, 0, false }, .{ false, 0, true } }) |v| {
        const mh = v[0];
        N4.main_hook = mh;
        N4.z = v[1];
        N4.no_hook = v[2];
        N4.hits = .{ 0, 0 };
        const cfgs = [_]Config{
            .{ .name = "hookverify", .verify = false, .extra = true },
            .{ .name = "disabled", .verify = false, .extra = false },
        };
        for (cfgs, 0..) |cfg, i| {
            N4.cur = i;
            const one = [_]Config{cfg};
            const t = try h.runLockstep(&one, buildN4, moveN4, .{ .frames = 20, .hook_scope = .dirty_marking, .apply = applyVerify });
            testing.allocator.free(t);
        }
        raw_shadow.disabled_override = null;
        std.debug.print("[N4] z={d} no_hook={} main_hook={} render_cache_hit (frames 3..19): hookverify={d} disabled={d}\n", .{ N4.z, N4.no_hook, mh, N4.hits[0], N4.hits[1] });
        // A cache-trusted hook (.dirty_marking) on an overlay root keeps its descendants' legacy
        // overflow caches. A `main` hook is untrusted: below it nothing may replay (it may write
        // raw; see N3).
        if (!mh) {
            try testing.expect(N4.hits[0] > 0);
            try testing.expect(N4.hits[1] > 0);
        } else {
            try testing.expectEqual(@as(u64, 0), N4.hits[0]);
        }
    }
}

// ------------------------------------------------------------------------------------------
// Span segment positions after an in-place, same-length text edit. The interaction prefix-width
// cache (text_layout.getInteractionPrefixCacheIndex) is keyed on (node, content_version, range,
// spans hash, font) and not on the bytes. The verification marks the edit without bumping the
// content version, so the key alone cannot see it. Compared with a Cx that was built with the
// edited text from the start (the reference pass shares the global cache, so the incremental check
// cannot catch this).

const SpanCase = struct {
    var text: ?*Node = null;
    var buf: [19]u8 = undefined;
};

fn spanHook(_: *Node) void {
    if (frameNow() == 3) {
        const t = SpanCase.text.?.getTextRaw().?;
        const bytes: []u8 = @constCast(t.content);
        @memcpy(bytes, "\u{e9}\u{e9}\u{e9}\u{e9}a iiiiiiiii");
    }
}

fn buildSpanScene(cx: *ui.Cx, initial: []const u8) !*Node {
    const root = try ui.box(cx, .{ .width = .{ .px = 600 }, .height = .{ .px = 200 } }, .{});
    cx.root = root;
    const t = try ui.text(cx, initial, .{ .font_size = 16, .color = Color.hex(0x111111) });
    var tp = t.getTextRaw().?;
    const spans = try cx.allocator.alloc(ui.TextSpan, 2);
    spans[0] = .{ .start = 0, .end = 9, .color = Color.hex(0xaa0000), .bg_color = Color.hex(0xffee00) };
    spans[1] = .{ .start = 10, .end = 19, .color = Color.hex(0x0000aa), .bg_color = Color.hex(0x00eeff), .underline = true };
    tp.spans = spans;
    tp.spans_owned = true;
    t.setText(tp);
    try root.appendChild(cx.allocator, t);
    return t;
}

fn spanItems(cx: *ui.Cx, out: *std.ArrayList([4]f32)) !void {
    out.clearRetainingCapacity();
    for (cx.lowering.main_paint.items) |it| try out.append(testing.allocator, .{ it.geom.x, it.geom.y, it.geom.w, it.geom.h });
}

test "r11b span: in-place same-length edit of spanned text moves its segments like a fresh build" {
    raw_shadow.disabled_override = false;
    defer raw_shadow.disabled_override = null;
    var a = try ui.Cx.init(testing.allocator, testing.io);
    defer a.deinit();
    a.setViewport(600, 200);
    SpanCase.text = try buildSpanScene(a, "iiiiiiiii WWWWWWWWW");
    a.root.?.addBeforeRenderScoped(spanHook, .subtree);
    var b = try ui.Cx.init(testing.allocator, testing.io);
    defer b.deinit();
    b.setViewport(600, 200);
    _ = try buildSpanScene(b, "\u{e9}\u{e9}\u{e9}\u{e9}a iiiiiiiii");
    var ia: std.ArrayList([4]f32) = .empty;
    defer ia.deinit(testing.allocator);
    var ib: std.ArrayList([4]f32) = .empty;
    defer ib.deinit(testing.allocator);
    for (0..8) |f| {
        a.frame_time_ms = @as(f64, @floatFromInt(f + 1)) * 8;
        _ = a.render();
        a.layout();
        try spanItems(a, &ia);
        b.frame_time_ms = a.frame_time_ms;
        _ = b.render();
        b.layout();
        try spanItems(b, &ib);
        if (f >= 4) {
            std.debug.print("[span] frame {d}: edited {any} fresh {any}\n", .{ f, ia.items, ib.items });
            try testing.expectEqual(ib.items.len, ia.items.len);
            for (ia.items, ib.items) |x, y| for (x, y) |p, q| try testing.expect(@abs(p - q) < 0.01);
        }
    }
}

test {
    // The unit test of the prefix-cache key (the headless test measurer is per byte, so the
    // end-to-end span test above cannot show a width change; the key test pins the fix).
    _ = @import("text_layout.zig");
}
