//! Frame-first delivery through a Cx (docs/design/append-inbox.md §8). Imported from core.zig's
//! test block.
const std = @import("std");
const testing = std.testing;
const core = @import("../core.zig");
const Cx = core.Cx;
const Node = core.Node;
const Scope = core.Scope;
const Signal = core.Signal;
const Inbox = core.Inbox;
const box = core.box;
const cx_render = @import("cx_render.zig");
const slots = @import("inbox.zig");

var wakes: std.atomic.Value(u32) = .init(0);
fn countWake() void {
    _ = wakes.fetchAdd(1, .monotonic);
}

/// A host's ordinary frame: deliveries, clock, layout, render.
fn frame(cx: *Cx) void {
    _ = cx.deliverInboxes();
    cx.advanceFrameClock();
    cx.layout();
    _ = cx.render();
}

const Counter = struct {
    calls: usize = 0,
    fn run(self: *Counter) void {
        self.calls += 1;
    }
};

test "Inbox: the callback runs before the frame's first layout; one after-layout round" {
    const cx = try Cx.init(testing.allocator, testing.io);
    defer cx.deinit();
    const scope = try Scope.init(testing.allocator, null, cx.owner);
    defer scope.dispose();
    const child = try box(cx, .{ .width = .{ .px = 10 }, .height = .{ .px = 10 }, .flex_shrink = 0 }, .{});
    cx.root = try box(cx, .{ .width = .{ .px = 400 }, .height = .{ .px = 100 } }, .{child});
    frame(cx);

    // Data -> signal -> effect -> tree, the shape a streaming view has.
    const Model = struct {
        width: *Signal(f32),
        child: *Node,
        incoming: f32 = 0,
        fn drain(self: *@This()) void {
            self.width.set(self.incoming);
        }
        fn apply(self: *@This()) void {
            self.child.setWidth(self.width.get());
        }
    };
    var model: Model = .{ .width = try scope.createSignal(f32, 10), .child = child };
    try scope.createEffect(&model, Model.apply);
    const inbox = try cx.createInbox(scope, cx.on(Model, &model, Model.drain));

    const Rounds = struct {
        child: *Node,
        rounds: usize = 0,
        width_seen: f32 = 0,
        fn run(raw: *anyopaque, round: u8, _: bool) core.AfterLayoutResult {
            const self: *@This() = @ptrCast(@alignCast(raw));
            _ = round;
            self.rounds += 1;
            self.width_seen = self.child.rectFromWorldOrFallback().w;
            return .done;
        }
    };
    var rounds: Rounds = .{ .child = child };
    try cx.addAfterLayoutHook(&rounds, Rounds.run);
    defer cx.removeAfterLayoutHook(&rounds);
    frame(cx);
    rounds.rounds = 0;

    model.incoming = 77;
    inbox.notify();
    try testing.expect(cx.inboxPending());
    try testing.expect(cx.wantsFrame());
    try testing.expectEqual(@as(usize, 1), cx.deliverInboxes());
    // The effect of the callback's write has already run (one owner batch).
    try testing.expect(child.style.width == .px and child.style.width.px == 77);
    cx.advanceFrameClock();
    cx.layout();
    // The first layout of the frame already has it.
    try testing.expectApproxEqAbs(@as(f32, 77), child.rectFromWorldOrFallback().w, 0.001);
    _ = cx.render();
    try testing.expectEqual(@as(usize, 1), rounds.rounds);
    try testing.expectApproxEqAbs(@as(f32, 77), rounds.width_seen, 0.001);
    try testing.expect(!cx.inboxPending());
    try testing.expect(!cx.wantsFrame());
}

