//! Raw-state shadow verification of undeclared before_render hooks (render_engine/raw_shadow.zig).
//!
//! Core test: a `.subtree` root hook and an "event handler" between frames make random raw writes
//! (Raw setters, direct `node.style.*` / ext fields, World rect / layout output, content in place,
//! borrowed text buffers, icons, child order, descendants at any depth), mixed with ordinary
//! setter writes. Four configurations run in lockstep: hook verification on / off
//! (ZENIT_DISABLE_HOOK_VERIFY) x ZENIT_VERIFY_INCREMENTAL on / off. Every verified frame must
//! show zero incremental-vs-full mismatches, and all four must give the same frames: verification
//! never changes what is drawn, only how much is re-recorded.
const std = @import("std");
const ui = @import("../core.zig");
const raw_shadow = @import("render_engine/raw_shadow.zig");
const view = @import("../view.zig");
const h = @import("translate_render_tests.zig");
const testing = std.testing;

const Cx = ui.Cx;
const Node = ui.Node;
const Color = ui.Color;
const World = h.World;
const Config = h.Config;

fn applyVerify(cfg: Config) void {
    h.applyBase(cfg);
    raw_shadow.disabled_override = !cfg.extra;
}

fn resetVerify() void {
    raw_shadow.disabled_override = null;
}

const four = [_]Config{
    .{ .name = "hookverify+check", .verify = true, .extra = true },
    .{ .name = "disabled+check", .verify = true, .extra = false },
    .{ .name = "hookverify", .verify = false, .extra = true },
    .{ .name = "disabled", .verify = false, .extra = false },
};

// ---------------------------------------------------------------- fuzz scene

const BorrowBuf = struct { bytes: [24]u8 };

/// Scene switch: overflow-clip containers (and toggling overflow_hidden on nodes with children).
/// Today's path used to replay a legacy overflow / promoted cache inside a hook-owned subtree, so
/// raw writes below a clip showed stale; fixed (render_engine buildNodeExecutionPlan
/// inside_hook_owned), see the today's-path test below.
var g_with_clip = true;
/// Op switch: in-place edits of a node's owned text buffer. Pre-existing and not fixed: such an
/// edit can show through another node's text item with the same content (text blob reuse by
/// content hash, whose cache key the edit does not change) on today's path; with verification on
/// the edited node is marked. Off for comparisons with today's path.
var g_inplace_owned = true;
var g_seed_base: u64 = 0x5eed_0000;

fn shelvesOf(w: *World) *[2]*Node {
    return @ptrCast(@alignCast(w.user[32..48]));
}

fn borrowBuf(w: *World) *BorrowBuf {
    return @ptrCast(@alignCast(&w.user));
}

