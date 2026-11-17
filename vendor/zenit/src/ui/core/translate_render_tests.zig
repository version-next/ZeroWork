//! Translate-only render fast path (node_dirty.markOwnTranslationDirty -> `pipeline.transform`):
//! a node moved by translate alone keeps its node-local caches (own payload, its own subtree
//! payload, a retained memo rooted at it) and only its ancestors are invalidated.
//!
//! The scenes run in lockstep under several configurations (fast path on / off, incremental
//! verify on / off): every frame of a verified configuration must show zero incremental-vs-full
//! mismatches, and every configuration must produce the same lowered frames as the first one
//! (incremental_verify.compare: frame-local ids skipped, floats within 0.001).
const std = @import("std");
const ui = @import("../core.zig");
const node_dirty = @import("node_dirty.zig");
const cx_render = @import("cx_render.zig");
const retained_memo = @import("render_engine/retained_memo.zig");
const view = @import("../view.zig");
const Scope = @import("../reactive.zig").Scope;
const W = @import("../components/mod.zig");
const verify = @import("render_engine/incremental_verify.zig");
const testing = std.testing;

const Cx = ui.Cx;
const Node = ui.Node;
const Color = ui.Color;
const BoxStyle = ui.BoxStyle;

// ---------------------------------------------------------------- lockstep harness

pub const Config = struct {
    name: []const u8,
    /// node_dirty translate-only render fast path.
    fast: bool = true,
    /// ZENIT_VERIFY_INCREMENTAL for every frame.
    verify: bool = true,
    /// Extra per-configuration switch (set by the caller's `apply`, e.g. hook verification).
    extra: bool = true,
};

pub const Totals = struct {
    mismatches: u64 = 0,
    memo_self: u64 = 0,
    memo_replays: u64 = 0,
    own_hits: u64 = 0,
    splices: u64 = 0,
    rebuilds: u64 = 0,
    paint_nodes: u64 = 0,
    exact_frames: usize = 0,
    /// raw_shadow.zig counters (hook verification).
    hv_nodes: u64 = 0,
    hv_diffs: u64 = 0,
    hv_unverifiable: u64 = 0,
    hv_skipped: u64 = 0,
    /// hv_diffs of the frames from the third on (shadows exist), and the largest of them.
    hv_diffs_warm: u64 = 0,
    hv_diffs_warm_max: u32 = 0,
};

/// One scene instance (its own Cx) driven by one configuration.
pub const World = struct {
    cx: *Cx,
    scope: *Scope,
    root: *Node = undefined,
    nodes: std.ArrayList(*Node) = .empty,
    totals: Totals = .{},
    frame: usize = 0,
    /// Scene-specific data (buffers etc.), owned by the scene.
    user: [256]u8 = undefined,
};

pub const BuildFn = *const fn (w: *World) anyerror!void;
pub const MoveFn = *const fn (w: *World, frame: usize) void;
/// Applies a configuration's global switches right before its world renders.
pub const ApplyFn = *const fn (cfg: Config) void;

var g_world: ?*World = null;
/// The last rendered frame's perf counters (Cx.layout resets cx.perf).
pub var last_perf: ui.PerfCounters = .{};
var g_move: ?MoveFn = null;

fn worldHook(_: *Node) void {
    const w = g_world orelse return;
    if (g_move) |m| m(w, w.frame);
}

pub fn applyBase(cfg: Config) void {
    node_dirty.translate_render_fast_path_override = cfg.fast;
    cx_render.setVerifyIncrementalForTest(cfg.verify);
}

fn resetSwitches() void {
    node_dirty.translate_render_fast_path_override = null;
    cx_render.setVerifyIncrementalForTest(null);
}

