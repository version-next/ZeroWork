//! 窗口通知的两个原生栈（`W.NotificationHost`，`toast_stack.yix`：右上角卡片栈、中下方轻提示栈）与协调器的接线：
//! 内容、来源、详情、动作、关闭、到期（原生生命条计时）、就地转换、卡片栈的遮挡与操作失败例外、本地回执的落点、
//! 分流（无动作的成功 / 信息类提醒进轻提示栈），以及轻提示栈永远在最上层（不随遮挡隐藏、不停表，层级高于宿主
//! 浮层）。外观归 zenit，这里只断言行为、位置分区、层级与 test_id。
const std = @import("std");
const ui = @import("ui");
const host = @import("../../../host/notification_host.zig");
const presenter_mod = @import("../host/notification_presenter.zig");
const Presenter = presenter_mod.Presenter;
const a = std.testing.allocator;
const content_rect: ui.ComputedRect = .{ .x = 0, .y = 0, .w = 860, .h = 480 };

/// Walk the window (root and popover portal) for a test id.
fn find(cx: *ui.Cx, id: []const u8) ?*ui.Node {
    if (cx.root) |root| if (findIn(root, id)) |node| return node;
    const portal = cx.ensurePopoverPortalRoot() catch return null;
    return findIn(portal, id);
}
fn findIn(root: *ui.Node, id: []const u8) ?*ui.Node {
    if (root.meta.ownership.meta.test_id) |value| if (std.mem.eql(u8, value, id)) return root;
    for (root.children.items) |child| if (findIn(child, id)) |found| return found;
    return null;
}
fn countIn(root: *ui.Node, id: []const u8) usize {
    var n: usize = if (root.meta.ownership.meta.test_id) |value| @intFromBool(std.mem.eql(u8, value, id)) else 0;
    for (root.children.items) |child| n += countIn(child, id);
    return n;
}
fn textOf(node: *ui.Node) []const u8 {
    if (node.getText()) |t| return t.content;
    for (node.children.items) |child| {
        const t = textOf(child);
        if (t.len > 0) return t;
    }
    return "";
}

const WindowProbe = struct {
    calls: usize = 0,
    owner: u64 = 0,
    fn owns(_: *anyopaque, _: host.notifications.Target) bool {
        return true;
    }
    fn activate(raw: *anyopaque, target: host.notifications.Target) bool {
        const self: *@This() = @ptrCast(@alignCast(raw));
        self.calls += 1;
        self.owner = @backingInt(target.owner.session.session_id);
        return true;
    }
    fn feedback(_: *anyopaque, _: []const u8) void {}
    fn name(_: *anyopaque, _: host.ContentOwner) []const u8 {
        return "prod-web-01";
    }
};

/// One window: a notification host (coordinator), the presenter and its native stack. `frame`
/// projects the coordinator and runs one native frame at `now`.
const Rig = struct {
    cx: *ui.Cx,
    scope: *ui.Scope,
    notice: host.Host,
    window: host.WindowId = @fromBackingInt(1),
    view: *Presenter = undefined,
    probe: WindowProbe = .{},

    fn init(self: *Rig, quiet_hours: []const u8) !void {
        const cx = try ui.Cx.init(a, std.testing.io);
        errdefer cx.deinit();
        cx.setViewport(860, 480);
        // Fixed like a window root: the stack's portal fills it.
        cx.root = try ui.box(cx, .{ .width = .{ .px = 860 }, .height = .{ .px = 480 } }, .{});
        // A live pointer over the content, as after a platform pointer move.
        cx.cursor_state.pointer_valid = true;
        cx.hover_sync.pointer_over_content = true;
        cx.mouse_x = 5;
        cx.mouse_y = 470;
        self.* = .{ .cx = cx, .scope = try ui.Scope.init(a, null, cx.owner), .notice = .{ .allocator = a, .activity = .{ .allocator = a }, .driver = undefined, .coordinator = try host.notifications.Coordinator.init(a, .{ .quiet_hours = quiet_hours }, .{}) } };
        self.window = try self.notice.registerWindow(.{ .context = &self.probe, .owns = WindowProbe.owns, .activate = WindowProbe.activate, .feedback = WindowProbe.feedback, .owner_name = WindowProbe.name });
        self.view = try Presenter.mount(cx, self.scope, &self.notice, self.window);
    }
    fn deinit(self: *Rig) void {
        self.scope.dispose();
        self.notice.coordinator.deinit();
        self.notice.activity.deinit();
        self.notice.actions.deinit(a);
        self.notice.windows.deinit(a);
        self.notice.ai_origins.deinit(a);
        self.cx.deinit();
    }
    fn frameWith(self: *Rig, now: u64, placement: presenter_mod.Placement) !void {
        self.cx.frame_time_ms = @floatFromInt(now);
        try self.view.update(now, true, null, placement);
        self.cx.layout();
        // World rects (the stack hit-tests the pointer against them) come from a render pass.
        _ = self.cx.render();
        // Both native stacks run their frame hook (cards top-right, toasts bottom-center).
        for ([_][]const u8{ "notifications.viewport", "notifications.toasts" }) |id| {
            if (find(self.cx, id)) |container| ui.widgets.Notifier.frameHookForTest()(container);
        }
        self.cx.layout();
    }
    fn frame(self: *Rig, now: u64) !void {
        try self.frameWith(now, .{ .content = content_rect });
    }
    /// Frames from `from` to `to` (inclusive) every 16 ms.
    fn run(self: *Rig, from: u64, to: u64) !void {
        var t = from;
        while (t < to) : (t += 16) try self.frame(t);
        try self.frame(to);
    }
    fn click(self: *Rig, node: *ui.Node) void {
        const r = node.globalRect();
        self.cx.handleMouseMove(r.x + r.w / 2, r.y + r.h / 2);
        self.cx.handleMouseDown(r.x + r.w / 2, r.y + r.h / 2, .{});
        self.cx.handleMouseUp(r.x + r.w / 2, r.y + r.h / 2);
    }
    fn away(self: *Rig) void {
        self.cx.handleMouseMove(5, 470);
    }
    fn event(self: *Rig, operation: u64, revision: u64) host.notifications.NotificationEvent {
        return .{ .definition_id = "host.feedback", .owner = .{ .window_id = @backingInt(self.window), .content = .{ .session = .{ .session_id = @fromBackingInt(1), .generation = 1 } } }, .operation_id = operation, .event_revision = revision, .phase = .failed, .title = "需要处理", .owner_name = "prod-web-01", .detail = "保留完整详情", .attention = .{ .kind = .task_blocked, .requires_action = true, .time_sensitive = true } };
    }
};

