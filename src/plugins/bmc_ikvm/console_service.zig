//! The renderer/AI boundary. This module contains no controller, driver,
//! transport, credentials or token access. Every snapshot owns its strings.
const std = @import("std");
const typed = @import("../../host/plugin_services.zig");
const identity = @import("../../host/identity.zig");
const operations = @import("../../host/operation.zig");
const services = @import("services.zig");
pub const remote_input = @import("remote_input.zig");
pub const framebuffer = @import("framebuffer.zig");
pub const progress = @import("connection_progress.zig");
pub const key: typed.ServiceKey = .{ .name = "bmc_ikvm.console", .major = 1 };
pub const RouteState = enum { frozen, connecting, connected, failed, closed };
pub const VideoState = enum { idle, authenticating, negotiating, awaiting_frame, streaming, failed, closed };
pub const ManagementState = enum { idle, authenticating, available, unavailable, closed };
pub const Cleanup = enum { not_started, awaiting, unknown, released };
pub const FailureStage = enum { route, identity, trust, authentication, management, video, cleanup };
pub const ControlReply = enum { full_control, video_only, reject };
pub const ControlState = enum { read_only, major, awaiting_authorization, rejected };
/// What AI is doing with this screen, read from the owner's real state (never inferred by views):
/// `operating` = an AI run holds the content automation lease or has input queued / in flight;
/// `observing` = an AI observation of this screen is being encoded or still inside its validity
/// window (≤ 15 s after capture).
pub const AiActivity = enum { none, observing, operating };
pub const Snapshot = struct {
    owner: identity.SessionHandle,
    operation: operations.OperationKey,
    name: []const u8 = "",
    target: []const u8 = "",
    route_summary: []const u8 = "",
    route: RouteState = .frozen,
    video: VideoState = .idle,
    management: ManagementState = .idle,
    cleanup: Cleanup = .not_started,
    input: remote_input.Snapshot,
    control: ControlState = .read_only,
    control_request: ?[4]u8 = null,
    failure_stage: ?FailureStage = null,
    failure_code: ?[]const u8 = null,
    progress: progress.Snapshot = .{},
    width: u32 = 0,
    height: u32 = 0,
    stride: usize = 0,
    format: framebuffer.Format = .rgba8,
    frame_sequence: u64 = 0,
    /// Complete CPU frame publications; independent of window submission rate.
    decoded_frames: u64 = 0,
    frame_generation: u64 = 0,
    rfb_ready: bool = false,
    read_only_requested: bool = false,
    ai: AiActivity = .none,
    /// These remote logout receipts describe only our own remote sessions.
    /// They never substitute for the local cleanup/FrameLease barrier.
    remote_web_logout: enum { not_created, awaiting, confirmed, unknown } = .not_created,
    remote_kvm_logout: enum { not_created, awaiting, confirmed, unknown } = .not_created,
};
pub const OwnedSnapshot = struct {
    arena: std.heap.ArenaAllocator,
    value: Snapshot,
    pub fn init(allocator: std.mem.Allocator, value: Snapshot) !OwnedSnapshot {
        var arena: std.heap.ArenaAllocator = .init(allocator);
        errdefer arena.deinit();
        // Telemetry owns its bounded paths/IDs by value. Copy its few borrowed
        // strings directly: parsing the large event array through generic JSON
        // creates an excessive stack frame in Debug builds.
        var result = value;
        try copyStrings(arena.allocator(), &result);
        return .{ .arena = arena, .value = result };
    }
    // Keep allocation failures in a small !void frame. Handling each failure in
    // init's large !OwnedSnapshot return frame multiplies Debug stack storage.
    fn copyStrings(a: std.mem.Allocator, result: *Snapshot) !void {
        result.name = try a.dupe(u8, result.name);
        result.target = try a.dupe(u8, result.target);
        result.route_summary = try a.dupe(u8, result.route_summary);
        result.failure_code = try copyOptional(a, result.failure_code);
        result.progress.failure_code = try copyOptional(a, result.progress.failure_code);
        if (result.progress.failure_event) |*event| event.error_code = try copyOptional(a, event.error_code);
        if (result.progress.discovery_issue) |*event| event.error_code = try copyOptional(a, event.error_code);
        for (&result.progress.events) |*event| event.error_code = try copyOptional(a, event.error_code);
    }
    pub fn deinit(self: *OwnedSnapshot) void {
        self.arena.deinit();
        self.* = undefined;
    }
    fn copyOptional(allocator: std.mem.Allocator, text: ?[]const u8) !?[]const u8 {
        return if (text) |value| try allocator.dupe(u8, value) else null;
    }
};
/// The owner's change tokens for a renderer. The owner publishes; the renderer compares and
/// re-reads `snapshot` / the management services only when a token moved. Reading it is cheap
/// (no allocation) and never performs IO. Main thread only.
pub const Pulse = struct {
    /// Moves whenever anything `snapshot` would return changes, except `frame_sequence`,
    /// `decoded_frames` and the running clocks (`progress.elapsed_ms`, `progress.stage_elapsed_ms`):
    /// a renderer that shows those keeps its own clock while they are on screen.
    state: u64,
    /// Moves whenever a power / boot snapshot or a management result changes.
    management: u64 = 0,
    /// == `Snapshot.decoded_frames` (complete CPU frame publications), for rate meters.
    decoded_frames: u64 = 0,
};
/// `Pulse.state` from a snapshot value: a hash of every field the token covers (borrowed strings
/// by content). Adding a field to `Snapshot` covers it here automatically.
pub fn stateToken(value: Snapshot) u64 {
    var hasher = std.hash.Wyhash.init(0x6b766d5f70756c73);
    inline for (@typeInfo(Snapshot).@"struct".field_names) |name| {
        if (comptime std.mem.eql(u8, name, "frame_sequence") or std.mem.eql(u8, name, "decoded_frames")) continue;
        if (comptime std.mem.eql(u8, name, "progress")) {
            // The tracker's own publication counter covers its events, stage times and failure
            // (every tracker mutation appends an event and advances `revision`).
            const p = value.progress;
            hashValue(&hasher, .{ p.revision, p.stage, p.waiting_for_user, p.route_hops, p.failure_stage, p.failure_code, p.event_count, p.started_unix_ms });
        } else hashValue(&hasher, @field(value, name));
    }
    return hasher.final();
}
fn hashValue(hasher: *std.hash.Wyhash, value: anytype) void {
    const T = @TypeOf(value);
    switch (@typeInfo(T)) {
        .bool => hasher.update(&.{@intFromBool(value)}),
        .int => hasher.update(std.mem.asBytes(&value)),
        .float => hasher.update(std.mem.asBytes(&value)),
        .@"enum" => hashValue(hasher, @backingInt(value)),
        .optional => if (value) |inner| {
            hasher.update(&.{1});
            hashValue(hasher, inner);
        } else hasher.update(&.{0}),
        .array => for (value) |item| hashValue(hasher, item),
        .pointer => |info| {
            comptime std.debug.assert(info.size == .slice);
            hashValue(hasher, value.len);
            if (info.child == u8) hasher.update(value) else for (value) |item| hashValue(hasher, item);
        },
        .@"struct" => |info| inline for (info.field_names) |name| hashValue(hasher, @field(value, name)),
        .@"union" => {
            hashValue(hasher, @backingInt(std.meta.activeTag(value)));
            switch (value) {
                inline else => |payload| if (@TypeOf(payload) != void) hashValue(hasher, payload),
            }
        },
        else => @compileError("console.stateToken: unsupported field type " ++ @typeName(T)),
    }
}
pub const Interface = struct {
    snapshot: *const fn (*anyopaque, typed.Binding, std.mem.Allocator) anyerror!OwnedSnapshot,
    pulse: *const fn (*anyopaque, typed.Binding) anyerror!Pulse,
    /// The renderer names the window that shows this session (its presentation wake target) when
    /// it mounts (`shown` = true) and when it unmounts (false), so the owner's worker publications
    /// wake that window only. null: the provider publishes on the main thread only.
    bind_presentation: ?*const fn (*anyopaque, typed.Binding, u64, bool) anyerror!void = null,
    request_control: *const fn (*anyopaque, typed.Binding) anyerror!void,
    reply_control: *const fn (*anyopaque, typed.Binding, [4]u8, ControlReply) anyerror!void,
    refresh: *const fn (*anyopaque, typed.Binding) anyerror!void,
    set_focus: *const fn (*anyopaque, typed.Binding, bool) anyerror!void,
    /// Queue a main-thread SessionHost close/retry. No connection or IO runs
    /// inside this call. The old instance must report released before retry.
    retry: *const fn (*anyopaque, typed.Binding) anyerror!void,
    /// Queue cancellation on the owner thread; keep the tab's diagnostics.
    cancel: ?*const fn (*anyopaque, typed.Binding) anyerror!void = null,
    /// Human action: freeze the request and ask the host for explicit approval.
    request_management: ?*const fn (*anyopaque, typed.Binding, services.ManagementRequest) services.RequestResult = null,
};
pub const definition = typed.Definition.of(Interface, key);

