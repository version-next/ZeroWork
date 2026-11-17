//! Current transfer contract: 76px shallow cards, direct actions and hover details.
//! Island B v3 (Pencil `R3LCmV` 传输窗口, `Gq5xg` 传输弹层): window/island radius 12,
//! popover radius 10, task rows radius 6, 4pt progress (W:hl4YW, radius 2),
//! 24pt ghost actions (W:SwTks, radius 6), md buttons radius 6.
const ui = @import("ui");
pub const theme = @import("../../../shared/ui/theme/app_theme.zig");
pub const path_line_height: f32 = 18;
// Existing header 48 + inner top/bottom 8/16 + footer gap/height 10/34.
// Body height is measured from its real children, including validation errors.
pub const confirmation_chrome_height: f32 = 48 + 8 + 16 + 10 + 34;
pub const row_height: f32 = 76;
pub const row_pitch: f32 = 84;
pub const detail_height: f32 = 176;
pub fn panel(window: bool) ui.BoxStyle {
    return .{ .width = .{ .px = if (window) 840 else 620 }, .height = .{ .px = if (window) 578 else 330 }, .direction = .column, .padding = .{ .top = 17, .left = 14, .right = 14, .bottom = if (window) 16 else 18 }, .background = theme.current().overlay, .glass = theme.overlayGlass(), .border = .{ .radius = 12 }, .overflow = .hidden, .flex_shrink = 0 };
}
/// Content of the title bar's native Popover (title-click): same box as `panel`, the Popover chrome is the surface.
pub fn popoverContent() ui.BoxStyle {
    return .{ .width = .{ .px = 840 }, .height = .{ .px = 578 }, .direction = .column, .padding = .{ .top = 17, .left = 14, .right = 14, .bottom = 16 }, .overflow = .hidden, .flex_shrink = 0 };
}
pub fn row(h: f32, spacing: f32) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = h }, .direction = .row, .align_items = .center, .gap = spacing, .min_width = 0, .flex_shrink = 0 };
}
pub fn stack() ui.BoxStyle {
    return .{ .width = .fill(), .height = .fill(), .direction = .column, .min_width = 0, .min_height = 0 };
}
pub fn gap(h: f32) ui.BoxStyle {
    return .{ .height = .{ .px = h }, .flex_shrink = 0 };
}
pub fn text(size: f32, weight: u16, secondary: bool) ui.TextStyle {
    return .{ .font_size = size, .font_weight = weight, .line_height = 1.5, .color = if (secondary) theme.current().fg_2 else theme.current().fg_1 };
}
pub fn label(w: f32) ui.BoxStyle {
    return .{ .width = .{ .px = w }, .min_width = 0, .flex_shrink = 0, .overflow = .hidden };
}
pub fn flexibleLabel() ui.BoxStyle {
    return .{ .width = .fill(), .min_width = 0, .flex = 1, .overflow = .hidden };
}
pub fn icon(size: f32) ui.Style {
    return .{ .width = .{ .px = size }, .height = .{ .px = size }, .flex_shrink = 0 };
}
pub fn badge(width: f32, _: ui.Color) ui.BoxStyle {
    return .{ .width = .{ .px = width }, .height = .{ .px = 22 }, .padding = .{ .left = 8, .right = 8 }, .align_items = .center, .justify = .center, .background = theme.popupInset(), .border = .{ .radius = 6 }, .flex_shrink = 0 };
}
pub fn task(selected: bool) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = row_height }, .direction = .column, .gap = 7, .padding = .{ .top = 9, .left = 10, .right = 10, .bottom = 9 }, .background = if (selected) theme.popupSelection() else theme.popupInset(), .border = .{ .radius = 6 }, .flex_shrink = 0 };
}
pub fn detail() ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = 120 }, .direction = .column, .gap = 4, .padding = .{ .top = 8, .left = 10, .right = 10, .bottom = 8 }, .background = ui.Color.TRANSPARENT, .border = .{ .radius = 8 }, .flex_shrink = 0, .overflow = .hidden };
}
pub fn track() ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = 4 }, .background = theme.states().range_track, .border = .{ .radius = 2 }, .flex_shrink = 0 };
}
pub fn fill(fraction: f32, color: ui.Color) ui.BoxStyle {
    return .{ .width = .{ .percent = fraction * 100 }, .height = .fill(), .background = color, .border = .{ .radius = 2 } };
}
/// Right gutter inside the task list, beside the scrollbar.
pub const list_gutter: f32 = 14;
pub fn viewport() ui.BoxStyle {
    return .{ .width = .fill(), .height = .fill(), .flex = 1, .min_height = 0, .min_width = 0 };
}
// Vanta empty list: use the available list viewport, with one centered status.
pub fn emptyState() ui.BoxStyle {
    // VlICC Empty: gap 6, bottom padding 44 lifts the group above center.
    return .{ .width = .fill(), .height = .fill(), .flex = 1, .min_height = 0, .min_width = 0, .direction = .column, .align_items = .center, .justify = .center, .gap = 6, .padding = .{ .bottom = 44 }, .overflow = .hidden };
}
pub fn errorLine() ui.BoxStyle {
    return .{ .width = .fill(), .min_height = 24, .padding = .{ .top = 3, .bottom = 3 }, .flex_shrink = 0 };
}

