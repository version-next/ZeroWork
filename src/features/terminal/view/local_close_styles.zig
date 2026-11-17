const ui = @import("ui");
const theme = @import("../../../shared/ui/theme/app_theme.zig");
// Content of the shared confirmation (`shared/ui/confirm`): the panel, title bar, message and
// buttons are zenit ConfirmDialog's defaults; only the frozen risk block is styled here.
/// The risk card sits inside the native confirmation Modal (an opaque panel).
pub fn riskFill() ui.Color {
    return @import("../../../shared/ui/styles/surface_material.zig").fill(theme.popupAction(), .solid);
}
pub fn risk() ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = 56 }, .direction = .column, .gap = 4, .padding = ui.Padding.all(8), .background = riskFill(), .border = .{ .radius = 9 }, .flex_shrink = 0 };
}
pub fn text(size: f32, strong: bool) ui.TextStyle {
    return .{ .font_size = size, .font_weight = if (strong) 500 else 400, .color = if (strong) theme.current().fg_1 else theme.current().fg_2, .line_height = (if (size == 11) @as(f32, 16) else 18) / size, .text_overflow = .ellipsis };
}
