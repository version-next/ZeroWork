//! Figma Local Bridge: 274:913661, 499:657547, 300:593434.
const std = @import("std");
const ui = @import("ui");
pub fn dropMarker() ui.BoxStyle {
    return .{ .position = .absolute, .height = .{ .px = 2 }, .background = theme.current().accent, .hit_behavior = .pass_through };
}
pub const theme = @import("../../../shared/ui/theme/app_theme.zig");
pub const expanded_width: f32 = @import("../model/sidebar_model.zig").default_width;
pub const collapsed_width: f32 = 48;
/// Island B v3 environment row (Pencil `ZW4 / Project Row`): 28 high, radius 6.
pub const host_height: f32 = 28;
pub const group_height: f32 = 24; // Island B v3 "Sections heading"
pub const tail_width: f32 = 36;
pub const action_size: f32 = 24;
pub const host_icon_size: f32 = 14;
pub const group_member_indent: f32 = 12;

/// Saved KVM consoles keep a blue identity in every theme family.
pub fn kvmIconInk() ui.Color {
    return ui.Color.hex(if (theme.currentName() == .dark) 0x88b4ff else 0x2d5ca8);
}

/// Island B v3 sidebar (Pencil `JrTg7`): flush with the window ground, the
/// native traffic lights in its header. Structure in shell/styles.yss.
const Shell = @import("shell/_styles.yss.zig");
pub fn panel(t: *const ui.ThemeTokens) ui.BoxStyle {
    var style = @TypeOf(Shell.sidebar).box(t);
    style.width = .{ .px = expanded_width };
    return style;
}
pub fn full() ui.BoxStyle {
    return @TypeOf(Shell.sidebar_full).box(&ui.theme.light);
}
pub fn header() ui.BoxStyle {
    return @TypeOf(Shell.sidebar_header).box(&ui.theme.light);
}
pub fn searchRow() ui.BoxStyle {
    return @TypeOf(Shell.sidebar_search).box(&ui.theme.light);
}
pub fn viewport() ui.BoxStyle {
    return .{ .width = .fill(), .height = .fill(), .flex = 1, .min_height = 0 };
}
pub fn list() ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .fit = .{} }, .direction = .column, .gap = 15, .min_width = 0 };
}

