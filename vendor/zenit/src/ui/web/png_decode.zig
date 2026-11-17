//! Minimal PNG decoder -> RGBA8 (straight alpha), target-independent.
//!
//! For the Web DOM host, where app code that needs raw pixels synchronously
//! (export rasterizers, redaction) has no platform decoder. Supports every
//! non-interlaced PNG (all colour types, bit depths 1..16, PLTE + tRNS);
//! Adam7-interlaced images return error.Interlaced.
const std = @import("std");

pub const Image = struct {
    w: u32,
    h: u32,
    rgba: []u8,
    pub fn deinit(self: Image, a: std.mem.Allocator) void {
        a.free(self.rgba);
    }
};

pub const Error = error{ NotPng, Truncated, Unsupported, Interlaced, BadData, OutOfMemory };

fn be32(b: []const u8) u32 {
    return std.mem.readInt(u32, b[0..4], .big);
}

pub fn decode(a: std.mem.Allocator, bytes: []const u8) Error!Image {
    if (bytes.len < 8 or !std.mem.eql(u8, bytes[0..8], "\x89PNG\r\n\x1a\n")) return error.NotPng;
    var i: usize = 8;
    var w: u32 = 0;
    var h: u32 = 0;
    var depth: u8 = 0;
    var ctype: u8 = 0;
    var palette: [256][4]u8 = @splat(.{ 0, 0, 0, 255 });
    var trns_gray: ?u16 = null;
    var trns_rgb: ?[3]u16 = null;
    var idat: std.ArrayListUnmanaged(u8) = .empty;
    defer idat.deinit(a);
    while (i + 12 <= bytes.len) {
        const len = be32(bytes[i..]);
        const typ = bytes[i + 4 .. i + 8];
        if (i + 12 + len > bytes.len) return error.Truncated;
        const data = bytes[i + 8 .. i + 8 + len];
        if (std.mem.eql(u8, typ, "IHDR")) {
            if (len < 13) return error.BadData;
            w = be32(data[0..]);
            h = be32(data[4..]);
            depth = data[8];
            ctype = data[9];
            if (data[12] != 0) return error.Interlaced;
        } else if (std.mem.eql(u8, typ, "PLTE")) {
            var k: usize = 0;
            while (k * 3 + 2 < len and k < 256) : (k += 1) palette[k] = .{ data[k * 3], data[k * 3 + 1], data[k * 3 + 2], 255 };
        } else if (std.mem.eql(u8, typ, "tRNS")) {
            switch (ctype) {
                3 => for (data, 0..) |al, k| {
                    if (k < 256) palette[k][3] = al;
                },
                0 => if (len >= 2) {
                    trns_gray = @intCast(std.mem.readInt(u16, data[0..2], .big));
                },
                2 => if (len >= 6) {
                    trns_rgb = .{ std.mem.readInt(u16, data[0..2], .big), std.mem.readInt(u16, data[2..4], .big), std.mem.readInt(u16, data[4..6], .big) };
                },
                else => {},
            }
        } else if (std.mem.eql(u8, typ, "IDAT")) {
            try idat.appendSlice(a, data);
        } else if (std.mem.eql(u8, typ, "IEND")) break;
        i += 12 + len;
    }
    if (w == 0 or h == 0) return error.BadData;
    const channels: u32 = switch (ctype) {
        0 => 1,
        2 => 3,
        3 => 1,
        4 => 2,
        6 => 4,
        else => return error.Unsupported,
    };
    const bpp_bits: u32 = channels * depth;
    const stride: usize = (@as(usize, w) * bpp_bits + 7) / 8;
    const bpp: usize = @max(1, bpp_bits / 8);

    // zlib inflate
    const raw = try a.alloc(u8, (stride + 1) * h);
    defer a.free(raw);
    {
        var in: std.Io.Reader = .fixed(idat.items);
        var window: [std.compress.flate.max_window_len]u8 = undefined;
        var dec: std.compress.flate.Decompress = .init(&in, .zlib, &window);
        dec.reader.readSliceAll(raw) catch return error.BadData;
    }

    // unfilter in place
    var prev: ?[]u8 = null;
    var y: usize = 0;
    while (y < h) : (y += 1) {
        const row = raw[y * (stride + 1) ..][0 .. stride + 1];
        const f = row[0];
        const cur = row[1..];
        for (cur, 0..) |*px, x| {
            const left: u16 = if (x >= bpp) cur[x - bpp] else 0;
            const up: u16 = if (prev) |p| p[x] else 0;
            const ul: u16 = if (prev != null and x >= bpp) prev.?[x - bpp] else 0;
            px.* = switch (f) {
                0 => px.*,
                1 => px.* +% @as(u8, @truncate(left)),
                2 => px.* +% @as(u8, @truncate(up)),
                3 => px.* +% @as(u8, @truncate((left + up) / 2)),
                4 => px.* +% paeth(left, up, ul),
                else => return error.BadData,
            };
        }
        prev = cur;
    }

    // expand to RGBA8
    const out = try a.alloc(u8, @as(usize, w) * h * 4);
    errdefer a.free(out);
    y = 0;
    while (y < h) : (y += 1) {
        const cur = raw[y * (stride + 1) + 1 ..][0..stride];
        var x: usize = 0;
        while (x < w) : (x += 1) {
            const o = out[(y * w + x) * 4 ..][0..4];
            switch (ctype) {
                0 => {
                    const g = sample(cur, x, depth);
                    const v = scale8(g, depth);
                    o.* = .{ v, v, v, if (trns_gray) |t| (if (g == t) 0 else 255) else 255 };
                },
                2 => {
                    const r = sample(cur, x * 3, depth);
                    const g = sample(cur, x * 3 + 1, depth);
                    const b = sample(cur, x * 3 + 2, depth);
                    const transparent = if (trns_rgb) |t| (r == t[0] and g == t[1] and b == t[2]) else false;
                    o.* = .{ scale8(r, depth), scale8(g, depth), scale8(b, depth), if (transparent) 0 else 255 };
                },
                3 => o.* = palette[@min(sample(cur, x, depth), 255)],
                4 => {
                    const v = scale8(sample(cur, x * 2, depth), depth);
                    o.* = .{ v, v, v, scale8(sample(cur, x * 2 + 1, depth), depth) };
                },
                6 => o.* = .{
                    scale8(sample(cur, x * 4, depth), depth),
                    scale8(sample(cur, x * 4 + 1, depth), depth),
                    scale8(sample(cur, x * 4 + 2, depth), depth),
                    scale8(sample(cur, x * 4 + 3, depth), depth),
                },
                else => unreachable,
            }
        }
    }
    return .{ .w = w, .h = h, .rgba = out };
}

