//! Group close: the dialog is the shared native confirmation (zenit ConfirmDialog); only the frozen
//! member ledger inside it is styled here.
const ui = @import("ui");
const theme = @import("../../../shared/ui/theme/app_theme.zig");
pub fn text(strong: bool) ui.TextStyle {
    return .{ .font_size = 12, .color = if (strong) theme.current().fg_1 else theme.current().fg_2, .line_height = 1.5, .wrap = .word };
}
pub fn note() ui.TextStyle {
    return .{ .font_size = 10.5, .color = theme.current().fg_2, .line_height = 16.0 / 10.5, .wrap = .word };
}
pub fn list() ui.BoxStyle {
    return .{ .direction = .column, .width = .fill(), .gap = 6, .padding = ui.Padding.all(8), .background = theme.popupInset(), .border = .{ .radius = 8 } };
}
pub fn scroll(partial: bool) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = if (partial) 132 else 180 }, .flex_shrink = 0 };
}
pub fn scrollContent() ui.BoxStyle {
    return .{ .direction = .column, .width = .fill(), .gap = 0 };
}