/// Cards (hosted and ui.box), a container whose text_color its texts inherit, a borrowed-buffer
/// text, a clipping container, a 6-deep chain.
fn buildFuzz(w: *World) !void {
    try h.makeRoot(w);
    const cx = w.cx;
    for (0..8) |i| {
        const x: f32 = @floatFromInt((i % 4) * 140 + 10);
        const y: f32 = @floatFromInt((i / 4) * 90 + 10);
        if (i % 2 == 0) {
            _ = try h.makeHostedCard(w.scope, cx, w.root, x, y, h.labels[i % h.labels.len]);
        } else {
            const c = try h.makeCard(cx, w.root, x, y, h.labels[i % h.labels.len]);
            if (g_extras) try w.nodes.append(testing.allocator, c);
        }
    }
    const inherit = try view.append(w.scope, cx, w.root, view.box(.{ .style = .{
        .position = .absolute,
        .inset = .{ .left = .{ .px = 620 }, .top = .{ .px = 20 } },
        .width = .{ .px = 200 },
        .height = .{ .px = 120 },
        .direction = .column,
        .text_color = Color.hex(0x2244aa),
        .background = Color.hex(0xfafafa),
    } }, .{
        view.text(.{}, "inherits color"),
        view.box(.{ .style = .{ .padding = ui.Padding.all(4) } }, .{view.text(.{}, "nested inherit")}),
    }));
    _ = inherit;
    // Borrowed (not owned) text buffer, edited in place.
    const bb = borrowBuf(w);
    @memcpy(bb.bytes[0..], "borrowed text buffer 000");
    const borrowed = try ui.text(cx, "x", .{ .font_size = 14, .color = Color.hex(0x111111) });
    var t = borrowed.getTextRaw().?;
    // setText retires the owned copy itself.
    t.content = bb.bytes[0..];
    t.owned = false;
    borrowed.setText(t);
    const holder = try ui.box(cx, .{ .position = .absolute, .inset = .{ .left = .{ .px = 620 }, .top = .{ .px = 160 } }, .width = .{ .px = 240 }, .height = .{ .px = 30 } }, .{});
    try holder.appendChild(cx.allocator, borrowed);
    try w.root.appendChild(cx.allocator, holder);
    // Clipping container with children crossing its edge.
    if (g_with_clip) {
    const clip = try ui.box(cx, .{ .position = .absolute, .inset = .{ .left = .{ .px = 40 }, .top = .{ .px = 300 } }, .width = .{ .px = 300 }, .height = .{ .px = 150 }, .overflow_hidden = true, .corner_radius = 10, .background = Color.hex(0xdddddd) }, .{});
    try w.root.appendChild(cx.allocator, clip);
    for (0..4) |i| _ = try h.makeCard(cx, clip, @floatFromInt(i * 90), @floatFromInt(i * 30), "clipped");
    }
    // Deep chain.
    var parent = w.root;
    for (0..6) |i| {
        const n = try ui.box(cx, .{ .padding = ui.Padding.all(3), .background = Color.rgba(@intCast(40 * i), 100, 160, 255), .position = if (i == 0) .absolute else .relative, .inset = if (i == 0) .{ .left = .{ .px = 700 }, .top = .{ .px = 300 } } else .{} }, .{});
        try parent.appendChild(cx.allocator, n);
        parent = n;
    }
    const deep = try h.makeCard(cx, parent, 0, 0, "deep");
    if (g_extras) {
        try w.nodes.append(testing.allocator, deep);
        // Popover-like overlay root (z_index > 0) whose own `main` hook repositions it and writes
        // raw into itself and a descendant; it keeps a promoted / legacy surface across frames.
        const ov = try ui.box(cx, .{ .position = .absolute, .z_index = 3, .will_change_transform = true, .overflow_hidden = true, .corner_radius = 8, .inset = .{ .left = .{ .px = 900 }, .top = .{ .px = 60 } }, .width = .{ .px = 260 }, .height = .{ .px = 160 }, .background = Color.hex(0xfafafa), .direction = .column }, .{});
        const row = try ui.box(cx, .{ .width = .{ .px = 240 }, .height = .{ .px = 70 }, .overflow_hidden = true, .background = Color.hex(0xdddddd) }, .{});
        for (0..2) |i| _ = try h.makeCard(cx, row, @floatFromInt(i * 110), 0, "pop");
        try ov.appendChild(cx.allocator, row);
        try w.root.appendChild(cx.allocator, ov);
        ov.meta.per_frame.hooks.before_render.main = overlayFuzzMain;
        // Two shelves holding the movable cards, so hooks land on their parents and moves leave
        // a hook subtree.
        // Same placement for both, so a card moved from one to the other keeps its rect (no
        // layout-driven re-record hides a stale replay).
        for (0..2) |si| {
            const shelf = try ui.box(cx, .{ .position = .absolute, .inset = .{ .left = .{ .px = 40 }, .top = .{ .px = 480 } }, .width = .{ .px = 280 }, .height = .{ .px = 200 } }, .{});
            try w.root.appendChild(cx.allocator, shelf);
            shelvesOf(w)[si] = shelf;
            // A fixed child: a shelf never becomes a leaf when its cards leave (an overflow-clip
            // leaf replays an empty clip pair, pre-existing, see op 16 of fuzzStep).
            try shelf.appendChild(cx.allocator, try ui.box(cx, .{ .width = .{ .px = 4 }, .height = .{ .px = 4 } }, .{}));
            for (w.nodes.items, 0..) |c, ci| if (ci % 2 == si) try shelf.appendChild(cx.allocator, c);
        }
        // Plain leaves (a flow child of a shelf, no children of their own): moved to the tree root
        // they are re-placed, but nothing below re-records them.
        for (0..2) |si| {
            const leaf = try ui.box(cx, .{ .width = .{ .px = 30 }, .height = .{ .px = 20 }, .background = Color.hex(0x2244aa) }, .{});
            try shelvesOf(w)[si].appendChild(cx.allocator, leaf);
            try w.nodes.append(testing.allocator, leaf);
        }
    }
}

/// Transition fuzz extras: movable cards (w.nodes) and a Popover-like overlay.
var g_extras = false;

fn overlayFuzzMain(node: *Node) void {
    const f = @as(usize, @intFromFloat(@import("render_engine/mod.zig").current_frame_time_ms / 8.0));
    node.setTranslateX(@floatFromInt(f % 3));
    switch (f % 5) {
        1 => node.setBackgroundRaw(Color.rgba(@intCast((f * 41) % 250), 200, 220, 255)),
        3 => if (node.children.items.len > 0 and node.children.items[0].children.items.len > 0) {
            node.children.items[0].children.items[0].setBackgroundRaw(Color.rgba(@intCast((f * 17) % 250), 60, 60, 255));
        },
        else => {},
    }
}

fn isInSubtree(node: *Node, root: *Node) bool {
    var cur: ?*Node = node;
    while (cur) |c| : (cur = c.parent) if (c == root) return true;
    return false;
}

/// Raw write to a movable card, then move it to another parent in the same tick.
fn reparentWrite(w: *World, rng: std.Random) void {
    if (w.nodes.items.len < 2) return;
    const m = w.nodes.items[rng.uintLessThan(usize, w.nodes.items.len)];
    m.setBackgroundRaw(Color.rgba(rng.int(u8), rng.int(u8), 10, 255));
    if (m.children.items.len > 0) m.children.items[0].setBackgroundRaw(Color.rgba(10, rng.int(u8), rng.int(u8), 255));
    const q = if (rng.boolean()) w.root else w.nodes.items[rng.uintLessThan(usize, w.nodes.items.len)];
    if (q == m or isInSubtree(q, m)) return;
    q.appendChild(w.cx.allocator, m) catch {};
}

