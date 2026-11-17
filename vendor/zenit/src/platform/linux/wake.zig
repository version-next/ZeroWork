//! Process-wide event-loop wake for the Linux backend (docs/design/append-inbox.md §5).
//!
//! One eventfd for the process, created on first use and never closed (a producer thread may
//! post at any moment, including during teardown; closing it would let a late write hit a reused
//! descriptor). `post` adds 1 from any thread; the main event pump polls `fd()` beside the
//! Wayland display and `drain`s it when readable. Counts coalesce in the kernel, so a burst of
//! posts wakes the pump once. Windows' `zenit_windows_post_empty_event` (an auto-reset event in
//! `MsgWaitForMultipleObjectsEx`) is the same shape.
const std = @import("std");
const linux = std.os.linux;

const unset: i32 = -1;
const failed: i32 = -2;
var wake_fd: std.atomic.Value(i32) = .init(unset);

/// The wake descriptor, or -1 when the kernel refused to create one (the pump then waits as it
/// did before: until input or its timeout).
pub fn fd() i32 {
    const current = wake_fd.load(.acquire);
    if (current >= 0) return current;
    if (current == failed) return -1;
    const rc = linux.eventfd(0, linux.EFD.CLOEXEC | linux.EFD.NONBLOCK);
    if (linux.errno(rc) != .SUCCESS) {
        _ = wake_fd.cmpxchgStrong(unset, failed, .acq_rel, .acquire);
        const now = wake_fd.load(.acquire);
        return if (now >= 0) now else -1;
    }
    const created: i32 = @intCast(rc);
    // Another thread may have created one first: keep the winner, close ours.
    if (wake_fd.cmpxchgStrong(unset, created, .acq_rel, .acquire)) |winner| {
        _ = linux.close(created);
        return if (winner >= 0) winner else -1;
    }
    return created;
}

/// Any thread: wake a pump blocked in `poll` on `fd()`.
pub fn post() void {
    const f = fd();
    if (f < 0) return;
    const one: u64 = 1;
    // EAGAIN only when the counter would overflow 2^64 - 2: the fd is readable then anyway.
    _ = linux.write(f, std.mem.asBytes(&one), @sizeOf(u64));
}

/// Main thread: consume pending posts (non-blocking).
pub fn drain(f: i32) void {
    if (f < 0) return;
    var count: u64 = 0;
    _ = linux.read(f, std.mem.asBytes(&count), @sizeOf(u64));
}

// ===== Tests (Linux only) =====

const testing = std.testing;

fn pollWake(f: i32, timeout_ms: i32) bool {
    var fds = [_]linux.pollfd{.{ .fd = f, .events = linux.POLL.IN }};
    while (true) {
        const rc = linux.poll(&fds, 1, timeout_ms);
        switch (linux.errno(rc)) {
            .SUCCESS => return rc == 1 and fds[0].revents & linux.POLL.IN != 0,
            .INTR => continue,
            else => return false,
        }
    }
}

test "linux wake: a post from another thread ends a blocking poll; drain consumes it" {
    const f = fd();
    try testing.expect(f >= 0);
    try testing.expectEqual(f, fd()); // one descriptor per process
    drain(f);
    try testing.expect(!pollWake(f, 0));
    const Poster = struct {
        fn run() void {
            std.Io.sleep(testing.io, .fromNanoseconds(50 * std.time.ns_per_ms), .awake) catch {};
            post();
        }
    };
    const thread = try std.Thread.spawn(.{}, Poster.run, .{});
    // Times out (false) after 10 s without the post.
    try testing.expect(pollWake(f, 10_000));
    thread.join();
    drain(f);
    try testing.expect(!pollWake(f, 0));
}

test "linux wake: posts coalesce into one readable state" {
    const f = fd();
    drain(f);
    for (0..1000) |_| post();
    try testing.expect(pollWake(f, 0));
    drain(f);
    try testing.expect(!pollWake(f, 0));
}

test "linux wake: concurrent first use creates one descriptor" {
    // The descriptor may already exist from an earlier test; the property is that every thread
    // sees the same one.
    var seen: [8]i32 = undefined;
    var threads: [8]std.Thread = undefined;
    const Reader = struct {
        fn run(out: *i32) void {
            out.* = fd();
        }
    };
    for (&threads, &seen) |*t, *s| t.* = try std.Thread.spawn(.{}, Reader.run, .{s});
    for (threads) |t| t.join();
    for (seen) |s| try testing.expectEqual(seen[0], s);
}
