//! 主窗口传输宿主 TransferHost 及其回调（P2 自 src/main.zig 原样拆出）。

const std = @import("std");
const applog = @import("../../../platform/applog.zig");
const ui = @import("ui");
const ws = @import("../../workspace/view/workspace.zig");
const transfer_mod = @import("../../../transfer/manager.zig");
const sftp_engine_mod = @import("../../../transfer/sftp_engine.zig");
const transfer_panel_mod = @import("../view/transfer_panel.zig");
const transfer_manager_view = @import("../view/transfer_manager_view.zig");
const transfer_conflict_view = @import("../view/transfer_conflict_view.zig");
const TerminalViewNode = @import("../../terminal/view/terminal_view.zig").TerminalViewNode;
const application_host_mod = @import("../../shell/host/application_host.zig");
const file_application_mod = @import("../../files/host/file_application_host.zig");
const transfer_dispatch_mod = @import("../../../transfer/engine_dispatch.zig");
const retained_store_mod = @import("../../../host/retained_transfer_store.zig");
const retained_runtime_mod = @import("../../../host/file_transfer_runtime.zig");
const task_domain_mod = @import("../../../host/application_task_domain.zig");
const process_state = @import("../../../app/process_state.zig");
const SettingsHost = @import("../../settings/host/settings_host.zig").SettingsHost;

/// Refresh cadence of the open global transfer list and of the status-bar ticker (at most every 250 ms). A poll
/// inside the window answers how long to wait, so the caller schedules a redraw for the trailing refresh instead of
/// dropping it: the last state change of a job (已暂停 / 已完成) can land just after a refresh, and nothing else may
/// wake the window.
pub const ManagerRefresh = struct {
    pub const interval_ms: u64 = 250;
    last_ms: u64 = 0,
    pub const Step = union(enum) { refresh, wait_ms: u64 };
    pub fn step(self: *ManagerRefresh, now: u64) Step {
        const elapsed = now -| self.last_ms;
        if (elapsed >= interval_ms) {
            self.last_ms = now;
            return .refresh;
        }
        return .{ .wait_ms = interval_ms - elapsed };
    }
    /// As soon as the manager has no pending work, paint the final projection on this frame without
    /// scheduling another sample. A theme publication also takes effect immediately.
    pub fn presentationStep(self: *ManagerRefresh, now: u64, busy: bool, repaint_due: bool) Step {
        if (!busy or repaint_due) {
            self.last_ms = now;
            return .refresh;
        }
        return self.step(now);
    }
};

