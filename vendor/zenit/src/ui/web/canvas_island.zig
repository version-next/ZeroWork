//! WebGPU canvas island: a node subtree that the Web DOM host does NOT mirror
//! as DOM, but paints into a <canvas> from zenit's own lowered display list
//! (window space, after transforms) — the same items the native encoder draws.
//!
//! Selection: Cx.lowering.web_lowered + main_paint_nodes (1:1, web builds only).
//! Items whose owner node lies in the island subtree are taken; control tokens
//! (clips/opacity, node id = maxInt) between the first and last island item are
//! taken too — the subtree paints contiguously in painter's order, so ancestor
//! brackets stay outside and island-internal brackets stay balanced.
//!
//! Output: a flat word stream (u32/f32 bit patterns) + string bytes + f32 point
//! pool, consumed by web/runtime/zenit-gpu.mjs. Coordinates stay in window space;
//! JS subtracts the canvas origin.
const std = @import("std");
const core = @import("../core.zig");
const dl = @import("../core/display_list.zig");
const types = @import("../core/types.zig");

const Node = core.Node;
const Color = types.Color;

pub const Op = enum(u32) {
    rect = 1, // x y w h color r4 shape stroke(0=fill)
    border4 = 2, // x y w h color r4 wt wr wb wl
    shadow = 3, // x y w h color r4 blur ox oy spread
    gradient = 4, // x y w h from to dir r4 shape
    text = 5, // x y(baseline) color size weight flags str_off str_len
    icon = 6, // x y w h tint vx vy vw vh str_off str_len stroke fill opacity
    image = 7, // x y w h texture tint radius opacity
    path_fill = 8, // color opacity ox oy pts_off contours rule
    path_stroke = 9, // color opacity ox oy pts_off contours width join
    push_clip = 10, // x y w h r4 shape
    pop_clip = 11,
    begin_opacity = 12, // opacity
    end_opacity = 13,
    arc = 14, // cx cy r width a0 a1 color
    /// k: glass k samples what is drawn before this point (backdrop streams, buildBackdrop).
    mark = 15,
    /// x y w h dir r4 shape n, then n x (color pos): a multi-stop gradient.
    multi_gradient = 16,
};

