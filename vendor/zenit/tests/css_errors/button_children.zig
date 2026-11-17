//! Yix <W.Button>…elements…</W.Button>: Button mounts a single node and has no children slot
//! (used to fail only at mount with error.ViewComponentHasNoSlot).
const ui = @import("ui");
test {
    const v = ui.view;
    _ = v.with(ui.widgets.Button(.{ .label = "Save" }), .{v.text(.{}, "extra")});
}
