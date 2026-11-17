//! Assistant ownership and model-selected remote targets. UI focus is never a
//! transport target: every call is checked against its captured owner scope.
const std = @import("std");
const permission = @import("permission.zig");

/// AI 对话的归属（PLUGIN_ARCH_PLAN 2.5.8 M10）：统一为所在的 tab（`identity.TabId` 的数值，与
/// `workspace_model.Tab.id` 同一个标识）。单卡 tab 与分屏（会话组）tab 都绑定自己的 TabId，绑定、
/// 交接、日志与界面都只认这一种。
///
/// `session` / `group` 是 M10 之前的两套归属，**只读**：只在回放 schema 1–3 的旧日志行时出现，
/// 用于在会话列表里显示来源；`session_lifecycle.Store.attach` 拒绝用它们创建新绑定。
pub const Owner = union(enum) {
    tab: u64,
    session: u64,
    group: u64,
    pub fn eql(a: Owner, b: Owner) bool {
        return std.meta.activeTag(a) == std.meta.activeTag(b) and switch (a) {
            .tab => |id| id == b.tab,
            .session => |id| id == b.session,
            .group => |id| id == b.group,
        };
    }
    /// 旧日志里的只读归属（不能作为新绑定）。
    pub fn legacy(self: Owner) bool {
        return self != .tab;
    }
    pub fn raw(self: Owner) u64 {
        return switch (self) {
            inline else => |number| number,
        };
    }
};
/// 绑定 tab 里装的是什么：单卡 tab 的会话卡片，或分屏 tab 的会话组。它不是归属，而是每次捕获
/// 作用域 / 宿主授权时从工作区派生的事实；会话组相关的宿主工具（`host.get_group` 等）与
/// 模型可见的元数据（`binding`、`current_binding`）按它表达，因此与 M10 之前逐字相同。
pub const Content = union(enum) {
    session: u64,
    group: u64,
    pub fn eql(a: Content, b: Content) bool {
        return std.meta.eql(a, b);
    }
    pub fn raw(self: Content) u64 {
        return switch (self) {
            inline else => |number| number,
        };
    }
    /// 旧日志里的 `session` / `group` 归属本身就是内容。
    pub fn ofLegacy(owner: Owner) ?Content {
        return switch (owner) {
            .tab => null,
            .session => |value| .{ .session = value },
            .group => |value| .{ .group = value },
        };
    }
};
pub const max_targets = 16;
pub const Targets = struct {
    ids: [max_targets]u64 = @splat(0),
    len: usize = 0,
    pub fn slice(self: *const Targets) []const u64 {
        return self.ids[0..self.len];
    }
};
pub const Scope = struct {
    owner: Owner,
    /// 捕获时 tab 的内容（派生事实，见 `Content`）。绑定为 `.tab` 时必须给出；只读的旧归属
    /// （测试夹具与旧日志）由归属本身派生。
    content: ?Content = null,
    members: Targets,
    /// A frozen directory may contain more members than one tool call. Owners
    /// of a request must clone this slice; the legacy Targets stay call-sized.
    inventory: ?[]const u64 = null,

    /// tab 的内容；旧归属由归属本身派生；`.tab` 归属而未捕获内容时是不含任何成员的空会话，
    /// 所有成员与会话组判断都失败关闭。
    pub fn contentOf(self: Scope) Content {
        return self.content orelse Content.ofLegacy(self.owner) orelse .{ .session = 0 };
    }
    pub fn memberIds(self: *const Scope) []const u64 {
        return self.inventory orelse self.members.slice();
    }
    pub fn clone(self: Scope, allocator: std.mem.Allocator) !Scope {
        var result = self;
        if (self.inventory) |ids| result.inventory = try allocator.dupe(u64, ids);
        return result;
    }
    pub fn validateDirectory(self: Scope, ids: []const u64) !void {
        if (ids.len == 0) return error.InvalidTargetCount;
        for (ids, 0..) |id, i| {
            if (id == 0 or std.mem.indexOfScalar(u64, self.memberIds(), id) == null) return error.TargetOutsideAssistant;
            if (std.mem.indexOfScalar(u64, ids[0..i], id) != null) return error.DuplicateTarget;
            // 单卡 tab 只能指向它自己的会话。内容未捕获时（回放日志里的 tab 归属）只按成员目录校验。
            if (self.content orelse Content.ofLegacy(self.owner)) |held| switch (held) {
                .session => |session| if (id != session) return error.TargetOutsideAssistant,
                .group => {},
            };
        }
    }
    /// Validate again immediately before dispatch against the live roster.
    /// A closed session or removed member cannot inherit an approved call.
    pub fn validate(self: Scope, ids: []const u64) !Targets {
        if (ids.len == 0 or ids.len > max_targets) return error.InvalidTargetCount;
        try self.validateDirectory(ids);
        var result: Targets = .{};
        @memcpy(result.ids[0..ids.len], ids);
        result.len = ids.len;
        return result;
    }
};

