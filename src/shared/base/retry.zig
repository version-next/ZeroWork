//! 重试退避、超时截止与可取消等待的唯一共享实现（persist-async，一致性审查 #11）。
//!
//! 各处的重试只是不同参数（改造前的值，原样保留）：
//!
//! | 场景 | 次数 | 间隔 |
//! |---|---|---|
//! | SSH 首连自动重试 | 共 3 次（含首次） | 线性 0.5 s、1 s |
//! | SSH / SOCKS 断线重连 | `ssh.reconnect_max` 次（默认 5） | 秒表 `ssh.reconnect_backoff`（默认 1,2,4,8,16） |
//! | SFTP 传输打开 | 共 4 次（含首次） | 指数 1 s 起、封顶 8 s |
//! | AI 模型请求 | 3 次重试 | 1,2,4 s（超出表长时沿用最后一项）；服务端 Retry-After 优先 |
const std = @import("std");

/// SSH / SOCKS 断线重连的默认秒表（config.toml `ssh.reconnect_backoff` 的默认值）。
pub const ssh_reconnect_seconds = [5]u8{ 1, 2, 4, 8, 16 };
/// SSH 断线重连默认最多次数（`ssh.reconnect_max`）。
pub const ssh_reconnect_max: u8 = 5;
/// SSH 连接超时默认值（`ssh.connect_timeout_sec`）。
pub const ssh_connect_timeout_sec: u16 = 15;
pub const ssh_connect_timeout_ms: u32 = @as(u32, ssh_connect_timeout_sec) * std.time.ms_per_s;

/// 退避策略：第 `retry` 次重试（从 0 起）之前等待多久；用完返回 null。
pub const Backoff = struct {
    /// 允许的重试次数（不含首次尝试）。
    max_retries: u32,
    schedule: Schedule,

    pub const Schedule = union(enum) {
        /// 按表取值，单位秒；超出表长即用完。
        seconds: []const u8,
        /// 按表取值，单位毫秒；超出表长时沿用最后一项。
        millis_repeat_last: []const u32,
        /// `step_ms * (retry + 1)`。
        linear: struct { step_ms: u64 },
        /// `min(base_ms << retry, max_ms)`，移位封顶 63。
        exponential: struct { base_ms: u64, max_ms: u64 },
    };

    pub fn delayMs(self: Backoff, retry: u32) ?u64 {
        if (retry >= self.max_retries) return null;
        return switch (self.schedule) {
            .seconds => |table| if (retry < table.len) @as(u64, table[retry]) * std.time.ms_per_s else null,
            .millis_repeat_last => |table| if (table.len == 0) null else table[@min(retry, table.len - 1)],
            .linear => |value| value.step_ms *| (@as(u64, retry) + 1),
            .exponential => |value| @min(value.base_ms *| (@as(u64, 1) << @intCast(@min(retry, 63))), value.max_ms),
        };
    }

    /// 秒表退避的原始秒数（重连状态机与界面倒计时按秒展示）。
    pub fn delaySeconds(self: Backoff, retry: u32) ?u8 {
        if (retry >= self.max_retries) return null;
        return switch (self.schedule) {
            .seconds => |table| if (retry < table.len) table[retry] else null,
            else => unreachable,
        };
    }
};

/// 绝对截止时刻（单调时钟纳秒）。null = 不设截止。
pub const Deadline = struct {
    at_ns: ?i128 = null,

    pub const none: Deadline = .{};
    pub fn after(now_ns: i128, ms: u64) Deadline {
        return .{ .at_ns = now_ns + @as(i128, ms) * std.time.ns_per_ms };
    }
    pub fn afterSeconds(now_ns: i128, seconds: u64) Deadline {
        return .{ .at_ns = now_ns + @as(i128, seconds) * std.time.ns_per_s };
    }
    pub fn expired(self: Deadline, now_ns: i128) bool {
        return if (self.at_ns) |at| now_ns >= at else false;
    }
    /// 剩余纳秒（已过期为 0；无截止为 null）。
    pub fn remainingNs(self: Deadline, now_ns: i128) ?i128 {
        return if (self.at_ns) |at| @max(at - now_ns, 0) else null;
    }
    pub fn earliest(self: Deadline, other: Deadline) Deadline {
        const a = self.at_ns orelse return other;
        const b = other.at_ns orelse return self;
        return .{ .at_ns = @min(a, b) };
    }
};

