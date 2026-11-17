//! Where the AI header popovers (子智能体 · 会话列表) open (cards-float): beside their button in the
//! floating chrome, or beside the docked pane's "更多" button while the AI sits in a split — the same
//! entry points in both placements. The popover reads the anchor every frame (virtual anchor), so
//! moving the AI between the two places only re-points it.
//!
//! ai-redesign-c（Pencil O7 / O8 `SmqQV` / `TTNSh`）：弹层宽 360，但不能超出面板——420 宽的浮动面板上旧的 440 宽
//! 弹层盖出面板右缘。宽度取 `min(360, 面板宽 − 2 × 8)`，横向位置夹在面板左右各 8 以内；停靠时右对齐“更多”。
const std = @import("std");
const ui = @import("ui");

/// Design width (O7 / O8 W.Popover 360).
pub const design_width: f32 = 360;
/// Inset kept from the panel's left / right edge.
pub const panel_inset: f32 = 8;
/// Narrowest popover worth showing (a panel narrower than this + insets still gets this width).
pub const min_width: f32 = 240;

pub const Rect = struct { x: f32, y: f32, w: f32, h: f32 };

/// The popover width inside a panel `panel_w` wide.
pub fn width(panel_w: ?f32) f32 {
    const w = panel_w orelse return design_width;
    if (w <= 0) return design_width;
    return @max(min_width, @min(design_width, w - 2 * panel_inset));
}

/// The anchor rect handed to the popover (`bottom_start`: the popover's left edge = the rect's x).
/// `trigger` is the button the popover belongs to; `right_align` lines the popover's right edge up
/// with the trigger's (docked 更多); `panel` keeps it inside the AI panel / pane.
pub fn place(trigger: Rect, popover_w: f32, right_align: bool, panel: ?Rect) Rect {
    var x = if (right_align) trigger.x + trigger.w - popover_w else trigger.x;
    if (panel) |p| if (p.w > 0) {
        const lo = p.x + panel_inset;
        const hi = p.x + p.w - panel_inset - popover_w;
        x = if (hi < lo) lo else std.math.clamp(x, lo, hi);
    };
    return .{ .x = x, .y = trigger.y, .w = popover_w, .h = trigger.h };
}

pub const Anchor = struct {
    /// The chrome slot button the popover belongs to.
    node: *ui.Node,
    /// The docked pane's "更多" button while docked; null = the chrome button.
    override: ?*ui.Node = null,
    /// The AI panel (floating chrome root) or the docked pane the popover must stay inside.
    bounds: ?*ui.Node = null,
    /// Kept for callers that size before the first layout; the live width is `currentWidth`.
    width: f32 = design_width,

    pub fn popover(self: *Anchor) ui.widgets.popover.Anchor {
        return .{ .virtual = .{ .ctx = self, .getRect = rect } };
    }
    pub fn panelRect(self: *const Anchor) ?Rect {
        const node = self.bounds orelse return null;
        const r = node.globalRect();
        if (r.w <= 0 or r.h <= 0) return null;
        return .{ .x = r.x, .y = r.y, .w = r.w, .h = r.h };
    }
    /// The popover width for the panel as it is now.
    pub fn currentWidth(self: *const Anchor) f32 {
        return width(if (self.panelRect()) |p| p.w else null);
    }
    fn rect(raw: *anyopaque) ui.widgets.popover.AnchorRect {
        const self: *Anchor = @ptrCast(@alignCast(raw));
        const target = self.override orelse self.node;
        const r = target.globalRect();
        const placed = place(.{ .x = r.x, .y = r.y, .w = r.w, .h = r.h }, self.currentWidth(), self.override != null, self.panelRect());
        return .{ .x = placed.x, .y = placed.y, .w = placed.w, .h = placed.h };
    }
};

test "popover width never exceeds the panel" {
    try std.testing.expectEqual(@as(f32, 360), width(null));
    try std.testing.expectEqual(@as(f32, 360), width(800));
    try std.testing.expectEqual(@as(f32, 360), width(420 - 44));
    try std.testing.expectEqual(@as(f32, 304), width(320));
    try std.testing.expectEqual(@as(f32, min_width), width(200));
}

test "popover stays inside the panel and right-aligns beside 更多" {
    const panel: Rect = .{ .x = 100, .y = 50, .w = 420, .h = 640 };
    // Chrome button near the right edge: shifted left so the right edge stays 8 inside.
    const near_right = place(.{ .x = 400, .y = 60, .w = 24, .h = 24 }, 360, false, panel);
    try std.testing.expectEqual(@as(f32, 100 + 420 - 8 - 360), near_right.x);
    try std.testing.expect(near_right.x + near_right.w <= panel.x + panel.w - 8);
    // Left button: stays at the button.
    const left = place(.{ .x = 120, .y = 60, .w = 24, .h = 24 }, 360, false, panel);
    try std.testing.expectEqual(@as(f32, 120), left.x);
    // Docked 更多: right edges line up.
    const more = place(.{ .x = 476, .y = 60, .w = 24, .h = 24 }, 360, true, panel);
    try std.testing.expectEqual(@as(f32, 500 - 360), more.x);
    // No panel known yet: plain placement.
    try std.testing.expectEqual(@as(f32, 400), place(.{ .x = 400, .y = 0, .w = 24, .h = 24 }, 360, false, null).x);
}
