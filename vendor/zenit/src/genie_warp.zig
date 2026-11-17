//! Genie warp: the mesh deformation of "collapse into an anchor" (macOS Dock minimize).
//! Shared by the UI (anchor transition geometry, bounds, tests) and the renderer (the GPU mesh
//! composite of a cached layer texture), so both evaluate the exact same function.
//!
//! A picture of the content (one cached texture) is covered by a grid; every grid point moves from
//! where it rests in the home rect to the matching point of the anchor rect. The rows of the grid
//! (lines across the direction of travel) do not move together: the edge facing the anchor leads,
//! the far edge follows `stagger` later, so the content is pulled in by its near edge. Across the
//! direction of travel each row narrows to the anchor's width ahead of its travel (`squeeze`), so
//! the near edge first pinches to the anchor's width and the sides bend into smooth S curves
//! between the still-wide far edge and the narrow near edge; then the whole strip slides in.
//!
//! The shape is a pure function of progress (0 = home, 1 = exactly the anchor rect), so a run that
//! reverses midway stays continuous. Coordinates: window (logical px). `u, v` address the content
//! normalised over the home rect (0..1 inside it; points outside, such as an outer shadow, extend
//! the same map).
const std = @import("std");

/// Direction of travel, from the home rect toward the anchor. Chosen once per run.
pub const Direction = enum(u8) {
    down = 0,
    up = 1,
    right = 2,
    left = 3,

    pub fn vertical(d: Direction) bool {
        return d == .down or d == .up;
    }
};

/// The warp as carried by a display item (plain data, fixed size).
pub const Warp = extern struct {
    /// 0 = no warp (composite the layer with its affine transform).
    active: u8 = 0,
    /// `Direction`.
    direction: u8 = 0,
    /// Grid cells along the direction of travel / across it (the renderer clamps to 1..64).
    rows: u8 = 32,
    cols: u8 = 8,
    /// The node's rect in the layer's own (surface-local) coordinates: it rests exactly on `home`.
    local: [4]f32 = .{ 0, 0, 0, 0 },
    /// Home rect and anchor rect, window coordinates (x, y, w, h).
    home: [4]f32 = .{ 0, 0, 0, 0 },
    anchor: [4]f32 = .{ 0, 0, 0, 0 },
    /// 0 = home, 1 = in the anchor.
    progress: f32 = 0,
    /// Share of the run by which the far edge starts after the near edge (0 = all rows together).
    stagger: f32 = 0.35,
    /// How much faster a row narrows than it travels (0 = in step).
    squeeze: f32 = 0.6,

    pub fn isActive(self: Warp) bool {
        return self.active != 0 and self.home[2] > 0 and self.home[3] > 0 and self.local[2] > 0 and self.local[3] > 0;
    }

    pub fn withProgress(self: Warp, p: f32) Warp {
        var out = self;
        out.progress = p;
        return out;
    }

    pub fn dir(self: Warp) Direction {
        return switch (self.direction) {
            1 => .up,
            2 => .right,
            3 => .left,
            else => .down,
        };
    }
};

pub const Rect = struct { x: f32, y: f32, w: f32, h: f32 };

fn rectOf(r: [4]f32) Rect {
    return .{ .x = r[0], .y = r[1], .w = r[2], .h = r[3] };
}

/// Travel direction from `home` toward `anchor`: an anchor wholly above / below the home rect pulls
/// vertically, wholly left / right horizontally; an overlapping one by the larger relative offset.
pub fn chooseDirection(home: [4]f32, anchor: [4]f32) Direction {
    const h = rectOf(home);
    const a = rectOf(anchor);
    if (a.y + a.h <= h.y) return .up;
    if (a.y >= h.y + h.h) return .down;
    if (a.x + a.w <= h.x) return .left;
    if (a.x >= h.x + h.w) return .right;
    const dx = (a.x + a.w * 0.5) - (h.x + h.w * 0.5);
    const dy = (a.y + a.h * 0.5) - (h.y + h.h * 0.5);
    const rx = if (h.w > 0) @abs(dx) / h.w else 0;
    const ry = if (h.h > 0) @abs(dy) / h.h else 0;
    if (ry >= rx) return if (dy >= 0) .down else .up;
    return if (dx >= 0) .right else .left;
}

