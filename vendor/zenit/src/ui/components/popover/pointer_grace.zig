const core = @import("../../core.zig");
const floating = @import("../../compute_position.zig");

pub const duration_ms = 350;

/// The corridor narrows to the last point on the trigger and opens to the
/// facing edge of the positioned panel. Use the actual side after flipping.
pub fn contains(origin: core.Point, pointer: core.Point, panel: floating.Rect, side: floating.Side) bool {
    const horizontal = side == .left or side == .right;
    const edge = switch (side) {
        .top => panel.y + panel.h,
        .bottom => panel.y,
        .left => panel.x + panel.w,
        .right => panel.x,
    };
    const from_main = if (horizontal) origin.x else origin.y;
    const to_main = if (horizontal) pointer.x else pointer.y;
    const distance = edge - from_main;
    if (@abs(distance) < 0.01) return false;
    const progress = (to_main - from_main) / distance;
    if (progress < 0 or progress > 1) return false;
    const from_cross = if (horizontal) origin.y else origin.x;
    const to_cross = if (horizontal) pointer.y else pointer.x;
    const start = if (horizontal) panel.y else panel.x;
    const extent = if (horizontal) panel.h else panel.w;
    const low = from_cross + (start - from_cross) * progress;
    const high = from_cross + (start + extent - from_cross) * progress;
    return to_cross >= low - 1 and to_cross <= high + 1;
}
