//! The part of a node that is actually on screen: its rect clipped by every clipping ancestor
//! (scrolled ones included) and the viewport. Visual timers use it so that offscreen or hidden
//! content does not keep requesting frames.
const ui = @import("ui");
pub const Rect = ui.ComputedRect;
pub fn intersection(a: Rect, b: Rect) Rect {
    const x = @max(a.x, b.x);
    const y = @max(a.y, b.y);
    return Rect.init(x, y, @max(0, @min(a.x + a.w, b.x + b.w) - x), @max(0, @min(a.y + a.h, b.y + b.h) - y));
}
pub const Snapshot = struct { rect: Rect, clip: Rect, visible: Rect };
/// Reads the physical clip chain once, including scrolled ancestors. Useful
/// for visual timers too: offscreen content must not keep requesting frames.
pub fn snapshot(cx: *ui.Cx, node: *ui.Node) ?Snapshot {
    const bounds = node.globalRect();
    var clip = Rect.init(0, 0, cx.viewport.width, cx.viewport.height);
    var cursor: ?*ui.Node = node;
    var world = bounds;
    while (cursor) |current| {
        if (current.style.display == .none) return null;
        if (current != node and (current.style.overflow != .visible or current.style.overflow_hidden)) clip = intersection(clip, world);
        const local = current.rectFromWorldOrFallback();
        world.x -= local.x + current.style.translate_x + current.frame_state.frame_local.runtime.sticky.x;
        world.y -= local.y + current.style.translate_y + current.frame_state.frame_local.runtime.sticky.y;
        cursor = current.parent;
        if (cursor) |parent| {
            const r = parent.rectFromWorldOrFallback();
            world.w = r.w;
            world.h = r.h;
        }
    }
    const region = intersection(bounds, clip);
    return if (region.w > 0 and region.h > 0) .{ .rect = bounds, .clip = clip, .visible = region } else null;
}
