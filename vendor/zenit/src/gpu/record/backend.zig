//! Record backend: the renderer's GPU work as a replayable command stream.
//!
//! The null backend's state machine (same renderer code as Metal, no device)
//! plus a recorder: textures, passes, pipelines (by shader entry), samplers,
//! fragment bytes and buffers, draws and copies become the event stream that
//! web/runtime/zenit-glass.mjs replays on WebGPU — the same format as the
//! native glass pass trace (metal/glass_trace.zig). Used by the Web DOM host
//! to run zenit's own glass pipeline (backdrop_blur.zig) in wasm; the browser
//! executes it. See docs/WEB_GLASS_DESIGN.md §5 (P2).
//!
//! Textures hold no pixels here: the browser owns them. One texture is the
//! *frame* (recorder.frame_texture): the backdrop the host paints, which glass
//! copies from as native copies from its main render target.
const std = @import("std");
const gpu = @import("../gpu.zig");

/// Process-scope allocator. Null backend resources are real memory (so getMappedRange returns
/// writable slice, renderer flush path runs to end), but GPU-uninvolved.
const alloc = std.heap.page_allocator;

// ============================================================================
// Recorder
// ============================================================================

pub const recorder = struct {
    /// Record opcodes: every record is [op, word count, payload...]; floats are
    /// f32 bits. web/runtime/zenit-glass-stream.mjs decodes them into the event
    /// objects web/runtime/zenit-glass.mjs replays.
    pub const Op = enum(u32) {
        // resources, registered on first use
        texture = 1, // id w h format frame
        sampler = 2, // id min mag mip u v
        pipeline = 3, // id vertex(str_off str_len) fragment(str_off str_len) format has_blend src_rgb dst_rgb op_rgb src_a dst_a op_a
        buffer = 4, // id blob_off len
        // GPU work
        pass = 10, // id target load(0 clear 1 load 2 dont_care) r g b a
        set_pipeline = 11, // p
        viewport = 12, // x y w h (f32)
        scissor = 13, // x y w h
        texture_slot = 14, // slot t
        sampler_slot = 15, // slot s
        bytes = 16, // slot blob_off len
        buffer_slot = 17, // slot b offset
        draw = 18, // vc ic fv fi
        end = 19,
        copy = 20, // src sx sy w h dst dx dy clear
        // glass
        glass = 21, // owner x y w h
        composite = 22, // t w h uv4 tint4 radii4 transform6 rotate scale offscreen world4
        warn = 23, // code (1 pass attachments, 2 vertex buffer, 3 vertex bytes)
        // host data (src/ui/web/glass.zig)
        glass_row = 30, // node host item
        luminance = 31, // t w h n, then n x (key u0 v0 u1 v1)
        scale = 32, // f32
    };

    pub var words: std.ArrayListUnmanaged(u32) = .empty;
    pub var strings: std.ArrayListUnmanaged(u8) = .empty;
    pub var blob: std.ArrayListUnmanaged(u8) = .empty;
    var texture_count: u32 = 0;
    var sampler_ids: std.ArrayListUnmanaged(u64) = .empty;
    var pipeline_ids: std.ArrayListUnmanaged(u64) = .empty;
    var buffer_ptrs: std.ArrayListUnmanaged(usize) = .empty;
    /// Texture id -> stream index (textures registered this frame).
    var texture_index: std.AutoHashMapUnmanaged(u64, u32) = .empty;
    /// The texture standing for the frame being drawn (the host's backdrop).
    pub var frame_texture: u64 = 0;
    pub var enabled: bool = false;

    /// Start a frame's stream. Resources are re-registered on first use.
    pub fn begin() void {
        words.clearRetainingCapacity();
        strings.clearRetainingCapacity();
        blob.clearRetainingCapacity();
        texture_count = 0;
        sampler_ids.clearRetainingCapacity();
        pipeline_ids.clearRetainingCapacity();
        buffer_ptrs.clearRetainingCapacity();
        texture_index.clearRetainingCapacity();
        enabled = true;
    }

    pub fn finish() void {
        enabled = false;
    }

    pub fn f(x: f32) u32 {
        return @bitCast(x);
    }

    /// Append one record.
    pub fn emit(op: Op, payload: []const u32) void {
        words.ensureUnusedCapacity(alloc, payload.len + 2) catch return;
        words.appendAssumeCapacity(@intFromEnum(op));
        words.appendAssumeCapacity(@intCast(payload.len));
        words.appendSliceAssumeCapacity(payload);
    }

    /// Record even while not encoding (host data appended after finish()).
    pub fn emitAlways(op: Op, payload: []const u32) void {
        const was = enabled;
        enabled = true;
        defer enabled = was;
        emit(op, payload);
    }

    pub fn event(op: Op, payload: []const u32) void {
        if (enabled) emit(op, payload);
    }

    fn str(s: []const u8) [2]u32 {
        const off: u32 = @intCast(strings.items.len);
        strings.appendSlice(alloc, s) catch return .{ 0, 0 };
        return .{ off, @intCast(s.len) };
    }

    /// The stream index of a texture registered this frame.
    pub fn indexOf(id: u64) ?u32 {
        return texture_index.get(id);
    }

    pub fn tex(id: u64, width: u32, height: u32, format: gpu.TextureFormat) u32 {
        if (texture_index.get(id)) |i| return i;
        const i = texture_count;
        texture_count += 1;
        texture_index.put(alloc, id, i) catch {};
        event(.texture, &.{ i, width, height, formatCode(format), @intFromBool(id == frame_texture) });
        return i;
    }

    fn sampler(s: *const Sampler) u32 {
        for (sampler_ids.items, 0..) |id, i| if (id == s.id) return @intCast(i);
        const i: u32 = @intCast(sampler_ids.items.len);
        sampler_ids.append(alloc, s.id) catch {};
        const d = s.desc;
        event(.sampler, &.{ i, @intFromEnum(d.min_filter), @intFromEnum(d.mag_filter), @intFromEnum(d.mipmap_filter), @intFromEnum(d.address_mode_u), @intFromEnum(d.address_mode_v) });
        return i;
    }

    fn pipeline(p: *const RenderPipeline) u32 {
        for (pipeline_ids.items, 0..) |id, i| if (id == p.id) return @intCast(i);
        const i: u32 = @intCast(pipeline_ids.items.len);
        pipeline_ids.append(alloc, p.id) catch {};
        const v = str(p.vertex[0..p.vertex_len]);
        const fr = str(p.fragment[0..p.fragment_len]);
        const b = p.blend orelse BlendState{};
        event(.pipeline, &.{ i, v[0], v[1], fr[0], fr[1], if (p.format) |fmt| formatCode(fmt) else 0, @intFromBool(p.blend != null), @intCast(@intFromEnum(b.source_rgb)), @intCast(@intFromEnum(b.destination_rgb)), @intCast(@intFromEnum(b.rgb_operation)), @intCast(@intFromEnum(b.source_alpha)), @intCast(@intFromEnum(b.destination_alpha)), @intCast(@intFromEnum(b.alpha_operation)) });
        return i;
    }

    fn buffer(b: *const Buffer) u32 {
        const key = @intFromPtr(b.bytes.ptr);
        for (buffer_ptrs.items, 0..) |ptr, i| if (ptr == key) return @intCast(i);
        const i: u32 = @intCast(buffer_ptrs.items.len);
        buffer_ptrs.append(alloc, key) catch {};
        event(.buffer, &.{ i, @intCast(bytes(b.bytes)), @intCast(b.bytes.len) });
        return i;
    }

    /// Append bytes to the blob (16-byte aligned records); returns the offset.
    pub fn bytes(data: []const u8) usize {
        const off = blob.items.len;
        blob.appendSlice(alloc, data) catch return off;
        while (blob.items.len % 16 != 0) blob.append(alloc, 0) catch break;
        return off;
    }

    /// Format codes (zenit-glass-stream.mjs FORMATS).
    fn formatCode(fmt: gpu.TextureFormat) u32 {
        return switch (fmt) {
            .bgra8_unorm => 1,
            .rgba8_unorm => 2,
            .rgba16_float => 3,
            .r8_unorm => 4,
            .r16_float => 5,
            .rgba32_float => 6,
            else => 0,
        };
    }
};

