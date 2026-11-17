/// Display List: internal IR of the paint pass.
///
/// **core/ internal only; external code must not import it directly.**
/// The encoder main path uses paint_table.DisplayItem (struct, not union). This file remains as
/// the IR bridge between paint pass -> display_list_lowering; snapshot.zig also holds this union
/// across frames (Snapshot.commands). Modules needing paint data should import `paint_table.zig`.
/// `grep -rn "@import.*display_list.zig" src/` should only hit the src/ui/core/ subtree.
///
/// DisplayItem is the unique IR between paint pass -> encoder. Each item associates via ItemHeader
/// with transform/clip/effect in PropertyTree. The paint pass emits local coordinates;
/// display_list_lowering applies the transform to get world coordinates, and the encoder directly
/// consumes the lowered DisplayItem.
const std = @import("std");
const types = @import("types.zig");
const icon_ir = @import("icon_ir");
const genie_warp = @import("zenit_genie_warp");
const property_tree = @import("property_tree.zig");
const text_blob_mod = @import("text_blob.zig");

pub const TextRasterPolicy = text_blob_mod.TextRasterPolicy;

const Allocator = std.mem.Allocator;
const Color = types.Color;
const TextSpan = types.TextSpan;
const GradientDirection = types.GradientDirection;
pub const INVALID_ID = property_tree.INVALID_ID;

/// Clip primitive type (R3f defined in display_list), shared with ClipNode/clip token. PathFillRule
/// reused from types.PathFillRule (cross-module shared, not defined here).
pub const max_clip_polygon_points: usize = 32;
pub const max_clip_polygon_contours: usize = 8;

/// Sentinel in `begin_opacity_layer.surface_stable_id`: doesn't participate in GPU retained
/// composite. Semantically 'no stable identity', encoder seeing it must take old
/// every-frame-repaint path.
pub const INVALID_SURFACE_ID: u32 = std.math.maxInt(u32);

pub const ClipShapeKind = enum(u8) {
    rect = 0,
    rounded_rect = 1,
    ellipse = 2,
    polygon = 3,
};

pub const ClipPolygon = struct {
    point_count: u8 = 0,
    contour_count: u8 = 0,
    fill_rule: types.PathFillRule = .evenodd,
    contour_end_points: [max_clip_polygon_contours]u8 = @as([max_clip_polygon_contours]u8, @splat(0)),
    points: [max_clip_polygon_points][2]f32 = @as([max_clip_polygon_points][2]f32, @splat(.{ 0, 0 })),

    pub fn empty() ClipPolygon {
        return .{};
    }

    /// The polygon a frame-local reference names (empty for null).
    pub fn of(p: ?*const ClipPolygon) ClipPolygon {
        return if (p) |polygon| polygon.* else .{};
    }
};

/// Common associating header for each DisplayItem (PropertyTree reference)
pub const ItemHeader = struct {
    /// Frozen snapshot geometry has no dependency on the current property tree.
    already_lowered: bool = false,
    transform_id: u32,
    clip_id: u32 = INVALID_ID,
    effect_id: u32 = INVALID_ID,
    node_id: u32,
    paint_order: u64 = 0,
    /// contentFingerprint of the item as recorded (0 = not computed). Set once
    /// when the item enters a DisplayList and carried by every replay, so an
    /// unchanged item is never hashed again; whoever rewrites an item's content
    /// must reset it to 0 (ids above are frame-local and not content).
    local_fp: u64 = 0,
};

/// Content fingerprint of a display item: every field of its variant except
/// the header and frame-local resource ids (text blob_id), slices and
/// pointees followed (to a bounded depth; deeper pointers hash their address,
/// which can only make an unchanged item look changed). Never 0.
///
/// The value is Wyhash over a canonical byte stream: the active tag (u32), then
/// each field in declaration order, field by field (never the struct's bytes, so
/// padding and undefined bytes are never read): bool as one byte, floats as their
/// bit pattern, integers and enum tags widened to 64 bits, optionals as "+" value
/// or "-", arrays element by element, slices as their u64 length then elements,
/// tagged unions as their u32 tag then payload. The stream is assembled in a stack
/// buffer and handed to Wyhash in large chunks; Wyhash's streaming result does not
/// depend on how the stream is chunked, so the value is exactly that of hashing the
/// stream field by field (`contentFingerprintStreamed`, kept for the equivalence
/// tests).
pub fn contentFingerprint(item: *const DisplayItem) u64 {
    var sink: FingerprintSink = .{ .h = std.hash.Wyhash.init(fingerprint_seed) };
    const tag: u32 = @backingInt(std.meta.activeTag(item.*));
    sink.put(4, std.mem.asBytes(&tag));
    switch (item.*) {
        inline else => |*variant| serializeContent(&sink, variant, 0),
    }
    const fp = sink.final();
    return if (fp == 0) 1 else fp;
}

const fingerprint_seed: u64 = 0x6c6f63616c;

/// Stack buffer in front of a Wyhash: fixed-size writes are a bounds check and a
/// store instead of a Wyhash.update call each.
const FingerprintSink = struct {
    h: std.hash.Wyhash,
    len: usize = 0,
    buf: [capacity]u8 = undefined,

    const capacity = 1024;

    inline fn put(self: *FingerprintSink, comptime n: usize, bytes: *const [n]u8) void {
        comptime std.debug.assert(n <= capacity);
        if (self.len + n > capacity) self.flush();
        self.buf[self.len..][0..n].* = bytes.*;
        self.len += n;
    }

    fn putSlice(self: *FingerprintSink, bytes: []const u8) void {
        if (bytes.len <= capacity - self.len) {
            @memcpy(self.buf[self.len..][0..bytes.len], bytes);
            self.len += bytes.len;
        } else {
            self.flush();
            self.h.update(bytes);
        }
    }

    fn flush(self: *FingerprintSink) void {
        self.h.update(self.buf[0..self.len]);
        self.len = 0;
    }

    fn final(self: *FingerprintSink) u64 {
        self.flush();
        return self.h.final();
    }
};

/// True for arrays (of arrays) of floats: their in-memory bytes are exactly the
/// element-by-element bit patterns (no padding between array elements).
fn isFloatArray(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .float => |f| f.bits == 32 or f.bits == 64,
        .array => |a| isFloatArray(a.child),
        else => false,
    };
}

