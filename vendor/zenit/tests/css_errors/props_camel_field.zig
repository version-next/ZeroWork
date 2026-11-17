//! Yix <Row fieldId="x" /> arrives as .field_id; a hand-written Props field spelled fieldId never
//! matches. Say which name to use.
const ui = @import("ui");
const Props = struct { fieldId: []const u8 = "" };
fn mount(_: Props, _: *ui.Scope, _: *ui.Cx) anyerror!*ui.Node {
    unreachable;
}
test {
    _ = ui.view.component(mount, .{ .field_id = "x" });
}
