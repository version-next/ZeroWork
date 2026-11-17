//! 重试 / 超时参数基准（persist-async）。在引入共享 `Backoff` 之前写成并在旧代码上通过；
//! 改造后原样保留：每处的重试次数、间隔与超时都与改造前一致。
const std = @import("std");
const config = @import("../../config/config.zig");
const ssh_worker = @import("../../vt/ssh_worker.zig");
const reconnect = @import("../../vt/reconnect.zig");
const socks = @import("../socks_background_runtime.zig");
const transfer = @import("../../transfer/manager.zig");
const ai_retry = @import("../../ai/retry.zig");
const provider = @import("../../ai/provider.zig");
const provider_http = @import("../../ai/provider_http.zig");

test "retry schedule: SSH reconnect defaults are identical in config, worker and SOCKS background" {
    const expected = [5]u8{ 1, 2, 4, 8, 16 };
    const ssh: config.Ssh = .{};
    try std.testing.expectEqual(expected, ssh.reconnect_backoff);
    try std.testing.expectEqual(@as(u8, 5), ssh.reconnect_max);
    try std.testing.expectEqual(@as(u16, 15), ssh.connect_timeout_sec);
    const runtime: ssh_worker.RuntimeOptions = .{};
    try std.testing.expectEqual(expected, runtime.reconnect_backoff);
    try std.testing.expectEqual(@as(u8, 5), runtime.reconnect_max);
    try std.testing.expectEqual(@as(u32, 15_000), runtime.connect_timeout_ms);
    const policy: socks.Policy = .{};
    try std.testing.expectEqual(expected, policy.reconnect_backoff);
    try std.testing.expectEqual(@as(u8, 5), policy.reconnect_max);
    try std.testing.expectEqual(@as(u32, 15_000), policy.timeout_ms);
}

test "retry schedule: SSH reconnect machine follows the configured seconds and then dies" {
    const backoff = [5]u8{ 1, 2, 4, 8, 16 };
    var machine = try reconnect.Machine.init(5, &backoff);
    machine.suspect(null);
    for (backoff) |expected| try std.testing.expectEqual(expected, try machine.nextDelay());
    try std.testing.expectError(error.RetryExhausted, machine.nextDelay());
    try std.testing.expectEqual(reconnect.State.dead, machine.currentState());
    try std.testing.expectError(error.InvalidTransition, machine.nextDelay());
    const custom = [5]u8{ 2, 3, 5, 8, 13 };
    var limited = try reconnect.Machine.init(3, &custom);
    limited.suspect(null);
    for (custom[0..2]) |expected| {
        try std.testing.expectEqual(expected, try limited.nextDelay());
        limited.failed();
        try std.testing.expectEqual(reconnect.State.suspected, limited.currentState());
    }
    try std.testing.expectEqual(@as(u8, 5), try limited.nextDelay());
    limited.failed();
    try std.testing.expectEqual(reconnect.State.dead, limited.currentState());
    limited.connected();
    limited.suspect(0);
    try std.testing.expectEqual(@as(u8, 2), try limited.nextDelay());
    try std.testing.expectError(error.InvalidPolicy, reconnect.Machine.init(0, &custom));
    try std.testing.expectError(error.InvalidPolicy, reconnect.Machine.init(6, &custom));
}

test "retry schedule: automatic reconnect delay table" {
    const backoff = [_]u8{ 1, 2, 4, 8, 16 };
    for (0..5) |count| try std.testing.expectEqual(@as(?u8, backoff[count]), reconnect.automaticDelay(true, @intCast(count), 5, &backoff, error.ConnectionRefused));
    try std.testing.expectEqual(@as(?u8, null), reconnect.automaticDelay(true, 5, 5, &backoff, null));
    try std.testing.expectEqual(@as(?u8, null), reconnect.automaticDelay(true, 2, 2, &backoff, null));
    try std.testing.expectEqual(@as(?u8, null), reconnect.automaticDelay(true, 3, 9, backoff[0..3], null));
    try std.testing.expectEqual(@as(?u8, null), reconnect.automaticDelay(false, 0, 5, &backoff, null));
    try std.testing.expectEqual(@as(?u8, null), reconnect.automaticDelay(true, 0, 5, &backoff, error.AuthenticationFailed));
}

