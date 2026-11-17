// GENERATED FILE, do not edit: generated from connection_stepper.yss; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! 连接编辑器步骤条（SSH/SFTP 与 BMC 共用）的步骤行：原生 `W.Pressable` 的 `look`，随主题由 zenit 解析。
//! 当前 / 完成 / 无效只改徽标与标题（视图按进度切换），步骤行本身在各状态下外观相同、没有悬停底色。
const ui = @import("ui");

/// 步骤行（Island B v3 安静步骤条）：按内容宽、36 高，徽标与标题间距 10，圆角 7，透明底。
pub const step = ui.previewCss("src/features/connections/wizard/view/connection_stepper.yss", "step", @embedFile("connection_stepper.yss"), .{ .width = .fit, .flex = 0, .min_width = 0, .height = 36, .padding = 0, .flex_shrink = 0, .direction = .row, .align_items = .center, .justify = .start, .gap = 10, .corner_radius = 7, .background = ui.Color.TRANSPARENT, });

//# yix-map connection_stepper.yss
