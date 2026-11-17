//! popover_test.zig: Popover/overlay positioning and lifecycle unit tests.
//!
//! Split out of popover.zig to keep it implementation-only. Needs an explicit
//! `_ = @import(...)` in components/mod.zig or upstream for the test runner to collect
//! it; Zig's refAllDecls only recurses modules referenced in this file.

const std = @import("std");
const core = @import("../../core.zig");
const Cx = core.Cx;
const Node = core.Node;
const box = core.box;
const Color = core.Color;
const Signal = core.Signal;
const Scope = @import("../../reactive.zig").Scope;
const animation = @import("../../animation/mod.zig");
const overlay_stack_mod = @import("../../overlay_stack.zig");
const render_engine = @import("../../core/render_engine/mod.zig");
const floating = @import("../../compute_position.zig");
const popover_mod = @import("mod.zig");
const Popover = popover_mod.Popover;
const PopoverPosition = popover_mod.PopoverPosition;
const AnchorRect = popover_mod.AnchorRect;
const PopoverPositionCtx = popover_mod.PopoverPositionCtx;
const transformOriginForPlacement = popover_mod.transformOriginForPlacement;
const popoverBeforeRender = popover_mod.popoverBeforeRender;
const HIDDEN_OPACITY: f32 = 0.001;

// ========== Tests ==========

test "Popover: basic structure" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const result = try Popover(.{}).mount(scope, ctx);

    try root.appendChild(std.testing.allocator, result.wrapper);

    // Hidden content is retained off-tree until the popover opens.
    try std.testing.expectEqual(@as(usize, 1), result.wrapper.children.items.len);
    try std.testing.expect(result.content.parent == null);

    // Initially hidden
    try std.testing.expectEqual(core.Sizing{ .px = 0 }, result.content.style.width);
    // Default placement is .bottom_start -> transform_origin = (0%, 0%) -> (0, 0).
    const origin = result.content.style.transform_origin().resolve(200, 100);
    try std.testing.expectApproxEqAbs(@as(f32, 0), origin.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), origin.y, 0.001);
}

test "Popover: every trigger mode keeps floating content in the window portal" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try box(ctx, .{
        .width = .{ .px = 400 },
        .height = .{ .px = 300 },
    }, .{});
    ctx.root = root;

    const portal = try box(ctx, .{
        .position = .absolute,
        .width = .{ .grow = .{} },
        .height = .{ .grow = .{} },
    }, .{});
    try root.appendChild(std.testing.allocator, portal);
    ctx.popover_portal_root = portal;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const triggers = [_]popover_mod.PopoverTrigger{ .click, .hover, .manual };
    for (triggers) |trigger| {
        const result = try Popover(.{
            .trigger = trigger,
            // Keep the closed node attached so this test can assert its stable
            // host without coupling to the visibility lifecycle.
            .detach_hidden_content = false,
        }).mount(scope, ctx);

        try std.testing.expect(!result.portaled);
        try std.testing.expect(result.wrapper.parent == null);
        try std.testing.expectEqual(@as(usize, 1), result.wrapper.children.items.len);
        try std.testing.expect(result.wrapper.children.items[0] == result.trigger);
        try std.testing.expect(result.chrome.parent == portal);
        try std.testing.expect(!result.chrome.isDescendantOf(result.wrapper));

        // The caller always owns placement of the trigger wrapper, including
        // manual mode; only the floating panel is out-of-flow.
        try root.appendChild(std.testing.allocator, result.wrapper);
    }
}

test "Popover: transform origin tracks placement" {
    const cases = [_]struct {
        placement: PopoverPosition,
        expected_x: f32,
        expected_y: f32,
    }{
        .{ .placement = .top_start, .expected_x = 0, .expected_y = 100 },
        .{ .placement = .top, .expected_x = 100, .expected_y = 100 },
        .{ .placement = .top_end, .expected_x = 200, .expected_y = 100 },
        .{ .placement = .bottom_start, .expected_x = 0, .expected_y = 0 },
        .{ .placement = .bottom, .expected_x = 100, .expected_y = 0 },
        .{ .placement = .bottom_end, .expected_x = 200, .expected_y = 0 },
        .{ .placement = .left_start, .expected_x = 200, .expected_y = 0 },
        .{ .placement = .left, .expected_x = 200, .expected_y = 50 },
        .{ .placement = .left_end, .expected_x = 200, .expected_y = 100 },
        .{ .placement = .right_start, .expected_x = 0, .expected_y = 0 },
        .{ .placement = .right, .expected_x = 0, .expected_y = 50 },
        .{ .placement = .right_end, .expected_x = 0, .expected_y = 100 },
    };

    for (cases) |case| {
        const origin = transformOriginForPlacement(case.placement).resolve(200, 100);
        try std.testing.expectApproxEqAbs(case.expected_x, origin.x, 0.001);
        try std.testing.expectApproxEqAbs(case.expected_y, origin.y, 0.001);
    }
}

test "Popover: virtual anchor returns dynamic rect" {
    // Verify PopoverPositionCtx.anchorRect() returns correct rect under all three effective_anchor
    // modes
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const root = try box(ctx, .{}, .{});
    ctx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const trigger = try box(ctx, .{ .width = .{ .px = 100 }, .height = .{ .px = 20 } }, .{});
    trigger.setLayoutRect(.{ .x = 50, .y = 60, .w = 100, .h = 20 });
    try root.appendChild(std.testing.allocator, trigger);

    // self_trigger
    {
        const open = try scope.createSignal(bool, true);
        const popover = try box(ctx, .{}, .{});
        try root.appendChild(std.testing.allocator, popover);
        var pctx = PopoverPositionCtx{
            .popover = popover,
            .scope = scope,
            .trigger_node = trigger,
            .effective_anchor = .self_trigger,
            .is_open = .{ .signal = open },
            .layer_handle = .{ .id = 0, .z_index = 0 },
            .pos = .bottom_start,
            .offset = .{ .static = 0 },
            .cx = ctx,
            .flip = false,
            .fallback_placements = &.{},
            .fallback_placements_ptr = null,
            .preferred_width = null,
            .preferred_max_width = null,
            .preferred_max_height = null,
            .match_trigger_width = false,
            .constrain_width_to_viewport = false,
            .viewport_padding = 0,
            .active_position = .bottom_start,
            .entry_ready = false,
            .prewarmed_ready = false,
            .is_visible = false,
            .prewarm_hidden_layout = false,
            .enter_transition = .none,
            .exit_transition = .none,
        };
        const r = pctx.anchorRect();
        try std.testing.expectEqual(@as(f32, 100), r.w);
        try std.testing.expectEqual(@as(f32, 20), r.h);
    }

    // virtual
    {
        const StateVirt = struct {
            var x: f32 = 200;
            var y: f32 = 300;
            fn cb(_: *anyopaque) AnchorRect {
                return .{ .x = x, .y = y, .w = 0, .h = 18 };
            }
        };
        const open = try scope.createSignal(bool, true);
        const popover = try box(ctx, .{}, .{});
        try root.appendChild(std.testing.allocator, popover);
        var dummy: u32 = 0;
        var pctx = PopoverPositionCtx{
            .popover = popover,
            .scope = scope,
            .trigger_node = trigger,
            .effective_anchor = .{ .virtual = .{ .ctx = @ptrCast(&dummy), .getRect = StateVirt.cb } },
            .is_open = .{ .signal = open },
            .layer_handle = .{ .id = 0, .z_index = 0 },
            .pos = .bottom_start,
            .offset = .{ .static = 0 },
            .cx = ctx,
            .flip = false,
            .fallback_placements = &.{},
            .fallback_placements_ptr = null,
            .preferred_width = null,
            .preferred_max_width = null,
            .preferred_max_height = null,
            .match_trigger_width = false,
            .constrain_width_to_viewport = false,
            .viewport_padding = 0,
            .active_position = .bottom_start,
            .entry_ready = false,
            .prewarmed_ready = false,
            .is_visible = false,
            .prewarm_hidden_layout = false,
            .enter_transition = .none,
            .exit_transition = .none,
        };
        // First read
        const r1 = pctx.anchorRect();
        try std.testing.expectEqual(@as(f32, 200), r1.x);
        try std.testing.expectEqual(@as(f32, 300), r1.y);
        try std.testing.expectEqual(@as(f32, 18), r1.h);

        // Move anchor -> second read returns new value (key reactive anchor capability)
        StateVirt.x = 400;
        StateVirt.y = 500;
        const r2 = pctx.anchorRect();
        try std.testing.expectEqual(@as(f32, 400), r2.x);
        try std.testing.expectEqual(@as(f32, 500), r2.y);
    }
}

test "Popover: mount with virtual anchor stores effective_anchor correctly" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const root = try box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    ctx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const VAnchor = struct {
        fn cb(_: *anyopaque) AnchorRect {
            return .{ .x = 100, .y = 200, .w = 0, .h = 16 };
        }
    };
    var dummy: u32 = 0;
    const result = try Popover(.{
        .trigger = .manual,
        .anchor = popover_mod.Anchor{ .virtual = .{ .ctx = @ptrCast(&dummy), .getRect = VAnchor.cb } },
    }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, result.wrapper);

    // Extract position_ctx and verify effective_anchor is virtual
    const pctx: *PopoverPositionCtx = @ptrCast(@alignCast(result.content.meta.per_frame.hooks.slots.anim_state.?));
    try std.testing.expect(pctx.effective_anchor == .virtual);
    const r = pctx.anchorRect();
    try std.testing.expectEqual(@as(f32, 100), r.x);
    try std.testing.expectEqual(@as(f32, 200), r.y);
}

test "Popover: toggle open/close" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const result = try Popover(.{}).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, result.wrapper);
    try std.testing.expect(result.content.parent == null);

    // Open
    result.open.?.set(true);
    try std.testing.expect(result.open.?.peek());
    try std.testing.expect(result.content.parent == ctx.popover_portal_root.?);

    // Close
    result.open.?.set(false);
    try std.testing.expect(!result.open.?.peek());
}

test "Popover: hidden content detaches from window portal after close commits" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const result = try Popover(.{
        .enter_transition = .none,
        .exit_transition = .none,
    }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, result.wrapper);

    try std.testing.expectEqual(@as(usize, 1), result.wrapper.children.items.len);
    try std.testing.expect(result.content.parent == null);

    result.open.?.set(true);
    try std.testing.expectEqual(@as(usize, 1), result.wrapper.children.items.len);
    try std.testing.expect(result.content.parent == ctx.popover_portal_root.?);

    const position_ctx: *PopoverPositionCtx = @ptrCast(@alignCast(result.content.meta.per_frame.hooks.slots.anim_state.?));
    position_ctx.entry_ready = true;
    position_ctx.is_visible = true;

    result.open.?.set(false);
    popoverBeforeRender(result.content);

    try std.testing.expectEqual(@as(usize, 1), result.wrapper.children.items.len);
    try std.testing.expect(result.content.parent == null);
    try std.testing.expect(!position_ctx.entry_ready);
    try std.testing.expect(!position_ctx.is_visible);
}

test "Popover: reopening during the exit transition cancels the pending close" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const result = try Popover(.{
        .enter_transition = .fade_fast,
        .exit_transition = .fade_fast,
    }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, result.wrapper);

    result.open.?.set(true);
    result.open.?.set(false);
    var layer_ptr: ?*overlay_stack_mod.OverlayLayer = null;
    for (ctx.overlay_stack.layers.items) |*slot| {
        if (slot.*) |*l| layer_ptr = l;
    }
    const layer = layer_ptr.?;
    const handle = layer.handle;
    try std.testing.expectEqual(overlay_stack_mod.LayerState.exiting, layer.state);

    // Reopen before the fade-out finishes (completion list re-shown on `.`).
    result.open.?.set(true);
    try std.testing.expect(layer.state != .exiting);

    // Play well past the fade: the old exit must not commit and close it.
    _ = handle;
    var t: f64 = render_engine.current_frame_time_ms;
    for (0..60) |_| {
        t += 16;
        _ = ctx.overlay_stack.tick(t, 0.016, 400, 300, std.testing.allocator);
    }
    try std.testing.expect(result.open.?.peek());
    try std.testing.expect(!layer.suspended);
}

fn onlyLayer(ctx: *Cx) *overlay_stack_mod.OverlayLayer {
    var layer_ptr: ?*overlay_stack_mod.OverlayLayer = null;
    for (ctx.overlay_stack.layers.items) |*slot| {
        if (slot.*) |*l| layer_ptr = l;
    }
    return layer_ptr.?;
}

test "Popover: mounted open shows the open state at once; later opens animate" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setViewport(640, 480);
    const root = try box(ctx, .{ .width = .{ .px = 640 }, .height = .{ .px = 480 } }, .{});
    ctx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const open = try scope.createSignal(bool, true);
    const result = try Popover(.{ .open = open, .position = .bottom_start }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, result.wrapper);
    try result.trigger.appendChild(std.testing.allocator, try box(ctx, .{ .width = .{ .px = 120 }, .height = .{ .px = 32 } }, .{}));
    try result.content.appendChild(std.testing.allocator, try core.text(ctx, "Already open", .{}));

    const layer = onlyLayer(ctx);
    try std.testing.expectEqual(overlay_stack_mod.LayerState.visible, layer.state);
    try std.testing.expect(!layer.suspended);

    // The first frame that shows the content shows it fully: no scale_fade intermediate.
    var now_ms: f64 = render_engine.current_frame_time_ms;
    var first_visible: ?f32 = null;
    for (0..6) |_| {
        now_ms += 16;
        render_engine.current_frame_time_ms = now_ms;
        render_engine.current_frame_dt_ms = 16;
        ctx.layout();
        _ = ctx.render();
        const opacity = result.chrome.getOpacity();
        if (first_visible == null and opacity > HIDDEN_OPACITY + 0.0001) {
            first_visible = opacity;
            try std.testing.expectEqual(@as(f32, 1), result.chrome.style.scale_x());
        }
    }
    try std.testing.expectEqual(@as(?f32, 1), first_visible);

    // Closing still plays the exit transition, and reopening plays the enter transition.
    open.set(false);
    try std.testing.expectEqual(overlay_stack_mod.LayerState.exiting, layer.state);
    for (0..60) |_| {
        now_ms += 16;
        _ = ctx.overlay_stack.tick(now_ms, 0.016, 640, 480, std.testing.allocator);
    }
    try std.testing.expect(layer.suspended);
    open.set(true);
    try std.testing.expectEqual(overlay_stack_mod.LayerState.entering, layer.state);
}

fn flippedDropdown(ctx: *Cx, scope: *Scope, open: *core.Signal(bool)) !popover_mod.PopoverResult {
    ctx.setViewport(640, 480);
    const root = try box(ctx, .{ .width = .{ .px = 640 }, .height = .{ .px = 480 }, .direction = .column }, .{});
    ctx.root = root;
    // The trigger sits near the bottom: a 120 px panel below it overflows, so it flips to top.
    try root.appendChild(std.testing.allocator, try box(ctx, .{ .width = .{ .px = 10 }, .height = .{ .px = 420 } }, .{}));
    const result = try Popover(.{ .open = open, .position = .bottom_start, .enter_transition = .dropdown, .exit_transition = .dropdown }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, result.wrapper);
    try result.trigger.appendChild(std.testing.allocator, try box(ctx, .{ .width = .{ .px = 120 }, .height = .{ .px = 32 } }, .{}));
    try result.content.appendChild(std.testing.allocator, try box(ctx, .{ .width = .{ .px = 160 }, .height = .{ .px = 120 } }, .{}));
    return result;
}

test "Popover: a dropdown mounted open lands at rest on its first opaque frame" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const open = try scope.createSignal(bool, true);
    const result = try flippedDropdown(ctx, scope, open);
    var now_ms: f64 = render_engine.current_frame_time_ms;
    var first_y: ?f32 = null;
    for (0..8) |_| {
        renderFrames(ctx, &now_ms, 1);
        if (first_y == null and result.chrome.getOpacity() > 0.999) first_y = result.chrome.style.translate_y;
    }
    try std.testing.expect(first_y != null);
    try std.testing.expectEqual(PopoverPosition.top_start, result.active_position_ptr.*);
    try std.testing.expectApproxEqAbs(result.chrome.style.translate_y, first_y.?, 0.01);
}

test "Popover: a flipped dropdown exits toward its anchor" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const open = try scope.createSignal(bool, true);
    const result = try flippedDropdown(ctx, scope, open);
    var now_ms: f64 = render_engine.current_frame_time_ms;
    renderFrames(ctx, &now_ms, 8);
    try std.testing.expectEqual(PopoverPosition.top_start, result.active_position_ptr.*);
    const rest_y = result.chrome.style.translate_y;
    open.set(false);
    renderFrames(ctx, &now_ms, 4);
    // Mid-exit the panel above its trigger has slid down (toward the trigger), not up.
    try std.testing.expect(result.chrome.getOpacity() > 0.001);
    try std.testing.expect(result.chrome.style.translate_y > rest_y + 0.1);
}

test "Popover: animate_initial_open plays the enter transition for a popover mounted open" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const root = try box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    ctx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const open = try scope.createSignal(bool, true);
    const result = try Popover(.{ .open = open, .animate_initial_open = true }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, result.wrapper);
    try std.testing.expectEqual(overlay_stack_mod.LayerState.entering, onlyLayer(ctx).state);
}

test "Popover: external visible signal" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const vis = try scope.createSignal(bool, false);
    const result = try Popover(.{ .open = vis }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, result.wrapper);

    // External control
    try std.testing.expect(result.open.? == vis);
    vis.set(true);
    try std.testing.expect(vis.peek());
}

test "Popover: an open anchor leaving the viewport dismisses the panel" {
    const a = std.testing.allocator;
    const cx = try Cx.init(a, std.testing.io);
    defer cx.deinit();
    cx.setViewport(400, 300);
    const root = try box(cx, .{ .width = .fixed(400), .height = .fixed(300) }, .{});
    cx.root = root;
    const scope = try Scope.init(a, null, cx.owner);
    defer scope.dispose();
    var anchor_x: f32 = 50;
    const pop = try Popover(.{
        .trigger = .manual,
        .close_on_anchor_scroll = true,
        .anchor = .{ .virtual = .{
            .ctx = &anchor_x,
            .getRect = struct {
                fn rect(raw: *anyopaque) popover_mod.AnchorRect {
                    const x: *f32 = @ptrCast(@alignCast(raw));
                    return .{ .x = x.*, .y = 50, .w = 10, .h = 10 };
                }
            }.rect,
        } },
        .enter_transition = .none,
        .exit_transition = .none,
    }).mount(scope, cx);
    try root.appendChild(a, pop.wrapper);
    try pop.content.appendChild(a, try box(cx, .{ .width = .fixed(100), .height = .fixed(40) }, .{}));
    var now_ms: f64 = 0;
    openPopoverForConsumeTest(cx, pop, &now_ms);
    try std.testing.expect(pop.open.?.peek());
    anchor_x = 410;
    cx.frame_time_ms += 16;
    pop.chrome.markRenderDirty();
    cx.layout();
    _ = cx.render();
    try std.testing.expect(!pop.open.?.peek());
}

test "Popover: high contrast updates chrome without changing its layout" {
    const a = std.testing.allocator;
    const cx = try Cx.init(a, std.testing.io);
    defer cx.deinit();
    cx.setViewport(400, 300);
    cx.setTheme(&core.theme.light);
    const root = try box(cx, .{ .width = .fixed(400), .height = .fixed(300) }, .{});
    cx.root = root;
    const scope = try Scope.init(a, null, cx.owner);
    defer scope.dispose();
    const pop = try Popover(.{ .trigger = .manual, .enter_transition = .none }).mount(scope, cx);
    try root.appendChild(a, pop.wrapper);
    try pop.trigger.appendChild(a, try box(cx, .{ .width = .fixed(20), .height = .fixed(20) }, .{}));
    try pop.content.appendChild(a, try box(cx, .{ .width = .fixed(100), .height = .fixed(40) }, .{}));
    var now_ms: f64 = 0;
    openPopoverForConsumeTest(cx, pop, &now_ms);
    const bounds = pop.chrome.globalRect();
    try std.testing.expect(pop.chrome.style.getExt().shadows[0].color.a > 0);
    cx.setTheme(&core.theme.high_contrast);
    cx.layout();
    _ = cx.render();
    try std.testing.expectEqual(bounds, pop.chrome.globalRect());
    try std.testing.expectEqual(@as(u8, 0), pop.chrome.style.getExt().shadows[0].color.a);
    try std.testing.expectEqual(core.theme.high_contrast.tokens.color.border, pop.chrome.style.border.color);
}

