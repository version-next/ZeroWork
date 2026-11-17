// GENERATED FILE, do not edit: generated from ai_children_rows.yss; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! 子智能体弹层的行（O8 C534cF）与子对话的「任务记录」行：原生 `W.Pressable` 的 `look`，随主题由 zenit 按行自身状态解析
//! （悬停 / 按下的底色是 zenit 交互 token），不再在挂载时把 token 取成定值、也不在主题变化时由视图重设。
const ui = @import("ui");

/// 子智能体行：44 高，左右 8，间距 10，圆角 6；悬停 bg-hover，按下 bg-active。
pub const child_row = ui.previewCss("src/features/ai/sessions/view/ai_children_rows.yss", "child_row", @embedFile("ai_children_rows.yss"), .{ .width = .fill, .height = 44, .flex_shrink = 0, .direction = .row, .align_items = .center, .justify = .start, .padding = .{ .y = 0, .x = 8 }, .gap = 10, .corner_radius = 6, ._hover = .{ .background = ui.tokenRef(.color, "bg-hover"), }, ._active = .{ .background = ui.tokenRef(.color, "bg-active"), }, });
/// 任务记录行：整宽 28 高，间距 6，控件圆角；悬停 / 按下同 ghost 控件的交互底色。
pub const history_row = ui.previewCss("src/features/ai/sessions/view/ai_children_rows.yss", "history_row", @embedFile("ai_children_rows.yss"), .{ .width = .fill, .height = 28, .flex_shrink = 0, .direction = .row, .align_items = .center, .gap = 6, .corner_radius = ui.tokenRef(.radius, "control"), .background = ui.Color.TRANSPARENT, ._hover = .{ .background = ui.tokenRef(.color, "bg-hover"), }, ._active = .{ .background = ui.tokenRef(.color, "button-pressed-bg"), }, });

//# yix-map ai_children_rows.yss
