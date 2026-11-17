const std = @import("std");
const ui = @import("ui");
const messages = @import("../view/ai_message_view.zig");
const a = std.testing.allocator;
const Fixture = struct {
    cx: *ui.Cx,
    scope: *ui.Scope,
    fn init() !Fixture {
        const cx = try ui.Cx.init(a, std.testing.io);
        cx.setViewport(800, 600);
        cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
        return .{ .cx = cx, .scope = try ui.Scope.init(a, null, cx.owner) };
    }
    fn deinit(self: Fixture) void {
        self.scope.dispose();
        self.cx.deinit();
    }
};
fn text(root: *ui.Node, result: *std.ArrayList(u8)) !void {
    if (root.getText()) |value| {
        try result.appendSlice(a, value.content);
        try result.append(a, '\n');
    }
    for (root.children.items) |child| try text(child, result);
}
test "incremental UI Markdown keeps completed blocks and matches final prose code and table text" {
    const f = try Fixture.init();
    defer f.deinit();
    const view = try messages.Retained.mount(f.cx, f.scope);
    try f.cx.root.?.appendChild(a, view.root);
    const first = "# 标题\n\n正文含 **粗体** 与 `code`。\n\n```zig\nconst x = 1;\n\nconst y = 2;\n```\n";
    try view.update(first, 540, null);
    const heading = view.chunks.items[0].root.id;
    const code = view.chunks.items[2].root.id;
    const final = first ++ "\n| 字段 | 值 |\n| --- | --- |\n| name | 中文 |\n\n最后一段";
    try view.update(final, 540, null);
    try std.testing.expectEqual(heading, view.chunks.items[0].root.id);
    try std.testing.expectEqual(code, view.chunks.items[2].root.id);
    const plain = try messages.mountWithWidth(f.cx, f.scope, final, 540);
    try f.cx.root.?.appendChild(a, plain);
    var expected: std.ArrayList(u8) = .empty;
    defer expected.deinit(a);
    var actual: std.ArrayList(u8) = .empty;
    defer actual.deinit(a);
    try text(plain, &expected);
    try text(view.root, &actual);
    try std.testing.expectEqualStrings(expected.items, actual.items);
    // Replacing an earlier segment invalidates its suffix, including bindings.
    try view.update("完全替换\n\n新尾部", 540, null);
    _ = f.cx.render();
    try std.testing.expectEqual(@as(usize, 2), view.chunks.items.len);
    try view.update("", 540, null);
    _ = f.cx.render();
    try std.testing.expectEqual(@as(usize, 0), view.chunks.items.len);
}
fn findId(root: *ui.Node, id: []const u8) ?*ui.Node {
    if (root.meta.ownership.meta.test_id) |value| if (std.mem.eql(u8, value, id)) return root;
    for (root.children.items) |child| if (findId(child, id)) |found| return found;
    return null;
}
fn findText(root: *ui.Node, value: []const u8) ?*ui.Node {
    if (root.getText()) |t| if (std.mem.eql(u8, t.content, value)) return root;
    for (root.children.items) |child| if (findText(child, value)) |found| return found;
    return null;
}
fn visibleSelection(root: *ui.Node) usize {
    var count: usize = 0;
    if (root.meta.ownership.meta.test_id) |id| if (std.mem.eql(u8, id, "ai.message.selection") and root.style.display != .none) {
        count += 1;
    };
    for (root.children.items) |child| count += visibleSelection(child);
    return count;
}
test "incremental UI Markdown selection crosses retained blocks and survives a plain tail update" {
    const FontSystem = @typeInfo(@typeInfo(@TypeOf(@as(ui.Cx, undefined).text.font_system)).optional.child).pointer.child;
    var fonts = try FontSystem.init(a, std.testing.io);
    defer fonts.deinit();
    const f = try Fixture.init();
    defer f.deinit();
    f.cx.text.setFontSystem(&fonts);
    const view = try messages.Retained.mount(f.cx, f.scope);
    try f.cx.root.?.appendChild(a, view.root);
    try view.update("first paragraph\n\nsecond paragraph\n\nmutable", 540, null);
    for (0..3) |_| {
        f.cx.advanceFrameClock();
        _ = f.cx.render();
    }
    const first = findText(view.root, "first paragraph").?;
    const second = findText(view.root, "second paragraph").?;
    const start = first.globalRect();
    const end = second.globalRect();
    f.cx.handleMouseMove(start.x + 1, start.y + start.h / 2);
    f.cx.handleMouseDown(start.x + 1, start.y + start.h / 2, .{});
    f.cx.handleMouseMove(end.x + 90, end.y + end.h / 2);
    f.cx.advanceFrameClock();
    _ = f.cx.render();
    f.cx.handleMouseUp(end.x + 90, end.y + end.h / 2);
    _ = f.cx.render();
    try std.testing.expect(visibleSelection(view.root) >= 2);
    try view.update("first paragraph\n\nsecond paragraph\n\nnew tail", 540, null);
    _ = f.cx.render();
    try std.testing.expectEqual(first, findText(view.root, "first paragraph").?);
    try std.testing.expect(visibleSelection(view.root) >= 2);
    try view.update("replace selected blocks", 540, null);
    _ = f.cx.render();
    try std.testing.expectEqual(@as(usize, 0), visibleSelection(view.root));
}

