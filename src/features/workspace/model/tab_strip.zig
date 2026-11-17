//! 页签条（design-r3 稿 3）的行数据与外观状态：纯数据，视图是 `view/tab_strip.yix`，挂载与信号在
//! `view/tab_strip_view.zig`。行由 workspace 每次同步时重算，按页签 id 调和（同一个页签的行原地更新）。
const std = @import("std");

/// Pencil SHfTh 页签面状态：激活页签保持岛面；非激活页签按下（指针仍在其中）优先于悬停。
pub const State = enum { normal, hover, press, active };

/// 一个页签面的外观输入（宽度 + 状态 + 拖起 / 合组目标），给 `tab_strip.yss` 的样式函数。
pub const Look = struct {
    width: f32,
    state: State = .normal,
    lifted: bool = false,
    drop: bool = false,
};

pub fn state(active: bool, hovered: bool, pressed: bool) State {
    if (active) return .active;
    if (pressed and hovered) return .press;
    if (hovered) return .hover;
    return .normal;
}

/// 一行（一个可见页签）。字符串由视图模型持有（双缓冲），替换前一直有效。
pub const Row = struct {
    /// 页签 id（`identity.TabId` 的整数值）；keyed 调和的键。
    id: u64,
    width: f32,
    active: bool = false,
    previous_id: ?u64 = null,
    previous_active: bool = false,
    grouped: bool = false,
    name: []const u8 = "",
    /// 组页签的“(n)”；普通页签为空。
    count: []const u8 = "",
    title_width: f32 = 0,
    count_width: f32 = 0,
    tip: []const u8 = "",
    /// 按住 ⌘ 时关闭槽里的“⌘1…⌘9”（序号只在前 8 个与最后一个页签上有）。
    ordinal: []const u8 = "",
    close_label: []const u8 = "关闭页签",
    test_id: []const u8 = "",
    cell_test_id: []const u8 = "",
    close_test_id: []const u8 = "",
    /// Z12 `motionAnchor` 名（`tabAnchorId`）：页签所属的浮动卡片（AI 面板）收进 / 展开自这个页签。
    anchor: []const u8 = "",
};

/// Z12 锚点名前缀（与 ai-panel-anchor 的 `shared/base/tab_motion_anchor.zig` 约定一致）。
pub const anchor_prefix = "workspace.tab.";

/// 页签的 `motionAnchor` 名：`workspace.tab.<页签 id>`。渲染出的每个页签面都以这个名字登记为锚点
/// （`tab_strip.yix` 页签面上的 `motionAnchor`），页签被收进“⌄ n”时不登记（锚点查找回落到调用方的默认处理）。
/// `buffer` 至少 36 字节；不够时返回 null。
pub fn tabAnchorId(buffer: []u8, tab_id: u64) ?[]const u8 {
    return std.fmt.bufPrint(buffer, anchor_prefix ++ "{d}", .{tab_id}) catch null;
}

test "tab strip: anchor names and states" {
    var buffer: [36]u8 = undefined;
    try std.testing.expectEqualStrings("workspace.tab.42", tabAnchorId(&buffer, 42).?);
    try std.testing.expectEqualStrings("workspace.tab.18446744073709551615", tabAnchorId(&buffer, std.math.maxInt(u64)).?);
    var tiny: [4]u8 = undefined;
    try std.testing.expect(tabAnchorId(&tiny, 42) == null);
    try std.testing.expectEqual(State.active, state(true, true, true));
    try std.testing.expectEqual(State.press, state(false, true, true));
    try std.testing.expectEqual(State.normal, state(false, false, true));
    try std.testing.expectEqual(State.hover, state(false, true, false));
}
