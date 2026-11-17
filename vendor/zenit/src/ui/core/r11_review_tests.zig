//! r11 review repros (raw_shadow / translate fast path). Copied into src/ui/core/ of a scratch
//! worktree and imported from tests.zig. Each test runs "hookverify+check" and
//! "disabled+check" in lockstep and reports incremental-vs-full mismatches per config instead of
//! failing on the first one, so the output shows which configuration goes stale.
const std = @import("std");
const ui = @import("../core.zig");
const raw_shadow = @import("render_engine/raw_shadow.zig");
const view = @import("../view.zig");
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

/// Runs each configuration on its own (one world per call), so a mismatch in one does not stop
/// the other. Returns mismatches per configuration.
fn runEach(build: h.BuildFn, move: h.MoveFn, frames: usize) ![2]u64 {
    const cfgs = [_]Config{
        .{ .name = "hookverify+check", .verify = true, .extra = true },
        .{ .name = "disabled+check", .verify = true, .extra = false },
    };
    var out: [2]u64 = .{ 0, 0 };
    for (cfgs, 0..) |cfg, i| {
        const one = [_]Config{cfg};
        const t = h.runLockstep(&one, build, move, .{ .frames = frames, .hook_scope = .subtree, .apply = applyVerify }) catch |e| {
            std.debug.print("[r11] {s}: {s}\n", .{ cfg.name, @errorName(e) });
            out[i] = 1;
            continue;
        };
        defer testing.allocator.free(t);
        out[i] = t[0].mismatches;
    }
    raw_shadow.disabled_override = null;
    std.debug.print("[r11] mismatches: hookverify={d} disabled={d}\n", .{ out[0], out[1] });
    return out;
}

// ------------------------------------------------------------------------------------------
// R1: LayoutArtifacts.text_layout is compared by identity, but storeTextLayout overwrites the
// slot's TextLayout in place (same pointer). A raw in-place text edit (seen, marked render, but
// no layout) followed later by any layout pass that re-wraps the text (here a marked layout
// write on its parent) changes the line breaks without changing anything the shadow compares.

const R1 = struct {
    var buf: [23]u8 = undefined;
    var text_node: ?*Node = null;
    var holder: ?*Node = null;
};

fn buildR1(w: *World) !void {
    try h.makeRoot(w);
    const cx = w.cx;
    const holder = try ui.box(cx, .{ .position = .absolute, .inset = .{ .left = .{ .px = 40 }, .top = .{ .px = 40 } }, .width = .{ .px = 140 }, .height = .{ .px = 120 }, .background = Color.hex(0xeeeeee), .direction = .column }, .{});
    const t = try ui.box(cx, .{ .width = .{ .px = 90 }, .height = .{ .px = 90 } }, .{});
    @memcpy(R1.buf[0..], "aa bb cc dd ee ff gg hh");
    // Borrowed buffer (owned = false), edited in place like the fuzz's borrowed text.
    t.setText(.{ .content = R1.buf[0..], .font_size = 14, .line_height = 1.4, .wrap = .word, .color = Color.hex(0x111111) });
    try holder.appendChild(cx.allocator, t);
    try w.root.appendChild(cx.allocator, holder);
    for (0..4) |i| _ = try h.makeHostedCard(w.scope, cx, w.root, @floatFromInt(300 + i * 110), 40, "beside");
    R1.text_node = t;
    R1.holder = holder;
}

fn moveR1(w: *World, frame: usize) void {
    _ = w;
    const t = R1.text_node.?;
    if (frame == 4) {
        // In place, same length: different break positions.
        const tp = t.getTextRaw().?;
        const bytes: []u8 = @constCast(tp.content);
        const repl = "aaaaaaaaaaaaa bbbbbbbbb";
        std.debug.print("[r11 R1] content len={d} owned={} '{s}'\n", .{ bytes.len, tp.owned, bytes });
        if (bytes.len != repl.len) return;
        @memcpy(bytes, repl);
    }
    if (frame == 8) {
        // Any marked layout write that re-runs the parent's child layout.
        R1.holder.?.markLayoutDirty();
    }
}

test "r11 R1: in-place TextLayout overwrite after a raw text edit is invisible to the shadow" {
    const m = try runEach(buildR1, moveR1, 14);
    std.debug.print("[r11 R1] hookverify mismatches={d} (disabled={d})\n", .{ m[0], m[1] });
    try testing.expectEqual(@as(u64, 0), m[1]); // today's path is right
    try testing.expectEqual(@as(u64, 0), m[0]); // fails on e06e0760: verified path goes stale
}

