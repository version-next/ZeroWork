//! Close confirmation for the assistant's ×: the shared native confirmation (`shared/ui/confirm`).
//! The host validates the captured conversation ticket and applies stop/close at its safe boundary.
const std = @import("std");
const ui = @import("ui");
const identity = @import("../../../../host/identity.zig");
const S = @import("ai_close_confirmation_styles.zig");
const confirm_ui = @import("../../../../shared/ui/confirm/confirm.zig");
pub const Ticket = struct {
    sequence: u64,
    conversation_id: identity.ConversationId,
    pub fn eql(self: Ticket, other: Ticket) bool {
        return self.sequence == other.sequence and self.conversation_id.eql(other.conversation_id);
    }
};
pub const Snapshot = struct { ticket: Ticket, running: bool, enabled: bool = true };
pub const Callbacks = struct {
    context: *anyopaque,
    on_confirm: *const fn (*anyopaque, Ticket) anyerror!void,
    on_cancel: *const fn (*anyopaque, Ticket) void,
};
pub const View = struct {
    cx: *ui.Cx,
    /// Zero-layout owner the caller mounts; the dialog itself portals over the window.
    root: *ui.Node = undefined,
    /// The dialog panel (`ai.close.confirmation`).
    panel: *ui.Node = undefined,
    title: *ui.Node = undefined,
    detail: *ui.Node = undefined,
    confirm: *ui.Node = undefined,
    cancel: *ui.Node = undefined,
    anchor: *ui.Node,
    open: *ui.Signal(bool),
    disabled: *ui.Signal(bool),
    title_text: *ui.Signal([]const u8),
    snapshot: ?Snapshot = null,
    resolved_ticket: ?Ticket = null,
    focus_pending: bool = false,
    callbacks: Callbacks,

    const end_label = confirm_ui.label(.end, " AI 会话");

    /// The shared `confirm(spec)` (zenit ConfirmDialog, CONSISTENCY_AUDIT #2): native title bar (the
    /// question), the consequence as its message, 取消 (focus on open) and the danger “结束 AI 会话”.
    /// Esc / × / scrim = 取消 (OverlayHost `dialog`); the modal scrim keeps a click from reaching
    /// what is underneath.
    pub fn mount(cx: *ui.Cx, scope: *ui.Scope, anchor: *ui.Node, callbacks: Callbacks) !*View {
        const self = try scope.createState(View, .{ .cx = cx, .anchor = anchor, .callbacks = callbacks, .open = try scope.createSignal(bool, false), .disabled = try scope.createSignal(bool, true), .title_text = try scope.createText("结束当前会话？", .{}) });
        self.root = try ui.box(cx, .{ .position = .absolute, .width = .{ .px = 0 }, .height = .{ .px = 0 }, .flex_shrink = 0 }, .{});
        const dialog = try confirm_ui.confirm(scope, cx, .{
            .open = ui.split(self.open, cx.on(View, self, openChanged)),
            .title = self.title_text,
            .message = "历史和草稿保留，待处理消息暂停。完成后解绑，连接保持打开。",
            .action = end_label,
            .action_disabled = self.disabled,
            .width = S.width,
            // confirmRequest resolves the captured ticket and closes the dialog itself.
            .close_on_confirm = false,
            .on_confirm = cx.on(View, self, confirmRequest),
            .test_id = "ai.close.confirmation",
            .test_ids = .{ .title = "ai.close.confirmation.title", .message = "ai.close.confirmation.detail", .cancel = "ai.close.confirmation.cancel", .confirm = "ai.close.confirmation.confirm" },
        });
        if (!dialog.modal.portaled) try self.root.appendChild(cx.allocator, dialog.modal.overlay);
        self.panel = dialog.modal.dialog;
        self.panel.behavior.interaction.a11y = .{ .role = .dialog, .label = "关闭助手确认", .modal = true };
        // The native title bar's text carries the question.
        self.title = dialog.title.?;
        self.detail = dialog.message;
        self.cancel = dialog.cancel;
        self.confirm = dialog.confirm;
        try scope.onCleanup(View, self, cleanup);
        return self;
    }
    pub fn update(self: *View, next: ?Snapshot) !void {
        const snapshot = next orelse {
            self.dismiss();
            self.resolved_ticket = null;
            return;
        };
        if (self.resolved_ticket) |ticket| if (ticket.eql(snapshot.ticket)) return;
        const changed = if (self.snapshot) |old| !old.ticket.eql(snapshot.ticket) or old.running != snapshot.running or old.enabled != snapshot.enabled else true;
        // The host republishes this snapshot from its frame poll. An unchanged
        // open request must not rewrite text, disturb a press, or schedule work.
        if (!changed and self.open.peek()) return;
        if (changed) self.cancelPress();
        self.snapshot = snapshot;
        self.resolved_ticket = null;
        self.disabled.set(!snapshot.enabled);
        self.title_text.set(if (snapshot.running) "停止并结束当前会话？" else "结束当前会话？");
        self.open.set(true);
        self.cx.requestRedraw();
    }
    /// Host-driven dismissal never emits a user cancellation or destroys nodes.
    pub fn dismiss(self: *View) void {
        if (self.snapshot == null and !self.open.peek() and self.disabled.peek()) return;
        self.cancelPress();
        self.snapshot = null;
        self.disabled.set(true);
        self.open.set(false);
        self.cx.requestRedraw();
    }
    fn cancelPress(self: *View) void {
        if (self.cx.pressed_node) |pressed| if (pressed == self.panel or pressed.isDescendantOf(self.panel)) self.cx.cancelPointerInteractions(.explicit);
    }
    fn confirmRequest(self: *View) void {
        const snapshot = self.snapshot orelse return;
        if (!snapshot.enabled or self.disabled.peek()) return;
        self.resolved_ticket = snapshot.ticket;
        self.dismiss();
        self.callbacks.on_confirm(self.callbacks.context, snapshot.ticket) catch |err| std.log.warn("AI close confirmation rejected: {s}", .{@errorName(err)});
    }
    fn cancelRequest(self: *View) void {
        const snapshot = self.snapshot orelse return;
        self.resolved_ticket = snapshot.ticket;
        self.dismiss();
        self.callbacks.on_cancel(self.callbacks.context, snapshot.ticket);
    }
    /// The dialog's own close proposal (取消, ×, Esc, scrim) is 取消.
    fn openChanged(self: *View, value: bool) void {
        if (!value) self.cancelRequest();
    }
    fn cleanup(self: *View) void {
        if (self.cx.focus_manager.current_focus) |focused| if (focused == self.panel or focused.isDescendantOf(self.panel)) self.cx.clearFocus();
    }
};
