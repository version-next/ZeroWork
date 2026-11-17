//! The composer area as a template (ai_composer.yix, ai-redesign-e AI-1): the host's result
//! handle, the slots it fills, Send / Stop and the width-rule margins are view-model state.
const std = @import("std");
const ui = @import("ui");
const Composer = @import("../view/ai_composer_view.zig");
const a = std.testing.allocator;

const Host = struct {
    sent: usize = 0,
    stopped: usize = 0,
    changed: usize = 0,
    fn send(raw: *anyopaque) void {
        const self: *Host = @ptrCast(@alignCast(raw));
        self.sent += 1;
    }
    fn stop(raw: *anyopaque) void {
        const self: *Host = @ptrCast(@alignCast(raw));
        self.stopped += 1;
    }
    fn prompt(raw: *anyopaque, _: []const u8) void {
        const self: *Host = @ptrCast(@alignCast(raw));
        self.changed += 1;
    }
    fn action(_: *anyopaque, _: Composer.Controls.Envelope) !void {}
    fn act(_: *anyopaque, _: Composer.Interaction.Ticket, _: Composer.Interaction.Action) !void {}
};
fn find(node: *ui.Node, id: []const u8) ?*ui.Node {
    if (node.meta.ownership.meta.test_id) |value| if (std.mem.eql(u8, value, id)) return node;
    for (node.children.items) |child| if (find(child, id)) |result| return result;
    return null;
}
fn settle(cx: *ui.Cx) void {
    for (0..10) |_| {
        cx.advanceFrameClock();
        cx.layout();
        _ = cx.render();
    }
}

test "AI composer area: the Textarea result reaches the host; slots, Send / Stop and margins follow the view-model" {
    const cx = try ui.Cx.init(a, std.testing.io);
    defer cx.deinit();
    cx.bindFrameClock();
    try cx.setTestFrameStep(16);
    cx.setViewport(800, 600);
    cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .direction = .column, .justify = .end }, .{});
    const scope = try ui.Scope.init(a, null, cx.owner);
    defer scope.dispose();
    var host: Host = .{};
    const prompt = try scope.createText("", .{ .capacity = 256 });
    const vm = try Composer.View.mount(cx, scope, .{
        .prompt = prompt,
        .callbacks = .{ .context = &host, .send = Host.send, .stop = Host.stop, .prompt_changed = Host.prompt },
        .controls = .{ .context = &host, .action = Host.action },
        .interaction = .{ .context = &host, .act = Host.act },
    });
    try cx.root.?.appendChild(a, vm.root);
    settle(cx);
    // The host's handle: the compound field's own result (edit state, header / footer rows).
    const input = vm.input();
    try std.testing.expectEqualStrings("ai.prompt", input.input.meta.ownership.meta.test_id.?);
    try std.testing.expect(input.header != null and input.footer != null);
    try std.testing.expect(vm.chips.isDescendantOf(input.header.?));
    // The header row (attachment chips) follows the view-model (Textarea `header_visible`).
    try std.testing.expect(!input.header.?.isDisplayedInTree());
    try std.testing.expect(vm.setHeaderShown(true));
    try std.testing.expect(!vm.setHeaderShown(true));
    settle(cx);
    try std.testing.expect(input.header.?.isDisplayedInTree());
    try std.testing.expect(vm.setHeaderShown(false));
    settle(cx);
    try std.testing.expect(!input.header.?.isDisplayedInTree());
    try std.testing.expect(find(input.footer.?, "ai.composer.controls") != null);
    try std.testing.expect(vm.queue.isDescendantOf(vm.root) and vm.interaction.panel.isDescendantOf(vm.root));
    // Typing reaches the draft signal and the host; the host's own writes show in the field.
    cx.setFocus(input.input);
    cx.handleTextInput("hello");
    settle(cx);
    try std.testing.expectEqualStrings("hello", prompt.peek());
    try std.testing.expect(host.changed > 0);
    prompt.set("recalled");
    settle(cx);
    try std.testing.expectEqualStrings("recalled", input.state.getText());
    // Send / Stop (A8): states from the host, presses back to it.
    const send = find(vm.root, "ai.send").?;
    const stop = find(vm.root, "ai.stop").?;
    try std.testing.expect(!stop.isDisplayedInTree());
    vm.sendDisabledSignal().set(false);
    vm.setActions(true, true);
    vm.setSendHint("引导当前任务", "引导当前任务");
    settle(cx);
    try std.testing.expect(stop.isDisplayedInTree() and send.isDisplayedInTree());
    try std.testing.expectEqualStrings("引导当前任务", send.behavior.interaction.a11y.?.label.?);
    for ([_]*ui.Node{ send, stop }) |button| {
        const r = button.globalRect();
        cx.handleMouseDown(r.x + r.w / 2, r.y + r.h / 2, .{});
        cx.handleMouseUp(r.x + r.w / 2, r.y + r.h / 2);
        settle(cx);
    }
    try std.testing.expectEqual(@as(usize, 1), host.sent);
    try std.testing.expectEqual(@as(usize, 1), host.stopped);
    vm.setActions(true, false);
    settle(cx);
    try std.testing.expect(!send.isDisplayedInTree());
    // Width rule (⑤): margins and the pinned height are the area's own style.
    try std.testing.expect(vm.setArea(.{ .left = 16, .right = 16, .bottom = 16, .top = 6 }, 120, 16));
    settle(cx);
    try std.testing.expectEqual(@as(f32, 16), vm.root.style.padding.left);
    try std.testing.expectApproxEqAbs(@as(f32, 120), vm.root.globalRect().h, 0.5);
    try std.testing.expect(!vm.setArea(.{ .left = 16, .right = 16, .bottom = 16, .top = 6 }, 120, 16));
    // A decision panel takes the field's place; the composer hides when not writable.
    vm.setFieldShown(false);
    settle(cx);
    try std.testing.expect(!input.wrapper.isDisplayedInTree());
    vm.setShown(false);
    settle(cx);
    try std.testing.expect(!vm.root.isDisplayedInTree());
}
