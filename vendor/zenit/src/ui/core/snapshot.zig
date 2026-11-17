const std = @import("std");
const Allocator = std.mem.Allocator;

const node_mod = @import("node.zig");
const types = @import("types.zig");
const render_engine = @import("render_engine/mod.zig");
const display_list_mod = @import("display_list.zig");
const text_layout = @import("text_layout.zig");
const text_blob_mod = @import("text_blob.zig");
const scene_runtime_mod = @import("scene_runtime.zig");
const property_tree_mod = @import("property_tree.zig");
const layer_tree_mod = @import("layer_tree.zig");
const lowering = @import("render_engine/display_list_lowering.zig");
const hit_runtime_mod = @import("hit_runtime.zig");
const genie_warp = @import("zenit_genie_warp");

const Node = node_mod.Node;
const CachedRenderSlice = node_mod.CachedRenderSlice;
const ComputedRect = types.ComputedRect;
const Point = types.Point;
const Transform2D = types.Transform2D;
const DisplayItem = display_list_mod.DisplayItem;
const ItemHeader = display_list_mod.ItemHeader;
const INVALID_ID = property_tree_mod.INVALID_ID;
const DrawContext = render_engine.DrawContext;

/// Translate only absolute geometry in an already lowered command. Relative
/// attributes (shadow offsets, text fade windows, polygon points) stay unchanged.
fn offsetDisplayItem(it: DisplayItem, dx: f32, dy: f32) DisplayItem {
    // Copy the full payload. Rebuilding each variant field-by-field silently
    // dropped font_family, fade windows, shape and path-gradient attributes.
    var out = it;
    switch (out) {
        inline else => |*value, tag| {
            const T = @TypeOf(value.*);
            if (@hasField(T, "x")) value.x += dx;
            if (@hasField(T, "y")) value.y += dy;
            if (@hasField(T, "cx")) value.cx += dx;
            if (@hasField(T, "cy")) value.cy += dy;
            if (tag == .border_side) {
                value.clip_x += dx;
                value.clip_y += dy;
            }
            if (tag == .fill_path or tag == .stroke_path) {
                value.offset_x += dx;
                value.offset_y += dy;
            }
        },
    }
    return out;
}

