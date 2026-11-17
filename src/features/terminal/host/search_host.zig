//! 侧栏搜索框宿主 SearchHost（P2 自 src/main.zig 原样拆出）。

const std = @import("std");
const ws = @import("../../workspace/view/workspace.zig");

/// Sidebar search box host: routes Input on_change into Workspace.setSearch,
/// which live-filters the host list (previously a static placeholder).
pub const SearchHost = struct {
    allocator: std.mem.Allocator,
    workspace: *ws.Workspace,

    pub fn onChange(self: *SearchHost, text: []const u8) void {
        self.workspace.setSearch(text);
    }

    pub fn cleanup(self: *SearchHost) void {
        self.allocator.destroy(self);
    }
};

pub fn caseInsensitiveContains(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (haystack.len < needle.len) return false;
    for (haystack[0 .. haystack.len - needle.len + 1], 0..) |_, index| {
        var matches = true;
        for (needle, 0..) |n, offset| {
            if (std.ascii.toLower(haystack[index + offset]) != std.ascii.toLower(n)) {
                matches = false;
                break;
            }
        }
        if (matches) return true;
    }
    return false;
}

