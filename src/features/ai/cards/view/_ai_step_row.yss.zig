// GENERATED FILE, do not edit: generated from ai_step_row.yss; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! 步骤行（Pencil Kaf7E A6）：工具卡 / 执行结果卡 / 步骤的表头行与工具卡的目标行都是原生 `W.Pressable`（按钮语义、
//! 子元素即内容），这里是它们的 `look`——随主题由 zenit 按根自身状态解析（悬停 / 按下的底色用 zenit 交互 token），
//! 不再把原生 Button 当容器、隐藏它的子节点，也不在主题变化时由卡片重算外观。
const ui = @import("ui");

/// 表头行：24 高，左右 6，间距 6，圆角 6；整行展开 / 收起详情。
pub const step_row = ui.previewCss("src/features/ai/cards/view/ai_step_row.yss", "step_row", @embedFile("ai_step_row.yss"), .{ .width = .fill, .height = 24, .flex_shrink = 0, .direction = .row, .align_items = .center, .justify = .start, .padding = .{ .y = 0, .x = 6 }, .gap = 6, .corner_radius = 6, .background = ui.Color.TRANSPARENT, ._hover = .{ .background = ui.tokenRef(.color, "bg-hover"), }, ._active = .{ .background = ui.tokenRef(.color, "button-pressed-bg"), }, });
/// 工具卡的目标行（Figma 16 / 186 / 6 / fill 的槽位在内容里）：26 高，圆角 4。
pub const target_row = ui.previewCss("src/features/ai/cards/view/ai_step_row.yss", "target_row", @embedFile("ai_step_row.yss"), .{ .width = .fill, .height = 26, .flex_shrink = 0, .direction = .row, .align_items = .center, .justify = .start, .gap = 6, .corner_radius = 4, .background = ui.Color.TRANSPARENT, ._hover = .{ .background = ui.tokenRef(.color, "bg-hover"), }, ._active = .{ .background = ui.tokenRef(.color, "button-pressed-bg"), }, });

//# yix-map ai_step_row.yss
