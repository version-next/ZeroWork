//! `ai.chat` 卡片类型（PLUGIN_ARCH_PLAN 2.5.4、2.5.8）：浮动，也可以放进所属 tab 的分屏（cards-float，
//! 用户判定“AI chat也是可以放回cards layout的”，覆盖 Q4 的“只保留浮动”）；仍不能单独成 tab。绑定所属
//! tab（M10），自身不声明 AI（它是上下文的消费者）。浮动声明就是通用卡片浮动层的 `float_model.descriptor`。
const card_types = @import("../../../../host/card_types.zig");
const float_model = @import("../../../../ai/float_model.zig");

pub const def: card_types.CardTypeDef = .{
    .id = card_types.ids.ai_chat,
    .title = "AI 对话",
    .binding = .tab,
    .placements = .{ .split = true, .float = true },
    .default_placement = .float,
    .float = float_model.descriptor,
};
