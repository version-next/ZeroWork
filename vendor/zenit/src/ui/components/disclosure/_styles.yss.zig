// GENERATED FILE, do not edit: generated from styles.yss; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! Disclosure styles: a 28-high trigger row (hover / open fill), status inks by tone, and the
//! content rail (1px border at the left, no card). View in disclosure.yix.
const ui = @import("../../ui.zig");

pub const root = ui.previewCss("src/ui/components/disclosure/styles.yss", "root", @embedFile("styles.yss"), .{ .width = .fill, .min_width = 0, .height = .fit, .direction = .column, .gap = ui.tokenRef(.space, "space50"), });

/// Trigger: 28 high, 0 6, radius control, 6 apart; hover and open fill with bg-hover.
pub const Trigger = ui.previewCva("src/ui/components/disclosure/styles.yss", "Trigger", @embedFile("styles.yss"), .{ .base = .{ .width = .fill, .min_width = 0, .height = 28, .direction = .row, .align_items = .center, .gap = ui.tokenRef(.space, "space150"), .padding = .{ .y = 0, .x = ui.tokenRef(.space, "space150") }, .corner_radius = ui.tokenRef(.radius, "control"), .background = ui.Color.TRANSPARENT, .cursor = .pointer, .transition = ui.transition("background 120ms ease-out"), ._hover = .{ .background = ui.tokenRef(.color, "bg-hover"), }, }, .variants = .{ .open = .{ .false = .{ }, .true = .{ .background = ui.tokenRef(.color, "bg-hover"), }, }, .disabled = .{ .false = .{ }, .true = .{ .cursor = .default, ._hover = .{ .background = ui.Color.TRANSPARENT, }, }, }, }, .defaults = .{ .open = false, .disabled = false, }, });

pub const chevron = ui.previewCss("src/ui/components/disclosure/styles.yss", "chevron", @embedFile("styles.yss"), .{ .width = 12, .height = 12, .flex_shrink = 0, .icon_color = ui.tokenRef(.color, "fg-tertiary"), });
/// A caller's status view (a spinner, a custom glyph) in the 14 status box.
pub const status_slot = ui.previewCss("src/ui/components/disclosure/styles.yss", "status_slot", @embedFile("styles.yss"), .{ .width = 14, .height = 14, .flex_shrink = 0, .justify = .center, .align_items = .center, });

pub const Status = ui.previewCva("src/ui/components/disclosure/styles.yss", "Status", @embedFile("styles.yss"), .{ .base = .{ .width = 14, .height = 14, .flex_shrink = 0, }, .variants = .{ .tone = .{ .neutral = .{ .icon_color = ui.tokenRef(.color, "fg-tertiary"), }, .accent = .{ .icon_color = ui.tokenRef(.color, "accent"), }, .success = .{ .icon_color = ui.tokenRef(.color, "success"), }, .warning = .{ .icon_color = ui.tokenRef(.color, "warning"), }, .danger = .{ .icon_color = ui.tokenRef(.color, "danger"), }, }, }, .defaults = .{ .tone = .neutral, }, });

pub const title = ui.previewCss("src/ui/components/disclosure/styles.yss", "title", @embedFile("styles.yss"), .{ .font_size = ui.tokenRef(.font_size, "sm"), .font_weight = 500, .line_height = 1.5, .color = ui.tokenRef(.color, "fg-secondary"), .wrap = .none, .selectable = false, });
/// Title and trailing keep their width; the detail gives way first.
pub const fixed_box = ui.previewCss("src/ui/components/disclosure/styles.yss", "fixed_box", @embedFile("styles.yss"), .{ .flex_shrink = 0, });
pub const detail_box = ui.previewCss("src/ui/components/disclosure/styles.yss", "detail_box", @embedFile("styles.yss"), .{ .min_width = 0, .flex_shrink = 1, });

/// Count / status after the title; it gives way first when the row is narrow.
pub const Detail = ui.previewCva("src/ui/components/disclosure/styles.yss", "Detail", @embedFile("styles.yss"), .{ .base = .{ .font_size = ui.tokenRef(.font_size, "sm"), .line_height = 1.5, .wrap = .none, .text_overflow = .ellipsis, .selectable = false, }, .variants = .{ .tone = .{ .neutral = .{ .color = ui.tokenRef(.color, "fg-tertiary"), }, .accent = .{ .color = ui.tokenRef(.color, "accent"), }, .success = .{ .color = ui.tokenRef(.color, "success"), }, .warning = .{ .color = ui.tokenRef(.color, "warning"), }, .danger = .{ .color = ui.tokenRef(.color, "danger"), }, }, }, .defaults = .{ .tone = .neutral, }, });

pub const spacer = ui.previewCss("src/ui/components/disclosure/styles.yss", "spacer", @embedFile("styles.yss"), .{ .width = .fill, .min_width = 0, .height = 1, });
pub const trailing = ui.previewCss("src/ui/components/disclosure/styles.yss", "trailing", @embedFile("styles.yss"), .{ .font_size = ui.tokenRef(.font_size, "xs"), .line_height = 1.5, .color = ui.tokenRef(.color, "fg-tertiary"), .wrap = .none, .selectable = false, });

/// Content: hangs on a 1px border-colour rail at the left (2 0 2 12), items 2 apart.
pub const rail = ui.previewCss("src/ui/components/disclosure/styles.yss", "rail", @embedFile("styles.yss"), .{ .width = .fill, .min_width = 0, .height = .fit, .direction = .column, .gap = ui.tokenRef(.space, "space50"), .padding = .{ .top = ui.tokenRef(.space, "space50"), .right = 0, .bottom = ui.tokenRef(.space, "space50"), .left = ui.tokenRef(.space, "space300") }, .border_left_width = 1, .border_left_color = ui.tokenRef(.color, "border"), });

//# yix-map styles.yss