test "notification banner shows the admitted fact natively with source, collapsed details, actions and test ids" {
    var rig: Rig = undefined;
    try rig.init("00:00-00:00");
    defer rig.deinit();
    var event = rig.event(1, 1);
    event.actions = &.{ .{ .kind = .locate_owner, .label = "查看来源" }, .{ .kind = .view_result, .label = "查看结果" }, .{ .kind = .view_result, .label = "重试" } };
    const fact = (try rig.notice.coordinator.publishNotification(event, .{ .monotonic_ms = 1, .local_minute = 0 })).fact_id;
    try rig.run(1, 700);
    try std.testing.expectEqual(@as(?u64, fact), rig.view.vm.shownFact());
    const card = find(rig.cx, "notifications.toast.0") orelse return error.TestUnexpectedResult;
    const rect = card.globalRect();
    // Docked top-right under the tab strip, inside the window.
    try std.testing.expect(rect.x + rect.w <= 860 and rect.x > 860 / 2);
    try std.testing.expect(rect.y >= 40 and rect.y + rect.h <= 480);
    try std.testing.expectEqualStrings("需要处理", textOf(find(rig.cx, "notifications.title").?));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, textOf(find(rig.cx, "notifications.metadata").?), "prod-web-01"));
    try std.testing.expectEqualStrings("保留完整详情", textOf(find(rig.cx, "notifications.detail").?));
    try std.testing.expect(find(rig.cx, "notifications.expand") != null);
    try std.testing.expectEqual(@as(usize, 3), countIn(card, "notifications.action"));
    try std.testing.expect(find(rig.cx, "notifications.dismiss.0") != null);
    // Collapsed (not a failure): the detail frame is hidden until expanded.
    var frame = find(rig.cx, "notifications.detail").?;
    while (frame.parent) |p| : (frame = p) if (frame.style.display == .none) break;
    try std.testing.expect(frame.style.display == .none);
    // The coordinator's own timer holds while the native stack counts down.
    try std.testing.expect(rig.notice.coordinator.recordFor(fact).?.paused);
}

test "notification banner action dispatches to the original fact once; a morph cancels the old press" {
    for ([_]bool{ false, true }) |replace_fact| {
        var rig: Rig = undefined;
        try rig.init("00:00-00:00");
        defer rig.deinit();
        try rig.notice.registerDefinition(.{ .id = "audit.press", .category = .connection_change, .default_channels = .{ .system = false, .attention = true } });
        var first = rig.event(1, 1);
        first.definition_id = "audit.press";
        first.severity = .failure;
        first.attention = .{ .kind = .connection_stopped, .requires_action = true, .time_sensitive = true };
        first.actions = &.{.{ .kind = .locate_owner, .label = "查看来源" }};
        _ = try rig.notice.coordinator.publishNotification(first, .{ .monotonic_ms = 1, .local_minute = 0 });
        try rig.run(1, 700);
        const before = find(rig.cx, "notifications.action").?;
        const r = before.globalRect();
        rig.cx.handleMouseMove(r.x + r.w / 2, r.y + r.h / 2);
        rig.cx.handleMouseDown(r.x + r.w / 2, r.y + r.h / 2, .{});
        var next = first;
        if (replace_fact) {
            next.owner.content.session.session_id = @fromBackingInt(2);
            next.operation_id = 2;
        } else next.event_revision = 2;
        const publication = try rig.notice.coordinator.publishNotification(next, .{ .monotonic_ms = 2, .local_minute = 0 });
        try rig.run(716, 1100);
        rig.cx.handleMouseUp(r.x + r.w / 2, r.y + r.h / 2);
        try rig.run(1116, 1200);
        try std.testing.expectEqual(@as(usize, 0), rig.probe.calls);
        try std.testing.expectEqual(host.notifications.Presentation.visible, rig.notice.coordinator.recordFor(publication.fact_id).?.presentation);
        rig.click(find(rig.cx, "notifications.action").?);
        try rig.run(1216, 1300);
        try std.testing.expectEqual(@as(usize, 1), rig.probe.calls);
        try std.testing.expectEqual(@as(u64, if (replace_fact) 2 else 1), rig.probe.owner);
        try std.testing.expectEqual(host.notifications.Presentation.hidden, rig.notice.coordinator.recordFor(publication.fact_id).?.presentation);
    }
}

