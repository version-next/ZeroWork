//! Per-execution terminal history. Opening or locating a record never writes PTY input.
//! Showing a card never replays a command or changes PTY input.
//! title-click: the list is a native `W.Popover` (manual, anchored under the trigger) that opens on
//! click only (the trigger, ⇧⌘B, the menus); hovering the trigger shows its Tooltip and nothing else.
//! A second click, Escape or an outside click closes it (Popover dismissals, outside click not consumed).
const std = @import("std");
const ui = @import("ui");
const ThemeWatch = @import("../../../shared/ui/theme/theme_watch.zig").ThemeWatch;
const overlay = @import("../../../shared/ui/overlay/overlay_host.zig");
const Workspace = @import("../../workspace/view/workspace.zig").Workspace;
const Terminal = @import("terminal_view.zig").TerminalViewNode;
const Command = @import("../../../vt/snapshot.zig").Command;
const annotations = @import("../model/command_annotations.zig");
const S = @import("command_history_styles.zig");
const panel_header = @import("../../../shared/ui/components/panel_header/panel_header.zig");

pub const Mode = enum { closed, pinned };
pub const View = struct {
    workspace_chrome: bool = false,
    unavailable: *ui.Signal(bool),
    cx: *ui.Cx,
    scope: *ui.Scope,
    workspace: *Workspace,
    root: *ui.Node,
    /// Native Popover around `root`: its wrapper joins the window tree, its content is portaled.
    wrapper: *ui.Node,
    /// The Popover's open state (the title bar click group watches it).
    open: *ui.Signal(bool),
    /// 头部副标题“N 条 · 会话名”（自持有文本信号）。
    subtitle: *ui.Signal([]const u8),
    scroll: ui.widgets.ScrollAreaResult,
    empty: *ui.Node,
    virtual: *ui.widgets.VirtualListState,
    records: std.ArrayList(Command) = .empty,
    buttons: [2]*ui.Node,
    /// 本视图自己建的触发按钮（标题栏那个由标题栏工具组管理无障碍名）。
    own_triggers: [2]?*ui.Node = .{ null, null },
    trigger_hint: []const u8 = "",
    trigger_synced: bool = false,
    trigger_text: [2][64]u8 = undefined,
    trigger_flip: u1 = 0,
    rows: std.ArrayList(Row) = .empty,
    mode: Mode = .closed,
    signature: u64 = 0,
    active_id: u64 = 0,
    visible_count: usize = 0,
    colors: S.theme.Colors,
    /// Raised by the window's theme publication; consumed where this view repaints.
    theme_watch: ThemeWatch = .{},
    const Action = struct {
        view: *View,
        id: u64 = 0,
        owner_id: u64 = 0,
        fn invoke(action: *Action) void {
            const self = action.view;
            if (self.active_id != action.owner_id) return;
            const terminal_node = self.terminal() orelse return;
            self.mode = .pinned;
            _ = terminal_node.locateCommand(action.id);
            self.cx.requestRedraw();
        }
    };
    const Row = struct { root: *ui.Node, card: *ui.Node, state: *ui.Node, command: *ui.Node, meta: *ui.Node, tip: *ui.Node, tip_open: ?*ui.Signal(bool), action: *Action };

    /// A native title bar button (design-r3 稿 5) used as the primary trigger
    /// instead of building one; its availability is the given signal.
    pub const External = struct { button: *ui.Node, unavailable: *ui.Signal(bool) };
    pub fn mount(cx: *ui.Cx, scope: *ui.Scope, workspace: *Workspace, ssh_bar: *ui.Node, local_bar: *ui.Node) !*View {
        return mountWith(cx, scope, workspace, ssh_bar, local_bar, null);
    }
    pub fn mountWith(cx: *ui.Cx, scope: *ui.Scope, workspace: *Workspace, ssh_bar: *ui.Node, local_bar: *ui.Node, external: ?External) !*View {
        const self = try cx.allocator.create(View);
        const open = try scope.createSignal(bool, false);
        const popup = try overlay.Popover(.panel, .{ .open = open, .trigger = .manual, .anchor = .{ .virtual = .{ .ctx = self, .getRect = anchorRect } }, .position = .bottom, .offset = .{ .static = 6 }, .viewport_padding = 8, .flip = true, .constrain_width_to_viewport = true, .close_on_outside_click = true, .consume_outside_click = false, .close_on_escape = true, .size_policy = .fit_content, .on_open_change = cx.on(View, self, openChanged) }).mount(scope, cx);
        popup.trigger.setDisplay(.none);
        const root = try ui.box(cx, S.panel(), .{});
        try popup.content.appendChild(cx.allocator, root);
        @import("../../../shared/ui/components/floating_input/floating_input.zig").protect(cx, root);
        root.meta.ownership.meta.test_id = "terminal.command-history";
        root.setDisplay(.none);
        // panel-heads：共享头部（图标 · “命令历史” · “N 条 · 会话名” · 统一关闭按钮）。
        const subtitle = try scope.createText("", .{});
        var header_slots: panel_header.Slots = .{};
        const header = try panel_header.mountHeader(popup.scope, cx, &header_slots, .{ .icon = ui.icons.list_restart, .title = "命令历史", .subtitle = subtitle, .inset = .flush, .header_test_id = "terminal.command-history.header", .subtitle_test_id = "terminal.command-history.count", .close_label = "关闭命令历史", .close_test_id = "terminal.command-history.close", .close_tooltip_test_id = "terminal.command-history.close.tooltip", .on_close = cx.on(View, self, hide) });
        try root.appendChild(cx.allocator, header);
        const list = try ui.widgets.VirtualList(.{ .item_count = @as(usize, 0), .measure_items = true, .estimate_item_height = 79, .overscan = 2 }).mountWithContext(scope, cx, self, null, renderItem);
        const scroll: ui.widgets.ScrollAreaResult = .{ .container = list.container, .content = list.state.content_node, .state = list.state.scroll_state };
        scroll.container.setStyleInline(cx.allocator, .{ .width = .fill(), .height = .fill(), .flex = 1, .min_height = 0 });
        scroll.content.setStyleInline(cx.allocator, .{ .width = .fill(), .padding = .{} });
        try root.appendChild(cx.allocator, scroll.container);
        const empty = try ui.view.render(scope, cx, ui.widgets.Empty(.{ .icon = ui.icons.list_restart, .title = "还没有命令记录", .description = "在这个会话里执行过的命令会出现在这里。" }));
        empty.meta.ownership.meta.test_id = "terminal.command-history.empty";
        empty.setStyleInline(cx.allocator, .{ .flex = 1 });
        try root.appendChild(cx.allocator, empty);
        self.* = .{ .cx = cx, .scope = scope, .workspace = workspace, .root = root, .wrapper = popup.wrapper, .open = open, .subtitle = subtitle, .scroll = scroll, .empty = empty, .virtual = list.state, .buttons = undefined, .colors = S.theme.current(), .unavailable = if (external) |value| value.unavailable else try scope.createSignal(bool, true) };
        try scope.onCleanup(View, self, cleanup);
        try self.theme_watch.bind(cx, scope);
        const primary = if (external) |value| blk: {
            value.button.behavior.events.on_click = cx.on(View, self, toggle);
            break :blk value.button;
        } else try self.button(ssh_bar, "status.command-history");
        self.buttons = .{ primary, try self.button(local_bar, "local.status.command-history") };
        try cx.root.?.appendChild(cx.allocator, popup.wrapper);
        try cx.addAfterLayoutHook(self, tick);
        return self;
    }
    fn button(self: *View, bar: *ui.Node, id: []const u8) !*ui.Node {
        const trigger = try ui.widgets.Button(.{ .variant = .ghost, .icon_only = true, .a11y_label = trigger_name, .disabled = self.unavailable, .base_style = @import("../../shell/view/status_connection_styles.zig").metricTrigger(28), .hover_style = .{ .background = S.theme.states().hover }, .on_click = self.cx.on(View, self, toggle) }).mount(self.scope, self.cx);
        trigger.setStyleInline(self.cx.allocator, .{ .align_items = .center, .justify = .center, .padding = .{}, .gap = 0 });
        trigger.meta.ownership.meta.test_id = id;
        try trigger.appendChild(self.cx.allocator, try S.theme.icon(self.cx, ui.icons.list_restart, "fg_2", .{ .width = .{ .px = 16 }, .height = .{ .px = 16 } }));
        try bar.appendChild(self.cx.allocator, trigger);
        for (&self.own_triggers) |*slot| if (slot.* == null) {
            slot.* = trigger;
            break;
        };
        return trigger;
    }
    const trigger_name = "命令历史";
    /// 触发按钮的无障碍名“命令历史 · ⇧⌘B”：快捷键文字由宿主从快捷键路由同步。
    pub fn syncShortcut(self: *View, hint_text: []const u8) void {
        if (self.trigger_synced and std.mem.eql(u8, self.trigger_hint, hint_text)) return;
        self.trigger_synced = true;
        self.trigger_hint = hint_text;
        self.trigger_flip ^= 1;
        const buffer = &self.trigger_text[self.trigger_flip];
        const value = if (hint_text.len == 0) trigger_name else std.fmt.bufPrint(buffer, "{s} · {s}", .{ trigger_name, hint_text }) catch trigger_name;
        for (self.own_triggers) |slot| if (slot) |trigger| if (trigger.behavior.interaction.a11y) |*a11y| {
            a11y.label = value;
        };
    }
    fn terminal(self: *View) ?*Terminal {
        const index = self.workspace.active_tab orelse return null;
        if (index >= self.workspace.tabs.items.len) return null;
        const tab = self.workspace.tabs.items[index];
        if (tab.terminal == null) return null;
        return &tab.terminal.?;
    }
    pub fn show(self: *View, enabled: bool) void {
        if (enabled and self.terminal() == null) return;
        if (enabled and self.mode == .closed) self.cx.dispatcher.cancelScrollGesture();
        self.mode = if (enabled) .pinned else .closed;
        if (enabled) if (self.terminal()) |terminal_node| terminal_node.refreshCommandHistory(true);
        if (self.open.peek() != enabled) self.open.set(enabled);
        self.cx.requestRedraw();
    }
    /// Escape / outside click (the Popover's own dismissals).
    fn openChanged(self: *View, value: bool) void {
        if (!value) self.mode = .closed;
        self.cx.requestRedraw();
    }
    /// The visible trigger: the title bar button, else the local status bar's.
    fn anchorRect(raw: *anyopaque) ui.widgets.popover.AnchorRect {
        const self: *View = @ptrCast(@alignCast(raw));
        for (self.buttons) |trigger| if (trigger.isDisplayedInTree()) {
            const r = trigger.globalRect();
            if (r.w > 0 and r.h > 0) return .{ .x = r.x, .y = r.y, .w = r.w, .h = r.h };
        };
        const r = self.buttons[0].globalRect();
        return .{ .x = r.x, .y = r.y, .w = r.w, .h = r.h };
    }
    pub fn toggle(self: *View) void {
        self.show(self.mode != .pinned);
    }
    pub fn hide(self: *View) void {
        self.show(false);
    }
    fn tick(raw: *anyopaque, _: u8, _: bool) ui.AfterLayoutResult {
        const self: *View = @ptrCast(@alignCast(raw));
        self.update() catch |err| std.log.debug("command history: {s}", .{@errorName(err)});
        return .done;
    }
    fn update(self: *View) !void {
        const active = self.terminal();
        if (self.unavailable.peek() != (active == null)) self.unavailable.set(active == null);
        for (self.buttons, 0..) |button_node, index| button_node.setDisplay(if (active != null or (self.workspace_chrome and index == 0)) .flex else .none);
        if (active == null and self.mode != .closed) self.show(false);
        if (self.mode != .closed and self.root.style.display == .none) self.cx.dispatcher.cancelScrollGesture();
        self.root.setDisplay(if (self.mode == .closed) .none else .flex);
        if (self.mode == .closed) return;
        const terminal_node = active.?;
        const tab = self.workspace.tabs.items[self.workspace.active_tab.?];
        const pane = tab.root.globalRect();
        const id = @as(u64, @intCast(tab.id));
        var hasher = std.hash.Wyhash.init(id);
        terminal_node.refreshCommandHistory(false);
        const commands = terminal_node.commandHistory();
        for (commands) |command| {
            std.hash.autoHash(&hasher, .{ command.id, command.state, command.exit_code, command.ai_execution_id, command.start_ms });
            if (command.command) |text| hasher.update(text);
            const elapsed = if (terminal_node.commandElapsed(command)) |ms| ms / 250 else 0;
            hasher.update(std.mem.asBytes(&elapsed));
            if (command.state == .running) self.cx.scheduleRedrawAfterNs(250 * std.time.ns_per_ms);
        }
        hasher.update(std.mem.asBytes(&terminal_node.command_history_partial));
        hasher.update(std.mem.asBytes(&terminal_node.command_history_pending));
        self.cx.scheduleRedrawAfterNs(500 * std.time.ns_per_ms);
        const themed = self.theme_watch.take();
        if (themed or self.signature != hasher.final() or self.active_id != id) {
            self.colors = S.theme.current();
            self.signature = hasher.final();
            self.active_id = id;
            try self.rebuild(terminal_node, commands, tab.titleSlice());
        }
        const w = @min(if (self.cx.viewport.width < 1000) @as(f32, 320) else S.width, @max(0, pane.w - 24));
        const content_height: f32 = if (self.visible_count == 0) 70 else self.virtual.totalContentHeight();
        const h = @min(@min(@as(f32, 475), @max(120, pane.h - 24)), 86 + content_height);
        // The Popover places it under (or, without room, above) the trigger.
        if (self.root.style.width != .px or self.root.style.width.px != w or self.root.style.height != .px or self.root.style.height.px != h)
            self.root.setStyleInline(self.cx.allocator, .{ .width = .{ .px = w }, .height = .{ .px = h } });
    }
    fn clearRecords(self: *View) void {
        for (self.records.items) |command| if (command.command) |text| self.cx.allocator.free(text);
        self.records.deinit(self.cx.allocator);
        self.records = .empty;
    }
    fn rebuild(self: *View, _: *Terminal, commands: []const Command, owner_name: []const u8) !void {
        self.clearRecords();
        try self.records.ensureTotalCapacity(self.cx.allocator, commands.len);
        for (commands) |command| {
            var copy = command;
            copy.command = if (command.command) |text| try self.cx.allocator.dupe(u8, text) else null;
            self.records.appendAssumeCapacity(copy);
        }
        std.mem.sort(Command, self.records.items, {}, struct {
            fn less(_: void, left: Command, right: Command) bool {
                return left.id > right.id;
            }
        }.less);
        self.visible_count = self.records.items.len;
        self.empty.setDisplay(if (self.visible_count == 0) .flex else .none);
        self.scroll.container.setDisplay(if (self.visible_count == 0) .none else .flex);
        const terminal_node = self.terminal().?;
        self.setSubtitle(owner_name, if (terminal_node.command_history_partial) " · 部分记录" else if (terminal_node.command_history_pending) " · 同步中" else "");
        ui.widgets.virtual_list.updateItemCount(self.virtual, self.visible_count);
        ui.widgets.virtual_list.refreshRange(self.virtual, 0, self.visible_count);
    }
    fn setSubtitle(self: *View, owner_name: []const u8, suffix: []const u8) void {
        var count: [160]u8 = undefined;
        var line: [200]u8 = undefined;
        const base = panel_header.countText(&count, self.visible_count, owner_name);
        const text = std.fmt.bufPrint(&line, "{s}{s}", .{ base, suffix }) catch base;
        if (!std.mem.eql(u8, self.subtitle.peek(), text)) self.subtitle.set(text);
    }
    fn renderItem(node: *ui.Node, index: usize, _: *ui.Cx, raw: ?*anyopaque) void {
        const self: *View = @ptrCast(@alignCast(raw orelse return));
        self.renderRecord(node, index) catch |err| std.log.debug("command history row: {s}", .{@errorName(err)});
    }
    fn renderRecord(self: *View, node: *ui.Node, index: usize) !void {
        if (index >= self.records.items.len) return;
        node.setStyleInline(self.cx.allocator, .{ .width = .fill(), .height = .{ .fit = .{} }, .padding = .{ .bottom = 8 }, .flex_shrink = 0 });
        var found: ?Row = null;
        for (self.rows.items) |row| if (row.root.parent == node) {
            found = row;
            break;
        };
        const row = found orelse try self.makeRow(node);
        const value = self.records.items[index];
        const terminal_node = self.terminal() orelse return;
        row.action.id = value.id;
        row.action.owner_id = self.active_id;
        row.root.setDisplay(.flex);
        row.card.setStyleInline(self.cx.allocator, S.row());
        row.command.setTextColor(self.colors.fg_1);
        row.state.setTextColor(switch (value.state) {
            .running => self.colors.accent_ink,
            .succeeded => self.colors.ok_ink,
            .failed => self.colors.danger_ink,
            .unknown => self.colors.fg_3,
        });
        try row.state.setTextContent(self.cx.allocator, annotations.glyph(value.state));
        row.meta.setTextColor(self.colors.fg_2);
        try row.command.setTextContent(self.cx.allocator, value.command orelse "命令文本未知");
        const location_available = terminal_node.commandLocationAvailable(value.id);
        if (location_available) try row.tip.setTextContent(self.cx.allocator, value.command orelse "命令文本未知") else {
            const tooltip = try std.fmt.allocPrint(self.cx.allocator, "{s}\n\n原输出位置不在当前保留范围中，可在会话记录中回看。", .{value.command orelse "命令文本未知"});
            defer self.cx.allocator.free(tooltip);
            try row.tip.setTextContent(self.cx.allocator, tooltip);
        }
        var date: [48]u8 = undefined;
        const date_text = if (value.start_ms > 0) @import("../../history/view/history_styles.zig").dateLabel(&date, value.start_ms) else "时间未知";
        var elapsed: [40]u8 = undefined;
        const elapsed_text = try annotations.duration(&elapsed, terminal_node.commandElapsed(value));
        var code: [30]u8 = undefined;
        const code_text = if (value.exit_code) |exit| try std.fmt.bufPrint(&code, "{d}", .{exit}) else "—";
        var meta: [180]u8 = undefined;
        try row.meta.setTextContent(self.cx.allocator, try std.fmt.bufPrint(&meta, "{s}{s} · {s} · {s}{s}", .{ date_text, if (value.ai_execution_id != null) " · AI" else "", code_text, elapsed_text, if (location_available) "" else " · 定位不可用" }));
    }
    fn makeRow(self: *View, host_node: *ui.Node) !Row {
        // `fill`: the record card is the Tooltip trigger. zenit's filled trigger takes the list column's width (min 0), so
        // every card spans the column and a long command wraps inside it; a content-sized trigger made short commands
        // narrow cards and long ones wider than the panel (cut off at its right edge).
        const tip = try ui.widgets.Tooltip(.{ .text = "", .position = .left, .width = @as(f32, 400), .wrap = .char, .font_size = 12, .background = self.colors.overlay, .text_color = self.colors.fg_1, .fill = true }).mount(self.scope, self.cx);
        tip.wrapper.setStyleInline(self.cx.allocator, .{ .flex_shrink = 0 });
        const row = tip.trigger;
        row.setStyleInline(self.cx.allocator, S.row());
        row.meta.ownership.meta.test_id = "terminal.command-history.record";
        tip.content.meta.ownership.meta.test_id = "terminal.command-history.tooltip";
        const headline = try ui.box(self.cx, .{ .width = .fill(), .height = .{ .fit = .{} }, .direction = .row, .align_items = .start, .gap = 7, .min_width = 0 }, .{});
        const state = try ui.text(self.cx, "", S.text(12, 500, false));
        state.setStyleInline(self.cx.allocator, .{ .width = .{ .px = 12 }, .flex_shrink = 0 });
        try headline.appendChild(self.cx.allocator, state);
        var command_style = S.text(12, 400, false);
        command_style.use_monospace_font = true;
        command_style.wrap = .char;
        const command = try ui.text(self.cx, "", command_style);
        command.setStyleInline(self.cx.allocator, .{ .width = .fill(), .height = .{ .fit = .{} }, .max_height = 54, .min_width = 0, .flex = 1, .overflow = .hidden });
        command.meta.ownership.meta.test_id = "terminal.command-history.command";
        try headline.appendChild(self.cx.allocator, command);
        const meta = try ui.text(self.cx, "", S.text(10.5, 400, true));
        meta.setStyleInline(self.cx.allocator, .{ .width = .fill(), .height = .{ .px = 18 }, .padding = .{ .left = 19 } });
        try row.appendChild(self.cx.allocator, headline);
        try row.appendChild(self.cx.allocator, meta);
        const action = try self.scope.createState(Action, .{ .view = self });
        _ = ui.clickable(row, self.cx.on(Action, action, Action.invoke));
        try host_node.appendChild(self.cx.allocator, tip.wrapper);
        const result: Row = .{ .root = tip.wrapper, .card = row, .state = state, .command = command, .meta = meta, .tip = tip.content.children.items[0], .tip_open = tip.open, .action = action };
        try self.rows.append(self.cx.allocator, result);
        return result;
    }
    fn cleanup(self: *View) void {
        self.cx.removeAfterLayoutHook(self);
        self.clearRecords();
        self.rows.deinit(self.cx.allocator);
        self.cx.allocator.destroy(self);
    }
};
