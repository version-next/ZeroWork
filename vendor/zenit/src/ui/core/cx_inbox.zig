//! Cx side of frame-first delivery: `Cx.createInbox`, the host frame phase `Cx.deliverInboxes`
//! (before `advanceFrameClock`, beside deferred work), the frame-request query and the pacing of
//! deliveries while a window renders nothing (docs/design/append-inbox.md §4.2, §5).
//!
//! The handles and their process-wide slots are in `inbox.zig`. Here: one window slot per Cx
//! (opened with its first inbox), the main-thread list of this window's inboxes with their
//! callbacks and scopes, and the delivery pass.
const std = @import("std");
const Allocator = std.mem.Allocator;
const core = @import("../core.zig");
const Cx = core.Cx;
const Scope = core.Scope;
const HandlerRef = core.HandlerRef;
const render_engine = core.render_engine;
const slots = @import("inbox.zig");

pub const Inbox = slots.Inbox;
pub const WakeFn = slots.WakeFn;

pub const Entry = struct {
    inbox: u64,
    scope: *Scope,
    handler: HandlerRef,
};

/// Per-Cx state (`Cx.inbox_hub`). Main thread only.
pub const Hub = struct {
    /// Window slot; 0 until the first inbox.
    window: u64 = 0,
    wake: ?WakeFn = null,
    entries: std.ArrayListUnmanaged(Entry) = .empty,
    /// Next entry of the running delivery; removal before it moves it back.
    cursor: ?usize = null,
    delivering: bool = false,
    /// Callbacks run (diagnostics, tests).
    delivered: u64 = 0,
    /// Monotonic time of the last delivery pass that found the window pending.
    last_delivery_ns: ?i128 = null,
};

pub fn setWakeHandler(cx: *Cx, wake: ?WakeFn) void {
    cx.inbox_hub.wake = wake;
    if (cx.inbox_hub.window != 0) slots.setWake(cx.inbox_hub.window, wake);
}

/// Some inbox of this window was notified and has not been delivered.
pub fn pending(cx: *const Cx) bool {
    const window = cx.inbox_hub.window;
    return window != 0 and slots.pending(window);
}

/// Scope resource: closes the inbox when its scope is disposed. Safe after the Cx is gone.
const Closer = struct {
    token: *Cx.LifetimeToken,
    cx: *Cx,
    inbox: u64,

    fn destroy(raw: *anyopaque, allocator: Allocator) void {
        const self: *Closer = @ptrCast(@alignCast(raw));
        slots.close(self.inbox);
        if (self.token.isAlive()) removeEntry(self.cx, self.inbox);
        self.token.release();
        allocator.destroy(self);
    }
};

pub fn createInbox(cx: *Cx, scope: *Scope, on_notify: HandlerRef) (Allocator.Error || slots.Error)!Inbox {
    cx.owner.assertThread();
    std.debug.assert(scope.owner == cx.owner);
    const hub = &cx.inbox_hub;
    if (hub.window == 0) hub.window = try slots.open(0, hub.wake);
    try hub.entries.ensureUnusedCapacity(cx.allocator, 1);
    const closer = try scope.allocator.create(Closer);
    const raw = slots.open(hub.window, null) catch |err| {
        scope.allocator.destroy(closer);
        return err;
    };
    closer.* = .{ .token = cx.retainLifetimeToken(), .cx = cx, .inbox = raw };
    hub.entries.appendAssumeCapacity(.{ .inbox = raw, .scope = scope, .handler = on_notify });
    // On failure adoptResource runs destroy: the slot is closed and the entry removed.
    try scope.adoptResource(closer, Closer.destroy);
    return @fromBackingInt(@intCast(raw));
}

fn removeEntry(cx: *Cx, raw: u64) void {
    const hub = &cx.inbox_hub;
    for (hub.entries.items, 0..) |entry, index| {
        if (entry.inbox != raw) continue;
        _ = hub.entries.orderedRemove(index);
        if (hub.cursor) |*next| {
            if (index < next.*) next.* -= 1;
        }
        return;
    }
}

/// Frame-first delivery: the host's frame phase before `advanceFrameClock` (beside deferred work,
/// never inside a native paint callback). Runs every notified inbox's callback in registration
/// order, as a host entry: this window's event clock, a reactive-callback guard and one owner
/// batch, so effects of the writes have run before the frame's layout. Scopes disposed by a
/// callback are released after the pass, and their inboxes later in the pass are skipped.
/// Returns the callbacks run.
pub fn deliver(cx: *Cx) usize {
    const hub = &cx.inbox_hub;
    if (hub.window == 0 or hub.delivering) return 0;
    // Window first, then each inbox, every mark a read-modify-write (inbox.zig `markPending`):
    // a notify racing this pass is either taken below or leaves the window pending.
    if (!slots.take(hub.window)) return 0;
    hub.last_delivery_ns = @import("zenit_time").monotonicTimestamp(cx.io);
    hub.delivering = true;
    defer hub.delivering = false;
    cx.beginActiveUse();
    defer cx.endActiveUse();
    const outer_clock = render_engine.saveFrameClock();
    defer render_engine.restoreFrameClock(outer_clock);
    cx.bindEventClock();
    const owner = cx.owner;
    owner.beginReactiveCallback();
    defer owner.endReactiveCallback();
    owner.beginBatch();
    defer owner.endBatch();
    hub.cursor = 0;
    defer hub.cursor = null;
    var ran: usize = 0;
    while (hub.cursor.? < hub.entries.items.len) {
        const entry = hub.entries.items[hub.cursor.?];
        hub.cursor.? += 1;
        // Taken before the call: a notify during (or after) it is delivered next time.
        if (!slots.take(entry.inbox)) continue;
        if (entry.scope.willBeDisposedAfterReactiveCallback()) continue;
        ran += 1;
        entry.handler.invoke();
    }
    hub.delivered +%= ran;
    return ran;
}

/// A window that renders no frames (occluded, minimized) keeps delivering, at most once per
/// display period, as it keeps firing timers. null: nothing pending; 0: due now; else the delay.
pub fn delayWhileUnrenderedNs(cx: *const Cx) ?u64 {
    if (!pending(cx)) return null;
    const last = cx.inbox_hub.last_delivery_ns orelse return 0;
    const hz: f64 = if (cx.display_refresh_hz > 0) cx.display_refresh_hz else 60;
    const period: i128 = @intFromFloat(@as(f64, std.time.ns_per_s) / hz);
    const elapsed = @import("zenit_time").monotonicTimestamp(cx.io) - last;
    return if (elapsed >= period) 0 else @intCast(period - elapsed);
}

/// `Cx.deinit`, first thing after the lifetime token dies: later notifies do nothing, and the
/// scope resources that close the inboxes afterwards no longer touch this Cx.
pub fn deinit(cx: *Cx) void {
    const hub = &cx.inbox_hub;
    std.debug.assert(!hub.delivering);
    for (hub.entries.items) |entry| slots.close(entry.inbox);
    hub.entries.deinit(cx.allocator);
    if (hub.window != 0) slots.close(hub.window);
    hub.* = .{};
}
