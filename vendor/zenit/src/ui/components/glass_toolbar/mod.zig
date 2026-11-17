//! GlassToolbar -- macOS 26 Liquid Glass toolbar replica of NSToolbar.
//!
//! Real measurement (scripts/glass_native_model/native_appkit_controls.swift: titled window with
//! NSToolbar, real cursor + HID hover/press/release/unfocus; docs/GLASS_NATIVE_FIDELITY.md
//! 'Mouse interaction on macOS'):
//! - Each group is a 36 pt tall regular glass capsule, groups 10 pt apart. Items are icon + 14 pt
//!   wide (the 24 pt Lucide icons both sides now carry: 38), centered on the icon: a button group
//!   has 1 pt pad at each end (two 24 pt items: capsule 78, icon centres 20 / 58), a segmented
//!   group none (three: 114, centres 19 / 57 / 95). AppKit's bordered items are icon + 16 wide
//!   and overlap by 2.
//! - Icon 70% black (read 74 on glass 247); window unfocused 28.5% (read 176 on 241).
//! - Backplate: 32x28 capsule centered on the item, stacked black: hover 13/255, press 26,
//!   selected 26, combos additive (selected + hover 39 -> 209, selected + press 52 -> 197, on glass
//!   247). Unfocused ratio unchanged.
//! - Divider between segments 1x20 pt (5% black), only between two unselected adjacent segments.
//! - State changes snap per frame, no transition; segment select jumps on release.
//! - Disabled item (not measured): icon at the family ink's tertiary-label alpha (~26%), no plate.
//!
//! Template form: `<W.GlassToolbar>` takes `<W.GlassToolbarGroup>` children, each a capsule of
//! `<W.GlassToolbarButton>` elements whose icon / label / disabled follow their sources.
const std = @import("std");
const Allocator = std.mem.Allocator;
const core = @import("../../core.zig");
const Cx = core.Cx;
const Node = core.Node;
const box = core.box;
const Color = core.Color;
const Handler = core.Handler;
const reactive = @import("../../reactive.zig");
const Scope = reactive.Scope;
const Model = reactive.Model;
const Source = reactive.Source;
const events = @import("../../events.zig");
const Event = events.Event;
const EventResult = events.EventResult;
const svg_assets = @import("../../svg_assets.zig");
const glass_box = @import("../glass_box/mod.zig");

/// Glass capsule height (= native NSToolbar item height)
pub const bar_height: f32 = 36;
/// Icon edge length (the 24 pt Lucide icons; the native probe carries the same files)
pub const icon_size: f32 = 24;
/// Item width (button and segment same): icon + 14
pub const button_width: f32 = icon_size + 14;
pub const segment_width: f32 = icon_size + 14;
/// Capsule ends padding: button group / segmented group
pub const buttons_end_pad: f32 = 1;
pub const segmented_end_pad: f32 = 0;
/// Group spacing (native first-group right edge 455 -> second-group left edge 465)
pub const group_spacing: f32 = 10;
/// Backplate: capsule centered on item
pub const plate_width: f32 = 32;
pub const plate_height: f32 = 28;
pub const separator_height: f32 = 20;

/// One appearance: backplate / divider / icon all stack same color (bright family black, dark
/// family white)
/// over glass, alpha is native reading converted directly in sRGB encoding space; backplate states
/// add up.
pub const Palette = struct {
    ink: Color,
    plate_hover: u8,
    plate_press: u8,
    plate_selected: u8,
    separator: u8,
    icon_active: u8,
    icon_inactive: u8,
    /// Disabled item icon (window focused or not), no backplate. Not measured on native yet:
    /// AppKit draws a disabled toolbar item with the tertiary label color (alpha ~0.26 light /
    /// 0.25 dark), so the same alpha of the family ink.
    icon_disabled: u8,
};

/// Light family (glass 247): hover 234, press/selected 222, selected+hover 209, selected+press 197;
/// icon 74 (unfocused 176).
pub const light_palette = Palette{ .ink = Color.rgba(0, 0, 0, 255), .plate_hover = 13, .plate_press = 26, .plate_selected = 26, .separator = 13, .icon_active = 179, .icon_inactive = 73, .icon_disabled = 66 };
/// Dark family (dark appearance, glass 26 on titlebar 31): hover 46, press/selected 61,
/// selected+hover 81,
/// selected+press 96 (stack white 8.7% / 15.3%, additive); icon 90% white (232, unfocused ~34%);
/// divider 46. Unfocused backplate ratio unchanged.
pub const dark_palette = Palette{ .ink = Color.rgba(255, 255, 255, 255), .plate_hover = 22, .plate_press = 39, .plate_selected = 39, .separator = 22, .icon_active = 230, .icon_inactive = 87, .icon_disabled = 64 };

pub const ToolbarButton = struct {
    icon: svg_assets.Asset,
    width: f32 = button_width,
    on_click: ?Handler(void) = null,
    /// Accessibility name
    label: []const u8 = "",
    test_id: ?[]const u8 = null,
    /// Disabled: dimmed icon, no hover / press plate, clicks ignored, a11y disabled
    /// (`.{ .signal = sig }` / `.{ .derived = … }` follows a source).
    disabled: Source(bool) = .{ .value = false },
};

pub const ToolbarSegmented = struct {
    icons: []const svg_assets.Asset,
    /// Each segment accessibility name (can be shorter than icons)
    labels: []const []const u8 = &.{},
    selected: Model(usize) = .{ .local = 0 },
    on_change: ?Handler(usize) = null,
    width: f32 = segment_width,
    /// Each segment test_id is '<test_id>.<segment_index>'
    test_id: ?[]const u8 = null,
};

pub const ToolbarGroup = union(enum) {
    /// Several buttons in one glass capsule
    buttons: []const ToolbarButton,
    /// Radio-button segmented group
    segmented: ToolbarSegmented,
    /// Flexible space (consume remaining width, push following groups right)
    flexible_space,
};

/// Groups use an explicit-typed array (anonymous literals can't infer the union across slices):
///   const groups = [_]ToolbarGroup{
///       .{ .buttons = &[_]ToolbarButton{ .{ .icon = icons.panel_left, .on_click = ... } } },
///       .{ .segmented = .{ .icons = &[_]Asset{ icons.list, icons.layout_grid }, .selected = .{
///       .bound = sel } } },
///       .flexible_space,
///   };
///   GlassToolbar(.{ .groups = &groups }).mount(scope, cx)
pub const GlassToolbarProps = struct {
    groups: []const ToolbarGroup = &.{},
    spacing: f32 = group_spacing,
    test_id: ?[]const u8 = null,
};

