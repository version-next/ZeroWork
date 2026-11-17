// GENERATED FILE, do not edit: generated from ai_composer_interaction.yss; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! Decision panel layout (Pencil Kaf7E A7 / A11, ③ “审批面板”): content padding 12 12 10 12, gap 10;
//! heading icon 16 + title 13/600 over the target 12 secondary; command well bg-secondary radius 6,
//! mono 12; impact note info 12 + 12 secondary. The surface (outlined Card) and every control are
//! native (view: ai_composer_interaction.yix).
const ui = @import("ui");

/// Card body: the scrolling decision content, then the action row.
pub const body = ui.previewCss("src/features/ai/composer/view/ai_composer_interaction.yss", "body", @embedFile("ai_composer_interaction.yss"), .{ .width = .fill, .height = .fit, .direction = .column, .gap = 10, .padding = .{ .top = 12, .right = 12, .bottom = 10, .left = 12 }, .flex_shrink = 0, });
/// The decision content viewport: scrolls past `$max` (≤ 180; short panels 40 %), actions stay put.
pub const viewport = ui.paramStyle(struct { max: f32, pub const declared = &[_][]const u8{ "width", "height", "max_height", "min_height", "flex_shrink", }; pub fn resolve(args: @This(), t: *const ui.theme.Values) ui.BoxStyle { return ui.boxFrom(.{ .width = .fill, .height = .{ .fit = .{ .max = args.max } }, .max_height = args.max, .min_height = 0, .flex_shrink = 0, }, t); } });
pub const content = ui.previewCss("src/features/ai/composer/view/ai_composer_interaction.yss", "content", @embedFile("ai_composer_interaction.yss"), .{ .width = .fill, .height = .fit, .direction = .column, .gap = 10, .flex_shrink = 0, });

pub const heading = ui.previewCss("src/features/ai/composer/view/ai_composer_interaction.yss", "heading", @embedFile("ai_composer_interaction.yss"), .{ .width = .fill, .direction = .row, .align_items = .start, .gap = 8, .flex_shrink = 0, });
pub const warn_glyph = ui.previewCss("src/features/ai/composer/view/ai_composer_interaction.yss", "warn_glyph", @embedFile("ai_composer_interaction.yss"), .{ .width = 16, .height = 16, .flex_shrink = 0, .icon_color = ui.tokenRef(.color, "warning"), });
pub const ask_glyph = ui.previewCss("src/features/ai/composer/view/ai_composer_interaction.yss", "ask_glyph", @embedFile("ai_composer_interaction.yss"), .{ .width = 16, .height = 16, .flex_shrink = 0, .icon_color = ui.tokenRef(.color, "accent"), });
pub const title_block = ui.previewCss("src/features/ai/composer/view/ai_composer_interaction.yss", "title_block", @embedFile("ai_composer_interaction.yss"), .{ .width = .fill, .flex = 1, .min_width = 0, .direction = .column, .gap = 2, });

