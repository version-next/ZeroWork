/// ScrollArea Component
///
/// Scrollable container component with Apple-level scroll physics.
///
/// Features:
/// - overflow_hidden clipping + translate_y/x scroll offset
/// - event-driven scroll (system momentum auto-supported)
/// - scrollbar indicator: auto fade in/out, brighter/wider on hover
/// - Apple UIScrollView-level rubber banding:
///   - Damping phase: rational function f(x)=x*d*c/(d+c*x) (c=0.55, Apple standard)
///   - Rebound phase: WebKit exponential decay x(t)=(x0+v0*t*0.31)*exp(-12.5*t)
///   - Momentum overscroll directly triggers rubber band + exponential decay to zero
/// - Content size auto-adaptation
const std = @import("std");
const core = @import("../../core.zig");
const view = @import("../../view.zig");
const Cx = core.Cx;
const Node = core.Node;
const box = core.box;
const BoxStyle = core.BoxStyle;
const Color = core.Color;
const ComputedRect = core.ComputedRect;
const theme = core.theme;
const Padding = core.Padding;
const HitProxySpec = core.HitProxySpec;
const physics = @import("../../physics.zig");
const Scope = @import("../../reactive.zig").Scope;

// Submodules
pub const debug = @import("debug.zig");
const state_mod = @import("state.zig");
const scroll_event = @import("event.zig");
const scroll_scrollbar = @import("scrollbar.zig");
pub const scroll_physics = @import("physics.zig");

// Re-exports, keep external API unchanged
pub const ScrollDirection = state_mod.ScrollDirection;
pub const OverscrollBehavior = state_mod.OverscrollBehavior;
pub const ScrollbarVisibility = state_mod.ScrollbarVisibility;
pub const ScrollbarGutter = state_mod.ScrollbarGutter;
pub const ScrollbarVisual = state_mod.ScrollbarVisual;
pub const ScrollbarAxisMetrics = state_mod.ScrollbarAxisMetrics;
pub const ScrollState = state_mod.ScrollState;
pub const ScrollTuning = state_mod.ScrollTuningT;

pub const scrollEventHandler = scroll_event.scrollEventHandler;
pub const isOutwardAtBoundary = scroll_event.isOutwardAtBoundary;

pub const scrollbarBeforeRender = scroll_scrollbar.scrollbarBeforeRender;
pub const scrollbarEventHandler = scroll_scrollbar.scrollbarEventHandler;
pub const scrollbarHEventHandler = scroll_scrollbar.scrollbarHEventHandler;
pub const computeVerticalScrollbarMetrics = scroll_scrollbar.computeVerticalScrollbarMetrics;
pub const computeHorizontalScrollbarMetrics = scroll_scrollbar.computeHorizontalScrollbarMetrics;

pub const applyVerticalScroll = scroll_physics.applyVerticalScroll;
pub const applyHorizontalScroll = scroll_physics.applyHorizontalScroll;

/// ScrollArea properties
pub const ScrollAreaProps = struct {
    /// Stable container identity for data-only restart persistence. Borrowed for scope lifetime.
    persist_key: ?[]const u8 = null,
    width: ?f32 = null,
    height: ?f32 = null,
    direction: ScrollDirection = .vertical,
    content_height: ?f32 = null,
    content_width: ?f32 = null,
    /// Scroll speed multiplier (scroll dx/dy are logical px, normalized at the event bridge, default 1.0)
    scroll_speed: f32 = 1,
    padding: Padding = Padding.ZERO,
    background: Color = Color.TRANSPARENT,
    /// Custom state ID (for cross-instance reuse or distinguishing scroll state)
    state_id: ?u64 = null,
    /// Enable rubber band (jelly rebound) effect for vertical direction
    rubber_band_y: bool = true,
    /// Enable rubber band (jelly rebound) effect for horizontal direction
    rubber_band_x: bool = true,
    /// Nested scrolling at the vertical edges (Yix `overscrollY={.contain}`; CSS
    /// `overscroll-behavior-y`): `.auto` hands input that would carry this area past an edge on to
    /// the enclosing ScrollArea (scroll chaining); `.contain` keeps it here (a wheel stops at the
    /// edge, a gesture and its momentum rubber-band here) while this area has something to scroll,
    /// and lets it through when it has not. See `OverscrollBehavior`.
    overscroll_y: OverscrollBehavior = .auto,
    /// Horizontal counterpart of `overscroll_y` (Yix `overscrollX`).
    overscroll_x: OverscrollBehavior = .auto,
    /// When the thumbs show (Yix `scrollbars={.always}`): `.auto` while scrolling / hovering, then
    /// fade; `.always` also at rest for an axis whose content overflows. See `ScrollbarVisibility`.
    scrollbars: ScrollbarVisibility = .auto,
    /// Reserve space beside the scrolling viewport for the scrollbar interaction bands
    /// (Yix `scrollbarGutter={.stable}`). See `ScrollbarGutter`.
    scrollbar_gutter: ScrollbarGutter = .none,
    /// Vertical scroll offset as a controlled value (Yix `scrollY={…}`; see offset_binding.zig).
    /// - literal (default 0): initial offset, applied once the area is laid out;
    /// - `*Signal(f32)`: two-way — writing the signal scrolls there, scrolling writes it;
    /// - read-only source + `on_scroll_y_change` (`ui.split`): the owner (view-model) keeps the
    ///   offset, e.g. one per page, and the area restores it on remount;
    /// - read-only source alone: follows the source's changes, never reports.
    /// A write is applied at the next before-render pass in which the area has a layout (never
    /// against stale or zero extents), clamped to [0, max]; it cancels momentum / bounce on the
    /// axis and wins over user scrolling of the same frame. Scrolling reports the settled offset
    /// (never the rubber-band displacement) at most once per frame, only when it changed.
    scroll_y: Model(f32) = .{ .local = 0 },
    /// Horizontal counterpart of `scroll_y` (Yix `scrollX={…}`).
    scroll_x: Model(f32) = .{ .local = 0 },
    /// Settled vertical offset changed (Yix `onScrollYChange`); with a read-only `scroll_y`
    /// it becomes the split write.
    on_scroll_y_change: ?core.Handler(f32) = null,
    on_scroll_x_change: ?core.Handler(f32) = null,
    /// Scroll edge effect (Yix `scrollEdge={.{ .edge = .top, .height = 52 }}`; AppKit / UIKit
    /// `UIScrollEdgeEffect`): a progressive blur band over the viewport edge, bound to this
    /// area's own scroll state, that appears as content scrolls under it. null = none.
    scroll_edge: ?ScrollEdgeEffect = null,
};

/// `ScrollAreaProps.scroll_edge`: a `.blur_only` `W.GlassBox` laid over the viewport edge (above
/// the content, below the scrollbars, hit-transparent) with `scroll_edge` bound to the area's
/// `ScrollState`. At rest (offset 0 on that edge) it is invisible; strength ramps with the
/// distance scrolled past the edge.
pub const ScrollEdgeEffect = struct {
    edge: glass_box.ScrollEdge = .top,
    /// `.soft` fades the blur out across `fade_width`; `.hard` is uniform over the band.
    style: glass_box.ScrollEdgeStyle = .automatic,
    /// Band thickness from the edge (pt): the header / toolbar height it sits under.
    height: f32 = 52,
    /// Soft fade length (pt) at the band's inner side.
    fade_width: f32 = 32,
    /// `.soft` only: length (pt) from the edge held at full blur before the fade starts — the
    /// part of the band a floating header covers (CSS `blur 0%, blur <hold>, none <hold +
    /// fade_width>`). 0 = the fade starts at the edge.
    hold: f32 = 0,
    /// Scroll distance (pt) for full strength.
    ramp_distance: f32 = 28,
    max_strength: f32 = 0.9,
    blur_radius: f32 = 15.5,
};
const glass_box = @import("../glass_box/mod.zig");
const Model = @import("../../reactive.zig").Model;
const offset_binding = @import("offset_binding.zig");

/// ScrollArea mount return value
pub const ScrollAreaResult = struct {
    container: *Node,
    content: *Node,
    state: *ScrollState,
    /// The scroll edge band (`ScrollAreaProps.scroll_edge`), else null.
    scroll_edge: ?*Node = null,
    /// `ui.view` integration (see src/ui/view_parts.zig).
    pub fn viewParts(self: ScrollAreaResult) core.ViewParts {
        return .{ .root = self.container, .slot = self.content };
    }
};

/// Create ScrollArea: `W.ScrollArea(.{ .width = 320, .height = 240 }).mount(scope, cx)`.
/// Scope manages ScrollState + ScrollEventCtx lifecycle.
/// AXScrollToVisible implementation for ScrollArea (registered with
/// core.a11y_scroll_into_view_hook).
fn a11yScrollIntoView(scroll: *Node, target: *Node) bool {
    if (scroll.behavior.events.on_event != scrollEventHandler) return false;
    const ev_ctx: *ScrollEventCtx = @ptrCast(@alignCast(scroll.behavior.events.event_context orelse return false));
    const content = ev_ctx.content orelse return false;
    const before_y = ev_ctx.state.scroll_y;
    const before_x = ev_ctx.state.scroll_x;
    scrollIntoView(ev_ctx.state, content, target, .nearest);
    scrollIntoViewX(ev_ctx.state, content, target, .nearest);
    return ev_ctx.state.scroll_y != before_y or ev_ctx.state.scroll_x != before_x;
}

/// Web DOM host: the browser scrolls the container natively (overflow:auto); the DOM
/// offset is the content's visual offset, -translate.
fn hostScrollQuery(container: *const Node) ?core.HostScroll {
    if (container.behavior.events.on_event != scrollEventHandler) return null;
    const ev_ctx: *ScrollEventCtx = @ptrCast(@alignCast(container.behavior.events.event_context orelse return null));
    const content = ev_ctx.content orelse return null;
    return .{
        .content = content,
        .x = -content.style.translate_x,
        .y = -content.style.translate_y,
        .axis_x = ev_ctx.direction != .vertical,
        .axis_y = ev_ctx.direction != .horizontal,
    };
}

/// The browser scrolled the container to (x, y) (DOM offsets): fold it into the
/// ScrollState like a programmatic scroll and flash the scrollbar. Returns whether
/// anything moved.
fn hostScrollSet(container: *Node, x: f32, y: f32) bool {
    if (container.behavior.events.on_event != scrollEventHandler) return false;
    const ev_ctx: *ScrollEventCtx = @ptrCast(@alignCast(container.behavior.events.event_context orelse return false));
    const content = ev_ctx.content orelse return false;
    const state = ev_ctx.state;
    // Keep viewport/content metrics current (the wheel path refreshes them per event).
    state_mod.refreshExtents(state, container, content);
    // The browser reports whole pixels: within 1px of the end is the end (else a fractional
    // maximum is never reached and the end fade stays on; an echo of our own snapped offset
    // must not pull it back).
    const max_y = state.maxScrollY();
    const max_x = state.maxScrollX();
    const ty = if (max_y > 0 and y >= max_y - 1) max_y else y;
    const tx = if (max_x > 0 and x >= max_x - 1) max_x else x;
    const dy = ty - -content.style.translate_y;
    const dx = tx - -content.style.translate_x;
    const move_y = ev_ctx.direction != .horizontal and @abs(dy) >= 0.01;
    const move_x = ev_ctx.direction != .vertical and @abs(dx) >= 0.01;
    if (move_y) setScrollY(state, content, state.scroll_y + dy);
    if (move_x) setScrollX(state, content, state.scroll_x + dx);
    if (!move_y and !move_x) return false;
    state.onScrollActivityAxes(move_y, move_x);
    container.markRenderDirty();
    return true;
}

pub fn ScrollArea(props: anytype) ScrollAreaBuilder {
    return .{ .props = @import("../../reactive.zig").props.coerce(ScrollAreaProps, props) };
}

pub const ScrollAreaBuilder = struct {
    props: ScrollAreaProps,

    pub fn mount(self: ScrollAreaBuilder, scope: *Scope, cx: *Cx) !ScrollAreaResult {
        return mountImpl(self.props, scope, cx);
    }
};

fn mountImpl(props: ScrollAreaProps, scope: *Scope, cx: *Cx) !ScrollAreaResult {
    core.a11y_scroll_into_view_hook = &a11yScrollIntoView;
    core.host_scroll_query_hook = &hostScrollQuery;
    core.host_scroll_set_hook = &hostScrollSet;
    {
        const my_scope = try scope.childScope();
        var scope_bound = false;
        errdefer if (!scope_bound) my_scope.dispose();
        const allocator = cx.allocator;
        const p = props;

        // Outer container: fixed size + overflow_hidden
        // ScrollArea container defaults to grow (fill parent); explicit size uses px
        var container_style = BoxStyle{
            // A horizontal or both-direction area lays its content out along x: the content keeps
            // at least its own width (no shrink to the viewport) and overflows sideways.
            .direction = if (p.direction == .vertical) .column else .row,
            .overflow_hidden = true,
            .background = p.background,
            .padding = p.padding,
            .width = .{ .grow = .{} },
            .height = .{ .grow = .{} },
        };
        if (p.width) |w| container_style.width = .{ .px = w };
        if (p.height) |h| container_style.height = .{ .px = h };

        // Structure: container / content column / two scrollbars (absolute positioned, hit proxy
        // for hitTest)
        const Parts = struct { content: *Node = undefined, bar_v: *Node = undefined, bar_h: *Node = undefined, track_v: *Node = undefined, track_h: *Node = undefined };
        var parts: Parts = .{};
        const bar_radius = ScrollbarVisual.idle_thickness / 2;
        // Thumbs/tracks: absolute at the padding-box origin; the per-frame hook moves the insets.
        const bar_origin: core.Inset = .{ .left = .{ .px = 0 }, .top = .{ .px = 0 } };
        // The content box spans what it scrolls. Both-axis content grows from a
        // max-content basis, with the viewport width as its minimum (see
        // docs/design/scroll-area-both-content-extent.md). Its transform is promoted
        // so scrolling does not repaint its paint chunks.
        const content_view = view.capture(&parts.content, view.box(.{ .style = BoxStyle{
            .direction = .column,
            .width = if (p.direction == .horizontal) .{ .fit = .{} } else .{ .grow = .{} },
            .height = .{ .fit = .{} },
            .flex_shrink = if (p.direction == .vertical) 1 else 0,
            .align_self = if (p.direction == .both) .start else null,
            .will_change_transform = true,
        } }, {}));
        const bars = .{
            view.capture(&parts.track_v, view.box(.{ .hit_test = false, .style = .{ .position = .absolute, .inset = bar_origin, .width = 0, .height = 0 } }, {})),
            view.capture(&parts.track_h, view.box(.{ .hit_test = false, .style = .{ .position = .absolute, .inset = bar_origin, .width = 0, .height = 0 } }, {})),
            view.capture(&parts.bar_v, view.box(.{ .style = BoxStyle{
                .width = .{ .px = ScrollbarVisual.idle_thickness },
                .height = .{ .px = ScrollbarVisual.min_length },
                .position = .absolute,
                .inset = bar_origin,
                .background = Color.TRANSPARENT,
                .border = .{ .radius = bar_radius },
                .hit_shape = .{ .rounded_rect = bar_radius },
                .clip_shape = .{ .rounded_rect = bar_radius },
            } }, {})),
            view.capture(&parts.bar_h, view.box(.{ .style = BoxStyle{
                .width = .{ .px = ScrollbarVisual.min_length },
                .height = .{ .px = ScrollbarVisual.idle_thickness },
                .position = .absolute,
                .inset = bar_origin,
                .background = Color.TRANSPARENT,
                .border = .{ .radius = bar_radius },
                .hit_shape = .{ .rounded_rect = bar_radius },
                .clip_shape = .{ .rounded_rect = bar_radius },
            } }, {})),
        };
        // Reserve space in the layout of a private clipping viewport. Applying a style to the
        // area or its content cannot replace the gutter. The browser owns the DOM scrollport.
        const stable_gutter = p.scrollbar_gutter == .stable and !@import("zenit_environment").web_host;
        const gutter: Padding = if (stable_gutter) .{
            .right = if (p.direction != .horizontal) ScrollbarVisual.interaction_band else 0,
            .bottom = if (p.direction != .vertical) ScrollbarVisual.interaction_band else 0,
        } else .ZERO;
        const root = .{ .style = container_style, .tag = .scroll };
        const container = if (stable_gutter) try view.render(my_scope, cx, view.box(root, .{
            view.box(.{
                .style = BoxStyle{
                    .direction = container_style.direction,
                    .width = .{ .grow = .{} },
                    .height = .{ .grow = .{} },
                    .min_width = 0,
                    .min_height = 0,
                    .margin = gutter,
                    .overflow_hidden = true,
                },
            }, content_view),
        } ++ bars)) else try view.render(my_scope, cx, view.box(root, .{content_view} ++ bars));
        errdefer cx.freeNode(container);
        container.meta.ownership.meta.component_name = "ScrollArea";
        // Below the container the scrollbar hook only moves `content` (translate), flips its
        // linear-text state (part of the cache stamps) and repaints thumbs / tracks with a
        // render-dirty mark on change (scrollbar.syncBar*), so the scrolled content stays
        // cacheable across frames (before_render_hook_descendants_cache_safe, audited in Debug).
        container.frame_state.state_bits.flags.before_render_hook_descendants_cache_safe = true;
        try core.bindScopeToNode(my_scope, container);
        scope_bound = true;

        const content = parts.content;
        // The scroll offset is content's translate: hit-test the content in its own space so
        // scrolling moves a hit layer instead of rebuilding the hit index (hit_runtime.HitLayer).
        content.behavior.interaction.hit_layer = true;
        const scrollbar_v = parts.bar_v;
        const scrollbar_h = parts.bar_h;
        scrollbar_v.frame_state.state_bits.flags.inspectable = false;
        scrollbar_h.frame_state.state_bits.flags.inspectable = false;
        scrollbar_v.setHitProxyProvider(thumbHitProxies(.vertical), null);
        scrollbar_h.setHitProxyProvider(thumbHitProxies(.horizontal), null);

        // Scope allocates ScrollState (retain mode: nodes not rebuilt, state lives with scope)
        const state = blk: {
            const state = try my_scope.allocator.create(ScrollState);
            errdefer my_scope.allocator.destroy(state);
            state.* = ScrollState{};
            try my_scope.registerResource(@ptrCast(state), struct {
                fn destroy(ptr: *anyopaque, alloc: std.mem.Allocator) void {
                    const s: *ScrollState = @ptrCast(@alignCast(ptr));
                    alloc.destroy(s);
                }
            }.destroy);
            break :blk state;
        };
        container.addDebugState(@ptrCast(state));

        if (p.content_height) |ch| state.content_height = ch;
        if (p.content_width) |cw| state.content_width = cw;
        state.rubber_band_y_enabled = p.rubber_band_y;
        state.rubber_band_x_enabled = p.rubber_band_x;
        if (p.scrollbars == .always) {
            if (p.direction != .horizontal) state.scrollbar_fade.persistent = true;
            if (p.direction != .vertical) state.scrollbar_fade_h.persistent = true;
        }
        if (p.height) |h| {
            if (state.viewport_height == 0) state.viewport_height = @max(0, h - container.style.contentInsets().vertical() - gutter.vertical());
        }
        if (p.width) |w| {
            if (state.viewport_width == 0) state.viewport_width = @max(0, w - container.style.contentInsets().horizontal() - gutter.horizontal());
        }

        // Node on_cleanup relay cell: must outlive my_scope (see ScrollCtxCell),
        // so attached to Cx for cleanup fallback, not my_scope.
        // After registration, ownership goes to Cx (deinit unified cleanup), so errdefer only
        // covers
        // the 'allocated but not yet registered' window, use block to limit scope.
        const cell = blk: {
            const c = try allocator.create(ScrollCtxCell);
            errdefer allocator.destroy(c);
            c.* = .{};
            try cx.registerScrollCtxCell(.{
                .ptr = @ptrCast(c),
                .can_destroy = struct {
                    fn ready(ptr: *anyopaque) bool {
                        const cc: *ScrollCtxCell = @ptrCast(@alignCast(ptr));
                        return cc.ctx == null and cc.references == 0;
                    }
                }.ready,
                .destroyFn = struct {
                    fn destroy(ptr: *anyopaque, alloc: std.mem.Allocator) void {
                        const cc: *ScrollCtxCell = @ptrCast(@alignCast(ptr));
                        alloc.destroy(cc);
                    }
                }.destroy,
            });
            break :blk c;
        };

        // Scope allocates ScrollEventCtx
        const event_ctx = blk: {
            const event_ctx = try my_scope.allocator.create(ScrollEventCtx);
            errdefer my_scope.allocator.destroy(event_ctx);
            event_ctx.* = ScrollEventCtx{
                .persist_key = p.persist_key,
                .state = state,
                .cell = cell,
                .content = content,
                .container = container,
                .scrollbar = scrollbar_v,
                .scrollbar_h = scrollbar_h,
                .track_v = parts.track_v,
                .track_h = parts.track_h,
                .cx = cx,
                .scroll_speed = p.scroll_speed,
                .direction = p.direction,
                .overscroll_y = p.overscroll_y,
                .overscroll_x = p.overscroll_x,
                .scrollbar_thumb = cx.tokens.tokens.color.scrollbar_thumb,
            };
            try my_scope.registerResource(@ptrCast(event_ctx), struct {
                fn destroy(ptr: *anyopaque, alloc: std.mem.Allocator) void {
                    const s: *ScrollEventCtx = @ptrCast(@alignCast(ptr));
                    // ctx vanishes here: sever relay cell backref. Node still alive but unbound:
                    // callbacks see cell.ctx == null, safe no-op.
                    if (s.cell) |c| c.ctx = null;
                    alloc.destroy(s);
                }
            }.destroy);

            break :blk event_ctx;
        };
        cell.ctx = event_ctx;
        _ = try offset_binding.install(my_scope, event_ctx, p.scroll_y, p.scroll_x, p.on_scroll_y_change, p.on_scroll_x_change);
        // Node may outlive scope.dispose() for one reuse cycle (e.g., VirtualList slot rebind).
        // Unbind event_ctx-based hooks/handlers before freeing ScrollEventCtx to avoid dangling
        // pointers.
        try my_scope.onCleanup(ScrollEventCtx, event_ctx, detachScrollAreaBindings);
        container.behavior.events.on_event = scrollEventHandler;
        container.behavior.events.event_context = event_ctx;
        container.behavior.events.scroll_direction_hint = switch (p.direction) {
            .vertical => .vertical,
            .horizontal => .horizontal,
            .both => .both,
        };
        container.meta.per_frame.hooks.before_render.main = scrollbarBeforeRender;
        // Extents and the clamp follow every finished layout pass, on screen or not.
        container.setLayoutObserver(scrollAreaAfterLayout, null);

        // Scrollbar attaches its own handler for hitTest hit + drag interaction handling
        scrollbar_v.behavior.events.on_event = scrollbarEventHandler;
        scrollbar_v.behavior.events.event_context = event_ctx;
        scrollbar_v.setCursor(.grab);

        // Horizontal scrollbar attaches handler
        scrollbar_h.behavior.events.on_event = scrollbarHEventHandler;
        scrollbar_h.behavior.events.event_context = event_ctx;
        scrollbar_h.setCursor(.grab);

        // Reverse: node freed before scope (e.g., ancestor freeNode releases container children,
        // but
        // ScrollArea scope is subtree of outer scope, cleanup runs on outer dispose)
        // -> on node freeNode, immediately null the event_ctx field,
        //   then detachScrollAreaBindings skips on null to avoid use-after-free.
        // Context is **cell not event_ctx**: node may outlive ctx and unbinding can't reach it
        // (see ScrollCtxCell). Writing cell is always safe, null ctx is safe no-op.
        cell.references += 6;
        container.meta.ownership.hooks.on_cleanup = .{ .callback = clearContainerOnNodeFree, .context = @ptrCast(cell) };
        scrollbar_v.meta.ownership.hooks.on_cleanup = .{ .callback = clearScrollbarOnNodeFree, .context = @ptrCast(cell) };
        scrollbar_h.meta.ownership.hooks.on_cleanup = .{ .callback = clearScrollbarHOnNodeFree, .context = @ptrCast(cell) };
        parts.track_v.meta.ownership.hooks.on_cleanup = .{ .callback = clearTrackVOnNodeFree, .context = @ptrCast(cell) };
        parts.track_h.meta.ownership.hooks.on_cleanup = .{ .callback = clearTrackHOnNodeFree, .context = @ptrCast(cell) };
        content.meta.ownership.hooks.on_cleanup = .{ .callback = clearContentOnNodeFree, .context = @ptrCast(cell) };

        // Apply initial scroll position
        content.style.translate_y = state.contentTranslateY();
        content.style.translate_x = state.contentTranslateX();

        // Register ScrollArea container to PropertyTree.scrolls + InteractionTable.
        // Write real scroll_id to InteractionTable for layerize's PromotionHint to recognize.
        // ScrollArea state also holds scroll_id for updateScrollOffset during scroll.
        if (container.element_id_raw != 0xFFFFFFFF) {
            const cx_core = @import("../../core.zig");
            const property_tree_mod = @import("../../core/property_tree.zig");
            const eid = cx_core.world.ElementId.fromRaw(container.element_id_raw);

            const w_size: f32 = if (p.width) |w| w else 0;
            const h_size: f32 = if (p.height) |h| h else 0;
            const scroll_id = cx.property_tree.appendScroll(.{
                .parent = property_tree_mod.INVALID_ID,
                .transform_id = property_tree_mod.INVALID_ID,
                .node_id = container.id,
                .content_size = .{ .width = w_size, .height = h_size },
                .viewport_size = .{ .width = w_size, .height = h_size },
            }) catch property_tree_mod.INVALID_ID;

            // Registration failure = scroll_id allocated but layerize's PromotionHint never sees
            // it,
            // manifests as silent scroll failure (no error). Propagate here, don't swallow.
            try cx.world.interaction.put(eid, .{
                .scroll_id = scroll_id,
            });

            state.world_scroll_id = scroll_id;
            state.world_ref = @ptrCast(&cx.world);
        }

        const viewport_child = if (stable_gutter) content.parent.? else content;
        const edge_node: ?*Node = if (p.scroll_edge) |se| try mountScrollEdge(my_scope, cx, container, viewport_child, state, se) else null;
        return .{ .container = container, .content = content, .state = state, .scroll_edge = edge_node };
    }
}

/// The scroll edge band, inserted right after the content (scrollbars stay on top).
fn mountScrollEdge(scope: *Scope, cx: *Cx, container: *Node, viewport_child: *Node, state: *ScrollState, se: ScrollEdgeEffect) !*Node {
    const a = cx.allocator;
    const horizontal_band = se.edge == .top or se.edge == .bottom;
    const band = try glass_box.GlassBox(.{
        .shape = .{ .rounded = 0 },
        .material = .blur_only,
        .blur_radius = se.blur_radius,
        .drop_shadow = false,
        .padding = Padding.all(0),
        .body_gap = 0,
        .scroll_edge = .{
            .scroll = state,
            .edge = se.edge,
            .style = se.style,
            .fade_width = se.fade_width,
            .hold = se.hold,
            .ramp_distance = se.ramp_distance,
            .max_strength = se.max_strength,
        },
    }).mount(scope, cx);
    errdefer cx.freeNode(band);
    band.style.position = .absolute;
    band.style.width = if (horizontal_band) .{ .grow = .{} } else .{ .px = se.height };
    band.style.height = if (horizontal_band) .{ .px = se.height } else .{ .grow = .{} };
    const ext = try band.style.ensureExtFallible(a);
    const zero: core.InsetValue = .{ .px = 0 };
    ext.inset = switch (se.edge) {
        .top => .{ .top = zero, .left = zero },
        .bottom => .{ .bottom = zero, .left = zero },
        .left => .{ .top = zero, .left = zero },
        .right => .{ .top = zero, .right = zero },
    };
    // Pointer, wheel and a11y go to the content underneath.
    ext.hit_behavior = .pass_through;
    band.behavior.interaction.a11y = null;
    band.meta.ownership.meta.component_name = "ScrollEdgeEffect";
    const after = std.mem.indexOfScalar(*Node, container.children.items, viewport_child).? + 1;
    try container.insertChildBefore(a, band, if (after < container.children.items.len) container.children.items[after] else null);
    return band;
}

// ============================================================================
// Programmatic scroll: public API
//
// Apps scrolling an element into view must not write `state.scroll_y` directly: that
// skips three essentials (clamp, momentum/bounce reset, translate pixel alignment),
// leaving residual momentum scrolling content away and text half-pixel jitter.
// This is the single correct entry point.
// ============================================================================

/// Alignment mode
pub const ScrollAlign = enum {
    /// If fully visible, don't scroll (minimum motion to bring into view)
    nearest,
    /// Align element top to viewport top
    start,
    /// Align element bottom to viewport bottom
    end,
    /// Center element in viewport
    center,
};

/// The ScrollArea context of `content`'s container, or null when `content` is not the content node
/// of a mounted area (bare state / content pairs in tests and embedders).
fn areaCtxOf(content: *const Node) ?*ScrollEventCtx {
    const viewport = content.parent orelse return null;
    // The stable gutter puts a private viewport between the content and the area.
    const container = if (viewport.behavior.events.on_event == scrollEventHandler) viewport else viewport.parent orelse return null;
    if (container.behavior.events.on_event != scrollEventHandler) return null;
    const ctx: *ScrollEventCtx = @ptrCast(@alignCast(container.behavior.events.event_context orelse return null));
    return if (ctx.content == content) ctx else null;
}

