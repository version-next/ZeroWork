// GENERATED FILE, do not edit: generated from pane_header.yss; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! 窗格头部的排版（ZW2 / Pane Header tOrT3：高 30 · 内边距 0 4 0 12 · 间距 6 · 类型图标 14 · 标题 12 · 状态点 6 ·
//! 路径 11）。按钮、提示、菜单都是原生组件默认外观——这里只写布局、正文文字与状态点。
const ui = @import("ui");

pub const header = ui.previewCss("src/features/workspace/view/pane_header.yss", "header", @embedFile("pane_header.yss"), .{ .width = .fill, .min_width = 0, .height = 30, .flex_shrink = 0, .direction = .row, .align_items = .center, .gap = 6, .padding = .{ .top = 0, .right = 4, .bottom = 0, .left = 12 }, });
/// 把手的图标（13，fg-secondary）；外层是手写拖动组件 `PaneDrag`。
pub const grip_icon = ui.previewCss("src/features/workspace/view/pane_header.yss", "grip_icon", @embedFile("pane_header.yss"), .{ .width = 13, .height = 13, .flex_shrink = 0, .icon_color = ui.tokenRef(.color, "fg-secondary"), .hit_behavior = .pass_through, });
/// 类型图标：聚焦窗格（或卡片自己要求，如 AI）用 accent，其余 fg-secondary。
pub const Type = ui.previewCva("src/features/workspace/view/pane_header.yss", "Type", @embedFile("pane_header.yss"), .{ .base = .{ .width = 14, .height = 14, .flex_shrink = 0, .hit_behavior = .pass_through, }, .variants = .{ .accent = .{ .false = .{ .icon_color = ui.tokenRef(.color, "fg-secondary"), }, .true = .{ .icon_color = ui.tokenRef(.color, "accent"), }, }, }, .defaults = .{ .accent = false, }, });
/// 标题：聚焦窗格 600 / fg-primary，其余 500 / fg-secondary；放不下时省略号。
pub const Title = ui.previewCva("src/features/workspace/view/pane_header.yss", "Title", @embedFile("pane_header.yss"), .{ .base = .{ .font_size = 12, .line_height = 1.5, .wrap = .none, .text_overflow = .ellipsis, .selectable = false, }, .variants = .{ .focused = .{ .false = .{ .font_weight = 500, .color = ui.tokenRef(.color, "fg-secondary"), }, .true = .{ .font_weight = 600, .color = ui.tokenRef(.color, "fg-primary"), }, }, }, .defaults = .{ .focused = false, }, });
pub const title_slot = ui.previewCss("src/features/workspace/view/pane_header.yss", "title_slot", @embedFile("pane_header.yss"), .{ .width = .fit, .min_width = 0, .flex_shrink = 1, .direction = .row, .align_items = .center, .overflow = .hidden, });
pub const title_box = ui.previewCss("src/features/workspace/view/pane_header.yss", "title_box", @embedFile("pane_header.yss"), .{ .width = .fill, .min_width = 0, });
/// 连接状态点 6。
/// 颜色由 workspace 按连接阶段给（与页签圆点同一个映射，见 `pane_header_view.Spec.dot`），这里只定形状。
pub fn dot(color: ui.Color, _: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .{ .px = 6 }, .height = .{ .px = 6 }, .corner_radius = 3, .flex_shrink = 0, .background = color };
}
pub const spacer = ui.previewCss("src/features/workspace/view/pane_header.yss", "spacer", @embedFile("pane_header.yss"), .{ .width = .fill, .min_width = 0, .height = 1, .flex_shrink = 1, .hit_behavior = .pass_through, });
/// 路径 · 列 × 行。
pub const meta = ui.previewCss("src/features/workspace/view/pane_header.yss", "meta", @embedFile("pane_header.yss"), .{ .flex_shrink = 0, .font_size = 11, .line_height = 1.4545, .color = ui.tokenRef(.color, "fg-secondary"), .wrap = .none, .text_overflow = .ellipsis, .selectable = false, });
/// 按钮的槽（原生 ghost sm 图标按钮），永不收缩。
pub const action = ui.previewCss("src/features/workspace/view/pane_header.yss", "action", @embedFile("pane_header.yss"), .{ .width = .fit, .height = .fit, .flex_shrink = 0, });

//# yix-map pane_header.yss