test "BMC console state token covers every snapshot field except frame counters and running clocks" {
    const owner: identity.SessionHandle = .{ .session_id = @fromBackingInt(1), .generation = 1 };
    const base: Snapshot = .{ .owner = owner, .operation = .{ .owner = .{ .session = owner }, .operation_id = 1 }, .name = "a", .input = .{ .input_epoch = 1, .control_generation = 1, .transport_generation = 1, .connected = true, .controlled = false, .focused = false, .capture_paused = false, .queued = 0, .remote_unconfirmed = false } };
    const token = stateToken(base);
    var same = base;
    same.frame_sequence = 9;
    same.decoded_frames = 9;
    same.progress.elapsed_ms = 1234;
    same.progress.stage_elapsed_ms = 99;
    try std.testing.expectEqual(token, stateToken(same));
    // The same text at another address is the same state.
    var text: [1]u8 = .{'a'};
    var moved = base;
    moved.name = &text;
    try std.testing.expectEqual(token, stateToken(moved));
    var changed = base;
    changed.video = .streaming;
    try std.testing.expect(stateToken(changed) != token);
    changed = base;
    changed.input.controlled = true;
    try std.testing.expect(stateToken(changed) != token);
    changed = base;
    changed.control_request = .{ 1, 2, 3, 4 };
    try std.testing.expect(stateToken(changed) != token);
    changed = base;
    changed.failure_code = "VideoClosed";
    try std.testing.expect(stateToken(changed) != token);
    changed = base;
    changed.ai = .observing;
    try std.testing.expect(stateToken(changed) != token);
    changed = base;
    changed.progress.revision = 1;
    changed.progress.events[0] = .{ .sequence = 1, .stage = .route };
    changed.progress.event_count = 1;
    try std.testing.expect(stateToken(changed) != token);
    changed = base;
    changed.frame_generation = 2;
    try std.testing.expect(stateToken(changed) != token);
}
