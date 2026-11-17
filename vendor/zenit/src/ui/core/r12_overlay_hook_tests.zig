//! R12: the framework's overlay roots (Popover and everything built on it, Select, the
//! Notification viewport) register their per-frame hooks `.dirty_marking`. Their writes all go
//! through dirty-marking entries, so the overlay root is cache-trusted without the per-frame
//! raw-state verification (render_engine/raw_shadow.zig): its promoted surface is reused across
//! open / animation / reposition frames with verification on and with it off
//! (`raw_shadow.disabled_override = true`, the ZENIT_DISABLE_HOOK_VERIFY switch). Every frame is
//! also rendered a second time through the reference full path (incremental verify), which must
//! match, and the Debug before_render scope audit runs every frame (tick.zig
//! runBeforeRenderHook: an unmarked paint-state write of a scoped hook panics).
const std = @import("std");
const ui = @import("../core.zig");
const raw_shadow = @import("render_engine/raw_shadow.zig");
const tick_mod = @import("render_engine/tick.zig");
const cx_render = @import("cx_render.zig");
const Scope = @import("../reactive.zig").Scope;
const popover_mod = @import("../components/popover/mod.zig");
const select_mod = @import("../components/select/mod.zig");
const notification_mod = @import("../components/notification/mod.zig");

const testing = std.testing;
const Cx = ui.Cx;
const Node = ui.Node;

const Mode = struct {
    /// raw_shadow.disabled_override: ZENIT_DISABLE_HOOK_VERIFY=1 behavior.
    verify_disabled: bool,
    /// Control: move the hook back to the undeclared `main` slot (the pre-R12 registration).
    legacy_main: bool = false,
    /// Render every frame a second time through the reference full path and count mismatches.
    /// The reference pass re-records every surface, so reuse is counted in a run without it.
    check: bool = true,
};

const Stats = struct {
    frames: usize = 0,
    reused: usize = 0,
    rebuilt: usize = 0,
    mismatches: u64 = 0,
    /// Paint-pass node rebuilds (own content re-recorded) summed over the frames.
    rebuilds: usize = 0,
    /// Paint-pass cache replays (promoted / legacy overflow / subtree / memo) summed.
    replays: usize = 0,
};

fn begin(mode: Mode) void {
    cx_render.setVerifyIncrementalForTest(mode.check);
    raw_shadow.disabled_override = mode.verify_disabled;
    tick_mod.self_scope_audit_every_frame_cache = true;
}

fn end() void {
    cx_render.setVerifyIncrementalForTest(null);
    raw_shadow.disabled_override = null;
    tick_mod.self_scope_audit_every_frame_cache = null;
}

fn frame(ctx: *Cx, overlay_root: *Node, stats: *Stats) void {
    ctx.frame_time_ms += 16;
    ctx.incremental_verify_mismatch_total = 0;
    ctx.layout();
    _ = ctx.render();
    stats.mismatches += ctx.incremental_verify_mismatch_total;
    stats.frames += 1;
    stats.rebuilds += ctx.perf.rn_paint_rebuilds;
    stats.replays += ctx.perf.rn_paint_cache_replays + ctx.perf.rn_paint_subtree_replays + ctx.perf.rn_memo_replays;
    if (ctx.scene_runtime.get(overlay_root.id)) |rt| {
        if (rt.promoted_surface_flags.reused_this_frame) stats.reused += 1;
        if (rt.promoted_surface_flags.rebuilt_this_frame) stats.rebuilt += 1;
    }
}

/// The scenario twice: with the reference check (mismatches) and without it (surface reuse).
fn checked(comptime run: fn (Mode) anyerror!Stats, mode: Mode) !Stats {
    var with_check = mode;
    with_check.check = true;
    const a = try run(with_check);
    var without = mode;
    without.check = false;
    var b = try run(without);
    b.mismatches = a.mismatches;
    return b;
}

fn settle(ctx: *Cx, overlay_root: *Node) !void {
    var i: usize = 0;
    while (i < 12) : (i += 1) {
        ctx.frame_time_ms += 16;
        ctx.layout();
        _ = ctx.render();
        if (ctx.scene_runtime.get(overlay_root.id) != null) return;
    }
    return error.OverlayNeverRegistered;
}

/// The overlay root's hook is the declared `.dirty_marking` one (no `main`), so the node is
/// cache-trusted by declaration.
fn expectDeclared(node: *Node, hook: *const fn (*Node) void) !void {
    try testing.expect(node.meta.per_frame.hooks.before_render.main == null);
    try testing.expect(node.hasScopedBeforeRender(hook));
    try testing.expect(node.beforeRenderHooksScopedTrusted());
    try testing.expect(node.beforeRenderHooksCacheTrusted());
}

fn toLegacyMain(node: *Node, hook: *const fn (*Node) void) void {
    node.removeBeforeRender(hook);
    node.meta.per_frame.hooks.before_render.main = hook;
}

