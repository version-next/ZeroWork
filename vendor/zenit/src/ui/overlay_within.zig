//! Window areas for overlay layers: where a floating layer anchors (Popover `anchor`) and where a
//! barrier layer's content is placed (Modal `within`). Re-exported by overlay_stack.zig.
//! Design: docs/design/overlay-within-area.md.
//!
//! - `Anchor`: a rect in window (portal) coordinates, from a node (its laid-out rect, the node
//!   tracked by a generation-checked `NodeHandle`, never dereferenced once freed) or from a
//!   caller-provided rect callback.
//! - `TrackedNode`: the node half of that — a bare pointer plus its identity handle; `get` returns
//!   null once the node was freed (or its id reused).
//! - `WithinPlacement`: puts a barrier layer's content (a dialog panel) inside an area of the
//!   window instead of the whole overlay, and bounds it by that area. The barrier keeps covering
//!   the window (modality unchanged); an internal placement box between barrier and content is
//!   positioned on the area after layout and centres the content; the content's size cap is
//!   published as signals for the component to fold into its own size sources (one owner).
const std = @import("std");
const core = @import("core.zig");
const reactive = @import("reactive.zig");
const overlay_layer_refs = @import("overlay_layer_refs.zig");
const Node = core.Node;
const Cx = core.Cx;
const NodeHandle = core.NodeHandle;
const ComputedRect = core.ComputedRect;
const Scope = reactive.Scope;
const Source = reactive.Source;
const Signal = core.Signal;

/// A rect in window (portal) coordinates: the same space overlay layers are laid out in.
pub const AnchorRect = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,
};

/// A caller-provided rect (a caret, a selection, an area drawn without nodes). `getRect` is a pure
/// read: Popover calls it from its positioning hook (before render, `.dirty_marking`), Modal
/// `within` from the after-layout pass; it must not write nodes (a write to an overlay goes through
/// a dirty-marking API, see Node.BeforeRenderScope). It returns window (portal) coordinates. It is
/// read on the frames those passes run: a rect that changes while nothing else does asks for a
/// frame (Popover: a redraw; `within`: a layout, e.g. `markLayoutDirty` on any node).
pub const VirtualAnchor = struct {
    ctx: *anyopaque,
    getRect: *const fn (ctx: *anyopaque) AnchorRect,
};

/// A rect source for overlays: a real node (its laid-out rect, followed every frame; the node is
/// tracked by identity and treated as gone once freed) or a `VirtualAnchor`.
pub const Anchor = union(enum) {
    node: *Node,
    virtual: VirtualAnchor,
};

/// A node referenced by an overlay without owning it: dereferenced only after the identity check.
pub const TrackedNode = struct {
    node: *Node,
    handle: ?NodeHandle,

    pub fn track(cx: *Cx, node: *Node) TrackedNode {
        return .{ .node = node, .handle = overlay_layer_refs.trackNode(&cx.node_registry, node) };
    }

    /// The node while it is alive; null once freed or its id reused (or when it could not be
    /// tracked: the safe side).
    pub fn get(self: TrackedNode, cx: *const Cx) ?*Node {
        return overlay_layer_refs.resolveTrackedNode(&cx.node_registry, self.handle, self.node);
    }
};

/// The node hangs under the window root (the portal lives under it too).
pub fn attachedToWindow(cx: *const Cx, node: *const Node) bool {
    const root = cx.root orelse return false;
    var top: *const Node = node;
    while (top.parent) |parent| top = parent;
    return top == root;
}

/// A node's rect in portal coordinates (the window header offset applied like Popover's anchors).
pub fn nodeRect(cx: *const Cx, node: *Node) AnchorRect {
    const g = node.globalRect();
    const offset = if (cx.windowHeaderOwns(node)) cx.window_header_offset else [2]f32{ 0, 0 };
    return .{ .x = g.x + offset[0], .y = g.y + offset[1], .w = g.w, .h = g.h };
}

fn intersect(a: AnchorRect, b: AnchorRect) ?AnchorRect {
    const x0 = @max(a.x, b.x);
    const y0 = @max(a.y, b.y);
    const x1 = @min(a.x + a.w, b.x + b.w);
    const y1 = @min(a.y + a.h, b.y + b.h);
    if (x1 <= x0 or y1 <= y0) return null;
    return .{ .x = x0, .y = y0, .w = x1 - x0, .h = y1 - y0 };
}