test "Popover: a height-capped scroll panel derives width from its content" {
    const a = std.testing.allocator;
    const cx = try Cx.init(a, std.testing.io);
    defer cx.deinit();
    cx.setViewport(400, 300);
    const root = try box(cx, .{ .width = .fixed(400), .height = .fixed(300) }, .{});
    cx.root = root;
    const scope = try Scope.init(a, null, cx.owner);
    defer scope.dispose();
    const pop = try Popover(.{
        .trigger = .manual,
        .enter_transition = .none,
        .size_policy = .fit_or_scroll,
        .max_height = 80,
    }).mount(scope, cx);
    try root.appendChild(a, pop.wrapper);
    try pop.trigger.appendChild(a, try box(cx, .{ .width = .fixed(20), .height = .fixed(20) }, .{}));
    try pop.content.appendChild(a, try box(cx, .{ .width = .fixed(100), .height = .fixed(140) }, .{}));
    var now_ms: f64 = 0;
    openPopoverForConsumeTest(cx, pop, &now_ms);
    try std.testing.expectApproxEqAbs(@as(f32, 100), pop.chrome.globalRect().w, 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 80), pop.chrome.globalRect().h, 0.5);
    try std.testing.expect(pop.content.globalRect().h >= 140);
}

test "Popover: hover trigger" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const result = try Popover(.{ .trigger = .hover }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, result.wrapper);

    // Hover trigger
    try std.testing.expect(result.wrapper.behavior.events.on_hover != null);
    try std.testing.expect(result.wrapper.behavior.events.on_leave != null);

    result.wrapper.behavior.events.on_hover.?.invoke();
    try std.testing.expect(result.open.?.peek());

    result.wrapper.behavior.events.on_leave.?.invoke();
    try std.testing.expect(!result.open.?.peek());
}

test "Popover: before_render preserves overlay-managed opacity and scale" {
    // Overlay-aware before_render must not reset opacity to HIDDEN_OPACITY (the
    // overlay_visual_in_progress logic already reads flags + opacity/scale midstate).
    //
    // Fixture requirements:
    //   1. Use a real `ctx.overlay_stack.push()` handle bound to content_node; a fake
    //      `.layer_handle = .{ .id = 0, .z_index = 0 }` makes findLayer find no layer,
    //      so the overlay path is never entered.
    //   2. Use setLayoutRect / meta.per_frame.hooks.slots (rect lives in the World SoA,
    //      hooks in meta.per_frame.hooks).
    //   3. Clear layout dirty first: manual nodes default to layout dirty and take the
    //      'pause unstable-layout' branch, which **should** suppress opacity.
    //   4. Don't assert an interim opacity (0.35) is preserved: on enter ready,
    //      before_render calls setEnterPaused(handle, false) and OverlayStack then
    //      `enter_ctrl.apply(content)` writes opacity by progress (0 -> 0). Opacity
    //      ownership shifts to the overlay controller.
    // True invariant: the hook doesn't reset opacity to HIDDEN_OPACITY and enter proceeds.
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setViewport(640, 480);

    const root = try box(ctx, .{ .width = .{ .px = 640 }, .height = .{ .px = 480 } }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const trigger = try box(ctx, .{ .width = .{ .px = 120 }, .height = .{ .px = 32 } }, .{});
    const content = try box(ctx, .{ .position = .absolute, .width = .{ .px = 160 }, .height = .{ .px = 72 } }, .{});
    try root.appendChild(std.testing.allocator, trigger);
    try root.appendChild(std.testing.allocator, content);

    trigger.setLayoutRect(.{ .x = 40, .y = 24, .w = 120, .h = 32 });
    content.setLayoutRect(.{ .x = 0, .y = 0, .w = 160, .h = 72 });
    content.style.overflow_hidden = false;
    // Manual nodes default layout dirty, take 'pause unstable-layout' branch (should suppress
    // opacity). Test verifies enter animation midstate with **stable layout**; clear dirty
    // first (same as 'pauses enter until content subtree is ready').
    content.frame_state.state_bits.dirty.core.layout = false;
    content.frame_state.state_bits.dirty.core.subtree_layout = false;

    // Real overlay layer (not fake handle), mid-enter animation: opacity/scale are overlay
    // animation midvalues.
    const handle = try ctx.overlay_stack.push(.{
        .kind = .non_modal,
        .dismiss = .{},
        .enter_transition = .scale_fade,
        .exit_transition = .scale_fade,
    });
    if (ctx.overlay_stack.findLayer(handle)) |layer| {
        layer.content_node = content;
    }

    content.setOpacityRaw(0.35);
    const ext = content.style.ensureExtPanic(std.testing.allocator);
    ext.scale_x = 0.92;
    ext.scale_y = 0.94;
    content.frame_state.state_bits.flags.manual_opacity_animation_active = true;
    content.frame_state.state_bits.flags.manual_transform_animation_active = true;

    const open = try scope.createSignal(bool, true);
    var position_ctx = PopoverPositionCtx{
        .popover = content,
        .scope = scope,
        .trigger_node = trigger,
        .effective_anchor = .self_trigger,
        .is_open = .{ .signal = open },
        .layer_handle = handle,
        .pos = .bottom_start,
        .offset = .{ .static = 8 },
        .cx = ctx,
        .flip = false,
        .preferred_width = null,
        .preferred_max_width = null,
        .preferred_max_height = null,
        .match_trigger_width = false,
        .constrain_width_to_viewport = false,
        .viewport_padding = 8,
        .active_position = .bottom_start,
        .entry_ready = false,
        .prewarmed_ready = false,
        .is_visible = false,
        .prewarm_hidden_layout = true,
        .enter_transition = .scale_fade,
        .exit_transition = .scale_fade,
    };
    content.meta.per_frame.hooks.slots.anim_state = @ptrCast(&position_ctx);

    popoverBeforeRender(content);

    // Invariant 1: with stable layout, hook must not reset popover to hidden-waiting state
    // (HIDDEN_OPACITY~0.001). That's pause-branch behavior; here means popup flashes.
    try std.testing.expect(content.getOpacity() != HIDDEN_OPACITY);

    // Invariant 2: enter proceeds, ownership moves to overlay controller; opacity written by
    // enter_ctrl per animation progress (progress=0 -> 0); scale likewise returns to transition
    // start.
    try std.testing.expect(position_ctx.entry_ready);
    try std.testing.expect(position_ctx.is_visible);
    try std.testing.expect(!ctx.overlay_stack.findLayer(handle).?.enter_paused);

    // Invariant 3: positioning applied (popup below trigger, not at 0).
    try std.testing.expect(content.style.translate_y > 0);
}

test "Popover: none transition becomes opaque when positioned" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setViewport(640, 480);

    const root = try box(ctx, .{ .width = .{ .px = 640 }, .height = .{ .px = 480 } }, .{});
    ctx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const trigger = try box(ctx, .{ .width = .{ .px = 120 }, .height = .{ .px = 32 } }, .{});
    const content = try box(ctx, .{ .position = .absolute, .width = .{ .px = 160 }, .height = .{ .px = 72 } }, .{});
    try root.appendChild(std.testing.allocator, trigger);
    try root.appendChild(std.testing.allocator, content);
    trigger.setLayoutRect(.{ .x = 40, .y = 24, .w = 120, .h = 32 });
    content.setLayoutRect(.{ .x = 0, .y = 0, .w = 160, .h = 72 });
    content.style.overflow_hidden = false;
    content.setOpacityRaw(0);
    content.frame_state.state_bits.dirty.core.layout = false;
    content.frame_state.state_bits.dirty.core.subtree_layout = false;

    const handle = try ctx.overlay_stack.push(.{
        .kind = .non_modal,
        .dismiss = .{},
        .enter_transition = .none,
        .exit_transition = .none,
    });
    if (ctx.overlay_stack.findLayer(handle)) |layer| layer.content_node = content;

    const open = try scope.createSignal(bool, true);
    var position_ctx = PopoverPositionCtx{
        .popover = content,
        .scope = scope,
        .trigger_node = trigger,
        .effective_anchor = .self_trigger,
        .is_open = .{ .signal = open },
        .layer_handle = handle,
        .pos = .bottom_start,
        .offset = .{ .static = 8 },
        .cx = ctx,
        .flip = false,
        .preferred_width = null,
        .preferred_max_width = null,
        .preferred_max_height = null,
        .match_trigger_width = false,
        .constrain_width_to_viewport = false,
        .viewport_padding = 8,
        .active_position = .bottom_start,
        .entry_ready = false,
        .prewarmed_ready = false,
        .is_visible = false,
        .prewarm_hidden_layout = false,
        .enter_transition = .none,
        .exit_transition = .none,
    };
    content.meta.per_frame.hooks.slots.anim_state = @ptrCast(&position_ctx);

    popoverBeforeRender(content);

    try std.testing.expect(position_ctx.entry_ready);
    try std.testing.expect(position_ctx.is_visible);
    try std.testing.expectEqual(@as(f32, 1), content.getOpacity());
    try std.testing.expect(content.style.translate_y > 0);
}

test "Popover: before_render keeps active exiting layer visible until commit" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    ctx.root = root;

    const trigger = try box(ctx, .{ .width = .{ .px = 120 }, .height = .{ .px = 32 } }, .{});
    const content = try box(ctx, .{ .position = .absolute, .width = .{ .px = 160 }, .height = .{ .px = 72 } }, .{});
    try root.appendChild(std.testing.allocator, trigger);
    try root.appendChild(std.testing.allocator, content);

    trigger.setLayoutRect(.{ .x = 40, .y = 24, .w = 120, .h = 32 });
    content.setLayoutRect(.{ .x = 0, .y = 0, .w = 160, .h = 72 });
    content.style.overflow_hidden = false;
    content.setOpacityRaw(1);

    const handle = try ctx.overlay_stack.push(.{
        .kind = .non_modal,
        .dismiss = .{},
        .enter_transition = .scale_fade,
        .exit_transition = .scale_fade,
    });
    if (ctx.overlay_stack.findLayer(handle)) |layer| {
        layer.content_node = content;
    }
    ctx.overlay_stack.beginExit(handle);

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const open = try scope.createSignal(bool, false);
    var position_ctx = PopoverPositionCtx{
        .popover = content,
        .scope = scope,
        .trigger_node = trigger,
        .effective_anchor = .self_trigger,
        .is_open = .{ .signal = open },
        .layer_handle = handle,
        .pos = .bottom_start,
        .offset = .{ .static = 8 },
        .cx = ctx,
        .flip = false,
        .preferred_width = null,
        .preferred_max_width = null,
        .preferred_max_height = null,
        .match_trigger_width = false,
        .constrain_width_to_viewport = false,
        .viewport_padding = 8,
        .active_position = .bottom_start,
        .entry_ready = false,
        .prewarmed_ready = false,
        .is_visible = false,
        .prewarm_hidden_layout = true,
        .enter_transition = .scale_fade,
        .exit_transition = .scale_fade,
    };
    content.meta.per_frame.hooks.slots.anim_state = @ptrCast(&position_ctx);

    popoverBeforeRender(content);

    try std.testing.expectEqual(@as(f32, 160), content.style.width.px);
    try std.testing.expectEqual(@as(f32, 72), content.style.height.px);
    try std.testing.expect(!content.style.overflow_hidden);
}

test "Popover: before_render pauses enter until content subtree is ready" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setViewport(640, 480);

    const root = try box(ctx, .{ .width = .{ .px = 640 }, .height = .{ .px = 480 } }, .{});
    ctx.root = root;

    const trigger = try box(ctx, .{ .width = .{ .px = 120 }, .height = .{ .px = 32 } }, .{});
    const content = try box(ctx, .{ .position = .absolute, .width = .{ .px = 160 }, .height = .{ .px = 72 } }, .{});
    try root.appendChild(std.testing.allocator, trigger);
    try root.appendChild(std.testing.allocator, content);

    trigger.setLayoutRect(.{ .x = 40, .y = 24, .w = 120, .h = 32 });
    content.setLayoutRect(.{ .x = 0, .y = 0, .w = 160, .h = 72 });
    // Not ready = **layout unstable**. popoverContentReady deliberately does not check
    // subtree_render: requiring it deadlocks a fresh overlay (a hidden subtree can't paint
    // its first frame before positioning is ready, but positioning waits for that frame).
    // See popover/mod.zig:popoverContentReady comment.
    content.frame_state.state_bits.dirty.core.subtree_render = true;
    content.frame_state.state_bits.dirty.core.subtree_layout = true;
    content.frame_state.state_bits.dirty.core.layout = false;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const open = try scope.createSignal(bool, true);

    const handle = try ctx.overlay_stack.push(.{
        .kind = .non_modal,
        .dismiss = .{},
        .enter_transition = .scale_fade,
        .exit_transition = .scale_fade,
    });
    ctx.overlay_stack.reactivate(handle);

    var position_ctx = PopoverPositionCtx{
        .popover = content,
        .scope = scope,
        .trigger_node = trigger,
        .effective_anchor = .self_trigger,
        .is_open = .{ .signal = open },
        .layer_handle = handle,
        .pos = .bottom_start,
        .offset = .{ .static = 8 },
        .cx = ctx,
        .flip = false,
        .preferred_width = null,
        .preferred_max_width = null,
        .preferred_max_height = null,
        .match_trigger_width = false,
        .constrain_width_to_viewport = false,
        .viewport_padding = 8,
        .active_position = .bottom_start,
        .entry_ready = false,
        .prewarmed_ready = false,
        .is_visible = false,
        .prewarm_hidden_layout = true,
        .enter_transition = .scale_fade,
        .exit_transition = .scale_fade,
    };
    content.meta.per_frame.hooks.slots.anim_state = @ptrCast(&position_ctx);

    popoverBeforeRender(content);

    try std.testing.expect(!position_ctx.entry_ready);
    try std.testing.expect(!position_ctx.is_visible);
    try std.testing.expectApproxEqAbs(HIDDEN_OPACITY, content.getOpacity(), 0.0001);
    const layer = ctx.overlay_stack.findLayer(handle).?;
    try std.testing.expect(layer.enter_paused);
}

test "Popover: subtree_render 脏不阻止定位（死锁防回归）" {
    // Paired test: the previous one holds 'layout dirty => pause'; this holds the opposite:
    // only subtree_render dirty (layout stable) must position and become ready normally.
    //
    // If popoverContentReady regains a subtree_render readiness check, a fresh overlay
    // deadlocks (hidden subtree can't paint first frame before positioning is ready, but
    // positioning waits). That change fails this test.
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setViewport(640, 480);

    const root = try box(ctx, .{ .width = .{ .px = 640 }, .height = .{ .px = 480 } }, .{});
    ctx.root = root;

    const trigger = try box(ctx, .{ .width = .{ .px = 120 }, .height = .{ .px = 32 } }, .{});
    const content = try box(ctx, .{ .position = .absolute, .width = .{ .px = 160 }, .height = .{ .px = 72 } }, .{});
    try root.appendChild(std.testing.allocator, trigger);
    try root.appendChild(std.testing.allocator, content);

    trigger.setLayoutRect(.{ .x = 40, .y = 24, .w = 120, .h = 32 });
    content.setLayoutRect(.{ .x = 0, .y = 0, .w = 160, .h = 72 });
    // Layout clean, only render dirty; exactly 'freshly-opened hidden subtree' real state
    content.frame_state.state_bits.dirty.core.subtree_render = true;
    content.frame_state.state_bits.dirty.core.subtree_layout = false;
    content.frame_state.state_bits.dirty.core.layout = false;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const open = try scope.createSignal(bool, true);

    const handle = try ctx.overlay_stack.push(.{
        .kind = .non_modal,
        .dismiss = .{},
        .enter_transition = .scale_fade,
        .exit_transition = .scale_fade,
    });
    ctx.overlay_stack.reactivate(handle);

    var position_ctx = PopoverPositionCtx{
        .popover = content,
        .scope = scope,
        .trigger_node = trigger,
        .effective_anchor = .self_trigger,
        .is_open = .{ .signal = open },
        .layer_handle = handle,
        .pos = .bottom_start,
        .offset = .{ .static = 8 },
        .cx = ctx,
        .flip = false,
        .preferred_width = null,
        .preferred_max_width = null,
        .preferred_max_height = null,
        .match_trigger_width = false,
        .constrain_width_to_viewport = false,
        .viewport_padding = 8,
        .active_position = .bottom_start,
        .entry_ready = false,
        .prewarmed_ready = false,
        .is_visible = false,
        .prewarm_hidden_layout = true,
        .enter_transition = .scale_fade,
        .exit_transition = .scale_fade,
    };
    content.meta.per_frame.hooks.slots.anim_state = @ptrCast(&position_ctx);

    popoverBeforeRender(content);

    try std.testing.expect(position_ctx.entry_ready);
    const layer = ctx.overlay_stack.findLayer(handle).?;
    try std.testing.expect(!layer.enter_paused);
}

test "Popover: prewarmed hidden content reopens without ready-frame pause" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setViewport(640, 480);

    const root = try box(ctx, .{ .width = .{ .px = 640 }, .height = .{ .px = 480 } }, .{});
    ctx.root = root;

    const trigger = try box(ctx, .{ .width = .{ .px = 120 }, .height = .{ .px = 32 } }, .{});
    const content = try box(ctx, .{ .position = .absolute, .width = .{ .px = 160 }, .height = .{ .px = 72 } }, .{});
    try root.appendChild(std.testing.allocator, trigger);
    try root.appendChild(std.testing.allocator, content);

    trigger.setLayoutRect(.{ .x = 40, .y = 24, .w = 120, .h = 32 });
    content.setLayoutRect(.{ .x = 0, .y = 0, .w = 160, .h = 72 });
    content.setOpacityRaw(HIDDEN_OPACITY);
    const ext = content.style.ensureExtPanic(std.testing.allocator);
    ext.scale_x = 0.92;
    ext.scale_y = 0.92;
    content.frame_state.state_bits.dirty.core.subtree_render = false;
    content.frame_state.state_bits.dirty.core.subtree_layout = false;
    content.frame_state.state_bits.dirty.core.layout = false;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const open = try scope.createSignal(bool, false);

    const handle = try ctx.overlay_stack.push(.{
        .kind = .non_modal,
        .dismiss = .{},
        .enter_transition = .scale_fade,
        .exit_transition = .scale_fade,
    });
    if (ctx.overlay_stack.findLayer(handle)) |layer| {
        layer.content_node = content;
        layer.suspended = true;
    }

    var position_ctx = PopoverPositionCtx{
        .popover = content,
        .scope = scope,
        .trigger_node = trigger,
        .effective_anchor = .self_trigger,
        .is_open = .{ .signal = open },
        .layer_handle = handle,
        .pos = .bottom_start,
        .offset = .{ .static = 8 },
        .cx = ctx,
        .flip = false,
        .preferred_width = null,
        .preferred_max_width = null,
        .preferred_max_height = null,
        .match_trigger_width = false,
        .constrain_width_to_viewport = false,
        .viewport_padding = 8,
        .active_position = .bottom_start,
        .entry_ready = false,
        .prewarmed_ready = false,
        .is_visible = false,
        .prewarm_hidden_layout = true,
        .enter_transition = .scale_fade,
        .exit_transition = .scale_fade,
    };
    content.meta.per_frame.hooks.slots.anim_state = @ptrCast(&position_ctx);

    popoverBeforeRender(content);

    open.set(true);
    ctx.overlay_stack.reactivate(handle);
    popoverBeforeRender(content);

    try std.testing.expect(position_ctx.entry_ready);
    try std.testing.expect(position_ctx.is_visible);
    try std.testing.expect(!ctx.overlay_stack.findLayer(handle).?.enter_paused);
}

