//! Text script detection / ASCII classification: pure functions decoupled from encoder state.
//!
//! This cluster **sees bytes only, not the encoder**: params are `[]const u8` + scalars, returns
//! bool/f32, no self, no allocation, no side effects. Common question: 'which writing system is
//! this text / can we take the fixed-width ASCII fast path', used by the encoder's font fallback
//! selection (selectCjkFallbackFont) and fixed-width advance (fixedMonospaceAdvance).
//!
//! Division with font_selector.zig: that picks the **font tier** (returns a Font handle); this only
//! does **script detection** (pure predicate). font_selector's own isAllAscii is an inline hot-path
//! private copy; the two are deliberately independent.
//!
//! command_encoder.zig re-exports the same names.

const std = @import("std");

/// entire segment is ASCII (no 0x80+ bytes). Precondition for fixed-width fast path.
pub fn isAllAscii(content: []const u8) bool {
    for (content) |b| {
        if (b >= 0x80) return false;
    }
    return true;
}

/// fixed advance per ASCII char on an explicit cell grid; return 0 if inapplicable.
///
/// Monospace long-line path measurement, scroll, hit, selection all use same fixed ASCII cell,
/// rendering must use same width or accumulate glyph-advance drift under large horizontal offset.
/// A positive `monospace_char_width` is itself the opt-in: terminals and editors that configure
/// their own face through `font_family` get the same grid as the global monospace face. The
/// default cell width is 0, so ordinary text never takes this path.
pub fn fixedMonospaceAdvance(content: []const u8, use_monospace_font: bool, monospace_char_width: f32) f32 {
    _ = use_monospace_font;
    if (!(monospace_char_width > 0)) return 0;
    return if (isAllAscii(content)) monospace_char_width else 0;
}

test "fixed ASCII grid applies to any explicitly configured cell width" {
    try std.testing.expectEqual(@as(f32, 0), fixedMonospaceAdvance("abc", false, 0));
    try std.testing.expectEqual(@as(f32, 0), fixedMonospaceAdvance("abc", true, 0));
    try std.testing.expectEqual(@as(f32, 0), fixedMonospaceAdvance("abc", false, std.math.nan(f32)));
    try std.testing.expectEqual(@as(f32, 8.25), fixedMonospaceAdvance("abc", true, 8.25));
    try std.testing.expectEqual(@as(f32, 8.25), fixedMonospaceAdvance("abc", false, 8.25));
    try std.testing.expectEqual(@as(f32, 0), fixedMonospaceAdvance("a\u{4E16}", false, 8.25));
}

/// Korean preferred fallback: contains Hangul and no Han/Kana.
///
/// Mixed (Korean + Han/Kanji) doesn't take Korean tier, Korean font Han glyphs differ from
/// Han/Kanji typography.
pub fn preferKoreanFallback(text: []const u8) bool {
    return containsHangul(text) and !containsHanOrKana(text);
}

/// CJK fallback: contains Han or Kana.
pub fn preferCjkFallback(text: []const u8) bool {
    return containsHanOrKana(text);
}

/// Per-codepoint scan common skeleton: invalid UTF-8 bytes skip not error (render path can't fail
/// on one bad byte), truncated tail sequence stops immediately.
fn anyCodepoint(text: []const u8, comptime pred: fn (u21) bool) bool {
    var i: usize = 0;
    while (i < text.len) {
        if (text[i] < 0x80) {
            if (pred(text[i])) return true;
            i += 1;
            continue;
        }
        const seq_len = std.unicode.utf8ByteSequenceLength(text[i]) catch {
            i += 1;
            continue;
        };
        if (i + seq_len > text.len) break;
        const cp = std.unicode.utf8Decode(text[i .. i + seq_len]) catch {
            i += seq_len;
            continue;
        };
        if (pred(cp)) return true;
        i += seq_len;
    }
    return false;
}

fn isHangulCodepoint(cp: u21) bool {
    return (cp >= 0x1100 and cp <= 0x11FF) or // Hangul Jamo
        (cp >= 0x3130 and cp <= 0x318F) or // Hangul Compatibility Jamo
        (cp >= 0xAC00 and cp <= 0xD7AF); // Hangul Syllables
}

fn isHanOrKanaCodepoint(cp: u21) bool {
    return (cp >= 0x3000 and cp <= 0x303F) or // CJK Symbols and Punctuation
        (cp >= 0x3040 and cp <= 0x309F) or // Hiragana
        (cp >= 0x30A0 and cp <= 0x30FF) or // Katakana
        (cp >= 0x3400 and cp <= 0x4DBF) or // CJK Ext A
        (cp >= 0x4E00 and cp <= 0x9FFF) or // CJK Unified Ideographs
        (cp >= 0xF900 and cp <= 0xFAFF); // CJK Compatibility Ideographs
}

pub fn containsHangul(text: []const u8) bool {
    return anyCodepoint(text, isHangulCodepoint);
}

pub fn containsHanOrKana(text: []const u8) bool {
    return anyCodepoint(text, isHanOrKanaCodepoint);
}

/// Han/Kana always wins over Hangul. Checking it first avoids walking a
/// whole CJK suffix just to prove it contains no Hangul before finding Han.
pub fn preferredFallback(text: []const u8) enum { none, korean, cjk } {
    if (containsHanOrKana(text)) return .cjk;
    if (containsHangul(text)) return .korean;
    return .none;
}

test "preferred fallback preserves legacy script priority for every partial stream" {
    const samples = [_][]const u8{
        "plain ASCII and 123",
        "한국어 English",
        "中文 suffix 한국어",
        "한국어 prefix 日本語",
        "한글\xff\xed\xa0\x80かな",
        "\xf0\x9f\x91\xa9\xe2\x80\x8d\xf0\x9f\x92\xbb English",
        "\xe4\xb8\xff\xe3\x81\x82",
        "\xe1\x84\x80\xe3\x80\x80",
        "\xc0\xaf\xf5\x80\x80\x80",
    };
    for (samples) |text| {
        for (0..text.len + 1) |end| {
            for (0..end + 1) |start| {
                const part = text[start..end];
                const old: @TypeOf(preferredFallback(part)) = if (preferKoreanFallback(part)) .korean else if (preferCjkFallback(part)) .cjk else .none;
                try std.testing.expectEqual(old, preferredFallback(part));
            }
        }
    }
    var suffix: [16384]u8 = @splat('x');
    @memcpy(suffix[0..3], "中");
    try std.testing.expectEqual(.cjk, preferredFallback(&suffix));
    @memcpy(suffix[0..3], "한");
    try std.testing.expectEqual(.korean, preferredFallback(&suffix));
    @memcpy(suffix[suffix.len - 3 ..], "日");
    try std.testing.expectEqual(.cjk, preferredFallback(&suffix));
}