test "notification native countdown expires the fact while retaining it; hover holds it" {
    var rig: Rig = undefined;
    try rig.init("00:00-00:00");
    defer rig.deinit();
    var risk = rig.event(1, 1);
    risk.severity = .failure;
    risk.attention = .{ .kind = .application_risk, .requires_action = true, .time_sensitive = true };
    const fact = (try rig.notice.coordinator.publishNotification(risk, .{ .monotonic_ms = 1, .local_minute = 0 })).fact_id;
    try rig.run(1, 400);
    // Hover holds the life bar: long past four seconds it is still shown.
    const card = find(rig.cx, "notifications.toast.0").?;
    const r = card.globalRect();
    rig.cx.handleMouseMove(r.x + 30, r.y + 20);
    try rig.run(416, 9000);
    try std.testing.expectEqual(@as(?u64, fact), rig.view.vm.shownFact());
    // Leaving resumes; four seconds (no actions) later the fact expires but stays pending.
    rig.away();
    try rig.run(9016, 13_600);
    try std.testing.expectEqual(@as(?u64, null), rig.view.vm.shownFact());
    const record = rig.notice.coordinator.recordFor(fact).?;
    try std.testing.expectEqual(host.notifications.Presentation.expired, record.presentation);
    try std.testing.expect(record.pending());
}

test "notification close control hides the banner without deleting the pending record" {
    var rig: Rig = undefined;
    try rig.init("00:00-00:00");
    defer rig.deinit();
    var event = rig.event(1, 1);
    event.severity = .failure;
    event.title = "无法保存记录";
    event.detail = "磁盘已满";
    event.attention = .{ .kind = .application_risk, .requires_action = true, .time_sensitive = true };
    const published = try rig.notice.coordinator.publishNotification(event, .{ .monotonic_ms = 1, .local_minute = 0 });
    try rig.run(1, 700);
    // The close button shows on hover (native).
    const card = find(rig.cx, "notifications.toast.0").?.globalRect();
    rig.cx.handleMouseMove(card.x + 40, card.y + 20);
    try rig.run(716, 1000);
    rig.click(find(rig.cx, "notifications.dismiss.0").?);
    try rig.run(1016, 1100);
    try std.testing.expectEqual(@as(?u64, null), rig.view.vm.shownFact());
    const record = rig.notice.coordinator.recordFor(published.fact_id).?;
    try std.testing.expectEqual(host.notifications.Presentation.hidden, record.presentation);
    try std.testing.expect(record.pending());
    try std.testing.expectEqualStrings("磁盘已满", record.event.detail);
    try std.testing.expectEqual(@as(usize, 1), rig.notice.coordinator.historyCount(true));
}

test "notification revision morphs the same card in place and keeps expanded details" {
    var rig: Rig = undefined;
    try rig.init("00:00-00:00");
    defer rig.deinit();
    var event = rig.event(1, 1);
    event.attention.incident_id = 11;
    event.actions = &.{.{ .kind = .view_result, .label = "View" }};
    const id = (try rig.notice.coordinator.publishNotification(event, .{ .monotonic_ms = 1, .local_minute = 0 })).fact_id;
    try rig.run(1, 700);
    const card = find(rig.cx, "notifications.toast.0").?;
    rig.click(find(rig.cx, "notifications.expand").?);
    try rig.run(716, 900);
    const remaining = rig.notice.coordinator.recordFor(id).?.remaining_ms;
    event.event_revision = 2;
    event.attention.incident_id = 22;
    event.detail = "更新后的详情";
    _ = try rig.notice.coordinator.publishNotification(event, .{ .monotonic_ms = 1100, .local_minute = 0 });
    try rig.run(916, 1400);
    try std.testing.expect(card == find(rig.cx, "notifications.toast.0").?);
    var frame = find(rig.cx, "notifications.detail").?;
    try std.testing.expectEqualStrings("更新后的详情", textOf(frame));
    while (frame.parent) |p| : (frame = p) if (frame.style.display == .none) break;
    try std.testing.expect(frame.style.display != .none);
    try std.testing.expectEqual(remaining, rig.notice.coordinator.recordFor(id).?.remaining_ms);
    try std.testing.expect(rig.notice.coordinator.recordFor(id).?.paused);
}