/// Frame hash of the lowered output (geometry, color, kind, text bytes): bit-identity only.
pub fn loweredHash(cx: *Cx) u64 {
    var h = std.hash.Wyhash.init(0);
    for (cx.lowering.main_paint.items) |it| {
        h.update(std.mem.asBytes(&it.geom));
        h.update(std.mem.asBytes(&it.color));
        h.update(std.mem.asBytes(&it.kind));
        h.update(it.text_content);
    }
    return h.final();
}

fn renderWorld(w: *World, cfg: Config, apply: ApplyFn, move: MoveFn) void {
    apply(cfg);
    g_world = w;
    g_move = move;
    defer g_move = null;
    w.cx.frame_time_ms = @as(f64, @floatFromInt(w.frame + 1)) * 8.0;
    w.cx.incremental_verify_mismatch_total = 0;
    _ = w.cx.render();
    // Cx.layout resets the per-frame counters: read them first.
    const p = w.cx.perf;
    last_perf = p;
    w.totals.mismatches += w.cx.incremental_verify_mismatch_total;
    w.totals.memo_self += p.rn_memo_self_translation_replays;
    w.totals.memo_replays += p.rn_memo_replays;
    w.totals.own_hits += p.own_payload_cache_hit_count;
    w.totals.splices += p.subtree_payload_splice_count;
    w.totals.rebuilds += p.rn_paint_rebuilds;
    w.totals.paint_nodes += p.rn_paint_nodes;
    w.totals.hv_nodes += p.hook_verify_nodes;
    w.totals.hv_diffs += p.hook_verify_diffs;
    w.totals.hv_unverifiable += p.hook_verify_unverifiable;
    w.totals.hv_skipped += p.hook_verify_skipped_cap;
    if (w.frame >= 2) {
        w.totals.hv_diffs_warm += p.hook_verify_diffs;
        w.totals.hv_diffs_warm_max = @max(w.totals.hv_diffs_warm_max, p.hook_verify_diffs);
    }
    w.cx.layout();
}

pub const Options = struct {
    hook_scope: ui.BeforeRenderScope = .dirty_marking,
    frames: usize = 60,
    viewport: [2]f32 = .{ 1280, 720 },
    apply: ApplyFn = applyBase,
    /// Called on every world after each frame (assertions on node state).
    after_frame: ?*const fn (w: *World, cfg: Config) anyerror!void = null,
};

