/// Menu component: command set expanding from a trigger element (dropdown / context menu),
/// Popover-based.
///
/// Features:
/// - Menu items + separators + group headings, optional icon/shortcut hint/danger style/disabled
///   state
/// - Two (compatible) receive modes: per-item `on_click` callback, or whole `on_select` with item
///   id
/// - items from signal / derived: a new array rebuilds items
/// - Keyboard navigation (ArrowUp/Down/Enter/Escape)
/// - Optional max height (overflow scrolls in panel)
const std = @import("std");
const Allocator = std.mem.Allocator;
const core = @import("../../core.zig");
const view = @import("../../view.zig");
const Cx = core.Cx;
const Node = core.Node;
const box = core.box;
const Color = core.Color;
const theme = core.theme;
const reactive = @import("../../reactive.zig");
const Signal = reactive.Signal;
const Scope = reactive.Scope;
const Source = reactive.Source;
const Model = reactive.Model;
const Handler = core.Handler;
const events = @import("../../events.zig");
const Event = events.Event;
const EventResult = events.EventResult;
const KeyCode = events.KeyCode;
const Modifiers = events.Modifiers;
const popover_mod = @import("../popover/mod.zig");
const floating = @import("../../compute_position.zig");
const pointer_grace = @import("../popover/pointer_grace.zig");
const time = @import("zenit_time");
const system_icons = @import("zenit_system_icons");
const submenu_hover_ns = 150 * std.time.ns_per_ms;
const svg_assets = @import("../../svg_assets.zig");
const bind_mod = @import("../../bind.zig");
pub const TagColor = @import("../tag/mod.zig").TagColor;

// Styling layer (recipe + named style functions) in styles.yss; re-exported here to keep public API
// stable
const styles = @import("_styles.yss.zig");
const views = @import("_menu.yix.zig");
/// Menu item appearance recipe (root / label / icon slots; danger / lit / disabled switches)
pub const MenuItemRecipe = styles.MenuRow;

/// Menu item type
pub const MenuItemKind = enum {
    item,
    separator,
    /// Group heading: a caption (`label`) that starts a group of items. Not selectable: keyboard
    /// navigation, typeahead and the pointer pass over it; `id`, `shortcut`, `icon_asset`,
    /// `children` and `on_click` are ignored.
    header,
};

/// Menu item
pub const MenuItem = struct {
    /// Nested menu. Static trees are copied at mount; leaf selection closes ancestors.
    children: []const MenuItem = &.{},
    /// Test id of the nested menu's popup panel (`children` non-empty). Empty = none.
    submenu_test_id: []const u8 = "",
    /// Max height of the nested menu's panel; a longer list scrolls inside it (as
    /// `MenuProps.max_height`). null = fit the rows.
    submenu_max_height: ?f32 = null,
    /// Item identifier (received by `on_select`)
    id: []const u8 = "",
    /// Display text
    label: []const u8 = "",
    /// Test id of the row node (e2e / harness lookup). Empty = none. Copied with static items,
    /// borrowed from signal items like the other strings.
    test_id: []const u8 = "",
    /// Type: normal item or separator
    kind: MenuItemKind = .item,
    disabled: bool = false,
    /// Why the item is unavailable. On a disabled item it is shown after the label (secondary
    /// colour) and is the row's accessibility description; ignored while the item is enabled.
    disabled_reason: ?[]const u8 = null,
    /// Second line under the label (secondary colour, xs, wraps): what the choice does. The row
    /// grows and aligns to the top; it is the row's accessibility description (after a disabled
    /// reason). Copied with static items, borrowed from signal items.
    description: ?[]const u8 = null,
    /// Native sm Tag at the right of the row (before the shortcut), e.g. "Interactive".
    tag: ?[]const u8 = null,
    tag_color: TagColor = .neutral,
    /// Persistent selected state. The check replaces the leading icon.
    selected: bool = false,
    /// Shortcut hint text
    shortcut: ?[]const u8 = null,
    /// Dangerous operation style (red)
    danger: bool = false,
    /// Left icon (optional)
    icon_asset: ?svg_assets.Asset = null,
    /// Icon colour override (e.g. a colour swatch row). null = the row's icon colour (follows the
    /// label: normal / danger / disabled). A disabled row keeps the disabled colour.
    icon_tint: ?Color = null,
    /// Command callback for this item; menu requests close via toggle pipeline, then calls
    /// on_select, then it
    on_click: ?Handler(void) = null,
};

/// Menu properties
pub const MenuProps = struct {
    trigger: popover_mod.PopoverTrigger = .click,
    /// Used by nested menus to return focus to their parent on Left/Escape.
    on_back: ?Handler(void) = null,
    /// Menu items. Static array copied at mount with strings (caller can pass function-local
    /// array);
    /// signal / derived borrow current value: new array rebuilds, old array and strings must stay
    /// valid until replaced. Handler context still follows Scope lifecycle. Items beyond MAX_ITEMS
    /// not rendered.
    items: Source([]const MenuItem) = .{ .value = &.{} },
    /// Toggle: `bool` uncontrolled; `*Signal(bool)` controlled (interaction writes directly);
    /// `ui.split` intercepts
    open: Model(bool) = .{ .local = false },
    on_open_change: ?Handler(bool) = null,
    /// Select an item (item id, valid only in this call, copy to keep). After select menu requests
    /// close via toggle pipeline
    on_select: ?Handler([]const u8) = null,
    /// Panel width. By default the widest row determines it.
    width: ?f32 = null,
    /// Popup position
    position: popover_mod.PopoverPosition = .bottom_start,
    /// Popup anchor. null = the trigger slot (dropdown, default). A context menu passes a
    /// `.virtual` anchor that returns the pointer position (zero-size rect) together with
    /// `.trigger = .manual` and a controlled `open`, and sets `open` from its own pointer
    /// handler (right click, or Shift+F10 / the context-menu key at the caret): the panel opens
    /// at the press point and is re-positioned every frame, the trigger slot only holds the
    /// wrapper. Focus moves into the menu and returns to the previously focused node on close,
    /// as for a trigger-anchored menu. Root menu only; nested menus anchor to their row.
    anchor: ?popover_mod.Anchor = null,
    /// Optional menu max height. When set, reuses Popover's native fit_or_scroll / ScrollArea.
    max_height: ?f32 = null,
    /// The trigger takes the width it is given instead of its content's (Popover
    /// `fill_trigger`): a full-width row that opens a menu (a sidebar switcher) keeps its layout.
    fill_trigger: bool = false,
    /// Test id of the popup panel (popover chrome, in the overlay portal) — the menu's rows live
    /// there, not under the wrapper that a `testId` attribute names. Empty = none. Read at mount.
    panel_test_id: []const u8 = "",
    /// Fixed colour scheme of the panel and its submenus (as `PopoverProps.color_scheme`): a menu
    /// over content with its own scheme (remote video) keeps it whatever the app theme. null =
    /// follow the app theme. Read at mount.
    color_scheme: ?core.theme.ColorScheme = null,
};

/// Menu mount result
pub const MenuResult = struct {
    /// Outer wrapper node
    wrapper: *Node,
    /// trigger slot (caller inserts trigger element here)
    trigger: *Node,
    /// Toggle signal (`ui.split` -> null)
    open: ?*Signal(bool),
    /// The menu panel (the popover content holding the rows; portaled while open). For a caller
    /// that has to tell whether a node is inside its menu (a press that started in it), instead of
    /// reaching the panel through the Menu's state.
    panel: *Node,
    /// `ui.view` integration (see src/ui/view_parts.zig). Menu rows come from `items`, so children go
    /// to the trigger (Yix `<W.Menu items={…}><W.Button …/></W.Menu>`); `.trigger(…)` keeps working.
    pub fn viewParts(self: MenuResult) core.ViewParts {
        return .{ .root = self.wrapper, .slot = self.trigger, .trigger = self.trigger };
    }
};

