// GENERATED FILE, do not edit: generated from styles.yss; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! Kbd styles: one keycap per key in the visual language of Tag (token surfaces, `md` radius,
//! tonal tag colors) with a keycap's raised bottom edge (a 2 pt bottom border) and an equal minimum
//! width (= height), so single glyphs ("⌘", "K") are square caps and words ("Space") grow.
//! View in mod.zig; KbdSize / KbdTone are public APIs defined there.
const ui = @import("../../ui.zig");
const mod = @import("mod.zig");

pub const row = ui.previewCss("src/ui/components/kbd/styles.yss", "row", @embedFile("styles.yss"), .{ .direction = .row, .width = .fit, .height = .fit, .align_items = .center, .no_cross_stretch = true, });

/// Keycap box: height / min width / padding by size, surface and edge by tone.
pub const KbdCap = ui.previewCva("src/ui/components/kbd/styles.yss", "KbdCap", @embedFile("styles.yss"), .{ .base = .{ .direction = .row, .width = .fit, .justify = .center, .align_items = .center, .corner_radius = ui.tokenRef(.radius, "md"), .border_overlay = true, .border_width = 1, .border_bottom_width = 2, }, .variants = .{ .size = .{ .sm = .{ .height = 20, .min_width = 20, .padding = .{ .y = 0, .x = ui.tokenRef(.space, "space100") }, }, .md = .{ .height = 24, .min_width = 24, .padding = .{ .y = 0, .x = ui.tokenRef(.space, "space150") }, }, }, .tone = .{ .neutral = .{ .background = ui.tokenRef(.color, "bg-primary"), .border_color = ui.tokenRef(.color, "border"), }, .accent = .{ .background = ui.tokenRef(.color, "accent-tag-bg"), .border_color = ui.tokenRef(.color, "accent-tag-border"), }, .warning = .{ .background = ui.tokenRef(.color, "warning-tag-bg"), .border_color = ui.tokenRef(.color, "warning-tag-border"), }, .danger = .{ .background = ui.tokenRef(.color, "danger-tag-bg"), .border_color = ui.tokenRef(.color, "danger-tag-border"), }, }, }, .defaults = .{ .size = .sm, .tone = .neutral, }, });

/// Key text: font size by size, ink by tone.
pub const KbdLabel = ui.previewCva("src/ui/components/kbd/styles.yss", "KbdLabel", @embedFile("styles.yss"), .{ .base = .{ .font_weight = 500, .line_height = 1.2, }, .variants = .{ .size = .{ .sm = .{ .font_size = ui.tokenRef(.font_size, "xs"), }, .md = .{ .font_size = ui.tokenRef(.font_size, "sm"), }, }, .tone = .{ .neutral = .{ .color = ui.tokenRef(.color, "fg-secondary"), }, .accent = .{ .color = ui.tokenRef(.color, "accent"), }, .warning = .{ .color = ui.tokenRef(.color, "warning"), }, .danger = .{ .color = ui.tokenRef(.color, "danger"), }, }, }, .defaults = .{ .size = .sm, .tone = .neutral, }, });

/// Gap between caps by size.
pub const KbdRow = ui.previewCva("src/ui/components/kbd/styles.yss", "KbdRow", @embedFile("styles.yss"), .{ .base = .{ }, .variants = .{ .size = .{ .sm = .{ .gap = ui.tokenRef(.space, "space50"), }, .md = .{ .gap = ui.tokenRef(.space, "space100"), }, }, }, .defaults = .{ .size = .sm, }, });

//# yix-map styles.yss
