//! One window-space material below every foreground control. Terminals reveal
//! this same layer, so their image scale, alignment and tile phase cannot drift.
const std = @import("std");
const ui = @import("ui");
const material = @import("../../../config/background_asset.zig");
const geometry = @import("../../../config/background_geometry.zig");
const repeat = @import("../model/background_repeat.zig");
pub const Image = struct { id: u32, width: u32, height: u32, repeating: ?repeat.Texture = null };
const theme = @import("../../../shared/ui/theme/app_theme.zig");
const joined = ui.widgets.joined_surface;
const tab_styles = @import("../../workspace/mod.zig").workspace_tab_styles;

/// Compatibility for foreground rebuilders: global material has no surface nodes.
pub fn isSurface(_: *const ui.Node) bool {
    return false;
}

/// One split member inside the island: its node (rect and nothing else is read) and whether it
/// is the focused member (focus island with the accent hairline) or a rest island.
pub const GroupMember = struct { node: *ui.Node, focused: bool };
/// The split's owner lists the members shown now (none when no split is shown).
pub const GroupSource = struct {
    ctx: *anyopaque,
    members: *const fn (ctx: *anyopaque, out: *std.ArrayList(GroupMember), allocator: std.mem.Allocator) anyerror!void,
};

pub const View = struct {
    cx: *ui.Cx,
    root: *ui.Node,
    images: *ui.Node,
    blur: *ui.Node,
    veil: *ui.Node,
    tiles: std.ArrayList(*ui.Node) = .empty,
    group_paints: std.ArrayList(*ui.Node) = .empty,
    fingerprint: ?u64 = null,
    /// The focused view island and its active tab share one plate in the canvas tint group.
    island: ?*ui.Node = null,
    island_surface: ?*joined.Surface = null,
    /// The split shown inside the island, when its owner bound one (`bindGroup`).
    group: ?GroupSource = null,
    group_members: std.ArrayList(GroupMember) = .empty,

    pub fn mount(cx: *ui.Cx, scope: *ui.Scope) !*View {
        const self = try cx.allocator.create(View);
        errdefer cx.allocator.destroy(self);
        const root = try ui.box(cx, layer(), .{});
        root.meta.ownership.meta.test_id = "appearance.background";
        root.setStyleInline(cx.allocator, .{ .overflow = .hidden, .background = theme.baseColors().app });
        const images = try ui.box(cx, layer(), .{});
        const blur = try ui.box(cx, layer(), .{});
        const veil = try ui.box(cx, layer(), .{});
        try root.appendChild(cx.allocator, images);
        try root.appendChild(cx.allocator, blur);
        try root.appendChild(cx.allocator, veil);
        images.setDisplay(.none);
        blur.setDisplay(.none);
        veil.setDisplay(.none);
        self.* = .{ .cx = cx, .root = root, .images = images, .blur = blur, .veil = veil };
        try scope.onCleanup(View, self, cleanup);
        try cx.addAfterLayoutHook(self, syncShell);
        return self;
    }

    /// The island and active tab provide the geometry; all their paint belongs to this layer.
    pub fn bindIsland(self: *View, scope: *ui.Scope, source: *ui.Node, active_tab: ?*ui.Signal(joined.Target)) !void {
        std.debug.assert(self.island == null);
        const panel = try joined.targetOf(self.cx, source);
        const island_radius = source.style.effectiveRadius();
        const tab_radius = tab_styles.attachedRadius(island_radius);
        const panel_member: joined.Member = .{ .target = panel, .radii = @splat(island_radius) };
        const tab_radii: [4]f32 = .{ tab_radius, tab_radius, 0, 0 };
        const fill = try ui.box(self.cx, layer(), .{});
        self.veil.appendChild(self.cx.allocator, fill) catch |err| {
            self.cx.destroyDetached(fill);
            return err;
        };
        fill.meta.ownership.meta.test_id = "appearance.canvas.card";
        fill.setDisplay(.none);
        const plate = try joined.attach(scope, self.cx, fill, .{
            .members = &.{
                .{ .target = if (active_tab) |tab| tab.peek() else .none, .radii = tab_radii },
                panel_member,
            },
            .join_radius = tab_radius,
        });
        if (active_tab) |tab| {
            try scope.createEffect(.{ .plate = plate, .tab = tab, .tab_radii = tab_radii, .panel = panel_member }, struct {
                fn update(ctx: anytype) void {
                    const active = ctx.tab.get();
                    ctx.plate.setMembers(&.{
                        .{ .target = active, .radii = ctx.tab_radii },
                        ctx.panel,
                    }) catch |err| std.log.err("Could not update island surface: {}", .{err});
                }
            }.update);
        }
        self.island = source;
        self.island_surface = plate;
    }
    /// The split members whose plates this layer paints, given by the split's owner (the
    /// workspace). The layer never looks for them in the tree.
    pub fn bindGroup(self: *View, source: GroupSource) void {
        self.group = source;
    }
    fn syncShell(raw: *anyopaque, _: u8, _: bool) ui.AfterLayoutResult {
        const self: *View = @ptrCast(@alignCast(raw));
        const origin = self.veil.globalRect();
        var needs_layout = false;
        self.group_members.clearRetainingCapacity();
        if (self.group) |source| source.members(source.ctx, &self.group_members, self.cx.allocator) catch {};
        const panes = &self.group_members;
        while (self.group_paints.items.len < panes.items.len) {
            const fill = ui.box(self.cx, .{ .position = .absolute, .hit_behavior = .pass_through }, .{}) catch break;
            self.veil.appendChild(self.cx.allocator, fill) catch break;
            self.group_paints.append(self.cx.allocator, fill) catch break;
        }
        for (self.group_paints.items, 0..) |fill, i| {
            const visible = i < panes.items.len;
            if ((fill.style.display != .none) != visible) {
                fill.setDisplay(if (visible) .flex else .none);
                needs_layout = true;
            }
            if (!visible) continue;
            const rect = panes.items[i].node.globalRect();
            const old = fill.globalRect();
            if (@abs(old.x - rect.x) > 0.01 or @abs(old.y - rect.y) > 0.01 or @abs(old.w - rect.w) > 0.01 or @abs(old.h - rect.h) > 0.01) {
                fill.setStyleInline(self.cx.allocator, .{ .width = .{ .px = rect.w }, .height = .{ .px = rect.h }, .inset = .{ .left = .{ .px = rect.x - origin.x }, .top = .{ .px = rect.y - origin.y } } });
                needs_layout = true;
            }
            // Island B v3 split panes: the focused member is a focus island with
            // an accent hairline; the others are rest islands (radius 8).
            const focused = panes.items[i].focused;
            const base = theme.baseColors();
            const plate = (if (focused) base.surface_1 else base.surface_2).withAlpha(255);
            const border: ui.Border = .{ .width = if (focused) 1 else 0, .color = base.accent.withAlpha(102), .radius = @import("../../workspace/view/group_workspace_styles.zig").pane_radius };
            if (!ui.Color.eql(fill.getBackground(), plate)) fill.setBackground(plate);
            if (!std.meta.eql(fill.style.border, border)) {
                fill.setStyleInline(self.cx.allocator, .{ .border = border });
                needs_layout = true;
            }
        }
        if (self.island) |source| {
            const fill = self.island_surface.?.node;
            const rect = source.globalRect();
            const visible = source.isDisplayedInTree() and rect.w > 0 and rect.h > 0;
            if ((fill.style.display != .none) != visible) {
                fill.setDisplay(if (visible) .flex else .none);
                needs_layout = true;
            }
            if (visible) {
                const base = theme.baseColors();
                const color = base.surface_1.withAlpha(255);
                const border: ui.Border = .{ .width = 1, .color = base.border, .overlay = true };
                if (!ui.Color.eql(fill.getBackground(), color)) fill.setBackground(color);
                if (!std.meta.eql(fill.style.border, border)) fill.setStyleInline(self.cx.allocator, .{ .border = border });
            }
        }
        return if (needs_layout) .needs_layout else .done;
    }

    /// Called at the host's safe point. Only decoded/uploaded resources enter;
    /// it never reads a file, changes settings or creates a second image fit.
    pub fn update(self: *View, texture: ?Image, materials: material.Materials, width: f32, height: f32) !void {
        try self.paint(texture, materials, width, height);
    }

    fn paint(self: *View, texture: ?Image, materials: material.Materials, width: f32, height: f32) !void {
        try materials.validate();
        const background = materials.background;
        var hash = std.hash.Wyhash.init(0);
        std.hash.autoHash(&hash, .{ if (texture) |image| image.id else @as(u32, 0), if (texture) |image| image.width else @as(u32, 0), if (texture) |image| image.height else @as(u32, 0), if (texture) |image| image.repeating else null, background.enabled, @as(u32, @bitCast(width)), @as(u32, @bitCast(height)), background.fit, background.alignment_x, background.alignment_y, @as(u32, @bitCast(background.transparency)), materials.blur_px, theme.baseColors().app });
        const fingerprint = hash.final();
        if (self.fingerprint == fingerprint) return;
        // Apply the one canvas alpha only when effective material changes.
        self.veil.setStyleInline(self.cx.allocator, .{ .composited_group = true, .opacity = 1 - background.alpha(), .background = theme.baseColors().app.withAlpha(255) });
        if (!background.enabled or texture == null) {
            self.root.setBackground(theme.baseColors().app);
            self.root.setDisplay(.flex);
            self.images.setDisplay(.none);
            self.blur.setDisplay(.none);
            self.veil.setDisplay(.flex);
            self.fingerprint = fingerprint;
            return;
        }
        const image = texture.?;
        const transform = try geometry.resolve(.{ .source = .{ .pixel_width = image.width, .pixel_height = image.height }, .window = .{ .width = width, .height = height }, .fit = background.fit, .horizontal = background.alignment_x, .vertical = background.alignment_y });
        var rect = transform.image;
        var texture_id = image.id;
        if (transform.repeats) if (image.repeating) |repeating| {
            if (repeating.width < image.width or repeating.height < image.height or repeating.width % image.width != 0 or repeating.height % image.height != 0) return error.InvalidRepeatingTexture;
            // Preserve the original alignment phase; only the integer period
            // gets larger. Other fit modes continue drawing the source image.
            rect.width *= @as(f64, @floatFromInt(repeating.width / image.width));
            rect.height *= @as(f64, @floatFromInt(repeating.height / image.height));
            texture_id = repeating.id;
        };
        const tiled = if (transform.repeats) try repeat.grid(width, height, rect.x, rect.y, rect.width, rect.height) else null;
        const first_x = if (tiled) |value| value.first_x else rect.x;
        const first_y = if (tiled) |value| value.first_y else rect.y;
        const cols = if (tiled) |value| value.cols else 1;
        const count = if (tiled) |value| value.count else 1;
        try self.tiles.ensureTotalCapacity(self.cx.allocator, count);
        while (self.tiles.items.len < count) {
            const node = try ui.image(self.cx, texture_id, .{ .position = .absolute, .flex_shrink = 0 });
            errdefer self.cx.destroyDetached(node);
            try self.images.appendChild(self.cx.allocator, node);
            self.tiles.appendAssumeCapacity(node);
        }
        for (self.tiles.items, 0..) |node, index| {
            node.setDisplay(if (index < count) .flex else .none);
            if (index >= count) continue;
            const col = index % cols;
            const row = index / cols;
            node.setImage(.{ .texture_id = texture_id });
            node.setStyleInline(self.cx.allocator, .{ .position = .absolute, .width = .{ .px = @floatCast(rect.width) }, .height = .{ .px = @floatCast(rect.height) }, .inset = .{ .left = .{ .px = @floatCast(first_x + @as(f64, @floatFromInt(col)) * rect.width) }, .top = .{ .px = @floatCast(first_y + @as(f64, @floatFromInt(row)) * rect.height) } } });
        }
        self.root.setBackground(theme.baseColors().app);
        self.images.setDisplay(.flex);
        self.veil.setDisplay(.flex);
        // Preview surfaces are composited offscreen. Sample their own image,
        // not the settings/terminal pixels behind the preview's surface.
        self.blur.setStyleInline(self.cx.allocator, .{ .glass = .{ .backdrop_blur = @floatFromInt(materials.blur_px), .glass_intensity = 0, .specular_opacity = 0, .refraction_level = 0, .warp_gain = 0, .capture_source = .current_surface, .capture_clamp = true, .a11y_exempt = true }, .background = ui.Color.TRANSPARENT });
        self.blur.setDisplay(if (materials.blur_px == 0) .none else .flex);
        // Only this background group is translucent; image blur is shared once.
        self.root.setDisplay(.flex);
        self.fingerprint = fingerprint;
        self.cx.requestRedraw();
    }
    fn layer() ui.BoxStyle {
        return .{ .hit_behavior = .pass_through, .hit_roles = .{ .pointer = false, .scroll = false, .inspect = false }, .position = .absolute, .inset = .{ .left = .{ .px = 0 }, .right = .{ .px = 0 }, .top = .{ .px = 0 }, .bottom = .{ .px = 0 } }, .width = .fill(), .height = .fill() };
    }
    fn cleanup(self: *View) void {
        self.cx.removeAfterLayoutHook(self);
        self.group_members.deinit(self.cx.allocator);
        self.group_paints.deinit(self.cx.allocator);
        self.tiles.deinit(self.cx.allocator);
        self.cx.allocator.destroy(self);
    }
};