/// The part of `node` that is on screen: its rect clipped by every clipping ancestor
/// (`overflow_hidden`, scroll areas). null when nothing of it shows.
pub fn visibleNodeRect(cx: *const Cx, node: *Node) ?AnchorRect {
    var rect = nodeRect(cx, node);
    if (rect.w <= 0 or rect.h <= 0) return null;
    var parent = node.parent;
    while (parent) |p| : (parent = p.parent) {
        if (!p.style.overflow_hidden and p.tag != .scroll) continue;
        rect = intersect(rect, nodeRect(cx, p)) orelse return null;
    }
    return rect;
}

/// Places a barrier layer's content inside a window area (Modal `within`). See the module doc.
pub const WithinPlacement = struct {
    /// Below this room (after the padding) an area is treated as unavailable and the content is
    /// placed in the whole overlay: a dialog narrower / shorter than this is not usable.
    pub const min_width: f32 = 200;
    pub const min_height: f32 = 120;

    cx: *Cx,
    barrier: *Node,
    /// Internal box between the barrier and the content: in the barrier's flow (centred by it, so
    /// with no area the content sits exactly as without placement) or, with an area, absolute on it.
    place: *Node,
    area: Source(?Anchor),
    padding: Source(f32),
    /// Identity of `area`'s node, taken when the source hands it over (at install and on every
    /// source change, while the caller's node is known alive) — never from a stale pointer later.
    tracked: ?TrackedNode = null,
    /// Content size cap (the area's room after the padding); null = no cap. The component folds
    /// them into its own width / height sources.
    cap_w: *Signal(?f32),
    cap_h: *Signal(?f32),
    /// The area the place box was last laid out on (null = in flow).
    shown: ?AnchorRect = null,
    warned_inside: bool = false,

    /// Builds the placement under `barrier` (append the content with `attach`). Registers the
    /// after-layout hook on `scope` (removed on its cleanup) and, for a dynamic source, an effect
    /// that re-lays out when the source changes.
    pub fn install(scope: *Scope, cx: *Cx, barrier: *Node, area: Source(?Anchor), padding: Source(f32)) !*WithinPlacement {
        reactive.checkBorrow(scope, area);
        reactive.checkBorrow(scope, padding);
        const place = try core.box(cx, .{ .direction = .column, .justify = .center, .align_items = .center }, .{});
        errdefer cx.freeNode(place);
        // The place box is not a target itself (a plain box has no pointer role, so a press on its
        // empty part reaches the barrier — the mask), but its subtree is: hiding the box from hit
        // testing would take the whole dialog with it.
        place.meta.ownership.meta.component_name = "WithinPlacement";
        try barrier.appendChild(cx.allocator, place);
        const self = try scope.allocator.create(WithinPlacement);
        self.* = .{
            .cx = cx,
            .barrier = barrier,
            .place = place,
            .area = area,
            .padding = padding,
            .cap_w = try scope.createSignal(?f32, null),
            .cap_h = try scope.createSignal(?f32, null),
        };
        try scope.adoptResource(@ptrCast(self), destroy);
        self.retrack();
        try cx.addAfterLayoutHook(self, afterLayout);
        try scope.onCleanup(WithinPlacement, self, cleanup);
        if (!area.isStatic() or !padding.isStatic()) try scope.createEffect(self, effect);
        return self;
    }

    /// Puts the content in the place box.
    pub fn attach(self: *WithinPlacement, content: *Node) !void {
        try self.place.appendChild(self.cx.allocator, content);
    }

    /// Content width bound by the area: min(wanted, cap).
    pub fn capWidth(wanted: f32, cap: ?f32) f32 {
        return if (cap) |c| @min(wanted, c) else wanted;
    }

    /// Optional content height bound by the area.
    pub fn capHeight(wanted: ?f32, cap: ?f32) ?f32 {
        const w = wanted orelse return null;
        return capWidth(w, cap);
    }

    /// The area's rect now, inside the overlay and inset by the padding; null = place in the whole
    /// overlay (no area, the area is gone / hidden / off screen / too small / inside the layer).
    fn target(self: *WithinPlacement, overlay: AnchorRect) ?AnchorRect {
        const anchor = self.area.peek() orelse return null;
        const raw: AnchorRect = switch (anchor) {
            .node => blk: {
                const node = (self.tracked orelse return null).get(self.cx) orelse return null;
                if (!attachedToWindow(self.cx, node) or !node.isDisplayedInTree()) return null;
                // An area inside the layer itself would size the dialog from its own size.
                if (node == self.barrier or node.isDescendantOf(self.barrier)) {
                    if (!self.warned_inside) std.log.warn("[overlay] within: the area node is inside the layer it places; ignored", .{});
                    self.warned_inside = true;
                    return null;
                }
                break :blk visibleNodeRect(self.cx, node) orelse return null;
            },
            .virtual => |v| v.getRect(v.ctx),
        };
        const on_screen = intersect(raw, overlay) orelse return null;
        const pad = @max(0, self.padding.peek());
        const room: AnchorRect = .{ .x = on_screen.x + pad, .y = on_screen.y + pad, .w = on_screen.w - 2 * pad, .h = on_screen.h - 2 * pad };
        if (room.w < min_width or room.h < min_height) return null;
        return room;
    }

    fn same(a: ?AnchorRect, b: ?AnchorRect) bool {
        if (a == null or b == null) return a == null and b == null;
        const x = a.?;
        const y = b.?;
        return @abs(x.x - y.x) < 0.25 and @abs(x.y - y.y) < 0.25 and @abs(x.w - y.w) < 0.25 and @abs(x.h - y.h) < 0.25;
    }

    fn afterLayout(raw: *anyopaque, _: u8, _: bool) core.AfterLayoutResult {
        const self: *WithinPlacement = @ptrCast(@alignCast(raw));
        // Closed: the barrier is collapsed to 0×0; leave the placement as it is.
        if (self.barrier.style.width == .px) return .done;
        const b = nodeRect(self.cx, self.barrier);
        if (b.w <= 0 or b.h <= 0) return .done;
        const next = self.target(b);
        if (same(next, self.shown)) return .done;
        self.shown = next;
        const a = self.cx.allocator;
        if (next) |r| {
            self.place.setStyleInline(a, .{
                .position = .absolute,
                .inset = .{ .left = .{ .px = r.x - b.x }, .top = .{ .px = r.y - b.y } },
                .width = .{ .px = r.w },
                .height = .{ .px = r.h },
            });
            self.cap_w.set(r.w);
            self.cap_h.set(r.h);
        } else {
            self.place.setStyleInline(a, .{ .position = .relative, .inset = .{}, .width = .{ .fit = .{} }, .height = .{ .fit = .{} } });
            self.cap_w.set(null);
            self.cap_h.set(null);
        }
        self.place.markLayoutDirty();
        self.barrier.markLayoutDirty();
        return .needs_layout;
    }

    fn retrack(self: *WithinPlacement) void {
        self.tracked = if (self.area.peek()) |a| switch (a) {
            .node => |n| TrackedNode.track(self.cx, n),
            .virtual => null,
        } else null;
    }

    /// A new area / padding: re-take the node's identity, lay out again so the after-layout pass
    /// re-places the content.
    fn effect(self: *WithinPlacement) void {
        _ = self.area.get();
        _ = self.padding.get();
        self.retrack();
        self.barrier.markLayoutDirty();
        self.cx.needs_redraw = true;
    }

    fn cleanup(self: *WithinPlacement) void {
        self.cx.removeAfterLayoutHook(self);
    }

    fn destroy(ptr: *anyopaque, alloc: std.mem.Allocator) void {
        alloc.destroy(@as(*WithinPlacement, @ptrCast(@alignCast(ptr))));
    }
};

test "visibleNodeRect: clipped by overflow-hidden ancestors, null when clipped away" {
    const cx = try Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    const root = try core.box(cx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    cx.root = root;
    const clip = try core.box(cx, .{ .width = .{ .px = 200 }, .height = .{ .px = 100 }, .overflow_hidden = true }, .{});
    try root.appendChild(std.testing.allocator, clip);
    const tall = try core.box(cx, .{ .width = .{ .px = 150 }, .height = .{ .px = 500 } }, .{});
    try clip.appendChild(std.testing.allocator, tall);
    cx.layout();
    const r = visibleNodeRect(cx, tall).?;
    try std.testing.expectApproxEqAbs(@as(f32, 150), r.w, 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 100), r.h, 0.5);
}

test "TrackedNode: get is null once the node is freed" {
    const cx = try Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    const root = try core.box(cx, .{}, .{});
    cx.root = root;
    const child = try core.box(cx, .{}, .{});
    try root.appendChild(std.testing.allocator, child);
    cx.layout();
    const tracked = TrackedNode.track(cx, child);
    try std.testing.expect(tracked.get(cx) == child);
    cx.detachChild(root, child);
    cx.freeNode(child);
    try std.testing.expect(tracked.get(cx) == null);
}
