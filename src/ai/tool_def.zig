//! 统一工具接口（PLUGIN_ARCH_PLAN 2.9）：一个 `ToolDef`、一套 schema 约定、
//! 一个一对一的 MCP 形状映射。一方内部不经过 MCP 序列化；`toMcpTool` /
//! `toMcpResult` 只是纯函数映射，用来证明形状一一对应，不连接任何外部服务。
//!
//! T1（本文件所在阶段）只做定义、注册与适配：现有三种定义（插件的
//! `ToolDefinition` + `ToolBinding`、宿主的 `host.Contribution`、遗留适配器的
//! `run_command` / `read_terminal` 等）经 `tool_registry.zig` 的适配器登记成
//! `ToolDef`，模型可见的名称、描述、schema 与审批逐字不变。
const std = @import("std");
const tools = @import("plugin_tools.zig");
const services = @import("../host/plugin_services.zig");

pub const Effect = tools.Effect;
/// 只读免审批 / 需审批 / 危险（沿用 `ApprovalPolicy` 的三个取值与拼写）。
pub const Approval = tools.ApprovalPolicy;
/// 结果约定：JSON 对象 / 纯文本 / JSON 对象加图片引用。
pub const OutputKind = enum { structured, text, structured_with_images };
/// 作用目标：整个对话 / 当前 tab / 某种卡片类型（`card_type` 为卡片类型名）。
pub const Target = union(enum) {
    global,
    tab,
    card_type: []const u8,
    pub fn eql(a: Target, b: Target) bool {
        if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
        return switch (a) {
            .card_type => |name| std.mem.eql(u8, name, b.card_type),
            else => true,
        };
    }
};
pub const Truncate = enum { tail, head, reject };
pub const Budget = struct {
    max_argument_bytes: usize = 64 * 1024,
    max_result_bytes: usize = 8192,
    truncate: Truncate = .tail,
};
/// 4.3 的权限词表在 PL1 定稿；T1 只落地工具相关的一项。插件工具必须带着
/// 所属插件的 `ai_integration`，宿主工具为 null。
pub const Permission = struct {
    plugin_id: []const u8,
    name: Name = .ai_integration,
    pub const Name = enum { ai_integration };
};
/// 工具归属：宿主模块或某个插件。插件工具的命名空间不得是 `host`。
pub const Owner = union(enum) {
    host,
    plugin: []const u8,
};

/// 原生 handler 的入参与出参。只有这一项由各卡片 / 插件 / 宿主模块实现。
pub const Call = struct {
    name: []const u8,
    arguments: std.json.Value,
    arguments_json: []const u8,
    arguments_hash: [32]u8,
    /// 作用域步骤解析出的目标（卡片 / 会话引用）；global 工具为 null。
    target: ?[]const u8 = null,
    /// 请求期环境（流水线 `Env.context`）：宿主在调用时提供，handler 只经它取运行期数据。
    env: ?*anyopaque = null,
};
pub const Content = union(enum) { text: []const u8, structured: []const u8 };
pub const Output = struct {
    status: tools.Status = .succeeded,
    /// 由 handler 用调用方 allocator 分配；流水线负责释放。
    content: []const Content = &.{},
    pub fn deinit(self: *Output, allocator: std.mem.Allocator) void {
        for (self.content) |item| switch (item) {
            .text, .structured => |bytes| allocator.free(bytes),
        };
        allocator.free(self.content);
        self.* = undefined;
    }
};
pub const NativeHandler = struct {
    context: *anyopaque,
    call: *const fn (*anyopaque, Call, std.mem.Allocator) anyerror!Output,
};
/// T1 的三种 handler 形态。`native` 是目标形态（M11 起的新工具直接写它）；
/// 另外两种是适配器保留的现有分发入口，T2 迁移后删除。
pub const Handler = union(enum) {
    native: NativeHandler,
    /// 插件 / 遗留工具：每个目标会话各自的 `ToolBinding.handler`，上下文是
    /// 请求期捕获的成员上下文。
    session: *const fn (*anyopaque, tools.Invocation, std.mem.Allocator) anyerror!tools.ToolResult,
    /// 宿主工具：经 AiHost 的宿主网关（`queryHost` / `dispatchHostWorker`）按工具名分发。
    host_gateway,
};

