//! AI conversation styles (header of the child dialog, transcript, composer). The floating main panel's
//! frame and header are the unified chrome (`shared/ui/float_card/float_chrome`).
const ui = @import("ui");
const IdSpace = @import("../../shared/view/ai_id_space.zig").IdSpace;
const theme = @import("../../../../shared/ui/theme/app_theme.zig");
pub const ButtonStyle = ui.StyleOverride;
pub fn header(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = 34 }, .flex_shrink = 0, .direction = .row, .align_items = .center, .gap = 6, .padding = .{ .left = 14, .right = 14, .bottom = 8, .top = 0 } };
}
pub fn title(_: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 13, .font_weight = 700, .line_height = 18.5 / 13.0, .color = theme.current().fg_1 };
}
pub fn secondary(_: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 11, .font_weight = 400, .line_height = 16.0 / 11.0, .color = theme.current().fg_2, .text_overflow = .ellipsis };
}
pub fn ownerText(_: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 11, .line_height = 20.0 / 11.0, .color = theme.current().fg_2, .text_overflow = .ellipsis };
}
pub fn windowControl() ButtonStyle {
    return .{ .width = .{ .px = 22 }, .height = .{ .px = 22 }, .padding = .{}, .gap = 0, .corner_radius = 6, .background = ui.Color.TRANSPARENT, .flex_shrink = 0 };
}
pub fn countBadge(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .position = .absolute, .inset = .{ .top = .{ .px = -1 }, .right = .{ .px = 0 } }, .height = .{ .px = 14 }, .background = ui.Color.TRANSPARENT, .padding = .{}, .border = .{ .width = 0, .radius = 0 } };
}
pub fn countBadgeText(_: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 9, .font_weight = 700, .line_height = 12.0 / 9.0, .text_align = .center, .color = theme.current().accent_ink };
}
pub fn icon() ui.Style {
    return .{ .width = .{ .px = 14 }, .height = .{ .px = 14 } };
}
pub fn regionIcon() ui.Style {
    return .{ .width = .{ .px = 18 }, .height = .{ .px = 18 }, .flex_shrink = 0 };
}
pub fn ownerPill(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .{ .fit = .{} }, .max_width = 160, .min_width = 0, .height = .{ .px = 20 }, .flex_shrink = 1, .direction = .row, .align_items = .center, .padding = .{ .left = 8, .right = 8 }, .background = theme.popupInset(), .border = .{ .radius = 8 }, .overflow = .hidden };
}
// ── Pencil Kaf7E A3 message flow (P2) ──
/// One horizontal inset for everything in the conversation column (messages, the live turn row,
/// task results, feedback): Kaf7E ③ "对话 ScrollArea padding 12 16 16 16".
pub const conversation_inset: f32 = 16;
pub const conversation_top: f32 = 12;
/// The reply ends 12 above the composer: the flow's last row (a turn's status row) keeps its 10 turn
/// gap below itself and its column adds 2 (the composer area has no top margin; a scroll content's
/// own bottom padding does not extend the scroll range, so the 2 sits on the columns).
pub const reply_to_composer: f32 = 12;
pub const conversation_bottom: f32 = reply_to_composer - (turn_gap - turn_block_gap);
/// Turns are 20 apart, blocks inside a turn 10 (Kaf7E ③): the column gap is the block gap; a user
/// row and a turn's status row add the other 10 below themselves.
pub const turn_gap: f32 = 20;
/// The width messages lay out in, from the conversation column's width.
pub fn contentWidth(column_width: f32) f32 {
    return @max(0, column_width - 2 * conversation_inset);
}
/// User bubble: at most 85% of the column, and 560 in the docked 720 column (Kaf7E ③ "≥760 时 ≤560").
pub fn userBubbleMaxWidth(content_width: f32) f32 {
    return @min(@max(0, content_width) * 0.85, 560);
}
/// The bubble itself is the native `W.Card` bubble (bg_active, radius panel, 8 12); its text column
/// caps the width (85% of the column less the card's horizontal padding) so long text wraps and
/// unbreakable runs break instead of widening the panel.
pub const user_bubble_padding_x: f32 = 24;
/// The cap of the bubble's text column for a message column `content_width` wide.
pub fn userBubbleTextMaxWidth(content_width: f32) f32 {
    return @max(0, userBubbleMaxWidth(content_width) - user_bubble_padding_x);
}
pub fn userBubbleBody(content_width: f32) ui.BoxStyle {
    return .{ .width = .{ .fit = .{} }, .max_width = userBubbleTextMaxWidth(content_width), .min_width = 0, .direction = .column, .gap = 6, .flex_shrink = 1 };
}
/// Sent attachments / images above the bubble: the same 85% cap as the bubble.
pub fn userAttachments(content_width: f32) ui.BoxStyle {
    return .{ .width = .{ .fit = .{} }, .max_width = userBubbleMaxWidth(content_width), .min_width = 0, .direction = .column, .gap = 4, .align_items = .end, .flex_shrink = 0 };
}
/// User text: 13 / 1.5 fg_primary.
pub fn userText(t: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = body_font_size, .line_height = 1.5, .wrap = .word_break, .color = t.tokens.color.fg_primary };
}
/// Hover actions under the bubble: 22 high, 2 apart (time 11 fg_tertiary, then ghost xs icons).
pub fn userActions(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .direction = .row, .gap = 2, .align_items = .center, .height = .{ .px = 22 }, .flex_shrink = 0 };
}
pub fn userTime(t: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 11, .line_height = 1.5, .color = t.tokens.color.fg_tertiary, .selectable = false };
}
pub fn messageRow(user: bool) ui.BoxStyle {
    // Align the measured, max-width-clamped bubble on the cross axis; a user row closes its turn
    // block (20 to what follows).
    return .{ .width = .fill(), .direction = .column, .align_items = if (user) .end else .start, .gap = 4, .padding = .{}, .margin = .{ .bottom = if (user) turn_gap - turn_block_gap else 0 }, .flex_shrink = 0 };
}
pub fn conversation(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .direction = .column, .gap = turn_block_gap, .padding = .{ .left = conversation_inset, .right = conversation_inset, .top = conversation_top, .bottom = conversation_bottom }, .height = .{ .fit = .{} }, .flex_shrink = 0 };
}
/// Holders after the conversation (task results, the live turn's status row): same inset, one block
/// gap above.
pub fn trailingHolder(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .min_width = 0, .height = .{ .fit = .{} }, .direction = .column, .gap = 8, .padding = .{ .left = conversation_inset, .right = conversation_inset, .top = turn_block_gap - conversation_bottom, .bottom = conversation_bottom }, .flex_shrink = 0 };
}
pub fn notice(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .min_width = 0, .height = .{ .fit = .{} }, .direction = .row, .align_items = .start, .gap = 8, .padding = .{ .left = 10, .right = 10, .top = 8, .bottom = 8 }, .background = theme.popupInset(), .border = .{ .radius = 8 }, .flex_shrink = 0 };
}
pub fn noticeText(_: *const ui.ThemeTokens) ui.TextStyle {
    // New zenit `.word` is CSS overflow-wrap:normal; long paths without spaces need the
    // emergency break (overflow-wrap:break-word) to stay inside the notice.
    return .{ .font_size = 11, .line_height = 18.0 / 11.0, .wrap = .word_break, .color = theme.current().fg_2 };
}
/// Composer area (Pencil Kaf7E ③ / ⑤): the queue, the decision panel or the composer, 8 apart;
/// margins 0 12 12 12 (320: 8; docked: 16; >= 760: a 720 column, see AiHost.layoutComposerArea).
pub fn composer(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .position = .relative, .width = .fill(), .height = .{ .fit = .{} }, .flex_shrink = 0, .direction = .column, .gap = 8, .padding = .{ .left = 12, .right = 12, .bottom = 12 } };
}
/// “稍后处理” capsule: right above the composer area, aligned to its right margin.
pub fn pendingCapsule() ui.BoxStyle {
    return .{ .position = .absolute, .inset = .{ .right = .{ .px = 12 }, .bottom = .{ .percent = 100 } }, .margin = .{ .bottom = 8 }, .z_index = 2 };
}

