//! Standalone shared-renderer baseline for the Linux desktop (and optional macOS reuse).
const std = @import("std");
const builtin = @import("builtin");
const App = @import("zenit_app").App;
pub fn main(init: std.process.Init) !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    var allow_software = false;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--allow-software")) allow_software = true else return error.InvalidArgument;
    }
    const family = init.environ_map.get("ZENIT_TEXT_FAMILY") orelse if (builtin.os.tag == .linux) "Sans" else "system";
    const locale = try gpa.allocator().dupeSentinel(u8, init.environ_map.get("ZENIT_TEXT_LOCALE") orelse "zh-CN", 0);
    defer gpa.allocator().free(locale);
    const app = try App.init(gpa.allocator(), .{
        .io = init.io,
        .window = .{ .width = 600, .height = 560, .title = "Zenit Text Baseline" },
        .font = .{ .fallback_families = &.{family}, .locale = locale },
        .allow_software_gpu = allow_software,
        .clear_color = .{ .r = 1, .g = 1, .b = 1, .a = 1 },
    });
    defer app.deinit();
    try app.runWith(@import("text_native_baseline_fixture.zig").mount);
}