fn collect(node: *Node, out: *std.ArrayList(*Node)) void {
    out.append(testing.allocator, node) catch return;
    for (node.children.items) |c| collect(c, out);
}

/// One random raw (or ordinary) write. Deterministic in (seed, tree shape).
fn randomWrite(w: *World, rng: std.Random) void {
    var nodes: std.ArrayList(*Node) = .empty;
    defer nodes.deinit(testing.allocator);
    collect(w.root, &nodes);
    const n = nodes.items[rng.uintLessThan(usize, nodes.items.len)];
    const cx = w.cx;
    const c = Color.rgba(rng.int(u8), rng.int(u8), rng.int(u8), 255);
    switch (rng.uintLessThan(u8, 18)) {
        0 => n.setBackgroundRaw(c),
        1 => n.setOpacityRaw(0.4 + @as(f32, @floatFromInt(rng.uintLessThan(u8, 7))) * 0.1),
        2 => n.style.border.color = c,
        3 => n.style.border.width = @floatFromInt(rng.uintLessThan(u8, 3)),
        4 => n.style.translate_x = @as(f32, @floatFromInt(rng.uintLessThan(u16, 60))) * 0.5 - 15,
        5 => if (n.style.ext) |e| {
            e.corner_radius = .{ .each = .{ 2, @floatFromInt(rng.uintLessThan(u8, 20)), 2, 2 } };
        },
        6 => if (n.style.ext) |e| {
            if (e.shadow_count > 0) e.shadows[0].color = c else e.shadow_count = 0;
        },
        7 => if (n.style.ext) |e| {
            if (e.gradient) |*g| g.to = c;
        },
        // Inherited text style raw write (descendants read it).
        8 => if (n.style.ext) |e| {
            if (e.text_color != null) e.text_color = c;
        },
        9 => if (g_inplace_owned) if (n.getTextRaw()) |t| {
            // In place, same length.
            if (t.content.len > 0) {
                const bytes: []u8 = @constCast(t.content);
                bytes[rng.uintLessThan(usize, bytes.len)] = 'a' + rng.uintLessThan(u8, 26);
            }
        },
        10 => {
            const bb = borrowBuf(w);
            bb.bytes[21 + rng.uintLessThan(usize, 3)] = '0' + rng.uintLessThan(u8, 10);
        },
        11 => if (n.getIcon()) |ic| {
            var x = ic;
            x.tint = c;
            n.setIcon(x); // raw: setIcon marks nothing
        },
        12 => if (n.children.items.len >= 2) {
            // Child order behind the API's back.
            const items = n.children.items;
            std.mem.swap(*Node, &items[0], &items[items.len - 1]);
        },
        13 => if (n.element_id_raw != 0xFFFFFFFF) {
            // World rect behind layout's back (like a scrollbar writing its rect).
            const eid = ui.world.ElementId.fromRaw(n.element_id_raw);
            if (cx.world.layout.rect(eid)) |r| {
                var r2 = r;
                r2.x += 1;
                cx.world.layout.setRect(eid, r2);
            }
        },
        14 => n.setBackground(c), // ordinary marked write, mixed in
        15 => n.setStyleInline(cx.allocator, .{ .translate_y = @as(f32, @floatFromInt(rng.uintLessThan(u8, 20))) - 10 }),
        // Only on nodes with children: an overflow-clip leaf replays its legacy overflow cache
        // with an empty push/pop pair the fresh record elides (pre-existing, any hook scope).
        16 => if (g_with_clip and n.children.items.len > 0) {
            n.style.overflow_hidden = !n.style.overflow_hidden;
        },
        17 => if (n.style.ext) |e| {
            e.outline = .{ .width = 1, .color = c, .offset = 1 };
        },
        else => unreachable,
    }
}

fn fuzzHook(w: *World, frame: usize) void {
    var prng = std.Random.DefaultPrng.init(g_seed_base + frame * 7919);
    const rng = prng.random();
    const k = rng.uintLessThan(usize, 4);
    for (0..k) |_| randomWrite(w, rng);
    // Static frames now and then (nothing written at all).
}

/// Between frames, like an event handler or timer: raw writes outside the hook.
fn fuzzBetween(w: *World, cfg: Config) !void {
    _ = cfg;
    var prng = std.Random.DefaultPrng.init((g_seed_base ^ 0xbee5_0000) + w.frame * 104729);
    const rng = prng.random();
    if (rng.uintLessThan(u8, 3) == 0) randomWrite(w, rng);
}

const verified_pair = [_]Config{ four[0], four[2] };

test "hook verify fuzz: random raw writes (clips included), incremental == full and check on == off, several seeds" {
    defer resetVerify();
    defer g_seed_base = 0x5eed_0000;
    g_with_clip = true;
    const frames = 200;
    for ([_]u64{ 0x5eed_0000, 0x1234_5678, 0xdead_beef }) |seed| {
        g_seed_base = seed;
        const t = try h.runLockstep(&verified_pair, buildFuzz, fuzzHook, .{ .frames = frames, .hook_scope = .subtree, .apply = applyVerify, .after_frame = fuzzBetween });
        defer testing.allocator.free(t);
        h.printTotals("hook-verify fuzz clip", &verified_pair, t, frames);
        try testing.expectEqual(@as(u64, 0), t[0].mismatches);
        try testing.expect(t[0].hv_diffs > frames / 2); // the raw writes were seen
    }
}