pub const Snapshot = struct {
    commands: CachedRenderSlice,
    local_bounds: ComputedRect,
    local_transform_origin: Point,
    captured_world_origin: Point,
    /// The captured node's top-left in snapshot-local space. (0, 0) for `node_rect`; with
    /// `command_bounds` it is offset by whatever paints above / left of the node (an outer
    /// shadow), which the local bounds include.
    node_offset: Point = .{ .x = 0, .y = 0 },
    allocator: Allocator,

    fn fromCommands(
        cx: anytype,
        commands: []const DisplayItem,
        geometry: SnapshotGeometry,
        capture_origin: Point,
    ) !?*Snapshot {
        if (commands.len == 0) return null;

        // The snapshot's own copy, payloads included (text bytes, spans, path geometry, glass):
        // it outlives the frame and the nodes it was captured from.
        const duped = try node_mod.duplicateDisplayItems(cx.allocator, commands);
        errdefer node_mod.freeDuplicatedDisplayItems(cx.allocator, duped);

        // Only commands in the capture's outer frame move. Surface contents are
        // already owner-local; shifting them again would displace their clips.
        var depth: usize = 0;
        for (duped) |*item| {
            const dx = -geometry.offset_origin.x;
            const dy = -geometry.offset_origin.y;
            switch (item.*) {
                .begin_opacity_layer => |*layer| {
                    layer.surface_stable_id = display_list_mod.INVALID_SURFACE_ID;
                    if (depth == 0) offsetLayerComposite(layer, dx, dy);
                    depth += 1;
                },
                .begin_rounded_clip => |*layer| {
                    if (depth == 0) offsetLayerComposite(layer, dx, dy);
                    depth += 1;
                },
                .end_opacity_layer, .end_rounded_clip => depth -|= 1,
                .begin_blur_layer => |*layer| {
                    if (depth == 0) offsetLayerComposite(layer, dx, dy);
                },
                else => if (depth == 0) {
                    item.* = offsetDisplayItem(item.*, dx, dy);
                },
            }
        }

        const self = try cx.allocator.create(Snapshot);
        errdefer cx.allocator.destroy(self);
        self.* = .{
            .commands = .{
                .commands = duped,
                .scroll_offset_x = 0,
                .scroll_offset_y = 0,
                .self_content_command_count = @intCast(duped.len),
                .descendant_content_command_count = 0,
                .descendant_regular_command_count = 0,
                .descendant_sticky_command_count = 0,
                .descendant_overlay_command_count = 0,
                .descendant_tail_command_count = 0,
                .regular_child_slices = &.{},
                .content_version = 0,
                .composite_version = 0,
                .promoted_layer_id = std.math.maxInt(u32),
                .world_bounds = geometry.local_bounds,
                .world_transform = Transform2D.identity(),
                .allocator = cx.allocator,
            },
            .local_bounds = geometry.local_bounds,
            .local_transform_origin = geometry.local_transform_origin,
            .node_offset = geometry.node_offset,
            .captured_world_origin = capture_origin,
            .allocator = cx.allocator,
        };
        return self;
    }

    pub const GeometryMode = enum {
        command_bounds,
        node_rect,
    };

    pub const CaptureOptions = struct {
        geometry_mode: GeometryMode = .command_bounds,
    };

    pub fn capture(cx: anytype, node: *Node) !?*Snapshot {
        return captureWithOptions(cx, node, .{});
    }

    pub fn captureWithOptions(cx: anytype, node: *Node, options: CaptureOptions) !?*Snapshot {
        const node_rect = node.rectFromWorldOrFallback();
        if (node.frame_state.state_bits.dirty.core.layout) return null;
        if (node_rect.w <= 0.001 or node_rect.h <= 0.001) return null;

        var render_list: std.ArrayList(DisplayItem) = .empty;
        defer render_list.deinit(cx.allocator);
        const paint_table_mod = @import("paint_table.zig");
        var render_list_paint: std.ArrayList(paint_table_mod.DisplayItem) = .empty;
        defer render_list_paint.deinit(cx.allocator);

        var display_list = display_list_mod.DisplayList.init(cx.allocator);
        defer display_list.deinit();
        var text_blob_store = text_blob_mod.BlobStore.init(cx.allocator);
        defer text_blob_store.deinit();
        var scene_runtime = scene_runtime_mod.SceneRuntime.init(cx.allocator);
        defer scene_runtime.deinit();
        var property_tree = property_tree_mod.PropertyTree.init(cx.allocator);
        defer property_tree.deinit();
        var perf: hit_runtime_mod.PerfCounters = .{};

        var frame_arena = std.heap.ArenaAllocator.init(cx.allocator);
        defer frame_arena.deinit();

        // Capturing must not replace the live compositor plan with a subtree plan.
        var layer_tree = layer_tree_mod.LayerTree.init(cx.allocator, .{});
        defer layer_tree.deinit();
        var render_ctx = render_engine.RenderContext{
            .lowering_buffer = &render_list,
            .lowering_buffer_paint = &render_list_paint,
            .display_list = &display_list,
            .text_blob_store = &text_blob_store,
            .scene_runtime = &scene_runtime,
            .property_tree = &property_tree,
            .layer_tree = &layer_tree,
            .world = &cx.world,
            .allocator = cx.allocator,
            .frame_allocator = frame_arena.allocator(),
            .viewport = cx.viewport,
            .perf = &perf,
            .external_clip_rects = &cx.external_clip_rects,
        };
        try render_engine.renderNode(&render_ctx, node);

        if (display_list.items.items.len == 0) return null;

        const current_world_rect = node.globalRect();
        const world_origin = Point{ .x = current_world_rect.x, .y = current_world_rect.y };
        render_ctx.capture_lowered = &render_list;
        render_list_paint.clearRetainingCapacity();
        try lowering.appendAllDisplayItemsToRenderList(&render_ctx);
        const items = render_list.items;
        const runtime = scene_runtime.get(node.id) orelse return null;
        const capture_frame_origin = property_tree.transforms.items[runtime.transform_id].world.applyPoint(0, 0);
        const geometry = chooseSnapshotGeometry(node, items, world_origin, options, capture_frame_origin);
        return fromCommands(cx, items, geometry, geometry.capture_origin);
    }

    pub fn captureDisplayed(cx: anytype, node: *Node) !?*Snapshot {
        return captureDisplayedWithOptions(cx, node, .{});
    }

    pub fn captureDisplayedWithOptions(cx: anytype, node: *Node, options: CaptureOptions) !?*Snapshot {
        const node_rect = node.rectFromWorldOrFallback();
        if (node_rect.w <= 0.001 or node_rect.h <= 0.001) return null;

        // Freeze the last emitted subtree while that frame's data is still alive (display list,
        // property tree, layer plan, scene runtime: all reset together when the next frame
        // begins). The tree may have changed since: a dirty node already holds new state, and
        // nodes inside the subtree may be gone. Everything read here belongs to the frame
        // (ids, values and payloads the frame copied), nothing is read through a node.
        if (cx.scene_runtime.get(node.id)) |runtime| {
            // Both parts of a subtree split between the prebuild prefix and the paint tail.
            const segments = runtime.subtreeDisplaySegments();
            const listed = cx.display_list.items.items.len;
            if (segments[0].count + segments[1].count > 0 and segments[0].end() <= listed and segments[1].end() <= listed) {
                var frozen: std.ArrayList(DisplayItem) = .empty;
                defer frozen.deinit(cx.allocator);
                var paint: std.ArrayList(@import("paint_table.zig").DisplayItem) = .empty;
                defer paint.deinit(cx.allocator);
                var arena = std.heap.ArenaAllocator.init(cx.allocator);
                defer arena.deinit();
                var perf: hit_runtime_mod.PerfCounters = .{};
                var ctx = render_engine.RenderContext{
                    .capture_lowered = &frozen,
                    .lowering_buffer = &frozen,
                    .lowering_buffer_paint = &paint,
                    .display_list = &cx.display_list,
                    .text_blob_store = &cx.text_blob_store,
                    .scene_runtime = &cx.scene_runtime,
                    .property_tree = &cx.property_tree,
                    .layer_tree = &cx.layer_tree,
                    .world = &cx.world,
                    .allocator = cx.allocator,
                    .frame_allocator = arena.allocator(),
                    .viewport = cx.viewport,
                    .perf = &perf,
                };
                const parent_effect_id = if (node.parent) |parent|
                    if (cx.scene_runtime.get(parent.id)) |parent_runtime| parent_runtime.effect_id else INVALID_ID
                else
                    INVALID_ID;
                try lowering.appendSnapshotDisplayItems(&ctx, &segments, parent_effect_id);
                var parent_inverse = Transform2D.identity();
                var effect_id = parent_effect_id;
                while (effect_id != INVALID_ID and effect_id < cx.property_tree.effects.items.len) {
                    const effect = cx.property_tree.effects.items[effect_id];
                    if (effect.requires_offscreen and effect.kind != .backdrop_blur) {
                        if (cx.scene_runtime.get(effect.node_id)) |owner| parent_inverse = owner.content_transform.invert();
                        break;
                    }
                    effect_id = effect.parent;
                }
                const frame_origin = parent_inverse.mul(cx.property_tree.transforms.items[runtime.transform_id].world).applyPoint(0, 0);
                const world_rect = node.globalRect();
                const geometry = chooseSnapshotGeometry(node, frozen.items, .{ .x = world_rect.x, .y = world_rect.y }, options, frame_origin);
                return fromCommands(cx, frozen.items, geometry, geometry.capture_origin);
            }
        }
        if (node.frame_state.state_bits.dirty.core.layout) return null;
        return captureWithOptions(cx, node, options);
    }

    pub fn appendTo(
        self: *const Snapshot,
        draw_ctx: DrawContext,
        origin: Point,
        opacity: f32,
        scale: f32,
    ) !void {
        if (opacity <= 0.001 or scale <= 0.001 or self.commands.commands.len == 0) return;
        const frame = draw_ctx.content_from_world;
        const transformed_frame = frame.a != 1 or frame.b != 0 or frame.c != 0 or frame.d != 1 or frame.tx != 0 or frame.ty != 0;
        const use_layer_transform = transformed_frame or @abs(scale - 1.0) > 0.0001 or origin.x != 0 or origin.y != 0 or opacity < 0.999;
        const local = Transform2D.translation(origin.x, origin.y).mul(
            Transform2D.scale(scale, scale, self.local_transform_origin.x, self.local_transform_origin.y),
        );
        return self.appendWithTransform(draw_ctx, local, opacity, use_layer_transform, .{});
    }

    /// Draw the snapshot through an arbitrary affine map from snapshot-local space (the captured
    /// node's top-left is the origin) to world space, for example a non-uniform scale that maps
    /// the captured rect onto another rect (anchor transitions). Always composited as one layer,
    /// so `opacity` applies to the whole picture.
    pub fn appendTransformed(
        self: *const Snapshot,
        draw_ctx: DrawContext,
        local_to_world: Transform2D,
        opacity: f32,
    ) !void {
        if (opacity <= 0.001 or self.commands.commands.len == 0) return;
        const t = local_to_world;
        if (!std.math.isFinite(t.a) or !std.math.isFinite(t.b) or !std.math.isFinite(t.c) or
            !std.math.isFinite(t.d) or !std.math.isFinite(t.tx) or !std.math.isFinite(t.ty)) return;
        if (@abs(t.a * t.d - t.b * t.c) <= 0.000001) return;
        return self.appendWithTransform(draw_ctx, local_to_world, opacity, true, .{});
    }

    /// How `appendWarped` composites the snapshot.
    pub const WarpedDraw = struct {
        /// Affine composite (snapshot-local to world): what backends without a mesh composite
        /// draw, and the layer's placement when `genie` is null.
        fallback: Transform2D,
        /// Where the snapshot rests (snapshot-local to world, no scale): the layer texture is
        /// rasterized on the target's pixel grid there, so the texture lands texel-for-pixel on
        /// the live node at rest and stays the same texture for the whole run.
        rest: Transform2D,
        opacity: f32,
        /// Stable identity of the layer texture across frames (GPU retained surface): with the
        /// content unchanged, the renderer rasterizes the snapshot once and only composites the
        /// cached texture afterwards. INVALID = rasterize every frame.
        surface_id: u32 = display_list_mod.INVALID_SURFACE_ID,
        /// Version of the frozen content under `surface_id` (non-zero; a new snapshot gets a new
        /// one): the renderer keys the cached texture by it instead of hashing the commands.
        content_version: u32 = 0,
        /// Genie mesh composite (window coordinates); `local` is filled in from the captured node
        /// rect (`node_w` x `node_h` at `node_offset`).
        genie: ?genie_warp.Warp = null,
        node_w: f32 = 0,
        node_h: f32 = 0,
        /// Transparent margin around the texture (logical px), so the warped outline is filtered
        /// instead of cut by the mesh edge.
        margin: f32 = 0,
    };

    /// Draw the snapshot as one cached layer texture: through `genie` (mesh) where the renderer
    /// supports it, else through `fallback`. The texture is keyed by `surface_id`.
    pub fn appendWarped(self: *const Snapshot, draw_ctx: DrawContext, d: WarpedDraw) !void {
        if (d.opacity <= 0.001 or self.commands.commands.len == 0) return;
        const t = d.fallback;
        if (!std.math.isFinite(t.a) or !std.math.isFinite(t.b) or !std.math.isFinite(t.c) or
            !std.math.isFinite(t.d) or !std.math.isFinite(t.tx) or !std.math.isFinite(t.ty)) return;
        if (@abs(t.a * t.d - t.b * t.c) <= 0.000001) return;
        var g: ?genie_warp.Warp = d.genie;
        if (g) |*w| w.local = .{ self.node_offset.x, self.node_offset.y, d.node_w, d.node_h };
        return self.appendWithTransform(draw_ctx, d.fallback, d.opacity, true, .{
            .surface_id = d.surface_id,
            .content_version = d.content_version,
            .rest_origin = .{ d.rest.tx, d.rest.ty },
            .genie = g,
            .margin = @max(d.margin, 0),
        });
    }

    fn restOrigin(frame: Transform2D, r: [2]f32) [2]f32 {
        const p = frame.applyPoint(r[0], r[1]);
        return .{ p.x, p.y };
    }

    fn mapRect(frame: Transform2D, r: [4]f32) [4]f32 {
        const m = frame.transformRect(.{ .x = r[0], .y = r[1], .w = r[2], .h = r[3] });
        return .{ m.x, m.y, m.w, m.h };
    }

    const LayerExtras = struct {
        surface_id: u32 = display_list_mod.INVALID_SURFACE_ID,
        content_version: u32 = 0,
        rest_origin: ?[2]f32 = null,
        genie: ?genie_warp.Warp = null,
        margin: f32 = 0,
    };

    /// Map that draws the snapshot so the captured node's own rect (`node_w` x `node_h` at
    /// `node_offset`) covers `dst`, whatever geometry mode it was captured with; what paints
    /// outside the node (an outer shadow) is drawn around `dst`, scaled alike.
    pub fn nodeRectToRect(self: *const Snapshot, node_w: f32, node_h: f32, dst: ComputedRect) Transform2D {
        return rectToRect(node_w, node_h, dst).mul(Transform2D.translation(-self.node_offset.x, -self.node_offset.y));
    }

    /// Map that draws the snapshot so the captured node rect (local `(0, 0, w, h)`) covers `dst`.
    pub fn rectToRect(node_w: f32, node_h: f32, dst: ComputedRect) Transform2D {
        const sx = if (node_w > 0.0001) dst.w / node_w else 0;
        const sy = if (node_h > 0.0001) dst.h / node_h else 0;
        return Transform2D.translation(dst.x, dst.y).mul(Transform2D.scale(sx, sy, 0, 0));
    }

    fn appendWithTransform(
        self: *const Snapshot,
        draw_ctx: DrawContext,
        local: Transform2D,
        opacity: f32,
        use_layer_transform: bool,
        extras: LayerExtras,
    ) !void {

        // Snapshot internal IR = DisplayItem (local coords, pulled by offsetDisplayItem to (0,0)
        // origin). appendTo writes two outlets:
        // (1) display_list side, splice to draw_ctx.display_list
        // (2) lowering_buffer_paint side, translate to paint_table.DisplayItem
        // **both must wrap with begin/end_opacity_layer** to apply origin + scale + opacity.
        //
        // Pitfall: at the end of cx.render(), `main_paint.clearRetainingCapacity()` then
        // appendAllDisplayItemsToRenderList rebuilds the whole paint list from display_list
        // (core.zig:3087-3089). If (1) splices bare commands without the wrapper, the wrapper
        // written to (2) and its origin are discarded and the snapshot draws at local (0,0) instead
        // of its anchor.
        const gpu_draw_shadow = @import("render_engine/gpu_draw_shadow.zig");
        const paint_table_mod = @import("paint_table.zig");
        // Keep all literal snapshot commands in the host's effect scope; an
        // INVALID effect would close that surface midway through its contents.
        const host = draw_ctx.display_header;
        const CONTROL: ItemHeader = .{
            .already_lowered = true,
            // Keep the host identity so retained splice can rebind scope IDs;
            // already_lowered prevents its geometry transform being applied twice.
            .transform_id = if (host) |h| h.transform_id else INVALID_ID,
            .node_id = if (host) |h| h.node_id else INVALID_ID,
            .effect_id = if (host) |h| h.effect_id else INVALID_ID,
            .clip_id = if (host) |h| h.clip_id else INVALID_ID,
        };
        const frame = draw_ctx.content_from_world;

        var begin_item: ?display_list_mod.DisplayItem = null;
        if (use_layer_transform) {
            const draw_transform = frame.mul(local);
            const m = extras.margin;
            const bounds: ComputedRect = .{ .x = self.local_bounds.x - m, .y = self.local_bounds.y - m, .w = self.local_bounds.w + 2 * m, .h = self.local_bounds.h + 2 * m };
            var draw_bounds = draw_transform.transformRect(bounds);
            var genie: genie_warp.Warp = .{};
            if (extras.genie) |g0| {
                // Window coordinates into the content frame (the overlay root: identity).
                var g = g0;
                g.home = mapRect(frame, g.home);
                g.anchor = mapRect(frame, g.anchor);
                genie = g;
                // The genie draws in window coordinates (localized like the content frame); the
                // envelope (damage / cull) covers both the mesh and the affine fallback.
                const gb = genie_warp.localBounds(g, .{ bounds.x, bounds.y, bounds.w, bounds.h });
                const wb = frame.transformRect(.{ .x = gb[0], .y = gb[1], .w = gb[2], .h = gb[3] });
                const x0 = @min(draw_bounds.x, wb.x);
                const y0 = @min(draw_bounds.y, wb.y);
                const x1 = @max(draw_bounds.x + draw_bounds.w, wb.x + wb.w);
                const y1 = @max(draw_bounds.y + draw_bounds.h, wb.y + wb.h);
                draw_bounds = .{ .x = x0, .y = y0, .w = x1 - x0, .h = y1 - y0 };
            }
            begin_item = .{
                .begin_opacity_layer = .{
                    .header = CONTROL,
                    .x = bounds.x,
                    .y = bounds.y,
                    .w = bounds.w,
                    .h = bounds.h,
                    .opacity = opacity,
                    .use_draw_transform = true,
                    .draw_transform = draw_transform,
                    .draw_x = draw_bounds.x,
                    .draw_y = draw_bounds.y,
                    .draw_w = draw_bounds.w,
                    .draw_h = draw_bounds.h,
                    .surface_rest_origin = if (extras.rest_origin) |r| restOrigin(frame, r) else null,
                    .genie = genie,
                    .surface_stable_id = extras.surface_id,
                    .surface_content_version = extras.content_version,
                },
            };
        }

        // (1) display_list side, must also wrap, else render end rebuilds paint list from
        // display_list losing all origin/scale/opacity.
        if (draw_ctx.display_list) |dl| {
            if (begin_item) |begin| try dl.append(begin);
            for (self.commands.commands) |command| {
                var scoped = command;
                scoped.headerPtr().* = CONTROL;
                try dl.append(scoped);
            }
            if (use_layer_transform) {
                try dl.append(.{ .end_opacity_layer = .{ .header = CONTROL } });
            }
        }

        // (2) lowering_buffer_paint side
        if (begin_item) |begin| {
            try draw_ctx.lowering_buffer_paint.?.append(draw_ctx.allocator, gpu_draw_shadow.lowerDisplayItem(begin));
        }
        for (self.commands.commands) |item| {
            var paint_item = gpu_draw_shadow.lowerDisplayItem(item);
            // inline payload (polygon / glass / icon_rep), spill to frame_arena for stable address
            switch (item) {
                .push_clip => |it| {
                    if (it.shape_kind == .polygon) {
                        const dup = try draw_ctx.frame_allocator.create(display_list_mod.ClipPolygon);
                        dup.* = display_list_mod.ClipPolygon.of(it.polygon);
                        paint_item.clip_polygon_ptr = dup;
                    }
                },
                .begin_blur_layer => |it| {
                    const dup = try draw_ctx.frame_allocator.create(@TypeOf(it.glass.*));
                    dup.* = it.glass.*;
                    paint_item.glass_ptr = dup;
                },
                .icon_rep => |it| {
                    const dup = try draw_ctx.frame_allocator.create(@TypeOf(it.rep));
                    dup.* = it.rep;
                    paint_item.icon_rep_ptr = dup;
                },
                else => {},
            }
            _ = paint_table_mod;
            try draw_ctx.lowering_buffer_paint.?.append(draw_ctx.allocator, paint_item);
        }
        if (use_layer_transform) {
            const end_item: display_list_mod.DisplayItem = .{ .end_opacity_layer = .{ .header = CONTROL } };
            try draw_ctx.lowering_buffer_paint.?.append(draw_ctx.allocator, gpu_draw_shadow.lowerDisplayItem(end_item));
        }
    }

    pub fn deinit(self: *Snapshot) void {
        self.commands.deinit();
        self.allocator.destroy(self);
    }
};

