//! File-provider compatibility bridge. It owns no terminal or exec binding and
//! reads only the original FileBindingHost session through its bounded reader.
const std = @import("std");
const App = @import("../../../shell/host/application_host.zig").ApplicationHost;
const identity = @import("../../../../host/identity.zig");
const sessions = @import("../../../../host/session_host.zig");
const provider = @import("../../../../ai/provider.zig");
const loop = @import("../../../../ai/tool_loop.zig");
const scope = @import("../../../../ai/tool_scope.zig");
const adapter = @import("../../../../ai/legacy_adapter.zig");
const capture = @import("../../../../host/ai_remote_file_snapshot.zig");
const bindings = @import("../../../../host/file_binding_host.zig");
const projection = @import("../../cards/model/ai_file_tool_result.zig");
const Capture = struct { owner: identity.SessionHandle, bindings: bindings.Bindings, target: []u8, cwd: ?[]const u8 = null };
const Exchange = struct { invocation: loop.Invocation, allocator: std.mem.Allocator, ready: std.atomic.Value(bool) = .init(false), cancel: std.atomic.Value(bool) = .init(false), outcome: ?loop.Outcome = null, failure: ?anyerror = null };
pub const Bridge = struct {
    allocator: std.mem.Allocator,
    files: ?*@import("../../../files/host/file_application_host.zig").Host = null,
    capture: ?Capture = null,
    delegated_owner: ?scope.Owner = null,
    exchange: ?*Exchange = null,
    reader: ?*capture.Reader = null,
    sequence: u64 = 0,
    mutex: std.atomic.Mutex = .unlocked,
    stopping: bool = false,
    pub fn init(a: std.mem.Allocator) Bridge {
        return .{ .allocator = a };
    }
    fn lock(self: *Bridge) void {
        while (!self.mutex.tryLock()) std.atomic.spinLoopHint();
    }
    pub fn prepare(self: *Bridge, app: *App, owner: identity.SessionHandle) !void {
        if (self.exchange != null or self.reader != null or self.capture != null) return error.ToolCleanupPending;
        const files = self.files orelse return error.FileSourceUnavailable;
        const source = try files.ensureReadonlySource(owner);
        if (!app.sessions.bindingIsLive(source.directory) or !app.sessions.bindingIsLive(source.file_read)) return error.StaleBinding;
        const id = app.legacyForHandle(owner) orelse return error.StaleSession;
        const tab = app.workspace.sessionTab(id) orelse return error.StaleSession;
        self.capture = .{ .owner = owner, .bindings = source, .target = try std.fmt.allocPrint(self.allocator, "文件 · {s}", .{tab.titleSlice()}) };
        self.stopping = false;
    }
    pub fn filesAvailable(self: *Bridge) bool {
        return self.files != null and self.capture != null;
    }
    pub fn preflight(self: *Bridge, app: *App, invocation: loop.Invocation) !void {
        const source = self.capture orelse return error.ServiceUnavailable;
        if (invocation.call.tool != .list_remote_files and invocation.call.tool != .read_remote_file) return error.UnsupportedTool;
        if (invocation.call.targets.len != 1 or invocation.call.targets.ids[0] != @backingInt(source.owner.session_id)) return error.TargetOutsideAssistant;
        if (self.delegated_owner) |owner| {
            if (!owner.eql(invocation.key.owner)) return error.TargetOutsideAssistant;
        } else if (!invocation.key.owner.eql(invocation.scope.owner) or invocation.scope.contentOf() != .session or invocation.scope.contentOf().session != @backingInt(source.owner.session_id)) return error.TargetOutsideAssistant;
        _ = try invocation.scope.validate(invocation.call.targets.slice());
        if (!app.sessions.bindingIsLive(source.bindings.directory) or !app.sessions.bindingIsLive(source.bindings.file_read) or app.legacyForHandle(source.owner) == null) return error.StaleBinding;
        const directory = switch (app.sessions.queryService(source.owner, .directory)) {
            .available => |binding| binding,
            else => return error.StaleBinding,
        };
        const file_read = switch (app.sessions.queryService(source.owner, .file_read)) {
            .available => |binding| binding,
            else => return error.StaleBinding,
        };
        if (!directory.eql(source.bindings.directory) or !file_read.eql(source.bindings.file_read)) return error.StaleBinding;
    }
    pub fn interface(self: *Bridge) loop.Host {
        return .{ .context = self, .execute = execute };
    }
    fn execute(raw: *anyopaque, invocation: loop.Invocation, a: std.mem.Allocator, cancel: ?*provider.CancelToken) !loop.Outcome {
        const self: *Bridge = @ptrCast(@alignCast(raw));
        var exchange: Exchange = .{ .invocation = invocation, .allocator = a };
        self.lock();
        if (self.stopping or self.exchange != null) {
            self.mutex.unlock();
            return error.ToolHostUnavailable;
        }
        self.sequence = try identity.advance(self.sequence +| @intFromBool(self.sequence == 0));
        self.exchange = &exchange;
        self.mutex.unlock();
        defer {
            self.lock();
            self.exchange = null;
            self.mutex.unlock();
        }
        while (!exchange.ready.load(.acquire)) {
            if (cancel) |token| if (token.isCancelled()) exchange.cancel.store(true, .release);
            pause();
        }
        if (exchange.failure) |err| return err;
        return exchange.outcome orelse error.ToolOutcomeUnknown;
    }
    fn finish(self: *Bridge, result: loop.TargetResult) void {
        const current = self.exchange orelse return;
        if (current.ready.load(.acquire)) return;
        current.outcome = loop.Outcome.copy(current.allocator, &.{result}) catch |err| {
            current.failure = err;
            current.ready.store(true, .release);
            return;
        };
        current.ready.store(true, .release);
    }
    /// Native work in flight that only `pump` observes: an exchange not answered yet or a read.
    pub fn busy(self: *Bridge) bool {
        self.lock();
        defer self.mutex.unlock();
        if (self.reader != null) return true;
        return if (self.exchange) |current| !current.ready.load(.acquire) else false;
    }
    pub fn pump(self: *Bridge, app: *App) void {
        self.lock();
        defer self.mutex.unlock();
        const current = self.exchange orelse return;
        if (current.ready.load(.acquire) and self.reader == null) return;
        const source = self.capture orelse return;
        const valid = blk: {
            self.preflight(app, current.invocation) catch break :blk false;
            break :blk true;
        };
        const context: capture.Context = .{ .scope = current.invocation.scope, .source = .{ .session = source.owner, .revision = self.sequence, .bindings = source.bindings } };
        const cancelled = self.stopping or current.cancel.load(.acquire) or !valid;
        if (self.reader == null) {
            if (cancelled) {
                self.finish(.{ .session_id = @backingInt(source.owner.session_id), .status = if (valid) .cancelled else .rejected, .transport = .sftp, .error_code = if (valid) "CancelledBeforeDispatch" else "StaleBinding" });
                return;
            }
            const host = (self.files orelse return).file_host orelse return;
            self.reader = capture.Reader.start(self.allocator, host, context, current.invocation.call.path, if (current.invocation.call.tool == .list_remote_files) .{ .list = .{ .paged = true, .offset = current.invocation.call.offset, .expected_version = current.invocation.call.expected_version, .max_entries = current.invocation.call.max_entries } } else .{ .read = .{ .max_bytes = current.invocation.call.max_bytes, .offset = current.invocation.call.offset, .expected_version = current.invocation.call.expected_version } }) catch |err| {
                self.finish(.{ .session_id = @backingInt(source.owner.session_id), .status = .failed, .transport = .sftp, .error_code = @errorName(err) });
                return;
            };
        }
        const reader = self.reader.?;
        if (cancelled) reader.cancel();
        _ = reader.poll(if (valid) context else null);
        if (reader.cleanupReceipt() == .unknown) {
            self.finish(.{ .session_id = @backingInt(source.owner.session_id), .status = .unknown, .transport = .sftp, .local_released = false, .error_code = "SftpCleanupUnknown" });
            return;
        }
        if (!reader.terminal or !reader.retired) return;
        var captured = reader.take() orelse return;
        defer captured.release();
        defer {
            reader.deinit() catch unreachable;
            self.reader = null;
        }
        const value = captured.value().?;
        if (value.body == .failure) {
            self.finish(.{ .session_id = @backingInt(source.owner.session_id), .status = if (value.body.failure == .cancelled) .cancelled else .failed, .transport = .sftp, .error_code = projection.failureCode(value.body.failure) });
            return;
        }
        const output = projection.project(current.allocator, value, @min(current.invocation.capture_bytes, 65536)) catch |err| {
            self.finish(.{ .session_id = @backingInt(source.owner.session_id), .status = .failed, .transport = .sftp, .error_code = @errorName(err) });
            return;
        };
        defer output.deinit(current.allocator);
        self.finish(.{ .session_id = @backingInt(source.owner.session_id), .status = .succeeded, .transport = .sftp, .stdout = output.stdout, .stderr = output.stderr, .truncated = output.truncated });
    }
    pub fn pendingApproval(_: *Bridge) ?adapter.Approval {
        return null;
    }
    pub fn decide(_: *Bridge, _: u64, _: [32]u8, _: bool) !void {
        return error.StaleApproval;
    }
    pub fn stopOwner(self: *Bridge, owner: identity.SessionHandle) sessions.CloseReceipt {
        self.lock();
        defer self.mutex.unlock();
        const source = self.capture orelse return .released;
        if (!source.owner.eql(owner)) return .released;
        self.stopping = true;
        if (self.exchange) |exchange| exchange.cancel.store(true, .release);
        if (self.reader) |reader| {
            reader.cancel();
            return .awaiting;
        }
        return if (self.exchange != null) .awaiting else .released;
    }
    pub fn writeRisk(_: *Bridge, _: identity.SessionHandle) bool {
        return false;
    }
    pub fn closeImpact(self: *Bridge, owner: identity.SessionHandle) @import("../../../../host/group_close_controller.zig").Impact {
        return .{ .ai = if (self.capture != null and self.capture.?.owner.eql(owner) and self.exchange != null) self.sequence else 0 };
    }
    pub fn shutdown(self: *Bridge, app: ?*App) void {
        if (self.capture) |source| _ = self.stopOwner(source.owner);
        if (app) |host| self.pump(host);
    }
    pub fn clear(self: *Bridge) !void {
        if (self.exchange != null or self.reader != null) return error.ToolCleanupPending;
        if (self.capture) |source| self.allocator.free(source.target);
        self.capture = null;
    }
    pub fn deinit(self: *Bridge) void {
        self.clear() catch unreachable;
        self.* = undefined;
    }
    pub fn assembleContext(a: std.mem.Allocator, raw: *anyopaque, owner: identity.SessionHandle, _: u32, redact: bool) !@import("../../../../ai/assembler.zig").Assembled {
        const app: *App = @ptrCast(@alignCast(raw));
        const manifest = app.sessions.manifestFor(owner) orelse return error.StaleSession;
        const text = try std.fmt.allocPrint(a, "provider={s} session_id={d} generation={d}\nRemote file session. Only directory and bounded text-file tools are available.\n", .{ if (redact) "<redacted>" else manifest.display_name, @backingInt(owner.session_id), owner.generation });
        return .{ .text = text, .tokens = @import("../../../../ai/card.zig").estimateTokens(text.len), .truncated = false };
    }
};
pub fn createAdapter(a: std.mem.Allocator) !adapter.Adapter {
    return adapter.Adapter.create(Bridge, App, a);
}
fn pause() void {
    var duration: std.c.timespec = .{ .sec = 0, .nsec = 5 * std.time.ns_per_ms };
    _ = std.c.nanosleep(&duration, null);
}

