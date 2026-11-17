//! Step rows on a step-group rail (Pencil Kaf7E A6): one surface — a 24 row (status 12, title
//! 12/500, arguments mono 11 fg_tertiary, elapsed 11), the disclosed details / output in one well
//! (bg_secondary, radius 8, 18 in), no card plate. Colours are zenit tokens.
const ui = @import("ui");
const IdSpace = @import("../../shared/view/ai_id_space.zig").IdSpace;
pub const ButtonStyle = ui.StyleOverride;
pub fn list(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .fit = .{} }, .direction = .column, .gap = 8, .padding = .{}, .flex_shrink = 0 };
}
pub fn card(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .fit = .{} }, .direction = .column, .flex_shrink = 0, .background = ui.Color.TRANSPARENT, .border = .{ .width = 0, .radius = 0 } };
}
pub const row_height: f32 = 24;
/// Details and output sit 18 in from the row (under the title, past the status glyph).
pub const detail_inset: f32 = 18;
pub fn body(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .fit = .{ .max = 150 } }, .flex_shrink = 0 };
}
pub fn content(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .fit = .{} }, .direction = .column, .padding = .{ .left = detail_inset, .top = 2, .bottom = 4 }, .gap = 6, .flex_shrink = 0 };
}
pub fn footer(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = 28 }, .direction = .row, .align_items = .center, .padding = .{ .left = detail_inset }, .gap = 6, .flex_shrink = 0, .background = ui.Color.TRANSPARENT };
}
/// An output well: the code-block surface (bg_secondary, radius 8, no border).
pub fn outputViewport(t: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .flex_shrink = 0, .background = t.tokens.color.bg_secondary, .border = .{ .width = 0, .radius = 8 }, .overflow = .hidden };
}
pub fn outputContent(_: *const ui.ThemeTokens) ui.BoxStyle {
    // `align_self = .start`: a horizontally scrolled `fit` content keeps its
    // intrinsic width; zenit stretches a stretch-aligned `fit` cross size.
    return .{ .width = .{ .fit = .{} }, .height = .{ .fit = .{} }, .padding = .{ .left = 12, .right = 12, .top = 6, .bottom = 8 }, .direction = .column, .flex_shrink = 0, .align_self = .start };
}
pub fn text(t: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 11, .line_height = 1.5, .wrap = .word, .color = t.tokens.color.fg_secondary };
}
pub fn title(t: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 12, .font_weight = 500, .line_height = 1.5, .text_overflow = .ellipsis, .wrap = .none, .color = t.tokens.color.fg_primary };
}
/// Output in a well: mono 12 / 1.55 fg_primary (the code-block spec).
pub fn output(t: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 12, .line_height = 1.55, .wrap = .none, .use_monospace_font = true, .color = t.tokens.color.fg_primary };
}
// Preserve explicit output newlines. Width is measured from the longest line,
// so long lines keep horizontal scrolling instead of wrapping to the card.
pub fn multilineOutput(tokens: *const ui.ThemeTokens) ui.TextStyle {
    var style = output(tokens);
    style.wrap = .word;
    return style;
}
pub fn button(size: f32) ButtonStyle {
    return .{ .width = .{ .px = size }, .height = .{ .px = size }, .padding = .{}, .flex_shrink = 0, .corner_radius = 6, .background = ui.Color.TRANSPARENT };
}
pub fn headerTitle(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .{ .fit = .{} }, .max_width = 160, .min_width = 0, .height = .{ .px = 18 }, .flex_shrink = 0 };
}
pub fn headerSeparator(t: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .{ .px = 3 }, .height = .{ .px = 3 }, .corner_radius = 1.5, .background = t.tokens.color.fg_tertiary, .flex_shrink = 0 };
}
pub fn headerSummary(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = 17 }, .flex = 1, .min_width = 0, .overflow = .hidden };
}
pub fn elapsedSlot(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .{ .fit = .{} }, .height = .{ .px = 17 }, .flex_shrink = 0 };
}
pub fn elapsed(t: *const ui.ThemeTokens) ui.TextStyle {
    // Kaf7E A6 duration: 11 fg_tertiary.
    return .{ .font_size = 11, .line_height = 1.5, .text_align = .end, .wrap = .none, .color = t.tokens.color.fg_tertiary };
}
pub fn targetRow(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = 26 }, .direction = .row, .align_items = .center, .gap = 6, .flex_shrink = 0 };
}
pub fn targetLabel(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .{ .px = 186 }, .height = .{ .px = 16 }, .flex_shrink = 0, .overflow = .hidden };
}
pub fn targetStatus(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = 16 }, .flex = 1, .min_width = 0, .overflow = .hidden };
}
pub fn targetText(t: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 11, .line_height = 1.5, .color = t.tokens.color.fg_secondary };
}
pub fn commandRow(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = 27 }, .direction = .row, .align_items = .start, .gap = 6, .flex_shrink = 0, .min_width = 0 };
}
pub fn commandViewport(t: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .flex = 1, .min_width = 0, .flex_shrink = 0, .background = t.tokens.color.bg_secondary, .corner_radius = 8 };
}

pub fn resultImage(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = 112 }, .flex_shrink = 0 };
}

// ── Pencil Kaf7E A6 step rows ──
pub fn stepRoot(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .fit = .{} }, .direction = .column, .flex_shrink = 0 };
}
pub fn stepTitle(tokens: *const ui.ThemeTokens) ui.TextStyle {
    return title(tokens);
}
/// Arguments: mono 11 fg_tertiary, giving way first.
pub fn stepArgs(t: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 11, .line_height = 1.5, .wrap = .none, .text_overflow = .ellipsis, .use_monospace_font = true, .color = t.tokens.color.fg_tertiary };
}
/// A thought's latest line: 12 fg_tertiary.
pub fn stepProse(t: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 12, .line_height = 1.5, .wrap = .none, .text_overflow = .ellipsis, .color = t.tokens.color.fg_tertiary };
}
/// Failure reason under the row: 11.5 danger, 24 in (past the status glyph).
pub fn stepError(t: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 11.5, .line_height = 1.5, .wrap = .word, .color = t.tokens.color.danger };
}
pub fn stepErrorBox(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .min_width = 0, .padding = .{ .left = 24, .right = 6, .top = 2 }, .flex_shrink = 0 };
}
/// Disclosed details: one well (bg_secondary, radius 8), 18 in.
pub fn stepDetail(t: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .min_width = 0, .margin = .{ .left = detail_inset, .top = 2 }, .background = t.tokens.color.bg_secondary, .border = .{ .width = 0, .radius = 8 }, .overflow = .hidden, .flex_shrink = 0 };
}
pub fn stepDetailContent(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .fit = .{} }, .direction = .column, .padding = .{ .left = 12, .right = 12, .top = 8, .bottom = 10 }, .gap = 4, .flex_shrink = 0 };
}
pub fn stepDetailText(t: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 12, .line_height = 1.55, .wrap = .word, .color = t.tokens.color.fg_secondary };
}

/// Output well (tool / execution cards): native W.CodeBlock, borderless bg-secondary, no header,
/// the message code text (mono 12 / 1.55), long lines keep their length and scroll sideways.
pub fn wellOptions(space: IdSpace) ui.widgets.MarkdownOptions {
    var options = @import("../../pane/view/ai_assistant_styles.zig").markdownOptions(space);
    // Long lines scroll sideways; the thumb stays shown while they overflow (as the card body).
    options.code_block = .{ .frame = .borderless, .header = false, .wrap = false, .scrollbars = .always };
    return options;
}
