//! Connection attempt card (Island B v3 i7VdGA / ybb2B): the session pane's
//! own content — a pane surface with a centred 580 card and per-hop rows.
const ui = @import("ui");
pub const theme = @import("../../../../shared/ui/theme/app_theme.zig");
/// Card width (iY0Iz / eZpyL): 580.
pub const width: f32 = 580;
pub const normal_height: f32 = 358;
pub const failed_height: f32 = 374;
pub const log_extra_height: f32 = 130;
pub const authentication_height: f32 = 346;
pub const max_hops = 9;
/// Card chrome around the scrolling body: identity line 28 + gap 14 +
/// actions row (gap 14 + 32).
pub const header_height: f32 = 28;
pub const footer_height: f32 = 46;
pub const chrome_height: f32 = header_height + 14 + footer_height;
/// Pane inset around the card when the pane is smaller than the card.
pub const pane_inset: f32 = 24;
/// Hop row 44 and the 10pt link between rows (W5ibrC).
pub const hop_height: f32 = 44;
pub const link_height: f32 = 10;

/// The pane body surface the card is centred on (zw.island.focus, no barrier).
pub fn paneSurface() ui.BoxStyle {
    return .{ .position = .absolute, .inset = .{ .left = .{ .px = 0 }, .top = .{ .px = 0 } }, .width = .fill(), .height = .fill(), .direction = .column, .align_items = .center, .justify = .center, .padding = ui.Padding.all(pane_inset), .background = zw().zw_island_focus, .hit_behavior = .@"opaque" };
}
pub fn panel(h: f32, viewport_width: f32) ui.BoxStyle {
    // The card has no chrome of its own; it shares the pane's surface.
    return .{ .width = .{ .px = @min(width, @max(160, viewport_width - 2 * pane_inset)) }, .height = .{ .px = h }, .padding = .{}, .gap = 0, .direction = .column, .background = zw().zw_island_focus, .border = .{ .radius = 0, .width = 0 }, .overflow_hidden = true, .flex_shrink = 0 };
}
pub fn header() ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = 40 }, .direction = .row, .align_items = .center, .gap = 6, .padding = .{ .left = 12, .right = 12 }, .flex_shrink = 0 };
}
pub fn attemptHeader(compact: bool) ui.BoxStyle {
    _ = compact;
    return .{ .width = .fill(), .height = .{ .px = header_height }, .direction = .row, .align_items = .center, .gap = 8, .padding = .{}, .flex_shrink = 0 };
}
// Card sections gap 14 (iY0Iz).
pub fn body(compact: bool) ui.BoxStyle {
    _ = compact;
    return .{ .width = .fill(), .height = .fill(), .min_height = 0, .direction = .column, .padding = .{ .top = 14 }, .gap = 14 };
}
pub fn stack() ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .fit = .{} }, .direction = .column, .gap = 14, .flex_shrink = 0 };
}
pub fn row(h: f32) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = h }, .direction = .row, .align_items = .center, .gap = 8, .flex_shrink = 0 };
}
pub fn scroll() ui.BoxStyle {
    return .{ .width = .fill(), .height = .fill(), .min_height = 0 };
}
pub fn chainScroll() ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .fit = .{} }, .flex_shrink = 0 };
}
pub fn chain(count: usize, available: f32) ui.BoxStyle {
    _ = count;
    _ = available;
    // Hops (W5ibrC): a plain list on the pane, no well.
    return .{ .width = .fill(), .height = .{ .fit = .{} }, .direction = .column, .gap = 0, .padding = .{}, .background = ui.Color.TRANSPARENT, .flex_shrink = 0 };
}
// Hop row (AlEHs): 44, marker 22 · gap 12 · copy column · status.
pub fn card(selected: bool) ui.BoxStyle {
    return .{ .width = .fill(), .align_self = .stretch, .height = .{ .px = hop_height }, .direction = .row, .align_items = .center, .padding = .{ .right = 6 }, .gap = 12, .background = if (selected) theme.popupSelection() else ui.Color.TRANSPARENT, .corner_radius = 6, .border = .{ .radius = 6, .width = 0 }, .flex_shrink = 0 };
}
pub fn hopCopy() ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = 32 }, .min_width = 0, .flex = 1, .flex_basis = 0, .direction = .column, .gap = 1, .flex_shrink = 1 };
}
// Marker (UOmVj): 22 circle on the state's subtle tint, 13 glyph.
pub fn marker(tint: ui.Color) ui.BoxStyle {
    return .{ .width = .{ .px = 22 }, .height = .{ .px = 22 }, .align_items = .center, .justify = .center, .background = tint.withAlpha(28), .border = .{ .radius = 11, .width = 0 }, .flex_shrink = 0 };
}
// Hop link (fxOy2): 10 high, 1px line at x 10.5 (marker centre).
pub fn link() ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = link_height }, .padding = .{ .left = 10.5 }, .flex_shrink = 0 };
}
pub fn linkLine() ui.BoxStyle {
    return .{ .width = .{ .px = 1 }, .height = .fill(), .background = zw().bg_active };
}
// Actions (G4OTn): 32 buttons, gap 8, right aligned, 14 below the log.
pub fn footer(compact: bool) ui.BoxStyle {
    _ = compact;
    return .{ .width = .fill(), .height = .{ .px = footer_height }, .direction = .row, .align_items = .end, .gap = 8, .padding = .{}, .background = ui.Color.TRANSPARENT, .outline = null, .flex_shrink = 0 };
}
pub fn connector() ui.BoxStyle {
    return .{ .width = .{ .px = 24 }, .height = .{ .px = 52 }, .direction = .column, .align_items = .center, .justify = .center, .gap = 4, .flex_shrink = 0 };
}
pub fn connectorText() ui.TextStyle {
    var result = text(8.5, 400, false);
    result.line_height = 12.0 / 8.5;
    result.text_align = .center;
    return result;
}
pub fn text(size: f32, weight: u16, mono: bool) ui.TextStyle {
    const line: f32 = if (size >= 15) 22 else if (size >= 13) 20 else if (size >= 12) 18 else if (size <= 10) 14 else 16;
    return .{ .font_size = size, .font_weight = weight, .line_height = line / size, .color = if (weight >= 500) theme.current().fg_1 else theme.current().fg_2, .selectable = false, .text_overflow = .ellipsis, .use_monospace_font = mono };
}
pub fn paragraph(size: f32, weight: u16) ui.TextStyle {
    var result = text(size, weight, false);
    result.line_height = (if (size >= 14) @as(f32, 20) else if (size >= 12) @as(f32, 18) else 16) / size;
    result.wrap = .word;
    result.text_overflow = .clip;
    return result;
}
pub fn icon(size: f32) ui.Style {
    return .{ .width = .{ .px = size }, .height = .{ .px = size }, .flex_shrink = 0 };
}
pub fn chip() ui.BoxStyle {
    return .{ .width = .{ .fit = .{} }, .min_width = 68, .height = .{ .px = 20 }, .direction = .row, .padding = .{ .left = 0, .right = 0 }, .background = ui.Color.TRANSPARENT, .border = .{ .radius = 6 }, .align_items = .center, .justify = .center, .flex_shrink = 0 };
}
pub fn attemptLabel() ui.BoxStyle {
    return .{ .width = .{ .fit = .{} }, .min_width = 64, .height = .{ .px = 16 }, .flex_shrink = 0 };
}
pub fn attemptText() ui.TextStyle {
    var result = text(10.5, 500, false);
    result.color = theme.current().fg_2;
    result.text_overflow = .clip;
    return result;
}
pub fn notice(failed: bool) ui.BoxStyle {
    // Status (CZPr7): plain block on the pane — title 20/600, detail 13, gap 4.
    _ = failed;
    return .{ .width = .fill(), .height = .{ .fit = .{} }, .padding = .{}, .gap = 4, .direction = .column, .background = ui.Color.TRANSPARENT, .border = .{ .radius = 0 }, .flex_shrink = 0 };
}
pub fn logs() ui.BoxStyle {
    // Log well (ybb2B CxmC6): zw.island.rest, r8.
    return .{ .width = .fill(), .height = .{ .px = 124 }, .background = zw().zw_island_rest, .border = .{ .radius = 8 }, .flex_shrink = 0, .overflow_hidden = true };
}
pub fn logContent() ui.BoxStyle {
    var result = stack();
    result.padding = .{ .top = 8, .bottom = 8, .left = 10, .right = 10 };
    result.gap = 2;
    return result;
}
pub fn button(w: f32, h: f32, primary: bool) ui.BoxStyle {
    // Button / primary (W:vp4Ld) solid accent; secondary (W:jHqcg) bg_primary + hairline; r6.
    const c = zw();
    return .{ .width = .{ .px = w }, .height = .{ .px = h }, .padding = .{}, .background = if (primary) theme.current().action_accent else c.bg_primary, .corner_radius = 6, .border = .{ .overlay = true, .radius = 6, .width = if (primary) 0 else 1, .color = if (primary) ui.Color.TRANSPARENT else c.border }, .align_items = .center, .justify = .center, .flex_shrink = 0 };
}
pub fn ghostHover(pressed: bool) ui.BoxStyle {
    return .{ .background = theme.current().fg_2.withAlpha(if (pressed) 32 else 20) };
}
pub fn actionHover(primary: bool, pressed: bool) ui.BoxStyle {
    const base = if (primary) theme.current().action_accent else theme.popupAction();
    return .{ .background = ui.Color.lerp(base, if (primary or pressed) ui.Color.BLACK else theme.current().fg_2, if (pressed) 0.18 else 0.1) };
}
pub fn iconButton(size: f32) ui.BoxStyle {
    var result = button(size, size, false);
    result.background = ui.Color.TRANSPARENT;
    result.border = .{ .radius = 6, .width = 0, .color = ui.Color.TRANSPARENT };
    result.corner_radius = 6;
    return result;
}
pub fn actionText(primary: bool) ui.TextStyle {
    var result = text(13, 500, false);
    result.color = if (primary) theme.widgetTheme(theme.currentName()).tokens.color.button_primary_fg else theme.current().fg_1;
    return result;
}
pub fn authentication() ui.BoxStyle {
    var result = stack();
    result.display = .none;
    return result;
}

