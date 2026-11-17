//! 会话记录的日期 / 时长文案：命令历史、终端回放与 AI 会话时间沿用同一格式。文案本体在
//! `model/record_labels.zig`；卡片视图的样式在 `history_card.yss`。
pub const dateLabel = @import("../model/record_labels.zig").dateLabel;