/// Runs `configs` in lockstep over the same scene. Returns the totals of each configuration
/// (caller frees). Fails on any verified mismatch or any frame that differs from configs[0].
pub fn runLockstep(configs: []const Config, build: BuildFn, move: MoveFn, opts: Options) ![]Totals {
    defer resetSwitches();
    const worlds = try testing.allocator.alloc(World, configs.len);
    defer testing.allocator.free(worlds);
    var built: usize = 0;
    defer for (worlds[0..built]) |*w| {
        w.nodes.deinit(testing.allocator);
        w.scope.dispose();
        w.cx.deinit();
    };
    for (worlds, configs) |*w, cfg| {
        opts.apply(cfg);
        const cx = try Cx.init(testing.allocator, testing.io);
        cx.setViewport(opts.viewport[0], opts.viewport[1]);
        const scope = Scope.init(testing.allocator, null, cx.owner) catch |e| {
            cx.deinit();
            return e;
        };
        w.* = .{ .cx = cx, .scope = scope };
        built += 1;
        try build(w);
        w.cx.root = w.root;
        _ = w.cx.render();
        w.cx.layout();
        w.root.addBeforeRenderScoped(worldHook, opts.hook_scope);
    }
    for (0..opts.frames) |f| {
        for (worlds, configs) |*w, cfg| {
            w.frame = f;
            const before = w.totals.mismatches;
            renderWorld(w, cfg, opts.apply, move);
            if (w.totals.mismatches != before) std.debug.print("[lockstep] frame {d}: config {s} incremental != full ({d} mismatches)\n", .{ f, cfg.name, w.totals.mismatches - before });
        }
        const ref = worlds[0].cx.lowering.main_paint.items;
        const ref_hash = loweredHash(worlds[0].cx);
        if (ref_hash == loweredHash(worlds[0].cx)) worlds[0].totals.exact_frames += 1;
        for (worlds[1..], configs[1..]) |*w, cfg| {
            const r = if (raw_cross_compare) verify.compare(w.cx.lowering.main_paint.items, ref) else crossWorldCompare(w.cx.lowering.main_paint.items, ref);
            if (r.mismatches != 0) {
                std.debug.print("\n[lockstep] frame {d}: config {s} differs from {s} in {d} items (len {d} vs {d}), first {d}.{s}\n", .{ f, cfg.name, configs[0].name, r.mismatches, r.lhs_len, r.rhs_len, r.first.?.index, r.first.?.field });
                const li = w.cx.lowering.main_paint.items;
                const fi = r.first.?.index;
                if (fi < li.len and fi < ref.len) std.debug.print("[lockstep]   {s}: kind={s} text=\"{s}\" geom=({d:.1},{d:.1},{d:.1}x{d:.1}) | {s}: kind={s} text=\"{s}\" geom=({d:.1},{d:.1},{d:.1}x{d:.1})\n", .{ cfg.name, @tagName(li[fi].kind), li[fi].text_content, li[fi].geom.x, li[fi].geom.y, li[fi].geom.w, li[fi].geom.h, configs[0].name, @tagName(ref[fi].kind), ref[fi].text_content, ref[fi].geom.x, ref[fi].geom.y, ref[fi].geom.w, ref[fi].geom.h });
                return error.FramesDiffer;
            }
            if (loweredHash(w.cx) == ref_hash) w.totals.exact_frames += 1;
        }
        // After the comparison: lowered text may borrow a buffer the callback edits.
        if (opts.after_frame) |af| for (worlds, configs) |*w, cfg| {
            opts.apply(cfg);
            try af(w, cfg);
        };
        for (worlds, configs) |*w, cfg| {
            if (cfg.verify and w.totals.mismatches != 0) {
                std.debug.print("\n[lockstep] frame {d}: config {s} incremental != full ({d} mismatches)\n", .{ f, cfg.name, w.totals.mismatches });
                return error.IncrementalMismatch;
            }
        }
    }
    const out = try testing.allocator.alloc(Totals, configs.len);
    for (worlds, out) |*w, *o| o.* = w.totals;
    return out;
}

/// incremental_verify.compare across two Cx instances, except path_geometry_ptr, compared
/// semantically here: incremental_verify's eqlValue falls back to raw bytes for unions, so it
/// compares the inactive payload bytes of PathCommand, which are undefined (ReleaseFast leaves
/// different garbage in two Cx instances even with identical configurations; the DIAG test in
/// hook_verify_tests shows two worlds with verification off differing there).
pub var raw_cross_compare = false;
fn pathEql(a: ?*const ui.PathGeometry, b: ?*const ui.PathGeometry) bool {
    if (a == null or b == null) return (a == null) == (b == null);
    const x = a.?;
    const y = b.?;
    if (x.fill_rule != y.fill_rule or x.commands.len != y.commands.len) return false;
    if (!verify.eqlValue(@TypeOf(x.bounds), x.bounds, y.bounds)) return false;
    for (x.commands, y.commands) |cx_, cy| {
        if (std.meta.activeTag(cx_) != std.meta.activeTag(cy)) return false;
        const same = switch (cx_) {
            .move_to => |p| verify.eqlValue(@TypeOf(p), p, cy.move_to),
            .line_to => |p| verify.eqlValue(@TypeOf(p), p, cy.line_to),
            .quad_to => |p| verify.eqlValue(@TypeOf(p), p, cy.quad_to),
            .cubic_to => |p| verify.eqlValue(@TypeOf(p), p, cy.cubic_to),
            .close => true,
        };
        if (!same) return false;
    }
    return true;
}

