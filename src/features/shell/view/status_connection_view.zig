//! Captured SSH identity. No native session lookup, reconnection or clipboard
//! access occurs here; actions retain the original complete operation key.
const std = @import("std");
const ui = @import("ui");
const overlay = @import("../../../shared/ui/overlay/overlay_host.zig");
const panel_header = @import("../../../shared/ui/components/panel_header/panel_header.zig");
pub const details = @import("../../../proto/ssh/connection_details.zig");
pub const OperationKey = details.OperationKey;
const S = @import("status_connection_styles.zig");
pub const State = enum { unknown, online, disconnected };
pub const Snapshot = struct {
    key: OperationKey,
    revision: u64,
    endpoint: details.Endpoint,
    state: State = .unknown,
    connected_duration_ms: ?u64 = null,
    latency_ms: ?u64 = null,
    utf8: ?bool = null,
    grid: ?struct { cols: u16, rows: u16 } = null,
    cipher_c2s: details.Text(64) = .{},
    cipher_s2c: details.Text(64) = .{},
    route: [details.max_hops]details.Endpoint = @splat(.{}),
    hop_count: usize,
    logs_available: bool = false,
    can_reconnect: bool = false,
};
/// Live session facts owned elsewhere (SOCKS forward host, group broadcast),
/// read when the card refreshes. Null sections are omitted, never invented.
pub const Extras = struct {
    forward: ?Forward = null,
    broadcast: ?Broadcast = null,
    pub const Forward = struct { detail: details.Text(64) = .{}, active: bool };
    pub const Broadcast = struct { enabled: bool, available: bool = true };
};
pub const ExtrasProvider = struct {
    context: *anyopaque,
    read: *const fn (*anyopaque, OperationKey) Extras,
    /// Existing actions: the SOCKS panel and the group broadcast toggle.
    open_forward: ?*const fn (*anyopaque) void = null,
    toggle_broadcast: ?*const fn (*anyopaque) void = null,
};
pub const Callbacks = struct {
    context: *anyopaque,
    copy: *const fn (*anyopaque, OperationKey, []const u8) anyerror!void,
    logs: ?*const fn (*anyopaque, OperationKey) anyerror!void = null,
    reconnect: ?*const fn (*anyopaque, OperationKey) anyerror!void = null,
};
const Action = struct {
    view: *View,
    key: OperationKey,
    kind: enum { close, copy, logs },
    fn click(self: *Action) void {
        const view = self.view;
        if (!view.visible or view.source == null or !view.source.?.key.eql(self.key)) return;
        switch (self.kind) {
            .close => view.hide(),
            .copy => view.copyAddress(),
            .logs => {
                if (!view.source.?.logs_available or view.callbacks.logs == null) return;
                view.callbacks.logs.?(view.callbacks.context, self.key) catch {
                    view.feedback("无法打开连接日志", false);
                    return;
                };
                view.hideWithoutFocus();
            },
        }
    }
    fn cleanup(self: *Action) void {
        self.view.cx.allocator.destroy(self);
    }
};
pub const View = struct {
    cx: *ui.Cx,
    scope: *ui.Scope,
    callbacks: Callbacks,
    root: *ui.Node = undefined,
    chrome: *ui.Node = undefined,
    content: *ui.Node = undefined,
    open: *ui.Signal(bool),
    logs_disabled: *ui.Signal(bool),
    source: ?Snapshot = null,
    expired: bool = false,
    visible: bool = false,
    dirty: bool = false,
    rebuild: bool = false,
    content_scope: ?*ui.Scope = null,
    /// What the card is attached to, given by whoever shows it (`show`).
    attached: ?Anchor = null,
    anchor_rect: ui.widgets.popover.AnchorRect = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
    status_top: f32 = 0,
    viewport: ui.Size = .ZERO,
    pointer: *ui.Node = undefined,
    name: *ui.Node = undefined,
    state: *ui.Node = undefined,
    state_text: *ui.Signal([]const u8),
    address: *ui.Node = undefined,
    session: *ui.Node = undefined,
    duration: *ui.Node = undefined,
    route: *ui.Node = undefined,
    hops: *ui.Node = undefined,
    feedback_label: *ui.Node = undefined,
    logs_button: *ui.Node = undefined,
    copy_button: *ui.Node = undefined,
    copy_feedback: *@import("../../../shared/ui/components/copy_button/copy_button.zig").Button = undefined,
    close_button: *ui.Node = undefined,
    scroll: ui.widgets.ScrollAreaResult = undefined,
    latency: *ui.Node = undefined,
    cipher: *ui.Node = undefined,
    encoding: *ui.Node = undefined,
    grid: *ui.Node = undefined,
    heartbeat: [3]*ui.Node = undefined,
    extras: ?ExtrasProvider = null,
    chips: *ui.Node = undefined,
    forward_row: *ui.Node = undefined,
    forward_detail: *ui.Node = undefined,
    forward_on: *ui.Signal(bool) = undefined,
    broadcast_row: *ui.Node = undefined,
    broadcast_on: *ui.Signal(bool) = undefined,
    broadcast_disabled: *ui.Signal(bool) = undefined,

    pub fn mount(cx: *ui.Cx, scope: *ui.Scope, callbacks: Callbacks) !*View {
        const self = try cx.allocator.create(View);
        var registered = false;
        errdefer if (!registered) cx.allocator.destroy(self);
        self.* = .{ .cx = cx, .scope = scope, .callbacks = callbacks, .open = try scope.createSignal(bool, false), .state_text = try scope.createSignal([]const u8, "未知"), .logs_disabled = try scope.createSignal(bool, true) };
        try scope.onCleanup(View, self, cleanup);
        registered = true;
        const focus_guard = try scope.childScope();
        const popup = try overlay.Popover(.panel, .{ .open = self.open, .trigger = .manual, .close_on_outside_click = true, .consume_outside_click = false, .anchor = .{ .virtual = .{ .ctx = self, .getRect = anchor } }, .position = .top_start, .width = S.width, .max_width = S.width, .max_height = S.height, .offset = .{ .static = S.anchor_gap }, .viewport_padding = S.margin, .constrain_width_to_viewport = true, .flip = true, .shift_main_axis = false, .on_open_change = cx.on(View, self, openChanged) }).mount(scope, cx);
        self.scope = popup.scope;
        self.root = popup.wrapper;
        self.chrome = popup.chrome;
        self.content = popup.content;
        try focus_guard.onCleanup(View, self, releaseFocus);
        self.root.setStyleInline(cx.allocator, S.wrapper());
        self.chrome.setStyleInline(cx.allocator, S.panel(S.height, cx.viewport.width));
        self.chrome.meta.ownership.meta.test_id = "status.connection";
        return self;
    }
    /// What the card attaches to. The caller owns the region (the active tab under the workspace
    /// identity region, the status bar's identity chip) and answers for it; the card never looks
    /// for nodes in the window tree.
    pub const Anchor = struct {
        ctx: *anyopaque,
        /// The region's current window rect, or null while it is not shown (the card closes).
        rect: *const fn (ctx: *anyopaque) ?ui.ComputedRect,
        /// Takes focus back when the card is dismissed (the control that opened it), if any.
        focus: ?*const fn (ctx: *anyopaque, cx: *ui.Cx) void = null,

        pub fn eql(a: Anchor, b: Anchor) bool {
            return a.ctx == b.ctx and a.rect == b.rect;
        }
        /// A control the caller keeps alive for as long as the card may be shown: the card
        /// attaches to the control itself and returns focus to it.
        pub fn control(node: *ui.Node) Anchor {
            return .{ .ctx = node, .rect = struct {
                fn rect(raw: *anyopaque) ?ui.ComputedRect {
                    const target: *ui.Node = @ptrCast(@alignCast(raw));
                    const r = target.globalRect();
                    return if (target.isDisplayedInTree() and r.w > 0) r else null;
                }
            }.rect, .focus = struct {
                fn focus(raw: *anyopaque, cx: *ui.Cx) void {
                    cx.setFocus(@ptrCast(@alignCast(raw)));
                }
            }.focus };
        }
    };
    pub fn show(self: *View, source: Snapshot, anchor_source: Anchor, status_top: f32) !void {
        try validate(source);
        if (!std.math.isFinite(status_top) or status_top < 0) return error.InvalidAnchor;
        if (self.visible and self.source != null and self.source.?.key.eql(source.key) and self.attached != null and self.attached.?.eql(anchor_source)) {
            self.hide();
            return;
        }
        const changed = self.source == null or !self.source.?.key.eql(source.key);
        if (changed) {
            self.source = source;
            self.expired = false;
            self.rebuild = true;
        } else if (!self.expired) try self.update(source);
        const rect = anchor_source.rect(anchor_source.ctx) orelse return error.InvalidAnchor;
        self.attached = anchor_source;
        self.status_top = if (rect.y < self.cx.viewport.height / 2) rect.y else status_top;
        self.anchor_rect = .{ .x = rect.x, .y = if (rect.y < self.cx.viewport.height / 2) rect.y else status_top, .w = rect.w, .h = if (rect.y < self.cx.viewport.height / 2) rect.h else 0 };
        self.visible = true;
        self.open.set(true);
        self.dirty = true;
        try self.flush();
    }
    pub fn update(self: *View, source: Snapshot) !void {
        try validate(source);
        const current = self.source orelse return error.ConnectionNotVisible;
        if (!current.key.eql(source.key)) return error.ConnectionOwnerMismatch;
        if (self.expired or source.revision < current.revision) return error.StaleConnection;
        if (!std.meta.eql(source.endpoint, current.endpoint) or source.hop_count != current.hop_count or !std.meta.eql(source.route, current.route)) return error.FrozenEndpointChanged;
        // `revision` versions only the connection details. The card also shows the session's live
        // facts (terminal grid and encoding, lifecycle state, retry permission), which change
        // without it — a resize changes only the grid. Unchanged means every shown fact is equal.
        if (std.meta.eql(source, current)) return;
        self.source = source;
        self.dirty = true;
        self.cx.requestRedraw();
    }
    pub fn invalidate(self: *View, key: OperationKey) void {
        if (self.source == null or !self.source.?.key.eql(key) or self.expired) return;
        self.expired = true;
        self.dirty = true;
        self.cx.requestRedraw();
    }
    pub fn reanchor(self: *View, status_top: f32) void {
        if (!self.visible) return;
        const source = self.attached orelse return;
        const rect = source.rect(source.ctx) orelse {
            self.hideWithoutFocus();
            return;
        };
        const next: ui.widgets.popover.AnchorRect = .{ .x = rect.x, .y = if (rect.y < self.cx.viewport.height / 2) rect.y else status_top, .w = rect.w, .h = if (rect.y < self.cx.viewport.height / 2) rect.h else 0 };
        if (std.meta.eql(next, self.anchor_rect)) return;
        self.status_top = if (rect.y < self.cx.viewport.height / 2) rect.y else status_top;
        self.anchor_rect = next;
        self.dirty = true;
        self.chrome.markLayoutDirty();
        self.cx.requestRedraw();
    }
    pub fn flush(self: *View) !void {
        if (!self.visible or self.source == null) return;
        if (!std.meta.eql(self.viewport, self.cx.viewport)) {
            self.viewport = self.cx.viewport;
            self.dirty = true;
        }
        if (self.rebuild or self.content_scope == null) {
            try self.build();
            self.rebuild = false;
            self.dirty = true;
        }
        const h = @min(S.height, @max(0, (if (self.status_top < self.cx.viewport.height / 2) self.cx.viewport.height - self.status_top - self.anchor_rect.h else self.status_top) - S.anchor_gap - S.margin));
        const w = @min(S.width, @max(0, self.cx.viewport.width - S.margin * 2));
        // The opening effect restores fit sizing. Retain the bounded card
        // even when no new SSH sample arrives after that effect.
        if (self.chrome.style.height != .px or self.chrome.style.height.px != h or self.chrome.style.width != .px or self.chrome.style.width.px != w) {
            self.chrome.setStyleInline(self.cx.allocator, S.panel(h, self.cx.viewport.width));
            self.dirty = true;
        }
        if (!self.dirty) return;
        self.dirty = false;
        const x = @min(@max(S.margin, self.alignedAnchor(self.anchor_rect).x), @max(S.margin, self.cx.viewport.width - w - S.margin));
        self.pointer.setStyleInline(self.cx.allocator, S.pointer(@min(@max(14, self.anchor_rect.x + self.anchor_rect.w / 2 - x - 6), @max(14, w - 26))));
        try self.refresh();
        self.cx.requestRedraw();
    }
    pub fn retheme(self: *View) !void {
        self.rebuild = true;
        try self.flush();
    }
    pub fn isVisible(self: *const View) bool {
        return self.visible;
    }
    pub fn hide(self: *View) void {
        self.hideWithoutFocus();
        const source = self.attached orelse return;
        if (source.focus) |focus| if (source.rect(source.ctx) != null) focus(source.ctx, self.cx);
    }
    /// Context changes must not steal focus back from the newly selected pane.
    pub fn dismiss(self: *View) void {
        self.hideWithoutFocus();
    }
    fn hideWithoutFocus(self: *View) void {
        if (!self.visible and !self.open.peek()) return;
        self.visible = false;
        self.open.set(false);
        self.cx.requestRedraw();
    }
    fn openChanged(self: *View, value: bool) void {
        if (!value and self.visible) self.hide();
    }
    fn build(self: *View) !void {
        clear(self.cx, self.content);
        // Remove custom siblings while retaining the public Popover content.
        var index: usize = 0;
        while (index < self.chrome.children.items.len) {
            const node = self.chrome.children.items[index];
            if (node == self.content or @import("background_layers.zig").isSurface(node)) {
                index += 1;
                continue;
            }
            self.cx.detachChild(self.chrome, node);
            self.cx.destroyDetached(node);
        }
        if (self.content_scope) |old| old.dispose();
        const scope = try self.scope.childScope();
        self.content_scope = scope;
        self.content.setStyleInline(self.cx.allocator, S.content());
        const header = try ui.box(self.cx, S.header(), .{});
        try header.appendChild(self.cx.allocator, try ui.iconTint(self.cx, ui.icons.terminal, S.theme.current().accent, S.icon(16)));
        _ = try label(self.cx, header, "会话详情", S.title(), S.titleBox());
        try header.appendChild(self.cx.allocator, try ui.spacer(self.cx));
        // panel-heads：统一关闭按钮（`Popover(.panel)` 按 Esc 关闭）。
        const close_action = try self.newAction(scope, .close);
        var close_button: ?*ui.Node = null;
        try header.appendChild(self.cx.allocator, try panel_header.mountClose(scope, self.cx, .{ .label = "关闭会话详情", .test_id = "status.connection.close", .on_close = self.cx.on(Action, close_action, Action.click), .button = &close_button }));
        self.close_button = close_button.?;
        try self.content.appendChild(self.cx.allocator, header);
        try self.content.appendChild(self.cx.allocator, try ui.box(self.cx, .{ .height = .{ .px = 12 }, .flex_shrink = 0 }, .{}));
        self.scroll = try ui.widgets.ScrollArea(.{ .direction = .vertical, .rubber_band_y = false }).mount(scope, self.cx);
        self.scroll.container.setStyleInline(self.cx.allocator, S.scroll());
        self.scroll.container.meta.ownership.meta.test_id = "status.connection.viewport";
        self.scroll.content.setStyleInline(self.cx.allocator, S.body());
        try self.content.appendChild(self.cx.allocator, self.scroll.container);
        const summary = try ui.box(self.cx, .{ .width = .fill(), .height = .{ .fit = .{} }, .padding = ui.Padding.all(10), .direction = .column, .gap = 4, .margin = .{ .bottom = 4 }, .background = S.theme.popupInset(), .border = .{ .radius = 8 }, .flex_shrink = 0 }, .{});
        const name_row = try ui.box(self.cx, S.row(24), .{});
        try summary.appendChild(self.cx.allocator, name_row);
        self.name = try label(self.cx, name_row, "", @import("../../connections/progress/view/connection_details_styles.zig").text(15, 600, 24, false), .{ .width = .fill(), .height = .{ .px = 24 }, .min_width = 0, .flex = 1, .overflow_hidden = true });
        self.name.meta.ownership.meta.test_id = "status.connection.name";
        const health = try ui.box(self.cx, .{ .height = .{ .px = 24 }, .direction = .row, .align_items = .center, .gap = 6, .flex_shrink = 0 }, .{});
        const tip = try ui.widgets.Tooltip(.{ .text = self.state_text, .background = S.theme.current().overlay, .text_color = S.theme.current().fg_1 }).mount(scope, self.cx);
        try tip.trigger.appendChild(self.cx.allocator, health);
        tip.wrapper.setStyleInline(self.cx.allocator, .{ .flex_shrink = 0 });
        try name_row.appendChild(self.cx.allocator, tip.wrapper);
        // Keep the tooltip's text node so state refreshes without remounting.
        self.state = tip.content.children.items[0];
        self.state.meta.ownership.meta.test_id = "status.connection.state";
        for ([_]ui.SvgAsset{ ui.icons.activity, ui.icons.get("unplug").?, ui.icons.get("circle-help").? }, 0..) |asset, i| {
            self.heartbeat[i] = try ui.iconTint(self.cx, asset, S.theme.current().fg_3, S.icon(14));
            try health.appendChild(self.cx.allocator, self.heartbeat[i]);
        }
        health.meta.ownership.meta.test_id = "status.connection.health";
        self.latency = try label(self.cx, health, "", S.infoText(false), .{ .height = .{ .px = 18 }, .flex_shrink = 0 });
        self.latency.meta.ownership.meta.test_id = "status.connection.latency";
        const address_row = try ui.box(self.cx, S.row(28), .{});
        try summary.appendChild(self.cx.allocator, address_row);
        self.address = try label(self.cx, address_row, "", S.address(), .{ .width = .fill(), .height = .{ .px = 20 }, .min_width = 0, .flex = 1, .overflow_hidden = true });
        self.address.meta.ownership.meta.test_id = "status.connection.address";
        self.copy_button = try self.button(scope, address_row, .copy, "复制信息", "status.connection.copy", ui.icons.copy, 28, false, null);
        self.copy_feedback = try @import("../../../shared/ui/components/copy_button/copy_button.zig").Button.attach(self.cx, scope, self.copy_button);
        self.logs_button = try self.button(scope, address_row, .logs, "连接日志", "status.connection.logs", ui.icons.get("file-text").?, 28, false, self.logs_disabled);
        try self.scroll.content.appendChild(self.cx.allocator, summary);
        _ = try self.factValue("协议", "SSH · 交互式 Shell", "status.connection.protocol");
        self.cipher = try self.fact("加密", "status.connection.cipher");
        self.encoding = try self.fact("编码", "status.connection.encoding.detail");
        self.grid = try self.fact("网格", "status.connection.grid.detail");
        self.session = try self.fact("会话", "status.connection.session");
        self.duration = try label(self.cx, self.session.parent.?, "", S.infoText(true), .{ .width = .{ .px = 66 }, .height = .{ .px = 18 }, .flex_shrink = 0 });
        self.duration.meta.ownership.meta.test_id = "status.connection.duration";
        self.route = try self.fact("路径", "status.connection.route");
        // Pencil lBTBA: the route reads as chips (本机 › hops › target) under
        // "通信链路"; the text fact stays for copy/a11y but is not shown.
        self.route.parent.?.setDisplay(.none);
        _ = try label(self.cx, self.scroll.content, "通信链路", S.sectionLabel(), .{ .width = .fill(), .height = .{ .px = 18 }, .margin = .{ .top = 8 }, .flex_shrink = 0 });
        self.chips = try ui.box(self.cx, S.routeRow(), .{});
        self.chips.meta.ownership.meta.test_id = "status.connection.route.chips";
        try self.scroll.content.appendChild(self.cx.allocator, self.chips);
        self.forward_on = try scope.createSignal(bool, false);
        self.broadcast_on = try scope.createSignal(bool, false);
        self.broadcast_disabled = try scope.createSignal(bool, false);
        self.forward_row = try self.toggleRow(scope, "端口转发", "status.connection.forward.row", self.forward_on, null, onForwardToggle);
        self.forward_detail = self.forward_row.children.items[0].children.items[1];
        self.broadcast_row = try self.toggleRow(scope, "输入广播", "status.connection.broadcast.row", self.broadcast_on, self.broadcast_disabled, onBroadcastToggle);
        try self.broadcast_row.children.items[0].children.items[1].setTextContent(self.cx.allocator, "把输入同步给组内终端");
        self.forward_row.setStyleInline(self.cx.allocator, .{ .margin = .{ .top = 6 } });
        // Retain the captured hop summary for existing host/test consumers.
        self.hops = try label(self.cx, self.scroll.content, "", S.infoText(true), S.factValue());
        self.hops.setDisplay(.none);
        self.feedback_label = try label(self.cx, self.scroll.content, "", S.infoText(true), S.feedbackBox());
        self.feedback_label.setDisplay(.none);
        self.pointer = try ui.iconTint(self.cx, ui.icons.chevron_down, S.theme.current().fg_3, S.icon(12));
        self.pointer.setDisplay(.none);
        try self.chrome.appendChild(self.cx.allocator, self.pointer);
    }
    fn fact(self: *View, title: []const u8, test_id: []const u8) !*ui.Node {
        return self.factValue(title, "", test_id);
    }
    fn factValue(self: *View, title: []const u8, value: []const u8, test_id: []const u8) !*ui.Node {
        const row = try ui.box(self.cx, S.info(), .{});
        _ = try label(self.cx, row, title, S.infoText(false), S.factLabel());
        const node = try label(self.cx, row, value, S.infoText(true), S.factValue());
        node.meta.ownership.meta.test_id = test_id;
        try self.scroll.content.appendChild(self.cx.allocator, row);
        return node;
    }
    fn newAction(self: *View, scope: *ui.Scope, kind: @FieldType(Action, "kind")) !*Action {
        const value = try self.cx.allocator.create(Action);
        errdefer self.cx.allocator.destroy(value);
        value.* = .{ .view = self, .key = self.source.?.key, .kind = kind };
        try scope.onCleanup(Action, value, Action.cleanup);
        return value;
    }
    fn button(self: *View, scope: *ui.Scope, parent: *ui.Node, kind: @FieldType(Action, "kind"), name: []const u8, test_id: []const u8, asset: ui.SvgAsset, size: f32, surface: bool, disabled: ?*ui.Signal(bool)) !*ui.Node {
        const action = try self.newAction(scope, kind);
        const disabled_signal = disabled orelse try scope.createSignal(bool, false);
        const button_node = try ui.widgets.Button(.{ .variant = .ghost, .a11y_label = name, .base_style = S.action(size, surface), .hover_style = S.hover(), .disabled = disabled_signal, .on_click = self.cx.on(Action, action, Action.click) }).mount(scope, self.cx);
        button_node.meta.ownership.meta.test_id = test_id;
        try button_node.appendChild(self.cx.allocator, try ui.iconTint(self.cx, asset, S.theme.current().fg_2, S.icon(16)));
        try parent.appendChild(self.cx.allocator, try @import("../../connections/progress/view/connection_details_view.zig").iconTooltip(self.cx, scope, button_node, name));
        return button_node;
    }
    fn toggleRow(self: *View, scope: *ui.Scope, title: []const u8, test_id: []const u8, value: *ui.Signal(bool), disabled: ?*ui.Signal(bool), comptime on_change: fn (*View, bool) void) !*ui.Node {
        const row = try ui.box(self.cx, S.toggleRow(), .{});
        row.meta.ownership.meta.test_id = test_id;
        const copy = try ui.box(self.cx, S.toggleCopy(), .{});
        _ = try label(self.cx, copy, title, S.toggleTitle(), .{ .width = .fill(), .height = .{ .px = 18 }, .min_width = 0 });
        _ = try label(self.cx, copy, "", S.toggleDetail(), .{ .width = .fill(), .height = .{ .px = 16 }, .min_width = 0 });
        try row.appendChild(self.cx.allocator, copy);
        const toggle = try ui.widgets.Switch(.{ .checked = value, .label = title, .size = .sm, .disabled = disabled orelse try scope.createSignal(bool, false), .on_change = self.cx.on(View, self, on_change) }).mount(scope, self.cx);
        toggle.meta.ownership.meta.test_id = "status.connection.toggle";
        try row.appendChild(self.cx.allocator, toggle);
        try self.scroll.content.appendChild(self.cx.allocator, row);
        return row;
    }
    /// The switch is a projection: it opens the existing SOCKS panel and
    /// snaps back to the live phase on the next refresh.
    fn onForwardToggle(self: *View, _: bool) void {
        const provider = self.extras orelse return;
        if (provider.open_forward) |open| open(provider.context);
        self.refreshExtras();
    }
    fn onBroadcastToggle(self: *View, _: bool) void {
        const provider = self.extras orelse return;
        if (provider.toggle_broadcast) |toggle| toggle(provider.context);
        self.refreshExtras();
    }
    pub fn refreshExtras(self: *View) void {
        if (self.source == null or self.content_scope == null) return;
        const facts: Extras = if (self.extras) |provider| provider.read(provider.context, self.source.?.key) else .{};
        self.forward_row.setDisplay(if (facts.forward != null) .flex else .none);
        if (facts.forward) |forward| {
            if (self.forward_on.peek() != forward.active) self.forward_on.set(forward.active);
            self.forward_detail.setTextContent(self.cx.allocator, if (forward.detail.len != 0) forward.detail.slice() else "未启动") catch {};
        }
        self.broadcast_row.setDisplay(if (facts.broadcast != null) .flex else .none);
        if (facts.broadcast) |broadcast| {
            if (self.broadcast_on.peek() != broadcast.enabled) self.broadcast_on.set(broadcast.enabled);
            if (self.broadcast_disabled.peek() == broadcast.available) self.broadcast_disabled.set(!broadcast.available);
        }
        self.cx.requestRedraw();
    }
    fn refreshChips(self: *View) !void {
        const source = &self.source.?;
        clear(self.cx, self.chips);
        const total = source.hop_count + 1;
        for (0..total) |index| {
            if (index != 0) {
                const sep = try ui.iconTint(self.cx, ui.icons.chevron_right, S.theme.current().fg_3, S.icon(12));
                try self.chips.appendChild(self.cx.allocator, sep);
            }
            const target = index == total - 1;
            const chip = try ui.box(self.cx, S.hopChip(target), .{});
            const text = if (index == 0) "本机" else blk: {
                const hop = &source.route[index - 1];
                break :blk if (hop.name.len != 0) hop.name.slice() else unknown(hop.host.slice());
            };
            _ = try label(self.cx, chip, text, S.hopText(target), .{ .height = .{ .px = 16 }, .min_width = 0, .flex_shrink = 1 });
            try self.chips.appendChild(self.cx.allocator, chip);
        }
    }
    fn refresh(self: *View) !void {
        const source = &self.source.?;
        try self.refreshChips();
        self.refreshExtras();
        try self.name.setTextContent(self.cx.allocator, if (source.endpoint.name.len != 0) source.endpoint.name.slice() else unknown(source.endpoint.host.slice()));
        // 文案与色调只取 shared/base/connection_presenter.zig：已连上的叫“已连接”（术语表），不写“在线”。
        const shown = @import("../../../shared/base/connection_presenter.zig").present(switch (source.state) {
            .unknown => .unknown,
            .online => .connected,
            .disconnected => .disconnected,
        });
        self.state_text.set(if (self.expired) "已过期" else shown.label);
        const online = !self.expired and source.state == .online;
        const color = if (self.expired) @import("../../../shared/ui/theme/status_tone.zig").ink(.danger) else @import("../../../shared/ui/theme/status_tone.zig").ink(shown.tone);
        const active: usize = if (online) 0 else if (self.expired or source.state == .disconnected) 1 else 2;
        for (self.heartbeat, 0..) |node, i| {
            node.setDisplay(if (i == active) .flex else .none);
            _ = node.setTint(color);
        }
        self.latency.setTextColor(color);

        var buffer: [4096]u8 = undefined;
        try self.latency.setTextContent(self.cx.allocator, if (online and source.latency_ms != null) @import("../../../shared/base/format.zig").duration(&buffer, source.latency_ms.?, .short) else "—");
        const latency_width = @ceil(self.cx.text.measureTextWidth(self.latency.getText().?.content, 12, 400, false)) + 1;
        self.latency.setStyle(self.cx.allocator, .width, .{ .px = latency_width });
        try self.encoding.setTextContent(self.cx.allocator, if (source.utf8 orelse false) "UTF-8" else "未知");
        try self.grid.setTextContent(self.cx.allocator, if (source.grid) |grid| try std.fmt.bufPrint(&buffer, "{d} × {d}", .{ grid.cols, grid.rows }) else "未知");
        const outgoing = source.cipher_c2s.slice();
        const incoming = source.cipher_s2c.slice();
        try self.cipher.setTextContent(self.cx.allocator, if (outgoing.len == 0 and incoming.len == 0) "未知" else if (std.mem.eql(u8, outgoing, incoming)) outgoing else try std.fmt.bufPrint(&buffer, "↑ {s} · ↓ {s}", .{ unknown(outgoing), unknown(incoming) }));
        try self.address.setTextContent(self.cx.allocator, try addressText(&buffer, &source.endpoint));
        try self.session.setTextContent(self.cx.allocator, try std.fmt.bufPrint(&buffer, "会话 {d}", .{@backingInt(source.key.owner.session.session_id)}));
        const duration = if (self.expired or source.state != .online) "未知" else if (source.connected_duration_ms) |ms| if (ms >= 60_000) try std.fmt.bufPrint(&buffer, "{d} 分钟", .{ms / 60_000}) else try std.fmt.bufPrint(&buffer, "{d} 秒", .{ms / 1000}) else "未知";
        try self.duration.setTextContent(self.cx.allocator, duration);
        self.duration.setDisplay(if (self.expired or source.state != .online or source.connected_duration_ms == null) .none else .flex);
        var route_text: std.Io.Writer.Allocating = .init(self.cx.allocator);
        defer route_text.deinit();
        if (source.hop_count == 1) try route_text.writer.writeAll("直连") else {
            for (source.route[0 .. source.hop_count - 1], 0..) |*hop, index| {
                if (index != 0) try route_text.writer.writeAll(" → ");
                try route_text.writer.writeAll(if (hop.name.len != 0) hop.name.slice() else unknown(hop.host.slice()));
            }
            try route_text.writer.writeAll(" → 目标");
        }
        try self.route.setTextContent(self.cx.allocator, route_text.writer.buffered());
        try self.hops.setTextContent(self.cx.allocator, if (source.hop_count == 1) "直连" else try std.fmt.bufPrint(&buffer, "{d} 跳", .{source.hop_count - 1}));
        self.logs_disabled.set(!source.logs_available or self.callbacks.logs == null);
    }
    pub fn copyAddress(self: *View) void {
        if (!self.visible or self.source == null) return;
        const source = &self.source.?;
        var buffer: [4096]u8 = undefined;
        const endpoint = addressText(&buffer, &source.endpoint) catch {
            self.feedback("复制失败，请重试", false);
            return;
        };
        const report = std.fmt.allocPrint(self.cx.allocator, "连接：{s}\n身份：{s}\n协议：SSH · 交互式 Shell\n状态：{s}\n延迟：{s}\n加密：{s}\n会话：{s}\n时长：{s}\n路径：{s}", .{ self.name.getText().?.content, endpoint, self.state_text.peek(), self.latency.getText().?.content, self.cipher.getText().?.content, self.session.getText().?.content, self.duration.getText().?.content, self.route.getText().?.content }) catch {
            self.feedback("复制失败，请重试", false);
            return;
        };
        defer self.cx.allocator.free(report);
        self.callbacks.copy(self.callbacks.context, source.key, report) catch {
            self.feedback("复制失败，请重试", false);
            return;
        };
        self.feedback("已复制信息", true);
    }
    fn feedback(self: *View, text: []const u8, success: bool) void {
        self.copy_feedback.report(success);
        self.feedback_label.setTextContent(self.cx.allocator, text) catch {};
        self.feedback_label.setDisplay(if (success) .none else .flex);
        self.feedback_label.setTextColor(if (success) @import("../../connections/socks/view/socks_info_styles.zig").text(.success) else S.theme.current().danger_ink);
        self.cx.requestRedraw();
    }
    fn anchor(raw: *anyopaque) ui.widgets.popover.AnchorRect {
        const self: *View = @ptrCast(@alignCast(raw));
        if (self.visible) if (self.attached) |source| if (source.rect(source.ctx)) |r| {
            return self.alignedAnchor(.{ .x = r.x, .y = r.y, .w = r.w, .h = r.h });
        };
        return self.alignedAnchor(self.anchor_rect);
    }
    fn alignedAnchor(self: *View, rect: ui.widgets.popover.AnchorRect) ui.widgets.popover.AnchorRect {
        const w = @min(S.width, @max(0, self.cx.viewport.width - S.margin * 2));
        const x = if (rect.x + w <= self.cx.viewport.width - S.margin) rect.x else rect.x + rect.w - w;
        return .{ .x = @max(S.margin, @min(x, self.cx.viewport.width - w - S.margin)), .y = rect.y, .w = 0, .h = if (rect.y < self.cx.viewport.height / 2) rect.h else 0 };
    }
    fn cleanup(self: *View) void {
        self.cx.allocator.destroy(self);
    }
    fn releaseFocus(self: *View) void {
        const focused = self.cx.focus_manager.current_focus orelse return;
        if (focused.isDescendantOf(self.chrome)) self.cx.clearFocus();
    }
};
pub fn validate(source: Snapshot) !void {
    if (source.key.owner != .session or @backingInt(source.key.owner.session.session_id) == 0 or source.key.owner.session.generation == 0 or source.key.operation_id == 0 or source.key.attempt_id == null or source.key.attempt_id == 0 or source.revision == 0 or source.hop_count == 0 or source.hop_count > details.max_hops) return error.InvalidConnection;
    if (source.cipher_c2s.len > source.cipher_c2s.bytes.len or source.cipher_s2c.len > source.cipher_s2c.bytes.len) return error.InvalidConnection;
    try validateEndpoint(source.endpoint);
    for (source.route[0..source.hop_count]) |endpoint| try validateEndpoint(endpoint);
}
fn validateEndpoint(endpoint: details.Endpoint) !void {
    if (endpoint.host.len > endpoint.host.bytes.len or endpoint.user.len > endpoint.user.bytes.len or endpoint.name.len > endpoint.name.bytes.len or endpoint.port == 0) return error.InvalidEndpoint;
}
fn addressText(buffer: []u8, endpoint: *const details.Endpoint) ![]const u8 {
    const host = unknown(endpoint.host.slice());
    return if (std.mem.indexOfScalar(u8, host, ':') != null) std.fmt.bufPrint(buffer, "{s}@[{s}]:{d}", .{ unknown(endpoint.user.slice()), host, endpoint.port }) else std.fmt.bufPrint(buffer, "{s}@{s}:{d}", .{ unknown(endpoint.user.slice()), host, endpoint.port });
}
fn unknown(value: []const u8) []const u8 {
    return if (value.len == 0) "未知" else value;
}
fn label(cx: *ui.Cx, parent: *ui.Node, text: []const u8, style: ui.TextStyle, box: ui.BoxStyle) !*ui.Node {
    const node = try ui.text(cx, "", style);
    node.setStyleInline(cx.allocator, box);
    try node.setTextContent(cx.allocator, text);
    try parent.appendChild(cx.allocator, node);
    return node;
}
fn clear(cx: *ui.Cx, parent: *ui.Node) void {
    var index: usize = 0;
    while (index < parent.children.items.len) {
        const child = parent.children.items[index];
        if (@import("background_layers.zig").isSurface(child)) {
            index += 1;
            continue;
        }
        cx.detachChild(parent, child);
        cx.destroyDetached(child);
    }
}
