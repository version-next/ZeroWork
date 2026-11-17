//! Maximum catalog is derived from the actual contributions, including group
//! lifecycle tools and optional extensions. Runtime filtering only narrows it.
//!
//! 宿主工具按来源分组登记进统一工具注册表（tool_registry.zig）。`groups` 由组合根
//! （linked_plugins.initRegistry）交给 `PluginHost.publish`；每次请求由 `select`
//! 从注册表快照按分组与请求条件筛出宿主工具表，顺序与 T1 之前 AiHost 逐个
//! import 拼接的顺序相同。
const host = @import("host_tools.zig");
const registry = @import("tool_registry.zig");
pub const Group = registry.HostGroup;
pub const groups = [_]registry.HostGroupEntry{
    .{ .group = .user_interaction, .contributions = &.{@import("user_interaction.zig").contribution} },
    .{ .group = .queries, .contributions = &@import("host_queries.zig").contributions },
    .{ .group = .catalog, .contributions = &@import("host_catalog.zig").contributions },
    .{ .group = .child_gateway, .contributions = &.{@import("child_gateway.zig").contribution} },
    .{ .group = .extension, .contributions = &@import("extension_gateway.zig").contributions },
    .{ .group = .builtin, .contributions = &.{@import("builtin_tools.zig").contribution} },
    .{ .group = .terminal, .contributions = &@import("host_queries.zig").terminal_contributions },
    .{ .group = .fetch_url, .contributions = &@import("fetch_url.zig").contributions },
    .{ .group = .batch_output, .contributions = &.{@import("batch_output.zig").contribution} },
    .{ .group = .execution, .contributions = &@import("host_execution.zig").contributions },
    .{ .group = .lifecycle, .contributions = &@import("host_lifecycle.zig").contributions },
};
pub const all = blk: {
    var count: usize = 0;
    for (groups) |entry| count += entry.contributions.len;
    var result: [count]host.Contribution = undefined;
    var index: usize = 0;
    for (groups) |entry| for (entry.contributions) |contribution| {
        result[index] = contribution;
        index += 1;
    };
    break :blk result;
};
/// 直接按统一 `ToolDef` 写的宿主工具（M11 起）。注册表里是 `native` 来源；请求表仍以
/// `host.Contribution` 列出它们（同一份名称、描述、schema 与审批），调用经 AiHost 走统一流水线。
pub const native = [_]@import("tool_def.zig").ToolDef{@import("tab_context.zig").registered()};
pub const Buffer = [all.len + native.len]host.Contribution;
/// 原生宿主工具在请求表里的形状：只读的对话上下文查询。
pub fn nativeContribution(def: @import("tool_def.zig").ToolDef) host.Contribution {
    return .{ .authority = .conversation_context, .definition = .{ .id = def.name, .version = def.version, .description = def.description, .schema = def.input_schema, .max_argument_bytes = def.budget.max_argument_bytes, .validate = def.validate, .effect = def.effect, .approval_policy = def.approval } };
}
pub fn isNative(tool: []const u8) bool {
    for (native) |def| if (std.mem.eql(u8, def.name, tool)) return true;
    return false;
}

/// 每次请求的宿主工具筛选条件（T1 之前散在 AiHost.prepareHostCatalog 里）。
pub const Request = struct {
    queries_only: bool = false,
    /// 有请求期宿主权限且不是子任务时，才提供子任务网关。
    child_gateway: bool = false,
    extension: ?struct { skills: bool, servers: bool } = null,
    execution: bool = false,
    lifecycle: ?Lifecycle = null,
    pub const Lifecycle = struct { context: *anyopaque, available: *const fn (*anyopaque, []const u8) bool };
};

/// 从注册表快照筛出本次请求的宿主工具表，写进 `out`，返回条数。
pub fn select(snapshot: *const registry.Snapshot, request: Request, out: *Buffer) usize {
    var len: usize = 0;
    const append = struct {
        fn one(buffer: *Buffer, cursor: *usize, contribution: host.Contribution) void {
            buffer[cursor.*] = contribution;
            cursor.* += 1;
        }
    }.one;
    for (snapshot.hostGroup(.user_interaction)) |contribution| append(out, &len, contribution);
    for (snapshot.hostGroup(.queries)) |contribution| append(out, &len, contribution);
    for (snapshot.entries) |entry| if (entry.source == .native and entry.def.owner == .host and entry.def.target != .card_type) append(out, &len, nativeContribution(entry.def));
    for (snapshot.hostGroup(.catalog)) |contribution| {
        if (request.queries_only and @import("host_catalog.zig").isMutation(contribution.definition.id)) continue;
        append(out, &len, contribution);
    }
    if (request.child_gateway) for (snapshot.hostGroup(.child_gateway)) |contribution| append(out, &len, contribution);
    if (request.extension) |extension| for (snapshot.hostGroup(.extension)) |contribution| {
        const skill_tool = std.mem.eql(u8, contribution.definition.id, "host.skills");
        if (skill_tool and !extension.skills) continue;
        if (!skill_tool and (!extension.servers or request.queries_only)) continue;
        append(out, &len, contribution);
    };
    if (request.queries_only) return len;
    for (snapshot.hostGroup(.builtin)) |contribution| append(out, &len, contribution);
    for (snapshot.hostGroup(.terminal)) |contribution| append(out, &len, contribution);
    for (snapshot.hostGroup(.fetch_url)) |contribution| append(out, &len, contribution);
    for (snapshot.hostGroup(.batch_output)) |contribution| append(out, &len, contribution);
    if (request.execution) for (snapshot.hostGroup(.execution)) |contribution| append(out, &len, contribution);
    if (request.lifecycle) |lifecycle| for (snapshot.hostGroup(.lifecycle)) |contribution| {
        if (!lifecycle.available(lifecycle.context, contribution.definition.id)) continue;
        append(out, &len, contribution);
    };
    return len;
}
const std = @import("std");

test "AI group host catalog fits every contribution and builds a valid request table" {
    const tools = @import("plugin_tools.zig");
    const buffer: Buffer = all ++ .{nativeContribution(native[0])};
    var table = try tools.RequestTable.initWithHost(std.testing.allocator, .{ .owner = .{ .tab = 7 }, .content = .{ .group = 7 }, .members = .{} }, &.{}, &.{}, .{ .conversation_id = .{ .bytes = @splat(1) }, .task_id = .{ .bytes = @splat(2) }, .binding = .{ .tab = 7 }, .content = .{ .group = 7 }, .binding_revision = 2, .grant_revision = 1 }, &buffer);
    defer table.deinit();
    try std.testing.expect(table.lookup("host__run_uin_uterminal") != null);
    try std.testing.expect(table.lookup("host__close_usession") != null);
    try std.testing.expect(table.lookup("host__get_ucurrent_ucontext") != null);
    try std.testing.expectEqual(buffer.len, table.entries.len);
}
