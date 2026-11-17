//! Attached-window list. All identities/counts are supplied by the registry.
const std = @import("std");
const ui = @import("ui");
const overlay = @import("../../../../shared/ui/overlay/overlay_host.zig");
const panel_header = @import("../../../../shared/ui/components/panel_header/panel_header.zig");
const identity = @import("../../../../host/identity.zig");
pub const M = @import("../../../../host/socks_background_model.zig");
pub const S = @import("socks_background_styles.zig");
const Sidebar = @import("../../../shell/view/sidebar_view.zig");
pub const Action = enum { open_terminal, reconnect, stop };
pub const Hooks = struct {
    context: *anyopaque,
    action: *const fn (*anyopaque, identity.SessionHandle, Action) void,
};
pub const View = struct {
    cx: *ui.Cx,
    hooks: Hooks,
    popover: ui.widgets.popover.PopoverResult,
    header: *ui.Node,
    list: ui.widgets.ScrollAreaResult,
    remote_entry: *ui.Node,
    local_entry: *ui.Node,
    count_text: *ui.Signal([]const u8),
    tint: *ui.Signal(?ui.Color),
    hover: *ui.Signal(?ui.BoxStyle),
    anchor: ui.ComputedRect = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
    filter: ?identity.ConnectionId = null,
    row_scope: ?*ui.Scope = null,
    revision: u64 = 0,
    last_hash: ?u64 = null,
    colors: S.theme.Colors,

    pub fn mount(cx: *ui.Cx, scope: *ui.Scope, hooks: Hooks) !*View {
        const tint = try scope.createSignal(?ui.Color, S.theme.current().fg_2);
        const hover = try scope.createSignal(?ui.BoxStyle, .{ .background = S.theme.states().hover });
        const count_text = try scope.createText("", .{});
        const self = try scope.createState(View, .{ .cx = cx, .hooks = hooks, .popover = undefined, .header = undefined, .list = undefined, .remote_entry = undefined, .local_entry = undefined, .count_text = count_text, .tint = tint, .hover = hover, .colors = S.theme.current() });
        self.popover = try overlay.Popover(.panel, .{ .trigger = .manual, .position = .top_end, .offset = .{ .static = 6 }, .width = @as(f32, 360), .max_width = @as(f32, 360), .max_height = @as(f32, 420), .constrain_width_to_viewport = true, .close_on_escape = true, .close_on_outside_click = true, .consume_outside_click = false, .anchor = .{ .virtual = .{ .ctx = self, .getRect = anchorRect } } }).mount(scope, cx);
        self.popover.content.meta.ownership.meta.test_id = "socks.background.panel";
        self.popover.content.setStyleInline(cx.allocator, S.panel(128, cx.viewport.width));
        self.popover.trigger.setDisplay(.none);
        const header = try ui.box(cx, .{ .width = .fill(), .height = .{ .px = 30 }, .direction = .row, .align_items = .center, .gap = 6, .flex_shrink = 0 }, .{});
        self.header = header;
        try header.appendChild(cx.allocator, try ui.iconTint(cx, ui.icons.get("plug-zap").?, S.theme.current().accent, .{ .width = .{ .px = 18 }, .height = .{ .px = 18 }, .flex_shrink = 0 }));
        const title = try ui.text(cx, "后台转发", S.text(13, 700, 20, S.theme.current().fg_1));
        title.setStyleInline(cx.allocator, .{ .width = .fill(), .min_width = 0 });
        try header.appendChild(cx.allocator, title);
        // panel-heads：统一关闭按钮（`Popover(.panel)` 按 Esc 关闭）。
        try header.appendChild(cx.allocator, try panel_header.mountClose(self.popover.scope, cx, .{ .label = "关闭后台转发列表", .test_id = "socks.background.close", .on_close = self.popover.close }));
        try self.popover.content.appendChild(cx.allocator, header);
        self.list = try ui.widgets.ScrollArea(.{}).mount(self.popover.scope, cx);
        self.list.container.setStyleInline(cx.allocator, .{ .width = .fill(), .height = .fill(), .flex = 1, .min_height = 0 });
        self.list.content.setStyleInline(cx.allocator, .{ .width = .fill(), .direction = .column, .gap = 6, .min_width = 0 });
        self.list.content.meta.ownership.meta.test_id = "socks.background.rows";
        try self.popover.content.appendChild(cx.allocator, self.list.container);
        self.remote_entry = try self.entry(scope, "status.background.forward");
        self.local_entry = try self.entry(scope, "local.status.background.forward");
        try scope.createEffect(.{ .view = self, .theme = try cx.themeSignal() }, struct {
            fn run(ctx: anytype) void {
                _ = ctx.theme.get();
                const view = ctx.view;
                Sidebar.styles.repaint(view.popover.content, view.colors);
                view.colors = S.theme.current();
                view.tint.set(view.colors.fg_2);
                view.hover.set(.{ .background = view.colors.hover });
                view.last_hash = null;
            }
        }.run);
        return self;
    }
    fn entry(self: *View, scope: *ui.Scope, id: []const u8) !*ui.Node {
        const trigger = try scope.createState(EntryTrigger, .{ .view = self, .node = undefined });
        const node = try ui.widgets.Button(.{ .icon_only = true, .icon_asset = ui.icons.get("plug-zap"), .icon_tint = self.tint, .variant = .ghost, .a11y_label = "后台转发列表", .hover_style = self.hover, .on_click = self.cx.on(EntryTrigger, trigger, EntryTrigger.open) }).mount(scope, self.cx);
        trigger.node = node;
        node.meta.ownership.meta.test_id = id;
        node.setDisplay(.none);
        return node;
    }
    const EntryTrigger = struct {
        view: *View,
        node: *ui.Node,
        fn open(self: *@This()) void {
            self.view.show(null, self.node);
        }
    };
    fn anchorRect(raw: *anyopaque) ui.widgets.popover.AnchorRect {
        const self: *View = @ptrCast(@alignCast(raw));
        return .{ .x = self.anchor.x, .y = self.anchor.y, .w = self.anchor.w, .h = self.anchor.h };
    }
    pub fn show(self: *View, asset: ?identity.ConnectionId, anchor: *ui.Node) void {
        self.showAt(asset, anchor.globalRect());
    }
    pub fn showAt(self: *View, asset: ?identity.ConnectionId, anchor: ui.ComputedRect) void {
        self.filter = asset;
        self.last_hash = null;
        self.anchor = anchor;
        self.popover.show.invoke();
        self.cx.requestRedraw();
    }
    pub fn update(self: *View, rows: []const M.Row) !void {
        var hash = std.hash.Wyhash.init(0);
        std.hash.autoHash(&hash, self.filter);
        hash.update(std.mem.asBytes(&self.cx.viewport.width));
        hash.update(std.mem.asBytes(&self.cx.viewport.height));
        for (rows) |row| {
            std.hash.autoHash(&hash, row.owner);
            std.hash.autoHash(&hash, row.source);
            std.hash.autoHash(&hash, row.phase);
            std.hash.autoHash(&hash, row.local_port);
            std.hash.autoHash(&hash, row.connections);
            std.hash.autoHash(&hash, if (row.failure) |err| @intFromError(err) else @as(u16, 0));
            hash.update(row.name);
        }
        const next = hash.final();
        if (self.last_hash != null and self.last_hash.? == next) return;
        for (self.list.content.children.items) |node| self.cx.invalidateReferencesTo(node);
        if (self.row_scope) |old| old.dispose();
        self.row_scope = null;
        while (self.list.content.children.items.len > 0) {
            const node = self.list.content.children.items[self.list.content.children.items.len - 1];
            self.cx.detachChild(self.list.content, node);
            self.cx.destroyDetached(node);
        }
        if (self.revision == std.math.maxInt(u64)) return error.RevisionExhausted;
        self.revision += 1;
        const scope = try self.popover.scope.childScope();
        self.row_scope = scope;
        var shown: usize = 0;
        for (rows) |row| {
            if (self.filter) |filter| if (row.source.id != filter) continue;
            try self.addRow(scope, row);
            shown += 1;
        }
        if (shown == 0) {
            // panel-heads：原生空状态（标题 + 说明）。
            const empty = try ui.view.render(scope, self.cx, ui.widgets.Empty(.{ .icon = ui.icons.get("plug-zap").?, .title = "没有后台转发", .description = "不占用终端页签、在后台运行的端口转发会列在这里。" }));
            empty.meta.ownership.meta.test_id = "socks.background.empty";
            try self.list.content.appendChild(self.cx.allocator, empty);
        }
        var buffer: [64]u8 = undefined;
        self.count_text.set(try std.fmt.bufPrint(&buffer, "后台转发 ×{d}", .{rows.len}));
        self.remote_entry.setDisplay(if (rows.len == 0) .none else .flex);
        self.local_entry.setDisplay(if (rows.len == 0) .none else .flex);
        // 空状态（图标 · 标题 · 说明）要比一行转发高，给它留出 200。
        const height = if (shown == 0) @min(@as(f32, 200), @max(0, @min(420, self.cx.viewport.height - 16))) else @min(@max(@as(f32, 128), 67 + @as(f32, @floatFromInt(shown)) * 64 + @as(f32, @floatFromInt(shown -| 1)) * 6), @max(0, @min(420, self.cx.viewport.height - 16)));
        self.popover.content.setStyleInline(self.cx.allocator, S.panel(height, self.cx.viewport.width));
        self.last_hash = next;
        self.cx.requestRedraw();
    }
    fn addRow(self: *View, scope: *ui.Scope, row: M.Row) !void {
        const node = try ui.box(self.cx, S.row(), .{});
        node.meta.ownership.meta.test_id = "socks.background.row";
        const labels = try ui.box(self.cx, .{ .width = .fill(), .min_width = 0, .direction = .column, .gap = 3 }, .{});
        const title = try std.fmt.allocPrint(self.cx.allocator, "{s} #{d}", .{ row.name, @backingInt(row.owner.session_id) });
        defer self.cx.allocator.free(title);
        try labels.appendChild(self.cx.allocator, try ui.text(self.cx, title, S.text(11.5, 500, 17, S.theme.current().fg_1)));
        var buffer: [160]u8 = undefined;
        const status = if (row.local_port) |port| try std.fmt.bufPrint(&buffer, ":{d} · {s} · {d} 个连接", .{ port, M.phaseLabel(row.phase), row.connections }) else try std.fmt.bufPrint(&buffer, "{s}{s}{s}", .{ M.phaseLabel(row.phase), if (row.failure != null) " · " else "", if (row.failure) |err| @import("../../../../shared/base/error_text.zig").lineOr(err, "原因见应用日志") else "" });
        const state = try ui.text(self.cx, status, S.text(10.5, 400, 16, S.ink(row.phase)));
        state.meta.ownership.meta.test_id = "socks.background.state";
        try labels.appendChild(self.cx.allocator, state);
        try node.appendChild(self.cx.allocator, labels);
        for ([_]Action{ .open_terminal, .reconnect, .stop }, [_][]const u8{ "terminal", "refresh-cw", "square" }, [_][]const u8{ "打开终端", "重新连接", "停止后台转发" }) |action, icon, label| {
            const enabled = switch (action) {
                .open_terminal => true,
                .reconnect => row.phase == .paused or row.phase == .failed,
                .stop => row.phase != .closing,
            };
            const capture = try scope.createState(RowAction, .{ .view = self, .owner = row.owner, .revision = self.revision, .action = action });
            const button = try ui.widgets.Button(.{ .variant = .ghost, .icon_only = true, .icon_asset = ui.icons.get(icon), .icon_size = @as(f32, 18), .icon_tint = self.tint, .a11y_label = label, .base_style = S.action(24), .hover_style = self.hover, .disabled = !enabled, .on_click = self.cx.on(RowAction, capture, RowAction.run) }).mount(scope, self.cx);
            button.meta.ownership.meta.test_id = switch (action) {
                .open_terminal => "socks.background.open_terminal",
                .reconnect => "socks.background.reconnect",
                .stop => "socks.background.stop",
            };
            try node.appendChild(self.cx.allocator, button);
        }
        try self.list.content.appendChild(self.cx.allocator, node);
    }
    const RowAction = struct {
        view: *View,
        owner: identity.SessionHandle,
        revision: u64,
        action: Action,
        fn run(self: *@This()) void {
            if (self.view.revision != self.revision) return;
            self.view.hooks.action(self.view.hooks.context, self.owner, self.action);
            if (self.action == .open_terminal) self.view.popover.close.invoke();
        }
    };
};
