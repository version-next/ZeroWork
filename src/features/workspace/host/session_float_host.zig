//! 会话卡片的浮动宿主（cards-float，用户判定“ssh类的也是可以floating的啊”）：终端（本地 / SSH）、文件
//! （SFTP）、KVM 以及注册表里所有会话类卡片都可以浮动。窗口一个宿主，挂在通用浮动层上。
//!
//! - 分屏窗格头部与单卡 tab 的窗格头部的“浮动”经 `Workspace.SessionFloatPort` 交到这里；下一帧把会话的
//!   同一个内容节点（`SessionTab.root`）从 tab body 搬进统一外框（`float_chrome`），会话照常运行：滚动、
//!   选中、输入、连接、传输、KVM 画面都在这个节点里，不重建。
//! - 浮动卡片仍属于原 tab（单卡 tab，或它所在的组 tab）：切换 tab 时收回到所属 tab，切回时展开（Z12）。
//!   单卡 tab 的卡片浮动出去后 tab 留在标签栏上，tab body 显示“卡片已浮动”（workspace）。
//! - 外框五个动作由注册表推出（`card_types.floatDescriptor`）：作为标签页打开 = 回到自己的单卡 tab（来自分屏
//!   时移出组，保留会话）；放入分屏 = 回到所属 tab 的分屏（单卡 tab 就是放回原位）；收起 = 会话卡片不支持，
//!   置灰并写原因；放大 = 浮动层；关闭 = 关闭这个会话（照常走关闭确认）。
//! - 键盘：点在浮动卡片里就把它设为当前会话（搜索、右键菜单、快捷键都作用于它），Esc 交给终端本身
//!   （浮动层的“Esc 关闭卡片”不用于会话卡片）。
const std = @import("std");
const ui = @import("ui");
const card_types = @import("../../../host/card_types.zig");
const float_layer = @import("../../../shared/ui/float_card/float_layer.zig");
const surface_migration = @import("../../../shared/ui/surface/surface_migration.zig");
const float_chrome = @import("../../../shared/ui/float_card/float_chrome.zig");
const float_card = @import("../../../shared/base/float_card.zig");
const float_card_motion = @import("../../../shared/ui/styles/float_card_motion.zig");
const floating_input = @import("../../../shared/ui/components/floating_input/floating_input.zig");
const workspace_view = @import("../view/workspace.zig");
const Workspace = workspace_view.Workspace;

/// Test ids of the floating session card (one card type look for every session card).
pub const ids: float_chrome.Ids = .{
    .root = "session.float.panel",
    .grip = "session.float.drag",
    .header = "session.float.header",
    .subtitle = "session.float.subtitle",
    .open_as_tab = "session.float.open_as_tab",
    .dock_to_split = "session.float.dock_to_split",
    .minimize = "session.float.minimize",
    .maximize = "session.float.maximize",
    .close = "session.float.close",
    .open_as_tab_tooltip = "session.float.open_as_tab.tooltip",
    .dock_to_split_tooltip = "session.float.dock_to_split.tooltip",
    .minimize_tooltip = "session.float.minimize.tooltip",
    .maximize_tooltip = "session.float.maximize.tooltip",
    .close_tooltip = "session.float.close.tooltip",
};

