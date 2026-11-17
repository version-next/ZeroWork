// GENERATED FILE, do not edit: generated from material_preview_bar.yss; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! 全窗口材质预览操作条的样式（旧 `appearance_styles.previewBar`：48 高、内边距 [0, 12]、间距 8、圆角 14、浮层底色）。
//! 位置由宿主按主窗口内容区算好（`Place`），经 `placed` 写成绝对定位；颜色只用 token。
const ui = @import("ui");

pub const Place = struct { left: f32 = 0, bottom: f32 = 58, width: f32 = 660 };

pub const bar = ui.previewCss("src/features/settings/view/material_preview_bar.yss", "bar", @embedFile("material_preview_bar.yss"), .{ .height = 48, .direction = .row, .align_items = .center, .gap = 8, .padding = .{ .y = 0, .x = 12 }, .corner_radius = 14, .background = ui.tokenRef(.color, "zw-window-surface"), .border_overlay = true, .border_width = 1, .border_color = ui.tokenRef(.color, "border"), .flex_shrink = 0, });
pub fn placed(place: Place, _: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .position = .absolute, .width = .{ .px = place.width }, .inset = .{ .left = .{ .px = place.left }, .bottom = .{ .px = place.bottom } }, .z_index = 11000 };
}
pub const bar_icon = ui.previewCss("src/features/settings/view/material_preview_bar.yss", "bar_icon", @embedFile("material_preview_bar.yss"), .{ .width = 16, .height = 16, .flex_shrink = 0, .icon_color = ui.tokenRef(.color, "zw-fg-supporting"), });
pub const bar_cell = ui.previewCss("src/features/settings/view/material_preview_bar.yss", "bar_cell", @embedFile("material_preview_bar.yss"), .{ .width = 120, .flex_shrink = 0, });
pub const bar_label = ui.previewCss("src/features/settings/view/material_preview_bar.yss", "bar_label", @embedFile("material_preview_bar.yss"), .{ .font_size = 13, .font_weight = 400, .line_height = 18.0 / 13.0, .color = ui.tokenRef(.color, "fg-primary"), });
pub const bar_value = ui.previewCss("src/features/settings/view/material_preview_bar.yss", "bar_value", @embedFile("material_preview_bar.yss"), .{ .font_size = 12, .font_weight = 400, .line_height = 18.0 / 12.0, .color = ui.tokenRef(.color, "zw-fg-supporting"), });

//# yix-map material_preview_bar.yss