pub fn repaint(node: *ui.Node, previous: theme.Colors) void {
    theme.setRetainedBackground(node, remap(node.getBackground(), previous));
    if (node.getText()) |text_value| node.setTextColor(remapInk(text_value.color, previous));
    if (node.getIcon()) |icon_value| _ = node.setTint(remapInk(icon_value.tint, previous));
    for (node.children.items) |child| repaint(child, previous);
}
fn remapInk(color: ui.Color, previous: theme.Colors) ui.Color {
    const inks = .{ "fg_1", "fg_2", "fg_3", "accent_ink", "ok_ink", "warn_ink", "danger_ink" };
    // Styled text recipes already repaint on the theme publication that precedes
    // this walk; ink that is already a current role must not be remapped again
    // (light fg_1 can equal a previous dark surface and would turn into a fill).
    inline for (inks) |field| {
        if (ui.Color.eql(color, @field(theme.current(), field))) return color;
    }
    // Some dark palettes share the base and readable ink RGB; preserve the
    // foreground role when the next light palette separates those colors.
    inline for (inks) |field| {
        if (ui.Color.eql(color, @field(previous, field))) return @field(theme.current(), field);
    }
    return remap(color, previous);
}
fn remap(color: ui.Color, previous: theme.Colors) ui.Color {
    if (theme.remapUiSurface(color, previous)) |next| return next;
    const next = theme.current();
    inline for (@typeInfo(theme.Colors).@"struct".field_names) |field| {
        if (ui.Color.eql(color, @field(previous, field))) return @field(next, field);
    }
    return color;
}

/// Confirmation Modal geometry only: the panel surface is zenit Modal's default.
/// Own column in the native Modal's body slot: header, then the form.
pub fn confirmationForm() ui.BoxStyle {
    // Fills the Modal body: the panel's height (natural, capped by the window / the pane) decides it.
    return .{ .width = .fill(), .height = .fill(), .min_height = 0, .direction = .column, .gap = 0, .overflow = .hidden, .flex_shrink = 1 };
}
pub fn confirmationHeader() ui.BoxStyle {
    var value = row(48, 6);
    value.padding = .{ .left = 16, .right = 14 };
    return value;
}
pub fn confirmationInner() ui.BoxStyle {
    var value = stack();
    value.flex = 1;
    value.padding = .{ .top = 8, .left = 16, .right = 16, .bottom = 16 };
    return value;
}
pub fn confirmationStack() ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .fit = .{} }, .direction = .column, .gap = 10, .flex_shrink = 0 };
}
pub fn confirmationIdentity() ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .fit = .{} }, .direction = .column, .gap = 4, .padding = ui.Padding.all(12), .background = theme.popupAction(), .border = .{ .radius = 9 }, .flex_shrink = 0 };
}
pub fn confirmationSources() ui.BoxStyle {
    return confirmationStack();
}
pub fn confirmationHint() ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = 16 }, .flex_shrink = 0 };
}
pub fn pathRow() ui.BoxStyle {
    var value = row(32, 6);
    value.padding = .{ .left = 8, .right = 8 };
    value.background = theme.popupInset();
    value.border = .{ .radius = 8 };
    return value;
}
pub fn option() ui.BoxStyle {
    return .{ .width = .{ .px = 98 }, .height = .{ .px = 24 }, .padding = .{}, .background = theme.popupAction(), .border = .{ .radius = 7 }, .flex_shrink = 0 };
}
pub fn topFade(_: *const ui.ThemeTokens) ui.BoxStyle {
    const c = theme.current();
    return .{ .width = .fill(), .height = .{ .px = 72 }, .position = .absolute, .inset = .{ .left = .{ .px = 0 }, .top = .{ .px = 0 } }, .gradient = .{ .from = c.well_border.withAlpha(48), .to = c.overlay.withAlpha(0) }, .border = .{ .radius = 12 }, .hit_behavior = .pass_through };
}
pub fn grip(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .position = .absolute, .inset = .{ .top = .{ .px = 7 }, .left = .{ .percent = 50 } }, .width = .{ .px = 32 }, .height = .{ .px = 3 }, .margin = .{ .left = -16 }, .background = theme.current().fg_3, .border = .{ .radius = 1.5 }, .hit_behavior = .pass_through };
}

