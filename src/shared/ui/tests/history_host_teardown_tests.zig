//! History host lifetime: the host's instances live in child scopes of the host scope. When the window goes, its
//! scope is disposed children first (zenit Scope.disposeNow), so an instance must be torn down by its own scope,
//! not by the host's cleanup afterwards (that used the freed view model: segfault at window close, seen on every
//! normal exit of confirm_undo_native as ReportCrash "fatal 309 report for corpse … zerowork").
const std = @import("std");
const ui = @import("ui");
const HistoryHost = @import("../../../features/history/host/history_host.zig").Host;
const Workspace = @import("../../../features/workspace/view/workspace.zig").Workspace;
const Config = @import("../../../config/config.zig").Config;
const float_layer = @import("../float_card/float_layer.zig");
const a = std.testing.allocator;

test "history host: the window scope going with a card open tears the card down through its own scope" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "hosts.toml", .data = "" });
    const hosts = try tmp.dir.realPathFileAlloc(std.testing.io, "hosts.toml", a);
    defer a.free(hosts);
    const root_dir = try tmp.dir.realPathFileAlloc(std.testing.io, ".", a);
    defer a.free(root_dir);
    const history_dir = try std.fs.path.join(a, &.{ root_dir, "history" });
    defer a.free(history_dir);
    const cx = try ui.Cx.init(a, std.testing.io);
    defer cx.deinit();
    cx.setViewport(1100, 720);
    cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .direction = .column }, .{});
    const scope = try ui.Scope.init(a, null, cx.owner);
    var nodes: [4]*ui.Node = undefined;
    for (&nodes) |*node| {
        node.* = try ui.box(cx, .{ .width = .fill(), .height = .{ .px = 100 } }, .{});
        try cx.root.?.appendChild(a, node.*);
    }
    var config: Config = .{};
    const workspace = try Workspace.init(a, cx, scope, std.testing.io, &config, hosts, nodes[0], nodes[1], nodes[2], nodes[3]);
    const layer = try float_layer.FloatLayer.mount(cx, scope, cx.root.?);
    // The window's scope for the history host (main_window.zig mounts it on the window scope).
    const window_scope = try scope.childScope();
    const host = try HistoryHost.mount(cx, window_scope, history_dir, workspace, layer);
    try host.open(null);
    cx.layout();
    _ = cx.render();
    try std.testing.expectEqual(@as(usize, 1), host.instances.items.len);
    // Window teardown: children first, then the host's cleanup. No use of a freed view model, no leak (the testing
    // allocator reports both), the floating frame and the card root are destroyed with it.
    window_scope.dispose();
    cx.layout();
    _ = cx.render();
    scope.dispose();
}
