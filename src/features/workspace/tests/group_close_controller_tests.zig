test {
    _ = @import("../../../host/group_close_controller.zig");
}

const std = @import("std");
const ui = @import("ui");

fn findCloseAction(node: *ui.Node) ?*ui.Node {
    if (node.meta.ownership.meta.test_id) |id| if (std.mem.eql(u8, id, "groups.close.accept")) return node;
    for (node.children.items) |child| if (findCloseAction(child)) |found| return found;
    return null;
}

noinline fn overwriteStack() void {
    var bytes: [8192]u8 = undefined;
    @memset(&bytes, 0);
    std.mem.doNotOptimizeAway(&bytes);
}

test "group close action owns its dynamic accessibility label after mount returns" {
    const a = std.testing.allocator;
    const cx = try ui.Cx.init(a, std.testing.io);
    defer cx.deinit();
    cx.setTheme(@import("../../../shared/ui/theme/app_theme.zig").widgetTheme(.dark));
    cx.setViewport(1000, 700);
    const scope = try ui.Scope.init(a, null, cx.owner);
    defer scope.dispose();
    const root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    cx.root = root;
    var plan: @import("../../../host/group_close_controller.zig").Plan = .{};
    defer plan.deinit(a);
    try plan.append(a, .{ .id = 1, .generation = 1 });
    try plan.append(a, .{ .id = 2, .generation = 1 });
    const callback = struct {
        fn noop(_: *anyopaque) void {}
    };
    const open = try scope.createSignal(bool, true);
    const dialog = try @import("../view/group_close_view.zig").mount(cx, scope, .{
        .open = .{ .bound = open },
        .group_name = "test-group",
        .plan = &plan,
        .partial = false,
        .approve = .{ .context = &plan, .callback = callback.noop },
    });
    if (!dialog.modal.portaled) try root.appendChild(a, dialog.modal.overlay);
    const action = findCloseAction(dialog.modal.dialog).?;
    overwriteStack();
    cx.layout();
    // 动词 + 对象 (the label is owned by the dialog's scope, not the caller's stack buffer).
    try std.testing.expectEqualStrings("关闭 2 个会话", action.behavior.interaction.a11y.?.label.?);
    try std.testing.expectEqualStrings("ConfirmDialog", dialog.modal.dialog.meta.ownership.meta.component_name.?);
    try std.testing.expectEqualStrings("groups.close.confirm", dialog.modal.dialog.meta.ownership.meta.test_id.?);
    const theme = @import("../../../shared/ui/theme/app_theme.zig");
    const previous = theme.currentName();
    defer theme.select(previous);
    for (@import("../../../config/theme_presets.zig").ids) |id| {
        theme.selectTokens(@import("../../../config/theme_registry.zig").builtinTokens(id));
        try @import("../../../shared/testing/ui_theme_test_support.zig").publish(cx, scope);
        try cx.setTestFrameStep(16);
        for (0..24) |_| {
            cx.advanceFrameClock();
            _ = cx.render();
        }
        // zenit Modal default panel; native danger Button: zenit's default danger role.
        try std.testing.expectEqual(cx.tokens.tokens.color.bg_primary, dialog.modal.dialog.getBackground());
        try std.testing.expectEqual(cx.tokens.tokens.color.button_danger_bg, action.getBackground());
        try std.testing.expectEqualStrings("关闭 2 个会话", action.behavior.interaction.a11y.?.label.?);
        try std.testing.expectEqual(@as(usize, 2), plan.members.items.len);
    }
}