fn offsetLayerComposite(layer: anytype, dx: f32, dy: f32) void {
    if (layer.use_draw_transform) {
        layer.draw_transform.tx += dx;
        layer.draw_transform.ty += dy;
    } else {
        layer.x += dx;
        layer.y += dy;
    }
    if (!std.math.isNan(layer.draw_x)) layer.draw_x += dx;
    if (!std.math.isNan(layer.draw_y)) layer.draw_y += dy;
}

fn displayItemBounds(it: DisplayItem) ?ComputedRect {
    return switch (it) {
        .begin_opacity_layer => |v| if (v.use_draw_transform) v.draw_transform.transformRect(ComputedRect.init(0, 0, v.w, v.h)) else ComputedRect.init(v.x, v.y, v.w, v.h),
        .begin_rounded_clip => |v| if (v.use_draw_transform) v.draw_transform.transformRect(ComputedRect.init(0, 0, v.w, v.h)) else ComputedRect.init(v.x, v.y, v.w, v.h),
        .fill_rect => |v| ComputedRect.init(v.x, v.y, v.w, v.h),
        .stroke_rect => |v| ComputedRect.init(v.x, v.y, v.w, v.h),
        .border_side => |v| ComputedRect.init(v.x, v.y, v.w, v.h),
        .border_per_side => |v| ComputedRect.init(v.x, v.y, v.w, v.h),
        .gradient_rect => |v| ComputedRect.init(v.x, v.y, v.w, v.h),
        .shadow_rect => |v| ComputedRect.init(
            v.x - v.blur - @abs(v.offset_x),
            v.y - v.blur - @abs(v.offset_y),
            v.w + (v.blur + @abs(v.offset_x)) * 2,
            v.h + (v.blur + @abs(v.offset_y)) * 2,
        ),
        .outline_rect => |v| ComputedRect.init(v.x - v.width, v.y - v.width, v.w + v.width * 2, v.h + v.width * 2),
        .text_run => |v| ComputedRect.init(v.x, v.y - v.font_size, text_layout.measureTextWidthWithSpans(
            v.content,
            0,
            @intCast(v.content.len),
            v.font_size,
            v.font_weight,
            v.use_italic_font,
            v.use_monospace_font,
            v.spans orelse &.{},
        ), v.font_size * 1.4),
        .image_quad => |v| ComputedRect.init(v.x, v.y, v.w, v.h),
        .icon_rep => |v| ComputedRect.init(v.x, v.y, v.w, v.h),
        .multi_gradient_rect => |v| ComputedRect.init(v.x, v.y, v.w, v.h),
        .noise_rect => |v| ComputedRect.init(v.x, v.y, v.w, v.h),
        .inset_shadow_rect => |v| ComputedRect.init(v.x, v.y, v.w, v.h),
        .shadow_dual_rect => |v| ComputedRect.init(
            v.x - @max(v.shadow1_blur + @abs(v.shadow1_offset_x), v.shadow2_blur + @abs(v.shadow2_offset_x)),
            v.y - @max(v.shadow1_blur + @abs(v.shadow1_offset_y), v.shadow2_blur + @abs(v.shadow2_offset_y)),
            v.w + @max(v.shadow1_blur + @abs(v.shadow1_offset_x), v.shadow2_blur + @abs(v.shadow2_offset_x)) * 2,
            v.h + @max(v.shadow1_blur + @abs(v.shadow1_offset_y), v.shadow2_blur + @abs(v.shadow2_offset_y)) * 2,
        ),
        else => null,
    };
}

