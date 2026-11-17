// GENERATED FILE, do not edit: generated from disabled_plugin_editor.yss; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! 已禁用插件主机的编辑区：只排布局（提示在上，名称一行在下），不写原生组件的外观。
const ui = @import("ui");

pub const root = ui.previewCss("src/features/connections/wizard/view/disabled_plugin_editor.yss", "root", @embedFile("disabled_plugin_editor.yss"), .{ .width = .fill, .direction = .column, .gap = 16, .padding = 16, .flex_shrink = 0, .min_width = 0, });
pub const notice = ui.previewCss("src/features/connections/wizard/view/disabled_plugin_editor.yss", "notice", @embedFile("disabled_plugin_editor.yss"), .{ .width = .fill, .direction = .column, .flex_shrink = 0, .min_width = 0, });
/// 名称行：标签 + 输入框，gap 12；输入框撑满剩余宽度。
pub const field = ui.previewCss("src/features/connections/wizard/view/disabled_plugin_editor.yss", "field", @embedFile("disabled_plugin_editor.yss"), .{ .width = .fill, .direction = .row, .align_items = .center, .gap = 12, .min_width = 0, });
pub const label = ui.previewCss("src/features/connections/wizard/view/disabled_plugin_editor.yss", "label", @embedFile("disabled_plugin_editor.yss"), .{ .font_size = 13, .font_weight = 400, .color = ui.tokenRef(.color, "fg-secondary"), .wrap = .none, .flex_shrink = 0, });

//# yix-map disabled_plugin_editor.yss