fn crossWorldCompare(lhs: []const verify.Item, rhs: []const verify.Item) verify.Result {
    var result: verify.Result = .{ .lhs_len = lhs.len, .rhs_len = rhs.len };
    const n = @min(lhs.len, rhs.len);
    for (0..n) |i| {
        var a = lhs[i];
        var b = rhs[i];
        const path_same = pathEql(a.path_geometry_ptr, b.path_geometry_ptr);
        a.path_geometry_ptr = null;
        b.path_geometry_ptr = null;
        const field: ?[]const u8 = if (!path_same) "path_geometry_ptr" else verify.firstDifference(a, b);
        if (field) |f| {
            result.mismatches += 1;
            if (result.first == null) result.first = .{ .index = i, .field = f };
        }
    }
    const extra = @max(lhs.len, rhs.len) - n;
    if (extra > 0) {
        result.mismatches += extra;
        if (result.first == null) result.first = .{ .index = n, .field = "<length>" };
    }
    return result;
}

pub fn printTotals(tag: []const u8, configs: []const Config, totals: []const Totals, frames: usize) void {
    for (configs, totals) |c, t| {
        std.debug.print("[{s}] {s}: mismatches={d} rebuilds={d} paint_nodes={d} own_hits={d} splices={d} memo={d} (self {d}) exact_frames={d}/{d} hv nodes={d} diffs={d} (warm {d}, max {d}) unverifiable={d} skipped={d}\n", .{ tag, c.name, t.mismatches, t.rebuilds, t.paint_nodes, t.own_hits, t.splices, t.memo_replays, t.memo_self, t.exact_frames, frames, t.hv_nodes, t.hv_diffs, t.hv_diffs_warm, t.hv_diffs_warm_max, t.hv_unverifiable, t.hv_skipped });
    }
}

// ---------------------------------------------------------------- scene pieces

pub fn cardStyle(x: f32, y: f32) BoxStyle {
    return .{
        .position = .absolute,
        .inset = .{ .left = .{ .px = x }, .top = .{ .px = y } },
        .width = .{ .px = 96 },
        .height = .{ .px = 64 },
        .corner_radius = 12,
        .background = Color.WHITE,
        .gradient = .{ .from = Color.hex(0x4f7cff), .to = Color.hex(0x8a5cff), .direction = .diagonal },
        .shadow = .{ .blur = 16, .offset_y = 4, .color = Color.rgba(0, 0, 0, 64) },
    };
}

pub const labels = [_][]const u8{ "card one", "card two", "第三张", "four 4", "fünf", "six six" };

/// Card with a text line and an icon (content whose raster / snap could depend on placement),
/// built with ui.box (no style host: setStyleInline restyles fully).
pub fn makeCard(cx: *Cx, parent: *Node, x: f32, y: f32, label: []const u8) !*Node {
    const card = try ui.box(cx, cardStyle(x, y), .{});
    const t = try ui.text(cx, label, .{ .font_size = 13, .color = Color.hex(0x111111) });
    try card.appendChild(cx.allocator, t);
    const icon = try ui.iconTint(cx, ui.svg_assets.common.star, Color.hex(0xff2020), .{ .width = .{ .px = 16 }, .height = .{ .px = 16 } });
    try card.appendChild(cx.allocator, icon);
    try parent.appendChild(cx.allocator, card);
    return card;
}

/// Same card mounted through ui.view (a StyleHost owns its style): setStyleInline translate writes
/// take the in-place translate path, like apps/zenit S4.
pub fn makeHostedCard(scope: *Scope, cx: *Cx, parent: *Node, x: f32, y: f32, label: []const u8) !*Node {
    return view.append(scope, cx, parent, view.box(.{ .style = cardStyle(x, y) }, .{
        view.text(.{ .style = .{ .font_size = 13, .color = Color.hex(0x111111) } }, label),
        view.box(.{ .style = .{ .width = .{ .px = 20 }, .height = .{ .px = 8 }, .corner_radius = 4, .background = Color.hex(0x22aa44) } }, .{}),
    }));
}

