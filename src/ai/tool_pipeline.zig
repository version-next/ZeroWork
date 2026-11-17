//! 统一调用流水线（PLUGIN_ARCH_PLAN 2.9 第 2 条）：
//! 解析 → schema 校验 → 作用域与权限 → 审批 → handler → 结果规范化 →
//! 脱敏与截断 → 审计记录 → 返回。各工具只写 handler。
//!
//! T1 的接线范围：
//! - 第 1、2 步（`parseArguments`）是所有来源共用的唯一实现，请求表
//!   `RequestTable.parse` 直接调用它，插件、遗留与宿主工具都经过这里。
//! - 第 3–9 步对 `native` handler 由 `invoke` 完整执行；适配器登记的现有工具
//!   仍由原有路径执行这些步骤（插件 / 遗留：`plugin_tools.Runtime.execute`；
//!   宿主：AiHost 的宿主网关），以保证行为不变。T2 把它们改为直接写 `ToolDef`
//!   后，统一由 `invoke` 执行。
//! - 脱敏：今天没有针对工具结果的统一脱敏规则（`assembler.zig` 的
//!   `redact_identity` 只作用于会话上下文组装），因此这里是一个钩子，默认不改写。
const std = @import("std");
const tool_def = @import("tool_def.zig");
const tools = @import("plugin_tools.zig");

pub const Stage = enum { parse, schema, scope, approval, dispatch, normalize, redact_truncate, audit, respond };

/// 第 1、2 步：参数大小上限、JSON 解析、必须是对象、按受限子集 schema 校验、
/// 跨字段 `validate` 钩子。所有工具来源共用（`RequestTable.parse` 调用它）。
/// 局限：校验器不支持 oneOf / anyOf / allOf、$ref、pattern、format；字段之间的
/// 约束放在 `validate` 钩子里。
pub fn parseArguments(allocator: std.mem.Allocator, schema_text: []const u8, max_argument_bytes: usize, validator: ?*const fn (std.json.Value) anyerror!void, arguments: []const u8) !std.json.Parsed(std.json.Value) {
    if (arguments.len > max_argument_bytes) return error.InvalidToolArguments;
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, arguments, .{ .allocate = .alloc_always });
    errdefer parsed.deinit();
    if (parsed.value != .object) return error.InvalidToolArguments;
    const schema = try std.json.parseFromSlice(std.json.Value, allocator, schema_text, .{});
    defer schema.deinit();
    try tools.validateArguments(schema.value, parsed.value);
    if (validator) |check| try check(parsed.value);
    return parsed;
}

/// 字段借用自本次调用，只在审计回调期间有效；需要保留时由回调自行复制。
pub const AuditRecord = struct {
    tool: []const u8,
    version: u32,
    arguments_hash: [32]u8,
    target: ?[]const u8,
    /// not_required / approved / rejected / not_reached
    approval: []const u8,
    /// 工具状态（succeeded 等）或错误码。
    outcome: []const u8,
};
pub const Env = struct {
    context: *anyopaque,
    /// 第 3 步：目标属于本次冻结的作用域、卡片类型匹配、所需服务可用、权限已声明。
    /// 返回解析出的目标引用（global 工具可返回 null）。
    scope: *const fn (*anyopaque, *const tool_def.ToolDef, std.json.Value) anyerror!?[]const u8,
    policy: tools.Policy = .{},
    grouped: bool = false,
    /// 第 3 步失败时工具给出的可操作提示（例如哪张卡片不支持哪个参数、哪些卡片支持）；
    /// 非 null 时覆盖按错误码给出的默认提示。
    scope_hint: ?*const fn (*anyopaque) ?[]const u8 = null,
    /// 第 4 步：需要审批时询问用户；返回 true 表示批准。null 表示没有审批通道。
    approve: ?*const fn (*anyopaque, *const tool_def.ToolDef, tool_def.Call) anyerror!bool = null,
    /// 第 7 步：脱敏钩子，返回新分配的文本；null 表示不改写。
    redact: ?*const fn (*anyopaque, []const u8, std.mem.Allocator) anyerror![]u8 = null,
    /// 第 8 步：审计与执行记录（`audit.Log` 适配见 `auditLogSink`）。
    audit: ?*const fn (*anyopaque, AuditRecord) void = null,
    /// 测试与诊断：每进入一步回调一次。
    trace: ?*const fn (*anyopaque, Stage) void = null,
};
pub const Response = struct {
    status: tools.Status,
    /// 规范化后返回给模型的 JSON：成功时 `{status, content, truncated}`，
    /// 失败时 `{status, error: {code, message, retryable, hint}}`。
    body: []u8,
    truncated: bool = false,
    err: ?tool_def.ErrorBody = null,
    pub fn deinit(self: *Response, allocator: std.mem.Allocator) void {
        allocator.free(self.body);
        self.* = undefined;
    }
};

