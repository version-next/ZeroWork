//! 原生通知窗口钩子 NotificationWindowHook（P2 自 src/main.zig 原样拆出）。

const std = @import("std");
const applog = @import("../../../platform/applog.zig");
const ui = @import("ui");
const ws = @import("../../workspace/view/workspace.zig");
const NotificationHost = @import("../../../host/notification_host.zig").Host;
const AiHost = @import("../../ai/host/ai_host.zig").AiHost;
const AppNavHost = @import("../../shell/host/nav_host.zig").AppNavHost;
const SettingsHost = @import("../../settings/host/settings_host.zig").SettingsHost;
const TransferHost = @import("../../transfer/host/transfer_host.zig").TransferHost;
const wallClockMsTransfer = @import("../../transfer/host/transfer_host.zig").wallClockMsTransfer;

/// Window presentation borrows task services; providers own native transfers.
/// （执行）。独立模式使用无 shell 的专用 Runtime；共享模式把 SFTP
/// 请求交回原 SSH Worker 的邮箱，原 Worker 是唯一 native IO owner。
pub const NotificationWindowHook = struct {
    host: *NotificationHost,
    cx: *ui.Cx,
    workspace: *ws.Workspace,
    settings: *SettingsHost,
    nav: *AppNavHost,
    transfer: *TransferHost,
    id: @import("../../../host/notification_host.zig").WindowId,
    was_active: bool = false,
    history_revision: u64 = 0,
    history_view: ?*@import("../view/notification_history.zig").View = null,

    pub fn mount(cx: *ui.Cx, scope: *ui.Scope, host: *NotificationHost, workspace: *ws.Workspace, settings: *SettingsHost, nav: *AppNavHost, transfer: *TransferHost) !*NotificationWindowHook {
        const self = try cx.allocator.create(NotificationWindowHook);
        self.* = .{ .host = host, .cx = cx, .workspace = workspace, .settings = settings, .nav = nav, .transfer = transfer, .id = undefined };
        self.id = host.registerWindow(.{ .context = self, .owns = owns, .activate = activate, .activate_ai = activateAi, .prepare_activity = prepareActivity, .tab_presentation = tabPresentation, .feedback = feedback, .operation_action = operationAction, .owner_name = ownerName, .result_presented = resultPresented, .transfer_presented = transferPresented, .maintenance = maintain }) catch |err| {
            cx.allocator.destroy(self);
            return err;
        };
        scope.onCleanup(NotificationWindowHook, self, cleanup) catch |err| {
            host.removeWindow(self.id);
            cx.allocator.destroy(self);
            return err;
        };
        if (nav.notification_anchor) |trigger| {
            self.history_view = try @import("../view/notification_history.zig").View.mount(cx, scope, host, trigger);
        }
        workspace.status_feedback = .{ .context = self, .publish = publishStatus };
        if (nav.application_host) |application| application.file_failure = .{ .context = self, .publish = publishFileFailure };
        try cx.addAfterLayoutHook(self, run);
        return self;
    }
    fn painted(node: *ui.Node) bool {
        if (node.globalRect().w <= 0 or node.globalRect().h <= 0) return false;
        var ancestor: ?*ui.Node = node;
        while (ancestor) |value| : (ancestor = value.parent) {
            if (value.style.display == .none or value.isPaintSkipped()) return false;
        }
        return true;
    }
    fn tabPresentation(raw: *anyopaque, owner: @import("../../../host/identity.zig").ContentOwner) ?@import("../../../host/tab_presentation.zig").Presentation {
        const self: *NotificationWindowHook = @ptrCast(@alignCast(raw));
        if (self.workspace.shutting_down) return null;
        return self.workspace.tabPresentation(owner);
    }
    fn ownerName(raw: *anyopaque, owner: @import("../../../host/identity.zig").ContentOwner) []const u8 {
        const self: *NotificationWindowHook = @ptrCast(@alignCast(raw));
        for (self.workspace.tabs.items) |tab| if (tab.content_owner.eql(owner)) return self.workspace.shownName(tab);
        if (owner == .group) if (self.nav.ai) |ai| if (ai.roster) |roster| {
            for (roster.groups.items) |group| if (group.id == @backingInt(owner.group.id)) return group.name;
        };
        return "原会话已关闭";
    }
    fn resultPresented(raw: *anyopaque, kind: @import("../../../host/notification_coordinator.zig").Kind, owner: @import("../../../host/identity.zig").ContentOwner) bool {
        const self: *NotificationWindowHook = @ptrCast(@alignCast(raw));
        if (!self.cx.window_active) return false;
        if (kind == .ai_ready) {
            const ai = self.nav.ai orelse return false;
            // The request (and its owner) lives on the execution host; the view host only shows it.
            const request_owner = ai.execution().request_content_owner orelse return false;
            const follow = ai.tail_follow orelse return false;
            return request_owner.eql(owner) and ai.controller.model.visible and ai.controller.model.expanded and painted(ai.panel) and
                follow.following and follow.scroll.state.scroll_y >= follow.scroll.state.maxScrollY() - 1 and
                ai.requestDisplayed();
        }
        if (kind == .reconnect) for (self.workspace.tabs.items) |tab| {
            if (tab.content_owner.eql(owner) and painted(tab.root)) return true;
        };
        return false;
    }
    fn transferPresented(raw: *anyopaque, job: u64) bool {
        const self: *NotificationWindowHook = @ptrCast(@alignCast(raw));
        if (!self.cx.window_active) return false;
        if (self.transfer.manager_panel) |panel| if (painted(panel.root) and panel.presents(job)) return true;
        for (self.workspace.tabs.items) |tab| for (tab.transfer_trays) |tray| {
            if (tray) |panel| if (painted(panel.root) and panel.presents(job)) return true;
        };
        return false;
    }
    fn publishFileFailure(raw: *anyopaque, owner: @import("../../../host/identity.zig").SessionHandle, message: []const u8) void {
        const self: *NotificationWindowHook = @ptrCast(@alignCast(raw));
        self.workspace.status(message);
        self.host.publishOperationError(self.id, .{ .session = owner }, "文件", "文件操作失败", message, null) catch |err| applog.warn(.ui, "file creation failure notification: {s}", .{@errorName(err)});
        self.cx.requestRedraw();
    }
    fn publishStatus(raw: *anyopaque, owner: ?@import("../../../host/identity.zig").ContentOwner, message: []const u8, kind: ws.Workspace.StatusKind) void {
        if (kind != .failure) return;
        const self: *NotificationWindowHook = @ptrCast(@alignCast(raw));
        var buffer: [2048]u8 = undefined;
        self.host.publishOperationError(self.id, owner, "工作区", "操作未完成", @import("../../../shared/base/feedback_message.zig").message(message, &buffer), null) catch |err| applog.warn(.ui, "failure feedback: {s}", .{@errorName(err)});
        self.cx.requestRedraw();
    }
    fn operationAction(raw: *anyopaque, action: u64) void {
        const self: *NotificationWindowHook = @ptrCast(@alignCast(raw));
        switch (action) {
            1 => self.settings.locateSettingsProblem(),
            2 => if (self.nav.ai) |ai| {
                ai.settings_request = false;
                ai.openRequestedSettings();
            },
            else => {},
        }
        self.cx.requestRedraw();
    }
    fn cleanup(self: *NotificationWindowHook) void {
        self.cx.removeAfterLayoutHook(self);
        self.workspace.setNotificationAttentionBridge(.{});
        self.workspace.status_feedback = null;
        if (self.nav.application_host) |application| application.file_failure = null;
        self.host.removeWindow(self.id);
        self.cx.allocator.destroy(self);
    }
    fn prepareActivity(raw: *anyopaque) bool {
        const self: *NotificationWindowHook = @ptrCast(@alignCast(raw));
        if (self.workspace.shutting_down) return false;
        if (self.nav.app_runtime) |app| app.win.activate();
        // Keep the existing save/discard decision when settings contain edits.
        if (self.settings.open) self.settings.toggle();
        if (self.settings.open) return false;
        if (self.nav.quick_host) |quick| quick.close();
        return true;
    }
    pub fn hasDot(raw: ?*anyopaque, owner: @import("../../../host/identity.zig").ContentOwner) bool {
        const self: *NotificationWindowHook = @ptrCast(@alignCast(raw orelse return false));
        return self.host.coordinator.hasDot(owner);
    }
    fn owns(raw: *anyopaque, target: @import("../../../host/notification_coordinator.zig").Target) bool {
        const self: *NotificationWindowHook = @ptrCast(@alignCast(raw));
        if (target.kind == .transfer_done) for (self.transfer.tasks.job_owners.items) |job| {
            if (job.job == target.operation_id and target.owner.eql(.{ .session = job.owner })) return true;
        };
        for (self.workspace.tabs.items) |tab| if (tab.content_owner.eql(target.owner)) return true;
        return false;
    }
    fn activate(raw: *anyopaque, target: @import("../../../host/notification_coordinator.zig").Target) bool {
        const self: *NotificationWindowHook = @ptrCast(@alignCast(raw));
        if (self.workspace.shutting_down) return false;
        if (target.kind == .transfer_done) for (self.transfer.tasks.job_owners.items) |job| {
            if (job.job != target.operation_id or !target.owner.eql(.{ .session = job.owner })) continue;
            if (self.transfer.manager_panel) |panel| {
                panel.refresh(wallClockMsTransfer(), .{ .window_chunks = self.workspace.app_config.transfer.window_chunks, .chunk_kb = self.workspace.app_config.transfer.chunk_kb }) catch return false;
                panel.show();
                self.transfer.acknowledgeTransfers();
                self.transfer.manager_visible = true;
                if (self.nav.app_runtime) |app| app.win.activate();
                self.cx.requestRedraw();
                return true;
            }
        };
        for (self.workspace.tabs.items, 0..) |tab, index| {
            if (!tab.content_owner.eql(target.owner) or tab.closing) continue;
            self.workspace.selectTab(index);
            if (self.nav.app_runtime) |app| app.win.activate();
            if (target.kind == .ai_ready) if (self.nav.ai) |ai| if (!ai.controller.model.visible) ai.toggle();
            self.cx.requestRedraw();
            return true;
        }
        return false;
    }
    fn activateAi(raw: *anyopaque, conversation: @import("../../../host/identity.zig").ConversationId) bool {
        const self: *NotificationWindowHook = @ptrCast(@alignCast(raw));
        if (self.workspace.shutting_down) return false;
        const ai = self.nav.ai orelse return false;
        const store = if (ai.assistant_states) |value| value else return false;
        const state = store.findConversation(conversation) orelse return false;
        if (state.closed) return false;
        // 对话归属的 tab 仍在（单卡 tab 未在关闭，或组 tab 的会话组仍在）才定位。
        const bound = ai.resolveOwner(state.owner) orelse return false;
        if (bound.card) |tab| if (tab.closing) return false;
        AiHost.conversationAction(ai, state.id, .locate);
        if (self.nav.app_runtime) |app| app.win.activate();
        self.cx.requestRedraw();
        return true;
    }
    fn feedback(raw: *anyopaque, message: []const u8) void {
        const self: *NotificationWindowHook = @ptrCast(@alignCast(raw));
        if (self.workspace.shutting_down) return;
        if (self.settings.open and self.settings.controller.model.page_index == 6) self.settings.refresh(message) else self.workspace.status(message);
        self.cx.requestRedraw();
    }
    fn observeReconnect(self: *NotificationWindowHook, tab: *ws.SessionTab) void {
        const runtime = tab.runtime orelse return;
        const state = runtime.reconnectSnapshot() orelse return;
        const key = state.key orelse return;
        if (key.owner != .session or !tab.content_owner.eql(.{ .session = key.owner.session }) or key.attempt_id == null) return;
        if (state.phase == .active and key.attempt_id.? > 1) {
            self.host.publishReconnectDetails(tab.content_owner, key.operation_id, key.attempt_id.?, .recovered, .{ .object = tab.titleSlice() }) catch |err| applog.warn(.app, "reconnect notification: {s}", .{@errorName(err)});
        } else if (state.phase == .waiting and state.cleanup == .released and (state.was_attached or tab.remote_retrying) and tab.remote_retry_deadline == null and state.failure != null) {
            self.host.publishReconnectDetails(tab.content_owner, key.operation_id, key.attempt_id.?, .failed, .{ .object = tab.titleSlice(), .detail = @import("../../connections/progress/view/connection_progress_view.zig").failureText(state.failure), .incident_id = state.notification_incident }) catch |err| applog.warn(.app, "disconnect notification: {s}", .{@errorName(err)});
        }
    }
    fn run(raw: *anyopaque, _: u8, _: bool) ui.AfterLayoutResult {
        const self: *NotificationWindowHook = @ptrCast(@alignCast(raw));
        self.observe();
        self.history_revision = self.host.coordinator.history_revision;
        if (self.history_view) |view| {
            self.nav.notification_pending = view.vm.pendingCount();
            self.nav.notification_unread = view.vm.badgeShown();
        }
        return .done;
    }
    fn maintain(raw: *anyopaque, settings_changed: bool) void {
        const self: *NotificationWindowHook = @ptrCast(@alignCast(raw));
        if (self.workspace.shutting_down) return;
        if (settings_changed and self.settings.open and self.settings.controller.model.page_index == 6) {
            self.settings.pending_rebuild = true;
            self.cx.requestRedraw();
        }
        self.observe();
        // A receipt can change the history badge without producing terminal
        // output. Wake for that change, never merely for the polling interval.
        if (self.history_revision != self.host.coordinator.history_revision) self.cx.requestRedraw();
        self.history_revision = self.host.coordinator.history_revision;
    }
    fn observe(self: *NotificationWindowHook) void {
        if (self.workspace.shutting_down) return;
        self.host.activity.setForeground(@import("../../../platform/menu_bar.zig").active());
        if (self.cx.window_active and !self.was_active) self.host.refreshAuthorization() catch |err| {
            if (err != error.NotificationUnavailable) applog.warn(.app, "notification authorization refresh: {s}", .{@errorName(err)});
        };
        self.was_active = self.cx.window_active;
        const clock = @import("../../../host/notification_host.zig").localClock() catch return;
        for (self.workspace.tabs.items, 0..) |tab, index| {
            if (tab.closing or tab.isCard() or tab.content_owner != .session or tab.terminal == null) continue;
            self.observeReconnect(tab);
            const terminal = if (tab.terminal) |*value| value else continue;
            const owner = tab.content_owner.session;
            const facts: @import("../../../host/terminal_service.zig").NotificationSnapshot = if (terminal.terminal_surface) |surface| blk: {
                const status = surface.service.status() catch continue;
                if (!status.owner.eql(owner)) continue;
                break :blk status.notification();
            } else if (tab.runtime) |runtime| runtime.workerPtr().notificationSnapshot(owner) catch continue else continue;
            self.host.activity.observeTerminal(facts) catch |err| applog.warn(.app, "menu bar activity: {s}", .{@errorName(err)});
            self.host.publishRecordingStatus(self.id, owner, facts.recording_error) catch |err| applog.warn(.app, "recording risk notification: {s}", .{@errorName(err)});
            if (facts.output_sequence != 0) _ = self.host.coordinator.observeOutput(tab.content_owner, facts.output_sequence) catch false;
            if (facts.bell_count != 0) {
                const bell = self.host.coordinator.observeBell(tab.content_owner, facts.bell_count, clock) catch continue;
                if (!bell.duplicate and @import("../../../platform/runtime_mode.zig").automation) std.debug.print("NOTIFICATION_BELL {{\"owner_id\":{d},\"owner_generation\":{d},\"sequence\":{d},\"duplicate\":{},\"disposition\":\"{s}\",\"failure\":\"{s}\"}}\n", .{ @backingInt(owner.session_id), owner.generation, facts.bell_count, bell.duplicate, @tagName(bell.sound.disposition), if (bell.sound.failure) |failure| @errorName(failure) else "" });
            }
            const bounds = tab.root.globalRect();
            const grouped_visible = self.workspace.active_group_view != null and tab.root.isDisplayedInTree() and bounds.w > 0 and bounds.h > 0;
            const standalone_visible = self.workspace.active_group_view == null and self.workspace.active_tab == index and self.cx.focus_manager.getFocused() == terminal.root;
            const visible = self.cx.window_active and (grouped_visible or standalone_visible) and !self.settings.open and (if (self.nav.ai) |ai| !ai.controller.model.visible else true);
            if (visible) {
                if (terminal.notificationReadSequence(owner)) |sequence| {
                    if (sequence == facts.output_sequence) {
                        const read = self.host.coordinator.markRead(tab.content_owner, sequence, true);
                        if (read and @import("../../../platform/runtime_mode.zig").automation) std.debug.print("NOTIFICATION_READ {{\"owner_id\":{d},\"owner_generation\":{d},\"through_sequence\":{d}}}\n", .{ @backingInt(owner.session_id), owner.generation, sequence });
                    }
                }
            }
        }
        self.workspace.refreshNotificationAttention();
    }
};

