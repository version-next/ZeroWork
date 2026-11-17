/// Progress Component
///
/// Progress bar component supporting determinate / indeterminate modes. View in progress.yix,
/// styles and drawing in styles.yss.
///
/// Features:
/// - Percentage progress (value / status can come from signals)
/// - Status color: normal/success/warning/error (progress_* role tokens)
/// - Indeterminate mode (shiny bar sweeps with frame clock, custom-drawn canvas)
/// - Optional percentage text
const std = @import("std");
const core = @import("../../core.zig");
const Cx = core.Cx;
const Node = core.Node;
const box = core.box;
const Color = core.Color;
const theme = core.theme;
const ConditionalStyle = core.ConditionalStyle;
const reactive = @import("../../reactive.zig");
const Scope = reactive.Scope;
const styles = @import("_styles.yss.zig");

/// Progress bar status.
pub const ProgressStatus = enum {
    normal,
    success,
    @"error",
    warning,

    pub fn color(self: ProgressStatus, t: *const theme.ThemeTokens) Color {
        return styles.statusColor(self, t);
    }
};

/// Indeterminate sweep bar shading: `.gloss` (default) mixes a white highlight into the leading
/// edge and a dark tail into the trailing edge; `.flat` paints the bar in the plain state color.
pub const ProgressSweep = enum { gloss, flat };

/// Create Progress: `W.Progress(.{ .value = upload_ratio, .show_text = true })`
pub const Progress = @import("_progress.yix.zig").Progress;
pub const ProgressProps = @import("_progress.yix.zig").ProgressProps;

/// Tone of one part of a segmented bar: neutral = fg-tertiary, the others the progress-* role
/// tokens (accent = progress-fill).
pub const ProgressTone = enum { neutral, accent, success, warning, danger };

/// One part of a `ProgressSegments` bar: its share (0-100) and tone.
pub const ProgressSegment = struct { value: f32, tone: ProgressTone = .accent };

/// Most parts a `ProgressSegments` bar shows (the rest are dropped).
pub const max_segments: usize = 8;

/// Ring progress: `W.ProgressRing(.{ .value = 23, .size = 12 })` (ring.yix).
pub const ProgressRing = @import("_ring.yix.zig").ProgressRing;
pub const ProgressRingProps = @import("_ring.yix.zig").ProgressRingProps;

/// Segmented progress: `W.ProgressSegments(.{ .segments = &parts })` (segments.yix).
pub const ProgressSegments = @import("_segments.yix.zig").ProgressSegments;
pub const ProgressSegmentsProps = @import("_segments.yix.zig").ProgressSegmentsProps;

// ========== Tests ==========

test "Progress: basic" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try box(ctx, .{ .width = .{ .px = 300 }, .height = .{ .px = 50 } }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const progress = try Progress(.{ .value = 75 }).mount(scope, ctx);

    try root.appendChild(std.testing.allocator, progress);

    // Container has 1 child: track.
    try std.testing.expectEqual(@as(usize, 1), progress.children.items.len);

    // Track has 1 child: fill.
    const track = progress.children.items[0];
    try std.testing.expectEqual(@as(usize, 1), track.children.items.len);
}

test "Progress: indeterminate custom draw emits display list gradient" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setViewport(300, 60);

    const root = try box(ctx, .{ .width = .{ .px = 300 }, .height = .{ .px = 60 } }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const progress = try Progress(.{ .indeterminate = true }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, progress);

    ctx.layout();
    _ = ctx.render();

    var saw_gradient = false;
    for (ctx.display_list.items.items) |item| {
        switch (item) {
            .multi_gradient_rect => |grad| {
                if (grad.direction == .horizontal and grad.w > 0 and grad.h > 0) {
                    saw_gradient = true;
                    break;
                }
            },
            else => {},
        }
    }
    try std.testing.expect(saw_gradient);
}

test "Progress: indeterminate custom draw replays own content from display list" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setViewport(300, 60);

    const root = try box(ctx, .{ .width = .{ .px = 300 }, .height = .{ .px = 60 } }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const progress = try Progress(.{ .indeterminate = true }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, progress);

    ctx.layout();
    ctx.perf.display_list_own_replay_count = 0;
    _ = ctx.render();
    const commands = ctx.lowerForEncoderPaintTable();

    try std.testing.expect(ctx.perf.display_list_own_replay_count >= 1);

    var saw_gradient = false;
    for (commands) |cmd| {
        if (cmd.isGradient() and cmd.mg_stop_count > 0) {
            // multi_gradient_rect in paint_table distinguished by mg_stop_count > 0; direction
            // field not separately stored (paint_table simplification), geom.w/h > 0 suffices to
            // validate.
            if (cmd.geom.w > 0 and cmd.geom.h > 0) {
                saw_gradient = true;
                break;
            }
        }
    }
    try std.testing.expect(saw_gradient);
}