test "a hidden island hides its plate and the hook settles without repeated layout requests" {
    const cx = try ui.Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    const scope = try ui.Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    cx.setViewport(800, 600);
    const view = try View.mount(cx, scope);
    cx.root = view.root;
    try view.update(null, .{}, 800, 600);
    const source = try ui.box(cx, .{ .position = .absolute, .inset = .{ .left = .{ .px = 5 }, .top = .{ .px = 50 } }, .width = .{ .px = 790 }, .height = .{ .px = 500 } }, .{});
    try cx.root.?.appendChild(cx.allocator, source);
    try view.bindIsland(scope, source, null);
    const frames = struct {
        fn run(c: *ui.Cx) void {
            for (0..2) |_| {
                c.frame_count += 1;
                c.frame_time_ms += 16;
                _ = c.render();
            }
        }
    }.run;
    frames(cx);
    try std.testing.expectEqual(.flex, view.island_surface.?.node.style.display);
    source.setDisplay(.none);
    frames(cx);
    try std.testing.expectEqual(.none, view.island_surface.?.node.style.display);
    for (0..3) |_| try std.testing.expectEqual(ui.AfterLayoutResult.done, View.syncShell(view, 0, false));
    source.setDisplay(.flex);
    frames(cx);
    try std.testing.expectEqual(.flex, view.island_surface.?.node.style.display);
    for (0..3) |_| try std.testing.expectEqual(ui.AfterLayoutResult.done, View.syncShell(view, 0, false));
}

