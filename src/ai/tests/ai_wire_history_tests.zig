//! Dedicated headless regression entry; no model or network requests.
test {
    _ = @import("../wire_history.zig");
    _ = @import("../assistant_store.zig");
    _ = @import("../provider_json.zig");
}