/// `host.tab_context` 的文件卡片查询（`card_ai.file.query.run`）：远端窗格当前目录的目录项，按 `limit` 分页；游标的修订号是目录修订号，目录
/// 换了或刷新过就返回 `SnapshotChanged`。只读文件工作区的内存投影。
pub fn fileCardQuery(raw: *anyopaque, owner: identity.SessionHandle, args: CardAi.QueryArgs, allocator: std.mem.Allocator) anyerror!CardAi.QueryResult {
    const app: *App = @ptrCast(@alignCast(raw));
    for (app.workspace.tabs.items) |item| {
        if (item.content_owner == .session and item.content_owner.session.eql(owner)) break;
    } else return error.StaleSession;
    if (args.max_lines != null) return error.UnsupportedParameter;
    const host: *@import("../../../files/host/file_application_host.zig").Host = @ptrCast(@alignCast(args.file_host orelse return error.ServiceUnavailable));
    const presentation = host.presentation orelse return error.ServiceUnavailable;
    const model = presentation.modelFor(owner) orelse return error.ServiceUnavailable;
    const current = model.projection() orelse return error.FileProjectionUnavailable;
    if (!current.owner.eql(owner)) return error.StaleSession;
    return listEntries(allocator, current.panes[1], args);
}

const CardAi = @import("../../../../host/card_types.zig").CardAi;
/// `pane` 是文件工作区的窗格投影（`PaneProjection`：`stamp.directory_revision`、`resolved_path`、`state`、`failure`、`entries`）。
fn listEntries(allocator: std.mem.Allocator, pane: anytype, args: CardAi.QueryArgs) !CardAi.QueryResult {
    const revision = pane.stamp.directory_revision;
    if (args.cursor) |offset| {
        if ((args.cursor_revision orelse 0) != revision or offset > pane.entries.len) return error.SnapshotChanged;
    }
    const start: usize = @intCast(args.cursor orelse 0);
    const page = args.limit orelse 50;
    var text: std.ArrayList(u8) = .empty;
    errdefer text.deinit(allocator);
    try text.print(allocator, "Remote directory {s} ({s}), {d} entries", .{ pane.resolved_path, @tagName(pane.state), pane.entries.len });
    if (pane.failure.len != 0) try text.print(allocator, "; failure: {s}", .{pane.failure});
    try text.print(allocator, "; showing from #{d}:\n", .{start + 1});
    var index = start;
    while (index < pane.entries.len and index - start < page) : (index += 1) {
        const entry = pane.entries[index];
        var line: std.ArrayList(u8) = .empty;
        defer line.deinit(allocator);
        try line.print(allocator, "{s} {s}", .{ switch (entry.kind) {
            .directory => "dir ",
            .file => "file",
            .symlink => "link",
            .unknown => "?   ",
        }, entry.display_name });
        if (entry.size) |size| try line.print(allocator, " {d}B", .{size});
        if (entry.modified_label.len != 0) try line.print(allocator, " {s}", .{entry.modified_label});
        try line.append(allocator, '\n');
        // 停在条目边界：下一页从第一条放不下的条目开始，不会跳过。
        if (index > start and text.items.len + line.items.len > args.budget_bytes) break;
        try text.appendSlice(allocator, line.items);
    }
    const more = index < pane.entries.len;
    return .{ .text = try text.toOwnedSlice(allocator), .truncated = more, .next_offset = if (more) index else null, .revision = revision };
}

