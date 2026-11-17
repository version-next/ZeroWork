//! Stable rows keep their child identity while a popover is being operated.
const std = @import("std");
const ui = @import("ui");
const ThemeWatch = @import("../../../../shared/ui/theme/theme_watch.zig").ThemeWatch;
const theme = @import("../../../../shared/ui/theme/app_theme.zig");
const projection = @import("../../../../ai/child_projection.zig");
const Logo = @import("ai_child_logo.zig");
const Rows = @import("_ai_children_rows.yss.zig");
const S = @import("ai_children_styles.zig");
const Header = @import("../../pane/view/ai_assistant_header.zig");
const id = @import("../../../../host/identity.zig");
pub const Hooks = struct { context: *anyopaque, select: *const fn (*anyopaque, id.AgentId, u64) void };
pub const View = struct {
    /// Where the popover opens (the chrome button, or the docked pane's 更多; cards-float).
    anchor_ref: *@import("ai_popover_anchor.zig").Anchor = undefined,
    /// The header button's live accessible name goes to the floating chrome (its slot button).
    label_sink: ?@import("../../../../shared/ui/float_card/float_chrome.zig").SlotLabel = null,
    cx: *ui.Cx,
    scope: *ui.Scope,
    hooks: Hooks,
    open: *ui.Signal(bool),
    root: *ui.Node,
    content: *ui.Node,
    chrome: *ui.Node,
    /// The popover's content box (padding 6; its width sizes the popover).
    panel: *ui.Node,
    painted_colors: theme.Colors,
    /// Raised by the window's theme publication; consumed where this view repaints.
    theme_watch: ThemeWatch = .{},
    button: *ui.Node,
    badge: *ui.Node,
    heading_count: *ui.Node,
    rows: std.ArrayList(*Row) = .empty,
    rows_scope: ?*ui.Scope = null,
    fingerprint: u64 = 0,
    a11y_label: [80]u8 = undefined,
    /// Open beside `node` (the docked pane's 更多) instead of the chrome button; null = the button.
    pub fn setAnchor(self: *View, node: ?*ui.Node) void {
        self.anchor_ref.override = node;
    }
    /// The panel (floating chrome root or docked pane) the popover stays inside (O8: never wider than it).
    pub fn setBounds(self: *View, node: ?*ui.Node) void {
        self.anchor_ref.bounds = node;
    }
    pub fn mount(cx: *ui.Cx, scope: *ui.Scope, button: *ui.Node, hooks: Hooks) !*View {
        const open = try scope.createSignal(bool, false);
        const anchor_ref = try scope.createState(@import("ai_popover_anchor.zig").Anchor, .{ .node = button });
        // Pencil O8 `TTNSh`: native W.Popover (default panel), 360 wide but inside the AI panel; PanelHeader
        // (bot · 子智能体 · count · ×), group titles, rows (Pressable 44: logo 24 · name · detail · status 14).
        const popup = try ui.widgets.Popover(.{ .open = open, .trigger = .manual, .anchor = anchor_ref.popover(), .position = .bottom_start, .offset = .{ .static = 6 }, .close_on_escape = true, .close_on_outside_click = true, .flip = true, .shift_main_axis = true, .viewport_padding = 8 }).mount(scope, cx);
        popup.wrapper.setStyleInline(cx.allocator, .{ .position = .absolute, .width = .{ .px = 0 }, .height = .{ .px = 0 } });
        const panel = try ui.box(cx, S.panel(), .{});
        try popup.content.appendChild(cx.allocator, panel);
        const heading = try ui.box(cx, S.heading(), .{});
        heading.meta.ownership.meta.test_id = "ai.children.heading";
        try heading.appendChild(cx.allocator, try ui.iconTint(cx, ui.icons.bot, cx.tokens.tokens.color.fg_secondary, S.headingIcon()));
        const title = try ui.textStyled(cx, S.headingTitle, "子智能体");
        title.meta.ownership.meta.test_id = "ai.children.title";
        try heading.appendChild(cx.allocator, title);
        const heading_count = try ui.textStyled(cx, S.headingCount, "");
        try heading.appendChild(cx.allocator, heading_count);
        try heading.appendChild(cx.allocator, try ui.spacer(cx));
        try panel.appendChild(cx.allocator, heading);
        const scroll = try ui.widgets.ScrollArea(.{ .direction = .vertical }).mount(popup.scope, cx);
        scroll.container.setStyleInline(cx.allocator, S.list());
        scroll.content.setStyleInline(cx.allocator, .{ .width = .fill(), .direction = .column });
        scroll.container.meta.ownership.meta.test_id = "ai.children.list";
        try panel.appendChild(cx.allocator, scroll.container);
        const badge = try Header.mountCountBadge(cx, scope, button, "ai.children.count");
        const self = try scope.createState(View, .{ .cx = cx, .scope = popup.scope, .hooks = hooks, .open = open, .root = popup.wrapper, .content = scroll.content, .chrome = popup.chrome, .panel = panel, .painted_colors = theme.current(), .button = button, .badge = badge, .heading_count = heading_count });
        self.anchor_ref = anchor_ref;
        const close = try ui.widgets.Button(.{ .variant = .ghost, .size = .sm, .icon_only = true, .icon_asset = ui.icons.x, .icon_size = 14, .a11y_label = "关闭子智能体列表", .on_click = cx.on(View, self, close_list) }).mount(popup.scope, cx);
        close.meta.ownership.meta.test_id = "ai.children.close";
        try heading.appendChild(cx.allocator, close);
        try scope.onCleanup(View, self, cleanup);
        try self.theme_watch.bind(cx, scope);
        return self;
    }
    fn cleanup(self: *View) void {
        self.rows.deinit(self.cx.allocator);
    }
    fn close_list(self: *View) void {
        self.open.set(false);
    }
    /// The header's 子智能体 button (the chrome slot button routes its press here).
    pub fn toggle(self: *View) void {
        self.open.set(!self.open.peek());
        self.fingerprint = 0;
        self.cx.requestRedraw();
    }
    pub fn update(self: *View, entries: []const projection.Entry) !void {
        return self.updateWithCount(entries, null);
    }
    /// Historical lists may show another parent's children. The header badge
    /// continues to describe only the currently displayed main conversation.
    pub fn updateWithCount(self: *View, entries: []const projection.Entry, running_count: ?usize) !void {
        if (self.theme_watch.take()) {
            self.painted_colors = theme.current();
            Header.repaintCountBadge(self.cx, self.badge);
            for (self.rows.items) |row| row.repaint();
            // Row looks resolve token colors at mount: rebuild on the next open.
            if (!self.open.peek()) self.fingerprint = 0;
        }
        const width = self.anchor_ref.currentWidth();
        if (self.panel.style.width != .px or @abs(self.panel.style.width.px - width) > 0.1) self.panel.setStyleInline(self.cx.allocator, .{ .width = .{ .px = width } });
        var count: usize = 0;
        var hash = std.hash.Wyhash.init(0);
        for (entries) |entry| {
            count += @intFromBool(entry.running);
            std.hash.autoHash(&hash, .{ entry.agent, entry.revision, entry.group, entry.running, entry.reusable, entry.changed_at_ms });
            hash.update(entry.name);
            hash.update(entry.status);
            hash.update(entry.summary);
        }
        count = running_count orelse count;
        var count_buffer: [64]u8 = undefined;
        const count_label = try std.fmt.bufPrint(&count_buffer, "{d} 个运行中", .{count});
        self.heading_count.setDisplay(if (count == 0) .none else .flex);
        if (!sameText(self.heading_count, count_label)) try self.heading_count.setTextContent(self.cx.allocator, count_label);
        const label = try std.fmt.bufPrint(&self.a11y_label, "子智能体，{d} 个运行中", .{count});
        if (self.label_sink) |sink| sink.set(label) else if (self.button.behavior.interaction.a11y) |*a11y| a11y.label = label;
        try Header.updateCountBadge(self.cx, self.badge, count);
        if (!self.open.peek()) {
            self.fingerprint = 0;
            return;
        }
        const stamp = hash.final();
        if (stamp == self.fingerprint) return;
        // While the list is open retain row nodes/order so a press cannot land
        // on a different Agent. The next open applies the latest grouped sort.
        if (self.rows.items.len != 0 and self.fingerprint != 0) {
            for (self.rows.items) |row| {
                row.node.setDisplay(.none);
                for (entries) |entry| if (row.agent.eql(entry.agent)) {
                    row.node.setDisplay(.flex);
                    try row.update(entry);
                    break;
                };
            }
            self.fingerprint = stamp;
            return;
        }
        if (self.rows_scope) |old| old.dispose();
        self.rows.clearRetainingCapacity();
        self.rows_scope = try self.scope.childScope();
        const scope = self.rows_scope.?;
        while (self.content.children.items.len != 0) {
            const node = self.content.children.items[0];
            self.cx.detachChild(self.content, node);
            self.cx.destroyDetached(node);
        }
        if (entries.len == 0) {
            const empty = try ui.textStyled(self.cx, S.secondary, "暂无子智能体");
            empty.setStyleInline(self.cx.allocator, S.emptyRow());
            try self.content.appendChild(self.cx.allocator, empty);
        }
        var group: ?projection.Group = null;
        for (entries) |entry| {
            if (group != entry.group) {
                const header = try ui.textStyled(self.cx, S.groupTitle, switch (entry.group) {
                    .attention => "待处理",
                    .active => "进行中",
                    .recent => "最近结束",
                });
                header.setStyleInline(self.cx.allocator, S.groupTitleBox());
                try self.content.appendChild(self.cx.allocator, header);
                group = entry.group;
            }
            const row = try scope.createState(Row, .{ .view = self, .agent = entry.agent, .revision = entry.revision, .node = undefined, .name = undefined, .detail = undefined, .status = undefined });
            row.a11y_name = try scope.createText(entry.name, .{});
            const node = try ui.view.render(scope, self.cx, ui.widgets.Pressable(.{ .a11y_label = row.a11y_name, .look = Rows.child_row, .on_click = self.cx.on(Row, row, Row.select) }));
            row.node = node;
            node.meta.ownership.meta.test_id = try std.fmt.bufPrint(&row.test_id, "ai.child.{s}", .{std.fmt.bytesToHex(entry.agent.bytes, .lower)});
            row.logo = try Logo.mount(self.cx, entry.agent);
            try node.appendChild(self.cx.allocator, row.logo);
            const copy = try ui.box(self.cx, S.rowCopy(), .{});
            row.name = try ui.textStyled(self.cx, S.name, "");
            row.name.meta.ownership.meta.test_id = "ai.child.row.name";
            row.name.setStyleInline(self.cx.allocator, .{ .width = .fill(), .min_width = 0, .overflow_hidden = true });
            row.detail = try ui.textStyled(self.cx, S.secondary, "");
            row.detail.meta.ownership.meta.test_id = "ai.child.row.detail";
            row.detail.setStyleInline(self.cx.allocator, .{ .width = .fill(), .min_width = 0, .overflow_hidden = true });
            row.status_text = try scope.createText(entry.status, .{});
            const status_tip = try ui.widgets.Tooltip(.{ .text = row.status_text, .width = 132 }).mount(scope, self.cx);
            status_tip.wrapper.meta.ownership.meta.test_id = "ai.child.row.status";
            status_tip.wrapper.setStyleInline(self.cx.allocator, S.statusSlot());
            status_tip.trigger.setStyleInline(self.cx.allocator, S.statusSlot());
            row.status = try ui.iconTint(self.cx, ui.icons.circle, theme.current().fg_2, .{ .width = .{ .px = 14 }, .height = .{ .px = 14 }, .flex_shrink = 0 });
            row.status.meta.ownership.meta.test_id = "ai.child.status.icon";
            try status_tip.trigger.appendChild(self.cx.allocator, row.status);
            try copy.appendChild(self.cx.allocator, row.name);
            try copy.appendChild(self.cx.allocator, row.detail);
            try node.appendChild(self.cx.allocator, copy);
            try node.appendChild(self.cx.allocator, status_tip.wrapper);
            try self.content.appendChild(self.cx.allocator, node);
            try row.update(entry);
            try self.rows.append(self.cx.allocator, row);
        }
        self.fingerprint = stamp;
    }
    fn sameText(node: *ui.Node, value: []const u8) bool {
        return if (node.getText()) |text| std.mem.eql(u8, text.content, value) else false;
    }
    const Row = struct {
        view: *View,
        agent: id.AgentId,
        revision: u64,
        test_id: [48]u8 = undefined,
        a11y_label: [384]u8 = undefined,
        node: *ui.Node,
        logo: *ui.Node = undefined,
        status_text: *ui.Signal([]const u8) = undefined,
        /// The row's accessible name ("name，status"): the Pressable's `a11y_label`.
        a11y_name: *ui.Signal([]const u8) = undefined,
        visual: Visual = .complete,
        name: *ui.Node,
        detail: *ui.Node,
        status: *ui.Node,
        fn update(self: *Row, entry: projection.Entry) !void {
            self.revision = entry.revision;
            if (!View.sameText(self.name, entry.name)) try self.name.setTextContent(self.view.cx.allocator, entry.name);
            self.a11y_name.set(try std.fmt.bufPrint(&self.a11y_label, "{s}，{s}", .{ entry.name, entry.status }));
            self.status_text.set(entry.status);
            self.visual = if (entry.running) .running else if (std.mem.eql(u8, entry.status, "失败")) .failed else if (entry.group == .attention) .attention else if (entry.group == .active) .waiting else if (std.mem.eql(u8, entry.status, "已停止")) .stopped else .complete;
            self.repaint();
            var buf: [256]u8 = undefined;
            const seconds: i64 = if (entry.changed_at_ms > 0) @max(0, @divTrunc(@import("../../../../platform/realtime.zig").milliseconds(undefined) - entry.changed_at_ms, 1000)) else 0;
            var summary_len = @min(entry.summary.len, 100);
            while (summary_len != 0 and summary_len < entry.summary.len and entry.summary[summary_len] & 0xc0 == 0x80) summary_len -= 1;
            const detail = try std.fmt.bufPrint(&buf, "{s}{s} · {d} 秒前", .{ if (entry.summary.len != 0) entry.summary[0..summary_len] else entry.status, if (entry.reusable) " · 可复用" else "", seconds });
            if (!View.sameText(self.detail, detail)) try self.detail.setTextContent(self.view.cx.allocator, detail);
        }
        const Visual = enum { running, waiting, attention, failed, stopped, complete };
        fn repaint(self: *Row) void {
            Logo.repaint(self.logo, self.agent);
            const colors = theme.current();
            const asset = ui.icons.get(switch (self.visual) {
                .running => "loader-circle",
                .waiting => "clock-3",
                .attention => "circle-help",
                .failed => "circle-alert",
                .stopped => "circle-stop",
                .complete => "circle-check",
            }).?;
            const tint = switch (self.visual) {
                .running, .waiting => colors.accent,
                .attention => colors.warn,
                .failed => colors.danger,
                .stopped => colors.fg_2,
                .complete => colors.ok,
            };
            self.status.setIcon(.{ .icon_id = asset.icon_id.?, .rep = asset.pickRep(14).?, .tint = tint });
        }
        fn select(self: *Row) void {
            self.view.open.set(false);
            self.view.hooks.select(self.view.hooks.context, self.agent, self.revision);
        }
    };
};
