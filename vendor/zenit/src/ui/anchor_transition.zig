//! Anchor transition: collapse a node subtree into an anchor rect and expand it back out
//! (ZeroWork Z12). Design: docs/ANCHOR_TRANSITION.md. Geometry and clock:
//! animation/anchor_motion.zig; the genie mesh: src/genie_warp.zig.
//!
//! Static-texture model: while a run is in flight only one picture of the node is drawn — its
//! snapshot, rasterized once by the renderer into a cached texture (stable surface id) and then
//! only composited, through a genie mesh (`.anchor`, default) or an affine frame. The node and its
//! children take no part in layout, paint or hit testing meanwhile (`Hold`: an out-of-flow node is
//! `display: none`; a node in flow keeps its own box, its children are `display: none`). At rest:
//!   * expanded: the node renders and hit-tests normally; no layer, no snapshot is kept;
//!   * collapsed: the node is `display: none`; its opacity and hit-test flag are its own again.
//!
//! Collapse freezes what was displayed last frame (`Snapshot.captureDisplayed`). Expand from rest
//! renders the node once, privately, in an after-layout round of the request frame (its content may
//! have changed), then takes it out of layout again; the landing frame hands back to the live node.
//! Home and anchor rects are taken once per run; only a real change (window resized, anchor laid out
//! anew, a new anchor) retargets, blended so the picture stays continuous.
const std = @import("std");
const core = @import("core.zig");
const motion_mod = @import("animation/anchor_motion.zig");
const render_engine = @import("core/render_engine/mod.zig");
const a11y_preferences = @import("a11y/preferences.zig");
const genie_warp_mod = @import("zenit_genie_warp");

const Allocator = std.mem.Allocator;
const Cx = core.Cx;
const Node = core.Node;
const NodeHandle = core.NodeHandle;
const Scope = core.Scope;
const Snapshot = core.Snapshot;
const ComputedRect = core.ComputedRect;
const DrawContext = render_engine.DrawContext;
const overlay_stack = core.overlay_stack_mod;

pub const Rect = motion_mod.Rect;
pub const Tokens = motion_mod.Tokens;
pub const Phase = motion_mod.Phase;
pub const Frame = motion_mod.Frame;
pub const Motion = motion_mod.Motion;
pub const ReducedMotion = motion_mod.ReducedMotion;
pub const Mode = motion_mod.Mode;
pub const default_tokens = motion_mod.default_tokens;
/// In-place preset (Z12b): fade out while shrinking slightly, reverse on the way in.
pub const fade_scale_tokens = motion_mod.fade_scale_tokens;
/// First-tier picture (curved path + scale + fade) without the genie mesh.
pub const affine_tokens = motion_mod.affine_tokens;
pub const Shape = motion_mod.Shape;
pub const GenieWarp = motion_mod.GenieWarp;

/// Where a collapse goes / an expand comes from. Re-resolved every frame of a run.
pub const Anchor = union(enum) {
    /// No anchor: the run degrades to the reduced-motion form (fade in place).
    none,
    /// A fixed rect in window coordinates.
    rect: Rect,
    /// A live node: its window rect, clamped into its clipping ancestors and the viewport
    /// (a tab scrolled out of its strip resolves to the strip's nearest visible end). Held by
    /// identity, never owned; a freed node falls back to the last resolved rect.
    node: *Node,
    /// A node registered under this name with `Cx.motion_anchors` (Yix `motionAnchor`). Copied.
    id: []const u8,
};

pub const CompletionFn = *const fn (ctx: ?*anyopaque, phase: Phase) void;

pub const Options = struct {
    tokens: Tokens = default_tokens,
    /// Overlay z-index of the flying snapshot (null = overlay stack default order).
    z_index: ?i16 = null,
    /// How a run keeps the node out of layout and paint (`.auto`: by its position).
    hold: Hold = .auto,
    /// Where the flying picture is drawn. null = an overlay above everything (the default).
    /// A node (usually the window root): the picture is a full-size child of it with `z_index`
    /// (default 0), so things that stack above the node's place in the live tree (a launcher
    /// button over a docked pane) stay above the picture too, and the landing frame matches.
    layer_parent: ?*Node = null,
    /// Called when a run comes to rest (`.collapsed` / `.expanded`), also for instant runs.
    on_complete: ?CompletionFn = null,
    on_complete_ctx: ?*anyopaque = null,
};

fn toRect(r: ComputedRect) Rect {
    return .{ .x = r.x, .y = r.y, .w = r.w, .h = r.h };
}

fn toComputed(r: Rect) ComputedRect {
    return .{ .x = r.x, .y = r.y, .w = r.w, .h = r.h };
}

/// Effective "reduce motion" for this window: the app / renderer flags or the system setting.
pub fn reducedMotion(cx: *const Cx) bool {
    return cx.reduced_motion or cx.renderer_reduced_motion or a11y_preferences.reduceMotion();
}

/// Window rect of `node` clamped into each clipping ancestor and then the viewport.
pub fn resolveNodeAnchor(cx: *const Cx, node: *const Node) Rect {
    var r = toRect(node.globalRect());
    var cur = node.parent;
    while (cur) |n| : (cur = n.parent) {
        if (n.style.overflow.clips() or n.style.overflow_hidden) {
            r = motion_mod.clampAnchor(r, toRect(n.globalRect()));
        }
    }
    return motion_mod.clampAnchor(r, .{ .w = cx.viewport.width, .h = cx.viewport.height });
}

// ---------------------------------------------------------------------------------------------
// Named anchors (Cx.motion_anchors, Yix `motionAnchor`)

/// Per-window registry of named anchor nodes. Entries hold the node by identity (never owned)
/// and are dropped by the registering scope. The same name registered twice resolves to the
/// newest registration.
pub const AnchorRegistry = struct {
    allocator: Allocator,
    entries: std.ArrayList(Entry) = .empty,
    next_token: u32 = 1,

    const Entry = struct {
        token: u32,
        name: []u8,
        node: *Node,
        identity: NodeHandle,
    };

    pub fn init(allocator: Allocator) AnchorRegistry {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *AnchorRegistry) void {
        for (self.entries.items) |e| self.allocator.free(e.name);
        self.entries.deinit(self.allocator);
    }

    /// Register `node` as `name` (copied). Returns the token for `unregister`.
    pub fn register(self: *AnchorRegistry, cx: *Cx, name: []const u8, node: *Node) !u32 {
        const generation = try cx.node_registry.trackGeneration(node);
        const owned = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned);
        const token = self.next_token;
        try self.entries.append(self.allocator, .{
            .token = token,
            .name = owned,
            .node = node,
            .identity = .{ .id = node.id, .generation = generation },
        });
        self.next_token +%= 1;
        if (self.next_token == 0) self.next_token = 1;
        return token;
    }

    /// Change the name of a registration (a `motionAnchor` bound to a source).
    pub fn rename(self: *AnchorRegistry, token: u32, name: []const u8) !void {
        for (self.entries.items) |*e| {
            if (e.token != token) continue;
            if (std.mem.eql(u8, e.name, name)) return;
            const owned = try self.allocator.dupe(u8, name);
            self.allocator.free(e.name);
            e.name = owned;
            return;
        }
    }

    pub fn unregister(self: *AnchorRegistry, token: u32) void {
        for (self.entries.items, 0..) |e, i| {
            if (e.token != token) continue;
            self.allocator.free(e.name);
            _ = self.entries.orderedRemove(i);
            return;
        }
    }

    /// The live node registered as `name` (newest first), or null.
    pub fn lookup(self: *const AnchorRegistry, cx: *const Cx, name: []const u8) ?*Node {
        if (name.len == 0) return null;
        var i = self.entries.items.len;
        while (i > 0) {
            i -= 1;
            const e = self.entries.items[i];
            if (!std.mem.eql(u8, e.name, name)) continue;
            if (!cx.node_registry.isCurrentIdentity(e.identity, e.node)) continue;
            return e.node;
        }
        return null;
    }
};

// ---------------------------------------------------------------------------------------------
// The transition

/// How a run keeps the node out of layout and paint while its texture flies.
pub const Hold = enum {
    /// `.hide` for out-of-flow nodes (`position: absolute`), `.keep_box` for nodes in flow.
    auto,
    /// `display: none` on the node for the whole run (out of layout, paint, hit testing).
    hide,
    /// The node keeps its own box in its parent's layout (siblings do not reflow) but paints
    /// nothing and takes no hits; its children are `display: none`, so its content is neither laid
    /// out nor painted. An auto-sized node shrinks to its padding meanwhile.
    keep_box,
};

/// Process-wide counters of anchor-transition runs (cumulative; tests and the e2e harness read
/// them). The subtree counters are filled only with `ZENIT_ANCHOR_FLIGHT_PROBE=1` (or
/// `probe_override = true`), since they walk the subtree every frame.
pub const FlightStats = struct {
    runs: u64 = 0,
    /// Frames drawn by a run in flight (texture only).
    flight_frames: u64 = 0,
    /// Probe: flight frames in which any descendant of the node was laid out, and how many
    /// descendant layouts that was. Both stay 0: the content does not take part in layout.
    subtree_layout_frames: u64 = 0,
    subtree_layouts: u64 = 0,
    /// Probe: display items of the node's subtree painted in flight frames (stays 0).
    subtree_paint_items: u64 = 0,
    /// One-time private renders of the subtree (an expand from rest; content may have changed).
    captures: u64 = 0,
    /// One-time home re-reads (the window changed size during an expand).
    home_refreshes: u64 = 0,
    /// Target changes followed during a run (window resize, anchor moved).
    retargets: u64 = 0,
    /// Runs that came to rest handing the picture back to the live node.
    landings: u64 = 0,
};

pub var flight_stats: FlightStats = .{};
/// Forces the subtree probe on / off (null = `ZENIT_ANCHOR_FLIGHT_PROBE`).
pub var probe_override: ?bool = null;

fn probeEnabled() bool {
    if (probe_override) |v| return v;
    return @import("zenit_environment").flag("ZENIT_ANCHOR_FLIGHT_PROBE");
}

/// Seconds over which a run blends onto a moved target (window resize, anchor moved).
const retarget_blend_s: f32 = 0.12;

/// Reserved index range of `layer_tree.LayerId` for transition surfaces (real layers never get
/// near it): the GPU keeps one cached texture per transition under this identity.
var next_surface: u32 = 0;
fn allocSurfaceId() u32 {
    next_surface +%= 1;
    return 0xF00000 + (next_surface % 0x0FFFFE);
}