/// Canonical frame: `c` across the travel, `a` along it, the anchor lying toward larger `a`.
const Canon = struct { c0: f32, cw: f32, a0: f32, ah: f32 };

fn canon(r: Rect, d: Direction) Canon {
    return switch (d) {
        .down => .{ .c0 = r.x, .cw = r.w, .a0 = r.y, .ah = r.h },
        .up => .{ .c0 = r.x, .cw = r.w, .a0 = -(r.y + r.h), .ah = r.h },
        .right => .{ .c0 = r.y, .cw = r.h, .a0 = r.x, .ah = r.w },
        .left => .{ .c0 = r.y, .cw = r.h, .a0 = -(r.x + r.w), .ah = r.w },
    };
}

fn toWorld(c: f32, a: f32, d: Direction) [2]f32 {
    return switch (d) {
        .down => .{ c, a },
        .up => .{ c, -a },
        .right => .{ a, c },
        .left => .{ -a, c },
    };
}

/// (s, r): across-travel position and along-travel position (0 = far edge, 1 = edge facing the
/// anchor), from the home-normalised (u, v).
fn rowCoords(u: f32, v: f32, d: Direction) [2]f32 {
    return switch (d) {
        .down => .{ u, v },
        .up => .{ u, 1 - v },
        .right => .{ v, u },
        .left => .{ v, 1 - u },
    };
}

fn easeInOutCubic(t: f32) f32 {
    return if (t < 0.5) 4 * t * t * t else 1 - std.math.pow(f32, -2 * t + 2, 3) / 2;
}

fn clamp01(x: f32) f32 {
    return if (std.math.isFinite(x)) std.math.clamp(x, 0, 1) else 0;
}

/// Progress of one row (`r` = 1 at the edge facing the anchor): the near edge starts at once, the
/// far edge `lag` later; every row covers its path in `1 - lag` of the run. `speed` > 1 makes the
/// row finish early (the cross-axis squeeze).
fn rowProgress(p: f32, r: f32, lag: f32, speed: f32) f32 {
    const span = 1 - lag;
    if (span <= 0.0001) return if (p >= 1) 1 else easeInOutCubic(clamp01(p * speed));
    return easeInOutCubic(clamp01((p * speed - (1 - r) * lag) / span));
}

fn lerp(a: f32, b: f32, t: f32) f32 {
    return a + (b - a) * t;
}

/// The two per-row weights (across, along) at progress `p` for row `r` (clamped into the rect).
pub fn rowWeights(w: Warp, r: f32) [2]f32 {
    const p = clamp01(w.progress);
    const lag = std.math.clamp(if (std.math.isFinite(w.stagger)) w.stagger else 0, 0, 0.9);
    const squeeze = std.math.clamp(if (std.math.isFinite(w.squeeze)) w.squeeze else 0, 0, 4);
    const rc = clamp01(r);
    return .{ rowProgress(p, rc, lag, 1 + squeeze), rowProgress(p, rc, lag, 1) };
}

/// Window position of the content point (u, v) (normalised over the home rect).
pub fn point(w: Warp, u: f32, v: f32) [2]f32 {
    const d = w.dir();
    const h = canon(rectOf(w.home), d);
    const a = canon(rectOf(w.anchor), d);
    const sr = rowCoords(u, v, d);
    const weights = rowWeights(w, sr[1]);
    const c = lerp(h.c0 + sr[0] * h.cw, a.c0 + sr[0] * a.cw, weights[0]);
    const along = lerp(h.a0 + sr[1] * h.ah, a.a0 + sr[1] * a.ah, weights[1]);
    return toWorld(c, along, d);
}

