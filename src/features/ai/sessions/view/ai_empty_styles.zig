//! Empty assistant states (Pencil A1 `iDZz1` setup guide, A2 `ZF1PS` welcome; ai-redesign-c). Buttons,
//! Tooltips and the setup guide are native (W.Button, W.Tooltip, W.Empty); here only layout and body text
//! in zenit tokens.
const ui = @import("ui");
/// Welcome page: welcome · suggestions · recent, 24 apart, left-aligned.
pub fn root(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .min_width = 0, .direction = .column, .gap = 24, .flex_shrink = 0 };
}
/// sparkles 20 · title 16/600, 6 apart; 56 from the top, 4 in from the sides (A2 Hpgjj).
pub fn welcome(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .direction = .column, .gap = 6, .padding = .{ .top = 56, .left = 4, .right = 4 }, .flex_shrink = 0 };
}
pub fn welcomeIcon() ui.Style {
    return .{ .width = .{ .px = 20 }, .height = .{ .px = 20 }, .flex_shrink = 0 };
}
pub fn welcomeTitle(t: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 16, .font_weight = 600, .line_height = 1.5, .color = t.tokens.color.fg_primary };
}
/// The two quick prompts, 8 apart, 4 in from the sides (A2 UlLVg).
pub fn row(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .min_width = 0, .direction = .row, .align_items = .center, .gap = 8, .padding = .{ .left = 4, .right = 4 }, .flex_shrink = 0 };
}
/// One starter's half of the row (the native Tooltip's wrapper and trigger around a block Button).
pub fn starterSlot() ui.BoxStyle {
    return .{ .width = .fill(), .flex = 1, .min_width = 0, .direction = .row, .align_items = .center };
}
/// 最近会话 (A2 wpVHR): heading 11/500 fg-tertiary (12 in), rows 2 apart.
pub fn recentGroup(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .min_width = 0, .direction = .column, .gap = 2, .flex_shrink = 0 };
}
pub fn recentHeading(t: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 11, .font_weight = 500, .line_height = 1.5, .color = t.tokens.color.fg_tertiary, .selectable = false };
}
pub fn recentHeadingBox() ui.BoxStyle {
    return .{ .width = .fill(), .padding = .{ .left = 12, .right = 12 }, .flex_shrink = 0 };
}
/// The setup guide's holder (the native W.Empty centers its own lines).
pub fn setup() ui.BoxStyle {
    return .{ .width = .fill(), .direction = .column, .align_items = .center, .flex_shrink = 0 };
}