/// Menu internal state (owned by Popover scope, lifetime with menu)
pub const MenuState = struct {
    const ActiveRoot = struct { menu: ?*MenuState = null };
    const root_state_id = std.hash.Wyhash.hash(0, "zenit.ui.menu.active_root");

    const Submenu = struct {
        menu: *MenuState,
        open: *Signal(bool),
    };
    was_open: bool = false,
    previous_focus: ?core.NodeHandle = null,
    cx: *Cx,
    /// Current highlight index (keyboard navigation and select use it)
    highlighted_index: usize = 0,
    /// Keyboard highlight, independent of the hovered row.
    highlighted: *Signal(usize),
    keyboard_focus: *Signal(bool),
    hovered: *Signal(usize),
    pointer_row: ?usize = null,
    submenu_timer: ?u64 = null,
    hover_started_ns: i128 = 0,
    grace_until_ns: i128 = 0,
    submenu_origin: ?core.Point = null,
    active_submenu: ?usize = null,
    typeahead: [32]u8 = undefined,
    typeahead_len: usize = 0,
    typeahead_ns: i128 = 0,
    root_menu: ?*MenuState,
    active_root: ?*ActiveRoot,
    close_task: reactive.SignalOwner.SettledTask = .{},
    scope: *Scope,
    trigger: *Node,
    show: Handler(void),
    toggle: Handler(void),
    open_read: Source(bool),
    chrome: *Node,
    position: *const popover_mod.PopoverPosition,
    color_scheme: ?core.theme.ColorScheme = null,
    pointer_open: bool = false,
    keyboard_open: ?bool = null,
    /// Currently rendered menu items (click / keyboard activate by it, matches screen)
    items: []const MenuItem = &.{},
    /// Deep copy of static items (null if from signal source, borrows current value)
    owned_items: ?[]MenuItem = null,
    /// Menu item UI nodes (for highlight style switching)
    item_nodes: [MAX_ITEMS]?*Node = @as([MAX_ITEMS]?*Node, @splat(null)),
    /// Actual rendered item count
    item_count: usize = 0,
    on_select: ?Handler([]const u8),
    /// Request close: goes through Popover toggle pipeline
    close: Handler(void),
    /// Container holding keyboard focus (aria-activedescendant attached to it)
    menu_node: ?*Node = null,
    on_back: ?Handler(void) = null,
    submenus: [MAX_ITEMS]?Submenu = @splat(null),

    pub const MAX_ITEMS = 64;
    /// highlight's "no highlight" value
    const no_highlight = std.math.maxInt(usize);

    fn deinit(self: *MenuState, allocator: Allocator) void {
        self.clearSubmenuTimer();
        self.close_task.cancel();
        if (self.active_root) |root| {
            if (root.menu == self) root.menu = null;
        }
        if (self.owned_items) |owned| freeItems(allocator, owned);
        self.owned_items = null;
        self.items = &.{};
    }

    /// Select current highlighted item: request close first, then notify on_select, then execute
    /// item's callback.
    /// All callbacks may destroy menu or swap items: extract needed values first, don't touch self
    /// after.
    /// id is borrowed (static items owned by state, signal items by caller), close request may
    /// invalidate it,
    /// so copy; all runs in one batch, effect-driven unmount/rebuild deferred after callbacks.
    pub fn selectHighlighted(self: *MenuState) void {
        self.pick(self.highlighted_index, true);
    }

    fn pick(self: *MenuState, index: usize, keyboard: bool) void {
        if (index >= self.items.len) return;
        const item = self.items[index];
        if (item.kind != .item or item.disabled) return;
        if (item.children.len > 0) {
            self.openSubmenu(index, keyboard);
            return;
        }
        const on_select = self.on_select;
        const close = self.close;
        const cx = self.cx;

        var id_buf: [256]u8 = undefined;
        var heap_id: ?[]u8 = null;
        defer if (heap_id) |h| cx.allocator.free(h);
        const id: []const u8 = if (item.id.len <= id_buf.len) blk: {
            @memcpy(id_buf[0..item.id.len], item.id);
            break :blk id_buf[0..item.id.len];
        } else blk: {
            heap_id = cx.allocator.dupe(u8, item.id) catch {
                std.log.err("[Menu] out of memory copying item id; selection dropped", .{});
                return;
            };
            break :blk heap_id.?;
        };

        cx.owner.beginBatch();
        defer cx.owner.endBatch();
        close.invoke();
        if (on_select) |h| h.call(id);
        if (item.on_click) |h| h.invoke();
    }

    /// Switch highlight to index
    pub fn highlightIndex(self: *MenuState, index: usize) void {
        if (index >= self.item_count) return;
        if (self.items[index].kind != .item) return;
        self.highlighted_index = index;
        self.highlighted.set(index);
        self.keyboard_focus.set(true);

        if (self.item_nodes[index]) |node| {
            if (self.menu_node) |menu_node| {
                if (menu_node.behavior.interaction.a11y) |*a| {
                    a.active_descendant_element_id = node.element_id_raw;
                }
                menu_node.markRenderDirty();
            }
        }
    }

    fn clearSubmenuTimer(self: *MenuState) void {
        if (self.submenu_timer) |id| self.cx.clearTimer(id);
        self.submenu_timer = null;
    }

    fn scheduleSubmenu(self: *MenuState, delay_ns: u64) void {
        self.clearSubmenuTimer();
        self.submenu_timer = self.cx.setTimer(delay_ns, submenuTimerFired, self) catch null;
    }

    fn submenuTimerFired(raw: ?*anyopaque) void {
        const self: *MenuState = @ptrCast(@alignCast(raw orelse return));
        self.submenu_timer = null;
        self.updateSubmenu();
    }

    fn point(self: *const MenuState) core.Point {
        return .{ .x = self.cx.mouse_x, .y = self.cx.mouse_y };
    }

    fn closeSubmenus(self: *MenuState, keep: ?usize) void {
        for (self.submenus, 0..) |entry, i| {
            if (keep == i) continue;
            if (entry) |sub| sub.open.set(false);
        }
        self.active_submenu = keep;
    }

    fn openSubmenu(self: *MenuState, index: usize, keyboard: bool) void {
        const sub = self.submenus[index] orelse return;
        self.clearSubmenuTimer();
        self.closeSubmenus(index);
        self.submenu_origin = self.point();
        self.grace_until_ns = 0;
        if (keyboard) {
            if (sub.open.peek()) {
                sub.menu.focusInitial(true);
                return;
            }
            sub.menu.keyboard_open = true;
        }
        sub.open.set(true);
    }

    /// Follow the actual side after a viewport flip. While the pointer is in
    /// the corridor, a sibling row cannot close or replace this submenu.
    fn updateSubmenu(self: *MenuState) void {
        if (!self.open_read.peek()) return;
        const now = time.monotonicTimestamp(self.cx.io);
        const pointer = self.point();
        if (self.active_submenu) |index| {
            const sub = self.submenus[index].?;
            if (sub.open.peek() and self.cx.pointerLive()) {
                if (self.pointer_row == index) {
                    self.hovered.set(index);
                    return;
                }
                const rect = sub.menu.chrome.globalRect();
                if (rect.contains(pointer.x, pointer.y)) return;
                if (self.submenu_origin) |origin| {
                    if (now < self.grace_until_ns and pointer_grace.contains(origin, pointer, rect, floating.getSide(sub.menu.position.*))) {
                        self.scheduleSubmenu(@intCast(@min(24 * std.time.ns_per_ms, self.grace_until_ns - now)));
                        return;
                    }
                }
            }
            self.closeSubmenus(null);
        }
        self.hovered.set(self.pointer_row orelse no_highlight);
        if (self.pointer_row) |index| {
            if (self.cx.pointerLive() and self.submenus[index] != null) {
                const remaining = submenu_hover_ns - (now - self.hover_started_ns);
                if (remaining > 0) self.scheduleSubmenu(@intCast(remaining)) else self.openSubmenu(index, false);
            }
        }
    }

    fn enterIndex(self: *MenuState, index: usize) void {
        self.pointer_row = index;
        self.hover_started_ns = time.monotonicTimestamp(self.cx.io);
        self.clearSubmenuTimer();
        self.updateSubmenu();
    }

    fn leaveIndex(self: *MenuState, index: usize) void {
        if (self.pointer_row == index) self.pointer_row = null;
        self.clearSubmenuTimer();
        if (self.active_submenu) |active| {
            if (active == index) {
                self.grace_until_ns = time.monotonicTimestamp(self.cx.io) + pointer_grace.duration_ms * std.time.ns_per_ms;
            }
            // Enter/leave callbacks arrive in order. Allow the new target
            // event to supply the row before deciding whether to switch.
            self.scheduleSubmenu(0);
        } else {
            self.hovered.set(no_highlight);
        }
    }

    fn focusInitial(self: *MenuState, forward: bool) void {
        const start = if (forward) self.items.len -| 1 else 0;
        if (nextEnabledIndex(self.items, start, forward)) |index| self.highlightIndex(index);
        if (self.menu_node) |node| self.cx.setFocus(node);
    }

    fn typeaheadKey(self: *MenuState, key: u8) void {
        const now = time.monotonicTimestamp(self.cx.io);
        if (now - self.typeahead_ns > 600 * std.time.ns_per_ms or self.typeahead_len == self.typeahead.len) self.typeahead_len = 0;
        self.typeahead_ns = now;
        const cycle = self.typeahead_len == 1 and self.typeahead[0] == key;
        if (!cycle) {
            self.typeahead[self.typeahead_len] = key;
            self.typeahead_len += 1;
        }
        const needle = self.typeahead[0..self.typeahead_len];
        const len = self.items.len;
        if (len == 0) return;
        const start = if (needle.len > 1) self.highlighted_index else if (self.keyboard_focus.peek()) self.highlighted_index + 1 else 0;
        for (0..len) |step| {
            const index = (start + step) % len;
            const item = self.items[index];
            if (item.kind == .item and !item.disabled and item.label.len >= needle.len and
                std.ascii.eqlIgnoreCase(item.label[0..needle.len], needle))
            {
                self.highlightIndex(index);
                return;
            }
        }
    }

    /// Rebuild key: content + string address + callback (strings borrowed, address change stales
    /// a11y label on old nodes)
    fn itemsKey(items: []const MenuItem) u64 {
        return itemsKeyDepth(items, 0);
    }
    fn itemsKeyDepth(items: []const MenuItem, depth: usize) u64 {
        if (depth > 8) return 0;
        var h = std.hash.Wyhash.init(0);
        h.update(std.mem.asBytes(&items.len));
        for (items) |it| {
            hashStr(&h, it.id);
            hashStr(&h, it.label);
            hashStr(&h, it.test_id);
            hashStr(&h, it.submenu_test_id);
            if (it.submenu_max_height) |height| h.update(std.mem.asBytes(&height)) else h.update("\x00");
            if (it.shortcut) |sc| hashStr(&h, sc) else h.update("\x00");
            if (it.disabled_reason) |why| hashStr(&h, why) else h.update("\x00");
            if (it.description) |about| hashStr(&h, about) else h.update("\x00");
            if (it.tag) |text| hashStr(&h, text) else h.update("\x00");
            h.update(&.{@backingInt(it.tag_color)});
            h.update(&.{ @backingInt(it.kind), @intFromBool(it.disabled), @intFromBool(it.danger), @intFromBool(it.selected) });
            const icon: usize = if (it.icon_asset) |a| @intFromPtr(a.svg_data.ptr) else 0;
            if (it.icon_tint) |tint| h.update(std.mem.asBytes(&tint)) else h.update("\x00");
            const child_key = if (it.children.len > 0) itemsKeyDepth(it.children, depth + 1) else 0;
            h.update(std.mem.asBytes(&child_key));
            h.update(std.mem.asBytes(&icon));
            if (it.on_click) |c| {
                h.update(std.mem.asBytes(&@intFromPtr(c.callback)));
                h.update(std.mem.asBytes(&@intFromPtr(c.context)));
            } else h.update("\x00");
        }
        return h.final();
    }

    fn hashStr(h: *std.hash.Wyhash, s: []const u8) void {
        h.update(std.mem.asBytes(&s.len));
        h.update(std.mem.asBytes(&@intFromPtr(s.ptr)));
        h.update(s);
    }

    /// Build menu items. Click context registered on `items_scope`, freed on rebuild;
    /// node table built locally, published only if all succeed (fail case rebuildOn clears subtree,
    /// state stays valid)
    fn buildItems(self: *MenuState, items_scope: *Scope, item_list: *Node, all_items: []const MenuItem) !void {
        const cx = self.cx;

        // Old nodes already freed by rebuildOn: clear references to them first
        self.items = &.{};
        self.item_nodes = @as([MAX_ITEMS]?*Node, @splat(null));
        self.item_count = 0;
        self.clearSubmenuTimer();
        self.submenus = @splat(null);
        self.pointer_row = null;
        self.active_submenu = null;
        self.submenu_origin = null;
        self.hovered.set(no_highlight);
        self.typeahead_len = 0;
        self.highlighted_index = 0;
        self.highlighted.set(no_highlight);
        if (self.menu_node) |menu_node| {
            if (menu_node.behavior.interaction.a11y) |*a| a.active_descendant_element_id = 0xFFFFFFFF;
        }

        // Only render first MAX_ITEMS; keyboard nav / select limited same range, else can activate
        // invisible items
        const items = all_items[0..@min(all_items.len, MAX_ITEMS)];
        var nodes = @as([MAX_ITEMS]?*Node, @splat(null));
        var submenus: [MAX_ITEMS]?Submenu = @splat(null);

        try view.mount(items_scope, cx, item_list, view.items(RowCtx{ .state = self, .nodes = &nodes, .submenus = &submenus }, items, rowElement));

        self.item_nodes = nodes;
        self.submenus = submenus;
        self.item_count = items.len;
        self.items = items;
    }

    const RowCtx = struct { state: *MenuState, nodes: *[MAX_ITEMS]?*Node, submenus: *[MAX_ITEMS]?Submenu };
    const RowArgs = struct { ctx: RowCtx, item: MenuItem, index: usize };

    fn rowElement(ctx: RowCtx, item: MenuItem, i: usize) view.ComponentOf(buildRow) {
        return view.component(buildRow, RowArgs{ .ctx = ctx, .item = item, .index = i });
    }

    /// One item (separator or menu item, view in menu.yix); node recorded in caller's local node
    /// table
    fn buildRow(args: RowArgs, scope: *Scope, cx: *Cx) !*Node {
        const item = args.item;
        const state = args.ctx.state;
        // A tinted icon (swatch row) takes the item's colour; a disabled row keeps the recipe's.
        const tinted = item.icon_tint != null and !item.disabled;
        const node = if (item.kind == .separator)
            try view.render(scope, cx, views.MenuSeparator(.{}))
        else if (item.kind == .header)
            try view.render(scope, cx, views.MenuHeader(.{ .label = item.label }))
        else
            try view.render(scope, cx, views.MenuEntry(.{
                .label = item.label,
                .index = args.index,
                .highlighted = state.highlighted,
                .keyboard_focus = state.keyboard_focus,
                .hovered = state.hovered,
                .danger = item.danger,
                .disabled = item.disabled,
                .shortcut = item.shortcut,
                .reason = if (item.disabled) item.disabled_reason else null,
                .description = item.description,
                .tag = item.tag,
                .tag_color = item.tag_color,
                .icon_asset = if (tinted) null else if (item.selected) system_icons.check else item.icon_asset,
                .tinted_icon = if (tinted) (if (item.selected) system_icons.check else item.icon_asset) else null,
                .icon_tint = item.icon_tint orelse Color.TRANSPARENT,
                .submenu_icon = if (item.children.len > 0 and !item.disabled) system_icons.chevron_right else null,
                .on_pick = Handler(usize).from(MenuState, state, MenuState.pickIndex),
            }));
        var orphan = true;
        errdefer if (orphan) cx.destroyDetached(node);
        args.ctx.nodes[args.index] = node;
        // Every row names its kind, so tests and tools tell native menu rows from look-alikes.
        node.meta.ownership.meta.component_name = switch (item.kind) {
            .item => "MenuItem",
            .separator => "MenuSeparator",
            .header => "MenuHeader",
        };
        if (item.test_id.len != 0) node.meta.ownership.meta.test_id = item.test_id;
        if (item.kind == .header) node.behavior.interaction.a11y = .{ .role = .heading, .label = item.label };
        if (item.kind == .item) node.behavior.interaction.a11y = .{
            .role = if (item.selected) .menuitemcheckbox else .menuitem,
            .label = item.label,
            .disabled = item.disabled,
            .checked = if (item.selected) true else null,
            .description = if (item.disabled and item.disabled_reason != null) item.disabled_reason else item.description orelse item.shortcut,
            .has_popup = if (item.children.len > 0 and !item.disabled) .menu else .none,
        };
        if (item.kind == .item and !item.disabled) {
            const row = try scope.createState(RowEvents, .{ .menu = state, .index = args.index });
            node.behavior.events.on_event = RowEvents.handle;
            node.behavior.events.event_context = row;
        }
        if (item.kind == .item and item.children.len > 0 and !item.disabled) {
            const open = try scope.createSignal(bool, false);
            const nested = try (Menu(.{
                .trigger = .manual,
                .items = item.children,
                .open = open,
                .position = .right_start,
                // The nested menu's trigger is its parent row: the row spans the parent panel like
                // its siblings, so `right_start` places the submenu beside the panel.
                .fill_trigger = true,
                .panel_test_id = item.submenu_test_id,
                .max_height = item.submenu_max_height,
                .color_scheme = state.color_scheme,
                .on_select = Handler([]const u8).from(MenuState, state, MenuState.childSelected),
            })).mountInternal(scope, cx, state.root_menu orelse state);
            errdefer cx.destroyDetached(nested.wrapper);
            args.ctx.submenus[args.index] = .{ .open = open, .menu = stateOf(nested) };
            orphan = false;
            _ = try core.adoptChild(cx, cx.allocator, nested.trigger, node);
            // The row component binds its scope to the node it returns. Returning the nested
            // Popover's own wrapper would take that node from the Popover's scope binding, and
            // the Popover then reads its wrapper as freed: a submenu whose rows were built while
            // the panel was detached (rebuilt between two opens) could never open again
            // (PopoverTriggerFreed). A plain host keeps the two bindings apart.
            const host = try box(cx, .{ .width = core.Sizing.fill(), .height = .{ .fit = .{} } }, .{});
            errdefer cx.destroyDetached(host);
            try host.appendChild(cx.allocator, nested.wrapper);
            return host;
        }
        orphan = false;
        return node;
    }

    const RowEvents = struct {
        menu: *MenuState,
        index: usize,

        fn handle(event: Event, raw: ?*anyopaque) EventResult {
            const row: *@This() = @ptrCast(@alignCast(raw orelse return .ignored));
            const self = row.menu;
            switch (event) {
                .mouse_enter => self.enterIndex(row.index),
                .mouse_leave => self.leaveIndex(row.index),
                .mouse_move => if (self.active_submenu == row.index) {
                    self.submenu_origin = self.point();
                },
                .mouse_up => |up| if (up.button == .left) {
                    const root = self.root_menu orelse self;
                    if (root.pointer_open) {
                        if (root.cx.dispatcher.mouseDownNode()) |down| {
                            if (down.isDescendantOf(root.trigger)) {
                                root.pointer_open = false;
                                self.pick(row.index, false);
                                return .stop;
                            }
                        }
                    }
                },
                else => {},
            }
            return .ignored;
        }
    };

    fn pickIndex(self: *MenuState, index: usize) void {
        self.pick(index, false);
    }

    fn childSelected(self: *MenuState, id: []const u8) void {
        const close = self.close;
        const notify = self.on_select;
        close.invoke();
        if (notify) |h| h.call(id);
    }

    fn triggerPress(event: Event, raw: ?*anyopaque) EventResult {
        const self: *MenuState = @ptrCast(@alignCast(raw orelse return .ignored));
        if (event == .mouse_down and event.mouse_down.button == .left) {
            self.keyboard_open = null;
            self.pointer_open = !self.open_read.peek();
            if (self.pointer_open) self.show.invoke();
        }
        return .ignored;
    }

    fn triggerClick(event: Event, raw: ?*anyopaque) EventResult {
        const self: *MenuState = @ptrCast(@alignCast(raw orelse return .ignored));
        if (event != .click) return .ignored;
        const opened_by_press = self.pointer_open and self.cx.dispatcher.mouseDownNode() != null;
        self.pointer_open = false;
        if (!opened_by_press) self.toggle.invoke();
        return .handled;
    }

    fn triggerKey(key: KeyCode, mods: Modifiers, raw: ?*anyopaque) EventResult {
        const self: *MenuState = @ptrCast(@alignCast(raw orelse return .ignored));
        if (mods.super or mods.ctrl or mods.alt) return .ignored;
        const forward = switch (key) {
            .up => false,
            .down, .@"return", .space => true,
            else => return .ignored,
        };
        if (self.open_read.peek()) {
            self.focusInitial(forward);
        } else {
            const cx = self.cx;
            const handle = cx.node_registry.handleFor(self.trigger);
            self.keyboard_open = forward;
            self.show.invoke();
            // The proposal can be rejected or synchronously unmount the menu.
            if (cx.node_registry.resolve(handle, null) != null and !self.open_read.peek()) self.keyboard_open = null;
        }
        return .stop;
    }

    fn syncOpen(self: *MenuState, open: bool) void {
        if (open == self.was_open) return;
        self.was_open = open;
        const menu = self.menu_node.?;
        if (open) {
            self.typeahead_len = 0;
            const focused = self.cx.focus_manager.getFocused();
            self.previous_focus = if (focused) |node| self.cx.node_registry.handleFor(node) else null;
            const previous = if (self.active_root) |root| root.menu else null;
            if (previous) |other| {
                if (focused == other.menu_node or other.ownsSubmenuFocus(focused)) self.previous_focus = other.previous_focus;
            }
            if (self.active_root) |root| root.menu = self;
            const keyboard_open = self.keyboard_open;
            self.keyboard_open = null;
            if (keyboard_open) |forward| {
                self.focusInitial(forward);
            } else if (self.root_menu == null) {
                self.cx.setFocus(menu);
            }
            if (previous) |other| {
                if (other != self and !other.scope.willBeDisposedAfterReactiveCallback()) {
                    other.cx.owner.runOutsideComputation(&other.close_task, other, closeReplacedRoot);
                }
            }
            return;
        }

        self.clearSubmenuTimer();
        self.pointer_row = null;
        self.hovered.set(no_highlight);
        self.highlighted.set(no_highlight);
        self.highlighted_index = 0;
        self.keyboard_focus.set(false);
        if (menu.behavior.interaction.a11y) |*a| {
            a.active_descendant_element_id = 0xFFFFFFFF;
            menu.markRenderDirty();
        }
        self.pointer_open = false;
        if (self.active_root) |root| {
            if (root.menu == self) root.menu = null;
        }
        const focused = self.cx.focus_manager.getFocused();
        const previous = self.previous_focus;
        self.previous_focus = null;
        // A nested child may hold keyboard focus while its ancestor closes.
        // Preserve the focus of a different root menu which just took over.
        const restore = focused == menu or self.ownsSubmenuFocus(focused);
        self.closeSubmenus(null);
        if (restore) if (previous) |handle| {
            if (self.cx.node_registry.resolve(handle, null)) |node| self.cx.setFocus(node);
        };
    }

    fn closeReplacedRoot(raw: *anyopaque) void {
        const self: *MenuState = @ptrCast(@alignCast(raw));
        if (self.active_root.?.menu != self and self.open_read.peek()) self.close.invoke();
    }

    fn ownsSubmenuFocus(self: *const MenuState, focused: ?*Node) bool {
        const node = focused orelse return false;
        for (self.submenus) |entry| if (entry) |sub| {
            if (sub.open.peek() and (sub.menu.menu_node == node or sub.menu.ownsSubmenuFocus(node))) return true;
        };
        return false;
    }
};

