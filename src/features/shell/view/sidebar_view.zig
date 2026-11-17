//! Sidebar widgets. Callbacks capture identities in the host; this view owns
//! only copied display strings and transient interaction state.
const std = @import("std");
const ui = @import("ui");
pub const styles = @import("sidebar_styles.zig");
const S = styles;
const T = S.theme;
const header_icon_size: f32 = 17;
pub const GroupRef = @import("../../../config/asset_actions.zig").GroupRef;
const app_menu = @import("app_menu.zig");
pub const GroupAction = enum { new_host, rename, color, toggle_collapsed, delete_empty };
pub const Bridge = struct {
    context: ?*anyopaque = null,
    set_anchor: ?*const fn (?*anyopaque, ui.ComputedRect) void = null,
    new_host: ?*const fn (?*anyopaque, ?GroupRef) void = null,
    new_group: ?*const fn (?*anyopaque) void = null,
    group_action: ?*const fn (?*anyopaque, GroupRef, GroupAction) void = null,
};
pub const Actions = struct {
    context: *anyopaque,
    collapse: *const fn (*anyopaque) void,
    search_changed: ui.Handler([]const u8),
    bridge: Bridge,
    local: ?*const fn (*anyopaque) void = null,
};
pub const View = struct {
    cx: *ui.Cx,
    root: *ui.Node,
    full: *ui.Node,
    empty: *ui.Node,
    list: *ui.Node,
    viewport: *ui.Node,
    list_visible: bool = false,
    title: *ui.Node,
    search_box: *ui.Node,
    search: ui.widgets.input.InputResult,
    search_clear: *ui.Node,
    header_leading: *ui.Node,
    header: *ui.Node,
    search_available: bool = true,
    search_value: *ui.Signal([]const u8),
    footer: *ui.Node,
    group_button: *ui.Node,
    colors: T.Colors,
    actions: Actions,
    tint: *ui.Signal(?ui.Color),
    hover: *ui.Signal(?ui.BoxStyle),
    host_disabled: *ui.Signal(bool),
    group_disabled: *ui.Signal(bool),
    /// “隐藏侧栏 · ⌘B”：快捷键文字来自路由（`syncShortcut`）。
    collapse_tip: ?*ShortcutTip = null,
    pub fn syncShortcut(self: *View, hint_text: []const u8) void {
        if (self.collapse_tip) |tip| tip.sync(hint_text);
    }
    pub fn mount(cx: *ui.Cx, scope: *ui.Scope, list: *ui.Node, actions: Actions) !*View {
        const root = try ui.boxStyled(cx, S.panel, .{});
        root.meta.ownership.meta.test_id = "workspace.sidebar";
        // The sidebar starts at the window top, so its first rows are part of the window's title
        // bar: the header and the inset above it form one band that drags the window (window
        // chrome region; the collapse button and the native traffic lights stay controls). The
        // band takes over the column's top padding, so nothing moves.
        var full_style = S.full();
        var full_padding = full_style.padding orelse ui.Padding{};
        const title_inset = full_padding.top;
        full_padding.top = 0;
        full_style.padding = full_padding;
        const full = try ui.box(cx, full_style, .{});
        try root.appendChild(cx.allocator, full);
        const title_band = try ui.box(cx, .{ .width = .fill(), .direction = .column, .align_items = .stretch, .padding = .{ .top = title_inset }, .flex_shrink = 0 }, .{});
        title_band.behavior.interaction.window_region = .drag;
        try full.appendChild(cx.allocator, title_band);
        const header = try ui.box(cx, S.header(), .{});
        header.meta.ownership.meta.test_id = "sidebar.header";
        header.setStyleInline(cx.allocator, .{ .width = .fill(), .min_width = 0 });
        try title_band.appendChild(cx.allocator, header);
        const header_leading = try ui.box(cx, .{ .width = .{ .grow = .{ .min = header_icon_size } }, .min_width = header_icon_size, .direction = .row, .align_items = .center, .gap = header.style.gap }, .{});
        try header.appendChild(cx.allocator, header_leading);
        try header_leading.appendChild(cx.allocator, try ui.iconTint(cx, ui.icons.get("server").?, T.current().accent, S.icon(header_icon_size)));
        const title = try text(cx, header_leading, "主机", 13, 700, false);
        title.setStyleInline(cx.allocator, .{ .width = .{ .grow = .{ .min = 0 } }, .min_width = 0 });
        const tint = try scope.createSignal(?ui.Color, T.current().fg_2);
        const hover = try scope.createSignal(?ui.BoxStyle, .{ .background = T.states().hover });
        const host_disabled = try scope.createSignal(bool, actions.bridge.new_host == null);
        const group_disabled = try scope.createSignal(bool, actions.bridge.new_group == null);
        const search_value = try scope.createText("", .{});
        const search = try mountSearchInput(cx, scope, search_value, actions.search_changed, "sidebar.search");
        // Island B v3 sidebar search (Pencil `JrTg7` › `ekeSE` Search): a resident
        // full-width 28pt field under the header whenever there are hosts to
        // filter. The header carries no search or "+" action; new hosts and
        // groups are created from the sidebar bottom row.
        const search_box = try ui.box(cx, S.searchRow(), .{});
        search_box.meta.ownership.meta.test_id = "sidebar.search.well";
        try full.appendChild(cx.allocator, search_box);
        const viewport = try ui.widgets.ScrollArea(.{}).mount(scope, cx);
        viewport.container.meta.ownership.meta.test_id = "sidebar.viewport";
        viewport.container.setStyleInline(cx.allocator, S.viewport());
        viewport.content.setStyleInline(cx.allocator, .{ .direction = .column, .width = .fill() });
        list.setStyleInline(cx.allocator, S.list());
        try viewport.content.appendChild(cx.allocator, list);
        try full.appendChild(cx.allocator, viewport.container);
        const self = try scope.createState(View, .{ .cx = cx, .root = root, .full = full, .empty = undefined, .list = list, .viewport = viewport.container, .title = title, .header = header, .search_box = search_box, .search = search, .search_clear = undefined, .header_leading = header_leading, .search_value = search_value, .footer = undefined, .group_button = undefined, .colors = T.current(), .actions = actions, .tint = tint, .hover = hover, .host_disabled = host_disabled, .group_disabled = group_disabled });
        try search_box.appendChild(cx.allocator, search.node);
        const clear = try iconButton(cx, scope, "x", "清空搜索", "sidebar.search.clear", S.headerAction(), tint, hover, cx.on(View, self, View.clearSearch), null);
        clear.setDisplay(.none);
        self.search_clear = clear;
        try search_box.appendChild(cx.allocator, clear);
        const collapse = try iconButton(cx, scope, "panel-left", collapse_name, "sidebar.collapse", S.headerAction(), tint, hover, ui.Cx.simpleHandler(actions.collapse, actions.context), null);
        // Island B v3 sidebar header: [traffic lights 52][toggle 24][title …] (Pencil `U4NxCm`).
        const window_controls = try ui.box(cx, .{ .position = .absolute, .inset = .{ .top = .{ .px = 14 }, .left = .{ .px = 72 } }, .width = .{ .px = 24 }, .height = .{ .px = 24 } }, .{});
        const collapse_hint = try shortcutHint(cx, scope, collapse, collapse_name, .right, "sidebar.collapse.tooltip");
        self.collapse_tip = collapse_hint.tip;
        try window_controls.appendChild(cx.allocator, collapse_hint.wrapper);
        try root.appendChild(cx.allocator, window_controls);
        const bottom = try ui.box(cx, .{ .width = .fill(), .direction = .column, .gap = 8, .margin = .{ .top = 12 }, .flex_shrink = 0 }, .{});
        bottom.meta.ownership.meta.test_id = "sidebar.bottom";
        // Sidebar bottom (Pencil `JrTg7` › `g7ijC`): the new-connection action
        // fills the row; trailing actions (24pt ghost icons) follow it.
        const bottom_row = try ui.box(cx, .{ .width = .fill(), .direction = .row, .align_items = .center, .gap = 6, .flex_shrink = 0 }, .{});
        bottom_row.meta.ownership.meta.test_id = "sidebar.bottom.row";
        const footer = try self.footerButton(scope, "sidebar.footer.new", false);
        footer.setStyleInline(cx.allocator, .{ .width = .fill(), .flex = 1, .min_width = 0 });
        try bottom_row.appendChild(cx.allocator, footer);
        const group_button = try ui.widgets.Button(.{ .variant = .ghost, .icon_only = true, .icon_asset = ui.icons.get("folder-plus"), .icon_size = @as(f32, 16), .icon_tint = tint, .a11y_label = "新建分组", .disabled = group_disabled, .base_style = S.headerAction(), .hover_style = hover, .on_click = cx.on(View, self, View.newGroup) }).mount(scope, cx);
        group_button.meta.ownership.meta.test_id = "sidebar.new.group";
        try @import("../../../shared/ui/components/icon_button_feedback/icon_button_feedback.zig").Binding.attach(cx, scope, group_button);
        self.group_button = group_button;
        try bottom_row.appendChild(cx.allocator, try hint(cx, scope, group_button, "新建分组", .top));
        try bottom.appendChild(cx.allocator, bottom_row);
        try full.appendChild(cx.allocator, bottom);
        self.footer = footer;
        var empty_style = S.full();
        // Same title band as the host list's header (drags the window); the guide starts 52pt down.
        const empty_band: f32 = @import("shell_styles.zig").title_height;
        empty_style.padding = .{ .top = 0, .left = 8, .right = 8, .bottom = 12 };
        empty_style.gap = 0;
        const empty = try ui.box(cx, empty_style, .{});
        empty.meta.ownership.meta.test_id = "sidebar.empty";
        const empty_title_band = try ui.box(cx, .{ .width = .fill(), .height = .{ .px = empty_band }, .margin = .{ .bottom = 52 - empty_band }, .flex_shrink = 0 }, .{});
        empty_title_band.behavior.interaction.window_region = .drag;
        try empty.appendChild(cx.allocator, empty_title_band);
        const guide = try ui.box(cx, .{ .width = .fill(), .direction = .column, .gap = 12, .padding = .{ .top = 16, .left = 16, .right = 16 }, .flex_shrink = 0 }, .{});
        try empty.appendChild(cx.allocator, guide);
        const empty_header = try ui.box(cx, .{ .width = .fill(), .height = .{ .px = 24 }, .direction = .row, .align_items = .center, .flex_shrink = 0 }, .{});
        try guide.appendChild(cx.allocator, empty_header);
        try empty_header.appendChild(cx.allocator, try ui.iconTint(cx, ui.icons.get("server").?, T.current().accent, S.icon(18)));
        try empty_header.appendChild(cx.allocator, try ui.spacer(cx));
        _ = try text(cx, guide, "还没有主机", 13, 500, false);
        const explanation = try text(cx, guide, "添加主机后，它会显示在这里。", 12, 400, true);
        explanation.meta.ownership.meta.test_id = "sidebar.empty.explanation";
        explanation.setStyleInline(cx.allocator, .{ .width = .fill() });
        if (explanation.getText()) |current| {
            var next = current;
            next.wrap = .word;
            explanation.setText(next);
        }
        try empty.appendChild(cx.allocator, try ui.spacer(cx));
        try empty.appendChild(cx.allocator, try self.footerButton(scope, "sidebar.empty.new", true));
        try root.appendChild(cx.allocator, empty);
        self.empty = empty;
        try scope.createEffect(.{ .view = self, .value = search_value }, struct {
            fn run(ctx: anytype) void {
                _ = ctx.value.get();
                ctx.view.syncSearchClear();
            }
        }.run);
        try scope.createEffect(.{ .view = self, .theme = try cx.themeSignal() }, struct {
            fn run(ctx: anytype) void {
                _ = ctx.theme.get();
                ctx.view.retheme();
            }
        }.run);
        try cx.addAfterLayoutHook(self, afterLayout);
        try scope.onCleanup(View, self, cleanup);
        return self;
    }
    pub fn setSearchAvailable(self: *View, available: bool) void {
        if (self.search_available == available) return;
        self.search_available = available;
        if (!available and self.search_value.peek().len != 0) {
            self.search_value.set("");
            self.actions.search_changed.call("");
        }
        self.search_box.setDisplay(if (available) .flex else .none);
        self.syncSearchClear();
    }
    pub fn focusSearchFallback(self: *View) void {
        if (self.search_available and self.full.style.display != .none) self.cx.setFocus(self.search.input_container);
    }
    fn syncSearchClear(self: *View) void {
        self.search_clear.setDisplay(if (self.search_value.peek().len != 0) .flex else .none);
    }
    fn clearSearch(self: *View) void {
        self.search_value.set("");
        self.actions.search_changed.call("");
        self.cx.setFocus(self.search.input_container);
    }
    fn afterLayout(raw: *anyopaque, _: u8, _: bool) ui.AfterLayoutResult {
        const self: *View = @ptrCast(@alignCast(raw));
        var visible = self.full.style.display != .none and self.root.globalRect().w > 0 and self.root.globalRect().h > 0;
        var ancestor: ?*ui.Node = self.root;
        while (ancestor) |node| : (ancestor = node.parent) if (node.style.display == .none) {
            visible = false;
            break;
        };
        if (visible == self.list_visible) return .done;
        self.list_visible = visible;
        if (!visible) return .done;
        // Rows rebuilt while hidden can retain zero-width layout entries.
        // Re-layout the list once when it becomes visible in either location.
        self.list.markLayoutDirty();
        return .needs_layout;
    }
    fn cleanup(self: *View) void {
        self.cx.removeAfterLayoutHook(self);
    }
    fn footerButton(self: *View, scope: *ui.Scope, id: []const u8, empty: bool) !*ui.Node {
        const slot = try ui.box(self.cx, S.footerSlot(empty), .{});
        try @import("sidebar_new_button.zig").mount(self.cx, scope, slot, id, empty, self.host_disabled, self.cx.on(View, self, View.newHost));
        return slot;
    }
    fn newLocal(self: *View) void {
        if (self.actions.local) |run| run(self.actions.context);
    }
    fn newHost(self: *View) void {
        if (self.actions.bridge.new_host) |call| call(self.actions.bridge.context, null);
    }
    fn newGroup(self: *View) void {
        if (self.actions.bridge.set_anchor) |call| call(self.actions.bridge.context, self.group_button.globalRect());
        if (self.actions.bridge.new_group) |call| call(self.actions.bridge.context);
    }
    pub fn setBridge(self: *View, bridge: Bridge) void {
        self.actions.bridge = bridge;
        self.host_disabled.set(bridge.new_host == null);
        self.group_disabled.set(bridge.new_group == null);
    }
    pub fn retheme(self: *View) void {
        S.repaint(self.root, self.colors);
        self.colors = T.current();
        self.tint.set(self.colors.fg_2);
        self.hover.set(.{ .background = T.states().hover });
        self.search_box.setBackground(self.colors.well_border);
        self.search.state.tokens = self.cx.tokens;
        self.search.state.placeholder_color = self.colors.fg_2;
        self.search.state.dirty = true;
        if (self.search.state.text_display_node) |label| if (label.getText()) |old| {
            var next = old;
            next.font_size = 12;
            next.font_weight = 400;
            next.line_height = 1.5;
            next.color = if (self.search_value.peek().len == 0) self.colors.fg_2 else self.colors.fg_1;
            label.setText(next);
        };
    }
};

