//! 统一工具注册表（PLUGIN_ARCH_PLAN 2.9 T1）的组合级等价性测试：用生产组合根
//! （linked_plugins.initRegistry + 随应用插件）发布的快照，与 T1 之前直接读
//! 清单 / 静态 import 的拼法分别建请求表，逐字比较模型可见的工具列表与系统提示，
//! 并比较每个目标的分发入口与参数校验结果。
const std = @import("std");
const T = std.testing;
const a = T.allocator;
const linked = @import("plugins/linked_plugins.zig");
const composition = @import("plugins/application_plugins.zig");
const plugins = @import("host/plugin_registry.zig");
const sessions = @import("host/session_host.zig");
const identity = @import("host/identity.zig");
const services = @import("host/plugin_services.zig");
const tools = @import("ai/plugin_tools.zig");
const host_tools = @import("ai/host_tools.zig");
const catalog = @import("ai/host_tool_catalog.zig");
const registry = @import("ai/tool_registry.zig");
const tool_def = @import("ai/tool_def.zig");
const prompt = @import("ai/session_prompt.zig");
const scope = @import("ai/tool_scope.zig");
const config = @import("config/config.zig");
const enablement = @import("host/plugin_enablement.zig");

const all_enabled: enablement.Launch = enablement.Launch.init(&composition.Bundle(true).linked, .{ .preferences = &.{} });
const FakeAdapter = struct {
    var context: u8 = 0;
    fn create(_: *anyopaque, _: sessions.CreateRequest) !void {}
    fn cancel(_: *anyopaque, _: @import("host/operation.zig").OperationKey) sessions.CloseReceipt {
        return .released;
    }
    fn close(_: *anyopaque, _: identity.SessionHandle, _: @import("host/operation.zig").OperationKey) !sessions.CloseReceipt {
        return .released;
    }
    fn stale(_: *anyopaque, _: identity.SessionHandle, _: @import("host/operation.zig").OperationKey) void {}
    const vtable: sessions.Adapter.VTable = .{ .create = create, .cancel = cancel, .close = close, .release_stale = stale };
    fn adapters() [3]sessions.Adapter {
        return .{
            .{ .registration = .{ .plugin_id = .local, .workspace_kind = .terminal, .services = plugins.requiredServices(.local) }, .context = &context, .vtable = &vtable },
            .{ .registration = .{ .plugin_id = .ssh, .workspace_kind = .terminal, .services = linked.sshServices() }, .context = &context, .vtable = &vtable },
            .{ .registration = .{ .plugin_id = .sftp, .workspace_kind = .file, .services = plugins.requiredServices(.sftp) }, .context = &context, .vtable = &vtable },
        };
    }
};

/// 生产组合：内置 local / ssh / sftp + 随应用插件（acceptance 版本额外含 fixture_probe）。
const Production = struct {
    tmp: T.TmpDir,
    path: [:0]u8,
    bundle: *composition.Bundle(true),
    published: plugins.Registry,
    fn init() !*Production {
        const self = try a.create(Production);
        errdefer a.destroy(self);
        self.tmp = T.tmpDir(.{});
        errdefer self.tmp.cleanup();
        self.path = try self.tmp.dir.realPathFileAlloc(T.io, ".", a);
        errdefer a.free(self.path);
        self.bundle = try a.create(composition.Bundle(true));
        errdefer a.destroy(self.bundle);
        self.bundle.* = try composition.Bundle(true).init(a, T.io, self.path, &all_enabled);
        const adapters = FakeAdapter.adapters();
        self.published = try linked.initRegistry(a, &adapters, self.bundle.manifests(), self.bundle.renderers());
        return self;
    }
    fn deinit(self: *Production) void {
        self.published.deinit();
        self.bundle.deinit() catch unreachable;
        a.destroy(self.bundle);
        a.free(self.path);
        self.tmp.cleanup();
        a.destroy(self);
    }
};