test "frozen directory exceeds one call without granting extra call targets" {
    var ids: [300]u64 = undefined;
    for (&ids, 1..) |*id, index| id.* = index;
    const original: Scope = .{ .owner = .{ .tab = 1 }, .content = .{ .group = 1 }, .members = .{}, .inventory = &ids };
    const frozen = try original.clone(std.testing.allocator);
    defer std.testing.allocator.free(frozen.inventory.?);
    ids[299] = 901;
    try std.testing.expectEqual(@as(u64, 300), frozen.memberIds()[299]);
    try frozen.validateDirectory(frozen.memberIds());
    _ = try frozen.validate(&.{ 300, 17 });
    try std.testing.expectError(error.InvalidTargetCount, frozen.validate(frozen.memberIds()));
    try std.testing.expectError(error.TargetOutsideAssistant, frozen.validate(&.{901}));
    try std.testing.expectError(error.DuplicateTarget, frozen.validateDirectory(&.{ 300, 300 }));
}
pub const Tool = enum { run_command, read_terminal, list_remote_files, read_remote_file };
pub const Call = struct {
    tool: Tool,
    command: []const u8 = "",
    path: []const u8 = "",
    targets: Targets,
    max_bytes: u32 = 4096,
    offset: u64 = 0,
    max_entries: u32 = 128,
    expected_version: ?u64 = null,
};
pub const ParsedCall = struct {
    json: std.json.Parsed(Arguments),
    call: Call,
    pub fn deinit(self: *ParsedCall) void {
        self.json.deinit();
    }
};
const Arguments = struct { session_ids: []const u64, command: []const u8 = "", path: []const u8 = "", max_bytes: u32 = 4096, offset: u64 = 0, max_entries: u32 = 128, source_version: []const u8 = "" };

pub fn parse(allocator: std.mem.Allocator, scope: Scope, name: []const u8, arguments: []const u8) !ParsedCall {
    const tool = std.meta.stringToEnum(Tool, name) orelse return error.UnsupportedTool;
    var json = try std.json.parseFromSlice(Arguments, allocator, arguments, .{ .ignore_unknown_fields = false });
    errdefer json.deinit();
    const value = json.value;
    const targets = try scope.validate(value.session_ids);
    switch (tool) {
        .run_command => if (std.mem.trim(u8, value.command, " \t\r\n").len == 0 or value.path.len != 0) return error.InvalidToolArguments,
        .read_remote_file, .list_remote_files => {
            if (!std.mem.startsWith(u8, value.path, "/") or std.mem.indexOfScalar(u8, value.path, 0) != null or value.command.len != 0) return error.InvalidToolArguments;
        },
        .read_terminal => if (value.command.len != 0 or value.path.len != 0) return error.InvalidToolArguments,
    }
    if (value.max_bytes == 0 or value.max_bytes > 64 * 1024) return error.InvalidToolArguments;
    if (tool == .read_remote_file and value.max_bytes < 4) return error.InvalidToolArguments;
    if (value.max_entries == 0 or value.max_entries > 128) return error.InvalidToolArguments;
    const version = if (value.source_version.len == 0) null else if (value.source_version.len == 16) std.fmt.parseInt(u64, value.source_version, 16) catch return error.InvalidToolArguments else return error.InvalidToolArguments;
    if (value.offset != 0 and version == null) return error.InvalidToolArguments;
    return .{ .json = json, .call = .{ .offset = value.offset, .max_entries = value.max_entries, .expected_version = version, .tool = tool, .command = value.command, .path = value.path, .targets = targets, .max_bytes = value.max_bytes } };
}

/// Dispatcher binding lives with the assistant, not the selected UI tab.
/// Approval belongs to the exact validated call; it cannot retarget it.
pub const Dispatcher = struct {
    ctx: *anyopaque,
    invoke: *const fn (*anyopaque, Tool, u64, []const u8, u32) anyerror!void,
    pub fn dispatch(self: Dispatcher, live: Scope, captured: Scope, call: Call, policy: permission.Engine, approved: bool) !void {
        if (!Owner.eql(live.owner, captured.owner)) return error.AssistantOwnerChanged;
        _ = try captured.validate(call.targets.slice());
        _ = try live.validate(call.targets.slice());
        if (call.max_bytes == 0 or call.max_bytes > 64 * 1024) return error.InvalidToolArguments;
        if (call.tool == .run_command) {
            switch (permission.classify(policy, call.command, captured.contentOf() == .group)) {
                .deny_exec_copy_only => return error.ToolExecutionDenied,
                .need_confirm => if (!approved) return error.ToolApprovalRequired,
                .allow_auto => {},
            }
        }
        for (call.targets.slice()) |id| try self.invoke(self.ctx, call.tool, id, if (call.tool == .run_command) call.command else call.path, call.max_bytes);
    }
};

