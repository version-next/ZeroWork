//! Bounded process-local history behind the title-bar bell. The view is
//! `notification_history.yix` (native Popover / ScrollArea / Card / Button /
//! Badge / Alert, default looks); its state lives in
//! `history/model/view_model.zig`. This file is the host glue: it mounts the
//! panel and the bell badge, forwards bell clicks, polls the (non-reactive)
//! coordinator once per frame and returns focus to the bell on close.
const std = @import("std");
const ui = @import("ui");
const host = @import("../../../host/notification_host.zig");
const m = @import("../history/model/view_model.zig");
const template = @import("_notification_history.yix.zig");

pub const View = struct {
    cx: *ui.Cx,
    trigger: *ui.Node,
    vm: *m.ViewModel,
    open: *ui.Signal(bool),
    /// Popover content root (`notifications.history`), resolved after mount.
    root: *ui.Node,
    was_open: bool = false,
    panel: ?*ui.Node = null,

    pub fn mount(cx: *ui.Cx, scope: *ui.Scope, notification_host: *host.Host, trigger: *ui.Node) !*View {
        const vm = try m.ViewModel.init(scope, cx.allocator, notification_host);
        // “清除已结束”走本窗口的撤销账本（`shared/ui/confirm`）。
        vm.undo = @import("../../../shared/ui/confirm/confirm.zig").port(cx);
        const self = try scope.createState(View, .{ .cx = cx, .trigger = trigger, .vm = vm, .open = vm.open, .root = undefined });
        try trigger.appendChild(cx.allocator, try ui.view.render(scope, cx, template.Unread(.{ .vm = vm })));
        // The popover wrapper stays in the bell's subtree (normal teardown frees
        // it); the panel itself is portaled over the window.
        try trigger.appendChild(cx.allocator, try ui.view.render(scope, cx, template.History(.{ .vm = vm, .anchor = trigger, .panel_slot = &self.panel })));
        self.root = self.panel orelse return error.NotificationHistoryPanelMissing;
        trigger.behavior.events.on_click = .{ .callback = toggle, .context = self };
        try cx.addAfterLayoutHook(self, frame);
        try scope.onCleanup(View, self, cleanup);
        vm.sync(cx.window_active);
        return self;
    }

    fn toggle(raw: *anyopaque) void {
        const self: *View = @ptrCast(@alignCast(raw));
        self.vm.toggle();
        self.cx.requestRedraw();
    }

    /// Close (the title bar click group closes the bell's panel when another tool opens).
    pub fn close(self: *View) void {
        if (self.open.peek()) self.vm.toggle();
        self.cx.requestRedraw();
    }

    fn frame(raw: *anyopaque, _: u8, _: bool) ui.AfterLayoutResult {
        const self: *View = @ptrCast(@alignCast(raw));
        self.vm.sync(self.cx.window_active);
        // Focus entry / return is the panel's native Popover (OverlayHost `panel`).
        self.was_open = self.open.peek();
        return .done;
    }

    fn cleanup(self: *View) void {
        self.cx.removeAfterLayoutHook(self);
    }
};
