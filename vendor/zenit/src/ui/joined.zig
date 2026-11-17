//! Joined outline: several rounded rectangles read as one continuous surface
//! (docs/design/joined-surface.md §4.1).
//!
//! A chain of axis-aligned rectangles touches end to end along one axis (a folder
//! tab on its panel, the rows of a multi-line selection, a dropdown on its trigger).
//! Their union is an orthogonal polygon; every convex vertex is a member's corner
//! and takes that member's corner radius, every concave vertex is a join and takes
//! the chain's join radius. Radii that do not fit shrink proportionally per shared
//! edge, so two arcs sharing a short edge meet as a smooth S and vanish together
//! when the edge does. The outline is a continuous function of the members, so
//! animating the members and solving again every frame morphs the outline without
//! a jump. `solve(chain, d)` with d > 0 gives the concentric outline d inside.
//!
//! Coordinates are screen coordinates (y down). Contours wind clockwise.
const std = @import("std");
const types = @import("core/types.zig");

pub const PathCommand = types.PathCommand;
pub const PathGeometry = types.PathGeometry;
pub const Rect = types.ComputedRect;

/// Members are stacked top to bottom (`vertical`) or left to right (`horizontal`).
pub const Axis = enum { vertical, horizontal };

pub const Member = struct {
    rect: Rect,
    /// Corner radii TL, TR, BR, BL in screen order (the `corner_radii` order). A corner
    /// covered by a neighbour is not used; a corner that sticks out past its neighbour at a
    /// join is.
    radii: [4]f32 = @splat(0),
};

pub const Chain = struct {
    axis: Axis = .vertical,
    members: []const Member,
    /// Base radius of the concave arcs where two members join.
    join_radius: f32 = 0,
};

pub const Vertex = struct {
    x: f32,
    y: f32,
    /// Resolved arc radius (after shrinking).
    radius: f32,
    convex: bool,
};

pub const Contour = struct { start: u32, len: u32 };

/// Spans closer than this are aligned (no vertices); overlaps at most this break the chain.
pub const epsilon: f32 = 1e-3;
/// Cubic Bezier handle length of a quarter circle, as a fraction of the radius.
pub const kappa: f32 = 0.5522847498;

const TL = 0;
const TR = 1;
const BR = 2;
const BL = 3;

pub fn rectEql(a: Rect, b: Rect) bool {
    return a.x == b.x and a.y == b.y and a.w == b.w and a.h == b.h;
}

/// Componentwise interpolation (t in [0, 1]).
pub fn rectLerp(a: Rect, b: Rect, t: f32) Rect {
    return .{ .x = a.x + (b.x - a.x) * t, .y = a.y + (b.y - a.y) * t, .w = a.w + (b.w - a.w) * t, .h = a.h + (b.h - a.h) * t };
}

/// A member in the vertical frame.
const Span = struct {
    left: f32,
    right: f32,
    top: f32,
    bottom: f32 = 0,
    radii: [4]f32,
    /// Extra per-corner caps (a chain break: the corners facing across the gap).
    caps: [4]f32 = @splat(std.math.inf(f32)),

    fn extent(s: Span) f32 {
        return s.bottom - s.top;
    }
    /// A member's corner never exceeds half its shorter side (`corner_radii.normalize`).
    fn cornerCap(s: Span, corner: usize) f32 {
        return @min(s.caps[corner], @min(s.right - s.left, s.extent()) / 2);
    }
};

fn overlap(a: Span, b: Span) f32 {
    return @min(a.right, b.right) - @max(a.left, b.left);
}

