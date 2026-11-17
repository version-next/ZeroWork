// GENERATED FILE, do not edit: generated from styles.yss; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! ZeroWork window shell, Island B v3 (Pencil `aPxql` 本地终端, 1440×900).
//! The sidebar starts at the window top (the native traffic lights sit in
//! its header); the content column is a 44pt view bar over a stage whose
//! focused island carries the workspace. Values are the design's numbers;
//! colors are zenit semantic tokens plus ZeroWork's zw-* island tokens.
const ui = @import("ui");

/// Window root. It paints nothing: the ground between islands is the window background layer
/// (`appearance.background`, features/shell/view/background_layers.zig), so the wallpaper and
/// its tint show through.
///
/// `flex-basis: 0; min-height: 0`: the root is a growing item of the runtime's viewport column. With the default
/// automatic minimum (its content's min-content height) a long sidebar list made the whole shell taller than the
/// window — the list then had nothing to scroll and the sidebar footer and the rows below the fold were unreachable
/// (zenit MIGRATION「明确填充和固定留白」: the outermost root mounted into the viewport host must state this).
pub const root = ui.previewCss("src/features/shell/view/shell/styles.yss", "root", @embedFile("styles.yss"), .{ .width = .fill, .height = .fill, .flex_basis = 0, .min_height = 0, .direction = .column, .gap = 0, .padding = 0, });
/// Sidebar | content.
pub const body = ui.previewCss("src/features/shell/view/shell/styles.yss", "body", @embedFile("styles.yss"), .{ .width = .fill, .height = .fill, .flex = 1, .min_height = 0, .direction = .row, .gap = 0, });

/// Sidebar column: 264 wide, transparent over the ground.
pub const sidebar = ui.previewCss("src/features/shell/view/shell/styles.yss", "sidebar", @embedFile("styles.yss"), .{ .width = 264, .height = .fill, .flex_shrink = 0, .direction = .column, .overflow = .hidden, });
/// Sidebar content: padding [12, 8], gap 12.
pub const sidebar_full = ui.previewCss("src/features/shell/view/shell/styles.yss", "sidebar_full", @embedFile("styles.yss"), .{ .width = .fill, .height = .fill, .min_height = 0, .direction = .column, .align_items = .stretch, .gap = ui.tokenRef(.space, "space300"), .padding = .{ .y = ui.tokenRef(.space, "space300"), .x = ui.tokenRef(.space, "space200") }, });
/// Sidebar header row (28): traffic lights (6 + 52) and the toggle (6 + 24 + 6) precede the title.
pub const sidebar_header = ui.previewCss("src/features/shell/view/shell/styles.yss", "sidebar_header", @embedFile("styles.yss"), .{ .height = 28, .direction = .row, .align_items = .center, .gap = ui.tokenRef(.space, "space150"), .padding = .{ .top = 0, .right = ui.tokenRef(.space, "space150"), .bottom = 0, .left = 94 }, .flex_shrink = 0, });

/// View bar: 44 high, padding [0, 6, 0, 12]; tabs sit on the island edge.
pub const view_bar = ui.previewCss("src/features/shell/view/shell/styles.yss", "view_bar", @embedFile("styles.yss"), .{ .width = .fill, .height = 44, .flex_shrink = 0, .direction = .row, .align_items = .end, .padding = .{ .top = 0, .right = ui.tokenRef(.space, "space150"), .bottom = 0, .left = ui.tokenRef(.space, "space300") }, .background = ui.Color.TRANSPARENT, });
/// Tab strip: tabs bottom-aligned, gap 2.
pub const tabs = ui.previewCss("src/features/shell/view/shell/styles.yss", "tabs", @embedFile("styles.yss"), .{ .direction = .row, .align_items = .end, .gap = 2, .height = .fill, .background = ui.Color.TRANSPARENT, });
/// Toolbar controls: gap 8, 4pt above the island; holds zenit's native md icon buttons (32 × 32).
pub const toolbar = ui.previewCss("src/features/shell/view/shell/styles.yss", "toolbar", @embedFile("styles.yss"), .{ .direction = .row, .align_items = .center, .gap = ui.tokenRef(.space, "space200"), .height = 36, .padding = .{ .top = 0, .right = 0, .bottom = ui.tokenRef(.space, "space100"), .left = 0 }, .flex_shrink = 0, });

/// Focused view island: stage padding [0, 6, 6, 0], radius 12. Its plate is painted by the window
/// background layer (`appearance.canvas.card`, in the canvas tint group) from this box's rect and
/// radius; the box itself declares no background, so nothing has to clear one after a theme replay.
pub const island = ui.previewCss("src/features/shell/view/shell/styles.yss", "island", @embedFile("styles.yss"), .{ .width = .fill, .height = .fill, .min_width = 0, .min_height = 0, .direction = .column, .margin = .{ .top = 0, .right = ui.tokenRef(.space, "space150"), .bottom = ui.tokenRef(.space, "space150"), .left = 0 }, .corner_radius = ui.tokenRef(.radius, "island"), .overflow = .hidden, });
/// Pane header (ZW2 / Pane Header): 30 high, padding [0, 4, 0, 12], gap 6.
pub const pane_header = ui.previewCss("src/features/shell/view/shell/styles.yss", "pane_header", @embedFile("styles.yss"), .{ .width = .fill, .height = 30, .flex_shrink = 0, .direction = .row, .align_items = .center, .gap = ui.tokenRef(.space, "space150"), .padding = .{ .top = 0, .right = ui.tokenRef(.space, "space100"), .bottom = 0, .left = ui.tokenRef(.space, "space300") }, .background = ui.Color.TRANSPARENT, });
/// Toolbar group (ZW5 / View Tools · Split / Actions): plain icon buttons.
pub const toolbar_group = ui.previewCss("src/features/shell/view/shell/styles.yss", "toolbar_group", @embedFile("styles.yss"), .{ .direction = .row, .align_items = .center, .gap = ui.tokenRef(.space, "space150"), .height = 32, .flex_shrink = 0, .background = ui.Color.TRANSPARENT, });
/// 1×16 hairline between toolbar groups.
pub const toolbar_divider = ui.previewCss("src/features/shell/view/shell/styles.yss", "toolbar_divider", @embedFile("styles.yss"), .{ .width = 1, .height = 16, .flex_shrink = 0, .background = ui.tokenRef(.color, "border-strong"), });
/// Sidebar search row (ZW5 / Sidebar › Search): full width, 28 high, radius 8, under the header.
pub const sidebar_search = ui.previewCss("src/features/shell/view/shell/styles.yss", "sidebar_search", @embedFile("styles.yss"), .{ .width = .fill, .height = 28, .min_width = 0, .flex_shrink = 0, .direction = .row, .align_items = .center, .gap = ui.tokenRef(.space, "space100"), .padding = .{ .top = 0, .right = 2, .bottom = 0, .left = ui.tokenRef(.space, "space200") }, .corner_radius = 8, .overflow = .hidden, });

//# yix-map styles.yss