test "Inbox: a notify from another thread wakes the host and the next frame delivers once" {
    const cx = try Cx.init(testing.allocator, testing.io);
    defer cx.deinit();
    const scope = try Scope.init(testing.allocator, null, cx.owner);
    defer scope.dispose();
    cx.root = try box(cx, .{ .width = .{ .px = 40 }, .height = .{ .px = 40 } }, .{});
    wakes.store(0, .monotonic);
    cx.setWakeHandler(countWake);
    var counter: Counter = .{};
    const inbox = try cx.createInbox(scope, cx.on(Counter, &counter, Counter.run));
    frame(cx);
    try testing.expect(!cx.wantsFrame());

    const Producer = struct {
        fn run(target: Inbox) void {
            for (0..1000) |_| target.notify();
        }
    };
    var threads: [4]std.Thread = undefined;
    for (&threads) |*t| t.* = try std.Thread.spawn(.{}, Producer.run, .{inbox});
    for (threads) |t| t.join();
    // 4000 notifications, one host wake, one delivery.
    try testing.expectEqual(@as(u32, 1), wakes.load(.monotonic));
    try testing.expect(cx.wantsFrame());
    frame(cx);
    try testing.expectEqual(@as(usize, 1), counter.calls);
    try testing.expect(!cx.wantsFrame());
    frame(cx);
    try testing.expectEqual(@as(usize, 1), counter.calls);
}

test "Inbox: a notify during the callback is delivered next frame" {
    const cx = try Cx.init(testing.allocator, testing.io);
    defer cx.deinit();
    const scope = try Scope.init(testing.allocator, null, cx.owner);
    defer scope.dispose();
    const Again = struct {
        inbox: Inbox = .none,
        calls: usize = 0,
        fn run(self: *@This()) void {
            self.calls += 1;
            if (self.calls == 1) self.inbox.notify();
        }
    };
    var again: Again = .{};
    again.inbox = try cx.createInbox(scope, cx.on(Again, &again, Again.run));
    again.inbox.notify();
    frame(cx);
    try testing.expectEqual(@as(usize, 1), again.calls);
    try testing.expect(cx.wantsFrame());
    frame(cx);
    try testing.expectEqual(@as(usize, 2), again.calls);
    try testing.expect(!cx.wantsFrame());
}

test "Inbox: only the owning window wants a frame and runs its callback" {
    const a = try Cx.init(testing.allocator, testing.io);
    defer a.deinit();
    const b = try Cx.init(testing.allocator, testing.io);
    defer b.deinit();
    const scope_a = try Scope.init(testing.allocator, null, a.owner);
    defer scope_a.dispose();
    const scope_b = try Scope.init(testing.allocator, null, b.owner);
    defer scope_b.dispose();
    a.root = try box(a, .{ .width = .{ .px = 40 }, .height = .{ .px = 40 } }, .{});
    b.root = try box(b, .{ .width = .{ .px = 40 }, .height = .{ .px = 40 } }, .{});
    wakes.store(0, .monotonic);
    a.setWakeHandler(countWake);
    b.setWakeHandler(countWake);
    var in_a: Counter = .{};
    var in_b: Counter = .{};
    const inbox_a = try a.createInbox(scope_a, a.on(Counter, &in_a, Counter.run));
    _ = try b.createInbox(scope_b, b.on(Counter, &in_b, Counter.run));
    frame(a);
    frame(b);

    const thread = try std.Thread.spawn(.{}, struct {
        fn run(target: Inbox) void {
            target.notify();
        }
    }.run, .{inbox_a});
    thread.join();
    try testing.expectEqual(@as(u32, 1), wakes.load(.monotonic));
    try testing.expect(a.wantsFrame());
    try testing.expect(!b.inboxPending());
    try testing.expect(!b.wantsFrame());
    // A host that renders both anyway (forced frames): only A's callback runs.
    frame(a);
    frame(b);
    try testing.expectEqual(@as(usize, 1), in_a.calls);
    try testing.expectEqual(@as(usize, 0), in_b.calls);
}