fn mountSearchInput(cx: *ui.Cx, scope: *ui.Scope, value: *ui.Signal([]const u8), changed: ui.Handler([]const u8), id: []const u8) !ui.widgets.input.InputResult {
    const input = try ui.widgets.Input(.{ .value = value, .placeholder = "搜索主机、标签、地址…", .placeholder_color = T.current().fg_2, .embedded = true, .on_change = changed }).mountResult(scope, cx);
    input.node.meta.ownership.meta.test_id = id;
    input.node.setStyleInline(cx.allocator, .{ .width = .fill(), .height = .fill(), .flex = 1, .min_width = 0, .justify = .center });
    input.state.font_size = 11;
    input.state.line_height = 16.5;
    input.state.char_width = 11 * 0.6;
    input.state.dirty = true;
    if (input.state.text_display_node) |label| if (label.getText()) |old| {
        var next = old;
        next.font_size = 11;
        next.font_weight = 400;
        next.line_height = 1.5;
        next.color = T.current().fg_2;
        label.setText(next);
    };
    return input;
}

pub const HostAction = enum { copy, edit };
pub const HostCallbacks = struct {
    action: ?*const fn (*anyopaque, HostAction) void = null,
    context: *anyopaque,
    select: *const fn (*anyopaque) void,
    connect: *const fn (*anyopaque) void,
    menu: *const fn (*anyopaque, *ui.Node) void,
};
pub const ForwardBadge = struct { port: ?u16, phase: @import("../../../host/socks_background_model.zig").Phase };
pub const HostData = struct {
    /// Where the list's owner keeps the sidebar this row is listed in (it may be mounted after the
    /// first rows): the identity hint attaches to that panel's edge.
    sidebar: ?*const ?*View = null,
    protocol: []const u8 = "SSH", supports_route: bool = true, icon: ?ui.SvgAsset = null, kind: @import("../../../shared/ui/components/session_icon/session_icon.zig").Kind = .terminal, name: []const u8, detail: []const u8, route: []const u8, hops: usize, online: bool, selected: bool = false, forward: ?ForwardBadge = null,
    /// 协议插件被禁用（Q5，qQaos）：不可连接的原因与恢复路径（Tooltip 全文）。非 null 时行以禁用样式显示、
    /// 行尾是“已禁用”而不是连接按钮，回车 / 双击只打开同一个提示。
    unavailable: ?[]const u8 = null };
