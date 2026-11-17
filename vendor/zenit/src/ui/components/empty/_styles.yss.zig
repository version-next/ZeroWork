// GENERATED FILE, do not edit: generated from styles.yss; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! Empty state styling: centered column, tertiary icon, primary title, secondary description;
//! all ink and type from tokens. View in empty.yix.
const ui = @import("../../ui.zig");

/// Fills the space it is given and centers the content vertically; each line centers itself.
pub const root = ui.previewCss("src/ui/components/empty/styles.yss", "root", @embedFile("styles.yss"), .{ .width = .fill, .height = .fill, .min_width = 0, .min_height = 0, .direction = .column, .justify = .center, .gap = ui.tokenRef(.space, "space200"), .padding = ui.tokenRef(.space, "space400"), });
/// One centered line (icon / copy column / action).
pub const line = ui.previewCss("src/ui/components/empty/styles.yss", "line", @embedFile("styles.yss"), .{ .width = .fill, .min_width = 0, .height = .fit, .direction = .row, .justify = .center, });
/// 24 × 24 glyph in the tertiary ink (quiet, not a status color).
pub const icon = ui.previewCss("src/ui/components/empty/styles.yss", "icon", @embedFile("styles.yss"), .{ .width = 24, .height = 24, .flex_shrink = 0, .icon_color = ui.tokenRef(.color, "fg-tertiary"), });
/// Title and description share one column, at most 280 wide; lines are centered.
pub const copy = ui.previewCss("src/ui/components/empty/styles.yss", "copy", @embedFile("styles.yss"), .{ .width = .fill, .max_width = 280, .min_width = 0, .height = .fit, .direction = .column, .gap = ui.tokenRef(.space, "space100"), });
pub const title = ui.previewCss("src/ui/components/empty/styles.yss", "title", @embedFile("styles.yss"), .{ .width = .fill, .min_width = 0, .font_size = 13, .font_weight = 500, .line_height = 1.4, .color = ui.tokenRef(.color, "fg-primary"), .wrap = .word, .text_align = .center, .selectable = false, });
/// The description is required by design: it says what will appear here, or what to do.
pub const description = ui.previewCss("src/ui/components/empty/styles.yss", "description", @embedFile("styles.yss"), .{ .width = .fill, .min_width = 0, .font_size = 12, .line_height = 1.5, .color = ui.tokenRef(.color, "fg-secondary"), .wrap = .word, .text_align = .center, .selectable = false, });
/// The action sits 4 below the description (gap + 4).
pub const action = ui.previewCss("src/ui/components/empty/styles.yss", "action", @embedFile("styles.yss"), .{ .width = .fill, .height = .fit, .direction = .row, .justify = .center, .padding = .{ .top = ui.tokenRef(.space, "space100"), .right = 0, .bottom = 0, .left = 0 }, });

//# yix-map styles.yss
