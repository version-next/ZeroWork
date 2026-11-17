//! Anchor motion: the geometry and clock of "collapse into an anchor / expand out of it"
//! (macOS Dock minimize). `.anchor` draws a genie mesh warp of the content by default
//! (`Tokens.shape = .genie`, geometry in src/genie_warp.zig); `.affine` is the curved path +
//! scale + fade picture, which is also what renderers without a mesh composite draw.
//!
//! Pure and window-free: the runtime (`ui/anchor_transition.zig`) feeds it the home rect (where
//! the content rests), the anchor rect (where it goes) and the frame clock, and draws the
//! returned `Frame`. Design: docs/ANCHOR_TRANSITION.md.
//!
//! One progress value drives both directions: 0 = at home, 1 = in the anchor. Collapsing moves
//! it toward 1, expanding toward 0, at a per-direction rate. Retargeting only flips the
//! direction, so a reversal mid-flight continues from the current state (no queue, no jump);
//! the shape is a fixed function of progress, so the picture is continuous across the flip.
//!
//! `Tokens.mode = .fade_scale` is the in-place alternative (ZeroWork Z12b): no travel, the
//! content fades out while shrinking slightly about its own center (to `fade_scale_end_scale`),
//! and the reverse on the way in. Same clock, same reversal rules, same reduced-motion fallback.
const std = @import("std");
const Easing = @import("easing.zig").Easing;
pub const genie_warp = @import("zenit_genie_warp");
pub const GenieWarp = genie_warp.Warp;

pub const Rect = struct {
    x: f32 = 0,
    y: f32 = 0,
    w: f32 = 0,
    h: f32 = 0,

    pub fn centerX(r: Rect) f32 {
        return r.x + r.w * 0.5;
    }

    pub fn centerY(r: Rect) f32 {
        return r.y + r.h * 0.5;
    }

    pub fn approxEql(a: Rect, b: Rect, tolerance: f32) bool {
        return @abs(a.x - b.x) <= tolerance and @abs(a.y - b.y) <= tolerance and
            @abs(a.w - b.w) <= tolerance and @abs(a.h - b.h) <= tolerance;
    }

    pub fn isFinite(r: Rect) bool {
        return std.math.isFinite(r.x) and std.math.isFinite(r.y) and std.math.isFinite(r.w) and std.math.isFinite(r.h);
    }
};

/// What "reduce motion" (system accessibility setting) turns the transition into.
pub const ReducedMotion = enum {
    /// Fade in place (no displacement, no scale). Apple HIG: a dissolve is safe.
    fade,
    /// Show / hide at once.
    instant,
};

/// The shape of a run.
pub const Mode = enum {
    /// Fly into the anchor: curved path, scale onto the anchor rect, fade (Z12).
    anchor,
    /// Stay in place: fade out while shrinking slightly about the home center, reverse on the
    /// way in (Z12b). The anchor is not used.
    fade_scale,
};

/// The picture of an `.anchor` run.
pub const Shape = enum {
    /// Genie (macOS Dock minimize): the content's texture on a mesh is pulled into the anchor by
    /// its near edge (src/genie_warp.zig). Renderers without a mesh composite draw `.affine`.
    genie,
    /// Curved path + scale onto the anchor rect + fade (the first tier).
    affine,
};