/// Create Menu: `W.Menu(.{ .items = &items, .on_select = cx.on(S, s, S.run) })`
pub fn Menu(props: anytype) MenuBuilder {
    return .{ .props = reactive.props.coerce(MenuProps, props) };
}

pub const MenuBuilder = struct {
    props: MenuProps,

    /// Retained mode: mount
    pub fn mount(self: MenuBuilder, scope: *Scope, cx: *Cx) !MenuResult {
        return self.mountInternal(scope, cx, null);
    }

    fn mountInternal(self: MenuBuilder, scope: *Scope, cx: *Cx, root: ?*MenuState) !MenuResult {
        cx.owner.enterMount();
        defer cx.owner.exitMount();
        const p = self.props;

        var pop_result = try popover_mod.Popover(.{
            .position = p.position,
            // Nested triggers are inset 4px inside the parent panel, so a
            // flush row edge gives the submenu a 4px overlap of the panel.
            .offset = .{ .static = if (root == null) @as(f32, 4) else 0 },
            .trigger = p.trigger,
            .width = p.width,
            .max_width = if (p.max_height != null) p.width else null,
            .max_height = p.max_height,
            .size_policy = @as(popover_mod.SizePolicy, if (p.max_height != null) .fit_or_scroll else .hard_clip),
            .constrain_width_to_viewport = true,
            .fill_trigger = p.fill_trigger,
            .trap_focus = false,
            .consume_outside_click = false,
            .open = p.open,
            .on_open_change = p.on_open_change,
            .anchor = if (root == null) p.anchor else null,
            .color_scheme = p.color_scheme,
        }).mount(scope, cx);
        // All menu resources and effects owned by Popover scope (on wrapper): menu content in
        // portal,
        // freed with it on unmount; effects on other scopes wake from external signals, write freed
        // nodes
        // sweep: wrapper holds until return (with Popover scope dispose); adopt subtree after build
        errdefer cx.freeNode(pop_result.wrapper);
        const menu_scope = pop_result.scope;
        if (p.panel_test_id.len != 0) pop_result.chrome.meta.ownership.meta.test_id = p.panel_test_id;

        pop_result.wrapper.meta.ownership.meta.component_name = "Menu";

        // ---- State ----
        // Do failables first: no fail points between create and adoptResource
        const highlighted = try menu_scope.createSignal(usize, MenuState.no_highlight);
        const keyboard_focus = try menu_scope.createSignal(bool, false);
        const hovered = try menu_scope.createSignal(usize, MenuState.no_highlight);
        const active_root = if (root == null and p.on_back == null)
            try cx.state(MenuState.ActiveRoot, MenuState.root_state_id, .{})
        else
            null;
        const state = try menu_scope.allocator.create(MenuState);
        state.* = .{
            .cx = cx,
            .on_select = p.on_select,
            .on_back = p.on_back,
            .close = pop_result.close,
            .highlighted = highlighted,
            .keyboard_focus = keyboard_focus,
            .hovered = hovered,
            .root_menu = root,
            .active_root = active_root,
            .scope = menu_scope,
            .trigger = pop_result.trigger,
            .show = pop_result.show,
            .toggle = pop_result.toggle,
            .open_read = pop_result.open_read,
            .chrome = pop_result.chrome,
            .position = pop_result.active_position_ptr,
            .color_scheme = p.color_scheme,
        };
        // adoptResource fails, self-destroy (with owned_items)
        try menu_scope.adoptResource(@ptrCast(state), struct {
            fn cleanup(ptr: *anyopaque, alloc: Allocator) void {
                const st: *MenuState = @ptrCast(@alignCast(ptr));
                st.deinit(alloc);
                alloc.destroy(st);
            }
        }.cleanup);
        pop_result.wrapper.addDebugState(@ptrCast(state));

        var items = p.items;
        if (p.items == .value) {
            state.owned_items = try cloneItems(menu_scope.allocator, p.items.value[0..@min(p.items.value.len, MenuState.MAX_ITEMS)]);
            items = .{ .value = state.owned_items.? };
        }

        // ---- Menu Items ----
        var item_list: *Node = undefined;
        try view.mount(menu_scope, cx, pop_result.content, view.capture(&item_list, view.box(.{ .style = styles.list }, {})));
        // The focusable popover content owns the menu role and active
        // descendant. Keeping those on the same node makes VoiceOver's
        // focusedUIElement query resolve the highlighted item; the visual
        // item_list remains an unprojected layout wrapper.
        pop_result.content.behavior.interaction.a11y = .{ .role = .menu };
        state.menu_node = pop_result.content;
        pop_result.content.setFocusable(true);

        try bind_mod.rebuildOn(cx, menu_scope, items, item_list, state, MenuState.itemsKey, MenuState.buildItems);

        // Keyboard navigation
        pop_result.content.behavior.events.on_key_down = menuKeyHandler;
        pop_result.content.behavior.events.key_context = @ptrCast(state);

        if (p.trigger == .click) {
            const trigger = pop_result.trigger;
            // Capture opens on press while leaving the child Button's normal
            // press/focus behavior intact. Only the Menu's own click toggle
            // is suppressed when that press already opened it.
            trigger.behavior.events.on_click = null;
            trigger.behavior.events.on_event_capture = MenuState.triggerPress;
            trigger.behavior.events.capture_context = state;
            trigger.behavior.events.on_event = MenuState.triggerClick;
            trigger.behavior.events.event_context = state;
            trigger.behavior.events.on_key_down = MenuState.triggerKey;
            trigger.behavior.events.key_context = state;
        }

        try menu_scope.createEffect(state, struct {
            fn update(menu: *MenuState) void {
                menu.syncOpen(menu.open_read.get());
            }
        }.update);

        return .{
            .wrapper = pop_result.wrapper,
            .trigger = pop_result.trigger,
            .open = pop_result.open,
            .panel = pop_result.content,
        };
    }
};

