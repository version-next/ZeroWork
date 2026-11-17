const std = @import("std");
const ui = @import("ui");
const View = @import("../view/startup_view.zig").View;

const Clicks = struct {
    count: usize = 0,
    fn hit(self: *Clicks) void {
        self.count += 1;
    }
};

test "startup overlay passes input to the ready workspace once it fades" {
    const a = std.testing.allocator;
    const cx = try ui.Cx.init(a, std.testing.io);
    defer cx.deinit();
    cx.setViewport(800, 600);
    const root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    cx.root = root;
    const scope = try ui.Scope.init(a, null, cx.owner);
    defer scope.dispose();
    var clicks: Clicks = .{};
    const button = try ui.widgets.Button(.{ .label = "设置", .on_click = cx.on(Clicks, &clicks, Clicks.hit) }).mount(scope, cx);
    try root.appendChild(a, button);
    const view = try View.mount(cx, scope);
    try root.appendChild(a, view.root);
    cx.layout();
    _ = cx.render();
    const rect = button.globalRect();
    const click = struct {
        fn at(c: *ui.Cx, r: anytype) void {
            c.handleClick(r.x + r.w / 2, r.y + r.h / 2);
            c.handleMouseUpEx(r.x + r.w / 2, r.y + r.h / 2, .left, .{});
            _ = c.render();
        }
    }.at;

    // Still preparing (opaque cover over a workspace that is not shown yet): input stays out.
    view.update(false);
    cx.layout();
    _ = cx.render();
    click(cx, rect);
    try std.testing.expectEqual(@as(usize, 0), clicks.count);

    // Ready: the cover fades over the visible workspace and no longer takes the first click.
    const now: u64 = @intCast(@divTrunc(@import("../../../platform/realtime.zig").monotonicNs(), std.time.ns_per_ms));
    view.transition.started_ms = now -| 100;
    view.update(true);
    try std.testing.expect(view.transition.fade_started_ms != null and !view.transition.finished);
    try std.testing.expect(view.root.style.display != .none);
    cx.layout();
    _ = cx.render();
    click(cx, rect);
    try std.testing.expectEqual(@as(usize, 1), clicks.count);
}
