const std = @import("std");
const keys = @import("../../../config/keybindings.zig");
test "keybinding roundtrip conflicts and remote reservation" {
    var map: keys.Map = .{};
    try map.set(.search, .{ .key = .e });
    try std.testing.expectError(error.Conflict, map.set(.ai, .{ .key = .e }));
    try std.testing.expectError(error.RemoteKeyReserved, map.set(.search, .{ .key = .tab }));
    try std.testing.expectError(error.RemoteKeyReserved, map.set(.search, .{ .key = .l, .command = false, .control = true }));
    var buffer: [4096]u8 = undefined;
    const next = try keys.Map.parse(try map.format(&buffer));
    try std.testing.expectEqualDeep(map, next);
    map.reset();
    try std.testing.expectEqual(keys.Action.search, map.match(.f, .{ .super = true }).?);
}
test "nine tab range and Control passthrough" {
    const map: keys.Map = .{};
    const text = @import("../../shell/mod.zig").shortcut_router.text;
    try std.testing.expectEqualStrings("⌘1", text(map.get(.tab_1)));
    try std.testing.expectEqualStrings("⌘9", text(map.get(.tab_9)));
    try std.testing.expect(map.match(.tab, .{ .ctrl = true }) == null);
    try std.testing.expect(map.match(.c, .{ .ctrl = true }) == null);
}
