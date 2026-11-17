//! 随应用提供（`bundled`）插件的启用 / 禁用（PLUGIN_ARCH_PLAN 2.4、6.2.1 的 Q5、Q5a–Q5c；PL1 机制）。
//!
//! - 只对 `origin = .bundled` 的插件生效；内置的 local / ssh / sftp 写了 `host.enabled = "false"` 也不生效（Q5a，调用方记警告）。
//! - 状态存放在 `config.toml` 的 `[[plugin_preferences]]`：`plugin_id = <id>`、`key = "host.enabled"`、`value = "false"`。
//!   没有这一条就表示启用；重新启用时删除这一条，而不是写成 `"true"`。
//! - 启动时在构造插件 bundle **之前**读取（`app/main.zig`）。被禁用的插件不初始化、不交给注册表，所以它的创建入口、服务、
//!   AI 工具、通知定义与 `ai_context` 摘要都随快照消失；切换在下次启动时生效（Q5b）。
//! - 配置无法读取或无法解析时，`bundled` 插件按禁用处理（fail-closed，Q5c）；内置三项不受影响。
//! - 禁用只是“不初始化、不注册、不暴露入口”：插件的代码仍在同一个可执行文件里，随应用一起签名分发（6.2.1“禁用不是卸载”）。
//!
//! 启动时的读法（`readSource`）与设置页的读法（`savedEnabled`）都只经过 `Config.parseWithAllocator` 与
//! `disabledIn`，两条路径读到的值一致（本文件的单测覆盖）。
const std = @import("std");
const registry = @import("plugin_registry.zig");
const config = @import("../config/config.zig");

/// 宿主保留的偏好键前缀：插件不能把自己的偏好字段命名为 `host.*`（注册校验拒绝，2.2 第 7 条）。
pub const reserved_prefix = "host.";
/// 启用状态的保留键。
pub const enabled_key = "host.enabled";
pub const disabled_value = "false";

/// “已链接插件表”的一行：不初始化插件就能读到的元数据（PL1 第 6 条）。设置页的列表 / 详情、侧栏的“已禁用”原因、
/// 连接向导的禁用选项都按它区分“被禁用的插件”和“未知插件”。
pub const Linked = struct {
    id: []const u8,
    display_name: []const u8,
    summary: ?[]const u8 = null,
    plugin_version: []const u8,
    origin: registry.Origin = .bundled,
    icons: registry.Icons = .{},
    dependencies: []const registry.Dependency = &.{},
    provides: []const registry.ApiDefinition = &.{},
    /// 能不能在连接向导里新建（有 `connection` 贡献）。
    creatable: bool = true,
};

/// 启动时读到的启用状态来源。
pub const Source = union(enum) {
    /// 配置可读（文件不存在时是空表，等同全部启用）。
    preferences: []const config.PluginPreference,
    /// 配置无法读取或解析（Q5c：`bundled` 插件按禁用处理）。
    unreadable,
};

pub fn isEnabledEntry(preference: config.PluginPreference) bool {
    return std.mem.eql(u8, preference.key, enabled_key);
}

/// 偏好表里是否写了“禁用”。只认 `"false"`；其它值（含 `"true"`）都按启用。
pub fn disabledIn(preferences: []const config.PluginPreference, plugin_id: []const u8) bool {
    for (preferences) |preference| {
        if (std.mem.eql(u8, preference.plugin_id, plugin_id) and isEnabledEntry(preference)) return std.mem.eql(u8, preference.value, disabled_value);
    }
    return false;
}

/// 某个已链接插件在本次启动时是否初始化并注册。内置插件永远启用（Q5a）。
pub fn enabledAtLaunch(linked: Linked, source: Source) bool {
    if (linked.origin != .bundled) return true;
    return switch (source) {
        .unreadable => false,
        .preferences => |preferences| !disabledIn(preferences, linked.id),
    };
}

/// 已保存配置（设置页的 `original`）里，插件是否处于启用状态。内置插件永远启用。
pub fn savedEnabled(value: config.Config, linked: Linked) bool {
    return enabledAtLaunch(linked, .{ .preferences = value.plugin_preferences });
}

/// 对内置插件写了 `host.enabled` 的偏好条目（Q5a：不生效，调用方逐条记警告）。
pub fn ignoredBuiltinEntry(preference: config.PluginPreference, builtin_ids: []const []const u8) bool {
    if (!isEnabledEntry(preference)) return false;
    for (builtin_ids) |id| if (std.mem.eql(u8, id, preference.plugin_id)) return true;
    return false;
}

