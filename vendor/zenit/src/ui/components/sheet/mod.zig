/// Sheet / Drawer component.
///
/// Panel sliding in from a screen edge (drawer), based on OverlayStack.
///
/// Features:
/// - Signal(bool) controls show/hide
/// - Four directions: left / right / top / bottom
/// - translate_x/translate_y implicit transition animation
/// - OverlayStack auto-manages z-index, mask, focus trap, Escape/outside-click
const std = @import("std");
const core = @import("../../core.zig");
const view = @import("../../view.zig");
const Cx = core.Cx;
const Node = core.Node;
const box = core.box;
const Color = core.Color;
const Padding = core.Padding;
const Signal = core.Signal;
const reactive = @import("../../reactive.zig");
const Scope = reactive.Scope;
const Model = reactive.Model;
const Source = reactive.Source;
const Handler = core.Handler;
const overlay_stack = @import("../../overlay_stack.zig");
const render_engine = @import("../../core/render_engine/mod.zig");

// Style layer in styles.zig.
const styles = @import("styles.zig");

/// Panel slide direction.
pub const SheetSide = enum {
    left,
    right,
    top,
    bottom,
};

/// Sheet properties.
pub const SheetProps = struct {
    side: SheetSide = .right,
    width: f32 = 320,
    height: f32 = 320,
    /// Mask color: null = the theme overlay token (follows `Cx.setTheme`); a color stays fixed.
    overlay_color: ?Color = null,
    background: ?Color = null,
    close_on_overlay: bool = true,
    close_on_escape: bool = true,
    /// Toggle state; semantics same as ModalProps.open (X / Esc / click mask are
    /// only suggestions).
    open: Model(bool) = .{ .local = false },
    animation_ms: f32 = 250,
    /// Play the enter transition when `open` is already true as the sheet mounts. Default false:
    /// one mounted open (a page restored with its panel up) is the open result, not an opening, so
    /// it appears at once. Set true when the caller mounts it in response to the opening itself.
    animate_initial_open: bool = false,
    /// Called after user-initiated toggle (Esc / click mask) settles.
    on_open_change: ?Handler(bool) = null,
    /// focusId of the control focused each time the sheet opens (read then, looked up inside it;
    /// see `FocusManager.pushScopeWith`); a change while it still waits is followed. Mounted but
    /// not shown / enabled yet = the sheet panel holds focus until it is; not mounted yet = the first
    /// control meanwhile. null = a declared `autoFocus` inside, else the first focusable control.
    initial_focus: Source(?[]const u8) = .{ .value = null },
    /// focusId of the control focus returns to when the sheet closes (read then, looked up in the
    /// whole window once the sheet is gone). null or not ready = the focus before it opened.
    return_focus: Source(?[]const u8) = .{ .value = null },
};

/// Sheet mount returns handle.
pub const SheetResult = struct {
    overlay: *Node,
    panel: *Node,
    content: *Node,
    /// See Modal.mount: true = overlay mounted to portal root; caller should not
    /// append again.
    portaled: bool = false,
    /// Parsed toggle signal (non-null when local / bound).
    open: ?*Signal(bool) = null,
    /// Entry for ui.view (see src/ui/view_parts.zig).
    pub fn viewParts(self: SheetResult) core.ViewParts {
        return .{ .root = if (self.portaled) null else self.overlay, .slot = self.content };
    }
};

const SheetRuntime = struct {
    open: reactive.Bound(bool),
    on_open_change: ?Handler(bool),

    fn requestClose(context: *anyopaque) void {
        const self: *SheetRuntime = @ptrCast(@alignCast(context));
        self.open.propose(false, self.on_open_change);
    }
};

fn transitionForSide(side: SheetSide) overlay_stack.Transition {
    return switch (side) {
        .left => .slide_left,
        .right => .slide_right,
        .top => .slide_top,
        .bottom => .slide_bottom,
    };
}

/// Create Sheet: `W.Sheet(.{ .side = .right, .open = panel_open })`
pub fn Sheet(props: anytype) SheetBuilder {
    return .{ .props = reactive.props.coerce(SheetProps, props) };
}