/// Main workspace Sidebar 233:335283: each asset group is one inset surface.
pub fn groupCard() ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .fit = .{} }, .direction = .column, .gap = 0, .padding = .{}, .background = ui.Color.TRANSPARENT, .border = .{ .radius = 0 }, .flex_shrink = 0, .min_width = 0 };
}
pub fn members() ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .fit = .{} }, .direction = .column, .padding = .{ .left = group_member_indent, .top = 6 }, .gap = 1, .min_width = 0 };
}
pub fn groupGuideColor() ui.Color {
    return ui.Color.lerp(theme.current().surface_1, theme.current().well_border, 0.85);
}
pub fn groupGuide() ui.BoxStyle {
    return .{ .position = .absolute, .inset = .{ .left = .{ .px = 5.5 }, .top = .{ .px = 9 }, .bottom = .{ .px = host_height / 2 } }, .width = .{ .px = 1 }, .height = .fill(), .background = groupGuideColor(), .border = .{ .radius = 0.5 }, .hit_behavior = .pass_through, .hit_roles = .{ .pointer = false, .scroll = false, .inspect = false } };
}
pub fn footer() ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = 34 }, .padding = .{ .left = 10, .right = 10 }, .direction = .row, .align_items = .center, .justify = .center, .gap = 6, .background = ui.Color.TRANSPARENT, .border = .{ .radius = 8 }, .font_size = 12, .font_weight = 500, .text_color = theme.current().fg_2, .flex_shrink = 0 };
}
pub fn footerSlot(empty: bool) ui.BoxStyle {
    // Current Figma: workspace 233:334511 ends 8px above the panel;
    // empty state 392:1835642 ends 2px above it. Both wells are 34px high.
    return .{ .width = .fill(), .height = .{ .px = 34 }, .margin = if (empty) .{ .left = 8, .right = 8, .bottom = 2 } else .{}, .direction = .row, .flex_shrink = 0 };
}
pub fn footerFrame() ui.Style {
    return .{ .position = .absolute, .width = .{ .px = 208 }, .height = .{ .px = 34 } };
}
pub fn emptyFooter() ui.BoxStyle {
    var value = footer();
    value.border.?.radius = 9;
    return value;
}
pub fn headerAction() ui.BoxStyle {
    var value = action(24);
    value.border = .{ .radius = 8 };
    return value;
}
pub fn railAction(size: f32) ui.BoxStyle {
    var value = action(size);
    value.border = .{ .radius = 8 };
    return value;
}
pub fn action(size: f32) ui.BoxStyle {
    return .{ .width = .{ .px = size }, .height = .{ .px = size }, .padding = .{}, .align_items = .center, .justify = .center, .background = ui.Color.TRANSPARENT, .border = .{ .radius = 7 }, .flex_shrink = 0 };
}
pub fn hostSelection() ui.Color {
    const colors = theme.current();
    var selection = colors.selection;
    const transparency = theme.materialParameters().transparency / 100;
    const start_alpha: f32 = @floatFromInt(selection.a);
    const material_alpha: f32 = @floatFromInt(theme.states().selected.a);
    selection.a = @intFromFloat(@round(start_alpha + (material_alpha - start_alpha) * transparency));
    const opacity = @as(f32, @floatFromInt(selection.a)) / 255;
    const composite = ui.Color.lerp(theme.baseColors().surface_1.withAlpha(255), selection.withAlpha(255), opacity);
    if (@import("../../../shared/ui/theme/theme_states.zig").contrast(composite, colors.fg_1) < @import("../../../shared/ui/theme/theme_states.zig").text_min) return theme.states().selected;
    return selection;
}
pub fn host(selected: bool, hot: bool) ui.BoxStyle {
    const selection = hostSelection();
    _ = selection;
    // Active row = the list's active surface (zw.list.active), hover/press tints.
    return .{ .width = .fill(), .height = .{ .px = host_height }, .direction = .row, .align_items = .center, .gap = 8, .padding = .{ .left = 8, .right = 8 }, .background = if (selected) theme.current().surface_1 else if (hot) theme.states().hover else ui.Color.TRANSPARENT, .border = .{ .radius = 6 }, .flex_shrink = 0, .min_width = 0 };
}
/// Pencil F0U1j project row states: normal RI5FN (transparent) · hover gjAf6
/// (#18181B0A = states.hover) · press NQngd (#18181B12 = states.pressed) ·
/// active rQNox (zw.list.active = surface_1). 28 high, radius 6, padding [0, 8], gap 8.
pub const RowState = enum { normal, hover, press, active };
pub fn hostState(state: RowState) ui.BoxStyle {
    var style = host(state == .active, state == .hover);
    if (state == .press) style.background = theme.states().pressed;
    return style;
}
pub fn content() ui.BoxStyle {
    return .{ .position = .absolute, .inset = .{ .left = .{ .px = 0 }, .top = .{ .px = 0 } }, .width = .fill(), .height = .fill(), .direction = .row, .align_items = .center, .gap = 8, .padding = .{ .left = 8, .right = 4 }, .min_width = 0 };
}
pub fn titleViewport() ui.BoxStyle {
    return .{ .height = .{ .px = 18 }, .width = .{ .grow = .{ .min = 0 } }, .flex = 1, .flex_shrink = 1, .min_width = 0, .overflow = .hidden, .align_items = .center };
}
pub fn tail() ui.BoxStyle {
    return .{ .width = .{ .px = tail_width }, .height = .{ .px = action_size }, .direction = .row, .align_items = .center, .justify = .end, .gap = 4, .flex_shrink = 0 };
}
pub fn route() ui.BoxStyle {
    return .{ .width = .{ .px = 24 }, .height = .{ .px = 24 }, .flex_shrink = 0 };
}
pub fn routeIcon() ui.BoxStyle {
    return .{ .position = .absolute, .inset = .{ .left = .{ .px = 0 }, .top = .{ .px = 4 } }, .width = .{ .px = 16 }, .height = .{ .px = 16 } };
}
pub fn routeBadge() ui.BoxStyle {
    return .{ .position = .absolute, .inset = .{ .right = .{ .px = 0 }, .top = .{ .px = 0 } }, .width = .{ .px = 12 }, .height = .{ .px = 12 }, .direction = .row, .align_items = .center, .justify = .center, .flex_shrink = 0 };
}
pub fn routeBadgeText() ui.TextStyle {
    return .{ .font_size = 8.5, .font_weight = 600, .line_height = 1, .color = theme.current().fg_2, .text_align = .center, .use_monospace_font = true, .selectable = false };
}
pub fn icon(size: f32) ui.Style {
    return .{ .width = .{ .px = size }, .height = .{ .px = size }, .flex_shrink = 0 };
}
pub fn text(size: f32, weight: u16, secondary: bool) ui.TextStyle {
    return .{ .font_size = size, .font_weight = weight, .line_height = if (size == 13) 20.0 / 13.0 else if (size == 12) 1.5 else 16.0 / size, .color = if (secondary) theme.current().fg_2 else theme.current().fg_1, .selectable = false, .text_overflow = .ellipsis };
}
pub fn status(online: bool) ui.BoxStyle {
    return .{ .width = .{ .px = 6 }, .height = .{ .px = 6 }, .background = if (online) theme.current().ok else theme.current().fg_3, .border = .{ .radius = 3 }, .flex_shrink = 0 };
}
pub fn group() ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = group_height }, .padding = .{ .left = 0, .right = 8 }, .direction = .row, .align_items = .center, .gap = 6, .background = ui.Color.TRANSPARENT, .border = .{ .radius = 7 }, .flex_shrink = 0 };
}
pub fn groupContent() ui.BoxStyle {
    var value = content();
    // Trailing edge matches the host row content (content(): right 4) so the
    // group count stays centered over the rows' route column.
    value.padding = .{ .left = 0, .right = 4 };
    value.gap = 6;
    return value;
}
pub fn badge() ui.BoxStyle {
    // Center the count on the host route icon, 16px inside the content edge.
    return .{ .width = .{ .px = 32 }, .height = .{ .px = 14 }, .direction = .row, .align_items = .center, .justify = .center, .background = ui.Color.TRANSPARENT, .padding = .{}, .border = .{ .radius = 0 }, .flex_shrink = 0 };
}
pub fn badgeText() ui.TextStyle {
    return .{ .font_size = 10, .font_weight = 500, .line_height = 1.4, .color = theme.current().fg_3, .text_align = .center, .selectable = false, .text_overflow = .clip };
}
pub fn badgeLabel() ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = 14 }, .flex_shrink = 0 };
}
pub fn menu(height: f32) ui.BoxStyle {
    return .{ .width = .{ .px = 258 }, .height = .{ .px = height }, .direction = .column, .gap = 1, .padding = ui.Padding.all(14), .background = theme.current().overlay, .border = .{ .radius = 11 }, .shadow = .{ .offset_y = 4, .blur = 10, .color = theme.current().shadow.withAlpha(if (theme.currentName() == .dark) 51 else if (theme.currentName() == .light) 18 else 20) } };
}
pub fn menuRow() ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = 30 }, .direction = .row, .align_items = .center, .justify = .start, .gap = 6, .padding = ui.Padding.all(6), .background = ui.Color.TRANSPARENT, .border = .{ .radius = 7 }, .flex_shrink = 0 };
}
pub fn hint() ui.BoxStyle {
    return .{ .padding = .{ .top = 8, .bottom = 8, .left = 10, .right = 10 }, .direction = .column, .gap = 4, .background = theme.current().overlay, .border = .{ .radius = 8 } };
}
pub fn rail(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .{ .px = collapsed_width }, .height = .fill(), .direction = .column, .align_items = .center, .gap = 10, .padding = .{ .top = 12, .bottom = 8 }, .background = theme.current().surface_1, .border = .{ .radius = 11 }, .flex_shrink = 0 };
}
pub fn collectionEntry() ui.BoxStyle {
    var value = action(32);
    value.background = theme.current().accent;
    value.border = .{ .radius = 8 };
    return value;
}
pub fn detail() ui.BoxStyle {
    return .{ .width = .{ .px = 344 }, .height = .{ .px = 128 }, .min_height = 128, .direction = .column, .padding = .{ .top = 10, .bottom = 14, .left = 14, .right = 14 }, .gap = 0, .background = theme.current().overlay, .border = .{ .radius = 14 }, .shadow = .{ .offset_y = 4, .blur = 10, .color = theme.current().shadow.withAlpha(if (theme.currentName() == .dark) 51 else if (theme.currentName() == .light) 18 else 20) } };
}
pub fn repaint(node: *ui.Node, old: theme.Colors) void {
    // Button owns reactive styles, including the in-flight background color.
    // An imperative repaint becomes an inline override and can pin an
    // interpolated old-theme color above its base_style signal forever.
    if (node.meta.ownership.meta.component_name) |name| if (std.mem.eql(u8, name, "Button")) return;
    theme.setRetainedBackground(node, remap(node.getBackground(), old));
    node.setBorderColor(remap(node.style.border.color, old));
    if (node.getText()) |value| node.setTextColor(theme.remapUiInk(value.color, old));
    if (node.getIcon()) |value| _ = node.setTint(theme.remapUiInk(value.tint, old));
    if (node.getImage()) |value| _ = node.setTint(theme.remapUiInk(value.tint, old));
    for (node.children.items) |child| repaint(child, old);
}
fn remap(value: ui.Color, old: theme.Colors) ui.Color {
    if (theme.remapUiSurface(value, old)) |next| return next;
    const current = theme.current();
    inline for (@typeInfo(theme.Colors).@"struct".field_names) |field| if (ui.Color.eql(value, @field(old, field))) return @field(current, field);
    return value;
}