test "Inbox: notify after its scope is disposed (racing threads) does nothing" {
    const cx = try Cx.init(testing.allocator, testing.io);
    defer cx.deinit();
    cx.root = try box(cx, .{ .width = .{ .px = 40 }, .height = .{ .px = 40 } }, .{});
    wakes.store(0, .monotonic);
    cx.setWakeHandler(countWake);
    const open_before = slots.openSlotCount();
    const Producer = struct {
        target: std.atomic.Value(Inbox) = .init(.none),
        stop: std.atomic.Value(bool) = .init(false),
        notified: std.atomic.Value(u64) = .init(0),
        fn run(self: *@This()) void {
            while (!self.stop.load(.acquire)) {
                self.target.load(.acquire).notify();
                _ = self.notified.fetchAdd(1, .monotonic);
            }
        }
    };
    var producer: Producer = .{};
    var threads: [2]std.Thread = undefined;
    for (&threads) |*t| t.* = try std.Thread.spawn(.{}, Producer.run, .{&producer});
    // The callback context lives in the scope: it is freed when the scope goes.
    const Ctx = struct {
        calls: *usize,
        fn run(self: *@This()) void {
            self.calls.* += 1;
        }
    };
    var calls: usize = 0;
    for (0..300) |_| {
        const scope = try Scope.init(testing.allocator, null, cx.owner);
        const ctx = try scope.createState(Ctx, .{ .calls = &calls });
        const inbox = try cx.createInbox(scope, cx.on(Ctx, ctx, Ctx.run));
        producer.target.store(inbox, .release);
        scope.dispose(); // the producers keep notifying the dead handle
        try testing.expect(!inbox.isOpen());
        frame(cx);
    }
    producer.stop.store(true, .release);
    for (threads) |t| t.join();
    try testing.expect(producer.notified.load(.monotonic) > 0);
    // Deliveries happened only while a scope was alive; none after its disposal, none leaked.
    const delivered = cx.inbox_hub.delivered;
    frame(cx);
    try testing.expectEqual(delivered, cx.inbox_hub.delivered);
    try testing.expectEqual(@as(usize, 0), cx.inbox_hub.entries.items.len);
    // Only the window slot remains open.
    try testing.expectEqual(open_before + 1, slots.openSlotCount());
}

test "Inbox: a window destroyed before the inbox's scope closes it; the scope cleans up later" {
    const cx = try Cx.init(testing.allocator, testing.io);
    const scope = try Scope.init(testing.allocator, null, cx.owner);
    // Cx.deinit disposes its root scope after the window's lifetime token is dead.
    cx.root_scope = scope;
    var counter: Counter = .{};
    const inbox = try cx.createInbox(scope, cx.on(Counter, &counter, Counter.run));
    const open_before = slots.openSlotCount();
    cx.deinit();
    try testing.expect(!inbox.isOpen());
    inbox.notify(); // nothing to wake, nothing to touch
    try testing.expectEqual(open_before - 2, slots.openSlotCount());
}

test "Inbox: the hit-test refresh path does not deliver; the next layout does" {
    const cx = try Cx.init(testing.allocator, testing.io);
    defer cx.deinit();
    const scope = try Scope.init(testing.allocator, null, cx.owner);
    defer scope.dispose();
    cx.root = try box(cx, .{ .width = .{ .px = 40 }, .height = .{ .px = 40 } }, .{});
    frame(cx);
    var counter: Counter = .{};
    const inbox = try cx.createInbox(scope, cx.on(Counter, &counter, Counter.run));
    inbox.notify();
    cx.root.?.markLayoutDirty();
    cx_render.forceTickAndRebuildForHitTest(cx);
    _ = cx.hitTestQuery(.{ .kind = .pointer, .world_x = 5, .world_y = 5 });
    // Layout and render outside the host's frame phase (a harness command, a test) do not
    // deliver either.
    cx.layout();
    _ = cx.render();
    try testing.expectEqual(@as(usize, 0), counter.calls);
    try testing.expect(cx.inboxPending());
    frame(cx);
    try testing.expectEqual(@as(usize, 1), counter.calls);
}

