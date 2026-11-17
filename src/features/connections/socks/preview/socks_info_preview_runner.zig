//! Isolated visual fixture: actual production SOCKS view, no network or service evidence.
const std = @import("std");
const ui = @import("ui");
const App = @import("zenit_app").App;
const socks = @import("../view/socks_info_view.zig");
const theme = @import("../../../../shared/ui/theme/app_theme.zig");
const fixture_window = @import("../../../../shared/ui/window/fixture_window.zig");
fn ignore(_: *anyopaque, _: socks.Action) void {}
var sink: u8 = 0;
var selected_theme: theme.Name = .dark;
fn mount(cx: *ui.Cx, scope: *ui.Scope) !*ui.Node {
    const name = selected_theme;
    theme.select(name);
    _ = theme.setMaterialVisible(false);
    cx.setTheme(theme.widgetTheme(name));
    const root = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .background = theme.current().surface_1 }, .{});
    const trigger = try ui.box(cx, .{ .position = .absolute, .width = .{ .px = 28 }, .height = .{ .px = 28 }, .inset = .{ .right = .{ .px = 72 }, .bottom = .{ .px = 14 } } }, .{});
    try trigger.appendChild(cx.allocator, try ui.iconTint(cx, ui.icons.get("plug-zap").?, theme.current().fg_2, .{ .width = .{ .px = 18 }, .height = .{ .px = 18 } }));
    try root.appendChild(cx.allocator, trigger);
    const view = try socks.mount(cx, scope, .{ .context = &sink, .action = ignore });
    if (!view.portaled) try root.appendChild(cx.allocator, view.wrapper);
    try view.update(.{ .state = .running, .host = "Bastion-01", .exit = "Bastion-01", .session_id = 201, .port = 1080, .connections = 2, .downloaded = 48444211, .uploaded = 8493466 });
    view.showNode(trigger);
    return fixture_window.mount(cx, scope, root, .{ .background = theme.current().surface_1 });
}
pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();
    while (args.next()) |arg| {
        if (std.mem.startsWith(u8, arg, "--theme=")) selected_theme = std.meta.stringToEnum(theme.Name, arg[8..]) orelse return error.InvalidTheme else return error.InvalidOption;
    }
    const app = try App.init(std.heap.c_allocator, .{ .io = init.io, .window = .{ .width = 720, .height = 440, .title = "ZeroWork · SOCKS 信息卡预览", .chrome = fixture_window.chrome, .titlebar_height = fixture_window.title_height } });
    defer app.deinit();
    try app.runWith(mount);
}
