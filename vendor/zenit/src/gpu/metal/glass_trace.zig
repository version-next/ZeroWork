//! Glass pass trace (docs/WEB_GLASS_DESIGN.md §5, P0).
//!
//! Records every GPU operation of the glass composites of one frame — render
//! passes, pipelines, textures, samplers, fragment bytes, draws and copies —
//! plus a CPU-readable snapshot of every pass target and copy destination,
//! so the web glass executor can replay the frame on WebGPU and compare each
//! intermediate with the native result.
//!
//! Off unless ZENIT_GLASS_TRACE=<dir>. Creating `<dir>/arm` arms one frame:
//! the glass composites of the next frame that draws glass are recorded
//! between `enter` and `leave` (backdrop_blur.applyBackdropBlur); at submit
//! the frame is waited on and written to `<dir>/trace.json`, `<dir>/blob.bin`
//! and `<dir>/snap_<n>.bin`, `arm` is removed and `<dir>/done` written.
//! Record with ZENIT_GLASS_RENDER_BANKS=1 ZENIT_GLASS_NO_FRAME_QUARTER=1
//! ZENIT_GLASS_GENERAL_ONLY=1 so the trace is self-contained and uses only the
//! portable passes (each is bit-identical to the path it replaces).
//!
//! Only passes that begin inside a glass section are recorded. A copy whose
//! source was not produced inside the trace (the main render target) is a
//! *seed*: the replay loads the destination's snapshot instead of copying.
const std = @import("std");
const gpu = @import("../gpu.zig");
const mtl = @import("metal_bindings.zig");
const resources = @import("resources.zig");
const pipeline_mod = @import("pipeline.zig");

const alloc = std.heap.page_allocator;

const State = enum { off, idle, recording, done };

const Tex = struct { raw: *mtl.MTLTexture, w: u32, h: u32, fmt: c_ulong, produced: bool = false };
const Snap = struct { tex: u32, after: u32, raw: *mtl.MTLTexture, w: u32, h: u32, bpp: u32 };

var state: State = .idle;
var checked_env = false;
var dir_buf: [512]u8 = undefined;
var dir: []const u8 = "";
var depth: u32 = 0;

var json: std.Io.Writer.Allocating = undefined;
var blob: std.ArrayListUnmanaged(u8) = .empty;
var textures: std.ArrayListUnmanaged(Tex) = .empty;
var samplers: std.ArrayListUnmanaged(*mtl.MTLSamplerState) = .empty;
var sampler_json: std.Io.Writer.Allocating = undefined;
var pipelines: std.ArrayListUnmanaged(*mtl.MTLRenderPipelineState) = .empty;
var pipeline_json: std.Io.Writer.Allocating = undefined;
var buffers: std.ArrayListUnmanaged(*mtl.MTLBuffer) = .empty;
var buffer_json: std.Io.Writer.Allocating = undefined;
var snaps: std.ArrayListUnmanaged(Snap) = .empty;
var event_count: u32 = 0;
var command_buffer: ?*mtl.MTLCommandBuffer = null;
var next_pass: u32 = 1;
var pass_target: u32 = 0;
var section: u32 = 0;
var live_pass: u32 = 0;
var live_section: u32 = 0;
var warnings: u32 = 0;

fn enabled() bool {
    if (!checked_env) {
        checked_env = true;
        const v = std.c.getenv("ZENIT_GLASS_TRACE") orelse {
            state = .off;
            return false;
        };
        const s = std.mem.span(v);
        if (s.len == 0 or s.len >= dir_buf.len) {
            state = .off;
            return false;
        }
        @memcpy(dir_buf[0..s.len], s);
        dir = dir_buf[0..s.len];
    }
    return state != .off;
}

fn path(comptime fmt: []const u8, args: anytype) [:0]const u8 {
    const S = struct {
        var buf: [768]u8 = undefined;
    };
    return std.fmt.bufPrintSentinel(&S.buf, "{s}/" ++ fmt, .{dir} ++ args, 0) catch "";
}