fn unionBounds(acc: ?ComputedRect, next: ComputedRect) ComputedRect {
    if (acc) |current| {
        const min_x = @min(current.x, next.x);
        const min_y = @min(current.y, next.y);
        const max_x = @max(current.x + current.w, next.x + next.w);
        const max_y = @max(current.y + current.h, next.y + next.h);
        return ComputedRect.init(min_x, min_y, max_x - min_x, max_y - min_y);
    }
    return next;
}

const SnapshotGeometry = struct {
    offset_origin: Point,
    node_offset: Point = .{ .x = 0, .y = 0 },
    capture_origin: Point,
    local_bounds: ComputedRect,
    local_transform_origin: Point,
};

fn chooseSnapshotGeometry(node: *Node, commands: []const DisplayItem, world_origin: Point, options: Snapshot.CaptureOptions, capture_frame_origin: Point) SnapshotGeometry {
    // The outer commands share the captured subtree's parent content frame.
    // Nested surface content has a separate frame and contributes via its composite bounds.
    var bounds_opt: ?ComputedRect = null;
    var depth: usize = 0;
    for (commands) |it| {
        switch (it) {
            .end_opacity_layer, .end_rounded_clip => {
                depth -|= 1;
                continue;
            },
            else => {},
        }
        if (depth == 0) {
            if (displayItemBounds(it)) |rect| bounds_opt = unionBounds(bounds_opt, rect);
        }
        switch (it) {
            .begin_opacity_layer, .begin_rounded_clip => depth += 1,
            else => {},
        }
    }
    const node_rect = node.rectFromWorldOrFallback();
    const resolved_origin = node.style.transform_origin().resolve(node_rect.w, node_rect.h);
    const bounds = bounds_opt orelse return .{
        .offset_origin = .{ .x = 0, .y = 0 },
        .node_offset = capture_frame_origin,
        .capture_origin = world_origin,
        .local_bounds = ComputedRect.init(0, 0, node_rect.w, node_rect.h),
        .local_transform_origin = resolved_origin,
    };
    if (options.geometry_mode == .node_rect) {
        // Keep descendant padding/offsets relative to the captured node, even
        // when the node has no background command of its own.
        return .{
            .offset_origin = capture_frame_origin,
            .capture_origin = world_origin,
            .local_bounds = ComputedRect.init(0, 0, node_rect.w, node_rect.h),
            .local_transform_origin = resolved_origin,
        };
    }
    return .{
        // Tight command bounds use their own origin; preserve the node's pivot
        // relative to that origin for later scale animation.
        .offset_origin = .{ .x = bounds.x, .y = bounds.y },
        .node_offset = .{ .x = capture_frame_origin.x - bounds.x, .y = capture_frame_origin.y - bounds.y },
        .capture_origin = world_origin,
        .local_bounds = ComputedRect.init(0, 0, bounds.w, bounds.h),
        .local_transform_origin = .{
            .x = resolved_origin.x - (bounds.x - capture_frame_origin.x),
            .y = resolved_origin.y - (bounds.y - capture_frame_origin.y),
        },
    };
}

