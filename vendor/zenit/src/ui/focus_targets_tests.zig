//! Declarative focus through ui.view (`focus_id` / `auto_focus` / `focus_request` /
//! `focus_restore`, Yix focusId / autoFocus / focusRequest / focusRestore) without a window:
//! pending work is settled the way Cx.render does at frame start (Cx.settlePendingFocus).
//! Design: docs/FOCUS_AND_KEY_CAPTURE_DESIGN.md.
const std = @import("std");
const testing = std.testing;
const core = @import("core.zig");
const reactive = @import("reactive.zig");
const theme = @import("theme.zig");
const types = @import("core/types.zig");
const v = @import("view.zig");
const Node = core.Node;
const Cx = core.Cx;
const Scope = reactive.Scope;
const FocusRequest = v.FocusRequest;

const Env = struct {
    cx: *Cx,
    scope: *Scope,
    root: ?*Node = null,

    fn init() !Env {
        const cx = try Cx.init(testing.allocator, std.testing.io);
        cx.tokens = &theme.light;
        const scope = try Scope.init(testing.allocator, null, cx.owner);
        return .{ .cx = cx, .scope = scope };
    }

    fn mount(e: *Env, element: anytype) !*Node {
        const root = try v.render(e.scope, e.cx, element);
        e.root = root;
        e.cx.root = root;
        e.cx.content_root = root;
        return root;
    }

    fn focused(e: *Env) ?[]const u8 {
        const n = e.cx.focus_manager.getFocused() orelse return null;
        return n.meta.ownership.meta.test_id;
    }

    fn deinit(e: *Env) void {
        e.scope.dispose();
        e.cx.root = null;
        e.cx.content_root = null;
        if (e.root) |r| e.cx.freeNode(r);
        e.cx.deinit();
    }
};

fn findTestId(n: *Node, id: []const u8) ?*Node {
    if (n.meta.ownership.meta.test_id) |t| if (std.mem.eql(u8, t, id)) return n;
    for (n.children.items) |c| if (findTestId(c, id)) |r| return r;
    return null;
}

fn expectFocused(e: *Env, want: ?[]const u8) !void {
    const got = e.focused();
    if (want) |w| {
        try testing.expect(got != null);
        try testing.expectEqualStrings(w, got.?);
    } else try testing.expect(got == null);
}

test "autoFocus: focuses its target once settled; resolves to the first focusable descendant" {
    var e = try Env.init();
    defer e.deinit();
    _ = try e.mount(v.col(.{}, .{
        v.box(.{ .test_id = "a", .focusable = true }, .{}),
        v.box(.{ .test_id = "wrap", .focus_id = "search", .auto_focus = true }, .{v.box(.{ .test_id = "inner", .focusable = true }, .{})}),
    }));
    try expectFocused(&e, null);
    try testing.expect(e.cx.needs_redraw);
    e.cx.settlePendingFocus();
    try expectFocused(&e, "inner");
    // Not repeated: a later settle after the user moved on leaves focus alone.
    e.cx.setFocus(findTestId(e.root.?, "a").?);
    e.cx.settlePendingFocus();
    try expectFocused(&e, "a");
}

test "autoFocus: any focus transition after mount supersedes it (last writer wins)" {
    var e = try Env.init();
    defer e.deinit();
    const root = try e.mount(v.col(.{}, .{
        v.box(.{ .test_id = "a", .focusable = true }, .{}),
        v.box(.{ .test_id = "b", .focusable = true, .auto_focus = true }, .{}),
    }));
    e.cx.setFocus(findTestId(root, "a").?);
    e.cx.settlePendingFocus();
    try expectFocused(&e, "a");
}

test "autoFocus: a hidden or disabled target waits until it is ready" {
    var e = try Env.init();
    defer e.deinit();
    const shown = try e.scope.createSignal(bool, false);
    _ = try e.mount(v.col(.{}, .{
        v.box(.{ .test_id = "h", .focusable = true, .auto_focus = true, .visible = shown }, .{}),
    }));
    e.cx.settlePendingFocus();
    try expectFocused(&e, null);
    shown.set(true);
    e.cx.settlePendingFocus();
    try expectFocused(&e, "h");

    // Disabled (a11y.disabled) targets are not ready either.
    var e2 = try Env.init();
    defer e2.deinit();
    _ = try e2.mount(v.col(.{}, .{v.box(.{ .test_id = "x", .focusable = true, .auto_focus = true, .a11y = .{ .disabled = true } }, .{})}));
    e2.cx.settlePendingFocus();
    try expectFocused(&e2, null);
}

