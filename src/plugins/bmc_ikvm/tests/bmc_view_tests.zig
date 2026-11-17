const std = @import("std");
const ui = @import("ui");
const mapping = @import("../input_mapping.zig");
const vm = @import("../view_model.zig");
const views = @import("../views.zig");
const console = @import("../console_service.zig");
const remote = @import("../remote_input.zig");
const services = @import("../services.zig");
const typed = @import("../../../host/plugin_services.zig");
const identity = @import("../../../host/identity.zig");
const frames = @import("../../../host/frame_texture_sink.zig");
const access = @import("../../../host/session_service_access.zig");
const a = std.testing.allocator;
const owner: identity.SessionHandle = .{ .session_id = @fromBackingInt(732) };

test "BMC view snapshot owns resource paths and retained error strings after source mutation" {
    var code = "SyntheticReadError".*;
    var fixture: Fixture = .{};
    fixture.progress.event_count = 1;
    fixture.progress.events[0] = .{ .stage = .redfish_discovery, .error_code = &code, .context = .{ .method = .get, .resource_path = console.progress.resourcePath("/redfish/v1/Systems/node-B/BootOptions/Boot0001"), .http_status = 404, .response_errors = console.progress.ResponseErrors.init("Base.1.19.ResourceNotFound") } };
    fixture.progress.failure_code = &code;
    fixture.progress.failure_event = fixture.progress.events[0];
    fixture.progress.discovery_issue = fixture.progress.events[0];
    var snapshot = try Fixture.snapshot(&fixture, undefined, a);
    defer snapshot.deinit();
    @memset(&code, 'x');
    fixture.progress = .{};
    const value = snapshot.value.progress;
    try std.testing.expectEqualStrings("SyntheticReadError", value.failure_code.?);
    try std.testing.expectEqualStrings("SyntheticReadError", value.failure_event.?.error_code.?);
    try std.testing.expectEqualStrings("SyntheticReadError", value.discovery_issue.?.error_code.?);
    try std.testing.expectEqualStrings("SyntheticReadError", value.events[0].error_code.?);
    try std.testing.expectEqualStrings("/redfish/v1/Systems/node-B/BootOptions/Boot0001", value.events[0].context.?.resource_path.?.text());
    try std.testing.expectEqualStrings("Base.1.19.ResourceNotFound", value.events[0].context.?.response_errors.?.text());
}

test "BMC view mapping preserves fit aspect, rejects letterbox and clamps captured drag" {
    const g = mapping.Geometry.calculate(.{ .x = 8, .y = 94, .width = 1194, .height = 750 }, 1920, 1200, .fit, .{ .x = 0, .y = 0 }).?;
    try std.testing.expectApproxEqAbs(@as(f32, 0.621875), g.scale, 0.00001);
    try std.testing.expectApproxEqAbs(@as(f32, 95.875), g.image.y, 0.001);
    try std.testing.expect(g.remote(.{ .x = 500, .y = 94 }, false) == null);
    const top_left = g.remote(.{ .x = 8, .y = 95.875 }, false).?;
    try std.testing.expectEqual(@as(u16, 0), top_left.x);
    try std.testing.expectEqual(@as(u16, 0), top_left.y);
    const center = g.remote(.{ .x = 605, .y = 469 }, false).?;
    try std.testing.expectEqual(@as(u16, 960), center.x);
    try std.testing.expectEqual(@as(u16, 600), center.y);
    const dragged = g.remote(.{ .x = 9999, .y = -20 }, true).?;
    try std.testing.expectEqual(@as(u16, 1919), dragged.x);
    try std.testing.expectEqual(@as(u16, 0), dragged.y);
}

test "BMC view mapping original uses logical units and bounded scroll once at Retina" {
    const g = mapping.Geometry.calculate(.{ .x = 8, .y = 94, .width = 844, .height = 346 }, 1920, 1200, .original, .{ .x = 400, .y = 200 }).?;
    try std.testing.expectEqual(@as(f32, 1), g.scale);
    const pixel = g.remote(.{ .x = 18, .y = 104 }, false).?;
    try std.testing.expectEqual(@as(u16, 410), pixel.x);
    try std.testing.expectEqual(@as(u16, 210), pixel.y);
    const clamped = mapping.Geometry.calculate(g.viewport, 1920, 1200, .original, .{ .x = 10000, .y = 10000 }).?;
    try std.testing.expectEqual(@as(f32, 1076), clamped.scroll_x);
    try std.testing.expectEqual(@as(f32, 854), clamped.scroll_y);
}

test "BMC view keys retain the down symbol and reserve only Control Alt Escape" {
    var keyboard: mapping.Keyboard = .{};
    try std.testing.expectEqual(@as(u32, 'A'), keyboard.key(0, .{ .shift = true }, true).?.keysym);
    try std.testing.expectEqual(@as(u32, 'A'), keyboard.key(0, .{}, true).?.keysym); // repeat after Shift-up keeps the original down paired
    try std.testing.expectEqual(@as(u32, 'A'), keyboard.key(0, .{}, false).?.keysym);
    try std.testing.expectEqual(@as(u32, 0xffeb), mapping.keysym(55, false).?);
    try std.testing.expectEqual(@as(u32, 0xffe3), mapping.keysym(59, false).?);
    try std.testing.expect(mapping.keysym(0xffff, false) == null);
    try std.testing.expect(mapping.isReleaseShortcut(53, .{ .ctrl = true, .alt = true }));
    try std.testing.expect(!mapping.isReleaseShortcut(53, .{}));
    try std.testing.expectEqual(@as(u32, 0xff1b), mapping.keysym(53, false).?);
}

test "BMC view wheel keeps trackpad remainder and mouse wheel steps" {
    var wheel: mapping.WheelAccumulator = .{};
    try std.testing.expectEqual(@as(i8, 0), wheel.add(0, 21, true).y);
    try std.testing.expectEqual(@as(i8, -1), wheel.add(0, 21, true).y);
    try std.testing.expectApproxEqAbs(@as(f32, -2), wheel.y, 0.001);
    try std.testing.expectEqual(@as(i8, 1), wheel.add(0, -0.1, false).y);
    try std.testing.expectEqual(@as(i8, 0), wheel.add(std.math.nan(f32), 0, true).x);
}

fn bootSnapshot() services.BootSnapshot {
    return .{ .system_uri = "/redfish/v1/Systems/1", .write_uri = "/redfish/v1/Systems/1", .state = .{ .enabled = "Disabled", .target = "None", .mode = "UEFI" }, .allowed_enabled = .{ .value = &.{ "Disabled", "Once", "Continuous" }, .evidence = .{ .validity = .valid } }, .allowed_targets = .{ .value = &.{ "None", "Pxe", "Hdd", "Usb" }, .evidence = .{ .validity = .valid } }, .allowed_modes = .{ .value = &.{ "UEFI", "Legacy" }, .evidence = .{ .validity = .valid } }, .enabled_evidence = .{ .validity = .valid }, .target_evidence = .{ .validity = .valid }, .mode_evidence = .{ .validity = .valid } };
}

test "BMC view Boot draft persists fields across menu changes and disable restores selection" {
    var draft: vm.BootDraft = .{};
    const snapshot = bootSnapshot();
    try draft.refresh(snapshot);
    try std.testing.expect(!draft.dirty());
    try draft.selectTarget("Pxe");
    try draft.setContinuous(true);
    try draft.selectMode("Legacy");
    try draft.refresh(snapshot);
    try std.testing.expect(draft.value.target.equal("Pxe"));
    try std.testing.expect(draft.continuous());
    try std.testing.expect(draft.value.mode.equal("Legacy"));
    try draft.selectTarget("Disabled");
    try std.testing.expect(draft.disabled());
    try std.testing.expect(!draft.dirty()); // already Disabled: hidden fields are not a patch
    try draft.selectTarget("Pxe");
    try std.testing.expect(draft.continuous());
    try std.testing.expect(draft.value.mode.equal("Legacy"));
    try std.testing.expect(!draft.canApply(snapshot)); // production default is read-only
}

test "BMC view Boot draft retains conflicts and never treats None as Disabled" {
    var draft: vm.BootDraft = .{};
    var snapshot = bootSnapshot();
    snapshot.state = .{ .enabled = "Once", .target = "None", .mode = "UEFI" };
    try draft.refresh(snapshot);
    try std.testing.expect(!draft.disabled());
    try draft.selectTarget("Pxe");
    snapshot.state.target = "Usb";
    try draft.refresh(snapshot);
    try std.testing.expect(draft.conflict);
    try std.testing.expect(draft.value.target.equal("Pxe"));
    try std.testing.expect(draft.baseline.target.equal("Usb"));
}

test "BMC view capability gate rejects unknown authentication, partial evidence and unsupported action" {
    var snapshot: services.PowerSnapshot = .{ .reset_target = "/reset", .state = .{ .value = .on, .evidence = .{ .validity = .valid } }, .reset_types = .{ .value = &.{"GracefulRestart"}, .evidence = .{ .validity = .valid } }, .capability = .{ .write_granted = true, .system_mapping_verified = true, .secondary_auth = .disabled, .secondary_auth_evidence = .{ .validity = .valid } } };
    try std.testing.expect(vm.powerAllowed(snapshot, .graceful_restart));
    try std.testing.expect(!vm.powerAllowed(snapshot, .force_restart));
    snapshot.capability.secondary_auth = .unknown;
    try std.testing.expect(!vm.powerAllowed(snapshot, .graceful_restart));
    snapshot.capability.secondary_auth = .disabled;
    snapshot.reset_types.evidence.validity = .partial_with_error;
    try std.testing.expect(!vm.powerAllowed(snapshot, .graceful_restart));
    snapshot.reset_types.evidence.corroborated = true;
    try std.testing.expect(vm.powerAllowed(snapshot, .graceful_restart));
}

test "BMC view resource diagnostics do not replace operation field validation" {
    const cap: services.Capability = .{ .write_requestable = true, .system_mapping_verified = true, .secondary_auth = .disabled, .secondary_auth_evidence = .{ .validity = .valid } };
    var power: services.PowerSnapshot = .{ .resource_evidence = .{ .validity = .partial_with_error }, .capability = cap, .reset_target = "/redfish/v1/Systems/1/Actions/ComputerSystem.Reset", .state = .{ .value = .on, .evidence = .{ .validity = .valid } }, .reset_types = .{ .value = &.{"GracefulRestart"}, .evidence = .{ .validity = .valid } } };
    var boot = bootSnapshot();
    boot.capability = cap;
    boot.resource_evidence.validity = .partial_with_error;
    boot.boot_order.evidence.validity = .partial_with_error;
    boot.mode_evidence.validity = .partial_with_error;
    var draft: vm.BootDraft = .{};
    try draft.refresh(boot);
    try draft.selectTarget("Pxe");
    try std.testing.expect(vm.powerAllowed(power, .graceful_restart));
    try std.testing.expect(draft.canApply(boot)); // Neither BootOrder nor unchanged mode is required.
    power.state.evidence.validity = .partial_with_error;
    try std.testing.expect(!vm.powerAllowed(power, .graceful_restart));
    try std.testing.expect(draft.canApply(boot));
    power.state.evidence.validity = .valid;
    boot.target_evidence.validity = .partial_with_error;
    try std.testing.expect(!draft.canApply(boot));
    try std.testing.expect(vm.powerAllowed(power, .graceful_restart));
}

test "BMC view closing Boot override requires no target or mode proof" {
    var boot = bootSnapshot();
    boot.capability = .{ .write_requestable = true, .system_mapping_verified = true, .secondary_auth = .disabled, .secondary_auth_evidence = .{ .validity = .valid } };
    boot.state = .{ .enabled = "Once", .target = null, .mode = null };
    boot.target_evidence.validity = .partial_with_error;
    boot.mode_evidence.validity = .partial_with_error;
    boot.allowed_targets = .{};
    boot.allowed_modes = .{};
    var draft: vm.BootDraft = .{};
    try draft.refresh(boot);
    try draft.selectTarget("Disabled");
    try std.testing.expect(draft.canApply(boot));
    try std.testing.expect(draft.unavailableReason(boot) == null);
    boot.enabled_evidence.validity = .partial_with_error;
    try std.testing.expect(!draft.canApply(boot));
}

test "BMC view failure keeps explicit stale frame state separate from completed cleanup" {
    const state: console.Snapshot = .{ .owner = owner, .operation = .{ .owner = .{ .session = owner }, .operation_id = 1 }, .route = .failed, .video = .failed, .cleanup = .released, .input = .{ .input_epoch = 1, .control_generation = 1, .transport_generation = 1, .connected = false, .controlled = false, .focused = false, .capture_paused = true, .queued = 0, .remote_unconfirmed = false } };
    try std.testing.expectEqualStrings("视频已中断 · 画面已停止更新", vm.statusTitle(state, true));
    try std.testing.expectEqualStrings("连接失败", vm.statusTitle(state, false));
    var ended = state;
    ended.route = .closed;
    try std.testing.expectEqualStrings("连接已结束", vm.statusTitle(ended, true));
}

test "BMC view progress uses visited evidence without inventing optional steps and preserves failures" {
    var projection: vm.ProgressProjection = .{};
    var value: console.progress.Snapshot = .{ .revision = 5, .stage = .waiting_credentials, .waiting_for_user = true, .event_count = 5 };
    for ([_]console.progress.Stage{ .route, .tls_handshake, .public_identity, .public_script, .waiting_credentials }, 0..) |stage, index| value.events[index] = .{ .sequence = index + 1, .at_ms = index * 100, .stage = stage };
    projection.observe(value);
    try std.testing.expectEqual(vm.StepState.done, projection.state(value, .route));
    try std.testing.expectEqual(vm.StepState.waiting_for_user, projection.state(value, .authentication));
    try std.testing.expectEqual(vm.StepState.waiting, projection.state(value, .management));
    try std.testing.expectEqual(vm.StepState.waiting, projection.state(value, .video));
    // A second TLS channel can revisit earlier work; enum order is irrelevant.
    value.stage = .tls_handshake;
    value.waiting_for_user = false;
    projection.observe(value);
    try std.testing.expectEqual(vm.StepState.current, projection.state(value, .tls));
    value = .{ .revision = 39, .stage = .cleanup, .failure_stage = .public_script, .failure_code = "UnsupportedProfilePublicEvidenceUnavailable", .event_count = 1 };
    value.events[0] = .{ .sequence = 39, .stage = .cleanup };
    projection.observe(value);
    try std.testing.expectEqual(vm.StepState.failed, projection.state(value, .identity));
    try std.testing.expectEqual(vm.StepState.done, projection.state(value, .route)); // retained when the event ring rotates
    try std.testing.expectEqual(vm.StepState.waiting, projection.state(value, .management));
    try std.testing.expectEqualStrings("无法取得可验证的公开设备信息，设备兼容性尚未确认。", vm.failureReason(value.failure_code, value.failure_stage));
    var cancelled: vm.ProgressProjection = .{};
    value = .{ .revision = 2, .stage = .cancelled, .event_count = 2 };
    value.events[0] = .{ .sequence = 1, .stage = .route };
    value.events[1] = .{ .sequence = 2, .stage = .cancelled };
    cancelled.observe(value);
    try std.testing.expectEqual(vm.StepState.stopped, cancelled.state(value, .route));
    try std.testing.expectEqual(vm.StepState.waiting, cancelled.state(value, .tls));
}

test "BMC view connection log formats only bounded typed telemetry and warns on mapping diagnostics" {
    var value: console.progress.Snapshot = .{ .revision = 3, .stage = .streaming, .event_count = 3 };
    value.events[0] = .{ .sequence = 1, .at_ms = 1234, .stage = .redfish_discovery, .kind = .http_response, .resource = .system, .http_status = 200 };
    value.events[1] = .{ .sequence = 2, .at_ms = 2234, .stage = .redfish_discovery, .kind = .diagnostic, .code = .mapping_system_reverse_link_missing };
    value.events[2] = .{ .sequence = 3, .at_ms = 3234, .stage = .public_script, .kind = .failure, .error_code = "UnsupportedProfilePublicEvidenceUnavailable" };
    var projection: vm.ProgressProjection = .{};
    projection.observe(value);
    try std.testing.expectEqual(vm.StepState.warning, projection.state(value, .management));
    var writer: std.Io.Writer.Allocating = .init(a);
    defer writer.deinit();
    try vm.writeConnectionLog(&writer.writer, value);
    try std.testing.expect(std.mem.indexOf(u8, writer.written(), "+1.2 s  Redfish 只读发现 · 系统资源 · HTTP 200") != null);
    try std.testing.expect(std.mem.indexOf(u8, writer.written(), "系统映射未验证：缺少反向管理器关系") != null);
    try std.testing.expect(std.mem.indexOf(u8, writer.written(), "UnsupportedProfilePublicEvidenceUnavailable") != null);
    try std.testing.expect(std.mem.indexOf(u8, writer.written(), "首帧就绪") == null);
}

test "BMC view progress diagnostics identify safe request and retain user collapse after cleanup" {
    const context: console.progress.Context = .{ .channel = .management, .method = .get, .path = .public_script, .phase = .response_body, .http_status = 200, .received_bytes = 524288, .duration_ms = 15000 };
    var tracker = console.progress.Tracker.initAt(1, 0);
    tracker.setStageAt(.public_script, 1);
    tracker.setContext(context);
    tracker.failAt(error.HttpTimeout, 15001);
    var disclosure: vm.ProgressDisclosure = .{};
    disclosure.observe(tracker.snapshotAt(15001));
    try std.testing.expect(disclosure.isOpen(.identity));
    try std.testing.expect(!disclosure.isOpen(.tls));
    disclosure.toggle(.identity);
    tracker.setStageAt(.cleanup, 15002);
    for (0..40) |index| tracker.noteAt(.{ .code = .remote_logout_unconfirmed, .resource = .web_session }, 15003 + index);
    tracker.finishAt(false, 15100);
    const snapshot = tracker.snapshotAt(16000);
    disclosure.observe(snapshot);
    try std.testing.expect(!disclosure.isOpen(.identity));
    var writer: std.Io.Writer.Allocating = .init(a);
    defer writer.deinit();
    try vm.writeStepDiagnosticsForTarget(&writer.writer, snapshot, .identity, "offline.invalid:443");
    for ([_][]const u8{ "保留的原始失败", "管理通道 → offline.invalid:443", "GET /js/app.0bc71eb0.js", "读取响应正文", "HTTP 200", "已收 524288 B", "请求 15 s", "HttpTimeout" }) |text| try std.testing.expect(std.mem.indexOf(u8, writer.written(), text) != null);
    writer.clearRetainingCapacity();
    try vm.writeStepDiagnostics(&writer.writer, snapshot, .tls);
    try std.testing.expectEqualStrings("该步骤尚无连接事件。", writer.written());
    try std.testing.expect(std.mem.indexOf(u8, console.progress.pathLabel(.web_session), "{id}") != null);
}