pub const Host = struct {
    cx: *ui.Cx,
    scope: *ui.Scope,
    workspace: *Workspace,
    layer: *float_layer.FloatLayer,
    cards: std.ArrayList(*Card) = .empty,
    requests: std.ArrayList(Request) = .empty,
    put_backs: std.ArrayList(u64) = .empty,

    const Request = struct { session: u64, from: ?ui.ComputedRect };

    pub fn mount(cx: *ui.Cx, scope: *ui.Scope, workspace: *Workspace, layer: *float_layer.FloatLayer) !*Host {
        const self = try scope.createState(Host, .{ .cx = cx, .scope = scope, .workspace = workspace, .layer = layer });
        workspace.session_float = .{ .ctx = self, .float = requestFloat, .put_back = requestPutBack };
        try cx.addAfterLayoutHook(self, frame);
        try scope.onCleanup(Host, self, cleanup);
        return self;
    }

    fn cleanup(self: *Host) void {
        self.cx.removeAfterLayoutHook(self);
        self.workspace.session_float = null;
        // The window is closing: the content nodes go back to the workspace, which tears them down.
        for (self.cards.items) |card| card.release();
        self.cards.deinit(self.cx.allocator);
        self.requests.deinit(self.cx.allocator);
        self.put_backs.deinit(self.cx.allocator);
    }

    fn requestFloat(raw: *anyopaque, session: u64, from: ?ui.ComputedRect) void {
        const self: *Host = @ptrCast(@alignCast(raw));
        self.requests.append(self.cx.allocator, .{ .session = session, .from = from }) catch return;
        self.cx.requestRedraw();
    }

    fn requestPutBack(raw: *anyopaque, session: u64) void {
        const self: *Host = @ptrCast(@alignCast(raw));
        self.put_backs.append(self.cx.allocator, session) catch return;
        self.cx.requestRedraw();
    }

    fn find(self: *Host, session: u64) ?*Card {
        for (self.cards.items) |card| if (card.session == session) return card;
        return null;
    }

    /// The strip id of the tab shown now (a group's tab while a split is shown).
    pub fn currentTab(self: *Host) ?u64 {
        const workspace = self.workspace;
        if (workspace.active_group_view) |group| return if (workspace.groupTabId(group)) |tab| @backingInt(tab) else null;
        const index = workspace.active_tab orelse return null;
        return if (index < workspace.tabs.items.len) @backingInt(workspace.tabs.items[index].tab_id) else null;
    }

    fn frame(raw: *anyopaque, _: u8, _: bool) ui.AfterLayoutResult {
        const self: *Host = @ptrCast(@alignCast(raw));
        var changed = false;
        if (self.requests.items.len != 0) {
            const pending = self.requests.toOwnedSlice(self.cx.allocator) catch return .done;
            defer self.cx.allocator.free(pending);
            for (pending) |request| {
                if (self.find(request.session) != null) continue;
                const card = Card.create(self, request.session, request.from) catch |err| {
                    self.workspace.statusFailure(@errorName(err));
                    continue;
                };
                self.cards.append(self.cx.allocator, card) catch {
                    card.putBack(.split);
                    card.destroy();
                    continue;
                };
                changed = true;
            }
        }
        if (self.put_backs.items.len != 0) {
            for (self.put_backs.items) |session| if (self.find(session)) |card| card.putBack(.split);
            self.put_backs.clearRetainingCapacity();
            changed = true;
        }
        var index: usize = self.cards.items.len;
        while (index > 0) {
            index -= 1;
            const card = self.cards.items[index];
            if (!card.closing) card.sync();
            if (card.closing) {
                _ = self.cards.orderedRemove(index);
                card.destroy();
                changed = true;
            }
        }
        if (changed) self.cx.requestRedraw();
        return if (changed) .needs_layout else .done;
    }
};