/// 是否需要审批：与 `plugin_tools.callNeedsApproval` 同一规则（效果开关、
/// 自动模式 / 完全控制豁免、细粒度钩子）。
pub fn needsApproval(def: *const tool_def.ToolDef, arguments: std.json.Value, policy: tools.Policy, grouped: bool) !bool {
    const basic = try tools.needsApproval(.{ .id = def.name, .schema = def.input_schema, .effect = def.effect, .approval_policy = def.approval }, policy);
    if (def.approval_hook) |evaluate| {
        var effective = policy;
        if (policy.full_control) effective.engine.mode = .auto;
        return evaluate(arguments, effective, grouped);
    }
    return basic;
}

/// 对 `native` handler 完整执行九步。返回的 `Response.body` 由调用方释放。
pub fn invoke(allocator: std.mem.Allocator, def: *const tool_def.ToolDef, arguments_json: []const u8, env: Env) !Response {
    const native = switch (def.handler) {
        .native => |value| value,
        else => return error.InvalidToolHandler,
    };
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(arguments_json, &hash, .{});
    var record: AuditRecord = .{ .tool = def.name, .version = def.version, .arguments_hash = hash, .target = null, .approval = "not_reached", .outcome = "" };

    step(env, .parse);
    step(env, .schema);
    var parsed = parseArguments(allocator, def.input_schema, def.budget.max_argument_bytes, def.validate, arguments_json) catch |err|
        return failure(allocator, env, &record, .rejected, tool_def.ErrorBody.init(.InvalidArguments, @errorName(err), "Fix the arguments to match the tool's input schema."));
    defer parsed.deinit();

    step(env, .scope);
    record.target = env.scope(env.context, def, parsed.value) catch |err| {
        const code: tool_def.ErrorCode = switch (err) {
            error.CardNotInTab => .CardNotInTab,
            error.SnapshotChanged => .SnapshotChanged,
            error.PermissionDenied, error.ToolPermissionUndeclared => .PermissionDenied,
            error.RequiredServiceUnavailable, error.UnsupportedParameter => .Unsupported,
            error.InvalidCursor => .InvalidArguments,
            else => .TargetNotAuthorized,
        };
        const default_hint: ?[]const u8 = if (code == .CardNotInTab) "Call host.tab_context without card_refs to list the cards in this tab." else null;
        const hint = if (env.scope_hint) |get| get(env.context) orelse default_hint else default_hint;
        return failure(allocator, env, &record, .rejected, tool_def.ErrorBody.init(code, @errorName(err), hint));
    };
    const call: tool_def.Call = .{ .name = def.name, .arguments = parsed.value, .arguments_json = arguments_json, .arguments_hash = hash, .target = record.target, .env = env.context };

    step(env, .approval);
    const required = needsApproval(def, parsed.value, env.policy, env.grouped) catch |err|
        return failure(allocator, env, &record, .rejected, tool_def.ErrorBody.init(.PermissionDenied, @errorName(err), null));
    if (required) {
        const ask = env.approve orelse {
            record.approval = "rejected";
            return failure(allocator, env, &record, .rejected, tool_def.ErrorBody.init(.ApprovalRequired, "ToolApprovalRequired", null));
        };
        const approved = ask(env.context, def, call) catch false;
        record.approval = if (approved) "approved" else "rejected";
        if (!approved) return failure(allocator, env, &record, .rejected, tool_def.ErrorBody.init(.ApprovalRejected, "ToolApprovalRejected", null));
    } else record.approval = "not_required";

    step(env, .dispatch);
    var output = native.call(native.context, call, allocator) catch |err| {
        // 读到一半内容已变化（例如分页游标签发后目录刷新）：可重试，提示从头再读。
        if (err == error.SnapshotChanged) return failure(allocator, env, &record, .failed, tool_def.ErrorBody.init(.SnapshotChanged, @errorName(err), "The content changed since the cursor was issued. Call the tool again without cursor."));
        return failure(allocator, env, &record, .failed, tool_def.ErrorBody.init(.HandlerFailed, @errorName(err), null));
    };
    defer output.deinit(allocator);

    step(env, .normalize);
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const Block = struct { type: []const u8, text: []const u8 };
    const blocks = try a.alloc(Block, output.content.len);
    for (output.content, blocks) |item, *block| switch (item) {
        .text => |text| {
            if (!std.unicode.utf8ValidateSlice(text)) return failure(allocator, env, &record, .failed, tool_def.ErrorBody.init(.HandlerFailed, "InvalidToolResult", null));
            block.* = .{ .type = "text", .text = text };
        },
        .structured => |text| {
            const check = std.json.parseFromSlice(std.json.Value, a, text, .{}) catch return failure(allocator, env, &record, .failed, tool_def.ErrorBody.init(.HandlerFailed, "InvalidToolResult", null));
            check.deinit();
            block.* = .{ .type = "structured", .text = text };
        },
    };

    step(env, .redact_truncate);
    if (env.redact) |redact| for (blocks) |*block| {
        if (!std.mem.eql(u8, block.type, "text")) continue;
        block.text = try redact(env.context, block.text, a);
    };
    const truncated = budgetBlocks(blocks, def.budget) catch
        return failure(allocator, env, &record, .failed, tool_def.ErrorBody.init(.ResultTooLarge, "ToolResultTooLarge", "Request a smaller range or lower max_bytes."));

    step(env, .audit);
    record.outcome = @tagName(output.status);
    if (env.audit) |sink| sink(env.context, record);

    step(env, .respond);
    const body = try std.json.Stringify.valueAlloc(allocator, .{ .status = output.status, .content = blocks, .truncated = truncated }, .{});
    return .{ .status = output.status, .body = body, .truncated = truncated };
}

