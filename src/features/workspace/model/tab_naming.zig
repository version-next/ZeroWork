//! 页签显示名（design-r3 稿 3，Pencil `Oxgby`）：纯函数，不碰视图。
//!
//! 取值优先级：
//! 1. 用户自定义名称（右键“重命名…”或 F2）原样使用。
//! 2. 远端会话：主机显示名（`staging-api`）。
//! 3. 本地终端：当前工作目录的末级名（`zerowork`）；前台有程序时写“程序 · 目录”（`vim · zerowork`）；
//!    在家目录时写“本地终端”（有程序时“vim · ~”）；拿不到目录时也写“本地终端”。界面上不再出现“Local Terminal”。
//!    状态后缀（启动失败 / 已退出）接在后面。
//! 4. 其它（插件页签、历史记录、已归档）：调用方给的标题。
//!
//! 仍重名时在末尾加最短的区分片段：第一个保留原名，后面的本地终端优先加“· 上一级目录名”（在同名组里唯一时），
//! 否则按出现顺序加“· 2”“· 3”。同一主机开多个也是“· 2”“· 3”。
//!
//! 事实来源（不编造）：本地目录来自 shell 进程的 cwd（`proc_pidinfo`，`local/darwin_process.c` 的 `zw_local_cwd`），
//! 前台程序来自 PTY 前台进程组的进程名（`zw_local_foreground`）；两者由宿主经 workspace 的 session bridge 提供。
//! 远端页签不取 cwd / 前台程序（命名规则只用主机名）。
const std = @import("std");

pub const home_label = "本地终端";

pub const Kind = enum { local, remote, other };

pub const Source = struct {
    kind: Kind,
    /// 用户自定义名称；非空时优先。
    custom: ?[]const u8 = null,
    /// 远端：主机显示名；其它：调用方的标题。
    label: []const u8 = "",
    /// 本地：shell 的当前目录（绝对路径）；null 表示拿不到。
    cwd: ?[]const u8 = null,
    /// 本地：家目录，用于判断“在 ~”。
    home: ?[]const u8 = null,
    /// 本地：前台程序名（不是 shell 本身时才给）。
    program: ?[]const u8 = null,
    /// 本地：状态后缀（“启动失败”“已退出”），空串表示正常。
    suffix: []const u8 = "",
};

fn trimSlash(path: []const u8) []const u8 {
    var end = path.len;
    while (end > 1 and path[end - 1] == '/') end -= 1;
    return path[0..end];
}

/// 路径末级名；根目录返回 "/"。
pub fn basename(path: []const u8) []const u8 {
    const value = trimSlash(path);
    if (value.len == 0) return value;
    if (std.mem.eql(u8, value, "/")) return value;
    const at = std.mem.lastIndexOfScalar(u8, value, '/') orelse return value;
    return value[at + 1 ..];
}

/// 上一级目录的末级名（家目录写 “~”）；没有上一级时 null。
pub fn parentName(path: []const u8, home: ?[]const u8) ?[]const u8 {
    const value = trimSlash(path);
    const at = std.mem.lastIndexOfScalar(u8, value, '/') orelse return null;
    if (at == 0) return if (value.len > 1) "/" else null;
    const parent = value[0..at];
    if (home) |h| if (std.mem.eql(u8, trimSlash(h), parent)) return "~";
    return basename(parent);
}

fn atHome(source: Source) bool {
    const cwd = source.cwd orelse return false;
    const home = source.home orelse return false;
    return std.mem.eql(u8, trimSlash(cwd), trimSlash(home));
}

/// 不含区分片段的名字。
pub fn base(allocator: std.mem.Allocator, source: Source) ![]u8 {
    if (source.custom) |value| if (value.len != 0) return allocator.dupe(u8, value);
    switch (source.kind) {
        .remote, .other => return allocator.dupe(u8, source.label),
        .local => {
            const home = atHome(source);
            const dir: []const u8 = if (source.cwd) |cwd| (if (home) "~" else basename(cwd)) else "~";
            const known_dir = source.cwd != null and !home;
            var out: std.ArrayList(u8) = .empty;
            errdefer out.deinit(allocator);
            if (source.program) |program| if (program.len != 0) {
                try out.appendSlice(allocator, program);
                try out.appendSlice(allocator, " · ");
                try out.appendSlice(allocator, if (source.cwd != null) dir else home_label);
            };
            if (out.items.len == 0) try out.appendSlice(allocator, if (known_dir) dir else home_label);
            if (source.suffix.len != 0) {
                try out.appendSlice(allocator, " · ");
                try out.appendSlice(allocator, source.suffix);
            }
            return out.toOwnedSlice(allocator);
        },
    }
}