test "Progress: with text" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try box(ctx, .{ .width = .{ .px = 300 }, .height = .{ .px = 50 } }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const progress = try Progress(.{ .value = 50, .show_text = true }).mount(scope, ctx);

    try root.appendChild(std.testing.allocator, progress);

    // Container has 2 children: track + text.
    try std.testing.expectEqual(@as(usize, 2), progress.children.items.len);
}

test "Progress: status colors" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try box(ctx, .{ .width = .{ .px = 300 }, .height = .{ .px = 100 } }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const normal = try Progress(.{ .value = 80, .status = .normal }).mount(scope, ctx);
    const success_p = try Progress(.{ .value = 100, .status = .success }).mount(scope, ctx);
    const err = try Progress(.{ .value = 30, .status = .@"error" }).mount(scope, ctx);

    try root.appendChild(std.testing.allocator, normal);
    try root.appendChild(std.testing.allocator, success_p);
    try root.appendChild(std.testing.allocator, err);

    try std.testing.expectEqual(@as(usize, 3), root.children.items.len);
}

test "Progress: clamp value" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try box(ctx, .{ .width = .{ .px = 300 }, .height = .{ .px = 50 } }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    // Over 100 should clamp.
    const progress = try Progress(.{ .value = 150 }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, progress);

    const track = progress.children.items[0];
    const fill = track.children.items[0];
    try std.testing.expectEqual(core.Sizing{ .percent = 100 }, fill.style.width);
}

test "Progress: indeterminate" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try box(ctx, .{ .width = .{ .px = 300 }, .height = .{ .px = 50 } }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const progress = try Progress(.{ .indeterminate = true }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, progress);

    const track = progress.children.items[0];
    // Indeterminate mode: 1 custom-drawn child, redrawn each frame; reports busy not value.
    try std.testing.expectEqual(@as(usize, 1), track.children.items.len);
    const draw_node = track.children.items[0];
    try std.testing.expect(draw_node.hasBeforeRenderHooks());
    try std.testing.expect(draw_node.meta.per_frame.custom_hooks.draw != null);
    const a11y = progress.behavior.interaction.a11y.?;
    try std.testing.expect(a11y.busy);
    try std.testing.expect(a11y.value_range == null);
}

test "Progress: 光泽条只由绝对时间决定，入场展开、离场收窄" {
    const cycle: f64 = styles.cycle_seconds * 1000.0;
    const start = styles.barAt(0);
    try std.testing.expect(start.right - start.left < 0.05);
    const mid = styles.barAt(cycle * 0.5);
    try std.testing.expect(mid.right - mid.left > 0.2);
    const again = styles.barAt(cycle * 3.5); // Same phase across cycles.
    try std.testing.expectApproxEqAbs(mid.left, again.left, 0.0001);
    try std.testing.expectApproxEqAbs(mid.right, again.right, 0.0001);
}

test "Progress: render emits visible fill and percent text" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setViewport(320, 80);

    const root = try box(ctx, .{
        .width = .{ .px = 320 },
        .height = .{ .px = 80 },
        .background = ctx.tokens.tokens.color.bg_primary,
    }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const progress = try Progress(.{
        .value = 70,
        .status = .success,
        .show_text = true,
        .width = 240,
    }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, progress);

    ctx.layout();
    _ = ctx.render();
    const commands = ctx.lowerForEncoderPaintTable();

    var saw_track = false;
    var saw_fill = false;
    var saw_text = false;
    // COMPONENTS.json Progress / 65%: flat semantic track surface.
    const expected_track = ctx.tokens.tokens.color.progress_track;
    for (commands) |cmd| {
        if (cmd.isFillRect()) {
            if (Color.eql(cmd.color.toColor(), expected_track) and cmd.geom.w >= 160 and cmd.geom.h >= 4) {
                saw_track = true;
            }
        } else if (cmd.isGradient() and cmd.mg_stop_count > 0) {
            if (cmd.geom.w >= 100 and cmd.geom.h >= 4) {
                saw_fill = true;
            }
        } else if (cmd.isText()) {
            if (std.mem.eql(u8, cmd.text_content, "70%")) saw_text = true;
        }
    }

    try std.testing.expect(saw_track);
    try std.testing.expect(saw_fill);
    try std.testing.expect(saw_text);
}

