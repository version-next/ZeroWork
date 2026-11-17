//! 列表的加载 / 空 / 失败（可重试）/ 有内容 状态模型（CONSISTENCY_AUDIT #5）。
//!
//! 各列表的 view-model 只报告事实（是否在读取、是否失败、有几项、是否在过滤），由这里得出唯一的
//! `Phase` 和占位文案；视图仍用原生组件（Spinner、按钮等），只按 `Phase` 显隐。“重新读取”只在
//! `failed` 时提供。用户拍板：空状态一律带说明文字，所以 `Copy` 的每一档都有标题和说明。
const std = @import("std");

pub const Phase = enum {
    loading,
    /// 读取失败，可重试。
    failed,
    /// 读取成功但没有内容（或过滤后没有匹配项）。
    empty,
    ready,
};

pub const Facts = struct {
    loading: bool = false,
    failed: bool = false,
    count: usize = 0,
};

/// 读取中优先于失败，失败优先于空。
pub fn resolve(facts: Facts) Phase {
    if (facts.loading) return .loading;
    if (facts.failed) return .failed;
    return if (facts.count == 0) .empty else .ready;
}

/// 只有失败时提供“重新读取”。
pub fn retryAvailable(phase: Phase) bool {
    return phase == .failed;
}

pub const Text = struct { title: []const u8, hint: []const u8 = "" };

/// 每个列表的占位文案。`no_match` 用于过滤后为空，`empty` 用于本来就没有内容。
pub const Copy = struct {
    loading: Text,
    failed: Text,
    no_match: Text,
    empty: Text,
};

/// 当前状态的占位文案；`ready` 时没有占位，返回 null。
pub fn placeholder(phase: Phase, filtered: bool, copy: Copy) ?Text {
    return switch (phase) {
        .loading => copy.loading,
        .failed => copy.failed,
        .empty => if (filtered) copy.no_match else copy.empty,
        .ready => null,
    };
}

test "phase precedence: loading, then failed, then empty" {
    try std.testing.expectEqual(Phase.loading, resolve(.{ .loading = true, .failed = true, .count = 3 }));
    try std.testing.expectEqual(Phase.failed, resolve(.{ .failed = true, .count = 3 }));
    try std.testing.expectEqual(Phase.empty, resolve(.{}));
    try std.testing.expectEqual(Phase.ready, resolve(.{ .count = 1 }));
    try std.testing.expect(retryAvailable(.failed));
    try std.testing.expect(!retryAvailable(.empty));
}

test "placeholder picks no_match only for filtered empty lists" {
    const copy: Copy = .{ .loading = .{ .title = "L" }, .failed = .{ .title = "F" }, .no_match = .{ .title = "N", .hint = "n" }, .empty = .{ .title = "E", .hint = "e" } };
    try std.testing.expectEqualStrings("N", placeholder(.empty, true, copy).?.title);
    try std.testing.expectEqualStrings("E", placeholder(.empty, false, copy).?.title);
    try std.testing.expectEqualStrings("F", placeholder(.failed, true, copy).?.title);
    try std.testing.expectEqual(@as(?Text, null), placeholder(.ready, false, copy));
}