test "incremental UI growing fenced code retains controls wrap choice scroll state and full copy source" {
    const f = try Fixture.init();
    defer f.deinit();
    const view = try messages.Retained.mount(f.cx, f.scope);
    try f.cx.root.?.appendChild(a, view.root);
    try view.update("```zig\nconst value = 1;\n", 540, null);
    const code = view.chunks.items[0].code.?;
    for (0..3) |_| {
        f.cx.advanceFrameClock();
        _ = f.cx.render();
    }
    // The native W.CodeBlock's wrap toggle (Kaf7E A4: lines keep their length until wrapped).
    const button = findId(view.root, "ai.message.code.wrap").?.globalRect();
    f.cx.handleMouseDown(button.x + button.w / 2, button.y + button.h / 2, .{});
    f.cx.handleMouseUp(button.x + button.w / 2, button.y + button.h / 2);
    for (0..2) |_| _ = f.cx.render();
    try std.testing.expectEqualStrings("取消自动换行", findId(view.root, "ai.message.code.wrap").?.behavior.interaction.a11y.?.label.?);
    const text_node = findId(view.root, "ai.message.code.text").?;
    const root_id = view.chunks.items[0].root.id;
    const epoch = view.root.ownedTreeStructureRevision();
    var source: std.ArrayList(u8) = .empty;
    defer source.deinit(a);
    try source.appendSlice(a, "```zig\nconst value = 1;\n");
    for (0..50) |i| {
        var buffer: [64]u8 = undefined;
        try source.appendSlice(a, try std.fmt.bufPrint(&buffer, "const x{d} = {d};\n", .{ i, i }));
        try view.update(source.items, 540, null);
        try std.testing.expectEqual(root_id, view.chunks.items[0].root.id);
    }
    try source.appendSlice(a, "```\n");
    try view.update(source.items, 540, null);
    _ = f.cx.render();
    // The wrap choice and the code's text node survive the stream (the text follows its signal).
    try std.testing.expectEqualStrings("取消自动换行", findId(view.root, "ai.message.code.wrap").?.behavior.interaction.a11y.?.label.?);
    try std.testing.expect(findId(view.root, "ai.message.code.text").? == text_node);
    try std.testing.expectEqual(epoch, view.root.ownedTreeStructureRevision());
    try std.testing.expectEqualStrings(source.items[7 .. source.items.len - 4], code.source.peek());
}

test "a selection taken out of a view goes back onto a rebuilt view of the same text, never onto other text" {
    const Selection = @import("../view/ai_text_selection.zig");
    const FontSystem = @typeInfo(@typeInfo(@TypeOf(@as(ui.Cx, undefined).text.font_system)).optional.child).pointer.child;
    var fonts = try FontSystem.init(a, std.testing.io);
    defer fonts.deinit();
    const f = try Fixture.init();
    defer f.deinit();
    f.cx.text.setFontSystem(&fonts);
    const body = "first paragraph\n\nsecond paragraph\n\ntail";
    const settle = struct {
        fn run(cx: *ui.Cx) void {
            for (0..3) |_| {
                cx.advanceFrameClock();
                _ = cx.render();
            }
        }
    }.run;
    // The row the owner finds again (LIFECYCLE.md §3: a transcript row by its key).
    var row_scope = try f.scope.childScope();
    var view = try messages.Retained.mount(f.cx, row_scope);
    try f.cx.root.?.appendChild(a, view.root);
    try view.update(body, 540, null);
    settle(f.cx);
    {
        const start = findText(view.root, "first paragraph").?.globalRect();
        const end = findText(view.root, "second paragraph").?.globalRect();
        f.cx.handleMouseMove(start.x + 1, start.y + start.h / 2);
        f.cx.handleMouseDown(start.x + 1, start.y + start.h / 2, .{});
        f.cx.handleMouseMove(end.x + 90, end.y + end.h / 2);
        f.cx.advanceFrameClock();
        _ = f.cx.render();
        f.cx.handleMouseUp(end.x + 90, end.y + end.h / 2);
        _ = f.cx.render();
    }
    const marks = visibleSelection(view.root);
    try std.testing.expect(marks >= 2);
    const saved = Selection.capture(f.cx, view.root).?;
    // The view goes away (a rebuild, the panel closing): nodes first, then the Scope.
    f.cx.clearFocus();
    f.cx.detachChild(f.cx.root.?, view.root);
    f.cx.destroyDetached(view.root);
    row_scope.dispose();
    try std.testing.expect(Selection.selectedRoot(f.cx) == null);
    // Rebuilt from the same model: the same selection, and the root has the keyboard.
    row_scope = try f.scope.childScope();
    view = try messages.Retained.mount(f.cx, row_scope);
    try f.cx.root.?.appendChild(a, view.root);
    try view.update(body, 540, null);
    settle(f.cx);
    try std.testing.expect(Selection.restore(f.cx, view.root, saved));
    settle(f.cx);
    try std.testing.expectEqual(marks, visibleSelection(view.root));
    try std.testing.expect(Selection.selectedRoot(f.cx) != null);
    // Rebuilt over other text: nothing is selected (never moved onto other text).
    f.cx.clearFocus();
    f.cx.detachChild(f.cx.root.?, view.root);
    f.cx.destroyDetached(view.root);
    row_scope.dispose();
    row_scope = try f.scope.childScope();
    view = try messages.Retained.mount(f.cx, row_scope);
    try f.cx.root.?.appendChild(a, view.root);
    try view.update("first paragraph\n\nanother paragraph\n\ntail", 540, null);
    settle(f.cx);
    try std.testing.expect(!Selection.restore(f.cx, view.root, saved));
    settle(f.cx);
    try std.testing.expectEqual(@as(usize, 0), visibleSelection(view.root));
}