pub fn makeRoot(w: *World) !void {
    w.root = try view.render(w.scope, w.cx, view.box(.{ .style = .{ .width = .{ .px = 1280 }, .height = .{ .px = 720 }, .background = Color.hex(0xf6f5f2) } }, .{}));
}

// ---------------------------------------------------------------- scene: wandering cards

/// 24 cards (half hosted, half ui.box), half of them inside a clipping container, plus a card
/// whose descendant sits far outside the viewport (culled when recorded).
pub fn buildWander(w: *World) !void {
    try makeRoot(w);
    const cx = w.cx;
    const clipper = try view.append(w.scope, cx, w.root, view.box(.{ .style = .{
        .position = .absolute,
        .inset = .{ .left = .{ .px = 600 }, .top = .{ .px = 300 } },
        .width = .{ .px = 400 },
        .height = .{ .px = 260 },
        .overflow_hidden = true,
        .background = Color.hex(0xe0e0e0),
    } }, .{}));
    for (0..24) |i| {
        const parent = if (i % 2 == 0) w.root else clipper;
        const x: f32 = @floatFromInt((i % 6) * 110 + 10);
        const y: f32 = @floatFromInt((i / 6) * 80 + 10);
        const card = if (i % 4 < 2)
            try makeHostedCard(w.scope, cx, parent, x, y, labels[i % labels.len])
        else
            try makeCard(cx, parent, x, y, labels[i % labels.len]);
        try w.nodes.append(testing.allocator, card);
    }
    const far = try makeHostedCard(w.scope, cx, w.root, 20, 600, "far");
    _ = try view.append(w.scope, cx, far, view.box(.{ .style = .{
        .position = .absolute,
        .inset = .{ .left = .{ .px = -800 }, .top = .{ .px = 10 } },
        .width = .{ .px = 30 },
        .height = .{ .px = 30 },
        .background = Color.hex(0x00aa00),
    } }, .{}));
    try w.nodes.append(testing.allocator, far);
}

/// Fractional offsets, an exact 0 now and then (culling switches on at translate 0), and large
/// jumps across the viewport / clip edges; writers alternate between setStyleInline and
/// setTranslateX.
pub fn wander(w: *World, frame: usize) void {
    for (w.nodes.items, 0..) |card, i| {
        const phase = @as(f32, @floatFromInt(frame)) * 0.37 + @as(f32, @floatFromInt(i)) * 0.9;
        var tx = @sin(phase) * 13.3;
        var ty = @cos(phase * 1.3) * 7.7;
        if ((frame + i) % 7 == 0) {
            tx = 0;
            ty = 0;
        }
        if ((frame + i) % 11 == 0) tx += 900;
        if ((frame * 3 + i) % 13 == 0) ty -= 400;
        if (i == w.nodes.items.len - 1 and frame % 5 == 0) tx = 820; // brings the far outlier in
        if (i % 3 != 2) {
            card.setStyleInline(w.cx.allocator, .{ .translate_x = tx, .translate_y = ty });
        } else {
            card.style.translate_y = ty;
            card.setTranslateX(tx);
        }
    }
}

const fast_slow = [_]Config{
    .{ .name = "fast+verify", .fast = true, .verify = true },
    .{ .name = "full+verify", .fast = false, .verify = true },
    .{ .name = "fast", .fast = true, .verify = false },
    .{ .name = "full", .fast = false, .verify = false },
};

test "translate fast path: wandering cards (text, clip edge, viewport edge, culled descendant) == full path, frame by frame" {
    const frames = 90;
    const t = try runLockstep(&fast_slow, buildWander, wander, .{ .frames = frames });
    defer testing.allocator.free(t);
    printTotals("translate-fast wander", &fast_slow, t, frames);
    // The fast path really ran: moved cards replayed their memo instead of re-recording (a moved
    // card's whole subtree splices as one, so the splice count itself is no measure).
    try testing.expect(t[0].memo_self > 0 and t[1].memo_self == 0);
    try testing.expect(t[0].rebuilds < t[1].rebuilds);
}