pub const HostRow = struct {
    cx: *ui.Cx,
    node: *ui.Node,
    name: *ui.Node,
    trailing: *ui.Node,
    tail: *ui.Node,
    supports_route: bool,
    route: *ui.Node,
    route_label: ?*ui.Node = null,
    actions: *ui.Node,
    /// design-r3 A2: the selected row's native “连接” button (`sidebar_host_connect.yix`).
    connect_slot: *ui.Node,
    dot: *ui.Node,
    online: bool,
    forward: *ui.Node,
    forward_label: *ui.Node,
    forward_badge: ?ForwardBadge = null,
    hot: bool = false,
    selected: *ui.Signal(bool),
    menu_open: *ui.Signal(bool),
    menu_trigger: *ui.Node = undefined,
    base: *ui.Signal(ui.BoxStyle),
    hover: *ui.Signal(?ui.BoxStyle),
    tint: *ui.Signal(?ui.Color),
    callbacks: HostCallbacks,
    colors: T.Colors,
    /// 协议插件被禁用（Q5）：行尾“已禁用”与它的 Tooltip 开合。
    unavailable: ?*ui.Node = null,
    unavailable_open: ?*ui.Signal(bool) = null,
    pub fn mount(cx: *ui.Cx, scope: *ui.Scope, data: HostData, callbacks: HostCallbacks) !*HostRow {
        const selected = try scope.createSignal(bool, data.selected);
        const menu_open = try scope.createSignal(bool, false);
        const base = try scope.createSignal(ui.BoxStyle, S.host(data.selected, false));
        const hover = try scope.createSignal(?ui.BoxStyle, .{ .background = T.states().hover });
        const tint = try scope.createSignal(?ui.Color, T.current().fg_2);
        const self = try scope.createState(HostRow, .{ .cx = cx, .node = undefined, .name = undefined, .trailing = undefined, .tail = undefined, .supports_route = data.supports_route, .route = undefined, .actions = undefined, .connect_slot = undefined, .dot = undefined, .online = data.online, .forward = undefined, .forward_label = undefined, .selected = selected, .menu_open = menu_open, .base = base, .hover = hover, .tint = tint, .callbacks = callbacks, .colors = T.current() });
        const node = try ui.widgets.Button(.{ .variant = .ghost, .a11y_label = try scope.createText(data.name, .{}), .base_style = base, .hover_style = ui.BoxStyle{}, .on_click = cx.on(HostRow, self, HostRow.select), .on_event = onEvent, .event_context = @as(?*anyopaque, self) }).mount(scope, cx);
        node.meta.ownership.meta.test_id = "sidebar.host";
        node.behavior.events.on_event_capture = captureStatusClick;
        node.behavior.events.capture_context = self;
        self.node = node;
        self.menu_trigger = node;
        const content = try ui.box(cx, S.content(), .{});
        try node.appendChild(cx.allocator, content);
        self.dot = try ui.iconTint(cx, data.icon orelse @import("../../../shared/ui/components/session_icon/session_icon.zig").resolve(data.kind), ui.Color.WHITE, S.icon(16));
        @import("../../../shared/ui/components/session_icon/session_icon.zig").refreshHostTint(self.dot);
        self.dot.meta.ownership.meta.test_id = "sidebar.host.icon";
        try content.appendChild(cx.allocator, self.dot);
        const metadata = try ui.box(cx, .{ .width = .{ .grow = .{ .min = 0 } }, .flex_shrink = 1, .height = .{ .px = 24 }, .direction = .row, .align_items = .center, .gap = 6, .min_width = 0 }, .{});
        // Island B v3 environment row: name 13, regular / active 500 (ZW4 / Project Row).
        const initial_weight: u16 = if (data.selected) 500 else 400;
        const name = try ui.text(cx, data.name, S.text(13, initial_weight, false));
        name.meta.ownership.meta.test_id = "sidebar.host.name";
        name.setStyleInline(cx.allocator, .{ .width = .{ .grow = .{ .min = 0 } }, .min_width = 0, .flex_shrink = 1, .overflow_hidden = true });
        self.name = name;
        try metadata.appendChild(cx.allocator, name);
        const identity = try std.fmt.allocPrint(cx.allocator, "{s}\n{s}\n{s}", .{ data.name, data.detail, data.route });
        defer cx.allocator.free(identity);
        const identity_hint = try mountHostHint(cx, scope, metadata, identity, node, data.sidebar);
        var metadata_viewport = S.titleViewport();
        metadata_viewport.height = .{ .px = 24 };
        // The hint wrapper is a column: stretch the title across it and center vertically.
        metadata_viewport.align_items = .stretch;
        metadata_viewport.justify = .center;
        identity_hint.wrapper.setStyleInline(cx.allocator, metadata_viewport);
        identity_hint.trigger.setStyleInline(cx.allocator, .{ .width = .{ .grow = .{ .min = 0 } }, .height = .fill(), .min_width = 0, .flex_shrink = 1, .overflow = .hidden });
        try content.appendChild(cx.allocator, identity_hint.wrapper);
        const trailing = try ui.box(cx, .{ .width = .{ .fit = .{} }, .height = .{ .px = 24 }, .direction = .row, .align_items = .center, .gap = 4, .flex_shrink = 0 }, .{});
        self.trailing = trailing;
        trailing.meta.ownership.meta.test_id = "sidebar.host.trailing";
        try content.appendChild(cx.allocator, trailing);
        const tail = try ui.box(cx, S.tail(), .{});
        self.tail = tail;
        tail.meta.ownership.meta.test_id = "sidebar.host.tail";
        try trailing.appendChild(cx.allocator, tail);
        const route = try ui.box(cx, S.route(), .{});
        route.meta.ownership.meta.test_id = "sidebar.host.route";
        if (data.supports_route) {
            const icon = try ui.iconTintStyled(cx, ui.icons.get("route").?, T.current().fg_2, S.routeIcon());
            icon.meta.ownership.meta.test_id = "sidebar.host.route-icon";
            try route.appendChild(cx.allocator, icon);
            const badge = try ui.box(cx, S.routeBadge(), .{});
            badge.meta.ownership.meta.test_id = "sidebar.host.route-badge";
            var count: [24]u8 = undefined;
            const hops = try ui.text(cx, try std.fmt.bufPrint(&count, "{d}", .{data.hops}), S.routeBadgeText());
            hops.meta.ownership.meta.test_id = "sidebar.host.hops";
            hops.setStyleInline(cx.allocator, .{ .width = .{ .px = 12 }, .height = .{ .px = 10 }, .flex_shrink = 0 });
            try badge.appendChild(cx.allocator, hops);
            try route.appendChild(cx.allocator, badge);
            self.route_label = hops;
        }
        self.route = route;
        self.forward = try ui.box(cx, .{ .width = .{ .px = S.tail_width }, .height = .{ .px = 20 }, .direction = .row, .align_items = .center, .justify = .end, .flex_shrink = 0, .display = .none }, .{});
        self.forward.meta.ownership.meta.test_id = "sidebar.host.background";
        self.forward_label = try ui.text(cx, "", S.text(9, 500, true));
        self.forward_label.setStyleInline(cx.allocator, .{ .width = .fill(), .min_width = 0 });
        try self.forward.appendChild(cx.allocator, self.forward_label);
        try tail.appendChild(cx.allocator, self.forward);
        try tail.appendChild(cx.allocator, route);
        const actions = try ui.box(cx, .{ .width = .{ .px = S.action_size }, .height = .{ .px = S.action_size }, .direction = .row, .align_items = .center, .flex_shrink = 0 }, .{});
        self.actions = actions;
        const connect_button = try iconButtonWithSize(cx, scope, "play", "新标签连接", "sidebar.host.connect", S.action(S.action_size), S.host_icon_size, tint, hover, cx.on(HostRow, self, HostRow.connect), swallowDoubleClick);
        try actions.appendChild(cx.allocator, try hint(cx, scope, connect_button, "新标签连接", .right));
        try trailing.appendChild(cx.allocator, actions);
        // A2: selected row → native secondary/sm “连接”; unselected hover → ▶ above.
        self.connect_slot = try ui.view.render(scope, cx, @import("_sidebar_host_connect.yix.zig").HostConnect(.{ .on_connect = cx.on(HostRow, self, HostRow.connect) }));
        self.connect_slot.setDisplay(if (data.selected) .flex else .none);
        try trailing.appendChild(cx.allocator, self.connect_slot);
        if (data.unavailable) |reason| {
            const open = try scope.createSignal(bool, false);
            self.unavailable_open = open;
            const owned = try scope.createText(reason, .{});
            self.unavailable = try ui.view.render(scope, cx, @import("_sidebar_host_unavailable.yix.zig").HostUnavailable(.{ .reason = owned, .open = open, .on_open_change = cx.on(HostRow, self, HostRow.unavailableOpenChanged) }));
            try trailing.appendChild(cx.allocator, self.unavailable.?);
        }
        const hovered = try ui.hooks.useHover(scope, node);
        const pressed = try ui.hooks.usePressed(scope, cx, node);
        const name_hover = try ui.hooks.useHover(scope, identity_hint.trigger);
        const connect_hover = try ui.hooks.useHover(scope, connect_button);
        const focus = try ui.hooks.useFocusState(scope, cx, node);
        const connect_focus = try ui.hooks.useFocusState(scope, cx, connect_button);
        try scope.createEffect(.{ .self = self, .hovered = hovered, .pressed = pressed, .name_hover = name_hover, .connect_hover = connect_hover, .focus = focus.focused, .focus_visible = focus.visible, .connect_focus = connect_focus.focused, .identity_open = identity_hint.open.?, .last_identity_focus = try scope.createState(bool, false), .theme = try cx.themeSignal() }, struct {
            fn run(ctx: anytype) void {
                _ = ctx.theme.get();
                const picked = ctx.self.selected.get();
                const hot = ctx.hovered.get() or ctx.name_hover.get() or ctx.connect_hover.get() or ctx.focus.get() or ctx.connect_focus.get() or ctx.self.menu_open.get();
                const identity_focus = ctx.focus_visible.get();
                if (ctx.last_identity_focus.* != identity_focus) {
                    ctx.last_identity_focus.* = identity_focus;
                    ctx.identity_open.set(identity_focus);
                }
                S.repaint(ctx.self.node, ctx.self.colors);
                if (ctx.self.route_label) |label| label.setTextColor(T.current().fg_2);
                @import("../../../shared/ui/components/session_icon/session_icon.zig").refreshHostTint(ctx.self.dot);
                // 已禁用（qQaos）：图标 fg_disabled、名称三级墨色。
                if (ctx.self.unavailable != null) _ = ctx.self.dot.setTint(T.current().fg_3.withAlpha(140));
                ctx.self.colors = T.current();
                ctx.self.tint.set(T.current().fg_2);
                ctx.self.hover.set(.{ .background = T.current().well });
                const row_state: S.RowState = if (picked) .active else if (ctx.pressed.get() and ctx.hovered.get()) .press else if (hot) .hover else .normal;
                ctx.self.base.set(S.hostState(row_state));
                ctx.self.node.setStyleInline(ctx.self.cx.allocator, S.hostState(row_state));
                ctx.self.hot = hot;
                ctx.self.updateTrailing();
                if (ctx.self.forward_badge) |badge| ctx.self.forward_label.setTextColor(@import("../../connections/socks/view/socks_background_styles.zig").ink(badge.phase));
                if (ctx.self.name.getText()) |current| {
                    var next = current;
                    next.font_weight = if (picked) 500 else 400;
                    next.color = if (ctx.self.unavailable != null) T.current().fg_3 else T.current().fg_1;
                    ctx.self.name.setText(next);
                }
                if (ctx.self.node.behavior.interaction.a11y) |*a11y| a11y.selected = picked;
            }
        }.run);
        self.setForwardBadge(data.forward);
        self.updateTrailing();
        return self;
    }
    pub fn setForwardBadge(self: *HostRow, badge: ?ForwardBadge) void {
        if (std.meta.eql(self.forward_badge, badge)) return;
        self.forward_badge = badge;
        var buffer: [64]u8 = undefined;
        const label = if (badge) |value| if (value.port) |port| std.fmt.bufPrint(&buffer, ":{d}后台", .{port}) catch "后台" else @import("../../../host/socks_background_model.zig").phaseLabel(value.phase) else "";
        self.forward_label.setTextContent(self.cx.allocator, label) catch return;
        if (badge) |value| self.forward_label.setTextColor(@import("../../connections/socks/view/socks_background_styles.zig").ink(value.phase));
        self.updateTrailing();
        if (self.node.behavior.interaction.a11y) |*props| props.description = if (badge) |value| @import("../../../host/socks_background_model.zig").phaseLabel(value.phase) else null;
    }
    fn updateTrailing(self: *HostRow) void {
        if (self.unavailable != null) {
            // 已禁用（Q5）：只有“已禁用”，没有连接按钮、▶ 与路由徽标。
            self.trailing.setDisplay(.flex);
            self.tail.setDisplay(.none);
            self.actions.setDisplay(.none);
            self.connect_slot.setDisplay(.none);
            return;
        }
        const picked = self.selected.peek();
        const show_route = self.supports_route;
        const show_forward = !self.hot and self.forward_badge != null;
        self.trailing.setDisplay(if (show_route or show_forward or self.hot or picked) .flex else .none);
        self.tail.setStyle(self.cx.allocator, .width, .{ .px = if (show_forward) S.action_size * 3 else S.tail_width });
        self.tail.setDisplay(if (show_route or show_forward) .flex else .none);
        self.route.setDisplay(if (show_route) .flex else .none);
        self.forward.setDisplay(if (show_forward) .flex else .none);
        self.actions.setDisplay(if (self.hot and !picked) .flex else .none);
        self.connect_slot.setDisplay(if (picked) .flex else .none);
    }
    pub fn setOnline(self: *HostRow, online: bool) void {
        if (self.online == online) return;
        self.online = online;
    }
    pub fn setSelected(self: *HostRow, selected: bool) void {
        self.selected.set(selected);
    }
    pub fn setMenuOpen(self: *HostRow, open: bool) void {
        self.menu_open.set(open);
    }
    fn inConnectSlot(self: *HostRow, x: f32, y: f32) bool {
        if (self.connect_slot.style.display == .none) return false;
        const slot = self.connect_slot.globalRect();
        return x >= slot.x and x < slot.x + slot.w and y >= slot.y and y < slot.y + slot.h;
    }
    fn select(self: *HostRow) void {
        self.callbacks.select(self.callbacks.context);
    }
    fn connect(self: *HostRow) void {
        // 已禁用（Q5）：不发起连接，只打开原因提示。
        if (self.unavailable_open) |open| return open.set(true);
        self.callbacks.connect(self.callbacks.context);
    }
    fn unavailableOpenChanged(self: *HostRow, open: bool) void {
        if (self.unavailable_open) |signal| signal.set(open);
    }
    fn menu(self: *HostRow) void {
        self.callbacks.menu(self.callbacks.context, self.node);
    }
    fn captureStatusClick(event: ui.events.Event, raw: ?*anyopaque) ui.events.EventResult {
        const self: *HostRow = @ptrCast(@alignCast(raw orelse return .ignored));
        const click = switch (event) {
            .click => |value| value,
            else => return .ignored,
        };
        const trailing = self.trailing.globalRect();
        if (click.x < trailing.x or click.x >= trailing.x + trailing.w or click.y < trailing.y or click.y >= trailing.y + trailing.h) return .ignored;
        const actions = self.actions.globalRect();
        if (self.actions.style.display != .none and click.x >= actions.x and click.x < actions.x + actions.w and click.y >= actions.y and click.y < actions.y + actions.h) return .ignored;
        if (self.inConnectSlot(click.x, click.y)) return .ignored;
        // A pass-through status node may hit the row itself. Capture must run
        // before Button's target on_click; a bubble handler would be too late.
        return .handled;
    }
    fn onEvent(event: ui.events.Event, raw: ?*anyopaque) ui.events.EventResult {
        const self: *HostRow = @ptrCast(@alignCast(raw orelse return .ignored));
        switch (event) {
            .mouse_down => |mouse| if (mouse.button == .right) {
                self.menu();
                return .handled;
            },
            .click => |click| {
                // A row click only selects. Repeated clicks do not connect;
                // the separate action button and Return explicitly connect.
                if (click.click_count > 1) return .handled;
                // Child action buttons have already handled their own click.
                // Stop the row's connect callback when that click bubbles.
                if (self.cx.focus_manager.getFocused()) |focused| {
                    if (focused.isDescendantOf(self.actions) or focused.isDescendantOf(self.connect_slot)) return .handled;
                }
                const actions = self.actions.globalRect();
                if (click.x >= actions.x and click.x < actions.x + actions.w and click.y >= actions.y and click.y < actions.y + actions.h) return .handled;
                if (self.inConnectSlot(click.x, click.y)) return .handled;
            },
            .double_click => {
                // 已禁用（qQaos）：双击只选中并显示同一个提示。
                if (self.unavailable_open) |open| open.set(true);
                return .handled;
            },
            .key_down => |key| {
                const focused = self.cx.focus_manager.getFocused();
                if (key.key == .@"return" and focused == self.node) {
                    self.connect();
                    return .handled;
                }
            },
            else => {},
        }
        return .ignored;
    }
};

