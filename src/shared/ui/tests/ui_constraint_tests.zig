//! Shared action recipes exercised with their real labels, icons and states.
const std = @import("std");
const ui = @import("ui");
const shell = @import("../../../features/shell/view/shell_styles.zig");
const theme = @import("../theme/app_theme.zig");
const quick = @import("../../../features/connections/quick_connect/view/quick_connect_styles.zig");
const wizard = @import("../../../features/connections/wizard/view/wizard_styles.zig");
const approval = @import("../../../features/ai/approvals/view/ai_tool_approval_styles.zig");
const asset = @import("../../../features/connections/assets/view/asset_action_styles.zig");
const progress = @import("../../../features/connections/progress/view/connection_progress_styles.zig");
const transfer = @import("../../../features/transfer/view/transfer_styles.zig");
const empty = @import("../../../features/ai/sessions/view/ai_empty_styles.zig");

fn frames(cx: *ui.Cx) void {
    for (0..12) |_| {
        cx.advanceFrameClock();
        _ = cx.render();
    }
}
fn checkText(cx: *ui.Cx, button: *ui.Node, node: *ui.Node, label: []const u8) !void {
    if (node.style.display == .none) return;
    const outer = button.globalRect();
    if (node.getText()) |text| {
        const rect = node.globalRect();
        const measured = cx.text.measureTextWidth(text.content, text.font_size, text.font_weight, false);
        const fits = rect.x >= outer.x - 0.5 and rect.y >= outer.y - 0.5 and rect.x + @max(rect.w, measured) <= outer.x + outer.w + 0.5 and rect.y + text.font_size * text.line_height <= outer.y + outer.h + 0.5;
        if (!fits) std.debug.print("\nAction overflow '{s}': button={any}, text={any}, width={d}, line={d}\n", .{ label, outer, rect, measured, text.font_size * text.line_height });
        try std.testing.expect(fits);
    }
    for (node.children.items) |child| try checkText(cx, button, child, label);
}

test "UI constraints action recipes contain full labels and preserve hit bounds when disabled" {
    const cx = try ui.Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    cx.setViewport(860, 480);
    cx.setTheme(theme.widgetTheme(.dark));
    cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    const cases = .{
        .{ "保存并连接", wizard.button(116, 34, true), false },
        .{ "仅保存", wizard.button(88, 34, false), false },
        .{ "确认移动", asset.button(120, 30, true, false), false },
        .{ "查看现有会话", asset.button(140, 30, false, false), false },
        .{ "重试连接", progress.button(112, 34, true), false },
    };
    var failures: usize = 0;
    inline for (cases) |case| {
        const scope = try ui.Scope.init(std.testing.allocator, null, cx.owner);
        const disabled = try scope.createSignal(bool, false);
        const button = try ui.widgets.Button(.{ .label = @as([]const u8, case[0]), .icon_asset = if (case[2]) ui.icons.terminal else null, .icon_size = @as(f32, 17), .base_style = case[1], .disabled = disabled }).mount(scope, cx);
        try cx.root.?.appendChild(cx.allocator, button);
        frames(cx);
        const initial = button.globalRect();
        checkText(cx, button, button, case[0]) catch {
            failures += 1;
        };
        disabled.set(true);
        frames(cx);
        try std.testing.expectEqual(initial, button.globalRect());
        disabled.set(false);
        frames(cx);
        checkText(cx, button, button, case[0]) catch {
            failures += 1;
        };
        scope.dispose();
    }
    try std.testing.expectEqual(@as(usize, 0), failures);
}

fn find(node: *ui.Node, id: []const u8) ?*ui.Node {
    if (node.meta.ownership.meta.test_id) |value| if (std.mem.eql(u8, value, id)) return node;
    for (node.children.items) |child| if (find(child, id)) |result| return result;
    return null;
}
