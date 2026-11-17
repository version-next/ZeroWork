//! 页签条（design-r3 稿 3）的挂载与信号。视图是 `tab_strip.yix`（每个页签：原生 Tooltip、xs 图标关闭按钮；
//! 条尾：原生“⌄ n”溢出 Menu 与“+”新建按钮），样式在 `tab_strip.yss`，行数据在 `model/tab_strip.zig`。
//!
//! 页签条只挂一次：workspace 每次同步写入行（`setRows`），按页签 id 调和，同一个页签的行原地更新，
//! 悬停、焦点、拖动中的状态都保住。悬停 / 按下 / 焦点 / ⌘ 序号 / 拖起 / 合组目标是这里的信号，页签面的外观由
//! `tab_strip.yss` 的样式函数按它们算出；workspace 不再改任何节点的样式。
//!
//! 唯一的手写部分是 `TabCell`：每个页签单元的外层盒子，承载 zenit 的拖动绑定（绑定占用节点的事件槽，
//! 需要行自己的 scope，随行卸载释放）。
const std = @import("std");
const ui = @import("ui");
const W = ui.widgets;
const m = @import("../model/tab_strip.zig");
const template = @import("_tab_strip.yix.zig");

pub const ids = template.ids;
pub const Row = m.Row;
/// 一个页签每帧可能变的视觉（类型图标、着色、连接状态点、未读轻跳）：与行分开，变化时不必重算名称与提示。
pub const Visual = struct {
    id: u64,
    icon: ui.SvgAsset,
    tint: ui.Color = ui.Color.TRANSPARENT,
    dot: ui.Color = ui.Color.TRANSPARENT,
    /// 未读后台页签的类型图标轻跳（向上为负）。
    bounce: f32 = 0,

    pub fn eql(a: Visual, b: Visual) bool {
        return a.id == b.id and a.icon.icon_id == b.icon.icon_id and ui.Color.eql(a.tint, b.tint) and ui.Color.eql(a.dot, b.dot) and a.bounce == b.bounce;
    }
};

pub const Look = m.Look;

/// workspace 的接线：选中、关闭、单元上的其余指针 / 键盘事件（右键菜单、中键关闭、双击重命名、Enter 激活）、
/// 拖动、溢出菜单里选中一个页签、Tooltip 是否允许出现。
pub const Hooks = struct {
    context: *anyopaque,
    select: *const fn (*anyopaque, u64) void,
    close: *const fn (*anyopaque, u64) void,
    event: *const fn (*anyopaque, *Cell, ui.events.Event) ui.events.EventResult,
    drag: *const fn (*anyopaque, *Cell, ui.interaction.drag.Event) void,
    overflow: *const fn (*anyopaque, u64) void,
    tip_allowed: *const fn (*anyopaque, u64) bool,
    /// A row's nodes were mounted (`keepNodes`) or its row unmounted (`Cell.unmounted`). Rows mount and
    /// unmount when the template's list reconciles `rows_signal`, which is not necessarily inside
    /// `setRows`: a write made in a reactive batch (an after-layout hook) is reconciled when the batch
    /// ends. Whoever binds tab ids to row nodes re-binds here, not right after `setRows`.
    mounted: *const fn (*anyopaque, u64) void,
    unmounted: *const fn (*anyopaque, u64) void,
};

/// 行里的字符串（名称、提示、test_id、锚点名 …）由单元持有：内容不变时一直是同一个指针（同 key 内容不变的行
/// 不会重写数据源，模板仍持有旧值），内容变化时换新指针，上一份保留到下一次变化。
pub const Text = enum { name, count, tip, ordinal, test_id, cell_test_id, close_test_id, anchor };

