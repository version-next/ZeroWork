// GENERATED FILE, do not edit: generated from ai_composer_controls.yss; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! AI composer tool row and its popovers (Pencil Kaf7E A3 / ⑤ / O1–O4 / O6). The controls are
//! native (ghost sm Buttons, Tooltips, Menus, Popovers, Slider, Divider, ProgressRing / Segments,
//! Pressable); these styles only lay out the row and the popovers' own content (view:
//! ai_composer_controls.yix).
const ui = @import("ui");

/// Tool row: 2 apart (Kaf7E A3 Toolbar gap 2); the Textarea footer row pads it. Takes the footer's
/// width and no more (min 0, shrinks): the collapse logic measures this row.
pub const row = ui.previewCss("src/features/ai/composer/view/ai_composer_controls.yss", "row", @embedFile("ai_composer_controls.yss"), .{ .width = .fill, .height = .fill, .direction = .row, .align_items = .center, .gap = 2, .flex_shrink = 1, .min_width = 0, });
/// Send / Stop: the host's native primary sm icon Buttons, side by side.
pub const trailing = ui.previewCss("src/features/ai/composer/view/ai_composer_controls.yss", "trailing", @embedFile("ai_composer_controls.yss"), .{ .width = .fit, .height = .fit, .direction = .row, .align_items = .center, .gap = 4, .flex_shrink = 0, });
pub const no_shrink = ui.previewCss("src/features/ai/composer/view/ai_composer_controls.yss", "no_shrink", @embedFile("ai_composer_controls.yss"), .{ .flex_shrink = 0, });
/// Popover / menu mount points take no room on the row.
pub const wrapper = ui.previewCss("src/features/ai/composer/view/ai_composer_controls.yss", "wrapper", @embedFile("ai_composer_controls.yss"), .{ .position = .absolute, .width = 0, .height = 0, .padding = 0, .gap = 0, });

/// Popover content columns (the native Popover draws the surface).
pub const model_body = ui.previewCss("src/features/ai/composer/view/ai_composer_controls.yss", "model_body", @embedFile("ai_composer_controls.yss"), .{ .width = .fill, .height = .fit, .min_height = 0, .direction = .column, .gap = 4, });
pub const usage_body = ui.previewCss("src/features/ai/composer/view/ai_composer_controls.yss", "usage_body", @embedFile("ai_composer_controls.yss"), .{ .width = .fill, .height = .fit, .min_height = 0, .direction = .column, .gap = 8, });