fn cloneItems(allocator: Allocator, source: []const MenuItem) ![]MenuItem {
    return cloneItemsDepth(allocator, source, 0);
}
fn cloneItemsDepth(allocator: Allocator, source: []const MenuItem, depth: usize) ![]MenuItem {
    if (depth > 8) return error.MenuNestingTooDeep;
    const cloned = try allocator.alloc(MenuItem, source.len);
    errdefer allocator.free(cloned);
    var initialized: usize = 0;
    errdefer for (cloned[0..initialized]) |item| {
        allocator.free(item.id);
        allocator.free(item.label);
        allocator.free(item.test_id);
        allocator.free(item.submenu_test_id);
        if (item.shortcut) |shortcut| allocator.free(shortcut);
        if (item.disabled_reason) |why| allocator.free(why);
        if (item.description) |about| allocator.free(about);
        if (item.tag) |text| allocator.free(text);
        if (item.children.len > 0) freeItems(allocator, @constCast(item.children));
    };

    for (source, 0..) |item, index| {
        const id = try allocator.dupe(u8, item.id);
        errdefer allocator.free(id);
        const label = try allocator.dupe(u8, item.label);
        errdefer allocator.free(label);
        const test_id = try allocator.dupe(u8, item.test_id);
        errdefer allocator.free(test_id);
        const submenu_test_id = try allocator.dupe(u8, item.submenu_test_id);
        errdefer allocator.free(submenu_test_id);
        const shortcut = if (item.shortcut) |value| try allocator.dupe(u8, value) else null;
        errdefer if (shortcut) |text| allocator.free(text);
        const reason = if (item.disabled_reason) |value| try allocator.dupe(u8, value) else null;
        errdefer if (reason) |text| allocator.free(text);
        const about = if (item.description) |value| try allocator.dupe(u8, value) else null;
        errdefer if (about) |text| allocator.free(text);
        const tag = if (item.tag) |value| try allocator.dupe(u8, value) else null;
        errdefer if (tag) |text| allocator.free(text);
        const children: []const MenuItem = if (item.children.len > 0) try cloneItemsDepth(allocator, item.children, depth + 1) else &.{};
        cloned[index] = item;
        cloned[index].id = id;
        cloned[index].label = label;
        cloned[index].test_id = test_id;
        cloned[index].submenu_test_id = submenu_test_id;
        cloned[index].shortcut = shortcut;
        cloned[index].disabled_reason = reason;
        cloned[index].description = about;
        cloned[index].tag = tag;
        cloned[index].children = children;
        initialized += 1;
    }
    return cloned;
}

fn freeItems(allocator: Allocator, items: []MenuItem) void {
    for (items) |item| {
        allocator.free(item.id);
        allocator.free(item.label);
        allocator.free(item.test_id);
        allocator.free(item.submenu_test_id);
        if (item.shortcut) |shortcut| allocator.free(shortcut);
        if (item.disabled_reason) |why| allocator.free(why);
        if (item.description) |about| allocator.free(about);
        if (item.tag) |text| allocator.free(text);
        if (item.children.len > 0) freeItems(allocator, @constCast(item.children));
    }
    allocator.free(items);
}

// ========== Internal helpers ==========

/// From `from` in direction, find next selectable item index, skip separator and disabled, wrap at
/// boundary.
/// Returns null if no items selectable.
fn nextEnabledIndex(items: []const MenuItem, from: usize, forward: bool) ?usize {
    const len = items.len;
    if (len == 0) return null;
    var idx = from;
    var count: usize = 0;
    while (count < len) : (count += 1) {
        if (forward) {
            idx = if (idx + 1 >= len) 0 else idx + 1;
        } else {
            idx = if (idx == 0) len - 1 else idx - 1;
        }
        if (items[idx].kind == .item and !items[idx].disabled) return idx;
    }
    return null;
}

/// Keyboard navigation handler
fn menuKeyHandler(key: KeyCode, mods: Modifiers, context: ?*anyopaque) EventResult {
    const state: *MenuState = @ptrCast(@alignCast(context orelse return .ignored));
    if (mods.super or mods.ctrl or mods.alt) return .ignored;

    switch (key) {
        .right => {
            const index = state.highlighted_index;
            if (index < state.items.len and state.items[index].children.len > 0) state.selectHighlighted();
        },
        .left, .escape => {
            if (state.on_back) |h| h.invoke() else if (key == .escape or state.root_menu != null) state.close.invoke();
        },
        // Tab never leaves an open menu (it is one focus stop with an active descendant): Tab /
        // Shift+Tab move the highlight like Down / Up.
        .down, .up, .home, .end, .tab => {
            const forward = key == .down or key == .home or (key == .tab and !mods.shift);
            const start = switch (key) {
                .home => state.items.len -| 1,
                .end => 0,
                else => state.highlighted_index,
            };
            if (nextEnabledIndex(state.items, start, forward)) |index| state.highlightIndex(index);
        },
        .@"return", .space => state.selectHighlighted(),
        else => {
            const name = @tagName(key);
            if (name.len != 1 or !std.ascii.isAlphabetic(name[0])) return .ignored;
            state.typeaheadKey(name[0]);
        },
    }
    return .stop;
}

// ========== Tests ==========

fn stateOf(r: MenuResult) *MenuState {
    return @ptrCast(@alignCast(r.wrapper.meta.ownership.debug_slots.state_ptrs[0].?));
}

const test_items = [_]MenuItem{
    .{ .id = "cut", .label = "Cut", .shortcut = "\xe2\x8c\x98X", .icon_asset = svg_assets.common.star }, // ⌘X
    .{ .id = "copy", .label = "Copy", .shortcut = "\xe2\x8c\x98C" }, // ⌘C
    .{ .kind = .separator },
    .{ .id = "paste", .label = "Paste", .shortcut = "\xe2\x8c\x98V" }, // ⌘V
    .{ .id = "delete", .label = "Delete", .danger = true },
    .{ .id = "disabled_item", .label = "Unavailable", .disabled = true },
};

/// Test helper: on_select id valid only in callback, copy to keep for assertion
const Picked = struct {
    buf: [32]u8 = undefined,
    len: usize = 0,
    fn set(self: *Picked, id: []const u8) void {
        @memcpy(self.buf[0..id.len], id);
        self.len = id.len;
    }
    fn get(self: *const Picked) []const u8 {
        return self.buf[0..self.len];
    }
};

const TestEnv = struct {
    ctx: *Cx,
    root: *Node,
    scope: *Scope,

    fn init() !TestEnv {
        const ctx = try Cx.init(std.testing.allocator, std.testing.io);
        errdefer ctx.deinit();
        const root = try box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 1200 } }, .{});
        ctx.root = root;
        const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
        return .{ .ctx = ctx, .root = root, .scope = scope };
    }

    fn deinit(self: TestEnv) void {
        self.scope.dispose();
        self.ctx.deinit();
    }

    fn mount(self: TestEnv, props: anytype) !MenuResult {
        const r = try Menu(props).mount(self.scope, self.ctx);
        try self.root.appendChild(std.testing.allocator, r.wrapper);
        return r;
    }
};

test "MenuItemRecipe: disabled 压过 danger 与虚拟高亮；图标着色跟随文字" {
    const t = &theme.dark;
    const normal = MenuItemRecipe.resolve(.{ .danger = false, .lit = false, .disabled = false }, t);
    try std.testing.expectEqual(t.tokens.color.fg_primary, normal.label.base.text_color.?);
    try std.testing.expectEqual(t.tokens.color.fg_primary, normal.icon.base.icon_color.?);
    const danger = MenuItemRecipe.resolve(.{ .danger = true, .lit = false, .disabled = false }, t);
    try std.testing.expectEqual(t.tokens.color.danger, danger.label.base.text_color.?);
    try std.testing.expectEqual(t.tokens.color.danger, danger.icon.base.icon_color.?);
    const lit = MenuItemRecipe.resolve(.{ .danger = false, .lit = true, .disabled = false }, t);
    try std.testing.expectEqual(t.tokens.color.list_hover_bg, lit.root.base.background.?);
    const dis = MenuItemRecipe.resolve(.{ .danger = true, .lit = true, .disabled = true }, t);
    try std.testing.expectEqual(t.tokens.color.fg_disabled, dis.label.base.text_color.?);
    try std.testing.expect(dis.root.base.background == null or !std.meta.eql(dis.root.base.background.?, t.tokens.color.list_hover_bg));
}

test "Menu: basic structure" {
    const env = try TestEnv.init();
    defer env.deinit();
    const result = try env.mount(.{ .items = &test_items });
    try std.testing.expectEqual(@as(usize, 6), stateOf(result).item_count);
    // Icon item: icon + text two children in left group
    const left = stateOf(result).item_nodes[0].?.children.items[0];
    try std.testing.expectEqual(@as(usize, 2), left.children.items.len);
}

test "Menu: the result's panel is the popover content that holds the rows" {
    const env = try TestEnv.init();
    defer env.deinit();
    const result = try env.mount(.{ .items = &test_items });
    try std.testing.expect(result.panel == stateOf(result).menu_node.?);
    try std.testing.expect(stateOf(result).item_nodes[0].?.isDescendantOf(result.panel));
}