/// Glass section start (backdrop_blur.applyBackdropBlur). Arms on `<dir>/arm`.
pub fn enter(owner: u32, rect: [4]f32) void {
    if (!enabled()) return;
    if (state == .done and mtl.metal_trace_file_exists(path("arm", .{})) != 0 and
        mtl.metal_trace_file_exists(path("done", .{})) == 0) state = .idle;
    if (state == .idle) {
        if (mtl.metal_trace_file_exists(path("arm", .{})) == 0) return;
        begin();
    }
    if (state != .recording) return;
    depth += 1;
    if (depth == 1) {
        // Each glass section is self-contained: what it reads but did not
        // produce comes from the frame (seed copies).
        for (textures.items) |*t| t.produced = false;
        section += 1;
        event("{{\"op\":\"glass\",\"owner\":{d},\"rect\":[{d},{d},{d},{d}]}}", .{ owner, rect[0], rect[1], rect[2], rect[3] });
    }
}

pub fn leave() void {
    if (state != .recording or depth == 0) return;
    depth -= 1;
}

/// True while a glass section is being recorded (callers bypass cross-frame
/// reuse so every composite of the traced frame is encoded).
pub fn active() bool {
    return state == .recording or (state == .idle and enabled() and mtl.metal_trace_file_exists(path("arm", .{})) != 0);
}

fn recording() bool {
    return state == .recording and depth > 0;
}

/// The pass `id` began in the current glass section (a pass carried over
/// from an earlier section, the restored main pass, is not replayed).
pub fn live(id: u32) bool {
    return id != 0 and id == live_pass and live_section == section and recording();
}

fn begin() void {
    json = .init(alloc);
    sampler_json = .init(alloc);
    pipeline_json = .init(alloc);
    buffer_json = .init(alloc);
    blob = .empty;
    textures = .empty;
    samplers = .empty;
    pipelines = .empty;
    buffers = .empty;
    snaps = .empty;
    event_count = 0;
    command_buffer = null;
    next_pass = 1;
    warnings = 0;
    state = .recording;
}

fn event(comptime fmt: []const u8, args: anytype) void {
    const w = &json.writer;
    if (event_count > 0) w.writeAll(",\n") catch {};
    w.print(fmt, args) catch {};
    event_count += 1;
}

fn texId(raw: *mtl.MTLTexture, w: u32, h: u32) u32 {
    const fmt = mtl.metal_texture_pixel_format(raw);
    var i = textures.items.len;
    while (i > 0) {
        i -= 1;
        const t = textures.items[i];
        if (t.raw == raw) {
            if (t.w == w and t.h == h and t.fmt == fmt) return @intCast(i);
            break; // address reused by a different texture
        }
    }
    textures.append(alloc, .{ .raw = raw, .w = w, .h = h, .fmt = fmt }) catch return 0;
    return @intCast(textures.items.len - 1);
}

fn bytesPerPixel(fmt: c_ulong) u32 {
    return switch (fmt) {
        10, 11, 12, 13 => 1, // r8
        70, 71, 80, 81, 72, 73, 74 => 4, // rgba8 / bgra8
        115 => 8, // rgba16Float
        125 => 16, // rgba32Float
        25 => 2, // r16Float
        55 => 4, // r32Float
        65 => 4, // rg16Float
        else => 0,
    };
}

fn snapshot(cb: *mtl.MTLCommandBuffer, tex: u32) void {
    const t = textures.items[tex];
    const bpp = bytesPerPixel(t.fmt);
    if (bpp == 0) {
        warnings += 1;
        event("{{\"op\":\"warn\",\"msg\":\"unsupported snapshot format {d}\",\"tex\":{d}}}", .{ t.fmt, tex });
        return;
    }
    const raw = mtl.metal_trace_snapshot(cb, t.raw) orelse return;
    snaps.append(alloc, .{ .tex = tex, .after = event_count - 1, .raw = raw, .w = t.w, .h = t.h, .bpp = bpp }) catch {};
}

// ---- hooks (command_encoder.zig) ----

pub fn onBeginPass(cb: *mtl.MTLCommandBuffer, desc: gpu.RenderPassDescriptor) u32 {
    if (!recording()) return 0;
    if (desc.color_attachments.len != 1 or desc.depth_stencil_attachment != null) {
        warnings += 1;
        event("{{\"op\":\"warn\",\"msg\":\"pass with {d} color attachments / depth not traced\"}}", .{desc.color_attachments.len});
        return 0;
    }
    command_buffer = cb;
    const a = desc.color_attachments[0];
    const raw = a.view.raw;
    const tex = texId(raw, @intCast(mtl.metal_trace_texture_width(raw)), @intCast(mtl.metal_trace_texture_height(raw)));
    pass_target = tex;
    const id = next_pass;
    next_pass += 1;
    live_pass = id;
    live_section = section;
    const c = a.clear_value;
    event("{{\"op\":\"pass\",\"id\":{d},\"target\":{d},\"load\":\"{s}\",\"clear\":[{d},{d},{d},{d}]}}", .{ id, tex, @tagName(a.load_op), c.r, c.g, c.b, c.a });
    return id;
}

