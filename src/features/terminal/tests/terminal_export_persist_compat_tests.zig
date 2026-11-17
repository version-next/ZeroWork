//! 终端文本导出的"读旧写新"基准（persist-async，说明见 config/tests/persist_compat_tests.zig）。
//! 夹具由引入共享持久化模块之前的代码写出；再生成：设置 `ZW_PERSIST_COMPAT_OUT`。
const std = @import("std");
const terminal_export = @import("../host/terminal_export.zig");
const a = std.testing.allocator;
const io = std.testing.io;

const fixture = @embedFile("../test_fixtures/persist_compat/export.txt");
const text = "导出文本\n\t└─测试\n";

test "persist compat: terminal export written before the shared module is unchanged" {
    try std.testing.expectEqualStrings(text, fixture);
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try terminal_export.writeSnapshot(io, tmp.dir, "export.txt", text);
    const bytes = try tmp.dir.readFileAlloc(io, "export.txt", a, .limited(64 * 1024));
    defer a.free(bytes);
    try std.testing.expectEqualStrings(fixture, bytes);
    const stat = try tmp.dir.statFile(io, "export.txt", .{});
    try std.testing.expectEqual(@as(u32, 0o600), @backingInt(stat.permissions) & 0o777);
}

test "persist compat: regenerate terminal export fixture (ZW_PERSIST_COMPAT_OUT)" {
    const out = if (std.c.getenv("ZW_PERSIST_COMPAT_OUT")) |value| std.mem.span(value) else return error.SkipZigTest;
    var dir = try std.Io.Dir.cwd().createDirPathOpen(io, out, .{});
    defer dir.close(io);
    try terminal_export.writeSnapshot(io, dir, "export.txt", text);
}