fn step(env: Env, stage: Stage) void {
    if (env.trace) |trace| trace(env.context, stage);
}
fn failure(allocator: std.mem.Allocator, env: Env, record: *AuditRecord, status: tools.Status, body: tool_def.ErrorBody) !Response {
    step(env, .audit);
    record.outcome = @tagName(body.code);
    if (env.audit) |sink| sink(env.context, record.*);
    step(env, .respond);
    const text = try std.json.Stringify.valueAlloc(allocator, .{ .status = status, .@"error" = body }, .{});
    return .{ .status = status, .body = text, .err = body };
}

/// 文本块按 `truncate` 处理；结构化块不可截断（截断会破坏 JSON），超出即拒绝。
fn budgetBlocks(blocks: anytype, budget: tool_def.Budget) !bool {
    var total: usize = 0;
    var structured: usize = 0;
    for (blocks) |block| {
        total += block.text.len;
        if (!std.mem.eql(u8, block.type, "text")) structured += block.text.len;
    }
    if (total <= budget.max_result_bytes) return false;
    if (budget.truncate == .reject or structured > budget.max_result_bytes) return error.ToolResultTooLarge;
    var remaining = budget.max_result_bytes - structured;
    // tail 保留末尾：从后往前分配预算；head 保留开头：从前往后。
    if (budget.truncate == .tail) {
        var index = blocks.len;
        while (index > 0) {
            index -= 1;
            const block = &blocks[index];
            if (!std.mem.eql(u8, block.type, "text")) continue;
            block.text = tailBytes(block.text, remaining);
            remaining -= block.text.len;
        }
    } else for (blocks) |*block| {
        if (!std.mem.eql(u8, block.type, "text")) continue;
        block.text = headBytes(block.text, remaining);
        remaining -= block.text.len;
    }
    return true;
}
fn headBytes(text: []const u8, limit: usize) []const u8 {
    if (text.len <= limit) return text;
    var end = limit;
    while (end > 0 and (text[end] & 0xC0) == 0x80) end -= 1;
    return text[0..end];
}
fn tailBytes(text: []const u8, limit: usize) []const u8 {
    if (text.len <= limit) return text;
    var start = text.len - limit;
    while (start < text.len and (text[start] & 0xC0) == 0x80) start += 1;
    return text[start..];
}

/// 把审计记录写进现有的 `audit.Log`（命令列记工具名，裁决列记审批结论）。
pub fn auditLogSink(log: *@import("audit.zig").Log, record: AuditRecord, timestamp_ms: i64, turn_id: u64) !void {
    try log.append(.{ .timestamp_ms = timestamp_ms, .turn_id = turn_id, .command = record.tool, .verdict = record.approval, .target = record.target orelse "" });
}

