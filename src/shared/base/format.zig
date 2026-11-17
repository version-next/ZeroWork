//! 唯一的用户可见数值格式化：字节、速率、时长、相对时间、计数（CONSISTENCY_AUDIT #6）。
//!
//! 用户拍板（2026-11-14）：字节单位用 1024 进制、IEC 写法 B / KiB / MiB / GiB / TiB（速率 KiB/s、MiB/s），
//! 保留一位小数、整数值不带 “.0”；面板计数统一写 “N 条”。
//! 纯函数、不分配、不失败：结果写进调用方的缓冲（`max_len` 字节足够任何输入），缓冲不够时返回 `fallback`。
//! 各功能不得再自写字节单位换算、“分钟前” 之类的私有实现，一律调这里。
const std = @import("std");

/// 任何输入的最长输出（含负号、20 位整数、单位与 “/s”）。
pub const max_len = 48;
pub const Buffer = [max_len]u8;
/// 缓冲不够时的占位。
pub const fallback = "—";
/// 速率未知（尚未开始测速、排队中）时的占位，与真实速率同形。
pub const rate_placeholder = "— MiB/s";

const units = [_][]const u8{ "B", "KiB", "MiB", "GiB", "TiB", "PiB", "EiB" };
const step: u128 = 1024;

fn wide(value: anytype) i128 {
    return switch (@typeInfo(@TypeOf(value))) {
        .comptime_int => value,
        .int => @intCast(value),
        else => @compileError("format: integer expected, got " ++ @typeName(@TypeOf(value))),
    };
}

/// 字节数：`< 1024` 写整数 “1023 B”；否则按 1024 进制换算到 KiB…EiB，保留一位小数并四舍五入，
/// 整数值不带 “.0”（“1 KiB”、“1.5 MiB”、“64 KiB”）。
/// 进位：舍入后达到 1024.0 的值进到下一个单位（1023.95 KiB → “1 MiB”，不会出现 “1024 KiB”）。
/// 负数（差值）带 “-”；u64 上限写作 “16 EiB”。
pub fn bytes(buffer: []u8, value: anytype) []const u8 {
    return scaled(buffer, wide(value), "");
}

/// 传输速率（字节每秒），单位同 `bytes`，后缀 “/s”：“0 B/s”、“820 KiB/s”、“12.4 MiB/s”。
pub fn rate(buffer: []u8, bytes_per_second: anytype) []const u8 {
    return scaled(buffer, wide(bytes_per_second), "/s");
}

/// 进行中任务的实时速率：0 表示还没测出速度（刚开始、排队、暂停），显示 `rate_placeholder`；
/// 状态栏、传输面板、传输管理统一用它，同一个速度在各处写法一致。
pub fn liveRate(buffer: []u8, bytes_per_second: anytype) []const u8 {
    return if (wide(bytes_per_second) == 0) rate_placeholder else rate(buffer, bytes_per_second);
}

/// 固定上限（编译期常量字节数）的界面文案：与 `bytes` 同一写法，结果是编译期字符串，可用 `++` 拼进字面量。
/// 标签由真实字节数算出，不手写单位（1 048 576 B → “1 MiB”，65 536 B → “64 KiB”）。
/// `inline` with a comptime result: `"…" ++ comptimeBytes(n) ++ "…"` is folded at compile time into static
/// read-only text (a runtime call would make `++` build the array in a stack temporary).
pub inline fn comptimeBytes(comptime value: anytype) *const [comptimeBytesLen(value):0]u8 {
    return comptime &ComptimeLabel(value).text;
}
fn ComptimeLabel(comptime value: anytype) type {
    return struct {
        const text: [comptimeBytesLen(value):0]u8 = blk: {
            var buffer: Buffer = undefined;
            const rendered = bytes(&buffer, value);
            var out: [rendered.len:0]u8 = undefined;
            @memcpy(out[0..rendered.len], rendered);
            break :blk out;
        };
    };
}
fn comptimeBytesLen(comptime value: anytype) usize {
    var buffer: Buffer = undefined;
    return comptime bytes(&buffer, value).len;
}

