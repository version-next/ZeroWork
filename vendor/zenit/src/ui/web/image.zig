//! Image header parsing (dimensions only) for the Web DOM host: pixels are
//! decoded asynchronously by the browser, but app code usually needs width/
//! height synchronously (layout, aspect ratio). Target-independent.
const std = @import("std");

fn be16(b: []const u8, i: usize) u32 {
    return (@as(u32, b[i]) << 8) | b[i + 1];
}
fn be32(b: []const u8, i: usize) u32 {
    return (@as(u32, b[i]) << 24) | (@as(u32, b[i + 1]) << 16) | (@as(u32, b[i + 2]) << 8) | b[i + 3];
}
fn le16(b: []const u8, i: usize) u32 {
    return @as(u32, b[i]) | (@as(u32, b[i + 1]) << 8);
}
fn le24(b: []const u8, i: usize) u32 {
    return @as(u32, b[i]) | (@as(u32, b[i + 1]) << 8) | (@as(u32, b[i + 2]) << 16);
}

/// PNG, JPEG, GIF, WebP (VP8/VP8L/VP8X), BMP. null = unknown / truncated.
pub fn imageSize(b: []const u8) ?[2]u32 {
    if (b.len >= 24 and std.mem.eql(u8, b[0..8], "\x89PNG\r\n\x1a\n")) return .{ be32(b, 16), be32(b, 20) };
    if (b.len >= 10 and (std.mem.eql(u8, b[0..6], "GIF87a") or std.mem.eql(u8, b[0..6], "GIF89a"))) return .{ le16(b, 6), le16(b, 8) };
    if (b.len >= 26 and b[0] == 'B' and b[1] == 'M') {
        const w = std.mem.readInt(i32, b[18..22], .little);
        const h = std.mem.readInt(i32, b[22..26], .little);
        return .{ @abs(w), @abs(h) };
    }
    if (b.len >= 30 and std.mem.eql(u8, b[0..4], "RIFF") and std.mem.eql(u8, b[8..12], "WEBP")) {
        const chunk = b[12..16];
        if (std.mem.eql(u8, chunk, "VP8X")) return .{ le24(b, 24) + 1, le24(b, 27) + 1 };
        if (std.mem.eql(u8, chunk, "VP8 ")) return .{ le16(b, 26) & 0x3fff, le16(b, 28) & 0x3fff };
        if (std.mem.eql(u8, chunk, "VP8L") and b.len >= 25) {
            const v = @as(u32, b[21]) | (@as(u32, b[22]) << 8) | (@as(u32, b[23]) << 16) | (@as(u32, b[24]) << 24);
            return .{ (v & 0x3fff) + 1, ((v >> 14) & 0x3fff) + 1 };
        }
        return null;
    }
    if (b.len >= 4 and b[0] == 0xFF and b[1] == 0xD8) {
        var i: usize = 2;
        while (i + 9 < b.len) {
            if (b[i] != 0xFF) {
                i += 1;
                continue;
            }
            const m = b[i + 1];
            if (m == 0xD8 or m == 0x01 or (m >= 0xD0 and m <= 0xD7) or m == 0xFF) {
                i += if (m == 0xFF) 1 else 2;
                continue;
            }
            const len = be16(b, i + 2);
            // SOF0..SOF15 except DHT(C4), JPG(C8), DAC(CC)
            if (m >= 0xC0 and m <= 0xCF and m != 0xC4 and m != 0xC8 and m != 0xCC) return .{ be16(b, i + 7), be16(b, i + 5) };
            i += 2 + len;
        }
        return null;
    }
    return null;
}

test "web image: header sizes" {
    const png = "\x89PNG\r\n\x1a\n\x00\x00\x00\x0dIHDR\x00\x00\x01\x2c\x00\x00\x00\xc8\x08\x06\x00\x00\x00";
    try std.testing.expectEqual([2]u32{ 300, 200 }, imageSize(png).?);
    const gif = "GIF89a\x0a\x00\x14\x00";
    try std.testing.expectEqual([2]u32{ 10, 20 }, imageSize(gif).?);
    const jpg = "\xff\xd8\xff\xe0\x00\x04ab\xff\xc0\x00\x11\x08\x00\x30\x00\x40\x03\x01\x22\x00";
    try std.testing.expectEqual([2]u32{ 64, 48 }, imageSize(jpg).?);
    try std.testing.expect(imageSize("nope") == null);
}