/// A bound area (scroll_y / scroll_x / on_scroll_*_change) whose offset moved: make sure a frame
/// comes to report it, whatever phase moved it (docs/design/scroll-area-layout-derived-state.md).
fn noteOffsetMoved(content: *const Node) void {
    const ctx = areaCtxOf(content) orelse return;
    if (ctx.offset_binding != null) ctx.cx.requestRedraw();
}

/// Programmatically set vertical scroll position. **Only correct way to write scroll_y.**
///
/// Does: clamp to [0, maxScrollY], zero rubber-band bonus and spring velocity,
/// cancel in-flight rebound animation, snap translate_y to pixel_scale grid.
///
/// A primitive: it clamps against the **stored** extents and never re-reads layout (an embedder
/// may have written a predicted `content_height` for a layout that has not run yet). The stored
/// extents follow every finished layout pass (the area's layout observer); the node-based
/// `scrollIntoView` / `scrollIntoViewX` also refresh them from the layout first.
pub fn setScrollY(state: *ScrollState, content: *Node, y: f32) void {
    const clamped = std.math.clamp(y, 0, state.maxScrollY());
    if (clamped != state.scroll_y) noteOffsetMoved(content);
    state.scroll_y = clamped;
    // Reset momentum/rebound together; else residual inertia pushes content away next frames
    state.bonus_y = 0;
    state.bonus_velocity = 0;
    state.bounce_active_y = false;
    state.momentum_spent_y = false;
    // Pixel-snap like scrollbarBeforeRender to eliminate text jitter
    content.style.translate_y = state.contentTranslateY();
    content.markHitLayerMotionPropDirty();
}

/// Scroll [top, top+height) content range vertically into view.
///
/// `top` is offset in **content coordinates** (element's distance from content top,
/// not including current scroll_y).
pub fn scrollRectIntoView(
    state: *ScrollState,
    content: *Node,
    top: f32,
    height: f32,
    alignment: ScrollAlign,
) void {
    const vh = state.viewport_height;
    const bottom = top + height;
    const cur = state.scroll_y;

    const target: f32 = switch (alignment) {
        .start => top,
        .end => bottom - vh,
        .center => top + (height - vh) / 2,
        .nearest => blk: {
            if (top < cur) break :blk top; // Above viewport -> align top
            if (bottom > cur + vh) break :blk bottom - vh; // Below viewport -> align bottom
            break :blk cur; // Fully visible -> no-op
        },
    };
    setScrollY(state, content, target);
}

/// Re-read the extents from the layout (node-based entries: the node's own rect says the layout
/// it belongs to has run).
fn refreshFromLayout(state: *ScrollState, content: *Node) void {
    const viewport = content.parent orelse return;
    const container = if (areaCtxOf(content)) |ctx| ctx.container orelse viewport else viewport;
    state_mod.refreshExtents(state, container, content);
}

/// Scroll a **fully laid-out** node into view (the extents it clamps against are read from that
/// layout, so it is correct from an after-layout hook in the frame the content changed).
///
/// Uses node-vs-content rect delta for content coords; must call after layout
/// (zero rect is no-op, won't scroll viewport to weird position).
pub fn scrollIntoView(
    state: *ScrollState,
    content: *Node,
    node: *Node,
    alignment: ScrollAlign,
) void {
    const nr = node.rectFromWorldOrFallback();
    if (nr.h <= 0) return; // Not yet laid out: don't scroll viewport to weird position with zero rect
    refreshFromLayout(state, content);

    // Accumulate layout-local y along parent chain up to content: that's the
    // content-coordinate offset (not including content's translate/scroll, as needed).
    var top: f32 = 0;
    var cur: ?*Node = node;
    var found = false;
    while (cur) |n| {
        if (n == content) {
            found = true;
            break;
        }
        top += n.rectFromWorldOrFallback().y;
        cur = n.parent;
    }
    if (!found) return; // node not in this ScrollArea

    scrollRectIntoView(state, content, top, nr.h, alignment);
}

/// Horizontal counterpart of `setScrollY`.
pub fn setScrollX(state: *ScrollState, content: *Node, x: f32) void {
    const clamped = std.math.clamp(x, 0, state.maxScrollX());
    if (clamped != state.scroll_x) noteOffsetMoved(content);
    state.scroll_x = clamped;
    state.bonus_x = 0;
    state.bonus_velocity_x = 0;
    state.bounce_active_x = false;
    state.momentum_spent_x = false;
    content.style.translate_x = state.contentTranslateX();
    content.markHitLayerMotionPropDirty();
}

/// Scroll [left, left+width) content range horizontally into view. `left`
/// is in content coordinates (not including the current scroll_x).
pub fn scrollRectIntoViewX(
    state: *ScrollState,
    content: *Node,
    left: f32,
    width: f32,
    alignment: ScrollAlign,
) void {
    const vw = state.viewport_width;
    const right = left + width;
    const cur = state.scroll_x;
    const target: f32 = switch (alignment) {
        .start => left,
        .end => right - vw,
        .center => left + (width - vw) / 2,
        .nearest => blk: {
            // Wider than the viewport: show its start.
            if (left < cur or width > vw) break :blk left;
            if (right > cur + vw) break :blk right - vw;
            break :blk cur;
        },
    };
    if (target == cur) return;
    setScrollX(state, content, target);
}

/// Horizontal counterpart of `scrollIntoView` (same laid-out-node contract).
pub fn scrollIntoViewX(
    state: *ScrollState,
    content: *Node,
    node: *Node,
    alignment: ScrollAlign,
) void {
    const nr = node.rectFromWorldOrFallback();
    if (nr.w <= 0) return;
    refreshFromLayout(state, content);
    var left: f32 = 0;
    var cur: ?*Node = node;
    var found = false;
    while (cur) |n| {
        if (n == content) {
            found = true;
            break;
        }
        left += n.rectFromWorldOrFallback().x;
        cur = n.parent;
    }
    if (!found) return;
    scrollRectIntoViewX(state, content, left, nr.w, alignment);
}

/// The container's layout observer: after every layout pass that laid the area out (visible or
/// culled), refresh the stored extents and pull the offsets back into range. A bound area that
/// moved gets a frame to report it (offset_binding.zig).
fn scrollAreaAfterLayout(container: *Node, _: ?*anyopaque) void {
    if (container.behavior.events.on_event != scrollEventHandler) return;
    const ctx: *ScrollEventCtx = @ptrCast(@alignCast(container.behavior.events.event_context orelse return));
    const content = ctx.content orelse return;
    state_mod.refreshExtents(ctx.state, container, content);
    if (ctx.state.clampOffsets(content)) noteOffsetMoved(content);
}

pub const ScrollEventCtx = state_mod.ScrollEventCtx;
pub const ScrollCtxCell = state_mod.ScrollCtxCell;

fn clearContainerOnNodeFree(ctx: *anyopaque) void {
    const cell: *ScrollCtxCell = @ptrCast(@alignCast(ctx));
    if (cell.ctx) |event_ctx| event_ctx.container = null;
    cell.release();
}

fn clearScrollbarOnNodeFree(ctx: *anyopaque) void {
    const cell: *ScrollCtxCell = @ptrCast(@alignCast(ctx));
    if (cell.ctx) |event_ctx| event_ctx.scrollbar = null;
    cell.release();
}

fn clearScrollbarHOnNodeFree(ctx: *anyopaque) void {
    const cell: *ScrollCtxCell = @ptrCast(@alignCast(ctx));
    if (cell.ctx) |event_ctx| event_ctx.scrollbar_h = null;
    cell.release();
}

fn clearTrackVOnNodeFree(ctx: *anyopaque) void {
    const cell: *ScrollCtxCell = @ptrCast(@alignCast(ctx));
    if (cell.ctx) |event_ctx| event_ctx.track_v = null;
    cell.release();
}

fn clearTrackHOnNodeFree(ctx: *anyopaque) void {
    const cell: *ScrollCtxCell = @ptrCast(@alignCast(ctx));
    if (cell.ctx) |event_ctx| event_ctx.track_h = null;
    cell.release();
}

fn clearContentOnNodeFree(ctx: *anyopaque) void {
    const cell: *ScrollCtxCell = @ptrCast(@alignCast(ctx));
    if (cell.ctx) |event_ctx| event_ctx.content = null;
    cell.release();
}

fn detachScrollAreaBindings(event_ctx: *ScrollEventCtx) void {
    const raw_ctx: *anyopaque = @ptrCast(event_ctx);
    // on_cleanup context is cell (see mountScrollArea), compare by cell here.
    const raw_cell: ?*anyopaque = if (event_ctx.cell) |c| @ptrCast(c) else null;
    // An offset scrolled since the last frame reaches the owner before the area goes.
    offset_binding.flushOnTeardown(event_ctx);
    // The binding is scope state freed with event_ctx; the hook must not reach it afterwards.
    event_ctx.offset_binding = null;

    // IMPORTANT: must clear on_cleanup on each node **before** event_ctx is freed by scope.
    // Else node's freeNode invokes callback to freed ScrollEventCtx (clearContainerOnNodeFree/
    // clearContentOnNodeFree, etc), UAF. Critical path for Textarea/VirtualList with embedded
    // ScrollArea: on outer cx.deinit the nodes survive until freeNode, but my_scope has already
    // been disposed.

    if (event_ctx.container) |container| {
        if (container.behavior.events.event_context == raw_ctx) {
            if (container.behavior.events.on_event == scrollEventHandler) {
                container.behavior.events.on_event = null;
            }
            if (container.meta.per_frame.hooks.before_render.main == scrollbarBeforeRender) {
                container.meta.per_frame.hooks.before_render.main = null;
            }
            if (container.meta.per_frame.hooks.layout_observer) |o| {
                if (o.run == scrollAreaAfterLayout) container.meta.per_frame.hooks.layout_observer = null;
            }
            container.behavior.events.event_context = null;
            container.behavior.events.scroll_direction_hint = null;
        }
        if (container.meta.ownership.hooks.on_cleanup) |cu| {
            if (raw_cell != null and cu.context == raw_cell.? and cu.callback == clearContainerOnNodeFree) {
                container.meta.ownership.hooks.on_cleanup = null;
                event_ctx.cell.?.release();
            }
        }
        event_ctx.container = null;
    }

    if (event_ctx.scrollbar) |scrollbar| {
        if (scrollbar.behavior.events.event_context == raw_ctx) {
            if (scrollbar.behavior.events.on_event == scrollbarEventHandler) {
                scrollbar.behavior.events.on_event = null;
            }
            scrollbar.behavior.events.event_context = null;
        }
        if (scrollbar.meta.ownership.hooks.on_cleanup) |cu| {
            if (raw_cell != null and cu.context == raw_cell.? and cu.callback == clearScrollbarOnNodeFree) {
                scrollbar.meta.ownership.hooks.on_cleanup = null;
                event_ctx.cell.?.release();
            }
        }
        event_ctx.scrollbar = null;
    }

    if (event_ctx.scrollbar_h) |scrollbar_h| {
        if (scrollbar_h.behavior.events.event_context == raw_ctx) {
            if (scrollbar_h.behavior.events.on_event == scrollbarHEventHandler) {
                scrollbar_h.behavior.events.on_event = null;
            }
            scrollbar_h.behavior.events.event_context = null;
        }
        if (scrollbar_h.meta.ownership.hooks.on_cleanup) |cu| {
            if (raw_cell != null and cu.context == raw_cell.? and cu.callback == clearScrollbarHOnNodeFree) {
                scrollbar_h.meta.ownership.hooks.on_cleanup = null;
                event_ctx.cell.?.release();
            }
        }
        event_ctx.scrollbar_h = null;
    }

    for ([_]?*Node{ event_ctx.track_v, event_ctx.track_h }, [_]*const fn (*anyopaque) void{ clearTrackVOnNodeFree, clearTrackHOnNodeFree }) |maybe, callback| {
        if (maybe) |track| if (track.meta.ownership.hooks.on_cleanup) |hook| {
            if (raw_cell != null and hook.context == raw_cell.? and hook.callback == callback) {
                track.meta.ownership.hooks.on_cleanup = null;
                event_ctx.cell.?.release();
            }
        };
    }
    event_ctx.track_v = null;
    event_ctx.track_h = null;

    if (event_ctx.content) |content| {
        if (content.meta.ownership.hooks.on_cleanup) |cu| {
            if (raw_cell != null and cu.context == raw_cell.? and cu.callback == clearContentOnNodeFree) {
                content.meta.ownership.hooks.on_cleanup = null;
                event_ctx.cell.?.release();
            }
        }
        event_ctx.content = null;
    }
}

/// Resting thumbs take the pointer only where they are drawn. Approached and dragged thumbs
/// widen; their larger hit area makes them easier to grab. Both follow the frame installed by
/// scrollbarBeforeRender, which marks changed bounds interaction-dirty.
fn thumbHitProxies(comptime axis: enum { vertical, horizontal }) Node.HitProxyProviderFn {
    return struct {
        fn provide(node: *const Node, _: ?*anyopaque, out: []HitProxySpec) usize {
            if (out.len < 2) return 0;
            const rect = node.rectFromWorldOrFallback();
            const hidden: HitProxySpec = .{ .local_rect = ComputedRect.init(0, 0, 0, 0), .behavior = .self_only };
            // Preserve the planned count across visibility/hover changes for a partial hit rebuild.
            out[0] = hidden;
            out[1] = hidden;
            if (rect.w <= 0 or rect.h <= 0) return 2;

            const radius = node.style.border.radius;
            const thickness = if (axis == .vertical) rect.w else rect.h;
            if (thickness >= ScrollbarVisual.active_thickness) {
                const slop = ScrollbarVisual.hover_slop;
                out[0] = .{
                    .local_rect = ComputedRect.init(-slop, -slop, rect.w + 2 * slop, rect.h + 2 * slop),
                    .shape = .{ .rounded_rect = radius },
                    .behavior = .self_only,
                };
            }
            out[1] = .{
                .local_rect = ComputedRect.init(0, 0, rect.w, rect.h),
                .shape = .{ .rounded_rect = radius },
                .behavior = .self_only,
            };
            return 2;
        }
    }.provide;
}

// ========== Tests ==========

test "ScrollArea: basic vertical" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);

    defer scope.dispose();

    const result = try ScrollArea(.{
        .width = 300,
        .height = 200,
    }).mount(scope, ctx);

    try root.appendChild(std.testing.allocator, result.container);

    for (0..10) |_| {
        const item = try box(ctx, .{
            .width = .{ .grow = .{} },
            .height = .{ .px = 40 },
            .background = theme.dark.tokens.color.bg_tertiary,
        }, .{});
        try result.content.appendChild(std.testing.allocator, item);
    }

    // COMPONENTS.json Scrollbar: content + two thumbs + two hover tracks.
    try std.testing.expectEqual(@as(usize, 5), result.container.children.items.len);
    try std.testing.expectEqual(@as(usize, 10), result.content.children.items.len);
    try std.testing.expect(result.container.style.overflow_hidden);
}

test "ScrollArea: scroll_edge mounts a hit-transparent blur band bound to its own scroll state" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const root = try box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    ctx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const result = try ScrollArea(.{ .width = 300, .height = 200, .scroll_edge = .{ .height = 48 } }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, result.container);
    for (0..20) |_| _ = try core.adoptChild(ctx, std.testing.allocator, result.content, try box(ctx, .{ .width = .{ .grow = .{} }, .height = .{ .px = 40 } }, .{}));
    const band = result.scroll_edge.?;
    // Right after the content: under the scrollbars (content + band + two thumbs + two tracks).
    try std.testing.expectEqual(@as(usize, 6), result.container.children.items.len);
    try std.testing.expect(result.container.children.items[1] == band);
    try std.testing.expectEqual(core.HitBehavior.pass_through, band.style.ext.?.hit_behavior.?);
    const glass: *glass_box.AdaptiveGlassBoxState = @ptrCast(@alignCast(band.meta.per_frame.hooks.slots.anim_state.?));
    try std.testing.expectEqual(glass_box.GlassMaterial.blur_only, glass.material);
    try std.testing.expect(glass.scroll_edge.?.scroll == result.state);

    const render_engine = @import("../../core/render_engine/mod.zig");
    const Frames = struct {
        fn run(cx: *Cx) void {
            for (0..60) |_| {
                render_engine.current_frame_time_ms += 16.0;
                render_engine.current_frame_dt_ms = 16.0;
                cx.frame_time_ms = render_engine.current_frame_time_ms;
                cx.layout();
                _ = cx.render();
            }
        }
    };
    Frames.run(ctx);
    const r = band.rectFromWorldOrFallback();
    try std.testing.expectApproxEqAbs(@as(f32, 300), r.w, 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 48), r.h, 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 0), r.y - result.container.rectFromWorldOrFallback().y, 0.5);
    // At rest: no strength. Scrolled past the ramp distance: full strength.
    try std.testing.expectEqual(@as(f32, 0), glass.edge_strength);
    // At rest the band must not blur the content under it. The shader fades between the uniform
    // base level and the gradient profile by strength (local = mix(blur_level, profile, strength)),
    // so with strength 0 the base level alone decides: it must be sharp (0), not a full blur_only
    // blur (1) — that rendered the first line under a header permanently frosted.
    const rest_params = glass.surface.style.ext.?.glass.?;
    try std.testing.expectEqual(@as(f32, 0), rest_params.blur_level);
    try std.testing.expectEqual(@as(f32, 0), restLocalBlur(rest_params, 0));
    try std.testing.expectEqual(@as(f32, 0), restLocalBlur(rest_params, 0.5));
    setScrollY(result.state, result.content, 120);
    Frames.run(ctx);
    try std.testing.expectApproxEqAbs(@as(f32, 0.9), glass.edge_strength, 0.01);
    // Scrolled: the edge of the band blurs, fading to sharp across fade_width.
    const scrolled_params = glass.surface.style.ext.?.glass.?;
    try std.testing.expect(restLocalBlur(scrolled_params, 0) > 0.85);
    try std.testing.expectApproxEqAbs(@as(f32, 0), restLocalBlur(scrolled_params, 1), 0.01);
    setScrollY(result.state, result.content, 0);
    Frames.run(ctx);
    try std.testing.expectApproxEqAbs(@as(f32, 0), glass.edge_strength, 0.01);
}

/// CPU mirror of glass.metal `gradient_blur_level` (local blur level at position `t` 0..1 along the
/// gradient axis): stop profile with smoothstep segments, faded in from the base level by strength.
fn restLocalBlur(g: core.GlassParams, t: f32) f32 {
    const bg = g.blur_gradient;
    if (bg.direction == .none or bg.strength <= 0.001) return g.blur_level;
    const n: usize = @max(@as(usize, 2), @min(@as(usize, bg.stop_count), 4));
    var prof = bg.stops[0].strength;
    for (0..n - 1) |i| {
        const p0 = bg.stops[i].pos;
        const p1 = @max(bg.stops[i + 1].pos, p0 + 1e-4);
        if (t >= p0) {
            const x = std.math.clamp((t - p0) / (p1 - p0), 0, 1);
            prof = std.math.lerp(bg.stops[i].strength, bg.stops[i + 1].strength, x * x * (3 - 2 * x));
        }
    }
    const str = std.math.clamp(bg.strength, 0, 1);
    return std.math.lerp(g.blur_level, std.math.clamp(prof, 0, 1), str);
}

test "ScrollArea: scroll_edge hold keeps the band fully frosted from the edge, then fades to sharp" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const root = try box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    ctx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const result = try ScrollArea(.{ .width = 300, .height = 200, .scroll_edge = .{ .style = .soft, .height = 76, .hold = 22.8, .fade_width = 53.2, .max_strength = 1, .blur_radius = 180 } }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, result.container);
    for (0..20) |_| _ = try core.adoptChild(ctx, std.testing.allocator, result.content, try box(ctx, .{ .width = .{ .grow = .{} }, .height = .{ .px = 40 } }, .{}));
    const glass: *glass_box.AdaptiveGlassBoxState = @ptrCast(@alignCast(result.scroll_edge.?.meta.per_frame.hooks.slots.anim_state.?));
    try std.testing.expectEqual(@as(f32, 22.8), glass.scroll_edge.?.hold);
    const render_engine = @import("../../core/render_engine/mod.zig");
    const Frames = struct {
        fn run(cx: *Cx) void {
            for (0..60) |_| {
                render_engine.current_frame_time_ms += 16.0;
                render_engine.current_frame_dt_ms = 16.0;
                cx.frame_time_ms = render_engine.current_frame_time_ms;
                cx.layout();
                _ = cx.render();
            }
        }
    };
    Frames.run(ctx);
    // At rest: sharp everywhere (hold does not change the rest behaviour).
    const rest = glass.surface.style.ext.?.glass.?;
    try std.testing.expectEqual(@as(f32, 0), restLocalBlur(rest, 0));
    try std.testing.expectEqual(@as(f32, 0), restLocalBlur(rest, 0.2));
    setScrollY(result.state, result.content, 120);
    Frames.run(ctx);
    try std.testing.expectApproxEqAbs(@as(f32, 1), glass.edge_strength, 0.01);
    const g = glass.surface.style.ext.?.glass.?;
    try std.testing.expectEqual(@as(f32, 180), g.backdrop_blur);
    try std.testing.expectEqual(@as(u8, 3), g.blur_gradient.stop_count);
    // Full blur across the held 30 %, then a smooth fade to sharp at the band's inner side.
    try std.testing.expect(restLocalBlur(g, 0) > 0.99);
    try std.testing.expect(restLocalBlur(g, 0.29) > 0.99);
    const mid = restLocalBlur(g, 0.65);
    try std.testing.expect(mid > 0.2 and mid < 0.8);
    try std.testing.expectApproxEqAbs(@as(f32, 0), restLocalBlur(g, 1), 0.01);
}

test "GlassBox: a plain blur_only layer (no scroll edge) stays uniformly blurred" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const root = try box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    ctx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const layer = try glass_box.GlassBox(.{ .material = .blur_only, .blur_radius = 12, .width = 200, .height = 40 }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, layer);
    ctx.layout();
    _ = ctx.render();
    const glass: *glass_box.AdaptiveGlassBoxState = @ptrCast(@alignCast(layer.meta.per_frame.hooks.slots.anim_state.?));
    const params = glass.surface.style.ext.?.glass.?;
    try std.testing.expectEqual(@as(f32, 1), params.blur_level);
    try std.testing.expectEqual(@as(f32, 1), restLocalBlur(params, 0.5));
}

test "ScrollArea: scroll_edge mount OOM sweep (every allocation failure path frees exactly once)" {
    try @import("../oom_sweep.zig").sweepMount("scroll_area_edge", struct {
        fn mount(scope: *Scope, cx: *Cx) anyerror!?*Node {
            return (try ScrollArea(.{ .width = 300, .height = 200, .scroll_edge = .{} }).mount(scope, cx)).container;
        }
    }.mount);
}

test "ScrollArea: no scroll_edge, no band (tree unchanged)" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const result = try ScrollArea(.{ .width = 300, .height = 200 }).mount(scope, ctx);
    defer ctx.freeNode(result.container);
    try std.testing.expect(result.scroll_edge == null);
    try std.testing.expectEqual(@as(usize, 5), result.container.children.items.len);
}

test "ScrollArea: scroll state" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);

    defer scope.dispose();

    const result = try ScrollArea(.{
        .width = 300,
        .height = 200,
        .content_height = 600,
    }).mount(scope, ctx);

    try root.appendChild(std.testing.allocator, result.container);
    ctx.layout();

    try std.testing.expectEqual(@as(f32, 0), result.content.style.translate_y);

    const event = core.Event{ .scroll = .{ .x = 150, .y = 100, .dx = 0, .dy = -1 } };
    const handler_result = scrollEventHandler(event, result.container.behavior.events.event_context);
    try std.testing.expectEqual(core.EventResult.stop, handler_result);
    try std.testing.expect(result.content.style.translate_y < 0);
}

/// Single 300x200 vertical ScrollArea (content 600), return mounted result.
fn mountTestScrollArea(ctx: *Cx, scope: *Scope) !ScrollAreaResult {
    const root = try box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    ctx.root = root;
    const result = try ScrollArea(.{
        .width = 300,
        .height = 200,
        .content_height = 600,
    }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, result.container);
    ctx.layout();
    return result;
}

fn testState(result: ScrollAreaResult) *ScrollState {
    const event_ctx: *ScrollEventCtx = @ptrCast(@alignCast(result.container.behavior.events.event_context.?));
    return event_ctx.state;
}

fn sendScroll(result: ScrollAreaResult, ev: @import("../../events.zig").ScrollEvent) core.EventResult {
    return scrollEventHandler(.{ .scroll = ev }, result.container.behavior.events.event_context);
}

fn settleSpring(state: *ScrollState) void {
    var ms: f64 = 1000.0;
    state.tickBonus(ms);
    while ((state.bounce_active_y or state.bounce_active_x) and ms < 4000.0) {
        ms += 16.667;
        state.tickBonus(ms);
        state.tickBonusX(ms);
    }
}

test "ScrollArea: lifting while overscrolled hands outward momentum to the spring" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const result = try mountTestScrollArea(ctx, scope);
    const state = testState(result);

    // Finger drags content past bottom
    state.scroll_y = state.maxScrollY();
    _ = sendScroll(result, .{ .x = 150, .y = 100, .dx = 0, .dy = 0, .phase = .began });
    _ = sendScroll(result, .{ .x = 150, .y = 100, .dx = 0, .dy = -30, .phase = .changed });
    try std.testing.expect(state.touching);
    try std.testing.expect(state.bonus_y > 0);
    _ = sendScroll(result, .{ .x = 150, .y = 100, .dx = 0, .dy = 0, .phase = .ended });
    try std.testing.expect(!state.touching);

    // After release, outward inertia no longer pushes; overscroll goes to spring
    const bonus_at_lift = state.bonus_y;
    try std.testing.expectEqual(core.EventResult.stop, sendScroll(result, .{ .x = 150, .y = 100, .dx = 0, .dy = -80, .momentum = .began }));
    try std.testing.expectEqual(bonus_at_lift, state.bonus_y);
    try std.testing.expectEqual(state.maxScrollY(), state.scroll_y);

    // After rebound completes, outward inertia tail won't overscroll again
    settleSpring(state);
    try std.testing.expectEqual(@as(f32, 0), state.bonus_y);
    _ = sendScroll(result, .{ .x = 150, .y = 100, .dx = 0, .dy = -80, .momentum = .changed });
    try std.testing.expectEqual(@as(f32, 0), state.bonus_y);

    // Inward inertia scrolls normally
    _ = sendScroll(result, .{ .x = 150, .y = 100, .dx = 0, .dy = 20, .momentum = .changed });
    try std.testing.expect(state.scroll_y < state.maxScrollY());
}

test "ScrollArea: momentum that reaches the edge bounces once per stream" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const result = try mountTestScrollArea(ctx, scope);
    const state = testState(result);

    state.scroll_y = 5;
    _ = sendScroll(result, .{ .x = 150, .y = 100, .dx = 0, .dy = 40, .momentum = .began });
    try std.testing.expectEqual(@as(f32, 0), state.scroll_y);
    try std.testing.expect(state.bonus_y < 0);
    try std.testing.expect(state.momentum_spent_y);

    settleSpring(state);
    for (0..5) |_| {
        _ = sendScroll(result, .{ .x = 150, .y = 100, .dx = 0, .dy = 30, .momentum = .changed });
        try std.testing.expectEqual(@as(f32, 0), state.bonus_y);
    }

    // Next gesture can pull overscroll again
    _ = sendScroll(result, .{ .x = 150, .y = 100, .dx = 0, .dy = 0, .phase = .began });
    try std.testing.expect(!state.momentum_spent_y);
    _ = sendScroll(result, .{ .x = 150, .y = 100, .dx = 0, .dy = 20, .phase = .changed });
    try std.testing.expect(state.bonus_y < 0);
}

test "ScrollArea: momentum means the finger is up, so the spring can run" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const result = try mountTestScrollArea(ctx, scope);
    const state = testState(result);

    _ = sendScroll(result, .{ .x = 150, .y = 100, .dx = 0, .dy = 20, .phase = .changed });
    try std.testing.expect(state.touching);
    // ended event lost, momentum arrives directly
    _ = sendScroll(result, .{ .x = 150, .y = 100, .dx = 0, .dy = 5, .momentum = .began });
    try std.testing.expect(!state.touching);
    try std.testing.expect(state.momentum_active);
}

test "ScrollArea: inputActive follows begin/end signals without timers" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const result = try mountTestScrollArea(ctx, scope);
    const state = testState(result);
    state.scroll_y = 200;

    try std.testing.expect(!state.inputActive());
    _ = sendScroll(result, .{ .x = 150, .y = 100, .dx = 0, .dy = 0, .phase = .began });
    _ = sendScroll(result, .{ .x = 150, .y = 100, .dx = 0, .dy = -10, .phase = .changed });
    try std.testing.expect(state.inputActive());
    _ = sendScroll(result, .{ .x = 150, .y = 100, .dx = 0, .dy = 0, .phase = .ended });
    try std.testing.expect(!state.inputActive());
    _ = sendScroll(result, .{ .x = 150, .y = 100, .dx = 0, .dy = -10, .momentum = .began });
    try std.testing.expect(state.inputActive());
    // Won't auto-revert to idle; depends on signal only
    for (0..100) |_| scrollbarBeforeRender(result.container);
    try std.testing.expect(state.inputActive());
    _ = sendScroll(result, .{ .x = 150, .y = 100, .dx = 0, .dy = 0, .momentum = .ended });
    try std.testing.expect(!state.inputActive());

    // New gesture interrupts inertia
    _ = sendScroll(result, .{ .x = 150, .y = 100, .dx = 0, .dy = -10, .momentum = .began });
    _ = sendScroll(result, .{ .x = 150, .y = 100, .dx = 0, .dy = 0, .phase = .may_begin });
    try std.testing.expect(!state.momentum_active);
}