// ─── 单测 ────────────────────────────────────────────────────────────────

const Fixture = struct {
    stages: std.ArrayList(Stage) = .empty,
    audits: std.ArrayList(AuditRecord) = .empty,
    target_copy: [16]u8 = undefined,
    calls: usize = 0,
    approve_answer: bool = true,
    approvals: usize = 0,
    scope_error: ?anyerror = null,
    scope_hint_text: ?[]const u8 = null,
    handler_error: ?anyerror = null,
    output_text: []const u8 = "hello",
    output_status: tools.Status = .succeeded,

    fn trace(raw: *anyopaque, stage: Stage) void {
        const self: *Fixture = @ptrCast(@alignCast(raw));
        self.stages.append(std.testing.allocator, stage) catch unreachable;
    }
    fn audit(raw: *anyopaque, record: AuditRecord) void {
        const self: *Fixture = @ptrCast(@alignCast(raw));
        var copy = record;
        if (record.target) |target| {
            @memcpy(self.target_copy[0..target.len], target);
            copy.target = self.target_copy[0..target.len];
        }
        self.audits.append(std.testing.allocator, copy) catch unreachable;
    }
    fn scope(raw: *anyopaque, _: *const tool_def.ToolDef, arguments: std.json.Value) anyerror!?[]const u8 {
        const self: *Fixture = @ptrCast(@alignCast(raw));
        if (self.scope_error) |err| return err;
        return if (arguments.object.get("card_ref")) |value| value.string else null;
    }
    fn approve(raw: *anyopaque, _: *const tool_def.ToolDef, _: tool_def.Call) anyerror!bool {
        const self: *Fixture = @ptrCast(@alignCast(raw));
        self.approvals += 1;
        return self.approve_answer;
    }
    fn hint(raw: *anyopaque) ?[]const u8 {
        const self: *Fixture = @ptrCast(@alignCast(raw));
        return self.scope_hint_text;
    }
    fn handle(raw: *anyopaque, call: tool_def.Call, allocator: std.mem.Allocator) anyerror!tool_def.Output {
        const self: *Fixture = @ptrCast(@alignCast(raw));
        self.calls += 1;
        if (self.handler_error) |err| return err;
        const content = try allocator.alloc(tool_def.Content, 2);
        content[0] = .{ .structured = try std.fmt.allocPrint(allocator, "{{\"target\":\"{s}\"}}", .{call.target orelse ""}) };
        content[1] = .{ .text = try allocator.dupe(u8, self.output_text) };
        return .{ .status = self.output_status, .content = content };
    }
    fn deinit(self: *Fixture) void {
        self.stages.deinit(std.testing.allocator);
        self.audits.deinit(std.testing.allocator);
    }
    fn env(self: *Fixture) Env {
        return .{ .context = self, .scope = scope, .approve = approve, .audit = audit, .trace = trace, .policy = .{ .engine = .{ .mode = .confirm } } };
    }
    fn def(self: *Fixture, approval: tool_def.Approval, effect: tool_def.Effect) tool_def.ToolDef {
        return .{ .name = "probe.read_text", .description = "Read text.", .input_schema = "{\"type\":\"object\",\"additionalProperties\":false,\"properties\":{\"card_ref\":{\"type\":\"string\",\"minLength\":1,\"maxLength\":128},\"max_bytes\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":65536}},\"required\":[\"card_ref\"]}", .handler = .{ .native = .{ .context = self, .call = handle } }, .approval = approval, .effect = effect, .target = .{ .card_type = "terminal" }, .budget = .{ .max_result_bytes = 64 } };
    }
};

test "tooldef pipeline runs every stage in order and only the handler is tool specific" {
    const a = std.testing.allocator;
    var fixture: Fixture = .{};
    defer fixture.deinit();
    const def = fixture.def(.read_only, .read_state);
    var response = try invoke(a, &def, "{\"card_ref\":\"c1\"}", fixture.env());
    defer response.deinit(a);
    try std.testing.expectEqualSlices(Stage, std.enums.values(Stage), fixture.stages.items);
    try std.testing.expectEqualStrings("{\"status\":\"succeeded\",\"content\":[{\"type\":\"structured\",\"text\":\"{\\\"target\\\":\\\"c1\\\"}\"},{\"type\":\"text\",\"text\":\"hello\"}],\"truncated\":false}", response.body);
    try std.testing.expectEqual(@as(usize, 1), fixture.calls);
    try std.testing.expectEqual(@as(usize, 0), fixture.approvals);
    try std.testing.expectEqualStrings("not_required", fixture.audits.items[0].approval);
    try std.testing.expectEqualStrings("succeeded", fixture.audits.items[0].outcome);
    try std.testing.expectEqualStrings("c1", fixture.audits.items[0].target.?);
}