const Dummy = struct {
    var service_context: u8 = 0;
    var service_vtable: u8 = 0;
};
const Members = struct {
    arena: std.heap.ArenaAllocator,
    old: []tools.Member,
    new: []tools.Member,
    old_definitions: []const tools.ToolDefinition,
    new_definitions: []const tools.ToolDefinition,
    scope: scope.Scope,
    fn deinit(self: *Members) void {
        self.arena.deinit();
    }
};
/// T1 之前：成员绑定取 `manifest.tools`，定义取全部 `manifest.tool_definitions`
/// （ai_tools.prepareScope 原样）。T1 之后：都从注册表快照按插件 / 卡片类型筛出。
fn buildMembers(published: *const plugins.Registry, manifest_ids: []const []const u8, group: bool) !Members {
    var arena = std.heap.ArenaAllocator.init(a);
    errdefer arena.deinit();
    const x = arena.allocator();
    const old = try x.alloc(tools.Member, manifest_ids.len);
    const new = try x.alloc(tools.Member, manifest_ids.len);
    var old_definitions: std.ArrayList(tools.ToolDefinition) = .empty;
    var new_definitions: std.ArrayList(tools.ToolDefinition) = .empty;
    var captured: scope.Scope = .{ .owner = if (group) .{ .tab = 9 } else .{ .tab = 1 }, .content = if (group) .{ .group = 9 } else .{ .session = 1 }, .members = .{} };
    for (manifest_ids, old, new, 0..) |id, *old_member, *new_member, index| {
        const manifest = published.find(id).?;
        const owner: identity.SessionHandle = .{ .session_id = @fromBackingInt(index + 1), .generation = 3 };
        const bound = try x.alloc(services.Binding, manifest.services.len);
        for (manifest.services, bound) |definition, *binding| binding.* = .{ .definition = definition, .context = &Dummy.service_context, .vtable = &Dummy.service_vtable, .owner = owner, .generation = owner.generation };
        old_member.* = .{ .owner = owner, .plugin_id = manifest.id, .context = manifest.session_factory.?.context, .bindings = manifest.tools, .services = bound };
        new_member.* = old_member.*;
        new_member.bindings = published.tools.pluginBindings(manifest.id);
        for (manifest.tool_definitions) |definition| {
            for (old_definitions.items) |existing| {
                if (std.mem.eql(u8, existing.id, definition.id)) break;
            } else try old_definitions.append(x, definition);
        }
        for (published.tools.pluginEntries(manifest.id)) |entry| {
            const definition = entry.origin.plugin.definition;
            for (new_definitions.items) |existing| {
                if (std.mem.eql(u8, existing.id, definition.id)) break;
            } else try new_definitions.append(x, definition);
        }
        captured.members.ids[captured.members.len] = index + 1;
        captured.members.len += 1;
    }
    return .{ .arena = arena, .old = old, .new = new, .old_definitions = try old_definitions.toOwnedSlice(x), .new_definitions = try new_definitions.toOwnedSlice(x), .scope = captured };
}

/// T1 之前 AiHost.prepareHostCatalog 的逐字拷贝（静态 import 拼接），仅用于等价性对照。
fn legacyHostCatalog(request: catalog.Request, out: *catalog.Buffer) usize {
    var len: usize = 0;
    out[len] = @import("ai/user_interaction.zig").contribution;
    len += 1;
    for (@import("ai/host_queries.zig").contributions) |contribution| {
        out[len] = contribution;
        len += 1;
    }
    for (@import("ai/host_catalog.zig").contributions) |contribution| {
        if (request.queries_only and @import("ai/host_catalog.zig").isMutation(contribution.definition.id)) continue;
        out[len] = contribution;
        len += 1;
    }
    if (request.child_gateway) {
        out[len] = @import("ai/child_gateway.zig").contribution;
        len += 1;
    }
    if (request.extension) |session| {
        for (@import("ai/extension_gateway.zig").contributions) |contribution| {
            const skill_tool = std.mem.eql(u8, contribution.definition.id, "host.skills");
            if (skill_tool and !session.skills) continue;
            if (!skill_tool and (!session.servers or request.queries_only)) continue;
            out[len] = contribution;
            len += 1;
        }
    }
    if (request.queries_only) return len;
    out[len] = @import("ai/builtin_tools.zig").contribution;
    len += 1;
    for (@import("ai/host_queries.zig").terminal_contributions) |contribution| {
        out[len] = contribution;
        len += 1;
    }
    for (@import("ai/fetch_url.zig").contributions) |contribution| {
        out[len] = contribution;
        len += 1;
    }
    out[len] = @import("ai/batch_output.zig").contribution;
    len += 1;
    if (request.execution) for (@import("ai/host_execution.zig").contributions) |contribution| {
        out[len] = contribution;
        len += 1;
    };
    if (request.lifecycle) |lifecycle| for (@import("ai/host_lifecycle.zig").contributions) |contribution| {
        if (!lifecycle.available(lifecycle.context, contribution.definition.id)) continue;
        out[len] = contribution;
        len += 1;
    };
    return len;
}
const LifecycleMode = enum { none, all, alternate, deny };
const LifecycleProbe = struct {
    mode: LifecycleMode,
    calls: usize = 0,
    fn available(raw: *anyopaque, _: []const u8) bool {
        const self: *LifecycleProbe = @ptrCast(@alignCast(raw));
        self.calls += 1;
        return switch (self.mode) {
            .all => true,
            .deny, .none => false,
            .alternate => self.calls % 2 == 0,
        };
    }
};

