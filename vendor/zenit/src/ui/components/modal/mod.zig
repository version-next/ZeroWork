/// Modal Component
///
/// Modal dialog component, based on the OverlayStack framework
///
/// Features:
/// - Signal(bool) controls show/hide
/// - OverlayStack auto-manages z-index, mask, focus trap, Escape/outside-click close
/// - Supports title and close button
/// - fade in/out animation
const std = @import("std");
const core = @import("../../core.zig");
const view = @import("../../view.zig");
const Cx = core.Cx;
const Node = core.Node;
const box = core.box;
const Color = core.Color;
const Padding = core.Padding;
const theme = core.theme;
const Signal = core.Signal;
const svg_assets = @import("../../svg_assets.zig");
const reactive = @import("../../reactive.zig");
const Scope = reactive.Scope;
const Source = reactive.Source;
const Model = reactive.Model;
const Handler = core.Handler;
const bind_mod = @import("../../bind.zig");
const overlay_stack = @import("../../overlay_stack.zig");
const render_engine = @import("../../core/render_engine/mod.zig");

/// Modal props (Signal-first, docs/SIGNAL_API_DESIGN.md)
pub const ModalProps = struct {
    /// Open/close state. `*Signal(bool)` controlled (interaction writes directly) (typical usage);
    /// `bool` self-held by component (via `ModalResult.open` access signal to drive);
    /// `ui.split(read, cx.on(...))` lets parent intercept close (X/Esc/mask-click only propose,
    /// parent refuse keeps open).
    open: Model(bool) = .{ .local = false },
    /// Title; empty string and static doesn't build titlebar (no close button either).
    title: Source([]const u8) = .{ .value = "" },
    /// Dialog width (pt). A source resizes the open dialog.
    width: Source(f32) = .{ .value = 480 },
    /// Fitted height cap (pt) when `height` is null. A source is followed.
    max_height: Source(f32) = .{ .value = 600 },
    /// Fixed dialog height (pt; the body takes what the title bar leaves); null = fit the content
    /// up to `max_height`. A source is followed.
    height: Source(?f32) = .{ .value = null },
    /// The window area the dialog belongs to (null = the whole window, the default): the dialog is
    /// centred in it and bounded by it (width ≤ the area's width, fitted / fixed height ≤ its height,
    /// both less `within_padding` on each side; content taller than that scrolls in the body). The
    /// barrier still covers the window: modality, focus trap, Escape and mask clicks are unchanged.
    /// The area is a node (its on-screen rect, followed on every layout: window resizes, split drags,
    /// scrolling; the node is tracked by identity) or a `VirtualAnchor` (same type as Popover's
    /// `anchor`). An area that is gone, hidden, off screen, inside the dialog or too small
    /// (`WithinPlacement.min_width` / `min_height` after padding) places the dialog as if null; the
    /// dialog stays open. A source is followed. Design: docs/design/overlay-within-area.md.
    within: Source(?overlay_stack.Anchor) = .{ .value = null },
    /// Room kept between the dialog and the edges of the `within` area (pt; Popover's
    /// `viewport_padding` default). A source is followed.
    within_padding: Source(f32) = .{ .value = 8 },
    /// Mask color: null = the theme overlay token (follows `Cx.setTheme`); a color stays fixed
    overlay_color: ?Color = null,
    /// Dialog background
    background: ?Color = null,
    /// Body slot padding; null = the default [8, 20, 20, 20] (`Padding.all(0)` for edge-to-edge
    /// content). Read at mount.
    body_padding: ?Padding = null,
    /// Gap between body children; null = token space400. Read at mount.
    body_gap: ?f32 = null,
    /// Click mask to close
    close_on_overlay: bool = true,
    /// Close button glyph (an SVG asset); null = the framework's x.
    close_icon_asset: ?svg_assets.Asset = null,
    /// Accessible name of the title bar's close button (an icon-only native Button; the glyph is not
    /// a readable name). Default "Close"; the app's wording when it is localized or needs to say more.
    /// A source is followed. An empty name is an accessibility defect (Debug warns at mount).
    close_label: Source([]const u8) = .{ .value = "Close" },
    /// The title bar shows its close button (Escape and a mask click still close per their own
    /// settings). A source is followed. No title bar, no close button.
    closable: Source(bool) = .{ .value = true },
    /// Opening and closing motion. Set to .none for a fixed presentation.
    enter_transition: overlay_stack.Transition = .scale_fade,
    exit_transition: overlay_stack.Transition = .scale_fade,
    /// Play the enter transition when `open` is already true as the modal mounts. Default false:
    /// one mounted open (a page restored with its dialog up) is the open result, not an opening, so
    /// it appears at once. Set true when the caller mounts it in response to the opening itself.
    animate_initial_open: bool = false,
    /// User-initiated toggle (X/Esc/mask-click) fires after settling, param is settled toggle
    /// state.
    on_open_change: ?Handler(bool) = null,
    /// focusId of the control focused each time the modal opens (read then, looked up inside it;
    /// see `FocusManager.pushScopeWith`); a change while it still waits is followed. Mounted but
    /// not shown / enabled yet = the modal panel holds focus until it is; not mounted yet = the first
    /// control meanwhile. null = a declared `autoFocus` inside, else the first focusable control.
    initial_focus: Source(?[]const u8) = .{ .value = null },
    /// focusId of the control focus returns to when the modal closes (read then, looked up in the
    /// whole window once the modal is gone). null or not ready = the focus before it opened.
    return_focus: Source(?[]const u8) = .{ .value = null },
};

// ── Style layer in styles.yss ──
const styles = @import("_styles.yss.zig");
const views = @import("_modal.yix.zig");

/// The `within` area: a node or a `VirtualAnchor` (overlay_stack; the same type as Popover's `anchor`).
pub const Anchor = overlay_stack.Anchor;
pub const VirtualAnchor = overlay_stack.VirtualAnchor;
pub const AnchorRect = overlay_stack.AnchorRect;

/// Confirm preset (title, message, slot, cancel + confirm): `confirm.zig`.
pub const confirm = @import("confirm.zig");
pub const ConfirmDialog = confirm.ConfirmDialog;
pub const ConfirmDialogProps = confirm.ConfirmDialogProps;
pub const ConfirmDialogResult = confirm.ConfirmDialogResult;
pub const ConfirmTone = confirm.ConfirmTone;
pub const ConfirmFocus = confirm.ConfirmFocus;
pub const ConfirmTestIds = confirm.ConfirmTestIds;

/// Create Modal: `W.Modal(.{ .title = "Settings", .open = settings_open })`
pub fn Modal(props: anytype) ModalBuilder {
    return .{ .props = reactive.props.coerce(ModalProps, props) };
}

/// ModalBuilder.mount result. `open` is parsed toggle signal (local/bound non-null when present).
pub const ModalResult = struct {
    overlay: *Node,
    dialog: *Node,
    body: *Node,
    /// The title bar's text (null without a title bar).
    title: ?*Node,
    /// The title bar's close button: a native icon-only Button's root (null without a title bar).
    /// As a part it takes `test_id` (default "modal.close"), `style` and `visible`; its click and
    /// accessibility belong to the Modal (`close_label`): a part's `on_click` / `a11y` replace them
    /// wholesale and are overwritten when `close_label` changes.
    close_button: ?*Node,
    portaled: bool,
    open: ?*Signal(bool),

    /// `ui.view` intake: when portal overlay already hung at window root, nothing in parent.
    /// Parts (Yix `parts={.{ .body = … }}`): `overlay` (barrier), `dialog` (panel), `body` (slot),
    /// `title`, `close_button`; a part spec takes a test id, `style` (an overlay layer over the
    /// part's own) etc. For body spacing prefer `body_padding` / `body_gap`.
    pub fn viewParts(self: ModalResult) core.ViewParts {
        return .{ .root = if (self.portaled) null else self.overlay, .slot = self.body };
    }
};