/// Motion tokens. `default_tokens` is the house style; callers override per transition.
pub const Tokens = struct {
    /// `.anchor` (fly into the anchor) or `.fade_scale` (fade and shrink in place).
    mode: Mode = .anchor,
    /// `.anchor`: genie mesh warp (default) or the curved path + scale (`.affine`).
    shape: Shape = .genie,
    /// Genie grid: cells along the direction of travel (the bending rows) and across it.
    genie_rows: u8 = 32,
    genie_cols: u8 = 8,
    /// Genie suction: share of the run by which the far edge trails the edge facing the anchor.
    genie_stagger: f32 = 0.35,
    /// Genie suction: how much faster a row narrows to the anchor's width than it travels.
    genie_squeeze: f32 = 0.6,
    /// Genie: seconds for a full collapse / expand.
    genie_collapse_duration_s: f32 = 0.36,
    genie_expand_duration_s: f32 = 0.40,
    /// Genie: progress at which the content starts to fade into the anchor (to `end_opacity`).
    genie_fade_start: f32 = 0.6,
    /// Seconds for a full collapse (home -> anchor).
    collapse_duration_s: f32 = 0.28,
    /// Seconds for a full expand (anchor -> home).
    expand_duration_s: f32 = 0.32,
    /// Maps linear progress to path / size progress. Symmetric curves keep reversals smooth.
    easing: Easing = .ease_in_out_cubic,
    /// How an expand moves through that shape over time: the eased shape distance still to cover
    /// follows `1 - expand_easing(t)`, so an ease-out starts at full speed out of the anchor and
    /// settles softly at home (macOS window / Dock restore), instead of the symmetric curve's slow
    /// start where the content barely leaves the anchor for the first frames. Only the clock
    /// changes: the picture stays a function of progress, so reversals stay continuous.
    /// null = expand on the same linear clock as collapse.
    expand_easing: ?Easing = .ease_out_cubic,
    /// Path bend: 0 = straight line between the centers; 1 = the quadratic control point sits at
    /// (anchor center x, home center y), so the content first swings toward the anchor's column
    /// and then drops into it. Negative values bend the other way.
    path_bend: f32 = 0.6,
    /// Progress at which the fade starts (before it the content is fully opaque).
    fade_start: f32 = 0.35,
    /// Opacity when the content sits in the anchor.
    end_opacity: f32 = 0.0,
    /// Size lag: > 0 shrinks ahead of the motion (Dock-like suction), 0 = in step with it.
    scale_lead: f32 = 0.25,
    reduced: ReducedMotion = .fade,
    /// Seconds for the reduced-motion fade (either direction).
    reduced_duration_s: f32 = 0.15,
    /// `.fade_scale`: scale at the end of a fade-out (and the start of a fade-in), about the
    /// home center. 1 = pure fade.
    fade_scale_end_scale: f32 = 0.97,
    /// `.fade_scale`: seconds for a full fade-out.
    fade_scale_out_duration_s: f32 = 0.18,
    /// `.fade_scale`: seconds for a full fade-in.
    fade_scale_in_duration_s: f32 = 0.22,

    pub fn durationFor(self: Tokens, direction: Direction, reduced: bool) f32 {
        if (reduced) return if (self.reduced == .instant) 0 else self.reduced_duration_s;
        return switch (self.mode) {
            .anchor => switch (direction) {
                .collapse => if (self.shape == .genie) self.genie_collapse_duration_s else self.collapse_duration_s,
                .expand => if (self.shape == .genie) self.genie_expand_duration_s else self.expand_duration_s,
            },
            .fade_scale => switch (direction) {
                .collapse => self.fade_scale_out_duration_s,
                .expand => self.fade_scale_in_duration_s,
            },
        };
    }

    /// Whether a run needs an anchor rect (`.fade_scale` stays in place).
    pub fn usesAnchor(self: Tokens) bool {
        return self.mode == .anchor;
    }

    /// Whether `.anchor` runs draw the genie mesh.
    pub fn genie(self: Tokens) bool {
        return self.mode == .anchor and self.shape == .genie;
    }
};

pub const default_tokens: Tokens = .{};

/// The in-place preset (Z12b): `.fade_scale` with the house durations and scale.
pub const fade_scale_tokens: Tokens = .{ .mode = .fade_scale };

/// The first-tier picture (curved path + scale + fade), no mesh warp.
pub const affine_tokens: Tokens = .{ .shape = .affine };

pub const Direction = enum { collapse, expand };

pub const Phase = enum {
    /// At rest at home (progress 0).
    expanded,
    collapsing,
    /// At rest in the anchor (progress 1).
    collapsed,
    expanding,

    pub fn isAnimating(self: Phase) bool {
        return self == .collapsing or self == .expanding;
    }
};

/// What to draw. Affine pictures map the content's home rect onto `rect`; a genie frame warps it
/// through `genie` (window coordinates), `rect` is then the warped node's bounds and
/// `fallback_rect` the affine picture drawn by renderers without a mesh composite.
pub const Frame = struct {
    rect: Rect,
    opacity: f32,
    genie: ?GenieWarp = null,
    fallback_rect: ?Rect = null,

    /// The rect the affine composite maps the home rect onto.
    pub fn affineRect(self: Frame) Rect {
        return self.fallback_rect orelse self.rect;
    }
};

fn arr(r: Rect) [4]f32 {
    return .{ r.x, r.y, r.w, r.h };
}

/// Genie frame at `progress`: the mesh warp from `home` into `anchor` (exactly the anchor rect at
/// 1), opacity 1 until `genie_fade_start`, then easing to `end_opacity`. The affine first-tier frame
/// rides along as the fallback picture.
pub fn genieFrameAt(home: Rect, anchor: Rect, progress: f32, tokens: Tokens) Frame {
    const p = std.math.clamp(progress, 0, 1);
    var affine_tokens_ = tokens;
    affine_tokens_.shape = .affine;
    const fallback = frameAt(home, anchor, p, affine_tokens_);
    if (p <= 0) return .{ .rect = home, .opacity = 1 };
    const w: GenieWarp = .{
        .active = 1,
        .direction = @intFromEnum(genie_warp.chooseDirection(arr(home), arr(anchor))),
        .rows = tokens.genie_rows,
        .cols = tokens.genie_cols,
        .local = .{ 0, 0, home.w, home.h },
        .home = arr(home),
        .anchor = arr(anchor),
        .progress = p,
        .stagger = tokens.genie_stagger,
        .squeeze = tokens.genie_squeeze,
    };
    const b = genie_warp.bounds(w);
    const fade = smoothstep(std.math.clamp(tokens.genie_fade_start, 0, 0.999), 1, p);
    const opacity = std.math.clamp(lerp(1, tokens.end_opacity, fade), 0, 1);
    return .{ .rect = .{ .x = b[0], .y = b[1], .w = b[2], .h = b[3] }, .opacity = opacity, .genie = w, .fallback_rect = fallback.rect };
}

