//! Application theme layers, consumed by the UI: the provider is default.json + app_overlay.json
//! (see build.zig). App tokens reach Zig (`cx.tokens.tokens.color.zw_island_ground`, typed refs)
//! and .yss (`zw-island-ground`), and the overlay's override reaches built-in components.
const std = @import("std");
const ui = @import("ui");
const probe = @import("layer_probe");

const hex = ui.Color.hex;

test "theme layers: app overlay tokens are Values fields, typed refs and ui.css names" {
    const light = &ui.theme.light;
    try std.testing.expectEqual(hex(0xF4F1EC), light.tokens.color.zw_island_ground);
    try std.testing.expectEqual(hex(0x1B1A19), ui.theme.dark.tokens.color.zw_island_ground);
    try std.testing.expectEqual(hex(0x141312), ui.theme.modes.dim.tokens.color.zw_island_ground);
    try std.testing.expectEqual(hex(0xF4F1EC), ui.theme.resolve(.color, ui.tokenRef(.color, "zw-island-ground"), light));
    try std.testing.expectEqual(@as(f32, 44), ui.theme.resolve(.size, ui.tokenRef(.size, "zw_rail"), light));
    // The override replaced the base accent for every consumer.
    try std.testing.expectEqual(hex(0xA23010), light.tokens.color.accent);
    try std.testing.expectEqual(hex(0xA23010), light.tokens.color.checkbox_checked_bg);
}

test "theme layers: a .yss recipe resolves app overlay tokens" {
    const light = &ui.theme.light;
    const root = probe.Island.Slot(.root).resolve(.{}, light).base;
    try std.testing.expectEqual(hex(0xF4F1EC), root.background.?);
    try std.testing.expectEqual(light.tokens.color.border, root.border_color.?);
    const raised = probe.Island.Slot(.root).resolve(.{ .raised = true }, light).base;
    try std.testing.expectEqual(hex(0xA23010), raised.background.?);
    const rail = probe.Island.Slot(.rail).resolve(.{}, light).base;
    try std.testing.expectEqual(@as(f32, 44), rail.width.?.px);
}

test "theme layers: mounted nodes read app tokens through cx.tokens and follow setTheme" {
    var cx = try ui.Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    cx.setTheme(&ui.theme.light);
    try std.testing.expectEqual(hex(0xF4F1EC), cx.tokens.tokens.color.zw_island_ground);
    const scope = try ui.Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    const island = try ui.view.render(scope, cx, ui.view.box(.{ .style = probe.Island.slot(.root, .{}) }, {}));
    defer cx.freeNode(island);
    try std.testing.expectEqual(hex(0xF4F1EC), island.getBackground());
    // A built-in component picks up the overridden accent through its role token.
    const sw = try ui.widgets.Switch(.{ .checked = true }).mount(scope, cx);
    defer cx.freeNode(sw);
    try std.testing.expectEqual(hex(0xA23010), sw.children.items[0].getBackground());
    cx.setTheme(&ui.theme.dark);
    try std.testing.expectEqual(hex(0x1B1A19), cx.tokens.tokens.color.zw_island_ground);
}
