//! How a step or a step group shows its state (Pencil Kaf7E A5 / A6, ③ "失败 / 被拒绝"): one status
//! glyph and one tone per phase, failed and rejected kept apart. Pure: views map `Tone` to zenit
//! tokens and `spinner` to a native W.Spinner.
const std = @import("std");
const Phase = @import("../../../../ai/step_events.zig").Phase;

pub const Tone = enum { neutral, accent, success, warning, danger };

pub const Visual = struct {
    /// lucide icon name (ignored while `spinner`).
    icon: []const u8,
    tone: Tone,
    /// A running step shows the native spinner instead of a glyph.
    spinner: bool = false,
};

/// One step: assembling / running / approved spin (accent); waiting for approval is a hand
/// (warning); done is a check (neutral, the row is quiet); failed is a red circle-x; rejected a
/// neutral ban (with a "已拒绝" tag in the row); cancelled a slashed circle; skipped skip-forward.
pub fn step(phase: Phase) Visual {
    return switch (phase) {
        .assembling, .running, .approved => .{ .icon = "loader-circle", .tone = .accent, .spinner = true },
        .approval => .{ .icon = "hand", .tone = .warning },
        .succeeded => .{ .icon = "check", .tone = .neutral },
        .failed => .{ .icon = "circle-x", .tone = .danger },
        .rejected => .{ .icon = "ban", .tone = .neutral },
        .cancelled => .{ .icon = "circle-slash", .tone = .neutral },
        .skipped => .{ .icon = "skip-forward", .tone = .neutral },
    };
}

/// A group: any failure marks it (circle-alert, danger); otherwise any rejection (ban, neutral);
/// otherwise its summary phase. A group of thinking only shows the brain once done.
pub fn group(phase: Phase, failed: usize, rejected: usize, thinking_only: bool) Visual {
    if (failed > 0) return .{ .icon = "circle-alert", .tone = .danger };
    if (rejected > 0) return .{ .icon = "ban", .tone = .neutral };
    const visual = step(phase);
    if (thinking_only and !visual.spinner) return .{ .icon = "brain", .tone = .neutral };
    return visual;
}

/// The group's detail after its title: "· 5 个步骤 · 1 个失败 · 1 个被拒绝", or the latest
/// projection (a single tool's target, a live thought) after the count. Failure counts come before
/// the projection; the detail is red only when something failed.
pub fn groupDetail(allocator: std.mem.Allocator, count: ?usize, failed: usize, rejected: usize, cancelled: bool, projection: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    if (count) |n| try out.print(allocator, "· {d} 个步骤", .{n});
    if (failed > 0) try out.print(allocator, "{s}{d} 个失败", .{ if (out.items.len > 0) " · " else "· ", failed });
    if (rejected > 0) try out.print(allocator, "{s}{d} 个被拒绝", .{ if (out.items.len > 0) " · " else "· ", rejected });
    if (cancelled and failed == 0 and rejected == 0) try out.appendSlice(allocator, if (out.items.len > 0) " · 已取消" else "· 已取消");
    const trimmed = std.mem.trim(u8, projection, " \t\r\n");
    if (trimmed.len > 0 and failed == 0 and rejected == 0) {
        if (out.items.len > 0) try out.appendSlice(allocator, " · ");
        try out.appendSlice(allocator, trimmed);
    }
    return out.toOwnedSlice(allocator);
}

pub fn detailTone(failed: usize) Tone {
    return if (failed > 0) .danger else .neutral;
}

test "every phase has a glyph and tone; failed and rejected differ" {
    for (std.enums.values(Phase)) |phase| {
        const v = step(phase);
        try std.testing.expect(v.icon.len > 0);
    }
    try std.testing.expectEqual(Tone.danger, step(.failed).tone);
    try std.testing.expectEqual(Tone.neutral, step(.rejected).tone);
    try std.testing.expect(!std.mem.eql(u8, step(.failed).icon, step(.rejected).icon));
    try std.testing.expect(step(.running).spinner and step(.assembling).spinner and step(.approved).spinner);
    try std.testing.expect(!step(.succeeded).spinner);
    try std.testing.expectEqual(Tone.warning, step(.approval).tone);
    try std.testing.expectEqualStrings("circle-slash", step(.cancelled).icon);
    try std.testing.expectEqualStrings("skip-forward", step(.skipped).icon);
}

test "a group with a failure is red; a rejection alone is neutral; thinking shows the brain when done" {
    try std.testing.expectEqualStrings("circle-alert", group(.failed, 1, 1, false).icon);
    try std.testing.expectEqual(Tone.danger, group(.failed, 1, 0, false).tone);
    try std.testing.expectEqualStrings("ban", group(.rejected, 0, 1, false).icon);
    try std.testing.expectEqual(Tone.neutral, group(.rejected, 0, 1, false).tone);
    try std.testing.expectEqualStrings("brain", group(.succeeded, 0, 0, true).icon);
    try std.testing.expect(group(.running, 0, 0, true).spinner);
    try std.testing.expectEqualStrings("check", group(.succeeded, 0, 0, false).icon);
}

test "group detail lists the count, failures and rejections apart, else the projection" {
    const a = std.testing.allocator;
    const full = try groupDetail(a, 5, 1, 1, false, "ignored");
    defer a.free(full);
    try std.testing.expectEqualStrings("· 5 个步骤 · 1 个失败 · 1 个被拒绝", full);
    const live = try groupDetail(a, 2, 0, 0, false, "最新判断：需要核对\n");
    defer a.free(live);
    try std.testing.expectEqualStrings("· 2 个步骤 · 最新判断：需要核对", live);
    const single = try groupDetail(a, null, 0, 0, false, "ipmitool sel list");
    defer a.free(single);
    try std.testing.expectEqualStrings("ipmitool sel list", single);
    const rejected = try groupDetail(a, null, 0, 2, false, "");
    defer a.free(rejected);
    try std.testing.expectEqualStrings("· 2 个被拒绝", rejected);
    const cancelled = try groupDetail(a, 3, 0, 0, true, "");
    defer a.free(cancelled);
    try std.testing.expectEqualStrings("· 3 个步骤 · 已取消", cancelled);
    try std.testing.expectEqual(Tone.danger, detailTone(1));
    try std.testing.expectEqual(Tone.neutral, detailTone(0));
}
