const std = @import("std");
const ui = @import("ui");
const policy = @import("../../../ai/command_error_hint.zig");
const View = @import("../view/command_error_hint_view.zig").View;
const Adapter = @import("../../../vt/ghostty_adapter.zig").Adapter;
const notice_host = @import("../../../host/notification_host.zig");
const notifications = @import("../../notifications/mod.zig");
const identity = @import("../../../host/identity.zig");
const a = std.testing.allocator;
const owner: identity.SessionHandle = .{ .session_id = @fromBackingInt(7), .generation = 2 };

fn observe(model: *policy.Model, adapter: *Adapter) !bool {
    var projection = try adapter.copyProjection(a);
    defer projection.deinit(a);
    return model.observe(owner, &projection);
}
fn baseline(model: *policy.Model, adapter: *Adapter, enabled: bool) !void {
    model.configure(owner, enabled);
    try std.testing.expect(!try observe(model, adapter));
}
const failure = "\x1b]133;A\x07% \x1b]133;B\x07false\r\n\x1b]133;C;cmdline_url=false\x07\x1b[31m失败 output\x1b[0m\r\n\x1b]133;D;7\x07";

test "AI error hint real OSC parser provides one original command nonzero exit and plain frozen context" {
    var adapter = try Adapter.init(a, 6, 80);
    defer adapter.destroy();
    var model = policy.Model.init(a);
    defer model.deinit();
    try baseline(&model, &adapter, true);
    _ = try adapter.feed(failure[0..25]);
    try std.testing.expect(!try observe(&model, &adapter));
    _ = try adapter.feed(failure[25..]);
    try std.testing.expect(try observe(&model, &adapter));
    const hint = model.pending.?;
    try std.testing.expect(hint.owner.eql(owner));
    try std.testing.expect(hint.command_id != 0 and hint.end_sequence > hint.command_id);
    try std.testing.expectEqualStrings("false", hint.command);
    try std.testing.expectEqual(@as(i32, 7), hint.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, hint.output, "失败 output") != null);
    try std.testing.expect(std.mem.indexOfScalar(u8, hint.output, 0x1b) == null);
    try std.testing.expect(!try observe(&model, &adapter));
    _ = try adapter.feed("\x1b[2J\x1b[Hnew unrelated output");
    try std.testing.expect(!try observe(&model, &adapter));
    try std.testing.expect(std.mem.indexOf(u8, hint.output, "失败 output") != null);
    try std.testing.expect(model.current(owner, hint.command_id) != null);
    try std.testing.expect(model.current(try owner.nextGeneration(), hint.command_id) == null);
    try std.testing.expect(model.current(owner, hint.command_id + 1) == null);
    model.dismiss();
    try std.testing.expect(!try observe(&model, &adapter));
    try std.testing.expect(model.pending == null);
}

test "AI error hint ignores ERROR words success unknown exit orphan end and redraw" {
    var adapter = try Adapter.init(a, 4, 80);
    defer adapter.destroy();
    var model = policy.Model.init(a);
    defer model.deinit();
    try baseline(&model, &adapter, true);
    for ([_][]const u8{
        "ERROR fatal failure exit=1\r\n",
        "\x1b]133;D;2\x07",
        "\x1b]133;C;cmdline=true\x07ERROR\x1b]133;D;0\x07",
        "\x1b]133;C;cmdline=unknown\x07\x1b]133;D\x07",
        "\x1b]133;A\x07\x1b]133;A\x07",
    }) |bytes| {
        _ = try adapter.feed(bytes);
        try std.testing.expect(!try observe(&model, &adapter));
        try std.testing.expect(model.pending == null);
    }
}

test "AI error hint saved switch consumes disabled facts and enabling never replays them" {
    var adapter = try Adapter.init(a, 4, 80);
    defer adapter.destroy();
    var model = policy.Model.init(a);
    defer model.deinit();
    try baseline(&model, &adapter, false);
    _ = try adapter.feed(failure);
    try std.testing.expect(!try observe(&model, &adapter));
    try baseline(&model, &adapter, true);
    try std.testing.expect(!try observe(&model, &adapter));
    _ = try adapter.feed(failure);
    try std.testing.expect(try observe(&model, &adapter));
    model.configure(owner, false);
    try std.testing.expect(model.pending == null);
    try baseline(&model, &adapter, true);
    try std.testing.expect(model.pending == null);
}

