//! 会话记录的展示文案（状态、不可回看原因、日期与时长），以原目录浮层的代码为准，列表行与
//! 详情头共用。纯函数，不依赖 UI。
const std = @import("std");
const archive_mod = @import("../../../vt/session_archive.zig");
const Descriptor = archive_mod.Descriptor;

/// 状态标签的色调（映射到原生 `W.Tag` 的 color）。
pub const Tone = enum { neutral, warning, danger };

pub fn stateTone(descriptor: Descriptor) Tone {
    if (notRecorded(descriptor)) return .neutral;
    if (!descriptor.can_open) return if (descriptor.replayability == .unsupported or descriptor.replayability == .baseline_unavailable) .warning else .danger;
    if (descriptor.coverage == .partial or descriptor.coverage == .gapped) return .warning;
    if (descriptor.coverage == .retained) return if (descriptor.replayability == .legacy_unverified) .neutral else .warning;
    return if (descriptor.entry.exit_code == null) .warning else if (descriptor.entry.exit_code.? == 0) .neutral else .danger;
}

pub fn stateLabel(descriptor: Descriptor) []const u8 {
    if (notRecorded(descriptor)) return "未录制";
    if (!descriptor.can_open) return if (descriptor.replayability == .unsupported) "版本不支持" else if (descriptor.replayability == .baseline_unavailable) "起始状态缺失" else "录制不可用";
    if (descriptor.coverage == .partial) return "部分记录";
    if (descriptor.coverage == .gapped) return "记录有缺口";
    if (descriptor.coverage == .retained) return if (descriptor.replayability == .legacy_unverified) "旧版记录" else "保留片段";
    return if (descriptor.entry.exit_code == null) "连接中断" else if (descriptor.entry.exit_code.? == 0) "正常结束" else "异常结束";
}

pub fn unavailableReason(descriptor: Descriptor) []const u8 {
    if (notRecorded(descriptor)) return "该会话未启用录制，没有可回看的内容";
    return switch (descriptor.replayability) {
        .unsupported => "录制版本不受支持，无法回看",
        .baseline_unavailable => "记录起始状态已淘汰，无法准确回放；可导出保留内容",
        else => descriptor.failure orelse "该会话的录制内容不可用",
    };
}

fn notRecorded(descriptor: Descriptor) bool {
    const reason = descriptor.failure orelse return false;
    return std.mem.eql(u8, reason, "RecordingDisabled") or std.mem.eql(u8, reason, "NotRecorded");
}

const Time = extern struct { sec: c_int, min: c_int, hour: c_int, day: c_int, month: c_int, year: c_int, week_day: c_int, year_day: c_int, daylight: c_int, offset: c_long, zone: ?[*:0]const u8 };
extern "c" fn localtime_r(*const c_long, *Time) ?*Time;
/// Real recording start in the system timezone, never a design fixture or raw epoch.
pub fn dateLabel(buffer: []u8, wall_ms: i64) []const u8 {
    const seconds: c_long = @intCast(@divFloor(wall_ms, 1000));
    var value: Time = undefined;
    if (localtime_r(&seconds, &value) == null) return "时间未知";
    if (value.year < -1900 or value.month < 0 or value.day < 1 or value.hour < 0 or value.min < 0) return "时间未知";
    return std.fmt.bufPrint(buffer, "{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}", .{ @as(u32, @intCast(value.year + 1900)), @as(u32, @intCast(value.month + 1)), @as(u32, @intCast(value.day)), @as(u32, @intCast(value.hour)), @as(u32, @intCast(value.min)) }) catch "时间未知";
}

test "record durations keep the catalogue wording (shared format .long)" {
    const shared_format = @import("../../../shared/base/format.zig");
    const durationLabel = struct {
        fn label(buffer: []u8, ms: u64) []const u8 {
            return shared_format.duration(buffer, ms, .long);
        }
    }.label;
    var buffer: [64]u8 = undefined;
    try std.testing.expectEqualStrings("2 分钟", durationLabel(&buffer, 125_000));
    try std.testing.expectEqualStrings("1 小时 5 分钟", durationLabel(&buffer, 65 * std.time.ms_per_min));
    try std.testing.expectEqualStrings("9 秒", durationLabel(&buffer, 9_500));
}