test "the island plate has one writer: shell styles declare no background and the layer never writes the island" {
    // The window root, the view bar, the sidebar, the island and the pane header: none may
    // declare a background, or a theme replay would paint it back over the canvas group and
    // something would have to clear it every frame again.
    const styles = @import("shell_styles.zig");
    for ([_]*const ui.ThemeTokens{ &ui.theme.light, &ui.theme.dark }) |tokens| {
        inline for (.{ styles.root, styles.title, styles.sidebar, styles.pane, styles.status }) |style| {
            const background = style(tokens).background;
            try std.testing.expect(background == null or background.?.a == 0);
        }
    }
    // The layer reads the island's rect and radius only: a background on the node is not its
    // to change (nothing in the shell sets one; this pins the layer's side of the contract).
    const cx = try ui.Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    const scope = try ui.Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    cx.setViewport(800, 600);
    const view = try View.mount(cx, scope);
    cx.root = view.root;
    try view.update(null, .{}, 800, 600);
    const own = ui.Color.rgb(10, 20, 30);
    const source = try ui.box(cx, .{ .position = .absolute, .width = .{ .px = 200 }, .height = .{ .px = 30 }, .background = own, .border = .{ .radius = 12 } }, .{});
    try cx.root.?.appendChild(cx.allocator, source);
    try view.bindIsland(scope, source, null);
    for (0..3) |_| {
        cx.frame_count += 1;
        cx.frame_time_ms += 16;
        _ = cx.render();
    }
    try std.testing.expect(ui.Color.eql(own, source.getBackground()));
    try std.testing.expectEqual(.flex, view.island_surface.?.node.style.display);
    const outline = view.island_surface.?.shownOutline();
    try std.testing.expectEqual(@as(usize, 1), outline.contours.items.len);
    for (outline.vertices.items) |vertex| try std.testing.expectEqual(@as(f32, 12), vertex.radius);
    try std.testing.expectEqual(@as(u8, 255), view.island_surface.?.node.getBackground().a);
}