test "hook verify fuzz: clip scene, all four configurations (today's path included) agree" {
    // Regression of the legacy overflow / promoted replay inside hook-owned subtrees (raw writes
    // below a clip used to show stale with verification off).
    defer resetVerify();
    defer g_inplace_owned = true;
    g_with_clip = true;
    g_inplace_owned = false;
    for ([_]u64{ 0x5eed_0000, 0x1234_5678 }) |seed| {
        g_seed_base = seed;
        const t = try h.runLockstep(&four, buildFuzz, fuzzHook, .{ .frames = 160, .hook_scope = .subtree, .apply = applyVerify, .after_frame = fuzzBetween });
        defer testing.allocator.free(t);
        try testing.expectEqual(@as(u64, 0), t[0].mismatches);
        try testing.expectEqual(@as(u64, 0), t[1].mismatches);
    }
    g_seed_base = 0x5eed_0000;
}

test "hook verify fuzz: random raw writes (no clip), all four configurations give the same frames, several seeds" {
    defer resetVerify();
    defer g_with_clip = true;
    defer g_seed_base = 0x5eed_0000;
    g_with_clip = false;
    g_inplace_owned = false;
    defer g_inplace_owned = true;
    const frames = 200;
    for ([_]u64{ 0x5eed_0000, 0x1234_5678, 0xdead_beef }) |seed| {
        g_seed_base = seed;
        const t = try h.runLockstep(&four, buildFuzz, fuzzHook, .{ .frames = frames, .hook_scope = .subtree, .apply = applyVerify, .after_frame = fuzzBetween });
        defer testing.allocator.free(t);
        h.printTotals("hook-verify fuzz", &four, t, frames);
        try testing.expectEqual(@as(u64, 0), t[0].mismatches);
        try testing.expectEqual(@as(u64, 0), t[1].mismatches);
        // Verification really let caches work (else this tests nothing).
        try testing.expect(t[0].rebuilds < t[1].rebuilds);
    }
}

// ---------------------------------------------------------------- static frames, counters

fn staticHook(w: *World, frame: usize) void {
    _ = frame;
    // Rewrites the same values every frame (setters and raw), changes nothing.
    for (w.nodes.items) |n| {
        n.setBackgroundRaw(n.getBackground());
        n.style.border.width = n.style.border.width;
        n.setStyleInline(w.cx.allocator, .{ .translate_x = n.style.translate_x });
    }
}

test "hook verify: static frames report zero differences after the first verified frame" {
    defer resetVerify();
    const cfgs = [_]Config{ four[0], four[1] };
    const t = try h.runLockstep(&cfgs, h.buildS4, staticHook, .{ .frames = 30, .hook_scope = .subtree, .apply = applyVerify });
    defer testing.allocator.free(t);
    h.printTotals("hook-verify static", &cfgs, t, 30);
    try testing.expectEqual(@as(u64, 0), t[0].hv_diffs_warm);
    try testing.expect(t[0].hv_nodes >= 1001 * 30);
    // Static and verified: nothing re-recorded but the root path.
    try testing.expect(t[0].rebuilds < t[1].rebuilds / 10);
}

test "hook verify: S4 under the app's .subtree hook reuses the cards (counters) and matches the unverified path" {
    defer resetVerify();
    const frames = 10;
    const cfgs = [_]Config{ four[0], four[1] };
    const t = try h.runLockstep(&cfgs, h.buildS4, h.s4Move, .{ .frames = frames, .hook_scope = .subtree, .apply = applyVerify });
    defer testing.allocator.free(t);
    h.printTotals("hook-verify S4", &cfgs, t, frames);
    // First two frames build the shadows / caches.
    try testing.expect((t[0].own_hits + t[0].splices) / frames >= 400);
    try testing.expect(t[0].memo_self / frames >= 300);
    try testing.expect(t[0].rebuilds <= 10 * frames + 1001 * 3);
    // Unverified: every node re-recorded every frame.
    try testing.expect(t[1].rebuilds >= 1001 * frames);
}

// ---------------------------------------------------------------- unverifiable nodes

fn drawSquare(dc: ui.DrawContext, _: ?*anyopaque) anyerror!void {
    _ = dc;
}

var g_draw_node: ?*Node = null;

fn buildUnverifiable(w: *World) !void {
    try h.makeRoot(w);
    const holder = try view.append(w.scope, w.cx, w.root, view.box(.{ .style = .{ .position = .absolute, .inset = .{ .left = .{ .px = 50 }, .top = .{ .px = 50 } }, .width = .{ .px = 300 }, .height = .{ .px = 200 }, .background = Color.hex(0xeeeeee) } }, .{}));
    const drawn = try view.append(w.scope, w.cx, holder, view.box(.{ .style = .{ .width = .{ .px = 40 }, .height = .{ .px = 40 }, .background = Color.hex(0x884422) } }, .{}));
    drawn.meta.per_frame.custom_hooks.draw = .{ .callback = drawSquare };
    try w.nodes.append(testing.allocator, drawn);
    try w.nodes.append(testing.allocator, holder);
    for (0..6) |i| _ = try h.makeHostedCard(w.scope, w.cx, w.root, @floatFromInt(400 + (i % 3) * 120), @floatFromInt(40 + (i / 3) * 90), "verifiable");
}

