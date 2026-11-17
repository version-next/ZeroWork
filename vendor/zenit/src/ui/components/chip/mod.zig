/// Chip: filter / category tag built on ControlShell (chip.yix + styles.yss).
///
/// - 3 sizes: xs(20) / sm(28) / md(32)
/// - looks: default / active (selected) / outline / disabled, raised (xs shadow) where the design
///   says so
/// - optional leading icon + close button
/// - read-only by default (readonly=true); hover / click / focus only when readonly=false
const std = @import("std");
const core = @import("../../core.zig");
const Cx = core.Cx;
const Node = core.Node;
const box = core.box;
const Color = core.Color;
const reactive = @import("../../reactive.zig");
const Scope = reactive.Scope;
const svg_assets = @import("../../svg_assets.zig");
const view_mod = @import("_chip.yix.zig");

pub const Chip = view_mod.Chip;
pub const ChipProps = view_mod.ChipProps;
pub const ChipSize = view_mod.ChipSize;
pub const ChipVariant = view_mod.ChipVariant;
pub const ChipLook = view_mod.ChipLook;
/// Attachment spec of the Chip family: type icon / thumbnail, name, size, remove button; or a 44
/// thumbnail tile (attachment.yix). `W.AttachmentChip(.{ .label = "syslog.1", .detail = "48 KB",
/// .icon_asset = icons.file_text, .on_remove = … })`.
pub const AttachmentChip = @import("_attachment.yix.zig").AttachmentChip;

// ============================================================================
// Tests
// ============================================================================

/// Settled background (transition target while easing).
fn backgroundTarget(n: *Node) Color {
    if (n.frame_state.frame_local.runtime.transitions) |slots| if (slots.find(.background)) |slot| if (slot.active) return slot.to_color;
    return n.getBackground();
}

test "Chip: basic creation" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 100 } }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const node = try Chip(.{ .label = "Tag" }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, node);

    try std.testing.expectEqualStrings("Chip", node.meta.ownership.meta.component_name.?);
    // COMPONENTS.json Chip / default: sm height is 28px.
    ctx.layout();
    // height fitted by padding_y * 2 + line_height (no longer style.height px)
    try std.testing.expectEqual(@as(f32, 28), node.rectFromWorldOrFallback().h);
}

test "Chip: 反复 mount/free 不泄漏 World element slot（未用 slot 走 freeNode）" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const root = try box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 400 } }, .{});
    ctx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const Cycle = struct {
        fn run(c: *Cx, s: *Scope, r: *Node) !void {
            const sub = try s.childScope();
            const n = try Chip(.{ .label = "x" }).mount(sub, c); // no icon, not closeable: both slots unused
            try r.appendChild(c.allocator, n);
            c.detachChild(r, n);
            c.freeNode(n);
            sub.dispose();
        }
    };
    try Cycle.run(ctx, scope, root);
    const baseline = ctx.world.elements.count();
    var i: usize = 0;
    while (i < 20) : (i += 1) try Cycle.run(ctx, scope, root);
    try std.testing.expectEqual(baseline, ctx.world.elements.count());
}

test "Chip: with icon and close" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 100 } }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const node = try Chip(.{
        .label = "Filter",
        .icon_asset = svg_assets.common.search,
        .closable = true,
        .size = .md,
    }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, node);

    // md -> ControlSize.md -> height=32
    ctx.layout();
    // height fitted by padding_y * 2 + line_height (no longer style.height px)
    try std.testing.expectEqual(@as(f32, 32), node.rectFromWorldOrFallback().h);
}

test "Chip: xs size" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 100 } }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const node = try Chip(.{
        .label = "Mini",
        .size = .xs,
    }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, node);

    // xs -> ControlSize.xs -> height=20
    ctx.layout();
    // height fitted by padding_y * 2 + line_height (no longer style.height px)
    try std.testing.expectEqual(@as(f32, 20), node.rectFromWorldOrFallback().h);
}