/// gpu.glass_trace for this backend: glass sections and their final composite
/// quads as stream records (backdrop_blur.applyBackdropBlur / traceComposite).
pub const glass_events = struct {
    pub fn enter(owner: u32, rect: [4]f32) void {
        const f = recorder.f;
        recorder.event(.glass, &.{ owner, f(rect[0]), f(rect[1]), f(rect[2]), f(rect[3]) });
    }
    pub fn leave() void {}
    pub fn active() bool {
        return false;
    }
    pub fn onComposite(binding: TextureBinding, w: f32, h: f32, uv: [4]f32, tint: [4]f32, radii: [4]f32, transform: [6]f32, rotate: f32, scale: f32, offscreen: u32, premultiplied: bool, world: [4]f32) void {
        _ = premultiplied;
        const f = recorder.f;
        const t = recorder.tex(binding.id, binding.width, binding.height, binding.format);
        recorder.event(.composite, &.{
            t,            f(w),         f(h),
            f(uv[0]),     f(uv[1]),     f(uv[2]),     f(uv[3]),
            f(tint[0]),   f(tint[1]),   f(tint[2]),   f(tint[3]),
            f(radii[0]),  f(radii[1]),  f(radii[2]),  f(radii[3]),
            f(transform[0]), f(transform[1]), f(transform[2]), f(transform[3]), f(transform[4]), f(transform[5]),
            f(rotate),    f(scale),     offscreen,
            f(world[0]),  f(world[1]),  f(world[2]),  f(world[3]),
        });
    }
};