pub fn onPipeline(p: *const pipeline_mod.RenderPipeline) void {
    if (!recording()) return;
    var id: ?usize = null;
    for (pipelines.items, 0..) |raw, i| if (raw == p.raw) {
        id = i;
        break;
    };
    if (id == null) {
        pipelines.append(alloc, p.raw) catch return;
        id = pipelines.items.len - 1;
        const w = &pipeline_json.writer;
        if (id.? > 0) w.writeAll(",\n") catch {};
        const t = p.trace;
        w.print("{{\"id\":{d},\"vertex\":\"{s}\",\"fragment\":\"{s}\",\"format\":\"{s}\",\"blend\":", .{ id.?, std.mem.sliceTo(&t.vertex, 0), std.mem.sliceTo(&t.fragment, 0), if (t.format) |f| @tagName(f) else "" }) catch {};
        if (t.blend) |b| {
            w.print("{{\"src_rgb\":\"{s}\",\"dst_rgb\":\"{s}\",\"op_rgb\":\"{s}\",\"src_a\":\"{s}\",\"dst_a\":\"{s}\",\"op_a\":\"{s}\"}}}}", .{ @tagName(b.source_rgb), @tagName(b.destination_rgb), @tagName(b.rgb_operation), @tagName(b.source_alpha), @tagName(b.destination_alpha), @tagName(b.alpha_operation) }) catch {};
        } else w.writeAll("null}") catch {};
    }
    event("{{\"op\":\"pipeline\",\"p\":{d}}}", .{id.?});
}

pub fn onViewport(x: f32, y: f32, w: f32, h: f32) void {
    if (!recording()) return;
    event("{{\"op\":\"viewport\",\"x\":{d},\"y\":{d},\"w\":{d},\"h\":{d}}}", .{ x, y, w, h });
}

pub fn onScissor(x: u32, y: u32, w: u32, h: u32) void {
    if (!recording()) return;
    event("{{\"op\":\"scissor\",\"x\":{d},\"y\":{d},\"w\":{d},\"h\":{d}}}", .{ x, y, w, h });
}

pub fn onTexture(slot: u32, raw: ?*mtl.MTLTexture) void {
    if (!recording()) return;
    const r = raw orelse return event("{{\"op\":\"tex\",\"slot\":{d},\"t\":null}}", .{slot});
    const tex = texId(r, @intCast(mtl.metal_trace_texture_width(r)), @intCast(mtl.metal_trace_texture_height(r)));
    if (!textures.items[tex].produced) {
        warnings += 1;
        event("{{\"op\":\"warn\",\"msg\":\"sampled texture not produced in trace\",\"tex\":{d}}}", .{tex});
    }
    event("{{\"op\":\"tex\",\"slot\":{d},\"t\":{d}}}", .{ slot, tex });
}

pub fn onSampler(slot: u32, s: ?*const resources.Sampler) void {
    if (!recording()) return;
    const smp = s orelse return event("{{\"op\":\"sampler\",\"slot\":{d},\"s\":null}}", .{slot});
    var id: ?usize = null;
    for (samplers.items, 0..) |raw, i| if (raw == smp.raw) {
        id = i;
        break;
    };
    if (id == null) {
        samplers.append(alloc, smp.raw) catch return;
        id = samplers.items.len - 1;
        const w = &sampler_json.writer;
        if (id.? > 0) w.writeAll(",\n") catch {};
        const d = smp.trace;
        w.print("{{\"id\":{d},\"min\":\"{s}\",\"mag\":\"{s}\",\"mip\":\"{s}\",\"u\":\"{s}\",\"v\":\"{s}\"}}", .{ id.?, @tagName(d.min_filter), @tagName(d.mag_filter), @tagName(d.mipmap_filter), @tagName(d.address_mode_u), @tagName(d.address_mode_v) }) catch {};
    }
    event("{{\"op\":\"sampler\",\"slot\":{d},\"s\":{d}}}", .{ slot, id.? });
}