const Fixture = struct {
    real_input: ?*remote.Service = null,
    management_available: bool = false,
    system_mapping_verified: bool = true,
    management_write_requestable: bool = false,
    resource_diagnostic: bool = false,
    boot_order: ?[]const []const u8 = null,
    management_writes: usize = 0,
    /// Bump after changing management data a field above does not cover.
    management_epoch: u64 = 0,
    frame_generation: u64 = 1,
    width: u32 = 2,
    height: u32 = 2,
    focused: bool = false,
    releases: usize = 0,
    /// Owner reads made by the renderer (what a frame costs the owner).
    snapshot_reads: usize = 0,
    pulse_reads: usize = 0,
    submitted: usize = 0,
    control_requests: usize = 0,
    cancel_requests: usize = 0,
    retry_requests: usize = 0,
    route: console.RouteState = .connected,
    video: console.VideoState = .streaming,
    cleanup: console.Cleanup = .not_started,
    progress: console.progress.Snapshot = .{},
    route_summary: []const u8 = "本机 → SSH 链 → offline.invalid",
    input_state: remote.Snapshot = .{ .input_epoch = 1, .control_generation = 1, .transport_generation = 1, .connected = true, .controlled = true, .focused = false, .capture_paused = false, .queued = 0, .remote_unconfirmed = false },
    fn lookup(raw: *anyopaque, requested: identity.SessionHandle, definition: typed.Definition) !?typed.Binding {
        if (!requested.eql(owner)) return error.StaleSession;
        if (definition.matches(console.definition)) return typed.Binding.init(console.Interface, console.key, raw, &console_table, owner, 1);
        if (definition.matches(remote.definition)) {
            const self: *Fixture = @ptrCast(@alignCast(raw));
            return if (self.real_input) |service| service.binding() else typed.Binding.init(remote.Interface, remote.key, raw, &input_table, owner, 1);
        }
        if (definition.matches(services.boot_definition)) {
            const self: *Fixture = @ptrCast(@alignCast(raw));
            if (self.management_available) return typed.Binding.init(services.BootService, services.boot_key, raw, &boot_table, owner, 1);
        }
        if (definition.matches(services.power_definition)) {
            const self: *Fixture = @ptrCast(@alignCast(raw));
            if (self.management_available) return typed.Binding.init(services.PowerService, services.power_key, raw, &power_table, owner, 1);
        }
        return null;
    }
    fn snapshot(raw: *anyopaque, _: typed.Binding, allocator: std.mem.Allocator) !console.OwnedSnapshot {
        const self: *Fixture = @ptrCast(@alignCast(raw));
        self.snapshot_reads += 1;
        return console.OwnedSnapshot.init(allocator, try self.consoleValue());
    }
    fn consoleValue(self: *Fixture) !console.Snapshot {
        return .{ .owner = owner, .operation = .{ .owner = .{ .session = owner }, .operation_id = 1 }, .name = "Synthetic", .target = "offline.invalid", .route_summary = self.route_summary, .route = self.route, .video = self.video, .cleanup = self.cleanup, .progress = self.progress, .management = if (self.management_available) .available else .unavailable, .input = if (self.real_input) |service| try service.snapshot(service.binding()) else self.input_state, .rfb_ready = self.video == .streaming, .width = self.width, .height = self.height, .frame_generation = self.frame_generation, .frame_sequence = 1 };
    }
    /// The fixture keeps no publication counter: its tokens are hashes of what it would return,
    /// so a test that edits a field has published it.
    fn pulse(raw: *anyopaque, _: typed.Binding) !console.Pulse {
        const self: *Fixture = @ptrCast(@alignCast(raw));
        self.pulse_reads += 1;
        var management = std.hash.Wyhash.init(0);
        management.update(std.mem.asBytes(&[_]u8{ @intFromBool(self.management_available), @intFromBool(self.system_mapping_verified), @intFromBool(self.management_write_requestable), @intFromBool(self.resource_diagnostic) }));
        management.update(std.mem.asBytes(&self.management_writes));
        management.update(std.mem.asBytes(&self.management_epoch));
        if (self.boot_order) |order| for (order) |entry| management.update(entry);
        return .{ .state = console.stateToken(try self.consoleValue()), .management = management.final() };
    }
    fn request(raw: *anyopaque, _: typed.Binding) !void {
        const self: *Fixture = @ptrCast(@alignCast(raw));
        self.control_requests += 1;
    }
    fn reply(_: *anyopaque, _: typed.Binding, _: [4]u8, _: console.ControlReply) !void {}
    fn refresh(_: *anyopaque, _: typed.Binding) !void {}
    fn focus(raw: *anyopaque, _: typed.Binding, value: bool) !void {
        const self: *Fixture = @ptrCast(@alignCast(raw));
        self.focused = value;
        self.input_state.focused = value;
        if (self.real_input) |service| service.setFocus(value);
    }
    fn retry(raw: *anyopaque, _: typed.Binding) !void {
        const self: *Fixture = @ptrCast(@alignCast(raw));
        self.retry_requests += 1;
    }
    fn cancel(raw: *anyopaque, _: typed.Binding) !void {
        const self: *Fixture = @ptrCast(@alignCast(raw));
        self.cancel_requests += 1;
    }
    const console_table: console.Interface = .{ .snapshot = snapshot, .pulse = pulse, .request_control = request, .reply_control = reply, .refresh = refresh, .set_focus = focus, .retry = retry, .cancel = cancel };
    fn inputSnapshot(raw: *anyopaque, _: typed.Binding) !remote.Snapshot {
        const self: *Fixture = @ptrCast(@alignCast(raw));
        return self.input_state;
    }
    fn submit(raw: *anyopaque, _: typed.Binding, command: remote.Command) remote.SubmitResult {
        const self: *Fixture = @ptrCast(@alignCast(raw));
        if (!self.focused) return .not_focused;
        self.submitted += 1;
        return .{ .accepted = command.input_sequence };
    }
    fn releaseAll(raw: *anyopaque, _: typed.Binding, _: remote.ReleaseCause) remote.ReleaseResult {
        const self: *Fixture = @ptrCast(@alignCast(raw));
        self.releases += 1;
        self.input_state.input_epoch += 1;
        return .accepted;
    }
    const input_table: remote.Interface = .{ .snapshot = inputSnapshot, .submit = submit, .release_all = releaseAll };
    fn readBoot(raw: *anyopaque, _: services.Call, allocator: std.mem.Allocator) !services.OwnedBootSnapshot {
        const self: *Fixture = @ptrCast(@alignCast(raw));
        var value = bootSnapshot();
        value.capability.system_mapping_verified = self.system_mapping_verified;
        value.capability.write_granted = false;
        value.capability.write_requestable = self.management_write_requestable;
        value.capability.secondary_auth = .disabled;
        value.capability.secondary_auth_evidence.validity = .valid;
        value.resource_evidence.validity = if (self.resource_diagnostic) .partial_with_error else .valid;
        value.state = .{ .enabled = "Once", .target = "Pxe", .mode = "UEFI" };
        value.boot_order = .{ .value = self.boot_order, .evidence = .{ .validity = .valid } };
        return services.OwnedBootSnapshot.init(allocator, value);
    }
    fn applyBoot(raw: *anyopaque, _: services.BootExecutionPatch) services.RequestResult {
        const self: *Fixture = @ptrCast(@alignCast(raw));
        self.management_writes += 1;
        return .{ .rejected = .permission_denied };
    }
    fn cancelBoot(_: *anyopaque, _: services.Call, _: services.OperationKey) services.CancelResult {
        return .stale_operation;
    }
    fn bootResult(_: *anyopaque, _: services.Call, _: services.OperationKey, _: std.mem.Allocator) !services.Owned(services.Result) {
        return error.Unavailable;
    }
    const boot_table: services.BootService = .{ .snapshot = readBoot, .apply = applyBoot, .cancel = cancelBoot, .result = bootResult };
    fn readPower(raw: *anyopaque, _: services.Call, allocator: std.mem.Allocator) !services.OwnedPowerSnapshot {
        const self: *Fixture = @ptrCast(@alignCast(raw));
        return services.OwnedPowerSnapshot.init(allocator, .{ .system_uri = "/redfish/v1/Systems/1", .resource_evidence = .{ .validity = if (self.resource_diagnostic) .partial_with_error else .valid }, .capability = .{ .system_mapping_verified = self.system_mapping_verified, .write_granted = false, .write_requestable = self.management_write_requestable, .secondary_auth = .disabled, .secondary_auth_evidence = .{ .validity = .valid } }, .state = .{ .value = .on, .evidence = .{ .validity = .valid } }, .reset_types = .{ .value = &.{ "On", "GracefulShutdown", "GracefulRestart" }, .evidence = .{ .validity = .valid } }, .reset_target = "/redfish/v1/Systems/1/Actions/ComputerSystem.Reset" });
    }
    fn requestPower(raw: *anyopaque, _: services.PowerExecutionRequest) services.RequestResult {
        const self: *Fixture = @ptrCast(@alignCast(raw));
        self.management_writes += 1;
        return .{ .rejected = .permission_denied };
    }
    const power_table: services.PowerService = .{ .snapshot = readPower, .request = requestPower, .cancel = cancelBoot, .result = bootResult };
    fn create(_: *anyopaque, _: u32, _: u32) !u32 {
        return 77;
    }
    fn upload(_: *anyopaque, _: u32, _: []const u8) !void {}
    fn release(_: *anyopaque, _: u32) void {}
};

test "BMC view native renderer uses real sink, captures on image, releases on menu and unmount preserves host sink" {
    var fixture: Fixture = .{ .management_available = true };
    const cx = try ui.Cx.init(a, std.testing.io);
    defer cx.deinit();
    cx.setViewport(860, 480);
    const scope = try ui.Scope.init(a, null, cx.owner);
    defer scope.dispose();
    cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    var sink = frames.Sink.init(owner, .{ .context = &fixture, .create = Fixture.create, .update = Fixture.upload, .release = Fixture.release });
    defer sink.close() catch unreachable;
    try sink.submit(try frames.Frame.copy(a, owner, 1, 2, 2, &.{ 255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 255 }));
    _ = try sink.drain();
    const renderer = try views.mount(null, .{ .cx = cx, .scope = scope, .slot = cx.root.?, .owner = owner, .connection = .{ .protocol_id = "bmc_ikvm", .name = "Synthetic", .payload = "{}" }, .frame_sink = &sink, .service_access = access.SessionServiceAccess{ .context = &fixture, .owner = owner, .lookup_fn = Fixture.lookup } });
    defer renderer.vtable.unmount(renderer.context);
    const view: *views.View = @ptrCast(@alignCast(renderer.context));
    for (0..3) |_| {
        cx.frame_count += 1;
        cx.frame_time_ms += 34;
        _ = cx.render();
    }
    try std.testing.expectEqual(@as(?u32, 77), view.image_node.?.getImage().?.texture_id);
    try std.testing.expectEqual(.online, renderer.vtable.connection_status.?(renderer.context).state);
    try std.testing.expect(!view.captured);
    const rect = view.viewport.?.globalRect();
    try std.testing.expectApproxEqAbs(@import("../styles.zig").toolbar_height, view.toolbar.?.globalRect().h, 0.01);
    // The menu buttons are zenit's native Buttons at their own size, inside the toolbar.
    const tool = view.tool_nodes[0].?.globalRect();
    const bar = view.toolbar.?.globalRect();
    try std.testing.expect(tool.w > 0 and tool.h > 0 and tool.y >= bar.y - 0.01 and tool.y + tool.h <= bar.y + bar.h + 0.01);
    const event: ui.events.Event = .{ .mouse_down = .{ .x = rect.x + rect.w / 2, .y = rect.y + rect.h / 2 } };
    _ = view.viewport.?.behavior.events.on_event_capture.?(event, view);
    try std.testing.expect(view.captured);
    try std.testing.expectEqual(@as(usize, 1), fixture.submitted);
    _ = view.viewport.?.behavior.events.on_event_capture.?(.{ .key_down = .{ .key = .escape } }, view);
    try std.testing.expectEqual(@as(usize, 2), fixture.submitted);
    try std.testing.expect(view.captured);
    _ = view.viewport.?.behavior.events.on_event_capture.?(.{ .text_input = .{ .text = "x" } }, view);
    try std.testing.expectEqual(@as(usize, 2), fixture.submitted);
    _ = view.viewport.?.behavior.events.on_event_capture.?(.{ .key_down = .{ .key = .escape, .modifiers = .{ .ctrl = true, .alt = true } } }, view);
    try std.testing.expectEqual(@as(usize, 2), fixture.submitted);
    try std.testing.expect(!view.captured);
    _ = view.viewport.?.behavior.events.on_event_capture.?(event, view);
    try std.testing.expect(view.captured);
    const before_watch = fixture.submitted;
    findById(view.menus[0].?.content, "bmc.control.view_only").?.behavior.events.on_click.?.invoke();
    _ = view.viewport.?.behavior.events.on_event_capture.?(event, view);
    try std.testing.expect(!view.captured);
    try std.testing.expectEqual(before_watch, fixture.submitted);
    findById(view.menus[0].?.content, "bmc.control.capture").?.behavior.events.on_click.?.invoke();
    for (0..3) |_| {
        cx.frame_count += 1;
        cx.frame_time_ms += 34;
        _ = cx.render();
    }
    try std.testing.expect(view.captured);
    view.tool_nodes[4].?.behavior.events.on_click.?.invoke();
    for (0..8) |_| {
        cx.frame_count += 1;
        cx.frame_time_ms += 34;
        _ = cx.render();
    }
    try std.testing.expect(!view.captured);
    try std.testing.expect(!fixture.focused);
    try std.testing.expect(view.open[4].peek());
    try std.testing.expect(view.menus[4].?.chrome.getOpacity() > 0.98);
    try std.testing.expectEqual(.none, view.boot_mapping_warning.?.style.display);
    try std.testing.expectEqual(.none, view.order_mapping_warning.?.style.display);
    const popup = view.menus[4].?.chrome.globalRect();
    try std.testing.expectApproxEqAbs(@as(f32, 312), popup.w, 0.01);
    const execute = findById(view.menus[4].?.content, "bmc.boot.execute").?.globalRect();
    // 执行 is zenit's native secondary Button at its own size, inside the panel.
    try std.testing.expect(execute.w > 0 and execute.x >= popup.x and execute.x + execute.w <= popup.x + popup.w + 0.01);
    try std.testing.expect(popup.h > 100 and popup.y >= 0 and popup.y + popup.h <= 480);
    // 持续生效 is a native zenit sm Switch: recipe geometry, thumb at its rest offset (no inline pin).
    const continuous = findById(view.menus[4].?.content, "bmc.boot.continuous").?;
    const sizes = cx.tokens.tokens.size;
    const track = continuous.children.items[0];
    try std.testing.expectApproxEqAbs(sizes.switch_width_sm, track.globalRect().w, 0.01);
    try std.testing.expectApproxEqAbs(sizes.switch_height_sm, track.globalRect().h, 0.01);
    try std.testing.expectApproxEqAbs(sizes.switch_thumb_sm, track.children.items[0].globalRect().w, 0.01);
    const rest: f32 = if (view.boot_continuous.peek()) sizes.switch_width_sm - sizes.switch_thumb_sm - 2 else 2;
    try std.testing.expectApproxEqAbs(rest, track.children.items[0].globalRect().x - track.globalRect().x, 0.01);
    try std.testing.expectEqual(ui.A11yRole.switch_role, continuous.behavior.interaction.a11y.?.role);
    view.tool_nodes[1].?.behavior.events.on_click.?.invoke();
    for (0..5) |_| {
        cx.frame_count += 1;
        cx.frame_time_ms += 34;
        _ = cx.render();
    }
    const key_scroll = view.menu_scrolls[1].?;
    ui.widgets.scroll_area.setScrollY(key_scroll.state, key_scroll.content, key_scroll.state.maxScrollY());
    for (0..3) |_| {
        cx.frame_count += 1;
        cx.frame_time_ms += 34;
        _ = cx.render();
    }
    const keys_popup = view.menus[1].?.chrome.globalRect();
    const keys_close = findById(view.menus[1].?.chrome, "bmc.keys.close").?.globalRect();
    try std.testing.expect(keys_close.y >= keys_popup.y and keys_close.y + keys_close.h <= keys_popup.y + keys_popup.h);
    view.tool_nodes[2].?.behavior.events.on_click.?.invoke();
    renderFrames(cx, 8);
    findById(view.menus[2].?.content, "bmc.display.connection_log").?.behavior.events.on_click.?.invoke();
    renderFrames(cx, 8);
    try std.testing.expect(view.log_open.?.peek());
    try std.testing.expectEqual(console.VideoState.streaming, view.snapshot.?.value.video);
    try std.testing.expectEqual(@as(?u32, 77), view.texture);
    try std.testing.expect(!view.captured);
    findById(view.log_modal.?.dialog, "bmc.connection_log.dismiss").?.behavior.events.on_click.?.invoke();
    renderFrames(cx, 8);
    try std.testing.expect(!view.log_open.?.peek());
    try std.testing.expectEqual(@as(usize, 0), fixture.cancel_requests);
    renderer.vtable.focus_changed(renderer.context, false);
    try std.testing.expect(!view.captured);
    try std.testing.expect(!fixture.focused);
    renderer.vtable.focus_changed(renderer.context, true);
    fixture.frame_generation = 2; // CPU generation is newer than the uploaded sink.
    try renderer.vtable.update(renderer.context, .{ .owner = owner, .revision = 2, .title = "Synthetic", .status = "" });
    const before_waiting_frame = fixture.submitted;
    _ = view.viewport.?.behavior.events.on_event_capture.?(event, view);
    try std.testing.expect(!view.captured);
    try std.testing.expectEqual(before_waiting_frame, fixture.submitted);
    try std.testing.expect(view.texture == null);
    renderer.vtable.unmount(renderer.context);
    try std.testing.expect(sink.texture != null);
    try std.testing.expect(view.closed);
}

test "BMC view management target and response diagnostics keep distinct mounted operation gates" {
    var fixture: Fixture = .{ .management_available = true, .system_mapping_verified = false };
    const cx = try ui.Cx.init(a, std.testing.io);
    defer cx.deinit();
    cx.setViewport(1440, 900);
    const scope = try ui.Scope.init(a, null, cx.owner);
    defer scope.dispose();
    cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    var sink = frames.Sink.init(owner, .{ .context = &fixture, .create = Fixture.create, .update = Fixture.upload, .release = Fixture.release });
    defer sink.close() catch unreachable;
    try sink.submit(try frames.Frame.copy(a, owner, 1, 2, 2, &.{ 255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 255 }));
    _ = try sink.drain();
    const renderer = try views.mount(null, .{ .cx = cx, .scope = scope, .slot = cx.root.?, .owner = owner, .connection = .{ .protocol_id = "bmc_ikvm", .name = "Synthetic", .payload = "{}" }, .frame_sink = &sink, .service_access = access.SessionServiceAccess{ .context = &fixture, .owner = owner, .lookup_fn = Fixture.lookup } });
    defer renderer.vtable.unmount(renderer.context);
    const view: *views.View = @ptrCast(@alignCast(renderer.context));
    const warning = "尚未确认管理目标或系统信息的来源，仅供查看";
    view.tool_nodes[3].?.behavior.events.on_click.?.invoke();
    for (0..8) |_| {
        cx.frame_count += 1;
        cx.frame_time_ms += 34;
        _ = cx.render();
    }
    try std.testing.expect(view.menus[3].?.chrome.getOpacity() > 0.98);
    const unverified_status = renderer.vtable.connection_status.?(renderer.context);
    try std.testing.expectEqual(.degraded, unverified_status.state);
    try std.testing.expectEqualStrings("视频已连接 · 管理条件待核实", unverified_status.label);
    try std.testing.expectEqualStrings(warning, view.power_mapping_warning.?.getText().?.content);
    try std.testing.expectEqual(.flex, view.power_mapping_warning.?.style.display);
    try std.testing.expect(view.power_mapping_warning.?.globalRect().h > 0);
    try std.testing.expectEqualStrings("资源电源状态", view.power_scope_label.?.getText().?.content);
    try std.testing.expectEqualStrings("开机", view.power_label.?.getText().?.content);
    const power_execute = findById(view.menus[3].?.content, "bmc.power.execute").?;
    try std.testing.expect(!power_execute.behavior.interaction.focusable);
    power_execute.behavior.events.on_click.?.invoke();
    view.tool_nodes[4].?.behavior.events.on_click.?.invoke();
    for (0..8) |_| {
        cx.frame_count += 1;
        cx.frame_time_ms += 34;
        _ = cx.render();
    }
    try std.testing.expect(view.menus[4].?.chrome.getOpacity() > 0.98);
    try std.testing.expectEqualStrings(warning, view.boot_mapping_warning.?.getText().?.content);
    try std.testing.expectEqual(.flex, view.boot_mapping_warning.?.style.display);
    try std.testing.expect(view.boot_mapping_warning.?.globalRect().h > 0);
    try std.testing.expectEqualStrings("资源启动覆盖", view.boot_scope_label.?.getText().?.content);
    try std.testing.expect(view.power_disabled.peek() and view.boot_disabled.peek() and view.switch_disabled.peek());
    try std.testing.expect(!view.power_snapshot.?.value.capability.write_granted);
    try std.testing.expect(!view.boot_snapshot.?.value.capability.system_mapping_verified);
    try std.testing.expectEqual(services.Validity.valid, view.boot_snapshot.?.value.enabled_evidence.validity);
    const boot_execute = findById(view.menus[4].?.content, "bmc.boot.execute").?;
    try std.testing.expect(!boot_execute.behavior.interaction.focusable);
    boot_execute.behavior.events.on_click.?.invoke();
    findById(view.menus[4].?.content, "bmc.boot.order").?.behavior.events.on_click.?.invoke();
    for (0..8) |_| {
        cx.frame_count += 1;
        cx.frame_time_ms += 34;
        _ = cx.render();
    }
    try std.testing.expect(view.order_open.?.peek());
    try std.testing.expectEqualStrings(warning, view.order_mapping_warning.?.getText().?.content);
    try std.testing.expectEqual(.flex, view.order_mapping_warning.?.style.display);
    try std.testing.expect(view.order_mapping_warning.?.globalRect().h > 0);
    try std.testing.expectEqual(@as(usize, 0), fixture.management_writes);
    fixture.system_mapping_verified = true;
    cx.frame_time_ms += 1001;
    try renderer.vtable.update(renderer.context, .{ .owner = owner, .revision = 2, .title = "Synthetic", .status = "" });
    try std.testing.expectEqual(.none, view.power_mapping_warning.?.style.display);
    try std.testing.expectEqual(.none, view.boot_mapping_warning.?.style.display);
    try std.testing.expectEqual(.none, view.order_mapping_warning.?.style.display);
    try std.testing.expectEqualStrings("当前电源", view.power_scope_label.?.getText().?.content);
    try std.testing.expectEqualStrings("当前启动覆盖", view.boot_scope_label.?.getText().?.content);
    // Mapping verified but no write authority (neither granted nor requestable): the whole
    // management draft stays read-only, not only the execute buttons.
    try std.testing.expect(!view.power_snapshot.?.value.capability.write_granted and !view.power_snapshot.?.value.capability.write_requestable);
    try std.testing.expect(view.power_disabled.peek() and view.boot_disabled.peek() and view.mode_disabled.peek() and view.switch_disabled.peek());
    try std.testing.expect(view.power_execute_disabled.peek() and view.boot_execute_disabled.peek());
    try std.testing.expectEqual(.online, renderer.vtable.connection_status.?(renderer.context).state);
    fixture.resource_diagnostic = true;
    fixture.management_write_requestable = true;
    view.power_choice = .graceful_restart;
    try view.draft.selectTarget("Hdd");
    cx.frame_time_ms += 1001;
    try renderer.vtable.update(renderer.context, .{ .owner = owner, .revision = 3, .title = "Synthetic", .status = "" });
    try std.testing.expectEqualStrings("设备响应含附加诊断；以下字段按各自读取结果显示。", view.power_mapping_warning.?.getText().?.content);
    try std.testing.expectEqual(.flex, view.power_mapping_warning.?.style.display);
    try std.testing.expectEqual(.flex, view.boot_mapping_warning.?.style.display);
    try std.testing.expectEqualStrings("开机", view.power_label.?.getText().?.content);
    try std.testing.expect(!view.power_execute_disabled.peek());
    try std.testing.expect(!view.boot_execute_disabled.peek());
    // A requestable write makes the draft editable again.
    try std.testing.expect(!view.power_disabled.peek() and !view.boot_disabled.peek());
    try std.testing.expectEqual(@as(usize, 0), fixture.management_writes);
}

