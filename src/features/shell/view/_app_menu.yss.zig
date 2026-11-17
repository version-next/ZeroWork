// GENERATED FILE, do not edit: generated from app_menu.yss; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! 菜单挂载点。菜单面板、行、分组标题、子菜单、分隔线、快捷键与禁用原因都是原生 `W.Menu` 默认外观，这里不写任何菜单样式。
const ui = @import("ui");

/// 原生 Menu 的挂载点：面板挂到窗口浮层根（portal）并按锚点定位，模板根不能为空，留一个不占位的 box。
pub const anchor = ui.previewCss("src/features/shell/view/app_menu.yss", "anchor", @embedFile("app_menu.yss"), .{ .position = .absolute, .width = 0, .height = 0, });

//# yix-map app_menu.yss
