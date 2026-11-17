//! Back / forward history over settings categories and their drill-down
//! subpages (ui-free so the settings Controller stays testable headless).
const std = @import("std");

/// Subpages per category, in `settings_pages.pages` order; checked against
/// the `settings_subpages` table at compile time.
pub const subpage_counts = [_]u8{ 3, 0, 4, 3, 3, 0, 2, 3, 0 };

/// 子页是运行时数据的分类（F-set-plugins）：协议插件——列表页（`sub == null`）→ 每个已注册插件一个详情页
/// （`sub` = 插件在注册表里的下标）。静态表里它的子页数是 0（没有概览）；这里只做上限检查，是否真有这个插件由
/// Controller 按注册表裁决（`Controller.show`）。
pub const dynamic_page: usize = 5;
pub const dynamic_subpage_capacity: u8 = 64;
pub fn isDynamic(page: usize) bool {
    return page == dynamic_page;
}

pub fn validSubpage(page: usize, sub: ?u8) ?u8 {
    const index = sub orelse return null;
    if (isDynamic(page)) return if (index < dynamic_subpage_capacity) index else null;
    return if (page < subpage_counts.len and index < subpage_counts[page]) index else null;
}

/// Back / forward history over (category, subpage) locations, like the
/// macOS System Settings toolbar. Selecting a category also records a step.
pub const Location = struct {
    page: u8 = 0,
    sub: ?u8 = null,
    /// F-set-ai：“AI 辅助 › 服务提供方”下某个提供方的详情页（第三级，动态：提供方是草稿数据）。只在
    /// `page` = AI 辅助、`sub` = 服务提供方时有意义；下标越界（提供方被删）时按列表页处理（`Controller.location`）。
    ai_provider: ?u8 = null,
};
pub const History = struct {
    const capacity = 32;
    items: [capacity]Location = @splat(.{}),
    len: u8 = 1,
    cursor: u8 = 0,

    pub fn current(self: History) Location {
        return self.items[self.cursor];
    }
    pub fn canBack(self: History) bool {
        return self.cursor > 0;
    }
    pub fn canForward(self: History) bool {
        return self.cursor + 1 < self.len;
    }
    /// Record a step; a repeat of the current location is not a new step.
    pub fn push(self: *History, location: Location) void {
        const now = self.current();
        if (std.meta.eql(now, location)) return;
        if (self.cursor + 1 == capacity) {
            std.mem.copyForwards(Location, self.items[0 .. capacity - 1], self.items[1..capacity]);
            self.cursor -= 1;
        }
        self.cursor += 1;
        self.items[self.cursor] = location;
        self.len = self.cursor + 1;
    }
    pub fn back(self: *History) ?Location {
        if (!self.canBack()) return null;
        self.cursor -= 1;
        return self.current();
    }
    pub fn forward(self: *History) ?Location {
        if (!self.canForward()) return null;
        self.cursor += 1;
        return self.current();
    }
    /// Start over at `location` (window reopened).
    pub fn reset(self: *History, location: Location) void {
        self.* = .{};
        self.items[0] = location;
    }
};


test "history records category and subpage steps and truncates forward steps" {
    var history: History = .{};
    history.push(.{ .page = 2 });
    history.push(.{ .page = 2, .sub = 1 });
    history.push(.{ .page = 2, .sub = 1 });
    try std.testing.expectEqual(@as(u8, 3), history.len);
    try std.testing.expectEqual(Location{ .page = 2 }, history.back().?);
    try std.testing.expect(history.canForward());
    history.push(.{ .page = 5 });
    try std.testing.expect(!history.canForward());
    try std.testing.expectEqual(Location{ .page = 2 }, history.back().?);
    try std.testing.expectEqual(Location{ .page = 0 }, history.back().?);
    try std.testing.expectEqual(@as(?Location, null), history.back());
    for (0..40) |i| history.push(.{ .page = @intCast(i % 9), .sub = @intCast(i % 2) });
    try std.testing.expectEqual(@as(u8, 32), history.len);
}