/// Single clickable item (button or segment)
const Item = struct {
    cx: *Cx,
    /// Glass state of capsule it's in: family (light/dark) adapts to background, coloring follows.
    /// A `GlassToolbarButton` element finds its capsule on its first frame (null before: the
    /// appearance's family).
    glass: ?*glass_box.AdaptiveGlassBoxState,
    node: *Node,
    plate: *Node,
    icon: *Node,
    width: f32,
    hovered: bool = false,
    pressed: bool = false,
    /// Pointer still in item after press (drag out cancels highlight, drag back restores--AppKit
    /// std tracking)
    inside: bool = false,
    disabled: Source(bool) = .{ .value = false },
    /// svg data of the icon on screen (element buttons rebuild the icon when it changes)
    icon_svg: ?[*]const u8 = null,
    kind: union(enum) {
        button: ?Handler(void),
        segment: struct { group: *Segmented, index: usize },
    },

    fn selected(self: *const Item) bool {
        return switch (self.kind) {
            .button => false,
            .segment => |s| s.group.selected.readAs(false) == s.index,
        };
    }

    fn familyDark(self: *const Item) bool {
        return if (self.glass) |g| g.family_dark else self.cx.tokens.scheme == .dark;
    }

    fn isDisabled(self: *const Item) bool {
        return self.disabled.peek();
    }

    fn palette(self: *const Item) *const Palette {
        return if (self.familyDark()) &dark_palette else &light_palette;
    }

    /// Color under one family, interpolate between families by capsule's family transition (ink
    /// color
    /// transitions with glass on family flip)
    fn ink(self: *const Item, comptime f: fn (*const Item, *const Palette) Color) Color {
        const g = self.glass orelse return f(self, self.palette());
        return glass_box.familyInk(g, f(self, &light_palette), f(self, &dark_palette));
    }

    fn plateColor(self: *const Item, p: *const Palette) Color {
        return p.ink.withAlpha(self.plateAlphaIn(p));
    }

    fn iconColor(self: *const Item, p: *const Palette) Color {
        if (self.isDisabled()) return p.ink.withAlpha(p.icon_disabled);
        return p.ink.withAlpha(if (self.cx.window_active) p.icon_active else p.icon_inactive);
    }

    fn separatorColor(self: *const Item, p: *const Palette) Color {
        _ = self;
        return p.ink.withAlpha(p.separator);
    }

    fn plateAlpha(self: *const Item) u8 {
        return self.plateAlphaIn(self.palette());
    }

    fn plateAlphaIn(self: *const Item, p: *const Palette) u8 {
        const base: u8 = if (self.selected()) p.plate_selected else 0;
        if (self.isDisabled()) return base;
        const state: u8 = if (self.pressed and self.inside) p.plate_press else if (self.hovered and !self.pressed) p.plate_hover else 0;
        return base + state;
    }
};

const Segmented = struct {
    selected: reactive.Bound(usize),
    on_change: ?Handler(usize),
    /// Three slices per-item assigned, unified cleanup by GlassToolbarRuntime (assembly fail
    /// mid-way
    /// only free already-allocated)
    items: []*Item = &.{},
    /// separators[i] between segment i and i+1
    separators: []*Node = &.{},
    /// Each segment test_id '<test_id>.<segment_index>': node only borrowed, held here, freed with
    /// scope
    test_ids: [][]u8 = &.{},

    /// Must be caller's last step: on_change may destroy this control
    fn select(self: *Segmented, index: usize) void {
        const on_change = self.on_change;
        const landed = self.selected.commit(index) orelse return;
        if (on_change) |h| h.call(landed);
    }
};

pub const GlassToolbarRuntime = struct {
    cx: *Cx,
    root: *Node,
    items: std.ArrayListUnmanaged(*Item) = .empty,
    segmented: std.ArrayListUnmanaged(*Segmented) = .empty,

    /// Each frame (before_render) write state as appearance; setBackground/setTint
    /// self-deduplicate,
    /// silent when at rest (not mark dirty).
    fn refresh(self: *GlassToolbarRuntime) void {
        for (self.items.items) |it| refreshItem(it);
        for (self.segmented.items) |seg| {
            const sel = seg.selected.readAs(false);
            for (seg.separators, 0..) |sep, i| {
                const hidden = sel == i or sel == i + 1;
                const c = seg.items[i].ink(Item.separatorColor);
                sep.setBackground(if (hidden) c.withAlpha(0) else c);
            }
        }
    }
};

/// macOS 26 titlebar edge (native_titlebar_scroll.swift: unified NSToolbar fullSizeContentView
/// window, NSScrollView content scrolling under the toolbar, pixel-aligned with a no-titlebar
/// same-content reference): content is **washed to the window background color**; the top 0-20 pt
/// holds 0.85, then decays smoothly to gone at ~76 pt (52 pt titlebar + ~24 pt more). Light/dark
/// curves are identical per point, target colors 249 / 34.
/// scrollEdgeEffectStyle(.soft/.hard/hidden)
/// changes nothing: this strip is the titlebar's own background, independent of scroll, always
/// there. In sRGB encoding space blend out = (1 - a)*content + a*bg is exactly one layer of
/// background color with a gradient. Unmodeled: within the titlebar range there is another
/// ~1.5 pt sigma light blur.
pub const titlebar_edge_height: f32 = 76;
/// (distance from top pt, wash-white ratio) -- real measurement curve (light/dark average)
pub const titlebar_edge_profile = [_][2]f32{
    .{ 0, 0.85 },  .{ 20, 0.85 }, .{ 24, 0.79 }, .{ 28, 0.75 }, .{ 32, 0.70 }, .{ 36, 0.63 },
    .{ 40, 0.54 }, .{ 44, 0.44 }, .{ 48, 0.35 }, .{ 52, 0.25 }, .{ 56, 0.18 }, .{ 60, 0.12 },
    .{ 64, 0.07 }, .{ 68, 0.04 }, .{ 72, 0.02 }, .{ 76, 0 },
};
pub const titlebar_edge_light = Color.rgba(249, 249, 249, 255);
pub const titlebar_edge_dark = Color.rgba(34, 34, 34, 255);

