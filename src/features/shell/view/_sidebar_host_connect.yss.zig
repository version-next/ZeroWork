// GENERATED FILE, do not edit: generated from sidebar_host_connect.yss; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! 主机行“连接”按钮的挂载点：只排位置，不写按钮外观（原生默认）。
const ui = @import("ui");

/// 行尾一格：按钮自身宽度，不收缩，竖直居中。
pub const slot = ui.previewCss("src/features/shell/view/sidebar_host_connect.yss", "slot", @embedFile("sidebar_host_connect.yss"), .{ .width = .fit, .height = .fit, .direction = .row, .align_items = .center, .flex_shrink = 0, });

//# yix-map sidebar_host_connect.yss