/// Bytes-per-pixel. `gpu.TextureFormat` itself lacks this query (Metal backend uses
/// `conv.zig` to MTLPixelFormat, Metal handles it); Null backend self-computes
/// alloc size, needs minimal map here, covers only formats renderer uses.
fn bytesPerPixel(format: gpu.TextureFormat) u32 {
    return switch (format) {
        .r8_unorm, .r8_snorm, .r8_uint, .r8_sint => 1,
        .r16_uint, .r16_sint, .r16_float, .rg8_unorm, .rg8_snorm, .rg8_uint, .rg8_sint => 2,
        .rgba8_unorm, .rgba8_unorm_srgb, .rgba8_snorm, .rgba8_uint, .rgba8_sint, .bgra8_unorm, .bgra8_unorm_srgb, .r32_float, .r32_uint, .r32_sint, .rg16_uint, .rg16_sint, .rg16_float => 4,
        .rg32_float, .rg32_uint, .rg32_sint, .rgba16_uint, .rgba16_sint, .rgba16_float => 8,
        .rgba32_float, .rgba32_uint, .rgba32_sint => 16,
        else => 4,
    };
}

// ============================================================================
// Diagnostic counters to make abstract bypassing observable
// ============================================================================

/// Cross-backend instance counts. Tests assert resources paired-freed (leak detection).
pub var stats: Stats = .{};

pub const Stats = struct {
    buffers_created: u64 = 0,
    buffers_destroyed: u64 = 0,
    textures_created: u64 = 0,
    textures_destroyed: u64 = 0,
    samplers_created: u64 = 0,
    render_passes: u64 = 0,
    blit_passes: u64 = 0,
    draws: u64 = 0,
    submits: u64 = 0,

    pub fn reset() void {
        stats = .{};
    }

    /// Resource balance. Assertion that renderer didn't leak.
    pub fn balanced() bool {
        return stats.buffers_created == stats.buffers_destroyed and
            stats.textures_created == stats.textures_destroyed;
    }
};

// ============================================================================
// Resources
// ============================================================================

pub const Buffer = struct {
    bytes: []u8,
    size: u64,

    pub fn getMappedRange(self: *Buffer, offset: u64, size: u64) ![]u8 {
        // Same boundary semantics as Metal backend: out-of-bounds is error not UB. Assertion here
        // is
        // **deterministically testable** in Null backend, device-dependent in Metal.
        if (offset + size > self.size) return error.OutOfBounds;
        return self.bytes[@intCast(offset)..@intCast(offset + size)];
    }

    pub fn destroy(self: *Buffer) void {
        alloc.free(self.bytes);
        self.bytes = &.{};
        stats.buffers_destroyed += 1;
    }

    pub fn deinit(self: *Buffer) void {
        self.destroy();
    }
};

pub const TextureBinding = struct {
    /// Opaque id. Metal backend here `*MTLTexture`; Null backend uses monotonic id,
    /// semantically only needs 'comparable', `eql` is renderer's only dependency.
    id: u64,
    width: u32,
    height: u32,
    format: gpu.TextureFormat = .bgra8_unorm,

    pub fn eql(self: TextureBinding, other: TextureBinding) bool {
        return self.id == other.id;
    }

    pub fn samePixelFormat(self: TextureBinding, other: TextureBinding) bool {
        return self.format == other.format;
    }

    pub fn createView(self: TextureBinding) TextureView {
        return .{ .id = self.id, .width = self.width, .height = self.height, .format = self.format };
    }

    /// See Metal backend same-name function: backend-neutral test constructor.
    pub fn testBinding(token: u64, width: u32, height: u32) TextureBinding {
        return .{ .id = token, .width = width, .height = height };
    }
};

pub const TextureView = struct {
    id: u64,
    width: u32 = 0,
    height: u32 = 0,
    format: gpu.TextureFormat = .bgra8_unorm,

    pub fn destroy(self: *TextureView) void {
        self.id = 0;
    }
};

var next_texture_id: u64 = 1;

