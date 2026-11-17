const std = @import("std");
const error_text = @import("../../../shared/base/error_text.zig");
const ui = @import("ui");
const ThemeWatch = @import("../../../shared/ui/theme/theme_watch.zig").ThemeWatch;
const styles = @import("record_cleanup_styles.zig");
const theme = @import("../../../shared/ui/theme/app_theme.zig");
const Progress = @import("../../../host/record_cleanup.zig").Progress;
const confirm = @import("../../../shared/ui/confirm/confirm.zig");
pub const Action = enum { confirm, retry, dismiss };
pub const Hooks = struct { context: *anyopaque, action: *const fn (*anyopaque, Action) void };
pub const Mode = enum { confirm, running, failed, cleared };

/// “清空会话记录”：共享的原生确认框（`shared/ui/confirm`，zenit ConfirmDialog）。确认态：标题“清空会话记录？”、说明、
/// “取消” + 危险的“清空会话记录”；确认后同一个框显示进度（取消不可用）、失败（“返回” + “重试失败项”）或完成
/// （“返回” + “完成”）。焦点在“取消 / 返回”，每换一步回到它；Esc / 标题栏 × 等于“取消 / 返回”。
pub const View = struct {
    cx: *ui.Cx,
    hooks: Hooks,
    open: *ui.Signal(bool),
    dialog: *ui.Node,
    content_stack: *ui.Node,
    headline: *ui.Node,
    detail: *ui.Node,
    receipt: *ui.Node,
    cancel: *ui.Node,
    primary: *ui.Node,
    mode: Mode = .confirm,
    title_text: *ui.Signal([]const u8),
    headline_text: *ui.Signal([]const u8),
    cancel_text: *ui.Signal([]const u8),
    primary_text: *ui.Signal([]const u8),
    primary_shown: *ui.Signal(bool),
    running: *ui.Signal(bool),
    step: *ui.Signal(u64),
    colors: theme.Colors,
    /// Raised by the window's theme publication; consumed where this view repaints.
    theme_watch: ThemeWatch = .{},

    pub fn mount(cx: *ui.Cx, scope: *ui.Scope, hooks: Hooks) !*View {
        const self = try cx.allocator.create(View);
        errdefer cx.allocator.destroy(self);
        const open = try scope.createSignal(bool, false);
        self.* = .{ .cx = cx, .hooks = hooks, .open = open, .dialog = undefined, .content_stack = undefined, .headline = undefined, .detail = undefined, .receipt = undefined, .cancel = undefined, .primary = undefined, .title_text = try scope.createText("清空会话记录？", .{}), .headline_text = try scope.createText("", .{}), .cancel_text = try scope.createText(confirm.cancel_label, .{}), .primary_text = try scope.createText(confirm.label(.clear, "会话记录"), .{}), .primary_shown = try scope.createSignal(bool, true), .running = try scope.createSignal(bool, false), .step = try scope.createSignal(u64, 0), .colors = theme.current() };
        const dialog = try confirm.confirm(scope, cx, .{
            .open = ui.split(open, cx.on(View, self, changed)),
            .title = self.title_text,
            .message = self.headline_text,
            .action = self.primary_text,
            .cancel = self.cancel_text,
            .action_shown = self.primary_shown,
            .cancel_disabled = self.running,
            .refocus = self.step,
            .width = 440,
            .max_height = 320,
            .close_on_confirm = false,
            .on_confirm = cx.on(View, self, activate),
            .test_id = "settings.record-cleanup",
            .test_ids = .{ .message = "settings.record-cleanup.headline", .cancel = "settings.record-cleanup.cancel", .confirm = "settings.record-cleanup.confirm" },
        });
        if (!dialog.modal.portaled) if (cx.root) |root| try root.appendChild(cx.allocator, dialog.modal.overlay);
        if (dialog.modal.dialog.behavior.interaction.a11y) |*a11y| a11y.label = "会话记录清理";
        self.dialog = dialog.modal.dialog;
        self.headline = dialog.message;
        self.cancel = dialog.cancel;
        self.primary = dialog.confirm;
        self.content_stack = dialog.content;
        const detail = try ui.text(cx, "", styles.text(12, 18, 400));
        detail.setStyleInline(cx.allocator, .{ .width = .fill(), .flex_shrink = 0 });
        detail.meta.ownership.meta.test_id = "settings.record-cleanup.detail";
        try dialog.content.appendChild(cx.allocator, detail);
        const receipt = try ui.text(cx, "", styles.text(11, 16, 400));
        receipt.setStyleInline(cx.allocator, .{ .width = .fill(), .flex_shrink = 0 });
        receipt.meta.ownership.meta.test_id = "settings.record-cleanup.receipt";
        receipt.behavior.interaction.a11y = .{ .role = .status, .live = "polite" };
        try dialog.content.appendChild(cx.allocator, receipt);
        self.detail = detail;
        self.receipt = receipt;
        try scope.onCleanup(View, self, cleanup);
        try self.theme_watch.bind(cx, scope);
        try cx.addAfterLayoutHook(self, afterLayout);
        return self;
    }
    fn nextStep(self: *View) void {
        self.step.set(self.step.peek() +% 1);
        self.running.set(self.mode == .running);
        self.primary_shown.set(self.mode != .running);
    }
    pub fn showConfirmation(self: *View) !void {
        self.mode = .confirm;
        self.title_text.set("清空会话记录？");
        self.headline_text.set("将删除所有已结束会话的输出与快照。");
        try self.detail.setTextContent(self.cx.allocator, "无法撤销。主机、设置草稿与诊断日志保留。");
        try self.receipt.setTextContent(self.cx.allocator, "");
        self.cancel_text.set(confirm.cancel_label);
        self.primary_text.set(confirm.label(.clear, "会话记录"));
        if (self.primary.behavior.interaction.a11y) |*a11y| a11y.label = "清空已结束会话记录";
        self.nextStep();
        self.retheme();
        self.open.set(true);
        self.cx.requestRedraw();
    }
    pub fn update(self: *View, progress: Progress, failure: ?anyerror, index_missing: bool) !void {
        self.mode = if (!progress.done()) .running else if (progress.failed != 0) .failed else .cleared;
        self.title_text.set("会话记录清理");
        var headline: [192]u8 = undefined;
        const value = switch (self.mode) {
            .confirm => unreachable,
            .running => "正在清理会话记录…",
            // 原因取 shared/base/error_text.zig 的标题；原始错误名不进界面（宿主写应用日志）。
            .failed => if (failure) |err| try std.fmt.bufPrint(&headline, "{s} · {s}", .{ if (index_missing) "文件缺失，索引提交失败" else "部分记录未清理", if (error_text.describe(err)) |known| known.title else "原因见应用日志" }) else if (index_missing) "文件缺失，索引提交失败" else "部分记录未清理",
            .cleared => if (progress.total == 0) "暂无可清理的会话记录" else "会话记录已清空",
        };
        self.headline_text.set(value);
        try self.detail.setTextContent(self.cx.allocator, if (self.mode == .failed) failureDetail(failure) else if (self.mode == .running) "正在处理本次确认的记录。" else "主机、设置与应用诊断日志保留。");
        var receipt: [128]u8 = undefined;
        try self.receipt.setTextContent(self.cx.allocator, try std.fmt.bufPrint(&receipt, "已清理 {d} 项 · 失败 {d} 项{s}", .{ progress.deleted, progress.failed, if (progress.pending == 0) "" else " · 处理中" }));
        self.cancel_text.set("返回");
        self.primary_text.set(if (self.mode == .failed) confirm.label(.retry, "失败项") else "完成");
        if (self.primary.behavior.interaction.a11y) |*a11y| a11y.label = if (self.mode == .failed) "仅重试本次清理失败的记录" else "完成并返回设置";
        self.nextStep();
        self.retheme();
        self.cx.requestRedraw();
    }
    pub fn showResult(self: *View) void {
        self.open.set(true);
        self.cx.requestRedraw();
    }
    pub fn showProblem(self: *View, err: anyerror) void {
        self.mode = .failed;
        self.title_text.set("会话记录清理");
        var buffer: [192]u8 = undefined;
        self.headline_text.set(std.fmt.bufPrint(&buffer, "无法开始清理 · {s}", .{if (error_text.describe(err)) |known| known.title else "原因见应用日志"}) catch "无法开始清理");
        self.detail.setTextContent(self.cx.allocator, failureDetail(err)) catch {};
        self.receipt.setTextContent(self.cx.allocator, "") catch {};
        self.cancel_text.set("返回");
        self.primary_text.set(confirm.label(.retry, "清理"));
        self.nextStep();
        self.retheme();
        self.cx.requestRedraw();
    }
    pub fn hide(self: *View) void {
        self.open.set(false);
    }
    pub fn dismiss(self: *View) void {
        self.open.set(false);
        self.hooks.action(self.hooks.context, .dismiss);
        self.cx.requestRedraw();
    }
    fn activate(self: *View) void {
        switch (self.mode) {
            .confirm => self.hooks.action(self.hooks.context, .confirm),
            .failed => self.hooks.action(self.hooks.context, .retry),
            .cleared => self.dismiss(),
            .running => {},
        }
    }
    fn changed(self: *View, open: bool) void {
        if (!open) self.dismiss();
    }
    pub fn retheme(self: *View) void {
        const c = theme.current();
        const has_receipt = if (self.receipt.getText()) |value| value.content.len != 0 else false;
        self.receipt.setDisplay(if (has_receipt) .flex else .none);
        self.detail.setTextColor(c.fg_1);
        self.receipt.setTextColor(c.fg_2);
        self.colors = c;
    }
    fn afterLayout(raw: *anyopaque, _: u8, _: bool) ui.AfterLayoutResult {
        const self: *View = @ptrCast(@alignCast(raw));
        if (self.theme_watch.take()) self.retheme();
        return .done;
    }
    fn cleanup(self: *View) void {
        self.cx.removeAfterLayoutHook(self);
        self.cx.allocator.destroy(self);
    }
};
fn failureDetail(failure: ?anyerror) []const u8 {
    const err = failure orelse return "未完成的记录保留，可重试失败项。";
    return switch (err) {
        error.RecordBusy => "记录正被读取，请关闭预览或等待导出结束后重试。",
        error.LiveSessionActive => "请先结束活动会话。",
        error.AccessDenied => "未删除的记录保留；检查目录权限后重试。",
        error.RecordingChanged => "记录内容已变化；本次不会删除被替换的文件。",
        else => "未完成的记录保留，可重试失败项。",
    };
}