test "Popover: prewarm keeps content measurable after close (reopen fast-path)" {
    // Initial closed state: content.rect stays 0 (layer suspended, popoverBeforeRender
    // early-returns
    // before prewarm size recovery), independent of settle frames or prewarm setting.
    // prewarm_hidden_layout means 'after opened once, keep measured layout when closed so reopen
    // needs
    // no ready-frame', not 'pre-measure before first open'. So: open -> close -> still measurable.
    // Initial closed rect==0 is covered by 'can collapse hidden content when prewarm disabled'.
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setViewport(640, 480);

    const root = try box(ctx, .{ .width = .{ .px = 640 }, .height = .{ .px = 480 } }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const result = try Popover(.{
        .position = .bottom_start,
        .trigger = .click,
        // Both required: detach default true removes closed content from tree entirely, detached
        // nodes neither layout nor run before_render hooks.
        .prewarm_hidden_layout = true,
        .detach_hidden_content = false,
    }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, result.wrapper);

    const trigger_box = try box(ctx, .{ .width = .{ .px = 120 }, .height = .{ .px = 32 } }, .{});
    try result.trigger.appendChild(std.testing.allocator, trigger_box);

    const content_text = try core.text(ctx, "Popover content", .{});
    try result.content.appendChild(std.testing.allocator, content_text);

    ctx.layout();
    _ = ctx.render();

    // Open and settle: content is truly measured now.
    result.open.?.set(true);
    var iter: usize = 0;
    while (iter < 8) : (iter += 1) {
        ctx.frame_time_ms += 16;
        ctx.layout();
        _ = ctx.render();
        if (result.content.rectFromWorldOrFallback().w > 0) break;
    }
    try std.testing.expect(result.content.rectFromWorldOrFallback().w > 0);

    // Close and settle: prewarm preserves dimensions (not collapsing to 0), so next open doesn't
    // need another ready frame.
    result.open.?.set(false);
    iter = 0;
    while (iter < 8) : (iter += 1) {
        ctx.frame_time_ms += 16;
        ctx.layout();
        _ = ctx.render();
    }

    try std.testing.expect(result.content.rectFromWorldOrFallback().w > 0);
    try std.testing.expect(result.content.rectFromWorldOrFallback().h > 0);
}

test "Popover: closed initial render can collapse hidden content when prewarm disabled" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setViewport(640, 480);

    const root = try box(ctx, .{ .width = .{ .px = 640 }, .height = .{ .px = 480 } }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const result = try Popover(.{
        .position = .bottom_start,
        .trigger = .manual,
        .prewarm_hidden_layout = false,
    }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, result.wrapper);

    const content_text = try core.text(ctx, "Popover content", .{});
    try result.content.appendChild(std.testing.allocator, content_text);

    ctx.layout();
    _ = ctx.render();

    try std.testing.expectEqual(@as(f32, 0), result.content.rectFromWorldOrFallback().w);
    try std.testing.expectEqual(@as(f32, 0), result.content.rectFromWorldOrFallback().h);
    try std.testing.expect(result.content.style.overflow_hidden);
    try std.testing.expectEqual(@as(f32, 0), result.content.getOpacity());
}

test "Popover: open render emits content text at panel position after prewarm settles" {
    // History: needs multiple frames to settle (popover prewarm is multi-frame path).
    //
    // After P6.3 Popover uses composited_group surface (entire group scale_fade). Assert real
    // invariant "content text drawn + positioned in panel world coords (below trigger)", not old
    // begin/end_opacity_layer wrapping order (that promoted-surface path loses children + panel
    // flies to (0,0), root cause of component unusability, see docs/BUGS.md).
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setViewport(640, 480);

    const root = try box(ctx, .{ .width = .{ .px = 640 }, .height = .{ .px = 480 } }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const result = try Popover(.{
        .position = .bottom_start,
        .trigger = .click,
    }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, result.wrapper);

    const trigger_box = try box(ctx, .{ .width = .{ .px = 120 }, .height = .{ .px = 32 } }, .{});
    try result.trigger.appendChild(std.testing.allocator, trigger_box);

    const content_text = try core.text(ctx, "Popover content", .{});
    try result.content.appendChild(std.testing.allocator, content_text);

    ctx.layout();
    _ = ctx.render();

    result.open.?.set(true);

    var commands: []const @import("../../core.zig").paint_table.DisplayItem = &.{};
    var text_idx: ?usize = null;
    var text_geom_x: f32 = 0;
    var text_geom_y: f32 = 0;
    var iter: usize = 0;
    while (iter < 8) : (iter += 1) {
        ctx.frame_time_ms += 16;
        ctx.layout();
        _ = ctx.render();
        commands = ctx.lowerForEncoderPaintTable();
        text_idx = null;
        // After P6.3 popover content in composited surface: text geom is surface-local.
        // World coords = M_composite translation component - src origin + local geom
        // (M = owner_world·Translate(src), encoder subtracts src first then applies M, at settle
        // owner_world = Translate(owner_pos) => world = M_t - src + geom).
        var surf_tx: f32 = 0;
        var surf_ty: f32 = 0;
        var surf_src_x: f32 = 0;
        var surf_src_y: f32 = 0;
        var in_surface = false;
        for (commands, 0..) |cmd, i| {
            if (cmd.kind == .control) {
                switch (cmd.control_kind) {
                    .begin_opacity_layer => {
                        in_surface = true;
                        surf_tx = cmd.draw_transform[4];
                        surf_ty = cmd.draw_transform[5];
                        surf_src_x = cmd.geom.x;
                        surf_src_y = cmd.geom.y;
                    },
                    .end_opacity_layer => in_surface = false,
                    else => {},
                }
                continue;
            }
            if (cmd.isText()) {
                const txt = cmd;
                if (std.mem.eql(u8, txt.text_content, "Popover content")) {
                    text_idx = i;
                    if (in_surface) {
                        text_geom_x = surf_tx - surf_src_x + txt.geom.x;
                        text_geom_y = surf_ty - surf_src_y + txt.geom.y;
                    } else {
                        text_geom_x = txt.geom.x;
                        text_geom_y = txt.geom.y;
                    }
                }
            }
        }
        if (text_idx != null) break;
    }

    // content text must be drawn (promoted-surface path once lost entire children).
    try std.testing.expect(text_idx != null);
    // and (in world coords) positioned below trigger (bottom_start + offset). Past bug threw it to
    // (0,0).
    const trigger_rect = result.trigger.globalRect();
    try std.testing.expect(text_geom_y > trigger_rect.y + trigger_rect.h - 1.0);
    try std.testing.expect(text_geom_x >= trigger_rect.x - 1.0);
}

test "Popover: first open render keeps content scale_fade intermediate state" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setViewport(640, 480);

    const root = try box(ctx, .{ .width = .{ .px = 640 }, .height = .{ .px = 480 } }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const result = try Popover(.{
        .position = .bottom_start,
        .trigger = .click,
    }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, result.wrapper);

    const trigger_box = try box(ctx, .{ .width = .{ .px = 120 }, .height = .{ .px = 32 } }, .{});
    try result.trigger.appendChild(std.testing.allocator, trigger_box);

    const content_text = try core.text(ctx, "Popover content", .{});
    try result.content.appendChild(std.testing.allocator, content_text);

    ctx.layout();
    _ = ctx.render();

    result.open.?.set(true);
    render_engine.current_frame_time_ms = 16.0;
    render_engine.current_frame_dt_ms = 16.0;
    ctx.layout();
    _ = ctx.render();

    try std.testing.expect(result.content.getOpacity() >= 0.0);
    try std.testing.expect(result.content.getOpacity() <= 1.0);
    try std.testing.expect(result.content.style.scale_x() <= 1.0);
    try std.testing.expect(result.content.style.scale_y() <= 1.0);
}

test "Popover: default bottom placement fades and rises 4px without scaling" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setViewport(640, 480);

    const root = try box(ctx, .{ .width = .{ .px = 640 }, .height = .{ .px = 480 } }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const result = try Popover(.{
        .position = .bottom_start,
        .trigger = .click,
    }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, result.wrapper);

    const trigger_box = try box(ctx, .{ .width = .{ .px = 120 }, .height = .{ .px = 32 } }, .{});
    try result.trigger.appendChild(std.testing.allocator, trigger_box);
    try result.content.appendChild(std.testing.allocator, try core.text(ctx, "Animated popover", .{}));

    ctx.layout();
    _ = ctx.render();

    result.open.?.set(true);

    var opacities: [10]f32 = undefined;
    var offsets: [10]f32 = undefined;
    var now_ms: f64 = 0;
    for (0..10) |i| {
        now_ms += 16.0;
        render_engine.current_frame_time_ms = now_ms;
        render_engine.current_frame_dt_ms = 16.0;
        ctx.layout();
        _ = ctx.render();
        opacities[i] = result.content.getOpacity();
        try std.testing.expectEqual(@as(f32, 1), result.content.style.scale_x());
        offsets[i] = result.content.style.getExt().motion_offset[1];
    }

    var first_visible_idx: ?usize = null;
    for (opacities, 0..) |opacity, i| {
        if (opacity > HIDDEN_OPACITY + 0.0001) {
            first_visible_idx = i;
            break;
        }
    }

    const first = first_visible_idx orelse return error.PopoverNeverVisible;
    try std.testing.expect(opacities[first] < 0.4);
    try std.testing.expect(offsets[first] > 2);
    for (opacities[first..], offsets[first..]) |opacity, offset| {
        try std.testing.expectApproxEqAbs(4 * (1 - opacity), offset, 0.01);
    }
}

test "Popover: scale_fade open animation reuses promoted surface for stable text" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setViewport(640, 480);

    const root = try box(ctx, .{ .width = .{ .px = 640 }, .height = .{ .px = 480 } }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const result = try Popover(.{
        .position = .bottom_start,
        .trigger = .click,
    }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, result.wrapper);

    const trigger_box = try box(ctx, .{ .width = .{ .px = 120 }, .height = .{ .px = 32 } }, .{});
    try result.trigger.appendChild(std.testing.allocator, trigger_box);
    try result.content.appendChild(std.testing.allocator, try core.text(ctx, "Stable popover text", .{}));

    ctx.layout();
    _ = ctx.render();

    result.open.?.set(true);

    // Popover enter is **multi-frame** path: content waits for prewarm/positioning settle before
    // registering in scene_runtime (measured 4th frame in this fixture). Original test ran only 1
    // frame then `scene_runtime.get(...).?`, invariably unwrapped null crash, actual meaning of
    // original comment "not registered until prewarm settles". Changed to settle until
    // registration, then assert "first registration frame rebuilt, reused after".
    var settle: usize = 0;
    while (settle < 10) : (settle += 1) {
        ctx.frame_time_ms += 16;
        ctx.layout();
        _ = ctx.render();
        if (ctx.scene_runtime.get(result.content.id) != null) break;
    }

    // First registration frame: surface just created (rebuilt, not reused).
    const fr = ctx.scene_runtime.get(result.content.id) orelse return error.PopoverNeverRegistered;
    try std.testing.expect(fr.has_active_transform_animation);
    try std.testing.expect(result.content.meta.per_frame.caches.commands.promoted != null);
    try std.testing.expect(fr.promoted_surface_flags.rebuilt_this_frame);
    try std.testing.expect(!fr.promoted_surface_flags.reused_this_frame);

    // Next frame: animation still running, surface should be **reused** not rebuilt, precondition
    // for text not jittering during scale_fade.
    ctx.frame_time_ms += 16;
    ctx.layout();
    _ = ctx.render();
    const second_runtime = ctx.scene_runtime.get(result.content.id).?;
    try std.testing.expect(second_runtime.has_active_transform_animation);
    try std.testing.expect(second_runtime.promoted_surface_flags.surface_valid);
    try std.testing.expect(second_runtime.promoted_surface_flags.reused_this_frame);
    try std.testing.expect(!second_runtime.promoted_surface_flags.rebuilt_this_frame);
}

// ========== autosize: available height -> max_height (floating-ui size.availableHeight) ==========

/// Shared fixture: 640x480 viewport, trigger at y=300 (bottom 132 remain, top 284 remain, both
/// minus padding 8 + offset 8), content height `content_h`.
const AutosizeFixture = struct {
    cx: *Cx,
    scope: *Scope,
    content: *Node,
    handle: overlay_stack_mod.LayerHandle,
    open: *Signal(bool),
    trigger: *Node,

    fn init(content_h: f32) !AutosizeFixture {
        const cx = try Cx.init(std.testing.allocator, std.testing.io);
        errdefer cx.deinit();
        cx.setViewport(640, 480);
        const root = try box(cx, .{ .width = .{ .px = 640 }, .height = .{ .px = 480 } }, .{});
        cx.root = root;
        const scope = try Scope.init(std.testing.allocator, null, cx.owner);
        errdefer scope.dispose();

        const trigger = try box(cx, .{ .width = .{ .px = 120 }, .height = .{ .px = 32 } }, .{});
        const content = try box(cx, .{ .position = .absolute, .width = .{ .px = 160 }, .height = .{ .fit = .{} } }, .{});
        try root.appendChild(std.testing.allocator, trigger);
        try root.appendChild(std.testing.allocator, content);
        trigger.setLayoutRect(.{ .x = 40, .y = 300, .w = 120, .h = 32 });
        content.setLayoutRect(.{ .x = 0, .y = 0, .w = 160, .h = content_h });
        content.style.overflow_hidden = false;
        content.frame_state.state_bits.dirty.core.layout = false;
        content.frame_state.state_bits.dirty.core.subtree_layout = false;

        const handle = try cx.overlay_stack.push(.{
            .kind = .non_modal,
            .dismiss = .{},
            .enter_transition = .none,
            .exit_transition = .none,
        });
        if (cx.overlay_stack.findLayer(handle)) |layer| layer.content_node = content;
        const open = try scope.createSignal(bool, true);
        return .{ .cx = cx, .scope = scope, .content = content, .handle = handle, .open = open, .trigger = trigger };
    }

    fn deinit(self: *AutosizeFixture) void {
        self.scope.dispose();
        self.cx.deinit();
    }

    fn positionCtx(self: *AutosizeFixture, preferred_max_height: ?f32) PopoverPositionCtx {
        return .{
            .popover = self.content,
            .scope = self.scope,
            .trigger_node = self.trigger,
            .effective_anchor = .self_trigger,
            .is_open = .{ .signal = self.open },
            .layer_handle = self.handle,
            .pos = .bottom_start,
            .offset = .{ .static = 8 },
            .cx = self.cx,
            .flip = true,
            .preferred_width = null,
            .preferred_max_width = null,
            .preferred_max_height = preferred_max_height,
            .match_trigger_width = false,
            .constrain_width_to_viewport = false,
            .viewport_padding = 8,
            .active_position = .bottom_start,
            .entry_ready = false,
            .prewarmed_ready = false,
            .is_visible = false,
            .prewarm_hidden_layout = false,
            .enter_transition = .none,
            .exit_transition = .none,
        };
    }
};

test "Popover autosize: 两侧都放不下且 caller 未设 max_height 时，max_height 收紧到可用高度" {
    // Reproduction: content 300 tall, bottom 132 / top 284 both can't fit -> flip best-fit chooses
    // top. Before fix autosize only activated when caller set max_height, panel stayed 300 tall,
    // translate stuck to viewport top, bottom edge passes trigger obscuring reference element.
    var f = try AutosizeFixture.init(300);
    defer f.deinit();
    var position_ctx = f.positionCtx(null);
    f.content.meta.per_frame.hooks.slots.anim_state = @ptrCast(&position_ctx);

    popoverBeforeRender(f.content);

    try std.testing.expect(floating.getSide(position_ctx.active_position) == .top);
    // 284 = trigger.y(300) - padding(8) - offset(8)
    try std.testing.expectApproxEqAbs(@as(f32, 284), f.content.style.max_height(), 0.5);
    // Next frame layout applies max_height, this frame must already flag sizing dirty
    try std.testing.expect(f.content.frame_state.state_bits.dirty.core.layout);
    // cap bites content (300 > 284) -> chrome must clip children, else content overflows shell back
    // onto trigger
    try std.testing.expect(f.content.style.overflow_hidden);
}

test "Popover autosize: caller max_height 比可用高度更小时以 caller 为准" {
    var f = try AutosizeFixture.init(300);
    defer f.deinit();
    var position_ctx = f.positionCtx(200);
    f.content.meta.per_frame.hooks.slots.anim_state = @ptrCast(&position_ctx);

    popoverBeforeRender(f.content);

    try std.testing.expectApproxEqAbs(@as(f32, 200), f.content.style.max_height(), 0.5);
}

test "Popover autosize: 内容放得下时 max_height 不低于内容高度（不产生裁剪）" {
    // content 100 tall, bottom 132 remains -> stays bottom, cap = 132 >= 100.
    var f = try AutosizeFixture.init(100);
    defer f.deinit();
    var position_ctx = f.positionCtx(null);
    f.content.meta.per_frame.hooks.slots.anim_state = @ptrCast(&position_ctx);

    popoverBeforeRender(f.content);

    try std.testing.expect(floating.getSide(position_ctx.active_position) == .bottom);
    try std.testing.expectApproxEqAbs(@as(f32, 132), f.content.style.max_height(), 0.5);
    try std.testing.expect(f.content.style.max_height() >= 100);
    // cap doesn't bite -> no extra clipping (preserve caller's false)
    try std.testing.expect(!f.content.style.overflow_hidden);
}

test "Popover autosize: 可用高度变大的那一帧仍保持裁切（ph 还贴着旧 cap）" {
    // Reproduction: open tall popover then scroll page, trigger moves down -> upward available
    // height grows per frame. ph is height laid out with previous cap; comparing only to new cap
    // judges "doesn't bite" and disables overflow_hidden, this frame content (taller than old cap)
    // fully overflows panel; continuous scroll = continuous leak.
    var f = try AutosizeFixture.init(300);
    defer f.deinit();
    var position_ctx = f.positionCtx(null);
    f.content.meta.per_frame.hooks.slots.anim_state = @ptrCast(&position_ctx);

    popoverBeforeRender(f.content);
    try std.testing.expectApproxEqAbs(@as(f32, 284), f.content.style.max_height(), 0.5);
    try std.testing.expect(f.content.style.overflow_hidden);

    // Next frame: layout clamped panel to 284 by cap; page scroll moves trigger down 20 ->
    // available 304
    f.content.setLayoutRect(.{ .x = 0, .y = 0, .w = 160, .h = 284 });
    f.trigger.setLayoutRect(.{ .x = 40, .y = 320, .w = 120, .h = 32 });
    popoverBeforeRender(f.content);

    try std.testing.expectApproxEqAbs(@as(f32, 304), f.content.style.max_height(), 0.5);
    try std.testing.expect(f.content.style.overflow_hidden);
}

test "Popover autosize: viewport 极挤时保底 AUTOSIZE_MIN_HEIGHT 而非折到 0" {
    var f = try AutosizeFixture.init(300);
    defer f.deinit();
    // trigger almost at top filling height: top 8, bottom 8
    f.trigger.setLayoutRect(.{ .x = 40, .y = 16, .w = 120, .h = 448 });
    var position_ctx = f.positionCtx(null);
    f.content.meta.per_frame.hooks.slots.anim_state = @ptrCast(&position_ctx);

    popoverBeforeRender(f.content);

    try std.testing.expectApproxEqAbs(popover_mod.AUTOSIZE_MIN_HEIGHT, f.content.style.max_height(), 0.5);
}

test "Popover: portal content has no clip and wins hit over clipped trigger container" {
    // Plan section 9.3: After C2 deleted implicit clipping escape for z>0, "draw outside container"
    // has only structural portal path. trigger in overflow_hidden small container, content extends
    // outside: content's retained clip_id must be empty, its background fill not in any scissor,
    // outside-container points hit content.
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setViewport(400, 300);

    const root = try box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const clip_box = try box(ctx, .{
        .width = .{ .px = 120 },
        .height = .{ .px = 40 },
        .overflow_hidden = true,
    }, .{});
    try root.appendChild(std.testing.allocator, clip_box);

    const result = try Popover(.{
        .position = .bottom_start,
        .trigger = .manual,
        .enter_transition = .none,
        .exit_transition = .none,
    }).mount(scope, ctx);
    try clip_box.appendChild(std.testing.allocator, result.wrapper);

    const trigger_box = try box(ctx, .{ .width = .{ .px = 80 }, .height = .{ .px = 24 } }, .{});
    try result.trigger.appendChild(std.testing.allocator, trigger_box);

    const panel_color = Color.rgba(12, 200, 150, 255);
    const panel = try box(ctx, .{
        .width = .{ .px = 160 },
        .height = .{ .px = 120 },
        .background = panel_color,
    }, .{});
    panel.setFocusable(true);
    try result.content.appendChild(std.testing.allocator, panel);

    ctx.layout();
    _ = ctx.render();

    result.open.?.set(true);
    var iter: usize = 0;
    while (iter < 12) : (iter += 1) {
        ctx.frame_time_ms += 16;
        ctx.layout();
        _ = ctx.render();
    }

    // content under portal, portal ancestor chain has no clipping.
    try std.testing.expect(result.chrome.parent == ctx.popover_portal_root.?);
    const chrome_rt = ctx.scene_runtime.get(result.chrome.id) orelse return error.ChromeNotRendered;
    try std.testing.expectEqual(core.SceneRuntimeInvalidId, chrome_rt.clip_id);

    // panel background fill not in any scissor (contrast: trigger's container is 40px tall clipping
    // box).
    var depth: usize = 0;
    var found = false;
    for (ctx.lowerForEncoderPaintTable()) |it| {
        if (it.kind == .control) {
            switch (it.control_kind) {
                .push_clip => depth += 1,
                .pop_clip => depth -|= 1,
                else => {},
            }
            continue;
        }
        if (!it.isFillRect()) continue;
        if (it.color.r != panel_color.r or it.color.g != panel_color.g or it.color.b != panel_color.b) continue;
        found = true;
        try std.testing.expectEqual(@as(usize, 0), depth);
        break;
    }
    try std.testing.expect(found);

    // points outside container (y > 40), inside panel, hit panel.
    const panel_rect = panel.globalRect();
    try std.testing.expect(panel_rect.y + panel_rect.h > 60);
    const hit = ctx.hitTest(panel_rect.x + 20, panel_rect.y + panel_rect.h - 10) orelse return error.NoHit;
    try std.testing.expect(hit == panel or hit.isDescendantOf(result.chrome));
}

test "Popover: dropdown transition slides 6px toward the anchor with opacity and settles at rest" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setViewport(640, 480);

    const root = try box(ctx, .{ .width = .{ .px = 640 }, .height = .{ .px = 480 } }, .{});
    ctx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const result = try Popover(.{
        .position = .bottom_end,
        .trigger = .click,
        .offset = .{ .static = 6 },
        .enter_transition = .dropdown,
        .exit_transition = .dropdown,
    }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, result.wrapper);
    const trigger_box = try box(ctx, .{ .width = .{ .px = 26 }, .height = .{ .px = 20 } }, .{});
    try result.trigger.appendChild(std.testing.allocator, trigger_box);
    try result.content.appendChild(std.testing.allocator, try box(ctx, .{ .width = .{ .px = 200 }, .height = .{ .px = 120 } }, .{}));

    ctx.layout();
    _ = ctx.render();
    result.open.?.set(true);

    var now_ms: f64 = 0;
    var saw_mid = false;
    for (0..30) |_| {
        now_ms += 16.0;
        render_engine.current_frame_time_ms = now_ms;
        render_engine.current_frame_dt_ms = 16.0;
        ctx.frame_time_ms = now_ms;
        ctx.layout();
        _ = ctx.render();
        const op = result.content.getOpacity();
        if (op > 0.05 and op < 0.95) {
            saw_mid = true;
            // offset from rest position = (1 - opacity) x 6, direction upward (away from bottom
            // landing, toward anchor).
            const pctx: *PopoverPositionCtx = @ptrCast(@alignCast(result.content.meta.per_frame.hooks.slots.anim_state.?));
            const dy = result.content.style.translate_y - pctx.rest_translate_y;
            try std.testing.expect(dy < -0.1);
            try std.testing.expect(@abs(dy + (1 - op) * popover_mod.DROPDOWN_SLIDE_PX) < 0.05);
        }
    }
    try std.testing.expect(saw_mid);
    const pctx: *PopoverPositionCtx = @ptrCast(@alignCast(result.content.meta.per_frame.hooks.slots.anim_state.?));
    try std.testing.expectApproxEqAbs(@as(f32, 1), result.content.getOpacity(), 0.001);
    try std.testing.expectApproxEqAbs(pctx.rest_translate_y, result.content.style.translate_y, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 0.98), overlay_stack_mod.TransitionController.hiddenScaleForTransition(.dropdown), 0.0001);

    // Exit: positioner stops, slide-out offset still follows opacity.
    const rest_y = pctx.rest_translate_y;
    result.open.?.set(false);
    var saw_exit_mid = false;
    for (0..20) |_| {
        now_ms += 16.0;
        render_engine.current_frame_time_ms = now_ms;
        render_engine.current_frame_dt_ms = 16.0;
        ctx.frame_time_ms = now_ms;
        ctx.layout();
        _ = ctx.render();
        const op = result.content.getOpacity();
        if (op > 0.05 and op < 0.95) {
            saw_exit_mid = true;
            try std.testing.expect(result.content.style.translate_y < rest_y - 0.1);
        }
    }
    try std.testing.expect(saw_exit_mid);
}

