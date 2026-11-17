//! 新建会话菜单（页签条“+”、⌘T）：原生 `W.Menu`，经菜单唯一入口（`shell/view/app_menu.zig`）挂载与投影
//! （menus 包；此前是 Popover + Button 手画的分组列表，自写方向键与“更多”悬停子面板）。
//!
//! 条目（声明顺序 = 常用程度）：本地终端 · 最近使用的主机（至多 3 台；没有时一行“暂无最近使用的主机”，不可选）·
//! 更多 ›（原生子菜单：全部已保存主机，过长时在子菜单里滚动）| 分组标题“快捷连接”· 新建主机 · 新建 SFTP · 新建 KVM
//! （KVM 插件没注册时不出现，Q5）。键盘导航、子菜单开合、Esc、焦点进入与归还都是原生菜单的事。
const std = @import("std");
const ui = @import("ui");
const identity = @import("../../../host/identity.zig");
const app_menu = @import("../../shell/mod.zig").app_menu;
const shortcut_router = @import("../../shell/mod.zig").shortcut_router;
pub const Saved = struct { owner: identity.AssetOwner, name: []const u8, icon: ui.SvgAsset };

pub const Callbacks = struct {
    context: *anyopaque,
    new_profile: *const fn (*anyopaque) void,
    quick: *const fn (*anyopaque) void,
    local: ?*const fn (*anyopaque) void = null,
    new_sftp: ?*const fn (*anyopaque) void = null,
    new_kvm: ?*const fn (*anyopaque) void = null,
    saved: ?*const fn (*anyopaque, identity.AssetOwner) void = null,
};

pub const recent_max = 3;
/// 子菜单里一次列出的已保存主机（原生菜单一级至多 64 行）。
pub const all_max = 60;
const recent_ids = [_][]const u8{ "recent.0", "recent.1", "recent.2" };
const no_keys: shortcut_router.Map = .{};

/// 一组主机行的存放处：名字复制进 arena（调用方的列表可能是临时的），图标与归属并排存。两块 arena 交替：
/// 已挂载的原生菜单在重建前仍借用上一次的名字与图标（含无障碍标签），上一代要活到下一次填充。
const Hosts = struct {
    arenas: [2]std.heap.ArenaAllocator,
    slot: u1 = 0,
    owners: []identity.AssetOwner = &.{},
    names: [][]const u8 = &.{},
    icons: []ui.SvgAsset = &.{},

    fn init(allocator: std.mem.Allocator) Hosts {
        return .{ .arenas = .{ .init(allocator), .init(allocator) } };
    }
    fn deinit(self: *Hosts) void {
        for (&self.arenas) |*arena| arena.deinit();
    }
    fn fill(self: *Hosts, entries: []const Saved, max: usize) !void {
        self.slot ^= 1;
        _ = self.arenas[self.slot].reset(.retain_capacity);
        const allocator = self.arenas[self.slot].allocator();
        const n = @min(entries.len, max);
        self.owners = try allocator.alloc(identity.AssetOwner, n);
        self.names = try allocator.alloc([]const u8, n);
        self.icons = try allocator.alloc(ui.SvgAsset, n);
        for (entries[0..n], 0..) |entry, index| {
            self.owners[index] = entry.owner;
            self.names[index] = try allocator.dupe(u8, entry.name);
            self.icons[index] = entry.icon;
        }
    }
};

