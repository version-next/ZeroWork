//! Native layout and actual Button/Radio/Input event tests for composer requests.
const std = @import("std");
const ui = @import("ui");
const V = @import("../view/ai_composer_interaction_view.zig");
const S = @import("../../pane/view/ai_assistant_styles.zig");
const a = std.testing.allocator;
const Fixture = struct {
    cx: *ui.Cx,
    scope: *ui.Scope,
    view: *V.View,
    composer: *ui.Node,
    calls: usize = 0,
    ticket: ?V.Ticket = null,
    last_route: ?@import("../../../../ai/execution_routing.zig").Route = null,
    fn init(self: *Fixture) !void {
        self.* = .{ .cx = try ui.Cx.init(a, std.testing.io), .scope = undefined, .view = undefined, .composer = undefined };
        self.cx.setViewport(600, 456);
        self.cx.root = try ui.box(self.cx, .{ .width = .fill(), .height = .fill(), .direction = .column, .justify = .end }, .{});
        self.scope = try ui.Scope.init(a, null, self.cx.owner);
        self.composer = try ui.boxStyled(self.cx, S.composer, .{});
        self.composer.setStyleInline(a, .{ .position = .relative });
        try self.cx.root.?.appendChild(a, self.composer);
        self.view = try V.View.mount(self.cx, self.scope, .{ .context = self, .act = act });
        try self.composer.appendChild(a, self.view.panel);
        self.view.pending.setStyleInline(a, S.pendingCapsule());
        try self.composer.appendChild(a, self.view.pending);
    }
    fn deinit(self: *Fixture) void {
        self.cx.clearFocus();
        self.scope.dispose();
        self.cx.deinit();
    }
    fn act(raw: *anyopaque, ticket: V.Ticket, action: V.Action) !void {
        const self: *Fixture = @ptrCast(@alignCast(raw));
        if (self.ticket == null or !ticket.eql(self.ticket.?)) return error.StaleApproval;
        if (action == .route) self.last_route = action.route;
        self.calls += 1;
    }
    fn show(self: *Fixture, snapshot: ?V.Snapshot) !void {
        self.ticket = if (snapshot) |value| value.ticket else null;
        _ = try self.view.update(snapshot);
        self.settle();
    }
    fn settle(self: *Fixture) void {
        self.cx.setTestFrameStep(16) catch unreachable;
        for (0..6) |_| {
            self.cx.advanceFrameClock();
            self.cx.layout();
            _ = self.cx.render();
        }
    }
    fn click(self: *Fixture, target: *ui.Node) void {
        const r = target.globalRect();
        self.cx.handleMouseDown(r.x + r.w / 2, r.y + r.h / 2, .{});
        self.cx.handleMouseUp(r.x + r.w / 2, r.y + r.h / 2);
        self.settle();
    }
    fn option(self: *Fixture, index: usize) *ui.Node {
        var buffer: [32]u8 = undefined;
        return self.node(std.fmt.bufPrint(&buffer, "ai.interaction.option.{d}", .{index}) catch unreachable);
    }
    fn node(self: *Fixture, id: []const u8) *ui.Node {
        return find(self.cx.root.?, id) orelse @panic("missing node");
    }
};
fn find(node: *ui.Node, id: []const u8) ?*ui.Node {
    if (node.meta.ownership.meta.test_id) |value| if (std.mem.eql(u8, value, id)) return node;
    for (node.children.items) |child| if (find(child, id)) |result| return result;
    return null;
}
fn approval(sequence: u64) V.Snapshot {
    return .{ .ticket = .{ .host = .{ .sequence = sequence, .hash = @splat(7) } }, .title = "确认执行命令", .target = "prod-web-01", .detail = "printf approval", .impact = "影响尚未核实。" };
}
fn question() V.Snapshot {
    return .{ .ticket = .{ .question = .{ .context = .{ .conversation_id = .{ .bytes = @splat(1) }, .task_id = .{ .bytes = @splat(2) }, .binding = .{ .tab = 1 }, .content = .{ .session = 1 }, .binding_revision = 1, .grant_revision = 1 }, .sequence = 1, .operation_id = 1, .turn_id = 1, .arguments_hash = @splat(1) } }, .title = "如何处理？", .options = &.{ .{ .id = "reload", .label = "重载配置", .description = "保留连接" }, .{ .id = "restart", .label = "重启服务" } } };
}
test "composer interaction postpones without a decision and retains question draft and selection" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    try f.show(question());
    f.click(f.option(1));
    try std.testing.expectEqualStrings("1", f.view.selected.peek().?);
    f.view.setVisible(false);
    try std.testing.expect(!f.view.expanded());
    f.view.setVisible(true);
    try std.testing.expectEqualStrings("1", f.view.selected.peek().?);
    f.view.custom_text.set("保留自定义答案");
    f.click(f.node("ai.interaction.postpone"));
    try std.testing.expectEqual(@as(usize, 0), f.calls);
    try std.testing.expect(f.view.pendingVisible());
    const pending = f.view.pending.globalRect();
    const composer = f.composer.globalRect();
    // Native secondary sm Button capsule, 8 above the composer area.
    try std.testing.expect(pending.h > 0 and pending.h <= 28);
    try std.testing.expectApproxEqAbs(composer.y - 8, pending.y + pending.h, 0.1);
    f.click(f.view.pending);
    try std.testing.expect(f.view.expanded());
    try std.testing.expectEqualStrings("1", f.view.selected.peek().?);
    try std.testing.expectEqualStrings("保留自定义答案", f.view.custom_text.peek());
    f.click(f.view.submit_button);
    f.click(f.view.submit_button);
    try std.testing.expectEqual(@as(usize, 1), f.calls);
}
test "composer interaction cancels an in-flight old press before replacing request" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    try f.show(approval(1));
    const r = f.view.accept.globalRect();
    f.cx.handleMouseDown(r.x + r.w / 2, r.y + r.h / 2, .{});
    try f.show(approval(2));
    f.cx.handleMouseUp(r.x + r.w / 2, r.y + r.h / 2);
    f.settle();
    try std.testing.expectEqual(@as(usize, 0), f.calls);
    f.click(f.view.accept);
    try std.testing.expectEqual(@as(usize, 1), f.calls);
    try f.show(null);
    try std.testing.expect(!f.view.expanded());
    try std.testing.expect(!f.view.pendingVisible());
}
test "composer interaction validates empty custom answer and keeps action row outside long content" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    try f.show(question());
    // The decision card is the composer area's content (composer padding: 0 top — the reply keeps
    // its own 12 above it, ai_assistant_styles.reply_to_composer — and 12 bottom).
    try std.testing.expect(f.view.panel.globalRect().h > 0);
    try std.testing.expectApproxEqAbs(f.view.panel.globalRect().h + 12, f.composer.globalRect().h, 0.5);
    f.click(f.view.submit_button);
    try std.testing.expectEqual(@as(usize, 0), f.calls);
    try std.testing.expect(f.node("ai.interaction.error").style.display == .flex);
    try std.testing.expect(f.node("ai.interaction.custom").style.display == .none);
    f.click(f.option(6));
    try std.testing.expect(f.node("ai.interaction.custom").style.display == .flex);
    try std.testing.expect(f.cx.focus_manager.current_focus == f.node("ai.interaction.answer"));
    try std.testing.expectEqualStrings("custom", f.view.selected.peek().?);
    f.click(f.view.submit_button);
    try std.testing.expectEqual(@as(usize, 0), f.calls);
    var long = approval(1);
    const detail = try a.alloc(u8, 8000);
    defer a.free(detail);
    @memset(detail, 'x');
    long.detail = detail;
    try f.show(long);
    // Long content scrolls inside the 180 viewport; the actions stay below it, inside the panel.
    try std.testing.expectEqual(@as(f32, 180), f.view.viewport.globalRect().h);
    const button = f.view.accept.globalRect();
    try std.testing.expect(button.y >= f.view.viewport.globalRect().y + 180);
    try std.testing.expect(button.y + button.h <= f.view.panel.globalRect().y + f.view.panel.globalRect().h);
    try std.testing.expect(button.y + button.h <= 456);
    f.cx.setViewport(360, 358);
    f.settle();
    for ([_]*ui.Node{ f.node("ai.interaction.postpone"), f.view.reject, f.view.accept }) |node| {
        const bounds = node.globalRect();
        // Inside the panel (composer margin 12 at the right).
        try std.testing.expect(bounds.x >= 0 and bounds.x + bounds.w <= 348.1);
    }
    try f.show(approval(2));
    try std.testing.expect(f.view.viewport.globalRect().h < 180);
    try std.testing.expectApproxEqAbs(f.view.panel.globalRect().h + 12, f.composer.globalRect().h, 0.5);
}
test "composer interaction run mode is the native segmented Tabs: chosen segment follows the snapshot, a click proposes the route" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    var snapshot = approval(1);
    snapshot.route_selectable = true;
    snapshot.route = .current_terminal;
    try f.show(snapshot);
    const tabs = f.node("ai.interaction.route");
    try std.testing.expectEqualStrings("Tabs", tabs.meta.ownership.meta.component_name.?);
    // Kaf7E A7: one 28-tall segmented control across the content column, three equal segments.
    const row = tabs.globalRect();
    try std.testing.expectApproxEqAbs(@as(f32, 28), row.h, 0.5);
    const segments = [_]*ui.Node{ f.node("ai.interaction.route.0"), f.node("ai.interaction.route.1"), f.node("ai.interaction.route.2") };
    for (segments) |segment| try std.testing.expectApproxEqAbs(segments[0].globalRect().w, segment.globalRect().w, 0.5);
    try std.testing.expect(segments[1].behavior.interaction.a11y.?.selected);
    try std.testing.expect(!segments[0].behavior.interaction.a11y.?.selected);
    // A click proposes the route; the shown segment waits for the host's snapshot.
    f.click(segments[2]);
    try std.testing.expectEqual(@as(usize, 1), f.calls);
    try std.testing.expectEqual(@import("../../../../ai/execution_routing.zig").Route.new_terminal, f.last_route.?);
    try std.testing.expect(segments[1].behavior.interaction.a11y.?.selected);
    snapshot.route = .new_terminal;
    try f.show(snapshot);
    try std.testing.expect(f.node("ai.interaction.route.2").behavior.interaction.a11y.?.selected);
    // After the decision the segments are disabled (no further proposals).
    f.click(f.view.accept);
    try std.testing.expectEqual(@as(usize, 2), f.calls);
    f.click(f.node("ai.interaction.route.0"));
    try std.testing.expectEqual(@as(usize, 2), f.calls);
    try std.testing.expect(f.node("ai.interaction.route.0").behavior.interaction.a11y.?.disabled);
}
test "composer interaction long impact note wraps inside the panel instead of running past it" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    var snapshot = approval(1);
    snapshot.impact = "仅执行上述完整命令。新工作终端将以此会话为来源，创建前会单独确认，并在执行结束后保留以便核对输出。";
    try f.show(snapshot);
    const note = f.node("ai.interaction.impact.note").globalRect();
    const text = f.node("ai.interaction.impact").globalRect();
    try std.testing.expect(text.x + text.w <= note.x + note.w + 0.5);
    // Wrapped onto more than one 18 line.
    try std.testing.expect(text.h > 18 * 1.5);
}
