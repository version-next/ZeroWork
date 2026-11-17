//! Display groups follow timeline prose boundaries, never provider rounds.
const std = @import("std");
const turns = @import("conversation_turn.zig");
const events = @import("step_events.zig");

/// Stable ownership keeps disclosure state alive through streaming rebuilds,
/// history moves, and disposal of a view after a provider retry.
pub const State = struct {
    allocator: std.mem.Allocator,
    references: usize = 1,
    first: usize,
    expanded: bool,
    pub fn create(a: std.mem.Allocator, first: usize, expanded: bool) !*State {
        const self = try a.create(State);
        self.* = .{ .allocator = a, .first = first, .expanded = expanded };
        return self;
    }
    pub fn retain(self: *State) void {
        self.references += 1;
    }
    pub fn release(self: *State) void {
        self.references -= 1;
        if (self.references == 0) self.allocator.destroy(self);
    }
};

pub fn boundary(item: turns.TimelineItem) bool {
    // Independent host notices must remain visible in chronological position.
    return switch (item) {
        .message => |segment| std.mem.trim(u8, segment.text.items, " \t\r\n").len != 0,
        .notice, .input => true,
        else => false,
    };
}
pub fn rangeEnd(turn: *const turns.Turn, first: usize) usize {
    var end = first;
    while (end < turn.timeline.items.len and !boundary(turn.timeline.items[end])) : (end += 1) {}
    return end;
}
pub fn toolVisible(step: events.Step) bool {
    // Only pending confirmation controls need an always-accessible surface.
    // Every settled outcome belongs to the same consecutive step group.
    return step.phase != .assembling and step.phase != .approval;
}
pub const Summary = struct {
    count: usize = 0,
    latest: ?turns.TimelineItem = null,
    elapsed_ms: u64 = 0,
    phase: events.Phase = .succeeded,
    live: bool = false,
    thinking_projection: ?[]const u8 = null,
    /// 失败与被拒绝分开统计（用户主动拒绝不算失败）。
    failed: usize = 0,
    rejected: usize = 0,
};

/// 步骤组的状态文案：失败、被拒绝分开写；两者都有时并列。
pub fn statusLabel(buffer: []u8, phase: events.Phase, failed: usize, rejected: usize) ?[]const u8 {
    if (failed > 0 and rejected > 0) return std.fmt.bufPrint(buffer, "{d} 个步骤失败 · {d} 个被拒绝", .{ failed, rejected }) catch "有步骤失败";
    return switch (phase) {
        .failed => "有步骤失败",
        .rejected => "有步骤被拒绝",
        .cancelled => "有步骤取消",
        else => null,
    };
}
/// Shared with the thinking card: project the latest line of the streamed
/// content. Completed thinking never overrides the group's normal summary.
pub fn thinkingProjection(text: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, text, " \t\r\n");
    return if (std.mem.lastIndexOfScalar(u8, trimmed, '\n')) |offset| trimmed[offset + 1 ..] else trimmed;
}
pub fn summarize(turn: *const turns.Turn, first: usize, end: usize, now: u64) Summary {
    var result: Summary = .{};
    for (turn.timeline.items[first..end]) |item| {
        var phase: events.Phase = .succeeded;
        switch (item) {
            .thinking => |segment| {
                result.elapsed_ms +|= (segment.ended_ms orelse now) -| segment.started_ms;
                if (segment.ended_ms == null) {
                    phase = .running;
                    const projection = thinkingProjection(segment.text.items);
                    if (projection.len != 0) result.thinking_projection = projection;
                }
            },
            .tool => |index| {
                const step = turn.steps.items[index];
                if (!toolVisible(step)) continue;
                phase = step.phase;
                result.elapsed_ms +|= step.elapsedAt(now);
            },
            else => continue,
        }
        result.count += 1;
        result.latest = item;
        if (phase == .running or phase == .approved) result.live = true;
        if (phase == .failed) result.failed += 1;
        if (phase == .rejected) result.rejected += 1;
        // A later cancellation or completed step must not hide an earlier failure.
        if (phase == .failed or (phase == .rejected and result.phase != .failed) or (phase == .cancelled and result.phase != .failed and result.phase != .rejected)) result.phase = phase;
    }
    if (result.phase == .succeeded and result.live) result.phase = .running;
    return result;
}
pub fn find(turn: *const turns.Turn, first: usize) ?*State {
    for (turn.step_groups.items) |state| if (state.first == first) return state;
    return null;
}
/// Called for every display event, so a changed setting affects only new groups.
pub fn sync(a: std.mem.Allocator, turn: *turns.Turn, expanded: bool) !void {
    var first: usize = 0;
    while (first < turn.timeline.items.len) {
        if (boundary(turn.timeline.items[first])) {
            first += 1;
            continue;
        }
        const end = rangeEnd(turn, first);
        if (summarize(turn, first, end, 0).count != 0 and find(turn, first) == null) {
            const state = try State.create(a, first, expanded);
            errdefer state.release();
            try turn.step_groups.append(a, state);
        }
        first = end;
    }
}

test "step group status keeps failures and user rejections apart" {
    var buffer: [64]u8 = undefined;
    try std.testing.expectEqualStrings("有步骤被拒绝", statusLabel(&buffer, .rejected, 0, 1).?);
    try std.testing.expectEqualStrings("有步骤失败", statusLabel(&buffer, .failed, 1, 0).?);
    try std.testing.expectEqualStrings("1 个步骤失败 · 2 个被拒绝", statusLabel(&buffer, .failed, 1, 2).?);
    try std.testing.expect(statusLabel(&buffer, .succeeded, 0, 0) == null);
}