pub const ToolDef = struct {
    /// 带命名空间：host.* / terminal.* / file.* / bmc_ikvm.* / <plugin_id>.*
    name: []const u8,
    version: u32 = 1,
    /// 写给模型看：做什么、何时用、返回什么、常见错误怎么办。
    description: []const u8,
    /// JSON schema，受限子集（见 `checkConventions` 与 plugin_tools 的校验器局限）。
    input_schema: []const u8,
    output: OutputKind = .structured,
    handler: Handler,
    owner: Owner = .host,
    permission: ?Permission = null,
    approval: Approval = .read_only,
    effect: Effect = .read_state,
    target: Target = .global,
    required_services: []const services.Requirement = &.{},
    budget: Budget = .{},
    /// 跨字段约束（子集表达不了的，例如 cursor 与范围字段互斥）。
    validate: ?*const fn (std.json.Value) anyerror!void = null,
    /// 审批步骤里的细粒度策略钩子（遗留 `evaluate_policy`，例如 shellPolicy）。
    /// 返回 true 表示本次调用需要用户确认。
    approval_hook: ?*const fn (std.json.Value, tools.Policy, bool) anyerror!bool = null,

    /// 与提供方之间互转用的安全名（`encodeName`，'.' → '__'，'_' → '_u'）。
    pub fn wireName(self: ToolDef, buffer: *[64]u8) ![]const u8 {
        return tools.encodeName(buffer, self.name);
    }
    /// 模型可见部分与审批语义是否逐项相同（同名工具跨提供方共享时必须成立）。
    pub fn sameContract(a: ToolDef, b: ToolDef) bool {
        if (!std.mem.eql(u8, a.name, b.name) or a.version != b.version or !std.mem.eql(u8, a.description, b.description) or !std.mem.eql(u8, a.input_schema, b.input_schema)) return false;
        if (a.output != b.output or a.approval != b.approval or a.effect != b.effect or a.validate != b.validate or a.approval_hook != b.approval_hook) return false;
        if (a.budget.max_argument_bytes != b.budget.max_argument_bytes or a.budget.max_result_bytes != b.budget.max_result_bytes or a.budget.truncate != b.budget.truncate) return false;
        return true;
    }
};

// ─── 统一错误结构 ────────────────────────────────────────────────────────

/// 共享错误码。`hint` 告诉模型下一步可以调用什么。
pub const ErrorCode = enum {
    InvalidArguments,
    ToolNotInRequest,
    TargetNotAuthorized,
    CardNotInTab,
    SnapshotChanged,
    RangeUnavailable,
    Unsupported,
    PermissionDenied,
    ApprovalRequired,
    ApprovalRejected,
    ResultTooLarge,
    HandlerFailed,

    pub fn retryable(self: ErrorCode) bool {
        return switch (self) {
            .SnapshotChanged, .ApprovalRequired => true,
            else => false,
        };
    }
};
pub const ErrorBody = struct {
    code: ErrorCode,
    message: []const u8,
    retryable: bool,
    hint: ?[]const u8 = null,
    pub fn init(code: ErrorCode, message: []const u8, hint: ?[]const u8) ErrorBody {
        return .{ .code = code, .message = message, .retryable = code.retryable(), .hint = hint };
    }
    pub fn jsonStringify(self: ErrorBody, writer: *std.json.Stringify) !void {
        try writer.beginObject();
        try writer.objectField("code");
        try writer.write(@tagName(self.code));
        try writer.objectField("message");
        try writer.write(self.message);
        try writer.objectField("retryable");
        try writer.write(self.retryable);
        try writer.objectField("hint");
        try writer.write(self.hint);
        try writer.endObject();
    }
};

// ─── schema 约定（只写一次，注册期强制） ─────────────────────────────────