/// Modal runtime state (scope owns)
const ModalRuntime = struct {
    open: reactive.Bound(bool),
    on_open_change: ?Handler(bool),

    /// X/Esc/mask-click: only propose close, data-source settle then open effect drives exit
    fn requestClose(context: *anyopaque) void {
        const self: *ModalRuntime = @ptrCast(@alignCast(context));
        self.open.propose(false, self.on_open_change);
    }
};

pub const ModalBuilder = struct {
    props: ModalProps,

    /// Retained mode: mount
    /// portaled=true overlay already auto-hung to cx.popover_portal_root (covers whole window),
    /// caller don't appendChild(overlay) again; false (no portal, like unit tests) caller still
    /// needs append.
    pub fn mount(self: ModalBuilder, scope: *Scope, cx: *Cx) !ModalResult {
        cx.owner.enterMount();
        defer cx.owner.exitMount();
        const my_scope = try scope.childScope();
        var scope_bound = false;
        errdefer if (!scope_bound) my_scope.dispose();
        const allocator = cx.allocator;
        const p = self.props;

        // Parse Model first then allocate rt: rt given to scope before can't have fail calls
        // between
        // (else leak)
        const open = try reactive.resolveModel(bool, my_scope, p.open);
        const rt = try my_scope.allocator.create(ModalRuntime);
        rt.* = .{ .open = open, .on_open_change = p.on_open_change };
        try my_scope.adoptResource(@ptrCast(rt), struct {
            fn destroy(ptr: *anyopaque, alloc: std.mem.Allocator) void {
                alloc.destroy(@as(*ModalRuntime, @ptrCast(@alignCast(ptr))));
            }
        }.destroy);
        const has_title = !(p.title.isStatic() and p.title.peek().len == 0);
        reactive.checkBorrow(my_scope, p.close_label);
        reactive.checkBorrow(my_scope, p.closable);
        if (std.debug.runtime_safety and has_title and p.close_label.peek().len == 0)
            std.log.warn("[Modal] close_label is empty: the close button has no accessible name", .{});
        const title_ref = try view.createRef(my_scope, *Node);
        const close_ref = try view.createRef(my_scope, *Node);

        // Create modal layer via OverlayStack
        const ol = try overlay_stack.overlay(my_scope, cx, .{
            .kind = .modal,
            .barrier = .colorOr(p.overlay_color),
            .dismiss = .{
                .outside_click = if (p.close_on_overlay) .close else .none,
                .escape = true,
            },
            .enter_transition = p.enter_transition,
            .exit_transition = p.exit_transition,
            .focus = .{ .trap = true, .auto_focus = true, .restore = true },
            .on_dismiss_request = core.Cx.simpleHandler(ModalRuntime.requestClose, rt),
        });

        // barrier node as overlay (container holding dialog)
        const barrier = ol.barrier.?;
        // overlay() sets focus_scope on ol.content, but this component doesn't use ol.content;
        // the node that actually does pushScope is barrier, so unless configured on barrier,
        // trap/auto_focus are all no-ops.
        barrier.setFocusScope(.{ .trap = true, .auto_focus = true });
        barrier.meta.ownership.meta.component_name = "Modal";
        try core.bindScopeToNode(my_scope, barrier);
        scope_bound = true;
        errdefer {
            if (barrier.parent) |parent| cx.detachChild(parent, barrier);
            cx.freeNode(barrier);
        }

        // Placement in a window area (`within`): an internal box between barrier and panel, and the
        // area's size cap folded into the panel's own size sources (the cap has one owner).
        const placement: ?*overlay_stack.WithinPlacement = if (!p.within.isStatic() or p.within.peek() != null)
            try overlay_stack.WithinPlacement.install(my_scope, cx, barrier, p.within, p.within_padding)
        else
            null;
        const Place = overlay_stack.WithinPlacement;
        const Capped = struct {
            fn width(c: anytype) f32 {
                return Place.capWidth(c.wanted.get(), c.cap.get());
            }
            fn height(c: anytype) ?f32 {
                return Place.capHeight(c.wanted.get(), c.cap.get());
            }
        };
        const width: Source(f32) = if (placement) |pl| .{ .memo = try my_scope.createMemo(f32, .{ .wanted = p.width, .cap = pl.cap_w }, Capped.width) } else p.width;
        const max_height: Source(f32) = if (placement) |pl| .{ .memo = try my_scope.createMemo(f32, .{ .wanted = p.max_height, .cap = pl.cap_h }, Capped.width) } else p.max_height;
        const height: Source(?f32) = if (placement) |pl| .{ .memo = try my_scope.createMemo(?f32, .{ .wanted = p.height, .cap = pl.cap_h }, Capped.height) } else p.height;

        // Dialog panel (view in modal.yix; titlebar present/absent static structure at mount-time)
        const panel = try views.ModalPanel(.{
            .title = p.title.peek(),
            .has_title = has_title,
            .width = width,
            .max_height = max_height,
            .height = height,
            .background = p.background,
            .close_icon_asset = p.close_icon_asset,
            .close_label = p.close_label,
            .closable = p.closable,
            .title_ref = title_ref,
            .close_ref = close_ref,
            .body_padding = p.body_padding,
            .body_gap = p.body_gap,
            .on_close = core.Cx.simpleHandler(ModalRuntime.requestClose, rt),
        }).viewMount(my_scope, cx);
        const dialog = panel.root.?;
        (if (placement) |pl| pl.attach(dialog) else barrier.appendChild(allocator, dialog)) catch |err| {
            cx.freeNode(dialog);
            return err;
        };
        const body = panel.slot.?;
        // Post-title change and dialog a11y name: name points to titlebar text node self-copy
        const title_node: ?*Node = if (has_title) title_ref.get() else null;
        const close_button: ?*Node = if (has_title) close_ref.get() else null;
        if (title_node) |tn| {
            if (dialog.behavior.interaction.a11y) |*a| a.label = tn.getText().?.content;
            try bind_mod.bindTextLabel(cx, my_scope, p.title, tn, dialog);
        }

        // Bind OverlayStack layer's real content_node to dialog,
        // let tick() in-out animation (fade) apply on dialog.
        cx.overlay_stack.bindContentNode(allocator, ol.handle, dialog);
        if (rt.open.read.peek() and !p.animate_initial_open) cx.overlay_stack.skipInitialEnter(ol.handle);

        // open controls show/hide (via Effect drive OverlayStack)
        {
            const open_src = rt.open.read;
            const fm = &cx.focus_manager;
            const scope_pushed = try my_scope.createSignal(bool, false);
            // Open unload direct (Show cut away/parent scope dispose) won't run visible effect pop
            // branch
            // -> focus scope stack leaks entry pointing to freed barrier.
            const scope_guard = try my_scope.allocator.create(FocusScopeGuard);
            scope_guard.* = .{ .fm = fm, .pushed = scope_pushed, .barrier_id = barrier.id };
            try my_scope.adoptResource(@ptrCast(scope_guard), FocusScopeGuard.destroy);
            try my_scope.onCleanup(FocusScopeGuard, scope_guard, FocusScopeGuard.cleanup);

            // Initial hide: barrier shrink 0 + layer suspend (direct set suspended, don't run
            // commitExit).
            // Must also whole-tree remove from hit-test: overflow_hidden only clips visual not hit,
            // dialog content overflowing 0x0 barrier leaves unvisible hot-zone at window top-left,
            // eats hover/click of controls below.
            if (!open_src.peek()) {
                barrier.style.width = .{ .px = 0 };
                barrier.style.height = .{ .px = 0 };
                barrier.style.overflow_hidden = true;
                barrier.setHitTestVisible(false);
                if (cx.overlay_stack.findLayer(ol.handle)) |layer| {
                    layer.suspended = true;
                }
            }

            reactive.checkBorrow(my_scope, open_src);
            reactive.checkBorrow(my_scope, p.initial_focus);
            reactive.checkBorrow(my_scope, p.return_focus);
            try my_scope.createEffect(.{
                .barrier = barrier,
                .visible = open_src,
                .fm = fm,
                .scope_pushed = scope_pushed,
                .cx = cx,
                .layer_handle = ol.handle,
                .initial_focus = p.initial_focus,
                .return_focus = p.return_focus,
                .holder = dialog,
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
                        c.barrier.setHitTestVisible(true);
                        if (!c.scope_pushed.peek()) {
                            // While the named target is not ready, the dialog holds focus (not a control).
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
                        c.barrier.setHitTestVisible(false);
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

        return .{ .overlay = barrier, .dialog = dialog, .body = body, .title = title_node, .close_button = close_button, .portaled = ol.portaled, .open = rt.open.asSignal() };
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

test "Modal: basic structure" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try box(ctx, .{ .width = .{ .px = 800 }, .height = .{ .px = 600 } }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const result = try Modal(.{
        .title = "Test Modal",
        .width = 400,
    }).mount(scope, ctx);

    try root.appendChild(std.testing.allocator, result.overlay);

    // overlay(barrier) contains dialog
    try std.testing.expectEqual(@as(usize, 1), result.overlay.children.items.len);
    // dialog contains header + body + the close button's place (after the body: focus order)
    try std.testing.expectEqual(@as(usize, 3), result.dialog.children.items.len);
    try std.testing.expect(result.dialog.children.items[1] == result.body);
    try std.testing.expect(result.close_button.?.isDescendantOf(result.dialog.children.items[2]));
    try std.testing.expect(result.title.? == result.dialog.children.items[0].children.items[0]);
    // absolutely positioned
    try std.testing.expectEqual(core.Position.absolute, result.overlay.style.position);
}

test "Modal: visible signal control" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try box(ctx, .{ .width = .{ .px = 800 }, .height = .{ .px = 600 } }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const vis = try scope.createSignal(bool, false);

    const result = try Modal(.{
        .title = "Toggle Modal",
        .open = vis,
    }).mount(scope, ctx);

    try root.appendChild(std.testing.allocator, result.overlay);

    // initially hidden
    try std.testing.expectEqual(core.Sizing{ .px = 0 }, result.overlay.style.width);

    // shown
    vis.set(true);
    try std.testing.expectEqual(core.Sizing{ .grow = .{} }, result.overlay.style.width);

    // hidden
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
    while (ticks < 16) : (ticks += 1) {
        test_time += 16.0;
        render_engine.current_frame_time_ms = test_time;
        _ = ctx.overlay_stack.tick(test_time, 0.016, 800, 600, std.testing.allocator);
    }

    try std.testing.expectEqual(core.Sizing{ .px = 0 }, result.overlay.style.width);
}

test "Modal: 打开状态下卸载会弹出自己的 focus scope" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const root = try box(ctx, .{ .width = .{ .px = 800 }, .height = .{ .px = 600 } }, .{});
    ctx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const vis = try scope.createSignal(bool, true);

    const sub = try scope.childScope();
    const result = try Modal(.{ .title = "Unmount open", .open = vis }).mount(sub, ctx);
    if (!result.portaled) try root.appendChild(std.testing.allocator, result.overlay);
    const fm = &ctx.focus_manager;
    try std.testing.expectEqual(@as(u8, 1), fm.scope_count);

    sub.dispose();
    try std.testing.expectEqual(@as(u8, 0), fm.scope_count);
    try std.testing.expect(fm.activeScope() == null);
}

test "Modal: 打开时 focus trap 生效并自动聚焦到对话框内" {
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

    const result = try Modal(.{ .title = "Trap", .open = vis }).mount(scope, ctx);
    if (!result.portaled) try root.appendChild(std.testing.allocator, result.overlay);
    const inside = try box(ctx, .{ .width = .{ .px = 100 }, .height = .{ .px = 30 } }, .{});
    inside.behavior.interaction.focusable = true;
    try result.body.appendChild(std.testing.allocator, inside);

    ctx.layout();
    const fm = &ctx.focus_manager;
    fm.setFocus(outside);
    vis.set(true);

    try std.testing.expect(fm.getFocused() == inside);
    const order = fm.scopedFocusOrder();
    for (order) |n| try std.testing.expect(n != outside);
}

test "Modal: exiting keeps overlay visible until commit" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try box(ctx, .{ .width = .{ .px = 800 }, .height = .{ .px = 600 } }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const vis = try scope.createSignal(bool, true);

    const result = try Modal(.{
        .title = "Exit Modal",
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

test "Modal: first 10 open frames progress from enter state instead of flashing" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setViewport(800, 600);

    const root = try box(ctx, .{ .width = .{ .px = 800 }, .height = .{ .px = 600 } }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const vis = try scope.createSignal(bool, false);

    const result = try Modal(.{
        .title = "Animated Modal",
        .width = 400,
        .open = vis,
    }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, result.overlay);

    ctx.layout();
    _ = ctx.render();

    vis.set(true);

    var opacities: [10]f32 = undefined;
    var scales: [10]f32 = undefined;
    var now_ms: f64 = 0;
    for (0..10) |i| {
        now_ms += 16.0;
        render_engine.current_frame_time_ms = now_ms;
        render_engine.current_frame_dt_ms = 16.0;
        ctx.layout();
        _ = ctx.render();
        opacities[i] = result.dialog.getOpacity();
        scales[i] = result.dialog.style.scale_x();
    }

    var first_visible_idx: ?usize = null;
    for (opacities, 0..) |opacity, i| {
        if (opacity > 0.001) {
            first_visible_idx = i;
            break;
        }
    }

    if (first_visible_idx) |idx| {
        try std.testing.expect(opacities[idx] < 0.3);
        try std.testing.expect(scales[idx] < 1.0);

        var last_opacity = opacities[idx];
        var last_scale = scales[idx];
        for (opacities[(idx + 1)..], scales[(idx + 1)..]) |opacity, scale| {
            try std.testing.expect(opacity + 0.0001 >= last_opacity);
            try std.testing.expect(scale + 0.0001 >= last_scale);
            last_opacity = opacity;
            last_scale = scale;
        }
    }
}

fn firstOpenFrame(animate_initial_open: bool) !struct { opacity: f32, scale: f32 } {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setViewport(800, 600);
    const root = try box(ctx, .{ .width = .{ .px = 800 }, .height = .{ .px = 600 } }, .{});
    ctx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const result = try Modal(.{ .title = "Mounted open", .width = 400, .open = true, .animate_initial_open = animate_initial_open }).mount(scope, ctx);
    if (!result.portaled) try root.appendChild(std.testing.allocator, result.overlay);
    render_engine.current_frame_time_ms += 16.0;
    render_engine.current_frame_dt_ms = 16.0;
    ctx.layout();
    _ = ctx.render();
    return .{ .opacity = result.dialog.getOpacity(), .scale = result.dialog.style.scale_x() };
}

test "Modal: mounted open shows at once; animate_initial_open plays the enter transition" {
    const instant = try firstOpenFrame(false);
    try std.testing.expectEqual(@as(f32, 1), instant.opacity);
    try std.testing.expectEqual(@as(f32, 1), instant.scale);
    const animated = try firstOpenFrame(true);
    try std.testing.expect(animated.opacity < 0.5);
    try std.testing.expect(animated.scale < 1);
}

test "Modal: mounted open skips only the first enter; a close then reopen animates" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setViewport(800, 600);
    const root = try box(ctx, .{ .width = .{ .px = 800 }, .height = .{ .px = 600 } }, .{});
    ctx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const vis = try scope.createSignal(bool, true);
    const result = try Modal(.{ .title = "Reopened", .width = 400, .open = vis }).mount(scope, ctx);
    if (!result.portaled) try root.appendChild(std.testing.allocator, result.overlay);
    const frame = struct {
        fn run(c: *Cx) void {
            render_engine.current_frame_time_ms += 16.0;
            render_engine.current_frame_dt_ms = 16.0;
            c.layout();
            _ = c.overlay_stack.tick(render_engine.current_frame_time_ms, 0.016, 800, 600, std.testing.allocator);
        }
    }.run;
    frame(ctx);
    try std.testing.expectEqual(@as(f32, 1), result.dialog.getOpacity());

    vis.set(false);
    for (0..30) |_| frame(ctx);
    try std.testing.expect(result.dialog.getOpacity() < 0.01);

    vis.set(true);
    frame(ctx);
    try std.testing.expect(result.dialog.getOpacity() < 0.5);
    try std.testing.expect(result.dialog.style.scale_x() < 1);
    for (0..30) |_| frame(ctx);
    try std.testing.expectEqual(@as(f32, 1), result.dialog.getOpacity());
    try std.testing.expectEqual(@as(f32, 1), result.dialog.style.scale_x());
}

test "Modal: long title wraps instead of overflowing dialog" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setViewport(800, 600);

    const root = try box(ctx, .{ .width = .{ .px = 800 }, .height = .{ .px = 600 } }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const result = try Modal(.{
        .title = "Do you want to save changes to \"03-canvas-engine-research.md\" before closing this window forever?",
        .width = 320,
    }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, result.overlay);

    ctx.layout();

    const header = result.dialog.children.items[0];
    const title_box = header.children.items[0];
    const title_rect = title_box.rectFromWorldOrFallback();
    const dialog_rect = result.dialog.rectFromWorldOrFallback();

    // titlebox width constrained in dialog (old behavior: fit content width -> horizontal overflow
    // dialog)
    try std.testing.expect(title_rect.w <= dialog_rect.w);
    // after wrap height exceeds single line (14px*1.4 ~19.6; old behavior fixed 20px clipped second
    // line)
    try std.testing.expect(title_rect.h > 30);
}

test "Modal: no title" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try box(ctx, .{ .width = .{ .px = 800 }, .height = .{ .px = 600 } }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const result = try Modal(.{}).mount(scope, ctx);

    try root.appendChild(std.testing.allocator, result.overlay);

    // no title: dialog only body
    try std.testing.expectEqual(@as(usize, 1), result.dialog.children.items.len);
}

test "Modal: dialog exposes role=dialog and a label that follows a dynamic title" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const root = try box(ctx, .{ .width = .{ .px = 800 }, .height = .{ .px = 600 } }, .{});
    ctx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const title = try scope.createText("Delete file?", .{});
    const result = try Modal(.{ .title = title, .open = true }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, result.overlay);
    const a11y = &result.dialog.behavior.interaction.a11y;
    try std.testing.expectEqual(core.A11yRole.dialog, a11y.*.?.role);
    try std.testing.expectEqualStrings("Delete file?", a11y.*.?.label.?);
    title.set("Delete 3 files?");
    // label must point to node currently-held text, not replaced old buffer
    const title_node = result.dialog.children.items[0].children.items[0];
    try std.testing.expectEqual(title_node.getText().?.content.ptr, a11y.*.?.label.?.ptr);
    try std.testing.expectEqualStrings("Delete 3 files?", a11y.*.?.label.?);
}

// styles.yss test collection, this line required, see docs/STYLING.md
test {
    _ = @import("_styles.yss.zig");
    _ = @import("confirm.zig");
}

test "Modal: mount 在任意分配点失败时不泄漏（sweep）" {
    try @import("../oom_sweep.zig").sweepMount("modal", struct {
        fn m(scope: *Scope, cx: *Cx) anyerror!?*Node {
            const r = try Modal(.{ .title = "Test Modal", .width = 400 }).mount(scope, cx);
            return r.overlay;
        }
    }.m);
}

test "Modal: split open — ✕ and Esc are proposals the parent can reject" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const root = try box(ctx, .{ .width = .{ .px = 800 }, .height = .{ .px = 600 } }, .{});
    ctx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const open = try scope.createSignal(bool, true);
    const Gate = struct {
        open: *Signal(bool),
        allow: bool = false,
        asked: u32 = 0,
        fn propose(self: *@This(), v: bool) void {
            self.asked += 1;
            if (self.allow) self.open.set(v);
        }
    };
    var gate = Gate{ .open = open };
    const result = try Modal(.{ .title = "Unsaved changes", .open = reactive.split(open, ctx.on(Gate, &gate, Gate.propose)) }).mount(scope, ctx);
    if (!result.portaled) try root.appendChild(std.testing.allocator, result.overlay);
    try std.testing.expect(result.open == null); // split: toggle owned by parent

    const close_btn = result.close_button.?;
    close_btn.behavior.events.on_click.?.invoke(); // X: rejected
    ctx.handleKeyDown(.escape, .{}); // Esc: rejected
    try std.testing.expectEqual(@as(u32, 2), gate.asked);
    try std.testing.expect(open.peek());
    try std.testing.expect(result.overlay.style.width != .px); // still open
    try std.testing.expect(!ctx.overlay_stack.anyExiting()); // layer also no self-exit

    gate.allow = true;
    ctx.handleKeyDown(.escape, .{});
    try std.testing.expect(!open.peek());
    try std.testing.expect(ctx.overlay_stack.anyExiting()); // settle then open effect drive exit
}

/// Condition of the branch in the test below (the branch build fn has no context argument).
var branch_open: ?*Signal(bool) = null;
test "Modal: mounted only while open with open derived in its branch; closing by outside click unmounts it safely" {
    // Yix `{if (open) <W.Modal open={open} onOpenChange={close}>}`: the parent's write (close)
    // unmounts the branch, which owns the derived `open` and the callback context, while the
    // Modal's write pipeline still reads the settled value. That read must come first.
    const a = std.testing.allocator;
    const control_flow = @import("../../control_flow.zig");
    const ctx = try Cx.init(a, std.testing.io);
    defer ctx.deinit();
    ctx.setViewport(800, 600);
    const root = try box(ctx, .{ .width = .{ .px = 800 }, .height = .{ .px = 600 } }, .{});
    ctx.root = root;
    _ = try ctx.ensurePopoverPortalRoot();
    const scope = try Scope.init(a, null, ctx.owner);
    defer scope.dispose();
    const open = try scope.createSignal(bool, false);
    branch_open = open;
    defer branch_open = null;
    try control_flow.Show(scope, root, open, ctx, struct {
        fn close(signal: *Signal(bool), value: bool) void {
            if (!value) signal.set(false);
        }
        fn build(s: *Scope, c: *Cx) anyerror!*Node {
            const derived = try s.derive(bool, .{ .open = branch_open.? }, struct {
                fn f(k: anytype) bool {
                    return k.open.get();
                }
            }.f);
            const m = try Modal(.{ .open = derived, .on_open_change = c.on(Signal(bool), branch_open.?, close), .enter_transition = .none, .exit_transition = .none }).mount(s, c);
            return if (m.portaled) try box(c, .{}, .{}) else m.overlay;
        }
    }.build);
    for (0..3) |_| {
        open.set(true);
        ctx.layout();
        _ = ctx.render();
        try std.testing.expect(ctx.overlay_stack.layer_count == 1);
        // Click on the barrier (outside the dialog panel): the Modal proposes close.
        ctx.handleMouseDown(5, 5, .{});
        ctx.handleMouseUp(5, 5);
        _ = ctx.render();
        try std.testing.expect(!open.peek());
        ctx.layout();
        _ = ctx.render();
        try std.testing.expectEqual(@as(usize, 0), ctx.overlay_stack.layer_count);
    }
}

test "Modal: composition Escape reaches Input and Textarea before overlay dismissal" {
    const input_mod = @import("../input/mod.zig");
    inline for (.{ false, true }) |multiline| {
        const ctx = try Cx.init(std.testing.allocator, std.testing.io);
        defer ctx.deinit();
        ctx.root = try box(ctx, .{ .width = .{ .px = 800 }, .height = .{ .px = 600 } }, .{});
        ctx.setViewport(800, 600);
        const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
        defer scope.dispose();
        const visible = try scope.createSignal(bool, false);
        const modal = try Modal(.{ .open = visible, .enter_transition = .none, .exit_transition = .none }).mount(scope, ctx);
        if (!modal.portaled) try ctx.root.?.appendChild(std.testing.allocator, modal.overlay);
        const field = if (multiline) blk: {
            const mounted = try input_mod.Textarea(.{ .value = "draft" }).mountResult(scope, ctx);
            try modal.body.appendChild(std.testing.allocator, mounted.wrapper);
            break :blk mounted.input;
        } else blk: {
            const mounted = try input_mod.Input(.{ .value = "draft" }).mountResult(scope, ctx);
            try modal.body.appendChild(std.testing.allocator, mounted.node);
            break :blk mounted.input_container;
        };
        visible.set(true);
        ctx.layout();
        ctx.setFocus(field);
        try std.testing.expect(ctx.isFocused(field));
        ctx.handleImePreedit("候", 3);
        const client = field.behavior.interaction.text_input_client.?;
        try std.testing.expect(client.is_composing.?(client.context));
        ctx.handleKeyDown(.escape, .{});
        try std.testing.expect(visible.peek());
        try std.testing.expect(!client.is_composing.?(client.context));
        try std.testing.expect(ctx.isFocused(field));
        ctx.handleKeyDown(.escape, .{});
        try std.testing.expect(!visible.peek());
    }
}

const FocusFixture = struct {
    cx: *Cx,
    scope: *Scope,
    root: *Node,
    outside: *Node,

    fn init() !FocusFixture {
        const cx = try Cx.init(std.testing.allocator, std.testing.io);
        errdefer cx.deinit();
        cx.setViewport(800, 600);
        const root = try box(cx, .{ .width = .{ .px = 800 }, .height = .{ .px = 600 } }, .{});
        cx.root = root;
        const outside = try box(cx, .{ .width = .{ .px = 100 }, .height = .{ .px = 30 } }, .{});
        outside.behavior.interaction.focusable = true;
        try root.appendChild(std.testing.allocator, outside);
        return .{ .cx = cx, .scope = try Scope.init(std.testing.allocator, null, cx.owner), .root = root, .outside = outside };
    }
    fn deinit(f: *FocusFixture) void {
        f.scope.dispose();
        f.cx.deinit();
    }
    /// Mount a Modal with two focusable boxes ("a", "b"; `b_auto`: b is a declared autoFocus
    /// target) in its body, the way a template fills it: after the Modal mounted.
    fn modal(f: *FocusFixture, open: anytype, b_auto: bool) !struct { result: ModalResult, a: *Node, b: *Node } {
        const result = try Modal(.{ .title = "Dialog", .open = open }).mount(f.scope, f.cx);
        if (!result.portaled) try f.root.appendChild(std.testing.allocator, result.overlay);
        var a: *Node = undefined;
        var b: *Node = undefined;
        try view.mount(f.scope, f.cx, result.body, view.col(.{}, .{
            view.capture(&a, view.box(.{ .focusable = true, .style = .{ .width = .{ .px = 60 }, .height = .{ .px = 20 } } }, {})),
            view.capture(&b, view.box(.{ .focusable = true, .focus_id = "dialog.b", .auto_focus = b_auto, .style = .{ .width = .{ .px = 60 }, .height = .{ .px = 20 } } }, {})),
        }));
        return .{ .result = result, .a = a, .b = b };
    }
    fn frame(f: *FocusFixture) void {
        f.cx.layout();
        _ = f.cx.render();
    }
};

test "Modal: mounted open, focus moves into the dialog once its content is in the focus order" {
    var f = try FocusFixture.init();
    defer f.deinit();
    f.cx.focus_manager.setFocus(f.outside);
    const m = try f.modal(true, false);
    f.frame();
    try std.testing.expect(f.cx.focus_manager.getFocused() == m.a);
}

test "Modal: opened right after mount, focus moves into the dialog" {
    var f = try FocusFixture.init();
    defer f.deinit();
    const open = try f.scope.createSignal(bool, false);
    f.cx.focus_manager.setFocus(f.outside);
    const m = try f.modal(open, false);
    open.set(true);
    f.frame();
    try std.testing.expect(f.cx.focus_manager.getFocused() == m.a);
}

test "Modal: a declared autoFocus target inside wins, on every open" {
    var f = try FocusFixture.init();
    defer f.deinit();
    const open = try f.scope.createSignal(bool, false);
    const m = try f.modal(open, true);
    f.frame();
    f.cx.focus_manager.setFocus(f.outside);
    // Closed at mount: autoFocus waits for the dialog instead of focusing hidden content.
    try std.testing.expect(f.cx.focus_manager.getFocused() == f.outside);
    open.set(true);
    f.frame();
    try std.testing.expect(f.cx.focus_manager.getFocused() == m.b);
    open.set(false);
    f.frame();
    open.set(true);
    f.frame();
    try std.testing.expect(f.cx.focus_manager.getFocused() == m.b);
}

test "Modal: initial_focus names the control focused on each open; return_focus names where focus goes back" {
    var f = try FocusFixture.init();
    defer f.deinit();
    const open = try f.scope.createSignal(bool, false);
    const initial = try f.scope.createSignal(?[]const u8, "dialog.b");
    const back = try f.scope.createSignal(?[]const u8, null);
    const result = try Modal(.{ .title = "Dialog", .open = open, .initial_focus = initial, .return_focus = back }).mount(f.scope, f.cx);
    if (!result.portaled) try f.root.appendChild(std.testing.allocator, result.overlay);
    var a: *Node = undefined;
    var b: *Node = undefined;
    try view.mount(f.scope, f.cx, result.body, view.col(.{}, .{
        view.capture(&a, view.box(.{ .focusable = true, .focus_id = "dialog.a", .style = .{ .width = .{ .px = 60 }, .height = .{ .px = 20 } } }, {})),
        view.capture(&b, view.box(.{ .focusable = true, .focus_id = "dialog.b", .style = .{ .width = .{ .px = 60 }, .height = .{ .px = 20 } } }, {})),
    }));
    var other: *Node = undefined;
    try view.mount(f.scope, f.cx, f.root, view.capture(&other, view.box(.{ .focusable = true, .focus_id = "page.other", .style = .{ .width = .{ .px = 60 }, .height = .{ .px = 20 } } }, {})));
    f.frame();
    const fm = &f.cx.focus_manager;
    fm.setFocus(f.outside);
    open.set(true);
    f.frame();
    try std.testing.expect(fm.getFocused() == b);
    open.set(false);
    f.frame();
    try std.testing.expect(fm.getFocused() == f.outside);
    // Read at each open / close.
    initial.set("dialog.a");
    back.set("page.other");
    open.set(true);
    f.frame();
    try std.testing.expect(fm.getFocused() == a);
    open.set(false);
    f.frame();
    try std.testing.expect(fm.getFocused() == other);
    // A named control that is hidden: the dialog panel holds focus (not a control), then it.
    initial.set("dialog.b");
    back.set(null);
    b.setDisplay(.none);
    fm.setFocus(f.outside);
    open.set(true);
    f.frame();
    try std.testing.expect(fm.getFocused() == result.dialog);
    b.setDisplay(.flex);
    f.frame();
    try std.testing.expect(fm.getFocused() == b);
}

test "Modal: focus put inside the dialog before it opens stays there" {
    var f = try FocusFixture.init();
    defer f.deinit();
    const open = try f.scope.createSignal(bool, false);
    const m = try f.modal(open, false);
    f.frame();
    f.cx.focus_manager.setFocus(m.b);
    open.set(true);
    f.frame();
    try std.testing.expect(f.cx.focus_manager.getFocused() == m.b);
}

test "Modal: a closed Modal's content is not in the Tab order" {
    var f = try FocusFixture.init();
    defer f.deinit();
    const open = try f.scope.createSignal(bool, false);
    const m = try f.modal(open, false);
    f.frame();
    const fm = &f.cx.focus_manager;
    fm.clearFocus();
    for (0..4) |_| {
        f.cx.handleKeyDown(.tab, .{});
        try std.testing.expect(fm.getFocused() == f.outside);
    }
    // Open: Tab cycles inside the dialog only.
    open.set(true);
    f.frame();
    try std.testing.expect(fm.getFocused() == m.a);
    f.cx.handleKeyDown(.tab, .{});
    try std.testing.expect(fm.getFocused() == m.b);
    // Closed again (exit animation running, then committed): back to the page only.
    open.set(false);
    f.frame();
    fm.clearFocus();
    for (0..4) |_| {
        f.cx.handleKeyDown(.tab, .{});
        try std.testing.expect(fm.getFocused() == f.outside);
    }
}

test "Modal: width / max_height / height follow their sources; a fixed height gives the body the rest" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setViewport(1000, 800);
    const root = try box(ctx, .{ .width = .{ .px = 1000 }, .height = .{ .px = 800 } }, .{});
    ctx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const width = try scope.createSignal(f32, 400);
    const height = try scope.createSignal(?f32, null);
    const r = try Modal(.{ .title = "Size", .open = true, .width = width, .max_height = 500, .height = height }).mount(scope, ctx);
    if (!r.portaled) try root.appendChild(std.testing.allocator, r.overlay);
    _ = try core.adoptChild(ctx, std.testing.allocator, r.body, try box(ctx, .{ .width = .{ .px = 50 }, .height = .{ .px = 40 } }, .{}));
    ctx.layout();
    try std.testing.expectApproxEqAbs(@as(f32, 400), r.dialog.rectFromWorldOrFallback().w, 0.5);
    const fitted = r.dialog.rectFromWorldOrFallback().h;
    try std.testing.expect(fitted < 200);
    width.set(640);
    height.set(450);
    ctx.layout();
    try std.testing.expectApproxEqAbs(@as(f32, 640), r.dialog.rectFromWorldOrFallback().w, 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 450), r.dialog.rectFromWorldOrFallback().h, 0.5);
    // The body grows into the fixed height (title bar above it).
    const body = r.body.rectFromWorldOrFallback();
    try std.testing.expect(body.h > 450 - 80);
    height.set(null);
    ctx.layout();
    try std.testing.expectApproxEqAbs(fitted, r.dialog.rectFromWorldOrFallback().h, 0.5);
}

test "Modal: body_padding / body_gap replace the body spacing; parts reach the body" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setViewport(1000, 800);
    const root = try box(ctx, .{ .width = .{ .px = 1000 }, .height = .{ .px = 800 } }, .{});
    ctx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const plain = try Modal(.{ .title = "Plain", .open = true }).mount(scope, ctx);
    try std.testing.expectEqual(@as(f32, 20), plain.body.style.padding.left);
    try std.testing.expectEqual(ctx.tokens.tokens.space.space400, plain.body.style.gap);
    const flush = try Modal(.{ .title = "Flush", .open = true, .body_padding = Padding.all(0), .body_gap = 4 }).mount(scope, ctx);
    try std.testing.expectEqual(@as(f32, 0), flush.body.style.padding.left);
    try std.testing.expectEqual(@as(f32, 0), flush.body.style.padding.top);
    try std.testing.expectEqual(@as(f32, 4), flush.body.style.gap);
    // parts.body (what a template's `parts={.{ .body = … }}` produces) lands on the body slot.
    var holder: *Node = undefined;
    try view.mount(scope, ctx, root, view.capture(&holder, view.box(.{}, .{
        view.attrs(.{ .parts = .{ .body = .{ .test_id = "modal.parts.body" } } }, Modal(.{ .title = "Parts", .open = true })),
    })));
    var found = false;
    for (ctx.overlay_stack.layers.items) |slot| if (slot) |layer| if (layer.barrier_node) |b| {
        if (findTestId(b, "modal.parts.body") != null) found = true;
    };
    try std.testing.expect(found);
}

fn findTestId(n: *Node, id: []const u8) ?*Node {
    if (n.meta.ownership.meta.test_id) |t| if (std.mem.eql(u8, t, id)) return n;
    for (n.children.items) |c| if (findTestId(c, id)) |r| return r;
    return null;
}

test "Modal: the body stays inside a fixed / capped dialog when its content is taller" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setViewport(1000, 800);
    const root = try box(ctx, .{ .width = .{ .px = 1000 }, .height = .{ .px = 800 } }, .{});
    ctx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const height = try scope.createSignal(?f32, 300);
    const r = try Modal(.{ .open = true, .width = 400, .max_height = 360, .height = height, .body_padding = Padding.all(0), .body_gap = 0 }).mount(scope, ctx);
    if (!r.portaled) try root.appendChild(std.testing.allocator, r.overlay);
    // A column that scrolls / clips its own content: it may shrink to the body (min 0).
    const column = try core.adoptChild(ctx, std.testing.allocator, r.body, try box(ctx, .{ .width = .{ .grow = .{} }, .height = .{ .grow = .{ .min = 0 } }, .min_height = 0, .direction = .column, .overflow_hidden = true }, .{}));
    _ = try core.adoptChild(ctx, std.testing.allocator, column, try box(ctx, .{ .width = .{ .px = 50 }, .height = .{ .px = 1000 }, .flex_shrink = 0 }, .{}));
    const foot = try core.adoptChild(ctx, std.testing.allocator, r.body, try box(ctx, .{ .width = .{ .grow = .{} }, .height = .{ .px = 40 }, .flex_shrink = 0 }, .{}));
    for ([_]?f32{ 300, null }) |h| {
        height.set(h);
        ctx.layout();
        const dialog = r.dialog.rectFromWorldOrFallback();
        const body = r.body.rectFromWorldOrFallback();
        try std.testing.expectApproxEqAbs(@as(f32, h orelse 360), dialog.h, 0.5);
        try std.testing.expect(body.y + body.h <= dialog.y + dialog.h + 0.5);
        // The footer under the scrolling column stays inside the panel.
        const f = foot.rectFromWorldOrFallback();
        try std.testing.expect(f.y + f.h <= dialog.y + dialog.h + 0.5);
    }
}

test "Modal: the close button is a native Button part — default name and test id, parts rename it, close_label follows" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const root = try box(ctx, .{ .width = .{ .px = 800 }, .height = .{ .px = 600 } }, .{});
    ctx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const plain = try Modal(.{ .title = "Plain", .open = true }).mount(scope, ctx);
    if (!plain.portaled) try root.appendChild(std.testing.allocator, plain.overlay);
    const plain_close = plain.close_button.?;
    try std.testing.expect(findTestId(plain.dialog, "modal.close") == plain_close);
    try std.testing.expectEqual(core.A11yRole.button, plain_close.behavior.interaction.a11y.?.role);
    try std.testing.expectEqualStrings("Close", plain_close.behavior.interaction.a11y.?.label.?);

    // Through ui.view: parts name the button; the Modal keeps its role, name and action.
    const label = try scope.createText("关闭日志", .{});
    var named: ModalResult = undefined;
    try root.appendChild(std.testing.allocator, try view.render(scope, ctx, view.box(.{}, .{
        view.capture(&named, view.with(Modal(.{ .title = "Log", .open = true, .close_label = label }), .{}).parts(.{ .close_button = "log.close" })),
    })));
    if (!named.portaled) try root.appendChild(std.testing.allocator, named.overlay);
    const close = named.close_button.?;
    try std.testing.expect(findTestId(named.dialog, "log.close") == close);
    try std.testing.expectEqual(core.A11yRole.button, close.behavior.interaction.a11y.?.role);
    try std.testing.expectEqualStrings("关闭日志", close.behavior.interaction.a11y.?.label.?);
    label.set("Close the log");
    try std.testing.expectEqualStrings("Close the log", close.behavior.interaction.a11y.?.label.?);
    try std.testing.expectEqual(core.A11yRole.button, close.behavior.interaction.a11y.?.role);
    // Still the close proposal.
    close.behavior.events.on_click.?.invoke();
    try std.testing.expect(!named.open.?.peek());

    // No title bar: no title, no close button; a parts entry for it is skipped.
    var bare: ModalResult = undefined;
    try root.appendChild(std.testing.allocator, try view.render(scope, ctx, view.box(.{}, .{
        view.capture(&bare, view.with(Modal(.{ .open = true }), .{}).parts(.{ .close_button = "never" })),
    })));
    if (!bare.portaled) try root.appendChild(std.testing.allocator, bare.overlay);
    try std.testing.expect(bare.close_button == null);
    try std.testing.expect(bare.title == null);
}

