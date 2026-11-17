const std = @import("std");
const ui = @import("ui");
const theme = @import("../theme/app_theme.zig");

fn frames(cx: *ui.Cx, count: usize) void {
    for (0..count) |_| {
        cx.advanceFrameClock();
        cx.layout();
        _ = cx.render();
    }
}

// Focus presentation is zenit's native default (the ZeroWork filled focus
// extension was removed): keyboard focus draws zenit's focus ring outline in
// the `focus_ring` role, the control's own fill never changes for focus, and
// pointer focus shows nothing extra.
test "buttons keep zenit's native keyboard focus ring and restore their resting fill on blur in every theme" {
    for ([_]theme.Name{ .dark, .light, .sauber }) |name| {
        inline for (.{ .ghost, .secondary, .primary, .danger }) |variant| {
            const cx = try ui.Cx.init(std.testing.allocator, std.testing.io);
            defer cx.deinit();
            cx.setTheme(theme.widgetTheme(name));
            cx.setViewport(480, 160);
            const scope = try ui.Scope.init(cx.allocator, null, cx.owner);
            defer scope.dispose();
            cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
            const button = try ui.widgets.Button(.{ .label = "当前会话传输", .variant = variant }).mount(scope, cx);
            try cx.root.?.appendChild(cx.allocator, button);
            try cx.setTestFrameStep(16);
            frames(cx, 20);
            const resting = button.getBackground();
            try std.testing.expectEqual(cx.tokens.tokens.color.focus_ring, theme.zenitDefaults(name).tokens.color.focus_ring);
            cx.handleKeyDown(.tab, .{});
            frames(cx, 20);
            try std.testing.expect(cx.isFocused(button));
            try std.testing.expectEqual(resting, button.getBackground());
            const ring = button.style.outline() orelse return error.MissingFocusRing;
            const expected = cx.tokens.tokens.color.focus_ring;
            try std.testing.expect(ui.Color.eql(expected.withAlpha(255), ring.color.withAlpha(255)));
            try std.testing.expect(@as(u16, ring.color.a) + 2 >= expected.a and ring.width > 0);
            cx.clearFocus();
            frames(cx, 20);
            try std.testing.expectEqual(resting, button.getBackground());
        }
    }
}

test "a clicked button returns to its resting fill once the pointer leaves and focus moves on" {
    // Regression: the removed focus extension restored the fill it saw when focus
    // arrived (the hover color), so a pressed button stayed hovered after blur.
    for ([_]theme.Name{ .dark, .light, .sauber }) |name| {
        inline for (.{ .ghost, .secondary, .primary }) |variant| {
            const cx = try ui.Cx.init(std.testing.allocator, std.testing.io);
            defer cx.deinit();
            cx.setTheme(theme.widgetTheme(name));
            cx.setViewport(480, 160);
            const scope = try ui.Scope.init(cx.allocator, null, cx.owner);
            defer scope.dispose();
            cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
            const button = try ui.widgets.Button(.{ .label = "保存", .variant = variant }).mount(scope, cx);
            try cx.root.?.appendChild(cx.allocator, button);
            try cx.setTestFrameStep(16);
            frames(cx, 20);
            const resting = button.getBackground();
            const rect = button.globalRect();
            cx.handleMouseMove(rect.x + rect.w / 2, rect.y + rect.h / 2);
            frames(cx, 20);
            cx.handleMouseDown(rect.x + rect.w / 2, rect.y + rect.h / 2, .{});
            cx.handleMouseUp(rect.x + rect.w / 2, rect.y + rect.h / 2);
            frames(cx, 5);
            cx.handleMouseMove(470, 150);
            frames(cx, 20);
            try std.testing.expectEqual(resting, button.getBackground());
            cx.clearFocus();
            frames(cx, 20);
            try std.testing.expectEqual(resting, button.getBackground());
            try std.testing.expect(button.style.outline() == null);
        }
    }
}