test "BMC view BootOrder has twenty separate ordered rows and scrolls in standard and compact windows" {
    const references = [_][]const u8{
        "Boot0001", "Boot0002", "Boot0003", "Boot0004", "Boot0005",
        "Boot0006", "Boot0007", "Boot0008", "Boot0009", "Boot000A",
        "Boot000B", "Boot000C", "Boot000D", "Boot000E", "Boot000F",
        "Boot0010", "Boot0011", "Boot0012", "Boot0013", "Boot0014",
    };
    var fixture: Fixture = .{ .management_available = true, .boot_order = &references };
    const cx = try ui.Cx.init(a, std.testing.io);
    defer cx.deinit();
    cx.setViewport(1440, 900);
    const scope = try ui.Scope.init(a, null, cx.owner);
    defer scope.dispose();
    cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    var sink = frames.Sink.init(owner, .{ .context = &fixture, .create = Fixture.create, .update = Fixture.upload, .release = Fixture.release });
    defer sink.close() catch unreachable;
    const renderer = try views.mount(null, .{ .cx = cx, .scope = scope, .slot = cx.root.?, .owner = owner, .connection = .{ .protocol_id = "bmc_ikvm", .name = "Synthetic", .payload = "{}" }, .frame_sink = &sink, .service_access = access.SessionServiceAccess{ .context = &fixture, .owner = owner, .lookup_fn = Fixture.lookup } });
    defer renderer.vtable.unmount(renderer.context);
    const view: *views.View = @ptrCast(@alignCast(renderer.context));
    const order_action = findById(view.menus[4].?.content, "bmc.boot.order").?;
    for ([_][2]f32{ .{ 1440, 900 }, .{ 860, 480 } }) |size| {
        cx.setViewport(size[0], size[1]);
        renderFrames(cx, 8);
        order_action.behavior.events.on_click.?.invoke();
        renderFrames(cx, 8);
        const scroll = view.order_scroll.?;
        const rows = view.order_rows.?.children.items;
        try std.testing.expect(view.order_open.?.peek());
        try std.testing.expectEqual(@as(usize, 20), rows.len);
        try std.testing.expectApproxEqAbs(@as(f32, 240), view.order_viewport.?.globalRect().h, 0.01);
        try std.testing.expect(scroll.state.maxScrollY() > 0);
        for (rows, references, 0..) |row, reference, index| {
            var expected: [64]u8 = undefined;
            try std.testing.expectEqualStrings(try std.fmt.bufPrint(&expected, "{d:0>2}  {s}", .{ index + 1, reference }), row.getText().?.content);
            try std.testing.expect(row.globalRect().h >= 22);
            if (index > 0) try std.testing.expect(row.globalRect().y >= rows[index - 1].globalRect().y + rows[index - 1].globalRect().h - 0.01);
        }
        _ = view.order_viewport.?.behavior.events.on_event_capture.?(.{ .key_down = .{ .key = .end } }, view);
        renderFrames(cx, 3);
        try std.testing.expectApproxEqAbs(scroll.state.maxScrollY(), scroll.state.scroll_y, 0.01);
        _ = view.order_viewport.?.behavior.events.on_event_capture.?(.{ .key_down = .{ .key = .home } }, view);
        renderFrames(cx, 3);
        try std.testing.expectApproxEqAbs(@as(f32, 0), scroll.state.scroll_y, 0.01);
        findById(view.order_modal.?.dialog, "bmc.boot.order_close").?.behavior.events.on_click.?.invoke();
        renderFrames(cx, 8);
        try std.testing.expect(!view.order_open.?.peek());
        order_action.behavior.events.on_click.?.invoke();
        renderFrames(cx, 8);
        cx.handleKeyDown(.escape, .{});
        cx.handleKeyUp(.escape, .{});
        renderFrames(cx, 8);
        try std.testing.expect(!view.order_open.?.peek());
    }
    fixture.boot_order = &references[0..2].*;
    cx.frame_time_ms += 1001;
    try renderer.vtable.update(renderer.context, .{ .owner = owner, .revision = 2, .title = "Synthetic", .status = "" });
    try std.testing.expectEqual(.flex, view.order_rows.?.children.items[1].style.display);
    try std.testing.expectEqual(.none, view.order_rows.?.children.items[2].style.display);
    fixture.boot_order = null;
    cx.frame_time_ms += 1001;
    try renderer.vtable.update(renderer.context, .{ .owner = owner, .revision = 3, .title = "Synthetic", .status = "" });
    try std.testing.expectEqualStrings("设备尚未返回启动顺序。", view.order_rows.?.children.items[0].getText().?.content);
    try std.testing.expectEqual(.none, view.order_rows.?.children.items[1].style.display);
    try std.testing.expectEqual(@as(usize, 0), fixture.management_writes);
}

test "BMC view progress compact card scrolls independently and log close never cancels the session" {
    var fixture: Fixture = .{ .route = .connecting, .video = .authenticating, .progress = .{ .revision = 3, .stage = .public_script, .elapsed_ms = 12345, .stage_elapsed_ms = 3456, .route_hops = 2, .event_count = 3 } };
    fixture.progress.events[0] = .{ .sequence = 1, .stage = .route };
    fixture.progress.events[1] = .{ .sequence = 2, .at_ms = 1000, .stage = .tls_handshake };
    fixture.progress.events[2] = .{ .sequence = 3, .at_ms = 2000, .stage = .public_script };
    const cx = try ui.Cx.init(a, std.testing.io);
    defer cx.deinit();
    cx.setViewport(860, 480);
    const scope = try ui.Scope.init(a, null, cx.owner);
    defer scope.dispose();
    cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    // Match the measured compact shell content region: toolbar y=50..94,
    // This explicit legacy host slot remains valid; video now fills its
    // full width and all height below the 44px toolbar, without card insets.
    // The shell itself remains host-owned.
    const slot = try ui.box(cx, .{ .width = .{ .px = 844 }, .height = .{ .px = 390 }, .position = .absolute, .inset = .{ .left = .{ .px = 8 }, .top = .{ .px = 50 } } }, .{});
    try cx.root.?.appendChild(a, slot);
    const renderer = try views.mount(null, .{ .cx = cx, .scope = scope, .slot = slot, .owner = owner, .connection = .{ .protocol_id = "bmc_ikvm", .name = "Synthetic", .payload = "{}" }, .service_access = access.SessionServiceAccess{ .context = &fixture, .owner = owner, .lookup_fn = Fixture.lookup } });
    defer renderer.vtable.unmount(renderer.context);
    const view: *views.View = @ptrCast(@alignCast(renderer.context));
    renderFrames(cx, 8);
    try std.testing.expectEqualStrings("验证公开脚本摘要", view.waiting_title.?.getText().?.content);
    try std.testing.expectEqualStrings("3.5 s", view.progress_durations[2].?.getText().?.content);
    try std.testing.expectEqualStrings("12.3 s", view.progress_total_time.?.getText().?.content);
    try std.testing.expectEqualStrings("连接中", view.progress_status.?.getText().?.content);
    const title_bounds = view.waiting_title.?.globalRect();
    const route_bounds = view.progress_route.?.globalRect();
    const timing_bounds = view.progress_timing.?.globalRect();
    try std.testing.expectApproxEqAbs(@as(f32, 12), route_bounds.y - title_bounds.y - title_bounds.h, 0.1);
    try std.testing.expectEqual(@as(f32, 11), view.progress_total_time.?.getText().?.font_size);
    for (view.progress_timing.?.children.items) |node| try std.testing.expectEqual(@as(f32, 11), node.getText().?.font_size);
    try std.testing.expectApproxEqAbs(route_bounds.x + route_bounds.w - 30, timing_bounds.x + timing_bounds.w, 0.1);
    const step_time = view.progress_durations[2].?.globalRect();
    const total_time = view.progress_total_time.?.globalRect();
    const step_status = view.progress_states[2].?.globalRect();
    const overall_status = view.progress_status.?.globalRect();
    try std.testing.expectApproxEqAbs(step_time.x + step_time.w, total_time.x + total_time.w, 0.1);
    try std.testing.expectApproxEqAbs(step_status.x + step_status.w, overall_status.x + overall_status.w, 0.1);
    try std.testing.expectEqualStrings("—", view.progress_durations[5].?.getText().?.content);
    for (view.progress_rows, view.progress_names, view.progress_durations, view.progress_states) |row, name, duration, status| {
        const backdrop = row.?.globalRect();
        try std.testing.expect(backdrop.h >= 34);
        for ([_]*ui.Node{ name.?, duration.?, status.? }) |node| {
            const bounds = node.globalRect();
            try std.testing.expect(bounds.x >= backdrop.x + 9.9);
            try std.testing.expect(bounds.x + bounds.w <= backdrop.x + backdrop.w - 9.9);
            try std.testing.expect(bounds.y >= backdrop.y + 7.9);
            try std.testing.expect(bounds.y + bounds.h <= backdrop.y + backdrop.h - 7.9);
        }
    }
    try std.testing.expectEqualStrings("建立独立 SSH 路由 · 2 跳", view.progress_names[0].?.getText().?.content);
    try std.testing.expectEqualStrings("等待", view.progress_states[4].?.getText().?.content);
    try std.testing.expect(std.mem.indexOf(u8, view.progress_route_text.?.getText().?.content, "offline.invalid") != null);
    const video = view.viewport.?.globalRect();
    const card = view.waiting.?.globalRect();
    const body = view.waiting_body.?;
    const actions = view.waiting_actions.?.globalRect();
    try std.testing.expectApproxEqAbs(@as(f32, 390) - @import("../styles.zig").toolbar_height - 16, video.h, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 520), card.w, 0.01);
    try std.testing.expect(card.h <= video.h - 23.9);
    try std.testing.expect(card.y >= video.y + 11.9 and card.y + card.h <= video.y + video.h - 11.9);
    try std.testing.expect(body.state.maxScrollY() > 0);
    try std.testing.expect(actions.y >= card.y and actions.y + actions.h <= card.y + card.h);
    try std.testing.expectApproxEqAbs(@as(f32, 32), view.cancel_node.?.globalRect().h, 0.01);
    _ = view.waiting_viewport.?.behavior.events.on_event_capture.?(.{ .key_down = .{ .key = .end } }, view);
    renderFrames(cx, 3);
    const route = view.progress_route.?.globalRect();
    const body_rect = view.waiting_viewport.?.globalRect();
    // The complete route is a fixed sibling above the header and scroller.
    try std.testing.expect(route.y >= card.y and route.y + route.h < body_rect.y);
    try std.testing.expectEqualDeep(card, view.waiting.?.globalRect());
    for ([_]console.progress.Stage{ .waiting_certificate, .waiting_credentials, .waiting_video_certificate }) |stage| {
        fixture.progress.stage = stage;
        fixture.progress.waiting_for_user = true;
        fixture.progress.revision += 1;
        try renderer.vtable.update(renderer.context, .{ .owner = owner, .revision = 2, .title = "Synthetic", .status = "" });
        renderFrames(cx, 3);
        try std.testing.expectEqualStrings(console.progress.stageLabel(stage), view.waiting_title.?.getText().?.content);
        try std.testing.expect(std.mem.startsWith(u8, view.progress_notice.?.getText().?.content, "等待你的操作"));
        try std.testing.expect(std.mem.indexOf(u8, view.waiting_detail.?.getText().?.content, "连接正在等待你的") != null);
    }
    fixture.progress.stage = .public_script;
    fixture.progress.waiting_for_user = false;
    try renderer.vtable.update(renderer.context, .{ .owner = owner, .revision = 2, .title = "Synthetic", .status = "" });
    findById(view.waiting.?, "bmc.connection_log").?.behavior.events.on_click.?.invoke();
    renderFrames(cx, 8);
    try std.testing.expectEqual(@as(usize, 3), view.log_count);
    findById(view.log_modal.?.dialog, "bmc.connection_log.dismiss").?.behavior.events.on_click.?.invoke();
    renderFrames(cx, 8);
    // Bounded history can be longer than a compact viewport. Opening/closing
    // the native Modal must keep the running attempt and its log intact.
    fixture.progress.revision = 35;
    fixture.progress.event_count = 32;
    for (&fixture.progress.events, 0..) |*event, index| event.* = .{ .sequence = index + 4, .at_ms = index * 100, .stage = .public_script, .kind = .http_response, .resource = .public_script, .http_status = 200 };
    try renderer.vtable.update(renderer.context, .{ .owner = owner, .revision = 2, .title = "Synthetic", .status = "" });
    findById(view.waiting.?, "bmc.connection_log").?.behavior.events.on_click.?.invoke();
    renderFrames(cx, 8);
    try std.testing.expect(view.log_open.?.peek());
    try std.testing.expectEqual(@as(usize, 32), view.log_count);
    try std.testing.expectApproxEqAbs(@as(f32, 32 * 28), view.log_detail.?.globalRect().h, 0.01);
    try std.testing.expect(view.log_scroll.?.state.maxScrollY() > 0);
    try std.testing.expectApproxEqAbs(view.log_scroll.?.state.maxScrollY(), view.log_scroll.?.state.scroll_y, 0.01);
    const modal = view.log_modal.?.dialog.globalRect();
    const header_close = findById(view.log_modal.?.dialog, "bmc.connection_log.close").?.globalRect();
    const dismiss = findById(view.log_modal.?.dialog, "bmc.connection_log.dismiss").?.globalRect();
    try std.testing.expectApproxEqAbs(@as(f32, 760), modal.w, 0.01);
    try std.testing.expect(modal.y >= 16 and modal.y + modal.h <= 464.1);
    try std.testing.expect(header_close.y >= modal.y and header_close.y + header_close.h <= modal.y + modal.h);
    try std.testing.expect(dismiss.y >= modal.y and dismiss.y + dismiss.h <= modal.y + modal.h);
    _ = view.log_viewport.?.behavior.events.on_event_capture.?(.{ .key_down = .{ .key = .end } }, view);
    renderFrames(cx, 3);
    try std.testing.expectApproxEqAbs(view.log_scroll.?.state.maxScrollY(), view.log_scroll.?.state.scroll_y, 0.01);
    const log_scroll = view.log_scroll.?;
    ui.widgets.scroll_area.setScrollY(log_scroll.state, log_scroll.content, 100);
    const evicted_height = view.log_rows[0].?.globalRect().h;
    fixture.progress.revision += 1;
    for (&fixture.progress.events) |*event| {
        event.sequence += 1;
        event.at_ms += 100;
    }
    try renderer.vtable.update(renderer.context, .{ .owner = owner, .revision = 3, .title = "Synthetic", .status = "" });
    renderFrames(cx, 5);
    try std.testing.expectApproxEqAbs(100 - evicted_height, log_scroll.state.scroll_y, 0.6); // same event remains under the reader after one ring eviction
    _ = view.log_viewport.?.behavior.events.on_event_capture.?(.{ .key_down = .{ .key = .end } }, view);
    fixture.progress.revision += 1;
    fixture.progress.events[31].code = .readonly_collection_rejected;
    fixture.progress.events[31].error_code = "LOCAL_READONLY_REJECTION_WITH_A_LONG_STATIC_DIAGNOSTIC";
    try renderer.vtable.update(renderer.context, .{ .owner = owner, .revision = 4, .title = "Synthetic", .status = "" });
    renderFrames(cx, 5);
    try std.testing.expectApproxEqAbs(log_scroll.state.maxScrollY(), log_scroll.state.scroll_y, 0.01);
    const retained_log = try a.dupe(u8, view.log_messages[31].?.getText().?.content);
    defer a.free(retained_log);
    findById(view.log_modal.?.dialog, "bmc.connection_log.dismiss").?.behavior.events.on_click.?.invoke();
    renderFrames(cx, 8);
    try std.testing.expect(!view.log_open.?.peek());
    try std.testing.expectEqual(@as(usize, 0), fixture.cancel_requests);
    try std.testing.expectEqualStrings(retained_log, view.log_messages[31].?.getText().?.content);
    view.cancel_node.?.behavior.events.on_click.?.invoke();
    view.cancel_node.?.behavior.events.on_click.?.invoke();
    try std.testing.expectEqual(@as(usize, 1), fixture.cancel_requests);
    try std.testing.expect(view.cancel_disabled.peek());
    fixture.progress.stage = .cancelled;
    fixture.progress.revision += 1;
    fixture.cleanup = .released;
    fixture.route = .closed;
    fixture.video = .closed;
    try renderer.vtable.update(renderer.context, .{ .owner = owner, .revision = 3, .title = "Synthetic", .status = "" });
    renderFrames(cx, 3);
    try std.testing.expectEqualStrings("连接已取消", view.waiting_title.?.getText().?.content);
    try std.testing.expectEqualStrings("已取消", view.progress_status.?.getText().?.content);
    try std.testing.expectEqual(.none, view.cancel_node.?.style.display);
    try std.testing.expectEqual(.flex, view.retry_node.?.style.display);
    try std.testing.expect(!view.retry_disabled.peek());
    view.retry_node.?.behavior.events.on_click.?.invoke();
    try std.testing.expectEqual(@as(usize, 1), fixture.retry_requests);
    // Production retry mounts a fresh renderer; the local service fixture
    // keeps this instance, so clear its prior cancellation for the new attempt.
    view.cancel_pending = false;
    fixture.progress.stage = .streaming;
    fixture.progress.revision += 1;
    fixture.route = .connected;
    fixture.video = .streaming;
    fixture.cleanup = .not_started;
    try renderer.vtable.update(renderer.context, .{ .owner = owner, .revision = 4, .title = "Synthetic", .status = "" });
    try std.testing.expectEqualStrings("连接成功", view.progress_status.?.getText().?.content);
}