test "AI error hint original generation cannot attach an old projection or command to replacement owner" {
    var adapter = try Adapter.init(a, 4, 80);
    defer adapter.destroy();
    var model = policy.Model.init(a);
    defer model.deinit();
    try baseline(&model, &adapter, true);
    _ = try adapter.feed(failure);
    try std.testing.expect(try observe(&model, &adapter));
    const original_command = model.pending.?.command_id;
    const replacement = try owner.nextGeneration();
    model.configure(replacement, true);
    try std.testing.expect(model.pending == null);
    var projection = try adapter.copyProjection(a);
    defer projection.deinit(a);
    try std.testing.expectError(error.StaleOwner, model.observe(owner, &projection));
    try std.testing.expect(model.current(replacement, original_command) == null);
    try std.testing.expect(!try model.observe(replacement, &projection));
    try std.testing.expect(model.pending == null);
}

test "AI error hint missing semantic records cannot pair a later unrelated exit with old command" {
    var adapter = try Adapter.init(a, 4, 80);
    defer adapter.destroy();
    var model = policy.Model.init(a);
    defer model.deinit();
    try baseline(&model, &adapter, true);
    _ = try adapter.feed("\x1b]133;C;cmdline=old\x07");
    try std.testing.expect(!try observe(&model, &adapter));
    for (0..70) |_| _ = try adapter.feed("\x1b]133;A\x07");
    _ = try adapter.feed("\x1b]133;D;7\x07");
    try std.testing.expect(!try observe(&model, &adapter));
    try std.testing.expect(model.pending == null);
    _ = try adapter.feed(failure);
    try std.testing.expect(try observe(&model, &adapter));
    try std.testing.expectEqualStrings("false", model.pending.?.command);
}

const Sink = struct {
    calls: usize = 0,
    command_id: u64 = 0,
    fn open(raw: ?*anyopaque, hint: policy.Hint) !void {
        const self: *Sink = @ptrCast(@alignCast(raw.?));
        try std.testing.expect(hint.owner.eql(owner));
        try std.testing.expectEqualStrings("false", hint.command);
        try std.testing.expect(std.mem.indexOf(u8, hint.output, "失败 output") != null);
        self.calls += 1;
        self.command_id = hint.command_id;
    }
};

