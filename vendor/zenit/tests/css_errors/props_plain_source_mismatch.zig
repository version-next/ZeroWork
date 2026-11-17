//! Yix <W.Input width={label} /> with a string parameter: a plain-value prop of a builder widget
//! reads a source once when the widget is built, but only a source of the prop's own type.
const ui = @import("ui");
test {
    const label: ui.Source([]const u8) = .{ .value = "wide" };
    _ = ui.widgets.Input(.{ .width = label });
}