pub const Outline = struct {
    vertices: std.ArrayList(Vertex) = .empty,
    contours: std.ArrayList(Contour) = .empty,

    pub fn deinit(self: *Outline, allocator: std.mem.Allocator) void {
        self.vertices.deinit(allocator);
        self.contours.deinit(allocator);
        self.* = .{};
    }

    pub fn clear(self: *Outline) void {
        self.vertices.clearRetainingCapacity();
        self.contours.clearRetainingCapacity();
    }

    pub fn contour(self: *const Outline, index: usize) []const Vertex {
        const c = self.contours.items[index];
        return self.vertices.items[c.start..][0..c.len];
    }

    pub fn eql(a: *const Outline, b: *const Outline) bool {
        if (a.contours.items.len != b.contours.items.len or a.vertices.items.len != b.vertices.items.len) return false;
        for (a.contours.items, b.contours.items) |x, y| if (x.start != y.start or x.len != y.len) return false;
        for (a.vertices.items, b.vertices.items) |x, y| if (x.x != y.x or x.y != y.y or x.radius != y.radius or x.convex != y.convex) return false;
        return true;
    }

    /// Solve `chain` into this outline (replaces its contents, keeps capacity). `inset` = 0 is
    /// the outline itself; `inset` = d > 0 is the concentric outline d inside it (a border's
    /// centre line, concentric content), split where a join is narrower than 2d.
    pub fn solve(self: *Outline, allocator: std.mem.Allocator, chain: Chain, inset: f32) !void {
        self.clear();
        var list: std.ArrayList(Span) = .empty;
        defer list.deinit(allocator);
        try collectSpans(allocator, chain, &list);
        const spans = list.items;
        if (spans.len == 0) return;
        const join = sanitize(chain.join_radius);
        const d = if (std.math.isFinite(inset)) @max(0, inset) else 0;
        var start: usize = 0;
        while (start < spans.len) {
            var end = start;
            while (end + 1 < spans.len and overlap(spans[end], spans[end + 1]) > epsilon) end += 1;
            if (end + 1 < spans.len) breakCaps(&spans[end], &spans[end + 1]);
            // The concentric outline pinches off where a join is narrower than 2d.
            var sub = start;
            while (sub <= end) {
                var sub_end = sub;
                while (sub_end < end and overlap(spans[sub_end], spans[sub_end + 1]) - 2 * d > epsilon) sub_end += 1;
                try self.appendRun(allocator, spans[sub .. sub_end + 1], join, d);
                sub = sub_end + 1;
            }
            start = end + 1;
        }
        if (chain.axis == .horizontal) self.transposeInPlace();
    }

    /// Members in the vertical frame: each ends where the next begins, absent ones (no width,
    /// non-finite) dropped, zero-extent middle members dropped (their neighbours join directly).
    fn collectSpans(allocator: std.mem.Allocator, chain: Chain, out: *std.ArrayList(Span)) !void {
        for (chain.members) |m| {
            const r = if (chain.axis == .vertical) m.rect else transposeRect(m.rect);
            if (!(std.math.isFinite(r.x) and std.math.isFinite(r.y) and std.math.isFinite(r.w) and std.math.isFinite(r.h)) or !(r.w > 0)) continue;
            const radii = sanitizeRadii(if (chain.axis == .vertical) m.radii else transposeRadii(m.radii));
            const top = if (out.items.len == 0) r.y else @max(r.y, out.items[out.items.len - 1].top);
            try out.append(allocator, .{ .left = r.x, .right = r.x + r.w, .top = top, .bottom = @max(top, r.y + @max(0, r.h)), .radii = radii });
        }
        const s = out.items;
        // Every member but the last ends where the next begins.
        if (s.len > 1) for (s[0 .. s.len - 1], s[1..]) |*a, b| {
            a.bottom = b.top;
        };
        var i: usize = 1;
        while (i + 1 < out.items.len) {
            if (out.items[i].extent() <= epsilon) {
                _ = out.orderedRemove(i);
                out.items[i - 1].bottom = out.items[i].top;
            } else i += 1;
        }
    }

    /// Where the chain breaks, the corners that face each other across the gap g are capped at
    /// g / 2, so they grow from 0 as the parts separate (no jump at the break).
    fn breakCaps(upper: *Span, lower: *Span) void {
        const gap = @max(0, -overlap(upper.*, lower.*));
        if (upper.right <= lower.left + epsilon) {
            upper.caps[BR] = @min(upper.caps[BR], gap / 2);
            lower.caps[TL] = @min(lower.caps[TL], gap / 2);
        } else if (upper.left >= lower.right - epsilon) {
            upper.caps[BL] = @min(upper.caps[BL], gap / 2);
            lower.caps[TR] = @min(lower.caps[TR], gap / 2);
        }
    }

    const Builder = struct {
        outline: *Outline,
        allocator: std.mem.Allocator,
        bases: std.ArrayList(f32) = .empty,
        caps: std.ArrayList(f32) = .empty,

        fn add(b: *Builder, x: f32, y: f32, base: f32, cap: f32, convex: bool) !void {
            try b.outline.vertices.append(b.allocator, .{ .x = x, .y = y, .radius = 0, .convex = convex });
            try b.bases.append(b.allocator, base);
            try b.caps.append(b.allocator, cap);
        }
        fn deinit(b: *Builder) void {
            b.bases.deinit(b.allocator);
            b.caps.deinit(b.allocator);
        }
    };

    fn appendRun(self: *Outline, allocator: std.mem.Allocator, run: []const Span, join: f32, d: f32) !void {
        const begin: u32 = @intCast(self.vertices.items.len);
        var b: Builder = .{ .outline = self, .allocator = allocator };
        defer b.deinit();
        const first = run[0];
        const last = run[run.len - 1];
        try b.add(first.left, first.top, first.radii[TL], first.cornerCap(TL), true);
        try b.add(first.right, first.top, first.radii[TR], first.cornerCap(TR), true);
        // Right side, top to bottom: the wider member gets a convex corner, the narrower a join.
        for (run[0 .. run.len - 1], run[1..]) |upper, lower| {
            const y = lower.top;
            const o = overlap(upper, lower);
            if (@abs(upper.right - lower.right) <= epsilon) continue;
            if (lower.right > upper.right) {
                try b.add(upper.right, y, join, o, false);
                try b.add(lower.right, y, lower.radii[TR], lower.cornerCap(TR), true);
            } else {
                try b.add(upper.right, y, upper.radii[BR], upper.cornerCap(BR), true);
                try b.add(lower.right, y, join, o, false);
            }
        }
        try b.add(last.right, last.bottom, last.radii[BR], last.cornerCap(BR), true);
        try b.add(last.left, last.bottom, last.radii[BL], last.cornerCap(BL), true);
        // Left side, bottom to top.
        var k = run.len - 1;
        while (k > 0) {
            k -= 1;
            const upper = run[k];
            const lower = run[k + 1];
            const y = lower.top;
            const o = overlap(upper, lower);
            if (@abs(upper.left - lower.left) <= epsilon) continue;
            if (lower.left < upper.left) {
                try b.add(lower.left, y, lower.radii[TL], lower.cornerCap(TL), true);
                try b.add(upper.left, y, join, o, false);
            } else {
                try b.add(lower.left, y, join, o, false);
                try b.add(upper.left, y, upper.radii[BL], upper.cornerCap(BL), true);
            }
        }
        const verts = self.vertices.items[begin..];
        try fit(allocator, verts, b.bases.items, b.caps.items);
        if (d > 0 and !try offset(allocator, verts, d)) {
            self.vertices.shrinkRetainingCapacity(begin);
            return;
        }
        try self.contours.append(allocator, .{ .start = begin, .len = @intCast(verts.len) });
    }

    /// The shrinking rule (design §4.1): cap each base (its two edges and `caps`), then every
    /// edge scales the two arcs on it proportionally when they do not fit.
    fn fit(allocator: std.mem.Allocator, verts: []Vertex, bases: []const f32, caps_in: []const f32) !void {
        const n = verts.len;
        if (n == 0) return;
        const caps = try allocator.alloc(f32, 2 * n);
        defer allocator.free(caps);
        const factors = caps[n..];
        for (0..n) |i| {
            const l_in = edgeLength(verts[(i + n - 1) % n], verts[i]);
            const l_out = edgeLength(verts[i], verts[(i + 1) % n]);
            caps[i] = @max(0, @min(@min(sanitize(bases[i]), caps_in[i]), @min(l_in, l_out)));
            factors[i] = 1;
        }
        for (0..n) |i| {
            const j = (i + 1) % n;
            const sum = caps[i] + caps[j];
            const length = edgeLength(verts[i], verts[j]);
            if (sum > length and sum > 0) {
                const g = length / sum;
                factors[i] = @min(factors[i], g);
                factors[j] = @min(factors[j], g);
            }
        }
        for (verts, 0..) |*v, i| v.radius = caps[i] * factors[i];
    }

    /// Move a solved contour d inwards: vertices along their bisectors, convex arcs r - d,
    /// concave arcs r + d (same centres), then fit again. False when it collapsed.
    fn offset(allocator: std.mem.Allocator, verts: []Vertex, d: f32) !bool {
        const n = verts.len;
        const scratch = try allocator.alloc(f32, 2 * n);
        defer allocator.free(scratch);
        const bases = scratch[0..n];
        const no_caps = scratch[n..];
        const moved = try allocator.alloc(Vertex, n);
        defer allocator.free(moved);
        for (verts, 0..) |v, i| {
            const n_in = rightNormal(verts[(i + n - 1) % n], v);
            const n_out = rightNormal(v, verts[(i + 1) % n]);
            moved[i] = .{ .x = v.x + d * (n_in[0] + n_out[0]), .y = v.y + d * (n_in[1] + n_out[1]), .radius = 0, .convex = v.convex };
            bases[i] = if (v.convex) v.radius - d else v.radius + d;
            no_caps[i] = std.math.inf(f32);
        }
        for (0..n) |i| {
            const a0 = verts[i];
            const b0 = verts[(i + 1) % n];
            const a1 = moved[i];
            const b1 = moved[(i + 1) % n];
            if ((b0.x - a0.x) * (b1.x - a1.x) + (b0.y - a0.y) * (b1.y - a1.y) < 0) return false;
        }
        @memcpy(verts, moved);
        try fit(allocator, verts, bases, no_caps);
        return true;
    }

    /// Append the outline as closed path commands: straight edges and one cubic per arc.
    /// Each contour starts with one `move_to` and ends with `close`.
    pub fn appendPath(self: *const Outline, allocator: std.mem.Allocator, out: *std.ArrayList(PathCommand)) !void {
        for (self.contours.items, 0..) |_, ci| {
            const verts = self.contour(ci);
            const n = verts.len;
            if (n < 3) continue;
            var cursor: [2]f32 = undefined;
            for (verts, 0..) |v, i| {
                const prev = verts[(i + n - 1) % n];
                const next = verts[(i + 1) % n];
                const start = arcStart(prev, v);
                if (i == 0) {
                    try out.append(allocator, .{ .move_to = .{ .x = start[0], .y = start[1] } });
                } else if (!near(cursor, start)) {
                    try out.append(allocator, .{ .line_to = .{ .x = start[0], .y = start[1] } });
                }
                cursor = start;
                if (v.radius > 0) {
                    const din = direction(prev, v);
                    const dout = direction(v, next);
                    const end = [2]f32{ v.x + v.radius * dout[0], v.y + v.radius * dout[1] };
                    try out.append(allocator, .{ .cubic_to = .{
                        .ctrl1 = .{ .x = start[0] + kappa * v.radius * din[0], .y = start[1] + kappa * v.radius * din[1] },
                        .ctrl2 = .{ .x = end[0] - kappa * v.radius * dout[0], .y = end[1] - kappa * v.radius * dout[1] },
                        .end = .{ .x = end[0], .y = end[1] },
                    } });
                    cursor = end;
                }
            }
            try out.append(allocator, .{ .close = {} });
        }
    }

    /// Bounding box of all contours (zero rect when empty).
    pub fn bounds(self: *const Outline) Rect {
        if (self.vertices.items.len == 0) return .{ .x = 0, .y = 0, .w = 0, .h = 0 };
        var x0: f32 = std.math.inf(f32);
        var y0: f32 = std.math.inf(f32);
        var x1: f32 = -std.math.inf(f32);
        var y1: f32 = -std.math.inf(f32);
        for (self.vertices.items) |v| {
            x0 = @min(x0, v.x);
            y0 = @min(y0, v.y);
            x1 = @max(x1, v.x);
            y1 = @max(y1, v.y);
        }
        return .{ .x = x0, .y = y0, .w = x1 - x0, .h = y1 - y0 };
    }

    fn transposeInPlace(self: *Outline) void {
        for (self.vertices.items) |*v| std.mem.swap(f32, &v.x, &v.y);
        // Transposing mirrors the winding: reverse each contour to stay clockwise.
        for (self.contours.items) |c| std.mem.reverse(Vertex, self.vertices.items[c.start..][0..c.len]);
    }
};

