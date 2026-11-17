// GENERATED FILE, do not edit: generated from keys.yss; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! 快捷键面板（P3 3e 第二批，人工验收反馈第 7 条）的样式：键帽区与行下的说明。
//! 键帽本身是原生 `W.Kbd`（sm，色调随录制状态），按钮是原生 `W.Button`，这里只给 `W.Pressable` 根（它没有自己的外观）
//! 与布局盒子定外观；颜色全部是 token。
const ui = @import("ui");

/// 键帽区（`W.Pressable` 根）：键帽 + 录制提示 + 铅笔，gap 4，圆角 6。静止透明（只有一圈透明描边占位，状态切换不跳），
/// 悬停 / 按下 bg-hover / bg-active；录制中 accent 描边、无效 danger 描边、冲突 warning 描边；固定动作没有悬停反馈。
pub const KeyArea = ui.previewCva("src/features/settings/view/panes/keys.yss", "KeyArea", @embedFile("keys.yss"), .{ .base = .{ .min_height = 28, .flex_shrink = 0, .direction = .row, .align_items = .center, .gap = 4, .padding = .{ .y = 2, .x = 6 }, .corner_radius = 6, .background = ui.Color.TRANSPARENT, .border_width = 1, .border_color = ui.Color.TRANSPARENT, .transition = ui.transition("background 150ms ease-out"), ._hover = .{ .background = ui.tokenRef(.color, "bg-hover"), }, ._active = .{ .background = ui.tokenRef(.color, "bg-active"), }, }, .variants = .{ .tone = .{ .rest = .{ }, .recording = .{ .border_width = 1, .border_color = ui.tokenRef(.color, "accent"), .background = ui.tokenRef(.color, "bg-primary"), ._hover = .{ .background = ui.tokenRef(.color, "bg-primary"), }, }, .invalid = .{ .border_width = 1, .border_color = ui.tokenRef(.color, "danger"), .background = ui.tokenRef(.color, "bg-primary"), ._hover = .{ .background = ui.tokenRef(.color, "bg-primary"), }, }, .conflict = .{ .border_width = 1, .border_color = ui.tokenRef(.color, "warning"), .background = ui.tokenRef(.color, "bg-primary"), ._hover = .{ .background = ui.tokenRef(.color, "bg-primary"), }, }, }, .fixed = .{ .false = .{ }, .true = .{ ._hover = .{ .background = ui.Color.TRANSPARENT, }, ._active = .{ .background = ui.Color.TRANSPARENT, }, }, }, }, .defaults = .{ .tone = .rest, .fixed = false, }, });
/// 键帽区右侧的铅笔：淡墨，提示“可以改”；录制中 / 固定动作不显示。
pub const key_pencil = ui.previewCss("src/features/settings/view/panes/keys.yss", "key_pencil", @embedFile("keys.yss"), .{ .width = 12, .height = 12, .flex_shrink = 0, .icon_color = ui.tokenRef(.color, "zw-fg-supporting"), });
/// 录制中的提示：“按下新快捷键…”（12，accent 墨）与“Esc 取消”（11，淡墨）。
pub const key_prompt = ui.previewCss("src/features/settings/view/panes/keys.yss", "key_prompt", @embedFile("keys.yss"), .{ .font_size = 12, .font_weight = 500, .line_height = 16.0 / 12.0, .color = ui.tokenRef(.color, "accent"), .wrap = .none, });
pub const key_escape = ui.previewCss("src/features/settings/view/panes/keys.yss", "key_escape", @embedFile("keys.yss"), .{ .font_size = 11, .font_weight = 400, .line_height = 16.0 / 11.0, .color = ui.tokenRef(.color, "zw-fg-supporting"), .wrap = .none, });
/// 行尾“恢复默认”的位置：固定 24 宽，按钮出现 / 消失时键帽区不左右跳。
pub const key_reset_slot = ui.previewCss("src/features/settings/view/panes/keys.yss", "key_reset_slot", @embedFile("keys.yss"), .{ .width = 24, .height = 24, .flex_shrink = 0, .direction = .row, .align_items = .center, .justify = .center, });
/// 行下的说明行（无效原因 / 冲突 + 交换 / 取消），与标签左对齐。
pub const key_problem = ui.previewCss("src/features/settings/view/panes/keys.yss", "key_problem", @embedFile("keys.yss"), .{ .width = .fill, .min_width = 0, .direction = .row, .align_items = .center, .gap = 8, .padding = .{ .top = 0, .right = 0, .bottom = 10, .left = 0 }, });
pub const key_problem_text = ui.previewCss("src/features/settings/view/panes/keys.yss", "key_problem_text", @embedFile("keys.yss"), .{ .font_size = 11.5, .font_weight = 400, .line_height = 16.0 / 11.5, .color = ui.tokenRef(.color, "danger"), .wrap = .word, });
pub const key_problem_text_box = ui.previewCss("src/features/settings/view/panes/keys.yss", "key_problem_text_box", @embedFile("keys.yss"), .{ .width = .fill, .flex = 1, .min_width = 0, });
/// 冲突说明用 warning 墨（不是错误：给出了一步解决）。
pub const key_conflict_text = ui.previewCss("src/features/settings/view/panes/keys.yss", "key_conflict_text", @embedFile("keys.yss"), .{ .font_size = 11.5, .font_weight = 400, .line_height = 16.0 / 11.5, .color = ui.tokenRef(.color, "warning"), .wrap = .word, });
/// 键帽区的外层（Tooltip 的触发点）；不占额外空间。
pub const key_slot = ui.previewCss("src/features/settings/view/panes/keys.yss", "key_slot", @embedFile("keys.yss"), .{ .flex_shrink = 0, .direction = .row, .align_items = .center, });

//# yix-map keys.yss
