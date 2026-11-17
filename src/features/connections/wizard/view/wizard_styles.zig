//! Local Figma Bridge: 339:1019169, 235:370377, 235:371322,
//! 299:587764, 235:378249, 319:702700, 321:890421,
//! SFTP 342:1210942 / 342:1207116 / 319:704376.
const ui = @import("ui");
pub const theme = @import("../../../../shared/ui/theme/app_theme.zig");
// Island B v3 新建连接 Stack 1/1a/2/3 (hb6dT, LCs7p, kiUlJ, zp7WE): 720 window.
pub const width: f32 = 720;
pub const max_height: f32 = 710;
pub const ButtonStyle = ui.StyleOverride;
pub const chrome_height: f32 = 168;
/// Step row height (Island B v3 quiet stepper).
pub const stepper_height: f32 = 40;
/// Window chrome around the pane: title bar 44 + Stage bottom 6 + island
/// padding 4×2; the pane hairline is drawn inside (hb6dT: 413 = 44 + 4 + 355 + 4 + 6).
pub const header_height: f32 = 44;
pub const frame_height: f32 = 6 + 8;
/// Pane Body padding [20,28,0,28]; Footer 56 with a top hairline.
pub const body_inset: f32 = 28;
pub const body_top: f32 = 20;
pub const footer_height: f32 = 56;

fn zw() @FieldType(@FieldType(ui.ThemeTokens, "tokens"), "color") {
    return theme.widgetTheme(theme.currentName()).tokens.color;
}
/// Design `$W:zenit.color.bg_active` dividers (Advanced row, Footer, summaries).
pub fn divider() ui.Color {
    return zw().bg_active;
}
/// Design `#80808A` muted ink (hints, summary values, chevrons).
pub fn muted() ui.Color {
    return theme.states().muted_ink;
}

