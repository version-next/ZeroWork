//! Translate-only hit-index path (node_dirty.markTranslationDirty -> cx_runtime_index.
//! commitPendingTranslations -> HitRuntime.translateSubtree): after any sequence of translate
//! writes (mixed with other changes that take the rebuild path) the incrementally maintained
//! index answers every query exactly like an index rebuilt from scratch over the same tree, and a
//! frame that only moves nodes rebuilds nothing.
const std = @import("std");
const ui = @import("../core.zig");
const hit_runtime = @import("hit_runtime.zig");
const types = @import("types.zig");
const testing = std.testing;

const Cx = ui.Cx;
const Node = ui.Node;
const BoxStyle = ui.BoxStyle;
const HitRuntime = hit_runtime.HitRuntime;
const HitQueryKind = hit_runtime.HitQueryKind;
const HitResult = hit_runtime.HitResult;
const Spatial = @FieldType(@FieldType(@FieldType(Node, "frame_state"), "frame_local"), "spatial");

fn twoProxyProvider(node: *const Node, _: ?*anyopaque, out: []types.HitProxySpec) usize {
    if (out.len < 2) return 0;
    const r = node.rectFromWorldOrFallback();
    out[0] = .{ .local_rect = types.ComputedRect.init(-6, -6, r.w + 12, r.h + 12), .behavior = .self_only };
    out[1] = .{ .local_rect = types.ComputedRect.init(0, 0, r.w, r.h), .behavior = .self_only };
    return 2;
}

fn diagonalHalf(_: *const Node, x: f32, y: f32, _: ?*anyopaque) bool {
    return x >= y;
}

fn attached(cx: *Cx, node: *Node) bool {
    var cur: ?*Node = node;
    while (cur) |n| : (cur = n.parent) if (n == cx.root.?) return true;
    return false;
}

fn collectTree(node: *Node, out: *std.ArrayList(*Node)) !void {
    try out.append(testing.allocator, node);
    for (node.children.items) |child| try collectTree(child, out);
}

fn expectNoPendingTranslation(node: *Node) !void {
    try testing.expect(!node.frame_state.state_bits.dirty.hit.translation);
    try testing.expect(!node.frame_state.state_bits.dirty.hit.subtree_translation);
    for (node.children.items) |child| try expectNoPendingTranslation(child);
}

const kinds = [_]HitQueryKind{ .pointer, .scroll, .inspect, .window_chrome };

/// One query's answer, identity-only (proxy ids and block / layer ids are allocation details of
/// one index): best hit, and every accepting node in paint order (the paint rank of each hit).
const Answer = struct {
    best: ?HitResult,
    ranked: []u32,
};

fn askAll(rt: *HitRuntime, cx: *Cx, points: []const [2]f32, out: *std.ArrayList(Answer)) !void {
    for (points) |p| for (kinds) |kind| {
        const q: hit_runtime.HitQuery = .{ .kind = kind, .world_x = p[0], .world_y = p[1] };
        const best = rt.hitTestQuery(q, &cx.node_registry, null);
        const all = try rt.collectHitsForTest(testing.allocator, q, &cx.node_registry);
        defer testing.allocator.free(all);
        // The broadphase finds what an exhaustive scan finds.
        if (all.len == 0) try testing.expect(best == null) else {
            try testing.expect(best != null);
            try testing.expectEqual(all[0].node_id, best.?.node_id);
        }
        const ranked = try testing.allocator.alloc(u32, all.len);
        for (all, ranked) |h, *r| r.* = h.node_id;
        try out.append(testing.allocator, .{ .best = best, .ranked = ranked });
    };
}

fn freeAnswers(list: *std.ArrayList(Answer)) void {
    for (list.items) |a| testing.allocator.free(a.ranked);
    list.deinit(testing.allocator);
}

fn expectSameHit(a: ?HitResult, b: ?HitResult) !void {
    try testing.expectEqual(a == null, b == null);
    const x = a orelse return;
    const y = b.?;
    try testing.expectEqual(y.node_id, x.node_id);
    try testing.expectEqual(y.handle.id, x.handle.id);
    try testing.expectEqual(y.handle.generation, x.handle.generation);
    try testing.expectEqual(y.shape_kind, x.shape_kind);
    try testing.expectEqual(y.local_point.x, x.local_point.x);
    try testing.expectEqual(y.local_point.y, x.local_point.y);
}

fn proxyOf(rt: *const HitRuntime, s: Spatial, i: usize) hit_runtime.HitProxy {
    return rt.proxies.items[s.hit.proxy_start + i];
}

