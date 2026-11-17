// GENERATED FILE, do not edit: generated from float_chrome.yss; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! 浮动卡片统一窗口外观的排版（Pencil「浮动卡片统一窗口外观」规范稿，取自 AI 浮动面板定稿
//! `uyp8W`：拖动把手 14、头部 30、内边距 0 4 0 12、间距 6、图标 14、标题 12/600、副标题 11）。
//! 外框是原生 `W.Card` floating（圆角 dialog 12、1px border、shadow lg、bg-primary），把手是原生
//! `W.Grabber`，动作按钮是原生 ghost sm 图标按钮——这里只写布局与正文文字，不写原生组件的背景、
//! 圆角、阴影。
const ui = @import("ui");

/// 外框根：填满浮动层给的尺寸（浮动层写宽高）。
pub const root = ui.previewCss("src/shared/ui/float_card/float_chrome.yss", "root", @embedFile("float_chrome.yss"), .{ .width = .fill, .height = .fill, .min_width = 0, .min_height = 0, .direction = .column, });

/// 顶部拖动把手 `float.drag`：整条宽、高 14，原生 Grabber 居中（光标由浮动层按可拖动状态设置）。
/// 按住（下滑收起稿 AveHg 的 Drag Trigger 按下态）：整条铺 `bg-hover`，Grabber 自己变 active。
pub const Grip = ui.previewCva("src/shared/ui/float_card/float_chrome.yss", "Grip", @embedFile("float_chrome.yss"), .{ .base = .{ .width = .fill, .height = 14, .flex_shrink = 0, .direction = .row, .justify = .center, .align_items = .center, }, .variants = .{ .held = .{ .false = .{ }, .true = .{ .background = ui.tokenRef(.color, "bg-hover"), }, }, }, .defaults = .{ .held = false, }, });

/// 头部：图标 · 标题 · 副标题（先省略、放不下时隐藏）· 弹性空白 · 卡片插槽按钮 · 统一动作按钮。
pub const header = ui.previewCss("src/shared/ui/float_card/float_chrome.yss", "header", @embedFile("float_chrome.yss"), .{ .width = .fill, .min_width = 0, .height = 30, .flex_shrink = 0, .direction = .row, .align_items = .center, .gap = 6, .padding = .{ .top = 0, .right = 4, .bottom = 0, .left = 12 }, });
/// The icon's holder: at the narrowest width it steps aside before the title truncates (ai-redesign-c).
pub const icon_box = ui.previewCss("src/shared/ui/float_card/float_chrome.yss", "icon_box", @embedFile("float_chrome.yss"), .{ .width = 14, .height = 14, .flex_shrink = 0, .direction = .row, .align_items = .center, });
pub const Icon = ui.previewCva("src/shared/ui/float_card/float_chrome.yss", "Icon", @embedFile("float_chrome.yss"), .{ .base = .{ .width = 14, .height = 14, .flex_shrink = 0, }, .variants = .{ .accent = .{ .false = .{ .icon_color = ui.tokenRef(.color, "fg-secondary"), }, .true = .{ .icon_color = ui.tokenRef(.color, "accent"), }, }, }, .defaults = .{ .accent = false, }, });
pub const title = ui.previewCss("src/shared/ui/float_card/float_chrome.yss", "title", @embedFile("float_chrome.yss"), .{ .font_size = 12, .font_weight = 600, .color = ui.tokenRef(.color, "fg-primary"), .wrap = .none, .text_overflow = .ellipsis, .selectable = false, });
/// 标题是最后的让位者（float-split：放置动作固定出现后 320 宽的 AI 头部有 8 个按钮）：副标题先截断、隐藏，
/// 之后标题才以几乎为零的收缩权重省略号截断，按钮永不收缩。
pub const title_box = ui.previewCss("src/shared/ui/float_card/float_chrome.yss", "title_box", @embedFile("float_chrome.yss"), .{ .width = .fit, .min_width = 0, .flex_shrink = 0.01, .direction = .row, .align_items = .center, .overflow = .hidden, });
/// 副标题（归属 / 条数）：最先让位——先省略号截断，窄到 `min_subtitle_width` 以下由宿主钩子隐藏。
pub const subtitle_box = ui.previewCss("src/shared/ui/float_card/float_chrome.yss", "subtitle_box", @embedFile("float_chrome.yss"), .{ .width = .fit, .max_width = 160, .min_width = 0, .flex_shrink = 1, .direction = .row, .align_items = .center, .overflow = .hidden, });
pub const subtitle = ui.previewCss("src/shared/ui/float_card/float_chrome.yss", "subtitle", @embedFile("float_chrome.yss"), .{ .font_size = 11, .color = ui.tokenRef(.color, "fg-secondary"), .wrap = .none, .text_overflow = .ellipsis, .selectable = false, });
pub const text_box = ui.previewCss("src/shared/ui/float_card/float_chrome.yss", "text_box", @embedFile("float_chrome.yss"), .{ .width = .fill, .min_width = 0, });
pub const spacer = ui.previewCss("src/shared/ui/float_card/float_chrome.yss", "spacer", @embedFile("float_chrome.yss"), .{ .width = .{ .grow = .{} }, .min_width = 0, .height = 1, });
/// 动作按钮（插槽按钮与统一动作同尺寸：原生 ghost sm 图标按钮 24 × 24），永不收缩。
pub const action = ui.previewCss("src/shared/ui/float_card/float_chrome.yss", "action", @embedFile("float_chrome.yss"), .{ .width = .fit, .height = .fit, .flex_shrink = 0, });

/// 内容区：卡片只负责这里面的内容。
pub const body = ui.previewCss("src/shared/ui/float_card/float_chrome.yss", "body", @embedFile("float_chrome.yss"), .{ .width = .fill, .min_width = 0, .height = .{ .grow = .{} }, .min_height = 0, .direction = .column, });

//# yix-map float_chrome.yss
