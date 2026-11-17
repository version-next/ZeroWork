const std = @import("std");
const ui = @import("ui");
const S = @import("../../pane/view/ai_assistant_styles.zig");
const theme = @import("../../../../shared/ui/theme/app_theme.zig");
const a = std.testing.allocator;

const Fixture = struct {
    cx: *ui.Cx,
    scope: *ui.Scope,
    input: ui.widgets.input.TextareaResult,
    value: *ui.Signal([]const u8),
    disabled: *ui.Signal(bool),
    error_message: *ui.Signal([]const u8),
    outside: *ui.Node,
    submissions: usize = 0,
    alternates: usize = 0,

    fn init(self: *Fixture, borderless: bool) !void {
        const cx = try ui.Cx.init(a, std.testing.io);
        const scope = try ui.Scope.init(a, null, cx.owner);
        cx.setViewport(800, 400);
        cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .direction = .column }, .{});
        const composer = try ui.box(cx, S.composer(cx.tokens), .{});
        composer.setStyleInline(a, .{ .width = .{ .px = 600 } });
        try cx.root.?.appendChild(a, composer);
        const value = try scope.createText("", .{});
        const disabled = try scope.createSignal(bool, false);
        const error_message = try scope.createText("", .{});
        const input = try ui.widgets.Textarea(.{ .rows = 2, .value = value, .disabled = disabled, .error_msg = error_message, .placeholder = "继续提问", .embedded = borderless }).mountResult(scope, cx);
        if (borderless) input.wrapper.setStyleInline(a, .{ .width = .fill(), .height = .{ .fit = .{} } });
        try composer.appendChild(a, input.wrapper);
        const outside = try ui.widgets.Button(.{ .label = "外部控件" }).mount(scope, cx);
        try cx.root.?.appendChild(a, outside);
        self.* = .{ .cx = cx, .scope = scope, .input = input, .value = value, .disabled = disabled, .error_message = error_message, .outside = outside };
        input.input.behavior.events.capture_context = self;
        input.input.behavior.events.on_event_capture = composerKey;
        self.settle();
    }
    fn composerKey(event: ui.events.Event, raw: ?*anyopaque) ui.events.EventResult {
        const self: *Fixture = @ptrCast(@alignCast(raw orelse return .ignored));
        if (event == .key_down and event.key_down.key == .@"return") {
            switch (@import("../view/ai_composer_keys.zig").handleReturn(event.key_down, self.input.state)) {
                .composing => return .ignored,
                .newline => {},
                .submit => self.submissions += 1,
                .alternate => self.alternates += 1,
            }
            return .stop;
        }
        return .ignored;
    }
    fn deinit(self: *Fixture) void {
        self.cx.clearFocus();
        self.scope.dispose();
        self.cx.deinit();
    }
    fn settle(self: *Fixture) void {
        self.cx.setTestFrameStep(16) catch unreachable;
        for (0..4) |_| {
            self.cx.advanceFrameClock();
            self.cx.layout();
            _ = self.cx.render();
        }
    }
    fn expectBorderless(self: *Fixture) !void {
        try std.testing.expectEqual(@as(f32, 0), self.input.input.style.border.width);
        try std.testing.expect(ui.Color.eql(ui.Color.TRANSPARENT, self.input.input.getBackground()));
        try std.testing.expect(self.input.input.style.outline() == null);
        try std.testing.expect(self.input.input.parent.?.style.outline() == null);
    }
};

test "AI composer borderless Textarea preserves exact transparent Figma field through hover focus and blur" {
    var f: Fixture = undefined;
    try f.init(true);
    defer f.deinit();
    // Composer area margins (Pencil Kaf7E ③): 600 - 12 - 12.
    try std.testing.expectEqual(@as(f32, 576), f.input.input.globalRect().w);
    try f.expectBorderless();
    f.input.input.behavior.events.on_hover.?.invoke();
    f.settle();
    try f.expectBorderless();
    f.cx.setFocus(f.input.input);
    f.settle();
    try std.testing.expect(f.input.state.focused);
    try std.testing.expect(f.cx.focus_manager.current_focus == f.input.input);
    try f.expectBorderless();
    f.cx.setFocus(f.outside);
    f.settle();
    try std.testing.expect(!f.input.state.focused);
    try f.expectBorderless();
    f.input.input.behavior.events.on_leave.?.invoke();
    f.settle();
    try f.expectBorderless();
}