test "Popover: dropdownSlideOffset follows the resolved side" {
    const off_b = popover_mod.dropdownSlideOffset(.bottom, 0);
    try std.testing.expectEqual(@as(f32, -6), off_b[1]);
    const off_t = popover_mod.dropdownSlideOffset(.top, 0.5);
    try std.testing.expectEqual(@as(f32, 3), off_t[1]);
    try std.testing.expectEqual(@as(f32, 0), popover_mod.dropdownSlideOffset(.bottom, 1)[1]);
}

fn openPopoverForConsumeTest(ctx: *Cx, result: anytype, now_ms: *f64) void {
    result.open.?.set(true);
    for (0..20) |_| {
        now_ms.* += 16.0;
        render_engine.current_frame_time_ms = now_ms.*;
        render_engine.current_frame_dt_ms = 16.0;
        ctx.frame_time_ms = now_ms.*;
        ctx.layout();
        _ = ctx.render();
    }
}

fn consumeCase(consume: bool) !usize {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setViewport(640, 480);
    const root = try box(ctx, .{ .width = .{ .px = 640 }, .height = .{ .px = 480 }, .direction = .column }, .{});
    ctx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    var clicks: usize = 0;
    const outside = try box(ctx, .{ .width = .{ .px = 100 }, .height = .{ .px = 40 } }, .{});
    outside.behavior.events.on_click = Cx.simpleHandler(struct {
        fn f(c: *anyopaque) void {
            const n: *usize = @ptrCast(@alignCast(c));
            n.* += 1;
        }
    }.f, &clicks);
    try root.appendChild(std.testing.allocator, outside);

    const result = try Popover(.{
        .position = .bottom_start,
        .trigger = .click,
        .consume_outside_click = consume,
    }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, result.wrapper);
    const trigger_box = try box(ctx, .{ .width = .{ .px = 40 }, .height = .{ .px = 20 } }, .{});
    try result.trigger.appendChild(std.testing.allocator, trigger_box);
    try result.content.appendChild(std.testing.allocator, try box(ctx, .{ .width = .{ .px = 120 }, .height = .{ .px = 60 } }, .{}));
    ctx.layout();
    _ = ctx.render();
    var now_ms: f64 = 0;
    openPopoverForConsumeTest(ctx, result, &now_ms);
    try std.testing.expect(result.open.?.peek());

    // First click on button outside panel.
    ctx.handleClick(50, 20);
    for (0..20) |_| {
        now_ms += 16;
        render_engine.current_frame_time_ms = now_ms;
        ctx.frame_time_ms = now_ms;
        ctx.layout();
        _ = ctx.render();
    }
    try std.testing.expect(!result.open.?.peek());
    const first = clicks;
    // Second click after close triggers normally.
    ctx.handleClick(50, 20);
    try std.testing.expectEqual(first + 1, clicks);
    return first;
}

fn renderFrames(ctx: *Cx, now_ms: *f64, n: usize) void {
    for (0..n) |_| {
        now_ms.* += 16.0;
        render_engine.current_frame_time_ms = now_ms.*;
        render_engine.current_frame_dt_ms = 16.0;
        ctx.frame_time_ms = now_ms.*;
        ctx.layout();
        _ = ctx.render();
    }
}

test "Popover: an outside press closes the popover on release, not on press" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setViewport(640, 480);
    const root = try box(ctx, .{ .width = .{ .px = 640 }, .height = .{ .px = 480 }, .direction = .column }, .{});
    ctx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    try root.appendChild(std.testing.allocator, try box(ctx, .{ .width = .{ .px = 100 }, .height = .{ .px = 40 } }, .{}));
    const result = try Popover(.{ .position = .bottom_start, .trigger = .click }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, result.wrapper);
    try result.trigger.appendChild(std.testing.allocator, try box(ctx, .{ .width = .{ .px = 40 }, .height = .{ .px = 20 } }, .{}));
    try result.content.appendChild(std.testing.allocator, try box(ctx, .{ .width = .{ .px = 120 }, .height = .{ .px = 60 } }, .{}));
    ctx.layout();
    _ = ctx.render();
    var now_ms: f64 = 0;
    openPopoverForConsumeTest(ctx, result, &now_ms);
    const layer = onlyLayer(ctx);
    try std.testing.expect(!layer.suspended);

    ctx.handleMouseDown(50, 20, .{});
    renderFrames(ctx, &now_ms, 3);
    try std.testing.expect(!layer.suspended);
    try std.testing.expect(layer.state != .exiting);

    ctx.handleMouseUp(50, 20);
    renderFrames(ctx, &now_ms, 1);
    try std.testing.expect(layer.suspended or layer.state == .exiting);
}

test "Popover: an outside click is not lost to a later press inside before the next frame" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setViewport(640, 480);
    const root = try box(ctx, .{ .width = .{ .px = 640 }, .height = .{ .px = 480 }, .direction = .column }, .{});
    ctx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    try root.appendChild(std.testing.allocator, try box(ctx, .{ .width = .{ .px = 100 }, .height = .{ .px = 40 } }, .{}));
    const result = try Popover(.{ .position = .bottom_start, .trigger = .click }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, result.wrapper);
    try result.trigger.appendChild(std.testing.allocator, try box(ctx, .{ .width = .{ .px = 40 }, .height = .{ .px = 20 } }, .{}));
    try result.content.appendChild(std.testing.allocator, try box(ctx, .{ .width = .{ .px = 120 }, .height = .{ .px = 60 } }, .{}));
    ctx.layout();
    _ = ctx.render();
    var now_ms: f64 = 0;
    openPopoverForConsumeTest(ctx, result, &now_ms);
    const layer = onlyLayer(ctx);
    try std.testing.expect(!layer.suspended);
    const panel = result.content.globalRect();
    // One event batch: a click outside, then a press inside the panel that is still held.
    ctx.handleMouseDown(50, 20, .{});
    ctx.handleMouseUp(50, 20);
    ctx.handleMouseDown(panel.x + panel.w / 2, panel.y + panel.h / 2, .{});
    renderFrames(ctx, &now_ms, 1);
    try std.testing.expect(layer.suspended or layer.state == .exiting);
}

test "Popover: a popover its press opened survives that press's release" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setViewport(640, 480);
    const root = try box(ctx, .{ .width = .{ .px = 640 }, .height = .{ .px = 480 }, .direction = .column }, .{});
    ctx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const opener = try box(ctx, .{ .width = .{ .px = 100 }, .height = .{ .px = 40 } }, .{});
    try root.appendChild(std.testing.allocator, opener);
    const result = try Popover(.{ .position = .bottom_start, .trigger = .manual }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, result.wrapper);
    try result.trigger.appendChild(std.testing.allocator, try box(ctx, .{ .width = .{ .px = 40 }, .height = .{ .px = 20 } }, .{}));
    try result.content.appendChild(std.testing.allocator, try box(ctx, .{ .width = .{ .px = 120 }, .height = .{ .px = 60 } }, .{}));
    ctx.layout();
    _ = ctx.render();
    var now_ms: f64 = 0;

    // The opener's press opens the popover (as an on-press handler would), several frames pass,
    // then the press releases.
    ctx.handleMouseDown(50, 20, .{});
    result.open.?.set(true);
    renderFrames(ctx, &now_ms, 4);
    ctx.handleMouseUp(50, 20);
    renderFrames(ctx, &now_ms, 2);
    const layer = onlyLayer(ctx);
    try std.testing.expect(!layer.suspended);
    try std.testing.expect(layer.state != .exiting);
    try std.testing.expect(result.open.?.peek());
}

test "Popover: consume_outside_click closes without activating what was clicked" {
    try std.testing.expectEqual(@as(usize, 0), try consumeCase(true));
    // Contrast: default behavior, close and click still reach below.
    try std.testing.expectEqual(@as(usize, 1), try consumeCase(false));
}

const LostUp = enum { cancel_pointer, new_press };

/// If consumed press doesn't receive matching release (window loses focus / pointer interaction
/// cancelled / release lost), swallow-release flag can't outlive this press, else next normal
/// click's release swallowed, click doesn't synthesize. Outside dismissal happens on release, so
/// a press without one closes nothing by itself.
fn lostUpCase(mode: LostUp) !struct { clicks: usize, open: bool } {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setViewport(640, 480);
    const root = try box(ctx, .{ .width = .{ .px = 640 }, .height = .{ .px = 480 }, .direction = .column }, .{});
    ctx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    var clicks: usize = 0;
    const outside = try box(ctx, .{ .width = .{ .px = 100 }, .height = .{ .px = 40 } }, .{});
    outside.behavior.events.on_click = Cx.simpleHandler(struct {
        fn f(c: *anyopaque) void {
            const n: *usize = @ptrCast(@alignCast(c));
            n.* += 1;
        }
    }.f, &clicks);
    try root.appendChild(std.testing.allocator, outside);

    const result = try Popover(.{ .position = .bottom_start, .trigger = .click, .consume_outside_click = true }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, result.wrapper);
    try result.trigger.appendChild(std.testing.allocator, try box(ctx, .{ .width = .{ .px = 40 }, .height = .{ .px = 20 } }, .{}));
    try result.content.appendChild(std.testing.allocator, try box(ctx, .{ .width = .{ .px = 120 }, .height = .{ .px = 60 } }, .{}));
    ctx.layout();
    _ = ctx.render();
    var now_ms: f64 = 0;
    openPopoverForConsumeTest(ctx, result, &now_ms);
    try std.testing.expect(result.open.?.peek());

    // press outside panel swallowed; corresponding release lost.
    ctx.handleMouseDown(50, 20, .{});
    try std.testing.expect(ctx.swallowed_press_button != null);
    switch (mode) {
        // pointer interaction cancelled ends this press: flag immediately invalidated, don't expect
        // later press to cover.
        .cancel_pointer => {
            ctx.cancelPointerInteractions(.window_blur);
            try std.testing.expect(ctx.swallowed_press_button == null);
        },
        .new_press => {},
    }
    const settle = struct {
        fn run(c: *Cx, t: *f64) void {
            for (0..20) |_| {
                t.* += 16;
                render_engine.current_frame_time_ms = t.*;
                c.frame_time_ms = t.*;
                c.layout();
                _ = c.render();
            }
        }
    }.run;
    settle(ctx, &now_ms);
    // No release, no click: the panel stays open.
    try std.testing.expect(result.open.?.peek());
    // Next click: a lost release counts as released (the panel closes and the click goes
    // through); after a cancelled press the still-open panel consumes this click to close.
    ctx.handleClick(50, 20);
    settle(ctx, &now_ms);
    return .{ .clicks = clicks, .open = result.open.?.peek() };
}

test "Popover: consumed press whose mouse-up is lost does not swallow the next click" {
    const lost = try lostUpCase(.new_press);
    try std.testing.expectEqual(@as(usize, 1), lost.clicks);
    try std.testing.expect(!lost.open);
    const cancelled = try lostUpCase(.cancel_pointer);
    try std.testing.expectEqual(@as(usize, 0), cancelled.clicks);
    try std.testing.expect(!cancelled.open);
}

test "Popover: an item that closes a nested popover from its click handler keeps the parent open" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setViewport(640, 480);
    const root = try box(ctx, .{ .width = .{ .px = 640 }, .height = .{ .px = 480 }, .direction = .column }, .{});
    ctx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const outer = try Popover(.{ .position = .bottom_start, .trigger = .click, .consume_outside_click = true }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, outer.wrapper);
    try outer.trigger.appendChild(std.testing.allocator, try box(ctx, .{ .width = .{ .px = 40 }, .height = .{ .px = 20 } }, .{}));
    try outer.content.appendChild(std.testing.allocator, try box(ctx, .{ .width = .{ .px = 200 }, .height = .{ .px = 200 } }, .{}));

    // inner menu: manual + own visible, on menu item click close it in click callback.
    const inner_visible = try core.Signal(bool).createInScope(scope, false);
    const inner = try Popover(.{ .position = .bottom_start, .trigger = .manual, .open = inner_visible, .consume_outside_click = true }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, inner.wrapper);
    const item = try box(ctx, .{ .width = .{ .px = 120 }, .height = .{ .px = 30 } }, .{});
    item.behavior.events.on_click = Cx.simpleHandler(struct {
        fn f(c: *anyopaque) void {
            const sig: *Signal(bool) = @ptrCast(@alignCast(c));
            sig.set(false);
        }
    }.f, @ptrCast(inner_visible));
    try inner.content.appendChild(std.testing.allocator, item);

    ctx.layout();
    _ = ctx.render();
    var now_ms: f64 = 0;
    openPopoverForConsumeTest(ctx, outer, &now_ms);
    inner_visible.set(true);
    for (0..20) |_| {
        now_ms += 16;
        render_engine.current_frame_time_ms = now_ms;
        ctx.frame_time_ms = now_ms;
        ctx.layout();
        _ = ctx.render();
    }
    try std.testing.expect(outer.open.?.peek());
    try std.testing.expect(inner_visible.peek());

    const r = item.globalRect();
    const ir = item.rectFromWorldOrFallback();
    ctx.handleClick(r.x + ir.w / 2, r.y + ir.h / 2);
    for (0..20) |_| {
        now_ms += 16;
        render_engine.current_frame_time_ms = now_ms;
        ctx.frame_time_ms = now_ms;
        ctx.layout();
        _ = ctx.render();
    }
    try std.testing.expect(!inner_visible.peek());
    try std.testing.expect(outer.open.?.peek());
}

const HookTextCtx = struct {
    node: *Node,
    reveal: ?*Node = null,
    armed: bool = false,
    fn hook(n: *Node) void {
        const self: *HookTextCtx = @ptrCast(@alignCast(n.meta.per_frame.hooks.slots.anim_state orelse return));
        if (!self.armed) return;
        self.armed = false;
        self.node.setTextContent(std.testing.allocator, "0 silenced · nothing pops up; summarized once when it ends, and this sentence keeps going so it needs several lines") catch unreachable;
        self.node.markSizingDirty();
        if (self.reveal) |w| {
            w.style.height = .{ .fit = .{} };
            w.markSizingDirty();
            w.setOpacity(1);
        }
    }
};

test "Popover: wrapped text updated from a before_render hook re-wraps and repaints in full" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setViewport(640, 480);
    const root = try box(ctx, .{ .width = .{ .px = 640 }, .height = .{ .px = 480 }, .direction = .column }, .{});
    ctx.root = root;
    const portal = try box(ctx, .{ .position = .absolute, .width = .{ .px = 640 }, .height = .{ .px = 480 } }, .{});
    try root.appendChild(std.testing.allocator, portal);
    ctx.popover_portal_root = portal;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const pop = try Popover(.{ .position = .bottom_start, .trigger = .click, .width = 360, .size_policy = .fit_content }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, pop.wrapper);
    try pop.trigger.appendChild(std.testing.allocator, try box(ctx, .{ .width = .{ .px = 40 }, .height = .{ .px = 20 } }, .{}));
    pop.chrome.style.direction = .column;
    try pop.content.appendChild(std.testing.allocator, try box(ctx, .{ .width = .fill(), .height = .{ .px = 40 } }, .{}));
    // first collapse (height 0 + clipped + transparent), hook expands same frame as text change,
    // panel banner real timing.
    const collapsed = try box(ctx, .{ .width = .fill(), .direction = .column, .padding = .{ .top = 0, .right = 10, .bottom = 10, .left = 10 } }, .{});
    try pop.content.appendChild(std.testing.allocator, collapsed);
    collapsed.style.height = .{ .px = 0 };
    collapsed.style.overflow_hidden = true;
    collapsed.setOpacityRaw(0);
    const row = try box(ctx, .{ .width = .fill(), .direction = .row, .gap = 10 }, .{});
    try collapsed.appendChild(std.testing.allocator, row);
    const col = try box(ctx, .{ .width = .fill(), .direction = .column, .gap = 1 }, .{});
    try row.appendChild(std.testing.allocator, col);
    const t = try core.text(ctx, "", .{ .font_size = 11.5, .wrap = .word_break });
    try col.appendChild(std.testing.allocator, t);
    t.style.width = .fill();

    // hook on node in main tree: simulate host refreshing panel text in before_render.
    var hctx: HookTextCtx = .{ .node = t, .reveal = collapsed };
    const driver = try box(ctx, .{ .width = .{ .px = 1 }, .height = .{ .px = 1 } }, .{});
    try root.appendChild(std.testing.allocator, driver);
    driver.meta.per_frame.hooks.slots.anim_state = @ptrCast(&hctx);
    driver.meta.per_frame.hooks.before_render.main = HookTextCtx.hook;

    ctx.layout();
    _ = ctx.render();
    var now_ms: f64 = 0;
    openPopoverForConsumeTest(ctx, pop, &now_ms);
    const one_line_h = t.rectFromWorldOrFallback().h;

    hctx.armed = true;
    driver.markRenderDirty();
    var painted: usize = 0;
    // real apps only call render() (layout inside render); extra ctx.layout() masks issue.
    for (0..3) |_| {
        now_ms += 16;
        render_engine.current_frame_time_ms = now_ms;
        ctx.frame_time_ms = now_ms;
        const items = ctx.render();
        painted = 0;
        for (items) |it| {
            if (it == .text_run) painted += it.text_run.content.len;
        }
    }
    try std.testing.expect(t.rectFromWorldOrFallback().h > one_line_h * 2);
    const expected = "0 silenced · nothing pops up; summarized once when it ends, and this sentence keeps going so it needs several lines".len;
    try std.testing.expect(painted + 8 >= expected);
}

fn setRows(ctx: *Cx, content: *Node, n: usize) !void {
    while (content.children.items.len > 0) {
        const c = content.children.items[content.children.items.len - 1];
        ctx.detachChildRetained(content, c);
        ctx.freeNode(c);
    }
    for (0..n) |_| try content.appendChild(std.testing.allocator, try box(ctx, .{ .width = .fill(), .height = .{ .px = 60 } }, .{}));
    content.markLayoutDirty();
}

fn stepFrames(ctx: *Cx, now_ms: *f64, n: usize) void {
    for (0..n) |_| {
        now_ms.* += 16;
        render_engine.current_frame_time_ms = now_ms.*;
        render_engine.current_frame_dt_ms = 16;
        ctx.frame_time_ms = now_ms.*;
        _ = ctx.render();
    }
}

