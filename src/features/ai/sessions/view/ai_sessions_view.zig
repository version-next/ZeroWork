//! Session list and one frozen-identity close confirmation. Host applies actions next frame.
const std = @import("std");
const ui = @import("ui");
const IdSpace = @import("../../shared/view/ai_id_space.zig").IdSpace;
const S = @import("ai_sessions_styles.zig");
const panel_header = @import("../../../../shared/ui/components/panel_header/panel_header.zig");
const T = @import("../../../../shared/ui/theme/app_theme.zig");
const RowView = @import("ai_session_row.zig");
const Header = @import("../../pane/view/ai_assistant_header.zig");
const Confirm = @import("../../../../shared/ui/confirm/confirm.zig");
pub const Action = RowView.Action;
pub const Entry = RowView.Entry;
pub const Hooks = RowView.Hooks;
const model = @import("../model/view_model.zig");
pub const View = struct {
    /// Test-id namespace of the surface this list is mounted in.
    space: IdSpace,
    /// The window's conversation phases (rows here and on the welcome page follow it) and its
    /// bound-session count (the button's badge and accessible name follow it). They follow the
    /// shared conversations once the window binds them (`follow`).
    phases: *model.SessionPhases,
    bound: *model.BoundSessions,
    /// The Scope the view was mounted in (it owns the count's effect).
    home: *ui.Scope,
    count_followed: bool = false,
    /// Where the popover opens (the chrome button, or the docked pane's 更多; cards-float).
    anchor_ref: *@import("ai_popover_anchor.zig").Anchor = undefined,
    /// The header button's live accessible name goes to the floating chrome (its slot button).
    label_sink: ?@import("../../../../shared/ui/float_card/float_chrome.zig").SlotLabel = null,
    cx: *ui.Cx,
    scope: *ui.Scope,
    hooks: Hooks,
    open: *ui.Signal(bool),
    confirmation: *ui.Signal(bool),
    highlighted: *ui.Signal(u64),
    content: *ui.Node,
    root: *ui.Node,
    surface: *ui.Node,
    chrome: *ui.Node,
    /// The popover's content (`ai.sessions.menu`): PanelHeader · list · 显示更多.
    panel: *ui.Node,
    heading_count: *ui.Node,
    more: *ui.Node = undefined,
    painted_colors: T.Colors,
    button: *ui.Node,
    badge: *ui.Node,
    a11y_label: [96]u8 = undefined,
    scroll: ui.widgets.ScrollAreaResult,
    rows: ?*ui.Scope = null,
    pending: ?u64 = null,
    desired_height: f32 = 0,
    entry_count: usize = 0,
    detail: *ui.Node,
    dialog: *ui.Node,
    confirmation_title: *ui.Signal([]const u8) = undefined,
    confirmation_message: *ui.Signal([]const u8) = undefined,
    accept_label: *ui.Signal([]const u8) = undefined,
    accept_disabled: *ui.Signal(bool) = undefined,
    confirmation_operation: ?u64 = null,
    history_open: *ui.Signal(bool) = undefined,
    history_dialog: *ui.Node = undefined,
    history_dialog_body: *ui.Node = undefined,
    history_title: *ui.Node = undefined,
    history_status: *ui.Node = undefined,
    history_body: *ui.Node = undefined,
    history_scroll: *ui.Node = undefined,
    history_actions: *ui.Node = undefined,
    history_scope: ?*ui.Scope = null,
    history_entry: ?u64 = null,

    /// Open beside `node` (the docked pane's 更多) instead of the chrome button; null = the button.
    pub fn setAnchor(self: *View, node: ?*ui.Node) void {
        self.anchor_ref.override = node;
    }
    /// The panel (floating chrome root or docked pane) the popover stays inside (O7: never wider than it).
    pub fn setBounds(self: *View, node: ?*ui.Node) void {
        self.anchor_ref.bounds = node;
    }
    pub fn mount(cx: *ui.Cx, scope: *ui.Scope, anchor: *ui.Node, hooks: Hooks) !*View {
        const space = IdSpace.of(scope);
        const open = try scope.createSignal(bool, false);
        const confirmation = try scope.createSignal(bool, false);
        const anchor_ref = try scope.createState(@import("ai_popover_anchor.zig").Anchor, .{ .node = anchor });
        // Pencil O7 `SmqQV`: native W.Popover (default panel), 360 wide but never wider than the AI panel
        // (`ai_popover_anchor`), PanelHeader · rows · 显示更多. The content box sizes the popover.
        const popup = try ui.widgets.Popover(.{ .open = open, .trigger = .manual, .anchor = anchor_ref.popover(), .position = .bottom_start, .offset = .{ .static = 6 }, .close_on_escape = true, .close_on_outside_click = true, .flip = true, .shift_main_axis = true, .viewport_padding = 8 }).mount(scope, cx);
        popup.wrapper.setStyleInline(cx.allocator, .{ .position = .absolute, .width = .{ .px = 0 }, .height = .{ .px = 0 }, .flex_shrink = 0 });
        const panel = try ui.box(cx, S.panel(), .{});
        panel.meta.ownership.meta.test_id = space.id("ai.sessions.menu");
        try popup.content.appendChild(cx.allocator, panel);
        const heading = try ui.box(cx, S.heading(), .{});
        heading.meta.ownership.meta.test_id = space.id("ai.sessions.heading");
        try heading.appendChild(cx.allocator, try ui.iconTint(cx, ui.icons.messages_square, cx.tokens.tokens.color.fg_secondary, S.headingIcon()));
        try heading.appendChild(cx.allocator, try ui.textStyled(cx, S.headingTitle, "AI 会话"));
        const heading_count = try ui.textStyled(cx, S.headingCount, "");
        heading_count.meta.ownership.meta.test_id = space.id("ai.sessions.total");
        try heading.appendChild(cx.allocator, heading_count);
        try heading.appendChild(cx.allocator, try ui.spacer(cx));
        try panel.appendChild(cx.allocator, heading);
        const scroll = try ui.widgets.ScrollArea(.{ .height = 240, .direction = .vertical, .rubber_band_y = false }).mount(popup.scope, cx);
        scroll.container.setStyleInline(cx.allocator, S.listSurface());
        scroll.content.setStyleInline(cx.allocator, S.menu());
        scroll.container.meta.ownership.meta.test_id = space.id("ai.sessions.list");
        try panel.appendChild(cx.allocator, scroll.container);
        const badge = try Header.mountCountBadge(cx, scope, anchor, space.id("ai.sessions.count"));
        const phases = try model.SessionPhases.mount(scope, cx.allocator, null);
        var row_hooks = hooks;
        row_hooks.phases = phases;
        const self = try scope.createState(View, .{ .space = space, .phases = phases, .bound = try model.BoundSessions.mount(scope, null), .home = scope, .cx = cx, .scope = popup.scope, .hooks = row_hooks, .open = open, .confirmation = confirmation, .highlighted = try scope.createSignal(u64, 0), .content = scroll.content, .root = popup.wrapper, .surface = scroll.container, .chrome = popup.chrome, .panel = panel, .heading_count = heading_count, .painted_colors = T.current(), .button = anchor, .badge = badge, .scroll = scroll, .detail = undefined, .dialog = undefined });
        self.anchor_ref = anchor_ref;
        // panel-heads：头部关闭是全应用共享的 PanelClose（原生 ghost sm 图标按钮 + Tooltip“关闭 · Esc”）。
        try heading.appendChild(cx.allocator, try panel_header.mountClose(popup.scope, cx, .{ .label = "关闭 AI 会话列表", .test_id = space.id("ai.sessions.close"), .tooltip_test_id = space.id("ai.sessions.close.tooltip"), .on_close = cx.on(View, self, closeMenu) }));
        const more_state = try scope.createState(HistoryAction, .{ .view = self, .id = 0, .action = .more });
        self.more = try ui.widgets.Button(.{ .label = "显示更多", .variant = .link, .size = .sm, .block = true, .on_click = cx.on(HistoryAction, more_state, HistoryAction.run) }).mount(popup.scope, cx);
        self.more.meta.ownership.meta.test_id = space.id("ai.sessions.more");
        self.more.setDisplay(.none);
        try panel.appendChild(cx.allocator, self.more);
        // Delete / end confirmation: the shared `confirm(spec)` (zenit ConfirmDialog; 取消 takes focus,
        // Esc / × / scrim = 取消, danger 动词 + 对象).
        self.confirmation_title = try scope.createText("删除此 AI 会话？", .{});
        self.confirmation_message = try scope.createText("将删除此会话及其历史，无法撤销。已绑定的会话须先结束并解绑。", .{});
        self.accept_label = try scope.createText(Confirm.label(.delete, " AI 会话"), .{});
        self.accept_disabled = try scope.createSignal(bool, false);
        const dialog = try Confirm.confirm(scope, cx, .{
            .open = ui.split(confirmation, cx.on(View, self, confirmationChanged)),
            .title = self.confirmation_title,
            .message = self.confirmation_message,
            .action = self.accept_label,
            .action_disabled = self.accept_disabled,
            .width = 360,
            // acceptClose takes the dialog down itself (and tells the host which choice it was).
            .close_on_confirm = false,
            .on_confirm = cx.on(View, self, acceptClose),
            .test_id = space.id("ai.session.close.confirmation"),
            .test_ids = .{ .message = space.id("ai.session.close.detail"), .cancel = space.id("ai.session.close.cancel"), .confirm = space.id("ai.session.close.accept") },
        });
        if (!dialog.modal.portaled) if (cx.root) |root| try root.appendChild(cx.allocator, dialog.modal.overlay);
        self.dialog = dialog.modal.dialog;
        self.detail = dialog.message;
        self.history_open = try scope.createSignal(bool, false);
        const history_modal = try ui.widgets.Modal(.{ .open = self.history_open, .width = 600, .max_height = 480 }).mount(scope, cx);
        if (!history_modal.portaled) if (cx.root) |root| try root.appendChild(cx.allocator, history_modal.overlay);
        self.history_dialog = history_modal.dialog;
        self.history_dialog_body = history_modal.body;
        history_modal.dialog.meta.ownership.meta.test_id = space.id("ai.history");
        history_modal.dialog.setStyleInline(cx.allocator, .{ .width = .{ .px = 600 }, .max_width = 600 });
        history_modal.body.setStyleInline(cx.allocator, .{ .width = .fill(), .direction = .column, .padding = ui.Padding.all(16), .gap = 12 });
        const history_heading = try ui.box(cx, S.actions(), .{});
        self.history_title = try ui.textStyled(cx, S.dialogTitle, "AI 会话");
        self.history_title.setStyleInline(cx.allocator, .{ .width = .fill(), .min_width = 0 });
        try history_heading.appendChild(cx.allocator, self.history_title);
        // panel-heads：统一关闭按钮（历史 Modal 的 Esc 同样关闭）。
        try history_heading.appendChild(cx.allocator, try panel_header.mountClose(scope, cx, .{ .label = "关闭会话历史", .test_id = space.id("ai.history.close"), .tooltip_test_id = space.id("ai.history.close.tooltip"), .on_close = cx.on(View, self, closeHistory) }));
        try history_modal.body.appendChild(cx.allocator, history_heading);
        self.history_status = try ui.textStyled(cx, S.dialogDetailStyle, "只读查看");
        self.history_status.meta.ownership.meta.test_id = space.id("ai.history.status");
        try history_modal.body.appendChild(cx.allocator, self.history_status);
        const history_scroll = try ui.widgets.ScrollArea(.{ .height = 220, .direction = .vertical }).mount(scope, cx);
        history_scroll.container.setStyleInline(cx.allocator, .{ .width = .fill(), .height = .{ .px = 220 }, .min_height = 0, .flex_shrink = 0 });
        self.history_scroll = history_scroll.container;
        self.history_body = try ui.textStyled(cx, S.dialogDetailStyle, "");
        self.history_body.meta.ownership.meta.test_id = space.id("ai.history.body");
        self.history_body.setStyleInline(cx.allocator, .{ .width = .fill(), .height = .{ .fit = .{} }, .flex_shrink = 0 });
        try history_scroll.content.appendChild(cx.allocator, self.history_body);
        try history_modal.body.appendChild(cx.allocator, history_scroll.container);
        self.history_actions = try ui.box(cx, S.actions(), .{});
        self.history_actions.setStyleInline(cx.allocator, .{ .height = .{ .fit = .{} }, .flex_wrap = .wrap });
        try history_modal.body.appendChild(cx.allocator, self.history_actions);
        try scope.createEffect(.{ .view = self, .open = confirmation }, struct {
            fn apply(ctx: anytype) void {
                if (!ctx.open.get()) if (ctx.view.confirmation_operation) |operation| {
                    ctx.view.confirmation_operation = null;
                    if (ctx.view.hooks.confirmed) |callback| callback(ctx.view.hooks.context, operation, false);
                };
            }
        }.apply);

        try scope.createEffect(.{ .view = self, .publication = try cx.themeSignal() }, struct {
            fn apply(ctx: anytype) void {
                _ = ctx.publication.get();
                ctx.view.retheme();
            }
        }.apply);
        self.reflow();
        return self;
    }
    /// Native Modal is fixed-width by default; constrain our surfaces and give
    /// the scrollable body only the space left by the real footer and heading.
    pub fn reflow(self: *View) void {
        if (self.open.peek()) self.fitList();
        const width = @max(0, self.cx.viewport.width - 32);
        self.setPixels(self.dialog, true, @min(360, width));
        self.setPixels(self.history_dialog, true, @min(600, width));
        const fixed = 32 + 36 + 28 + @max(16, self.history_status.globalRect().h) + @max(28, self.history_actions.globalRect().h);
        const body_height = @min(220, @max(0, self.cx.viewport.height - 32 - fixed));
        self.setPixels(self.history_scroll, false, body_height);
        self.setPixels(self.history_dialog, false, fixed + body_height);
    }
    fn setPixels(self: *View, node: *ui.Node, horizontal: bool, value: f32) void {
        const old = if (horizontal) node.style.width else node.style.height;
        if (old == .px and @abs(old.px - value) < 0.1) return;
        node.setStyleInline(self.cx.allocator, if (horizontal) .{ .width = .{ .px = value } } else .{ .height = .{ .px = value } });
    }
    fn retheme(self: *View) void {
        const next = T.current();
        if (@import("std").meta.eql(self.painted_colors, next)) return;
        // Rows, header and the history dialog are token-styled (they follow the theme themselves); the
        // popover and Modal panels are zenit's default surfaces.
        Header.repaintCountBadge(self.cx, self.badge);
        self.reflow();
        self.painted_colors = next;
        self.cx.requestRedraw();
    }
    /// Follows the window's shared conversations: row phases and the bound count.
    pub fn follow(self: *View, sources: model.Sources) !void {
        try self.phases.attach(sources.presentations);
        try self.bound.attach(sources.lifecycle);
        if (self.count_followed) return;
        self.count_followed = true;
        // From here on the badge and the accessible name show the count, and change only with it.
        try self.home.createEffect(.{ .view = self, .count = self.bound.count }, struct {
            fn run(ctx: anytype) void {
                ctx.view.updateBoundCount(ctx.count.get()) catch {};
                ctx.view.cx.requestRedraw();
            }
        }.run);
    }
    pub fn updateBoundCount(self: *View, count: usize) !void {
        try Header.updateCountBadge(self.cx, self.badge, count);
        const label = try @import("std").fmt.bufPrint(&self.a11y_label, "AI 会话列表，{d} 个已绑定", .{count});
        if (self.label_sink) |sink| sink.set(label) else if (self.button.behavior.interaction.a11y) |*a11y| a11y.label = label;
    }
    fn closeMenu(self: *View) void {
        self.open.set(false);
    }
    /// The dialog's own close proposal (取消, ×, Esc, scrim) is 取消.
    fn confirmationChanged(self: *View, open: bool) void {
        if (open) return self.confirmation.set(true);
        self.cancelClose();
    }
    fn cancelClose(self: *View) void {
        if (self.confirmation_operation) |operation| {
            self.confirmation_operation = null;
            if (self.hooks.confirmed) |callback| callback(self.hooks.context, operation, false);
        }
        self.pending = null;
        self.confirmation.set(false);
    }
    fn acceptClose(self: *View) void {
        if (self.accept_disabled.peek()) return;
        if (self.confirmation_operation) |operation| {
            self.confirmation_operation = null;
            self.confirmation.set(false);
            if (self.hooks.confirmed) |callback| callback(self.hooks.context, operation, true);
            return;
        }
        const id = self.pending orelse return;
        self.pending = null;
        self.confirmation.set(false);
        self.open.set(false);
        self.hooks.remove(self.hooks.context, id);
    }
    pub fn confirm(self: *View, id: u64) void {
        self.confirmation_operation = null;
        self.confirmation_title.set("删除此 AI 会话？");
        self.confirmation_message.set("将删除此会话及其历史，无法撤销。已绑定的会话须先结束并解绑。");
        self.accept_label.set(Confirm.label(.delete, " AI 会话"));
        self.accept_disabled.set(false);
        self.pending = id;
        self.reflow();
        self.confirmation.set(true);
    }
    pub fn confirmOperation(self: *View, operation: u64, title: []const u8, label: []const u8) !void {
        self.pending = null;
        self.open.set(false);
        self.history_open.set(false);
        self.confirmation_title.set(title);
        self.confirmation_message.set("当前任务将停止，待处理消息暂停。历史和草稿保留，连接保持打开。");
        self.accept_label.set(label);
        self.accept_disabled.set(false);
        self.confirmation_operation = operation;
        self.reflow();
        self.confirmation.set(true);
        self.cx.requestRedraw();
    }
    pub fn showProgress(self: *View, operation: u64) !void {
        self.confirmation_title.set("已绑定 · 正在停止当前任务");
        self.confirmation_message.set("正在等待资源释放。取消只取消后续恢复或使用副本，已受理的结束仍会完成；历史和草稿会保留。");
        self.accept_label.set("等待释放…");
        self.accept_disabled.set(true);
        self.confirmation_operation = operation;
        self.reflow();
        self.confirmation.set(true);
    }
    fn closeHistory(self: *View) void {
        self.history_open.set(false);
    }
    pub fn showHistory(self: *View, entry: Entry, text: []const u8) !void {
        const space = self.space;
        self.open.set(false);
        try self.history_title.setTextContent(self.cx.allocator, entry.title);
        try self.history_status.setTextContent(self.cx.allocator, if (entry.ending) "已绑定 · 正在停止任务 · 只读查看" else if (entry.bound) "已绑定 · 只读查看" else "未绑定 · 历史环境 · 只读查看");
        try self.history_body.setTextContent(self.cx.allocator, if (text.len == 0) "此会话尚无已保存消息，草稿与待处理记录仍保留。" else text);
        if (self.cx.pressed_node) |node| if (node.isDescendantOf(self.history_actions)) self.cx.cancelPointerInteractions(.explicit);
        while (self.history_actions.children.items.len != 0) {
            const child = self.history_actions.children.items[0];
            self.cx.detachChild(self.history_actions, child);
            self.cx.destroyDetached(child);
        }
        if (self.history_scope) |old| old.dispose();
        const scope = try self.scope.childScope();
        self.history_scope = scope;
        self.history_entry = entry.id;
        if (entry.can_copy) {
            try self.historyButton(scope, entry.id, .copy, "复制，不使用", space.id("ai.history.copy"));
            try self.historyButton(scope, entry.id, .copy_use, "复制到当前 Agent", space.id("ai.history.copy_use"));
        }
        if (entry.bound) {
            try self.historyButton(scope, entry.id, .locate, "定位", space.id("ai.history.locate"));
            if (entry.active and !entry.ending) try self.historyButton(scope, entry.id, .end, "结束并解绑", space.id("ai.history.end"));
        } else if (entry.can_restore) try self.historyButton(scope, entry.id, .restore, if (entry.first_use) "使用到当前 Agent" else "恢复到当前 Agent", space.id("ai.history.restore"));
        if (entry.has_children) try self.historyButton(scope, entry.id, .children, "查看子智能体", space.id("ai.history.children"));
        self.reflow();
        self.history_open.set(true);
        self.cx.requestRedraw();
    }
    const HistoryAction = struct {
        view: *View,
        id: u64,
        action: Action,
        fn run(self: *HistoryAction) void {
            if (self.action == .end or self.action == .children) self.view.history_open.set(false);
            if (self.view.hooks.act) |act| act(self.view.hooks.context, self.id, self.action);
        }
    };
    fn historyButton(self: *View, scope: *ui.Scope, id: u64, action: Action, label: []const u8, test_id: []const u8) !void {
        const state = try scope.createState(HistoryAction, .{ .view = self, .id = id, .action = action });
        const button = try ui.widgets.Button(.{ .label = if (action == .children) "" else label, .a11y_label = label, .icon_only = action == .children, .icon_asset = if (action == .children) ui.icons.bot else null, .variant = .secondary, .size = .sm, .on_click = self.cx.on(HistoryAction, state, HistoryAction.run) }).mount(scope, self.cx);
        button.meta.ownership.meta.test_id = test_id;
        try self.history_actions.appendChild(self.cx.allocator, button);
    }
    pub fn show(self: *View, entries: []const Entry) !void {
        const space = self.space;
        self.open.set(false);
        if (self.rows) |old| old.dispose();
        while (self.content.children.items.len > 0) {
            const child = self.content.children.items[0];
            self.content.removeChild(child);
            self.cx.destroyDetached(child);
        }
        const scope = try self.scope.childScope();
        self.rows = scope;
        var count_buffer: [32]u8 = undefined;
        try self.heading_count.setTextContent(self.cx.allocator, try std.fmt.bufPrint(&count_buffer, "{d} 条", .{entries.len}));
        if (entries.len == 0) {
            const empty_row = try ui.box(self.cx, S.emptyRow(), .{});
            const empty = try ui.textStyled(self.cx, S.emptyText, "暂无已保存对话。新建会话时，当前对话和草稿会保留在这里。");
            empty.meta.ownership.meta.test_id = space.id("ai.sessions.empty");
            empty.setStyleInline(self.cx.allocator, .{ .width = .fill() });
            try empty_row.appendChild(self.cx.allocator, empty);
            try self.content.appendChild(self.cx.allocator, empty_row);
        }
        self.highlighted.set(0);
        for (entries) |entry| if (entry.active) {
            self.highlighted.set(entry.id);
            break;
        };
        for (entries) |entry| {
            try self.content.appendChild(self.cx.allocator, try RowView.mount(self.cx, scope, entry, self.hooks, self.highlighted, self.open));
        }
        self.more.setDisplay(if (self.hooks.act != null and entries.len >= 50) .flex else .none);
        self.entry_count = entries.len;
        self.fitList();
        ui.widgets.setScrollY(self.scroll.state, self.scroll.content, 0);
        self.open.set(true);
    }
    /// The list's natural height (rows 59, 2 apart), capped so the popover ends inside the AI panel
    /// (O7: the old fixed 240 cut the fourth row in half and could hang below a short panel).
    fn fitList(self: *View) void {
        const n: f32 = @floatFromInt(self.entry_count);
        const natural = if (self.entry_count == 0) S.empty_height else n * S.row_height + (n - 1) * S.row_gap;
        // Without a known panel: at most five rows.
        var limit: f32 = 5 * S.row_height + 4 * S.row_gap;
        if (self.anchor_ref.panelRect()) |panel| {
            const trigger = (self.anchor_ref.override orelse self.anchor_ref.node).globalRect();
            const top = trigger.y + trigger.h + 6;
            const fixed = 2 * S.content_padding + S.header_height + S.row_gap + (if (self.more.style.display != .none) S.more_height + S.row_gap else 0);
            limit = panel.y + panel.h - @import("ai_popover_anchor.zig").panel_inset - top - fixed;
        }
        const height = @max(@min(natural, S.row_height), @min(natural, limit));
        self.desired_height = height;
        const width = self.anchor_ref.currentWidth();
        if (self.panel.style.width != .px or @abs(self.panel.style.width.px - width) > 0.1) self.panel.setStyleInline(self.cx.allocator, .{ .width = .{ .px = width } });
        if (self.surface.style.height != .px or @abs(self.surface.style.height.px - height) > 0.1) self.surface.setStyleInline(self.cx.allocator, .{ .height = .{ .px = height }, .display = .flex });
    }
};