test "Chip: disabled variant" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 100 } }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const node = try Chip(.{
        .label = "Disabled",
        .disabled = true,
    }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, node);

    try std.testing.expectEqual(@as(f32, 1.0), node.getOpacity());
    try std.testing.expectEqual(thematicColor(ctx.tokens.tokens.color.bg_secondary), thematicColor(backgroundTarget(node)));
    try std.testing.expectEqual(thematicColor(ctx.tokens.tokens.color.separator), thematicColor(node.style.border.color));
}

fn thematicColor(color: Color) u32 {
    return @bitCast(color);
}

test "Chip: readonly by default disables hover interaction" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 100 } }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const node = try Chip(.{ .label = "Readonly by default" }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, node);

    // The look's resting background holds under the pointer (no hover feedback).
    const resting = backgroundTarget(node);
    const enter = node.behavior.events.on_hover.?;
    enter.callback(enter.context);
    try std.testing.expect(Color.eql(resting, backgroundTarget(node)));
    try std.testing.expectEqual(core.CursorShape.default, node.style.cursor);
}

test "Chip: readonly false enables hover interaction" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 100 } }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const node = try Chip(.{
        .label = "Interactive",
        .readonly = false,
    }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, node);

    const enter = node.behavior.events.on_hover.?;
    enter.callback(enter.context);
    try std.testing.expect(Color.eql(ctx.tokens.tokens.color.bg_active, backgroundTarget(node)));
    try std.testing.expectEqual(core.CursorShape.pointer, node.style.cursor);
}

test "Chip: render emits background and label text" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setViewport(240, 80);

    const root = try box(ctx, .{
        .width = .{ .px = 240 },
        .height = .{ .px = 80 },
        .background = ctx.tokens.tokens.color.bg_primary,
    }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const node = try Chip(.{
        .label = "Filter",
        .variant = .default,
    }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, node);

    ctx.layout();
    _ = ctx.render();
    const commands = ctx.lowerForEncoderPaintTable();

    var saw_bg = false;
    var saw_label = false;
    for (commands) |cmd| if (cmd.isFillRect()) {
        const r = cmd;
        if (Color.eql(r.color.toColor(), ctx.tokens.tokens.color.bg_primary) and r.geom.w >= 40 and r.geom.h >= 20) {
            saw_bg = true;
        }
    } else if (cmd.isText()) {
        const tcmd = cmd;
        if (std.mem.eql(u8, tcmd.text_content, "Filter")) saw_label = true;
    };

    try std.testing.expect(saw_bg);
    try std.testing.expect(saw_label);
}

// OOM sweep per allocation point; see src/ui/components/oom_sweep.zig
test "chip(closable): mount 在任意分配点失败时不泄漏（sweep）" {
    try @import("../oom_sweep.zig").sweepMount("chip(closable)", struct {
        fn m(scope: *Scope, cx: *Cx) anyerror!?*Node {
            return try Chip(.{ .label = "chip", .closable = true, .readonly = false }).mount(scope, cx);
        }
    }.m);
}

test "Chip: selected / disabled from signals; disabled gates the click; dynamic label" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const on = try scope.createSignal(bool, false);
    const off = try scope.createSignal(bool, false);
    const name = try scope.createText("Open", .{});
    var clicks: u32 = 0;
    const node = try Chip(.{ .label = name, .selected = on, .disabled = off, .readonly = false, .on_click = ctx.on(u32, &clicks, struct {
        fn f(c: *u32) void {
            c.* += 1;
        }
    }.f) }).mount(scope, ctx);
    defer ctx.freeNode(node);
    const label = node.children.items[0].children.items[0];

    on.set(true);
    try std.testing.expect(node.behavior.interaction.a11y.?.selected);
    try std.testing.expect(Color.eql(label.getText().?.color, ctx.tokens.tokens.color.selection_fg));
    try std.testing.expect(Color.eql(ctx.tokens.tokens.color.selection_bg, backgroundTarget(node)));

    node.behavior.events.on_click.?.invoke();
    try std.testing.expectEqual(@as(u32, 1), clicks);
    off.set(true);
    node.behavior.events.on_click.?.invoke();
    try std.testing.expectEqual(@as(u32, 1), clicks); // no response when disabled
    try std.testing.expect(!node.behavior.interaction.focusable);
    try std.testing.expect(node.behavior.interaction.a11y.?.disabled);

    name.set("Open issues");
    try std.testing.expectEqualStrings("Open issues", label.getText().?.content);
    try std.testing.expectEqualStrings("Open issues", node.behavior.interaction.a11y.?.label.?);
}

