const std = @import("std");

/// libssh2 error codes from the vendored include/libssh2.h.
pub fn fromCode(code: c_int) anyerror {
    return switch (code) {
        -43 => error.SshHandshakeReceiveFailed,
        -7, -3 => error.SshHandshakeSendFailed,
        -13 => error.SshHandshakeDisconnected,
        -2 => error.SshHandshakeBannerFailed,
        -5, -8, -17, -33, -51 => error.SshHandshakeNegotiationFailed,
        -9, -30 => error.SshHandshakeTimedOut,
        else => error.HandshakeFailed,
    };
}

// 用户文案在 shared/base/error_text.zig（唯一目录，copy-terms）；这里只做 libssh2 错误码 → 错误名的分类。

/// Server-provided text must not inject extra lines into the diagnostic log.
pub fn logMessage(buffer: []u8, message: []const u8) []const u8 {
    const len = @min(buffer.len, message.len);
    for (message[0..len], buffer[0..len]) |byte, *out| {
        out.* = if (byte < 0x20 or byte == 0x7f) ' ' else byte;
    }
    return buffer[0..len];
}

test "handshake diagnostics classify receive errors and preserve unknown fallback" {
    try std.testing.expectEqual(error.SshHandshakeReceiveFailed, fromCode(-43));
    try std.testing.expectEqual(error.HandshakeFailed, fromCode(-999));
    const catalog = @import("../../shared/base/error_text.zig");
    try std.testing.expect(catalog.describe(fromCode(-43)).?.in_log);
    try std.testing.expect(!catalog.describe(error.AuthenticationFailed).?.in_log);
    var buffer: [8]u8 = undefined;
    try std.testing.expectEqualStrings("bad  msg", logMessage(&buffer, "bad\r\nmsg extra"));
}
