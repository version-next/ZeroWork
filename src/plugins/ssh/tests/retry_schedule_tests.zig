//! SSH 首连自动重试参数基准（persist-async）。在引入共享 `Backoff` 之前写成并在旧代码上通过；
//! 首连与断线重连是两套参数（首连 3 次、0.5→1s；重连见 host/tests/retry_schedule_tests.zig），改造后保持不变。
const std = @import("std");
const ConnectJob = @import("../connect_job.zig").ConnectJob;

test "retry schedule: SSH initial connection retries three times at 0.5s then 1s" {
    try std.testing.expectEqual(@as(u8, 3), ConnectJob.automatic_attempt_limit);
    try std.testing.expectEqual(@as(u32, 500), ConnectJob.automaticRetryDelayMs(1));
    try std.testing.expectEqual(@as(u32, 1_000), ConnectJob.automaticRetryDelayMs(2));
}

test "retry schedule: SSH initial connection schedule is the shared linear backoff" {
    const backoff = ConnectJob.automatic_retry;
    try std.testing.expectEqual(@as(u32, ConnectJob.automatic_attempt_limit - 1), backoff.max_retries);
    for (1..ConnectJob.automatic_attempt_limit) |attempts| try std.testing.expectEqual(@as(?u64, ConnectJob.automaticRetryDelayMs(@intCast(attempts))), backoff.delayMs(@intCast(attempts - 1)));
    try std.testing.expectEqual(@as(?u64, null), backoff.delayMs(ConnectJob.automatic_attempt_limit - 1));
}