pub const AnchorTransition = struct {
    allocator: Allocator,
    cx: *Cx,
    node: *Node,
    identity: NodeHandle,
    options: Options,

    motion: Motion = .{},
    anchor: Anchor = .none,
    /// Owned copy for `.id` anchors.
    anchor_name: []u8 = &.{},
    anchor_node_identity: NodeHandle = .{ .id = 0 },
    last_anchor: ?Rect = null,

    snapshot: ?*Snapshot = null,
    snap_w: f32 = 0,
    snap_h: f32 = 0,
    /// GPU texture identity of the flying picture (stable for this transition).
    surface_id: u32 = 0,
    /// Version of the snapshot under `surface_id` (the renderer's cache key for its content).
    snap_version: u32 = 0,
    /// Frame drawn by the layer this frame; null = draw nothing.
    frame: ?Frame = null,
    /// The run's form was decided as reduced (system setting or no anchor).
    reduced_run: bool = false,
    /// Tokens set while a run was in flight; adopted when it comes to rest so a run never
    /// changes shape (mode, durations) halfway.
    pending_tokens: ?Tokens = null,

    layer: ?*Node = null,
    layer_identity: NodeHandle = .{ .id = 0 },
    overlay_handle: ?overlay_stack.LayerHandle = null,

    hooked: bool = false,
    /// The node's paint and hit testing are suppressed by this transition.
    suppressed: bool = false,
    saved_opacity: f32 = 1,
    saved_hit: bool = true,
    /// The node's display is none (set by this transition): collapsed at rest, or held `.hide`.
    hidden: bool = false,
    saved_display: core.Display = .flex,
    /// `.keep_box` hold: the children this transition set to `display: none`.
    kept: std.ArrayList(KeptChild) = .empty,
    holding: bool = false,

    /// Frozen geometry of the run (window coordinates), taken once when it starts.
    run_home: Rect = .{},
    run_anchor: ?Rect = null,
    /// The anchor is re-read once on the first frame (this frame's layout), then only on change.
    anchor_fresh: bool = false,
    anchor_epoch: u64 = 0,
    run_viewport: [2]f32 = .{ 0, 0 },
    /// Blend from the previous targets onto moved ones (1 = done).
    blend_t: f32 = 1,
    blend_home: Rect = .{},
    blend_anchor: ?Rect = null,

    /// Work that needs a layout round of this frame (see `afterLayout`).
    stage: Stage = .idle,
    /// `.keep_box`: the node's own layout epoch when its home was last read.
    home_epoch: u64 = 0,
    /// The home refresh in progress also renders the content again (the box changed size).
    recapture: bool = false,
    /// Box-moved refreshes this run (bounded: a box that changes size with its hold must not loop).
    box_refreshes: u8 = 0,
    /// Flight frames of the run so far.
    run_frames: u32 = 0,
    /// `.keep_box` expand: frames left to confirm the box stays put before the run starts.
    settling: bool = false,
    settle_frames: u8 = 0,
    /// The capture already let the subtree's before-render hooks see the final layout.
    hooks_synced: bool = false,
    capture_attempts: u8 = 0,

    /// Subtree probe (see FlightStats).
    probe: ?Probe = null,

    first_tick: bool = true,
    last_tick_ms: f64 = 0,
    disposed: bool = false,
    /// An expand reached home: this frame draws the texture exactly at home (texel for pixel on
    /// the live node), the next frame hands over, so the handover changes no pixel.
    home_frame: bool = false,
    home_frame_ms: f64 = 0,

    const KeptChild = struct { node: *Node, identity: NodeHandle, display: core.Display };

    const Stage = enum {
        idle,
        /// The node is shown (paint suppressed) for the one-time capture of an expand.
        capture,
        /// The node is shown (paint suppressed) to re-read its home after a window resize.
        refresh_home,
        /// The node went back out of layout; re-baseline the probe after that relayout.
        rebaseline,
    };

    const Probe = struct {
        /// Descendant node id -> its layout epoch when last checked.
        ids: std.AutoHashMapUnmanaged(u32, u64) = .empty,
        /// The previous frame was a flight frame (its display list is the one read now).
        prev_flight: bool = false,
    };

    /// Create a transition for `node`. Caller owns it (`destroy`), or use `attach`.
    pub fn create(cx: *Cx, node: *Node, options: Options) !*AnchorTransition {
        const generation = try cx.node_registry.trackGeneration(node);
        const self = try cx.allocator.create(AnchorTransition);
        self.* = .{
            .allocator = cx.allocator,
            .cx = cx,
            .node = node,
            .identity = .{ .id = node.id, .generation = generation },
            .options = options,
            .surface_id = allocSurfaceId(),
        };
        return self;
    }

    /// Create a transition owned by `scope` (destroyed with it).
    pub fn attach(scope: *Scope, cx: *Cx, node: *Node, options: Options) !*AnchorTransition {
        const self = try create(cx, node, options);
        try scope.adoptResource(@ptrCast(self), struct {
            fn destroy(ptr: *anyopaque, _: Allocator) void {
                const t: *AnchorTransition = @ptrCast(@alignCast(ptr));
                t.destroy();
            }
        }.destroy);
        return self;
    }

    /// Stop any run, give the node back (displayed, own opacity and hit testing, children shown)
    /// when it is still alive, drop the layer and the snapshot, and free the transition.
    pub fn destroy(self: *AnchorTransition) void {
        self.disposed = true;
        self.unhook();
        self.dropLayer(true);
        self.dropSnapshot();
        if (self.nodeAlive()) {
            self.releaseChildren();
            self.unsuppress();
            self.unhide();
        }
        self.kept.deinit(self.allocator);
        self.dropProbe();
        self.setAnchor(.none);
        self.allocator.destroy(self);
    }

    // -- queries --

    pub fn phase(self: *const AnchorTransition) Phase {
        if (self.home_frame) return .expanding;
        return self.motion.phase();
    }

    /// 0 = home, 1 = in the anchor.
    pub fn progress(self: *const AnchorTransition) f32 {
        return self.motion.progress;
    }

    /// The frame drawn this frame (window coordinates), null when nothing is in flight.
    pub fn currentFrame(self: *const AnchorTransition) ?Frame {
        return self.frame;
    }

    /// Collapsed at rest or heading there.
    pub fn isCollapsed(self: *const AnchorTransition) bool {
        return self.motion.target >= 1;
    }

    /// The geometry the run in flight aims at (window coordinates): taken once when the run
    /// started, changed only by a real target change (window resize, anchor moved).
    pub fn runGeometry(self: *const AnchorTransition) struct { home: Rect, anchor: ?Rect } {
        return .{ .home = self.run_home, .anchor = self.run_anchor };
    }

    /// Replace the motion tokens (e.g. switch `.anchor` <-> `.fade_scale`). At rest they apply
    /// at once; while a run is in flight they apply from the next run (the current one keeps its
    /// shape, so a reversal stays continuous).
    pub fn setTokens(self: *AnchorTransition, tokens: Tokens) void {
        if (self.motion.phase().isAnimating()) {
            self.pending_tokens = tokens;
            return;
        }
        self.pending_tokens = null;
        self.options.tokens = tokens;
    }

    /// The tokens the current (or next) run uses.
    pub fn motionTokens(self: *const AnchorTransition) Tokens {
        return self.options.tokens;
    }

    /// Change the anchor without starting a run (a run in flight retargets onto it).
    pub fn setAnchor(self: *AnchorTransition, anchor: Anchor) void {
        switch (anchor) {
            .id => |name| {
                if (self.anchor == .id and std.mem.eql(u8, self.anchor_name, name)) return;
                const owned = self.allocator.dupe(u8, name) catch {
                    // Keep the previous anchor; the run still has last_anchor to aim at.
                    return;
                };
                self.freeAnchorName();
                self.anchor_name = owned;
                self.anchor = .{ .id = owned };
            },
            .node => |n| {
                self.freeAnchorName();
                const generation = self.cx.node_registry.trackGeneration(n) catch {
                    self.anchor = .none;
                    return;
                };
                self.anchor = anchor;
                self.anchor_node_identity = .{ .id = n.id, .generation = generation };
            },
            else => {
                self.freeAnchorName();
                self.anchor = anchor;
            },
        }
        // A new anchor is a real target change: re-read it on the next frame.
        self.anchor_fresh = false;
    }

    fn freeAnchorName(self: *AnchorTransition) void {
        if (self.anchor_name.len > 0) self.allocator.free(self.anchor_name);
        self.anchor_name = &.{};
        if (self.anchor == .id) self.anchor = .none;
    }

    // -- requests --

    /// Collapse into `anchor` (or reverse an expand in flight). Collapsed / collapsing: only the
    /// anchor changes.
    pub fn collapse(self: *AnchorTransition, anchor: Anchor) void {
        self.setAnchor(anchor);
        self.request(.collapse);
    }

    /// Expand out of `anchor` back home (or reverse a collapse in flight).
    pub fn expand(self: *AnchorTransition, anchor: Anchor) void {
        self.setAnchor(anchor);
        self.request(.expand);
    }

    pub fn setCollapsed(self: *AnchorTransition, collapsed: bool, anchor: Anchor) void {
        if (collapsed) self.collapse(anchor) else self.expand(anchor);
    }

    /// Collapse / expand with the anchor already set (`setAnchor`).
    pub fn retarget(self: *AnchorTransition, collapsed: bool) void {
        self.request(if (collapsed) .collapse else .expand);
    }

    /// Jump to rest without animating (initial state, or the anchor's owner went away).
    pub fn snapTo(self: *AnchorTransition, collapsed: bool) void {
        if (!self.nodeAlive()) return;
        _ = self.motion.retarget(if (collapsed) .collapse else .expand);
        self.motion.finish();
        self.settleAt(false);
    }

    fn request(self: *AnchorTransition, dir: motion_mod.Direction) void {
        if (self.home_frame) {
            // Landing was one frame away: the run is at home, a collapse starts from there.
            self.home_frame = false;
            if (dir == .collapse) {
                _ = self.motion.retarget(.collapse);
                self.first_tick = true;
                self.cx.requestRedraw();
                return;
            }
            return;
        }
        if (self.disposed or !self.nodeAlive()) return;
        const was = self.motion.phase();
        if (!self.motion.retarget(dir)) return;
        const tokens = self.options.tokens;
        const reduced = reducedMotion(self.cx);
        if (reduced and tokens.reduced == .instant) {
            self.motion.finish();
            self.settle();
            return;
        }
        switch (was) {
            .expanded => {
                // Collapse from rest: freeze what is on screen now (rasterized once by the
                // renderer), take the node out of layout and paint at once.
                const snap = Snapshot.captureDisplayed(self.cx, self.node) catch null;
                const s = snap orelse {
                    self.motion.finish();
                    self.settle();
                    return;
                };
                self.adoptSnapshot(s);
                self.run_home = self.liveHomeRect();
                self.run_viewport = .{ self.cx.viewport.width, self.cx.viewport.height };
                self.blend_t = 1;
                self.run_anchor = if (self.options.tokens.usesAnchor()) self.resolveAnchor() else null;
                self.anchor_fresh = false;
                self.hold();
                self.startProbe();
                self.beginRun(reduced) catch {
                    self.motion.finish();
                    self.settle();
                };
            },
            .collapsed => {
                // Expand from rest: the content may have changed while it was away. Show the node
                // with paint suppressed for this frame's layout only, render it once privately in
                // an after-layout round (`tryCapture`), and take it out of layout again.
                self.unhide();
                self.suppress();
                self.stage = .capture;
                self.capture_attempts = 0;
                self.box_refreshes = 0;
                self.run_frames = 0;
                self.hooks_synced = false;
                self.settling = false;
                self.reduced_run = reduced;
                self.run_viewport = .{ self.cx.viewport.width, self.cx.viewport.height };
                self.blend_t = 1;
                self.anchor_fresh = false;
                self.hook() catch {
                    self.stage = .idle;
                    self.motion.finish();
                    self.settle();
                };
                flight_stats.runs += 1;
            },
            // Reversal in flight (or an expand still waiting for its capture).
            .collapsing, .expanding => {
                if (self.settling) {
                    // Reversed while settling: the picture flies from here, the node leaves layout.
                    self.settling = false;
                    self.hold();
                    self.home_epoch = layoutEpoch(self.node);
                    self.startProbe();
                    self.stage = .rebaseline;
                }
                if (self.stage == .capture and dir == .collapse) {
                    // Never left the anchor: back to rest.
                    self.stage = .idle;
                    self.motion.finish();
                    self.settle();
                    return;
                }
                self.first_tick = true;
                self.cx.requestRedraw();
            },
        }
    }

    fn beginRun(self: *AnchorTransition, reduced: bool) !void {
        self.reduced_run = reduced;
        self.run_frames = 0;
        self.first_tick = true;
        self.frame = null;
        flight_stats.runs += 1;
        try self.ensureLayer();
        try self.hook();
        self.updateFrame();
        self.cx.requestRedraw();
    }

    // -- per-frame work (after layout) --

    fn afterLayout(ctx: *anyopaque, round: u8, last_round: bool) core.AfterLayoutResult {
        const self: *AnchorTransition = @ptrCast(@alignCast(ctx));
        if (round == 0) return self.tick(last_round);
        return switch (self.stage) {
            .capture => self.tryCapture(round, last_round),
            .refresh_home => self.readHome(last_round),
            // Every later round of the capture / refresh frame lays out what the hold changed:
            // none of it is a flight-frame layout (the stage clears on the next frame's tick).
            .rebaseline => blk: {
                self.rebaselineProbe();
                break :blk .done;
            },
            .idle => .done,
        };
    }

    fn tick(self: *AnchorTransition, last_round: bool) core.AfterLayoutResult {
        if (!self.nodeAlive()) {
            self.motion.finish();
            self.unhook();
            self.dropLayer(false);
            self.dropSnapshot();
            self.dropProbe();
            self.frame = null;
            self.stage = .idle;
            return .done;
        }
        if (self.stage == .capture) return self.tryCapture(0, last_round);
        if (self.stage == .rebaseline) self.rebaselineProbe();
        self.stage = .idle;
        self.probeFrame();
        // Something rewrote the suppressed node's opacity (theme replay, an app write): adopt it
        // as the value to restore and keep the node hidden.
        if (self.suppressed and self.node.getOpacity() != 0) {
            self.saved_opacity = self.node.getOpacity();
            self.node.setOpacityRaw(0);
            self.node.markCompositeDirty();
        }
        const now = self.cx.frame_time_ms;
        const dt_ms: f64 = if (self.first_tick)
            @min(@as(f64, render_engine.current_frame_dt_ms), 34.0)
        else
            @max(now - self.last_tick_ms, 0);
        self.first_tick = false;
        self.last_tick_ms = now;
        const dt_s: f32 = @floatCast(dt_ms / 1000.0);
        if (self.blend_t < 1) self.blend_t = @min(1, self.blend_t + dt_s / retarget_blend_s);
        // Targets are frozen; only a real change (window resize, anchor laid out anew) is followed.
        if (self.settling) return self.tickSettle(dt_ms, last_round);
        if (self.followTargets(last_round)) return .needs_layout;
        const reduced = self.reduced_run or reducedMotion(self.cx);
        if (self.home_frame) {
            // Hand over once the home picture has been on screen for a frame of time (frames drawn
            // without the clock advancing do not count).
            self.home_frame_ms += dt_ms;
            if (self.home_frame_ms < 15) {
                self.cx.requestRedraw();
                return .done;
            }
            self.home_frame = false;
            return self.land();
        }
        const moving = self.motion.step(dt_s, self.options.tokens, reduced);
        if (!moving) {
            if (self.motion.target >= 1 or self.snapshot == null or self.layer == null) return self.land();
            // Expand: one frame of the picture exactly at home first (the last moving frame may be
            // a fraction of a pixel or a little opacity away), then the live node takes over.
            self.home_frame = true;
            self.home_frame_ms = 0;
            self.frame = .{ .rect = self.effHome(), .opacity = 1 };
            if (self.layer) |layer| if (self.layerAlive()) {
                layer.markRenderDirty();
                layer.markCompositeDirty();
            };
            if (self.probe) |*p| p.prev_flight = true;
            flight_stats.flight_frames += 1;
            self.cx.requestRedraw();
            return .done;
        }
        self.updateFrame();
        if (self.probe) |*p| p.prev_flight = true;
        flight_stats.flight_frames += 1;
        self.run_frames +|= 1;
        self.cx.requestRedraw();
        return .done;
    }

    /// The one-time capture of an expand from rest (the node is shown with paint suppressed).
    fn tryCapture(self: *AnchorTransition, round: u8, last_round: bool) core.AfterLayoutResult {
        const node = self.node;
        // Let the other after-layout hooks of this frame (scroll areas placing their bars, panels
        // re-attaching) apply their changes and lay out once more before the picture is taken.
        if (round == 0 and !last_round) return .needs_layout;
        // The whole subtree must be laid out in the window (a retained panel re-attaches the node in
        // its own after-layout round): a capture of stale child geometry would land with a jump.
        const dirty = node.frame_state.state_bits.dirty.core;
        if (dirty.layout or dirty.subtree_layout or !node.isDisplayedInTree() or !self.inWindow() or node.globalRect().w < 0.5) {
            if (!last_round) return .needs_layout;
            if (self.capture_attempts < 4) {
                self.capture_attempts += 1;
                self.cx.requestRedraw();
                return .done;
            }
        }
        // Geometry that before-render hooks place from layout (scroll bars) was placed from this
        // frame's layout before the after-layout rounds moved the node: let them see the final
        // layout (no time passes), lay out what they changed, then take the picture.
        if (!self.hooks_synced) {
            self.hooks_synced = true;
            syncLayoutHooks(self.cx, node);
            if (!last_round) return .needs_layout;
        }
        // Render the subtree with its own opacity into a private list; nothing is painted. Colour
        // transitions under way (a focus frame just turning) are shown at their end: the live
        // subtree keeps ticking while the picture flies and lands with the end look.
        render_engine.finishColorTransitionsIn(node, self.cx.allocator);
        node.setOpacityRaw(self.saved_opacity);
        const snap = Snapshot.capture(self.cx, node) catch null;
        node.setOpacityRaw(0);
        const s = snap orelse {
            if (self.capture_attempts < 4) {
                self.capture_attempts += 1;
                self.cx.requestRedraw();
                return .done;
            }
            // Nothing to fly (empty or unmeasurable): appear at once.
            self.stage = .idle;
            self.motion.finish();
            self.settle();
            return .needs_layout;
        };
        self.adoptSnapshot(s);
        self.run_home = self.liveHomeRect();
        self.run_anchor = if (self.options.tokens.usesAnchor()) self.resolveAnchor() else null;
        self.anchor_fresh = true;
        self.anchor_epoch = self.anchorEpoch();
        flight_stats.captures += 1;
        self.ensureLayer() catch {
            self.stage = .idle;
            self.motion.finish();
            self.settle();
            return .needs_layout;
        };
        self.last_tick_ms = self.cx.frame_time_ms;
        self.first_tick = false;
        // Settle: the node stays in this and the next frame's layout (paint suppressed) and is
        // rendered once more before it leaves layout for the flight. Content that measures itself
        // a frame later (virtual lists) and a box placed by its surroundings a frame later (a
        // split around a docked pane) are then in the picture the live node lands as.
        self.settling = true;
        self.settle_frames = 0;
        self.stage = .idle;
        if (self.holdKind() == .keep_box) {
            // The home may still move: stay at the start of the run (the anchor) meanwhile, so no
            // frame aims at a provisional home.
            self.updateFrame();
            flight_stats.flight_frames += 1;
            self.cx.requestRedraw();
            return .needs_layout;
        }
        // The request was made a frame ago at the earliest (the anchor may already be gone, e.g.
        // a launcher icon hidden on click): the first frame drawn is already one frame into the
        // run, not a still copy sitting in the anchor.
        const first_dt_ms = @min(@as(f64, render_engine.current_frame_dt_ms), 34.0);
        const reduced = self.reduced_run or reducedMotion(self.cx);
        if (!self.motion.step(@floatCast(first_dt_ms / 1000.0), self.options.tokens, reduced)) {
            self.stage = .idle;
            self.settle();
            return .needs_layout;
        }
        self.updateFrame();
        flight_stats.flight_frames += 1;
        if (self.probe) |*p| p.prev_flight = true;
        self.cx.requestRedraw();
        return .needs_layout;
    }

    /// A frame of the settle window (see tryCapture): the node is still in layout, paint
    /// suppressed. Once it held still for a frame of time (or after three), render it once more
    /// against the final layout and take it out of layout for the flight.
    fn tickSettle(self: *AnchorTransition, dt_ms: f64, last_round: bool) core.AfterLayoutResult {
        if (dt_ms > 0) self.settle_frames +|= 1;
        const rect = self.liveHomeRect();
        const moved = !rect.approxEql(self.run_home, 0.01);
        if (moved) self.run_home = rect;
        const dirty = self.node.frame_state.state_bits.dirty.core;
        const still = !moved and !dirty.layout and !dirty.subtree_layout;
        if ((self.settle_frames >= 1 and still) or self.settle_frames >= 3 or last_round) {
            syncLayoutHooks(self.cx, self.node);
            render_engine.finishColorTransitionsIn(self.node, self.cx.allocator);
            self.node.setOpacityRaw(self.saved_opacity);
            const snap = Snapshot.capture(self.cx, self.node) catch null;
            self.node.setOpacityRaw(0);
            if (snap) |sn| {
                self.adoptSnapshot(sn);
                flight_stats.captures += 1;
            }
            self.settling = false;
            self.hold();
            self.home_epoch = layoutEpoch(self.node);
            self.startProbe();
            self.stage = .rebaseline;
            self.updateFrame();
            flight_stats.flight_frames += 1;
            self.cx.requestRedraw();
            return .needs_layout;
        }
        self.updateFrame();
        flight_stats.flight_frames += 1;
        self.cx.requestRedraw();
        return .done;
    }

    /// Follow a real target change. True = a layout round of this frame is needed (the node was
    /// shown, paint suppressed, to re-read its home: an expand whose window changed size).
    fn followTargets(self: *AnchorTransition, last_round: bool) bool {
        const vp = [2]f32{ self.cx.viewport.width, self.cx.viewport.height };
        const resized = vp[0] != self.run_viewport[0] or vp[1] != self.run_viewport[1];
        const uses_anchor = self.options.tokens.usesAnchor();
        if (!self.anchor_fresh) {
            // First frame of a run: this frame's layout is the one the run aims at.
            self.anchor_fresh = true;
            self.anchor_epoch = self.anchorEpoch();
            if (uses_anchor) {
                const a = self.resolveAnchor();
                if (self.frame == null or self.run_anchor == null) {
                    self.run_anchor = a;
                } else if (a) |r| {
                    if (!r.approxEql(self.run_anchor.?, 0.25)) self.retargetOnto(self.run_home, a);
                }
            }
        } else if (uses_anchor and (resized or self.anchorEpoch() != self.anchor_epoch)) {
            self.anchor_epoch = self.anchorEpoch();
            const a = self.resolveAnchor();
            const same = if (a) |r| (if (self.run_anchor) |old| r.approxEql(old, 0.25) else false) else self.run_anchor == null;
            if (!same) self.retargetOnto(self.run_home, a);
        }
        // A node held with `.keep_box` keeps its own box in its parent's layout: when that box is laid
        // out anew at another place or size (a split settling around a docked pane), the home moved
        // for real. An expand then re-reads it and renders the content once more at the new size.
        if (!resized and self.motion.direction() == .expand and self.holding and self.holdKind() == .keep_box and !last_round and self.box_refreshes < 3) {
            const epoch = layoutEpoch(self.node);
            if (epoch != self.home_epoch) {
                self.home_epoch = epoch;
                const now = toRect(self.node.globalRect());
                if (!now.approxEql(self.run_home, 0.01)) {
                    self.recapture = !(@abs(now.w - self.snap_w) < 0.5 and @abs(now.h - self.snap_h) < 0.5);
                    self.box_refreshes += 1;
                    self.releaseHold();
                    self.suppress();
                    self.stage = .refresh_home;
                    return true;
                }
            }
        }
        if (!resized) return false;
        self.run_viewport = vp;
        // An expand aims at home: re-read where the node rests in the resized window.
        if (self.motion.direction() == .expand and !last_round) {
            self.releaseHold();
            self.suppress();
            self.unhide();
            self.stage = .refresh_home;
            return true;
        }
        return false;
    }

    fn readHome(self: *AnchorTransition, last_round: bool) core.AfterLayoutResult {
        const dirty = self.node.frame_state.state_bits.dirty.core;
        if ((dirty.layout or (self.recapture and dirty.subtree_layout)) and !last_round) return .needs_layout;
        const home = self.liveHomeRect();
        if (self.recapture) {
            // The size changed: the old picture would be stretched. Render the content once more.
            self.recapture = false;
            syncLayoutHooks(self.cx, self.node);
            render_engine.finishColorTransitionsIn(self.node, self.cx.allocator);
            self.node.setOpacityRaw(self.saved_opacity);
            const snap = Snapshot.capture(self.cx, self.node) catch null;
            self.node.setOpacityRaw(0);
            if (snap) |sn| {
                self.adoptSnapshot(sn);
                flight_stats.captures += 1;
            }
        }
        self.hold();
        self.home_epoch = layoutEpoch(self.node);
        flight_stats.home_refreshes += 1;
        if (!home.approxEql(self.run_home, 0.01)) {
            self.retargetOnto(home, self.run_anchor);
            // Right after the run started the picture has barely left its start: take the settled
            // home directly instead of blending away from a box that was never really there.
            if (self.run_frames <= 3) self.blend_t = 1;
        }
        self.stage = .rebaseline;
        const reduced = self.reduced_run or reducedMotion(self.cx);
        if (!self.motion.step(0, self.options.tokens, reduced) and !self.motion.phase().isAnimating()) return self.land();
        self.updateFrame();
        self.cx.requestRedraw();
        return .needs_layout;
    }

    /// Blend from the geometry drawn now onto new targets (continuous picture).
    fn retargetOnto(self: *AnchorTransition, home: Rect, anchor: ?Rect) void {
        self.blend_home = self.effHome();
        self.blend_anchor = self.effAnchor();
        self.blend_t = 0;
        self.run_home = home;
        self.run_anchor = anchor;
        flight_stats.retargets += 1;
    }

    fn effHome(self: *const AnchorTransition) Rect {
        if (self.blend_t >= 1) return self.run_home;
        return lerpRect(self.blend_home, self.run_home, easeOut(self.blend_t));
    }

    fn effAnchor(self: *const AnchorTransition) ?Rect {
        const to = self.run_anchor orelse return self.blend_anchor;
        if (self.blend_t >= 1) return to;
        const from = self.blend_anchor orelse return to;
        return lerpRect(from, to, easeOut(self.blend_t));
    }

    /// Hand the picture back to the live node (a landing): this frame lays the node out and paints
    /// it, so the frame after the last texture frame already shows the live node.
    fn land(self: *AnchorTransition) core.AfterLayoutResult {
        self.probeFrame();
        flight_stats.landings += 1;
        self.settle();
        return .needs_layout;
    }

    fn resolveAnchor(self: *AnchorTransition) ?Rect {
        const resolved: ?Rect = switch (self.anchor) {
            .none => null,
            .rect => |r| motion_mod.clampAnchor(r, .{ .w = self.cx.viewport.width, .h = self.cx.viewport.height }),
            .node => |n| if (self.cx.node_registry.isCurrentIdentity(self.anchor_node_identity, n) and n.isDisplayedInTree())
                resolveNodeAnchor(self.cx, n)
            else
                null,
            .id => |name| if (self.cx.motion_anchors.lookup(self.cx, name)) |n|
                (if (n.isDisplayedInTree()) resolveNodeAnchor(self.cx, n) else null)
            else
                null,
        };
        if (resolved) |r| {
            if (r.isFinite()) {
                self.last_anchor = r;
                return r;
            }
        }
        return self.last_anchor;
    }

    /// Layout epoch of the anchor node (0 for rect / no anchor): changes when it is laid out anew.
    fn anchorEpoch(self: *const AnchorTransition) u64 {
        const n: *Node = switch (self.anchor) {
            .node => |n| if (self.cx.node_registry.isCurrentIdentity(self.anchor_node_identity, n)) n else return 0,
            .id => |name| self.cx.motion_anchors.lookup(self.cx, name) orelse return 0,
            else => return 0,
        };
        return layoutEpoch(n) +% @as(u64, n.id) *% 0x9E3779B97F4A7C15;
    }

    /// The node hangs under the window root (not a detached retained branch).
    fn inWindow(self: *const AnchorTransition) bool {
        const root = self.cx.root orelse return false;
        var cur: ?*Node = self.node;
        while (cur) |n| : (cur = n.parent) {
            if (n == root) return true;
        }
        return false;
    }

    fn liveHomeRect(self: *AnchorTransition) Rect {
        const g = self.node.globalRect();
        if (g.w > 0.5 and g.h > 0.5) return toRect(g);
        return .{ .x = g.x, .y = g.y, .w = self.snap_w, .h = self.snap_h };
    }

    fn updateFrame(self: *AnchorTransition) void {
        const home = self.effHome();
        const uses_anchor = self.options.tokens.usesAnchor();
        // `.fade_scale` stays in place: no anchor to resolve, and none is needed.
        const anchor: ?Rect = if (uses_anchor) self.effAnchor() else home;
        const reduced = self.reduced_run or reducedMotion(self.cx) or anchor == null;
        self.frame = self.motion.frame(home, anchor orelse home, self.options.tokens, reduced);
        if (self.layer) |layer| {
            if (self.layerAlive()) {
                layer.markRenderDirty();
                layer.markCompositeDirty();
            }
        }
    }

    /// Bring the node to rest at the motion's target (a landing: an expand that comes to rest
    /// does not hover what it lands under a resting pointer).
    fn settle(self: *AnchorTransition) void {
        self.settleAt(true);
    }

    fn settleAt(self: *AnchorTransition, landing: bool) void {
        self.home_frame = false;
        self.unhook();
        self.dropLayer(false);
        self.dropSnapshot();
        self.dropProbe();
        self.frame = null;
        self.stage = .idle;
        if (self.pending_tokens) |next| {
            self.options.tokens = next;
            self.pending_tokens = null;
        }
        if (self.nodeAlive()) {
            self.releaseChildren();
            self.holding = false;
            self.unsuppress();
            if (self.motion.target >= 1) self.hide() else {
                self.unhide();
                // Landed content arrives under a pointer that did not move: it is not hovered
                // until the pointer moves (Cx.holdHoverOutsideLanded). A snap is not a landing.
                if (landing) self.cx.holdHoverOutsideLanded(self.node);
            }
        }
        self.cx.requestRedraw();
        if (self.options.on_complete) |cb| cb(self.options.on_complete_ctx, self.motion.phase());
    }

    // -- node state --

    fn nodeAlive(self: *const AnchorTransition) bool {
        return self.cx.node_registry.isCurrentIdentity(self.identity, self.node);
    }

    fn layerAlive(self: *const AnchorTransition) bool {
        const layer = self.layer orelse return false;
        return self.cx.node_registry.isCurrentIdentity(self.layer_identity, layer);
    }

    fn holdKind(self: *const AnchorTransition) Hold {
        return switch (self.options.hold) {
            .auto => if (self.node.style.position == .absolute) .hide else .keep_box,
            else => |h| h,
        };
    }

    /// Take the node out of layout and paint for a run (the texture stands in for it).
    fn hold(self: *AnchorTransition) void {
        self.suppress();
        self.holding = true;
        switch (self.holdKind()) {
            .keep_box => {
                self.unhide();
                self.hideChildren();
            },
            else => self.hide(),
        }
    }

    /// Undo `hold` (the node is about to be shown for a layout round or at rest).
    fn releaseHold(self: *AnchorTransition) void {
        self.releaseChildren();
        self.holding = false;
    }

    fn hideChildren(self: *AnchorTransition) void {
        if (self.kept.items.len > 0) return;
        for (self.node.children.items) |child| {
            if (child.style.display == .none) continue;
            const generation = self.cx.node_registry.trackGeneration(child) catch continue;
            self.kept.append(self.allocator, .{ .node = child, .identity = .{ .id = child.id, .generation = generation }, .display = child.style.display }) catch continue;
            child.setDisplay(.none);
        }
    }

    fn releaseChildren(self: *AnchorTransition) void {
        for (self.kept.items) |k| {
            if (!self.cx.node_registry.isCurrentIdentity(k.identity, k.node)) continue;
            if (k.node.parent != self.node) continue;
            k.node.setDisplay(k.display);
        }
        self.kept.clearRetainingCapacity();
    }

    fn suppress(self: *AnchorTransition) void {
        if (self.suppressed) return;
        self.suppressed = true;
        self.saved_opacity = self.node.getOpacity();
        self.saved_hit = self.node.frame_state.state_bits.flags.hit_test_visible;
        self.node.setOpacityRaw(0);
        self.node.markRenderDirty();
        self.node.markCompositeDirty();
        self.node.setHitTestVisible(false);
    }

    fn unsuppress(self: *AnchorTransition) void {
        if (!self.suppressed) return;
        self.suppressed = false;
        self.node.setOpacityRaw(self.saved_opacity);
        self.node.markRenderDirty();
        self.node.markCompositeDirty();
        self.node.setHitTestVisible(self.saved_hit);
    }

    fn hide(self: *AnchorTransition) void {
        if (self.hidden) return;
        self.hidden = true;
        self.saved_display = self.node.style.display;
        self.node.setDisplay(.none);
    }

    fn unhide(self: *AnchorTransition) void {
        if (!self.hidden) return;
        self.hidden = false;
        self.node.setDisplay(self.saved_display);
    }

    fn adoptSnapshot(self: *AnchorTransition, s: *Snapshot) void {
        self.dropSnapshot();
        self.snapshot = s;
        self.snap_version +%= 1;
        if (self.snap_version == 0) self.snap_version = 1;
        const r = self.node.rectFromWorldOrFallback();
        self.snap_w = r.w;
        self.snap_h = r.h;
    }

    fn dropSnapshot(self: *AnchorTransition) void {
        if (self.snapshot) |s| s.deinit();
        self.snapshot = null;
    }

    fn hook(self: *AnchorTransition) !void {
        if (self.hooked) return;
        try self.cx.addAfterLayoutHook(@ptrCast(self), afterLayout);
        self.hooked = true;
        self.cx.requestRedraw();
    }

    fn unhook(self: *AnchorTransition) void {
        if (!self.hooked) return;
        self.hooked = false;
        self.cx.removeAfterLayoutHook(@ptrCast(self));
    }

    // -- subtree probe --

    fn startProbe(self: *AnchorTransition) void {
        self.dropProbe();
        if (!probeEnabled()) return;
        var p: Probe = .{};
        collectIds(self.allocator, &p.ids, self.node) catch {
            p.ids.deinit(self.allocator);
            return;
        };
        self.probe = p;
    }

    fn dropProbe(self: *AnchorTransition) void {
        if (self.probe) |*p| p.ids.deinit(self.allocator);
        self.probe = null;
    }

    fn rebaselineProbe(self: *AnchorTransition) void {
        if (self.probe) |*p| _ = countLayouts(self.allocator, &p.ids, self.node);
    }

    /// Account the previous flight frame's display list and this frame's layout of the subtree.
    fn probeFrame(self: *AnchorTransition) void {
        const p = if (self.probe) |*v| v else return;
        if (p.prev_flight) {
            var n: u64 = 0;
            for (self.cx.display_list.items.items) |*item| {
                if (p.ids.contains(item.header().node_id)) n += 1;
            }
            flight_stats.subtree_paint_items += n;
            const laid_out = countLayouts(self.allocator, &p.ids, self.node);
            if (laid_out > 0) {
                flight_stats.subtree_layout_frames += 1;
                flight_stats.subtree_layouts += laid_out;
            }
        } else _ = countLayouts(self.allocator, &p.ids, self.node);
        p.prev_flight = false;
    }

    fn collectIds(allocator: Allocator, ids: *std.AutoHashMapUnmanaged(u32, u64), node: *Node) !void {
        for (node.children.items) |child| {
            try ids.put(allocator, child.id, layoutEpoch(child));
            try collectIds(allocator, ids, child);
        }
    }

    /// Descendants laid out since the last check (their layout epoch moved); records the new epochs.
    fn countLayouts(allocator: Allocator, ids: *std.AutoHashMapUnmanaged(u32, u64), node: *Node) u64 {
        var n: u64 = 0;
        for (node.children.items) |child| {
            const epoch = layoutEpoch(child);
            const entry = ids.getOrPut(allocator, child.id) catch continue;
            if (entry.found_existing and entry.value_ptr.* != epoch) n += 1;
            entry.value_ptr.* = epoch;
            n += countLayouts(allocator, ids, child);
        }
        return n;
    }

    // -- the flying layer --

    fn ensureLayer(self: *AnchorTransition) !void {
        if (self.layer != null and self.layerAlive()) return;
        self.layer = null;
        const cx = self.cx;
        if (self.options.layer_parent) |parent| return self.ensureTreeLayer(parent);
        const root = cx.root orelse return error.RootUnavailable;
        const handle = try cx.overlay_stack.push(.{
            .kind = .non_modal,
            .dismiss = .{ .outside_click = .none, .escape = false, .focus_out = false },
            .enter_transition = .none,
            .exit_transition = .none,
            .focus = .{ .trap = false, .auto_focus = false, .restore = false },
            .barrier = .none,
            .content_hit_test_visible = false,
            .z_index = self.options.z_index,
        });
        errdefer cx.overlay_stack.removePermanently(handle);
        const layer = try core.box(cx, .{
            .position = .absolute,
            .width = .{ .grow = .{} },
            .height = .{ .grow = .{} },
        }, .{});
        errdefer cx.freeNode(layer);
        layer.meta.ownership.meta.component_name = "AnchorTransitionLayer";
        layer.setHitTestVisible(false);
        layer.setInspectPickDisabled(true);
        _ = try layer.style.ensureExtFallible(cx.allocator);
        const generation = try cx.node_registry.trackGeneration(layer);
        try root.appendChild(cx.allocator, layer);
        cx.overlay_stack.bindFloatingContent(cx.allocator, handle, layer);
        layer.setCustomDraw(drawLayer, @ptrCast(self));
        self.layer = layer;
        self.layer_identity = .{ .id = layer.id, .generation = generation };
        self.overlay_handle = handle;
    }

    /// The flying layer as a child of `parent` (Options.layer_parent) instead of an overlay.
    fn ensureTreeLayer(self: *AnchorTransition, parent: *Node) !void {
        const cx = self.cx;
        const layer = try core.box(cx, .{
            .position = .absolute,
            .inset = .{ .left = .{ .px = 0 }, .top = .{ .px = 0 } },
            .width = .fill(),
            .height = .fill(),
            .z_index = self.options.z_index orelse 0,
            .hit_behavior = .pass_through,
        }, .{});
        errdefer cx.freeNode(layer);
        layer.meta.ownership.meta.component_name = "AnchorTransitionLayer";
        layer.setHitTestVisible(false);
        layer.setInspectPickDisabled(true);
        _ = try layer.style.ensureExtFallible(cx.allocator);
        const generation = try cx.node_registry.trackGeneration(layer);
        // Paint order among siblings follows the child order too: go before the first sibling that
        // stacks above `z_index`, so it is drawn over the picture as it is over the live node.
        const z = self.options.z_index orelse 0;
        var above: ?*Node = null;
        for (parent.children.items) |child| if (child.style.z_index() > z) {
            above = child;
            break;
        };
        if (above) |child| try parent.insertChildBefore(cx.allocator, layer, child) else try parent.appendChild(cx.allocator, layer);
        layer.setCustomDraw(drawLayer, @ptrCast(self));
        self.layer = layer;
        self.layer_identity = .{ .id = layer.id, .generation = generation };
        self.overlay_handle = null;
    }

    fn dropLayer(self: *AnchorTransition, scope_teardown: bool) void {
        if (self.overlay_handle) |h| self.cx.overlay_stack.removePermanently(h);
        self.overlay_handle = null;
        const layer = self.layer orelse return;
        self.layer = null;
        if (!self.cx.node_registry.isCurrentIdentity(self.layer_identity, layer)) return;
        // The draw callback must never see a freed transition.
        layer.setCustomDraw(drawNothing, null);
        if (layer.parent) |parent| self.cx.detachChild(parent, layer);
        if (scope_teardown) self.cx.freeDetachedNodeAfterScopeDispose(layer) else self.cx.freeNode(layer);
    }

    fn drawNothing(_: DrawContext, _: ?*anyopaque) anyerror!void {}

    fn drawLayer(ctx: DrawContext, context: ?*anyopaque) anyerror!void {
        const self: *AnchorTransition = @ptrCast(@alignCast(context orelse return));
        const snap = self.snapshot orelse return;
        const f = self.frame orelse return;
        if (f.opacity <= 0.001 or f.rect.w < 0.5 or f.rect.h < 0.5) return;
        // The node's own rect (not the bounds of everything painted, which include an outer
        // shadow) maps onto the frame: a card with a drop shadow flies exactly where it rests.
        // One cached texture: rasterized once at the home pixel grid, then only composited
        // (genie mesh, or the affine picture on renderers without a mesh composite).
        const home = self.effHome();
        try snap.appendWarped(ctx, .{
            .fallback = snap.nodeRectToRect(self.snap_w, self.snap_h, toComputed(f.affineRect())),
            .rest = snap.nodeRectToRect(self.snap_w, self.snap_h, toComputed(home)),
            .opacity = f.opacity,
            .surface_id = self.surface_id,
            .content_version = self.snap_version,
            .genie = f.genie,
            .node_w = self.snap_w,
            .node_h = self.snap_h,
            .margin = if (f.genie != null) 2 else 0,
        });
    }
};

