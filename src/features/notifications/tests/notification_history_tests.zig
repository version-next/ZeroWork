//! 通知历史（`view/notification_history.yix` + `history/model/view_model.zig`）：原生 Popover / ScrollArea / Card /
//! Button / Badge / Alert 默认外观，状态在 view-model。这里断言行为：角标、内容、筛选、展开、有界滚动、动作、焦点、空闲不重绘。
const std = @import("std");
const ui = @import("ui");
const host = @import("../../../host/notification_host.zig");
const History = @import("../view/notification_history.zig").View;
const a = std.testing.allocator;

const Env = struct {
    cx: *ui.Cx,
    scope: *ui.Scope,
    notice: *host.Host,
    trigger: *ui.Node,
    view: *History,

    fn init(notice: *host.Host) !Env {
        const cx = try ui.Cx.init(a, std.testing.io);
        cx.setViewport(860, 480);
        cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
        const scope = try ui.Scope.init(a, null, cx.owner);
        notice.* = .{ .allocator = a, .activity = .{ .allocator = a }, .driver = undefined, .coordinator = try host.notifications.Coordinator.init(a, .{ .quiet_hours = "00:00-00:00" }, .{}) };
        const trigger = try ui.widgets.Button(.{ .label = "通知" }).mount(scope, cx);
        try cx.root.?.appendChild(a, trigger);
        const view = try History.mount(cx, scope, notice, trigger);
        return .{ .cx = cx, .scope = scope, .notice = notice, .trigger = trigger, .view = view };
    }
    fn deinit(self: Env) void {
        self.scope.dispose();
        self.notice.coordinator.deinit();
        self.notice.activity.deinit();
        self.notice.windows.deinit(a);
        self.cx.deinit();
    }
    fn settle(self: Env) void {
        for (0..8) |_| {
            self.cx.frame_count += 1;
            self.cx.frame_time_ms += 16;
            self.cx.layout();
            _ = self.cx.render();
        }
    }
    fn publish(self: Env, operation: u64, severity: host.notifications.Severity, detail: []const u8, actions: []const host.notifications.NotificationAction) !u64 {
        const published = try self.notice.coordinator.publishNotification(.{ .attention = .{ .kind = .task_blocked, .requires_action = true, .time_sensitive = true }, .definition_id = "host.feedback", .owner = .{ .window_id = 1, .content = .{ .session = .{ .session_id = @fromBackingInt(1) } } }, .operation_id = operation, .event_revision = 1, .phase = .failed, .severity = severity, .title = "Failure", .owner_name = "Local Terminal", .object_name = "backup.zip", .detail = detail, .actions = actions }, .{ .local_minute = 0, .monotonic_ms = 0 });
        return published.fact_id;
    }
    fn click(self: Env, node: *ui.Node) void {
        const rect = node.globalRect();
        self.cx.handleMouseDown(rect.x + rect.w / 2, rect.y + rect.h / 2, .{});
        self.cx.handleMouseUp(rect.x + rect.w / 2, rect.y + rect.h / 2);
        self.settle();
    }
};

fn find(root: *ui.Node, id: []const u8) ?*ui.Node {
    if (root.meta.ownership.meta.test_id) |value| if (std.mem.eql(u8, value, id)) return root;
    for (root.children.items) |child| if (find(child, id)) |found| return found;
    return null;
}
fn count(root: *ui.Node, id: []const u8) usize {
    var n: usize = 0;
    if (root.meta.ownership.meta.test_id) |value| if (std.mem.eql(u8, value, id)) {
        n += 1;
    };
    for (root.children.items) |child| n += count(child, id);
    return n;
}
fn textOf(root: *ui.Node, buffer: *std.ArrayList(u8)) !void {
    if (root.getText()) |text| try buffer.appendSlice(a, text.content);
    for (root.children.items) |child| try textOf(child, buffer);
}
fn contains(root: *ui.Node, needle: []const u8) bool {
    var buffer: std.ArrayList(u8) = .empty;
    defer buffer.deinit(a);
    textOf(root, &buffer) catch return false;
    return std.mem.indexOf(u8, buffer.items, needle) != null;
}
fn displayed(root: *ui.Node, id: []const u8) bool {
    const node = find(root, id) orelse return false;
    return node.isDisplayedInTree() and node.globalRect().w > 0;
}

