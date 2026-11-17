//! WP0 (docs/design/streaming-content.md §5.8): every work counter moves at its counting point
//! and by the amount of work done there, and Cx.render closes one frame of them.
const std = @import("std");
const ui = @import("../core.zig");
const work = @import("trace").work_counters;
const text_layout = @import("text_layout.zig");
const markdown = @import("../components/markdown/mod.zig");

const Cx = ui.Cx;

fn delta(before: work.Counts, counter: work.Counter) u64 {
    return work.snapshot().since(before).get(counter);
}

test "work counters: text layout counts computations and bytes, cache hits count nothing" {
    const content = "alpha beta gamma\ndelta";
    const before = work.snapshot();
    var scratch = text_layout.LineScratch.init(std.testing.allocator);
    defer scratch.deinit();
    _ = try text_layout.computeTextLayout(&scratch, content, 200, .word, 0, 12, 1.2, 400, false, false, &.{});
    try std.testing.expectEqual(@as(u64, 1), delta(before, .text_layouts));
    try std.testing.expectEqual(@as(u64, content.len), delta(before, .text_layout_bytes));

    const cx = try Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    cx.setViewport(300, 200);
    const root = try ui.box(cx, .{ .width = .{ .px = 300 }, .direction = .column }, .{});
    cx.root = root;
    const node = try ui.text(cx, content, .{ .wrap = .word, .monospace_char_width = 7 });
    try root.appendChild(cx.allocator, node);
    cx.layout();
    _ = cx.render();
    // Unchanged content and width: the stored layout is reused, nothing is re-broken.
    root.markLayoutDirty();
    const settled = work.snapshot();
    cx.layout();
    try std.testing.expectEqual(@as(u64, 0), delta(settled, .text_layout_bytes));
    try std.testing.expectEqual(@as(u64, 1), delta(settled, .layout_passes));
}

test "work counters: heap node allocation and release, through Cx and standalone" {
    const cx = try Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    const before = work.snapshot();
    const parent = try ui.box(cx, .{}, .{});
    const child = try ui.box(cx, .{}, .{});
    try parent.appendChild(cx.allocator, child);
    try std.testing.expectEqual(@as(u64, 2), delta(before, .nodes_created));
    cx.freeNode(parent);
    try std.testing.expectEqual(@as(u64, 2), delta(before, .nodes_destroyed));

    const standalone = try ui.Node.create(std.testing.allocator, 1, .box, .{});
    try std.testing.expectEqual(@as(u64, 3), delta(before, .nodes_created));
    standalone.destroy(std.testing.allocator);
    try std.testing.expectEqual(@as(u64, 3), delta(before, .nodes_destroyed));
}

test "work counters: layout passes and after-layout rounds" {
    const cx = try Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    cx.setViewport(200, 100);
    const root = try ui.box(cx, .{ .width = .{ .px = 200 }, .height = .{ .px = 100 } }, .{});
    cx.root = root;
    cx.layout();
    _ = cx.render();
    // Nothing dirty: no layout walk.
    var before = work.snapshot();
    cx.layout();
    try std.testing.expectEqual(@as(u64, 0), delta(before, .layout_passes));

    // A hook that changes layout once: round 0 asks for a relayout, round 1 is quiet.
    const Hook = struct {
        node: *ui.Node,
        rounds: u8 = 0,
        fn run(ctx: *anyopaque, round: u8, _: bool) ui.AfterLayoutResult {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            self.rounds += 1;
            if (round == 0) {
                self.node.markLayoutDirty();
                return .needs_layout;
            }
            return .done;
        }
    };
    var hook = Hook{ .node = root };
    try cx.addAfterLayoutHook(&hook, Hook.run);
    defer cx.removeAfterLayoutHook(&hook);
    root.markLayoutDirty();
    cx.advanceFrameClock();
    before = work.snapshot();
    _ = cx.render();
    try std.testing.expectEqual(@as(u64, hook.rounds), delta(before, .after_layout_rounds));
    try std.testing.expectEqual(@as(u64, 2), delta(before, .after_layout_rounds));
    // The before-render layout of the dirty root plus the relayout the hook asked for.
    try std.testing.expectEqual(@as(u64, 2), delta(before, .layout_passes));
}

test "work counters: Markdown counts the bytes its block scanner walks" {
    const cx = try Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    const container = try ui.box(cx, .{}, .{});
    defer cx.freeNode(container);
    const source = "# Title\n\nA paragraph with **bold**.\n\n```\ncode\n```\n- item\n";
    const before = work.snapshot();
    try markdown.renderInto(cx, container, source, .{});
    try std.testing.expectEqual(@as(u64, source.len), delta(before, .md_scanned_bytes));
}