fn moveNothingButRaw(w: *World, frame: usize) void {
    // A raw write the custom-draw node's own content would show.
    w.nodes.items[0].setBackgroundRaw(Color.rgba(@intCast(frame % 250), 20, 20, 255));
}

test "hook verify: unverifiable (custom draw) nodes re-record every frame, their ancestors never splice / memo, the rest is reused" {
    defer resetVerify();
    const t = try h.runLockstep(&four, buildUnverifiable, moveNothingButRaw, .{ .frames = 20, .hook_scope = .subtree, .apply = applyVerify });
    defer testing.allocator.free(t);
    h.printTotals("hook-verify unverifiable", &four, t, 20);
    try testing.expect(t[0].hv_unverifiable >= 20);
    try testing.expectEqual(@as(u64, 0), t[0].mismatches);
    // The verifiable cards still reuse their caches.
    try testing.expect(t[0].rebuilds < t[1].rebuilds);
}

// ---------------------------------------------------------------- node cap, escape switch

test "hook verify: past the node cap the pass aborts and the frame takes today's path (same frames)" {
    defer resetVerify();
    const saved = raw_shadow.max_nodes_per_pass;
    defer raw_shadow.max_nodes_per_pass = saved;
    raw_shadow.max_nodes_per_pass = 10;
    g_with_clip = false;
    defer g_with_clip = true;
    g_inplace_owned = false;
    defer g_inplace_owned = true;
    const t = try h.runLockstep(&four, buildFuzz, fuzzHook, .{ .frames = 40, .hook_scope = .subtree, .apply = applyVerify });
    defer testing.allocator.free(t);
    h.printTotals("hook-verify cap", &four, t, 40);
    try testing.expect(t[0].hv_skipped >= 20);
    try testing.expectEqual(@as(u64, 0), t[0].mismatches);
    try testing.expectEqual(t[1].rebuilds, t[0].rebuilds);
}

test "hook verify: adaptive backoff stops verifying when the paint reuses too little, then retries (same frames)" {
    defer resetVerify();
    const saved = .{ raw_shadow.backoff_ratio, raw_shadow.backoff_streak, raw_shadow.backoff_passes };
    defer {
        raw_shadow.backoff_ratio = saved[0];
        raw_shadow.backoff_streak = saved[1];
        raw_shadow.backoff_passes = saved[2];
    }
    // Every verified frame counts as low benefit: back off after 3, for 5 frames, and so on.
    raw_shadow.backoff_ratio = 0;
    raw_shadow.backoff_streak = 3;
    raw_shadow.backoff_passes = 5;
    g_with_clip = false;
    defer g_with_clip = true;
    g_inplace_owned = false;
    defer g_inplace_owned = true;
    const t = try h.runLockstep(&four, buildFuzz, fuzzHook, .{ .frames = 48, .hook_scope = .subtree, .apply = applyVerify });
    defer testing.allocator.free(t);
    h.printTotals("hook-verify backoff", &four, t, 48);
    try testing.expectEqual(@as(u64, 0), t[0].mismatches);
    try testing.expect(t[0].hv_skipped >= 16); // backed off
    try testing.expect(t[0].hv_nodes > 0); // and verified again
}

test "hook verify: S4 and the default thresholds never back off" {
    defer resetVerify();
    const cfgs = [_]Config{ .{ .name = "hookverify", .verify = true, .extra = true } };
    const t = try h.runLockstep(&cfgs, h.buildS4, h.s4Move, .{ .frames = 60, .hook_scope = .subtree, .apply = applyVerify });
    defer testing.allocator.free(t);
    try testing.expectEqual(@as(u64, 0), t[0].hv_skipped);
}

test "hook verify: ZENIT_DISABLE_HOOK_VERIFY (override) verifies nothing and keeps today's full re-record" {
    defer resetVerify();
    const cfgs = [_]Config{ .{ .name = "disabled", .verify = true, .extra = false } };
    const t = try h.runLockstep(&cfgs, h.buildS4, h.s4Move, .{ .frames = 6, .hook_scope = .subtree, .apply = applyVerify });
    defer testing.allocator.free(t);
    try testing.expectEqual(@as(u64, 0), t[0].hv_nodes);
    try testing.expect(t[0].rebuilds >= 1001 * 6);
}

// ---------------------------------------------------------------- memory

test "hook verify: mounting and unmounting a 10k-node subtree under a verified hook frees every shadow" {
    defer resetVerify();
    raw_shadow.disabled_override = false;
    var cx = try Cx.init(testing.allocator, testing.io);
    defer cx.deinit();
    cx.setViewport(800, 600);
    const root = try ui.box(cx, .{ .width = .{ .px = 800 }, .height = .{ .px = 600 } }, .{});
    cx.root = root;
    root.addBeforeRenderScoped(noopHook, .subtree);
    for (0..3) |round| {
        const big = try ui.box(cx, .{ .width = .{ .px = 800 }, .height = .{ .px = 600 }, .direction = .row, .flex_wrap = .wrap }, .{});
        for (0..10_000) |i| {
            const leaf = try ui.box(cx, .{ .width = .{ .px = 4 }, .height = .{ .px = 4 }, .background = Color.rgba(@intCast(i % 255), 1, 1, 255) }, .{});
            try big.appendChild(cx.allocator, leaf);
        }
        try root.appendChild(cx.allocator, big);
        for (0..3) |f| {
            cx.frame_time_ms = @floatFromInt(round * 100 + f * 8 + 8);
            _ = cx.render();
            cx.layout();
        }
        try testing.expect(raw_shadow.shadowOf(big.children.items[0]) != null);
        root.removeChild(big);
        cx.freeNode(big);
        _ = cx.render();
        cx.layout();
    }
    // testing.allocator reports any shadow left behind at deinit.
}