fn lerp(a: f32, b: f32, t: f32) f32 {
    return a + (b - a) * t;
}

fn smoothstep(edge0: f32, edge1: f32, x: f32) f32 {
    if (edge1 <= edge0) return if (x >= edge1) 1 else 0;
    const t = std.math.clamp((x - edge0) / (edge1 - edge0), 0, 1);
    return t * t * (3 - 2 * t);
}

/// Geometry at `progress` (0 = home, 1 = anchor). Pure: same inputs, same frame. The rect's
/// center follows a quadratic curve from the home center to the anchor center; its size moves
/// from the home size to the anchor size (exactly the anchor rect at progress 1); opacity holds
/// at 1 until `fade_start`, then eases to `end_opacity`.
pub fn frameAt(home: Rect, anchor: Rect, progress: f32, tokens: Tokens) Frame {
    if (tokens.mode == .fade_scale) return fadeScaleFrameAt(home, progress, tokens);
    if (tokens.shape == .genie) return genieFrameAt(home, anchor, progress, tokens);
    const p = std.math.clamp(progress, 0, 1);
    if (p <= 0) return .{ .rect = home, .opacity = 1 };
    if (p >= 1) return .{ .rect = anchor, .opacity = std.math.clamp(tokens.end_opacity, 0, 1) };
    const e = std.math.clamp(tokens.easing.apply(p), -0.25, 1.25);
    // Size leads the motion: progress through the size change runs ahead by scale_lead, so the
    // content is already small when it travels the last stretch (suction).
    const lead = std.math.clamp(tokens.scale_lead, 0, 0.9);
    const es = std.math.clamp(tokens.easing.apply(std.math.clamp(p * (1 + lead), 0, 1)), 0, 1.25);

    const h_cx = home.centerX();
    const h_cy = home.centerY();
    const a_cx = anchor.centerX();
    const a_cy = anchor.centerY();
    const mid_x = (h_cx + a_cx) * 0.5;
    const mid_y = (h_cy + a_cy) * 0.5;
    const k_x = lerp(mid_x, a_cx, tokens.path_bend);
    const k_y = lerp(mid_y, h_cy, tokens.path_bend);
    const u = 1 - e;
    const cx = u * u * h_cx + 2 * u * e * k_x + e * e * a_cx;
    const cy = u * u * h_cy + 2 * u * e * k_y + e * e * a_cy;

    const w = @max(lerp(home.w, anchor.w, es), 0);
    const h = @max(lerp(home.h, anchor.h, es), 0);
    const fade = smoothstep(std.math.clamp(tokens.fade_start, 0, 0.999), 1, p);
    const opacity = std.math.clamp(lerp(1, tokens.end_opacity, fade), 0, 1);
    return .{ .rect = .{ .x = cx - w * 0.5, .y = cy - h * 0.5, .w = w, .h = h }, .opacity = opacity };
}

/// `.fade_scale` frame at `progress` (0 = shown, 1 = gone): the home rect scaled about its center
/// from 1 to `fade_scale_end_scale`, opacity from 1 to `end_opacity`, both along `easing`. Pure;
/// at progress 0 it is exactly the home rect at full opacity.
pub fn fadeScaleFrameAt(home: Rect, progress: f32, tokens: Tokens) Frame {
    const p = std.math.clamp(progress, 0, 1);
    const end_opacity = std.math.clamp(tokens.end_opacity, 0, 1);
    if (p <= 0) return .{ .rect = home, .opacity = 1 };
    const end_scale = if (std.math.isFinite(tokens.fade_scale_end_scale)) std.math.clamp(tokens.fade_scale_end_scale, 0, 2) else 1;
    const e: f32 = if (p >= 1) 1 else std.math.clamp(tokens.easing.apply(p), 0, 1);
    const s = lerp(1, end_scale, e);
    const w = @max(home.w * s, 0);
    const h = @max(home.h * s, 0);
    const opacity = std.math.clamp(lerp(1, end_opacity, e), 0, 1);
    return .{ .rect = .{ .x = home.centerX() - w * 0.5, .y = home.centerY() - h * 0.5, .w = w, .h = h }, .opacity = opacity };
}

/// Reduced-motion frame: the content stays at home and only fades (1 at home, 0 in the anchor).
pub fn reducedFrameAt(home: Rect, progress: f32) Frame {
    return .{ .rect = home, .opacity = 1 - std.math.clamp(progress, 0, 1) };
}