/// Path geometry of `outline` (borrows `commands`; see `Outline.appendPath`).
pub fn geometry(commands: []const PathCommand, outline: *const Outline) PathGeometry {
    return .{ .commands = commands, .fill_rule = .nonzero, .bounds = outline.bounds() };
}

fn sanitize(r: f32) f32 {
    return if (r > 0 and std.math.isFinite(r)) r else if (r > 0) std.math.inf(f32) else 0; // NaN > 0 is false
}

fn sanitizeRadii(r: [4]f32) [4]f32 {
    return .{ sanitize(r[0]), sanitize(r[1]), sanitize(r[2]), sanitize(r[3]) };
}

fn transposeRect(r: Rect) Rect {
    return .{ .x = r.y, .y = r.x, .w = r.h, .h = r.w };
}

/// Corner (x, y) maps to (y, x): TL stays, TR <-> BL, BR stays.
fn transposeRadii(r: [4]f32) [4]f32 {
    return .{ r[TL], r[BL], r[BR], r[TR] };
}

fn edgeLength(a: Vertex, b: Vertex) f32 {
    return @abs(b.x - a.x) + @abs(b.y - a.y);
}

fn direction(a: Vertex, b: Vertex) [2]f32 {
    const dx = b.x - a.x;
    const dy = b.y - a.y;
    const l = @sqrt(dx * dx + dy * dy);
    if (l == 0) return .{ 0, 0 };
    return .{ dx / l, dy / l };
}