pub const GroupData = struct { reference: ?GroupRef, name: []const u8, count: usize, collapsed: bool, color: ?ui.Color = null };
pub const GroupRow = struct {
    cx: *ui.Cx,
    root: *ui.Node,
    header: *ui.Node,
    members: *ui.Node,
    actions: *ui.Node,
    reference: ?GroupRef,
    bridge: Bridge,
    collapsed: bool,
    disclosure: *@import("../../../shared/ui/styles/layout_motion.zig").Disclosure = undefined,
    chevron: *ui.Node,
    /// “更多分组操作”：原生 `W.Menu`，经菜单唯一入口（`app_menu.zig`）挂载与投影；右键分组标题也打开它。
    menu: *app_menu.AppMenu,
    menu_trigger: *ui.Node,
    caption: [160]u8 = undefined,
    count: usize,
    pub fn mount(cx: *ui.Cx, scope: *ui.Scope, data: GroupData, bridge: Bridge) !*GroupRow {
        const root = try ui.box(cx, S.groupCard(), .{});
        root.meta.ownership.meta.test_id = "sidebar.group.card";
        const self = try scope.createState(GroupRow, .{ .cx = cx, .root = root, .header = undefined, .members = undefined, .actions = undefined, .reference = data.reference, .bridge = bridge, .collapsed = data.collapsed, .chevron = undefined, .menu = undefined, .menu_trigger = undefined, .count = data.count });
        const header_hover = try scope.createSignal(?ui.BoxStyle, .{ .background = T.current().overlay });
        const header = try ui.widgets.Button(.{ .variant = .ghost, .a11y_label = try scope.createText(data.name, .{}), .base_style = S.group(), .hover_style = header_hover, .on_click = cx.on(GroupRow, self, GroupRow.toggle), .on_event = groupEvent, .event_context = @as(?*anyopaque, self) }).mount(scope, cx);
        header.meta.ownership.meta.test_id = "sidebar.group";
        self.header = header;
        try root.appendChild(cx.allocator, header);
        const content = try ui.box(cx, S.groupContent(), .{});
        try header.appendChild(cx.allocator, content);
        const chevron = try ui.iconTint(cx, ui.icons.chevron_down, T.current().fg_2, S.icon(12));
        chevron.setStyle(cx.allocator, .rotate, if (data.collapsed) -std.math.pi / 2.0 else @as(f32, 0));
        self.chevron = chevron;
        try content.appendChild(cx.allocator, chevron);
        const identity_dot = try ui.box(cx, .{ .width = .{ .px = 5 }, .height = .{ .px = 5 }, .background = data.color orelse T.current().fg_3, .border = .{ .radius = 3 }, .flex_shrink = 0 }, .{});
        try content.appendChild(cx.allocator, identity_dot);
        // Island B v3 section heading: 12, regular, secondary ink.
        const name = try text(cx, content, data.name, 12, 400, true);
        name.setStyleInline(cx.allocator, .{ .width = .fill(), .min_width = 0, .flex = 1 });
        const tint = try scope.createSignal(?ui.Color, T.current().fg_2);
        const hover = try scope.createSignal(?ui.BoxStyle, .{ .background = T.current().well });
        const badge = try ui.box(cx, S.badge(), .{});
        badge.meta.ownership.meta.test_id = "sidebar.group.badge";
        var count: [24]u8 = undefined;
        const count_label = try ui.text(cx, "", S.badgeText());
        const count_text = try std.fmt.bufPrint(&count, "{d}", .{data.count});
        try count_label.setTextContent(cx.allocator, count_text);
        count_label.setStyleInline(cx.allocator, S.badgeLabel());
        count_label.meta.ownership.meta.test_id = "sidebar.group.count";
        try badge.appendChild(cx.allocator, count_label);
        var group_tail = S.tail();
        group_tail.width = .{ .fit = .{} };
        const trailing = try ui.box(cx, group_tail, .{});
        try content.appendChild(cx.allocator, trailing);
        try trailing.appendChild(cx.allocator, badge);
        const actions = try ui.box(cx, .{ .direction = .row, .align_items = .center, .gap = 4, .flex_shrink = 0 }, .{});
        self.actions = actions;
        const plus = try iconButton(cx, scope, "plus", "组内新建主机", "sidebar.group.new", S.action(24), tint, hover, cx.on(GroupRow, self, GroupRow.newHost), swallowDoubleClick);
        if (bridge.new_host == null) plus.behavior.interaction.focusable = false;
        try actions.appendChild(cx.allocator, plus);
        const mounted = try app_menu.AppMenu.mountTrigger(cx, scope, .{ .panel_test_id = "sidebar.group.menu" }, .{ .context = self, .select = GroupRow.menuSelected });
        self.menu = mounted.menu;
        self.menu_trigger = mounted.result.trigger;
        const more = try iconButton(cx, scope, "ellipsis", "更多分组操作", "sidebar.group.more", S.action(24), tint, hover, null, swallowDoubleClick);
        try mounted.result.trigger.appendChild(cx.allocator, more);
        try actions.appendChild(cx.allocator, mounted.result.wrapper);
        try trailing.appendChild(cx.allocator, actions);
        const caption = std.fmt.bufPrint(&self.caption, "资产组 · {s}", .{data.name}) catch "资产组";
        const editable = bridge.group_action != null and data.reference != null;
        const entries = [_]app_menu.Entry{
            .{ .label = caption, .kind = .header, .test_id = "sidebar.group.menu.header" },
            .{ .id = "new_host", .label = "组内新建主机", .icon = "server", .disabled = bridge.new_host == null, .test_id = "sidebar.group.menu.new_host" },
            .{ .id = "rename", .label = "重命名分组", .icon = "pencil", .disabled = !editable, .test_id = "sidebar.group.menu.rename" },
            .{ .id = "color", .label = "更改组色", .icon = "palette", .disabled = !editable, .test_id = "sidebar.group.menu.color" },
            .{ .id = "toggle_collapsed", .label = if (data.collapsed) "展开分组" else "折叠分组", .icon = if (data.collapsed) "chevron-down" else "chevron-up", .disabled = !(data.reference == null or editable), .test_id = "sidebar.group.menu.toggle_collapsed" },
            .{ .id = "delete_empty", .label = "删除空分组", .icon = "trash-2", .danger = true, .disabled = !editable, .disabled_reason = if (editable and data.count != 0) "分组不为空" else null, .test_id = "sidebar.group.menu.delete_empty" },
        };
        mounted.menu.set(&entries, .{ .keys = &no_keys });
        const members = try ui.box(cx, S.members(), .{});
        self.members = members;
        const guide = try ui.box(cx, S.groupGuide(), .{});
        guide.meta.ownership.meta.test_id = "sidebar.group.guide";
        try members.appendChild(cx.allocator, guide);
        self.disclosure = try @import("../../../shared/ui/styles/layout_motion.zig").Disclosure.mount(cx, scope, members, !data.collapsed);
        try root.appendChild(cx.allocator, self.disclosure.root);
        const hovered = try ui.hooks.useHover(scope, header);
        const focused = try ui.hooks.useFocusState(scope, cx, header);
        const plus_focus = try ui.hooks.useFocusState(scope, cx, plus);
        const more_focus = try ui.hooks.useFocusState(scope, cx, more);
        try scope.createEffect(.{ .self = self, .hovered = hovered, .focused = focused.focused, .plus_focus = plus_focus.focused, .more_focus = more_focus.focused, .actions = actions, .badge = badge, .count_label = count_label, .open = self.menu.open, .tint = tint, .hover = hover, .header_hover = header_hover, .guide = guide, .theme = try cx.themeSignal() }, struct {
            fn run(ctx: anytype) void {
                _ = ctx.theme.get();
                const hot = ctx.hovered.get() or ctx.focused.get() or ctx.plus_focus.get() or ctx.more_focus.get() or ctx.open.get();
                ctx.actions.setDisplay(if (hot) .flex else .none);
                ctx.badge.setDisplay(if (hot) .none else .flex);
                ctx.count_label.setTextColor(T.current().fg_3);
                ctx.tint.set(T.current().fg_2);
                ctx.hover.set(.{ .background = T.current().well });
                ctx.header_hover.set(.{ .background = T.current().overlay });
                ctx.guide.setBackground(S.groupGuideColor());
            }
        }.run);
        return self;
    }
    fn toggle(self: *GroupRow) void {
        if (self.reference) |group| {
            if (self.bridge.group_action) |call| call(self.bridge.context, group, .toggle_collapsed);
        } else {
            self.collapsed = !self.collapsed;
            self.disclosure.setExpanded(!self.collapsed);
            self.header.behavior.interaction.a11y.?.expanded = !self.collapsed;
            self.chevron.setStyle(self.cx.allocator, .rotate, if (self.collapsed) -std.math.pi / 2.0 else @as(f32, 0));
        }
    }
    fn menuSelected(raw: *anyopaque, id: []const u8) void {
        const self: *GroupRow = @ptrCast(@alignCast(raw));
        const action = std.meta.stringToEnum(GroupAction, id) orelse return;
        if (self.bridge.set_anchor) |call| call(self.bridge.context, self.menu_trigger.globalRect());
        if (action == .new_host) return self.newHost();
        if (action == .toggle_collapsed and self.reference == null) return self.toggle();
        if (self.reference) |group| if (self.bridge.group_action) |call| call(self.bridge.context, group, action);
    }
    fn newHost(self: *GroupRow) void {
        if (self.bridge.new_host) |call| call(self.bridge.context, self.reference);
    }
    fn groupEvent(event: ui.events.Event, raw: ?*anyopaque) ui.events.EventResult {
        const self: *GroupRow = @ptrCast(@alignCast(raw orelse return .ignored));
        switch (event) {
            .mouse_down => |mouse| if (mouse.button == .right) {
                self.menu.open.set(true);
                return .handled;
            },
            .click => |click| {
                if (self.cx.focus_manager.getFocused()) |focused| {
                    if (focused.isDescendantOf(self.actions)) return .handled;
                }
                const actions = self.actions.globalRect();
                if (self.actions.style.display != .none and click.x >= actions.x and click.x < actions.x + actions.w and click.y >= actions.y and click.y < actions.y + actions.h) return .handled;
            },
            .double_click => return .handled,
            else => {},
        }
        return .ignored;
    }
};
/// 分组菜单没有快捷键：路由用空表（文字为空，不显示）。
const no_keys: @import("../model/shortcut_router.zig").Map = .{};

