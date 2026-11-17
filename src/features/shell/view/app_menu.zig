//! 菜单的唯一构建与挂载入口（CONSISTENCY_AUDIT #3，menus 包）。
//!
//! - `build`：把 `model/menu_spec.zig` 的声明按唯一的排列规则（`menu_spec.arrange`）投影成原生 `W.MenuItem`：
//!   图标名 → `ui.icons`，快捷键命令 → 路由当前的组合文字，禁用原因、危险、分组标题、子菜单照搬。
//! - `AppMenu`：一个原生 `W.Menu` 的状态——打开标志、项（两块交替的缓冲，信号替换时旧数组仍有效）、
//!   锚点矩形与宿主回调。右键 / 快捷键打开的菜单用 `mountContext`（`app_menu.yix`，`trigger = .manual` +
//!   虚拟锚点），按钮触发的菜单（窗格“更多”、传输任务“⋯”、分组“⋯”、KVM“更多”）用 `mountTrigger`，
//!   触发按钮由调用方放进返回的 `trigger` 槽。两者都只经这里，不再有手画的菜单列表。
//! - 打开中的菜单登记在 `live`，测试路由（`/zerowork/menus`）据此列出每一行的标题、快捷键与命令。
const std = @import("std");
const ui = @import("ui");
const W = ui.widgets;
const spec = @import("../model/menu_spec.zig");
const shortcut_router = @import("../model/shortcut_router.zig");
const template = @import("_app_menu.yix.zig");

pub const Entry = spec.Entry;
pub const Command = spec.Command;
pub const max_rows = spec.max_rows;
pub const max_children = 96;
/// 模板形态的右键式菜单（`app_menu.yix`），配合 `AppMenu.initContext`。
pub const ContextMenu = template.ContextMenu;

/// 一份投影结果：行、子菜单行、每行对应的命令（测试路由用）。
pub const Built = struct {
    items: [max_rows]W.MenuItem = undefined,
    commands: [max_rows]?spec.Command = undefined,
    pool: [max_children]W.MenuItem = undefined,
    count: usize = 0,
    used: usize = 0,

    pub fn slice(self: *const Built) []const W.MenuItem {
        return self.items[0..self.count];
    }
};

fn project(entry: *const Entry, router: shortcut_router.Router, children: []const W.MenuItem) W.MenuItem {
    if (entry.kind == .header) return .{ .kind = .header, .label = entry.label, .test_id = entry.test_id };
    return .{
        .id = entry.id,
        .label = entry.label,
        .test_id = entry.test_id,
        .shortcut = spec.shortcutText(entry.*, router),
        .disabled = entry.isDisabled(),
        .disabled_reason = entry.disabled_reason,
        .danger = entry.danger,
        .selected = entry.selected,
        .description = entry.description,
        .tag = entry.tag,
        .icon_asset = if (entry.icon_asset) |raw| @as(*const ui.SvgAsset, @ptrCast(@alignCast(raw))).* else if (entry.icon.len != 0) ui.icons.get(entry.icon) else null,
        .icon_tint = if (entry.tint) |rgb| ui.Color.hex(@truncate(rgb)) else null,
        .children = children,
        .submenu_test_id = entry.submenu_test_id,
        .submenu_max_height = entry.submenu_max_height,
    };
}

fn buildChildren(out: *Built, entries: []const Entry, router: shortcut_router.Router) []const W.MenuItem {
    var rows: [max_rows]spec.Row = undefined;
    const arranged = spec.arrange(entries, &rows);
    const start = out.used;
    const room = max_children - start;
    const n = @min(arranged.len, room);
    for (arranged[0..n], 0..) |row, index| out.pool[start + index] = switch (row) {
        .separator => .{ .kind = .separator },
        // Second level only: deeper trees are not used by any ZeroWork menu.
        .entry => |entry| project(entry, router, &.{}),
    };
    out.used = start + n;
    return out.pool[start .. start + n];
}