pub const Texture = struct {
    id: u64,
    bytes: []u8,
    format: gpu.TextureFormat,
    size: gpu.Extent3D,
    mip_level_count: u32,
    dimension: gpu.TextureDimension,
    memory: gpu.TextureMemory,

    pub fn writeRegion(
        self: *Texture,
        mip_level: u32,
        x: u32,
        y: u32,
        width: u32,
        height: u32,
        bytes: []const u8,
        bytes_per_row: u32,
    ) !void {
        _ = mip_level;
        // Matches Metal backend: device-local textures not directly writable. Keep this error;
        // renderer branches depending on it get coverage in Null backend.
        if (self.memory != .host_upload) return error.TextureNotHostWritable;
        if (width == 0 or height == 0) return;
        // Host uploads are not part of the glass stream yet.
        if (self.bytes.len == 0) return;
        if (x + width > self.size.width or y + height > self.size.height)
            return error.InvalidTextureRegion;
        const bpp = bytesPerPixel(self.format);
        const dst_stride = self.size.width * bpp;
        var row: u32 = 0;
        while (row < height) : (row += 1) {
            const src_off = row * bytes_per_row;
            const dst_off = (y + row) * dst_stride + x * bpp;
            const len = width * bpp;
            if (src_off + len > bytes.len) return error.InvalidTextureRegion;
            @memcpy(self.bytes[dst_off .. dst_off + len], bytes[src_off .. src_off + len]);
        }
    }

    pub fn readBgra8(self: *const Texture, width: u32, height: u32, bytes: []u8, bytes_per_row: u32) !void {
        const bpp = bytesPerPixel(self.format);
        const stride = self.size.width * bpp;
        var row: u32 = 0;
        while (row < @min(height, self.size.height)) : (row += 1) {
            const dst_off = row * bytes_per_row;
            const src_off = row * stride;
            const len = @min(@min(stride, bytes_per_row), width * bpp);
            if (dst_off + len > bytes.len) return;
            @memcpy(bytes[dst_off .. dst_off + len], self.bytes[src_off .. src_off + len]);
        }
    }

    pub fn nativeHandleForRecording(self: *const Texture) ?*anyopaque {
        _ = self;
        return null;
    }

    /// Test-only: construct metadata-only fake texture (matches Metal backend intent).
    /// `bytes` empty slice, so `destroy` doesn't mistakenly free.
    pub fn fakeForTesting(width: u32, height: u32, format: gpu.TextureFormat) Texture {
        const id = next_texture_id;
        next_texture_id += 1;
        return .{
            .id = id,
            .bytes = &.{},
            .format = format,
            .size = .{ .width = width, .height = height },
            .mip_level_count = 1,
            .dimension = .@"2d",
            .memory = .device_local,
        };
    }

    pub fn binding(self: *const Texture) TextureBinding {
        return .{ .id = self.id, .width = self.size.width, .height = self.size.height, .format = self.format };
    }

    pub fn destroy(self: *Texture) void {
        if (self.bytes.len > 0) alloc.free(self.bytes);
        if (self.id != 0) stats.textures_destroyed += 1;
        self.bytes = &.{};
        self.id = 0;
    }

    pub fn deinit(self: *Texture) void {
        self.destroy();
    }
};

pub const Sampler = struct {
    id: u64,
    desc: gpu.SamplerDescriptor = .{},

    pub fn destroy(self: *Sampler) void {
        self.id = 0;
    }

    pub fn deinit(self: *Sampler) void {
        self.destroy();
    }
};

// ============================================================================
// Device / Queue / Instance / Adapter
// ============================================================================

var next_sampler_id: u64 = 0;

pub const Device = struct {
    features: gpu.Features = .{},
    limits: gpu.Limits = .{},
    buffer_count: usize = 0,
    texture_count: usize = 0,
    sampler_count: usize = 0,

    pub fn createBuffer(
        self: *Device,
        allocator: std.mem.Allocator,
        desc: gpu.BufferDescriptor,
    ) !Buffer {
        _ = allocator;
        if (desc.size == 0) return error.InvalidDescriptor;
        const bytes = try alloc.alloc(u8, @intCast(desc.size));
        @memset(bytes, 0);
        self.buffer_count += 1;
        stats.buffers_created += 1;
        return .{ .bytes = bytes, .size = desc.size };
    }

    pub fn createTexture(
        self: *Device,
        allocator: std.mem.Allocator,
        desc: gpu.TextureDescriptor,
    ) !Texture {
        _ = allocator;
        if (desc.size.width == 0 or desc.size.height == 0) return error.InvalidDescriptor;
        if (desc.size.width > self.limits.max_texture_dimension_2d or
            desc.size.height > self.limits.max_texture_dimension_2d)
            return error.InvalidDescriptor;
        // The browser owns texture memory: no CPU copy.
        const id = next_texture_id;
        next_texture_id += 1;
        self.texture_count += 1;
        stats.textures_created += 1;
        return .{
            .id = id,
            .bytes = &.{},
            .format = desc.format,
            .size = desc.size,
            .mip_level_count = desc.mip_level_count,
            .dimension = desc.dimension,
            .memory = desc.memory,
        };
    }

    pub fn createSampler(
        self: *Device,
        allocator: std.mem.Allocator,
        desc: gpu.SamplerDescriptor,
    ) !Sampler {
        _ = allocator;
        self.sampler_count += 1;
        stats.samplers_created += 1;
        var d = desc;
        d.label = null;
        next_sampler_id += 1;
        return .{ .id = next_sampler_id, .desc = d };
    }

    pub fn deinit(self: *Device) void {
        self.* = .{};
    }
};

