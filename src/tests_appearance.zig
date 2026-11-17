//! No-window appearance model, assets and configuration transactions.
test {
    _ = @import("features/shell/model/startup_transition.zig");
    _ = @import("config/theme_registry.zig");
    _ = @import("config/background_asset.zig");
    _ = @import("config/background_geometry.zig");
    _ = @import("config/tests/background_asset_tests.zig");
    _ = @import("config/tests/theme_installation_tests.zig");
    _ = @import("features/settings/tests/appearance_apply_tests.zig");
    _ = @import("features/settings/tests/appearance_ui_worker_tests.zig");
    _ = @import("features/settings/model/settings_controller.zig");
}