/// A window with the native notification stack (the hint's card goes there) and a terminal pane.
const Window = struct {
    cx: *ui.Cx,
    scope: *ui.Scope,
    notice: notice_host.Host,
    pane: *ui.Node,
    view: *View = undefined,

    fn init(self: *Window) !void {
        const cx = try ui.Cx.init(a, std.testing.io);
        cx.setViewport(800, 600);
        // Fixed like a window root: the notification stack's portal fills it.
        cx.root = try ui.box(cx, .{ .width = .{ .px = 800 }, .height = .{ .px = 600 } }, .{});
        cx.root.?.behavior.interaction.focusable = true;
        cx.cursor_state.pointer_valid = true;
        cx.hover_sync.pointer_over_content = true;
        cx.mouse_x = 5;
        cx.mouse_y = 590;
        const pane = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
        try cx.root.?.appendChild(a, pane);
        self.* = .{ .cx = cx, .scope = try ui.Scope.init(a, null, cx.owner), .pane = pane, .notice = .{ .allocator = a, .activity = .{ .allocator = a }, .driver = undefined, .coordinator = try notice_host.notifications.Coordinator.init(a, .{ .quiet_hours = "00:00-00:00" }, .{}) } };
        _ = try notifications.NotificationPresenter.mount(cx, self.scope, &self.notice, @fromBackingInt(1));
        self.view = try View.create(cx, pane);
    }
    fn deinit(self: *Window) void {
        self.view.destroy();
        self.scope.dispose();
        self.notice.coordinator.deinit();
        self.notice.activity.deinit();
        self.cx.deinit();
    }
    fn frame(self: *Window, now: u64) void {
        self.cx.frame_time_ms = @floatFromInt(now);
        self.cx.layout();
        // After-layout: the hint view syncs its card into the stack.
        self.view.sync();
        _ = self.cx.render();
        if (self.card()) |node| if (node.parent) |container| ui.widgets.Notifier.frameHookForTest()(container);
        self.cx.layout();
    }
    fn run(self: *Window, from: u64, to: u64) void {
        var t = from;
        while (t < to) : (t += 16) self.frame(t);
        self.frame(to);
    }
    fn card(self: *Window) ?*ui.Node {
        return find(self.cx, "terminal.ai-error-hint");
    }
    fn fail(self: *Window, adapter: *Adapter) !void {
        _ = try adapter.feed(failure);
        var failed = try adapter.copyProjection(a);
        defer failed.deinit(a);
        try self.view.observe(owner, &failed);
    }
};
fn find(cx: *ui.Cx, id: []const u8) ?*ui.Node {
    const portal = cx.ensurePopoverPortalRoot() catch return null;
    return findIn(portal, id);
}
fn findIn(root: *ui.Node, id: []const u8) ?*ui.Node {
    if (root.meta.ownership.meta.test_id) |value| if (std.mem.eql(u8, value, id)) return root;
    for (root.children.items) |child| if (findIn(child, id)) |found| return found;
    return null;
}
fn textOf(node: *ui.Node) []const u8 {
    if (node.getText()) |t| return t.content;
    for (node.children.items) |child| {
        const t = textOf(child);
        if (t.len > 0) return t;
    }
    return "";
}
fn primed(w: *Window, adapter: *Adapter, sink: *Sink) !void {
    w.view.configure(owner, true, .{ .context = sink, .on_open = Sink.open });
    var empty = try adapter.copyProjection(a);
    defer empty.deinit(a);
    try w.view.observe(owner, &empty);
}

test "AI error hint card in the window stack preserves focus until clicked and opens the original assistant once" {
    var w: Window = undefined;
    try w.init();
    defer w.deinit();
    w.cx.setFocus(w.cx.root.?);
    var sink: Sink = .{};
    var adapter = try Adapter.init(a, 4, 80);
    defer adapter.destroy();
    try primed(&w, &adapter, &sink);
    try w.fail(&adapter);
    w.run(0, 600);
    try std.testing.expectEqual(w.cx.root.?, w.cx.focus_manager.getFocused().?);
    try std.testing.expectEqual(@as(usize, 0), sink.calls);
    const card = w.card() orelse return error.TestUnexpectedResult;
    try std.testing.expect(card.globalRect().w > 0);
    try std.testing.expectEqualStrings("命令  false", textOf(find(w.cx, "terminal.ai-error-hint.command").?));
    try std.testing.expectEqualStrings("输出  失败 output", textOf(find(w.cx, "terminal.ai-error-hint.output").?));
    try std.testing.expectEqualStrings("命令执行失败 · 退出码 7", textOf(find(w.cx, "terminal.ai-error-hint.exit").?));
    try std.testing.expect(find(w.cx, "terminal.ai-error-hint.countdown") != null);
    // Activate through the native action button.
    const open = find(w.cx, "terminal.ai-error-hint.open").?;
    const r = open.globalRect();
    w.cx.handleMouseMove(r.x + r.w / 2, r.y + r.h / 2);
    w.cx.handleMouseDown(r.x + r.w / 2, r.y + r.h / 2, .{});
    w.cx.handleMouseUp(r.x + r.w / 2, r.y + r.h / 2);
    w.run(616, 1000);
    w.view.activate();
    try std.testing.expectEqual(@as(usize, 1), sink.calls);
    try std.testing.expect(sink.command_id != 0);
    try std.testing.expect(w.view.shownCard() == null);
    var failed = try adapter.copyProjection(a);
    defer failed.deinit(a);
    try w.view.observe(owner, &failed);
    w.run(1016, 1400);
    try std.testing.expect(w.view.shownCard() == null);
    try std.testing.expect(w.card() == null);
}