pub const Queue = struct {
    pub fn deinit(self: *Queue) void {
        _ = self;
    }
};

pub const Adapter = struct {
    pub fn requestDevice(
        self: *Adapter,
        allocator: std.mem.Allocator,
        desc: anytype,
    ) !struct { device: Device, queue: Queue } {
        _ = self;
        _ = allocator;
        if (@hasField(@TypeOf(desc), "required_features")) {
            if (@hasField(@TypeOf(desc.required_features), "non_uniform_uav_buffer_array_atomics") and desc.required_features.non_uniform_uav_buffer_array_atomics)
                return error.UnsupportedFeatures;
        }
        return .{ .device = .{}, .queue = .{} };
    }

    pub fn deinit(self: *Adapter) void {
        _ = self;
    }
};

pub const Instance = struct {
    adapters_storage: [1]Adapter = .{.{}},

    pub fn init(allocator: std.mem.Allocator, desc: anytype) !Instance {
        _ = allocator;
        _ = desc;
        return .{};
    }

    pub fn enumerateAdapters(self: *Instance) ![]Adapter {
        return self.adapters_storage[0..];
    }

    pub fn deinit(self: *Instance) void {
        _ = self;
    }
};

// ============================================================================
// Pipeline
// ============================================================================

pub const ShaderFunction = struct {
    /// Stable copy of function name. Metal backend here `*MTLFunction`; Null backend keeps name,
    /// letting pipeline creation discriminate meaningfully (also proves 'name'-based shader
    /// identification works, see pipeline.zig PSO cache flip lesson).
    name: [64]u8 = @as([64]u8, @splat(0)),
    name_len: usize = 0,

    pub fn deinit(self: *ShaderFunction) void {
        self.name_len = 0;
    }
};

pub const ShaderModule = struct {
    /// Source length. Null backend doesn't compile MSL; only proves module->function lifecycle
    /// contract holds. Real second **graphics** backend needs another shader source, way bigger
    /// scope.
    source_len: usize,

    pub fn initFromSource(device: *Device, source: []const u8) !ShaderModule {
        _ = device;
        if (source.len == 0) return error.ShaderCompilationFailed;
        return .{ .source_len = source.len };
    }

    pub fn getFunction(self: *ShaderModule, name: []const u8) !ShaderFunction {
        _ = self;
        if (name.len == 0 or name.len > 64) return error.FunctionNotFound;
        var f = ShaderFunction{};
        @memcpy(f.name[0..name.len], name);
        f.name_len = name.len;
        return f;
    }

    pub fn deinit(self: *ShaderModule) void {
        self.source_len = 0;
    }
};

pub const RenderPipeline = struct {
    id: u64,
    vertex: [64]u8 = @splat(0),
    vertex_len: usize = 0,
    fragment: [64]u8 = @splat(0),
    fragment_len: usize = 0,
    format: ?gpu.TextureFormat = null,
    blend: ?BlendState = null,

    pub fn deinit(self: *RenderPipeline) void {
        self.id = 0;
    }
};

/// Descriptor family aligned per-field with Metal backend. Intentionally each backend
/// carries own copy not in gpu.zig: they hold `?*const ShaderFunction` references to
/// backend-specific types.
pub const BlendFactor = enum(c_ulong) {
    zero = 0,
    one = 1,
    src_color = 2,
    one_minus_src_color = 3,
    src_alpha = 4,
    one_minus_src_alpha = 5,
    dst_color = 6,
    one_minus_dst_color = 7,
    dst_alpha = 8,
    one_minus_dst_alpha = 9,
    src_alpha_saturated = 10,
    blend_color = 11,
    one_minus_blend_color = 12,
    blend_alpha = 13,
    one_minus_blend_alpha = 14,
};

pub const BlendOperation = enum(c_ulong) {
    add = 0,
    subtract = 1,
    reverse_subtract = 2,
    min = 3,
    max = 4,
};

pub const BlendState = struct {
    source_rgb: BlendFactor = .one,
    destination_rgb: BlendFactor = .zero,
    rgb_operation: BlendOperation = .add,
    source_alpha: BlendFactor = .one,
    destination_alpha: BlendFactor = .zero,
    alpha_operation: BlendOperation = .add,

    pub const ALPHA_BLENDING = BlendState{
        .source_rgb = .src_alpha,
        .destination_rgb = .one_minus_src_alpha,
        .rgb_operation = .add,
        .source_alpha = .one,
        .destination_alpha = .one_minus_src_alpha,
        .alpha_operation = .add,
    };
};

pub const VertexAttributeDescriptor = struct {
    format: gpu.VertexFormat,
    offset: u64,
    shader_location: u32,
};

pub const VertexBufferLayoutDescriptor = struct {
    stride: u64,
    step_mode: gpu.VertexStepMode = .vertex,
    attributes: []const VertexAttributeDescriptor,
};

