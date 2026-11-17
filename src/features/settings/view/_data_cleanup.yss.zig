// GENERATED FILE, do not edit: generated from data_cleanup.yss; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! “清除全部数据…”确认对话框（S-12，`data_cleanup.yix`）的正文样式。面板、遮罩、标题栏、按钮都是原生 `W.Modal` /
//! `W.Button` 默认外观；这里只给正文的布局盒子与文字（颜色只用 token）。文字层级同 H-save 的确认对话框（`styles.yss` 的
//! `confirm_*`）：说明 13 / 提示 12，警示句用 `danger`。
const ui = @import("ui");

/// 插槽正文：范围说明、保留说明、后果、状态行（标题句是确认框的说明）。
pub const detail = ui.previewCss("src/features/settings/view/data_cleanup.yss", "detail", @embedFile("data_cleanup.yss"), .{ .font_size = 13, .font_weight = 400, .line_height = 1.5, .color = ui.tokenRef(.color, "fg-primary"), .wrap = .word, });
pub const outcome = ui.previewCss("src/features/settings/view/data_cleanup.yss", "outcome", @embedFile("data_cleanup.yss"), .{ .font_size = 12, .font_weight = 400, .line_height = 1.5, .color = ui.tokenRef(.color, "zw-fg-supporting"), .wrap = .word, });
/// 状态行（阻塞原因 / 进行中说明 / 失败原因）：空时不占高。
pub const Message = ui.previewCva("src/features/settings/view/data_cleanup.yss", "Message", @embedFile("data_cleanup.yss"), .{ .base = .{ .font_size = 12, .font_weight = 400, .line_height = 1.5, .color = ui.tokenRef(.color, "zw-fg-supporting"), .wrap = .word, }, .variants = .{ .warning = .{ .false = .{ }, .true = .{ .color = ui.tokenRef(.color, "danger"), }, }, }, .defaults = .{ .warning = false, }, });
pub const text_box = ui.previewCss("src/features/settings/view/data_cleanup.yss", "text_box", @embedFile("data_cleanup.yss"), .{ .width = .fill, });

//# yix-map data_cleanup.yss