test "Inbox: callbacks run on the window's event clock; their writes make the frame active" {
    const cx = try Cx.init(testing.allocator, testing.io);
    defer cx.deinit();
    const scope = try Scope.init(testing.allocator, null, cx.owner);
    defer scope.dispose();
    const child = try box(cx, .{ .width = .{ .px = 10 }, .height = .{ .px = 10 }, .flex_shrink = 0 }, .{});
    cx.root = try box(cx, .{ .width = .{ .px = 40 }, .height = .{ .px = 40 } }, .{child});
    try cx.setTestFrameStep(16);
    frame(cx);
    frame(cx);
    const idle_time = cx.frame_time_ms;
    const Probe = struct {
        child: *Node,
        seen_ms: f64 = -1,
        fn run(self: *@This()) void {
            self.seen_ms = core.render_engine.current_frame_time_ms;
            self.child.setWidth(20);
        }
    };
    var probe: Probe = .{ .child = child };
    const inbox = try cx.createInbox(scope, cx.on(Probe, &probe, Probe.run));
    // Another window's clock is bound (multi-window): the callback must see this one's.
    core.render_engine.setFrameClock(.{ .io = testing.io, .time_ms = 123_456, .dt_ms = 0, .dt_seconds = 0 });
    inbox.notify();
    try testing.expectEqual(@as(usize, 1), cx.deliverInboxes());
    // Fixed-step clock: this window's event time is its frame time.
    try testing.expectEqual(idle_time, probe.seen_ms);
    // The outer clock is restored after the pass.
    try testing.expectEqual(@as(f64, 123_456), core.render_engine.current_frame_time_ms);
    cx.advanceFrameClock();
    cx.layout();
    _ = cx.render();
    // The callback dirtied the tree, so the frame advanced the clock and laid it out.
    try testing.expect(cx.frame_time_ms > idle_time);
    try testing.expectApproxEqAbs(@as(f32, 20), child.rectFromWorldOrFallback().w, 0.001);
}

test "Inbox: a notify after the frame's delivery waits for the next frame" {
    const cx = try Cx.init(testing.allocator, testing.io);
    defer cx.deinit();
    const scope = try Scope.init(testing.allocator, null, cx.owner);
    defer scope.dispose();
    cx.root = try box(cx, .{ .width = .{ .px = 40 }, .height = .{ .px = 40 } }, .{});
    frame(cx);
    var counter: Counter = .{};
    const inbox = try cx.createInbox(scope, cx.on(Counter, &counter, Counter.run));
    _ = cx.deliverInboxes();
    cx.advanceFrameClock();
    inbox.notify(); // between the clock and the layout: not delivered on that clock
    cx.layout();
    _ = cx.render();
    try testing.expectEqual(@as(usize, 0), counter.calls);
    try testing.expect(cx.wantsFrame());
    frame(cx);
    try testing.expectEqual(@as(usize, 1), counter.calls);
    try testing.expect(!cx.wantsFrame());
}

test "Inbox: a window that renders nothing paces deliveries at the display period" {
    const cx = try Cx.init(testing.allocator, testing.io);
    defer cx.deinit();
    const scope = try Scope.init(testing.allocator, null, cx.owner);
    defer scope.dispose();
    var counter: Counter = .{};
    const inbox = try cx.createInbox(scope, cx.on(Counter, &counter, Counter.run));
    try testing.expectEqual(@as(?u64, null), cx.inboxDelayWhileUnrenderedNs());
    inbox.notify();
    try testing.expectEqual(@as(?u64, 0), cx.inboxDelayWhileUnrenderedNs()); // never delivered: due
    try testing.expectEqual(@as(usize, 1), cx.deliverInboxes());
    try testing.expectEqual(@as(?u64, null), cx.inboxDelayWhileUnrenderedNs());
    cx.display_refresh_hz = 1; // a one-second period makes the wait observable
    inbox.notify();
    const delay = cx.inboxDelayWhileUnrenderedNs().?;
    try testing.expect(delay > 0 and delay <= std.time.ns_per_s);
    cx.display_refresh_hz = 1_000_000; // one microsecond: due again
    try std.Io.sleep(testing.io, .fromNanoseconds(10 * std.time.ns_per_us), .awake);
    try testing.expectEqual(@as(?u64, 0), cx.inboxDelayWhileUnrenderedNs());
    try testing.expectEqual(@as(usize, 1), cx.deliverInboxes());
    try testing.expectEqual(@as(usize, 2), counter.calls);
}