/// `bytes` 的分配版本（调用方释放）。
pub fn allocBytes(allocator: std.mem.Allocator, value: anytype) ![]u8 {
    var buffer: Buffer = undefined;
    return allocator.dupe(u8, bytes(&buffer, value));
}

fn scaled(buffer: []u8, value: i128, suffix: []const u8) []const u8 {
    const negative = value < 0;
    const magnitude: u128 = @intCast(if (negative) -value else value);
    const sign: []const u8 = if (negative) "-" else "";
    if (magnitude < step) return std.fmt.bufPrint(buffer, "{s}{d} B{s}", .{ sign, magnitude, suffix }) catch fallback;
    var unit: usize = 1;
    var scale: u128 = step;
    var tenths = roundedTenths(magnitude, scale);
    while (tenths >= step * 10 and unit + 1 < units.len) {
        unit += 1;
        scale *= step;
        tenths = roundedTenths(magnitude, scale);
    }
    // 整数值不带 “.0”：“64 KiB”，不是 “64.0 KiB”。
    if (tenths % 10 == 0) return std.fmt.bufPrint(buffer, "{s}{d} {s}{s}", .{ sign, tenths / 10, units[unit], suffix }) catch fallback;
    return std.fmt.bufPrint(buffer, "{s}{d}.{d} {s}{s}", .{ sign, tenths / 10, tenths % 10, units[unit], suffix }) catch fallback;
}

fn roundedTenths(magnitude: u128, scale: u128) u128 {
    return (magnitude * 10 + scale / 2) / scale;
}

pub const DurationStyle = enum {
    /// 计时与诊断：“850 ms”、“1.2 s”、“58 s”（整数秒不带小数）、“1 分 05 秒”、“2 小时 03 分”。
    short,
    /// 记录时长：“9 秒”、“2 分钟”、“1 小时 5 分钟”（不足一分钟的部分不写）。
    long,
};

/// 时长（毫秒）。负数按 0 处理；两种写法的单位用词一致（秒、分钟、小时）。
pub fn duration(buffer: []u8, milliseconds: anytype, style: DurationStyle) []const u8 {
    const raw = wide(milliseconds);
    const ms: u128 = if (raw < 0) 0 else @intCast(raw);
    switch (style) {
        .short => {
            if (ms < 1000) return std.fmt.bufPrint(buffer, "{d} ms", .{ms}) catch fallback;
            const tenths = (ms + 50) / 100;
            if (tenths < 600) {
                // 整数秒不带小数：“58 s”，不是“58.0 s”。
                if (tenths % 10 == 0) return std.fmt.bufPrint(buffer, "{d} s", .{tenths / 10}) catch fallback;
                return std.fmt.bufPrint(buffer, "{d}.{d} s", .{ tenths / 10, tenths % 10 }) catch fallback;
            }
            const seconds = (ms + 500) / 1000;
            if (seconds < 3600) return std.fmt.bufPrint(buffer, "{d} 分 {d:0>2} 秒", .{ seconds / 60, seconds % 60 }) catch fallback;
            const minutes = seconds / 60;
            return std.fmt.bufPrint(buffer, "{d} 小时 {d:0>2} 分", .{ minutes / 60, minutes % 60 }) catch fallback;
        },
        .long => {
            const minutes = ms / std.time.ms_per_min;
            if (minutes >= 60) return std.fmt.bufPrint(buffer, "{d} 小时 {d} 分钟", .{ minutes / 60, minutes % 60 }) catch fallback;
            if (minutes > 0) return std.fmt.bufPrint(buffer, "{d} 分钟", .{minutes}) catch fallback;
            return std.fmt.bufPrint(buffer, "{d} 秒", .{ms / 1000}) catch fallback;
        },
    }
}

