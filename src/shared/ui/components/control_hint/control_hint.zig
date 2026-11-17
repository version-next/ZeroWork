//! Contextual help for existing controls, shared by the affected panels.
const ui = @import("ui");

pub const Options = struct {
    id: []const u8,
    layout: ui.BoxStyle = .{ .flex_shrink = 0 },
    width: ?f32 = null,
    wrap: ui.TextWrap = .word,
    /// The hint applies only while this holds (e.g. its panel is open). With `enabled`, both must.
    visible: ?*ui.Signal(bool) = null,
    /// The hint applies only while this holds (a state: turning true under a resting pointer or a
    /// held focus shows it without a new hover).
    enabled: ?*ui.Signal(bool) = null,
    /// Test id of the hint's text (the native Tooltip's `text_test_id`); `id` names the panel.
    text_id: ?[]const u8 = null,
};

/// Contextual help for a control: a native `W.Tooltip` around it, in zenit's default look, shown
/// on the control's hover or keyboard focus. Its conditions (`visible`, `enabled`) are the
/// Tooltip's own `disabled` state; hiding, detaching or disabling the control closes it natively.
pub fn mount(cx: *ui.Cx, scope: *ui.Scope, control: *ui.Node, text: anytype, options: Options) !ui.widgets.TooltipResult {
    // The hint applies while every given condition holds (the Tooltip's `disabled` is its negation).
    var disabled: ui.Source(bool) = .{ .value = false };
    if (options.visible) |visible| {
        if (options.enabled) |enabled| {
            disabled = try scope.derive(bool, .{ .v = visible, .e = enabled }, struct {
                fn f(c: anytype) bool {
                    return !(c.v.get() and c.e.get());
                }
            }.f);
        } else disabled = try notOf(scope, visible);
    } else if (options.enabled) |enabled| disabled = try notOf(scope, enabled);
    const tip = try ui.widgets.Tooltip(.{ .text = text, .text_test_id = options.text_id, .position = .bottom_end, .width = options.width, .wrap = options.wrap, .font_size = 11, .disabled = disabled }).mount(scope, cx);
    tip.wrapper.setStyleInline(cx.allocator, options.layout);
    // The tooltip wrapper aligns its trigger to the start (anchor geometry);
    // a filling control must stretch across it explicitly (CSS align-self).
    var trigger_layout = options.layout;
    const fills = if (options.layout.width) |width| width == .grow else false;
    if (fills) trigger_layout.align_self = .stretch;
    tip.trigger.setStyleInline(cx.allocator, trigger_layout);
    // Controls opt out of inherited cross stretch (no_cross_stretch); a
    // filling control stretches across the trigger explicitly.
    if (fills) control.setStyleInline(cx.allocator, .{ .align_self = .stretch });
    tip.content.meta.ownership.meta.test_id = options.id;
    try tip.trigger.appendChild(cx.allocator, control);
    return tip;
}

fn notOf(scope: *ui.Scope, condition: *ui.Signal(bool)) !ui.Source(bool) {
    return scope.derive(bool, .{ .c = condition }, struct {
        fn f(c: anytype) bool {
            return !c.c.get();
        }
    }.f);
}