pub fn onUnsupported(comptime what: []const u8) void {
    if (!recording()) return;
    warnings += 1;
    event("{{\"op\":\"warn\",\"msg\":\"" ++ what ++ " not traced\"}}", .{});
}

pub fn onRawSampler(slot: u32) void {
    if (!recording()) return;
    warnings += 1;
    event("{{\"op\":\"warn\",\"msg\":\"raw sampler at slot {d} (descriptor unknown)\"}}", .{slot});
}

pub fn onBytes(slot: u32, data: []const u8) void {
    if (!recording()) return;
    const off = blob.items.len;
    blob.appendSlice(alloc, data) catch return;
    // 16-byte align the next record so the replay can view it as f32/u32.
    while (blob.items.len % 16 != 0) blob.append(alloc, 0) catch return;
    event("{{\"op\":\"bytes\",\"slot\":{d},\"off\":{d},\"len\":{d}}}", .{ slot, off, data.len });
}

pub fn onBuffer(slot: u32, b: *const resources.Buffer, offset: u64) void {
    if (!recording()) return;
    var id: ?usize = null;
    for (buffers.items, 0..) |raw, i| if (raw == b.raw) {
        id = i;
        break;
    };
    if (id == null) {
        const contents = mtl.metal_buffer_contents(b.raw) orelse {
            warnings += 1;
            return event("{{\"op\":\"warn\",\"msg\":\"private buffer at slot {d}\"}}", .{slot});
        };
        const len = mtl.metal_buffer_get_length(b.raw);
        const off = blob.items.len;
        blob.appendSlice(alloc, @as([*]const u8, @ptrCast(contents))[0..len]) catch return;
        while (blob.items.len % 16 != 0) blob.append(alloc, 0) catch return;
        buffers.append(alloc, b.raw) catch return;
        id = buffers.items.len - 1;
        const w = &buffer_json.writer;
        if (id.? > 0) w.writeAll(",\n") catch {};
        w.print("{{\"id\":{d},\"off\":{d},\"len\":{d}}}", .{ id.?, off, len }) catch {};
    }
    event("{{\"op\":\"buffer\",\"slot\":{d},\"b\":{d},\"offset\":{d}}}", .{ slot, id.?, offset });
}

pub fn onDraw(vertex_count: u32, instance_count: u32, first_vertex: u32, first_instance: u32, strip: bool) void {
    if (!recording()) return;
    event("{{\"op\":\"draw\",\"vc\":{d},\"ic\":{d},\"fv\":{d},\"fi\":{d},\"strip\":{}}}", .{ vertex_count, instance_count, first_vertex, first_instance, strip });
}

/// After endEncoding of a traced pass: snapshot its target.
pub fn onEnd(cb: *mtl.MTLCommandBuffer) void {
    // A pass that ends outside the glass section (the restored main pass)
    // keeps drawing the frame: it is not replayed.
    if (!recording()) return;
    event("{{\"op\":\"end\"}}", .{});
    textures.items[pass_target].produced = true;
    snapshot(cb, pass_target);
}

/// The glass result drawn into the frame (backdrop_blur's image-renderer
/// composite): `transform` maps the quad's local 0..w x 0..h (logical px)
/// to the target, `rotate` applies about the quad centre (rect form).
pub fn onComposite(binding: resources.TextureBinding, w: f32, h: f32, uv: [4]f32, tint: [4]f32, radii: [4]f32, transform: [6]f32, rotate: f32, scale: f32, offscreen: u32, premultiplied: bool, world: [4]f32) void {
    if (!recording()) return;
    const raw = binding.raw;
    const tex = texId(raw, @intCast(mtl.metal_trace_texture_width(raw)), @intCast(mtl.metal_trace_texture_height(raw)));
    event("{{\"op\":\"composite\",\"t\":{d},\"w\":{d},\"h\":{d},\"uv\":[{d},{d},{d},{d}],\"tint\":[{d},{d},{d},{d}],\"radii\":[{d},{d},{d},{d}],\"transform\":[{d},{d},{d},{d},{d},{d}],\"rotate\":{d},\"scale\":{d},\"offscreen\":{d},\"premultiplied\":{},\"world\":[{d},{d},{d},{d}]}}", .{
        tex,          w,            h,            uv[0],        uv[1],        uv[2],        uv[3],
        tint[0],      tint[1],      tint[2],      tint[3],      radii[0],     radii[1],     radii[2],
        radii[3],     transform[0], transform[1], transform[2], transform[3], transform[4], transform[5],
        rotate,       scale,        offscreen,    premultiplied, world[0], world[1], world[2], world[3],
    });
}

