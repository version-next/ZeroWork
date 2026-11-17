//! The per-tab floating AI launcher (PL4c 4c-2): an idle launcher leaves the retained scene clean;
//! the running state animates (breathing), so it keeps scheduling frames.
const std = @import("std");
const ui = @import("ui");
const V = @import("../view/ai_launcher_view.zig");
const model = @import("../model/ai_launcher.zig");

fn tick(cx: *ui.Cx) void {
    cx.frame_count += 1;
    cx.frame_time_ms += 16;
    _ = cx.render();
}

test "idle AI launcher leaves the retained scene clean; running keeps animating" {
    const a = std.testing.allocator;
    const cx = try ui.Cx.init(a, std.testing.io);
    defer cx.deinit();
    const scope = try ui.Scope.init(a, null, cx.owner);
    defer scope.dispose();
    cx.setViewport(800, 600);
    cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    const Probe = struct {
        fn open(_: *@This()) void {}
        fn drag(_: *@This(), _: V.ButtonDrag) void {}
    };
    var probe: Probe = .{};
    const entry = try V.View.mount(cx, scope, cx.on(Probe, &probe, Probe.open), cx.on(Probe, &probe, Probe.drag));
    try cx.root.?.appendChild(a, entry.ring);
    try cx.root.?.appendChild(a, entry.root);
    const rect: model.Rect = .{ .x = 600, .y = 500, .w = 48, .h = 48 };
    for (0..32) |_| {
        entry.update(rect, .idle, false, false);
        tick(cx);
    }
    try std.testing.expect(!cx.hasPendingSceneWork());
    entry.update(rect, .idle, false, false);
    try std.testing.expect(!cx.hasPendingSceneWork());
    entry.update(rect, .working, false, false);
    try std.testing.expect(cx.hasPendingSceneWork());
    try std.testing.expectEqual(@as(f32, 48), entry.x.peek() + 48 - 600);
}