test "notification closed history badge does not request another idle frame" {
    var notice: host.Host = undefined;
    const env = try Env.init(&notice);
    defer env.deinit();
    const hook = env.cx.after_layout_hooks.items[env.cx.after_layout_hooks.items.len - 1];
    for (0..32) |_| {
        env.cx.frame_count += 1;
        env.cx.frame_time_ms += 16;
        _ = env.cx.render();
    }
    try std.testing.expect(!env.cx.hasPendingSceneWork());
    _ = hook.run(hook.ctx, 0, false);
    try std.testing.expect(!env.cx.hasPendingSceneWork());
}

test "notification history bell badge shows pending count and an unread dot" {
    var notice: host.Host = undefined;
    const env = try Env.init(&notice);
    defer env.deinit();
    env.settle();
    try std.testing.expect(!displayed(env.trigger, "notifications.unread"));
    _ = try env.publish(1, .failure, "disk full", &.{});
    env.settle();
    try std.testing.expect(displayed(env.trigger, "notifications.unread"));
    try std.testing.expect(contains(find(env.trigger, "notifications.unread").?, "1"));
    // Resolved but unread: a dot without a number.
    for (notice.coordinator.notification_records.items) |*record| record.event.attention.resolved = true;
    notice.coordinator.history_revision +%= 1;
    env.settle();
    try std.testing.expect(displayed(env.trigger, "notifications.unread"));
    try std.testing.expect(!contains(find(env.trigger, "notifications.unread").?, "1"));
    // Opening reads the history; nothing left to badge.
    env.view.open.set(true);
    env.settle();
    env.view.open.set(false);
    env.settle();
    try std.testing.expect(!displayed(env.trigger, "notifications.unread"));
}

test "notification history shows complete errors in a bounded scrolling middle layer" {
    var notice: host.Host = undefined;
    const env = try Env.init(&notice);
    defer env.deinit();
    var detail: [4096]u8 = undefined;
    for (&detail, 0..) |*byte, index| byte.* = "complete retained long notification detail "[index % 43];
    _ = try env.publish(1, .failure, &detail, &.{});
    env.view.open.set(true);
    env.settle();
    const details = find(env.view.root, "notifications.history.details").?;
    const message = find(env.view.root, "notifications.history.message").?;
    try std.testing.expect(contains(message, &detail));
    try std.testing.expect(details.globalRect().h <= 240.5);
    try std.testing.expect(message.globalRect().h > details.globalRect().h);
    try std.testing.expect(find(env.view.root, "notifications.history.expand") == null);
    try std.testing.expect(find(env.view.root, "notifications.history.viewport").?.globalRect().h <= 320.5);
    // Scrolling the cause moves it inside its own viewport only.
    const before = message.globalRect().y;
    const area = details.globalRect();
    env.cx.handleScroll(.{ .x = area.x + area.w / 2, .y = area.y + area.h / 2, .dx = 0, .dy = -400 });
    env.settle();
    try std.testing.expect(message.globalRect().y < before);
}