test "BMC view progress remains readable across built-in themes and transparency" {
    const theme = @import("../../../shared/ui/theme/app_theme.zig");
    const colors = @import("../../../shared/ui/theme/theme_states.zig");
    const styles = @import("../styles.zig");
    const previous = theme.currentName();
    const parameters = theme.materialParameters();
    defer {
        theme.select(previous);
        _ = theme.setMaterialParameters(parameters.transparency, parameters.blur);
    }
    for (@import("../../../config/theme_presets.zig").ids) |id| {
        theme.selectTokens(@import("../../../config/theme_registry.zig").builtinTokens(id));
        for ([_]f32{ 0, 1, 50, 100 }) |transparency| {
            _ = theme.setMaterialParameters(transparency, 24);
            const palette = theme.current();
            const surface = styles.progressSurface(theme.widgetTheme(theme.currentName())).background.?;
            try std.testing.expectEqual(palette.overlay.withAlpha(255), surface);
            const route = styles.progressRouteBox(theme.widgetTheme(theme.currentName())).background.?;
            try std.testing.expectEqual(palette.well.withAlpha(255), route);
            const active = theme.patchPaint(styles.progressCurrentFill(), surface);
            for ([_]ui.Color{ surface, route, active }) |background| {
                for ([_]ui.Color{ palette.fg_1, styles.progressSecondary() }) |ink| {
                    if (colors.contrast(ink, background) < 4.5) std.debug.print("KVM progress contrast: {s}, T={d}\n", .{ id, transparency });
                    try std.testing.expect(colors.contrast(ink, background) >= 4.5);
                }
            }
            for ([_]ui.Color{ palette.warn_ink, palette.danger_ink, palette.ok_ink }) |ink| {
                try std.testing.expect(colors.contrast(ink, surface) >= 4.5);
                try std.testing.expect(colors.contrast(ink, route) >= 4.5);
            }
            try std.testing.expect(colors.contrast(palette.accent_ink, active) >= 4.5);
            const button = theme.widgetTheme(theme.currentName()).tokens.color;
            try std.testing.expect(colors.contrast(button.button_secondary_fg, theme.patchPaint(button.button_secondary_bg, surface)) >= 4.5);
        }
    }
}

test "BMC view progress slots remain fixed across phase timing legacy and long diagnostics" {
    const theme = @import("../../../shared/ui/theme/app_theme.zig");
    const previous_material = theme.materialParameters();
    defer _ = theme.setMaterialParameters(previous_material.transparency, previous_material.blur);
    for ([_]struct { width: f32, height: f32 }{ .{ .width = 1440, .height = 900 }, .{ .width = 860, .height = 480 } }) |size| {
        _ = theme.setMaterialParameters(0, 0);
        var fixture: Fixture = .{ .route = .connecting, .video = .authenticating, .route_summary = "本机 → a-long-synthetic-hostname.invalid:22 → another-long-synthetic-hostname.invalid:22 → third-long-synthetic-hostname.invalid:22 → offline.invalid:443" };
        const cx = try ui.Cx.init(a, std.testing.io);
        defer cx.deinit();
        cx.setTheme(theme.widgetTheme(theme.currentName()));
        cx.setViewport(size.width, size.height);
        const scope = try ui.Scope.init(a, null, cx.owner);
        defer scope.dispose();
        cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
        const renderer = try views.mount(null, .{ .cx = cx, .scope = scope, .slot = cx.root.?, .owner = owner, .connection = .{ .protocol_id = "bmc_ikvm", .name = "Synthetic", .payload = "{}" }, .service_access = access.SessionServiceAccess{ .context = &fixture, .owner = owner, .lookup_fn = Fixture.lookup } });
        defer renderer.vtable.unmount(renderer.context);
        const view: *views.View = @ptrCast(@alignCast(renderer.context));
        renderFrames(cx, 5);
        // The local card stays opaque over the black waiting viewport, and
        // polling must not replace either surface with a translucent material.
        const surface = findById(view.waiting.?, "bmc.progress.surface").?;
        try std.testing.expectEqual(ui.Color.BLACK, view.viewport.?.getBackground());
        try std.testing.expectEqual(theme.current().overlay.withAlpha(255), surface.getBackground());
        try std.testing.expectEqual(@as(f32, 0), view.waiting.?.style.border.width);
        try std.testing.expectEqual(@as(f32, 0), surface.style.border.width);
        try std.testing.expect(surface.style.glass_params() == null);
        try std.testing.expectEqualDeep(view.waiting.?.globalRect(), surface.globalRect());
        const nodes = [_]*ui.Node{ view.waiting.?, view.waiting_header.?, view.waiting_title.?, view.progress_timing.?, view.progress_total_time.?, view.waiting_viewport.?, view.progress_route.?, view.waiting_actions.?, findById(view.waiting.?, "bmc.connection_log").? };
        var baseline: [nodes.len]ui.ComputedRect = undefined;
        for (nodes, &baseline) |node, *rect| rect.* = node.globalRect();
        const stages = [_]console.progress.Stage{ .public_script, .public_script, .public_script, .public_script, .waiting_certificate, .waiting_credentials, .redfish_discovery, .failed };
        const times = [_]u64{ 9900, 10000, 99900, 100000, 100000, 100000, 100000, 100000 };
        for (stages, times, 0..) |stage, ms, index| {
            fixture.progress = .{ .revision = index + 1, .stage = stage, .elapsed_ms = ms, .stage_elapsed_ms = ms, .waiting_for_user = stage == .waiting_certificate or stage == .waiting_credentials };
            if (stage == .failed) {
                fixture.progress.failure_stage = .public_script;
                fixture.progress.failure_code = "UnsupportedProfilePublicEvidenceUnavailable";
            }
            try renderer.vtable.update(renderer.context, .{ .owner = owner, .revision = index + 2, .title = "Synthetic", .status = "" });
            try std.testing.expectEqualStrings(if (stage == .failed) "连接失败" else "连接中", view.progress_status.?.getText().?.content);
            for (0..3) |frame| {
                renderFrames(cx, 1);
                for (nodes, baseline) |node, expected| {
                    const actual = node.globalRect();
                    inline for (.{ "x", "y", "w", "h" }) |field| try std.testing.expectApproxEqAbs(@field(expected, field), @field(actual, field), 0.01);
                }
                // The view asks for the offset at the layout point of the first frame; the native
                // ScrollArea applies its controlled offset in the next one.
                if (frame > 0) if (vm.progressGroup(stage)) |group| {
                    const row = view.progress_rows[@intCast(@backingInt(group))].?.globalRect();
                    const body = view.waiting_viewport.?.globalRect();
                    try std.testing.expect(row.y >= body.y - 0.6 and row.y + row.h <= body.y + body.h + 0.6);
                };
                try std.testing.expectEqual(ui.Color.BLACK, view.viewport.?.getBackground());
                try std.testing.expectEqual(theme.current().overlay.withAlpha(255), surface.getBackground());
                try std.testing.expectEqualDeep(view.waiting.?.globalRect(), surface.globalRect());
                if (stage == .public_script) {
                    try std.testing.expect(view.progress_rows[2].?.getBackground().a > 0);
                    try std.testing.expectEqual(@as(u8, 0), view.progress_rows[1].?.getBackground().a);
                } else if (stage == .waiting_certificate) {
                    try std.testing.expect(view.progress_rows[1].?.getBackground().a > 0);
                    try std.testing.expectEqual(@as(u8, 0), view.progress_rows[2].?.getBackground().a);
                }
            }
        }
        try std.testing.expectApproxEqAbs(@as(f32, 76), view.progress_durations[2].?.globalRect().w, 0.01);
        try std.testing.expect(view.progress_durations[2].?.getText().?.use_monospace_font);
        const title_ink = view.waiting_title.?.getText().?.color;
        _ = theme.setMaterialParameters(100, 40);
        // Publish a new token identity, as the application theme publication
        // does; Cx deliberately ignores the same pointer a second time.
        const material_tokens = theme.widgetTheme(theme.currentName()).*;
        cx.setTheme(&material_tokens);
        renderFrames(cx, 4);
        try std.testing.expectEqual(theme.current().overlay.withAlpha(255), surface.getBackground());
        try std.testing.expect(surface.style.glass_params() == null);
        try std.testing.expectEqualDeep(title_ink, view.waiting_title.?.getText().?.color);
        for (nodes, baseline) |node, expected| {
            const actual = node.globalRect();
            inline for (.{ "x", "y", "w", "h" }) |field| try std.testing.expectApproxEqAbs(@field(expected, field), @field(actual, field), 0.01);
        }
    }
}

test "BMC view connection log renders independent timestamp message and duration columns" {
    var fixture: Fixture = .{ .route = .connecting, .video = .authenticating, .progress = .{ .revision = 1, .stage = .public_script, .event_count = 1 } };
    fixture.progress.events[0] = .{ .sequence = 1, .at_ms = 987654, .at_unix_ms = 1_799_000_000_123, .duration_ms = 1534, .stage = .public_script, .kind = .failure, .error_code = "HttpTimeout", .context = .{ .channel = .management, .method = .get, .path = .public_script, .phase = .response_body, .http_status = 200 } };
    const cx = try ui.Cx.init(a, std.testing.io);
    defer cx.deinit();
    cx.setViewport(860, 480);
    const scope = try ui.Scope.init(a, null, cx.owner);
    defer scope.dispose();
    cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    const renderer = try views.mount(null, .{ .cx = cx, .scope = scope, .slot = cx.root.?, .owner = owner, .connection = .{ .protocol_id = "bmc_ikvm", .name = "Synthetic", .payload = "{}" }, .service_access = access.SessionServiceAccess{ .context = &fixture, .owner = owner, .lookup_fn = Fixture.lookup } });
    defer renderer.vtable.unmount(renderer.context);
    const view: *views.View = @ptrCast(@alignCast(renderer.context));
    findById(view.waiting.?, "bmc.connection_log").?.behavior.events.on_click.?.invoke();
    renderFrames(cx, 8);
    const timestamp = view.log_timestamps[0].?;
    const message = view.log_messages[0].?;
    const duration = view.log_durations[0].?;
    try std.testing.expect(std.mem.endsWith(u8, timestamp.getText().?.content, ".123"));
    try std.testing.expect(!std.mem.startsWith(u8, timestamp.getText().?.content, "+"));
    try std.testing.expectEqualStrings("1.5 s", duration.getText().?.content);
    try std.testing.expect(std.mem.indexOf(u8, message.getText().?.content, "GET /js/app.0bc71eb0.js") != null);
    try std.testing.expect(std.mem.indexOf(u8, message.getText().?.content, "HttpTimeout") != null);
    try std.testing.expectApproxEqAbs(@as(f32, 86), timestamp.globalRect().w, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 76), duration.globalRect().w, 0.01);
    try std.testing.expect(message.globalRect().x >= timestamp.globalRect().x + timestamp.globalRect().w + 11.9);
    try std.testing.expect(duration.globalRect().x >= message.globalRect().x + message.globalRect().w + 11.9);
    fixture.progress.events[0].at_unix_ms = null;
    fixture.progress.revision += 1;
    try renderer.vtable.update(renderer.context, .{ .owner = owner, .revision = 2, .title = "Synthetic", .status = "" });
    renderFrames(cx, 3);
    try std.testing.expectEqualStrings("时间未知", timestamp.getText().?.content);
}

test "BMC view progress follows active stage changes but preserves manual scrolling during timer updates" {
    var fixture: Fixture = .{ .route = .connecting, .video = .authenticating };
    const cx = try ui.Cx.init(a, std.testing.io);
    defer cx.deinit();
    cx.setViewport(860, 480);
    const scope = try ui.Scope.init(a, null, cx.owner);
    defer scope.dispose();
    cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    const renderer = try views.mount(null, .{ .cx = cx, .scope = scope, .slot = cx.root.?, .owner = owner, .connection = .{ .protocol_id = "bmc_ikvm", .name = "Synthetic", .payload = "{}" }, .service_access = access.SessionServiceAccess{ .context = &fixture, .owner = owner, .lookup_fn = Fixture.lookup } });
    defer renderer.vtable.unmount(renderer.context);
    const view: *views.View = @ptrCast(@alignCast(renderer.context));
    renderFrames(cx, 5);
    const route = view.progress_route.?.globalRect();
    const actions = view.waiting_actions.?.globalRect();
    const stages = [_]console.progress.Stage{ .route, .tls_handshake, .public_identity, .public_script, .waiting_credentials, .web_login, .firmware_confirmation, .redfish_discovery, .oem_session, .video_tls_handshake, .waiting_video_certificate, .websocket_upgrade, .rfb_negotiation, .awaiting_first_frame };
    for (stages, 0..) |stage, index| {
        fixture.progress = .{ .revision = index + 1, .stage = stage, .elapsed_ms = index * 1000, .waiting_for_user = stage == .waiting_credentials or stage == .waiting_video_certificate };
        try renderer.vtable.update(renderer.context, .{ .owner = owner, .revision = index + 1, .title = "Synthetic", .status = "" });
        renderFrames(cx, 3);
        const body = view.waiting_viewport.?.globalRect();
        const row = view.progress_rows[@intCast(@backingInt(vm.progressGroup(stage).?))].?.globalRect();
        try std.testing.expect(row.y >= body.y - 0.6 and row.y + row.h <= body.y + body.h + 0.6);
        try std.testing.expectEqualDeep(route, view.progress_route.?.globalRect());
        try std.testing.expectEqualDeep(actions, view.waiting_actions.?.globalRect());
    }
    const body = view.waiting_body.?;
    try std.testing.expect(body.state.scroll_y > 0);
    // A user can read an earlier step while the current phase keeps waiting.
    ui.widgets.scroll_area.setScrollY(body.state, body.content, 0);
    fixture.progress.revision += 1;
    fixture.progress.elapsed_ms += 1000;
    fixture.progress.stage_elapsed_ms += 1000;
    try renderer.vtable.update(renderer.context, .{ .owner = owner, .revision = 100, .title = "Synthetic", .status = "" });
    renderFrames(cx, 3);
    try std.testing.expectEqual(@as(f32, 0), body.state.scroll_y);
    // Another real phase within the same video group brings its row back.
    fixture.progress.stage = .rfb_negotiation;
    fixture.progress.revision += 1;
    try renderer.vtable.update(renderer.context, .{ .owner = owner, .revision = 101, .title = "Synthetic", .status = "" });
    renderFrames(cx, 3);
    const row = view.progress_rows[5].?.globalRect();
    const rect = view.waiting_viewport.?.globalRect();
    try std.testing.expect(row.y >= rect.y - 0.6 and row.y + row.h <= rect.y + rect.h + 0.6);
}

test "BMC view failure retains Chinese reason and static code after cleanup and success keeps log entry" {
    var fixture: Fixture = .{ .route = .failed, .video = .failed, .cleanup = .released, .progress = .{ .revision = 2, .stage = .failed, .failure_stage = .public_script, .failure_code = "UnsupportedProfilePublicEvidenceUnavailable", .event_count = 2 } };
    fixture.progress.events[0] = .{ .sequence = 1, .stage = .public_script };
    fixture.progress.events[1] = .{ .sequence = 2, .at_ms = 2200, .stage = .public_script, .kind = .failure, .error_code = "UnsupportedProfilePublicEvidenceUnavailable" };
    const cx = try ui.Cx.init(a, std.testing.io);
    defer cx.deinit();
    cx.setViewport(860, 480);
    const scope = try ui.Scope.init(a, null, cx.owner);
    defer scope.dispose();
    cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    const renderer = try views.mount(null, .{ .cx = cx, .scope = scope, .slot = cx.root.?, .owner = owner, .connection = .{ .protocol_id = "bmc_ikvm", .name = "Synthetic", .payload = "{}" }, .service_access = access.SessionServiceAccess{ .context = &fixture, .owner = owner, .lookup_fn = Fixture.lookup } });
    defer renderer.vtable.unmount(renderer.context);
    const view: *views.View = @ptrCast(@alignCast(renderer.context));
    renderFrames(cx, 3);
    try std.testing.expectEqualStrings("连接失败", view.waiting_title.?.getText().?.content);
    const detail = view.progress_details[2].?.getText().?.content;
    try std.testing.expectEqual(.flex, view.progress_details[2].?.style.display);
    try std.testing.expect(std.mem.indexOf(u8, detail, "无法取得可验证的公开设备信息") != null);
    try std.testing.expect(std.mem.indexOf(u8, detail, "UnsupportedProfilePublicEvidenceUnavailable") != null);
    try std.testing.expectEqualStrings("失败", view.progress_states[2].?.getText().?.content);
    findById(view.waiting.?, "bmc.progress.step.identity").?.behavior.events.on_click.?.invoke();
    renderFrames(cx, 3);
    try std.testing.expectEqual(.none, view.progress_details[2].?.style.display);
    fixture.progress.stage = .cleanup;
    fixture.progress.revision += 1;
    try renderer.vtable.update(renderer.context, .{ .owner = owner, .revision = 3, .title = "Synthetic", .status = "" });
    renderFrames(cx, 3);
    try std.testing.expectEqual(.none, view.progress_details[2].?.style.display);
    findById(view.waiting.?, "bmc.progress.step.identity").?.behavior.events.on_click.?.invoke();
    renderFrames(cx, 3);
    try std.testing.expectEqual(.flex, view.progress_details[2].?.style.display);
    findById(view.waiting.?, "bmc.connection_log").?.behavior.events.on_click.?.invoke();
    renderFrames(cx, 8);
    try std.testing.expect(std.mem.indexOf(u8, view.log_messages[1].?.getText().?.content, "UnsupportedProfilePublicEvidenceUnavailable") != null);
    findById(view.log_modal.?.dialog, "bmc.connection_log.close").?.behavior.events.on_click.?.invoke();
    renderFrames(cx, 8);
    try std.testing.expect(!view.log_open.?.peek());
    try std.testing.expectEqual(@as(usize, 0), fixture.cancel_requests);
    // This menu entry is mounted in every state, including a live connection.
    try std.testing.expect(findById(view.menus[2].?.content, "bmc.display.connection_log") != null);
}

test "BMC view same owner remount resumes real ordinary and explicit input sequence" {
    var service = remote.Service.init(owner);
    defer service.close();
    try service.setConnected(true, 1);
    try service.setControl(true, 1);
    service.setFocus(true);
    try std.testing.expectEqual(remote.SubmitResult{ .accepted = 1000 }, service.submit(service.binding(), service.command(1000, .{ .key = .{ .keysym = 'a', .down = false } })));
    var fixture: Fixture = .{ .real_input = &service };
    const cx = try ui.Cx.init(a, std.testing.io);
    defer cx.deinit();
    cx.setViewport(860, 480);
    const window_root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    cx.root = window_root;
    var sink = frames.Sink.init(owner, .{ .context = &fixture, .create = Fixture.create, .update = Fixture.upload, .release = Fixture.release });
    defer sink.close() catch unreachable;
    try sink.submit(try frames.Frame.copy(a, owner, 1, 2, 2, &.{ 255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 255 }));
    _ = try sink.drain();
    for (0..2) |iteration| {
        const scope = try ui.Scope.init(a, null, cx.owner);
        const slot = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
        try window_root.appendChild(a, slot);
        const renderer = try views.mount(null, .{ .cx = cx, .scope = scope, .slot = slot, .owner = owner, .connection = .{ .protocol_id = "bmc_ikvm", .name = "Synthetic", .payload = "{}" }, .frame_sink = &sink, .service_access = access.SessionServiceAccess{ .context = &fixture, .owner = owner, .lookup_fn = Fixture.lookup } });
        const view: *views.View = @ptrCast(@alignCast(renderer.context));
        for (0..3) |_| {
            cx.frame_count += 1;
            cx.frame_time_ms += 34;
            _ = cx.render();
        }
        const rect = view.viewport.?.globalRect();
        _ = view.viewport.?.behavior.events.on_event_capture.?(.{ .mouse_down = .{ .x = rect.x + rect.w / 2, .y = rect.y + rect.h / 2 } }, view);
        try std.testing.expect(view.captured);
        try std.testing.expectEqual(@as(u64, 1001) + iteration * 2, (try service.snapshot(service.binding())).last_input_sequence);
        const chord = findById(view.menus[1].?.content, "bmc.keys.escape").?;
        chord.behavior.events.on_click.?.invoke();
        const after_chord = try service.snapshot(service.binding());
        try std.testing.expectEqual(@as(u64, 1002) + iteration * 2, after_chord.last_input_sequence);
        try std.testing.expect(!after_chord.focused);
        renderer.vtable.unmount(renderer.context);
        scope.dispose();
        cx.detachChild(window_root, slot);
        cx.freeNode(slot);
    }
}

fn findById(node: *ui.Node, test_id: []const u8) ?*ui.Node {
    if (node.meta.ownership.meta.test_id) |id| if (std.mem.eql(u8, id, test_id)) return node;
    for (node.children.items) |child| if (findById(child, test_id)) |found| return found;
    return null;
}
/// The first text node in a rendered subtree (reads the tree as drawn; changes nothing).
fn findTextIn(node: *ui.Node) ?*ui.Node {
    if (node.getText() != null) return node;
    for (node.children.items) |child| if (findTextIn(child)) |found| return found;
    return null;
}
fn renderFrames(cx: *ui.Cx, count: usize) void {
    for (0..count) |_| {
        cx.frame_count += 1;
        cx.frame_time_ms += 34;
        _ = cx.render();
    }
}