/// 一个页签单元的上下文（事件、拖动、节点）。按页签 id 保留到这个页签离开页签条且行已卸载。
pub const Cell = struct {
    vm: *ViewModel,
    id: u64,
    holder: ?*ui.Node = null,
    surface: ?*ui.Node = null,
    title: ?*ui.Node = null,
    close: ?*ui.Node = null,
    /// The type icon's slot; the icon node itself is rebuilt when the glyph changes (`iconNode`).
    icon_slot: ?*ui.Node = null,
    ordinal: ?*ui.Node = null,
    drag: ?*ui.interaction.drag.Binding = null,
    hovered: bool = false,
    pressed: bool = false,
    /// 按下过或菜单打开时指针在它上面：直到指针离开前不再弹 Tooltip。
    tip_suppressed: bool = false,
    /// 本次同步里这个页签还在页签条上。
    present: bool = true,
    texts: [@typeInfo(Text).@"enum".field_names.len][2]?[]u8 = @splat(.{ null, null }),

    /// The cell's stable copy of `value` for `field` (see `Text`).
    pub fn text(self: *Cell, field: Text, value: []const u8) ![]const u8 {
        const slot = &self.texts[@intFromEnum(field)];
        if (slot[0]) |current| if (std.mem.eql(u8, current, value)) return current;
        const allocator = self.vm.cx.allocator;
        const copy = try allocator.dupe(u8, value);
        if (slot[1]) |older| allocator.free(older);
        slot[1] = slot[0];
        slot[0] = copy;
        return copy;
    }
    fn freeTexts(self: *Cell) void {
        for (&self.texts) |*slot| for (slot) |maybe| if (maybe) |value| self.vm.cx.allocator.free(value);
    }

    fn unmounted(self: *Cell) void {
        self.holder = null;
        self.surface = null;
        self.title = null;
        self.close = null;
        self.icon_slot = null;
        self.ordinal = null;
        self.drag = null;
        self.hovered = false;
        self.pressed = false;
        self.vm.hooks.unmounted(self.vm.hooks.context, self.id);
    }
};

