// GENERATED FILE, do not edit: generated from panel_header.yss; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! 面板头部的排版（Pencil「面板头部与空状态规范」= 浮动卡片外框头部规格：高 30 · 间距 6 · 图标 14 ·
//! 标题 12/600 · 副标题 11）。按钮是原生 ghost sm 图标按钮——这里只写布局与正文文字，不写原生组件的外观。
const ui = @import("ui");

/// 头部：`.card` 贴边（内边距 0 4 0 12，同浮动外框）；`.flush` 放在已有内边距的容器里（左右不再留白）。
pub const Header = ui.previewCva("src/shared/ui/components/panel_header/panel_header.yss", "Header", @embedFile("panel_header.yss"), .{ .base = .{ .width = .fill, .min_width = 0, .height = 30, .flex_shrink = 0, .direction = .row, .align_items = .center, .gap = 6, }, .variants = .{ .inset = .{ .card = .{ .padding = .{ .top = 0, .right = 4, .bottom = 0, .left = 12 }, }, .flush = .{ .padding = 0, }, }, }, .defaults = .{ .inset = .card, }, });
pub const Inset = Header.Dim(.inset);
pub const Icon = ui.previewCva("src/shared/ui/components/panel_header/panel_header.yss", "Icon", @embedFile("panel_header.yss"), .{ .base = .{ .width = 14, .height = 14, .flex_shrink = 0, }, .variants = .{ .accent = .{ .false = .{ .icon_color = ui.tokenRef(.color, "fg-secondary"), }, .true = .{ .icon_color = ui.tokenRef(.color, "accent"), }, }, }, .defaults = .{ .accent = false, }, });
/// 标题最后让位：副标题先省略号截断，标题以几乎为零的收缩权重截断，按钮永不收缩。
pub const title_box = ui.previewCss("src/shared/ui/components/panel_header/panel_header.yss", "title_box", @embedFile("panel_header.yss"), .{ .width = .fit, .min_width = 0, .flex_shrink = 0.01, .direction = .row, .align_items = .center, .overflow = .hidden, });
pub const title = ui.previewCss("src/shared/ui/components/panel_header/panel_header.yss", "title", @embedFile("panel_header.yss"), .{ .font_size = 12, .font_weight = 600, .color = ui.tokenRef(.color, "fg-primary"), .wrap = .none, .text_overflow = .ellipsis, .selectable = false, });
pub const subtitle_box = ui.previewCss("src/shared/ui/components/panel_header/panel_header.yss", "subtitle_box", @embedFile("panel_header.yss"), .{ .width = .fit, .max_width = 200, .min_width = 0, .flex_shrink = 1, .direction = .row, .align_items = .center, .overflow = .hidden, });
pub const subtitle = ui.previewCss("src/shared/ui/components/panel_header/panel_header.yss", "subtitle", @embedFile("panel_header.yss"), .{ .font_size = 11, .color = ui.tokenRef(.color, "fg-secondary"), .wrap = .none, .text_overflow = .ellipsis, .selectable = false, });
pub const text_box = ui.previewCss("src/shared/ui/components/panel_header/panel_header.yss", "text_box", @embedFile("panel_header.yss"), .{ .width = .fill, .min_width = 0, });
pub const spacer = ui.previewCss("src/shared/ui/components/panel_header/panel_header.yss", "spacer", @embedFile("panel_header.yss"), .{ .width = .{ .grow = .{} }, .min_width = 0, .height = 1, });
/// 动作区：辅助动作（原生组件），间距同头部；永不收缩。
pub const actions = ui.previewCss("src/shared/ui/components/panel_header/panel_header.yss", "actions", @embedFile("panel_header.yss"), .{ .width = .fit, .height = .fit, .flex_shrink = 0, .direction = .row, .align_items = .center, .gap = 6, });
/// 关闭按钮的槽：原生 ghost sm 图标按钮 24 × 24，永不收缩。
pub const action = ui.previewCss("src/shared/ui/components/panel_header/panel_header.yss", "action", @embedFile("panel_header.yss"), .{ .width = .fit, .height = .fit, .flex_shrink = 0, });

//# yix-map panel_header.yss
