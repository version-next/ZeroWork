//! Guard: an isolated (test) build started on a fake private root resolves
//! every key path under that root, and refuses rather than falls back to the
//! real account when the root is missing or is the account home.
const std = @import("std");
const user_dirs = @import("../user_dirs.zig");
const user_dirs_native = @import("../user_dirs_native.zig");
const Paths = @import("../../config/paths.zig").Paths;
const config = @import("../../config/config.zig");
const transfer_defaults = @import("../../config/transfer_defaults.zig");
const local_native = @import("../../local/native.zig");

const C = struct {
    extern "c" fn mkdtemp([*:0]u8) ?[*:0]u8;
    extern "c" fn setenv([*:0]const u8, [*:0]const u8, c_int) c_int;
    extern "c" fn unsetenv([*:0]const u8) c_int;
};

const variables = [_][:0]const u8{ "HOME", "CFFIXED_USER_HOME", "ZEROWORK_DATA_DIR" };

/// Saves and restores the variables this guard changes, so later tests keep
/// the runner's private environment.
const Environment = struct {
    saved: [variables.len]?[:0]u8 = @splat(null),

    fn capture(a: std.mem.Allocator) !Environment {
        var result: Environment = .{};
        errdefer result.restore(a);
        for (variables, 0..) |name, i| if (std.c.getenv(name)) |value| {
            result.saved[i] = try a.dupeSentinel(u8, std.mem.span(value), 0);
        };
        return result;
    }
    fn restore(self: *Environment, a: std.mem.Allocator) void {
        for (variables, 0..) |name, i| {
            if (self.saved[i]) |value| {
                if (C.setenv(name, value, 1) != 0) @panic("cannot restore environment");
                a.free(value);
            } else if (C.unsetenv(name) != 0) @panic("cannot restore environment");
        }
        self.* = .{};
    }
};

fn set(name: [:0]const u8, value: ?[]const u8) !void {
    if (value) |text| {
        var buffer: [std.c.PATH_MAX]u8 = undefined;
        const z = try std.fmt.bufPrintSentinel(&buffer, "{s}", .{text}, 0);
        if (C.setenv(name, z, 1) != 0) return error.EnvironmentFailed;
    } else if (C.unsetenv(name) != 0) return error.EnvironmentFailed;
}

fn expectUnder(root: []const u8, path: []const u8) !void {
    const inside = std.mem.startsWith(u8, path, root) and path.len > root.len and path[root.len] == '/';
    if (!inside) {
        std.debug.print("path escapes the private root:\n  root: {s}\n  path: {s}\n", .{ root, path });
        return error.PathEscapesPrivateRoot;
    }
}

/// A fresh private root (mkdtemp, 0700) outside the real account home: under
/// the runner's TMPDIR, else /private/tmp. The repository's .zig-cache lives in
/// the account home, so std.testing.tmpDir cannot serve as a fake HOME.
const PrivateRoot = struct {
    path: [:0]u8,

    fn create(a: std.mem.Allocator) !PrivateRoot {
        const base = if (std.c.getenv("TMPDIR")) |value| std.mem.trimEnd(u8, std.mem.span(value), "/") else "/private/tmp";
        const template = try std.fmt.allocPrintSentinel(a, "{s}/zw-home-guard-XXXXXX", .{base}, 0);
        defer a.free(template);
        if (C.mkdtemp(template.ptr) == null) return error.PrivateRootUnavailable;
        var buffer: [std.c.PATH_MAX]u8 = undefined;
        const resolved = std.c.realpath(template.ptr, &buffer) orelse return error.PrivateRootUnavailable;
        return .{ .path = try a.dupeSentinel(u8, std.mem.span(resolved), 0) };
    }
    fn destroy(self: *PrivateRoot, a: std.mem.Allocator) void {
        std.Io.Dir.cwd().deleteTree(std.testing.io, self.path) catch {};
        a.free(self.path);
    }
};

