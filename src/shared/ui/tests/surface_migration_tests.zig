//! 表面迁移适配器（`shared/ui/surface/surface_migration.zig`，LIFECYCLE.md §2）在真实 Cx 上的契约：
//! `move` 保住属于节点的状态、结束属于旧位置的输入、关掉从表面里打开的浮层；`park` 是真的离开窗口。
const std = @import("std");
const ui = @import("ui");
const migration = @import("../surface/surface_migration.zig");
const drag = ui.interaction.drag;

const Fixture = struct {
    cx: *ui.Cx,
    scope: *ui.Scope,
    root: *ui.Node,
    home: *ui.Node,
    away: *ui.Node,
    outside: *ui.Node,
    surface: *ui.Node,
    editor: ui.widgets.input.InputResult,
    scroll: ui.widgets.ScrollAreaResult,
    blurs: usize = 0,

    fn init(f: *Fixture) !void {
        const a = std.testing.allocator;
        const cx = try ui.Cx.init(a, std.testing.io);
        errdefer cx.deinit();
        cx.setViewport(900, 600);
        const scope = try ui.Scope.init(a, null, cx.owner);
        errdefer scope.dispose();
        const root = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .direction = .row }, .{});
        cx.root = root;
        const home = try ui.box(cx, .{ .width = .{ .px = 300 }, .height = .{ .px = 400 }, .direction = .column }, .{});
        const away = try ui.box(cx, .{ .width = .{ .px = 420 }, .height = .{ .px = 500 }, .direction = .column }, .{});
        const outside = try ui.box(cx, .{ .width = .{ .px = 40 }, .height = .{ .px = 40 } }, .{});
        outside.setFocusable(true);
        try root.appendChild(a, home);
        try root.appendChild(a, away);
        try root.appendChild(a, outside);
        const surface = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .direction = .column }, .{});
        const editor = try ui.widgets.Input(.{ .value = "unsaved draft" }).mountResult(scope, cx);
        try surface.appendChild(a, editor.node);
        const scroll = try ui.widgets.ScrollArea(.{ .direction = .vertical, .height = 120, .rubber_band_y = false }).mount(scope, cx);
        try scroll.content.appendChild(a, try ui.box(cx, .{ .width = .fill(), .height = .{ .px = 900 }, .flex_shrink = 0 }, .{}));
        try surface.appendChild(a, scroll.container);
        try home.appendChild(a, surface);
        try migration.own(scope, cx, surface);
        f.* = .{ .cx = cx, .scope = scope, .root = root, .home = home, .away = away, .outside = outside, .surface = surface, .editor = editor, .scroll = scroll };
        f.frames(3);
    }

    fn deinit(f: *Fixture) void {
        // A surface still parked when the test ends is released with the scope that owns it.
        f.scope.dispose();
        migration.forgetWindow(f.cx);
        f.cx.deinit();
    }

    fn frames(f: *Fixture, n: usize) void {
        for (0..n) |_| {
            f.cx.frame_time_ms += 16;
            f.cx.layout();
            _ = f.cx.render();
        }
    }
};

test "surface migration: move keeps focus, the caret, an IME composition, the scroll position and node identity" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    const cx = f.cx;
    cx.setFocus(f.editor.input_container);
    f.editor.state.cursor_pos = 7;
    const handler = f.editor.input_container.behavior.events.on_event.?;
    _ = handler(.{ .ime_preedit = .{ .text = "ni", .cursor_utf8_offset = 2 } }, f.editor.input_container.behavior.events.event_context);
    try std.testing.expect(f.editor.state.imeIsComposing());
    ui.widgets.scroll_area.setScrollY(f.scroll.state, f.scroll.content, 240);
    f.frames(2);
    const scrolled = f.scroll.state.scroll_y;
    try std.testing.expect(scrolled > 200);
    const identity: ui.hit.NodeHandle = .{ .id = f.surface.id, .generation = try cx.node_registry.trackGeneration(f.surface) };
    const editor_identity: ui.hit.NodeHandle = .{ .id = f.editor.input_container.id, .generation = try cx.node_registry.trackGeneration(f.editor.input_container) };
    const before_moves = migration.moves;

    try migration.move(cx, f.surface, .{ .parent = f.away });
    try std.testing.expect(f.surface.parent == f.away);
    try std.testing.expectEqual(before_moves + 1, migration.moves);
    try std.testing.expect(migration.holdsFocus(cx, f.surface));
    try std.testing.expect(cx.focus_manager.getFocused() == f.editor.input_container);
    try std.testing.expect(f.editor.state.imeIsComposing());
    try std.testing.expectEqual(@as(usize, 7), f.editor.state.cursor_pos);
    try std.testing.expect(cx.node_registry.isCurrentIdentity(identity, f.surface));
    try std.testing.expect(cx.node_registry.isCurrentIdentity(editor_identity, f.editor.input_container));
    f.frames(3);
    // Laid out in the new host, same scroll offset, composition still open after frames.
    try std.testing.expect(f.surface.globalRect().x >= f.away.globalRect().x and f.surface.globalRect().w > 400);
    try std.testing.expectApproxEqAbs(scrolled, f.scroll.state.scroll_y, 0.5);
    try std.testing.expect(f.editor.state.imeIsComposing());
    try std.testing.expect(cx.focus_manager.getFocused() == f.editor.input_container);
    _ = handler(.{ .ime_commit = .{ .text = "你" } }, f.editor.input_container.behavior.events.event_context);
    try std.testing.expectEqualStrings("unsaved你 draft", f.editor.state.getText());

    // Already there: nothing happens (not counted, nothing closed).
    try migration.move(cx, f.surface, .{ .parent = f.away });
    try std.testing.expectEqual(before_moves + 1, migration.moves);
}

