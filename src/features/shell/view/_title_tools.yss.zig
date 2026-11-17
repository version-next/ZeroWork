// GENERATED FILE, do not edit: generated from title_tools.yss; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! 标题栏工具组的布局：只排位置、间距与收起时的叠放，不写按钮、分隔线、菜单、Tooltip 的外观（全部原生默认）。
const ui = @import("ui");

/// 一行：组内间距 2（行的 gap）；组间分隔线两侧各 6（gap 2 + margin 4）。收起的按钮绝对定位叠在行尾的“⋯”下。
pub const tools = ui.previewCss("src/features/shell/view/title_tools.yss", "tools", @embedFile("title_tools.yss"), .{ .direction = .row, .align_items = .center, .height = 32, .gap = 2, .flex_shrink = 0, });
/// 一个按钮的位置（32 × 32 是原生 md icon-only 的尺寸，这里只占位）。收起时叠到行尾“⋯”下方：透明、不参与命中，
/// 留在树里以便弹层仍从这里（即“⋯”处）弹出。
pub const Slot = ui.previewCva("src/features/shell/view/title_tools.yss", "Slot", @embedFile("title_tools.yss"), .{ .base = .{ .width = 32, .height = 32, .flex_shrink = 0, }, .variants = .{ .folded = .{ .false = .{ }, .true = .{ .position = .absolute, .inset = ui.Inset{ .right = .{ .px = 0 }, .top = .{ .px = 0 } }, .opacity = 0, .z_index = 0, .hit_behavior = .pass_through, }, }, }, .defaults = .{ .folded = false, }, });
/// 宿主挂进来的额外入口（后台 SOCKS 的远端入口）。
pub const extra = ui.previewCss("src/features/shell/view/title_tools.yss", "extra", @embedFile("title_tools.yss"), .{ .direction = .row, .align_items = .center, .flex_shrink = 0, });
/// 组间分隔线：1 × 16，两侧各 6。
pub const divider = ui.previewCss("src/features/shell/view/title_tools.yss", "divider", @embedFile("title_tools.yss"), .{ .width = 1, .height = 16, .margin = .{ .y = 0, .x = 4 }, .flex_shrink = 0, });
/// “⋯”：与前一个按钮相距 6，叠在收起的按钮上面。
pub const more = ui.previewCss("src/features/shell/view/title_tools.yss", "more", @embedFile("title_tools.yss"), .{ .width = 32, .height = 32, .margin = .{ .top = 0, .right = 0, .bottom = 0, .left = 4 }, .flex_shrink = 0, .z_index = 1, });
/// 未读通知圆点：贴在“⋯”右上角，不参与命中。
pub const dot = ui.previewCss("src/features/shell/view/title_tools.yss", "dot", @embedFile("title_tools.yss"), .{ .position = .absolute, .inset = ui.Inset{ .right = .{ .px = 4 }, .top = .{ .px = 4 } }, .width = 8, .height = 8, .hit_behavior = .pass_through, });

//# yix-map title_tools.yss