/// Where a collapse may aim when the anchor is clipped: slide `anchor` into `bounds` (keeping
/// its size, capped to the bounds), so an anchor scrolled out of a tab strip resolves to the
/// strip's nearest visible end instead of a point off screen. Bounds with no area leave the
/// anchor unchanged.
pub fn clampAnchor(anchor: Rect, bounds: Rect) Rect {
    if (bounds.w <= 0 or bounds.h <= 0) return anchor;
    const w = @min(@max(anchor.w, 0), bounds.w);
    const h = @min(@max(anchor.h, 0), bounds.h);
    return .{
        .x = std.math.clamp(anchor.x, bounds.x, bounds.x + bounds.w - w),
        .y = std.math.clamp(anchor.y, bounds.y, bounds.y + bounds.h - h),
        .w = w,
        .h = h,
    };
}

/// Inverse of a monotonic easing on [0, 1] (bisection; non-monotonic curves get a usable root).
fn invertEasing(e: anytype, y: f32) f32 {
    const target = std.math.clamp(y, 0, 1);
    if (target <= 0) return 0;
    if (target >= 1) return 1;
    var lo: f32 = 0;
    var hi: f32 = 1;
    var i: usize = 0;
    while (i < 40) : (i += 1) {
        const mid = (lo + hi) * 0.5;
        if (e.apply(mid) < target) lo = mid else hi = mid;
    }
    return (lo + hi) * 0.5;
}

/// One expand step of `delta` (share of a full run) on the `curve` clock: `shape(progress)` is the
/// eased distance from home, and it shrinks as `1 - curve(t)`. Returns the new progress (0 = home);
/// never moves backwards.
pub fn expandStep(progress: f32, delta: f32, shape: anytype, curve: Easing) f32 {
    const p = std.math.clamp(progress, 0, 1);
    if (p <= 0) return 0;
    const g = std.math.clamp(shape.apply(p), 0, 1);
    const t = invertEasing(curve, 1 - g);
    const next_t = t + @max(delta, 0);
    if (next_t >= 1) return 0;
    const next_g = 1 - std.math.clamp(curve.apply(next_t), 0, 1);
    const next = invertEasing(shape, next_g);
    return std.math.clamp(@min(next, p), 0, 1);
}

/// How far a genie picture is from home at a progress. The expand clock shrinks this distance as
/// `1 - expand_easing(t)`, so the whole mesh, not just an eased scalar, settles softly at home.
pub const GenieDistance = struct {
    stagger: f32,
    squeeze: f32,

    pub fn of(tokens: Tokens) GenieDistance {
        return .{ .stagger = tokens.genie_stagger, .squeeze = tokens.genie_squeeze };
    }

    /// Mean row weight (across and along the travel) over the rows of the mesh: 0 at home, 1 in
    /// the anchor, strictly increasing in between, so the expand clock moves every row smoothly.
    /// (A weight on the furthest row would land smoother but makes a reversal mid-run lurch.)
    pub fn apply(self: GenieDistance, p: f32) f32 {
        const w: GenieWarp = .{ .progress = std.math.clamp(p, 0, 1), .stagger = self.stagger, .squeeze = self.squeeze };
        const rows = 8;
        var sum: f32 = 0;
        var i: usize = 0;
        while (i <= rows) : (i += 1) {
            const weights = genie_warp.rowWeights(w, @as(f32, @floatFromInt(i)) / rows);
            sum += weights[0] + weights[1];
        }
        return sum / (2 * (rows + 1));
    }
};

/// The clock: progress plus the direction it is moving in.
pub const Motion = struct {
    /// 0 = home, 1 = anchor.
    progress: f32 = 0,
    /// 0 or 1.
    target: f32 = 0,

    pub fn collapsed() Motion {
        return .{ .progress = 1, .target = 1 };
    }

    pub fn phase(self: Motion) Phase {
        if (self.progress == self.target) return if (self.target >= 1) .collapsed else .expanded;
        return if (self.target >= 1) .collapsing else .expanding;
    }

    pub fn direction(self: Motion) Direction {
        return if (self.target >= 1) .collapse else .expand;
    }

    /// Head for `dir` from wherever the motion is now. Returns true when this changed the
    /// target (a new run or a reversal); asking again for the current direction is a no-op.
    pub fn retarget(self: *Motion, dir: Direction) bool {
        const t: f32 = if (dir == .collapse) 1 else 0;
        if (self.target == t) return false;
        self.target = t;
        return true;
    }

    /// Jump to rest in the current direction.
    pub fn finish(self: *Motion) void {
        self.progress = self.target;
    }

    /// Advance by `dt_s` seconds. Returns true while still moving. The rate is a full run per
    /// `durationFor(direction)`, so a reversal at progress p takes p (or 1 - p) of a run.
    pub fn step(self: *Motion, dt_s: f32, tokens: Tokens, reduced: bool) bool {
        if (self.progress == self.target) return false;
        const dur = tokens.durationFor(self.direction(), reduced);
        const dt = if (std.math.isFinite(dt_s)) @max(dt_s, 0) else 0;
        if (dur <= 0.0001) {
            self.progress = self.target;
            return false;
        }
        const delta = dt / dur;
        if (self.target > self.progress) {
            self.progress = @min(self.target, self.progress + delta);
        } else if (!reduced and tokens.expand_easing != null) {
            self.progress = if (tokens.genie())
                expandStep(self.progress, delta, GenieDistance.of(tokens), tokens.expand_easing.?)
            else
                expandStep(self.progress, delta, tokens.easing, tokens.expand_easing.?);
        } else {
            self.progress = @max(self.target, self.progress - delta);
        }
        return self.progress != self.target;
    }

    /// The frame for the current progress. Reduced motion is a pure fade in place for every mode.
    pub fn frame(self: Motion, home: Rect, anchor: Rect, tokens: Tokens, reduced: bool) Frame {
        return if (reduced) reducedFrameAt(home, self.progress) else frameAt(home, anchor, self.progress, tokens);
    }
};