test "surface migration: move ends what was bound to the old place and closes the layers opened from inside" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    const cx = f.cx;
    const a = std.testing.allocator;
    // A popover opened from a button inside the surface, and one opened from outside it.
    const inside_open = try f.scope.createSignal(bool, false);
    const inside = try ui.widgets.Popover(.{ .open = inside_open, .trigger = .manual, .enter_transition = .none, .exit_transition = .none, .width = 120 }).mount(f.scope, cx);
    try inside.content.appendChild(a, try ui.text(cx, "from the surface", .{}));
    try f.surface.appendChild(a, inside.wrapper);
    const trigger = inside.wrapper;
    const outside_open = try f.scope.createSignal(bool, false);
    const other = try ui.widgets.Popover(.{ .open = outside_open, .trigger = .manual, .enter_transition = .none, .exit_transition = .none, .width = 120 }).mount(f.scope, cx);
    try other.content.appendChild(a, try ui.text(cx, "from elsewhere", .{}));
    try f.root.appendChild(a, other.wrapper);
    inside_open.set(true);
    outside_open.set(true);
    f.frames(4);
    try std.testing.expect(inside_open.peek() and outside_open.peek());
    _ = try cx.node_registry.trackGeneration(trigger);
    cx.pressed_node = trigger;
    cx.hovered_node = trigger;
    cx.dispatcher.setPointerCapture(trigger);

    try migration.move(cx, f.surface, .{ .parent = f.away });
    f.frames(30);
    try std.testing.expect(!inside_open.peek());
    try std.testing.expect(outside_open.peek());
    try std.testing.expect(cx.pressed_node == null and cx.hovered_node == null);
    try std.testing.expect(cx.dispatcher.pointer_capture_handle == null);
}

test "surface migration: park takes the surface out of the window — focus leaves, state stays — and move puts it back in any host" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    const cx = f.cx;
    cx.setFocus(f.editor.input_container);
    ui.widgets.scroll_area.setScrollY(f.scroll.state, f.scroll.content, 180);
    f.frames(2);
    const scrolled = f.scroll.state.scroll_y;
    const before_parks = migration.parks;

    migration.park(cx, f.surface);
    try std.testing.expect(migration.isParked(f.surface));
    try std.testing.expectEqual(before_parks + 1, migration.parks);
    try std.testing.expect(!migration.holdsFocus(cx, f.surface));
    try std.testing.expect(cx.focus_manager.getFocused() == null);
    // Parked again: nothing more happens.
    migration.park(cx, f.surface);
    try std.testing.expectEqual(before_parks + 1, migration.parks);
    // Out of the window: frames do not lay it out, its state is untouched.
    f.frames(3);
    try std.testing.expectEqualStrings("unsaved draft", f.editor.state.getText());

    try migration.move(cx, f.surface, .{ .parent = f.away });
    f.frames(3);
    try std.testing.expect(f.surface.parent == f.away and f.surface.globalRect().w > 400);
    try std.testing.expectApproxEqAbs(scrolled, f.scroll.state.scroll_y, 0.5);
    // Focus is not brought back by the adapter: the host that shows the surface decides.
    try std.testing.expect(cx.focus_manager.getFocused() == null);
    cx.setFocus(f.editor.input_container);
    try std.testing.expect(migration.holdsFocus(cx, f.surface));
}