test "AI composer borderless Textarea retains native text IME caret and keyboard behavior" {
    var f: Fixture = undefined;
    try f.init(true);
    defer f.deinit();
    f.cx.setFocus(f.input.input);
    f.cx.handleTextInput("hello ");
    f.cx.handleImePreedit("nihao", 5);
    f.settle();
    try std.testing.expectEqualStrings("hello ", f.value.peek());
    try std.testing.expect(f.input.state.imeIsComposing());
    try std.testing.expectEqualStrings("nihao", f.input.state.preeditText());
    try std.testing.expect(f.input.input.behavior.interaction.text_input_client != null);
    try std.testing.expect(f.input.state.cursor_node != null);
    try f.expectBorderless();
    f.cx.handleImeCommit("你好");
    f.settle();
    try std.testing.expectEqualStrings("hello 你好", f.value.peek());
    f.cx.handleKeyDown(.left, .{});
    f.cx.handleTextInput("中");
    f.settle();
    try std.testing.expectEqualStrings("hello 你中好", f.value.peek());
    try std.testing.expect(f.input.input.behavior.interaction.a11y.?.editable_text != null);
    try f.expectBorderless();
}

test "AI composer borderless Textarea stays unframed across dynamic disabled error and global theme" {
    const previous = theme.currentName();
    defer theme.select(previous);
    var f: Fixture = undefined;
    try f.init(true);
    defer f.deinit();
    f.cx.setFocus(f.input.input);
    f.cx.handleImePreedit("ni", 2);
    f.disabled.set(true);
    f.settle();
    try std.testing.expect(!f.input.state.focused);
    try std.testing.expect(!f.input.state.imeIsComposing());
    try std.testing.expect(!f.input.input.behavior.interaction.focusable);
    try f.expectBorderless();
    f.error_message.set("请求失败");
    f.settle();
    try std.testing.expect(f.input.input.behavior.interaction.a11y.?.invalid);
    try f.expectBorderless();
    f.disabled.set(false);
    f.cx.setFocus(f.input.input);
    theme.select(.light);
    f.cx.setTheme(theme.widgetTheme(.light));
    f.settle();
    try f.expectBorderless();
    f.error_message.set("");
    f.cx.setFocus(f.outside);
    f.settle();
    try f.expectBorderless();
}

test "AI composer borderless prop defaults to existing normal and focused Textarea borders" {
    const cx = try ui.Cx.init(a, std.testing.io);
    defer cx.deinit();
    cx.setViewport(800, 400);
    cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    const scope = try ui.Scope.init(a, null, cx.owner);
    defer scope.dispose();
    const input = try ui.widgets.Textarea(.{ .rows = 2 }).mountResult(scope, cx);
    try cx.root.?.appendChild(a, input.wrapper);
    cx.layout();
    _ = cx.render();
    try std.testing.expectEqual(@as(f32, 1), input.input.style.border.width);
    cx.setFocus(input.input);
    try std.testing.expect(input.state.focused);
    try std.testing.expectEqual(@as(f32, 1.5), input.input.style.border.width);
    cx.clearFocus();
    try std.testing.expectEqual(@as(f32, 1), input.input.style.border.width);
}