test "chip: 动态选中 / 禁用 / 文本的 mount 在任意分配点失败时不泄漏（sweep）" {
    try @import("../oom_sweep.zig").sweepMount("chip(dynamic)", struct {
        fn m(scope: *Scope, cx: *Cx) anyerror!?*Node {
            const on = try scope.createSignal(bool, true);
            const name = try scope.createText("Open", .{});
            return try Chip(.{ .label = name, .selected = on, .closable = true, .readonly = false, .icon_asset = svg_assets.common.search }).mount(scope, cx);
        }
    }.m);
}

// Reference-checked OOM sweep (see oom_sweep.zig): a mount that reports success must look exactly
// like the uninjected mount; `check` also pins the states the reference was given.
test "chip(selected+overlay): mount 成功即外观完整，任意分配点失败不假成功（sweep）" {
    const sw = @import("../oom_sweep.zig");
    try sw.sweepMountVerified("chip(selected+overlay)", struct {
        fn m(scope: *Scope, cx: *Cx) anyerror!?*Node {
            const view = @import("../../view.zig");
            const on = try scope.createSignal(bool, true);
            const off = try scope.createSignal(bool, false);
            return try view.render(scope, cx, view.attrs(.{ .style = core.BoxStyle{ .margin = core.Padding.all(2) } }, Chip(.{ .label = "Open", .selected = on, .disabled = off, .readonly = false, .icon_asset = svg_assets.common.search })));
        }
    }.m, struct {
        fn check(root: *Node) anyerror!void {
            const t = &core.theme.dark;
            // the active look (selected) at mount: background, border, foreground
            try std.testing.expect(Color.eql(t.tokens.color.selection_bg, root.getBackground()));
            try std.testing.expect(Color.eql(t.tokens.color.accent_border, root.style.border.color));
            try std.testing.expect(root.style.border.width > 0);
            try std.testing.expect(root.style.effectiveRadii()[0] > 0);
            try std.testing.expect(root.style.padding.left > 0);
            try std.testing.expectEqual(core.Padding.all(2), root.style.margin);
        }
    }.check);
}

test "Chip: 选中态文字在渲染时取 selection_fg，不被外壳 tone 的前景色（primary fg）覆盖；换主题跟随" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const root = try box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 100 } }, .{});
    ctx.root = root;
    ctx.setTheme(&core.theme.modes.light);
    const node = try Chip(.{ .label = "Active", .selected = true }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, node);
    const label = node.children.items[0].children.items[0];
    const painted = @import("../../core/render_engine/text_render.zig").resolveNodeLogicalTextProps;
    try std.testing.expect(Color.eql(painted(label).?.color, core.theme.modes.light.tokens.color.selection_fg));
    ctx.setTheme(&core.theme.modes.dark);
    try std.testing.expect(Color.eql(painted(label).?.color, core.theme.modes.dark.tokens.color.selection_fg));
}

// ========== AttachmentChip ==========

const aview = @import("../../view.zig");
const zicons = @import("zenit_icons");

fn findTestIdIn(n: *Node, id: []const u8) ?*Node {
    if (n.meta.ownership.meta.test_id) |t| if (std.mem.eql(u8, t, id)) return n;
    for (n.children.items) |c| if (findTestIdIn(c, id)) |r| return r;
    return null;
}

