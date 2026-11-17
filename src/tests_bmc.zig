//! Isolated V0.3 public seam and protocol tests; no user credentials or BMC IO.
comptime {
    _ = @import("host/frame_performance.zig");
    _ = @import("plugins/bmc_ikvm/input_mapping.zig");
    _ = @import("plugins/bmc_ikvm/overlay_model.zig");
    _ = @import("plugins/bmc_ikvm/presentation_wake.zig");
    _ = @import("plugins/bmc_ikvm/tests/bmc_security_tests.zig");
    _ = @import("plugins/bmc_ikvm/tests/bmc_frame_input_tests.zig");
    _ = @import("plugins/bmc_ikvm/tests/bmc_wire_tests.zig");
    _ = @import("plugins/bmc_ikvm/tests/bmc_rfb_tests.zig");
    _ = @import("plugins/bmc_ikvm/tests/bmc_management_tests.zig");
    _ = @import("plugins/bmc_ikvm/tests/bmc_redfish_compatibility_tests.zig");
    _ = @import("plugins/bmc_ikvm/tests/bmc_production_management_tests.zig");
    _ = @import("plugins/bmc_ikvm/tests/bmc_journal_concurrency_tests.zig");
    _ = @import("plugins/bmc_ikvm/tests/bmc_probe_access_tests.zig");
    _ = @import("plugins/bmc_ikvm/tests/bmc_credential_gc_tests.zig");
    _ = @import("plugins/bmc_ikvm/route.zig");
    _ = @import("plugins/bmc_ikvm/tests/bmc_controller_tests.zig");
    _ = @import("plugins/bmc_ikvm/tests/bmc_native_driver_tests.zig");
    _ = @import("plugins/bmc_ikvm/native_driver.zig");
    _ = @import("plugins/bmc_ikvm/tests/bmc_plugin_probe_tests.zig");
    _ = @import("plugins/bmc_ikvm/tests/bmc_plugin_runtime_tests.zig");
    _ = @import("plugins/bmc_ikvm/tests/bmc_view_tests.zig");
    _ = @import("plugins/bmc_ikvm/tests/bmc_editor_tests.zig");
    _ = @import("plugins/bmc_ikvm/tests/bmc_editor_capability_tests.zig");
    _ = @import("plugins/bmc_ikvm/tests/bmc_bootstrap_tests.zig");
    _ = @import("plugins/bmc_ikvm/tests/bmc_composition_tests.zig");
    _ = @import("plugins/bmc_ikvm/tests/bmc_explicit_input_tests.zig");
    _ = @import("plugins/bmc_ikvm/tests/bmc_live_backend_tests.zig");
    _ = @import("plugins/bmc_ikvm/tests/bmc_connection_progress_tests.zig");
    _ = @import("plugins/bmc_ikvm/tests/bmc_ai_observation_tests.zig");
    _ = @import("plugins/bmc_ikvm/tests/bmc_ai_input_tests.zig");
    _ = @import("plugins/bmc_ikvm/tests/bmc_ai_tool_tests.zig");
    _ = @import("plugins/bmc_ikvm/tests/bmc_snapshot_copy_tests.zig");
    _ = @import("features/shell/host/plugin_window_host.zig");
}