test "notification history expands only independent details without repeating title or owner" {
    var notice: host.Host = undefined;
    const env = try Env.init(&notice);
    defer env.deinit();
    for ([_][]const u8{ "", " \n\t", "Failure", "Local Terminal", "backup.zip", "Permission denied\nexit 1" }, 1..) |detail, operation| {
        for (notice.coordinator.notification_records.items) |*prior| prior.event.attention.resolved = true;
        notice.coordinator.clearHistory();
        _ = try env.publish(operation, .failure, detail, &.{});
        env.view.open.set(true);
        env.settle();
        try std.testing.expect(find(env.view.root, "notifications.history.expand") == null);
        if (operation < 6) {
            try std.testing.expect(find(env.view.root, "notifications.history.details") == null);
        } else {
            try std.testing.expect(contains(find(env.view.root, "notifications.history.message").?, detail));
        }
    }
    // A non-failure with an independent detail is collapsed behind the expand control.
    for (notice.coordinator.notification_records.items) |*prior| prior.event.attention.resolved = true;
    notice.coordinator.clearHistory();
    env.view.vm.showRecent();
    _ = try env.publish(10, .warning, "retry later", &.{});
    env.settle();
    try std.testing.expect(find(env.view.root, "notifications.history.details") == null);
    const expand = find(env.view.root, "notifications.history.expand").?;
    env.click(expand);
    try std.testing.expect(contains(find(env.view.root, "notifications.history.message").?, "retry later"));
    env.click(find(env.view.root, "notifications.history.expand").?);
    try std.testing.expect(find(env.view.root, "notifications.history.details") == null);
}

test "notification history filters, clears ended records and reports unavailable actions" {
    var notice: host.Host = undefined;
    const env = try Env.init(&notice);
    defer env.deinit();
    const pending = try env.publish(1, .failure, "", &.{.{ .kind = .locate_owner, .label = "查看来源" }});
    _ = try env.publish(2, .failure, "", &.{});
    notice.coordinator.notification_records.items[1].event.attention.resolved = true;
    notice.coordinator.history_revision +%= 1;
    env.view.open.set(true);
    env.settle();
    // Pending only by default; the count is the pending number.
    try std.testing.expectEqual(@as(usize, 1), count(env.view.root, "notifications.history.record"));
    try std.testing.expect(contains(find(env.view.root, "notifications.history.count").?, "1"));
    try std.testing.expect(contains(find(env.view.root, "notifications.history.summary").?, "Local Terminal"));
    env.click(find(env.view.root, "notifications.history.recent").?);
    try std.testing.expectEqual(@as(usize, 2), count(env.view.root, "notifications.history.record"));
    try std.testing.expect(displayed(env.view.root, "notifications.history.footer"));
    // No window owns the source: the action is unavailable and the panel says so.
    env.click(find(env.view.root, "notifications.history.action").?);
    try std.testing.expect(env.view.open.peek());
    try std.testing.expect(contains(env.view.root, "该操作已不可用"));
    try std.testing.expect(notice.coordinator.recordFor(pending) != null);
    env.click(find(env.view.root, "notifications.history.clear").?);
    try std.testing.expect(!displayed(env.view.root, "notifications.history.footer"));
    try std.testing.expect(!contains(env.view.root, "该操作已不可用"));
    env.click(find(env.view.root, "notifications.history.pending").?);
    try std.testing.expectEqual(@as(usize, 1), count(env.view.root, "notifications.history.record"));
    // Ended owners keep their record but disable its actions.
    notice.coordinator.ownerEnded(.{ .session = .{ .session_id = @fromBackingInt(1) } });
    env.click(find(env.view.root, "notifications.history.recent").?);
    try std.testing.expect(find(env.view.root, "notifications.history.action") != null);
    // Empty state per filter.
    for (notice.coordinator.notification_records.items) |*prior| prior.event.attention.resolved = true;
    notice.coordinator.clearHistory();
    env.settle();
    try std.testing.expect(displayed(env.view.root, "notifications.history.empty"));
    try std.testing.expect(contains(env.view.root, "暂无重要提醒"));
    env.click(find(env.view.root, "notifications.history.pending").?);
    try std.testing.expect(contains(env.view.root, "当前没有待处理提醒"));
}

