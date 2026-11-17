//! The single place ZeroWork resolves the user's home and the folders it uses
//! under it (Application Support, Caches, Logs, Preferences, Downloads, the
//! updater area, OpenSSH trust and the legacy data directory).
//!
//! Callers never read getpwuid, HOME, NSHomeDirectory or the standard folder
//! APIs themselves; they ask this file. The folder helpers are pure joins on
//! a given home, so every location is the same string the previous per-site
//! code produced.
//!
//! Formal builds: `home()` is the account's passwd record, exactly as before.
//! Nothing in the process environment can redirect it; the isolated branch
//! below is not compiled into a formal binary.
//!
//! Isolated builds (unit tests, -Dtest-mode=true, previews, fixtures and
//! acceptance runners; see runtime_mode.isolated_home): `home()` is the
//! process HOME, which must name an existing directory that is neither the
//! real account home nor one of its ancestors. If CFFIXED_USER_HOME is set it
//! must resolve to the same directory, so Foundation agrees with us. Anything
//! else is an error; there is no fallback to the account.
const std = @import("std");
const runtime_mode = @import("runtime_mode.zig");

pub const bundle_id = "com.zerowork.app";
pub const updater_bundle_id = "com.zerowork.updater";

/// Comptime: this binary derives paths from a private test root.
pub const isolated = runtime_mode.isolated_home;
/// Formal builds publish the Dock icon style to the app's preference domain
/// (~/Library/Preferences/<bundle id>.plist). Isolated builds never write user
/// preferences: cfprefsd does not honour HOME, so no private redirect exists.
pub const writes_user_preferences = !isolated;

pub const IsolationError = error{
    /// HOME is unset.
    IsolatedHomeRequired,
    /// HOME is relative, too long, missing, or not a directory.
    IsolatedHomeInvalid,
    /// HOME resolves to the real account home or one of its ancestors.
    IsolatedHomeIsAccountHome,
    /// HOME, or a path derived from it, lies inside the real account home.
    IsolatedHomeUnderAccountHome,
    /// ZEROWORK_DATA_DIR lies in the real account's Library, user folders,
    /// OpenSSH or legacy ZeroWork data.
    IsolatedDataInAccountHome,
    /// CFFIXED_USER_HOME names a different directory than HOME.
    IsolatedHomeMismatch,
    /// The account home needed for the comparison is unavailable.
    IsolatedHomeUnverifiable,
};

/// The home every application path is derived from. Owned by the caller.
pub fn home(allocator: std.mem.Allocator) ![]u8 {
    const result = try Resolver(isolated).home(allocator);
    errdefer allocator.free(result);
    try ensureOutsideAccount(result);
    return result;
}

/// Both policies, so tests can exercise the formal one from a test binary.
pub fn Resolver(comptime isolated_build: bool) type {
    return struct {
        pub fn home(allocator: std.mem.Allocator) ![]u8 {
            if (comptime !isolated_build) return accountHome(allocator);
            return isolatedHome(allocator, environment("HOME"), environment("CFFIXED_USER_HOME"));
        }
    };
}

/// Refuse to start an isolated build without a valid private HOME, before
/// any path is opened. No-op in formal builds.
pub fn requireIsolatedStartup() !void {
    if (comptime !isolated) return;
    const value = home(std.heap.c_allocator) catch |err| {
        std.debug.print("ZeroWork test build refuses to start ({s}): set HOME (and CFFIXED_USER_HOME, if used) to a private directory that is not the account home.\n", .{@errorName(err)});
        return err;
    };
    std.heap.c_allocator.free(value);
}

/// The live account's home from the passwd record, ignoring application
/// overrides and mutable environment strings. Formal builds derive every path
/// from it; isolated builds only use it to refuse the real account.
pub fn accountHome(allocator: std.mem.Allocator) ![]u8 {
    var record: std.c.passwd = undefined;
    var result: ?*std.c.passwd = null;
    var buffer: [16 * 1024]u8 = undefined;
    if (std.c.getpwuid_r(std.c.getuid(), &record, &buffer, buffer.len, &result) != 0 or result == null) return error.HomeUnavailable;
    const value = std.mem.span(record.dir orelse return error.HomeUnavailable);
    if (value.len == 0 or value[0] != '/') return error.HomeUnavailable;
    return allocator.dupe(u8, value);
}

