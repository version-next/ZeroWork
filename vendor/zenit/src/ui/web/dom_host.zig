//! Web DOM host (M0, "DOM 还原版"): mirrors the live zenit node forest into the
//! browser DOM through a flat command buffer.
//!
//! - Structure comes from the renderer host seam (node_tree.Host): create/place/
//!   retained_remove/destroy are encoded in arrival order, so the JS replay sees
//!   the same forest the native renderer sees.
//! - Geometry: layout domains (WEB_HOST_DESIGN §3). By default every node is laid
//!   out by the browser: its zenit Style is mapped to CSS flex/grid with the same
//!   mapping the LC3 conformance gate validates in three engines
//!   (tools/layout_css_conformance/conformance.mjs `styleCSS`). Only domain
//!   boundaries take the wasm-computed box: roots/overlays, absolute and sticky
//!   nodes (out of flow, placed at zenit's rect), canvas-island roots and
//!   content-sized non-text leaves (pinned in flow at zenit's size,
//!   `contain: layout size`). `css_layout = false` restores the M0 all-absolute
//!   mirror (diagnostics / A-B).
//! - Paint: resolved box/text/icon state is diffed per node against the last
//!   value sent (a small fixed snapshot, no allocation per frame once warm).
//! - Text is browser text (selection/copy/a11y/IME stay native); zenit measured it
//!   through the same font string (see web runtime measure hook).
//!
//! The callback only records; it never touches nodes (host contract).
const std = @import("std");
const core = @import("../core.zig");
const node_tree = @import("../core/node_tree.zig");
const types = @import("../core/types.zig");
const node_lifecycle = @import("../core/node_lifecycle.zig");
const icon_ir = @import("icon_ir");

const Node = core.Node;
const Color = types.Color;

pub const Op = enum(u32) {
    create = 1, // id, tag
    place = 2, // id, parent, before (0 = append)
    remove = 3, // id (retained: unlink only)
    destroy = 4, // id
    text = 7, // id, str_off, str_len: text content (its style is atomic classes)
    icon = 8, // id, icon_id, rep size: <svg class=z-icon><use href=#zi-ID-SIZE/></svg>
    /// icon_id, rep size, view x/y/w/h, path_off, path_len, stroke_width, fill: <symbol>
    icon_def = 22,
    root = 9, // id
    cursor = 10, // css cursor index
    island = 11, // id, on(1)/off(0): this element hosts a WebGPU canvas; descendants are not mirrored
    image = 12, // id, texture_id, tint
    a11y = 14, // id, str_off, str_len: "role\nlabel\ndescription\nvalue\nflags" (ARIA)
    /// id, cls_off, cls_len, inline_off, inline_len: the node's atomic class list
    /// (space separated) and its per-frame inline declarations ("prop:value;").
    style = 16,
    /// off, len: one atomic rule ".<class>{prop:value}" first seen at runtime.
    rule = 17,
    /// id, str_off, str_len: zenit test_id -> data-testid (e2e / DevTools lookup).
    test_id = 18,
    /// id, str_off, str_len: overflow_fade overlay as CSS background-image layers
    /// ("" = none). Painted above the node's children like the native fade rects.
    fade = 19,
    /// id, tag: the element's semantic HTML tag (SemanticTag); the host swaps the element.
    tag = 20,
    /// id, str_off, str_len: native form control for an editable text node
    /// ("" = none). Fields separated by 0x1f, see syncField.
    field = 21,
    /// id, axes (bit0 x, bit1 y; 0 = not a native scroller), x, y (f32 bits), content id:
    /// the element scrolls natively (overflow:auto); scrollLeft/scrollTop follow zenit's
    /// offset. Its other children (scrollbar thumbs, tracks) move to a non-scrolling rail.
    scroll = 23,
    /// id, on(1)/off(0): the node carries glass material (StyleExt.glass). The host
    /// marks the element (.z-glass); the glass paint island draws into a canvas under
    /// its children (docs/WEB_GLASS_DESIGN.md §5), the CSS backdrop-filter tier
    /// stays as the fallback until it does.
    glass = 24,
    /// id, w, h, r_tl, r_tr, r_br, r_bl, cap, edge, fade_start, fade_width (f32 bits; w = 0:
    /// none): lens warp of the subtree (StyleExt.content_warp, native composite.metal's
    /// blend_fragment_main). The host displaces the element's rendering with an SVG
    /// feDisplacementMap computed from the same contour formula.
    warp = 25,
};

pub const BoxFlags = struct {
    pub const clip: u32 = 1;
    pub const hidden: u32 = 2;
    pub const anchor: u32 = 4;
    /// Border is painted over the content (Border.overlay): no layout space.
    pub const border_overlay: u32 = 8;
};

pub const TextFlags = struct {
    pub const italic: u32 = 1;
    pub const mono: u32 = 2;
    pub const ellipsis: u32 = 4;
    pub const strike: u32 = 8;
    // wrap mode in bits 8..11, align in bits 12..13
};

const Mirror = struct {
    node: *const Node,
    style_hash: u64 = 0,
    text_hash: u64 = 0,
    /// A component wrote this node's rect outside layout (setLayoutRect hook):
    /// a layout-domain boundary at its zenit box from then on.
    component_placed: bool = false,
    /// Opacity changed in the last frames (animation): keep it inline.
    last_opacity: f32 = 1,
    opacity_hot: u8 = 0,
    icon_hash: u64 = 0,
    image_hash: u64 = 0,
    a11y_hash: u64 = 0,
    test_id_hash: u64 = 0,
    fade_hash: u64 = 0,
    tag: SemanticTag = .div,
    field_hash: u64 = 0,
    /// Glass presence last sent (Op.glass).
    glass: bool = false,
    /// Content warp last sent (Op.warp), hashed.
    warp_hash: u64 = 0,
    /// Native scroller state last sent (Op.scroll).
    scroll_axes: u32 = 0,
    scroll_x: f32 = 0,
    scroll_y: f32 = 0,
};

/// ScrollArea container the browser scrolls natively (core.host_scroll_query_hook).
fn hostScroll(n: *const Node) ?core.HostScroll {
    const q = core.host_scroll_query_hook orelse return null;
    return q(n);
}

/// Semantic HTML5 element for a node (WEB_HOST_DESIGN: native elements first, ARIA as
/// a supplement). Index = JS TAG_NAMES in zenit-dom.mjs.
pub const SemanticTag = enum(u8) { div, button, a, h1, h2, h3, h4, h5, h6, ul, li, nav, main, dialog, p, section, article, form, header, footer, hr };