/// Run the before-render hooks of `node`'s subtree against the current layout, without time
/// passing (dt 0): hook-placed geometry (scroll bar thumbs) follows a layout made in an after-layout
/// round. What they change is laid out by the caller's next round.
fn syncLayoutHooks(cx: *Cx, node: *Node) void {
    _ = cx;
    // A direct walk, not the frame tick: the tick skips subtrees it judges invisible (the node is
    // paint-suppressed here) or out of its clip, which is exactly the content being pictured.
    runHooksIn(node);
}

fn runHooksIn(node: *Node) void {
    if (node.style.display == .none) return;
    const hooks = &node.meta.per_frame.hooks.before_render;
    if (hooks.main) |hook| hook(node);
    for (hooks.hooks[0..hooks.count]) |hook_opt| if (hook_opt) |hook| hook(node);
    var i: usize = 0;
    while (i < node.children.items.len) : (i += 1) runHooksIn(node.children.items[i]);
}

fn layoutEpoch(node: *const Node) u64 {
    const w = node.world_ref orelse return 0;
    if (node.element_id_raw == 0xFFFFFFFF) return 0;
    return w.layout.epoch(core.world.ElementId.fromRaw(node.element_id_raw));
}

fn lerpRect(a: Rect, b: Rect, t: f32) Rect {
    return .{ .x = a.x + (b.x - a.x) * t, .y = a.y + (b.y - a.y) * t, .w = a.w + (b.w - a.w) * t, .h = a.h + (b.h - a.h) * t };
}