// Target identity and state stay separate from the current phase.
pub fn identity() ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .fit = .{} }, .min_width = 0, .flex = 1, .direction = .row, .align_items = .end, .gap = 8 };
}
// Identity line above the status: 13 semibold (the 20 status title is the summary).
pub fn targetTitle() ui.TextStyle {
    var result = text(13, 600, false);
    result.line_height = 18.0 / 13.0;
    return result;
}
pub fn stateBadge(failed: bool) ui.BoxStyle {
    return .{ .width = .{ .fit = .{} }, .height = .{ .px = 24 }, .padding = .{ .left = 8, .right = 8 }, .align_items = .center, .justify = .center, .background = (if (failed) theme.current().danger else theme.current().accent).withAlpha(23), .border = .{ .radius = 6 }, .flex_shrink = 0 };
}
pub fn disclosure() ui.BoxStyle {
    return .{ .width = .{ .px = 112 }, .height = .{ .px = 28 }, .direction = .row, .align_items = .center, .justify = .start, .padding = .{ .left = 4, .right = 4 }, .gap = 6, .background = ui.Color.TRANSPARENT, .border = .{ .radius = 6 }, .flex_shrink = 0 };
}
pub fn copyButton() ui.BoxStyle {
    return .{ .width = .{ .px = 96 }, .height = .{ .px = 28 }, .direction = .row, .align_items = .center, .justify = .center, .gap = 6, .padding = .ZERO, .background = ui.Color.TRANSPARENT, .border = .{ .radius = 6 }, .flex_shrink = 0 };
}

pub fn logRow() ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .fit = .{} }, .min_width = 0, .flex_shrink = 0, .hit_behavior = .@"opaque" };
}
pub fn diagnosticPanel() ui.BoxStyle {
    return .{ .height = .{ .fit = .{} }, .direction = .column, .padding = ui.Padding.all(12), .gap = 8, .background = ui.Color.TRANSPARENT, .border = .{ .radius = 9, .width = 0 } };
}

fn zw() @FieldType(@FieldType(ui.ThemeTokens, "tokens"), "color") {
    return theme.widgetTheme(theme.currentName()).tokens.color;
}