// Test collection from styles.yss, this line required, see docs/STYLING.md.
test {
    _ = @import("_styles.yss.zig");
}

// Per-allocation point OOM sweep, see src/ui/components/oom_sweep.zig.
test "progress: mount 在任意分配点失败时不泄漏（sweep）" {
    const sw = @import("../oom_sweep.zig");
    try sw.sweepMount("progress", struct {
        fn m(scope: *sw.Scope, cx: *sw.Cx) anyerror!?*sw.Node {
            return try Progress(.{ .value = 75 }).mount(scope, cx);
        }
    }.m);
}

test "progress(indeterminate): mount 在任意分配点失败时不泄漏（sweep）" {
    const sw = @import("../oom_sweep.zig");
    try sw.sweepMount("progress(indeterminate)", struct {
        fn m(scope: *sw.Scope, cx: *sw.Cx) anyerror!?*sw.Node {
            return try Progress(.{ .indeterminate = true }).mount(scope, cx);
        }
    }.m);
}

// -- Signal-first behavior --

test "Progress: value and status follow their sources" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const root = try box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 100 } }, .{});
    ctx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const done = try scope.createSignal(f32, 10);
    const status = reactive.map(done, struct {
        fn s(v: f32) ProgressStatus {
            return if (v >= 100) .success else .normal;
        }
    }.s);
    const progress = try Progress(.{ .value = done, .status = status, .show_text = true }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, progress);
    if (reactive.SignalOwner.debug_checks) try std.testing.expectEqual(@as(u32, 0), ctx.owner.debug.mount_tracked_reads);
    const fill = progress.children.items[0].children.items[0];
    const text_node = progress.children.items[1];
    try std.testing.expectEqual(core.Sizing{ .percent = 10 }, fill.style.width);
    try std.testing.expectEqualStrings("10%", text_node.getText().?.content);

    done.set(64);
    try std.testing.expectEqual(core.Sizing{ .percent = 64 }, fill.style.width);
    try std.testing.expectEqualStrings("64%", text_node.getText().?.content);
    try std.testing.expectEqual(@as(?f32, 64), progress.behavior.interaction.a11y.?.value_now);
    const normal_mid = fill.style.ext.?.multi_gradient.?.stops[1].color;

    done.set(250); // Clamp to 100, status switches success.
    try std.testing.expectEqual(core.Sizing{ .percent = 100 }, fill.style.width);
    try std.testing.expect(!Color.eql(normal_mid, fill.style.ext.?.multi_gradient.?.stops[1].color));
    try std.testing.expect(Color.eql(ProgressStatus.success.color(ctx.tokens), fill.style.ext.?.multi_gradient.?.stops[1].color));
}

test "Progress: static props add no effects (zero-cost static)" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const before = ctx.owner.graph.countByKind().get(.effect);
    const p = try Progress(.{ .value = 30, .status = .success, .show_text = true }).mount(scope, ctx);
    defer ctx.freeNode(p);
    try std.testing.expectEqual(before, ctx.owner.graph.countByKind().get(.effect));
}

test "progress(value signal): mount 在任意分配点失败时不泄漏（sweep）" {
    try @import("../oom_sweep.zig").sweepMount("progress(signal)", struct {
        fn m(scope: *Scope, cx: *Cx) anyerror!?*Node {
            const v = try scope.createSignal(f32, 42);
            return try Progress(.{ .value = v, .show_text = true }).mount(scope, cx);
        }
    }.m);
}

/// Stop colors of the first horizontal sweep bar in the display list.
fn sweepStops(ctx: *Cx) ?[3]Color {
    for (ctx.display_list.items.items) |item| switch (item) {
        .multi_gradient_rect => |grad| if (grad.direction == .horizontal and grad.w > 0) return grad.stop_colors[0..3].*,
        else => {},
    };
    return null;
}

fn renderSweep(t: *const theme.ThemeTokens, props: anytype) ![3]Color {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setTheme(t);
    ctx.setViewport(300, 60);
    const root = try box(ctx, .{ .width = .{ .px = 300 }, .height = .{ .px = 60 } }, .{});
    ctx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    try root.appendChild(std.testing.allocator, try Progress(props).mount(scope, ctx));
    ctx.layout();
    _ = ctx.render();
    return sweepStops(ctx) orelse error.NoSweep;
}

