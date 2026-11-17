// GENERATED FILE, do not edit: generated from styles.yss; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! Modal styles: dialog panel, title bar, close button, body. Panel view in modal.yix, popover /
//! focus trap / animation in mod.zig.
const ui = @import("../../ui.zig");

/// Dialog panel: design radius.dialog, 1px border and shadow.lg.
pub const dialog = ui.paramStyle(struct { width: f32, max_height: f32, height: ?f32 = null, background: ?ui.Color = null, pub const declared = &[_][]const u8{ "width", "height", "background", "direction", "corner_radius", "border_overlay", "border_width", "border_color", "shadow", }; pub fn resolve(args: @This(), t: *const ui.theme.Values) ui.BoxStyle { return ui.boxFrom(.{ .width = args.width, .height = dialogHeight(args.height, args.max_height), .background = ui.orElse(args.background, ui.tokenRef(.color, "bg-primary")), .direction = .column, .corner_radius = ui.tokenRef(.radius, "dialog"), .border_overlay = true, .border_width = 1, .border_color = ui.tokenRef(.color, "border"), .shadow = ui.tokenRef(.shadow, "lg"), }, t); } });

/// Title bar: title + close button space-between
pub const header = ui.previewCss("src/ui/components/modal/styles.yss", "header", @embedFile("styles.yss"), .{ .direction = .row, .justify = .space_between, .align_items = .center, .gap = ui.tokenRef(.space, "space300"), .padding = .{ .top = 16, .right = 12, .bottom = 0, .left = 20 }, .width = .{ .grow = .{} }, .background = ui.Color.TRANSPARENT, .border_overlay = true, .border_bottom_width = 1, .border_color = ui.tokenRef(.color, "border"), });
pub fn title(t: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .color = t.tokens.color.fg_primary, .font_size = t.tokens.font_size.xl, .font_weight = 600, .line_height = 1.25, .wrap = .word_break };
}
/// The title bar's room for the close button (the button itself is laid out over it, see closePlace in modal.yix).
pub const close_slot = ui.previewCss("src/ui/components/modal/styles.yss", "close_slot", @embedFile("styles.yss"), .{ .width = 28, .height = 28, .flex_shrink = 0, });
/// Close button (a native ghost icon Button): 28x28.
pub const close_button = ui.previewCss("src/ui/components/modal/styles.yss", "close_button", @embedFile("styles.yss"), .{ .width = 28, .height = 28, .min_height = 0, .padding = 0, });
/// Body slot: default padding [8, 20, 20, 20] and gap space400, or the caller's (`body_padding` /
/// `body_gap`). It takes what the title bar leaves and never more (`min-height: 0`): content taller
/// than a fixed / capped dialog stays inside the body's box (a ScrollArea in the body scrolls)
/// instead of stretching the body past the panel's bottom edge.
pub const body = ui.paramStyle(struct { padding: ?ui.Padding = null, gap: ?f32 = null, pub const declared = &[_][]const u8{ "direction", "width", "height", "min_height", "padding", "gap", }; pub fn resolve(args: @This(), t: *const ui.theme.Values) ui.BoxStyle { return ui.boxFrom(.{ .direction = .column, .width = .{ .grow = .{} }, .height = .{ .grow = .{} }, .min_height = 0, .padding = args.padding orelse ui.Padding{ .top = 8, .right = 20, .bottom = 20, .left = 20 }, .gap = args.gap orelse t.tokens.space.space400, }, t); } });


/// Fixed height, else fit up to the cap.
pub fn dialogHeight(height: ?f32, max_height: f32) ui.Sizing {
    return if (height) |h| .{ .px = h } else .{ .fit = .{ .max = max_height } };
}

pub fn headerCorners(t: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .corner_radii = .{ .each = .{ t.tokens.radius.dialog, t.tokens.radius.dialog, 0, 0 } } };
}

//# yix-map styles.yss