pub const SheetBuilder = struct {
    props: SheetProps,

    /// Retained mode: mount.
    pub fn mount(self: SheetBuilder, scope: *Scope, cx: *Cx) !SheetResult {
        cx.owner.enterMount();
        defer cx.owner.exitMount();
        const my_scope = try scope.childScope();
        const allocator = cx.allocator;
        const p = self.props;

        const open = try reactive.resolveModel(bool, my_scope, p.open);
        const rt = try my_scope.allocator.create(SheetRuntime);
        rt.* = .{ .open = open, .on_open_change = p.on_open_change };
        try my_scope.adoptResource(@ptrCast(rt), struct {
            fn destroy(ptr: *anyopaque, alloc: std.mem.Allocator) void {
                alloc.destroy(@as(*SheetRuntime, @ptrCast(@alignCast(ptr))));
            }
        }.destroy);

        // Create modal layer via OverlayStack.
        const panel_transition = transitionForSide(p.side);
        const ol = try overlay_stack.overlay(my_scope, cx, .{
            .kind = .modal,
            .barrier = .colorOr(p.overlay_color),
            .dismiss = .{
                .outside_click = if (p.close_on_overlay) .close else .none,
                .escape = p.close_on_escape,
            },
            .enter_transition = panel_transition,
            .exit_transition = panel_transition,
            .focus = .{ .trap = true, .auto_focus = true, .restore = true },
            .on_dismiss_request = core.Cx.simpleHandler(SheetRuntime.requestClose, rt),
        });

        const barrier = ol.barrier.?;
        // overlay() configures focus_scope on ol.content, but this component doesn't
        // use ol.content; actual pushScope is barrier, so no config on barrier, trap/auto_focus
        // are no-ops.
        barrier.setFocusScope(.{ .trap = true, .auto_focus = true });
        barrier.meta.ownership.meta.component_name = "Sheet";
        try core.bindScopeToNode(my_scope, barrier);

        // Set overlay internal layout by direction, panel edges screen.
        switch (p.side) {
            .left => {
                barrier.style.direction = .row;
                barrier.style.justify = .start;
                barrier.style.align_items = .stretch;
            },
            .right => {
                barrier.style.direction = .row;
                barrier.style.justify = .end;
                barrier.style.align_items = .stretch;
            },
            .top => {
                barrier.style.direction = .column;
                barrier.style.justify = .start;
                barrier.style.align_items = .stretch;
            },
            .bottom => {
                barrier.style.direction = .column;
                barrier.style.justify = .end;
                barrier.style.align_items = .stretch;
            },
        }

        // sweep: panel mounted to barrier (barrier owned by overlay layer); on failure
        // view.mount reclaims mounted nodes.
        var panel: *Node = undefined;
        var content: *Node = undefined;
        try view.mount(my_scope, cx, barrier, view.capture(&panel, view.col(.{
            // styleBy: background / border / shadow re-resolve on theme switch.
            .style = view.styleBy(styles.Panel{ .side = p.side, .width = p.width, .height = p.height, .background = p.background }, styles.sheetPanel),
            // a11y attached to visible panel (overlay-configured a11y lands on ol.content
            // unused by this component).
            .a11y = .{ .role = .dialog, .modal = true },
        }, view.capture(&content, view.box(.{ .style = view.styleBy(styles.Themed{}, styles.sheetContent) }, {})))));

        // Position transition entirely via OverlayStack's slide_* transition. Don't
        // hand-write translate init here, otherwise stacks with enter/exit animation,
        // leaving panel in unstable "double offset" state on query/screenshot.

        // Bind real content_node from OverlayStack layer to panel, keeping hierarchy
        // and animation target aligned.
        cx.overlay_stack.bindContentNode(allocator, ol.handle, panel);
        if (rt.open.read.peek() and !p.animate_initial_open) cx.overlay_stack.skipInitialEnter(ol.handle);

        // open Effect
        {
            const vis = rt.open.read;
            reactive.checkBorrow(my_scope, vis);
            reactive.checkBorrow(my_scope, p.initial_focus);
            reactive.checkBorrow(my_scope, p.return_focus);
            const fm = &cx.focus_manager;
            const scope_pushed = try my_scope.createSignal(bool, false);
            // Direct unmount while open (Show switched / parent scope dispose) skips visible
            // effect pop branch -> focus scope stack leaks entry pointing to released barrier.
            const scope_guard = try my_scope.allocator.create(FocusScopeGuard);
            scope_guard.* = .{ .fm = fm, .pushed = scope_pushed, .barrier_id = barrier.id };
            try my_scope.adoptResource(@ptrCast(scope_guard), FocusScopeGuard.destroy);
            try my_scope.onCleanup(FocusScopeGuard, scope_guard, FocusScopeGuard.cleanup);

            // Initially hidden: barrier shrinks to 0 + layer suspended.
            if (!vis.peek()) {
                barrier.style.width = .{ .px = 0 };
                barrier.style.height = .{ .px = 0 };
                barrier.style.overflow_hidden = true;
                if (cx.overlay_stack.findLayer(ol.handle)) |layer| {
                    layer.suspended = true;
                }
            }

            try my_scope.createEffect(.{
                .barrier = barrier,
                .panel = panel,
                .visible = vis,
                .fm = fm,
                .scope_pushed = scope_pushed,
                .cx = cx,
                .layer_handle = ol.handle,
                .initial_focus = p.initial_focus,
                .return_focus = p.return_focus,
                .holder = panel,
            }, struct {
                fn update(c: anytype) void {
                    if (c.visible.get()) {
                        if (c.cx.overlay_stack.findLayer(c.layer_handle)) |layer| {
                            if (layer.suspended) {
                                c.cx.overlay_stack.reactivate(c.layer_handle);
                            } else if (layer.state == .exiting) {
                                c.cx.overlay_stack.cancelExit(c.layer_handle, .entering);
                            }
                        }
                        c.barrier.style.width = .{ .grow = .{} };
                        c.barrier.style.height = .{ .grow = .{} };
                        c.barrier.style.overflow_hidden = false;
                        c.barrier.markSizingDirty();
                        if (!c.scope_pushed.peek()) {
                            // While the named target is not ready, the panel holds focus (not a control).
                            c.fm.pushScopeWith(c.barrier, .{ .initial_focus = c.initial_focus.peek(), .placeholder = c.holder });
                            c.scope_pushed.set(true);
                        }
                    } else {
                        if (c.cx.overlay_stack.findLayer(c.layer_handle)) |layer| {
                            if (!layer.suspended and layer.state != .exiting) {
                                c.cx.overlay_stack.beginExit(c.layer_handle);
                            }
                        }
                        if (c.scope_pushed.peek()) {
                            c.fm.removeScopeWith(c.barrier.id, .{ .restore = true, .return_focus = c.return_focus.peek() });
                            c.scope_pushed.set(false);
                        }
                    }
                    c.barrier.markSizingDirty();
                    c.barrier.markRenderDirty();
                    c.cx.needs_redraw = true;
                }
            }.update);
            // A name computed from data that arrives after the open: the pending entry follows it.
            if (!p.initial_focus.isStatic()) try my_scope.createEffect(.{ .fm = fm, .barrier = barrier, .pushed = scope_pushed, .initial = p.initial_focus }, struct {
                fn follow(c: anytype) void {
                    const name = c.initial.get();
                    if (c.pushed.peek()) c.fm.updateScopeEntry(c.barrier, name);
                }
            }.follow);
        }

        return .{ .overlay = barrier, .panel = panel, .content = content, .portaled = ol.portaled, .open = rt.open.asSignal() };
    }
};