// Window: radius 18, fill zw.island.ground, 1px zenit border.
/// Modal dialog geometry only: the panel surface (background, border, radius,
/// shadow) is zenit Modal's default.
pub fn panel(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .{ .px = width }, .height = .{ .px = max_height }, .max_height = max_height, .padding = .{}, .gap = 0, .direction = .column, .overflow_hidden = true, .flex_shrink = 0 };
}
// Stage padding [0,6,6,6] → View island (zw.island.focus, r12, p4) → Pane
// (zw.island.focus, r8, inner accent_border hairline, clip).
pub fn stage(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = shrink, .flex = 1, .min_height = 0, .direction = .column, .padding = .{ .left = 6, .right = 6, .bottom = 6 }, .gap = 0 };
}
pub fn island(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = shrink, .flex = 1, .min_height = 0, .direction = .column, .padding = ui.Padding.all(4), .gap = 0, .background = zw().zw_island_focus, .border = .{ .radius = 12 } };
}
pub fn pane(_: *const ui.ThemeTokens) ui.BoxStyle {
    const c = zw();
    return .{ .width = .fill(), .height = shrink, .flex = 1, .min_height = 0, .direction = .column, .gap = 0, .background = c.zw_island_focus, .border = .{ .overlay = true, .radius = 8, .width = 1, .color = c.accent_border }, .overflow_hidden = true };
}
pub fn editorSlot(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = shrink, .min_height = 0, .flex = 1, .flex_shrink = 1, .direction = .column, .gap = 0 };
}
pub fn stack(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .fit = .{} }, .direction = .column, .gap = 6, .flex_shrink = 0 };
}
pub fn formSection(_: *const ui.ThemeTokens) ui.BoxStyle {
    var style = stack(undefined);
    style.gap = 14;
    return style;
}
// Measured HTML identity fields start at y230.5 (1280×720), with
// 55.5px field rows separated by 12px.
pub fn identitySection(tokens: *const ui.ThemeTokens) ui.BoxStyle {
    var style = formSection(tokens);
    style.gap = 17.5;
    return style;
}
pub fn identityFields(tokens: *const ui.ThemeTokens) ui.BoxStyle {
    var style = formSection(tokens);
    style.gap = 12;
    return style;
}
pub fn card(_: *const ui.ThemeTokens) ui.BoxStyle {
    var style = stack(undefined);
    style.padding = ui.Padding.all(12);
    style.background = theme.popupAction();
    style.border = .{ .radius = 9 };
    return style;
}
// Title bar 44, padding [0,14], gap 12 (hb6dT zZR14).
pub fn header() ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = header_height }, .padding = .{ .left = 14, .right = 14 }, .direction = .row, .align_items = .center, .gap = 12, .flex_shrink = 0 };
}
pub fn modalBody() ui.BoxStyle {
    return .{ .width = .fill(), .height = shrink, .flex = 1, .min_height = 0, .padding = ui.Padding.all(0), .gap = 0, .direction = .column };
}
// Pane Body: padding [20,28,0,28]; sections gap 22 (gDsxf).
pub fn body() ui.BoxStyle {
    return .{ .width = .fill(), .height = shrink, .flex = 1, .min_height = 0, .direction = .column, .padding = .{ .left = body_inset, .right = body_inset, .top = body_top }, .gap = 22 };
}
pub fn row(h: f32) ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = h }, .direction = .row, .align_items = .center, .gap = 6, .flex_shrink = 0 };
}
// Footer 56 inside the pane's 28 inset, top hairline bg_active, gap 8 (dtfCz).
pub fn footer() ui.BoxStyle {
    var style = row(footer_height);
    style.gap = 8;
    style.padding = .{};
    style.margin = .{ .left = body_inset, .right = body_inset };
    style.background = ui.Color.TRANSPARENT;
    style.border_top_width = 1;
    style.border_overlay = true;
    style.border_top_color = divider();
    return style;
}
pub fn footerHint() ui.TextStyle {
    var style = text(12, 400, false);
    style.color = muted();
    return style;
}
/// 稿 2 ③：标题栏与底栏固定，只有中间内容滚动。高度是 grow 且显式最小 0——`.fill()` 的自动最小值等于内容高度，
/// 会把整个窗口根撑高、把底栏挤出窗口（860 × 480 / 600 × 420 下看不到“上一步 / 下一步”）。
pub fn scroll() ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .grow = .{ .min = 0 } }, .flex = 1, .min_height = 0 };
}
/// 底栏上方 28 的滚动提示：原生 ScrollArea 的底边 scroll edge（下方还有内容时出现，滚到底消失）。
pub const scroll_hint_height: f32 = 28;
/// Column chain from the window root down to the scroll: grow with an explicit 0 minimum, so a
/// short window shrinks the scroll instead of growing the root past the window edge.
pub const shrink: ui.Sizing = .{ .grow = .{ .min = 0 } };
// Field (LCs7p Rv9op): label 15 + gap 6 + control 32 = 53.
pub const field_height: f32 = 53;
pub const label_height: f32 = 15;
pub const control_height: f32 = 32;
/// Input text 13 / line 18 (Inter 13, lineHeight 1.4); approximate advance.
pub const input_font: f32 = 13;
pub const input_line: f32 = 18;
// Input / default (W:rTb0Z): 32 high, radius 6, padding [0,12], 13px text.
// The field frame (hairline border, focus ring, invalid border) is zenit's
// ControlShell; an inline border here sits above its state layer and hid it.
pub fn input() ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = control_height }, .padding = .{ .left = 12, .right = 12 }, .background = zw().bg_primary, .corner_radius = 6, .font_size = 13 };
}
pub fn button(w: f32, h: f32, primary: bool) ui.BoxStyle {
    // Button / primary (W:vp4Ld): solid accent, r6. Button / secondary
    // (W:jHqcg): bg_primary fill with the zenit border hairline, r6.
    const c = zw();
    return .{ .width = .{ .px = w }, .height = .{ .px = h }, .padding = .{}, .direction = .row, .align_items = .center, .justify = .center, .gap = 6, .background = if (primary) theme.current().action_accent else c.bg_primary, .border = .{ .overlay = true, .radius = 6, .width = if (primary) 0 else 1, .color = if (primary) ui.Color.TRANSPARENT else c.border }, .flex_shrink = 0 };
}
/// Footer actions: Button / md 32 high (W:vp4Ld 108×32).
pub const action_height: f32 = 32;
pub fn disclosure() ui.BoxStyle {
    var style = row(15);
    style.padding = .{};
    style.justify = .start;
    style.gap = 0;
    style.background = ui.Color.TRANSPARENT;
    return style;
}
// Advanced (hb6dT b7EPH): 39 = 12 + 15 + 12; top hairline bg_active.
pub fn disclosureRow() ui.BoxStyle {
    var style = row(39);
    style.padding = .{ .top = 12, .right = 4, .bottom = 12 };
    style.border_top_width = 1;
    style.border_overlay = true;
    style.border_top_color = divider();
    return style;
}
pub fn disclosureTitle() ui.TextStyle {
    var style = text(12.5, 500, false);
    style.line_height = 15.0 / 12.5;
    style.text_overflow = .clip;
    return style;
}
pub fn stepTitle(selected: bool) ui.TextStyle {
    var style = text(12, 400, false);
    style.line_height = 18.0 / 12.0;
    style.color = if (selected) theme.current().accent_ink else theme.current().fg_2;
    return style;
}
pub fn stepNumber() ui.TextStyle {
    var style = text(12, 400, false);
    style.line_height = 1.5;
    style.text_align = .center;
    return style;
}
pub fn icon(size: f32) ui.Style {
    return .{ .width = .{ .px = size }, .height = .{ .px = size }, .flex_shrink = 0 };
}
pub fn iconBox(size: f32) ui.BoxStyle {
    return .{ .width = .{ .px = size }, .height = .{ .px = size }, .flex_shrink = 0 };
}
// 358:1508903 (direct) / 358:1507656 (routed, unavailable).
pub fn number(selected: bool) ui.BoxStyle {
    // Hop Index (kiUlJ MnSH3): 22 circle on bg_active; the current step keeps accent.
    return .{ .width = .{ .px = 22 }, .height = .{ .px = 22 }, .align_items = .center, .justify = .center, .background = if (selected) theme.current().action_accent else divider(), .border = .{ .radius = 11 }, .flex_shrink = 0 };
}
pub fn routeHop() ui.BoxStyle {
    // Hop row (kiUlJ uc0uH): 52 high, padding [0,10], gap 12, zw.island.rest, r8.
    return .{ .width = .fill(), .height = .{ .px = 52 }, .direction = .row, .align_items = .center, .padding = .{ .left = 10, .right = 10 }, .gap = 12, .background = zw().zw_island_rest, .border = .{ .radius = 8 }, .border_bottom_width = 0, .border_bottom_color = ui.Color.TRANSPARENT, .flex_shrink = 0 };
}
pub fn routeNode(_: bool) ui.BoxStyle {
    return .{ .width = .{ .px = 146 }, .height = .{ .px = 76 }, .padding = ui.Padding.all(10), .direction = .column, .gap = 2, .background = zw().zw_island_rest, .border = .{ .radius = 9 }, .flex_shrink = 0 };
}
pub fn testNodeText(kind: enum { name, address, status }) ui.TextStyle {
    var style = text(switch (kind) {
        .name => 11,
        .address => 9,
        .status => 9.5,
    }, if (kind == .name) 500 else 400, false);
    style.line_height = (if (kind == .address) @as(f32, 14) else 16) / style.font_size;
    return style;
}
// 358:1328935 / 1328950 / 1328988: 28+4+80+4+26 = 142.
pub fn testLogs() ui.BoxStyle {
    // Log well (ybb2B CxmC6 pattern): zw.island.rest, r8.
    return .{ .width = .fill(), .height = .{ .fit = .{} }, .direction = .column, .gap = 4, .background = zw().zw_island_rest, .border = .{ .radius = 8, .width = 0 }, .flex_shrink = 0 };
}
pub fn testLogText(column: usize) ui.TextStyle {
    var style = text(if (column == 3) 10.5 else 9.5, 400, false);
    style.line_height = 16 / style.font_size;
    return style;
}
pub fn text(size: f32, weight: u16, mono: bool) ui.TextStyle {
    const line: f32 = if (size >= 13) 20 else if (size >= 12) 18 else if (size < 10) 14 else 16;
    return .{ .font_size = size, .font_weight = weight, .line_height = line / size, .color = if (weight >= 500) theme.current().fg_1 else theme.current().fg_2, .selectable = false, .text_overflow = .ellipsis, .use_monospace_font = mono };
}
// Field label (LCs7p GXUTT): 12 regular fg_secondary, 15 high.
pub fn label(_: *const ui.ThemeTokens) ui.TextStyle {
    var style = text(12, 400, false);
    style.line_height = 15.0 / 12.0;
    return style;
}
// Section titles (kiUlJ QTf37 / zp7WE aOc2y): 12.5 semibold fg_primary.
pub fn title(_: *const ui.ThemeTokens) ui.TextStyle {
    var style = text(12.5, 600, false);
    style.line_height = 15.0 / 12.5;
    return style;
}
// Hints (hb6dT cJ6Pv): 11.5 muted.
pub fn hint(_: *const ui.ThemeTokens) ui.TextStyle {
    var style = text(11.5, 400, false);
    style.line_height = 15.0 / 11.5;
    style.color = muted();
    return style;
}
pub fn paragraph(_: *const ui.ThemeTokens) ui.TextStyle {
    var style = text(11.5, 400, false);
    style.wrap = .word;
    style.text_overflow = .clip;
    return style;
}
pub fn logs(_: *const ui.ThemeTokens) ui.TextStyle {
    var style = paragraph(undefined);
    style.use_monospace_font = true;
    style.selectable = true;
    return style;
}
// Button label (W:FDTyf / W:I3EcsU): 13 medium; secondary ink is fg_primary.
pub fn action(primary: bool) ui.TextStyle {
    var style = text(13, 500, false);
    style.line_height = 16.0 / 13.0;
    style.text_overflow = .clip;
    style.color = if (primary) theme.widgetTheme(theme.currentName()).tokens.color.button_primary_fg else theme.current().fg_1;
    return style;
}