test "ScrollArea: input_serial counts applied input only" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const result = try mountTestScrollArea(ctx, scope);
    const state = testState(result);
    state.scroll_y = 200;

    const s0 = state.input_serial;
    _ = sendScroll(result, .{ .x = 150, .y = 100, .dx = 0, .dy = -10 });
    try std.testing.expectEqual(s0 + 1, state.input_serial);
    _ = sendScroll(result, .{ .x = 150, .y = 100, .dx = 0, .dy = -10, .phase = .changed });
    try std.testing.expectEqual(s0 + 2, state.input_serial);
    _ = sendScroll(result, .{ .x = 150, .y = 100, .dx = 0, .dy = 0, .phase = .ended });
    try std.testing.expectEqual(s0 + 2, state.input_serial);
}

test "ScrollArea: mouse wheel stops at the edge without rubber band" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const result = try mountTestScrollArea(ctx, scope);
    const state = testState(result);

    state.scroll_y = 3;
    _ = sendScroll(result, .{ .x = 150, .y = 100, .dx = 0, .dy = 40 });
    try std.testing.expectEqual(@as(f32, 0), state.scroll_y);
    try std.testing.expectEqual(@as(f32, 0), state.bonus_y);
    try std.testing.expect(!state.touching);
    try std.testing.expect(!state.inputActive());
}

test "ScrollArea: finger down catches a running bounce" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const result = try mountTestScrollArea(ctx, scope);
    const state = testState(result);

    state.bonus_y = -20;
    state.tickBonus(1000.0);
    state.tickBonus(1032.0);
    try std.testing.expect(state.bounce_active_y);
    const held = state.bonus_y;

    _ = sendScroll(result, .{ .x = 150, .y = 100, .dx = 0, .dy = 0, .phase = .may_begin });
    try std.testing.expect(state.touching);
    try std.testing.expect(!state.bounce_active_y);
    try std.testing.expectEqual(held, state.bonus_y);
    // Spring doesn't run while pressed
    state.tickBonus(1100.0);
    try std.testing.expectEqual(held, state.bonus_y);
    // Spring takes over on release
    _ = sendScroll(result, .{ .x = 150, .y = 100, .dx = 0, .dy = 0, .phase = .cancelled });
    settleSpring(state);
    try std.testing.expectEqual(@as(f32, 0), state.bonus_y);
}

test "ScrollArea: nested chain delegates outward boundary scroll to ancestor" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try box(ctx, .{ .width = .{ .px = 500 }, .height = .{ .px = 400 } }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);

    defer scope.dispose();

    const outer = try ScrollArea(.{
        .width = 320,
        .height = 220,
    }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, outer.container);

    const inner = try ScrollArea(.{
        .width = 280,
        .height = 120,
        .content_height = 420,
    }).mount(scope, ctx);
    try outer.content.appendChild(std.testing.allocator, inner.container);

    const spacer = try box(ctx, .{
        .width = .{ .grow = .{} },
        .height = .{ .px = 420 },
    }, .{});
    try outer.content.appendChild(std.testing.allocator, spacer);

    ctx.layout();

    const outer_ctx: *ScrollEventCtx = @ptrCast(@alignCast(outer.container.behavior.events.event_context.?));
    const inner_ctx: *ScrollEventCtx = @ptrCast(@alignCast(inner.container.behavior.events.event_context.?));
    outer_ctx.state.scroll_y = 0;
    outer_ctx.state.bonus_y = 0;
    inner_ctx.state.scroll_y = 0;
    inner_ctx.state.bonus_y = 0;

    const inner_global = inner.container.globalRect();
    const px = inner_global.x + 8;
    const py = inner_global.y + 8;
    ctx.handleScroll(.{ .x = px, .y = py, .dx = 0, .dy = 8, .phase = .changed });

    try std.testing.expectEqual(@as(f32, 0), inner_ctx.state.scroll_y);
    try std.testing.expectEqual(@as(f32, 0), inner_ctx.state.bonus_y);
    try std.testing.expect(outer_ctx.state.bonus_y < 0);
}

test "ScrollArea: nested chain delegates on boundary crossing frame" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try box(ctx, .{ .width = .{ .px = 500 }, .height = .{ .px = 400 } }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);

    defer scope.dispose();

    const outer = try ScrollArea(.{
        .width = 320,
        .height = 220,
    }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, outer.container);

    const inner = try ScrollArea(.{
        .width = 280,
        .height = 120,
        .content_height = 420,
    }).mount(scope, ctx);
    try outer.content.appendChild(std.testing.allocator, inner.container);

    const spacer = try box(ctx, .{
        .width = .{ .grow = .{} },
        .height = .{ .px = 420 },
    }, .{});
    try outer.content.appendChild(std.testing.allocator, spacer);

    ctx.layout();
    _ = ctx.render(); // Ensure hitTest scene updates

    const outer_ctx: *ScrollEventCtx = @ptrCast(@alignCast(outer.container.behavior.events.event_context.?));
    const inner_ctx: *ScrollEventCtx = @ptrCast(@alignCast(inner.container.behavior.events.event_context.?));
    outer_ctx.state.scroll_y = 0;
    outer_ctx.state.bonus_y = 0;
    inner_ctx.state.scroll_y = 2; // Not yet at boundary, but will overscroll this frame
    inner_ctx.state.bonus_y = 0;

    const inner_global = inner.container.globalRect();
    const px = inner_global.x + 8;
    const py = inner_global.y + 8;
    ctx.handleScroll(.{ .x = px, .y = py, .dx = 0, .dy = 8, .phase = .changed });

    try std.testing.expectEqual(@as(f32, 0), inner_ctx.state.scroll_y);
    try std.testing.expectEqual(@as(f32, 0), inner_ctx.state.bonus_y);
    try std.testing.expect(outer_ctx.state.bonus_y < 0);
}

test "ScrollArea: nested chain snaps inner to boundary before delegating" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try box(ctx, .{ .width = .{ .px = 500 }, .height = .{ .px = 400 } }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);

    defer scope.dispose();

    const outer = try ScrollArea(.{
        .width = 320,
        .height = 220,
    }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, outer.container);

    const inner = try ScrollArea(.{
        .width = 280,
        .height = 120,
        .content_height = 420,
    }).mount(scope, ctx);
    try outer.content.appendChild(std.testing.allocator, inner.container);

    const spacer = try box(ctx, .{
        .width = .{ .grow = .{} },
        .height = .{ .px = 420 },
    }, .{});
    try outer.content.appendChild(std.testing.allocator, spacer);

    ctx.layout();
    _ = ctx.render(); // Ensure hitTest scene updates

    const inner_ctx: *ScrollEventCtx = @ptrCast(@alignCast(inner.container.behavior.events.event_context.?));
    inner_ctx.state.scroll_y = inner_ctx.state.maxScrollY() - 2;
    inner_ctx.state.bonus_y = 0;

    const inner_global = inner.container.globalRect();
    const px = inner_global.x + 8;
    const py = inner_global.y + 8;
    ctx.handleScroll(.{ .x = px, .y = py, .dx = 0, .dy = -8, .phase = .changed });

    try std.testing.expectApproxEqAbs(inner_ctx.state.maxScrollY(), inner_ctx.state.scroll_y, 0.01);
    try std.testing.expectEqual(@as(f32, 0), inner_ctx.state.bonus_y);
}

test "ScrollArea: an outer layer holding the gesture keeps it over an inner one" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try box(ctx, .{ .width = .{ .px = 500 }, .height = .{ .px = 400 } }, .{});
    ctx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const outer = try ScrollArea(.{ .width = 320, .height = 220 }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, outer.container);
    const inner = try ScrollArea(.{ .width = 280, .height = 120, .content_height = 420 }).mount(scope, ctx);
    try outer.content.appendChild(std.testing.allocator, inner.container);
    const spacer = try box(ctx, .{ .width = .{ .grow = .{} }, .height = .{ .px = 420 } }, .{});
    try outer.content.appendChild(std.testing.allocator, spacer);
    ctx.layout();
    _ = ctx.render();

    const outer_state = testState(outer);
    const inner_state = testState(inner);
    inner_state.scroll_y = 60;
    const g = inner.container.globalRect();

    // outer idle: inner scrolls normally under pointer
    ctx.handleScroll(.{ .x = g.x + 8, .y = g.y + 8, .dx = 0, .dy = -6, .phase = .changed });
    try std.testing.expectEqual(@as(f32, 66), inner_state.scroll_y);
    ctx.handleScroll(.{ .x = g.x + 8, .y = g.y + 8, .dx = 0, .dy = 0, .phase = .ended });

    // outer holds gesture (finger on pad, content moves under pointer): no handoff to inner
    // mid-gesture
    outer_state.touching = true;
    const outer_before = outer_state.scroll_y;
    ctx.handleScroll(.{ .x = g.x + 8, .y = g.y + 8, .dx = 0, .dy = -6, .phase = .changed });
    try std.testing.expectEqual(@as(f32, 66), inner_state.scroll_y);
    try std.testing.expect(outer_state.scroll_y > outer_before);
}

test "ScrollArea: an outer bounce does not steal a gesture that starts on the inner layer" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try box(ctx, .{ .width = .{ .px = 500 }, .height = .{ .px = 400 } }, .{});
    ctx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const outer = try ScrollArea(.{ .width = 320, .height = 220 }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, outer.container);
    const inner = try ScrollArea(.{ .width = 280, .height = 120, .content_height = 420 }).mount(scope, ctx);
    try outer.content.appendChild(std.testing.allocator, inner.container);
    const spacer = try box(ctx, .{ .width = .{ .grow = .{} }, .height = .{ .px = 420 } }, .{});
    try outer.content.appendChild(std.testing.allocator, spacer);
    ctx.layout();
    _ = ctx.render();

    const outer_state = testState(outer);
    const inner_state = testState(inner);
    // outer is rebounding
    outer_state.bonus_y = -12;
    outer_state.tickBonus(1000.0);
    try std.testing.expect(outer_state.bounce_active_y);
    inner_state.scroll_y = 60;

    const g = inner.container.globalRect();
    ctx.handleScroll(.{ .x = g.x + 8, .y = g.y + 8, .dx = 0, .dy = 0, .phase = .began });
    try std.testing.expect(!outer_state.touching);
    ctx.handleScroll(.{ .x = g.x + 8, .y = g.y + 8, .dx = 0, .dy = -6, .phase = .changed });
    try std.testing.expectEqual(@as(f32, 66), inner_state.scroll_y);
}

test "ScrollArea: ended reaches every layer of a delegated nested gesture" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try box(ctx, .{ .width = .{ .px = 500 }, .height = .{ .px = 400 } }, .{});
    ctx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const outer = try ScrollArea(.{ .width = 320, .height = 220 }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, outer.container);
    const inner = try ScrollArea(.{ .width = 280, .height = 120, .content_height = 420 }).mount(scope, ctx);
    try outer.content.appendChild(std.testing.allocator, inner.container);
    const spacer = try box(ctx, .{ .width = .{ .grow = .{} }, .height = .{ .px = 420 } }, .{});
    try outer.content.appendChild(std.testing.allocator, spacer);
    ctx.layout();
    _ = ctx.render();

    const outer_state = testState(outer);
    const inner_state = testState(inner);
    // Gesture delegated to outer; inner retains prior overscroll amount
    outer_state.touching = true;
    inner_state.bonus_y = 5;

    const g = inner.container.globalRect();
    ctx.handleScroll(.{ .x = g.x + 8, .y = g.y + 8, .dx = 0, .dy = 0, .phase = .began });
    ctx.handleScroll(.{ .x = g.x + 8, .y = g.y + 8, .dx = 0, .dy = 0, .phase = .ended });
    try std.testing.expect(!outer_state.touching);
    try std.testing.expect(!inner_state.touching);
}

test "ScrollArea: a gesture whose ended was lost is cancelled when the next one begins" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try box(ctx, .{ .width = .{ .px = 700 }, .height = .{ .px = 300 }, .direction = .row }, .{});
    ctx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const a = try ScrollArea(.{ .width = 300, .height = 200, .content_height = 600 }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, a.container);
    const b = try ScrollArea(.{ .width = 300, .height = 200, .content_height = 600 }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, b.container);
    ctx.layout();
    _ = ctx.render();

    const a_state = testState(a);
    const b_state = testState(b);
    a_state.scroll_y = 100;
    b_state.scroll_y = 100;
    const ga = a.container.globalRect();
    const gb = b.container.globalRect();

    ctx.handleScroll(.{ .x = ga.x + 20, .y = ga.y + 20, .dx = 0, .dy = 0, .phase = .began });
    ctx.handleScroll(.{ .x = ga.x + 20, .y = ga.y + 20, .dx = 0, .dy = -10, .phase = .changed });
    try std.testing.expect(a_state.touching);

    ctx.handleScroll(.{ .x = gb.x + 20, .y = gb.y + 20, .dx = 0, .dy = 0, .phase = .began });
    ctx.handleScroll(.{ .x = gb.x + 20, .y = gb.y + 20, .dx = 0, .dy = -10, .phase = .changed });
    try std.testing.expect(!a_state.touching);
    try std.testing.expect(b_state.touching);
}

test "ScrollArea: window blur cancels an in-progress gesture" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const result = try mountTestScrollArea(ctx, scope);
    _ = ctx.render();
    const state = testState(result);
    state.scroll_y = 200;

    const g = result.container.globalRect();
    ctx.handleScroll(.{ .x = g.x + 20, .y = g.y + 20, .dx = 0, .dy = 0, .phase = .began });
    ctx.handleScroll(.{ .x = g.x + 20, .y = g.y + 20, .dx = 0, .dy = -10, .phase = .changed });
    try std.testing.expect(state.touching);

    ctx.cancelPointerInteractions(.window_blur);
    try std.testing.expect(!state.touching);
    try std.testing.expect(!state.inputActive());
}

test "ScrollArea: window blur ends in-progress momentum" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const result = try mountTestScrollArea(ctx, scope);
    _ = ctx.render();
    const state = testState(result);
    state.scroll_y = 200;

    const g = result.container.globalRect();
    ctx.handleScroll(.{ .x = g.x + 20, .y = g.y + 20, .dx = 0, .dy = 0, .phase = .began });
    ctx.handleScroll(.{ .x = g.x + 20, .y = g.y + 20, .dx = 0, .dy = -10, .phase = .changed });
    ctx.handleScroll(.{ .x = g.x + 20, .y = g.y + 20, .dx = 0, .dy = 0, .phase = .ended });
    ctx.handleScroll(.{ .x = g.x + 20, .y = g.y + 20, .dx = 0, .dy = -10, .momentum = .began });
    try std.testing.expect(state.momentum_active);

    ctx.cancelPointerInteractions(.window_blur);
    try std.testing.expect(!state.momentum_active);
}

test "ScrollArea: bounce animation blocks outward momentum" {
    const render_engine = @import("../../core/render_engine/mod.zig");
    render_engine.current_frame_time_ms = 1000.0;
    var state = ScrollState{
        .content_height = 500,
        .viewport_height = 200,
        .scroll_y = 0,
        .bonus_y = -20,
    };

    // Start rebound
    state.tickBonus(1016.0);
    state.tickBonus(1032.0);
    try std.testing.expect(state.bounce_active_y);

    // During animation, outward momentum should be rejected
    const scroll_event_mod = @import("event.zig");
    const bounce_active = scroll_event_mod.hasBounceActive(&state, .vertical);
    try std.testing.expect(bounce_active);

    // Run to completion
    var ms: f64 = 1000.0;
    while (state.bounce_active_y and ms < 3000.0) {
        ms += 16.667;
        state.tickBonus(ms);
    }
    try std.testing.expectEqual(@as(f32, 0), state.bonus_y);
    try std.testing.expect(!state.bounce_active_y);
}

fn mountBothInsideVertical(ctx: *Cx, scope: *Scope) !struct { outer: ScrollAreaResult, inner: ScrollAreaResult } {
    const root = try box(ctx, .{ .width = .{ .px = 500 }, .height = .{ .px = 400 } }, .{});
    ctx.root = root;
    const outer = try ScrollArea(.{ .width = 320, .height = 220 }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, outer.container);
    // Horizontal-only both area: content wider than viewport, same height
    const inner = try ScrollArea(.{ .width = 280, .height = 120, .direction = .both }).mount(scope, ctx);
    try outer.content.appendChild(std.testing.allocator, inner.container);
    const strip = try box(ctx, .{ .width = .{ .px = 900 }, .height = .{ .px = 120 } }, .{});
    try inner.content.appendChild(std.testing.allocator, strip);
    const spacer = try box(ctx, .{ .width = .{ .grow = .{} }, .height = .{ .px = 420 } }, .{});
    try outer.content.appendChild(std.testing.allocator, spacer);
    ctx.layout();
    _ = ctx.render();
    // Horizontal content width managed by host (Grid / VirtualList usage)
    const inner_state = testState(inner);
    inner_state.external_content_width = true;
    inner_state.content_width = 900;
    return .{ .outer = outer, .inner = inner };
}

test "ScrollArea: a both-direction area scrolls sideways over a child wider than the viewport" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const root = try box(ctx, .{ .width = .{ .px = 500 }, .height = .{ .px = 400 } }, .{});
    ctx.root = root;
    const area = try ScrollArea(.{ .width = 280, .height = 120, .direction = .both, .rubber_band_x = false, .rubber_band_y = false }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, area.container);
    // The caller's own box decides the scrolled extent; nobody writes the area's state.
    const canvas = try box(ctx, .{ .width = .{ .px = 900 }, .height = .{ .px = 300 }, .flex_shrink = 0 }, .{});
    try area.content.appendChild(std.testing.allocator, canvas);
    ctx.layout();
    _ = ctx.render();
    const r = area.container.globalRect();
    _ = ctx.handleScroll(.{ .x = r.x + 20, .y = r.y + 20, .dx = -50, .dy = 0 });
    ctx.layout();
    _ = ctx.render();
    try std.testing.expectApproxEqAbs(@as(f32, 900), area.state.content_width, 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 620), area.state.maxScrollX(), 0.5);
    try std.testing.expect(area.state.scroll_x > 0);
    // The child shrinks back inside the viewport: nothing left to scroll sideways.
    canvas.setStyleInline(std.testing.allocator, .{ .width = .{ .px = 200 } });
    ctx.layout();
    _ = ctx.render();
    _ = ctx.render();
    try std.testing.expectApproxEqAbs(@as(f32, 0), area.state.maxScrollX(), 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 0), area.state.scroll_x, 0.5);
}

test "ScrollArea: both mode hands a diagonal event to the layer of its dominant axis" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const areas = try mountBothInsideVertical(ctx, scope);
    const outer_state = testState(areas.outer);
    const inner_state = testState(areas.inner);
    try std.testing.expectEqual(@as(f32, 0), inner_state.maxScrollY());
    const g = areas.inner.container.globalRect();

    // Vertical dominant: hand entire event to outer, preserve y component
    ctx.handleScroll(.{ .x = g.x + 8, .y = g.y + 8, .dx = -2, .dy = -8 });
    try std.testing.expectEqual(@as(f32, 8), outer_state.scroll_y);
    try std.testing.expectEqual(@as(f32, 0), inner_state.scroll_x);

    // Horizontal dominant: handle x here, discard small y per axis lock
    ctx.handleScroll(.{ .x = g.x + 8, .y = g.y + 8, .dx = -8, .dy = -2 });
    try std.testing.expectEqual(@as(f32, 8), inner_state.scroll_x);
    try std.testing.expectEqual(@as(f32, 8), outer_state.scroll_y);
}

test "ScrollArea: both mode keeps a held gesture when the dominant axis changes" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const areas = try mountBothInsideVertical(ctx, scope);
    const outer_state = testState(areas.outer);
    const inner_state = testState(areas.inner);
    const g = areas.inner.container.globalRect();

    ctx.handleScroll(.{ .x = g.x + 8, .y = g.y + 8, .dx = 0, .dy = 0, .phase = .began });
    ctx.handleScroll(.{ .x = g.x + 8, .y = g.y + 8, .dx = -8, .dy = -1, .phase = .changed });
    try std.testing.expect(inner_state.touching);
    // Mid-gesture switch to vertical dominant: no handoff to outer
    ctx.handleScroll(.{ .x = g.x + 8, .y = g.y + 8, .dx = -1, .dy = -8, .phase = .changed });
    try std.testing.expectEqual(@as(f32, 0), outer_state.scroll_y);
    try std.testing.expectEqual(@as(f32, 9), inner_state.scroll_x);
}

test "ScrollArea: both mode keeps the momentum of a gesture it held" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const areas = try mountBothInsideVertical(ctx, scope);
    const outer_state = testState(areas.outer);
    const inner_state = testState(areas.inner);
    const g = areas.inner.container.globalRect();

    ctx.handleScroll(.{ .x = g.x + 8, .y = g.y + 8, .dx = 0, .dy = 0, .phase = .began });
    ctx.handleScroll(.{ .x = g.x + 8, .y = g.y + 8, .dx = -8, .dy = -1, .phase = .changed });
    ctx.handleScroll(.{ .x = g.x + 8, .y = g.y + 8, .dx = 0, .dy = 0, .phase = .ended });
    // Inertia tail becomes vertical dominant: still inner's inertia, no leak to outer
    ctx.handleScroll(.{ .x = g.x + 8, .y = g.y + 8, .dx = -1, .dy = -6, .momentum = .changed });
    try std.testing.expectEqual(@as(f32, 0), outer_state.scroll_y);
    try std.testing.expectEqual(@as(f32, 9), inner_state.scroll_x);
}

test "ScrollArea: both mode does not inject bonus on non-scrollable axis" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try box(ctx, .{ .width = .{ .px = 600 }, .height = .{ .px = 400 } }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const result = try ScrollArea(.{
        .width = 300,
        .height = 200,
        .direction = .both,
    }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, result.container);
    // Content as tall as the viewport and wider than it: only x scrolls. (The extents follow the
    // laid-out content; initial `content_*` props are replaced by the first layout.)
    try result.content.appendChild(std.testing.allocator, try box(ctx, .{ .width = .{ .px = 500 }, .height = .{ .px = 200 }, .flex_shrink = 0 }, .{}));
    ctx.layout();

    const event_ctx: *ScrollEventCtx = @ptrCast(@alignCast(result.container.behavior.events.event_context.?));
    const state = event_ctx.state;
    try std.testing.expectEqual(@as(f32, 0), state.maxScrollY());
    try std.testing.expect(state.maxScrollX() > 0);

    const y_only = core.Event{
        .scroll = .{
            .x = 150,
            .y = 100,
            .dx = 0,
            .dy = 24,
            .phase = .changed,
        },
    };
    const routed = scrollEventHandler(y_only, result.container.behavior.events.event_context);
    try std.testing.expectEqual(core.EventResult.ignored, routed);
    try std.testing.expectEqual(@as(f32, 0), state.bonus_y);
}

test "ScrollArea: both-mode momentum x bounce does not block vertical scrolling" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try box(ctx, .{ .width = .{ .px = 600 }, .height = .{ .px = 400 } }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const result = try ScrollArea(.{
        .width = 300,
        .height = 200,
        .direction = .both,
        .content_height = 1200,
        .content_width = 1200,
    }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, result.container);
    ctx.layout();

    const event_ctx: *ScrollEventCtx = @ptrCast(@alignCast(result.container.behavior.events.event_context.?));
    const state = event_ctx.state;
    state.scroll_x = 0;
    state.scroll_y = 329;
    state.bonus_x = -0.04;
    state.bonus_y = 0;

    const momentum_vertical = core.Event{
        .scroll = .{
            .x = 150,
            .y = 100,
            .dx = 0,
            .dy = -38,
            .momentum = .changed,
        },
    };

    const handled = scrollEventHandler(momentum_vertical, result.container.behavior.events.event_context);
    try std.testing.expectEqual(core.EventResult.stop, handled);
    try std.testing.expectEqual(@as(f32, 367), state.scroll_y);
    try std.testing.expectApproxEqAbs(@as(f32, -0.04), state.bonus_x, 0.001);
}

test "ScrollArea: isOutwardAtBoundary both returns false when no active delta" {
    const state = ScrollState{
        .content_height = 600,
        .viewport_height = 200,
        .content_width = 800,
        .viewport_width = 300,
        .scroll_y = 20,
        .scroll_x = 40,
    };
    try std.testing.expect(!isOutwardAtBoundary(&state, .both, 0, 0, 1.0));
}

test "ScrollState: effectiveScrollY with bonus" {
    var state = ScrollState{
        .content_height = 500,
        .viewport_height = 200,
    };

    // Normal range: effective = scroll_y (bonus=0)
    state.scroll_y = 100;
    try std.testing.expectEqual(@as(f32, 100), state.effectiveScrollY());

    // With bonus: effective = scroll_y + bonus
    state.scroll_y = 0;
    state.bonus_y = -90;
    try std.testing.expectEqual(@as(f32, -90), state.effectiveScrollY());

    state.scroll_y = 300;
    state.bonus_y = 60;
    try std.testing.expectEqual(@as(f32, 360), state.effectiveScrollY());
}

test "ScrollState: duration-based bounce decay" {
    const render_engine = @import("../../core/render_engine/mod.zig");
    render_engine.current_frame_time_ms = 1000.0;
    var state = ScrollState{
        .content_height = 500,
        .viewport_height = 200,
    };

    state.bonus_y = 100;
    state.tickBonus(1000.0);
    // First frame: bonus should start decreasing
    try std.testing.expect(state.bonus_y <= 100);
    try std.testing.expect(state.bonus_y > 0);
    try std.testing.expect(state.bounce_active_y);

    // Run to completion
    var ms: f64 = 1000.0;
    while (state.bounce_active_y and ms < 3000.0) {
        ms += 16.667;
        state.tickBonus(ms);
    }
    try std.testing.expectEqual(@as(f32, 0), state.bonus_y);
    try std.testing.expect(!state.bounce_active_y);
}

test "ScrollState: bonus bounce blocked while touching" {
    const render_engine = @import("../../core/render_engine/mod.zig");
    render_engine.current_frame_time_ms = 1000.0;
    var state = ScrollState{
        .content_height = 500,
        .viewport_height = 200,
    };

    state.bonus_y = 100;
    state.touching = true;
    state.tickBonus(1000.0);
    // Spring doesn't start
    try std.testing.expect(!state.bounce_active_y);
    try std.testing.expectEqual(@as(f32, 100), state.bonus_y);
}

test "ScrollState: larger displacement settles later (critically damped spring)" {
    const render_engine = @import("../../core/render_engine/mod.zig");
    render_engine.current_frame_time_ms = 1000.0;
    var small = ScrollState{
        .content_height = 500,
        .viewport_height = 200,
        .bonus_y = 20,
    };
    var large = ScrollState{
        .content_height = 500,
        .viewport_height = 200,
        .bonus_y = 120,
    };

    small.tickBonus(1000.0);
    large.tickBonus(1000.0);

    var small_done_ms: f64 = 0;
    var large_done_ms: f64 = 0;
    var ms: f64 = 1000.0;
    while ((small.bounce_active_y or large.bounce_active_y) and ms < 3000.0) {
        ms += 16.667;
        small.tickBonus(ms);
        large.tickBonus(ms);
        if (!small.bounce_active_y and small_done_ms == 0) small_done_ms = ms;
        if (!large.bounce_active_y and large_done_ms == 0) large_done_ms = ms;
    }
    // Both converge to zero; larger displacement converges later
    try std.testing.expectEqual(@as(f32, 0), small.bonus_y);
    try std.testing.expectEqual(@as(f32, 0), large.bonus_y);
    try std.testing.expect(large_done_ms >= small_done_ms);
}

test "ScrollState: spring bounce carries inbound velocity (overshoot then return)" {
    var state = ScrollState{
        .content_height = 500,
        .viewport_height = 200,
        .bonus_y = 30,
        .bonus_velocity = 800, // Incoming inertia still pushes outward
    };
    state.tickBonus(1000.0);
    try std.testing.expect(state.bounce_active_y);

    // Should deepen briefly (velocity continuous -> smooth)
    state.tickBonus(1030.0);
    try std.testing.expect(state.bonus_y > 30);

    var ms: f64 = 1030.0;
    while (state.bounce_active_y and ms < 4000.0) {
        ms += 16.667;
        state.tickBonus(ms);
    }
    try std.testing.expectEqual(@as(f32, 0), state.bonus_y);
}

test "ScrollState: rubberBand round-trip (via physics.RubberBand)" {
    // clamp -> unclamp should restore original value (test via ScrollState.rubber_band)
    const rb = physics.RubberBand{};
    const dim: f32 = 200;
    const inputs = [_]f32{ 5, 20, 50, 100, -10, -80 };
    for (inputs) |input| {
        const clamped = rb.clamp(input, dim);
        const recovered = rb.unclamp(clamped, dim);
        try std.testing.expectApproxEqAbs(input, recovered, 0.1);
    }
}

