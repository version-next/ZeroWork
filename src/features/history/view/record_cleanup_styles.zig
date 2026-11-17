//! 会话记录清理：对话框、标题栏、说明与按钮都是共享原生确认框（zenit ConfirmDialog）的默认外观；
//! 这里只有插槽里两行文字的样式。
const ui = @import("ui");
const theme = @import("../../../shared/ui/theme/app_theme.zig");
pub fn text(size: f32, height: f32, weight: u16) ui.TextStyle {
    return .{ .font_size = size, .line_height = height / size, .font_weight = weight, .color = theme.current().fg_1, .wrap = .word, .selectable = false };
}
