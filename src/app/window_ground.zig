//! 原生窗口的“地面色”：创建窗口时把 `Config.clear_color` 设为窗口地面角色的
//! 主题底色。zenit 在创建窗口的同一个事件循环回合内把它落到 CAMetalLayer 背景
//! （首帧呈现前窗口显示的颜色），并在每帧的 `syncResizePresentation` 里跟随
//! clear color 变化（live resize 暴露的未上帧条带用它填充）——应用侧只需在创
//! 建时给出颜色、在主题切换时更新 renderer 的 clear color。
//!
//! 地面角色（`aux_window.Ground`）：`.panel` = 设置窗口（zw-window-surface，
//! surface_1 不透明）；`.shell` = 外壳地面（主窗口与向导窗口的 ground = 主题
//! app 色）。每个窗口创建时取样一次。
//!
//! 已知限制（既有启动路径如此，非本次引入）：导入主题在 registry 异步加载完成
//! 前只有 `builtinTokens` 的回退调色板，导入浅色主题的首帧（含首帧前的地面色）
//! 会短暂显示回退深色。
const app_theme = @import("../shared/ui/theme/app_theme.zig");
const aux_window = @import("../shared/ui/window/aux_window.zig");
const zenit_app = @import("zenit_app");

pub fn clear(ground: aux_window.Ground) zenit_app.ClearColor {
    // 颜色计算唯一真源在 app_theme（preview runner 同源接入）。
    const c = app_theme.windowClearColor(ground);
    return .{ .r = c.r, .g = c.g, .b = c.b, .a = c.a };
}

/// 主题切换后由进程循环调用（`ProcessWindows.syncGrounds`）：更新该窗口 renderer
/// 的 clear color（layer 背景由 zenit 的每帧同步跟随）。圆角透明 clear
/// （chrome_controller）生效中只更新待恢复值，退出圆角时回到当前主题。
pub fn syncWindow(app: *zenit_app.App, ground: zenit_app.ClearColor) void {
    if (app.chrome.saved_clear) |*saved| {
        saved.* = ground;
    } else {
        app.renderer.config.clear_color = ground;
    }
}