test "tooldef pipeline rejects before dispatch with the shared error structure" {
    const a = std.testing.allocator;
    const cases = .{
        .{ "{\"card_ref\":\"c1\",\"extra\":1}", @as(?anyerror, null), tool_def.ErrorCode.InvalidArguments },
        .{ "[]", @as(?anyerror, null), tool_def.ErrorCode.InvalidArguments },
        .{ "{\"card_ref\":\"c1\",\"max_bytes\":0}", @as(?anyerror, null), tool_def.ErrorCode.InvalidArguments },
        .{ "{\"card_ref\":\"c9\"}", @as(?anyerror, error.CardNotInTab), tool_def.ErrorCode.CardNotInTab },
        .{ "{\"card_ref\":\"c9\"}", @as(?anyerror, error.TargetOutsideScope), tool_def.ErrorCode.TargetNotAuthorized },
    };
    inline for (cases) |case| {
        var fixture: Fixture = .{ .scope_error = case[1] };
        defer fixture.deinit();
        const def = fixture.def(.read_only, .read_state);
        var response = try invoke(a, &def, case[0], fixture.env());
        defer response.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), fixture.calls);
        try std.testing.expectEqual(case[2], response.err.?.code);
        const parsed = try std.json.parseFromSlice(std.json.Value, a, response.body, .{});
        defer parsed.deinit();
        const err = parsed.value.object.get("error").?.object;
        for ([_][]const u8{ "code", "message", "retryable", "hint" }) |key| try std.testing.expect(err.contains(key));
        try std.testing.expectEqualStrings(@tagName(case[2]), fixture.audits.items[0].outcome);
    }
}

test "tooldef pipeline maps unsupported parameters and stale cursors to actionable errors" {
    const a = std.testing.allocator;
    {
        // 第 3 步：工具给出的提示覆盖默认提示（例如哪张卡片不支持哪个参数）。
        var fixture: Fixture = .{ .scope_error = error.UnsupportedParameter, .scope_hint_text = "Card k1 (kvm) does not support max_lines." };
        defer fixture.deinit();
        const def = fixture.def(.read_only, .read_state);
        var env = fixture.env();
        env.scope_hint = Fixture.hint;
        var response = try invoke(a, &def, "{\"card_ref\":\"c1\"}", env);
        defer response.deinit(a);
        try std.testing.expectEqual(tool_def.ErrorCode.Unsupported, response.err.?.code);
        try std.testing.expectEqualStrings("Card k1 (kvm) does not support max_lines.", response.err.?.hint.?);
        try std.testing.expectEqual(@as(usize, 0), fixture.calls);
    }
    {
        var fixture: Fixture = .{ .scope_error = error.InvalidCursor };
        defer fixture.deinit();
        const def = fixture.def(.read_only, .read_state);
        var response = try invoke(a, &def, "{\"card_ref\":\"c1\"}", fixture.env());
        defer response.deinit(a);
        try std.testing.expectEqual(tool_def.ErrorCode.InvalidArguments, response.err.?.code);
    }
    {
        // 分发后内容已变化：SnapshotChanged，可重试，带提示。
        var fixture: Fixture = .{ .handler_error = error.SnapshotChanged };
        defer fixture.deinit();
        const def = fixture.def(.read_only, .read_state);
        var response = try invoke(a, &def, "{\"card_ref\":\"c1\"}", fixture.env());
        defer response.deinit(a);
        try std.testing.expectEqual(tool_def.ErrorCode.SnapshotChanged, response.err.?.code);
        try std.testing.expect(response.err.?.retryable and response.err.?.hint != null);
    }
}

