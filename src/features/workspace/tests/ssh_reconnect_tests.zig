//! Reconnection controller and original-pane integration. No native window.
test {
    _ = @import("../../../vt/reconnect.zig");
    _ = @import("../../../host/session_host.zig");
    _ = @import("../../shell/host/application_host.zig");
    _ = @import("../view/workspace.zig");
    _ = @import("../../connections/wizard/tests/ssh_resource_ledger_tests.zig");
}