test "Modal: closable hides the close button and its slot; a source is followed" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const root = try box(ctx, .{ .width = .{ .px = 800 }, .height = .{ .px = 600 } }, .{});
    ctx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const closable = try scope.createSignal(bool, false);
    const r = try Modal(.{ .title = "Busy", .open = true, .closable = closable }).mount(scope, ctx);
    if (!r.portaled) try root.appendChild(std.testing.allocator, r.overlay);
    const place = r.dialog.children.items[2];
    const slot = r.dialog.children.items[0].children.items[1];
    try std.testing.expectEqual(core.Display.none, place.style.display);
    try std.testing.expectEqual(core.Display.none, slot.style.display);
    closable.set(true);
    try std.testing.expect(place.style.display != .none);
    try std.testing.expect(slot.style.display != .none);
}

fn focusedWithin(ctx: *Cx, node: *Node) bool {
    const f = ctx.focus_manager.getFocused() orelse return false;
    return f == node or f.isDescendantOf(node);
}

test "Modal: the dialog's initial focus goes to the body's first control, not the close button" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setViewport(800, 600);
    const root = try box(ctx, .{ .width = .{ .px = 800 }, .height = .{ .px = 600 } }, .{});
    ctx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const open = try scope.createSignal(bool, false);
    const r = try Modal(.{ .title = "Rename", .open = open, .enter_transition = .none }).mount(scope, ctx);
    if (!r.portaled) try root.appendChild(std.testing.allocator, r.overlay);
    const field = try box(ctx, .{ .width = .{ .px = 100 }, .height = .{ .px = 20 } }, .{});
    field.setFocusable(true);
    try r.body.appendChild(std.testing.allocator, field);
    _ = ctx.render();
    open.set(true);
    _ = ctx.render();
    try std.testing.expect(ctx.focus_manager.getFocused() == field);

    // Nothing focusable in the body: the close button.
    const empty_open = try scope.createSignal(bool, false);
    const e = try Modal(.{ .title = "Note", .open = empty_open, .enter_transition = .none }).mount(scope, ctx);
    if (!e.portaled) try root.appendChild(std.testing.allocator, e.overlay);
    open.set(false);
    _ = ctx.render();
    empty_open.set(true);
    _ = ctx.render();
    try std.testing.expect(focusedWithin(ctx, e.close_button.?));
}