/// 如果有另一个已启用的插件依赖 `target` 提供（`provides`）的 API，返回那个插件；禁用 `target` 会让下次启动的
/// `publish` 因缺依赖整体失败，所以要拒绝（6.2.1 Q5“依赖”）。今天没有这种依赖，规则先写上。
pub fn blockingDependent(table: []const Linked, enabled: []const bool, target: Linked) ?Linked {
    for (table, 0..) |other, index| {
        if (std.mem.eql(u8, other.id, target.id)) continue;
        if (index < enabled.len and !enabled[index]) continue;
        for (other.dependencies) |dependency| for (target.provides) |api| {
            if (std.mem.eql(u8, dependency.id, api.id) and dependency.major == api.major) return other;
        };
    }
    return null;
}

/// 进程启动时定下的事实（之后不再变化，切换在下次启动时生效）。
pub const Launch = struct {
    pub const capacity = 16;
    linked_storage: [capacity]Linked = undefined,
    enabled_storage: [capacity]bool = @splat(true),
    count: usize = 0,
    /// 配置无法读取或解析：随应用提供的插件这次没有加载（Q5c）。
    config_unreadable: bool = false,

    pub fn init(table: []const Linked, source: Source) Launch {
        var result: Launch = .{ .config_unreadable = source == .unreadable };
        for (table[0..@min(table.len, capacity)]) |entry| {
            result.linked_storage[result.count] = entry;
            result.enabled_storage[result.count] = enabledAtLaunch(entry, source);
            result.count += 1;
        }
        return result;
    }
    pub fn linked(self: *const Launch) []const Linked {
        return self.linked_storage[0..self.count];
    }
    pub fn enabledFlags(self: *const Launch) []const bool {
        return self.enabled_storage[0..self.count];
    }
    pub fn indexOf(self: *const Launch, id: []const u8) ?usize {
        for (self.linked(), 0..) |entry, index| if (std.mem.eql(u8, entry.id, id)) return index;
        return null;
    }
    pub fn find(self: *const Launch, id: []const u8) ?Linked {
        return self.linked_storage[self.indexOf(id) orelse return null];
    }
    pub fn isEnabled(self: *const Launch, id: []const u8) bool {
        const index = self.indexOf(id) orelse return false;
        return self.enabled_storage[index];
    }
    /// 已链接、但这次启动没有加载的插件（区别于“未知插件”）。
    pub fn disabled(self: *const Launch, id: []const u8) ?Linked {
        const index = self.indexOf(id) orelse return null;
        return if (self.enabled_storage[index]) null else self.linked_storage[index];
    }
};

/// 启动前读配置里的启用状态：只读文件并解析，不碰钥匙串、不迁移、不写回。文件不存在时是空表；读不出或解析失败时
/// 是 `.unreadable`（Q5c）。`arena` 持有返回的偏好表。
pub fn readSource(io: std.Io, dir: std.Io.Dir, arena: std.mem.Allocator, path: []const u8) Source {
    if (path.len == 0) return .unreadable;
    const text = dir.readFileAlloc(io, path, arena, .limited(config_limit)) catch |err| return switch (err) {
        error.FileNotFound => .{ .preferences = &.{} },
        else => .unreadable,
    };
    return parseSource(arena, text);
}
pub fn parseSource(arena: std.mem.Allocator, text: []const u8) Source {
    const value = config.Config.parseWithAllocator(arena, text) catch return .unreadable;
    value.validate() catch return .unreadable;
    return .{ .preferences = value.plugin_preferences };
}
const config_limit = @import("../config/store.zig").max_config_bytes;

/// 设置页“状态”分组的状态（41 号说明稿的状态流转）。
pub const Phase = enum {
    /// 已启用，已保存配置也是启用（Jm2fZ）。
    enabled,
    /// 草稿里拨动了开关、还没保存（SH1gb：沿用保存栏）。
    draft,
    /// 已保存，与本次启动时的状态不同，等待重启（NHr2L / DzPbO）。
    pending_disable,
    pending_enable,
    /// 本次启动没有加载，已保存配置也是禁用（B0QXg6 / IeCzY）。
    disabled,
};
pub fn phase(launch_enabled: bool, saved_enabled: bool, draft_enabled: bool) Phase {
    if (draft_enabled != saved_enabled) return .draft;
    if (saved_enabled != launch_enabled) return if (saved_enabled) .pending_enable else .pending_disable;
    return if (launch_enabled) .enabled else .disabled;
}

const testing = std.testing;
const probe: Linked = .{ .id = "probe", .display_name = "Probe", .plugin_version = "1.0.0", .origin = .bundled };
const ssh_like: Linked = .{ .id = "ssh", .display_name = "SSH", .plugin_version = "1.0.0", .origin = .builtin };

