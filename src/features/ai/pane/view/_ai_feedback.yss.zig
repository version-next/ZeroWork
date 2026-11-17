// GENERATED FILE, do not edit: generated from ai_feedback.yss; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! AI 反馈条的布局：提示本身是原生 `W.Alert` 默认外观，这里只排位置与宽度（不写颜色 / 圆角 / 阴影）。
const ui = @import("ui");

/// 滚动区里的一行：宽度跟随对话列，左右与消息同一边距（16，Kaf7E ③），上方一个块间距（10），不收缩。
pub const holder = ui.previewCss("src/features/ai/pane/view/ai_feedback.yss", "holder", @embedFile("ai_feedback.yss"), .{ .width = .fill, .height = .fit, .padding = .{ .top = 10, .right = 16, .bottom = 10, .left = 16 }, .flex_shrink = 0, });
/// 提示与关闭钮一行：提示吃掉剩余宽度（长路径在提示里换行），关闭钮贴右上。
pub const line = ui.previewCss("src/features/ai/pane/view/ai_feedback.yss", "line", @embedFile("ai_feedback.yss"), .{ .width = .fill, .height = .fit, .direction = .row, .align_items = .start, .gap = 4, });
pub const alert = ui.previewCss("src/features/ai/pane/view/ai_feedback.yss", "alert", @embedFile("ai_feedback.yss"), .{ .flex = 1, .min_width = 0, });

//# yix-map ai_feedback.yss
