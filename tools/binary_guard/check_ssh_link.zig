//! check-ssh-link：核对链接产物只用 vendor 自带的静态 libssh2 / Mbed TLS（REQUESTS #54）。
//!
//! 用法：check-ssh-link <binary>...
//!
//! libssh2 按 vendor/mbedtls（3.6.7）的头文件编译。若链接时经 pkg-config 拿到主机上的
//! Mbed TLS（例如 Homebrew 3.6.3 的 dylib），ABI 不一致，SSH KEX 会失败
//! （"Unable to exchange encryption keys"）。这里只读 Mach-O 加载命令，不执行被检查的二进制：
//! - 任何动态库依赖（LC_LOAD_DYLIB / LC_LOAD_WEAK_DYLIB / LC_REEXPORT_DYLIB / LC_LAZY_LOAD_DYLIB /
//!   LC_LOAD_UPWARD_DYLIB）的路径里出现 mbedtls / mbedcrypto / mbedx509 / libssh2 → 失败；
//! - 正向对照：二进制里必须能看到 Mbed TLS 符号与 libssh2 的协议横幅，证明它们确实被静态链接进来，
//!   检查不是因为没链 SSH 才“通过”。
const std = @import("std");

pub const forbidden_dylib = [_][]const u8{ "mbedtls", "mbedcrypto", "mbedx509", "libssh2" };
pub const required_bytes = [_][]const u8{ "_mbedtls_", "SSH-2.0-libssh2_" };

const LC_REQ_DYLD: u32 = 0x80000000;
const dylib_commands = [_]u32{
    0xc, // LC_LOAD_DYLIB
    0x18 | LC_REQ_DYLD, // LC_LOAD_WEAK_DYLIB
    0x1f | LC_REQ_DYLD, // LC_REEXPORT_DYLIB
    0x20, // LC_LAZY_LOAD_DYLIB
    0x23 | LC_REQ_DYLD, // LC_LOAD_UPWARD_DYLIB
};

pub const Finding = union(enum) {
    dynamic: []const u8,
    missing: []const u8,
    malformed: []const u8,
};

fn readInt(comptime T: type, bytes: []const u8, offset: usize, endian: std.builtin.Endian) ?T {
    if (offset > bytes.len or bytes.len - offset < @sizeOf(T)) return null;
    return std.mem.readInt(T, bytes[offset..][0..@sizeOf(T)], endian);
}

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len > haystack.len) return false;
    for (0..haystack.len - needle.len + 1) |start| {
        if (std.ascii.eqlIgnoreCase(haystack[start..][0..needle.len], needle)) return true;
    }
    return false;
}

/// Thin 64-bit Mach-O: first forbidden dylib dependency, or null.
fn scanThin(image: []const u8) ?Finding {
    const magic = readInt(u32, image, 0, .little) orelse return .{ .malformed = "truncated Mach-O header" };
    if (magic != 0xfeedfacf) return .{ .malformed = "not a 64-bit little-endian Mach-O image" };
    const ncmds = readInt(u32, image, 16, .little) orelse return .{ .malformed = "truncated header" };
    var offset: usize = 32;
    for (0..ncmds) |_| {
        const cmd = readInt(u32, image, offset, .little) orelse return .{ .malformed = "truncated load command" };
        const size = readInt(u32, image, offset + 4, .little) orelse return .{ .malformed = "truncated load command" };
        if (size < 8 or size > image.len - offset) return .{ .malformed = "load command size out of range" };
        if (std.mem.indexOfScalar(u32, &dylib_commands, cmd) != null) {
            const name_offset = readInt(u32, image, offset + 8, .little) orelse return .{ .malformed = "truncated dylib command" };
            if (name_offset >= size) return .{ .malformed = "dylib name offset out of range" };
            const raw = image[offset + name_offset .. offset + size];
            const name = raw[0 .. std.mem.indexOfScalar(u8, raw, 0) orelse raw.len];
            for (forbidden_dylib) |needle| if (containsIgnoreCase(name, needle)) return .{ .dynamic = name };
        }
        offset += size;
    }
    return null;
}

/// Thin or fat (universal) Mach-O. Returns the first finding, or null when the binary passes.
pub fn verify(bytes: []const u8) ?Finding {
    const magic = readInt(u32, bytes, 0, .big) orelse return .{ .malformed = "empty file" };
    if (magic == 0xcafebabe) {
        const count = readInt(u32, bytes, 4, .big).?;
        for (0..count) |index| {
            const entry = 8 + index * 20;
            const offset = readInt(u32, bytes, entry + 8, .big) orelse return .{ .malformed = "truncated fat header" };
            const size = readInt(u32, bytes, entry + 12, .big) orelse return .{ .malformed = "truncated fat header" };
            if (offset > bytes.len or size > bytes.len - offset) return .{ .malformed = "fat slice out of range" };
            if (scanThin(bytes[offset..][0..size])) |finding| return finding;
        }
    } else if (scanThin(bytes)) |finding| return finding;
    for (required_bytes) |needle| if (std.mem.indexOf(u8, bytes, needle) == null) return .{ .missing = needle };
    return null;
}

