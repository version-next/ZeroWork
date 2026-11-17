//! 浮动卡片放入分屏（float-split，PLUGIN_ARCH_PLAN 2.5.1 / 2.5.7）：浮动卡片的头部“放入分屏”把同一张
//! 卡片（同一个内容节点）放进它所属 tab 的 tab body 分屏，成为一个窗格；窗格头部“浮动”把它送回上次的
//! 浮动位置。这里是与视图无关的规则：
//!
//! - **叶子身份**：分屏树（`group_layout.Tree`）的叶子是卡片。会话卡片的叶子是会话 ID；非会话卡片不是
//!   roster 成员（M6），由 workspace 按序分配带 `card_leaf_bit` 的叶子 ID，与会话 ID 不会相撞。
//! - **方向与位置**（`edgeFor`）：浮动卡片的中心落在 tab body 外圈四分之一带里时，放在离它最近的那一边；
//!   中心在中间区域（或者 tab body 还没有尺寸）时默认放在右侧。新窗格放在整棵分屏树的那一边（不插进某个
//!   已有窗格内部），占 1 / (n + 1)：所属 tab 原来只有单卡时变成两卡分屏，已经是分屏时追加一个窗格。
//! - **容量**（`fits`）：新窗格加上已有的 n 个窗格，在 tab body 的宽或高上仍能保证每张卡片的最小尺寸
//!   （宽 320 / 高 100，间距 4，与分屏现有的最小尺寸同源）才放得下，否则提示“分屏已满”。
//! - **不可用原因**（`Refusal`）：卡片类型不允许分屏由卡片类型自己说明（`card_types.placementRefusal`）；
//!   这里只有所属 tab 的状态原因。
const std = @import("std");
const layout = @import("group_layout.zig");

pub const Edge = layout.Edge;
pub const Rect = struct { x: f32, y: f32, w: f32, h: f32 };

/// 非会话卡片叶子 ID 的标记位（会话 ID 是从 1 递增的计数，不会用到最高位）。
pub const card_leaf_bit: u64 = 1 << 63;

pub fn cardLeaf(sequence: u64) u64 {
    return card_leaf_bit | (sequence & ~card_leaf_bit);
}
pub fn isCardLeaf(leaf: u64) bool {
    return leaf & card_leaf_bit != 0;
}

/// 外圈带宽（相对 tab body 宽 / 高的比例）：中心落在这里才算“靠近某一边”。
pub const edge_band: f32 = 0.25;

/// 放入分屏的一侧：中心靠近哪边放哪边，否则右侧。
pub fn edgeFor(body: Rect, card: Rect) Edge {
    if (body.w <= 0 or body.h <= 0) return .right;
    const cx = std.math.clamp((card.x + card.w / 2 - body.x) / body.w, 0, 1);
    const cy = std.math.clamp((card.y + card.h / 2 - body.y) / body.h, 0, 1);
    const distances = [_]struct { edge: Edge, d: f32 }{
        .{ .edge = .right, .d = 1 - cx },
        .{ .edge = .left, .d = cx },
        .{ .edge = .bottom, .d = 1 - cy },
        .{ .edge = .top, .d = cy },
    };
    var best = distances[0];
    for (distances[1..]) |entry| if (entry.d < best.d) {
        best = entry;
    };
    return if (best.d < edge_band) best.edge else .right;
}

/// `panes` 个已有窗格再加一个，tab body 放不放得下（任一方向能排开即可，分屏会按宽度改为上下排列）。
pub fn fits(body: Rect, panes: usize) bool {
    if (body.w <= 0 or body.h <= 0) return true;
    const n: f32 = @floatFromInt(panes + 1);
    const gaps = (n - 1) * layout.card_gap;
    return n * layout.min_card_width + gaps <= body.w + 0.5 or n * layout.min_card_height + gaps <= body.h + 0.5;
}

/// 所属 tab 的状态不允许放入分屏的原因。
pub const Refusal = enum {
    /// 卡片不属于任何 tab（打开时窗口里没有 tab）。
    no_tab,
    /// 所属 tab 的卡片不能进分屏（例如会话记录 tab），或不是会话 tab。
    tab_not_splittable,
    /// 所属 tab 正在关闭或尚未就绪。
    tab_busy,
    /// 再放一个窗格就小于卡片最小尺寸。
    full,

    pub fn text(self: Refusal) []const u8 {
        return switch (self) {
            .no_tab => "没有可放入分屏的标签页",
            .tab_not_splittable => "所属标签页不能分屏",
            .tab_busy => "所属标签页正在关闭或尚未就绪",
            .full => "所属标签页的分屏已满",
        };
    }
};

test "dock edge: nearest side inside the outer quarter band, otherwise right" {
    const body: Rect = .{ .x = 240, .y = 44, .w = 1200, .h = 800 };
    // Centre in the middle: default right.
    try std.testing.expectEqual(Edge.right, edgeFor(body, .{ .x = 640, .y = 244, .w = 400, .h = 400 }));
    // Near each side.
    try std.testing.expectEqual(Edge.right, edgeFor(body, .{ .x = 1100, .y = 300, .w = 300, .h = 300 }));
    try std.testing.expectEqual(Edge.left, edgeFor(body, .{ .x = 250, .y = 300, .w = 200, .h = 300 }));
    try std.testing.expectEqual(Edge.top, edgeFor(body, .{ .x = 640, .y = 50, .w = 400, .h = 200 }));
    try std.testing.expectEqual(Edge.bottom, edgeFor(body, .{ .x = 640, .y = 640, .w = 400, .h = 200 }));
    // Floating over the sidebar (centre left of the body): clamped, nearest is left.
    try std.testing.expectEqual(Edge.left, edgeFor(body, .{ .x = 0, .y = 300, .w = 200, .h = 200 }));
    // No layout yet.
    try std.testing.expectEqual(Edge.right, edgeFor(.{ .x = 0, .y = 0, .w = 0, .h = 0 }, .{ .x = 0, .y = 0, .w = 10, .h = 10 }));
}

test "dock capacity keeps every card at its minimum size in one direction" {
    try std.testing.expect(fits(.{ .x = 0, .y = 0, .w = 644, .h = 100 }, 1));
    try std.testing.expect(!fits(.{ .x = 0, .y = 0, .w = 643, .h = 203 }, 1));
    try std.testing.expect(fits(.{ .x = 0, .y = 0, .w = 300, .h = 204 }, 1));
    try std.testing.expect(fits(.{ .x = 0, .y = 0, .w = 0, .h = 0 }, 9));
}

test "card leaves never collide with session ids" {
    try std.testing.expect(isCardLeaf(cardLeaf(1)) and !isCardLeaf(1) and !isCardLeaf(std.math.maxInt(u63)));
    try std.testing.expect(cardLeaf(1) != cardLeaf(2));
}