/// Interior side of a clockwise (screen) contour edge a -> b.
fn rightNormal(a: Vertex, b: Vertex) [2]f32 {
    const d = direction(a, b);
    return .{ -d[1], d[0] };
}

fn arcStart(prev: Vertex, v: Vertex) [2]f32 {
    if (v.radius <= 0) return .{ v.x, v.y };
    const d = direction(prev, v);
    return .{ v.x - v.radius * d[0], v.y - v.radius * d[1] };
}

fn near(a: [2]f32, b: [2]f32) bool {
    return @abs(a[0] - b[0]) <= 1e-4 and @abs(a[1] - b[1]) <= 1e-4;
}

// Tests
// ---------------------------------------------------------------------------

const testing = std.testing;

fn solved(chain: Chain) !Outline {
    return solvedInset(chain, 0);
}

fn solvedInset(chain: Chain, d: f32) !Outline {
    var o: Outline = .{};
    errdefer o.deinit(testing.allocator);
    try o.solve(testing.allocator, chain, d);
    return o;
}

/// A tab (top, 100 wide, 33 high) on a panel 400 x 200 at x = 0; tab left edge at `w`.
fn tabOnPanel(w: f32, panel_r: f32, tab_r: f32) [2]Member {
    return .{
        .{ .rect = .{ .x = w, .y = 0, .w = 100, .h = 33 }, .radii = @splat(tab_r) },
        .{ .rect = .{ .x = 0, .y = 33, .w = 400, .h = 200 }, .radii = @splat(panel_r) },
    };
}

