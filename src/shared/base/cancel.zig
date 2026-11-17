//! 取消令牌的唯一共享实现（persist-async，一致性审查 #11）。原先定义在 ai/provider.zig，
//! 那里保留 `provider.CancelToken` 作为别名，现有调用点不变。
//!
//! 令牌本身是一个原子标志加一个可选的外部来源（`source.poll`）；`isCancelled` 两者任一为真即取消。
//! SSH、BMC、本地执行等仍以裸 `*const std.atomic.Value(bool)` 跨插件接口传递取消（HostContext /
//! ProbeContext 的回调签名），改成令牌属于插件契约变更，未在本包内做。
const std = @import("std");

pub const CancelToken = struct {
    cancelled: std.atomic.Value(bool) = .init(false),
    /// Borrowed for this operation only. The source and its thread-safe poll
    /// must outlive every consumer, including child work through its join.
    source: ?struct {
        context: *const anyopaque,
        poll: *const fn (*const anyopaque) bool,
        /// Human decisions suspend the active-run budget, not Stop or scope checks.
        user_wait: ?*const fn (*const anyopaque, bool) void = null,
        /// Capacity waits pause this branch without reporting a human decision.
        resource_wait: ?*const fn (*const anyopaque, bool) void = null,
    } = null,
    pub const UserWait = struct {
        token: ?*const CancelToken,
        resource: bool = false,
        pub fn end(self: UserWait) void {
            if (self.token) |token| if (token.source) |source| {
                const callback = if (self.resource) source.resource_wait else source.user_wait;
                if (callback) |notify| notify(source.context, false);
            };
        }
    };
    /// Worker-owned guard. Always end it, including rejection and cancellation.
    pub fn beginUserWait(self: ?*const CancelToken) UserWait {
        if (self) |token| if (token.source) |source| if (source.user_wait) |notify| notify(source.context, true);
        return .{ .token = self };
    }
    pub fn beginResourceWait(self: ?*const CancelToken) UserWait {
        if (self) |token| if (token.source) |source| if (source.resource_wait) |notify| notify(source.context, true);
        return .{ .token = self, .resource = true };
    }
    pub fn cancel(self: *CancelToken) void {
        self.cancelled.store(true, .release);
    }
    pub fn isCancelled(self: *const CancelToken) bool {
        return self.cancelled.load(.acquire) or if (self.source) |source| source.poll(source.context) else false;
    }
};

test "cancel token observes its own flag and its source" {
    var token: CancelToken = .{};
    try std.testing.expect(!token.isCancelled());
    token.cancel();
    try std.testing.expect(token.isCancelled());
    const Source = struct {
        fn poll(context: *const anyopaque) bool {
            const flag: *const std.atomic.Value(bool) = @ptrCast(@alignCast(context));
            return flag.load(.acquire);
        }
    };
    var flag: std.atomic.Value(bool) = .init(false);
    const sourced: CancelToken = .{ .source = .{ .context = &flag, .poll = Source.poll } };
    try std.testing.expect(!sourced.isCancelled());
    flag.store(true, .release);
    try std.testing.expect(sourced.isCancelled());
}
