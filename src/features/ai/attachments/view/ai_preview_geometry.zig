//! Shared attachment bubble bounds: 78% × 78% of the workspace content (~61%).
const ui = @import("ui");
pub fn bounds(cx: *ui.Cx, content: ?*ui.Node) ui.ComputedRect {
    const area = if (content) |node| node.globalRect() else ui.ComputedRect{ .x = 0, .y = 0, .w = cx.viewport.width, .h = cx.viewport.height };
    const w = @max(1, @min(area.w - 24, area.w * 0.78));
    const h = @max(1, @min(area.h - 24, area.h * 0.78));
    return .{ .x = area.x + (area.w - w) / 2, .y = area.y + (area.h - h) / 2, .w = w, .h = h };
}
pub fn panel(rect: ui.ComputedRect, _: bool) ui.BoxStyle {
    // Reapplied on resize. Geometry only: the panel surface (background,
    // border, radius, shadow) is zenit Modal's default.
    return .{ .position = .absolute, .inset = .{ .left = .{ .px = rect.x }, .top = .{ .px = rect.y } }, .width = .{ .px = rect.w }, .height = .{ .px = rect.h }, .max_height = rect.h, .padding = .{}, .gap = 0, .direction = .column, .flex_shrink = 0, .overflow = .hidden };
}