// ── O4 model popover ─────────────────────────────────────────────────────────────────────
pub const model_card = ui.previewCss("src/features/ai/composer/view/ai_composer_controls.yss", "model_card", @embedFile("ai_composer_controls.yss"), .{ .width = .fill, .height = 192, .direction = .column, .gap = 0, .flex_shrink = 0, .min_height = 0, });
/// A list row's root (the list sizes it: 28 for a header, 30 for a model).
pub const list_row = ui.previewCss("src/features/ai/composer/view/ai_composer_controls.yss", "list_row", @embedFile("ai_composer_controls.yss"), .{ .width = .fill, .direction = .column, });
pub const models = ui.previewCss("src/features/ai/composer/view/ai_composer_controls.yss", "models", @embedFile("ai_composer_controls.yss"), .{ .width = .fill, .height = .fill, .min_height = 0, .flex = 1, });
pub const empty_text = ui.previewCss("src/features/ai/composer/view/ai_composer_controls.yss", "empty_text", @embedFile("ai_composer_controls.yss"), .{ .font_size = 12, .font_weight = 400, .line_height = 1.5, .color = ui.tokenRef(.color, "fg-secondary"), .text_overflow = .clip, });
pub const empty_box = ui.previewCss("src/features/ai/composer/view/ai_composer_controls.yss", "empty_box", @embedFile("ai_composer_controls.yss"), .{ .width = .fill, .height = 30, .flex = 1, .min_width = 0, });
pub const error_text = ui.previewCss("src/features/ai/composer/view/ai_composer_controls.yss", "error_text", @embedFile("ai_composer_controls.yss"), .{ .font_size = 11, .font_weight = 400, .line_height = 16.0 / 11.0, .color = ui.tokenRef(.color, "danger"), .text_overflow = .clip, });
pub const error_box = ui.previewCss("src/features/ai/composer/view/ai_composer_controls.yss", "error_box", @embedFile("ai_composer_controls.yss"), .{ .width = .fill, .height = 16, .flex = 1, .min_width = 0, });
/// Reasoning area: the header (16), and the slider area (28) when the model has effort steps.
/// Its height is its content's (28 without the slider, 64 with it): a fixed 40 let the slider and
/// its mark labels spill out of the popover over the tool row.
pub const reasoning_card = ui.previewCss("src/features/ai/composer/view/ai_composer_controls.yss", "reasoning_card", @embedFile("ai_composer_controls.yss"), .{ .width = .fill, .height = .fit, .direction = .column, .padding = .{ .top = 4, .right = 8, .bottom = 8, .left = 8 }, .gap = 8, .flex_shrink = 0, });
pub const reasoning_header = ui.previewCss("src/features/ai/composer/view/ai_composer_controls.yss", "reasoning_header", @embedFile("ai_composer_controls.yss"), .{ .width = .fill, .height = 16, .direction = .row, .align_items = .center, .gap = 8, .flex_shrink = 0, });
pub const effort_title = ui.previewCss("src/features/ai/composer/view/ai_composer_controls.yss", "effort_title", @embedFile("ai_composer_controls.yss"), .{ .font_size = 10, .font_weight = 400, .line_height = 16.5 / 10.0, .color = ui.tokenRef(.color, "zw-fg-faint"), .text_overflow = .clip, });
pub const effort_title_box = ui.previewCss("src/features/ai/composer/view/ai_composer_controls.yss", "effort_title_box", @embedFile("ai_composer_controls.yss"), .{ .width = .fill, .height = 16.5, .flex = 1, .min_width = 0, });
pub const effort_name = ui.previewCss("src/features/ai/composer/view/ai_composer_controls.yss", "effort_name", @embedFile("ai_composer_controls.yss"), .{ .font_size = 10, .font_weight = 500, .line_height = 16.5 / 10.0, .color = ui.tokenRef(.color, "fg-primary"), .text_overflow = .clip, });
pub const effort_name_box = ui.previewCss("src/features/ai/composer/view/ai_composer_controls.yss", "effort_name_box", @embedFile("ai_composer_controls.yss"), .{ .width = .fit, .height = 16.5, .flex_shrink = 0, });
pub const slider_area = ui.previewCss("src/features/ai/composer/view/ai_composer_controls.yss", "slider_area", @embedFile("ai_composer_controls.yss"), .{ .width = .fill, .height = 28, .direction = .column, .flex_shrink = 0, });
pub const slider_box = ui.previewCss("src/features/ai/composer/view/ai_composer_controls.yss", "slider_box", @embedFile("ai_composer_controls.yss"), .{ .width = .fill, .height = 16, .flex_shrink = 0, });
pub const slider = ui.previewCss("src/features/ai/composer/view/ai_composer_controls.yss", "slider", @embedFile("ai_composer_controls.yss"), .{ .width = .fill, .height = 16, .padding = .{ .top = 5, .right = 12, .bottom = 0, .left = 12 }, .flex_shrink = 0, });