test "Popover fit_content: a shrinkable scroll list grows back when its rows grow again" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setViewport(640, 480);
    const root = try box(ctx, .{ .width = .{ .px = 640 }, .height = .{ .px = 480 }, .direction = .column }, .{});
    ctx.root = root;
    const portal = try box(ctx, .{ .position = .absolute, .width = .{ .px = 640 }, .height = .{ .px = 480 } }, .{});
    try root.appendChild(std.testing.allocator, portal);
    ctx.popover_portal_root = portal;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const pop = try Popover(.{ .position = .bottom_start, .trigger = .click, .width = 300, .size_policy = .fit_content }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, pop.wrapper);
    try pop.trigger.appendChild(std.testing.allocator, try box(ctx, .{ .width = .{ .px = 40 }, .height = .{ .px = 20 } }, .{}));
    pop.chrome.style.direction = .column;
    const header = try box(ctx, .{ .width = .fill(), .height = .{ .px = 50 } }, .{});
    header.style.flex_shrink = 0;
    try pop.content.appendChild(std.testing.allocator, header);
    const sa = try @import("../scroll_area/mod.zig").ScrollArea(.{ .direction = .vertical }).mount(scope, ctx);
    try pop.content.appendChild(std.testing.allocator, sa.container);
    sa.container.style.height = .{ .fit = .{ .max = 300 } };
    sa.container.style.flex_shrink = 1;
    sa.content.style.width = .fill();

    try setRows(ctx, sa.content, 6);
    ctx.layout();
    _ = ctx.render();
    var now_ms: f64 = 0;
    openPopoverForConsumeTest(ctx, pop, &now_ms);
    try std.testing.expectApproxEqAbs(@as(f32, 300), sa.container.rectFromWorldOrFallback().h, 1);

    try setRows(ctx, sa.content, 2);
    stepFrames(ctx, &now_ms, 3);
    try std.testing.expectApproxEqAbs(@as(f32, 120), sa.container.rectFromWorldOrFallback().h, 1);

    try setRows(ctx, sa.content, 4);
    stepFrames(ctx, &now_ms, 3);
    try std.testing.expectApproxEqAbs(@as(f32, 240), sa.container.rectFromWorldOrFallback().h, 1);
    try std.testing.expectApproxEqAbs(@as(f32, 290), pop.chrome.rectFromWorldOrFallback().h, 1);
}

test "Popover: split open — trigger click and Esc are proposals the parent can reject" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const root = try box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    ctx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const open = try scope.createSignal(bool, false);
    const Gate = struct {
        open: *Signal(bool),
        allow_close: bool = false,
        fn propose(self: *@This(), v: bool) void {
            if (v or self.allow_close) self.open.set(v); // allow open, refuse close on demand
        }
    };
    var gate = Gate{ .open = open };
    const result = try Popover(.{ .open = @import("../../reactive.zig").split(open, ctx.on(Gate, &gate, Gate.propose)) }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, result.wrapper);

    result.trigger.behavior.events.on_click.?.invoke(); // open: parent accepts
    try std.testing.expect(open.peek());
    result.trigger.behavior.events.on_click.?.invoke(); // close: parent refuses
    ctx.handleKeyDown(.escape, .{}); // Esc: also refused
    try std.testing.expect(open.peek());
    try std.testing.expect(!ctx.overlay_stack.anyExiting());
    gate.allow_close = true;
    ctx.handleKeyDown(.escape, .{});
    try std.testing.expect(!open.peek());
}

test "Popover: a trigger freed without disposing the Popover's scope closes the layer instead of dangling" {
    // The trigger's nodes can be freed before the Popover's scope disposal lands (a disposal
    // requested inside a reactive callback is deferred). Until then the portal content stays
    // stacked: its before-render hook must not dereference the freed trigger
    // (generation-checked through the overlay stack) and the layer closes.
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setViewport(400, 300);
    const root = try box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    ctx.root = root;
    // Content in the window portal, outside the trigger's subtree (as in an app).
    const portal = try box(ctx, .{ .position = .absolute, .width = .{ .grow = .{} }, .height = .{ .grow = .{} } }, .{});
    try root.appendChild(std.testing.allocator, portal);
    ctx.popover_portal_root = portal;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const result = try Popover(.{ .enter_transition = .none, .exit_transition = .none }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, result.wrapper);
    result.open.?.set(true);
    _ = ctx.render();
    try std.testing.expect(result.content.parent == portal);
    // Free the trigger subtree while the scope is still alive.
    ctx.detachChild(root, result.wrapper);
    ctx.freeDetachedNodeAfterScopeDispose(result.wrapper);
    // The next frame runs the content's positioning hook (as the window relayout that follows
    // the deletion does). It must not touch the freed trigger.
    for (0..3) |_| popoverBeforeRender(result.content);
    for (ctx.overlay_stack.layers.items) |slot| {
        if (slot) |layer| try std.testing.expect(layer.suspended or layer.state == .exiting);
    }
}

test "Popover: hundreds of closed panels reserve no overlay slots and reuse capacity after exit" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const root = try box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    ctx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    // More than the overlay stack's capacity: closed hints / menus that were never opened
    // must not hold interaction-depth slots.
    var panels: [300]popover_mod.PopoverResult = undefined;
    for (&panels, 0..) |*panel, i| {
        panel.* = try Popover(.{
            .trigger = @as(popover_mod.PopoverTrigger, if (i % 2 == 0) .hover else .click),
            .enter_transition = .none,
            .exit_transition = .none,
        }).mount(scope, ctx);
        try root.appendChild(std.testing.allocator, panel.wrapper);
    }
    try std.testing.expectEqual(@as(usize, 0), ctx.overlay_stack.layer_count);

    for (&panels) |*panel| {
        panel.open.?.set(true);
        try std.testing.expectEqual(@as(usize, 1), ctx.overlay_stack.layer_count);
        const handle = ctx.overlay_stack.topmost().?.handle;
        try std.testing.expect(ctx.overlay_stack.findLayer(handle).?.content_node == panel.chrome);
        try std.testing.expect(panel.chrome.parent != null);
        panel.open.?.set(false);
        // A no-animation exit commits synchronously; the position hook then releases the
        // registration and detaches the content.
        popoverBeforeRender(panel.chrome);
        try std.testing.expectEqual(@as(usize, 0), ctx.overlay_stack.layer_count);
        try std.testing.expect(ctx.overlay_stack.findLayer(handle) == null);
        try std.testing.expect(panel.chrome.parent == null);
    }
    // A closed panel reopens with a fresh live handle; freeing it releases that.
    panels[0].open.?.set(true);
    try std.testing.expectEqual(@as(usize, 1), ctx.overlay_stack.layer_count);
    ctx.detachChild(root, panels[0].wrapper);
    ctx.freeNode(panels[0].wrapper);
    try std.testing.expectEqual(@as(usize, 0), ctx.overlay_stack.layer_count);
}

test "Popover: content kept attached while hidden keeps its suspended layer" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const root = try box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    ctx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const panel = try Popover(.{ .detach_hidden_content = false, .enter_transition = .none, .exit_transition = .none }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, panel.wrapper);
    // The attached hidden subtree stays gated (hit testing, semantic actions) by its layer.
    try std.testing.expectEqual(@as(usize, 1), ctx.overlay_stack.layer_count);
    try std.testing.expect(ctx.overlay_stack.isNodeInSuspendedLayer(panel.chrome));
    try std.testing.expect(!ctx.overlay_stack.allowsSemanticAction(panel.chrome));
    panel.open.?.set(true);
    panel.open.?.set(false);
    popoverBeforeRender(panel.chrome);
    try std.testing.expectEqual(@as(usize, 1), ctx.overlay_stack.layer_count);
    try std.testing.expect(ctx.overlay_stack.isNodeInSuspendedLayer(panel.chrome));
}

test "Popover: closing keeps the layer through the fade, then releases it for reopen" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setViewport(400, 300);
    const root = try box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    ctx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const panel = try Popover(.{
        .enter_transition = .fade_fast,
        .exit_transition = .fade_fast,
    }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, panel.wrapper);
    try panel.trigger.appendChild(std.testing.allocator, try box(ctx, .{ .width = .{ .px = 60 }, .height = .{ .px = 20 } }, .{}));
    try panel.content.appendChild(std.testing.allocator, try box(ctx, .{ .width = .{ .px = 80 }, .height = .{ .px = 40 } }, .{}));
    var now_ms = render_engine.current_frame_time_ms;
    openPopoverForConsumeTest(ctx, panel, &now_ms);
    const handle = ctx.overlay_stack.topmost().?.handle;
    panel.open.?.set(false);
    try std.testing.expectEqual(@as(usize, 1), ctx.overlay_stack.layer_count);
    try std.testing.expectEqual(overlay_stack_mod.LayerState.exiting, ctx.overlay_stack.findLayer(handle).?.state);
    try std.testing.expect(panel.chrome.parent != null);
    stepFrames(ctx, &now_ms, 30);
    try std.testing.expectEqual(@as(usize, 0), ctx.overlay_stack.layer_count);
    try std.testing.expect(ctx.overlay_stack.findLayer(handle) == null);
    try std.testing.expect(panel.chrome.parent == null);
    panel.open.?.set(true);
    const reopened = ctx.overlay_stack.topmost().?.handle;
    try std.testing.expect(reopened.id != handle.id);
    stepFrames(ctx, &now_ms, 30);
    try std.testing.expectApproxEqAbs(@as(f32, 1), panel.chrome.getOpacity(), 0.001);
    try std.testing.expect(panel.open.?.peek());
}

fn matchWidthPopover(ctx: *Cx, scope: *Scope, open: *core.Signal(bool), trigger_box: **Node, props_max_width: ?f32) !popover_mod.PopoverResult {
    ctx.setViewport(640, 480);
    const root = try box(ctx, .{ .width = .{ .px = 640 }, .height = .{ .px = 480 } }, .{});
    ctx.root = root;
    const result = try Popover(.{ .open = open, .position = .bottom_start, .match_trigger_width = true, .max_width = props_max_width }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, result.wrapper);
    trigger_box.* = try box(ctx, .{ .width = .{ .px = 120 }, .height = .{ .px = 32 } }, .{});
    try result.trigger.appendChild(std.testing.allocator, trigger_box.*);
    try result.content.appendChild(std.testing.allocator, try core.text(ctx, "Width follows trigger", .{}));
    return result;
}

test "Popover: an entered panel stays visible when the trigger width changes (remeasure)" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const open = try scope.createSignal(bool, true);
    var trigger_box: *Node = undefined;
    const result = try matchWidthPopover(ctx, scope, open, &trigger_box, null);
    var now_ms: f64 = render_engine.current_frame_time_ms;
    renderFrames(ctx, &now_ms, 12);
    try std.testing.expectApproxEqAbs(@as(f32, 1), result.chrome.getOpacity(), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 120), result.chrome.rectFromWorldOrFallback().w, 0.5);

    trigger_box.style.width = .{ .px = 200 };
    trigger_box.markSizingDirty();
    for (0..30) |_| {
        renderFrames(ctx, &now_ms, 1);
        // Never drops to the hidden prewarm opacity while open and entered.
        try std.testing.expect(result.chrome.getOpacity() > 0.999);
    }
    try std.testing.expectApproxEqAbs(@as(f32, 200), result.chrome.rectFromWorldOrFallback().w, 0.5);
    try std.testing.expect(!onlyLayer(ctx).enter_paused);
}

test "Popover: a panel mid-enter keeps animating when the trigger width changes" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const open = try scope.createSignal(bool, false);
    var trigger_box: *Node = undefined;
    const result = try matchWidthPopover(ctx, scope, open, &trigger_box, null);
    var now_ms: f64 = render_engine.current_frame_time_ms;
    renderFrames(ctx, &now_ms, 2);
    open.set(true);
    renderFrames(ctx, &now_ms, 4);
    trigger_box.style.width = .{ .px = 200 };
    trigger_box.markSizingDirty();
    renderFrames(ctx, &now_ms, 60);
    try std.testing.expectApproxEqAbs(@as(f32, 1), result.chrome.getOpacity(), 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 200), result.chrome.rectFromWorldOrFallback().w, 0.5);
}

test "Popover: width and max_width changing in the same frame still remeasure" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const open = try scope.createSignal(bool, true);
    var trigger_box: *Node = undefined;
    const result = try matchWidthPopover(ctx, scope, open, &trigger_box, 400);
    const ctx_ptr: *PopoverPositionCtx = @ptrCast(@alignCast(result.chrome.meta.per_frame.hooks.slots.anim_state.?));
    var now_ms: f64 = render_engine.current_frame_time_ms;
    renderFrames(ctx, &now_ms, 12);
    try std.testing.expectApproxEqAbs(@as(f32, 120), result.chrome.rectFromWorldOrFallback().w, 0.5);
    // Same frame: the trigger widens to 150 and the max_width cap moves to 300. The current
    // 120 px panel is within the new cap, which must not cancel the width remeasure.
    trigger_box.style.width = .{ .px = 150 };
    trigger_box.markSizingDirty();
    ctx.layout();
    ctx_ptr.preferred_max_width = 300;
    result.chrome.frame_state.state_bits.dirty.core.layout = false;
    popoverBeforeRender(result.chrome);
    try std.testing.expect(result.chrome.frame_state.state_bits.dirty.core.layout);
    renderFrames(ctx, &now_ms, 4);
    try std.testing.expectApproxEqAbs(@as(f32, 150), result.chrome.rectFromWorldOrFallback().w, 0.5);
    try std.testing.expect(result.chrome.getOpacity() > 0.999);
}

test "Popover: a popover open in a retained menu closes when the menu detaches it and reopens later" {
    const a = std.testing.allocator;
    var ctx = try Cx.init(a, std.testing.io);
    defer ctx.deinit();
    ctx.setViewport(400, 300);
    const root = try box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    ctx.root = root;
    const scope = try Scope.init(a, null, ctx.owner);
    defer scope.dispose();
    const menu = try Popover(.{ .trigger = .manual }).mount(scope, ctx);
    try root.appendChild(a, menu.wrapper);
    try menu.trigger.appendChild(a, try box(ctx, .{ .width = .{ .px = 60 }, .height = .{ .px = 20 } }, .{}));
    const nested = try Popover(.{ .trigger = .click }).mount(scope, ctx);
    try menu.content.appendChild(a, nested.wrapper);
    try nested.trigger.appendChild(a, try box(ctx, .{ .width = .{ .px = 80 }, .height = .{ .px = 24 } }, .{}));
    try nested.content.appendChild(a, try box(ctx, .{ .width = .{ .px = 100 }, .height = .{ .px = 40 } }, .{}));

    var now_ms = render_engine.current_frame_time_ms;
    for (0..3) |_| {
        menu.open.?.set(true);
        stepFrames(ctx, &now_ms, 20);
        nested.open.?.set(true);
        stepFrames(ctx, &now_ms, 20);
        try std.testing.expectApproxEqAbs(@as(f32, 1), nested.chrome.getOpacity(), 0.001);
        try std.testing.expectEqual(@as(usize, 2), ctx.overlay_stack.layer_count);
        // The retained menu's exit detaches its content, nested trigger included: the nested
        // panel closes through its open state (no stale, never-reopening layer) and no layer
        // outlives the two closes.
        menu.open.?.set(false);
        stepFrames(ctx, &now_ms, 20);
        try std.testing.expect(!nested.open.?.peek());
        try std.testing.expect(nested.chrome.parent == null);
        try std.testing.expectEqual(@as(usize, 0), ctx.overlay_stack.layer_count);
    }
}

test "Popover: a root rebound by its component opens after its identity is rebuilt" {
    // A `.yix` component whose root is a Popover rebinds the wrapper to the component's scope;
    // an AnchorTransition flight then re-registers the wrapper (identity retired, node alive).
    // The Popover must still read its trigger as alive and open (not PopoverTriggerFreed).
    const a = std.testing.allocator;
    var ctx = try Cx.init(a, std.testing.io);
    defer ctx.deinit();
    ctx.setViewport(400, 300);
    const root = try box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    ctx.root = root;
    const scope = try Scope.init(a, null, ctx.owner);
    defer scope.dispose();
    const component = try scope.childScope();
    const panel = try Popover(.{ .trigger = .manual }).mount(try component.childScope(), ctx);
    try panel.trigger.appendChild(a, try box(ctx, .{ .width = .{ .px = 60 }, .height = .{ .px = 20 } }, .{}));
    try panel.content.appendChild(a, try box(ctx, .{ .width = .{ .px = 100 }, .height = .{ .px = 40 } }, .{}));
    const slot = panel.wrapper.meta.ownership.scope.node_slot.?;
    // Step 1: the component scope rebinds the root.
    try core.bindScopeToNode(component, panel.wrapper);
    try std.testing.expectEqual(component, panel.wrapper.meta.ownership.scope.scope.?);
    try std.testing.expectEqual(panel.wrapper, slot.*.?);
    try root.appendChild(a, panel.wrapper);
    var now_ms = render_engine.current_frame_time_ms;
    stepFrames(ctx, &now_ms, 2);
    for (0..2) |_| {
        // Step 2: the identity is rebuilt (retained detach unregisters, re-append registers anew).
        ctx.detachChildRetained(root, panel.wrapper);
        try root.appendChild(a, panel.wrapper);
        stepFrames(ctx, &now_ms, 2);
        panel.open.?.set(true);
        stepFrames(ctx, &now_ms, 20);
        try std.testing.expect(panel.open.?.peek());
        try std.testing.expectEqual(@as(usize, 1), ctx.overlay_stack.layer_count);
        try std.testing.expectApproxEqAbs(@as(f32, 1), panel.chrome.getOpacity(), 0.001);
        panel.open.?.set(false);
        stepFrames(ctx, &now_ms, 20);
    }
    // Freeing the wrapper disposes the component scope it is bound to (and the Popover's with it).
    ctx.detachChild(root, panel.wrapper);
    ctx.freeNode(panel.wrapper);
    try std.testing.expectEqual(@as(usize, 0), ctx.overlay_stack.layer_count);
}

test "Popover: a trigger never mounted in the window does not close an open popover" {
    // Detach closing applies to a trigger seen in the window during the open: a menu whose
    // wrapper the caller never mounts (opened programmatically) stays open.
    const a = std.testing.allocator;
    var ctx = try Cx.init(a, std.testing.io);
    defer ctx.deinit();
    ctx.setViewport(400, 300);
    const root = try box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    ctx.root = root;
    const scope = try Scope.init(a, null, ctx.owner);
    defer scope.dispose();
    const panel = try Popover(.{ .trigger = .manual }).mount(scope, ctx);
    defer ctx.freeNode(panel.wrapper);
    try panel.content.appendChild(a, try box(ctx, .{ .width = .{ .px = 100 }, .height = .{ .px = 40 } }, .{}));
    var now_ms = render_engine.current_frame_time_ms;
    panel.open.?.set(true);
    stepFrames(ctx, &now_ms, 20);
    try std.testing.expect(panel.open.?.peek());
    try std.testing.expectEqual(@as(usize, 1), ctx.overlay_stack.layer_count);
}

test "Popover: theme replay survives open popovers and nested tooltips joining their layers" {
    // A theme publication replays every retained tree and runs each node's before-render hook.
    // The open popovers' and tooltips' hooks attach and detach floating content in the trees
    // being walked, so the replay must reread each child list instead of a captured slice.
    const a = std.testing.allocator;
    const cx = try Cx.init(a, std.testing.io);
    defer cx.deinit();
    cx.setViewport(1400, 900);
    const root = try box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    cx.root = root;
    const scope = try Scope.init(a, null, cx.owner);
    defer scope.dispose();
    cx.setTheme(&core.theme.dark);
    const Tooltip = @import("../tooltip/mod.zig").Tooltip;
    const shell = try box(cx, .{ .width = .fixed(600), .height = .fixed(456) }, .{});
    try root.appendChild(a, shell);
    const open = try scope.createSignal(bool, true);
    const menu = try Popover(.{ .open = open, .trigger = .manual, .enter_transition = .none, .exit_transition = .none, .width = 336 }).mount(scope, cx);
    try shell.appendChild(a, menu.wrapper);
    const independent = try Popover(.{ .open = open, .trigger = .manual, .enter_transition = .none, .exit_transition = .none, .width = 220 }).mount(scope, cx);
    independent.wrapper.setStyleInline(a, .{ .position = .absolute, .inset = .{ .left = .{ .px = 1000 }, .top = .{ .px = 100 } } });
    try root.appendChild(a, independent.wrapper);
    const card = try box(cx, .{ .width = .fill(), .height = .fixed(32) }, .{});
    try menu.content.appendChild(a, card);
    const hint = try Tooltip(.{ .text = "Model metadata", .open = open }).mount(scope, cx);
    try card.appendChild(a, hint.wrapper);
    const root_hint = try Tooltip(.{ .text = "Workspace metadata", .open = open }).mount(scope, cx);
    root_hint.wrapper.setStyleInline(a, .{ .position = .absolute, .inset = .{ .left = .{ .px = 1000 }, .top = .{ .px = 650 } } });
    try root.appendChild(a, root_hint.wrapper);
    // Two snapshots alternate like an app's theme publication (each publish is a new address).
    var snapshots: [2]core.theme.ThemeTokens = .{ core.theme.dark, core.theme.light };
    for (0..12) |round| {
        const slot = round % 2;
        snapshots[slot] = if (round % 3 == 0) core.theme.light else core.theme.dark;
        cx.setTheme(&snapshots[slot]);
        for (0..6) |_| {
            cx.frame_count += 1;
            cx.frame_time_ms += 16;
            _ = cx.render();
        }
    }
    // The walk survived the hooks detaching floating content mid-replay (a captured child
    // slice read the vacated tail slot) and the retained wrappers kept their places.
    try std.testing.expect(menu.wrapper.parent == shell);
    try std.testing.expect(independent.wrapper.parent == root);
    try std.testing.expect(root_hint.wrapper.parent == root);
}

