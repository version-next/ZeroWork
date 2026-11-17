const ui = @import("ui");
const theme = @import("../../../shared/ui/theme/app_theme.zig");

/// Island B v3 tabs (Pencil `ZW4 / Tab`): the strip is 33 high and sits on
/// the island's top edge. Inactive surfaces are 30 high (3pt above the island);
/// the active surface is 33 high, island-colored, and joins the island.
pub const height: f32 = 33;
pub const surface_height: f32 = 30;
/// View bar `Tabs` (hvc0K) lays tab cells edge to edge (no gap); each cell
/// insets its surface by `outer_inset` (ZW4 / Tab padding [0, 2, 3, 2]), so two
/// surfaces sit 4 apart and every cell edge is a hit target for its own tab.
pub const gap: f32 = 0;
pub const outer_inset: f32 = 2;
/// Surface width inside a laid-out tab cell.
pub fn surfaceWidth(cell_width: f32) f32 {
    return @max(0, cell_width - 2 * outer_inset);
}
/// New tab (nCMeb): zenit's native ghost sm icon-only button (24 in the design),
/// 4 after the last tab (tab_strip.yss `NewSlot`).
pub const new_tab_size: f32 = 24;
pub const title_font: f32 = 12;
pub const title_weight: u16 = 400;
pub const active_title_weight: u16 = 600;
/// The tab’s corners follow the island radius after the cell's lateral inset.
pub fn attachedRadius(island_radius: f32) f32 {
    return @max(0, island_radius - outer_inset);
}
pub const attention_duration_ms: f64 = 480;
pub fn attentionOffset(elapsed_ms: f64) f32 {
    const phase = @max(0, elapsed_ms);
    if (phase >= attention_duration_ms) return 0;
    const amplitude: f64 = if (phase < 240) 3 else 1.5;
    return @floatCast(-amplitude * @sin(@mod(phase, 240) / 240 * @import("std").math.pi));
}
pub const rename_width: f32 = 320;
pub const rename_height: f32 = 118;
pub const field_height: f32 = 32;

pub const title_left: f32 = 10 + 14 + 6;
/// Title box width inside a tab surface of `width` (native xs close button 20 + right padding 2).
pub fn titleWidth(width: f32) f32 {
    return @max(0, width - title_left - 20 - 2);
}
pub fn field() ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = field_height }, .background = theme.popupInset(), .border = .{ .width = 0, .color = ui.Color.TRANSPARENT, .radius = 7 } };
}

pub fn tuneInput(input: *ui.widgets.input.InputResult) void {
    input.state.font_size = 12;
    input.state.line_height = 18;
    input.state.char_width = 7.2;
    input.state.dirty = true;
    if (input.state.text_display_node) |node| if (node.getText()) |text| {
        var next = text;
        next.font_size = 12;
        next.line_height = 1.5;
        node.setText(next);
    };
}

// Figma Local Bridge 236:547754: anchored 320x172 editor, header36,
// content at12,40, input at0,21, footer at0,89.
pub fn renameDialog(has_error: bool) ui.BoxStyle {
    return .{ .width = .{ .px = rename_width }, .height = .{ .px = rename_height + @as(f32, if (has_error) 24 else 0) }, .padding = ui.Padding.all(0) };
}
pub fn renameBody() ui.BoxStyle {
    return .{ .padding = ui.Padding.all(0), .width = .fill(), .height = .fill(), .direction = .column, .gap = 0 };
}
pub fn renameContent() ui.BoxStyle {
    return .{ .width = .fill(), .height = .fill(), .direction = .column, .gap = 8, .padding = .{ .left = 12, .right = 12, .top = 4, .bottom = 12 } };
}
pub fn renameActions() ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = 30 }, .direction = .row, .justify = .end, .gap = 8, .flex_shrink = 0 };
}
pub fn renameHeader() ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = 32 }, .direction = .row, .align_items = .center, .gap = 6, .padding = .{ .left = 12, .right = 12 }, .flex_shrink = 0 };
}
pub fn renameTitle() ui.TextStyle {
    return .{ .font_size = 13, .font_weight = 700, .line_height = 20.0 / 13.0, .color = theme.current().fg_1 };
}
pub fn renameIcon() ui.Style {
    return .{ .width = .{ .px = 18 }, .height = .{ .px = 18 }, .flex_shrink = 0 };
}
pub fn renameClose() ui.BoxStyle {
    return .{ .width = .{ .px = 22 }, .height = .{ .px = 22 }, .padding = ui.Padding.all(0), .border = .{ .radius = 8 }, .flex_shrink = 0 };
}
pub fn renameField() ui.BoxStyle {
    var value = field();
    value.border = .{ .width = 0, .color = ui.Color.TRANSPARENT, .radius = 8 };
    return value;
}
pub fn renameLabel() ui.TextStyle {
    return .{ .font_size = 11, .font_weight = 500, .color = theme.current().fg_2, .line_height = 16.0 / 11.0 };
}
pub fn renameHint() ui.TextStyle {
    return .{ .font_size = 11, .color = theme.current().fg_2, .line_height = 16.0 / 11.0, .selectable = false };
}
pub fn renameButton(width: f32) ui.BoxStyle {
    return .{ .width = .{ .px = width }, .height = .{ .px = 30 }, .border = .{ .radius = 8 } };
}
pub fn repaintRename(root: *ui.Node, previous: theme.Colors) void {
    theme.setRetainedBackground(root, remapRename(root.getBackground(), previous));
    if (root.getText()) |value| root.setTextColor(theme.remapUiInk(value.color, previous));
    if (root.getIcon()) |value| _ = root.setTint(theme.remapUiInk(value.tint, previous));
    if (root.getImage()) |value| _ = root.setTint(theme.remapUiInk(value.tint, previous));
    for (root.children.items) |child| repaintRename(child, previous);
}
fn remapRename(value: ui.Color, previous: theme.Colors) ui.Color {
    const next = theme.current();
    inline for (@typeInfo(theme.Colors).@"struct".field_names) |role| if (ui.Color.eql(value, @field(previous, role))) return @field(next, role);
    return value;
}

/// 稿 3 group tab: gap between the (truncated) group name and its member count.
pub const group_count_gap: f32 = 4;