test "island plate follows the active tab in one contour and leaves input to the tab" {
    const cx = try ui.Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    const scope = try ui.Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    cx.setViewport(800, 600);
    cx.reduced_motion = true;
    const view = try View.mount(cx, scope);
    cx.root = view.root;
    try view.update(null, .{}, 800, 600);
    const source = try ui.box(cx, .{
        .position = .absolute,
        .inset = .{ .left = .{ .px = 5 }, .top = .{ .px = 50 } },
        .width = .{ .px = 790 },
        .height = .{ .px = 500 },
        .border = .{ .radius = 12 },
    }, .{});
    try view.root.appendChild(cx.allocator, source);
    const tabs = [2]*ui.Node{
        try ui.box(cx, .{
            .position = .absolute,
            .inset = .{ .left = .{ .px = 19 }, .top = .{ .px = 17 } },
            .width = .{ .px = 100 },
            .height = .{ .px = 33 },
            .hit_behavior = .@"opaque",
        }, .{}),
        try ui.box(cx, .{
            .position = .absolute,
            .inset = .{ .left = .{ .px = 130 }, .top = .{ .px = 17 } },
            .width = .{ .px = 100 },
            .height = .{ .px = 33 },
            .hit_behavior = .@"opaque",
        }, .{}),
    };
    for (tabs) |tab| try view.root.appendChild(cx.allocator, tab);
    const selected = try scope.createSignal(joined.Target, try joined.targetOf(cx, tabs[0]));
    try view.bindIsland(scope, source, selected);
    const plate = view.island_surface.?;
    const render = struct {
        fn frame(c: *ui.Cx) void {
            c.frame_count += 1;
            c.frame_time_ms += 16;
            _ = c.render();
        }
    }.frame;
    render(cx);
    render(cx);
    try std.testing.expectEqual(@as(usize, 1), plate.shownOutline().contours.items.len);
    try std.testing.expectEqual(@as(usize, 8), plate.shownOutline().vertices.items.len);
    try std.testing.expect(plate.node.shapePath() != null);
    try std.testing.expectEqual(@as(f32, 1), plate.node.style.border.width);
    try std.testing.expectEqual(tabs[0].globalRect().x, plate.shownRect(0).?.x);
    try std.testing.expect(cx.hitTest(45, 30) == tabs[0]);

    selected.set(try joined.targetOf(cx, tabs[1]));
    render(cx);
    try std.testing.expectEqual(@as(usize, 1), plate.shownOutline().contours.items.len);
    try std.testing.expectEqual(tabs[1].globalRect().x, plate.shownRect(0).?.x);
    selected.set(.none);
    render(cx);
    try std.testing.expectEqual(@as(usize, 1), plate.shownOutline().contours.items.len);
    try std.testing.expectEqual(@as(usize, 4), plate.shownOutline().vertices.items.len);
    try std.testing.expectEqual(source.globalRect(), plate.shownRect(1).?);
}