/// Validate a candidate private home. Pure apart from realpath and the passwd
/// lookup; the environment values are passed in. Returns the canonical path.
pub fn isolatedHome(allocator: std.mem.Allocator, home_value: ?[]const u8, fixed_value: ?[]const u8) ![]u8 {
    const raw = home_value orelse return error.IsolatedHomeRequired;
    var buffer: [std.c.PATH_MAX]u8 = undefined;
    const canonical = canonicalDirectory(raw, &buffer) orelse return error.IsolatedHomeInvalid;
    const account = accountHome(allocator) catch return error.IsolatedHomeUnverifiable;
    defer allocator.free(account);
    var account_buffer: [std.c.PATH_MAX]u8 = undefined;
    const account_canonical = canonicalDirectory(account, &account_buffer) orelse account;
    if (isSelfOrAncestor(canonical, account) or isSelfOrAncestor(canonical, account_canonical)) return error.IsolatedHomeIsAccountHome;
    if (isSelfOrAncestor(account, canonical) or isSelfOrAncestor(account_canonical, canonical)) return error.IsolatedHomeUnderAccountHome;
    if (fixed_value) |fixed| {
        var fixed_buffer: [std.c.PATH_MAX]u8 = undefined;
        const resolved = canonicalDirectory(fixed, &fixed_buffer) orelse return error.IsolatedHomeMismatch;
        if (!std.mem.eql(u8, resolved, canonical)) return error.IsolatedHomeMismatch;
    }
    return allocator.dupe(u8, canonical);
}

/// Isolated builds: fail if `path` lies inside the real account home. Every
/// path this file derives from `home()` passes through it, so a test build can
/// never hand out a location under the real `~`. No-op in formal builds.
pub fn ensureOutsideAccount(path: []const u8) !void {
    if (comptime !isolated) return;
    var buffer: [16 * 1024]u8 = undefined;
    var fixed = std.heap.FixedBufferAllocator.init(&buffer);
    const account = accountHome(fixed.allocator()) catch return error.IsolatedHomeUnverifiable;
    var account_buffer: [std.c.PATH_MAX]u8 = undefined;
    const account_canonical = canonicalDirectory(account, &account_buffer) orelse account;
    if (isSelfOrAncestor(account, path) or isSelfOrAncestor(account_canonical, path)) return error.IsolatedHomeUnderAccountHome;
}

/// Isolated builds: an explicit ZEROWORK_DATA_DIR may be any instance
/// directory (unit fixtures use the repository's .zig-cache), but never the
/// real account's Library, user folders, OpenSSH directory or legacy ZeroWork
/// data. Lexical check, before any IO. No-op in formal builds.
pub fn checkDataOverride(path: []const u8) !void {
    if (comptime !isolated) return;
    var buffer: [16 * 1024]u8 = undefined;
    var fixed = std.heap.FixedBufferAllocator.init(&buffer);
    const account = accountHome(fixed.allocator()) catch return error.IsolatedHomeUnverifiable;
    var account_buffer: [std.c.PATH_MAX]u8 = undefined;
    const account_canonical = canonicalDirectory(account, &account_buffer) orelse account;
    for ([_][]const u8{ account, account_canonical }) |base| {
        if (isSelfOrAncestor(path, base)) return error.IsolatedDataInAccountHome;
        for ([_][]const u8{ "Library", "Downloads", "Desktop", "Documents", ".ssh", ".zerowork" }) |name| {
            var joined: [std.c.PATH_MAX]u8 = undefined;
            const protected = std.fmt.bufPrint(&joined, "{s}/{s}", .{ std.mem.trimEnd(u8, base, "/"), name }) catch return error.IsolatedDataInAccountHome;
            if (isSelfOrAncestor(protected, path)) return error.IsolatedDataInAccountHome;
        }
    }
}

fn environment(name: [*:0]const u8) ?[]const u8 {
    return if (std.c.getenv(name)) |value| std.mem.span(value) else null;
}