pub const DomHost = struct {
    allocator: std.mem.Allocator,
    host: node_tree.Host,
    live: std.AutoHashMapUnmanaged(u32, Mirror) = .empty,
    cmds: std.ArrayListUnmanaged(u32) = .empty,
    strings: std.ArrayListUnmanaged(u8) = .empty,
    root_id: u32 = 0,
    oom: bool = false,
    /// Layout domains (browser CSS layout inside, wasm boxes at boundaries).
    /// false = M0 mirror: every node absolutely positioned at its zenit rect.
    css_layout: bool = true,
    /// Host ids with a pointer/scroll hit proxy this frame (-> pointer-events:auto;
    /// everything else is transparent to the browser's hit test).
    hittable: std.AutoHashMapUnmanaged(u32, void) = .empty,
    /// Atomic classes whose rule the browser already has: the build-time
    /// zenit-atoms.css set plus rules inserted at runtime (owned keys).
    defined: std.StringHashMapUnmanaged(void) = .empty,
    /// Icon symbols already defined in the document (icon_id << 32 | rep size).
    icon_defs: std.AutoHashMapUnmanaged(u64, void) = .empty,
    /// The Cx being flushed (focus state for native fields).
    cx: ?*core.Cx = null,
    /// Some node's volatile value settled: resync styles next flush.
    force_resync: bool = false,
    /// Canvas islands (set by the runtime each frame before flush).
    islands: ?*const @import("canvas_island.zig").IslandSet = null,

    pub fn init(self: *DomHost, allocator: std.mem.Allocator) void {
        self.* = .{ .allocator = allocator, .host = .{ .context = self, .patch = onPatch } };
        self.host.attach();
        self.defineStaticAtoms();
        active = self;
        node_lifecycle.component_rect_hook = onComponentRect;
    }

    var active: ?*DomHost = null;
    fn onComponentRect(n: *Node) void {
        const self = active orelse return;
        const id = std.math.cast(u32, n.host_id) orelse return;
        if (self.live.getPtr(id)) |m| if (!m.component_placed) {
            m.component_placed = true;
            m.style_hash = 0;
        };
    }

    pub fn deinit(self: *DomHost) void {
        if (active == self) {
            active = null;
            node_lifecycle.component_rect_hook = null;
        }
        self.host.detach();
        self.hittable.deinit(self.allocator);
        self.icon_defs.deinit(self.allocator);
        var dit = self.defined.keyIterator();
        while (dit.next()) |k| self.allocator.free(k.*);
        self.defined.deinit(self.allocator);
        self.live.deinit(self.allocator);
        self.cmds.deinit(self.allocator);
        self.strings.deinit(self.allocator);
    }

    pub fn setCssLayout(self: *DomHost, on: bool) void {
        if (self.css_layout == on) return;
        self.css_layout = on;
        var it = self.live.valueIterator();
        while (it.next()) |m| m.style_hash = 0;
    }

    /// JS consumed the previous batch.
    pub fn reset(self: *DomHost) void {
        self.cmds.clearRetainingCapacity();
        self.strings.clearRetainingCapacity();
    }

    fn id32(id: node_tree.HostId) u32 {
        return std.math.cast(u32, id) orelse @panic("web host: identity space exhausted");
    }

    fn put(self: *DomHost, words: []const u32) void {
        self.cmds.appendSlice(self.allocator, words) catch {
            self.oom = true;
        };
    }

    fn onPatch(ctx: *anyopaque, patch: node_tree.HostPatch) void {
        const self: *DomHost = @ptrCast(@alignCast(ctx));
        switch (patch) {
            .create => |c| {
                const id = id32(c.id);
                self.live.put(self.allocator, id, .{ .node = c.node }) catch {
                    self.oom = true;
                    return;
                };
                self.put(&.{ @backingInt(Op.create), id, @backingInt(c.tag) });
            },
            .place => |p| self.put(&.{ @backingInt(Op.place), id32(p.id), id32(p.parent), if (p.before) |b| id32(b) else 0 }),
            .retained_remove => |id| self.put(&.{ @backingInt(Op.remove), id32(id) }),
            .destroy => |id| {
                _ = self.live.remove(id32(id));
                self.put(&.{ @backingInt(Op.destroy), id32(id) });
            },
            // Final-state diff happens in flush; every live node is compared there.
            .dirty => {},
        }
    }

    fn f(x: f32) u32 {
        return @bitCast(x);
    }
    fn col(c: Color) u32 {
        return (@as(u32, c.r) << 24) | (@as(u32, c.g) << 16) | (@as(u32, c.b) << 8) | c.a;
    }

    /// Diff every live node against its mirror and append updates. Runs after
    /// layout + render on the UI thread, when the tree is quiescent.
    pub fn flush(self: *DomHost, cx: *core.Cx) void {
        self.cx = cx;
        if (cx.root) |r| {
            const rid = id32(r.host_id);
            if (rid != self.root_id) {
                self.root_id = rid;
                self.put(&.{ @backingInt(Op.root), rid });
            }
        }
        if (self.css_layout) {
            @import("../core/cx_render.zig").ensureHitTestSceneFresh(cx);
            self.hittable.clearRetainingCapacity();
            for (cx.interaction_index.proxies.items) |proxy| {
                if (!@TypeOf(cx.interaction_index).proxyAnswersInput(proxy)) continue;
                const n = cx.node_registry.resolve(proxy.handle, null) orelse continue;
                const hid = std.math.cast(u32, n.host_id) orelse continue;
                self.hittable.put(self.allocator, hid, {}) catch {
                    self.oom = true;
                };
            }
        }
        if (self.islands) |set| {
            for (set.removed.items) |rid| if (self.live.contains(rid)) self.put(&.{ @backingInt(Op.island), rid, 0 });
            // 1 = explicit island (subtree in the canvas), 2 = paint island (children stay DOM).
            for (set.added.items) |rid| {
                const explicit = if (set.explicit) |e| (std.math.cast(u32, e.host_id) orelse 0) == rid else false;
                self.put(&.{ @backingInt(Op.island), rid, if (explicit) 1 else 2 });
            }
        }
        var it = self.live.iterator();
        while (it.next()) |entry| {
            if (self.islands) |set| if (set.owner.contains(entry.value_ptr.node.id) and !set.isPaintRoot(entry.value_ptr.node)) {
                // Explicit island: the root keeps its box geometry (canvas host); its own
                // paint and every descendant are drawn by the WebGPU island. Paint-island
                // roots sync like any node (writeDecls leaves their own paint to the canvas).
                if (set.isRoot(entry.value_ptr.node)) self.syncStyle(entry.key_ptr.*, entry.value_ptr);
                continue;
            };
            self.syncNode(entry.key_ptr.*, entry.value_ptr);
        }
    }

    fn syncNode(self: *DomHost, id: u32, m: *Mirror) void {
        const n = m.node;
        if (n.freeing) return;
        // Control-flow anchors never render (reset.css: .z-anchor { display:none }).
        if (n.tag == .anchor) return;
        self.syncTag(id, m, n);
        self.syncStyle(id, m);
        self.syncScroll(id, m, n);
        self.syncWarp(id, m, n);
        if (n.tag == .text or n.getText() != null) self.syncText(id, m, n);
        if (n.getIcon()) |icon| self.syncIcon(id, m, n, icon);
        if (n.tag == .image) if (n.getImage()) |img| self.syncImage(id, m, n, img);
        self.syncA11y(id, m, n);
        self.syncTestId(id, m, n);
        self.syncFade(id, m, n);
        self.syncField(id, m, n);
    }

    fn syncWarp(self: *DomHost, id: u32, m: *Mirror, n: *const Node) void {
        var words: [12]u32 = @splat(0);
        words[0] = @backingInt(Op.warp);
        words[1] = id;
        if (n.style.contentWarp()) |cw| if (cw.cap != 0 or cw.edge != 0) {
            const r = n.rectFromWorldOrFallback();
            const e = n.style.getExt();
            const radius: [4]f32 = if (e.corner_radius) |cr| cr.resolve4() else @splat(n.style.border.radius);
            const vals = [10]f32{ r.w, r.h, radius[0], radius[1], radius[2], radius[3], cw.cap, cw.edge, cw.fade_start, cw.fade_width };
            for (vals, 0..) |v, i| words[2 + i] = @bitCast(v);
        };
        const h = std.hash.Wyhash.hash(25, std.mem.sliceAsBytes(words[2..])) | 1;
        const off = words[2] == 0;
        if (off and m.warp_hash == 0) return;
        if (h == m.warp_hash) return;
        m.warp_hash = if (off) 0 else h;
        self.put(&words);
    }

    /// Native scrolling (WEB_HOST_DESIGN: the platform scrolls): a ScrollArea container is
    /// overflow:auto; the browser's scroll comes back through zw_scroll_set, and zenit's
    /// own offset changes (scrollIntoView, keyboard, restore) are pushed as scrollLeft/Top.
    fn syncScroll(self: *DomHost, id: u32, m: *Mirror, n: *const Node) void {
        const hs = hostScroll(n);
        const axes: u32 = if (hs) |h| @as(u32, @intFromBool(h.axis_x)) | @as(u32, @intFromBool(h.axis_y)) << 1 else 0;
        const x: f32 = if (hs) |h| h.x else 0;
        const y: f32 = if (hs) |h| h.y else 0;
        const content: u32 = if (hs) |h| std.math.cast(u32, h.content.host_id) orelse 0 else 0;
        if (axes == m.scroll_axes and @abs(x - m.scroll_x) < 0.75 and @abs(y - m.scroll_y) < 0.75) return;
        m.scroll_axes = axes;
        m.scroll_x = x;
        m.scroll_y = y;
        self.put(&.{ @backingInt(Op.scroll), id, axes, @bitCast(x), @bitCast(y), content });
    }

    /// The node whose text a field shows (Input's display node, a Textarea line):
    /// first text-bearing descendant.
    fn displayText(n: *const Node) ?*const Node {
        for (n.children.items) |c| {
            if (c.getText() != null) return c;
            if (displayText(c)) |d| return d;
        }
        return null;
    }

    /// Editable text (zenit Input / Textarea with a11y.editable_text) is a native
    /// <input>/<textarea> (WEB_HOST_DESIGN §3 "输入框用原生控件"): the browser owns caret,
    /// selection, IME, spellcheck, autofill and context menu; edits come back through
    /// editable_text.set_value/set_selection (runtime zw_field_*). zenit's own text,
    /// caret and selection nodes stay in the tree (layout) but are not painted.
    /// Wire: kind(0 input,1 textarea) | value | placeholder | sel_start | sel_end |
    /// flags(d disabled, r readonly, f focused) | font-size | weight | family var |
    /// colour | placeholder colour | padding t r b l | line-height
    fn syncField(self: *DomHost, id: u32, m: *Mirror, n: *const Node) void {
        var buf: [8192]u8 = undefined;
        var w: std.Io.Writer = .fixed(&buf);
        self.writeField(&w, n) catch {
            w = .fixed(&buf);
        };
        const s = w.buffered();
        const h = std.hash.Wyhash.hash(21, s) | 1;
        if (h == m.field_hash) return;
        m.field_hash = h;
        const off: u32 = @intCast(self.strings.items.len);
        self.strings.appendSlice(self.allocator, s) catch {
            self.oom = true;
            return;
        };
        self.put(&.{ @backingInt(Op.field), id, off, @intCast(s.len) });
    }

    fn writeField(self: *DomHost, w: *std.Io.Writer, n: *const Node) !void {
        const a = n.behavior.interaction.a11y orelse return;
        switch (a.role) {
            .textbox, .searchbox, .textarea, .combobox => {},
            else => return,
        }
        const et = a.editable_text orelse return;
        const value = a.value_text orelse "";
        const disp = displayText(n);
        const tp = if (disp) |d| d.resolveTextProps() else null;
        // A control whose text wraps is multi-line on the web even if a11y says single
        // line (an <input> never wraps).
        const wraps = if (tp) |t| (t.wrap != .none and t.wrap != .newline_only) or t.max_lines > 1 else false;
        const multiline = a.multiline or a.role == .textarea or wraps;
        // Geometry: the field covers only the edit area (the child of the control that
        // holds the text) so prefix/suffix adornments stay; its padding puts the text
        // where zenit's display node puts it.
        const area: *const Node = blk: {
            var cur: ?*const Node = disp;
            while (cur) |c| : (cur = c.parent) if (c.parent == n) break :blk c;
            break :blk n;
        };
        // A single-line field takes the display text's place inside its clipping surface
        // (the node that owns overflow_fade), so it sits in zenit's own structure: shell ->
        // content slot -> surface -> <input>, under the surface's fade bands. A multi-line
        // field still covers the edit area from the control's root.
        const host: ?*const Node = if (!multiline) (if (disp) |d| d.parent else null) else null;
        const r = n.globalRect();
        const ar = if (host) |h| h.globalRect() else area.globalRect();
        const nb = if (n.style.border.overlay) [4]f32{ 0, 0, 0, 0 } else n.style.border.resolvedWidths();
        var pl: f32 = 0;
        var pt: f32 = 0;
        var pr: f32 = 0;
        if (disp) |d| {
            const dr = d.globalRect();
            // zenit scrolls a single-line text by shrinking its left padding (padding -
            // scroll_x); the field's padding is the rest position, the browser scrolls.
            pl = dr.x - ar.x + @max(0, d.style.padding.left + et.scroll_x);
            pt = dr.y - ar.y + @max(0, d.style.padding.top);
            // The text's right edge as zenit lays it out (scrollbar gutter, trailing
            // padding): the browser wraps within the same width.
            pr = (ar.x + ar.w) - (dr.x + dr.w) + @max(0, d.style.padding.right);
            // A multi-line control scrolls its rows inside a scroller (Textarea's list): a
            // row's y moves with the scroll (and virtual rows are recycled), so the top inset
            // is the scroller's padding edge. Rows keep their x and wrap width (scrollbar
            // gutter included), so left/right still come from the row.
            if (multiline) if (core.host_scroll_query_hook) |q| {
                var cur: ?*const Node = d.parent;
                while (cur) |c| : (cur = c.parent) {
                    if (c == n) break;
                    if (q(c) == null) continue;
                    pt = c.globalRect().y - ar.y + c.style.padding.top;
                    break;
                }
            };
        }
        const area_id: u32 = if (area == n) 0 else std.math.cast(u32, area.host_id) orelse 0;
        const focused = if (self.cx) |cx| cx.focus_manager.getFocused() == n or (if (cx.focus_manager.getFocused()) |fo| fo.parent == n else false) else false;
        try w.print("{d}\x1f{s}\x1f{s}\x1f{d}\x1f{d}\x1f", .{ @intFromBool(multiline), value, a.placeholder orelse "", et.selection_start, et.selection_end });
        if (a.disabled) try w.writeByte('d');
        if (a.readonly) try w.writeByte('r');
        if (focused) try w.writeByte('f');
        if (tp) |t| {
            const empty = value.len == 0;
            const ink = if (empty) (if (self.cx) |cx| cx.tokens.tokens.color.fg_primary else t.color) else t.color;
            try w.print("\x1f{d}\x1f{d}\x1fvar(--zf{s}-{d})\x1f", .{ t.font_size, t.font_weight, if (t.use_monospace_font) "m" else "", t.font_family });
            try color(w, ink);
            try w.writeByte(0x1f);
            try color(w, if (empty) t.color else (if (self.cx) |cx| cx.tokens.tokens.color.fg_secondary else t.color));
            try w.print("\x1f{d}\x1f{d}\x1f{d}\x1f{d}\x1f{d}", .{ if (multiline) pt else 0, if (multiline) pr else pl, if (multiline) pt else 0, pl, t.font_size * t.line_height });
            if (host) |h| {
                try w.print("\x1f{d}\x1f0\x1f0\x1f{d}\x1f{d}", .{ area_id, ar.w, ar.h });
                try w.print("\x1f{d}", .{std.math.cast(u32, h.host_id) orelse 0});
            } else {
                try w.print("\x1f{d}\x1f{d}\x1f{d}\x1f{d}\x1f{d}", .{ area_id, ar.x - r.x - nb[3], ar.y - r.y - nb[0], ar.w, ar.h });
                // zenit's own scroll of a multi-line control (its scrollbar thumb dragged):
                // the field follows when it differs from what the browser reported.
                try w.print("\x1f0\x1f{d}", .{@round(et.scroll_y)});
            }
        }
    }

    /// StyleExt.overflow_fade: gradient bands over overflowing edges, exactly the native
    /// conditions (render_engine appendNodeOverflowFade: clipping node, content extent
    /// beyond the padding edge): solid colour over `solid` px, then -> transparent over `size` px.
    fn syncFade(self: *DomHost, id: u32, m: *Mirror, n: *const Node) void {
        var buf: [1024]u8 = undefined;
        var w: std.Io.Writer = .fixed(&buf);
        const s = &n.style;
        if (s.overflow_fade()) |fade| if (s.overflow_hidden or s.overflow != .visible) {
            const extent = @import("../core/render_engine/text_render.zig").computeContentExtent(@constCast(n));
            const r = n.rectFromWorldOrFallback();
            const pad = s.contentInsets();
            const solid = fade.color orelse n.getBackground();
            const Edge = struct { on: bool, dir: []const u8, solid: bool };
            const se = fade.solid_edges;
            const eps: f32 = 0.5; // sub-pixel overflow is invisible (as render_engine)
            const edges = [_]Edge{
                .{ .on = fade.edges.top and extent.min_y < pad.top - eps, .dir = "to bottom", .solid = se.top },
                .{ .on = fade.edges.bottom and extent.max_y > r.h - pad.bottom + eps, .dir = "to top", .solid = se.bottom },
                .{ .on = fade.edges.left and extent.min_x < pad.left - eps, .dir = "to right", .solid = se.left },
                .{ .on = fade.edges.right and extent.max_x > r.w - pad.right + eps, .dir = "to left", .solid = se.right },
            };
            var first = true;
            for (edges) |e| if (e.on) {
                if (!first) w.writeAll(",") catch {};
                first = false;
                w.print("linear-gradient({s},", .{e.dir}) catch {};
                // Solid band (fade.solid) at the clip edge, then the gradient over fade.size.
                color(&w, solid) catch {};
                w.print(" 0px,", .{}) catch {};
                color(&w, solid) catch {};
                const band: f32 = if (e.solid) fade.solid else 0;
                w.print(" {d}px,transparent {d}px)", .{ band, band + fade.size }) catch {};
            };
        };
        const css = w.buffered();
        const h = std.hash.Wyhash.hash(19, css) | 1;
        if (h == m.fade_hash) return;
        m.fade_hash = h;
        const off: u32 = @intCast(self.strings.items.len);
        self.strings.appendSlice(self.allocator, css) catch {
            self.oom = true;
            return;
        };
        self.put(&.{ @backingInt(Op.fade), id, off, @intCast(css.len) });
    }

    fn roleOf(n: *const Node) types.A11yRole {
        return if (n.behavior.interaction.a11y) |p| p.role else .none;
    }

    /// Interactive content may not nest inside <button>/<a> (HTML content model).
    fn insideInteractive(n: *const Node) bool {
        var cur = n.parent;
        while (cur) |p| : (cur = p.parent) {
            switch (semanticTag(p)) {
                .button, .a => return true,
                else => {},
            }
        }
        return false;
    }

    fn semanticTag(n: *const Node) SemanticTag {
        const p = n.behavior.interaction.a11y orelse return .div;
        const leaf = n.children.items.len == 0;
        return switch (p.role) {
            .button => if (insideInteractive(n)) .div else .button,
            .link => if (insideInteractive(n)) .div else .a,
            .heading => switch (if (p.level == 0) 2 else @min(p.level, 6)) {
                1 => .h1,
                2 => .h2,
                3 => .h3,
                4 => .h4,
                5 => .h5,
                else => .h6,
            },
            .list => .ul,
            .listitem => if (n.parent != null and semanticTag(n.parent.?) == .ul) .li else .div,
            .navigation => .nav,
            .main => .main,
            .dialog, .alertdialog => .dialog,
            .paragraph => .p,
            .section, .region => .section,
            .article => .article,
            .form => .form,
            .banner => .header,
            .contentinfo => .footer,
            .separator => if (leaf) .hr else .div,
            else => .div,
        };
    }

    fn syncTag(self: *DomHost, id: u32, m: *Mirror, n: *const Node) void {
        // Canvas-island roots keep their <div> host (the canvas lives inside).
        if (self.islands) |set| if (set.isRoot(n)) return;
        const t = semanticTag(n);
        if (t == m.tag) return;
        m.tag = t;
        self.put(&.{ @backingInt(Op.tag), id, @intFromEnum(t) });
    }

    fn syncTestId(self: *DomHost, id: u32, m: *Mirror, n: *const Node) void {
        const tid = n.meta.ownership.meta.test_id orelse "";
        const h = std.hash.Wyhash.hash(18, tid) | 1;
        if (h == m.test_id_hash) return;
        m.test_id_hash = h;
        const off: u32 = @intCast(self.strings.items.len);
        self.strings.appendSlice(self.allocator, tid) catch {
            self.oom = true;
            return;
        };
        self.put(&.{ @backingInt(Op.test_id), id, off, @intCast(tid.len) });
    }

    fn ariaRole(r: types.A11yRole) []const u8 {
        return switch (r) {
            .none => "",
            .switch_role => "switch",
            .img => "img",
            inline else => |tag| @tagName(tag),
        };
    }

    /// zenit semantics -> ARIA (role, name, states) so screen readers see the
    /// same tree the native a11y bridge exposes.
    fn syncA11y(self: *DomHost, id: u32, m: *Mirror, n: *const Node) void {
        const p = n.behavior.interaction.a11y orelse {
            if (m.a11y_hash != 0) {
                m.a11y_hash = 0;
                self.putA11y(id, "\n\n\n\n");
            }
            return;
        };
        var buf: [512]u8 = undefined;
        var flags: [16]u8 = undefined;
        var fl: usize = 0;
        const F = struct {
            fn add(dst: []u8, len: *usize, c: u8) void {
                dst[len.*] = c;
                len.* += 1;
            }
        };
        if (p.disabled) F.add(&flags, &fl, 'd');
        if (p.hidden) F.add(&flags, &fl, 'h');
        if (p.selected) F.add(&flags, &fl, 's');
        if (p.pressed) F.add(&flags, &fl, 'p');
        if (p.required) F.add(&flags, &fl, 'r');
        if (p.invalid) F.add(&flags, &fl, 'i');
        if (p.modal) F.add(&flags, &fl, 'm');
        if (p.checked) |c| F.add(&flags, &fl, if (c) 'C' else 'c');
        if (p.expanded) |e| F.add(&flags, &fl, if (e) 'E' else 'e');
        const label: []const u8 = p.label orelse "";
        const desc: []const u8 = p.description orelse "";
        const value: []const u8 = p.value_text orelse "";
        const text = std.fmt.bufPrint(&buf, "{s}\n{s}\n{s}\n{s}\n{s}", .{
            ariaRole(p.role),
            label[0..@min(label.len, 200)],
            desc[0..@min(desc.len, 120)],
            value[0..@min(value.len, 120)],
            flags[0..fl],
        }) catch return;
        const h = @import("trace").work_counters.hashText(11, text) | 1;
        if (h == m.a11y_hash) return;
        m.a11y_hash = h;
        self.putA11y(id, text);
    }

    fn putA11y(self: *DomHost, id: u32, text: []const u8) void {
        const off: u32 = @intCast(self.strings.items.len);
        self.strings.appendSlice(self.allocator, text) catch {
            self.oom = true;
            return;
        };
        self.put(&.{ @backingInt(Op.a11y), id, off, @intCast(text.len) });
    }

    fn syncImage(self: *DomHost, id: u32, m: *Mirror, n: *const Node, img: types.ImageProps) void {
        const tint = img.paintTint(if (img.tint_current_color) n.resolveTextColor() else null);
        const words = [_]u32{ @backingInt(Op.image), id, img.texture_id, col(tint) };
        const h = std.hash.Wyhash.hash(3, std.mem.sliceAsBytes(words[2..]));
        if (h == m.image_hash) return;
        m.image_hash = h;
        self.put(&words);
    }

    const LayoutMode = enum {
        /// In flow; CSS lays the node out from its mapped Style.
        flow,
        /// In flow at zenit's size (domain boundary): canvas islands, content-sized
        /// leaves whose intrinsic size the browser cannot know (icons, images).
        pinned,
        /// Out of flow at zenit's rect: roots, overlays, absolute/sticky nodes.
        abs,
    };

    fn layoutMode(self: *const DomHost, n: *const Node) LayoutMode {
        if (!self.css_layout) return .abs;
        const p = n.parent orelse return .abs;
        _ = p;
        if (n.style.position == .absolute or n.style.position == .sticky) return .abs;
        if (self.live.get(std.math.cast(u32, n.host_id) orelse 0)) |m| if (m.component_placed) return .abs;
        if (self.islands) |set| if (set.isRoot(n)) return .pinned;
        const content_sized = n.style.width == .fit or n.style.height == .fit;
        if (n.tag != .text and n.getText() == null and n.children.items.len == 0 and content_sized) return .pinned;
        return .flow;
    }

    /// zenit rect relative to the parent's CSS padding box (layout rects are local
    /// to the parent's border box; overlay borders take no CSS space).
    fn parentRelRect(n: *const Node) [4]f32 {
        const r = n.rectFromWorldOrFallback();
        var rel: [4]f32 = .{ r.x, r.y, r.w, r.h };
        if (n.parent) |p| if (!p.style.border.overlay) {
            const pb = p.style.border.resolvedWidths();
            rel[0] -= pb[3];
            rel[1] -= pb[0];
        };
        return rel;
    }

    const style_atoms = @import("style_atoms.zig");
    /// Upper bound on rules inserted at runtime; past it, new values go inline
    /// (e.g. a long colour transition) instead of growing the sheet forever.
    const max_runtime_rules = 16384;

    fn defineStaticAtoms(self: *DomHost) void {
        const Ctx = struct {
            host: *DomHost,
            fn add(ctx: @This(), prop: []const u8, value: []const u8) anyerror!void {
                var b: [96]u8 = undefined;
                const cls = style_atoms.className(&b, prop, value);
                if (ctx.host.defined.contains(cls)) return;
                try ctx.host.defined.put(ctx.host.allocator, try ctx.host.allocator.dupe(u8, cls), {});
            }
        };
        @import("atom_set.zig").forEach(Ctx{ .host = self }, Ctx.add) catch {
            self.oom = true;
        };
    }

    /// One node's style -> atomic class list + per-frame inline declarations.
    /// Declarations are written as "prop:value;" ("@prop:value;" = inline only).
    fn syncStyle(self: *DomHost, id: u32, m: *Mirror) void {
        const n = m.node;
        if (n.freeing) return;
        const has_glass = n.style.getExt().glass != null;
        if (has_glass != m.glass) {
            m.glass = has_glass;
            self.put(&.{ @backingInt(Op.glass), id, @intFromBool(has_glass) });
        }
        var buf: [16384]u8 = undefined;
        var w: std.Io.Writer = .fixed(&buf);
        self.writeDecls(&w, id, n) catch {
            w = .fixed(&buf);
            writeLayoutCss(&w, n, .abs) catch return;
        };
        const decls = w.buffered();
        const h = std.hash.Wyhash.hash(16, decls) | 1;
        // A node whose opacity just moved keeps it inline; re-check next frames
        // so a settled value is folded back into an atom.
        if (m.opacity_hot > 0) {
            m.opacity_hot -= 1;
            self.force_resync = true;
        }
        if (h == m.style_hash) return;
        m.style_hash = h;

        var cls_buf: [4096]u8 = undefined;
        var cls_w: std.Io.Writer = .fixed(&cls_buf);
        var inl_buf: [8192]u8 = undefined;
        var inl_w: std.Io.Writer = .fixed(&inl_buf);
        var it = std.mem.tokenizeScalar(u8, decls, ';');
        while (it.next()) |d| {
            const volatile_decl = d[0] == '@';
            const body = if (volatile_decl) d[1..] else d;
            const colon = std.mem.indexOfScalar(u8, body, ':') orelse continue;
            const prop = body[0..colon];
            var nv: [8192]u8 = undefined;
            const value = normalizeNumbers(&nv, body[colon + 1 ..]);
            // Equal to the reset baseline of every mirrored node: no class needed.
            if (!volatile_decl and isBaseline(prop, value)) continue;
            if (!volatile_decl) {
                var cb: [96]u8 = undefined;
                const cls = style_atoms.className(&cb, prop, value);
                if (self.defined.contains(cls) or self.defineRuntimeAtom(cls, prop, value)) {
                    cls_w.print("{s} ", .{cls}) catch {};
                    continue;
                }
            }
            inl_w.print("{s}:{s};", .{ prop, value }) catch {};
        }
        const cls = cls_w.buffered();
        const inl = inl_w.buffered();
        const cls_off: u32 = @intCast(self.strings.items.len);
        self.strings.appendSlice(self.allocator, cls) catch {
            self.oom = true;
            return;
        };
        const inl_off: u32 = @intCast(self.strings.items.len);
        self.strings.appendSlice(self.allocator, inl) catch {
            self.oom = true;
            return;
        };
        self.put(&.{ @backingInt(Op.style), id, cls_off, @intCast(cls.len), inl_off, @intCast(inl.len) });
    }

    /// Declarations equal to the reset baseline of `[data-zid]` (zenit-reset.css):
    /// omitted, like Panda omits defaults. Keep in sync with the reset rule.
    const baseline = std.StaticStringMap(void).initComptime(.{
        .{"display:flex"},           .{"flex-direction:column"}, .{"align-items:stretch"},
        .{"align-content:normal"},   .{"justify-content:flex-start"}, .{"gap:0px"},
        .{"flex-wrap:nowrap"},       .{"flex-grow:0"},           .{"flex-shrink:1"},
        .{"flex-basis:auto"},        .{"align-self:auto"},       .{"min-width:auto"},
        .{"min-height:auto"},        .{"max-width:none"},        .{"max-height:none"},
        .{"width:auto"},             .{"height:auto"},           .{"margin-top:0px"},
        .{"margin-right:0px"},       .{"margin-bottom:0px"},     .{"margin-left:0px"},
        .{"padding-top:0px"},        .{"padding-right:0px"},     .{"padding-bottom:0px"},
        .{"padding-left:0px"},       .{"pointer-events:none"},   .{"position:relative"},
        .{"white-space:pre"},        .{"text-align:start"},
    });
    fn isBaseline(prop: []const u8, value: []const u8) bool {
        var b: [96]u8 = undefined;
        const key = std.fmt.bufPrint(&b, "{s}:{s}", .{ prop, value }) catch return false;
        return baseline.has(key);
    }

    /// f32 noise -> stable spelling (6.9000006 -> 6.9): rounds every decimal
    /// number in a CSS value to 3 places so one value is one atom.
    fn normalizeNumbers(out: []u8, v: []const u8) []const u8 {
        var w: std.Io.Writer = .fixed(out);
        var i: usize = 0;
        while (i < v.len) {
            const ch = v[i];
            // A number starts at a digit not inside a token: after a letter (#hex,
            // ident, SVG path command "H300.06") or another digit/dot, it is the
            // tail of what came before ("H300.06" read as "H3" + "00.06" lost a digit).
            const starts = std.ascii.isDigit(ch) and (i == 0 or !(std.ascii.isAlphanumeric(v[i - 1]) or v[i - 1] == '#' or v[i - 1] == '_' or v[i - 1] == '.'));
            if (!starts) {
                w.writeByte(ch) catch return v;
                i += 1;
                continue;
            }
            var j = i;
            var dot = false;
            while (j < v.len and (std.ascii.isDigit(v[j]) or (v[j] == '.' and !dot))) : (j += 1) {
                if (v[j] == '.') dot = true;
            }
            const num = v[i..j];
            if (dot) {
                const x = std.fmt.parseFloat(f64, num) catch {
                    w.writeAll(num) catch return v;
                    i = j;
                    continue;
                };
                w.print("{d}", .{@round(x * 1000) / 1000}) catch return v;
            } else w.writeAll(num) catch return v;
            i = j;
        }
        return w.buffered();
    }

    fn opacityAnimating(self: *DomHost, id: u32, n: *const Node) bool {
        const m = self.live.getPtr(id) orelse return false;
        const op = n.getOpacity();
        if (op != m.last_opacity) {
            const first = m.style_hash == 0;
            m.last_opacity = op;
            if (!first) m.opacity_hot = 8;
        }
        return m.opacity_hot > 0;
    }

    fn defineRuntimeAtom(self: *DomHost, cls: []const u8, prop: []const u8, value: []const u8) bool {
        if (self.defined.count() >= max_runtime_rules) return false;
        var rb: [16384]u8 = undefined;
        var rw: std.Io.Writer = .fixed(&rb);
        style_atoms.writeSelector(&rw, cls) catch return false;
        rw.print("{{{s}:{s}}}", .{ prop, value }) catch return false;
        const rule = rw.buffered();
        const owned = self.allocator.dupe(u8, cls) catch return false;
        self.defined.put(self.allocator, owned, {}) catch {
            self.allocator.free(owned);
            return false;
        };
        const off: u32 = @intCast(self.strings.items.len);
        self.strings.appendSlice(self.allocator, rule) catch {
            self.oom = true;
            return false;
        };
        self.put(&.{ @backingInt(Op.rule), off, @intCast(rule.len) });
        return true;
    }

    fn color(w: *std.Io.Writer, c: Color) !void {
        try style_atoms.writeColor(w, c.r, c.g, c.b, c.a);
    }

    fn writeDecls(self: *DomHost, w: *std.Io.Writer, id: u32, n: *const Node) !void {
        try writeLayoutCss(w, n, self.layoutMode(n));
        if (self.css_layout) {
            // Browser hit testing (WEB_HOST_DESIGN §5): only nodes zenit can hit receive
            // pointer events; island roots take input for zenit's in-canvas hit test.
            const island_root = if (self.islands) |set| set.isRoot(n) else false;
            try w.writeAll(if (island_root or self.hittable.contains(id)) "pointer-events:auto;" else "pointer-events:none;");
        }
        const island_member_paint = if (self.islands) |set| set.isRoot(n) else false;
        if (!island_member_paint) try writePaint(w, n, self.opacityAnimating(id, n));
        if (n.tag == .text or n.getText() != null) if (n.resolveTextProps()) |t| try writeText(w, t);
    }

    fn writePaint(w: *std.Io.Writer, n: *const Node, animating_opacity: bool) !void {
        const s = &n.style;
        const e = s.getExt();
        const is_text = n.tag == .text or n.getText() != null;
        // zenit's inherited text style (StyleExt.text_*) is CSS inheritance: emit it on the
        // declaring node and let the browser inherit (text nodes emit their resolved values).
        if (!is_text) {
            if (e.text_color) |c| {
                try w.writeAll("color:");
                try color(w, c);
                try w.writeAll(";");
            }
            if (e.text_font_size) |v| try w.print("font-size:{d}px;", .{v});
            if (e.text_font_weight) |v| try w.print("font-weight:{d};", .{v});
        }
        // Icons: 1em SVG in currentColor (syncIcon). font-size = the icon box; an explicit
        // tint is the icon's own color, tint_current_color inherits it.
        if (n.getIcon()) |icon| {
            const r = n.rectFromWorldOrFallback();
            try w.print("font-size:{d}px;", .{@min(r.w, r.h)});
            // tint_current_color with no ancestor text colour falls back to the tint (zenit
            // IconProps.paintTint); otherwise CSS inheritance supplies currentColor.
            if (!icon.tint_current_color or n.resolveTextColor() == null) {
                try w.writeAll("color:");
                try color(w, icon.tint);
                try w.writeAll(";");
            }
        }
        const bg = n.getBackground();
        // Vector fill (setPathHitGeometry & co.): native paints the *background* in the path
        // shape and leaves children unclipped (node_style_render fill_path). A solid fill is
        // an SVG background in the path; a gradient fill falls back to clip-path below.
        const lo_path: ?types.PathGeometry = if (n.layoutOutput()) |lo| lo.vector.fill.path else null;
        const has_gradient = e.gradient != null or (e.multi_gradient != null and e.multi_gradient.?.stop_count >= 2);
        const path_bg = n.getIcon() == null and bg.a != 0 and !has_gradient and lo_path != null and lo_path.?.commands.len > 0;
        if (path_bg) {
            const r = n.rectFromWorldOrFallback();
            try w.print("background-image:url(\"data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' width='{d}' height='{d}' viewBox='0 0 {d} {d}' preserveAspectRatio='none'><path fill-rule='{s}' fill='%23{x:0>2}{x:0>2}{x:0>2}{x:0>2}' d='", .{ r.w, r.h, r.w, r.h, @tagName(lo_path.?.fill_rule), bg.r, bg.g, bg.b, bg.a });
            try writePathD(w, lo_path.?.commands);
            try w.writeAll("'/></svg>\");background-size:100% 100%;background-origin:border-box;background-repeat:no-repeat;");
        } else if (bg.a != 0) {
            try w.writeAll("background-color:");
            try color(w, bg);
            try w.writeAll(";");
        }
        const bw = s.border.resolvedWidths();
        if (bw[0] > 0 or bw[1] > 0 or bw[2] > 0 or bw[3] > 0) {
            if (s.border.overlay) {
                // Border.overlay paints over the content (children included) and takes
                // no layout space: a ::after frame on top (zenit-reset.css, selected by
                // the --zob class), fed through non-inherited custom properties. An
                // outline would sit under positioned children (the stepper's buttons).
                try w.print("--zob:{d}px {d}px {d}px {d}px;--zob-c:", .{ bw[0], bw[1], bw[2], bw[3] });
                try color(w, s.border.color);
                try w.writeAll(";");
            } else {
                try w.writeAll("border-style:solid;border-color:");
                try color(w, s.border.color);
                try w.writeAll(";");
                inline for (.{ "border-top-width", "border-right-width", "border-bottom-width", "border-left-width" }, 0..) |p, i| {
                    if (bw[i] > 0) try w.print(p ++ ":{d}px;", .{bw[i]});
                }
            }
        }
        // Outline (focus rings, FocusRingConfig): CSS outline + outline-offset, which
        // follow border-radius like the native ring and take no layout space.
        if (s.outline()) |o| if (o.width > 0 and o.color.a > 0) {
            try w.print("outline:{d}px solid ", .{o.width});
            try color(w, o.color);
            try w.print(";outline-offset:{d}px;", .{o.offset});
        };
        const radius: [4]f32 = if (e.corner_radius) |cr| cr.resolve4() else @splat(s.border.radius);
        inline for (.{ "border-top-left-radius", "border-top-right-radius", "border-bottom-right-radius", "border-bottom-left-radius" }, 0..) |p, i| {
            if (radius[i] > 0) try w.print(p ++ ":{d}px;", .{radius[i]});
        }
        if (hostScroll(n)) |hs| {
            // Native scroller; zenit draws its own overlay thumbs, so no browser scrollbar.
            try w.print("overflow-x:{s};overflow-y:{s};scrollbar-width:none;", .{ if (hs.axis_x) "auto" else "hidden", if (hs.axis_y) "auto" else "hidden" });
        } else if (!is_text and (s.overflow_hidden or s.overflow != .visible)) {
            try w.writeAll("overflow:hidden;");
        } else if (is_text and s.overflow_hidden) {
            // An explicit box clip on a text node clips like natively (a recycled VirtualList
            // slot: height 0 + overflow_hidden, its stale line must not spill out). clip, not
            // hidden: no scroll container. Plain text keeps vertical overflow (descenders).
            try w.writeAll("overflow:clip;");
        }
        // Vector fill / custom clip (setPathHitGeometry, SVG paths, custom clips): the node's
        // paint (and the browser's hit test) take the path shape, like native.
        // Icons/SVG carry their outline as *hit* geometry only (their strokes are the SVG
        // op): clipping them to it cuts stroked icons apart. Only a painted fill (background
        // or gradient) takes the path shape; custom clips always apply.
        // Custom clips always clip (subtree); a vector fill clips only for gradient fills
        // (solid fills are the SVG background above), never icons (hit outline only).
        const gradient_fill = n.getIcon() == null and has_gradient;
        if (n.layoutOutput()) |lo| {
            const geom = lo.vector.fill.custom_clip orelse (if (gradient_fill) lo.vector.fill.path else null);
            if (geom) |g| if (g.commands.len > 0) {
                try w.print("clip-path:path({s},'", .{@tagName(g.fill_rule)});
                try writePathD(w, g.commands);
                try w.writeAll("');");
            };
        }
        if (n.tag == .image) try w.writeAll("background-size:100% 100%;overflow:hidden;");
        if (e.z_index != 0) try w.print("z-index:{d};", .{e.z_index});
        // Composite blend (Opacity Layer blend_mode) = CSS mix-blend-mode (same names).
        if (e.blend_mode != .normal) {
            try w.writeAll("mix-blend-mode:");
            for (@tagName(e.blend_mode)) |ch| try w.writeByte(if (ch == '_') '-' else ch);
            try w.writeAll(";");
        }
        // Gradients (background-image).
        if (e.multi_gradient != null and e.multi_gradient.?.stop_count > 0) {
            const mg = e.multi_gradient.?;
            try w.writeAll("background-image:");
            try gradientHead(w, mg.direction);
            for (mg.stops[0..mg.stop_count], 0..) |st, i| {
                if (i > 0) try w.writeAll(",");
                try color(w, st.color);
                try w.print(" {d:.2}%", .{st.position * 100});
            }
            try w.writeAll(");");
        } else if (e.gradient) |g2| {
            try w.writeAll("background-image:");
            try gradientHead(w, g2.direction);
            try color(w, g2.from);
            try w.writeAll(",");
            try color(w, g2.to);
            try w.writeAll(");");
        }
        // Every drop shadow + inset shadows.
        if (e.shadow_count > 0 or e.inset_shadow != null or e.extra_inset_count > 0) {
            try w.writeAll("box-shadow:");
            var first = true;
            for (e.shadows[0..e.shadow_count]) |sh| {
                if (!first) try w.writeAll(",");
                first = false;
                try w.print("{d}px {d}px {d}px {d}px ", .{ sh.offset_x, sh.offset_y, sh.blur, sh.spread });
                try color(w, sh.color);
            }
            if (e.inset_shadow) |sh| {
                if (!first) try w.writeAll(",");
                first = false;
                try w.print("inset {d}px {d}px {d}px ", .{ sh.offset_x, sh.offset_y, sh.blur });
                try color(w, sh.color);
            }
            for (e.extra_inset_shadows[0..e.extra_inset_count]) |sh| {
                if (!first) try w.writeAll(",");
                first = false;
                try w.print("inset {d}px {d}px {d}px ", .{ sh.offset_x, sh.offset_y, sh.blur });
                try color(w, sh.color);
            }
            try w.writeAll(";");
        }
        // Glass, CSS tier (docs/WEB_GLASS_DESIGN.md §7): without WebGPU (or until the
        // glass paint island draws) the native *frosted* quality — a backdrop blur under
        // the material colour (visual_quality.materialAlpha / backdrop_blur.basicMaterial):
        // the tint when there is one (alpha 0.85), else the veil gray (alpha 0.62); a
        // group per member (scaled by its level), clipped to the union of its capsules.
        // Through --zgv / --zgi so the WebGPU tier (.z-glass-gpu) retires them alone.
        if (e.glass) |g| if (g.backdrop_blur > 0 or g.group != null) {
            try w.print("backdrop-filter:blur({d}px);-webkit-backdrop-filter:blur({d}px);", .{ g.backdrop_blur, g.backdrop_blur });
            const group_shapes = if (g.group) |grp| grp.count else 0;
            if (group_shapes > 0) {
                const grp = g.group.?;
                try w.writeAll("--zgi:");
                // Edge: the union's outline as a stroked SVG layer on top (clip-path keeps its
                // inner half): white glass on a white page otherwise has no contour at all.
                {
                    const r = n.rectFromWorldOrFallback();
                    const sh0 = grp.shapes[0];
                    const g0 = unit8(sh0.base_veil[0]);
                    const ec = edgeColor(material(.{ .r = unit8(sh0.material.glass_tint[0]), .g = unit8(sh0.material.glass_tint[1]), .b = unit8(sh0.material.glass_tint[2]), .a = unit8(sh0.material.glass_tint[3]) }, .{ .r = g0, .g = g0, .b = g0, .a = 255 }));
                    try w.print("url(\"data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' width='{d}' height='{d}' viewBox='0 0 {d} {d}'><path fill='none' stroke-width='1.5' stroke='%23{x:0>2}{x:0>2}{x:0>2}{x:0>2}' d='", .{ r.w, r.h, r.w, r.h, ec.r, ec.g, ec.b, ec.a });
                    for (grp.shapes[0..grp.count]) |sh| try writeRoundRect(w, sh.x, sh.y, sh.w, sh.h, sh.radius);
                    try w.writeAll("'/></svg>\") 0 0/100% 100% no-repeat,");
                }
                for (grp.shapes[0..grp.count], 0..) |sh, i| {
                    const t = sh.material.glass_tint;
                    const gray = unit8(sh.base_veil[0]);
                    // tint_mode < 1: absorption, 1 - tint_amount (GlassParams.toUniform).
                    const share = if (sh.material.tint_mode < 1) 1 - sh.material.tint_mode else 1;
                    var c = material(.{ .r = unit8(t[0]), .g = unit8(t[1]), .b = unit8(t[2]), .a = unit8(t[3] * share) }, .{ .r = gray, .g = gray, .b = gray, .a = 255 });
                    c.a = unit8(std.math.clamp(sh.level, 0, 1) * @as(f32, @floatFromInt(c.a)) / 255);
                    if (i > 0) try w.writeAll(",");
                    try w.writeAll("linear-gradient(");
                    try color(w, c);
                    try w.writeAll(",");
                    try color(w, c);
                    try w.print(") {d}px {d}px/{d}px {d}px no-repeat", .{ sh.x, sh.y, sh.w, sh.h });
                }
                try w.writeAll(";background:var(--zgi);clip-path:path(nonzero,'");
                for (grp.shapes[0..grp.count]) |sh| try writeRoundRect(w, sh.x, sh.y, sh.w, sh.h, sh.radius);
                try w.writeAll("');");
            } else {
                var tint = g.glass_tint orelse Color{ .r = 0, .g = 0, .b = 0, .a = 0 };
                // An absorption tint's strength is its alpha times tint_amount.
                if (g.tint_mode == .absorption) tint.a = unit8(@as(f32, @floatFromInt(tint.a)) / 255 * std.math.clamp(g.tint_amount, 0, 1));
                var c = material(tint, g.base_veil orelse Color{ .r = 247, .g = 247, .b = 247, .a = 255 });
                // The node's own fill paints over its material (native order); CSS has
                // one background colour, so the two are composited here. --zgb keeps
                // the fill alone for the WebGPU tier (zenit-reset.css .z-glass-gpu).
                if (bg.a > 0) {
                    c = over(bg, c);
                    try w.writeAll("--zgb:");
                    try color(w, bg);
                    try w.writeAll(";");
                }
                try w.writeAll("--zgv:");
                try color(w, c);
                try w.writeAll(";background-color:var(--zgv);");
                // Edge (the WebGPU tier draws a rim; --zgo retires this one there).
                if (s.outline() == null) {
                    try w.writeAll("--zgo:");
                    try color(w, edgeColor(c));
                    try w.writeAll(";outline:1px solid var(--zgo);outline-offset:-1px;");
                }
            }
        };
        // Per-frame values stay inline: opacity and transform (scroll, animation).
        const op = n.getOpacity();
        if (op < 1) try w.print("{s}opacity:{d};", .{ if (animating_opacity) "@" else "", op });
        const scaled = e.scale_x != 1 or e.scale_y != 1 or e.rotate != 0;
        // A native scroller's content is offset by the browser's scroll, not a transform.
        const scrolled = if (n.parent) |p| if (hostScroll(p)) |hs| hs.content == n else false else false;
        const tx: f32 = if (scrolled) 0 else s.translate_x;
        const ty: f32 = if (scrolled) 0 else s.translate_y;
        if (tx != 0 or ty != 0 or scaled) {
            try w.print("@transform:translate({d}px,{d}px)", .{ tx, ty });
            if (scaled) try w.print(" scale({d},{d}) rotate({d}rad)", .{ e.scale_x, e.scale_y, e.rotate });
            try w.writeAll(";");
            if (scaled) try w.writeAll("transform-origin:50% 50%;");
        }
    }

    /// CSS-tier glass material (native frosted: visual_quality.materialAlpha): a
    /// material tint (alpha >= 0.5) at 0.85; else the veil gray at 0.62 with a
    /// weak tint (a dim such as prominentClearGlass's 5 % black) laid over it at
    /// its own alpha — native's opaqueTint would paint that dim solid black.
    fn material(tint: Color, veil: Color) Color {
        if (tint.a >= 128) return .{ .r = tint.r, .g = tint.g, .b = tint.b, .a = unit8(0.85) };
        var c = over(tint, .{ .r = veil.r, .g = veil.g, .b = veil.b, .a = 255 });
        c.a = unit8(0.62);
        return c;
    }

    /// CSS-tier glass contour: a faint dark line on light material, a faint light one on dark.
    fn edgeColor(c: Color) Color {
        const lum = (0.2126 * @as(f32, @floatFromInt(c.r)) + 0.7152 * @as(f32, @floatFromInt(c.g)) + 0.0722 * @as(f32, @floatFromInt(c.b))) / 255;
        return if (lum > 0.5) .{ .r = 0, .g = 0, .b = 0, .a = 31 } else .{ .r = 255, .g = 255, .b = 255, .a = 38 };
    }

    /// Source-over of straight-alpha colours.
    fn over(top: Color, under: Color) Color {
        const ta = @as(f32, @floatFromInt(top.a)) / 255;
        const ua = @as(f32, @floatFromInt(under.a)) / 255;
        const oa = ta + ua * (1 - ta);
        if (oa <= 0) return .{ .r = 0, .g = 0, .b = 0, .a = 0 };
        const ch = struct {
            fn f(t: u8, u: u8, ta_: f32, ua_: f32, oa_: f32) u8 {
                const v = (@as(f32, @floatFromInt(t)) * ta_ + @as(f32, @floatFromInt(u)) * ua_ * (1 - ta_)) / oa_;
                return @intFromFloat(@round(std.math.clamp(v, 0, 255)));
            }
        }.f;
        return .{ .r = ch(top.r, under.r, ta, ua, oa), .g = ch(top.g, under.g, ta, ua, oa), .b = ch(top.b, under.b, ta, ua, oa), .a = unit8(oa) };
    }

    fn unit8(x: f32) u8 {
        return @intFromFloat(@round(std.math.clamp(x, 0, 1) * 255));
    }

    fn writeRoundRect(w: *std.Io.Writer, x: f32, y: f32, wd: f32, ht: f32, radius: f32) !void {
        const r = @max(0, @min(radius, @min(wd, ht) / 2));
        try w.print("M{d} {d}H{d}A{d} {d} 0 0 1 {d} {d}V{d}A{d} {d} 0 0 1 {d} {d}H{d}A{d} {d} 0 0 1 {d} {d}V{d}A{d} {d} 0 0 1 {d} {d}Z", .{
            x + r, y, x + wd - r, r, r, x + wd, y + r, y + ht - r, r, r, x + wd - r, y + ht, x + r, r, r, x, y + ht - r, y + r, r, r, x + r, y,
        });
    }

    fn writePathD(w: *std.Io.Writer, cmds: []const types.PathCommand) !void {
        for (cmds) |c| switch (c) {
            .move_to => |p| try w.print("M{d} {d}", .{ p.x, p.y }),
            .line_to => |p| try w.print("L{d} {d}", .{ p.x, p.y }),
            .quad_to => |q| try w.print("Q{d} {d} {d} {d}", .{ q.ctrl.x, q.ctrl.y, q.end.x, q.end.y }),
            .cubic_to => |cu| try w.print("C{d} {d} {d} {d} {d} {d}", .{ cu.ctrl1.x, cu.ctrl1.y, cu.ctrl2.x, cu.ctrl2.y, cu.end.x, cu.end.y }),
            .close => try w.writeAll("Z"),
        };
    }

    fn gradientHead(w: *std.Io.Writer, dir: types.GradientDirection) !void {
        try w.writeAll(switch (dir) {
            .horizontal => "linear-gradient(to right,",
            .vertical => "linear-gradient(to bottom,",
            .diagonal => "linear-gradient(to bottom right,",
            .radial => "radial-gradient(closest-side,",
            .conic => "conic-gradient(",
        });
    }

    /// Rows the browser clamps: max_lines of multi-line text (a single line has one row).
    fn lineClamp(t: types.TextProps) u16 {
        return if (t.wrap == .none) 0 else t.max_lines;
    }

    fn writeText(w: *std.Io.Writer, t: types.TextProps) !void {
        try w.writeAll("color:");
        try color(w, t.color);
        try w.print(";font-family:var(--zf{s}-{d});font-size:{d}px;font-weight:{d};line-height:{d}px;", .{
            if (t.use_monospace_font) "m" else "", t.font_family, t.font_size, t.font_weight, t.font_size * t.line_height,
        });
        if (t.use_italic_font) try w.writeAll("font-style:italic;");
        const ellipsis = t.text_overflow != .clip;
        // Wrapping is the browser's (CSS text mapping validated by the LC conformance gate):
        // TextWrap -> white-space, plus overflow-wrap / word-break. An ellipsis no longer makes
        // wrapped text single-line: text_overflow marks overflowing lines and the line clamp.
        try w.writeAll(if (t.wrap == .none or t.wrap == .newline_only) "white-space:pre;" else "white-space:pre-wrap;");
        if (t.wrap != .none and t.wrap != .newline_only) {
            const ow: []const u8 = switch (t.overflow_wrap) {
                .normal => switch (t.wrap) {
                    .char => "anywhere",
                    .word_break => "break-word",
                    else => "normal",
                },
                .break_word => "break-word",
                .anywhere => "anywhere",
            };
            if (!std.mem.eql(u8, ow, "normal")) try w.print("overflow-wrap:{s};", .{ow});
            const wb: []const u8 = switch (t.word_break) {
                .normal => switch (t.wrap) {
                    .break_all => "break-all",
                    .keep_all => "keep-all",
                    else => "normal",
                },
                .break_all => "break-all",
                .keep_all => "keep-all",
            };
            if (!std.mem.eql(u8, wb, "normal")) try w.print("word-break:{s};", .{wb});
        }
        try w.print("text-align:{s};", .{@tagName(t.text_align)});
        const clamp = lineClamp(t);
        if (clamp > 0) {
            // Multi-line text cut at max_lines (display:-webkit-box, writeLayoutCss). Browsers
            // end the last line with an ellipsis here whatever text-overflow says.
            try w.print("overflow:hidden;-webkit-box-orient:vertical;-webkit-line-clamp:{d};", .{clamp});
        }
        if (ellipsis) {
            // Single lines and every overflowing line of multi-line text end in an ellipsis.
            try w.writeAll("text-overflow:ellipsis;overflow:hidden;");
        } else if (t.wrap == .none) {
            // zenit .clip = GPU scissor at the node box: a single line never spills past
            // its width; horizontal only so ascenders/descenders still paint.
            try w.writeAll("overflow-x:clip;");
        }
        if (t.fade_right > 0) {
            // TextProps.fade_right: glyph alpha ramps to 0 over the last N px.
            try w.print("mask-image:linear-gradient(to right,#000 calc(100% - {d}px),transparent);-webkit-mask-image:linear-gradient(to right,#000 calc(100% - {d}px),transparent);", .{ t.fade_right, t.fade_right });
        }
        if (t.strikethrough) try w.writeAll("text-decoration:line-through;");
    }

    fn flexAlign(a: types.AlignItems) []const u8 {
        return switch (a) {
            .start => "flex-start",
            .end => "flex-end",
            .center => "center",
            .stretch => "stretch",
            .baseline => "baseline",
            .first_baseline => "first baseline",
        };
    }

    fn justifyCss(j: types.JustifyContent) []const u8 {
        return switch (j) {
            .start => "flex-start",
            .end => "flex-end",
            .center => "center",
            .space_between => "space-between",
            .space_around => "space-around",
            .space_evenly => "space-evenly",
        };
    }

    fn alignContentCss(a: types.AlignContent) []const u8 {
        return switch (a) {
            .normal => "normal",
            .start => "flex-start",
            .end => "flex-end",
            .center => "center",
            .stretch => "stretch",
            .space_between => "space-between",
            .space_around => "space-around",
            .space_evenly => "space-evenly",
        };
    }

    fn writeTrack(w: *std.Io.Writer, t: types.GridTrackSize) !void {
        switch (t) {
            .minmax => |mm| {
                try w.writeAll("minmax(");
                switch (mm.min) {
                    .auto => try w.writeAll("auto"),
                    inline else => |v, tag| try w.print("{d}{s}", .{ v, if (comptime std.mem.eql(u8, @tagName(tag), "fr")) "fr" else "px" }),
                }
                try w.writeAll(",");
                switch (mm.max) {
                    .auto => try w.writeAll("auto"),
                    inline else => |v, tag| try w.print("{d}{s}", .{ v, if (comptime std.mem.eql(u8, @tagName(tag), "fr")) "fr" else "px" }),
                }
                try w.writeAll(")");
            },
            .auto => try w.writeAll("auto"),
            inline else => |v, tag| try w.print("{d}{s}", .{ v, if (comptime std.mem.eql(u8, @tagName(tag), "fr")) "fr" else "px" }),
        }
    }

    /// zenit Style -> CSS layout declarations. Port of the LC conformance oracle
    /// mapping (conformance.mjs `styleCSS`); keep the two in sync.
    fn writeLayoutCss(w: *std.Io.Writer, n: *const Node, mode: LayoutMode) !void {
        const s = &n.style;
        const e = s.getExt();
        // Text-bearing boxes (Input display nodes etc.) are text blocks too.
        const tp = if (n.tag == .text or n.getText() != null) n.resolveTextProps() else null;
        const is_text = tp != null;
        const max_lines: u16 = if (tp) |t| lineClamp(t) else 0;

        // ── container side (applies in every mode: children may flow inside) ──
        const display: []const u8 = if (s.display == .none) "none" else if (is_text) (if (max_lines > 0) "-webkit-box" else "block") else if (e.grid != null) "grid" else "flex";
        try w.print("display:{s};", .{display});
        if (!is_text) {
            try w.print("flex-direction:{s};align-items:{s};align-content:{s};justify-content:{s};gap:{d}px;flex-wrap:{s};", .{
                switch (s.direction) {
                    .row => "row",
                    .row_reverse => "row-reverse",
                    .column => "column",
                    .column_reverse => "column-reverse",
                },
                flexAlign(s.align_items),
                alignContentCss(s.align_content),
                justifyCss(s.justify),
                s.gap,
                switch (e.flex_wrap) {
                    .no_wrap => "nowrap",
                    .wrap => "wrap",
                    .wrap_reverse => "wrap-reverse",
                },
            });
        }
        // zenit allows negative padding (Input scrolls its text with padding-left =
        // padding - scroll_x); CSS does not. The negative part moves to the margin
        // (flow items, below), which shrinks the outer size and shifts the content alike.
        const pads = [4]f32{ s.padding.top, s.padding.right, s.padding.bottom, s.padding.left };
        inline for (.{ "top", "right", "bottom", "left" }, 0..) |side, i| try w.print("padding-" ++ side ++ ":{d}px;", .{@max(0, pads[i])});
        if (e.grid) |g| {
            try w.writeAll("grid-template-columns:");
            for (g.columns[0..g.column_count], 0..) |t, i| {
                if (i > 0) try w.writeAll(" ");
                try writeTrack(w, t);
            }
            try w.writeAll(";");
            if (g.row_count > 0) {
                try w.writeAll("grid-template-rows:");
                for (g.rows[0..g.row_count], 0..) |t, i| {
                    if (i > 0) try w.writeAll(" ");
                    try writeTrack(w, t);
                }
                try w.writeAll(";");
            }
            try w.print("column-gap:{d}px;row-gap:{d}px;", .{ g.column_gap, g.row_gap });
        }
        if (s.layout_isolation) try w.writeAll("contain:layout;");

        // ── item side ──
        switch (mode) {
            .abs => {
                // Out-of-flow children of a native scroller (its overlay scrollbar
                // thumbs) live in the scroller's non-scrolling rail (zenit-dom.mjs), which
                // covers the scroller's padding box: same coordinates, never scrolled.
                const r = parentRelRect(n);
                try w.print("position:absolute;@left:{d}px;@top:{d}px;@width:{d}px;@height:{d}px;flex-grow:0;flex-shrink:0;", .{ r[0], r[1], r[2], r[3] });
                return;
            },
            .pinned => {
                const r = n.rectFromWorldOrFallback();
                try w.print("position:relative;width:{d}px;height:{d}px;flex-grow:0;flex-shrink:0;contain:layout size;", .{ r.w, r.h });
            },
            .flow => {
                const parent = n.parent.?;
                const row = parent.style.direction.isRow();
                const parent_grid = parent.style.getExt().grid != null;
                // An overlay border's ::after frame needs the node as its containing block.
                const positioned = s.position != .static or (s.border.overlay and s.border.resolvedWidths()[0] + s.border.resolvedWidths()[1] + s.border.resolvedWidths()[2] + s.border.resolvedWidths()[3] > 0);
                try w.print("position:{s};flex-shrink:{d};", .{ if (positioned) "relative" else "static", s.flex_shrink });
                var grow: f32 = 0;
                var mins: [2]?f32 = .{ null, null };
                var maxs: [2]?f32 = .{ null, null };
                inline for (.{ "width", "height" }, 0..) |axis, ai| {
                    const sz = @field(s, axis);
                    const main = (ai == 0) == row;
                    switch (sz) {
                        .px => |v| try w.print(axis ++ ":{d}px;", .{v}),
                        .percent => |v| try w.print(axis ++ ":{d}%;", .{v}),
                        .grow => |mm| {
                            try w.writeAll(axis ++ ":auto;");
                            if (main and !parent_grid) grow = s.flex;
                            if (mm.min != -1) mins[ai] = mm.min;
                            if (mm.max != std.math.inf(f32)) maxs[ai] = mm.max;
                        },
                        .fit => |mm| {
                            try w.writeAll(if (main) axis ++ ":max-content;" else axis ++ ":auto;");
                            if (mm.min != -1) mins[ai] = mm.min;
                            if (mm.max != std.math.inf(f32)) maxs[ai] = mm.max;
                        },
                    }
                }
                // Ext and Sizing constraints intersect; CSS min wins over max.
                const ext_min = [2]f32{ e.min_width, e.min_height };
                const ext_max = [2]f32{ e.max_width, e.max_height };
                inline for (.{ "width", "height" }, 0..) |axis, ai| {
                    if (ext_min[ai] >= 0) mins[ai] = @max(ext_min[ai], mins[ai] orelse 0);
                    if (ext_max[ai] != std.math.inf(f32)) maxs[ai] = @min(ext_max[ai], maxs[ai] orelse std.math.inf(f32));
                    // zenit text is at least one line tall even when empty.
                    if (ai == 1 and mins[ai] == null and s.height == .fit) if (tp) |t| {
                        if (t.content.len == 0) mins[ai] = t.font_size * t.line_height + s.padding.top + s.padding.bottom;
                    };
                    // Non-text leaves have no CSS-visible content for zenit (an <img>/<svg>
                    // child is paint only): automatic minimum size is 0, as in the engine.
                    if (mins[ai] == null and tp == null and n.children.items.len == 0) mins[ai] = 0;
                    if (mins[ai]) |v| try w.print("min-" ++ axis ++ ":{d}px;", .{v}) else try w.writeAll("min-" ++ axis ++ ":auto;");
                    if (maxs[ai]) |v| try w.print("max-" ++ axis ++ ":{d}px;", .{v}) else try w.writeAll("max-" ++ axis ++ ":none;");
                }
                try w.print("flex-grow:{d};", .{grow});
                if (e.flex_basis == types.FlexBasis.content) {
                    try w.writeAll("flex-basis:content;");
                } else if (e.flex_basis >= 0) {
                    try w.print("flex-basis:{d}px;", .{e.flex_basis});
                } else try w.writeAll("flex-basis:auto;");
                if (e.align_self) |a| {
                    try w.print("align-self:{s};", .{flexAlign(a)});
                } else if (e.no_cross_stretch and parent.style.align_items == .stretch) {
                    try w.writeAll("align-self:flex-start;");
                } else try w.writeAll("align-self:auto;");
                const mv = [4]f32{ s.margin.top, s.margin.right, s.margin.bottom, s.margin.left };
                const pv = [4]f32{ s.padding.top, s.padding.right, s.padding.bottom, s.padding.left };
                inline for (.{ "margin-top", "margin-right", "margin-bottom", "margin-left" }, 0..) |side, i| {
                    if (e.margin_auto_mask & (@as(u8, 1) << i) != 0) {
                        try w.writeAll(side ++ ":auto;");
                    } else if (pv[i] < 0) {
                        // Negative padding (a scroll offset): per-frame, keep it inline.
                        try w.print("@" ++ side ++ ":{d}px;", .{mv[i] + pv[i]});
                    } else try w.print(side ++ ":{d}px;", .{mv[i]});
                }
                const ins = e.inset;
                inline for (.{ "top", "right", "bottom", "left" }) |side| switch (@field(ins, side)) {
                    .auto => {},
                    .px => |v| try w.print(side ++ ":{d}px;", .{v}),
                    .percent => |v| try w.print(side ++ ":{d}%;", .{v}),
                };
                if (e.aspect_ratio > 0) try w.print("aspect-ratio:{d};", .{e.aspect_ratio});
                if (e.grid_placement) |gp| {
                    if (gp.col_start > 0) try w.print("grid-column:{d} / span {d};", .{ gp.col_start, gp.col_span }) else try w.print("grid-column:auto / span {d};", .{gp.col_span});
                    if (gp.row_start > 0) try w.print("grid-row:{d} / span {d};", .{ gp.row_start, gp.row_span }) else try w.print("grid-row:auto / span {d};", .{gp.row_span});
                }
            },
        }
    }

    fn syncText(self: *DomHost, id: u32, m: *Mirror, n: *const Node) void {
        const t = n.resolveTextProps() orelse return;
        const off: u32 = @intCast(self.strings.items.len);
        // The browser wraps (white-space/overflow-wrap/word-break from TextProps, see
        // writeText): selection and copy see the real text, no injected line breaks.
        self.strings.appendSlice(self.allocator, t.content) catch {
            self.oom = true;
            return;
        };
        const text = self.strings.items[off..];
        const h = @import("trace").work_counters.hashText(1, text) | 1;
        if (h == m.text_hash) {
            self.strings.shrinkRetainingCapacity(off);
            return;
        }
        m.text_hash = h;
        self.put(&.{ @backingInt(Op.text), id, off, @intCast(text.len) });
    }

    /// Icons: each glyph is defined once as an SVG <symbol> (icon_def), nodes reference
    /// it (<svg class=z-icon><use/></svg>). Paint is CSS: the SVG is 1em square and
    /// draws in currentColor, so the icon is sized by font-size and tinted by color
    /// (inherited from the ancestors for tint_current_color, like zenit). See writePaint.
    fn syncIcon(self: *DomHost, id: u32, m: *Mirror, n: *const Node, icon: types.IconProps) void {
        _ = n;
        const rep = icon.rep;
        const key: u64 = (@as(u64, icon.icon_id) << 32) | rep.size;
        if (!self.icon_defs.contains(key)) {
            self.icon_defs.put(self.allocator, key, {}) catch {
                self.oom = true;
                return;
            };
            const off: u32 = @intCast(self.strings.items.len);
            var stroke: f32 = 0;
            var fill = false;
            for (rep.shapes) |shape| {
                if (shape.stroke_width > 0) stroke = shape.stroke_width;
                if (shape.fill) fill = true;
                for (shape.contours) |c| {
                    for (c.points, 0..) |p, i| {
                        var buf: [48]u8 = undefined;
                        const seg = std.fmt.bufPrint(&buf, "{c}{d:.2} {d:.2}", .{ @as(u8, if (i == 0) 'M' else 'L'), p.x, p.y }) catch unreachable;
                        self.strings.appendSlice(self.allocator, seg) catch {
                            self.oom = true;
                            return;
                        };
                    }
                    if (c.closed) self.strings.append(self.allocator, 'Z') catch {
                        self.oom = true;
                    };
                }
            }
            const len: u32 = @intCast(self.strings.items.len - off);
            self.put(&.{ @backingInt(Op.icon_def), icon.icon_id, rep.size, f(rep.view_min_x), f(rep.view_min_y), f(rep.view_width), f(rep.view_height), off, len, f(stroke), @intFromBool(fill) });
        }
        if (key == m.icon_hash) return;
        m.icon_hash = key;
        self.put(&.{ @backingInt(Op.icon), id, icon.icon_id, rep.size });
    }
};

