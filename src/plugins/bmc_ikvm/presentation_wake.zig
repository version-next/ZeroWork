//! Where this session's worker publications wake the presentation.
//!
//! The session's threads (protocol worker, image encoder) publish values the owner's main-thread
//! poll reads on the next frame. They wake only the window that shows the session: the renderer
//! binds its window's wake target when it mounts and clears it when it unmounts (a session moved
//! to another window is mounted there by a new renderer, which binds that window). With no
//! renderer bound the target is 0, which wakes every window — reliable, never silent.
const std = @import("std");
const presentation = @import("../../platform/presentation_wakeup.zig");

pub const Target = presentation.Target;

pub const Wake = struct {
    target: std.atomic.Value(Target) = .init(0),

    /// Main thread: the window whose renderer shows this session.
    pub fn bind(self: *Wake, target: Target) void {
        self.target.store(target, .release);
    }
    /// Main thread: the renderer in `target`'s window is gone. A renderer that has since bound
    /// another window (the session moved) keeps its binding.
    pub fn unbind(self: *Wake, target: Target) void {
        _ = self.target.cmpxchgStrong(target, 0, .acq_rel, .acquire);
    }
    /// Any thread: a publication the owner must drain. Edge-triggered and coalesced.
    pub fn notify(self: *const Wake) void {
        presentation.notifyTarget(self.target.load(.acquire));
    }
};

/// Publish through a session's wake when one is attached; a standalone service wakes every window.
pub fn notify(wake: ?*const Wake) void {
    if (wake) |value| value.notify() else presentation.notify();
}

test "BMC presentation wake reaches only the bound window; unbound wakes every window" {
    _ = presentation.take();
    const a = presentation.registerWindow(0xb5b1);
    defer presentation.unregisterWindow(0xb5b1, a);
    const b = presentation.registerWindow(0xb5b2);
    defer presentation.unregisterWindow(0xb5b2, b);
    var wake: Wake = .{};
    // No renderer bound: global.
    wake.notify();
    try std.testing.expect(presentation.take());
    try std.testing.expect(!presentation.takeWindow(0xb5b1) and !presentation.takeWindow(0xb5b2));
    // Bound to window A: A only.
    wake.bind(a);
    notify(&wake);
    try std.testing.expect(!presentation.take());
    try std.testing.expect(presentation.takeWindow(0xb5b1));
    try std.testing.expect(!presentation.takeWindow(0xb5b2));
    // The session moved: its new renderer binds window B.
    wake.bind(b);
    wake.notify();
    try std.testing.expect(!presentation.take());
    try std.testing.expect(!presentation.takeWindow(0xb5b1));
    try std.testing.expect(presentation.takeWindow(0xb5b2));
    // The old window's renderer unmounts after the move: B stays bound.
    wake.unbind(a);
    wake.notify();
    try std.testing.expect(!presentation.take());
    try std.testing.expect(presentation.takeWindow(0xb5b2));
    // Unmounted: back to every window.
    wake.unbind(b);
    wake.notify();
    try std.testing.expect(presentation.take());
    // A standalone service (no session wake) is global too.
    notify(null);
    try std.testing.expect(presentation.take());
}