fn serializeContent(sink: *FingerprintSink, ptr: anytype, comptime depth: u32) void {
    const T = @typeInfo(@TypeOf(ptr)).pointer.child;
    switch (@typeInfo(T)) {
        .void => {},
        .bool => sink.put(1, &[_]u8{@intFromBool(ptr.*)}),
        .float => |f| {
            const bits: @Int(.unsigned, f.bits) = @bitCast(ptr.*);
            sink.put(@sizeOf(@TypeOf(bits)), std.mem.asBytes(&bits));
        },
        .int => |i| {
            const wide: @Int(i.signedness, 64) = ptr.*;
            sink.put(8, std.mem.asBytes(&wide));
        },
        .@"enum" => {
            const backing = @backingInt(ptr.*);
            serializeContent(sink, &backing, depth);
        },
        .optional => if (ptr.*) |*v| {
            sink.put(1, "+");
            serializeContent(sink, v, depth);
        } else sink.put(1, "-"),
        .array => |a| if (comptime isFloatArray(T) and @sizeOf(T) <= FingerprintSink.capacity) {
            comptime std.debug.assert(@sizeOf(T) == a.len * @sizeOf(a.child));
            sink.put(@sizeOf(T), std.mem.asBytes(ptr));
        } else for (ptr) |*v| serializeContent(sink, v, depth),
        .pointer => |p| switch (p.size) {
            .slice => {
                const value = ptr.*;
                const n: u64 = value.len;
                sink.put(8, std.mem.asBytes(&n));
                if (p.child == u8) sink.putSlice(value) else for (value) |*v| serializeContent(sink, v, depth);
            },
            .one => if (depth < 3) serializeContent(sink, ptr.*, depth + 1) else {
                const addr = @intFromPtr(ptr.*);
                sink.put(@sizeOf(usize), std.mem.asBytes(&addr));
            },
            else => {
                const addr = @intFromPtr(ptr.*);
                sink.put(@sizeOf(usize), std.mem.asBytes(&addr));
            },
        },
        .@"struct" => |info| inline for (info.field_names, info.field_types) |name, field_type| {
            if (comptime field_type == ItemHeader or std.mem.eql(u8, name, "blob_id")) continue;
            serializeContent(sink, &@field(ptr.*, name), depth);
        },
        .@"union" => |info| {
            if (info.tag_type == null) @compileError("contentFingerprint: untagged union " ++ @typeName(T));
            const tag: u32 = @backingInt(std.meta.activeTag(ptr.*));
            sink.put(4, std.mem.asBytes(&tag));
            switch (ptr.*) {
                inline else => |*v| serializeContent(sink, v, depth),
            }
        },
        else => @compileError("contentFingerprint: unsupported " ++ @typeName(T)),
    }
}

/// Reference form of contentFingerprint: the same canonical stream fed to Wyhash
/// one field at a time (the original implementation). Only the tests call it.
fn contentFingerprintStreamed(item: *const DisplayItem) u64 {
    var h = std.hash.Wyhash.init(fingerprint_seed);
    const tag: u32 = @backingInt(std.meta.activeTag(item.*));
    h.update(std.mem.asBytes(&tag));
    switch (item.*) {
        inline else => |*variant| hashContentStreamed(&h, variant.*, 0),
    }
    const fp = h.final();
    return if (fp == 0) 1 else fp;
}

fn hashContentStreamed(h: *std.hash.Wyhash, value: anytype, comptime depth: u32) void {
    const T = @TypeOf(value);
    switch (@typeInfo(T)) {
        .void => {},
        .bool => h.update(&[_]u8{@intFromBool(value)}),
        .float => |f| {
            const bits: @Int(.unsigned, f.bits) = @bitCast(value);
            h.update(std.mem.asBytes(&bits));
        },
        .int => |i| {
            const wide: @Int(i.signedness, 64) = value;
            h.update(std.mem.asBytes(&wide));
        },
        .@"enum" => hashContentStreamed(h, @backingInt(value), depth),
        .optional => if (value) |v| {
            h.update("+");
            hashContentStreamed(h, v, depth);
        } else h.update("-"),
        .array => for (value) |v| hashContentStreamed(h, v, depth),
        .pointer => |ptr| switch (ptr.size) {
            .slice => {
                const n: u64 = value.len;
                h.update(std.mem.asBytes(&n));
                if (ptr.child == u8) h.update(value) else for (value) |v| hashContentStreamed(h, v, depth);
            },
            .one => if (depth < 3) hashContentStreamed(h, value.*, depth + 1) else {
                const addr = @intFromPtr(value);
                h.update(std.mem.asBytes(&addr));
            },
            else => {
                const addr = @intFromPtr(value);
                h.update(std.mem.asBytes(&addr));
            },
        },
        .@"struct" => |info| inline for (info.field_names, info.field_types) |name, field_type| {
            if (comptime field_type == ItemHeader or std.mem.eql(u8, name, "blob_id")) continue;
            hashContentStreamed(h, @field(value, name), depth);
        },
        .@"union" => |info| {
            if (info.tag_type == null) @compileError("contentFingerprint: untagged union " ++ @typeName(T));
            const tag: u32 = @backingInt(std.meta.activeTag(value));
            h.update(std.mem.asBytes(&tag));
            switch (value) {
                inline else => |v| hashContentStreamed(h, v, depth),
            }
        },
        else => @compileError("contentFingerprint: unsupported " ++ @typeName(T)),
    }
}

/// Glass parameters of a begin_blur_layer that sets none.
pub const default_glass: types.ResolvedGlassParams = .{};