test "notification history: 清除已结束 is undoable — hidden at once, 撤销 restores, the toast leaving clears" {
    const C = @import("../../../shared/ui/confirm/confirm.zig");
    const Toasts = struct {
        ids: [4]u64 = undefined,
        n: usize = 0,
        fn post(raw: *anyopaque, text: []const u8) anyerror!u64 {
            const self: *@This() = @ptrCast(@alignCast(raw));
            try std.testing.expectEqualStrings("已清除已结束的提醒", text);
            self.ids[self.n] = 100 + self.n;
            self.n += 1;
            return self.ids[self.n - 1];
        }
    };
    var notice: host.Host = undefined;
    const env = try Env.init(&notice);
    defer env.deinit();
    var toasts: Toasts = .{};
    C.install(env.cx, .{ .context = &toasts, .post = Toasts.post });
    defer C.uninstall(env.cx);
    _ = try env.publish(1, .failure, "", &.{});
    _ = try env.publish(2, .failure, "", &.{});
    notice.coordinator.notification_records.items[1].event.attention.resolved = true;
    notice.coordinator.history_revision +%= 1;
    env.view.open.set(true);
    env.settle();
    env.click(find(env.view.root, "notifications.history.recent").?);
    try std.testing.expectEqual(@as(usize, 2), count(env.view.root, "notifications.history.record"));
    env.click(find(env.view.root, "notifications.history.clear").?);
    // Hidden right away, still in the coordinator while the toast is up.
    try std.testing.expectEqual(@as(usize, 1), count(env.view.root, "notifications.history.record"));
    try std.testing.expect(!displayed(env.view.root, "notifications.history.footer"));
    try std.testing.expectEqual(@as(usize, 2), notice.coordinator.notification_records.items.len);
    try std.testing.expectEqual(@as(usize, 1), env.view.vm.clearPending());
    // 撤销: back again, nothing removed.
    C.settle(env.cx, toasts.ids[0], .revert);
    env.settle();
    try std.testing.expectEqual(@as(usize, 2), count(env.view.root, "notifications.history.record"));
    try std.testing.expect(displayed(env.view.root, "notifications.history.footer"));
    // Again, and the toast leaves: the ended record is cleared from the coordinator.
    env.click(find(env.view.root, "notifications.history.clear").?);
    C.settle(env.cx, toasts.ids[1], .commit);
    env.settle();
    try std.testing.expectEqual(@as(usize, 1), notice.coordinator.notification_records.items.len);
    try std.testing.expectEqual(@as(usize, 1), count(env.view.root, "notifications.history.record"));
    try std.testing.expectEqual(@as(usize, 0), env.view.vm.clearPending());
}

test "notification history opens on the bell, focuses close, and returns focus on close" {
    var notice: host.Host = undefined;
    const env = try Env.init(&notice);
    defer env.deinit();
    env.settle();
    try std.testing.expectEqual(@as(usize, 0), notice.coordinator.open_centers);
    env.click(env.trigger);
    try std.testing.expect(env.view.open.peek());
    try std.testing.expectEqual(@as(usize, 1), notice.coordinator.open_centers);
    try std.testing.expect(displayed(env.view.root, "notifications.history"));
    const close = find(env.view.root, "notifications.history.close").?;
    const focused = env.cx.focus_manager.getFocused().?;
    try std.testing.expect(focused == close or focused.isDescendantOf(close));
    env.click(close);
    try std.testing.expect(!env.view.open.peek());
    try std.testing.expectEqual(@as(usize, 0), notice.coordinator.open_centers);
    try std.testing.expectEqual(env.trigger, env.cx.focus_manager.getFocused().?);
    // Reopening keeps one panel (no rebuilt chrome) and stays toggled by the bell.
    const root = env.view.root;
    for (0..4) |_| {
        env.click(env.trigger);
        try std.testing.expect(env.view.open.peek());
        try std.testing.expectEqual(root, env.view.root);
        env.click(env.trigger);
        try std.testing.expect(!env.view.open.peek());
    }
}
test {
    _ = @import("../history/model/view_model.zig");
}