pub fn text(cx: *ui.Cx, parent: *ui.Node, value: []const u8, size: f32, weight: u16, secondary: bool) !*ui.Node {
    const node = try ui.text(cx, "", S.text(size, weight, secondary));
    try node.setTextContent(cx.allocator, value);
    try parent.appendChild(cx.allocator, node);
    return node;
}
pub fn iconButton(cx: *ui.Cx, scope: *ui.Scope, icon_name: []const u8, label: []const u8, id: []const u8, base: ui.BoxStyle, tint: *ui.Signal(?ui.Color), hover: *ui.Signal(?ui.BoxStyle), click: ?ui.Handler(void), event: ?*const fn (ui.events.Event, ?*anyopaque) ui.events.EventResult) !*ui.Node {
    return iconButtonWithSize(cx, scope, icon_name, label, id, base, 16, tint, hover, click, event);
}
fn iconButtonWithSize(cx: *ui.Cx, scope: *ui.Scope, icon_name: []const u8, label: []const u8, id: []const u8, base: ui.BoxStyle, icon_size: f32, tint: *ui.Signal(?ui.Color), hover: *ui.Signal(?ui.BoxStyle), click: ?ui.Handler(void), event: ?*const fn (ui.events.Event, ?*anyopaque) ui.events.EventResult) !*ui.Node {
    const node = try ui.widgets.Button(.{ .variant = .ghost, .icon_only = true, .icon_asset = ui.icons.get(icon_name), .icon_size = icon_size, .icon_tint = tint, .a11y_label = label, .base_style = base, .hover_style = hover, .on_click = click, .on_event = event }).mount(scope, cx);
    node.meta.ownership.meta.test_id = id;
    try @import("../../../shared/ui/components/icon_button_feedback/icon_button_feedback.zig").Binding.attach(cx, scope, node);
    return node;
}
fn swallowDoubleClick(event: ui.events.Event, _: ?*anyopaque) ui.events.EventResult {
    return switch (event) {
        .double_click, .mouse_down => .handled,
        else => .ignored,
    };
}
pub fn hint(cx: *ui.Cx, scope: *ui.Scope, node: *ui.Node, value: []const u8, position: ui.widgets.PopoverPosition) !*ui.Node {
    return (try mountHint(cx, scope, node, value, position)).wrapper;
}
fn mountHint(cx: *ui.Cx, scope: *ui.Scope, node: *ui.Node, value: []const u8, position: ui.widgets.PopoverPosition) !ui.widgets.popover.PopoverResult {
    return mountHintAnchored(cx, scope, node, value, position, null);
}