pub const View = struct {
    cx: *ui.Cx,
    scope: *ui.Scope,
    callbacks: Callbacks,
    /// 挂载点（零尺寸；菜单面板在窗口浮层根）。
    root: *ui.Node,
    menu: *app_menu.AppMenu,
    anchor_id: ?u32 = null,
    recent: Hosts,
    all: Hosts,
    all_ids: [all_max][16]u8 = undefined,
    children: [all_max]app_menu.Entry = undefined,
    entries: [12]app_menu.Entry = undefined,

    pub fn mount(cx: *ui.Cx, scope: *ui.Scope, callbacks: Callbacks) !*View {
        const self = try cx.allocator.create(View);
        errdefer cx.allocator.destroy(self);
        const root = try ui.box(cx, .{ .position = .absolute, .width = .{ .px = 0 }, .height = .{ .px = 0 } }, .{});
        self.* = .{ .cx = cx, .scope = scope, .callbacks = callbacks, .root = root, .menu = undefined, .recent = .init(cx.allocator), .all = .init(cx.allocator) };
        try scope.onCleanup(View, self, cleanup);
        self.menu = try app_menu.AppMenu.mountContext(cx, scope, root, .{ .panel_test_id = "session.menu" }, .{ .context = self, .select = selected });
        return self;
    }

    /// 在 `anchor`（“+”按钮）下方打开。焦点进入菜单，关闭后回到打开前的位置（⌘T：终端），原生菜单负责。
    pub fn show(self: *View, anchor: *ui.Node) !void {
        self.anchor_id = anchor.id;
        self.menu.show(self.declare(), .{ .keys = &no_keys }, anchorRect(anchor));
    }
    pub fn hide(self: *View) void {
        self.menu.hide();
    }
    pub fn isOpen(self: *const View) bool {
        return self.menu.isOpen();
    }
    /// 键盘导航全在原生菜单里；宿主仍把打开期间的按键先交给这里（不吞）。
    pub fn handleKey(_: *View, _: ui.events.KeyCode) ui.events.EventResult {
        return .ignored;
    }

    pub fn setSaved(self: *View, entries: []const Saved) !void {
        try self.recent.fill(entries, recent_max);
    }
    pub fn setAll(self: *View, entries: []const Saved) !void {
        try self.all.fill(entries, all_max);
    }

    /// 本次打开的条目（排列、分隔线由 `menu_spec.arrange` 统一给出）。
    fn declare(self: *View) []const app_menu.Entry {
        var n: usize = 0;
        self.entries[n] = .{ .id = "local", .label = "本地终端", .icon = "terminal", .test_id = "session.menu.local", .disabled_reason = if (self.callbacks.local == null) "本机终端不可用" else null };
        n += 1;
        for (self.recent.names, 0..) |name, index| {
            self.entries[n] = .{ .id = recent_ids[index], .label = name, .icon_asset = &self.recent.icons[index], .test_id = "session.menu.saved" };
            n += 1;
        }
        if (self.recent.names.len == 0) {
            self.entries[n] = .{ .id = "recent.none", .label = "暂无最近使用的主机", .disabled = true, .test_id = "session.menu.empty" };
            n += 1;
        }
        for (self.all.names, 0..) |name, index| {
            const id = std.fmt.bufPrint(&self.all_ids[index], "all.{d}", .{index}) catch "all";
            self.children[index] = .{ .id = id, .label = name, .icon_asset = &self.all.icons[index], .test_id = "session.menu.more.host" };
        }
        var children: []const app_menu.Entry = self.children[0..self.all.names.len];
        if (children.len == 0) {
            self.children[0] = .{ .id = "all.none", .label = "暂无已保存主机", .disabled = true };
            children = self.children[0..1];
        }
        self.entries[n] = .{ .id = "more", .label = "更多", .icon = "server", .children = children, .submenu_test_id = "session.menu.more.panel", .submenu_max_height = if (children.len > 8) 264 else null, .test_id = "session.menu.more" };
        n += 1;
        self.entries[n] = .{ .label = "快捷连接", .kind = .header, .group = 1 };
        n += 1;
        self.entries[n] = .{ .id = "new_profile", .label = "新建主机", .icon = "server", .group = 1, .test_id = "session.menu.new_profile" };
        n += 1;
        self.entries[n] = .{ .id = "new_sftp", .label = "新建 SFTP", .icon = "folder", .group = 1, .test_id = "session.menu.new_sftp", .disabled = self.callbacks.new_sftp == null };
        n += 1;
        // “新建 KVM”的插件没有注册（随应用插件被禁用，Q5）：这一项不出现。
        if (self.callbacks.new_kvm != null) {
            self.entries[n] = .{ .id = "new_kvm", .label = "新建 KVM", .icon = "monitor", .group = 1, .test_id = "session.menu.new_kvm" };
            n += 1;
        }
        return self.entries[0..n];
    }

    fn selected(raw: *anyopaque, id: []const u8) void {
        const self: *View = @ptrCast(@alignCast(raw));
        const context = self.callbacks.context;
        if (std.mem.eql(u8, id, "local")) {
            if (self.callbacks.local) |create| create(context);
        } else if (std.mem.eql(u8, id, "new_profile")) {
            self.callbacks.new_profile(context);
        } else if (std.mem.eql(u8, id, "new_sftp")) {
            if (self.callbacks.new_sftp) |create| create(context);
        } else if (std.mem.eql(u8, id, "new_kvm")) {
            if (self.callbacks.new_kvm) |create| create(context);
        } else if (std.mem.startsWith(u8, id, "recent.")) {
            const index = std.fmt.parseInt(usize, id["recent.".len..], 10) catch return;
            if (index < self.recent.owners.len) self.connect(self.recent.owners[index]);
        } else if (std.mem.startsWith(u8, id, "all.")) {
            const index = std.fmt.parseInt(usize, id["all.".len..], 10) catch return;
            if (index < self.all.owners.len) self.connect(self.all.owners[index]);
        }
    }
    fn connect(self: *View, owner: identity.AssetOwner) void {
        const callback = self.callbacks.saved orelse return;
        callback(self.callbacks.context, owner);
    }

    fn anchorRect(anchor: *ui.Node) ui.ComputedRect {
        const r = anchor.globalRect();
        const shell = @import("../../shell/view/shell_styles.zig");
        return .{ .x = r.x, .y = r.y, .w = r.w, .h = @max(r.h, shell.outer + shell.title_height - r.y) };
    }
    fn cleanup(self: *View) void {
        self.recent.deinit();
        self.all.deinit();
        self.cx.allocator.destroy(self);
    }
};