test "ScrollState: rubberBand asymptotic (via physics.RubberBand)" {
    const rb = physics.RubberBand{};
    const dim: f32 = 200;
    // Small input: output < input (with damping) and close to input
    const small = rb.clamp(10, dim);
    try std.testing.expect(small > 0);
    try std.testing.expect(small <= 10.0);
    // Large input approaches dim asymptotically
    const large = rb.clamp(10000, dim);
    try std.testing.expect(large > 0);
    try std.testing.expect(large <= dim);
    // Monotonically increasing
    try std.testing.expect(large > small);
    // Symmetric for negative input
    const neg = rb.clamp(-50, dim);
    try std.testing.expect(neg < 0);
}

test "applyVerticalScroll: boundary bonus with damping" {
    var state = ScrollState{
        .content_height = 500,
        .viewport_height = 200,
    };

    // Normal scroll
    applyVerticalScroll(&state, -5, 1, .gesture);
    try std.testing.expectEqual(@as(f32, 0), state.bonus_y);
    try std.testing.expect(state.scroll_y > 0);

    // Overshoot top -> bonus becomes negative (with damping decay)
    state.scroll_y = 0;
    state.bonus_y = 0;
    applyVerticalScroll(&state, 10, 1, .gesture); // delta = -10
    try std.testing.expectEqual(@as(f32, 0), state.scroll_y);
    try std.testing.expect(state.bonus_y < 0);
    // Damping: |bonus| should be < 10 (after decay)
    try std.testing.expect(@abs(state.bonus_y) <= 10);

    // Overshoot bottom -> bonus becomes positive (with damping decay)
    state.scroll_y = 300;
    state.bonus_y = 0;
    applyVerticalScroll(&state, -10, 1, .gesture); // delta = +10
    try std.testing.expectEqual(@as(f32, 300), state.scroll_y);
    try std.testing.expect(state.bonus_y > 0);
    try std.testing.expect(state.bonus_y <= 10);

    // Repeated overshoot: damping accumulates, each increment smaller
    state.scroll_y = 0;
    state.bonus_y = 0;
    applyVerticalScroll(&state, 5, 1, .gesture);
    const first_bonus = @abs(state.bonus_y);
    const prev_bonus = state.bonus_y;
    applyVerticalScroll(&state, 5, 1, .gesture);
    const second_increment = @abs(state.bonus_y - prev_bonus);
    try std.testing.expect(second_increment < first_bonus);
}

test "ScrollState: scrollbar metrics" {
    var state = ScrollState{
        .content_height = 1000,
        .viewport_height = 200,
    };

    try std.testing.expect(state.needsScrollbar());
    try std.testing.expectEqual(@as(f32, 40), state.scrollbarHeight());

    state.scroll_y = 0;
    try std.testing.expectEqual(@as(f32, 2), state.scrollbarY());

    state.scroll_y = 800;
    try std.testing.expectEqual(@as(f32, 158), state.scrollbarY());

    state.content_height = 100;
    try std.testing.expect(!state.needsScrollbar());
}

test "ScrollState: overscroll shrinks vertical thumb and pins to edge" {
    var state = ScrollState{
        .content_height = 1000,
        .viewport_height = 200,
        .scroll_y = 400,
    };

    const base = computeVerticalScrollbarMetrics(&state);
    try std.testing.expectApproxEqAbs(@as(f32, 40), base.length, 0.01);

    state.scroll_y = 0;
    state.bonus_y = -28;
    const top = computeVerticalScrollbarMetrics(&state);
    try std.testing.expect(top.length < base.length);
    try std.testing.expectApproxEqAbs(@as(f32, 2), top.pos, 0.01);

    state.scroll_y = state.maxScrollY();
    state.bonus_y = 28;
    const bottom = computeVerticalScrollbarMetrics(&state);
    try std.testing.expect(bottom.length < base.length);
    try std.testing.expectApproxEqAbs(@as(f32, 198), bottom.pos + bottom.length, 0.05);
}

test "ScrollArea: scrollbar thumb rect updates in before-render hook" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);

    defer scope.dispose();

    const result = try ScrollArea(.{
        .width = 300,
        .height = 200,
        .content_height = 1000,
        .padding = Padding.all(10),
    }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, result.container);
    ctx.layout();

    const event_ctx: *ScrollEventCtx = @ptrCast(@alignCast(result.container.behavior.events.event_context.?));
    const state = event_ctx.state;
    state.scrollbar_fade.opacity = 1.0;

    state.scroll_y = state.maxScrollY() / 2;
    scrollbarBeforeRender(result.container);

    const thumb_node = event_ctx.scrollbar.?;
    try std.testing.expectApproxEqAbs(@as(f32, ScrollbarVisual.idle_thickness), thumb_node.rectFromWorldOrFallback().w, 0.01);
    const expected_x = result.container.rectFromWorldOrFallback().x + result.container.rectFromWorldOrFallback().w - thumb_node.rectFromWorldOrFallback().w - ScrollbarVisual.edge_inset;
    try std.testing.expectApproxEqAbs(expected_x, thumb_node.rectFromWorldOrFallback().x, 0.01);
    const first_y = thumb_node.rectFromWorldOrFallback().y;
    try std.testing.expect(first_y > result.container.rectFromWorldOrFallback().y + result.container.style.contentInsets().top);

    state.scroll_y = state.maxScrollY();
    scrollbarBeforeRender(result.container);
    try std.testing.expect(thumb_node.rectFromWorldOrFallback().y > first_y);

    // COMPONENTS.json Scrollbar variants and zenit.scrollbar.*: 4 -> 6, track 10, inset 2.
    try std.testing.expectEqual(ctx.tokens.tokens.color.scrollbar_thumb, thumb_node.getBackground());
    // An idle track is hidden and keeps its transparent mount paint, so running
    // this hook again (e.g. from a theme replay) matches a fresh mount.
    try std.testing.expectEqual(Color.TRANSPARENT, event_ctx.track_v.?.getBackground());
    state.scrollbar_hovered = true;
    scrollbarBeforeRender(result.container);
    try std.testing.expectEqual(@as(f32, 6), thumb_node.rectFromWorldOrFallback().w);
    try std.testing.expectEqual(@as(f32, 10), event_ctx.track_v.?.rectFromWorldOrFallback().w);
    try std.testing.expectEqual(ctx.tokens.tokens.color.scrollbar_thumb_hover, thumb_node.getBackground());
    try std.testing.expectEqual(ctx.tokens.tokens.color.scrollbar_track, event_ctx.track_v.?.getBackground());
    ctx.setTheme(&core.theme.dark);
    scrollbarBeforeRender(result.container);
    try std.testing.expectEqual(core.theme.dark.tokens.color.scrollbar_thumb_hover, thumb_node.getBackground());
    try std.testing.expectEqual(core.theme.dark.tokens.color.scrollbar_track, event_ctx.track_v.?.getBackground());
    state.scrollbar_hovered = false;
    scrollbarBeforeRender(result.container);
    try std.testing.expectEqual(Color.TRANSPARENT, event_ctx.track_v.?.getBackground());
}

test "ScrollArea: scope dispose detaches before-render hook and event handlers" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    var scope_disposed = false;
    defer if (!scope_disposed) scope.dispose();

    const result = try ScrollArea(.{
        .width = 300,
        .height = 200,
        .content_height = 600,
    }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, result.container);

    const event_ctx: *ScrollEventCtx = @ptrCast(@alignCast(result.container.behavior.events.event_context.?));
    const scrollbar_v = event_ctx.scrollbar.?;
    const scrollbar_h = event_ctx.scrollbar_h.?;

    scope.dispose();
    scope_disposed = true;

    try std.testing.expect(result.container.behavior.events.on_event == null);
    try std.testing.expect(result.container.behavior.events.event_context == null);
    try std.testing.expect(result.container.meta.per_frame.hooks.before_render.main == null);
    try std.testing.expect(scrollbar_v.behavior.events.on_event == null);
    try std.testing.expect(scrollbar_v.behavior.events.event_context == null);
    try std.testing.expect(scrollbar_h.behavior.events.on_event == null);
    try std.testing.expect(scrollbar_h.behavior.events.event_context == null);

    scrollbarBeforeRender(result.container);
}

test "ScrollState: scrollbar fade" {
    var state = ScrollState{
        .content_height = 500,
        .viewport_height = 200,
    };

    state.onScrollActivity();
    try std.testing.expectEqual(@as(f32, 0.7), state.scrollbar_fade.opacity);

    for (0..90) |_| _ = state.tickScrollbar();
    try std.testing.expectEqual(@as(f32, 0.7), state.scrollbar_fade.opacity);

    _ = state.tickScrollbar();
    try std.testing.expect(state.scrollbar_fade.opacity < 0.7);

    for (0..40) |_| _ = state.tickScrollbar();
    try std.testing.expectEqual(@as(f32, 0), state.scrollbar_fade.opacity);

    state.onScrollActivity();
    state.scrollbar_hovered = true;
    _ = state.tickScrollbar();
    try std.testing.expectEqual(@as(f32, 1.0), state.scrollbar_fade.opacity);
}

test "ScrollState: scrollbar fade tick stays idle while opacity is unchanged" {
    var state = ScrollState{
        .content_height = 500,
        .viewport_height = 200,
    };

    state.onScrollActivity();
    try std.testing.expectEqual(@as(f32, 0.7), state.scrollbar_fade.opacity);

    var i: usize = 0;
    while (i < state.scrollbar_fade.fade_delay) : (i += 1) {
        const changed = state.tickScrollbar();
        try std.testing.expect(!changed);
        try std.testing.expectEqual(@as(f32, 0.7), state.scrollbar_fade.opacity);
    }

    const changed = state.tickScrollbar();
    try std.testing.expect(changed);
    try std.testing.expect(state.scrollbar_fade.opacity < 0.7);
}

// -- Programmatic scroll API ----------------

test "setScrollY: clamp + 动量复位 + 像素对齐（裸写 scroll_y 三样全没有）" {
    const testing = std.testing;
    var cx = try Cx.init(testing.allocator, std.testing.io);
    defer cx.deinit();
    const content = try box(cx, .{ .width = .{ .px = 200 }, .height = .{ .px = 1000 } }, .{});
    cx.root = content;

    var state = ScrollState{
        .content_height = 1000,
        .viewport_height = 200,
        .pixel_scale = 2.0,
    };
    // Fabricate 'residual inertia + in-flight rebound' scenario
    state.bonus_y = 37;
    state.bonus_velocity = 900;
    state.bounce_active_y = true;
    state.momentum_spent_y = true;

    setScrollY(&state, content, 300.4);

    try testing.expectEqual(@as(f32, 300.4), state.scroll_y);
    // Reset momentum/rebound; else next frames' inertia pushes content away
    try testing.expectEqual(@as(f32, 0), state.bonus_y);
    try testing.expectEqual(@as(f32, 0), state.bonus_velocity);
    try testing.expect(!state.bounce_active_y);
    try testing.expect(!state.momentum_spent_y);
    // Snap translate to physical pixel grid (pixel_scale=2 -> 0.5px grid)
    const ty = content.style.translate_y;
    try testing.expectEqual(@as(f32, -300.5), ty);

    // Clamp both top and bottom
    setScrollY(&state, content, -100);
    try testing.expectEqual(@as(f32, 0), state.scroll_y);
    setScrollY(&state, content, 99999);
    try testing.expectEqual(@as(f32, 800), state.scroll_y); // maxScrollY = 1000-200
}

test "scrollRectIntoView: 四种对齐" {
    const testing = std.testing;
    var cx = try Cx.init(testing.allocator, std.testing.io);
    defer cx.deinit();
    const content = try box(cx, .{ .width = .{ .px = 200 }, .height = .{ .px = 1000 } }, .{});
    cx.root = content;

    var state = ScrollState{ .content_height = 1000, .viewport_height = 200 };

    // start: align top
    scrollRectIntoView(&state, content, 500, 40, .start);
    try testing.expectEqual(@as(f32, 500), state.scroll_y);
    // end: align bottom to viewport bottom
    scrollRectIntoView(&state, content, 500, 40, .end);
    try testing.expectEqual(@as(f32, 340), state.scroll_y); // 540 - 200
    // center: center in viewport
    scrollRectIntoView(&state, content, 500, 40, .center);
    try testing.expectEqual(@as(f32, 420), state.scroll_y); // 500 + (40-200)/2

    // nearest: fully visible -> no-op
    state.scroll_y = 480;
    scrollRectIntoView(&state, content, 500, 40, .nearest);
    try testing.expectEqual(@as(f32, 480), state.scroll_y);
    // nearest: below viewport -> align bottom (min motion)
    state.scroll_y = 200;
    scrollRectIntoView(&state, content, 500, 40, .nearest);
    try testing.expectEqual(@as(f32, 340), state.scroll_y);
    // nearest: above viewport -> align top
    state.scroll_y = 700;
    scrollRectIntoView(&state, content, 500, 40, .nearest);
    try testing.expectEqual(@as(f32, 500), state.scroll_y);
}

test "scrollIntoView: 按节点 rect 把子节点滚进视野" {
    const testing = std.testing;
    var cx = try Cx.init(testing.allocator, std.testing.io);
    defer cx.deinit();

    const root = try box(cx, .{ .width = .{ .px = 200 }, .height = .{ .px = 200 } }, .{});
    cx.root = root;
    const scope = try Scope.init(testing.allocator, null, cx.owner);
    defer scope.dispose();

    const sa = try ScrollArea(.{ .width = 200, .height = 200 }).mount(scope, cx);
    try root.appendChild(testing.allocator, sa.container);

    sa.state.content_height = 1000;
    sa.state.viewport_height = 200;
    sa.state.external_content_height = true;

    // Create child at content y=600, height 40 (with intermediate container, verify ancestor chain)
    const mid = try box(cx, .{ .width = .{ .px = 200 }, .height = .{ .px = 1000 } }, .{});
    const target = try box(cx, .{ .width = .{ .px = 200 }, .height = .{ .px = 40 } }, .{});
    try sa.content.appendChild(testing.allocator, mid);
    try mid.appendChild(testing.allocator, target);
    mid.setLayoutRect(.{ .x = 0, .y = 100, .w = 200, .h = 1000 });
    target.setLayoutRect(.{ .x = 0, .y = 500, .w = 200, .h = 40 });

    // Content coordinate top = 100 + 500 = 600
    scrollIntoView(sa.state, sa.content, target, .start);
    try testing.expectEqual(@as(f32, 600), sa.state.scroll_y);

    scrollIntoView(sa.state, sa.content, target, .end);
    try testing.expectEqual(@as(f32, 440), sa.state.scroll_y); // 640 - 200

    // Node outside ScrollArea -> no-op, won't scroll viewport away
    const outsider = try box(cx, .{ .width = .{ .px = 10 }, .height = .{ .px = 10 } }, .{});
    try root.appendChild(testing.allocator, outsider); // Attached outside ScrollArea
    outsider.setLayoutRect(.{ .x = 0, .y = 0, .w = 10, .h = 10 });
    const before = sa.state.scroll_y;
    scrollIntoView(sa.state, sa.content, outsider, .start);
    try testing.expectEqual(before, sa.state.scroll_y);

    // Unlaid-out (h=0) is also no-op
    const unlaid = try box(cx, .{ .width = .{ .px = 10 }, .height = .{ .px = 10 } }, .{});
    try sa.content.appendChild(testing.allocator, unlaid);
    scrollIntoView(sa.state, sa.content, unlaid, .start);
    try testing.expectEqual(before, sa.state.scroll_y);
}

test "scrollIntoViewX: brings a laid-out child into the horizontal viewport" {
    const testing = std.testing;
    var cx = try Cx.init(testing.allocator, std.testing.io);
    defer cx.deinit();

    const root = try box(cx, .{ .width = .{ .px = 200 }, .height = .{ .px = 40 } }, .{});
    cx.root = root;
    const scope = try Scope.init(testing.allocator, null, cx.owner);
    defer scope.dispose();

    const sa = try ScrollArea(.{ .width = 200, .height = 40, .direction = .horizontal }).mount(scope, cx);
    try root.appendChild(testing.allocator, sa.container);
    sa.state.content_width = 1000;
    sa.state.viewport_width = 200;
    sa.state.external_content_width = true;

    const mid = try box(cx, .{ .width = .{ .px = 1000 }, .height = .{ .px = 40 } }, .{});
    const target = try box(cx, .{ .width = .{ .px = 60 }, .height = .{ .px = 40 } }, .{});
    try sa.content.appendChild(testing.allocator, mid);
    try mid.appendChild(testing.allocator, target);
    mid.setLayoutRect(.{ .x = 100, .y = 0, .w = 1000, .h = 40 });
    target.setLayoutRect(.{ .x = 500, .y = 0, .w = 60, .h = 40 });

    // Content coordinate left = 100 + 500 = 600; nearest aligns its right edge.
    scrollIntoViewX(sa.state, sa.content, target, .nearest);
    try testing.expectEqual(@as(f32, 460), sa.state.scroll_x);
    try testing.expectEqual(@as(f32, -460), sa.content.style.translate_x);
    // Already visible: unchanged.
    scrollIntoViewX(sa.state, sa.content, target, .nearest);
    try testing.expectEqual(@as(f32, 460), sa.state.scroll_x);
    // Left of the viewport: aligns its left edge.
    sa.state.scroll_x = 700;
    scrollIntoViewX(sa.state, sa.content, target, .nearest);
    try testing.expectEqual(@as(f32, 600), sa.state.scroll_x);
    // Clamped to the scrollable range.
    scrollIntoViewX(sa.state, sa.content, target, .start);
    try testing.expectEqual(@as(f32, 600), sa.state.scroll_x);
    setScrollX(sa.state, sa.content, 5000);
    try testing.expectEqual(@as(f32, 800), sa.state.scroll_x);
}

test "LP3 template scroll relay retirement preserves escaped callbacks and window ownership" {
    const t = std.testing;
    // Keep another live window while the first is repeatedly retired/recreated.
    const other = try Cx.init(t.allocator, t.io);
    defer other.deinit();
    const other_scope = try Scope.init(t.allocator, null, other.owner);
    defer other_scope.dispose();
    const other_area = try ScrollArea(.{ .height = 80 }).mount(other_scope, other);
    defer other.freeNode(other_area.container);
    const other_cell = other.scroll_ctx_cells.items[0].ptr;
    for (0..2) |_| {
        const cx = try Cx.init(t.allocator, t.io);
        defer cx.deinit();
        for (0..12) |round| {
            const scope = try Scope.init(t.allocator, null, cx.owner);
            const area = try ScrollArea(.{ .height = 80 }).mount(scope, cx);
            try t.expectEqual(@as(usize, 1), cx.scroll_ctx_cells.items.len);
            const cell: *ScrollCtxCell = @ptrCast(@alignCast(cx.scroll_ctx_cells.items[0].ptr));
            try t.expectEqual(@as(usize, 6), cell.references);
            if (round % 2 == 0) {
                scope.dispose();
                cx.freeNode(area.container);
            } else {
                cx.freeNode(area.container);
                scope.dispose();
            }
            try t.expect(cell.ctx == null);
            try t.expectEqual(@as(usize, 0), cell.references);
            try t.expectEqual(other_cell, other.scroll_ctx_cells.items[0].ptr);
        }
        // A callback hidden from event_ctx's current node slots still owns the
        // relay. It must remain safe across scope teardown and a later mount.
        const scope = try Scope.init(t.allocator, null, cx.owner);
        const area = try ScrollArea(.{ .height = 80 }).mount(scope, cx);
        const cell: *ScrollCtxCell = @ptrCast(@alignCast(cx.scroll_ctx_cells.items[0].ptr));
        const escaped = try box(cx, .{}, .{});
        escaped.meta.ownership.hooks.on_cleanup = .{ .callback = clearContentOnNodeFree, .context = @ptrCast(cell) };
        cell.references += 1;
        scope.dispose();
        cx.freeNode(area.container);
        try t.expectEqual(@as(usize, 1), cell.references);
        const next_scope = try Scope.init(t.allocator, null, cx.owner);
        defer next_scope.dispose();
        const next = try ScrollArea(.{ .height = 80 }).mount(next_scope, cx);
        defer cx.freeNode(next.container);
        try t.expectEqual(@as(usize, 2), cx.scroll_ctx_cells.items.len);
        cx.freeNode(escaped); // cell.ctx==null, release without touching dead ctx
        try t.expectEqual(@as(usize, 0), cell.references);
        const final_scope = try Scope.init(t.allocator, null, cx.owner);
        defer final_scope.dispose();
        const last = try ScrollArea(.{ .height = 80 }).mount(final_scope, cx);
        defer cx.freeNode(last.container);
        try t.expectEqual(@as(usize, 2), cx.scroll_ctx_cells.items.len);
        for (cx.scroll_ctx_cells.items) |entry| try t.expect(entry.ptr != @as(*anyopaque, @ptrCast(cell)) or @as(*ScrollCtxCell, @ptrCast(@alignCast(entry.ptr))).ctx != null);
    }
}

test "ScrollArea: mountScrollArea 在任意分配点失败时不泄漏" {
    // OOM injection of PlainTextEditor.mount: 98 leak stacks top out at mountScrollArea, but
    // in isolation it leaks 0. Stack tops show *where* memory was allocated, not *who* must free.
    // The real bug was in the caller (LineVirtualList): missing errdefer on my_scope and
    // sa.container.
    //
    // Regression guard: don't regress mountScrollArea's cleanup contract.
    const t = std.testing;

    // First measure how many allocation points a successful call consumes.
    const total_allocs = blk: {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        var counting = t.FailingAllocator.init(arena.allocator(), .{});
        const ctx = try Cx.init(counting.allocator(), std.testing.io);
        defer ctx.deinit();
        const scope = try Scope.init(counting.allocator(), null, ctx.owner);
        defer scope.dispose();
        const before = counting.alloc_index;
        _ = try ScrollArea(.{ .width = 300, .height = 200 }).mount(scope, ctx);
        break :blk counting.alloc_index - before;
    };
    try t.expect(total_allocs > 0);

    var induced: usize = 0;
    var leaked: usize = 0;
    var first_leak: ?usize = null;

    for (0..total_allocs) |failure_index| {
        // Each injection point uses independent GPA; use deinit() == .leak to detect leaks.
        // Arena would reclaim leaks as a whole, hiding these defects.
        var gpa = std.heap.DebugAllocator(.{ .safety = true }){};
        {
            var failing = t.FailingAllocator.init(gpa.allocator(), .{});
            const ctx = Cx.init(failing.allocator(), std.testing.io) catch {
                _ = gpa.deinit();
                continue;
            };
            const scope = Scope.init(failing.allocator(), null, ctx.owner) catch {
                ctx.deinit();
                _ = gpa.deinit();
                continue;
            };

            failing.fail_index = failing.alloc_index + failure_index;
            failing.resize_fail_index = failing.resize_index + failure_index;
            const result = ScrollArea(.{ .width = 300, .height = 200 }).mount(scope, ctx);
            failing.fail_index = std.math.maxInt(usize);
            failing.resize_fail_index = std.math.maxInt(usize);

            if (result) |r| {
                // Success: caller owns this detached subtree.
                ctx.freeNode(r.container);
            } else |_| {
                induced += 1;
            }
            scope.dispose();
            ctx.deinit();
        }
        if (gpa.deinit() == .leak) {
            leaked += 1;
            if (first_leak == null) first_leak = failure_index;
        }
    }

    // No-op guard uses ratio not absolute floor (calibration as oom_sweep.zig): induced > 0
    // threshold is three orders below measured value, can't block allocation-point collapse.
    const min_induced = total_allocs / 2;
    if (induced < min_induced) {
        std.debug.print(
            "\n[{s}] sweep 覆盖坍塌: induced={d} / total_allocs={d}（要求 >= {d}）\n",
            .{ "scroll_area", induced, total_allocs, min_induced },
        );
    }
    try t.expect(induced >= min_induced);
    if (leaked > 0) {
        std.debug.print(
            "\n[scroll_area] LEAK at {d}/{d} failure points; first={?d}\n",
            .{ leaked, total_allocs, first_leak },
        );
    }
    try t.expectEqual(@as(usize, 0), leaked);
}

test "ScrollArea: mountScrollArea 在 childScope 下失败时不泄漏" {
    // Prior test used root scope and didn't attach container to any parent tree, result clean.
    // Consumer (downstream editor line_virtual_list) calls differently: passes scope.childScope()
    // derived scope, and container later attaches to main_lane. This test replicates that pattern
    // to determine if 'dependency-side leak' needs consumer context.
    const t = std.testing;

    const total_allocs = blk: {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        var counting = t.FailingAllocator.init(arena.allocator(), .{});
        const ctx = try Cx.init(counting.allocator(), std.testing.io);
        defer ctx.deinit();
        const root_scope = try Scope.init(counting.allocator(), null, ctx.owner);
        defer root_scope.dispose();
        const child = try root_scope.childScope();
        const before = counting.alloc_index;
        _ = try ScrollArea(.{ .width = 300, .height = 200 }).mount(child, ctx);
        break :blk counting.alloc_index - before;
    };
    try t.expect(total_allocs > 0);

    var induced: usize = 0;
    var leaked: usize = 0;
    var first_leak: ?usize = null;

    for (0..total_allocs) |failure_index| {
        var gpa = std.heap.DebugAllocator(.{ .safety = true }){};
        {
            var failing = t.FailingAllocator.init(gpa.allocator(), .{});
            const ctx = Cx.init(failing.allocator(), std.testing.io) catch {
                _ = gpa.deinit();
                continue;
            };
            const root_scope = Scope.init(failing.allocator(), null, ctx.owner) catch {
                ctx.deinit();
                _ = gpa.deinit();
                continue;
            };
            const parent = box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{}) catch {
                root_scope.dispose();
                ctx.deinit();
                _ = gpa.deinit();
                continue;
            };
            const child = root_scope.childScope() catch {
                ctx.freeNode(parent);
                root_scope.dispose();
                ctx.deinit();
                _ = gpa.deinit();
                continue;
            };

            failing.fail_index = failing.alloc_index + failure_index;
            failing.resize_fail_index = failing.resize_index + failure_index;
            const result = ScrollArea(.{ .width = 300, .height = 200 }).mount(child, ctx);
            const appended = if (result) |r| blk2: {
                parent.appendChild(failing.allocator(), r.container) catch break :blk2 false;
                break :blk2 true;
            } else |_| false;
            failing.fail_index = std.math.maxInt(usize);
            failing.resize_fail_index = std.math.maxInt(usize);

            if (result) |r| {
                if (!appended) ctx.freeNode(r.container);
            } else |_| {
                induced += 1;
                // KEY: on failure path, **only dispose scope, don't freeNode separately**.
                // This matches consumer LineVirtualList pattern: when mountScrollArea fails
                // internally,
                // caller doesn't get sa, relies on scope cleanup alone. If we freeNode here too,
                // we mask the defect (first version did this, showed 0 leaks).
            }
            // Order matches consumer pt_editor.mount errdefer: dispose scope first, then freeNode.
            root_scope.dispose();
            ctx.freeNode(parent);
            ctx.deinit();
        }
        if (gpa.deinit() == .leak) {
            leaked += 1;
            if (first_leak == null) first_leak = failure_index;
        }
    }

    // No-op guard uses ratio not absolute floor (calibration as oom_sweep.zig): induced > 0
    // threshold is three orders below measured value, can't block allocation-point collapse.
    const min_induced = total_allocs / 2;
    if (induced < min_induced) {
        std.debug.print(
            "\n[{s}] sweep 覆盖坍塌: induced={d} / total_allocs={d}（要求 >= {d}）\n",
            .{ "scroll_area", induced, total_allocs, min_induced },
        );
    }
    try t.expect(induced >= min_induced);
    if (leaked > 0) {
        std.debug.print(
            "\n[scroll_area/childScope] LEAK at {d}/{d} failure points; first={?d}\n",
            .{ leaked, total_allocs, first_leak },
        );
    }
    try t.expectEqual(@as(usize, 0), leaked);
}

test "ScrollArea: fit + max 被夹住的列容器里收缩成可滚动，px 兄弟不被推出容器" {
    // Pattern like popover chrome height-limited by autosize: head(px) + ScrollArea(fit) +
    // footer(px).
    // Pre-fix: layoutChildren didn't recompute fit child's intrinsic, overflow underestimated,
    // ScrollArea still laid out at content height 300, footer pushed to y=320 (container only 100
    // tall).
    const t = std.testing;
    var ctx = try Cx.init(t.allocator, std.testing.io);
    defer ctx.deinit();
    const root = try box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 800 }, .align_items = .start }, .{});
    ctx.root = root;
    const scope = try Scope.init(t.allocator, null, ctx.owner);
    defer scope.dispose();

    const panel = try box(ctx, .{ .width = .{ .px = 300 }, .height = .{ .fit = .{ .max = 100 } }, .direction = .column, .overflow_hidden = true }, .{});
    try root.appendChild(t.allocator, panel);
    const head = try box(ctx, .{ .width = .{ .grow = .{} }, .height = .{ .px = 20 }, .flex_shrink = 0 }, .{});
    try panel.appendChild(t.allocator, head);
    const sa = try ScrollArea(.{}).mount(scope, ctx);
    sa.container.style.height = .{ .fit = .{} };
    try panel.appendChild(t.allocator, sa.container);
    for (0..10) |_| {
        const row = try box(ctx, .{ .width = .{ .grow = .{} }, .height = .{ .px = 30 } }, .{});
        try sa.content.appendChild(t.allocator, row);
    }
    const foot = try box(ctx, .{ .width = .{ .grow = .{} }, .height = .{ .px = 20 }, .flex_shrink = 0 }, .{});
    try panel.appendChild(t.allocator, foot);

    ctx.layout();
    const p = panel.globalRect();
    try t.expectApproxEqAbs(@as(f32, 100), p.h, 0.5);
    // Container squeezed to 100 - 20 - 20, content stays 300 (not squashed, can scroll)
    try t.expectApproxEqAbs(@as(f32, 60), sa.container.globalRect().h, 0.5);
    try t.expectApproxEqAbs(@as(f32, 300), sa.content.globalRect().h, 0.5);
    // footer fully inside container
    const f = foot.globalRect();
    try t.expectApproxEqAbs(@as(f32, 20), f.h, 0.5);
    try t.expect(f.y + f.h <= p.y + p.h + 0.5);

    // Enough space: no shrink, content-driven as usual
    panel.style.height = .{ .fit = .{ .max = 1000 } };
    panel.markSizingDirty();
    ctx.layout();
    try t.expectApproxEqAbs(@as(f32, 340), panel.globalRect().h, 0.5);
    try t.expectApproxEqAbs(@as(f32, 300), sa.container.globalRect().h, 0.5);
}

