//! 菜单唯一挂载入口（`view/app_menu.zig`，menus 包）的组件测试，以终端右键菜单（design-r3 B1）为例。
//! 证据：原生 `W.Menu` 在按下处弹出（不在挂载点）、跟随新的按下点；行是原生 `MenuItem`，带 `terminal.menu.<动作>`
//! test_id，禁用项不可选并写原因；打开时焦点进菜单、关闭后回到终端；点选只把动作 id 交回宿主，Esc 关闭不选任何项。
//! 项的顺序与可用性由 `workspace/model/context_menus.zig` 的单测覆盖，排列规则由 `model/menu_spec.zig` 覆盖；
//! 宿主 `MenuHost` 拉起的完整链路由 `e2e/terminal_right_click_native.ts` 与 `e2e/menu_contract_native.ts` 验证。
const std = @import("std");
const ui = @import("ui");
const kit = @import("../../../shared/testing/ui_kit.zig");
const shell = @import("../../shell/mod.zig");
const app_menu = shell.app_menu;
const shortcut_router = shell.shortcut_router;
const menus = @import("../model/context_menus.zig");

const Picks = struct {
    buf: [32]u8 = undefined,
    len: usize = 0,
    closes: usize = 0,
    fn select(raw: *anyopaque, id: []const u8) void {
        const self: *Picks = @ptrCast(@alignCast(raw));
        @memcpy(self.buf[0..id.len], id);
        self.len = id.len;
    }
    fn closed(raw: *anyopaque) void {
        const self: *Picks = @ptrCast(@alignCast(raw));
        self.closes += 1;
    }
    fn picked(self: *const Picks) []const u8 {
        return self.buf[0..self.len];
    }
};

fn terminalBox(env: *kit.Headless) !*ui.Node {
    const terminal = try ui.box(env.cx, .{ .width = .fill(), .height = .fill() }, .{});
    terminal.behavior.interaction.focusable = true;
    try env.mount(terminal);
    return terminal;
}

fn focusedInside(cx: *ui.Cx, panel: *ui.Node) bool {
    const focused = cx.focus_manager.getFocused() orelse return false;
    return focused == panel or focused.isDescendantOf(panel);
}

test "app menu (terminal right click) opens the native menu at the press point and returns focus after a pick" {
    const a = std.testing.allocator;
    var env = try kit.headless(a, .{ .width = 1000, .height = 700 });
    defer env.deinit();
    const terminal = try terminalBox(&env);
    var picks: Picks = .{};
    const menu = try app_menu.AppMenu.mountContext(env.cx, env.scope, terminal, .{ .panel_test_id = "terminal.menu" }, .{ .context = &picks, .select = Picks.select, .closed = Picks.closed });
    const defaults: shortcut_router.Map = .{};
    const router: shortcut_router.Router = .{ .keys = &defaults };
    var entries: menus.Entries = .{};
    env.frames(4);
    env.cx.focus_manager.setFocus(terminal);
    menu.show(menus.rightClickEntries(.{}, &entries), router, .{ .x = 320, .y = 240, .w = 0, .h = 0 });
    env.frames(30);
    const panel = try env.expect("terminal.menu");
    try std.testing.expectApproxEqAbs(@as(f32, 320), panel.globalRect().x, 0.5);
    try std.testing.expect(panel.globalRect().y >= 240 and panel.globalRect().y <= 248);
    try std.testing.expect(focusedInside(env.cx, panel));
    const paste = try env.expect("terminal.menu.paste");
    const copy = try env.expect("terminal.menu.copy");
    try std.testing.expect(copy.behavior.interaction.a11y.?.disabled);
    try std.testing.expectEqualStrings("未选中内容", copy.behavior.interaction.a11y.?.description.?);
    try std.testing.expectEqualStrings("MenuItem", copy.meta.ownership.meta.component_name.?);
    // The shortcut column is the router's text (a11y description of an enabled row).
    try std.testing.expectEqualStrings(router.hint(.paste), paste.behavior.interaction.a11y.?.description.?);
    try std.testing.expect(paste.globalRect().y < copy.globalRect().y);
    const r = paste.globalRect();
    env.cx.handleMouseDownEx(r.x + r.w / 2, r.y + r.h / 2, .left, .{});
    env.cx.handleMouseUpEx(r.x + r.w / 2, r.y + r.h / 2, .left, .{});
    env.frames(30);
    try std.testing.expectEqualStrings("paste", picks.picked());
    try std.testing.expect(!menu.isOpen());
    try std.testing.expect(picks.closes >= 1);
    try std.testing.expectEqual(@as(?*ui.Node, terminal), env.cx.focus_manager.getFocused());

    // Esc 关闭，不选任何项；再次打开跟随新的按下点。
    picks.len = 0;
    menu.show(menus.rightClickEntries(.{}, &entries), router, .{ .x = 500, .y = 300, .w = 0, .h = 0 });
    env.frames(30);
    try std.testing.expectApproxEqAbs(@as(f32, 500), (try env.expect("terminal.menu")).globalRect().x, 0.5);
    // Keyboard: Down moves the native highlight over the disabled row; Escape closes without a pick.
    env.cx.handleKeyDown(.down, .{});
    env.cx.handleKeyDown(.escape, .{});
    env.frames(30);
    try std.testing.expect(!menu.isOpen());
    try std.testing.expectEqual(@as(usize, 0), picks.len);
    try std.testing.expectEqual(@as(?*ui.Node, terminal), env.cx.focus_manager.getFocused());
}
