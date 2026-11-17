//! 状态色调 → 当前主题颜色（shared/base/connection_presenter.zig 的 Tone）。连接与转发状态的颜色只从这里取。
const ui = @import("ui");
const theme = @import("app_theme.zig");
pub const Tone = @import("../../base/connection_presenter.zig").Tone;

/// 圆点、图标等小面积图形。
pub fn dot(tone: Tone) ui.Color {
    const c = theme.current();
    return switch (tone) {
        .ok => c.ok,
        .warn => c.warn,
        .danger => c.danger,
        .muted => c.fg_3,
    };
}

/// 文字（加深的 ink 版本，保证对比度）。
pub fn ink(tone: Tone) ui.Color {
    const c = theme.current();
    return switch (tone) {
        .ok => c.ok_ink,
        .warn => c.warn_ink,
        .danger => c.danger_ink,
        .muted => c.fg_3,
    };
}
