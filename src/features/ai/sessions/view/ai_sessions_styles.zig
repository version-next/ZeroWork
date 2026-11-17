//! AI 会话列表 / 会话行的排版（Pencil O7 `SmqQV` / `zMxw4`，ai-redesign-c）：弹层是原生 `W.Popover` 默认面板，
//! 标签是原生 `W.Tag`、按钮是原生 ghost `W.Button`——这里只写布局与正文文字（zenit token 墨色），不写原生组件的
//! 背景、圆角、阴影。
const ui = @import("ui");

/// Popover content: padding 6, rows 2 apart (O7 V8OxC).
pub const content_padding: f32 = 6;
pub const row_gap: f32 = 2;
/// PanelHeader (no grip): 30 high (O7 G3Ky0y).
pub const header_height: f32 = 30;
/// One session row: 8 + 19 + 4 + 24 + 8 (line 2 holds native xs icon buttons, 23.6 square in zenit;
/// the design's 20 is the design value — zenit wins).
pub const row_height: f32 = 63;
/// The empty text row.
pub const empty_height: f32 = 40;
/// 显示更多（W.Button link sm 28）.
pub const more_height: f32 = 28;

pub fn listSurface() ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = 0 }, .flex_shrink = 0, .display = .flex };
}
pub fn panel() ui.BoxStyle {
    return .{ .width = .fill(), .direction = .column, .padding = ui.Padding.all(content_padding), .gap = row_gap };
}
pub fn menu() ui.BoxStyle {
    return .{ .width = .fill(), .direction = .column, .gap = row_gap };
}
/// PanelHeader：icon 14 · title 12/600 · count 11 · spacer · close ghost sm 24；padding 0 0 0 8, gap 6.
pub fn heading() ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = header_height }, .flex_shrink = 0, .direction = .row, .align_items = .center, .gap = 6, .padding = .{ .left = 8 } };
}
pub fn headingIcon() ui.Style {
    return .{ .width = .{ .px = 14 }, .height = .{ .px = 14 }, .flex_shrink = 0 };
}
pub fn headingTitle(t: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 12, .font_weight = 600, .line_height = 1.5, .color = t.tokens.color.fg_primary, .selectable = false };
}
pub fn headingCount(t: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 11, .line_height = 1.5, .color = t.tokens.color.fg_secondary, .selectable = false, .text_overflow = .ellipsis };
}
pub fn emptyText(t: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 11, .line_height = 1.5, .color = t.tokens.color.fg_secondary, .wrap = .word };
}
pub fn emptyRow() ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .fit = .{} }, .min_height = empty_height, .padding = .{ .left = 8, .right = 8, .top = 4, .bottom = 8 }, .flex_shrink = 0 };
}

/// Session row (ai_session_row, O7 cMKkE): column, padding 8, gap 4, radius 6; the current
/// conversation sits on bg-hover.
pub fn row() ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .fit = .{} }, .direction = .column, .gap = 4, .padding = ui.Padding.all(8), .flex_shrink = 0 };
}
pub fn rowBackground(t: *const ui.ThemeTokens, active: bool, hovered: bool) ui.BoxStyle {
    return .{ .background = if (active or hovered) t.tokens.color.bg_hover else ui.Color.TRANSPARENT, .corner_radius = 6 };
}
pub fn rowContent() ui.BoxStyle {
    return .{ .width = .fill(), .min_width = 0, .direction = .column, .gap = 4 };
}
/// Line 1: title (12.5/500) · spacer · W.Tag sm; 19 high, gap 6.
pub fn firstLine() ui.BoxStyle {
    return .{ .width = .fill(), .min_width = 0, .height = .{ .px = 19 }, .direction = .row, .align_items = .center, .gap = 6, .flex_shrink = 0 };
}
/// Line 2: 已绑定 / 未绑定 (11) · 归属 (11 fg-secondary) · spacer · ghost xs icon buttons; 24 high, gap 6.
pub fn secondLine() ui.BoxStyle {
    return .{ .width = .fill(), .min_width = 0, .height = .{ .px = 24 }, .direction = .row, .align_items = .center, .gap = 6, .flex_shrink = 0 };
}
pub fn rowActions() ui.BoxStyle {
    return .{ .width = .{ .fit = .{} }, .height = .{ .px = 24 }, .direction = .row, .align_items = .center, .gap = 6, .flex_shrink = 0 };
}
pub fn title(t: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 12.5, .font_weight = 500, .line_height = 1.5, .color = t.tokens.color.fg_primary, .text_overflow = .ellipsis, .selectable = false };
}
pub fn titleBox() ui.BoxStyle {
    return .{ .width = .fill(), .min_width = 0, .height = .{ .px = 19 }, .overflow_hidden = true };
}
pub fn binding(t: *const ui.ThemeTokens, bound: bool) ui.TextStyle {
    return .{ .font_size = 11, .line_height = 1.5, .color = if (bound) t.tokens.color.accent else t.tokens.color.fg_tertiary, .selectable = false };
}
pub fn boundText(t: *const ui.ThemeTokens) ui.TextStyle {
    return binding(t, true);
}
pub fn unboundText(t: *const ui.ThemeTokens) ui.TextStyle {
    return binding(t, false);
}
pub fn owner(t: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 11, .line_height = 1.5, .color = t.tokens.color.fg_secondary, .text_overflow = .ellipsis, .selectable = false };
}
pub fn ownerBox() ui.BoxStyle {
    return .{ .width = .fill(), .min_width = 0, .height = .{ .px = 17 }, .flex = 1 };
}

/// Read-only history dialog text (ai.history).
pub fn dialogDetail() ui.TextStyle {
    return .{ .font_size = 11, .font_weight = 400, .line_height = 16.0 / 11.0, .wrap = .word, .text_overflow = .ellipsis };
}
pub fn dialogDetailStyle(t: *const ui.ThemeTokens) ui.TextStyle {
    var s = dialogDetail();
    s.color = t.tokens.color.fg_secondary;
    return s;
}
pub fn dialogTitle(t: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 13, .font_weight = 600, .line_height = 20.0 / 13.0, .color = t.tokens.color.fg_primary, .text_overflow = .ellipsis };
}
pub fn actions() ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = 28 }, .direction = .row, .justify = .end, .align_items = .center, .gap = 8 };
}