// Island B v3 field contract: Input / Textarea frames are zenit's ControlShell
// `.field` tone (vendor/zenit src/ui/components/control_shell/styles.yss): a 1px
// `input_border` hairline at rest, `accent` while focused, `danger` while invalid
// (announced through a11y `invalid`, the field is no longer flooded with a danger
// fill) and `border` over `disabled_bg` while disabled. Fields own their focus frame
// (ControlShell), zenit's native default.
fn settle(cx: *ui.Cx) void {
    // ControlShell eases background/border colors (150ms); run past the transition.
    for (0..20) |_| {
        cx.advanceFrameClock();
        cx.layout();
        _ = cx.render();
    }
}
fn expectFrame(node: *ui.Node, color: ui.Color) !void {
    try std.testing.expectEqual(@as(f32, 1), node.style.border.width);
    try std.testing.expectEqual(color, node.style.border.color);
    try std.testing.expect(node.style.outline() == null);
}

test "input field frame follows ControlShell through focus typing and invalid state without an outline" {
    for ([_]theme.Name{ .dark, .light, .sauber }) |name| {
        const cx = try ui.Cx.init(std.testing.allocator, std.testing.io);
        defer cx.deinit();
        cx.setTheme(theme.widgetTheme(name));
        try cx.setTestFrameStep(16);
        cx.setViewport(480, 160);
        const scope = try ui.Scope.init(cx.allocator, null, cx.owner);
        defer scope.dispose();
        cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .direction = .column }, .{});
        const result = try ui.widgets.Input(.{ .placeholder = "搜索", .error_msg = "示例错误" }).mountResult(scope, cx);
        try cx.root.?.appendChild(cx.allocator, result.node);
        const valid = try ui.widgets.Input(.{ .placeholder = "主机" }).mountResult(scope, cx);
        try cx.root.?.appendChild(cx.allocator, valid.node);
        settle(cx);
        const c = cx.tokens.tokens.color;
        const state = result.state;
        const container = state.input_container_node.?;
        const resting_background = container.getBackground();
        // Invalid: danger frame and a11y invalid, background stays the field surface.
        try std.testing.expect(container.behavior.interaction.a11y.?.invalid);
        try expectFrame(container, c.danger);
        try std.testing.expectEqual(c.input_bg, resting_background);
        try expectFrame(valid.input_container, c.input_border);
        try std.testing.expect(!valid.input_container.behavior.interaction.a11y.?.invalid);
        // Focus + typing keeps the invalid frame (invalid outranks focus) and fill.
        cx.setFocus(container);
        cx.handleTextInput("value");
        settle(cx);
        try std.testing.expect(state.focused);
        try std.testing.expect(std.mem.indexOf(u8, result.value.?.peek(), "value") != null);
        try expectFrame(container, c.danger);
        try std.testing.expectEqual(resting_background, container.getBackground());
        cx.clearFocus();
        settle(cx);
        try std.testing.expect(!state.focused);
        try expectFrame(container, c.danger);
        try std.testing.expectEqual(resting_background, container.getBackground());
        // A valid field shows the accent focus frame and restores its hairline on blur.
        cx.setFocus(valid.input_container);
        settle(cx);
        try std.testing.expect(valid.state.focused);
        try expectFrame(valid.input_container, c.accent);
        cx.clearFocus();
        settle(cx);
        try expectFrame(valid.input_container, c.input_border);
        try std.testing.expectEqual(c.input_bg, valid.input_container.getBackground());
    }
}

test "grouped input focuses the actual field frame without creating an outline" {
    const cx = try ui.Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    cx.setTheme(theme.widgetTheme(.dark));
    try cx.setTestFrameStep(16);
    cx.setViewport(480, 160);
    const scope = try ui.Scope.init(cx.allocator, null, cx.owner);
    defer scope.dispose();
    cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    const group = try ui.widgets.Group(.{}).mount(scope, cx);
    try cx.root.?.appendChild(cx.allocator, group.container);
    const result = try ui.widgets.Input(.{ .value = "host", .width = 200 }).mountResult(scope, cx);
    try ui.widgets.group.addGroupItem(group.container, cx.allocator, result.node, .first, 8);
    settle(cx);
    const c = cx.tokens.tokens.color;
    try expectFrame(result.input_container, c.input_border);
    cx.setFocus(result.input_container);
    settle(cx);
    try std.testing.expect(cx.focus_manager.getFocused() == result.input_container);
    try expectFrame(result.input_container, c.accent);
    try std.testing.expectEqual(c.input_bg, result.input_container.getBackground());
    // The group wrapper itself draws no second frame.
    try std.testing.expect(result.node.style.border.width == 0 or result.node.style.border.color.a == 0);
    try std.testing.expect(result.node.style.outline() == null);
    cx.clearFocus();
    settle(cx);
    try expectFrame(result.input_container, c.input_border);
}

