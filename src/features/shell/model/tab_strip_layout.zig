//! Tab-strip arithmetic (design-r3 稿 3 “宽度与溢出”). Callers supply shaped title advances,
//! never UTF-8 byte counts.
//!
//! Tabs take their content width (88–200; session-group tabs 160–240). When the natural widths do
//! not fit, every tab shrinks toward its minimum; when even the minimums do not fit, the tabs that
//! were used least recently (never the active one) go into the “⌄ n” overflow menu, and the rest
//! share the space that is left after the overflow control. There is no horizontal scrolling.
const std = @import("std");

pub const Mode = enum { normal, compressed, overflow };
pub const Result = struct {
    mode: Mode,
    /// Width of the visible tab cells (the strip without the overflow control).
    content: f32,
    /// Tabs in the overflow menu.
    hidden: usize,
};
pub const minimum: f32 = 88;
pub const maximum: f32 = 200;
/// 稿 3 group tab (“组 · 组名 (n)”): its own width range, so the member count stays visible.
pub const group_minimum: f32 = 160;
pub const group_maximum: f32 = 240;
/// Island B v3 tab: title + 60 (padding 10/4, icon 14, close 16, gaps 6, outer 2+2).
pub const chrome: f32 = 60;
/// Pencil hvc0K: tab cells abut; ZW4 / Tab's own 2+2 outer padding spaces the surfaces.
pub const gap: f32 = 0;
/// Room the “⌄ n” overflow control takes after the visible tabs (native ghost sm Button with a
/// chevron and a one- or two-digit count, plus the 4 before it).
pub const overflow_reserve: f32 = 56;

fn minOf(grouped: bool) f32 {
    return if (grouped) group_minimum else minimum;
}

/// Natural (uncompressed) width of one tab cell.
pub fn naturalWidth(advance: f32, grouped: bool) f32 {
    return if (grouped) std.math.clamp(advance + chrome, group_minimum, group_maximum) else std.math.clamp(advance + chrome, minimum, maximum);
}

pub const Input = struct {
    /// Space the tab strip may take (the workspace chrome's budget).
    available: f32,
    advances: []const f32,
    /// `grouped[i]` marks a session-group tab.
    grouped: []const bool,
    /// Visible index of the active tab: it is never hidden.
    active: ?usize = null,
    /// Recency rank per tab: 0 = most recently used; larger = older. Ties keep strip order
    /// (the later tab is hidden first).
    rank: []const usize,
};

/// Fills `widths` (0 for a hidden tab) and `shown` (false = in the overflow menu).
pub fn plan(input: Input, widths: []f32, shown: []bool) !Result {
    const count = input.advances.len;
    if (!std.math.isFinite(input.available) or input.available < 0) return error.InvalidGeometry;
    if (widths.len != count or shown.len != count or input.grouped.len != count or input.rank.len != count) return error.InvalidOutput;
    var natural: f32 = 0;
    var min_total: f32 = 0;
    for (input.advances, widths, shown, input.grouped) |advance, *width, *visible, grouped| {
        if (!std.math.isFinite(advance) or advance < 0) return error.InvalidGeometry;
        width.* = naturalWidth(advance, grouped);
        visible.* = true;
        natural += width.*;
        min_total += minOf(grouped);
    }
    if (natural <= input.available) return .{ .mode = .normal, .content = natural, .hidden = 0 };
    if (min_total <= input.available) {
        shrink(input, widths, shown, input.available, natural, min_total);
        return .{ .mode = .compressed, .content = input.available, .hidden = 0 };
    }
    // Overflow: hide the least recently used inactive tabs until the rest fit at their minimum.
    const budget = @max(0, input.available - overflow_reserve);
    var hidden: usize = 0;
    while (min_total > budget) {
        var victim: ?usize = null;
        for (input.rank, 0..) |rank, i| {
            if (!shown[i] or (input.active != null and input.active.? == i)) continue;
            if (victim == null or rank >= input.rank[victim.?]) victim = i;
        }
        const at = victim orelse break;
        shown[at] = false;
        natural -= widths[at];
        min_total -= minOf(input.grouped[at]);
        widths[at] = 0;
        hidden += 1;
    }
    if (natural <= budget) return .{ .mode = .overflow, .content = natural, .hidden = hidden };
    // The active tab alone may still be wider than the budget: it keeps its minimum.
    const space = @max(budget, min_total);
    shrink(input, widths, shown, space, natural, min_total);
    return .{ .mode = .overflow, .content = space, .hidden = hidden };
}

fn shrink(input: Input, widths: []f32, shown: []const bool, space: f32, natural: f32, min_total: f32) void {
    const remaining = space - min_total;
    const flexibility = natural - min_total;
    for (widths, shown, input.grouped) |*width, visible, grouped| {
        if (!visible) continue;
        const low = minOf(grouped);
        width.* = if (flexibility <= 0) low else low + (width.* - low) * remaining / flexibility;
    }
}

fn identityRanks(comptime n: usize) [n]usize {
    var ranks: [n]usize = undefined;
    for (&ranks, 0..) |*rank, i| rank.* = i;
    return ranks;
}