fn easeOut(t: f32) f32 {
    const u = 1 - std.math.clamp(t, 0, 1);
    return 1 - u * u * u;
}

// ---------------------------------------------------------------------------------------------
// Tests (window-free Cx: real layout, snapshot capture, overlay layer and paint list)

const testing = std.testing;

const Rig = struct {
    cx: *Cx,
    root: *Node,
    card: *Node,
    tab: *Node,
    now: f64 = 0,

    fn init() !Rig {
        var cx = try Cx.init(testing.allocator, testing.io);
        errdefer cx.deinit();
        cx.setViewport(400, 300);
        const root = try core.box(cx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
        cx.root = root;
        const tab = try core.box(cx, .{
            .position = .absolute,
            .width = .{ .px = 40 },
            .height = .{ .px = 20 },
            .background = core.Color.rgb(40, 40, 200),
        }, .{});
        tab.style.translate_x = 20;
        tab.style.translate_y = 10;
        try root.appendChild(cx.allocator, tab);
        const card = try core.box(cx, .{
            .position = .absolute,
            .width = .{ .px = 120 },
            .height = .{ .px = 80 },
            .background = core.Color.rgb(220, 70, 60),
        }, .{});
        card.style.translate_x = 200;
        card.style.translate_y = 150;
        try root.appendChild(cx.allocator, card);
        var rig: Rig = .{ .cx = cx, .root = root, .card = card, .tab = tab };
        rig.frame(0);
        return rig;
    }

    fn deinit(self: *Rig) void {
        self.cx.deinit();
    }

    /// Render the frame at `ms`.
    fn frame(self: *Rig, ms: f64) void {
        self.now = ms;
        self.cx.frame_time_ms = ms;
        self.cx.frame_dt_ms = 16;
        self.cx.requestRedraw();
        _ = self.cx.render();
        _ = self.cx.drainDeferredWork(self.cx.deferredBudgetUs());
    }

    fn advance(self: *Rig, ms: f64) void {
        self.frame(self.now + ms);
    }

    /// Run frames until `t` rests or `limit_ms` passes; returns the elapsed time.
    fn settle(self: *Rig, t: *const AnchorTransition, limit_ms: f64) f64 {
        const start = self.now;
        while (t.phase().isAnimating() and self.now - start < limit_ms) self.advance(16);
        return self.now - start;
    }

    /// A transformed snapshot layer was painted onto `r` this frame.
    fn drewLayerAt(self: *Rig, r: Rect) bool {
        for (self.cx.lowerForEncoderPaintTable()) |cmd| {
            if (cmd.kind == .control and cmd.control_kind == .begin_opacity_layer and
                @abs(cmd.draw_x - r.x) < 0.05 and @abs(cmd.draw_y - r.y) < 0.05 and
                @abs(cmd.draw_w - r.w) < 0.05 and @abs(cmd.draw_h - r.h) < 0.05) return true;
        }
        return false;
    }

    /// The live card (not a snapshot) was painted at its home rect this frame.
    fn drewLiveCard(self: *Rig) bool {
        var depth: usize = 0;
        for (self.cx.lowerForEncoderPaintTable()) |cmd| {
            if (cmd.kind == .control and cmd.control_kind == .begin_opacity_layer) {
                depth += 1;
            } else if (cmd.kind == .control and cmd.control_kind == .end_opacity_layer) {
                depth -|= 1;
            } else if (depth == 0 and cmd.isFillRect() and
                @abs(cmd.geom.x - card_home.x) < 0.05 and @abs(cmd.geom.y - card_home.y) < 0.05 and
                @abs(cmd.geom.w - card_home.w) < 0.05 and @abs(cmd.geom.h - card_home.h) < 0.05) return true;
        }
        return false;
    }

    fn anyLayer(self: *Rig) bool {
        for (self.cx.lowerForEncoderPaintTable()) |cmd| {
            if (cmd.kind == .control and cmd.control_kind == .begin_opacity_layer) return true;
        }
        return false;
    }
};

const card_home: Rect = .{ .x = 200, .y = 150, .w = 120, .h = 80 };
const tab_home: Rect = .{ .x = 20, .y = 10, .w = 40, .h = 20 };

test "AnchorTransition: collapse flies a snapshot into the anchor and rests hidden" {
    var rig = try Rig.init();
    defer rig.deinit();
    var completed: ?Phase = null;
    const t = try AnchorTransition.create(rig.cx, rig.card, .{ .tokens = affine_tokens, .on_complete = struct {
        fn f(ctx: ?*anyopaque, ph: Phase) void {
            const out: *?Phase = @ptrCast(@alignCast(ctx.?));
            out.* = ph;
        }
    }.f, .on_complete_ctx = @ptrCast(&completed) });
    defer t.destroy();

    try testing.expect(rig.drewLiveCard());
    t.collapse(.{ .node = rig.tab });
    try testing.expectEqual(Phase.collapsing, t.phase());
    // The live node is suppressed at once; the snapshot takes its place on the next frame.
    try testing.expectEqual(@as(f32, 0), rig.card.getOpacity());
    try testing.expect(!rig.card.frame_state.state_bits.flags.hit_test_visible);
    rig.advance(16);
    const f1 = t.currentFrame().?;
    try testing.expect(f1.rect.approxEql(motion_mod.frameAt(card_home, tab_home, t.progress(), t.options.tokens).rect, 0.01));
    try testing.expect(rig.drewLayerAt(f1.rect));
    try testing.expect(!rig.drewLiveCard());
    rig.advance(100);
    const mid = t.currentFrame().?;
    try testing.expect(mid.rect.w < card_home.w and mid.rect.w > tab_home.w);
    try testing.expect(rig.drewLayerAt(mid.rect));
    // Convergence: just before rest the frame is (almost) the anchor rect.
    while (t.progress() < 0.97) rig.advance(4);
    try testing.expect(t.currentFrame().?.rect.approxEql(tab_home, 2.0));

    const took = rig.settle(t, 1000);
    try testing.expect(took < 400);
    try testing.expectEqual(Phase.collapsed, t.phase());
    try testing.expectEqual(Phase.collapsed, completed.?);
    // At rest: out of layout / paint / focus, own opacity and hit flag back, no layer, no snapshot.
    try testing.expectEqual(core.Display.none, rig.card.style.display);
    try testing.expectEqual(@as(f32, 1), rig.card.getOpacity());
    try testing.expect(rig.card.frame_state.state_bits.flags.hit_test_visible);
    try testing.expect(t.snapshot == null and t.layer == null and !t.hooked);
    try testing.expectEqual(@as(usize, 2), rig.root.children.items.len);
    rig.advance(16);
    try testing.expect(!rig.anyLayer());
}

test "AnchorTransition: collapse after the content was rebuilt flies what was displayed" {
    // The application replaces the node's content and collapses it before the next paint (same
    // tick, or an after-layout hook): the nodes that painted the displayed frame are destroyed,
    // their text released and its memory handed out again. The picture is the displayed frame.
    var rig = try Rig.init();
    defer rig.deinit();
    const shown = "line shown in the displayed frame";
    const old_line = try core.text(rig.cx, shown, .{ .font_size = 12 });
    try rig.card.appendChild(rig.cx.allocator, old_line);
    rig.advance(16);
    const t = try AnchorTransition.create(rig.cx, rig.card, .{ .tokens = affine_tokens });
    defer t.destroy();

    rig.card.removeChild(old_line);
    rig.cx.freeNode(old_line);
    const new_line = try core.text(rig.cx, "LINE BUILT AFTER THAT FRAME, SAME", .{ .font_size = 12 });
    try testing.expectEqual(shown.len, new_line.getText().?.content.len);
    try rig.card.appendChild(rig.cx.allocator, new_line);
    rig.cx.layout();

    t.collapse(.{ .node = rig.tab });
    try testing.expectEqual(Phase.collapsing, t.phase());
    var texts: usize = 0;
    for (t.snapshot.?.commands.commands) |item| {
        if (item != .text_run) continue;
        try testing.expectEqualStrings(shown, item.text_run.content);
        texts += 1;
    }
    try testing.expectEqual(@as(usize, 1), texts);
    _ = rig.settle(t, 1000);
    try testing.expectEqual(Phase.collapsed, t.phase());
}

test "AnchorTransition: expand snapshots current content and leaves no residue" {
    var rig = try Rig.init();
    defer rig.deinit();
    const t = try AnchorTransition.create(rig.cx, rig.card, .{ .tokens = affine_tokens });
    defer t.destroy();
    t.snapTo(true);
    try testing.expectEqual(core.Display.none, rig.card.style.display);
    rig.advance(16);

    // Content changed while collapsed.
    rig.card.setBackground(core.Color.rgb(20, 160, 90));
    t.expand(.{ .node = rig.tab });
    try testing.expectEqual(Phase.expanding, t.phase());
    try testing.expectEqual(core.Display.flex, rig.card.style.display);
    try testing.expectEqual(@as(f32, 0), rig.card.getOpacity());
    rig.advance(16); // laid out, snapshot taken, already one frame out of the anchor
    try testing.expect(t.snapshot != null);
    try testing.expect(t.progress() < 1 and t.progress() > 0);
    try testing.expect(t.currentFrame().?.opacity > 0);
    rig.advance(16);
    rig.advance(16);
    rig.advance(100);
    const mid = t.currentFrame().?;
    try testing.expect(t.progress() < 1 and t.progress() > 0);
    try testing.expect(rig.drewLayerAt(mid.rect));
    try testing.expect(!rig.drewLiveCard());
    // The snapshot is the fresh content (green), not the color at mount.
    var green = false;
    for (t.snapshot.?.commands.commands) |c| switch (c) {
        .fill_rect => |r| green = green or (r.color.g == 160 and r.color.r == 20),
        else => {},
    };
    try testing.expect(green);

    _ = rig.settle(t, 1000);
    try testing.expectEqual(Phase.expanded, t.phase());
    try testing.expectEqual(@as(f32, 1), rig.card.getOpacity());
    try testing.expect(rig.card.frame_state.state_bits.flags.hit_test_visible);
    try testing.expect(t.snapshot == null and t.layer == null and !t.hooked);
    // The settling frame already paints the live node and no snapshot layer.
    try testing.expect(!rig.anyLayer());
    try testing.expect(rig.drewLiveCard());
    rig.advance(16);
    try testing.expect(!rig.anyLayer());
    try testing.expect(rig.drewLiveCard());
    try testing.expectEqual(@as(usize, 2), rig.root.children.items.len);
}

test "AnchorTransition: an expand's picture shows colour transitions at their end (no colour switch at landing)" {
    var rig = try Rig.init();
    defer rig.deinit();
    // A field inside the card whose look (background here; a focus frame's border colour in an app)
    // eases over 150 ms, and a fade that must keep running.
    const field = try core.box(rig.cx, .{ .width = .{ .px = 60 }, .height = .{ .px = 20 }, .background = core.Color.rgb(200, 200, 200) }, .{});
    try rig.card.appendChild(rig.cx.allocator, field);
    try field.applyTransition(rig.cx.allocator, &core.transition("background 150ms, opacity 400ms"));
    rig.advance(16);
    const t = try AnchorTransition.create(rig.cx, rig.card, .{ .tokens = affine_tokens });
    defer t.destroy();
    t.snapTo(true);
    rig.advance(16);
    // The click that opens the card also focuses the field: its look starts turning now.
    const target = core.Color.rgb(20, 160, 90);
    field.setBackground(target);
    field.setOpacity(0.5);
    t.expand(.{ .node = rig.tab });
    rig.advance(16);
    rig.advance(16);
    const snap = t.snapshot orelse return error.NoSnapshot;
    var end_colour = false;
    var halfway = false;
    for (snap.commands.commands) |c| switch (c) {
        .fill_rect => |r| if (@abs(r.w - 60) < 0.5 and @abs(r.h - 20) < 0.5) {
            // RGB only: the alpha carries the field's fade, which keeps running.
            if (r.color.r == target.r and r.color.g == target.g and r.color.b == target.b) end_colour = true else halfway = true;
        },
        else => {},
    };
    try testing.expect(end_colour and !halfway);
    try testing.expect(core.Color.eql(field.getBackground(), target));
    // Only colours are brought to their end; the fade keeps its own time.
    const slots = field.frame_state.frame_local.runtime.transitions.?;
    try testing.expect(slots.find(.opacity).?.active);
    try testing.expect(!slots.find(.background).?.active);
    _ = rig.settle(t, 1000);
    try testing.expectEqual(Phase.expanded, t.phase());
    try testing.expect(core.Color.eql(field.getBackground(), target));
}

test "AnchorTransition: a reversal mid-flight continues from the current frame" {
    var rig = try Rig.init();
    defer rig.deinit();
    const t = try AnchorTransition.create(rig.cx, rig.card, .{ .tokens = affine_tokens });
    defer t.destroy();
    t.collapse(.{ .node = rig.tab });
    rig.advance(16);
    rig.advance(100);
    const p = t.progress();
    const before = t.currentFrame().?;
    try testing.expect(p > 0.2 and p < 0.8);

    t.expand(.{ .node = rig.tab });
    try testing.expectEqual(Phase.expanding, t.phase());
    // Not restarted: the snapshot and layer of the run in flight are kept.
    try testing.expect(t.snapshot != null and t.layer != null);
    rig.advance(16);
    const after = t.currentFrame().?;
    try testing.expect(t.progress() < p);
    // One frame of motion, not a jump back home or to the anchor.
    try testing.expect(@abs(after.rect.centerX() - before.rect.centerX()) < 40);
    try testing.expect(@abs(after.rect.centerY() - before.rect.centerY()) < 40);
    const took = rig.settle(t, 1000);
    // The way back is the remaining share of an expand on its (ease-out) clock.
    const tok = t.options.tokens;
    const g = tok.easing.apply(p);
    var share: f32 = 1;
    var lo: f32 = 0;
    var hi: f32 = 1;
    for (0..40) |_| {
        const mid = (lo + hi) / 2;
        if (tok.expand_easing.?.apply(mid) < 1 - g) lo = mid else hi = mid;
    }
    share = 1 - lo;
    try testing.expect(took <= share * tok.expand_duration_s * 1000 + 32);
    try testing.expectEqual(Phase.expanded, t.phase());
    try testing.expectEqual(core.Display.flex, rig.card.style.display);

    // Rapid toggling never queues: each request just flips the direction.
    var i: usize = 0;
    while (i < 6) : (i += 1) {
        t.setCollapsed(i % 2 == 0, .{ .node = rig.tab });
        rig.advance(16);
    }
    try testing.expectEqual(Phase.expanding, t.phase());
    _ = rig.settle(t, 1000);
    try testing.expectEqual(Phase.expanded, t.phase());
    try testing.expectEqual(@as(f32, 1), rig.card.getOpacity());
}

test "AnchorTransition: reduced motion fades in place or switches instantly" {
    var rig = try Rig.init();
    defer rig.deinit();
    rig.cx.reduced_motion = true;
    const t = try AnchorTransition.create(rig.cx, rig.card, .{ .tokens = affine_tokens });
    defer t.destroy();
    t.collapse(.{ .node = rig.tab });
    rig.advance(16);
    rig.advance(50);
    const f = t.currentFrame().?;
    // No displacement or scale: only opacity changes.
    try testing.expect(f.rect.approxEql(card_home, 0.01));
    try testing.expect(f.opacity < 1 and f.opacity > 0);
    const took = rig.settle(t, 1000);
    try testing.expect(took <= t.options.tokens.reduced_duration_s * 1000 + 16);
    try testing.expectEqual(Phase.collapsed, t.phase());

    var tokens = default_tokens;
    tokens.reduced = .instant;
    t.setTokens(tokens);
    t.expand(.{ .node = rig.tab });
    try testing.expectEqual(Phase.expanded, t.phase());
    try testing.expectEqual(core.Display.flex, rig.card.style.display);
    try testing.expect(t.layer == null and t.snapshot == null);
    t.collapse(.{ .node = rig.tab });
    try testing.expectEqual(Phase.collapsed, t.phase());
    try testing.expectEqual(core.Display.none, rig.card.style.display);
}

test "AnchorTransition: the node takes no hits during a run" {
    var rig = try Rig.init();
    defer rig.deinit();
    rig.card.setFocusable(true);
    rig.advance(16);
    try testing.expectEqual(rig.card, rig.cx.hitTest(260, 190).?);
    const t = try AnchorTransition.create(rig.cx, rig.card, .{ .tokens = affine_tokens });
    defer t.destroy();
    t.collapse(.{ .node = rig.tab });
    rig.advance(16);
    // The card's home and the flying snapshot are both click-through.
    try testing.expect(rig.cx.hitTest(260, 190) != rig.card);
    const fr = t.currentFrame().?;
    try testing.expect(rig.cx.hitTest(fr.rect.centerX(), fr.rect.centerY()) != rig.card);
    t.expand(.{ .node = rig.tab });
    _ = rig.settle(t, 1000);
    rig.advance(16);
    try testing.expectEqual(rig.card, rig.cx.hitTest(260, 190).?);
}

test "AnchorTransition: the anchor is followed while it moves and clamped into its clip" {
    var rig = try Rig.init();
    defer rig.deinit();
    const t = try AnchorTransition.create(rig.cx, rig.card, .{ .tokens = affine_tokens });
    defer t.destroy();
    t.collapse(.{ .node = rig.tab });
    rig.advance(16);
    rig.advance(60);
    // The tab strip scrolls: the anchor moves 100pt right mid-run.
    rig.tab.style.translate_x = 120;
    rig.tab.markLayoutDirty();
    while (t.progress() < 0.97) rig.advance(4);
    try testing.expect(t.currentFrame().?.rect.approxEql(.{ .x = 120, .y = 10, .w = 40, .h = 20 }, 2.0));
    _ = rig.settle(t, 1000);

    // A tab scrolled out of an overflow-clipped strip resolves to the strip's nearest end.
    const strip = try core.box(rig.cx, .{
        .position = .absolute,
        .width = .{ .px = 100 },
        .height = .{ .px = 30 },
        .overflow = .hidden,
    }, .{});
    strip.style.translate_x = 50;
    strip.style.translate_y = 4;
    try rig.root.appendChild(rig.cx.allocator, strip);
    const far = try core.box(rig.cx, .{ .position = .absolute, .width = .{ .px = 30 }, .height = .{ .px = 20 } }, .{});
    far.style.translate_x = 300;
    far.style.translate_y = 5;
    try strip.appendChild(rig.cx.allocator, far);
    rig.advance(16);
    const r = resolveNodeAnchor(rig.cx, far);
    try testing.expect(r.approxEql(.{ .x = 120, .y = 9, .w = 30, .h = 20 }, 0.01));
}

test "AnchorTransition: named anchors, missing anchors and a node freed mid-run" {
    var rig = try Rig.init();
    defer rig.deinit();
    const token = try rig.cx.motion_anchors.register(rig.cx, "tab-1", rig.tab);
    const t = try AnchorTransition.create(rig.cx, rig.card, .{ .tokens = affine_tokens });
    defer t.destroy();
    t.collapse(.{ .id = "tab-1" });
    rig.advance(16);
    rig.advance(60);
    // The registration goes away mid-run: the run keeps aiming at the last resolved rect.
    rig.cx.motion_anchors.unregister(token);
    while (t.progress() < 0.97) rig.advance(4);
    try testing.expect(t.currentFrame().?.rect.approxEql(tab_home, 2.0));
    _ = rig.settle(t, 1000);
    try testing.expectEqual(Phase.collapsed, t.phase());

    // No anchor ever resolved: the run degrades to a fade in place.
    const t2 = try AnchorTransition.create(rig.cx, rig.tab, .{});
    defer t2.destroy();
    t2.collapse(.{ .id = "nowhere" });
    rig.advance(16);
    rig.advance(50);
    try testing.expect(t2.currentFrame().?.rect.approxEql(tab_home, 0.01));
    _ = rig.settle(t2, 1000);

    // The animated node is freed mid-run: the layer and snapshot go, nothing dangles.
    t.expand(.{ .id = "tab-1" });
    rig.advance(16);
    rig.advance(16);
    try testing.expect(t.layer != null);
    rig.cx.detachChild(rig.root, rig.card);
    rig.cx.freeNode(rig.card);
    rig.advance(16);
    try testing.expect(t.layer == null and t.snapshot == null and !t.hooked);
    rig.advance(16);
    try testing.expect(!rig.anyLayer());
}

test "AnchorTransition: fade_scale fades and shrinks in place, ignoring the anchor" {
    var rig = try Rig.init();
    defer rig.deinit();
    const t = try AnchorTransition.create(rig.cx, rig.card, .{ .tokens = fade_scale_tokens });
    defer t.destroy();
    // A far anchor is given but never flown to; a missing anchor does not degrade the run either.
    t.collapse(.{ .node = rig.tab });
    try testing.expectEqual(Phase.collapsing, t.phase());
    rig.advance(16);
    rig.advance(60);
    const mid = t.currentFrame().?;
    try testing.expect(mid.opacity < 1 and mid.opacity > 0);
    try testing.expect(mid.rect.w < card_home.w and mid.rect.w >= card_home.w * 0.97 - 0.01);
    try testing.expectApproxEqAbs(card_home.centerX(), mid.rect.centerX(), 0.01);
    try testing.expectApproxEqAbs(card_home.centerY(), mid.rect.centerY(), 0.01);
    try testing.expect(rig.drewLayerAt(mid.rect));
    try testing.expect(!rig.drewLiveCard());
    const took = rig.settle(t, 1000);
    try testing.expect(took <= fade_scale_tokens.fade_scale_out_duration_s * 1000 + 32);
    try testing.expectEqual(Phase.collapsed, t.phase());
    try testing.expectEqual(core.Display.none, rig.card.style.display);
    try testing.expect(t.layer == null and t.snapshot == null);

    // Fade back in from rest with no anchor at all: still the scale + fade, centered on home.
    t.expand(.none);
    rig.advance(16); // snapshot
    rig.advance(16);
    rig.advance(50);
    const back = t.currentFrame().?;
    try testing.expect(back.rect.w < card_home.w and back.rect.w > card_home.w * 0.97 - 0.01);
    try testing.expectApproxEqAbs(card_home.centerX(), back.rect.centerX(), 0.01);
    // Reversal mid-flight continues from the current frame.
    const p = t.progress();
    t.collapse(.none);
    rig.advance(16);
    try testing.expect(t.progress() > p);
    try testing.expect(@abs(t.currentFrame().?.opacity - back.opacity) < 0.3);
    t.expand(.none);
    _ = rig.settle(t, 1000);
    try testing.expectEqual(Phase.expanded, t.phase());
    try testing.expectEqual(@as(f32, 1), rig.card.getOpacity());
    try testing.expect(rig.drewLiveCard());
}

test "AnchorTransition: fade_scale under reduced motion is a pure fade" {
    var rig = try Rig.init();
    defer rig.deinit();
    rig.cx.reduced_motion = true;
    const t = try AnchorTransition.create(rig.cx, rig.card, .{ .tokens = fade_scale_tokens });
    defer t.destroy();
    t.collapse(.none);
    rig.advance(16);
    rig.advance(50);
    const f = t.currentFrame().?;
    try testing.expect(f.rect.approxEql(card_home, 0.01));
    try testing.expect(f.opacity < 1 and f.opacity > 0);
    _ = rig.settle(t, 1000);
    try testing.expectEqual(Phase.collapsed, t.phase());
}

test "AnchorTransition: setTokens mid-run applies from the next run" {
    var rig = try Rig.init();
    defer rig.deinit();
    const t = try AnchorTransition.create(rig.cx, rig.card, .{ .tokens = affine_tokens });
    defer t.destroy();
    t.collapse(.{ .node = rig.tab });
    rig.advance(16);
    rig.advance(60);
    t.setTokens(fade_scale_tokens);
    // The run in flight keeps flying to the tab.
    try testing.expectEqual(Mode.anchor, t.motionTokens().mode);
    rig.advance(16);
    try testing.expect(t.currentFrame().?.rect.centerY() < card_home.centerY() - 5);
    _ = rig.settle(t, 1000);
    try testing.expectEqual(Mode.fade_scale, t.motionTokens().mode);
    // The next run is in place.
    t.expand(.{ .node = rig.tab });
    rig.advance(16);
    rig.advance(16);
    rig.advance(40);
    try testing.expectApproxEqAbs(card_home.centerY(), t.currentFrame().?.rect.centerY(), 0.01);
    _ = rig.settle(t, 1000);
    // At rest the change is immediate.
    t.setTokens(default_tokens);
    try testing.expectEqual(Mode.anchor, t.motionTokens().mode);
}

test "AnchorTransition: a card with a drop shadow flies in its own rect (no shadow offset)" {
    var rig = try Rig.init();
    defer rig.deinit();
    // A drop shadow paints outside the card (blur 24, offset 8 down): the snapshot's origin must
    // stay the card's top-left, or the flying picture sits shifted by the shadow's extent and
    // jumps back when the live card takes over at rest (ZeroWork AI panel, open-motion).
    const card = try core.box(rig.cx, .{
        .position = .absolute,
        .width = .{ .px = 120 },
        .height = .{ .px = 80 },
        .background = core.Color.rgb(220, 70, 60),
        .shadow = .{ .blur = 24, .offset_y = 8, .color = core.Color.rgba(0, 0, 0, 90) },
    }, .{});
    card.style.translate_x = 200;
    card.style.translate_y = 150;
    rig.card.setDisplay(.none);
    try rig.root.appendChild(rig.cx.allocator, card);
    rig.advance(16);
    const t = try AnchorTransition.create(rig.cx, card, .{ .tokens = affine_tokens });
    defer t.destroy();
    const Check = struct {
        fn cardAtOrigin(snap: *const Snapshot, w: f32, h: f32) !void {
            // Drawn onto the card's own rect, the card's fill lands exactly there.
            const m = snap.nodeRectToRect(w, h, toComputed(card_home));
            var found = false;
            for (snap.commands.commands) |c| switch (c) {
                .fill_rect => |r| if (r.color.r == 220 and r.color.g == 70 and r.color.b == 60) {
                    found = true;
                    const drawn = m.transformRect(.{ .x = r.x, .y = r.y, .w = r.w, .h = r.h });
                    try testing.expect(toRect(drawn).approxEql(card_home, 0.01));
                },
                else => {},
            };
            try testing.expect(found);
            // The shadow is part of the picture: the snapshot's bounds reach past the card.
            try testing.expect(snap.local_bounds.w > w + 8 and snap.local_bounds.h > h + 8);
            try testing.expect(snap.node_offset.x > 1 and snap.node_offset.y > 1);
        }
    };
    // Collapse from rest (the displayed frame is frozen).
    t.collapse(.{ .node = rig.tab });
    try Check.cardAtOrigin(t.snapshot.?, t.snap_w, t.snap_h);
    // The flying layer is drawn with that map: the card part of the picture is on the frame.
    rig.advance(16);
    const f = t.currentFrame().?;
    const snap = t.snapshot.?;
    const want = snap.nodeRectToRect(t.snap_w, t.snap_h, toComputed(f.rect)).transformRect(snap.local_bounds);
    try testing.expect(rig.drewLayerAt(toRect(want)));
    try testing.expectApproxEqAbs(card_home.w, t.snap_w, 0.01);
    _ = rig.settle(t, 1000);
    // Expand from rest (a fresh capture after layout).
    t.expand(.{ .node = rig.tab });
    rig.advance(16);
    try Check.cardAtOrigin(t.snapshot.?, t.snap_w, t.snap_h);
    _ = rig.settle(t, 1000);
    try testing.expectEqual(Phase.expanded, t.phase());
}

const HoverLog = struct {
    enters: u32 = 0,
    leaves: u32 = 0,
    fn onEvent(event: core.Event, context: ?*anyopaque) core.EventResult {
        const log: *HoverLog = @ptrCast(@alignCast(context.?));
        switch (event) {
            .mouse_enter => log.enters += 1,
            .mouse_leave => log.leaves += 1,
            else => {},
        }
        return .ignored;
    }
};

fn cardHovered(rig: *Rig) bool {
    const node = rig.cx.hovered_node orelse return false;
    return node.isDescendantOf(rig.card);
}

test "AnchorTransition: an expand landing under a resting pointer does not hover until it moves" {
    var rig = try Rig.init();
    defer rig.deinit();
    var log: HoverLog = .{};
    rig.card.behavior.events.on_event = HoverLog.onEvent;
    rig.card.behavior.events.event_context = &log;
    const t = try AnchorTransition.create(rig.cx, rig.card, .{ .tokens = affine_tokens });
    defer t.destroy();
    t.snapTo(true);
    rig.advance(16);
    // The pointer rests where the card will land (it clicked the anchor, then stayed put).
    rig.cx.handleMouseMove(card_home.x + 30, card_home.y + 30);
    try testing.expect(!cardHovered(&rig));

    t.expand(.{ .node = rig.tab });
    _ = rig.settle(t, 1000);
    try testing.expectEqual(Phase.expanded, t.phase());
    for (0..4) |_| rig.advance(16);
    // Landed content is hit-testable (a click still reaches it) but not hovered.
    try testing.expect(rig.card.frame_state.state_bits.flags.hit_test_visible);
    try testing.expect(!cardHovered(&rig));
    try testing.expectEqual(@as(u32, 0), log.enters);
    // A move event at the same spot is not a move: still no hover.
    rig.cx.handleMouseMove(card_home.x + 30, card_home.y + 30);
    rig.advance(16);
    try testing.expect(!cardHovered(&rig));

    // The pointer moves: hover resolves normally again.
    rig.cx.handleMouseMove(card_home.x + 31, card_home.y + 30);
    try testing.expect(cardHovered(&rig));
    try testing.expectEqual(@as(u32, 1), log.enters);
    rig.advance(16);
    try testing.expect(cardHovered(&rig));
}

test "AnchorTransition: only a landing holds hover; a snap or other scene change under a resting pointer hovers" {
    var rig = try Rig.init();
    defer rig.deinit();
    var log: HoverLog = .{};
    rig.card.behavior.events.on_event = HoverLog.onEvent;
    rig.card.behavior.events.event_context = &log;
    const t = try AnchorTransition.create(rig.cx, rig.card, .{ .tokens = affine_tokens });
    defer t.destroy();
    t.snapTo(true);
    rig.advance(16);
    rig.cx.handleMouseMove(card_home.x + 30, card_home.y + 30);
    // A snap is a programmatic placement, not a landing: global stationary re-resolution applies.
    t.snapTo(false);
    rig.advance(16); // laid out and committed to the hit scene
    rig.advance(16); // stationary re-resolution
    try testing.expect(cardHovered(&rig));
    try testing.expectEqual(@as(u32, 1), log.enters);

    // A landing elsewhere leaves the rest of the scene alone: content that moves under the
    // resting pointer after the hold ended (pointer moved) is hovered by the ordinary rules.
    rig.cx.handleMouseMove(390, 290);
    rig.advance(16);
    try testing.expect(!cardHovered(&rig));
    t.collapse(.{ .node = rig.tab });
    _ = rig.settle(t, 1000);
    t.expand(.{ .node = rig.tab });
    _ = rig.settle(t, 1000);
    rig.advance(16);
    try testing.expect(!cardHovered(&rig));
    rig.cx.handleMouseMove(391, 290);
    rig.advance(16);
    try testing.expect(!cardHovered(&rig));
    // The card slides under the resting pointer: ordinary stationary re-resolution hovers it.
    rig.card.style.translate_x = 300;
    rig.card.style.translate_y = 250;
    rig.card.markCompositePropDirty();
    rig.card.markLayoutDirty();
    rig.advance(16);
    rig.advance(16);
    try testing.expect(cardHovered(&rig));
}

// -- The static-texture run model (genie-static) -------------------------------------------------

/// A card with two children (a bar and a body) next to the tab of `Rig`.
const ContentRig = struct {
    rig: Rig,
    bar: *Node,
    body: *Node,

    fn init() !ContentRig {
        var rig = try Rig.init();
        errdefer rig.deinit();
        rig.card.style.direction = .column;
        const bar = try core.box(rig.cx, .{ .width = .{ .px = 100 }, .height = .{ .px = 20 }, .background = core.Color.rgb(250, 250, 250) }, .{});
        const body = try core.box(rig.cx, .{ .width = .{ .px = 60 }, .height = .{ .px = 30 }, .background = core.Color.rgb(10, 10, 120) }, .{});
        try rig.card.appendChild(rig.cx.allocator, bar);
        try rig.card.appendChild(rig.cx.allocator, body);
        rig.card.markLayoutDirty();
        rig.advance(16);
        return .{ .rig = rig, .bar = bar, .body = body };
    }

    fn deinit(self: *ContentRig) void {
        self.rig.deinit();
    }

    /// Display items this frame that belong to the card's subtree (the card or its children).
    fn subtreeItems(self: *ContentRig) usize {
        var n: usize = 0;
        for (self.rig.cx.display_list.items.items) |*item| {
            const id = item.header().node_id;
            if (id == self.rig.card.id or id == self.bar.id or id == self.body.id) n += 1;
        }
        return n;
    }

    fn epochs(self: *ContentRig) u64 {
        return layoutEpoch(self.bar) +% layoutEpoch(self.body);
    }

    /// The flying layer's begin item this frame.
    fn layerItem(self: *ContentRig, t: *const AnchorTransition) ?paint_table_mod.DisplayItem {
        for (self.rig.cx.lowerForEncoderPaintTable()) |cmd| {
            if (cmd.kind == .control and cmd.control_kind == .begin_opacity_layer and cmd.surface_stable_id == t.surface_id) return cmd;
        }
        return null;
    }
};

const paint_table_mod = @import("core/paint_table.zig");

test "AnchorTransition: in flight the subtree takes no part in layout or paint; only one cached texture is drawn" {
    var c = try ContentRig.init();
    defer c.deinit();
    probe_override = true;
    defer probe_override = null;
    const before = flight_stats;
    const t = try AnchorTransition.create(c.rig.cx, c.rig.card, .{});
    defer t.destroy();
    try testing.expect(c.subtreeItems() > 0);

    t.collapse(.{ .node = c.rig.tab });
    // Out of layout at once (an absolutely positioned card is held with display: none).
    try testing.expectEqual(core.Display.none, c.rig.card.style.display);
    const e0 = c.epochs();
    var surface: ?u32 = null;
    var frames: usize = 0;
    while (t.phase().isAnimating()) : (frames += 1) {
        // Content changes in flight: neither laid out nor painted until the node is back.
        c.body.setWidth(40 + @as(f32, @floatFromInt(frames % 3)) * 10);
        c.bar.setBackground(core.Color.rgb(250, @intCast(frames % 200), 250));
        c.rig.advance(16);
        if (!t.phase().isAnimating()) break;
        try testing.expectEqual(@as(usize, 0), c.subtreeItems());
        try testing.expectEqual(e0, c.epochs());
        const item = c.layerItem(t) orelse return error.NoLayer;
        // Genie by default: the mesh warp rides on the cached layer, the same texture identity
        // every frame, rasterized on the home pixel grid.
        try testing.expect(item.genie.isActive());
        try testing.expect(item.surface_rest_origin != null);
        if (surface) |s| try testing.expectEqual(s, item.surface_stable_id) else surface = item.surface_stable_id;
        // The damage envelope holds the warped picture.
        const gb = genie_warp_mod.localBounds(item.genie, .{ item.geom.x, item.geom.y, item.geom.w, item.geom.h });
        try testing.expect(item.draw_x <= gb[0] + 0.01 and item.draw_y <= gb[1] + 0.01);
        try testing.expect(item.draw_x + item.draw_w >= gb[0] + gb[2] - 0.01 and item.draw_y + item.draw_h >= gb[1] + gb[3] - 0.01);
    }
    try testing.expect(frames > 10);
    try testing.expectEqual(Phase.collapsed, t.phase());
    try testing.expectEqual(before.subtree_layout_frames, flight_stats.subtree_layout_frames);
    try testing.expectEqual(before.subtree_layouts, flight_stats.subtree_layouts);
    try testing.expectEqual(before.subtree_paint_items, flight_stats.subtree_paint_items);
    try testing.expect(flight_stats.flight_frames - before.flight_frames >= frames - 1);

    // Expand from rest: a private render in the request frame, the settle frame (the node stays in
    // layout, paint suppressed, and is rendered once more), then only the texture until the landing
    // frame hands back to the live node.
    t.expand(.{ .node = c.rig.tab });
    c.rig.advance(16);
    try testing.expectEqual(before.captures + 1, flight_stats.captures);
    c.rig.advance(16);
    try testing.expectEqual(before.captures + 2, flight_stats.captures);
    try testing.expectEqual(core.Display.none, c.rig.card.style.display);
    c.rig.advance(16);
    const e1 = c.epochs();
    var landed_frame_live = false;
    while (t.phase().isAnimating()) {
        c.rig.advance(16);
        if (t.phase().isAnimating()) {
            try testing.expectEqual(@as(usize, 0), c.subtreeItems());
            try testing.expectEqual(e1, c.epochs());
        } else {
            // Landing frame: the live node is laid out and painted in this very frame, no layer.
            landed_frame_live = c.subtreeItems() > 0 and c.layerItem(t) == null;
        }
    }
    try testing.expect(landed_frame_live);
    try testing.expectEqual(Phase.expanded, t.phase());
    try testing.expectEqual(core.Display.flex, c.rig.card.style.display);
    try testing.expectEqual(before.captures + 2, flight_stats.captures);
    try testing.expectEqual(before.subtree_layouts, flight_stats.subtree_layouts);
    try testing.expectEqual(before.subtree_paint_items, flight_stats.subtree_paint_items);
    try testing.expect(flight_stats.landings > before.landings);
}

test "AnchorTransition: geometry is frozen at the start; a resize retargets continuously" {
    var c = try ContentRig.init();
    defer c.deinit();
    const t = try AnchorTransition.create(c.rig.cx, c.rig.card, .{});
    defer t.destroy();
    // A rect anchor at the right edge: the viewport clamps it, so shrinking the window moves it.
    t.collapse(.{ .rect = .{ .x = 380, .y = 4, .w = 20, .h = 20 } });
    c.rig.advance(16);
    const g0 = t.runGeometry();
    try testing.expect(g0.home.approxEql(card_home, 0.01));
    try testing.expect(g0.anchor.?.approxEql(.{ .x = 380, .y = 4, .w = 20, .h = 20 }, 0.01));
    // The anchor tab node moving (laid out anew) does not matter to a rect anchor; frames go on
    // from the frozen geometry.
    c.rig.tab.setWidth(80);
    c.rig.advance(16);
    try testing.expect(t.runGeometry().anchor.?.approxEql(g0.anchor.?, 0.01));
    const retargets = flight_stats.retargets;
    const before = t.currentFrame().?.rect;
    c.rig.cx.setViewport(300, 300);
    c.rig.advance(16);
    try testing.expectEqual(retargets + 1, flight_stats.retargets);
    try testing.expect(t.runGeometry().anchor.?.approxEql(.{ .x = 280, .y = 4, .w = 20, .h = 20 }, 0.01));
    // Continuous: the frame moves on by about one frame of motion, not onto the new target.
    const after = t.currentFrame().?.rect;
    try testing.expect(@abs(after.centerX() - before.centerX()) < 40);
    try testing.expect(@abs(after.centerY() - before.centerY()) < 40);
    _ = c.rig.settle(t, 1000);
    try testing.expectEqual(Phase.collapsed, t.phase());
}

test "AnchorTransition: a node anchor laid out anew is followed, blended" {
    var c = try ContentRig.init();
    defer c.deinit();
    const t = try AnchorTransition.create(c.rig.cx, c.rig.card, .{});
    defer t.destroy();
    t.collapse(.{ .node = c.rig.tab });
    c.rig.advance(16);
    try testing.expect(t.runGeometry().anchor.?.approxEql(tab_home, 0.01));
    const retargets = flight_stats.retargets;
    c.rig.tab.setWidth(100);
    c.rig.advance(16);
    try testing.expectEqual(retargets + 1, flight_stats.retargets);
    try testing.expectApproxEqAbs(@as(f32, 100), t.runGeometry().anchor.?.w, 0.01);
    while (t.phase().isAnimating()) c.rig.advance(16);
    try testing.expect(t.last_anchor.?.approxEql(.{ .x = 20, .y = 10, .w = 100, .h = 20 }, 0.01));
}

test "AnchorTransition: an in-flow node keeps its box (no reflow) while its content is held out" {
    var rig = try Rig.init();
    defer rig.deinit();
    // A row: [pane][sibling]; the pane is in flow.
    const row = try core.box(rig.cx, .{ .direction = .row, .width = .{ .px = 300 }, .height = .{ .px = 100 } }, .{});
    const pane = try core.box(rig.cx, .{ .width = .{ .px = 150 }, .height = .{ .px = 100 }, .background = core.Color.rgb(30, 30, 30) }, .{});
    const inner = try core.box(rig.cx, .{ .width = .{ .px = 80 }, .height = .{ .px = 40 }, .background = core.Color.rgb(200, 200, 0) }, .{});
    const sibling = try core.box(rig.cx, .{ .width = .{ .px = 150 }, .height = .{ .px = 100 }, .background = core.Color.rgb(0, 200, 0) }, .{});
    try pane.appendChild(rig.cx.allocator, inner);
    try row.appendChild(rig.cx.allocator, pane);
    try row.appendChild(rig.cx.allocator, sibling);
    try rig.root.appendChild(rig.cx.allocator, row);
    rig.advance(16);
    const sibling_rest = sibling.globalRect();
    const t = try AnchorTransition.create(rig.cx, pane, .{});
    defer t.destroy();
    t.snapTo(true);
    t.expand(.{ .node = rig.tab });
    rig.advance(16);
    rig.advance(16);
    try testing.expectEqual(Phase.expanding, t.phase());
    // The pane box stays in the row; its content is out of layout and paint.
    try testing.expectEqual(core.Display.flex, pane.style.display);
    try testing.expectEqual(core.Display.none, inner.style.display);
    rig.advance(16);
    try testing.expect(sibling.globalRect().x == sibling_rest.x);
    var pane_items: usize = 0;
    for (rig.cx.display_list.items.items) |*item| {
        const id = item.header().node_id;
        if (id == pane.id or id == inner.id) pane_items += 1;
    }
    try testing.expectEqual(@as(usize, 0), pane_items);
    _ = rig.settle(t, 1000);
    try testing.expectEqual(Phase.expanded, t.phase());
    try testing.expectEqual(core.Display.flex, inner.style.display);
    try testing.expect(sibling.globalRect().x == sibling_rest.x);
}

test "AnchorTransition: a reversal keeps the texture, and landing does not need another capture" {
    var c = try ContentRig.init();
    defer c.deinit();
    const t = try AnchorTransition.create(c.rig.cx, c.rig.card, .{});
    defer t.destroy();
    const captures = flight_stats.captures;
    t.collapse(.{ .node = c.rig.tab });
    c.rig.advance(16);
    c.rig.advance(100);
    const snap = t.snapshot;
    t.expand(.{ .node = c.rig.tab });
    c.rig.advance(16);
    try testing.expect(t.snapshot == snap);
    _ = c.rig.settle(t, 1000);
    try testing.expectEqual(Phase.expanded, t.phase());
    try testing.expectEqual(captures, flight_stats.captures);
    try testing.expect(c.subtreeItems() > 0);
}

test "AnchorTransition: an in-flow box laid out anew during an expand is followed and rendered once more" {
    var rig = try Rig.init();
    defer rig.deinit();
    const row = try core.box(rig.cx, .{ .direction = .row, .width = .{ .px = 300 }, .height = .{ .px = 100 } }, .{});
    const pane = try core.box(rig.cx, .{ .width = .{ .px = 150 }, .height = .{ .px = 100 }, .background = core.Color.rgb(30, 30, 30) }, .{});
    const inner = try core.box(rig.cx, .{ .width = .{ .px = 80 }, .height = .{ .px = 40 }, .background = core.Color.rgb(200, 200, 0) }, .{});
    try pane.appendChild(rig.cx.allocator, inner);
    try row.appendChild(rig.cx.allocator, pane);
    try rig.root.appendChild(rig.cx.allocator, row);
    rig.advance(16);
    const t = try AnchorTransition.create(rig.cx, pane, .{});
    defer t.destroy();
    t.snapTo(true);
    t.expand(.{ .node = rig.tab });
    rig.advance(16);
    const captures = flight_stats.captures;
    try testing.expectApproxEqAbs(@as(f32, 150), t.runGeometry().home.w, 0.01);
    // The split settles: the pane's box gets wider.
    pane.setWidth(200);
    rig.advance(16);
    rig.advance(16);
    try testing.expectApproxEqAbs(@as(f32, 200), t.runGeometry().home.w, 0.01);
    try testing.expectEqual(captures + 1, flight_stats.captures);
    try testing.expectApproxEqAbs(@as(f32, 200), t.snap_w, 0.01);
    // Still held: the content is out of layout again.
    try testing.expectEqual(core.Display.none, inner.style.display);
    _ = rig.settle(t, 1000);
    try testing.expectEqual(Phase.expanded, t.phase());
    try testing.expectEqual(core.Display.flex, inner.style.display);
}

test "AnchorTransition: an expand's picture places scroll bars from the final layout" {
    const scroll_area = @import("components/scroll_area/mod.zig");
    var rig = try Rig.init();
    defer rig.deinit();
    const scope = try Scope.init(testing.allocator, null, rig.cx.owner);
    defer scope.dispose();
    const sa = try scroll_area.ScrollArea(.{ .height = 60, .content_height = 300 }).mount(scope, rig.cx);
    sa.container.setStyleInline(rig.cx.allocator, .{ .width = .fill() });
    try rig.card.appendChild(rig.cx.allocator, sa.container);
    // A persistent bar (as an app that keeps it visible while content overflows).
    sa.state.scrollbar_fade.persistent = true;
    rig.card.markLayoutDirty();
    rig.advance(16);
    rig.advance(16);
    const t = try AnchorTransition.create(rig.cx, rig.card, .{});
    defer t.destroy();
    t.snapTo(true);
    rig.advance(16);
    // The card comes back wider, resized by an after-layout hook of the frame (after the
    // before-render hooks placed the bars): its bar must sit at the new right edge in the picture.
    const Resize = struct {
        card: *Node,
        done: bool = false,
        fn run(ctx: *anyopaque, _: u8, _: bool) core.AfterLayoutResult {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            if (self.done) return .done;
            self.done = true;
            self.card.setWidth(200);
            return .needs_layout;
        }
    };
    var resize: Resize = .{ .card = rig.card };
    try rig.cx.addAfterLayoutHook(@ptrCast(&resize), Resize.run);
    defer rig.cx.removeAfterLayoutHook(@ptrCast(&resize));
    t.expand(.{ .node = rig.tab });
    rig.advance(16);
    const snap = t.snapshot orelse return error.NoSnapshot;
    var thumb_right: ?f32 = null;
    for (snap.commands.commands) |c| switch (c) {
        .fill_rect => |r| if (r.w <= 6 and r.h >= 10) {
            thumb_right = r.x + r.w - snap.node_offset.x;
        },
        else => {},
    };
    const right = thumb_right orelse return error.NoThumb;
    try testing.expectApproxEqAbs(@as(f32, 200 - 2), right, 0.5);
}

test "AnchorTransition: an in-flow box starts its run only after it held still for a frame" {
    var rig = try Rig.init();
    defer rig.deinit();
    const row = try core.box(rig.cx, .{ .direction = .row, .width = .{ .px = 300 }, .height = .{ .px = 100 } }, .{});
    const pane = try core.box(rig.cx, .{ .width = .{ .px = 150 }, .height = .{ .px = 100 }, .background = core.Color.rgb(30, 30, 30) }, .{});
    const inner = try core.box(rig.cx, .{ .width = .{ .px = 80 }, .height = .{ .px = 40 }, .background = core.Color.rgb(200, 200, 0) }, .{});
    try pane.appendChild(rig.cx.allocator, inner);
    try row.appendChild(rig.cx.allocator, pane);
    try rig.root.appendChild(rig.cx.allocator, row);
    rig.advance(16);
    var tok = affine_tokens;
    tok.end_opacity = 1;
    const t = try AnchorTransition.create(rig.cx, pane, .{ .tokens = tok });
    defer t.destroy();
    t.snapTo(true);
    t.expand(.{ .rect = .{ .x = 20, .y = 150, .w = 100, .h = 60 } });
    rig.advance(16);
    // Capture frame: the picture sits in the anchor, fully drawn (no blank frame), not moving yet.
    try testing.expectApproxEqAbs(@as(f32, 1), t.progress(), 0.0001);
    try testing.expect(t.currentFrame().?.rect.approxEql(.{ .x = 20, .y = 150, .w = 100, .h = 60 }, 0.01));
    // The split settles on the next frame: the run aims at the settled box, never the provisional one.
    pane.setWidth(200);
    rig.advance(16);
    try testing.expectApproxEqAbs(@as(f32, 200), t.runGeometry().home.w, 0.01);
    try testing.expectApproxEqAbs(@as(f32, 1), t.progress(), 0.0001);
    rig.advance(16);
    rig.advance(16);
    try testing.expect(t.progress() < 1);
    _ = rig.settle(t, 1000);
    try testing.expectEqual(Phase.expanded, t.phase());
}

test "AnchorTransition: a layer parent draws the picture inside the tree, under what stacks above it" {
    var rig = try Rig.init();
    defer rig.deinit();
    const t = try AnchorTransition.create(rig.cx, rig.card, .{ .layer_parent = rig.root, .z_index = 5 });
    defer t.destroy();
    t.collapse(.{ .node = rig.tab });
    rig.advance(16);
    const layer = t.layer orelse return error.NoLayer;
    try testing.expect(layer.parent == rig.root);
    try testing.expect(t.overlay_handle == null);
    try testing.expectEqual(@as(i16, 5), layer.style.z_index());
    // Before any sibling that stacks above it (the card has z 0 here, so the layer goes last).
    try testing.expect(rig.root.children.items[rig.root.children.items.len - 1] == layer);
    try testing.expect(rig.drewLayerAt(t.currentFrame().?.rect) or t.currentFrame().?.genie != null);
    _ = rig.settle(t, 1000);
    try testing.expect(t.layer == null);
    try testing.expectEqual(@as(usize, 2), rig.root.children.items.len);
}

/// Repro rig for "a node mounted into the subtree around a flight is laid out after the landing".
const LateChild = struct {
    var cx: *Cx = undefined;
    var added: ?*Node = null;
    var arm: bool = false;

    /// Before-render hook on the body: once armed, appends one child (what a virtual list does
    /// when its pool grows) and marks the body's layout dirty.
    fn hook(body: *Node) void {
        if (!arm or added != null) return;
        const child = core.box(cx, .{ .width = .{ .px = 30 }, .height = .{ .px = 12 }, .flex_shrink = 0 }, .{}) catch return;
        body.appendChild(cx.allocator, child) catch {
            cx.freeNode(child);
            return;
        };
        added = child;
        body.markLayoutDirty();
    }

    fn laidOut() bool {
        const n = added orelse return false;
        const r = n.globalRect();
        return r.w > 0 and r.h > 0;
    }
};

fn lateChildRun(comptime when: enum { at_capture_hook, mid_flight, before_expand }) !bool {
    var c = try ContentRig.init();
    defer c.deinit();
    LateChild.cx = c.rig.cx;
    LateChild.added = null;
    LateChild.arm = false;
    c.body.style.direction = .column;
    c.body.meta.per_frame.hooks.before_render.main = LateChild.hook;
    const t = try AnchorTransition.create(c.rig.cx, c.rig.card, .{});
    defer t.destroy();
    t.collapse(.{ .node = c.rig.tab });
    while (t.phase().isAnimating()) c.rig.advance(16);
    try testing.expectEqual(Phase.collapsed, t.phase());
    switch (when) {
        // Mounted while the node rests collapsed (display none), before the expand is asked for.
        .before_expand => {
            LateChild.arm = true;
            LateChild.hook(c.body);
        },
        // Mounted by the subtree's own before-render hook when the expand takes its picture
        // (syncLayoutHooks runs the hooks by a direct walk).
        .at_capture_hook => LateChild.arm = true,
        .mid_flight => {},
    }
    t.expand(.{ .node = c.rig.tab });
    var frames: usize = 0;
    while (t.phase().isAnimating() and frames < 400) : (frames += 1) {
        c.rig.advance(16);
        if (when == .mid_flight and frames == 6) {
            // Mounted by the app while only the texture flies.
            LateChild.arm = true;
            LateChild.hook(c.body);
        }
    }
    try testing.expectEqual(Phase.expanded, t.phase());
    try testing.expect(LateChild.added != null);
    // Rest: a few more frames, nothing else asks for layout.
    for (0..4) |_| c.rig.advance(16);
    return LateChild.laidOut();
}

test "AnchorTransition: a node mounted into the subtree before / during an expand is laid out once it has landed" {
    const before_expand = try lateChildRun(.before_expand);
    const at_capture_hook = try lateChildRun(.at_capture_hook);
    const mid_flight = try lateChildRun(.mid_flight);
    try testing.expect(before_expand);
    try testing.expect(at_capture_hook);
    // Failed before: the layout pass drops the dirty marks of a display-none subtree, and the
    // landing only marked the node itself.
    try testing.expect(mid_flight);
}