/// All canvas islands of a frame: the app's explicit island (a board: its whole
/// subtree is painted into the canvas) plus one *paint* island per custom-drawn
/// node (spinners, charts, rulers…): only that node's own paint goes into a canvas
/// under its children, which stay DOM (text, inputs, buttons remain native
/// elements). Islands keep identity (root host id) across frames so unchanged
/// ones are not redrawn.
pub const IslandSet = struct {
    allocator: std.mem.Allocator,
    explicit: ?*Node = null,
    islands: std.ArrayListUnmanaged(*Island) = .empty,
    /// Node.id -> island index (whole subtrees).
    owner: std.AutoHashMapUnmanaged(u32, u16) = .empty,
    scratch: std.ArrayListUnmanaged(*Island) = .empty,
    /// Root host ids added / removed this frame (for the DOM host).
    added: std.ArrayListUnmanaged(u32) = .empty,
    removed: std.ArrayListUnmanaged(u32) = .empty,

    pub fn deinit(self: *IslandSet) void {
        for (self.islands.items) |isl| {
            isl.deinit();
            self.allocator.destroy(isl);
        }
        self.islands.deinit(self.allocator);
        self.owner.deinit(self.allocator);
        self.scratch.deinit(self.allocator);
        self.added.deinit(self.allocator);
        self.removed.deinit(self.allocator);
    }

    fn hasCustomDraw(n: *const Node) bool {
        return n.meta.per_frame.custom_hooks.draw != null;
    }

    fn covered(self: *const IslandSet, n: *const Node) bool {
        var cur: ?*const Node = n;
        while (cur) |c| : (cur = c.parent) {
            if (self.explicit) |e| if (c == e) return true;
        }
        return false;
    }

    /// Pick island roots from the live node set (`live` iterates *const Node),
    /// reconcile with last frame, and rebuild every island's stream.
    pub fn update(self: *IslandSet, cx: *core.Cx, live: anytype) !void {
        self.added.clearRetainingCapacity();
        self.removed.clearRetainingCapacity();
        // 1. roots this frame
        self.scratch.clearRetainingCapacity();
        var roots: std.ArrayListUnmanaged(*Node) = .empty;
        defer roots.deinit(self.allocator);
        if (self.explicit) |e| try roots.append(self.allocator, e);
        var it = live;
        while (it.next()) |entry| {
            const n: *Node = @constCast(entry.value_ptr.node);
            if (n.freeing or n.tag == .anchor or !hasCustomDraw(n)) continue;
            if (self.covered(n)) continue;
            try roots.append(self.allocator, n);
        }
        // 2. reconcile by root host id
        for (roots.items) |r| {
            var found: ?*Island = null;
            for (self.islands.items) |isl| if (isl.root_id == r.host_id) {
                found = isl;
                break;
            };
            const isl = found orelse blk: {
                const fresh = try self.allocator.create(Island);
                fresh.* = .{ .allocator = self.allocator, .root_id = r.host_id };
                try self.added.append(self.allocator, @intCast(r.host_id));
                break :blk fresh;
            };
            isl.root = r;
            try self.scratch.append(self.allocator, isl);
        }
        for (self.islands.items) |isl| {
            const kept = for (self.scratch.items) |k| {
                if (k == isl) break true;
            } else false;
            if (!kept) {
                try self.removed.append(self.allocator, @intCast(isl.root_id));
                isl.deinit();
                self.allocator.destroy(isl);
            }
        }
        std.mem.swap(std.ArrayListUnmanaged(*Island), &self.islands, &self.scratch);
        // 3. ownership + streams (one pass over the lowered list)
        self.owner.clearRetainingCapacity();
        for (self.islands.items, 0..) |isl, i| try self.collect(isl.root.?, @intCast(i), isl.root.? == self.explicit);
        const items = cx.lowering.web_lowered.items;
        const nodes = cx.lowering.main_paint_nodes.items;
        const n = @min(items.len, nodes.len);
        for (self.islands.items) |isl| {
            isl.first = null;
            isl.last = 0;
        }
        for (nodes[0..n], 0..) |id, i| if (self.owner.get(id)) |k| {
            const isl = self.islands.items[k];
            if (isl.first == null) isl.first = i;
            isl.last = i;
        };
        for (self.islands.items, 0..) |isl, k| try isl.build(items[0..n], nodes[0..n], &self.owner, @intCast(k));
    }

    fn collect(self: *IslandSet, n: *Node, k: u16, subtree: bool) !void {
        try self.owner.put(self.allocator, n.id, k);
        if (subtree) for (n.children.items) |child| try self.collect(child, k, true);
    }

    /// A paint island (custom-drawn node): only the root's own paint is in the canvas.
    pub fn isPaintRoot(self: *const IslandSet, n: *const Node) bool {
        if (self.explicit) |e| if (e == n) return false;
        return self.isRoot(n);
    }

    pub fn isRoot(self: *const IslandSet, n: *const Node) bool {
        for (self.islands.items) |isl| if (isl.root == n) return true;
        return false;
    }
};