/// 相对时间：“刚刚”（不足 1 分钟，或 `then` 在未来）、“N 分钟前”、“N 小时前”、“N 天前”。
pub fn relative(buffer: []u8, now_ms: anytype, then_ms: anytype) []const u8 {
    const elapsed = wide(now_ms) - wide(then_ms);
    if (elapsed < std.time.ms_per_min) return "刚刚";
    const minutes: u128 = @intCast(@divFloor(elapsed, std.time.ms_per_min));
    if (minutes < 60) return std.fmt.bufPrint(buffer, "{d} 分钟前", .{minutes}) catch "刚刚";
    if (minutes < 60 * 24) return std.fmt.bufPrint(buffer, "{d} 小时前", .{minutes / 60}) catch "刚刚";
    return std.fmt.bufPrint(buffer, "{d} 天前", .{minutes / (60 * 24)}) catch "刚刚";
}

/// 面板与列表计数（用户拍板：统一写 “N 条”）。负数按 0。
pub fn count(buffer: []u8, n: anytype) []const u8 {
    const raw = wide(n);
    return std.fmt.bufPrint(buffer, "{d} 条", .{if (raw < 0) 0 else raw}) catch fallback;
}

/// 面板头部副标题：“N 条”，有上下文（会话名等）时“N 条 · 上下文”；放不下上下文时只写“N 条”。
pub fn countWith(buffer: []u8, n: anytype, context: []const u8) []const u8 {
    if (context.len == 0) return count(buffer, n);
    const raw = wide(n);
    return std.fmt.bufPrint(buffer, "{d} 条 · {s}", .{ if (raw < 0) 0 else raw, context }) catch count(buffer, n);
}

const expectEqualStrings = std.testing.expectEqualStrings;

test "countWith: N 条 and N 条 · context" {
    var b: [64]u8 = undefined;
    try expectEqualStrings("0 条", countWith(&b, 0, ""));
    try expectEqualStrings("12 条 · Audit SSH", countWith(&b, 12, "Audit SSH"));
    var tiny: [8]u8 = undefined;
    try expectEqualStrings("3 条", countWith(&tiny, 3, "a long session name"));
}

test "bytes: zero, the 1024 boundary and IEC units" {
    var b: Buffer = undefined;
    try expectEqualStrings("0 B", bytes(&b, 0));
    try expectEqualStrings("1 B", bytes(&b, 1));
    try expectEqualStrings("999 B", bytes(&b, 999));
    try expectEqualStrings("1000 B", bytes(&b, 1000));
    try expectEqualStrings("1023 B", bytes(&b, 1023));
    try expectEqualStrings("1 KiB", bytes(&b, 1024));
    try expectEqualStrings("1.5 KiB", bytes(&b, 1536));
    try expectEqualStrings("64 KiB", bytes(&b, 64 * 1024));
    try expectEqualStrings("64.3 KiB", bytes(&b, 65_829));
    try expectEqualStrings("1 MiB", bytes(&b, 1024 * 1024));
    try expectEqualStrings("1.5 MiB", bytes(&b, 1024 * 1024 * 3 / 2));
    try expectEqualStrings("2 MiB", bytes(&b, 2 * 1024 * 1024));
    try expectEqualStrings("1 GiB", bytes(&b, 1024 * 1024 * 1024));
    try expectEqualStrings("1 TiB", bytes(&b, 1024 * 1024 * 1024 * 1024));
    // 1000 进制的整数在 1024 进制下带小数。
    try expectEqualStrings("976.6 KiB", bytes(&b, 1_000_000));
    try expectEqualStrings("953.7 MiB", bytes(&b, 1_000_000_000));
}

test "comptimeBytes derives fixed-limit labels from the real byte counts" {
    try expectEqualStrings("1 MiB", comptimeBytes(1024 * 1024));
    try expectEqualStrings("64 KiB", comptimeBytes(64 * 1024));
    try expectEqualStrings("2 MiB", comptimeBytes(2 * 1024 * 1024));
    try expectEqualStrings("128 MiB", comptimeBytes(128 * 1024 * 1024));
    try expectEqualStrings("256 MiB", comptimeBytes(256 * 1024 * 1024));
    try expectEqualStrings("1023 B", comptimeBytes(1023));
    // Concatenated labels are static text: a slice kept past the expression stays valid.
    const kept: []const u8 = switch (@as(u8, 1)) {
        1 => "粘贴超过 " ++ comptimeBytes(1024 * 1024) ++ " 限制",
        else => "",
    };
    var clobber: [256]u8 = @splat(0);
    std.mem.doNotOptimizeAway(&clobber);
    try expectEqualStrings("粘贴超过 1 MiB 限制", kept);
}

