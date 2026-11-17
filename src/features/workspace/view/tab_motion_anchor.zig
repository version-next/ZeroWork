//! Registers the rendered tabs of the top strip as Z12 motion anchors (names: shared/base
//! tab_motion_anchor.zig). A registration lives as long as the strip scope that rendered the tab.
const std = @import("std");
const ui = @import("ui");
const name = @import("../../../shared/base/tab_motion_anchor.zig").name;

const Registration = struct { cx: *ui.Cx, token: u32 };

/// Register `node` (a rendered tab) under the tab's anchor name until `scope` is disposed.
pub fn register(scope: *ui.Scope, cx: *ui.Cx, tab_id: u64, node: *ui.Node) !void {
    var buffer: [48]u8 = undefined;
    const anchor = name(&buffer, tab_id) orelse return error.NoSpaceLeft;
    const token = try cx.motion_anchors.register(cx, anchor, node);
    const entry = scope.allocator.create(Registration) catch |err| {
        cx.motion_anchors.unregister(token);
        return err;
    };
    entry.* = .{ .cx = cx, .token = token };
    scope.adoptResource(@ptrCast(entry), struct {
        fn drop(raw: *anyopaque, allocator: std.mem.Allocator) void {
            const self: *Registration = @ptrCast(@alignCast(raw));
            self.cx.motion_anchors.unregister(self.token);
            allocator.destroy(self);
        }
    }.drop) catch |err| {
        cx.motion_anchors.unregister(token);
        scope.allocator.destroy(entry);
        return err;
    };
}

test "tab motion anchors resolve to the rendered tab until the strip scope is disposed" {
    const cx = try ui.Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    const scope = try ui.Scope.init(std.testing.allocator, null, cx.owner);
    cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    const tab = try ui.box(cx, .{ .width = .{ .px = 120 }, .height = .{ .px = 30 } }, .{});
    try cx.root.?.appendChild(cx.allocator, tab);
    try register(scope, cx, 42, tab);
    try std.testing.expect(cx.motion_anchors.lookup(cx, "workspace.tab.42") == tab);
    scope.dispose();
    try std.testing.expect(cx.motion_anchors.lookup(cx, "workspace.tab.42") == null);
}
