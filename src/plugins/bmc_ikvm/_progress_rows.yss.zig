// GENERATED FILE, do not edit: generated from progress_rows.yss; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! 连接进度的分组标题行：原生 `W.Pressable` 的 `look`（随主题由 zenit 按行自身状态解析）。
//! 当前步骤的底色画在行外的背板上（视图按进度状态切换），这一行本身没有悬停 / 按下底色。
const ui = @import("ui");

/// 分组标题行：整宽、按内容高（至少 34），上下 8 左右 10，间距 8，圆角 8；状态 / 名称 / 时长 / 展开列是它的内容。
pub const progress_step = ui.previewCss("src/plugins/bmc_ikvm/progress_rows.yss", "progress_step", @embedFile("progress_rows.yss"), .{ .width = .fill, .height = .fit, .min_height = 34, .min_width = 0, .flex_shrink = 0, .justify = .start, .gap = 8, .padding = .{ .y = 8, .x = 10 }, .corner_radius = 8, });

//# yix-map progress_rows.yss
