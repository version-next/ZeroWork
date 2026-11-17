//! KVM connection form, measured at 1488×1040 CSS px, zoom 1,
//! DPR 1 (App 1440×900). The shared Wizard owns the 760px modal/header.
const ui = @import("ui");
pub const host = @import("../../features/connections/wizard/view/wizard_styles.zig");
pub const theme = host.theme;
pub const width: f32 = host.width;

pub fn root(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .fill(), .min_height = 0, .direction = .column, .gap = 0, .flex = 1 };
}
pub fn content(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .fit = .{} }, .direction = .column, .padding = .{ .left = 24, .right = 24, .bottom = 20 }, .gap = 12, .flex_shrink = 0 };
}
pub fn row(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .fit = .{} }, .direction = .row, .align_items = .start, .gap = 16, .min_width = 0, .flex_shrink = 0 };
}
pub fn field(_: *const ui.ThemeTokens) ui.BoxStyle {
    // Equal columns whatever the control inside (an Input and a native Select have different
    // content widths): basis 0, so the row splits evenly and each control fills its column.
    return .{ .width = .fill(), .height = .{ .fit = .{} }, .direction = .column, .gap = 5, .min_width = 0, .flex = 1, .flex_basis = 0, .flex_shrink = 1 };
}
pub fn label(tokens: *const ui.ThemeTokens) ui.TextStyle {
    return host.label(tokens);
}
pub fn section(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = 18 }, .direction = .row, .align_items = .center, .gap = 10, .flex_shrink = 0 };
}
pub fn sectionLabel(_: *const ui.ThemeTokens) ui.TextStyle {
    return host.text(12, 700, false);
}
pub fn footer(_: *const ui.ThemeTokens) ui.BoxStyle {
    var value = host.footer();
    value.gap = 8;
    return value;
}
pub fn routeRow(_: *const ui.ThemeTokens) ui.BoxStyle {
    return host.routeHop();
}
/// The hop row's flexible column for its native Select (which fills it).
pub fn routePicker(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .direction = .column, .flex = 1, .min_width = 0 };
}
pub fn routeNumber(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .{ .px = 22 }, .height = .{ .px = 22 }, .align_items = .center, .justify = .center, .background = theme.popupSelection(), .border = .{ .radius = 11 }, .flex_shrink = 0 };
}
pub fn routePreview(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .fit = .{} }, .direction = .column, .padding = .{ .left = 14, .right = 14, .top = 12, .bottom = 12 }, .background = theme.popupInset(), .border = .{ .radius = 9 }, .flex_shrink = 0 };
}
pub fn previewText(_: *const ui.ThemeTokens) ui.TextStyle {
    var value = host.text(11, 400, false);
    value.line_height = 1.8;
    value.wrap = .word;
    value.text_overflow = .clip;
    return value;
}
pub fn feedback(_: *const ui.ThemeTokens) ui.TextStyle {
    var value = host.paragraph(undefined);
    value.font_size = 11;
    value.line_height = 17.0 / 11.0;
    value.color = theme.current().fg_2;
    return value;
}
pub fn feedbackArea(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .fit = .{} }, .min_height = 34, .direction = .row, .align_items = .center, .gap = 12, .padding = .{ .left = 24, .right = 24, .top = 4, .bottom = 4 }, .flex_shrink = 0 };
}
pub fn logText(_: *const ui.ThemeTokens) ui.TextStyle {
    var value = feedback(undefined);
    value.line_height = 20.0 / 11.0;
    value.use_monospace_font = true;
    return value;
}
pub fn errorText(_: *const ui.ThemeTokens) ui.TextStyle {
    var value = host.paragraph(undefined);
    value.color = theme.current().danger_ink;
    return value;
}
/// The box that holds a native Checkbox beside / under a 34pt field: content sized, centred.
pub fn checkSlot(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .{ .fit = .{} }, .height = .{ .px = 34 }, .direction = .row, .align_items = .center, .flex_shrink = 0 };
}
/// The probe log's viewport: gives the native ScrollArea its height.
pub fn logViewport(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = 200 }, .min_width = 0, .flex_shrink = 0 };
}