test "Menu: fill_trigger gives the trigger the row's width" {
    const env = try TestEnv.init();
    defer env.deinit();
    const filled = try env.mount(.{ .items = &test_items, .fill_trigger = true });
    const filled_row = try box(env.ctx, .{ .width = .fill(), .height = .{ .px = 20 } }, .{});
    try filled.trigger.appendChild(std.testing.allocator, filled_row);
    const plain = try env.mount(.{ .items = &test_items });
    const plain_row = try box(env.ctx, .{ .width = .{ .px = 120 }, .height = .{ .px = 20 } }, .{});
    try plain.trigger.appendChild(std.testing.allocator, plain_row);
    env.ctx.layout();
    try std.testing.expectApproxEqAbs(@as(f32, 400), filled.wrapper.rectFromWorldOrFallback().w, 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 400), filled.trigger.rectFromWorldOrFallback().w, 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 400), filled_row.rectFromWorldOrFallback().w, 0.5);
    // Default: the trigger keeps its content's width.
    try std.testing.expectApproxEqAbs(@as(f32, 120), plain.trigger.rectFromWorldOrFallback().w, 0.5);
}

test "Menu: static items are copied with their strings — the caller's array may go away" {
    const env = try TestEnv.init();
    defer env.deinit();

    var picked = Picked{};
    var local_items = [_]MenuItem{
        .{ .id = "local", .label = "Local item", .shortcut = "Cmd-L" },
    };
    const result = try env.mount(.{ .items = &local_items, .on_select = env.ctx.on(Picked, &picked, Picked.set) });

    const items = stateOf(result).items;
    try std.testing.expect(items.ptr != local_items[0..].ptr);
    try std.testing.expect(items[0].id.ptr != local_items[0].id.ptr);
    try std.testing.expect(items[0].label.ptr != local_items[0].label.ptr);
    try std.testing.expect(items[0].shortcut.?.ptr != local_items[0].shortcut.?.ptr);
    local_items[0] = .{ .id = "changed", .label = "Changed" };
    stateOf(result).selectHighlighted();
    try std.testing.expectEqualStrings("local", picked.get());
    try std.testing.expectEqualStrings("Local item", items[0].label);
    try std.testing.expectEqualStrings("Cmd-L", items[0].shortcut.?);
}

test "Menu: state and keyboard navigation are capped to rendered items" {
    const env = try TestEnv.init();
    defer env.deinit();

    var many_items: [MenuState.MAX_ITEMS + 1]MenuItem = undefined;
    for (&many_items) |*item| item.* = .{ .id = "item", .label = "Item" };
    const result = try env.mount(.{ .items = &many_items });
    try std.testing.expectEqual(MenuState.MAX_ITEMS, stateOf(result).items.len);
    try std.testing.expectEqual(MenuState.MAX_ITEMS, stateOf(result).item_count);

    stateOf(result).highlighted_index = MenuState.MAX_ITEMS - 1;
    _ = menuKeyHandler(.down, .{}, @ptrCast(stateOf(result)));
    try std.testing.expectEqual(@as(usize, 0), stateOf(result).highlighted_index);
    _ = menuKeyHandler(.up, .{}, @ptrCast(stateOf(result)));
    try std.testing.expectEqual(MenuState.MAX_ITEMS - 1, stateOf(result).highlighted_index);
}

test "Menu: keyboard navigation skips separator and disabled" {
    const env = try TestEnv.init();
    defer env.deinit();
    const result = try env.mount(.{ .items = &test_items });
    const st = stateOf(result);

    _ = menuKeyHandler(.down, .{}, @ptrCast(st));
    try std.testing.expectEqual(@as(usize, 1), st.highlighted_index);
    // Foundations keyboard focus: 2px ring + 2px offset on the virtual row.
    const outline = st.item_nodes[1].?.style.outline().?;
    try std.testing.expectEqual(@as(f32, 2), outline.width);
    try std.testing.expectEqual(@as(f32, 2), outline.offset);
    try std.testing.expectEqual(env.ctx.tokens.tokens.color.focus_ring, outline.color);
    st.enterIndex(3);
    try std.testing.expectEqual(outline, st.item_nodes[1].?.style.outline().?);
    // Skip separator (index 2)
    _ = menuKeyHandler(.down, .{}, @ptrCast(st));
    try std.testing.expectEqual(@as(usize, 3), st.highlighted_index);
    _ = menuKeyHandler(.down, .{}, @ptrCast(st));
    try std.testing.expectEqual(@as(usize, 4), st.highlighted_index);
    // Skip disabled (index 5), wrap to index 0
    _ = menuKeyHandler(.down, .{}, @ptrCast(st));
    try std.testing.expectEqual(@as(usize, 0), st.highlighted_index);
}

test "Menu: select closes the menu, then reports the id, then runs the item command" {
    const env = try TestEnv.init();
    defer env.deinit();

    const Probe = struct {
        open: ?*Signal(bool) = null,
        log: [4]u8 = undefined,
        len: usize = 0,
        fn select(self: *@This(), id: []const u8) void {
            // Close request comes first: toggle now settled to false
            if (self.open.?.peek()) self.log[self.len] = 'X' else self.log[self.len] = id[0];
            self.len += 1;
        }
        fn run(self: *@This()) void {
            self.log[self.len] = '!';
            self.len += 1;
        }
    };
    var probe = Probe{};
    const items = [_]MenuItem{.{ .id = "go", .label = "Go", .on_click = env.ctx.on(Probe, &probe, Probe.run) }};
    const result = try env.mount(.{ .items = &items, .on_select = env.ctx.on(Probe, &probe, Probe.select) });
    probe.open = result.open;
    result.open.?.set(true);
    stateOf(result).selectHighlighted();
    try std.testing.expect(!result.open.?.peek());
    try std.testing.expectEqualStrings("g!", probe.log[0..probe.len]);
}

test "Menu: escape closes menu" {
    const env = try TestEnv.init();
    defer env.deinit();
    const result = try env.mount(.{ .items = &test_items });
    result.open.?.set(true);
    _ = menuKeyHandler(.escape, .{}, @ptrCast(stateOf(result)));
    try std.testing.expect(!result.open.?.peek());
}

test "Menu: a split parent can refuse to close; on_select and the command still run" {
    const env = try TestEnv.init();
    defer env.deinit();

    const Parent = struct {
        open: *Signal(bool),
        pinned: bool = true,
        picked: Picked = .{},
        runs: u32 = 0,
        fn write(self: *@This(), v: bool) void {
            if (!v and self.pinned) return; // Reject close when pinned
            self.open.set(v);
        }
        fn select(self: *@This(), id: []const u8) void {
            self.picked.set(id);
        }
        fn run(self: *@This()) void {
            self.runs += 1;
        }
    };
    var parent = Parent{ .open = try env.scope.createSignal(bool, true) };
    const items = [_]MenuItem{
        .{ .id = "cut", .label = "Cut" },
        .{ .id = "copy", .label = "Copy", .on_click = env.ctx.on(Parent, &parent, Parent.run) },
    };
    const result = try env.mount(.{
        .items = &items,
        .open = reactive.split(parent.open, env.ctx.on(Parent, &parent, Parent.write)),
        .on_select = env.ctx.on(Parent, &parent, Parent.select),
    });
    try std.testing.expect(result.open == null);

    _ = menuKeyHandler(.down, .{}, @ptrCast(stateOf(result))); // -> copy
    _ = menuKeyHandler(.@"return", .{}, @ptrCast(stateOf(result)));
    try std.testing.expectEqualStrings("copy", parent.picked.get());
    try std.testing.expectEqual(@as(u32, 1), parent.runs);
    try std.testing.expect(parent.open.peek()); // Parent rejected close
    _ = menuKeyHandler(.escape, .{}, @ptrCast(stateOf(result)));
    try std.testing.expect(parent.open.peek());

    parent.pinned = false;
    _ = menuKeyHandler(.escape, .{}, @ptrCast(stateOf(result)));
    try std.testing.expect(!parent.open.peek());
}

test "Menu: a parent that unmounts the menu while closing still gets the right id" {
    const env = try TestEnv.init();
    defer env.deinit();

    const Parent = struct {
        env: TestEnv,
        open: *Signal(bool),
        wrapper: ?*Node = null,
        picked: [16]u8 = undefined,
        picked_len: usize = 0,
        runs: u32 = 0,
        fn write(self: *@This(), v: bool) void {
            self.open.set(v);
            // Close syncs unmount: menu's items copy (with id strings) freed
            if (!v) if (self.wrapper) |w| {
                self.env.ctx.detachChild(self.env.root, w);
                self.env.ctx.freeNode(w);
                self.wrapper = null;
            };
        }
        fn select(self: *@This(), id: []const u8) void {
            @memcpy(self.picked[0..id.len], id);
            self.picked_len = id.len;
        }
        fn run(self: *@This()) void {
            self.runs += 1;
        }
    };
    var parent = Parent{ .env = env, .open = try env.scope.createSignal(bool, true) };
    var items = [_]MenuItem{.{ .id = "copy", .label = "Copy", .on_click = env.ctx.on(Parent, &parent, Parent.run) }};
    const result = try env.mount(.{
        .items = &items,
        .open = reactive.split(parent.open, env.ctx.on(Parent, &parent, Parent.write)),
        .on_select = env.ctx.on(Parent, &parent, Parent.select),
    });
    parent.wrapper = result.wrapper;
    stateOf(result).selectHighlighted();
    try std.testing.expect(parent.wrapper == null);
    try std.testing.expectEqualStrings("copy", parent.picked[0..parent.picked_len]);
    try std.testing.expectEqual(@as(u32, 1), parent.runs);
}

test "Menu: items from a signal rebuild when a new array is set" {
    const env = try TestEnv.init();
    defer env.deinit();

    var picked = Picked{};
    const first = [_]MenuItem{
        .{ .id = "a", .label = "A" },
        .{ .kind = .separator },
        .{ .id = "b", .label = "B" },
        .{ .id = "c", .label = "C" },
    };
    const second = [_]MenuItem{.{ .id = "z", .label = "Z" }};
    const items = try env.scope.createSignal([]const MenuItem, &first);
    const result = try env.mount(.{ .items = items, .on_select = env.ctx.on(Picked, &picked, Picked.set) });
    const st = stateOf(result);
    try std.testing.expectEqual(@as(usize, 4), st.item_count);
    // Caller-scope signal lent to Popover scope: latter parented below former, borrow valid
    if (reactive.SignalOwner.debug_checks)
        try std.testing.expectEqual(@as(u32, 0), env.ctx.owner.debug.borrow_warnings);

    // Highlight past end, swap to shorter array: highlight back to start, no overflow, no stale
    // active_descendant on old nodes
    st.highlightIndex(3);
    items.set(&second);
    try std.testing.expectEqual(@as(usize, 1), st.item_count);
    try std.testing.expectEqual(@as(usize, 1), st.items.len);
    try std.testing.expectEqual(@as(usize, 0), st.highlighted_index);
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), st.menu_node.?.behavior.interaction.a11y.?.active_descendant_element_id);
    try std.testing.expect(st.item_nodes[1] == null);
    st.selectHighlighted();
    try std.testing.expectEqualStrings("z", picked.get());
    // Menu panel now holds only the new item
    try std.testing.expectEqual(@as(usize, 1), st.item_nodes[0].?.parent.?.children.items.len);
}

test "Menu: rebuild key ignores array identity but sees borrowed string addresses and handlers" {
    var copy = test_items;
    try std.testing.expectEqual(MenuState.itemsKey(&test_items), MenuState.itemsKey(&copy));
    // Different string address of same content: old nodes' a11y label borrows old address, must
    // rebuild
    var label_buf = "Cut".*;
    copy[0].label = &label_buf;
    try std.testing.expect(MenuState.itemsKey(&test_items) != MenuState.itemsKey(&copy));
    // Context changed (same function, different object) requires rebuild, else click calls old
    // object
    const noop = struct {
        fn f(_: *anyopaque) void {}
    }.f;
    var n1: u32 = 0;
    var n2: u32 = 0;
    copy = test_items;
    copy[1].on_click = core.HandlerRef{ .callback = noop, .context = @ptrCast(&n1) };
    var other = copy;
    other[1].on_click = core.HandlerRef{ .callback = noop, .context = @ptrCast(&n2) };
    try std.testing.expect(MenuState.itemsKey(&other) != MenuState.itemsKey(&copy));
    try std.testing.expect(MenuState.itemsKey(&test_items) != MenuState.itemsKey(&copy));
}