const Probe = struct {
    local: usize = 0,
    quick: usize = 0,
    saved: usize = 0,
    kvm: usize = 0,
    owner: ?identity.AssetOwner = null,
    fn onKvm(raw: *anyopaque) void {
        const self: *Probe = @ptrCast(@alignCast(raw));
        self.kvm += 1;
    }
    fn onLocal(raw: *anyopaque) void {
        const self: *Probe = @ptrCast(@alignCast(raw));
        self.local += 1;
    }
    fn onQuick(raw: *anyopaque) void {
        const self: *Probe = @ptrCast(@alignCast(raw));
        self.quick += 1;
    }
    fn onSaved(raw: *anyopaque) void {
        const self: *Probe = @ptrCast(@alignCast(raw));
        self.saved += 1;
    }
    fn onConnect(raw: *anyopaque, owner: identity.AssetOwner) void {
        const self: *Probe = @ptrCast(@alignCast(raw));
        self.owner = owner;
    }
};

fn frames(cx: *ui.Cx) void {
    for (0..6) |_| {
        cx.layout();
        _ = cx.render();
    }
}

test "new session menu: native rows in the declared order, each command once, focus restored" {
    const cx = try ui.Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    const scope = try ui.Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    cx.setViewport(860, 480);
    cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    const anchor = try ui.box(cx, .{ .width = .{ .px = 24 }, .height = .{ .px = 24 } }, .{});
    anchor.behavior.interaction.focusable = true;
    try cx.root.?.appendChild(cx.allocator, anchor);
    var probe: Probe = .{};
    const view = try View.mount(cx, scope, .{ .context = &probe, .local = Probe.onLocal, .quick = Probe.onQuick, .new_profile = Probe.onSaved, .new_kvm = Probe.onKvm, .saved = Probe.onConnect });
    try cx.root.?.appendChild(cx.allocator, view.root);
    const owner: identity.AssetOwner = .{ .id = @fromBackingInt(42), .revision = 7 };
    var saved_name = "Saved SSH".*;
    try view.setSaved(&.{.{ .owner = owner, .name = &saved_name, .icon = ui.icons.terminal }});
    try view.setAll(&.{.{ .owner = owner, .name = &saved_name, .icon = ui.icons.terminal }});
    saved_name[0] = 'X'; // the menu keeps its own copy of the names
    cx.setFocus(anchor);
    try view.show(anchor);
    frames(cx);
    const items = view.menu.currentItems();
    const want = [_][]const u8{ "local", "recent.0", "more", "", "", "new_profile", "new_sftp", "new_kvm" };
    try std.testing.expectEqual(want.len, items.len);
    for (want, items) |id, item| try std.testing.expectEqualStrings(id, item.id);
    try std.testing.expectEqualStrings("Saved SSH", items[1].label);
    try std.testing.expect(items[1].icon_asset != null);
    try std.testing.expectEqual(ui.widgets.MenuItemKind.separator, items[3].kind);
    try std.testing.expectEqual(ui.widgets.MenuItemKind.header, items[4].kind);
    try std.testing.expectEqualStrings("session.menu.more.panel", items[2].submenu_test_id);
    try std.testing.expectEqual(@as(usize, 1), items[2].children.len);
    try std.testing.expect(view.isOpen());
    for ([_][]const u8{ "local", "new_profile", "new_kvm", "recent.0" }) |id| View.selected(view, id);
    View.selected(view, "all.0");
    try std.testing.expectEqual(@as(usize, 1), probe.local);
    try std.testing.expectEqual(@as(usize, 1), probe.saved);
    try std.testing.expectEqual(@as(usize, 1), probe.kvm);
    try std.testing.expectEqual(@as(usize, 0), probe.quick);
    try std.testing.expectEqualDeep(owner, probe.owner.?);
    // Escape closes the native menu and focus returns to where it was.
    cx.handleKeyDown(.escape, .{});
    frames(cx);
    try std.testing.expect(!view.isOpen());
    try std.testing.expect(cx.focus_manager.getFocused() == anchor);
}

test "new session menu: no local terminal, no recent hosts, no KVM plugin (Q5)" {
    const cx = try ui.Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    const scope = try ui.Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    cx.setViewport(860, 480);
    cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    const anchor = try ui.box(cx, .{ .width = .{ .px = 24 }, .height = .{ .px = 24 } }, .{});
    try cx.root.?.appendChild(cx.allocator, anchor);
    var probe: Probe = .{};
    const view = try View.mount(cx, scope, .{ .context = &probe, .quick = Probe.onQuick, .new_profile = Probe.onSaved });
    try cx.root.?.appendChild(cx.allocator, view.root);
    try view.show(anchor);
    frames(cx);
    const items = view.menu.currentItems();
    try std.testing.expect(items[0].disabled);
    try std.testing.expectEqualStrings("本机终端不可用", items[0].disabled_reason.?);
    try std.testing.expectEqualStrings("recent.none", items[1].id);
    try std.testing.expect(items[1].disabled);
    try std.testing.expect(items[2].children[0].disabled);
    for (items) |item| try std.testing.expect(!std.mem.eql(u8, item.id, "new_kvm"));
    View.selected(view, "local");
    try std.testing.expectEqual(@as(usize, 0), probe.local);
    view.hide();
}