// Exercise the same hit testing, focus and event dispatch used by the window,
// followed by the real RFB sender. Only the GPU backend is a local fixture.
const InputViewHarness = struct {
    cx: *ui.Cx,
    scope: *ui.Scope,
    fixture: *Fixture,
    sink: *frames.Sink,
    budget: *frames.Budget,
    renderer: @import("../../../host/plugin_ui_contract.zig").RendererInstance,
    view: *views.View,

    fn init(service: *remote.Service) !InputViewHarness {
        const fixture = try a.create(Fixture);
        errdefer a.destroy(fixture);
        fixture.* = .{ .real_input = service, .width = 1920, .height = 1200 };
        const cx = try ui.Cx.init(a, std.testing.io);
        errdefer cx.deinit();
        cx.setViewport(860, 480);
        const scope = try ui.Scope.init(a, null, cx.owner);
        errdefer scope.dispose();
        cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
        const sink = try a.create(frames.Sink);
        errdefer a.destroy(sink);
        const budget = try a.create(frames.Budget);
        errdefer a.destroy(budget);
        budget.* = frames.Budget.init(32 * 1024 * 1024);
        errdefer budget.deinit() catch unreachable;
        sink.* = frames.Sink.initWithBudget(owner, .{ .context = fixture, .create = Fixture.create, .update = Fixture.upload, .release = Fixture.release }, budget, .kvm);
        errdefer sink.close() catch unreachable;
        const pixels = try a.alloc(u8, 1920 * 1200 * 4);
        defer a.free(pixels);
        @memset(pixels, 0);
        try sink.submit(try frames.Frame.copyWithBudget(a, budget, owner, 1, 1920, 1200, pixels));
        _ = try sink.drain();
        const renderer = try views.mount(null, .{ .cx = cx, .scope = scope, .slot = cx.root.?, .owner = owner, .connection = .{ .protocol_id = "bmc_ikvm", .name = "Synthetic", .payload = "{}" }, .frame_sink = sink, .service_access = access.SessionServiceAccess{ .context = fixture, .owner = owner, .lookup_fn = Fixture.lookup } });
        renderFrames(cx, 4);
        return .{ .cx = cx, .scope = scope, .fixture = fixture, .sink = sink, .budget = budget, .renderer = renderer, .view = @ptrCast(@alignCast(renderer.context)) };
    }
    fn deinit(self: *InputViewHarness) void {
        self.renderer.vtable.unmount(self.renderer.context);
        self.scope.dispose();
        self.sink.close() catch unreachable;
        self.budget.deinit() catch unreachable;
        self.cx.deinit();
        a.destroy(self.sink);
        a.destroy(self.budget);
        a.destroy(self.fixture);
    }
    fn click(self: *InputViewHarness, node: *ui.Node) void {
        const r = node.globalRect();
        self.cx.handleMouseDown(r.x + r.w / 2, r.y + r.h / 2, .{});
        self.cx.handleMouseUp(r.x + r.w / 2, r.y + r.h / 2);
    }
};

const InputWire = struct {
    data: [8192]u8 = undefined,
    len: usize = 0,
    fn write(raw: *anyopaque, value: []const u8) !usize {
        const self: *InputWire = @ptrCast(@alignCast(raw));
        if (value.len > self.data.len - self.len) return error.TestOutputFull;
        @memcpy(self.data[self.len..][0..value.len], value);
        self.len += value.len;
        return value.len;
    }
    fn pump(self: *InputWire, service: *remote.Service) !void {
        const snapshot = try service.snapshot(service.binding());
        _ = try service.pump(.{ .context = self, .generation = snapshot.transport_generation, .write = write, .abort = abort });
    }
    fn abort(_: *anyopaque) void {}
    fn expectKey(self: *const InputWire, offset: usize, keysym: u32, down: bool) !void {
        try std.testing.expectEqualSlices(u8, &.{ 4, @intFromBool(down), 0, 0 }, self.data[offset..][0..4]);
        try std.testing.expectEqual(keysym, std.mem.readInt(u32, self.data[offset + 4 ..][0..4], .big));
    }
    fn expectPointer(self: *const InputWire, offset: usize, x: u16, y: u16, buttons: u8) !void {
        try std.testing.expectEqual(@as(u8, 5), self.data[offset]);
        try std.testing.expectEqual(buttons, self.data[offset + 1]);
        try std.testing.expectEqual(x, std.mem.readInt(u16, self.data[offset + 2 ..][0..2], .big));
        try std.testing.expectEqual(y, std.mem.readInt(u16, self.data[offset + 4 ..][0..2], .big));
    }
};

// Pencil TcJSa: 40pt toolbar (padding [0,8,0,12]) flush above the video, no gap.
test "BMC view workspace aligns floating toolbar and video surface and aligns host identity across resize" {
    var service = remote.Service.init(owner);
    try service.setConnected(true, 1);
    try service.setControl(true, 2);
    var harness = try InputViewHarness.init(&service);
    defer harness.deinit();
    const view = harness.view;
    for ([_][2]f32{ .{ 860, 480 }, .{ 1440, 900 } }) |size| {
        harness.cx.setViewport(size[0], size[1]);
        renderFrames(harness.cx, 4);
        const card_node = findById(view.root.?, "bmc.video_card").?;
        const card = card_node.globalRect();
        const viewport = view.viewport.?.globalRect();
        const image = view.image_node.?.globalRect();
        try std.testing.expectApproxEqAbs(@as(f32, 0), card.x, 0.01);
        try std.testing.expectApproxEqAbs(@as(f32, 40), card.y, 0.01);
        try std.testing.expectApproxEqAbs(card.x + 8, viewport.x, 0.01);
        try std.testing.expectApproxEqAbs(card.y + 8, viewport.y, 0.01);
        try std.testing.expectApproxEqAbs(size[0] - 16, viewport.w, 0.01);
        try std.testing.expectApproxEqAbs(size[1] - 56, viewport.h, 0.01);
        try std.testing.expectEqual(ui.Padding.all(8), card_node.style.padding);
        try std.testing.expectEqual(ui.Padding.ZERO, findById(view.root.?, "bmc.video_workspace").?.style.padding);
        try std.testing.expectEqual(@as(f32, 0), view.root.?.style.border.radius);
        try std.testing.expectEqual(@as(f32, 0), view.viewport.?.style.border.radius);
        try std.testing.expectEqual(@as(f32, 0), view.image_node.?.style.border.radius);
        const icon = findById(view.root.?, "bmc.title.icon").?.globalRect();
        try std.testing.expectApproxEqAbs(card.x + 12, icon.x, 0.01);
        const title_node = findById(view.root.?, "bmc.title").?;
        const title = title_node.globalRect();
        const status = view.disconnect_node.?.globalRect();
        try std.testing.expect(title_node.isDisplayedInTree());
        try std.testing.expect(title.w > 0 and icon.x + icon.w <= title.x);
        try std.testing.expect(title.x + title.w <= status.x + 0.01);
        const last_tool = view.tool_nodes[4].?.globalRect();
        // Native Button at its own height, centred in the 40 point toolbar.
        try std.testing.expectApproxEqAbs((40 - last_tool.h) / 2, last_tool.y, 0.01);
        try std.testing.expectApproxEqAbs((40 - last_tool.h) / 2, card.y - last_tool.y - last_tool.h, 0.01);
        try std.testing.expectApproxEqAbs(card.x + card.w - 8, last_tool.x + last_tool.w, 0.01);
        try std.testing.expectApproxEqAbs(@as(f32, 15), icon.w, 0.01);
        try std.testing.expectApproxEqAbs(@as(f32, 20), icon.y + icon.h / 2, 0.01);
        try std.testing.expectEqual(ui.Color.TRANSPARENT, view.root.?.getBackground());
        try std.testing.expectApproxEqAbs(@as(f32, 1.6), image.w / image.h, 0.0001);
        try std.testing.expect(image.x >= card.x and image.y >= card.y);
        try std.testing.expect(image.x + image.w <= card.x + card.w + 0.01);
        try std.testing.expect(image.y + image.h <= card.y + card.h + 0.01);
        // Header and letterbox stay local; the square frame preserves all
        // four remote corners and maps each input coordinate exactly once.
        for ([_][2]f32{ .{ 1, 45 }, .{ card.x + 2, card.y + 2 }, .{ viewport.x + 1, viewport.y + viewport.h / 2 } }) |point| {
            harness.cx.handleMouseDown(point[0], point[1], .{});
            harness.cx.handleMouseUp(point[0], point[1]);
            try std.testing.expect(!view.captured);
            try std.testing.expectEqual(@as(usize, 0), (try service.snapshot(service.binding())).queued);
        }
        var wire: InputWire = .{};
        const scale = image.w / 1920;
        for ([_][2]u16{ .{ 0, 0 }, .{ 1919, 0 }, .{ 0, 1199 }, .{ 1919, 1199 }, .{ 960, 600 } }) |point| {
            const x = image.x + (@as(f32, @floatFromInt(point[0])) + 0.25) * scale;
            const y = image.y + (@as(f32, @floatFromInt(point[1])) + 0.25) * scale;
            const offset = wire.len;
            harness.cx.handleMouseDown(x, y, .{});
            harness.cx.handleMouseUp(x, y);
            try wire.pump(&service);
            try std.testing.expect(view.captured);
            try wire.expectPointer(offset, point[0], point[1], 1);
            try wire.expectPointer(offset + 6, point[0], point[1], 0);
        }
        harness.cx.handleKeyDown(.escape, .{ .ctrl = true, .alt = true });
        try wire.pump(&service);
        try std.testing.expect(!view.captured);
    }
}

test "BMC view compact toolbar keeps narrow split controls reachable and opens management from more" {
    var service = remote.Service.init(owner);
    defer service.close();
    try service.setConnected(true, 1);
    try service.setControl(true, 2);
    var harness = try InputViewHarness.init(&service);
    defer harness.deinit();
    const view = harness.view;
    // Keep the window wide: only the session's allocated split changes.
    harness.cx.setViewport(1440, 900);
    // The toolbar folds by need: zenit's native Buttons have their own sizes, so the view folds
    // (labels -> icons -> the “更多” menu) exactly when the laid-out controls would not fit.
    const styles = @import("../styles.zig");
    var seen = [_]bool{ false, false, false };
    for ([_]f32{ 900, 520, 480, 336, 280, 264, 240, 228, 200, 170, 900, 336 }) |width| {
        harness.cx.root.?.setStyleInline(a, .{ .width = .{ .px = width } });
        renderFrames(harness.cx, 12);
        const compact = view.last_compact.?;
        const overflow = view.last_overflow;
        seen[if (overflow) 2 else if (compact) 1 else 0] = true;
        try std.testing.expectEqual(width < styles.toolbar_labelled_reserve + view.tools_labelled_width.?, compact);
        if (compact) try std.testing.expectEqual(width < styles.toolbar_icon_reserve + view.tools_icon_width.?, overflow) else try std.testing.expect(!overflow);
        try std.testing.expectEqual(compact, view.tool_icon_only.peek());
        const bar = view.toolbar.?.globalRect();
        try std.testing.expectApproxEqAbs(width, bar.w, 0.01);
        try std.testing.expectApproxEqAbs(styles.toolbar_height, bar.h, 0.01);
        var last_right: f32 = bar.x;
        for (view.tool_nodes, 0..) |maybe, index| {
            const node = maybe.?;
            try std.testing.expectEqual(!overflow or index < 3, node.isDisplayedInTree());
            if (node.isDisplayedInTree()) {
                const rect = node.globalRect();
                try std.testing.expect(rect.w > 0 and rect.x >= last_right - 0.01 and rect.x + rect.w <= bar.x + bar.w + 0.01);
                last_right = rect.x + rect.w;
            }
        }
        try std.testing.expectEqual(overflow, view.more_node.?.isDisplayedInTree());
        const connection = view.disconnect_node.?.globalRect();
        try std.testing.expect(connection.w > 0 and connection.x >= bar.x and connection.x + connection.w <= view.tool_nodes[0].?.globalRect().x + 0.01);
        const title = view.connection_title.?.globalRect();
        const icon = view.connection_icon.?.globalRect();
        try std.testing.expect(view.connection_title.?.isDisplayedInTree());
        // The identity (icon + title) gives way first: the title shortens to nothing, and below
        // what zenit's own controls need the identity box clips — nothing of it paints under
        // the buttons.
        const identity_box = view.connection_identity.?;
        const identity_rect = identity_box.globalRect();
        try std.testing.expect(identity_box.style.overflow_hidden);
        try std.testing.expect(identity_rect.x + identity_rect.w <= connection.x + 0.01);
        // Icon and title are laid out at their place inside the box; once the box is narrower
        // than the icon (or the icon and the gap before the title) they lie past its clipped edge.
        if (identity_rect.w >= styles.connection_icon_size) try std.testing.expect(icon.x + icon.w <= connection.x + 0.01);
        if (identity_rect.w >= styles.connection_icon_size + styles.connectionIdentity(harness.cx.tokens).gap.?) try std.testing.expect(title.x + title.w <= connection.x + 0.01);
        try std.testing.expectEqual(compact, view.connection_label.peek().len == 0);
        harness.cx.handleMouseMove(connection.x + connection.w / 2, connection.y + connection.h / 2);
        renderFrames(harness.cx, 4);
        try std.testing.expectEqual(ui.icons.unplug.icon_id, view.connection_symbol.peek().?.icon_id);
        harness.cx.handleMouseMove(0, 0);
        renderFrames(harness.cx, 4);
        try std.testing.expectEqual(ui.icons.circle_check.icon_id, view.connection_symbol.peek().?.icon_id);
        if (!overflow) {
            for (3..5) |index| {
                harness.click(view.tool_nodes[index].?);
                renderFrames(harness.cx, 8);
                try std.testing.expect(view.open[index].peek());
                const menu = view.menus[index].?.chrome.globalRect();
                try std.testing.expect(menu.x >= 0 and menu.x + menu.w <= harness.cx.viewport.width);
                harness.cx.handleKeyDown(.escape, .{});
                renderFrames(harness.cx, 8);
                try std.testing.expect(!view.open[index].peek());
            }
            continue;
        }
        const video_before = view.viewport.?.globalRect();
        harness.click(view.more_node.?);
        renderFrames(harness.cx, 8);
        try std.testing.expect(view.more_open.?.peek());
        // menus 包：“更多”是原生 `W.Menu`（面板 `bmc.more.popover`），焦点进入菜单（原生）。
        const popup = findById(harness.cx.root.?, "bmc.more.popover").?.globalRect();
        try std.testing.expect(popup.x >= bar.x and popup.x + popup.w <= bar.x + bar.w + 0.01);
        // Native Menu: below its trigger (the “更多” button) at zenit's default offset.
        const trigger = view.more_node.?.globalRect();
        try std.testing.expect(popup.y >= trigger.y + trigger.h);
        try std.testing.expectEqual(video_before, view.viewport.?.globalRect());
        for ([_][]const u8{ "bmc.more.power", "bmc.more.boot" }, 3..) |id, index| {
            if (!view.more_open.?.peek()) {
                harness.click(view.more_node.?);
                renderFrames(harness.cx, 8);
            }
            harness.click(findById(harness.cx.root.?, id).?);
            renderFrames(harness.cx, 8);
            try std.testing.expect(!view.more_open.?.peek());
            try std.testing.expect(view.open[index].peek());
            const menu = view.menus[index].?.chrome.globalRect();
            try std.testing.expect(menu.x >= 0 and menu.x + menu.w <= harness.cx.viewport.width);
            harness.cx.handleKeyDown(.escape, .{});
            renderFrames(harness.cx, 8);
            try std.testing.expect(!view.open[index].peek());
            try std.testing.expect(harness.cx.focus_manager.getFocused() == view.more_node.?);
        }
        for (0..2) |_| {
            harness.click(view.more_node.?);
            renderFrames(harness.cx, 8);
            harness.cx.handleKeyDown(.escape, .{});
            renderFrames(harness.cx, 8);
            try std.testing.expect(!view.more_open.?.peek());
            try std.testing.expect(harness.cx.focus_manager.getFocused() == view.more_node.?);
        }
        harness.click(view.more_node.?);
        renderFrames(harness.cx, 8);
        harness.cx.root.?.setStyleInline(a, .{ .width = .{ .px = 520 } });
        renderFrames(harness.cx, 8);
        try std.testing.expect(!view.more_open.?.peek());
        try std.testing.expect(!view.more_node.?.isDisplayedInTree());
    }
    // The sweep reached every fold level.
    try std.testing.expectEqual([_]bool{ true, true, true }, seen);
    try std.testing.expectEqual(@as(usize, 0), (try service.snapshot(service.binding())).queued);
}

test "BMC view final coalesced mouse move schedules its own deadline and flushes without another event" {
    var service = remote.Service.init(owner);
    try service.setConnected(true, 1);
    try service.setControl(true, 2);
    var harness = try InputViewHarness.init(&service);
    defer harness.deinit();
    const view = harness.view;
    harness.click(view.image_node.?);
    var wire: InputWire = .{};
    try wire.pump(&service);
    try std.testing.expect(view.captured);
    renderFrames(harness.cx, 4);
    const image = view.image_node.?.globalRect();
    view.last_pointer_ms = ui.frame.estimateTimeMs();
    harness.cx.next_redraw_scheduled_at = null;
    harness.cx.next_redraw_delay_ns = null;
    _ = view.viewport.?.behavior.events.on_event_capture.?(.{ .mouse_move = .{ .x = image.x + image.w * (1440.25 / 1920.0), .y = image.y + image.h * (900.25 / 1200.0) } }, view);
    try std.testing.expect(view.pending_pointer != null);
    const deadline = harness.cx.next_redraw_delay_ns orelse return error.PointerDeadlineMissing;
    try std.testing.expect(deadline > 0 and deadline <= 16_666_667);
    view.last_pointer_ms -= 17;
    renderFrames(harness.cx, 1);
    try std.testing.expect(view.pending_pointer == null);
    const offset = wire.len;
    try wire.pump(&service);
    try wire.expectPointer(offset, 1440, 900, 0);
}

test "BMC view Cx routes physical keys Esc pointer and wheel to real RFB without duplicate text" {
    var service = remote.Service.init(owner);
    try service.setConnected(true, 1);
    try service.setControl(true, 2);
    var harness = try InputViewHarness.init(&service);
    defer harness.deinit();
    const cx = harness.cx;
    const view = harness.view;
    const r = view.viewport.?.globalRect();
    cx.handleMouseDown(r.x + 2, r.y + r.h / 2, .{}); // fit letterbox stays local
    cx.handleMouseUp(r.x + 2, r.y + r.h / 2);
    try std.testing.expect(!view.captured);
    try std.testing.expectEqual(@as(usize, 0), (try service.snapshot(service.binding())).queued);
    harness.click(view.image_node.?);
    try std.testing.expect(view.captured);
    try std.testing.expect(cx.focus_manager.getFocused() == view.viewport);
    var wire: InputWire = .{};
    try wire.pump(&service);
    try std.testing.expectEqual(@as(usize, 12), wire.len);
    try wire.expectPointer(0, 960, 600, 1);
    try wire.expectPointer(6, 960, 600, 0);
    cx.handleKeyDown(.left_shift, .{ .shift = true });
    cx.handleKeyDown(.a, .{ .shift = true });
    cx.handleKeyUp(.left_shift, .{});
    cx.handleKeyDown(.a, .{}); // an OS repeat after Shift-up must not leave remote 'A' held
    cx.handleKeyUp(.a, .{});
    cx.handleKeyDown(.escape, .{});
    cx.handleKeyUp(.escape, .{});
    cx.handleTextInput("A");
    cx.handleImePreedit("中文", 0);
    cx.handleImeCommit("中文");
    try wire.pump(&service);
    try std.testing.expectEqual(@as(usize, 68), wire.len);
    try wire.expectKey(12, 0xffe1, true);
    try wire.expectKey(20, 'A', true);
    try wire.expectKey(28, 0xffe1, false);
    try wire.expectKey(36, 'A', true);
    try wire.expectKey(44, 'A', false);
    try wire.expectKey(52, 0xff1b, true);
    try wire.expectKey(60, 0xff1b, false);
    try std.testing.expectEqual(@as(usize, 0), service.pressed_count);
    try std.testing.expect(view.captured);
    cx.handleScroll(.{ .x = r.x + r.w / 2, .y = r.y + r.h / 2, .dx = 0, .dy = -1 });
    try wire.pump(&service);
    try std.testing.expectEqual(@as(usize, 80), wire.len);
    try wire.expectPointer(68, 960, 600, 8);
    try wire.expectPointer(74, 960, 600, 0);
    cx.handleKeyDown(.left_ctrl, .{ .ctrl = true });
    cx.handleKeyDown(.left_alt, .{ .ctrl = true, .alt = true });
    try wire.pump(&service);
    cx.handleKeyDown(.escape, .{ .ctrl = true, .alt = true });
    cx.handleKeyUp(.escape, .{ .ctrl = true, .alt = true });
    cx.handleKeyUp(.left_alt, .{ .ctrl = true });
    cx.handleKeyUp(.left_ctrl, .{});
    try wire.pump(&service);
    try std.testing.expect(!view.captured and !view.pointer_captured);
    try std.testing.expect(cx.focus_manager.getFocused() != view.viewport);
    try std.testing.expect(!(try service.snapshot(service.binding())).focused);
    try std.testing.expectEqual(@as(usize, 112), wire.len); // only Ctrl/Alt pairs; Esc stayed local
    try std.testing.expectEqual(@as(usize, 0), service.pressed_count);
}

