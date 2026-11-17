//! 只在 `-Dtest-mode=true` 构建里编译：系统文件对话框的 e2e 注入器（见 dialog_port.zig）。
//!
//! 约定：环境变量 `ZEROWORK_E2E_DIALOG_DIR` 指向一个目录。
//! - `<dir>/queue`：每行一个应答，按对话框出现的顺序逐行消费。一行是绝对路径 = 选中这个路径；
//!   `cancel` = 用户取消。队列用完后的对话框一律按取消处理（绝不回退到真实对话框，批量回归不会卡住）。
//! - `<dir>/requests.jsonl`：每次对话框追加一行 `{"kind","title","answer"}`，供脚本断言。
//! 未设置该环境变量时不注入，照常弹真实对话框（手动验收脚本用）。
const std = @import("std");
const dialog_port = @import("dialog_port.zig");

comptime {
    // 正式构建一旦引用本文件就编译失败；check-test-hooks 再用正式二进制做字节级核对。
    if (!dialog_port.injection_supported) @compileError("test_dialog_injection.zig is test-mode only");
}

pub const env_name = "ZEROWORK_E2E_DIALOG_DIR";

extern "c" fn getenv(name: [*:0]const u8) ?[*:0]const u8;
extern "c" fn fopen(path: [*:0]const u8, mode: [*:0]const u8) ?*anyopaque;
extern "c" fn fread(ptr: [*]u8, size: usize, count: usize, stream: *anyopaque) usize;
extern "c" fn fwrite(ptr: [*]const u8, size: usize, count: usize, stream: *anyopaque) usize;
extern "c" fn fclose(stream: *anyopaque) c_int;
extern "c" fn mkdir(path: [*:0]const u8, mode: c_uint) c_int;
extern "c" fn getpid() c_int;
extern "c" fn unlink(path: [*:0]const u8) c_int;
extern "c" fn rmdir(path: [*:0]const u8) c_int;

var consumed: usize = 0;

pub fn install() void {
    if (getenv(env_name) == null) return;
    dialog_port.install(answer);
}

fn joinZ(buffer: []u8, dir: []const u8, name: []const u8) ?[:0]const u8 {
    return std.fmt.bufPrintSentinel(buffer, "{s}/{s}", .{ dir, name }, 0) catch null;
}

fn answer(kind: []const u8, title: []const u8, out: []u8) dialog_port.Injection {
    const dir = std.mem.span(getenv(env_name) orelse return .passthrough);
    return answerIn(dir, kind, title, out);
}

/// 与 `answer` 相同，但目录由调用方给出。测试直接调用它：不改进程环境变量
/// （setenv / unsetenv 会让 Zig std 缓存的 environ 视图失效，之后任何子进程 spawn 都可能 panic）。
fn answerIn(dir: []const u8, kind: []const u8, title: []const u8, out: []u8) dialog_port.Injection {
    var path_buffer: [4096]u8 = undefined;
    var queue: [64 * 1024]u8 = undefined;
    var len: usize = 0;
    if (joinZ(&path_buffer, dir, "queue")) |queue_path| if (fopen(queue_path.ptr, "rb")) |file| {
        len = fread(&queue, 1, queue.len, file);
        _ = fclose(file);
    };
    var lines = std.mem.splitScalar(u8, queue[0..len], '\n');
    var index: usize = 0;
    var line: ?[]const u8 = null;
    while (lines.next()) |raw| {
        const trimmed = std.mem.trim(u8, raw, " \r\t");
        if (trimmed.len == 0) continue;
        if (index == consumed) {
            line = trimmed;
            break;
        }
        index += 1;
    }
    var result: dialog_port.Injection = .cancel;
    if (line) |value| {
        consumed += 1;
        if (!std.mem.eql(u8, value, "cancel") and value.len <= out.len) {
            @memcpy(out[0..value.len], value);
            result = .{ .path = out[0..value.len] };
        }
    }
    record(dir, kind, title, switch (result) {
        .path => |p| p,
        else => "cancel",
    });
    return result;
}

fn record(dir: []const u8, kind: []const u8, title: []const u8, value: []const u8) void {
    var path_buffer: [4096]u8 = undefined;
    const log_path = joinZ(&path_buffer, dir, "requests.jsonl") orelse return;
    const file = fopen(log_path.ptr, "ab") orelse return;
    defer _ = fclose(file);
    var line: [8192]u8 = undefined;
    const text = std.fmt.bufPrint(&line, "{{\"kind\":{f},\"title\":{f},\"answer\":{f}}}\n", .{
        std.json.fmt(kind, .{}), std.json.fmt(title, .{}), std.json.fmt(value, .{}),
    }) catch return;
    _ = fwrite(text.ptr, 1, text.len, file);
}

test "dialog injection is only wired from test-mode startup" {
    // 守卫：注入器只能在 src/app/main.zig 的 test-mode 分支里安装，正式构建不编译它。
    const main_source = @embedFile("../app/main.zig");
    var lines = std.mem.splitScalar(u8, main_source, '\n');
    var wired: usize = 0;
    while (lines.next()) |line| {
        if (std.mem.indexOf(u8, line, "test_dialog_injection.zig") == null) continue;
        wired += 1;
        try std.testing.expect(std.mem.indexOf(u8, line, "if (comptime application_test_mode)") != null);
    }
    try std.testing.expectEqual(@as(usize, 1), wired);
}

test "dialog injection answers from the queue, records every request and never falls back to a real dialog" {
    var dir_buffer: [128]u8 = undefined;
    const dir = try std.fmt.bufPrintSentinel(&dir_buffer, "/private/tmp/zw-dialog-injection-test-{d}", .{getpid()}, 0);
    _ = mkdir(dir.ptr, 0o700);
    var path_buffer: [256]u8 = undefined;
    const queue_path = joinZ(&path_buffer, dir, "queue").?;
    var cleanup_buffer: [256]u8 = undefined;
    defer {
        _ = unlink(queue_path.ptr);
        if (joinZ(&cleanup_buffer, dir, "requests.jsonl")) |p| _ = unlink(p.ptr);
        _ = rmdir(dir.ptr);
    }
    const queue = fopen(queue_path.ptr, "wb").?;
    const lines = "/tmp/a.txt\ncancel\n";
    _ = fwrite(lines.ptr, 1, lines.len, queue);
    _ = fclose(queue);
    consumed = 0;
    var out: [64]u8 = undefined;
    try std.testing.expectEqualStrings("/tmp/a.txt", answerIn(dir, "open_file", "t", &out).path);
    try std.testing.expect(answerIn(dir, "open_file", "t", &out) == .cancel);
    try std.testing.expect(answerIn(dir, "pick_folder", "t", &out) == .cancel); // exhausted queue: cancel, not passthrough
    var log_buffer: [256]u8 = undefined;
    const log = fopen(joinZ(&log_buffer, dir, "requests.jsonl").?.ptr, "rb").?;
    var text: [1024]u8 = undefined;
    const len = fread(&text, 1, text.len, log);
    _ = fclose(log);
    try std.testing.expectEqual(@as(usize, 3), std.mem.count(u8, text[0..len], "\n"));
    try std.testing.expect(std.mem.indexOf(u8, text[0..len], "\"answer\":\"/tmp/a.txt\"") != null);
}
