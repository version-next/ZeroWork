//! Island B v3 SFTP workspace (Pencil `c0vKlM` 列表视图, `OQD5Y` 多选).
//! Structural boxes live in files/styles.yss; this module adapts them and
//! keeps the theme-ink text/row recipes that the repaint walk remaps.
const ui = @import("ui");
pub const theme = @import("../../../shared/ui/theme/app_theme.zig");
const Y = @import("_styles.yss.zig");
/// Files / Row (Che9A): 26 high.
pub const row_height: f32 = 26;
/// Files / Header (GW9no): 26 high.
pub const header_height: f32 = 26;
/// File list padding [4, 6, 0, 6]: rows are inset 6 on both sides.
pub const row_inset: f32 = 6;
/// Row padding [0, 10] plus the 6 inset: content starts 16 from the pane edge.
pub const row_padding: f32 = 10;
/// Inset + row padding + 20 selector column precede the name column.
pub const lead_width: f32 = row_inset + row_padding + 20;
pub const min_columns: f32 = 490;
pub const columns_fixed: f32 = 284;
pub const path_font: f32 = 11.5;
pub const ButtonStyle = ui.StyleOverride;
pub fn root(t: *const ui.ThemeTokens) ui.BoxStyle {
    return @TypeOf(Y.root).box(t);
}
/// Each side owns a file card plus an optional sibling transfer card.
/// Hidden transfer roots do not contribute a gap or reserve any height.
pub fn columnStack(t: *const ui.ThemeTokens) ui.BoxStyle {
    return @TypeOf(Y.column_stack).box(t);
}
pub fn card(t: *const ui.ThemeTokens) ui.BoxStyle {
    return @TypeOf(Y.card).box(t);
}
/// Pane Header (QGtx5): title row above the files toolbar.
pub fn paneHeader(t: *const ui.ThemeTokens) ui.BoxStyle {
    return @TypeOf(Y.pane_header).box(t);
}
pub fn toolbar(t: *const ui.ThemeTokens) ui.BoxStyle {
    return @TypeOf(Y.toolbar).box(t);
}
/// Path bar (breadcrumb + status) replaces the former 44pt footer.
pub fn footer(t: *const ui.ThemeTokens) ui.BoxStyle {
    return @TypeOf(Y.path_bar).box(t);
}
pub fn pathStatus(t: *const ui.ThemeTokens) ui.BoxStyle {
    return @TypeOf(Y.path_status).box(t);
}
pub fn line(height: f32) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = height }, .flex_shrink = 0, .direction = .row, .gap = 8, .align_items = .center, .min_width = 0 };
}
/// Pane title (QGtx5 Pane title): 12 / 500, fg-primary.
pub fn title(_: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 12, .font_weight = 500, .line_height = 16.0 / 12.0, .color = theme.current().fg_1, .wrap = .none, .text_overflow = .ellipsis };
}
/// Empty-state headline keeps the former 13 / 600 emphasis.
pub fn emptyTitle(_: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 13, .font_weight = 600, .line_height = 18.5 / 13.0, .color = theme.current().fg_1, .wrap = .none, .text_overflow = .ellipsis };
}
/// Location title (tVVKV Location title): 13 / 600, fg-primary.
pub fn location(_: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 13, .font_weight = 600, .line_height = 18.0 / 13.0, .color = theme.current().fg_1, .wrap = .none, .text_overflow = .ellipsis };
}
/// Path bar / header text (11.5, fg-secondary).
pub fn secondary(_: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 11.5, .line_height = 16.0 / 11.5, .color = theme.current().fg_2, .wrap = .none };
}
/// Header label of the sorted column (GW9no Name label): 11.5 / 600, fg-primary.
pub fn headingActive(_: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 11.5, .font_weight = 600, .line_height = 16.0 / 11.5, .color = theme.current().fg_1, .wrap = .none };
}
/// Cached directory data is a warning, independent of the file card.
pub fn staleText(t: *const ui.ThemeTokens) ui.TextStyle {
    var value = secondary(t);
    value.font_size = 10;
    value.line_height = 1.5;
    value.color = theme.current().warn_ink;
    return value;
}
pub fn staleNotice() ui.BoxStyle {
    return .{ .padding = .{ .top = 6, .bottom = 6, .left = 12, .right = 12 }, .background = theme.popupInset(), .flex_shrink = 0 };
}
/// Size / Date cells (Che9A Size text, Date text): 12, fg-secondary.
pub fn numeric(_: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 12, .line_height = 16.0 / 12.0, .color = theme.current().fg_2, .wrap = .none, .text_overflow = .ellipsis };
}
pub fn modified(t: *const ui.ThemeTokens) ui.TextStyle {
    return numeric(t);
}
pub fn subtitle(_: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 10.5, .line_height = 18.0 / 10.5, .color = theme.current().fg_2, .wrap = .none };
}
/// File name (Che9A File name): 12.5, fg-primary.
pub fn filename(_: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 12.5, .line_height = 16.0 / 12.5, .color = theme.current().fg_1, .wrap = .none, .text_overflow = .ellipsis };
}
pub fn badge(t: *const ui.ThemeTokens) ui.BoxStyle {
    return @TypeOf(Y.badge).box(t);
}
/// Badge label: 11, fg-secondary.
pub fn badgeText(_: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 11, .line_height = 14.0 / 11.0, .color = theme.current().fg_2, .wrap = .none, .text_overflow = .ellipsis };
}
/// Button / ghost / sm / icon only (W:SwTks): 24, radius 6.
pub fn iconButton(size: f32) ButtonStyle {
    return .{ .width = .{ .px = size }, .height = .{ .px = size }, .padding = .{}, .gap = 0, .flex_shrink = 0, .corner_radius = 6, .background = ui.Color.TRANSPARENT };
}
/// Location (tVVKV Location): 28 high, radius 6, padding [0, 6], gap 4.
pub fn locationButton() ButtonStyle {
    return .{ .height = .{ .px = 28 }, .width = .{ .fit = .{} }, .min_width = 0, .flex_shrink = 1, .padding = .{ .left = 6, .right = 6 }, .gap = 4, .corner_radius = 6, .direction = .row, .align_items = .center, .justify = .start, .font_size = 13, .font_weight = 600, .text_color = theme.current().fg_1, .background = ui.Color.TRANSPARENT, .overflow = .hidden };
}
/// Files toolbar search (tVVKV Search, Input/default at 168×28).
pub fn search() ui.BoxStyle {
    return .{ .width = .{ .px = 168 }, .height = .{ .px = 28 }, .flex_shrink = 1, .min_width = 72 };
}
pub fn pathField(t: *const ui.ThemeTokens) ui.BoxStyle {
    return @TypeOf(Y.path_field).box(t);
}
pub fn pathInput() ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = 24 }, .flex = 1, .min_width = 0, .padding = .{}, .border = .{ .width = 0 }, .background = ui.Color.TRANSPARENT };
}
/// Breadcrumb crumb (path bar Crumb · …): 22 high text button, 11.5.
pub fn crumb(current: bool) ButtonStyle {
    return .{ .height = .{ .px = 22 }, .padding = .{ .left = 2, .right = 2 }, .font_size = path_font, .font_weight = if (current) 500 else 400, .text_color = if (current) theme.current().fg_1 else theme.current().fg_2, .corner_radius = 4, .background = ui.Color.TRANSPARENT, .flex_shrink = 0 };
}
pub fn table(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .fill(), .flex = 1, .min_height = 0, .min_width = 0, .direction = .column, .background = ui.Color.TRANSPARENT, .border = .{ .radius = 0 }, .overflow = .hidden, .overflow_hidden = true };
}
pub fn headerClip(t: *const ui.ThemeTokens) ui.BoxStyle {
    return @TypeOf(Y.header_clip).box(t);
}
/// Row / header content: inset 6, padding [0, 10] (Che9A, list padding 6).
pub fn columns(width: f32) ui.BoxStyle {
    return .{ .width = .{ .px = @max(0, width - 2 * row_inset) }, .height = .{ .px = row_height }, .flex_shrink = 0, .direction = .row, .align_items = .center, .padding = .{ .left = row_padding, .right = 0 }, .margin = .{ .left = row_inset, .right = row_inset }, .gap = 0, .border = .{ .radius = 6 } };
}
pub fn column(width: f32) ui.BoxStyle {
    return .{ .width = .{ .px = width }, .height = .{ .px = row_height }, .flex_shrink = 0, .min_width = 0, .direction = .row, .align_items = .center, .gap = 5, .overflow = .hidden, .overflow_hidden = true };
}
/// Header cell (GW9no Name/Size/Date): label + 11pt sort chevron, gap 4.
pub fn sortButton(width: f32) ButtonStyle {
    return .{ .width = .{ .px = width }, .height = .{ .px = header_height }, .padding = .{ .left = 0, .right = 4 }, .gap = 4, .direction = .row, .align_items = .center, .justify = .start, .flex_shrink = 0, .background = ui.Color.TRANSPARENT };
}
/// Files / Row: inset 6, radius 6; selected = list-selection fill.
pub fn fileRow(width: f32, selected: bool, focused: bool) ButtonStyle {
    return .{ .width = .{ .px = @max(0, width - 2 * row_inset) }, .height = .{ .px = row_height }, .margin = .{ .left = row_inset, .right = row_inset }, .padding = .{}, .gap = 0, .flex_shrink = 0, .corner_radius = 6, .background = if (selected) theme.states().selected else if (focused) theme.states().focus else ui.Color.TRANSPARENT, .border = .{ .width = 0, .color = ui.Color.TRANSPARENT } };
}
/// File list padding top 4 (Che9A list padding [4, 6, 0, 6]).
pub fn viewport() ui.BoxStyle {
    return .{ .width = .fill(), .height = .fill(), .flex = 1, .min_height = 0, .min_width = 0, .padding = .{ .top = 4 } };
}
pub fn empty(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .position = .absolute, .width = .fill(), .height = .{ .px = 128 }, .direction = .column, .inset = .{ .left = .{ .px = 0 }, .top = .{ .px = header_height } } };
}
pub fn errorBox(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .fit = .{} }, .flex_shrink = 0, .direction = .column, .gap = 4, .padding = ui.Padding.all(8), .background = theme.current().surface_2, .border = .{ .radius = 9 }, .overflow = .hidden, .overflow_hidden = true };
}
pub fn errorText(_: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 12, .font_weight = 500, .line_height = 1.5, .color = theme.current().danger_ink, .wrap = .word };
}
pub fn icon(size: f32) ui.Style {
    return .{ .width = .{ .px = size }, .height = .{ .px = size }, .flex_shrink = 0 };
}
pub fn repaint(node: *ui.Node, previous: theme.Colors) void {
    theme.setRetainedBackground(node, remap(node.getBackground(), previous));
    // Read the painted color (new zenit: setTextColor lives in the node's StyleExt, not
    // in TextProps.color) and leave ink that the theme publication already made current.
    if (node.resolveTextProps()) |text| if (!isCurrentInk(text.color)) node.setTextColor(theme.remapUiInk(text.color, previous));
    if (node.getIcon()) |icon_| _ = node.setTint(theme.remapUiInk(icon_.tint, previous));
    if (node.getImage()) |image_| _ = node.setTint(theme.remapUiInk(image_.tint, previous));
    for (node.children.items) |child| repaint(child, previous);
}
fn isCurrentInk(color: ui.Color) bool {
    inline for (.{ "fg_1", "fg_2", "fg_3", "accent_ink", "ok_ink", "warn_ink", "danger_ink" }) |field| {
        if (ui.Color.eql(color, @field(theme.current(), field))) return true;
    }
    return false;
}
fn remap(color: ui.Color, previous: theme.Colors) ui.Color {
    // boxStyled recipes (card, toolbar, ...) already repaint on the theme publication
    // that precedes this walk; a fill that is already a current role must not be
    // remapped again (light overlay white equals a previous dark role and would turn
    // into that role's light value, e.g. an opaque black card).
    inline for (@typeInfo(theme.Colors).@"struct".field_names) |field| {
        if (ui.Color.eql(color, @field(theme.current(), field))) return color;
    }
    if (theme.remapUiSurface(color, previous)) |next| return next;
    inline for (@typeInfo(theme.Colors).@"struct".field_names) |field| {
        if (ui.Color.eql(color, @field(previous, field))) return @field(theme.current(), field);
    }
    return color;
}