// ---------------------------------------------------------------------------------------------
// Tests (window-free: geometry, timing, reversal, reduced motion)

const testing = std.testing;
const home_rect: Rect = .{ .x = 300, .y = 200, .w = 520, .h = 354 };
const tab_rect: Rect = .{ .x = 120, .y = 8, .w = 140, .h = 28 };

test "anchor motion: frame starts at home and lands exactly on the anchor" {
    const t = affine_tokens;
    const start = frameAt(home_rect, tab_rect, 0, t);
    try testing.expect(start.rect.approxEql(home_rect, 0.0001));
    try testing.expectEqual(@as(f32, 1), start.opacity);
    const end = frameAt(home_rect, tab_rect, 1, t);
    try testing.expect(end.rect.approxEql(tab_rect, 0.0001));
    try testing.expectEqual(@as(f32, 0), end.opacity);
    // Just short of the end the rect has converged onto the anchor (continuity at 1).
    const near = frameAt(home_rect, tab_rect, 0.999, t);
    try testing.expect(near.rect.approxEql(tab_rect, 1.0));
}

test "anchor motion: path is curved, size and opacity are monotonic" {
    const t = affine_tokens;
    var prev = frameAt(home_rect, tab_rect, 0, t);
    var max_dev: f32 = 0;
    var i: usize = 1;
    while (i <= 40) : (i += 1) {
        const p = @as(f32, @floatFromInt(i)) / 40;
        const f = frameAt(home_rect, tab_rect, p, t);
        try testing.expect(f.rect.w <= prev.rect.w + 0.001);
        try testing.expect(f.rect.h <= prev.rect.h + 0.001);
        try testing.expect(f.opacity <= prev.opacity + 0.0001);
        // Distance of the center from the straight home->anchor line.
        const ax = home_rect.centerX();
        const ay = home_rect.centerY();
        const bx = tab_rect.centerX();
        const by = tab_rect.centerY();
        const len = @sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay));
        const dev = @abs((bx - ax) * (ay - f.rect.centerY()) - (ax - f.rect.centerX()) * (by - ay)) / len;
        max_dev = @max(max_dev, dev);
        prev = f;
    }
    // A visible arc, not a straight slide.
    try testing.expect(max_dev > 20);
    // Opaque until fade_start.
    try testing.expectEqual(@as(f32, 1), frameAt(home_rect, tab_rect, t.fade_start, t).opacity);
    // A straight path when the bend is 0.
    var straight = t;
    straight.path_bend = 0;
    straight.easing = .linear;
    const mid = frameAt(home_rect, tab_rect, 0.5, straight);
    try testing.expectApproxEqAbs((home_rect.centerX() + tab_rect.centerX()) / 2, mid.rect.centerX(), 0.01);
    try testing.expectApproxEqAbs((home_rect.centerY() + tab_rect.centerY()) / 2, mid.rect.centerY(), 0.01);
}

test "anchor motion: timing follows the per-direction duration" {
    // Linear clock both ways (the expand ease-out clock has its own test).
    var t = affine_tokens;
    t.expand_easing = null;
    var m: Motion = .{};
    try testing.expectEqual(Phase.expanded, m.phase());
    try testing.expect(m.retarget(.collapse));
    try testing.expectEqual(Phase.collapsing, m.phase());
    try testing.expect(m.step(t.collapse_duration_s / 2, t, false));
    try testing.expectApproxEqAbs(@as(f32, 0.5), m.progress, 0.0001);
    try testing.expect(!m.step(t.collapse_duration_s, t, false));
    try testing.expectEqual(@as(f32, 1), m.progress);
    try testing.expectEqual(Phase.collapsed, m.phase());
    // Same direction again: no new run.
    try testing.expect(!m.retarget(.collapse));
    try testing.expect(m.retarget(.expand));
    try testing.expect(m.step(t.expand_duration_s / 4, t, false));
    try testing.expectApproxEqAbs(@as(f32, 0.75), m.progress, 0.0001);
    // Bad clock input does not move or poison progress.
    try testing.expect(m.step(std.math.nan(f32), t, false));
    try testing.expect(m.step(-1, t, false));
    try testing.expectApproxEqAbs(@as(f32, 0.75), m.progress, 0.0001);
}