/// Window position of a surface-local point (layer coordinates; `local` rests on `home`).
pub fn localPoint(w: Warp, x: f32, y: f32) [2]f32 {
    const u = if (w.local[2] > 0) (x - w.local[0]) / w.local[2] else 0;
    const v = if (w.local[3] > 0) (y - w.local[1]) / w.local[3] else 0;
    return point(w, u, v);
}

/// Window bounds (x, y, w, h) of the warped surface-local rect `r`.
pub fn localBounds(w: Warp, r: [4]f32) [4]f32 {
    var min_x: f32 = std.math.inf(f32);
    var min_y: f32 = std.math.inf(f32);
    var max_x: f32 = -std.math.inf(f32);
    var max_y: f32 = -std.math.inf(f32);
    const samples = 24;
    var i: usize = 0;
    while (i <= samples) : (i += 1) {
        const t: f32 = @as(f32, @floatFromInt(i)) / samples;
        // Every row maps to a straight segment, so its extremes are its two ends; sample rows
        // along both axes (the travel axis depends on the direction).
        for ([_][2]f32{
            .{ r[0] + t * r[2], r[1] },
            .{ r[0] + t * r[2], r[1] + r[3] },
            .{ r[0], r[1] + t * r[3] },
            .{ r[0] + r[2], r[1] + t * r[3] },
        }) |q| {
            const p = localPoint(w, q[0], q[1]);
            min_x = @min(min_x, p[0]);
            min_y = @min(min_y, p[1]);
            max_x = @max(max_x, p[0]);
            max_y = @max(max_y, p[1]);
        }
    }
    if (!(max_x >= min_x) or !(max_y >= min_y)) return .{ 0, 0, 0, 0 };
    return .{ min_x, min_y, max_x - min_x, max_y - min_y };
}

/// Window bounds of the warped home rect (the node itself, without what paints around it).
pub fn bounds(w: Warp) [4]f32 {
    return localBounds(w, w.local);
}

// ---------------------------------------------------------------------------------------------
// Tests

const testing = std.testing;

fn sample(progress: f32) Warp {
    return .{
        .active = 1,
        .direction = @intFromEnum(chooseDirection(.{ 300, 200, 400, 300 }, .{ 100, 10, 120, 28 })),
        .local = .{ 24, 24, 400, 300 },
        .home = .{ 300, 200, 400, 300 },
        .anchor = .{ 100, 10, 120, 28 },
        .progress = progress,
    };
}

fn near(a: [2]f32, b: [2]f32, tol: f32) bool {
    return @abs(a[0] - b[0]) <= tol and @abs(a[1] - b[1]) <= tol;
}

test "genie: rests exactly on home at 0 and exactly on the anchor at 1" {
    const w0 = sample(0);
    try testing.expectEqual(Direction.up, w0.dir());
    try testing.expect(near(point(w0, 0, 0), .{ 300, 200 }, 1e-4));
    try testing.expect(near(point(w0, 1, 1), .{ 700, 500 }, 1e-4));
    try testing.expect(near(localPoint(w0, 24, 24), .{ 300, 200 }, 1e-4));
    // A shadow pixel outside the node keeps its place at rest.
    try testing.expect(near(localPoint(w0, 0, 0), .{ 276, 176 }, 1e-3));
    const w1 = sample(1);
    try testing.expect(near(point(w1, 0, 0), .{ 100, 10 }, 1e-4));
    try testing.expect(near(point(w1, 1, 1), .{ 220, 38 }, 1e-4));
    const b = bounds(w1);
    try testing.expectApproxEqAbs(@as(f32, 100), b[0], 1e-3);
    try testing.expectApproxEqAbs(@as(f32, 120), b[2], 1e-3);
}

