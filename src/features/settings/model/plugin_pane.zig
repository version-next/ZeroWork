//! 协议插件分类的数据（F-set-plugins，人工验收反馈第 10 条）：两级导航——列表页（Pencil `T5k96`）→ 每个已注册插件
//! 一个详情页（`KUKQ5`）。插件是运行时数据（`Controller.plugin_page.registry_source`），所以本分类不在
//! `pane_fields.zig` 的静态面板表里：列表的分组、搜索过滤、文案与 test_id 都从注册表派生，规则同旧
//! `view/panes/settings_plugins.zig`（3f 已删除）。
//!
//! 只展示注册的元数据：名称、来源、版本、清单里的说明（`summary`）、权限说明与插件自带的偏好字段；不为插件编造能力。
//! 列表页末尾的“计划中”只列路线条目（`host/plugin_roadmap.zig`，PLUGIN_ARCH_PLAN 2.6 / Q1）：名称与“{目标版本} 版本待实施”，
//! 没有能力、版本号、权限，也不能进入详情页。
//!
//! 详情页的位置是 `Location{ .page = 5, .sub = <插件在注册表里的下标> }`（`settings_history.isDynamic`）。
//! 本文件不依赖 zenit `ui`。
const std = @import("std");
const catalog = @import("catalog.zig");
const history = @import("settings_history.zig");
pub const registry = @import("../../../host/plugin_registry.zig");

pub const Manifest = registry.PluginManifest;
pub const Origin = registry.Origin;
pub const PreferenceField = registry.PreferenceField;

/// 分类下标（`settings_pages.pages` 里的“协议插件”）。
pub const page: usize = history.dynamic_page;
/// 一个页面最多挂多少个插件行 / 偏好行（id 与文字缓冲按它分槽）。
pub const max_plugins: usize = history.dynamic_subpage_capacity;
pub const max_preferences: usize = 16;
pub const max_options: usize = 16;

/// 列表页的分组（`T5k96`：已内置 / 随应用提供），顺序同旧实现。
pub const Group = enum { builtin, bundled };
pub const groups = [_]Group{ .builtin, .bundled };

pub fn origin(group: Group) Origin {
    return switch (group) {
        .builtin => .builtin,
        .bundled => .bundled,
    };
}
/// 分组标题（旧分组标签的前半）。
pub fn groupTitle(group: Group) []const u8 {
    return switch (group) {
        .builtin => "已内置",
        .bundled => "随应用提供",
    };
}
/// 分组面板根的 test_id（旧分组标签的 id）。
pub fn groupId(group: Group) []const u8 {
    return switch (group) {
        .builtin => "settings.plugins.builtin",
        .bundled => "settings.plugins.bundled",
    };
}
pub fn groupHeaderId(group: Group) []const u8 {
    return switch (group) {
        .builtin => "settings.plugins.builtin.header",
        .bundled => "settings.plugins.bundled.header",
    };
}
pub fn groupMetaId(group: Group) []const u8 {
    return switch (group) {
        .builtin => "settings.plugins.builtin.summary",
        .bundled => "settings.plugins.bundled.summary",
    };
}
/// 详情页信息面板正文的 test_id（旧详情正文的 id，按来源）。
pub fn bodyId(value: Origin) []const u8 {
    return switch (value) {
        .builtin => "settings.plugins.builtin.body",
        .bundled => "settings.plugins.bundled.body",
    };
}
pub fn groupOf(value: Origin) Group {
    return switch (value) {
        .builtin => .builtin,
        .bundled => .bundled,
    };
}
/// 来源标签（详情页头部卡片的原生 `W.Tag`）。
pub fn originTag(value: Origin) []const u8 {
    return switch (value) {
        .builtin => "内置",
        .bundled => "随应用提供",
    };
}
/// 详情页头部卡片下的说明（旧详情页头的“已内置 · 随应用管理”与版本对话框的“插件随应用更新”）。
pub fn manageNote(value: Origin) []const u8 {
    return switch (value) {
        .builtin => "已内置 · 随应用管理 · 插件随应用更新",
        .bundled => "随应用提供 · 随应用管理 · 插件随应用更新",
    };
}

