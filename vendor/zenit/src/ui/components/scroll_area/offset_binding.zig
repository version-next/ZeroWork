//! ScrollArea offset binding (`scroll_y` / `scroll_x`: `Model(f32)`), see ScrollAreaProps.
//!
//! The source and the scroll state meet only at the container's before-render hook, once per
//! frame:
//!
//! - **Write (source -> area)**: an effect on the source records a pending offset when the value
//!   differs from what the binding last agreed with (`synced_*`) and asks for a frame. The hook
//!   applies it after it has refreshed the viewport / content extents from this frame's layout,
//!   so a write made before the content is laid out (a fresh mount restoring a remembered offset)
//!   waits for layout instead of clamping against zero extents. Applying clamps to
//!   [0, max], cancels momentum / bounce on that axis, and publishes the clamped value back.
//! - **Read (area -> source)**: at the end of the hook, a settled offset (`scroll_y`, never the
//!   rubber-band displacement) that differs from `synced_*` is proposed to the source
//!   (`Bound.propose`): bound signal written, split handler called, `on_scroll_*_change`
//!   reported. At most one proposal per axis per frame however many wheel / momentum events
//!   arrived, and nothing while the offset rests.
//!
//! Proposals only happen inside the render tick (owner batch, `tick_depth > 0`), never from a
//! theme replay or inside a reactive computation; the next frame publishes instead.
//!
//! Areas the render tick did not visit (docs/design/scroll-area-layout-derived-state.md). The tick
//! skips hooks below a box outside the clip (render_engine/tick.zig), so one after-layout pass per
//! Cx (the `Registry`) settles every bound area whose hook did not run this frame: an area that is
//! attached under the current root and laid out (a non-zero rect) gets its pending write applied
//! and its offset published, as the hook would have done; an area that is hidden, not laid out
//! yet, or detached from the root keeps its pending write and leaves the source alone (its
//! `scroll_y` reads the last settled offset). Visited areas are only published again (an
//! after-layout hook may have scrolled them after the tick; a no-op otherwise). The extents and
//! the clamp to them come from the area's layout observer (mod.zig), on screen or not. An offset
//! that moves outside the tick (`setScrollY` / `setScrollX`, the clamp) asks for a frame so the
//! report is never left waiting for unrelated input.
const std = @import("std");
const core = @import("../../core.zig");
const reactive = @import("../../reactive.zig");
const state_mod = @import("state.zig");
const ScrollEventCtx = state_mod.ScrollEventCtx;
const ScrollState = state_mod.ScrollState;
const Node = core.Node;
const Handler = core.Handler;

pub const OffsetBinding = struct {
    ctx: *ScrollEventCtx,
    y: ?reactive.Bound(f32) = null,
    x: ?reactive.Bound(f32) = null,
    on_y_change: ?Handler(f32) = null,
    on_x_change: ?Handler(f32) = null,
    pending_y: ?f32 = null,
    pending_x: ?f32 = null,
    synced_y: f32 = 0,
    synced_x: f32 = 0,
    registry: ?*Registry = null,
    registry_index: usize = 0,

    pub fn effectY(self: *OffsetBinding) void {
        const b = self.y orelse return;
        self.request(&self.pending_y, self.synced_y, b.readAs(true));
    }

    pub fn effectX(self: *OffsetBinding) void {
        const b = self.x orelse return;
        self.request(&self.pending_x, self.synced_x, b.readAs(true));
    }

    /// The registry's after-layout pass (module doc).
    fn settle(self: *OffsetBinding) void {
        const ctx = self.ctx;
        if (ctx.hook_frame != ctx.cx.frame_count) {
            const container = ctx.container orelse return;
            if (!attachedTo(container, ctx.cx.root)) return;
            const r = container.rectFromWorldOrFallback();
            if (r.w <= 0 and r.h <= 0) return;
            applyPending(ctx, r);
        }
        publish(ctx);
    }

    fn cleanup(self: *OffsetBinding) void {
        if (self.registry) |r| r.remove(self);
    }

    fn request(self: *OffsetBinding, pending: *?f32, synced: f32, v: f32) void {
        if (!std.math.isFinite(v)) return;
        if (v == synced) {
            // Back to the agreed offset (an echo of our own publication, or an owner
            // reverting a write that has not landed yet): nothing to apply.
            pending.* = null;
            return;
        }
        pending.* = v;
        self.ctx.cx.requestRedraw();
        if (self.ctx.container) |c| c.markRenderDirty();
    }
};

/// Before-render, after the hook refreshed the extents: apply pending source writes. Waits while
/// the container has no layout yet (a zero rect: not laid out, or hidden).
pub fn applyPending(ctx: *ScrollEventCtx, container_rect: core.ComputedRect) void {
    const self = ctx.offset_binding orelse return;
    if (self.pending_y == null and self.pending_x == null) return;
    if (ctx.cx.tick_depth == 0) return;
    if (container_rect.w <= 0 and container_rect.h <= 0) return;
    const content = ctx.content orelse return;
    const state = ctx.state;
    if (self.pending_y) |y| {
        self.pending_y = null;
        state.touching = false;
        state.momentum_active = false;
        @import("mod.zig").setScrollY(state, content, y);
    }
    if (self.pending_x) |x| {
        self.pending_x = null;
        state.touching = false;
        state.momentum_active = false;
        @import("mod.zig").setScrollX(state, content, x);
    }
    ctx.cx.requestRedraw();
}

