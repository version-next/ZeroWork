//! Keys routed while the focused text input composes (IME preedit): they belong to the input
//! method. Driven through the real key path (Cx.handleKeyDown -> routeKeyDown -> EventDispatcher).
const std = @import("std");
const testing = std.testing;
const core = @import("../core.zig");
const types = @import("types.zig");
const events_mod = @import("../events.zig");
const Cx = core.Cx;
const Node = core.Node;

/// A text input client whose composition state the test drives.
const Ime = struct {
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
        const self: *Ime = @ptrCast(@alignCast(ctx));
        return self.composing;
    }
    fn client(self: *Ime) types.TextInputClient {
        return .{ .context = @ptrCast(self), .text_len = textLen, .copy_text = copyText, .selection = selection, .is_composing = isComposing };
    }
};

/// What reached the nodes. `field_handles_keys`: the field's own handler takes every key (zenit's
/// Input does while composing); false = a client that leaves keys it does not use unhandled.
const Seen = struct {
    clicks: usize = 0,
    row_keys: usize = 0,
    field_keys: usize = 0,
    actions: usize = 0,
    field_handles_keys: bool = false,

    fn rowEvent(event: events_mod.Event, ctx: ?*anyopaque) events_mod.EventResult {
        const self: *Seen = @ptrCast(@alignCast(ctx.?));
        switch (event) {
            .click => self.clicks += 1,
            else => {},
        }
        return .ignored;
    }
    fn rowKey(_: core.KeyCode, _: core.Modifiers, ctx: ?*anyopaque) events_mod.EventResult {
        const self: *Seen = @ptrCast(@alignCast(ctx.?));
        self.row_keys += 1;
        return .handled;
    }
    fn fieldEvent(event: events_mod.Event, ctx: ?*anyopaque) events_mod.EventResult {
        const self: *Seen = @ptrCast(@alignCast(ctx.?));
        switch (event) {
            .key_down => {
                self.field_keys += 1;
                return if (self.field_handles_keys) .handled else .ignored;
            },
            else => return .ignored,
        }
    }
    fn onAction(_: @import("../actions.zig").Action, ctx: ?*anyopaque) events_mod.EventResult {
        const self: *Seen = @ptrCast(@alignCast(ctx.?));
        self.actions += 1;
        return .handled;
    }
};

/// root > row (clickable, handles keys in on_key_down) > field (text input) ; root > other (focusable)
const Rig = struct {
    cx: *Cx,
    row: *Node,
    field: *Node,
    other: *Node,

    fn init(seen: *Seen, ime: *Ime) !Rig {
        const cx = try Cx.init(testing.allocator, std.testing.io);
        cx.setViewport(300, 200);
        const root = try core.box(cx, .{ .width = .{ .px = 300 }, .height = .{ .px = 200 }, .direction = .column }, .{});
        cx.root = root;
        cx.content_root = root;
        const row = try core.box(cx, .{ .width = .{ .px = 300 }, .height = .{ .px = 40 } }, .{});
        row.behavior.events.event_context = seen;
        row.behavior.events.on_event = Seen.rowEvent;
        row.behavior.events.key_context = seen;
        row.behavior.events.on_key_down = Seen.rowKey;
        row.behavior.interaction.key_context = "row";
        row.behavior.events.action_context = seen;
        row.behavior.events.on_action = Seen.onAction;
        try root.appendChild(cx.allocator, row);
        const field = try core.box(cx, .{ .width = .{ .px = 200 }, .height = .{ .px = 30 } }, .{});
        field.setFocusable(true);
        field.tag = .input;
        field.behavior.events.event_context = seen;
        field.behavior.events.on_event = Seen.fieldEvent;
        field.behavior.interaction.text_input_client = ime.client();
        try row.appendChild(cx.allocator, field);
        const other = try core.box(cx, .{ .width = .{ .px = 100 }, .height = .{ .px = 30 } }, .{});
        other.setFocusable(true);
        try root.appendChild(cx.allocator, other);
        cx.layout();
        cx.setFocus(field);
        return .{ .cx = cx, .row = row, .field = field, .other = other };
    }

    fn deinit(r: *Rig) void {
        r.field.behavior.interaction.text_input_client = null;
        r.cx.deinit();
    }
};

test "IME: Enter routed during a composition does not synthesize a click on the input" {
    var seen: Seen = .{};
    var ime: Ime = .{};
    var rig = try Rig.init(&seen, &ime);
    defer rig.deinit();
    rig.cx.handleKeyDown(.@"return", .{});
    // The key reached the input (target phase, with its flag), not the row's flag-less handler.
    try testing.expectEqual(@as(usize, 1), seen.field_keys);
    try testing.expectEqual(@as(usize, 0), seen.row_keys);
    // No default activation: nothing clicked the input, nothing bubbled a click to the row.
    try testing.expectEqual(@as(usize, 0), seen.clicks);
    // Composition over: Enter is an ordinary key again (the row's handler takes it).
    ime.composing = false;
    rig.cx.handleKeyDown(.@"return", .{});
    try testing.expectEqual(@as(usize, 1), seen.row_keys);
}

test "IME: Space routed during a composition does not synthesize a click" {
    var seen: Seen = .{};
    var ime: Ime = .{};
    var rig = try Rig.init(&seen, &ime);
    defer rig.deinit();
    rig.row.behavior.events.on_key_down = null;
    rig.cx.handleKeyDown(.space, .{});
    try testing.expectEqual(@as(usize, 1), seen.field_keys);
    try testing.expectEqual(@as(usize, 0), seen.clicks);
}

test "IME: Tab routed during a composition does not move focus" {
    var seen: Seen = .{};
    var ime: Ime = .{};
    var rig = try Rig.init(&seen, &ime);
    defer rig.deinit();
    rig.row.behavior.events.on_key_down = null;
    rig.cx.handleKeyDown(.tab, .{});
    try testing.expect(rig.cx.focus_manager.getFocused() == rig.field);
    try testing.expectEqual(@as(usize, 1), seen.field_keys);
    // Composition over: Tab traverses again.
    ime.composing = false;
    rig.cx.handleKeyDown(.tab, .{});
    try testing.expect(rig.cx.focus_manager.getFocused() == rig.other);
}

test "IME: a plain-key action binding does not fire during a composition; a Cmd / Ctrl chord does" {
    var seen: Seen = .{};
    var ime: Ime = .{};
    var rig = try Rig.init(&seen, &ime);
    defer rig.deinit();
    rig.cx.action_dispatcher.bind(.@"return", .{}, .{ .context = "row", .name = "confirm" });
    rig.cx.action_dispatcher.bind(.s, .{ .super = true }, .{ .context = "row", .name = "save" });
    rig.cx.handleKeyDown(.@"return", .{});
    try testing.expectEqual(@as(usize, 0), seen.actions);
    try testing.expectEqual(@as(usize, 0), seen.clicks);
    // A shortcut chord is not text: it reaches its binding as it does on Windows (VK_PROCESSKEY
    // with Ctrl / Alt is reported as the real key).
    rig.cx.handleKeyDown(.s, .{ .super = true });
    try testing.expectEqual(@as(usize, 1), seen.actions);
    ime.composing = false;
    rig.cx.handleKeyDown(.@"return", .{});
    try testing.expectEqual(@as(usize, 2), seen.actions);
}
