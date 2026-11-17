//! 连接失败 / 重试视图（design-r3 稿 1，Pencil RDiob › Hwswl）的投影：纯函数，只读连接状态，输出文案与状态。
//!
//! - 失败原因只来自连接状态机给出的错误码（`vt/reconnect.zig` 的 `FailureClass`）与主机密钥确认请求，不编造：
//!   拒连、超时、认证失败、主机密钥变更四类有专门文案，其余一律按“{阶段}失败 + 原有错误说明”。
//! - 自动重试行只在确实有一次自动重试在等待时出现，次数、间隔、倒计时都来自连接任务本身。
//! - 逐跳路径的状态是用户能看懂的说法（已就绪 / 已连通 / 拒绝连接 / 认证失败 / 超时 / 已中止 · 密钥不符 / 未连接），
//!   不再出现“已释放”。
const std = @import("std");
const reconnect = @import("../../../../vt/reconnect.zig");
const journal_mod = @import("../../../../proto/ssh/connection_progress.zig");

pub const Kind = enum { refused, timeout, authentication, host_key_changed, other };
pub const Tone = enum { ok, danger, warning, muted };
pub const AuthMode = enum { agent, private_key, password };

pub const Hop = struct {
    name: []const u8,
    host: []const u8,
    user: []const u8,
    port: u16 = 22,
    auth_mode: AuthMode = .agent,
    identity_file: []const u8 = "",
    saved_password: bool = false,
    saved_passphrase: bool = false,
};

pub const Retry = struct {
    next_attempt: u8,
    limit: u8,
    remaining_ns: i128,
    delay_ns: i128,
    /// Every automatic wait of this chain, in order (ns).
    delays_ns: []const i128 = &.{},
};

pub const HostKeyPair = struct {
    saved_algorithm: []const u8,
    saved_fingerprint: []const u8,
    offered_algorithm: []const u8,
    offered_fingerprint: []const u8,
};

pub const Input = struct {
    /// Network order, target last.
    hops: []const Hop,
    local_name: []const u8 = "",
    failure: ?anyerror = null,
    /// Fallback text for failures without a dedicated description.
    reason: []const u8 = "",
    failed_hop: ?usize = null,
    failed_phase: ?journal_mod.Phase = null,
    /// Hops whose `ready` phase succeeded in the failed attempt.
    reached: []const bool = &.{},
    retry: ?Retry = null,
    host_key: ?HostKeyPair = null,
    connect_timeout_sec: u16 = 0,
    can_edit: bool = false,
    can_retry: bool = false,
    retry_requested: bool = false,
    logs_open: bool = false,
    has_logs: bool = false,
};

pub const Badge = enum { info, success, warning, @"error" };
pub const Icon = enum { refused, timeout, shield, failed };
pub const Primary = enum { retry_now, credentials, trust_key };

pub const LogLine = struct { id: u64, text: []const u8 };
pub const HopRow = struct {
    key: u64,
    name: []const u8,
    address: []const u8,
    status: []const u8,
    tone: Tone,
};

pub const Projection = struct {
    /// Bumped by the owner on every publication: its strings live in a
    /// rotating arena, so an "equal" value must still replace the old one.
    generation: u64 = 0,
    shown: bool = false,
    kind: Kind = .other,
    icon: Icon = .failed,
    name: []const u8 = "",
    endpoint: []const u8 = "",
    badge: Badge = .@"error",
    badge_text: []const u8 = "",
    title: []const u8 = "",
    alert_warning: bool = false,
    alert_title: []const u8 = "",
    alert_detail: []const u8 = "",
    retry_shown: bool = false,
    retry_text: []const u8 = "",
    retry_percent: f32 = 0,
    hold_text: []const u8 = "",
    host_key_shown: bool = false,
    saved_key_title: []const u8 = "",
    saved_key: []const u8 = "",
    offered_key_title: []const u8 = "",
    offered_key: []const u8 = "",
    route: []const u8 = "",
    hops: []const HopRow = &.{},
    can_edit: bool = false,
    logs_label: []const u8 = "查看日志",
    logs_open: bool = false,
    has_logs: bool = false,
    log_lines: []const LogLine = &.{},
    stop_retry: bool = false,
    retry_now: bool = false,
    retry_disabled: bool = false,
    credentials: bool = false,
    disconnect: bool = false,
    trust_key: bool = false,
    primary: Primary = .retry_now,
};

