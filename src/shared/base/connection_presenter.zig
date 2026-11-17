//! 连接状态与转发（SOCKS / 端口转发）状态 → 文案、图标、色调的唯一映射（CONSISTENCY_AUDIT #8，copy-terms）。
//!
//! - 页签圆点、页签图标、状态栏身份、会话卡片、组页签、转发 chip 与转发卡片都从这里取，不再各写一个 switch。
//! - 术语按 docs/ui-revamp/GLOSSARY.md：已连上的叫“已连接”（不写“在线”），失败一律显示危险色。
//! - 这里只给出色调（Tone）；具体颜色由 shared/ui/theme/status_tone.zig 按当前主题取。
//! - 连接中统一用警示色（黄色）：页签圆点与页签图标不再一黄一灰。
const std = @import("std");

pub const Tone = enum { ok, warn, danger, muted };

pub const Presentation = struct {
    tone: Tone,
    label: []const u8,
    /// lucide 图标名（`ui.icons.get(name)`）。
    icon: []const u8,
};

/// 会话（SSH、SFTP、图形会话、本地终端）的连接状态。
pub const Phase = enum {
    connected,
    connecting,
    reconnecting,
    authenticating,
    disconnecting,
    /// 仍连着但通道异常（图形会话的视频或管理通道降级）。
    degraded,
    /// 意外断开（网络、对端关闭）。
    disconnected,
    failed,
    /// 正常结束（用户关闭、进程退出、已取消）。
    ended,
    not_connected,
    unknown,
};

pub fn present(phase: Phase) Presentation {
    return switch (phase) {
        .connected => .{ .tone = .ok, .label = "已连接", .icon = "circle-check" },
        .connecting => .{ .tone = .warn, .label = "连接中", .icon = "loader-circle" },
        .reconnecting => .{ .tone = .warn, .label = "重连中", .icon = "refresh-cw" },
        .authenticating => .{ .tone = .warn, .label = "认证中", .icon = "key-round" },
        .disconnecting => .{ .tone = .warn, .label = "断开中", .icon = "loader-circle" },
        .degraded => .{ .tone = .danger, .label = "连接异常", .icon = "triangle-alert" },
        .disconnected => .{ .tone = .danger, .label = "已断开", .icon = "unplug" },
        .failed => .{ .tone = .danger, .label = "连接失败", .icon = "circle-alert" },
        .ended => .{ .tone = .muted, .label = "已结束", .icon = "circle-stop" },
        .not_connected => .{ .tone = .muted, .label = "未连接", .icon = "circle-dashed" },
        .unknown => .{ .tone = .muted, .label = "状态未知", .icon = "circle-help" },
    };
}

/// 转发（SOCKS5 动态转发、本地 L / 远端 R 固定转发、后台转发）的状态。
pub const ForwardPhase = enum {
    off,
    starting,
    running,
    /// 承载转发的会话断开，等待恢复。
    paused,
    stopping,
    failed,
    cleanup_unknown,
    stopped,
};

pub fn presentForward(phase: ForwardPhase) Presentation {
    return switch (phase) {
        .off => .{ .tone = .muted, .label = "未开启", .icon = "circle-dashed" },
        .starting => .{ .tone = .warn, .label = "启动中", .icon = "loader-circle" },
        .running => .{ .tone = .ok, .label = "监听中", .icon = "radio-tower" },
        .paused => .{ .tone = .warn, .label = "已暂停", .icon = "circle-pause" },
        .stopping => .{ .tone = .warn, .label = "停止中", .icon = "loader-circle" },
        .failed => .{ .tone = .danger, .label = "启动失败", .icon = "circle-alert" },
        .cleanup_unknown => .{ .tone = .danger, .label = "清理待确认", .icon = "circle-help" },
        .stopped => .{ .tone = .muted, .label = "已停止", .icon = "circle-stop" },
    };
}

test "connection presenter: connected reads 已连接, never 在线; failures are danger" {
    for (std.enums.values(Phase)) |phase| {
        const value = present(phase);
        try std.testing.expect(value.label.len != 0 and value.icon.len != 0);
        try std.testing.expect(std.mem.indexOf(u8, value.label, "在线") == null);
    }
    try std.testing.expectEqualStrings("已连接", present(.connected).label);
    try std.testing.expectEqual(Tone.danger, present(.failed).tone);
    try std.testing.expectEqual(Tone.danger, present(.disconnected).tone);
    try std.testing.expectEqual(Tone.warn, present(.connecting).tone);
}

test "forward presenter: one wording for chip, card and background forward" {
    for (std.enums.values(ForwardPhase)) |phase| try std.testing.expect(presentForward(phase).label.len != 0);
    try std.testing.expectEqualStrings("已暂停", presentForward(.paused).label);
    try std.testing.expectEqualStrings("启动中", presentForward(.starting).label);
    try std.testing.expectEqual(Tone.danger, presentForward(.failed).tone);
}
