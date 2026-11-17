//! 列表键盘导航的唯一实现（CONSISTENCY_AUDIT #5）：上下键移动当前行。
//!
//! `wrap`：到头后回到另一端（菜单、候选列表、会话记录）；`clamp`：停在两端（文件列表）。
//! 没有当前行时，向后从第一行开始、向前从最后一行开始。空列表返回 null。
const std = @import("std");

pub const Mode = enum { wrap, clamp };

/// 从 `current` 移动 `delta` 行（负数向前）。
pub fn step(current: ?usize, count: usize, delta: isize, mode: Mode) ?usize {
    if (count == 0) return null;
    const at = current orelse return if (delta >= 0) 0 else count - 1;
    const n: i128 = @intCast(count);
    const target = @as(i128, @intCast(@min(at, count - 1))) + delta;
    return @intCast(switch (mode) {
        .wrap => @mod(target, n),
        .clamp => std.math.clamp(target, 0, n - 1),
    });
}

/// 方向键的常用写法：`down` 为真时下一行，否则上一行。
pub fn move(current: ?usize, count: usize, down: bool, mode: Mode) ?usize {
    return step(current, count, if (down) 1 else -1, mode);
}

test "wrap cycles both ways and starts at the ends" {
    try std.testing.expectEqual(@as(?usize, null), move(null, 0, true, .wrap));
    try std.testing.expectEqual(@as(?usize, null), move(3, 0, false, .clamp));
    try std.testing.expectEqual(@as(?usize, 0), move(null, 4, true, .wrap));
    try std.testing.expectEqual(@as(?usize, 3), move(null, 4, false, .wrap));
    try std.testing.expectEqual(@as(?usize, 0), move(3, 4, true, .wrap));
    try std.testing.expectEqual(@as(?usize, 3), move(0, 4, false, .wrap));
    try std.testing.expectEqual(@as(?usize, 2), move(1, 4, true, .wrap));
    try std.testing.expectEqual(@as(?usize, 0), move(0, 1, true, .wrap));
    try std.testing.expectEqual(@as(?usize, 1), step(3, 4, 6, .wrap));
}

test "clamp stops at the ends; a stale index past the end is pulled back" {
    try std.testing.expectEqual(@as(?usize, 3), move(3, 4, true, .clamp));
    try std.testing.expectEqual(@as(?usize, 0), move(0, 4, false, .clamp));
    try std.testing.expectEqual(@as(?usize, 3), step(1, 4, 10, .clamp));
    try std.testing.expectEqual(@as(?usize, 0), step(1, 4, -10, .clamp));
    try std.testing.expectEqual(@as(?usize, 0), move(9, 2, false, .clamp));
    try std.testing.expectEqual(@as(?usize, 1), move(9, 2, true, .clamp));
}
