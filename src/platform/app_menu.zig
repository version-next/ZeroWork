const metadata = @import("application_options");
extern fn zw_app_menu_apply_branding([*:0]const u8) void;

/// Apply product names to the framework's native application menu.
/// Call on the UI thread after the macOS application has initialized.
pub fn apply() void {
    zw_app_menu_apply_branding(metadata.version_metadata ++ "\x00");
}

extern fn zw_app_menu_take_appearance() bool;
/// 显示 › 外观… was chosen since the last call (main thread).
pub const takeAppearanceRequest = zw_app_menu_take_appearance;

extern fn zw_app_menu_test(c_int, [*]const u8, usize, [*]u8, usize) usize;
pub const TestAction = union(enum) { snapshot, appearance, title: []const u8 };
/// Test harness only (called from the harness-gated `/zerowork/app-menu` route): snapshot the native
/// main menu (titles, 显示 items, every item's key equivalent), after invoking 显示 › 外观… or the item
/// with the given title.
pub fn testRoute(action: TestAction, buffer: []u8) ?[]const u8 {
    const mode: c_int, const title: []const u8 = switch (action) {
        .snapshot => .{ 0, "" },
        .appearance => .{ 1, "" },
        .title => |value| .{ 2, value },
    };
    const length = zw_app_menu_test(mode, title.ptr, title.len, buffer.ptr, buffer.len);
    return if (length == 0) null else buffer[0..length];
}