pub const DisplayItem = union(enum) {
    fill_rect: struct {
        header: ItemHeader,
        x: f32,
        y: f32,
        w: f32,
        h: f32,
        color: Color,
        radius: [4]f32 = .{ 0, 0, 0, 0 },
        /// Draw shape (0 = rounded_rect, 1 = ellipse). Same sequence as types.ShapeSpec. Radius
        /// ignored when ellipse (SDF determined by semi-axes).
        shape: u8 = 0,
    },
    stroke_rect: struct {
        header: ItemHeader,
        x: f32,
        y: f32,
        w: f32,
        h: f32,
        color: Color,
        width: f32,
        radius: [4]f32 = .{ 0, 0, 0, 0 },
        /// See fill_rect.shape
        shape: u8 = 0,
    },
    border_side: struct {
        header: ItemHeader,
        x: f32,
        y: f32,
        w: f32,
        h: f32,
        color: Color,
        width: f32,
        radius: [4]f32 = .{ 0, 0, 0, 0 },
        clip_x: f32,
        clip_y: f32,
        clip_w: f32,
        clip_h: f32,
        /// TL, TR, BR, BL (.rounded_rect only).
        clip_radii: [4]f32 = .{ 0, 0, 0, 0 },
        clip_shape_kind: ClipShapeKind = .rect,
        /// By reference, like push_clip.polygon (null = empty).
        clip_polygon: ?*const ClipPolygon = null,
    },
    /// Per-side border: shader computes inner outline, no clip needed
    border_per_side: struct {
        header: ItemHeader,
        x: f32,
        y: f32,
        w: f32,
        h: f32,
        color: Color,
        widths: [4]f32, // top, right, bottom, left
        radius: [4]f32 = .{ 0, 0, 0, 0 },
    },
    gradient_rect: struct {
        header: ItemHeader,
        x: f32,
        y: f32,
        w: f32,
        h: f32,
        from: Color,
        to: Color,
        direction: GradientDirection = .vertical,
        radius: [4]f32 = .{ 0, 0, 0, 0 },
        radial_center_x: f32 = 0,
        radial_center_y: f32 = 0,
        conic_start_angle: f32 = 0,
        extend_mode: types.GradientExtendMode = .pad,
        /// See fill_rect.shape
        shape: u8 = 0,
    },
    shadow_rect: struct {
        header: ItemHeader,
        x: f32,
        y: f32,
        w: f32,
        h: f32,
        color: Color,
        blur: f32,
        offset_x: f32 = 0,
        offset_y: f32 = 0,
        /// CSS spread (positive outer expand / negative shrink shadow shape; body always hollowed
        /// below).
        spread: f32 = 0,
        radius: [4]f32 = .{ 0, 0, 0, 0 },
    },
    outline_rect: struct {
        header: ItemHeader,
        x: f32,
        y: f32,
        w: f32,
        h: f32,
        color: Color,
        width: f32,
        radius: [4]f32 = .{ 0, 0, 0, 0 },
    },
    text_run: struct {
        header: ItemHeader,
        /// local origin x
        x: f32,
        /// local baseline y
        y: f32,
        content: []const u8,
        blob_byte_start: u32 = 0,
        blob_byte_end: u32 = 0,
        color: Color,
        /// Logical font size (not multiplied by scale!)
        font_size: f32,
        font_weight: u16 = 400,
        /// Font family id (see TextProps.font_family). 0 = default family.
        font_family: u16 = 0,
        use_symbols_font: bool = false,
        use_monospace_font: bool = false,
        monospace_char_width: f32 = 0,
        use_italic_font: bool = false,
        /// TextProps.font_smoothing
        font_smoothing: bool = true,
        spans: ?[]const TextSpan = null,
        /// The TextLayoutBlob this run was laid out in (INVALID_ID = none), with the run's byte
        /// range in the laid-out text (`blob_byte_start..blob_byte_end`). A **frame-local
        /// sequence number**: the blob store is cleared and renumbered each frame, so an item
        /// kept across frames (cache, snapshot) drops it. It names layout only; the bytes of the
        /// run are `content`, owned with the item.
        blob_id: u32 = INVALID_ID,
        /// Phase L3: rasterization strategy
        raster_policy: TextRasterPolicy = .static_crisp,
        /// Right-edge fade-out mask window, **offset relative to run start x** (0/0 = off).
        /// Relative quantity during lowering only needs scale multiply; snapshot translation
        /// naturally avoids change. See TextProps.fade_right.
        fade_dx0: f32 = 0,
        fade_dx1: f32 = 0,
    },
    image_quad: struct {
        header: ItemHeader,
        x: f32,
        y: f32,
        w: f32,
        h: f32,
        texture_id: u32,
        tint: Color = Color.WHITE,
        corner_radius: f32 = 0,
        opacity: f32 = 1,
        rotate: f32 = 0,
    },
    icon_rep: struct {
        header: ItemHeader,
        icon_id: u16,
        rep_size: u8,
        rep: icon_ir.Rep,
        x: f32,
        y: f32,
        w: f32,
        h: f32,
        tint: Color = Color.WHITE,
        corner_clip_radius: f32 = 0,
        opacity: f32 = 1,
        rotate: f32 = 0,
        /// Snap the quad to device pixels (static icons, like static_crisp text).
        /// The mask is rasterized at whole physical pixels; drawn at a fractional
        /// offset, bilinear sampling smears each stroke over two pixels.
        snap: bool = true,
    },
    arc: struct {
        header: ItemHeader,
        cx: f32,
        cy: f32,
        outer_radius: f32,
        stroke_width: f32,
        start_angle: f32,
        end_angle: f32,
        color: Color,
    },
    /// Multi-color gradient (multiple stops)
    multi_gradient_rect: struct {
        header: ItemHeader,
        x: f32,
        y: f32,
        w: f32,
        h: f32,
        direction: GradientDirection = .vertical,
        radius: [4]f32 = .{ 0, 0, 0, 0 },
        stop_colors: [16]Color = @as([16]Color, @splat(Color.rgba(0, 0, 0, 0))),
        stop_positions: [16]f32 = @as([16]f32, @splat(0)),
        stop_count: u8 = 0,
        radial_center_x: f32 = 0,
        radial_center_y: f32 = 0,
        /// Radial ellipse radii (UV units; 0.5 = inscribed).
        radial_radius_x: f32 = 0.5,
        radial_radius_y: f32 = 0.5,
        conic_start_angle: f32 = 0,
        extend_mode: types.GradientExtendMode = .pad,
        /// See fill_rect.shape (0 = rounded_rect, 1 = ellipse). Gradient must also obey shape, else
        /// ellipse gradient fills entire bounding box.
        shape: u8 = 0,
    },
    /// Procedural noise texture
    noise_rect: struct {
        header: ItemHeader,
        x: f32,
        y: f32,
        w: f32,
        h: f32,
        fill: Color,
        mode: u8 = 1,
        scale: f32 = 2.0,
        intensity: f32 = 0.04,
        seed: u8 = 0,
        radius: [4]f32 = .{ 0, 0, 0, 0 },
    },
    /// Inset Shadow inner shadow
    inset_shadow_rect: struct {
        header: ItemHeader,
        x: f32,
        y: f32,
        w: f32,
        h: f32,
        fill: Color,
        shadow_color: Color,
        blur: f32,
        offset_x: f32 = 0,
        offset_y: f32 = 0,
        radius: [4]f32 = .{ 0, 0, 0, 0 },
    },
    /// Double outer shadow
    shadow_dual_rect: struct {
        header: ItemHeader,
        x: f32,
        y: f32,
        w: f32,
        h: f32,
        fill: Color,
        shadow1_color: Color,
        shadow1_blur: f32,
        shadow1_offset_x: f32 = 0,
        shadow1_offset_y: f32 = 0,
        shadow2_color: Color,
        shadow2_blur: f32,
        shadow2_offset_x: f32 = 0,
        shadow2_offset_y: f32 = 0,
        radius: [4]f32 = .{ 0, 0, 0, 0 },
    },
    /// Vector path fill (local coordinates, offset relative to node top-left)
    fill_path: struct {
        header: ItemHeader,
        /// PathGeometry lifetime managed by caller (scene runtime)
        geometry: *const types.PathGeometry,
        color: Color,
        offset_x: f32 = 0,
        offset_y: f32 = 0,
        opacity: f32 = 1.0,
        /// Optional gradient fill. `gradient_direction == 0` means pure color via `color`.
        /// Per-vertex coloring done by path_renderer (GPU PathVertex.color already supported),
        /// polygon gradient fill (triangle/star) via this, else degrades to pure color.
        gradient_direction: u8 = 0,
        gradient_stop_colors: [16]Color = @as([16]Color, @splat(Color.rgba(0, 0, 0, 0))),
        gradient_stop_positions: [16]f32 = @as([16]f32, @splat(0)),
        gradient_stop_count: u8 = 0,
        gradient_center_x: f32 = 0.5,
        gradient_center_y: f32 = 0.5,
        gradient_start_angle: f32 = 0,
    },
    /// Vector path stroke (local coordinates, offset relative to node top-left)
    stroke_path: struct {
        header: ItemHeader,
        geometry: *const types.PathGeometry,
        color: Color,
        width: f32 = 1.0,
        line_join: types.LineJoin = .miter,
        offset_x: f32 = 0,
        offset_y: f32 = 0,
        opacity: f32 = 1.0,
    },

    // ─── Effect/clip literal token variant ───
    // Effect bridge tokens already lowered to active content frame.
    // Node-owned push_clip is exception: node_local requests same
    // property-tree/replay transform as paint items before encoder dispatch.

    push_clip: struct {
        header: ItemHeader,
        /// Node clips share the paint item transform; literal bridge/snapshot clips are already lowered.
        node_local: bool = false,
        x: f32,
        y: f32,
        w: f32,
        h: f32,
        /// Corner radii TL, TR, BR, BL (read for .rounded_rect only).
        radii: [4]f32 = .{ 0, 0, 0, 0 },
        shape_kind: ClipShapeKind = .rect,
        /// By reference (null = empty): a 32-point polygon is most of the item, and every item
        /// of the union paid for it. DisplayList.append freezes it into the list's payload
        /// arena; cached copies own theirs (render_cache.duplicateDisplayItem).
        polygon: ?*const ClipPolygon = null,
    },
    pop_clip: struct {
        header: ItemHeader,
    },

    begin_opacity_layer: struct {
        header: ItemHeader,
        x: f32,
        y: f32,
        w: f32,
        h: f32,
        opacity: f32,
        /// Stage 3 rounded-clip fold: when same-node rounded_clip folds into opacity layer, rounded
        /// mask radii TL, TR, BR, BL applied by composite blit (all 0 = no mask).
        corner_radii: [4]f32 = .{ 0, 0, 0, 0 },
        rotate: f32 = 0,
        draw_x: f32 = std.math.nan(f32),
        draw_y: f32 = std.math.nan(f32),
        draw_w: f32 = std.math.nan(f32),
        draw_h: f32 = std.math.nan(f32),
        use_draw_transform: bool = false,
        draw_transform: types.Transform2D = types.Transform2D.identity(),
        /// draw_transform's translation at rest (CompositedLayer.surface_rest_origin).
        surface_rest_origin: ?[2]f32 = null,
        blend_mode: types.BlendMode = .normal,
        /// Lens warp of the layer surface at composite (see types.ContentWarp; {cap, edge,
        /// fade_start, fade_width} logical px; all zero = none).
        warp: [4]f32 = .{ 0, 0, 0, 0 },
        /// Genie mesh composite of the layer surface (anchor transitions; see genie_warp.zig).
        /// Inactive by default. Backends without a mesh composite use `draw_transform`.
        genie: genie_warp.Warp = .{},
        /// GPU retained composite cache key.
        ///
        /// `surface_stable_id` = this layer's cross-frame stable identity (packed raw of retained
        /// LayerId,
        /// includes generation ABA guard); `surface_content_version` = content version, incremented
        /// once
        /// per content change. Encoder: same layer and unchanged content -> reuse last frame's
        /// rasterized offscreen texture and skip the content pass.
        ///
        /// INVALID (= std.math.maxInt(u32)) means the layer doesn't participate in GPU retained
        /// (non-promoted / no stable identity); the encoder must repaint every frame (safe
        /// default).
        surface_stable_id: u32 = INVALID_SURFACE_ID,
        surface_content_version: u32 = 0,
    },
    end_opacity_layer: struct {
        header: ItemHeader,
    },

    begin_blur_layer: struct {
        header: ItemHeader,
        x: f32,
        y: f32,
        w: f32,
        h: f32,
        /// Glass shape corner radii TL/TR/BR/BL, as written on the owner (the same values its
        /// overflow clip and hit shape read). Raw: the encoder normalises them against the rect the
        /// glass is evaluated over (src/corner_radii.zig), like every other rounded shape.
        corner_radii: [4]f32 = .{ 0, 0, 0, 0 },
        /// glass owner node id (stable key for luminance region slot; header is CONTROL without it)
        owner_node: u32 = std.math.maxInt(u32),
        /// By reference (it is most of the item: every item of the union paid its ~520 bytes).
        /// DisplayList.append freezes it into the list's payload arena; cached copies own theirs
        /// (render_cache.duplicateDisplayItem).
        glass: *const types.ResolvedGlassParams = &default_glass,
        rotate: f32 = 0,
        draw_x: f32 = std.math.nan(f32),
        draw_y: f32 = std.math.nan(f32),
        draw_w: f32 = std.math.nan(f32),
        draw_h: f32 = std.math.nan(f32),
        use_draw_transform: bool = false,
        draw_transform: types.Transform2D = types.Transform2D.identity(),
        /// draw_transform's translation at rest (CompositedLayer.surface_rest_origin).
        surface_rest_origin: ?[2]f32 = null,
    },
    end_blur_layer: struct {
        header: ItemHeader,
    },

    begin_rounded_clip: struct {
        header: ItemHeader,
        x: f32,
        y: f32,
        w: f32,
        h: f32,
        /// Corner radii TL, TR, BR, BL.
        radii: [4]f32,
        rotate: f32 = 0,
        draw_x: f32 = std.math.nan(f32),
        draw_y: f32 = std.math.nan(f32),
        draw_w: f32 = std.math.nan(f32),
        draw_h: f32 = std.math.nan(f32),
        use_draw_transform: bool = false,
        draw_transform: types.Transform2D = types.Transform2D.identity(),
        /// draw_transform's translation at rest (CompositedLayer.surface_rest_origin).
        surface_rest_origin: ?[2]f32 = null,
    },
    end_rounded_clip: struct {
        header: ItemHeader,
    },

    /// Return common ItemHeader of all variants (eliminate caller's switch repetition)
    pub fn header(self: *const DisplayItem) ItemHeader {
        // By pointer: a by-value receiver / capture copies the whole item (a push_clip carries a
        // 32-point polygon), which made per-item header reads in whole-list scans memcpy-bound.
        return switch (self.*) {
            inline else => |*it| it.header,
        };
    }

    /// Mutable header access: cross-frame cache splice rewrites frame-local
    /// transform/clip/effect_id to this frame's values by node_id (see render_engine
    /// rewriteSplicedItemHeaders).
    /// Control items (layer begin/end, push/pop clip) only group/toggle state, no geometry.
    /// The scroll-clip token carries a **real header** (node_id = the node that sent it); any scan
    /// by node_id attributing "child subtree content" must skip it, else the token is treated as
    /// that node's last content.
    pub fn isControl(self: DisplayItem) bool {
        return switch (self) {
            .begin_opacity_layer,
            .end_opacity_layer,
            .begin_blur_layer,
            .end_blur_layer,
            .begin_rounded_clip,
            .end_rounded_clip,
            .push_clip,
            .pop_clip,
            => true,
            else => false,
        };
    }

    pub fn headerPtr(self: *DisplayItem) *ItemHeader {
        return switch (self.*) {
            inline else => |*it| &it.header,
        };
    }
};

