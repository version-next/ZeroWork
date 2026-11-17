const std = @import("std");
const shared = @import("../shared/base/retry.zig");
/// AI 模型请求的重试退避（共享 `Backoff`，参数与改造前一致：3 次，1,2,4 s，超出表长沿用最后一项）。
pub const Policy = struct {
    max_attempts: u8 = 3,
    delays_ms: [3]u32 = .{ 1000, 2000, 4000 },
    pub fn backoff(self: *const Policy) shared.Backoff {
        return .{ .max_retries = self.max_attempts, .schedule = .{ .millis_repeat_last = &self.delays_ms } };
    }
    pub fn delay(self: Policy, attempt: u8) !u32 {
        return @intCast(self.backoff().delayMs(attempt) orelse return error.Exhausted);
    }
};

/// Configuration/authentication failures and cancellation cannot be repaired
/// by repeating the same request. Unknown transport failures retain the
/// existing bounded retry behavior.
pub fn isRetryable(err: anyerror) bool {
    return switch (err) {
        error.ContextFixedOverhead, error.SharedTaskTimeout, error.TaskAlreadyFinished, error.TaskPersistenceFailed => false,
        error.Cancelled, error.Timeout, error.ProviderFailure, error.MissingApiKey, error.ResponseTooLarge, error.RequestTooLarge, error.InsecureEndpoint, error.StreamCallbackFailed, error.MissingEndpoint, error.MissingModel, error.InvalidContextWindow, error.MissingAuthEnvironment, error.InvalidAuth, error.ProviderDisabled, error.MissingProviderConfiguration, error.ProviderMissingDone, error.OutOfMemory, error.UnsupportedToolProtocol, error.InvalidToolDefinition, error.InvalidToolCall, error.InvalidToolMessage, error.ToolRequestTooLarge, error.InvalidUtf8, error.UnsupportedEffort, error.ProviderProtocolMismatch, error.InvalidToolArguments => false,
        else => true,
    };
}

pub const Clock = struct {
    pub fn now(_: @This()) i128 {
        return @import("../platform/realtime.zig").monotonicNs();
    }
    pub fn sleep(_: @This(), ns: u64) void {
        const duration: std.c.timespec = .{ .sec = 0, .nsec = @intCast(ns) };
        // Recompute both deadlines and check Stop after every wake, including
        // interrupted sleeps. Requested sleep time is not elapsed time.
        _ = std.c.nanosleep(&duration, null);
    }
};

/// Short waits keep Stop/close cancellation responsive during rate limiting.
pub fn wait(delay_ms: u32, token: ?*@import("provider.zig").CancelToken) !void {
    return waitWithTiming(delay_ms, token, null, Clock{});
}

/// The optional request deadline is absolute and shared by all attempts.
/// Nanosecond precision also keeps Retry-After from rounding down a wait.
pub fn waitWithTiming(delay_ms: u32, token: ?*@import("provider.zig").CancelToken, deadline_ns: ?i128, timing: anytype) !void {
    return shared.wait(delay_ms, token, .{ .at_ns = deadline_ns }, timing);
}
test "provider retry policy backs off and exhausts" {
    const p: Policy = .{};
    try std.testing.expectEqual(@as(u32, 1000), try p.delay(0));
    try std.testing.expectError(error.Exhausted, p.delay(3));
}

test "cancelled rate limit wait never sleeps or retries" {
    var token: @import("provider.zig").CancelToken = .{};
    token.cancel();
    try std.testing.expectError(error.Cancelled, wait(60_000, &token));
    try std.testing.expect(!isRetryable(error.Cancelled));
    try std.testing.expect(!isRetryable(error.ProviderFailure));
    try std.testing.expect(isRetryable(error.RequestRejected));
}

