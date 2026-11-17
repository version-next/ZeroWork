//! Child list (Pencil O8 `TTNSh`, ai-redesign-c) and the child dialog. The popover panel, the close button
//! and the row's press semantics are native (W.Popover default panel, ghost W.Button, W.Pressable); here
//! only layout, body text and the row's hover / press look in zenit tokens.
const ui = @import("ui");
const theme = @import("../../../../shared/ui/theme/app_theme.zig");
const Sessions = @import("ai_sessions_styles.zig");
pub const panel = Sessions.panel;
pub const heading = Sessions.heading;
pub const headingIcon = Sessions.headingIcon;
pub const headingTitle = Sessions.headingTitle;
pub const headingCount = Sessions.headingCount;
/// The list grows with its rows up to 252 (about five rows with group titles), then scrolls.
pub fn list() ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .fit = .{ .max = 252 } }, .max_height = 252, .min_height = 0 };
}
pub fn emptyRow() ui.BoxStyle {
    return .{ .width = .fill(), .padding = .{ .left = 8, .right = 8, .top = 6, .bottom = 8 }, .flex_shrink = 0 };
}
/// Group title (待处理 / 进行中 / 最近结束): 11/500 fg-tertiary, padding 6 8 2 8.
pub fn groupTitle(t: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 11, .font_weight = 500, .line_height = 1.5, .color = t.tokens.color.fg_tertiary, .selectable = false };
}
pub fn groupTitleBox() ui.BoxStyle {
    return .{ .width = .fill(), .padding = .{ .left = 8, .right = 8, .top = 6, .bottom = 2 }, .flex_shrink = 0 };
}
pub fn rowCopy() ui.BoxStyle {
    return .{ .width = .fill(), .flex = 1, .min_width = 0, .direction = .column };
}
pub fn statusSlot() ui.BoxStyle {
    return .{ .width = .{ .px = 14 }, .height = .{ .px = 14 }, .align_items = .center, .justify = .center, .flex_shrink = 0 };
}
/// Row name 12.5/500 fg-primary (also the dialog's settings name label).
pub fn name(t: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 12.5, .font_weight = 500, .line_height = 1.5, .color = t.tokens.color.fg_primary, .text_overflow = .ellipsis };
}
/// Detail / secondary text 11 fg-secondary.
pub fn secondary(t: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 11, .line_height = 1.5, .color = t.tokens.color.fg_secondary, .text_overflow = .ellipsis };
}
pub fn detail(_: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 11, .color = theme.current().fg_2, .wrap = .word };
}
pub fn status(_: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 11, .color = theme.current().accent };
}

pub fn settings(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .direction = .column, .padding = .{}, .overflow_hidden = true };
}

pub fn settingsBody(viewport_height: f32) ui.BoxStyle {
    const limit = @max(80, @min(300, viewport_height - 136));
    return .{ .width = .fill(), .height = .{ .fit = .{ .max = limit } }, .max_height = limit, .min_height = 0, .flex_shrink = 0 };
}
pub fn settingsContent(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .fit = .{} }, .direction = .column, .padding = .{ .left = 12, .right = 12, .top = 2, .bottom = 12 }, .gap = 8, .flex_shrink = 0 };
}
pub fn settingsRow(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .min_height = 28, .direction = .row, .align_items = .center, .gap = 12, .flex_shrink = 0 };
}
pub fn settingLabel(_: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 12, .font_weight = 500, .color = theme.current().fg_1, .text_overflow = .ellipsis };
}
pub fn divider(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = 1 }, .background = theme.current().border, .flex_shrink = 0 };
}
pub fn settingsFooter(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = 40 }, .direction = .row, .align_items = .center, .justify = .end, .padding = .{ .left = 12, .right = 12 }, .border_top_width = 1, .border_top_color = theme.current().border, .flex_shrink = 0 };
}
