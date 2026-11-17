//! 会话记录的卡片类型 `history`（PLUGIN_ARCH_PLAN 2.5.4、PL4b）。
//!
//! 一张完整卡片，内部是列表 + 详情。用户判定（6.2.1 Q11 / Q15 / Q21）：可独立成 tab，可浮动
//! （默认：从标题栏或侧栏入口打开即浮在窗口上），不进分屏（模型保留开关）；tab 可以同时开多张，
//! 每个所属 tab 最多一张浮动实例。不声明 AI（Q22）。
//!
//! 尺寸按设计稿校准（Pencil「ZW · 会话记录卡片补稿 2026-11-13（PL4b）」稿 B / 稿 C）：
//! 默认宽 = clamp(内容宽 × 0.7, 360, 960)、高 = clamp(内容高 × 0.72, 320, 640)，1440 × 900 窗口约
//! 820 × 600；最小 360 × 320；宽度小于 `split_min_width` 时列表与详情二选一（`card_vm.Layout`）。
const std = @import("std");
const card_types = @import("../../../host/card_types.zig");
const float_card = @import("../../../shared/base/float_card.zig");

pub const minimum_width: f32 = 360;
pub const minimum_height: f32 = 320;
/// 列表栏宽（稿 A / 稿 B：320）。
pub const list_width: f32 = 320;
/// 低于这个宽度时卡片只显示列表或只显示详情（列表 320 + 分隔 1 + 详情最少 279）。
pub const split_min_width: f32 = 600;

pub fn defaultSize(content: float_card.Rect) float_card.Size {
    return .{
        .width = @round(std.math.clamp(content.width * 0.7, minimum_width, 960)),
        .height = @round(std.math.clamp(content.height * 0.72, minimum_height, 640)),
    };
}

pub const float_descriptor: float_card.Descriptor = .{
    .id = card_types.ids.history,
    // 首次浮动在浮动区域内居中；没有锚点式首开（入口在标题栏与侧栏，不是每 tab 的图标）。
    .interactions = .initMany(&.{ .move, .resize, .maximize, .raise, .close, .fold_to_tab, .remember_position, .open_as_tab }),
    .min_size = .{ .width = minimum_width, .height = minimum_height },
    .default_size = defaultSize,
    .first_open = .center,
};

pub const def: card_types.CardTypeDef = .{
    .id = card_types.ids.history,
    .title = "会话记录",
    .binding = .standalone,
    .placements = .{ .standalone_tab = true, .split = false, .float = true },
    .default_placement = .float,
    .float = float_descriptor,
    .float_per_tab = 1,
};

fn anyHostTool(_: []const u8) bool {
    return true;
}
test "history card type satisfies registration constraints" {
    try card_types.validate(def, anyHostTool);
    try std.testing.expect(!def.placements.split and def.placements.standalone_tab and def.placements.float);
    try std.testing.expect(def.ai == null and def.float_per_tab.? == 1 and !def.supports_window_transfer);
    try std.testing.expect(!float_descriptor.supports(.open_from_anchor));
}

test "history default size follows the calibrated design" {
    // 1440 × 900 窗口的 tab body（约 1170 × 850）：约 820 × 600。
    const size = defaultSize(.{ .x = 268, .y = 48, .width = 1170, .height = 834 });
    try std.testing.expectEqual(@as(f32, 819), size.width);
    try std.testing.expectEqual(@as(f32, 600), size.height);
    const small = defaultSize(.{ .x = 0, .y = 0, .width = 400, .height = 300 });
    try std.testing.expectEqual(@as(f32, minimum_width), small.width);
    try std.testing.expectEqual(@as(f32, minimum_height), small.height);
    const large = defaultSize(.{ .x = 0, .y = 0, .width = 3000, .height = 2000 });
    try std.testing.expectEqual(@as(f32, 960), large.width);
    try std.testing.expectEqual(@as(f32, 640), large.height);
}
