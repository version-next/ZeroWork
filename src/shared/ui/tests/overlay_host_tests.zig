//! OverlayHost（`shared/ui/overlay/overlay_host.zig`）在真实 Cx 上的行为：同级面板的点击语义与互斥，
//! 以及 `Popover(.panel, …)` 的焦点进入、Tab 圈住、Esc、点外部与焦点归还（zenit 原生 Popover）。
const std = @import("std");
const ui = @import("ui");
const overlay = @import("../overlay/overlay_host.zig");

const Panel = struct {
    open: *ui.Signal(bool),
    fn show(self: *Panel) void {
        self.open.set(true);
    }
    fn hide(self: *Panel) void {
        self.open.set(false);
    }
};

fn frames(cx: *ui.Cx, n: usize) void {
    for (0..n) |_| {
        cx.frame_time_ms += 16;
        cx.layout();
        _ = cx.render();
    }
}

test "OverlayHost siblings: hover opens nothing; click toggles; siblings are exclusive, also when opened another way" {
    const a = std.testing.allocator;
    const cx = try ui.Cx.init(a, std.testing.io);
    defer cx.deinit();
    cx.setViewport(800, 600);
    const root = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .direction = .row, .padding = .{ .left = 120, .top = 120 } }, .{});
    cx.root = root;
    _ = try cx.ensurePopoverPortalRoot();
    const scope = try ui.Scope.init(a, null, cx.owner);
    defer scope.dispose();
    var states: [2]Panel = undefined;
    var triggers: [2]*ui.Node = undefined;
    var group: overlay.Siblings = .{};
    for (0..2) |i| {
        states[i] = .{ .open = try scope.createSignal(bool, false) };
        triggers[i] = try ui.widgets.Button(.{ .label = "工具", .on_click = cx.on(Panel, &states[i], Panel.show) }).mount(scope, cx);
        try root.appendChild(a, triggers[i]);
        try group.add(cx, scope, triggers[i], states[i].open, cx.on(Panel, &states[i], Panel.hide));
    }
    frames(cx, 2);
    const r = triggers[0].globalRect();
    cx.handleMouseMove(r.x + 4, r.y + r.h / 2);
    frames(cx, 4);
    try std.testing.expect(!states[0].open.peek());
    triggers[0].behavior.events.on_click.?.invoke();
    frames(cx, 1);
    try std.testing.expect(states[0].open.peek());
    triggers[1].behavior.events.on_click.?.invoke();
    frames(cx, 1);
    try std.testing.expect(!states[0].open.peek() and states[1].open.peek());
    triggers[1].behavior.events.on_click.?.invoke();
    frames(cx, 1);
    try std.testing.expect(!states[1].open.peek());
    try std.testing.expect(group.open_entry == null);
    // Opened by a shortcut (not the trigger): still closes the open sibling.
    triggers[0].behavior.events.on_click.?.invoke();
    frames(cx, 1);
    states[1].open.set(true);
    frames(cx, 1);
    try std.testing.expect(!states[0].open.peek() and states[1].open.peek());
    try std.testing.expect(group.open_entry != null and group.open_entry.?.open == states[1].open);
    // Closed from elsewhere (Escape, outside click, the panel itself): the group forgets it.
    states[1].open.set(false);
    frames(cx, 1);
    try std.testing.expect(group.open_entry == null);
    // Exclusivity is the open signals' effect: the group runs nothing per frame.
    try std.testing.expectEqual(@as(usize, 0), cx.after_layout_hooks.items.len);
}

test "OverlayHost panel popover: focus enters, Tab stays, Escape returns focus to the trigger, an outside click keeps the clicked focus" {
    const a = std.testing.allocator;
    const cx = try ui.Cx.init(a, std.testing.io);
    defer cx.deinit();
    cx.setViewport(800, 600);
    const root = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .direction = .column, .padding = .{ .left = 40, .top = 40 } }, .{});
    cx.root = root;
    _ = try cx.ensurePopoverPortalRoot();
    const scope = try ui.Scope.init(a, null, cx.owner);
    defer scope.dispose();
    var state: Panel = .{ .open = try scope.createSignal(bool, false) };
    const trigger = try ui.widgets.Button(.{ .label = "工具", .on_click = cx.on(Panel, &state, Panel.show) }).mount(scope, cx);
    try root.appendChild(a, trigger);
    const other = try ui.widgets.Button(.{ .label = "别处" }).mount(scope, cx);
    try root.appendChild(a, other);
    const popup = try overlay.Popover(.panel, .{ .open = state.open, .trigger = .manual, .anchor = .{ .node = trigger }, .position = .bottom_start, .width = 200 }).mount(scope, cx);
    try root.appendChild(a, popup.wrapper);
    var items: [2]*ui.Node = undefined;
    for (&items) |*item| {
        item.* = try ui.widgets.Button(.{ .label = "项" }).mount(scope, cx);
        try popup.content.appendChild(a, item.*);
    }
    frames(cx, 2);
    cx.setFocus(trigger);
    state.open.set(true);
    frames(cx, 30);
    try std.testing.expect(cx.focus_manager.getFocused() == items[0]);
    for (0..3) |_| {
        cx.handleKeyDown(.tab, .{});
        const now = cx.focus_manager.getFocused().?;
        try std.testing.expect(now == items[0] or now == items[1]);
    }
    cx.handleKeyDown(.escape, .{});
    frames(cx, 30);
    try std.testing.expect(!state.open.peek());
    try std.testing.expect(cx.focus_manager.getFocused() == trigger);
    // Outside click on another control: closes and keeps that control's focus.
    state.open.set(true);
    frames(cx, 30);
    try std.testing.expect(cx.focus_manager.getFocused() == items[0]);
    // An outside click: the press focuses the clicked control, then the panel closes (the outside
    // dismissal itself is zenit's, covered upstream).
    cx.setFocus(other);
    state.open.set(false);
    frames(cx, 30);
    try std.testing.expect(!state.open.peek());
    try std.testing.expect(cx.focus_manager.getFocused() == other);
}