const shortcut_router = @import("../model/shortcut_router.zig");
const collapse_name = "隐藏侧栏";
pub const restore_name = "显示主机列表";

/// 带快捷键的提示气泡：“名称 · 快捷键”，快捷键文字由宿主从路由同步（键位改了随之变）；按钮的无障碍名同步。
pub const ShortcutTip = struct {
    label: *ui.Node,
    button: *ui.Node,
    name: []const u8,
    hint: []const u8 = "",
    synced: bool = false,
    buffers: [2][96]u8 = undefined,
    flip: u1 = 0,

    pub fn sync(self: *ShortcutTip, hint_text: []const u8) void {
        if (self.synced and std.mem.eql(u8, self.hint, hint_text)) return;
        self.synced = true;
        self.hint = hint_text;
        self.flip ^= 1;
        const value = shortcut_router.tooltip(&self.buffers[self.flip], self.name, hint_text);
        if (self.label.getText()) |old| {
            var next = old;
            next.content = value;
            self.label.setText(next);
        }
        if (self.button.behavior.interaction.a11y) |*a11y| a11y.label = value;
    }
};
/// `tip_id`：提示面板的 test_id（e2e 按 id 读提示文字）。
pub fn shortcutHint(cx: *ui.Cx, scope: *ui.Scope, node: *ui.Node, name: []const u8, position: ui.widgets.PopoverPosition, tip_id: []const u8) !struct { wrapper: *ui.Node, tip: *ShortcutTip } {
    var label: ?*ui.Node = null;
    const popup = try mountHintLabeled(cx, scope, node, name, position, null, &label);
    popup.content.meta.ownership.meta.test_id = tip_id;
    const tip = try scope.createState(ShortcutTip, .{ .label = label.?, .button = node, .name = name });
    return .{ .wrapper = popup.wrapper, .tip = tip };
}
fn mountHintAnchored(cx: *ui.Cx, scope: *ui.Scope, node: *ui.Node, value: []const u8, position: ui.widgets.PopoverPosition, anchor: ?*HostHintAnchor) !ui.widgets.popover.PopoverResult {
    return mountHintLabeled(cx, scope, node, value, position, anchor, null);
}
fn mountHintLabeled(cx: *ui.Cx, scope: *ui.Scope, node: *ui.Node, value: []const u8, position: ui.widgets.PopoverPosition, anchor: ?*HostHintAnchor, label_out: ?*?*ui.Node) !ui.widgets.popover.PopoverResult {
    const popup = try ui.widgets.Popover(.{ .trigger = .hover, .position = position, .anchor = if (anchor) |host| @as(ui.widgets.popover.Anchor, .{ .virtual = .{ .ctx = host, .getRect = HostHintAnchor.rect } }) else null, .offset = .{ .static = 8 }, .tier = .tooltip, .open_delay_ms = @import("../../../shared/ui/interaction.zig").hint_delay_ms, .close_on_escape = false, .close_on_outside_click = false, .max_width = @as(f32, 320), .max_height = @as(f32, 120), .size_policy = .fit_content }).mount(scope, cx);
    popup.content.setStyleInline(cx.allocator, S.hint());
    popup.content.behavior.interaction.a11y = .{ .role = .tooltip };
    const label = try text(cx, popup.content, value, 11, 400, true);
    if (label_out) |out| out.* = label;
    if (label.getText()) |old| {
        var next = old;
        next.wrap = .word;
        label.setText(next);
    }
    label.setStyleInline(cx.allocator, .{ .max_width = 300 });
    try popup.trigger.appendChild(cx.allocator, node);
    const focus = try ui.hooks.useFocusState(scope, cx, node);
    const last = try scope.createState(bool, false);
    try scope.createEffect(.{ .focus = focus.visible, .open = popup.open.?, .last = last, .theme = try cx.themeSignal(), .content = popup.content, .old = try scope.createState(T.Colors, T.current()) }, struct {
        fn run(ctx: anytype) void {
            _ = ctx.theme.get();
            const focused = ctx.focus.get();
            if (focused != ctx.last.*) {
                ctx.open.set(focused);
                ctx.last.* = focused;
            }
            S.repaint(ctx.content, ctx.old.*);
            ctx.old.* = T.current();
        }
    }.run);
    return popup;
}

