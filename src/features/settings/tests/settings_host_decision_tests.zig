//! SettingsHost 决策弹窗的主题重绘测试（P2 自 src/main.zig 原样拆出；原先位于可执行文件根 main.zig，不被任何测试聚合根收集，搬迁后保持不变）。

const std = @import("std");
const ui = @import("ui");
const SettingsController = @import("../model/settings_controller.zig").Controller;
const app_theme = @import("../../../shared/ui/theme/app_theme.zig");
const SettingsHost = @import("../host/settings_host.zig").SettingsHost;

test "settings retained decision repaints Dark creation after close Light reopen without replacing draft or modal" {
    const before = app_theme.currentName();
    defer app_theme.select(before);
    app_theme.select(.dark);
    const cx = try ui.Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    cx.setViewport(1440, 900);
    const scope = try ui.Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    const panel = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    cx.root = panel;
    var controller = try SettingsController.init(std.testing.allocator, .{});
    defer controller.deinit();
    try controller.editKey("ui", "font_size", .{ .unsigned = 18 });
    var host: SettingsHost = .{ .allocator = std.testing.allocator, .cx = cx, .scope = scope, .controller = controller, .runtime = undefined, .io = std.testing.io, .panel = panel, .status = panel };
    try host.showDecision(.reset);
    cx.frame_count += 1;
    cx.frame_time_ms += 16;
    _ = cx.render();
    const dialog = host.decision_dialog.?;
    const title = host.decision_title_node.?;
    const draft = host.controller.draft_id;
    host.cancelDecision();
    cx.frame_count += 1;
    cx.frame_time_ms += 16;
    _ = cx.render();
    app_theme.select(.light);
    cx.setTheme(app_theme.widgetTheme(.light));
    try host.showDecision(.close);
    cx.frame_count += 1;
    cx.frame_time_ms += 16;
    _ = cx.render();
    try std.testing.expectEqual(dialog, host.decision_dialog.?);
    try std.testing.expectEqual(title, host.decision_title_node.?);
    try std.testing.expectEqual(app_theme.current().overlay, dialog.getBackground());
    try std.testing.expectEqual(app_theme.current().fg_1, title.getText().?.color);
    try std.testing.expectEqual(app_theme.current().fg_2, host.decision_message_node.?.getText().?.color);
    try std.testing.expectEqual(app_theme.current().fg_2, host.decision_notice.?.getText().?.color);
    try std.testing.expectEqual(draft, host.controller.draft_id);
    try std.testing.expectEqual(@as(u8, 18), host.controller.model.value.ui.font_size);
    try std.testing.expect(host.controller.model.dirty);
    host.cancelDecision();
    try std.testing.expect(!host.decision_open.?.get());
}