pub fn readonlyValue(_: *const ui.ThemeTokens) ui.TextStyle {
    var style = text(12, 400, false);
    style.line_height = 1.5;
    style.color = theme.current().fg_1;
    return style;
}

pub fn topFade(_: *const ui.ThemeTokens) ui.BoxStyle {
    const c = theme.current();
    return .{ .width = .fill(), .height = .{ .px = 72 }, .position = .absolute, .inset = .{ .left = .{ .px = 0 }, .top = .{ .px = 0 } }, .gradient = .{ .from = c.well_border.withAlpha(48), .to = c.overlay.withAlpha(0) }, .border = .{ .radius = 14 }, .hit_behavior = .pass_through };
}
pub fn grip(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .position = .absolute, .inset = .{ .top = .{ .px = 7 }, .left = .{ .percent = 50 } }, .width = .{ .px = 32 }, .height = .{ .px = 3 }, .margin = .{ .left = -16 }, .background = theme.current().fg_2, .border = .{ .radius = 1.5 }, .hit_behavior = .pass_through };
}

pub fn summaryName() ui.TextStyle {
    var value = text(12, 500, false);
    value.line_height = 16.0 / 12.0;
    return value;
}
pub fn summaryField(w: f32) ui.BoxStyle {
    return .{ .width = .{ .px = w }, .height = .{ .px = 16 }, .min_width = 0, .flex_shrink = 1 };
}
pub fn summaryOptions(_: *const ui.ThemeTokens) ui.TextStyle {
    var value = text(11, 400, false);
    value.wrap = .word;
    value.text_overflow = .clip;
    return value;
}


