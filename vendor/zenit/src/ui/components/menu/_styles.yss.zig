// GENERATED FILE, do not edit: generated from styles.yss; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! Menu styles: menu item recipe (danger variant + hover highlight + disabled state) and panel /
//! divider / inline layout.
//! View in menu.yix; popover, keyboard nav and selection pipeline in mod.zig.
const ui = @import("../../ui.zig");
const core = @import("../../core.zig");
const theme = core.theme;
const Color = core.Color;
const Padding = core.Padding;

/// Menu item: root (row, hover / keyboard virtual highlight use list-hover-bg), label (text), icon
/// (icon, color follows text).
/// Lit represents either the hovered row or the independent keyboard highlight.
/// Disabled colors override danger and highlight.
pub const MenuRow = ui.sva(.{ .slots = .{ .root, .label, .icon, .description, }, .base = .{ .root = .{ .width = .{ .grow = .{} }, .height = 28, .direction = .row, .align_items = .center, .justify = .space_between, .gap = ui.tokenRef(.space, "space200"), .padding = .{ .y = 0, .x = ui.tokenRef(.space, "space200") }, .corner_radius = ui.tokenRef(.radius, "md"), .background = ui.Color.TRANSPARENT, }, .label = .{ .font_size = ui.tokenRef(.font_size, "md"), .color = ui.tokenRef(.color, "fg-primary"), }, .icon = .{ .width = 16, .height = 16, .icon_color = ui.tokenRef(.color, "fg-primary"), }, .description = .{ .color = ui.tokenRef(.color, "fg-secondary"), }, }, .variants = .{ .described = .{ .false = .{ }, .true = .{ .root = .{ .height = .fit, .min_height = 28, .padding = .{ .y = ui.tokenRef(.space, "space150"), .x = ui.tokenRef(.space, "space200") }, .align_items = .start, }, }, }, .danger = .{ .false = .{ }, .true = .{ .label = .{ .color = ui.tokenRef(.color, "danger"), }, .icon = .{ .icon_color = ui.tokenRef(.color, "danger"), }, }, }, .lit = .{ .false = .{ }, .true = .{ }, }, .disabled = .{ .false = .{ .root = .{ .cursor = .pointer, ._active = .{ .background = ui.tokenRef(.color, "bg-active"), }, }, }, .true = .{ .label = .{ .color = ui.tokenRef(.color, "fg-disabled"), }, .icon = .{ .icon_color = ui.tokenRef(.color, "fg-disabled"), }, .description = .{ .color = ui.tokenRef(.color, "fg-disabled"), }, }, }, }, .defaults = .{ .described = false, .danger = false, .lit = false, .disabled = false, }, .compound = .{ .{ .when = .{ .lit = true, .disabled = false, }, .style = .{ .root = .{ .background = ui.tokenRef(.color, "bg-hover"), }, } }, }, });

/// Item list in panel
pub const list = ui.previewCss("src/ui/components/menu/styles.yss", "list", @embedFile("styles.yss"), .{ .width = .{ .grow = .{} }, .height = .fit, .direction = .column, .padding = 4, });