pub const TextRunItem = @FieldType(DisplayItem, "text_run");

pub const DisplayList = struct {
    allocator: Allocator,
    items: std.ArrayList(DisplayItem),
    /// Pointer-backed items can be replayed after their node/cache/snapshot has
    /// rebuilt or been replaced, and the list of the displayed frame is read again
    /// in the next frame before it is rebuilt (`Snapshot.captureDisplayed`), when
    /// the nodes that painted it may be gone. Everything an item points to is
    /// copied here: text bytes and spans, path geometry, clip polygons, glass
    /// parameters with their group shape table. Nothing is borrowed from a node,
    /// a component or the application. (An icon's `rep.shapes` is program data.)
    payload_arena: std.heap.ArenaAllocator,
    /// Retained display lists cache content identities for replay/lowering.
    /// A transient producer whose consumers never read them may opt out.
    record_content_fingerprints: bool = true,
    /// Set by trimIdleCapacity: payload capacity the next clear keeps.
    idle_payload_limit: ?usize = null,

    pub fn init(allocator: Allocator) DisplayList {
        return .{
            .allocator = allocator,
            .items = .empty,
            .payload_arena = std.heap.ArenaAllocator.init(allocator),
        };
    }

    pub fn deinit(self: *DisplayList) void {
        self.items.deinit(self.allocator);
        self.payload_arena.deinit();
    }

    pub const MemoryStats = struct { item_capacity_bytes: usize, payload_capacity_bytes: usize };
    pub fn memoryStats(self: *const DisplayList) MemoryStats {
        return .{ .item_capacity_bytes = self.items.capacity * @sizeOf(DisplayItem), .payload_capacity_bytes = self.payload_arena.queryCapacity() };
    }

    pub fn clear(self: *DisplayList) void {
        self.items.clearRetainingCapacity();
        _ = self.payload_arena.reset(if (self.idle_payload_limit) |limit| .{ .retain_with_limit = limit } else .retain_capacity);
        self.idle_payload_limit = null;
    }

    /// Preserve the live replay and its owned payload; release only spare
    /// item capacity now. Payload pages shrink at the next normal clear.
    /// Returns the item bytes released.
    pub fn trimIdleCapacity(self: *DisplayList, retain_bytes: usize) usize {
        self.idle_payload_limit = retain_bytes;
        const len = self.items.items.len;
        const target = @max(len, retain_bytes / @sizeOf(DisplayItem));
        if (self.items.capacity <= target *| 2) return 0;
        const replacement = self.allocator.alloc(DisplayItem, target) catch return 0;
        @memcpy(replacement[0..len], self.items.items);
        const old_bytes = self.items.capacity * @sizeOf(DisplayItem);
        self.items.deinit(self.allocator);
        self.items = .fromOwnedSlice(replacement);
        self.items.items.len = len;
        return old_bytes - target * @sizeOf(DisplayItem);
    }

    pub fn append(self: *DisplayList, item: DisplayItem) !void {
        _ = try self.appendPtr(&item);
    }

    /// append, copying the item once, straight into the list (items are a few hundred bytes and
    /// this runs for every item of every frame). Returns the stored item; nothing is stored on
    /// error.
    pub fn appendPtr(self: *DisplayList, item: *const DisplayItem) !*DisplayItem {
        // An item of this list itself would move with the growth below: copy it out first.
        const own = self.items.items;
        if (own.len > 0 and @intFromPtr(item) >= @intFromPtr(own.ptr) and @intFromPtr(item) < @intFromPtr(own.ptr + own.len)) {
            const copy = item.*;
            return self.appendPtrUnaliased(&copy);
        }
        return self.appendPtrUnaliased(item);
    }

    fn appendPtrUnaliased(self: *DisplayList, item: *const DisplayItem) !*DisplayItem {
        try self.items.ensureUnusedCapacity(self.allocator, 1);
        const slot = self.items.addOneAssumeCapacity();
        slot.* = item.*;
        errdefer self.items.items.len -= 1;
        switch (slot.*) {
            .text_run => |*text| {
                const arena = self.payload_arena.allocator();
                text.content = if (text.content.len > 0) try arena.dupe(u8, text.content) else "";
                if (text.spans) |spans| {
                    text.spans = if (spans.len > 0) try arena.dupe(types.TextSpan, spans) else null;
                }
            },
            .fill_path => |*path| path.geometry = try self.clonePathGeometry(path.geometry),
            .stroke_path => |*path| path.geometry = try self.clonePathGeometry(path.geometry),
            .begin_blur_layer => |*blur| {
                const arena = self.payload_arena.allocator();
                const glass = try arena.create(types.ResolvedGlassParams);
                glass.* = blur.glass.*;
                // The shape table of a glass group is content of the item like the rest.
                if (glass.group) |table| {
                    const own = try arena.create(types.GlassGroupShapes);
                    own.* = table.*;
                    glass.group = own;
                }
                blur.glass = glass;
            },
            .push_clip => |*clip| clip.polygon = try self.clonePolygon(clip.polygon),
            .border_side => |*border| border.clip_polygon = try self.clonePolygon(border.clip_polygon),
            else => {},
        }
        // Recorded content: fingerprinted once, then carried by every replay.
        const hp = slot.headerPtr();
        if (hp.local_fp == 0 and !hp.already_lowered and self.record_content_fingerprints) hp.local_fp = contentFingerprint(slot);
        return slot;
    }

    fn clonePolygon(self: *DisplayList, source: ?*const ClipPolygon) !?*const ClipPolygon {
        const p = source orelse return null;
        const clone = try self.payload_arena.allocator().create(ClipPolygon);
        clone.* = p.*;
        return clone;
    }

    fn clonePathGeometry(self: *DisplayList, source: *const types.PathGeometry) !*const types.PathGeometry {
        const arena = self.payload_arena.allocator();
        const clone = try arena.create(types.PathGeometry);
        clone.* = source.*;
        clone.commands = try arena.dupe(types.PathCommand, source.commands);
        // The arena owns the command slice and releases it as a group.
        clone.owned = false;
        return clone;
    }

    pub fn slice(self: *const DisplayList, start: usize, len: usize) []const DisplayItem {
        const clamped_start = @min(start, self.items.items.len);
        const clamped_end = @min(clamped_start + len, self.items.items.len);
        return self.items.items[clamped_start..clamped_end];
    }

    pub fn count(self: *const DisplayList) usize {
        return self.items.items.len;
    }
};

