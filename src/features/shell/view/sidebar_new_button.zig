//! Centered new-connection action shared by the empty and populated sidebar.
const std = @import("std");
const ui = @import("ui");
const S = @import("sidebar_styles.zig");
const T = S.theme;

pub fn mount(cx: *ui.Cx, scope: *ui.Scope, slot: *ui.Node, id: []const u8, empty: bool, disabled: *ui.Signal(bool), on_click: ui.Handler(void)) !void {
    const base = try scope.createSignal(ui.BoxStyle, if (empty) S.emptyFooter() else S.footer());
    const interaction = try scope.createSignal(?ui.BoxStyle, .{});
    const tint = try scope.createSignal(?ui.Color, T.current().fg_2);
    const button = try ui.widgets.Button(.{ .label = "新建主机", .icon_asset = ui.icons.plus, .icon_size = @as(f32, 14), .icon_tint = tint, .variant = .ghost, .a11y_label = "新建主机", .base_style = base, .hover_style = interaction, .pressed_style = interaction, .disabled = disabled, .on_click = on_click }).mount(scope, cx);
    // Focus is zenit's native focus ring; the effect below paints hover / pressed only.
    button.meta.ownership.meta.test_id = id;
    try button.applyTransition(cx.allocator, &(comptime ui.transition("background 160ms ease")));
    try slot.appendChild(cx.allocator, button);
    try scope.createEffect(.{ .base = base, .interaction = interaction, .tint = tint, .empty = empty, .disabled = disabled, .hovered = try ui.hooks.useHover(scope, button), .pressed = try ui.hooks.usePressed(scope, cx, button), .publication = try cx.themeSignal() }, struct {
        fn paint(ctx: anytype) void {
            _ = ctx.publication.get();
            const unavailable = ctx.disabled.get();
            const hot = !unavailable and ctx.hovered.get();
            const down = !unavailable and ctx.pressed.get() and ctx.hovered.get();
            var style = if (ctx.empty) S.emptyFooter() else S.footer();
            style.background = if (down)
                sidebarFill(T.states().pressed, T.material_transparency_base.well)
            else if (hot)
                sidebarFill(T.current().hover, T.material_transparency_base.hover)
            else
                ui.Color.TRANSPARENT;
            style.text_color = T.current().fg_2;
            ctx.base.set(style);
            ctx.interaction.set(.{ .background = style.background });
            ctx.tint.set(style.text_color);
        }
    }.paint);
}

/// Match the approved solid-color preview at zero transparency while retaining
/// the theme role's alpha and its response to the global material setting.
fn sidebarFill(target: ui.Color, base_transparency: f32) ui.Color {
    const background = T.baseColors().surface_1;
    const alpha = @round(255 * (1 - base_transparency)) / 255;
    var fill = target;
    inline for (.{ "r", "g", "b" }) |channel| {
        const bg: f32 = @floatFromInt(@field(background, channel));
        const color: f32 = @floatFromInt(@field(target, channel));
        @field(fill, channel) = @intFromFloat(@round(std.math.clamp(bg + (color - bg) / alpha, 0, 255)));
    }
    return fill;
}
