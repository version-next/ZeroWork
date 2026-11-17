//! A look is resolved per state into the control's tone; transitions belong to the element's own
//! style, so a part that declares one is rejected instead of silently losing it.
const ui = @import("ui");
test {
    const look = ui.view.Look.from(ui.css(.{ .background = .accent, .transition = ui.transition("background 120ms ease-out") }));
    _ = look;
}