pub fn kindOf(input: Input) Kind {
    if (input.host_key != null) return .host_key_changed;
    const err = input.failure orelse return .other;
    return switch (reconnect.FailureClass.of(err)) {
        .refused => .refused,
        .timeout => .timeout,
        .authentication => .authentication,
        .host_key_changed => .host_key_changed,
        .other => .other,
    };
}

/// The target of the failure: the failed hop, else the session target.
fn subjectIndex(input: Input) usize {
    if (input.failed_hop) |hop| if (hop < input.hops.len) return hop;
    return input.hops.len - 1;
}

pub fn formatEndpoint(buffer: []u8, user: []const u8, host: []const u8, port: u16) ![]const u8 {
    const ipv6 = std.mem.indexOfScalar(u8, host, ':') != null and !std.mem.startsWith(u8, host, "[");
    if (user.len == 0) return if (ipv6) std.fmt.bufPrint(buffer, "[{s}]:{d}", .{ host, port }) else std.fmt.bufPrint(buffer, "{s}:{d}", .{ host, port });
    return if (ipv6) std.fmt.bufPrint(buffer, "{s}@[{s}]:{d}", .{ user, host, port }) else std.fmt.bufPrint(buffer, "{s}@{s}:{d}", .{ user, host, port });
}

fn hostPort(a: std.mem.Allocator, hop: Hop) ![]const u8 {
    var buffer: [1100]u8 = undefined;
    return a.dupe(u8, try formatEndpoint(&buffer, "", hop.host, hop.port));
}

pub fn phaseName(phase: journal_mod.Phase) []const u8 {
    return switch (phase) {
        .transport => "TCP 连接",
        .tunnel => "隧道建立",
        .handshake => "SSH 握手",
        .host_key => "主机密钥核对",
        .authentication => "SSH 认证",
        .shell => "终端准备",
        .ready => "协议就绪",
    };
}

/// Seconds shown to people: never "0 秒" while still waiting.
fn ceilSeconds(ns: i128) i128 {
    if (ns <= 0) return 0;
    return @divFloor(ns + std.time.ns_per_s - 1, std.time.ns_per_s);
}

fn writeSeconds(writer: *std.Io.Writer, ns: i128) !void {
    const ms = @divFloor(ns, std.time.ns_per_ms);
    if (@mod(ms, 1000) == 0) return writer.print("{d}", .{@divFloor(ms, 1000)});
    try writer.print("{d}.{d}", .{ @divFloor(ms, 1000), @divFloor(@mod(ms, 1000), 100) });
}

/// Whether "重新输入凭据" can actually ask for a secret on the next attempt:
/// only the target's password, or a saved key passphrase it would skip.
pub fn canPromptCredentials(input: Input) bool {
    const index = subjectIndex(input);
    if (index + 1 != input.hops.len) return false;
    const hop = input.hops[index];
    return switch (hop.auth_mode) {
        .password => true,
        .private_key => hop.saved_passphrase,
        .agent => false,
    };
}