test "tabs take their content width between 88 and 200" {
    var widths: [4]f32 = undefined;
    var shown: [4]bool = undefined;
    const result = try plan(.{ .available = 1152, .advances = &.{ 72, 84, 10, 400 }, .grouped = &.{ false, false, false, false }, .rank = &identityRanks(4) }, &widths, &shown);
    try std.testing.expectEqual(Mode.normal, result.mode);
    // Island B v3 tab chrome is 60pt (padding 10/4, icon 14, close 16, gaps 6, outer 2+2).
    try std.testing.expectEqualSlices(f32, &.{ 132, 144, 88, 200 }, &widths);
    try std.testing.expectEqual(@as(usize, 0), result.hidden);
}

test "compression shares the space and never goes below 88" {
    var widths: [5]f32 = undefined;
    var shown: [5]bool = undefined;
    const result = try plan(.{ .available = 572, .advances = &.{ 124, 104, 84, 64, 44 }, .grouped = &.{ false, false, false, false, false }, .rank = &identityRanks(5) }, &widths, &shown);
    try std.testing.expectEqual(Mode.compressed, result.mode);
    var sum: f32 = 0;
    for (widths) |width| {
        try std.testing.expect(width >= minimum);
        sum += width;
    }
    try std.testing.expectApproxEqAbs(@as(f32, 572), sum, 0.001);
}

test "overflow hides the least recently used inactive tabs; the active tab stays" {
    var widths: [6]f32 = undefined;
    var shown: [6]bool = undefined;
    // Ranks: tab 0 is the oldest, tab 5 the most recent; tab 0 is active.
    const ranks = [_]usize{ 5, 4, 3, 2, 1, 0 };
    const result = try plan(.{ .available = 360, .advances = &.{ 40, 40, 40, 40, 40, 40 }, .grouped = &.{ false, false, false, false, false, false }, .active = 0, .rank = &ranks }, &widths, &shown);
    try std.testing.expectEqual(Mode.overflow, result.mode);
    // 360 - 56 = 304 → three 100-wide tabs fit at their minimum of 88; 100 × 3 = 300 fits naturally.
    try std.testing.expectEqual(@as(usize, 3), result.hidden);
    try std.testing.expectEqualSlices(bool, &.{ true, false, false, false, true, true }, &shown);
    try std.testing.expectEqual(@as(f32, 0), widths[1]);
    try std.testing.expectEqual(@as(f32, 300), result.content);
}

test "overflow shrinks the remaining tabs into the space left by the overflow control" {
    var widths: [4]f32 = undefined;
    var shown: [4]bool = undefined;
    const result = try plan(.{ .available = 300, .advances = &.{ 140, 140, 140, 140 }, .grouped = &.{ false, false, false, false }, .active = 3, .rank = &.{ 0, 1, 2, 3 } }, &widths, &shown);
    try std.testing.expectEqual(Mode.overflow, result.mode);
    // 244 budget: two tabs at their minimum (176) fit, a third (264) does not; tabs 2 then 1 go.
    try std.testing.expectEqualSlices(bool, &.{ true, false, false, true }, &shown);
    try std.testing.expectApproxEqAbs(@as(f32, 244), widths[0] + widths[3], 0.001);
    try std.testing.expect(widths[0] >= minimum and widths[3] >= minimum);
}

test "a narrow window keeps the active tab at its minimum width" {
    var widths: [3]f32 = undefined;
    var shown: [3]bool = undefined;
    const result = try plan(.{ .available = 96, .advances = &.{ 90, 90, 90 }, .grouped = &.{ false, false, false }, .active = 1, .rank = &.{ 1, 0, 2 } }, &widths, &shown);
    try std.testing.expectEqual(@as(usize, 2), result.hidden);
    try std.testing.expectEqualSlices(bool, &.{ false, true, false }, &shown);
    try std.testing.expectEqual(minimum, widths[1]);
}

test "group tabs keep 160-240 and never compress below 160" {
    var widths: [3]f32 = undefined;
    var shown: [3]bool = undefined;
    const kinds = [_]bool{ false, true, false };
    const wide = try plan(.{ .available = 1000, .advances = &.{ 20, 20, 300 }, .grouped = &kinds, .rank = &identityRanks(3) }, &widths, &shown);
    try std.testing.expectEqual(Mode.normal, wide.mode);
    try std.testing.expectEqualSlices(f32, &.{ 88, 160, 200 }, &widths);
    _ = try plan(.{ .available = 1000, .advances = &.{ 40, 400, 40 }, .grouped = &kinds, .rank = &identityRanks(3) }, &widths, &shown);
    try std.testing.expectEqual(@as(f32, 240), widths[1]);
    const tight = try plan(.{ .available = 400, .advances = &.{ 140, 400, 140 }, .grouped = &kinds, .rank = &identityRanks(3) }, &widths, &shown);
    try std.testing.expectEqual(Mode.compressed, tight.mode);
    try std.testing.expect(widths[1] >= group_minimum and widths[0] >= minimum);
}