test "notification covered corner suppresses ordinary facts; an operation failure stays above with its cause expanded" {
    var rig: Rig = undefined;
    try rig.init("00:00-00:00");
    defer rig.deinit();
    const modal: presenter_mod.Placement = .{ .content = content_rect, .avoid = &.{.{ .x = 16, .y = 16, .w = 828, .h = 448 }} };
    _ = try rig.notice.coordinator.publishNotification(rig.event(1, 1), .{ .monotonic_ms = 1, .local_minute = 1 });
    var t: u64 = 1;
    while (t < 700) : (t += 16) try rig.frameWith(t, modal);
    try std.testing.expect(rig.view.vm.cardsSuppressed());
    try std.testing.expect(!find(rig.cx, "notifications.toast.0").?.frame_state.state_bits.flags.hit_test_visible);
    rig.notice.coordinator.dismissNotification(rig.view.vm.shownFact().?);
    _ = try rig.notice.coordinator.publishNotification(.{ .definition_id = "host.operation_error", .owner = .{ .window_id = @backingInt(rig.window), .window_only = true }, .operation_id = 2, .event_revision = 1, .phase = .failed, .severity = .failure, .title = "无法保存设置", .detail = "SCNetX · API Key：请填写 API Key，或停用此服务提供方。", .attention = .{ .kind = .operation_failed, .requires_action = true, .time_sensitive = true } }, .{ .monotonic_ms = 700, .local_minute = 1 });
    while (t < 1500) : (t += 16) try rig.frameWith(t, modal);
    try std.testing.expect(!rig.view.vm.cardsSuppressed());
    var frame = find(rig.cx, "notifications.detail").?;
    try std.testing.expect(frame.globalRect().h > 18);
    while (frame.parent) |p| : (frame = p) if (frame.style.display == .none) break;
    try std.testing.expect(frame.style.display != .none);
}

test "notification presenter bounds the longest admitted content inside the minimum window" {
    var rig: Rig = undefined;
    try rig.init("00:00-00:00");
    defer rig.deinit();
    try rig.notice.coordinator.registerDefinition(.{ .id = "audit.feedback", .category = .operation_result, .default_channels = .{ .system = false, .attention = false } });
    var detail = cycled("long detail content with words and spaces ", 4096);
    @memset(detail[0..512], 'x'); // A long unbroken path/token must also wrap.
    const label = cycled("long action label with spaces ", 128);
    var event = rig.event(1, 1);
    event.definition_id = "audit.feedback";
    event.severity = .failure;
    event.title = &cycled("Longest admitted title ", 256);
    event.detail = &detail;
    event.actions = &.{ .{ .kind = .view_result, .label = &label }, .{ .kind = .view_result, .label = &label }, .{ .kind = .view_result, .label = &label } };
    _ = try rig.notice.coordinator.publishNotification(event, .{ .monotonic_ms = 1, .local_minute = 0 });
    try rig.run(1, 900);
    const card = find(rig.cx, "notifications.toast.0").?.globalRect();
    try std.testing.expect(card.y + card.h <= 480 + 0.5);
    try std.testing.expect(card.x >= 0 and card.x + card.w <= 860);
    const detail_node = find(rig.cx, "notifications.detail").?;
    var frame = detail_node;
    while (frame.parent) |p| : (frame = p) if (std.mem.eql(u8, frame.meta.ownership.meta.component_name orelse "", "Notification.detail")) break;
    try std.testing.expect(frame.globalRect().h <= 160 + 0.5);
    try std.testing.expect(detail_node.globalRect().h > frame.globalRect().h);
    var actions: [8]*ui.Node = undefined;
    var n: usize = 0;
    collect(find(rig.cx, "notifications.toast.0").?, "notifications.action", &actions, &n);
    try std.testing.expectEqual(@as(usize, 3), n);
    for (actions[0..n]) |b| {
        const r = b.globalRect();
        try std.testing.expect(r.x >= card.x and r.x + r.w <= card.x + card.w + 0.5);
    }
}

fn collect(root: *ui.Node, id: []const u8, out: []*ui.Node, n: *usize) void {
    if (root.meta.ownership.meta.test_id) |value| if (std.mem.eql(u8, value, id) and n.* < out.len) {
        out[n.*] = root;
        n.* += 1;
    };
    for (root.children.items) |child| collect(child, id, out, n);
}

fn cycled(comptime text: []const u8, comptime length: usize) [length]u8 {
    var result: [length]u8 = undefined;
    for (&result, 0..) |*byte, index| byte.* = text[index % text.len];
    return result;
}

test "notification local receipt is a native success hint in the window's bottom-center toast stack" {
    var rig: Rig = undefined;
    try rig.init("00:00-00:00");
    defer rig.deinit();
    try std.testing.expectError(error.InvalidAcknowledgmentAnchor, presenter_mod.acknowledgeAt(rig.cx, .{ .x = 0, .y = 0, .w = 0, .h = 0 }, "路径已复制"));
    try presenter_mod.acknowledgeAt(rig.cx, .{ .x = 10, .y = 10, .w = 40, .h = 20 }, "路径已复制");
    try rig.run(1, 400);
    const receipt = find(rig.cx, "notifications.local") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("路径已复制", textOf(receipt));
    // It lives in the toast stack, not the card stack, and docks bottom-center (zenit's default).
    try std.testing.expect(isWithin(receipt, find(rig.cx, "notifications.toasts").?));
    try std.testing.expect(!isWithin(receipt, find(rig.cx, "notifications.viewport").?));
    const r = receipt.globalRect();
    try std.testing.expect(@abs((r.x + r.w / 2) - content_rect.w / 2) < 1);
    try std.testing.expect(r.y > content_rect.h / 2);
    // Two seconds (native plain hint) later it is gone.
    try rig.run(416, 3000);
    try std.testing.expect(find(rig.cx, "notifications.local") == null);
}

