//! ui.view capture-phase key attributes (`on_key_down_capture` / `on_key_up_capture`, Yix
//! onKeyDownCapture) driven through the real key path (Cx.handleKeyDown -> routeKeyDown ->
//! EventDispatcher). Design: docs/FOCUS_AND_KEY_CAPTURE_DESIGN.md.
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
const KeyPress = v.KeyPress;

/// A mounted view installed as the window's tree (root = content root), so keys route the way
/// they do in an app window.
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
        e.cx.layout();
        return root;
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

/// Records handler calls in order ("wc" = window capture, "t" = target, "wb" = window bubble).
const Log = struct {
    buf: [16][]const u8 = undefined,
    len: usize = 0,
    /// What the window capture handler does with the key.
    capture_action: enum { pass, consume, stop } = .pass,
    saw_composing: ?bool = null,

    fn push(self: *Log, tag: []const u8) void {
        self.buf[self.len] = tag;
        self.len += 1;
    }
    fn has(self: *const Log, comptime want: []const []const u8) !void {
        try testing.expectEqual(want.len, self.len);
        for (want, self.buf[0..self.len]) |w, got| try testing.expectEqualStrings(w, got);
    }
    fn windowCapture(self: *Log, e: KeyPress) void {
        self.push("wc");
        switch (self.capture_action) {
            .pass => {},
            .consume => e.consume(),
            .stop => e.stop(),
        }
    }
    fn windowCaptureUp(self: *Log, _: KeyPress) void {
        self.push("wcu");
    }
    fn target(self: *Log, _: KeyPress) void {
        self.push("t");
    }
    fn windowBubble(self: *Log, e: KeyPress) void {
        self.saw_composing = e.composing;
        self.push("wb");
    }
};

fn handler(log: *Log, comptime method: anytype) core.Handler(KeyPress) {
    return core.Handler(KeyPress).from(Log, log, method);
}

fn mountWindow(e: *Env, log: *Log) !*Node {
    return e.mount(v.box(.{
        .test_id = "window",
        .on_key_down_capture = handler(log, Log.windowCapture),
        .on_key_up_capture = handler(log, Log.windowCaptureUp),
        .on_key_down = handler(log, Log.windowBubble),
    }, .{v.box(.{ .test_id = "panel" }, .{v.box(.{ .test_id = "field", .focusable = true, .on_key_down = handler(log, Log.target) }, .{})})}));
}

test "onKeyDownCapture: a non-focusable container sees the key before the focused child; pass lets target and bubble run" {
    var e = try Env.init();
    defer e.deinit();
    var log: Log = .{};
    const root = try mountWindow(&e, &log);
    try testing.expect(!root.behavior.interaction.focusable);
    const field = findTestId(root, "field").?;
    e.cx.setFocus(field);
    e.cx.handleKeyDown(.w, .{ .super = true });
    try log.has(&.{ "wc", "t", "wb" });
    try testing.expectEqual(@as(?bool, false), log.saw_composing);
    e.cx.handleKeyUp(.w, .{ .super = true });
    try log.has(&.{ "wc", "t", "wb", "wcu" });
}

test "onKeyDownCapture: e.stop() keeps the key from the target and bubble; e.consume() only prevents the default" {
    var e = try Env.init();
    defer e.deinit();
    var log: Log = .{ .capture_action = .stop };
    const root = try mountWindow(&e, &log);
    const field = findTestId(root, "field").?;
    e.cx.setFocus(field);
    e.cx.handleKeyDown(.w, .{ .super = true });
    try log.has(&.{"wc"});

    // consume: the target still gets the key, but Tab no longer traverses focus.
    log = .{ .capture_action = .consume };
    e.cx.handleKeyDown(.tab, .{});
    try log.has(&.{ "wc", "t", "wb" });
    try testing.expectEqual(field, e.cx.focus_manager.getFocused().?);
}

test "onKeyDownCapture: with nothing focused the window template root still receives keys (no focusable card needed)" {
    var e = try Env.init();
    defer e.deinit();
    var log: Log = .{};
    _ = try mountWindow(&e, &log);
    try testing.expect(e.cx.focus_manager.getFocused() == null);
    e.cx.handleKeyDown(.escape, .{});
    // Target phase on the content root: its capture handler first, then its own onKeyDown.
    try log.has(&.{ "wc", "wb" });
}

const ComposingClient = struct {
    composing: bool = true,
    fn textLen(_: *anyopaque) usize {
        return 0;
    }
    fn copyText(_: *anyopaque, _: usize, _: []u8) usize {
        return 0;
    }
    fn selection(_: *anyopaque) types.TextInputSelection {
        return .{ .start = 0, .end = 0, .caret = 0 };
    }
    fn isComposing(ctx: *anyopaque) bool {
        const self: *ComposingClient = @ptrCast(@alignCast(ctx));
        return self.composing;
    }
    fn client(self: *ComposingClient) types.TextInputClient {
        return .{ .context = @ptrCast(self), .text_len = textLen, .copy_text = copyText, .selection = selection, .is_composing = isComposing };
    }
};

test "onKeyDownCapture: keys routed while the focused input composes skip capture handlers; onKeyDown sees e.composing" {
    var e = try Env.init();
    defer e.deinit();
    var log: Log = .{ .capture_action = .stop };
    const root = try mountWindow(&e, &log);
    const field = findTestId(root, "field").?;
    var ime: ComposingClient = .{};
    field.behavior.interaction.text_input_client = ime.client();
    e.cx.setFocus(field);
    // Escape during composition belongs to the input: the window's stop() must not swallow it.
    e.cx.handleKeyDown(.escape, .{});
    try log.has(&.{ "t", "wb" });
    try testing.expectEqual(@as(?bool, true), log.saw_composing);
    // Composition over: the window captures again.
    ime.composing = false;
    log = .{ .capture_action = .stop };
    e.cx.handleKeyDown(.escape, .{});
    try log.has(&.{"wc"});
    field.behavior.interaction.text_input_client = null;
}

test "onKeyDownCapture: the adapter leaves the node at scope release; elements without it keep an empty capture slot" {
    var e = try Env.init();
    var log: Log = .{};
    const root = try mountWindow(&e, &log);
    try testing.expect(root.behavior.events.on_event_capture != null);
    try testing.expect(findTestId(root, "panel").?.behavior.events.on_event_capture == null);
    try testing.expect(findTestId(root, "field").?.behavior.events.on_event_capture == null);
    e.scope.dispose();
    try testing.expect(root.behavior.events.on_event_capture == null);
    try testing.expect(root.behavior.events.capture_context == null);
    e.cx.root = null;
    e.cx.content_root = null;
    e.cx.freeNode(root);
    e.root = null;
    e.cx.deinit();
}