const WithinRig = struct {
    ctx: *Cx,
    scope: *Scope,
    root: *Node,

    fn init() !WithinRig {
        const ctx = try Cx.init(std.testing.allocator, std.testing.io);
        errdefer ctx.deinit();
        ctx.setViewport(1000, 800);
        const root = try box(ctx, .{ .width = .{ .px = 1000 }, .height = .{ .px = 800 }, .direction = .row }, .{});
        ctx.root = root;
        return .{ .ctx = ctx, .scope = try Scope.init(std.testing.allocator, null, ctx.owner), .root = root };
    }

    fn deinit(self: WithinRig) void {
        self.scope.dispose();
        self.ctx.deinit();
    }

    fn pane(self: WithinRig, w: f32, h: f32) !*Node {
        const n = try box(self.ctx, .{ .width = .{ .px = w }, .height = .{ .px = h }, .flex_shrink = 0 }, .{});
        try self.root.appendChild(std.testing.allocator, n);
        return n;
    }

    fn frame(self: WithinRig) void {
        _ = self.ctx.render();
        self.ctx.frame_count += 1;
    }

    fn mount(self: WithinRig, props: anytype) !ModalResult {
        const r = try Modal(props).mount(self.scope, self.ctx);
        if (!r.portaled) try self.root.appendChild(std.testing.allocator, r.overlay);
        return r;
    }
};