/// After a copy has been encoded (blit or render copy).
pub fn onCopy(cb: *mtl.MTLCommandBuffer, src: resources.TextureBinding, sx: u32, sy: u32, w: u32, h: u32, dst: resources.TextureBinding, dx: u32, dy: u32, clear: bool, render: bool) void {
    if (!recording()) return;
    command_buffer = cb;
    const s = texId(src.raw, src.width, src.height);
    const d = texId(dst.raw, dst.width, dst.height);
    const seed = !textures.items[s].produced;
    textures.items[d].produced = true;
    event("{{\"op\":\"copy\",\"src\":{d},\"sx\":{d},\"sy\":{d},\"w\":{d},\"h\":{d},\"dst\":{d},\"dx\":{d},\"dy\":{d},\"clear\":{},\"render\":{},\"seed\":{}}}", .{ s, sx, sy, w, h, d, dx, dy, clear, render, seed });
    snapshot(cb, d);
}

/// After commit: if this command buffer carries the trace, wait and write it.
pub fn onSubmit(cb: *mtl.MTLCommandBuffer) void {
    if (state != .recording or depth != 0) return;
    const traced = command_buffer orelse return;
    if (traced != cb) return;
    mtl.metal_command_buffer_wait_until_completed(cb);
    write();
    state = .done;
}

fn write() void {
    var out: std.Io.Writer.Allocating = .init(alloc);
    defer out.deinit();
    const w = &out.writer;
    w.writeAll("{\"version\":1,\n\"textures\":[") catch return;
    for (textures.items, 0..) |t, i| {
        if (i > 0) w.writeAll(",") catch return;
        w.print("\n{{\"id\":{d},\"w\":{d},\"h\":{d},\"mtl_format\":{d}}}", .{ i, t.w, t.h, t.fmt }) catch return;
    }
    w.print("],\n\"samplers\":[{s}],\n\"pipelines\":[{s}],\n\"buffers\":[{s}],\n\"snapshots\":[", .{ sampler_json.written(), pipeline_json.written(), buffer_json.written() }) catch return;
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(alloc);
    for (snaps.items, 0..) |s, i| {
        if (i > 0) w.writeAll(",") catch return;
        w.print("\n{{\"tex\":{d},\"after\":{d},\"file\":\"snap_{d}.bin\",\"w\":{d},\"h\":{d},\"bpp\":{d}}}", .{ s.tex, s.after, i, s.w, s.h, s.bpp }) catch return;
        buf.resize(alloc, s.w * s.h * s.bpp) catch return;
        if (mtl.metal_trace_read(s.raw, buf.items.ptr, s.w * s.bpp) != 0)
            _ = mtl.metal_trace_write_file(path("snap_{d}.bin", .{i}), buf.items.ptr, buf.items.len);
        mtl.release(s.raw);
    }
    w.print("],\n\"warnings\":{d},\n\"events\":[\n{s}\n]}}\n", .{ warnings, json.written() }) catch return;
    _ = mtl.metal_trace_write_file(path("blob.bin", .{}), blob.items.ptr, blob.items.len);
    const text = out.written();
    _ = mtl.metal_trace_write_file(path("trace.json", .{}), text.ptr, text.len);
    mtl.metal_trace_remove_file(path("arm", .{}));
    _ = mtl.metal_trace_write_file(path("done", .{}), "ok", 2);
    std.log.info("[glass-trace] {d} events, {d} snapshots, {d} warnings -> {s}", .{ event_count, snaps.items.len, warnings, dir });
    json.deinit();
    sampler_json.deinit();
    pipeline_json.deinit();
    buffer_json.deinit();
    blob.deinit(alloc);
    textures.deinit(alloc);
    samplers.deinit(alloc);
    pipelines.deinit(alloc);
    buffers.deinit(alloc);
    snaps.deinit(alloc);
}
