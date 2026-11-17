const ui = @import("ui");

/// Registry tokens reuse one address. Publish a different, window-owned
/// snapshot so Cx and native widgets observe each actual palette change.
/// Allocate this through cx.bindState to keep both addresses valid for Cx.
pub const ThemePublication = struct {
    snapshots: [2]ui.ThemeTokens = undefined,
    slot: u1 = 0,

    pub fn publish(self: *ThemePublication, cx: *ui.Cx, prepared: *const ui.ThemeTokens) void {
        self.slot ^= 1;
        self.snapshots[self.slot] = prepared.*;
        @import("app_theme.zig").publishSchemes(cx);
        cx.setTheme(&self.snapshots[self.slot]);
    }
};
