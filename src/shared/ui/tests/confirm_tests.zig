//! `shared/ui/confirm`：`confirm(spec)` 的原生确认框与 `undoable(spec)` 的提交 / 回滚（CONSISTENCY_AUDIT #2）。
const std = @import("std");
const ui = @import("ui");
const C = @import("../confirm/confirm.zig");

const testing = std.testing;

fn textOf(node: *ui.Node) []const u8 {
    if (node.getText()) |t| return t.content;
    for (node.children.items) |child| {
        const s = textOf(child);
        if (s.len != 0) return s;
    }
    return "";
}

const Probe = struct {
    confirmed: usize = 0,
    cancelled: usize = 0,
    committed: std.ArrayList(u64) = .empty,
    reverted: std.ArrayList(u64) = .empty,
    posted: std.ArrayList(u64) = .empty,
    next: u64 = 500,

    fn onConfirm(self: *Probe) void {
        self.confirmed += 1;
    }
    fn onCancel(self: *Probe) void {
        self.cancelled += 1;
    }
    fn commit(raw: *anyopaque, token: u64) void {
        const self: *Probe = @ptrCast(@alignCast(raw));
        self.committed.append(testing.allocator, token) catch unreachable;
    }
    fn revert(raw: *anyopaque, token: u64) void {
        const self: *Probe = @ptrCast(@alignCast(raw));
        self.reverted.append(testing.allocator, token) catch unreachable;
    }
    fn post(raw: *anyopaque, _: []const u8) anyerror!u64 {
        const self: *Probe = @ptrCast(@alignCast(raw));
        self.next += 1;
        try self.posted.append(testing.allocator, self.next);
        return self.next;
    }
    fn deinit(self: *Probe) void {
        self.committed.deinit(testing.allocator);
        self.reverted.deinit(testing.allocator);
        self.posted.deinit(testing.allocator);
    }
};

test "confirm(spec): native ConfirmDialog with 动词 + 对象, 取消, danger, scrim = cancel" {
    const cx = try ui.Cx.init(testing.allocator, testing.io);
    defer cx.deinit();
    cx.setViewport(900, 700);
    const root = try ui.box(cx, .{ .width = .{ .px = 900 }, .height = .{ .px = 700 } }, .{});
    cx.root = root;
    const scope = try ui.Scope.init(testing.allocator, null, cx.owner);
    defer scope.dispose();
    var probe: Probe = .{};
    defer probe.deinit();
    const open = try scope.createSignal(bool, false);
    const dialog = try C.confirm(scope, cx, .{
        .open = open,
        .title = "替换主机密钥？",
        .message = "服务器的主机密钥与已保存的不同。",
        .action = C.label(.replace, "主机密钥"),
        .on_confirm = cx.on(Probe, &probe, Probe.onConfirm),
        .on_cancel = cx.on(Probe, &probe, Probe.onCancel),
        .test_id = "t.confirm",
        .test_ids = .{ .cancel = "t.cancel", .confirm = "t.accept" },
    });
    if (!dialog.modal.portaled) try root.appendChild(testing.allocator, dialog.modal.overlay);
    try testing.expectEqualStrings("t.confirm", dialog.modal.dialog.meta.ownership.meta.test_id.?);
    try testing.expectEqualStrings("取消", textOf(dialog.cancel));
    try testing.expectEqualStrings("替换主机密钥", textOf(dialog.confirm));
    const danger = try ui.widgets.Button(.{ .label = "x", .variant = .danger }).mount(scope, cx);
    defer cx.freeNode(danger);
    try testing.expectEqual(danger.getBackground(), dialog.confirm.getBackground());
    open.set(true);
    cx.handleKeyDown(.escape, .{});
    try testing.expect(!open.peek());
    try testing.expectEqual(@as(usize, 1), probe.cancelled);
    open.set(true);
    dialog.confirm.behavior.events.on_click.?.invoke();
    try testing.expect(!open.peek());
    try testing.expectEqual(@as(usize, 1), probe.confirmed);
}

test "undoable(spec): nothing commits while the toast is up; 撤销 reverts; the toast leaving commits" {
    const cx = try ui.Cx.init(testing.allocator, testing.io);
    defer cx.deinit();
    var probe: Probe = .{};
    defer probe.deinit();
    // No toast outlet in this window yet: the operation commits at once.
    try testing.expect(!C.undoable(cx, .{ .text = "已删除主机 a", .owner = &probe, .context = &probe, .token = 1, .commit = Probe.commit, .revert = Probe.revert }));
    try testing.expectEqualSlices(u64, &.{1}, probe.committed.items);
    C.install(cx, .{ .context = &probe, .post = Probe.post });
    defer C.uninstall(cx);
    try testing.expect(C.undoable(cx, .{ .text = "已删除主机 b", .owner = &probe, .context = &probe, .token = 2, .commit = Probe.commit, .revert = Probe.revert }));
    try testing.expect(C.undoable(cx, .{ .text = "已删除主机 c", .owner = &probe, .context = &probe, .token = 3, .commit = Probe.commit, .revert = Probe.revert }));
    try testing.expect(C.isPending(cx, &probe, 2));
    try testing.expectEqual(@as(usize, 1), probe.committed.items.len);
    C.settle(cx, probe.posted.items[0], .revert);
    try testing.expectEqualSlices(u64, &.{2}, probe.reverted.items);
    try testing.expect(!C.isPending(cx, &probe, 2));
    C.settle(cx, probe.posted.items[1], .commit);
    try testing.expectEqualSlices(u64, &.{ 1, 3 }, probe.committed.items);
    // The owner going away commits what is still pending.
    _ = C.undoable(cx, .{ .text = "已删除会话记录", .owner = &probe, .context = &probe, .token = 4, .commit = Probe.commit, .revert = Probe.revert });
    C.flushOwner(cx, &probe);
    try testing.expectEqualSlices(u64, &.{ 1, 3, 4 }, probe.committed.items);
    try testing.expectEqual(@as(usize, 1), probe.reverted.items.len);
}

test "undoable(spec): closing the window commits every pending operation" {
    const cx = try ui.Cx.init(testing.allocator, testing.io);
    defer cx.deinit();
    var probe: Probe = .{};
    defer probe.deinit();
    C.install(cx, .{ .context = &probe, .post = Probe.post });
    _ = C.undoable(cx, .{ .text = "a", .owner = &probe, .context = &probe, .token = 9, .commit = Probe.commit, .revert = Probe.revert });
    C.uninstall(cx);
    try testing.expectEqualSlices(u64, &.{9}, probe.committed.items);
    // After the outlet is gone a new operation commits at once (no ledger is recreated).
    _ = C.undoable(cx, .{ .text = "b", .owner = &probe, .context = &probe, .token = 10, .commit = Probe.commit, .revert = Probe.revert });
    try testing.expectEqualSlices(u64, &.{ 9, 10 }, probe.committed.items);
}