test "focusRequest: focuses a ready target at once; the mount-time value is only a baseline" {
    var e = try Env.init();
    defer e.deinit();
    const req = try e.scope.createSignal(FocusRequest, (FocusRequest{}).to("b"));
    _ = try e.mount(v.col(.{ .focus_request = req }, .{
        v.box(.{ .test_id = "a", .focusable = true, .focus_id = "a" }, .{}),
        v.box(.{ .test_id = "b", .focusable = true, .focus_id = "b" }, .{}),
    }));
    e.cx.settlePendingFocus();
    try expectFocused(&e, null); // baseline request not replayed
    req.set(req.peek().to("a"));
    try expectFocused(&e, "a");
    req.set(req.peek().to("b"));
    try expectFocused(&e, "b");
    // Same target twice: seq tells the requests apart.
    e.cx.clearFocus();
    req.set(req.peek().to("b"));
    try expectFocused(&e, "b");
    // blur clears focus inside the requesting element.
    req.set(req.peek().blur());
    try expectFocused(&e, null);
}

test "focusRequest: a target mounted later is focused at the next settle; a newer transition cancels it" {
    var e = try Env.init();
    defer e.deinit();
    const req = try e.scope.createSignal(FocusRequest, .{});
    const open = try e.scope.createSignal(bool, false);
    const root = try e.mount(v.col(.{ .focus_request = req }, .{
        v.box(.{ .test_id = "a", .focusable = true }, .{}),
        v.show(open, .{v.box(.{ .test_id = "late", .focusable = true, .focus_id = "late" }, .{})}),
    }));
    req.set(req.peek().to("late"));
    try expectFocused(&e, null);
    open.set(true);
    e.cx.settlePendingFocus();
    try expectFocused(&e, "late");

    // Pending again, then an imperative setFocus wins.
    open.set(false);
    try expectFocused(&e, null);
    req.set(req.peek().to("late"));
    e.cx.setFocus(findTestId(root, "a").?);
    open.set(true);
    e.cx.settlePendingFocus();
    try expectFocused(&e, "a");
}

test "focusId / focusRequest keep working after their subtree was detached retained and attached again" {
    var e = try Env.init();
    defer e.deinit();
    const req = try e.scope.createSignal(FocusRequest, .{});
    const root = try e.mount(v.col(.{}, .{
        v.box(.{ .test_id = "outside", .focusable = true }, .{}),
        v.col(.{ .test_id = "panel", .focus_request = req }, .{
            v.box(.{ .test_id = "a", .focusable = true, .focus_id = "a" }, .{}),
            v.box(.{ .test_id = "b", .focusable = true, .focus_id = "b" }, .{}),
        }),
    }));
    req.set(req.peek().to("a"));
    try expectFocused(&e, "a");
    // A panel that leaves the tree while closed (retained: its nodes and scope live on).
    const panel = findTestId(root, "panel").?;
    e.cx.detachChildRetained(root, panel);
    try expectFocused(&e, null);
    req.set(req.peek().to("b"));
    e.cx.settlePendingFocus();
    try expectFocused(&e, null); // not in the window: stays pending
    try root.appendChild(testing.allocator, panel);
    e.cx.settlePendingFocus();
    try expectFocused(&e, "b");
    // And a request made after the re-attach.
    req.set(req.peek().to("a"));
    try expectFocused(&e, "a");
}

test "focusRequest: lookup stays inside the requesting element and its window" {
    var e = try Env.init();
    defer e.deinit();
    var other = try Env.init();
    defer other.deinit();
    const req = try e.scope.createSignal(FocusRequest, .{});
    _ = try e.mount(v.col(.{}, .{
        v.box(.{ .test_id = "outside", .focusable = true, .focus_id = "x" }, .{}),
        v.box(.{ .focus_request = req }, .{v.box(.{ .test_id = "inside", .focusable = true, .focus_id = "y" }, .{})}),
    }));
    _ = try other.mount(v.col(.{}, .{v.box(.{ .test_id = "elsewhere", .focusable = true, .focus_id = "x" }, .{})}));
    req.set(req.peek().to("x"));
    e.cx.settlePendingFocus();
    other.cx.settlePendingFocus();
    try expectFocused(&e, null);
    try expectFocused(&other, null);
    req.set(req.peek().to("y"));
    try expectFocused(&e, "inside");
    try expectFocused(&other, null);
}