/// Unload this overlay's focus scope by id even when a child is above it.
const FocusScopeGuard = struct {
    fm: *@FieldType(core.Cx, "focus_manager"),
    pushed: *Signal(bool),
    barrier_id: u32,

    fn cleanup(g: *FocusScopeGuard) void {
        if (!g.pushed.peek()) return;
        g.pushed.set(false);
        g.fm.removeScope(g.barrier_id, true);
    }

    fn destroy(ptr: *anyopaque, alloc: std.mem.Allocator) void {
        const g: *FocusScopeGuard = @ptrCast(@alignCast(ptr));
        alloc.destroy(g);
    }
};

// ========== Tests ==========

test "Sheet: basic structure" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try box(ctx, .{ .width = .{ .px = 800 }, .height = .{ .px = 600 } }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const result = try Sheet(.{
        .side = .right,
        .width = 300,
    }).mount(scope, ctx);

    try root.appendChild(std.testing.allocator, result.overlay);

    // Overlay contains panel.
    try std.testing.expectEqual(@as(usize, 1), result.overlay.children.items.len);
    // Panel contains content.
    try std.testing.expectEqual(@as(usize, 1), result.panel.children.items.len);
    // Absolute positioning.
    try std.testing.expectEqual(core.Position.absolute, result.overlay.style.position);
}

