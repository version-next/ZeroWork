//! Yix <Row count={n} /> into a hand-written component whose Props field is a plain i32: the
//! template passes a reactive source; reject it by field name instead of an obscure @as error.
const ui = @import("ui");
const Props = struct { count: i32 = 0 };
fn mount(_: Props, _: *ui.Scope, _: *ui.Cx) anyerror!*ui.Node {
    unreachable;
}
test {
    const src: ui.Source(i32) = .{ .value = 1 };
    _ = ui.view.component(mount, .{ .count = src });
}