/// 保留参数名与它们的固定形状（与 `host_terminal_queries.zig` 的共享片段一致）。
/// 比较时忽略 description / default / title。
pub const reserved_parameters = [_]struct { name: []const u8, schema: []const u8 }{
    .{ .name = "card_ref", .schema = "{\"type\":\"string\",\"minLength\":1,\"maxLength\":128}" },
    .{ .name = "max_bytes", .schema = "{\"type\":\"integer\",\"minimum\":1,\"maximum\":65536}" },
    .{ .name = "max_lines", .schema = "{\"type\":\"integer\",\"minimum\":1,\"maximum\":500}" },
    .{ .name = "limit", .schema = "{\"type\":\"integer\",\"minimum\":1,\"maximum\":200}" },
    .{ .name = "cursor", .schema = "{\"type\":\"string\",\"minLength\":1,\"maxLength\":128}" },
    .{ .name = "start_ms", .schema = "{\"type\":\"integer\",\"minimum\":0}" },
    .{ .name = "end_ms", .schema = "{\"type\":\"integer\",\"minimum\":0}" },
    .{ .name = "time_basis", .schema = "{\"type\":\"string\",\"enum\":[\"client_receive_absolute_ms\",\"cast_first_event_elapsed_ms\"]}" },
};
/// 只出现在响应里的保留名：请求 schema 不得声明。
pub const reserved_output_parameters = [_][]const u8{"next_cursor"};
/// 多目标数组（`card_refs`）的上限。
pub const max_target_refs = 16;

pub const Violation = enum {
    /// 名称不是 `命名空间.动词_对象`（小写、下划线、至少一个命名空间段）。
    name_format,
    /// 插件工具使用了宿主保留的 `host` 命名空间。
    reserved_namespace,
    /// 参数名不是小写加下划线。
    parameter_name,
    /// 保留参数名的类型或取值范围与共享片段不一致。
    reserved_parameter_shape,
    /// 请求 schema 声明了只用于响应的保留名（next_cursor）。
    reserved_output_parameter,
    /// 顶层不是 `{"type":"object", "additionalProperties": false}`。
    top_level_object,
    /// `card_refs` 不是上限不超过 16 的字符串数组。
    target_array,
    /// schema 超出受限子集（validateDefinition 失败）。
    schema_subset,
};
pub const Violations = std.EnumSet(Violation);

/// 返回全部违反的约定（空集表示合规）。schema 解析失败记为 `schema_subset`。
pub fn conventionViolations(def: ToolDef) Violations {
    var out: Violations = .empty;
    if (!validName(def.name)) out.insert(.name_format);
    if (def.owner == .plugin and std.mem.startsWith(u8, def.name, "host.")) out.insert(.reserved_namespace);
    tools.validateDefinition(.{ .id = def.name, .version = def.version, .description = def.description, .schema = def.input_schema, .max_argument_bytes = def.budget.max_argument_bytes }) catch {
        out.insert(.schema_subset);
        return out;
    };
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const parsed = std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(), def.input_schema, .{}) catch {
        out.insert(.schema_subset);
        return out;
    };
    const additional = parsed.object.get("additionalProperties");
    if (additional == null or additional.? != .bool or additional.?.bool) out.insert(.top_level_object);
    const properties = (parsed.object.get("properties") orelse return out).object;
    var iterator = properties.iterator();
    while (iterator.next()) |field| {
        const name = field.key_ptr.*;
        if (!validIdentifier(name)) out.insert(.parameter_name);
        for (reserved_output_parameters) |reserved| if (std.mem.eql(u8, name, reserved)) out.insert(.reserved_output_parameter);
        for (reserved_parameters) |reserved| if (std.mem.eql(u8, name, reserved.name)) {
            const expected = std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(), reserved.schema, .{}) catch unreachable;
            if (!sameShape(expected, field.value_ptr.*)) out.insert(.reserved_parameter_shape);
        };
        if (std.mem.eql(u8, name, "card_refs")) {
            const value = field.value_ptr.*.object;
            const kind = value.get("type");
            const max = value.get("maxItems");
            const items = value.get("items");
            const ok = kind != null and kind.? == .string and std.mem.eql(u8, kind.?.string, "array") and max != null and max.? == .integer and max.?.integer <= max_target_refs and items != null and sameShape(std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(), reserved_parameters[0].schema, .{}) catch unreachable, items.?);
            if (!ok) out.insert(.target_array);
        }
    }
    return out;
}

