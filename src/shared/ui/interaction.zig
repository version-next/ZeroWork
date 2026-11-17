//! 列表与浮层交互常量的唯一出处（CONSISTENCY_AUDIT #12、#13）。
//!
//! 用户拍板：提示延迟用 zenit 默认值。zenit 已有的值直接取 zenit 的字段默认值，不在这里另抄数字；
//! 各处 `W.Tooltip` 不再写 `openDelayMs`（直接用原生默认），只有需要拿到数值的地方
//! （自管计时、用 Popover 实现的悬停提示）引用这里。
const std = @import("std");
const ui = @import("ui");

/// 悬停提示的出现延迟（毫秒）：zenit 原生 Tooltip 的默认值。
pub const hint_delay_ms: f32 = (ui.widgets.tooltip.TooltipProps{ .text = .{ .value = "" } }).open_delay_ms;

/// 拖动排序 / 拖出的起拖距离（像素）：zenit drag 的默认值。按下后移动不到这个距离仍算点击。
pub const drag_activation: f32 = (ui.interaction.drag.Config{}).activation_distance;

/// 分隔条、侧栏宽度这类“按住即调整尺寸”的把手：移动 1 像素就开始跟随（不需要区分点击）。
pub const resize_drag_activation: f32 = 1;

test "constants come from zenit defaults" {
    try std.testing.expectEqual(@as(f32, 500), hint_delay_ms);
    try std.testing.expectEqual(@as(f32, 4), drag_activation);
}