/// Divider outer: vertical padding, line itself 1px
pub const separator = ui.previewCss("src/ui/components/menu/styles.yss", "separator", @embedFile("styles.yss"), .{ .width = .{ .grow = .{} }, .height = .fit, .padding = .{ .y = 4, .x = 0 }, });
pub const separator_line = ui.previewCss("src/ui/components/menu/styles.yss", "separator_line", @embedFile("styles.yss"), .{ .width = .{ .grow = .{} }, .height = 1, .background = ui.tokenRef(.color, "border"), });
/// Group heading (`MenuItem.kind = .header`): caption in the secondary colour, aligned with the
/// row labels, no hover or cursor.
pub const header = ui.previewCss("src/ui/components/menu/styles.yss", "header", @embedFile("styles.yss"), .{ .width = .{ .grow = .{} }, .height = 24, .direction = .row, .align_items = .center, .padding = .{ .y = 0, .x = ui.tokenRef(.space, "space200") }, });
pub const header_text = ui.previewCss("src/ui/components/menu/styles.yss", "header_text", @embedFile("styles.yss"), .{ .font_size = ui.tokenRef(.font_size, "xs"), .color = ui.tokenRef(.color, "fg-secondary"), });
/// Leading part: icon + label (and description). A described row aligns it to the top.
pub const item_left = ui.paramStyle(struct { top: bool, pub const declared = &[_][]const u8{ "width", "min_width", "height", "direction", "align_items", "gap", }; pub fn resolve(args: @This(), t: *const ui.theme.Values) ui.BoxStyle { var out = ui.boxFrom(.{ .width = .fit, .min_width = 0, .height = .fit, .direction = .row, .align_items = .center, .gap = 8, }, t); if (args.top) out = out.merge(ui.boxFrom(.{ .align_items = .start, }, t)); return out; } });
/// Label (+ disabled reason) on one line.
pub const item_label_line = ui.previewCss("src/ui/components/menu/styles.yss", "item_label_line", @embedFile("styles.yss"), .{ .width = .fit, .height = .fit, .direction = .row, .align_items = .center, .gap = 8, });
/// Label line over the description line (`MenuItem.description`).
pub const item_text = ui.previewCss("src/ui/components/menu/styles.yss", "item_text", @embedFile("styles.yss"), .{ .width = .fit, .min_width = 0, .height = .fit, .direction = .column, .gap = ui.tokenRef(.space, "space50"), });
/// `MenuItem.description`: xs, wraps inside the panel.
pub const description = ui.previewCss("src/ui/components/menu/styles.yss", "description", @embedFile("styles.yss"), .{ .font_size = ui.tokenRef(.font_size, "xs"), .line_height = 1.5, .wrap = .word, });
pub const item_right = ui.previewCss("src/ui/components/menu/styles.yss", "item_right", @embedFile("styles.yss"), .{ .width = .fit, .height = .fit, .direction = .row, .align_items = .center, .gap = 8, });
pub const submenu_arrow = ui.previewCss("src/ui/components/menu/styles.yss", "submenu_arrow", @embedFile("styles.yss"), .{ .width = 12, .height = 12, .icon_color = ui.tokenRef(.color, "fg-secondary"), });
/// Why a disabled row is unavailable (`MenuItem.disabled_reason`), after the label.
pub const reason = ui.previewCss("src/ui/components/menu/styles.yss", "reason", @embedFile("styles.yss"), .{ .color = ui.tokenRef(.color, "fg-secondary"), .font_size = ui.tokenRef(.font_size, "xs"), });
pub const shortcut = ui.previewCss("src/ui/components/menu/styles.yss", "shortcut", @embedFile("styles.yss"), .{ .color = ui.tokenRef(.color, "fg-secondary"), .font_size = ui.tokenRef(.font_size, "xs"), });

/// Body text line height from COMPONENTS.json Menu rows.
pub fn rowText(t: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = t.tokens.font_size.md, .line_height = 1.4, .color = t.tokens.color.fg_primary };
}

/// Menu uses aria-activedescendant: the keyboard ring follows the virtual row,
/// while pointer highlight only paints bg-hover. Foundations: 2px ring + 2px offset.
pub const virtual_focus = ui.paramStyle(struct { visible: bool, pub const declared = &[_][]const u8{ "outline", }; pub fn resolve(args: @This(), t: *const ui.theme.Values) ui.BoxStyle { var out: ui.BoxStyle = .{}; if (args.visible) out = out.merge(ui.boxFrom(.{ .outline = ui.Outline{ .color = t.tokens.color.focus_ring, .width = t.tokens.border_width.focus, .offset = t.tokens.size.focus_offset }, }, t)); return out; } });

/// `MenuItem.icon_tint` row icon: same box as the recipe's icon, colour from the item (swatch rows).
pub const tinted_icon = ui.previewCss("src/ui/components/menu/styles.yss", "tinted_icon", @embedFile("styles.yss"), .{ .width = 16, .height = 16, });
/// The swatch colour itself (`tint` of `tinted_icon`).
pub fn itemTint(tint: Color, _: *const ui.ThemeTokens) Color {
    return tint;
}

//# yix-map styles.yss