test "genie: the edge facing the anchor leads and pinches first" {
    const w = sample(0.3);
    // Anchor above: v = 0 is the near edge.
    const near_l = point(w, 0, 0);
    const near_r = point(w, 1, 0);
    const far_l = point(w, 0, 1);
    const far_r = point(w, 1, 1);
    // The near edge is already much narrower than the far edge.
    try testing.expect(near_r[0] - near_l[0] < (far_r[0] - far_l[0]) * 0.7);
    // The near edge travelled further (upward) than the far edge.
    try testing.expect(200 - near_l[1] > 500 - far_l[1]);
    // The sides bend: the midpoint of the left side is not on the line between its ends.
    const mid_l = point(w, 0, 0.5);
    const chord = (near_l[0] + far_l[0]) * 0.5;
    try testing.expect(@abs(mid_l[0] - chord) > 2);
}

test "genie: rows never fold back and frames are continuous in progress" {
    var p: f32 = 0;
    var prev = point(sample(0), 0.5, 0.5);
    while (p <= 1.0001) : (p += 0.01) {
        const w = sample(p);
        var last_y: f32 = -std.math.inf(f32);
        var v: f32 = 0;
        while (v <= 1.0001) : (v += 0.05) {
            const q = point(w, 0.5, v);
            try testing.expect(q[1] >= last_y - 1e-3);
            last_y = q[1];
        }
        const c = point(w, 0.5, 0.5);
        // A small progress step is a small move (no jumps): peak speed stays a few times the mean.
        try testing.expect(@abs(c[0] - prev[0]) + @abs(c[1] - prev[1]) <= 30);
        prev = c;
    }
}

test "genie: bounds hold every sampled point and every direction lands on the anchor" {
    const w = sample(0.55);
    const b = localBounds(w, .{ 0, 0, 448, 348 });
    var i: usize = 0;
    while (i <= 10) : (i += 1) {
        var j: usize = 0;
        while (j <= 10) : (j += 1) {
            const q = localPoint(w, @as(f32, @floatFromInt(i)) * 44.8, @as(f32, @floatFromInt(j)) * 34.8);
            try testing.expect(q[0] >= b[0] - 1e-3 and q[0] <= b[0] + b[2] + 1e-3);
            try testing.expect(q[1] >= b[1] - 1e-3 and q[1] <= b[1] + b[3] + 1e-3);
        }
    }
    const home = [4]f32{ 400, 300, 200, 100 };
    for ([_][4]f32{ .{ 450, 20, 40, 20 }, .{ 450, 700, 40, 20 }, .{ 20, 330, 40, 20 }, .{ 900, 330, 40, 20 } }, [_]Direction{ .up, .down, .left, .right }) |anchor, expected| {
        const d = chooseDirection(home, anchor);
        try testing.expectEqual(expected, d);
        const w1: Warp = .{ .active = 1, .direction = @intFromEnum(d), .local = .{ 0, 0, 200, 100 }, .home = home, .anchor = anchor, .progress = 1 };
        try testing.expect(near(point(w1, 0, 0), .{ anchor[0], anchor[1] }, 1e-3));
        try testing.expect(near(point(w1, 1, 1), .{ anchor[0] + anchor[2], anchor[1] + anchor[3] }, 1e-3));
        const w0 = w1.withProgress(0);
        try testing.expect(near(point(w0, 0.25, 0.75), .{ 450, 375 }, 1e-3));
    }
}

test "genie: bad tokens never produce NaN" {
    var w = sample(0.4);
    w.stagger = std.math.nan(f32);
    w.squeeze = std.math.inf(f32);
    const q = point(w, 0.3, 0.3);
    try testing.expect(std.math.isFinite(q[0]) and std.math.isFinite(q[1]));
    w.stagger = 5;
    const q2 = point(w, 0.3, 0.3);
    try testing.expect(std.math.isFinite(q2[0]) and std.math.isFinite(q2[1]));
}
