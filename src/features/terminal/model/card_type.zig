//! `terminal` 卡片类型的放置约束（PLUGIN_ARCH_PLAN 2.5.4）：会话卡片，可独立成 tab、可进分屏、可浮动
//! （cards-float，用户判定“ssh类的也是可以floating的”）。浮动时仍属于原 tab，搬动同一个内容节点，会话照常
//! 运行。AI 声明（上下文由会话引擎组装、工具取会话所属插件登记的工具）由 features/ai 提供，在组合根与这里的
//! 约束合成一个类型登记（`linked_plugins.initRegistry`）。
const card_types = @import("../../../host/card_types.zig");

pub const def: card_types.CardTypeDef = .{
    .id = card_types.ids.terminal,
    .title = "终端",
    .binding = .session,
    .placements = .{ .standalone_tab = true, .split = true, .float = true },
    .default_placement = .standalone_tab,
    .float = card_types.sessionFloat(card_types.ids.terminal, card_types.float_sizes.terminal),
};