/// Drop a run's reference to the frame's blob store, for an item kept past the frame (command
/// cache, payload cache): the number would name another text's layout once the store is
/// renumbered. The bytes stay with the item (`content`).
pub fn detachTextRunFromFrame(run: *TextRunItem) void {
    run.blob_id = INVALID_ID;
    run.blob_byte_start = 0;
    run.blob_byte_end = 0;
}

test "DisplayList: a text run's bytes and spans are the list's own" {
    // Whoever reads the list later (lowering, a capture of the displayed frame in the next frame,
    // a replay) reads what was appended, whatever became of the storage it was appended from.
    const testing = std.testing;
    var list = DisplayList.init(testing.allocator);
    defer list.deinit();
    const source = try testing.allocator.dupe(u8, "bytes of the producer");
    const source_spans = try testing.allocator.dupe(TextSpan, &.{.{ .start = 0, .end = 5, .color = .{ .r = 1, .g = 2, .b = 3, .a = 255 } }});
    try list.append(.{ .text_run = .{
        .header = .{ .transform_id = 0, .node_id = 0 },
        .x = 0,
        .y = 0,
        .content = source,
        .blob_byte_start = 0,
        .blob_byte_end = @intCast(source.len),
        .color = .{ .r = 0, .g = 0, .b = 0, .a = 255 },
        .font_size = 13,
        .spans = source_spans,
        // A number another text holds by now (or none at all) does not change the bytes.
        .blob_id = 7,
    } });
    @memset(source, 'X');
    testing.allocator.free(source);
    source_spans[0].end = 99;
    testing.allocator.free(source_spans);
    const run = list.items.items[0].text_run;
    try testing.expectEqualStrings("bytes of the producer", run.content);
    try testing.expectEqual(@as(u32, 5), run.spans.?[0].end);
}

