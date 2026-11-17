//! 通用会话卡片 `session`：没有声明 `card_type` 的插件会话呈现为它（PLUGIN_ARCH_PLAN 2.5.4）。
//! 可独立成 tab、可进分屏、可浮动（cards-float：注册表里所有会话类卡片都可以浮动），不声明 AI——与今天
//! “任何会话 tab 都能入组”的规则一致。
const card_types = @import("../../../host/card_types.zig");

pub const session_def: card_types.CardTypeDef = .{
    .id = card_types.ids.session,
    .title = "会话",
    .binding = .session,
    .placements = .{ .standalone_tab = true, .split = true, .float = true },
    .default_placement = .standalone_tab,
    .float = card_types.sessionFloat(card_types.ids.session, card_types.float_sizes.terminal),
    // 插件渲染器呈现的会话 tab 可以整体移交到另一个窗口（渲染器另行声明是否支持）。
    .supports_window_transfer = true,
};