fn centreOf(n: *Node) [2]f32 {
    const g = n.globalRect();
    return .{ g.x + g.w / 2, g.y + g.h / 2 };
}

test "Modal: within centres the dialog on a node's area and follows the node as the layout changes" {
    const rig = try WithinRig.init();
    defer rig.deinit();
    const left = try rig.pane(500, 800);
    const right = try rig.pane(500, 800);
    const r = try rig.mount(.{ .open = true, .width = 300, .height = 200, .within = .{ .node = right }, .enter_transition = .none });
    rig.frame();
    var c = centreOf(r.dialog);
    try std.testing.expectApproxEqAbs(@as(f32, 750), c[0], 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 400), c[1], 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 300), r.dialog.globalRect().w, 0.5);
    // A split drag: the left pane grows, the right one moves and narrows; nobody writes the Modal.
    left.style.width = .{ .px = 700 };
    left.markLayoutDirty();
    right.style.width = .{ .px = 300 };
    right.markLayoutDirty();
    rig.frame();
    c = centreOf(r.dialog);
    try std.testing.expectApproxEqAbs(@as(f32, 850), c[0], 0.5);
    // Bounded by the area: 300 − 2 × 8.
    try std.testing.expectApproxEqAbs(@as(f32, 284), r.dialog.globalRect().w, 0.5);
}