fn findTextIn(n: *Node, text: []const u8) ?*Node {
    if (n.getText()) |t| if (std.mem.eql(u8, t.content, text)) return n;
    for (n.children.items) |c| if (findTextIn(c, text)) |r| return r;
    return null;
}

fn findKind(n: *Node, comptime image: bool) ?*Node {
    for (n.children.items) |c| {
        if (image and c.getImage() != null) return c;
        if (!image and c.getIcon() != null) return c;
        if (findKind(c, image)) |r| return r;
    }
    return null;
}

const Removes = struct {
    n: u32 = 0,
    fn hit(self: *Removes) void {
        self.n += 1;
    }
};

test "AttachmentChip row: 28 high on bg-secondary, type icon, name, size, native remove button" {
    var cx = try Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    cx.setViewport(400, 200);
    const root = try box(cx, .{ .width = .{ .px = 400 }, .height = .{ .px = 200 }, .direction = .row, .align_items = .start }, .{});
    cx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    var removes: Removes = .{};
    const chip = try aview.render(scope, cx, AttachmentChip(.{ .label = "syslog.1", .detail = "48 KB", .icon_asset = zicons.file_text, .remove_test_id = "att.remove", .on_remove = cx.on(Removes, &removes, Removes.hit) }));
    try root.appendChild(std.testing.allocator, chip);
    cx.layout();
    const k = cx.tokens.tokens;
    try std.testing.expectApproxEqAbs(@as(f32, 28), chip.globalRect().h, 0.5);
    try std.testing.expect(Color.eql(chip.getBackground(), k.color.bg_secondary));
    try std.testing.expectEqual(@as(f32, 0), chip.style.border.width);
    const glyph = findKind(chip, false).?;
    try std.testing.expectEqual(@as(f32, 13), glyph.globalRect().w);
    try std.testing.expect(Color.eql(glyph.getIcon().?.tint, k.color.fg_secondary));
    const name = findTextIn(chip, "syslog.1").?.getText().?;
    try std.testing.expectEqual(k.font_size.sm, name.font_size);
    try std.testing.expect(Color.eql(name.color, k.color.fg_primary));
    try std.testing.expectEqual(@as(u16, 400), name.font_weight);
    const size = findTextIn(chip, "48 KB").?.getText().?;
    try std.testing.expectEqual(@as(u16, 400), size.font_weight);
    try std.testing.expectEqual(k.font_size.xs, size.font_size);
    try std.testing.expect(Color.eql(size.color, k.color.fg_tertiary));
    const remove = findTestIdIn(chip, "att.remove").?;
    try std.testing.expectEqualStrings("Button", remove.meta.ownership.meta.component_name.?);
    try std.testing.expectEqualStrings("Remove attachment", remove.behavior.interaction.a11y.?.label.?);
    remove.behavior.events.on_click.?.invoke();
    try std.testing.expectEqual(@as(u32, 1), removes.n);
    // Not clickable itself: a list item, not a Tab stop.
    try std.testing.expect(!chip.behavior.interaction.focusable);
    try std.testing.expectEqual(core.A11yRole.listitem, chip.behavior.interaction.a11y.?.role);
    // Layout: icon, text, button left to right inside the chip.
    try std.testing.expect(glyph.globalRect().x < findTextIn(chip, "syslog.1").?.globalRect().x);
    try std.testing.expect(remove.globalRect().x + remove.globalRect().w <= chip.globalRect().x + chip.globalRect().w + 0.5);
    cx.root = null;
    cx.freeNode(root);
}