test "background repeat layer uses the atlas only for Tile and keeps original fit coordinates" {
    const cx = try ui.Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    const scope = try ui.Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    const view = try View.mount(cx, scope);
    cx.root = view.root;
    cx.setViewport(1440, 900);
    const image: Image = .{ .id = 7, .width = 3, .height = 5, .repeating = .{ .id = 8, .width = 66, .height = 65 } };
    var materials: material.Materials = .{ .background = .{ .enabled = true, .path = "/fixture", .fit = .tile } };
    try view.update(image, materials, 1440, 900);
    cx.layout();
    try std.testing.expect(view.tiles.items.len <= 24 * 16);
    const first = view.tiles.items[0];
    try std.testing.expectEqual(@as(u32, 8), first.getImage().?.texture_id);
    try std.testing.expectEqual(@as(f32, 66), first.globalRect().w);
    try std.testing.expectEqual(@as(f32, 65), first.globalRect().h);
    try std.testing.expectEqual(@as(f32, -7.5), first.globalRect().x);
    try std.testing.expectEqual(@as(f32, -7.5), first.globalRect().y);

    const Case = struct { fit: material.Fit, x: f32, y: f32, width: f32, height: f32 };
    for ([_]Case{
        .{ .fit = .fill, .x = 0, .y = -750, .width = 1440, .height = 2400 },
        .{ .fit = .fit, .x = 450, .y = 0, .width = 540, .height = 900 },
        .{ .fit = .center, .x = 718.5, .y = 447.5, .width = 3, .height = 5 },
    }) |case| {
        materials.background.fit = case.fit;
        try view.update(image, materials, 1440, 900);
        cx.layout();
        try std.testing.expectEqual(@as(u32, 7), first.getImage().?.texture_id);
        const rect = first.globalRect();
        try std.testing.expectEqual(case.x, rect.x);
        try std.testing.expectEqual(case.y, rect.y);
        try std.testing.expectEqual(case.width, rect.w);
        try std.testing.expectEqual(case.height, rect.h);
        for (view.tiles.items[1..]) |node| try std.testing.expectEqual(.none, node.style.display);
    }
}

