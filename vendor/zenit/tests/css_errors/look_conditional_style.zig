//! A ConditionalStyle value is too large to carry in a Look; the message names the alternatives.
const ui = @import("ui");
test {
    const cs: ui.ConditionalStyle = .{ .hover = .{ .background = ui.Color.WHITE } };
    _ = ui.widgets.Button(.{ .label = "x", .look = cs });
}