test "ScrollArea: ext.max_height（popover autosize 的写法）夹住的列容器里同样收缩可滚" {
    const t = std.testing;
    var ctx = try Cx.init(t.allocator, std.testing.io);
    defer ctx.deinit();
    const root = try box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 800 }, .align_items = .start }, .{});
    ctx.root = root;
    const scope = try Scope.init(t.allocator, null, ctx.owner);
    defer scope.dispose();

    const panel = try box(ctx, .{ .width = .{ .px = 300 }, .height = .{ .fit = .{} }, .direction = .column, .overflow_hidden = true }, .{});
    try root.appendChild(t.allocator, panel);
    (try panel.style.ensureExtFallible(t.allocator)).max_height = 100;
    const sa = try ScrollArea(.{}).mount(scope, ctx);
    sa.container.style.height = .{ .fit = .{} };
    try panel.appendChild(t.allocator, sa.container);
    for (0..10) |_| {
        const row = try box(ctx, .{ .width = .{ .grow = .{} }, .height = .{ .px = 30 } }, .{});
        try sa.content.appendChild(t.allocator, row);
    }
    const foot = try box(ctx, .{ .width = .{ .grow = .{} }, .height = .{ .px = 20 }, .flex_shrink = 0 }, .{});
    try panel.appendChild(t.allocator, foot);

    ctx.layout();
    const p = panel.globalRect();
    try t.expectApproxEqAbs(@as(f32, 100), p.h, 0.5);
    try t.expectApproxEqAbs(@as(f32, 80), sa.container.globalRect().h, 0.5);
    try t.expectApproxEqAbs(@as(f32, 300), sa.content.globalRect().h, 0.5);
    const f = foot.globalRect();
    try t.expect(f.y + f.h <= p.y + p.h + 0.5);
}

test "ScrollArea: px 0 + overflow_hidden 的隐藏容器里，flex 收缩为零后重新显示恢复尺寸" {
    // CSS flex shrinks the hidden dialog to zero. Reopening must recompute
    // the intrinsic basis, rather than keeping the previously frozen result.
    const t = std.testing;
    var ctx = try Cx.init(t.allocator, std.testing.io);
    defer ctx.deinit();
    const root = try box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 800 }, .align_items = .start }, .{});
    ctx.root = root;
    const scope = try Scope.init(t.allocator, null, ctx.owner);
    defer scope.dispose();

    const hidden = try box(ctx, .{ .width = .{ .px = 0 }, .height = .{ .px = 0 }, .direction = .column, .overflow_hidden = true }, .{});
    try root.appendChild(t.allocator, hidden);
    const dialog = try box(ctx, .{ .width = .{ .px = 300 }, .height = .{ .fit = .{ .max = 600 } }, .direction = .column, .overflow_hidden = true }, .{});
    try hidden.appendChild(t.allocator, dialog);
    const sa = try ScrollArea(.{}).mount(scope, ctx);
    sa.container.style.height = .{ .fit = .{} };
    try dialog.appendChild(t.allocator, sa.container);
    for (0..4) |_| {
        const row = try box(ctx, .{ .width = .{ .grow = .{} }, .height = .{ .px = 30 } }, .{});
        try sa.content.appendChild(t.allocator, row);
    }

    ctx.layout();
    try t.expectApproxEqAbs(@as(f32, 0), dialog.globalRect().h, 0.5);
    try t.expectApproxEqAbs(@as(f32, 0), sa.container.globalRect().h, 0.5);
    hidden.style.width = .{ .px = 300 };
    hidden.style.height = .{ .px = 200 };
    hidden.markSizingDirty();
    ctx.layout();
    try t.expectApproxEqAbs(@as(f32, 120), dialog.globalRect().h, 0.5);
    try t.expectApproxEqAbs(@as(f32, 120), sa.container.globalRect().h, 0.5);
}

/// Validated read interface; never expose an event-context cast to callers.
pub const PersistView = struct { key: ?[]const u8, x: f32, y: f32, anchor_required: bool };
fn persistContext(node: *Node) ?*ScrollEventCtx {
    if (node.behavior.events.on_event != scrollEventHandler) return null;
    const ptr = node.behavior.events.event_context orelse return null;
    const ctx: *ScrollEventCtx = @ptrCast(@alignCast(ptr));
    if (ctx.cell) |cell| if (cell.ctx != ctx) return null;
    return ctx;
}
pub fn persistView(node: *Node) ?PersistView {
    const ctx = persistContext(node) orelse return null;
    return .{ .key = ctx.persist_key orelse node.meta.ownership.meta.test_id, .x = ctx.state.scroll_x, .y = ctx.state.scroll_y, .anchor_required = ctx.state.external_content_height or ctx.state.external_content_width };
}
pub fn restorePersistOffset(node: *Node, x: f32, y: f32) void {
    const ctx = persistContext(node) orelse return;
    const content = ctx.content orelse return;
    if (!std.math.isFinite(x) or !std.math.isFinite(y)) return;
    // Clamp against the current layout (a restore can run before the next layout observer pass).
    state_mod.refreshExtents(ctx.state, node, content);
    setScrollY(ctx.state, content, y);
    const state = ctx.state;
    state.touching = false;
    state.momentum_active = false;
    state.scroll_x = std.math.clamp(x, 0, state.maxScrollX());
    state.bonus_x = 0;
    state.bonus_velocity_x = 0;
    state.bounce_active_x = false;
    state.momentum_spent_x = false;
    content.style.translate_x = state.contentTranslateX();
    content.markHitLayerMotionPropDirty();
    ctx.cx.needs_redraw = true;
}

test "persist scroll key, offset clamp, gesture reset and detached context" {
    const allocator = std.testing.allocator;
    const cx = try Cx.init(allocator, std.testing.io);
    defer cx.deinit();
    const scope = try Scope.init(allocator, null, cx.owner);
    cx.root_scope = scope;
    const result = try ScrollArea(.{ .width = 100, .height = 80, .persist_key = "stable-scroll" }).mount(scope, cx);
    cx.root = result.container;
    const state = result.state;
    state.content_width = 300;
    state.content_height = 500;
    state.viewport_width = 100;
    state.viewport_height = 80;
    state.bonus_x = 20;
    state.bonus_y = 30;
    restorePersistOffset(result.container, 900, 900);
    const persisted = persistView(result.container).?;
    try std.testing.expectEqualStrings("stable-scroll", persisted.key.?);
    try std.testing.expectEqual(@as(f32, 200), persisted.x);
    try std.testing.expectEqual(@as(f32, 420), persisted.y);
    try std.testing.expectEqual(@as(f32, 0), state.bonus_x);
    try std.testing.expectEqual(@as(f32, 0), state.bonus_y);
    const ctx: *ScrollEventCtx = @ptrCast(@alignCast(result.container.behavior.events.event_context.?));
    ctx.cell.?.ctx = null;
    try std.testing.expect(persistView(result.container) == null);
    restorePersistOffset(result.container, 0, 0);
    try std.testing.expectEqual(@as(f32, 420), state.scroll_y);
    ctx.cell.?.ctx = ctx;
}

// Hover events are window coordinates; scrollbar frames are local to the viewport.
test "ScrollArea: scrollbar hover survives an offset viewport" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const root = try box(ctx, .{ .width = .fixed(600), .height = .fixed(400), .padding = Padding.all(40) }, .{});
    ctx.root = root;
    const sa = try ScrollArea(.{ .width = 300, .height = 200, .content_height = 1000 }).mount(scope, ctx);
    try root.appendChild(ctx.allocator, sa.container);
    ctx.layout();
    sa.state.onScrollActivity();
    scrollbarBeforeRender(sa.container);
    const ec: *ScrollEventCtx = @ptrCast(@alignCast(sa.container.behavior.events.event_context.?));
    const r = ec.scrollbar.?.globalRect();
    _ = scrollEventHandler(.{ .mouse_move = .{ .x = r.x + r.w / 2, .y = r.y + r.h / 2, .dx = 0, .dy = 0 } }, ec);
    try std.testing.expect(sa.state.scrollbar_hovered);
    scrollbarBeforeRender(sa.container);
    // COMPONENTS.json: hover expands thumb 4 -> 6 and reveals the 10px track.
    try std.testing.expectEqual(@as(f32, 6), ec.scrollbar.?.rectFromWorldOrFallback().w);
    try std.testing.expectEqual(@as(f32, 10), ec.track_v.?.rectFromWorldOrFallback().w);
}

test "ScrollArea: thumbs show grab and hold a capture-scoped grabbing cursor while dragged" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const root = try box(ctx, .{ .width = .fixed(600), .height = .fixed(400) }, .{});
    ctx.root = root;
    const sa = try ScrollArea(.{ .width = 300, .height = 200, .content_width = 800, .content_height = 1000 }).mount(scope, ctx);
    try root.appendChild(ctx.allocator, sa.container);
    ctx.layout();
    sa.state.onScrollActivity();
    scrollbarBeforeRender(sa.container);
    const ec: *ScrollEventCtx = @ptrCast(@alignCast(sa.container.behavior.events.event_context.?));
    try std.testing.expectEqual(core.CursorShape.grab, ec.scrollbar.?.style.cursor);
    try std.testing.expectEqual(core.CursorShape.grab, ec.scrollbar_h.?.style.cursor);

    const r = ec.scrollbar.?.globalRect();
    _ = scroll_scrollbar.scrollbarEventHandler(.{ .mouse_down = .{ .x = r.x + r.w / 2, .y = r.y + r.h / 2, .button = .left, .modifiers = .{} } }, ec);
    try std.testing.expect(sa.state.scrollbar_dragging);
    try std.testing.expectEqual(@as(usize, 1), ctx.cursor_state.leases.items.len);
    try std.testing.expectEqual(core.CursorShape.grabbing, ctx.cursor_state.leases.items[0].shape);

    // Ending the capture ends the lease; the target underneath decides the cursor again.
    ctx.releasePointerCapture();
    ctx.refreshCursor();
    try std.testing.expectEqual(@as(usize, 0), ctx.cursor_state.leases.items.len);
}

test "ScrollArea: leaving the container clears scrollbar hover" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const root = try box(ctx, .{ .width = .fixed(600), .height = .fixed(400) }, .{});
    ctx.root = root;
    const sa = try ScrollArea(.{ .width = 300, .height = 200, .content_width = 800, .content_height = 1000 }).mount(scope, ctx);
    try root.appendChild(ctx.allocator, sa.container);
    ctx.layout();
    sa.state.onScrollActivity();
    scrollbarBeforeRender(sa.container);
    const ec: *ScrollEventCtx = @ptrCast(@alignCast(sa.container.behavior.events.event_context.?));
    const r = ec.scrollbar.?.globalRect();
    _ = scrollEventHandler(.{ .mouse_move = .{ .x = r.x + r.w / 2, .y = r.y + r.h / 2, .dx = 0, .dy = 0 } }, ec);
    try std.testing.expect(sa.state.scrollbar_hovered);
    // The pointer exits straight through the hover slop: no further move reaches the container.
    _ = scrollEventHandler(.mouse_leave, ec);
    try std.testing.expect(!sa.state.scrollbar_hovered);
    try std.testing.expect(!sa.state.scrollbar_hovered_h);
    scrollbarBeforeRender(sa.container);
    try std.testing.expectEqual(@as(f32, 4), ec.scrollbar.?.rectFromWorldOrFallback().w);
}

// ---- Stationary-pointer hover (core/cx_hover.zig) through the real ScrollArea ----

const HoverRig = struct {
    fn rows(cx: *Cx, parent: *Node, out: []*Node, h: f32) !void {
        for (out) |*slot| {
            const row = try box(cx, .{ .width = .{ .grow = .{} }, .height = .{ .px = h } }, .{});
            // Rows that observe pointer events participate in hit testing (hoverable rows).
            row.behavior.events.on_event = observe;
            try parent.appendChild(std.testing.allocator, row);
            slot.* = row;
        }
    }

    fn observe(_: core.Event, _: ?*anyopaque) core.EventResult {
        return .ignored;
    }

    fn settle(cx: *Cx) !void {
        var frames: usize = 0;
        while (cx.wantsFrame() and frames < 600) : (frames += 1) {
            cx.advanceFrameClock();
            cx.layout();
            _ = cx.render();
        }
        try std.testing.expect(!cx.wantsFrame());
    }

    fn indexOf(rows_: []*Node, node: ?*Node) ?usize {
        const n = node orelse return null;
        for (rows_, 0..) |r, i| if (r == n) return i;
        return null;
    }
};

