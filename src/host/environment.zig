//! The environment the AI's authority is checked against (docs/ui-revamp/LIFECYCLE.md §5.2):
//! which tabs exist and which is current, what each tab shows and whether it is closing, groups and
//! their members, session capabilities and bindings, SSH reconnect state, the agent policy in the
//! configuration, and input leases. Every place that changes one of these publishes here; the AI
//! host's frame hook runs its pass (resource stamps, host-context validation, automation grants,
//! presentation) on the frame after the revision moved instead of on every frame.
//!
//! Publish only on an actual change (a writer that publishes the same value every frame keeps every
//! window rendering). A publication wakes every window: these are process-level facts (groups,
//! sessions, configuration are shared), and changes are user-scale events.
const std = @import("std");
const presentation = @import("../platform/presentation_wakeup.zig");

var published: std.atomic.Value(u64) = .init(1);

/// The current revision (any thread). Never 0, so a host that has handled nothing yet (0) runs.
pub fn revision() u64 {
    return published.load(.acquire);
}

/// Any thread, after the change is written.
pub fn publish() void {
    _ = published.fetchAdd(1, .acq_rel);
    presentation.notify();
}

test "an environment publication advances the revision and wakes every window" {
    _ = presentation.take();
    const before = revision();
    publish();
    try std.testing.expect(revision() > before);
    try std.testing.expect(presentation.take());
}
