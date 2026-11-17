//! 统一工具注册表（PLUGIN_ARCH_PLAN 2.9 第 3 条）。组合根在发布插件注册表时
//! 同时构建它：两阶段校验（逐项 `register*`，整体 `publish`），发布后是不可变
//! 快照；每次请求的工具表从快照按作用域筛出来，不再分别拼三个来源。
//!
//! T1 的三个适配器把现有定义原样登记成 `ToolDef`：
//! - `registerPlugin`：插件清单的 `ToolDefinition` + `ToolBinding`（bmc 等）；
//!   其中 `plugin_tools.legacyName` 命中的四个工具（`run_command`、
//!   `read_terminal`、`list_remote_files`、`read_remote_file`）记为遗留来源，
//!   它们的 `evaluate_policy`（例如 shellPolicy）成为审批步骤的钩子；
//! - `registerHost`：宿主的 `host.Contribution`。
//! 适配器保留原始定义（`origin`），请求表据此逐字复用，因此模型可见的名称、
//! 描述、schema、审批与分发入口都不变。现有工具不合约定的地方记为约定债务
//! （`debt`），由单测钉住、只减不增；直接按 `ToolDef` 写的新工具严格检查。
const std = @import("std");
const tool_def = @import("tool_def.zig");
const tools = @import("plugin_tools.zig");
const host = @import("host_tools.zig");
const services = @import("../host/plugin_services.zig");

pub const ToolDef = tool_def.ToolDef;

/// 宿主工具的来源分组。顺序即 AiHost 拼宿主工具表的顺序（`host_tool_catalog.groups`）。
pub const HostGroup = enum { user_interaction, queries, catalog, child_gateway, extension, builtin, terminal, fetch_url, batch_output, execution, lifecycle };
pub const HostGroupEntry = struct { group: HostGroup, contributions: []const host.Contribution };

pub const Source = enum { native, plugin, legacy, host };
pub const PluginOrigin = struct { definition: tools.ToolDefinition, binding: tools.ToolBinding };
pub const HostOrigin = struct { contribution: host.Contribution, group: HostGroup };
pub const Origin = union(enum) { native, plugin: PluginOrigin, host: HostOrigin };
pub const Entry = struct {
    def: ToolDef,
    source: Source,
    origin: Origin,
    /// 现有工具不合 2.9 第 4 条约定的地方（适配器登记时记录，不拒绝）。
    debt: tool_def.Violations = .empty,
};

/// 请求期的作用域选择：tab 内有哪些卡片类型、来自哪个插件。
pub const Selection = struct {
    global: bool = true,
    tab: bool = true,
    card_types: []const []const u8 = &.{},
    /// 只选这个插件提供的工具（会话卡片按它的清单筛）；null 表示不限。
    plugin: ?[]const u8 = null,
    host: bool = true,
};

const PluginRange = struct { plugin_id: []const u8, entries: []const Entry, bindings: []const tools.ToolBinding };
const GroupRange = struct { group: HostGroup, contributions: []const host.Contribution };