pub fn fieldRow() ui.BoxStyle {
    var value = row(52);
    value.height = .{ .fit = .{} };
    value.align_items = .start;
    value.gap = 16;
    return value;
}

// Frozen V3 connection review: identity header, two-column values and plain route.
pub fn reviewStack(_: *const ui.ThemeTokens) ui.BoxStyle {
    var value = stack(undefined);
    value.gap = 16;
    value.padding = .{ .left = 4, .right = 4 };
    return value;
}
pub fn reviewIdentity() ui.BoxStyle {
    var value = row(66);
    value.gap = 12;
    value.padding = .{ .top = 12, .right = 16, .bottom = 12, .left = 16 };
    value.background = zw().zw_island_rest;
    value.border = .{ .radius = 10 };
    return value;
}
pub fn reviewFields(_: *const ui.ThemeTokens) ui.BoxStyle {
    var value = stack(undefined);
    value.gap = 12;
    value.padding = .{ .left = 2, .right = 2 };
    return value;
}
pub fn reviewFieldRow() ui.BoxStyle {
    var value = row(39);
    value.gap = 18;
    value.align_items = .start;
    return value;
}
pub fn reviewField() ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = 39 }, .min_width = 0, .flex = 1, .direction = .column, .gap = 4, .flex_shrink = 0 };
}
pub fn reviewRoute() ui.BoxStyle {
    var value = stack(undefined);
    value.gap = 10;
    value.padding = .{ .top = 12, .right = 16, .bottom = 16, .left = 16 };
    value.background = zw().zw_island_rest;
    value.border = .{ .radius = 10 };
    return value;
}

// Frozen V3 details: plain disclosure, 18px preceding margin and 12px body gap.
pub fn advancedSection(_: *const ui.ThemeTokens) ui.BoxStyle {
    var value = stack(undefined);
    value.gap = 12;
    // Form → Advanced spacing is 22 (gDsxf gap): 14 section gap + 8.
    value.margin = .{ .top = 8 };
    return value;
}