test "anchor motion: reversal mid-flight continues from the current state" {
    var t = affine_tokens;
    t.expand_easing = null;
    var m: Motion = .{};
    _ = m.retarget(.collapse);
    _ = m.step(t.collapse_duration_s * 0.4, t, false);
    const before = m.frame(home_rect, tab_rect, t, false);
    try testing.expect(m.retarget(.expand));
    try testing.expectEqual(Phase.expanding, m.phase());
    // Same picture on the frame of the flip.
    const at_flip = m.frame(home_rect, tab_rect, t, false);
    try testing.expect(at_flip.rect.approxEql(before.rect, 0.0001));
    try testing.expectEqual(before.opacity, at_flip.opacity);
    // The way back takes the remaining share of an expand, not a full run.
    try testing.expect(m.step(t.expand_duration_s * 0.39, t, false));
    try testing.expect(!m.step(t.expand_duration_s * 0.02, t, false));
    try testing.expectEqual(Phase.expanded, m.phase());
    try testing.expect(m.frame(home_rect, tab_rect, t, false).rect.approxEql(home_rect, 0.0001));
    // Rapid toggling never jumps: every flip keeps the frame.
    var n: Motion = .{};
    var k: usize = 0;
    while (k < 12) : (k += 1) {
        _ = n.retarget(if (k % 2 == 0) .collapse else .expand);
        const a = n.frame(home_rect, tab_rect, t, false);
        _ = n.step(0.016, t, false);
        const b = n.frame(home_rect, tab_rect, t, false);
        // One 16 ms step moves the center far less than the whole distance.
        try testing.expect(@abs(a.rect.centerY() - b.rect.centerY()) < 60);
    }
}

test "anchor motion: reduced motion fades in place or switches at once" {
    var t = affine_tokens;
    var m: Motion = .{};
    _ = m.retarget(.collapse);
    try testing.expectEqual(t.reduced_duration_s, t.durationFor(.collapse, true));
    _ = m.step(t.reduced_duration_s / 2, t, true);
    const f = m.frame(home_rect, tab_rect, t, true);
    try testing.expect(f.rect.approxEql(home_rect, 0.0001));
    try testing.expectApproxEqAbs(@as(f32, 0.5), f.opacity, 0.0001);
    t.reduced = .instant;
    var n: Motion = .{};
    _ = n.retarget(.collapse);
    try testing.expect(!n.step(0, t, true));
    try testing.expectEqual(Phase.collapsed, n.phase());
}

test "anchor motion: degenerate anchors and clamping" {
    const t = affine_tokens;
    // A zero-size anchor: the content shrinks to a point at it, no NaN.
    const point: Rect = .{ .x = 40, .y = 10 };
    var p: f32 = 0;
    while (p <= 1) : (p += 0.125) {
        const f = frameAt(home_rect, point, p, t);
        try testing.expect(f.rect.isFinite());
        try testing.expect(f.rect.w >= 0 and f.rect.h >= 0);
    }
    // An anchor scrolled out of its strip slides to the strip's nearest end.
    const strip: Rect = .{ .x = 80, .y = 6, .w = 400, .h = 32 };
    const off_right = clampAnchor(.{ .x = 700, .y = 8, .w = 120, .h = 28 }, strip);
    try testing.expect(off_right.approxEql(.{ .x = 360, .y = 8, .w = 120, .h = 28 }, 0.0001));
    const off_left = clampAnchor(.{ .x = -300, .y = 8, .w = 120, .h = 28 }, strip);
    try testing.expectEqual(@as(f32, 80), off_left.x);
    const inside = clampAnchor(tab_rect, strip);
    try testing.expect(inside.approxEql(tab_rect, 0.0001));
    try testing.expect(clampAnchor(tab_rect, .{}).approxEql(tab_rect, 0));
}