/// A text-input client stub: selection reads/writes for restore.
const FakeClient = struct {
    sel: types.TextInputSelection = .{ .start = 2, .end = 4, .caret = 4 },
    set_calls: u32 = 0,
    len: usize = 10,
    fn textLen(ctx: *anyopaque) usize {
        return @as(*FakeClient, @ptrCast(@alignCast(ctx))).len;
    }
    fn copyText(_: *anyopaque, _: usize, _: []u8) usize {
        return 0;
    }
    fn selection(ctx: *anyopaque) types.TextInputSelection {
        return @as(*FakeClient, @ptrCast(@alignCast(ctx))).sel;
    }
    fn setSelection(ctx: *anyopaque, start: u32, end: u32) bool {
        const self: *FakeClient = @ptrCast(@alignCast(ctx));
        self.sel = .{ .start = start, .end = end, .caret = end };
        self.set_calls += 1;
        return true;
    }
    fn client(self: *FakeClient) types.TextInputClient {
        return .{ .context = @ptrCast(self), .text_len = textLen, .copy_text = copyText, .selection = selection, .set_selection = setSelection };
    }
};

test "focusRestore: focus returns to the same focusId after the subtree is remounted, with its selection" {
    var e = try Env.init();
    defer e.deinit();
    const page = try e.scope.createSignal(bool, true);
    const root = try e.mount(v.col(.{}, .{
        v.box(.{ .test_id = "nav", .focusable = true }, .{}),
        v.box(.{ .test_id = "content", .focus_restore = true }, .{
            v.show(page, .{v.box(.{ .focus_id = "name" }, .{v.box(.{ .test_id = "field", .focusable = true }, .{})})}),
        }),
    }));
    var old_client: FakeClient = .{};
    const field = findTestId(root, "field").?;
    field.behavior.interaction.text_input_client = old_client.client();
    e.cx.focus_manager.setFocusWithVisibility(field, .tab, .show);
    // The component owning the client tears down first (Input does this in its scope cleanup).
    e.cx.focus_manager.abandonFocus(field);
    field.behavior.interaction.text_input_client = null;
    page.set(false);
    try expectFocused(&e, null);
    page.set(true);
    var new_client: FakeClient = .{ .sel = .{ .start = 0, .end = 0, .caret = 0 } };
    const again = findTestId(root, "field").?;
    again.behavior.interaction.text_input_client = new_client.client();
    e.cx.settlePendingFocus();
    try expectFocused(&e, "field");
    try testing.expect(e.cx.focus_manager.focus_visible);
    try testing.expectEqual(@as(u32, 1), new_client.set_calls);
    try testing.expectEqual(@as(u32, 2), new_client.sel.start);
    try testing.expectEqual(@as(u32, 4), new_client.sel.end);
    again.behavior.interaction.text_input_client = null;
}

test "focusRestore: teardown without abandon (plain focusable) restores too; focus taken elsewhere first cancels it" {
    var e = try Env.init();
    defer e.deinit();
    const page = try e.scope.createSignal(bool, true);
    const root = try e.mount(v.col(.{}, .{
        v.box(.{ .test_id = "nav", .focusable = true }, .{}),
        v.box(.{ .focus_restore = true }, .{
            v.show(page, .{v.box(.{ .test_id = "sw", .focusable = true, .focus_id = "sw" }, .{})}),
        }),
    }));
    e.cx.setFocus(findTestId(root, "sw").?);
    page.set(false);
    try expectFocused(&e, null);
    page.set(true);
    e.cx.settlePendingFocus();
    try expectFocused(&e, "sw");

    page.set(false);
    e.cx.setFocus(findTestId(root, "nav").?);
    page.set(true);
    e.cx.settlePendingFocus();
    try expectFocused(&e, "nav");
}