test "Sheet: visible signal control" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try box(ctx, .{ .width = .{ .px = 800 }, .height = .{ .px = 600 } }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const vis = try scope.createSignal(bool, false);

    const result = try Sheet(.{
        .side = .left,
        .open = vis,
    }).mount(scope, ctx);

    try root.appendChild(std.testing.allocator, result.overlay);

    try std.testing.expectEqual(core.Sizing{ .px = 0 }, result.overlay.style.width);

    vis.set(true);
    try std.testing.expectEqual(core.Sizing{ .grow = .{} }, result.overlay.style.width);

    vis.set(false);
    try std.testing.expectEqual(core.Sizing{ .grow = .{} }, result.overlay.style.width);
    var exiting_found = false;
    for (ctx.overlay_stack.layers.items) |slot| {
        if (slot) |layer| {
            try std.testing.expectEqual(overlay_stack.LayerState.exiting, layer.state);
            exiting_found = true;
            break;
        }
    }
    try std.testing.expect(exiting_found);

    var test_time: f64 = 0;
    var ticks: u32 = 0;
    while (ticks < 32) : (ticks += 1) {
        test_time += 16.0;
        render_engine.current_frame_time_ms = test_time;
        _ = ctx.overlay_stack.tick(test_time, 0.016, 800, 600, std.testing.allocator);
    }

    try std.testing.expectEqual(core.Sizing{ .px = 0 }, result.overlay.style.width);
}

fn sheetFirstFrameOffset(animate_initial_open: bool) !f32 {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setViewport(800, 600);
    const root = try box(ctx, .{ .width = .{ .px = 800 }, .height = .{ .px = 600 } }, .{});
    ctx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const result = try Sheet(.{ .side = .right, .open = true, .animate_initial_open = animate_initial_open }).mount(scope, ctx);
    if (!result.portaled) try root.appendChild(std.testing.allocator, result.overlay);
    render_engine.current_frame_time_ms += 16.0;
    render_engine.current_frame_dt_ms = 16.0;
    ctx.layout();
    _ = ctx.render();
    return result.panel.style.translate_x;
}

test "Sheet: mounted open shows at once; animate_initial_open slides it in" {
    try std.testing.expectEqual(@as(f32, 0), try sheetFirstFrameOffset(false));
    try std.testing.expect(try sheetFirstFrameOffset(true) > 1);
}

test "Sheet: 打开状态下卸载会弹出自己的 focus scope" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const root = try box(ctx, .{ .width = .{ .px = 800 }, .height = .{ .px = 600 } }, .{});
    ctx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const vis = try scope.createSignal(bool, true);

    const sub = try scope.childScope();
    const result = try Sheet(.{ .side = .right, .open = vis }).mount(sub, ctx);
    if (!result.portaled) try root.appendChild(std.testing.allocator, result.overlay);
    const fm = &ctx.focus_manager;
    try std.testing.expectEqual(@as(u8, 1), fm.scope_count);

    sub.dispose();
    try std.testing.expectEqual(@as(u8, 0), fm.scope_count);
    try std.testing.expect(fm.activeScope() == null);
}

