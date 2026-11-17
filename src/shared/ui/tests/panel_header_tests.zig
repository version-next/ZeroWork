//! 同级面板统一头部与关闭按钮（panel-heads，`shared/ui/components/panel_header`）：头部高 30、图标 14、关闭按钮
//! 是原生 ghost sm 图标按钮 24 × 24（不带样式覆盖）、提示“关闭 · Esc”；与浮动卡片外框头部同一规格。
const std = @import("std");
const ui = @import("ui");
const ph = @import("../components/panel_header/panel_header.zig");

fn findTestId(node: *ui.Node, id: []const u8) ?*ui.Node {
    if (node.meta.ownership.meta.test_id) |t| if (std.mem.eql(u8, t, id)) return node;
    for (node.children.items) |child| if (findTestId(child, id)) |hit| return hit;
    return null;
}

fn settle(cx: *ui.Cx) void {
    for (0..4) |_| {
        cx.layout();
        _ = cx.render();
    }
}

const Counter = struct {
    n: u32 = 0,
    fn hit(self: *@This()) void {
        self.n += 1;
    }
};

test "panel header: 30 high, icon 14, close is the native ghost sm icon button (24 high); card and flush insets" {
    const cx = try ui.Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    cx.setViewport(800, 200);
    cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .direction = .column }, .{});
    const scope = try ui.Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    var counter: Counter = .{};
    var slots: ph.Slots = .{};
    const subtitle = try scope.createSignal([]const u8, "3 条");
    const card = try ph.mountHeader(scope, cx, &slots, .{ .icon = ui.icons.bell, .title = "提醒", .subtitle = subtitle, .header_test_id = "t.header", .subtitle_test_id = "t.count", .close_test_id = "t.close", .close_tooltip_test_id = "t.close.tooltip", .on_close = cx.on(Counter, &counter, Counter.hit) });
    var flush_slots: ph.Slots = .{};
    const flush = try ph.mountHeader(scope, cx, &flush_slots, .{ .icon = ui.icons.bell, .title = "提醒", .inset = .flush, .close_test_id = "t.flush.close" });
    var bare_slots: ph.Slots = .{};
    const bare = try ph.mountHeader(scope, cx, &bare_slots, .{ .icon = ui.icons.history, .title = "会话记录", .closable = false, .header_test_id = "t.bare" });
    for ([_]*ui.Node{ card, flush, bare }) |n| try cx.root.?.appendChild(cx.allocator, n);
    settle(cx);

    try std.testing.expect(slots.root == card);
    try std.testing.expect(slots.actions != null);
    for ([_]*ui.Node{ card, flush, bare }) |n| try std.testing.expectEqual(@as(f32, 30), n.globalRect().h);
    const close = findTestId(card, "t.close").?;
    const r = close.globalRect();
    // native ghost sm icon-only geometry (height 24; width from the native icon slot)
    // native ghost sm icon-only geometry: square, the native sm control height (24 in the app theme)
    try std.testing.expectEqual(r.w, r.h);
    try std.testing.expect(r.h >= 24 and r.h <= 26);
    // card inset: 12 before the icon, 4 after the close button
    const icon = card.children.items[0];
    try std.testing.expectEqual(@as(f32, 12), icon.globalRect().x - card.globalRect().x);
    try std.testing.expectEqual(@as(f32, 14), icon.globalRect().w);
    try std.testing.expectApproxEqAbs(@as(f32, 4), (card.globalRect().x + card.globalRect().w) - (r.x + r.w), 0.5);
    // flush inset: icon and close touch the edges
    const flush_close = findTestId(flush, "t.flush.close").?.globalRect();
    try std.testing.expectEqual(flush.globalRect().x, flush.children.items[0].globalRect().x);
    try std.testing.expectApproxEqAbs(flush.globalRect().x + flush.globalRect().w, flush_close.x + flush_close.w, 0.5);
    // no close when closable = false; the count reads "N 条"
    try std.testing.expect(findTestId(bare, "t.close") == null);
    try std.testing.expect(findTestId(card, "t.count") != null);
    try std.testing.expectEqualStrings("关闭", close.behavior.interaction.a11y.?.label.?);
    close.behavior.events.on_click.?.invoke();
    try std.testing.expectEqual(@as(u32, 1), counter.n);
}

test "panel close: standalone mount is the same native ghost sm button" {
    const cx = try ui.Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    cx.setViewport(200, 100);
    cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .direction = .column }, .{});
    const scope = try ui.Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    const slot = try ph.mountClose(scope, cx, .{ .label = "关闭预览", .test_id = "t.solo" });
    try cx.root.?.appendChild(cx.allocator, slot);
    settle(cx);
    const button = findTestId(slot, "t.solo").?;
    try std.testing.expectEqual(button.globalRect().w, button.globalRect().h);
    try std.testing.expect(button.globalRect().h >= 24 and button.globalRect().h <= 26);
    try std.testing.expectEqualStrings("关闭预览", button.behavior.interaction.a11y.?.label.?);
}

test {
    _ = ph;
}

test "panel close: options.button receives the native button node (no test_id walk needed)" {
    const cx = try ui.Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    cx.setViewport(400, 120);
    cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .direction = .row }, .{});
    const scope = try ui.Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    var counter: Counter = .{};
    var button: ?*ui.Node = null;
    const slot = try ph.mountClose(scope, cx, .{ .label = "关闭面板", .test_id = "t.out.close", .on_close = cx.on(Counter, &counter, Counter.hit), .button = &button });
    try cx.root.?.appendChild(cx.allocator, slot);
    settle(cx);
    try std.testing.expect(button != null);
    try std.testing.expect(button.? == findTestId(slot, "t.out.close").?);
    try std.testing.expect(button.? != slot);
    try std.testing.expectEqualStrings("关闭面板", button.?.behavior.interaction.a11y.?.label.?);
    // Without the out-parameter nothing is written and the slot is still returned.
    const plain = try ph.mountClose(scope, cx, .{ .test_id = "t.plain.close" });
    try cx.root.?.appendChild(cx.allocator, plain);
    settle(cx);
    try std.testing.expect(findTestId(plain, "t.plain.close") != null);
}