/// 注册期强制：任何一条不合规都拒绝。只用于直接按 `ToolDef` 写的工具；
/// 适配器登记的现有工具改为记录约定债务（见 tool_registry.zig）。
pub fn checkConventions(def: ToolDef) !void {
    const violations = conventionViolations(def);
    if (violations.count() == 0) return;
    if (violations.contains(.schema_subset)) return error.UnsupportedToolSchema;
    if (violations.contains(.name_format) or violations.contains(.reserved_namespace)) return error.ToolNameConvention;
    return error.ToolSchemaConvention;
}

fn validIdentifier(text: []const u8) bool {
    if (text.len == 0 or !std.ascii.isLower(text[0])) return false;
    for (text) |byte| if (!std.ascii.isLower(byte) and !std.ascii.isDigit(byte) and byte != '_') return false;
    return text[text.len - 1] != '_' and std.mem.indexOf(u8, text, "__") == null;
}
fn validName(name: []const u8) bool {
    var segments = std.mem.splitScalar(u8, name, '.');
    var count: usize = 0;
    while (segments.next()) |segment| {
        if (!validIdentifier(segment)) return false;
        count += 1;
    }
    return count >= 2;
}
/// 只比较约束关键字；description / default / title 不影响形状。
fn sameShape(expected: std.json.Value, actual: std.json.Value) bool {
    if (expected != .object or actual != .object) return false;
    const keys = [_][]const u8{ "type", "minimum", "maximum", "minLength", "maxLength", "enum", "items", "minItems", "maxItems" };
    for (keys) |key| {
        const left = expected.object.get(key);
        const right = actual.object.get(key);
        if ((left == null) != (right == null)) return false;
        if (left) |value| if (!jsonEqual(value, right.?)) return false;
    }
    return true;
}
fn jsonEqual(a: std.json.Value, b: std.json.Value) bool {
    if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
    return switch (a) {
        .null => true,
        .bool => |v| v == b.bool,
        .integer => |v| v == b.integer,
        .float => |v| v == b.float,
        .number_string, .string => |v| std.mem.eql(u8, v, switch (b) {
            .number_string, .string => |w| w,
            else => unreachable,
        }),
        .array => |items| items.items.len == b.array.items.len and for (items.items, b.array.items) |x, y| {
            if (!jsonEqual(x, y)) break false;
        } else true,
        .object => sameShape(a, b),
    };
}

// ─── 导出为 MCP tool（纯函数映射，不接外部服务） ─────────────────────────

/// `name` → 安全名；`description` 原样；`input_schema` → `inputSchema`（受限子集
/// 本身是合法 JSON Schema）；`approval` / `effect` → `annotations`。
pub fn toMcpTool(allocator: std.mem.Allocator, def: ToolDef) ![]u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const schema = try std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(), def.input_schema, .{});
    var name: [64]u8 = undefined;
    return std.json.Stringify.valueAlloc(allocator, .{
        .name = try def.wireName(&name),
        .description = def.description,
        .inputSchema = schema,
        .annotations = mcpAnnotations(def),
    }, .{});
}
/// 字段名即 MCP 规范里的拼写。
pub const McpAnnotations = struct { readOnlyHint: bool, destructiveHint: bool };
pub fn mcpAnnotations(def: ToolDef) McpAnnotations {
    return .{
        .readOnlyHint = def.approval == .read_only and (def.effect == .read_state or def.effect == .observe_image),
        .destructiveHint = def.approval == .always_confirm or def.effect == .resource_write,
    };
}
/// 结构化内容 → `structuredContent`（取第一个结构化块），全部内容 → `content`
/// 文本块；错误结构 → `isError` 加错误内容。
pub const McpResultInput = union(enum) { ok: Output, err: ErrorBody };
pub fn toMcpResult(allocator: std.mem.Allocator, output: McpResultInput) ![]u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const TextBlock = struct { type: []const u8 = "text", text: []const u8 };
    switch (output) {
        .err => |body| {
            const text = try std.json.Stringify.valueAlloc(a, body, .{});
            return std.json.Stringify.valueAlloc(allocator, .{ .content = &[_]TextBlock{.{ .text = text }}, .structuredContent = body, .isError = true }, .{});
        },
        .ok => |value| {
            const blocks = try a.alloc(TextBlock, value.content.len);
            var structured: ?std.json.Value = null;
            for (value.content, blocks) |item, *block| switch (item) {
                .text => |text| block.* = .{ .text = text },
                .structured => |text| {
                    block.* = .{ .text = text };
                    if (structured == null) structured = try std.json.parseFromSliceLeaky(std.json.Value, a, text, .{});
                },
            };
            return std.json.Stringify.valueAlloc(allocator, .{ .content = blocks, .structuredContent = structured, .isError = value.status != .succeeded }, .{ .emit_null_optional_fields = false });
        },
    }
}

