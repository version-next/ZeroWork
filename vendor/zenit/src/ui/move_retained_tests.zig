//! Cx.moveChildRetained: a live subtree changes place inside the window as one operation.
//! What belongs to the nodes stays (focus, identity); what belongs to the old geometry ends.
const std = @import("std");
const testing = std.testing;
const core = @import("core.zig");
const reactive = @import("reactive.zig");
const theme = @import("theme.zig");
const v = @import("view.zig");
const Node = core.Node;
const Cx = core.Cx;
const Scope = reactive.Scope;

const Spy = struct {
    blurs: usize = 0,
    focuses: usize = 0,
    fn blur(self: *Spy) void {
        self.blurs += 1;
    }
    fn focus(self: *Spy) void {
        self.focuses += 1;
    }
};

const Env = struct {
    cx: *Cx,
    scope: *Scope,
    root: *Node,
    spy: *Spy,

    fn init() !Env {
        const cx = try Cx.init(testing.allocator, testing.io);
        cx.tokens = &theme.light;
        const scope = try Scope.init(testing.allocator, null, cx.owner);
        const spy = try scope.createState(Spy, .{});
        const root = try v.render(scope, cx, v.col(.{}, .{
            v.col(.{ .test_id = "home" }, .{
                v.col(.{ .test_id = "surface" }, .{
                    v.box(.{ .test_id = "field", .focusable = true, .on_blur = cx.on(Spy, spy, Spy.blur), .on_focus = cx.on(Spy, spy, Spy.focus) }, .{}),
                }),
            }),
            v.col(.{ .test_id = "away" }, .{v.box(.{ .test_id = "first" }, .{})}),
            v.box(.{ .test_id = "outside", .focusable = true }, .{}),
        }));
        cx.root = root;
        cx.content_root = root;
        return .{ .cx = cx, .scope = scope, .root = root, .spy = spy };
    }

    fn deinit(e: *Env) void {
        e.scope.dispose();
        e.cx.root = null;
        e.cx.content_root = null;
        e.cx.freeNode(e.root);
        e.cx.deinit();
    }

    fn node(e: *Env, id: []const u8) *Node {
        return find(e.root, id).?;
    }
};

fn find(n: *Node, id: []const u8) ?*Node {
    if (n.meta.ownership.meta.test_id) |t| if (std.mem.eql(u8, t, id)) return n;
    for (n.children.items) |c| if (find(c, id)) |r| return r;
    return null;
}

test "moveChildRetained: focus inside the moved subtree stays, without a blur / focus pair, and identities stay current" {
    var e = try Env.init();
    defer e.deinit();
    const surface = e.node("surface");
    const field = e.node("field");
    e.cx.setFocus(field);
    try testing.expectEqual(@as(usize, 1), e.spy.focuses);
    const surface_id: core.NodeHandle = .{ .id = surface.id, .generation = try e.cx.node_registry.trackGeneration(surface) };
    const field_id: core.NodeHandle = .{ .id = field.id, .generation = try e.cx.node_registry.trackGeneration(field) };

    try e.cx.moveChildRetained(surface, e.node("away"), null);
    try testing.expect(surface.parent == e.node("away"));
    try testing.expectEqual(@as(usize, 0), e.node("home").children.items.len);
    try testing.expect(e.cx.focus_manager.getFocused() == field);
    try testing.expectEqual(@as(usize, 0), e.spy.blurs);
    try testing.expectEqual(@as(usize, 1), e.spy.focuses);
    try testing.expect(e.cx.node_registry.isCurrentIdentity(surface_id, surface));
    try testing.expect(e.cx.node_registry.isCurrentIdentity(field_id, field));

    // `before`: placed ahead of an existing child; and back again, still the same focus.
    try e.cx.moveChildRetained(surface, e.node("home"), null);
    try e.cx.moveChildRetained(surface, e.node("away"), e.node("first"));
    try testing.expect(e.node("away").children.items[0] == surface);
    try testing.expect(e.cx.focus_manager.getFocused() == field);
    try testing.expectEqual(@as(usize, 0), e.spy.blurs);
}

test "moveChildRetained: the contrast — detach retained then append loses focus and retires identities" {
    var e = try Env.init();
    defer e.deinit();
    const surface = e.node("surface");
    const field = e.node("field");
    e.cx.setFocus(field);
    const field_id: core.NodeHandle = .{ .id = field.id, .generation = try e.cx.node_registry.trackGeneration(field) };
    e.cx.detachChildRetained(e.node("home"), surface);
    try e.node("away").appendChild(testing.allocator, surface);
    try testing.expect(e.cx.focus_manager.getFocused() == null);
    try testing.expectEqual(@as(usize, 1), e.spy.blurs);
    _ = try e.cx.node_registry.trackGeneration(field);
    try testing.expect(!e.cx.node_registry.isCurrentIdentity(field_id, field));
}

test "moveChildRetained: what was bound to the old place ends — pressed, hover, pointer capture" {
    var e = try Env.init();
    defer e.deinit();
    const surface = e.node("surface");
    const field = e.node("field");
    const outside = e.node("outside");
    _ = try e.cx.node_registry.trackGeneration(field);
    e.cx.pressed_node = field;
    e.cx.hovered_node = field;
    e.cx.last_mouse_down_target = field;
    e.cx.dispatcher.setPointerCapture(field);
    try e.cx.moveChildRetained(surface, e.node("away"), null);
    try testing.expect(e.cx.pressed_node == null);
    try testing.expect(e.cx.hovered_node == null);
    try testing.expect(e.cx.last_mouse_down_target == null);
    try testing.expect(e.cx.dispatcher.pointer_capture_handle == null);

    // State of nodes outside the moved subtree is not touched.
    e.cx.pressed_node = outside;
    try e.cx.moveChildRetained(surface, e.node("home"), null);
    try testing.expect(e.cx.pressed_node == outside);
    e.cx.pressed_node = null;
}

test "moveChildRetained: a destination outside the window takes focus away like a removal" {
    var e = try Env.init();
    defer e.deinit();
    const surface = e.node("surface");
    e.cx.setFocus(e.node("field"));
    const loose = try core.box(e.cx, .{}, .{});
    defer e.cx.freeNode(loose);
    try e.cx.moveChildRetained(surface, loose, null);
    try testing.expect(e.cx.focus_manager.getFocused() == null);
    try testing.expectEqual(@as(usize, 1), e.spy.blurs);
    // Coming back is an ordinary move; focus is not brought back by the tree.
    try e.cx.moveChildRetained(surface, e.node("home"), null);
    try testing.expect(e.cx.focus_manager.getFocused() == null);
}

test "moveChildRetained: a refused move changes nothing" {
    var e = try Env.init();
    defer e.deinit();
    const surface = e.node("surface");
    const field = e.node("field");
    e.cx.setFocus(field);
    e.cx.pressed_node = field;
    try testing.expectError(error.CyclicNodeTree, e.cx.moveChildRetained(surface, field, null));
    try testing.expectError(error.InvalidAnchor, e.cx.moveChildRetained(surface, e.node("away"), e.node("outside")));
    try testing.expect(surface.parent == e.node("home"));
    try testing.expect(e.cx.focus_manager.getFocused() == field);
    try testing.expect(e.cx.pressed_node == field);
    try testing.expectEqual(@as(usize, 0), e.spy.blurs);
    e.cx.pressed_node = null;
}
