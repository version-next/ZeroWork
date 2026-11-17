//! When the AI host's frame hook runs its pass (docs/ui-revamp/LIFECYCLE.md §5.1).
//!
//! The hook reads a handful of facts each frame (O(1)): the AI service's publication revision, the
//! environment revision, whether the window's theme was published, the configuration revision, the
//! earliest deadline a step asked for, whether the floating card is in flight or changed phase, a
//! fingerprint of the rectangles the pass lays out against, the focused node and whether the window
//! is active. The pass runs when any of them differs from what the last pass saw (or a deadline is
//! due); within the frame it ran in, it runs again in every later layout round (a step that changed
//! the tree asked for another layout). Otherwise the frame does no AI work.
const std = @import("std");

pub const Facts = struct {
    publication: u64,
    environment: u64,
    config: u64 = 0,
    theme: bool = false,
    now_ns: i128,
    /// The card is expanding / collapsing (an animation: its frames drive presentation and the
    /// launcher), or its phase differs from the one the last pass saw.
    card_phase: u8 = 0,
    card_flying: bool = false,
    layout: u64 = 0,
    focus: usize = 0,
    window_active: bool = true,
};

pub const Reason = enum(u8) { first, rerun, publication, environment, config, theme, deadline, card, layout, focus, window };
pub const reason_count = @typeInfo(Reason).@"enum".field_names.len;
comptime {
    // The budget diagnostic counts passes per reason under these names (shared/ui cannot import features).
    const names = @import("../../../shared/ui/surface/lifecycle_budget.zig").ai_pass_reason_names;
    std.debug.assert(names.len == reason_count);
    for (@typeInfo(Reason).@"enum".field_names, 0..) |name, at| std.debug.assert(std.mem.eql(u8, name, names[at]));
}

pub const Gate = struct {
    seen: ?Facts = null,
    deadline_ns: ?i128 = null,
    /// The frame whose pass is running (its later layout rounds run it too).
    pass_frame: ?u64 = null,
    /// The last pass asked for a frame (a step changed what an earlier step reads, a view it
    /// updated wants repainting): the next frame runs the pass again, as the old every-frame loop did.
    rerun: bool = false,

    /// Why a pass is due now, null when nothing changed.
    pub fn due(self: *const Gate, facts: Facts) ?Reason {
        const seen = self.seen orelse return .first;
        if (self.rerun) return .rerun;
        if (facts.publication != seen.publication) return .publication;
        if (facts.environment != seen.environment) return .environment;
        if (facts.theme) return .theme;
        if (facts.config != seen.config) return .config;
        if (self.deadline_ns) |at| if (facts.now_ns >= at) return .deadline;
        if (facts.card_flying or facts.card_phase != seen.card_phase) return .card;
        if (facts.layout != seen.layout) return .layout;
        if (facts.focus != seen.focus) return .focus;
        if (facts.window_active != seen.window_active) return .window;
        return null;
    }

    /// A pass starts with these facts (read before any step runs: what is published while it
    /// runs is seen by the next pass). A due deadline is consumed; steps ask again if they must.
    pub fn begin(self: *Gate, facts: Facts, frame: u64) void {
        self.seen = facts;
        self.rerun = false;
        if (self.deadline_ns) |at| if (facts.now_ns >= at) {
            self.deadline_ns = null;
        };
        self.pass_frame = frame;
    }

    /// Whether this frame's pass already started (a later layout round of the same frame).
    pub fn running(self: *const Gate, frame: u64) bool {
        return self.pass_frame == frame;
    }

    /// A step needs a pass again at `at_ns` (monotonic); the earliest request wins.
    pub fn wakeAt(self: *Gate, at_ns: i128) void {
        self.deadline_ns = if (self.deadline_ns) |current| @min(current, at_ns) else at_ns;
    }

    /// Nanoseconds until the earliest deadline (0 when due), null when none is set.
    pub fn untilDeadline(self: *const Gate, now_ns: i128) ?u64 {
        const at = self.deadline_ns orelse return null;
        return @intCast(@max(0, at - now_ns));
    }
};