test "DisplayList: a blur layer's glass parameters and group shape table are the list's own" {
    const testing = std.testing;
    var list = DisplayList.init(testing.allocator);
    defer list.deinit();
    const table = try testing.allocator.create(types.GlassGroupShapes);
    table.* = .{ .count = 2, .version = 9 };
    table.shapes[1] = .{ .node_id = 5, .x = 30, .w = 44, .h = 44, .radius = 22 };
    const glass = try testing.allocator.create(types.ResolvedGlassParams);
    glass.* = .{ .backdrop_blur = 12, .group = table };
    try list.append(.{ .begin_blur_layer = .{ .header = .{ .transform_id = 0, .node_id = 0 }, .x = 0, .y = 0, .w = 100, .h = 44, .glass = glass } });
    const fp = list.items.items[0].header().local_fp;
    testing.allocator.destroy(glass);
    testing.allocator.destroy(table);
    const own = list.items.items[0].begin_blur_layer.glass;
    try testing.expectEqual(@as(f32, 12), own.backdrop_blur);
    try testing.expectEqual(@as(u8, 2), own.group.?.count);
    try testing.expectEqual(@as(u32, 9), own.group.?.version);
    try testing.expectEqual(@as(f32, 30), own.group.?.shapes[1].x);
    // The copy is the same content: the fingerprint follows the table, not its address.
    try testing.expectEqual(fp, contentFingerprint(&list.items.items[0]));
}

