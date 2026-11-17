//! 生命周期预算的计数与上限（docs/ui-revamp/LIFECYCLE.md §6）。
//!
//! 计数只是整数自增，生产构建里也在（没有分支、没有分配）；读它们的诊断接口 `POST /zerowork/lifecycle`
//! 只在 test-mode 构建里存在（`multiwindow_test_routes.zig`），e2e `lifecycle_budget_native.ts` 用它断言。
const std = @import("std");
const surface_migration = @import("surface_migration.zig");

/// 自进程启动以来“重的事情”各做了几次。
pub const Counters = struct {
    /// AI 对话整段重建（`AiHost.rebuildConversation`）。
    conversation_rebuilds: u64 = 0,
    /// 分屏整体重新呈现（`Workspace.presentGroup`）。
    group_presentations: u64 = 0,
    /// AI 内容视图按需挂载 / 释放的次数（`AiHost.mountContent` / `unmountContent`），以及最近一次挂载
    /// （建节点、Scope，不含随后那一帧的对话重建与布局）用掉的纳秒数。
    content_mounts: u64 = 0,
    content_unmounts: u64 = 0,
    last_content_mount_ns: u64 = 0,
    /// AI 宿主帧 hook（`AiHost.PollHook`，LIFECYCLE.md §5）：运行次数、其中跑了宿主轮（整串步骤）的帧数与
    /// 布局轮数、各门打开的次数（下标 = `frame_gate.Reason`），以及没有宿主轮的帧里执行的逐帧步骤数。
    ai_hook_runs: u64 = 0,
    ai_passes: u64 = 0,
    ai_pass_rounds: u64 = 0,
    ai_pass_reasons: [ai_pass_reason_names.len]u64 = @splat(0),
    ai_frame_steps: u64 = 0,
    /// 上面两类 hook 运行各自累计用掉的纳秒数（跑宿主轮的布局轮 / 只做逐帧工作的帧）。拆分前每次运行都是一轮。
    ai_pass_ns: u64 = 0,
    ai_idle_ns: u64 = 0,
};
/// 宿主轮的触发原因（与 `features/ai/host/frame_gate.zig` 的 `Reason` 一一对应，那里在编译期核对）。
pub const ai_pass_reason_names = [_][]const u8{ "first", "rerun", "publication", "environment", "config", "theme", "deadline", "card", "layout", "focus", "window" };
pub var counters: Counters = .{};

/// 静止判定（e2e 的“静止窗口”从这里开始，而不是固定等一段时间）：每个会在帧 hook 里跑整轮工作的宿主登记一个
/// 探针，回答它的下一帧会不会跑一轮（`due`：有待处理的发布 / 环境变化 / 重跑请求、外框在飞……，值是原因名）
/// 以及还挂着多久以后的截止时刻（`deadline_in_ns`）。只在 UI 线程上登记、注销、查询；诊断接口
/// `POST /zerowork/lifecycle` 逐个报告。
pub const RestState = struct {
    due: ?[]const u8 = null,
    deadline_in_ns: ?i128 = null,
};
pub const RestProbe = struct {
    context: *anyopaque,
    state: *const fn (*anyopaque) RestState,
};
var rest_probes: std.ArrayList(RestProbe) = .empty;
pub fn addRestProbe(probe: RestProbe) !void {
    try rest_probes.append(std.heap.c_allocator, probe);
}
pub fn removeRestProbe(context: *anyopaque) void {
    for (rest_probes.items, 0..) |probe, index| if (probe.context == context) {
        _ = rest_probes.swapRemove(index);
        return;
    };
}
pub fn restProbes() []const RestProbe {
    return rest_probes.items;
}

pub fn noteContentMount(elapsed_ns: i128) void {
    counters.content_mounts += 1;
    counters.last_content_mount_ns = @intCast(@max(0, elapsed_ns));
}
pub fn surfaceMoves() u64 {
    return surface_migration.moves;
}
pub fn surfaceParks() u64 {
    return surface_migration.parks;
}

/// 一个窗口各状态下的上限（节点数 / after-layout hook 数 / Scope 数）。数字来自整改后的实测值加余量
/// （LIFECYCLE.md §6 的表），超出即回归。
pub const Budget = struct { nodes: usize, after_layout_hooks: usize, scopes: usize };
pub const Budgets = struct {
    /// 主窗口壳 + 一个本地终端标签页，AI 关闭。
    shell_one_terminal: Budget,
    /// 同上，AI 面板打开（欢迎页）。
    ai_open_welcome: Budget,
    /// 同上，AI 停靠进分屏。
    ai_docked: Budget,
};

test "lifecycle budget rest probes: registered probes answer for themselves until removed" {
    const Probe = struct {
        due: ?[]const u8 = null,
        fn state(raw: *anyopaque) RestState {
            const self: *@This() = @ptrCast(@alignCast(raw));
            return .{ .due = self.due };
        }
    };
    var a: Probe = .{};
    var b: Probe = .{ .due = "publication" };
    const before = restProbes().len;
    try addRestProbe(.{ .context = &a, .state = Probe.state });
    try addRestProbe(.{ .context = &b, .state = Probe.state });
    try std.testing.expectEqual(before + 2, restProbes().len);
    var busy: usize = 0;
    for (restProbes()) |probe| {
        if (probe.state(probe.context).due != null) busy += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), busy);
    removeRestProbe(&b);
    removeRestProbe(&a);
    try std.testing.expectEqual(before, restProbes().len);
    // Removing a probe that is not registered is a no-op.
    removeRestProbe(&a);
    try std.testing.expectEqual(before, restProbes().len);
}
