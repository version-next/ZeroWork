//! 测试卡片 `fixture.float`（float-split，只在 -Dtest-mode=true 构建里装配）：一张允许浮动与分屏、不能独立
//! 成 tab 的非会话卡片。今天的两张浮动卡片都不允许分屏（AI 对话 Q4 / 2.5.4、会话记录 Q11），所以
//! “放入分屏 ⇄ 浮动”的完整往返由它在 e2e 里走一遍。内容有可编辑的文字、可滚动的长列表与选中行，
//! 用来核对同一个内容节点在两种放置之间搬动时状态不丢。
const std = @import("std");
const card_types = @import("../../../host/card_types.zig");
const float_card = @import("../../../shared/base/float_card.zig");

pub const id = "fixture.float";
pub const title = "测试卡片";
pub const row_count = 40;

fn defaultSize(content: float_card.Rect) float_card.Size {
    return .{ .width = @min(380, @max(320, content.width * 0.3)), .height = @min(420, @max(240, content.height * 0.5)) };
}

pub const def: card_types.CardTypeDef = .{
    .id = id,
    .title = title,
    .binding = .standalone,
    .placements = .{ .split = true, .float = true },
    .default_placement = .float,
    .float = .{
        .id = id,
        .interactions = .initMany(&.{ .move, .resize, .maximize, .raise, .close, .fold_to_tab, .remember_position }),
        .min_size = .{ .width = 320, .height = 240 },
        .default_size = defaultSize,
        .first_open = .center,
    },
};

test "fixture card type: floats and splits, no standalone tab; placement actions derive from it" {
    try card_types.validate(def, struct {
        fn known(_: []const u8) bool {
            return false;
        }
    }.known);
    const descriptor = card_types.floatDescriptor(&def).?;
    try std.testing.expect(descriptor.supports(.dock_to_split) and !descriptor.supports(.open_as_tab));
}