test "AI composer text grows with its wrapped lines from one to six (native auto_rows) and preserves IME" {
    // The production composer: one compound field (attachments header, tool-row footer) whose text
    // grows by the native auto_rows (ai_host.mountAssistantConversation).
    const cx = try ui.Cx.init(a, std.testing.io);
    defer cx.deinit();
    cx.bindFrameClock();
    try cx.setTestFrameStep(16);
    cx.setViewport(600, 600);
    cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .direction = .column, .justify = .end }, .{});
    const scope = try ui.Scope.init(a, null, cx.owner);
    defer scope.dispose();
    const value = try scope.createText("", .{});
    const input = try ui.widgets.Textarea(.{ .value = value, .size = .md, .rows = 1, .auto_rows = .{ .min = 1, .max = 6 }, .placeholder = "继续提问…" }).mountCompound(scope, cx, .{ .header = true, .footer = true });
    try cx.root.?.appendChild(a, input.wrapper);
    const settle = struct {
        fn run(c: *ui.Cx) void {
            for (0..8) |_| {
                c.advanceFrameClock();
                c.layout();
                _ = c.render();
            }
        }
    }.run;
    settle(cx);
    const line = input.state.line_height;
    const pad = input.state.padding_v * 2;
    try std.testing.expectApproxEqAbs(line + pad, input.input.globalRect().h, 0.5);
    value.set("一\n二\n三\n四\n五\n六\n七\n八");
    settle(cx);
    try std.testing.expectApproxEqAbs(6 * line + pad, input.input.globalRect().h, 0.5);
    try std.testing.expectEqualStrings("一\n二\n三\n四\n五\n六\n七\n八", value.peek());
    cx.setFocus(input.input);
    cx.handleImePreedit("nihao", 5);
    settle(cx);
    try std.testing.expect(input.state.imeIsComposing());
    try std.testing.expectApproxEqAbs(6 * line + pad, input.input.globalRect().h, 0.5);
    cx.handleImeCommit("你好");
    settle(cx);
    try std.testing.expect(std.mem.endsWith(u8, value.peek(), "你好"));
    value.set("短问题");
    settle(cx);
    try std.testing.expectApproxEqAbs(line + pad, input.input.globalRect().h, 0.5);
    // Settled: further frames do not change the height.
    const settled = input.input.globalRect().h;
    settle(cx);
    try std.testing.expectEqual(settled, input.input.globalRect().h);
    cx.clearFocus();
}

test "AI composer empty states mount real shortcuts and configuration actions without dispatch" {
    const Empty = @import("../../sessions/view/ai_empty_view.zig");
    const Actions = struct {
        clicks: usize = 0,
        fn click(raw: *anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.clicks += 1;
        }
    };
    var f: Fixture = undefined;
    try f.init(true);
    defer f.deinit();
    var actions: Actions = .{};
    const hooks: Empty.Actions = .{ .context = &actions, .summarize = Actions.click, .logs = Actions.click, .settings = Actions.click, .ollama = Actions.click };
    const configured = try Empty.mount(f.cx, f.scope, true, hooks);
    configured.setStyleInline(a, .{ .width = .{ .px = 560 } });
    try f.cx.root.?.appendChild(a, configured);
    const unconfigured = try Empty.mount(f.cx, f.scope, false, hooks);
    unconfigured.setStyleInline(a, .{ .width = .{ .px = 560 } });
    try f.cx.root.?.appendChild(a, unconfigured);
    f.settle();
    try std.testing.expectEqual(@as(usize, 0), actions.clicks);
    const Find = struct {
        fn id(node: *ui.Node, key: []const u8) ?*ui.Node {
            if (node.meta.ownership.meta.test_id) |value| if (std.mem.eql(u8, value, key)) return node;
            for (node.children.items) |child| if (id(child, key)) |found| return found;
            return null;
        }
    };
    // A1 (ai-redesign-c): the setup guide is the native W.Empty; its action is Empty's sm Button.
    const settings = Find.id(unconfigured, "ai.empty.settings").?;
    try std.testing.expect(settings.globalRect().w > 80);
    try std.testing.expectApproxEqAbs(@as(f32, 24), settings.globalRect().h, 0.01); // native sm Button (W.Empty action)
    f.cx.setFocus(settings);
    f.cx.handleKeyDown(.@"return", .{});
    f.settle();
    try std.testing.expectEqual(@as(usize, 1), actions.clicks);
}

