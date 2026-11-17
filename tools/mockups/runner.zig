//! Mockup 预览入口（基建，仅由集成者维护；子智能体不得修改）。
//!
//! 用途：`zig build mockup -Dmockup=<name>` 构建单页设计稿预览程序
//! `zig-out/bin/mockup-<name>`，窗口尺寸取自该 mockup 文件的
//! `window_size`/`title` 常量。用于子智能体并行开发时做实机像素级比对。
//!
//! 隔离机制：视图文件由 build.zig 按名字装配为 `mockup_view` 模块导入
//! 本文件 —— 每次构建的 import 图里只有被选中的那一个 mockup 文件，
//! 其他 mockup 的语法/编译错误互不可见（Zig 对 @import 是 AstGen 急切
//! 解析，if 链剪枝挡不住语法错误，所以必须在 build 层装配）。

const std = @import("std");
const ui = @import("ui");
const App = @import("zenit_app").App;

const M = @import("mockup_view");

/// A mockup paints the whole window, title bar included, as a static picture. The window uses
/// zenit's window chrome, so what drags it is declared here: the mockup's surface is one drag
/// region (zenit `W.DragRegion`). Interactive nodes inside stay controls, and a mockup that
/// declares its own regions (yix_spike's `windowRegion` header) is read as written, because the
/// nearest declared region wins.
fn mountMock(cx: *ui.Cx, scope: *ui.Scope) anyerror!*ui.Node {
    const view = try M.mount(cx, scope);
    return ui.widgets.DragRegion(.{ .style = .{ .width = .fill, .height = .fill } }, .{view}).mount(scope, cx);
}

pub fn main() !void {
    var io_threaded: std.Io.Threaded = .init(std.heap.c_allocator, .{});
    defer io_threaded.deinit();
    std.log.info("ZeroWork mockup preview: {s} ({d}x{d})", .{ M.title, M.window_size.width, M.window_size.height });
    const app = try App.init(std.heap.c_allocator, .{
        .io = io_threaded.io(),
        .window = .{
            .width = M.window_size.width,
            .height = M.window_size.height,
            .title = M.title,
            .chrome = .{ .custom = .{} },
            .titlebar_height = 40,
        },
    });
    defer app.deinit();
    try app.runWith(mountMock);
}

comptime {
    // -Dtest-mode=true builds carry the e2e launch-guard marker (same bytes as
    // src/platform/build_mode_marker.zig, outside this root's import tree).
    if (@import("build_options").test_mode) @export(&build_mode_marker, .{ .name = "zerowork_build_mode_marker" });
}
const build_mode_marker: [29:0]u8 = "ZEROWORK_BUILD_MODE=test-mode".*;