test "home isolation guard: data, logs, preferences, downloads, local terminal and updater stay under the fake private root" {
    comptime std.debug.assert(user_dirs.isolated and !user_dirs.writes_user_preferences);
    const a = std.testing.allocator;
    var private = try PrivateRoot.create(a);
    defer private.destroy(a);
    const root = private.path;
    var environment = try Environment.capture(a);
    defer environment.restore(a);
    try set("HOME", root);
    try set("CFFIXED_USER_HOME", root);
    try set("ZEROWORK_DATA_DIR", null);

    const home = try user_dirs.home(a);
    defer a.free(home);
    try std.testing.expectEqualStrings(root, home);
    try user_dirs.requireIsolatedStartup();

    // Data directory, settings, hosts, OpenSSH trust, cache and the default
    // applog directory (applog uses Paths.diagnostic_directory).
    var paths = try Paths.forApplication(a);
    defer paths.deinit();
    try std.testing.expect(!paths.is_override);
    inline for (.{ "directory", "config", "hosts", "known_hosts", "cache_directory", "diagnostic_directory" }) |field| try expectUnder(root, @field(paths, field));
    try expectUnder(root, paths.legacy_directory.?);
    for ([_]*const fn (std.mem.Allocator) anyerror![]u8{ user_dirs.appSupport, user_dirs.logs, user_dirs.caches, user_dirs.preferences, user_dirs.downloads }) |resolve| {
        const path = try resolve(a);
        defer a.free(path);
        try expectUnder(root, path);
    }

    // The default transfer download directory ("~/Downloads").
    const configured = (config.Transfer{}).download_dir;
    try std.testing.expectEqualStrings("~/Downloads", configured);
    const download = try transfer_defaults.downloadDirectory(a, configured, home);
    defer a.free(download);
    try expectUnder(root, download);

    // A local terminal started without a directory opens in the private home.
    const cwd = (try local_native.cwdZ(a, null)).?;
    defer a.free(cwd);
    try std.testing.expectEqualStrings(root, cwd);

    // The Objective-C updater's area (check.json, active.json, downloads).
    var buffer: [std.c.PATH_MAX]u8 = undefined;
    try std.testing.expectEqual(@as(c_int, 1), user_dirs_native.zw_user_dirs_isolated_home(&buffer, buffer.len));
    try std.testing.expectEqualStrings(root, std.mem.sliceTo(&buffer, 0));

    // An explicit data directory still wins for application data.
    const data = try std.fs.path.join(a, &.{ root, "data" });
    defer a.free(data);
    try set("ZEROWORK_DATA_DIR", data);
    var explicit = try Paths.forApplication(a);
    defer explicit.deinit();
    try std.testing.expect(explicit.is_override);
    inline for (.{ "directory", "config", "hosts", "known_hosts", "cache_directory", "diagnostic_directory" }) |field| try expectUnder(root, @field(explicit, field));
}