pub const RenderPipelineDescriptor = struct {
    vertex_function: ?*const ShaderFunction = null,
    fragment_function: ?*const ShaderFunction = null,
    color_attachment_formats: []const gpu.TextureFormat = &.{},
    depth_attachment_format: ?gpu.TextureFormat = null,
    stencil_attachment_format: ?gpu.TextureFormat = null,
    sample_count: u32 = 1,
    vertex_buffers: []const VertexBufferLayoutDescriptor = &.{},
    blend_state: ?BlendState = null,
};

var next_pipeline_id: u64 = 1;

pub fn createRenderPipeline(device: *Device, desc: RenderPipelineDescriptor) !RenderPipeline {
    _ = device;
    const id = next_pipeline_id;
    next_pipeline_id += 1;
    var p: RenderPipeline = .{ .id = id, .blend = desc.blend_state };
    if (desc.vertex_function) |f| {
        p.vertex = f.name;
        p.vertex_len = f.name_len;
    }
    if (desc.fragment_function) |f| {
        p.fragment = f.name;
        p.fragment_len = f.name_len;
    }
    if (desc.color_attachment_formats.len > 0) p.format = desc.color_attachment_formats[0];
    return p;
}

// ============================================================================
// Command encoding; pass state machine is the most valuable part of this backend
// ============================================================================

const PassKind = enum { none, render, blit };

/// Pass state machine isomorphic to Metal backend. Metal backend uses `generation` to reject stale
/// pass (ObjC object addresses are immediately reused, the root cause of GlassBox blit crash). Null
/// backend replicates same semantics, allowing this invariant to be verified in **device-free
/// deterministic tests** instead of relying on real window E2E.
pub const CommandEncoder = struct {
    state: PassKind = .none,
    next_generation: u64 = 1,
    active_generation: u64 = 0,
    finished: bool = false,

    pub fn init(queue: *Queue) !CommandEncoder {
        _ = queue;
        return .{};
    }

    fn activate(self: *CommandEncoder, kind: PassKind) u64 {
        std.debug.assert(self.state == .none);
        const g = self.next_generation;
        self.next_generation +%= 1;
        if (self.next_generation == 0) self.next_generation = 1;
        self.active_generation = g;
        self.state = kind;
        return g;
    }

    fn close(self: *CommandEncoder, kind: PassKind, generation: u64) void {
        if (self.state != kind or self.active_generation != generation)
            @panic("stale or wrong-kind GPU pass used after its lifetime ended");
        self.state = .none;
        self.active_generation = 0;
    }

    fn isActive(self: *const CommandEncoder, kind: PassKind, generation: u64) bool {
        return self.state == kind and self.active_generation == generation;
    }

    pub fn beginRenderPass(self: *CommandEncoder, desc: gpu.RenderPassDescriptor) !RenderPass {
        if (self.state != .none) return error.InvalidEncoderState;
        const g = self.activate(.render);
        stats.render_passes += 1;
        if (desc.color_attachments.len == 1 and desc.depth_stencil_attachment == null) {
            const a = desc.color_attachments[0];
            const t = recorder.tex(a.view.id, a.view.width, a.view.height, a.view.format);
            const c = a.clear_value;
            recorder.event(.pass, &.{ @intCast(g), t, switch (a.load_op) { .clear => 0, .load => 1, .dont_care => 2 }, recorder.f(@floatCast(c.r)), recorder.f(@floatCast(c.g)), recorder.f(@floatCast(c.b)), recorder.f(@floatCast(c.a)) });
        } else recorder.event(.warn, &.{1});
        return .{ .command_encoder = self, .generation = g };
    }

    pub fn beginBlitPass(self: *CommandEncoder) !BlitPass {
        if (self.state != .none) return error.InvalidEncoderState;
        const g = self.activate(.blit);
        stats.blit_passes += 1;
        return .{ .command_encoder = self, .generation = g };
    }

    pub fn finish(self: *CommandEncoder) !CommandBuffer {
        if (self.finished) return error.EncoderAlreadyFinished;
        if (self.state != .none) return error.InvalidEncoderState;
        self.finished = true;
        return .{};
    }

    pub fn deinit(self: *CommandEncoder) void {
        _ = self;
    }
};