fn findVertex(o: *const Outline, x: f32, y: f32) ?Vertex {
    for (o.vertices.items) |v| if (@abs(v.x - x) < 1e-4 and @abs(v.y - y) < 1e-4) return v;
    return null;
}

test "joined outline: panel corner and join shrink together (reference values 32, 29, 13, 0)" {
    // Reference video: both bases 16.
    const cases = [_][3]f32{ .{ 32, 16, 16 }, .{ 29, 14.5, 14.5 }, .{ 13, 6.5, 6.5 }, .{ 40, 16, 16 } };
    for (cases) |c| {
        const members = tabOnPanel(c[0], 16, 12);
        var o = try solved(.{ .members = &members, .join_radius = 16 });
        defer o.deinit(testing.allocator);
        const corner = findVertex(&o, 0, 33).?;
        const join = findVertex(&o, c[0], 33).?;
        try testing.expect(corner.convex and !join.convex);
        try testing.expectApproxEqAbs(c[1], corner.radius, 1e-4);
        try testing.expectApproxEqAbs(c[2], join.radius, 1e-4);
    }
    // w = 0: the tab's side and the panel's side are one straight line (no vertices at the join).
    const flush = tabOnPanel(0, 16, 12);
    var o = try solved(.{ .members = &flush, .join_radius = 16 });
    defer o.deinit(testing.allocator);
    try testing.expect(findVertex(&o, 0, 33) == null);
    try testing.expectEqual(@as(usize, 6), o.vertices.items.len);
}

test "joined outline: unequal bases shrink proportionally and never grow" {
    // Panel 12, join 10: shared edge 14 < 22 scales both by 14 / 22.
    const members = tabOnPanel(14, 12, 10);
    var o = try solved(.{ .members = &members, .join_radius = 10 });
    defer o.deinit(testing.allocator);
    try testing.expectApproxEqAbs(12.0 * 14.0 / 22.0, findVertex(&o, 0, 33).?.radius, 1e-4);
    try testing.expectApproxEqAbs(10.0 * 14.0 / 22.0, findVertex(&o, 14, 33).?.radius, 1e-4);
    // Sweeping w, no radius ever exceeds its base and each edge holds its arcs.
    var w: f32 = 0;
    while (w <= 60) : (w += 0.25) {
        const ms = tabOnPanel(w, 12, 10);
        var s = try solved(.{ .members = &ms, .join_radius = 10 });
        defer s.deinit(testing.allocator);
        try expectEdgesHoldArcs(&s);
        for (s.vertices.items) |v| try testing.expect(v.radius <= 12 + 1e-4);
    }
}