/// 不可变快照。字符串与 handler 上下文借用自登记来源（已克隆的清单与静态
/// 宿主表），生命周期与发布它的插件注册表相同。
pub const Snapshot = struct {
    entries: []const Entry = &.{},
    plugins: []const PluginRange = &.{},
    host_groups: []const GroupRange = &.{},

    pub fn find(self: *const Snapshot, name: []const u8) ?*const Entry {
        for (self.entries) |*entry| if (std.mem.eql(u8, entry.def.name, name)) return entry;
        return null;
    }
    /// 某插件登记的全部工具，顺序与清单 `tools` 相同。
    pub fn pluginEntries(self: *const Snapshot, plugin_id: []const u8) []const Entry {
        for (self.plugins) |range| if (std.mem.eql(u8, range.plugin_id, plugin_id)) return range.entries;
        return &.{};
    }
    /// 与 `pluginEntries` 一一对应的执行绑定（请求表的成员绑定）。
    pub fn pluginBindings(self: *const Snapshot, plugin_id: []const u8) []const tools.ToolBinding {
        for (self.plugins) |range| if (std.mem.eql(u8, range.plugin_id, plugin_id)) return range.bindings;
        return &.{};
    }
    /// 某分组的宿主工具，元素即原 `host.Contribution`（逐字复用）。
    pub fn hostGroup(self: *const Snapshot, group: HostGroup) []const host.Contribution {
        for (self.host_groups) |range| if (range.group == group) return range.contributions;
        return &.{};
    }
    pub fn selects(selection: Selection, entry: *const Entry) bool {
        if (selection.plugin) |plugin_id| switch (entry.def.owner) {
            .plugin => |owner| if (!std.mem.eql(u8, owner, plugin_id)) return false,
            .host => {},
        };
        if (!selection.host and entry.def.owner == .host) return false;
        return switch (entry.def.target) {
            .global => selection.global,
            .tab => selection.tab,
            .card_type => |name| for (selection.card_types) |candidate| {
                if (std.mem.eql(u8, candidate, name)) break true;
            } else false,
        };
    }
    /// 按作用域筛出本次请求可见的工具（按登记顺序）。
    pub fn select(self: *const Snapshot, allocator: std.mem.Allocator, selection: Selection) ![]const *const Entry {
        var out: std.ArrayList(*const Entry) = .empty;
        errdefer out.deinit(allocator);
        for (self.entries) |*entry| if (selects(selection, entry)) try out.append(allocator, entry);
        return out.toOwnedSlice(allocator);
    }
};

/// 宿主工具分组 → 作用目标：用户交互、扩展（技能与 MCP 网关）与本机网络读取
/// 不依附于某个 tab；其余都在本次对话绑定的 tab（会话或会话组）内生效。
pub fn hostTarget(group: HostGroup) tool_def.Target {
    return switch (group) {
        .user_interaction, .extension, .fetch_url => .global,
        else => .tab,
    };
}

/// 适配器：宿主 `host.Contribution` → `ToolDef`。
pub fn fromHost(contribution: host.Contribution, group: HostGroup) !ToolDef {
    const definition = contribution.definition;
    if (contribution.authority == .session_targets or !std.mem.startsWith(u8, definition.id, "host.") or definition.required_services.len != 0) return error.InvalidHostAuthority;
    return .{
        .name = definition.id,
        .version = definition.version,
        .description = definition.description,
        .input_schema = definition.schema,
        .output = .structured,
        .handler = .host_gateway,
        .owner = .host,
        .approval = definition.approval_policy,
        .effect = definition.effect,
        .target = hostTarget(group),
        // 宿主结果今天由 `host.Result.validate` 限在 64 KiB，超出即拒绝。
        .budget = .{ .max_argument_bytes = definition.max_argument_bytes, .max_result_bytes = 64 * 1024, .truncate = .reject },
        .validate = definition.validate,
        .approval_hook = definition.evaluate_policy,
    };
}

/// 适配器：插件 `ToolDefinition` + `ToolBinding` → `ToolDef`。`card_type` 是
/// 清单的内容渲染器（会话卡片类型）。`required_services` 由调用方合并好传入。
pub fn fromPlugin(plugin_id: []const u8, card_type: []const u8, definition: tools.ToolDefinition, binding: tools.ToolBinding, required: []const services.Requirement) ToolDef {
    return .{
        .name = definition.id,
        .version = definition.version,
        .description = definition.description,
        .input_schema = definition.schema,
        .output = if (definition.effect == .observe_image) .structured_with_images else .structured,
        .handler = .{ .session = binding.handler },
        .owner = .{ .plugin = plugin_id },
        .permission = .{ .plugin_id = plugin_id },
        .approval = definition.approval_policy,
        .effect = definition.effect,
        .target = .{ .card_type = card_type },
        .required_services = required,
        // 插件结果今天由 `ToolResult.validate` 限在 64 KiB 文本，超出即拒绝。
        .budget = .{ .max_argument_bytes = definition.max_argument_bytes, .max_result_bytes = 64 * 1024, .truncate = .reject },
        .validate = definition.validate,
        .approval_hook = definition.evaluate_policy,
    };
}

