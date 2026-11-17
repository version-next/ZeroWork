//! 菜单栏（NSMenu）由快捷键路由生成（一致性审查 #9，shortcuts 包）：菜单项的名称、快捷键都取自
//! `shortcut_router`（`menu_bar` 结构 + 当前 `[keys]`），设置里改了键位后菜单栏随之重建。
//!
//! 选中菜单项（或按下它的快捷键，AppKit 先匹配菜单）时，把这一项当前的组合作为一次按键送进当时的关键窗口，
//! 与直接按键走同一条路径（路由的分发与让位规则一视同仁）。退出、隐藏、最小化这类系统项用 AppKit 的标准动作。
const std = @import("std");
const zenit_app = @import("zenit_app");
const ui = @import("ui");
const MultiWindowApp = zenit_app.MultiWindowApp;
/// zenit 的菜单模型类型（经 `MultiWindowApp.setMenuModel` 的签名取得，不另加模块依赖）。
const system_sdk = struct {
    const MenuModel = @typeInfo(@TypeOf(MultiWindowApp.setMenuModel)).@"fn".param_types[1].?;
    const MenuNode = @typeInfo(@FieldType(MenuModel, "nodes")).pointer.child;
    const MenuRole = @FieldType(MenuNode, "role");
    const events = struct {
        const Modifiers = @FieldType(MenuNode, "modifiers");
    };
};
const router_mod = @import("../features/shell/mod.zig").shortcut_router;
const Map = router_mod.Map;

/// 最多的节点数：5 个菜单 + 每个菜单的项。
const max_nodes = 64;

pub const Sync = struct {
    applied: ?Map = null,

    /// 键位变化（或首次）时重建菜单栏。需要已有窗口（zenit 的菜单模型挂在窗口的 SDK 上）。
    pub fn sync(self: *Sync, windows: *MultiWindowApp, keys: *const Map) void {
        if (self.applied) |current| if (std.meta.eql(current, keys.*)) return;
        var nodes: [max_nodes]system_sdk.MenuNode = undefined;
        const count = build(.{ .keys = keys }, &nodes);
        windows.setMenuModel(.{ .nodes = nodes[0..count] }) catch |err| {
            @import("../platform/applog.zig").warn(.app, "menu bar model: {s}", .{@errorName(err)});
            return;
        };
        // AppKit 换了主菜单：品牌项（关于、检查更新…、显示 › 外观…）补回到新菜单上。
        @import("../platform/app_menu.zig").apply();
        self.applied = keys.*;
    }
};

fn systemRole(command: router_mod.Command) ?system_sdk.MenuRole {
    return switch (command) {
        .quit => .quit,
        .hide => .hide,
        .hide_others => .hide_others,
        .minimize => .minimize,
        else => null,
    };
}

fn modifiers(chord: router_mod.Chord) system_sdk.events.Modifiers {
    return .{ .shift = chord.shift, .ctrl = chord.control, .alt = chord.option, .super = chord.command };
}

/// 生成菜单模型的节点（父在前）。返回节点数。
pub fn build(router: router_mod.Router, nodes: *[max_nodes]system_sdk.MenuNode) usize {
    var count: usize = 0;
    var next_id: u64 = 1;
    for (router_mod.menu_bar) |menu| {
        const menu_id = next_id;
        next_id += 1;
        nodes[count] = .{ .id = menu_id, .kind = .menu, .label = menu.title };
        count += 1;
        for (menu.items) |item| {
            const id = next_id;
            next_id += 1;
            switch (item) {
                .separator => nodes[count] = .{ .id = id, .parent_id = menu_id, .kind = .separator },
                .role => |role| nodes[count] = .{ .id = id, .parent_id = menu_id, .kind = .item, .label = router_mod.menuLabel(item), .role = switch (role) {
                    .about => .about,
                    .show_all => .show_all,
                    .zoom => .zoom,
                    .bring_all_to_front => .bring_all_to_front,
                } },
                .command => |command| {
                    const chord = router_mod.menuChord(router, item);
                    nodes[count] = .{
                        .id = id,
                        .parent_id = menu_id,
                        .kind = .item,
                        .label = router_mod.menuLabel(item),
                        .key_equivalent = if (chord) |value| router_mod.menuKey(value) else "",
                        .modifiers = if (chord) |value| modifiers(value) else .{},
                        .role = systemRole(command) orelse .custom,
                        .command_id = if (systemRole(command) != null) 0 else router_mod.menuCommandId(command),
                    };
                },
            }
            count += 1;
        }
    }
    return count;
}

/// `MultiWindowConfig.on_menu_command`：把菜单项当前的组合作为一次按键送进选中时的关键窗口。
pub fn onMenuCommand(windows: *MultiWindowApp, command: zenit_app.MenuCommand) bool {
    const which = router_mod.fromMenuCommandId(command.command_id) orelse return false;
    const process = @import("process_state.zig").process_windows orelse return true;
    // 没有关键窗口时（例如应用在后台、从菜单栏选中）送到当前活动窗口，再不行送到主窗口。
    const app = windows.window(command.window_id) orelse windows.activeWindow() orelse process.primary orelse return true;
    const runtime = process.runtime_config orelse return true;
    const chord = (router_mod.Router{ .keys = &runtime.value.keys }).chord(which) orelse return true;
    const key = std.meta.stringToEnum(ui.events.KeyCode, @tagName(chord.key)) orelse return true;
    app.cx.handleKeyDown(key, .{ .shift = chord.shift, .ctrl = chord.control, .alt = chord.option, .super = chord.command });
    app.cx.requestRedraw();
    return true;
}