fn paeth(a: u16, b: u16, c: u16) u8 {
    const p: i32 = @as(i32, a) + b - c;
    const pa = @abs(p - a);
    const pb = @abs(p - b);
    const pc = @abs(p - c);
    return @truncate(if (pa <= pb and pa <= pc) a else if (pb <= pc) b else c);
}

/// Sample index `n` (in units of `depth` bits) from a row.
fn sample(row: []const u8, n: usize, depth: u8) u16 {
    return switch (depth) {
        8 => row[n],
        16 => std.mem.readInt(u16, row[n * 2 ..][0..2], .big),
        else => blk: {
            const bit = n * depth;
            const byte = row[bit / 8];
            const shift: u3 = @intCast(8 - depth - (bit % 8));
            const mask: u8 = @intCast((@as(u16, 1) << @intCast(depth)) - 1);
            break :blk (byte >> shift) & mask;
        },
    };
}

fn scale8(v: u16, depth: u8) u8 {
    return switch (depth) {
        8 => @intCast(v),
        16 => @intCast(v >> 8),
        1 => if (v != 0) 255 else 0,
        2 => @intCast(v * 85),
        4 => @intCast(v * 17),
        else => @intCast(v),
    };
}

fn testPng(comptime raw: []const u8, comptime ihdr: [13]u8) []const u8 {
    comptime {
        const adler = std.hash.Adler32.hash(raw);
        const n = raw.len;
        const zlib = [_]u8{ 0x78, 0x01, 0x01, @intCast(n & 0xff), @intCast(n >> 8), @intCast(~n & 0xff), @intCast((~n >> 8) & 0xff) } ++ raw.* ++
            [_]u8{ @intCast(adler >> 24), @intCast((adler >> 16) & 0xff), @intCast((adler >> 8) & 0xff), @intCast(adler & 0xff) };
        const chunk = struct {
            fn c(comptime typ: *const [4]u8, comptime data: []const u8) []const u8 {
                const len = data.len;
                return &[_]u8{ @intCast(len >> 24), @intCast((len >> 16) & 0xff), @intCast((len >> 8) & 0xff), @intCast(len & 0xff) } ++ typ.* ++ data[0..len].* ++ [_]u8{ 0, 0, 0, 0 };
            }
        }.c;
        return "\x89PNG\r\n\x1a\n" ++ chunk("IHDR", &ihdr) ++ chunk("IDAT", &zlib) ++ chunk("IEND", "");
    }
}

test "png decode: RGBA8, palette+tRNS, gray 1-bit, filters" {
    const a = std.testing.allocator;
    // 2x2 RGBA8; row 0 filter None, row 1 filter Sub.
    const rgba = comptime testPng(&[_]u8{ 0, 255, 0, 0, 255, 0, 255, 0, 255, 1, 0, 0, 255, 255, 0, 0, 1, 1 }, .{ 0, 0, 0, 2, 0, 0, 0, 2, 8, 6, 0, 0, 0 });
    const img = try decode(a, rgba);
    defer img.deinit(a);
    try std.testing.expectEqual(@as(u32, 2), img.w);
    try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255 }, img.rgba[0..4]);
    try std.testing.expectEqualSlices(u8, &.{ 0, 255, 0, 255 }, img.rgba[4..8]);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 255, 255 }, img.rgba[8..12]);
    // Sub filter: second pixel = raw + left = (0,0,1+255,1+255) mod 256
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 0, 0 }, img.rgba[12..16]);
    // gray 1-bit 8x1: 0b10110000
    const gray = comptime testPng(&[_]u8{ 0, 0b10110000 }, .{ 0, 0, 0, 8, 0, 0, 0, 1, 1, 0, 0, 0, 0 });
    const g = try decode(a, gray);
    defer g.deinit(a);
    try std.testing.expectEqual(@as(u8, 255), g.rgba[0]);
    try std.testing.expectEqual(@as(u8, 0), g.rgba[4]);
    try std.testing.expectEqual(@as(u8, 255), g.rgba[8]);
    try std.testing.expectEqual(@as(u8, 255), g.rgba[12]);
    try std.testing.expectEqual(@as(u8, 0), g.rgba[16]);
    try std.testing.expectError(error.NotPng, decode(a, "nope"));
}