fn expectSameWire(old: []const @import("ai/provider.zig").ToolDefinition, new: []const @import("ai/provider.zig").ToolDefinition) !void {
    try T.expectEqual(old.len, new.len);
    for (old, new) |left, right| {
        try T.expectEqualStrings(left.name(), right.name());
        try T.expectEqual(left.authority, right.authority);
        try T.expectEqualSlices(u64, left.session_ids, right.session_ids);
        try T.expectEqualStrings(left.dynamic.?.id, right.dynamic.?.id);
        try T.expectEqualStrings(left.dynamic.?.description, right.dynamic.?.description);
        try T.expectEqualStrings(left.dynamic.?.schema, right.dynamic.?.schema);
    }
    for (std.enums.values(config.ExecutionMode)) |mode| {
        const left = try prompt.build(a, mode, old);
        defer a.free(left);
        const right = try prompt.build(a, mode, new);
        defer a.free(right);
        try T.expectEqualStrings(left, right);
    }
}
/// 每个工具每个目标的分发入口相同（同一 handler、同一上下文、同一插件、同一所需服务）。
fn expectSameDispatch(old: *const tools.RequestTable, new: *const tools.RequestTable) !void {
    try T.expectEqual(old.entries.len, new.entries.len);
    for (old.entries, new.entries) |left, right| {
        try T.expect(tools.sameDefinition(left.definition, right.definition));
        try T.expectEqual(left.authority, right.authority);
        try T.expectEqual(left.targets.len, right.targets.len);
        for (left.targets, right.targets) |x, y| {
            try T.expect(x.owner.eql(y.owner));
            try T.expect(x.binding.handler == y.binding.handler);
            try T.expectEqual(x.binding.execution, y.binding.execution);
            try T.expectEqualStrings(x.binding.plugin_id, y.binding.plugin_id);
            try T.expect(x.context == y.context);
            try T.expectEqual(x.binding.required_services.len, y.binding.required_services.len);
            for (x.binding.required_services, y.binding.required_services) |p, q| try T.expect(p.matches(q));
        }
    }
}
/// 参数校验结果相同：同一组参数在两张表上要么都通过，要么给出同一个错误。
fn expectSameParse(old: *const tools.RequestTable, new: *const tools.RequestTable) !void {
    const corpus = [_][]const u8{ "{}", "[]", "{\"session_ids\":[1]}", "{\"session_ids\":[1,2]}", "{\"session_ids\":[99]}", "{\"session_ids\":[1],\"command\":\"ls\"}", "{\"session_ids\":[1],\"path\":\"/etc\"}", "{\"session_ids\":[1],\"path\":\"etc\"}", "{\"session_ids\":[1],\"unknown\":true}", "{\"limit\":5}", "{\"detail\":\"summary\"}", "{\"session_ref\":\"x\"}", "{\"url\":\"https://example.test/\"}", "not json" };
    for (old.entries) |entry| for (corpus) |arguments| {
        const left = old.parse(a, entry.provider_name, arguments);
        const right = new.parse(a, entry.provider_name, arguments);
        if (left) |value| {
            var l = value;
            defer l.deinit();
            var r = try right;
            defer r.deinit();
            try T.expectEqualSlices(u64, l.targets.slice(), r.targets.slice());
            try T.expectEqualSlices(u8, &l.arguments_hash, &r.arguments_hash);
        } else |err| {
            if (right) |value| {
                var r = value;
                r.deinit();
                return error.ParseMismatch;
            } else |other| try T.expectEqual(err, other);
        }
    };
}