test "Sheet: 打开时 focus trap 生效并自动聚焦到对话框内" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const root = try box(ctx, .{ .width = .{ .px = 800 }, .height = .{ .px = 600 } }, .{});
    ctx.root = root;
    ctx.setViewport(800, 600);
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const vis = try scope.createSignal(bool, false);

    const outside = try box(ctx, .{ .width = .{ .px = 100 }, .height = .{ .px = 30 } }, .{});
    outside.behavior.interaction.focusable = true;
    try root.appendChild(std.testing.allocator, outside);

    const result = try Sheet(.{ .side = .right, .open = vis }).mount(scope, ctx);
    if (!result.portaled) try root.appendChild(std.testing.allocator, result.overlay);
    const inside = try box(ctx, .{ .width = .{ .px = 100 }, .height = .{ .px = 30 } }, .{});
    inside.behavior.interaction.focusable = true;
    try result.content.appendChild(std.testing.allocator, inside);

    ctx.layout();
    const fm = &ctx.focus_manager;
    fm.setFocus(outside);
    vis.set(true);

    try std.testing.expect(fm.getFocused() == inside);
    const order = fm.scopedFocusOrder();
    for (order) |n| try std.testing.expect(n != outside);
}

test "Sheet: initial_focus names the control focused on open; return_focus names where focus goes back" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const root = try box(ctx, .{ .width = .{ .px = 800 }, .height = .{ .px = 600 } }, .{});
    ctx.root = root;
    ctx.setViewport(800, 600);
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const vis = try scope.createSignal(bool, false);
    const outside = try box(ctx, .{ .width = .{ .px = 100 }, .height = .{ .px = 30 } }, .{});
    outside.behavior.interaction.focusable = true;
    try root.appendChild(std.testing.allocator, outside);
    const other = try box(ctx, .{ .width = .{ .px = 100 }, .height = .{ .px = 30 } }, .{});
    other.behavior.interaction.focusable = true;
    try root.appendChild(std.testing.allocator, other);
    _ = try ctx.focus_targets.register(ctx, .target, other, "page.other", false);

    const result = try Sheet(.{ .side = .right, .open = vis, .initial_focus = @as(?[]const u8, "sheet.second"), .return_focus = @as(?[]const u8, "page.other") }).mount(scope, ctx);
    if (!result.portaled) try root.appendChild(std.testing.allocator, result.overlay);
    const first = try box(ctx, .{ .width = .{ .px = 100 }, .height = .{ .px = 30 } }, .{});
    first.behavior.interaction.focusable = true;
    try result.content.appendChild(std.testing.allocator, first);
    const second = try box(ctx, .{ .width = .{ .px = 100 }, .height = .{ .px = 30 } }, .{});
    second.behavior.interaction.focusable = true;
    try result.content.appendChild(std.testing.allocator, second);
    _ = try ctx.focus_targets.register(ctx, .target, second, "sheet.second", false);

    ctx.layout();
    _ = ctx.render();
    const fm = &ctx.focus_manager;
    fm.setFocus(outside);
    vis.set(true);
    try std.testing.expect(fm.getFocused() == second);
    vis.set(false);
    try std.testing.expect(fm.getFocused() == other);
}

test "Sheet: exiting keeps overlay visible until commit" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try box(ctx, .{ .width = .{ .px = 800 }, .height = .{ .px = 600 } }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const vis = try scope.createSignal(bool, true);

    const result = try Sheet(.{
        .side = .right,
        .open = vis,
    }).mount(scope, ctx);

    try root.appendChild(std.testing.allocator, result.overlay);

    vis.set(false);
    try std.testing.expectEqual(core.Sizing{ .grow = .{} }, result.overlay.style.width);
    try std.testing.expectEqual(core.Sizing{ .grow = .{} }, result.overlay.style.height);

    var exiting_found = false;
    for (ctx.overlay_stack.layers.items) |slot| {
        if (slot) |layer| {
            if (layer.state == .exiting) {
                exiting_found = true;
                break;
            }
        }
    }
    try std.testing.expect(exiting_found);
}

test "Sheet: four sides" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try box(ctx, .{ .width = .{ .px = 800 }, .height = .{ .px = 600 } }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    // overlay_stack.overlay() always portals barrier when root exists (same window
    // portal as Popover); caller doesn't inline append, acts per `portaled` contract.
    inline for (.{ SheetSide.left, SheetSide.right, SheetSide.top, SheetSide.bottom }) |s| {
        const result = try Sheet(.{ .side = s }).mount(scope, ctx);
        try std.testing.expect(result.portaled);
        try std.testing.expect(result.overlay.parent == ctx.popover_portal_root.?);
    }

    try std.testing.expectEqual(@as(usize, 4), ctx.popover_portal_root.?.children.items.len);
    try std.testing.expectEqual(@as(usize, 1), root.children.items.len);
    try std.testing.expect(root.children.items[0] == ctx.popover_portal_root.?);
}