test "model selects a subset of group members and remote file targets" {
    const scope: Scope = .{ .owner = .{ .tab = 7 }, .content = .{ .group = 7 }, .members = .{ .ids = .{ 101, 102, 103 } ++ @as([13]u64, @splat(0)), .len = 3 } };
    var parsed = try parse(std.testing.allocator, scope, "read_remote_file", "{\"session_ids\":[103,101],\"path\":\"/var/log/app.log\"}");
    defer parsed.deinit();
    try std.testing.expectEqualSlices(u64, &.{ 103, 101 }, parsed.call.targets.slice());
    try std.testing.expectError(error.TargetOutsideAssistant, scope.validate(&.{999}));
    try std.testing.expectError(error.DuplicateTarget, scope.validate(&.{ 101, 101 }));
    try std.testing.expectError(error.InvalidTargetCount, scope.validate(&.{}));
}

test "single assistant cannot cross sessions; unsupported subagents fail closed" {
    const scope: Scope = .{ .owner = .{ .tab = 101 }, .content = .{ .session = 101 }, .members = .{ .ids = .{101} ++ @as([15]u64, @splat(0)), .len = 1 } };
    try std.testing.expectError(error.TargetOutsideAssistant, scope.validate(&.{102}));
    try std.testing.expectError(error.UnsupportedTool, parse(std.testing.allocator, scope, "spawn_agent", "{}"));
    try std.testing.expectError(error.InvalidToolArguments, parse(std.testing.allocator, scope, "read_remote_file", "{\"session_ids\":[101],\"path\":\"relative\"}"));
}

test "dispatch rejects stale membership before contacting any remote target" {
    const Fake = struct {
        count: usize = 0,
        fn invoke(raw: *anyopaque, _: Tool, _: u64, _: []const u8, _: u32) !void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.count += 1;
        }
    };
    var fake: Fake = .{};
    const captured: Scope = .{ .owner = .{ .tab = 7 }, .content = .{ .group = 7 }, .members = .{ .ids = .{ 101, 102 } ++ @as([14]u64, @splat(0)), .len = 2 } };
    var live = captured;
    live.members.len = 1;
    const call: Call = .{ .tool = .run_command, .command = "df -h", .targets = try captured.validate(&.{ 101, 102 }) };
    const dispatcher: Dispatcher = .{ .ctx = &fake, .invoke = Fake.invoke };
    try std.testing.expectError(error.TargetOutsideAssistant, dispatcher.dispatch(live, captured, call, .{}, false));
    try std.testing.expectEqual(@as(usize, 0), fake.count);
    try dispatcher.dispatch(captured, captured, call, .{}, false);
    try std.testing.expectEqual(@as(usize, 2), fake.count);
}

test "approval never overrides blacklist including compounds and group writes require approval" {
    const Fake = struct {
        count: usize = 0,
        fn invoke(raw: *anyopaque, _: Tool, _: u64, _: []const u8, _: u32) !void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.count += 1;
        }
    };
    var fake: Fake = .{};
    const scope: Scope = .{ .owner = .{ .tab = 7 }, .content = .{ .group = 7 }, .members = .{ .ids = .{101} ++ @as([15]u64, @splat(0)), .len = 1 } };
    const dispatcher: Dispatcher = .{ .ctx = &fake, .invoke = Fake.invoke };
    var call: Call = .{ .tool = .run_command, .command = "touch /tmp/file", .targets = try scope.validate(&.{101}) };
    try std.testing.expectError(error.ToolApprovalRequired, dispatcher.dispatch(scope, scope, call, .{}, false));
    for ([_][]const u8{ "rm -rf /", "printf safe; rm -rf /tmp/fixture", "if true; then shutdown now; fi" }) |command| {
        call.command = command;
        try std.testing.expectError(error.ToolExecutionDenied, dispatcher.dispatch(scope, scope, call, .{ .mode = .auto }, true));
    }
    try std.testing.expectEqual(@as(usize, 0), fake.count);
}