pub const ViewModel = struct {
    cx: *ui.Cx,
    scope: *ui.Scope,
    hooks: Hooks,
    root: *ui.Node = undefined,
    rows_signal: *ui.Signal([]const Row),
    active_surface: *ui.Signal(W.joined_surface.Target),
    visuals_signal: *ui.Signal([]const Visual),
    visual_buffers: [2]std.ArrayList(Visual) = .{ .empty, .empty },
    visual_current: u1 = 0,
    /// The workspace's scratch list for building the next visuals (reused every frame).
    scratch: std.ArrayList(Visual) = .empty,
    hovered: *ui.Signal(?u64),
    pressed: *ui.Signal(?u64),
    focused: *ui.Signal(?u64),
    ordinals: *ui.Signal(bool),
    lifted: *ui.Signal(?u64),
    drop: *ui.Signal(?u64),
    gap: *ui.Signal(?f32),
    tips_epoch: *ui.Signal(u64),
    overflow_items: *ui.Signal([]const W.MenuItem),
    overflow_label: *ui.Signal([]const u8),
    new_tab: ?*ui.Node = null,
    /// The row of tab cells (drag geometry).
    viewport: ?*ui.Node = null,
    cells: std.AutoArrayHashMapUnmanaged(u64, *Cell) = .empty,
    /// Row strings / menu items: the signal keeps the previous array alive until it is replaced.
    arenas: [2]std.heap.ArenaAllocator,
    current: u1 = 0,

    // ---- 模板读的选择器 ----

    pub fn rows(self: *const ViewModel) []const Row {
        return self.rows_signal.get();
    }
    /// 这个页签的视觉；还没同步到时给一个空图标。
    pub fn visual(self: *const ViewModel, id: u64) Visual {
        for (self.visuals_signal.get()) |value| if (value.id == id) return value;
        return .{ .id = id, .icon = ui.icons.terminal };
    }
    /// `visual` as a snapshot (no dependency), for readers outside the template's effects that may
    /// run during a row's mount (the tab node binding, Hooks.mounted).
    pub fn visualNow(self: *const ViewModel, id: u64) Visual {
        for (self.visuals_signal.peek()) |value| if (value.id == id) return value;
        return .{ .id = id, .icon = ui.icons.terminal };
    }
    pub fn hasVisual(self: *const ViewModel, id: u64) bool {
        for (self.visuals_signal.peek()) |value| if (value.id == id) return true;
        return false;
    }
    pub fn hasTabs(self: *const ViewModel) bool {
        return self.rows_signal.get().len != 0;
    }
    pub fn look(self: *const ViewModel, row: Row) Look {
        const hovered = self.hovered.get() == row.id;
        const pressed = self.pressed.get() == row.id;
        const lifted = self.lifted.get() == row.id;
        return .{ .width = row.width, .state = if (lifted) .normal else m.state(row.active, hovered, pressed), .lifted = lifted, .drop = self.drop.get() == row.id };
    }
    pub fn dividerShown(self: *const ViewModel, row: Row) bool {
        const previous = row.previous_id orelse return false;
        if (row.active or row.previous_active) return false;
        const hovered = self.hovered.get();
        const lifted = self.lifted.get();
        return hovered != row.id and hovered != previous and lifted != row.id and lifted != previous;
    }
    /// 关闭钮跟随指针或键盘焦点出现（激活页签同样）；按住 ⌘ 时让位给序号；拖起的页签隐藏它。
    pub fn closeShown(self: *const ViewModel, id: u64) bool {
        if (self.ordinals.get() or self.lifted.get() == id) return false;
        return self.hovered.get() == id or self.focused.get() == id;
    }
    pub fn ordinalsShown(self: *const ViewModel) bool {
        return self.ordinals.get();
    }
    pub fn gapShown(self: *const ViewModel) bool {
        return self.gap.get() != null;
    }
    pub fn gapX(self: *const ViewModel) f32 {
        return self.gap.get() orelse 0;
    }
    pub fn tipsEpoch(self: *const ViewModel) u64 {
        return self.tips_epoch.get();
    }
    pub fn tipAllowed(self: *const ViewModel, id: u64) bool {
        if (self.cells.get(id)) |value| if (value.tip_suppressed) return false;
        return self.hooks.tip_allowed(self.hooks.context, id);
    }
    pub fn overflowShown(self: *const ViewModel) bool {
        return self.overflow_items.get().len != 0;
    }
    pub fn overflowItems(self: *const ViewModel) []const W.MenuItem {
        return self.overflow_items.get();
    }
    pub fn overflowLabel(self: *const ViewModel) []const u8 {
        return self.overflow_label.get();
    }
    /// 单元上下文（事件与拖动的 context）。模板求值时调用，所以缺了就建。
    pub fn cell(self: *ViewModel, id: u64) ?*anyopaque {
        return @ptrCast(self.cellFor(id) catch return null);
    }

    // ---- 模板里的事件 ----

    pub fn hover(self: *ViewModel, id: u64, on: bool) void {
        const target = self.cells.get(id) orelse return;
        target.hovered = on;
        if (!on) {
            target.pressed = false;
            target.tip_suppressed = false;
        }
        if (on) self.hovered.set(id) else if (self.hovered.peek() == id) self.hovered.set(null);
        if (!on and self.pressed.peek() == id) self.pressed.set(null);
    }
    pub fn focus(self: *ViewModel, id: u64, on: bool) void {
        if (on) self.focused.set(id) else if (self.focused.peek() == id) self.focused.set(null);
    }
    pub fn close(self: *ViewModel, id: u64) void {
        self.hooks.close(self.hooks.context, id);
    }
    pub fn pickOverflow(self: *ViewModel, id: []const u8) void {
        const value = std.fmt.parseInt(u64, id, 10) catch return;
        self.hooks.overflow(self.hooks.context, value);
    }

    /// 单元的通用事件：左键按下 / 抬起只记按下态，其余交给 workspace（选中、关闭列、右键 / 中键、双击、Enter）。
    pub fn cellEvent(event: ui.events.Event, context: ?*anyopaque) ui.events.EventResult {
        const target: *Cell = @ptrCast(@alignCast(context orelse return .ignored));
        const self = target.vm;
        switch (event) {
            .mouse_down => |mouse| {
                // Any press hides this tab's hint until the pointer leaves it.
                target.tip_suppressed = true;
                self.closeTips();
                if (mouse.button == .left) {
                    target.pressed = true;
                    self.pressed.set(target.id);
                }
            },
            .mouse_up => if (target.pressed) {
                target.pressed = false;
                if (self.pressed.peek() == target.id) self.pressed.set(null);
            },
            else => {},
        }
        return self.hooks.event(self.hooks.context, target, event);
    }
    /// 关闭钮的事件：点击（含空格 / 回车合成的点击）关闭这个页签并到此为止，按下 / 抬起也不冒泡到页签
    /// （按住关闭钮时页签不进入按下态，单元的“关闭列”逻辑不会再关一次）。
    pub fn closeEvent(event: ui.events.Event, context: ?*anyopaque) ui.events.EventResult {
        const target: *Cell = @ptrCast(@alignCast(context orelse return .ignored));
        switch (event) {
            .click => |click| if (click.button == .left) {
                target.vm.close(target.id);
                return .stop;
            },
            .mouse_down, .mouse_up => return .stop,
            else => {},
        }
        return .ignored;
    }

    // ---- 宿主接口 ----

    pub fn mount(cx: *ui.Cx, scope: *ui.Scope, hooks: Hooks) !*ViewModel {
        const self = try scope.createState(ViewModel, .{
            .cx = cx,
            .scope = scope,
            .hooks = hooks,
            .rows_signal = try scope.createSignal([]const Row, &.{}),
            .active_surface = try scope.createSignal(W.joined_surface.Target, .none),
            .visuals_signal = try scope.createSignal([]const Visual, &.{}),
            .hovered = try scope.createSignal(?u64, null),
            .pressed = try scope.createSignal(?u64, null),
            .focused = try scope.createSignal(?u64, null),
            .ordinals = try scope.createSignal(bool, false),
            .lifted = try scope.createSignal(?u64, null),
            .drop = try scope.createSignal(?u64, null),
            .gap = try scope.createSignal(?f32, null),
            .tips_epoch = try scope.createSignal(u64, 0),
            .overflow_items = try scope.createSignal([]const W.MenuItem, &.{}),
            .overflow_label = try scope.createSignal([]const u8, ""),
            .arenas = .{ std.heap.ArenaAllocator.init(cx.allocator), std.heap.ArenaAllocator.init(cx.allocator) },
        });
        try scope.onCleanup(ViewModel, self, deinit);
        self.root = try ui.view.render(scope, cx, template.TabStrip(.{ .vm = self }));
        return self;
    }

    fn deinit(self: *ViewModel) void {
        for (self.cells.values()) |value| {
            value.freeTexts();
            self.cx.allocator.destroy(value);
        }
        self.cells.deinit(self.cx.allocator);
        for (&self.arenas) |*arena| arena.deinit();
        for (&self.visual_buffers) |*buffer| buffer.deinit(self.cx.allocator);
        self.scratch.deinit(self.cx.allocator);
    }

    pub fn cellFor(self: *ViewModel, id: u64) !*Cell {
        if (self.cells.get(id)) |found| return found;
        const created = try self.cx.allocator.create(Cell);
        errdefer self.cx.allocator.destroy(created);
        created.* = .{ .vm = self, .id = id };
        try self.cells.put(self.cx.allocator, id, created);
        return created;
    }
    pub fn findCell(self: *const ViewModel, id: u64) ?*Cell {
        return self.cells.get(id);
    }

    /// 下一次同步用的分配器（与当前显示的行不是同一块）。
    pub fn nextArena(self: *ViewModel) std.mem.Allocator {
        const next: u1 = self.current ^ 1;
        _ = self.arenas[next].reset(.retain_capacity);
        return self.arenas[next].allocator();
    }

    /// 写入新的行与溢出菜单（都必须分配在 `nextArena()` 里）。与当前内容相同时什么也不写、也不切换 arena：
    /// 信号在内容相同的写入里会保留旧数组，那块 arena 若被下一次同步复用，新数组可能落在同一地址并被就地改写，
    /// 信号就会把真正的变化当成“没变”。
    pub fn setRows(self: *ViewModel, next_rows: []const Row, items: []const W.MenuItem, label: []const u8) void {
        if (sameRows(self.rows_signal.peek(), next_rows) and sameItems(self.overflow_items.peek(), items) and std.mem.eql(u8, self.overflow_label.peek(), label)) return;
        self.current ^= 1;
        for (self.cells.values()) |value| value.present = false;
        for (next_rows) |row| if (self.cells.get(row.id)) |value| {
            value.present = true;
        };
        self.rows_signal.set(next_rows);
        self.overflow_items.set(items);
        self.overflow_label.set(label);
        self.prune();
        self.publishActiveSurface();
    }

    pub fn activeSurface(self: *const ViewModel) *ui.Signal(W.joined_surface.Target) {
        return self.active_surface;
    }

    fn publishActiveSurface(self: *ViewModel) void {
        const target: W.joined_surface.Target = for (self.rows_signal.peek()) |row| {
            if (!row.active or self.lifted.peek() == row.id) continue;
            const selected_cell = self.cells.get(row.id) orelse break .none;
            const surface = selected_cell.surface orelse break .none;
            break W.joined_surface.targetOf(self.cx, surface) catch |err| {
                std.log.err("Could not track active tab surface: {}", .{err});
                return;
            };
        } else .none;
        if (!self.active_surface.peek().eql(target)) self.active_surface.set(target);
    }

    fn sameRows(a: []const Row, b: []const Row) bool {
        if (a.len != b.len) return false;
        // Row strings are cell-owned: equal content keeps the same pointer (Cell.text).
        for (a, b) |x, y| if (!std.meta.eql(x, y)) return false;
        return true;
    }
    fn sameItems(a: []const W.MenuItem, b: []const W.MenuItem) bool {
        if (a.len != b.len) return false;
        for (a, b) |x, y| {
            if (!std.mem.eql(u8, x.id, y.id) or !std.mem.eql(u8, x.label, y.label) or !std.mem.eql(u8, x.test_id, y.test_id)) return false;
            if ((x.shortcut == null) != (y.shortcut == null)) return false;
            if (x.shortcut) |sx| if (!std.mem.eql(u8, sx, y.shortcut.?)) return false;
            if (!std.meta.eql(x.icon_tint, y.icon_tint)) return false;
            if ((x.icon_asset == null) != (y.icon_asset == null)) return false;
            if (x.icon_asset) |ax| if (ax.icon_id != y.icon_asset.?.icon_id) return false;
        }
        return true;
    }

    /// 已离开页签条、行也已卸载的单元上下文。
    fn prune(self: *ViewModel) void {
        var index: usize = 0;
        while (index < self.cells.count()) {
            const value = self.cells.values()[index];
            if (!value.present and value.holder == null) {
                self.cells.swapRemoveAt(index);
                if (self.hovered.peek() == value.id) self.hovered.set(null);
                if (self.focused.peek() == value.id) self.focused.set(null);
                value.freeTexts();
                self.cx.allocator.destroy(value);
            } else index += 1;
        }
    }

    /// 写入每个页签的视觉；与当前相同时不触发更新（每帧调用）。
    pub fn setVisuals(self: *ViewModel, values: []const Visual) !void {
        const old = self.visuals_signal.peek();
        if (old.len == values.len) {
            var same = true;
            for (old, values) |a, b| if (!a.eql(b)) {
                same = false;
                break;
            };
            if (same) return;
        }
        const next: u1 = self.visual_current ^ 1;
        const buffer = &self.visual_buffers[next];
        buffer.clearRetainingCapacity();
        try buffer.appendSlice(self.cx.allocator, values);
        self.visual_current = next;
        self.visuals_signal.set(buffer.items);
    }
    pub fn setOrdinals(self: *ViewModel, shown: bool) void {
        if (self.ordinals.peek() != shown) self.ordinals.set(shown);
    }
    pub fn setLifted(self: *ViewModel, id: ?u64) void {
        if (self.lifted.peek() == id) return;
        self.lifted.set(id);
        self.publishActiveSurface();
    }
    pub fn setDropTarget(self: *ViewModel, id: ?u64) void {
        if (self.drop.peek() != id) self.drop.set(id);
    }
    /// 拖动插入缝的位置（相对页签区左缘）；null 隐藏。
    pub fn setGap(self: *ViewModel, x: ?f32) void {
        const old = self.gap.peek();
        if (old == null and x == null) return;
        if (old != null and x != null and @abs(old.? - x.?) < 0.01) return;
        self.gap.set(x);
    }
    /// 收起所有页签的 Tooltip；指针所在的页签直到离开前不再弹（打开页签菜单时）。
    pub fn suppressTips(self: *ViewModel) void {
        for (self.cells.values()) |value| if (value.hovered) {
            value.tip_suppressed = true;
        };
        self.closeTips();
    }
    pub fn closeTips(self: *ViewModel) void {
        self.tips_epoch.set(self.tips_epoch.peek() +% 1);
    }
    pub fn clearPressed(self: *ViewModel, id: u64) void {
        if (self.cells.get(id)) |value| value.pressed = false;
        if (self.pressed.peek() == id) self.pressed.set(null);
    }
    pub fn isHovered(self: *const ViewModel, id: u64) bool {
        return if (self.cells.get(id)) |value| value.hovered else false;
    }
    pub fn newTabButton(self: *const ViewModel) ?*ui.Node {
        return self.new_tab;
    }
};

