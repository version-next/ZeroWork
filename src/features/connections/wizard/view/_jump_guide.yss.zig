// GENERATED FILE, do not edit: generated from jump_guide.yss; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! 跳板引导（`jump_guide.yix`）的布局与文字：按钮、告警、通知栈都是 zenit 原生默认外观，这里只排盒子与文字层级（颜色只用 token）。
//! 尺寸照 Pencil RDiob › Li7pX：空态卡片在本机与目标之间，内边距 24，内容居中。
const ui = @import("ui");

/// 模板根：空态卡片；通知栈挂到窗口浮层根（portal），不占位。
pub const holder = ui.previewCss("src/features/connections/wizard/view/jump_guide.yss", "holder", @embedFile("jump_guide.yss"), .{ .width = .fill, .direction = .column, });
pub const empty = ui.previewCss("src/features/connections/wizard/view/jump_guide.yss", "empty", @embedFile("jump_guide.yss"), .{ .width = .fill, .direction = .column, .align_items = .center, .gap = 8, .padding = .{ .top = 20, .right = 24, .bottom = 20, .left = 24 }, .background = ui.tokenRef(.color, "bg-secondary"), .corner_radius = 10, });
pub const badge = ui.previewCss("src/features/connections/wizard/view/jump_guide.yss", "badge", @embedFile("jump_guide.yss"), .{ .width = 32, .height = 32, .corner_radius = 16, .align_items = .center, .justify = .center, .background = ui.tokenRef(.color, "accent-subtle"), });
pub const badge_icon = ui.previewCss("src/features/connections/wizard/view/jump_guide.yss", "badge_icon", @embedFile("jump_guide.yss"), .{ .width = 16, .height = 16, .icon_color = ui.tokenRef(.color, "accent"), });
pub const title = ui.previewCss("src/features/connections/wizard/view/jump_guide.yss", "title", @embedFile("jump_guide.yss"), .{ .font_size = 13, .font_weight = 600, .color = ui.tokenRef(.color, "fg-primary"), });
pub const detail = ui.previewCss("src/features/connections/wizard/view/jump_guide.yss", "detail", @embedFile("jump_guide.yss"), .{ .font_size = 12, .color = ui.tokenRef(.color, "fg-secondary"), .text_align = .center, .wrap = .word, });
pub const detail_box = ui.previewCss("src/features/connections/wizard/view/jump_guide.yss", "detail_box", @embedFile("jump_guide.yss"), .{ .width = .fill, });
pub const actions = ui.previewCss("src/features/connections/wizard/view/jump_guide.yss", "actions", @embedFile("jump_guide.yss"), .{ .direction = .row, .align_items = .center, .gap = 8, .padding = .{ .top = 4, .right = 0, .bottom = 0, .left = 0 }, });
pub const banner = ui.previewCss("src/features/connections/wizard/view/jump_guide.yss", "banner", @embedFile("jump_guide.yss"), .{ .width = .fill, .padding = .{ .top = 0, .right = 0, .bottom = 8, .left = 0 }, });
pub const footer = ui.previewCss("src/features/connections/wizard/view/jump_guide.yss", "footer", @embedFile("jump_guide.yss"), .{ .width = .fill, .direction = .row, .align_items = .center, .gap = 8, .padding = .{ .top = 12, .right = 16, .bottom = 12, .left = 16 }, .border_top_width = 1, .border_color = ui.tokenRef(.color, "border"), });
pub const hint = ui.previewCss("src/features/connections/wizard/view/jump_guide.yss", "hint", @embedFile("jump_guide.yss"), .{ .font_size = 12, .color = ui.tokenRef(.color, "fg-secondary"), });
pub const hint_box = ui.previewCss("src/features/connections/wizard/view/jump_guide.yss", "hint_box", @embedFile("jump_guide.yss"), .{ .width = .{ .grow = .{} }, .min_width = 0, });

//# yix-map jump_guide.yss