/// 一组页签的显示名（与 `sources` 一一对应，同一 allocator 分配，用 `freeAll` 释放）。
pub fn resolve(allocator: std.mem.Allocator, sources: []const Source) ![][]u8 {
    const bases = try allocator.alloc([]u8, sources.len);
    var based: usize = 0;
    defer {
        for (bases[0..based]) |name| allocator.free(name);
        allocator.free(bases);
    }
    for (sources, 0..) |source, i| {
        bases[i] = try base(allocator, source);
        based += 1;
    }
    const names = try allocator.alloc([]u8, sources.len);
    var filled: usize = 0;
    errdefer {
        for (names[0..filled]) |name| allocator.free(name);
        allocator.free(names);
    }
    for (0..sources.len) |i| {
        // 第一次出现保留原名；后面的按出现顺序编号或加上一级目录名。
        var ordinal: usize = 1;
        for (bases[0..i]) |other| {
            if (std.mem.eql(u8, other, bases[i])) ordinal += 1;
        }
        names[i] = if (ordinal == 1)
            try allocator.dupe(u8, bases[i])
        else if (distinctParent(sources, bases, i)) |parent|
            try std.fmt.allocPrint(allocator, "{s} · {s}", .{ bases[i], parent })
        else
            try std.fmt.allocPrint(allocator, "{s} · {d}", .{ bases[i], ordinal });
        filled += 1;
    }
    return names;
}

/// 本地终端的同名项：上一级目录名在同名组里唯一、且与第一项不同时用它。
fn distinctParent(sources: []const Source, bases: []const []u8, index: usize) ?[]const u8 {
    const source = sources[index];
    if (source.kind != .local or source.custom != null) return null;
    const cwd = source.cwd orelse return null;
    const parent = parentName(cwd, source.home) orelse return null;
    for (sources, 0..) |other, j| {
        if (j == index or !std.mem.eql(u8, bases[j], bases[index])) continue;
        const other_cwd = other.cwd orelse continue;
        const other_parent = parentName(other_cwd, other.home) orelse continue;
        if (std.mem.eql(u8, other_parent, parent)) return null;
    }
    return parent;
}

pub fn freeAll(allocator: std.mem.Allocator, names: [][]u8) void {
    for (names) |name| allocator.free(name);
    allocator.free(names);
}

/// 会话组页签：“组 · 组名”（成员数由视图单独排，截断组名不截断成员数）。
pub fn groupTitle(buffer: []u8, name: []const u8) []const u8 {
    const prefix = "组 · ";
    if (std.mem.startsWith(u8, name, prefix)) return fit(buffer, name);
    const out = std.fmt.bufPrint(buffer, "{s}{s}", .{ prefix, name }) catch return fit(buffer, prefix ++ "…");
    return out;
}

fn fit(buffer: []u8, value: []const u8) []const u8 {
    var n = @min(value.len, buffer.len);
    while (n > 0 and !std.unicode.utf8ValidateSlice(value[0..n])) n -= 1;
    @memcpy(buffer[0..n], value[0..n]);
    return buffer[0..n];
}

/// “(3)”：会话组成员数。
pub fn memberCount(buffer: []u8, count: usize) []const u8 {
    return std.fmt.bufPrint(buffer, "({d})", .{count}) catch "";
}

/// Tooltip：“完整名称 · 路径或地址 · shell / 类型 · 快捷键”，空的段跳过。
pub fn tooltip(allocator: std.mem.Allocator, parts: []const []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    for (parts) |part| {
        if (part.len == 0) continue;
        if (out.items.len != 0) try out.appendSlice(allocator, " · ");
        try out.appendSlice(allocator, part);
    }
    return out.toOwnedSlice(allocator);
}

/// 家目录缩写成 “~”（Tooltip 里的路径）。
pub fn shortPath(buffer: []u8, path: []const u8, home: ?[]const u8) []const u8 {
    if (home) |h| {
        const prefix = trimSlash(h);
        if (prefix.len > 1 and std.mem.startsWith(u8, path, prefix) and (path.len == prefix.len or path[prefix.len] == '/')) {
            return std.fmt.bufPrint(buffer, "~{s}", .{path[prefix.len..]}) catch fit(buffer, path);
        }
    }
    return fit(buffer, path);
}

/// ⌘ 序号（稿 3：按住 ⌘ 时关闭按钮位置换成 “⌘1…⌘9”，⌘9 总是最后一个页签）。
/// 返回 1…9；没有快捷键的页签返回 null。
pub fn commandOrdinal(index: usize, count: usize) ?u8 {
    if (count == 0 or index >= count) return null;
    if (index == count - 1) return if (count <= 9) @intCast(count) else 9;
    if (index < 8) return @intCast(index + 1);
    return null;
}

/// ⌘N 选中的页签下标（⌘9 = 最后一个）。
pub fn ordinalTarget(digit_index: usize, count: usize) ?usize {
    if (count == 0) return null;
    if (digit_index == 8) return count - 1;
    return if (digit_index < count) digit_index else null;
}

