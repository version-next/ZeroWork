//! 统一工具注册表的单元测试（只依赖 core）。组合级等价性见 src/tests_tool_registry.zig。
const std = @import("std");
const T = std.testing;
const registry = @import("../tool_registry.zig");
const tool_def = @import("../tool_def.zig");
const tools = @import("../plugin_tools.zig");
const host = @import("../host_tools.zig");
const services = @import("../../host/plugin_services.zig");

const Fake = struct {
    var context: u8 = 0;
    fn native(_: *anyopaque, _: tool_def.Call, _: std.mem.Allocator) anyerror!tool_def.Output {
        return .{};
    }
    fn session(_: *anyopaque, _: tools.Invocation, _: std.mem.Allocator) anyerror!tools.ToolResult {
        return error.Unexpected;
    }
    fn policy(_: std.json.Value, _: tools.Policy, _: bool) anyerror!bool {
        return true;
    }
};
const strict_schema = "{\"type\":\"object\",\"additionalProperties\":false,\"properties\":{\"card_ref\":{\"type\":\"string\",\"minLength\":1,\"maxLength\":128}}}";
const legacy_schema = "{\"type\":\"object\",\"additionalProperties\":false,\"properties\":{\"session_ids\":{\"type\":\"array\",\"minItems\":1,\"maxItems\":16,\"items\":{\"type\":\"integer\",\"minimum\":1}}},\"required\":[\"session_ids\"]}";
const Service = struct { x: u8 };
const service = services.Definition.of(Service, .{ .name = "probe.svc" });

fn native(name: []const u8, target: tool_def.Target) tool_def.ToolDef {
    return .{ .name = name, .description = "d", .input_schema = strict_schema, .handler = .{ .native = .{ .context = &Fake.context, .call = Fake.native } }, .target = target };
}

test "tooldef registry publishes an immutable snapshot after both validation phases" {
    var builder = registry.Builder.init(T.allocator);
    defer builder.deinit();
    var arena = std.heap.ArenaAllocator.init(T.allocator);
    defer arena.deinit();
    try builder.register(native("host.tab_context", .tab));
    try builder.register(native("terminal.read_text", .{ .card_type = "terminal" }));
    const contributions = [_]host.Contribution{.{ .authority = .conversation_context, .definition = .{ .id = "host.get_session", .description = "g", .schema = strict_schema } }};
    try builder.registerHost(.queries, &contributions);
    const definitions = [_]tools.ToolDefinition{
        .{ .id = "probe.observe", .description = "o", .schema = legacy_schema, .effect = .observe_image, .required_services = &.{service} },
        .{ .id = "run_command", .description = "r", .schema = legacy_schema, .approval_policy = .confirm, .effect = .resource_write, .evaluate_policy = Fake.policy },
    };
    const bindings = [_]tools.ToolBinding{
        .{ .plugin_id = "probe", .definition_id = "probe.observe", .handler = Fake.session },
        .{ .plugin_id = "probe", .definition_id = "run_command", .handler = Fake.session, .required_services = &.{service} },
    };
    try builder.registerPlugin("probe", "probe_canvas", &definitions, &bindings, &.{service});
    // 第二个插件共享同一份 run_command 定义（local / ssh 的情形）。
    const other_bindings = [_]tools.ToolBinding{.{ .plugin_id = "other", .definition_id = "run_command", .handler = Fake.session }};
    try builder.registerPlugin("other", "terminal", &definitions, &other_bindings, &.{service});
    const snapshot = try builder.publish(arena.allocator());

    try T.expectEqual(@as(usize, 6), snapshot.entries.len);
    const observe = snapshot.find("probe.observe").?;
    try T.expectEqual(registry.Source.plugin, observe.source);
    try T.expectEqual(tool_def.OutputKind.structured_with_images, observe.def.output);
    try T.expect(observe.def.target.eql(.{ .card_type = "probe_canvas" }));
    try T.expectEqualStrings("probe", observe.def.permission.?.plugin_id);
    const run = snapshot.pluginEntries("probe")[1];
    try T.expectEqual(registry.Source.legacy, run.source);
    try T.expect(run.def.approval_hook == Fake.policy);
    try T.expectEqual(tool_def.Approval.confirm, run.def.approval);
    // 定义与绑定的所需服务合并。
    try T.expectEqual(@as(usize, 1), run.def.required_services.len);
    try T.expectEqual(@as(usize, 2), snapshot.pluginBindings("probe").len);
    try T.expectEqual(@as(usize, 1), snapshot.pluginEntries("other").len);
    try T.expectEqual(@as(usize, 1), snapshot.hostGroup(.queries).len);
    try T.expectEqual(@as(usize, 0), snapshot.hostGroup(.lifecycle).len);
    try T.expect(snapshot.find("host.get_session").?.def.handler == .host_gateway);
    try T.expect(snapshot.find("host.get_session").?.def.target == .tab);
    // 现有工具记录约定债务，不拒绝。
    try T.expect(run.debt.contains(.name_format));
    try T.expect(observe.debt.count() == 0 or !observe.debt.contains(.name_format));

    // 按作用域筛：tab 内只有 terminal 卡片时看不到 probe_canvas 的工具。
    const terminal_only = try snapshot.select(T.allocator, .{ .card_types = &.{"terminal"} });
    defer T.allocator.free(terminal_only);
    var names: std.ArrayList(u8) = .empty;
    defer names.deinit(T.allocator);
    for (terminal_only) |entry| {
        try names.appendSlice(T.allocator, entry.def.name);
        try names.append(T.allocator, ' ');
    }
    try T.expectEqualStrings("host.tab_context terminal.read_text host.get_session run_command ", names.items);
    const probe_only = try snapshot.select(T.allocator, .{ .card_types = &.{"probe_canvas"}, .plugin = "probe", .host = false, .global = false, .tab = false });
    defer T.allocator.free(probe_only);
    try T.expectEqual(@as(usize, 2), probe_only.len);
}

