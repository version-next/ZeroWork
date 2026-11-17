// GENERATED FILE, do not edit: generated from attachment.yss; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! AttachmentChip styles (attachment.yix): a quiet bg-secondary row (no border, no shadow) or a
//! 44 tile on bg-tertiary; all ink from tokens.
const ui = @import("../../ui.zig");

/// Root look over ControlShell (ghost tone): fill, geometry; hover only while clickable.
pub const Attachment = ui.previewCva("src/ui/components/chip/attachment.yss", "Attachment", @embedFile("attachment.yss"), .{ .base = .{ .background = ui.tokenRef(.color, "bg-secondary"), .font_weight = 400, .corner_radius = ui.tokenRef(.radius, "control"), .border_overlay = true, .border_width = 0, .border_color = ui.Color.TRANSPARENT, .shadow = .{ .offset_x = 0, .offset_y = 0, .blur = 0, .spread = 0, .color = ui.Color.TRANSPARENT }, .justify = .start, }, .variants = .{ .tile = .{ .false = .{ .height = 28, .padding = .{ .top = 0, .right = ui.tokenRef(.space, "space100"), .bottom = 0, .left = ui.tokenRef(.space, "space200") }, .gap = ui.tokenRef(.space, "space150"), .max_width = 260, }, .true = .{ .width = 44, .height = 44, .padding = 0, .gap = 0, .background = ui.tokenRef(.color, "bg-tertiary"), .overflow = .hidden, .justify = .center, }, }, .interactive = .{ .false = .{ }, .true = .{ ._hover = .{ .background = ui.tokenRef(.color, "bg-active"), }, ._active = .{ .background = ui.tokenRef(.color, "button-pressed-bg"), }, }, }, }, .defaults = .{ .tile = false, .interactive = false, }, });

pub const Lead = ui.previewCva("src/ui/components/chip/attachment.yss", "Lead", @embedFile("attachment.yss"), .{ .base = .{ .justify = .center, .align_items = .center, .corner_radius = ui.tokenRef(.radius, "md"), .overflow = .hidden, }, .variants = .{ .tile = .{ .false = .{ .width = .fit, .height = .fit, }, .true = .{ .width = 44, .height = 44, }, }, }, .defaults = .{ .tile = false, }, });
pub const Thumb = ui.previewCva("src/ui/components/chip/attachment.yss", "Thumb", @embedFile("attachment.yss"), .{ .base = .{ .corner_radius = ui.tokenRef(.radius, "md"), }, .variants = .{ .tile = .{ .false = .{ .width = 20, .height = 20, }, .true = .{ .width = 44, .height = 44, }, }, }, .defaults = .{ .tile = false, }, });
pub const Glyph = ui.previewCva("src/ui/components/chip/attachment.yss", "Glyph", @embedFile("attachment.yss"), .{ .variants = .{ .tile = .{ .false = .{ .width = 13, .height = 13, .icon_color = ui.tokenRef(.color, "fg-secondary"), }, .true = .{ .width = 16, .height = 16, .icon_color = ui.tokenRef(.color, "fg-tertiary"), }, }, }, .defaults = .{ .tile = false, }, });

pub const text_row = ui.previewCss("src/ui/components/chip/attachment.yss", "text_row", @embedFile("attachment.yss"), .{ .width = .fit, .min_width = 0, .height = .fit, .direction = .row, .align_items = .baseline, .gap = ui.tokenRef(.space, "space150"), });
pub const name = ui.previewCss("src/ui/components/chip/attachment.yss", "name", @embedFile("attachment.yss"), .{ .font_size = ui.tokenRef(.font_size, "sm"), .font_weight = 400, .line_height = 1.5, .color = ui.tokenRef(.color, "fg-primary"), .wrap = .none, .text_overflow = .ellipsis, .selectable = false, });
pub const name_box = ui.previewCss("src/ui/components/chip/attachment.yss", "name_box", @embedFile("attachment.yss"), .{ .min_width = 0, .flex_shrink = 1, });
pub const detail = ui.previewCss("src/ui/components/chip/attachment.yss", "detail", @embedFile("attachment.yss"), .{ .font_size = ui.tokenRef(.font_size, "xs"), .line_height = 1.5, .color = ui.tokenRef(.color, "fg-tertiary"), .wrap = .none, .selectable = false, });
pub const detail_box = ui.previewCss("src/ui/components/chip/attachment.yss", "detail_box", @embedFile("attachment.yss"), .{ .flex_shrink = 0, });


/// Remove button look: on the tile an 18 round over the corner, on bg-primary (readable over a
/// picture), clear of the tile's center; on the row the plain ghost xs Button.
pub const TileRemove = ui.previewCva("src/ui/components/chip/attachment.yss", "TileRemove", @embedFile("attachment.yss"), .{ .variants = .{ .tile = .{ .false = .{ }, .true = .{ .width = 18, .height = 18, .min_height = 0, .padding = 0, .corner_radius = 999, .justify = .center, .align_items = .center, .background = ui.tokenRef(.color, "bg-primary"), ._hover = .{ .background = ui.tokenRef(.color, "bg-active"), }, }, }, }, .defaults = .{ .tile = false, }, });

//# yix-map attachment.yss