const Card = struct {
    host: *Host,
    scope: *ui.Scope,
    session: u64,
    node: *ui.Node,
    chrome: *float_chrome.Chrome,
    float: *float_layer.Card,
    placement: float_card.Placement = .{},
    owner_tab: u64,
    descriptor: float_card.Descriptor,
    title: [128]u8 = undefined,
    title_len: usize = 0,
    action: ?float_card.HeaderAction = null,
    closing: bool = false,

    fn create(host: *Host, session: u64, from: ?ui.ComputedRect) !*Card {
        const cx = host.cx;
        const workspace = host.workspace;
        const tab = workspace.sessionTab(session) orelse return error.UnknownSession;
        if (workspace.floatRefusal(session)) |_| return error.FloatRefused;
        const descriptor = card_types.floatDescriptor(tab.card_type) orelse return error.PlacementNotAllowed;
        // A failure after the frame joined the layer takes the frame down again, after the card's
        // scope (declared first: runs last).
        var frame: ?*ui.Node = null;
        errdefer if (frame) |node| {
            if (node.parent) |parent| cx.detachChild(parent, node);
            cx.destroyDetached(node);
        };
        const scope = try host.scope.childScope();
        errdefer scope.dispose();
        const self = try scope.createState(Card, .{ .host = host, .scope = scope, .session = session, .node = undefined, .chrome = undefined, .float = undefined, .owner_tab = 0, .descriptor = descriptor });
        const name = workspace.shownName(tab);
        self.title_len = @min(name.len, self.title.len);
        while (self.title_len > 0 and !std.unicode.utf8ValidateSlice(name[0..self.title_len])) self.title_len -= 1;
        @memcpy(self.title[0..self.title_len], name[0..self.title_len]);
        self.chrome = try float_chrome.Chrome.mount(cx, scope, .{
            .title = self.title[0..self.title_len],
            .icon = workspace.floatCardIcon(tab),
            .type_title = tab.card_type.title,
            .descriptor = descriptor,
            .ids = ids,
            .labels = .{ .close = "关闭此会话" },
        });
        // The subtitle names the kind ("SSH", a plugin's name) unless the title already says it.
        const kind = workspace.floatCardKind(tab);
        if (!std.mem.eql(u8, kind, self.title[0..self.title_len])) self.chrome.setSubtitle(kind);
        self.node = try ui.box(cx, .{ .position = .absolute, .direction = .column }, .{});
        frame = self.node;
        floating_input.protect(cx, self.node);
        floating_input.protect(cx, self.chrome.root);
        // Escape belongs to the session (vim, less, a shell's line editor): the layer's
        // "Escape closes the card" is not installed on a session card.
        self.node.behavior.events.on_key_down = keepKey;
        self.node.behavior.events.key_context = self;
        // A pointer down inside makes this the current session (search, menus, shortcuts).
        self.chrome.body.behavior.events.on_event_capture = bodyCapture;
        self.chrome.body.behavior.events.capture_context = self;
        self.float = try host.layer.attach(scope, .{
            .node = self.node,
            .chrome = self.chrome,
            .descriptor = descriptor,
            .placement = &self.placement,
            .callbacks = .{ .ctx = self, .close = closeFloat, .action = headerAction },
            .grip_test_id = ids.grip,
            .handle_test_ids = .{ "session.float.resize.n", "session.float.resize.s", "session.float.resize.w", "session.float.resize.e", "session.float.resize.nw", "session.float.resize.ne", "session.float.resize.sw", "session.float.resize.se" },
        });
        // The frame is in the window now: the session's content moves into it in one step
        // (`surface_migration`), so what the session holds — focus, an IME composition, its
        // selection — is never dropped on the way.
        const take = try workspace.takeFloatSession(session, .{ .parent = self.chrome.body });
        self.owner_tab = take.owner_tab;
        errdefer workspace.returnFloatSession(session, .split, null, null) catch {};
        const content = workspace.terminal_area.globalRect();
        self.float.update(.{ .content = .{ .x = content.x, .y = content.y, .width = content.w, .height = content.h } }, true);
        self.float.unfoldFrom(self.owner_tab, if (from) |r| .{ .x = r.x, .y = r.y, .width = r.w, .height = r.h } else null);
        host.layer.raise(self.float);
        self.focusSession();
        const to = self.float.rect();
        trace("float", host.layer.currentMode(), from, .{ .x = to.x, .y = to.y, .w = to.width, .h = to.height }, session);
        return self;
    }

    /// The session's input surface takes the keyboard (the terminal, else the content root).
    fn focusSession(self: *Card) void {
        const workspace = self.host.workspace;
        const index = workspace.tabIndex(self.session) orelse return;
        const tab = workspace.tabs.items[index];
        workspace.setActiveTab(index);
        for (workspace.tabs.items) |other| if (other.plugin_renderer) |renderer| renderer.vtable.focus_changed(renderer.context, other.id == self.session);
        self.host.cx.setFocus(if (tab.terminal) |*terminal| terminal.root else tab.root);
    }

    fn sync(self: *Card) void {
        const host = self.host;
        const workspace = host.workspace;
        const tab = workspace.sessionTab(self.session) orelse {
            // The session closed (its content node was detached and torn down with it).
            self.closing = true;
            return;
        };
        if (!tab.floating) {
            self.closing = true;
            return;
        }
        if (self.action) |action| {
            self.action = null;
            switch (action) {
                .open_as_tab => if (workspace.floatTabRefusal(self.session) == null) return self.putBack(.own_tab),
                .dock_to_split => if (workspace.floatDockRefusal(self.session) == null) return self.putBack(.split),
                .close => if (workspace.tabIndex(self.session)) |index| workspace.requestCloseTab(index),
                .minimize, .maximize => {},
            }
        }
        if (workspace.floatOwnerTab(self.session)) |owner| self.owner_tab = owner;
        const current = host.currentTab();
        const shown = current != null and current.? == self.owner_tab;
        const content = workspace.terminal_area.globalRect();
        self.float.update(.{ .content = .{ .x = content.x, .y = content.y, .width = content.w, .height = content.h } }, shown);
        self.float.present(.{ .shown = shown, .tab = self.owner_tab, .current_tab = current });
        self.chrome.setActionState(.open_as_tab, workspace.floatTabRefusal(self.session));
        self.chrome.setActionState(.dock_to_split, workspace.floatDockRefusal(self.session));
    }

    /// Back into the tab body (`split`) or into its own single-card tab (`own_tab`): the floating frame
    /// leaves without motion and the pane flies in from it (Z12 anchor mode) or fades in.
    fn putBack(self: *Card, to: Workspace.PutBack) void {
        const host = self.host;
        const from = self.chrome.root.globalRect();
        const mode = host.layer.currentMode();
        const flight: workspace_view.GroupFlight = .{ .anchor = if (mode == .anchor and from.w > 0 and from.h > 0) .{ .rect = .{ .x = from.x, .y = from.y, .w = from.w, .h = from.h } } else .none, .tokens = float_card_motion.placeTokens(mode) };
        self.float.hideForDock();
        host.workspace.returnFloatSession(self.session, to, from, flight) catch |err| host.workspace.statusFailure(@errorName(err));
        trace(if (to == .own_tab) "tab" else "dock", mode, from, null, self.session);
        self.closing = true;
    }

    /// Window shutdown: hand the content node back to the workspace without motion.
    fn release(self: *Card) void {
        const workspace = self.host.workspace;
        if (workspace.sessionTab(self.session)) |tab| if (tab.floating) {
            tab.setFloating(false);
            surface_migration.move(self.host.cx, tab.root, .{ .parent = workspace.terminal_area }) catch surface_migration.park(self.host.cx, tab.root);
        };
    }

    fn destroy(self: *Card) void {
        const cx = self.host.cx;
        self.float.cancel();
        // Still floating (the card failed to settle): the content goes back to its tab body first.
        if (self.host.workspace.sessionTab(self.session)) |tab| if (tab.floating) {
            self.host.workspace.returnFloatSession(self.session, .split, null, null) catch self.release();
        };
        const node = self.node;
        self.scope.dispose();
        if (node.parent) |parent| cx.detachChild(parent, node);
        cx.destroyDetached(node);
        cx.requestRedraw();
    }

    fn trace(action: []const u8, mode: float_layer.TransitionMode, from: ?ui.ComputedRect, to: ?ui.ComputedRect, session: u64) void {
        if (!@import("../../../platform/runtime_mode.zig").automation) return;
        const r = from orelse ui.ComputedRect{ .x = 0, .y = 0, .w = 0, .h = 0 };
        const t = to orelse ui.ComputedRect{ .x = 0, .y = 0, .w = 0, .h = 0 };
        std.debug.print("ZW_SESSION_FLOAT {{\"action\":\"{s}\",\"session\":{d},\"mode\":\"{s}\",\"from\":[{d:.1},{d:.1},{d:.1},{d:.1}],\"to\":[{d:.1},{d:.1},{d:.1},{d:.1}]}}\n", .{ action, session, @tagName(mode), r.x, r.y, r.w, r.h, t.x, t.y, t.w, t.h });
    }

    fn headerAction(ctx: ?*anyopaque, action: float_card.HeaderAction) bool {
        const self: *Card = @ptrCast(@alignCast(ctx orelse return false));
        switch (action) {
            .open_as_tab, .dock_to_split, .close => {},
            .minimize, .maximize => return false,
        }
        self.action = action;
        self.host.cx.requestRedraw();
        return true;
    }
    fn closeFloat(ctx: ?*anyopaque) void {
        const self: *Card = @ptrCast(@alignCast(ctx orelse return));
        self.action = .close;
        self.host.cx.requestRedraw();
    }
    fn keepKey(_: ui.events.KeyCode, _: ui.events.Modifiers, _: ?*anyopaque) ui.events.EventResult {
        return .ignored;
    }
    fn bodyCapture(event: ui.events.Event, raw: ?*anyopaque) ui.events.EventResult {
        const self: *Card = @ptrCast(@alignCast(raw orelse return .ignored));
        if (event == .mouse_down) {
            const workspace = self.host.workspace;
            if (workspace.tabIndex(self.session)) |index| if (workspace.active_tab != index) {
                workspace.setActiveTab(index);
                for (workspace.tabs.items) |other| if (other.plugin_renderer) |renderer| renderer.vtable.focus_changed(renderer.context, other.id == self.session);
            };
        }
        return .ignored;
    }
};