test "tooldef registry rejects invalid registrations in phase one" {
    var builder = registry.Builder.init(T.allocator);
    defer builder.deinit();
    // 原生工具严格执行约定。
    try T.expectError(error.ToolNameConvention, builder.register(native("read_terminal", .global)));
    var loose = native("host.loose", .global);
    loose.input_schema = "{\"type\":\"object\",\"properties\":{}}";
    try T.expectError(error.ToolSchemaConvention, builder.register(loose));
    var unsupported = native("host.any", .global);
    unsupported.input_schema = "{\"type\":\"object\",\"additionalProperties\":false,\"properties\":{\"a\":{\"type\":\"string\",\"anyOf\":[]}}}";
    try T.expectError(error.UnsupportedToolSchema, builder.register(unsupported));
    var adapted = native("host.adapted", .global);
    adapted.handler = .host_gateway;
    try T.expectError(error.InvalidToolHandler, builder.register(adapted));
    var plugin = native("probe.read_state", .{ .card_type = "probe_canvas" });
    plugin.owner = .{ .plugin = "probe" };
    try T.expectError(error.ToolPermissionUndeclared, builder.register(plugin));
    plugin.permission = .{ .plugin_id = "probe" };
    try builder.register(plugin);
    var empty_card = native("host.bad_target", .{ .card_type = "" });
    empty_card.target = .{ .card_type = "" };
    try T.expectError(error.InvalidToolTarget, builder.register(empty_card));
    // 宿主适配器：只接受 host.* 且不是会话目标的贡献。
    try T.expectError(error.InvalidHostAuthority, builder.registerHost(.queries, &.{.{ .authority = .session_targets, .definition = .{ .id = "host.x", .schema = strict_schema } }}));
    try T.expectError(error.InvalidHostAuthority, builder.registerHost(.catalog, &.{.{ .authority = .conversation_context, .definition = .{ .id = "probe.x", .schema = strict_schema } }}));
    try builder.registerHost(.terminal, &.{});
    try T.expectError(error.DuplicateHostGroup, builder.registerHost(.terminal, &.{}));
    // 插件适配器：沿用 validateBindings 的规则。
    const definitions = [_]tools.ToolDefinition{.{ .id = "probe.observe", .schema = legacy_schema, .required_services = &.{service} }};
    try T.expectError(error.ToolServiceUndeclared, builder.registerPlugin("probe", "c", &definitions, &.{.{ .plugin_id = "probe", .definition_id = "probe.observe", .handler = Fake.session }}, &.{}));
    try T.expectError(error.ReservedToolNamespace, builder.registerPlugin("probe", "c", &definitions, &.{.{ .plugin_id = "probe", .definition_id = "host.observe", .handler = Fake.session }}, &.{service}));
    try T.expectError(error.UnknownToolDefinition, builder.registerPlugin("probe", "c", &definitions, &.{.{ .plugin_id = "probe", .definition_id = "probe.missing", .handler = Fake.session }}, &.{service}));
}

test "tooldef registry rejects conflicts in phase two and publishes nothing" {
    var arena = std.heap.ArenaAllocator.init(T.allocator);
    defer arena.deinit();
    {
        var builder = registry.Builder.init(T.allocator);
        defer builder.deinit();
        try builder.register(native("host.tab_context", .tab));
        try builder.registerHost(.queries, &.{.{ .authority = .conversation_context, .definition = .{ .id = "host.tab_context", .schema = strict_schema } }});
        try T.expectError(error.DuplicateTool, builder.publish(arena.allocator()));
    }
    {
        // 同名插件工具的定义必须逐项相同。
        var builder = registry.Builder.init(T.allocator);
        defer builder.deinit();
        try builder.registerPlugin("a", "terminal", &.{.{ .id = "x.read_state", .description = "one", .schema = legacy_schema }}, &.{.{ .plugin_id = "a", .definition_id = "x.read_state", .handler = Fake.session }}, &.{});
        try builder.registerPlugin("b", "terminal", &.{.{ .id = "x.read_state", .description = "two", .schema = legacy_schema }}, &.{.{ .plugin_id = "b", .definition_id = "x.read_state", .handler = Fake.session }}, &.{});
        try T.expectError(error.ToolDefinitionConflict, builder.publish(arena.allocator()));
    }
    {
        try T.expectError(error.DuplicatePlugin, blk: {
            var builder = registry.Builder.init(T.allocator);
            defer builder.deinit();
            try builder.registerPlugin("a", "terminal", &.{}, &.{}, &.{});
            break :blk builder.registerPlugin("a", "terminal", &.{}, &.{}, &.{});
        });
    }
}
