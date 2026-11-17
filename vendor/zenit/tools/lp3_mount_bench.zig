//! LP3 setup/view baseline: 100 Yix Checkbox instances, no GPU or native window.
const std = @import("std");
const ui = @import("ui");
pub fn main(init: std.process.Init) !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const a = gpa.allocator();
    const cx = try ui.Cx.init(a, init.io);
    defer cx.deinit();
    var samples: [51]u64 = undefined;
    for (0..samples.len + 5) |sample| {
        const scope = try ui.Scope.init(a, null, cx.owner);
        const started = std.Io.Clock.awake.now(init.io).nanoseconds;
        const root = try ui.view.render(scope, cx, ui.view.col(.{}, .{}));
        for (0..100) |_| {
            const child = try ui.widgets.Checkbox(.{ .label = "checkbox" }).mount(scope, cx);
            try root.appendChild(a, child);
        }
        const elapsed: u64 = @intCast(std.Io.Clock.awake.now(init.io).nanoseconds - started);
        if (sample >= 5) samples[sample - 5] = elapsed;
        scope.dispose();
        cx.freeNode(root);
    }
    const chronological = samples;
    std.mem.sort(u64, &samples, {}, std.sort.asc(u64));
    const json = try std.json.Stringify.valueAlloc(a, .{ .samples = samples.len, .warmups = 5, .checkboxes = 100, .samples_ns = chronological, .p50_ns = samples[25], .p95_ns = samples[48], .allocator = "DebugAllocator", .renderer = "none" }, .{});
    defer a.free(json);
    try std.Io.File.stdout().writeStreamingAll(init.io, json);
    try std.Io.File.stdout().writeStreamingAll(init.io, "\n");
}