/// Text tiers: `word-break` (CSS overflow-wrap: break-word) keeps long paths inside the panel.
pub const title = ui.previewCss("src/features/ai/composer/view/ai_composer_interaction.yss", "title", @embedFile("ai_composer_interaction.yss"), .{ .font_size = 13, .line_height = 1.5, .font_weight = 600, .color = ui.tokenRef(.color, "fg-primary"), .wrap = .word_break, });
pub const secondary = ui.previewCss("src/features/ai/composer/view/ai_composer_interaction.yss", "secondary", @embedFile("ai_composer_interaction.yss"), .{ .font_size = 12, .line_height = 1.5, .font_weight = 400, .color = ui.tokenRef(.color, "fg-secondary"), .wrap = .word_break, });
pub const reason = ui.previewCss("src/features/ai/composer/view/ai_composer_interaction.yss", "reason", @embedFile("ai_composer_interaction.yss"), .{ .font_size = 11, .line_height = 16.0 / 11.0, .font_weight = 400, .color = ui.tokenRef(.color, "fg-secondary"), .wrap = .word_break, });
pub const failure = ui.previewCss("src/features/ai/composer/view/ai_composer_interaction.yss", "failure", @embedFile("ai_composer_interaction.yss"), .{ .font_size = 11, .line_height = 16.0 / 11.0, .font_weight = 400, .color = ui.tokenRef(.color, "danger"), .wrap = .word_break, });
/// A text that fills its row and may shrink below its longest word.
pub const fill_text = ui.previewCss("src/features/ai/composer/view/ai_composer_interaction.yss", "fill_text", @embedFile("ai_composer_interaction.yss"), .{ .width = .fill, .height = .fit, .min_width = 0, .flex = 1, .flex_shrink = 0, });
/// A text beside an icon in a row: it gives way to the row's width and wraps (never runs past it).
pub const row_text = ui.previewCss("src/features/ai/composer/view/ai_composer_interaction.yss", "row_text", @embedFile("ai_composer_interaction.yss"), .{ .width = .fill, .height = .fit, .min_width = 0, .flex = 1, .flex_shrink = 1, });

pub const command_row = ui.previewCss("src/features/ai/composer/view/ai_composer_interaction.yss", "command_row", @embedFile("ai_composer_interaction.yss"), .{ .width = .fill, .direction = .row, .align_items = .start, .gap = 4, .flex_shrink = 0, });
/// Command well (a functional surface: bg-secondary, radius 6, padding 6 10).
pub const command = ui.previewCss("src/features/ai/composer/view/ai_composer_interaction.yss", "command", @embedFile("ai_composer_interaction.yss"), .{ .font_size = 12, .line_height = 1.5, .font_weight = 400, .color = ui.tokenRef(.color, "fg-primary"), .wrap = .word_break, .use_monospace_font = true, });
pub const command_well = ui.previewCss("src/features/ai/composer/view/ai_composer_interaction.yss", "command_well", @embedFile("ai_composer_interaction.yss"), .{ .width = .fill, .min_width = 0, .flex = 1, .flex_shrink = 1, .padding = .{ .y = 6, .x = 10 }, .background = ui.tokenRef(.color, "bg-secondary"), .corner_radius = 6, });

pub const impact_row = ui.previewCss("src/features/ai/composer/view/ai_composer_interaction.yss", "impact_row", @embedFile("ai_composer_interaction.yss"), .{ .width = .fill, .height = .fit, .direction = .row, .align_items = .center, .gap = 6, .flex_shrink = 0, });
pub const info_glyph = ui.previewCss("src/features/ai/composer/view/ai_composer_interaction.yss", "info_glyph", @embedFile("ai_composer_interaction.yss"), .{ .width = 12, .height = 12, .flex_shrink = 0, .icon_color = ui.tokenRef(.color, "fg-tertiary"), });

pub const options = ui.previewCss("src/features/ai/composer/view/ai_composer_interaction.yss", "options", @embedFile("ai_composer_interaction.yss"), .{ .width = .fill, .height = .fit, .direction = .column, .flex_shrink = 0, });
/// The custom answer Input sits under the radio list, aligned with the option labels.
pub const custom_row = ui.previewCss("src/features/ai/composer/view/ai_composer_interaction.yss", "custom_row", @embedFile("ai_composer_interaction.yss"), .{ .width = .fill, .height = .fit, .direction = .row, .align_items = .center, .padding = .{ .top = 0, .right = 0, .bottom = 0, .left = 22 }, .flex_shrink = 0, });

pub const actions = ui.previewCss("src/features/ai/composer/view/ai_composer_interaction.yss", "actions", @embedFile("ai_composer_interaction.yss"), .{ .width = .fill, .height = .fit, .direction = .row, .align_items = .center, .gap = 6, .flex_shrink = 0, });

//# yix-map ai_composer_interaction.yss