// ─── 单测 ────────────────────────────────────────────────────────────────

fn testHandler(_: *anyopaque, _: Call, _: std.mem.Allocator) anyerror!Output {
    return .{};
}
var test_context: u8 = 0;
fn sample(name: []const u8, schema: []const u8) ToolDef {
    return .{ .name = name, .description = "d", .input_schema = schema, .handler = .{ .native = .{ .context = &test_context, .call = testHandler } } };
}

test "tooldef conventions accept a compliant tool and reject each violated rule" {
    const ok = "{\"type\":\"object\",\"additionalProperties\":false,\"properties\":{\"card_ref\":{\"type\":\"string\",\"minLength\":1,\"maxLength\":128,\"description\":\"x\"},\"max_bytes\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":65536},\"cursor\":{\"type\":\"string\",\"minLength\":1,\"maxLength\":128},\"card_refs\":{\"type\":\"array\",\"maxItems\":16,\"items\":{\"type\":\"string\",\"minLength\":1,\"maxLength\":128}}},\"required\":[\"card_ref\"]}";
    try checkConventions(sample("terminal.read_text", ok));
    try checkConventions(sample("host.tab_context", ok));
    try std.testing.expect(conventionViolations(sample("terminal.read", ok)).count() == 0);
    const cases = .{
        .{ "read_terminal", ok, Violation.name_format },
        .{ "Host.Get", ok, Violation.name_format },
        .{ "host..x", ok, Violation.name_format },
        .{ "host.x", "{\"type\":\"object\",\"properties\":{}}", Violation.top_level_object },
        .{ "host.x", "{\"type\":\"object\",\"additionalProperties\":true,\"properties\":{}}", Violation.top_level_object },
        .{ "host.x", "{\"type\":\"object\",\"additionalProperties\":false,\"properties\":{\"maxBytes\":{\"type\":\"integer\"}}}", Violation.parameter_name },
        .{ "host.x", "{\"type\":\"object\",\"additionalProperties\":false,\"properties\":{\"max_bytes\":{\"type\":\"integer\",\"minimum\":4,\"maximum\":65536}}}", Violation.reserved_parameter_shape },
        .{ "host.x", "{\"type\":\"object\",\"additionalProperties\":false,\"properties\":{\"limit\":{\"type\":\"string\"}}}", Violation.reserved_parameter_shape },
        .{ "host.x", "{\"type\":\"object\",\"additionalProperties\":false,\"properties\":{\"next_cursor\":{\"type\":\"string\"}}}", Violation.reserved_output_parameter },
        .{ "host.x", "{\"type\":\"object\",\"additionalProperties\":false,\"properties\":{\"card_refs\":{\"type\":\"array\",\"maxItems\":17,\"items\":{\"type\":\"string\",\"minLength\":1,\"maxLength\":128}}}}", Violation.target_array },
        .{ "host.x", "{\"type\":\"object\",\"additionalProperties\":false,\"properties\":{\"a\":{\"oneOf\":[]}}}", Violation.schema_subset },
        .{ "host.x", "{\"type\":\"object\",\"additionalProperties\":false,\"properties\":{\"a\":{\"$ref\":\"#/x\"}}}", Violation.schema_subset },
    };
    inline for (cases) |case| {
        const violations = conventionViolations(sample(case[0], case[1]));
        try std.testing.expect(violations.contains(case[2]));
        try std.testing.expect(std.meta.isError(checkConventions(sample(case[0], case[1]))));
    }
    var plugin = sample("host.read_x", ok);
    plugin.owner = .{ .plugin = "bmc_ikvm" };
    try std.testing.expect(conventionViolations(plugin).contains(.reserved_namespace));
}

