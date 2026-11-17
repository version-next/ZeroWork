//! 停靠宽度规则（用户拍板，Pencil 宽度画板 W800 `EMLQ5` / `Y7boO`，ai-redesign-c）：AI 停靠在分屏且窗格宽度
//! ≥ 760 时，对话与输入区共用一个 720 宽的居中内容列，两侧留白；窄于 760 或浮动时占满宽度。纯逻辑，宿主把
//! 返回的左右留白写到内容节点（`ai.content`）上，对话视口、待处理、提示、新消息提示与输入区都在它里面。
const std = @import("std");

/// The shared column width.
pub const column_width: f32 = 720;
/// Docked panes at least this wide use the column.
pub const min_docked_width: f32 = 760;

/// Left / right inset of the content node so its children form the centered column (0 = full width).
pub fn inset(docked: bool, width: f32) f32 {
    if (!docked or !std.math.isFinite(width) or width < min_docked_width) return 0;
    return @floor((width - column_width) / 2);
}

test "docked panes from 760 wide share one centered 720 column" {
    try std.testing.expectEqual(@as(f32, 0), inset(false, 1200));
    try std.testing.expectEqual(@as(f32, 0), inset(true, 560));
    try std.testing.expectEqual(@as(f32, 0), inset(true, 759.5));
    try std.testing.expectEqual(@as(f32, 20), inset(true, 760));
    try std.testing.expectEqual(@as(f32, 40), inset(true, 800));
    try std.testing.expectEqual(@as(f32, 140), inset(true, 1000));
    try std.testing.expectEqual(@as(f32, 0), inset(true, std.math.nan(f32)));
}