test "retry schedule: SFTP transfer exponential backoff" {
    const policy: transfer.RetryPolicy = .{};
    try std.testing.expectEqual(@as(u8, 4), policy.max_attempts);
    for ([_]u64{ 1_000, 2_000, 4_000 }, 1..) |expected, failed| try std.testing.expectEqual(@as(?u64, expected), policy.delay(@intCast(failed)));
    try std.testing.expectEqual(@as(?u64, null), policy.delay(4));
    try std.testing.expectEqual(@as(?u64, null), policy.delay(9));
    const capped: transfer.RetryPolicy = .{ .max_attempts = 7, .base_delay_ms = 500, .max_delay_ms = 3_000 };
    for ([_]u64{ 500, 1_000, 2_000, 3_000, 3_000, 3_000 }, 1..) |expected, failed| try std.testing.expectEqual(@as(?u64, expected), capped.delay(@intCast(failed)));
    try std.testing.expectEqual(@as(?u64, null), capped.delay(7));
    const huge: transfer.RetryPolicy = .{ .max_attempts = 255, .base_delay_ms = 1, .max_delay_ms = std.math.maxInt(u64) };
    try std.testing.expectEqual(@as(?u64, @as(u64, 1) << 63), huge.delay(200));
}

test "retry schedule: AI provider retries and request timeouts" {
    const policy: ai_retry.Policy = .{};
    try std.testing.expectEqual(@as(u8, 3), policy.max_attempts);
    for ([_]u32{ 1_000, 2_000, 4_000 }, 0..) |expected, attempt| try std.testing.expectEqual(expected, try policy.delay(@intCast(attempt)));
    try std.testing.expectError(error.Exhausted, policy.delay(3));
    const long: ai_retry.Policy = .{ .max_attempts = 5 };
    try std.testing.expectEqual(@as(u32, 4_000), try long.delay(4));
    const request: provider.ChatRequest = .{ .model = "m", .system = "", .messages = &.{} };
    try std.testing.expectEqual(@as(u32, 10 * 60_000), request.timeout_ms);
    try std.testing.expectEqual(@as(u32, 60_000), request.idle_timeout_ms);
    try std.testing.expectEqual(@as(?u32, null), request.run_timeout_ms);
    const plan: provider_http.RequestPlan = .{ .endpoint = "https://example.invalid", .auth_style = .none };
    try std.testing.expectEqual(@as(u32, 60_000), plan.timeout_ms);
}

test "retry schedule: AI Retry-After parsing" {
    try std.testing.expectEqual(@as(?u32, 1_000), provider_http.parseRetryAfter(" 1 "));
    try std.testing.expectEqual(@as(?u32, 0), provider_http.parseRetryAfter("0"));
    try std.testing.expectEqual(@as(?u32, null), provider_http.parseRetryAfter("invalid"));
    try std.testing.expectEqual(@as(?u32, null), provider_http.parseRetryAfter(""));
    try std.testing.expectEqual(@as(?u32, null), provider_http.parseRetryAfter("-1"));
    try std.testing.expectEqual(@as(?u32, null), provider_http.parseRetryAfter("4294967296"));
    try std.testing.expectEqual(@as(?u32, std.math.maxInt(u32)), provider_http.parseRetryAfter("4294967295"));
    try std.testing.expectEqual(@as(?u32, std.math.maxInt(u32)), provider_http.parseRetryAfter("4294968"));
    try std.testing.expectEqual(@as(?u32, 4_294_967_000), provider_http.parseRetryAfter("4294967"));
}

test "retry schedule: SOCKS background reconnect uses the same seconds table as SSH" {
    var policy: socks.Policy = .{};
    const backoff = policy.reconnectBackoff();
    for (policy.reconnect_backoff, 0..) |seconds, count| try std.testing.expectEqual(@as(?u8, seconds), backoff.delaySeconds(@intCast(count)));
    try std.testing.expectEqual(@as(?u8, null), backoff.delaySeconds(5));
    policy.reconnect_max = 2;
    try std.testing.expectEqual(@as(?u8, 2), policy.reconnectBackoff().delaySeconds(1));
    try std.testing.expectEqual(@as(?u8, null), policy.reconnectBackoff().delaySeconds(2));
}

test "retry schedule: BMC and AI share one Retry-After parser" {
    const shared = @import("../../shared/base/retry.zig");
    // BMC：头部存在但无效时按 0 处理，毫秒换算饱和（与改造前的内联解析一致）。
    for ([_]struct { text: []const u8, ms: u64 }{ .{ .text = "5", .ms = 5_000 }, .{ .text = "x", .ms = 0 }, .{ .text = "18446744073709551616", .ms = 0 }, .{ .text = "18446744073709552", .ms = std.math.maxInt(u64) } }) |case|
        try std.testing.expectEqual(case.ms, (shared.parseRetryAfterSeconds(case.text) orelse 0) *| 1000);
}