fn schemeInk(t: *const core.theme.ThemeTokens) core.TextStyle {
    return .{ .color = t.tokens.color.fg_primary };
}

test "Popover: color_scheme fixes the panel and content appended after mount to the scheme tokens" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const theme = core.theme;
    ctx.setTheme(&theme.light);
    const root = try box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    ctx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const result = try Popover(.{ .trigger = .manual, .color_scheme = .dark }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, result.wrapper);
    const styles = @import("styles.zig");
    // (4) The default chrome paints the scheme's popover surface, not the app theme's.
    try std.testing.expect(Color.eql(styles.popoverContentBackground(&theme.dark), result.chrome.getBackground()));
    try std.testing.expect(!Color.eql(styles.popoverContentBackground(&theme.light), result.chrome.getBackground()));

    // Content the caller appends after mount resolves against the scheme once the popover opens.
    const label = try core.textStyled(ctx, schemeInk, "over video");
    try result.content.appendChild(std.testing.allocator, label);
    try std.testing.expect(Color.eql(theme.light.tokens.color.fg_primary, label.getText().?.color));
    result.open.?.set(true);
    try std.testing.expect(Color.eql(theme.dark.tokens.color.fg_primary, label.getText().?.color));
    try std.testing.expectEqual(&theme.dark, ctx.tokensFor(label));

    // An app theme switch leaves the panel on the scheme.
    ctx.setTheme(&theme.high_contrast);
    try std.testing.expect(Color.eql(theme.dark.tokens.color.fg_primary, label.getText().?.color));
    try std.testing.expect(Color.eql(styles.popoverContentBackground(&theme.dark), result.chrome.getBackground()));

    // App-registered scheme tokens recolour the chrome and the content.
    var app_dark = theme.dark;
    app_dark.tokens.color.bg_primary = Color.rgb(9, 8, 7);
    app_dark.tokens.color.fg_primary = Color.rgb(200, 201, 202);
    ctx.setSchemeTokens(.dark, &app_dark);
    try std.testing.expect(Color.eql(Color.rgb(9, 8, 7), result.chrome.getBackground()));
    try std.testing.expect(Color.eql(Color.rgb(200, 201, 202), label.getText().?.color));
    ctx.setSchemeTokens(.dark, null);
    try std.testing.expect(Color.eql(styles.popoverContentBackground(&theme.dark), result.chrome.getBackground()));
    result.open.?.set(false);
}

test "Popover: without color_scheme the chrome follows the app theme" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const theme = core.theme;
    ctx.setTheme(&theme.light);
    const root = try box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    ctx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const result = try Popover(.{ .trigger = .manual }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, result.wrapper);
    const styles = @import("styles.zig");
    try std.testing.expect(Color.eql(styles.popoverContentBackground(&theme.light), result.chrome.getBackground()));
    ctx.setTheme(&theme.dark);
    try std.testing.expect(Color.eql(styles.popoverContentBackground(&theme.dark), result.chrome.getBackground()));
    try std.testing.expectEqual(ctx.tokens, ctx.tokensFor(result.chrome));
}

// ---- color_scheme: native controls appended after mount resolve against the scheme ----

const SchemeFixtures = struct {
    const button_mod = @import("../button/mod.zig");
    const checkbox_mod = @import("../checkbox/mod.zig");
    const select_mod = @import("../select/mod.zig");
    const text_render = @import("../../core/render_engine/text_render.zig");
    const icons = @import("zenit_system_icons");

    /// What a node paints: transition target background, resolved text colour, glyph tint.
    const Paint = struct { bg: Color, text: ?Color, tint: ?Color };

    fn targetBackground(n: *Node) Color {
        if (n.frame_state.frame_local.runtime.transitions) |tr| if (tr.find(.background)) |slot| {
            if (slot.active) return slot.to_color;
        };
        return n.getBackground();
    }

    fn paint(n: *Node) Paint {
        const text: ?Color = if (n.getText() != null) if (text_render.resolveNodeLogicalTextProps(n)) |p| p.color else null else null;
        const tint: ?Color = if (n.getIcon()) |ic| ic.paintTint(if (ic.tint_current_color) n.resolveTextColor() else null) else null;
        return .{ .bg = targetBackground(n), .text = text, .tint = tint };
    }

    fn collect(n: *Node, out: *std.ArrayList(Paint)) !void {
        try out.append(std.testing.allocator, paint(n));
        for (n.children.items) |c| try collect(c, out);
    }

    fn expectSamePaint(expected: *Node, actual: *Node) !void {
        var a: std.ArrayList(Paint) = .empty;
        defer a.deinit(std.testing.allocator);
        var b: std.ArrayList(Paint) = .empty;
        defer b.deinit(std.testing.allocator);
        try collect(expected, &a);
        try collect(actual, &b);
        try std.testing.expectEqual(a.items.len, b.items.len);
        for (a.items, b.items) |x, y| {
            try std.testing.expect(Color.eql(x.bg, y.bg));
            try std.testing.expectEqual(x.text != null, y.text != null);
            if (x.text) |c| try std.testing.expect(Color.eql(c, y.text.?));
            try std.testing.expectEqual(x.tint != null, y.tint != null);
            if (x.tint) |c| try std.testing.expect(Color.eql(c, y.tint.?));
        }
    }

    const options = [_]select_mod.SelectOption{ .{ .value = "a", .label = "Alpha" }, .{ .value = "b", .label = "Beta" } };

    /// The four controls, in a fixed order: secondary Button, ghost icon Button, Select trigger,
    /// Switch, Checkbox.
    fn mountControls(scope: *Scope, cx: *Cx, parent: *Node, out: *[5]*Node) !void {
        out[0] = try button_mod.Button(.{ .label = "Secondary", .variant = .secondary }).mount(scope, cx);
        out[1] = try button_mod.Button(.{ .variant = .ghost, .icon_only = true, .icon_asset = icons.close, .a11y_label = "Close" }).mount(scope, cx);
        const select = try select_mod.Select(.{ .options = &options, .placeholder = "Pick", .width = 160 }).mount(scope, cx);
        out[2] = select.wrapper;
        out[3] = try checkbox_mod.Switch(.{}).mount(scope, cx);
        out[4] = try checkbox_mod.Checkbox(.{ .label = "Check" }).mount(scope, cx);
        for (out) |n| try parent.appendChild(std.testing.allocator, n);
    }
};

test "Popover: color_scheme resolves native controls appended after mount (Button / Select / Switch / Checkbox, hover) against the scheme" {
    const F = SchemeFixtures;
    const theme = core.theme;
    // Reference: the same controls mounted under the dark app theme.
    var ref_cx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ref_cx.deinit();
    ref_cx.setTheme(&theme.dark);
    const ref_root = try box(ref_cx, .{ .width = .{ .px = 600 }, .height = .{ .px = 400 } }, .{});
    ref_cx.root = ref_root;
    const ref_scope = try Scope.init(std.testing.allocator, null, ref_cx.owner);
    defer ref_scope.dispose();
    var ref: [5]*Node = undefined;
    try F.mountControls(ref_scope, ref_cx, ref_root, &ref);

    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setTheme(&theme.light);
    const root = try box(ctx, .{ .width = .{ .px = 600 }, .height = .{ .px = 400 } }, .{});
    ctx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const popover = try Popover(.{ .trigger = .manual, .color_scheme = .dark }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, popover.wrapper);
    var got: [5]*Node = undefined;
    try F.mountControls(popover.scope, ctx, popover.content, &got);
    // Built while the panel was closed: still the app theme (light) here.
    try std.testing.expect(!Color.eql(F.paint(ref[0]).bg, F.paint(got[0]).bg));

    popover.open.?.set(true);
    for (ref, got) |r, g| try F.expectSamePaint(r, g);

    // Another light app theme: the panel stays dark.
    var other_light = theme.light;
    other_light.tokens.color.bg_primary = Color.rgb(250, 240, 230);
    other_light.tokens.color.fg_primary = Color.rgb(10, 20, 30);
    ctx.setTheme(&other_light);
    for (ref, got) |r, g| try F.expectSamePaint(r, g);

    // Hover resolves the dark hover state.
    for ([_]usize{ 0, 1 }) |i| {
        ref[i].behavior.events.on_hover.?.invoke();
        got[i].behavior.events.on_hover.?.invoke();
        try F.expectSamePaint(ref[i], got[i]);
    }
    popover.open.?.set(false);
}

const FocusRig = struct {
    ctx: *Cx,
    scope: *Scope,
    opener: *Node,
    other: *Node,
    item: *Node,
    result: popover_mod.PopoverResult,
    now_ms: f64 = 0,

    fn init(props: popover_mod.PopoverProps) !FocusRig {
        return initWith(props, null);
    }
    /// `names`: the popover's `initial_focus` / `return_focus` follow these signals (created in the
    /// rig's scope, written by the test).
    fn initWith(props_in: popover_mod.PopoverProps, names: ?*FocusNames) !FocusRig {
        var props = props_in;
        const ctx = try Cx.init(std.testing.allocator, std.testing.io);
        errdefer ctx.deinit();
        ctx.setViewport(640, 480);
        const root = try box(ctx, .{ .width = .{ .px = 640 }, .height = .{ .px = 480 }, .direction = .column }, .{});
        ctx.root = root;
        const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
        if (names) |n| {
            n.initial = try scope.createSignal(?[]const u8, null);
            n.back = try scope.createSignal(?[]const u8, null);
            props.initial_focus = .{ .signal = n.initial };
            props.return_focus = .{ .signal = n.back };
        }
        const opener = try box(ctx, .{ .width = .{ .px = 100 }, .height = .{ .px = 30 } }, .{});
        opener.setFocusable(true);
        try root.appendChild(std.testing.allocator, opener);
        const other = try box(ctx, .{ .width = .{ .px = 100 }, .height = .{ .px = 30 } }, .{});
        other.setFocusable(true);
        try root.appendChild(std.testing.allocator, other);
        const result = try Popover(props).mount(scope, ctx);
        try root.appendChild(std.testing.allocator, result.wrapper);
        try result.trigger.appendChild(std.testing.allocator, try box(ctx, .{ .width = .{ .px = 40 }, .height = .{ .px = 20 } }, .{}));
        const item = try box(ctx, .{ .width = .{ .px = 120 }, .height = .{ .px = 30 } }, .{});
        item.setFocusable(true);
        try result.content.appendChild(std.testing.allocator, item);
        ctx.layout();
        _ = ctx.render();
        return .{ .ctx = ctx, .scope = scope, .opener = opener, .other = other, .item = item, .result = result };
    }
    fn deinit(self: *FocusRig) void {
        self.scope.dispose();
        self.ctx.deinit();
    }
    fn frames(self: *FocusRig, n: usize) void {
        renderFrames(self.ctx, &self.now_ms, n);
    }
    fn open(self: *FocusRig) void {
        self.ctx.setFocus(self.opener);
        self.result.open.?.set(true);
        self.frames(30);
    }
    fn close(self: *FocusRig) void {
        self.ctx.handleKeyDown(.escape, .{});
        self.frames(30);
    }
    fn focused(self: *FocusRig) ?*Node {
        return self.ctx.focus_manager.getFocused();
    }
    /// A focusable control appended to the panel, named `name` (a `focusId`) when given.
    fn control(self: *FocusRig, name: ?[]const u8, auto_focus: bool) !*Node {
        const node = try box(self.ctx, .{ .width = .{ .px = 120 }, .height = .{ .px = 30 } }, .{});
        node.setFocusable(true);
        try self.result.content.appendChild(std.testing.allocator, node);
        if (name) |n| _ = try self.ctx.focus_targets.register(self.ctx, .target, node, n, auto_focus);
        return node;
    }
};

const FocusNames = struct {
    initial: *Signal(?[]const u8) = undefined,
    back: *Signal(?[]const u8) = undefined,
};

test "Popover: a focus-trapping manual popover returns focus to the node focused when it opened" {
    var rig = try FocusRig.init(.{ .trigger = .manual, .trap_focus = true });
    defer rig.deinit();
    rig.open();
    try std.testing.expectEqual(rig.item, rig.ctx.focus_manager.getFocused().?);
    // Escape closes the top layer; focus goes back to the opener (the trigger box has nothing focusable).
    rig.ctx.handleKeyDown(.escape, .{});
    rig.frames(30);
    try std.testing.expect(!rig.result.open.?.peek());
    try std.testing.expectEqual(rig.opener, rig.ctx.focus_manager.getFocused().?);
}

test "Popover: a close after focus moved outside keeps that focus" {
    var rig = try FocusRig.init(.{ .trigger = .manual, .trap_focus = true });
    defer rig.deinit();
    rig.open();
    try std.testing.expectEqual(rig.item, rig.ctx.focus_manager.getFocused().?);
    // An outside click focused another control, then the panel closed: focus stays there.
    rig.ctx.setFocus(rig.other);
    rig.result.open.?.set(false);
    rig.frames(30);
    try std.testing.expectEqual(rig.other, rig.ctx.focus_manager.getFocused().?);
}

test "Popover: return_focus names the close-time focus target; not ready keeps the default" {
    var names: FocusNames = .{};
    var rig = try FocusRig.initWith(.{ .trigger = .manual, .trap_focus = true }, &names);
    defer rig.deinit();
    _ = try rig.ctx.focus_targets.register(rig.ctx, .target, rig.other, "back.other", false);
    names.back.set("back.other");
    rig.open();
    try std.testing.expectEqual(rig.item, rig.focused().?);
    rig.close();
    try std.testing.expectEqual(rig.other, rig.focused().?);
    // Read at close: a name with no ready target gives the default (the opener).
    names.back.set("back.missing");
    rig.open();
    rig.close();
    try std.testing.expectEqual(rig.opener, rig.focused().?);
}

test "Popover: initial_focus is read at each open and names the control focused then" {
    var names: FocusNames = .{};
    var rig = try FocusRig.initWith(.{ .trigger = .manual, .trap_focus = true }, &names);
    defer rig.deinit();
    const second = try rig.control("row.second", false);
    const third = try rig.control("row.third", false);
    // The same mount opened again and again: each open focuses the target named at that open.
    for ([_]struct { name: ?[]const u8, want: *Node }{
        .{ .name = "row.second", .want = second },
        .{ .name = "row.third", .want = third },
        .{ .name = "row.second", .want = second },
        .{ .name = null, .want = rig.item },
    }) |step| {
        names.initial.set(step.name);
        rig.open();
        try std.testing.expectEqual(step.want, rig.focused().?);
        rig.close();
        try std.testing.expectEqual(rig.opener, rig.focused().?);
    }
}

test "Popover: a named control mounted after the open takes focus in the frame it mounts; until then the first control holds it" {
    var names: FocusNames = .{};
    var rig = try FocusRig.initWith(.{ .trigger = .manual, .trap_focus = true }, &names);
    defer rig.deinit();
    names.initial.set("row.late");
    rig.ctx.setFocus(rig.opener);
    rig.result.open.?.set(true);
    rig.frames(5);
    // Not mounted yet: the default holds focus inside the panel (not the opener outside it).
    try std.testing.expectEqual(rig.item, rig.focused().?);
    const late = try rig.control("row.late", false);
    rig.frames(1);
    try std.testing.expectEqual(late, rig.focused().?);
    rig.close();
    try std.testing.expectEqual(rig.opener, rig.focused().?);

    // Mounted but hidden: the panel itself holds focus (no control); shown: focused that frame.
    late.setDisplay(.none);
    rig.ctx.setFocus(rig.opener);
    rig.result.open.?.set(true);
    rig.frames(5);
    try std.testing.expectEqual(rig.result.chrome, rig.focused().?);
    late.setDisplay(.flex);
    rig.frames(1);
    try std.testing.expectEqual(late, rig.focused().?);
}

test "Popover: initial_focus that changes while the panel waits is followed" {
    var names: FocusNames = .{};
    var rig = try FocusRig.initWith(.{ .trigger = .manual, .trap_focus = true }, &names);
    defer rig.deinit();
    // The name depends on data that arrives after the open (null at the open).
    rig.ctx.setFocus(rig.opener);
    rig.result.open.?.set(true);
    rig.frames(5);
    try std.testing.expectEqual(rig.item, rig.focused().?);
    names.initial.set("row.loaded");
    const loaded = try rig.control("row.loaded", false);
    rig.frames(1);
    // With no name at the open the entry was done: a name set afterwards is not a new entry.
    try std.testing.expectEqual(rig.item, rig.focused().?);
    rig.close();
    // Named at the open, renamed while waiting: the new name wins.
    names.initial.set("row.unknown");
    rig.ctx.setFocus(rig.opener);
    rig.result.open.?.set(true);
    rig.frames(5);
    try std.testing.expectEqual(rig.item, rig.focused().?);
    names.initial.set("row.loaded");
    rig.frames(1);
    try std.testing.expectEqual(loaded, rig.focused().?);
}

test "Popover: a stale name leaves the first control focused; nothing moves it later once the user acted" {
    var names: FocusNames = .{};
    var rig = try FocusRig.initWith(.{ .trigger = .manual, .trap_focus = true }, &names);
    defer rig.deinit();
    // Named after a control outside the panel: never this panel's target.
    _ = try rig.ctx.focus_targets.register(rig.ctx, .target, rig.other, "row.elsewhere", false);
    names.initial.set("row.elsewhere");
    rig.open();
    try std.testing.expectEqual(rig.item, rig.focused().?);
    rig.close();
    // Named after nothing: the first control; the user scrolls, then the row shows up: stays.
    names.initial.set("row.lazy");
    rig.open();
    try std.testing.expectEqual(rig.item, rig.focused().?);
    _ = rig.ctx.handleScrollConsumed(.{ .x = 50, .y = 50, .dx = 0, .dy = -3 });
    _ = try rig.control("row.lazy", false);
    rig.frames(3);
    try std.testing.expectEqual(rig.item, rig.focused().?);
}

test "Popover: a focusRequest made with the open wins over initial_focus, also when its target mounts later" {
    var names: FocusNames = .{};
    var rig = try FocusRig.initWith(.{ .trigger = .manual, .trap_focus = true }, &names);
    defer rig.deinit();
    const second = try rig.control("row.second", false);
    const third = try rig.control("row.third", false);
    names.initial.set("row.second");
    const requester = try rig.ctx.focus_targets.register(rig.ctx, .requester, rig.ctx.root.?, "", false);
    // The view-model opens the panel and asks for a control in it in the same turn.
    rig.ctx.setFocus(rig.opener);
    rig.result.open.?.set(true);
    rig.ctx.focus_targets.requestFocus(rig.ctx, requester, "row.third");
    rig.frames(30);
    try std.testing.expectEqual(third, rig.focused().?);
    rig.close();
    try std.testing.expectEqual(rig.opener, rig.focused().?);

    // The requested control is not mounted yet: initial_focus only holds focus meanwhile (the
    // placeholder does not cancel the request), then the request lands.
    rig.ctx.setFocus(rig.opener);
    rig.result.open.?.set(true);
    rig.ctx.focus_targets.requestFocus(rig.ctx, requester, "row.later");
    rig.frames(5);
    try std.testing.expectEqual(second, rig.focused().?);
    const later = try rig.control("row.later", false);
    rig.frames(1);
    try std.testing.expectEqual(later, rig.focused().?);
}

