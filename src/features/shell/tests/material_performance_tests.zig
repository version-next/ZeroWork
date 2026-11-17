//! Idle gates: hidden content must not keep the frame loop running.
const std = @import("std");
const ui = @import("ui");
const theme = @import("../../../shared/ui/theme/app_theme.zig");
comptime {
    _ = @import("../../../ai/composer_usage_cache.zig");
}
const Mode = enum { sidebar, ai_results, hidden_ai, file_virtual, floats };

test "idle hidden loading animation stops and resumes with its visible ancestor" {
    const a = std.testing.allocator;
    const cx = try ui.Cx.init(a, std.testing.io);
    defer cx.deinit();
    const scope = try ui.Scope.init(a, null, cx.owner);
    defer scope.dispose();
    cx.setViewport(200, 200);
    cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    const parent = try ui.box(cx, .{ .width = .{ .px = 100 }, .height = .{ .px = 100 } }, .{});
    try cx.root.?.appendChild(a, parent);
    const spinner = try ui.widgets.Spinner(.{}).mount(scope, cx);
    try parent.appendChild(a, spinner);
    for (0..4) |_| _ = tick(cx);
    try std.testing.expect(cx.hasPendingSceneWork());
    spinner.setDisplay(.none);
    for (0..4) |_| _ = tick(cx);
    try std.testing.expect(!cx.hasPendingSceneWork());
    spinner.setDisplay(.flex);
    for (0..4) |_| _ = tick(cx);
    try std.testing.expect(cx.hasPendingSceneWork());
    parent.setDisplay(.none);
    for (0..4) |_| _ = tick(cx);
    try std.testing.expect(!cx.hasPendingSceneWork());
    parent.setDisplay(.flex);
    for (0..4) |_| _ = tick(cx);
    try std.testing.expect(cx.hasPendingSceneWork());
}

fn tick(cx: *ui.Cx) []const ui.DisplayItem {
    cx.frame_count += 1;
    cx.frame_time_ms += 16;
    return cx.render();
}