test "global material composites opaque shell fills before applying canvas transparency once" {
    const parameters = theme.materialParameters();
    defer _ = theme.setMaterialParameters(parameters.transparency, parameters.blur);
    const previous = theme.currentName();
    const was_visible = theme.materialVisible();
    defer {
        theme.select(previous);
        _ = theme.setMaterialVisible(was_visible);
    }
    _ = theme.setMaterialVisible(true);
    const cx = try ui.Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    const scope = try ui.Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    const view = try View.mount(cx, scope);
    cx.root = view.root;
    cx.setViewport(1440, 900);
    const island = try ui.box(cx, .{ .position = .absolute, .width = .{ .px = 200 }, .height = .{ .px = 50 }, .inset = .{ .left = .{ .px = 5 }, .top = .{ .px = 125 } }, .border = .{ .radius = 11 } }, .{});
    try view.root.appendChild(cx.allocator, island);
    try view.bindIsland(scope, island, null);
    var materials: material.Materials = .{ .background = .{ .enabled = true, .path = "/fixture", .fit = .fit } };
    for (std.enums.values(theme.Name)) |name| {
        theme.select(name);
        for ([_]f32{ 0, 50, 100 }) |percent| {
            materials.background.transparency = percent;
            materials.blur_px = @intFromFloat(percent * 0.96);
            _ = theme.setMaterialParameters(percent, @floatFromInt(materials.blur_px));
            try view.update(.{ .id = 7, .width = 320, .height = 180 }, materials, 1440, 900);
            cx.layout();
            _ = View.syncShell(view, 0, false);
            cx.layout();
            try std.testing.expectEqual(1 - percent / 100, view.veil.getOpacity());
            try std.testing.expect(view.veil.style.composited_group());
            // The island plate is opaque inside the canvas group (the group's opacity is the one
            // transparency); the island node itself stays unpainted.
            try std.testing.expectEqual(@as(u8, 0), island.getBackground().a);
            try std.testing.expectEqual(.flex, view.island_surface.?.node.style.display);
            try std.testing.expectEqual(@as(u8, 255), view.island_surface.?.node.getBackground().a);
            try std.testing.expectEqual(@as(f32, @floatFromInt(materials.blur_px)), view.blur.style.backdrop_blur());
            try std.testing.expect((view.blur.style.display == .none) == (materials.blur_px == 0));
            cx.layout();
            try std.testing.expectEqual(@as(u8, 0), theme.current().app.a);
            try std.testing.expectEqual(theme.baseColors().app, view.root.getBackground());
            try std.testing.expectEqual(theme.baseColors().app.withAlpha(255), view.veil.getBackground());
            const rect = view.tiles.items[0].globalRect();
            try std.testing.expectApproxEqAbs(@as(f32, 0), rect.x, 0.01);
            try std.testing.expectApproxEqAbs(@as(f32, 45), rect.y, 0.01);
            try std.testing.expectApproxEqAbs(@as(f32, 1440), rect.w, 0.01);
            try std.testing.expectApproxEqAbs(@as(f32, 810), rect.h, 0.01);
        }
    }
}