/// 插件的一句话说明：清单的 `summary`；清单没写时只给它注册的工作区类型。
pub fn description(entry: Manifest) []const u8 {
    return entry.summary orelse entry.workspace_kind;
}
/// 权限说明全文（同旧 `settings_plugins.permissions`）。
pub fn permissions(entry: Manifest) []const u8 {
    if (std.mem.eql(u8, entry.id, "local")) return "允许本机 Shell 进程与当前目录访问；\n实际授权遵循 macOS 权限。";
    if (std.mem.eql(u8, entry.id, "ssh")) return "连接时按需读取钥匙串、进行网络连接及用户批准的转发。";
    if (std.mem.eql(u8, entry.id, "sftp")) return "按用户选择的路径访问本地文件，通过远端连接读写目录；传输任务可取消。";
    return "连接时按需请求权限";
}
/// 权限行的值（旧“权限”事实行）。
pub const permissions_value = "连接时按需请求";

/// 搜索（同旧 `settings_plugins.entryMatches`）：名称、来源、“协议 插件”；搜索词命中分类名时整类不过滤。
pub fn matches(query: []const u8, entry: Manifest) bool {
    const q = effectiveQuery(query);
    const m = catalog.search.matches;
    return m(q, entry.display_name) or m(q, groupTitle(groupOf(entry.origin))) or m(q, "协议 插件");
}
pub fn effectiveQuery(query: []const u8) []const u8 {
    if (query.len != 0 and catalog.search.matches(query, catalog.pages.pages[page].name)) return "";
    return query;
}
/// 某分组在搜索词下命中的插件数。
pub fn groupCount(entries: []const Manifest, group: Group, query: []const u8) usize {
    var count: usize = 0;
    for (entries[0..@min(entries.len, max_plugins)]) |entry| {
        if (entry.origin == origin(group) and matches(query, entry)) count += 1;
    }
    return count;
}
/// 搜索词下有没有命中的插件（搜索结果里本分类是否显示）。
pub fn anyMatch(entries: []const Manifest, query: []const u8) bool {
    for (groups) |group| if (groupCount(entries, group, query) != 0) return true;
    return false;
}

// ── 随应用插件的启用开关（PLUGIN_ARCH_PLAN 6.2.1 Q5；文案按 Pencil XqqLV 稿 2 / 41 号说明稿） ──

pub const Phase = @import("../../../host/plugin_enablement.zig").Phase;
/// “状态”分组的标题与右侧说明。
pub const status_title = "状态";
pub const status_meta = "重启后生效";
/// 开关下方的说明（`settings.plugin.<id>.enabled.hint`）：如实说明“禁用不是卸载”。
pub const toggle_hint = "重启 ZeroWork 后生效。停用只是不再加载，插件代码仍随应用分发；已保存的主机与凭据保留。";
/// 已禁用提示的正文（B0QXg6）：已保存主机、插件自有数据都保留；禁用期间插件自己的待确认操作不会被核对。
pub const disabled_message = "使用此协议的已保存主机在侧栏和连接向导里显示为“已禁用、不可连接”，配置与凭据保留；插件自己的数据文件不打开也不删除，禁用期间它不会核对待确认的操作。重新打开开关并重启后恢复。";
/// 配置无法读取（Q5c）。
pub const unreadable_message = "为避免加载你可能已关闭的插件，配置文件修复之前，随应用提供的插件不会加载。内置的本地终端、SSH、SFTP 不受影响。";
pub const restart_label = "立即重启";

/// 头部卡片 / 列表行上的状态标签（41 号说明稿：待重启 warning，已禁用中性）。
pub fn stateTag(value: Phase) []const u8 {
    return switch (value) {
        .pending_disable => "重启后停用",
        .pending_enable => "重启后启用",
        .disabled => "已禁用",
        .enabled, .draft => "",
    };
}
pub fn stateWarning(value: Phase) bool {
    return value == .pending_disable or value == .pending_enable;
}
/// 待重启提示的正文（NHr2L）。
pub fn pendingMessage(value: Phase) []const u8 {
    return if (value == .pending_enable)
        "更改已保存。重启后加载这个插件，它的连接、AI 工具和通知恢复可用；关闭开关并保存即可撤销。"
    else
        "更改已保存。重启前插件照常可用，已打开的会话不受影响；重新打开开关并保存即可撤销。";
}