// ------------------------------------------------------------------------------------------
// R2: retained memo replay (buildRetainedSubtree -> tryReplay) runs before any hook-trust /
// nodeVolatile check. Inside a verified `.subtree` hook subtree memos now exist; a `main` hook
// installed on a clean node inside it (component pattern: `before_render.main = f`) is excluded
// from verification, so its raw writes (here a child's translate) are never marked, and the
// ancestor's memo replays the old transforms.

const R2 = struct {
    var m: ?*Node = null;
    var k: ?*Node = null;
    var sibling: ?*Node = null;
    var invalidate_quiet = false;
    var pre_hook = false;
};

fn noopHookR2(_: *Node) void {}

fn mainHookR2(node: *Node) void {
    _ = node;
    const f: u32 = @intFromFloat(@import("render_engine/mod.zig").current_frame_time_ms / 8.0);
    R2.k.?.style.translate_x = @floatFromInt((f * 7) % 50);
}

fn buildR2(w: *World) !void {
    try h.makeRoot(w);
    const cx = w.cx;
    const p = try ui.box(cx, .{ .position = .absolute, .inset = .{ .left = .{ .px = 40 }, .top = .{ .px = 40 } }, .width = .{ .px = 220 }, .height = .{ .px = 120 }, .background = Color.hex(0xeeeeee) }, .{});
    const m = try ui.box(cx, .{ .width = .{ .px = 200 }, .height = .{ .px = 100 }, .background = Color.hex(0xdddddd) }, .{});
    const k = try ui.box(cx, .{ .width = .{ .px = 30 }, .height = .{ .px = 20 }, .background = Color.hex(0x2244aa) }, .{});
    try m.appendChild(cx.allocator, k);
    try p.appendChild(cx.allocator, m);
    try w.root.appendChild(cx.allocator, p);
    R2.sibling = try h.makeHostedCard(w.scope, cx, w.root, 400, 40, "dirty sibling");
    R2.m = m;
    R2.k = k;
    // Variant R2b: M already carries an undeclared `.subtree` hook (flags already set), so the
    // later `main` install changes no flag the shadow could see.
    if (R2.pre_hook) m.addBeforeRenderScoped(noopHookR2, .subtree);
}

fn moveR2(w: *World, frame: usize) void {
    _ = w;
    std.debug.print("[r11 R2] frame {d}: prev memo_replays={d} self={d} hv_nodes={d} k.tx={d}\n", .{ frame, h.last_perf.rn_memo_replays, h.last_perf.rn_memo_self_translation_replays, h.last_perf.hook_verify_nodes, R2.k.?.style.translate_x });
    // Keep the root path dirty so P is a clean memo frontier.
    R2.sibling.?.setBackground(Color.rgba(@intCast((frame * 13) % 250), 80, 80, 255));
    if (frame == 6) {
        R2.m.?.meta.per_frame.hooks.before_render.main = mainHookR2;
        if (R2.invalidate_quiet) R2.m.?.invalidateTickQuietChain();
        // What noteRenderCleanedAfterTick does after any marked mutation between the tick's end
        // and the render's clean (after-layout hooks, overlay anchors, ...): every quiet stamp
        // goes, no memo is dropped.
        @import("render_engine/tick.zig").invalidateTickQuietStamps();
    }
}

// Control: passes. The NodeFlags compare catches the new has_*_before_render_subtree bits on the
// ancestors and marks them, which drops the memo (see R2b for the case without flag changes).
test "r11 R2: memo of a verified-subtree ancestor replays over a runtime-installed main hook" {
    const m = try runEach(buildR2, moveR2, 16);
    std.debug.print("[r11 R2] hookverify mismatches={d} (disabled={d})\n", .{ m[0], m[1] });
}

test "r11 R2b: same, M already had a .subtree hook (no flag changes when main is installed)" {
    R2.pre_hook = true;
    defer R2.pre_hook = false;
    const m = try runEach(buildR2, moveR2, 16);
    std.debug.print("[r11 R2b] hookverify mismatches={d} (disabled={d})\n", .{ m[0], m[1] });
    try testing.expectEqual(@as(u64, 0), m[1]); // today's path is right
    try testing.expectEqual(@as(u64, 0), m[0]); // fails on e06e0760: verified path goes stale
}

// ------------------------------------------------------------------------------------------
// R3: the node budget is shared by every hook of the pass. Another hook subtree (B) growing past
// max_nodes_per_pass aborts the pass before A is walked: nothing is trusted for this frame and
// the next 60 (retry_after), A's raw writes are not marked, and a memo recorded at A while it was
// verified replays (tryReplay runs before any trust / volatility check).

