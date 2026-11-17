//! 系统文件对话框（打开文件 / 保存文件 / 选择目录）的唯一出口。
//!
//! 生产路径就是 `sdk.runDialog`。只有 `-Dtest-mode=true` 的构建会在启动时（src/app/main.zig）
//! 装上 `test_dialog_injection.zig` 的注入器，让 e2e 预先指定“下一次对话框返回什么”，
//! 不弹真实的 NSOpenPanel / NSSavePanel；正式构建里注入器的实现根本不会被编译进来
//! （见本文件末尾与 test_dialog_injection.zig 的守卫测试）。
const std = @import("std");
const runtime_mode = @import("runtime_mode.zig");

/// 注入能力只在自动化构建（单元测试、`-Dtest-mode=true`、预览 / 夹具）里存在。
/// 正式构建里它是 comptime false：`injector` 变量与 `install` 都不会进入二进制，
/// `run` 就是 `sdk.runDialog` 本身（`zig build check-test-hooks` 用正式二进制核对）。
pub const injection_supported = runtime_mode.automation;

pub const Injection = union(enum) {
    /// 不注入：走真实系统对话框。
    passthrough,
    /// 相当于用户点了“取消”。
    cancel,
    /// 相当于用户选中了这个路径（切片指向调用方传入的 buffer）。
    path: []const u8,
};

pub const Injector = *const fn (kind: []const u8, title: []const u8, buffer: []u8) Injection;

var injector: ?Injector = null;

/// 只由 test-mode 构建的启动代码调用；正式构建引用它就是编译错误。
pub fn install(f: Injector) void {
    if (comptime !injection_supported) @compileError("dialog injection exists only in automation (test-mode) builds");
    injector = f;
}

pub fn installed() bool {
    if (comptime !injection_supported) return false;
    return injector != null;
}

fn RequestOf(comptime Sdk: type) type {
    const T = switch (@typeInfo(Sdk)) {
        .pointer => |p| p.child,
        else => Sdk,
    };
    return @typeInfo(@TypeOf(T.runDialog)).@"fn".param_types[1].?;
}

/// 与 `sdk.runDialog(request, buffer)` 同签名同语义。
pub fn run(sdk: anytype, request: RequestOf(@TypeOf(sdk)), buffer: []u8) !?[]const u8 {
    if (comptime injection_supported) if (injector) |f| switch (f(@tagName(request.kind), request.title, buffer)) {
        .passthrough => {},
        .cancel => return null,
        .path => |p| return p,
    };
    return sdk.runDialog(request, buffer);
}

const FakeRequest = struct { kind: enum { open_file, save_file, pick_folder }, title: []const u8 = "", default_path: []const u8 = "" };

test "dialog port passes through to the system dialog when nothing is installed" {
    const Fake = struct {
        calls: usize = 0,
        fn runDialog(self: *@This(), request: FakeRequest, buffer: []u8) !?[]const u8 {
            _ = request;
            self.calls += 1;
            @memcpy(buffer[0..4], "/sys");
            return buffer[0..4];
        }
    };
    var fake: Fake = .{};
    var buffer: [16]u8 = undefined;
    const saved = injector;
    defer injector = saved;
    injector = null;
    const got = try run(&fake, .{ .kind = .open_file, .title = "t" }, &buffer);
    try std.testing.expectEqualStrings("/sys", got.?);
    try std.testing.expectEqual(@as(usize, 1), fake.calls);
}

test "dialog port: an installed injector answers without showing the system dialog" {
    const Fake = struct {
        calls: usize = 0,
        fn runDialog(self: *@This(), request: FakeRequest, buffer: []u8) !?[]const u8 {
            _ = request;
            _ = buffer;
            self.calls += 1;
            return null;
        }
    };
    const Inject = struct {
        fn f(kind: []const u8, title: []const u8, buffer: []u8) Injection {
            _ = title;
            if (std.mem.eql(u8, kind, "pick_folder")) return .cancel;
            @memcpy(buffer[0..5], "/test");
            return .{ .path = buffer[0..5] };
        }
    };
    var fake: Fake = .{};
    var buffer: [16]u8 = undefined;
    const saved = injector;
    defer injector = saved;
    install(Inject.f);
    try std.testing.expectEqualStrings("/test", (try run(&fake, .{ .kind = .open_file, .title = "" }, &buffer)).?);
    try std.testing.expectEqual(@as(?[]const u8, null), try run(&fake, .{ .kind = .pick_folder, .title = "" }, &buffer));
    try std.testing.expectEqual(@as(usize, 0), fake.calls);
}