test "contentFingerprint names content: not ids, blob numbers or payload addresses" {
    const testing = std.testing;
    const run = TextRunItem{
        .header = .{ .transform_id = 3, .clip_id = 4, .node_id = 9 },
        .x = 10,
        .y = 20,
        .content = "hello",
        .color = .{ .r = 1, .g = 2, .b = 3, .a = 255 },
        .font_size = 14,
    };
    const base = contentFingerprint(&.{ .text_run = run });
    try testing.expect(base != 0);
    // Frame-local ids and the blob sequence number are not content.
    var moved_ids = run;
    moved_ids.header = .{ .transform_id = 30, .clip_id = 40, .effect_id = 5, .node_id = 9, .local_fp = 77 };
    moved_ids.blob_id = 123;
    try testing.expectEqual(base, contentFingerprint(&.{ .text_run = moved_ids }));
    // The same bytes elsewhere in memory are the same content.
    var copy_buf: [5]u8 = "hello".*;
    var same_text = run;
    same_text.content = &copy_buf;
    try testing.expectEqual(base, contentFingerprint(&.{ .text_run = same_text }));
    // Every content field counts: text, colour, size, position.
    var other = run;
    other.content = "hellp";
    try testing.expect(contentFingerprint(&.{ .text_run = other }) != base);
    other = run;
    other.color.g = 7;
    try testing.expect(contentFingerprint(&.{ .text_run = other }) != base);
    other = run;
    other.font_size = 14.5;
    try testing.expect(contentFingerprint(&.{ .text_run = other }) != base);
    other = run;
    other.x = 11;
    try testing.expect(contentFingerprint(&.{ .text_run = other }) != base);
}

test "a recorded item is fingerprinted once and replays carry it" {
    const testing = std.testing;
    var list = DisplayList.init(testing.allocator);
    defer list.deinit();
    const stored = try list.appendPtr(&.{ .fill_rect = .{ .header = .{ .transform_id = 0, .node_id = 1 }, .x = 1, .y = 2, .w = 3, .h = 4, .color = .{ .r = 9, .g = 0, .b = 0, .a = 255 } } });
    const fp = stored.header().local_fp;
    try testing.expect(fp != 0);
    try testing.expectEqual(contentFingerprint(stored), fp);
    // A replay (an item already fingerprinted) keeps its value.
    const replay = stored.*;
    const again = try list.appendPtr(&replay);
    try testing.expectEqual(fp, again.header().local_fp);
}

// ─── contentFingerprint equivalence (buffered stream vs field-by-field reference) ───

const FingerprintGen = struct {
    rng: std.Random,
    arena: Allocator,
    /// Every optional present (so the leaves inside optionals get mutated too).
    all_present: bool = false,

    fn fill(self: *FingerprintGen, ptr: anytype, comptime depth: u32) Allocator.Error!void {
        const T = @typeInfo(@TypeOf(ptr)).pointer.child;
        switch (@typeInfo(T)) {
            .void => {},
            .bool => ptr.* = self.rng.boolean(),
            // Small integers in float form: exercise equal values as well as the bit pattern.
            .float => ptr.* = @floatFromInt(self.rng.intRangeAtMost(i32, -64, 64)),
            .int => ptr.* = self.rng.int(T),
            .@"enum" => {
                const values = comptime std.enums.values(T);
                ptr.* = values[self.rng.uintLessThan(usize, values.len)];
            },
            // Optional pointers stop at the followed depth (deeper pointees hash their address,
            // which would make two equal-content builds differ).
            .optional => |o| if ((comptime @typeInfo(o.child) == .pointer and @typeInfo(o.child).pointer.size == .one and depth >= 2) or
                (!self.all_present and self.rng.uintLessThan(u8, 4) == 0))
            {
                ptr.* = null;
            } else {
                var v: o.child = undefined;
                try self.fill(&v, depth);
                ptr.* = v;
            },
            .array => for (ptr) |*v| try self.fill(v, depth),
            .pointer => |p| switch (p.size) {
                .slice => {
                    const n = self.rng.uintAtMost(usize, if (p.child == u8) 12 else 3);
                    const items = try self.arena.alloc(p.child, n);
                    for (items) |*v| try self.fill(v, depth);
                    ptr.* = items;
                },
                .one => {
                    if (comptime depth >= 3) @compileError("FingerprintGen: pointer past the followed depth in " ++ @typeName(T));
                    const v = try self.arena.create(p.child);
                    try self.fill(v, depth + 1);
                    ptr.* = v;
                },
                else => @compileError("FingerprintGen: unsupported pointer " ++ @typeName(T)),
            },
            .@"struct" => |info| inline for (info.field_names) |name| try self.fill(&@field(ptr.*, name), depth),
            .@"union" => |info| {
                const k = self.rng.uintLessThan(usize, info.field_names.len);
                inline for (info.field_names, info.field_types) |name, FT| {
                    if (k == comptime std.meta.fieldIndex(T, name).?) {
                        var payload: FT = undefined;
                        try self.fill(&payload, depth);
                        ptr.* = @unionInit(T, name, payload);
                    }
                }
            },
            else => @compileError("FingerprintGen: unsupported " ++ @typeName(T)),
        }
    }

    /// Change the `target`-th content leaf of `ptr` (header and blob_id are not content;
    /// pointees past the followed depth hash their address). Returns true once it changed one.
    fn mutate(ptr: anytype, index: *usize, target: usize, comptime depth: u32) bool {
        const T = @typeInfo(@TypeOf(ptr)).pointer.child;
        switch (@typeInfo(T)) {
            .void => return false,
            .bool, .float, .int, .@"enum" => {
                defer index.* += 1;
                if (index.* != target) return false;
                switch (@typeInfo(T)) {
                    .bool => ptr.* = !ptr.*,
                    .float => |f| {
                        const U = @Int(.unsigned, f.bits);
                        ptr.* = @bitCast(@as(U, @bitCast(ptr.*)) ^ 1);
                    },
                    .int => ptr.* +%= 1,
                    .@"enum" => {
                        const values = comptime std.enums.values(T);
                        if (values.len < 2) return false;
                        for (values, 0..) |v, i| if (v == ptr.*) {
                            ptr.* = values[(i + 1) % values.len];
                            break;
                        };
                    },
                    else => unreachable,
                }
                return true;
            },
            .optional => {
                if (ptr.*) |*v| {
                    if (mutate(v, index, target, depth)) return true;
                }
                // The presence bit itself: drop the payload.
                defer index.* += 1;
                if (index.* != target or ptr.* == null) return false;
                ptr.* = null;
                return true;
            },
            .array => {
                for (ptr) |*v| if (mutate(v, index, target, depth)) return true;
                return false;
            },
            .pointer => |p| switch (p.size) {
                .slice => {
                    for (@constCast(ptr.*)) |*v| if (mutate(v, index, target, depth)) return true;
                    // The length: shorten by one.
                    defer index.* += 1;
                    if (index.* != target or ptr.len == 0) return false;
                    ptr.* = ptr.*[0 .. ptr.len - 1];
                    return true;
                },
                .one => return if (depth < 3) mutate(@constCast(ptr.*), index, target, depth + 1) else false,
                else => return false,
            },
            .@"struct" => |info| {
                inline for (info.field_names, info.field_types) |name, FT| {
                    if (comptime !(FT == ItemHeader or std.mem.eql(u8, name, "blob_id"))) {
                        if (mutate(&@field(ptr.*, name), index, target, depth)) return true;
                    }
                }
                return false;
            },
            .@"union" => {
                switch (ptr.*) {
                    inline else => |*v| return mutate(v, index, target, depth),
                }
            },
            else => return false,
        }
    }
};

