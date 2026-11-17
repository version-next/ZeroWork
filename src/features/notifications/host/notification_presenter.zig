//! 每个应用窗口两个 zenit 原生通知栈（`toast_stack.yix` 的两个 `<W.NotificationHost>`：右上角卡片栈、中下方
//! 轻提示栈）的宿主胶水：每帧把协调器给本窗口的提醒投影进 view-model（`model/view_model.zig`）的卡片通道（协调器
//! 只在窗口里呈现待处理或操作失败的事实，按 `laneFor` 都是卡片），卡片栈的回报（关闭、到期、动作）写回协调器。
//! 本地回执（`acknowledgeAt`）与插件的无动作反馈进轻提示栈。卡片、文字提示、倒计时（原生生命条）、悬停 / 焦点
//! 暂停、详情展开、关闭按钮都是原生的，这里不画任何节点、不写任何样式。几何只用来判断卡片栈的停靠区（右上角）是否被宿主自己的浮层盖住（盖住时卡片栈
//! 整体隐藏、计时保持；操作失败例外）。轻提示栈永远在最上层，不做遮挡判断。
const std = @import("std");
const ui = @import("ui");
const host = @import("../../../host/notification_host.zig");
const notifications = host.notifications;
const m = @import("../model/view_model.zig");
const card_model = @import("../model/notification_card.zig");
const layout = @import("../model/notification_placement.zig");
const stack = @import("../view/_toast_stack.yix.zig");
const confirm = @import("../../../shared/ui/confirm/confirm.zig");

pub const Placement = struct {
    /// App bounds (the V3 #app), independent of sidebar/content layout.
    content: ui.ComputedRect,
    /// Already open popovers and captured-pointer areas in window coordinates.
    avoid: []const ui.ComputedRect = &.{},
};

/// 每个窗口（Cx）至多一个；本地回执与命令失败提示经它找到本窗口的通知栈。
const Registry = struct { value: ?*Presenter = null };
const registry_key = std.hash.Wyhash.hash(0, "ZeroWork.windowNotifications");

/// 卡片栈停靠的提醒角（右上，宽 392 的卡片列；高度取一张带详情卡片的常见高度），用于遮挡判断。
const corner_width: f32 = 392 + 22;
const corner_height: f32 = 180;