test "Menu: with an external open signal, unmount leaves no live effect behind" {
    const env = try TestEnv.init();
    defer env.deinit();
    const open = try env.scope.createSignal(bool, false);
    const items = try env.scope.createSignal([]const MenuItem, &test_items);
    const before = env.ctx.owner.graph.countByKind().get(.effect);
    const result = try env.mount(.{ .items = items, .open = open });
    env.ctx.detachChild(env.root, result.wrapper);
    env.ctx.freeNode(result.wrapper);
    // Focus effect reads external open, rebuild effect reads external items: both must destroy with
    // Popover scope,
    // else write below touches freed menu content
    try std.testing.expectEqual(before, env.ctx.owner.graph.countByKind().get(.effect));
    open.set(true);
    items.set(test_items[0..1]);
}

test "Menu: 卸载 wrapper 即回收菜单资源（不必等调用方 scope 释放）" {
    const env = try TestEnv.init();
    defer env.deinit();
    const before = env.scope.resources.items.len;
    const result = try env.mount(.{ .items = &test_items });
    env.ctx.detachChild(env.root, result.wrapper);
    env.ctx.freeNode(result.wrapper);
    // Menu leaves no resources on caller scope
    try std.testing.expectEqual(before, env.scope.resources.items.len);
    try std.testing.expectEqual(@as(usize, 0), env.scope.children.items.len);
}

test "nextEnabledIndex 跳过 separator 与 disabled，到边界回绕" {
    const items = [_]MenuItem{ .{}, .{ .kind = .separator }, .{ .disabled = true }, .{} };
    try std.testing.expectEqual(@as(?usize, 3), nextEnabledIndex(&items, 0, true));
    try std.testing.expectEqual(@as(?usize, 0), nextEnabledIndex(&items, 3, true));
    try std.testing.expectEqual(@as(?usize, 0), nextEnabledIndex(&items, 3, false));
    // With one selectable item, wrap to self
    const single = [_]MenuItem{ .{ .kind = .separator }, .{}, .{ .disabled = true } };
    try std.testing.expectEqual(@as(?usize, 1), nextEnabledIndex(&single, 1, true));
    try std.testing.expectEqual(@as(?usize, 1), nextEnabledIndex(&single, 1, false));
}

test "nextEnabledIndex 全不可选或空列表时返回 null" {
    const none = [_]MenuItem{ .{ .kind = .separator }, .{ .disabled = true } };
    try std.testing.expectEqual(@as(?usize, null), nextEnabledIndex(&none, 0, true));
    try std.testing.expectEqual(@as(?usize, null), nextEnabledIndex(&none, 0, false));
    try std.testing.expectEqual(@as(?usize, null), nextEnabledIndex(&.{}, 0, true));
}

// Test collection from styles.yss, this line required, see docs/STYLING.md
test {
    _ = @import("_styles.yss.zig");
}

// OOM sweep at each allocation point, see src/ui/components/oom_sweep.zig
test "Menu: mount 在任意分配点失败时不泄漏（sweep）" {
    const sw = @import("../oom_sweep.zig");
    try sw.sweepMount("menu", struct {
        fn m(scope: *sw.Scope, cx: *sw.Cx) anyerror!?*sw.Node {
            return (try Menu(.{ .items = &test_items }).mount(scope, cx)).wrapper;
        }
    }.m);
    try sw.sweepMount("menu_signal_items", struct {
        fn m(scope: *sw.Scope, cx: *sw.Cx) anyerror!?*sw.Node {
            const items = try scope.createSignal([]const MenuItem, &test_items);
            return (try Menu(.{ .items = items, .max_height = 120 }).mount(scope, cx)).wrapper;
        }
    }.m);
}

test "Menu: nested navigation, ancestor close and focus restoration" {
    const env = try TestEnv.init();
    defer env.deinit();
    const open = try env.scope.createSignal(bool, false);
    const result = try env.mount(.{ .items = &[_]MenuItem{.{ .id = "file", .label = "File", .children = &.{.{ .id = "new", .label = "New" }} }}, .open = open });
    try env.ctx.node_registry.rebuild(env.root);
    result.trigger.setFocusable(true);
    env.ctx.setFocus(result.trigger);
    open.set(true);
    const parent = stateOf(result);
    const child_open = parent.submenus[0].?.open;
    parent.highlightIndex(0);
    try std.testing.expect(!child_open.peek());
    _ = menuKeyHandler(.right, .{}, parent);
    try std.testing.expect(child_open.peek());
    open.set(false);
    try std.testing.expect(!child_open.peek());
    try std.testing.expectEqual(result.trigger, env.ctx.focused_node.?);
}

test "Menu: keyboard opening picks an endpoint and pointer hover leaves typeahead focus intact" {
    const env = try TestEnv.init();
    defer env.deinit();
    var picked = Picked{};
    const result = try env.mount(.{ .items = &test_items, .on_select = env.ctx.on(Picked, &picked, Picked.set) });
    const state = stateOf(result);
    try env.ctx.node_registry.rebuild(env.root);
    result.trigger.setFocusable(true);
    env.ctx.setFocus(result.trigger);

    env.ctx.handleKeyDown(.up, .{});
    try std.testing.expect(result.open.?.peek());
    try std.testing.expectEqual(@as(usize, 4), state.highlighted_index);
    try std.testing.expectEqual(state.menu_node, env.ctx.focus_manager.getFocused());
    env.ctx.layout();
    _ = env.ctx.render();
    env.ctx.handleKeyDown(.home, .{});
    try std.testing.expectEqual(@as(usize, 0), state.highlighted_index);
    env.ctx.handleKeyDown(.c, .{});
    env.ctx.handleKeyDown(.o, .{});
    try std.testing.expectEqual(@as(usize, 1), state.highlighted_index);
    state.enterIndex(4);
    try std.testing.expect(state.item_nodes[1].?.style.outline() != null);
    env.ctx.handleKeyDown(.space, .{});
    try std.testing.expectEqualStrings("copy", picked.get());
    try std.testing.expect(!result.open.?.peek());
    try std.testing.expectEqual(@as(?*Node, result.trigger), env.ctx.focus_manager.getFocused());
}

test "Menu: Tab and Shift+Tab move the highlight and never leave the open menu" {
    const env = try TestEnv.init();
    defer env.deinit();
    const result = try env.mount(.{ .items = &test_items });
    const state = stateOf(result);
    try env.ctx.node_registry.rebuild(env.root);
    result.trigger.setFocusable(true);
    const after = try box(env.ctx, .{ .width = .{ .px = 20 }, .height = .{ .px = 20 } }, .{});
    after.setFocusable(true);
    try env.root.appendChild(std.testing.allocator, after);
    try env.ctx.node_registry.rebuild(env.root);
    env.ctx.setFocus(result.trigger);
    env.ctx.handleKeyDown(.down, .{});
    try std.testing.expect(result.open.?.peek());
    env.ctx.layout();
    _ = env.ctx.render();
    try std.testing.expectEqual(@as(usize, 0), state.highlighted_index);
    env.ctx.handleKeyDown(.tab, .{});
    try std.testing.expectEqual(@as(usize, 1), state.highlighted_index);
    try std.testing.expectEqual(state.menu_node, env.ctx.focus_manager.getFocused());
    env.ctx.handleKeyDown(.tab, .{ .shift = true });
    try std.testing.expectEqual(@as(usize, 0), state.highlighted_index);
    try std.testing.expectEqual(state.menu_node, env.ctx.focus_manager.getFocused());
    try std.testing.expect(result.open.?.peek());
}

test "Menu: a virtual anchor opens the panel at the pointer (context menu)" {
    const env = try TestEnv.init();
    defer env.deinit();
    env.ctx.setViewport(400, 1200);
    const Pointer = struct {
        x: f32 = 120,
        y: f32 = 300,
        fn rect(raw: *anyopaque) popover_mod.AnchorRect {
            const self: *@This() = @ptrCast(@alignCast(raw));
            return .{ .x = self.x, .y = self.y, .w = 0, .h = 0 };
        }
    };
    var pointer: Pointer = .{};
    const open = try env.scope.createSignal(bool, false);
    var picked = Picked{};
    const result = try env.mount(.{
        .items = &test_items,
        .trigger = .manual,
        .open = open,
        .anchor = popover_mod.Anchor{ .virtual = .{ .ctx = @ptrCast(&pointer), .getRect = Pointer.rect } },
        .on_select = env.ctx.on(Picked, &picked, Picked.set),
    });
    // The trigger slot holds nothing: a manual context menu has no visible trigger.
    try std.testing.expectEqual(@as(usize, 0), result.trigger.children.items.len);
    const outside = try box(env.ctx, .{ .width = .{ .px = 40 }, .height = .{ .px = 20 } }, .{});
    outside.setFocusable(true);
    try env.root.appendChild(std.testing.allocator, outside);
    try env.ctx.node_registry.rebuild(env.root);
    env.ctx.setFocus(outside);
    open.set(true);
    for (0..4) |_| {
        env.ctx.frame_time_ms += 400;
        env.ctx.layout();
        _ = env.ctx.render();
    }
    const state = stateOf(result);
    const panel = state.chrome.globalRect();
    // bottom_start of a zero-size rect at the pointer: left edge at the pointer, top edge one
    // menu offset (4) below it — never at the trigger slot (0, 0).
    try std.testing.expectApproxEqAbs(@as(f32, 120), panel.x, 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 304), panel.y, 0.5);
    try std.testing.expectEqual(state.menu_node, env.ctx.focus_manager.getFocused());
    // Moving the anchor between opens follows the new pointer.
    open.set(false);
    pointer = .{ .x = 200, .y = 500 };
    open.set(true);
    for (0..4) |_| {
        env.ctx.frame_time_ms += 400;
        env.ctx.layout();
        _ = env.ctx.render();
    }
    try std.testing.expectApproxEqAbs(@as(f32, 200), state.chrome.globalRect().x, 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 504), state.chrome.globalRect().y, 0.5);
    // Picking closes and returns focus to the node that had it before the menu opened.
    state.highlightIndex(1);
    state.selectHighlighted();
    try std.testing.expectEqualStrings("copy", picked.get());
    try std.testing.expect(!open.peek());
    try std.testing.expectEqual(@as(?*Node, outside), env.ctx.focus_manager.getFocused());
}

test "Menu: item and panel test ids name the rows and the popup panel" {
    const env = try TestEnv.init();
    defer env.deinit();
    const items = [_]MenuItem{
        .{ .id = "paste", .label = "Paste", .test_id = "demo.menu.paste" },
        .{ .kind = .separator },
        .{ .id = "clear", .label = "Clear", .test_id = "demo.menu.clear", .disabled = true },
        .{ .id = "plain", .label = "Plain" },
    };
    const result = try env.mount(.{ .items = &items, .panel_test_id = "demo.menu" });
    const state = stateOf(result);
    try std.testing.expectEqualStrings("demo.menu", state.chrome.meta.ownership.meta.test_id.?);
    try std.testing.expectEqualStrings("demo.menu.paste", state.item_nodes[0].?.meta.ownership.meta.test_id.?);
    try std.testing.expectEqualStrings("demo.menu.clear", state.item_nodes[2].?.meta.ownership.meta.test_id.?);
    try std.testing.expect(state.item_nodes[3].?.meta.ownership.meta.test_id == null);
    // Static items are copied: the row keeps its id after the caller's array goes away.
    try std.testing.expect(state.item_nodes[0].?.meta.ownership.meta.test_id.?.ptr != items[0].test_id.ptr);
    // Signal items rebuild when only the test id changes (borrowed string address).
    const source = try env.scope.createSignal([]const MenuItem, items[0..1]);
    const live = try env.mount(.{ .items = source });
    var renamed = items[0..1].*;
    renamed[0].test_id = "demo.menu.other";
    source.set(&renamed);
    try std.testing.expectEqualStrings("demo.menu.other", stateOf(live).item_nodes[0].?.meta.ownership.meta.test_id.?);
    // Without either id nothing is written (default tree unchanged).
    const bare = try env.mount(.{ .items = &test_items });
    try std.testing.expect(stateOf(bare).chrome.meta.ownership.meta.test_id == null);
}