/// The live index of `cx` against `HitRuntime.rebuild` of the same tree: identical answers for
/// every query kind at `points` (best hit with handle, generation and local point, and the full
/// paint-ranked hit list), identical stored geometry per node. The node-side index state the
/// fresh build writes is restored afterwards, so the live index carries on.
fn expectMatchesFullRebuild(cx: *Cx, points: []const [2]f32) !void {
    const root = cx.root.?;
    try expectNoPendingTranslation(root);
    var nodes: std.ArrayList(*Node) = .empty;
    defer nodes.deinit(testing.allocator);
    try collectTree(root, &nodes);

    var live: std.ArrayList(Answer) = .empty;
    defer freeAnswers(&live);
    try askAll(&cx.interaction_index, cx, points, &live);

    const saved = try testing.allocator.alloc(Spatial, nodes.items.len);
    defer testing.allocator.free(saved);
    const saved_hit = try testing.allocator.alloc(@FieldType(@FieldType(@FieldType(Node, "frame_state"), "state_bits"), "dirty"), nodes.items.len);
    defer testing.allocator.free(saved_hit);
    for (nodes.items, saved, saved_hit) |n, *s, *d| {
        s.* = n.frame_state.frame_local.spatial;
        d.* = n.frame_state.state_bits.dirty;
    }
    defer for (nodes.items, saved, saved_hit) |n, s, d| {
        n.frame_state.frame_local.spatial = s;
        n.frame_state.state_bits.dirty = d;
    };

    var fresh = HitRuntime.init(testing.allocator);
    defer fresh.deinit();
    try fresh.rebuild(root, &cx.node_registry);
    var reference: std.ArrayList(Answer) = .empty;
    defer freeAnswers(&reference);
    try askAll(&fresh, cx, points, &reference);

    for (live.items, reference.items) |l, r| {
        try expectSameHit(l.best, r.best);
        try testing.expectEqualSlices(u32, r.ranked, l.ranked);
    }

    // Stored geometry, node by node.
    const inc = &cx.interaction_index;
    for (nodes.items, saved) |n, s| {
        const f = n.frame_state.frame_local.spatial;
        try testing.expectEqual(f.hit.proxy_len, s.hit.proxy_len);
        try testing.expectEqual(f.hit.clip_chain_id == null, s.hit.clip_chain_id == null);
        if (f.hit.proxy_len == 0 and f.hit.clip_chain_id == null) continue;
        try testing.expect(std.meta.eql(f.world.matrix, s.world.matrix));
        try testing.expect(std.meta.eql(f.world.inverse, s.world.inverse));
        for (0..f.hit.proxy_len) |i| {
            const fp = proxyOf(&fresh, f, i);
            const lp = proxyOf(inc, s, i);
            try testing.expect(lp.flags.alive);
            try testing.expect(std.meta.eql(fp.true_aabb, lp.true_aabb));
            try testing.expect(std.meta.eql(fp.local_rect, lp.local_rect));
            try testing.expectEqual(fp.roles, lp.roles);
            try testing.expectEqual(fp.behavior, lp.behavior);
            try testing.expect(std.meta.eql(fresh.shapes.items[fp.shape_id], inc.shapes.items[lp.shape_id]));
            // The broadphase leaf holds the proxy's true AABB.
            const leaf = inc.proxy_tree_nodes.items[s.hit.proxy_start + i];
            const tree = if (lp.layer == hit_runtime.root_layer) &inc.proxy_aabb_tree else &inc.layers.items[lp.layer - 1].tree;
            const fat = tree.nodes.items[leaf].aabb;
            try testing.expect(lp.true_aabb.x >= fat.x and lp.true_aabb.y >= fat.y and
                lp.true_aabb.x + lp.true_aabb.w <= fat.x + fat.w and lp.true_aabb.y + lp.true_aabb.h <= fat.y + fat.h);
        }
        if (f.hit.clip_chain_id) |fid| {
            const fe = fresh.clip_chain.items[fid];
            const le = inc.clip_chain.items[s.hit.clip_chain_id.?];
            try testing.expectEqual(fe.handle.id, le.handle.id);
            if (fe.handle.id == n.id) {
                try testing.expect(std.meta.eql(fe.world_aabb, le.world_aabb));
                try testing.expect(std.meta.eql(fe.inverse_world_transform, le.inverse_world_transform));
                try testing.expect(std.meta.eql(fe.local_rect, le.local_rect));
            }
        }
    }
}

const Gen = struct {
    cx: *Cx,
    rng: std.Random,
    all: std.ArrayList(*Node) = .empty,

    fn chance(self: *Gen, n: u32) bool {
        return self.rng.uintLessThan(u32, n) == 0;
    }

    fn node(self: *Gen, depth: u32, parent_w: f32, parent_h: f32) !*Node {
        const r = self.rng;
        const w: f32 = if (self.chance(25)) 0 else @floatFromInt(r.intRangeAtMost(u32, 6, @max(8, @as(u32, @intFromFloat(parent_w * 0.8)))));
        const h: f32 = if (self.chance(25)) 0 else @floatFromInt(r.intRangeAtMost(u32, 6, @max(8, @as(u32, @intFromFloat(parent_h * 0.8)))));
        var style: BoxStyle = .{ .width = .{ .px = w }, .height = .{ .px = h } };
        if (depth > 0 and !self.chance(4)) {
            style.position = .absolute;
            style.inset = .{
                .left = .{ .px = @floatFromInt(r.intRangeAtMost(i32, -20, @intFromFloat(parent_w))) },
                .top = .{ .px = @floatFromInt(r.intRangeAtMost(i32, -20, @intFromFloat(parent_h))) },
            };
        }
        if (self.chance(4)) style.overflow_hidden = true;
        if (self.chance(4)) style.corner_radius = r.float(f32) * 24;
        if (self.chance(9)) style.corner_radii = .{ .each = .{ r.float(f32) * 16, 0, r.float(f32) * 16, 4 } };
        if (self.chance(5)) style.z_index = r.intRangeAtMost(i16, -2, 5);
        if (self.chance(6)) style.hit_shape = switch (r.uintLessThan(u8, 5)) {
            0 => .circle,
            1 => .ellipse,
            2 => .{ .rounded_rect = 7 },
            3 => .none,
            else => .rect,
        };
        if (self.chance(6)) style.hit_behavior = switch (r.uintLessThan(u8, 5)) {
            0 => .@"opaque",
            1 => .pass_through,
            2 => .children_only,
            3 => .self_only,
            else => .self_and_children,
        };
        if (self.chance(8)) style.hit_roles = .{ .scroll = true };
        if (depth > 0 and self.chance(10)) {
            style.scale_x = 0.5 + r.float(f32);
            style.scale_y = 0.5 + r.float(f32);
        }
        if (depth > 0 and self.chance(10)) style.rotate = (r.float(f32) - 0.5) * 1.2;
        if (depth > 0 and self.chance(25)) style.display = .none;
        if (depth > 0 and self.chance(25)) style.opacity = 0;
        const n = try ui.box(self.cx, style, .{});
        try self.all.append(testing.allocator, n);
        if (self.chance(3)) n.behavior.interaction.focusable = true;
        if (depth > 0 and self.chance(9)) n.behavior.interaction.hit_layer = true;
        if (self.chance(25)) n.setHitProxyProvider(twoProxyProvider, null);
        if (self.chance(25)) {
            (try n.style.ensureExtFallible(self.cx.allocator)).hit_shape = .custom;
            n.meta.per_frame.custom_hooks.hit_test = .{ .callback = diagonalHalf };
        }
        if (depth < 4) {
            const count = r.uintLessThan(u32, if (depth == 0) 6 else 4);
            for (0..count) |_| {
                if (self.all.items.len >= 56) break;
                try n.appendChild(self.cx.allocator, try self.node(depth + 1, @max(w, 40), @max(h, 40)));
            }
        }
        return n;
    }
};