pub fn project(a: std.mem.Allocator, input: Input) !Projection {
    if (input.hops.len == 0) return .{};
    const kind = kindOf(input);
    const target = input.hops[input.hops.len - 1];
    const subject = input.hops[subjectIndex(input)];
    var p: Projection = .{ .shown = true, .kind = kind, .name = target.name, .can_edit = input.can_edit, .logs_open = input.logs_open, .has_logs = input.has_logs };
    var buffer: [1100]u8 = undefined;
    p.endpoint = try a.dupe(u8, try formatEndpoint(&buffer, target.user, target.host, target.port));
    const where = try hostPort(a, subject);
    switch (kind) {
        .refused => {
            p.icon = .refused;
            p.title = try std.fmt.allocPrint(a, "无法连接到 {s}", .{target.name});
            p.alert_title = try std.fmt.allocPrint(a, "{s} 拒绝连接", .{where});
            p.alert_detail = "目标端口没有 SSH 服务在监听，或被防火墙拒绝。请确认 sshd 已启动、端口无误。";
        },
        .timeout => {
            p.icon = .timeout;
            p.alert_warning = true;
            p.title = try std.fmt.allocPrint(a, "连接 {s} 超时", .{target.name});
            const transport = input.failure != null and input.failure.? == error.ConnectionTimedOut and (input.failed_phase == null or input.failed_phase.? == .transport);
            p.alert_title = if (transport and input.connect_timeout_sec != 0)
                try std.fmt.allocPrint(a, "{s} 在 {d} 秒内没有响应", .{ where, input.connect_timeout_sec })
            else
                try std.fmt.allocPrint(a, "{s} 没有及时响应", .{where});
            p.alert_detail = "主机可能未开机、网络不通，或在防火墙之后。经 VPN 访问时，请先确认 VPN 已连接。";
        },
        .authentication => {
            p.icon = .refused;
            p.title = try std.fmt.allocPrint(a, "{s} 拒绝了认证", .{subject.name});
            p.alert_title = try std.fmt.allocPrint(a, "服务器不接受 {s} 的认证信息", .{subject.user});
            const method = switch (subject.auth_mode) {
                .password => try a.dupe(u8, "密码（password）"),
                .private_key => if (subject.identity_file.len != 0) try std.fmt.allocPrint(a, "私钥 {s}（publickey）", .{subject.identity_file}) else try a.dupe(u8, "私钥（publickey）"),
                .agent => try a.dupe(u8, "SSH agent 中的密钥（publickey）"),
            };
            p.alert_detail = try std.fmt.allocPrint(a, "已尝试：{s}。认证信息不变时重试不会成功。", .{method});
            p.hold_text = "不自动重试：请先修改认证方式或重新输入凭据";
        },
        .host_key_changed => {
            p.icon = .shield;
            p.title = try std.fmt.allocPrint(a, "{s} 的主机密钥变了", .{subject.name});
            p.alert_title = "服务器提供的密钥与已保存的不一致";
            p.alert_detail = "可能是服务器重装或换了密钥，也可能是中间人攻击。确认来源前不要继续；不会自动重试。";
            if (input.host_key) |pair| {
                p.host_key_shown = true;
                p.saved_key_title = try std.fmt.allocPrint(a, "已保存的密钥 · {s}", .{pair.saved_algorithm});
                p.saved_key = try a.dupe(u8, pair.saved_fingerprint);
                p.offered_key_title = try std.fmt.allocPrint(a, "服务器当前提供的密钥 · {s}", .{pair.offered_algorithm});
                p.offered_key = try a.dupe(u8, pair.offered_fingerprint);
            }
        },
        .other => {
            p.icon = .failed;
            p.title = try std.fmt.allocPrint(a, "无法连接到 {s}", .{target.name});
            p.alert_title = if (input.failed_phase) |phase| try std.fmt.allocPrint(a, "{s} · {s}失败", .{ where, phaseName(phase) }) else try std.fmt.allocPrint(a, "{s} · 连接失败", .{where});
            p.alert_detail = try a.dupe(u8, input.reason);
        },
    }
    if (input.retry) |retry| {
        p.retry_shown = true;
        var text = std.Io.Writer.Allocating.init(a);
        try text.writer.print("自动重试 · 第 {d} 次 / 共 {d} 次 · ", .{ retry.next_attempt, retry.limit });
        const seconds = ceilSeconds(retry.remaining_ns);
        if (seconds == 0) try text.writer.writeAll("即将开始") else try text.writer.print("{d} 秒后开始", .{seconds});
        if (retry.delays_ns.len > 1) {
            try text.writer.writeAll(" · 间隔 ");
            for (retry.delays_ns, 0..) |delay, index| {
                if (index != 0) try text.writer.writeAll(" → ");
                try writeSeconds(&text.writer, delay);
            }
            try text.writer.writeAll(" 秒");
        }
        p.retry_text = text.written();
        const elapsed = retry.delay_ns - @max(0, retry.remaining_ns);
        p.retry_percent = if (retry.delay_ns <= 0) 100 else @floatCast(std.math.clamp(@as(f64, @floatFromInt(elapsed)) * 100 / @as(f64, @floatFromInt(retry.delay_ns)), 0, 100));
        p.badge = .warning;
        p.badge_text = if (seconds == 0) try a.dupe(u8, "即将重试") else try std.fmt.allocPrint(a, "{d} 秒后重试", .{seconds});
        p.stop_retry = true;
        p.retry_now = true;
        p.primary = .retry_now;
    } else if (kind == .host_key_changed and input.host_key != null) {
        p.badge_text = "需要确认";
        p.disconnect = true;
        p.trust_key = true;
        p.primary = .trust_key;
    } else {
        p.badge_text = "已停止重试";
        if (p.hold_text.len == 0) p.hold_text = "不再自动重试：可以立即重试，或先编辑主机";
        p.retry_now = true;
        p.retry_disabled = !input.can_retry or input.retry_requested;
        p.credentials = kind == .authentication and canPromptCredentials(input);
        p.primary = if (p.credentials) .credentials else .retry_now;
    }
    p.logs_label = if (input.logs_open) "收起日志" else "查看日志";
    p.route = if (input.hops.len == 1) "连接路径 · 直连" else try std.fmt.allocPrint(a, "连接路径 · {d} 级跳板", .{input.hops.len - 1});
    const rows = try a.alloc(HopRow, input.hops.len + 1);
    rows[0] = .{ .key = 0, .name = "本机", .address = if (input.local_name.len != 0) input.local_name else "连接起点", .status = "已就绪", .tone = .ok };
    const failed_index = subjectIndex(input);
    for (input.hops, 0..) |hop, index| {
        const last = index + 1 == input.hops.len;
        const address = if (last) try hostPort(a, hop) else try a.dupe(u8, try formatEndpoint(&buffer, hop.user, hop.host, hop.port));
        var status: []const u8 = "未连接";
        var tone: Tone = .muted;
        if (index == failed_index) {
            status = switch (kind) {
                .refused => "拒绝连接",
                .timeout => "超时",
                .authentication => "认证失败",
                .host_key_changed => if (input.host_key != null) "等待确认 · 密钥不符" else "已中止 · 密钥不符",
                .other => if (input.failed_phase) |phase| try std.fmt.allocPrint(a, "{s}失败", .{phaseName(phase)}) else "连接失败",
            };
            tone = if (kind == .timeout) .warning else .danger;
        } else if (index < failed_index and index < input.reached.len and input.reached[index]) {
            status = "已连通";
            tone = .ok;
        }
        var hash = std.hash.Wyhash.init(index + 1);
        for ([_][]const u8{ hop.name, address, status }) |part| hash.update(part);
        hash.update(&[_]u8{@intFromEnum(tone)});
        rows[index + 1] = .{ .key = hash.final(), .name = hop.name, .address = address, .status = status, .tone = tone };
    }
    p.hops = rows;
    return p;
}