fn expectFingerprintsAgree(item: *const DisplayItem) !u64 {
    const fp = contentFingerprint(item);
    try std.testing.expectEqual(contentFingerprintStreamed(item), fp);
    return fp;
}

fn generateItem(comptime name: []const u8, seed: u64, arena: Allocator, all_present: bool) !DisplayItem {
    var prng = std.Random.DefaultPrng.init(seed);
    var gen: FingerprintGen = .{ .rng = prng.random(), .arena = arena, .all_present = all_present };
    var payload: @FieldType(DisplayItem, name) = undefined;
    try gen.fill(&payload, 0);
    return @unionInit(DisplayItem, name, payload);
}

test "contentFingerprint: buffered stream equals the field-by-field reference, every variant" {
    const testing = std.testing;
    var prng = std.Random.DefaultPrng.init(0x5eed);
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var leaves_checked: usize = 0;
    inline for (comptime std.meta.fieldNames(DisplayItem)) |name| {
        for (0..32) |round| {
            defer _ = arena.reset(.retain_capacity);
            const seed = prng.random().int(u64);
            const all_present = round % 2 == 0;

            // Equal content, built twice in different memory (every pointer and slice differs),
            // with different headers and blob numbers (not content).
            const a = try generateItem(name, seed, arena.allocator(), all_present);
            var b = try generateItem(name, seed, arena.allocator(), all_present);
            b.headerPtr().* = .{ .transform_id = 77, .clip_id = 5, .effect_id = 6, .node_id = 8, .paint_order = 9, .local_fp = 1234 };
            if (comptime std.mem.eql(u8, name, "text_run")) b.text_run.blob_id = 4321;
            const base = try expectFingerprintsAgree(&a);
            try testing.expect(base != 0);
            try testing.expectEqual(base, try expectFingerprintsAgree(&b));

            // Every content leaf changed on its own (fresh copy each time): both fingerprints
            // change, and they still agree.
            var target: usize = 0;
            while (true) : (target += 1) {
                var m = try generateItem(name, seed, arena.allocator(), all_present);
                var index: usize = 0;
                const changed = switch (m) {
                    inline else => |*v| FingerprintGen.mutate(v, &index, target, 0),
                };
                if (target >= index) break; // walked past the last leaf
                if (!changed) continue; // single-valued enum / absent optional / empty slice
                leaves_checked += 1;
                if (try expectFingerprintsAgree(&m) == base) {
                    std.debug.print("contentFingerprint: {s} leaf {d}: change not seen\n", .{ name, target });
                    return error.TestUnexpectedResult;
                }
            }
        }
    }
    try testing.expect(leaves_checked > 1000);
}

test "contentFingerprint: variants with equal payload bytes differ by tag" {
    const h: ItemHeader = .{ .transform_id = 0, .node_id = 0 };
    const fps = [_]u64{
        try expectFingerprintsAgree(&.{ .pop_clip = .{ .header = h } }),
        try expectFingerprintsAgree(&.{ .end_opacity_layer = .{ .header = h } }),
        try expectFingerprintsAgree(&.{ .end_blur_layer = .{ .header = h } }),
        try expectFingerprintsAgree(&.{ .end_rounded_clip = .{ .header = h } }),
    };
    for (fps, 0..) |x, i| for (fps[i + 1 ..]) |y| try std.testing.expect(x != y);
}

test "contentFingerprint never reads padding: same fields over different garbage bytes" {
    // The stream is built field by field; the only bulk copies are float arrays (no padding
    // between array elements) and u8 slices. Build the same payload over 0xAA and over 0x55
    // filled memory and fingerprint it through the same path as contentFingerprint.
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    inline for (comptime std.meta.fieldNames(DisplayItem)) |name| {
        const Payload = @FieldType(DisplayItem, name);
        var fps: [2]u64 = undefined;
        for (&fps, [_]u8{ 0xAA, 0x55 }) |*fp, garbage| {
            var storage: [@sizeOf(Payload)]u8 align(@alignOf(Payload)) = undefined;
            @memset(&storage, garbage);
            const payload: *Payload = @ptrCast(&storage);
            var prng = std.Random.DefaultPrng.init(0xabc);
            var gen: FingerprintGen = .{ .rng = prng.random(), .arena = arena.allocator(), .all_present = true };
            // Leaf-wise fill in place (struct fields are written one by one; padding keeps garbage).
            try gen.fill(payload, 0);
            var sink: FingerprintSink = .{ .h = std.hash.Wyhash.init(fingerprint_seed) };
            serializeContent(&sink, payload, 0);
            fp.* = sink.final();
        }
        try testing.expectEqual(fps[0], fps[1]);
    }
}