test "input disable cancels composition shows the disabled field and rejects editing" {
    for ([_]theme.Name{ .dark, .light, .sauber }) |name| {
        const cx = try ui.Cx.init(std.testing.allocator, std.testing.io);
        defer cx.deinit();
        cx.setTheme(theme.widgetTheme(name));
        try cx.setTestFrameStep(16);
        cx.setViewport(480, 160);
        const scope = try ui.Scope.init(cx.allocator, null, cx.owner);
        defer scope.dispose();
        cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
        const disabled = try scope.createSignal(bool, false);
        const result = try ui.widgets.Input(.{ .disabled = disabled, .value = "saved" }).mountResult(scope, cx);
        try cx.root.?.appendChild(cx.allocator, result.node);
        settle(cx);
        const c = cx.tokens.tokens.color;
        cx.setFocus(result.input_container);
        cx.handleImePreedit("候选", 6);
        disabled.set(true);
        settle(cx);
        try std.testing.expect(!result.state.focused);
        try std.testing.expect(!result.state.imeIsComposing());
        try std.testing.expect(cx.focus_manager.getFocused() == null);
        try std.testing.expect(result.input_container.behavior.interaction.a11y.?.disabled);
        try expectFrame(result.input_container, c.border);
        try std.testing.expectEqual(c.disabled_bg, result.input_container.getBackground());
        cx.handleTextInput("blocked");
        try std.testing.expectEqualStrings("saved", result.value.?.peek());
        disabled.set(false);
        settle(cx);
        try expectFrame(result.input_container, c.input_border);
        try std.testing.expectEqual(c.input_bg, result.input_container.getBackground());
        cx.setFocus(result.input_container);
        cx.handleTextInput("x");
        try std.testing.expect(std.mem.indexOf(u8, result.value.?.peek(), "x") != null);
        cx.clearFocus();
    }
}

test "textarea field frame announces errors focuses and disables without an outline" {
    for ([_]theme.Name{ .dark, .light, .sauber }) |name| {
        const cx = try ui.Cx.init(std.testing.allocator, std.testing.io);
        defer cx.deinit();
        cx.setTheme(theme.widgetTheme(name));
        try cx.setTestFrameStep(16);
        cx.setViewport(480, 240);
        const scope = try ui.Scope.init(cx.allocator, null, cx.owner);
        defer scope.dispose();
        cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
        const disabled = try scope.createSignal(bool, false);
        const result = try ui.widgets.Textarea(.{ .disabled = disabled, .value = "saved", .error_msg = "错误信息", .rows = 2 }).mountResult(scope, cx);
        try cx.root.?.appendChild(cx.allocator, result.wrapper);
        settle(cx);
        const c = cx.tokens.tokens.color;
        const resting = result.input.getBackground();
        try std.testing.expect(result.input.behavior.interaction.a11y.?.invalid);
        try expectFrame(result.input, c.danger);
        cx.setFocus(result.input);
        settle(cx);
        try std.testing.expect(result.state.focused);
        try expectFrame(result.input, c.danger);
        // Focus never repaints the field fill (zenit native focus presentation).
        try std.testing.expectEqual(resting, result.input.getBackground());
        cx.clearFocus();
        settle(cx);
        try std.testing.expectEqual(resting, result.input.getBackground());
        try expectFrame(result.input, c.danger);
        cx.setFocus(result.input);
        disabled.set(true);
        settle(cx);
        try std.testing.expect(!result.state.focused);
        try std.testing.expect(result.input.behavior.interaction.a11y.?.disabled);
        try std.testing.expectEqual(c.disabled_bg, result.input.getBackground());
        try std.testing.expect(result.input.style.outline() == null);
    }
}