fn expectEdgesHoldArcs(o: *const Outline) !void {
    for (o.contours.items, 0..) |_, ci| {
        const vs = o.contour(ci);
        for (vs, 0..) |v, i| {
            const next = vs[(i + 1) % vs.len];
            try testing.expect(v.radius + next.radius <= edgeLength(v, next) + 1e-3);
        }
    }
}

test "joined outline: mirrored input gives a mirrored outline" {
    const members = tabOnPanel(20, 12, 10);
    var mirrored: [2]Member = members;
    for (&mirrored) |*m| {
        m.rect.x = 400 - (m.rect.x + m.rect.w);
        m.radii = .{ m.radii[TR], m.radii[TL], m.radii[BL], m.radii[BR] };
    }
    var a = try solved(.{ .members = &members, .join_radius = 10 });
    defer a.deinit(testing.allocator);
    var b = try solved(.{ .members = &mirrored, .join_radius = 10 });
    defer b.deinit(testing.allocator);
    try testing.expectEqual(a.vertices.items.len, b.vertices.items.len);
    for (a.vertices.items) |v| {
        const m = findVertex(&b, 400 - v.x, v.y) orelse return error.TestUnexpectedResult;
        try testing.expectApproxEqAbs(v.radius, m.radius, 1e-4);
        try testing.expectEqual(v.convex, m.convex);
    }
}

test "joined outline: concentric inset 17 - 6 = 11 agrees with concentric.radiiFor" {
    const concentric = @import("concentric.zig");
    const members = [_]Member{.{ .rect = .{ .x = 0, .y = 0, .w = 120, .h = 80 }, .radii = @splat(17) }};
    var inner = try solvedInset(.{ .members = &members }, 6);
    defer inner.deinit(testing.allocator);
    const expected = concentric.radiiFor(.{ 6, 6, 108, 68 }, .{ 0, 0, 120, 80 }, 17, 0);
    try testing.expectEqual(@as(usize, 4), inner.vertices.items.len);
    for (inner.vertices.items) |v| try testing.expectApproxEqAbs(expected[0], v.radius, 1e-4);
    try testing.expect(findVertex(&inner, 6, 6) != null and findVertex(&inner, 114, 74) != null);
    // Concave joins grow by the inset: the arcs stay concentric (same centres).
    const tab = tabOnPanel(50, 12, 10);
    var t = try solvedInset(.{ .members = &tab, .join_radius = 10 }, 1);
    defer t.deinit(testing.allocator);
    const join = findVertex(&t, 51, 34).?;
    try testing.expect(!join.convex);
    try testing.expectApproxEqAbs(@as(f32, 11), join.radius, 1e-4);
    try testing.expectApproxEqAbs(@as(f32, 9), findVertex(&t, 51, 1).?.radius, 1e-4);
}

test "joined outline: the inset pinches off at a join narrower than twice the inset" {
    // Rows [0, 100] and [95, 195] overlap by 5; 3 inside, the neck closes: two contours,
    // neither self-intersecting (every vertex of a contour stays inside its own row).
    const rows = [_]Member{
        .{ .rect = .{ .x = 0, .y = 0, .w = 100, .h = 20 }, .radii = @splat(4) },
        .{ .rect = .{ .x = 95, .y = 20, .w = 100, .h = 20 }, .radii = @splat(4) },
    };
    var outer = try solved(.{ .members = &rows, .join_radius = 4 });
    defer outer.deinit(testing.allocator);
    try testing.expectEqual(@as(usize, 1), outer.contours.items.len);
    var inner = try solvedInset(.{ .members = &rows, .join_radius = 4 }, 3);
    defer inner.deinit(testing.allocator);
    try testing.expectEqual(@as(usize, 2), inner.contours.items.len);
    for (inner.contour(0)) |v| try testing.expect(v.x <= 97 + 1e-4 and v.y <= 17 + 1e-4);
    for (inner.contour(1)) |v| try testing.expect(v.x >= 98 - 1e-4 and v.y >= 23 - 1e-4);
    try expectEdgesHoldArcs(&inner);
}