test "multiline input uses the same typography for painted rows caret wrapping and scrolling" {
    for ([_]bool{ false, true }) |borderless| {
        var f: Fixture = undefined;
        try f.init(borderless);
        defer f.deinit();
        // Reproduce a form supplying a different inherited font from the editor.
        f.input.input.setStyleInline(a, .{ .font_size = 28, .font_weight = 700 });
        f.input.state.font_size = 17;
        f.input.state.font_weight = 600;
        f.input.state.line_height = 25;
        f.input.state.char_width = 10;
        f.value.set("Wi中😀 abcdefghijklmnopqrstuvwxyz\nsecond line\nthird line");
        f.cx.setFocus(f.input.input);
        f.settle();
        const state = f.input.state;
        try std.testing.expectEqual(@as(f32, 17), state.wrap_map.font_size);
        try std.testing.expectEqual(@as(u16, 600), state.wrap_map.font_weight);
        try std.testing.expectEqual(@as(f32, 25), state.vl_state.?.props.item_height);
        var count: usize = 0;
        for (state.vl_state.?.pool_nodes) |row| {
            const text = row.getText() orelse continue;
            // Painted row typography is the row's resolved text props (its own pinned
            // metrics); new zenit `resolveTextFontSize` reports only the inherited box
            // font the parent supplies, which this test deliberately sets to 28/700.
            try std.testing.expectEqual(@as(f32, 17), row.resolveTextProps().?.font_size);
            try std.testing.expectEqual(@as(u16, 600), row.resolveTextProps().?.font_weight);
            try std.testing.expectApproxEqAbs(@as(f32, 25.0 / 17.0), text.line_height, 0.001);
            count += 1;
        }
        try std.testing.expect(count > 0);
        try std.testing.expectApproxEqAbs(@as(f32, 23), state.cursor_node.?.globalRect().h, 0.01);
        // A parent style change must not silently change the row's font.
        f.input.input.setStyleInline(a, .{ .font_size = 32, .font_weight = 300 });
        f.settle();
        for (state.vl_state.?.pool_nodes) |row| {
            if (row.getText() == null) continue;
            try std.testing.expectEqual(@as(f32, 17), row.resolveTextProps().?.font_size);
            try std.testing.expectEqual(@as(u16, 600), row.resolveTextProps().?.font_weight);
        }
    }
}

test "AI composer Shift Return inserts a newline while Return submits and queue shortcuts remain separate" {
    var f: Fixture = undefined;
    try f.init(true);
    defer f.deinit();
    f.cx.setFocus(f.input.input);
    f.cx.handleTextInput("first");
    f.cx.handleKeyDown(.@"return", .{ .shift = true });
    f.cx.handleTextInput("第二行");
    f.settle();
    try std.testing.expectEqualStrings("first\n第二行", f.value.peek());
    try std.testing.expectEqual(@as(usize, 0), f.submissions);
    f.cx.handleKeyDown(.@"return", .{});
    try std.testing.expectEqual(@as(usize, 1), f.submissions);
    try std.testing.expectEqualStrings("first\n第二行", f.value.peek());
    f.cx.handleKeyDown(.@"return", .{ .super = true, .shift = true });
    f.cx.handleKeyDown(.@"return", .{ .ctrl = true, .shift = true });
    try std.testing.expectEqual(@as(usize, 2), f.alternates);
    f.cx.handleKeyDown(.@"return", .{ .super = true });
    try std.testing.expectEqualStrings("first\n第二行\n", f.value.peek());
    f.cx.handleImePreedit("zhong", 5);
    f.cx.handleKeyDown(.@"return", .{ .shift = true });
    try std.testing.expectEqual(@as(usize, 1), f.submissions);
    f.cx.handleImeCommit("中");
    f.settle();
    try std.testing.expect(std.mem.endsWith(u8, f.value.peek(), "中"));
}