test "Q5: only an explicit host.enabled = false disables a bundled plugin; builtins ignore it" {
    const prefs = [_]config.PluginPreference{
        .{ .plugin_id = "probe", .key = "host.enabled", .value = "false" },
        .{ .plugin_id = "ssh", .key = "host.enabled", .value = "false" },
        .{ .plugin_id = "probe", .key = "show_grid", .value = "false" },
    };
    try testing.expect(!enabledAtLaunch(probe, .{ .preferences = &prefs }));
    try testing.expect(enabledAtLaunch(ssh_like, .{ .preferences = &prefs }));
    try testing.expect(ignoredBuiltinEntry(prefs[1], &.{ "local", "ssh", "sftp" }));
    try testing.expect(!ignoredBuiltinEntry(prefs[0], &.{ "local", "ssh", "sftp" }));
    try testing.expect(!ignoredBuiltinEntry(prefs[2], &.{"probe"}));
    // 没有条目、写成 "true" 都是启用。
    try testing.expect(enabledAtLaunch(probe, .{ .preferences = &.{} }));
    const truthy = [_]config.PluginPreference{.{ .plugin_id = "probe", .key = "host.enabled", .value = "true" }};
    try testing.expect(enabledAtLaunch(probe, .{ .preferences = &truthy }));
}

test "Q5c: an unreadable or unparseable config disables bundled plugins only" {
    try testing.expect(!enabledAtLaunch(probe, .unreadable));
    try testing.expect(enabledAtLaunch(ssh_like, .unreadable));
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try testing.expect(parseSource(arena.allocator(), "[ui\nbroken") == .unreadable);
    const launch = Launch.init(&.{ ssh_like, probe }, .unreadable);
    try testing.expect(launch.config_unreadable);
    try testing.expect(launch.isEnabled("ssh"));
    try testing.expect(launch.disabled("probe") != null);
    try testing.expect(launch.disabled("unknown") == null);
}

test "startup read and settings read agree on the same config text" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const text =
        \\[[plugin_preferences]]
        \\plugin_id = "probe"
        \\key = "host.enabled"
        \\value = "false"
        \\
    ;
    const source = parseSource(arena.allocator(), text);
    try testing.expect(source == .preferences);
    const value = try config.Config.parseWithAllocator(arena.allocator(), text);
    try testing.expectEqual(enabledAtLaunch(probe, source), savedEnabled(value, probe));
    try testing.expect(!savedEnabled(value, probe));
    // 读文件：不存在 → 全部启用；存在 → 同上。
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const io = testing.io;
    try testing.expect(readSource(io, tmp.dir, arena.allocator(), "missing.toml").preferences.len == 0);
    try tmp.dir.writeFile(io, .{ .sub_path = "config.toml", .data = text });
    try testing.expect(!enabledAtLaunch(probe, readSource(io, tmp.dir, arena.allocator(), "config.toml")));
    try tmp.dir.writeFile(io, .{ .sub_path = "broken.toml", .data = "[ui]\nfont_size = not-a-number\n" });
    try testing.expect(readSource(io, tmp.dir, arena.allocator(), "broken.toml") == .unreadable);
}

test "disabling is refused while another enabled plugin depends on what it provides" {
    const provider: Linked = .{ .id = "provider", .display_name = "Provider", .plugin_version = "1", .provides = &.{.{ .id = "provider.api", .major = 2 }} };
    const consumer: Linked = .{ .id = "consumer", .display_name = "Consumer", .plugin_version = "1", .dependencies = &.{.{ .id = "provider.api", .major = 2 }} };
    const all = [_]Linked{ provider, consumer, probe };
    try testing.expectEqualStrings("consumer", blockingDependent(&all, &.{ true, true, true }, provider).?.id);
    try testing.expect(blockingDependent(&all, &.{ true, false, true }, provider) == null);
    try testing.expect(blockingDependent(&all, &.{ true, true, true }, probe) == null);
}

test "settings phase follows the 41 state flow" {
    try testing.expectEqual(Phase.enabled, phase(true, true, true));
    try testing.expectEqual(Phase.draft, phase(true, true, false));
    try testing.expectEqual(Phase.pending_disable, phase(true, false, false));
    // 待重启时拨回并保存：回到原状态，不需要重启。
    try testing.expectEqual(Phase.enabled, phase(true, true, true));
    try testing.expectEqual(Phase.disabled, phase(false, false, false));
    try testing.expectEqual(Phase.pending_enable, phase(false, true, true));
}