test "BMC view Cx preserves held before capture modifiers and keeps release shortcut local" {
    var service = remote.Service.init(owner);
    try service.setConnected(true, 1);
    try service.setControl(true, 2);
    var harness = try InputViewHarness.init(&service);
    defer harness.deinit();
    const cx = harness.cx;
    const view = harness.view;
    harness.click(view.image_node.?);
    try std.testing.expect(view.captured);
    var wire: InputWire = .{};
    try wire.pump(&service);
    wire.len = 0;

    // A modifier held before capture, and a combined native event, can arrive
    // with flags but without a separate modifier key-down in the viewport.
    cx.handleKeyDown(.right, .{ .shift = true });
    cx.handleKeyUp(.right, .{ .shift = true });
    try wire.pump(&service);
    try std.testing.expectEqual(@as(usize, 32), wire.len);
    try wire.expectKey(0, 0xffe1, true);
    try wire.expectKey(8, 0xff53, true);
    try wire.expectKey(16, 0xff53, false);
    try wire.expectKey(24, 0xffe1, false);
    try std.testing.expectEqual(@as(usize, 0), service.pressed_count);
    try std.testing.expect(view.captured);

    cx.handleKeyDown(.escape, .{ .ctrl = true, .alt = true });
    cx.handleKeyUp(.escape, .{ .ctrl = true, .alt = true });
    try wire.pump(&service);
    try std.testing.expectEqual(@as(usize, 32), wire.len);
    try std.testing.expect(!view.captured);
    try std.testing.expect(cx.focus_manager.getFocused() != view.viewport);
}

test "BMC view Cx original scrollbars remain local and mapped input includes scroll exactly once" {
    var service = remote.Service.init(owner);
    try service.setConnected(true, 1);
    try service.setControl(true, 2);
    var harness = try InputViewHarness.init(&service);
    defer harness.deinit();
    const view = harness.view;
    harness.click(view.tool_nodes[2].?);
    renderFrames(harness.cx, 8);
    harness.click(findById(view.menus[2].?.content, "bmc.display.original").?);
    harness.cx.handleKeyDown(.escape, .{});
    renderFrames(harness.cx, 8);
    try std.testing.expectEqual(mapping.Mode.original, view.mode);
    const scroll = view.scroll.?;
    const viewport = view.viewport.?.globalRect();
    harness.cx.handleScroll(.{ .x = viewport.x + viewport.w / 2, .y = viewport.y + viewport.h / 2, .dx = 0, .dy = -1 });
    renderFrames(harness.cx, 2); // native overlay scrollbars appear after local scroll activity
    // The ScrollArea's own vertical thumb, where zenit draws it: along the right edge, at the top
    // after this first small scroll (at least its 24 point minimum long).
    const visual = ui.widgets.scroll_area.ScrollbarVisual;
    const bar_rect: ui.ComputedRect = .{ .x = viewport.x + viewport.w - visual.edge_inset - visual.active_thickness, .y = viewport.y + visual.edge_inset, .w = visual.active_thickness, .h = visual.min_length };
    harness.cx.handleMouseDown(bar_rect.x + bar_rect.w / 2, bar_rect.y + bar_rect.h / 2, .{});
    try std.testing.expect(scroll.state.scrollbar_dragging);
    try std.testing.expect(!view.captured);
    harness.cx.handleMouseMove(bar_rect.x + bar_rect.w / 2, bar_rect.y + bar_rect.h / 2 + 50);
    harness.cx.handleMouseUp(bar_rect.x + bar_rect.w / 2, bar_rect.y + bar_rect.h / 2 + 50);
    renderFrames(harness.cx, 3);
    try std.testing.expect(scroll.state.scroll_y > 0);
    const r = view.viewport.?.globalRect();
    harness.cx.handleScroll(.{ .x = r.x + r.w / 2, .y = r.y + r.h / 2, .dx = -31.25, .dy = 0 });
    renderFrames(harness.cx, 3);
    try std.testing.expect(scroll.state.scroll_x > 0);
    try std.testing.expectEqual(@as(usize, 0), (try service.snapshot(service.binding())).queued);
    const x = r.x + 100.6;
    const y = r.y + 100.6;
    const image_rect = view.image_node.?.globalRect();
    const remote_x: u16 = @intFromFloat(@floor(x - image_rect.x));
    const remote_y: u16 = @intFromFloat(@floor(y - image_rect.y));
    harness.cx.handleMouseDown(x, y, .{});
    harness.cx.handleMouseUp(x, y);
    var wire: InputWire = .{};
    try wire.pump(&service);
    try std.testing.expect(view.captured);
    try std.testing.expectEqual(@as(usize, 12), wire.len);
    try wire.expectPointer(0, remote_x, remote_y, 1);
    try wire.expectPointer(6, remote_x, remote_y, 0);
}

test "BMC view Cx old capture cannot follow renewed input transport or control authority" {
    for (0..3) |barrier| {
        var service = remote.Service.init(owner);
        try service.setConnected(true, 1);
        try service.setControl(true, 2);
        var harness = try InputViewHarness.init(&service);
        defer harness.deinit();
        harness.click(harness.view.image_node.?);
        var wire: InputWire = .{};
        try wire.pump(&service);
        const sequence = (try service.snapshot(service.binding())).last_input_sequence;
        switch (barrier) {
            0 => _ = service.releaseAll(service.binding(), .geometry_changed),
            1 => {
                try service.setControl(false, 3);
                try service.setControl(true, 4);
            },
            else => {
                try service.setConnected(true, 2);
                try service.setControl(true, 4);
            },
        }
        // A newer backend focus must not revive the View's older capture.
        service.setFocus(true);
        harness.cx.handleKeyDown(.a, .{});
        try wire.pump(&service);
        try std.testing.expect(!harness.view.captured);
        try std.testing.expectEqual(sequence, (try service.snapshot(service.binding())).last_input_sequence);
        try std.testing.expectEqual(@as(usize, 12), wire.len);
        harness.click(harness.view.image_node.?); // explicit recapture establishes new authority
        harness.cx.handleKeyDown(.a, .{});
        harness.cx.handleKeyUp(.a, .{});
        try wire.pump(&service);
        try std.testing.expect(harness.view.captured);
        try std.testing.expectEqual(@as(usize, 40), wire.len);
    }
}

test "BMC view Cx drag clamps outside and focus menu modal barriers release actual remote downs" {
    var service = remote.Service.init(owner);
    try service.setConnected(true, 1);
    try service.setControl(true, 2);
    var harness = try InputViewHarness.init(&service);
    defer harness.deinit();
    const cx = harness.cx;
    const view = harness.view;
    const r = view.viewport.?.globalRect();
    cx.handleMouseDown(r.x + r.w / 2, r.y + r.h / 2, .{});
    cx.handleKeyDown(.a, .{});
    var wire: InputWire = .{};
    try wire.pump(&service);
    try std.testing.expectEqual(@as(usize, 1), service.pressed_count);
    try std.testing.expectEqual(@as(u8, 1), service.pressed_buttons);
    cx.handleMouseMove(2000, -100);
    cx.handleMouseUp(2000, -100);
    try wire.pump(&service);
    try wire.expectPointer(wire.len - 6, 1919, 0, 0);
    try std.testing.expect(!view.pointer_captured);
    cx.focus_manager.clearFocus();
    try wire.pump(&service);
    try std.testing.expect(!view.captured);
    try std.testing.expectEqual(@as(usize, 0), service.pressed_count);
    try std.testing.expectEqual(@as(u8, 0), service.pressed_buttons);
    harness.click(view.image_node.?);
    cx.handleMouseDownEx(r.x + r.w / 2, r.y + r.h / 2, .right, .{});
    try wire.pump(&service);
    try wire.expectPointer(wire.len - 6, 960, 600, 4);
    cx.handleMouseUpEx(r.x + r.w / 2, r.y + r.h / 2, .right, .{});
    cx.handleMouseDownEx(r.x + r.w / 2, r.y + r.h / 2, .middle, .{});
    try wire.pump(&service);
    try wire.expectPointer(wire.len - 6, 960, 600, 2);
    cx.handleMouseUpEx(r.x + r.w / 2, r.y + r.h / 2, .middle, .{});
    harness.click(view.tool_nodes[1].?);
    renderFrames(cx, 8);
    try wire.pump(&service);
    try std.testing.expect(!view.captured);
    try std.testing.expectEqual(@as(u8, 0), service.pressed_buttons);
    harness.click(findById(view.menus[1].?.content, "bmc.keys.escape").?);
    renderFrames(cx, 8);
    const chord_start = wire.len;
    try wire.pump(&service);
    try std.testing.expectEqual(chord_start + 16, wire.len);
    try wire.expectKey(chord_start, 0xff1b, true);
    try wire.expectKey(chord_start + 8, 0xff1b, false);
    try std.testing.expect(!view.captured and !(try service.snapshot(service.binding())).focused);
    harness.click(view.image_node.?);
    cx.handleKeyDown(.a, .{});
    try wire.pump(&service);
    const open = try harness.scope.createSignal(bool, false);
    const modal = try ui.widgets.Modal(.{ .title = "Local fixture", .open = open, .width = @as(f32, 300), .close_icon_asset = ui.icons.x }).mount(harness.scope, cx);
    if (!modal.portaled) try cx.root.?.appendChild(a, modal.overlay);
    open.set(true);
    renderFrames(cx, 8);
    try wire.pump(&service);
    try std.testing.expect(!view.captured and view.capture_authority == null);
    try std.testing.expectEqual(@as(usize, 0), service.pressed_count);
    open.set(false);
    renderFrames(cx, 8);
    const after_modal = wire.len;
    cx.handleKeyDown(.a, .{});
    try wire.pump(&service);
    try std.testing.expectEqual(after_modal, wire.len); // closing a local overlay never recaptures
    harness.click(view.image_node.?);
    harness.renderer.vtable.focus_changed(harness.renderer.context, false);
    harness.renderer.vtable.focus_changed(harness.renderer.context, true);
    cx.handleKeyDown(.a, .{});
    try wire.pump(&service);
    try std.testing.expect(!view.captured and !view.pending_capture);
    try std.testing.expectEqual(@as(usize, 0), service.pressed_count);
}

test "BMC view Cx pending capture cannot cross an input barrier while its menu exits" {
    var service = remote.Service.init(owner);
    try service.setConnected(true, 1);
    try service.setControl(true, 2);
    var harness = try InputViewHarness.init(&service);
    defer harness.deinit();
    harness.click(harness.view.tool_nodes[0].?);
    renderFrames(harness.cx, 8);
    harness.click(findById(harness.view.menus[0].?.content, "bmc.control.capture").?);
    try std.testing.expect(harness.view.pending_capture);
    _ = service.releaseAll(service.binding(), .geometry_changed);
    renderFrames(harness.cx, 8);
    try std.testing.expect(!harness.view.captured and !harness.view.pending_capture);
    try std.testing.expect(!(try service.snapshot(service.binding())).focused);
    try std.testing.expectEqual(@as(usize, 0), (try service.snapshot(service.binding())).queued);
    harness.click(harness.view.tool_nodes[0].?);
    renderFrames(harness.cx, 8);
    harness.click(findById(harness.view.menus[0].?.content, "bmc.control.capture").?);
    renderFrames(harness.cx, 8);
    try std.testing.expect(harness.view.captured);
    try std.testing.expect((try service.snapshot(service.binding())).focused);
}

test "BMC view Cx resize refuses old texture until the published geometry is actually uploaded" {
    var service = remote.Service.init(owner);
    try service.setConnected(true, 1);
    try service.setControl(true, 2);
    try service.beginGeometryChange(1);
    try service.completeGeometryChange(1, 1);
    var harness = try InputViewHarness.init(&service);
    defer harness.deinit();
    const view = harness.view;
    harness.click(view.image_node.?);
    harness.cx.handleKeyDown(.left_shift, .{ .shift = true });
    var wire: InputWire = .{};
    try wire.pump(&service);
    try std.testing.expect(view.captured);
    try std.testing.expectEqual(@as(usize, 1), service.pressed_count);
    try service.beginGeometryChange(1); // decoder saw DesktopSize; complete new pixels do not exist yet
    harness.cx.handleKeyUp(.left_shift, .{});
    try wire.pump(&service);
    try std.testing.expect(!view.captured);
    try std.testing.expectEqual(@as(usize, 0), service.pressed_count);
    const sequence = (try service.snapshot(service.binding())).last_input_sequence;
    harness.click(view.image_node.?);
    try std.testing.expect(!view.captured);
    try std.testing.expect((try service.snapshot(service.binding())).geometry_pending);
    try service.completeGeometryChange(1, 2); // worker published, Runtime still reports/presents generation 1
    harness.click(view.image_node.?);
    try std.testing.expect(!view.captured);
    try std.testing.expect(!(try service.snapshot(service.binding())).focused);
    try std.testing.expectEqual(sequence, (try service.snapshot(service.binding())).last_input_sequence);
    try std.testing.expectEqual(@as(u64, 1), view.frame_generation);
    harness.fixture.frame_generation = 2; // owner poll advanced before the GPU queue drained
    harness.fixture.width = 640;
    harness.fixture.height = 480;
    renderFrames(harness.cx, 2);
    try std.testing.expect(view.texture == null);
    const pixels = try a.alloc(u8, 640 * 480 * 4);
    defer a.free(pixels);
    @memset(pixels, 0);
    try harness.sink.submit(try frames.Frame.copyForGeneration(a, harness.budget, owner, 2, 2, 640, 480, pixels));
    _ = try harness.sink.drain();
    renderFrames(harness.cx, 3);
    try std.testing.expectEqual(@as(u64, 2), view.frame_generation);
    try std.testing.expect(!view.captured); // uploading never restores human focus by itself
    const image = view.image_node.?.globalRect();
    const x = image.x + image.w / 2 + 0.2;
    const y = image.y + image.h / 2 + 0.2;
    harness.cx.handleMouseDown(x, y, .{});
    harness.cx.handleMouseUp(x, y);
    try wire.pump(&service);
    try std.testing.expect(view.captured);
    try std.testing.expectEqual(@as(u64, 2), view.capture_authority.?.frame_generation);
    try wire.expectPointer(wire.len - 12, 320, 240, 1);
    try wire.expectPointer(wire.len - 6, 320, 240, 0);
}

test "BMC summaries and log wells are opaque inside their native panels while the video HUD stays local" {
    const theme = @import("../../../shared/ui/theme/app_theme.zig");
    const previous = theme.currentName();
    const parameters = theme.materialParameters();
    defer {
        theme.select(previous);
        _ = theme.setMaterialParameters(parameters.transparency, parameters.blur);
    }
    var service = remote.Service.init(owner);
    try service.setConnected(true, 1);
    try service.setControl(true, 2);
    var h = try InputViewHarness.init(&service);
    defer h.deinit();
    var publication: @import("../../../features/shell/view/shell_styles.zig").ThemePublication = .{};
    for ([_]theme.Name{ .dark, .light, .sauber }) |name| {
        for ([_]f32{ 0, 75, 100 }) |t| {
            theme.select(name);
            _ = theme.setMaterialParameters(t, 24);
            publication.publish(h.cx, theme.widgetTheme(name));
            for ([_]usize{ 3, 4 }) |index| {
                h.view.open[index].set(true);
                renderFrames(h.cx, 12);
                const card = findById(h.view.menus[index].?.content, if (index == 3) "bmc.power.summary" else "bmc.boot.summary").?;
                // KVM popups keep the fixed dark scheme over video in every app theme (bugfix-2).
                const popup = theme.schemeColors(.dark);
                try std.testing.expectEqual(popup.well.withAlpha(255), card.getBackground());
                try std.testing.expectEqual(popup.fg_1, (if (index == 3) h.view.power_label else h.view.boot_label).?.getText().?.color);
                try std.testing.expectEqual(@as(?ui.ColorScheme, .dark), theme.tokenScheme(h.cx.tokensFor(h.view.menus[index].?.content)));
                h.view.open[index].set(false);
                renderFrames(h.cx, 10);
            }
            h.view.log_open.?.set(true);
            renderFrames(h.cx, 12);
            try std.testing.expectEqual(theme.current().well.withAlpha(255), h.view.log_route_text.?.getBackground());
            try std.testing.expectEqual(theme.current().well.withAlpha(255), h.view.log_viewport.?.getBackground());
            try std.testing.expectEqual(theme.current().surface_2.withAlpha(255), h.view.log_footer.?.getBackground());
            h.view.log_open.?.set(false);
            renderFrames(h.cx, 10);
            h.fixture.route = .connecting;
            h.fixture.video = .awaiting_frame;
            try h.renderer.vtable.update(h.renderer.context, .{ .owner = owner, .revision = 1, .title = "Synthetic", .status = "" });
            renderFrames(h.cx, 6);
            const surface = findById(h.view.waiting.?, "bmc.progress.surface").?;
            const route_card = findById(h.view.waiting.?, "bmc.progress.route").?;
            try std.testing.expectEqual(surface, route_card.parent.?);
            try std.testing.expectEqual(theme.current().overlay.withAlpha(255), surface.getBackground());
            try std.testing.expect(surface.style.glass_params() == null);
            try std.testing.expectEqual(ui.Color.BLACK, h.view.viewport.?.getBackground());
            try std.testing.expectEqual(theme.current().well.withAlpha(255), route_card.getBackground());
            try std.testing.expectEqualDeep(h.view.waiting.?.globalRect(), surface.globalRect());
            // j8WXoF O2: the HUD hides under the connection card.
            try std.testing.expect(!h.view.overlays.?.hud_shown.peek());
            h.fixture.route = .connected;
            h.fixture.video = .streaming;
            try h.renderer.vtable.update(h.renderer.context, .{ .owner = owner, .revision = 2, .title = "Synthetic", .status = "" });
            renderFrames(h.cx, 6);
            try std.testing.expectEqual(ui.Color.BLACK, h.view.viewport.?.getBackground());
        }
    }
}

test "BMC key popup keeps the fixed dark scheme over video in light and dark app themes" {
    const theme = @import("../../../shared/ui/theme/app_theme.zig");
    const previous = theme.currentName();
    const parameters = theme.materialParameters();
    defer {
        theme.select(previous);
        _ = theme.setMaterialParameters(parameters.transparency, parameters.blur);
    }
    var service = remote.Service.init(owner);
    try service.setConnected(true, 1);
    try service.setControl(true, 2);
    var h = try InputViewHarness.init(&service);
    defer h.deinit();
    var publication: @import("../../../features/shell/view/shell_styles.zig").ThemePublication = .{};
    for ([_]theme.Name{ .light, .sauber, .dark }) |name| {
        for ([_]f32{ 0, 100 }) |t| {
            theme.select(name);
            _ = theme.setMaterialParameters(t, 24);
            publication.publish(h.cx, theme.widgetTheme(name));
            h.view.open[1].set(true);
            renderFrames(h.cx, 12);
            const popup = h.view.menus[1].?;
            const dark = theme.schemeTokens(.dark);
            try std.testing.expectEqual(@as(?ui.ColorScheme, .dark), theme.tokenScheme(h.cx.tokensFor(popup.content)));
            // Title in the scheme's primary ink; the hint in its supporting ink (fg_1 once
            // the material is at least half clear), whatever the app theme is.
            try std.testing.expectEqual(theme.schemeColors(.dark).fg_1, findById(popup.chrome, "bmc.keys.title").?.getText().?.color);
            try std.testing.expectEqual(dark.tokens.color.zw_fg_supporting, findById(popup.chrome, "bmc.keys.hint").?.getText().?.color);
            if (t == 100) try std.testing.expectEqual(theme.schemeColors(.dark).fg_1, dark.tokens.color.zw_fg_supporting);
            // The panel is zenit's own Popover surface in the fixed dark scheme: opaque over the
            // video at every material setting, with the scheme's hairline; nothing repaints it.
            const fill = popup.chrome.getBackground();
            try std.testing.expectEqual(@as(u8, 255), fill.a);
            try std.testing.expectEqual(dark.tokens.color.border, popup.chrome.style.border.color);
            try std.testing.expect(popup.chrome.style.glass_params() == null);
            try std.testing.expect(@import("../../../shared/ui/theme/theme_states.zig").contrast(fill, theme.schemeColors(.dark).fg_1) >= 4.5);
            h.view.open[1].set(false);
            renderFrames(h.cx, 10);
        }
    }
}