// ---------------------------------------------------------------------------------- Popover

/// Opens a click Popover (scale_fade enter), plays the enter animation, moves its anchor twice
/// (the popover is repositioned) and keeps it open.
fn runPopover(mode: Mode) !Stats {
    begin(mode);
    defer end();
    var ctx = try Cx.init(testing.allocator, testing.io);
    defer ctx.deinit();
    ctx.setViewport(640, 480);
    const root = try ui.box(ctx, .{ .width = .{ .px = 640 }, .height = .{ .px = 480 }, .direction = .column }, .{});
    ctx.root = root;
    const spacer = try ui.box(ctx, .{ .width = .{ .px = 10 }, .height = .{ .px = 40 } }, .{});
    try root.appendChild(testing.allocator, spacer);
    const scope = try Scope.init(testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const result = try popover_mod.Popover(.{ .position = .bottom_start, .trigger = .click }).mount(scope, ctx);
    try root.appendChild(testing.allocator, result.wrapper);
    try result.trigger.appendChild(testing.allocator, try ui.box(ctx, .{ .width = .{ .px = 120 }, .height = .{ .px = 32 } }, .{}));
    try result.content.appendChild(testing.allocator, try ui.text(ctx, "Stable popover text", .{}));
    try result.content.appendChild(testing.allocator, try ui.box(ctx, .{ .width = .{ .px = 80 }, .height = .{ .px = 20 }, .background = ui.Color.hex(0x2244aa) }, .{}));
    try expectDeclared(result.content, popover_mod.popoverBeforeRender);
    if (mode.legacy_main) toLegacyMain(result.content, popover_mod.popoverBeforeRender);

    ctx.layout();
    _ = ctx.render();
    result.open.?.set(true);
    try settle(ctx, result.content);

    var stats = Stats{};
    for (0..24) |f| {
        // Anchor moves: the positioning hook follows with a new translate.
        if (f == 14) spacer.setStyleInline(testing.allocator, .{ .height = .{ .px = 64 } });
        if (f == 19) spacer.setStyleInline(testing.allocator, .{ .height = .{ .px = 52 } });
        frame(ctx, result.content, &stats);
    }
    return stats;
}

test "r12 Popover: .dirty_marking positioning hook reuses the promoted surface with verification on, matches the full path" {
    const s = try checked(runPopover, .{ .verify_disabled = false });
    try testing.expectEqual(@as(u64, 0), s.mismatches);
    // Every enter-animation and settled frame reuses; the two anchor-move frames may re-record
    // (the moved wrapper relayouts the panel).
    try testing.expect(s.reused >= s.frames - 2);
}

test "r12 Popover: .dirty_marking positioning hook reuses the promoted surface with verification off (ZENIT_DISABLE_HOOK_VERIFY)" {
    const s = try checked(runPopover, .{ .verify_disabled = true });
    try testing.expectEqual(@as(u64, 0), s.mismatches);
    try testing.expect(s.reused >= s.frames - 2);
}

test "r12 Popover control: the same hook as an undeclared main hook loses the surface with verification off" {
    const off = try checked(runPopover, .{ .verify_disabled = true, .legacy_main = true });
    try testing.expectEqual(@as(u64, 0), off.mismatches);
    try testing.expectEqual(@as(usize, 0), off.reused);
    // With verification on the verified main hook keeps it (today's path before R12).
    const on = try checked(runPopover, .{ .verify_disabled = false, .legacy_main = true });
    try testing.expectEqual(@as(u64, 0), on.mismatches);
    try testing.expect(on.reused >= on.frames - 3);
    // Declared, verification off records no more than the verified legacy path.
    const declared = try checked(runPopover, .{ .verify_disabled = true });
    try testing.expect(declared.rebuilds <= on.rebuilds);
    try testing.expect(declared.rebuilds < off.rebuilds);
}

// ----------------------------------------------------------------------------------- Select

const select_opts = [_]select_mod.SelectOption{
    .{ .value = "one", .label = "Option 1" },
    .{ .value = "two", .label = "Option 2" },
    .{ .value = "three", .label = "Option 3" },
};

/// Opens a Select (its panel is a Popover with the `.dropdown` slide), plays the enter
/// animation, moves the trigger once and keeps the panel open.
fn runSelect(mode: Mode) !Stats {
    begin(mode);
    defer end();
    var ctx = try Cx.init(testing.allocator, testing.io);
    defer ctx.deinit();
    ctx.setViewport(600, 400);
    const root = try ui.box(ctx, .{ .width = .{ .px = 600 }, .height = .{ .px = 400 }, .direction = .column }, .{});
    ctx.root = root;
    const spacer = try ui.box(ctx, .{ .width = .{ .px = 10 }, .height = .{ .px = 20 } }, .{});
    try root.appendChild(testing.allocator, spacer);
    const scope = try Scope.init(testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const result = try select_mod.Select(.{ .options = &select_opts }).mount(scope, ctx);
    try root.appendChild(testing.allocator, result.wrapper);
    try expectDeclared(result.panel, popover_mod.popoverBeforeRender);
    if (mode.legacy_main) toLegacyMain(result.panel, popover_mod.popoverBeforeRender);

    ctx.layout();
    _ = ctx.render();
    result.open.?.set(true);
    try settle(ctx, result.panel);

    var stats = Stats{};
    for (0..20) |f| {
        if (f == 14) spacer.setStyleInline(testing.allocator, .{ .height = .{ .px = 44 } });
        frame(ctx, result.panel, &stats);
    }
    return stats;
}

test "r12 Select: panel reuses its promoted surface with verification on and off, matches the full path" {
    for ([_]bool{ false, true }) |disabled| {
        const s = try checked(runSelect, .{ .verify_disabled = disabled });
        try testing.expectEqual(@as(u64, 0), s.mismatches);
        try testing.expect(s.reused >= s.frames - 2);
    }
}

test "r12 Select control: an undeclared main positioning hook loses the panel surface with verification off" {
    const s = try checked(runSelect, .{ .verify_disabled = true, .legacy_main = true });
    try testing.expectEqual(@as(u64, 0), s.mismatches);
    try testing.expectEqual(@as(usize, 0), s.reused);
    const declared = try checked(runSelect, .{ .verify_disabled = true });
    try testing.expect(declared.rebuilds < s.rebuilds);
}

// ----------------------------------------------------------------------------- Notification

/// Shows a sticky notification and runs its entry animation (~700 ms) and settled frames.
fn runNotification(mode: Mode) !Stats {
    begin(mode);
    defer end();
    var ctx = try Cx.init(testing.allocator, testing.io);
    defer ctx.deinit();
    ctx.setViewport(1200, 800);
    const root = try ui.box(ctx, .{ .width = .{ .px = 1200 }, .height = .{ .px = 800 } }, .{});
    ctx.root = root;
    const scope = try Scope.init(testing.allocator, null, ctx.owner);
    defer scope.dispose();
    ctx.frame_time_ms = -16;
    const n = try notification_mod.Notifier.init(scope, ctx, .{ .position = .bottom_center });
    if (!n.portaled) try root.appendChild(testing.allocator, n.container);
    try expectDeclared(n.container, notification_mod.Notifier.frameHookForTest());
    if (mode.legacy_main) toLegacyMain(n.container, notification_mod.Notifier.frameHookForTest());

    _ = try n.show(.{ .tone = .success, .title = "Saved to iCloud", .body = "3 files synced", .sticky = true });
    var stats = Stats{};
    for (0..80) |_| frame(ctx, n.container, &stats);
    return stats;
}

test "r12 Notification: .dirty_marking frame hook keeps the viewport's caches with verification on and off, matches the full path" {
    // Before R12 (undeclared main hook) the viewport's subtree was hook-owned: re-recorded
    // every frame even when verified (the viewport is not itself promoted while static).
    const legacy = try checked(runNotification, .{ .verify_disabled = false, .legacy_main = true });
    try testing.expectEqual(@as(u64, 0), legacy.mismatches);
    for ([_]bool{ false, true }) |disabled| {
        const s = try checked(runNotification, .{ .verify_disabled = disabled });
        try testing.expectEqual(@as(u64, 0), s.mismatches);
        try testing.expect(s.reused >= s.frames / 2);
        try testing.expect(s.rebuilds * 2 < legacy.rebuilds);
    }
}

// ------------------------------------------------------------------- write-marking contract
//
// The paint pass reads translate / opacity from this frame's property tree, so a missing mark
// on those often heals in the display list; what goes stale is whatever a cache baked in. The
// checks above therefore cannot prove the contract on their own. `Marked` wraps a declared hook
// and checks the contract directly: every node of the hook's subtree whose paint / layout input
// the hook changed must carry a mark afterwards (content or composite version bumped, layout
// dirty, or for a translate-only change the translate dirty bit).

const Style = @TypeOf(@as(Node, undefined).style);
const StyleExt = std.meta.Child(std.meta.Child(@TypeOf(@as(Style, undefined).ext)));

const NodeSnap = struct {
    node: *Node,
    style: Style,
    ext: StyleExt,
    opacity: f32,
    background: ui.Color,
    text_hash: u64,
    content_version: u32,
    composite_version: u32,
};

fn textHash(node: *const Node) u64 {
    const t = node.getText() orelse return 0;
    var h = std.hash.Wyhash.init(1);
    h.update(t.content);
    h.update(std.mem.asBytes(&t.color));
    return h.final();
}

fn snapOf(node: *Node) NodeSnap {
    var style = node.style;
    style.ext = null;
    return .{
        .node = node,
        .style = style,
        .ext = if (node.style.ext) |e| e.* else .{},
        .opacity = node.getOpacity(),
        .background = node.getBackground(),
        .text_hash = textHash(node),
        .content_version = @intCast(node.meta.per_frame.caches.versions.content),
        .composite_version = @intCast(node.meta.per_frame.caches.versions.composite),
    };
}

const Marked = struct {
    var hook: ?*const fn (*Node) void = null;
    var buf: [512]NodeSnap = undefined;
    var unmarked: usize = 0;
    var runs: usize = 0;

    fn collect(node: *Node, n: *usize) void {
        if (n.* < buf.len) {
            buf[n.*] = snapOf(node);
            n.* += 1;
        }
        for (node.children.items) |c| collect(c, n);
    }

    fn run(node: *Node) void {
        var n: usize = 0;
        collect(node, &n);
        hook.?(node);
        runs += 1;
        for (buf[0..n]) |before| check(before);
    }

    fn check(before: NodeSnap) void {
        const node = before.node;
        if (node.freeing or node.pending_free_cx != null) return;
        const now = snapOf(node);
        var style_only_translate = before.style;
        style_only_translate.translate_x = now.style.translate_x;
        style_only_translate.translate_y = now.style.translate_y;
        const translate_changed = before.style.translate_x != now.style.translate_x or before.style.translate_y != now.style.translate_y;
        const other_changed = !std.meta.eql(style_only_translate, now.style) or !std.meta.eql(before.ext, now.ext) or
            before.opacity != now.opacity or !ui.Color.eql(before.background, now.background) or before.text_hash != now.text_hash;
        if (!translate_changed and !other_changed) return;
        const d = node.frame_state.state_bits.dirty;
        const versioned = now.content_version != before.content_version or now.composite_version != before.composite_version or d.core.layout;
        if (versioned) return;
        if (!other_changed and d.pipeline.transform) return;
        unmarked += 1;
        std.debug.print("[r12 marked] unmarked hook write on node {d} ({s}): translate={} other={}\n", .{ node.id, node.meta.ownership.meta.component_name orelse "-", translate_changed, other_changed });
    }

    /// Replaces the node's declared `real` hook with the checking wrapper (still `.dirty_marking`).
    fn install(node: *Node, real: *const fn (*Node) void) void {
        hook = real;
        unmarked = 0;
        runs = 0;
        node.removeBeforeRender(real);
        node.addBeforeRenderScoped(run, .dirty_marking);
    }
};

/// Ends a contract scenario: the wrapped hook ran and made no unmarked write.
fn expectAllMarked() !void {
    try testing.expect(Marked.runs > 0);
    try testing.expectEqual(@as(usize, 0), Marked.unmarked);
}

const Virtual = struct {
    var rect: popover_mod.AnchorRect = .{ .x = 100, .y = 100, .w = 40, .h = 20 };
    var dummy: u8 = 0;
    fn getRect(_: *anyopaque) popover_mod.AnchorRect {
        return rect;
    }
};

test "r12 contract: a virtual-anchor Popover follows its anchor with marked translates" {
    for ([_]bool{ false, true }) |disabled| {
        begin(.{ .verify_disabled = disabled });
        defer end();
        var ctx = try Cx.init(testing.allocator, testing.io);
        defer ctx.deinit();
        ctx.setViewport(640, 480);
        const root = try ui.box(ctx, .{ .width = .{ .px = 640 }, .height = .{ .px = 480 } }, .{});
        ctx.root = root;
        const scope = try Scope.init(testing.allocator, null, ctx.owner);
        defer scope.dispose();
        Virtual.rect = .{ .x = 100, .y = 100, .w = 40, .h = 20 };
        const result = try popover_mod.Popover(.{ .position = .bottom_start, .trigger = .click, .anchor = .{ .virtual = .{ .ctx = @as(*anyopaque, @ptrCast(&Virtual.dummy)), .getRect = Virtual.getRect } } }).mount(scope, ctx);
        try root.appendChild(testing.allocator, result.wrapper);
        try result.trigger.appendChild(testing.allocator, try ui.box(ctx, .{ .width = .{ .px = 120 }, .height = .{ .px = 32 } }, .{}));
        try result.content.appendChild(testing.allocator, try ui.text(ctx, "Follows the cursor", .{}));
        Marked.install(result.content, popover_mod.popoverBeforeRender);
        var stats = Stats{};
        frame(ctx, result.content, &stats);
        result.open.?.set(true);
        for (0..40) |f| {
            // The anchor moves sideways relative to the wrapper: only the translate changes (no
            // autosize / sizing write in the same hook run to carry a mark for it).
            if (f >= 20 and f % 3 == 0) Virtual.rect = .{ .x = 100 + @as(f32, @floatFromInt(f)) * 7, .y = 100, .w = 40, .h = 20 };
            frame(ctx, result.content, &stats);
        }
        try testing.expectEqual(@as(u64, 0), stats.mismatches);
        try expectAllMarked();
        try testing.expect(result.content.style.translate_x > 100 + 7 * 30);
    }
}

/// Grows the panel from inside the frame (a hook ahead of the positioning hook on the same node,
/// like content populated by an earlier hook): the positioning hook then meets a layout-dirty,
/// never positioned panel and pauses the enter at hidden opacity (0 -> HIDDEN_OPACITY).
const Grow = struct {
    var left: usize = 0;
    var cx: ?*Cx = null;
    fn hook(node: *Node) void {
        if (left == 0) return;
        left -= 1;
        const row = ui.text(cx.?, "late row", .{}) catch return;
        node.appendChild(testing.allocator, row) catch return;
        node.markSizingDirty();
    }
};

test "r12 contract: opening while the content relayouts pauses with a marked opacity" {
    for ([_]bool{ false, true }) |disabled| {
        begin(.{ .verify_disabled = disabled });
        defer end();
        var ctx = try Cx.init(testing.allocator, testing.io);
        defer ctx.deinit();
        ctx.setViewport(640, 480);
        const root = try ui.box(ctx, .{ .width = .{ .px = 640 }, .height = .{ .px = 480 } }, .{});
        ctx.root = root;
        const scope = try Scope.init(testing.allocator, null, ctx.owner);
        defer scope.dispose();
        const result = try popover_mod.Popover(.{ .position = .bottom_start, .trigger = .click }).mount(scope, ctx);
        try root.appendChild(testing.allocator, result.wrapper);
        try result.trigger.appendChild(testing.allocator, try ui.box(ctx, .{ .width = .{ .px = 120 }, .height = .{ .px = 32 } }, .{}));
        try result.content.appendChild(testing.allocator, try ui.text(ctx, "Grows while opening", .{}));
        Grow.cx = ctx;
        Grow.left = 0;
        result.content.addBeforeRenderScoped(Grow.hook, .dirty_marking);
        Marked.install(result.content, popover_mod.popoverBeforeRender);
        var stats = Stats{};
        frame(ctx, result.content, &stats);
        Grow.left = 3;
        result.open.?.set(true);
        for (0..30) |_| frame(ctx, result.content, &stats);
        try testing.expectEqual(@as(usize, 0), Grow.left);
        try testing.expectEqual(@as(u64, 0), stats.mismatches);
        try expectAllMarked();
        try testing.expect(result.content.getOpacity() > 0.99);
    }
}

test "r12 contract: a dropdown slide offset change without a translate change is marked" {
    begin(.{ .verify_disabled = true });
    defer end();
    var ctx = try Cx.init(testing.allocator, testing.io);
    defer ctx.deinit();
    ctx.setViewport(640, 480);
    const root = try ui.box(ctx, .{ .width = .{ .px = 640 }, .height = .{ .px = 480 } }, .{});
    ctx.root = root;
    const scope = try Scope.init(testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const result = try popover_mod.Popover(.{ .position = .bottom_start, .trigger = .click, .enter_transition = .dropdown, .exit_transition = .dropdown }).mount(scope, ctx);
    try root.appendChild(testing.allocator, result.wrapper);
    try result.trigger.appendChild(testing.allocator, try ui.box(ctx, .{ .width = .{ .px = 120 }, .height = .{ .px = 32 } }, .{}));
    try result.content.appendChild(testing.allocator, try ui.text(ctx, "Dropdown", .{}));
    var stats = Stats{};
    frame(ctx, result.content, &stats);
    result.open.?.set(true);
    for (0..30) |_| frame(ctx, result.content, &stats);
    try testing.expect(result.content.getOpacity() > 0.999);
    Marked.install(result.content, popover_mod.popoverBeforeRender);
    // A slide offset left 0.004 px off rest (inside setPopoverTranslate's 0.01 px tolerance): the
    // hook resets the offset to 0 while the translate stays put.
    const ext = result.content.style.ensureExtPanic(ctx.allocator);
    ext.motion_offset = .{ 0, 0.004 };
    result.content.style.translate_y += 0.004;
    result.content.markCompositePropDirty();
    for (0..3) |_| frame(ctx, result.content, &stats);
    try testing.expectEqual(@as(f32, 0), result.content.style.ext.?.motion_offset[1]);
    try testing.expectEqual(@as(u64, 0), stats.mismatches);
    try expectAllMarked();
}

/// A panel clamped by the viewport cap (constrain_width_to_viewport) widens once the viewport
/// grows: the new cap is a layout input, and the current (clamped) width already fits it.
fn runCapGrow(disabled: bool) !f32 {
    begin(.{ .verify_disabled = disabled });
    defer end();
    var ctx = try Cx.init(testing.allocator, testing.io);
    defer ctx.deinit();
    ctx.setViewport(260, 480);
    const root = try ui.box(ctx, .{ .width = .{ .grow = .{} }, .height = .{ .grow = .{} } }, .{});
    ctx.root = root;
    const scope = try Scope.init(testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const result = try popover_mod.Popover(.{ .position = .bottom_start, .trigger = .click, .constrain_width_to_viewport = true, .enter_transition = .none, .exit_transition = .none }).mount(scope, ctx);
    try root.appendChild(testing.allocator, result.wrapper);
    try result.trigger.appendChild(testing.allocator, try ui.box(ctx, .{ .width = .{ .px = 60 }, .height = .{ .px = 32 } }, .{}));
    try result.content.appendChild(testing.allocator, try ui.box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 30 }, .flex_shrink = 1 }, .{}));
    Marked.install(result.content, popover_mod.popoverBeforeRender);
    var stats = Stats{};
    frame(ctx, result.content, &stats);
    result.open.?.set(true);
    for (0..20) |_| frame(ctx, result.content, &stats);
    const narrow = result.content.rectFromWorldOrFallback().w;
    try testing.expect(narrow < 260);
    ctx.setViewport(640, 480);
    for (0..20) |_| frame(ctx, result.content, &stats);
    try testing.expectEqual(@as(u64, 0), stats.mismatches);
    try expectAllMarked();
    return result.content.rectFromWorldOrFallback().w;
}

test "r12 contract: a panel held by the old viewport cap widens when the cap grows" {
    for ([_]bool{ false, true }) |disabled| {
        const w = try runCapGrow(disabled);
        try testing.expect(w >= 399);
    }
}

/// Three cards, the pointer hovers the stack (it expands: every card moves), leaves, one card
/// expires and exits, one is transformed in place, one is dismissed.
fn runNotificationContract(disabled: bool) !Stats {
    begin(.{ .verify_disabled = disabled });
    defer end();
    var ctx = try Cx.init(testing.allocator, testing.io);
    defer ctx.deinit();
    ctx.setViewport(1200, 800);
    const root = try ui.box(ctx, .{ .width = .{ .px = 1200 }, .height = .{ .px = 800 } }, .{});
    ctx.root = root;
    const scope = try Scope.init(testing.allocator, null, ctx.owner);
    defer scope.dispose();
    ctx.frame_time_ms = -16;
    ctx.cursor_state.pointer_valid = true;
    ctx.hover_sync.pointer_over_content = true;
    ctx.mouse_x = 5;
    ctx.mouse_y = 5;
    const n = try notification_mod.Notifier.init(scope, ctx, .{ .position = .bottom_center });
    if (!n.portaled) try root.appendChild(testing.allocator, n.container);
    Marked.install(n.container, notification_mod.Notifier.frameHookForTest());
    const a = try n.show(.{ .tone = .success, .title = "Saved to iCloud", .body = "3 files synced", .sticky = true });
    _ = try n.show(.{ .tone = .info, .title = "Second", .body = "expires", .duration_ms = 1500 });
    _ = try n.show(.{ .tone = .warning, .title = "Third", .body = "sticky", .sticky = true });
    var stats = Stats{};
    for (0..60) |_| frame(ctx, n.container, &stats);
    ctx.mouse_x = 600;
    ctx.mouse_y = 760;
    for (0..60) |_| frame(ctx, n.container, &stats);
    try testing.expect(n.isExpanded());
    ctx.mouse_x = 5;
    ctx.mouse_y = 5;
    for (0..60) |_| frame(ctx, n.container, &stats);
    try n.update(a, .{ .tone = .@"error", .title = "Changed", .body = "in place" });
    for (0..160) |_| frame(ctx, n.container, &stats);
    n.dismiss(a);
    for (0..60) |_| frame(ctx, n.container, &stats);
    try expectAllMarked();
    return stats;
}

test "r12 contract: Notification hover expand / expire / transform / dismiss make only marked writes" {
    for ([_]bool{ false, true }) |disabled| {
        const s = try runNotificationContract(disabled);
        try testing.expectEqual(@as(u64, 0), s.mismatches);
    }
}

test "r12 contract: a trigger-width panel follows a trigger resize that also moves the viewport cap" {
    begin(.{ .verify_disabled = false });
    defer end();
    var ctx = try Cx.init(testing.allocator, testing.io);
    defer ctx.deinit();
    ctx.setViewport(640, 480);
    const root = try ui.box(ctx, .{ .width = .{ .grow = .{} }, .height = .{ .grow = .{} } }, .{});
    ctx.root = root;
    const scope = try Scope.init(testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const result = try popover_mod.Popover(.{ .position = .bottom_start, .trigger = .click, .match_trigger_width = true, .constrain_width_to_viewport = true, .enter_transition = .none, .exit_transition = .none }).mount(scope, ctx);
    try root.appendChild(testing.allocator, result.wrapper);
    const tbox = try ui.box(ctx, .{ .width = .{ .px = 120 }, .height = .{ .px = 32 } }, .{});
    try result.trigger.appendChild(testing.allocator, tbox);
    try result.content.appendChild(testing.allocator, try ui.text(ctx, "Option", .{}));
    Marked.install(result.content, popover_mod.popoverBeforeRender);
    var stats = Stats{};
    frame(ctx, result.content, &stats);
    result.open.?.set(true);
    for (0..20) |_| frame(ctx, result.content, &stats);
    try testing.expectApproxEqAbs(@as(f32, 120), result.content.rectFromWorldOrFallback().w, 0.5);
    // Same frame: the trigger widens and the viewport (the width cap) shrinks, still above both.
    tbox.setStyleInline(testing.allocator, .{ .width = .{ .px = 180 } });
    ctx.setViewport(600, 480);
    for (0..20) |_| frame(ctx, result.content, &stats);
    try testing.expectApproxEqAbs(@as(f32, 180), result.content.rectFromWorldOrFallback().w, 0.5);
    try testing.expect(result.content.getOpacity() > 0.99);
    try testing.expectEqual(@as(u64, 0), stats.mismatches);
    try expectAllMarked();
}

// ------------------------------------------------------------------ hover popover contract
//
// A hover Popover with the pointer-grace corridor (safe_triangle, the default). Hover enter /
// leave on the trigger and the panel run as event handlers between frames; the positioning hook
// itself re-checks the pointer every frame (updateHover) and can close the panel from inside the
// hook, as can the anchor-scroll check. Each scenario drives the real pointer path
// (handleMouseMove -> hit test -> on_hover / on_leave) and checks that every hook write is
// marked and every frame matches the full path.

const HoverRig = struct {
    ctx: *Cx,
    scope: *Scope,
    result: popover_mod.PopoverResult,
    stats: Stats = .{},

    /// Trigger 120x32 at (0, 100); the panel opens below it (bottom_start, 4 px offset).
    fn init(rig: *HoverRig, disabled: bool) !void {
        begin(.{ .verify_disabled = disabled });
        const ctx = try Cx.init(testing.allocator, testing.io);
        errdefer ctx.deinit();
        ctx.setViewport(640, 480);
        const root = try ui.box(ctx, .{ .width = .{ .px = 640 }, .height = .{ .px = 480 }, .direction = .column }, .{});
        ctx.root = root;
        try root.appendChild(testing.allocator, try ui.box(ctx, .{ .width = .{ .px = 10 }, .height = .{ .px = 100 } }, .{}));
        const scope = try Scope.init(testing.allocator, null, ctx.owner);
        const result = try popover_mod.Popover(.{ .position = .bottom_start, .trigger = .hover }).mount(scope, ctx);
        try root.appendChild(testing.allocator, result.wrapper);
        try result.trigger.appendChild(testing.allocator, try ui.box(ctx, .{ .width = .{ .px = 120 }, .height = .{ .px = 32 } }, .{}));
        try result.content.appendChild(testing.allocator, try ui.text(ctx, "Hover panel", .{}));
        try result.content.appendChild(testing.allocator, try ui.box(ctx, .{ .width = .{ .px = 160 }, .height = .{ .px = 60 }, .background = ui.Color.hex(0x2244aa) }, .{}));
        Marked.install(result.content, popover_mod.popoverBeforeRender);
        rig.* = .{ .ctx = ctx, .scope = scope, .result = result };
        rig.frames(2);
    }

    fn deinit(rig: *HoverRig) void {
        rig.scope.dispose();
        rig.ctx.deinit();
        end();
    }

    fn frames(rig: *HoverRig, n: usize) void {
        for (0..n) |_| frame(rig.ctx, rig.result.content, &rig.stats);
    }

    fn move(rig: *HoverRig, x: f32, y: f32) void {
        rig.ctx.handleMouseMove(x, y);
    }

    fn isOpen(rig: *HoverRig) bool {
        return rig.result.open.?.peek();
    }

    /// Hover the trigger and play the enter to rest.
    fn open(rig: *HoverRig) !void {
        rig.move(10, 110);
        try testing.expect(rig.isOpen());
        rig.frames(30);
        try testing.expect(rig.result.content.getOpacity() > 0.999);
    }

    fn panelTop(rig: *HoverRig) f32 {
        return rig.result.content.globalRect().y;
    }

    fn pendingTimers(rig: *HoverRig) usize {
        return rig.ctx.timers.items.len;
    }

    /// Fire the pending grace timer now (timers run on the wall clock).
    fn expireTimers(rig: *HoverRig) void {
        for (rig.ctx.timers.items) |*t| t.due_ns = 0;
        rig.ctx.fireDueTimers();
    }

    fn finish(rig: *HoverRig) !void {
        try testing.expectEqual(@as(u64, 0), rig.stats.mismatches);
        try expectAllMarked();
    }
};

test "r12 contract hover: hover open, grace corridor, panel enter and leave make only marked writes" {
    for ([_]bool{ false, true }) |disabled| {
        var rig: HoverRig = undefined;
        try rig.init(disabled);
        defer rig.deinit();
        try rig.open();
        const top = rig.panelTop();
        try testing.expect(top > 132 and top < 140);
        // Leave the trigger into the gap toward the panel: the grace timer holds it open while
        // the hook re-checks the corridor every frame.
        rig.move(10, top - 1);
        try testing.expectEqual(@as(usize, 1), rig.pendingTimers());
        rig.frames(4);
        try testing.expect(rig.isOpen());
        // Reach the panel: the timer is cleared and the panel keeps itself open.
        rig.move(20, top + 20);
        rig.frames(4);
        try testing.expect(rig.isOpen());
        try testing.expectEqual(@as(usize, 0), rig.pendingTimers());
        // Leave the panel away from the trigger: it closes and plays the exit.
        rig.move(500, 400);
        try testing.expect(!rig.isOpen());
        rig.frames(30);
        try testing.expect(rig.result.content.getOpacity() < 0.01);
        // Re-hover reopens it.
        try rig.open();
        try rig.finish();
    }
}

test "r12 contract hover: leaving the grace corridor closes from inside the positioning hook" {
    for ([_]bool{ false, true }) |disabled| {
        var rig: HoverRig = undefined;
        try rig.init(disabled);
        defer rig.deinit();
        try rig.open();
        const top = rig.panelTop();
        rig.move(10, top - 1);
        rig.frames(2);
        try testing.expect(rig.isOpen());
        // Sideways out of the corridor: no further leave event, the hook's updateHover closes.
        rig.move(400, top - 1);
        try testing.expect(rig.isOpen());
        rig.frames(1);
        try testing.expect(!rig.isOpen());
        try testing.expectEqual(@as(usize, 0), rig.pendingTimers());
        rig.frames(30);
        try testing.expect(rig.result.content.getOpacity() < 0.01);
        try rig.open();
        try rig.finish();
    }
}

test "r12 contract hover: the grace timer expiring closes the panel" {
    for ([_]bool{ false, true }) |disabled| {
        var rig: HoverRig = undefined;
        try rig.init(disabled);
        defer rig.deinit();
        try rig.open();
        const top = rig.panelTop();
        rig.move(10, top - 1);
        rig.frames(3);
        try testing.expect(rig.isOpen());
        // The pointer rests in the corridor until the grace period runs out.
        rig.expireTimers();
        try testing.expect(!rig.isOpen());
        rig.frames(30);
        try testing.expect(rig.result.content.getOpacity() < 0.01);
        try rig.finish();
    }
}

test "r12 contract: a click Popover whose anchor scrolls closes from inside the positioning hook" {
    const scroll_area_mod = @import("../components/scroll_area/mod.zig");
    for ([_]bool{ false, true }) |disabled| {
        begin(.{ .verify_disabled = disabled });
        defer end();
        var ctx = try Cx.init(testing.allocator, testing.io);
        defer ctx.deinit();
        ctx.setViewport(640, 480);
        const root = try ui.box(ctx, .{ .width = .{ .px = 640 }, .height = .{ .px = 480 } }, .{});
        ctx.root = root;
        const scope = try Scope.init(testing.allocator, null, ctx.owner);
        defer scope.dispose();
        const sa = try scroll_area_mod.ScrollArea(.{ .width = 300, .height = 200 }).mount(scope, ctx);
        try root.appendChild(testing.allocator, sa.container);
        const column = try ui.box(ctx, .{ .width = .{ .px = 280 }, .height = .{ .px = 800 }, .direction = .column }, .{});
        try sa.content.appendChild(testing.allocator, column);
        try column.appendChild(testing.allocator, try ui.box(ctx, .{ .width = .{ .px = 10 }, .height = .{ .px = 40 } }, .{}));
        const result = try popover_mod.Popover(.{ .position = .bottom_start, .trigger = .click }).mount(scope, ctx);
        try column.appendChild(testing.allocator, result.wrapper);
        const button = try ui.box(ctx, .{ .width = .{ .px = 120 }, .height = .{ .px = 32 } }, .{});
        button.setFocusable(true);
        try result.trigger.appendChild(testing.allocator, button);
        const item = try ui.box(ctx, .{ .width = .{ .px = 100 }, .height = .{ .px = 24 } }, .{});
        item.setFocusable(true);
        try result.content.appendChild(testing.allocator, item);
        Marked.install(result.content, popover_mod.popoverBeforeRender);
        var stats = Stats{};
        frame(ctx, result.content, &stats);
        result.open.?.set(true);
        for (0..30) |_| frame(ctx, result.content, &stats);
        try testing.expect(result.content.getOpacity() > 0.999);
        // The open moved focus into the panel from the hook (trap_focus).
        try testing.expect(ctx.focus_manager.getFocused() == item);
        scroll_area_mod.setScrollY(sa.state, sa.content, 30);
        frame(ctx, result.content, &stats);
        try testing.expect(!result.open.?.peek());
        for (0..30) |_| frame(ctx, result.content, &stats);
        try testing.expect(result.content.getOpacity() < 0.01);
        try testing.expectEqual(@as(u64, 0), stats.mismatches);
        try expectAllMarked();
    }
}