// Pencil Kaf7E A3: ordinary answers are open prose (no bubble); blocks 10 apart within a turn.
pub const turn_block_gap: f32 = 10;
pub fn assistantMessage() ui.BoxStyle {
    return .{ .width = .fill(), .min_width = 0, .direction = .column, .gap = turn_block_gap, .flex_shrink = 0 };
}
/// Kaf7E ③: body 13 / 1.6 fg_primary; headings 600 (16 for # / ##, 13 below — the type scale is
/// 11 / 12 / 13 / 16); blocks 10 apart; tables `.rules` (header 12/600 fg_secondary, a separator
/// under each row, no frame or column lines). Colours are zenit's (null = follow the theme).
/// `space`: the test-id namespace of the surface the text is shown in (it names the tables).
pub fn markdownOptions(space: IdSpace) ui.widgets.MarkdownOptions {
    return .{ .base_font_size = body_font_size, .code_font_size = code_font_size, .line_height = body_line_height, .code_line_height = code_line_height, .paragraph_gap = turn_block_gap, .heading_sizes = .{ 16, 16, 13, 13, 13, 13 }, .table = .rules, .table_test_id = space.id("ai.message.table"), .code_block = codeBlockOptions() };
}
/// Kaf7E A4: bg_secondary, radius 8, no border; header 28 (language, wrap, copy); code mono
/// 12 / 1.55; at most 320 high, scrolling inside both ways (lines keep their length until wrapped).
pub fn codeBlockOptions() ui.widgets.markdown.CodeBlockOptions {
    return .{ .frame = .borderless, .header = true, .max_height = code_max_height, .wrap = false };
}

pub const body_font_size: f32 = 13;
pub const body_line_height: f32 = 1.6;
pub const code_font_size: f32 = 12;
pub const code_line_height: f32 = 1.55;
pub const code_max_height: f32 = 320;


pub fn textSelection() ui.Color {
    return theme.current().accent_ink.withAlpha(80);
}
