//! Yix parts={.{ .inner = .{ .test_id = count(vm) } }}: the lifted test id must carry a string.
const ui = @import("ui");
const Panel = struct {
    const Result = struct {
        outer: *ui.Node,
        inner: *ui.Node,
        pub fn viewParts(self: Result) ui.ViewParts {
            return .{ .root = self.outer, .slot = self.inner };
        }
    };
    pub fn mount(_: Panel, _: *ui.Scope, _: *ui.Cx) !Result {
        unreachable;
    }
};
test {
    const count: ui.Source(i32) = .{ .value = 1 };
    const element = ui.view.attrs(.{ .parts = .{ .inner = .{ .test_id = count } } }, Panel{});
    _ = ui.view.render(undefined, undefined, element) catch {};
}