pub const RenderPass = struct {
    command_encoder: *CommandEncoder,
    generation: u64,

    /// type-level counter with same name and type as Metal backend
    /// (`src/render/command_encoder.zig` zeroes it each frame). Must exist across backends, else
    /// renderer fails to compile.
    pub var frame_draw_call_count: u32 = 0;

    fn assertActive(self: *const RenderPass) void {
        if (!self.command_encoder.isActive(.render, self.generation))
            @panic("stale or wrong-kind GPU pass used after its lifetime ended");
    }

    pub fn isActive(self: *const RenderPass) bool {
        return self.command_encoder.isActive(.render, self.generation);
    }

    pub fn setPipeline(self: *RenderPass, pipeline: *const RenderPipeline) void {
        self.assertActive();
        recorder.event(.set_pipeline, &.{recorder.pipeline(pipeline)});
    }

    pub fn setViewport(self: *RenderPass, x: f32, y: f32, w: f32, h: f32, min_d: f32, max_d: f32) void {
        self.assertActive();
        _ = .{ min_d, max_d };
        recorder.event(.viewport, &.{ recorder.f(x), recorder.f(y), recorder.f(w), recorder.f(h) });
    }

    pub fn setScissorRect(self: *RenderPass, x: u32, y: u32, w: u32, h: u32) void {
        self.assertActive();
        recorder.event(.scissor, &.{ x, y, w, h });
    }

    pub fn setVertexBuffer(self: *RenderPass, slot: u32, buffer: *const Buffer, offset: u64) void {
        self.assertActive();
        _ = .{ buffer, offset };
        recorder.event(.warn, &.{ 2, slot });
    }

    pub fn setFragmentBuffer(self: *RenderPass, slot: u32, buffer: *const Buffer, offset: u64) void {
        self.assertActive();
        recorder.event(.buffer_slot, &.{ slot, recorder.buffer(buffer), @intCast(offset) });
    }

    pub fn setFragmentTexture(self: *RenderPass, slot: u32, texture: *const Texture) void {
        self.assertActive();
        self.setFragmentTextureBinding(slot, texture.binding());
    }

    pub fn setFragmentTextureBinding(self: *RenderPass, slot: u32, texture: TextureBinding) void {
        self.assertActive();
        recorder.event(.texture_slot, &.{ slot, recorder.tex(texture.id, texture.width, texture.height, texture.format) });
    }

    pub fn setFragmentSampler(self: *RenderPass, slot: u32, sampler: ?*const Sampler) void {
        self.assertActive();
        const s = sampler orelse return;
        recorder.event(.sampler_slot, &.{ slot, recorder.sampler(s) });
    }

    pub fn setVertexBytes(self: *RenderPass, slot: u32, data: []const u8) void {
        self.assertActive();
        _ = data;
        recorder.event(.warn, &.{ 3, slot });
    }

    pub fn setFragmentBytes(self: *RenderPass, slot: u32, data: []const u8) void {
        self.assertActive();
        recorder.event(.bytes, &.{ slot, @intCast(recorder.bytes(data)), @intCast(data.len) });
    }

    pub fn draw(self: *RenderPass, vertex_count: u32, instance_count: u32, first_vertex: u32, first_instance: u32) void {
        self.assertActive();
        if (vertex_count == 0 or instance_count == 0) return;
        frame_draw_call_count += 1;
        stats.draws += 1;
        recorder.event(.draw, &.{ vertex_count, instance_count, first_vertex, first_instance });
    }

    pub fn end(self: *RenderPass) void {
        self.assertActive();
        self.command_encoder.close(.render, self.generation);
        recorder.event(.end, &.{});
    }
};

pub const BlitPass = struct {
    command_encoder: *CommandEncoder,
    generation: u64,

    fn assertActive(self: *const BlitPass) void {
        if (!self.command_encoder.isActive(.blit, self.generation))
            @panic("stale or wrong-kind GPU pass used after its lifetime ended");
    }

    pub fn isActive(self: *const BlitPass) bool {
        return self.command_encoder.isActive(.blit, self.generation);
    }

    pub fn copyTextureRegion(
        self: *BlitPass,
        source: TextureBinding,
        source_x: u32,
        source_y: u32,
        width: u32,
        height: u32,
        destination: TextureBinding,
        destination_x: u32,
        destination_y: u32,
    ) !void {
        self.assertActive();
        // region validation aligned byte-for-byte with Metal backend; this contract is
        // deterministically testable in Null backend.
        if (width == 0 or height == 0 or
            source_x > source.width or width > source.width - source_x or
            source_y > source.height or height > source.height - source_y or
            destination_x > destination.width or width > destination.width - destination_x or
            destination_y > destination.height or height > destination.height - destination_y)
        {
            return error.InvalidTextureRegion;
        }
        const s = recorder.tex(source.id, source.width, source.height, source.format);
        const d = recorder.tex(destination.id, destination.width, destination.height, destination.format);
        recorder.event(.copy, &.{ s, source_x, source_y, width, height, d, destination_x, destination_y, 0 });
    }

    pub fn end(self: *BlitPass) void {
        self.assertActive();
        self.command_encoder.close(.blit, self.generation);
    }
};

