//! Filled text actions keep live theme paint; icon tools remain chromeless.
const std = @import("std");
const ui = @import("ui");
const theme = @import("../theme/app_theme.zig");
const Notice = @import("../../../features/workspace/view/remote_session_notice.zig");
const Copy = @import("../components/copy_button/copy_button.zig").Button;
const Style = ui.StyleOverride;

fn frames(cx: *ui.Cx) void {
    for (0..16) |_| {
        cx.advanceFrameClock();
        cx.layout();
        _ = cx.render();
    }
}
fn label(node: *ui.Node) ?*ui.Node {
    if (node.getText()) |text| if (text.content.len != 0) return node;
    for (node.children.items) |child| if (label(child)) |found| return found;
    return null;
}
const Sink = struct {
    calls: usize = 0,
    fn click(self: *@This()) void {
        self.calls += 1;
    }
    fn notice(raw: *anyopaque, _: u64) void {
        const self: *@This() = @ptrCast(@alignCast(raw));
        self.calls += 1;
    }
};

test "button policy retained text actions follow every builtin palette and interaction state" {
    const previous = theme.currentName();
    const parameters = theme.materialParameters();
    defer {
        theme.select(previous);
        _ = theme.setMaterialParameters(parameters.transparency, parameters.blur);
    }
    theme.select(.dark);
    _ = theme.setMaterialParameters(0, 0);
    const cx = try ui.Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    const scope = try ui.Scope.init(cx.allocator, null, cx.owner);
    defer scope.dispose();
    const publication = try cx.bindState(@import("../theme/theme_publication.zig").ThemePublication, .{});
    publication.publish(cx, theme.widgetTheme(theme.currentName()));
    try cx.setTestFrameStep(16);
    cx.setViewport(900, 600);
    cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .direction = .column, .gap = 8 }, .{});
    var sink: Sink = .{};
    const notice = try Notice.View.mount(cx, scope, cx.root.?, .{ .context = &sink, .session_id = 1, .reconnect = Sink.notice, .close = Sink.notice });
    notice.update(.{ .state = .exited, .exit_code = 0 });
    const close_id = notice.close.id;
    const execution = try ui.widgets.Button(.{ .label = "接管输入", .variant = .secondary, .base_style = try theme.paintSignal(Style, cx, scope, @import("../../../features/ai/cards/view/ai_execution_result_styles.zig").action, .{}) }).mount(scope, cx);
    try cx.root.?.appendChild(cx.allocator, execution);
    const transfer = try ui.widgets.Button(.{ .label = "取消传输", .variant = .secondary, .size = .sm }).mount(scope, cx);
    try cx.root.?.appendChild(cx.allocator, transfer);
    const notification = try ui.widgets.Button(.{ .label = "查看结果", .variant = .secondary, .base_style = @import("../../../features/notifications/view/notification_history_styles.zig").action() }).mount(scope, cx);
    try cx.root.?.appendChild(cx.allocator, notification);
    const disabled = try scope.createSignal(bool, true);
    const blocked = try ui.widgets.Button(.{ .label = "暂不可操作", .variant = .secondary, .disabled = disabled, .on_click = cx.on(Sink, &sink, Sink.click) }).mount(scope, cx);
    try cx.root.?.appendChild(cx.allocator, blocked);
    const tool = try ui.widgets.Button(.{ .icon_only = true, .icon_asset = ui.icons.copy, .variant = .ghost }).mount(scope, cx);
    try cx.root.?.appendChild(cx.allocator, tool);
    var registry = try @import("../../../config/theme_registry.zig").Registry.init(cx.allocator);
    defer registry.deinit();
    for (registry.records.items) |record| {
        errdefer std.debug.print("\nbutton policy palette: {s}\n", .{record.theme.name});
        theme.selectTokens(record.ui_tokens);
        publication.publish(cx, theme.widgetTheme(theme.currentName()));
        notice.update(.{ .state = .exited, .exit_code = 0 });
        cx.clearFocus();
        cx.handleMouseMove(899, 599);
        frames(cx);
        const colors = cx.tokens.tokens.color;
        try std.testing.expectEqual(close_id, notice.close.id);
        for ([_]*ui.Node{ notice.close, transfer, notification }) |node| {
            try std.testing.expectEqual(colors.button_secondary_bg, node.getBackground());
            try std.testing.expectEqual(colors.button_secondary_fg, label(node).?.resolveTextProps().?.color);
        }
        // Pencil g0gO7 Actions (itWiC): execution actions are unfilled accent links;
        // the ink keeps the 4.5:1 readability contract on the execution card.
        try std.testing.expectEqual(ui.Color.TRANSPARENT, execution.getBackground());
        try std.testing.expectEqual(@import("../../../features/ai/cards/view/ai_execution_result_styles.zig").actionInk(), label(execution).?.resolveTextProps().?.color);
        try std.testing.expectEqual(ui.Color.TRANSPARENT, tool.getBackground());
        try std.testing.expect(blocked.behavior.interaction.a11y.?.disabled);
        // New zenit disables through the ControlShell tone (disabled-bg + fg-disabled)
        // rather than fading the whole button.
        try std.testing.expectEqual(colors.disabled_bg, blocked.getBackground());
        try std.testing.expectEqual(colors.fg_disabled, label(blocked).?.resolveTextProps().?.color);
        const disabled_rect = blocked.globalRect();
        cx.handleMouseDown(disabled_rect.x + 8, disabled_rect.y + 8, .{});
        cx.handleMouseUp(disabled_rect.x + 8, disabled_rect.y + 8);
        try std.testing.expectEqual(@as(usize, 0), sink.calls);
        const rect = notice.close.globalRect();
        cx.handleMouseMove(rect.x + rect.w / 2, rect.y + rect.h / 2);
        frames(cx);
        try std.testing.expectEqual(colors.bg_hover, notice.close.getBackground());
        cx.pressed_node = notice.close;
        cx.notifyPressWatchers();
        frames(cx);
        // zenit ControlShell secondary tone: `:active { background: button-pressed-bg }`.
        try std.testing.expectEqual(colors.button_pressed_bg, notice.close.getBackground());
        cx.pressed_node = null;
        cx.notifyPressWatchers();
        cx.handleMouseMove(899, 599);
        frames(cx);
        // Focus is zenit's native presentation: the fill stays at rest.
        cx.setFocus(notice.close);
        frames(cx);
        try std.testing.expectEqual(colors.button_secondary_bg, notice.close.getBackground());
        for ([_]ui.Color{ colors.button_secondary_bg, colors.bg_hover, colors.button_pressed_bg }) |background| {
            const painted = theme.patchPaint(background, theme.current().overlay.withAlpha(255));
            try std.testing.expect(@import("../theme/theme_states.zig").contrast(painted, colors.button_secondary_fg) >= 4.5);
        }
    }
}
