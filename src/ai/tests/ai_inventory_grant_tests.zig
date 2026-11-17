//! Headless metadata grant tests. No application, host service or data access.
comptime {
    _ = @import("../inventory_grants.zig");
    _ = @import("../inventory_approval.zig");
}