test "translate fast path: untrusted (.subtree) hook keeps today's full re-record and the same frames" {
    // Today's path: no raw-state verification (it would make the hook trusted, render_engine
    // raw_shadow.zig).
    const raw_shadow = @import("render_engine/raw_shadow.zig");
    raw_shadow.disabled_override = true;
    defer raw_shadow.disabled_override = null;
    const frames = 30;
    const t = try runLockstep(&fast_slow, buildWander, wander, .{ .frames = frames, .hook_scope = .subtree });
    defer testing.allocator.free(t);
    printTotals("translate-fast subtree", &fast_slow, t, frames);
    try testing.expectEqual(t[1].rebuilds, t[0].rebuilds);
}

// ---------------------------------------------------------------- fallbacks, one per condition

const Special = enum { opacity, scale, rotate, overflow_clip, blur, glass, sticky, promoted_z, out_of_band, composited_group, custom_draw };

fn drawNothing(_: ui.DrawContext, _: ?*anyopaque) anyerror!void {}

var g_special: Special = .opacity;

fn applySpecial(cx: *Cx, card: *Node, kind: Special) void {
    switch (kind) {
        .opacity => card.setOpacity(0.5),
        .scale => card.setStyleInline(cx.allocator, .{ .scale_x = 1.25 }),
        .rotate => card.setStyleInline(cx.allocator, .{ .rotate = 0.2 }),
        .overflow_clip => card.style.overflow_hidden = true,
        .blur => card.setStyleInline(cx.allocator, .{ .glass = .{ .backdrop_blur = 8, .glass_intensity = 0 } }),
        .glass => card.setStyleInline(cx.allocator, .{ .glass = .{ .backdrop_blur = 0, .glass_intensity = 1 } }),
        .sticky => card.style.position = .sticky,
        .promoted_z => card.setStyleInline(cx.allocator, .{ .z_index = 3, .will_change_transform = true }),
        .out_of_band => card.setStyleInline(cx.allocator, .{ .z_index = 2 }),
        .composited_group => card.setStyleInline(cx.allocator, .{ .composited_group = true }),
        .custom_draw => card.meta.per_frame.custom_hooks.draw = .{ .callback = drawNothing },
    }
    card.markRenderDirty();
}

fn buildSpecial(w: *World) !void {
    try makeRoot(w);
    // Custom draw on a leaf (Spinner / Progress shape): a custom-draw node with children shows
    // incremental != reference already with the fast path off (pre-existing, not translation).
    const special = if (g_special == .custom_draw)
        try view.append(w.scope, w.cx, w.root, view.box(.{ .style = cardStyle(100, 100) }, .{}))
    else
        try makeHostedCard(w.scope, w.cx, w.root, 100, 100, "special");
    const plain = try makeHostedCard(w.scope, w.cx, w.root, 300, 100, "plain");
    applySpecial(w.cx, special, g_special);
    try w.nodes.append(testing.allocator, special);
    try w.nodes.append(testing.allocator, plain);
}

fn moveSpecial(w: *World, frame: usize) void {
    for (w.nodes.items) |n| {
        const tx = @as(f32, @floatFromInt(frame % 9)) * 3.5 - 10;
        n.style.translate_y = -tx * 0.5;
        n.setTranslateX(tx);
    }
}