/// realpath("<path>/.") resolves links and fails with ENOTDIR unless the
/// final component is a directory.
fn canonicalDirectory(path: []const u8, out: *[std.c.PATH_MAX]u8) ?[]const u8 {
    if (path.len == 0 or path[0] != '/' or std.mem.indexOfScalar(u8, path, 0) != null) return null;
    var input: [std.c.PATH_MAX + 3]u8 = undefined;
    if (path.len + 3 > input.len) return null;
    @memcpy(input[0..path.len], path);
    @memcpy(input[path.len..][0..3], "/.\x00");
    const resolved = std.c.realpath(@ptrCast(&input), out) orelse return null;
    return std.mem.span(resolved);
}

fn isSelfOrAncestor(candidate: []const u8, path: []const u8) bool {
    if (std.mem.eql(u8, candidate, "/")) return true;
    if (!std.mem.startsWith(u8, path, candidate)) return false;
    return path.len == candidate.len or path[candidate.len] == '/';
}

pub fn appSupportIn(allocator: std.mem.Allocator, base: []const u8) ![]u8 {
    return std.fs.path.join(allocator, &.{ base, "Library", "Application Support", bundle_id });
}
pub fn cachesIn(allocator: std.mem.Allocator, base: []const u8) ![]u8 {
    return std.fs.path.join(allocator, &.{ base, "Library", "Caches", bundle_id });
}
pub fn logsIn(allocator: std.mem.Allocator, base: []const u8) ![]u8 {
    return std.fs.path.join(allocator, &.{ base, "Library", "Logs", bundle_id });
}
pub fn preferencesIn(allocator: std.mem.Allocator, base: []const u8) ![]u8 {
    return std.fs.path.join(allocator, &.{ base, "Library", "Preferences" });
}
pub fn downloadsIn(allocator: std.mem.Allocator, base: []const u8) ![]u8 {
    return std.fs.path.join(allocator, &.{ base, "Downloads" });
}
pub fn updaterSupportIn(allocator: std.mem.Allocator, base: []const u8) ![]u8 {
    return std.fs.path.join(allocator, &.{ base, "Library", "Application Support", updater_bundle_id });
}
pub fn knownHostsIn(allocator: std.mem.Allocator, base: []const u8) ![]u8 {
    return std.fs.path.join(allocator, &.{ base, ".ssh", "known_hosts" });
}
pub fn legacyDataIn(allocator: std.mem.Allocator, base: []const u8) ![]u8 {
    return std.fs.path.join(allocator, &.{ base, ".zerowork" });
}

fn under(comptime join: fn (std.mem.Allocator, []const u8) anyerror![]u8, allocator: std.mem.Allocator) ![]u8 {
    const base = try home(allocator);
    defer allocator.free(base);
    const result = try join(allocator, base);
    errdefer allocator.free(result);
    try ensureOutsideAccount(result);
    return result;
}
pub fn appSupport(allocator: std.mem.Allocator) ![]u8 {
    return under(appSupportIn, allocator);
}
pub fn caches(allocator: std.mem.Allocator) ![]u8 {
    return under(cachesIn, allocator);
}
pub fn logs(allocator: std.mem.Allocator) ![]u8 {
    return under(logsIn, allocator);
}
pub fn preferences(allocator: std.mem.Allocator) ![]u8 {
    return under(preferencesIn, allocator);
}
pub fn downloads(allocator: std.mem.Allocator) ![]u8 {
    return under(downloadsIn, allocator);
}

test "user folder helpers keep the historical layout under a given home" {
    const a = std.testing.allocator;
    const cases = .{
        .{ appSupportIn, "/h/Library/Application Support/com.zerowork.app" },
        .{ cachesIn, "/h/Library/Caches/com.zerowork.app" },
        .{ logsIn, "/h/Library/Logs/com.zerowork.app" },
        .{ preferencesIn, "/h/Library/Preferences" },
        .{ downloadsIn, "/h/Downloads" },
        .{ updaterSupportIn, "/h/Library/Application Support/com.zerowork.updater" },
        .{ knownHostsIn, "/h/.ssh/known_hosts" },
        .{ legacyDataIn, "/h/.zerowork" },
    };
    inline for (cases) |case| {
        const value = try case[0](a, "/h");
        defer a.free(value);
        try std.testing.expectEqualStrings(case[1], value);
    }
}