test "surface migration: parking a surface in the middle of an IME composition ends the composition without committing or losing text" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    const cx = f.cx;
    cx.setFocus(f.editor.input_container);
    f.editor.state.cursor_pos = 7;
    const handler = f.editor.input_container.behavior.events.on_event.?;
    const context = f.editor.input_container.behavior.events.event_context;
    _ = handler(.{ .ime_preedit = .{ .text = "zhong", .cursor_utf8_offset = 5 } }, context);
    try std.testing.expect(f.editor.state.imeIsComposing());
    // The panel that shows the surface closes: the surface leaves the window.
    migration.park(cx, f.surface);
    try std.testing.expect(!f.editor.state.imeIsComposing());
    try std.testing.expectEqualStrings("unsaved draft", f.editor.state.getText());
    try std.testing.expect(cx.focus_manager.getFocused() == null);
    // Reopened: the draft is there, a new composition starts cleanly at the caret.
    try migration.move(cx, f.surface, .{ .parent = f.home });
    f.frames(2);
    cx.setFocus(f.editor.input_container);
    _ = handler(.{ .ime_preedit = .{ .text = "wen", .cursor_utf8_offset = 3 } }, context);
    try std.testing.expect(f.editor.state.imeIsComposing());
    _ = handler(.{ .ime_commit = .{ .text = "文" } }, context);
    try std.testing.expect(std.mem.indexOf(u8, f.editor.state.getText(), "文") != null);
    try std.testing.expectEqual(@as(usize, "unsaved draft".len + "文".len), f.editor.state.getText().len);
}

test "surface migration: a drag in progress from inside the surface is cancelled when the surface moves or leaves" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    const cx = f.cx;
    const a = std.testing.allocator;
    const Probe = struct {
        cancelled: usize = 0,
        fn on(event: drag.Event, raw: *anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            if (event.phase == .cancel) self.cancelled += 1;
        }
    };
    var probe: Probe = .{};
    const grip = try ui.box(cx, .{ .width = .{ .px = 80 }, .height = .{ .px = 24 } }, .{});
    try f.surface.appendChild(a, grip);
    _ = try drag.Binding.attach(f.scope, cx, grip, .{}, Probe.on, &probe);
    f.frames(3);
    const r = grip.globalRect();
    cx.handleMouseDown(r.x + 10, r.y + 10, .{});
    cx.handleMouseMove(r.x + 40, r.y + 30);
    cx.handleMouseMove(r.x + 80, r.y + 60);
    try std.testing.expect(cx.drag_manager.session != null);
    // The tab that owns the surface closes mid drag: the surface leaves.
    migration.park(cx, f.surface);
    try std.testing.expect(cx.drag_manager.session == null);
    try std.testing.expectEqual(@as(usize, 1), probe.cancelled);
    cx.handleMouseUp(r.x + 80, r.y + 60);
    f.frames(2);
}

test "surface migration: a parked surface is released with its owning scope; one inside a host is left to the host" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    const cx = f.cx;
    const a = std.testing.allocator;
    const scope = try f.scope.childScope();
    const parked = try ui.box(cx, .{}, .{});
    try parked.appendChild(a, try ui.text(cx, "parked content", .{}));
    try f.away.appendChild(a, parked);
    const hosted = try ui.box(cx, .{}, .{});
    try f.away.appendChild(a, hosted);
    try migration.own(scope, cx, parked);
    try migration.own(scope, cx, hosted);
    migration.park(cx, parked);
    f.frames(2);
    // The testing allocator reports the parked subtree if nobody frees it; the hosted one must not be freed twice.
    scope.dispose();
    try std.testing.expect(hosted.parent == f.away);
    f.frames(2);
}

test "surface migration: an anchor transition made on the surface before a move still drives it afterwards" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    const cx = f.cx;
    const t = try ui.fx.AnchorTransition.attach(f.scope, cx, f.surface, .{});
    try migration.move(cx, f.surface, .{ .parent = f.away });
    f.frames(2);
    t.collapse(.none);
    for (0..120) |_| f.frames(1);
    try std.testing.expectEqual(ui.fx.anchor_transition.Phase.collapsed, t.phase());
    t.expand(.none);
    for (0..120) |_| f.frames(1);
    try std.testing.expectEqual(ui.fx.anchor_transition.Phase.expanded, t.phase());
    try std.testing.expect(f.surface.style.display != .none and f.surface.parent == f.away);
}

test "surface migration: a placement button leaves keyboard focus where it is on a pointer press" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    const cx = f.cx;
    const a = std.testing.allocator;
    const button = try ui.widgets.Button(.{ .label = "放入分屏" }).mount(f.scope, cx);
    try f.away.appendChild(a, button);
    const plain = try ui.widgets.Button(.{ .label = "别的按钮" }).mount(f.scope, cx);
    try f.away.appendChild(a, plain);
    migration.placementButton(button);
    f.frames(3);
    cx.setFocus(f.editor.input_container);
    var r = button.globalRect();
    cx.handleMouseDown(r.x + r.w / 2, r.y + r.h / 2, .{});
    cx.handleMouseUp(r.x + r.w / 2, r.y + r.h / 2);
    try std.testing.expect(cx.focus_manager.getFocused() == f.editor.input_container);
    // The contrast: an ordinary button takes focus.
    r = plain.globalRect();
    cx.handleMouseDown(r.x + r.w / 2, r.y + r.h / 2, .{});
    cx.handleMouseUp(r.x + r.w / 2, r.y + r.h / 2);
    try std.testing.expect(cx.focus_manager.getFocused() != f.editor.input_container);
}
