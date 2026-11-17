//! “立即重启”的再启动一步（设置 › 协议插件，PLUGIN_ARCH_PLAN 6.2.1 Q5 的“生效时机”）。
//!
//! 退出本身走正常流程（`ProcessWindows.requestRelaunch` → 与 ⌘Q 相同的关闭确认），这里只负责“退出之后再启动同一个
//! 应用”。核实结论（2026-11-13）：自动更新的再启动在独立的安装辅助程序里（`update/native_installer.m` 的 `LaunchNew`），
//! 它是 `static`、读更新事务的全局记录、和换包 / 回滚状态机绑在一起，不能拿来做“不更新、只重启”；ZeroWork 里也没有现成的
//! relaunch。所以这里新起一个极小的等待进程：等当前进程退出（数据目录锁随之释放）后，用 `open -n` 重新打开同一个
//! `.app`（不在 `.app` 里运行时直接执行同一个可执行文件）。等待进程不碰数据、不传任何参数给新进程。
//!
//! 位置在 platform：只是起一个系统进程，不依赖应用层（`app/main.zig` 在主循环结束后调用）。
//!
//! 测试构建不启动外部进程：再启动会逃出 e2e 的隔离环境（`open` 经 LaunchServices，不继承私有 HOME 与断网沙箱），
//! 所以只打印一行 `ZW_RELAUNCH`，由 e2e 用同一个数据目录自己重新启动。
const std = @import("std");
const applog = @import("applog.zig");

/// 正常退出完成之后调用（主循环已结束）。失败只记日志：应用照常退出，用户可以手动再打开。
/// `test_mode`：测试构建只打印 `ZW_RELAUNCH`，不启动外部进程。
pub fn schedule(io: std.Io, allocator: std.mem.Allocator, test_mode: bool) void {
    if (test_mode) {
        std.debug.print("ZW_RELAUNCH {{\"scheduled\":true,\"spawned\":false}}\n", .{});
        return;
    }
    const executable = std.process.executablePathAlloc(io, allocator) catch |err| {
        applog.warn(.app, "relaunch: executable path: {s}", .{@errorName(err)});
        return;
    };
    defer allocator.free(executable);
    var pid_text: [32]u8 = undefined;
    const pid = std.fmt.bufPrint(&pid_text, "{d}", .{std.c.getpid()}) catch return;
    const target = target_of(executable);
    const argv = [_][]const u8{ "/bin/sh", "-c", waiter_script, "zerowork-relaunch", pid, target.path, if (target.bundle) "bundle" else "binary" };
    _ = std.process.spawn(io, .{ .argv = &argv, .stdin = .ignore, .stdout = .ignore, .stderr = .ignore, .pgid = 0 }) catch |err| {
        applog.warn(.app, "relaunch: spawn waiter: {s}", .{@errorName(err)});
        return;
    };
    applog.info(.app, "relaunch scheduled for {s}", .{target.path});
}

/// `$1` = 当前 pid，`$2` = 目标路径，`$3` = bundle / binary。等 `$1` 退出（最多约 2 分钟，退出确认可能还在等用户）后再启动。
const waiter_script =
    \\i=0; while kill -0 "$1" 2>/dev/null; do i=$((i+1)); [ "$i" -gt 1200 ] && exit 0; sleep 0.1; done
    \\if [ "$3" = bundle ]; then exec /usr/bin/open -n "$2"; else exec "$2"; fi
;

const Target = struct { path: []const u8, bundle: bool };
/// `/Applications/ZeroWork.app/Contents/MacOS/ZeroWork` → `/Applications/ZeroWork.app`；不在 `.app` 里时是可执行文件本身。
fn target_of(executable: []const u8) Target {
    const marker = ".app/Contents/MacOS/";
    if (std.mem.lastIndexOf(u8, executable, marker)) |index| {
        const rest = executable[index + marker.len ..];
        if (rest.len != 0 and std.mem.indexOfScalar(u8, rest, '/') == null) return .{ .path = executable[0 .. index + ".app".len], .bundle = true };
    }
    return .{ .path = executable, .bundle = false };
}

test "relaunch targets the enclosing .app bundle, or the executable itself" {
    const bundled = target_of("/Applications/ZeroWork.app/Contents/MacOS/ZeroWork");
    try std.testing.expect(bundled.bundle);
    try std.testing.expectEqualStrings("/Applications/ZeroWork.app", bundled.path);
    const bare = target_of("/private/tmp/zw-formal/bin/zerowork");
    try std.testing.expect(!bare.bundle);
    try std.testing.expectEqualStrings("/private/tmp/zw-formal/bin/zerowork", bare.path);
    try std.testing.expect(!target_of("/x/Odd.app/Contents/MacOS/sub/tool").bundle);
}