/// Bridge 342:1084206: target-card drag preview, 574×74, padding8/gap4/r9.
pub fn dragPreview(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .position = .absolute, .inset = .{ .left = .{ .px = 8 }, .right = .{ .px = 8 }, .bottom = .{ .px = 40 } }, .height = .{ .px = 74 }, .flex_shrink = 0, .direction = .column, .gap = 4, .padding = ui.Padding.all(8), .background = theme.current().surface_2, .border = .{ .radius = 9 }, .hit_behavior = .pass_through };
}

/// O52ucD Drag preview: icon stack over the hint, gap 6; follows the pointer.
pub fn dragGhost() ui.BoxStyle {
    return .{ .position = .absolute, .width = .{ .fit = .{} }, .height = .{ .fit = .{} }, .direction = .column, .align_items = .start, .gap = 6, .z_index = 80, .hit_behavior = .pass_through };
}
/// Stack (60×52, free layout): back icon 40, front icon 42, count badge.
pub fn dragStack() ui.BoxStyle {
    return .{ .width = .{ .px = 60 }, .height = .{ .px = 52 }, .flex_shrink = 0, .hit_behavior = .pass_through };
}
pub fn dragIcon(size: f32, x: f32, y: f32) ui.BoxStyle {
    return .{ .position = .absolute, .inset = .{ .left = .{ .px = x }, .top = .{ .px = y } }, .width = .{ .px = size }, .height = .{ .px = size } };
}
/// Count: 20 circle, accent fill, 11 / 600 inverse ink.
pub fn dragCount() ui.BoxStyle {
    return .{ .position = .absolute, .inset = .{ .right = .{ .px = 0 }, .top = .{ .px = 0 } }, .width = .{ .px = 20 }, .height = .{ .px = 20 }, .align_items = .center, .justify = .center, .background = theme.current().action_accent, .border = .{ .radius = 10 } };
}
pub fn dragCountText(_: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 11, .font_weight = 600, .line_height = 14.0 / 11.0, .color = theme.actionForeground(theme.current().action_accent), .wrap = .none };
}
/// Drop hint (W:F1E0E Tooltip): inverse fill, radius 6, padding [6, 8], shadow 0/2/6.
pub fn dragHint() ui.BoxStyle {
    return .{ .width = .{ .fit = .{} }, .max_width = 320, .padding = .{ .top = 6, .bottom = 6, .left = 8, .right = 8 }, .background = theme.current().fg_1, .border = .{ .radius = 6 }, .shadow = .{ .blur = 6, .offset_y = 2, .color = theme.current().shadow }, .hit_behavior = .pass_through };
}
pub fn dragHintText(_: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 12, .line_height = 16.0 / 12.0, .color = theme.current().surface_1.withAlpha(255), .wrap = .none, .text_overflow = .ellipsis };
}
/// O52ucD drop-target row: accent-subtle fill (states().drop_target) with a 1px accent ring.
pub fn dropRing(active: bool) ui.Border {
    return .{ .overlay = true, .width = if (active) 1 else 0, .radius = 6, .color = if (active) theme.current().action_accent else ui.Color.TRANSPARENT };
}