test "tooldef error body has the fixed code message retryable hint shape" {
    const a = std.testing.allocator;
    const body = try std.json.Stringify.valueAlloc(a, ErrorBody.init(.SnapshotChanged, "source revision changed", "call host.read_terminal again"), .{});
    defer a.free(body);
    try std.testing.expectEqualStrings("{\"code\":\"SnapshotChanged\",\"message\":\"source revision changed\",\"retryable\":true,\"hint\":\"call host.read_terminal again\"}", body);
    const plain = try std.json.Stringify.valueAlloc(a, ErrorBody.init(.InvalidArguments, "bad", null), .{});
    defer a.free(plain);
    try std.testing.expectEqualStrings("{\"code\":\"InvalidArguments\",\"message\":\"bad\",\"retryable\":false,\"hint\":null}", plain);
}

test "tooldef export to MCP tool maps every field one to one" {
    const a = std.testing.allocator;
    const schema = "{\"type\":\"object\",\"additionalProperties\":false,\"properties\":{\"card_ref\":{\"type\":\"string\",\"minLength\":1,\"maxLength\":128}},\"required\":[\"card_ref\"]}";
    var def = sample("host.tab_context", schema);
    def.description = "Read a bounded tab overview.";
    const exported = try toMcpTool(a, def);
    defer a.free(exported);
    try std.testing.expectEqualStrings("{\"name\":\"host__tab_ucontext\",\"description\":\"Read a bounded tab overview.\",\"inputSchema\":" ++ schema ++ ",\"annotations\":{\"readOnlyHint\":true,\"destructiveHint\":false}}", exported);
    // 反向：MCP 名称经 decodeName 回到同一个 ToolDef 名称，inputSchema 原样可解析。
    const parsed = try std.json.parseFromSlice(std.json.Value, a, exported, .{});
    defer parsed.deinit();
    var back: [64]u8 = undefined;
    try std.testing.expectEqualStrings(def.name, try tools.decodeName(&back, parsed.value.object.get("name").?.string));
    const round = try std.json.Stringify.valueAlloc(a, parsed.value.object.get("inputSchema").?, .{});
    defer a.free(round);
    try std.testing.expectEqualStrings(schema, round);

    def.approval = .confirm;
    def.effect = .resource_write;
    const write = mcpAnnotations(def);
    try std.testing.expect(!write.readOnlyHint and write.destructiveHint);
    def.approval = .always_confirm;
    def.effect = .remote_input;
    try std.testing.expect(mcpAnnotations(def).destructiveHint);
    def.approval = .confirm;
    def.effect = .remote_input;
    const input = mcpAnnotations(def);
    try std.testing.expect(!input.readOnlyHint and !input.destructiveHint);
}

test "tooldef export to MCP result maps structured content text and errors" {
    const a = std.testing.allocator;
    const ok = try toMcpResult(a, .{ .ok = .{ .content = &.{ .{ .structured = "{\"n\":1}" }, .{ .text = "tail" } } } });
    defer a.free(ok);
    try std.testing.expectEqualStrings("{\"content\":[{\"type\":\"text\",\"text\":\"{\\\"n\\\":1}\"},{\"type\":\"text\",\"text\":\"tail\"}],\"structuredContent\":{\"n\":1},\"isError\":false}", ok);
    const failed = try toMcpResult(a, .{ .err = ErrorBody.init(.CardNotInTab, "card is not in this tab", "call host.tab_context") });
    defer a.free(failed);
    const parsed = try std.json.parseFromSlice(std.json.Value, a, failed, .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.value.object.get("isError").?.bool);
    try std.testing.expectEqualStrings("CardNotInTab", parsed.value.object.get("structuredContent").?.object.get("code").?.string);
}