test "BMC material retained FPS tooltip survives parent detach and reopen" {
    const theme = @import("../../../shared/ui/theme/app_theme.zig");
    const previous = theme.currentName();
    defer theme.select(previous);
    var service = remote.Service.init(owner);
    try service.setConnected(true, 1);
    try service.setControl(true, 2);
    var h = try InputViewHarness.init(&service);
    defer h.deinit();
    var publication: @import("../../../features/shell/view/shell_styles.zig").ThemePublication = .{};
    for ([_]theme.Name{ .light, .sauber, .dark }) |name| {
        theme.select(name);
        publication.publish(h.cx, theme.widgetTheme(name));
        h.view.open[2].set(true);
        renderFrames(h.cx, 12);
        // The pointer rests on the control (the native Tooltip's own hover, past its open delay).
        const control = findById(h.view.menus[2].?.content, "bmc.display.fps").?;
        const rect = control.globalRect();
        h.cx.handleMouseMove(rect.x + rect.w / 2, rect.y + rect.h / 2);
        renderFrames(h.cx, 30);
        const tip = findById(h.cx.root.?, "bmc.display.fps.tooltip") orelse return error.RetainedHelpMissing;
        try std.testing.expect(tip.isDisplayedInTree());
        try std.testing.expect(tip.getOpacity() > 0.98);
        // The control hint is zenit's default Tooltip look for the published theme: its own
        // `tooltip_bg` bubble (not the overlay material) behind the `tooltip_fg` label.
        const tokens = h.cx.tokens.tokens.color;
        try std.testing.expectEqual(tokens.tooltip_bg, tip.getBackground());
        try std.testing.expect(tip.style.glass_params() == null);
        const label = findTextIn(tip) orelse return error.RetainedHelpMissing;
        try std.testing.expectEqual(tokens.tooltip_fg, label.getText().?.color);
        h.cx.handleMouseMove(0, 0);
        h.view.open[2].set(false);
        renderFrames(h.cx, 12);
    }
}

test "BMC FPS HUD defaults on, preserves pointer routing and toggles without changing video bounds" {
    var service = remote.Service.init(owner);
    try service.setConnected(true, 1);
    try service.setControl(true, 2);
    var h = try InputViewHarness.init(&service);
    defer h.deinit();
    // Match video aspect so the HUD lies over the image, not fit-mode padding.
    h.cx.setViewport(860, 581.5);
    renderFrames(h.cx, 3);
    try std.testing.expect(h.view.show_fps.peek());
    const before = h.view.viewport.?.globalRect();
    const hud = h.view.overlays.?.hud;
    try std.testing.expect(hud.globalRect().w > 0 and hud.globalRect().h > 0);
    // j8WXoF O2: the native Tooltip surface, dark in every app theme.
    const surface = findById(hud, "bmc.fps.display").?;
    try std.testing.expectEqualStrings("TooltipSurface", surface.meta.ownership.meta.component_name.?);
    try std.testing.expect(surface.getBackground().r < 80);
    // The stats overlay must not consume input intended for the remote video.
    h.click(hud);
    try std.testing.expect(h.view.captured);
    var wire: InputWire = .{};
    try wire.pump(&service);
    try std.testing.expect(wire.len > 0);
    h.view.open[@backingInt(vm.Menu.display)].set(true);
    renderFrames(h.cx, 3);
    const display = h.view.menus[@backingInt(vm.Menu.display)].?;
    const fit_rect = findById(display.content, "bmc.display.fit").?.globalRect();
    const original_rect = findById(display.content, "bmc.display.original").?.globalRect();
    try std.testing.expectApproxEqAbs(fit_rect.w, original_rect.w, 0.1);
    const refresh_rect = findById(display.content, "bmc.display.refresh").?.globalRect();
    const log_rect = findById(display.content, "bmc.display.connection_log").?.globalRect();
    try std.testing.expectApproxEqAbs(refresh_rect.y, log_rect.y, 0.1);
    try std.testing.expect(refresh_rect.x + refresh_rect.w <= log_rect.x);
    const expanded_height = display.chrome.globalRect().h;
    const toggle = findById(h.cx.root.?, "bmc.display.fps").?;
    h.click(toggle);
    renderFrames(h.cx, 3);
    try std.testing.expect(!h.view.show_fps.peek());
    try std.testing.expectEqual(.none, h.view.fps_detail.?.style.display);
    try std.testing.expect(display.chrome.globalRect().h < expanded_height);
    try std.testing.expectEqual(before, h.view.viewport.?.globalRect());
    h.click(toggle);
    renderFrames(h.cx, 3);
    try std.testing.expect(h.view.show_fps.peek());
    try std.testing.expectEqual(.flex, h.view.fps_detail.?.style.display);
    try std.testing.expectApproxEqAbs(expanded_height, display.chrome.globalRect().h, 0.1);
    h.click(findById(display.chrome, "bmc.display.close").?);
    renderFrames(h.cx, 3);
    try std.testing.expectEqual(h.view.tool_nodes[@backingInt(vm.Menu.display)], h.cx.focus_manager.getFocused());
}

test "BMC launcher contract: toolbar bottom anchors top corners, capture is reported, overlays give way" {
    var service = remote.Service.init(owner);
    try service.setConnected(true, 1);
    try service.setControl(true, 2);
    var h = try InputViewHarness.init(&service);
    defer h.deinit();
    h.cx.setViewport(1100, 720);
    renderFrames(h.cx, 3);
    const info = h.renderer.vtable.launcher_context.?(h.renderer.context);
    const bar = h.view.toolbar.?.globalRect();
    try std.testing.expect(info.bounds != null);
    try std.testing.expectEqual(bar.y + bar.h, info.top_chrome_bottom.?);
    try std.testing.expect(info.captured == null);
    // A top-right launcher: the HUD's right edge moves to the launcher's left - 12.
    const vp = h.view.viewport.?.globalRect();
    const icon: @import("../../../host/plugin_ui_contract.zig").LauncherRect = .{ .x = vp.x + vp.w - 64, .y = bar.y + bar.h + 12, .w = 48, .h = 48 };
    h.renderer.vtable.place_launcher.?(h.renderer.context, .{ .corner = .top_right, .rect = icon });
    renderFrames(h.cx, 4);
    const surface = findById(h.view.overlays.?.hud, "bmc.fps.display").?.globalRect();
    try std.testing.expectApproxEqAbs(icon.x - 12, surface.x + surface.w, 1.0);
    // Capture is reported to the host; the O1 status shows the captured state.
    h.click(h.view.viewport.?);
    renderFrames(h.cx, 2);
    try std.testing.expect(h.view.captured);
    try std.testing.expect(h.renderer.vtable.launcher_context.?(h.renderer.context).captured != null);
    try std.testing.expect(h.view.overlays.?.status_shown.peek());
    try std.testing.expect(std.mem.indexOf(u8, h.view.overlays.?.status_label.peek(), "捕获") != null);
    try std.testing.expect(!h.view.overlays.?.hud_shown.peek());
    h.renderer.vtable.place_launcher.?(h.renderer.context, null);
}

test "BMC Select keyboard highlight remains visible inside compact dropdown" {
    const cx = try ui.Cx.init(a, std.testing.io);
    defer cx.deinit();
    cx.setViewport(860, 480);
    const scope = try ui.Scope.init(a, null, cx.owner);
    defer scope.dispose();
    cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .direction = .column, .padding = .{ .top = 210 } }, .{});
    const options = [_]ui.widgets.SelectOption{
        .{ .value = "a", .label = "First" },   .{ .value = "b", .label = "Second" },
        .{ .value = "c", .label = "Third" },   .{ .value = "d", .label = "Fourth" },
        .{ .value = "e", .label = "Fifth" },   .{ .value = "f", .label = "Sixth" },
        .{ .value = "g", .label = "Seventh" }, .{ .value = "h", .label = "Last" },
    };
    // Production BMC menus: zenit Select owns rows, viewport, keyboard scrolling and the
    // panel surface; BMC supplies nothing but the options.
    const select = try ui.widgets.Select(.{ .panel_width = .trigger, .options = &options, .width = 180, .open = true, .virtualize = true, .max_dropdown_height = 120 }).mount(scope, cx);
    try cx.root.?.appendChild(a, select.wrapper);
    renderFrames(cx, 8);
    const state = ui.widgets.select.stateOf(select);
    const panel = select.panel;
    const key = state.focus_target.behavior.events.on_key_down.?;
    const key_ctx = state.focus_target.behavior.events.key_context;
    // A dropdown capped below its content cannot show all eight rows (zenit's own 28pt rows):
    // keyboard navigation has to scroll the highlighted row into view.
    try std.testing.expect(panel.globalRect().h <= 120.5);
    try std.testing.expect(panel.globalRect().h < 8 * 28);
    for ([_]struct { key: ui.events.KeyCode, index: usize }{ .{ .key = .end, .index = 7 }, .{ .key = .home, .index = 0 } }) |step| {
        _ = key(step.key, .{}, key_ctx);
        renderFrames(cx, 4);
        try std.testing.expectEqual(@as(?usize, step.index), state.highlighted_index);
        try expectRowVisible(state, panel, step.index);
    }
    for (0..7) |_| {
        _ = key(.down, .{}, key_ctx);
        renderFrames(cx, 3);
    }
    try std.testing.expectEqual(@as(?usize, 7), state.highlighted_index);
    try expectRowVisible(state, panel, 7);
    // Theme changes repaint zenit's own panel without rebuilding the menu.
    const theme = @import("../../../shared/ui/theme/app_theme.zig");
    const previous = theme.currentName();
    defer theme.select(previous);
    var publication: @import("../../../features/shell/view/shell_styles.zig").ThemePublication = .{};
    for ([_]theme.Name{ .light, .sauber, .dark }) |name| {
        theme.select(name);
        publication.publish(cx, theme.widgetTheme(name));
        renderFrames(cx, 6);
        try std.testing.expectEqual(@as(u8, 255), panel.getBackground().a);
        try std.testing.expectEqual(@as(?usize, 7), state.highlighted_index);
        try expectRowVisible(state, panel, 7);
    }
}

/// The highlighted row is located through the public accessibility contract
/// (active descendant), which also holds for virtualized row pools.
fn expectRowVisible(state: anytype, panel: *ui.Node, index: usize) !void {
    _ = index;
    const target = state.focus_target.behavior.interaction.a11y.?.active_descendant_element_id;
    try std.testing.expect(target != 0xFFFFFFFF);
    const row = findElement(panel, target) orelse return error.RowNotMounted;
    const rect = row.globalRect();
    const bounds = panel.globalRect();
    try std.testing.expect(rect.y >= bounds.y - 0.5 and rect.y + rect.h <= bounds.y + bounds.h + 0.5);
    // zenit's own option row (size token `row`).
    try std.testing.expectApproxEqAbs(@as(f32, 28), rect.h, 0.5);
}

fn findElement(node: *ui.Node, element_id: u32) ?*ui.Node {
    if (node.element_id_raw == element_id) return node;
    for (node.children.items) |child| if (findElement(child, element_id)) |found| return found;
    return null;
}

test "BMC view toolbar disconnect is owner bound and updates connection state" {
    var service = remote.Service.init(owner);
    defer service.close();
    try service.setConnected(true, 1);
    try service.setControl(true, 1);
    var harness = try InputViewHarness.init(&service);
    defer harness.deinit();
    const view = harness.view;
    try std.testing.expectEqualStrings("已连接", view.connection_hint.peek());
    // Include the sidebar at the minimum supported width; every action remains
    // inside the toolbar and the connection state retains its own width.
    harness.cx.root.?.setStyleInline(a, .{ .width = .{ .px = 604 } });
    renderFrames(harness.cx, 4);
    const bar = view.toolbar.?.globalRect();
    for (view.tool_nodes) |maybe| {
        const rect = maybe.?.globalRect();
        try std.testing.expect(rect.x >= bar.x and rect.x + rect.w <= bar.x + bar.w + 0.5);
    }
    const button = view.disconnect_node.?;
    const narrow = button.globalRect();
    try std.testing.expect(narrow.x + narrow.w <= bar.x + bar.w + 0.5);
    try std.testing.expect(narrow.w > 0 and narrow.x >= bar.x);
    // The state is spelled on the button while zenit's labelled controls fit; folded to icons
    // it stays the button's accessible name and tooltip.
    try std.testing.expectEqual(view.last_compact.?, view.connection_label.peek().len == 0);
    try std.testing.expectEqualStrings("已连接", view.connection_hint.peek());
    try std.testing.expectEqualStrings("已连接", button.behavior.interaction.a11y.?.label.?);
    harness.cx.root.?.setStyleInline(a, .{ .width = .{ .px = 900 } });
    renderFrames(harness.cx, 12);
    try std.testing.expect(!view.last_compact.?);
    const rect = button.globalRect();
    try std.testing.expectEqualStrings("已连接", view.connection_label.peek());
    try std.testing.expectEqual(ui.icons.circle_check.icon_id, view.connection_symbol.peek().?.icon_id);
    harness.cx.handleMouseMove(rect.x + rect.w / 2, rect.y + rect.h / 2);
    renderFrames(harness.cx, 4);
    try std.testing.expectEqual(ui.icons.unplug.icon_id, view.connection_symbol.peek().?.icon_id);
    try std.testing.expectEqualStrings("断开连接", view.connection_hint.peek());
    try std.testing.expectEqualStrings("断开连接", view.connection_label.peek());
    harness.cx.handleMouseMove(20, 100);
    renderFrames(harness.cx, 4);
    try std.testing.expectEqual(ui.icons.circle_check.icon_id, view.connection_symbol.peek().?.icon_id);
    harness.fixture.video = .awaiting_frame;
    try harness.renderer.vtable.update(harness.renderer.context, .{ .owner = owner, .revision = 2, .title = "Synthetic", .status = "" });
    try std.testing.expectEqual(ui.icons.loader_circle.icon_id, view.connection_symbol.peek().?.icon_id);
    button.behavior.events.on_click.?.invoke();
    try std.testing.expect(view.disconnect_confirm_open.peek());
    try std.testing.expectEqualStrings("取消连接？", view.disconnect_confirm_title.peek());
    try std.testing.expectEqualStrings("停止连接", view.disconnect_confirm_action.peek());
    try std.testing.expectEqual(@as(usize, 0), harness.fixture.cancel_requests);
    findById(harness.cx.root.?, "bmc.disconnect.return").?.behavior.events.on_click.?.invoke();
    try std.testing.expect(!view.disconnect_confirm_open.peek());
    harness.fixture.route = .failed;
    harness.fixture.video = .failed;
    try harness.renderer.vtable.update(harness.renderer.context, .{ .owner = owner, .revision = 3, .title = "Synthetic", .status = "" });
    try std.testing.expectEqual(ui.icons.circle_x.icon_id, view.connection_symbol.peek().?.icon_id);
    harness.fixture.route = .connected;
    harness.fixture.video = .streaming;
    try harness.renderer.vtable.update(harness.renderer.context, .{ .owner = owner, .revision = 4, .title = "Synthetic", .status = "" });
    button.behavior.events.on_click.?.invoke();
    button.behavior.events.on_click.?.invoke();
    try std.testing.expectEqual(@as(usize, 0), harness.fixture.cancel_requests);
    try std.testing.expect(view.disconnect_confirm_open.peek());
    try std.testing.expectEqualStrings("断开连接？", view.disconnect_confirm_title.peek());
    findById(harness.cx.root.?, "bmc.disconnect.return").?.behavior.events.on_click.?.invoke();
    try std.testing.expectEqual(@as(usize, 0), harness.fixture.cancel_requests);
    button.behavior.events.on_click.?.invoke();
    const confirm = findById(harness.cx.root.?, "bmc.disconnect.confirm").?;
    confirm.behavior.events.on_click.?.invoke();
    confirm.behavior.events.on_click.?.invoke();
    try std.testing.expectEqual(@as(usize, 1), harness.fixture.cancel_requests);
    try std.testing.expect(view.disconnect_disabled.peek());
    try std.testing.expect(!view.captured);
    harness.fixture.cleanup = .released;
    harness.fixture.route = .closed;
    harness.fixture.video = .closed;
    try harness.renderer.vtable.update(harness.renderer.context, .{ .owner = owner, .revision = 2, .title = "Synthetic", .status = "" });
    const ended = harness.renderer.vtable.connection_status.?(harness.renderer.context);
    try std.testing.expectEqual(.ended, ended.state);
    try std.testing.expectEqualStrings("已断开", view.connection_hint.peek());
}

test "BMC theme standard buttons and inputs consume their own surface roles across every palette" {
    const theme = @import("../../../shared/ui/theme/app_theme.zig");
    const previous = theme.currentName();
    const parameters = theme.materialParameters();
    defer {
        theme.select(previous);
        _ = theme.setMaterialParameters(parameters.transparency, parameters.blur);
    }
    for (@import("../../../config/theme_presets.zig").ids) |id| {
        theme.selectTokens(@import("../../../config/theme_registry.zig").builtinTokens(id));
        _ = theme.setMaterialParameters(100, 0);
        const cx = try ui.Cx.init(a, std.testing.io);
        defer cx.deinit();
        cx.setTheme(theme.widgetTheme(theme.currentName()));
        cx.setViewport(600, 400);
        const scope = try ui.Scope.init(a, null, cx.owner);
        defer scope.dispose();
        cx.root = try ui.vstack(cx, .{ .width = .fill(), .height = .fill(), .background = theme.current().overlay }, .{});
        const secondary = try ui.widgets.Button(.{ .label = "连接日志", .variant = .secondary }).mount(scope, cx);
        const primary = try ui.widgets.Button(.{ .label = "连接", .variant = .primary }).mount(scope, cx);
        const field = try ui.widgets.Input(.{}).mountResult(scope, cx);
        try cx.root.?.appendChild(a, secondary);
        try cx.root.?.appendChild(a, primary);
        try cx.root.?.appendChild(a, field.node);
        renderFrames(cx, 4);
        errdefer std.debug.print("palette={s}\n", .{id});
        // Secondary Button and Input fill are zenit's default role tokens (the theme no
        // longer rewrites them); the primary fill is zenit's default primary role too (T-1).
        try std.testing.expectEqual(cx.tokens.tokens.color.button_secondary_bg, secondary.getBackground());
        try std.testing.expectEqual(cx.tokens.tokens.color.button_primary_bg, primary.getBackground());
        try std.testing.expectEqual(cx.tokens.tokens.color.input_bg, field.input_container.getBackground());
        try std.testing.expect(!std.meta.eql(secondary.getBackground(), theme.current().overlay));
    }
}

/// A wall clock the view's timed behaviour runs on in these tests.
const TestClock = struct {
    var ms: f64 = 1_000_000;
    fn now() f64 {
        return ms;
    }
};

test "BMC view still picture: a frame reads only the owner's tokens, schedules nothing, and one publication is read once" {
    var service = remote.Service.init(owner);
    defer service.close();
    try service.setConnected(true, 1);
    try service.setControl(true, 2);
    var h = try InputViewHarness.init(&service);
    defer h.deinit();
    h.view.clock = TestClock.now;
    renderFrames(h.cx, 12);
    try std.testing.expect(h.view.texture != null);
    // The view registers one frame hook and no node render hook.
    try std.testing.expect(h.view.root.?.meta.per_frame.hooks.before_render.main == null and h.view.root.?.meta.per_frame.hooks.before_render.count == 0);
    const snapshots = h.fixture.snapshot_reads;
    const pulses = h.fixture.pulse_reads;
    const key = h.view.layout_key.?;
    renderFrames(h.cx, 40);
    // 40 frames of a still picture: 40 token reads, no snapshot, no geometry, no clock, no frame request.
    try std.testing.expectEqual(snapshots, h.fixture.snapshot_reads);
    try std.testing.expectEqual(pulses + 40, h.fixture.pulse_reads);
    try std.testing.expectEqual(key, h.view.layout_key.?);
    try std.testing.expect(!h.view.stale and !h.view.management_stale and !h.view.overlays_stale);
    try std.testing.expect(h.view.progress_due_ms == null and h.view.performance_due_ms == null and h.view.overlay_due_ms == null);
    try std.testing.expectEqual(@as(?u64, null), h.cx.next_redraw_delay_ns);
    try std.testing.expect(!h.cx.wantsFrame());
    // The owner publishes one change: read once, on the next frame, and then quiet again.
    h.fixture.cleanup = .awaiting;
    renderFrames(h.cx, 6);
    try std.testing.expectEqual(snapshots + 1, h.fixture.snapshot_reads);
    try std.testing.expectEqualStrings("正在释放连接", h.renderer.vtable.connection_status.?(h.renderer.context).label);
    try std.testing.expect(!h.cx.wantsFrame());
    // Frame counters alone (a new video frame) are not a state publication.
    const again = h.fixture.snapshot_reads;
    h.fixture.cleanup = .not_started;
    renderFrames(h.cx, 3);
    try std.testing.expectEqual(again + 1, h.fixture.snapshot_reads);
}

