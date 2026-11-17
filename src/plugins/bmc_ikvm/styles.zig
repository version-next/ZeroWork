//! Native KVM content aligned to the approved Mist workspace geometry.
//! Product palette and materials follow the existing theme registry.
const ui = @import("ui");
pub const theme = @import("../../shared/ui/theme/app_theme.zig");
const material = @import("../../shared/ui/styles/surface_material.zig");
const shell = @import("../../features/shell/view/shell_styles.zig");
// Pencil TcJSa "KVM toolbar" (uy2Fa): 40 high, padding [0,8,0,12], gap 2,
// flush on the focused view island (no floating card).
pub const toolbar_height: f32 = 40;
pub const tool_width: f32 = 76;
pub const tool_height: f32 = 28;
// Identity (108), connection state (82), five 76-point menus (icon 14 + label
// + chevron 11, padding [0,8], gap 5), gaps and outer padding.
pub const expanded_toolbar_width: f32 = 600;
// Outer padding (20), monitor/status (58), five icons (160), six gaps (12).
pub const icon_toolbar_width: f32 = 264;
// j8WXoF O1 status slot (sm Tag with the longest full label, or "AI 操作中" + sm "接管") and
// its leading gap: the toolbar folds this much earlier while a status is shown.
pub const status_reserve_width: f32 = 176;
// The video sits directly under the toolbar; the host island (radius 12,
// overflow hidden) rounds the outer corners. The 8-point black inset preserves
// every source pixel and all edge input targets in both fit and original modes.
pub const video_card_radius: f32 = 0;
pub const popup_width: f32 = 296;
pub const boot_width: f32 = 312;
pub const select_width: f32 = 180;
pub const popup_header_height: f32 = 55.5;
pub const display_header_height: f32 = 44;
pub const progress_width: f32 = 520;
pub const progress_height: f32 = 441;
pub const progress_header_height: f32 = 26;
pub const progress_padding: f32 = 20;
pub const progress_gap: f32 = 12;
pub const progress_action_height: f32 = 32;
pub const log_width: f32 = 760;
pub const popup_max_height: f32 = 730;
/// KVM menu Popovers: distance from their trigger and from the window edge (props; the menu body
/// height is fitted to the room this placement leaves).
pub const popup_offset: f32 = 8;
pub const popup_viewport_padding: f32 = 12;
// uy2Fa: toolbar padding [0,8,0,12] and gap 2. Beside the native controls (measured) the labelled
// toolbar keeps the identity (icon 15 + gap 6 + title, 108) and the icon toolbar its icon and gap (21).
pub const toolbar_gap: f32 = 2;
pub const toolbar_labelled_reserve: f32 = 20 + 108 + toolbar_gap * 2;
pub const toolbar_icon_reserve: f32 = 20 + 15 + 6 + toolbar_gap * 2;