pub const CommandBuffer = struct {
    completed: bool = true,

    pub fn submit(self: *CommandBuffer) void {
        _ = self;
        stats.submits += 1;
    }

    pub fn retained(self: *const CommandBuffer) CommandBuffer {
        return .{ .completed = self.completed };
    }

    pub fn waitUntilCompleted(self: *const CommandBuffer) void {
        _ = self;
    }

    pub fn isCompleted(self: *const CommandBuffer) bool {
        return self.completed;
    }

    pub fn gpuElapsedMicros(self: *const CommandBuffer) ?u64 {
        _ = self;
        return null;
    }

    /// type-level error counter with same name as Metal backend (observation point for cmd buffer
    /// submit failure).
    pub var error_count: std.atomic.Value(u64) = .init(0);

    pub fn presentDrawable(self: *CommandBuffer, drawable: *anyopaque) void {
        _ = .{ self, drawable };
    }

    pub fn deinit(self: *CommandBuffer) void {
        _ = self;
    }
};

// ============================================================================
// Surface
// ============================================================================

pub const SurfaceUsage = enum { color_target_only, color_target_and_read };
pub const PresentMode = enum { fifo, immediate, mailbox };
pub const AlphaMode = enum { fully_opaque, premultiplied, postmultiplied };

pub const SurfaceConfiguration = struct {
    format: gpu.TextureFormat,
    width: u32,
    height: u32,
    usage: SurfaceUsage = .color_target_only,
    present_mode: PresentMode = .fifo,
    alpha_mode: AlphaMode = .fully_opaque,
    maximum_frame_latency: u32 = 2,
};

pub const SurfaceTexture = struct {
    texture: Texture,
    present_with_transaction: bool = false,

    pub fn preparePresent(self: *SurfaceTexture, command_buffer: *CommandBuffer) void {
        _ = .{ self, command_buffer };
    }

    pub fn presentAfterSubmit(self: *SurfaceTexture, command_buffer: *CommandBuffer) void {
        _ = .{ self, command_buffer };
    }

    pub fn deinit(self: *SurfaceTexture) void {
        self.texture.destroy();
    }
};

pub const Surface = struct {
    format: ?gpu.TextureFormat = null,
    extent: gpu.Extent3D = .{ .width = 0, .height = 0, .depth = 1 },

    /// platform handle is ignored, which is the point of `*anyopaque` signature: Null backend need
    /// not know what CAMetalLayer is.
    pub fn init(layer: *anyopaque) Surface {
        _ = layer;
        return .{};
    }

    pub fn configure(
        self: *Surface,
        allocator: std.mem.Allocator,
        device: *Device,
        config: SurfaceConfiguration,
    ) !void {
        _ = .{ allocator, device };
        self.format = config.format;
        self.extent = .{ .width = config.width, .height = config.height, .depth = 1 };
    }

    pub fn acquireTexture(self: *Surface, allocator: std.mem.Allocator) !SurfaceTexture {
        _ = allocator;
        const format = self.format orelse return error.SurfaceNotConfigured;
        const id = next_texture_id;
        next_texture_id += 1;
        stats.textures_created += 1;
        return .{ .texture = .{
            .id = id,
            .bytes = &.{},
            .format = format,
            .size = self.extent,
            .mip_level_count = 1,
            .dimension = .@"2d",
            .memory = .device_local,
        } };
    }

    pub fn deinit(self: *Surface) void {
        self.format = null;
    }
};

// ============================================================================
// FrameSync
// ============================================================================

/// Metal backend uses `dispatch_semaphore_t` (Darwin-specific). Interface itself leaks no type, so
/// we can use portable `std.Io.Semaphore` here, which also proves FrameSync's abstraction is
/// clean.
pub const FrameSync = struct {
    sem: std.Io.Semaphore,
    io: std.Io,

    pub fn init(max_frames_in_flight: u32, io: std.Io) FrameSync {
        return .{ .io = io, .sem = .{ .permits = max_frames_in_flight } };
    }

    pub fn waitForNextFrame(self: *FrameSync) error{}!void {
        self.sem.waitUncancelable(self.io);
    }

    pub fn signalOnCompletion(self: *FrameSync, command_buffer: *const CommandBuffer) void {
        _ = command_buffer;
        self.sem.post(self.io);
    }

    pub fn signal(self: *FrameSync) void {
        self.sem.post(self.io);
    }

    /// aligned with Metal backend: drain then release sync primitive (std semaphore has no system
    /// resources, no-op semantics).
    pub fn deinit(self: *FrameSync) void {
        _ = self;
    }

    pub fn drain(self: *FrameSync, max_frames: u32) void {
        var i: u32 = 0;
        while (i < max_frames) : (i += 1) self.sem.waitUncancelable(self.io);
        i = 0;
        while (i < max_frames) : (i += 1) self.sem.post(self.io);
    }
};

// ============================================================================
// Miscellaneous
// ============================================================================

/// GPU-agnostic diagnostic tool (screenshot dump). Null backend does not write files.
pub fn writePngRgba(path: [:0]const u8, rgba: []const u8, width: u32, height: u32, bytes_per_row: u32) bool {
    _ = .{ path, rgba, width, height, bytes_per_row };
    return false;
}
