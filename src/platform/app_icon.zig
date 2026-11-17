const config = @import("../config/config.zig");
const assets = @import("app_icon_assets");
extern fn zw_app_icon_apply(bytes: [*]const u8, length: usize, background: [*:0]const u8) bool;
extern fn zw_app_icon_set_running(bytes: [*]const u8, length: usize) bool;
var applied: ?config.IconBackground = null;

/// Publish the committed selection to both the running app and Dock plug-in.
/// Signed bundle resources remain unchanged. UI thread only.
pub fn apply(background: config.IconBackground) bool {
    if (applied == background) return true;
    const bytes = switch (background) {
        .transparent => assets.transparent,
        .light => assets.light,
        .dark => assets.dark,
    };
    const style: [:0]const u8 = switch (background) {
        .transparent => "transparent",
        .light => "light",
        .dark => "dark",
    };
    // Isolated (test) builds never write the user's preference domain.
    const ok = if (comptime @import("user_dirs.zig").writes_user_preferences) zw_app_icon_apply(bytes.ptr, bytes.len, style.ptr) else zw_app_icon_set_running(bytes.ptr, bytes.len);
    if (!ok) return false;
    applied = background;
    return true;
}
