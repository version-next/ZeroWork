// GENERATED FILE, do not edit: generated from sidebar_host_unavailable.yss; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! 主机行“已禁用”的挂载点与文字（qQaos：右侧“已禁用”代替终端数，次要墨色）。只排位置与字号，不写 Tooltip 外观（原生默认）。
const ui = @import("ui");

/// 行尾一格：文字自身宽度，不收缩，竖直居中。
pub const slot = ui.previewCss("src/features/shell/view/sidebar_host_unavailable.yss", "slot", @embedFile("sidebar_host_unavailable.yss"), .{ .width = .fit, .height = .fit, .direction = .row, .align_items = .center, .flex_shrink = 0, });
/// “已禁用”：11.5、三级墨色，单行。
pub const label = ui.previewCss("src/features/shell/view/sidebar_host_unavailable.yss", "label", @embedFile("sidebar_host_unavailable.yss"), .{ .font_size = 11.5, .font_weight = 400, .line_height = 16.0 / 11.5, .color = ui.tokenRef(.color, "zw-fg-faint"), .wrap = .none, });

//# yix-map sidebar_host_unavailable.yss
