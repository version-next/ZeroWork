// GENERATED FILE, do not edit: generated from transfer_conflict_styles.yss; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! 同名文件处理对话框（`transfer_conflict.yix`）的布局与正文文字。
//!
//! 对话框面板、遮罩、单选组、输入框、复选框、按钮、提示条、滚动条都是 zenit 原生组件的默认外观；这里只写调用方
//! 自己的盒子（头部一行、正文滚动区的几何、对比卡片、页脚一行）和正文文字，颜色全部是 token。
const ui = @import("ui");

/// 对话框宽度上限；窄窗口里两侧各留 8。
pub const dialog_width: f32 = 480;
pub const window_gutter: f32 = 16;
/// 头部 52 + 页脚 64：正文滚动区之外固定占掉的高度。
pub const chrome_height: f32 = 116;

/// Modal 正文槽里的一列：头部、正文滚动区、页脚。高度随内容，由 Modal 的 maxHeight 封顶。
pub const form = ui.previewCss("src/features/transfer/view/transfer_conflict_styles.yss", "form", @embedFile("transfer_conflict_styles.yss"), .{ .width = .fill, .height = .fit, .min_height = 0, .flex_shrink = 1, .direction = .column, .gap = 0, });
pub const header = ui.previewCss("src/features/transfer/view/transfer_conflict_styles.yss", "header", @embedFile("transfer_conflict_styles.yss"), .{ .width = .fill, .height = 52, .flex_shrink = 0, .direction = .row, .align_items = .center, .gap = 8, .padding = .{ .top = 12, .right = 16, .bottom = 0, .left = 20 }, });
pub const header_icon = ui.previewCss("src/features/transfer/view/transfer_conflict_styles.yss", "header_icon", @embedFile("transfer_conflict_styles.yss"), .{ .width = 18, .height = 18, .flex_shrink = 0, .icon_color = ui.tokenRef(.color, "accent"), });
pub const title = ui.previewCss("src/features/transfer/view/transfer_conflict_styles.yss", "title", @embedFile("transfer_conflict_styles.yss"), .{ .font_size = 15, .font_weight = 600, .line_height = 22.0 / 15.0, .color = ui.tokenRef(.color, "fg-primary"), .wrap = .none, .text_overflow = .ellipsis, .selectable = false, });
pub const title_box = ui.previewCss("src/features/transfer/view/transfer_conflict_styles.yss", "title_box", @embedFile("transfer_conflict_styles.yss"), .{ .width = .fill, .flex = 1, .min_width = 0, });
/// 正文滚动区（原生 ScrollArea 的根）：只给几何——宽度、随内容的高度及其上限、左右留白。
pub const viewport = ui.paramStyle(struct { max: f32, pub const declared = &[_][]const u8{ "width", "height", "min_height", "flex_shrink", "margin", }; pub fn resolve(args: @This(), t: *const ui.theme.Values) ui.BoxStyle { return ui.boxFrom(.{ .width = .fill, .height = .{ .fit = .{ .max = args.max } }, .min_height = 0, .flex_shrink = 1, .margin = .{ .y = 0, .x = 20 }, }, t); } });
/// 滚动内容：一列，间距 8。
pub const body = ui.previewCss("src/features/transfer/view/transfer_conflict_styles.yss", "body", @embedFile("transfer_conflict_styles.yss"), .{ .width = .fill, .height = .fit, .direction = .column, .gap = 8, .min_width = 0, });
pub const stack = ui.previewCss("src/features/transfer/view/transfer_conflict_styles.yss", "stack", @embedFile("transfer_conflict_styles.yss"), .{ .width = .fill, .height = .fit, .direction = .column, .gap = 8, .min_width = 0, .flex_shrink = 0, });
pub const confirmation = ui.previewCss("src/features/transfer/view/transfer_conflict_styles.yss", "confirmation", @embedFile("transfer_conflict_styles.yss"), .{ .width = .fill, .height = .fit, .direction = .column, .gap = 10, .min_width = 0, .flex_shrink = 0, });
/// 原生控件外面的定位盒：占满一行，高度随控件。
pub const field = ui.previewCss("src/features/transfer/view/transfer_conflict_styles.yss", "field", @embedFile("transfer_conflict_styles.yss"), .{ .width = .fill, .height = .fit, .flex_shrink = 0, .direction = .column, });
pub const footer = ui.previewCss("src/features/transfer/view/transfer_conflict_styles.yss", "footer", @embedFile("transfer_conflict_styles.yss"), .{ .width = .fill, .height = 64, .flex_shrink = 0, .direction = .row, .align_items = .center, .justify = .end, .gap = 8, .padding = .{ .top = 12, .right = 20, .bottom = 20, .left = 20 }, });
pub const spacer = ui.previewCss("src/features/transfer/view/transfer_conflict_styles.yss", "spacer", @embedFile("transfer_conflict_styles.yss"), .{ .width = .{ .grow = .{} }, .min_width = 0, .height = 1, });