fn moveTo(node: *Node, x: f32, y: f32) void {
    node.setTranslateX(x);
    if (node.style.translate_y != y) {
        node.style.translate_y = y;
        node.markOwnTranslationDirty();
    }
}

fn randomMove(rng: std.Random, node: *Node) void {
    const far = rng.uintLessThan(u8, 5) == 0;
    const span: f32 = if (far) 160 else 1.2;
    moveTo(node, node.style.translate_x + (rng.float(f32) - 0.5) * span, node.style.translate_y + (rng.float(f32) - 0.5) * span);
}

/// A non-translate change through its regular marking (it takes the rebuild path, in the same
/// commit as pending moves).
fn randomOtherChange(cx: *Cx, rng: std.Random, node: *Node) !void {
    const a = cx.allocator;
    switch (rng.uintLessThan(u8, 7)) {
        0 => {
            (try node.style.ensureExtFallible(a)).hit_behavior = if (rng.boolean()) .@"opaque" else .pass_through;
            node.markInteractionDirty();
        },
        1 => node.setRotate(a, (rng.float(f32) - 0.5) * 0.8),
        2 => {
            (try node.style.ensureExtFallible(a)).z_index = rng.intRangeAtMost(i16, -1, 6);
            node.markOrderDirty();
            node.markCompositePropDirty();
        },
        3 => {
            node.style.display = if (node.style.display == .none) .flex else .none;
            node.markSizingDirty();
        },
        4 => {
            node.style.width = .{ .px = @floatFromInt(rng.intRangeAtMost(u32, 0, 120)) };
            node.markSizingDirty();
        },
        5 => node.setOpacity(if (node.getOpacity() > 0.5) 0 else 1),
        else => {
            node.style.overflow_hidden = !node.style.overflow_hidden;
            node.markInteractionDirty();
            node.markRenderDirty();
        },
    }
}

fn randomPoints(rng: std.Random, buf: [][2]f32) void {
    // A grid over (and past) the viewport, plus scattered points.
    var i: usize = 0;
    var gy: f32 = -15;
    while (gy < 340 and i < buf.len) : (gy += 23) {
        var gx: f32 = -15;
        while (gx < 440 and i < buf.len) : (gx += 23) {
            buf[i] = .{ gx, gy };
            i += 1;
        }
    }
    while (i < buf.len) : (i += 1) buf[i] = .{ rng.float(f32) * 460 - 20, rng.float(f32) * 360 - 20 };
}

test "hit translation: incremental moves answer every query like a full rebuild (random trees)" {
    var moves: u64 = 0;
    var refits: u64 = 0;
    var fallbacks: u64 = 0;
    var pure_steps: u64 = 0;
    var pure_full: u64 = 0;
    for (0..24) |seed| {
        var prng = std.Random.DefaultPrng.init(0x5d4_0000 + seed);
        const rng = prng.random();
        const cx = try Cx.init(testing.allocator, std.testing.io);
        defer cx.deinit();
        cx.setViewport(420, 320);
        var gen: Gen = .{ .cx = cx, .rng = rng };
        defer gen.all.deinit(testing.allocator);
        const root = try gen.node(0, 420, 320);
        root.style.width = .{ .px = 420 };
        root.style.height = .{ .px = 320 };
        cx.root = root;
        cx.layout();
        _ = cx.render();
        cx.layout();

        var detached: std.ArrayList(*Node) = .empty;
        defer detached.deinit(testing.allocator);
        // Re-attached (so the tree frees them) on every exit.
        defer for (detached.items) |n| root.appendChild(cx.allocator, n) catch {};
        var points: [300][2]f32 = undefined;
        const stats0 = cx.interaction_index;
        for (0..36) |_| {
            const full_before = cx.input_perf.in_hit_full_rebuilds;
            const partial_before = cx.input_perf.in_hit_partial_rebuilds;
            const fallbacks_before = cx.interaction_index.stat_translation_fallbacks;
            // Moves: a few nodes, sometimes most of them, sometimes the root.
            const n_moves = if (rng.uintLessThan(u8, 4) == 0) gen.all.items.len else rng.intRangeAtMost(usize, 1, 6);
            // Moves of hit layers / callback-driven nodes are interaction changes from the start,
            // as is interaction work an earlier change left pending (an order rebuild keeps the
            // interaction bits of the roots it covered).
            var other = root.frame_state.state_bits.dirty.pipeline.subtree_interaction or
                @import("cx_runtime_index.zig").subtreeHasLooseInteractionDirty(cx, root);
            for (0..n_moves) |_| {
                const n = gen.all.items[rng.uintLessThan(usize, gen.all.items.len)];
                if (!@import("node_dirty.zig").translationDirtyEligible(n)) other = true;
                randomMove(rng, n);
            }
            if (rng.uintLessThan(u8, 4) == 0) {
                other = true;
                const n = gen.all.items[rng.uintLessThan(usize, gen.all.items.len)];
                if (n != root and attached(cx, n)) try randomOtherChange(cx, rng, n);
            }
            // Detach a moved subtree (moves while detached are pending inside it), re-attach later.
            if (rng.uintLessThan(u8, 6) == 0) {
                other = true;
                const n = gen.all.items[rng.uintLessThan(usize, gen.all.items.len)];
                if (n != root and n.parent != null and attached(cx, n)) {
                    randomMove(rng, n);
                    n.parent.?.removeChildRetained(n);
                    try detached.append(testing.allocator, n);
                }
            } else if (detached.items.len > 0 and rng.boolean()) {
                other = true;
                const n = detached.swapRemove(rng.uintLessThan(usize, detached.items.len));
                randomMove(rng, n);
                var target = gen.all.items[rng.uintLessThan(usize, gen.all.items.len)];
                if (!attached(cx, target) or target.isDescendantOf(n)) target = root;
                try target.appendChild(cx.allocator, n);
            }
            // Commit through each of the three index commit points: frame end (Cx.layout), the
            // frame's before-render tick (Cx.render; every step ends its frame with layout, so the
            // tick runs), an event-time refresh (pointer move).
            const path = rng.uintLessThan(u8, 3);
            switch (path) {
                0 => cx.layout(),
                1 => _ = cx.render(),
                else => cx.handleMouseMove(rng.float(f32) * 420, rng.float(f32) * 320),
            }
            randomPoints(rng, &points);
            try expectMatchesFullRebuild(cx, &points);
            if (path != 0) cx.layout();
            if (!other and cx.interaction_index.stat_translation_fallbacks == fallbacks_before) {
                // Pure moves the index could move: nothing rebuilt.
                pure_steps += 1;
                pure_full += cx.input_perf.in_hit_full_rebuilds - full_before;
                try testing.expectEqual(partial_before, cx.input_perf.in_hit_partial_rebuilds);
            }
        }
        moves += cx.interaction_index.stat_translation_moves -% stats0.stat_translation_moves;
        refits += cx.interaction_index.stat_translation_refits -% stats0.stat_translation_refits;
        fallbacks += cx.interaction_index.stat_translation_fallbacks -% stats0.stat_translation_fallbacks;
    }
    try testing.expectEqual(@as(u64, 0), pure_full);
    // The sweep exercised all three outcomes.
    try testing.expect(pure_steps > 100);
    try testing.expect(moves > 1000);
    try testing.expect(refits > 50);
    try testing.expect(fallbacks > 20);
}

