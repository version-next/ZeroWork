//! Bounded single-card queue. Receipts remain authoritative; widgets emit frozen
//! versioned commands and never edit, remove or dispatch an optimistic copy.
const std = @import("std");
const app_menu = @import("../../../shell/mod.zig").app_menu;
const ui = @import("ui");
const IdSpace = @import("../../shared/view/ai_id_space.zig").IdSpace;
const input = @import("../../../../ai/session_input.zig");
const S = @import("ai_pending_styles.zig");
const T = @import("../../../../shared/ui/theme/app_theme.zig");
pub const Ticket = struct { receipt: input.Receipt, queue_revision: u64 };
pub const Action = enum { save, remove, now, up, down, continue_queue, copy_text, inspect };
pub const Item = struct { receipt: input.Receipt, text: []const u8, attachments: usize = 0, mutable: bool = true };
pub const Hooks = struct { context: *anyopaque, act: *const fn (*anyopaque, Ticket, Action, []const u8) anyerror!void };
/// The reader's editing of a queued message and the fold of the queue. This is the reader's state,
/// not the view's: its owner keeps one and mounts each view on it (`View.mountOn`), so a view that
/// is released and built again shows the same editor with the same text.
pub const Edit = struct {
    editing: ?Ticket = null,
    collapsed: bool = false,
    text: *ui.Signal([]const u8),
    original: *ui.Signal([]const u8),
    pub fn init(scope: *ui.Scope) !Edit {
        return .{ .text = try scope.createText("", .{}), .original = try scope.createText("", .{}) };
    }
};
pub const View = struct {
    /// Test-id namespace of the surface this view is mounted in (main assistant / child dialog).
    space: IdSpace,
    cx: *ui.Cx,
    scope: *ui.Scope,
    hooks: Hooks,
    edit: *Edit,
    root: *ui.Node,
    header: *ui.Node,
    surface: *ui.Node,
    toggle_focus_requested: bool = false,
    menus: []?*ui.Signal(bool) = &.{},
    scroll: ui.widgets.ScrollAreaResult,
    rows: ?*ui.Scope = null,
    retained: std.ArrayList(RetainedRow) = .empty,
    header_hash: ?u64 = null,
    header_ticket: ?*Ticket = null,
    toggle_node: ?*ui.Node = null,
    hash: ?u64 = null,
    edit_requested: ?Ticket = null,
    cancel_requested: bool = false,
    scroll_top_requested: bool = false,
    editor_scroll_requested: ?f32 = null,
    edit_text: *ui.Signal([]const u8),
    edit_original: *ui.Signal([]const u8),
    error_text: *ui.Signal([]const u8),
    error_node: *ui.Node,
    const RetainedRow = struct { root: *ui.Node, scope: *ui.Scope, hash: u64, ticket: *Ticket, editor: ?*ui.Node = null };
    pub fn mount(cx: *ui.Cx, scope: *ui.Scope, hooks: Hooks) !*View {
        return mountOn(cx, scope, hooks, null);
    }
    /// `edit` null: the view keeps its own (it then lives and dies with this view).
    pub fn mountOn(cx: *ui.Cx, scope: *ui.Scope, hooks: Hooks, shared_edit: ?*Edit) !*View {
        const edit = shared_edit orelse try scope.createState(Edit, try Edit.init(scope));
        const space = IdSpace.of(scope);
        const root = try ui.box(cx, S.root(), .{});
        root.meta.ownership.meta.test_id = space.id("ai.pending");
        const surface = try ui.box(cx, S.surface(), .{});
        surface.meta.ownership.meta.test_id = space.id("ai.pending.surface");
        try root.appendChild(cx.allocator, surface);
        const header = try ui.box(cx, S.row(), .{});
        try surface.appendChild(cx.allocator, header);
        const scroll = try ui.widgets.ScrollArea(.{ .direction = .vertical, .height = 0, .rubber_band_y = false }).mount(scope, cx);
        scroll.container.setStyleInline(cx.allocator, .{ .width = .fill(), .height = .{ .px = 0 }, .min_height = 0, .flex_shrink = 0, .overflow_hidden = true, .composited_group = true });
        // Reserve the scrollbar thumb plus its hit slop even before it appears.
        scroll.content.setStyleInline(cx.allocator, .{ .width = .fill(), .direction = .column, .gap = 0, .padding = .{ .right = 16 } });
        scroll.container.meta.ownership.meta.test_id = space.id("ai.pending.scroll");
        try surface.appendChild(cx.allocator, scroll.container);
        const error_text = try scope.createText("", .{});
        const error_node = try ui.text(cx, "", S.queueText(true));
        error_node.setStyleInline(cx.allocator, .{ .width = .fill(), .height = .{ .fit = .{} }, .min_width = 0, .flex_shrink = 0 });
        error_node.setDisplay(.none);
        try root.appendChild(cx.allocator, error_node);
        root.setDisplay(.none);
        const result = try scope.createState(View, .{ .space = space, .cx = cx, .scope = scope, .hooks = hooks, .root = root, .header = header, .surface = surface, .scroll = scroll, .edit = edit, .edit_text = edit.text, .edit_original = edit.original, .error_text = error_text, .error_node = error_node });
        try scope.onCleanup(View, result, cleanup);
        return result;
    }
    fn cleanup(self: *View) void {
        self.retained.deinit(self.cx.allocator);
        self.cx.allocator.free(self.menus);
    }
    fn removeRow(self: *View, index: usize) void {
        const old = self.retained.orderedRemove(index);
        self.cx.detachChild(self.scroll.content, old.root);
        old.scope.dispose();
        self.cx.destroyDetached(old.root);
    }
    const Cell = struct {
        view: *View,
        ticket: *Ticket,
        action: Action = .remove,
        initial: []const u8 = "",
        fn run(self: *Cell) void {
            self.view.hooks.act(self.view.hooks.context, self.ticket.*, self.action, if (self.action == .save) self.view.edit_text.peek() else "") catch |err| self.view.fail(@errorName(err));
        }
        fn edit(self: *Cell) void {
            self.view.edit_requested = self.ticket.*;
            self.view.edit_text.set(self.initial);
            self.view.edit_original.set(self.initial);
            self.view.cx.requestRedraw();
        }
        fn toggle(self: *Cell) void {
            self.view.edit.collapsed = !self.view.edit.collapsed;
            self.view.toggle_focus_requested = true;
            self.view.hash = null;
            self.view.cx.requestRedraw();
        }
        fn cancel(self: *Cell) void {
            self.view.cancel_requested = true;
            self.view.cx.requestRedraw();
        }
    };
    pub fn fail(self: *View, label: []const u8) void {
        const message = @import("../../../../ai/error_feedback.zig").localFailureLabel(label) orelse label;
        self.error_text.set(message);
        self.error_node.setTextContent(self.cx.allocator, message) catch {};
        self.error_node.setDisplay(.flex);
        self.cx.requestRedraw();
    }
    pub fn finishEdit(self: *View) void {
        self.cancel_requested = true;
        self.cx.requestRedraw();
    }
    pub fn scrollToTop(self: *View) void {
        self.scroll_top_requested = true;
        self.cx.requestRedraw();
    }
    const Button = struct { node: *ui.Node, wrapper: *ui.Node, focused: *ui.Signal(bool) };
    const Reveal = struct {
        cx: *ui.Cx,
        hovered: *ui.Signal(bool),
        focused: [4]?*ui.Signal(bool) = @splat(null),
        extra: [2]?Button = @splat(null),
        menu_open: ?*ui.Signal(bool) = null,
        fn apply(self: *Reveal) void {
            var active = self.hovered.get();
            for (self.focused) |focused| if (focused) |signal| {
                active = signal.get() or active;
            };
            if (self.menu_open) |open| active = open.get() or active;
            for (self.extra) |entry| if (entry) |b| {
                b.wrapper.setOpacityRaw(if (active) 1 else 0);
                b.node.setHitTestVisible(active);
            };
            self.cx.requestRedraw();
        }
    };
    fn button(self: *View, scope: *ui.Scope, row: *ui.Node, icon: []const u8, hint: []const u8, id: []const u8, disabled: bool, handler: ?ui.Handler(void), hide_hint_while: ?*ui.Signal(bool)) !Button {
        // Native ghost xs icon Button (Pencil Kaf7E A8: 20, icon 12) in a native Tooltip.
        const tooltip = try ui.widgets.Tooltip(.{ .text = hint, .position = .top }).mount(scope, self.cx);
        tooltip.wrapper.setStyleInline(self.cx.allocator, .{ .flex_shrink = 0 });
        const node = try ui.widgets.Button(.{ .icon_only = true, .icon_asset = ui.icons.get(icon).?, .a11y_label = hint, .variant = .ghost, .size = .xs, .disabled = disabled, .on_click = handler }).mount(scope, self.cx);
        node.meta.ownership.meta.test_id = id;
        try tooltip.trigger.appendChild(self.cx.allocator, node);
        try row.appendChild(self.cx.allocator, tooltip.wrapper);
        const focused = try ui.hooks.useFocusState(scope, self.cx, node);
        try scope.createEffect(.{ .view = self, .node = node, .focused = focused.visible, .tooltip = tooltip.open, .hide_hint_while = hide_hint_while }, struct {
            fn apply(ctx: anytype) void {
                // Tab may reach a row outside the bounded queue viewport: reveal it.
                if (ctx.focused.get()) ui.widgets.scrollIntoView(ctx.view.scroll.state, ctx.view.scroll.content, ctx.node, .nearest);
                // No hint over the row's own open menu.
                if (ctx.tooltip) |open| if (ctx.hide_hint_while) |signal| if (signal.get()) open.set(false);
            }
        }.apply);
        return .{ .node = node, .wrapper = tooltip.wrapper, .focused = focused.focused };
    }
    const PendingMenu = struct {
        ids: [4][]const u8 = undefined,
        cells: [4]*Cell = undefined,
        fn select(raw: *anyopaque, id: []const u8) void {
            const self: *PendingMenu = @ptrCast(@alignCast(raw));
            for (self.ids, self.cells, 0..) |known, target, at| if (std.mem.eql(u8, known, id)) {
                if (at == 0) target.edit() else target.run();
                return;
            };
        }
    };
    fn more(self: *View, scope: *ui.Scope, row: *ui.Node, cell: *Cell, index: usize, count: usize, reorder: bool, data: std.mem.Allocator) !struct { button: Button, open: ?*ui.Signal(bool) } {
        const space = self.space;
        // 经菜单唯一入口（app_menu，menus 包）：编辑在前，上移 / 下移其次，移除消息是危险项、排最后。
        const menu_state = try scope.createState(PendingMenu, .{});
        menu_state.ids = .{ "edit", "up", "down", "remove" };
        menu_state.cells[0] = cell;
        const entries = [_]app_menu.Entry{
            .{ .id = "edit", .label = "编辑消息", .icon = "pencil", .test_id = space.id("ai.pending.menu.edit") },
            .{ .id = "up", .label = "上移", .icon = "arrow-up", .group = 1, .disabled = !reorder or index == 0, .test_id = space.id("ai.pending.menu.up") },
            .{ .id = "down", .label = "下移", .icon = "arrow-down", .group = 1, .disabled = !reorder or index + 1 == count, .test_id = space.id("ai.pending.menu.down") },
            .{ .id = "remove", .label = "移除消息", .icon = "x", .danger = true, .test_id = space.id("ai.pending.menu.remove") },
        };
        inline for (.{ .{ Action.up, 1 }, .{ Action.down, 2 }, .{ Action.remove, 3 } }) |spec| {
            menu_state.cells[spec[1]] = try scope.createState(Cell, .{ .view = self, .ticket = cell.ticket, .action = spec[0] });
        }
        const mounted = try app_menu.AppMenu.mountTrigger(self.cx, scope, .{ .panel_test_id = "", .position = .top_end }, .{ .context = menu_state, .select = PendingMenu.select });
        const no_keys = struct {
            const map: @import("../../../shell/mod.zig").shortcut_router.Map = .{};
        };
        mounted.menu.set(&entries, .{ .keys = &no_keys.map });
        const menu = mounted.result;
        menu.wrapper.setStyleInline(self.cx.allocator, .{ .flex_shrink = 0 });
        const b = try self.button(scope, menu.trigger, "ellipsis", "更多消息操作", try space.alloc(data, "ai.pending.more.{d}", .{index}), false, null, menu.open);
        try row.appendChild(self.cx.allocator, menu.wrapper);
        self.menus[index] = menu.open;
        return .{ .button = b, .open = menu.open };
    }
    fn clear(self: *View, node: *ui.Node) void {
        while (node.children.items.len != 0) {
            const child = node.children.items[0];
            self.cx.detachChild(node, child);
            self.cx.destroyDetached(child);
        }
    }
    pub fn update(self: *View, items: []const Item, queue_revision: u64, compact: bool, continuing: bool) !bool {
        const space = self.space;
        const begin_edit = self.edit_requested != null;
        if (self.cancel_requested) {
            self.edit.editing = null;
            self.cancel_requested = false;
            self.hash = null;
            self.error_node.setDisplay(.none);
            self.scroll_top_requested = true;
        }
        if (self.edit_requested) |ticket| {
            self.edit.editing = ticket;
            self.edit_requested = null;
            self.hash = null;
        }
        var h = std.hash.Wyhash.init(0);
        std.hash.autoHash(&h, .{ queue_revision, compact, continuing, T.current() });
        for (items) |item| {
            std.hash.autoHash(&h, .{ item.receipt, item.attachments, item.mutable });
            h.update(item.text);
        }
        const hash = h.final();
        if (self.hash == hash) {
            if (self.editor_scroll_requested) |offset| {
                ui.widgets.setScrollY(self.scroll.state, self.scroll.content, offset);
                self.editor_scroll_requested = null;
            }
            if (self.scroll_top_requested) {
                ui.widgets.setScrollY(self.scroll.state, self.scroll.content, 0);
                self.scroll_top_requested = false;
            }
            return false;
        }
        for (self.menus) |menu| if (menu) |open| if (open.peek()) {
            self.cx.cancelPointerInteractions(.explicit);
            open.set(false);
        };
        if (self.cx.pressed_node) |node| if (node.isDescendantOf(self.root)) self.cx.cancelPointerInteractions(.explicit);
        self.menus = try self.cx.allocator.realloc(self.menus, items.len);
        // Retained rows own their scopes independently of the header.
        while (self.retained.items.len > items.len) self.removeRow(self.retained.items.len - 1);
        var header_hash = std.hash.Wyhash.init(0);
        std.hash.autoHash(&header_hash, .{ items.len, continuing, self.edit.collapsed, self.edit.editing != null, T.current() });
        if (self.header_ticket) |ticket| {
            if (items.len > 0) ticket.* = .{ .receipt = items[0].receipt, .queue_revision = queue_revision };
        }
        if (self.header_hash != header_hash.final()) {
            self.clear(self.header);
            if (self.rows) |old| old.dispose();
            const scope = try self.scope.childScope();
            self.rows = scope;
            const arena = try scope.createState(std.heap.ArenaAllocator, .init(self.cx.allocator));
            try scope.onCleanup(std.heap.ArenaAllocator, arena, struct {
                fn cleanup(value: *std.heap.ArenaAllocator) void {
                    value.deinit();
                }
            }.cleanup);
            const data = arena.allocator();
            self.header_ticket = try scope.createState(Ticket, if (items.len > 0) .{ .receipt = items[0].receipt, .queue_revision = queue_revision } else undefined);
            self.root.setStyleInline(self.cx.allocator, S.root());
            self.surface.setStyleInline(self.cx.allocator, S.surface());
            self.root.setDisplay(if (items.len == 0) .none else .flex);
            const label = try std.fmt.allocPrint(data, "待处理 · {d}", .{items.len});
            try self.header.appendChild(self.cx.allocator, try ui.iconTint(self.cx, ui.icons.get("list-ordered").?, T.current().fg_3, S.glyph()));
            try self.header.appendChild(self.cx.allocator, try ui.text(self.cx, label, S.headerText()));
            try self.header.appendChild(self.cx.allocator, try ui.spacer(self.cx));
            if (items.len > 0 and continuing) {
                const cell = try scope.createState(Cell, .{ .view = self, .ticket = self.header_ticket.?, .action = .continue_queue });
                _ = try self.button(scope, self.header, "play", "继续队列", space.id("ai.pending.continue"), false, self.cx.on(Cell, cell, Cell.run), null);
            }
            self.toggle_node = null;
            if (items.len > 0) {
                const cell = try scope.createState(Cell, .{ .view = self, .ticket = self.header_ticket.? });
                const toggle = try self.button(scope, self.header, if (self.edit.collapsed) "chevron-down" else "chevron-up", if (self.edit.collapsed) "展开消息队列" else "收起消息队列", space.id("ai.pending.toggle"), self.edit.editing != null, self.cx.on(Cell, cell, Cell.toggle), null);
                self.toggle_node = toggle.node;
            }
            self.header_hash = header_hash.final();
        }
        var content_height: f32 = 0;
        var editor_node: ?*ui.Node = null;
        var has_editor = false;
        for (items, 0..) |item, index| {
            const editing = if (self.edit.editing) |edit| edit.receipt.id.eql(item.receipt.id) else false;
            var row_hash = std.hash.Wyhash.init(0);
            std.hash.autoHash(&row_hash, .{ item.receipt, item.attachments, item.mutable, index, index + 1 == items.len, editing, T.current() });
            row_hash.update(item.text);
            const fingerprint = row_hash.final();
            if (index < self.retained.items.len and self.retained.items[index].hash == fingerprint) {
                const kept = self.retained.items[index];
                kept.ticket.* = .{ .receipt = item.receipt, .queue_revision = queue_revision };
                if (editing) {
                    has_editor = true;
                    editor_node = kept.editor;
                }
                content_height += if (editing) S.edit_height else S.row_height;
                continue;
            }
            const before = if (index < self.retained.items.len) self.retained.items[index].root else null;
            const scope = try self.scope.childScope();
            errdefer scope.dispose();
            const arena = try scope.createState(std.heap.ArenaAllocator, .init(self.cx.allocator));
            try scope.onCleanup(std.heap.ArenaAllocator, arena, struct {
                fn release(value: *std.heap.ArenaAllocator) void {
                    value.deinit();
                }
            }.release);
            const data = arena.allocator();
            const ticket = try scope.createState(Ticket, .{ .receipt = item.receipt, .queue_revision = queue_revision });
            self.menus[index] = null;
            const card = try ui.box(self.cx, S.card(), .{});
            card.meta.ownership.meta.test_id = try space.alloc(data, "ai.pending.card.{d}", .{index});
            if (editing) {
                has_editor = true;
                self.editor_scroll_requested = content_height;
                card.setStyleInline(self.cx.allocator, .{ .height = .{ .px = S.edit_height }, .direction = .column, .align_items = .stretch, .gap = 4 });
                const editor = try ui.widgets.Textarea(.{ .value = self.edit_text, .rows = 2, .placeholder = "编辑排队消息" }).mountResult(scope, self.cx);
                editor.wrapper.setStyleInline(self.cx.allocator, .{ .width = .fill(), .height = .{ .px = 48 }, .flex_shrink = 0 });
                editor.input.meta.ownership.meta.test_id = space.id("ai.pending.editor");
                editor_node = editor.input;
                try card.appendChild(self.cx.allocator, editor.wrapper);
            }
            const row = if (editing) try ui.box(self.cx, S.row(), .{}) else card;
            if (editing) try card.appendChild(self.cx.allocator, row);
            const state = if (item.receipt.delivery == .outcome_unknown) "待核对" else if (item.receipt.pause != null) "已暂停" else if (item.receipt.delivery != .queued) "待处理" else "排队";
            const status = try std.fmt.allocPrint(data, "{s} · {d}{s}", .{ state, index + 1, if (item.attachments != 0) " · 含附件" else "" });
            const status_node = try ui.text(self.cx, "", S.stateText());
            try status_node.setTextContent(self.cx.allocator, status);
            status_node.setStyleInline(self.cx.allocator, .{ .width = .{ .fit = .{} }, .flex_shrink = 0 });
            status_node.meta.ownership.meta.test_id = try space.alloc(data, "ai.pending.status.{d}", .{index});
            status_node.behavior.interaction.a11y = .{ .label = status };
            try row.appendChild(self.cx.allocator, status_node);
            if (!editing) {
                const text = try ui.text(self.cx, "", S.queueText(false));
                try text.setTextContent(self.cx.allocator, item.text);
                text.setStyleInline(self.cx.allocator, .{ .width = .fill(), .min_width = 0, .height = .{ .px = 18 }, .flex_shrink = 1 });
                try row.appendChild(self.cx.allocator, text);
                if (item.attachments != 0) {
                    try row.appendChild(self.cx.allocator, try ui.iconTint(self.cx, ui.icons.get("paperclip").?, T.current().fg_2, .{ .width = .{ .px = 12 }, .height = .{ .px = 12 }, .flex_shrink = 0 }));
                    try row.appendChild(self.cx.allocator, try ui.text(self.cx, try std.fmt.allocPrint(data, "{d}", .{item.attachments}), S.stateText()));
                }
            } else try row.appendChild(self.cx.allocator, try ui.spacer(self.cx));
            const mutable = item.mutable and item.receipt.delivery == .queued and !item.receipt.archived;
            const cell = try scope.createState(Cell, .{ .view = self, .ticket = if (editing) try scope.createState(Ticket, self.edit.editing.?) else ticket, .initial = try data.dupe(u8, item.text) });
            if (editing) {
                cell.action = .save;
                _ = try self.button(scope, row, "x", "取消编辑", space.id("ai.pending.cancel"), false, self.cx.on(Cell, cell, Cell.cancel), null);
                _ = try self.button(scope, row, "check", "保存排队消息", space.id("ai.pending.save"), !mutable, self.cx.on(Cell, cell, Cell.run), null);
            } else if (mutable and item.receipt.pause != .environment) {
                const reveal = try scope.createState(Reveal, .{ .cx = self.cx, .hovered = try ui.hooks.useHover(scope, card) });
                const edit = try self.button(scope, row, "pencil", "编辑排队消息", try space.alloc(data, "ai.pending.edit.{d}", .{index}), false, self.cx.on(Cell, cell, Cell.edit), null);
                reveal.extra[0] = edit;
                reveal.focused[0] = edit.focused;
                const remove_cell = try scope.createState(Cell, .{ .view = self, .ticket = ticket, .action = .remove });
                const remove = try self.button(scope, row, "x", "移除排队消息", try space.alloc(data, "ai.pending.remove.{d}", .{index}), false, self.cx.on(Cell, remove_cell, Cell.run), null);
                reveal.extra[1] = remove;
                reveal.focused[1] = remove.focused;
                const now_cell = try scope.createState(Cell, .{ .view = self, .ticket = ticket, .action = .now });
                const now = try self.button(scope, row, "arrow-up", "立即引导当前任务", try space.alloc(data, "ai.pending.now.{d}", .{index}), item.receipt.pause != null, self.cx.on(Cell, now_cell, Cell.run), null);
                reveal.focused[2] = now.focused;
                const menu = try self.more(scope, row, cell, index, items.len, item.receipt.pause == null, data);
                reveal.menu_open = menu.open;
                reveal.focused[3] = menu.button.focused;
                try scope.createEffect(reveal, Reveal.apply);
            } else {
                if (item.receipt.delivery != .outcome_unknown) {
                    const copy = try scope.createState(Cell, .{ .view = self, .ticket = ticket, .action = .copy_text });
                    _ = try self.button(scope, row, "copy", "复制文字到草稿", space.id("ai.pending.copy_text"), false, self.cx.on(Cell, copy, Cell.run), null);
                }
                const inspect_cell = try scope.createState(Cell, .{ .view = self, .ticket = ticket, .action = .inspect });
                _ = try self.button(scope, row, "eye", "查看待处理消息", space.id("ai.pending.inspect"), false, self.cx.on(Cell, inspect_cell, Cell.run), null);
                if (mutable) {
                    const remove = try scope.createState(Cell, .{ .view = self, .ticket = ticket, .action = .remove });
                    _ = try self.button(scope, row, "x", "移除排队消息", space.id("ai.pending.remove_paused"), false, self.cx.on(Cell, remove, Cell.run), null);
                }
            }
            try self.scroll.content.insertChildBefore(self.cx.allocator, card, before);
            const next: RetainedRow = .{ .root = card, .scope = scope, .hash = fingerprint, .ticket = ticket, .editor = if (editing) editor_node else null };
            if (before != null) {
                self.removeRow(index);
                try self.retained.insert(self.cx.allocator, index, next);
            } else try self.retained.append(self.cx.allocator, next);
            content_height += if (editing) S.edit_height else S.row_height;
        }
        self.scroll.container.setStyleInline(self.cx.allocator, .{ .height = .{ .px = if (self.edit.collapsed and !has_editor) 0 else @min(if (has_editor) S.edit_height else if (compact) S.row_height * 2 else S.row_height * 3, content_height) } });
        if (self.scroll_top_requested) {
            ui.widgets.setScrollY(self.scroll.state, self.scroll.content, 0);
            self.scroll_top_requested = false;
        }
        self.scroll.container.setDisplay(if (self.edit.collapsed and !has_editor) .none else .flex);
        if (self.toggle_focus_requested) {
            self.toggle_focus_requested = false;
            if (self.toggle_node) |node| self.cx.setFocus(node);
        }
        // Focus only a newly requested editor after its row is attached.
        if (begin_edit) if (editor_node) |node| self.cx.setFocus(node);
        self.hash = hash;
        self.cx.requestRedraw();
        return true;
    }
};
