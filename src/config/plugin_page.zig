//! Protocol settings page state: the published registry and the selected plugin.
//! Only registered manifests are shown. "计划中" rows come from the separate
//! roadmap table (`host/plugin_roadmap.zig`), never from this state. This model
//! intentionally has no install, permission, preview or reload command.
const std = @import("std");
const registry = @import("../host/plugin_registry.zig");
const enablement = @import("../host/plugin_enablement.zig");

pub const State = struct {
    /// Selected plugin ID (legacy master/detail layout only). Page state, never a Config edit.
    selection: []const u8 = "local",
    builtin_registry_snapshot: []const registry.BuiltinSnapshot,
    registry_source: registry.Registry,
    settings_draft_revision: u64,
    /// 本次启动时随应用插件的启用状态与“已链接插件表”（Q5）。null 时（单测、预览）没有被禁用的插件。
    launch: ?*const enablement.Launch = null,
    /// 设置页列出的插件：注册表里的清单，后面接本次启动被禁用、所以不在注册表里的随应用插件（只有已链接插件表里的
    /// 元数据：名称、说明、版本、来源、图标；没有服务、偏好字段与工厂）。
    entry_storage: [entry_capacity]registry.PluginManifest = undefined,
    entry_count: usize = 0,

    pub const entry_capacity = 32;

    pub fn init(source: registry.Registry, revision: u64) State {
        var result: State = .{ .builtin_registry_snapshot = source.snapshot(), .registry_source = source, .settings_draft_revision = revision };
        result.rebuild();
        return result;
    }

    pub fn refreshRegistry(self: *State, source: registry.Registry, revision: u64) void {
        self.builtin_registry_snapshot = source.snapshot();
        self.registry_source = source;
        self.settings_draft_revision = revision;
        self.rebuild();
    }

    pub fn setLaunch(self: *State, launch: ?*const enablement.Launch) void {
        self.launch = launch;
        self.rebuild();
    }

    fn rebuild(self: *State) void {
        self.entry_count = 0;
        for (self.registry_source.manifests()) |manifest| {
            if (self.entry_count == entry_capacity) return;
            self.entry_storage[self.entry_count] = manifest;
            self.entry_count += 1;
        }
        const launch = self.launch orelse return;
        for (launch.linked(), launch.enabledFlags()) |entry, enabled| {
            if (enabled or self.registry_source.find(entry.id) != null) continue;
            if (self.entry_count == entry_capacity) return;
            self.entry_storage[self.entry_count] = .{ .id = entry.id, .display_name = entry.display_name, .summary = entry.summary, .plugin_version = entry.plugin_version, .origin = entry.origin, .icons = entry.icons, .dependencies = entry.dependencies, .provides = entry.provides, .workspace_kind = "", .content_renderer = "" };
            self.entry_count += 1;
        }
    }

    /// 设置页的插件列表（注册表顺序，被禁用的随应用插件排在后面）。
    pub fn entries(self: *const State) []const registry.PluginManifest {
        return self.entry_storage[0..self.entry_count];
    }

    /// 插件能否在设置里禁用（Q5a：只有已链接插件表里的随应用插件）。
    pub fn linked(self: *const State, plugin_id: []const u8) ?enablement.Linked {
        const launch = self.launch orelse return null;
        const entry = launch.find(plugin_id) orelse return null;
        return if (entry.origin == .bundled) entry else null;
    }

    /// 本次启动时是否加载了它（没有启动事实时：注册表里有就算加载了）。
    pub fn launchEnabled(self: *const State, plugin_id: []const u8) bool {
        const launch = self.launch orelse return self.registry_source.find(plugin_id) != null;
        if (launch.indexOf(plugin_id) == null) return self.registry_source.find(plugin_id) != null;
        return launch.isEnabled(plugin_id);
    }

    pub fn select(self: *State, plugin_id: []const u8) void {
        self.selection = plugin_id;
    }
};

test "protocol page reflects the real registry and keeps its selection" {
    const source = registry.Registry.builtins();
    var page = State.init(source, 7);
    try std.testing.expectEqual(@as(usize, 3), page.builtin_registry_snapshot.len);
    for (page.builtin_registry_snapshot) |entry| {
        try std.testing.expectEqual(registry.Availability.adapter_not_connected, entry.availability);
        try std.testing.expectEqualStrings(registry.plugin_version, entry.descriptor.plugin_version);
    }
    page.select("ssh");
    page.refreshRegistry(source, 8);
    try std.testing.expectEqualStrings("ssh", page.selection);
    try std.testing.expectEqual(@as(u64, 8), page.settings_draft_revision);
}

test "disabled bundled plugins stay listed from the linked table, after registered ones" {
    const entries = [_]registry.PluginManifest{.{ .id = "ssh", .display_name = "SSH", .origin = .builtin, .workspace_kind = "terminal", .content_renderer = "terminal" }};
    var page = State.init(.{ .published = .{ .entries = &entries, .renderers = &.{} } }, 1);
    try std.testing.expectEqual(@as(usize, 1), page.entries().len);
    const launch = enablement.Launch.init(&.{.{ .id = "probe", .display_name = "Probe", .summary = "合成画面", .plugin_version = "0.2.0", .icons = .{ .settings = "server" } }}, .{ .preferences = &.{.{ .plugin_id = "probe", .key = "host.enabled", .value = "false" }} });
    page.setLaunch(&launch);
    try std.testing.expectEqual(@as(usize, 2), page.entries().len);
    try std.testing.expectEqualStrings("probe", page.entries()[1].id);
    try std.testing.expectEqualStrings("合成画面", page.entries()[1].summary.?);
    try std.testing.expect(page.entries()[1].settings_section == null);
    try std.testing.expect(!page.launchEnabled("probe"));
    try std.testing.expect(page.launchEnabled("ssh"));
    try std.testing.expect(page.linked("probe") != null);
    try std.testing.expect(page.linked("ssh") == null);
}