test "AI error hint times out without replay and a newer failure restarts the timer" {
    var w: Window = undefined;
    try w.init();
    defer w.deinit();
    var sink: Sink = .{};
    var adapter = try Adapter.init(a, 4, 80);
    defer adapter.destroy();
    try primed(&w, &adapter, &sink);
    try w.fail(&adapter);
    w.run(1000, 5000);
    const first = w.view.shownCard().?;
    try w.fail(&adapter);
    w.run(5016, 12_900);
    // Replaced at 5000: still shown (8 s from the new card).
    const second = w.view.shownCard() orelse return error.TestUnexpectedResult;
    try std.testing.expect(second != first);
    w.run(12_916, 13_600);
    try std.testing.expect(w.view.shownCard() == null);
    try std.testing.expect(w.view.model.pending == null);
    var again = try adapter.copyProjection(a);
    defer again.deinit(a);
    try w.view.observe(owner, &again);
    w.view.activate();
    try std.testing.expectEqual(@as(usize, 0), sink.calls);
}

test "AI error hint holds on hover and leaves the stack while its pane or window is hidden" {
    var w: Window = undefined;
    try w.init();
    defer w.deinit();
    var sink: Sink = .{};
    var adapter = try Adapter.init(a, 4, 80);
    defer adapter.destroy();
    try primed(&w, &adapter, &sink);
    try w.fail(&adapter);
    w.run(1000, 1400);
    const card = w.card().?.globalRect();
    w.cx.handleMouseMove(card.x + 30, card.y + 20);
    w.run(1416, 15_000);
    try std.testing.expect(w.view.shownCard() != null);
    w.cx.handleMouseMove(5, 590);
    // Hidden pane: the card leaves the stack, the failure stays pending.
    w.pane.setDisplay(.none);
    w.run(15_016, 15_600);
    try std.testing.expect(w.view.shownCard() == null);
    try std.testing.expect(w.view.model.pending != null);
    // Back on screen: shown again with the full window.
    w.pane.setDisplay(.flex);
    w.cx.root.?.markLayoutDirty();
    w.run(15_616, 16_000);
    try std.testing.expect(w.view.shownCard() != null);
    w.cx.window_active = false;
    w.run(16_016, 16_400);
    try std.testing.expect(w.view.shownCard() == null);
    w.cx.window_active = true;
    w.run(16_416, 16_800);
    try std.testing.expect(w.view.shownCard() != null);
    w.run(16_816, 24_300);
    try std.testing.expect(w.view.shownCard() != null);
    w.run(24_316, 25_200);
    try std.testing.expect(w.view.shownCard() == null);
    try std.testing.expect(w.view.model.pending == null);
}

test "AI error hint closing the setting removes the prompt" {
    var w: Window = undefined;
    try w.init();
    defer w.deinit();
    var sink: Sink = .{};
    var adapter = try Adapter.init(a, 4, 80);
    defer adapter.destroy();
    try primed(&w, &adapter, &sink);
    try w.fail(&adapter);
    w.run(0, 400);
    try std.testing.expect(w.view.shownCard() != null);
    w.view.configure(owner, false, .{ .context = &sink, .on_open = Sink.open });
    w.view.activate();
    try std.testing.expectEqual(@as(usize, 0), sink.calls);
    try std.testing.expect(w.view.shownCard() == null);
}

test "AI error hint window teardown frees the notification stack before the terminal pane without touching it" {
    // App quit order: the window scope (and its notification presenter) is disposed first, the
    // terminal pane and its hint view afterwards. The view must not reach into the freed stack.
    var w: Window = undefined;
    try w.init();
    var sink: Sink = .{};
    var adapter = try Adapter.init(a, 4, 80);
    defer adapter.destroy();
    try primed(&w, &adapter, &sink);
    try w.fail(&adapter);
    w.run(0, 400);
    try std.testing.expect(w.view.shownCard() != null);
    w.scope.dispose();
    try std.testing.expect(notifications.windowToasts(w.cx) == null);
    w.view.dismiss();
    w.view.destroy();
    w.notice.coordinator.deinit();
    w.notice.activity.deinit();
    w.cx.deinit();
}

