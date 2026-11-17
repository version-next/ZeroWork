//! Browser I/O for the Web DOM host: monotonic clocks map to performance.now,
//! the real clock to Date.now, randomness to crypto.getRandomValues, and the
//! filesystem to an in-memory tree (`vfs.zig`) that the JS runtime loads from
//! and persists to IndexedDB (`zw_vfs_*` exports, see `exportVfs`), and
//! stdout/stderr (std.debug.print, std.log) to console.log. Everything else
//! (threads, processes, sockets) fails explicitly, as in wasm_io.
//!
//! The VFS needs real descriptors, so it is only active on wasm32-wasi (the
//! Web DOM host target; WASI is never imported). On wasm32-freestanding
//! `std.Io.File.Handle` is `void` and the filesystem keeps failing.
const std = @import("std");
const vfs = @import("vfs.zig");
extern "zenit" fn now_ns() u64;
extern "zenit" fn real_ns() u64;
extern "zenit" fn random_bytes(ptr: [*]u8, len: usize) void;
extern "zenit" fn console_log(ptr: [*]const u8, len: usize) void;

pub const has_fs = std.Io.File.Handle != void;

fn now(_: ?*anyopaque, clock: std.Io.Clock) std.Io.Timestamp {
    return .{ .nanoseconds = switch (clock) {
        .real => real_ns(),
        else => now_ns(),
    } };
}
fn resolution(_: ?*anyopaque, _: std.Io.Clock) std.Io.Clock.ResolutionError!std.Io.Duration {
    return .{ .nanoseconds = 1000 };
}
// Nothing on the browser main thread is ever canceled; std.debug.print and
// friends only need the swap to round-trip.
var cancel_protection: std.Io.CancelProtection = .unblocked;
fn swapCancelProtection(_: ?*anyopaque, new: std.Io.CancelProtection) std.Io.CancelProtection {
    defer cancel_protection = new;
    return cancel_protection;
}

// stdout/stderr (std.debug.print, std.log) -> console.log, one call per line.
var console_line: [1024]u8 = undefined;
var console_len: usize = 0;
fn consoleBytes(bytes: []const u8) void {
    for (bytes) |b| {
        if (b == '\n' or console_len == console_line.len) {
            console_log(&console_line, console_len);
            console_len = 0;
            if (b == '\n') continue;
        }
        console_line[console_len] = b;
        console_len += 1;
    }
}
var stderr_writer: std.Io.File.Writer = undefined;
var stderr_ready = false;
fn lockStderr(_: ?*anyopaque, _: ?std.Io.Terminal.Mode) std.Io.Cancelable!std.Io.LockedStderr {
    if (!stderr_ready) {
        stderr_writer = std.Io.File.stderr().writerStreaming(io, &.{});
        stderr_ready = true;
    }
    return .{ .file_writer = &stderr_writer, .terminal_mode = .no_color };
}
fn tryLockStderr(ud: ?*anyopaque, mode: ?std.Io.Terminal.Mode) std.Io.Cancelable!?std.Io.LockedStderr {
    return try lockStderr(ud, mode);
}
fn unlockStderr(_: ?*anyopaque) void {
    stderr_writer.interface.flush() catch {};
}
fn unsupportedWait(_: ?*anyopaque, _: *const u32, _: u32) void {
    @panic("web host: the browser main thread cannot block");
}
fn fillRandom(buffer: []u8) void {
    // crypto.getRandomValues caps one call at 64 KiB.
    var rest = buffer;
    while (rest.len > 0) {
        const n = @min(rest.len, 65536);
        random_bytes(rest.ptr, n);
        rest = rest[n..];
    }
}
fn random(_: ?*anyopaque, buffer: []u8) void {
    fillRandom(buffer);
}
fn randomSecure(_: ?*anyopaque, buffer: []u8) std.Io.RandomSecureError!void {
    fillRandom(buffer);
}
fn realNowNs() i96 {
    return real_ns();
}

