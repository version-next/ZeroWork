//! Focused std.http fetch tests. Only system CFNetwork/CoreFoundation are used.
test {
    _ = @import("../fetch_url.zig");
    _ = @import("../host_approval.zig");
    _ = @import("../fetch_url_feedback.zig");
}
