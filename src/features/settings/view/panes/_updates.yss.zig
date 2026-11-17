// GENERATED FILE, do not edit: generated from updates.yss; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! 关于与更新面板（P3 3e 第二批）的样式：版本卡（应用图标、名称、版本行、更新块）。
//! 状态徽标是原生 `W.Tag`、检查更新是原生 primary `W.Button`（默认外观，不覆盖）、发布来源是原生 link 按钮；
//! 这里只有布局盒子与文字。几何沿用旧 `settings_updates_styles`（`Vbefc`）；颜色全部是 token。
const ui = @import("ui");

/// 版本卡（`Vbefc` › Body）：内边距 14、间距 14、圆角 12，窗面静止底色（同其它面板的正文卡片）。
pub const card = ui.previewCss("src/features/settings/view/panes/updates.yss", "card", @embedFile("updates.yss"), .{ .width = .fill, .direction = .column, .gap = 14, .padding = 14, .corner_radius = 12, .background = ui.tokenRef(.color, "zw-window-rest"), .overflow = .hidden, .flex_shrink = 0, .min_width = 0, });
/// 身份行（`sPPyy`）：64pt 应用图标 + 名称 / 版本，间距 14。
pub const identity = ui.previewCss("src/features/settings/view/panes/updates.yss", "identity", @embedFile("updates.yss"), .{ .width = .fill, .direction = .row, .align_items = .center, .gap = 14, .flex_shrink = 0, .min_width = 0, });
/// 应用图标（`Ebev1`）：64、圆角 14，品牌对角渐变（`zw-primary*` token；图标墨色 `zw-primary-fg`），终端图标 30。
pub const app_mark = ui.previewCss("src/features/settings/view/panes/updates.yss", "app_mark", @embedFile("updates.yss"), .{ .width = 64, .height = 64, .flex_shrink = 0, .direction = .row, .align_items = .center, .justify = .center, .corner_radius = 14, .background = ui.tokenRef(.color, "zw-primary"), .gradient = .{ .from = ui.tokenRef(.color, "zw-primary"), .to = ui.tokenRef(.color, "zw-primary-to"), .direction = .diagonal }, });
pub const app_mark_icon = ui.previewCss("src/features/settings/view/panes/updates.yss", "app_mark_icon", @embedFile("updates.yss"), .{ .width = 30, .height = 30, .icon_color = ui.tokenRef(.color, "zw-primary-fg"), });
pub const identity_text = ui.previewCss("src/features/settings/view/panes/updates.yss", "identity_text", @embedFile("updates.yss"), .{ .width = .fill, .flex = 1, .min_width = 0, .direction = .column, .gap = 3, });
pub const app_name = ui.previewCss("src/features/settings/view/panes/updates.yss", "app_name", @embedFile("updates.yss"), .{ .font_size = 18, .font_weight = 600, .line_height = 24.0 / 18.0, .color = ui.tokenRef(.color, "fg-primary"), });
pub const version_text = ui.previewCss("src/features/settings/view/panes/updates.yss", "version_text", @embedFile("updates.yss"), .{ .font_size = 11.5, .font_weight = 400, .line_height = 17.0 / 11.5, .color = ui.tokenRef(.color, "zw-fg-supporting"), .wrap = .word, });
pub const version_text_box = ui.previewCss("src/features/settings/view/panes/updates.yss", "version_text_box", @embedFile("updates.yss"), .{ .width = .fill, .min_width = 0, });
/// 更新块（`vUN0f`）：圆角 10、内边距 [14, 16]、间距 12；有可用的新版本时换成强调面，否则是输入面。
pub const Banner = ui.previewCva("src/features/settings/view/panes/updates.yss", "Banner", @embedFile("updates.yss"), .{ .base = .{ .width = .fill, .direction = .row, .align_items = .center, .gap = 12, .padding = .{ .y = 14, .x = 16 }, .corner_radius = 10, .background = ui.tokenRef(.color, "bg-primary"), .flex_shrink = 0, .min_width = 0, }, .variants = .{ .available = .{ .false = .{ }, .true = .{ .background = ui.tokenRef(.color, "accent-tag-bg"), }, }, }, .defaults = .{ .available = false, }, });
pub const banner_text = ui.previewCss("src/features/settings/view/panes/updates.yss", "banner_text", @embedFile("updates.yss"), .{ .width = .fill, .flex = 1, .min_width = 0, .direction = .column, .gap = 2, });
pub const banner_title = ui.previewCss("src/features/settings/view/panes/updates.yss", "banner_title", @embedFile("updates.yss"), .{ .font_size = 14, .font_weight = 600, .line_height = 20.0 / 14.0, .color = ui.tokenRef(.color, "fg-primary"), .wrap = .word, });
pub const banner_note = ui.previewCss("src/features/settings/view/panes/updates.yss", "banner_note", @embedFile("updates.yss"), .{ .font_size = 12, .font_weight = 400, .line_height = 1.5, .color = ui.tokenRef(.color, "zw-fg-supporting"), .wrap = .word, });

//# yix-map updates.yss