test "AI error hint terminal host integration declarations compile" {
    _ = &@import("../view/terminal_view.zig").TerminalViewNode.configureErrorHint;
    _ = &@import("../view/terminal_view.zig").TerminalViewNode.consumeWorkerText;
    _ = &@import("../view/terminal_view.zig").TerminalViewNode.refreshTerminalService;
    _ = &@import("../../workspace/view/workspace.zig").Workspace.init;
}

test "AI error hint question preserves existing draft and complete original command output without dispatch" {
    const hint: policy.Hint = .{ .owner = owner, .command_id = 4, .end_sequence = 5, .command = "printf '%s' 工作目录", .output = "失败\nline two\n", .exit_code = 7 };
    const text = try policy.question(a, "现有草稿\n保留", hint);
    defer a.free(text);
    try std.testing.expect(std.mem.startsWith(u8, text, "现有草稿\n保留\n\n"));
    try std.testing.expect(std.mem.indexOf(u8, text, hint.command) != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "退出码：7") != null);
    try std.testing.expect(std.mem.endsWith(u8, text, hint.output));
    const empty = try policy.question(a, "", hint);
    defer a.free(empty);
    try std.testing.expect(!std.mem.startsWith(u8, empty, "\n"));
}

test "AI error hint sequence cutoff and reconnect reset keep old running commands out" {
    var adapter = try Adapter.init(a, 4, 80);
    defer adapter.destroy();
    var model = policy.Model.init(a);
    defer model.deinit();
    model.configure(owner, true);
    try model.primeSequence(owner, adapter.semanticSequence());
    _ = try adapter.feed("\x1b]133;C;cmdline=old\x07");
    try std.testing.expect(!try observe(&model, &adapter));
    model.resetFacts();
    try model.primeSequence(owner, adapter.semanticSequence());
    _ = try adapter.feed("\x1b]133;D;7\x07");
    try std.testing.expect(!try observe(&model, &adapter));
    _ = try adapter.feed(failure);
    try std.testing.expect(try observe(&model, &adapter));
}

test "AI error hint output preview excludes previous output and shell prompts" {
    var adapter = try Adapter.init(a, 12, 80);
    defer adapter.destroy();
    _ = try adapter.feed("old unrelated output\r\n" ++ failure ++ "\x1b]133;A\x07next prompt % ");
    var projection = try adapter.copyProjection(a);
    defer projection.deinit(a);
    const preview = try policy.outputPreview(a, &projection);
    defer a.free(preview);
    try std.testing.expectEqualStrings("失败 output", preview);
}

test "AI error hint output preview handles empty output and bounded Unicode" {
    var adapter = try Adapter.init(a, 20, 80);
    defer adapter.destroy();
    _ = try adapter.feed("old output\r\n\x1b]133;A\x07% \x1b]133;B\x07false\r\n\x1b]133;C\x07\x1b]133;D;1\x07\x1b]133;A\x07% ");
    var empty = try adapter.copyProjection(a);
    defer empty.deinit(a);
    const no_output = try policy.outputPreview(a, &empty);
    defer a.free(no_output);
    try std.testing.expectEqualStrings("", no_output);
    _ = try adapter.feed("\x1b]133;B\x07test\r\n\x1b]133;C\x07");
    for (0..100) |_| _ = try adapter.feed("错误详情");
    _ = try adapter.feed("\r\n\x1b]133;D;1\x07");
    var long = try adapter.copyProjection(a);
    defer long.deinit(a);
    const preview = try policy.outputPreview(a, &long);
    defer a.free(preview);
    try std.testing.expect(preview.len <= 515);
    try std.testing.expect(std.unicode.utf8ValidateSlice(preview));
    try std.testing.expect(std.mem.endsWith(u8, preview, "…"));
}

test "AI error hint exit code maps success interruption and failure to the card tone" {
    try std.testing.expectEqual(View.tone(0), .success);
    for ([_]i32{ 130, 143 }) |code| try std.testing.expectEqual(View.tone(code), .warning);
    for ([_]i32{ 1, 2, 126, 127, 137, 255 }) |code| try std.testing.expectEqual(View.tone(code), .failure);
}