pub const TitlebarEdgeProps = struct {
    /// null = fill parent width
    width: ?f32 = null,
    /// null = pick light/dark by theme (ThemeTokens.scheme)
    dark: ?bool = null,
};

/// Build titlebar edge strip: absolutely positioned stick to parent top, don't intercept hit
/// (content below scrolls normally), place above content, below toolbar. With `dark` null the
/// strip re-picks light / dark on every `Cx.setTheme`.
pub fn titlebarEdge(cx: *Cx, props: TitlebarEdgeProps) !*Node {
    const n = try box(cx, .{
        .width = if (props.width) |w| .{ .px = w } else .{ .grow = .{} },
        .height = .{ .px = titlebar_edge_height },
        .position = .absolute,
    }, .{});
    errdefer cx.freeNode(n);
    const e = try n.style.ensureExtFallible(cx.allocator);
    e.inset = .{ .left = .{ .px = 0 }, .top = .{ .px = 0 } };
    e.hit_behavior = .pass_through;
    setTitlebarEdgeGradient(n, props.dark orelse (cx.tokens.scheme == .dark));
    if (props.dark == null) n.meta.per_frame.hooks.on_theme = struct {
        fn hook(node: *Node, t: *const core.ThemeTokens, _: Allocator) void {
            setTitlebarEdgeGradient(node, t.scheme == .dark);
            node.markRenderDirty();
        }
    }.hook;
    n.meta.ownership.meta.component_name = "TitlebarEdge";
    return n;
}

/// The measured wash profile toward the window background of one appearance (ext allocated).
fn setTitlebarEdgeGradient(n: *Node, dark: bool) void {
    const base = if (dark) titlebar_edge_dark else titlebar_edge_light;
    var stops: [titlebar_edge_profile.len]core.GradientStop = undefined;
    for (titlebar_edge_profile, 0..) |pt, i| {
        stops[i] = .{ .color = base.withAlpha(@intFromFloat(@round(pt[1] * 255))), .position = pt[0] / titlebar_edge_height };
    }
    n.style.ext.?.multi_gradient = core.MultiGradient.fromSlice(&stops, .vertical);
}

/// `W.TitlebarEdge` (Yix `<W.TitlebarEdge />`): `titlebarEdge` as a component. Put it in the
/// positioned container that holds the scrolling content, after the content and before the
/// toolbar / header, so it paints between them.
pub fn TitlebarEdge(props: anytype) TitlebarEdgeBuilder {
    return .{ .props = reactive.props.coerce(TitlebarEdgeProps, props) };
}

pub const TitlebarEdgeBuilder = struct {
    props: TitlebarEdgeProps,

    pub fn mount(self: TitlebarEdgeBuilder, scope: *Scope, cx: *Cx) !*Node {
        _ = scope;
        return titlebarEdge(cx, self.props);
    }
};

test "titlebarEdge: measured wash profile as a vertical gradient of the window background" {
    var ctx = try Cx.init(testing.allocator, std.testing.io);
    defer ctx.deinit();
    const n = try titlebarEdge(ctx, .{ .width = 640, .dark = false });
    defer ctx.freeNode(n);
    const g = n.style.ext.?.multi_gradient.?;
    try testing.expectEqual(@as(u8, 16), g.stop_count);
    try testing.expectEqual(@as(u8, 217), g.stops[0].color.a); // 0.85
    try testing.expectEqual(@as(u8, 249), g.stops[0].color.r);
    try testing.expectEqual(@as(u8, 0), g.stops[15].color.a);
    try testing.expectApproxEqAbs(@as(f32, 1), g.stops[15].position, 1e-6);
    const d = try titlebarEdge(ctx, .{ .dark = true });
    defer ctx.freeNode(d);
    try testing.expectEqual(@as(u8, 34), d.style.ext.?.multi_gradient.?.stops[0].color.r);
}