/// Provider group row: 26 high, chevron + logo + 13/600 name.
pub const group_row = ui.previewCss("src/features/ai/composer/view/ai_composer_controls.yss", "group_row", @embedFile("ai_composer_controls.yss"), .{ .width = .fill, .height = 26, .direction = .row, .align_items = .center, .justify = .start, .padding = .{ .y = 0, .x = 8 }, .gap = 6, .flex_shrink = 0, .min_width = 0, });
pub const group_chevron = ui.previewCss("src/features/ai/composer/view/ai_composer_controls.yss", "group_chevron", @embedFile("ai_composer_controls.yss"), .{ .width = 12, .height = 12, .flex_shrink = 0, .icon_color = ui.tokenRef(.color, "fg-secondary"), });
pub const group_name = ui.previewCss("src/features/ai/composer/view/ai_composer_controls.yss", "group_name", @embedFile("ai_composer_controls.yss"), .{ .font_size = 13, .font_weight = 600, .line_height = 18.0 / 13.0, .color = ui.tokenRef(.color, "fg-primary"), .text_overflow = .clip, });
pub const group_name_box = ui.previewCss("src/features/ai/composer/view/ai_composer_controls.yss", "group_name_box", @embedFile("ai_composer_controls.yss"), .{ .width = .fill, .height = 18, .flex = 1, .min_width = 0, });
/// Model row: 30 high, padding 0 8, gap 8; the current model sits on the selection fill.
pub const ModelRow = ui.previewCva("src/features/ai/composer/view/ai_composer_controls.yss", "ModelRow", @embedFile("ai_composer_controls.yss"), .{ .base = .{ .width = .fill, .height = 30, .direction = .row, .align_items = .center, .justify = .start, .padding = .{ .y = 0, .x = 8 }, .gap = 8, .background = ui.Color.TRANSPARENT, .corner_radius = 6, .flex_shrink = 0, .min_width = 0, }, .variants = .{ .selected = .{ .false = .{ }, .true = .{ .background = ui.tokenRef(.color, "selection-bg"), }, }, }, .defaults = .{ .selected = false, }, });
/// The details tooltip's trigger: the whole row (all rows share the card width, aligned columns).
pub const row_hint = ui.previewCss("src/features/ai/composer/view/ai_composer_controls.yss", "row_hint", @embedFile("ai_composer_controls.yss"), .{ .width = .fill, .height = 30, .min_width = 0, });
/// Native Tooltip pins its column to `align-items: start`: the trigger stretches itself so every
/// row shares the card width (aligned columns).
pub const row_trigger = ui.previewCss("src/features/ai/composer/view/ai_composer_controls.yss", "row_trigger", @embedFile("ai_composer_controls.yss"), .{ .width = .fill, .height = 30, .min_width = 0, .align_self = .stretch, });
pub const marker = ui.previewCss("src/features/ai/composer/view/ai_composer_controls.yss", "marker", @embedFile("ai_composer_controls.yss"), .{ .width = 12, .height = 16, .direction = .row, .align_items = .center, .justify = .center, .flex_shrink = 0, });
pub const marker_dot = ui.previewCss("src/features/ai/composer/view/ai_composer_controls.yss", "marker_dot", @embedFile("ai_composer_controls.yss"), .{ .width = 4, .height = 4, .background = ui.tokenRef(.color, "zw-fg-faint"), .corner_radius = 2, .flex_shrink = 0, });
pub const marker_text = ui.previewCss("src/features/ai/composer/view/ai_composer_controls.yss", "marker_text", @embedFile("ai_composer_controls.yss"), .{ .font_size = 12, .font_weight = 600, .line_height = 16.0 / 12.0, .color = ui.tokenRef(.color, "info"), .text_align = .center, .text_overflow = .clip, });
pub const marker_text_box = ui.previewCss("src/features/ai/composer/view/ai_composer_controls.yss", "marker_text_box", @embedFile("ai_composer_controls.yss"), .{ .width = 4.234375, .height = 16, .min_width = 0, .flex_shrink = 0, });
pub const ModelName = ui.previewCva("src/features/ai/composer/view/ai_composer_controls.yss", "ModelName", @embedFile("ai_composer_controls.yss"), .{ .base = .{ .font_size = 11, .font_weight = 400, .line_height = 16.0 / 11.0, .color = ui.tokenRef(.color, "fg-primary"), .text_overflow = .ellipsis, }, .variants = .{ .off = .{ .false = .{ }, .true = .{ .color = ui.tokenRef(.color, "zw-fg-faint"), }, }, }, .defaults = .{ .off = false, }, });
pub const model_name_box = ui.previewCss("src/features/ai/composer/view/ai_composer_controls.yss", "model_name_box", @embedFile("ai_composer_controls.yss"), .{ .width = .fill, .height = 16, .flex = 1, .min_width = 0, .overflow = .hidden, });
pub const ModelContext = ui.previewCva("src/features/ai/composer/view/ai_composer_controls.yss", "ModelContext", @embedFile("ai_composer_controls.yss"), .{ .base = .{ .font_size = 10, .font_weight = 400, .line_height = 13.0 / 10.0, .color = ui.tokenRef(.color, "fg-secondary"), .text_overflow = .clip, .text_align = .end, .use_monospace_font = true, }, .variants = .{ .off = .{ .false = .{ }, .true = .{ .color = ui.tokenRef(.color, "zw-fg-faint"), }, }, }, .defaults = .{ .off = false, }, });
pub const context_box = ui.paramStyle(struct { w: f32, pub const declared = &[_][]const u8{ "width", "height", "min_width", "flex_shrink", }; pub fn resolve(args: @This(), t: *const ui.theme.Values) ui.BoxStyle { return ui.boxFrom(.{ .width = args.w, .height = 13, .min_width = 0, .flex_shrink = 0, }, t); } });
pub const capability = ui.previewCss("src/features/ai/composer/view/ai_composer_controls.yss", "capability", @embedFile("ai_composer_controls.yss"), .{ .width = 13, .height = 13, .flex_shrink = 0, });
pub const CapabilityIcon = ui.previewCva("src/features/ai/composer/view/ai_composer_controls.yss", "CapabilityIcon", @embedFile("ai_composer_controls.yss"), .{ .base = .{ .width = 14, .height = 14, .flex_shrink = 0, .icon_color = ui.tokenRef(.color, "zw-fg-faint"), }, .variants = .{ .on = .{ .false = .{ }, .true = .{ .icon_color = ui.tokenRef(.color, "info"), }, }, }, .defaults = .{ .on = false, }, });
/// Brand mark (provider settings and model rows): a rounded tile with the brand glyph, or the
/// name's first character.
pub const brand_tile = ui.previewCss("src/features/ai/composer/view/ai_composer_controls.yss", "brand_tile", @embedFile("ai_composer_controls.yss"), .{ .width = 16, .height = 16, .align_items = .center, .justify = .center, .background = ui.tokenRef(.color, "bg-hover"), .corner_radius = 4, .flex_shrink = 0, });
pub const brand_glyph = ui.previewCss("src/features/ai/composer/view/ai_composer_controls.yss", "brand_glyph", @embedFile("ai_composer_controls.yss"), .{ .width = 16.0 * 2.0 / 3.0, .height = 16.0 * 2.0 / 3.0, .icon_color = ui.tokenRef(.color, "fg-primary"), });
pub const brand_initial = ui.previewCss("src/features/ai/composer/view/ai_composer_controls.yss", "brand_initial", @embedFile("ai_composer_controls.yss"), .{ .font_size = 16.0 * 0.43, .font_weight = 600, .color = ui.tokenRef(.color, "fg-secondary"), });