fn checkSpecialBits(w: *World, cfg: Config) !void {
    if (!cfg.fast or w.frame == 0) return;
    const special = w.nodes.items[0];
    const plain = w.nodes.items[1];
    // The paint pass cleared this frame's bits: re-mark to inspect what a translate write sets.
    try testing.expect(!node_dirty.translationRenderFastPathEligible(special));
    try testing.expect(node_dirty.translationRenderFastPathEligible(plain));
    special.setTranslateX(special.style.translate_x + 0.5);
    plain.setTranslateX(plain.style.translate_x + 0.5);
    try testing.expect(!special.frame_state.state_bits.dirty.pipeline.transform);
    try testing.expect(special.frame_state.state_bits.dirty.pipeline.composite);
    try testing.expect(plain.frame_state.state_bits.dirty.pipeline.transform);
    try testing.expect(!plain.frame_state.state_bits.dirty.pipeline.composite);
    try testing.expect(!plain.frame_state.state_bits.dirty.core.render);
    // Ancestor bits are what markCompositeDirty gives them.
    try testing.expect(w.root.frame_state.state_bits.dirty.pipeline.subtree_composite);
    try testing.expect(w.root.frame_state.state_bits.dirty.core.subtree_render);
}

test "translate fast path: every fallback condition takes the full composite path and matches the reference" {
    const all = [_]Special{ .opacity, .scale, .rotate, .overflow_clip, .blur, .glass, .sticky, .promoted_z, .out_of_band, .composited_group, .custom_draw };
    for (all) |kind| {
        g_special = kind;
        // Verified and unverified groups separately: with a custom-draw node the verified frames
        // differ from unverified ones already with the fast path off (pre-existing, unrelated
        // to translation); fast == full is what is checked here.
        for ([_][]const Config{ fast_slow[0..2], fast_slow[2..4] }) |group| {
            const t = runLockstep(group, buildSpecial, moveSpecial, .{ .frames = 16, .viewport = .{ 800, 600 }, .after_frame = checkSpecialBits }) catch |e| {
                std.debug.print("\n[translate-fast] fallback {s} failed: {s}\n", .{ @tagName(kind), @errorName(e) });
                return e;
            };
            testing.allocator.free(t);
        }
    }
}