/// 唯一的投影：排列（常用在前、组间分隔、危险最后）+ 原生行。
pub fn build(out: *Built, entries: []const Entry, router: shortcut_router.Router) []const W.MenuItem {
    out.count = 0;
    out.used = 0;
    var rows: [max_rows]spec.Row = undefined;
    for (spec.arrange(entries, &rows)) |row| {
        switch (row) {
            .separator => {
                out.items[out.count] = .{ .kind = .separator };
                out.commands[out.count] = null;
            },
            .entry => |entry| {
                const children = if (entry.children.len != 0) buildChildren(out, entry.children, router) else &.{};
                out.items[out.count] = project(entry, router, children);
                out.commands[out.count] = if (entry.kind == .item) entry.command else null;
            },
        }
        out.count += 1;
    }
    return out.slice();
}

/// 编译期投影（设置窗口等静态菜单）：同一排列规则，图标只能给 `icon_asset`（`&ui.icons.x`），不带快捷键命令。
pub fn static(comptime entries: []const Entry) []const W.MenuItem {
    return comptime blk: {
        @setEvalBranchQuota(100_000);
        var rows: [max_rows]spec.Row = undefined;
        const arranged = spec.arrange(entries, &rows);
        var out: [arranged.len]W.MenuItem = undefined;
        for (arranged, 0..) |row, index| out[index] = switch (row) {
            .separator => .{ .kind = .separator },
            .entry => |entry| item: {
                if (entry.command != null or entry.icon.len != 0 or entry.children.len != 0) @compileError("app_menu.static: no shortcut commands, icon names or submenus");
                if (entry.kind == .header) break :item .{ .kind = .header, .label = entry.label, .test_id = entry.test_id };
                break :item .{ .id = entry.id, .label = entry.label, .test_id = entry.test_id, .shortcut = entry.note, .disabled = entry.isDisabled(), .disabled_reason = entry.disabled_reason, .danger = entry.danger, .icon_asset = if (entry.icon_asset) |raw| @as(*const ui.SvgAsset, @ptrCast(@alignCast(raw))).* else null };
            },
        };
        const final = out;
        break :blk &final;
    };
}

pub const Hooks = struct {
    context: *anyopaque,
    select: *const fn (*anyopaque, []const u8) void,
    closed: ?*const fn (*anyopaque) void = null,
};

pub const ContextOptions = struct {
    /// 弹出面板的 test_id（行的 test_id 写在各条目上）。
    panel_test_id: []const u8,
    width: ?f32 = null,
    /// 行多时面板的最大高度（原生菜单在面板里滚动）。
    max_height: ?f32 = null,
    position: W.PopoverPosition = .bottom_start,
};

pub const TriggerOptions = struct {
    panel_test_id: []const u8,
    width: ?f32 = null,
    position: W.PopoverPosition = .bottom_start,
    /// `.manual`：触发按钮自己开合（`AppMenu.open`），例如开菜单前要先收起同排的其他面板。
    trigger: W.popover.PopoverTrigger = .click,
    /// 固定配色（KVM 远端画面上的菜单保持深色，与同排面板一致）。
    color_scheme: ?ui.ColorScheme = null,
};