pub const Builder = struct {
    arena: std.heap.ArenaAllocator,
    staged: std.ArrayList(Entry) = .empty,
    plugin_marks: std.ArrayList(struct { plugin_id: []const u8, start: usize, bindings: []const tools.ToolBinding }) = .empty,
    group_marks: std.ArrayList(struct { group: HostGroup, contributions: []const host.Contribution }) = .empty,

    pub fn init(allocator: std.mem.Allocator) Builder {
        return .{ .arena = .init(allocator) };
    }
    pub fn deinit(self: *Builder) void {
        self.arena.deinit();
        self.* = undefined;
    }

    // ── 阶段一：逐项校验 ──────────────────────────────────────────────

    /// 直接按 `ToolDef` 写的工具：受限子集、名称与 schema 约定全部强制。
    pub fn register(self: *Builder, def: ToolDef) !void {
        if (def.handler != .native) return error.InvalidToolHandler;
        try validateBasics(def);
        try tool_def.checkConventions(def);
        switch (def.owner) {
            .plugin => |plugin_id| {
                const permission = def.permission orelse return error.ToolPermissionUndeclared;
                if (!std.mem.eql(u8, permission.plugin_id, plugin_id)) return error.ToolPermissionUndeclared;
                if (!std.mem.startsWith(u8, def.name, plugin_id) or def.name.len <= plugin_id.len or def.name[plugin_id.len] != '.') {
                    if (def.target != .card_type) return error.ToolNamespaceMismatch;
                }
            },
            .host => if (def.permission != null) return error.InvalidHostAuthority,
        }
        if (def.target == .card_type and def.target.card_type.len == 0) return error.InvalidToolTarget;
        try self.staged.append(self.arena.allocator(), .{ .def = def, .source = .native, .origin = .native });
    }

    /// 宿主分组适配器。同一分组只登记一次，保持组内顺序。
    pub fn registerHost(self: *Builder, group: HostGroup, contributions: []const host.Contribution) !void {
        for (self.group_marks.items) |mark| if (mark.group == group) return error.DuplicateHostGroup;
        for (contributions) |contribution| {
            const def = try fromHost(contribution, group);
            try validateBasics(def);
            try self.staged.append(self.arena.allocator(), .{ .def = def, .source = .host, .origin = .{ .host = .{ .contribution = contribution, .group = group } }, .debt = tool_def.conventionViolations(def) });
        }
        try self.group_marks.append(self.arena.allocator(), .{ .group = group, .contributions = contributions });
    }

    /// 插件清单适配器：与 `PluginHost.publish` 同一套绑定校验（命名空间、
    /// 重复绑定、未知定义、未声明服务），每个绑定登记成一个 `ToolDef`。
    pub fn registerPlugin(self: *Builder, plugin_id: []const u8, card_type: []const u8, definitions: []const tools.ToolDefinition, bindings: []const tools.ToolBinding, declared: []const services.Definition) !void {
        for (self.plugin_marks.items) |mark| if (std.mem.eql(u8, mark.plugin_id, plugin_id)) return error.DuplicatePlugin;
        try tools.validateBindings(plugin_id, definitions, bindings, declared);
        const a = self.arena.allocator();
        const start = self.staged.items.len;
        for (bindings) |binding| {
            const definition = for (definitions) |candidate| {
                if (std.mem.eql(u8, candidate.id, binding.definition_id)) break candidate;
            } else return error.UnknownToolDefinition;
            const required = try a.alloc(services.Requirement, definition.required_services.len + binding.required_services.len);
            @memcpy(required[0..definition.required_services.len], definition.required_services);
            @memcpy(required[definition.required_services.len..], binding.required_services);
            const def = fromPlugin(plugin_id, card_type, definition, binding, required);
            try validateBasics(def);
            try self.staged.append(a, .{ .def = def, .source = if (tools.legacyName(definition.id)) .legacy else .plugin, .origin = .{ .plugin = .{ .definition = definition, .binding = binding } }, .debt = tool_def.conventionViolations(def) });
        }
        try self.plugin_marks.append(a, .{ .plugin_id = plugin_id, .start = start, .bindings = bindings });
    }

    // ── 阶段二：整体校验并发布 ────────────────────────────────────────

    /// 全部登记项一起校验后复制进 `allocator`（通常是插件注册表的 arena）。
    /// 任何一项失败都不发布。
    pub fn publish(self: *Builder, allocator: std.mem.Allocator) !Snapshot {
        const staged = self.staged.items;
        for (staged, 0..) |entry, index| {
            var wire: [64]u8 = undefined;
            const name = try entry.def.wireName(&wire);
            for (staged[0..index]) |earlier| {
                if (std.mem.eql(u8, earlier.def.name, entry.def.name)) {
                    // 同名只允许多个插件共享同一份定义（例如 local / ssh 的 run_command）。
                    if (earlier.def.owner == .host or entry.def.owner == .host) return error.DuplicateTool;
                    if (std.mem.eql(u8, earlier.def.owner.plugin, entry.def.owner.plugin)) return error.DuplicateToolBinding;
                    if (!ToolDef.sameContract(earlier.def, entry.def)) return error.ToolDefinitionConflict;
                    if (earlier.origin == .plugin and entry.origin == .plugin and !tools.sameDefinition(earlier.origin.plugin.definition, entry.origin.plugin.definition)) return error.ToolDefinitionConflict;
                    continue;
                }
                var other: [64]u8 = undefined;
                if (std.mem.eql(u8, try earlier.def.wireName(&other), name)) return error.ToolNameCollision;
            }
        }
        const entries = try allocator.alloc(Entry, staged.len);
        for (staged, entries) |entry, *copy| {
            copy.* = entry;
            copy.def.required_services = try allocator.dupe(services.Requirement, entry.def.required_services);
        }
        const plugins = try allocator.alloc(PluginRange, self.plugin_marks.items.len);
        // registerPlugin 一次登记一个插件的全部绑定，因此每个插件的范围连续。
        for (self.plugin_marks.items, plugins) |mark, *range| range.* = .{ .plugin_id = mark.plugin_id, .entries = entries[mark.start..][0..mark.bindings.len], .bindings = mark.bindings };
        const groups = try allocator.alloc(GroupRange, self.group_marks.items.len);
        for (self.group_marks.items, groups) |mark, *range| range.* = .{ .group = mark.group, .contributions = mark.contributions };
        return .{ .entries = entries, .plugins = plugins, .host_groups = groups };
    }
};