test "Progress: status fills read the progress_* role tokens (defaults = accent / success / warning / danger)" {
    inline for (.{ &theme.light, &theme.dark, &theme.high_contrast }) |t| {
        const c = t.tokens.color;
        try std.testing.expectEqual(c.accent, ProgressStatus.normal.color(t));
        try std.testing.expectEqual(c.success, ProgressStatus.success.color(t));
        try std.testing.expectEqual(c.warning, ProgressStatus.warning.color(t));
        try std.testing.expectEqual(c.danger, ProgressStatus.@"error".color(t));
    }
    var custom = theme.light;
    custom.tokens.color.progress_fill = Color.hex(0x111111);
    custom.tokens.color.progress_success = Color.hex(0x222222);
    custom.tokens.color.progress_warning = Color.hex(0x333333);
    custom.tokens.color.progress_error = Color.hex(0x444444);
    try std.testing.expectEqual(Color.hex(0x111111), ProgressStatus.normal.color(&custom));
    try std.testing.expectEqual(Color.hex(0x222222), ProgressStatus.success.color(&custom));
    try std.testing.expectEqual(Color.hex(0x333333), ProgressStatus.warning.color(&custom));
    try std.testing.expectEqual(Color.hex(0x444444), ProgressStatus.@"error".color(&custom));

    // Mounted: the determinate fill and the indeterminate sweep follow the role.
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setTheme(&custom);
    const root = try box(ctx, .{ .width = .{ .px = 300 }, .height = .{ .px = 50 } }, .{});
    ctx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const p = try Progress(.{ .value = 50, .status = .warning }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, p);
    const fill = p.children.items[0].children.items[0];
    try std.testing.expectEqual(Color.hex(0x333333), fill.style.ext.?.multi_gradient.?.stops[1].color);
    try std.testing.expectEqual(Color.hex(0x111111), (try renderSweep(&custom, .{ .indeterminate = true }))[1]);
}

test "Progress: sweep = .flat paints the indeterminate bar in the plain state color; .gloss (default) keeps the highlight" {
    const t = &theme.light;
    const c = ProgressStatus.normal.color(t);
    const white = Color.rgba(255, 255, 255, 255);
    const black = Color.rgba(0, 0, 0, 255);
    const gloss = try renderSweep(t, .{ .indeterminate = true });
    try std.testing.expectEqual(Color.lerp(c, white, 0.35), gloss[0]);
    try std.testing.expectEqual(c, gloss[1]);
    try std.testing.expectEqual(Color.lerp(c, black, 0.15), gloss[2]);
    const flat = try renderSweep(t, .{ .indeterminate = true, .sweep = .flat });
    try std.testing.expectEqual([3]Color{ c, c, c }, flat);
    const flat_ok = try renderSweep(t, .{ .indeterminate = true, .status = .success, .sweep = .flat });
    const s = ProgressStatus.success.color(t);
    try std.testing.expectEqual([3]Color{ s, s, s }, flat_ok);
}

// ========== ProgressRing / ProgressSegments ==========

test "ProgressRing: track circle plus the share clockwise from 12 o'clock, size square" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setViewport(100, 40);
    const root = try box(ctx, .{ .width = .{ .px = 100 }, .height = .{ .px = 40 }, .align_items = .start }, .{});
    ctx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const value = try scope.createSignal(f32, 25);
    const ring = try ProgressRing(.{ .value = value, .size = 12 }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, ring);
    ctx.layout();
    _ = ctx.render();
    const r = ring.rectFromWorldOrFallback();
    try std.testing.expectApproxEqAbs(@as(f32, 12), r.w, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 12), r.h, 0.01);
    try std.testing.expectEqual(core.A11yRole.progressbar, ring.behavior.interaction.a11y.?.role);
    try std.testing.expectApproxEqAbs(@as(f32, 25), ring.behavior.interaction.a11y.?.value_now, 0.01);

    const arcs = struct {
        fn collect(c: *Cx, out: *[4]@FieldType(core.display_list.DisplayItem, "arc")) usize {
            var n: usize = 0;
            for (c.display_list.items.items) |item| switch (item) {
                .arc => |a| if (n < out.len) {
                    out[n] = a;
                    n += 1;
                },
                else => {},
            };
            return n;
        }
    };
    var found: [4]@FieldType(core.display_list.DisplayItem, "arc") = undefined;
    try std.testing.expectEqual(@as(usize, 2), arcs.collect(ctx, &found));
    const t = ctx.tokens.tokens.color;
    try std.testing.expect(Color.eql(found[0].color, t.progress_track));
    try std.testing.expectApproxEqAbs(std.math.tau, found[0].end_angle - found[0].start_angle, 0.001);
    try std.testing.expect(Color.eql(found[1].color, t.progress_fill));
    try std.testing.expectApproxEqAbs(-std.math.pi / 2.0, found[1].start_angle, 0.001);
    try std.testing.expectApproxEqAbs(std.math.tau * 0.25, found[1].end_angle - found[1].start_angle, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 6), found[1].outer_radius, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 2), found[1].stroke_width, 0.01);

    // A new value repaints with the new share; 0 draws the track only.
    value.set(60);
    ctx.layout();
    _ = ctx.render();
    try std.testing.expectEqual(@as(usize, 2), arcs.collect(ctx, &found));
    try std.testing.expectApproxEqAbs(std.math.tau * 0.6, found[1].end_angle - found[1].start_angle, 0.001);
    value.set(0);
    ctx.layout();
    _ = ctx.render();
    try std.testing.expectEqual(@as(usize, 1), arcs.collect(ctx, &found));
}

