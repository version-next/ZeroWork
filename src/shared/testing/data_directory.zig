//! Only honoured by isolated builds: unit tests, the explicit test-mode
//! executable, previews, fixtures and acceptance runners. Formal builds return
//! null at comptime.
const std = @import("std");
pub fn override() ?[]const u8 {
    if (comptime !@import("../../platform/runtime_mode.zig").isolated_home) return null;
    const value = std.c.getenv("ZEROWORK_DATA_DIR") orelse return null;
    return std.mem.span(value);
}