fn noopHook(_: *Node) void {}

// ---------------------------------------------------------------- nested component (main) hook

/// Component-style `before_render.main` hook: writes its child raw every frame (ScrollArea's
/// scrollbar thumb, an Input caret blink).
fn componentMainHook(node: *Node) void {
    const f: u32 = @intFromFloat(@import("render_engine/mod.zig").current_frame_time_ms / 8.0);
    if (node.children.items.len > 0) node.children.items[0].setBackgroundRaw(Color.rgba(@intCast(f % 200), 90, 90, 255));
}

fn buildNestedMain(w: *World) !void {
    try h.makeRoot(w);
    const comp = try view.append(w.scope, w.cx, w.root, view.box(.{ .style = .{ .position = .absolute, .inset = .{ .left = .{ .px = 30 }, .top = .{ .px = 30 } }, .width = .{ .px = 200 }, .height = .{ .px = 100 }, .background = Color.hex(0xeeeeee) } }, .{
        view.box(.{ .style = .{ .width = .{ .px = 40 }, .height = .{ .px = 20 }, .background = Color.hex(0x333333) } }, .{}),
    }));
    comp.meta.per_frame.hooks.before_render.main = componentMainHook;
    for (0..6) |i| _ = try h.makeHostedCard(w.scope, w.cx, w.root, @floatFromInt(300 + (i % 3) * 120), @floatFromInt(40 + (i / 3) * 90), "beside");
}

test "hook verify: a nested component main hook keeps today's path for its subtree, the rest is verified" {
    defer resetVerify();
    g_with_clip = false;
    defer g_with_clip = true;
    g_inplace_owned = false;
    defer g_inplace_owned = true;
    const t = try h.runLockstep(&four, buildNestedMain, fuzzHook, .{ .frames = 40, .hook_scope = .subtree, .apply = applyVerify });
    defer testing.allocator.free(t);
    h.printTotals("hook-verify nested main", &four, t, 40);
    try testing.expectEqual(@as(u64, 0), t[0].mismatches);
    try testing.expect(t[0].rebuilds < t[1].rebuilds);
}

test "harness: two identical worlds (verification off) agree under the semantic cross-world compare" {
    // With raw_cross_compare (incremental_verify.compare's raw union bytes) this fails in
    // ReleaseFast at a path item: the inactive PathCommand payload bytes are undefined. It is
    // the comparison, not the frames, that differs.
    defer resetVerify();
    g_with_clip = false;
    defer g_with_clip = true;
    g_inplace_owned = false;
    defer g_inplace_owned = true;
    const same = [_]Config{ four[1], four[1] };
    const t = try h.runLockstep(&same, buildFuzz, fuzzHook, .{ .frames = 120, .hook_scope = .subtree, .apply = applyVerify, .after_frame = fuzzBetween });
    testing.allocator.free(t);
}

// ---------------------------------------------------------------- trust transitions

/// Component-style main hook installed / removed at random (writes its first child raw).
fn transitionMainHook(node: *Node) void {
    const f: u32 = @intFromFloat(@import("render_engine/mod.zig").current_frame_time_ms / 8.0);
    if (node.children.items.len > 0) {
        const c = node.children.items[0];
        c.setBackgroundRaw(Color.rgba(@intCast((f * 37) % 250), 40, 140, 255));
        c.style.translate_x = @floatFromInt(f % 9);
    }
}

/// fuzzHook plus trust transitions: some frames the pass runs out of budget (abort: nothing
/// trusted, then retried), and main hooks come and go on random nodes (verified -> excluded ->
/// verified).
fn transitionHook(w: *World, frame: usize) void {
    var prng = std.Random.DefaultPrng.init(g_seed_base ^ (0x7a11 + frame * 31337));
    const rng = prng.random();
    raw_shadow.max_nodes_per_pass = if (rng.uintLessThan(u8, 6) == 0) 12 else 16 * 1024;
    // Random adaptive backoffs (same transition as an abort, a few frames long). Not with
    // in-place owned text writes: during a backoff every hook takes today's path, which shows
    // those stale (pre-existing text blob aliasing, see g_inplace_owned).
    if (!g_inplace_owned and rng.uintLessThan(u8, 12) == 0) raw_shadow.force_backoff = true;
    var nodes: std.ArrayList(*Node) = .empty;
    defer nodes.deinit(testing.allocator);
    collect(w.root, &nodes);
    if (rng.uintLessThan(u8, 4) == 0) {
        const n = nodes.items[1 + rng.uintLessThan(usize, nodes.items.len - 1)];
        const hooks = &n.meta.per_frame.hooks.before_render;
        hooks.main = if (hooks.main == null) transitionMainHook else null;
        // What a component's mount does around a direct `before_render.main =` (addBeforeRender's
        // bookkeeping): without it a quiet subtree is not ticked, so whether the hook runs depends
        // on tick quiet stamps, which ZENIT_VERIFY_INCREMENTAL's reference pass perturbs.
        n.markSubtreeBeforeRenderHook();
        n.invalidateTickQuietChain();
    }
    g_movable = w.nodes.items;
    g_move_alloc = w.cx.allocator;
    if (g_extras) g_shelves = shelvesOf(w).*;
    transitionScopedHooks(w, frame, rng, nodes.items);
    // Raw writes from the root hook are only legal when it is `.subtree` (a `.dirty_marking`
    // hook's are audited); then the moves stay inside the verified tree. Moves out of a verified
    // subtree come from transitionSubtreeHook below.
    if (g_extras and g_root_writes and rng.uintLessThan(u8, 3) == 0) reparentWrite(w, rng);
    if (g_root_writes) fuzzHook(w, frame);
}

