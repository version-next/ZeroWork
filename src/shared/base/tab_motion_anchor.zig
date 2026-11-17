//! Z12 `motionAnchor` names of the top tab strip's tabs (PLUGIN_ARCH_PLAN 2.5.7). The workspace
//! registers each rendered tab under its name; a floating card owned by the tab (the AI panel)
//! folds into it when another tab becomes current and unfolds from it when the tab comes back.
const std = @import("std");

pub const prefix = "workspace.tab.";

/// `workspace.tab.<tab id>`; null only when `buffer` is too small (36 bytes always suffice).
pub fn name(buffer: []u8, tab_id: u64) ?[]const u8 {
    return std.fmt.bufPrint(buffer, prefix ++ "{d}", .{tab_id}) catch null;
}

test "tab motion anchor names carry the tab id" {
    var buffer: [36]u8 = undefined;
    try std.testing.expectEqualStrings("workspace.tab.42", name(&buffer, 42).?);
    try std.testing.expectEqualStrings("workspace.tab.18446744073709551615", name(&buffer, std.math.maxInt(u64)).?);
    var tiny: [4]u8 = undefined;
    try std.testing.expect(name(&tiny, 42) == null);
}
