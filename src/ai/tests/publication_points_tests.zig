//! Worker → UI publication points (docs/ui-revamp/LIFECYCLE.md §5.3): every write a worker makes for
//! the UI advances the publication revision and wakes the window its owner bound.
const std = @import("std");
const publication = @import("../publication.zig");
const presentation = @import("../../platform/presentation_wakeup.zig");

const Window = struct {
    context: usize,
    target: presentation.Target,
    wake: publication.Wake = .{},
    fn open(context: usize) Window {
        _ = presentation.take();
        var self: Window = .{ .context = context, .target = presentation.registerWindow(context) };
        self.wake.bind(self.target);
        return self;
    }
    fn close(self: *Window) void {
        presentation.unregisterWindow(self.context, self.target);
    }
    /// The write published, and woke this window only.
    fn expectPublished(self: *Window, before: u64) !void {
        try std.testing.expect(publication.revision() > before);
        try std.testing.expect(!presentation.take());
        try std.testing.expect(presentation.takeWindow(self.context));
    }
};

test "stream, thinking, reset, step and context-usage mailboxes publish every write" {
    var window = Window.open(0xb5e2);
    defer window.close();
    var stream = @import("../stream_mailbox.zig").Mailbox.init(std.testing.allocator);
    defer stream.deinit();
    stream.wake = &window.wake;
    var before = publication.revision();
    try stream.append("delta");
    try window.expectPublished(before);
    before = publication.revision();
    try stream.appendThinking("thinking");
    try window.expectPublished(before);
    before = publication.revision();
    stream.reset();
    try window.expectPublished(before);
    var steps = @import("../step_events.zig").Mailbox.init(std.testing.allocator);
    defer steps.deinit();
    steps.wake = &window.wake;
    before = publication.revision();
    try steps.push(.{ .kind = .step, .call_id = "c1", .name = "run", .command = "ls", .detail = "", .phase = .running, .at_ms = 1 });
    try window.expectPublished(before);
    var usage: @import("../live_context_usage.zig").Mailbox = .{ .wake = &window.wake };
    usage.reset(7);
    before = publication.revision();
    usage.publish(7, std.mem.zeroes(@import("../live_context_usage.zig").Snapshot));
    try window.expectPublished(before);
    // A stale turn's value is not stored and not published.
    before = publication.revision();
    usage.publish(6, std.mem.zeroes(@import("../live_context_usage.zig").Snapshot));
    try std.testing.expectEqual(before, publication.revision());
}