/// Root hook raw writes on (the root is `.subtree`, so they are verified) or off (the root is
/// `.dirty_marking`: the added `.subtree` hooks are then the outermost, top-level hook roots).
var g_root_writes = true;

fn frameNowT() usize {
    return @as(usize, @intFromFloat(@import("render_engine/mod.zig").current_frame_time_ms / 8.0)) -| 1;
}

/// An undeclared `.subtree` hook that writes its subtree raw and, now and then, goes away in the
/// same tick: removed (removeBeforeRender) or downgraded (re-registered as `.dirty_marking`).
fn transitionSubtreeHook(node: *Node) void {
    const f = frameNowT();
    node.setBackgroundRaw(Color.rgba(@intCast((f * 53 + node.id) % 250), 120, 30, 255));
    if (node.children.items.len > 0) node.children.items[0].setBackgroundRaw(Color.rgba(30, @intCast((f * 29) % 250), 90, 255));
    switch ((f + node.id) % 9) {
        0 => node.removeBeforeRender(transitionSubtreeHook),
        4 => {
            node.removeBeforeRender(transitionSubtreeHook);
            node.addBeforeRenderScoped(transitionTrustedHook, .dirty_marking);
        },
        6, 7 => if (g_extras) moveOutOfSubtree(node, f),
        else => {},
    }
}

fn transitionTrustedHook(_: *Node) void {}

var g_movable: []*Node = &.{};
var g_shelves: [2]*Node = undefined;
var g_move_alloc: std.mem.Allocator = undefined;

/// Inside an undeclared hook: write a movable card of its subtree raw and move it out of the
/// subtree (to the tree root) in the same tick.
fn moveOutOfSubtree(node: *Node, f: usize) void {
    var top = node;
    while (top.parent) |p| top = p;
    // Up to two movable cards of the subtree: the first leaves through appendChild (its old
    // parent's removeChildRetained), the second through replaceChildOrder (the old parent's new
    // order omits it, as For / Notification / WindowChrome do), then is placed elsewhere.
    var moved: usize = 0;
    for (g_movable) |m| {
        if (moved == 2) return;
        if (m == node or !isInSubtree(m, node)) continue;
        m.setBackgroundRaw(Color.rgba(@intCast((f * 23 + moved * 90) % 250), 200, 40, 255));
        // To the other shelf when it sits on one (same rect there), else (and every fourth time)
        // to the tree root.
        const dest = if (f % 4 == 3) top else if (m.parent == g_shelves[0]) g_shelves[1] else if (m.parent == g_shelves[1]) g_shelves[0] else top;
        if (moved == 1) if (m.parent) |old| {
            var keep: [64]*Node = undefined;
            var n: usize = 0;
            for (old.children.items) |c| if (c != m and n < keep.len) {
                keep[n] = c;
                n += 1;
            };
            if (n == old.children.items.len - 1) old.replaceChildOrder(g_move_alloc, keep[0..n]) catch {};
        };
        if (isInSubtree(dest, node)) {
            top.appendChild(g_move_alloc, m) catch {};
        } else dest.appendChild(g_move_alloc, m) catch {};
        moved += 1;
    }
}

fn transitionScopedHooks(w: *World, frame: usize, rng: std.Random, nodes: []*Node) void {
    _ = w;
    _ = frame;
    if (rng.uintLessThan(u8, 3) != 0) return;
    var n = nodes[1 + rng.uintLessThan(usize, nodes.len - 1)];
    // Often the parent of a movable card (so that moves out of a hook subtree happen).
    if (g_extras and g_movable.len > 0 and rng.boolean()) {
        const m = g_movable[rng.uintLessThan(usize, g_movable.len)];
        if (m.parent) |p| if (p.parent != null) {
            n = p;
        };
    }
    n.removeBeforeRender(transitionTrustedHook);
    n.addBeforeRenderScoped(transitionSubtreeHook, .subtree);
}

