//! Read-only frozen event snapshot. No Manager/engine mutation or current-owner lookup.
const std = @import("std");
const ui = @import("ui");
const overlay = @import("../../../shared/ui/overlay/overlay_host.zig");
const S = @import("transfer_events_styles.zig");
const panel_header = @import("../../../shared/ui/components/panel_header/panel_header.zig");
const theme = @import("../../../shared/ui/theme/app_theme.zig");
pub const View = struct {
    cx: *ui.Cx,
    open: *ui.Signal(bool),
    /// The popover's place in the tree: an own zero-size box holding the (manual, empty) trigger.
    root: *ui.Node = undefined,
    /// Own content column inside the native popover panel.
    body: *ui.Node = undefined,
    title: *ui.Node = undefined,
    entries: *ui.Node = undefined,
    /// 没有事件时的原生空状态（与事件行二选一显示）。
    empty: *ui.Node = undefined,
    snapshot: []const u8 = "",
    job: u64 = 0,
    anchor_id: ?u32 = null,
    viewport: *ui.Node = undefined,
    content: *ui.Node = undefined,
    colors: theme.Colors = undefined,
    pub fn mount(cx: *ui.Cx, scope: *ui.Scope) !*View {
        const self = try scope.createState(View, .{ .cx = cx, .open = try scope.createSignal(bool, false), .colors = theme.current() });
        try scope.onCleanup(View, self, cleanup);
        const popover = try overlay.Popover(.panel, .{
            .open = self.open,
            .trigger = .manual,
            .anchor = .{ .virtual = .{ .ctx = self, .getRect = anchorRect } },
            .position = .top_end,
            .offset = .{ .static = 8 },
            .width = S.width,
            .max_height = S.max_height,
            .constrain_width_to_viewport = true,
            .viewport_padding = @as(f32, 8),
            .a11y_role = .dialog,
            .on_open_change = cx.on(View, self, changed),
        }).mount(scope, cx);
        // The panel (surface, radius, shadow, padding) is the native Popover's default; nothing is written on it.
        self.root = try ui.boxStyled(cx, S.anchor, .{});
        try self.root.appendChild(cx.allocator, popover.wrapper);
        try cx.root.?.appendChild(cx.allocator, self.root);
        const body = try ui.boxStyled(cx, S.body, .{});
        self.body = body;
        try popover.content.appendChild(cx.allocator, body);
        body.meta.ownership.meta.test_id = "transfer.events.dialog";
        const head = try ui.boxStyled(cx, S.row, .{});
        try head.appendChild(cx.allocator, try ui.iconTint(cx, ui.icons.get("file-clock").?, theme.current().accent, .{ .width = .{ .px = 18 }, .height = .{ .px = 18 } }));
        self.title = try ui.textStyled(cx, S.title, "任务事件");
        try head.appendChild(cx.allocator, self.title);
        try head.appendChild(cx.allocator, try ui.spacer(cx));
        // panel-heads：统一关闭按钮（`Popover(.panel)` 按 Esc 关闭）。
        try head.appendChild(cx.allocator, try panel_header.mountClose(popover.scope, cx, .{ .label = "关闭任务事件", .test_id = "transfer.events.dismiss", .on_close = cx.on(View, self, close) }));
        try body.appendChild(cx.allocator, head);
        const scroll = try ui.widgets.ScrollArea(.{ .direction = .vertical, .rubber_band_y = false }).mount(popover.scope, cx);
        // The native ScrollArea fills this own box; the box carries the height.
        const viewport = try ui.boxStyled(cx, S.viewport, .{});
        viewport.meta.ownership.meta.test_id = "transfer.events.viewport";
        try viewport.appendChild(cx.allocator, scroll.container);
        self.entries = try ui.boxStyled(cx, S.eventList, .{});
        self.entries.meta.ownership.meta.test_id = "transfer.events.entries";
        try scroll.content.appendChild(cx.allocator, self.entries);
        // panel-heads：原生空状态（标题 + 说明）。
        self.empty = try ui.view.render(popover.scope, cx, ui.widgets.Empty(.{ .icon = ui.icons.get("file-clock").?, .title = "暂无任务事件", .description = "这个任务的排队、传输与结果事件会记录在这里。" }));
        self.empty.meta.ownership.meta.test_id = "transfer.events.empty";
        self.empty.setDisplay(.none);
        try scroll.content.appendChild(cx.allocator, self.empty);
        try body.appendChild(cx.allocator, viewport);
        self.viewport = viewport;
        self.content = scroll.content;
        try cx.addAfterLayoutHook(self, layout);
        return self;
    }
    pub fn show(self: *View, job: u64, entries: []const u8, anchor: *ui.Node) !void {
        self.job = job;
        self.anchor_id = anchor.id;
        var buffer: [80]u8 = undefined;
        try self.title.setTextContent(self.cx.allocator, try std.fmt.bufPrint(&buffer, "任务事件 · #{d}", .{job}));
        const snapshot = try self.cx.allocator.dupe(u8, entries);
        while (self.entries.children.items.len > 0) {
            const child = self.entries.children.items[0];
            self.entries.removeChild(child);
            self.cx.destroyDetached(child);
        }
        self.cx.allocator.free(self.snapshot);
        self.snapshot = snapshot;
        self.empty.setDisplay(if (snapshot.len == 0) .flex else .none);
        var lines = std.mem.splitScalar(u8, snapshot, '\n');
        while (lines.next()) |line| {
            if (snapshot.len == 0) break;
            const row = try ui.boxStyled(self.cx, S.eventRow, .{});
            try self.entries.appendChild(self.cx.allocator, row);
            const entry = try ui.textStyled(self.cx, S.entries, line);
            entry.setStyleInline(self.cx.allocator, .{ .width = .fill(), .flex_shrink = 0 });
            entry.meta.ownership.meta.test_id = "transfer.events.entry";
            try row.appendChild(self.cx.allocator, entry);
            try @import("../../../shared/ui/styles/log_typography.zig").apply(self.cx, entry);
        }
        self.open.set(true);
    }
    /// Virtual-list refreshes replace buttons. Retain only the current node ID.
    pub fn reanchor(self: *View, job: u64, anchor: *ui.Node) void {
        if (self.job == job) self.anchor_id = anchor.id;
    }
    fn findAnchor(self: *View) ?*ui.Node {
        return findNode(self.cx.root orelse return null, self.anchor_id orelse return null);
    }
    fn findNode(node: *ui.Node, wanted: u32) ?*ui.Node {
        if (node.id == wanted) return node;
        for (node.children.items) |child| if (findNode(child, wanted)) |found| return found;
        return null;
    }
    fn anchorRect(raw: *anyopaque) ui.widgets.popover.AnchorRect {
        const self: *View = @ptrCast(@alignCast(raw));
        const node = self.findAnchor() orelse return .{ .x = -1e6, .y = -1e6, .w = 0, .h = 0 };
        const rect = node.globalRect();
        return .{ .x = rect.x, .y = rect.y, .w = rect.w, .h = rect.h };
    }
    fn layout(raw: *anyopaque, _: u8, _: bool) ui.AfterLayoutResult {
        const self: *View = @ptrCast(@alignCast(raw));
        if (!self.open.peek()) return .done;
        const anchor = self.findAnchor() orelse {
            self.close();
            return .done;
        };
        if (!anchor.isDisplayedInTree()) {
            self.close();
            return .done;
        }
        const rect = anchor.globalRect();
        const top = self.cx.safe_area_top + 8;
        const bottom = self.cx.viewport.height - self.cx.safe_area_bottom - 8;
        // A freshly rebuilt virtual row is measured in the next layout round.
        if (rect.w <= 0 or rect.h <= 0) return .done;
        // Only the event rows scroll when space is tight: the own viewport box takes the height the
        // side with more room allows (header and panel padding reserved); the native panel fits it.
        const available = @max(rect.y - top - 8, bottom - rect.y - rect.h - 8);
        const height = @min(@max(16, self.content.globalRect().h), @max(0, @min(S.viewport_max, available - S.reserved)));
        if (self.viewport.style.height == .px and @abs(self.viewport.style.height.px - height) < 0.1) return .done;
        self.viewport.setStyleInline(self.cx.allocator, .{ .height = .{ .px = height } });
        return .needs_layout;
    }
    pub fn retheme(self: *View) void {
        @import("transfer_styles.zig").repaint(self.body, self.colors);
        self.colors = theme.current();
    }
    pub fn close(self: *View) void {
        self.open.set(false);
    }
    fn changed(self: *View, open: bool) void {
        self.open.set(open);
    }
    fn cleanup(self: *View) void {
        self.cx.removeAfterLayoutHook(self);
        self.cx.allocator.free(self.snapshot);
    }
};
