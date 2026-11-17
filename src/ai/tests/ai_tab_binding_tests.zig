//! M10（PLUGIN_ARCH_PLAN 2.5.8）：AI 对话统一绑定到 tab。
//! - 旧日志（schema 1–3，session / group 归属）只读、能完整回放；
//! - 新写入的行都是 schema 4、归属为 tab；schema 4 之前的行出现 tab 归属即拒绝；
//! - 用只读的旧归属 attach / handoff 被拒绝；交接只在两个不同的 tab 之间进行。
const std = @import("std");
const a = std.testing.allocator;
const life = @import("../session_lifecycle.zig");
const Journal = @import("../session_journal.zig").Journal;
const scope = @import("../tool_scope.zig");

fn replaceAll(allocator: std.mem.Allocator, text: []const u8, needle: []const u8, replacement: []const u8) ![]u8 {
    return std.mem.replaceOwned(u8, allocator, text, needle, replacement);
}

test "M10 journal writes schema 4 tab rows and replays legacy session and group rows read-only" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    // 1. 用本版本写一份日志：两个 tab 各一个对话。
    {
        var journal = try Journal.open(a, std.testing.io, tmp.dir, "new.jsonl");
        defer journal.deinit();
        var store = life.Store.init(a);
        defer store.deinit();
        try journal.bind(&store);
        const single = try store.attach(.{ .tab = 5 });
        _ = try store.create(single.id);
        const split = try store.attach(.{ .tab = 9 });
        _ = try store.create(split.id);
        var lines = std.mem.splitScalar(u8, std.mem.trimEnd(u8, journal.bytes.items, "\n"), '\n');
        while (lines.next()) |line| {
            try std.testing.expect(std.mem.startsWith(u8, line, "{\"schema\":4,"));
        }
        try std.testing.expect(std.mem.indexOf(u8, journal.bytes.items, "\"owner\":{\"tab\":5}") != null);
        try std.testing.expect(std.mem.indexOf(u8, journal.bytes.items, "\"owner\":{\"tab\":9}") != null);
        try std.testing.expect(std.mem.indexOf(u8, journal.bytes.items, "\"session\":") == null and std.mem.indexOf(u8, journal.bytes.items, "\"group\":") == null);
        // 2. 把它改写成 M10 之前的格式：schema 1、session / group 归属（旧版本写出的就是这种行）。
        const step1 = try replaceAll(a, journal.bytes.items, "\"schema\":4", "\"schema\":1");
        defer a.free(step1);
        const step2 = try replaceAll(a, step1, "{\"tab\":5}", "{\"session\":5}");
        defer a.free(step2);
        const legacy = try replaceAll(a, step2, "{\"tab\":9}", "{\"group\":9}");
        defer a.free(legacy);
        try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "legacy.jsonl", .data = legacy });
        // schema 4 之前的行里出现 tab 归属是格式错误。
        const forged = try replaceAll(a, journal.bytes.items, "\"schema\":4", "\"schema\":3");
        defer a.free(forged);
        try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "forged.jsonl", .data = forged });
    }
    // 3. 旧日志完整回放：来源仍是旧的 session / group 归属（只读，只用于显示来源）。
    var journal = try Journal.open(a, std.testing.io, tmp.dir, "legacy.jsonl");
    defer journal.deinit();
    var store = life.Store.init(a);
    defer store.deinit();
    try journal.bind(&store);
    try std.testing.expectEqual(@as(usize, 2), store.records.items.len);
    var saw_session = false;
    var saw_group = false;
    for (store.records.items) |record| {
        const origin = record.initial_origin.?;
        try std.testing.expect(origin.legacy());
        if (origin.eql(.{ .session = 5 })) saw_session = true;
        if (origin.eql(.{ .group = 9 })) saw_group = true;
        try std.testing.expect(record.binding.?.owner.eql(origin));
    }
    try std.testing.expect(saw_session and saw_group);
    // 4. 旧归属不能创建新绑定；tab 归属可以，且新行是 schema 4。
    try std.testing.expectError(error.ReadOnlyOwner, store.attach(.{ .session = 5 }));
    try std.testing.expectError(error.ReadOnlyOwner, store.attach(.{ .group = 9 }));
    const before = journal.bytes.items.len;
    const fresh = try store.attach(.{ .tab = 5 });
    _ = try store.create(fresh.id);
    const appended = journal.bytes.items[before..];
    try std.testing.expect(std.mem.startsWith(u8, appended, "{\"schema\":4,"));
    try std.testing.expect(std.mem.indexOf(u8, appended, "\"owner\":{\"tab\":5}") != null);
    // 5. schema 3 的行带 tab 归属：拒绝。
    var forged = try Journal.open(a, std.testing.io, tmp.dir, "forged.jsonl");
    defer forged.deinit();
    var rejected = life.Store.init(a);
    defer rejected.deinit();
    try std.testing.expectError(error.InvalidSessionJournal, forged.bind(&rejected));
}

test "M10 handoff moves a conversation only between two different tabs" {
    var store = life.Store.init(a);
    defer store.deinit();
    const single = try store.attach(.{ .tab = 5 });
    const fence = try store.create(single.id);
    try std.testing.expectError(error.InvalidBindingHandoff, store.handoff(fence, .{ .group = 9 }));
    try std.testing.expectError(error.InvalidBindingHandoff, store.handoff(fence, .{ .tab = 5 }));
    // 容器 tab 已有附着的对话：冲突。
    const occupied = try store.attach(.{ .tab = 90 });
    _ = try store.create(occupied.id);
    try std.testing.expectError(error.BindingConflict, store.handoff(fence, .{ .tab = 90 }));
    const moved = try store.handoff(fence, .{ .tab = 91 });
    try std.testing.expect(store.find(moved.conversation).?.binding.?.owner.eql(.{ .tab = 91 }));
    try std.testing.expect(store.find(moved.conversation).?.initial_origin.?.eql(.{ .tab = 5 }));
}

test "M10 scope: a single-card tab targets only its own card and a split tab only its members" {
    const single: scope.Scope = .{ .owner = .{ .tab = 3 }, .content = .{ .session = 101 }, .members = .{ .ids = .{101} ++ @as([15]u64, @splat(0)), .len = 1 } };
    _ = try single.validate(&.{101});
    try std.testing.expectError(error.TargetOutsideAssistant, single.validate(&.{102}));
    const split: scope.Scope = .{ .owner = .{ .tab = 4 }, .content = .{ .group = 7 }, .members = .{ .ids = .{ 101, 102 } ++ @as([14]u64, @splat(0)), .len = 2 } };
    _ = try split.validate(&.{ 102, 101 });
    try std.testing.expectError(error.TargetOutsideAssistant, split.validate(&.{103}));
    // 内容未捕获时失败关闭：判断为空会话，不是会话组。
    const unresolved: scope.Scope = .{ .owner = .{ .tab = 5 }, .members = .{} };
    try std.testing.expect(unresolved.contentOf() == .session and unresolved.contentOf().session == 0);
}