pub const AppMenu = struct {
    cx: *ui.Cx,
    hooks: Hooks,
    panel_test_id: []const u8,
    open: *ui.Signal(bool),
    items: *ui.Signal([]const W.MenuItem),
    rect: W.popover.AnchorRect = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
    built: [2]Built = .{ .{}, .{} },
    current: u1 = 0,
    next: ?*AppMenu = null,
    prev: ?*AppMenu = null,

    fn create(cx: *ui.Cx, scope: *ui.Scope, panel_test_id: []const u8, hooks: Hooks) !*AppMenu {
        const self = try scope.createState(AppMenu, .{ .cx = cx, .hooks = hooks, .panel_test_id = panel_test_id, .open = try scope.createSignal(bool, false), .items = try scope.createSignal([]const W.MenuItem, &.{}) });
        try scope.onCleanup(AppMenu, self, unregister);
        register(self);
        return self;
    }

    /// 右键 / 快捷键打开的菜单：挂载点放进 `parent`（零尺寸），面板在窗口浮层根。
    pub fn mountContext(cx: *ui.Cx, scope: *ui.Scope, parent: *ui.Node, options: ContextOptions, hooks: Hooks) !*AppMenu {
        const self = try create(cx, scope, options.panel_test_id, hooks);
        try parent.appendChild(cx.allocator, try ui.view.render(scope, cx, template.ContextMenu(.{
            .open = self.open,
            .items = self.items,
            .anchor = W.popover.Anchor{ .virtual = .{ .ctx = self, .getRect = anchorRect } },
            .panel_test_id = options.panel_test_id,
            .width = options.width,
            .max_height = options.max_height,
            .position = options.position,
            .on_open_change = cx.on(AppMenu, self, openChanged),
            .on_select = cx.on(AppMenu, self, selected),
        })));
        return self;
    }

    /// 由模板摆放的右键式菜单（`.yix` 视图里写 `<ContextMenu …/>`）：这里只建状态——项、开合、锚点矩形、
    /// 回调与测试路由登记，与 `mountContext` 相同；模板用 `virtualAnchor()` / `openChanged` / `selected` 接线。
    pub fn initContext(cx: *ui.Cx, scope: *ui.Scope, panel_test_id: []const u8, hooks: Hooks) !*AppMenu {
        return create(cx, scope, panel_test_id, hooks);
    }
    /// 模板里的虚拟锚点（`show` 写入的矩形）。
    pub fn virtualAnchor(self: *AppMenu) W.popover.Anchor {
        return .{ .virtual = .{ .ctx = self, .getRect = anchorRect } };
    }
    /// 模板的 `onOpenChange` / `onSelect` 转到这里。
    pub fn openChange(self: *AppMenu, value: bool) void {
        self.openChanged(value);
    }
    pub fn select(self: *AppMenu, id: []const u8) void {
        self.selected(id);
    }

    pub const Mounted = struct { menu: *AppMenu, result: W.menu.MenuResult };

    /// 按钮触发的菜单：调用方把触发按钮放进 `result.trigger`、把 `result.wrapper` 放进布局。
    pub fn mountTrigger(cx: *ui.Cx, scope: *ui.Scope, options: TriggerOptions, hooks: Hooks) !Mounted {
        const self = try create(cx, scope, options.panel_test_id, hooks);
        const result = try W.Menu(.{
            .items = self.items,
            .open = self.open,
            .width = options.width,
            .position = options.position,
            .trigger = options.trigger,
            .color_scheme = options.color_scheme,
            .panel_test_id = options.panel_test_id,
            .on_open_change = cx.on(AppMenu, self, openChanged),
            .on_select = cx.on(AppMenu, self, selected),
        }).mount(scope, cx);
        return .{ .menu = self, .result = result };
    }

    fn anchorRect(raw: *anyopaque) W.popover.AnchorRect {
        const self: *AppMenu = @ptrCast(@alignCast(raw));
        return self.rect;
    }
    fn openChanged(self: *AppMenu, value: bool) void {
        self.open.set(value);
        if (!value) if (self.hooks.closed) |closed| closed(self.hooks.context);
    }
    fn selected(self: *AppMenu, id: []const u8) void {
        self.hooks.select(self.hooks.context, id);
    }

    /// 换上新的项（写进打开中的菜单没在显示的那块缓冲）。
    pub fn set(self: *AppMenu, entries: []const Entry, router: shortcut_router.Router) void {
        const slot = self.current ^ 1;
        self.current = slot;
        self.items.set(build(&self.built[slot], entries, router));
    }

    /// 写入项并在 `anchor`（全局坐标；指针按下处是零尺寸矩形）打开。
    pub fn show(self: *AppMenu, entries: []const Entry, router: shortcut_router.Router, anchor: ui.ComputedRect) void {
        self.set(entries, router);
        self.rect = .{ .x = anchor.x, .y = anchor.y, .w = anchor.w, .h = anchor.h };
        self.open.set(true);
        self.cx.requestRedraw();
    }

    /// Drops the rows (a hidden menu keeps its rows mounted; clear them before the strings they borrow go away).
    pub fn clear(self: *AppMenu) void {
        self.hide();
        if (self.items.peek().len != 0) self.items.set(&.{});
    }
    pub fn isOpen(self: *const AppMenu) bool {
        return self.open.peek();
    }
    pub fn hide(self: *AppMenu) void {
        if (self.open.peek()) self.open.set(false);
    }
    pub fn currentItems(self: *const AppMenu) []const W.MenuItem {
        return self.items.peek();
    }
    pub fn currentCommands(self: *const AppMenu) []const ?spec.Command {
        const built = &self.built[self.current];
        return built.commands[0..built.count];
    }
};