/// The browser filesystem (one per wasm instance).
pub var fs: if (has_fs) vfs.Vfs else void = if (has_fs) vfs.Vfs.lazy(std.heap.wasm_allocator, .{ .now_ns = realNowNs, .random = fillRandom, .console = consoleBytes }) else {};

const vtable: std.Io.VTable = blk: {
    var table = std.Io.failing.vtable.*;
    if (has_fs) table = vfs.overlay(table);
    table.swapCancelProtection = swapCancelProtection;
    if (has_fs) {
        table.lockStderr = lockStderr;
        table.tryLockStderr = tryLockStderr;
        table.unlockStderr = unlockStderr;
    }
    table.futexWaitUncancelable = unsupportedWait;
    table.now = now;
    table.clockResolution = resolution;
    table.random = random;
    table.randomSecure = randomSecure;
    break :blk table;
};
pub const io: std.Io = .{ .userdata = if (has_fs) @ptrCast(&fs) else null, .vtable = &vtable };

/// JS ↔ VFS persistence protocol (driven by web/runtime/zenit-dom.mjs):
///   load:    p = zw_vfs_alloc(n) …write bytes… zw_vfs_import(kind, path, data, mtime_ms)
///            (import copies the path and takes ownership of the data buffer)
///   persist: n = zw_vfs_take(); for i < n: info = zw_vfs_entry(i) (copy out);
///            zw_vfs_release()
/// kind: 0 = deleted, 1 = file, 2 = directory. Paths are absolute.
pub fn exportVfs() void {
    if (!has_fs) return;
    const E = struct {
        const Info = extern struct {
            path_ptr: u32,
            path_len: u32,
            kind: u32,
            data_ptr: u32,
            data_len: u32,
            _pad: u32 = 0,
            mtime_ms: f64,
        };
        var info: Info = undefined;
        const gpa = std.heap.wasm_allocator;
        fn alloc(len: usize) callconv(.c) ?[*]u8 {
            const s = gpa.alloc(u8, len) catch return null;
            return s.ptr;
        }
        fn free(ptr: [*]u8, len: usize) callconv(.c) void {
            gpa.free(ptr[0..len]);
        }
        fn import(kind: u32, path_ptr: [*]const u8, path_len: usize, data_ptr: [*]u8, data_len: usize, mtime_ms: f64) callconv(.c) void {
            const k = std.enums.fromInt(vfs.EntryKind, kind) orelse return;
            const data: []u8 = if (data_len == 0) &.{} else data_ptr[0..data_len];
            fs.import(path_ptr[0..path_len], k, data, @intFromFloat(mtime_ms * std.time.ns_per_ms));
        }
        fn dirtyCount() callconv(.c) usize {
            return fs.dirtyCount();
        }
        fn take() callconv(.c) usize {
            return fs.takeDirty();
        }
        fn entry(i: usize) callconv(.c) *const Info {
            const e = fs.takenEntry(i);
            info = .{
                .path_ptr = @intFromPtr(e.path.ptr),
                .path_len = @intCast(e.path.len),
                .kind = @backingInt(e.kind),
                .data_ptr = @intFromPtr(e.data.ptr),
                .data_len = @intCast(e.data.len),
                .mtime_ms = @as(f64, @floatFromInt(e.mtime_ns)) / std.time.ns_per_ms,
            };
            return &info;
        }
        fn release() callconv(.c) void {
            fs.releaseTaken();
        }
    };
    @export(&E.alloc, .{ .name = "zw_vfs_alloc" });
    @export(&E.free, .{ .name = "zw_vfs_free" });
    @export(&E.import, .{ .name = "zw_vfs_import" });
    @export(&E.dirtyCount, .{ .name = "zw_vfs_dirty_count" });
    @export(&E.take, .{ .name = "zw_vfs_take" });
    @export(&E.entry, .{ .name = "zw_vfs_entry" });
    @export(&E.release, .{ .name = "zw_vfs_release" });
}