pub const Presenter = struct {
    cx: *ui.Cx,
    host: *host.Host,
    window_id: host.WindowId,
    vm: m.ViewModel,
    root: *ui.Node = undefined,

    pub fn mount(cx: *ui.Cx, scope: *ui.Scope, notification_host: *host.Host, window_id: host.WindowId) !*Presenter {
        const slot = try cx.state(Registry, registry_key, .{});
        if (slot.value != null) return error.NotificationPresenterAlreadyMounted;
        const self = try scope.createState(Presenter, .{ .cx = cx, .host = notification_host, .window_id = window_id, .vm = m.ViewModel.init(cx.allocator, .{}) });
        self.vm.ports = .{ .context = self, .cards = .{ .banner = banner }, .toasts = .{ .undo = undoSettled } };
        try scope.onCleanup(Presenter, self, cleanup);
        try self.vm.attach(scope);
        // The window portal must exist before the stack mounts: the native stack portals itself
        // over the window only when it finds one (otherwise it stays inside the template's box).
        const portal = try cx.ensurePopoverPortalRoot();
        self.root = try ui.view.render(scope, cx, stack.ToastStack(.{ .vm = &self.vm }));
        try portal.appendChild(cx.allocator, self.root);
        slot.value = self;
        // 本窗口的撤销 Toast 出口（`shared/ui/confirm` 的 `undoable`）。
        confirm.install(cx, .{ .context = self, .post = postUndo });
        return self;
    }

    fn postUndo(raw: *anyopaque, text: []const u8) anyerror!u64 {
        const self: *Presenter = @ptrCast(@alignCast(raw));
        const id = try self.vm.undoToast(text);
        self.cx.requestRedraw();
        return id;
    }

    fn undoSettled(raw: ?*anyopaque, id: u64, outcome: m.UndoOutcome) void {
        const self: *Presenter = @ptrCast(@alignCast(raw orelse return));
        confirm.settle(self.cx, id, switch (outcome) {
            .revert => .revert,
            .commit => .commit,
        });
    }

    fn cleanup(self: *Presenter) void {
        // 窗口关闭：还没结局的撤销一律提交（登记方销毁前已各自 `flushOwner`）。
        confirm.uninstall(self.cx);
        if (self.cx.state(Registry, registry_key, .{})) |slot| {
            if (slot.value == self) slot.value = null;
        } else |_| {}
        self.vm.deinit();
    }

    /// 本窗口的通知栈（没有挂载时为 null）。
    pub fn forWindow(cx: *ui.Cx) ?*Presenter {
        const slot = cx.state(Registry, registry_key, .{}) catch return null;
        return slot.value;
    }

    /// Call at the existing safe frame boundary. This never changes focus.
    /// Geometry belongs to the window host and is not supplied by plugins.
    pub fn update(self: *Presenter, now_ms: u64, window_focused: bool, active_owner: ?notifications.Owner, placement: Placement) !void {
        if (window_focused) if (active_owner) |owner| {
            _ = self.host.coordinator.markNotificationsRead(owner);
        };
        var records: [3]*const notifications.NotificationRecord = undefined;
        const count = self.host.coordinator.visibleNotifications(@backingInt(self.window_id), now_ms, window_focused, &records);
        if (count == 0 or placement.content.w <= 0) {
            _ = try self.vm.sync(null);
        } else {
            const record = records[0];
            const source = try card_model.summary(self.cx.allocator, record.event, record.owner_ended);
            defer self.cx.allocator.free(source);
            const title = try self.cx.allocator.dupe(u8, record.event.title);
            defer self.cx.allocator.free(title);
            for (title) |*byte| if (byte.* == '\n' or byte.* == '\r' or byte.* == '\t') {
                byte.* = ' ';
            };
            var labels: [m.max_actions][]const u8 = undefined;
            const actions = record.event.actions[0..@min(record.event.actions.len, m.max_actions)];
            for (actions, 0..) |action, i| labels[i] = action.label;
            const failure = record.event.severity == .failure;
            const keep = try self.vm.sync(.{
                .fact_id = record.fact_id,
                .revision = record.event.event_revision,
                .owner_ended = record.owner_ended,
                .tone = switch (record.event.severity) {
                    .info => .info,
                    .success => .success,
                    .warning => .warning,
                    .failure => .failure,
                },
                .title = title,
                .source = source,
                .detail = card_model.extraDetail(record.event),
                .failure = failure,
                .actions = labels[0..actions.len],
                .remaining_ms = record.remaining_ms,
                // Errors caused by the active modal must be visible above that
                // modal, otherwise Save appears to do nothing again.
                .above_overlays = std.mem.eql(u8, record.event.definition_id, "host.operation_error"),
            });
            // The native stack owns the countdown (life bar, hover / focus pause) while it shows
            // the fact; the coordinator's own timer stays paused.
            if (keep) |id| self.host.coordinator.pauseNotification(id, true);
        }
        self.vm.setCardsCovered(cornerCovered(placement));
    }

    /// 是否需要宿主算遮挡几何：协调器有提醒可显示（只有卡片栈看遮挡；轻提示栈永远在最上层，一次性使用提示也在那里）。
    pub fn wantsPlacement(self: *const Presenter) bool {
        return self.host.coordinator.presentation_count != 0;
    }

    fn banner(raw: ?*anyopaque, event: m.BannerEvent) void {
        const self: *Presenter = @ptrCast(@alignCast(raw orelse return));
        const coordinator = &self.host.coordinator;
        switch (event) {
            .dismissed => |fact| coordinator.dismissNotification(fact),
            .expired => |fact| coordinator.expireNotification(fact),
            .action => |a| {
                // A stale or unavailable action leaves the fact queued: the next frame shows it again.
                self.host.dispatchAction(a.fact_id, a.index) catch return;
                coordinator.dismissNotification(a.fact_id);
            },
        }
        self.cx.requestRedraw();
    }
};

/// 卡片栈的提醒角（右上）是否与宿主浮层重叠。
fn cornerCovered(placement: Placement) bool {
    const content = placement.content;
    return overlaps(.{ .x = content.x + @max(0, content.w - corner_width), .y = content.y + layout.top, .w = @min(corner_width, content.w), .h = corner_height }, placement.avoid);
}

fn overlaps(area: layout.Rect, avoid: []const ui.ComputedRect) bool {
    for (avoid) |rect| {
        if (rect.w <= 0 or rect.h <= 0) continue;
        if (!layout.separated(area, .{ .x = rect.x, .y = rect.y, .w = rect.w, .h = rect.h })) return true;
    }
    return false;
}

/// Present a successful local operation (copied, refreshed) as a native text hint in this
/// window's toast stack (bottom center, zenit's standard toast; always on top, never hidden or
/// paused by host overlays). The anchor only validates that the trigger is on screen; the hint
/// docks with the window's other toasts. The caller owns outcome / owner validation and must not
/// also publish globally.
pub fn acknowledgeAt(cx: *ui.Cx, anchor: ui.ComputedRect, message: []const u8) !void {
    if (anchor.w <= 0 or anchor.h <= 0 or message.len == 0) return error.InvalidAcknowledgmentAnchor;
    const presenter = Presenter.forWindow(cx) orelse return error.NoAcknowledgmentWindow;
    try presenter.vm.receipt(message);
    cx.requestRedraw();
}

test "notification presenter corner overlaps only obstacles near the top-right stack" {
    const content: ui.ComputedRect = .{ .x = 0, .y = 0, .w = 1440, .h = 900 };
    try std.testing.expect(!cornerCovered(.{ .content = content }));
    try std.testing.expect(cornerCovered(.{ .content = content, .avoid = &.{.{ .x = 1000, .y = 50, .w = 400, .h = 500 }} }));
    try std.testing.expect(!cornerCovered(.{ .content = content, .avoid = &.{.{ .x = 0, .y = 50, .w = 400, .h = 500 }} }));
    try std.testing.expect(!cornerCovered(.{ .content = content, .avoid = &.{.{ .x = 1000, .y = 600, .w = 400, .h = 200 }} }));
}