test "hit translation: a moving clip with a scroll layer inside, and moving rows of that layer, need no rebuild" {
    const cx = try Cx.init(testing.allocator, std.testing.io);
    defer cx.deinit();
    cx.setViewport(400, 300);
    const root = try ui.box(cx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    cx.root = root;
    // A rounded clip panel under a rotated, scaled ancestor; inside it a scroll viewport whose
    // content is a hit layer.
    const tilt = try ui.box(cx, .{ .position = .absolute, .inset = .{ .left = .{ .px = 20 }, .top = .{ .px = 10 } }, .width = .{ .px = 300 }, .height = .{ .px = 260 }, .rotate = 0.15, .scale_x = 1.1, .scale_y = 0.9 }, .{});
    try root.appendChild(cx.allocator, tilt);
    const panel = try ui.box(cx, .{ .position = .absolute, .inset = .{ .left = .{ .px = 40 }, .top = .{ .px = 30 } }, .width = .{ .px = 220 }, .height = .{ .px = 200 }, .overflow_hidden = true, .corner_radius = 18 }, .{});
    try tilt.appendChild(cx.allocator, panel);
    const viewport = try ui.box(cx, .{ .position = .absolute, .inset = .{ .left = .{ .px = 10 }, .top = .{ .px = 20 } }, .width = .{ .px = 180 }, .height = .{ .px = 150 }, .overflow_hidden = true }, .{});
    try panel.appendChild(cx.allocator, viewport);
    const content = try ui.box(cx, .{ .width = .{ .px = 180 }, .height = .{ .px = 600 } }, .{});
    content.behavior.interaction.hit_layer = true;
    try viewport.appendChild(cx.allocator, content);
    var rows: [12]*Node = undefined;
    for (&rows, 0..) |*row, i| {
        row.* = try ui.box(cx, .{ .position = .absolute, .inset = .{ .left = .{ .px = 4 }, .top = .{ .px = @floatFromInt(i * 40) } }, .width = .{ .px = 160 }, .height = .{ .px = 34 }, .corner_radius = 6 }, .{});
        row.*.behavior.interaction.focusable = true;
        const chip = try ui.box(cx, .{ .position = .absolute, .inset = .{ .left = .{ .px = 100 }, .top = .{ .px = 4 } }, .width = .{ .px = 50 }, .height = .{ .px = 26 }, .hit_shape = .circle }, .{});
        chip.behavior.interaction.focusable = true;
        try row.*.appendChild(cx.allocator, chip);
        try content.appendChild(cx.allocator, row.*);
    }
    cx.layout();
    const full0 = cx.input_perf.in_hit_full_rebuilds;
    const partial0 = cx.input_perf.in_hit_partial_rebuilds;
    const fallbacks0 = cx.interaction_index.stat_translation_fallbacks;
    var points: [500][2]f32 = undefined;
    var prng = std.Random.DefaultPrng.init(77);
    const rng = prng.random();
    for (0..30) |f| {
        const t: f32 = @floatFromInt(f);
        moveTo(panel, @sin(t * 0.3) * 30, @cos(t * 0.2) * 20);
        for (rows, 0..) |row, i| if ((i + f) % 3 == 0) moveTo(row, @sin(t + @as(f32, @floatFromInt(i))) * 25, 0);
        cx.layout();
        for (&points) |*p| p.* = .{ rng.float(f32) * 400, rng.float(f32) * 300 };
        try expectMatchesFullRebuild(cx, &points);
    }
    try testing.expectEqual(full0, cx.input_perf.in_hit_full_rebuilds);
    try testing.expectEqual(partial0, cx.input_perf.in_hit_partial_rebuilds);
    try testing.expectEqual(fallbacks0, cx.interaction_index.stat_translation_fallbacks);

    // A moved node with its own scale / rotation takes the rebuild path (a partial root, not a
    // full rebuild), with the same answers.
    moveTo(tilt, 5, 5);
    cx.layout();
    try testing.expectEqual(fallbacks0 + 1, cx.interaction_index.stat_translation_fallbacks);
    try testing.expectEqual(full0, cx.input_perf.in_hit_full_rebuilds);
    try testing.expect(cx.input_perf.in_hit_partial_rebuilds > partial0);
    try expectMatchesFullRebuild(cx, &points);
}

/// S4 shape: 500 absolutely placed cards (each a box with one in-flow child) on one root, every
/// card's translate rewritten each frame.
const Cards = struct {
    cx: *Cx,
    cards: [500]*Node,

    fn init() !Cards {
        const cx = try Cx.init(testing.allocator, std.testing.io);
        errdefer cx.deinit();
        cx.setViewport(1280, 720);
        const root = try ui.box(cx, .{ .width = .{ .px = 1280 }, .height = .{ .px = 720 } }, .{});
        cx.root = root;
        var self: Cards = .{ .cx = cx, .cards = undefined };
        for (&self.cards, 0..) |*card, i| {
            const x: f32 = @floatFromInt((i % 25) * 50 + 16);
            const y: f32 = @floatFromInt((i / 25) * 34 + 16);
            card.* = try ui.box(cx, .{ .position = .absolute, .inset = .{ .left = .{ .px = x }, .top = .{ .px = y } }, .width = .{ .px = 96 }, .height = .{ .px = 64 }, .corner_radius = 12 }, .{});
            const body = try ui.box(cx, .{ .width = .{ .grow = .{} }, .height = .{ .grow = .{} }, .corner_radius = 12 }, .{});
            try card.*.appendChild(cx.allocator, body);
            try root.appendChild(cx.allocator, card.*);
        }
        cx.layout();
        return self;
    }

    fn frame(self: *Cards, t: f64) void {
        for (self.cards, 0..) |card, i| {
            const phase = 2 * std.math.pi * 0.25 * t + @as(f64, @floatFromInt(i)) * 0.1;
            moveTo(card, @floatCast(@sin(phase) * 12), @floatCast(@cos(phase) * 12));
        }
        self.cx.layout();
    }
};

test "hit translation: S4-shaped frames move 1000 proxies without any index rebuild" {
    var s = try Cards.init();
    defer s.cx.deinit();
    const cx = s.cx;
    const full0 = cx.input_perf.in_hit_full_rebuilds;
    const partial0 = cx.input_perf.in_hit_partial_rebuilds;
    const built0 = cx.interaction_index.stat_build_nodes;
    const moves0 = cx.interaction_index.stat_translation_moves;
    const epoch0 = cx.interaction_index.sceneEpoch();
    for (0..240) |f| s.frame(@as(f64, @floatFromInt(f)) / 120.0);
    try testing.expectEqual(full0, cx.input_perf.in_hit_full_rebuilds);
    try testing.expectEqual(partial0, cx.input_perf.in_hit_partial_rebuilds);
    try testing.expectEqual(built0, cx.interaction_index.stat_build_nodes);
    try testing.expectEqual(@as(u32, 0), cx.interaction_index.stat_translation_fallbacks);
    try testing.expectEqual(@as(u32, 240 * 1000), cx.interaction_index.stat_translation_moves - moves0);
    // Hover / cursor consumers still see a changed scene every frame.
    try testing.expect(cx.interaction_index.sceneEpoch() != epoch0);
    var points: [400][2]f32 = undefined;
    var prng = std.Random.DefaultPrng.init(4);
    for (&points) |*p| p.* = .{ prng.random().float(f32) * 1280, prng.random().float(f32) * 720 };
    try expectMatchesFullRebuild(cx, &points);
}

test "hit translation: with the path off, the same frames fall back to a full rebuild each" {
    Cx.setHitTranslationPathForTest(false);
    defer Cx.setHitTranslationPathForTest(true);
    var s = try Cards.init();
    defer s.cx.deinit();
    const full0 = s.cx.input_perf.in_hit_full_rebuilds;
    for (0..8) |f| s.frame(@as(f64, @floatFromInt(f)) / 120.0);
    // 500 interaction-dirty absolute cards overflow the 64 partial roots: one full rebuild a frame.
    try testing.expectEqual(full0 + 8, s.cx.input_perf.in_hit_full_rebuilds);
}

test "hit translation: a translate written through a style host marks the move, not interaction" {
    const v = @import("../view.zig");
    const W = @import("../components/mod.zig");
    const reactive = @import("../reactive.zig");
    const cx = try Cx.init(testing.allocator, std.testing.io);
    defer cx.deinit();
    cx.tokens = &@import("../theme.zig").light;
    cx.setViewport(400, 300);
    const scope = try reactive.Scope.init(testing.allocator, null, cx.owner);
    const root = try ui.box(cx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    cx.root = root;
    defer {
        scope.dispose();
    }
    var cards: [80]*Node = undefined;
    for (&cards, 0..) |*card, i| {
        const style: BoxStyle = .{ .position = .absolute, .inset = .{ .left = .{ .px = @floatFromInt((i % 10) * 36) }, .top = .{ .px = @floatFromInt((i / 10) * 30) } }, .width = .{ .px = 32 }, .height = .{ .px = 24 }, .corner_radius = 6, .border_width = 0, .shadow = .{ .blur = 8, .offset_y = 2 } };
        card.* = try v.append(scope, cx, root, v.attrs(.{ .style = style }, W.Card(.{ .width = 32, .height = 24, .padded = false })));
    }
    cx.layout();
    _ = cx.render();
    const full0 = cx.input_perf.in_hit_full_rebuilds;
    const partial0 = cx.input_perf.in_hit_partial_rebuilds;
    for (0..6) |f| {
        for (cards, 0..) |card, i| {
            const d: f32 = @floatFromInt(f * 3 + i % 7);
            // The S4 write: unchanged non-transform fields next to the moving translate.
            card.setStyleInline(cx.allocator, .{ .border_width = 0, .shadow = .{ .blur = 8, .offset_y = 2 }, .translate_x = d * 0.25, .translate_y = -d * 0.5 });
            try testing.expect(card.frame_state.state_bits.dirty.hit.translation);
            try testing.expect(!card.frame_state.state_bits.dirty.pipeline.interaction);
        }
        if (f % 2 == 0) cx.layout() else _ = cx.render();
    }
    try testing.expectEqual(full0, cx.input_perf.in_hit_full_rebuilds);
    try testing.expectEqual(partial0, cx.input_perf.in_hit_partial_rebuilds);
    var points: [300][2]f32 = undefined;
    var prng = std.Random.DefaultPrng.init(9);
    for (&points) |*p| p.* = .{ prng.random().float(f32) * 400, prng.random().float(f32) * 300 };
    try expectMatchesFullRebuild(cx, &points);

    // Changing a transform part other than translate still takes the rebuild path.
    cards[3].setStyleInline(cx.allocator, .{ .border_width = 0, .shadow = .{ .blur = 8, .offset_y = 2 }, .translate_x = 2, .translate_y = 1, .scale_x = 1.5 });
    try testing.expect(cards[3].frame_state.state_bits.dirty.pipeline.interaction);
    cx.layout();
    try expectMatchesFullRebuild(cx, &points);
}

// ── Layout reflow ──
//
// A layout pass places nodes the frame never marked: an in-flow size change resizes fit
// ancestors, which their own parents then re-center, re-align to the end, or push siblings with.
// Those nodes only move or resize as layout output; the index must follow them like a full rebuild
// would, whatever path the change took through the tree.

fn hitNodeId(cx: *Cx, x: f32, y: f32) ?u32 {
    const hit = cx.interaction_index.hitTestQuery(.{ .kind = .pointer, .world_x = x, .world_y = y }, &cx.node_registry, null) orelse return null;
    return hit.node_id;
}

fn gridPoints(buf: [][2]f32, w: f32, h: f32) void {
    var i: usize = 0;
    var gy: f32 = 1;
    while (gy < h and i < buf.len) : (gy += 9) {
        var gx: f32 = 1;
        while (gx < w and i < buf.len) : (gx += 9) {
            buf[i] = .{ gx, gy };
            i += 1;
        }
    }
    while (i < buf.len) : (i += 1) buf[i] = .{ w / 2, h / 2 };
}

test "hit layout reflow: a fit dialog centered in the window keeps header and footer hits when its body grows" {
    for (0..3) |path| {
        const cx = try Cx.init(testing.allocator, std.testing.io);
        defer cx.deinit();
        cx.setViewport(420, 320);
        // Window: centers the dialog (a Modal barrier). Dialog: fit height, clips (rounded frame).
        const root = try ui.box(cx, .{ .width = .{ .px = 420 }, .height = .{ .px = 320 }, .direction = .column, .justify = .center, .align_items = .center }, .{});
        cx.root = root;
        const dialog = try ui.box(cx, .{ .width = .{ .px = 200 }, .height = .{ .fit = .{} }, .direction = .column, .overflow_hidden = true }, .{});
        try root.appendChild(cx.allocator, dialog);
        const header = try ui.box(cx, .{ .width = .{ .px = 200 }, .height = .{ .px = 24 }, .direction = .row, .justify = .end }, .{});
        const close = try ui.box(cx, .{ .width = .{ .px = 20 }, .height = .{ .px = 20 } }, .{});
        close.behavior.interaction.focusable = true;
        try header.appendChild(cx.allocator, close);
        // Body: a scroll viewport (hit layer) around a fit content column (ScrollArea's shape).
        const body = try ui.box(cx, .{ .width = .{ .px = 200 }, .height = .{ .fit = .{} }, .direction = .column, .overflow_hidden = true }, .{});
        body.behavior.interaction.hit_layer = true;
        const column = try ui.box(cx, .{ .width = .{ .px = 200 }, .height = .{ .fit = .{} }, .direction = .column }, .{});
        try body.appendChild(cx.allocator, column);
        const content = try ui.box(cx, .{ .width = .{ .px = 200 }, .height = .{ .px = 40 } }, .{});
        content.behavior.interaction.focusable = true;
        try column.appendChild(cx.allocator, content);
        const footer = try ui.box(cx, .{ .width = .{ .px = 200 }, .height = .{ .px = 24 }, .direction = .row, .justify = .end }, .{});
        const run = try ui.box(cx, .{ .width = .{ .px = 60 }, .height = .{ .px = 20 } }, .{});
        run.behavior.interaction.focusable = true;
        try footer.appendChild(cx.allocator, run);
        for ([_]*Node{ header, body, footer }) |n| try dialog.appendChild(cx.allocator, n);
        cx.layout();
        _ = cx.render();
        cx.layout();
        const close0 = close.globalRect();
        try testing.expectEqual(@as(?u32, close.id), hitNodeId(cx, close0.x + 10, close0.y + 10));

        // Only the innermost box changes; header and footer move as layout output.
        content.style.height = .{ .px = 160 };
        content.markSizingDirty();
        switch (path) {
            0 => cx.layout(),
            1 => _ = cx.render(),
            else => cx.handleMouseMove(1, 1),
        }
        const close1 = close.globalRect();
        const run1 = run.globalRect();
        try testing.expect(close1.y < close0.y - 50);
        try testing.expectEqual(@as(?u32, close.id), hitNodeId(cx, close1.x + 10, close1.y + 10));
        try testing.expectEqual(@as(?u32, run.id), hitNodeId(cx, run1.x + 30, run1.y + 10));
        var points: [600][2]f32 = undefined;
        gridPoints(&points, 420, 320);
        try expectMatchesFullRebuild(cx, &points);
    }
}

/// Random flow trees: rows and columns with every justify / align, fit / px / grow sizes, gaps and
/// padding, clips, scroll layers, a few absolute children. Each step resizes a few leaves (the
/// change reflows ancestors and siblings through layout only) and commits through one of the
/// three commit points; the live index must answer like a full rebuild.
const FlowGen = struct {
    cx: *Cx,
    rng: std.Random,
    all: std.ArrayList(*Node) = .empty,
    leaves: std.ArrayList(*Node) = .empty,

    fn sizing(self: *FlowGen, depth: u32) types.Sizing {
        return switch (self.rng.uintLessThan(u8, if (depth == 0) 1 else 4)) {
            0 => .{ .px = @floatFromInt(self.rng.intRangeAtMost(u32, 20, 160)) },
            1, 2 => .{ .fit = .{} },
            else => .{ .grow = .{} },
        };
    }

    fn node(self: *FlowGen, depth: u32) !*Node {
        const r = self.rng;
        const leaf = depth >= 4 or (depth > 0 and r.uintLessThan(u8, 3) == 0);
        var style: BoxStyle = .{
            .direction = if (r.boolean()) .row else .column,
            .justify = switch (r.uintLessThan(u8, 4)) {
                0 => .start,
                1 => .center,
                2 => .end,
                else => .space_between,
            },
            .align_items = switch (r.uintLessThan(u8, 4)) {
                0 => .start,
                1 => .center,
                2 => .end,
                else => .stretch,
            },
            .gap = @floatFromInt(r.uintLessThan(u8, 3) * 3),
        };
        if (r.uintLessThan(u8, 3) == 0) style.padding = .{ .top = 3, .right = 5, .bottom = 2, .left = 4 };
        if (leaf) {
            style.width = .{ .px = @floatFromInt(r.intRangeAtMost(u32, 8, 60)) };
            style.height = .{ .px = @floatFromInt(r.intRangeAtMost(u32, 8, 40)) };
        } else {
            style.width = self.sizing(depth);
            style.height = self.sizing(depth);
        }
        if (depth > 0 and r.uintLessThan(u8, 5) == 0) style.overflow_hidden = true;
        if (depth > 0 and r.uintLessThan(u8, 12) == 0) {
            style.position = .absolute;
            style.inset = .{ .left = .{ .px = @floatFromInt(r.uintLessThan(u32, 40)) }, .bottom = .{ .px = @floatFromInt(r.uintLessThan(u32, 30)) } };
        }
        const n = try ui.box(self.cx, style, .{});
        try self.all.append(testing.allocator, n);
        if (r.uintLessThan(u8, 2) == 0) n.behavior.interaction.focusable = true;
        if (depth > 0 and !leaf and r.uintLessThan(u8, 8) == 0) n.behavior.interaction.hit_layer = true;
        if (leaf) {
            try self.leaves.append(testing.allocator, n);
        } else {
            const count = r.intRangeAtMost(u32, 1, 4);
            for (0..count) |_| {
                if (self.all.items.len >= 60) break;
                try n.appendChild(self.cx.allocator, try self.node(depth + 1));
            }
        }
        return n;
    }
};

test "hit layout reflow: leaf resizes in random flow trees answer every query like a full rebuild" {
    for (0..16) |seed| {
        var prng = std.Random.DefaultPrng.init(0xF10_0000 + seed);
        const rng = prng.random();
        const cx = try Cx.init(testing.allocator, std.testing.io);
        defer cx.deinit();
        cx.setViewport(420, 320);
        var gen: FlowGen = .{ .cx = cx, .rng = rng };
        defer gen.all.deinit(testing.allocator);
        defer gen.leaves.deinit(testing.allocator);
        const root = try gen.node(0);
        root.style.width = .{ .px = 420 };
        root.style.height = .{ .px = 320 };
        cx.root = root;
        cx.layout();
        _ = cx.render();
        cx.layout();
        var points: [400][2]f32 = undefined;
        for (0..24) |_| {
            const n_changes = rng.intRangeAtMost(usize, 1, 3);
            for (0..n_changes) |_| {
                if (gen.leaves.items.len == 0) break;
                const leaf = gen.leaves.items[rng.uintLessThan(usize, gen.leaves.items.len)];
                if (rng.boolean())
                    leaf.style.width = .{ .px = @floatFromInt(rng.intRangeAtMost(u32, 4, 90)) }
                else
                    leaf.style.height = .{ .px = @floatFromInt(rng.intRangeAtMost(u32, 4, 70)) };
                leaf.markSizingDirty();
            }
            switch (rng.uintLessThan(u8, 3)) {
                0 => cx.layout(),
                1 => _ = cx.render(),
                else => cx.handleMouseMove(rng.float(f32) * 420, rng.float(f32) * 320),
            }
            randomPoints(rng, &points);
            try expectMatchesFullRebuild(cx, &points);
            cx.layout();
        }
    }
}

test "hit layer: a reflow inside one block that resizes it moves the following sibling blocks' hit areas" {
    // Settings-page shape (ZeroWork MCP "查看"): a scroll content hit layer whose children are
    // blocks; a row appears deep inside one pane, the pane grows, and the next block (a reset row
    // with a button) moves down. Its hit area must move with it in the same frame.
    const cx = try Cx.init(testing.allocator, std.testing.io);
    defer cx.deinit();
    cx.setViewport(400, 400);
    const root = try ui.box(cx, .{ .width = .{ .px = 400 }, .height = .{ .px = 400 } }, .{});
    cx.root = root;
    const content = try ui.box(cx, .{ .width = .{ .px = 400 }, .height = .{ .fit = .{} }, .direction = .column }, .{});
    content.behavior.interaction.hit_layer = true;
    try root.appendChild(cx.allocator, content);
    const pane = try ui.box(cx, .{ .width = .{ .px = 400 }, .height = .{ .fit = .{} }, .direction = .column }, .{});
    try content.appendChild(cx.allocator, pane);
    const body = try ui.box(cx, .{ .width = .{ .px = 400 }, .height = .{ .fit = .{} }, .direction = .column }, .{});
    try pane.appendChild(cx.allocator, body);
    const list = try ui.box(cx, .{ .width = .{ .px = 400 }, .height = .{ .px = 20 } }, .{});
    try body.appendChild(cx.allocator, list);
    const row = try ui.box(cx, .{ .width = .{ .px = 400 }, .height = .{ .px = 40 } }, .{});
    try content.appendChild(cx.allocator, row);
    const button = try ui.box(cx, .{ .width = .{ .px = 120 }, .height = .{ .px = 24 } }, .{});
    button.behavior.interaction.focusable = true;
    try row.appendChild(cx.allocator, button);
    cx.layout();
    try testing.expect(cx.hitTest(60, 32) == button);

    // The row inside the pane grows by 57: the reset row moves from y 20 to y 77.
    list.style.height = .{ .px = 77 };
    list.markLayoutDirty();
    cx.layout();
    try testing.expectEqual(@as(f32, 77), button.globalRect().y);
    try testing.expect(cx.hitTest(60, 89) == button);
    try testing.expect(cx.hitTest(60, 32) != button);
    var points: [200][2]f32 = undefined;
    for (&points, 0..) |*p, i| p.* = .{ @floatFromInt((i * 37) % 400), @floatFromInt((i * 13) % 160) };
    try expectMatchesFullRebuild(cx, &points);
}

/// A row whose height an after-layout hook settles: it reads a content height, writes a px height
/// on a clipping viewport and asks for layout again (`.needs_layout`). Shape of a card that caps a
/// list of lines between one line and a maximum, with action buttons centered beside it and a
/// sibling card below.
const SettlingRow = struct {
    viewport: *Node,
    lines: *Node,
    rounds: usize = 0,

    fn afterLayout(raw: *anyopaque, _: u8, _: bool) ui.AfterLayoutResult {
        const self: *SettlingRow = @ptrCast(@alignCast(raw));
        self.rounds += 1;
        const want = std.math.clamp(self.lines.globalRect().h, 16, 80);
        if (@abs(self.viewport.globalRect().h - want) <= 0.5) return .done;
        self.viewport.setStyle(testing.allocator, .height, .{ .px = want });
        return .needs_layout;
    }
};

test "hit layout reflow: an after-layout hook that resizes a node and asks for layout moves its siblings' hits in the same frame" {
    for (0..3) |path| {
        errdefer std.debug.print("path {d}\n", .{path});
        const cx = try Cx.init(testing.allocator, std.testing.io);
        defer cx.deinit();
        cx.setViewport(420, 320);
        try cx.setTestFrameStep(16);
        const root = try ui.box(cx, .{ .width = .{ .px = 420 }, .height = .{ .px = 320 }, .direction = .column }, .{});
        cx.root = root;
        // card: [content: viewport(px, clips, scroll layer) > lines(fit column)] [actions: stop, takeover]
        const card = try ui.box(cx, .{ .width = .{ .px = 420 }, .height = .{ .fit = .{} }, .direction = .row, .align_items = .center }, .{});
        try root.appendChild(cx.allocator, card);
        const content = try ui.box(cx, .{ .width = .{ .grow = .{} }, .height = .{ .fit = .{} }, .direction = .column }, .{});
        try card.appendChild(cx.allocator, content);
        const viewport = try ui.box(cx, .{ .width = .{ .grow = .{} }, .height = .{ .px = 16 }, .direction = .column, .overflow_hidden = true }, .{});
        viewport.behavior.interaction.hit_layer = true;
        try content.appendChild(cx.allocator, viewport);
        const lines = try ui.box(cx, .{ .width = .{ .grow = .{} }, .height = .{ .fit = .{} }, .direction = .column }, .{});
        try viewport.appendChild(cx.allocator, lines);
        try lines.appendChild(cx.allocator, try ui.box(cx, .{ .width = .{ .px = 100 }, .height = .{ .px = 16 } }, .{}));
        const actions = try ui.box(cx, .{ .width = .{ .fit = .{} }, .height = .{ .fit = .{} }, .direction = .column, .gap = 4 }, .{});
        try card.appendChild(cx.allocator, actions);
        const stop = try ui.box(cx, .{ .width = .{ .px = 80 }, .height = .{ .px = 24 } }, .{});
        stop.behavior.interaction.focusable = true;
        const takeover = try ui.box(cx, .{ .width = .{ .px = 80 }, .height = .{ .px = 24 } }, .{});
        takeover.behavior.interaction.focusable = true;
        try actions.appendChild(cx.allocator, stop);
        try actions.appendChild(cx.allocator, takeover);
        // A sibling card below the row.
        const below = try ui.box(cx, .{ .width = .{ .px = 120 }, .height = .{ .px = 30 } }, .{});
        below.behavior.interaction.focusable = true;
        try root.appendChild(cx.allocator, below);

        var settle: SettlingRow = .{ .viewport = viewport, .lines = lines };
        try cx.addAfterLayoutHook(&settle, SettlingRow.afterLayout);
        defer cx.removeAfterLayoutHook(&settle);
        for (0..3) |_| {
            cx.advanceFrameClock();
            _ = cx.render();
        }
        const takeover0 = takeover.globalRect();
        const below0 = below.globalRect();
        try testing.expectEqual(@as(?u32, takeover.id), hitNodeId(cx, takeover0.x + 40, takeover0.y + 12));

        // The list grows to six lines: only the hook knows the viewport's new height (capped at 80).
        for (0..5) |_| try lines.appendChild(cx.allocator, try ui.box(cx, .{ .width = .{ .px = 100 }, .height = .{ .px = 16 } }, .{}));
        settle.rounds = 0;
        cx.advanceFrameClock();
        switch (path) {
            0 => _ = cx.render(),
            // An input event first: the hit-test refresh lays the tree out but does not run
            // after-layout hooks; the frame that follows does, and must leave no stale hit.
            1 => {
                cx.handleMouseMove(1, 1);
                _ = cx.render();
            },
            else => {
                _ = cx.render();
                cx.advanceFrameClock();
                _ = cx.render();
            },
        }
        try testing.expect(settle.rounds >= 2);
        try testing.expectApproxEqAbs(@as(f32, 80), viewport.globalRect().h, 0.5);
        const takeover1 = takeover.globalRect();
        const below1 = below.globalRect();
        try testing.expect(takeover1.y > takeover0.y + 10);
        try testing.expect(below1.y > below0.y + 20);
        try testing.expectEqual(@as(?u32, takeover.id), hitNodeId(cx, takeover1.x + 40, takeover1.y + 12));
        try testing.expectEqual(@as(?u32, stop.id), hitNodeId(cx, stop.globalRect().x + 40, stop.globalRect().y + 12));
        try testing.expectEqual(@as(?u32, below.id), hitNodeId(cx, below1.x + 60, below1.y + 15));
        var points: [600][2]f32 = undefined;
        gridPoints(&points, 420, 320);
        try expectMatchesFullRebuild(cx, &points);
    }
}