test "Sheet: content taller than the panel stays inside it on every side (a scrolling column over a footer)" {
    inline for (.{ SheetSide.left, SheetSide.right, SheetSide.top, SheetSide.bottom }) |s| {
        var ctx = try Cx.init(std.testing.allocator, std.testing.io);
        defer ctx.deinit();
        ctx.setViewport(800, 600);
        const root = try box(ctx, .{ .width = .{ .px = 800 }, .height = .{ .px = 600 } }, .{});
        ctx.root = root;
        const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
        defer scope.dispose();
        const result = try Sheet(.{ .side = s, .width = 300, .height = 240, .open = true }).mount(scope, ctx);
        if (!result.portaled) try root.appendChild(std.testing.allocator, result.overlay);
        // A column that clips / scrolls its own content (min 0), then a fixed footer.
        const column = try core.adoptChild(ctx, std.testing.allocator, result.content, try box(ctx, .{ .width = .{ .grow = .{} }, .height = .{ .grow = .{} }, .min_height = 0, .direction = .column, .overflow_hidden = true }, .{}));
        _ = try core.adoptChild(ctx, std.testing.allocator, column, try box(ctx, .{ .width = .{ .px = 50 }, .height = .{ .px = 1000 }, .flex_shrink = 0 }, .{}));
        const foot = try core.adoptChild(ctx, std.testing.allocator, result.content, try box(ctx, .{ .width = .{ .grow = .{} }, .height = .{ .px = 40 }, .flex_shrink = 0 }, .{}));
        ctx.layout();
        const panel = result.panel.rectFromWorldOrFallback();
        const content = result.content.rectFromWorldOrFallback();
        try std.testing.expect(panel.h > 0 and panel.h <= 600);
        try std.testing.expect(content.y + content.h <= panel.h + 0.5);
        const f = foot.rectFromWorldOrFallback();
        try std.testing.expect(content.y + f.y + f.h <= panel.h + 0.5);
        try std.testing.expect(column.rectFromWorldOrFallback().h < 1000);
    }
}

// Test collection from styles.zig; this line required (see docs/STYLING.md).
test {
    _ = @import("styles.zig");
}

// Per-allocation OOM sweep (see src/ui/components/oom_sweep.zig).
test "sheet: mount 在任意分配点失败时不泄漏（sweep）" {
    try @import("../oom_sweep.zig").sweepMount("sheet", struct {
        fn m(scope: *Scope, cx: *Cx) anyerror!?*Node {
            const r = try Sheet(.{}).mount(scope, cx);
            return r.overlay;
        }
    }.m);
}

test "Sheet: a closed Sheet's content is not in the Tab order" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setViewport(800, 600);
    const root = try core.box(ctx, .{ .width = .{ .px = 800 }, .height = .{ .px = 600 } }, .{});
    ctx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const outside = try core.box(ctx, .{ .width = .{ .px = 100 }, .height = .{ .px = 30 } }, .{});
    outside.behavior.interaction.focusable = true;
    try root.appendChild(std.testing.allocator, outside);
    const open = try scope.createSignal(bool, false);
    const r = try Sheet(.{ .open = open }).mount(scope, ctx);
    if (!r.portaled) try root.appendChild(std.testing.allocator, r.overlay);
    const inside = try core.box(ctx, .{ .width = .{ .px = 100 }, .height = .{ .px = 30 } }, .{});
    inside.behavior.interaction.focusable = true;
    try r.content.appendChild(std.testing.allocator, inside);
    ctx.layout();
    for (0..3) |_| {
        ctx.handleKeyDown(.tab, .{});
        try std.testing.expect(ctx.focus_manager.getFocused() == outside);
    }
    open.set(true);
    ctx.layout();
    try std.testing.expect(ctx.focus_manager.getFocused() == inside);
}
