const std = @import("std");
const ui = @import("ui");
const Feedback = @import("../view/ai_feedback_view.zig");
const a = std.testing.allocator;

fn find(node: *ui.Node, id: []const u8) ?*ui.Node {
    if (node.meta.ownership.meta.test_id) |value| if (std.mem.eql(u8, value, id)) return node;
    for (node.children.items) |child| if (find(child, id)) |hit| return hit;
    return null;
}
fn hasText(node: *ui.Node, needle: []const u8) bool {
    if (node.getText()) |text| if (std.mem.indexOf(u8, text.content, needle) != null) return true;
    for (node.children.items) |child| if (hasText(child, needle)) return true;
    return false;
}
fn shown(root: *ui.Node, id: []const u8) bool {
    const node = find(root, id) orelse return false;
    return node.isDisplayedInTree();
}
fn settle(cx: *ui.Cx) void {
    for (0..4) |_| {
        cx.frame_count += 1;
        cx.layout();
        _ = cx.render();
    }
}

test "AI feedback repeated polling errors leave the idle scene clean" {
    const cx = try ui.Cx.init(a, std.testing.io);
    defer cx.deinit();
    const scope = try ui.Scope.init(a, null, cx.owner);
    defer scope.dispose();
    cx.setViewport(600, 358);
    cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    const feedback = try Feedback.View.mount(cx, scope);
    try cx.root.?.appendChild(a, feedback.root);
    var buffer: [32]u8 = undefined;
    // The host passes transient buffers; the shown text must not alias them.
    feedback.show(try std.fmt.bufPrint(&buffer, "InvalidUtf8", .{}), .warning);
    @memset(&buffer, 'z');
    settle(cx);
    for (0..4) |_| _ = cx.render();
    try std.testing.expect(!cx.hasPendingSceneWork());
    const revision = ui.Node.treeStructureRevision();
    for (0..100) |_| feedback.show("InvalidUtf8", .warning);
    try std.testing.expect(!cx.hasPendingSceneWork());
    try std.testing.expectEqual(revision, ui.Node.treeStructureRevision());
    try std.testing.expect(hasText(find(feedback.root, "ai.feedback.text").?, "InvalidUtf8"));
    feedback.show("请求失败", .warning);
    try std.testing.expect(cx.hasPendingSceneWork());
    feedback.show("请求失败", .rollback);
    settle(cx);
    try std.testing.expect(shown(feedback.root, "ai.feedback.dismiss"));
    feedback.dismiss();
    settle(cx);
    try std.testing.expect(!feedback.root.isDisplayedInTree());
    // The same text again is a new notice.
    feedback.show("请求失败", .rollback);
    feedback.dismiss();
    feedback.show(Feedback.rollback_label, .rollback);
    settle(cx);
    try std.testing.expect(feedback.root.isDisplayedInTree());
}

test "AI feedback stays in scroll flow and preserves composer bounds with long text" {
    const cx = try ui.Cx.init(a, std.testing.io);
    defer cx.deinit();
    const scope = try ui.Scope.init(a, null, cx.owner);
    defer scope.dispose();
    cx.setViewport(600, 358);
    const root = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .direction = .column }, .{});
    cx.root = root;
    const scroll = try ui.widgets.ScrollArea(.{ .height = 200, .direction = .vertical }).mount(scope, cx);
    scroll.container.setStyleInline(a, .{ .width = .fill(), .height = .fill(), .flex = 1, .min_height = 0 });
    try root.appendChild(a, scroll.container);
    const feedback = try Feedback.View.mount(cx, scope);
    try scroll.content.appendChild(a, feedback.root);
    const composer = try ui.box(cx, .{ .width = .fill(), .height = .{ .px = 90 }, .flex_shrink = 0 }, .{});
    try root.appendChild(a, composer);
    for ([_]f32{ 600, 320 }) |width| {
        cx.setViewport(width, 358);
        feedback.show("", .warning);
        settle(cx);
        const before = composer.globalRect();
        try std.testing.expect(!feedback.root.isDisplayedInTree());
        feedback.show(Feedback.rollback_label, .rollback);
        settle(cx);
        try std.testing.expectEqual(before, composer.globalRect());
        try std.testing.expect(shown(feedback.root, "ai.feedback.rollback"));
        try std.testing.expect(!shown(feedback.root, "ai.feedback.warning"));
        const close = find(feedback.root, "ai.feedback.dismiss").?.globalRect();
        const text = find(feedback.root, "ai.feedback.text").?.globalRect();
        try std.testing.expect(text.x + text.w <= close.x);
        try std.testing.expect(close.x + close.w <= width);
        try std.testing.expect(text.h > 0);
        // A path with no whitespace must wrap within the content width.
        var path: [1600]u8 = undefined;
        @memset(&path, 'x');
        feedback.show(&path, .warning);
        settle(cx);
        try std.testing.expectEqual(before, composer.globalRect());
        try std.testing.expect(shown(feedback.root, "ai.feedback.warning"));
        try std.testing.expect(!shown(feedback.root, "ai.feedback.dismiss"));
        const long_text = find(feedback.root, "ai.feedback.text").?.globalRect();
        try std.testing.expect(long_text.x + long_text.w <= width + 0.1);
        try std.testing.expect(long_text.h > 36);
        feedback.show(Feedback.rollback_label, .rollback);
        settle(cx);
        const dismiss = find(feedback.root, "ai.feedback.dismiss").?.globalRect();
        cx.handleMouseDown(dismiss.x + dismiss.w / 2, dismiss.y + dismiss.h / 2, .{});
        cx.handleMouseUp(dismiss.x + dismiss.w / 2, dismiss.y + dismiss.h / 2);
        settle(cx);
        try std.testing.expect(!feedback.root.isDisplayedInTree());
        try std.testing.expectEqual(before, composer.globalRect());
    }
}
