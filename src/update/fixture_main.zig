//! Isolated updater process/verification fixture. Never installed by production builds.
pub const application_test_mode = true;
comptime {
    _ = @import("crypto.zig");
    _ = @import("user_dirs_native");
    // Test-only root: always carries the launch-guard marker (same bytes as
    // src/platform/build_mode_marker.zig, which a root here cannot import).
    @export(&build_mode_marker, .{ .name = "zerowork_build_mode_marker" });
}
const build_mode_marker: [29:0]u8 = "ZEROWORK_BUILD_MODE=test-mode".*;
extern fn zw_update_fixture_main() void;
pub fn main() void { zw_update_fixture_main(); }