test "bytes: rounding to one decimal and carry into the next unit at 1024" {
    var b: Buffer = undefined;
    // 1.05 KiB = 1075.2 B：1075 B 舍到 1.0（写 “1 KiB”），1076 B 舍到 1.1。
    try expectEqualStrings("1 KiB", bytes(&b, 1075));
    try expectEqualStrings("1.1 KiB", bytes(&b, 1076));
    try expectEqualStrings("1023.5 KiB", bytes(&b, 1023 * 1024 + 512));
    // 1023.95 KiB = 1 048 524.8 B：低于它停在 “1023.9 KiB”，达到它舍入成 1024.0 → 进位成 “1 MiB”，不出现 “1024 KiB”。
    try expectEqualStrings("1023.9 KiB", bytes(&b, 1_048_524));
    try expectEqualStrings("1 MiB", bytes(&b, 1_048_525));
    try expectEqualStrings("1 MiB", bytes(&b, 1024 * 1024 - 1));
    try expectEqualStrings("1 GiB", bytes(&b, 1024 * 1024 * 1024 - 1));
    try expectEqualStrings("1023.9 MiB", bytes(&b, 1023 * 1024 * 1024 + 1024 * 1024 * 9 / 10));
}

test "bytes: negatives and extreme values" {
    var b: Buffer = undefined;
    try expectEqualStrings("-1 B", bytes(&b, @as(i64, -1)));
    try expectEqualStrings("-1023 B", bytes(&b, @as(i64, -1023)));
    try expectEqualStrings("-1 KiB", bytes(&b, @as(i64, -1024)));
    try expectEqualStrings("-1.5 KiB", bytes(&b, @as(i64, -1536)));
    try expectEqualStrings("-1 MiB", bytes(&b, @as(i64, -1_048_525)));
    try expectEqualStrings("-8 EiB", bytes(&b, @as(i64, std.math.minInt(i64))));
    try expectEqualStrings("8 EiB", bytes(&b, @as(i64, std.math.maxInt(i64))));
    try expectEqualStrings("16 EiB", bytes(&b, @as(u64, std.math.maxInt(u64))));
    try expectEqualStrings("15.9 EiB", bytes(&b, @as(u64, std.math.maxInt(u64)) - (1 << 56)));
    // 缓冲不够：返回占位，不崩溃。
    var tiny: [3]u8 = undefined;
    try expectEqualStrings(fallback, bytes(&tiny, 1_500_000));
    const owned = try allocBytes(std.testing.allocator, 2 * 1024 * 1024);
    defer std.testing.allocator.free(owned);
    try expectEqualStrings("2 MiB", owned);
}

test "rate: same units as bytes with /s; zero is a real zero" {
    var b: Buffer = undefined;
    try expectEqualStrings("0 B/s", rate(&b, 0));
    try expectEqualStrings("1023 B/s", rate(&b, 1023));
    try expectEqualStrings("1 KiB/s", rate(&b, 1024));
    try expectEqualStrings("820 KiB/s", rate(&b, 820 * 1024));
    try expectEqualStrings("1 MiB/s", rate(&b, 1_048_525));
    try expectEqualStrings("12.4 MiB/s", rate(&b, 13_002_342));
    try expectEqualStrings("2 GiB/s", rate(&b, @as(u64, 2 * 1024 * 1024 * 1024)));
    try expectEqualStrings("16 EiB/s", rate(&b, @as(u64, std.math.maxInt(u64))));
    try expectEqualStrings("-1 KiB/s", rate(&b, @as(i64, -1024)));
    try expectEqualStrings("— MiB/s", rate_placeholder);
    try expectEqualStrings(rate_placeholder, liveRate(&b, 0));
    try expectEqualStrings("8 KiB/s", liveRate(&b, 8192));
    try expectEqualStrings("1.5 MiB/s", liveRate(&b, 1024 * 1024 * 3 / 2));
}