test "Modal: within bounds the dialog by the area; taller content scrolls in the body" {
    const rig = try WithinRig.init();
    defer rig.deinit();
    const area = try rig.pane(400, 300);
    const r = try rig.mount(.{ .open = true, .width = 520, .max_height = 10000, .within = .{ .node = area }, .within_padding = 12, .body_padding = Padding.all(0), .enter_transition = .none });
    _ = try core.adoptChild(rig.ctx, std.testing.allocator, r.body, try box(rig.ctx, .{ .width = .{ .px = 50 }, .height = .{ .px = 1000 }, .flex_shrink = 0 }, .{}));
    rig.frame();
    const d = r.dialog.globalRect();
    try std.testing.expectApproxEqAbs(@as(f32, 400 - 24), d.w, 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 300 - 24), d.h, 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 12), d.x, 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 12), d.y, 0.5);
}

test "Modal: within follows its source and a virtual area; null goes back to the whole window" {
    const rig = try WithinRig.init();
    defer rig.deinit();
    const a = try rig.pane(400, 800);
    const b = try rig.pane(600, 800);
    const Area = struct {
        rect: overlay_stack.AnchorRect = .{ .x = 0, .y = 0, .w = 400, .h = 400 },
        fn get(raw: *anyopaque) overlay_stack.AnchorRect {
            return @as(*@This(), @ptrCast(@alignCast(raw))).rect;
        }
    };
    var virt = Area{};
    const area = try rig.scope.createSignal(?overlay_stack.Anchor, .{ .node = a });
    const r = try rig.mount(.{ .open = true, .width = 300, .height = 200, .within = area, .enter_transition = .none });
    rig.frame();
    try std.testing.expectApproxEqAbs(@as(f32, 200), centreOf(r.dialog)[0], 0.5);
    area.set(.{ .node = b });
    rig.frame();
    try std.testing.expectApproxEqAbs(@as(f32, 700), centreOf(r.dialog)[0], 0.5);
    area.set(.{ .virtual = .{ .ctx = @ptrCast(&virt), .getRect = Area.get } });
    rig.frame();
    try std.testing.expectApproxEqAbs(@as(f32, 200), centreOf(r.dialog)[0], 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 200), centreOf(r.dialog)[1], 0.5);
    // A virtual area is read after every layout; a rect that moves without a layout change asks
    // for one (here: the caller's own node).
    virt.rect = .{ .x = 600, .y = 400, .w = 400, .h = 400 };
    a.markLayoutDirty();
    rig.frame();
    try std.testing.expectApproxEqAbs(@as(f32, 800), centreOf(r.dialog)[0], 0.5);
    area.set(null);
    rig.frame();
    try std.testing.expectApproxEqAbs(@as(f32, 500), centreOf(r.dialog)[0], 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 400), centreOf(r.dialog)[1], 0.5);
}