test "anchor motion: fade_scale fades and shrinks in place, never travels" {
    const t = fade_scale_tokens;
    try testing.expect(!t.usesAnchor());
    try testing.expectEqual(@as(f32, 0.97), t.fade_scale_end_scale);
    const start = frameAt(home_rect, tab_rect, 0, t);
    try testing.expect(start.rect.approxEql(home_rect, 0.0001));
    try testing.expectEqual(@as(f32, 1), start.opacity);
    const end = frameAt(home_rect, tab_rect, 1, t);
    try testing.expectEqual(@as(f32, 0), end.opacity);
    try testing.expectApproxEqAbs(home_rect.w * 0.97, end.rect.w, 0.001);
    try testing.expectApproxEqAbs(home_rect.h * 0.97, end.rect.h, 0.001);
    var prev = start;
    var i: usize = 1;
    while (i <= 40) : (i += 1) {
        const p = @as(f32, @floatFromInt(i)) / 40;
        const f = frameAt(home_rect, tab_rect, p, t);
        // Centered on home the whole way: the anchor is ignored.
        try testing.expectApproxEqAbs(home_rect.centerX(), f.rect.centerX(), 0.001);
        try testing.expectApproxEqAbs(home_rect.centerY(), f.rect.centerY(), 0.001);
        // Shrinks (only slightly) and fades monotonically.
        try testing.expect(f.rect.w <= prev.rect.w + 0.0001 and f.rect.w >= home_rect.w * 0.97 - 0.001);
        try testing.expect(f.opacity <= prev.opacity + 0.0001);
        prev = f;
    }
    // Same frame whatever the anchor is (none resolved = the home rect).
    const mid_a = frameAt(home_rect, tab_rect, 0.4, t);
    const mid_b = frameAt(home_rect, home_rect, 0.4, t);
    try testing.expect(mid_a.rect.approxEql(mid_b.rect, 0.0001));
    try testing.expectEqual(mid_a.opacity, mid_b.opacity);
    // The scale is a token: 1 = pure fade.
    var flat = t;
    flat.fade_scale_end_scale = 1;
    try testing.expect(frameAt(home_rect, tab_rect, 0.7, flat).rect.approxEql(home_rect, 0.0001));
    // Bad token values do not produce NaN.
    var bad = t;
    bad.fade_scale_end_scale = std.math.nan(f32);
    try testing.expect(frameAt(home_rect, tab_rect, 0.5, bad).rect.isFinite());
}

test "anchor motion: fade_scale timing, reversal and reduced motion" {
    var t = fade_scale_tokens;
    t.expand_easing = null;
    try testing.expectEqual(t.fade_scale_out_duration_s, t.durationFor(.collapse, false));
    try testing.expectEqual(t.fade_scale_in_duration_s, t.durationFor(.expand, false));
    try testing.expectEqual(t.reduced_duration_s, t.durationFor(.collapse, true));
    var m: Motion = .{};
    _ = m.retarget(.collapse);
    try testing.expect(m.step(t.fade_scale_out_duration_s / 2, t, false));
    try testing.expectApproxEqAbs(@as(f32, 0.5), m.progress, 0.0001);
    // Reversal mid-flight: same picture on the flip, remaining share of a fade-in to get back.
    const before = m.frame(home_rect, tab_rect, t, false);
    try testing.expect(m.retarget(.expand));
    const at_flip = m.frame(home_rect, tab_rect, t, false);
    try testing.expect(at_flip.rect.approxEql(before.rect, 0.0001));
    try testing.expectEqual(before.opacity, at_flip.opacity);
    try testing.expect(m.step(t.fade_scale_in_duration_s * 0.49, t, false));
    try testing.expect(!m.step(t.fade_scale_in_duration_s * 0.02, t, false));
    try testing.expectEqual(Phase.expanded, m.phase());
    // Reduced motion: pure fade, no scale.
    var n: Motion = .{};
    _ = n.retarget(.collapse);
    _ = n.step(t.reduced_duration_s / 2, t, true);
    const f = n.frame(home_rect, tab_rect, t, true);
    try testing.expect(f.rect.approxEql(home_rect, 0.0001));
    try testing.expectApproxEqAbs(@as(f32, 0.5), f.opacity, 0.0001);
}