pub fn copyHeader() ui.BoxStyle {
    var value = header();
    value.height = .{ .px = 52 };
    value.padding = .{ .left = 20, .right = 20, .top = 14, .bottom = 14 };
    value.gap = 6;
    return value;
}
pub fn copyFooter() ui.BoxStyle {
    var value = footer();
    value.height = .{ .px = 62 };
    value.padding = .{ .left = 24, .right = 24, .top = 14, .bottom = 14 };
    // The copy dialog keeps its own action bar rather than the pane footer.
    value.margin = .{};
    value.border_top_width = 0;
    value.background = theme.popupAction();
    return value;
}

pub fn commandField(_: *const ui.ThemeTokens) ui.BoxStyle {
    var value = stack(undefined);
    value.gap = 6;
    return value;
}

// Frozen HTML connectionTest: compact header and per-hop stage list. Rich
// diagnostics stay in the existing disclosure beneath this summary.
pub fn testResult(_: *const ui.ThemeTokens) ui.BoxStyle {
    // Route / 连接测试 block (zp7WE RlQle): padding [12,16,16,16], zw.island.rest, r10.
    return .{ .width = .fill(), .height = .{ .fit = .{} }, .direction = .column, .padding = .{ .top = 12, .right = 16, .bottom = 16, .left = 16 }, .gap = 0, .background = zw().zw_island_rest, .border = .{ .radius = 10 }, .flex_shrink = 0 };
}
pub fn testStage() ui.BoxStyle {
    return .{ .width = .fill(), .height = .{ .px = 54.6 }, .direction = .row, .align_items = .start, .padding = .{ .top = 8, .bottom = 8 }, .gap = 10, .flex_shrink = 0 };
}
pub fn testStageTitle() ui.TextStyle {
    var value = text(11, 500, false);
    value.line_height = 1.5;
    return value;
}
pub fn testStageDetail() ui.TextStyle {
    var value = text(11, 400, false);
    value.line_height = 1.6;
    return value;
}

// Read-only facts drawn as an Input value (LCs7p KxqrP "15 秒"): 13 fg_primary.
pub fn inputValue(_: *const ui.ThemeTokens) ui.TextStyle {
    var style = text(input_font, 400, false);
    style.line_height = input_line / input_font;
    style.color = theme.current().fg_1;
    return style;
}

pub fn windowTitle() ui.TextStyle {
    var style = text(13, 600, false);
    style.line_height = 16.0 / 13.0;
    style.color = theme.current().fg_1;
    return style;
}
// Native window (hb6dT): the whole window is the ground; no extra frame.
pub fn windowRoot() ui.BoxStyle {
    return .{ .width = .fill(), .height = shrink, .direction = .column, .gap = 0, .padding = .{}, .background = ground() };
}
// Title bar 44: traffic lights 14..66 + gap 12 → content starts at 78 (Nav).
pub fn windowHeader() ui.BoxStyle {
    var style = header();
    style.padding = .{ .left = 78, .right = 14 };
    return style;
}

/// `zw.island.ground` as an opaque fill. The shell's token is transparent
/// (the main window paints the ground behind its root); the wizard window and
/// the modal frame draw the ground themselves.
pub fn ground() ui.Color {
    return theme.baseColors().app;
}


// Stack 3 chain (zp7WE by4KM): hop dot 9 (origin hollow), name 12.5/500,
// meta 11 fg_secondary indented 16, hairline links between hops.
pub fn chainDot(origin: bool) ui.BoxStyle {
    return .{ .width = .{ .px = 9 }, .height = .{ .px = 9 }, .background = if (origin) ui.Color.TRANSPARENT else theme.current().accent, .border = .{ .overlay = true, .radius = 4.5, .width = if (origin) 1.5 else 0, .color = muted() }, .flex_shrink = 0 };
}
pub fn chainName() ui.TextStyle {
    var style = text(12.5, 500, false);
    style.line_height = 15.0 / 12.5;
    return style;
}
pub fn chainMeta() ui.TextStyle {
    var style = text(11, 400, false);
    style.line_height = 15.0 / 11.0;
    return style;
}
pub fn chainLink(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .{ .px = 28 }, .height = .{ .px = 1 }, .background = muted(), .flex_shrink = 0 };
}

// Stack 3 summary (zp7WE QgEGN): "back to" rows — key 84 12.5/500, value
// 12 fg_secondary, chevron 14; rows 37 with hairlines between them.
pub fn backKey() ui.TextStyle {
    var style = text(12.5, 500, false);
    style.line_height = 15.0 / 12.5;
    style.text_overflow = .clip;
    return style;
}
pub fn backValue() ui.TextStyle {
    var style = text(12, 400, false);
    style.line_height = 15.0 / 12.0;
    return style;
}
