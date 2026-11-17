//! Yix <W.ScrollArea scrollY={label} /> with a string: the offset is a Model(f32); reject it at
//! the prop instead of accepting a value it cannot scroll to.
const ui = @import("ui");
test {
    const label: ui.Source([]const u8) = .{ .value = "top" };
    _ = ui.widgets.ScrollArea(.{ .scroll_y = label });
}