var live: ?*AppMenu = null;

fn register(menu: *AppMenu) void {
    menu.next = live;
    menu.prev = null;
    if (live) |head| head.prev = menu;
    live = menu;
}
fn unregister(menu: *AppMenu) void {
    if (menu.prev) |prev| prev.next = menu.next else if (live == menu) live = menu.next;
    if (menu.next) |next| next.prev = menu.prev;
    menu.next = null;
    menu.prev = null;
}

/// 测试路由（`/zerowork/menus`，只在 test-mode 由 src/app 接入）：每个打开中的菜单的面板 id 与行。
pub fn writeSnapshot(writer: *std.Io.Writer) !void {
    try writer.writeAll("{\"ok\":true,\"menus\":[");
    var first = true;
    var cursor = live;
    while (cursor) |menu| : (cursor = menu.next) {
        if (!menu.isOpen()) continue;
        if (!first) try writer.writeAll(",");
        first = false;
        try writer.writeAll("{\"panel\":");
        try std.json.Stringify.value(menu.panel_test_id, .{}, writer);
        try writer.writeAll(",\"rows\":[");
        const items = menu.currentItems();
        const commands = menu.currentCommands();
        for (items, 0..) |item, index| {
            if (index != 0) try writer.writeAll(",");
            try writer.print("{{\"kind\":\"{s}\",\"id\":", .{@tagName(item.kind)});
            try std.json.Stringify.value(item.id, .{}, writer);
            try writer.writeAll(",\"label\":");
            try std.json.Stringify.value(item.label, .{}, writer);
            try writer.writeAll(",\"test_id\":");
            try std.json.Stringify.value(item.test_id, .{}, writer);
            try writer.writeAll(",\"shortcut\":");
            try std.json.Stringify.value(item.shortcut orelse "", .{}, writer);
            try writer.writeAll(",\"reason\":");
            try std.json.Stringify.value(item.disabled_reason orelse "", .{}, writer);
            const command: ?spec.Command = if (index < commands.len) commands[index] else null;
            try writer.print(",\"command\":\"{s}\",\"danger\":{},\"disabled\":{},\"submenu\":", .{ if (command) |value| @tagName(value) else "", item.danger, item.disabled });
            try std.json.Stringify.value(item.submenu_test_id, .{}, writer);
            try writer.writeAll(",\"children\":[");
            for (item.children, 0..) |child, child_index| {
                if (child_index != 0) try writer.writeAll(",");
                try writer.print("{{\"kind\":\"{s}\",\"id\":", .{@tagName(child.kind)});
                try std.json.Stringify.value(child.id, .{}, writer);
                try writer.writeAll(",\"label\":");
                try std.json.Stringify.value(child.label, .{}, writer);
                try writer.writeAll(",\"shortcut\":");
                try std.json.Stringify.value(child.shortcut orelse "", .{}, writer);
                try writer.writeAll(",\"reason\":");
                try std.json.Stringify.value(child.disabled_reason orelse "", .{}, writer);
                try writer.print(",\"command\":\"\",\"danger\":{},\"disabled\":{}}}", .{ child.danger, child.disabled });
            }
            try writer.writeAll("]}");
        }
        try writer.writeAll("]}");
    }
    // Layers of the window that owns the first open menu: tier, paint order (content z) and rect, so
    // e2e can prove no tooltip paints over an open menu.
    try writer.writeAll("],\"layers\":[");
    var owner: ?*ui.Cx = null;
    cursor = live;
    while (cursor) |menu| : (cursor = menu.next) if (menu.isOpen()) {
        owner = menu.cx;
        break;
    };
    if (owner) |cx| {
        var first_layer = true;
        for (cx.overlay_stack.layers.items) |*slot| {
            const layer = if (slot.*) |*value| value else continue;
            if (layer.suspended or layer.state == .exiting) continue;
            const content = layer.content_node orelse continue;
            const Tier = @typeInfo(@TypeOf(layer.config.tier)).optional.child;
            const tier = layer.config.tier orelse Tier.fromKind(layer.config.kind);
            const rect = content.globalRect();
            if (!first_layer) try writer.writeAll(",");
            first_layer = false;
            try writer.print("{{\"tier\":\"{s}\",\"z\":{d},\"x\":{d},\"y\":{d},\"w\":{d},\"h\":{d},\"test_id\":", .{ @tagName(tier), content.style.z_index(), rect.x, rect.y, rect.w, rect.h });
            try std.json.Stringify.value(content.meta.ownership.meta.test_id orelse "", .{}, writer);
            try writer.writeAll("}");
        }
    }
    try writer.writeAll("]}");
}