test "Inbox: a callback disposing its scope skips that scope's later inboxes; one created in a callback works" {
    const cx = try Cx.init(testing.allocator, testing.io);
    defer cx.deinit();
    const outer = try Scope.init(testing.allocator, null, cx.owner);
    defer outer.dispose();
    const doomed = try outer.childScope();
    const State = struct {
        cx: *Cx,
        doomed: ?*Scope,
        outer: *Scope,
        first: usize = 0,
        second: usize = 0,
        late: usize = 0,
        late_inbox: Inbox = .none,
        fn disposeOwn(self: *@This()) void {
            self.first += 1;
            if (self.doomed) |s| s.dispose(); // deferred until the delivery ends
            self.doomed = null;
            self.late_inbox = self.cx.createInbox(self.outer, self.cx.on(@This(), self, @This().onLate)) catch unreachable;
        }
        fn other(self: *@This()) void {
            self.second += 1;
        }
        fn onLate(self: *@This()) void {
            self.late += 1;
        }
    };
    var state: State = .{ .cx = cx, .doomed = doomed, .outer = outer };
    const a = try cx.createInbox(doomed, cx.on(State, &state, State.disposeOwn));
    const b = try cx.createInbox(doomed, cx.on(State, &state, State.other));
    a.notify();
    b.notify();
    frame(cx);
    try testing.expectEqual(@as(usize, 1), state.first);
    try testing.expectEqual(@as(usize, 0), state.second); // its scope was going away
    try testing.expect(!a.isOpen() and !b.isOpen());
    try testing.expectEqual(@as(usize, 1), cx.inbox_hub.entries.items.len);
    state.late_inbox.notify();
    frame(cx);
    try testing.expectEqual(@as(usize, 1), state.late);
}

test "Inbox: createInbox under allocation failure registers nothing" {
    var saw_failure = false;
    var saw_success = false;
    var fail_index: usize = 1; // index 0 is the scope itself
    while (fail_index < 12) : (fail_index += 1) {
        const cx = try Cx.init(testing.allocator, testing.io);
        defer cx.deinit();
        var failing = testing.FailingAllocator.init(testing.allocator, .{ .fail_index = fail_index });
        const scope = try Scope.init(failing.allocator(), null, cx.owner);
        defer scope.dispose();
        // The entry list (Cx allocator), the closer and its scope registration (scope allocator)
        // fail one at a time.
        const saved = cx.allocator;
        cx.allocator = failing.allocator();
        var counter: Counter = .{};
        const open_before = slots.openSlotCount();
        const result = cx.createInbox(scope, cx.on(Counter, &counter, Counter.run));
        cx.allocator = saved;
        const window_opened: u32 = if (cx.inbox_hub.window != 0) 1 else 0;
        if (result) |inbox| {
            saw_success = true;
            try testing.expect(inbox.isOpen());
            try testing.expectEqual(@as(usize, 1), cx.inbox_hub.entries.items.len);
            try testing.expectEqual(open_before + window_opened + 1, slots.openSlotCount());
        } else |err| {
            saw_failure = true;
            try testing.expectEqual(error.OutOfMemory, err);
            try testing.expectEqual(@as(usize, 0), cx.inbox_hub.entries.items.len);
            try testing.expectEqual(open_before + window_opened, slots.openSlotCount());
        }
    }
    try testing.expect(saw_failure and saw_success);
}
