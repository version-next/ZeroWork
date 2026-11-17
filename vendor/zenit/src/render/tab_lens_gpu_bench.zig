//! Offscreen GPU benchmark of one iOS tab-bar lens composite (the real glass.metal on a live
//! Metal device, MTLCommandBuffer GPUStart/EndTime).
//!
//! Skipped by default; `ZENIT_GLASS_GPU_BENCH=1 zig build test-metal -Doptimize=ReleaseFast`
//! prints the GPU time of one held-lens composite (median / p10 / p90, microseconds).
//! ZENIT_GLASS_BENCH_BASELINE=<file.metal> also builds that shader and alternates the two in the
//! same process (A/B against a frequency-ramped GPU), e.g. the glass.metal of another commit,
//! and prints the largest channel difference of one composite of each (TAB-LENS-GPU-DIFF).
//!
//! The uniforms are the held lens of storybook `glassioslens` as the app encodes them
//! (testdata/tab_lens_held_uniforms.json: texture size, scissor, GlassUniforms); the pipeline is
//! the specialised variant the app would build for them (backdrop_blur.glassVariantKey). The
//! backdrop is a synthetic tab bar: a 210 platter over a 121 strip, the lens overhanging it by
//! 6 pt at the top and bottom like the fixture, so the lens's fold / fringe paths are all taken.
//! One command buffer draws the lens DRAWS times; the per-lens figure is its GPU time / DRAWS.

const std = @import("std");
const gpu = @import("gpu");
const blur = @import("backdrop_blur.zig");
const tab_lens_field = @import("tab_lens_field.zig");

const WARMUP = 20;
const ITERS = 120;
const DRAWS = 64;

const Fixture = struct { tex_w: u32, tex_h: u32, scissor: ?[4]u32, u: blur.GlassUniforms };

/// The GPU objects every draw binds besides its pipeline.
const Binds = struct { backdrop: *gpu.Backend.Texture, sampler: *gpu.Backend.Sampler, field: *gpu.Backend.Buffer };

const Stats = struct { median: f64, p10: f64, p90: f64 };

fn pipelineFor(device: *gpu.Backend.Device, a: std.mem.Allocator, source: []const u8, key: u16) !gpu.Backend.RenderPipeline {
    var prefix: std.ArrayList(u8) = .empty;
    defer prefix.deinit(a);
    for (blur.glass_variant_macros, 0..) |name, bit| {
        const on = key & (@as(u16, 1) << @intCast(bit)) != 0;
        try prefix.print(a, "#define {s} {s}\n", .{ name, if (on) "true" else "false" });
    }
    try prefix.appendSlice(a, source);
    var shader = try gpu.Backend.ShaderModule.initFromSource(device, prefix.items);
    defer shader.deinit();
    var vertex = try shader.getFunction("glass_vertex_main");
    defer vertex.deinit();
    var fragment = try shader.getFunction("glass_fragment_main");
    defer fragment.deinit();
    return gpu.Backend.createRenderPipeline(device, .{
        .vertex_function = &vertex,
        .fragment_function = &fragment,
        .color_attachment_formats = &.{gpu.color_format},
        .blend_state = null,
    });
}

/// GPU time of one command buffer drawing the lens DRAWS times, per lens (us).
fn timeOnce(queue: *gpu.Backend.Queue, pipeline: *gpu.Backend.RenderPipeline, binds: Binds, view: anytype, f: *const Fixture) !?f64 {
    var encoder = try gpu.Backend.CommandEncoder.init(queue);
    var pass = try encoder.beginRenderPass(.{ .color_attachments = &.{.{
        .view = view,
        .load_op = .clear,
        .store_op = .store,
        .clear_value = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
    }} });
    pass.setPipeline(pipeline);
    pass.setFragmentBytes(0, std.mem.asBytes(&f.u));
    for (0..5) |slot| pass.setFragmentTextureBinding(@intCast(slot), binds.backdrop.binding());
    pass.setFragmentSampler(0, binds.sampler);
    pass.setFragmentBuffer(tab_lens_field.slot, binds.field, 0);
    pass.setViewport(0, 0, @floatFromInt(f.tex_w), @floatFromInt(f.tex_h), 0, 1);
    if (f.scissor) |sc| pass.setScissorRect(sc[0], sc[1], sc[2], sc[3]);
    for (0..DRAWS) |_| pass.draw(3, 1, 0, 0);
    pass.end();
    var cb = try encoder.finish();
    defer cb.deinit();
    cb.submit();
    cb.waitUntilCompleted();
    const us = cb.gpuElapsedMicros() orelse return null;
    return @as(f64, @floatFromInt(us)) / DRAWS;
}