/// 等待时每次最多睡这么久，保证取消在一个切片内生效。
pub const wait_slice_ns: u64 = 50 * std.time.ns_per_ms;

/// 可取消、受截止约束的等待。`token` 需有 `isCancelled()`；`timing` 需有 `now() i128` 与 `sleep(ns)`。
/// 每次醒来都重新计算（被打断的睡眠不等于真的过去了那么久）；取消优先于超时，超时优先于完成。
pub fn wait(delay_ms: u64, token: anytype, deadline: Deadline, timing: anytype) error{ Cancelled, Timeout }!void {
    const until = timing.now() + @as(i128, delay_ms) * std.time.ns_per_ms;
    while (true) {
        if (isCancelled(token)) return error.Cancelled;
        const now = timing.now();
        if (deadline.expired(now)) return error.Timeout;
        if (now >= until) return;
        var remaining = until - now;
        if (deadline.remainingNs(now)) |left| remaining = @min(remaining, left);
        timing.sleep(@intCast(@min(remaining, wait_slice_ns)));
    }
}

fn isCancelled(token: anytype) bool {
    return switch (@typeInfo(@TypeOf(token))) {
        .null => false,
        .optional => if (token) |value| value.isCancelled() else false,
        else => token.isCancelled(),
    };
}

/// HTTP `Retry-After` 的秒数形式（前后空白忽略）。不是十进制非负整数或超出 u64 时返回 null。
/// HTTP-date 形式不支持（与改造前一致）。
pub fn parseRetryAfterSeconds(value: []const u8) ?u64 {
    return std.fmt.parseInt(u64, std.mem.trim(u8, value, " \t"), 10) catch null;
}

test "backoff schedules" {
    const ssh: Backoff = .{ .max_retries = 5, .schedule = .{ .seconds = &ssh_reconnect_seconds } };
    for (ssh_reconnect_seconds, 0..) |seconds, retry| {
        try std.testing.expectEqual(@as(?u64, @as(u64, seconds) * 1000), ssh.delayMs(@intCast(retry)));
        try std.testing.expectEqual(@as(?u8, seconds), ssh.delaySeconds(@intCast(retry)));
    }
    try std.testing.expectEqual(@as(?u64, null), ssh.delayMs(5));
    const short: Backoff = .{ .max_retries = 9, .schedule = .{ .seconds = ssh_reconnect_seconds[0..2] } };
    try std.testing.expectEqual(@as(?u8, null), short.delaySeconds(2));
    const ai: Backoff = .{ .max_retries = 5, .schedule = .{ .millis_repeat_last = &.{ 1000, 2000, 4000 } } };
    try std.testing.expectEqual(@as(?u64, 4000), ai.delayMs(4));
    const linear: Backoff = .{ .max_retries = 2, .schedule = .{ .linear = .{ .step_ms = 500 } } };
    try std.testing.expectEqual(@as(?u64, 500), linear.delayMs(0));
    try std.testing.expectEqual(@as(?u64, 1000), linear.delayMs(1));
    try std.testing.expectEqual(@as(?u64, null), linear.delayMs(2));
    const exp: Backoff = .{ .max_retries = 300, .schedule = .{ .exponential = .{ .base_ms = 1, .max_ms = std.math.maxInt(u64) } } };
    try std.testing.expectEqual(@as(?u64, @as(u64, 1) << 63), exp.delayMs(250));
}

test "deadline and retry-after" {
    const d = Deadline.after(100, 1);
    try std.testing.expect(!d.expired(100) and d.expired(100 + std.time.ns_per_ms));
    try std.testing.expectEqual(@as(?i128, 0), d.remainingNs(10 * std.time.ns_per_ms));
    try std.testing.expectEqual(@as(?i128, null), Deadline.none.remainingNs(0));
    try std.testing.expectEqual(d.at_ns, Deadline.none.earliest(d).at_ns);
    try std.testing.expectEqual(@as(?u64, 5), parseRetryAfterSeconds(" 5\t"));
    try std.testing.expectEqual(@as(?u64, null), parseRetryAfterSeconds("Wed, 21 Oct 2015 07:28:00 GMT"));
    try std.testing.expectEqual(@as(?u64, null), parseRetryAfterSeconds("18446744073709551616"));
}