test "ScrollArea: wheel scroll under a stationary pointer moves hover to the row now under it" {
    var cx = try Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    cx.setViewport(400, 300);
    try cx.setTestFrameStep(16);
    cx.caret_flip_host = true;
    const scope = try Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    const root = try box(cx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    cx.root = root;
    const area = try ScrollArea(.{ .width = 300, .height = 200, .content_height = 600, .rubber_band_y = false }).mount(scope, cx);
    try root.appendChild(std.testing.allocator, area.container);
    var rows: [15]*Node = undefined;
    try HoverRig.rows(cx, area.content, &rows, 40);
    try HoverRig.settle(cx);

    cx.handleMouseMove(150, 20);
    try std.testing.expectEqual(@as(?usize, 0), HoverRig.indexOf(&rows, cx.hovered_node));
    cx.handleScroll(.{ .x = 150, .y = 20, .dx = 0, .dy = -80 });
    try HoverRig.settle(cx);
    try std.testing.expectEqual(@as(f32, 80), area.state.scroll_y);
    try std.testing.expectEqual(@as(?usize, 2), HoverRig.indexOf(&rows, cx.hovered_node));

    // Trackpad gesture with momentum: hover tracks every committed position and lands on the row
    // under the pointer once the content rests.
    cx.handleScroll(.{ .x = 150, .y = 20, .dx = 0, .dy = 0, .phase = .began });
    cx.handleScroll(.{ .x = 150, .y = 20, .dx = 0, .dy = -50, .phase = .changed });
    cx.handleScroll(.{ .x = 150, .y = 20, .dx = 0, .dy = 0, .phase = .ended });
    cx.handleScroll(.{ .x = 150, .y = 20, .dx = 0, .dy = -30, .momentum = .began });
    cx.handleScroll(.{ .x = 150, .y = 20, .dx = 0, .dy = 0, .momentum = .ended });
    try HoverRig.settle(cx);
    const want: usize = @intFromFloat(@floor((20 + area.state.scroll_y) / 40));
    try std.testing.expect(area.state.scroll_y > 80);
    try std.testing.expectEqual(@as(?usize, want), HoverRig.indexOf(&rows, cx.hovered_node));
}

test "ScrollArea: a wheel that moves nothing requests no frame" {
    var cx = try Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    cx.setViewport(400, 300);
    try cx.setTestFrameStep(16);
    cx.caret_flip_host = true;
    const scope = try Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    const root = try box(cx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    cx.root = root;
    const area = try ScrollArea(.{ .width = 300, .height = 200, .content_height = 600, .rubber_band_y = false }).mount(scope, cx);
    try root.appendChild(std.testing.allocator, area.container);
    var rows: [15]*Node = undefined;
    try HoverRig.rows(cx, area.content, &rows, 40);
    try HoverRig.settle(cx);
    // A live stationary pointer over the rows: hover re-resolution must not keep frames going.
    cx.handleMouseMove(150, 20);
    try HoverRig.settle(cx);

    // Against the top end: the first wheel reveals the scroller (a visible change) ...
    cx.handleScroll(.{ .x = 150, .y = 20, .dx = 0, .dy = 40 });
    try std.testing.expect(cx.wantsFrame());
    try HoverRig.settle(cx);
    // ... and a wheel with the scroller already shown and the content pinned changes nothing.
    cx.handleScroll(.{ .x = 150, .y = 20, .dx = 0, .dy = 40 });
    try std.testing.expect(!cx.wantsFrame());
    try std.testing.expectEqual(@as(f32, 0), area.state.scroll_y);

    // A wheel that moves the content renders, and so does the next one pinned at the far end
    // only while it still moves.
    cx.handleScroll(.{ .x = 150, .y = 20, .dx = 0, .dy = -1000 });
    try std.testing.expect(cx.wantsFrame());
    try HoverRig.settle(cx);
    try std.testing.expectEqual(@as(f32, 400), area.state.scroll_y);
    cx.handleScroll(.{ .x = 150, .y = 20, .dx = 0, .dy = -40 });
    try std.testing.expect(!cx.wantsFrame());
}

test "ScrollArea: overscroll at a pinned end still renders its rubber band and spring" {
    var cx = try Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    cx.setViewport(400, 300);
    try cx.setTestFrameStep(16);
    cx.caret_flip_host = true;
    const scope = try Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    const root = try box(cx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    cx.root = root;
    const area = try ScrollArea(.{ .width = 300, .height = 200, .content_height = 600 }).mount(scope, cx);
    try root.appendChild(std.testing.allocator, area.container);
    var rows: [15]*Node = undefined;
    try HoverRig.rows(cx, area.content, &rows, 40);
    try HoverRig.settle(cx);
    cx.handleMouseMove(150, 20);
    try HoverRig.settle(cx);
    // Pinned at the top, a trackpad pull past the end rubber-bands: it renders ...
    cx.handleScroll(.{ .x = 150, .y = 20, .dx = 0, .dy = 0, .phase = .began });
    cx.handleScroll(.{ .x = 150, .y = 20, .dx = 0, .dy = 40, .phase = .changed });
    try std.testing.expect(cx.wantsFrame());
    try std.testing.expect(area.state.bonus_y != 0);
    // ... and the release hands the overscroll to the spring, which runs to rest.
    cx.handleScroll(.{ .x = 150, .y = 20, .dx = 0, .dy = 0, .phase = .ended });
    try std.testing.expect(cx.wantsFrame());
    try HoverRig.settle(cx);
    try std.testing.expectEqual(@as(f32, 0), area.state.bonus_y);
    try std.testing.expectEqual(@as(f32, 0), area.state.scroll_y);
}

test "ScrollArea: a wheel over content that cannot scroll requests no frame" {
    var cx = try Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    cx.setViewport(400, 300);
    try cx.setTestFrameStep(16);
    cx.caret_flip_host = true;
    const scope = try Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    const root = try box(cx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    cx.root = root;
    const area = try ScrollArea(.{ .width = 300, .height = 200, .content_height = 120 }).mount(scope, cx);
    try root.appendChild(std.testing.allocator, area.container);
    var rows: [3]*Node = undefined;
    try HoverRig.rows(cx, area.content, &rows, 40);
    // A window-level capture handler that passes scroll events on (a key-binding layer) is not
    // a change either.
    const Keys = struct {
        var seen: u32 = 0;
        fn capture(e: core.Event, _: ?*anyopaque) core.EventResult {
            if (e == .scroll) seen += 1;
            return .ignored;
        }
    };
    root.behavior.events.on_event_capture = Keys.capture;
    try HoverRig.settle(cx);
    cx.handleMouseMove(150, 20);
    try HoverRig.settle(cx);
    for ([_]f32{ 40, -40, 12, -12 }) |dy| {
        cx.handleScroll(.{ .x = 150, .y = 20, .dx = 0, .dy = dy });
        try std.testing.expect(!cx.wantsFrame());
    }
    try std.testing.expectEqual(@as(u32, 4), Keys.seen);
}

test "ScrollArea: a scroll handler that takes the event without declaring it inert still renders" {
    var cx = try Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    cx.setViewport(400, 300);
    try cx.setTestFrameStep(16);
    cx.caret_flip_host = true;
    const root = try box(cx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    cx.root = root;
    const canvas = try box(cx, .{ .width = .{ .px = 200 }, .height = .{ .px = 200 } }, .{});
    const App = struct {
        var seen: u32 = 0;
        fn onScroll(_: @import("../../events.zig").ScrollEvent, _: ?*anyopaque) core.EventResult {
            seen += 1;
            return .stop;
        }
    };
    canvas.behavior.events.on_scroll = App.onScroll;
    try root.appendChild(std.testing.allocator, canvas);
    try HoverRig.settle(cx);
    cx.handleScroll(.{ .x = 50, .y = 50, .dx = 0, .dy = 12 });
    try std.testing.expectEqual(@as(u32, 1), App.seen);
    try std.testing.expect(cx.wantsFrame());
}

test "ScrollArea: nested and programmatic scroll re-resolve hover under a stationary pointer" {
    var cx = try Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    cx.setViewport(400, 300);
    try cx.setTestFrameStep(16);
    cx.caret_flip_host = true;
    const scope = try Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    const root = try box(cx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    cx.root = root;
    const outer = try ScrollArea(.{ .width = 300, .height = 200, .content_height = 600, .rubber_band_y = false }).mount(scope, cx);
    try root.appendChild(std.testing.allocator, outer.container);
    const header = try box(cx, .{ .width = .{ .grow = .{} }, .height = .{ .px = 100 } }, .{});
    try outer.content.appendChild(std.testing.allocator, header);
    const inner = try ScrollArea(.{ .width = 300, .height = 120, .content_height = 600, .rubber_band_y = false }).mount(scope, cx);
    try outer.content.appendChild(std.testing.allocator, inner.container);
    var rows: [20]*Node = undefined;
    try HoverRig.rows(cx, inner.content, &rows, 30);
    const filler = try box(cx, .{ .width = .{ .grow = .{} }, .height = .{ .px = 380 } }, .{});
    try outer.content.appendChild(std.testing.allocator, filler);
    try HoverRig.settle(cx);

    // Pointer 50px into the inner list: inner row 1.
    cx.handleMouseMove(150, 150);
    try std.testing.expectEqual(@as(?usize, 1), HoverRig.indexOf(&rows, cx.hovered_node));
    // Programmatic scroll of the outer area carries the inner list up by 60: inner row 3.
    setScrollY(outer.state, outer.content, 60);
    try HoverRig.settle(cx);
    try std.testing.expectEqual(@as(?usize, 3), HoverRig.indexOf(&rows, cx.hovered_node));
    // Wheel over the inner list scrolls the inner area by 30: inner row 4.
    cx.handleScroll(.{ .x = 150, .y = 150, .dx = 0, .dy = -30 });
    try HoverRig.settle(cx);
    try std.testing.expectEqual(@as(f32, 30), inner.state.scroll_y);
    try std.testing.expectEqual(@as(?usize, 4), HoverRig.indexOf(&rows, cx.hovered_node));
}

// ---- Hit layers (core/hit_runtime.zig HitLayer): scrolling moves hit geometry, no rebuild ----

const HitLayerRig = struct {
    cx: *Cx,
    scope: *Scope,
    area: ScrollAreaResult,
    rows: [15]*Node = undefined,

    fn init(rig: *HitLayerRig) !void {
        rig.cx = try Cx.init(std.testing.allocator, std.testing.io);
        rig.cx.setViewport(400, 300);
        try rig.cx.setTestFrameStep(16);
        rig.cx.caret_flip_host = true;
        rig.scope = try Scope.init(std.testing.allocator, null, rig.cx.owner);
        const root = try box(rig.cx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
        rig.cx.root = root;
        // Area at y=50: rows above y=50 and below y=250 are clipped by the viewport.
        const spacer = try box(rig.cx, .{ .width = .{ .px = 400 }, .height = .{ .px = 50 } }, .{});
        try root.appendChild(std.testing.allocator, spacer);
        rig.area = try ScrollArea(.{ .width = 300, .height = 200, .content_height = 600, .rubber_band_y = false }).mount(rig.scope, rig.cx);
        try root.appendChild(std.testing.allocator, rig.area.container);
        try HoverRig.rows(rig.cx, rig.area.content, &rig.rows, 40);
        try HoverRig.settle(rig.cx);
    }

    fn deinit(rig: *HitLayerRig) void {
        rig.scope.dispose();
        rig.cx.deinit();
    }

    fn rowAt(rig: *HitLayerRig, x: f32, y: f32) ?usize {
        return HoverRig.indexOf(&rig.rows, rig.cx.hitTest(x, y));
    }

    fn rowEpochs(rig: *HitLayerRig) [15]u32 {
        var out: [15]u32 = undefined;
        for (rig.rows, 0..) |row, i| out[i] = row.frame_state.frame_local.spatial.hit.epoch;
        return out;
    }
};

test "ScrollArea hit layer: scrolling moves row hits without rebuilding their proxies" {
    var rig: HitLayerRig = undefined;
    try rig.init();
    defer rig.deinit();
    const cx = rig.cx;
    try std.testing.expect(rig.area.content.behavior.interaction.hit_layer);
    try std.testing.expectEqual(@as(?usize, 0), rig.rowAt(150, 60));
    const epochs = rig.rowEpochs();
    cx.input_perf = .{};

    // Event time (no frame in between): the next hit already resolves at the new offset.
    cx.handleScroll(.{ .x = 150, .y = 60, .dx = 0, .dy = -80 });
    try std.testing.expectEqual(@as(f32, 80), rig.area.state.scroll_y);
    try std.testing.expectEqual(@as(?usize, 2), rig.rowAt(150, 60));
    try std.testing.expectEqual(@as(?usize, 6), rig.rowAt(150, 249));
    // Clip of the (unscrolled) viewport still applies to scrolled rows.
    try std.testing.expectEqual(@as(?usize, null), rig.rowAt(150, 45));
    try std.testing.expectEqual(@as(?usize, null), rig.rowAt(150, 255));
    cx.handleScroll(.{ .x = 150, .y = 60, .dx = 0, .dy = -40 });
    try std.testing.expectEqual(@as(?usize, 3), rig.rowAt(150, 60));
    try HoverRig.settle(cx);
    try std.testing.expectEqual(@as(?usize, 3), rig.rowAt(150, 60));
    try std.testing.expectEqual(@as(?usize, 7), rig.rowAt(150, 249));
    // No row proxy was re-emitted by either the event-time refresh or the frames.
    const after = rig.rowEpochs();
    try std.testing.expectEqual(@as(u32, 0), cx.input_perf.in_hit_full_rebuilds);
    try std.testing.expectEqualSlices(u32, &epochs, &after);
}

test "ScrollArea hit layer: layout change inside scrolled content rebuilds siblings at their new place" {
    // Partial rebuild inside a moved layer must place the reflowed siblings in layer space, and
    // the viewport clip entry (outside the layer) must keep clipping them.
    var rig: HitLayerRig = undefined;
    try rig.init();
    defer rig.deinit();
    const cx = rig.cx;
    cx.handleScroll(.{ .x = 150, .y = 60, .dx = 0, .dy = -80 });
    try HoverRig.settle(cx);
    // Row 3 grows by 40: rows 4.. move down by 40 in content space.
    rig.rows[3].style.height = .{ .px = 80 };
    rig.rows[3].markLayoutDirty();
    // Event-time query commits the layout first.
    // content y of point (150,60) = 60 - 50 + 80 = 90 -> row 2; y=210 -> content 240 -> row 4
    // (row 3 spans 120..200, row 4 200..240, row 5 240..280).
    try std.testing.expectEqual(@as(?usize, 2), rig.rowAt(150, 60));
    try std.testing.expectEqual(@as(?usize, 3), rig.rowAt(150, 150));
    try std.testing.expectEqual(@as(?usize, 5), rig.rowAt(150, 220));
    try std.testing.expectEqual(@as(?usize, null), rig.rowAt(150, 260));
    // Scrolling after the partial rebuild keeps both the rebuilt and the untouched rows exact.
    cx.handleScroll(.{ .x = 150, .y = 60, .dx = 0, .dy = 40 });
    try std.testing.expectEqual(@as(f32, 40), rig.area.state.scroll_y);
    try std.testing.expectEqual(@as(?usize, 1), rig.rowAt(150, 60));
    try std.testing.expectEqual(@as(?usize, 3), rig.rowAt(150, 190));
    try std.testing.expectEqual(@as(?usize, 4), rig.rowAt(150, 215));
    try HoverRig.settle(cx);
    try std.testing.expectEqual(@as(?usize, 4), rig.rowAt(150, 215));
}

test "ScrollArea hit layer: partial rebuild below the layer node stays in layer space" {
    // The rebuild root is a row inside the scrolled content: its parent chain must be composed
    // relative to the layer node, not in world space.
    var rig: HitLayerRig = undefined;
    try rig.init();
    defer rig.deinit();
    const cx = rig.cx;
    const chip = try box(cx, .{ .width = .{ .px = 50 }, .height = .{ .px = 20 } }, .{});
    chip.behavior.events.on_event = HoverRig.observe;
    try rig.rows[3].appendChild(std.testing.allocator, chip);
    try HoverRig.settle(cx);
    cx.handleScroll(.{ .x = 150, .y = 60, .dx = 0, .dy = -80 });
    try HoverRig.settle(cx);
    // Row 3 spans content 120..160 -> window y 90..130 at scroll 80; chip at its top-left.
    try std.testing.expectEqual(@as(?*Node, chip), cx.hitTest(20, 100));
    chip.style.width = .{ .px = 120 };
    chip.markLayoutDirty();
    try std.testing.expectEqual(@as(?*Node, chip), cx.hitTest(100, 100));
    try std.testing.expectEqual(@as(?usize, 3), rig.rowAt(100, 125));
    try HoverRig.settle(cx);
    try std.testing.expectEqual(@as(?*Node, chip), cx.hitTest(100, 100));
}

test "ScrollArea hit layer: nested areas clip and move independently" {
    var cx = try Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    cx.setViewport(400, 300);
    try cx.setTestFrameStep(16);
    cx.caret_flip_host = true;
    const scope = try Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    const root = try box(cx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    cx.root = root;
    const outer = try ScrollArea(.{ .width = 300, .height = 200, .content_height = 600, .rubber_band_y = false }).mount(scope, cx);
    try root.appendChild(std.testing.allocator, outer.container);
    const header = try box(cx, .{ .width = .{ .grow = .{} }, .height = .{ .px = 100 } }, .{});
    try outer.content.appendChild(std.testing.allocator, header);
    const inner = try ScrollArea(.{ .width = 300, .height = 120, .content_height = 600, .rubber_band_y = false }).mount(scope, cx);
    try outer.content.appendChild(std.testing.allocator, inner.container);
    var rows: [20]*Node = undefined;
    try HoverRig.rows(cx, inner.content, &rows, 30);
    const filler = try box(cx, .{ .width = .{ .grow = .{} }, .height = .{ .px = 380 } }, .{});
    try outer.content.appendChild(std.testing.allocator, filler);
    try HoverRig.settle(cx);

    // Inner viewport spans y 100..220.
    try std.testing.expectEqual(@as(?usize, 1), HoverRig.indexOf(&rows, cx.hitTest(150, 150)));
    // Inner scroll by 30: inner row under y=150 is now row 2; outer does not move.
    cx.handleScroll(.{ .x = 150, .y = 150, .dx = 0, .dy = -30 });
    try std.testing.expectEqual(@as(f32, 30), inner.state.scroll_y);
    try std.testing.expectEqual(@as(f32, 0), outer.state.scroll_y);
    try std.testing.expectEqual(@as(?usize, 2), HoverRig.indexOf(&rows, cx.hitTest(150, 150)));
    // Outer scroll by 60 (programmatic) carries the inner viewport to y 40..160.
    setScrollY(outer.state, outer.content, 60);
    try std.testing.expectEqual(@as(?usize, 4), HoverRig.indexOf(&rows, cx.hitTest(150, 150)));
    // Above the moved inner viewport: header (not an inner row); below it: filler.
    try std.testing.expectEqual(@as(?usize, null), HoverRig.indexOf(&rows, cx.hitTest(150, 35)));
    try std.testing.expectEqual(@as(?usize, null), HoverRig.indexOf(&rows, cx.hitTest(150, 165)));
    // y=41 is 1px into the moved inner viewport: inner content y 31 -> row 1.
    try std.testing.expectEqual(@as(?usize, 1), HoverRig.indexOf(&rows, cx.hitTest(150, 41)));
    try HoverRig.settle(cx);
    try std.testing.expectEqual(@as(?usize, 4), HoverRig.indexOf(&rows, cx.hitTest(150, 150)));
}

fn overlayBox(cx: *Cx, parent: *Node, top: f32, h: f32) !*Node {
    const n = try box(cx, .{ .width = .{ .px = 100 }, .height = .{ .px = h }, .position = .absolute }, .{});
    (try n.style.ensureExtFallible(cx.allocator)).inset = .{ .top = .{ .px = top }, .left = .{ .px = 0 } };
    n.behavior.events.on_event = HoverRig.observe;
    try parent.appendChild(std.testing.allocator, n);
    return n;
}

test "ScrollArea hit layer: overlapping children follow paint order through reorders and z" {
    // Children of a hit layer are numbered in blocks of their own (hit_runtime.HitBlock); the
    // topmost hit must still be the last painted one when their order changes without any of
    // them being rebuilt.
    var rig: HitLayerRig = undefined;
    try rig.init();
    defer rig.deinit();
    const cx = rig.cx;
    const content = rig.area.content;
    // Two overlays over row 0 (content y 0..30, window y 50..80), painted after the rows.
    const a = try overlayBox(cx, content, 0, 30);
    const b = try overlayBox(cx, content, 0, 30);
    try HoverRig.settle(cx);
    try std.testing.expectEqual(b, cx.hitTest(20, 60).?);
    // Reorder only: a painted last.
    var order: [17]*Node = undefined;
    order[0] = b;
    for (rig.rows, 0..) |row, i| order[i + 1] = row;
    order[16] = a;
    try content.replaceChildOrder(std.testing.allocator, &order);
    try std.testing.expectEqual(a, cx.hitTest(20, 60).?);
    // Moving b in front of everything (b is first in tree order): positive z paints it last.
    (try b.style.ensureExtFallible(cx.allocator)).z_index = 3;
    b.markOrderDirty();
    b.markInteractionDirty();
    try std.testing.expectEqual(b, cx.hitTest(20, 60).?);
    // Rows keep their place under the overlays; outside them rows hit.
    try std.testing.expectEqual(@as(?usize, 0), rig.rowAt(150, 60));
    try std.testing.expectEqual(@as(?usize, 3), rig.rowAt(20, 175));
    try HoverRig.settle(cx);
    try std.testing.expectEqual(b, cx.hitTest(20, 60).?);
    try std.testing.expectEqual(@as(?usize, 3), rig.rowAt(20, 175));
}

test "ScrollArea hit layer: a layer subtree sorts between its node and the node's later siblings" {
    var cx = try Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    cx.setViewport(400, 300);
    try cx.setTestFrameStep(16);
    cx.caret_flip_host = true;
    const scope = try Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    const root = try box(cx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    cx.root = root;
    root.behavior.events.on_event = HoverRig.observe;
    const outer = try ScrollArea(.{ .width = 300, .height = 200, .content_height = 600, .rubber_band_y = false }).mount(scope, cx);
    try root.appendChild(std.testing.allocator, outer.container);
    // An outer row holding a nested area and, painted after it, an overlay over it.
    const row = try box(cx, .{ .width = .{ .grow = .{} }, .height = .{ .px = 150 } }, .{});
    row.behavior.events.on_event = HoverRig.observe;
    try outer.content.appendChild(std.testing.allocator, row);
    const inner = try ScrollArea(.{ .width = 300, .height = 120, .content_height = 600, .rubber_band_y = false }).mount(scope, cx);
    try row.appendChild(std.testing.allocator, inner.container);
    var rows: [20]*Node = undefined;
    try HoverRig.rows(cx, inner.content, &rows, 30);
    const cover = try overlayBox(cx, row, 60, 30);
    // Window-level overlay after the outer area, over its top.
    const top_cover = try overlayBox(cx, root, 0, 20);
    try HoverRig.settle(cx);

    try std.testing.expectEqual(top_cover, cx.hitTest(20, 10).?);
    try std.testing.expectEqual(@as(?usize, 0), HoverRig.indexOf(&rows, cx.hitTest(150, 10)));
    try std.testing.expectEqual(cover, cx.hitTest(20, 70).?);
    try std.testing.expectEqual(@as(?usize, 2), HoverRig.indexOf(&rows, cx.hitTest(150, 70)));
    // Inner rows beat the row and the outer content they are nested in.
    try std.testing.expectEqual(@as(?usize, 3), HoverRig.indexOf(&rows, cx.hitTest(150, 100)));
    // Below the inner viewport: the outer row itself.
    try std.testing.expectEqual(row, cx.hitTest(150, 130).?);
    // Rebind an inner row (structure change inside the nested layer): order is kept.
    cx.input_perf = .{};
    const fresh = try box(cx, .{ .width = .{ .grow = .{} }, .height = .{ .px = 30 } }, .{});
    fresh.behavior.events.on_event = HoverRig.observe;
    try inner.content.insertChildBefore(std.testing.allocator, fresh, rows[2]);
    try std.testing.expectEqual(fresh, cx.hitTest(150, 70).?);
    try std.testing.expectEqual(cover, cx.hitTest(20, 70).?);
    try std.testing.expectEqual(@as(?usize, 2), HoverRig.indexOf(&rows, cx.hitTest(150, 100)));
    try std.testing.expectEqual(@as(u32, 0), cx.input_perf.in_hit_full_rebuilds);
}

test "ScrollArea hit layer: a removed or hidden row stops hitting without a full rebuild" {
    var rig: HitLayerRig = undefined;
    try rig.init();
    defer rig.deinit();
    const cx = rig.cx;
    cx.input_perf = .{};
    // Retained removal: the node stays alive, its proxies must go.
    const row2 = rig.rows[2];
    rig.area.content.removeChildRetained(row2);
    // Row 3 moved up into row 2's place (content y 80..120 -> window y 130..170).
    try std.testing.expectEqual(@as(?usize, 3), rig.rowAt(150, 140));
    try std.testing.expect(cx.hitTest(150, 140).? != row2);
    // Hidden row: no hit, siblings unchanged.
    rig.rows[5].setHitTestVisible(false);
    try std.testing.expect(cx.hitTest(150, 225) != rig.rows[5]);
    try std.testing.expectEqual(@as(?usize, 4), rig.rowAt(150, 185));
    try std.testing.expectEqual(@as(u32, 0), cx.input_perf.in_hit_full_rebuilds);
    try rig.area.content.appendChild(std.testing.allocator, row2);
    try HoverRig.settle(cx);
    try std.testing.expectEqual(@as(?usize, 3), rig.rowAt(150, 140));
    // A removed overlay leaves nothing behind: the row under it hits again.
    const cover = try overlayBox(cx, rig.area.content, 0, 30);
    try HoverRig.settle(cx);
    try std.testing.expectEqual(cover, cx.hitTest(20, 60).?);
    rig.area.content.removeChildRetained(cover);
    try std.testing.expectEqual(@as(?usize, 0), rig.rowAt(20, 60));
    try rig.area.content.appendChild(std.testing.allocator, cover);
    try std.testing.expectEqual(cover, cx.hitTest(20, 60).?);
}

test "ScrollArea hit layer: a change inside a row is committed when an ancestor of the layer is dirty too" {
    // The layer node's build keeps rows whose own geometry is unchanged, so the change inside the
    // row must be a partial root of its own even though the ancestor's root covers the layer node.
    var rig: HitLayerRig = undefined;
    try rig.init();
    defer rig.deinit();
    const cx = rig.cx;
    const inner = try box(cx, .{ .width = .{ .px = 50 }, .height = .{ .px = 40 } }, .{});
    inner.behavior.events.on_event = HoverRig.observe;
    try rig.rows[1].appendChild(std.testing.allocator, inner);
    try HoverRig.settle(cx);
    try std.testing.expectEqual(rig.rows[1], cx.hitTest(150, 110).?);
    cx.input_perf = .{};
    inner.style.width = .{ .px = 200 };
    inner.markLayoutDirty();
    rig.area.container.markLayoutDirty();
    try std.testing.expectEqual(inner, cx.hitTest(150, 110).?);
    try std.testing.expectEqual(@as(u32, 0), cx.input_perf.in_hit_full_rebuilds);
}

test "ScrollArea: latched trackpad gesture and momentum dispatch without hit tests" {
    var rig: HitLayerRig = undefined;
    try rig.init();
    defer rig.deinit();
    const cx = rig.cx;
    cx.handleScroll(.{ .x = 150, .y = 60, .dx = 0, .dy = 0, .phase = .began });
    cx.handleScroll(.{ .x = 150, .y = 60, .dx = 0, .dy = -20, .phase = .changed });
    try std.testing.expectEqual(@as(f32, 20), rig.area.state.scroll_y);
    // Latched: changed events go to the session owner without querying the scene, even with the
    // pointer outside the area.
    const queries = cx.perf.hit_test_count;
    cx.handleScroll(.{ .x = 390, .y = 290, .dx = 0, .dy = -20, .phase = .changed });
    cx.handleScroll(.{ .x = 390, .y = 290, .dx = 0, .dy = 0, .phase = .ended });
    cx.handleScroll(.{ .x = 390, .y = 290, .dx = 0, .dy = -10, .momentum = .began });
    cx.handleScroll(.{ .x = 390, .y = 290, .dx = 0, .dy = -10, .momentum = .changed });
    try std.testing.expectEqual(queries, cx.perf.hit_test_count);
    try std.testing.expectEqual(@as(f32, 60), rig.area.state.scroll_y);
    cx.handleScroll(.{ .x = 390, .y = 290, .dx = 0, .dy = 0, .momentum = .ended });
    // A new gesture hit-tests again: outside the area nothing scrolls.
    cx.handleScroll(.{ .x = 390, .y = 290, .dx = 0, .dy = 0, .phase = .began });
    try std.testing.expect(cx.perf.hit_test_count > queries);
    cx.handleScroll(.{ .x = 390, .y = 290, .dx = 0, .dy = -20, .phase = .changed });
    try std.testing.expectEqual(@as(f32, 60), rig.area.state.scroll_y);
}

test "Cx hit refresh: one before-render tick per scene mutation between frames" {
    var rig: HitLayerRig = undefined;
    try rig.init();
    defer rig.deinit();
    const cx = rig.cx;
    // Pending render-only work after the last frame tick (e.g. an animation repaint).
    rig.rows[0].markRenderDirty();
    cx.input_perf = .{};
    _ = cx.hitTest(150, 60);
    try std.testing.expectEqual(@as(u32, 1), cx.input_perf.in_hit_refresh_forced);
    // No mutation since that tick: further queries reuse the committed scene.
    _ = cx.hitTest(150, 60);
    _ = cx.hitTest(150, 100);
    try std.testing.expectEqual(@as(u32, 1), cx.input_perf.in_hit_refresh_forced);
    // A mutation re-runs the tick before the next query.
    rig.rows[1].markRenderDirty();
    _ = cx.hitTest(150, 60);
    try std.testing.expectEqual(@as(u32, 2), cx.input_perf.in_hit_refresh_forced);
    // Hit-index work is committed even without a mutation-driven tick: a layout change made by
    // the tick's own hooks is laid out and indexed in the same refresh.
    try HoverRig.settle(cx);
}

const HookMoveProbe = struct {
    var target: ?*Node = null;
    var want_y: f32 = 0;
    fn hook(node: *Node) void {
        _ = node;
        const t = target orelse return;
        if (t.style.translate_y != want_y) {
            t.style.translate_y = want_y;
            t.markCompositePropDirty();
        }
    }
};

test "Cx hit refresh: a handler's mutation reaches before-render hooks before the next hit" {
    // A hook that turns handler state into geometry (VirtualList rows, scrollbar thumb, sticky
    // offsets) must have run before the next event's hit test, as before.
    var rig: HitLayerRig = undefined;
    try rig.init();
    defer rig.deinit();
    const cx = rig.cx;
    const root = cx.root.?;
    const probe = try box(cx, .{ .position = .absolute, .width = .{ .px = 60 }, .height = .{ .px = 40 } }, .{});
    probe.behavior.events.on_event = HoverRig.observe;
    try root.appendChild(std.testing.allocator, probe);
    root.meta.per_frame.hooks.before_render.main = HookMoveProbe.hook;
    HookMoveProbe.target = probe;
    HookMoveProbe.want_y = 0;
    defer HookMoveProbe.target = null;
    try HoverRig.settle(cx);
    try std.testing.expectEqual(@as(?*Node, probe), cx.hitTest(30, 20));
    // "Handler": state change plus a dirty mark, as event handlers do.
    HookMoveProbe.want_y = 100;
    root.markRenderDirty();
    try std.testing.expectEqual(@as(?*Node, probe), cx.hitTest(30, 120));
    try std.testing.expect(cx.hitTest(30, 20) != probe);
}

test "LC3C ScrollArea border viewport maxScroll and resize use content insets" {
    var cx = try Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    const scope = try Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    const area = try ScrollArea(.{ .width = 300, .height = 200, .padding = Padding.all(10), .content_height = 1000, .content_width = 800 }).mount(scope, cx);
    cx.root = area.container;
    area.state.external_content_height = true;
    area.state.external_content_width = true;
    area.container.style.border = .{ .width = 5 };
    cx.layout();
    scrollbarBeforeRender(area.container);
    try std.testing.expectEqual(@as(f32, 170), area.state.viewport_height);
    try std.testing.expectEqual(@as(f32, 270), area.state.viewport_width);
    try std.testing.expectEqual(@as(f32, 830), area.state.maxScrollY());
    try std.testing.expectEqual(@as(f32, 530), area.state.maxScrollX());
    restorePersistOffset(area.container, 9999, 9999);
    try std.testing.expectEqual(@as(f32, 830), area.state.scroll_y);
    try std.testing.expectEqual(@as(f32, 530), area.state.scroll_x);
    area.container.style.border.overlay = true;
    area.container.markLayoutDirty();
    cx.layout();
    scrollbarBeforeRender(area.container);
    try std.testing.expectEqual(@as(f32, 820), area.state.maxScrollY());
    try std.testing.expectEqual(@as(f32, 520), area.state.maxScrollX());
    try std.testing.expectEqual(area.state.maxScrollY(), area.state.scroll_y);
    try std.testing.expectEqual(area.state.maxScrollX(), area.state.scroll_x);
}

test "ScrollArea: fit + max viewport follows wrapped text that shrinks or grows after a laid-out frame" {
    // A bounded details viewport (fit, max 150) around wrapped text. The text's stored layout
    // comes from the previous pass; measuring the fit size from it after a content change kept
    // the viewport at its old height (and the intrinsic cache kept it there on later frames).
    const t = std.testing;
    var ctx = try Cx.init(t.allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setViewport(600, 800);
    const root = try box(ctx, .{ .width = .{ .px = 572 }, .height = .fill(), .direction = .column }, .{});
    ctx.root = root;
    const scope = try Scope.init(t.allocator, null, ctx.owner);
    defer scope.dispose();
    const sa = try ScrollArea(.{ .direction = .vertical }).mount(scope, ctx);
    sa.container.setStyleInline(t.allocator, .{ .width = .fill(), .height = .{ .fit = .{ .max = 150 } }, .flex_shrink = 0 });
    try root.appendChild(t.allocator, sa.container);
    const long = "a\nb\nc\nd\ne\nf\ng\nh\ni\nj\nk\nl\nm\nn\no\np";
    const label = try core.text(ctx, long, .{ .font_size = 11, .wrap = .word, .line_height = 16.0 / 11.0 });
    try sa.content.appendChild(t.allocator, label);
    const settle = struct {
        fn run(c: *Cx) void {
            for (0..3) |_| {
                c.advanceFrameClock();
                c.layout();
                _ = c.render();
            }
        }
    }.run;
    settle(ctx);
    try t.expectApproxEqAbs(@as(f32, 150), sa.container.globalRect().h, 0.5);
    try label.setTextContent(t.allocator, "");
    settle(ctx);
    try t.expectApproxEqAbs(sa.content.globalRect().h, sa.container.globalRect().h, 0.5);
    try t.expect(sa.container.globalRect().h < 30);
    try label.setTextContent(t.allocator, long);
    settle(ctx);
    try t.expectApproxEqAbs(@as(f32, 150), sa.container.globalRect().h, 0.5);
}

// ---------- scroll_y / scroll_x bound to a source (offset_binding.zig) ----------

const OffsetEnv = struct {
    cx: *Cx,
    scope: *Scope,
    root: *Node,

    fn init() !OffsetEnv {
        const cx = try Cx.init(std.testing.allocator, std.testing.io);
        errdefer cx.deinit();
        cx.setViewport(400, 300);
        const root = try box(cx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
        cx.root = root;
        return .{ .cx = cx, .scope = try Scope.init(std.testing.allocator, null, cx.owner), .root = root };
    }

    fn deinit(self: OffsetEnv) void {
        self.scope.dispose();
        self.cx.deinit();
    }

    /// 300x200 area, ten 100px rows (content 1000, max offset 800), not yet attached.
    fn mountDetached(self: OffsetEnv, scope: *Scope, props: anytype) !ScrollAreaResult {
        const result = try ScrollArea(props).mount(scope, self.cx);
        for (0..10) |_| try result.content.appendChild(std.testing.allocator, try box(self.cx, .{ .width = .{ .grow = .{} }, .height = .{ .px = 100 } }, .{}));
        return result;
    }

    fn frame(self: OffsetEnv) void {
        const render_engine = @import("../../core/render_engine/mod.zig");
        render_engine.current_frame_time_ms += 16.0;
        render_engine.current_frame_dt_ms = 16.0;
        self.cx.frame_time_ms = render_engine.current_frame_time_ms;
        self.cx.layout();
        _ = self.cx.render();
    }
};

fn offsetProps(sig: *core.Signal(f32)) ScrollAreaProps {
    return @import("../../reactive.zig").props.coerce(ScrollAreaProps, .{ .width = 300, .height = 200, .scroll_y = sig });
}

test "ScrollArea scroll_y: an offset written before layout waits for it, then applies clamped (no after-layout hook)" {
    const env = try OffsetEnv.init();
    defer env.deinit();
    const y = try env.scope.createSignal(f32, 350);
    const r = try env.mountDetached(env.scope, offsetProps(y));
    // Not in the tree: no layout yet, so nothing is applied (no clamp against zero extents).
    env.frame();
    try std.testing.expectEqual(@as(f32, 0), testState(r).scroll_y);
    try std.testing.expectEqual(@as(f32, 350), y.peek());
    try env.root.appendChild(std.testing.allocator, r.container);
    env.frame();
    try std.testing.expectEqual(@as(f32, 350), testState(r).scroll_y);
    try std.testing.expectEqual(@as(f32, -350), r.content.style.translate_y);
    try std.testing.expectEqual(@as(f32, 350), y.peek());
    // Out of range: clamped to the maximum, and the source learns the clamped offset.
    y.set(5000);
    env.frame();
    try std.testing.expectEqual(@as(f32, 800), testState(r).scroll_y);
    try std.testing.expectEqual(@as(f32, 800), y.peek());
    y.set(-20);
    env.frame();
    try std.testing.expectEqual(@as(f32, 0), testState(r).scroll_y);
    try std.testing.expectEqual(@as(f32, 0), y.peek());
}

test "ScrollArea scroll_y: scrolling publishes the settled offset once per frame, never while resting" {
    const env = try OffsetEnv.init();
    defer env.deinit();
    const y = try env.scope.createSignal(f32, 0);
    const Counter = struct {
        runs: usize = 0,
        fn run(c: anytype) void {
            _ = c.y.get();
            c.self.runs += 1;
        }
    };
    var counter = Counter{};
    try env.scope.createEffect(.{ .y = y, .self = &counter }, Counter.run);
    const r = try env.mountDetached(env.scope, offsetProps(y));
    try env.root.appendChild(std.testing.allocator, r.container);
    env.frame();
    const base = counter.runs;
    // Three wheel events inside one frame: one publication.
    for (0..3) |_| _ = sendScroll(r, .{ .x = 150, .y = 100, .dx = 0, .dy = -40 });
    try std.testing.expectEqual(@as(f32, 0), y.peek());
    env.frame();
    try std.testing.expectEqual(testState(r).scroll_y, y.peek());
    try std.testing.expect(y.peek() > 0);
    try std.testing.expectEqual(base + 1, counter.runs);
    // Resting frames publish nothing.
    env.frame();
    env.frame();
    try std.testing.expectEqual(base + 1, counter.runs);
}

test "ScrollArea scroll_y: an offset scrolled after the last frame is reported when the area is torn down" {
    const a = std.testing.allocator;
    const cx = try Cx.init(a, std.testing.io);
    defer cx.deinit();
    cx.setViewport(300, 300);
    const parent = try Scope.init(a, null, cx.owner);
    defer parent.dispose();
    const kept = try parent.createSignal(f32, 0);
    const Saved = struct {
        value: f32 = -1,
        fn save(self: *@This(), v: f32) void {
            self.value = v;
        }
    };
    var saved: Saved = .{};
    cx.root = try box(cx, .{ .width = .{ .px = 300 }, .height = .{ .px = 300 }, .direction = .column }, .{});
    const scope = try parent.childScope();
    const area = try ScrollArea(.{ .height = 100, .scroll_y = kept, .on_scroll_y_change = cx.on(Saved, &saved, Saved.save) }).mount(scope, cx);
    try cx.root.?.appendChild(a, area.container);
    try area.content.appendChild(a, try box(cx, .{ .width = .{ .grow = .{} }, .height = .{ .px = 600 }, .flex_shrink = 0 }, .{}));
    for (0..3) |_| {
        cx.layout();
        _ = cx.render();
    }
    cx.handleScroll(.{ .x = 20, .y = 20, .dx = 0, .dy = -40 });
    for (0..2) |_| {
        cx.layout();
        _ = cx.render();
    }
    try std.testing.expectEqual(@as(f32, 40), kept.peek());
    // Scrolled again, then torn down before any frame: the last offset still reaches the owner.
    cx.handleScroll(.{ .x = 20, .y = 20, .dx = 0, .dy = -20 });
    try std.testing.expectEqual(@as(f32, 40), kept.peek());
    scope.dispose();
    cx.detachChild(cx.root.?, area.container);
    cx.destroyDetached(area.container);
    try std.testing.expectEqual(@as(f32, 60), kept.peek());
    try std.testing.expectEqual(@as(f32, 60), saved.value);
}

test "ScrollArea scroll_y: an outside write during momentum cancels it and wins over that frame's scrolling" {
    const env = try OffsetEnv.init();
    defer env.deinit();
    const y = try env.scope.createSignal(f32, 0);
    const r = try env.mountDetached(env.scope, offsetProps(y));
    try env.root.appendChild(std.testing.allocator, r.container);
    env.frame();
    _ = sendScroll(r, .{ .x = 150, .y = 100, .dx = 0, .dy = -60, .phase = .changed });
    _ = sendScroll(r, .{ .x = 150, .y = 100, .dx = 0, .dy = -60, .momentum = .changed });
    y.set(100);
    env.frame();
    const s = testState(r);
    try std.testing.expectEqual(@as(f32, 100), s.scroll_y);
    try std.testing.expect(!s.momentum_active and !s.touching);
    try std.testing.expectEqual(@as(f32, 0), s.bonus_y);
    try std.testing.expectEqual(@as(f32, 100), y.peek());
}

test "ScrollArea on_scroll_y_change: an area the wheel hands off scrolls out of view and still reports its offset" {
    const env = try OffsetEnv.init();
    defer env.deinit();
    const alloc = std.testing.allocator;
    const Reports = struct {
        last: ?f32 = null,
        fn report(self: *@This(), v: f32) void {
            self.last = v;
        }
    };
    var reports = Reports{};
    // Outer 300x200 area: a 400px block, then the inner 100px area (300px of content) in a
    // plain box of the page, the way a view places it.
    const outer = try ScrollArea(.{ .width = 300, .height = 200, .rubber_band_y = false }).mount(env.scope, env.cx);
    try env.root.appendChild(alloc, outer.container);
    try outer.content.appendChild(alloc, try box(env.cx, .{ .width = .{ .grow = .{} }, .height = .{ .px = 400 } }, .{}));
    const holder = try box(env.cx, .{ .width = .{ .grow = .{} }, .height = .{ .fit = .{} } }, .{});
    try outer.content.appendChild(alloc, holder);
    const inner = try ScrollArea(.{ .width = 300, .height = 100, .rubber_band_y = false, .on_scroll_y_change = env.cx.on(Reports, &reports, Reports.report) }).mount(env.scope, env.cx);
    try holder.appendChild(alloc, inner.container);
    try inner.content.appendChild(alloc, try box(env.cx, .{ .width = .{ .grow = .{} }, .height = .{ .px = 300 } }, .{}));
    env.frame();
    // Both at their ends: the inner area is in view and has reported its offset.
    setScrollY(testState(outer), outer.content, testState(outer).maxScrollY());
    env.frame();
    setScrollY(testState(inner), inner.content, testState(inner).maxScrollY());
    env.frame();
    try std.testing.expectEqual(@as(f32, 200), testState(inner).scroll_y);
    try std.testing.expectEqual(@as(?f32, 200), reports.last);
    // One wheel past the inner area's top: it settles at 0 and hands the event to the outer area,
    // which scrolls the inner one out of view in the same event.
    const r = inner.container.globalRect();
    env.cx.handleScroll(.{ .x = r.x + r.w / 2, .y = r.y + r.h / 2, .dx = 0, .dy = 1000 });
    try std.testing.expectEqual(@as(f32, 0), testState(inner).scroll_y);
    try std.testing.expectEqual(@as(f32, 0), testState(outer).scroll_y);
    // The next frame reports the settled offset although the area is off screen.
    env.frame();
    try std.testing.expectEqual(@as(?f32, 0), reports.last);
    // Resting off screen reports nothing new.
    reports.last = null;
    env.frame();
    try std.testing.expectEqual(@as(?f32, null), reports.last);
}

test "ScrollArea scroll_y: a view-model keeps one offset per page and a remounted page restores it (split, no handles)" {
    const env = try OffsetEnv.init();
    defer env.deinit();
    const Vm = struct {
        page: *core.Signal(usize),
        offsets: [2]*core.Signal(f32),
        reports: usize = 0,
        fn current(c: anytype) f32 {
            return c.vm.offsets[c.vm.page.get()].get();
        }
        fn remember(self: *@This(), v: f32) void {
            self.reports += 1;
            self.offsets[self.page.peek()].set(v);
        }
    };
    var vm = Vm{ .page = try env.scope.createSignal(usize, 0), .offsets = .{ try env.scope.createSignal(f32, 0), try env.scope.createSignal(f32, 0) } };
    const shown = try env.scope.createMemo(f32, .{ .vm = &vm }, Vm.current);

    const mountPage = struct {
        fn run(e: OffsetEnv, v: *Vm, src: anytype) !struct { scope: *Scope, r: ScrollAreaResult } {
            const page_scope = try e.scope.childScope();
            const r = try e.mountDetached(page_scope, .{ .width = 300, .height = 200, .scroll_y = src, .on_scroll_y_change = e.cx.on(Vm, v, Vm.remember) });
            try e.root.appendChild(std.testing.allocator, r.container);
            return .{ .scope = page_scope, .r = r };
        }
    }.run;
    const unmount = struct {
        fn run(e: OffsetEnv, p: anytype) void {
            e.cx.detachChild(e.root, p.r.container);
            p.scope.dispose();
            e.cx.destroyDetached(p.r.container);
        }
    }.run;

    var p = try mountPage(env, &vm, shown);
    env.frame();
    _ = sendScroll(p.r, .{ .x = 150, .y = 100, .dx = 0, .dy = -250 });
    env.frame();
    const remembered = testState(p.r).scroll_y;
    try std.testing.expect(remembered > 0);
    try std.testing.expectEqual(remembered, vm.offsets[0].peek());
    // Leave page 0 for page 1 (fresh offset 0), scroll it a little.
    unmount(env, p);
    vm.page.set(1);
    p = try mountPage(env, &vm, shown);
    env.frame();
    try std.testing.expectEqual(@as(f32, 0), testState(p.r).scroll_y);
    _ = sendScroll(p.r, .{ .x = 150, .y = 100, .dx = 0, .dy = -30 });
    env.frame();
    try std.testing.expectEqual(testState(p.r).scroll_y, vm.offsets[1].peek());
    // Back to page 0: the remounted area restores its offset in its first laid-out frame.
    unmount(env, p);
    vm.page.set(0);
    p = try mountPage(env, &vm, shown);
    const reports = vm.reports;
    env.frame();
    try std.testing.expectEqual(remembered, testState(p.r).scroll_y);
    try std.testing.expectEqual(-remembered, p.r.content.style.translate_y);
    // Restoring is not a user scroll: the view-model is not written back.
    try std.testing.expectEqual(reports, vm.reports);
    try std.testing.expectEqual(remembered, vm.offsets[0].peek());
    unmount(env, p);
}

test "ScrollArea scroll_y: default props create no binding; a read-only source only follows" {
    const env = try OffsetEnv.init();
    defer env.deinit();
    const plain = try env.mountDetached(env.scope, .{ .width = 300, .height = 200 });
    const plain_ctx: *ScrollEventCtx = @ptrCast(@alignCast(plain.container.behavior.events.event_context.?));
    try std.testing.expect(plain_ctx.offset_binding == null);
    env.cx.freeNode(plain.container);

    const src = try env.scope.createSignal(f32, 0);
    const doubled = try env.scope.createMemo(f32, .{ .s = src }, struct {
        fn f(c: anytype) f32 {
            return c.s.get() * 2;
        }
    }.f);
    const r = try env.mountDetached(env.scope, .{ .width = 300, .height = 200, .scroll_y = doubled });
    try env.root.appendChild(std.testing.allocator, r.container);
    env.frame();
    src.set(60);
    env.frame();
    try std.testing.expectEqual(@as(f32, 120), testState(r).scroll_y);
    _ = sendScroll(r, .{ .x = 150, .y = 100, .dx = 0, .dy = -40 });
    env.frame();
    try std.testing.expect(testState(r).scroll_y > 120);
    try std.testing.expectEqual(@as(f32, 60), src.peek());
}

test "ScrollArea: a horizontal area sizes its content to the content's width and scrolls it by wheel" {
    // A strip of fixed-width tiles inside a horizontal area (no content_width prop): the content
    // column takes the row's width, not the viewport's, so the overflow is scrollable.
    var cx = try Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    cx.setViewport(400, 300);
    try cx.setTestFrameStep(16);
    cx.caret_flip_host = true;
    const scope = try Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    const root = try box(cx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 }, .direction = .column }, .{});
    cx.root = root;
    const area = try ScrollArea(.{ .direction = .horizontal, .rubber_band_x = false }).mount(scope, cx);
    area.container.style.width = .{ .px = 200 };
    area.container.style.height = .{ .px = 40 };
    try root.appendChild(std.testing.allocator, area.container);
    const strip = try box(cx, .{ .width = .{ .fit = .{} }, .height = .{ .px = 40 }, .direction = .row, .gap = 8 }, .{});
    try area.content.appendChild(std.testing.allocator, strip);
    for (0..8) |_| try strip.appendChild(std.testing.allocator, try box(cx, .{ .width = .{ .px = 150 }, .height = .{ .px = 40 }, .flex_shrink = 0 }, .{}));
    try HoverRig.settle(cx);
    const want: f32 = 8 * 150 + 7 * 8;
    try std.testing.expectApproxEqAbs(want, area.content.globalRect().w, 0.5);
    try std.testing.expectApproxEqAbs(want, area.state.content_width, 0.5);
    cx.handleScroll(.{ .x = 100, .y = 20, .dx = -120, .dy = 0 });
    try HoverRig.settle(cx);
    try std.testing.expectEqual(@as(f32, 120), area.state.scroll_x);
    try std.testing.expectEqual(@as(f32, -120), area.content.style.translate_x);
}

test "ScrollArea: a layout resize neither reveals the bar nor leaves a shown thumb at the old edge" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const result = try mountTestScrollArea(ctx, scope);
    const state = testState(result);
    for (0..3) |_| scrollbarBeforeRender(result.container);
    // Resizing the viewport by layout is not scroll activity: a hidden bar stays hidden.
    result.container.setWidth(240);
    ctx.layout();
    for (0..3) |_| scrollbarBeforeRender(result.container);
    try std.testing.expectEqual(@as(f32, 0), state.scrollbar_fade.opacity);
    // A bar that is shown (activity) follows the new edge as soon as the hook sees the layout.
    state.onScrollActivity();
    result.container.setWidth(280);
    ctx.layout();
    scrollbarBeforeRender(result.container);
    const ev_ctx: *ScrollEventCtx = @ptrCast(@alignCast(result.container.behavior.events.event_context.?));
    const bar = ev_ctx.scrollbar.?.rectFromWorldOrFallback();
    try std.testing.expectApproxEqAbs(@as(f32, 280 - 2), bar.x + bar.w, 0.01);
}

// ---- overscroll_y = .contain (nested scrolling at the edges) and scrollbars = .always ----

/// An outer page (400 high, 1000 of filler) holding a 150-high inner body with `content_height`
/// of its own content, `overscroll_y = .contain`; the pointer rests at (30, 50) over the body.
const ContainRig = struct {
    cx: *Cx,
    scope: *Scope,
    outer: ScrollAreaResult,
    inner: ScrollAreaResult,
    body: *Node,

    fn init(content_height: f32, overscroll: OverscrollBehavior) !ContainRig {
        const cx = try Cx.init(std.testing.allocator, std.testing.io);
        errdefer cx.deinit();
        cx.setViewport(460, 400);
        try cx.setTestFrameStep(16);
        const scope = try Scope.init(std.testing.allocator, null, cx.owner);
        errdefer scope.dispose();
        cx.root = try box(cx, .{ .width = .{ .grow = .{} }, .height = .{ .grow = .{} }, .direction = .column }, .{});
        const outer = try ScrollArea(.{ .height = 400 }).mount(scope, cx);
        try cx.root.?.appendChild(std.testing.allocator, outer.container);
        const inner = try ScrollArea(.{ .width = 360, .height = 150, .overscroll_y = overscroll }).mount(scope, cx);
        inner.container.setStyleInline(std.testing.allocator, .{ .flex_shrink = 0 });
        try outer.content.appendChild(std.testing.allocator, inner.container);
        const body = try box(cx, .{ .width = .{ .grow = .{} }, .height = .{ .px = content_height }, .flex_shrink = 0 }, .{});
        try inner.content.appendChild(std.testing.allocator, body);
        try outer.content.appendChild(std.testing.allocator, try box(cx, .{ .width = .{ .grow = .{} }, .height = .{ .px = 1000 }, .flex_shrink = 0 }, .{}));
        var rig = ContainRig{ .cx = cx, .scope = scope, .outer = outer, .inner = inner, .body = body };
        rig.settle();
        return rig;
    }
    fn settle(rig: *ContainRig) void {
        for (0..3) |_| {
            rig.cx.advanceFrameClock();
            rig.cx.layout();
            _ = rig.cx.render();
        }
    }
    fn send(rig: *ContainRig, dx: f32, dy: f32, phase: @import("../../events.zig").ScrollPhase, momentum: @import("../../events.zig").MomentumPhase) void {
        rig.cx.handleScroll(.{ .x = 30, .y = 50, .dx = dx, .dy = dy, .phase = phase, .momentum = momentum });
        rig.settle();
    }
    fn deinit(rig: *ContainRig) void {
        rig.scope.dispose();
        rig.cx.deinit();
    }
};

test "ScrollArea overscroll_y: .auto chains a wheel at the edge on to the enclosing area, .contain keeps it" {
    {
        var rig = try ContainRig.init(650, .auto);
        defer rig.deinit();
        rig.send(0, -35, .none, .none);
        try std.testing.expectEqual(@as(f32, 35), rig.inner.state.scroll_y);
        // A wheel that would carry the body past its end goes on to the page.
        rig.send(0, -10000, .none, .none);
        try std.testing.expectEqual(rig.inner.state.maxScrollY(), rig.inner.state.scroll_y);
        try std.testing.expect(rig.outer.state.scroll_y > 0);
    }
    var rig = try ContainRig.init(650, .contain);
    defer rig.deinit();
    rig.send(0, -35, .none, .none);
    try std.testing.expectEqual(@as(f32, 35), rig.inner.state.scroll_y);
    try std.testing.expectEqual(@as(f32, 0), rig.outer.state.scroll_y);
    // A delta that crosses the edge is applied once, clamped; the rest goes nowhere.
    rig.send(0, -10000, .none, .none);
    try std.testing.expectEqual(rig.inner.state.maxScrollY(), rig.inner.state.scroll_y);
    try std.testing.expectEqual(@as(f32, 0), rig.outer.state.scroll_y);
    rig.send(0, -30, .none, .none);
    try std.testing.expectEqual(@as(f32, 0), rig.outer.state.scroll_y);
    rig.send(0, 10000, .none, .none);
    rig.send(0, 30, .none, .none);
    try std.testing.expectEqual(@as(f32, 0), rig.inner.state.scroll_y);
    try std.testing.expectEqual(@as(f32, 0), rig.outer.state.scroll_y);
    // Input outside the contained area still scrolls the page.
    rig.cx.handleScroll(.{ .x = 430, .y = 50, .dx = 0, .dy = -45 });
    rig.settle();
    try std.testing.expectEqual(@as(f32, 45), rig.outer.state.scroll_y);
}

test "ScrollArea overscroll_y .contain: a gesture and its momentum rubber-band at both edges without moving the page" {
    var rig = try ContainRig.init(650, .contain);
    defer rig.deinit();
    rig.send(0, 0, .may_begin, .none);
    rig.send(0, -35, .began, .none);
    rig.send(0, -1000, .changed, .none);
    rig.send(0, -40, .changed, .none);
    try std.testing.expect(rig.inner.state.bonus_y > 0);
    try std.testing.expectEqual(@as(f32, 0), rig.outer.state.scroll_y);
    rig.send(0, 0, .ended, .none);
    rig.send(0, -30, .none, .began);
    rig.send(0, -15, .none, .changed);
    rig.send(0, 0, .none, .ended);
    try std.testing.expect(!rig.inner.state.touching and !rig.inner.state.latched and !rig.inner.state.momentum_active);
    try std.testing.expectEqual(@as(f32, 0), rig.outer.state.scroll_y);
    // The top edge (after the bottom spring settled): a fresh gesture pulling down from the top
    // rubber-bands too.
    for (0..60) |_| rig.settle();
    try std.testing.expectEqual(@as(f32, 0), rig.inner.state.bonus_y);
    rig.send(0, 10000, .none, .none);
    rig.send(0, 0, .may_begin, .none);
    rig.send(0, 40, .began, .none);
    rig.send(0, 50, .changed, .none);
    try std.testing.expect(rig.inner.state.bonus_y < 0);
    rig.send(0, 0, .cancelled, .none);
    for (0..60) |_| rig.settle();
    try std.testing.expectEqual(@as(f32, 0), rig.inner.state.scroll_y);
    try std.testing.expectEqual(@as(f32, 0), rig.inner.state.bonus_y);
    try std.testing.expectEqual(@as(f32, 0), rig.outer.state.scroll_y);
}

test "ScrollArea overscroll_y .contain: a body with nothing to scroll, and horizontal input, still reach the page" {
    var short = try ContainRig.init(60, .contain);
    defer short.deinit();
    short.send(0, -35, .none, .none);
    try std.testing.expectEqual(@as(f32, 0), short.inner.state.scroll_y);
    try std.testing.expectEqual(@as(f32, 35), short.outer.state.scroll_y);
    short.send(0, -35, .began, .none);
    short.send(0, -35, .changed, .none);
    short.send(0, 0, .ended, .none);
    try std.testing.expectEqual(@as(f32, 105), short.outer.state.scroll_y);
    // Growing content makes the same body contain again.
    short.body.setStyleInline(std.testing.allocator, .{ .height = .{ .px = 650 } });
    short.settle();
    // (The page moved the body up by 105: aim at what is left of it on screen.)
    short.cx.handleScroll(.{ .x = 30, .y = 20, .dx = 0, .dy = 10000 });
    short.settle();
    try std.testing.expectEqual(@as(f32, 0), short.inner.state.scroll_y);
    try std.testing.expectEqual(@as(f32, 105), short.outer.state.scroll_y);

    // A horizontal strip inside the contained body: horizontal input scrolls the strip, vertical
    // input over it is the body's (and stays there at the body's edges).
    var rig = try ContainRig.init(650, .contain);
    defer rig.deinit();
    const strip = try ScrollArea(.{ .height = 60, .direction = .horizontal, .rubber_band_x = false }).mount(rig.scope, rig.cx);
    strip.container.setStyleInline(std.testing.allocator, .{ .position = .absolute, .inset = .{ .top = .{ .px = 0 }, .left = .{ .px = 0 } }, .width = .{ .px = 340 } });
    strip.content.setStyleInline(std.testing.allocator, .{ .width = .{ .px = 1000 }, .height = .{ .px = 60 } });
    try rig.inner.content.appendChild(std.testing.allocator, strip.container);
    rig.settle();
    rig.send(-35, 0, .none, .none);
    try std.testing.expectEqual(@as(f32, 35), strip.state.scroll_x);
    try std.testing.expectEqual(@as(f32, 0), rig.inner.state.scroll_y);
    rig.send(0, -35, .none, .none);
    try std.testing.expectEqual(@as(f32, 35), rig.inner.state.scroll_y);
    rig.send(0, 35, .none, .none);
    rig.send(0, 35, .none, .none);
    try std.testing.expectEqual(@as(f32, 0), rig.inner.state.scroll_y);
    try std.testing.expectEqual(@as(f32, 0), rig.outer.state.scroll_y);
}

test "ScrollArea overscroll_y .contain: the deepest overflowing area takes each delta once and keeps its gesture" {
    var rig = try ContainRig.init(650, .contain);
    defer rig.deinit();
    const deepest = try ScrollArea(.{ .height = 60, .overscroll_y = .contain }).mount(rig.scope, rig.cx);
    deepest.container.setStyleInline(std.testing.allocator, .{ .position = .absolute, .width = .{ .px = 340 }, .inset = .{ .top = .{ .px = 0 } } });
    const long_content = try box(rig.cx, .{ .width = .{ .grow = .{} }, .height = .{ .px = 240 }, .flex_shrink = 0 }, .{});
    try deepest.content.appendChild(std.testing.allocator, long_content);
    try rig.inner.content.appendChild(std.testing.allocator, deepest.container);
    rig.settle();
    rig.send(0, -170, .none, .none);
    try std.testing.expectEqual(@as(f32, 170), deepest.state.scroll_y);
    rig.send(0, -25, .none, .none);
    try std.testing.expectEqual(deepest.state.maxScrollY(), deepest.state.scroll_y);
    try std.testing.expectEqual(@as(f32, 0), deepest.state.bonus_y);
    rig.send(0, -30, .none, .none);
    try std.testing.expectEqual(@as(f32, 0), rig.inner.state.scroll_y);
    try std.testing.expectEqual(@as(f32, 0), rig.outer.state.scroll_y);
    rig.send(0, 170, .none, .none);
    rig.send(0, 0, .may_begin, .none);
    rig.send(0, 0, .began, .none);
    rig.send(0, -5, .changed, .none);
    try std.testing.expectEqual(@as(f32, 15), deepest.state.scroll_y);
    try std.testing.expectEqual(@as(f32, 0), rig.inner.state.scroll_y);
    // The pointer leaves the deepest area, the gesture stays with it (session owner).
    rig.cx.handleScroll(.{ .x = 350, .y = 100, .dx = 0, .dy = -5, .phase = .changed });
    rig.settle();
    try std.testing.expectEqual(@as(f32, 20), deepest.state.scroll_y);
    rig.send(0, -200, .changed, .none);
    try std.testing.expect(deepest.state.bonus_y > 0);
    try std.testing.expect(deepest.state.bonus_y < 25); // only the 40pt past the edge overshoots
    rig.send(0, 0, .ended, .none);
    rig.send(0, -20, .none, .began);
    rig.send(0, 0, .none, .ended);
    try std.testing.expectEqual(@as(f32, 0), rig.inner.state.scroll_y);
    try std.testing.expectEqual(@as(f32, 0), rig.outer.state.scroll_y);
    // Shrunk below its viewport (and its rebound settled: while it still bounces it owns the
    // input), the deepest area lets the body scroll.
    long_content.setStyleInline(std.testing.allocator, .{ .height = .{ .px = 30 } });
    for (0..60) |_| rig.settle();
    try std.testing.expectEqual(@as(f32, 0), deepest.state.bonus_y);
    rig.send(0, -35, .none, .none);
    try std.testing.expectEqual(@as(f32, 35), rig.inner.state.scroll_y);
    try std.testing.expectEqual(@as(f32, 0), rig.outer.state.scroll_y);
}

test "ScrollArea scrollbars .always: an overflowing axis keeps its thumb at rest, nothing is shown without overflow" {
    var rig = try ContainRig.init(650, .auto);
    defer rig.deinit();
    const always = try ScrollArea(.{ .width = 300, .height = 100, .scrollbars = .always }).mount(rig.scope, rig.cx);
    always.container.setStyleInline(std.testing.allocator, .{ .flex_shrink = 0 });
    const filler = try box(rig.cx, .{ .width = .{ .grow = .{} }, .height = .{ .px = 400 }, .flex_shrink = 0 }, .{});
    try always.content.appendChild(std.testing.allocator, filler);
    try rig.outer.content.insertChildBefore(std.testing.allocator, always.container, rig.outer.content.children.items[0]);
    rig.settle();
    for (0..240) |_| {
        rig.cx.advanceFrameClock();
        rig.cx.root.?.markRenderDirty();
        _ = rig.cx.render();
    }
    const thumb = (try scrollEventCtxOf(always.container)).scrollbar.?;
    try std.testing.expect(thumb.rectFromWorldOrFallback().w > 0);
    try std.testing.expect(thumb.getBackground().a > 0);
    // The plain (auto) areas never scrolled: no thumb at rest.
    try std.testing.expectEqual(@as(f32, 0), rig.inner.state.scrollbar_fade.opacity);
    try std.testing.expectEqual(@as(f32, 0), rig.outer.state.scrollbar_fade.opacity);
    // A frame at rest is idle (the persistent thumb asks for no frames of its own).
    try std.testing.expect(!always.state.tickScrollbar());
    // Content that no longer overflows: no thumb.
    filler.setStyleInline(std.testing.allocator, .{ .height = .{ .px = 40 } });
    rig.settle();
    try std.testing.expectEqual(@as(f32, 0), thumb.rectFromWorldOrFallback().w);
    try std.testing.expectEqual(@as(f32, 0), thumb.rectFromWorldOrFallback().h);
    // A horizontal area keeps its horizontal thumb.
    const strip = try ScrollArea(.{ .height = 40, .direction = .horizontal, .scrollbars = .always }).mount(rig.scope, rig.cx);
    strip.container.setStyleInline(std.testing.allocator, .{ .width = .{ .px = 200 }, .flex_shrink = 0 });
    strip.content.setStyleInline(std.testing.allocator, .{ .width = .{ .px = 900 }, .height = .{ .px = 40 } });
    try rig.outer.content.insertChildBefore(std.testing.allocator, strip.container, rig.outer.content.children.items[0]);
    rig.settle();
    for (0..240) |_| {
        rig.cx.advanceFrameClock();
        rig.cx.root.?.markRenderDirty();
        _ = rig.cx.render();
    }
    const thumb_h = (try scrollEventCtxOf(strip.container)).scrollbar_h.?;
    try std.testing.expect(thumb_h.rectFromWorldOrFallback().h > 0);
    try std.testing.expect(thumb_h.getBackground().a > 0);
}

fn scrollEventCtxOf(container: *Node) !*const ScrollEventCtx {
    if (container.behavior.events.on_event != scrollEventHandler) return error.NotAScrollArea;
    return @ptrCast(@alignCast(container.behavior.events.event_context.?));
}

/// A page (400 high) with 200 of header, a 150-high contained card scrolled to its end, then
/// 1000 of filler. The pointer rests at (30, 250) over the card's lower part... or at (30, 150)
/// over the header, which the card slides under as the page scrolls.
const SlideRig = struct {
    rig: ContainRig,

    fn init() !SlideRig {
        var rig = try ContainRig.init(650, .contain);
        const header = try box(rig.cx, .{ .width = .{ .grow = .{} }, .height = .{ .px = 200 }, .flex_shrink = 0 }, .{});
        try rig.outer.content.insertChildBefore(std.testing.allocator, header, rig.inner.container);
        rig.settle();
        setScrollY(rig.inner.state, rig.inner.content, 10000);
        rig.settle();
        return .{ .rig = rig };
    }
    fn deinit(self: *SlideRig) void {
        self.rig.deinit();
    }
    fn wheel(self: *SlideRig, x: f32, y: f32, dy: f32) void {
        self.rig.cx.handleScroll(.{ .x = x, .y = y, .dx = 0, .dy = dy });
        self.rig.settle();
    }
};

test "ScrollArea wheel transaction: a page scrolled by wheel keeps scrolling when a contained card slides under the resting pointer" {
    var s = try SlideRig.init();
    defer s.deinit();
    const r = &s.rig;
    try std.testing.expectEqual(r.inner.state.maxScrollY(), r.inner.state.scroll_y);
    // Over the header: the page scrolls; from the second notch on the card is under the pointer.
    s.wheel(30, 150, -60);
    try std.testing.expectEqual(@as(f32, 60), r.outer.state.scroll_y);
    try std.testing.expect(r.inner.container.globalRect().contains(30, 150));
    s.wheel(30, 150, -60);
    s.wheel(30, 150, -60);
    try std.testing.expectEqual(@as(f32, 180), r.outer.state.scroll_y);
    // The pointer moves (a new transaction): the card under it now takes the wheel and, contained
    // at its end, keeps the page where it is.
    s.wheel(31, 160, -60);
    try std.testing.expectEqual(@as(f32, 180), r.outer.state.scroll_y);
    // A reversed direction is a new transaction too: the card scrolls up.
    s.wheel(31, 160, 30);
    try std.testing.expectEqual(r.inner.state.maxScrollY() - 30, r.inner.state.scroll_y);
    try std.testing.expectEqual(@as(f32, 180), r.outer.state.scroll_y);
}

test "ScrollArea wheel transaction: content sliding under a fixed overlay (wheel-transparent or not) does not take the page's wheel" {
    for ([_]bool{ true, false }) |transparent| {
        var s = try SlideRig.init();
        defer s.deinit();
        const r = &s.rig;
        // A fixed 40 x 40 node over the resting pointer, outside the scrolled content (a floating
        // button, a resize strip): the pointer leaf stays the same while the content slides.
        const overlay = try box(r.cx, .{ .position = .absolute, .inset = .{ .left = .{ .px = 10 }, .top = .{ .px = 130 } }, .width = .{ .px = 40 }, .height = .{ .px = 40 } }, .{});
        // A pointer handler makes it a pointer hit (its own clicks), not a scroll owner.
        overlay.behavior.events.on_event = struct {
            fn f(_: @import("../../events.zig").Event, _: ?*anyopaque) @import("../../events.zig").EventResult {
                return .ignored;
            }
        }.f;
        overlay.setWheelTransparent(transparent);
        try r.cx.root.?.appendChild(std.testing.allocator, overlay);
        r.settle();
        s.wheel(30, 150, -60);
        try std.testing.expectEqual(@as(f32, 60), r.outer.state.scroll_y);
        try std.testing.expect(r.inner.container.globalRect().contains(30, 150));
        s.wheel(30, 150, -60);
        s.wheel(30, 150, -60);
        try std.testing.expectEqual(@as(f32, 180), r.outer.state.scroll_y);
        try std.testing.expectEqual(r.inner.state.maxScrollY(), r.inner.state.scroll_y);
    }
}

test "ScrollArea wheel transaction: without latching (or after the gap) each notch goes to what is under the pointer" {
    var s = try SlideRig.init();
    defer s.deinit();
    const r = &s.rig;
    r.cx.dispatcher.wheel_latch_ns = 0;
    s.wheel(30, 150, -60);
    try std.testing.expectEqual(@as(f32, 60), r.outer.state.scroll_y);
    s.wheel(30, 150, -60);
    try std.testing.expectEqual(@as(f32, 60), r.outer.state.scroll_y);
}

test "ScrollArea: a trackpad gesture starting while the page's momentum still moves goes to the page, not the card that slid under" {
    var s = try SlideRig.init();
    defer s.deinit();
    const r = &s.rig;
    const at = struct {
        fn send(rig: *ContainRig, dy: f32, phase: @import("../../events.zig").ScrollPhase, momentum: @import("../../events.zig").MomentumPhase) void {
            rig.cx.handleScroll(.{ .x = 30, .y = 150, .dx = 0, .dy = dy, .phase = phase, .momentum = momentum });
            rig.settle();
        }
    }.send;
    at(r, 0, .may_begin, .none);
    at(r, -40, .began, .none);
    at(r, -20, .changed, .none);
    at(r, 0, .ended, .none);
    at(r, -30, .none, .began);
    at(r, -20, .none, .changed);
    const page_before = r.outer.state.scroll_y;
    try std.testing.expect(page_before >= 60);
    try std.testing.expect(r.inner.container.globalRect().contains(30, 150));
    // A new flick right away (the page is still moving): the page takes it.
    at(r, 0, .may_begin, .none);
    at(r, -40, .began, .none);
    at(r, -20, .changed, .none);
    at(r, 0, .ended, .none);
    try std.testing.expect(r.outer.state.scroll_y > page_before);
    try std.testing.expectEqual(r.inner.state.maxScrollY(), r.inner.state.scroll_y);
    // Once the page has come to rest (window elapsed), a gesture over the card is the card's.
    r.cx.dispatcher.moving_window_ns = 0;
    const page_rest = r.outer.state.scroll_y;
    at(r, 0, .may_begin, .none);
    at(r, 40, .began, .none);
    at(r, 0, .ended, .none);
    try std.testing.expectEqual(page_rest, r.outer.state.scroll_y);
    try std.testing.expect(r.inner.state.scroll_y < r.inner.state.maxScrollY());
}

test "ScrollArea: fingers that touch during the page's momentum and rest before moving keep the gesture on the page" {
    var s = try SlideRig.init();
    defer s.deinit();
    const r = &s.rig;
    const at = struct {
        fn send(rig: *ContainRig, dy: f32, phase: @import("../../events.zig").ScrollPhase, momentum: @import("../../events.zig").MomentumPhase) void {
            rig.cx.handleScroll(.{ .x = 30, .y = 150, .dx = 0, .dy = dy, .phase = phase, .momentum = momentum });
            rig.settle();
        }
    }.send;
    at(r, 0, .may_begin, .none);
    at(r, -40, .began, .none);
    at(r, -20, .changed, .none);
    at(r, 0, .ended, .none);
    at(r, -30, .none, .began);
    at(r, -20, .none, .changed);
    const page_before = r.outer.state.scroll_y;
    try std.testing.expect(r.inner.container.globalRect().contains(30, 150));
    // Touch while the page still moves (may_begin: the page catches it) ...
    at(r, 0, .may_begin, .none);
    // ... and the fingers rest past the moving window before they move (began): still the page's.
    r.cx.dispatcher.moving_window_ns = 0;
    at(r, -40, .began, .none);
    at(r, -20, .changed, .none);
    at(r, 0, .ended, .none);
    try std.testing.expect(r.outer.state.scroll_y > page_before);
    try std.testing.expectEqual(r.inner.state.maxScrollY(), r.inner.state.scroll_y);
}

test "ScrollArea overscroll_x .contain: horizontal edges, and per-axis containment in a .both area" {
    const cx = try Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    cx.setViewport(400, 300);
    try cx.setTestFrameStep(16);
    const scope = try Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    cx.root = try box(cx, .{ .width = .{ .grow = .{} }, .height = .{ .grow = .{} }, .direction = .column }, .{});
    const outer = try ScrollArea(.{ .height = 300, .direction = .both }).mount(scope, cx);
    try cx.root.?.appendChild(std.testing.allocator, outer.container);
    const wide = try box(cx, .{ .width = .{ .px = 2000 }, .height = .{ .px = 1000 }, .flex_shrink = 0, .direction = .column }, .{});
    try outer.content.appendChild(std.testing.allocator, wide);
    const strip = try ScrollArea(.{ .width = 200, .height = 100, .direction = .both, .overscroll_x = .contain }).mount(scope, cx);
    strip.container.setStyleInline(std.testing.allocator, .{ .flex_shrink = 0 });
    try wide.appendChild(std.testing.allocator, strip.container);
    try strip.content.appendChild(std.testing.allocator, try box(cx, .{ .width = .{ .px = 500 }, .height = .{ .px = 300 }, .flex_shrink = 0 }, .{}));
    for (0..3) |_| {
        cx.advanceFrameClock();
        cx.layout();
        _ = cx.render();
    }
    const send = struct {
        fn f(c: *Cx, dx: f32, dy: f32) void {
            c.handleScroll(.{ .x = 50, .y = 50, .dx = dx, .dy = dy });
            for (0..3) |_| {
                c.advanceFrameClock();
                c.layout();
                _ = c.render();
            }
        }
    }.f;
    // Each notch on its own (no wheel transaction across the asserts below).
    cx.dispatcher.wheel_latch_ns = 0;
    // Right edge: horizontal input stays in the strip (contained on x).
    send(cx, -10000, 0);
    try std.testing.expectEqual(strip.state.maxScrollX(), strip.state.scroll_x);
    send(cx, -40, 0);
    try std.testing.expectEqual(@as(f32, 0), outer.state.scroll_x);
    // Left edge too.
    send(cx, 10000, 0);
    send(cx, 40, 0);
    try std.testing.expectEqual(@as(f32, 0), strip.state.scroll_x);
    try std.testing.expectEqual(@as(f32, 0), outer.state.scroll_x);
    // y is .auto: past the strip's bottom the page scrolls.
    send(cx, 0, -10000);
    try std.testing.expectEqual(strip.state.maxScrollY(), strip.state.scroll_y);
    try std.testing.expect(outer.state.scroll_y > 0);
}

test "ScrollArea overscroll_y .contain with rubber_band_y = false (CSS none): a gesture stops at the edge without bounce or chaining" {
    const cx = try Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    cx.setViewport(460, 400);
    try cx.setTestFrameStep(16);
    const scope = try Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    cx.root = try box(cx, .{ .width = .{ .grow = .{} }, .height = .{ .grow = .{} }, .direction = .column }, .{});
    const outer = try ScrollArea(.{ .height = 400 }).mount(scope, cx);
    try cx.root.?.appendChild(std.testing.allocator, outer.container);
    const inner = try ScrollArea(.{ .width = 360, .height = 150, .overscroll_y = .contain, .rubber_band_y = false }).mount(scope, cx);
    inner.container.setStyleInline(std.testing.allocator, .{ .flex_shrink = 0 });
    try outer.content.appendChild(std.testing.allocator, inner.container);
    try inner.content.appendChild(std.testing.allocator, try box(cx, .{ .width = .{ .grow = .{} }, .height = .{ .px = 650 }, .flex_shrink = 0 }, .{}));
    try outer.content.appendChild(std.testing.allocator, try box(cx, .{ .width = .{ .grow = .{} }, .height = .{ .px = 1000 }, .flex_shrink = 0 }, .{}));
    const settle = struct {
        fn f(c: *Cx) void {
            for (0..3) |_| {
                c.advanceFrameClock();
                c.layout();
                _ = c.render();
            }
        }
    }.f;
    settle(cx);
    for ([_]@import("../../events.zig").ScrollPhase{ .may_begin, .began, .changed, .changed }, [_]f32{ 0, -100, -1000, -60 }) |phase, dy| {
        cx.handleScroll(.{ .x = 30, .y = 50, .dx = 0, .dy = dy, .phase = phase });
        settle(cx);
    }
    try std.testing.expectEqual(inner.state.maxScrollY(), inner.state.scroll_y);
    try std.testing.expectEqual(@as(f32, 0), inner.state.bonus_y);
    try std.testing.expectEqual(@as(f32, 0), outer.state.scroll_y);
}

test "ScrollArea scrollbars .always: a resting area asks for no frame, and hover fades back to the rest look, not out" {
    const cx = try Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    cx.setViewport(400, 300);
    try cx.setTestFrameStep(16);
    const scope = try Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    cx.root = try box(cx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    const area = try ScrollArea(.{ .width = 300, .height = 100, .scrollbars = .always }).mount(scope, cx);
    try cx.root.?.appendChild(std.testing.allocator, area.container);
    try area.content.appendChild(std.testing.allocator, try box(cx, .{ .width = .{ .grow = .{} }, .height = .{ .px = 400 }, .flex_shrink = 0 }, .{}));
    for (0..10) |_| {
        cx.advanceFrameClock();
        cx.layout();
        _ = cx.render();
    }
    // At rest: rendering a frame leaves nothing dirty (no self-scheduled redraw).
    cx.needs_redraw = false;
    cx.advanceFrameClock();
    cx.layout();
    _ = cx.render();
    try std.testing.expect(!cx.needs_redraw);
    try std.testing.expect(!area.container.frame_state.state_bits.dirty.core.render);
    try std.testing.expectEqual(area.state.scrollbar_fade.active_opacity, area.state.scrollbar_fade.opacity);
    // Hover over the bar, then leave: back to the rest look, not faded out.
    const bar = area.container.globalRect();
    cx.handleMouseMove(bar.x + bar.w - 3, bar.y + 20);
    for (0..3) |_| {
        cx.advanceFrameClock();
        cx.layout();
        _ = cx.render();
    }
    try std.testing.expectEqual(@as(f32, 1), area.state.scrollbar_fade.opacity);
    cx.handleMouseMove(390, 290);
    // (The fade hold counts rendered frames: keep frames coming as the window would.)
    for (0..300) |_| {
        cx.advanceFrameClock();
        cx.root.?.markRenderDirty();
        cx.layout();
        _ = cx.render();
    }
    try std.testing.expectEqual(area.state.scrollbar_fade.active_opacity, area.state.scrollbar_fade.opacity);
}

test "ScrollArea hit layer: an inner area taller than its outer area's viewport hits only inside that viewport" {
    var cx = try Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    cx.setViewport(400, 600);
    try cx.setTestFrameStep(16);
    cx.caret_flip_host = true;
    const scope = try Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    const root = try box(cx, .{ .width = .{ .px = 400 }, .height = .{ .px = 600 }, .direction = .column }, .{});
    cx.root = root;
    // Outer viewport y 0..150; the inner area is 760 tall, so it overflows that viewport by 610.
    const outer = try ScrollArea(.{ .direction = .vertical, .width = 300, .height = 150 }).mount(scope, cx);
    try root.appendChild(std.testing.allocator, outer.container);
    const inner = try ScrollArea(.{ .direction = .both, .width = 300, .height = 760 }).mount(scope, cx);
    try outer.content.appendChild(std.testing.allocator, inner.container);
    var rows: [40]*Node = undefined;
    try HoverRig.rows(cx, inner.content, &rows, 30);
    // A control below the outer area, where the inner area would be without the outer clip.
    var below: [1]*Node = undefined;
    try HoverRig.rows(cx, root, &below, 40);
    try HoverRig.settle(cx);
    try std.testing.expectApproxEqAbs(@as(f32, 150), below[0].globalRect().y, 0.5);
    try std.testing.expectEqual(@as(?usize, 2), HoverRig.indexOf(&rows, cx.hitTest(150, 75)));
    try std.testing.expectEqual(@as(?*Node, below[0]), cx.hitTest(150, 170));
    // Scrolled outer area: still clipped to its own viewport.
    setScrollY(outer.state, outer.content, 300);
    try HoverRig.settle(cx);
    try std.testing.expectEqual(@as(?usize, 12), HoverRig.indexOf(&rows, cx.hitTest(150, 75)));
    try std.testing.expectEqual(@as(?*Node, below[0]), cx.hitTest(150, 170));
}

test "scrollIntoView: clamps against the finished layout, not the extents of the last painted frame" {
    const testing = std.testing;
    var cx = try Cx.init(testing.allocator, std.testing.io);
    defer cx.deinit();
    const root = try box(cx, .{ .width = .{ .px = 200 }, .height = .{ .px = 200 } }, .{});
    cx.root = root;
    const scope = try Scope.init(testing.allocator, null, cx.owner);
    defer scope.dispose();
    const sa = try ScrollArea(.{ .width = 200, .height = 200 }).mount(scope, cx);
    try root.appendChild(testing.allocator, sa.container);
    // The last painted frame: 300 of content in a 200 viewport (max offset 100).
    sa.state.content_height = 300;
    sa.state.viewport_height = 200;
    // This frame's layout grew the content to 1000 (rows appended); the scrollbar pass that
    // refreshes the stored extents has not run yet (the caller is an after-layout hook).
    const target = try box(cx, .{ .width = .{ .px = 200 }, .height = .{ .px = 40 } }, .{});
    try sa.content.appendChild(testing.allocator, target);
    sa.container.setLayoutRect(.{ .x = 0, .y = 0, .w = 200, .h = 200 });
    sa.content.setLayoutRect(.{ .x = 0, .y = 0, .w = 200, .h = 1000 });
    target.setLayoutRect(.{ .x = 0, .y = 900, .w = 200, .h = 40 });
    scrollIntoView(sa.state, sa.content, target, .end);
    try testing.expectEqual(@as(f32, 740), sa.state.scroll_y); // 940 - 200; the stale maximum was 100
    try testing.expectEqual(@as(f32, 1000), sa.state.content_height);
}

test "scrollIntoView from an after-layout hook reveals a row that hook just showed (real frame, two rounds)" {
    const env = try OffsetEnv.init();
    defer env.deinit();
    const r = try env.mountDetached(env.scope, .{ .width = 300, .height = 200 });
    try env.root.appendChild(std.testing.allocator, r.container);
    const last = try box(env.cx, .{ .width = .{ .grow = .{} }, .height = .{ .px = 100 }, .display = .none }, .{});
    try r.content.appendChild(std.testing.allocator, last);
    env.frame();
    try std.testing.expectEqual(@as(f32, 800), testState(r).maxScrollY());
    const Reveal = struct {
        area: ScrollAreaResult,
        row: *Node,
        fn run(raw: *anyopaque, round: u8, _: bool) core.AfterLayoutResult {
            const self: *@This() = @ptrCast(@alignCast(raw));
            if (round == 0 and self.row.style.display == .none) {
                self.row.setDisplay(.flex);
                return .needs_layout;
            }
            if (round == 1) scrollIntoView(self.area.state, self.area.content, self.row, .end);
            return .done;
        }
    };
    var reveal = Reveal{ .area = r, .row = last };
    try env.cx.addAfterLayoutHook(&reveal, Reveal.run);
    defer env.cx.removeAfterLayoutHook(&reveal);
    env.cx.requestRedraw();
    env.frame();
    // Content 1100 after round 0's layout: the row's bottom (1100) at the viewport's (200).
    try std.testing.expectEqual(@as(f32, 900), testState(r).scroll_y);
}

test "ScrollArea .both: scrollIntoViewX reveals a child past the viewport and keeps the vertical reveal's x offset" {
    const env = try OffsetEnv.init();
    defer env.deinit();
    const r = try ScrollArea(.{ .width = 300, .height = 200, .direction = .both }).mount(env.scope, env.cx);
    try env.root.appendChild(std.testing.allocator, r.container);
    const row = try box(env.cx, .{ .width = .{ .fit = .{} }, .height = .{ .px = 40 }, .direction = .row }, .{});
    try r.content.appendChild(std.testing.allocator, row);
    _ = try core.adoptChild(env.cx, std.testing.allocator, row, try box(env.cx, .{ .width = .{ .px = 700 }, .height = .{ .px = 40 }, .flex_shrink = 0 }, .{}));
    const tail = try core.adoptChild(env.cx, std.testing.allocator, row, try box(env.cx, .{ .width = .{ .px = 100 }, .height = .{ .px = 40 }, .flex_shrink = 0 }, .{}));
    env.frame();
    try std.testing.expectEqual(@as(f32, 800), testState(r).content_width);
    scrollIntoViewX(testState(r), r.content, tail, .nearest);
    try std.testing.expectEqual(@as(f32, 500), testState(r).scroll_x);
    // A vertical reveal (a11y does both) must not pull the x offset back.
    scrollIntoView(testState(r), r.content, tail, .nearest);
    scrollIntoViewX(testState(r), r.content, tail, .nearest);
    try std.testing.expectEqual(@as(f32, 500), testState(r).scroll_x);
}

test "ScrollArea .both: the content box spans the widest child (padded area, stretched rows, unwrapped text)" {
    const env = try OffsetEnv.init();
    defer env.deinit();
    const r = try ScrollArea(.{ .width = 280, .height = 120, .direction = .both, .padding = Padding.all(10) }).mount(env.scope, env.cx);
    try env.root.appendChild(std.testing.allocator, r.container);
    // A stretched header row (no width of its own) and a 900-wide row with a right margin.
    const header = try box(env.cx, .{ .height = .{ .px = 20 } }, .{});
    try r.content.appendChild(std.testing.allocator, header);
    const wide = try box(env.cx, .{ .width = .{ .px = 900 }, .height = .{ .px = 20 }, .margin = .{ .right = 24 } }, .{});
    try r.content.appendChild(std.testing.allocator, wide);
    env.frame();
    const s = testState(r);
    try std.testing.expectEqual(@as(f32, 924), s.content_width);
    try std.testing.expectEqual(@as(f32, 924 - 260), s.maxScrollX());
    // The stretched row spans the scrolled width (CSS width: max-content; min-width: 100%).
    try std.testing.expectEqual(@as(f32, 924), header.rectFromWorldOrFallback().w);
    // Content narrower than the viewport still fills it, and nothing scrolls sideways.
    wide.setStyleInline(std.testing.allocator, .{ .width = .{ .px = 100 } });
    env.frame();
    try std.testing.expectEqual(@as(f32, 260), s.content_width);
    try std.testing.expectEqual(@as(f32, 0), s.maxScrollX());
    try std.testing.expect(!s.needsHScrollbar());
    try std.testing.expectEqual(@as(f32, 260), header.rectFromWorldOrFallback().w);
}

test "ScrollArea scroll_y: an area out of view applies an outside write and reports the clamp of shrunk content in that frame" {
    const env = try OffsetEnv.init();
    defer env.deinit();
    const alloc = std.testing.allocator;
    const outer = try ScrollArea(.{ .width = 300, .height = 200, .rubber_band_y = false }).mount(env.scope, env.cx);
    try env.root.appendChild(alloc, outer.container);
    try outer.content.appendChild(alloc, try box(env.cx, .{ .width = .{ .grow = .{} }, .height = .{ .px = 1000 } }, .{}));
    const holder = try box(env.cx, .{ .width = .{ .grow = .{} }, .height = .{ .fit = .{} } }, .{});
    try outer.content.appendChild(alloc, holder);
    const y = try env.scope.createSignal(f32, 0);
    const inner = try env.mountDetached(env.scope, offsetProps(y));
    try holder.appendChild(alloc, inner.container);
    env.frame();
    // The inner area sits 1000 below the outer viewport: the tick never visits its hook.
    const inner_ctx: *ScrollEventCtx = @ptrCast(@alignCast(inner.container.behavior.events.event_context.?));
    try std.testing.expectEqual(std.math.maxInt(u64), inner_ctx.hook_frame);
    y.set(350);
    env.frame();
    try std.testing.expectEqual(@as(f32, 350), testState(inner).scroll_y);
    // Its content shrinks to 300 (max 100): clamped by the layout observer, reported that frame.
    for (inner.content.children.items[3..]) |row| row.setDisplay(.none);
    env.cx.requestRedraw();
    env.frame();
    try std.testing.expectEqual(@as(f32, 100), testState(inner).scroll_y);
    try std.testing.expectEqual(@as(f32, 100), y.peek());
}

test "ScrollArea scroll_y: a detached area keeps an outside write pending and leaves the source alone" {
    const env = try OffsetEnv.init();
    defer env.deinit();
    const y = try env.scope.createSignal(f32, 0);
    const r = try env.mountDetached(env.scope, offsetProps(y));
    try env.root.appendChild(std.testing.allocator, r.container);
    env.frame();
    setScrollY(testState(r), r.content, 300);
    env.frame();
    try std.testing.expectEqual(@as(f32, 300), y.peek());
    // Detached from the root but kept alive (retained for re-insertion) and still bound: a write
    // waits, nothing is reported.
    env.root.removeChildRetained(r.container);
    y.set(120);
    env.frame();
    try std.testing.expectEqual(@as(f32, 300), testState(r).scroll_y);
    try std.testing.expectEqual(@as(f32, 120), y.peek());
    // Back in the tree: the write lands.
    try env.root.appendChild(std.testing.allocator, r.container);
    env.frame();
    try std.testing.expectEqual(@as(f32, 120), testState(r).scroll_y);
}

test "ScrollArea extents: content an ulp past the viewport is no overflow (no scroll range, no scrollbar)" {
    var s = ScrollState{ .viewport_height = 200, .content_height = std.math.nextAfter(f32, 200, 1000), .viewport_width = 280, .content_width = std.math.nextAfter(f32, 280, 1000) };
    try std.testing.expectEqual(@as(f32, 0), s.maxScrollY());
    try std.testing.expectEqual(@as(f32, 0), s.maxScrollX());
    try std.testing.expect(!s.needsScrollbar());
    try std.testing.expect(!s.needsHScrollbar());
    s.content_height = 201;
    try std.testing.expectEqual(@as(f32, 1), s.maxScrollY());
    try std.testing.expect(s.needsScrollbar());
}

test "ScrollArea offset bindings share one after-layout pass per window" {
    const env = try OffsetEnv.init();
    defer env.deinit();
    const before = env.cx.after_layout_hooks.items.len;
    var signals: [8]*core.Signal(f32) = undefined;
    for (&signals) |*sig| {
        sig.* = try env.scope.createSignal(f32, 0);
        const r = try env.mountDetached(env.scope, offsetProps(sig.*));
        try env.root.appendChild(std.testing.allocator, r.container);
    }
    try std.testing.expectEqual(before + 1, env.cx.after_layout_hooks.items.len);
}

// ---- Thumb hit area at rest and the scroller gutter ----

const ThumbHitRig = struct {
    cx: *Cx,
    scope: *Scope,
    area: ScrollAreaResult,
    control: *Node,
    downs: u32 = 0,

    fn onControl(event: @import("../../events.zig").Event, context: ?*anyopaque) @import("../../events.zig").EventResult {
        const self: *ThumbHitRig = @ptrCast(@alignCast(context.?));
        if (event == .mouse_down) {
            self.downs += 1;
            return .stop;
        }
        return .ignored;
    }

    /// A 300 x 100 `.always` area whose content (400 high) has a 24 x 24 control flush with its
    /// right edge in the first row (under the thumb's span while scrolled to the top).
    fn init(rig: *ThumbHitRig, gutter: ScrollbarGutter) !void {
        rig.downs = 0;
        rig.cx = try Cx.init(std.testing.allocator, std.testing.io);
        rig.cx.setViewport(400, 300);
        try rig.cx.setTestFrameStep(16);
        rig.scope = try Scope.init(std.testing.allocator, null, rig.cx.owner);
        rig.cx.root = try box(rig.cx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
        rig.area = try ScrollArea(.{ .width = 300, .height = 100, .scrollbars = .always, .scrollbar_gutter = gutter }).mount(rig.scope, rig.cx);
        try rig.cx.root.?.appendChild(std.testing.allocator, rig.area.container);
        const row = try box(rig.cx, .{ .width = .{ .grow = .{} }, .height = .{ .px = 24 }, .direction = .row, .justify = .end, .flex_shrink = 0 }, .{});
        rig.control = try box(rig.cx, .{ .width = .{ .px = 24 }, .height = .{ .px = 24 }, .flex_shrink = 0 }, .{});
        rig.control.behavior.events.on_event = onControl;
        rig.control.behavior.events.event_context = rig;
        try row.appendChild(std.testing.allocator, rig.control);
        try rig.area.content.appendChild(std.testing.allocator, row);
        try rig.area.content.appendChild(std.testing.allocator, try box(rig.cx, .{ .width = .{ .grow = .{} }, .height = .{ .px = 376 }, .flex_shrink = 0 }, .{}));
        rig.frames(3);
    }
    fn frames(rig: *ThumbHitRig, n: usize) void {
        for (0..n) |_| {
            rig.cx.advanceFrameClock();
            rig.cx.root.?.markRenderDirty();
            rig.cx.layout();
            _ = rig.cx.render();
        }
    }
    fn deinit(rig: *ThumbHitRig) void {
        rig.scope.dispose();
        rig.cx.deinit();
    }
};

test "ScrollArea: a resting thumb takes the pointer only where it is drawn; approached, it grows to be grabbed" {
    var rig: ThumbHitRig = undefined;
    try rig.init(.none);
    defer rig.deinit();
    const thumb = (try scrollEventCtxOf(rig.area.container)).scrollbar.?;
    const bar = thumb.globalRect();
    try std.testing.expect(bar.w > 0 and bar.w <= ScrollbarVisual.idle_thickness + 0.01);
    // A press next to the resting thumb (inside the old slop, outside the drawn bar), arriving with
    // no hover first (a touch, a programmatic click): the control under it gets it.
    const near_x = bar.x - 3;
    rig.cx.handleMouseDown(near_x, bar.y + 10, .{});
    rig.cx.handleMouseUp(near_x, bar.y + 10);
    try std.testing.expectEqual(@as(u32, 1), rig.downs);
    try std.testing.expect(!rig.area.state.scrollbar_dragging);
    // Approaching the edge widens the thumb; a press in its slop now grabs it.
    rig.cx.handleMouseMove(bar.x + bar.w / 2, bar.y + 10);
    rig.frames(2);
    try std.testing.expect(rig.area.state.scrollbar_hovered);
    const active = thumb.globalRect();
    try std.testing.expect(active.w > ScrollbarVisual.idle_thickness + 0.5);
    rig.cx.handleMouseDown(active.x - 3, active.y + 10, .{});
    try std.testing.expect(rig.area.state.scrollbar_dragging);
    rig.cx.handleMouseUp(active.x - 3, active.y + 10);
    try std.testing.expectEqual(@as(u32, 1), rig.downs);
}

test "ScrollArea scrollbar_gutter .stable: content keeps out of the scroller band, an edge control stays clickable when hovered" {
    var plain: ThumbHitRig = undefined;
    try plain.init(.none);
    defer plain.deinit();
    var kept: ThumbHitRig = undefined;
    try kept.init(.stable);
    defer kept.deinit();
    // The content is narrower by the interaction band; the thumb stays at the container's edge.
    try std.testing.expectApproxEqAbs(plain.area.content.globalRect().w - ScrollbarVisual.interaction_band, kept.area.content.globalRect().w, 0.5);
    const thumb = (try scrollEventCtxOf(kept.area.container)).scrollbar.?;
    try std.testing.expectApproxEqAbs(plain.area.container.globalRect().x + 300 - ScrollbarVisual.edge_inset, thumb.globalRect().x + thumb.globalRect().w, 0.5);
    // Without a gutter, the edge control's center is inside the scroller band: hovering it wakes
    // the scroller, which then takes the press.
    const c0 = plain.control.globalRect();
    plain.cx.handleMouseMove(c0.x + c0.w / 2, c0.y + c0.h / 2);
    plain.frames(2);
    try std.testing.expect(plain.area.state.scrollbar_hovered);
    plain.cx.handleMouseDown(c0.x + c0.w / 2, c0.y + c0.h / 2, .{});
    try std.testing.expectEqual(@as(u32, 0), plain.downs);
    plain.cx.handleMouseUp(c0.x + c0.w / 2, c0.y + c0.h / 2);
    // With the gutter, the same control is clear of the band: hover does not wake the scroller and
    // the press reaches the control.
    const c1 = kept.control.globalRect();
    kept.cx.handleMouseMove(c1.x + c1.w / 2, c1.y + c1.h / 2);
    kept.frames(2);
    try std.testing.expect(!kept.area.state.scrollbar_hovered);
    kept.cx.handleMouseDown(c1.x + c1.w / 2, c1.y + c1.h / 2, .{});
    kept.cx.handleMouseUp(c1.x + c1.w / 2, c1.y + c1.h / 2);
    try std.testing.expectEqual(@as(u32, 1), kept.downs);
    // The whole control lies left of the band.
    try std.testing.expect(c1.x + c1.w <= kept.area.container.globalRect().x + 300 - ScrollbarVisual.interaction_band + 0.5);
}

test "ScrollArea scrollbar_gutter .stable: both-axis scrolling clips at the reserved gutter" {
    const t = std.testing;
    const cx = try Cx.init(t.allocator, t.io);
    defer cx.deinit();
    cx.setViewport(400, 300);
    cx.root = try box(cx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    const scope = try Scope.init(t.allocator, null, cx.owner);
    defer scope.dispose();

    const area = try ScrollArea(.{
        .width = 300,
        .height = 200,
        .direction = .both,
        .scrollbars = .always,
        .scrollbar_gutter = .stable,
    }).mount(scope, cx);
    try cx.root.?.appendChild(t.allocator, area.container);

    // Styled content can exceed the viewport in both directions. Its own padding and
    // margins still belong to the caller, and are independent of the fixed gutter.
    try area.content.setStyleInlineFallible(t.allocator, .{
        .width = .{ .px = 480 },
        .height = .{ .px = 300 },
        .flex_shrink = 0,
        .margin = Padding.ZERO,
    });
    const target = try box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    target.behavior.events.on_event = struct {
        fn handle(_: core.Event, _: ?*anyopaque) core.EventResult {
            return .stop;
        }
    }.handle;
    try area.content.appendChild(t.allocator, target);
    cx.layout();
    _ = cx.render();

    const gutter = ScrollbarVisual.interaction_band;
    try t.expectApproxEqAbs(300 - gutter, area.state.viewport_width, 0.5);
    try t.expectApproxEqAbs(200 - gutter, area.state.viewport_height, 0.5);
    try t.expectApproxEqAbs(180 + gutter, area.state.maxScrollX(), 0.5);
    try t.expectApproxEqAbs(100 + gutter, area.state.maxScrollY(), 0.5);

    const view_rect = area.container.globalRect();
    try t.expectEqual(target, cx.hitTest(view_rect.x + 20, view_rect.y + 20).?);
    try t.expect(cx.hitTest(view_rect.x + view_rect.w - gutter + 2, view_rect.y + 20) != target);
    try t.expect(cx.hitTest(view_rect.x + 20, view_rect.y + view_rect.h - gutter + 2) != target);

    restorePersistOffset(area.container, 1000, 1000);
    cx.layout();
    _ = cx.render();
    const end = target.globalRect();
    try t.expectApproxEqAbs(view_rect.x + view_rect.w - gutter, end.x + end.w, 0.5);
    try t.expectApproxEqAbs(view_rect.y + view_rect.h - gutter, end.y + end.h, 0.5);
}

test "ScrollArea scrollbar_gutter .stable: fit viewport follows content before and after overflow" {
    const t = std.testing;
    const cx = try Cx.init(t.allocator, t.io);
    defer cx.deinit();
    cx.setViewport(400, 300);
    cx.root = try box(cx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    const scope = try Scope.init(t.allocator, null, cx.owner);
    defer scope.dispose();

    const area = try ScrollArea(.{ .scrollbars = .always, .scrollbar_gutter = .stable }).mount(scope, cx);
    try area.container.setStyleInlineFallible(t.allocator, .{
        .height = .{ .fit = .{ .max = 100 } },
        .min_height = 0,
        .max_height = 100,
        .flex_shrink = 0,
    });
    try cx.root.?.appendChild(t.allocator, area.container);
    const child = try box(cx, .{ .width = .fill(), .height = .{ .px = 48 }, .flex_shrink = 0 }, .{});
    try area.content.appendChild(t.allocator, child);
    cx.layout();
    _ = cx.render();

    const initial_width = area.content.globalRect().w;
    try t.expectApproxEqAbs(@as(f32, 48), area.container.globalRect().h, 0.5);
    try t.expect(!area.state.needsScrollbar());

    try child.setStyleInlineFallible(t.allocator, .{ .height = .{ .px = 160 } });
    cx.layout();
    _ = cx.render();
    try t.expectApproxEqAbs(@as(f32, 100), area.container.globalRect().h, 0.5);
    try t.expectApproxEqAbs(@as(f32, 60), area.state.maxScrollY(), 0.5);
    try t.expectApproxEqAbs(initial_width, area.content.globalRect().w, 0.5);
}