pub const Island = struct {
    allocator: std.mem.Allocator,
    root: ?*Node = null,
    root_id: u64 = 0,
    first: ?usize = null,
    last: usize = 0,
    words: std.ArrayListUnmanaged(u32) = .empty,
    strings: std.ArrayListUnmanaged(u8) = .empty,
    points: std.ArrayListUnmanaged(f32) = .empty,
    changed: bool = false,
    last_digest: u64 = 0,

    pub fn deinit(self: *Island) void {
        self.words.deinit(self.allocator);
        self.strings.deinit(self.allocator);
        self.points.deinit(self.allocator);
    }

    fn w(self: *Island, x: u32) !void {
        try self.words.append(self.allocator, x);
    }
    fn f(self: *Island, x: f32) !void {
        try self.words.append(self.allocator, @bitCast(x));
    }
    fn c(self: *Island, x: Color) !void {
        try self.w((@as(u32, x.r) << 24) | (@as(u32, x.g) << 16) | (@as(u32, x.b) << 8) | x.a);
    }
    fn r4(self: *Island, r: [4]f32) !void {
        for (r) |x| try self.f(x);
    }
    fn str(self: *Island, s: []const u8) !void {
        try self.w(@intCast(self.strings.items.len));
        try self.w(@intCast(s.len));
        try self.strings.appendSlice(self.allocator, s);
    }

    fn build(self: *Island, items: []const dl.DisplayItem, nodes: []const u32, owner: *const std.AutoHashMapUnmanaged(u32, u16), k: u16) !void {
        self.words.clearRetainingCapacity();
        self.strings.clearRetainingCapacity();
        self.points.clearRetainingCapacity();
        if (self.first) |start| {
            for (items[start .. self.last + 1], nodes[start .. self.last + 1]) |*item, id| {
                if (id != std.math.maxInt(u32)) {
                    const o = owner.get(id) orelse continue;
                    if (o != k) continue;
                }
                try self.emit(item);
            }
        }
        const digest = std.hash.Wyhash.hash(std.hash.Wyhash.hash(0, std.mem.sliceAsBytes(self.words.items)), self.strings.items) ^
            std.hash.Wyhash.hash(7, std.mem.sliceAsBytes(self.points.items));
        if (digest != self.last_digest) {
            self.last_digest = digest;
            self.changed = true;
        }
    }

    /// The glass backdrop (src/ui/web/glass.zig): every item of the frame in
    /// painter's order, with Op.mark k before the k-th glass, so the host can
    /// paint the frame up to each glass before replaying it.
    pub fn buildBackdrop(self: *Island, items: []const dl.DisplayItem) !void {
        self.words.clearRetainingCapacity();
        self.strings.clearRetainingCapacity();
        self.points.clearRetainingCapacity();
        var k: u32 = 0;
        for (items) |*item| {
            if (item.* == .begin_blur_layer) {
                try self.w(@backingInt(Op.mark));
                try self.w(k);
                k += 1;
            }
            try self.emit(item);
        }
    }

    fn emit(self: *Island, item: *const dl.DisplayItem) !void {
        switch (item.*) {
            .fill_rect => |it| {
                try self.w(@backingInt(Op.rect));
                try self.f(it.x);
                try self.f(it.y);
                try self.f(it.w);
                try self.f(it.h);
                try self.c(it.color);
                try self.r4(it.radius);
                try self.w(it.shape);
                try self.f(0);
            },
            inline .stroke_rect, .outline_rect => |it| {
                try self.w(@backingInt(Op.rect));
                try self.f(it.x);
                try self.f(it.y);
                try self.f(it.w);
                try self.f(it.h);
                try self.c(it.color);
                try self.r4(it.radius);
                try self.w(if (@hasField(@TypeOf(it), "shape")) it.shape else 0);
                try self.f(it.width);
            },
            .border_side => |it| {
                // Approximation: a full stroke clipped to the side's clip rect.
                try self.pushClipRect(it.clip_x, it.clip_y, it.clip_w, it.clip_h, it.clip_radii, @backingInt(it.clip_shape_kind));
                try self.w(@backingInt(Op.rect));
                try self.f(it.x);
                try self.f(it.y);
                try self.f(it.w);
                try self.f(it.h);
                try self.c(it.color);
                try self.r4(it.radius);
                try self.w(0);
                try self.f(it.width);
                try self.w(@backingInt(Op.pop_clip));
            },
            .border_per_side => |it| {
                try self.w(@backingInt(Op.border4));
                try self.f(it.x);
                try self.f(it.y);
                try self.f(it.w);
                try self.f(it.h);
                try self.c(it.color);
                try self.r4(it.radius);
                for (it.widths) |x| try self.f(x);
            },
            .shadow_rect => |it| try self.shadow(it.x, it.y, it.w, it.h, it.color, it.radius, it.blur, it.offset_x, it.offset_y, it.spread),
            .shadow_dual_rect => |it| {
                try self.shadow(it.x, it.y, it.w, it.h, it.shadow1_color, it.radius, it.shadow1_blur, it.shadow1_offset_x, it.shadow1_offset_y, 0);
                try self.shadow(it.x, it.y, it.w, it.h, it.shadow2_color, it.radius, it.shadow2_blur, it.shadow2_offset_x, it.shadow2_offset_y, 0);
                try self.fillRect(it.x, it.y, it.w, it.h, it.fill, it.radius);
            },
            .inset_shadow_rect => |it| try self.fillRect(it.x, it.y, it.w, it.h, it.fill, it.radius),
            .noise_rect => |it| try self.fillRect(it.x, it.y, it.w, it.h, it.fill, it.radius),
            .gradient_rect => |it| try self.gradient(it.x, it.y, it.w, it.h, it.from, it.to, @backingInt(it.direction), it.radius, it.shape),
            .multi_gradient_rect => |it| {
                const n: u32 = @min(it.stop_count, it.stop_colors.len);
                if (n < 2) {
                    try self.gradient(it.x, it.y, it.w, it.h, it.stop_colors[0], it.stop_colors[0], @backingInt(it.direction), it.radius, it.shape);
                    return;
                }
                try self.w(@backingInt(Op.multi_gradient));
                try self.f(it.x);
                try self.f(it.y);
                try self.f(it.w);
                try self.f(it.h);
                try self.w(@backingInt(it.direction));
                try self.r4(it.radius);
                try self.w(it.shape);
                try self.w(n);
                for (it.stop_colors[0..n], it.stop_positions[0..n]) |col, pos| {
                    try self.c(col);
                    try self.f(pos);
                }
            },
            .text_run => |it| {
                const s = if (it.blob_byte_end > it.blob_byte_start and it.blob_byte_end <= it.content.len) it.content[it.blob_byte_start..it.blob_byte_end] else it.content;
                if (s.len == 0) return;
                try self.w(@backingInt(Op.text));
                try self.f(it.x);
                try self.f(it.y);
                try self.c(it.color);
                try self.f(it.font_size);
                try self.w(it.font_weight);
                try self.w(@as(u32, @intFromBool(it.use_italic_font)) | (@as(u32, @intFromBool(it.use_monospace_font)) << 1) | (@as(u32, @intFromBool(it.use_symbols_font)) << 2) | (@as(u32, it.font_family) << 16));
                try self.str(s);
            },
            .icon_rep => |it| {
                try self.w(@backingInt(Op.icon));
                try self.f(it.x);
                try self.f(it.y);
                try self.f(it.w);
                try self.f(it.h);
                try self.c(it.tint);
                try self.f(it.rep.view_min_x);
                try self.f(it.rep.view_min_y);
                try self.f(it.rep.view_width);
                try self.f(it.rep.view_height);
                const off: u32 = @intCast(self.strings.items.len);
                var stroke: f32 = 0;
                var fill = false;
                for (it.rep.shapes) |shape| {
                    if (shape.stroke_width > 0) stroke = shape.stroke_width;
                    if (shape.fill) fill = true;
                    for (shape.contours) |ct| {
                        for (ct.points, 0..) |p, i| {
                            var buf: [48]u8 = undefined;
                            try self.strings.appendSlice(self.allocator, std.fmt.bufPrint(&buf, "{c}{d:.2} {d:.2}", .{ @as(u8, if (i == 0) 'M' else 'L'), p.x, p.y }) catch unreachable);
                        }
                        if (ct.closed) try self.strings.append(self.allocator, 'Z');
                    }
                }
                try self.w(off);
                try self.w(@intCast(self.strings.items.len - off));
                try self.f(stroke);
                try self.w(@intFromBool(fill));
                try self.f(it.opacity);
            },
            .image_quad => |it| {
                try self.w(@backingInt(Op.image));
                try self.f(it.x);
                try self.f(it.y);
                try self.f(it.w);
                try self.f(it.h);
                try self.w(it.texture_id);
                try self.c(it.tint);
                try self.f(it.corner_radius);
                try self.f(it.opacity);
            },
            .fill_path => |it| {
                try self.w(@backingInt(Op.path_fill));
                try self.c(it.color);
                try self.f(it.opacity);
                try self.f(it.offset_x);
                try self.f(it.offset_y);
                try self.flatten(it.geometry);
                try self.w(@backingInt(it.geometry.fill_rule));
            },
            .stroke_path => |it| {
                try self.w(@backingInt(Op.path_stroke));
                try self.c(it.color);
                try self.f(it.opacity);
                try self.f(it.offset_x);
                try self.f(it.offset_y);
                try self.flatten(it.geometry);
                try self.f(it.width);
                try self.w(@backingInt(it.line_join));
            },
            .arc => |it| {
                try self.w(@backingInt(Op.arc));
                try self.f(it.cx);
                try self.f(it.cy);
                try self.f(it.outer_radius);
                try self.f(it.stroke_width);
                try self.f(it.start_angle);
                try self.f(it.end_angle);
                try self.c(it.color);
            },
            .push_clip => |it| try self.pushClipRect(it.x, it.y, it.w, it.h, it.radii, @backingInt(it.shape_kind)),
            .begin_rounded_clip => |it| try self.pushClipRect(it.x, it.y, it.w, it.h, it.radii, 1),
            .pop_clip, .end_rounded_clip => try self.w(@backingInt(Op.pop_clip)),
            .begin_opacity_layer => |it| {
                try self.w(@backingInt(Op.begin_opacity));
                try self.f(it.opacity);
            },
            .begin_blur_layer => {
                // Glass: no backdrop blur on the web island yet; keep bracket balance.
                try self.w(@backingInt(Op.begin_opacity));
                try self.f(1);
            },
            .end_opacity_layer, .end_blur_layer => try self.w(@backingInt(Op.end_opacity)),
        }
    }

    fn fillRect(self: *Island, x: f32, y: f32, wd: f32, h: f32, color: Color, radius: [4]f32) !void {
        try self.w(@backingInt(Op.rect));
        try self.f(x);
        try self.f(y);
        try self.f(wd);
        try self.f(h);
        try self.c(color);
        try self.r4(radius);
        try self.w(0);
        try self.f(0);
    }

    fn shadow(self: *Island, x: f32, y: f32, wd: f32, h: f32, color: Color, radius: [4]f32, blur: f32, ox: f32, oy: f32, spread: f32) !void {
        try self.w(@backingInt(Op.shadow));
        try self.f(x);
        try self.f(y);
        try self.f(wd);
        try self.f(h);
        try self.c(color);
        try self.r4(radius);
        try self.f(blur);
        try self.f(ox);
        try self.f(oy);
        try self.f(spread);
    }

    fn gradient(self: *Island, x: f32, y: f32, wd: f32, h: f32, from: Color, to: Color, dir: u32, radius: [4]f32, shape: u8) !void {
        try self.w(@backingInt(Op.gradient));
        try self.f(x);
        try self.f(y);
        try self.f(wd);
        try self.f(h);
        try self.c(from);
        try self.c(to);
        try self.w(dir);
        try self.r4(radius);
        try self.w(shape);
    }

    fn pushClipRect(self: *Island, x: f32, y: f32, wd: f32, h: f32, radii: [4]f32, shape: u32) !void {
        try self.w(@backingInt(Op.push_clip));
        try self.f(x);
        try self.f(y);
        try self.f(wd);
        try self.f(h);
        try self.r4(radii);
        try self.w(shape);
    }

    /// Flatten path commands into the point pool: per contour `[n, x0, y0, …]`.
    /// Emits pts_off and contour count.
    fn flatten(self: *Island, g: *const types.PathGeometry) !void {
        const off: u32 = @intCast(self.points.items.len);
        var contours: u32 = 0;
        var count_at: ?usize = null;
        var cur: [2]f32 = .{ 0, 0 };
        var start: [2]f32 = .{ 0, 0 };
        for (g.commands) |cmd| {
            switch (cmd) {
                .move_to => |p| {
                    try self.points.append(self.allocator, 0);
                    count_at = self.points.items.len - 1;
                    contours += 1;
                    cur = .{ p.x, p.y };
                    start = cur;
                    try self.pt(count_at, cur);
                },
                .line_to => |p| {
                    if (count_at == null) {
                        try self.points.append(self.allocator, 0);
                        count_at = self.points.items.len - 1;
                        contours += 1;
                        try self.pt(count_at, cur);
                    }
                    cur = .{ p.x, p.y };
                    try self.pt(count_at, cur);
                },
                .quad_to => |q| {
                    const steps = 12;
                    for (1..steps + 1) |i| {
                        const t = @as(f32, @floatFromInt(i)) / steps;
                        const u = 1 - t;
                        try self.pt(count_at, .{ u * u * cur[0] + 2 * u * t * q.ctrl.x + t * t * q.end.x, u * u * cur[1] + 2 * u * t * q.ctrl.y + t * t * q.end.y });
                    }
                    cur = .{ q.end.x, q.end.y };
                },
                .cubic_to => |q| {
                    const steps = 16;
                    for (1..steps + 1) |i| {
                        const t = @as(f32, @floatFromInt(i)) / steps;
                        const u = 1 - t;
                        const a = u * u * u;
                        const b = 3 * u * u * t;
                        const cc = 3 * u * t * t;
                        const d = t * t * t;
                        try self.pt(count_at, .{
                            a * cur[0] + b * q.ctrl1.x + cc * q.ctrl2.x + d * q.end.x,
                            a * cur[1] + b * q.ctrl1.y + cc * q.ctrl2.y + d * q.end.y,
                        });
                    }
                    cur = .{ q.end.x, q.end.y };
                },
                .close => {
                    try self.pt(count_at, start);
                    cur = start;
                    count_at = null;
                },
            }
        }
        try self.w(off);
        try self.w(contours);
    }

    fn pt(self: *Island, count_at: ?usize, p: [2]f32) !void {
        const at = count_at orelse return;
        try self.points.appendSlice(self.allocator, &p);
        self.points.items[at] += 1;
    }
};