test "hook verify fuzz: trust transitions (random aborts, main hooks installed / removed, .subtree hooks removed / downgraded) stay equal to the full path" {
    defer resetVerify();
    const saved_cap = raw_shadow.max_nodes_per_pass;
    const saved_retry = raw_shadow.retry_after_passes;
    defer {
        raw_shadow.max_nodes_per_pass = saved_cap;
        raw_shadow.retry_after_passes = saved_retry;
        g_seed_base = 0x5eed_0000;
        g_with_clip = true;
    }
    raw_shadow.retry_after_passes = 2;
    const saved_backoff = raw_shadow.backoff_passes;
    raw_shadow.backoff_passes = 3;
    defer {
        raw_shadow.backoff_passes = saved_backoff;
        raw_shadow.force_backoff = false;
    }
    const frames = 160;
    defer g_root_writes = true;
    g_extras = true;
    defer g_extras = false;
    for ([_]bool{ true, false, false }, [_]ui.BeforeRenderScope{ .subtree, .subtree, .dirty_marking }) |with_clip, root_scope| {
        g_with_clip = with_clip;
        g_root_writes = root_scope == .subtree;
        g_inplace_owned = with_clip;
        defer g_inplace_owned = true;
        for ([_]u64{ 0x5eed_0000, 0x1234_5678, 0xdead_beef }) |seed| {
            g_seed_base = seed;
            // A `.subtree` hook that unregisters itself in the tick that wrote raw is not seen at
            // all on today's path (pre-existing): with top-level hook roots (trusted root hook)
            // only the verified configurations are compared.
            const cfgs: []const Config = if (with_clip or !g_root_writes) &verified_pair else &four;
            const t = try h.runLockstep(cfgs, buildFuzz, transitionHook, .{ .frames = frames, .hook_scope = root_scope, .apply = applyVerify, .after_frame = if (g_root_writes) fuzzBetween else null });
            defer testing.allocator.free(t);
            h.printTotals("hook-verify transitions", cfgs, t, frames);
            try testing.expectEqual(@as(u64, 0), t[0].mismatches);
            if (g_root_writes) try testing.expect(t[0].hv_skipped > 0); // aborts really happened
        }
    }
}

// ---------------------------------------------------------------- overlay slide (motion_offset)

const PopoverSlide = struct {
    var orig: ?*const fn (*Node) void = null;
    var n: usize = 0;
};

/// Popover content main hook plus an anchored enter slide the way a TransitionController /
/// Popover's anchored transition writes it: translate and StyleExt.motion_offset (its transient
/// part) raw, every frame, together with the opacity.
fn slidingPopoverHook(node: *Node) void {
    PopoverSlide.orig.?(node);
    PopoverSlide.n += 1;
    const off: f32 = 4.0 / @as(f32, @floatFromInt(PopoverSlide.n));
    const ext = node.style.ext orelse return;
    node.style.translate_y += off - ext.motion_offset[1];
    ext.motion_offset = .{ 0, off };
}

fn runSlidingPopover(check: bool, out_reused: *usize) !u64 {
    cx_render_mod.setVerifyIncrementalForTest(check);
    defer cx_render_mod.setVerifyIncrementalForTest(null);
    raw_shadow.disabled_override = false;
    defer raw_shadow.disabled_override = null;
    PopoverSlide.n = 0;
    var ctx = try ui.Cx.init(testing.allocator, testing.io);
    defer ctx.deinit();
    ctx.setViewport(640, 480);
    const root = try ui.box(ctx, .{ .width = .{ .px = 640 }, .height = .{ .px = 480 } }, .{});
    ctx.root = root;
    const scope = try @import("../reactive.zig").Scope.init(testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const result = try @import("../components/popover/mod.zig").Popover(.{ .position = .bottom_start, .trigger = .click }).mount(scope, ctx);
    try root.appendChild(testing.allocator, result.wrapper);
    try result.trigger.appendChild(testing.allocator, try ui.box(ctx, .{ .width = .{ .px = 120 }, .height = .{ .px = 32 } }, .{}));
    try result.content.appendChild(testing.allocator, try ui.text(ctx, "Stable popover text", .{}));
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
    _ = result.content.style.ensureExtPanic(ctx.allocator);
    // Popover registers its positioning hook `.dirty_marking`; this scenario needs it as the
    // overlay root's undeclared `main` hook (raw writes on top), as it used to be.
    PopoverSlide.orig = popoverAsMainHook(result.content);
    result.content.meta.per_frame.hooks.before_render.main = slidingPopoverHook;
    var mism: u64 = 0;
    out_reused.* = 0;
    for (0..6) |_| {
        ctx.frame_time_ms += 16;
        ctx.incremental_verify_mismatch_total = 0;
        ctx.layout();
        _ = ctx.render();
        mism += ctx.incremental_verify_mismatch_total;
        if (ctx.scene_runtime.get(result.content.id).?.promoted_surface_flags.reused_this_frame) out_reused.* += 1;
    }
    return mism;
}

const cx_render_mod = @import("cx_render.zig");

test "hook verify: an overlay root's raw translate + motion_offset slide keeps its promoted surface (composite only) and matches the full path" {
    var reused: usize = 0;
    try testing.expectEqual(@as(u64, 0), try runSlidingPopover(true, &reused));
    _ = try runSlidingPopover(false, &reused);
    // The first hooked frame records once (its shadow is new); every later one reuses.
    try testing.expect(reused >= 4);
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