const testing = std.testing;

fn expectNames(sources: []const Source, expected: []const []const u8) !void {
    const names = try resolve(testing.allocator, sources);
    defer freeAll(testing.allocator, names);
    try testing.expectEqual(expected.len, names.len);
    for (expected, names) |want, got| try testing.expectEqualStrings(want, got);
}

test "tab naming: custom > host > local cwd basename; never Local Terminal" {
    const home = "/Users/me";
    try expectNames(&.{
        .{ .kind = .remote, .label = "staging-api" },
        .{ .kind = .remote, .label = "prod-web-01", .custom = "生产" },
        .{ .kind = .local, .cwd = "/Users/me/src/zerowork", .home = home },
        .{ .kind = .local, .cwd = "/Users/me/docs", .home = home },
        .{ .kind = .local, .cwd = "/Users/me", .home = home },
        .{ .kind = .local },
        .{ .kind = .other, .label = "assets · SFTP" },
    }, &.{ "staging-api", "生产", "zerowork", "docs", "本地终端", "本地终端 · 2", "assets · SFTP" });
}

test "tab naming: foreground program reads program · dir" {
    const home = "/Users/me";
    try expectNames(&.{
        .{ .kind = .local, .cwd = "/Users/me/zerowork", .home = home, .program = "vim" },
        .{ .kind = .local, .cwd = "/Users/me", .home = home, .program = "htop" },
        .{ .kind = .local, .program = "top" },
    }, &.{ "vim · zerowork", "htop · ~", "top · 本地终端" });
}

test "tab naming: duplicates add · 2 / · 3 or the shortest parent fragment" {
    const home = "/Users/me";
    try expectNames(&.{
        .{ .kind = .remote, .label = "staging-api" },
        .{ .kind = .remote, .label = "staging-api" },
        .{ .kind = .remote, .label = "staging-api" },
    }, &.{ "staging-api", "staging-api · 2", "staging-api · 3" });
    try expectNames(&.{
        .{ .kind = .local, .cwd = "/Users/me/zerowork", .home = home },
        .{ .kind = .local, .cwd = "/Users/me/src/zerowork", .home = home },
        .{ .kind = .local, .cwd = "/Users/me/src/zerowork", .home = home },
    }, &.{ "zerowork", "zerowork · 2", "zerowork · 3" });
    try expectNames(&.{
        .{ .kind = .local, .cwd = "/Users/me/zerowork", .home = home },
        .{ .kind = .local, .cwd = "/Users/me/src/zerowork", .home = home },
    }, &.{ "zerowork", "zerowork · src" });
}

test "tab naming: state suffix follows the derived name" {
    try expectNames(&.{
        .{ .kind = .local, .cwd = "/tmp/build", .suffix = "已退出" },
        .{ .kind = .local, .suffix = "启动失败" },
    }, &.{ "build · 已退出", "本地终端 · 启动失败" });
}

test "tab naming: group title, member count, tooltip and short path" {
    var buffer: [96]u8 = undefined;
    try testing.expectEqualStrings("组 · 发布检查", groupTitle(&buffer, "发布检查"));
    try testing.expectEqualStrings("组 · 发布检查", groupTitle(&buffer, "组 · 发布检查"));
    var count: [16]u8 = undefined;
    try testing.expectEqualStrings("(3)", memberCount(&count, 3));
    var path: [96]u8 = undefined;
    try testing.expectEqualStrings("~/docs", shortPath(&path, "/Users/me/docs", "/Users/me"));
    try testing.expectEqualStrings("/etc", shortPath(&path, "/etc", "/Users/me"));
    const tip = try tooltip(testing.allocator, &.{ "本地终端", "~/docs", "", "zsh", "⌘4" });
    defer testing.allocator.free(tip);
    try testing.expectEqualStrings("本地终端 · ~/docs · zsh · ⌘4", tip);
}

test "tab naming: command ordinals, the ninth ordinal is always the last tab" {
    try testing.expectEqual(@as(?u8, 1), commandOrdinal(0, 3));
    try testing.expectEqual(@as(?u8, 3), commandOrdinal(2, 3));
    try testing.expectEqual(@as(?u8, 8), commandOrdinal(7, 12));
    try testing.expectEqual(@as(?u8, null), commandOrdinal(8, 12));
    try testing.expectEqual(@as(?u8, 9), commandOrdinal(11, 12));
    try testing.expectEqual(@as(?u8, 9), commandOrdinal(8, 9));
    try testing.expectEqual(@as(?usize, 11), ordinalTarget(8, 12));
    try testing.expectEqual(@as(?usize, 2), ordinalTarget(8, 3));
    try testing.expectEqual(@as(?usize, null), ordinalTarget(5, 3));
    try testing.expectEqual(@as(?usize, 1), ordinalTarget(1, 3));
}
