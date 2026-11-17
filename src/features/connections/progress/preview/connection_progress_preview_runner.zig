//! Isolated production view with local journal/ledger facts, without networking.
const std = @import("std");
const ui = @import("ui");
const App = @import("zenit_app").App;
const P = @import("../view/connection_progress_view.zig");
const ssh = @import("../../../../proto/ssh/session.zig");
const theme = @import("../../../../shared/ui/theme/app_theme.zig");
var scene: []const u8 = "direct";
var theme_name: theme.Name = .dark;
/// design-r3 稿 1 failure scenes (fixture hosts mirror the Pencil frames;
/// retry counts and waits are the connect job's real ones: 3 attempts, 0.5 → 1 s).
const Failure = enum { none, refused, auth, timeout, hostkey };
const refused_hops = [_]P.Hop{.{ .name = "staging-api", .host = "127.0.0.1", .user = "developer", .port = 65530 }};
const auth_hops = [_]P.Hop{.{ .name = "prod-web-01", .host = "10.0.1.24", .user = "deploy", .auth_mode = .private_key, .identity_file = "~/.ssh/id_ed25519", .saved_passphrase = true }};
const timeout_hops = [_]P.Hop{ .{ .name = "bastion-01", .host = "b1.example", .user = "admin" }, .{ .name = "build-agent-mac", .host = "10.0.3.8", .user = "admin" } };
const hostkey_hops = [_]P.Hop{.{ .name = "prod-db-primary", .host = "10.0.2.15", .user = "root" }};
const direct = [_]P.Hop{.{ .name = "ScaleX40-AI01", .host = "10.2.209.201", .user = "root" }};
const routed = [_]P.Hop{ .{ .name = "Bastion-01", .host = "b1.example", .user = "admin" }, .{ .name = "Bastion-02", .host = "b2.example", .user = "admin" }, direct[0] };
const long_direct = [_]P.Hop{.{ .name = "ScaleX40-AI01 · production-east-primary-cluster", .host = "2001:db8:1234:5678:abcd:ef01:2345:6789", .user = "operations-administrator", .port = 2222 }};
const Fixture = struct {
    cx: *ui.Cx,
    view: *P.View = undefined,
    result: *ui.Node,
    attempt: u64 = 1,
    failed: bool = false,
    handshake: bool = false,
    releasing: bool = false,
    cancelled: bool = false,
    route: bool = false,
    long: bool = false,
    pending: bool = true,
    failure: Failure = .none,
    /// Log records of the attempts before the current one, as the connection host keeps them
    /// (`connection_host.zig` passes every attempt's records in `Snapshot.logs`): after a retry the
    /// card still lists the failed rows of the earlier attempt, with their raw diagnostics.
    history: [32]P.LogRecord = undefined,
    history_len: usize = 0,
    shown_key: ?P.OperationKey = null,
    shown_journal: P.progress.Journal.Snapshot = undefined,
    fn stopRetry(raw: *anyopaque, _: P.OperationKey) !void {
        const self: *Fixture = @ptrCast(@alignCast(raw));
        try self.result.setTextContent(self.cx.allocator, "已停止自动重试");
    }
    fn retryNow(raw: *anyopaque, _: P.OperationKey) !void {
        const self: *Fixture = @ptrCast(@alignCast(raw));
        try self.result.setTextContent(self.cx.allocator, "已立即开始自动重试");
    }
    fn credentials(raw: *anyopaque, _: P.OperationKey) !void {
        const self: *Fixture = @ptrCast(@alignCast(raw));
        try self.result.setTextContent(self.cx.allocator, "已请求重新输入凭据");
    }
    fn trust(raw: *anyopaque, _: P.OperationKey) !void {
        const self: *Fixture = @ptrCast(@alignCast(raw));
        try self.result.setTextContent(self.cx.allocator, "已信任新密钥");
    }
    fn reject(raw: *anyopaque, _: P.OperationKey) void {
        const self: *Fixture = @ptrCast(@alignCast(raw));
        self.result.setTextContent(self.cx.allocator, "已断开") catch {};
    }
    fn edit(raw: *anyopaque, _: P.OperationKey) void {
        const self: *Fixture = @ptrCast(@alignCast(raw));
        self.result.setTextContent(self.cx.allocator, "已打开编辑连接") catch {};
    }
    fn canEdit(_: *anyopaque, _: P.OperationKey) bool {
        return true;
    }
    fn showFailure(self: *Fixture) !void {
        const hops: []const P.Hop = switch (self.failure) {
            .refused => &refused_hops,
            .auth => &auth_hops,
            .timeout => &timeout_hops,
            .hostkey => &hostkey_hops,
            .none => unreachable,
        };
        const key: P.OperationKey = .{ .owner = .{ .session = .{ .session_id = @fromBackingInt(1), .generation = 1 } }, .operation_id = 1, .attempt_id = self.attempt };
        const target = hops.len - 1;
        var journal: P.progress.Journal = .{};
        journal.begin(self.attempt);
        for (0..target) |hop| journal.record(.{ .attempt = self.attempt, .timestamp_ns = 0, .hop = hop, .hop_count = hops.len, .host = hops[hop].host, .port = hops[hop].port, .phase = .ready, .status = .succeeded });
        const phase: P.progress.Phase, const err: ?anyerror = switch (self.failure) {
            .refused => .{ .transport, error.ConnectionRefused },
            .auth => .{ .authentication, error.AuthenticationFailed },
            .timeout => .{ .transport, error.ConnectionTimedOut },
            .hostkey => .{ .host_key, null },
            .none => unreachable,
        };
        journal.record(.{ .attempt = self.attempt, .timestamp_ns = 50 * std.time.ns_per_ms, .hop = target, .hop_count = hops.len, .host = hops[target].host, .port = hops[target].port, .phase = phase, .status = .started });
        if (err) |value| journal.record(.{ .attempt = self.attempt, .timestamp_ns = 80 * std.time.ns_per_ms, .hop = target, .hop_count = hops.len, .host = hops[target].host, .port = hops[target].port, .phase = phase, .status = .failed, .failure = value });
        var ledger = try ssh.ResourceLedger.init(key, hops.len);
        for (0..hops.len) |hop| _ = ledger.record(key, hop, .session, .released);
        const delays = [_]i128{ 500 * std.time.ns_per_ms, 1000 * std.time.ns_per_ms };
        const pending_retry: ?P.Retry = switch (self.failure) {
            .refused => .{ .next_attempt = 2, .limit = 3, .remaining_ns = 300 * std.time.ns_per_ms, .delay_ns = 500 * std.time.ns_per_ms, .delays_ns = &delays },
            .timeout => .{ .next_attempt = 3, .limit = 3, .remaining_ns = 800 * std.time.ns_per_ms, .delay_ns = 1000 * std.time.ns_per_ms, .delays_ns = &delays },
            else => null,
        };
        try self.view.show(.{
            .key = key,
            .hops = hops,
            .journal = journal.snapshot(),
            .local_ready = true,
            .state = switch (self.failure) {
                .refused, .timeout => .retrying,
                .auth => .failed,
                .hostkey => .waiting_host_key,
                .none => unreachable,
            },
            .cleanup = if (self.failure == .hostkey) .not_started else .released,
            .resources = ledger.snapshot(),
            .failure = .{ .hop = target, .phase = phase, .reason = if (err) |value| P.failureText(value) else "", .err = err },
            .retry = pending_retry,
            .host_key = if (self.failure == .hostkey) .{ .saved_algorithm = "ssh-ed25519", .saved_fingerprint = "SHA256:9mQe4rKx2Lw0pT7vN3cZ8aJ1sD5fG6hK0lM2nB4vC7x", .offered_algorithm = "ssh-ed25519", .offered_fingerprint = "SHA256:Tb71HsQy5Dm1eR0uW4kJ6nP8rS2tV9wX3yZ5aB7cD1e" } else null,
            .connect_timeout_sec = 15,
        });
    }
    fn cancel(raw: *anyopaque, _: P.OperationKey) void {
        const self: *Fixture = @ptrCast(@alignCast(raw));
        self.cancelled = true;
        self.failed = false;
        self.pending = true;
        self.cx.requestRedraw();
    }
    fn retry(raw: *anyopaque, _: P.OperationKey) !void {
        const self: *Fixture = @ptrCast(@alignCast(raw));
        if (self.shown_key) |key| for (self.shown_journal.entries[0..self.shown_journal.count]) |entry| {
            if (self.history_len == self.history.len) break;
            self.history[self.history_len] = .{ .key = key, .entry = entry };
            self.history_len += 1;
        };
        self.shown_key = null;
        self.attempt += 1;
        self.failed = false;
        self.releasing = false;
        self.pending = true;
        try self.result.setTextContent(self.cx.allocator, "已调用原连接的重试操作");
        self.cx.requestRedraw();
    }
    fn close(raw: *anyopaque, _: P.OperationKey) void {
        const self: *Fixture = @ptrCast(@alignCast(raw));
        self.result.setTextContent(self.cx.allocator, "已关闭连接结果") catch {};
        self.cx.requestRedraw();
    }
    fn copy(raw: *anyopaque, _: P.OperationKey, text: []const u8) !void {
        const self: *Fixture = @ptrCast(@alignCast(raw));
        if (text.len == 0) return error.EmptyLogs;
        try self.result.setTextContent(self.cx.allocator, "已收到本次连接日志");
        self.cx.requestRedraw();
    }
    fn frame(raw: *anyopaque, _: u8, _: bool) ui.AfterLayoutResult {
        const self: *Fixture = @ptrCast(@alignCast(raw));
        if (!self.pending) return .done;
        self.pending = false;
        self.show() catch |err| std.log.err("progress fixture: {s}", .{@errorName(err)});
        return .needs_layout;
    }
    fn show(self: *Fixture) !void {
        if (self.failure != .none) return self.showFailure();
        const hops: []const P.Hop = if (self.long) &long_direct else if (self.route) &routed else &direct;
        const key: P.OperationKey = .{ .owner = .{ .session = .{ .session_id = @fromBackingInt(1), .generation = 1 } }, .operation_id = 1, .attempt_id = self.attempt };
        var journal: P.progress.Journal = .{};
        journal.begin(self.attempt);
        const current: usize = if (self.route) 1 else 0;
        for (0..current) |hop| journal.record(.{ .attempt = self.attempt, .timestamp_ns = 0, .hop = hop, .hop_count = hops.len, .host = hops[hop].host, .port = 22, .phase = .ready, .status = .succeeded });
        for ([_]P.progress.Phase{ .transport, .handshake, .host_key, .authentication }) |phase| journal.record(.{ .attempt = self.attempt, .timestamp_ns = @as(i128, @intCast(journal.count)) * 100 * std.time.ns_per_ms, .hop = current, .hop_count = hops.len, .host = hops[current].host, .port = 22, .phase = phase, .status = if (self.failed and phase == .authentication) .failed else .succeeded, .failure = if (self.failed and phase == .authentication) error.AuthenticationFailed else null });
        if (self.handshake and self.failed) {
            journal.begin(self.attempt);
            journal.record(.{ .attempt = self.attempt, .hop = 0, .hop_count = 1, .host = hops[0].host, .port = 22, .timestamp_ms = 1793600000000, .timestamp_ns = 0, .phase = .transport, .status = .started });
            journal.record(.{ .attempt = self.attempt, .hop = 0, .hop_count = 1, .host = hops[0].host, .port = 22, .timestamp_ms = 1793600000002, .timestamp_ns = 2 * std.time.ns_per_ms, .phase = .transport, .status = .succeeded });
            journal.record(.{ .attempt = self.attempt, .hop = 0, .hop_count = 1, .host = hops[0].host, .port = 22, .timestamp_ms = 1793600000003, .timestamp_ns = 3 * std.time.ns_per_ms, .phase = .handshake, .status = .started });
            journal.record(.{ .attempt = self.attempt, .hop = 0, .hop_count = 1, .host = hops[0].host, .port = 22, .timestamp_ms = 1793600000004, .timestamp_ns = 4 * std.time.ns_per_ms, .phase = .handshake, .status = .failed, .failure = error.SshHandshakeDisconnected, .diagnostic = "handshake transport host=10.2.209.201:22 hop=0 rc=-13 peer=10.2.209.201:22 local_port=55120 flags=4 identification_bytes=22 identification_hash=ab12 identification_complete=1\nhandshake failed host=10.2.209.201:22 hop=0 rc=-13 libssh2_code=-13 fd=12 recv_code=0 recv_errno=0 received_bytes=22 send_code=24 send_errno=0 sent_bytes=24 message=Failed getting banner" });
        }
        if (!self.failed) journal.record(.{ .attempt = self.attempt, .timestamp_ns = 520 * std.time.ns_per_ms, .hop = current, .hop_count = hops.len, .host = hops[current].host, .port = 22, .phase = .shell, .status = .started });
        var ledger = try ssh.ResourceLedger.init(key, hops.len);
        for (0..hops.len) |hop| _ = ledger.record(key, hop, .session, if (self.releasing) .releasing else if (self.failed or self.cancelled) .released else .owned);
        const snapshot = journal.snapshot();
        self.shown_key = key;
        self.shown_journal = snapshot;
        // The fixture scenes record a handful of entries per attempt; 64 holds the history and the current attempt.
        var logs: [64]P.LogRecord = undefined;
        var log_count: usize = 0;
        if (self.history_len != 0) {
            @memcpy(logs[0..self.history_len], self.history[0..self.history_len]);
            log_count = self.history_len;
            for (snapshot.entries[0..snapshot.count]) |entry| {
                if (log_count == logs.len) return error.FixtureLogOverflow;
                logs[log_count] = .{ .key = key, .entry = entry };
                log_count += 1;
            }
        }
        try self.view.show(.{ .key = key, .hops = hops, .journal = snapshot, .logs = logs[0..log_count], .local_ready = true, .state = if (self.cancelled) .cancelled else if (self.failed) .failed else .connecting, .cleanup = if (self.releasing) .releasing else if (self.failed or self.cancelled) .released else .not_started, .resources = ledger.snapshot() });
    }
};
fn mount(cx: *ui.Cx, scope: *ui.Scope) !*ui.Node {
    theme.select(theme_name);
    _ = theme.setMaterialParameters(0, 0);
    cx.setTheme(theme.widgetTheme(theme_name));
    const root = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .background = theme.baseColors().app, .padding = ui.Padding.all(24) }, .{});
    const result = try ui.text(cx, "", .{ .font_size = 12, .color = theme.current().fg_2 });
    result.meta.ownership.meta.test_id = "fixture.result";
    try root.appendChild(cx.allocator, result);
    const self = try scope.createState(Fixture, .{ .cx = cx, .result = result, .route = !std.mem.eql(u8, scene, "direct") and !std.mem.eql(u8, scene, "long") and !std.mem.eql(u8, scene, "handshake"), .long = std.mem.eql(u8, scene, "long"), .handshake = std.mem.eql(u8, scene, "handshake"), .failed = std.mem.eql(u8, scene, "handshake") or std.mem.eql(u8, scene, "failed") or std.mem.eql(u8, scene, "releasing"), .releasing = std.mem.eql(u8, scene, "releasing") });
    self.failure = std.meta.stringToEnum(Failure, scene) orelse .none;
    self.view = try P.View.mount(cx, scope, .{ .context = self, .cancel = Fixture.cancel, .retry = Fixture.retry, .close = Fixture.close, .copy_logs = Fixture.copy, .edit = Fixture.edit, .can_edit = Fixture.canEdit, .stop_retry = Fixture.stopRetry, .retry_now = Fixture.retryNow, .retry_with_credentials = Fixture.credentials, .trust_host_key = Fixture.trust, .reject_host_key = Fixture.reject });
    try cx.addAfterLayoutHook(self, Fixture.frame);
    return @import("../../../../shared/ui/window/fixture_window.zig").mount(cx, scope, root, .{ .background = theme.baseColors().app });
}
pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();
    scene = args.next() orelse "direct";
    if (args.next()) |name| theme_name = std.meta.stringToEnum(theme.Name, name) orelse .dark;
    const app = try App.init(std.heap.c_allocator, .{ .io = init.io, .window = .{ .width = 1280, .height = 720, .min_width = 620, .min_height = 480, .title = "ZeroWork · Connection progress preview", .chrome = @import("../../../../shared/ui/window/fixture_window.zig").chrome, .titlebar_height = @import("../../../../shared/ui/window/fixture_window.zig").title_height } });
    defer app.deinit();
    try app.runWith(mount);
}