const testing = std.testing;

fn testHops() [2]Hop {
    return .{
        .{ .name = "bastion-01", .host = "b1.example", .user = "admin" },
        .{ .name = "build-agent-mac", .host = "10.0.3.8", .user = "admin", .auth_mode = .private_key, .identity_file = "~/.ssh/id_ed25519" },
    };
}

test "failure view: refused with a pending retry shows the countdown and the real attempt counts" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const hops = [_]Hop{.{ .name = "staging-api", .host = "127.0.0.1", .user = "developer", .port = 65530 }};
    const delays = [_]i128{ 500 * std.time.ns_per_ms, 1000 * std.time.ns_per_ms };
    const p = try project(arena.allocator(), .{ .hops = &hops, .local_name = "spencer-mbp", .failure = error.ConnectionRefused, .failed_hop = 0, .failed_phase = .transport, .retry = .{ .next_attempt = 2, .limit = 3, .remaining_ns = 300 * std.time.ns_per_ms, .delay_ns = 500 * std.time.ns_per_ms, .delays_ns = &delays } });
    try testing.expectEqual(Kind.refused, p.kind);
    try testing.expectEqualStrings("无法连接到 staging-api", p.title);
    try testing.expectEqualStrings("127.0.0.1:65530 拒绝连接", p.alert_title);
    try testing.expectEqualStrings("developer@127.0.0.1:65530", p.endpoint);
    try testing.expect(p.retry_shown and p.stop_retry and p.retry_now and !p.credentials);
    try testing.expectEqualStrings("自动重试 · 第 2 次 / 共 3 次 · 1 秒后开始 · 间隔 0.5 → 1 秒", p.retry_text);
    try testing.expectApproxEqAbs(@as(f32, 40), p.retry_percent, 0.01);
    try testing.expectEqualStrings("1 秒后重试", p.badge_text);
    try testing.expectEqualStrings("拒绝连接", p.hops[1].status);
    try testing.expectEqualStrings("spencer-mbp", p.hops[0].address);
}