test "Modal: a static within node that is freed, hidden or too small places the dialog in the window; it stays open" {
    const rig = try WithinRig.init();
    defer rig.deinit();
    const keep = try rig.pane(300, 800);
    const area = try rig.pane(700, 800);
    _ = keep;
    const r = try rig.mount(.{ .open = true, .width = 300, .height = 200, .within = .{ .node = area }, .enter_transition = .none });
    rig.frame();
    try std.testing.expectApproxEqAbs(@as(f32, 650), centreOf(r.dialog)[0], 0.5);
    // Too small after padding (< WithinPlacement.min_width): the whole window.
    area.style.width = .{ .px = 150 };
    area.markLayoutDirty();
    rig.frame();
    try std.testing.expectApproxEqAbs(@as(f32, 500), centreOf(r.dialog)[0], 0.5);
    area.style.width = .{ .px = 700 };
    area.markLayoutDirty();
    rig.frame();
    try std.testing.expectApproxEqAbs(@as(f32, 650), centreOf(r.dialog)[0], 0.5);
    // Hidden.
    area.setDisplay(.none);
    rig.frame();
    try std.testing.expectApproxEqAbs(@as(f32, 500), centreOf(r.dialog)[0], 0.5);
    area.setDisplay(.flex);
    rig.frame();
    try std.testing.expectApproxEqAbs(@as(f32, 650), centreOf(r.dialog)[0], 0.5);
    // Freed while the dialog is open: no access to the freed node, the dialog stays open.
    rig.ctx.detachChild(rig.root, area);
    rig.ctx.freeNode(area);
    rig.frame();
    try std.testing.expectApproxEqAbs(@as(f32, 500), centreOf(r.dialog)[0], 0.5);
    try std.testing.expect(r.open.?.peek());
}

