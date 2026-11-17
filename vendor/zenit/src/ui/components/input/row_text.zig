const std = @import("std");
const core = @import("../../core.zig");

/// VirtualList retains each row after the renderer returns. Neither a shared
/// composition scratch buffer nor a mutable document is a valid text owner.
/// Allocate with the node's Cx allocator so ContentTable can release the copy.
/// Prepare before publishing; a failed copy leaves the previous row intact.
pub fn set(node: *core.Node, cx: *core.Cx, content: []const u8, color: core.Color, font_size: f32) !void {
    // Need to check if node already owns equivalent content (reuse, don't reallocate), read raw
    // value with ownership
    const old = node.getTextRaw();
    const same_content = if (old) |text| text.owned and std.mem.eql(u8, text.content, content) else false;
    if (same_content and core.Color.eql(old.?.color, color) and old.?.font_size == font_size) return;
    const bytes = if (same_content) old.?.content else try cx.allocator.dupe(u8, content);
    // The row's color is its own (placeholder / disabled tones), never the field's text color.
    node.setText(.{ .content = bytes, .owned = true, .color = color, .color_set = true, .font_size = font_size });
    if (!same_content or old.?.font_size != font_size) node.markSizingDirty();
    node.markRenderDirty();
}

/// Editable rows must paint with the metrics their caret, selection and wrapping measure with.
/// The row declares its size and weight (`font_size_set` / `font_weight_set`), so an enclosing
/// text_font_size / text_font_weight cannot override them, and its line box matches the row
/// pitch (`line_height` px).
pub fn setEditable(node: *core.Node, cx: *core.Cx, content: []const u8, color: core.Color, font_size: f32, font_weight: u16, line_height: f32) !void {
    return setEditableFace(node, cx, content, color, font_size, font_weight, line_height, false);
}
/// `setEditable` with the monospace face selectable (Textarea `monospace`).
pub fn setEditableFace(node: *core.Node, cx: *core.Cx, content: []const u8, color: core.Color, font_size: f32, font_weight: u16, line_height: f32, monospace: bool) !void {
    const ratio = if (font_size > 0 and line_height > 0) line_height / font_size else 1.4;
    const old = node.getTextRaw();
    const same_content = if (old) |text| text.owned and std.mem.eql(u8, text.content, content) else false;
    const same_metrics = if (old) |text| text.font_size == font_size and text.font_weight == font_weight and
        text.line_height == ratio and text.font_size_set and text.font_weight_set and text.use_monospace_font == monospace else false;
    if (same_content and same_metrics and core.Color.eql(old.?.color, color)) return;
    const bytes = if (same_content) old.?.content else try cx.allocator.dupe(u8, content);
    node.setText(.{
        .content = bytes,
        .owned = true,
        .color = color,
        .color_set = true,
        .font_size = font_size,
        .font_size_set = true,
        .font_weight = font_weight,
        .font_weight_set = true,
        .line_height = ratio,
        .use_monospace_font = monospace,
    });
    if (!same_content or !same_metrics) node.markSizingDirty();
    node.markRenderDirty();
}

/// A failed row copy must be retried even without a further editing event.
pub fn retry(cx: *core.Cx, node: *core.Node) void {
    node.markLayoutDirty();
    cx.scheduleRedrawAfterNs(16 * std.time.ns_per_ms);
}

test "setEditable pins row metrics against inherited typography" {
    const t = std.testing;
    var cx = try core.Cx.init(t.allocator, std.testing.io);
    defer cx.deinit();
    const parent = try core.box(cx, .{ .width = .{ .px = 200 }, .height = .{ .px = 40 } }, .{});
    defer cx.freeNode(parent);
    parent.setStyleInline(cx.allocator, .{ .font_size = 22, .font_weight = 700 });
    const row = try core.text(cx, "", .{});
    try parent.appendChild(cx.allocator, row);

    try setEditable(row, cx, "hello", core.Color.BLACK, 14, 500, 21);
    const painted = row.resolveTextProps().?;
    try t.expectEqual(@as(f32, 14), painted.font_size);
    try t.expectEqual(@as(u16, 500), painted.font_weight);
    try t.expectApproxEqAbs(@as(f32, 1.5), painted.line_height, 0.0001);
    try t.expectEqualStrings("hello", painted.content);
    // Unchanged content and metrics keep the owned copy.
    const bytes = row.getTextRaw().?.content.ptr;
    try setEditable(row, cx, "hello", core.Color.BLACK, 14, 500, 21);
    try t.expect(row.getTextRaw().?.content.ptr == bytes);
}

test "VirtualList refresh and recycling release owned row snapshots" {
    const t = std.testing;
    const list = @import("../virtual_list/mod.zig");
    const Scope = @import("../../reactive.zig").Scope;
    const Rows = struct {
        generation: usize = 0,
        fn render(node: *core.Node, index: usize, cx: *core.Cx, context: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            var scratch: [80]u8 = undefined;
            const text = std.fmt.bufPrint(&scratch, "row-{d}-generation-{d}", .{ index, self.generation }) catch unreachable;
            set(node, cx, text, core.Color.BLACK, 14) catch unreachable;
        }
    };
    var cx = try core.Cx.init(t.allocator, std.testing.io);
    defer cx.deinit();
    const root = try core.box(cx, .{ .width = .{ .px = 320 }, .height = .{ .px = 96 } }, .{});
    cx.root = root;
    const scope = try Scope.init(t.allocator, null, cx.owner);
    defer scope.dispose();
    var rows: Rows = .{};
    const mounted = try list.VirtualList(.{ .item_count = 40, .item_height = 24, .width = 320, .height = 96, .overscan = 0 }).mountWithContext(scope, cx, &rows, null, Rows.render);
    try root.appendChild(t.allocator, mounted.container);
    for (0..12) |generation| {
        rows.generation = generation;
        mounted.state.scroll_state.scroll_y = @floatFromInt(generation * 48);
        cx.layout();
        mounted.state.updateVisibleItems();
        list.refreshRange(mounted.state, 0, 40);
        var count: usize = 0;
        for (mounted.state.pool_bindings, mounted.state.pool_nodes) |binding, row| {
            const index = binding orelse continue;
            var expected: [80]u8 = undefined;
            try t.expectEqualStrings(try std.fmt.bufPrint(&expected, "row-{d}-generation-{d}", .{ index, generation }), row.getText().?.content);
            try t.expect(row.getTextRaw().?.owned);
            count += 1;
        }
        try t.expect(count > 0);
    }
}