// Shared compact transfer row and bounded popover presentations.
pub const v3_card_height: f32 = row_height;
pub const v3_card_pitch: f32 = row_pitch;
pub fn v3Panel(global: bool) ui.BoxStyle {
    // Transparent HTML border consumes 1px in addition to the 12px padding.
    return .{ .width = .{ .px = if (global) 640 else 560 }, .height = .{ .px = 199 }, .direction = .column, .padding = ui.Padding.all(13), .background = theme.current().overlay, .glass = theme.overlayGlass(), .border = .{ .radius = 10 }, .overflow = .hidden, .flex_shrink = 0, .hit_behavior = .@"opaque" };
}
pub fn v3EmptyState() ui.BoxStyle {
    return .{ .width = .fill(), .height = .fill(), .flex = 1, .min_width = 0, .min_height = 0, .direction = .row, .align_items = .center, .gap = 10, .padding = .{ .top = 8, .bottom = 8, .left = 4, .right = 4 }, .overflow = .hidden };
}
pub fn v3EmptyIcon() ui.BoxStyle {
    return .{ .width = .{ .px = 24 }, .height = .{ .px = 24 }, .align_items = .center, .justify = .center, .flex_shrink = 0 };
}
pub fn v3Segment() ui.BoxStyle {
    var s = row(30, 3);
    s.padding = ui.Padding.all(3);
    s.background = theme.popupInset();
    s.border = .{ .radius = 8 };
    return s;
}
pub fn v3Filter(selected: bool) ui.BoxStyle {
    return .{ .width = .fill(), .height = .fill(), .flex = 1, .padding = .{ .top = 4, .bottom = 4, .left = 8, .right = 8 }, .font_size = 11, .font_weight = 400, .text_color = if (selected) theme.current().accent_ink else theme.current().fg_2, .background = if (selected) theme.popupSelection() else theme.popupAction(), .border = .{ .radius = 6 }, .shadow = .{}, .align_items = .center, .justify = .center };
}
pub fn v3Card() ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = v3_card_height }, .direction = .column, .padding = .{ .left = 10, .right = 10, .top = 7, .bottom = 9 }, .background = theme.popupInset(), .border = .{ .radius = 6 }, .flex_shrink = 0 };
}

pub fn v3Footer() ui.BoxStyle {
    var s = row(38, 8);
    s.padding = .{ .top = 8 };
    return s;
}

/// Embedded SFTP tray shares exactly the same task renderer as both popovers.
pub fn sessionTray() ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = 127 }, .min_width = 0, .flex_shrink = 0, .direction = .column, .padding = .{ .top = 9, .right = 12, .bottom = 8, .left = 12 }, .background = theme.current().overlay, .border = .{ .radius = 16 }, .overflow = .hidden };
}

pub fn hoverDetail() ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .fit = .{} }, .min_width = 0, .direction = .column, .gap = 12, .padding = ui.Padding.all(14) };
}

pub fn hoverDetailField() ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .fit = .{} }, .min_width = 0, .direction = .column, .gap = 4, .flex_shrink = 0 };
}

pub fn hoverDetailIdentity() ui.BoxStyle {
    return .{ .width = .fill(), .min_width = 0, .padding = .{ .top = 7, .bottom = 7, .left = 8, .right = 8 }, .background = theme.popupInset(), .border = .{ .radius = 8 }, .flex_shrink = 0 };
}

pub fn optionTag(enabled: bool) ui.BoxStyle {
    return .{ .height = .{ .px = 24 }, .padding = .{ .left = 8, .right = 8, .top = 3, .bottom = 3 }, .background = if (enabled) theme.popupInset() else theme.popupAction(), .border = .{ .radius = 5 }, .flex_shrink = 0 };
}


