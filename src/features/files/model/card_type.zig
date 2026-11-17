//! `file` 卡片类型的放置约束（PLUGIN_ARCH_PLAN 2.5.4）：会话卡片（SFTP 文件工作区），可独立成 tab、
//! 可进分屏（V0.3 混合会话组）、可浮动（cards-float：传输与列表状态随同一个内容节点保留）。AI 声明由
//! features/ai 提供，在组合根合成。
const card_types = @import("../../../host/card_types.zig");

pub const def: card_types.CardTypeDef = .{
    .id = card_types.ids.file,
    .title = "文件",
    .binding = .session,
    .placements = .{ .standalone_tab = true, .split = true, .float = true },
    .default_placement = .standalone_tab,
    .float = card_types.sessionFloat(card_types.ids.file, card_types.float_sizes.file),
};
