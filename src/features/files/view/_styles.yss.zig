// GENERATED FILE, do not edit: generated from styles.yss; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! SFTP file workspace, Island B v3 (Pencil `c0vKlM` SFTP · 列表视图,
//! `OQD5Y` 多选与右键菜单). Reusable parts: `QGtx5` Pane Header, `tVVKV`
//! Files / Toolbar, `GW9no` Files / Header, `Che9A` Files / Row, path bar.
//! Values are the design's numbers; colors are zenit semantic tokens plus
//! ZeroWork's zw-* island tokens. Theme-ink text keeps app_theme roles.
const ui = @import("ui");

/// View island interior: padding 4, panes gap 4.
pub const root = ui.previewCss("src/features/files/view/styles.yss", "root", @embedFile("styles.yss"), .{ .width = .fill, .height = .fill, .min_width = 0, .min_height = 0, .direction = .row, .gap = 4, .padding = 4, .background = ui.Color.TRANSPARENT, });
/// One side: file pane over an optional transfer card, gap 4. `flex: 1` only sets the grow factor; with the
/// default `flex-basis: auto` each side would start from its own content width and the two sides would differ
/// by the difference of their contents (583.4 / 598.6 at 1194). Basis 0 makes the row split evenly.
pub const column_stack = ui.previewCss("src/features/files/view/styles.yss", "column_stack", @embedFile("styles.yss"), .{ .width = .fill, .height = .fill, .flex = 1, .flex_basis = 0, .min_width = 0, .min_height = 0, .direction = .column, .gap = 4, });
/// Pane (Pane · 本地文件 / 远程文件): radius 8, 1px bg-active hairline.
pub const card = ui.previewCss("src/features/files/view/styles.yss", "card", @embedFile("styles.yss"), .{ .width = .fill, .height = .fill, .flex = 1, .min_width = 0, .min_height = 0, .direction = .column, .gap = 0, .padding = 0, .background = ui.tokenRef(.color, "zw-island-focus"), .corner_radius = 8, .border_overlay = true, .border_width = 1, .border_color = ui.tokenRef(.color, "bg-active"), .overflow = .hidden, });
/// Pane Header (QGtx5 in the pane): 30 high, padding [0, 4, 0, 12], gap 6.
pub const pane_header = ui.previewCss("src/features/files/view/styles.yss", "pane_header", @embedFile("styles.yss"), .{ .width = .fill, .height = 30, .flex_shrink = 0, .min_width = 0, .direction = .row, .align_items = .center, .gap = 6, .padding = .{ .top = 0, .right = 4, .bottom = 0, .left = 12 }, .background = ui.Color.TRANSPARENT, });
/// Files / Toolbar (tVVKV): 44 high, padding [0, 10], gap 4.
pub const toolbar = ui.previewCss("src/features/files/view/styles.yss", "toolbar", @embedFile("styles.yss"), .{ .width = .fill, .height = 44, .flex_shrink = 0, .min_width = 0, .direction = .row, .align_items = .center, .gap = 4, .padding = .{ .y = 0, .x = 10 }, .background = ui.Color.TRANSPARENT, });
/// Files / Header (GW9no): 26 high, bottom bg-active hairline.
pub const header_clip = ui.previewCss("src/features/files/view/styles.yss", "header_clip", @embedFile("styles.yss"), .{ .width = .fill, .height = 26, .flex_shrink = 0, .overflow = .hidden, .border_overlay = true, .border_bottom_width = 1, .border_color = ui.tokenRef(.color, "bg-active"), });
/// Path bar: 28 high, top bg-active hairline, padding [0, 12], gap 4.
pub const path_bar = ui.previewCss("src/features/files/view/styles.yss", "path_bar", @embedFile("styles.yss"), .{ .width = .fill, .height = 28, .flex_shrink = 0, .min_width = 0, .direction = .row, .align_items = .center, .gap = 4, .padding = .{ .y = 0, .x = 12 }, .border_overlay = true, .border_top_width = 1, .border_color = ui.tokenRef(.color, "bg-active"), .background = ui.Color.TRANSPARENT, });
/// Breadcrumb frame inside the path bar (click to edit the path).
pub const path_field = ui.previewCss("src/features/files/view/styles.yss", "path_field", @embedFile("styles.yss"), .{ .width = .fill, .height = 28, .flex = 1, .min_width = 0, .direction = .row, .align_items = .center, .gap = 0, .padding = 0, .background = ui.Color.TRANSPARENT, .overflow = .hidden, });
/// Status group at the path bar end (summary · status).
pub const path_status = ui.previewCss("src/features/files/view/styles.yss", "path_status", @embedFile("styles.yss"), .{ .height = 28, .flex_shrink = 1, .min_width = 0, .direction = .row, .align_items = .center, .gap = 8, .overflow = .hidden, });
/// Pane title badge: 18 high, radius 6, bg-active tint.
pub const badge = ui.previewCss("src/features/files/view/styles.yss", "badge", @embedFile("styles.yss"), .{ .height = 18, .padding = .{ .y = 0, .x = 6 }, .align_items = .center, .justify = .center, .background = ui.tokenRef(.color, "bg-active"), .corner_radius = 6, .flex_shrink = 1, .min_width = 0, .max_width = 150, .overflow = .hidden, });

//# yix-map styles.yss