test "translate fast path: eligibility screens manual animations and linger" {
    var cx = try Cx.init(testing.allocator, testing.io);
    defer cx.deinit();
    const root = try ui.box(cx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    cx.root = root;
    const card = try makeCard(cx, root, 10, 10, "x");
    _ = cx.render();
    try testing.expect(node_dirty.translationRenderFastPathEligible(card));
    card.frame_state.state_bits.flags.manual_transform_animation_active = true;
    try testing.expect(!node_dirty.translationRenderFastPathEligible(card));
    card.frame_state.state_bits.flags.manual_transform_animation_active = false;
    card.frame_state.frame_local.runtime.linger.transform = 2;
    try testing.expect(!node_dirty.translationRenderFastPathEligible(card));
    card.frame_state.frame_local.runtime.linger.transform = 0;
    try testing.expect(node_dirty.translationRenderFastPathEligible(card));
}

// ---------------------------------------------------------------- parent with a linear part

var g_parent_linear: BoxStyle = .{};

fn buildLinearParent(w: *World) !void {
    try makeRoot(w);
    var ps = g_parent_linear;
    ps.position = .absolute;
    ps.inset = .{ .left = .{ .px = 100 }, .top = .{ .px = 80 } };
    ps.width = .{ .px = 600 };
    ps.height = .{ .px = 400 };
    const parent = try view.append(w.scope, w.cx, w.root, view.box(.{ .style = ps }, .{}));
    for (0..6) |i| {
        try w.nodes.append(testing.allocator, try makeHostedCard(w.scope, w.cx, parent, @floatFromInt((i % 3) * 150 + 20), @floatFromInt((i / 3) * 120 + 20), "inner"));
    }
}

fn moveInner(w: *World, frame: usize) void {
    for (w.nodes.items, 0..) |n, i| {
        const tx = @sin(@as(f32, @floatFromInt(frame + i)) * 0.7) * 9.25;
        n.setStyleInline(w.cx.allocator, .{ .translate_x = tx, .translate_y = tx * 0.3 });
    }
}

test "translate fast path: cards under a scaled / rotated / translated parent replay exactly or fall back" {
    const parents = [_]BoxStyle{ .{ .scale_x = 1.5, .scale_y = 1.5 }, .{ .rotate = 0.3 }, .{ .translate_x = 0.5, .translate_y = 0.25 } };
    for (parents) |linear| {
        g_parent_linear = linear;
        const t = try runLockstep(&fast_slow, buildLinearParent, moveInner, .{ .frames = 30, .viewport = .{ 1000, 700 } });
        testing.allocator.free(t);
    }
}

// ---------------------------------------------------------------- counters (S4 shape)

pub fn buildS4(w: *World) !void {
    try makeRoot(w);
    for (0..500) |i| {
        const x = @as(f32, @floatFromInt(i % 25)) * 50 + 16;
        const y = @as(f32, @floatFromInt(i / 25)) * 34 + 16;
        try w.nodes.append(testing.allocator, try view.append(w.scope, w.cx, w.root, view.attrs(.{ .style = cardStyle(x, y) }, W.Card(.{ .width = 96, .height = 64, .padded = false }))));
    }
}

/// apps/zenit/v4 S4 updateMotion.
pub fn s4Move(w: *World, frame: usize) void {
    const t = @as(f64, @floatFromInt(frame)) / 120.0;
    for (w.nodes.items, 0..) |node, i| {
        const phase = 2 * std.math.pi * 0.25 * t + @as(f64, @floatFromInt(i)) * 0.1;
        node.setStyleInline(w.cx.allocator, .{
            .border_width = 0,
            .border_color = Color.TRANSPARENT,
            .shadow = .{ .blur = 16, .offset_y = 4, .color = Color.rgba(0, 0, 0, 64) },
            .translate_x = @as(f32, @floatCast(@sin(phase) * 12)),
            .translate_y = @as(f32, @floatCast(@cos(phase) * 12)),
        });
    }
}

test "translate fast path: S4 shape under a trusted hook reuses the cards (counters) and matches the full path" {
    const frames = 8;
    const cfgs = [_]Config{ .{ .name = "fast+verify", .fast = true }, .{ .name = "full+verify", .fast = false } };
    const t = try runLockstep(&cfgs, buildS4, s4Move, .{ .frames = frames });
    defer testing.allocator.free(t);
    printTotals("translate-fast S4", &cfgs, t, frames);
    // Per frame after warm-up (first frames write the caches): every card reused, ~all memos.
    const per_frame_reuse = (t[0].own_hits + t[0].splices) / frames;
    try testing.expect(per_frame_reuse >= 400);
    try testing.expect(t[0].memo_self / frames >= 300);
    try testing.expect(t[0].rebuilds <= 10 * frames + 1001 * 2);
    try testing.expect(t[1].memo_self == 0);
}

// ---------------------------------------------------------------- bookkeeping

fn selfMoveHook(node: *Node) void {
    node.setTranslateX(node.style.translate_x + 1);
}

test "translate fast path: a hook moving its own node still requests the next frame, root move is not zero-dirty" {
    defer node_dirty.translate_render_fast_path_override = null;
    for ([_]bool{ true, false }) |fast| {
        node_dirty.translate_render_fast_path_override = fast;
        var cx = try Cx.init(testing.allocator, testing.io);
        defer cx.deinit();
        const root = try ui.box(cx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
        cx.root = root;
        const card = try makeCard(cx, root, 10, 10, "self");
        _ = cx.render();
        card.addBeforeRenderScoped(selfMoveHook, .dirty_marking);
        cx.frame_time_ms = 8;
        _ = cx.render();
        try testing.expect(cx.last_tick_animations_active);
        try testing.expect(!card.frame_state.state_bits.dirty.pipeline.transform);
        // A translate-only move of the root itself must not take the zero-dirty fast path.
        root.setTranslateX(3);
        try testing.expect(!cx_render.isTreeFullyClean(cx, root));
    }
}