test "Menu: root exclusivity is per Cx and survives active owner removal" {
    const first = try TestEnv.init();
    defer first.deinit();
    const second = try TestEnv.init();
    defer second.deinit();
    const first_menu = try first.mount(.{ .items = &test_items });
    const replacement = try first.mount(.{ .items = &test_items });
    const second_menu = try second.mount(.{ .items = &test_items });
    first_menu.open.?.set(true);
    second_menu.open.?.set(true);
    try std.testing.expect(first_menu.open.?.peek());
    replacement.open.?.set(true);
    try std.testing.expect(!first_menu.open.?.peek());
    try std.testing.expect(second_menu.open.?.peek());
    first.ctx.detachChild(first.root, replacement.wrapper);
    first.ctx.freeNode(replacement.wrapper);
    first_menu.open.?.set(true);
    try std.testing.expect(first_menu.open.?.peek());
    try std.testing.expect(second_menu.open.?.peek());
}

test "Menu: nested mount failures release rows, portal scopes and copied children" {
    const sw = @import("../oom_sweep.zig");
    try sw.sweepMount("nested_menu", struct {
        fn m(scope: *sw.Scope, cx: *sw.Cx) anyerror!?*sw.Node {
            return (try Menu(.{ .items = &[_]MenuItem{.{ .id = "file", .label = "File", .children = &.{.{ .id = "new", .label = "New", .children = &.{.{ .id = "leaf", .label = "Leaf" }} }} }} }).mount(scope, cx)).wrapper;
        }
    }.m);
}

test "Menu: icon_tint colours a row's icon (swatch rows); disabled rows keep the disabled colour" {
    const env = try TestEnv.init();
    defer env.deinit();
    const red = Color.hex(0xe27878);
    const items = [_]MenuItem{
        .{ .id = "red", .label = "Red", .icon_asset = svg_assets.common.star, .icon_tint = red },
        .{ .id = "plain", .label = "Plain", .icon_asset = svg_assets.common.star },
        .{ .id = "off", .label = "Off", .icon_asset = svg_assets.common.star, .icon_tint = red, .disabled = true },
    };
    const result = try env.mount(.{ .items = &items });
    const state = stateOf(result);
    const iconOf = struct {
        fn get(row: *Node) *Node {
            return row.children.items[0].children.items[0];
        }
    }.get;
    try std.testing.expect(Color.eql(iconOf(state.item_nodes[0].?).getIcon().?.tint, red));
    try std.testing.expect(!Color.eql(iconOf(state.item_nodes[1].?).getIcon().?.tint, red));
    try std.testing.expect(!Color.eql(iconOf(state.item_nodes[2].?).getIcon().?.tint, red));
    // A signal rebuild sees a tint change alone.
    const source = try env.scope.createSignal([]const MenuItem, items[0..1]);
    const live = try env.mount(.{ .items = source });
    var blue = items[0..1].*;
    blue[0].icon_tint = Color.hex(0x87bde8);
    source.set(&blue);
    try std.testing.expect(Color.eql(iconOf(stateOf(live).item_nodes[0].?).getIcon().?.tint, Color.hex(0x87bde8)));
}

test "Menu: header rows caption a group; navigation, typeahead and picking pass over them" {
    const env = try TestEnv.init();
    defer env.deinit();
    const items = [_]MenuItem{
        .{ .kind = .header, .label = "Host · web-1", .test_id = "demo.menu.header" },
        .{ .id = "open", .label = "Open" },
        .{ .kind = .separator },
        .{ .kind = .header, .label = "Danger" },
        .{ .id = "delete", .label = "Delete", .danger = true },
    };
    var picked: Picked = .{};
    const result = try env.mount(.{ .items = &items, .on_select = Handler([]const u8).from(Picked, &picked, Picked.set) });
    const st = stateOf(result);
    // Rows name their kind; a header is a heading with its caption, not a menu item.
    try std.testing.expectEqualStrings("MenuHeader", st.item_nodes[0].?.meta.ownership.meta.component_name.?);
    try std.testing.expectEqualStrings("MenuItem", st.item_nodes[1].?.meta.ownership.meta.component_name.?);
    try std.testing.expectEqualStrings("MenuSeparator", st.item_nodes[2].?.meta.ownership.meta.component_name.?);
    try std.testing.expectEqualStrings("demo.menu.header", st.item_nodes[0].?.meta.ownership.meta.test_id.?);
    const header_a11y = st.item_nodes[0].?.behavior.interaction.a11y.?;
    try std.testing.expectEqual(core.A11yRole.heading, header_a11y.role);
    try std.testing.expectEqualStrings("Host · web-1", header_a11y.label.?);
    try std.testing.expect(st.item_nodes[0].?.behavior.events.on_event == null);
    // Keyboard: Down from the top skips both headers and the separator.
    _ = menuKeyHandler(.down, .{}, @ptrCast(st));
    try std.testing.expectEqual(@as(usize, 1), st.highlighted_index);
    _ = menuKeyHandler(.down, .{}, @ptrCast(st));
    try std.testing.expectEqual(@as(usize, 4), st.highlighted_index);
    _ = menuKeyHandler(.down, .{}, @ptrCast(st));
    try std.testing.expectEqual(@as(usize, 1), st.highlighted_index);
    // A header can be neither highlighted nor picked.
    st.highlightIndex(3);
    try std.testing.expectEqual(@as(usize, 1), st.highlighted_index);
    st.pick(0, false);
    try std.testing.expectEqualStrings("", picked.get());
    // Typeahead matches items only ("D" → Delete, not the "Danger" header).
    _ = menuKeyHandler(.d, .{}, @ptrCast(st));
    try std.testing.expectEqual(@as(usize, 4), st.highlighted_index);
    // A menu without headers renders no MenuHeader (default tree unchanged).
    const plain = try env.mount(.{ .items = &test_items });
    for (stateOf(plain).item_nodes[0..stateOf(plain).item_count]) |node| try std.testing.expect(!std.mem.eql(u8, node.?.meta.ownership.meta.component_name.?, "MenuHeader"));
}

test "Menu: disabled_reason is shown after a disabled row's label and describes it; ignored when enabled" {
    const env = try TestEnv.init();
    defer env.deinit();
    var reason_buffer = "No selection".*;
    const items = [_]MenuItem{
        .{ .id = "copy", .label = "Copy", .shortcut = "\xe2\x8c\x98C", .disabled = true, .disabled_reason = &reason_buffer },
        .{ .id = "paste", .label = "Paste", .disabled_reason = "Not shown" },
    };
    const result = try env.mount(.{ .items = &items });
    const st = stateOf(result);
    const texts = struct {
        fn collect(node: *Node, out: *std.ArrayList([]const u8)) void {
            if (node.getText()) |t| out.append(std.testing.allocator, t.content) catch {};
            for (node.children.items) |child| collect(child, out);
        }
    }.collect;
    var copy_texts: std.ArrayList([]const u8) = .empty;
    defer copy_texts.deinit(std.testing.allocator);
    texts(st.item_nodes[0].?, &copy_texts);
    try std.testing.expectEqual(@as(usize, 3), copy_texts.items.len);
    try std.testing.expectEqualStrings("Copy", copy_texts.items[0]);
    try std.testing.expectEqualStrings("No selection", copy_texts.items[1]);
    try std.testing.expectEqualStrings("\xe2\x8c\x98C", copy_texts.items[2]);
    try std.testing.expectEqualStrings("No selection", st.item_nodes[0].?.behavior.interaction.a11y.?.description.?);
    // Static items are copied: the reason survives the caller's buffer.
    reason_buffer[0] = 'X';
    try std.testing.expectEqualStrings("No selection", st.items[0].disabled_reason.?);
    var paste_texts: std.ArrayList([]const u8) = .empty;
    defer paste_texts.deinit(std.testing.allocator);
    texts(st.item_nodes[1].?, &paste_texts);
    try std.testing.expectEqual(@as(usize, 1), paste_texts.items.len);
    // A signal rebuild sees a reason change alone.
    const source = try env.scope.createSignal([]const MenuItem, items[0..1]);
    const live = try env.mount(.{ .items = source });
    var other = items[0..1].*;
    other[0].disabled_reason = "Read only";
    source.set(&other);
    try std.testing.expectEqualStrings("Read only", stateOf(live).item_nodes[0].?.behavior.interaction.a11y.?.description.?);
}

test "Menu: a submenu's panel takes its test id and max height from the parent row" {
    const env = try TestEnv.init();
    defer env.deinit();
    var hosts: [12]MenuItem = undefined;
    for (&hosts) |*item| item.* = .{ .id = "host", .label = "Host" };
    const items = [_]MenuItem{
        .{ .id = "more", .label = "More", .children = &hosts, .submenu_test_id = "demo.menu.more", .submenu_max_height = 120 },
        .{ .id = "plain", .label = "Plain", .children = &.{.{ .id = "leaf", .label = "Leaf" }} },
    };
    const result = try env.mount(.{ .items = &items });
    const st = stateOf(result);
    const more = st.submenus[0].?.menu;
    try std.testing.expectEqualStrings("demo.menu.more", more.chrome.meta.ownership.meta.test_id.?);
    try std.testing.expectEqual(@as(usize, 12), more.item_count);
    // Without either field the nested panel is unnamed and fits its rows (default unchanged).
    try std.testing.expect(st.submenus[1].?.menu.chrome.meta.ownership.meta.test_id == null);
    // The copied tree owns the panel test id.
    try std.testing.expect(st.items[0].submenu_test_id.ptr != items[0].submenu_test_id.ptr);
}

test "Menu: color_scheme fixes the panel and its submenus to one scheme; default follows the app" {
    const env = try TestEnv.init();
    defer env.deinit();
    const items = [_]MenuItem{.{ .id = "more", .label = "More", .children = &.{.{ .id = "leaf", .label = "Leaf" }} }};
    const fixed = try env.mount(.{ .items = &items, .color_scheme = .dark });
    const st = stateOf(fixed);
    try std.testing.expectEqual(@as(?core.theme.ColorScheme, .dark), st.color_scheme);
    try std.testing.expectEqual(core.theme.ColorScheme.dark, env.ctx.colorSchemeOf(st.menu_node.?));
    try std.testing.expectEqual(core.theme.ColorScheme.dark, env.ctx.colorSchemeOf(st.submenus[0].?.menu.menu_node.?));
    const plain = try env.mount(.{ .items = &items });
    try std.testing.expect(stateOf(plain).color_scheme == null);
}

test "Menu: a submenu still opens after the rows were rebuilt while the menu was closed" {
    const env = try TestEnv.init();
    defer env.deinit();
    env.ctx.setViewport(800, 600);
    // A window portal as in an app: closed panels are detached from the window tree.
    _ = try env.ctx.ensurePopoverPortalRoot();
    const frames = struct {
        fn run(cx: *Cx) void {
            for (0..30) |_| {
                cx.advanceFrameClock();
                cx.layout();
                _ = cx.render();
            }
        }
    }.run;
    try env.ctx.setTestFrameStep(50);
    var first_label = "More".*;
    var second_label = "More".*;
    const first = [_]MenuItem{.{ .id = "more", .label = &first_label, .children = &.{.{ .id = "a", .label = "A" }} }};
    const second = [_]MenuItem{.{ .id = "more", .label = &second_label, .children = &.{.{ .id = "b", .label = "B" }} }};
    const source = try env.scope.createSignal([]const MenuItem, &first);
    const open = try env.scope.createSignal(bool, false);
    const result = try env.mount(.{ .items = source, .open = open });
    try env.ctx.node_registry.rebuild(env.root);
    const shown = struct {
        fn check(cx: *Cx, menu: *MenuState) bool {
            const sub = menu.submenus[0] orelse return false;
            const layer = cx.overlay_stack.findLayerForNode(sub.menu.chrome) orelse return false;
            return !layer.suspended and sub.open.peek();
        }
    }.check;
    for (0..2) |round| {
        if (round == 1) source.set(&second);
        open.set(true);
        frames(env.ctx);
        const parent = stateOf(result);
        parent.highlightIndex(0);
        _ = menuKeyHandler(.right, .{}, parent);
        frames(env.ctx);
        try std.testing.expect(shown(env.ctx, parent));
        open.set(false);
        frames(env.ctx);
    }
}