pub const TransferHost = struct {
    files: *file_application_mod.Host,
    tasks: *task_domain_mod.Domain,
    retained_store: *retained_store_mod.Store,
    dispatch: *transfer_dispatch_mod.Dispatch,
    application: *application_host_mod.ApplicationHost,
    file_binding: ?@import("../../../host/session_host.zig").ServiceHandle = null,
    file_conflict_context: ?transfer_mod.Conflict.Context = null,
    allocator: std.mem.Allocator,
    cx: *ui.Cx,
    workspace: *ws.Workspace,
    panel: *transfer_panel_mod.Panel,
    manager: *transfer_mod.Manager,
    notification_window: ?@import("../../../host/notification_host.zig").WindowId = null,
    last_job: ?transfer_mod.JobId = null,
    /// 状态栏进度行容器（mountStatusBar 注入）。
    progress_slot: ?*ui.Node = null,
    /// 终态失败只报一次。
    failure_reported: std.atomic.Value(u8) = .init(0),
    settings: ?*SettingsHost = null,
    manager_panel: ?*transfer_manager_view.Panel = null,
    seen_transfers: std.AutoHashMapUnmanaged(transfer_mod.JobId, void) = .empty,
    status_transfer: ?*@import("../../shell/view/status_transfer_view.zig").View = null,
    toolbar_progress: ?*@import("../view/transfer_toolbar_view.zig").View = null,
    ticker_scope: ?transfer_manager_view.Scope = null,
    ticker_scope_arena: ?std.heap.ArenaAllocator = null,
    ticker_refresh: ManagerRefresh = .{},
    ticker_started_ms: u64 = 0,
    conflict_view: ?*transfer_conflict_view.View = null,
    conflict_job: ?transfer_mod.JobId = null,
    conflict_manual: bool = false,
    conflict_presented: bool = false,
    manager_visible: bool = false,
    manager_open_requested: bool = false,
    cwd_pending: ?struct { owner: @import("../../../host/identity.zig").SessionHandle, started: u64 } = null,
    reveal_requested: ?struct { job: transfer_mod.JobId, attempt: u8, owner: @import("../../../host/identity.zig").SessionHandle } = null,
    sftp_open_requested: bool = false,
    manager_refresh: ManagerRefresh = .{},
    session_id: ?ws.SessionId = null,
    session_owner: ?@import("../../../host/identity.zig").SessionHandle = null,

    command_picker: ?CommandPicker = null,
    picker_running: bool = false,

    const CommandPicker = struct {
        owner: @import("../../../host/identity.zig").SessionHandle,
        operation: @import("../../../host/operation.zig").OperationKey,
        capability_revision: u64,
        command_id: ?u64,
        mode: transfer_panel_mod.Data.Mode,
        source: [:0]u8,
        started: u64,
        requested_frame: u64,
    };

    extern fn zw_pick_upload_files(initial: [*:0]const u8, context: *anyopaque, receive: *const fn (*anyopaque, [*:0]const u8) callconv(.c) c_int) c_int;

    const PickedFiles = struct {
        allocator: std.mem.Allocator,
        paths: std.ArrayList([]const u8) = .empty,
        fn receive(raw: *anyopaque, path: [*:0]const u8) callconv(.c) c_int {
            const self: *PickedFiles = @ptrCast(@alignCast(raw));
            const owned = self.allocator.dupe(u8, std.mem.span(path)) catch return 0;
            self.paths.append(self.allocator, owned) catch {
                self.allocator.free(owned);
                return 0;
            };
            return 1;
        }
        fn deinit(self: *PickedFiles) void {
            for (self.paths.items) |path| self.allocator.free(path);
            self.paths.deinit(self.allocator);
        }
    };

    fn finishPicker(self: *TransferHost, request: CommandPicker, state: TerminalViewNode.CommandRecordState, message: []const u8) void {
        if (request.command_id) |id| {
            for (self.workspace.tabs.items) |tab| {
                if (tab.terminal) |*terminal| if (terminal.commandRecordOwner()) |owner| {
                    if (owner.eql(request.owner)) {
                        _ = terminal.finishCommandRecord(owner, id, state, message);
                        // AppKit's modal picker temporarily owns the first responder.
                        // Restore only this captured session when it is still current.
                        if (state != .pending) if (self.workspace.active_tab) |index| {
                            if (index < self.workspace.tabs.items.len and self.workspace.tabs.items[index] == tab) terminal.focus();
                        };
                        self.cx.requestRedraw();
                        return;
                    }
                };
            }
        }
        self.workspace.status(message);
    }

    fn validatePicker(self: *TransferHost, request: CommandPicker) !void {
        const state = self.application.sessions.queryState(request.owner) orelse return error.TransferOwnerExpired;
        const capabilities = (try self.application.sessions.capabilitySnapshot(request.owner)) orelse return error.TransferOwnerExpired;
        if (state.lifecycle != .attached) return error.TransferSessionNotAttached;
        if (!state.create_operation.eql(request.operation)) return error.TransferOwnerExpired;
        if (capabilities.revision != request.capability_revision) return error.StaleCapabilityRevision;
        // The SSH transfer service is opened lazily after selection. Require
        // declaration and authorization here, not an already-open SFTP channel.
        const transfer_capability = for (capabilities.services) |service| {
            if (std.mem.eql(u8, service.key.name, "transfer")) break service;
        } else return error.TransferUnsupported;
        if (!transfer_capability.declared or !transfer_capability.authorized) return error.TransferNotAuthorized;
        const tab = self.workspace.sessionTab(self.application.legacyForHandle(request.owner) orelse return error.TransferOwnerExpired) orelse return error.TransferOwnerExpired;
        if (tab.closing or tab.isCard() or tab.failed or tab.runtime == null) return error.TransferOwnerExpired;
    }

    pub fn requestCommandTransfer(self: *TransferHost, index: usize, mode: transfer_panel_mod.Data.Mode, source: ?[]const u8) !void {
        if (self.command_picker != null or self.picker_running) return error.FileSelectionInProgress;
        const tab = self.workspace.tabs.items[index];
        const owner = switch (tab.content_owner) {
            .session => |value| value,
            else => return error.TransferOwnerExpired,
        };
        const state = self.application.sessions.queryState(owner) orelse return error.TransferOwnerExpired;
        const capabilities = (try self.application.sessions.capabilitySnapshot(owner)) orelse return error.TransferOwnerExpired;
        const request: CommandPicker = .{
            .owner = owner,
            .operation = state.create_operation,
            .capability_revision = capabilities.revision,
            .command_id = if (self.workspace.command_output) |terminal| terminal.active_command_record else null,
            .mode = mode,
            .source = try self.allocator.dupeSentinel(u8, source orelse "", 0),
            .started = wallClockMsTransfer(),
            .requested_frame = self.cx.frame_count,
        };
        errdefer self.allocator.free(request.source);
        try self.validatePicker(request);
        try self.validateNewTransferPolicy();
        if (mode == .upload or !std.fs.path.isAbsolute(request.source)) try tab.runtime.?.workerPtr().requestCurrentDirectory();
        self.command_picker = request;
        self.finishPicker(request, .pending, if (mode == .upload) "正在读取上传目标目录…" else "正在准备下载并选择保存位置…");
        self.cx.scheduleRedrawAfterNs(16 * std.time.ns_per_ms);
    }

    fn runCommandPicker(self: *TransferHost, request: CommandPicker, remote_dir: []const u8) !?[]u8 {
        try self.validatePicker(request);
        const policy = self.workspace.app_config.transfer;
        var files: PickedFiles = .{ .allocator = self.allocator };
        defer files.deinit();
        var buffer: [4096]u8 = undefined;
        var local_dir: []const u8 = "";
        if (request.mode == .upload) {
            const result = zw_pick_upload_files(request.source, &files, PickedFiles.receive);
            if (result < 0) return error.FileSelectionFailed;
            if (result == 0 or files.paths.items.len == 0) return null;
        } else {
            const sdk = self.cx.system_sdk orelse return error.NativeDialogUnavailable;
            const home = try @import("../../../platform/user_dirs.zig").home(self.allocator);
            defer self.allocator.free(home);
            const initial = try @import("../../../config/transfer_defaults.zig").downloadDirectory(self.allocator, policy.download_dir, home);
            defer self.allocator.free(initial);
            local_dir = (try @import("../../../platform/dialog_port.zig").run(sdk, .{ .kind = .pick_folder, .title = "选择下载保存位置", .default_path = initial }, &buffer)) orelse return null;
        }
        // AppKit runs a nested event loop. Revalidate the captured session,
        // rather than using whichever tab happens to be active afterwards.
        try self.validatePicker(request);
        const sources: []const []const u8 = if (request.mode == .upload) files.paths.items else &.{request.source};
        if (request.mode == .upload) if (request.command_id) |id| {
            for (self.workspace.tabs.items) |tab| {
                if (tab.terminal) |*terminal| if (terminal.commandRecordOwner()) |owner| {
                    if (owner.eql(request.owner)) {
                        _ = terminal.updateUploadCommandRecord(owner, id, sources);
                        break;
                    }
                };
            }
        };
        const spec = try transfer_panel_mod.buildSpec(.{
            .mode = request.mode,
            .owner = request.owner,
            .sources = sources,
            .remote_dir = remote_dir,
            .local_dir = local_dir,
            .resume_transfer = policy.@"resume",
            .md5 = policy.verify_md5,
        });
        const message = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{
            if (request.mode == .upload) "已加入上传队列 · 上传到远程目录：" else "已加入下载队列 · 保存到本地目录：",
            if (request.mode == .upload) spec.remote_dir else spec.local_dir,
        });
        errdefer self.allocator.free(message);
        try self.submitSessionTransfer(request.owner, spec);
        return message;
    }

    fn pollCommandPicker(self: *TransferHost) void {
        const request = self.command_picker orelse return;
        // The native modal blocks Metal presentation. Let a full frame paint
        // the dismissed command palette before entering AppKit's modal loop.
        if (self.cx.frame_count <= request.requested_frame +| 1) {
            self.cx.scheduleRedrawAfterNs(16 * std.time.ns_per_ms);
            return;
        }
        self.validatePicker(request) catch |err| {
            self.command_picker = null;
            defer self.allocator.free(request.source);
            self.finishPicker(request, .failure, @errorName(err));
            return;
        };
        var cwd: ?[]u8 = null;
        defer if (cwd) |value| self.allocator.free(value);
        if (request.mode == .upload or !std.fs.path.isAbsolute(request.source)) {
            const tab = self.workspace.sessionTab(self.application.legacyForHandle(request.owner).?).?;
            cwd = tab.runtime.?.workerPtr().copyCwd(self.allocator) catch null;
            if (cwd == null or cwd.?.len == 0) {
                if (wallClockMsTransfer() -| request.started < 5000) {
                    self.cx.scheduleRedrawAfterNs(50 * std.time.ns_per_ms);
                    return;
                }
                self.command_picker = null;
                defer self.allocator.free(request.source);
                self.finishPicker(request, .failure, "无法读取当前远程目录，请在终端空闲时重试传输指令");
                return;
            }
        }
        self.command_picker = null;
        defer self.allocator.free(request.source);
        self.picker_running = true;
        defer self.picker_running = false;
        const message = self.runCommandPicker(request, cwd orelse "") catch |err| {
            self.finishPicker(request, .failure, @errorName(err));
            return;
        };
        defer if (message) |value| self.allocator.free(value);
        self.finishPicker(request, .success, message orelse "已取消选择，未添加传输任务");
    }

    const AuxiliaryConnection = task_domain_mod.AuxiliaryConnection;

    const SharedConnection = task_domain_mod.SharedConnection;

    fn ensureShared(self: *TransferHost, owner: @import("../../../host/identity.zig").SessionHandle) !@import("../../../host/session_host.zig").SharedTransferStart {
        for (self.tasks.shared_connections.items) |connection| if (connection.owner.eql(owner) and !connection.released) {
            if (!self.application.sessions.bindingIsLive(connection.binding)) return error.TransferNotReady;
            try self.files.mux.?.register(connection.binding, connection.service.engine());
            try self.files.mux.?.setCleanupGuard(connection.binding, connection.service.cleanupGuard());
            return .{ .binding = connection.binding, .key = connection.key };
        };
        try self.tasks.shared_connections.ensureUnusedCapacity(self.allocator, 1);
        const legacy = self.application.legacyForHandle(owner) orelse return error.TransferOwnerExpired;
        const tab = self.workspace.sessionTab(legacy) orelse return error.TransferOwnerExpired;
        const runtime = tab.runtime orelse return error.TransferOwnerExpired;
        if (runtime.torn_down) return error.TransferOwnerExpired;
        const start = try self.application.sessions.beginSharedTransfer(owner);
        const service = try runtime.workerPtr().transferService(start.binding);
        self.tasks.shared_connections.appendAssumeCapacity(.{ .owner = owner, .binding = start.binding, .key = start.key, .service = service });
        if (!self.application.sessions.sharedTransferReady(start.binding, start.key)) return error.StaleBinding;
        try self.files.mux.?.register(start.binding, service.engine());
        try self.files.mux.?.setCleanupGuard(start.binding, service.cleanupGuard());
        return start;
    }

    fn pollShared(self: *TransferHost) !void {
        for (self.tasks.shared_connections.items) |*connection| {
            if (connection.released) continue;
            if (connection.service.faulted.load(.acquire)) {
                _ = self.application.sessions.sharedTransferReleased(connection.binding, connection.key, .awaiting);
                if (connection.fault_retained) continue;
                if (try self.retainShared(connection, connection.key, true) == .released) connection.fault_retained = true;
            }
        }
    }

    fn ensureAuxiliary(self: *TransferHost, owner: @import("../../../host/identity.zig").SessionHandle) !@import("../../../host/session_host.zig").AuxiliaryTransferStart {
        try self.tasks.auxiliary_connections.ensureUnusedCapacity(self.allocator, 1);
        const start = try self.application.sessions.beginAuxiliaryTransfer(owner);
        var exists = false;
        for (self.tasks.auxiliary_connections.items) |connection| if (!connection.released and connection.binding.eql(start.binding)) {
            if (connection.closing) return error.CleanupNotReleased;
            exists = true;
            break;
        };
        if (!exists) {
            self.tasks.auxiliary_connections.appendAssumeCapacity(.{ .owner = owner, .binding = start.binding, .key = start.key });
            const hooks = self.files.transfer_host.?.hooks();
            hooks.start(hooks.context, .{ .binding = start.binding, .source = .{ .owner = owner, .create_key = start.key, .open_key = start.key, .spec = start.spec } }) catch |err| {
                self.tasks.auxiliary_connections.items[self.tasks.auxiliary_connections.items.len - 1].closing = true;
                return err;
            };
        }
        return start;
    }

    // Reject an invalid new policy before connection creation or authentication.
    // Retained resume uses the original frozen JobSpec and never enters here.
    fn validateNewTransferPolicy(self: *const TransferHost) !void {
        const policy = self.workspace.app_config.transfer;
        try @import("../../../transfer/window_policy.zig").validateWindowPolicy(policy.chunk_kb, policy.window_chunks, policy.max_tasks);
    }

    fn submitSessionTransfer(self: *TransferHost, owner: @import("../../../host/identity.zig").SessionHandle, spec: transfer_mod.JobSpec) !void {
        try self.validateNewTransferPolicy();
        try self.tasks.job_owners.ensureUnusedCapacity(self.allocator, 1);
        if (self.tasks.next_transfer_intent == std.math.maxInt(u64)) return error.IntentIdExhausted;
        const dedicated = self.workspace.app_config.transfer.dedicated_connection;
        const binding = if (dedicated) (try self.ensureAuxiliary(owner)).binding else (try self.ensureShared(owner)).binding;
        const original = self.application.sessions.queryState(owner) orelse return error.StaleSession;
        const remote: @import("../../../transfer/conflict.zig").Endpoint = .{ .sftp = .{
            .binding_id = binding.binding_id,
            .binding_generation = binding.binding_generation,
            .resource_owner = binding.resource_owner,
            .origin_session = owner,
            .connection_snapshot_id = original.create_operation.operation_id,
        } };
        const local: @import("../../../transfer/conflict.zig").Endpoint = .{ .local_fs = self.files.local_service.?.endpoint };
        var captured = spec;
        captured.chunk_kb = self.workspace.app_config.transfer.chunk_kb;
        captured.window_chunks = self.workspace.app_config.transfer.window_chunks;
        captured.pacing_kbps = if (dedicated) 0 else self.workspace.app_config.transfer.shared_pacing_kbps;
        captured.session_id = @backingInt(owner.session_id);
        captured.transfer_binding = binding;
        captured.conflict_context = .{
            .intent_id = self.tasks.next_transfer_intent,
            .original_owner = owner,
            .resource_owner = binding.resource_owner,
            .source_endpoint = if (spec.direction == .upload) local else remote,
            .target_endpoint = if (spec.direction == .upload) remote else local,
        };
        self.tasks.next_transfer_intent += 1;
        const id = if (dedicated) try self.manager.enqueueWaitingBinding(captured) else try self.manager.enqueue(captured);
        self.tasks.job_owners.appendAssumeCapacity(.{ .job = id, .owner = owner });
        if (@import("../../../platform/runtime_mode.zig").automation) std.debug.print("FILE_SESSION_TRANSFER_ENQUEUED {{\"job\":{d},\"owner_id\":{d},\"owner_generation\":{d},\"binding_id\":{d},\"binding_generation\":{d},\"dedicated_connection\":{},\"pacing_kbps\":{d}}}\n", .{ id, @backingInt(owner.session_id), owner.generation, binding.binding_id, binding.binding_generation, dedicated, captured.pacing_kbps });
        self.last_job = id;
        self.panel.hide();
        self.cx.scheduleRedrawAfterNs(16 * std.time.ns_per_ms);
    }

    fn pollAuxiliary(self: *TransferHost) !void {
        const hooks = self.files.transfer_host.?.hooks();
        for (self.tasks.auxiliary_connections.items) |*connection| {
            if (connection.released) continue;
            if (self.files.transfer_host.?.fault(connection.binding, connection.key)) |fault| {
                if (try self.retainFault(fault) == .released) connection.released = true;
                continue;
            }
            const state = self.application.sessions.queryState(connection.owner) orelse continue;
            // The original close hook owns pause/export and exact release.
            if (state.lifecycle == .closing or state.lifecycle == .cleanup_unknown) continue;
            if (state.lifecycle == .closed) connection.closing = true;
            if (connection.closing) {
                const receipt = hooks.close(hooks.context, .{ .owner = connection.owner, .binding = connection.binding, .create_key = connection.key, .operation = connection.key });
                if (receipt == .released) {
                    _ = try self.application.sessions.auxiliaryTransferReleased(connection.binding, connection.key, .released);
                    connection.released = true;
                }
                continue;
            }
            var needed = false;
            for (0..self.manager.count()) |index| {
                const progress = self.manager.progressAt(index).?;
                const binding = self.manager.transferBinding(progress.job) orelse continue;
                if (binding.eql(connection.binding) and self.manager.retainedOwner(progress.job) == null and (progress.job_cleanup != .released or (progress.state != .succeeded and progress.state != .failed and progress.state != .cancelled))) {
                    needed = true;
                    break;
                }
            }
            if (!needed) {
                connection.closing = true;
                continue;
            }
            if (!self.application.sessions.bindingIsLive(connection.binding)) {
                switch (hooks.poll(hooks.context, connection.binding, connection.key)) {
                    .pending => continue,
                    .ready => |binding| {
                        if (!binding.eql(connection.binding) or !try self.application.sessions.auxiliaryTransferReady(binding, connection.key)) return error.StaleBinding;
                        continue;
                    },
                    .failed => |failure| {
                        const problem = transfer_mod.StartupFailure.init(failure.code, failure.stage);
                        for (0..self.manager.count()) |index| {
                            const progress = self.manager.progressAt(index).?;
                            const binding = self.manager.transferBinding(progress.job) orelse continue;
                            if (binding.eql(connection.binding) and progress.state == .queued and progress.attempt == 0) {
                                try self.manager.failWaitingBinding(progress.job, binding, problem);
                                applog.warn(.transfer, "connection startup failed job={d} binding={d} generation={d} stage={s} code={s}", .{ progress.job, binding.binding_id, binding.binding_generation, problem.stage(), problem.code() });
                            }
                        }
                        connection.closing = true;
                        var message: [512]u8 = undefined;
                        self.workspace.statusFailure(std.fmt.bufPrint(&message, "{s}（{s}），请重试", .{ problem.message(), problem.code() }) catch problem.message());
                        continue;
                    },
                }
            }
            if (!self.files.mux.?.isRegistered(connection.binding)) continue;
            for (0..self.manager.count()) |index| {
                const progress = self.manager.progressAt(index).?;
                const binding = self.manager.transferBinding(progress.job) orelse continue;
                if (binding.eql(connection.binding) and progress.attempt == 0 and (progress.state == .queued or progress.state == .paused) and self.manager.retainedOwner(progress.job) == null) try self.manager.releaseBindingWait(progress.job, binding);
            }
        }
    }

    const RetainedConnection = task_domain_mod.RetainedConnection;

    fn resumeRetained(self: *TransferHost, id: transfer_mod.JobId) !void {
        const owner = self.manager.retainedOwner(id) orelse return error.UnknownRetainedJob;
        const progress = self.manager.progress(id) orelse return error.UnknownJob;
        if (progress.state != .paused or progress.job_cleanup != .released) return error.InvalidState;
        var exists = false;
        for (self.tasks.retained_connections.items) |connection| if (!connection.released and std.meta.eql(connection.owner, owner)) {
            if (connection.closing) return error.CleanupNotReleased;
            exists = true;
            break;
        };
        if (!exists) {
            try self.tasks.retained_connections.ensureUnusedCapacity(self.allocator, 1);
            const start = try self.application.sessions.beginRetainedTransfer(owner.id, owner.original_handle);
            self.tasks.retained_connections.appendAssumeCapacity(.{ .owner = owner, .binding = start.binding, .key = start.key });
            const hooks = self.files.transfer_host.?.hooks();
            hooks.start(hooks.context, .{ .binding = start.binding, .source = .{
                .owner = owner.original_handle,
                .retained_owner = owner.id,
                .create_key = start.key,
                .open_key = start.key,
                .spec = start.spec,
            } }) catch |err| {
                self.tasks.retained_connections.items[self.tasks.retained_connections.items.len - 1].closing = true;
                return err;
            };
        }
        try self.manager.queueRetainedResume(id, progress.attempt, owner);
    }

    const RetainedImport = struct {
        host: *TransferHost,
        connection: *RetainedConnection,
        checkpoint: ?*sftp_engine_mod.OwnedCheckpoint,
        original: transfer_mod.JobSpec,
        job_id: transfer_mod.JobId,
        attempt: u8,
        spec: transfer_mod.JobSpec,
        fn native(raw: *anyopaque) anyerror!transfer_mod.EngineJobId {
            const self: *RetainedImport = @ptrCast(@alignCast(raw));
            if (self.checkpoint) |checkpoint| return self.host.files.transfer_host.?.importPaused(self.connection.binding, self.connection.key, checkpoint, self.spec);
            return self.host.files.transfer_host.?.startRetainedDraft(self.connection.binding, self.connection.key, .{ .original = self.original, .job_id = self.job_id, .attempt = self.attempt, .next = self.spec });
        }
        fn mux(raw: *anyopaque) anyerror!transfer_mod.EngineJobId {
            const self: *RetainedImport = @ptrCast(@alignCast(raw));
            return self.host.files.mux.?.importPaused(self.connection.binding, self, native);
        }
    };

    fn retainedConnectionNeeded(self: *TransferHost, connection: RetainedConnection) bool {
        for (0..self.manager.count()) |index| {
            const progress = self.manager.progressAt(index).?;
            const owner = self.manager.retainedOwner(progress.job) orelse continue;
            if (!std.meta.eql(owner, connection.owner)) continue;
            if (self.manager.engineJob(progress.job) == null) {
                if (progress.state == .queued) return true;
            } else if (self.manager.transferBinding(progress.job)) |binding| {
                if (binding.eql(connection.binding) and (progress.job_cleanup != .released or (progress.state != .succeeded and progress.state != .failed and progress.state != .cancelled))) return true;
            }
        }
        return false;
    }

    fn pollRetained(self: *TransferHost) !void {
        _ = try self.retained_store.poll();
        const hooks = self.files.transfer_host.?.hooks();
        for (self.tasks.retained_connections.items) |*connection| {
            if (connection.released) continue;
            if (self.files.transfer_host.?.fault(connection.binding, connection.key)) |fault| {
                if (try self.retainFault(fault) == .released) connection.released = true;
                continue;
            }
            if (connection.closing) {
                const receipt = hooks.close(hooks.context, .{ .owner = connection.owner.original_handle, .binding = connection.binding, .create_key = connection.key, .operation = connection.key });
                if (receipt == .released) {
                    _ = try self.application.sessions.retainedTransferReleased(connection.binding, connection.key, .released);
                    connection.released = true;
                }
                continue;
            }
            if (!self.retainedConnectionNeeded(connection.*)) {
                connection.closing = true;
                continue;
            }
            if (!self.application.sessions.bindingIsLive(connection.binding)) {
                switch (hooks.poll(hooks.context, connection.binding, connection.key)) {
                    .pending => continue,
                    .ready => |binding| {
                        if (!binding.eql(connection.binding) or !try self.application.sessions.retainedTransferReady(binding, connection.key)) return error.StaleBinding;
                        // The next FileTransferHost safeTick registers its Mux.
                        continue;
                    },
                    .failed => {
                        connection.closing = true;
                        for (0..self.manager.count()) |index| {
                            const progress = self.manager.progressAt(index).?;
                            const original = self.manager.retainedOwner(progress.job) orelse continue;
                            if (std.meta.eql(original, connection.owner) and progress.state == .queued and self.manager.engineJob(progress.job) == null) try self.manager.pause(progress.job);
                        }
                        self.workspace.statusFailure("传输连接失败，请重试");
                        continue;
                    },
                }
            }
            var live_jobs = false;
            for (0..self.manager.count()) |index| {
                const progress = self.manager.progressAt(index).?;
                const owner = self.manager.retainedOwner(progress.job) orelse continue;
                if (!std.meta.eql(owner, connection.owner)) continue;
                if (self.manager.engineJob(progress.job) != null) {
                    if (self.manager.transferBinding(progress.job)) |binding| {
                        if (binding.eql(connection.binding) and (progress.job_cleanup != .released or (progress.state != .succeeded and progress.state != .failed and progress.state != .cancelled))) live_jobs = true;
                    }
                    continue;
                }
                if (progress.state != .queued) continue;
                live_jobs = true;
                if (!self.manager.canAcceptRetainedResume(progress.job, progress.attempt)) continue;
                // Started jobs require a real checkpoint. Never-started
                // drafts use the separately validated fresh-preflight entry.
                const checkpoint = self.retained_store.checkpoint(progress.job, progress.attempt);
                if (checkpoint == null and progress.attempt != 0) {
                    try self.manager.pause(progress.job);
                    self.workspace.status("任务恢复数据不可用");
                    continue;
                }
                const frozen = self.manager.retainedSpec(progress.job, progress.attempt) orelse return error.StaleAttempt;
                var spec = frozen;
                spec.transfer_binding = connection.binding;
                if (spec.conflict_context) |*context| {
                    context.job = progress.job;
                    context.attempt = @as(u32, progress.attempt) + 1;
                    context.resource_owner = connection.binding.resource_owner;
                    switch (context.source_endpoint) {
                        .sftp => |*endpoint| {
                            endpoint.binding_id = connection.binding.binding_id;
                            endpoint.binding_generation = connection.binding.binding_generation;
                            endpoint.resource_owner = connection.binding.resource_owner;
                            endpoint.origin_session = connection.owner.original_handle;
                        },
                        else => {},
                    }
                    switch (context.target_endpoint) {
                        .sftp => |*endpoint| {
                            endpoint.binding_id = connection.binding.binding_id;
                            endpoint.binding_generation = connection.binding.binding_generation;
                            endpoint.resource_owner = connection.binding.resource_owner;
                            endpoint.origin_session = connection.owner.original_handle;
                        },
                        else => {},
                    }
                }
                try self.manager.validateRetainedResume(progress.job, progress.attempt, spec);
                var import = RetainedImport{ .host = self, .connection = connection, .checkpoint = checkpoint, .original = frozen, .job_id = progress.job, .attempt = progress.attempt, .spec = spec };
                const engine_id = self.dispatch.importBoundPaused(&import, RetainedImport.mux) catch |err| switch (err) {
                    error.TransferNotReady, error.StaleBinding => continue,
                    else => {
                        if (checkpoint == null or checkpoint.?.describe() != null) try self.manager.pause(progress.job);
                        self.workspace.statusFailure(@errorName(err));
                        continue;
                    },
                };
                try self.manager.acceptRetainedResume(progress.job, progress.attempt, spec, engine_id);
                if (checkpoint != null) try self.retained_store.consumeImported(progress.job, progress.attempt);
            }
            if (!live_jobs) connection.closing = true;
        }
    }

    const RetainedClose = task_domain_mod.RetainedClose;

    fn retainShared(self: *TransferHost, connection: *SharedConnection, key: @import("../../../host/operation.zig").OperationKey, fault: bool) !application_host_mod.CloseReceipt {
        for (self.tasks.retained_closes.items) |record| if (record.shared_binding != null and record.shared_binding.?.eql(connection.binding) and record.key.eql(key)) return self.finishSharedRetain(connection, record);
        var count: usize = 0;
        var has_jobs = false;
        for (0..self.manager.count()) |index| {
            const progress = self.manager.progressAt(index).?;
            const binding = self.manager.transferBinding(progress.job) orelse continue;
            if (!binding.eql(connection.binding) or self.manager.retainedOwner(progress.job) != null) continue;
            if (progress.state == .succeeded or progress.state == .failed or progress.state == .cancelled) {
                if (progress.job_cleanup == .unknown) return .unknown;
                if (progress.job_cleanup != .released) return .awaiting;
                continue;
            }
            has_jobs = true;
            if (progress.state == .running or progress.state == .queued or progress.state == .retry_wait) try self.manager.pause(progress.job);
            const current = self.manager.progress(progress.job).?;
            if (current.job_cleanup == .unknown) return .unknown;
            if (current.state != .paused or current.job_cleanup != .released) return .awaiting;
            if (self.manager.engineJob(progress.job)) |outer| {
                const proxy = try self.dispatch.pausedBoundRoute(outer);
                const native = try self.files.mux.?.pausedNativeId(proxy, binding);
                if (!connection.service.backend.canExportPaused(native)) return .awaiting;
                count += 1;
            }
        }
        if (!has_jobs) return self.releaseSharedRoute(connection);
        const retained_id = if (fault) try self.application.sessions.retainFaultTransferSource(connection.binding, key) else try self.application.sessions.retainTransferSource(connection.owner);
        try self.tasks.retained_closes.ensureUnusedCapacity(self.allocator, 1);
        var installed = false;
        const record = try self.allocator.create(RetainedClose);
        errdefer if (!installed) self.allocator.destroy(record);
        const jobs = try self.allocator.alloc(retained_runtime_mod.RetainJob, count);
        errdefer if (!installed) self.allocator.free(jobs);
        const owned = try self.allocator.alloc(retained_runtime_mod.RetainedJob, count);
        errdefer if (!installed) self.allocator.free(owned);
        var cursor: usize = 0;
        for (0..self.manager.count()) |index| {
            const progress = self.manager.progressAt(index).?;
            const binding = self.manager.transferBinding(progress.job) orelse continue;
            if (!binding.eql(connection.binding) or progress.state != .paused or self.manager.retainedOwner(progress.job) != null) continue;
            if (self.manager.engineJob(progress.job)) |outer| {
                const proxy = try self.dispatch.pausedBoundRoute(outer);
                const native = try self.files.mux.?.pausedNativeId(proxy, binding);
                if (!connection.service.backend.canExportPaused(native)) return error.CheckpointNotReleased;
                jobs[cursor] = .{ .job_id = progress.job, .attempt = progress.attempt, .proxy_id = proxy, .native_id = native };
                owned[cursor] = .{ .original = jobs[cursor] };
                cursor += 1;
            }
        }
        const batch = if (fault) try self.retained_store.prepareFault(connection.owner, connection.binding, key, retained_id, count) else try self.retained_store.prepareBinding(connection.owner, key, retained_id, count, connection.binding);
        record.* = .{ .owner = connection.owner, .key = key, .retained_id = retained_id, .jobs = jobs, .batch = batch, .fault_binding = if (fault) connection.binding else null, .shared_binding = connection.binding, .pending = .{ .allocator = self.allocator, .owner = connection.owner, .retained_owner = retained_id, .close_key = key, .binding = connection.binding, .jobs = owned } };
        self.tasks.retained_closes.appendAssumeCapacity(record);
        installed = true;
        return self.finishSharedRetain(connection, record);
    }

    fn releaseSharedRoute(self: *TransferHost, connection: *SharedConnection) !application_host_mod.CloseReceipt {
        connection.service.requestClose();
        const receipt: application_host_mod.CloseReceipt = switch (connection.service.closeReceipt()) {
            .released => .released,
            .awaiting => .awaiting,
            .unknown => .unknown,
        };
        if (receipt != .released) return receipt;
        self.files.mux.?.detach(connection.binding) catch |err| switch (err) {
            error.JobsActive, error.CleanupPending => return .awaiting,
            error.CleanupUnknown => return .unknown,
            error.UnknownBinding => {},
            else => return err,
        };
        if (!self.application.sessions.sharedTransferReleased(connection.binding, connection.key, .released)) return error.StaleBinding;
        try connection.service.routingReleased(connection.binding);
        connection.released = true;
        return .released;
    }

    fn finishSharedRetain(self: *TransferHost, connection: *SharedConnection, record: *RetainedClose) !application_host_mod.CloseReceipt {
        if (record.complete) return .released;
        if (record.pending) |*payload| {
            for (payload.jobs) |*job| if (job.checkpoint == null) {
                job.checkpoint = try connection.service.backend.exportPaused(job.original.native_id);
            };
            connection.service.requestClose();
            switch (connection.service.closeReceipt()) {
                .awaiting => return .awaiting,
                .unknown => return .unknown,
                .released => {},
            }
            try self.retained_store.accept(record.batch, payload);
            record.pending = null;
        }
        if (record.batch.payload != null) try self.retained_store.adopt(record.batch);
        for (0..self.manager.count()) |index| {
            const progress = self.manager.progressAt(index).?;
            const binding = self.manager.transferBinding(progress.job) orelse continue;
            if (!binding.eql(connection.binding) or progress.state != .paused) continue;
            if (self.manager.engineJob(progress.job) != null) return error.RetainedRouteNotRetired;
            try self.manager.retainPaused(progress.job, progress.attempt, null, .{ .id = record.retained_id, .original_handle = connection.owner });
        }
        try self.applyDeferredCancels(record);
        const receipt = try self.releaseSharedRoute(connection);
        if (receipt == .released) record.complete = true;
        return receipt;
    }

    fn retainFault(self: *TransferHost, fault: @import("../../../host/file_transfer_host.zig").FaultSnapshot) !application_host_mod.CloseReceipt {
        for (self.tasks.retained_closes.items) |record| if (record.fault_binding != null and record.fault_binding.?.eql(fault.binding) and record.key.eql(fault.key)) return self.finishRetainedClose(record);
        var count: usize = 0;
        for (0..self.manager.count()) |index| {
            const progress = self.manager.progressAt(index).?;
            const binding = self.manager.transferBinding(progress.job) orelse continue;
            if (!binding.eql(fault.binding)) continue;
            if (progress.state == .succeeded or progress.state == .failed or progress.state == .cancelled) {
                if (progress.job_cleanup == .unknown) return .unknown;
                if (progress.job_cleanup != .released) return .awaiting;
                continue;
            }
            if (progress.state == .running or progress.state == .queued or progress.state == .retry_wait) try self.manager.pause(progress.job);
            const paused = self.manager.progress(progress.job).?;
            if (paused.job_cleanup == .unknown) return .unknown;
            if (paused.state != .paused or paused.job_cleanup != .released) return .awaiting;
            if (self.manager.engineJob(progress.job) != null) count += 1;
        }
        const id = try self.application.sessions.retainFaultTransferSource(fault.binding, fault.key);
        try self.tasks.retained_closes.ensureUnusedCapacity(self.allocator, 1);
        var installed = false;
        const record = try self.allocator.create(RetainedClose);
        errdefer if (!installed) self.allocator.destroy(record);
        const jobs = try self.allocator.alloc(retained_runtime_mod.RetainJob, count);
        errdefer if (!installed) self.allocator.free(jobs);
        var cursor: usize = 0;
        for (0..self.manager.count()) |index| {
            const progress = self.manager.progressAt(index).?;
            const binding = self.manager.transferBinding(progress.job) orelse continue;
            if (!binding.eql(fault.binding) or progress.state != .paused) continue;
            if (self.manager.engineJob(progress.job)) |outer| {
                const proxy = try self.dispatch.pausedBoundRoute(outer);
                jobs[cursor] = .{ .job_id = progress.job, .attempt = progress.attempt, .proxy_id = proxy, .native_id = try self.files.mux.?.pausedNativeId(proxy, binding) };
                cursor += 1;
            }
        }
        const batch = try self.retained_store.prepareFault(fault.owner, fault.binding, fault.key, id, count);
        record.* = .{ .owner = fault.owner, .key = fault.key, .retained_id = id, .jobs = jobs, .batch = batch, .fault_binding = fault.binding };
        self.tasks.retained_closes.appendAssumeCapacity(record);
        installed = true;
        return self.finishRetainedClose(record);
    }

    /// The original close cannot advance until native checkpoints have moved
    /// into application storage and both original proxy routes are retired.
    pub fn retainForClose(self: *TransferHost, owner: @import("../../../host/identity.zig").SessionHandle) !application_host_mod.CloseReceipt {
        const state = self.application.sessions.queryState(owner) orelse return error.StaleSession;
        const key = state.close_operation orelse return error.StaleCloseOperation;
        for (self.tasks.shared_connections.items) |*connection| if (connection.owner.eql(owner) and !connection.released) {
            const receipt = try self.retainShared(connection, key, false);
            if (receipt != .released) return receipt;
        };
        for (self.tasks.retained_closes.items) |record| if (record.shared_binding == null and record.owner.eql(owner) and record.key.eql(key)) return self.finishRetainedClose(record);
        const backend = self.files.transfer_host orelse return error.TransferHostUnavailable;
        // Revoke automatic stale-session cancellation before waiting for pause.
        backend.prepareRetain(owner, key) catch |err| switch (err) {
            error.TransferHostClosing => {
                // Authentication failure may already be releasing the original
                // backend. Wait for that exact receipt, then retry preparation.
                const hooks = backend.hooks();
                for (self.tasks.auxiliary_connections.items) |*connection| {
                    if (!connection.owner.eql(owner) or connection.released) continue;
                    connection.closing = true;
                    const receipt = hooks.close(hooks.context, .{ .owner = owner, .binding = connection.binding, .create_key = connection.key, .operation = key });
                    if (receipt != .released) return receipt;
                    connection.released = true;
                }
                return .awaiting;
            },
            else => return err,
        };
        var count: usize = 0;
        var has_jobs = false;
        for (0..self.manager.count()) |index| {
            const progress = self.manager.progressAt(index).?;
            const original = jobOwner(self, progress.job) orelse continue;
            if (!original.eql(owner)) continue;
            if (self.manager.retainedOwner(progress.job) != null) continue;
            if (progress.state == .succeeded or progress.state == .failed or progress.state == .cancelled) {
                if (progress.job_cleanup == .unknown) return .unknown;
                if (progress.job_cleanup != .released) return .awaiting;
                continue;
            }
            has_jobs = true;
            if (progress.state == .running or progress.state == .queued or progress.state == .retry_wait) try self.manager.pause(progress.job);
            const current = self.manager.progress(progress.job).?;
            if (current.job_cleanup == .unknown) return .unknown;
            if (current.state != .paused or current.job_cleanup != .released) return .awaiting;
            if (self.manager.engineJob(progress.job) != null) count += 1;
        }
        if (!has_jobs) {
            const hooks = backend.hooks();
            for (self.tasks.auxiliary_connections.items) |*connection| {
                if (!connection.owner.eql(owner) or connection.released) continue;
                connection.closing = true;
                const receipt = hooks.close(hooks.context, .{ .owner = owner, .binding = connection.binding, .create_key = connection.key, .operation = key });
                if (receipt != .released) return receipt;
                connection.released = true;
            }
            return .released;
        }
        const retained_id = try self.application.sessions.retainTransferSource(owner);
        try self.tasks.retained_closes.ensureUnusedCapacity(self.allocator, 1);
        var installed = false;
        const record = try self.allocator.create(RetainedClose);
        errdefer if (!installed) self.allocator.destroy(record);
        const jobs = try self.allocator.alloc(retained_runtime_mod.RetainJob, count);
        errdefer if (!installed) self.allocator.free(jobs);
        var cursor: usize = 0;
        for (0..self.manager.count()) |index| {
            const progress = self.manager.progressAt(index).?;
            const original = jobOwner(self, progress.job) orelse continue;
            if (!original.eql(owner) or progress.state != .paused or self.manager.retainedOwner(progress.job) != null) continue;
            if (self.manager.engineJob(progress.job)) |outer_id| {
                const binding = self.manager.transferBinding(progress.job) orelse return error.TransferBindingRequired;
                const proxy_id = try self.dispatch.pausedBoundRoute(outer_id);
                const native_id = try self.files.mux.?.pausedNativeId(proxy_id, binding);
                jobs[cursor] = .{ .job_id = progress.job, .attempt = progress.attempt, .proxy_id = proxy_id, .native_id = native_id };
                cursor += 1;
            }
        }
        const batch = try self.retained_store.prepare(owner, key, retained_id, count);
        record.* = .{ .owner = owner, .key = key, .retained_id = retained_id, .jobs = jobs, .batch = batch };
        self.tasks.retained_closes.appendAssumeCapacity(record);
        installed = true;
        return self.finishRetainedClose(record);
    }

    fn finishRetainedClose(self: *TransferHost, record: *RetainedClose) !application_host_mod.CloseReceipt {
        if (record.complete) return .released;
        const backend = self.files.transfer_host orelse return error.TransferHostUnavailable;
        if (record.batch.payload == null) {
            const receipt = if (record.fault_binding) |binding| try backend.retainFault(binding, record.key, record.retained_id, record.jobs) else try backend.retainPaused(record.owner, record.key, record.retained_id, record.jobs);
            if (receipt != .released) return receipt;
            if (record.pending == null) record.pending = if (record.fault_binding) |binding| try backend.takeFaultRetained(binding, record.key) else try backend.takeRetained(record.owner, record.key);
            if (record.pending) |*payload| {
                // Retain the moved batch in this stable record on rejection.
                try self.retained_store.accept(record.batch, payload);
                record.pending = null;
            } else if (record.jobs.len != 0) return error.RetainedBatchMissing;
        }
        if (record.batch.payload != null) try self.retained_store.adopt(record.batch);
        for (0..self.manager.count()) |index| {
            const progress = self.manager.progressAt(index).?;
            const original = jobOwner(self, progress.job) orelse continue;
            if (!original.eql(record.owner) or progress.state != .paused or self.manager.retainedOwner(progress.job) != null) continue;
            if (record.fault_binding) |binding| {
                const current = self.manager.transferBinding(progress.job) orelse continue;
                if (!current.eql(binding)) continue;
            }
            if (self.manager.engineJob(progress.job) != null) return error.RetainedRouteNotRetired;
            try self.manager.retainPaused(progress.job, progress.attempt, null, .{ .id = record.retained_id, .original_handle = record.owner });
        }
        try self.applyDeferredCancels(record);
        record.complete = true;
        return .released;
    }

    fn applyDeferredCancels(self: *TransferHost, record: *RetainedClose) !void {
        for (record.deferred_cancel.items) |id| {
            const progress = self.manager.progress(id) orelse return error.UnknownJob;
            if (progress.state == .cancelled and progress.job_cleanup == .released) continue;
            const owner = self.manager.retainedOwner(id) orelse return error.RetainedRouteNotRetired;
            try self.retained_store.cancel(id, progress.attempt);
            try self.manager.retainedCancelReceipt(id, progress.attempt, owner, .awaiting);
        }
        record.deferred_cancel.clearRetainingCapacity();
    }

    pub fn jobOwnerLabel(raw: *anyopaque, job: transfer_mod.JobId) []const u8 {
        const self: *TransferHost = @ptrCast(@alignCast(raw));
        const owner = jobOwner(raw, job) orelse return "归属未知";
        for (self.workspace.tabs.items) |tab| if (tab.content_owner == .session and tab.content_owner.session.eql(owner)) return tab.titleSlice();
        return "原会话已关闭";
    }
    pub fn transferScopeChoices(raw: *anyopaque, a: std.mem.Allocator) ![]const transfer_manager_view.ScopeChoice {
        const self: *TransferHost = @ptrCast(@alignCast(raw));
        var choices: std.ArrayList(transfer_manager_view.ScopeChoice) = .empty;
        for (self.workspace.tabs.items) |tab| {
            if (tab.content_owner != .session) continue;
            const owner = tab.content_owner.session;
            var has_tasks = false;
            for (self.tasks.job_owners.items) |record| if (record.owner.eql(owner) and self.manager.progress(record.job) != null) {
                has_tasks = true;
                break;
            };
            if (has_tasks) try choices.append(a, .{ .label = try a.dupe(u8, tab.titleSlice()), .scope = .{ .session = owner } });
        }
        return choices.items;
    }

    pub fn jobOwner(raw: *anyopaque, job: transfer_mod.JobId) ?@import("../../../host/identity.zig").SessionHandle {
        const self: *TransferHost = @ptrCast(@alignCast(raw));
        for (self.tasks.job_owners.items) |record| if (record.job == job) return record.owner;
        return null;
    }

    const RevealLocation = struct { direction: transfer_mod.Direction, remote_dir: []const u8, local_dir: []const u8 };
    fn revealSpec(self: *TransferHost, job_id: transfer_mod.JobId, attempt: u8) ?RevealLocation {
        for (self.manager.jobs.items) |job| if (job.id == job_id) return .{ .direction = job.spec.direction, .remote_dir = job.spec.remote_dir, .local_dir = job.spec.local_dir };
        const spec = self.manager.retainedSpec(job_id, attempt) orelse return null;
        return .{ .direction = spec.direction, .remote_dir = spec.remote_dir, .local_dir = spec.local_dir };
    }
    pub fn canReveal(raw: *anyopaque, job_id: transfer_mod.JobId) bool {
        const self: *TransferHost = @ptrCast(@alignCast(raw));
        if (self.workspace.shutting_down) return false;
        const progress = self.manager.progress(job_id) orelse return false;
        if (progress.state != .succeeded) return false;
        const spec = self.revealSpec(job_id, progress.attempt) orelse return false;
        const owner = jobOwner(raw, job_id) orelse return false;
        if (spec.direction == .download) return std.fs.path.isAbsolute(spec.local_dir) and std.mem.indexOfScalar(u8, spec.local_dir, 0) == null;
        if (!std.fs.path.isAbsolute(spec.remote_dir)) return false;
        const presentation = self.files.presentation orelse return false;
        const model = presentation.modelFor(owner) orelse return false;
        const projection = model.projection() orelse return false;
        if (!projection.owner.eql(owner) or !projection.panes[1].navigation_enabled or (projection.panes[1].state != .ready and projection.panes[1].state != .empty)) return false;
        for (self.workspace.tabs.items) |tab| if (tab.content_owner.eql(.{ .session = owner }) and !tab.closing and !tab.failed and !tab.isCard()) return true;
        return false;
    }
    fn revealCompleted(self: *TransferHost, job_id: transfer_mod.JobId, attempt: u8, owner: @import("../../../host/identity.zig").SessionHandle) !void {
        const progress = self.manager.progress(job_id) orelse return error.StaleTask;
        if (progress.attempt != attempt or !canReveal(self, job_id)) return error.LocationUnavailable;
        if (!(jobOwner(self, job_id) orelse return error.TransferOwnerExpired).eql(owner)) return error.TransferOwnerExpired;
        const spec = self.revealSpec(job_id, attempt) orelse return error.StaleTask;
        if (spec.direction == .download) {
            const directory = try std.Io.Dir.cwd().openDir(self.workspace.io, spec.local_dir, .{});
            directory.close(self.workspace.io);
            const argv = [_][]const u8{ "open", spec.local_dir };
            var result = try std.process.run(self.allocator, self.workspace.io, .{ .argv = &argv, .stdout_limit = .limited(4096), .stderr_limit = .limited(4096) });
            defer self.allocator.free(result.stdout);
            defer self.allocator.free(result.stderr);
            if (!result.term.success()) return error.OpenTransferDirectoryFailed;
        } else {
            const presentation = self.files.presentation orelse return error.FileSourceUnavailable;
            const model = presentation.modelFor(owner) orelse return error.FileSourceUnavailable;
            const projection = model.projection() orelse return error.FileProjectionUnavailable;
            const pane = projection.panes[1];
            try model.handle(.{ .side = .remote, .stamp = pane.stamp, .projection_revision = projection.revision, .selection_revision = pane.selection_revision, .action = .{ .navigate = .{ .requested_path = spec.remote_dir, .base_directory = pane.resolved_path } } });
            for (self.workspace.tabs.items, 0..) |tab, index| if (tab.content_owner.eql(.{ .session = owner })) {
                self.workspace.selectTab(index);
                break;
            };
        }
        self.closeManagerPopover();
    }
    fn requestGlobalManager(raw: *anyopaque, _: transfer_manager_view.Scope) void {
        const self: *TransferHost = @ptrCast(@alignCast(raw));
        self.manager_open_requested = true;
        self.cx.requestRedraw();
    }
    fn requestSessionSftp(raw: *anyopaque) void {
        const self: *TransferHost = @ptrCast(@alignCast(raw));
        self.sftp_open_requested = true;
        self.cx.requestRedraw();
    }
    fn showExistingSftp(self: *TransferHost) void {
        // The frozen workspace action switches to an existing SFTP session.
        // Resolve at the safe point; no new connection or transfer is implied.
        for (self.workspace.tabs.items, 0..) |tab, index| {
            if (tab.closing or tab.isCard()) continue;
            const protocol = if (tab.plugin_protocol_id.len > 0) tab.plugin_protocol_id else if (tab.host_snapshot) |saved| saved.value.protocolId() else "";
            if (!std.mem.eql(u8, protocol, "sftp")) continue;
            self.workspace.selectTab(index);
            return;
        }
        self.workspace.status("尚未打开 SFTP，请从已保存的 SFTP 连接进入");
    }
    pub fn unreadTransferCount(self: *const TransferHost) usize {
        var count: usize = 0;
        for (self.manager.jobs.items) |job| {
            if (!self.seen_transfers.contains(job.id)) count += 1;
        }
        return count;
    }

    fn acknowledgeTransfer(self: *TransferHost, job: transfer_mod.JobId) void {
        self.seen_transfers.put(self.allocator, job, {}) catch {};
    }

    pub fn acknowledgeTransfers(self: *TransferHost) void {
        for (self.manager.jobs.items) |job| self.acknowledgeTransfer(job.id);
    }

    fn showGlobalManager(self: *TransferHost) void {
        const panel = self.manager_panel orelse return;
        if (self.workspace.shutting_down) return;
        panel.selected_scope = .all;
        panel.refresh(wallClockMsTransfer(), .{
            .window_chunks = self.workspace.app_config.transfer.window_chunks,
            .chunk_kb = self.workspace.app_config.transfer.chunk_kb,
        }) catch |err| {
            self.workspace.statusFailure(@errorName(err));
            return;
        };
        panel.show();
        self.acknowledgeTransfers();
        self.manager_visible = true;
        self.manager_refresh.last_ms = 0;
        self.cx.requestRedraw();
    }
    pub fn toggleManager(self: *TransferHost) void {
        const panel = self.manager_panel orelse return;
        if (panel.root.style.display != .none) {
            self.closeManagerPopover();
            return;
        }
        self.showGlobalManager();
    }

    pub fn closeManagerPopover(self: *TransferHost) void {
        const was_visible = if (self.manager_panel) |panel| panel.root.style.display != .none else false;
        if (self.manager_panel) |panel| panel.hide();
        self.manager_visible = false;
        if (was_visible) managerClosed(self);
        self.cx.requestRedraw();
    }

    pub fn managerClosed(raw: *anyopaque) void {
        const self: *TransferHost = @ptrCast(@alignCast(raw));
        self.manager_visible = false;
        // title-click: focus returns to the 传输管理 button (Panel.hide), like every title bar popover.
        self.cx.requestRedraw();
    }

    pub fn managerAction(raw: *anyopaque, id: transfer_mod.JobId, action: transfer_manager_view.Action) void {
        const self: *TransferHost = @ptrCast(@alignCast(raw));
        if (action == .reveal) {
            const progress = self.manager.progress(id) orelse return;
            if (!canReveal(raw, id)) {
                self.workspace.status("原任务位置当前不可用");
                return;
            }
            self.reveal_requested = .{ .job = id, .attempt = progress.attempt, .owner = jobOwner(raw, id) orelse return };
            self.cx.requestRedraw();
            return;
        }
        // Exported checkpoints move exactly once while their former native
        // route is retiring. Preserve a cancel made in that interval and
        // deliver it to the Store after adoption, never to a handed-off ID.
        for (self.tasks.retained_closes.items) |record| if (!record.complete) {
            for (record.jobs) |job| if (job.job_id == id) {
                if (action == .cancel) {
                    for (record.deferred_cancel.items) |queued| if (queued == id) return;
                    record.deferred_cancel.append(self.allocator, id) catch |err| {
                        self.workspace.statusFailure(@errorName(err));
                        return;
                    };
                    self.workspace.status("正在取消任务");
                    self.cx.scheduleRedrawAfterNs(16 * std.time.ns_per_ms);
                } else self.workspace.status("任务状态正在同步，请稍后重试");
                return;
            };
        };
        if (self.manager.retainedOwner(id) != null and self.manager.engineJob(id) == null) {
            const progress = self.manager.progress(id) orelse return;
            switch (action) {
                .resume_transfer, .retry => self.resumeRetained(id) catch |err| self.workspace.statusFailure(@errorName(err)),
                .cancel => {
                    if (progress.attempt == 0) {
                        self.manager.retainedCancelReceipt(id, progress.attempt, self.manager.retainedOwner(id).?, .released) catch |err| self.workspace.statusFailure(@errorName(err));
                    } else {
                        self.retained_store.cancel(id, progress.attempt) catch |err| {
                            self.workspace.statusFailure(@errorName(err));
                            return;
                        };
                        self.manager.retainedCancelReceipt(id, progress.attempt, self.manager.retainedOwner(id).?, .awaiting) catch |err| self.workspace.statusFailure(@errorName(err));
                    }
                },
                else => {},
            }
            self.manager_refresh.last_ms = 0;
            self.cx.requestRedraw();
            return;
        }
        if (action == .resume_transfer or action == .retry) {
            const progress = self.manager.progress(id) orelse return;
            if (progress.attempt == 0 and (progress.state == .paused or (progress.state == .failed and progress.startup_failure != null))) if (self.manager.transferBinding(id)) |binding| if (!self.application.sessions.bindingIsLive(binding)) {
                const owner = jobOwner(self, id) orelse return;
                const start = self.ensureAuxiliary(owner) catch |err| {
                    self.workspace.statusFailure(if (err == error.CleanupNotReleased) "旧传输连接正在清理，请稍后重试" else @errorName(err));
                    return;
                };
                self.manager.rebindWaitingDraft(id, start.binding) catch |err| self.workspace.statusFailure(@errorName(err));
                self.cx.requestRedraw();
                return;
            };
        }
        if (action == .retry or action == .resume_transfer) {
            const original = jobOwner(raw, id) orelse {
                self.workspace.status("任务归属已失效");
                return;
            };
            if (self.manager.transferBinding(id)) |binding| {
                if (!self.application.sessions.bindingIsLive(binding) or (binding.resource_owner == .session and !binding.resource_owner.session.eql(original)) or (binding.resource_owner == .retained_transfer and (binding.origin_session == null or !binding.origin_session.?.eql(original)))) {
                    self.workspace.status("任务所属文件连接已失效");
                    return;
                }
            } else {
                self.workspace.status("任务缺少有效传输服务，请新建传输");
                return;
            }
        }
        switch (action) {
            .resolve_conflict => {
                self.conflict_job = id;
                self.conflict_manual = true;
                self.conflict_presented = false;
                self.refreshConflict() catch |err| self.workspace.statusFailure(@errorName(err));
            },
            .pause => self.manager.pause(id) catch |err| self.workspace.status(if (err == error.UnsupportedPause) "当前连接不支持暂停" else @errorName(err)),
            .resume_transfer => self.manager.resumeJob(id) catch |err| self.workspace.status(if (err == error.UnsupportedResume or err == error.SafeResumeUnavailable) "当前任务不支持安全续传" else @errorName(err)),
            .cancel => self.manager.cancel(id) catch |err| self.workspace.statusFailure(@errorName(err)),
            .retry => self.manager.retry(id) catch |err| self.workspace.statusFailure(@errorName(err)),
            else => {},
        }
        self.manager_refresh.last_ms = 0;
        self.cx.requestRedraw();
    }

    pub fn conflictDecision(raw: *anyopaque, request: transfer_mod.Conflict.Request) !void {
        const self: *TransferHost = @ptrCast(@alignCast(raw));
        const key = request.key();
        if (self.conflict_job == null or self.conflict_job.? != key.job) return error.StaleConflict;
        try self.manager.resolveConflict(key.job, request);
        self.cx.requestRedraw();
    }

    pub fn deferConflict(raw: *anyopaque, key: @import("../../../transfer/conflict.zig").Key) !void {
        const self: *TransferHost = @ptrCast(@alignCast(raw));
        if (self.conflict_job == null or self.conflict_job.? != key.job) return error.StaleConflict;
        var snapshot = (try self.manager.conflictSnapshot(self.allocator, key.job)) orelse return error.StaleConflict;
        defer snapshot.deinit();
        const actual = switch (snapshot.value.pending) {
            .choice => |prompt| prompt.key,
            else => return error.StaleConflict,
        };
        if (!std.meta.eql(actual, key)) return error.StaleConflict;
        try self.manager.pause(key.job);
        self.conflict_job = null;
        self.conflict_manual = false;
        self.conflict_presented = false;
        if (self.conflict_view) |view| view.hide();
        self.cx.requestRedraw();
    }

    fn refreshConflict(self: *TransferHost) !void {
        const view = self.conflict_view orelse return;
        if (self.conflict_job == null) {
            for (0..self.manager.count()) |index| {
                const progress = self.manager.progressAt(index).?;
                if (progress.state == .running and progress.conflict_waiting) {
                    var candidate = (try self.manager.conflictSnapshot(self.allocator, progress.job)) orelse continue;
                    const has_context = candidate.value.context != null;
                    candidate.deinit();
                    if (!has_context) continue;
                    self.conflict_job = progress.job;
                    break;
                }
            }
        }
        const job = self.conflict_job orelse return;
        if (self.conflict_presented and !view.isVisible()) {
            self.conflict_job = null;
            self.conflict_manual = false;
            self.conflict_presented = false;
            return;
        }
        var snapshot = (try self.manager.conflictSnapshot(self.allocator, job)) orelse {
            self.conflict_job = null;
            self.conflict_manual = false;
            self.conflict_presented = false;
            view.hide();
            return;
        };
        defer snapshot.deinit();
        // Legacy jobs without a frozen Context cannot authorize decisions.
        // Their read-only explanation opens only on an explicit list action.
        if (snapshot.value.context == null and !self.conflict_manual) {
            self.conflict_job = null;
            return;
        }
        try view.show(snapshot.value);
        self.conflict_presented = true;
    }

    pub fn openPanel(self: *TransferHost) void {
        self.showPanel(.{ .mode = .upload });
        self.cx.requestRedraw();
    }

    fn showConfirmation(self: *TransferHost, data: transfer_panel_mod.Data) void {
        const defaults = @import("../../../config/transfer_defaults.zig");
        var captured = defaults.confirmation(self.workspace.app_config.transfer, data);
        if (captured.mode != .download or captured.local_dir.len > 0) {
            self.panel.show(captured);
            return;
        }
        const home = @import("../../../platform/user_dirs.zig").home(self.allocator) catch null;
        defer if (home) |value| self.allocator.free(value);
        const initial = defaults.downloadDirectory(self.allocator, self.workspace.app_config.transfer.download_dir, home) catch {
            self.panel.show(captured);
            return;
        };
        defer self.allocator.free(initial);
        captured.local_dir = initial;
        // Panel.show stores the path in an owning text signal. A suggestion
        // deliberately does not create the AppKit directory-selection receipt.
        self.panel.show(captured);
    }

    pub fn showSessionTransfer(self: *TransferHost, owner: @import("../../../host/identity.zig").SessionHandle, mode: transfer_panel_mod.Data.Mode, source: ?[]const u8) void {
        const capabilities = (self.application.sessions.capabilitySnapshot(owner) catch {
            self.workspace.statusFailure("传输失败：无法读取原会话状态");
            return;
        }) orelse {
            self.workspace.statusFailure("传输失败：原会话已失效");
            return;
        };
        const availability = @import("../../../host/actions.zig").project(if (mode == .upload) .upload else .download, capabilities);
        if (!availability.enabled) {
            self.workspace.status(availability.reason);
            return;
        }
        const tab_id = self.application.legacyForHandle(owner) orelse return;
        const tab = self.workspace.sessionTab(tab_id) orelse return;
        if (tab.closing or tab.isCard() or tab.failed or tab.runtime == null) {
            self.workspace.statusFailure("传输失败：需要已连接的 SSH 会话");
            return;
        }
        const host = if (tab.host_snapshot) |snapshot| snapshot.value else {
            self.workspace.statusFailure("传输失败：缺少主机配置");
            return;
        };
        const cwd = if (mode == .upload) tab.runtime.?.workerPtr().copyCwd(self.allocator) catch null else null;
        defer if (cwd) |value| self.allocator.free(value);
        self.file_binding = null;
        self.file_conflict_context = null;
        self.showConfirmation(.{ .mode = mode, .owner = owner, .endpoint = host.host, .host_name = tab.titleSlice(), .available = true, .sources = if (source) |value| &.{value} else &.{}, .local_dir = "", .remote_dir = cwd orelse "", .edit_remote_source = mode == .download, .require_directory_selection = mode == .download });
        if (mode == .upload) self.requestUploadDirectory(owner, tab.runtime.?.workerPtr());
        self.cx.requestRedraw();
    }

    fn requestUploadDirectory(self: *TransferHost, owner: @import("../../../host/identity.zig").SessionHandle, runtime: *@import("../../../host/runtime_service.zig").Runtime) void {
        runtime.requestCurrentDirectory() catch {
            self.workspace.status("无法读取当前远程目录，请重试");
            return;
        };
        self.panel.remote_dir_sig.set("");
        self.panel.setRemoteStatus("正在读取当前终端目录…") catch {};
        self.cwd_pending = .{ .owner = owner, .started = wallClockMsTransfer() };
        self.cx.scheduleRedrawAfterNs(50 * std.time.ns_per_ms);
    }

    fn showPanel(self: *TransferHost, data: transfer_panel_mod.Data) void {
        self.file_binding = null;
        self.file_conflict_context = null;
        const index = self.workspace.active_tab orelse return;
        const tab = self.workspace.tabs.items[index];
        var captured = data;
        captured.owner = switch (tab.content_owner) {
            .session => |handle| handle,
            else => null,
        };
        const host = self.workspace.tabHost(index);
        captured.endpoint = if (host) |value| value.host else "本机";
        captured.host_name = tab.titleSlice();
        captured.available = host != null and !tab.closing and !tab.isCard() and !tab.failed and tab.runtime != null;
        captured.unavailable_reason = "当前会话无法进行远程文件传输";
        self.showConfirmation(captured);
        if (data.mode == .upload and data.remote_dir.len == 0 and captured.available) if (captured.owner) |owner| self.requestUploadDirectory(owner, tab.runtime.?.workerPtr());
    }

    pub fn showFileTransfer(raw: *anyopaque, intent: @import("../../../host/file_workspace_controller.zig").FrozenTransfer, binding: @import("../../../host/session_host.zig").ServiceHandle) !void {
        const self: *TransferHost = @ptrCast(@alignCast(raw));
        const tab_id = self.application.legacyForHandle(intent.owner) orelse return error.TransferOwnerExpired;
        const tab = self.workspace.sessionTab(tab_id) orelse return error.TransferOwnerExpired;
        if (!tab.file_ready or tab.closing or !self.application.sessions.bindingIsLive(binding)) return error.TransferOwnerExpired;
        const host = tab.host_snapshot.?.value;
        if (self.tasks.next_transfer_intent == std.math.maxInt(u64)) return error.IntentIdExhausted;
        const conflict_context: transfer_mod.Conflict.Context = .{
            .intent_id = self.tasks.next_transfer_intent,
            .original_owner = intent.owner,
            .resource_owner = binding.resource_owner,
            .source_endpoint = switch (intent.source.endpoint) {
                .local_fs => |value| .{ .local_fs = value },
                .sftp => |value| .{ .sftp = value },
            },
            .target_endpoint = switch (intent.destination.endpoint) {
                .local_fs => |value| .{ .local_fs = value },
                .sftp => |value| .{ .sftp = value },
            },
        };
        self.tasks.next_transfer_intent += 1;
        const upload = intent.source.endpoint == .local_fs;
        self.showConfirmation(.{ .mode = if (upload) .upload else .download, .owner = intent.owner, .endpoint = host.host, .host_name = host.name, .available = true, .sources = intent.paths, .local_dir = if (upload) intent.source.directory else intent.destination.directory, .remote_dir = if (upload) intent.destination.directory else intent.source.directory });
        self.file_binding = binding;
        self.file_conflict_context = conflict_context;
        self.cx.requestRedraw();
    }

    pub fn exportFileTransfer(raw: *anyopaque, intent: @import("../../../host/file_workspace_controller.zig").FrozenTransfer, binding: @import("../../../host/session_host.zig").ServiceHandle) !u64 {
        if (intent.source.endpoint != .sftp or intent.destination.endpoint != .local_fs) return error.InvalidExportDirection;
        return enqueueFileTransfer(raw, intent, binding, .{ .resume_transfer = false, .md5_check = true });
    }

    pub fn cancelFileExport(raw: *anyopaque, id: u64) void {
        const self: *TransferHost = @ptrCast(@alignCast(raw));
        self.manager.cancel(id) catch |err| applog.warn(.transfer, "file export cancellation: {s}", .{@errorName(err)});
        self.cx.scheduleRedrawAfterNs(16 * std.time.ns_per_ms);
    }

    pub fn pollFileExport(raw: *anyopaque, id: u64) @import("../../files/view/file_workspace_presentation.zig").ExportStatus {
        const self: *TransferHost = @ptrCast(@alignCast(raw));
        const progress = self.manager.progress(id) orelse return .failed;
        return switch (progress.state) {
            .succeeded => .succeeded,
            .failed => .failed,
            .cancelled => .cancelled,
            else => .pending,
        };
    }

    pub fn confirmFileTransfer(raw: *anyopaque, intent: @import("../../../host/file_workspace_controller.zig").FrozenTransfer, binding: @import("../../../host/session_host.zig").ServiceHandle, options: @import("../../files/view/file_copy_view.zig").Options) !void {
        _ = try enqueueFileTransfer(raw, intent, binding, options);
    }

    fn enqueueFileTransfer(raw: *anyopaque, intent: @import("../../../host/file_workspace_controller.zig").FrozenTransfer, binding: @import("../../../host/session_host.zig").ServiceHandle, options: @import("../../files/view/file_copy_view.zig").Options) !u64 {
        const self: *TransferHost = @ptrCast(@alignCast(raw));
        try self.validateNewTransferPolicy();
        const tab_id = self.application.legacyForHandle(intent.owner) orelse return error.TransferOwnerExpired;
        const tab = self.workspace.sessionTab(tab_id) orelse return error.TransferOwnerExpired;
        if (!tab.file_ready or tab.closing or binding.resource_owner != .session or !binding.resource_owner.session.eql(intent.owner) or !self.application.sessions.bindingIsLive(binding)) return error.TransferOwnerExpired;
        if (self.tasks.next_transfer_intent == std.math.maxInt(u64)) return error.IntentIdExhausted;
        try self.tasks.job_owners.ensureUnusedCapacity(self.allocator, 1);
        const upload = intent.source.endpoint == .local_fs;
        const captured: transfer_mod.JobSpec = .{
            .session_id = @backingInt(intent.owner.session_id),
            .transfer_binding = binding,
            .direction = if (upload) .upload else .download,
            .sources = intent.paths,
            .local_dir = if (upload) intent.source.directory else intent.destination.directory,
            .remote_dir = if (upload) intent.destination.directory else intent.source.directory,
            .resume_transfer = options.resume_transfer,
            .md5_check = options.md5_check,
            .chunk_kb = self.workspace.app_config.transfer.chunk_kb,
            .window_chunks = self.workspace.app_config.transfer.window_chunks,
            .conflict_context = .{
                .intent_id = self.tasks.next_transfer_intent,
                .original_owner = intent.owner,
                .resource_owner = binding.resource_owner,
                .source_endpoint = switch (intent.source.endpoint) {
                    .local_fs => |v| .{ .local_fs = v },
                    .sftp => |v| .{ .sftp = v },
                },
                .target_endpoint = switch (intent.destination.endpoint) {
                    .local_fs => |v| .{ .local_fs = v },
                    .sftp => |v| .{ .sftp = v },
                },
            },
        };
        const id = try self.manager.enqueue(captured);
        self.tasks.next_transfer_intent += 1;
        self.tasks.job_owners.appendAssumeCapacity(.{ .job = id, .owner = intent.owner });
        if (@import("../../../platform/runtime_mode.zig").automation) std.debug.print("FILE_TRANSFER_ENQUEUED {{\"job\":{d},\"owner_id\":{d},\"owner_generation\":{d},\"binding_id\":{d},\"binding_generation\":{d},\"md5_check\":{},\"resume_transfer\":{},\"chunk_kb\":{d},\"window_chunks\":{d},\"max_tasks\":{d}}}\n", .{ id, @backingInt(intent.owner.session_id), intent.owner.generation, binding.binding_id, binding.binding_generation, captured.md5_check, captured.resume_transfer, captured.chunk_kb, captured.window_chunks, self.manager.concurrency });
        self.last_job = id;
        self.cx.scheduleRedrawAfterNs(16 * std.time.ns_per_ms);
        return id;
    }

    /// 创建 Panel 实例并 mount；回调指向自身。返回浮层根节点。
    pub fn panel_mounted(self: *TransferHost, cx: *ui.Cx, scope: *ui.Scope) !*ui.Node {
        const panel = try cx.allocator.create(transfer_panel_mod.Panel);
        panel.* = .{};
        self.panel = panel;
        const root = try panel.mount(cx, scope);
        panel.on_submit = onTransferSubmit;
        panel.on_submit_frozen = onTransferSubmitFrozen;
        panel.submit_ctx = @ptrCast(self);
        panel.on_cancel = onTransferCancel;
        panel.on_browse = browseSource;
        panel.on_replace_source = replaceSource;
        panel.on_local_directory = browseDirectory;
        return root;
    }

    fn browseSource(raw: *anyopaque) void {
        const self: *TransferHost = @ptrCast(@alignCast(raw));
        const revision = self.panel.source_revision;
        var buffer: [4096]u8 = undefined;
        const path = ui.platform_services.openFilePanel(self.cx.system_sdk, &buffer) orelse return;
        self.panel.replaceSource(0, revision, path) catch |err| self.panel.setError(@errorName(err));
        self.cx.requestRedraw();
    }

    fn replaceSource(raw: *anyopaque, index: usize, revision: u64) void {
        const self: *TransferHost = @ptrCast(@alignCast(raw));
        var buffer: [4096]u8 = undefined;
        const path = ui.platform_services.openFilePanel(self.cx.system_sdk, &buffer) orelse return;
        self.panel.replaceSource(index, revision, path) catch |err| self.panel.setError(@errorName(err));
        self.cx.requestRedraw();
    }

    fn browseDirectory(raw: *anyopaque) void {
        const self: *TransferHost = @ptrCast(@alignCast(raw));
        const sdk = self.cx.system_sdk orelse return;
        const ticket = self.panel.directoryTicket() catch return;
        const state = self.application.sessions.queryState(ticket.owner) orelse return;
        const capabilities = (self.application.sessions.capabilitySnapshot(ticket.owner) catch return) orelse return;
        if (!@import("../../../host/actions.zig").project(if (self.panel.mode == .upload) .upload else .download, capabilities).enabled) return;
        const operation = state.create_operation;
        // Keep this path alive across AppKit's nested run loop. Cancelling
        // yields no selection and never changes the confirmation's receipt.
        const initial = self.allocator.dupe(u8, self.panel.local_dir_sig.peek()) catch return;
        defer self.allocator.free(initial);
        var buffer: [4096]u8 = undefined;
        const path = (@import("../../../platform/dialog_port.zig").run(sdk, .{ .kind = .pick_folder, .default_path = initial }, &buffer) catch return) orelse return;
        const current = self.application.sessions.queryState(ticket.owner) orelse return;
        const current_capabilities = (self.application.sessions.capabilitySnapshot(ticket.owner) catch return) orelse return;
        if (current_capabilities.revision != capabilities.revision or current.lifecycle != .attached or !current.create_operation.eql(operation)) return;
        self.panel.applyDirectorySelection(ticket, path) catch return;
        self.cx.requestRedraw();
    }

    pub fn hookRun(ctx: *anyopaque, _: u8, _: bool) ui.AfterLayoutResult {
        const self: *TransferHost = @ptrCast(@alignCast(ctx));
        self.poll();
        return .done;
    }

    fn submit(self: *TransferHost, spec: transfer_mod.JobSpec) void {
        const owner = self.panel.capturedOwner() orelse return;
        self.submitFrozen(owner, spec) catch |err| self.panel.setError(@errorName(err));
    }

    fn submitFrozen(self: *TransferHost, owner: @import("../../../host/identity.zig").SessionHandle, spec: transfer_mod.JobSpec) !void {
        try self.validateNewTransferPolicy();
        if (self.file_binding) |binding| {
            if (binding.resource_owner != .session or !binding.resource_owner.session.eql(owner) or !self.application.sessions.bindingIsLive(binding)) return error.TransferOwnerExpired;
            try self.tasks.job_owners.ensureUnusedCapacity(self.allocator, 1);
            var captured = spec;
            captured.chunk_kb = self.workspace.app_config.transfer.chunk_kb;
            captured.window_chunks = self.workspace.app_config.transfer.window_chunks;
            captured.transfer_binding = binding;
            captured.conflict_context = self.file_conflict_context orelse return error.MissingConflictContext;
            captured.session_id = @backingInt(owner.session_id);
            const id = try self.manager.enqueue(captured);
            self.tasks.job_owners.appendAssumeCapacity(.{ .job = id, .owner = owner });
            if (@import("../../../platform/runtime_mode.zig").automation) std.debug.print("FILE_TRANSFER_ENQUEUED {{\"job\":{d},\"owner_id\":{d},\"owner_generation\":{d},\"binding_id\":{d},\"binding_generation\":{d},\"md5_check\":{},\"resume_transfer\":{},\"chunk_kb\":{d},\"window_chunks\":{d},\"max_tasks\":{d}}}\n", .{ id, @backingInt(owner.session_id), owner.generation, binding.binding_id, binding.binding_generation, captured.md5_check, captured.resume_transfer, captured.chunk_kb, captured.window_chunks, self.manager.concurrency });
            self.last_job = id;
            self.file_binding = null;
            self.file_conflict_context = null;
            self.panel.hide();
            self.cx.scheduleRedrawAfterNs(16 * std.time.ns_per_ms);
            return;
        }
        const index = for (self.workspace.tabs.items, 0..) |tab, index| {
            if (tab.content_owner.eql(.{ .session = owner })) break index;
        } else return error.TransferOwnerExpired;
        const tab = self.workspace.tabs.items[index];
        if (!tab.content_owner.eql(.{ .session = owner }) or tab.closing or tab.isCard() or tab.failed or tab.runtime == null) return error.TransferOwnerExpired;
        try self.submitSessionTransfer(owner, spec);
    }

    fn refreshCompletedTransfers(self: *TransferHost) void {
        const presentation = self.files.presentation orelse return;
        captures: for (self.tasks.job_owners.items, 0..) |*captured, captured_index| {
            for (self.tasks.job_owners.items[0..captured_index]) |previous| if (previous.job == captured.job) continue :captures;
            const progress = self.manager.progress(captured.job) orelse continue;
            if (progress.state != .succeeded or progress.job_cleanup != .released) continue;
            for (self.manager.jobs.items) |job| {
                if (job.id != captured.job) continue;
                const context = job.spec.conflict_context orelse break;
                if (!context.original_owner.eql(captured.owner)) break;
                const upload = job.spec.direction == .upload;
                if ((upload and context.target_endpoint != .sftp) or (!upload and context.target_endpoint != .local_fs)) break;
                _ = captured.directory_refresh.update(progress, .{ .owner = captured.owner, .endpoint = switch (context.target_endpoint) {
                    .local_fs => |value| .{ .local_fs = value },
                    .sftp => |value| .{ .sftp = value },
                }, .side = if (upload) .remote else .local, .directory = if (upload) job.spec.remote_dir else job.spec.local_dir }, presentation.modelFor(captured.owner)) catch |err| {
                    applog.warn(.transfer, "completed transfer directory refresh: {s}", .{@errorName(err)});
                    self.workspace.statusFailure("传输已完成，目标目录刷新失败，请重新读取");
                    break;
                };
                break;
            }
        }
    }

    /// after-layout 轮询：连接完成→消费挂起任务；活跃→tick + 进度行。
    fn poll(self: *TransferHost) void {
        if (!self.picker_running) self.pollCommandPicker();
        if (self.cwd_pending) |pending| cwd: {
            if (!self.panel.open.peek()) {
                self.cwd_pending = null;
                break :cwd;
            }
            const id = self.application.legacyForHandle(pending.owner) orelse {
                self.cwd_pending = null;
                break :cwd;
            };
            const tab = self.workspace.sessionTab(id) orelse {
                self.cwd_pending = null;
                break :cwd;
            };
            const runtime = tab.runtime orelse {
                self.cwd_pending = null;
                break :cwd;
            };
            const path = runtime.workerPtr().copyCwd(self.allocator) catch null;
            defer if (path) |value| self.allocator.free(value);
            if (path) |value| {
                self.panel.remote_dir_sig.set(value);
                self.panel.setRemoteStatus("已填入远程目录") catch {};
                self.cwd_pending = null;
            } else if (wallClockMsTransfer() -| pending.started > 5000) {
                self.panel.setRemoteStatus("未能读取当前目录，请在终端空闲时重新执行 @up") catch {};
                self.cwd_pending = null;
            } else self.cx.scheduleRedrawAfterNs(50 * std.time.ns_per_ms);
        }
        if (self.reveal_requested) |request| {
            self.reveal_requested = null;
            self.revealCompleted(request.job, request.attempt, request.owner) catch |err| self.workspace.statusFailure(@errorName(err));
        }
        if (self.manager_open_requested) {
            self.manager_open_requested = false;
            self.showGlobalManager();
        }
        if (self.sftp_open_requested) {
            self.sftp_open_requested = false;
            self.showExistingSftp();
        }
        self.pollShared() catch |err| applog.warn(.transfer, "shared transfer receipt: {s}", .{@errorName(err)});
        self.pollAuxiliary() catch |err| applog.warn(.transfer, "auxiliary transfer receipt: {s}", .{@errorName(err)});
        self.pollRetained() catch |err| {
            applog.warn(.transfer, "retained transfer receipt: {s}", .{@errorName(err)});
        };
        const now = wallClockMsTransfer();
        if (self.manager.count() != 0) {
            // Lower limits stop new scheduling until existing jobs drain; accepted jobs keep their policy.
            _ = self.tasks.tick(now, self.workspace.app_config.transfer.max_tasks) catch |err| applog.warn(.transfer, "application task tick: {s}", .{@errorName(err)});
        }
        const busy = self.manager.needsPolling();
        if (self.manager_panel) |panel| self.manager_visible = panel.root.style.display != .none;
        if (self.manager_visible) {
            switch (self.manager_refresh.presentationStep(now, busy, false)) {
                // Inside the window: come back when it ends. A job that pauses / completes right after the previous
                // refresh otherwise stays stale in the open list until unrelated input wakes the window.
                .wait_ms => |ms| self.cx.scheduleRedrawAfterNs(ms * std.time.ns_per_ms),
                .refresh => if (self.manager_panel) |panel| {
                    var refreshed = true;
                    panel.refresh(now, .{
                        .window_chunks = self.workspace.app_config.transfer.window_chunks,
                        .chunk_kb = self.workspace.app_config.transfer.chunk_kb,
                    }) catch |err| {
                        applog.warn(.transfer, "transfer window refresh: {s}", .{@errorName(err)});
                        refreshed = false;
                    };
                    if (refreshed and self.cx.window_active) self.acknowledgeTransfers();
                },
            }
        }
        self.refreshProgressRow(now, busy);
        if (self.manager.count() != 0) {
            self.refreshCompletedTransfers();
            if (process_state.process_notifications) |notifications| for (self.tasks.job_owners.items) |captured| {
                const progress = self.manager.progress(captured.job) orelse continue;
                const completed_job = for (self.manager.jobs.items) |job| {
                    if (job.id == captured.job) break job;
                } else continue;
                const notify_complete = completed_job.spec.notify_complete;
                var transfer_object_buffer: [1024]u8 = undefined;
                const first_source = if (completed_job.spec.sources.len > 0) std.fs.path.basename(completed_job.spec.sources[0]) else "文件传输";
                const transfer_object = if (completed_job.spec.sources.len > 1) std.fmt.bufPrint(&transfer_object_buffer, "{s} 等 {d} 项", .{ first_source, completed_job.spec.sources.len }) catch first_source else first_source;
                const batch_state: ?@import("../../../host/notification_host.zig").Host.TransferBatchState = switch (progress.state) {
                    .queued, .running, .retry_wait => .active,
                    .failed => if (progress.job_cleanup == .released) .blocked else null,
                    .succeeded, .cancelled => if (progress.job_cleanup == .released) .ended else null,
                    else => null,
                };
                if (batch_state) |state| if (self.notification_window) |window| {
                    notifications.publishTransferBatch(window, .{ .session = captured.owner }, progress.job, progress.attempt, completed_job.spec.sources.len, state, .{ .object = transfer_object, .detail = @import("../view/transfer_manager_view.zig").progressDetail(progress) }) catch |err| applog.warn(.transfer, "batch notification: {s}", .{@errorName(err)});
                };
                if (progress.job_cleanup != .released or (progress.state != .succeeded and progress.state != .failed and progress.state != .cancelled)) continue;
                notifications.publishTransfer(.{ .session = captured.owner }, progress.job, progress.attempt, .{ .result = if (progress.state == .succeeded) .succeeded else if (progress.state == .failed) .failed else .cancelled, .resources_released = true, .notify_complete = notify_complete, .details = .{ .object = transfer_object, .detail = @import("../view/transfer_manager_view.zig").progressDetail(progress) } }) catch |err| applog.warn(.app, "transfer notification: {s}", .{@errorName(err)});
            };
            if (@import("../../../platform/runtime_mode.zig").automation) for (self.tasks.job_owners.items) |*captured| {
                const progress = self.manager.progress(captured.job) orelse continue;
                const v = progress.verification orelse continue;
                if (progress.state != .succeeded or v.state != .passed or v.source_md5 == null or v.target_md5 == null or captured.verification_trace_attempt == progress.attempt) continue;
                std.debug.print("FILE_TRANSFER_MANAGER_VERIFICATION {{\"job\":{d},\"attempt\":{d},\"owner_id\":{d},\"owner_generation\":{d},\"state\":\"{s}\",\"verification_state\":\"{s}\",\"source_md5\":\"{s}\",\"target_md5\":\"{s}\"}}\n", .{ progress.job, progress.attempt, @backingInt(captured.owner.session_id), captured.owner.generation, @tagName(progress.state), @tagName(v.state), std.fmt.bytesToHex(v.source_md5.?, .lower), std.fmt.bytesToHex(v.target_md5.?, .lower) });
                captured.verification_trace_attempt = progress.attempt;
            };
            // 终态上抛：失败原因可见（成功不打扰）。
            if (self.manager.progressAt(self.manager.count() - 1)) |snap| {
                if (snap.state == .failed and self.failure_reported.swap(1, .acq_rel) == 0) {
                    const reason: []const u8 = if (snap.startup_failure) |problem| problem.message() else if (snap.failure) |f| switch (f) {
                        .connection => "连接失败",
                        .timeout => "超时",
                        .permission_denied => "权限不足",
                        .not_found => "文件不存在",
                        .checksum => "校验失败",
                        .invalid_request => "参数错误",
                        .conflict => "冲突",
                        .protocol => "协议错误",
                        .io => "IO 错误",
                    } else "未知错误";
                    var buffer: [512]u8 = undefined;
                    var writer = std.Io.Writer.fixed(&buffer);
                    if (snap.startup_failure) |problem| writer.print("{s}（{s}）", .{ reason, problem.code() }) catch {} else writer.print("传输失败：{s}（已重试 {d} 次）", .{ reason, snap.attempt }) catch {};
                    self.workspace.status(writer.buffered());
                }
            }
        }
        self.refreshConflict() catch |err| applog.warn(.transfer, "transfer conflict presentation: {s}", .{@errorName(err)});
        // Completed tasks remain in history, so count() never returns to zero.
        // Only scheduling/IO cleanup needs the frame clock; otherwise one
        // completed transfer keeps this window repainting at roughly 30 Hz.
        if (busy) self.cx.scheduleRedrawAfterNs(33 * std.time.ns_per_ms);
    }

    fn currentTransferScope(self: *TransferHost, a: std.mem.Allocator) !?transfer_manager_view.Scope {
        if (self.workspace.active_group_view) |id| {
            const roster = self.workspace.group_roster orelse return null;
            const group = roster.findById(id) orelse return null;
            var members: std.ArrayList(@import("../../../host/identity.zig").SessionHandle) = .empty;
            for (group.members.items) |member| {
                if (!member.active) continue;
                for (self.workspace.tabs.items) |tab| {
                    if (tab.id != member.pane_id or tab.content_owner != .session or tab.isCard() or tab.closing) continue;
                    try members.append(a, tab.content_owner.session);
                    break;
                }
            }
            if (members.items.len == 0) return null;
            return .{ .sessions = .{ .members = members.items, .revision = group.membership_revision } };
        }
        const index = self.workspace.active_tab orelse return null;
        if (index >= self.workspace.tabs.items.len) return null;
        const tab = self.workspace.tabs.items[index];
        if (tab.isCard() or tab.closing or tab.content_owner != .session) return null;
        const snapshot = (try self.application.sessions.capabilitySnapshot(tab.content_owner.session)) orelse return null;
        if (!@import("../../../host/actions.zig").project(.upload, snapshot).visible) return null;
        return .{ .session = tab.content_owner.session };
    }
    const FileTrayLink = struct {
        tab: *ws.SessionTab,
        index: usize,
        fn release(self: *@This()) void {
            self.tab.transfer_trays[self.index] = null;
        }
    };
    fn refreshFileTrays(self: *TransferHost, now: u64) void {
        const presentation = self.files.presentation orelse return;
        for (self.workspace.tabs.items) |tab| {
            if (tab.content_owner != .session or tab.closing or tab.isCard()) continue;
            const owner = tab.content_owner.session;
            const scope = presentation.transferScopeFor(owner) orelse continue;
            for ([_]@import("../../files/view/file_workspace_view.zig").Side{ .local, .remote }, 0..) |side, index| {
                const slot = presentation.transferSlotFor(owner, side) orelse continue;
                if (tab.transfer_trays[index] == null) {
                    const panel = transfer_manager_view.mountSessionTray(self.cx, scope, self.manager, .{ .context = self, .action = managerAction, .scope_choices = transferScopeChoices, .owner = jobOwner, .owner_label = jobOwnerLabel, .can_reveal = canReveal, .open_sftp = requestSessionSftp, .open_manager = requestGlobalManager }) catch continue;
                    panel.setDirectionFilter(if (side == .local) .upload else .download);
                    const link = scope.createState(FileTrayLink, .{ .tab = tab, .index = index }) catch continue;
                    scope.onCleanup(FileTrayLink, link, FileTrayLink.release) catch continue;
                    slot.appendChild(self.allocator, panel.root) catch continue;
                    tab.transfer_trays[index] = panel;
                }
                const panel = tab.transfer_trays[index].?;
                panel.selected_scope = .{ .session = owner };
                panel.refresh(now, .{ .window_chunks = self.workspace.app_config.transfer.window_chunks, .chunk_kb = self.workspace.app_config.transfer.chunk_kb }) catch continue;
                panel.show();
            }
        }
    }
    fn refreshGlobalToolbar(self: *TransferHost) void {
        const view = self.toolbar_progress orelse return;
        var done: u128 = 0;
        var total: u128 = 0;
        var active: usize = 0;
        var paused: usize = 0;
        var waiting: usize = 0;
        var unknown = false;
        var failed = false;
        var completed = false;
        for (0..self.manager.count()) |index| {
            const value = self.manager.progressAt(index) orelse continue;
            switch (value.state) {
                .cancelled => continue,
                .failed => {
                    failed = true;
                    continue;
                },
                .succeeded => {
                    completed = true;
                    continue;
                },
                .paused, .pausing => paused += 1,
                .queued, .retry_wait => waiting += 1,
                else => {},
            }
            active += 1;
            const bytes = if (value.source_read) |read| read.done_bytes else value.done_bytes;
            const size = if (value.source_read) |read| read.total_bytes else value.total_bytes;
            done += @min(bytes, size);
            total += size;
            if (size == 0) unknown = true;
        }
        if (active != 0) {
            const fraction: ?f32 = if (unknown or total == 0) null else @as(f32, @floatFromInt(done)) / @as(f32, @floatFromInt(total));
            view.update(if (paused == active) .paused else if (waiting + paused == active) .waiting else .running, fraction);
        } else view.update(if (self.unreadTransferCount() == 0) .idle else if (failed) .failed else if (completed) .completed else .idle, null);
    }
    fn refreshProgressRow(self: *TransferHost, now: u64, busy: bool) void {
        self.refreshGlobalToolbar();
        const view = self.status_transfer orelse return;
        var next_arena = std.heap.ArenaAllocator.init(self.allocator);
        defer next_arena.deinit();
        const next = self.currentTransferScope(next_arena.allocator()) catch return;
        const changed = if (next) |scope| if (self.ticker_scope) |previous| !transfer_manager_view.scopeEql(scope, previous) else true else self.ticker_scope != null;
        if (changed) {
            if (self.ticker_scope_arena) |*arena| arena.deinit();
            self.ticker_scope_arena = next_arena;
            next_arena = std.heap.ArenaAllocator.init(self.allocator);
            self.ticker_scope = next;
            self.ticker_started_ms = now;
            self.ticker_refresh.last_ms = 0;
        }
        view.root.setDisplay(if (self.ticker_scope == null) .none else .flex);
        const captured = self.ticker_scope orelse return;
        switch (self.ticker_refresh.presentationStep(now, busy, view.repaintDue())) {
            .refresh => {},
            .wait_ms => |ms| {
                self.cx.scheduleRedrawAfterNs(ms * std.time.ns_per_ms);
                return;
            },
        }
        self.refreshFileTrays(now);
        var active: usize = 0;
        var total: usize = 0;
        var latest: ?usize = null;
        for (0..self.manager.count()) |index| {
            const value = self.manager.progressAt(index) orelse continue;
            if (!transfer_manager_view.belongs(captured, self.tasks.ownerForJob(value.job))) continue;
            latest = index;
            total += 1;
            if (value.state != .succeeded and value.state != .failed and value.state != .cancelled) active += 1;
        }
        var chosen = latest;
        if (active > 0) {
            var target = @as(usize, @intCast((now -| self.ticker_started_ms) / 3000)) % active;
            for (0..self.manager.count()) |index| {
                const value = self.manager.progressAt(index) orelse continue;
                if (!transfer_manager_view.belongs(captured, self.tasks.ownerForJob(value.job)) or value.state == .succeeded or value.state == .failed or value.state == .cancelled) continue;
                if (target == 0) {
                    chosen = index;
                    break;
                }
                target -= 1;
            }
        }
        if (chosen) |index| {
            const value = self.manager.progressAt(index).?;
            var pct_buffer: [32]u8 = undefined;
            var count_buffer: [48]u8 = undefined;
            var speed_buffer: [48]u8 = undefined;
            const shown_done = if (value.source_read) |read| read.done_bytes else value.done_bytes;
            const shown_total = if (value.source_read) |read| read.total_bytes else value.total_bytes;
            const fraction: f32 = if (shown_total == 0) 0 else @min(1, @as(f32, @floatFromInt(shown_done)) / @as(f32, @floatFromInt(shown_total)));
            const pct = if (value.state == .running) (if (value.total_bytes == 0) "传输中" else std.fmt.bufPrint(&pct_buffer, "{d:.0}%", .{fraction * 100}) catch "") else transfer_manager_view.phaseLabel(std.meta.stringToEnum(transfer_manager_view.Phase, @tagName(value.state)) orelse .queued);
            const shown_speed = if (value.source_read) |read| read.speed_bps else value.speed_bps;
            const rate = if (value.state == .running) @import("../../../shared/base/format.zig").liveRate(&speed_buffer, shown_speed) else @import("../../../shared/base/format.zig").rate_placeholder;
            const counts = if (total > 99) "99+" else std.fmt.bufPrint(&count_buffer, "{d}", .{total}) catch "";
            if (self.cx.window_active and view.root.isDisplayedInTree() and view.root.globalRect().w > 0) self.acknowledgeTransfer(value.job);
            view.updateSummary(.{
                .name = self.manager.sourceName(index) orelse "传输任务",
                .percent = if (value.state == .succeeded) "100%" else pct,
                .rate = rate,
                .counts = counts,
                .fraction = fraction,
                .upload = self.manager.jobs.items[index].spec.direction == .upload,
                .phase = switch (value.state) {
                    .succeeded => .completed,
                    .failed => .failed,
                    .queued, .retry_wait => .waiting,
                    .paused, .pausing => .paused,
                    else => .running,
                },
            });
        } else view.update("传输 · 空闲", "", "", 0, false);
    }

    pub fn cleanup(self: *TransferHost) void {
        self.seen_transfers.deinit(self.allocator);
        if (self.command_picker) |request| self.allocator.free(request.source);
        self.cx.removeAfterLayoutHook(self);
        if (self.ticker_scope_arena) |*arena| arena.deinit();
        // Native transfer resources are exclusively owned by the process task
        // domain and provider bindings; a window only releases its presenter.
        self.allocator.destroy(self);
    }
};

pub fn onTransferSubmit(ctx: *anyopaque, spec: transfer_mod.JobSpec) void {
    TransferHost.submit(@ptrCast(@alignCast(ctx)), spec);
}

pub fn onTransferSubmitFrozen(ctx: *anyopaque, owner: @import("../../../host/identity.zig").SessionHandle, spec: transfer_mod.JobSpec) !void {
    const host: *TransferHost = @ptrCast(@alignCast(ctx));
    try host.submitFrozen(owner, spec);
}

pub fn onTransferCancel(ctx: *anyopaque) void {
    const self: *TransferHost = @ptrCast(@alignCast(ctx));
    self.panel.hide();
    self.file_binding = null;
    self.cx.requestRedraw();
}

pub fn wallClockMsTransfer() u64 {
    var ts: std.c.timespec = undefined;
    if (std.c.clock_gettime(.MONOTONIC, &ts) != 0) return 0;
    return @as(u64, @intCast(ts.sec)) * std.time.ms_per_s + @as(u64, @intCast(ts.nsec)) / std.time.ns_per_ms;
}