// ── O6 usage popover ─────────────────────────────────────────────────────────────────────
pub const usage_scroll = ui.previewCss("src/features/ai/composer/view/ai_composer_controls.yss", "usage_scroll", @embedFile("ai_composer_controls.yss"), .{ .width = .fill, .height = .fit, .min_height = 0, });
pub const usage_content = ui.previewCss("src/features/ai/composer/view/ai_composer_controls.yss", "usage_content", @embedFile("ai_composer_controls.yss"), .{ .width = .fill, .direction = .column, .gap = 8, .padding = 4, });
pub const usage_head = ui.previewCss("src/features/ai/composer/view/ai_composer_controls.yss", "usage_head", @embedFile("ai_composer_controls.yss"), .{ .width = .fill, .height = 16, .direction = .row, .align_items = .center, .gap = 8, .padding = .{ .y = 0, .x = 4 }, .flex_shrink = 0, });
pub const usage_caption = ui.previewCss("src/features/ai/composer/view/ai_composer_controls.yss", "usage_caption", @embedFile("ai_composer_controls.yss"), .{ .font_size = 11, .font_weight = 500, .line_height = 16.0 / 11.0, .color = ui.tokenRef(.color, "zw-fg-faint"), .text_overflow = .ellipsis, });
pub const usage_caption_box = ui.previewCss("src/features/ai/composer/view/ai_composer_controls.yss", "usage_caption_box", @embedFile("ai_composer_controls.yss"), .{ .width = .fill, .height = 16, .flex = 1, .min_width = 0, });
pub const usage_total = ui.previewCss("src/features/ai/composer/view/ai_composer_controls.yss", "usage_total", @embedFile("ai_composer_controls.yss"), .{ .font_size = 11, .font_weight = 400, .line_height = 16.0 / 11.0, .color = ui.tokenRef(.color, "fg-secondary"), .text_overflow = .clip, });
pub const usage_total_box = ui.previewCss("src/features/ai/composer/view/ai_composer_controls.yss", "usage_total_box", @embedFile("ai_composer_controls.yss"), .{ .width = .fit, .height = 16, .flex_shrink = 0, });
pub const usage_legend = ui.previewCss("src/features/ai/composer/view/ai_composer_controls.yss", "usage_legend", @embedFile("ai_composer_controls.yss"), .{ .width = .fill, .direction = .column, .gap = 2, .padding = .{ .y = 2, .x = 4 }, .flex_shrink = 0, });
pub const usage_row = ui.previewCss("src/features/ai/composer/view/ai_composer_controls.yss", "usage_row", @embedFile("ai_composer_controls.yss"), .{ .width = .fill, .height = 22, .direction = .row, .align_items = .center, .gap = 6, .flex_shrink = 0, });
/// Legend dot in its part's tone (the same role token the native segment paints).
pub const UsageSwatch = ui.previewCva("src/features/ai/composer/view/ai_composer_controls.yss", "UsageSwatch", @embedFile("ai_composer_controls.yss"), .{ .base = .{ .width = 6, .height = 6, .corner_radius = 3, .flex_shrink = 0, .background = ui.tokenRef(.color, "fg-tertiary"), }, .variants = .{ .tone = .{ .neutral = .{ .background = ui.tokenRef(.color, "fg-tertiary"), }, .accent = .{ .background = ui.tokenRef(.color, "progress-fill"), }, .success = .{ .background = ui.tokenRef(.color, "progress-success"), }, .warning = .{ .background = ui.tokenRef(.color, "progress-warning"), }, .danger = .{ .background = ui.tokenRef(.color, "progress-error"), }, }, }, .defaults = .{ .tone = .neutral, }, });
pub const usage_name = ui.previewCss("src/features/ai/composer/view/ai_composer_controls.yss", "usage_name", @embedFile("ai_composer_controls.yss"), .{ .font_size = 12, .font_weight = 400, .line_height = 1.5, .color = ui.tokenRef(.color, "fg-primary"), .text_overflow = .clip, });
pub const usage_name_box = ui.previewCss("src/features/ai/composer/view/ai_composer_controls.yss", "usage_name_box", @embedFile("ai_composer_controls.yss"), .{ .width = .fill, .height = 18, .flex = 1, .min_width = 0, });
pub const usage_value = ui.previewCss("src/features/ai/composer/view/ai_composer_controls.yss", "usage_value", @embedFile("ai_composer_controls.yss"), .{ .font_size = 12, .font_weight = 400, .line_height = 1.5, .color = ui.tokenRef(.color, "fg-secondary"), .text_overflow = .clip, });
pub const usage_value_box = ui.previewCss("src/features/ai/composer/view/ai_composer_controls.yss", "usage_value_box", @embedFile("ai_composer_controls.yss"), .{ .width = .fit, .height = 18, .flex_shrink = 0, });
pub const usage_action = ui.previewCss("src/features/ai/composer/view/ai_composer_controls.yss", "usage_action", @embedFile("ai_composer_controls.yss"), .{ .width = .fill, .direction = .row, .padding = .{ .y = 0, .x = 4 }, .flex_shrink = 0, });

//# yix-map ai_composer_controls.yss