test "failure view: authentication never shows a retry row and offers credentials only when they can be asked" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var hops = testHops();
    var p = try project(a, .{ .hops = &hops, .failure = error.AuthenticationFailed, .failed_hop = 1, .failed_phase = .authentication, .reached = &.{ true, false }, .can_retry = true });
    try testing.expectEqual(Kind.authentication, p.kind);
    try testing.expect(!p.retry_shown and !p.stop_retry);
    try testing.expectEqualStrings("服务器不接受 admin 的认证信息", p.alert_title);
    try testing.expectEqualStrings("已尝试：私钥 ~/.ssh/id_ed25519（publickey）。认证信息不变时重试不会成功。", p.alert_detail);
    try testing.expect(!p.credentials);
    try testing.expectEqual(Primary.retry_now, p.primary);
    try testing.expectEqualStrings("已连通", p.hops[1].status);
    try testing.expectEqualStrings("认证失败", p.hops[2].status);
    hops[1].auth_mode = .password;
    p = try project(a, .{ .hops = &hops, .failure = error.AuthenticationFailed, .failed_hop = 1, .can_retry = true });
    try testing.expect(p.credentials);
    try testing.expectEqual(Primary.credentials, p.primary);
}

test "failure view: timeout names the configured connect timeout and the downstream hop stays unconnected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const hops = testHops();
    const p = try project(arena.allocator(), .{ .hops = &hops, .failure = error.ConnectionTimedOut, .failed_hop = 0, .failed_phase = .transport, .connect_timeout_sec = 15 });
    try testing.expectEqual(Kind.timeout, p.kind);
    try testing.expect(p.alert_warning);
    try testing.expectEqualStrings("b1.example:22 在 15 秒内没有响应", p.alert_title);
    try testing.expectEqualStrings("超时", p.hops[1].status);
    try testing.expectEqualStrings("未连接", p.hops[2].status);
    try testing.expectEqualStrings("连接路径 · 1 级跳板", p.route);
}

test "failure view: changed host key labels both fingerprints and offers trust or disconnect only" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const hops = [_]Hop{.{ .name = "prod-db-primary", .host = "10.0.2.15", .user = "root" }};
    const p = try project(arena.allocator(), .{ .hops = &hops, .failed_hop = 0, .host_key = .{ .saved_algorithm = "ssh-ed25519", .saved_fingerprint = "SHA256:old", .offered_algorithm = "ssh-ed25519", .offered_fingerprint = "SHA256:new" } });
    try testing.expectEqual(Kind.host_key_changed, p.kind);
    try testing.expectEqualStrings("已保存的密钥 · ssh-ed25519", p.saved_key_title);
    try testing.expectEqualStrings("服务器当前提供的密钥 · ssh-ed25519", p.offered_key_title);
    try testing.expect(p.trust_key and p.disconnect and !p.retry_now and !p.retry_shown);
    try testing.expectEqual(Primary.trust_key, p.primary);
    try testing.expectEqualStrings("需要确认", p.badge_text);
}

test "failure view: other failures reuse the existing reason text instead of inventing one" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const hops = [_]Hop{.{ .name = "h", .host = "h.example", .user = "u" }};
    const p = try project(arena.allocator(), .{ .hops = &hops, .failure = error.ConnectFailed, .reason = "无法建立 TCP 连接，请检查地址、端口与网络", .failed_hop = 0, .failed_phase = .transport });
    try testing.expectEqual(Kind.other, p.kind);
    try testing.expectEqualStrings("h.example:22 · TCP 连接失败", p.alert_title);
    try testing.expectEqualStrings("无法建立 TCP 连接，请检查地址、端口与网络", p.alert_detail);
    try testing.expectEqualStrings("TCP 连接失败", p.hops[1].status);
}