test "group canvas paints each member and leaves gutters on base canvas" {
    const a = std.testing.allocator;
    const cx = try ui.Cx.init(a, std.testing.io);
    defer cx.deinit();
    const scope = try ui.Scope.init(a, null, cx.owner);
    defer scope.dispose();
    const view = try View.mount(cx, scope);
    cx.root = view.root;
    cx.setViewport(800, 600);
    try view.update(null, .{}, 800, 600);
    const island_source = try ui.box(cx, .{ .width = .{ .px = 600 }, .height = .{ .px = 400 } }, .{});
    try view.root.appendChild(a, island_source);
    try view.bindIsland(scope, island_source, null);
    const group = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .direction = .row, .gap = 4 }, .{});
    try island_source.appendChild(a, group);
    // The split's owner lists its members; the layer does not search the tree (the panes carry
    // no test id here, and a look-alike node that is not listed gets no plate).
    const Owner = struct {
        group: *ui.Node,
        panes: [2]*ui.Node = undefined,
        focused: usize = 0,
        fn members(raw: *anyopaque, out: *std.ArrayList(GroupMember), allocator: std.mem.Allocator) anyerror!void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            if (!self.group.isDisplayedInTree()) return;
            for (self.panes, 0..) |pane, i| try out.append(allocator, .{ .node = pane, .focused = i == self.focused });
        }
    };
    var owner: Owner = .{ .group = group };
    for (0..2) |i| {
        const pane = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .flex = 1, .border = .{ .radius = 11 } }, .{});
        try group.appendChild(a, pane);
        owner.panes[i] = pane;
    }
    const stray = try ui.box(cx, .{ .position = .absolute, .width = .{ .px = 10 }, .height = .{ .px = 10 } }, .{});
    stray.meta.ownership.meta.test_id = "groups.pane.99";
    try island_source.appendChild(a, stray);
    view.bindGroup(.{ .ctx = &owner, .members = Owner.members });
    for (0..3) |_| {
        cx.layout();
        _ = View.syncShell(view, 0, false);
    }
    cx.layout();
    try std.testing.expectEqual(@as(usize, 2), view.group_paints.items.len);
    // Island B v3 split (Pencil `i3Zme8`): members sit inside the view island,
    // so the island plate stays below them and the 4pt gutters show the island,
    // while each member gets its own radius-8 plate above it in the same veil.
    const island = view.island_surface.?.node;
    try std.testing.expectEqual(.flex, island.style.display);
    const island_index = std.mem.indexOfScalar(*ui.Node, view.veil.children.items, island).?;
    const first = view.group_paints.items[0].globalRect();
    const second = view.group_paints.items[1].globalRect();
    try std.testing.expectApproxEqAbs(@as(f32, 4), second.x - first.x - first.w, 0.01);
    // The focused member is the focus island (surface_1, accent hairline); the other rests.
    try std.testing.expectEqual(theme.baseColors().surface_1.withAlpha(255), view.group_paints.items[0].getBackground());
    try std.testing.expectEqual(@as(f32, 1), view.group_paints.items[0].style.border.width);
    try std.testing.expectEqual(theme.baseColors().surface_2.withAlpha(255), view.group_paints.items[1].getBackground());
    try std.testing.expectEqual(@as(f32, 0), view.group_paints.items[1].style.border.width);
    owner.focused = 1;
    for (0..2) |_| {
        cx.layout();
        _ = View.syncShell(view, 0, false);
    }
    try std.testing.expectEqual(@as(f32, 0), view.group_paints.items[0].style.border.width);
    try std.testing.expectEqual(@as(f32, 1), view.group_paints.items[1].style.border.width);
    for (view.group_paints.items) |paint| {
        try std.testing.expect(paint.parent == view.veil);
        try std.testing.expect(std.mem.indexOfScalar(*ui.Node, view.veil.children.items, paint).? > island_index);
        try std.testing.expectEqual(@as(u8, 255), paint.getBackground().a);
        try std.testing.expectEqual(@import("../../workspace/view/group_workspace_styles.zig").pane_radius, paint.style.effectiveRadius());
    }
    group.setDisplay(.none);
    for (0..2) |_| {
        cx.layout();
        _ = View.syncShell(view, 0, false);
    }
    try std.testing.expectEqual(.flex, view.island_surface.?.node.style.display);
    for (view.group_paints.items) |paint| try std.testing.expectEqual(.none, paint.style.display);
}