fn stats(samples: []f64) Stats {
    std.mem.sort(f64, samples, {}, std.sort.asc(f64));
    const n = samples.len;
    return .{ .median = samples[n / 2], .p10 = samples[n / 10], .p90 = samples[n * 9 / 10] };
}

/// A and B interleaved command buffer by command buffer, so a GPU clock change hits both alike;
/// the ratio is the median of the per-pair ratios.
fn measurePair(queue: *gpu.Backend.Queue, pa: *gpu.Backend.RenderPipeline, pb: ?*gpu.Backend.RenderPipeline, binds: Binds, view: anytype, f: *const Fixture) !struct { a: Stats, b: ?Stats, ratio: ?f64 } {
    var sa: [ITERS]f64 = undefined;
    var sb: [ITERS]f64 = undefined;
    var sr: [ITERS]f64 = undefined;
    var n: usize = 0;
    for (0..WARMUP + ITERS) |i| {
        const ta = try timeOnce(queue, pa, binds, view, f);
        const tb = if (pb) |p| try timeOnce(queue, p, binds, view, f) else null;
        if (i < WARMUP) continue;
        const x = ta orelse continue;
        sa[n] = x;
        if (tb) |y| {
            sb[n] = y;
            sr[n] = x / y;
        }
        n += 1;
    }
    if (n == 0) return error.NoGpuTimestamps;
    return .{
        .a = stats(sa[0..n]),
        .b = if (pb != null) stats(sb[0..n]) else null,
        .ratio = if (pb != null) stats(sr[0..n]).median else null,
    };
}

/// A tab bar under the lens: platter (sRGB 210) across the lens's middle, the 121 strip above and
/// below it where the lens overhangs (6 pt), antialiased over one texel.
fn fillBackdrop(a: std.mem.Allocator, tex: *gpu.Backend.Texture, f: *const Fixture) !void {
    const w = f.tex_w;
    const h = f.tex_h;
    const bytes = try a.alloc(u8, w * h * 4);
    defer a.free(bytes);
    const s = f.u.scale_factor;
    const top = (f.u.content_uv[1] * @as(f32, @floatFromInt(h))) + 6 * s;
    const bottom = ((f.u.content_uv[1] + f.u.content_uv[3]) * @as(f32, @floatFromInt(h))) - 6 * s;
    for (0..h) |y| {
        const yc = @as(f32, @floatFromInt(y)) + 0.5;
        const cover = std.math.clamp(@min(yc - top, bottom - yc) + 0.5, 0, 1);
        const v: u8 = @intFromFloat(@round(121 + (210 - 121) * cover));
        for (0..w) |x| @memcpy(bytes[(y * w + x) * 4 ..][0..4], &[_]u8{ v, v, v, 255 });
    }
    try tex.writeRegion(0, 0, 0, w, h, bytes, w * 4);
}