fn validateBasics(def: ToolDef) !void {
    try tools.validateDefinition(.{ .id = def.name, .version = def.version, .description = def.description, .schema = def.input_schema, .max_argument_bytes = def.budget.max_argument_bytes });
    if (def.budget.max_result_bytes == 0 or def.budget.max_result_bytes > 64 * 1024) return error.InvalidToolBudget;
}

/// 生产工具的约定债务清单（名称 → 违反项），由单测钉住。
pub fn debtReport(allocator: std.mem.Allocator, snapshot: *const Snapshot) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    for (snapshot.entries, 0..) |entry, index| {
        var seen = false;
        for (snapshot.entries[0..index]) |earlier| if (std.mem.eql(u8, earlier.def.name, entry.def.name)) {
            seen = true;
            break;
        };
        if (seen or entry.debt.count() == 0) continue;
        try out.appendSlice(allocator, entry.def.name);
        try out.append(allocator, ':');
        var iterator = entry.debt.iterator();
        while (iterator.next()) |violation| {
            try out.append(allocator, ' ');
            try out.appendSlice(allocator, @tagName(violation));
        }
        try out.append(allocator, '\n');
    }
    return out.toOwnedSlice(allocator);
}

test {
    _ = @import("tests/tool_registry_tests.zig");
}
