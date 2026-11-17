//! 唯一的搜索匹配（CONSISTENCY_AUDIT #5）：会话记录、主机列表、快速连接、传输、文件、设置等的过滤都调这里。
//!
//! 规则：
//! - 查询先去掉首尾空白（含全角空格）；空查询匹配一切。
//! - 子串匹配，ASCII 大小写不敏感；非 ASCII 字节按原样比较（中文直接按子串命中）。
//! - 拼音首字母（用户拍板）：查询全是 ASCII 字母时，再用字段的“首字母串”比一次。首字母串把每个汉字换成
//!   拼音首字母、ASCII 字母和数字转成小写保留、其余字符（空白、标点）跳过：“生产 db-01” → “scdb01”，
//!   所以 “scdb”“sc” 都能命中。数据见 `pinyin.zig`（静态表，查表无分配）。
const std = @import("std");
const pinyin = @import("pinyin.zig");

/// 任一字段命中即为匹配。
pub fn matches(query: []const u8, fields: []const []const u8) bool {
    const needle = trim(query);
    if (needle.len == 0) return true;
    const initials_eligible = allAsciiLetters(needle);
    for (fields) |field| {
        if (containsFold(field, needle)) return true;
        if (initials_eligible and hasNonAscii(field) and initialsContain(field, needle)) return true;
    }
    return false;
}

/// 单字段的便捷写法。
pub fn matchesText(query: []const u8, text: []const u8) bool {
    return matches(query, &.{text});
}

/// 去掉首尾 ASCII 空白与全角空格（U+3000）。
pub fn trim(query: []const u8) []const u8 {
    var value = query;
    while (true) {
        const before = value.len;
        value = std.mem.trim(u8, value, " \t\r\n");
        if (std.mem.startsWith(u8, value, "\u{3000}")) value = value[3..];
        if (std.mem.endsWith(u8, value, "\u{3000}")) value = value[0 .. value.len - 3];
        if (value.len == before) return value;
    }
}

fn containsFold(haystack: []const u8, needle: []const u8) bool {
    return std.ascii.findIgnoreCase(haystack, needle) != null;
}

fn allAsciiLetters(text: []const u8) bool {
    for (text) |c| if (!std.ascii.isAlphabetic(c)) return false;
    return true;
}

fn hasNonAscii(text: []const u8) bool {
    for (text) |c| if (c >= 0x80) return true;
    return false;
}

/// 边生成首字母串边比较；超长字段分段处理，段间保留 `needle.len - 1` 个字符，跨段的命中不会漏。
fn initialsContain(field: []const u8, needle: []const u8) bool {
    var window: [256]u8 = undefined;
    if (needle.len > window.len / 2) return false;
    var len: usize = 0;
    var index: usize = 0;
    while (index < field.len) {
        const byte = field[index];
        var letter: ?u8 = null;
        if (byte < 0x80) {
            if (std.ascii.isAlphanumeric(byte)) letter = std.ascii.toLower(byte);
            index += 1;
        } else {
            const width = std.unicode.utf8ByteSequenceLength(byte) catch {
                index += 1;
                continue;
            };
            if (index + width > field.len) break;
            if (std.unicode.utf8Decode(field[index..][0..width])) |code_point| letter = pinyin.initial(code_point) else |_| {}
            index += width;
        }
        const value = letter orelse continue;
        if (len == window.len) {
            if (containsFold(window[0..len], needle)) return true;
            const keep = needle.len - 1;
            std.mem.copyForwards(u8, window[0..keep], window[len - keep .. len]);
            len = keep;
        }
        window[len] = value;
        len += 1;
    }
    return containsFold(window[0..len], needle);
}

test "case-insensitive substring over any field" {
    try std.testing.expect(matches("", &.{"anything"}));
    try std.testing.expect(matches("   ", &.{}));
    try std.testing.expect(matches("QA", &.{ "staging", "qa" }));
    try std.testing.expect(matches("10.0.0.4", &.{ "prod-db", "10.0.0.4" }));
    try std.testing.expect(!matches("prod", &.{ "staging", "qa" }));
    try std.testing.expect(!matches("x", &.{}));
}

test "query whitespace is trimmed (trailing space no longer hides results)" {
    try std.testing.expect(matchesText("prod ", "prod-db"));
    try std.testing.expect(matchesText("\tprod\n", "prod-db"));
    try std.testing.expect(matchesText("\u{3000}生产\u{3000}", "生产数据库"));
    try std.testing.expectEqualStrings("a b", trim("  a b \u{3000}"));
}

test "chinese substring and pinyin initials" {
    try std.testing.expect(matchesText("数据", "生产数据库"));
    try std.testing.expect(matchesText("scsjk", "生产数据库"));
    try std.testing.expect(matchesText("SJK", "生产数据库"));
    try std.testing.expect(matchesText("sj", "生产 数据库"));
    try std.testing.expect(matchesText("scdb", "生产 db-01"));
    try std.testing.expect(matchesText("mrfz", "默认分组"));
    try std.testing.expect(!matchesText("xyz", "生产数据库"));
    // 只有字母查询走首字母：数字或混合查询仍按普通子串。
    try std.testing.expect(!matchesText("sc1", "生产1"));
    try std.testing.expect(matchesText("产1", "生产1"));
    // 纯 ASCII 字段不走首字母（“sc” 不会因为别的规则命中 “staging”）。
    try std.testing.expect(!matchesText("sg", "staging"));
}

test "initials survive long fields, invalid UTF-8 and window boundaries" {
    var long: [3 * 300]u8 = undefined;
    for (0..300) |i| @memcpy(long[i * 3 ..][0..3], if (i == 299) "库" else "生");
    try std.testing.expect(matchesText("ssk", &long));
    try std.testing.expect(!matchesText("kk", &long));
    try std.testing.expect(matchesText("zj", "\xff主机"));
    try std.testing.expect(!matchesText("zj", "\xe4\xb8"));
}
