/// Sheet, style layer
///
/// Overlay / panel coloring, shadow and content area styles; overlay lifecycle and slide-in
/// animation in mod.zig.
const core = @import("../../core.zig");
const theme = core.theme;
const Color = core.Color;
const Padding = core.Padding;

/// What the panel style depends on besides the theme (fixed at mount).
pub const Panel = struct {
    side: @import("mod.zig").SheetSide,
    width: f32,
    height: f32,
    /// Props override; null = token bg_primary.
    background: ?Color,
};

/// Panel: size along the side, background (props override priority), shadow.lg and the client
/// edge separator. Re-resolved on theme switch (`view.styleBy`).
pub fn sheetPanel(p: Panel, t: *const theme.ThemeTokens) core.BoxStyle {
    var s = sheetPanelEdge(t, p.side);
    s.width = switch (p.side) {
        .left, .right => .{ .px = p.width },
        .top, .bottom => .{ .grow = .{} },
    };
    s.height = switch (p.side) {
        .left, .right => .{ .grow = .{} },
        .top, .bottom => .{ .px = p.height },
    };
    s.background = p.background orelse t.tokens.color.bg_primary;
    s.shadows = core.ShadowList.of(&.{t.tokens.shadow.lg});
    return s;
}

/// `view.styleBy` key of a style that depends on the theme only.
pub const Themed = struct {};

pub fn sheetContent(_: Themed, t: *const theme.ThemeTokens) core.BoxStyle {
    return sheetContentStyle(t);
}

pub fn sheetContentStyle(t: *const theme.ThemeTokens) core.BoxStyle {
    return .{
        .direction = .column,
        .width = .{ .grow = .{} },
        .height = .{ .grow = .{} },
        // Fills the panel and never more (docs/design/flex-slot-automatic-minimum.md): content
        // taller than the panel stays inside this box, so a ScrollArea in it scrolls and what
        // follows it stays on the panel. Both axes: the panel is a column on every side.
        .min_width = 0,
        .min_height = 0,
        .padding = Padding.all(t.tokens.space.space300),
    };
}

/// Only the edge facing the client gets a separator (Sheet / right in COMPONENTS.json).
pub fn sheetPanelEdge(t: *const theme.ThemeTokens, side: @import("mod.zig").SheetSide) core.BoxStyle {
    return .{
        .border_overlay = true,
        .border_color = t.tokens.color.border,
        .border_left_width = if (side == .right) 1 else 0,
        .border_right_width = if (side == .left) 1 else 0,
        .border_top_width = if (side == .bottom) 1 else 0,
        .border_bottom_width = if (side == .top) 1 else 0,
    };
}