const HostHintAnchor = struct {
    row: *ui.Node,
    /// The sidebar the row is listed in, given by the list's owner (`HostData.sidebar`): the hint
    /// attaches to that panel's right edge. Without one it attaches to the row's own edge.
    sidebar: ?*const ?*View,
    fn rect(raw: *anyopaque) ui.widgets.popover.AnchorRect {
        const self: *@This() = @ptrCast(@alignCast(raw));
        const row = self.row.globalRect();
        if (self.sidebar) |slot| if (slot.*) |view| {
            const panel = view.root.globalRect();
            return .{ .x = panel.x + panel.w, .y = row.y, .w = 0, .h = row.h };
        };
        return .{ .x = row.x + row.w, .y = row.y, .w = 0, .h = row.h };
    }
};
fn mountHostHint(cx: *ui.Cx, scope: *ui.Scope, node: *ui.Node, value: []const u8, row: *ui.Node, sidebar: ?*const ?*View) !ui.widgets.popover.PopoverResult {
    const anchor = try scope.createState(HostHintAnchor, .{ .row = row, .sidebar = sidebar });
    const popup = try mountHintAnchored(cx, scope, node, value, .right, anchor);
    popup.content.meta.ownership.meta.test_id = "sidebar.host.info";
    return popup;
}
