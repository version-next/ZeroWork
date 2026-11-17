//! The window's floating card layer (PLUGIN_ARCH_PLAN 2.5 / 2.5.7 / 4c-3): the generic implementation
//! of the "float" placement of a content card. A window owns one `FloatLayer`; every floating card is
//! a `Card` on it. A card type declares which interactions it supports (`float_card.Descriptor`);
//! this layer implements all of them:
//!
//! - move / resize (eight edges, declared min / max) / maximize inside the window floating region
//!   (title bar and expanded sidebar excluded, status bar included, inset 8);
//! - raise (pointer down brings the card above the other floating cards) and close;
//! - Z12 presentation: unfold from / fold into an open anchor (`open_from_anchor`), fold into the owner
//!   tab on the strip when another tab becomes current and unfold back (`fold_to_tab`); reversals
//!   retarget mid flight; `ui.float_card_transition = "fade"` fades out in place shrinking slightly
//!   (Z12b) and the system "reduce motion" setting fades in place. Every form flies one static
//!   picture (zenit's static-texture model, genie-static): the card is out of layout and paint until
//!   it lands, and `anchor` draws the genie mesh (macOS Dock minimize);
//! - remember the dropped rectangle per card instance (`Placement`, window content coordinates) and
//!   re-clamp it into the visible region when the window shrinks.
//! - swipe down to collapse (`swipe_collapse`, Pencil AveHg, numbers in `float_swipe.Tokens`): a move
//!   that starts on the grip of a bottom-docked card follows the pointer past the view bottom; on
//!   release a fast downward fling (≥ 900 px/s over the last 80 ms) or a third of the card past the
//!   bottom slides it out (inheriting the release velocity, fading 220 ms ease-in) and hands it to
//!   the owner's `minimize` (AI: back into its launcher); otherwise — and always for a card without
//!   `minimize` — it springs back to the docked position (180 ms ease-out). Reduce motion: fades
//!   only (120 ms). The grip shows its held state (`Chrome.setGripHeld`) while pressed.
//! - inertia (Pencil JmcNv "not docked: an ordinary drag + inertia"): a move that is not a swipe
//!   collapse and leaves nothing to spring back glides on at the release velocity (same 80 ms
//!   samples), decaying exponentially (`float_swipe.glide`, numbers in `float_swipe.Tokens.glide_*`)
//!   and stopping on the drag region edge it reaches. Not under 8 px, under the minimum release
//!   speed, or with reduce motion. The placement is the landing rectangle from the release on (it
//!   is remembered like any drop); the glide is a translate from the release position to it, and a
//!   press on the card mid glide takes it over where it is.
//!
//! - the window look: a card attached with a `float_chrome.Chrome` wears the unified chrome (native
//!   floating Card frame, `float.drag` grip with the Grabber, header with the declared actions); the
//!   layer owns its maximize button and routes the other actions to the owner (`Callbacks.action`).
//!
//! The card's owner keeps its content and decides *whether* the card is shown (`Card.present`); the
//! layer decides *how*. The AI chat card (`features/ai`) is the first user; the history card and
//! plugin cards attach the same way.
const std = @import("std");
const ui = @import("ui");
const model = @import("../../base/float_card.zig");
const tab_anchor = @import("../../base/tab_motion_anchor.zig");
const S = @import("float_card_styles.zig");
pub const float_chrome = @import("float_chrome.zig");
const float_card_motion = @import("../styles/float_card_motion.zig");
const float_swipe = float_card_motion.swipe;
const overlay = @import("../overlay/overlay_host.zig");

pub const Rect = model.Rect;
pub const Descriptor = model.Descriptor;
pub const Placement = model.Placement;
pub const Origin = model.Origin;
pub const Interaction = model.Interaction;
pub const HeaderAction = model.HeaderAction;
pub const Chrome = float_chrome.Chrome;
const drag = ui.interaction.drag;
const Phase = ui.fx.anchor_transition.Phase;

/// `ui.float_card_transition`: how a card leaves / enters when its tab stops / becomes current, and
/// how it opens from / closes into its anchor. `anchor` flies into / out of the anchor (Z12);
/// `fade` fades out in place shrinking to about 0.97 (Z12b `fade_scale`, no anchor resolved).
/// "Reduce motion" turns both into zenit's plain fade in place.
pub const TransitionMode = float_card_motion.Mode;
/// Read once at the start of every run, so a saved setting applies from the next transition.
pub const ModeSource = struct { ctx: ?*anyopaque, read: *const fn (ctx: ?*anyopaque) TransitionMode };
/// Time base of the swipe velocity samples; null = the drag events' own clock (tests inject one).
pub const Clock = struct { ctx: ?*anyopaque, now_ns: *const fn (ctx: ?*anyopaque) u64 };

/// What the owner says about its card this frame.
pub const Presentation = struct {
    /// The card is open and its owner tab is the current tab.
    shown: bool,
    /// Owner tab (strip tab id) of the content in the card node; null when that tab is gone.
    tab: ?u64,
    /// The window's current tab.
    current_tab: ?u64,
    /// This change is an explicit open / close on the owner tab: fold into / unfold from `anchor`.
    explicit: bool = false,
    /// The card node's content moved to another tab's instance since the last call (one node shared
    /// by per-tab instances, like the AI panel).
    swapped: bool = false,
    /// The open anchor (window coordinates) for `open_from_anchor`.
    anchor: ?Rect = null,
};

pub const Callbacks = struct {
    ctx: ?*anyopaque = null,
    /// `close` interaction: the owner closes the card (and its content).
    close: ?*const fn (ctx: ?*anyopaque) void = null,
    /// A presentation run came to rest.
    rest: ?*const fn (ctx: ?*anyopaque, phase: Phase) void = null,
    /// A header action of the unified chrome (`maximize` is the layer's own and never comes here).
    /// Return false to let the layer handle it (`close` → `Card.close`).
    action: ?*const fn (ctx: ?*anyopaque, action: HeaderAction) bool = null,
};

pub const CardOptions = struct {
    /// Positioned node (child of the layer root); the Z12 transition target.
    node: *ui.Node,
    /// Sized visual frame inside `node` (may be `node`); resize handles are added to it. With a
    /// `chrome`, null = the chrome root.
    frame: ?*ui.Node = null,
    /// Drag grip (`move`); double click resets the position. With a `chrome`, null = its `float.drag`.
    grip: ?*ui.Node = null,
    /// The unified window chrome (`float_chrome.zig`): frame, grip and header actions come from it.
    chrome: ?*Chrome = null,
    descriptor: Descriptor,
    /// The instance's placement; the owner may swap its contents (cancel first).
    placement: *Placement,
    callbacks: Callbacks = .{},
    /// Test ids of the grip and of the resize handles (n, s, w, e, nw, ne, sw, se).
    grip_test_id: []const u8 = "float.drag",
    handle_test_ids: [8][]const u8 = .{ "float.resize.n", "float.resize.s", "float.resize.w", "float.resize.e", "float.resize.nw", "float.resize.ne", "float.resize.sw", "float.resize.se" },
};

