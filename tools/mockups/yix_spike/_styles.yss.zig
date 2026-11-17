// GENERATED FILE, do not edit: generated from styles.yss; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! yix_spike 样式（只求可读，不追设计稿）。
const ui = @import("ui");

pub const root = ui.previewCss("tools/mockups/yix_spike/styles.yss", "root", @embedFile("styles.yss"), .{ .width = .fill, .height = .fill, .direction = .column, .gap = ui.tokenRef(.space, "space200"), .padding = ui.tokenRef(.space, "space400"), .background = ui.tokenRef(.color, "bg-primary"), });
pub const section = ui.previewCss("tools/mockups/yix_spike/styles.yss", "section", @embedFile("styles.yss"), .{ .direction = .column, .gap = ui.tokenRef(.space, "space100"), .padding = ui.tokenRef(.space, "space200"), .border_width = ui.tokenRef(.border_width, "thin"), .border_color = ui.tokenRef(.color, "border"), .corner_radius = ui.tokenRef(.radius, "md"), .background = ui.tokenRef(.color, "bg-secondary"), });
pub const section_row = ui.previewCss("tools/mockups/yix_spike/styles.yss", "section_row", @embedFile("styles.yss"), .{ .direction = .row, .gap = ui.tokenRef(.space, "space200"), .align_items = .center, });
pub const heading = ui.previewCss("tools/mockups/yix_spike/styles.yss", "heading", @embedFile("styles.yss"), .{ .font_size = ui.tokenRef(.font_size, "sm"), .font_weight = ui.tokenRef(.font_weight, "semibold"), .color = ui.tokenRef(.color, "fg-primary"), });
pub const body_text = ui.previewCss("tools/mockups/yix_spike/styles.yss", "body_text", @embedFile("styles.yss"), .{ .font_size = ui.tokenRef(.font_size, "sm"), .color = ui.tokenRef(.color, "fg-primary"), });
pub const muted = ui.previewCss("tools/mockups/yix_spike/styles.yss", "muted", @embedFile("styles.yss"), .{ .font_size = ui.tokenRef(.font_size, "sm"), .color = ui.tokenRef(.color, "fg-secondary"), });
pub const header = ui.previewCss("tools/mockups/yix_spike/styles.yss", "header", @embedFile("styles.yss"), .{ .width = .fill, .height = 40, .direction = .row, .gap = ui.tokenRef(.space, "space200"), .align_items = .center, .padding = .{ .top = 0, .right = ui.tokenRef(.space, "space400"), .bottom = 0, .left = 80 }, .background = ui.tokenRef(.color, "bg-tertiary"), });
pub const chip = ui.previewCss("tools/mockups/yix_spike/styles.yss", "chip", @embedFile("styles.yss"), .{ .padding = .{ .y = ui.tokenRef(.space, "space100"), .x = ui.tokenRef(.space, "space200") }, .corner_radius = ui.tokenRef(.radius, "sm"), .border_width = ui.tokenRef(.border_width, "thin"), .border_color = ui.tokenRef(.color, "border"), });

//# yix-map styles.yss