test "tooldef pipeline approval follows approval policy effect and hook" {
    const a = std.testing.allocator;
    {
        var fixture: Fixture = .{ .approve_answer = false };
        defer fixture.deinit();
        const def = fixture.def(.confirm, .resource_write);
        var response = try invoke(a, &def, "{\"card_ref\":\"c1\"}", fixture.env());
        defer response.deinit(a);
        try std.testing.expectEqual(@as(usize, 1), fixture.approvals);
        try std.testing.expectEqual(@as(usize, 0), fixture.calls);
        try std.testing.expectEqual(tool_def.ErrorCode.ApprovalRejected, response.err.?.code);
        try std.testing.expectEqualStrings("rejected", fixture.audits.items[0].approval);
    }
    {
        var fixture: Fixture = .{};
        defer fixture.deinit();
        const def = fixture.def(.confirm, .resource_write);
        var env = fixture.env();
        env.policy.engine.mode = .auto;
        var response = try invoke(a, &def, "{\"card_ref\":\"c1\"}", env);
        defer response.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), fixture.approvals);
        try std.testing.expectEqual(@as(usize, 1), fixture.calls);
    }
    {
        var fixture: Fixture = .{};
        defer fixture.deinit();
        const def = fixture.def(.read_only, .resource_write);
        var env = fixture.env();
        env.policy.allow_write = false;
        var response = try invoke(a, &def, "{\"card_ref\":\"c1\"}", env);
        defer response.deinit(a);
        try std.testing.expectEqual(tool_def.ErrorCode.PermissionDenied, response.err.?.code);
        try std.testing.expectEqual(@as(usize, 0), fixture.calls);
    }
    {
        // 细粒度钩子（遗留 shellPolicy 一类）决定是否需要确认。
        var fixture: Fixture = .{};
        defer fixture.deinit();
        var def = fixture.def(.read_only, .read_state);
        def.approval_hook = struct {
            fn hook(_: std.json.Value, _: tools.Policy, _: bool) anyerror!bool {
                return true;
            }
        }.hook;
        var response = try invoke(a, &def, "{\"card_ref\":\"c1\"}", fixture.env());
        defer response.deinit(a);
        try std.testing.expectEqual(@as(usize, 1), fixture.approvals);
        try std.testing.expectEqualStrings("approved", fixture.audits.items[0].approval);
    }
}

test "tooldef pipeline truncates by budget and keeps utf8 boundaries" {
    const a = std.testing.allocator;
    const long = "一二三四五六七八九十一二三四五六七八九十";
    inline for (.{ tool_def.Truncate.tail, tool_def.Truncate.head, tool_def.Truncate.reject }) |mode| {
        var fixture: Fixture = .{ .output_text = long };
        defer fixture.deinit();
        var def = fixture.def(.read_only, .read_state);
        def.budget = .{ .max_result_bytes = 40, .truncate = mode };
        var response = try invoke(a, &def, "{\"card_ref\":\"c1\"}", fixture.env());
        defer response.deinit(a);
        if (mode == .reject) {
            try std.testing.expectEqual(tool_def.ErrorCode.ResultTooLarge, response.err.?.code);
            continue;
        }
        try std.testing.expect(response.truncated);
        const parsed = try std.json.parseFromSlice(std.json.Value, a, response.body, .{});
        defer parsed.deinit();
        const text = parsed.value.object.get("content").?.array.items[1].object.get("text").?.string;
        try std.testing.expect(std.unicode.utf8ValidateSlice(text));
        try std.testing.expect(text.len <= 40 - "{\"target\":\"c1\"}".len);
        if (mode == .tail) try std.testing.expect(std.mem.endsWith(u8, long, text)) else try std.testing.expect(std.mem.startsWith(u8, long, text));
    }
}

test "tooldef pipeline parse stage is the request table parse implementation" {
    const a = std.testing.allocator;
    const schema = "{\"type\":\"object\",\"additionalProperties\":false,\"properties\":{\"n\":{\"type\":\"integer\",\"minimum\":1}}}";
    var ok = try parseArguments(a, schema, 64, null, "{\"n\":2}");
    ok.deinit();
    try std.testing.expectError(error.InvalidToolArguments, parseArguments(a, schema, 4, null, "{\"n\":2}"));
    try std.testing.expectError(error.InvalidToolArguments, parseArguments(a, schema, 64, null, "{\"n\":0}"));
    try std.testing.expectError(error.InvalidToolArguments, parseArguments(a, schema, 64, null, "{\"m\":1}"));
    try std.testing.expectError(error.InvalidToolArguments, parseArguments(a, schema, 64, null, "1"));
    var log = @import("audit.zig").Log.init(a);
    defer log.deinit();
    try auditLogSink(&log, .{ .tool = "probe.read_text", .version = 1, .arguments_hash = @splat(0), .target = "c1", .approval = "approved", .outcome = "succeeded" }, 5, 7);
    try std.testing.expectEqualStrings("probe.read_text", log.entries.items[0].command);
}
