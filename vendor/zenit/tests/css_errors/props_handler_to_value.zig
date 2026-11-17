//! Yix <Row onPick={|v| …} /> into a hand-written component whose Props field is not a Handler.
const ui = @import("ui");
const Props = struct { on_pick: bool = false };
fn mount(_: Props, _: *ui.Scope, _: *ui.Cx) anyerror!*ui.Node {
    unreachable;
}
test {
    const H = ui.on.AnyHandler(struct {}, struct {
        fn f(_: anytype) void {}
    }.f);
    const h: H = undefined;
    _ = ui.view.component(mount, .{ .on_pick = h });
}