test "ProgressSegments: parts by share in their tones, remainder in the track, round ends, gaps" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setViewport(272, 40);
    const root = try box(ctx, .{ .width = .{ .px = 272 }, .height = .{ .px = 40 }, .direction = .column }, .{});
    ctx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const first = [_]ProgressSegment{ .{ .value = 25, .tone = .neutral }, .{ .value = 25, .tone = .accent }, .{ .value = 10, .tone = .success } };
    const parts = try scope.createSignal([]const ProgressSegment, &first);
    const bar = try ProgressSegments(.{ .segments = parts }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, bar);
    ctx.layout();
    // Control-flow anchors ({for} / {if}) sit between the parts: read the painted parts only.
    const Parts = struct {
        fn of(node: *Node, out: *[8]*Node) []*Node {
            var n: usize = 0;
            for (node.children.items) |child| if (child.style.display != .none and child.getBackground().a > 0) {
                out[n] = child;
                n += 1;
            };
            return out[0..n];
        }
    };
    var buf: [8]*Node = undefined;
    var shown = Parts.of(bar, &buf);

    const t = ctx.tokens.tokens.color;
    const r = bar.rectFromWorldOrFallback();
    try std.testing.expectApproxEqAbs(@as(f32, 272), r.w, 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 4), r.h, 0.01);
    try std.testing.expect(bar.style.overflow_hidden);
    try std.testing.expectApproxEqAbs(@as(f32, 60), bar.behavior.interaction.a11y.?.value_now, 0.01);
    try std.testing.expectEqual(@as(usize, 4), shown.len);
    const colors = [_]Color{ t.fg_tertiary, t.progress_fill, t.progress_success, t.progress_track };
    var x = r.x;
    var total: f32 = 0;
    for (shown, 0..) |seg, i| {
        const sr = seg.rectFromWorldOrFallback();
        try std.testing.expect(Color.eql(seg.getBackground(), colors[i]));
        try std.testing.expectApproxEqAbs(@as(f32, 4), sr.h, 0.01);
        if (i > 0) try std.testing.expectApproxEqAbs(x + 2, sr.x, 0.5);
        x = sr.x + sr.w;
        total += sr.w;
    }
    // The parts and the three 2-pt gaps exactly fill the bar.
    try std.testing.expectApproxEqAbs(r.w, total + 3 * 2, 0.5);
    // Shares keep their proportions (25 : 25 : 10).
    const w0 = shown[0].rectFromWorldOrFallback().w;
    const w2 = shown[2].rectFromWorldOrFallback().w;
    try std.testing.expectApproxEqAbs(w0, shown[1].rectFromWorldOrFallback().w, 0.5);
    try std.testing.expectApproxEqAbs(w0 * 0.4, w2, 1.0);

    // Over 100: the last part is clamped to what is left and the remainder disappears.
    const full = [_]ProgressSegment{ .{ .value = 70, .tone = .warning }, .{ .value = 50, .tone = .danger } };
    parts.set(&full);
    ctx.layout();
    shown = Parts.of(bar, &buf);
    try std.testing.expectEqual(@as(usize, 2), shown.len);
    try std.testing.expect(Color.eql(shown[0].getBackground(), t.progress_warning));
    try std.testing.expect(Color.eql(shown[1].getBackground(), t.progress_error));
    const a = shown[0].rectFromWorldOrFallback().w;
    const b = shown[1].rectFromWorldOrFallback().w;
    try std.testing.expectApproxEqAbs(r.w, a + b + 2, 0.5);
    try std.testing.expectApproxEqAbs(a * 30.0 / 70.0, b, 1.0);
}
