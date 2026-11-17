//! check-test-hooks：用编译出的 zerowork 二进制核对“测试专用入口只存在于 test-mode 构建”。
//!
//! 用法：check-test-hooks <binary> <formal|test-mode>
//!
//! - formal：`forbidden` 里的每个字节串都不得出现在二进制里（字符串常量与符号名都算）。
//! - test-mode：`required_in_test_mode` 必须出现——正向对照，证明检查本身能看见这些入口，
//!   不是因为改名或剥符号才“看不到”。
//!
//! 只做只读的字节扫描，不执行被检查的二进制。
const std = @import("std");

pub const Hook = struct { needle: []const u8, what: []const u8 };

/// 正式构建里不得出现的测试入口痕迹。
pub const forbidden = [_]Hook{
    .{ .needle = "ZEROWORK_E2E_DIALOG_DIR", .what = "系统文件对话框注入器的环境变量（platform/test_dialog_injection.zig）" },
    .{ .needle = "test_dialog_injection", .what = "对话框注入器的符号 / 源文件名" },
    .{ .needle = "dialog_port.injector", .what = "dialog_port 的注入钩子变量" },
    .{ .needle = "requests.jsonl", .what = "对话框注入器的请求记录文件名" },
    .{ .needle = "ZEROWORK_BUILD_MODE=test-mode", .what = "e2e 启动守卫认的 test-mode 标记（platform/build_mode_marker.zig）" },
};

/// test-mode 构建里必须能看到的（正向对照）。
pub const required_in_test_mode = [_]Hook{
    .{ .needle = "ZEROWORK_E2E_DIALOG_DIR", .what = "系统文件对话框注入器的环境变量" },
    .{ .needle = "ZEROWORK_BUILD_MODE=test-mode", .what = "e2e 启动守卫认的 test-mode 标记（platform/build_mode_marker.zig）" },
};

pub const Mode = enum { formal, @"test-mode" };

pub const Finding = struct { hook: Hook, offset: ?usize };

/// formal：返回第一个出现的 forbidden 条目；test-mode：返回第一个缺失的 required 条目。null = 通过。
pub fn verify(mode: Mode, bytes: []const u8) ?Finding {
    switch (mode) {
        .formal => for (forbidden) |hook| {
            if (std.mem.indexOf(u8, bytes, hook.needle)) |offset| return .{ .hook = hook, .offset = offset };
        },
        .@"test-mode" => for (required_in_test_mode) |hook| {
            if (std.mem.indexOf(u8, bytes, hook.needle) == null) return .{ .hook = hook, .offset = null };
        },
    }
    return null;
}

pub fn main(init: std.process.Init) !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const args = try init.minimal.args.toSlice(arena);
    const stderr = std.Io.File.stderr();
    if (args.len != 3) {
        try stderr.writeStreamingAll(init.io, "用法：check-test-hooks <binary> <formal|test-mode>\n");
        std.process.exit(2);
    }
    const mode = std.meta.stringToEnum(Mode, args[2]) orelse {
        try stderr.writeStreamingAll(init.io, "check-test-hooks：模式只能是 formal 或 test-mode\n");
        std.process.exit(2);
    };
    const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, args[1], arena, .limited(2 * 1024 * 1024 * 1024));
    var aw: std.Io.Writer.Allocating = .init(arena);
    if (verify(mode, bytes)) |finding| {
        switch (mode) {
            .formal => try aw.writer.print("check-test-hooks: 失败——正式构建 {s} 里出现了测试入口：\"{s}\"（{s}），偏移 {d}\n", .{ args[1], finding.hook.needle, finding.hook.what, finding.offset.? }),
            .@"test-mode" => try aw.writer.print("check-test-hooks: 失败——test-mode 构建 {s} 里找不到 \"{s}\"（{s}）；检查失去对照，先确认入口是否改名\n", .{ args[1], finding.hook.needle, finding.hook.what }),
        }
        try stderr.writeStreamingAll(init.io, aw.written());
        std.process.exit(1);
    }
    try aw.writer.print("check-test-hooks: 通过（{s}，{d} 字节，{s}）\n", .{ @tagName(mode), bytes.len, switch (mode) {
        .formal => "测试入口痕迹 0 处",
        .@"test-mode" => "测试入口存在（对照成立）",
    } });
    try std.Io.File.stdout().writeStreamingAll(init.io, aw.written());
}

test "formal binaries must not contain any test hook trace" {
    try std.testing.expect(verify(.formal, "plain production bytes, sdk.runDialog only") == null);
    const leaked = verify(.formal, "....ZEROWORK_E2E_DIALOG_DIR\x00....").?;
    try std.testing.expectEqualStrings("ZEROWORK_E2E_DIALOG_DIR", leaked.hook.needle);
    try std.testing.expectEqual(@as(?usize, 4), leaked.offset);
    try std.testing.expect(verify(.formal, "_platform.dialog_port.injector") != null);
    try std.testing.expect(verify(.formal, "platform.test_dialog_injection.answer") != null);
    try std.testing.expect(verify(.formal, "x ZEROWORK_BUILD_MODE=test-mode y") != null);
}

test "test-mode binaries must still show the hooks (positive control)" {
    try std.testing.expect(verify(.@"test-mode", "x ZEROWORK_E2E_DIALOG_DIR y ZEROWORK_BUILD_MODE=test-mode") == null);
    try std.testing.expect(verify(.@"test-mode", "x ZEROWORK_E2E_DIALOG_DIR y") != null);
    try std.testing.expect(verify(.@"test-mode", "renamed or stripped") != null);
}