pub const text_box = ui.previewCss("src/features/transfer/view/transfer_conflict_styles.yss", "text_box", @embedFile("transfer_conflict_styles.yss"), .{ .width = .fill, .height = .fit, .min_width = 0, .flex_shrink = 0, });
pub const caption = ui.previewCss("src/features/transfer/view/transfer_conflict_styles.yss", "caption", @embedFile("transfer_conflict_styles.yss"), .{ .font_size = 12.5, .font_weight = 500, .line_height = 18.0 / 12.5, .color = ui.tokenRef(.color, "fg-primary"), .wrap = .word, .selectable = false, });
pub const path = ui.previewCss("src/features/transfer/view/transfer_conflict_styles.yss", "path", @embedFile("transfer_conflict_styles.yss"), .{ .font_size = 10.5, .font_weight = 400, .line_height = 17.0 / 10.5, .color = ui.tokenRef(.color, "fg-primary"), .wrap = .char, .use_monospace_font = true, .selectable = true, });
pub const detail = ui.previewCss("src/features/transfer/view/transfer_conflict_styles.yss", "detail", @embedFile("transfer_conflict_styles.yss"), .{ .font_size = 10.5, .font_weight = 400, .line_height = 17.0 / 10.5, .color = ui.tokenRef(.color, "fg-secondary"), .wrap = .word, .selectable = false, });
pub const metadata = ui.previewCss("src/features/transfer/view/transfer_conflict_styles.yss", "metadata", @embedFile("transfer_conflict_styles.yss"), .{ .font_size = 11.5, .font_weight = 400, .line_height = 18.0 / 11.5, .color = ui.tokenRef(.color, "fg-secondary"), .wrap = .word, .selectable = false, });
pub const issue = ui.previewCss("src/features/transfer/view/transfer_conflict_styles.yss", "issue", @embedFile("transfer_conflict_styles.yss"), .{ .font_size = 10.5, .font_weight = 400, .line_height = 17.0 / 10.5, .color = ui.tokenRef(.color, "danger"), .wrap = .word, .selectable = false, });

/// 对比卡片：两张并排，间距 10。
pub const compare = ui.previewCss("src/features/transfer/view/transfer_conflict_styles.yss", "compare", @embedFile("transfer_conflict_styles.yss"), .{ .width = .fill, .height = .fit, .direction = .row, .gap = 10, .min_width = 0, .flex_shrink = 0, });
pub const compare_card = ui.previewCss("src/features/transfer/view/transfer_conflict_styles.yss", "compare_card", @embedFile("transfer_conflict_styles.yss"), .{ .width = .fill, .flex = 1, .height = .fit, .min_width = 0, .direction = .column, .gap = 6, .padding = 10, .background = ui.tokenRef(.color, "zw-island-rest"), .corner_radius = 8, .overflow = .hidden, });
pub const compare_head = ui.previewCss("src/features/transfer/view/transfer_conflict_styles.yss", "compare_head", @embedFile("transfer_conflict_styles.yss"), .{ .width = .fill, .height = .fit, .direction = .row, .align_items = .center, .gap = 8, .min_width = 0, });
pub const compare_icon = ui.previewCss("src/features/transfer/view/transfer_conflict_styles.yss", "compare_icon", @embedFile("transfer_conflict_styles.yss"), .{ .width = 24, .height = 24, .flex_shrink = 0, .icon_color = ui.tokenRef(.color, "fg-secondary"), });
pub const compare_titles = ui.previewCss("src/features/transfer/view/transfer_conflict_styles.yss", "compare_titles", @embedFile("transfer_conflict_styles.yss"), .{ .width = .fill, .flex = 1, .min_width = 0, .direction = .column, .gap = 1, });
pub const compare_title = ui.previewCss("src/features/transfer/view/transfer_conflict_styles.yss", "compare_title", @embedFile("transfer_conflict_styles.yss"), .{ .font_size = 12.5, .font_weight = 600, .line_height = 16.0 / 12.5, .color = ui.tokenRef(.color, "fg-primary"), .wrap = .none, .text_overflow = .ellipsis, .selectable = false, });
pub const compare_place = ui.previewCss("src/features/transfer/view/transfer_conflict_styles.yss", "compare_place", @embedFile("transfer_conflict_styles.yss"), .{ .font_size = 10.5, .font_weight = 400, .line_height = 14.0 / 10.5, .color = ui.tokenRef(.color, "fg-secondary"), .wrap = .none, .text_overflow = .ellipsis, .selectable = false, });
pub const compare_meta = ui.previewCss("src/features/transfer/view/transfer_conflict_styles.yss", "compare_meta", @embedFile("transfer_conflict_styles.yss"), .{ .width = .fill, .height = .fit, .direction = .column, .min_width = 0, });
pub const compare_row = ui.previewCss("src/features/transfer/view/transfer_conflict_styles.yss", "compare_row", @embedFile("transfer_conflict_styles.yss"), .{ .width = .fill, .height = 20, .direction = .row, .align_items = .center, .gap = 8, .min_width = 0, });
pub const compare_key = ui.previewCss("src/features/transfer/view/transfer_conflict_styles.yss", "compare_key", @embedFile("transfer_conflict_styles.yss"), .{ .font_size = 12, .font_weight = 400, .line_height = 16.0 / 12.0, .color = ui.tokenRef(.color, "fg-secondary"), .wrap = .none, .selectable = false, });
pub const compare_key_box = ui.previewCss("src/features/transfer/view/transfer_conflict_styles.yss", "compare_key_box", @embedFile("transfer_conflict_styles.yss"), .{ .flex_shrink = 0, });
pub const compare_value = ui.previewCss("src/features/transfer/view/transfer_conflict_styles.yss", "compare_value", @embedFile("transfer_conflict_styles.yss"), .{ .font_size = 12, .font_weight = 400, .line_height = 16.0 / 12.0, .color = ui.tokenRef(.color, "fg-primary"), .wrap = .none, .text_overflow = .ellipsis, .text_align = .end, .selectable = false, });
pub const compare_value_box = ui.previewCss("src/features/transfer/view/transfer_conflict_styles.yss", "compare_value_box", @embedFile("transfer_conflict_styles.yss"), .{ .width = .fill, .flex = 1, .min_width = 0, .overflow = .hidden, });

pub const anchor = ui.previewCss("src/features/transfer/view/transfer_conflict_styles.yss", "anchor", @embedFile("transfer_conflict_styles.yss"), .{ .position = .absolute, .width = 0, .height = 0, });

//# yix-map transfer_conflict_styles.yss