fn isWithin(node: *ui.Node, ancestor: *ui.Node) bool {
    var at: ?*ui.Node = node;
    while (at) |value| : (at = value.parent) if (value == ancestor) return true;
    return false;
}

test "notification window mounts two native stacks: cards dock top-right, toasts bottom-center" {
    var rig: Rig = undefined;
    try rig.init("00:00-00:00");
    defer rig.deinit();
    const cards = find(rig.cx, "notifications.viewport") orelse return error.TestUnexpectedResult;
    const toasts = find(rig.cx, "notifications.toasts") orelse return error.TestUnexpectedResult;
    try std.testing.expect(cards != toasts);
    // Both are portaled over the window; their overlay layers are toast-kind (the window host
    // skips those when it collects obstacles: the stacks' full-window containers never cover
    // their own docking areas).
    var toast_layers: usize = 0;
    for (rig.cx.overlay_stack.layers.items) |maybe| if (maybe) |layer| {
        if (layer.content_node == cards or layer.content_node == toasts) {
            try std.testing.expect(layer.config.kind == .toast);
            toast_layers += 1;
        }
    };
    try std.testing.expectEqual(@as(usize, 2), toast_layers);
    _ = try rig.notice.coordinator.publishNotification(rig.event(1, 1), .{ .monotonic_ms = 1, .local_minute = 1 });
    try presenter_mod.acknowledgeAt(rig.cx, .{ .x = 10, .y = 10, .w = 40, .h = 20 }, "已复制选中内容");
    try rig.run(1, 700);
    const banner = find(rig.cx, "notifications.toast.0") orelse return error.TestUnexpectedResult;
    const receipt = find(rig.cx, "notifications.local") orelse return error.TestUnexpectedResult;
    try std.testing.expect(isWithin(banner, cards) and !isWithin(banner, toasts));
    try std.testing.expect(isWithin(receipt, toasts) and !isWithin(receipt, cards));
    const b = banner.globalRect();
    try std.testing.expect(b.x + b.w > content_rect.w - 30 and b.y < content_rect.h / 2);
    const r = receipt.globalRect();
    try std.testing.expect(@abs((r.x + r.w / 2) - content_rect.w / 2) < 1 and r.y > content_rect.h / 2);
    // Separate stacks: neither collapses into the other's "N more" pill.
    try std.testing.expectEqual(@as(usize, 1), countIn(cards, "notifications.toast.0"));
    try std.testing.expectEqual(@as(usize, 0), countIn(cards, "notifications.local"));
}

test "notification toast stack stays on top: a covered bottom neither hides nor pauses toasts; a covered corner hides cards only" {
    var rig: Rig = undefined;
    try rig.init("00:00-00:00");
    defer rig.deinit();
    const corner: presenter_mod.Placement = .{ .content = content_rect, .avoid = &.{.{ .x = 480, .y = 50, .w = 370, .h = 220 }} };
    // A transfer manager / context menu over the bottom center, and a full-window modal.
    const bottom: presenter_mod.Placement = .{ .content = content_rect, .avoid = &.{.{ .x = 200, .y = 360, .w = 460, .h = 110 }} };
    const modal: presenter_mod.Placement = .{ .content = content_rect, .avoid = &.{.{ .x = 16, .y = 16, .w = 828, .h = 448 }} };
    _ = try rig.notice.coordinator.publishNotification(rig.event(1, 1), .{ .monotonic_ms = 1, .local_minute = 1 });
    try presenter_mod.acknowledgeAt(rig.cx, .{ .x = 10, .y = 10, .w = 40, .h = 20 }, "路径已复制");
    var t: u64 = 1;
    while (t < 400) : (t += 16) try rig.frameWith(t, corner);
    try std.testing.expect(rig.view.vm.cardsSuppressed());
    try std.testing.expect(!find(rig.cx, "notifications.toast.0").?.frame_state.state_bits.flags.hit_test_visible);
    // The toast keeps its own clock while the card stack is hidden: it expires on time.
    while (t < 3000) : (t += 16) try rig.frameWith(t, corner);
    try std.testing.expect(find(rig.cx, "notifications.local") == null);
    try std.testing.expect(find(rig.cx, "notifications.toast.0") != null);
    // Under a bottom panel and under a modal the toast stays visible and expires on time
    // (native plain hint: two seconds).
    for ([_]presenter_mod.Placement{ bottom, modal }) |cover| {
        try presenter_mod.acknowledgeAt(rig.cx, .{ .x = 10, .y = 10, .w = 40, .h = 20 }, "路径已复制");
        const shown_at = t;
        while (t < shown_at + 600) : (t += 16) try rig.frameWith(t, cover);
        const receipt = find(rig.cx, "notifications.local") orelse return error.TestUnexpectedResult;
        try std.testing.expect(receipt.frame_state.state_bits.flags.hit_test_visible);
        try std.testing.expect(!find(rig.cx, "notifications.toasts").?.isPaintSkipped());
        while (t < shown_at + 2600) : (t += 16) try rig.frameWith(t, cover);
        try std.testing.expect(find(rig.cx, "notifications.local") == null);
    }
}