pub fn railHost(selected: bool) ui.BoxStyle {
    var value = railAction(32);
    if (selected) {
        // Figma 231 selected rail: Dark #6164ec, Light/Sauber accent.
        // The selected surface is a light tint; status remains the icon tint.
        // Only the complete default Dark palette has the prototype's
        // #6164ec exception; custom palettes retain their own accent hue.
        value.background = (if (std.meta.eql(theme.baseColors(), theme.colors(.dark))) ui.Color.hex(0x6164ec) else theme.current().accent).withAlpha(64);
    }
    return value;
}
pub fn railDetail() ui.BoxStyle {
    return .{ .width = .{ .px = 320 }, .height = .{ .fit = .{} }, .direction = .column, .padding = ui.Padding.all(14), .gap = 8, .background = theme.current().overlay, .border = .{ .radius = 11 }, .flex_shrink = 0 };
}
pub fn railDetailButton(width: f32) ui.BoxStyle {
    return .{ .width = .{ .px = width }, .height = .{ .px = 30 }, .padding = ui.Padding.all(0), .font_size = 12, .font_weight = 500, .border = .{ .radius = 8 }, .flex_shrink = 0 };
}

/// Pencil KBJoz / D8dPB "Window chrome" while the sidebar is hidden: padding
/// [0, 10, 6, 14]; the native traffic lights (52) keep their place and the
/// sidebar toggle (ghost sm icon 24, radius 6) follows 6pt later (the view bar
/// reserves 14 + 52 + 6 = 72 on the left, shell_styles.syncWorkspaceChrome),
/// so it lands exactly where the expanded sidebar header shows it.
pub const restore_size: f32 = 24;
pub fn restoreChrome() ui.BoxStyle {
    return .{ .width = .{ .px = restore_size }, .height = .{ .px = restore_size }, .padding = ui.Padding.ZERO, .margin = .{ .right = 10, .bottom = 6 }, .direction = .row, .align_items = .center, .justify = .center, .flex_shrink = 0, .background = ui.Color.TRANSPARENT, .border = .{ .radius = 6 }, .shadow = .{ .blur = 0, .offset_y = 0, .color = ui.Color.TRANSPARENT } };
}
pub fn restoreButton() ui.BoxStyle {
    var value = action(restore_size);
    value.border = .{ .radius = 6 };
    return value;
}