test "snapshot localization preserves text font and fade and rectangle shape" {
    const header = ItemHeader{ .already_lowered = true, .transform_id = INVALID_ID, .node_id = INVALID_ID };
    const shifted = offsetDisplayItem(.{ .text_run = .{
        .header = header,
        .x = 40,
        .y = 50,
        .content = "fade",
        .color = types.Color.BLACK,
        .font_size = 14,
        .font_family = 17,
        .fade_dx0 = 30,
        .fade_dx1 = 45,
    } }, -20, -10).text_run;
    try std.testing.expectEqual(@as(f32, 20), shifted.x);
    try std.testing.expectEqual(@as(f32, 40), shifted.y);
    try std.testing.expectEqual(@as(u16, 17), shifted.font_family);
    try std.testing.expectEqual(@as(f32, 30), shifted.fade_dx0);
    try std.testing.expectEqual(@as(f32, 45), shifted.fade_dx1);
    const ellipse = offsetDisplayItem(.{ .fill_rect = .{
        .header = header,
        .x = 40,
        .y = 50,
        .w = 30,
        .h = 20,
        .color = types.Color.BLACK,
        .shape = 1,
    } }, -20, -10).fill_rect;
    try std.testing.expectEqual(@as(u8, 1), ellipse.shape);
}

test "Snapshot.rectToRect maps the captured rect onto any destination rect" {
    const m = Snapshot.rectToRect(120, 80, .{ .x = 20, .y = 10, .w = 40, .h = 20 });
    const r = m.transformRect(.{ .x = 0, .y = 0, .w = 120, .h = 80 });
    try std.testing.expectApproxEqAbs(@as(f32, 20), r.x, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 10), r.y, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 40), r.w, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 20), r.h, 0.0001);
    // A degenerate source collapses to a zero map instead of dividing by zero.
    const z = Snapshot.rectToRect(0, 80, .{ .x = 5, .y = 5, .w = 40, .h = 20 });
    try std.testing.expectEqual(@as(f32, 0), z.a);
}