// ---- 模板回调（onMount）----

pub fn keepNodes(vm: *ViewModel, id: u64, surface: *ui.view.Ref(*ui.Node), title: *ui.view.Ref(*ui.Node), close: *ui.view.Ref(*ui.Node), icon: *ui.view.Ref(*ui.Node), ordinal: *ui.view.Ref(*ui.Node)) void {
    const target = vm.cellFor(id) catch return;
    target.surface = surface.get();
    target.title = title.get();
    target.close = close.get();
    target.icon_slot = icon.get();
    target.ordinal = ordinal.get();
    vm.publishActiveSurface();
    vm.hooks.mounted(vm.hooks.context, id);
}
pub fn keepStrip(vm: *ViewModel, button: *ui.view.Ref(*ui.Node), viewport: *ui.view.Ref(*ui.Node)) void {
    vm.new_tab = button.get();
    vm.viewport = viewport.get();
}

// ---- TabCell：页签单元外层盒子 + 拖动绑定（手写组件，模板里当标签用）----

/// Read once at mount (a row keeps its tab id; a tab never turns into a group tab).
pub const TabCellProps = struct {
    vm: ui.Source(*ViewModel),
    id: ui.Source(u64),
    /// 会话组页签：外层盒子的 test_id 是 `groups.tab`。
    group: ui.Source(bool) = .{ .value = false },
};

fn mountTabCell(props: TabCellProps, scope: *ui.Scope, cx: *ui.Cx) !ui.view.ViewParts {
    const vm = props.vm.peek();
    const target = try vm.cellFor(props.id.peek());
    const root = try ui.box(cx, .{ .direction = .row, .align_items = .end, .flex_shrink = 0, .hit_behavior = .@"opaque" }, .{});
    errdefer cx.destroyDetached(root);
    // The whole capsule is a client surface: AppKit must not take these presses as window drags.
    root.behavior.interaction.window_region = .client;
    if (props.group.peek()) root.meta.ownership.meta.test_id = template.ids.group_tab;
    target.holder = root;
    try scope.onCleanup(Cell, target, Cell.unmounted);
    target.drag = try ui.interaction.drag.Binding.attach(scope, cx, root, .{ .axis = .both }, onDrag, target);
    return .{ .root = root, .slot = root };
}
pub fn TabCell(props: anytype) ui.view.SlottedOf(mountTabCell) {
    return ui.view.slotted(mountTabCell, props);
}

fn onDrag(event: ui.interaction.drag.Event, context: *anyopaque) void {
    const target: *Cell = @ptrCast(@alignCast(context));
    target.vm.hooks.drag(target.vm.hooks.context, target, event);
}