test "TitlebarEdge: follows theme switches unless `dark` is given; mounts from ui.view" {
    var ctx = try Cx.init(testing.allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setTheme(&core.theme.light);
    const root = try box(ctx, .{ .width = .{ .px = 640 }, .height = .{ .px = 400 }, .position = .relative }, .{});
    ctx.root = root;
    const scope = try Scope.init(testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const view = @import("../../view.zig");
    var themed: *Node = undefined;
    var pinned: *Node = undefined;
    try view.mount(scope, ctx, root, view.capture(&themed, TitlebarEdge(.{})));
    try view.mount(scope, ctx, root, view.capture(&pinned, TitlebarEdge(.{ .dark = false })));
    try testing.expectEqualStrings("TitlebarEdge", themed.meta.ownership.meta.component_name.?);
    try testing.expectEqual(@as(u8, 249), themed.style.ext.?.multi_gradient.?.stops[0].color.r);
    ctx.setTheme(&core.theme.dark);
    try testing.expectEqual(@as(u8, 34), themed.style.ext.?.multi_gradient.?.stops[0].color.r);
    try testing.expectEqual(@as(u8, 217), themed.style.ext.?.multi_gradient.?.stops[0].color.a);
    try testing.expectEqual(@as(u8, 249), pinned.style.ext.?.multi_gradient.?.stops[0].color.r);
    ctx.setTheme(&core.theme.light);
    try testing.expectEqual(@as(u8, 249), themed.style.ext.?.multi_gradient.?.stops[0].color.r);
}

/// Plate / icon as appearance (setBackground / setTint self-deduplicate).
fn refreshItem(it: *Item) void {
    it.plate.setBackground(it.ink(Item.plateColor));
    if (it.icon.setTint(it.ink(Item.iconColor))) it.icon.markRenderDirty();
}

pub fn GlassToolbar(props: anytype) GlassToolbarBuilder {
    return .{ .props = reactive.props.coerce(GlassToolbarProps, props) };
}

pub const GlassToolbarResult = struct {
    root: *Node,
    runtime: *GlassToolbarRuntime,

    /// `ui.view` / Yix `<W.GlassToolbar>`: children (`<W.GlassToolbarGroup>` elements, a
    /// `<spacer />`) go into the toolbar row after the `groups` built from props.
    pub fn viewParts(self: GlassToolbarResult) core.ViewParts {
        return .{ .root = self.root, .slot = self.root };
    }
};

pub const GlassToolbarBuilder = struct {
    props: GlassToolbarProps,

    pub fn mount(self: GlassToolbarBuilder, scope: *Scope, cx: *Cx) !GlassToolbarResult {
        const p = self.props;
        const my_scope = try scope.childScope();
        var bound = false;
        errdefer if (!bound) my_scope.dispose();
        const a = cx.allocator;

        const root = try box(cx, .{
            .width = .{ .grow = .{} },
            .height = .{ .px = bar_height },
            .direction = .row,
            .align_items = .center,
            .gap = p.spacing,
        }, .{});
        errdefer cx.freeNode(root);
        root.meta.ownership.meta.component_name = "GlassToolbar";
        if (p.test_id) |tid| root.meta.ownership.meta.test_id = tid;
        root.behavior.interaction.a11y = .{ .role = .group, .label = "Toolbar" };
        try core.bindScopeToNode(my_scope, root);
        bound = true;

        const rt = try my_scope.allocator.create(GlassToolbarRuntime);
        rt.* = .{ .cx = cx, .root = root };
        try my_scope.adoptResource(@ptrCast(rt), struct {
            fn cleanup(ptr: *anyopaque, alloc: Allocator) void {
                const r: *GlassToolbarRuntime = @ptrCast(@alignCast(ptr));
                for (r.items.items) |it| alloc.destroy(it);
                for (r.segmented.items) |seg| {
                    for (seg.test_ids) |tid| alloc.free(tid);
                    alloc.free(seg.test_ids);
                    alloc.free(seg.items);
                    alloc.free(seg.separators);
                    alloc.destroy(seg);
                }
                r.items.deinit(alloc);
                r.segmented.deinit(alloc);
                alloc.destroy(r);
            }
        }.cleanup);

        for (p.groups) |g| switch (g) {
            .flexible_space => _ = try core.adoptChild(cx, a, root, try box(cx, .{ .width = .{ .grow = .{} }, .height = .{ .px = 1 } }, .{})),
            .buttons => |buttons| {
                var w: f32 = 0;
                for (buttons) |b| w += b.width;
                const cap = try mountCapsule(my_scope, cx, root, w, buttons_end_pad);
                for (buttons) |b| {
                    const it = try mountItem(my_scope, cx, rt, cap, b.icon, b.width, .{ .button = b.on_click });
                    it.node.behavior.interaction.a11y = .{ .role = .button, .label = b.label };
                    if (b.test_id) |tid| it.node.meta.ownership.meta.test_id = tid;
                    try bindDisabled(my_scope, it, b.disabled);
                }
            },
            .segmented => |sp| {
                const n = sp.icons.len;
                const cap = try mountCapsule(my_scope, cx, root, sp.width * @as(f32, @floatFromInt(n)), segmented_end_pad);
                // seg taken by rt on creation (after any fail all cleaned by rt, no block errdefer
                // after,
                // else fails cleanup twice); slices per-item alloc, cleanup only free allocated
                // parts.
                const selected = try reactive.resolveModel(usize, my_scope, sp.selected);
                const seg = try my_scope.allocator.create(Segmented);
                seg.* = .{ .selected = selected, .on_change = sp.on_change };
                rt.segmented.append(my_scope.allocator, seg) catch |err| {
                    my_scope.allocator.destroy(seg);
                    return err;
                };
                seg.items = try my_scope.allocator.alloc(*Item, n);
                seg.separators = try my_scope.allocator.alloc(*Node, if (n > 0) n - 1 else 0);
                if (sp.test_id != null) {
                    seg.test_ids = try my_scope.allocator.alloc([]u8, n);
                    @memset(seg.test_ids, &.{});
                }
                cap.body.behavior.interaction.a11y = .{ .role = .radiogroup };
                for (sp.icons, 0..) |icon, i| {
                    const it = try mountItem(my_scope, cx, rt, cap, icon, sp.width, .{ .segment = .{ .group = seg, .index = i } });
                    seg.items[i] = it;
                    it.node.behavior.interaction.a11y = .{ .role = .radio, .label = if (i < sp.labels.len) sp.labels[i] else null, .checked = seg.selected.peek() == i };
                    if (sp.test_id) |tid| {
                        seg.test_ids[i] = try std.fmt.allocPrint(my_scope.allocator, "{s}.{d}", .{ tid, i });
                        it.node.meta.ownership.meta.test_id = seg.test_ids[i];
                    }
                    if (i + 1 < n) {
                        // 1x20 divider, vertically centered; horizontally at segment boundary right
                        // 0.5-1.5 pt
                        // (native 415-416 pt, boundary 414.5)
                        const sep = try core.adoptChild(cx, a, it.node, try box(cx, .{
                            .width = .{ .px = 1 },
                            .height = .{ .px = separator_height },
                            .position = .absolute,
                        }, .{}));
                        (try sep.style.ensureExtFallible(a)).inset = .{
                            .left = .{ .px = sp.width + 0.5 },
                            .top = .{ .px = (bar_height - separator_height) / 2 },
                        };
                        seg.separators[i] = sep;
                    }
                }
                try my_scope.createEffect(seg, struct {
                    fn run(s: *Segmented) void {
                        const v = s.selected.readAs(true);
                        for (s.items, 0..) |it, i| {
                            if (it.node.behavior.interaction.a11y) |*a11y| a11y.checked = v == i;
                            it.node.markRenderDirty();
                        }
                        if (s.items.len > 0) s.items[0].cx.needs_redraw = true;
                    }
                }.run);
            },
        };

        root.meta.per_frame.hooks.before_render.main = toolbarBeforeRender;
        // refresh() writes plates / icons / separators through setBackground / setTint +
        // markRenderDirty only: descendants stay cacheable (audited in Debug).
        root.frame_state.state_bits.flags.before_render_hook_descendants_cache_safe = true;
        root.behavior.events.event_context = @ptrCast(rt);
        rt.refresh();
        return .{ .root = root, .runtime = rt };
    }
};

/// One group glass capsule: regular, 36 pt tall, content horizontal, ends padded end_pad.
/// Return body to place items and glass state.
fn mountCapsule(scope: *Scope, cx: *Cx, parent: *Node, content_width: f32, end_pad: f32) !glass_box.GlassBoxMount {
    const g = try glass_box.GlassBox(.{
        .width = content_width + 2 * end_pad,
        .height = bar_height,
        .shape = .capsule,
        .corner_radius = bar_height / 2,
        .padding = .{ .left = end_pad, .right = end_pad },
        .body_gap = 0,
    }).mountWithState(scope, cx);
    _ = try core.adoptChild(cx, cx.allocator, parent, g.box);
    g.body.style.direction = .row;
    g.body.style.height = .{ .grow = .{} };
    return g;
}

fn mountItem(scope: *Scope, cx: *Cx, rt: *GlassToolbarRuntime, cap: glass_box.GlassBoxMount, icon: svg_assets.Asset, width: f32, kind: @FieldType(Item, "kind")) !*Item {
    const node = try core.adoptChild(cx, cx.allocator, cap.body, try itemNode(cx, icon, width));
    // All possible fail steps before creating Item; once in rt.items belongs to rt cleanup
    // (can't errdefer after, else later fail cleanup twice--OOM sweep measured)
    const it = try scope.allocator.create(Item);
    it.* = .{ .cx = cx, .glass = cap.state, .node = node, .plate = node.children.items[0], .icon = node.children.items[1], .width = width, .kind = kind };
    rt.items.append(scope.allocator, it) catch |err| {
        scope.allocator.destroy(it);
        return err;
    };
    attachItemEvents(it);
    return it;
}

fn attachItemEvents(it: *Item) void {
    const node = it.node;
    node.behavior.events.event_context = @ptrCast(it);
    node.behavior.events.on_event = itemEvent;
    node.on_capture_lost = itemCaptureLost;
}

/// Disabled source of a button: a11y and cursor now, and again whenever a dynamic source changes
/// (the per-frame refresh repaints icon and plate).
fn bindDisabled(scope: *Scope, it: *Item, disabled: Source(bool)) !void {
    it.disabled = disabled;
    applyDisabled(it, disabled.peek());
    if (disabled.isStatic()) return;
    try scope.createEffect(it, struct {
        fn run(item: *Item) void {
            applyDisabled(item, item.disabled.get());
            item.cx.needs_redraw = true;
        }
    }.run);
}

fn applyDisabled(it: *Item, disabled: bool) void {
    if (it.node.behavior.interaction.a11y) |*a| a.disabled = disabled;
    if (disabled) {
        it.hovered = false;
        it.pressed = false;
        it.inside = false;
    }
    it.node.markRenderDirty();
}

/// Item node: fixed-width cell with the centered backplate (child 0) and icon (child 1).
fn itemNode(cx: *Cx, icon: svg_assets.Asset, width: f32) !*Node {
    const a = cx.allocator;
    const node = try box(cx, .{
        .width = .{ .px = width },
        .height = .{ .px = bar_height },
        .position = .relative,
        .justify = .center,
        .align_items = .center,
    }, .{});
    errdefer cx.freeNode(node);
    const plate = try core.adoptChild(cx, a, node, try box(cx, .{
        .width = .{ .px = plate_width },
        .height = .{ .px = plate_height },
        .position = .absolute,
        .background = Color.rgba(0, 0, 0, 0),
    }, .{}));
    const ext = try plate.style.ensureExtFallible(a);
    ext.inset = .{ .left = .{ .px = (width - plate_width) / 2 }, .top = .{ .px = (bar_height - plate_height) / 2 } };
    ext.corner_radius = core.CornerRadius.uniform(plate_height / 2);
    plate.style.border = .{ .overlay = true, .width = 0, .color = Color.rgba(0, 0, 0, 0), .radius = plate_height / 2 };
    _ = try core.adoptChild(cx, a, node, try iconNode(cx, icon));
    node.style.cursor = .default;
    (try node.style.ensureExtFallible(a)).hit_roles = .{ .pointer = true };
    return node;
}

fn iconNode(cx: *Cx, icon: svg_assets.Asset) !*Node {
    return core.iconTint(cx, icon, light_palette.ink.withAlpha(light_palette.icon_active), .{
        .width = .{ .px = icon_size },
        .height = .{ .px = icon_size },
    });
}

fn toolbarBeforeRender(node: *Node) void {
    const rt: *GlassToolbarRuntime = @ptrCast(@alignCast(node.behavior.events.event_context orelse return));
    rt.refresh();
}

fn ownsCapture(cx: *Cx, node: *Node) bool {
    return cx.node_registry.resolve(cx.dispatcher.pointer_capture_handle, null) == node;
}

fn pointInside(it: *const Item, x: f32, y: f32) bool {
    const g = it.node.globalRect();
    return x >= g.x and x < g.x + g.w and y >= g.y and y < g.y + g.h;
}

fn itemCaptureLost(node: *Node) void {
    const it: *Item = @ptrCast(@alignCast(node.behavior.events.event_context orelse return));
    if (!it.pressed) return;
    it.pressed = false;
    it.inside = false;
    // Capture stolen: no coords to check if pointer still in item, capture period enter/leave
    // not guaranteed to re-send--prefer one fewer hover highlight, never leave backplate always lit
    // (next true enter resets)
    it.hovered = false;
    it.cx.needs_redraw = true;
}

fn itemEvent(event: Event, context: ?*anyopaque) EventResult {
    const it: *Item = @ptrCast(@alignCast(context orelse return .ignored));
    const cx = it.cx;
    switch (event) {
        .mouse_enter => {
            it.hovered = true;
            cx.needs_redraw = true;
            return .ignored;
        },
        .mouse_leave => {
            it.hovered = false;
            cx.needs_redraw = true;
            return .ignored;
        },
        .mouse_down => |e| {
            if (e.button != .left) return .ignored;
            // A disabled item takes the press (nothing behind it reacts) and does nothing.
            if (it.isDisabled()) return .stop;
            const identity = cx.node_registry.handleFor(it.node);
            cx.setPointerCapture(it.node);
            const live = cx.node_registry.resolve(identity, null) orelse return .stop;
            if (live.behavior.events.event_context != context or live.behavior.events.on_event != itemEvent) return .stop;
            if (!ownsCapture(cx, it.node)) return .stop;
            it.pressed = true;
            it.inside = true;
            cx.needs_redraw = true;
            return .stop;
        },
        .mouse_move => |e| {
            if (it.pressed and !ownsCapture(cx, it.node)) itemCaptureLost(it.node);
            if (!it.pressed) return .ignored;
            const inside = pointInside(it, e.x, e.y);
            if (inside != it.inside) {
                it.inside = inside;
                it.hovered = inside;
                cx.needs_redraw = true;
            }
            return .stop;
        },
        .mouse_up => |e| {
            // Another button released while the left is held is not this item's release.
            if (e.button != .left or !it.pressed) return .ignored;
            const inside = pointInside(it, e.x, e.y);
            it.pressed = false;
            it.inside = false;
            it.hovered = inside;
            if (ownsCapture(cx, it.node)) cx.releasePointerCapture();
            cx.needs_redraw = true;
            if (!inside or it.isDisabled()) return .stop;
            // Last step: callback may destroy this control, don't visit it after
            switch (it.kind) {
                .button => |h| if (h) |handler| handler.invoke(),
                .segment => |s| s.group.select(s.index),
            }
            return .stop;
        },
        else => return .ignored,
    }
}

// ============================================================================
// Template form: <W.GlassToolbarGroup> with <W.GlassToolbarButton> children
// ============================================================================

/// One toolbar capsule as an element (Yix):
///   <W.GlassToolbarGroup testId="nav.history">
///       <W.GlassToolbarButton icon={ui.icons.chevron_left} label="Back" disabled={!canBack(vm)} onClick={back(vm)} />
///       <W.GlassToolbarButton icon={ui.icons.chevron_right} label="Forward" disabled={!canForward(vm)} onClick={forward(vm)} />
///   </W.GlassToolbarGroup>
/// Same capsule as a `.buttons` group (36 pt regular glass, 1 pt end padding), its width fits the
/// buttons. Works inside `<W.GlassToolbar>` or on its own (a header row).
pub const GlassToolbarGroupProps = struct {
    /// Accessibility name of the group (null = none).
    label: ?[]const u8 = null,
};

pub fn GlassToolbarGroup(props: anytype) GlassToolbarGroupBuilder {
    return .{ .props = reactive.props.coerce(GlassToolbarGroupProps, props) };
}

pub const GlassToolbarGroupBuilder = struct {
    props: GlassToolbarGroupProps,

    pub fn mount(self: GlassToolbarGroupBuilder, scope: *Scope, cx: *Cx) !GlassToolbarGroupResult {
        const g = try glass_box.GlassBox(.{
            .height = bar_height,
            .shape = .capsule,
            .corner_radius = bar_height / 2,
            .padding = .{ .left = buttons_end_pad, .right = buttons_end_pad },
            .body_gap = 0,
        }).mountWithState(scope, cx);
        g.box.meta.ownership.meta.component_name = "GlassToolbarGroup";
        // The capsule keeps its fitted width in a stretching parent.
        (try g.box.style.ensureExtFallible(cx.allocator)).no_cross_stretch = true;
        g.body.style.direction = .row;
        g.body.style.height = .{ .grow = .{} };
        g.body.behavior.interaction.a11y = .{ .role = .group, .label = self.props.label };
        return .{ .glass = g };
    }
};

pub const GlassToolbarGroupResult = struct {
    glass: glass_box.GlassBoxMount,

    pub fn viewParts(self: GlassToolbarGroupResult) core.ViewParts {
        return .{ .root = self.glass.box, .slot = self.glass.body };
    }
};

/// One toolbar button as an element; every visual prop but `width` follows its source.
pub const GlassToolbarButtonProps = struct {
    icon: Source(svg_assets.Asset),
    /// Accessibility name
    label: Source([]const u8) = .{ .value = "" },
    /// Dimmed icon, no hover / press plate, clicks ignored, a11y disabled.
    disabled: Source(bool) = .{ .value = false },
    on_click: ?Handler(void) = null,
    width: f32 = button_width,
};

pub fn GlassToolbarButton(props: anytype) GlassToolbarButtonBuilder {
    return .{ .props = reactive.props.coerce(GlassToolbarButtonProps, props) };
}

pub const GlassToolbarButtonBuilder = struct {
    props: GlassToolbarButtonProps,

    pub fn mount(self: GlassToolbarButtonBuilder, scope: *Scope, cx: *Cx) !*Node {
        const p = self.props;
        const my_scope = try scope.childScope();
        var bound = false;
        errdefer if (!bound) my_scope.dispose();
        const node = try itemNode(cx, p.icon.peek(), p.width);
        errdefer cx.freeNode(node);
        node.meta.ownership.meta.component_name = "GlassToolbarButton";
        node.behavior.interaction.a11y = .{ .role = .button, .label = p.label.peek() };
        try core.bindScopeToNode(my_scope, node);
        bound = true;

        const it = try my_scope.allocator.create(Item);
        it.* = .{ .cx = cx, .glass = null, .node = node, .plate = node.children.items[0], .icon = node.children.items[1], .icon_svg = p.icon.peek().svg_data.ptr, .width = p.width, .kind = .{ .button = p.on_click } };
        try my_scope.adoptResource(@ptrCast(it), struct {
            fn destroy(ptr: *anyopaque, alloc: Allocator) void {
                alloc.destroy(@as(*Item, @ptrCast(@alignCast(ptr))));
            }
        }.destroy);
        attachItemEvents(it);
        try bindDisabled(my_scope, it, p.disabled);
        if (!p.label.isStatic()) try my_scope.createEffect(LabelBinding{ .item = it, .label = p.label }, LabelBinding.run);
        if (!p.icon.isStatic()) try my_scope.createEffect(IconBinding{ .item = it, .icon = p.icon }, IconBinding.run);

        node.meta.per_frame.hooks.before_render.main = buttonBeforeRender;
        // Like the toolbar hook: plate / icon writes are dirty-marking setters only.
        node.frame_state.state_bits.flags.before_render_hook_descendants_cache_safe = true;
        refreshItem(it);
        return node;
    }
};

const LabelBinding = struct {
    item: *Item,
    label: Source([]const u8),

    fn run(self: LabelBinding) void {
        const text = self.label.get();
        if (self.item.node.behavior.interaction.a11y) |*a| a.label = text;
        self.item.node.markRenderDirty();
    }
};

/// A changed icon source rebuilds the icon node in place (child 1).
const IconBinding = struct {
    item: *Item,
    icon: Source(svg_assets.Asset),

    fn run(self: IconBinding) void {
        const asset = self.icon.get();
        const it = self.item;
        if (it.icon_svg == asset.svg_data.ptr) return;
        const cx = it.cx;
        const fresh = iconNode(cx, asset) catch {
            std.log.warn("GlassToolbarButton: icon change dropped (out of memory)", .{});
            return;
        };
        it.node.insertChildBefore(cx.allocator, fresh, it.icon) catch {
            cx.freeNode(fresh);
            std.log.warn("GlassToolbarButton: icon change dropped (out of memory)", .{});
            return;
        };
        const old = it.icon;
        cx.detachChild(it.node, old);
        cx.freeNode(old);
        it.icon = fresh;
        it.icon_svg = asset.svg_data.ptr;
        refreshItem(it);
        it.node.markLayoutDirty();
        cx.needs_redraw = true;
    }
};

/// Per frame: find the capsule the button sits in (first frame on the tree), then paint.
fn buttonBeforeRender(node: *Node) void {
    const it: *Item = @ptrCast(@alignCast(node.behavior.events.event_context orelse return));
    if (it.glass == null) it.glass = enclosingGlass(node);
    refreshItem(it);
}

fn enclosingGlass(node: *Node) ?*glass_box.AdaptiveGlassBoxState {
    var cur = node.parent;
    while (cur) |n| : (cur = n.parent) {
        const name = n.meta.ownership.meta.component_name orelse continue;
        if (std.mem.eql(u8, name, "GlassToolbarGroup") or std.mem.eql(u8, name, "GlassBox")) {
            const raw = n.meta.per_frame.hooks.slots.anim_state orelse return null;
            return @ptrCast(@alignCast(raw));
        }
    }
    return null;
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;
const icons = @import("zenit_system_icons");

test "GlassToolbar: plate alphas add up (selected + hover / press) and switch within one frame" {
    var ctx = try Cx.init(testing.allocator, std.testing.io);
    defer ctx.deinit();
    // Light appearance: test Cx default dark theme, but new glass starts from appearance
    // matching family (measured on native)
    ctx.tokens = &core.theme.light;
    const root = try box(ctx, .{ .width = .{ .px = 600 }, .height = .{ .px = 80 } }, .{});
    ctx.root = root;
    const scope = try Scope.init(testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const groups = [_]ToolbarGroup{
        .{ .buttons = &[_]ToolbarButton{ .{ .icon = icons.home, .label = "Sidebar" }, .{ .icon = icons.upload, .label = "Share" } } },
        .{ .segmented = .{ .icons = &[_]svg_assets.Asset{ icons.more_horizontal, icons.settings, icons.calendar }, .test_id = "t.view" } },
    };
    const tb = try GlassToolbar(.{ .groups = &groups }).mount(scope, ctx);
    try root.appendChild(testing.allocator, tb.root);
    ctx.layout();
    const rt = tb.runtime;
    try testing.expectEqual(@as(usize, 5), rt.items.items.len);
    const btn = rt.items.items[0];
    const seg0 = rt.items.items[2];
    const seg1 = rt.items.items[3];
    try testing.expectEqual(@as(u8, 0), btn.plateAlpha());
    try testing.expectEqual(light_palette.plate_selected, seg0.plateAlpha()); // Default selected segment 0
    _ = itemEvent(.mouse_enter, btn);
    try testing.expectEqual(light_palette.plate_hover, btn.plateAlpha());
    _ = itemEvent(.mouse_enter, seg0);
    try testing.expectEqual(light_palette.plate_selected + light_palette.plate_hover, seg0.plateAlpha());
    // Press segment 1: press backplate, release in segment -> selected jump to segment 1
    const g1 = seg1.node.globalRect();
    _ = itemEvent(.{ .mouse_down = .{ .x = g1.x + 4, .y = g1.y + 4 } }, seg1);
    try testing.expectEqual(light_palette.plate_press, seg1.plateAlpha());
    _ = itemEvent(.{ .mouse_up = .{ .x = g1.x + 4, .y = g1.y + 4 } }, seg1);
    try testing.expectEqual(@as(usize, 1), rt.segmented.items[0].selected.peek());
    rt.refresh();
    try testing.expectEqual(light_palette.plate_selected + light_palette.plate_hover, seg1.plateAlpha());
    try testing.expectEqual(light_palette.plate_hover, seg0.plateAlpha());
    // Divider: both sides hidden when segment 1 selected
    const seps = rt.segmented.items[0].separators;
    try testing.expectEqual(@as(u8, 0), seps[0].getBackground().a);
    try testing.expectEqual(@as(u8, 0), seps[1].getBackground().a);
    // Drag out of segment release: no trigger
    const g2 = rt.items.items[4].node.globalRect();
    _ = itemEvent(.{ .mouse_down = .{ .x = g2.x + 4, .y = g2.y + 4 } }, rt.items.items[4]);
    _ = itemEvent(.{ .mouse_move = .{ .x = g2.x - 200, .y = g2.y + 4 } }, rt.items.items[4]);
    try testing.expectEqual(@as(u8, 0), rt.items.items[4].plateAlpha());
    _ = itemEvent(.{ .mouse_up = .{ .x = g2.x - 200, .y = g2.y + 4 } }, rt.items.items[4]);
    try testing.expectEqual(@as(usize, 1), rt.segmented.items[0].selected.peek());
    // Unfocus: icon ink 70% -> 28.5%
    ctx.window_active = false;
    rt.refresh();
    try testing.expectEqual(light_palette.icon_inactive, btn.icon.getIcon().?.tint.a);
    // Dark family: stack white, selected+hover = 39 + 22
    glass_box.glassSetFamilyImmediate(seg1.glass.?, true);
    try testing.expectEqual(dark_palette.plate_selected + dark_palette.plate_hover, seg1.plateAlpha());
    rt.refresh();
    try testing.expectEqual(@as(u8, 255), seg1.plate.getBackground().r);
    try testing.expectEqual(dark_palette.icon_inactive, seg1.icon.getIcon().?.tint.a);
}

test "GlassToolbar: mount OOM sweep (every allocation failure path frees exactly once)" {
    // Segment assembly fail mid-way cleanup seg twice (block errdefer + rt cleanup);
    // inject fail per alloc, GPA judge leak
    try @import("../oom_sweep.zig").sweepMount("glass_toolbar", struct {
        fn mount(scope: *Scope, cx: *Cx) anyerror!?*Node {
            const groups = [_]ToolbarGroup{
                .{ .buttons = &[_]ToolbarButton{ .{ .icon = icons.home }, .{ .icon = icons.upload } } },
                .{ .segmented = .{ .icons = &[_]svg_assets.Asset{ icons.more_horizontal, icons.settings, icons.calendar }, .test_id = "t.view" } },
                .flexible_space,
            };
            return (try GlassToolbar(.{ .groups = &groups }).mount(scope, cx)).root;
        }
    }.mount);
}

test "GlassToolbar: disabled button dims its icon, shows no plate, ignores clicks and follows its source" {
    var ctx = try Cx.init(testing.allocator, std.testing.io);
    defer ctx.deinit();
    ctx.tokens = &core.theme.light;
    const root = try box(ctx, .{ .width = .{ .px = 600 }, .height = .{ .px = 80 } }, .{});
    ctx.root = root;
    const scope = try Scope.init(testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const Counter = struct {
        n: usize = 0,
        fn hit(self: *@This()) void {
            self.n += 1;
        }
    };
    var counter: Counter = .{};
    const off = try scope.createSignal(bool, true);
    const groups = [_]ToolbarGroup{
        .{ .buttons = &[_]ToolbarButton{
            .{ .icon = icons.home, .label = "Back", .disabled = .{ .signal = off }, .on_click = Cx.handlerFrom(Counter, &counter, Counter.hit) },
            .{ .icon = icons.upload, .label = "Share" },
        } },
    };
    const tb = try GlassToolbar(.{ .groups = &groups }).mount(scope, ctx);
    try root.appendChild(testing.allocator, tb.root);
    ctx.layout();
    const back = tb.runtime.items.items[0];
    const share = tb.runtime.items.items[1];
    tb.runtime.refresh();
    try testing.expect(back.node.behavior.interaction.a11y.?.disabled);
    try testing.expect(!share.node.behavior.interaction.a11y.?.disabled);
    try testing.expectEqual(light_palette.icon_disabled, back.icon.getIcon().?.tint.a);
    try testing.expectEqual(light_palette.icon_active, share.icon.getIcon().?.tint.a);
    const g = back.node.globalRect();
    _ = itemEvent(.mouse_enter, back);
    try testing.expectEqual(@as(u8, 0), back.plateAlpha());
    try testing.expectEqual(EventResult.stop, itemEvent(.{ .mouse_down = .{ .x = g.x + 4, .y = g.y + 4 } }, back));
    _ = itemEvent(.{ .mouse_up = .{ .x = g.x + 4, .y = g.y + 4 } }, back);
    try testing.expectEqual(@as(usize, 0), counter.n);
    // Enabled again: full ink, hover plate, click lands.
    off.set(false);
    tb.runtime.refresh();
    try testing.expect(!back.node.behavior.interaction.a11y.?.disabled);
    try testing.expectEqual(light_palette.icon_active, back.icon.getIcon().?.tint.a);
    _ = itemEvent(.mouse_enter, back);
    try testing.expectEqual(light_palette.plate_hover, back.plateAlpha());
    _ = itemEvent(.{ .mouse_down = .{ .x = g.x + 4, .y = g.y + 4 } }, back);
    _ = itemEvent(.{ .mouse_up = .{ .x = g.x + 4, .y = g.y + 4 } }, back);
    try testing.expectEqual(@as(usize, 1), counter.n);
}

test "GlassToolbarGroup / GlassToolbarButton: element form mounts a fitted capsule; label, icon and disabled follow sources" {
    var ctx = try Cx.init(testing.allocator, std.testing.io);
    defer ctx.deinit();
    ctx.tokens = &core.theme.light;
    const root = try box(ctx, .{ .width = .{ .px = 600 }, .height = .{ .px = 80 }, .direction = .row, .align_items = .center }, .{});
    ctx.root = root;
    const scope = try Scope.init(testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const view = @import("../../view.zig");
    const off = try scope.createSignal(bool, true);
    const name = try scope.createSignal([]const u8, "Back");
    const glyph = try scope.createSignal(svg_assets.Asset, icons.home);
    var group: GlassToolbarGroupResult = undefined;
    var back_node: *Node = undefined;
    try view.mount(scope, ctx, root, view.capture(&group, view.with(GlassToolbarGroup(.{ .label = "History" }), .{
        view.capture(&back_node, GlassToolbarButton(.{ .icon = glyph, .label = name, .disabled = off })),
        GlassToolbarButton(.{ .icon = icons.upload, .label = "Forward" }),
    })));
    ctx.layout();
    try testing.expectEqualStrings("GlassToolbarGroup", group.glass.box.meta.ownership.meta.component_name.?);
    // Two 38 pt items + 1 pt at each end, 36 tall (the `.buttons` group capsule).
    try testing.expectApproxEqAbs(@as(f32, 2 * button_width + 2 * buttons_end_pad), group.glass.box.rectFromWorldOrFallback().w, 0.5);
    try testing.expectApproxEqAbs(bar_height, group.glass.box.rectFromWorldOrFallback().h, 0.5);
    const it: *Item = @ptrCast(@alignCast(back_node.behavior.events.event_context.?));
    buttonBeforeRender(back_node);
    try testing.expect(it.glass == group.glass.state);
    try testing.expect(back_node.behavior.interaction.a11y.?.disabled);
    try testing.expectEqual(light_palette.icon_disabled, it.icon.getIcon().?.tint.a);
    off.set(false);
    buttonBeforeRender(back_node);
    try testing.expect(!back_node.behavior.interaction.a11y.?.disabled);
    try testing.expectEqual(light_palette.icon_active, it.icon.getIcon().?.tint.a);
    name.set("Previous page");
    try testing.expectEqualStrings("Previous page", back_node.behavior.interaction.a11y.?.label.?);
    const before = it.icon;
    glyph.set(icons.settings);
    try testing.expect(it.icon != before);
    try testing.expectEqual(@as(usize, 2), back_node.children.items.len);
    try testing.expect(back_node.children.items[1] == it.icon);
    glyph.set(icons.settings);
    try testing.expect(back_node.children.items[1] == it.icon);
}

test "GlassToolbarButton: mount OOM sweep" {
    try @import("../oom_sweep.zig").sweepMount("glass_toolbar_button", struct {
        fn mount(scope: *Scope, cx: *Cx) anyerror!?*Node {
            const off = try scope.createSignal(bool, false);
            const name = try scope.createSignal([]const u8, "Back");
            return try GlassToolbarButton(.{ .icon = icons.home, .label = name, .disabled = off }).mount(scope, cx);
        }
    }.mount);
}