const edges = [_]model.Edge{ .n, .s, .w, .e, .nw, .ne, .sw, .se };

/// Swipe-collapse state of a card (`float_swipe.zig`).
const Swipe = struct {
    const Step = enum { idle, spring, slide, glide };
    phase: Step = .idle,
    /// The current move started on a bottom-docked card: it follows the pointer past the bottom.
    eligible: bool = false,
    /// The grip is pressed.
    held: bool = false,
    /// Visual offset (translate) from the card's laid-out rectangle.
    offset_x: f32 = 0,
    offset_y: f32 = 0,
    sampler: float_swipe.Sampler = .{},
    start_geometry: ?model.Geometry = null,
    /// A swipe collapse started and the owner's collapse target has not taken it yet.
    arrival: bool = false,
    /// This run fades only (reduce motion).
    reduced: bool = false,
    /// Inertia in flight: axes still animating (the glide ends when both are done).
    glide_axes: u2 = 0,
};
const Kind = union(enum) { move, resize: model.Edge };
const Part = struct { card: *Card, kind: Kind };
const Active = struct { geometry: model.Geometry, rect: Rect };

pub const FloatLayer = struct {
    cx: *ui.Cx,
    scope: *ui.Scope,
    /// Full-window, pass-through container of every floating card.
    root: *ui.Node,
    /// Where cards can be dragged (the whole window, inset 8).
    region: Rect = .{ .x = 0, .y = 0, .width = 0, .height = 0 },
    /// Maximize target and default placement area (title bar and expanded sidebar excluded);
    /// null = `region`.
    work: ?Rect = null,
    mode: TransitionMode = .anchor,
    /// The window's `ui.float_card_transition` (the host reads its runtime config); null = `mode`.
    mode_source: ?ModeSource = null,
    cards: std.ArrayList(*Card) = .empty,
    next_z: i16 = 0,
    /// Swipe-collapse numbers (`float_swipe.tokens`).
    swipe_tokens: float_swipe.Tokens = float_card_motion.swipe_tokens,
    clock: ?Clock = null,

    /// Mount the layer root (test id `float.layer`) under `parent` (the window root).
    pub fn mount(cx: *ui.Cx, scope: *ui.Scope, parent: *ui.Node) !*FloatLayer {
        const root = try ui.box(cx, S.layer(), .{});
        root.meta.ownership.meta.test_id = "float.layer";
        try parent.appendChild(cx.allocator, root);
        const self = try scope.createState(FloatLayer, .{ .cx = cx, .scope = scope, .root = root });
        try scope.onCleanup(FloatLayer, self, cleanup);
        return self;
    }

    fn cleanup(self: *FloatLayer) void {
        for (self.cards.items) |card| card.dispose();
        self.cards.deinit(self.cx.allocator);
    }

    /// The window floating region (window content coordinates), from the shell every frame.
    pub fn setRegion(self: *FloatLayer, region: Rect) void {
        self.region = region;
    }

    /// The work area (maximize / default placement), from the shell every frame.
    pub fn setWorkRegion(self: *FloatLayer, work: Rect) void {
        self.work = work;
    }

    /// A fixed mode (tests, windows without settings).
    pub fn setMode(self: *FloatLayer, mode: TransitionMode) void {
        self.mode = mode;
    }

    pub fn setModeSource(self: *FloatLayer, source: ModeSource) void {
        self.mode_source = source;
    }

    /// The transition mode for a run starting now.
    pub fn currentMode(self: *const FloatLayer) TransitionMode {
        const source = self.mode_source orelse return self.mode;
        return source.read(source.ctx);
    }

    /// Put a card on the layer. Its node is moved under the layer root.
    pub fn attach(self: *FloatLayer, scope: *ui.Scope, options: CardOptions) !*Card {
        const chrome_frame: ?*ui.Node = if (options.chrome) |chrome| chrome.root else null;
        const chrome_grip: ?*ui.Node = if (options.chrome) |chrome| chrome.grip else null;
        const frame = options.frame orelse chrome_frame orelse return error.FloatCardFrameMissing;
        // `swipe_collapse` is never declared: it follows `move` + `minimize`.
        var descriptor = options.descriptor;
        float_swipe.deriveInto(&descriptor);
        const card = try scope.createState(Card, .{ .layer = self, .node = options.node, .frame = frame, .grip = options.grip orelse chrome_grip, .descriptor = descriptor, .placement = options.placement, .callbacks = options.callbacks, .chrome = options.chrome, .focus = overlay.CardFocus.init(self.cx, options.node) });
        if (options.chrome) |chrome| {
            if (chrome.root.parent == null and chrome.root != options.node) try options.node.appendChild(self.cx.allocator, chrome.root);
            chrome.setActionHandler(.{ .ctx = card, .action = Card.chromeAction });
        }
        card.grip_id = options.grip_test_id;
        card.handle_ids = options.handle_test_ids;
        try scope.onCleanup(Card, card, Card.detachFromLayer);
        if (options.node.parent) |parent| if (parent != self.root) parent.removeChild(options.node);
        if (options.node.parent == null) try self.root.appendChild(self.cx.allocator, options.node);
        try self.cards.append(self.cx.allocator, card);
        card.mountTransition(scope);
        try card.mountGestures(scope);
        options.node.behavior.events.on_event_capture = Card.nodeCapture;
        options.node.behavior.events.capture_context = card;
        // Non-modal card rule (OverlayHost `card`): Escape reaches the card root only from inside it.
        if (options.node.behavior.events.on_key_down == null) {
            options.node.behavior.events.on_key_down = Card.nodeKey;
            options.node.behavior.events.key_context = card;
        }
        return card;
    }

    /// `raise`: bring `card` above the other floating cards.
    pub fn raise(self: *FloatLayer, card: *Card) void {
        if (!card.descriptor.supports(.raise)) return;
        var top: i16 = 0;
        for (self.cards.items) |other| if (other != card) {
            top = @max(top, other.node.style.z_index());
        };
        if (card.node.style.z_index() > top) return;
        self.next_z = @max(self.next_z, top) +| 1;
        card.node.setStyle(self.cx.allocator, .z_index, self.next_z);
        card.node.markLayoutDirty();
        self.cx.requestRedraw();
    }
};