test "BMC view HUD follows the picture's hover through the reveal state machine on wall-clock deadlines" {
    var service = remote.Service.init(owner);
    defer service.close();
    try service.setConnected(true, 1);
    try service.setControl(true, 2);
    var h = try InputViewHarness.init(&service);
    defer h.deinit();
    h.view.clock = TestClock.now;
    h.cx.setViewport(860, 581.5);
    renderFrames(h.cx, 6);
    const overlays = h.view.overlays.?;
    try std.testing.expect(overlays.hud_shown.peek() and !overlays.hud_faded);
    try std.testing.expect(h.view.overlay_due_ms == null);
    const vp = h.view.viewport.?.globalRect();
    // Enter: shown for 150 ms more, with exactly that deadline armed.
    h.cx.handleMouseMove(vp.x + vp.w / 2, vp.y + vp.h / 2);
    renderFrames(h.cx, 2);
    try std.testing.expect(h.view.picture_hovered.?.peek());
    try std.testing.expectEqual(@TypeOf(h.view.hud.state).leaving, h.view.hud.state);
    try std.testing.expect(!overlays.hud_faded);
    try std.testing.expectEqual(@as(?f64, TestClock.ms + 150), h.view.overlay_due_ms);
    try std.testing.expect(h.cx.next_redraw_delay_ns != null);
    TestClock.ms += 149;
    renderFrames(h.cx, 2);
    try std.testing.expect(!overlays.hud_faded);
    TestClock.ms += 1;
    renderFrames(h.cx, 2);
    try std.testing.expect(overlays.hud_faded);
    try std.testing.expect(h.view.overlay_due_ms == null);
    // Resting over the picture costs nothing further.
    const pulses = h.fixture.pulse_reads;
    const snapshots = h.fixture.snapshot_reads;
    renderFrames(h.cx, 10);
    try std.testing.expectEqual(snapshots, h.fixture.snapshot_reads);
    try std.testing.expectEqual(pulses + 10, h.fixture.pulse_reads);
    try std.testing.expect(overlays.hud_faded);
    // Leave: hidden for 600 ms more, then back.
    h.cx.handleMouseMove(vp.x + vp.w / 2, 2);
    renderFrames(h.cx, 2);
    try std.testing.expect(!h.view.picture_hovered.?.peek());
    try std.testing.expectEqual(@as(?f64, TestClock.ms + 600), h.view.overlay_due_ms);
    TestClock.ms += 599;
    renderFrames(h.cx, 2);
    try std.testing.expect(overlays.hud_faded);
    // Back over the picture before the 600 ms are up: stays hidden, the wait is dropped.
    h.cx.handleMouseMove(vp.x + vp.w / 2, vp.y + vp.h / 2);
    renderFrames(h.cx, 2);
    try std.testing.expect(overlays.hud_faded and h.view.overlay_due_ms == null);
    h.cx.handleMouseMove(vp.x + vp.w / 2, 2);
    renderFrames(h.cx, 2);
    TestClock.ms += 600;
    renderFrames(h.cx, 2);
    try std.testing.expect(!overlays.hud_faded);
    try std.testing.expect(h.view.overlay_due_ms == null);
}

test "BMC view clocks run only while their readout is on screen: capture hint, connection progress" {
    var service = remote.Service.init(owner);
    defer service.close();
    try service.setConnected(true, 1);
    try service.setControl(true, 2);
    var h = try InputViewHarness.init(&service);
    defer h.deinit();
    h.view.clock = TestClock.now;
    h.cx.setViewport(860, 581.5);
    renderFrames(h.cx, 6);
    // Capture: the transient hint arms its 3 s deadline and nothing else.
    const vp = h.view.viewport.?.globalRect();
    h.cx.handleMouseDown(vp.x + vp.w / 3, vp.y + vp.h / 3, .{});
    h.cx.handleMouseUp(vp.x + vp.w / 3, vp.y + vp.h / 3);
    renderFrames(h.cx, 3);
    try std.testing.expect(h.view.captured);
    const overlays = h.view.overlays.?;
    try std.testing.expect(overlays.hint_shown.peek());
    try std.testing.expect(h.view.overlay_due_ms != null);
    TestClock.ms += 2999;
    renderFrames(h.cx, 2);
    try std.testing.expect(overlays.hint_visible);
    TestClock.ms += 1;
    renderFrames(h.cx, 2);
    try std.testing.expect(!overlays.hint_visible);
    // The fade-out leaves the layout 200 ms later, then the clock is gone.
    TestClock.ms += 200;
    renderFrames(h.cx, 2);
    try std.testing.expect(!overlays.hint_shown.peek());
    try std.testing.expect(h.view.overlay_due_ms == null);
    // A connection attempt in progress shows elapsed times: re-read every 100 ms while it runs.
    var tracker = console.progress.Tracker.initAt(0, 0);
    tracker.setStageAt(.route, 10);
    h.fixture.video = .negotiating;
    h.fixture.progress = tracker.snapshotAt(500);
    renderFrames(h.cx, 3);
    try std.testing.expect(h.view.progress_shown and h.view.progress_running);
    try std.testing.expectEqual(@as(?f64, TestClock.ms + 100), h.view.progress_due_ms);
    const reads = h.fixture.snapshot_reads;
    renderFrames(h.cx, 5);
    try std.testing.expectEqual(reads, h.fixture.snapshot_reads);
    TestClock.ms += 100;
    renderFrames(h.cx, 2);
    try std.testing.expectEqual(reads + 1, h.fixture.snapshot_reads);
    // Streaming again: the card is gone and so is its clock.
    h.fixture.video = .streaming;
    h.fixture.progress = .{};
    renderFrames(h.cx, 3);
    try std.testing.expect(!h.view.progress_shown);
    try std.testing.expect(h.view.progress_due_ms == null);
}

test "BMC view compact toolbar tooltips: native hover opens, leaving closes, never under an open menu" {
    var service = remote.Service.init(owner);
    defer service.close();
    try service.setConnected(true, 1);
    try service.setControl(true, 2);
    var h = try InputViewHarness.init(&service);
    defer h.deinit();
    h.view.clock = TestClock.now;
    h.cx.setViewport(1440, 900);
    // Wide: labels are shown, no tooltip.
    renderFrames(h.cx, 8);
    try std.testing.expect(!h.view.hints_enabled.peek());
    h.cx.root.?.setStyleInline(a, .{ .width = .{ .px = 480 } });
    renderFrames(h.cx, 8);
    try std.testing.expect(h.view.last_compact.? and h.view.hints_enabled.peek());
    const keys = h.view.tool_nodes[1].?.globalRect();
    h.cx.handleMouseMove(keys.x + keys.w / 2, keys.y + keys.h / 2);
    renderFrames(h.cx, 30);
    try std.testing.expect(tooltipOpen(h.cx, "bmc.keys.tooltip"));
    const vp = h.view.viewport.?.globalRect();
    h.cx.handleMouseMove(vp.x + vp.w / 2, vp.y + vp.h / 2);
    renderFrames(h.cx, 30);
    try std.testing.expect(!tooltipOpen(h.cx, "bmc.keys.tooltip"));
    // A menu is open: hovering a toolbar button shows no tooltip.
    h.click(h.view.tool_nodes[2].?);
    renderFrames(h.cx, 12);
    try std.testing.expect(h.view.open[2].peek() and !h.view.hints_enabled.peek());
    h.cx.handleMouseMove(keys.x + keys.w / 2, keys.y + keys.h / 2);
    renderFrames(h.cx, 30);
    try std.testing.expect(!tooltipOpen(h.cx, "bmc.keys.tooltip"));    // The menu closes under the resting pointer: the hint shows without a new hover-enter.
    h.view.open[2].set(false);
    renderFrames(h.cx, 40);
    try std.testing.expect(h.view.hints_enabled.peek());
    try std.testing.expect(tooltipOpen(h.cx, "bmc.keys.tooltip"));
}
fn findPortaled(cx: *ui.Cx, id: []const u8) ?*ui.Node {
    for (cx.overlay_stack.layers.items) |maybe| if (maybe) |layer| if (layer.content_node) |node| if (findById(node, id)) |found| return found;
    return null;
}
/// The tooltip's content is displayed (in the window tree or its portal layer).
fn tooltipOpen(cx: *ui.Cx, id: []const u8) bool {
    const node = findById(cx.root.?, id) orelse findPortaled(cx, id) orelse return false;
    return node.isDisplayedInTree() and node.getOpacity() > 0.5;
}

test "BMC view two windows: the HUD keeps its fixed dark scheme whichever theme either window publishes" {
    const theme = @import("../../../shared/ui/theme/app_theme.zig");
    const previous = theme.currentName();
    defer theme.select(previous);
    var services_: [2]remote.Service = .{ remote.Service.init(owner), remote.Service.init(owner) };
    defer for (&services_) |*service| service.close();
    var windows: [2]InputViewHarness = undefined;
    for (&windows, &services_) |*window, *service| {
        try service.setConnected(true, 1);
        try service.setControl(true, 2);
        window.* = try InputViewHarness.init(service);
        window.view.clock = TestClock.now;
        window.cx.setViewport(860, 581.5);
    }
    defer for (&windows) |*window| window.deinit();
    var publications: [2]@import("../../../features/shell/view/shell_styles.zig").ThemePublication = .{ .{}, .{} };
    const Paint = struct { background: ui.Color, ink: ui.Color };
    var reference: ?Paint = null;
    // Each step switches one window's theme (the other keeps its own): light/dark, dark/light, both light, both dark.
    const steps = [_][2]theme.Name{ .{ .light, .dark }, .{ .dark, .light }, .{ .light, .light }, .{ .sauber, .dark }, .{ .dark, .dark } };
    for (steps) |step| {
        for (&windows, &publications, step) |*window, *publication, name| {
            theme.select(name);
            publication.publish(window.cx, theme.widgetTheme(name));
            renderFrames(window.cx, 6);
        }
        for (&windows, step) |*window, name| {
            theme.select(name);
            renderFrames(window.cx, 3);
            const hud = window.view.overlays.?.hud;
            try std.testing.expect(window.view.overlays.?.hud_shown.peek());
            const surface = findById(hud, "bmc.fps.display").?;
            // The HUD is the native TooltipSurface with `fixedDark`: one paint in every window theme.
            var ink: ?ui.Color = null;
            if (surface.getText()) |text| ink = text.color;
            for (surface.children.items) |child| if (ink == null) if (child.getText()) |text| {
                ink = text.color;
            };
            const paint: Paint = .{ .background = surface.getBackground(), .ink = ink orelse return error.HudTextMissing };
            try std.testing.expect(paint.background.r < 80 and paint.background.g < 80 and paint.background.b < 80);
            if (reference) |first| try std.testing.expectEqual(first, paint) else reference = paint;
        }
    }
}

test "BMC view two windows: native controls follow their own window's theme, popup controls keep the fixed scheme" {
    const theme = @import("../../../shared/ui/theme/app_theme.zig");
    const previous = theme.currentName();
    defer theme.select(previous);
    var services_: [2]remote.Service = .{ remote.Service.init(owner), remote.Service.init(owner) };
    defer for (&services_) |*service| service.close();
    var windows: [2]InputViewHarness = undefined;
    for (&windows, &services_) |*window, *service| {
        try service.setConnected(true, 1);
        try service.setControl(true, 2);
        window.* = try InputViewHarness.init(service);
        window.cx.setViewport(1100, 700);
    }
    defer for (&windows) |*window| window.deinit();
    var publications: [2]@import("../../../features/shell/view/shell_styles.zig").ThemePublication = .{ .{}, .{} };
    const steps = [_][2]theme.Name{ .{ .light, .dark }, .{ .dark, .light }, .{ .light, .light }, .{ .sauber, .dark }, .{ .dark, .dark } };
    for (steps) |step| {
        for (&windows, &publications, step) |*window, *publication, name| {
            theme.select(name);
            publication.publish(window.cx, theme.widgetTheme(name));
            renderFrames(window.cx, 6);
        }
        var dialog_fill: [2]ui.Color = undefined;
        for (&windows, step, 0..) |*window, name, index| {
            theme.select(name);
            const view = window.view;
            // The log dialog (closed, retained in its portal, then open): zenit's secondary Button
            // in this window's theme.
            const dismiss = findById(view.log_modal.?.dialog, "bmc.connection_log.dismiss").?;
            try std.testing.expectEqual(window.cx.tokens.tokens.color.button_secondary_bg, dismiss.getBackground());
            view.log_open.?.set(true);
            renderFrames(window.cx, 8);
            try std.testing.expectEqual(window.cx.tokens.tokens.color.button_secondary_bg, dismiss.getBackground());
            dialog_fill[index] = dismiss.getBackground();
            view.log_open.?.set(false);
            renderFrames(window.cx, 8);
            // A popup over the video keeps the fixed dark scheme: its native Button paints that
            // scheme's role token whatever the window theme is.
            view.open[@backingInt(vm.Menu.control)].set(true);
            renderFrames(window.cx, 10);
            const only = findById(view.menus[0].?.chrome, "bmc.control.view_only").?;
            const scheme = window.cx.tokensFor(only);
            try std.testing.expectEqual(@as(?ui.ColorScheme, .dark), theme.tokenScheme(scheme));
            try std.testing.expectEqual(scheme.tokens.color.button_secondary_bg, only.getBackground());
            view.open[@backingInt(vm.Menu.control)].set(false);
            renderFrames(window.cx, 8);
        }
        // Different themes give different paint (the check above is not vacuous); equal themes equal paint.
        if (step[0] == step[1]) try std.testing.expectEqual(dialog_fill[0], dialog_fill[1]) else if ((step[0] == .dark) != (step[1] == .dark)) try std.testing.expect(!std.meta.eql(dialog_fill[0], dialog_fill[1]));
    }
}

test "BMC view nested overlays: a Select open inside a KVM popup survives a theme switch and still commits" {
    const theme = @import("../../../shared/ui/theme/app_theme.zig");
    const previous = theme.currentName();
    defer theme.select(previous);
    var service = remote.Service.init(owner);
    defer service.close();
    try service.setConnected(true, 1);
    try service.setControl(true, 2);
    var h = try InputViewHarness.init(&service);
    defer h.deinit();
    h.cx.setViewport(1100, 700);
    renderFrames(h.cx, 6);
    const view = h.view;
    // The synthetic management service publishes the power actions.
    h.fixture.management_available = true;
    h.fixture.management_write_requestable = true;
    try h.renderer.vtable.update(h.renderer.context, .{ .owner = owner, .revision = 2, .title = "Synthetic", .status = "" });
    renderFrames(h.cx, 6);
    try std.testing.expect(view.power_options.peek().len >= 2);
    try std.testing.expect(!view.power_disabled.peek());
    var publication: @import("../../../features/shell/view/shell_styles.zig").ThemePublication = .{};
    theme.select(.light);
    publication.publish(h.cx, theme.widgetTheme(.light));
    renderFrames(h.cx, 6);
    h.click(view.tool_nodes[@backingInt(vm.Menu.power)].?);
    renderFrames(h.cx, 10);
    try std.testing.expect(view.open[@backingInt(vm.Menu.power)].peek());
    h.click(findById(h.cx.root.?, "bmc.power.action.trigger").?);
    renderFrames(h.cx, 10);
    const dropdown = findById(h.cx.root.?, "bmc.power.action.dropdown").?;
    try std.testing.expect(dropdown.isDisplayedInTree());
    // The Select's portaled panel keeps the scheme of the popup it was opened from.
    try std.testing.expectEqual(@as(?ui.ColorScheme, .dark), theme.tokenScheme(h.cx.tokensFor(dropdown)));
    for ([_]theme.Name{ .dark, .sauber, .light }) |name| {
        theme.select(name);
        publication.publish(h.cx, theme.widgetTheme(name));
        renderFrames(h.cx, 10);
        // Both layers are still up, in the popup's scheme, and the popup did not lose its content.
        try std.testing.expect(view.open[@backingInt(vm.Menu.power)].peek());
        try std.testing.expect(findById(h.cx.root.?, "bmc.power.action.dropdown").?.isDisplayedInTree());
        try std.testing.expectEqual(@as(?ui.ColorScheme, .dark), theme.tokenScheme(h.cx.tokensFor(findById(h.cx.root.?, "bmc.power.action.dropdown").?)));
        try std.testing.expect(findById(view.menus[3].?.chrome, "bmc.power.execute") != null);
    }
    const options = view.power_options.peek();
    const pick = options[options.len - 1];
    try std.testing.expect(!std.mem.eql(u8, pick.value, view.power_value.peek().?));
    h.click(findById(h.cx.root.?, pick.test_id.?).?);
    renderFrames(h.cx, 10);
    try std.testing.expectEqualStrings(pick.value, view.power_value.peek().?);
    // Committing closes the Select's own panel (zenit may also unmount it); the popup stays.
    if (findById(h.cx.root.?, "bmc.power.action.dropdown")) |panel| try std.testing.expect(!panel.isDisplayedInTree());
    try std.testing.expect(view.open[@backingInt(vm.Menu.power)].peek());
}

test "BMC view focus moved outside an open popup: closing keeps the outside focus, unmounting with it open is clean" {
    var service = remote.Service.init(owner);
    defer service.close();
    try service.setConnected(true, 1);
    try service.setControl(true, 2);
    var h = try InputViewHarness.init(&service);
    defer h.deinit();
    h.cx.setViewport(1100, 700);
    renderFrames(h.cx, 6);
    const view = h.view;
    const keys = @backingInt(vm.Menu.keys);
    h.click(view.tool_nodes[keys].?);
    renderFrames(h.cx, 10);
    try std.testing.expect(view.open[keys].peek());
    // Focus leaves the popup for a control outside it; the popup then closes.
    h.cx.setFocus(view.disconnect_node.?);
    renderFrames(h.cx, 3);
    view.open[keys].set(false);
    renderFrames(h.cx, 10);
    try std.testing.expect(!view.open[keys].peek());
    try std.testing.expect(h.cx.focus_manager.getFocused() == view.disconnect_node.?);
    // Open again, move focus outside, and leave it open: the harness unmounts the view next
    // (testing allocator: no leak, no write to a released node).
    h.click(view.tool_nodes[keys].?);
    renderFrames(h.cx, 10);
    try std.testing.expect(view.open[keys].peek());
    h.cx.setFocus(view.disconnect_node.?);
    renderFrames(h.cx, 3);
    try std.testing.expect(h.cx.focus_manager.getFocused() == view.disconnect_node.?);
}

test "BMC view unmounting with a menu open on the icon-only toolbar: the hint conditions flip during teardown without touching disposed tooltips" {
    // Each toolbar hint is a native Tooltip whose `disabled` state is derived from the view's
    // `hints_enabled`. Closing the menus while the view unmounts turns that condition back on, so
    // the hints' `disabled` sources change in the middle of teardown; the scope disposal that follows
    // must not run anything against a disposed tooltip or signal (an earlier hint implementation
    // kept a visibility effect in the view's scope that wrote the disposed tooltip's `open`).
    var service = remote.Service.init(owner);
    defer service.close();
    try service.setConnected(true, 1);
    try service.setControl(true, 2);
    var h = try InputViewHarness.init(&service);
    defer h.deinit();
    h.cx.setViewport(1100, 700);
    h.cx.root.?.setStyleInline(h.cx.allocator, .{ .width = .{ .px = 420 } });
    renderFrames(h.cx, 12);
    const view = h.view;
    try std.testing.expect(view.tool_icon_only.peek());
    const keys = @backingInt(vm.Menu.keys);
    h.click(view.tool_nodes[keys].?);
    renderFrames(h.cx, 10);
    try std.testing.expect(view.open[keys].peek());
    try std.testing.expect(!view.hints_enabled.peek());
    // Unmount (as the host does before disposing the view's scope): the menus close and the hint
    // condition flips back on during teardown. `deinit` then unmounts again (a no-op) and disposes.
    h.renderer.vtable.unmount(h.renderer.context);
    try std.testing.expect(!view.open[keys].peek());
    try std.testing.expect(view.hints_enabled.peek());
}