test "joined outline: one member is a plain rounded rectangle (corner_radii.normalize)" {
    const corner_radii = @import("zenit_corner_radii");
    const cases = [_][4]f32{ .{ 9999, 4, 0, 30 }, .{ 16, 0, 0, 4 }, .{ 8, 8, 8, 8 }, .{ std.math.inf(f32), 3, std.math.nan(f32), -2 } };
    for (cases) |radii| {
        const members = [_]Member{.{ .rect = .{ .x = 10, .y = 20, .w = 100, .h = 20 }, .radii = radii }};
        var o = try solved(.{ .members = &members });
        defer o.deinit(testing.allocator);
        const expected = corner_radii.normalize(radii, 100, 20);
        try testing.expectEqual(@as(usize, 4), o.vertices.items.len);
        for (o.vertices.items, 0..) |v, i| try testing.expectApproxEqAbs(expected[i], v.radius, 1e-4);
    }
}

test "joined outline: a narrow tab keeps its full join arcs" {
    // 28 wide, join 16: the arcs lie outside the tab on both sides and do not compete.
    const ms = [_]Member{
        .{ .rect = .{ .x = 100, .y = 0, .w = 28, .h = 40 }, .radii = @splat(8) },
        .{ .rect = .{ .x = 0, .y = 40, .w = 400, .h = 200 }, .radii = @splat(12) },
    };
    var o = try solved(.{ .members = &ms, .join_radius = 16 });
    defer o.deinit(testing.allocator);
    try testing.expectApproxEqAbs(@as(f32, 16), findVertex(&o, 100, 40).?.radius, 1e-4);
    try testing.expectApproxEqAbs(@as(f32, 16), findVertex(&o, 128, 40).?.radius, 1e-4);
}

test "joined outline: a zero-height middle member leaves its neighbours joined directly" {
    const ms = [_]Member{
        .{ .rect = .{ .x = 0, .y = 0, .w = 100, .h = 20 }, .radii = @splat(4) },
        .{ .rect = .{ .x = 40, .y = 20, .w = 20, .h = 0 }, .radii = @splat(4) },
        .{ .rect = .{ .x = 0, .y = 20, .w = 100, .h = 20 }, .radii = @splat(4) },
    };
    var o = try solved(.{ .members = &ms, .join_radius = 4 });
    defer o.deinit(testing.allocator);
    // One plain rectangle: no fold-back vertices on the join line.
    try testing.expectEqual(@as(usize, 4), o.vertices.items.len);
}

test "joined outline: continuous while a tab slides, retracts and the overlap closes" {
    var prev: ?Outline = null;
    defer if (prev) |*p| p.deinit(testing.allocator);
    // Slide from flush (w = 0) to 60 in small steps: each radius changes by a bounded amount.
    var w: f32 = 0;
    while (w <= 60) : (w += 0.05) {
        const ms = tabOnPanel(w, 12, 10);
        var o = try solved(.{ .members = &ms, .join_radius = 10 });
        const corner = if (findVertex(&o, 0, 33)) |v| v.radius else 0;
        if (prev) |*p| {
            const before = if (findVertex(p, 0, 33)) |v| v.radius else 0;
            try testing.expect(@abs(corner - before) < 0.1);
            p.deinit(testing.allocator);
        }
        prev = o;
    }
    // Retract the tab to zero height: the panel corner returns to its full radius.
    var h: f32 = 33;
    var last_corner: f32 = 0;
    while (h >= 0) : (h -= 0.5) {
        const ms = [_]Member{
            .{ .rect = .{ .x = 14, .y = 33 - h, .w = 100, .h = h }, .radii = @splat(10) },
            .{ .rect = .{ .x = 0, .y = 33, .w = 400, .h = 200 }, .radii = @splat(12) },
        };
        var o = try solved(.{ .members = &ms, .join_radius = 10 });
        defer o.deinit(testing.allocator);
        try expectEdgesHoldArcs(&o);
        last_corner = findVertex(&o, 0, 33).?.radius;
    }
    try testing.expectApproxEqAbs(@as(f32, 12), last_corner, 1e-4);
    // Shrinking the overlap of two staggered rows: the join arcs fade out before the chain breaks.
    var o_len: f32 = 20;
    var last_join: f32 = 1;
    while (o_len > 0) : (o_len -= 0.25) {
        const ms = [_]Member{
            .{ .rect = .{ .x = 0, .y = 0, .w = 100, .h = 20 }, .radii = @splat(4) },
            .{ .rect = .{ .x = 100 - o_len, .y = 20, .w = 100, .h = 20 }, .radii = @splat(4) },
        };
        var o = try solved(.{ .members = &ms, .join_radius = 4 });
        defer o.deinit(testing.allocator);
        try testing.expectEqual(@as(usize, 1), o.contours.items.len);
        for (o.vertices.items) |v| if (!v.convex) {
            try testing.expect(v.radius <= o_len + 1e-4);
            last_join = v.radius;
        };
    }
    try testing.expect(last_join <= 0.25 + 1e-4);
    // After the break the facing corners grow from 0 with the gap.
    var gap: f32 = 0.5;
    while (gap <= 10) : (gap += 0.5) {
        const ms = [_]Member{
            .{ .rect = .{ .x = 0, .y = 0, .w = 100, .h = 20 }, .radii = @splat(4) },
            .{ .rect = .{ .x = 100 + gap, .y = 20, .w = 100, .h = 20 }, .radii = @splat(4) },
        };
        var o = try solved(.{ .members = &ms, .join_radius = 4 });
        defer o.deinit(testing.allocator);
        try testing.expectEqual(@as(usize, 2), o.contours.items.len);
        try testing.expectApproxEqAbs(@min(4, gap / 2), findVertex(&o, 100, 20).?.radius, 1e-4);
        try testing.expectApproxEqAbs(@min(4, gap / 2), findVertex(&o, 100 + gap, 20).?.radius, 1e-4);
    }
}