test "build: rows follow the one arrangement rule, shortcut text from the router, reasons and headers kept" {
    const defaults: shortcut_router.Map = .{};
    const router: shortcut_router.Router = .{ .keys = &defaults };
    const colors = [_]Entry{
        .{ .id = "c.red", .label = "红", .icon = "circle", .tint = 0xe27878, .selected = true },
        .{ .id = "c.none", .label = "无", .icon = "circle-off" },
    };
    const entries = [_]Entry{
        .{ .id = "close", .label = "关闭页签", .icon = "x", .command = .close_tab, .danger = true, .test_id = "m.close" },
        .{ .label = "页签 · 1", .kind = .header },
        .{ .id = "copy", .label = "复制", .icon = "copy", .command = .copy, .disabled_reason = "未选中内容" },
        .{ .id = "color", .label = "颜色", .icon = "palette", .children = &colors, .submenu_test_id = "m.color" },
        .{ .id = "export", .label = "导出", .group = 1 },
    };
    var built: Built = .{};
    const items = build(&built, &entries, router);
    try std.testing.expectEqual(@as(usize, 7), items.len);
    try std.testing.expectEqual(W.MenuItemKind.header, items[0].kind);
    try std.testing.expect(items[1].disabled);
    try std.testing.expect(items[1].description == null and items[1].tag == null);
    try std.testing.expectEqualStrings("未选中内容", items[1].disabled_reason.?);
    try std.testing.expectEqualStrings(router.hint(.copy), items[1].shortcut.?);
    try std.testing.expect(items[1].icon_asset != null);
    try std.testing.expectEqual(@as(usize, 2), items[2].children.len);
    try std.testing.expect(items[2].children[0].selected and items[2].children[0].icon_tint != null);
    try std.testing.expectEqualStrings("m.color", items[2].submenu_test_id);
    try std.testing.expectEqual(W.MenuItemKind.separator, items[3].kind);
    try std.testing.expectEqualStrings("export", items[4].id);
    try std.testing.expectEqual(W.MenuItemKind.separator, items[5].kind);
    try std.testing.expect(items[6].danger);
    try std.testing.expectEqualStrings("m.close", items[6].test_id);
    try std.testing.expectEqual(@as(?spec.Command, .close_tab), built.commands[6]);
}

test "build: description and tag reach the native row" {
    const defaults: shortcut_router.Map = .{};
    const entries = [_]Entry{.{ .id = "pty", .label = "附加现有 PTY", .description = "在已打开的终端里执行", .tag = "交互式", .selected = true }};
    var built: Built = .{};
    const items = build(&built, &entries, .{ .keys = &defaults });
    try std.testing.expectEqualStrings("在已打开的终端里执行", items[0].description.?);
    try std.testing.expectEqualStrings("交互式", items[0].tag.?);
    try std.testing.expect(items[0].selected);
}

test "static: compile-time menus follow the same rule (danger last after a separator)" {
    const items = static(&.{
        .{ .id = "remove", .label = "移除", .icon_asset = &ui.icons.trash, .danger = true },
        .{ .id = "edit", .label = "编辑", .icon_asset = &ui.icons.pencil },
        .{ .id = "off", .label = "删除导入主题", .disabled_reason = "内置主题不可删除", .danger = true },
    });
    try std.testing.expectEqual(@as(usize, 4), items.len);
    try std.testing.expectEqualStrings("edit", items[0].id);
    try std.testing.expectEqual(W.MenuItemKind.separator, items[1].kind);
    try std.testing.expect(items[2].danger and items[3].disabled);
    try std.testing.expectEqualStrings("内置主题不可删除", items[3].disabled_reason.?);
}