pub fn main(init: std.process.Init) !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const args = try init.minimal.args.toSlice(arena);
    const stderr = std.Io.File.stderr();
    if (args.len < 2) {
        try stderr.writeStreamingAll(init.io, "用法：check-ssh-link <binary>...\n");
        std.process.exit(2);
    }
    var aw: std.Io.Writer.Allocating = .init(arena);
    for (args[1..]) |path| {
        const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, path, arena, .limited(2 * 1024 * 1024 * 1024));
        if (verify(bytes)) |finding| {
            switch (finding) {
                .dynamic => |name| try aw.writer.print("check-ssh-link: 失败——{s} 动态加载了 {s}。libssh2 按 vendor 自带的 Mbed TLS 3.6.7 编译，只能静态链接 vendor/ 里的归档（build.zig linkVendorSsh），不得走 pkg-config 链接主机库\n", .{ path, name }),
                .missing => |needle| try aw.writer.print("check-ssh-link: 失败——{s} 里找不到 \"{s}\"；静态 libssh2 / Mbed TLS 没有链进来，检查失去对照\n", .{ path, needle }),
                .malformed => |why| try aw.writer.print("check-ssh-link: 失败——{s} 无法解析：{s}\n", .{ path, why }),
            }
            try stderr.writeStreamingAll(init.io, aw.written());
            std.process.exit(1);
        }
        try aw.writer.print("check-ssh-link: 通过（{s}：无 Mbed TLS / libssh2 动态依赖，静态 vendor 库在位）\n", .{path});
    }
    try std.Io.File.stdout().writeStreamingAll(init.io, aw.written());
}

/// Builds a minimal thin Mach-O image (header + LC_LOAD_DYLIB commands + trailing bytes); caller frees.
fn testImage(dylibs: []const []const u8, extra: []const u8) ![]u8 {
    const a = std.testing.allocator;
    var commands: std.ArrayList(u8) = .empty;
    defer commands.deinit(a);
    for (dylibs) |name| {
        const padded = (24 + name.len + 1 + 7) / 8 * 8;
        const command = try commands.addManyAsSlice(a, padded);
        @memset(command, 0);
        std.mem.writeInt(u32, command[0..4], 0xc, .little);
        std.mem.writeInt(u32, command[4..8], @intCast(padded), .little);
        std.mem.writeInt(u32, command[8..12], 24, .little);
        @memcpy(command[24..][0..name.len], name);
    }
    var header: [32]u8 = @splat(0);
    std.mem.writeInt(u32, header[0..4], 0xfeedfacf, .little);
    std.mem.writeInt(u32, header[16..20], @intCast(dylibs.len), .little);
    std.mem.writeInt(u32, header[20..24], @intCast(commands.items.len), .little);
    return std.mem.concat(a, u8, &.{ &header, commands.items, extra });
}

fn expectVerify(dylibs: []const []const u8, extra: []const u8) !?Finding {
    const image = try testImage(dylibs, extra);
    defer std.testing.allocator.free(image);
    const finding = verify(image) orelse return null;
    return switch (finding) {
        // Detach the borrowed dylib name from the freed image.
        .dynamic => .{ .dynamic = "dynamic" },
        else => finding,
    };
}

test "check-ssh-link rejects host Mbed TLS / libssh2 dylibs and accepts static vendor archives" {
    const linked = "_mbedtls_sha256 SSH-2.0-libssh2_1.11.1";
    try std.testing.expect(try expectVerify(&.{ "/usr/lib/libSystem.B.dylib", "/usr/lib/libz.1.dylib" }, linked) == null);
    try std.testing.expect((try expectVerify(&.{ "/usr/lib/libSystem.B.dylib", "/opt/homebrew/opt/mbedtls/lib/libmbedcrypto.16.dylib" }, linked)).? == .dynamic);
    try std.testing.expect((try expectVerify(&.{"/opt/homebrew/lib/libssh2.1.dylib"}, linked)).? == .dynamic);
    try std.testing.expect((try expectVerify(&.{"@rpath/libMbedX509.7.dylib"}, linked)).? == .dynamic);
}

test "check-ssh-link positive control: static libraries must be present" {
    try std.testing.expectEqualStrings("_mbedtls_", (try expectVerify(&.{"/usr/lib/libSystem.B.dylib"}, "SSH-2.0-libssh2_1.11.1")).?.missing);
    try std.testing.expectEqualStrings("SSH-2.0-libssh2_", (try expectVerify(&.{}, "_mbedtls_sha256")).?.missing);
    try std.testing.expect(verify("not a binary at all").? == .malformed);
}