test "Modal: a within area clipped by a scroll area uses its visible part" {
    const rig = try WithinRig.init();
    defer rig.deinit();
    const clip = try box(rig.ctx, .{ .width = .{ .px = 600 }, .height = .{ .px = 400 }, .overflow_hidden = true, .flex_shrink = 0 }, .{});
    try rig.root.appendChild(std.testing.allocator, clip);
    const tall = try box(rig.ctx, .{ .width = .{ .px = 600 }, .height = .{ .px = 2000 }, .flex_shrink = 0 }, .{});
    try clip.appendChild(std.testing.allocator, tall);
    const r = try rig.mount(.{ .open = true, .width = 300, .height = 200, .within = .{ .node = tall }, .enter_transition = .none });
    rig.frame();
    const c = centreOf(r.dialog);
    try std.testing.expectApproxEqAbs(@as(f32, 300), c[0], 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 200), c[1], 0.5);
}

test "Modal: within leaves the overlay part's own layout styles alone and is unchanged when null" {
    const rig = try WithinRig.init();
    defer rig.deinit();
    const plain = try rig.mount(.{ .open = true, .width = 300, .height = 200, .enter_transition = .none });
    rig.frame();
    // No placement box without `within`: the panel is the barrier's child.
    try std.testing.expect(plain.dialog.parent == plain.overlay);
    const area = try rig.pane(400, 800);
    const r = try rig.mount(.{ .open = true, .width = 300, .height = 200, .within = .{ .node = area }, .enter_transition = .none });
    r.overlay.style.padding = Padding.all(40);
    r.overlay.markLayoutDirty();
    rig.frame();
    try std.testing.expectApproxEqAbs(@as(f32, 40), r.overlay.style.padding.top, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 200), centreOf(r.dialog)[0], 0.5);
}

test "ConfirmDialog takes within" {
    const rig = try WithinRig.init();
    defer rig.deinit();
    _ = try rig.pane(500, 800);
    const right = try rig.pane(500, 800);
    const d = try confirm.ConfirmDialog(.{ .open = true, .title = "Delete?", .within = .{ .node = right } }).mount(rig.scope, rig.ctx);
    if (!d.modal.portaled) try rig.root.appendChild(std.testing.allocator, d.modal.overlay);
    rig.frame();
    rig.frame();
    try std.testing.expectApproxEqAbs(@as(f32, 750), centreOf(d.modal.dialog)[0], 0.5);
}

test "Modal: within keeps the dialog's controls hittable; a press on the area around it is a press on the mask" {
    const button_mod = @import("../button/mod.zig");
    const Count = struct {
        clicks: usize = 0,
        fn hit(self: *@This()) void {
            self.clicks += 1;
        }
    };
    // Dynamic `within` installs the placement box between the barrier and the panel, whether the
    // area is null (whole window) or a node.
    for ([_]bool{ false, true }) |on_node| {
        const rig = try WithinRig.init();
        defer rig.deinit();
        const pane = try rig.pane(600, 800);
        const area = try rig.scope.createSignal(?Anchor, if (on_node) Anchor{ .node = pane } else null);
        const open = try rig.scope.createSignal(bool, true);
        const r = try rig.mount(.{ .open = open, .width = 300, .height = 200, .within = area, .enter_transition = .none });
        var count: Count = .{};
        const target = try button_mod.Button(.{ .label = "Go", .on_click = rig.ctx.on(Count, &count, Count.hit) }).mount(rig.scope, rig.ctx);
        try r.body.appendChild(std.testing.allocator, target);
        for (0..4) |_| rig.frame();
        const t = target.globalRect();
        rig.ctx.handleMouseDown(t.x + t.w / 2, t.y + t.h / 2, .{});
        rig.ctx.handleMouseUp(t.x + t.w / 2, t.y + t.h / 2);
        try std.testing.expectEqual(@as(usize, 1), count.clicks);
        try std.testing.expect(open.peek());
        // Outside the panel (inside the placement box's span): the mask's outside press closes.
        const d = r.dialog.globalRect();
        rig.ctx.handleMouseDown(d.x + d.w / 2, d.y + d.h + 40, .{});
        rig.ctx.handleMouseUp(d.x + d.w / 2, d.y + d.h + 40);
        for (0..4) |_| rig.frame();
        try std.testing.expect(!open.peek());
        try std.testing.expectEqual(@as(usize, 1), count.clicks);
    }
}