test "notification toast stack is layered above host popovers and dialogs" {
    var rig: Rig = undefined;
    try rig.init("00:00-00:00");
    defer rig.deinit();
    const portal = try rig.cx.ensurePopoverPortalRoot();
    // A menu / panel (overlay tier) and a modal (dialog tier) opened after the stacks mounted.
    var surfaces: [2]*ui.Node = undefined;
    for (&surfaces, 0..) |*surface, i| {
        const node = try ui.box(rig.cx, .{ .position = .absolute, .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
        try portal.appendChild(a, node);
        const layer = try rig.cx.overlay_stack.push(.{ .kind = if (i == 0) .non_modal else .modal });
        rig.cx.overlay_stack.bindFloatingContent(a, layer, node);
        surface.* = node;
    }
    try presenter_mod.acknowledgeAt(rig.cx, .{ .x = 10, .y = 10, .w = 40, .h = 20 }, "路径已复制");
    try rig.run(1, 300);
    const toasts = find(rig.cx, "notifications.toasts").?;
    try std.testing.expect(toasts.parent == portal);
    for (surfaces) |node| try std.testing.expect(toasts.style.z_index() > node.style.z_index());
}

test "notification plugin feedback without an action is an info toast in the bottom stack; a failure is refused there" {
    var rig: Rig = undefined;
    try rig.init("00:00-00:00");
    defer rig.deinit();
    try rig.view.vm.notice(.info, "已同步 3 个文件");
    try std.testing.expectError(error.NoticeNeedsCard, rig.view.vm.notice(.failure, "同步失败"));
    try rig.run(1, 400);
    const hint = find(rig.cx, "notifications.local") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("已同步 3 个文件", textOf(hint));
    try std.testing.expect(isWithin(hint, find(rig.cx, "notifications.toasts").?));
    try std.testing.expect(find(rig.cx, "notifications.toast.0") == null);
    try std.testing.expectEqual(@as(usize, 0), rig.notice.coordinator.historyCount(false));
}

test "notification sources appear once below event titles for every built-in kind and plugin phase" {
    const Probe = struct {
        fn owns(_: *anyopaque, _: host.notifications.Target) bool {
            return true;
        }
        fn activate(_: *anyopaque, _: host.notifications.Target) bool {
            return true;
        }
        fn feedback(_: *anyopaque, _: []const u8) void {}
        fn name(_: *anyopaque, _: host.ContentOwner) []const u8 {
            return "prod-web-01";
        }
    };
    const cx = try ui.Cx.init(a, std.testing.io);
    defer cx.deinit();
    cx.setViewport(860, 480);
    cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    const scope = try ui.Scope.init(a, null, cx.owner);
    var notice: host.Host = .{ .allocator = a, .activity = .{ .allocator = a }, .driver = undefined, .coordinator = try host.notifications.Coordinator.init(a, .{ .quiet_hours = "00:00-00:00" }, .{}) };
    defer {
        scope.dispose();
        notice.coordinator.deinit();
        notice.activity.deinit();
    }
    defer notice.windows.deinit(a);
    var probe: u8 = 0;
    const window = try notice.registerWindow(.{ .context = &probe, .owns = Probe.owns, .activate = Probe.activate, .feedback = Probe.feedback, .owner_name = Probe.name });
    try notice.registerDefinition(.{ .id = "audit.plugin", .category = .connection_change });
    const owner: host.ContentOwner = .{ .session = .{ .session_id = @fromBackingInt(1) } };
    const presenter = try Presenter.mount(cx, scope, &notice, window);
    const trigger = try ui.widgets.Button(.{ .label = "通知" }).mount(scope, cx);
    try cx.root.?.appendChild(a, trigger);
    const history = try @import("../view/notification_history.zig").View.mount(cx, scope, &notice, trigger);
    const Case = enum { transfer_done, transfer_failed, transfer_cancelled, disconnected, recovered, reconnect_failed, ai_ready, ai_failed, ai_unverified, ai_cancelled, feedback_failure, feedback_warning, command_error, plugin_accepted, plugin_verifying, plugin_succeeded, plugin_failed, plugin_cancelled, plugin_unknown };
    for (std.enums.values(Case), 0..) |case, index| {
        for (notice.coordinator.notification_records.items) |*prior| prior.event.attention.resolved = true;
        notice.coordinator.clearHistory();
        const operation: u64 = @intCast(index + 1);
        switch (case) {
            .transfer_done, .transfer_failed, .transfer_cancelled => try notice.publishTransfer(owner, operation, 1, .{ .result = if (case == .transfer_done) .succeeded else if (case == .transfer_failed) .failed else .cancelled, .resources_released = true, .notify_complete = true, .details = .{ .object = "backup.tar.gz" } }),
            .disconnected, .recovered, .reconnect_failed => try notice.publishReconnectDetails(owner, operation, 1, if (case == .disconnected) .disconnected else if (case == .recovered) .recovered else .failed, .{ .object = "prod-web-01" }),
            .ai_ready, .ai_failed, .ai_unverified, .ai_cancelled => try notice.publishAi(owner, operation, 1, .{ .result = if (case == .ai_ready) .succeeded else if (case == .ai_failed) .failed else if (case == .ai_unverified) .unverified else .cancelled, .resources_released = true, .final_answer = true }),
            .feedback_failure, .feedback_warning => try notice.publishFeedbackSeverity(window, owner, "连接失败: HandshakeFailed", if (case == .feedback_failure) .failure else .warning),
            .command_error => _ = try notice.publish(.{ .definition_id = "host.command_error", .owner = .{ .window_id = @backingInt(window), .content = owner }, .operation_id = operation, .event_revision = 1, .phase = .failed, .severity = .failure, .title = "命令执行失败", .detail = "command not found" }),
            else => _ = try notice.publish(.{ .definition_id = "audit.plugin", .owner = .{ .window_id = @backingInt(window), .content = owner }, .operation_id = operation, .event_revision = 1, .phase = switch (case) {
                .plugin_accepted => .accepted,
                .plugin_verifying => .verifying,
                .plugin_succeeded => .succeeded,
                .plugin_failed => .failed,
                .plugin_cancelled => .cancelled,
                else => .outcome_unknown,
            }, .title = "插件连接状态", .object_name = "prod-web-01" }),
        }
        if (case == .feedback_failure or case == .feedback_warning or case == .transfer_failed) {
            try std.testing.expectEqual(@as(usize, 1), notice.coordinator.historyCount(false));
            continue;
        }
        if (case != .reconnect_failed) {
            try std.testing.expectEqual(@as(usize, 0), notice.coordinator.historyCount(false));
            try std.testing.expectEqual(@as(usize, 0), notice.coordinator.presentation_count);
            continue;
        }
        const record = notice.coordinator.notification_records.items[0];
        try std.testing.expectEqualStrings("prod-web-01", record.event.owner_name);
        try std.testing.expect(std.mem.indexOf(u8, record.event.title, record.event.owner_name) == null);
        const now = record.published_ms;
        for (0..8) |_| {
            // The active owner also needs its source line now that titles
            // contain only the event, and equal object names must not repeat.
            try presenter.update(now, true, owner, .{ .content = .{ .x = 0, .y = 0, .w = 860, .h = 480 } });
            cx.layout();
        }
        if (case != .command_error) {
            try std.testing.expectEqualStrings(record.event.title, find(cx, "notifications.title").?.getText().?.content);
            const source = find(cx, "notifications.metadata").?;
            try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, source.getText().?.content, "prod-web-01"));
        }
        history.open.set(true);
        for (0..8) |_| {
            cx.layout();
            _ = cx.render();
        }
        try std.testing.expectEqualStrings(record.event.title, find(cx, "notifications.history.title").?.getText().?.content);
        try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, find(cx, "notifications.history.summary").?.getText().?.content, "prod-web-01"));
        history.open.set(false);
    }
}