const R3 = struct {
    var a: ?*Node = null;
    var k: ?*Node = null;
    var b: ?*Node = null;
    var sibling: ?*Node = null;
    var frame: usize = 0;
};

fn hookA(_: *Node) void {
    if (R3.frame >= 6) R3.k.?.style.translate_x = @floatFromInt((R3.frame * 7) % 50);
}
fn hookB(_: *Node) void {}

fn buildR3(w: *World) !void {
    try h.makeRoot(w);
    const cx = w.cx;
    const b = try ui.box(cx, .{ .position = .absolute, .inset = .{ .left = .{ .px = 400 }, .top = .{ .px = 300 } }, .width = .{ .px = 300 }, .height = .{ .px = 100 }, .direction = .row, .background = Color.hex(0xcccccc) }, .{});
    for (0..2) |_| try b.appendChild(cx.allocator, try ui.box(cx, .{ .width = .{ .px = 10 }, .height = .{ .px = 10 }, .background = Color.hex(0x884422) }, .{}));
    try w.root.appendChild(cx.allocator, b);
    const a = try ui.box(cx, .{ .position = .absolute, .inset = .{ .left = .{ .px = 40 }, .top = .{ .px = 40 } }, .width = .{ .px = 220 }, .height = .{ .px = 120 }, .background = Color.hex(0xeeeeee) }, .{});
    const k = try ui.box(cx, .{ .width = .{ .px = 30 }, .height = .{ .px = 20 }, .background = Color.hex(0x2244aa) }, .{});
    try a.appendChild(cx.allocator, k);
    try w.root.appendChild(cx.allocator, a);
    R3.sibling = try h.makeHostedCard(w.scope, cx, w.root, 400, 40, "dirty sibling");
    b.addBeforeRenderScoped(hookB, .subtree);
    a.addBeforeRenderScoped(hookA, .subtree);
    R3.a = a;
    R3.k = k;
    R3.b = b;
}

fn moveR3(w: *World, frame: usize) void {
    R3.frame = frame;
    R3.sibling.?.setBackground(Color.rgba(@intCast((frame * 13) % 250), 80, 80, 255));
    if (frame == 6) {
        // B grows (marked, legal): the pass now runs out of budget inside B.
        for (0..10) |_| {
            const leaf = ui.box(w.cx, .{ .width = .{ .px = 10 }, .height = .{ .px = 10 }, .background = Color.hex(0x448822) }, .{}) catch return;
            R3.b.?.appendChild(w.cx.allocator, leaf) catch return;
        }
    }
    std.debug.print("[r11 R3] frame {d}: prev memo_replays={d} hv_nodes={d} skipped={d} k.tx={d}\n", .{ frame, h.last_perf.rn_memo_replays, h.last_perf.hook_verify_nodes, h.last_perf.hook_verify_skipped_cap, R3.k.?.style.translate_x });
}

fn runEachScoped(build: h.BuildFn, move: h.MoveFn, frames: usize, scope: ui.BeforeRenderScope) ![2]u64 {
    const cfgs = [_]Config{
        .{ .name = "hookverify+check", .verify = true, .extra = true },
        .{ .name = "disabled+check", .verify = true, .extra = false },
    };
    var out: [2]u64 = .{ 0, 0 };
    for (cfgs, 0..) |cfg, i| {
        const one = [_]Config{cfg};
        const t = h.runLockstep(&one, build, move, .{ .frames = frames, .hook_scope = scope, .apply = applyVerify }) catch |e| {
            std.debug.print("[r11] {s}: {s}\n", .{ cfg.name, @errorName(e) });
            out[i] = 1;
            continue;
        };
        defer testing.allocator.free(t);
        out[i] = t[0].mismatches;
    }
    raw_shadow.disabled_override = null;
    return out;
}

test "r11 R3: another hook subtree past the node cap aborts the pass, a verified sibling hook's memo replays stale" {
    const saved = raw_shadow.max_nodes_per_pass;
    defer raw_shadow.max_nodes_per_pass = saved;
    raw_shadow.max_nodes_per_pass = 8;
    const m = try runEachScoped(buildR3, moveR3, 14, .dirty_marking);
    std.debug.print("[r11 R3] hookverify mismatches={d} (disabled={d})\n", .{ m[0], m[1] });
    try testing.expectEqual(@as(u64, 0), m[1]); // today's path is right
    try testing.expectEqual(@as(u64, 0), m[0]); // fails on e06e0760: verified path goes stale
}