// ---- Island B v3 task rows -------------------------------------------------
/// R3LCmV Transfer row: 48 high, radius 6, padding [0, 10], gap 12.
pub const table_row_height: f32 = 48;
/// Gq5xg Transfer row: padding [7, 8] around name 16 / gap 3 / meta 14 / gap 3 / bar 4.
pub const popover_row_height: f32 = 54;
pub const name_line: f32 = 16;
pub const meta_line: f32 = 14;
/// R3LCmV columns: 连接 148 (owner column, adaptive), 进度 168, 速度 84.
pub const connection_column: f32 = 148;
pub const progress_column: f32 = 168;
pub const speed_column: f32 = 84;
pub const rate_max: f32 = 120;
pub const status_max: f32 = 96;
pub const compact_button_size: ui.widgets.button.ButtonSize = .sm;
const action_gap: f32 = 2;

pub fn actionSide(t: *const ui.ThemeTokens) f32 {
    const shell = ui.widgets.control_shell;
    const metrics = shell.metrics(t, compact_button_size);
    // Icon-only Button padding is measured around its glyph, while the native icon slot retains its minimum.
    const glyph = shell.glyphSize(compact_button_size);
    return @max(glyph, metrics.icon_size) + @max(0, metrics.derivedHeight() - glyph);
}
/// Four native icon buttons and three gaps. The same measurement sizes the table header and every row.
pub fn actionsWidth(t: *const ui.ThemeTokens) f32 {
    return 4 * actionSide(t) + 3 * action_gap;
}
/// A task row's own fill: flat unless selected. The selection tint is opaque on the opaque
/// panels (transfer window, native popovers) and a first-layer card on the pane island (tray).
pub fn taskRowFill(selected: bool, in_tray: bool) ui.Color {
    if (!selected) return ui.Color.TRANSPARENT;
    return @import("../../../shared/ui/styles/surface_material.zig").fill(theme.popupSelection(), if (in_tray) .canvas else .solid);
}
pub fn tableRow(selected: bool, in_tray: bool) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = table_row_height }, .direction = .row, .align_items = .center, .gap = 12, .padding = .{ .left = 10, .right = 10 }, .background = taskRowFill(selected, in_tray), .border = .{ .radius = 6 }, .min_width = 0, .flex_shrink = 0 };
}
pub fn popoverRow(selected: bool, in_tray: bool) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = popover_row_height }, .direction = .row, .align_items = .center, .gap = 10, .padding = .{ .top = 7, .bottom = 7, .left = 8, .right = 8 }, .background = taskRowFill(selected, in_tray), .border = .{ .radius = 6 }, .min_width = 0, .flex_shrink = 0 };
}
/// 文件 cell: 24pt icon + copy column, gap 10.
pub fn fileCell() ui.BoxStyle {
    return .{ .width = .fill(), .flex = 1, .min_width = 0, .direction = .row, .align_items = .center, .gap = 10, .overflow = .hidden };
}
/// Name over detail, gap 3.
pub fn copyColumn() ui.BoxStyle {
    return .{ .width = .fill(), .flex = 1, .min_width = 0, .direction = .column, .gap = 3, .justify = .center };
}
pub fn cellColumn(w: f32, spacing: f32) ui.BoxStyle {
    return .{ .width = .{ .px = w }, .min_width = 0, .flex_shrink = 0, .direction = .column, .gap = spacing, .justify = .center, .overflow = .hidden };
}
pub fn fitLabel(max: f32) ui.BoxStyle {
    return .{ .width = .{ .fit = .{} }, .max_width = max, .min_width = 0, .flex_shrink = 1, .overflow = .hidden };
}
/// 操作 cell: native ghost actions, gap 2, right aligned.
pub fn actionsCell(t: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .{ .px = actionsWidth(t) }, .height = .{ .px = actionSide(t) }, .direction = .row, .align_items = .center, .justify = .end, .gap = action_gap, .flex_shrink = 0 };
}
pub fn actionsHeader(t: *const ui.ThemeTokens) ui.BoxStyle {
    return cellColumn(actionsWidth(t), 0);
}
pub fn passiveActionSlot(t: *const ui.ThemeTokens) ui.BoxStyle {
    const side = actionSide(t);
    return .{ .width = .{ .px = side }, .height = .{ .px = side }, .align_items = .center, .justify = .center, .flex_shrink = 0 };
}
/// R3LCmV list header: 26 high, bottom bg-active hairline, padding [0, 10], gap 12.
pub fn tableHeader(t: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = 26 }, .direction = .row, .align_items = .center, .gap = 12, .padding = .{ .left = 10, .right = 10 }, .border = .{ .overlay = true, .side_widths = .{ 0, 0, 1, 0 }, .width = 0, .color = t.tokens.color.bg_active }, .flex_shrink = 0, .min_width = 0 };
}
pub fn headerLabel(_: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 11.5, .line_height = 16.0 / 11.5, .color = theme.current().fg_2, .wrap = .none };
}