test "invalid tool wire requests never retry an unchanged payload" {
    for ([_]anyerror{ error.UnsupportedToolProtocol, error.InvalidToolDefinition, error.InvalidToolCall, error.InvalidToolMessage, error.RequestTooLarge, error.ToolRequestTooLarge, error.InvalidUtf8, error.UnsupportedEffort, error.ProviderProtocolMismatch, error.InvalidToolArguments }) |err| {
        try std.testing.expect(!isRetryable(err));
    }
    try std.testing.expect(isRetryable(error.RequestRejected));
}

const TestTiming = struct {
    ns: i128 = 0,
    advance_ns: u64,
    sleeps: usize = 0,
    last_sleep_ns: u64 = 0,
    stop: ?*@import("provider.zig").CancelToken = null,
    pub fn now(self: *@This()) i128 {
        return self.ns;
    }
    pub fn sleep(self: *@This(), ns: u64) void {
        self.sleeps += 1;
        self.last_sleep_ns = ns;
        self.ns += self.advance_ns;
        if (self.stop) |token| token.cancel();
    }
};
test "retry deadline delayed wakes count elapsed time instead of requested sleeps" {
    var timing: TestTiming = .{ .advance_ns = 125 * std.time.ns_per_ms };
    try waitWithTiming(200, null, null, &timing);
    try std.testing.expectEqual(@as(usize, 2), timing.sleeps);
    try std.testing.expectEqual(@as(i128, 250 * std.time.ns_per_ms), timing.ns);
}
test "retry deadline early interrupted wakes cannot retry before Retry-After" {
    var timing: TestTiming = .{ .advance_ns = 10 * std.time.ns_per_ms };
    try waitWithTiming(100, null, null, &timing);
    try std.testing.expectEqual(@as(i128, 100 * std.time.ns_per_ms), timing.ns);
    try std.testing.expectEqual(@as(usize, 10), timing.sleeps);
}
test "retry deadline wait checks total budget after an overslept wake" {
    var timing: TestTiming = .{ .advance_ns = 125 * std.time.ns_per_ms };
    try std.testing.expectError(error.Timeout, waitWithTiming(60, null, 70 * std.time.ns_per_ms, &timing));
    try std.testing.expectEqual(@as(usize, 1), timing.sleeps);
}
test "retry deadline Stop interrupts a long wait at the first wake" {
    var token: @import("provider.zig").CancelToken = .{};
    var timing: TestTiming = .{ .advance_ns = 1, .stop = &token };
    try std.testing.expectError(error.Cancelled, waitWithTiming(60_000, &token, 120_000 * std.time.ns_per_ms, &timing));
    try std.testing.expectEqual(@as(usize, 1), timing.sleeps);
    try std.testing.expectEqual(@as(u64, 50 * std.time.ns_per_ms), timing.last_sleep_ns);
}
test "retry deadline zero waits and Stop retain deadline priority without sleeping" {
    var timing: TestTiming = .{ .advance_ns = 0 };
    try waitWithTiming(0, null, null, &timing);
    try std.testing.expectError(error.Timeout, waitWithTiming(0, null, 0, &timing));
    var token: @import("provider.zig").CancelToken = .{};
    token.cancel();
    try std.testing.expectError(error.Cancelled, waitWithTiming(0, &token, 0, &timing));
    try std.testing.expectEqual(@as(usize, 0), timing.sleeps);
}
test "retry deadline submillisecond remaining wait is not rounded down" {
    var timing: TestTiming = .{ .advance_ns = std.time.ns_per_ms - 1 };
    try waitWithTiming(1, null, null, &timing);
    try std.testing.expectEqual(@as(usize, 2), timing.sleeps);
    try std.testing.expectEqual(@as(u64, 1), timing.last_sleep_ns);
}

test "local task failures cannot be repaired by repeating model requests" {
    for ([_]anyerror{ error.SharedTaskTimeout, error.TaskAlreadyFinished, error.TaskPersistenceFailed }) |err| try std.testing.expect(!isRetryable(err));
}
