//! 汉字的拼音首字母（搜索用，CONSISTENCY_AUDIT #5，用户拍板“搜索支持拼音首字母”）。
//!
//! 数据是仓库内的静态表 `pinyin_initials.dat`：CJK 统一表意文字基本区 U+4E00–U+9FFF，每个码点一个
//! 字节（小写首字母，无读音为 '-'）。表由 `tools/pinyin/gen_initials.py` 用 macOS 系统自带的
//! CFStringTransform（kCFStringTransformMandarinLatin + StripDiacritics）离线生成，没有第三方数据或依赖。
//! 运行时只做一次下标查表：无分配、无锁、线程安全、各平台一致。多音字取系统给出的默认读音。
const std = @import("std");

pub const first: u21 = 0x4E00;
pub const last: u21 = 0x9FFF;
const table = @embedFile("pinyin_initials.dat");

comptime {
    if (table.len != last - first + 1) @compileError("pinyin_initials.dat must hold one byte per code point U+4E00..U+9FFF");
}

/// 汉字的小写拼音首字母；不是表内汉字（或无读音）时返回 null。
pub fn initial(code_point: u21) ?u8 {
    if (code_point < first or code_point > last) return null;
    const letter = table[code_point - first];
    return if (letter >= 'a' and letter <= 'z') letter else null;
}

test "pinyin initials of common product words" {
    const words = [_]struct { []const u8, []const u8 }{
        .{ "生产数据库", "scsjk" },
        .{ "会话记录", "hhjl" },
        .{ "主机", "zj" },
        .{ "设置", "sz" },
        .{ "传输", "cs" },
        .{ "默认分组", "mrfz" },
    };
    for (words) |word| {
        var out: [16]u8 = undefined;
        var n: usize = 0;
        var it = (try std.unicode.Utf8View.init(word[0])).iterator();
        while (it.nextCodepoint()) |cp| {
            out[n] = initial(cp).?;
            n += 1;
        }
        try std.testing.expectEqualStrings(word[1], out[0..n]);
    }
    try std.testing.expectEqual(@as(?u8, null), initial('a'));
    try std.testing.expectEqual(@as(?u8, null), initial(0x3000));
    try std.testing.expectEqual(@as(?u8, null), initial(0xA000));
}