test "the first frame passes; then only a changed input opens the gate" {
    var gate: Gate = .{};
    var facts: Facts = .{ .publication = 5, .environment = 9, .config = 3, .now_ns = 1000, .layout = 77, .focus = 1 };
    try std.testing.expectEqual(Reason.first, gate.due(facts).?);
    gate.begin(facts, 1);
    try std.testing.expect(gate.running(1));
    try std.testing.expect(!gate.running(2));
    // Nothing changed: no pass, however many frames come.
    for (0..100) |i| {
        facts.now_ns += 16_000_000;
        _ = i;
        try std.testing.expectEqual(@as(?Reason, null), gate.due(facts));
    }
    const cases = [_]struct { reason: Reason, apply: *const fn (*Facts) void }{
        .{ .reason = .publication, .apply = struct {
            fn f(x: *Facts) void {
                x.publication += 1;
            }
        }.f },
        .{ .reason = .environment, .apply = struct {
            fn f(x: *Facts) void {
                x.environment += 1;
            }
        }.f },
        .{ .reason = .config, .apply = struct {
            fn f(x: *Facts) void {
                x.config += 1;
            }
        }.f },
        .{ .reason = .theme, .apply = struct {
            fn f(x: *Facts) void {
                x.theme = true;
            }
        }.f },
        .{ .reason = .card, .apply = struct {
            fn f(x: *Facts) void {
                x.card_phase +%= 1;
            }
        }.f },
        .{ .reason = .card, .apply = struct {
            fn f(x: *Facts) void {
                x.card_flying = true;
            }
        }.f },
        .{ .reason = .layout, .apply = struct {
            fn f(x: *Facts) void {
                x.layout +%= 1;
            }
        }.f },
        .{ .reason = .focus, .apply = struct {
            fn f(x: *Facts) void {
                x.focus +%= 1;
            }
        }.f },
        .{ .reason = .window, .apply = struct {
            fn f(x: *Facts) void {
                x.window_active = !x.window_active;
            }
        }.f },
    };
    var frame: u64 = 2;
    for (cases) |case| {
        var changed = facts;
        case.apply(&changed);
        try std.testing.expectEqual(case.reason, gate.due(changed).?);
        // The pass handles it; the same facts again do not open the gate (a flying card does:
        // its frames are the animation's).
        changed.theme = false;
        gate.begin(changed, frame);
        frame += 1;
        if (!changed.card_flying) try std.testing.expectEqual(@as(?Reason, null), gate.due(changed));
        changed.card_flying = false;
        gate.begin(changed, frame);
        facts = changed;
    }
}

test "a deadline opens the gate once, at its time, and the earliest one wins" {
    var gate: Gate = .{};
    var facts: Facts = .{ .publication = 1, .environment = 1, .now_ns = 0 };
    gate.begin(facts, 1);
    gate.wakeAt(50);
    gate.wakeAt(30);
    gate.wakeAt(90);
    try std.testing.expectEqual(@as(?u64, 30), gate.untilDeadline(0));
    facts.now_ns = 29;
    try std.testing.expectEqual(@as(?Reason, null), gate.due(facts));
    facts.now_ns = 30;
    try std.testing.expectEqual(Reason.deadline, gate.due(facts).?);
    gate.begin(facts, 2);
    try std.testing.expectEqual(@as(?i128, null), gate.deadline_ns);
    facts.now_ns = 1000;
    try std.testing.expectEqual(@as(?Reason, null), gate.due(facts));
}

test "a pass that asked for a frame runs again on it, once" {
    var gate: Gate = .{};
    const facts: Facts = .{ .publication = 1, .environment = 1, .now_ns = 0 };
    gate.begin(facts, 1);
    try std.testing.expectEqual(@as(?Reason, null), gate.due(facts));
    gate.rerun = true;
    try std.testing.expectEqual(Reason.rerun, gate.due(facts).?);
    gate.begin(facts, 2);
    try std.testing.expectEqual(@as(?Reason, null), gate.due(facts));
}