test "notification host retains structured details and dispatches built-in actions to original result kind" {
    const Probe = struct {
        kind: ?host.notifications.Kind = null,
        fn owns(_: *anyopaque, _: host.notifications.Target) bool {
            return true;
        }
        fn activate(raw: *anyopaque, target: host.notifications.Target) bool {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.kind = target.kind;
            return true;
        }
        fn feedback(_: *anyopaque, _: []const u8) void {}
        fn name(_: *anyopaque, _: host.ContentOwner) []const u8 {
            return "prod-web-01";
        }
    };
    var probe: Probe = .{};
    var notice: host.Host = .{ .allocator = a, .activity = .{ .allocator = a }, .driver = undefined, .coordinator = try host.notifications.Coordinator.init(a, .{ .quiet_hours = "00:00-00:00" }, .{}) };
    defer {
        notice.coordinator.deinit();
        notice.activity.deinit();
    }
    defer notice.windows.deinit(a);
    defer notice.ai_origins.deinit(a);
    const window = try notice.registerWindow(.{ .context = &probe, .owns = Probe.owns, .activate = Probe.activate, .feedback = Probe.feedback, .owner_name = Probe.name });
    const owner: host.ContentOwner = .{ .session = .{ .session_id = @fromBackingInt(1) } };
    var object = [_]u8{ 'a', '.', 'z', 'i', 'p' };
    try notice.publishTransfer(owner, 1, 1, .{ .result = .failed, .resources_released = true, .notify_complete = false, .details = .{ .object = &object, .detail = "没有文件访问权限" } });
    object[0] = 'b';
    try notice.publishReconnectDetails(owner, 2, 1, .disconnected, .{ .object = "prod-web-01", .detail = "连接超时" });
    const ai_operation = try notice.reserveAiOperation(window);
    try notice.publishAi(owner, ai_operation, 1, .{ .result = .unverified, .resources_released = true });
    try notice.publishTransfer(owner, 4, 1, .{ .result = .cancelled, .resources_released = true, .notify_complete = false });
    const facts = notice.coordinator.notification_records.items;
    try std.testing.expectEqualStrings("a.zip", facts[0].event.object_name);
    try std.testing.expectEqualStrings("没有文件访问权限", facts[0].event.detail);
    try std.testing.expectEqualStrings("prod-web-01", facts[0].event.owner_name);
    try std.testing.expectEqualStrings("文件传输失败", facts[0].event.title);
    try std.testing.expectEqualStrings("连接超时", facts[2].event.detail);
    try std.testing.expectEqual(.warning, facts[3].event.severity);
    // Explicit cancellation is silent: no application fact, system delivery
    // record, or queued toast is added by publishTransfer.
    try std.testing.expectEqual(@as(usize, 4), facts.len);
    try std.testing.expectEqual(@as(usize, 3), notice.coordinator.records.items.len);
    try std.testing.expectEqual(@as(usize, 1), notice.coordinator.presentation_count);
    for (facts) |fact| try std.testing.expect(fact.event.operation_id != 4);
    for ([_]host.notifications.Kind{ .transfer_done, .reconnect, .ai_ready }, 0..) |kind, index| {
        try notice.dispatchAction(facts[if (index == 0) 0 else index + 1].fact_id, 0);
        try std.testing.expectEqual(kind, probe.kind.?);
    }
}