test "Popover: with nothing focusable the panel itself takes focus; a control that appears takes it over unless focus moved" {
    var rig = try FocusRig.init(.{ .trigger = .manual, .trap_focus = true });
    defer rig.deinit();
    // Content with nothing focusable (text, a progress bar ...).
    try rig.result.content.appendChild(std.testing.allocator, try box(rig.ctx, .{ .width = .{ .px = 120 }, .height = .{ .px = 30 } }, .{}));
    rig.result.content.removeChild(rig.item);
    rig.ctx.setFocus(rig.opener);
    rig.result.open.?.set(true);
    rig.frames(3);
    try std.testing.expectEqual(rig.result.chrome, rig.focused().?);
    // Escape still closes the top layer and focus returns.
    rig.close();
    try std.testing.expectEqual(rig.opener, rig.focused().?);

    rig.ctx.setFocus(rig.opener);
    rig.result.open.?.set(true);
    rig.frames(3);
    try std.testing.expectEqual(rig.result.chrome, rig.focused().?);
    try rig.result.content.appendChild(std.testing.allocator, rig.item);
    rig.frames(1);
    try std.testing.expectEqual(rig.item, rig.focused().?);
    rig.close();

    // A focus move while waiting ends the wait: a later control does not take focus back.
    rig.result.content.removeChild(rig.item);
    rig.ctx.setFocus(rig.opener);
    rig.result.open.?.set(true);
    rig.frames(3);
    try std.testing.expectEqual(rig.result.chrome, rig.focused().?);
    rig.ctx.setFocus(rig.other);
    try rig.result.content.appendChild(std.testing.allocator, rig.item);
    rig.frames(3);
    try std.testing.expectEqual(rig.other, rig.focused().?);
    rig.close();

    // So does user input (a key the panel does not use): focus stays on the panel.
    rig.result.content.removeChild(rig.item);
    rig.ctx.setFocus(rig.opener);
    rig.result.open.?.set(true);
    rig.frames(3);
    try std.testing.expectEqual(rig.result.chrome, rig.focused().?);
    _ = rig.ctx.handleKeyDown(.down, .{});
    try rig.result.content.appendChild(std.testing.allocator, rig.item);
    rig.frames(3);
    try std.testing.expectEqual(rig.result.chrome, rig.focused().?);
}

test "Popover: a declared autoFocus inside the panel takes focus on every open; initial_focus wins over it" {
    var names: FocusNames = .{};
    var rig = try FocusRig.initWith(.{ .trigger = .manual, .trap_focus = true }, &names);
    defer rig.deinit();
    const auto = try rig.control("row.auto", true);
    const third = try rig.control("row.third", false);
    rig.frames(2);
    for (0..2) |_| {
        rig.open();
        try std.testing.expectEqual(auto, rig.focused().?);
        rig.close();
    }
    names.initial.set("row.third");
    rig.open();
    try std.testing.expectEqual(third, rig.focused().?);
    rig.close();
}

test "Popover: an autoFocus control mounted while the panel is open takes focus, and again on the next open" {
    var rig = try FocusRig.init(.{ .trigger = .manual, .trap_focus = true });
    defer rig.deinit();
    rig.open();
    try std.testing.expectEqual(rig.item, rig.focused().?);
    const auto = try rig.control("row.auto", true);
    rig.frames(2);
    try std.testing.expectEqual(auto, rig.focused().?);
    rig.close();
    rig.open();
    try std.testing.expectEqual(auto, rig.focused().?);
}

test "Popover: without initial_focus the first control gets focus (default unchanged)" {
    var rig = try FocusRig.init(.{ .trigger = .manual, .trap_focus = true });
    defer rig.deinit();
    const second = try box(rig.ctx, .{ .width = .{ .px = 120 }, .height = .{ .px = 30 } }, .{});
    second.setFocusable(true);
    try rig.result.content.appendChild(std.testing.allocator, second);
    rig.open();
    try std.testing.expectEqual(rig.item, rig.ctx.focus_manager.getFocused().?);
}

test "Popover: Tab stays inside a focus-trapping panel" {
    var rig = try FocusRig.init(.{ .trigger = .manual, .trap_focus = true });
    defer rig.deinit();
    const second = try box(rig.ctx, .{ .width = .{ .px = 120 }, .height = .{ .px = 30 } }, .{});
    second.setFocusable(true);
    try rig.result.content.appendChild(std.testing.allocator, second);
    rig.open();
    for (0..5) |_| {
        _ = rig.ctx.handleKeyDown(.tab, .{});
        rig.frames(1);
        const focused = rig.ctx.focus_manager.getFocused().?;
        try std.testing.expect(focused == rig.item or focused == second);
    }
}

test "Popover: an opener that focuses a control in the panel keeps it, and focus still returns to where it opened" {
    var rig = try FocusRig.init(.{ .trigger = .manual, .trap_focus = true });
    defer rig.deinit();
    const second = try box(rig.ctx, .{ .width = .{ .px = 120 }, .height = .{ .px = 30 } }, .{});
    second.setFocusable(true);
    try rig.result.content.appendChild(std.testing.allocator, second);
    rig.ctx.setFocus(rig.opener);
    rig.result.open.?.set(true);
    rig.ctx.setFocus(second);
    rig.frames(30);
    try std.testing.expectEqual(second, rig.ctx.focus_manager.getFocused().?);
    rig.ctx.handleKeyDown(.escape, .{});
    rig.frames(30);
    try std.testing.expectEqual(rig.opener, rig.ctx.focus_manager.getFocused().?);
}

test "Popover: a trapping panel whose focused control is rebuilt puts focus back inside" {
    var rig = try FocusRig.init(.{ .trigger = .manual, .trap_focus = true });
    defer rig.deinit();
    rig.open();
    try std.testing.expectEqual(rig.item, rig.ctx.focus_manager.getFocused().?);
    // The panel rebuilds its rows: the focused one goes away.
    rig.ctx.focus_manager.abandonFocus(rig.item);
    rig.result.content.removeChild(rig.item);
    const fresh = try box(rig.ctx, .{ .width = .{ .px = 120 }, .height = .{ .px = 30 } }, .{});
    fresh.setFocusable(true);
    try rig.result.content.appendChild(std.testing.allocator, fresh);
    rig.frames(3);
    try std.testing.expectEqual(fresh, rig.ctx.focus_manager.getFocused().?);
    rig.ctx.freeNode(rig.item);
    rig.ctx.handleKeyDown(.escape, .{});
    rig.frames(30);
    try std.testing.expectEqual(rig.opener, rig.ctx.focus_manager.getFocused().?);
}

test "Popover: focus the user cleared while a trapping panel is open stays cleared" {
    var rig = try FocusRig.init(.{ .trigger = .manual, .trap_focus = true });
    defer rig.deinit();
    rig.open();
    try std.testing.expectEqual(rig.item, rig.ctx.focus_manager.getFocused().?);
    rig.ctx.focus_manager.clearFocus();
    rig.frames(3);
    try std.testing.expect(rig.ctx.focus_manager.getFocused() == null);
}

test "Popover: a trapping panel that builds its controls after the open focuses the first one once it exists" {
    var rig = try FocusRig.init(.{ .trigger = .manual, .trap_focus = true });
    defer rig.deinit();
    rig.result.content.removeChild(rig.item);
    rig.ctx.setFocus(rig.opener);
    rig.result.open.?.set(true);
    rig.frames(3);
    try rig.result.content.appendChild(std.testing.allocator, rig.item);
    rig.frames(10);
    try std.testing.expectEqual(rig.item, rig.ctx.focus_manager.getFocused().?);
    rig.ctx.handleKeyDown(.escape, .{});
    rig.frames(30);
    try std.testing.expectEqual(rig.opener, rig.ctx.focus_manager.getFocused().?);
}

test "Popover: a trapping panel that detaches and destroys its focused row keeps focus inside" {
    var rig = try FocusRig.init(.{ .trigger = .manual, .trap_focus = true });
    defer rig.deinit();
    const second = try box(rig.ctx, .{ .width = .{ .px = 120 }, .height = .{ .px = 30 } }, .{});
    second.setFocusable(true);
    try rig.result.content.appendChild(std.testing.allocator, second);
    rig.open();
    try std.testing.expectEqual(rig.item, rig.ctx.focus_manager.getFocused().?);
    rig.ctx.detachChild(rig.result.content, rig.item);
    rig.ctx.destroyDetached(rig.item);
    try std.testing.expect(rig.ctx.focus_manager.pending_trap_refocus != null);
    rig.frames(3);
    try std.testing.expectEqual(second, rig.ctx.focus_manager.getFocused().?);
    // A focus the user cleared stays cleared.
    rig.ctx.focus_manager.clearFocus();
    rig.frames(3);
    try std.testing.expect(rig.ctx.focus_manager.getFocused() == null);
}

/// A panel row whose control rebuilds itself after layout when clicked (a toolbar that swaps
/// "Manage" for "Done"): the pressed node is gone before the release is judged.
const RebuildingRow = struct {
    cx: *Cx,
    row: *Node,
    button: *Node = undefined,
    dirty: bool = false,
    rebuilt: usize = 0,

    fn build(self: *RebuildingRow) !void {
        self.button = try box(self.cx, .{ .width = .{ .px = 80 }, .height = .{ .px = 24 } }, .{});
        self.button.behavior.events.on_click = Cx.simpleHandler(clicked, self);
        try self.row.appendChild(std.testing.allocator, self.button);
    }

    fn clicked(raw: *anyopaque) void {
        const self: *RebuildingRow = @ptrCast(@alignCast(raw));
        self.dirty = true;
        self.row.markLayoutDirty();
    }

    fn afterLayout(raw: *anyopaque, _: u8, _: bool) core.AfterLayoutResult {
        const self: *RebuildingRow = @ptrCast(@alignCast(raw));
        if (!self.dirty) return .done;
        self.dirty = false;
        const old = self.button;
        self.row.removeChild(old);
        self.cx.destroyDetached(old);
        self.build() catch unreachable;
        self.rebuilt += 1;
        return .needs_layout;
    }
};

test "Popover: a click on a panel control that rebuilds itself keeps the panel open; the same control outside the panel closes it" {
    for ([_]bool{ true, false }) |inside| {
        var ctx = try Cx.init(std.testing.allocator, std.testing.io);
        defer ctx.deinit();
        ctx.setViewport(640, 480);
        const root = try box(ctx, .{ .width = .{ .px = 640 }, .height = .{ .px = 480 }, .direction = .column }, .{});
        ctx.root = root;
        const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
        defer scope.dispose();
        const result = try Popover(.{
            .position = .bottom_end,
            .trigger = .manual,
            .close_on_outside_click = true,
            .consume_outside_click = false,
            .anchor = popover_mod.Anchor{ .virtual = .{ .ctx = @ptrCast(ctx), .getRect = struct {
                fn rect(_: *anyopaque) AnchorRect {
                    return .{ .x = 600, .y = 40, .w = 0, .h = 0 };
                }
            }.rect } },
        }).mount(scope, ctx);
        try root.appendChild(std.testing.allocator, result.wrapper);
        // The panel body: inside the Popover's content, or (the wrong mount) in the window tree.
        const body = try box(ctx, .{ .width = .{ .px = 200 }, .height = .{ .px = 60 }, .direction = .row }, .{});
        if (inside) try result.content.appendChild(std.testing.allocator, body) else try root.appendChild(std.testing.allocator, body);
        var row: RebuildingRow = .{ .cx = ctx, .row = body };
        try row.build();
        try ctx.addAfterLayoutHook(&row, RebuildingRow.afterLayout);
        defer ctx.removeAfterLayoutHook(&row);
        ctx.layout();
        _ = ctx.render();
        var now_ms: f64 = 0;
        openPopoverForConsumeTest(ctx, result, &now_ms);
        const layer = onlyLayer(ctx);
        const r = row.button.globalRect();
        ctx.handleMouseDown(r.x + r.w / 2, r.y + r.h / 2, .{});
        ctx.handleMouseUp(r.x + r.w / 2, r.y + r.h / 2);
        renderFrames(ctx, &now_ms, 3);
        try std.testing.expectEqual(@as(usize, 1), row.rebuilt);
        if (inside) {
            try std.testing.expect(result.open.?.peek());
            try std.testing.expect(!layer.suspended and layer.state != .exiting);
        } else {
            try std.testing.expect(!result.open.?.peek());
        }
    }
}

// ========== Overlay layers and the content below them (pointer / wheel) ==========

/// A window-filling surface below the overlay layers that counts what reaches it.
const BelowProbe = struct {
    clicks: usize = 0,
    wheels: usize = 0,
    gesture_ends: usize = 0,
    fn observe(event: core.Event, raw: ?*anyopaque) core.EventResult {
        const self: *BelowProbe = @ptrCast(@alignCast(raw.?));
        switch (event) {
            .mouse_down => self.clicks += 1,
            // The end of a gesture (ended / cancelled, momentum ended) is a notification, not
            // scrolling.
            .scroll => |scroll| if (scroll.phaseEnded() or scroll.momentum == .ended) {
                self.gesture_ends += 1;
            } else {
                self.wheels += 1;
            },
            else => return .ignored,
        }
        return .handled;
    }
    fn mount(self: *BelowProbe, ctx: *Cx) !void {
        ctx.setViewport(1000, 700);
        ctx.root = try box(ctx, .{ .width = .fill(), .height = .fill() }, .{});
        const below = try box(ctx, .{ .width = .fill(), .height = .fill(), .hit_roles = .{ .pointer = true, .scroll = true } }, .{});
        below.behavior.events.event_context = self;
        below.behavior.events.on_event = observe;
        try ctx.root.?.appendChild(ctx.allocator, below);
    }
    fn frames(ctx: *Cx) void {
        for (0..20) |_| {
            ctx.frame_count += 1;
            ctx.frame_time_ms += 16;
            _ = ctx.render();
        }
    }
    fn click(ctx: *Cx, x: f32, y: f32) void {
        ctx.handleMouseDown(x, y, .{});
        ctx.handleMouseUp(x, y);
    }
};

test "Popover: a wheel over the panel's blank area does not scroll what lies below it" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    var below: BelowProbe = .{};
    try below.mount(ctx);
    const open = try scope.createSignal(bool, true);
    const popup = try Popover(.{ .open = open, .trigger = .manual, .width = @as(f32, 300), .max_height = @as(f32, 300), .position = .bottom_start, .enter_transition = .none, .exit_transition = .none, .close_on_outside_click = false }).mount(scope, ctx);
    popup.trigger.setStyleInline(ctx.allocator, .{ .width = .{ .px = 80 }, .height = .{ .px = 30 } });
    try ctx.root.?.appendChild(ctx.allocator, popup.wrapper);
    popup.content.setStyleInline(ctx.allocator, .{ .padding = core.Padding.all(12), .gap = 8 });
    const scroll = try @import("../scroll_area/mod.zig").ScrollArea(.{ .height = @as(f32, 100), .direction = .vertical }).mount(scope, ctx);
    scroll.container.setStyleInline(ctx.allocator, .{ .width = .fill() });
    try scroll.content.appendChild(ctx.allocator, try box(ctx, .{ .width = .fill(), .height = .{ .px = 500 } }, .{}));
    try popup.content.appendChild(ctx.allocator, scroll.container);
    BelowProbe.frames(ctx);
    const r = popup.chrome.globalRect();
    try std.testing.expect(r.w > 0 and r.h > 0);
    // Blank panel area: neither the click nor the wheel reaches the surface below.
    BelowProbe.click(ctx, r.x + 5, r.y + 5);
    // The wheel the panel contains is reported as used (a web host must not scroll the page).
    try std.testing.expect(ctx.handleScrollConsumed(.{ .x = r.x + 5, .y = r.y + 5, .dx = 0, .dy = -24 }));
    try std.testing.expectEqual(@as(usize, 0), below.clicks);
    try std.testing.expectEqual(@as(usize, 0), below.wheels);
    // The panel's own scroll area still scrolls, and still nothing leaks below.
    const v = scroll.container.globalRect();
    ctx.handleScroll(.{ .x = v.x + v.w / 2, .y = v.y + v.h / 2, .dx = 0, .dy = -24 });
    try std.testing.expect(scroll.state.scroll_y > 0);
    try std.testing.expectEqual(@as(usize, 0), below.wheels);
    // Outside the panel the surface below scrolls as before.
    ctx.handleScroll(.{ .x = 900, .y = 600, .dx = 0, .dy = -24 });
    try std.testing.expectEqual(@as(usize, 1), below.wheels);
}

test "Modal: the dialog and the scrim block wheels, and a trackpad gesture captured before it opened ends" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    var below: BelowProbe = .{};
    try below.mount(ctx);
    const open = try scope.createSignal(bool, false);
    const modal = try @import("../modal/mod.zig").Modal(.{ .open = open, .width = @as(f32, 300), .max_height = @as(f32, 220), .enter_transition = .none, .exit_transition = .none, .close_on_overlay = false }).mount(scope, ctx);
    if (!modal.portaled) try ctx.root.?.appendChild(ctx.allocator, modal.overlay);
    try modal.body.appendChild(ctx.allocator, try box(ctx, .{ .width = .fill(), .height = .{ .px = 100 } }, .{}));
    BelowProbe.frames(ctx);
    // A trackpad gesture is in progress on the surface below when the modal opens.
    ctx.handleScroll(.{ .x = 30, .y = 30, .dx = 0, .dy = -12, .phase = .began });
    try std.testing.expect(below.wheels > 0);
    open.set(true);
    BelowProbe.frames(ctx);
    below.wheels = 0;
    const r = modal.dialog.globalRect();
    // The rest of the captured gesture, and its momentum, no longer reach the surface below.
    ctx.handleScroll(.{ .x = 30, .y = 30, .dx = 0, .dy = -12, .phase = .changed });
    ctx.handleScroll(.{ .x = 30, .y = 30, .dx = 0, .dy = -12, .phase = .ended });
    ctx.handleScroll(.{ .x = 30, .y = 30, .dx = 0, .dy = -12, .momentum = .changed });
    try std.testing.expectEqual(@as(usize, 0), below.wheels);
    // Its owner was told once that the gesture is over.
    try std.testing.expectEqual(@as(usize, 1), below.gesture_ends);
    // Dialog: click and mouse wheel stay in the dialog.
    BelowProbe.click(ctx, r.x + 12, r.y + 12);
    try std.testing.expect(ctx.handleScrollConsumed(.{ .x = r.x + 12, .y = r.y + 12, .dx = 0, .dy = -24 }));
    try std.testing.expectEqual(@as(usize, 0), below.clicks);
    try std.testing.expectEqual(@as(usize, 0), below.wheels);
    // Scrim: the same.
    BelowProbe.click(ctx, 30, 30);
    try std.testing.expect(ctx.handleScrollConsumed(.{ .x = 30, .y = 30, .dx = 0, .dy = -24 }));
    // A new trackpad gesture over the scrim is blocked like the mouse wheel.
    ctx.handleScroll(.{ .x = 30, .y = 30, .dx = 0, .dy = -12, .phase = .began });
    ctx.handleScroll(.{ .x = 30, .y = 30, .dx = 0, .dy = -12, .phase = .ended });
    try std.testing.expectEqual(@as(usize, 0), below.clicks);
    try std.testing.expectEqual(@as(usize, 0), below.wheels);
}

test "Tooltip: the bubble stays input-transparent every time it is shown" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    var below: BelowProbe = .{};
    try below.mount(ctx);
    const open = try scope.createSignal(bool, true);
    const tip = try @import("../tooltip/mod.zig").Tooltip(.{ .text = "Passive", .open = open, .open_delay_ms = @as(f32, 0), .position = .bottom }).mount(scope, ctx);
    tip.trigger.setStyleInline(ctx.allocator, .{ .width = .{ .px = 80 }, .height = .{ .px = 30 } });
    try ctx.root.?.appendChild(ctx.allocator, tip.wrapper);
    for (0..3) |round| {
        errdefer std.debug.print("tooltip round {d}\n", .{round});
        BelowProbe.frames(ctx);
        const r = tip.content.globalRect();
        try std.testing.expect(r.w > 0 and r.h > 0);
        const clicks = below.clicks;
        const wheels = below.wheels;
        BelowProbe.click(ctx, r.x + r.w / 2, r.y + r.h / 2);
        ctx.handleScroll(.{ .x = r.x + r.w / 2, .y = r.y + r.h / 2, .dx = 0, .dy = -24 });
        try std.testing.expectEqual(clicks + 1, below.clicks);
        try std.testing.expectEqual(wheels + 1, below.wheels);
        open.set(false);
        BelowProbe.frames(ctx);
        open.set(true);
    }
}