test "tab lens GPU bench（ZENIT_GLASS_GPU_BENCH=1 时运行）" {
    // SKIP-REASON: Opt-in GPU benchmark; enable ZENIT_GLASS_GPU_BENCH to run.
    if (!@import("zenit_environment").flag("ZENIT_GLASS_GPU_BENCH")) return error.SkipZigTest;
    const a = std.testing.allocator;
    const parsed = try std.json.parseFromSlice(Fixture, a, @embedFile("testdata/tab_lens_held_uniforms.json"), .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    const f = &parsed.value;

    var inst = try gpu.Backend.Instance.init(a, .{});
    defer inst.deinit();
    const adapters = try inst.enumerateAdapters();
    defer a.free(adapters);
    if (adapters.len == 0) return error.MetalAdapterUnavailable;
    var adapter = adapters[0];
    defer adapter.deinit();
    var dq = try adapter.requestDevice(a, .{});
    defer dq.device.deinit();
    defer dq.queue.deinit();

    var backdrop = try dq.device.createTexture(a, .{
        .size = .{ .width = f.tex_w, .height = f.tex_h },
        .format = gpu.color_format,
        .memory = .host_upload,
        .usage = .{ .texture_binding = true },
    });
    defer backdrop.destroy();
    try fillBackdrop(a, &backdrop, f);
    var target = try dq.device.createTexture(a, .{
        .size = .{ .width = f.tex_w, .height = f.tex_h },
        .format = gpu.color_format,
        .usage = .{ .render_attachment = true },
    });
    defer target.destroy();
    var view = target.binding().createView();
    defer view.destroy();
    var sampler = try dq.device.createSampler(a, .{ .min_filter = .linear, .mag_filter = .linear });
    defer sampler.destroy();
    var field = try tab_lens_field.create(a, &dq.device);
    defer field.destroy();
    const binds: Binds = .{ .backdrop = &backdrop, .sampler = &sampler, .field = &field };

    const key = blur.glassVariantKey(&f.u);
    var current = try pipelineFor(&dq.device, a, @embedFile("shaders/glass.metal"), key);
    defer current.deinit();
    var env_buf: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&env_buf);
    const baseline_path = @import("zenit_environment").getOwned(fba.allocator(), "ZENIT_GLASS_BENCH_BASELINE") catch null;
    var baseline: ?gpu.Backend.RenderPipeline = null;
    defer if (baseline) |*p| p.deinit();
    if (baseline_path) |path| {
        const src = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, .limited(4 << 20));
        defer a.free(src);
        baseline = try pipelineFor(&dq.device, a, src, key);
    }

    // ramp the GPU clock (the first rounds run at a lower frequency)
    const pb: ?*gpu.Backend.RenderPipeline = if (baseline) |*p| p else null;
    if (pb) |p| {
        // A host-visible target of its own: the timed one stays private.
        var probe = try dq.device.createTexture(a, .{
            .size = .{ .width = f.tex_w, .height = f.tex_h },
            .format = gpu.color_format,
            .memory = .host_upload,
            .usage = .{ .render_attachment = true, .copy_src = true },
        });
        defer probe.destroy();
        var probe_view = probe.binding().createView();
        defer probe_view.destroy();
        const n = f.tex_w * f.tex_h * 4;
        const pa_px = try a.alloc(u8, n);
        defer a.free(pa_px);
        const pb_px = try a.alloc(u8, n);
        defer a.free(pb_px);
        _ = try timeOnce(&dq.queue, &current, binds, probe_view, f);
        try probe.readBgra8(f.tex_w, f.tex_h, pa_px, f.tex_w * 4);
        _ = try timeOnce(&dq.queue, p, binds, probe_view, f);
        try probe.readBgra8(f.tex_w, f.tex_h, pb_px, f.tex_w * 4);
        var max: u8 = 0;
        var differ: usize = 0;
        for (pa_px, pb_px) |x, y| {
            const d = if (x > y) x - y else y - x;
            max = @max(max, d);
            differ += @intFromBool(d != 0);
        }
        std.debug.print("TAB-LENS-GPU-DIFF: max channel difference {d}, {d} of {d} channels differ\n", .{ max, differ, n });
    }
    for (0..2) |_| _ = try measurePair(&dq.queue, &current, pb, binds, view, f);
    for (0..3) |round| {
        const m = try measurePair(&dq.queue, &current, pb, binds, view, f);
        if (m.b) |bs| {
            std.debug.print("TAB-LENS-GPU-BENCH r{d}: baseline={d:.2}us (p10 {d:.2} p90 {d:.2}) current={d:.2}us (p10 {d:.2} p90 {d:.2}) current/baseline={d:.0}%\n", .{ round, bs.median, bs.p10, bs.p90, m.a.median, m.a.p10, m.a.p90, m.ratio.? * 100 });
        } else {
            std.debug.print("TAB-LENS-GPU-BENCH r{d}: current={d:.2}us (p10 {d:.2} p90 {d:.2})\n", .{ round, m.a.median, m.a.p10, m.a.p90 });
        }
    }
}