test "notification history evicts oldest facts without rejecting new ones and retains dismissed content" {
    var coordinator = try host.notifications.Coordinator.init(a, .{ .quiet_hours = "00:00-00:00" }, .{});
    defer coordinator.deinit();
    const owner: host.ContentOwner = .{ .session = .{ .session_id = @fromBackingInt(1) } };
    var first: u64 = 0;
    for (0..105) |index| {
        const published = try coordinator.publishNotification(.{ .attention = .{ .kind = .task_blocked, .requires_action = true, .time_sensitive = true }, .definition_id = "host.feedback", .owner = .{ .window_id = 1, .content = owner }, .operation_id = index + 1, .event_revision = 1, .phase = .succeeded, .title = "Retained" }, .{ .monotonic_ms = index, .local_minute = 0 });
        if (index == 0) first = published.fact_id;
        coordinator.dismissNotification(published.fact_id);
        coordinator.notification_records.items[coordinator.notification_records.items.len - 1].event.attention.resolved = true;
    }
    try std.testing.expectEqual(@as(usize, 100), coordinator.notification_records.items.len);
    try std.testing.expect(coordinator.recordFor(first) == null);
    try std.testing.expectEqual(@as(u64, 6), coordinator.notification_records.items[0].event.operation_id);
    try std.testing.expectEqual(@as(usize, 100), coordinator.unreadHistoryCount());
    coordinator.readHistory();
    try std.testing.expectEqual(@as(usize, 0), coordinator.unreadHistoryCount());
    coordinator.clearHistory();
    try std.testing.expectEqual(@as(usize, 0), coordinator.notification_records.items.len);
    try std.testing.expectEqual(@as(usize, 0), coordinator.presentation_count);
}

test "both native notification stacks stay transparent and click-through in the main window" {
    // Regression (blank main window): a window-level policy once painted every overlay layer's
    // content node and made it opaque to input. A native stack's layer content is a transparent
    // full-window container, so the window turned one solid colour and stopped taking clicks.
    // No such policy exists any more; the stacks are zenit's own.
    var rig: Rig = undefined;
    try rig.init("00:00-00:00");
    defer rig.deinit();
    const content = try ui.box(rig.cx, .{ .width = .fill(), .height = .fill() }, .{});
    content.meta.ownership.meta.test_id = "window.content";
    // Interactive like the window's real content (sidebar, tabs, terminal).
    content.behavior.events.on_event = struct {
        fn on(_: ui.events.Event, _: ?*anyopaque) ui.events.EventResult {
            return .ignored;
        }
    }.on;
    try rig.cx.root.?.insertChildBefore(a, content, rig.cx.root.?.children.items[0]);
    const fact = (try rig.notice.coordinator.publishNotification(rig.event(1, 1), .{ .monotonic_ms = 1, .local_minute = 0 })).fact_id;
    try rig.run(1, 700);
    try std.testing.expectEqual(@as(?u64, fact), rig.view.vm.shownFact());
    var stacks: usize = 0;
    for (rig.cx.overlay_stack.layers.items) |slot| if (slot) |layer| if (layer.config.kind == .toast) {
        const container = layer.content_node.?;
        stacks += 1;
        try std.testing.expectEqual(ui.Color.TRANSPARENT, container.getBackground());
        try std.testing.expect(container.style.glass_params() == null);
        try std.testing.expectEqual(@as(usize, 0), container.style.shadowSlice().len);
        try std.testing.expect(container.style.hit_behavior() == .children_only);
    };
    try std.testing.expectEqual(@as(usize, 2), stacks);
    // Away from the card, the window content takes the pointer; the card still takes its own.
    try std.testing.expectEqual(content, rig.cx.hitTest(200, 300).?);
    const card = find(rig.cx, "notifications.toast.0").?;
    const r = card.globalRect();
    const hit = rig.cx.hitTest(r.x + r.w / 2, r.y + r.h / 2).?;
    try std.testing.expect(hit == card or hit.isDescendantOf(card));
}