test "Overlay: a layer that blocks nothing leaves a running trackpad gesture alone" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    var below: BelowProbe = .{};
    try below.mount(ctx);
    // A non-modal panel (no barrier), a tooltip, and a modal that is mounted but stays closed.
    const panel_open = try scope.createSignal(bool, false);
    const panel = try Popover(.{ .open = panel_open, .trigger = .manual, .width = @as(f32, 200), .position = .bottom_start, .enter_transition = .none, .exit_transition = .none, .close_on_outside_click = false }).mount(scope, ctx);
    // The panel opens right under the pointer of the running gesture (300, 300).
    panel.wrapper.setStyleInline(ctx.allocator, .{ .position = .absolute, .inset = .{ .left = .{ .px = 250 }, .top = .{ .px = 260 } } });
    panel.trigger.setStyleInline(ctx.allocator, .{ .width = .{ .px = 80 }, .height = .{ .px = 30 } });
    try ctx.root.?.appendChild(ctx.allocator, panel.wrapper);
    try panel.content.appendChild(ctx.allocator, try box(ctx, .{ .width = .fill(), .height = .{ .px = 120 } }, .{}));
    const tip_open = try scope.createSignal(bool, false);
    const tip = try @import("../tooltip/mod.zig").Tooltip(.{ .text = "Hint", .open = tip_open, .open_delay_ms = @as(f32, 0), .position = .bottom }).mount(scope, ctx);
    tip.trigger.setStyleInline(ctx.allocator, .{ .width = .{ .px = 80 }, .height = .{ .px = 30 } });
    try ctx.root.?.appendChild(ctx.allocator, tip.wrapper);
    BelowProbe.frames(ctx);
    ctx.handleScroll(.{ .x = 300, .y = 300, .dx = 0, .dy = -12, .phase = .began });
    const modal_open = try scope.createSignal(bool, false);
    const modal = try @import("../modal/mod.zig").Modal(.{ .open = modal_open, .width = @as(f32, 300), .enter_transition = .none, .exit_transition = .none }).mount(scope, ctx);
    if (!modal.portaled) try ctx.root.?.appendChild(ctx.allocator, modal.overlay);
    panel_open.set(true);
    tip_open.set(true);
    BelowProbe.frames(ctx);
    const pr = panel.chrome.globalRect();
    errdefer std.debug.print("panel rect {any} trigger {any}\n", .{ pr, panel.trigger.globalRect() });
    try std.testing.expect(pr.x <= 300 and pr.x + pr.w >= 300 and pr.y <= 300 and pr.y + pr.h >= 300);
    const before = below.wheels;
    ctx.handleScroll(.{ .x = 300, .y = 300, .dx = 0, .dy = -12, .phase = .changed });
    ctx.handleScroll(.{ .x = 300, .y = 300, .dx = 0, .dy = -12, .phase = .ended });
    ctx.handleScroll(.{ .x = 300, .y = 300, .dx = 0, .dy = -12, .momentum = .changed });
    try std.testing.expectEqual(before + 2, below.wheels);
    try std.testing.expectEqual(@as(usize, 1), below.gesture_ends);
}

test "Modal: momentum running when it opens ends for its owner; the rest of that gesture is dropped, a mouse wheel in between does not resume it" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    var below: BelowProbe = .{};
    try below.mount(ctx);
    const open = try scope.createSignal(bool, false);
    const modal = try @import("../modal/mod.zig").Modal(.{ .open = open, .width = @as(f32, 300), .enter_transition = .none, .exit_transition = .none, .close_on_overlay = false }).mount(scope, ctx);
    if (!modal.portaled) try ctx.root.?.appendChild(ctx.allocator, modal.overlay);
    BelowProbe.frames(ctx);
    // Fingers lifted: momentum is running on the surface below when the modal opens.
    ctx.handleScroll(.{ .x = 30, .y = 30, .dx = 0, .dy = -12, .phase = .began });
    ctx.handleScroll(.{ .x = 30, .y = 30, .dx = 0, .dy = -12, .phase = .ended });
    ctx.handleScroll(.{ .x = 30, .y = 30, .dx = 0, .dy = -12, .momentum = .began });
    try std.testing.expectEqual(@as(usize, 1), below.gesture_ends);
    const wheels = below.wheels;
    open.set(true);
    BelowProbe.frames(ctx);
    try std.testing.expect(ctx.handleScrollConsumed(.{ .x = 30, .y = 30, .dx = 0, .dy = -12, .momentum = .changed }));
    // The momentum owner was told once that its momentum ended; nothing more reached it.
    try std.testing.expectEqual(@as(usize, 2), below.gesture_ends);
    // A gesture in progress when the modal opens: ended for its owner; a mouse wheel arriving in
    // the middle of the dropped rest does not let the rest re-target.
    open.set(false);
    BelowProbe.frames(ctx);
    ctx.handleScroll(.{ .x = 30, .y = 30, .dx = 0, .dy = -12, .phase = .began });
    open.set(true);
    BelowProbe.frames(ctx);
    ctx.handleScroll(.{ .x = 30, .y = 30, .dx = 0, .dy = -12, .phase = .changed });
    try std.testing.expectEqual(@as(usize, 3), below.gesture_ends);
    ctx.handleScroll(.{ .x = 30, .y = 30, .dx = 0, .dy = -24 });
    ctx.handleScroll(.{ .x = 30, .y = 30, .dx = 0, .dy = -12, .phase = .changed });
    ctx.handleScroll(.{ .x = 30, .y = 30, .dx = 0, .dy = -12, .phase = .ended });
    ctx.handleScroll(.{ .x = 30, .y = 30, .dx = 0, .dy = -12, .momentum = .changed });
    try std.testing.expectEqual(wheels + 1, below.wheels);
    try std.testing.expectEqual(@as(usize, 3), below.gesture_ends);
}

test "Modal: a mouse-wheel transaction on what lies below ends when the modal opens; the next notch is contained" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    var below: BelowProbe = .{};
    try below.mount(ctx);
    // A long latch window: the notches below belong to one transaction however slow the test runs.
    ctx.dispatcher.wheel_latch_ns = 60 * std.time.ns_per_s;
    const open = try scope.createSignal(bool, false);
    const modal = try @import("../modal/mod.zig").Modal(.{ .open = open, .width = @as(f32, 300), .enter_transition = .none, .exit_transition = .none, .close_on_overlay = false }).mount(scope, ctx);
    if (!modal.portaled) try ctx.root.?.appendChild(ctx.allocator, modal.overlay);
    BelowProbe.frames(ctx);
    ctx.handleScroll(.{ .x = 30, .y = 30, .dx = 0, .dy = -24 });
    ctx.handleScroll(.{ .x = 30, .y = 30, .dx = 0, .dy = -24 });
    try std.testing.expectEqual(@as(usize, 2), below.wheels);
    open.set(true);
    BelowProbe.frames(ctx);
    // Same place, same direction, inside the window: the transaction's owner is now behind the scrim.
    try std.testing.expect(ctx.handleScrollConsumed(.{ .x = 30, .y = 30, .dx = 0, .dy = -24 }));
    try std.testing.expect(ctx.handleScrollConsumed(.{ .x = 30, .y = 30, .dx = 0, .dy = -24 }));
    try std.testing.expectEqual(@as(usize, 2), below.wheels);
}

test "Overlay: a non-modal panel opening under the pointer leaves a mouse-wheel transaction with its owner" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    var below: BelowProbe = .{};
    try below.mount(ctx);
    ctx.dispatcher.wheel_latch_ns = 60 * std.time.ns_per_s;
    const open = try scope.createSignal(bool, false);
    const panel = try Popover(.{ .open = open, .trigger = .manual, .width = @as(f32, 200), .position = .bottom_start, .enter_transition = .none, .exit_transition = .none, .close_on_outside_click = false }).mount(scope, ctx);
    panel.wrapper.setStyleInline(ctx.allocator, .{ .position = .absolute, .inset = .{ .left = .{ .px = 250 }, .top = .{ .px = 260 } } });
    panel.trigger.setStyleInline(ctx.allocator, .{ .width = .{ .px = 80 }, .height = .{ .px = 30 } });
    try ctx.root.?.appendChild(ctx.allocator, panel.wrapper);
    try panel.content.appendChild(ctx.allocator, try box(ctx, .{ .width = .fill(), .height = .{ .px = 120 } }, .{}));
    BelowProbe.frames(ctx);
    ctx.handleScroll(.{ .x = 300, .y = 300, .dx = 0, .dy = -24 });
    try std.testing.expectEqual(@as(usize, 1), below.wheels);
    open.set(true);
    BelowProbe.frames(ctx);
    const pr = panel.chrome.globalRect();
    try std.testing.expect(pr.x <= 300 and pr.x + pr.w >= 300 and pr.y <= 300 and pr.y + pr.h >= 300);
    // The notch continues the transaction (as a latched gesture continues): its owner keeps it.
    ctx.handleScroll(.{ .x = 300, .y = 300, .dx = 0, .dy = -24 });
    try std.testing.expectEqual(@as(usize, 2), below.wheels);
    // A new transaction (the pointer moved) over the panel is contained.
    try std.testing.expect(ctx.handleScrollConsumed(.{ .x = 305, .y = 300, .dx = 0, .dy = -24 }));
    try std.testing.expectEqual(@as(usize, 2), below.wheels);
}

test "Modal: a wheel at the end of the dialog's own scroll area is used, and nothing below moves" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    var below: BelowProbe = .{};
    try below.mount(ctx);
    const open = try scope.createSignal(bool, true);
    const modal = try @import("../modal/mod.zig").Modal(.{ .open = open, .width = @as(f32, 300), .enter_transition = .none, .exit_transition = .none, .close_on_overlay = false }).mount(scope, ctx);
    if (!modal.portaled) try ctx.root.?.appendChild(ctx.allocator, modal.overlay);
    const area = try @import("../scroll_area/mod.zig").ScrollArea(.{ .height = @as(f32, 100), .direction = .vertical, .rubber_band_y = false }).mount(scope, ctx);
    area.container.setStyleInline(ctx.allocator, .{ .width = .fill() });
    try area.content.appendChild(ctx.allocator, try box(ctx, .{ .width = .fill(), .height = .{ .px = 400 } }, .{}));
    try modal.body.appendChild(ctx.allocator, area.container);
    BelowProbe.frames(ctx);
    const v = area.container.globalRect();
    // Pinned at the top, a wheel towards the top moves nothing in the dialog, and still is used.
    try std.testing.expect(ctx.handleScrollConsumed(.{ .x = v.x + 10, .y = v.y + 10, .dx = 0, .dy = 24 }));
    try std.testing.expectEqual(@as(f32, 0), area.state.scroll_y);
    try std.testing.expectEqual(@as(usize, 0), below.wheels);
}

test "Modal: a gesture that may begin on what lies below and begins after the modal opened tells its first owner it is not its own" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    var below: BelowProbe = .{};
    try below.mount(ctx);
    const open = try scope.createSignal(bool, false);
    const modal = try @import("../modal/mod.zig").Modal(.{ .open = open, .width = @as(f32, 300), .enter_transition = .none, .exit_transition = .none, .close_on_overlay = false }).mount(scope, ctx);
    if (!modal.portaled) try ctx.root.?.appendChild(ctx.allocator, modal.overlay);
    BelowProbe.frames(ctx);
    ctx.handleScroll(.{ .x = 30, .y = 30, .dx = 0, .dy = 0, .phase = .may_begin });
    open.set(true);
    BelowProbe.frames(ctx);
    const ends = below.gesture_ends;
    const wheels = below.wheels; // the may_begin itself reached it
    try std.testing.expect(ctx.handleScrollConsumed(.{ .x = 30, .y = 30, .dx = 0, .dy = -12, .phase = .began }));
    try std.testing.expectEqual(ends + 1, below.gesture_ends);
    ctx.handleScroll(.{ .x = 30, .y = 30, .dx = 0, .dy = -12, .phase = .changed });
    try std.testing.expectEqual(wheels, below.wheels);
}

const OpensOnWheel = struct {
    cx: *Cx,
    handle: @import("../../overlay_stack.zig").LayerHandle,
    barrier: *core.Node,
    wheels: usize = 0,
    fn observe(event: core.Event, raw: ?*anyopaque) core.EventResult {
        const self: *OpensOnWheel = @ptrCast(@alignCast(raw.?));
        switch (event) {
            .scroll => {
                self.wheels += 1;
                // Activated during dispatch, not through a signal (which would only apply after
                // the window's event batch): the layer is shown while the starting notch is routed.
                self.cx.overlay_stack.reactivateWith(self.handle, .{ .animate = false });
                // What a Modal does on open: give the barrier its size back (commitExit zeroed it).
                self.barrier.setStyleInline(self.cx.allocator, .{ .width = .{ .px = 1000 }, .height = .{ .px = 700 } });
            },
            else => return .ignored,
        }
        return .handled;
    }
};

test "Overlay: a modal layer shown by the handler of the notch that starts a wheel transaction contains the transaction's next notches" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    ctx.setViewport(1000, 700);
    ctx.root = try box(ctx, .{ .width = .fill(), .height = .fill() }, .{});
    ctx.dispatcher.wheel_latch_ns = 60 * std.time.ns_per_s;
    const layer = try @import("../../overlay_stack.zig").overlay(scope, ctx, .{ .kind = .modal, .barrier = .theme_overlay, .enter_transition = .none, .exit_transition = .none });
    const barrier = layer.barrier.?;
    if (barrier.parent == null) try ctx.root.?.appendChild(ctx.allocator, barrier);
    barrier.setStyleInline(ctx.allocator, .{ .inset = .{ .left = .{ .px = 0 }, .top = .{ .px = 0 } }, .width = .{ .px = 1000 }, .height = .{ .px = 700 } });
    ctx.overlay_stack.commitExit(layer.handle);
    var opener: OpensOnWheel = .{ .cx = ctx, .handle = layer.handle, .barrier = barrier };
    const surface = try box(ctx, .{ .width = .fill(), .height = .fill(), .hit_roles = .{ .pointer = true, .scroll = true } }, .{});
    surface.behavior.events.event_context = &opener;
    surface.behavior.events.on_event = OpensOnWheel.observe;
    try ctx.root.?.insertChildBefore(ctx.allocator, surface, ctx.root.?.children.items[0]);
    BelowProbe.frames(ctx);
    ctx.handleScroll(.{ .x = 30, .y = 30, .dx = 0, .dy = -24 });
    try std.testing.expectEqual(@as(usize, 1), opener.wheels);
    BelowProbe.frames(ctx);
    try std.testing.expect(ctx.handleScrollConsumed(.{ .x = 30, .y = 30, .dx = 0, .dy = -24 }));
    try std.testing.expect(ctx.handleScrollConsumed(.{ .x = 30, .y = 30, .dx = 0, .dy = -24 }));
    try std.testing.expectEqual(@as(usize, 1), opener.wheels);
}

test "Popover: when the panel closes under a trackpad gesture, the gesture ends for the panel's list and its rest reaches what it uncovered; its momentum is discarded" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    var below: BelowProbe = .{};
    try below.mount(ctx);
    const open = try scope.createSignal(bool, true);
    const panel = try Popover(.{ .open = open, .trigger = .manual, .width = @as(f32, 200), .position = .bottom_start, .enter_transition = .none, .exit_transition = .none, .close_on_outside_click = false }).mount(scope, ctx);
    panel.wrapper.setStyleInline(ctx.allocator, .{ .position = .absolute, .inset = .{ .left = .{ .px = 250 }, .top = .{ .px = 260 } } });
    panel.trigger.setStyleInline(ctx.allocator, .{ .width = .{ .px = 80 }, .height = .{ .px = 30 } });
    try ctx.root.?.appendChild(ctx.allocator, panel.wrapper);
    const list = try @import("../scroll_area/mod.zig").ScrollArea(.{ .height = @as(f32, 120), .direction = .vertical }).mount(scope, ctx);
    list.container.setStyleInline(ctx.allocator, .{ .width = .fill() });
    try list.content.appendChild(ctx.allocator, try box(ctx, .{ .width = .fill(), .height = .{ .px = 600 } }, .{}));
    try panel.content.appendChild(ctx.allocator, list.container);
    BelowProbe.frames(ctx);
    const v = list.container.globalRect();
    const x = v.x + 20;
    const y = v.y + 20;
    // Momentum on the list, then the panel closes: the next momentum packet is discarded.
    ctx.handleScroll(.{ .x = x, .y = y, .dx = 0, .dy = -12, .phase = .began });
    ctx.handleScroll(.{ .x = x, .y = y, .dx = 0, .dy = 0, .phase = .ended });
    ctx.handleScroll(.{ .x = x, .y = y, .dx = 0, .dy = -12, .momentum = .began });
    open.set(false);
    BelowProbe.frames(ctx);
    const scrolled = list.state.scroll_y;
    ctx.handleScroll(.{ .x = x, .y = y, .dx = 0, .dy = -12, .momentum = .changed });
    try std.testing.expectEqual(scrolled, list.state.scroll_y);
    try std.testing.expectEqual(@as(usize, 0), below.wheels);
    // A gesture on the list, then the panel closes: its next changed reaches what is now uncovered.
    open.set(true);
    BelowProbe.frames(ctx);
    ctx.handleScroll(.{ .x = x, .y = y, .dx = 0, .dy = -12, .phase = .began });
    open.set(false);
    BelowProbe.frames(ctx);
    const before = list.state.scroll_y;
    ctx.handleScroll(.{ .x = x, .y = y, .dx = 0, .dy = -12, .phase = .changed });
    try std.testing.expectEqual(before, list.state.scroll_y);
    try std.testing.expectEqual(@as(usize, 1), below.wheels);
}

test "Popover: when the panel closes under a wheel transaction, the next notch reaches what it uncovered" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    var below: BelowProbe = .{};
    try below.mount(ctx);
    ctx.dispatcher.wheel_latch_ns = 60 * std.time.ns_per_s;
    const open = try scope.createSignal(bool, true);
    const panel = try Popover(.{ .open = open, .trigger = .manual, .width = @as(f32, 200), .position = .bottom_start, .enter_transition = .none, .exit_transition = .none, .close_on_outside_click = false }).mount(scope, ctx);
    panel.wrapper.setStyleInline(ctx.allocator, .{ .position = .absolute, .inset = .{ .left = .{ .px = 250 }, .top = .{ .px = 260 } } });
    panel.trigger.setStyleInline(ctx.allocator, .{ .width = .{ .px = 80 }, .height = .{ .px = 30 } });
    try ctx.root.?.appendChild(ctx.allocator, panel.wrapper);
    const list = try @import("../scroll_area/mod.zig").ScrollArea(.{ .height = @as(f32, 120), .direction = .vertical }).mount(scope, ctx);
    list.container.setStyleInline(ctx.allocator, .{ .width = .fill() });
    try list.content.appendChild(ctx.allocator, try box(ctx, .{ .width = .fill(), .height = .{ .px = 600 } }, .{}));
    try panel.content.appendChild(ctx.allocator, list.container);
    BelowProbe.frames(ctx);
    const v = list.container.globalRect();
    const x = v.x + 20;
    const y = v.y + 20;
    ctx.handleScroll(.{ .x = x, .y = y, .dx = 0, .dy = -24 });
    try std.testing.expect(list.state.scroll_y > 0);
    const scrolled = list.state.scroll_y;
    open.set(false);
    BelowProbe.frames(ctx);
    ctx.handleScroll(.{ .x = x, .y = y, .dx = 0, .dy = -24 });
    try std.testing.expectEqual(scrolled, list.state.scroll_y);
    try std.testing.expectEqual(@as(usize, 1), below.wheels);
}

test "Popover: hit roles the content declares itself survive every reopen" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    var below: BelowProbe = .{};
    try below.mount(ctx);
    const open = try scope.createSignal(bool, true);
    const popup = try Popover(.{ .open = open, .trigger = .manual, .width = @as(f32, 200), .enter_transition = .none, .exit_transition = .none, .close_on_outside_click = false }).mount(scope, ctx);
    try ctx.root.?.appendChild(ctx.allocator, popup.wrapper);
    BelowProbe.frames(ctx);
    popup.content.style.ensureExtPanic(ctx.allocator).hit_roles = .{ .pointer = true, .scroll = true, .inspect = false };
    for (0..2) |_| {
        open.set(false);
        BelowProbe.frames(ctx);
        open.set(true);
        BelowProbe.frames(ctx);
        const roles = popup.content.style.ext.?.hit_roles;
        try std.testing.expectEqual(@as(?bool, true), roles.scroll);
        try std.testing.expectEqual(@as(?bool, false), roles.inspect);
    }
}

test "Popover: an external node anchor freed while open is not dereferenced; the panel stays where it was" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setViewport(400, 300);
    const root = try box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    ctx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const anchor = try box(ctx, .{ .width = .{ .px = 40 }, .height = .{ .px = 20 }, .inset = .{ .left = .{ .px = 100 }, .top = .{ .px = 50 } } }, .{});
    try root.appendChild(std.testing.allocator, anchor);
    const open = try scope.createSignal(bool, true);
    const result = try Popover(.{ .trigger = .manual, .open = open, .anchor = .{ .node = anchor }, .enter_transition = .none, .exit_transition = .none }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, result.wrapper);
    const panel = try box(ctx, .{ .width = .{ .px = 80 }, .height = .{ .px = 30 } }, .{});
    try result.content.appendChild(std.testing.allocator, panel);
    for (0..3) |_| {
        _ = ctx.render();
        ctx.frame_count += 1;
    }
    const before = result.content.globalRect();
    // The caller frees the anchor while the popover is open.
    ctx.detachChild(root, anchor);
    ctx.freeNode(anchor);
    for (0..3) |_| {
        _ = ctx.render();
        ctx.frame_count += 1;
    }
    const after = result.content.globalRect();
    try std.testing.expectApproxEqAbs(before.x, after.x, 0.5);
    try std.testing.expectApproxEqAbs(before.y, after.y, 0.5);
}