test "AttachmentChip tile: 44 x 44 on bg-tertiary, thumbnail fills it, remove over the corner; row thumbnail is 20" {
    var cx = try Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    cx.setViewport(400, 200);
    const root = try box(cx, .{ .width = .{ .px = 400 }, .height = .{ .px = 200 }, .direction = .row, .align_items = .start, .gap = 8 }, .{});
    cx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    var opened: Removes = .{};
    const tile = try aview.render(scope, cx, AttachmentChip(.{ .label = "dmesg.png", .thumbnail = 7, .tile = true, .remove_test_id = "tile.remove", .on_click = cx.on(Removes, &opened, Removes.hit) }));
    const placeholder = try aview.render(scope, cx, AttachmentChip(.{ .label = "shot.png", .icon_asset = zicons.image, .tile = true, .removable = false }));
    const row = try aview.render(scope, cx, AttachmentChip(.{ .label = "dmesg.png", .detail = "120 KB", .thumbnail = 7 }));
    try root.appendChild(std.testing.allocator, tile);
    try root.appendChild(std.testing.allocator, placeholder);
    try root.appendChild(std.testing.allocator, row);
    cx.layout();
    const k = cx.tokens.tokens;
    try std.testing.expectApproxEqAbs(@as(f32, 44), tile.globalRect().w, 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 44), tile.globalRect().h, 0.5);
    try std.testing.expect(Color.eql(tile.getBackground(), k.color.bg_tertiary));
    const image = findKind(tile, true).?;
    try std.testing.expectApproxEqAbs(@as(f32, 44), image.globalRect().w, 0.5);
    try std.testing.expect(findTextIn(tile, "dmesg.png") == null);
    try std.testing.expectEqualStrings("dmesg.png", tile.behavior.interaction.a11y.?.label.?);
    const remove = findTestIdIn(tile, "tile.remove").?;
    const t = tile.globalRect();
    try std.testing.expect(remove.globalRect().x + remove.globalRect().w <= t.x + t.w + 0.5);
    try std.testing.expect(remove.globalRect().y >= t.y and remove.globalRect().y < t.y + 8);
    // A compact 18 round, clear of the tile's center: a click there opens, never removes.
    try std.testing.expectApproxEqAbs(@as(f32, 18), remove.globalRect().w, 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 18), remove.globalRect().h, 0.5);
    const r = remove.globalRect();
    try std.testing.expect(!(r.x <= t.x + t.w / 2 and t.x + t.w / 2 <= r.x + r.w and r.y <= t.y + t.h / 2 and t.y + t.h / 2 <= r.y + r.h));
    _ = cx.render();
    cx.handleMouseDown(t.x + t.w / 2, t.y + t.h / 2, .{});
    cx.handleMouseUp(t.x + t.w / 2, t.y + t.h / 2);
    try std.testing.expectEqual(@as(u32, 1), opened.n);
    opened.n = 0;
    // Clickable: a button and a Tab stop; the click opens it.
    try std.testing.expect(tile.behavior.interaction.focusable);
    try std.testing.expectEqual(core.A11yRole.button, tile.behavior.interaction.a11y.?.role);
    tile.behavior.events.on_click.?.invoke();
    try std.testing.expectEqual(@as(u32, 1), opened.n);
    // Without a picture the tile centers the type icon (16, fg-tertiary).
    const glyph = findKind(placeholder, false).?;
    try std.testing.expectEqual(@as(f32, 16), glyph.globalRect().w);
    try std.testing.expect(Color.eql(glyph.getIcon().?.tint, k.color.fg_tertiary));
    try std.testing.expectApproxEqAbs(placeholder.globalRect().x + 22, glyph.globalRect().x + 8, 0.5);
    // Row form with a picture: a 20 thumbnail leads.
    try std.testing.expectApproxEqAbs(@as(f32, 20), findKind(row, true).?.globalRect().w, 0.5);
    cx.root = null;
    cx.freeNode(root);
}

test "attachment chip: mount 在任意分配点失败时不泄漏（sweep）" {
    try @import("../oom_sweep.zig").sweepMount("attachment chip", struct {
        fn m(scope: *Scope, cx: *Cx) anyerror!?*Node {
            return try aview.render(scope, cx, AttachmentChip(.{ .label = "syslog.1", .detail = "48 KB", .icon_asset = zicons.file_text }));
        }
    }.m);
}

test {
    _ = @import("_attachment.yss.zig");
}
