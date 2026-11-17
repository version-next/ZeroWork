//! 会话组布局文件的"读旧写新"基准（persist-async，说明见 config/tests/persist_compat_tests.zig）。
//! 夹具由引入共享持久化模块之前的代码写出；再生成：设置 `ZW_PERSIST_COMPAT_OUT`。
const std = @import("std");
const group_layout = @import("../model/group_layout.zig");
const a = std.testing.allocator;
const io = std.testing.io;

const fixture = @embedFile("../test_fixtures/persist_compat/session-group-layout.json");
const nodes = [_]group_layout.Node{ .{ .split = .{ .axis = .side_by_side, .ratio = 0.5, .first = 1, .second = 2 } }, .{ .leaf = 1 }, .{ .leaf = 2 } };
const sample: group_layout.Snapshot = .{ .layout = .side_by_side, .root = 0, .nodes = &nodes };

fn produce(directory: []const u8) !void {
    const path = try std.fs.path.join(a, &.{ directory, "session-group-layout.json" });
    defer a.free(path);
    try group_layout.save(a, io, path, sample);
}

test "persist compat: group layout written before the shared module reads back and rewrites byte-identically" {
    const parsed = try std.json.parseFromSlice(group_layout.Snapshot, a, fixture, .{});
    defer parsed.deinit();
    try std.testing.expect(group_layout.valid(parsed.value));
    try std.testing.expectEqualDeep(sample.nodes, parsed.value.nodes);
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(io, ".", a);
    defer a.free(root);
    try produce(root);
    const bytes = try tmp.dir.readFileAlloc(io, "session-group-layout.json", a, .limited(64 * 1024));
    defer a.free(bytes);
    try std.testing.expectEqualStrings(fixture, bytes);
    const stat = try tmp.dir.statFile(io, "session-group-layout.json", .{});
    try std.testing.expectEqual(@as(u32, 0o600), @backingInt(stat.permissions) & 0o777);
}

test "persist compat: regenerate group layout fixture (ZW_PERSIST_COMPAT_OUT)" {
    const out = if (std.c.getenv("ZW_PERSIST_COMPAT_OUT")) |value| std.mem.span(value) else return error.SkipZigTest;
    try std.Io.Dir.cwd().createDirPath(io, out);
    try produce(out);
}