test "DomHost text CSS: ellipsis keeps wrapped text multi-line with the line clamp; a single line is never clamped" {
    const T = struct {
        fn css(buf: []u8, t: types.TextProps) ![]const u8 {
            var w: std.Io.Writer = .fixed(buf);
            try DomHost.writeText(&w, t);
            return w.buffered();
        }
    };
    var buf: [1024]u8 = undefined;
    // Wrapped + max_lines + ellipsis (a clamped tooltip label): pre-wrap and -webkit-line-clamp.
    const clamped = try T.css(&buf, .{ .content = "long text", .wrap = .word_break, .max_lines = 3, .text_overflow = .ellipsis });
    try std.testing.expect(std.mem.indexOf(u8, clamped, "white-space:pre-wrap;") != null);
    try std.testing.expect(std.mem.indexOf(u8, clamped, "overflow-wrap:break-word;") != null);
    try std.testing.expect(std.mem.indexOf(u8, clamped, "-webkit-line-clamp:3;") != null);
    try std.testing.expect(std.mem.indexOf(u8, clamped, "text-overflow:ellipsis;") != null);
    try std.testing.expectEqual(@as(u16, 3), DomHost.lineClamp(.{ .wrap = .word_break, .max_lines = 3 }));
    // Newline-only rows: pre, clamped, each overflowing row ellipsized.
    const rows = try T.css(&buf, .{ .content = "a\nb", .wrap = .newline_only, .max_lines = 2, .text_overflow = .ellipsis });
    try std.testing.expect(std.mem.indexOf(u8, rows, "white-space:pre;") != null);
    try std.testing.expect(std.mem.indexOf(u8, rows, "-webkit-line-clamp:2;") != null);
    // A single line: ellipsis, no clamp (max_lines has no meaning for one row).
    const single = try T.css(&buf, .{ .content = "long", .wrap = .none, .max_lines = 3, .text_overflow = .ellipsis });
    try std.testing.expect(std.mem.indexOf(u8, single, "white-space:pre;") != null);
    try std.testing.expect(std.mem.indexOf(u8, single, "line-clamp") == null);
    try std.testing.expect(std.mem.indexOf(u8, single, "text-overflow:ellipsis;") != null);
    try std.testing.expectEqual(@as(u16, 0), DomHost.lineClamp(.{ .wrap = .none, .max_lines = 3 }));
    // Default clip on wrapped text: the clamp alone (no text-overflow).
    const clip = try T.css(&buf, .{ .content = "long text", .wrap = .word, .max_lines = 2 });
    try std.testing.expect(std.mem.indexOf(u8, clip, "-webkit-line-clamp:2;") != null);
    try std.testing.expect(std.mem.indexOf(u8, clip, "text-overflow") == null);
}

test "DomHost text CSS: a tooltip label clamped at three lines stays multi-line with the clamp and its ellipsis" {
    const tooltip_styles = @import("../components/tooltip/styles.zig");
    var props: types.TextProps = .{ .content = "A long description that needs more than three lines in a tooltip" };
    _ = tooltip_styles.tooltipLabelStyle(null, 12, &core.theme.dark).applyTo(&props);
    var buf: [1024]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try DomHost.writeText(&w, props);
    const css = w.buffered();
    try std.testing.expect(std.mem.indexOf(u8, css, "white-space:pre-wrap;") != null);
    try std.testing.expect(std.mem.indexOf(u8, css, "-webkit-line-clamp:3;") != null);
    try std.testing.expect(std.mem.indexOf(u8, css, "text-overflow:ellipsis;") != null);
    try std.testing.expectEqual(@as(u16, 3), DomHost.lineClamp(props));
}
