//! 命令失败提示（AI 错误轻提示）：会话里一条命令以非零退出码结束时，在本窗口的 zenit 原生通知栈里弹一张卡片
//! （“询问 AI”动作、8 秒、悬停 / 焦点暂停、关闭、滑动关闭都是原生的），不再在终端面板里手拼浮层。
//! 规则（哪条命令、何时算新失败、开关、重连重置）仍在 `ai/command_error_hint.zig` 的 `Model`；这里只负责
//! 何时把卡片放进 / 收出通知栈：所属终端面板不在屏幕上（切到别的标签、窗口失去焦点）时收起，回来后重新弹出并给满
//! 8 秒（与旧实现“恢复后给完整时长”一致）；关闭、到期、执行动作后不再重放同一条失败。
const std = @import("std");
const ui = @import("ui");
pub const policy = @import("../../../ai/command_error_hint.zig");
const vt = @import("../../../vt/snapshot.zig");
const SessionHandle = @import("../../../host/identity.zig").SessionHandle;
const notifications = @import("../../notifications/mod.zig");
const toast = notifications.toast;
const visible_region = @import("../../../shared/ui/styles/visible_region.zig");
pub const timeout_ms: u32 = 8000;

pub const View = struct {
    cx: *ui.Cx,
    /// The terminal pane: the card shows only while it is on screen.
    anchor: *ui.Node,
    model: policy.Model,
    handler: ?policy.Handler = null,
    /// The card in the window's notification stack, while shown. The stack itself is looked up
    /// through the window registry on every use, never cached: on quit the window scope frees the
    /// notification presenter (and its stack) before the terminal pane destroys this view.
    card: ?u64 = null,
    title: std.ArrayList(u8) = .empty,
    body: std.ArrayList(u8) = .empty,
    detail: std.ArrayList(u8) = .empty,
    exit_code: i32 = 1,

    pub fn create(cx: *ui.Cx, parent: *ui.Node) !*View {
        const self = try cx.allocator.create(View);
        errdefer cx.allocator.destroy(self);
        self.* = .{ .cx = cx, .anchor = parent, .model = policy.Model.init(cx.allocator) };
        try cx.addAfterLayoutHook(self, afterLayout);
        return self;
    }

    pub fn destroy(self: *View) void {
        self.cx.removeAfterLayoutHook(self);
        if (notifications.windowToasts(self.cx)) |stack| stack.releaseCommands(self);
        self.model.deinit();
        self.title.deinit(self.cx.allocator);
        self.body.deinit(self.cx.allocator);
        self.detail.deinit(self.cx.allocator);
        self.cx.allocator.destroy(self);
    }

    pub fn configure(self: *View, owner: SessionHandle, enabled: bool, handler: ?policy.Handler) void {
        self.model.configure(owner, enabled and handler != null);
        self.handler = handler;
        if (self.model.pending == null) self.hideCard();
    }

    pub fn observe(self: *View, owner: SessionHandle, projection: *const vt.Projection) !void {
        if (!try self.model.observe(owner, projection)) return;
        const hint = self.model.pending.?;
        const preview = try policy.outputPreview(self.cx.allocator, projection);
        defer self.cx.allocator.free(preview);
        if (self.handler) |handler| if (handler.on_notice) |publish| publish(handler.context, hint, preview) catch |err| {
            std.log.debug("command failure history unavailable: {s}", .{@errorName(err)});
        };
        const a = self.cx.allocator;
        self.title.clearRetainingCapacity();
        try self.title.print(a, "命令执行失败 · 退出码 {d}", .{hint.exit_code});
        self.body.clearRetainingCapacity();
        try self.body.print(a, "命令  {s}", .{if (hint.command.len == 0) "（未提供）" else hint.command});
        for (self.body.items) |*byte| if (byte.* == '\n' or byte.* == '\r' or byte.* == '\t') {
            byte.* = ' ';
        };
        // The bounded output preview is the card's details, expanded (scrolls inside the card).
        self.detail.clearRetainingCapacity();
        try self.detail.print(a, "输出  {s}", .{if (preview.len == 0) "命令未返回错误详情" else preview});
        self.exit_code = hint.exit_code;
        // A newer failure replaces the shown one and restarts the timer.
        self.hideCard();
        self.sync();
        self.cx.requestRedraw();
    }

    pub fn dismiss(self: *View) void {
        self.model.dismiss();
        self.hideCard();
        self.cx.requestRedraw();
    }

    pub fn resetFacts(self: *View) void {
        self.model.resetFacts();
        self.hideCard();
        self.cx.requestRedraw();
    }

    pub fn activate(self: *View) void {
        const handler = self.handler orelse return;
        const pending = self.model.pending orelse return;
        const hint = self.model.current(pending.owner, pending.command_id) orelse return;
        handler.on_open(handler.context, hint) catch return;
        self.dismiss();
    }

    /// The card currently in the window's notification stack (null = not shown).
    pub fn shownCard(self: *const View) ?u64 {
        return self.card;
    }

    /// Interrupted / terminated commands are a warning; other nonzero results are errors.
    pub fn tone(exit_code: i32) toast.Tone {
        return if (exit_code == 0) .success else if (exit_code == 130 or exit_code == 143) .warning else .failure;
    }

    fn visible(self: *View) bool {
        return self.cx.window_active and visible_region.snapshot(self.cx, self.anchor) != null;
    }

    /// Put the pending failure into the window stack while the pane is on screen; take it out
    /// (keeping it pending) while it is not.
    pub fn sync(self: *View) void {
        const want = self.model.pending != null and self.visible();
        if (!want) {
            self.hideCard();
            return;
        }
        if (self.card != null) return;
        const stack = notifications.windowToasts(self.cx) orelse return;
        self.card = stack.showCommand(self, onCard, .{
            .id = 0,
            .kind = .command,
            .tone = tone(self.exit_code),
            .title = self.title.items,
            .body = self.body.items,
            .detail = self.detail.items,
            .detail_expanded = true,
            .actions = .{ "询问 AI", "", "" },
            .action_count = 1,
            .duration_ms = timeout_ms,
        }) catch return;
    }

    fn hideCard(self: *View) void {
        const id = self.card orelse return;
        self.card = null;
        if (notifications.windowToasts(self.cx)) |stack| stack.dismissCommand(id);
    }

    fn onCard(raw: *anyopaque, event: toast.CommandEvent) void {
        const self: *View = @ptrCast(@alignCast(raw));
        // The stack has already forgotten the card.
        self.card = null;
        switch (event) {
            .action => self.activate(),
            .dismissed, .expired => self.dismiss(),
        }
        self.cx.requestRedraw();
    }

    fn afterLayout(raw: *anyopaque, _: u8, _: bool) ui.AfterLayoutResult {
        const self: *View = @ptrCast(@alignCast(raw));
        self.sync();
        return .done;
    }
};
