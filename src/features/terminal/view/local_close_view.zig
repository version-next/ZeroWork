//! Frozen local-close details; no process operation occurs before confirmation.
const std = @import("std");
const ui = @import("ui");
const confirm = @import("../../../shared/ui/confirm/confirm.zig");
const styles = @import("local_close_styles.zig");
const theme = @import("../../../shared/ui/theme/app_theme.zig");
const SessionId = @import("../../../host/session_lifecycle.zig").SessionId;
const Risk = @import("../../../host/process_service.zig").CloseRiskSnapshot;
pub const Hooks = struct { context: *anyopaque, resolve: *const fn (*anyopaque, SessionId, bool) void };
pub const View = struct {
    cx: *ui.Cx,
    hooks: Hooks,
    open: *ui.Signal(bool),
    overlay: *ui.Node,
    session: ?SessionId = null,
    identity: *ui.Node,
    risk_title: *ui.Node,
    risk_detail: *ui.Node,
    extra: *ui.Node,
    extra_text: *ui.Node,
    dialog: *ui.Node,
    cancel_button: *ui.Node,
    confirm_button: *ui.Node = undefined,
    risk: *ui.Node = undefined,
    notice: *ui.Node = undefined,

    /// The shared `confirm(spec)` (zenit `ConfirmDialog`): native title bar “关闭页签？”, the consequence as
    /// its message (glossary §4), the frozen session identity and risk in its slot, 取消 (focus on open)
    /// and the danger “关闭页签”. Esc / × / scrim = 取消 (OverlayHost `dialog`).
    pub fn mount(cx: *ui.Cx, scope: *ui.Scope, hooks: Hooks) !*View {
        const self = try cx.allocator.create(View);
        errdefer cx.allocator.destroy(self);
        const open = try scope.createSignal(bool, false);
        self.* = .{ .cx = cx, .hooks = hooks, .open = open, .overlay = undefined, .identity = undefined, .risk_title = undefined, .risk_detail = undefined, .extra = undefined, .extra_text = undefined, .dialog = undefined, .cancel_button = undefined};
        const dialog = try confirm.confirm(scope, cx, .{
            .open = ui.split(open, cx.on(View, self, changed)),
            .title = "关闭页签？",
            .message = "关闭页签会结束该本地会话及其进程。历史记录保留。",
            .action = confirm.label(.close, "页签"),
            .width = 480,
            .max_height = 500,
            // accept() resolves and takes the dialog down itself.
            .close_on_confirm = false,
            .on_confirm = cx.on(View, self, accept),
            .test_id = "local.close.confirmation",
            .test_ids = .{ .message = "local.close.notice", .cancel = "local.close.cancel", .confirm = "local.close.accept" },
        });
        self.overlay = dialog.modal.overlay;
        if (!dialog.modal.portaled) if (cx.root) |root| try root.appendChild(cx.allocator, dialog.modal.overlay);
        self.dialog = dialog.modal.dialog;
        self.cancel_button = dialog.cancel;
        self.confirm_button = dialog.confirm;
        self.notice = dialog.message;
        const body = dialog.content;
        self.identity = try self.label(body, "", 18, styles.text(12, true));
        const risk = try ui.box(cx, styles.risk(), .{});
        self.risk = risk;
        self.risk_title = try self.label(risk, "", 18, styles.text(12, true));
        var detail_style = styles.text(11.5, false);
        detail_style.use_monospace_font = true;
        self.risk_detail = try self.label(risk, "", 18, detail_style);
        try body.appendChild(cx.allocator, risk);
        const scroll = try ui.widgets.ScrollArea(.{ .direction = .vertical, .rubber_band_y = false }).mount(scope, cx);
        self.extra = scroll.container;
        scroll.container.setStyleInline(cx.allocator, .{ .width = .fill(), .height = .{ .px = 0 }, .flex_shrink = 0, .display = .none });
        const jobs_style = styles.text(11.5, false);
        const extra_text = try ui.text(cx, "", .{ .font_size = jobs_style.font_size, .color = jobs_style.color, .wrap = .word, .use_monospace_font = true });
        self.extra_text = extra_text;
        try scroll.content.appendChild(cx.allocator, extra_text);
        try body.appendChild(cx.allocator, scroll.container);
        try scope.onCleanup(View, self, cleanup);
        // Retained colours follow the window's theme publication (also while the dialog is closed).
        try scope.createEffect(.{ .view = self, .publication = try cx.themeSignal() }, struct {
            fn paint(ctx: anytype) void {
                _ = ctx.publication.get();
                ctx.view.retheme();
            }
        }.paint);
        return self;
    }
    fn label(self: *View, parent: *ui.Node, value: []const u8, height: f32, style: ui.TextStyle) !*ui.Node {
        const node = try ui.text(self.cx, value, style);
        node.setStyleInline(self.cx.allocator, .{ .width = .fill(), .height = .{ .px = height }, .flex_shrink = 0 });
        try parent.appendChild(self.cx.allocator, node);
        return node;
    }
    pub fn show(self: *View, id: SessionId, snapshot: ?*const Risk) !void {
        if (self.session != null) return error.CloseConfirmationAlreadyOpen;
        self.retheme();
        var buffer: [256]u8 = undefined;
        try self.identity.setTextContent(self.cx.allocator, try std.fmt.bufPrint(&buffer, "本地 · zsh · #{d}", .{id}));
        var title: []const u8 = "无法核实本地进程状态";
        var detail: []const u8 = "进程信息未知，确认关闭后才会尝试清理";
        var extra: std.Io.Writer.Allocating = .init(self.cx.allocator);
        defer extra.deinit();
        if (snapshot) |risk| {
            switch (risk.foreground_state) {
                .task => {
                    title = "仍有前台进程";
                    if (risk.foreground) |fg| detail = try std.fmt.bufPrint(&buffer, "{s} · PID {d}", .{ std.mem.sliceTo(&fg.name, 0), fg.pid });
                },
                .idle_shell => {
                    title = "本地 shell 仍在运行";
                    detail = "";
                },
                .not_running => {
                    title = "本地进程已结束";
                    detail = "仍需释放该会话的资源";
                },
                .unknown => {},
            }
            for (risk.active_exec) |job| try extra.writer.print("{s} · PID {?d} · {s}{s}\n", .{ @tagName(job.state), job.pid, job.command, if (job.command_truncated) " …" else "" });
            if (risk.unknown) try extra.writer.writeAll("部分进程状态无法核实\n");
        }
        try self.risk_title.setTextContent(self.cx.allocator, title);
        try self.risk_detail.setTextContent(self.cx.allocator, detail);
        self.risk_detail.setDisplay(if (detail.len == 0) .none else .flex);
        const bytes = extra.writer.buffered();
        try self.extra_text.setTextContent(self.cx.allocator, bytes);
        self.extra.setDisplay(if (bytes.len == 0) .none else .flex);
        self.extra.setStyle(self.cx.allocator, .height, .{ .px = 88 });
        self.session = id;
        self.open.set(true);
        self.cx.requestRedraw();
    }
    fn retheme(self: *View) void {
        const c = theme.current();
        self.risk.setBackground(styles.riskFill());
        for ([_]*ui.Node{ self.identity, self.risk_title }) |node| node.setTextColor(c.fg_1);
        for ([_]*ui.Node{ self.risk_detail, self.extra_text }) |node| node.setTextColor(c.fg_2);
        self.cx.requestRedraw();
    }
    pub fn cancel(self: *View) void {
        self.resolve(false);
    }
    pub fn accept(self: *View) void {
        self.resolve(true);
    }
    fn resolve(self: *View, accepted: bool) void {
        const id = self.session orelse return;
        self.session = null;
        self.open.set(false);
        self.hooks.resolve(self.hooks.context, id, accepted);
        self.cx.requestRedraw();
    }
    fn changed(self: *View, value: bool) void {
        if (!value) self.cancel();
    }
    fn cleanup(self: *View) void {
        self.cx.allocator.destroy(self);
    }
};