test "Menu: description line under the label and a right-hand Tag; default rows unchanged" {
    const env = try TestEnv.init();
    defer env.deinit();
    var about_buffer = "Reads run automatically, the rest by policy".*;
    const items = [_]MenuItem{
        .{ .kind = .header, .label = "Permissions" },
        .{ .id = "confirm", .label = "Confirm first", .description = &about_buffer, .selected = true },
        .{ .id = "pty", .label = "Attach existing PTY", .tag = "Interactive" },
        .{ .id = "plain", .label = "Plain" },
        .{ .id = "off", .label = "Revoke", .disabled = true, .disabled_reason = "Nothing granted", .description = "Grant first" },
    };
    env.ctx.setViewport(400, 1200);
    const result = try env.mount(.{ .items = &items, .width = 280, .open = true });
    const st = stateOf(result);
    env.ctx.layout();
    _ = env.ctx.render();
    env.ctx.layout();
    const k = env.ctx.tokens.tokens;
    const described = st.item_nodes[1].?;
    const about = findTextContent(described, "Reads run automatically, the rest by policy").?.getText().?;
    try std.testing.expect(Color.eql(about.color, k.color.fg_secondary));
    try std.testing.expectEqual(k.font_size.xs, about.font_size);
    try std.testing.expectEqual(core.AlignItems.start, described.style.align_items);
    try std.testing.expect(described.rectFromWorldOrFallback().h > 40);
    try std.testing.expectEqualStrings("Reads run automatically, the rest by policy", described.behavior.interaction.a11y.?.description.?);
    about_buffer[0] = 'X';
    try std.testing.expectEqualStrings("Reads run automatically, the rest by policy", st.items[1].description.?);
    // Tag: a native Tag on the right; the row keeps the 28 height.
    const tagged = st.item_nodes[2].?;
    const tag = findComponentNamed(tagged, "Tag").?;
    try std.testing.expect(findTextContent(tag, "Interactive") != null);
    try std.testing.expect(tag.globalRect().x > tagged.globalRect().x + tagged.globalRect().w / 2);
    try std.testing.expectApproxEqAbs(@as(f32, 28), tagged.rectFromWorldOrFallback().h, 0.5);
    // A plain row is the same as before: 28 high, centered, label only.
    const plain = st.item_nodes[3].?;
    try std.testing.expectApproxEqAbs(@as(f32, 28), plain.rectFromWorldOrFallback().h, 0.5);
    try std.testing.expectEqual(core.AlignItems.center, plain.style.align_items);
    try std.testing.expect(findComponentNamed(plain, "Tag") == null);
    // Disabled: the reason stays the a11y description; the description line is dimmed.
    const off = st.item_nodes[4].?;
    try std.testing.expectEqualStrings("Nothing granted", off.behavior.interaction.a11y.?.description.?);
    try std.testing.expect(Color.eql(findTextContent(off, "Grant first").?.getText().?.color, k.color.fg_disabled));
    // Keyboard navigation passes the header and lands on the described row.
    try std.testing.expectEqualStrings("Permissions", st.item_nodes[0].?.behavior.interaction.a11y.?.label.?);
    // A signal rebuild sees a description / tag change alone.
    const source = try env.scope.createSignal([]const MenuItem, items[2..3]);
    const live = try env.mount(.{ .items = source });
    var other = items[2..3].*;
    other[0].tag = "Batch";
    source.set(&other);
    try std.testing.expect(findTextContent(stateOf(live).item_nodes[0].?, "Batch") != null);
}

fn findTextContent(n: *Node, text: []const u8) ?*Node {
    if (n.getText()) |t| if (std.mem.eql(u8, t.content, text)) return n;
    for (n.children.items) |c| if (findTextContent(c, text)) |r| return r;
    return null;
}

fn findComponentNamed(n: *Node, name: []const u8) ?*Node {
    if (n.meta.ownership.meta.component_name) |c| if (std.mem.eql(u8, c, name)) return n;
    for (n.children.items) |c| if (findComponentNamed(c, name)) |r| return r;
    return null;
}

test "menu(description + tag): mount 在任意分配点失败时不泄漏（sweep）" {
    const sw = @import("../oom_sweep.zig");
    try sw.sweepMount("menu(description+tag)", struct {
        fn m(scope: *sw.Scope, cx: *sw.Cx) anyerror!?*sw.Node {
            const items = [_]MenuItem{
                .{ .kind = .header, .label = "Mode" },
                .{ .id = "a", .label = "Ask", .description = "Every step asks first", .selected = true },
                .{ .id = "b", .label = "Attach PTY", .tag = "Interactive", .tag_color = .accent },
            };
            return (try Menu(.{ .items = &items, .open = true }).mount(scope, cx)).wrapper;
        }
    }.m);
}

test "Menu: a nested row spans the panel like its siblings and its submenu opens beside the panel" {
    const env = try TestEnv.init();
    defer env.deinit();
    env.ctx.setViewport(800, 600);
    const items = [_]MenuItem{
        .{ .id = "long", .label = "A much longer sibling row", .shortcut = "\xe2\x8c\x98L" },
        .{ .id = "more", .label = "More", .children = &.{ .{ .id = "a", .label = "Alpha" }, .{ .id = "b", .label = "Beta" } } },
    };
    const open = try env.scope.createSignal(bool, false);
    const result = try env.mount(.{ .items = &items, .open = open });
    try env.ctx.node_registry.rebuild(env.root);
    open.set(true);
    const frames = struct {
        fn run(cx: *Cx) void {
            for (0..4) |_| {
                cx.frame_time_ms += 400;
                cx.layout();
                _ = cx.render();
            }
        }
    }.run;
    frames(env.ctx);
    const st = stateOf(result);
    const sibling = st.item_nodes[0].?.globalRect();
    const more = st.item_nodes[1].?.globalRect();
    // Both rows span the list: same left edge, same width (the nested row is not content-sized).
    try std.testing.expectApproxEqAbs(sibling.x, more.x, 0.5);
    try std.testing.expectApproxEqAbs(sibling.w, more.w, 0.5);
    st.highlightIndex(1);
    _ = menuKeyHandler(.right, .{}, st);
    frames(env.ctx);
    const sub = st.submenus[1].?.menu.chrome.globalRect();
    const panel = st.chrome.globalRect();
    // right_start of the full-width row: the submenu starts at the row's right edge (the 4px list
    // inset overlap), never over the parent's rows.
    try std.testing.expectApproxEqAbs(more.x + more.w, sub.x, 0.5);
    try std.testing.expect(sub.x >= panel.x + panel.w - 4.5);
    try std.testing.expectApproxEqAbs(more.y, sub.y, 4.5);
}

test "Menu: a long description wraps inside a fixed-width panel; the right-hand value and arrow stay in the row" {
    const env = try TestEnv.init();
    defer env.deinit();
    env.ctx.setViewport(800, 600);
    const items = [_]MenuItem{
        .{ .id = "plain", .label = "Plain" },
        .{
            .id = "retention",
            .label = "Task sessions",
            .icon_asset = svg_assets.common.star,
            .shortcut = "Ask every time",
            .description = "Whether a finished task keeps its session open for follow-up questions, closes it, or asks every time a task ends",
            .children = &.{ .{ .id = "keep", .label = "Keep" }, .{ .id = "close", .label = "Close" } },
        },
        .{
            .id = "flat",
            .label = "Flat described row",
            .shortcut = "\xe2\x8c\x98F",
            .tag = "Interactive",
            .description = "A row without a submenu wraps its description the same way when the text is longer than the panel",
        },
    };
    const result = try env.mount(.{ .items = &items, .width = 300, .open = true });
    for (0..4) |_| {
        env.ctx.frame_time_ms += 400;
        env.ctx.layout();
        _ = env.ctx.render();
    }
    const st = stateOf(result);
    const plain = st.item_nodes[0].?.globalRect();
    for ([_]usize{ 1, 2 }) |index| {
        const row_node = st.item_nodes[index].?;
        try expectRowInside(row_node, plain, st.chrome.globalRect(), items[index].description.?, env.ctx.tokens.tokens.font_size.xs);
    }
}

fn expectRowInside(row_node: *Node, plain: core.ComputedRect, panel: core.ComputedRect, description: []const u8, xs: f32) !void {
    const row = row_node.globalRect();
    // The described row is as wide as a plain row: its content never pushes it past the list.
    try std.testing.expectApproxEqAbs(plain.x, row.x, 0.5);
    try std.testing.expectApproxEqAbs(plain.w, row.w, 0.5);
    try std.testing.expect(row.x + row.w <= panel.x + panel.w + 0.5);
    // Every part of the row (label, description, value, arrow) lies inside it.
    const left = row_node.children.items[0].globalRect();
    const right = row_node.children.items[1].globalRect();
    try std.testing.expect(left.x >= row.x - 0.5 and left.x + left.w <= right.x + 0.5);
    try std.testing.expect(right.x + right.w <= row.x + row.w + 0.5);
    const about = findTextContent(row_node, description).?.globalRect();
    try std.testing.expect(about.x + about.w <= right.x + 0.5);
    // The description wraps onto more lines instead of running past the panel.
    try std.testing.expect(about.h > 2 * xs * 1.5 - 0.5);
}

test "Menu: without room on the right a nested submenu opens on the left of its row, beside the panel" {
    const env = try TestEnv.init();
    defer env.deinit();
    env.ctx.setViewport(400, 600);
    // The menu sits against the right edge of the window.
    env.root.style.width = .{ .px = 400 };
    env.root.style.direction = .row;
    env.root.style.justify = .end;
    const items = [_]MenuItem{
        .{ .id = "long", .label = "A much longer sibling row", .shortcut = "\xe2\x8c\x98L" },
        .{ .id = "more", .label = "More", .children = &.{ .{ .id = "a", .label = "Alpha item" }, .{ .id = "b", .label = "Beta item" } } },
    };
    const open = try env.scope.createSignal(bool, false);
    const result = try env.mount(.{ .items = &items, .open = open, .position = .bottom_end });
    try result.trigger.appendChild(std.testing.allocator, try box(env.ctx, .{ .width = .{ .px = 40 }, .height = .{ .px = 24 } }, .{}));
    try env.ctx.node_registry.rebuild(env.root);
    open.set(true);
    const frames = struct {
        fn run(cx: *Cx) void {
            for (0..4) |_| {
                cx.frame_time_ms += 400;
                cx.layout();
                _ = cx.render();
            }
        }
    }.run;
    frames(env.ctx);
    const st = stateOf(result);
    st.highlightIndex(1);
    _ = menuKeyHandler(.right, .{}, st);
    frames(env.ctx);
    const more = st.item_nodes[1].?.globalRect();
    const panel = st.chrome.globalRect();
    const sub = st.submenus[1].?.menu.chrome.globalRect();
    try std.testing.expect(panel.x + panel.w <= 400.5);
    // Flipped to left_start: the submenu ends at the row's left edge and stays in the window.
    try std.testing.expect(sub.x >= -0.5);
    try std.testing.expectApproxEqAbs(more.x, sub.x + sub.w, 0.5);
    try std.testing.expect(sub.x + sub.w <= panel.x + 4.5);
}
