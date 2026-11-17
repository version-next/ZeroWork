//! Standalone lifecycle backend regression root (no native UI launch).
test {
    _ = @import("../host_lifecycle.zig");
    _ = @import("../lifecycle_runtime.zig");
}