test "home isolation guard: missing, relative or account HOME is refused and never replaced by the account" {
    const a = std.testing.allocator;
    var private = try PrivateRoot.create(a);
    defer private.destroy(a);
    const root = private.path;
    const account = try user_dirs.accountHome(a);
    defer a.free(account);
    var environment = try Environment.capture(a);
    defer environment.restore(a);
    try set("CFFIXED_USER_HOME", null);
    try set("ZEROWORK_DATA_DIR", null);

    const Case = struct { home: ?[]const u8, fixed: ?[]const u8 = null, expected: anyerror };
    const other = try std.fs.path.join(a, &.{ root, "other" });
    defer a.free(other);
    try std.Io.Dir.createDirAbsolute(std.testing.io, other, .default_dir);
    const missing = try std.fs.path.join(a, &.{ root, "missing" });
    defer a.free(missing);
    const parent = std.fs.path.dirname(account).?;
    for ([_]Case{
        .{ .home = null, .expected = error.IsolatedHomeRequired },
        .{ .home = "", .expected = error.IsolatedHomeInvalid },
        .{ .home = "relative/home", .expected = error.IsolatedHomeInvalid },
        .{ .home = missing, .expected = error.IsolatedHomeInvalid },
        .{ .home = account, .expected = error.IsolatedHomeIsAccountHome },
        .{ .home = parent, .expected = error.IsolatedHomeIsAccountHome },
        .{ .home = "/", .expected = error.IsolatedHomeIsAccountHome },
        .{ .home = root, .fixed = account, .expected = error.IsolatedHomeMismatch },
        .{ .home = root, .fixed = other, .expected = error.IsolatedHomeMismatch },
    }) |case| {
        try set("HOME", case.home);
        try set("CFFIXED_USER_HOME", case.fixed);
        try std.testing.expectError(case.expected, user_dirs.home(a));
        try std.testing.expectError(case.expected, Paths.forApplication(a));
        try std.testing.expectError(case.expected, local_native.cwdZ(a, null));
        try std.testing.expectError(case.expected, user_dirs.downloads(a));
        var buffer: [std.c.PATH_MAX]u8 = undefined;
        try std.testing.expectEqual(@as(c_int, -1), user_dirs_native.zw_user_dirs_isolated_home(&buffer, buffer.len));
        try std.testing.expectError(case.expected, user_dirs.isolatedHome(a, case.home, case.fixed));
    }
    // A HOME inside the real account home (here: the repository's .zig-cache,
    // where std.testing.tmpDir lives) is refused too, as is spawning any local
    // child while HOME is the account, even with an explicit directory.
    var inside = std.testing.tmpDir(.{});
    defer inside.cleanup();
    const nested = try inside.dir.realPathFileAlloc(std.testing.io, ".", a);
    defer a.free(nested);
    if (std.mem.startsWith(u8, nested, account)) {
        try set("HOME", nested);
        try set("CFFIXED_USER_HOME", null);
        try std.testing.expectError(error.IsolatedHomeUnderAccountHome, user_dirs.home(a));
        try std.testing.expectError(error.IsolatedHomeUnderAccountHome, Paths.forApplication(a));
    }
    try set("HOME", account);
    try std.testing.expectError(error.IsolatedHomeIsAccountHome, local_native.cwdZ(a, root));
    // The child-path guard is lexical. Keep this case when the build and
    // std.testing.tmpDir both live outside the account home.
    const account_child = try std.fs.path.join(a, &.{ account, ".zerowork-test-home" });
    defer a.free(account_child);
    try std.testing.expectError(error.IsolatedHomeUnderAccountHome, user_dirs.ensureOutsideAccount(account_child));
    try user_dirs.ensureOutsideAccount(root);

    // An explicit data directory may not sit in the account's Library, user
    // folders, ~/.ssh or ~/.zerowork (lexical check, no IO on the real home).
    try set("HOME", root);
    for ([_][]const u8{ "", "/Library/Application Support/com.zerowork.app", "/Library/Logs/com.zerowork.app", "/Downloads/x", "/.ssh/zw", "/.zerowork" }) |suffix| {
        const data = try std.fmt.allocPrint(a, "{s}{s}", .{ account, suffix });
        defer a.free(data);
        try set("ZEROWORK_DATA_DIR", data);
        try std.testing.expectError(error.IsolatedDataInAccountHome, Paths.forApplication(a));
    }
    try set("ZEROWORK_DATA_DIR", null);

    // A HOME that is a symlink to the private root is accepted as that root.
    const link = try std.fmt.allocPrint(a, "{s}-link", .{root});
    defer a.free(link);
    try std.Io.Dir.symLinkAbsolute(std.testing.io, root, link, .{});
    defer std.Io.Dir.deleteFileAbsolute(std.testing.io, link) catch {};
    try set("HOME", link);
    try set("CFFIXED_USER_HOME", root);
    const resolved = try user_dirs.home(a);
    defer a.free(resolved);
    try std.testing.expectEqualStrings(root, resolved);
}

test "home isolation guard: the formal resolver has no override entry" {
    // Resolver(false) is the code a formal build compiles. With HOME and
    // CFFIXED_USER_HOME pointing at a private root it still returns the passwd
    // home, i.e. exactly the pre-isolation platform/account.zig result.
    const a = std.testing.allocator;
    var private = try PrivateRoot.create(a);
    defer private.destroy(a);
    const root = private.path;
    var environment = try Environment.capture(a);
    defer environment.restore(a);
    try set("HOME", root);
    try set("CFFIXED_USER_HOME", root);
    const formal = try user_dirs.Resolver(false).home(a);
    defer a.free(formal);
    const account = try user_dirs.accountHome(a);
    defer a.free(account);
    try std.testing.expectEqualStrings(account, formal);
    try std.testing.expect(!std.mem.eql(u8, formal, root));
    const isolated = try user_dirs.Resolver(true).home(a);
    defer a.free(isolated);
    try std.testing.expectEqualStrings(root, isolated);
}