test "joined outline: disjoint members make separate contours; horizontal chains transpose" {
    const ms = [_]Member{
        .{ .rect = .{ .x = 0, .y = 0, .w = 50, .h = 20 }, .radii = @splat(4) },
        .{ .rect = .{ .x = 60, .y = 20, .w = 50, .h = 20 }, .radii = @splat(4) },
    };
    var o = try solved(.{ .members = &ms, .join_radius = 4 });
    defer o.deinit(testing.allocator);
    try testing.expectEqual(@as(usize, 2), o.contours.items.len);
    // A side tab sticking out to the left of a panel, as a horizontal chain.
    const side = [_]Member{
        .{ .rect = .{ .x = 0, .y = 40, .w = 30, .h = 60 }, .radii = @splat(8) },
        .{ .rect = .{ .x = 30, .y = 0, .w = 200, .h = 300 }, .radii = @splat(12) },
    };
    var h = try solved(.{ .axis = .horizontal, .members = &side, .join_radius = 8 });
    defer h.deinit(testing.allocator);
    try testing.expectEqual(@as(usize, 8), h.vertices.items.len);
    try testing.expect(!findVertex(&h, 30, 40).?.convex);
    try testing.expect(findVertex(&h, 0, 40).?.convex);
    try testing.expectApproxEqAbs(@as(f32, 8), findVertex(&h, 30, 100).?.radius, 1e-4);
    // Clockwise: signed area (shoelace, y down) is positive.
    var area: f32 = 0;
    const vs = h.contour(0);
    for (vs, 0..) |v, i| {
        const nx = vs[(i + 1) % vs.len];
        area += v.x * nx.y - nx.x * v.y;
    }
    try testing.expect(area > 0);
}

test "joined outline: the path is one closed contour per surface (continuous stroke)" {
    const ms = tabOnPanel(30, 12, 10);
    var o = try solved(.{ .members = &ms, .join_radius = 10 });
    defer o.deinit(testing.allocator);
    var cmds: std.ArrayList(PathCommand) = .empty;
    defer cmds.deinit(testing.allocator);
    try o.appendPath(testing.allocator, &cmds);
    var moves: usize = 0;
    var closes: usize = 0;
    var cubics: usize = 0;
    for (cmds.items) |c| switch (c) {
        .move_to => moves += 1,
        .close => closes += 1,
        .cubic_to => cubics += 1,
        else => {},
    };
    try testing.expectEqual(@as(usize, 1), moves);
    try testing.expectEqual(@as(usize, 1), closes);
    try testing.expectEqual(@as(usize, 8), cubics);
    // Every segment starts where the previous one ended (no gaps along the contour).
    var cursor = cmds.items[0].move_to;
    for (cmds.items[1..]) |c| switch (c) {
        .line_to => |p| cursor = p,
        .cubic_to => |cb| {
            // A cubic arc starts tangent to the incoming edge: its first handle is collinear
            // with the cursor along one axis.
            try testing.expect(@abs(cb.ctrl1.x - cursor.x) < 1e-4 or @abs(cb.ctrl1.y - cursor.y) < 1e-4);
            cursor = cb.end;
        },
        else => {},
    };
    const g = geometry(cmds.items, &o);
    try testing.expectEqual(@as(f32, 0), g.bounds.x);
    try testing.expectEqual(@as(f32, 233), g.bounds.h);
}
