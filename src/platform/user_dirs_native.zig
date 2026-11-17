//! C ABI for the Objective-C updater (src/update/native_shared.m), which
//! derives its private area from the user's home. Linked into the app, the
//! ZeroWorkUpdater helper and the update fixture.
const std = @import("std");
const user_dirs = @import("user_dirs.zig");

/// 0: formal build. The caller keeps its historical source (NSHomeDirectory);
///    the updater only consults this function when compiled with
///    ZW_UPDATE_TESTING, so formal binaries never take this path.
/// 1: isolated build; the validated private home is written NUL-terminated.
/// -1: isolated build without a valid private HOME. The caller must refuse.
pub export fn zw_user_dirs_isolated_home(out: [*]u8, capacity: usize) c_int {
    if (comptime !user_dirs.isolated) return 0;
    const value = user_dirs.home(std.heap.c_allocator) catch return -1;
    defer std.heap.c_allocator.free(value);
    if (value.len >= capacity) return -1;
    @memcpy(out[0..value.len], value);
    out[value.len] = 0;
    return 1;
}