pub fn root(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .fill(), .direction = .column, .gap = 0, .min_width = 0, .min_height = 0, .overflow_hidden = true };
}
pub fn workspaceRoot(_: *const ui.ThemeTokens) ui.BoxStyle {
    // TcJSa: the toolbar and the video share one island; no gap between them.
    return .{ .width = .fill(), .height = .fill(), .min_width = 0, .min_height = 0, .direction = .column, .gap = 0, .padding = .{}, .background = ui.Color.TRANSPARENT };
}
pub fn toolbar(_: *const ui.ThemeTokens) ui.BoxStyle {
    // uy2Fa: height 40, padding [0,8,0,12], gap 2, alignItems center, no fill.
    return .{ .width = .fill(), .height = .{ .px = toolbar_height }, .min_width = 0, .direction = .row, .align_items = .center, .padding = .{ .left = 12, .right = 8 }, .gap = 2, .flex_shrink = 0, .background = ui.Color.TRANSPARENT };
}
pub fn connectionIdentity(_: *const ui.ThemeTokens) ui.BoxStyle {
    // Icon 15 + gap 6 + title, content sized; the status follows it and a
    // spacer keeps the menus right-aligned. Shrinks (title ellipsis) first.
    // Narrower than zenit's own controls need: the box clips rather than paint under them.
    return .{ .width = .{ .fit = .{} }, .min_width = 0, .flex_shrink = 1, .direction = .row, .align_items = .center, .gap = 6, .overflow_hidden = true };
}
pub const connection_icon_size: f32 = 15;
pub fn connectionIcon() ui.Style {
    return .{ .width = .{ .px = connection_icon_size }, .height = .{ .px = connection_icon_size }, .flex_shrink = 0 };
}
pub fn connectionTitle(_: *const ui.ThemeTokens) ui.TextStyle {
    // uy2Fa title: 13 / 600, fg_1.
    return .{ .font_size = 13, .font_weight = 600, .line_height = 1.5, .color = theme.current().fg_1, .selectable = false, .text_overflow = .ellipsis };
}
/// KVM popups sit on remote video, whose brightness is unrelated to the app theme:
/// they are mounted with a fixed dark colour scheme (zenit Popover `color_scheme`), and
/// their own paint reads that scheme's palette (bugfix-2, #64 key-menu contrast).
pub const popup_scheme: ui.ColorScheme = .dark;
pub fn popupPalette() theme.Colors {
    return theme.schemeColors(popup_scheme);
}
/// Secondary text: inside the fixed-scheme popups it is the scheme's supporting ink, which
/// strengthens toward fg_1 as the material clears over arbitrary video; elsewhere fg_2.
fn secondaryInk(t: *const ui.ThemeTokens) ui.Color {
    return if (theme.tokenScheme(t) != null) t.tokens.color.zw_fg_supporting else theme.current().fg_2;
}
pub fn videoWorkspace(_: *const ui.ThemeTokens) ui.BoxStyle {
    // workspaceRoot owns the 16-point gap below the floating toolbar.
    return .{ .width = .fill(), .height = .fill(), .min_width = 0, .min_height = 0, .padding = .{}, .gap = 0 };
}
pub fn videoCard(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .fill(), .min_width = 0, .min_height = 0, .padding = ui.Padding.all(8), .gap = 0, .background = ui.Color.BLACK, .border = .{ .width = 0, .radius = video_card_radius }, .overflow_hidden = true, .clip_shape = .{ .rounded_rect = video_card_radius } };
}
/// The picture viewport: this view's box around the native ScrollArea (input target, positions
/// the connection card).
pub fn video(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .fill(), .min_width = 0, .min_height = 0, .background = ui.Color.BLACK, .padding = ui.Padding.ZERO, .gap = 0, .border = .{ .width = 0, .radius = 0 }, .overflow_hidden = true, .clip_shape = .{ .rounded_rect = 0 }, .hit_behavior = .@"opaque" };
}
/// The scrolled extent inside the picture ScrollArea.
pub fn canvas(width: f32, height: f32) ui.BoxStyle {
    return .{ .width = .{ .px = width }, .height = .{ .px = height }, .flex_shrink = 0 };
}
/// This view's box around a native toolbar control: content sized, never squeezed.
pub fn toolSlot(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .{ .fit = .{} }, .height = .{ .fit = .{} }, .flex_shrink = 0 };
}
/// A popover's content: fixed header over the scroll viewport.
pub fn popupPanel(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .fit = .{} }, .direction = .column, .gap = 0, .min_width = 0 };
}
/// The box that gives a native ScrollArea its height (the area fills it).
pub fn scrollViewport(height: f32) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = height }, .min_width = 0, .flex_shrink = 0 };
}
pub fn menuViewport(height: f32) ui.BoxStyle {
    return scrollViewport(height);
}
pub fn image() ui.Style {
    return .{ .position = .absolute, .width = .{ .px = 1 }, .height = .{ .px = 1 }, .flex_shrink = 0, .border = .{ .width = 0, .radius = 0 } };
}
pub fn popupBody(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .fit = .{} }, .direction = .column, .gap = 12, .padding = ui.Padding.all(12), .min_width = 0, .flex_shrink = 0 };
}
pub fn popupHead(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = popup_header_height }, .direction = .row, .align_items = .center, .gap = 8, .padding = ui.Padding.all(12), .flex_shrink = 0, .min_width = 0 };
}
pub fn title(t: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 13, .font_weight = 700, .line_height = 1.5, .color = theme.paletteFor(t).fg_1, .selectable = false };
}
pub fn body(t: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 12, .font_weight = 400, .line_height = 1.5, .color = theme.paletteFor(t).fg_1, .selectable = false };
}
pub fn value(t: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 11, .font_weight = 700, .line_height = 1.5, .color = theme.paletteFor(t).fg_1, .selectable = false, .text_overflow = .ellipsis };
}
pub fn hint(t: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 11, .font_weight = 400, .line_height = 1.5, .color = secondaryInk(t), .wrap = .word, .selectable = false };
}
pub fn well(t: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .direction = .row, .align_items = .center, .justify = .space_between, .padding = .{ .top = 9, .bottom = 9, .left = 10, .right = 10 }, .gap = 8, .background = material.fill(theme.paletteFor(t).well, .solid), .border = .{ .radius = 8 }, .min_width = 0, .flex_shrink = 0 };
}
/// A step's diagnostic text block on the connection progress surface, which lies on the pane
/// island (first material layer).
pub fn diagnosticFill() ui.Color {
    return material.fill(theme.current().well, .canvas);
}
/// Wells inside the connection log's native Modal: an opaque panel, so an opaque well.
pub fn logWellFill() ui.Color {
    return material.fill(theme.current().well, .solid);
}
pub fn logFooterFill() ui.Color {
    return material.fill(theme.current().surface_2, .solid);
}
pub fn field(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = 32 }, .direction = .row, .align_items = .center, .justify = .space_between, .gap = 8, .min_width = 0, .flex_shrink = 0 };
}
pub fn actions(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .direction = .row, .justify = .end, .align_items = .center, .gap = 8, .flex_shrink = 0 };
}
pub fn keyRow(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .direction = .row, .gap = 6, .flex_shrink = 0 };
}
pub fn waiting(_: *const ui.ThemeTokens) ui.BoxStyle {
    return progressCard();
}
pub fn waitingTitle(_: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 18, .font_weight = 500, .line_height = 1.4, .color = ui.arb.hex(0xf4f4f5), .text_align = .center, .wrap = .word };
}
pub fn waitingHint(_: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 12, .line_height = 1.5, .color = ui.arb.hex(0xa4a4ad), .text_align = .center, .wrap = .word };
}
/// Connection progress: 520px card, 20px
/// padding, 12px gap; the header and actions stay outside its body scroller.
pub fn progressCard() ui.BoxStyle {
    const appearance = theme.currentName();
    // Keep the outer shadow on the layout owner so the renderer can paint it
    // beyond the card bounds.
    return .{ .position = .absolute, .width = .{ .px = progress_width }, .height = .{ .px = progress_height }, .max_width = progress_width, .direction = .column, .align_items = .stretch, .gap = 0, .padding = ui.Padding.ZERO, .min_width = 0, .min_height = 0, .background = ui.Color.TRANSPARENT, .border = .{ .width = 0, .radius = 12 }, .shadow = .{ .offset_y = 16, .blur = 48, .color = ui.Color.BLACK.withAlpha(switch (appearance) {
        .dark => 71,
        .light => 36,
        .sauber => 41,
    }) }, .overflow_hidden = true, .hit_behavior = .@"opaque", .flex_shrink = 0 };
}
pub fn progressSurface(_: *const ui.ThemeTokens) ui.BoxStyle {
    // This card can cover arbitrary video pixels, so its text needs a stable
    // theme surface independent of the global wallpaper transparency.
    return .{ .width = .fill(), .height = .fill(), .direction = .column, .align_items = .stretch, .gap = progress_gap, .padding = ui.Padding.all(progress_padding), .min_width = 0, .min_height = 0, .background = theme.current().overlay.withAlpha(255), .border = .{ .width = 0, .radius = 12 } };
}
pub fn progressSecondary() ui.Color {
    return theme.current().fg_2;
}
pub fn progressCurrentFill() ui.Color {
    return theme.current().accent_ink.withAlpha(if (theme.currentName() == .dark) 26 else 20);
}
pub fn progressHeader(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = progress_header_height }, .direction = .column, .gap = 6, .min_width = 0, .flex_shrink = 0 };
}
pub fn progressTitle(_: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 18, .font_weight = 500, .line_height = 26.0 / 18.0, .color = theme.current().fg_1, .selectable = false, .text_overflow = .ellipsis };
}
pub fn progressTiming(_: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 11, .line_height = 1.5, .color = progressSecondary(), .use_monospace_font = true, .text_align = .end, .selectable = false };
}
pub fn progressTimingLabel(_: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 11, .line_height = 1.5, .color = progressSecondary(), .selectable = false };
}
pub fn progressDetail(_: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 12, .line_height = 1.5, .color = progressSecondary(), .wrap = .word, .selectable = false };
}
pub fn progressNotice(_: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 11, .line_height = 18.0 / 11.0, .color = progressSecondary(), .selectable = false, .text_overflow = .ellipsis };
}
/// The progress body's content column inside the native ScrollArea.
pub fn progressList(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .fit = .{} }, .direction = .column, .gap = 12, .min_width = 0, .flex_shrink = 0 };
}
/// A progress step row: zenit's native Pressable (an unstyled pressable), laid out as the row.
pub fn progressSteps(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .fit = .{} }, .direction = .column, .gap = 8, .min_width = 0, .flex_shrink = 0 };
}
pub fn progressStepBackdrop(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .fit = .{} }, .min_height = 34, .direction = .row, .gap = 0, .padding = ui.Padding.ZERO, .min_width = 0, .flex_shrink = 0, .background = ui.Color.TRANSPARENT, .border = .{ .width = 0, .radius = 8 } };
}
pub fn progressDiagnostic(_: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 11, .line_height = 1.7, .color = theme.current().fg_1, .wrap = .word, .selectable = false, .use_monospace_font = true };
}
pub fn progressText(_: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 12, .line_height = 1.5, .color = theme.current().fg_1, .wrap = .word, .selectable = false };
}
pub fn progressState(_: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 11, .line_height = 18.0 / 11.0, .color = progressSecondary(), .text_align = .end, .selectable = false };
}
pub fn progressRoute(_: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 11, .line_height = 1.7, .color = theme.current().fg_1, .wrap = .word, .use_monospace_font = true, .selectable = false };
}
pub fn progressRouteLabel(_: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 11, .line_height = 1.5, .color = progressSecondary(), .selectable = false };
}
pub fn progressRouteBox(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .fit = .{} }, .direction = .column, .gap = 4, .padding = ui.Padding.all(10), .background = theme.current().well.withAlpha(255), .border = .{ .width = 0, .radius = 8 }, .min_width = 0, .flex_shrink = 0 };
}
pub fn progressActions(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .fit = .{} }, .direction = .row, .justify = .end, .align_items = .center, .gap = 8, .min_width = 0, .flex_shrink = 0 };
}
pub fn logText(_: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 11, .line_height = 1.7, .color = theme.current().fg_1, .wrap = .word, .selectable = false, .use_monospace_font = true };
}
/// The log dialog's content column (the Modal body is edge to edge).
pub fn logContent(compact: bool) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .fit = .{} }, .direction = .column, .gap = 0, .padding = .{ .top = 8, .left = if (compact) 18 else 24, .right = if (compact) 18 else 24, .bottom = logContentBottom(compact) }, .min_width = 0, .min_height = 0, .flex_shrink = 0 };
}
pub fn logContentBottom(compact: bool) f32 {
    return if (compact) 12 else 20;
}
/// The log list's viewport: a well that gives the native ScrollArea its height.
pub fn logViewport(height: f32) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = height }, .min_width = 0, .background = logWellFill(), .border = .{ .width = 0, .radius = 9 }, .overflow_hidden = true, .flex_shrink = 0 };
}
pub fn logFooter(compact: bool) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .fit = .{} }, .direction = .row, .justify = .end, .align_items = .center, .padding = if (compact) .{ .top = 10, .bottom = 10, .left = 18, .right = 18 } else .{ .top = 14, .bottom = 14, .left = 24, .right = 24 }, .background = logFooterFill(), .min_width = 0, .flex_shrink = 0 };
}
pub fn orderText(_: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 11, .line_height = 2.0, .color = theme.current().fg_1, .wrap = .word, .selectable = false, .use_monospace_font = true };
}
pub fn orderRow() ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .fit = .{} }, .min_width = 0, .flex_shrink = 0 };
}
// Display panel: 296-point panel, 16-point content inset.
pub fn displayBody(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .fit = .{} }, .direction = .column, .gap = 0, .padding = .{}, .min_width = 0, .flex_shrink = 0 };
}
pub fn displayHead(t: *const ui.ThemeTokens) ui.BoxStyle {
    var s = popupHead(t);
    s.height = .{ .px = display_header_height };
    s.padding = .{ .left = 16, .right = 12 };
    return s;
}
pub fn displayTitle(t: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 14, .font_weight = 600, .color = theme.paletteFor(t).fg_1, .selectable = false };
}
pub fn displayControls(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .fit = .{} }, .direction = .column, .gap = 8, .padding = .{ .top = 4, .left = 16, .right = 16, .bottom = 16 }, .min_width = 0, .flex_shrink = 0 };
}
/// The box around the native segmented scale control.
pub fn displayScale() ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .fit = .{} }, .min_width = 0, .flex_shrink = 0 };
}
pub fn displayPerformance(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .fit = .{} }, .direction = .column, .gap = 0, .padding = .{ .left = 16, .right = 16, .bottom = 14 }, .min_width = 0, .flex_shrink = 0 };
}
pub fn displaySwitchRow(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .fit = .{} }, .direction = .row, .align_items = .center, .margin = .{ .top = 12 }, .flex_shrink = 0 };
}
pub fn displayStats(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .fit = .{} }, .direction = .column, .gap = 4, .margin = .{ .top = 8 }, .min_width = 0, .flex_shrink = 0 };
}
pub fn displayStatRow(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = 20 }, .direction = .row, .justify = .space_between, .align_items = .center, .gap = 12, .min_width = 0, .flex_shrink = 0 };
}
pub fn displayStatLabel(t: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 13, .line_height = 20.0 / 13.0, .color = secondaryInk(t), .selectable = false };
}
pub fn displayStatValue(t: *const ui.ThemeTokens) ui.TextStyle {
    var s = displayStatLabel(t);
    s.color = theme.paletteFor(t).fg_1;
    s.text_align = .end;
    return s;
}
pub fn displayFooter(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .fit = .{} }, .direction = .row, .gap = 8, .padding = .{ .top = 12, .left = 16, .right = 16, .bottom = 16 }, .min_width = 0, .flex_shrink = 0 };
}

// Video-local contrast is stable across shell themes; never intercept input.