test "work counters: liveness, one real frame moves every counter" {
    // Guards against "0 means fine": each counter's counting point is reached by an ordinary
    // frame. A counter that stays 0 here lost its counting point.
    const a = std.testing.allocator;
    const cx = try Cx.init(a, std.testing.io);
    defer cx.deinit();
    var fonts = try @import("text").FontSystem.init(a, std.testing.io);
    defer fonts.deinit();
    cx.setViewport(320, 240);
    const root = try ui.box(cx, .{ .width = .{ .px = 320 }, .direction = .column }, .{});
    cx.root = root;
    const doomed = try ui.box(cx, .{}, .{});
    try root.appendChild(cx.allocator, doomed);
    const Hook = struct {
        fn run(_: *anyopaque, _: u8, _: bool) ui.AfterLayoutResult {
            return .done;
        }
    };
    var hook_ctx: u8 = 0;
    try cx.addAfterLayoutHook(&hook_ctx, Hook.run);
    defer cx.removeAfterLayoutHook(&hook_ctx);
    cx.work_counters.reset();
    const before = work.snapshot();
    try markdown.renderInto(cx, root, "# Title\n\nSome **text** that wraps across the width of the box.\n", .{});
    root.removeChild(doomed);
    cx.freeNode(doomed);
    // The platform shaper only for this call: layout below keeps the test measurer.
    cx.text.setFontSystem(&fonts);
    _ = try cx.text.shapeText(.{ .text = "liveness", .font_family = "system", .font_size = 13 });
    cx.text.clearFontSystem();
    cx.layout();
    cx.advanceFrameClock();
    _ = cx.render();
    cx.work_counters.commit();
    const frame = cx.work_counters.report().last;
    const process = work.snapshot().since(before);
    for (work.counters) |counter| {
        if (counter == .text_shape_bytes and @import("builtin").os.tag != .macos) continue;
        if (process.get(counter) == 0) {
            std.debug.print("counter {s} did not move\n", .{@tagName(counter)});
            return error.TestCounterDidNotMove;
        }
        try std.testing.expectEqual(process.get(counter), frame.get(counter));
    }
}

test "work counters: a sampler interval holds exactly the work since the previous commit" {
    const cx = try Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    cx.setViewport(200, 100);
    const root = try ui.box(cx, .{ .width = .{ .px = 200 }, .height = .{ .px = 100 } }, .{});
    cx.root = root;
    _ = cx.render();
    cx.work_counters.reset();

    const extra = try ui.box(cx, .{}, .{});
    try root.appendChild(cx.allocator, extra);
    cx.advanceFrameClock();
    _ = cx.render();
    cx.work_counters.commit();
    var r = cx.work_counters.report();
    try std.testing.expectEqual(@as(u64, 1), r.intervals);
    try std.testing.expectEqual(@as(u64, 1), r.last.get(.nodes_created));
    try std.testing.expect(r.last.get(.layout_passes) >= 1);

    // Renders the host does not present (no commit) leave their work to the next interval.
    _ = cx.render();
    const late = try ui.box(cx, .{}, .{});
    try root.appendChild(cx.allocator, late);
    _ = cx.render();
    cx.work_counters.commit();
    r = cx.work_counters.report();
    try std.testing.expectEqual(@as(u64, 2), r.intervals);
    try std.testing.expectEqual(@as(u64, 1), r.last.get(.nodes_created));
    try std.testing.expectEqual(@as(u64, 2), r.totals.get(.nodes_created));
}

test "work counters: shaping counts the bytes shaped on a shaping-cache miss only" {
    // SKIP-REASON: needs the platform shaper (CoreText) behind TextContext.shapeText.
    if (@import("builtin").os.tag != .macos) return error.SkipZigTest;
    const cx = try Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    var fonts = try @import("text").FontSystem.init(std.testing.allocator, std.testing.io);
    defer fonts.deinit();
    cx.text.setFontSystem(&fonts);
    defer cx.text.clearFontSystem();
    const s = "shaped once";
    const before = work.snapshot();
    _ = try cx.text.shapeText(.{ .text = s, .font_family = "system", .font_size = 16 });
    try std.testing.expectEqual(@as(u64, s.len), delta(before, .text_shape_bytes));
    _ = try cx.text.shapeText(.{ .text = s, .font_family = "system", .font_size = 16 });
    try std.testing.expectEqual(@as(u64, s.len), delta(before, .text_shape_bytes));
}