// ── 计划中（路线条目） ──

pub const roadmap = @import("../../../host/plugin_roadmap.zig");
pub const planned_title = "计划中";
/// 路线条目在搜索词下是否命中：名称、“计划中”、“协议 插件”。
pub fn plannedMatches(query: []const u8, entry: roadmap.RoadmapEntry) bool {
    const q = effectiveQuery(query);
    const m = catalog.search.matches;
    return m(q, entry.display_name) or m(q, planned_title) or m(q, "协议 插件");
}
pub fn plannedCount(query: []const u8) usize {
    var count: usize = 0;
    for (roadmap.entries) |entry| count += @intFromBool(plannedMatches(query, entry));
    return count;
}
/// 计划行的说明：“{目标版本} 版本待实施”（条目是编译期数据）。
pub fn plannedSummary(comptime entry: roadmap.RoadmapEntry) []const u8 {
    return entry.target ++ " 版本待实施";
}
/// 计划行的 test_id：`settings.plugins.planned.<条目 id>.<后缀>`（后缀 row / name / summary）。
pub fn plannedId(comptime entry: roadmap.RoadmapEntry, comptime suffix: []const u8) []const u8 {
    return "settings.plugins.planned." ++ entry.id ++ "." ++ suffix;
}

/// 插件偏好字段的“生效时机”提示（旧 `controls.inlineHint`）。
pub fn timingText(field: PreferenceField) []const u8 {
    return if (field.apply_timing == .next_connection) "下次连接生效" else "保存后生效";
}
/// 偏好字段的当前值（草稿里的值，否则是字段默认值）。
pub fn preferenceValue(value: catalog.config.Config, plugin_id: []const u8, field: PreferenceField) []const u8 {
    return value.pluginPreference(plugin_id, field.key) orelse field.default_value orelse "";
}

/// 详情页里能挂的偏好字段（超过 `max_preferences` 的不挂；旧实现没有上限，注册表里的插件都远少于此）。
pub fn preferenceFields(entry: Manifest) []const PreferenceField {
    const section = entry.settings_section orelse return &.{};
    return section.fields[0..@min(section.fields.len, max_preferences)];
}

test "plugin pane data follows the registry and the old matching rules" {
    const entries = [_]Manifest{
        .{ .id = "ssh", .display_name = "SSH", .origin = .builtin, .workspace_kind = "terminal", .content_renderer = "terminal" },
        .{ .id = "probe", .display_name = "Probe", .origin = .bundled, .workspace_kind = "canvas", .content_renderer = "canvas" },
    };
    try std.testing.expectEqualStrings("terminal", description(entries[0]));
    var with_summary = entries[0];
    with_summary.summary = "远程终端、认证与端口转发";
    try std.testing.expectEqualStrings("远程终端、认证与端口转发", description(with_summary));
    try std.testing.expectEqualStrings("canvas", description(entries[1]));
    try std.testing.expectEqualStrings("连接时按需请求权限", permissions(entries[1]));
    try std.testing.expectEqual(@as(usize, 1), groupCount(&entries, .builtin, ""));
    try std.testing.expectEqual(@as(usize, 1), groupCount(&entries, .bundled, "随应用"));
    try std.testing.expectEqual(@as(usize, 0), groupCount(&entries, .builtin, "随应用"));
    // 搜索词命中分类名：整类不过滤。
    try std.testing.expectEqual(@as(usize, 1), groupCount(&entries, .builtin, "协议插件"));
    try std.testing.expect(!anyMatch(&entries, "保活"));
}

test "planned group lists only roadmap entries and follows search" {
    try std.testing.expectEqual(@as(usize, 1), plannedCount(""));
    try std.testing.expectEqual(@as(usize, 1), plannedCount("网页"));
    try std.testing.expectEqual(@as(usize, 1), plannedCount("计划"));
    try std.testing.expectEqual(@as(usize, 0), plannedCount("SSH"));
    try std.testing.expectEqualStrings("0.5 版本待实施", plannedSummary(roadmap.entries[0]));
    try std.testing.expectEqualStrings("settings.plugins.planned.web.row", plannedId(roadmap.entries[0], "row"));
}