test "focusRestore: without a region, or after a deliberate blur, nothing is restored (unchanged behaviour)" {
    var e = try Env.init();
    defer e.deinit();
    const page = try e.scope.createSignal(bool, true);
    const root = try e.mount(v.col(.{}, .{
        v.box(.{}, .{v.show(page, .{v.box(.{ .test_id = "sw", .focusable = true, .focus_id = "sw" }, .{})})}),
    }));
    e.cx.setFocus(findTestId(root, "sw").?);
    page.set(false);
    page.set(true);
    e.cx.settlePendingFocus();
    try expectFocused(&e, null);
    try testing.expect(!e.cx.focus_targets.hasPending());
}

/// A hand-written component whose root is not focusable; its inner field is.
const Field = struct {
    pub fn mount(_: Field, _: *Scope, cx: *Cx) !*Node {
        const root = try core.box(cx, .{}, .{});
        errdefer cx.freeNode(root);
        const inner = try core.box(cx, .{}, .{});
        inner.setFocusable(true);
        inner.meta.ownership.meta.test_id = "field.inner";
        try root.appendChild(cx.allocator, inner);
        return root;
    }
};

test "focusId / autoFocus on a component element apply to its root and resolve to the focusable part inside" {
    var e = try Env.init();
    defer e.deinit();
    _ = try e.mount(v.col(.{}, .{v.attrs(.{ .focus_id = "search", .auto_focus = true }, Field{})}));
    e.cx.settlePendingFocus();
    try expectFocused(&e, "field.inner");
}

test "inert: Tab skips an inert subtree and its a11y; a source toggles it back" {
    var e = try Env.init();
    defer e.deinit();
    const folded = try e.scope.createSignal(bool, true);
    const root = try e.mount(v.col(.{}, .{
        v.box(.{ .test_id = "a", .focusable = true }, .{}),
        v.box(.{ .test_id = "slot", .inert = folded }, .{v.box(.{ .test_id = "hidden", .focusable = true }, .{})}),
        v.box(.{ .test_id = "b", .focusable = true }, .{}),
    }));
    e.cx.layout();
    try e.cx.focus_manager.collectFocusableNodes(root);
    const hidden = findTestId(root, "hidden").?;
    try testing.expect(!e.cx.focus_manager.keyboardReachable(hidden));
    e.cx.setFocus(findTestId(root, "a").?);
    e.cx.focus_manager.focusNext();
    try expectFocused(&e, "b");
    e.cx.focus_manager.focusPrev();
    try expectFocused(&e, "a");
    // Explicit focus still works (a host returning focus to the folded button).
    e.cx.setFocus(hidden);
    try expectFocused(&e, "hidden");
    folded.set(false);
    try testing.expect(!findTestId(root, "slot").?.behavior.interaction.inert);
    try testing.expect(e.cx.focus_manager.keyboardReachable(hidden));
    e.cx.setFocus(findTestId(root, "a").?);
    e.cx.focus_manager.focusNext();
    try expectFocused(&e, "hidden");
}

test "targetName: the focusId around a node, while that target is mounted" {
    var e = try Env.init();
    defer e.deinit();
    const page = try e.scope.createSignal(bool, true);
    const root = try e.mount(v.col(.{}, .{
        v.box(.{ .test_id = "nav", .focusable = true }, .{}),
        v.box(.{ .test_id = "content", .focus_restore = true }, .{
            v.show(page, .{v.box(.{ .focus_id = "name" }, .{v.box(.{ .test_id = "field", .focusable = true }, .{})})}),
            v.box(.{ .test_id = "plain", .focusable = true, .auto_focus = false }, .{}),
        }),
    }));
    const targets = &e.cx.focus_targets;
    // The named target itself and anything inside it.
    const field = findTestId(root, "field").?;
    try testing.expectEqualStrings("name", targets.targetName(e.cx, field).?);
    try testing.expectEqualStrings("name", targets.targetName(e.cx, field.parent.?).?);
    // Outside any named target: a restore region or an unnamed target is not a name.
    try testing.expect(targets.targetName(e.cx, findTestId(root, "nav").?) == null);
    try testing.expect(targets.targetName(e.cx, findTestId(root, "content").?) == null);
    try testing.expect(targets.targetName(e.cx, findTestId(root, "plain").?) == null);
    // Unmounted: the registration is gone with its scope.
    page.set(false);
    try testing.expect(targets.targetName(e.cx, findTestId(root, "content").?) == null);
    page.set(true);
    try testing.expectEqualStrings("name", targets.targetName(e.cx, findTestId(root, "field").?).?);
}