test "file card query pages directory entries at entry boundaries and rejects a changed directory" {
    const a = std.testing.allocator;
    // 与 `file_workspace_view.Entry` / `PaneProjection` 同名字段的最小替身（本文件不跨 feature 引用视图类型）。
    const Entry = struct { display_name: []const u8, kind: enum { file, directory, symlink, unknown }, size: ?u64 = null, modified_label: []const u8 = "" };
    const FakePane = struct { stamp: struct { directory_revision: u64 }, resolved_path: []const u8, state: enum { ready, empty }, failure: []const u8 = "", entries: []const Entry };
    const entries = [_]Entry{
        .{ .display_name = "a", .kind = .directory },
        .{ .display_name = "b.txt", .kind = .file, .size = 12 },
        .{ .display_name = "c", .kind = .symlink },
    };
    const pane: FakePane = .{ .stamp = .{ .directory_revision = 9 }, .resolved_path = "/srv", .state = .ready, .entries = &entries };
    const first = try listEntries(a, pane, .{ .limit = 2, .budget_bytes = 4096, .redact = false, .context_window = 8192 });
    defer a.free(first.text);
    try std.testing.expect(std.mem.indexOf(u8, first.text, "Remote directory /srv (ready), 3 entries") != null);
    try std.testing.expect(std.mem.indexOf(u8, first.text, "dir  a\n") != null and std.mem.indexOf(u8, first.text, "file b.txt 12B\n") != null and std.mem.indexOf(u8, first.text, "link c") == null);
    try std.testing.expect(first.next_offset.? == 2 and first.revision == 9 and first.truncated);
    const second = try listEntries(a, pane, .{ .limit = 2, .cursor = 2, .cursor_revision = 9, .budget_bytes = 4096, .redact = false, .context_window = 8192 });
    defer a.free(second.text);
    try std.testing.expect(std.mem.indexOf(u8, second.text, "link c\n") != null and second.next_offset == null and !second.truncated);
    // 目录换了（修订号不同）或偏移越界：SnapshotChanged，让模型从头读。
    try std.testing.expectError(error.SnapshotChanged, listEntries(a, pane, .{ .cursor = 2, .cursor_revision = 8, .budget_bytes = 4096, .redact = false, .context_window = 8192 }));
    try std.testing.expectError(error.SnapshotChanged, listEntries(a, pane, .{ .cursor = 9, .cursor_revision = 9, .budget_bytes = 4096, .redact = false, .context_window = 8192 }));
    // 预算只够头部与一条：停在条目边界，下一页从第二条开始。
    const tight = try listEntries(a, pane, .{ .budget_bytes = 60, .redact = false, .context_window = 8192 });
    defer a.free(tight.text);
    try std.testing.expectEqual(@as(?u64, 1), tight.next_offset);
}