/// End of the before-render hook (and the registry pass): propose a settled offset that moved
/// since the last agreement.
pub fn publish(ctx: *ScrollEventCtx) void {
    const self = ctx.offset_binding orelse return;
    const cx = ctx.cx;
    if (cx.tick_depth == 0 or cx.owner.inReactiveComputation()) return;
    const state = ctx.state;
    // A write still waiting for layout keeps the source's value; do not overwrite it with the
    // offset the area happens to have before applying it.
    if (self.pending_y == null and state.scroll_y != self.synced_y) {
        self.synced_y = state.scroll_y;
        if (self.y) |b| propose(b, state.scroll_y, self.on_y_change);
    }
    if (self.pending_x == null and state.scroll_x != self.synced_x) {
        self.synced_x = state.scroll_x;
        if (self.x) |b| propose(b, state.scroll_x, self.on_x_change);
    }
}

/// Teardown (the area's scope is being disposed): a settled offset that moved since the last
/// agreement and was not published yet — scrolled after the last before-render, e.g. an input
/// handler that rebuilds the view in the same frame — is proposed now, so the owner never loses
/// the reader's last scroll. Children scopes are disposed before their parent's cleanups and
/// resources, so a source / handler owned by an enclosing scope is alive here. Skipped inside a
/// reactive computation (no writes there); a write still waiting for layout keeps the source's
/// value.
pub fn flushOnTeardown(ctx: *ScrollEventCtx) void {
    const self = ctx.offset_binding orelse return;
    if (ctx.cx.owner.inReactiveComputation()) return;
    const state = ctx.state;
    if (self.pending_y == null and state.scroll_y != self.synced_y) {
        self.synced_y = state.scroll_y;
        if (self.y) |b| propose(b, state.scroll_y, self.on_y_change);
    }
    if (self.pending_x == null and state.scroll_x != self.synced_x) {
        self.synced_x = state.scroll_x;
        if (self.x) |b| propose(b, state.scroll_x, self.on_x_change);
    }
}

fn propose(b: reactive.Bound(f32), v: f32, on_change: ?Handler(f32)) void {
    // The source already holds it (an applied write that landed unclamped): nothing to report,
    // and a split owner is not asked to write the value it just gave.
    if (b.peek() == v) return;
    // Read-only source without a handler: follow-only, never reported.
    if (b.signal == null and b.write == null and on_change == null) return;
    b.propose(v, on_change);
}

/// Mount-time wiring (ScrollArea mount): null when the area is uncontrolled with no initial
/// offset and no change handler, so a plain ScrollArea allocates nothing extra.
pub fn install(
    scope: *reactive.Scope,
    ctx: *ScrollEventCtx,
    y: reactive.Model(f32),
    x: reactive.Model(f32),
    on_y_change: ?Handler(f32),
    on_x_change: ?Handler(f32),
) !?*OffsetBinding {
    const y_used = !isIdle(y) or on_y_change != null;
    const x_used = !isIdle(x) or on_x_change != null;
    if (!y_used and !x_used) return null;
    const self = try scope.createState(OffsetBinding, .{ .ctx = ctx, .on_y_change = on_y_change, .on_x_change = on_x_change });
    if (y_used) self.y = try reactive.resolveModel(f32, scope, y);
    if (x_used) self.x = try reactive.resolveModel(f32, scope, x);
    ctx.offset_binding = self;
    if (y_used) try scope.createEffect(self, OffsetBinding.effectY);
    if (x_used) try scope.createEffect(self, OffsetBinding.effectX);
    try (try Registry.of(ctx.cx)).add(self);
    try scope.onCleanup(OffsetBinding, self, OffsetBinding.cleanup);
    return self;
}

fn attachedTo(node: *const Node, root: ?*Node) bool {
    const r = root orelse return false;
    var cur: *const Node = node;
    var depth: usize = 0;
    while (cur.parent) |p| : (depth += 1) {
        if (depth > 4096) return false;
        cur = p;
    }
    return cur == r;
}

/// The bound areas of one Cx and their single after-layout pass: registering is O(1) however many
/// areas a window binds (a per-area after-layout hook would make mounting n areas O(n²): the hook
/// list deduplicates and removes by scanning). Found through the Cx's hook list (its own `run`),
/// freed with the last binding.
const Registry = struct {
    cx: *core.Cx,
    items: std.ArrayListUnmanaged(*OffsetBinding) = .empty,

    fn of(cx: *core.Cx) !*Registry {
        for (cx.after_layout_hooks.items) |h| {
            if (h.run == run) return @ptrCast(@alignCast(h.ctx));
        }
        const self = try cx.allocator.create(Registry);
        errdefer cx.allocator.destroy(self);
        self.* = .{ .cx = cx };
        try cx.addAfterLayoutHook(self, run);
        return self;
    }

    fn add(self: *Registry, b: *OffsetBinding) !void {
        try self.items.append(self.cx.allocator, b);
        b.registry = self;
        b.registry_index = self.items.items.len - 1;
    }

    fn remove(self: *Registry, b: *OffsetBinding) void {
        const i = b.registry_index;
        std.debug.assert(self.items.items[i] == b);
        _ = self.items.swapRemove(i);
        if (i < self.items.items.len) self.items.items[i].registry_index = i;
        b.registry = null;
        if (self.items.items.len == 0) {
            const cx = self.cx;
            cx.removeAfterLayoutHook(self);
            self.items.deinit(cx.allocator);
            cx.allocator.destroy(self);
        }
    }

    fn run(raw: *anyopaque, _: u8, _: bool) core.AfterLayoutResult {
        const self: *Registry = @ptrCast(@alignCast(raw));
        for (self.items.items) |b| b.settle();
        return .done;
    }
};

fn isIdle(m: reactive.Model(f32)) bool {
    return switch (m) {
        .local => |v| v == 0,
        else => false,
    };
}