const host_context: host_tools.Context = .{ .conversation_id = .{ .bytes = @splat(1) }, .task_id = .{ .bytes = @splat(2) }, .binding = .{ .tab = 9 }, .content = .{ .group = 9 }, .binding_revision = 2, .grant_revision = 1 };

test "tooldef production registry snapshot reproduces every request tool list and system prompt byte for byte" {
    const production = try Production.init();
    defer production.deinit();
    const snapshot = &production.published.tools;
    // 每个清单都登记进了注册表，绑定逐项相同。
    for (production.published.manifests()) |manifest| {
        try T.expectEqual(manifest.tools.ptr, snapshot.pluginBindings(manifest.id).ptr);
        try T.expectEqual(manifest.tools.len, snapshot.pluginEntries(manifest.id).len);
        for (snapshot.pluginEntries(manifest.id), manifest.tools) |entry, binding| {
            try T.expectEqualStrings(binding.definition_id, entry.def.name);
            try T.expect(entry.def.handler.session == binding.handler);
            try T.expect(entry.def.target.eql(.{ .card_type = manifest.content_renderer }));
            try T.expectEqual(if (tools.legacyName(binding.definition_id)) registry.Source.legacy else registry.Source.plugin, entry.source);
        }
    }
    // 宿主工具：注册表里的每个分组与 T1 之前的静态表逐项相同。
    for (catalog.groups) |group| {
        const stored = snapshot.hostGroup(group.group);
        try T.expectEqual(group.contributions.len, stored.len);
        for (group.contributions, stored) |left, right| {
            try T.expect(tools.sameDefinition(left.definition, right.definition));
            try T.expectEqual(left.authority, right.authority);
        }
    }

    const sets = [_][]const []const u8{ &.{"local"}, &.{"ssh"}, &.{"sftp"}, &.{"bmc_ikvm"}, &.{"fixture_probe"}, &.{ "local", "ssh", "sftp", "bmc_ikvm" }, &.{ "ssh", "bmc_ikvm", "fixture_probe" } };
    for (sets) |set| for ([_]bool{ false, true }) |group| {
        if (!group and set.len != 1) continue;
        var members = try buildMembers(&production.published, set, group);
        defer members.deinit();
        var old = try tools.RequestTable.init(a, members.scope, members.old_definitions, members.old);
        defer old.deinit();
        var new = try tools.RequestTable.init(a, members.scope, members.new_definitions, members.new);
        defer new.deinit();
        try T.expect(new.entries.len != 0);
        var wire_arena = std.heap.ArenaAllocator.init(a);
        defer wire_arena.deinit();
        try expectSameWire(try tools.providerDefinitions(&old, wire_arena.allocator()), try tools.providerDefinitions(&new, wire_arena.allocator()));
        try expectSameDispatch(&old, &new);
        try expectSameParse(&old, &new);

        // 加上宿主工具：所有请求条件组合下，宿主工具表与 T1 之前的拼法逐项相同。
        if (!group) continue;
        for ([_]bool{ false, true }) |queries_only| for ([_]bool{ false, true }) |child| for (0..5) |extension_case| for ([_]bool{ false, true }) |execution| for (std.enums.values(LifecycleMode)) |lifecycle_mode| {
            var old_probe: LifecycleProbe = .{ .mode = lifecycle_mode };
            var new_probe: LifecycleProbe = .{ .mode = lifecycle_mode };
            const extension: @FieldType(catalog.Request, "extension") = switch (extension_case) {
                0 => null,
                1 => .{ .skills = false, .servers = false },
                2 => .{ .skills = true, .servers = false },
                3 => .{ .skills = false, .servers = true },
                else => .{ .skills = true, .servers = true },
            };
            var request: catalog.Request = .{ .queries_only = queries_only, .child_gateway = child, .extension = extension, .execution = execution };
            if (lifecycle_mode != .none) request.lifecycle = .{ .context = &old_probe, .available = LifecycleProbe.available };
            var old_buffer: catalog.Buffer = undefined;
            const old_len = legacyHostCatalog(request, &old_buffer);
            if (lifecycle_mode != .none) request.lifecycle = .{ .context = &new_probe, .available = LifecycleProbe.available };
            var selected_buffer: catalog.Buffer = undefined;
            const selected_len = catalog.select(snapshot, request, &selected_buffer);
            // M11：唯一的变化是紧跟宿主查询之后多了直接按 ToolDef 写的 host.tab_context；其余逐项相同。
            const native_at = snapshot.hostGroup(.user_interaction).len + snapshot.hostGroup(.queries).len;
            try T.expectEqual(old_len + catalog.native.len, selected_len);
            for (catalog.native, selected_buffer[native_at..][0..catalog.native.len]) |def, contribution| {
                try T.expectEqualStrings(def.name, contribution.definition.id);
                try T.expect(tools.sameDefinition(catalog.nativeContribution(def).definition, contribution.definition));
                try T.expectEqual(@import("ai/provider.zig").ToolAuthority.conversation_context, contribution.authority);
            }
            var new_buffer: catalog.Buffer = undefined;
            var new_len: usize = 0;
            for (selected_buffer[0..selected_len]) |contribution| {
                if (catalog.isNative(contribution.definition.id)) continue;
                new_buffer[new_len] = contribution;
                new_len += 1;
            }
            try T.expectEqual(old_len, new_len);
            for (old_buffer[0..old_len], new_buffer[0..new_len]) |left, right| {
                try T.expect(tools.sameDefinition(left.definition, right.definition));
                try T.expectEqual(left.authority, right.authority);
                try T.expect(left.session_targets == null and right.session_targets == null);
            }
            if (queries_only or child or extension_case != 4 or !execution or lifecycle_mode != .all) continue;
            // 完整宿主工具表 + 插件工具：最终请求表与系统提示逐字一致。
            var old_full = try tools.RequestTable.initWithHost(a, members.scope, members.old_definitions, members.old, host_context, old_buffer[0..old_len]);
            defer old_full.deinit();
            var new_full = try tools.RequestTable.initWithHost(a, members.scope, members.new_definitions, members.new, host_context, new_buffer[0..new_len]);
            defer new_full.deinit();
            try expectSameWire(try tools.providerDefinitions(&old_full, wire_arena.allocator()), try tools.providerDefinitions(&new_full, wire_arena.allocator()));
            try expectSameDispatch(&old_full, &new_full);
            try expectSameParse(&old_full, &new_full);
        };
    };
}

test "tooldef production tools pin their convention debt and new tools are strict" {
    const production = try Production.init();
    defer production.deinit();
    const report = try registry.debtReport(a, &production.published.tools);
    defer a.free(report);
    // 现有工具不合 2.9 第 4 条约定的地方（T1 行为不变，只记录）。这张表只减不增：
    // T2 / T3 迁移时改掉一项就删一行；新增工具必须直接合规（`Builder.register` 严格检查）。
    try T.expectEqualStrings(expected_debt, report);
    // 统计：全部登记项都能导出成 MCP tool（形状一一对应）。
    for (production.published.tools.entries) |entry| {
        const exported = try tool_def.toMcpTool(a, entry.def);
        defer a.free(exported);
        const parsed = try std.json.parseFromSlice(std.json.Value, a, exported, .{});
        defer parsed.deinit();
        var name: [64]u8 = undefined;
        try T.expectEqualStrings(entry.def.name, try tools.decodeName(&name, parsed.value.object.get("name").?.string));
        try T.expectEqualStrings(entry.def.description, parsed.value.object.get("description").?.string);
    }
}

const expected_debt = @embedFile("ai/tests/tool_convention_debt.txt");