test "duration short: ms, seconds with one decimal, carry at 60 s and 1 h" {
    var b: Buffer = undefined;
    try expectEqualStrings("0 ms", duration(&b, 0, .short));
    try expectEqualStrings("999 ms", duration(&b, 999, .short));
    try expectEqualStrings("1 s", duration(&b, 1000, .short));
    try expectEqualStrings("1.2 s", duration(&b, 1234, .short));
    try expectEqualStrings("1 s", duration(&b, 1049, .short));
    try expectEqualStrings("1.1 s", duration(&b, 1050, .short));
    try expectEqualStrings("59.9 s", duration(&b, 59_949, .short));
    // 59.95 s 舍入到 60.0 → 进位到分钟写法。
    try expectEqualStrings("1 分 00 秒", duration(&b, 59_950, .short));
    try expectEqualStrings("1 分 05 秒", duration(&b, 65_000, .short));
    try expectEqualStrings("59 分 59 秒", duration(&b, 3_599_499, .short));
    try expectEqualStrings("1 小时 00 分", duration(&b, 3_599_500, .short));
    try expectEqualStrings("2 小时 03 分", duration(&b, (2 * 60 + 3) * std.time.ms_per_min, .short));
    try expectEqualStrings("0 ms", duration(&b, @as(i64, -5), .short));
    try expectEqualStrings("5124095576030 小时 25 分", duration(&b, @as(u64, std.math.maxInt(u64)), .short));
}

test "duration long keeps the record-length wording" {
    var b: Buffer = undefined;
    try expectEqualStrings("0 秒", duration(&b, 0, .long));
    try expectEqualStrings("9 秒", duration(&b, 9_500, .long));
    try expectEqualStrings("59 秒", duration(&b, 59_999, .long));
    try expectEqualStrings("1 分钟", duration(&b, 60_000, .long));
    try expectEqualStrings("2 分钟", duration(&b, 125_000, .long));
    try expectEqualStrings("1 小时 5 分钟", duration(&b, 65 * std.time.ms_per_min, .long));
    try expectEqualStrings("0 秒", duration(&b, @as(i64, -60_000), .long));
}

test "relative: buckets including days; future and huge values" {
    var b: Buffer = undefined;
    try expectEqualStrings("刚刚", relative(&b, 0, 0));
    try expectEqualStrings("刚刚", relative(&b, 59_999, 0));
    try expectEqualStrings("1 分钟前", relative(&b, 60_000, 0));
    try expectEqualStrings("5 分钟前", relative(&b, 5 * 60_000, 0));
    try expectEqualStrings("59 分钟前", relative(&b, 60 * 60_000 - 1, 0));
    try expectEqualStrings("2 小时前", relative(&b, 125 * 60_000, 0));
    try expectEqualStrings("23 小时前", relative(&b, 24 * 60 * 60_000 - 1, 0));
    // 审查 #6：通知里曾出现 “30 小时前”，现在统一进到 “天前”。
    try expectEqualStrings("1 天前", relative(&b, 30 * 60 * 60_000, 0));
    try expectEqualStrings("刚刚", relative(&b, 0, 5 * 60_000));
    try expectEqualStrings("刚刚", relative(&b, @as(i64, -10), @as(u64, std.math.maxInt(u64))));
    try expectEqualStrings("213503982334 天前", relative(&b, @as(u64, std.math.maxInt(u64)), 0));
}

test "count writes N 条" {
    var b: Buffer = undefined;
    try expectEqualStrings("0 条", count(&b, 0));
    try expectEqualStrings("1000 条", count(&b, 1000));
    try expectEqualStrings("0 条", count(&b, @as(i32, -3)));
    try expectEqualStrings("18446744073709551615 条", count(&b, @as(u64, std.math.maxInt(u64))));
}