test "anchor motion: expand starts fast out of the anchor and settles softly at home" {
    const t = affine_tokens;
    try testing.expect(t.expand_easing != null);
    const dt: f32 = 1.0 / 60.0;
    var m = Motion.collapsed();
    _ = m.retarget(.expand);
    // Distance from home along the eased shape, per frame.
    var shapes: [64]f32 = undefined;
    var n: usize = 0;
    shapes[n] = t.easing.apply(m.progress);
    n += 1;
    while (m.step(dt, t, false)) {
        shapes[n] = t.easing.apply(m.progress);
        n += 1;
    }
    shapes[n] = 0;
    n += 1;
    // Same duration as the linear clock (within a frame).
    try testing.expect(@abs(@as(f32, @floatFromInt(n - 1)) * dt - t.expand_duration_s) <= dt + 0.0001);
    // Fast start: the first frame already covers a visible share of the way (the symmetric clock
    // covers well under 1% in its first frame); the largest steps come early.
    try testing.expect(1 - shapes[1] > 0.1);
    // Soft landing, no overshoot: monotonic, the last steps are the smallest.
    var i: usize = 1;
    while (i < n) : (i += 1) try testing.expect(shapes[i] <= shapes[i - 1] + 0.0001);
    const first = shapes[0] - shapes[1];
    const last = shapes[n - 2] - shapes[n - 1];
    try testing.expect(last < first * 0.1);
    // Visible from the first frame (the symmetric clock is still transparent there).
    try testing.expect(frameAt(home_rect, tab_rect, expandStep(1, dt / t.expand_duration_s, t.easing, t.expand_easing.?), t).opacity > 0.2);
    // A reversal keeps the picture: flipping a collapse at progress p resumes from p.
    var r: Motion = .{};
    _ = r.retarget(.collapse);
    _ = r.step(t.collapse_duration_s * 0.5, t, false);
    const p = r.progress;
    const before = r.frame(home_rect, tab_rect, t, false);
    _ = r.retarget(.expand);
    try testing.expect(r.frame(home_rect, tab_rect, t, false).rect.approxEql(before.rect, 0.0001));
    try testing.expect(r.step(dt, t, false));
    try testing.expect(r.progress < p and r.progress > p - 0.3);
    // Reduced motion keeps its linear fade.
    var q = Motion.collapsed();
    _ = q.retarget(.expand);
    _ = q.step(t.reduced_duration_s / 2, t, true);
    try testing.expectApproxEqAbs(@as(f32, 0.5), q.progress, 0.0001);
    // No time, no motion.
    try testing.expectApproxEqAbs(@as(f32, 0.5), expandStep(0.5, 0, t.easing, t.expand_easing.?), 0.0001);
}

test "anchor motion: genie is the default picture, lands on the anchor and pinches its near edge first" {
    const t = default_tokens;
    try testing.expectEqual(Shape.genie, t.shape);
    try testing.expect(t.genie());
    const start = frameAt(home_rect, tab_rect, 0, t);
    try testing.expect(start.rect.approxEql(home_rect, 0.001));
    try testing.expectEqual(@as(f32, 1), start.opacity);
    const end = frameAt(home_rect, tab_rect, 1, t);
    try testing.expect(end.rect.approxEql(tab_rect, 0.01));
    const mid = frameAt(home_rect, tab_rect, 0.35, t);
    const w = mid.genie.?;
    try testing.expectEqual(genie_warp.Direction.up, w.dir());
    // The edge facing the tab (top) is narrower than the far edge (bottom).
    const tl = genie_warp.point(w, 0, 0);
    const tr = genie_warp.point(w, 1, 0);
    const bl = genie_warp.point(w, 0, 1);
    const br = genie_warp.point(w, 1, 1);
    try testing.expect(tr[0] - tl[0] < br[0] - bl[0]);
    // Opaque through most of the run (a genie does not dissolve on its way), fading at the end.
    try testing.expectEqual(@as(f32, 1), mid.opacity);
    try testing.expect(frameAt(home_rect, tab_rect, 0.95, t).opacity < 0.5);
    // The affine picture rides along for renderers without a mesh composite.
    try testing.expect(mid.fallback_rect != null);
    try testing.expectEqual(t.genie_collapse_duration_s, t.durationFor(.collapse, false));
    try testing.expectEqual(t.genie_expand_duration_s, t.durationFor(.expand, false));
    try testing.expectEqual(affine_tokens.collapse_duration_s, affine_tokens.durationFor(.collapse, false));
}

test "anchor motion: genie frames are continuous across a reversal" {
    const t = default_tokens;
    var m: Motion = .{};
    _ = m.retarget(.collapse);
    _ = m.step(t.genie_collapse_duration_s * 0.5, t, false);
    const before = m.frame(home_rect, tab_rect, t, false);
    _ = m.retarget(.expand);
    const after = m.frame(home_rect, tab_rect, t, false);
    try testing.expect(before.rect.approxEql(after.rect, 0.001));
    _ = m.step(1.0 / 60.0, t, false);
    const next = m.frame(home_rect, tab_rect, t, false);
    // One frame back is about one frame of motion: compare with a forward collapse frame here.
    var fwd: Motion = .{};
    _ = fwd.retarget(.collapse);
    _ = fwd.step(t.genie_collapse_duration_s * 0.5, t, false);
    const f0 = fwd.frame(home_rect, tab_rect, t, false);
    _ = fwd.step(1.0 / 60.0, t, false);
    const f1 = fwd.frame(home_rect, tab_rect, t, false);
    const forward = @abs(f1.rect.centerX() - f0.rect.centerX()) + @abs(f1.rect.centerY() - f0.rect.centerY());
    const back = @abs(next.rect.centerX() - after.rect.centerX()) + @abs(next.rect.centerY() - after.rect.centerY());
    try testing.expect(back > 0);
    try testing.expect(back <= forward * 2.5 + 1);
    try testing.expect(!next.rect.approxEql(home_rect, 20));
}