pub const Card = struct {
    layer: *FloatLayer,
    node: *ui.Node,
    frame: *ui.Node,
    grip: ?*ui.Node,
    descriptor: Descriptor,
    placement: *Placement,
    callbacks: Callbacks,
    chrome: ?*Chrome = null,
    /// Focus entry / Tab containment / Escape / focus return of a non-modal card (`overlay_host.zig`).
    focus: overlay.CardFocus,
    origin: Origin = .{ .content = .{ .x = 0, .y = 0, .width = 0, .height = 0 } },
    region: Rect = .{ .x = 0, .y = 0, .width = 0, .height = 0 },
    work: Rect = .{ .x = 0, .y = 0, .width = 0, .height = 0 },
    bounds_ready: bool = false,
    shown: bool = false,
    handles: [8]?*ui.Node = @splat(null),
    bindings: [9]?*drag.Binding = @splat(null),
    active: ?Active = null,
    disposed: bool = false,
    applied_inset: ?ui.Inset = null,
    grip_id: []const u8 = "float.drag",
    handle_ids: [8][]const u8 = @splat("float.resize"),

    /// Null only when it could not be made (out of memory): the card then shows / hides without motion.
    transition: ?*ui.fx.AnchorTransition = null,
    presented_visible: bool = false,
    presented_tab: ?u64 = null,
    presented_away: bool = false,
    /// Folding into / unfolding from the open anchor: the owner keeps its anchor (e.g. a launcher
    /// icon) hidden until the run lands.
    anchor_flight: bool = false,
    anchor_names: [2][48]u8 = undefined,
    anchor_slot: u1 = 0,
    /// The current run's anchor: `anchor`, `workspace.tab.<id>` or `none`.
    anchor_label: []const u8 = "none",

    swipe: Swipe = .{},

    // ── Geometry ────────────────────────────────────────────────────────────────────────────

    /// This frame's inputs: the owner tab's origin (default placement) and whether the card is shown.
    /// Shown cards are clamped into the layer region and positioned; a closed card keeps its node
    /// where it was, so a fold-away flies from there.
    pub fn update(self: *Card, origin: Origin, shown: bool) void {
        const region = self.layer.region;
        const work = self.layer.work orelse region;
        if (self.bounds_ready and (!std.meta.eql(self.region, region) or !std.meta.eql(self.work, work) or !std.meta.eql(self.origin, origin))) {
            self.cancel();
            self.endGlide();
        }
        self.region = region;
        self.work = work;
        self.origin = origin;
        self.bounds_ready = true;
        self.shown = shown;
        if (!self.disposed) self.focus.sync(shown);
        // A press that ended without a drag (released elsewhere, or a plain click) drops the held look.
        if (self.swipe.held and !self.gripBusy()) self.setGripHeld(false);
        if (!shown) {
            self.syncHandles();
            return;
        }
        self.placement.updateBounds(self.descriptor, origin, region);
        self.placement.clamped = self.rect();
        self.apply(self.rect());
        self.syncHandles();
    }

    /// The card rectangle (window content coordinates) for the current inputs.
    pub fn rect(self: *const Card) Rect {
        // Maximize fills the work area; a never-moved card sits at its default in the work area;
        // a dropped rectangle is only clamped into the whole-window drag region.
        if (self.placement.maximized) return self.work;
        if (self.placement.desired) |value| return model.clampRect(self.descriptor, value, self.region);
        return model.clampRect(self.descriptor, model.defaultRect(self.descriptor, self.origin, self.work), self.region);
    }

    fn apply(self: *Card, r: Rect) void {
        const parent_rect = if (self.node.parent) |parent| parent.globalRect() else ui.ComputedRect{ .x = 0, .y = 0, .w = 0, .h = 0 };
        const inset: ui.Inset = .{ .left = .{ .px = r.x - parent_rect.x }, .top = .{ .px = r.y - parent_rect.y } };
        if (self.applied_inset == null or !std.meta.eql(self.applied_inset.?, inset)) {
            self.node.setStyle(self.layer.cx.allocator, .inset, inset);
            self.applied_inset = inset;
        }
        if (self.node.style.width != .px or @abs(self.node.style.width.px - r.width) > 0.5) self.node.setStyle(self.layer.cx.allocator, .width, .{ .px = r.width });
        if (self.frame != self.node) {
            if (self.frame.style.width != .px or @abs(self.frame.style.width.px - r.width) > 0.5) self.frame.setStyle(self.layer.cx.allocator, .width, .{ .px = r.width });
        }
        if (self.frame.style.height != .px or @abs(self.frame.style.height.px - r.height) > 0.5) self.frame.setStyle(self.layer.cx.allocator, .height, .{ .px = r.height });
    }

    /// `maximize`: fill the floating region / restore.
    pub fn toggleMaximized(self: *Card) void {
        if (!self.bounds_ready) return;
        self.cancel();
        self.endGlide();
        self.placement.toggleMaximized(self.descriptor, self.origin, self.region);
        if (self.shown) self.apply(self.rect());
        self.syncHandles();
        self.layer.cx.requestRedraw();
    }

    /// Grip double click: back to the first-open position, keeping the size.
    pub fn resetPosition(self: *Card) void {
        if (!self.bounds_ready or !self.descriptor.supports(.move)) return;
        self.cancel();
        self.endGlide();
        self.placement.resetPosition(self.descriptor, self.origin, self.work);
        if (self.shown) self.apply(self.rect());
        self.syncHandles();
        self.layer.cx.requestRedraw();
    }

    /// A header button of the unified chrome: maximize is the layer's; the owner may take the others;
    /// an unhandled close closes the card.
    fn chromeAction(ctx: ?*anyopaque, action: HeaderAction) void {
        const self: *Card = @ptrCast(@alignCast(ctx orelse return));
        if (self.disposed) return;
        if (action == .maximize) return self.toggleMaximized();
        if (self.callbacks.action) |callback| if (callback(self.callbacks.ctx, action)) return;
        if (action == .close) self.close();
    }

    /// `close`: forget the position unless remembered, then let the owner close the card.
    pub fn close(self: *Card) void {
        if (!self.descriptor.supports(.close)) return;
        self.cancel();
        self.placement.closed(self.descriptor);
        if (self.callbacks.close) |callback| callback(self.callbacks.ctx);
    }

    // ── Gestures (move / resize / raise) ────────────────────────────────────────────────────

    fn mountGestures(self: *Card, scope: *ui.Scope) !void {
        const cx = self.layer.cx;
        if (self.grip) |grip| if (self.descriptor.supports(.move)) {
            const moving = try scope.createState(Part, .{ .card = self, .kind = .move });
            self.bindings[0] = try drag.Binding.attach(scope, cx, grip, .{ .enabled = false, .can_start = canStart }, changed, moving);
            grip.meta.ownership.meta.test_id = self.grip_id;
            grip.behavior.interaction.pointer_down_focus = .preserve;
            grip.behavior.events.on_event_capture = gripCapture;
            grip.behavior.events.capture_context = self;
        };
        if (!self.descriptor.supports(.resize)) return;
        for (edges, 0..) |edge, index| {
            const node = try ui.box(cx, S.handle(edge, 0, 0), .{});
            self.handles[index] = node;
            node.meta.ownership.meta.test_id = self.handle_ids[index];
            node.behavior.interaction.pointer_down_focus = .preserve;
            // The strips lie over the card's content (the east one over a conversation's scroll
            // bar): a wheel over one scrolls what is under it instead of stopping at the card.
            node.setWheelTransparent(true);
            const part = try scope.createState(Part, .{ .card = self, .kind = .{ .resize = edge } });
            self.bindings[index + 1] = try drag.Binding.attach(scope, cx, node, .{ .enabled = false, .activation_distance = 0, .active_cursor = S.cursor(edge), .can_start = canStart }, changed, part);
            node.setDisplay(.none);
            try self.frame.appendChild(cx.allocator, node);
        }
    }

    /// Cancel an in-flight move / resize (the owner calls this before swapping `placement`).
    pub fn cancel(self: *Card) void {
        for (self.bindings) |binding| if (binding) |value| value.cancel(.explicit);
    }

    fn interactive(self: *const Card) bool {
        // A glide can be taken over (a press stops it where it is).
        return self.bounds_ready and self.shown and !self.placement.maximized and (self.swipe.phase == .idle or self.swipe.phase == .glide);
    }

    fn syncHandles(self: *Card) void {
        if (self.chrome) |chrome| chrome.setMaximized(self.placement.maximized);
        const r = self.rect();
        const enabled = self.interactive() and r.width > 0 and r.height > 0 and self.transitionIdle();
        for (self.bindings) |binding| if (binding) |value| value.setEnabled(enabled);
        if (self.grip) |grip| if (self.descriptor.supports(.move)) grip.setCursor(if (!enabled) .default else if (self.swipe.held) .grabbing else .grab);
        for (self.handles, edges) |maybe, edge| if (maybe) |node| {
            node.setDisplay(if (enabled) .flex else .none);
            const box = S.handle(edge, r.width, r.height);
            if (box.inset) |inset| node.setStyle(self.layer.cx.allocator, .inset, inset);
            if (box.width) |w| node.setStyle(self.layer.cx.allocator, .width, w);
            if (box.height) |h| node.setStyle(self.layer.cx.allocator, .height, h);
        };
    }

    fn transitionIdle(self: *const Card) bool {
        const t = self.transition orelse return true;
        return t.phase() == .expanded;
    }

    fn canStart(_: drag.StartRequest, raw: *anyopaque) bool {
        const part: *Part = @ptrCast(@alignCast(raw));
        return part.card.interactive();
    }

    fn changed(event: drag.Event, raw: *anyopaque) void {
        const part: *Part = @ptrCast(@alignCast(raw));
        const self = part.card;
        if (event.phase == .cancel) {
            if (part.kind == .move) self.swipeCancel();
            if (self.active) |active| {
                self.active = null;
                self.placement.restoreGeometry(active.geometry);
                self.placement.updateBounds(self.descriptor, self.origin, self.region);
                if (self.shown) self.apply(self.rect());
                self.syncHandles();
                self.layer.cx.requestRedraw();
            }
            return;
        }
        if (event.phase == .start) {
            self.takeOverGlide();
            self.layer.raise(self);
            self.active = .{ .geometry = self.placement.geometry(), .rect = self.rect() };
            if (part.kind == .move) self.swipeBegin(event);
        }
        const active = self.active orelse return;
        if (!std.math.isFinite(event.delta.x) or !std.math.isFinite(event.delta.y)) {
            self.cancel();
            return;
        }
        var next = active.rect;
        switch (part.kind) {
            .move => {
                next.x += event.delta.x;
                next.y += event.delta.y;
            },
            .resize => |edge| next = model.resized(self.descriptor, active.rect, edge, event.delta.x, event.delta.y, self.region),
        }
        self.placement.setRectangle(self.descriptor, next, self.origin, self.region);
        if (part.kind == .move) self.swipeFollow(event, next);
        if (event.phase == .end) self.active = null;
        if (self.shown) self.apply(self.rect());
        if (event.phase == .end and part.kind == .move) {
            self.setGripHeld(false);
            self.swipeRelease(event);
        }
        self.syncHandles();
        self.layer.cx.requestRedraw();
    }

    fn gripCapture(event: ui.events.Event, raw: ?*anyopaque) ui.events.EventResult {
        const self: *Card = @ptrCast(@alignCast(raw orelse return .ignored));
        switch (event) {
            // Held feedback (AveHg ①): only a press on the grip counts.
            .mouse_down => if (self.interactive() and self.descriptor.supports(.move)) self.setGripHeld(true),
            .mouse_up => self.setGripHeld(false),
            .double_click => if (!self.placement.maximized) {
                self.resetPosition();
                return .stop;
            },
            else => {},
        }
        return .ignored;
    }

    // ── Swipe down to collapse (AveHg) ──────────────────────────────────────────────────────

    fn setGripHeld(self: *Card, held: bool) void {
        if (self.swipe.held == held) return;
        self.swipe.held = held;
        if (self.chrome) |chrome| chrome.setGripHeld(held);
        self.syncHandles();
        self.layer.cx.requestRedraw();
    }

    /// The grip's move binding is pending (pressed, under the activation distance) or dragging.
    fn gripBusy(self: *const Card) bool {
        const binding = self.bindings[0] orelse return false;
        return binding.isPending() or binding.isDragging();
    }

    fn sampleTime(self: *const Card, event: drag.Event) u64 {
        const clock = self.layer.clock orelse return event.elapsed_ns;
        return clock.now_ns(clock.ctx);
    }

    /// The lowest edge a card rests on: the owner tab's content bottom or the region bottom.
    pub fn viewBottom(self: *const Card) f32 {
        return float_swipe.viewBottom(self.origin.content, self.region);
    }

    /// The window bottom (the floating layer spans the window): where a sliding card has left the view.
    fn exitY(self: *const Card) f32 {
        const r = self.layer.root.globalRect();
        return @max(self.viewBottom(), r.y + r.h);
    }

    fn swipeBegin(self: *Card, event: drag.Event) void {
        const t = self.layer.swipe_tokens;
        self.swipe.eligible = self.grip != null and !self.placement.maximized and float_swipe.docked(t, self.rect(), self.viewBottom());
        self.swipe.start_geometry = self.placement.geometry();
        self.swipe.sampler.reset();
        // The press itself is the first sample (drag events count time from the pointer down).
        if (self.layer.clock == null) self.swipe.sampler.add(0, event.origin_window.x, event.origin_window.y);
    }

    /// Follow the pointer past the bottom while the move started docked (layout stays clamped; the
    /// overshoot is a translate).
    fn swipeFollow(self: *Card, event: drag.Event, next: Rect) void {
        self.swipe.sampler.add(self.sampleTime(event), event.position_window.x, event.position_window.y);
        if (!self.swipe.eligible) return;
        const placed = self.rect();
        self.setOffset(0, @max(0, next.y - placed.y));
    }

    fn swipeRelease(self: *Card, event: drag.Event) void {
        const t = self.layer.swipe_tokens;
        const eligible = self.swipe.eligible;
        self.swipe.eligible = false;
        const r = self.rect();
        const release: float_swipe.Release = .{
            .docked = eligible,
            .collapsible = self.descriptor.supports(.swipe_collapse) and self.callbacks.action != null,
            .dx = event.raw_delta.x,
            .dy = event.raw_delta.y,
            .velocity = self.swipe.sampler.velocity(t.sample_window_ms),
            .beyond = r.y + self.swipe.offset_y + r.height - self.viewBottom(),
            .height = r.height,
            .offset = self.swipe.offset_y,
        };
        // Swipe collapse first; only an ordinary drag with nothing to spring back glides on.
        switch (float_swipe.decide(t, release)) {
            .collapse => self.swipeCollapse(release.velocity),
            .spring_back => self.springBack(),
            .settle => self.startGlide(event),
        }
    }

    // ── Inertia (JmcNv: an ordinary drag + inertia) ─────────────────────────────────────────

    /// Glide on at the release velocity (`float_swipe.glide`): the placement becomes the landing
    /// rectangle now (remembered like any drop), the card is translated back to where it was let go
    /// and the translate decays to 0 per axis.
    fn startGlide(self: *Card, event: drag.Event) void {
        const t = self.layer.swipe_tokens;
        if (!self.shown or self.placement.maximized) return;
        const from = self.rect();
        const g = float_swipe.glide(t, .{
            .dx = event.raw_delta.x,
            .dy = event.raw_delta.y,
            .velocity = self.swipe.sampler.velocity2(t.sample_window_ms),
            .rect = from,
            .region = self.region,
            .reduced_motion = self.reducedMotion(),
        }) orelse return;
        self.placement.setRectangle(self.descriptor, g.target(from), self.origin, self.region);
        const to = self.rect();
        self.apply(to);
        self.swipe.phase = .glide;
        self.swipe.glide_axes = 0;
        const allocator = self.layer.cx.allocator;
        const axes = [_]struct { prop: ui.fx.animation.AnimatableProp, axis: float_swipe.GlideAxis, offset: f32, bit: u2 }{
            .{ .prop = .translate_x, .axis = g.x, .offset = from.x - to.x, .bit = 1 },
            .{ .prop = .translate_y, .axis = g.y, .offset = from.y - to.y, .bit = 2 },
        };
        for (axes) |a| {
            if (!a.axis.moves() or a.offset == 0) continue;
            self.swipe.glide_axes |= a.bit;
            ui.fx.animation.animateNode(self.node, allocator, .{ .prop = a.prop, .from = a.offset, .to = 0, .duration = a.axis.duration_ms / 1000, .easing = float_card_motion.easing(a.axis.curve), .restart = true, .on_complete = if (a.bit == 1) glideDoneX else glideDoneY, .on_complete_ctx = self });
        }
        if (self.swipe.glide_axes == 0) self.swipe.phase = .idle;
        self.syncHandles();
        self.layer.cx.requestRedraw();
    }

    fn glideDoneX(raw: *anyopaque) void {
        glideAxisDone(@ptrCast(@alignCast(raw)), 1);
    }

    fn glideDoneY(raw: *anyopaque) void {
        glideAxisDone(@ptrCast(@alignCast(raw)), 2);
    }

    fn glideAxisDone(self: *Card, bit: u2) void {
        if (self.disposed or self.swipe.phase != .glide) return;
        self.swipe.glide_axes &= ~bit;
        if (self.swipe.glide_axes == 0) self.endGlide();
    }

    /// Land a glide at once on its target (the placement already is the landing rectangle).
    fn endGlide(self: *Card) void {
        if (self.swipe.phase != .glide) return;
        self.swipe.phase = .idle;
        self.swipe.glide_axes = 0;
        self.snapProp(.translate_x, 0);
        self.snapProp(.translate_y, 0);
        self.swipe.offset_x = 0;
        self.swipe.offset_y = 0;
        self.syncHandles();
        self.layer.cx.requestRedraw();
    }

    /// A press mid glide: the card stops where it is drawn now, and that is its placement.
    fn takeOverGlide(self: *Card) void {
        if (self.swipe.phase != .glide) return;
        var here = self.rect();
        here.x += self.node.style.translate_x;
        here.y += self.node.style.translate_y;
        self.placement.setRectangle(self.descriptor, here, self.origin, self.region);
        self.apply(self.rect());
        self.endGlide();
    }

    /// For probes and tests: inertia in flight.
    pub fn gliding(self: *const Card) bool {
        return self.swipe.phase == .glide;
    }

    fn swipeCancel(self: *Card) void {
        self.swipe.eligible = false;
        self.setGripHeld(false);
        if (self.swipe.phase == .idle and (self.swipe.offset_x != 0 or self.swipe.offset_y != 0)) self.setOffset(0, 0);
    }

    /// Jump a node property (replacing any animation of it, so later animations start from here).
    fn snapProp(self: *Card, prop: ui.fx.animation.AnimatableProp, value: f32) void {
        ui.fx.animation.animateNode(self.node, self.layer.cx.allocator, .{ .prop = prop, .from = value, .to = value, .duration = 0, .restart = true });
    }

    fn setOffset(self: *Card, x: f32, y: f32) void {
        if (x != self.swipe.offset_x) self.snapProp(.translate_x, x);
        if (y != self.swipe.offset_y) self.snapProp(.translate_y, y);
        self.swipe.offset_x = x;
        self.swipe.offset_y = y;
        self.layer.cx.requestRedraw();
    }

    fn reducedMotion(self: *const Card) bool {
        return ui.fx.anchor_transition.reducedMotion(self.layer.cx);
    }

    /// Back to the docked position (180 ms ease-out; reduce motion: no displacement animation).
    fn springBack(self: *Card) void {
        const t = self.layer.swipe_tokens;
        if (self.swipe.offset_y == 0 and self.swipe.offset_x == 0) return;
        if (self.reducedMotion()) return self.setOffset(0, 0);
        self.swipe.phase = .spring;
        self.swipe.offset_x = 0;
        self.swipe.offset_y = 0;
        const allocator = self.layer.cx.allocator;
        ui.fx.animation.animateNode(self.node, allocator, .{ .prop = .translate_x, .to = 0, .duration = t.spring_ms / 1000, .easing = float_card_motion.easing(t.spring_curve) });
        ui.fx.animation.animateNode(self.node, allocator, .{ .prop = .translate_y, .to = 0, .duration = t.spring_ms / 1000, .easing = float_card_motion.easing(t.spring_curve), .on_complete = springDone, .on_complete_ctx = self });
        self.syncHandles();
        self.layer.cx.requestRedraw();
    }

    fn springDone(raw: *anyopaque) void {
        const self: *Card = @ptrCast(@alignCast(raw));
        if (self.disposed or self.swipe.phase != .spring) return;
        self.swipe.phase = .idle;
        self.syncHandles();
        self.layer.cx.requestRedraw();
    }

    /// Slide out of the view and hand the card to the owner's `minimize`. The placement goes back to
    /// where the drag started, so restoring brings the card back exactly as it was.
    fn swipeCollapse(self: *Card, velocity: f32) void {
        const t = self.layer.swipe_tokens;
        const before = self.rect();
        const visual_x = before.x + self.swipe.offset_x;
        const visual_y = before.y + self.swipe.offset_y;
        if (self.swipe.start_geometry) |geometry| {
            self.placement.restoreGeometry(geometry);
            self.placement.updateBounds(self.descriptor, self.origin, self.region);
        }
        const home = self.rect();
        self.apply(home);
        self.setOffset(visual_x - home.x, visual_y - home.y);
        self.swipe.phase = .slide;
        self.swipe.arrival = true;
        self.swipe.reduced = self.reducedMotion();
        self.noteAnchor("swipe");
        const allocator = self.layer.cx.allocator;
        if (self.swipe.reduced) {
            ui.fx.animation.animateNode(self.node, allocator, .{ .prop = .opacity, .to = 0, .duration = t.reduced_fade_ms / 1000, .easing = float_card_motion.easing(t.collapse_curve), .on_complete = slideDone, .on_complete_ctx = self });
        } else {
            const slide = float_swipe.slideOut(t, velocity, visual_y, self.exitY());
            self.swipe.offset_y += slide.distance;
            ui.fx.animation.animateNode(self.node, allocator, .{ .prop = .translate_y, .to = self.swipe.offset_y, .duration = slide.duration_ms / 1000, .easing = float_card_motion.easing(slide.curve) });
            ui.fx.animation.animateNode(self.node, allocator, .{ .prop = .opacity, .to = 0, .duration = t.collapse_ms / 1000, .easing = float_card_motion.easing(t.collapse_curve), .on_complete = slideDone, .on_complete_ctx = self });
        }
        self.syncHandles();
        self.layer.cx.requestRedraw();
        // The card's own collapse semantics (AI: back into the launcher); its `present` hides the
        // card without a Z12 run while the slide is in flight.
        const handled = if (self.callbacks.action) |callback| callback(self.callbacks.ctx, .minimize) else false;
        if (!handled) {
            self.swipe.arrival = false;
            self.swipeFinish(false);
        }
    }

    fn slideDone(raw: *anyopaque) void {
        const self: *Card = @ptrCast(@alignCast(raw));
        if (self.disposed or self.swipe.phase != .slide) return;
        // The owner hid the card (its `present` saw shown = false): rest collapsed. Otherwise it
        // kept the card open after all: put it back.
        self.swipeFinish(!self.presented_visible);
    }

    /// End a slide: rest collapsed (`hide`) or back in place, transform and opacity reset.
    fn swipeFinish(self: *Card, hide: bool) void {
        self.endGlide();
        self.swipe.phase = .idle;
        if (hide) {
            self.anchor_flight = false;
            if (self.panelTransition()) |t| t.snapTo(true) else self.node.setDisplay(.none);
        }
        self.snapProp(.opacity, 1);
        self.node.setOpacity(1);
        self.setOffset(0, 0);
        self.syncHandles();
        self.layer.cx.requestRedraw();
        if (hide) if (self.callbacks.rest) |callback| callback(self.callbacks.ctx, .collapsed);
    }

    /// The owner's collapse target (e.g. the AI launcher) asks once whether the card just went
    /// away by a swipe, to fade itself in at the anchor corner (`float_swipe.Tokens.icon_*`).
    pub fn takeSwipeArrival(self: *Card) bool {
        const arrival = self.swipe.arrival;
        self.swipe.arrival = false;
        return arrival;
    }

    /// Whether the last swipe collapse fades only (reduce motion), for the collapse target.
    pub fn swipeReduced(self: *const Card) bool {
        return self.swipe.reduced;
    }

    /// For probes: the grip is held.
    pub fn gripHeld(self: *const Card) bool {
        return self.swipe.held;
    }

    /// The owner opened the card explicitly (entry button, shortcut, menu): focus goes in.
    /// `trigger`: the entry button, where focus returns when nothing had focus at the open.
    pub fn focusOpened(self: *Card, trigger: ?*ui.Node) void {
        if (!self.disposed) self.focus.opened(trigger);
    }

    /// The owner closed the card explicitly: focus goes back to where it was when it opened
    /// (only while it is still in the card or nowhere).
    pub fn focusClosed(self: *Card) void {
        if (!self.disposed) self.focus.closed();
    }

    /// Bubble-phase key on the card root: inputs, menus and inner layers had it first.
    fn nodeKey(key: ui.events.KeyCode, mods: ui.events.Modifiers, raw: ?*anyopaque) ui.events.EventResult {
        const self: *Card = @ptrCast(@alignCast(raw orelse return .ignored));
        if (self.disposed or mods.super or mods.ctrl or mods.alt or mods.shift) return .ignored;
        if (!self.focus.escapeCloses(key) or !self.descriptor.supports(.close)) return .ignored;
        self.close();
        return .stop;
    }

    fn nodeCapture(event: ui.events.Event, raw: ?*anyopaque) ui.events.EventResult {
        const self: *Card = @ptrCast(@alignCast(raw orelse return .ignored));
        if (event == .mouse_down) {
            // A press anywhere on a gliding card catches it where it is (before the grip / a handle
            // sees the press, so the drag that may follow starts from that position).
            self.takeOverGlide();
            self.layer.raise(self);
        }
        return .ignored;
    }

    // ── Presentation (Z12) ──────────────────────────────────────────────────────────────────

    /// The card's one anchor transition, owned by the card's scope for the card's whole life
    /// (zenit `AnchorTransition.attach`, ANCHOR_TRANSITION.md §4). The card node never leaves the
    /// layer, so the transition never has to be remade; owners say what to present (`present`,
    /// `unfoldFrom`, `hideNow`), never touch the transition or the node's `display`.
    fn mountTransition(self: *Card, scope: *ui.Scope) void {
        const cx = self.layer.cx;
        // Rest collapsed with `display: none` saved as flex, so an expand shows the node.
        const was_hidden = self.node.style.display == .none;
        if (was_hidden) self.node.setDisplay(.flex);
        const t = ui.fx.AnchorTransition.attach(scope, cx, self.node, .{ .on_complete = transitionRest, .on_complete_ctx = self }) catch {
            if (was_hidden) self.node.setDisplay(.none);
            return;
        };
        if (was_hidden) t.snapTo(true);
        self.transition = t;
    }

    fn panelTransition(self: *Card) ?*ui.fx.AnchorTransition {
        return self.transition;
    }

    fn transitionRest(ctx: ?*anyopaque, rest_phase: Phase) void {
        const self: *Card = @ptrCast(@alignCast(ctx orelse return));
        self.anchor_flight = false;
        self.syncHandles();
        self.layer.cx.requestRedraw();
        if (self.callbacks.rest) |callback| callback(self.callbacks.ctx, rest_phase);
    }

    fn noteAnchor(self: *Card, label: []const u8) void {
        self.anchor_slot +%= 1;
        const slot = &self.anchor_names[self.anchor_slot];
        const n = @min(label.len, slot.len);
        @memcpy(slot[0..n], label[0..n]);
        self.anchor_label = slot[0..n];
    }

    /// The tab anchor of `tab`, null when its tab is not on the strip (closed).
    fn tabAnchor(self: *Card, tab: ?u64, buffer: []u8) ?[]const u8 {
        const id = tab orelse return null;
        const name = tab_anchor.name(buffer, id) orelse return null;
        if (self.layer.cx.motion_anchors.lookup(self.layer.cx, name) == null) return null;
        return name;
    }

    fn anchorOf(self: *Card, mode: TransitionMode, rect_: ?Rect) ui.fx.anchor_transition.Anchor {
        if (mode == .fade or !self.descriptor.supports(.open_from_anchor)) return .none;
        const r = rect_ orelse return .none;
        return .{ .rect = .{ .x = r.x, .y = r.y, .w = r.width, .h = r.height } };
    }

    /// Show / hide the card for this frame's owner state. Open / close unfold from / fold into the
    /// open anchor; a tab switch folds the leaving tab's card into that tab on the strip and unfolds
    /// the arriving tab's card from its own tab. Reversals retarget mid flight without queueing.
    pub fn present(self: *Card, p: Presentation) void {
        // Hidden mid glide: land it first, so the fold flies from (and a reopen returns to) the target.
        if (self.swipe.phase == .glide and !p.shown) self.endGlide();
        // Swipe collapse in flight: the slide is the exit; a reopen mid slide ends it and unfolds as usual.
        if (self.swipe.phase == .slide) {
            if (!p.shown) {
                self.presented_visible = false;
                self.presented_tab = p.tab;
                self.presented_away = false;
                return;
            }
            self.swipeFinish(true);
        }
        const visible = p.shown;
        const same_content = if (p.tab) |tab| if (self.presented_tab) |shown| tab == shown else false else false;
        if (visible == self.presented_visible and (!visible or same_content)) return;
        self.presented_visible = visible;
        const t = self.panelTransition() orelse {
            self.presented_tab = p.tab;
            self.anchor_flight = false;
            self.node.setDisplay(if (visible) .flex else .none);
            return;
        };
        const folds = self.descriptor.supports(.fold_to_tab);
        // Z12b: the mode is read when a run starts; `setTokens` during a run applies at its rest.
        const mode = self.layer.currentMode();
        t.setTokens(float_card_motion.tokens(mode));
        var buffer: [48]u8 = undefined;
        if (visible) {
            const content_changed = self.presented_tab != null and !same_content;
            const from_tab = folds and !p.explicit and (p.swapped or self.presented_away or content_changed);
            // The flying snapshot shows another tab's content: rest it before unfolding this one.
            if (content_changed and t.phase() != .collapsed) t.snapTo(true);
            self.presented_tab = p.tab;
            self.presented_away = false;
            if (from_tab) {
                self.anchor_flight = false;
                const name = self.tabAnchor(p.tab, &buffer);
                const fly = name != null and mode == .anchor;
                self.noteAnchor(if (fly) name.? else "none");
                t.expand(if (fly) .{ .id = name.? } else .none);
            } else {
                const anchor = self.anchorOf(mode, p.anchor);
                self.anchor_flight = anchor != .none;
                self.noteAnchor(if (anchor != .none) "anchor" else "none");
                t.expand(anchor);
            }
            return;
        }
        // Hidden: the current tab moved away from the card's tab (fold into it), or the card was
        // closed on its own tab (fold into the open anchor).
        const swapped = p.swapped and self.presented_tab != null and !same_content;
        const folding = if (swapped) self.presented_tab else p.tab;
        const leaving = !p.explicit and (swapped or (p.tab != null and (p.current_tab == null or p.current_tab.? != p.tab.?)));
        if (leaving and folds) {
            self.presented_tab = folding;
            self.anchor_flight = false;
            self.presented_away = true;
            // A closed tab's card closes with it (no motion).
            const name = self.tabAnchor(folding, &buffer) orelse {
                self.noteAnchor("none");
                t.snapTo(true);
                return;
            };
            self.noteAnchor(if (mode == .anchor) name else "none");
            t.collapse(if (mode == .anchor) .{ .id = name } else .none);
            return;
        }
        self.presented_tab = p.tab;
        self.presented_away = leaving;
        const anchor = if (leaving) ui.fx.anchor_transition.Anchor.none else self.anchorOf(mode, p.anchor);
        self.anchor_flight = anchor != .none;
        self.noteAnchor(if (anchor != .none) "anchor" else "none");
        t.collapse(anchor);
    }

    /// Dock to split (float-split): the content went into a tab body pane, which flies in from this
    /// card's rectangle; the card itself leaves without motion. Its placement (the dropped rectangle)
    /// is kept, so floating again returns to it.
    pub fn hideForDock(self: *Card) void {
        self.hideNow();
        self.presented_tab = null;
        self.presented_away = false;
    }

    /// Float again from a tab body pane (float-split): the card (already positioned by `update`)
    /// unfolds from the pane rectangle `from` (window coordinates) in `anchor` mode, and fades in
    /// place in `fade` mode / with reduced motion. `tab` is the owner tab the card now belongs to.
    pub fn unfoldFrom(self: *Card, tab: ?u64, from: ?Rect) void {
        self.cancel();
        if (self.swipe.phase != .idle) self.swipeFinish(false);
        self.presented_visible = true;
        self.presented_tab = tab;
        self.presented_away = false;
        self.anchor_flight = false;
        const t = self.panelTransition() orelse {
            self.node.setDisplay(.flex);
            return;
        };
        const mode = self.layer.currentMode();
        t.setTokens(float_card_motion.placeTokens(mode));
        if (t.phase() != .collapsed) t.snapTo(true);
        const anchor: ui.fx.anchor_transition.Anchor = if (mode == .anchor) if (from) |r| .{ .rect = .{ .x = r.x, .y = r.y, .w = r.width, .h = r.height } } else .none else .none;
        self.noteAnchor(if (anchor != .none) "pane" else "none");
        t.expand(anchor);
    }

    /// The anchor label of the current / last run (`anchor`, `pane`, `workspace.tab.<id>`, `none`).
    pub fn anchorLabel(self: *const Card) []const u8 {
        return self.anchor_label;
    }

    /// Close without motion (e.g. the workspace lost its last tab).
    pub fn hideNow(self: *Card) void {
        self.cancel();
        if (self.swipe.phase != .idle) self.swipeFinish(false);
        self.presented_visible = false;
        self.anchor_flight = false;
        if (self.panelTransition()) |t| t.snapTo(true) else self.node.setDisplay(.none);
    }

    pub fn phase(self: *const Card) Phase {
        if (self.swipe.phase == .slide) return .collapsing;
        return if (self.transition) |t| t.phase() else if (self.node.style.display == .none) .collapsed else .expanded;
    }

    /// The flight in progress already draws its picture (a visible frame). Between the trigger and the
    /// first drawn frame (the expand captures its picture first) nothing of the card is on screen yet.
    pub fn flightShowing(self: *const Card) bool {
        const t = self.transition orelse return false;
        const f = t.currentFrame() orelse return false;
        return f.opacity > 0.001;
    }

    /// The flight in progress draws an opaque frame over all of `r` (window coordinates), so what
    /// lies under it (the open anchor, e.g. a launcher icon) can appear / go without a visible change.
    pub fn flightCovers(self: *const Card, r: Rect) bool {
        const t = self.transition orelse return false;
        const f = t.currentFrame() orelse return false;
        return f.opacity >= 0.98 and f.rect.x <= r.x and f.rect.y <= r.y and
            f.rect.x + f.rect.w >= r.x + r.width and f.rect.y + f.rect.h >= r.y + r.height;
    }

    /// The frame drawn by the transition this frame, else the anchor it rests in (collapsed) or the
    /// card itself (expanded). Window coordinates; for probes and tests.
    pub fn presentedRect(self: *const Card) ui.ComputedRect {
        // A swipe offset is a translate of the card node, already in the frame's global rect.
        if (self.swipe.phase != .idle or self.node.style.translate_x != 0 or self.node.style.translate_y != 0) return self.frame.globalRect();
        const t = self.transition orelse return self.frame.globalRect();
        if (t.currentFrame()) |frame| return .{ .x = frame.rect.x, .y = frame.rect.y, .w = frame.rect.w, .h = frame.rect.h };
        return switch (t.phase()) {
            .collapsed => if (t.last_anchor) |a| .{ .x = a.x, .y = a.y, .w = a.w, .h = a.h } else .{ .x = 0, .y = 0, .w = 0, .h = 0 },
            else => self.frame.globalRect(),
        };
    }

    /// The opacity the transition draws this frame (1 at rest expanded, 0 at rest collapsed); for probes.
    pub fn presentedOpacity(self: *const Card) f32 {
        if (self.swipe.phase == .slide) return self.node.getOpacity();
        const t = self.transition orelse return if (self.node.style.display == .none) 0 else 1;
        if (t.currentFrame()) |frame| return frame.opacity;
        return if (t.phase() == .collapsed) 0 else 1;
    }

    fn detachFromLayer(self: *Card) void {
        self.dispose();
        for (self.layer.cards.items, 0..) |card, index| if (card == self) {
            _ = self.layer.cards.swapRemove(index);
            break;
        };
    }

    fn dispose(self: *Card) void {
        if (self.disposed) return;
        self.disposed = true;
        self.cancel();
        if (self.chrome) |chrome| if (chrome.vm.handler.ctx == @as(?*anyopaque, @ptrCast(self))) chrome.setActionHandler(.{});
        // The transition belongs to the card's scope (released after this cleanup).
        self.transition = null;
        if (self.node.behavior.events.capture_context == @as(?*anyopaque, @ptrCast(self))) {
            self.node.behavior.events.on_event_capture = null;
            self.node.behavior.events.capture_context = null;
        }
        if (self.node.behavior.events.key_context == @as(?*anyopaque, @ptrCast(self))) {
            self.node.behavior.events.on_key_down = null;
            self.node.behavior.events.key_context = null;
        }
        self.focus.sync(false);
        if (self.grip) |grip| if (grip.behavior.events.capture_context == @as(?*anyopaque, @ptrCast(self))) {
            grip.behavior.events.on_event_capture = null;
            grip.behavior.events.capture_context = null;
        };
        for (self.bindings, 0..) |binding, index| if (binding) |value| {
            const node = if (index == 0) self.grip.? else self.handles[index - 1].?;
            if (node.behavior.events.event_context == @as(*anyopaque, @ptrCast(value))) {
                node.behavior.events.on_event = null;
                node.behavior.events.event_context = null;
            }
        };
    }
};
