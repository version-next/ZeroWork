//! What the AI service's worker threads publish to the UI (docs/ui-revamp/LIFECYCLE.md §5).
//!
//! A worker (a conversation's runner, its tool / execution bridges, the approval brokers, the
//! execution driver, title / attachment / image / discovery / compaction jobs, the journal's
//! checkpoint writer) writes its result into the structure the UI reads, then publishes. A
//! publication advances one process-wide revision and wakes the window that shows the publisher
//! (`Wake`, bound by the view that displays it; unbound wakes every window: reliable, never
//! silent). The AI host's frame hook compares the revision with the one it last handled and runs
//! its pass only when it moved — nothing polls the workers on frames where nothing was published.
//!
//! Order: write the data, then publish (release); the UI reads the revision (acquire) before it
//! reads the data, so a publication racing with a pass is seen by the next pass, and its wake
//! guarantees that pass comes.
const std = @import("std");
const presentation = @import("../platform/presentation_wakeup.zig");

pub const Target = presentation.Target;

var published: std.atomic.Value(u64) = .init(1);

/// The current revision (any thread). Never 0, so a host that has handled nothing yet (0) runs.
pub fn revision() u64 {
    return published.load(.acquire);
}

/// Where a publisher's results are shown. The view that displays the publisher binds its window;
/// a publisher no view displays wakes every window.
pub const Wake = struct {
    target: std.atomic.Value(Target) = .init(0),

    /// Main thread: the window whose view shows this publisher.
    pub fn bind(self: *Wake, target: Target) void {
        self.target.store(target, .release);
    }
    /// Main thread: the view in `target`'s window no longer shows it (a view that has since bound
    /// another window keeps its binding).
    pub fn unbind(self: *Wake, target: Target) void {
        _ = self.target.cmpxchgStrong(target, 0, .acq_rel, .acquire);
    }
    /// Any thread: the publisher wrote a result the UI must handle.
    pub fn publish(self: *const Wake) void {
        _ = published.fetchAdd(1, .acq_rel);
        presentation.notifyTarget(self.target.load(.acquire));
    }
};

/// Any thread. A publisher without a bound wake (or a shared structure with no single viewer)
/// wakes every window.
pub fn publish(wake: ?*const Wake) void {
    if (wake) |value| return value.publish();
    publishAll();
}

/// Any thread: a change every window that shows AI state must see (the shared conversations'
/// phase, title, listing, ownership — LIFECYCLE.md §5.4).
pub fn publishAll() void {
    _ = published.fetchAdd(1, .acq_rel);
    presentation.notify();
}

test "a publication advances the revision and wakes only the bound window" {
    _ = presentation.take();
    const a = presentation.registerWindow(0xa1a1);
    defer presentation.unregisterWindow(0xa1a1, a);
    const b = presentation.registerWindow(0xa1a2);
    defer presentation.unregisterWindow(0xa1a2, b);
    var wake: Wake = .{};
    wake.bind(b);
    const before = revision();
    wake.publish();
    try std.testing.expect(revision() > before);
    try std.testing.expect(!presentation.take());
    try std.testing.expect(!presentation.takeWindow(0xa1a1));
    try std.testing.expect(presentation.takeWindow(0xa1a2));
    // The view in B goes away: the publisher wakes every window again.
    wake.unbind(b);
    publish(&wake);
    try std.testing.expect(presentation.take());
    // A view in A that bound before B's unbind keeps A.
    wake.bind(a);
    wake.unbind(b);
    wake.publish();
    try std.testing.expect(!presentation.take());
    try std.testing.expect(presentation.takeWindow(0xa1a1));
}

test "publishAll and an unbound publisher wake every window" {
    _ = presentation.take();
    const before = revision();
    publish(null);
    try std.testing.expect(presentation.take());
    publishAll();
    try std.testing.expect(presentation.take());
    try std.testing.expectEqual(before + 2, revision());
}
