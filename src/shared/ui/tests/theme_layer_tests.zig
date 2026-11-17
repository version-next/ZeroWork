//! Global appearance regression checks on retained, real production views.
comptime {
    _ = @import("../../../features/shell/tests/material_performance_tests.zig");
}
const std = @import("std");
const ui = @import("ui");
const theme = @import("../theme/app_theme.zig");
const publication = @import("../theme/theme_publication.zig").ThemePublication;
const Close = @import("../../../features/terminal/view/local_close_view.zig");
const Transfer = @import("../../../features/transfer/view/transfer_panel.zig");

test "native floating panels stay opaque at every material transparency" {
    // H-opaque-popups: zenit paints its floating panels (Popover / Menu / Select
    // panel / Modal dialog / Tooltip) with semantic surfaces it treats as opaque.
    // The ZeroWork theme must publish those at alpha 255 for every built-in
    // palette and material setting, while its own shell surfaces keep the
    // material alpha that lets the wallpaper through.
    const previous = theme.currentName();
    const was_visible = theme.materialVisible();
    const saved = theme.materialParameters();
    defer {
        theme.select(previous);
        _ = theme.setMaterialVisible(was_visible);
        _ = theme.setMaterialParameters(saved.transparency, saved.blur);
    }
    const w = try Window.init();
    defer w.deinit();
    const open = try w.scope.createSignal(bool, true);
    const popup = try ui.widgets.Popover(.{ .open = open, .trigger = .manual, .enter_transition = .none, .exit_transition = .none, .width = 240 }).mount(w.scope, w.cx);
    try w.cx.root.?.appendChild(w.cx.allocator, popup.wrapper);
    const items = [_]ui.widgets.MenuItem{ .{ .label = "向右分屏" }, .{ .label = "向下分屏" } };
    const menu = try ui.widgets.Menu(.{ .trigger = .manual, .open = open, .items = &items, .width = @as(f32, 220) }).mount(w.scope, w.cx);
    try w.cx.root.?.appendChild(w.cx.allocator, menu.wrapper);
    const menu_state: *ui.widgets.MenuState = @ptrCast(@alignCast(menu.wrapper.meta.ownership.debug_slots.state_ptrs[0].?));
    const options = [_]ui.widgets.SelectOption{ .{ .value = "xterm-256color", .label = "xterm-256color" }, .{ .value = "vt100", .label = "vt100" } };
    const select = try ui.widgets.Select(.{ .options = &options, .width = 220, .open = true }).mount(w.scope, w.cx);
    try w.cx.root.?.appendChild(w.cx.allocator, select.wrapper);
    const hint = try ui.widgets.Tooltip(.{ .text = "Opaque", .open = open }).mount(w.scope, w.cx);
    try w.cx.root.?.appendChild(w.cx.allocator, hint.wrapper);
    const modal = try ui.widgets.Modal(.{ .open = open, .width = @as(f32, 300), .enter_transition = .none, .exit_transition = .none }).mount(w.scope, w.cx);
    if (!modal.portaled) try w.cx.root.?.appendChild(w.cx.allocator, modal.overlay);
    var registry = try @import("../../../config/theme_registry.zig").Registry.init(std.testing.allocator);
    defer registry.deinit();
    var palettes: usize = 0;
    for (registry.records.items) |record| {
        if (record.source_kind != .builtin) continue;
        palettes += 1;
        theme.selectTokens(record.ui_tokens);
        for ([_]f32{ 0, 30, 70, 100 }) |transparency| for ([_]bool{ false, true }) |image| {
            errdefer std.debug.print("opaque panels: {s} T={d} image={}\n", .{ record.id, transparency, image });
            _ = theme.setMaterialParameters(transparency, 0);
            _ = theme.setMaterialVisible(image);
            const published = theme.widgetTheme(theme.currentName());
            w.publish.publish(w.cx, published);
            w.frame();
            const c = published.tokens.color;
            for ([_]ui.Color{ c.bg_base, c.bg_primary, c.bg_secondary, c.bg_tertiary, c.bg_inset }) |surface|
                try std.testing.expectEqual(@as(u8, 255), surface.a);
            for ([_]*ui.Node{ popup.chrome, menu_state.chrome, select.panel, hint.content, modal.dialog }) |panel| {
                try std.testing.expectEqual(@as(u8, 255), panel.getBackground().a);
            }
            try std.testing.expectEqual(c.bg_primary, select.panel.getBackground());
            try std.testing.expectEqual(c.bg_primary, modal.dialog.getBackground());
            // The palette RGB is unchanged; only the alpha differs from the shell surface.
            try std.testing.expectEqual(theme.current().surface_1.withAlpha(255), c.bg_primary);
            // ZeroWork's own material roles keep their transparency.
            try std.testing.expectEqual(@as(u8, @intFromFloat(@round(255 * (1 - transparency / 100)))), theme.current().surface_1.a);
            try std.testing.expectEqual(theme.current().surface_1, c.zw_island_focus);
            try std.testing.expectEqual(theme.current().surface_2, c.zw_island_rest);
        };
    }
    try std.testing.expect(palettes > 3);
}

/// One of each native floating surface, opened, with a Tooltip nested in the Popover.
const NativeSurfaces = struct {
    open: *ui.Signal(bool),
    hint_open: *ui.Signal(bool),
    popover: *ui.Node,
    menu: *ui.Node,
    select: *ui.Node,
    modal: *ui.Node,
    tooltip: *ui.Node,
    const menu_items = [_]ui.widgets.MenuItem{ .{ .label = "向右分屏" }, .{ .label = "向下分屏" } };
    const select_options = [_]ui.widgets.SelectOption{ .{ .value = "xterm-256color", .label = "xterm-256color" }, .{ .value = "vt100", .label = "vt100" } };
    fn mount(w: Window) !NativeSurfaces {
        const open = try w.scope.createSignal(bool, true);
        const hint_open = try w.scope.createSignal(bool, true);
        const popup = try ui.widgets.Popover(.{ .open = open, .trigger = .manual, .enter_transition = .none, .exit_transition = .none, .width = 240 }).mount(w.scope, w.cx);
        try w.cx.root.?.appendChild(w.cx.allocator, popup.wrapper);
        const hint = try ui.widgets.Tooltip(.{ .text = "Nested", .open = hint_open }).mount(w.scope, w.cx);
        try popup.content.appendChild(w.cx.allocator, hint.wrapper);
        const menu = try ui.widgets.Menu(.{ .trigger = .manual, .open = open, .items = &menu_items, .width = @as(f32, 220) }).mount(w.scope, w.cx);
        try w.cx.root.?.appendChild(w.cx.allocator, menu.wrapper);
        const menu_state: *ui.widgets.MenuState = @ptrCast(@alignCast(menu.wrapper.meta.ownership.debug_slots.state_ptrs[0].?));
        const select = try ui.widgets.Select(.{ .options = &select_options, .width = 220, .open = true }).mount(w.scope, w.cx);
        try w.cx.root.?.appendChild(w.cx.allocator, select.wrapper);
        const modal = try ui.widgets.Modal(.{ .open = open, .width = @as(f32, 300), .enter_transition = .none, .exit_transition = .none }).mount(w.scope, w.cx);
        if (!modal.portaled) try w.cx.root.?.appendChild(w.cx.allocator, modal.overlay);
        return .{ .open = open, .hint_open = hint_open, .popover = popup.chrome, .menu = menu_state.chrome, .select = select.panel, .modal = modal.dialog, .tooltip = hint.content };
    }
    fn expectSame(reference: NativeSurfaces, actual: NativeSurfaces) !void {
        const kit = @import("../../testing/ui_kit.zig");
        inline for (.{ "popover", "menu", "select", "modal", "tooltip" }) |name| {
            errdefer std.debug.print("native surface differs: {s}\n", .{name});
            try kit.expectSameSurface(@field(reference, name), @field(actual, name));
        }
    }
};

test "the application window repaints no native surface: Popover, Menu, Select, Modal and a nested Tooltip match a bare zenit window" {
    // Material belongs to whoever creates a surface. A zenit native panel is created by zenit, so
    // in a window carrying what ZeroWork mounts at window level (the canvas layer) it must paint
    // exactly what it paints in a window with nothing but zenit: across
    // every built-in palette and material setting, and again after the surfaces are closed,
    // rethemed while closed and reopened (nested Tooltip included).
    const previous = theme.currentName();
    const was_visible = theme.materialVisible();
    const saved = theme.materialParameters();
    defer {
        theme.select(previous);
        _ = theme.setMaterialVisible(was_visible);
        _ = theme.setMaterialParameters(saved.transparency, saved.blur);
    }
    const bare = try Window.init();
    defer bare.deinit();
    const app = try Window.init();
    defer app.deinit();
    const canvas = try @import("../../../features/shell/view/background_layers.zig").View.mount(app.cx, app.scope);
    try app.cx.root.?.appendChild(app.cx.allocator, canvas.root);
    try canvas.update(null, .{}, 1440, 900);
    const reference = try NativeSurfaces.mount(bare);
    const surfaces = try NativeSurfaces.mount(app);
    var registry = try @import("../../../config/theme_registry.zig").Registry.init(std.testing.allocator);
    defer registry.deinit();
    var palettes: usize = 0;
    for (registry.records.items) |record| {
        if (record.source_kind != .builtin) continue;
        palettes += 1;
        for ([_]f32{ 0, 50, 100 }) |transparency| {
            errdefer std.debug.print("native surfaces: {s} T={d}\n", .{ record.id, transparency });
            // Close, retheme while closed, reopen: the rebuilt surfaces are still zenit's own.
            for ([_]NativeSurfaces{ reference, surfaces }) |set| {
                set.open.set(false);
                set.hint_open.set(false);
            }
            bare.frame();
            app.frame();
            theme.selectTokens(record.ui_tokens);
            _ = theme.setMaterialParameters(transparency, transparency * 0.5);
            _ = theme.setMaterialVisible(transparency != 0);
            const published = theme.widgetTheme(theme.currentName());
            bare.publish.publish(bare.cx, published);
            app.publish.publish(app.cx, published);
            for ([_]NativeSurfaces{ reference, surfaces }) |set| {
                set.open.set(true);
                set.hint_open.set(true);
            }
            bare.frame();
            app.frame();
            try NativeSurfaces.expectSame(reference, surfaces);
            // And they are opaque: the material transparency is not theirs.
            inline for (.{ "popover", "menu", "select", "modal" }) |name| try std.testing.expectEqual(@as(u8, 255), @field(surfaces, name).getBackground().a);
            // Retheme while open as well.
            _ = theme.setMaterialParameters(100 - transparency, 0);
            const again = theme.widgetTheme(theme.currentName());
            bare.publish.publish(bare.cx, again);
            app.publish.publish(app.cx, again);
            bare.frame();
            app.frame();
            try NativeSurfaces.expectSame(reference, surfaces);
        }
    }
    try std.testing.expect(palettes > 3);
}

test "visible region ignores content clipped by a collapsed accordion" {
    const w = try Window.init();
    defer w.deinit();
    const clip = try ui.box(w.cx, .{ .width = .{ .px = 300 }, .height = .{ .px = 0 }, .overflow_hidden = true }, .{});
    const child = try ui.box(w.cx, .{ .width = .{ .px = 200 }, .height = .{ .px = 60 } }, .{});
    try clip.appendChild(w.cx.allocator, child);
    try w.cx.root.?.appendChild(w.cx.allocator, clip);
    w.frame();
    try std.testing.expect(@import("../styles/visible_region.zig").snapshot(w.cx, child) == null);
    clip.setStyle(w.cx.allocator, .height, .{ .px = 60 });
    w.frame();
    try std.testing.expect(@import("../styles/visible_region.zig").snapshot(w.cx, child) != null);
}

test "a native popover stays readable over video and terminal content at every material setting" {
    // Whatever is behind it (remote video, terminal output), the native Popover panel is opaque:
    // its text never depends on the pixels below. Nothing has to detect such backdrops.
    const previous = theme.currentName();
    const parameters = theme.materialParameters();
    defer {
        theme.select(previous);
        _ = theme.setMaterialParameters(parameters.transparency, parameters.blur);
    }
    const w = try Window.init();
    defer w.deinit();
    const open = try w.scope.createSignal(bool, true);
    const menu = try ui.widgets.Popover(.{ .open = open, .trigger = .manual, .enter_transition = .none, .exit_transition = .none, .width = 200 }).mount(w.scope, w.cx);
    try menu.content.appendChild(w.cx.allocator, try ui.text(w.cx, "Readable menu", .{}));
    try w.cx.root.?.appendChild(w.cx.allocator, menu.wrapper);
    const contrast = @import("../theme/theme_states.zig").contrast;
    for (@import("../../../config/theme_presets.zig").ids) |id| {
        theme.selectTokens(@import("../../../config/theme_registry.zig").builtinTokens(id));
        for ([_]f32{ 0, 75, 100 }) |t| {
            _ = theme.setMaterialParameters(t, 0);
            w.publish.publish(w.cx, theme.widgetTheme(theme.currentName()));
            w.frame();
            const fill = menu.chrome.getBackground();
            try std.testing.expectEqual(@as(u8, 255), fill.a);
            const base = theme.baseColors();
            for ([_]ui.Color{ base.fg_1, base.fg_2 }) |ink| try std.testing.expect(contrast(fill, ink) >= 4.5);
        }
    }
}

test "anchor transition flight layer stays unpainted (window stays visible mid flight)" {
    const w = try Window.init();
    defer w.deinit();
    const card = try ui.boxStyled(w.cx, overlayPanel, .{});
    card.setStyleInline(w.cx.allocator, .{ .position = .absolute, .inset = .{ .left = .{ .px = 600 }, .top = .{ .px = 200 } } });
    try w.cx.root.?.appendChild(w.cx.allocator, card);
    w.frame();
    const t = try ui.fx.AnchorTransition.create(w.cx, card, .{});
    defer t.destroy();
    t.collapse(.{ .rect = .{ .x = 1360, .y = 830, .w = 48, .h = 48 } });
    // One frame in: the full-window flight layer exists while the card folds.
    w.cx.frame_count += 1;
    w.cx.frame_time_ms += 16;
    _ = w.cx.render();
    try std.testing.expectEqual(ui.fx.anchor_transition.Phase.collapsing, t.phase());
    var found = false;
    for (w.cx.overlay_stack.layers.items) |slot| if (slot) |layer| if (layer.content_node) |node| {
        if (!std.mem.eql(u8, node.meta.ownership.meta.component_name orelse "", "AnchorTransitionLayer")) continue;
        found = true;
        // Painting it as overlay chrome would cover the whole window (blank window mid flight).
        try std.testing.expectEqual(@as(u8, 0), node.getBackground().a);
        try std.testing.expect(node.style.glass_params() == null);
    };
    try std.testing.expect(found);
}

const Window = struct {
    cx: *ui.Cx,
    scope: *ui.Scope,
    publish: *publication,
    fn init() !Window {
        const cx = try ui.Cx.init(std.testing.allocator, std.testing.io);
        errdefer cx.deinit();
        cx.setViewport(1440, 900);
        const scope = try ui.Scope.init(std.testing.allocator, null, cx.owner);
        errdefer scope.dispose();
        cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
        const publish = try cx.bindState(publication, .{});
        publish.publish(cx, theme.widgetTheme(theme.currentName()));
        return .{ .cx = cx, .scope = scope, .publish = publish };
    }
    fn frame(self: Window) void {
        for (0..6) |_| {
            self.cx.frame_count += 1;
            self.cx.frame_time_ms += 16;
            _ = self.cx.render();
        }
    }
    fn apply(self: Window, name: theme.Name, material: bool) void {
        theme.select(name);
        _ = theme.setMaterialVisible(material);
        self.publish.publish(self.cx, theme.widgetTheme(name));
        self.frame();
    }
    fn deinit(self: Window) void {
        self.scope.dispose();
        self.cx.deinit();
    }
};

const Receipt = struct {
    calls: usize = 0,
    id: @import("../../../host/session_lifecycle.zig").SessionId = 0,
    accepted: bool = false,
    fn resolve(raw: *anyopaque, id: @import("../../../host/session_lifecycle.zig").SessionId, accepted: bool) void {
        const self: *Receipt = @ptrCast(@alignCast(raw));
        self.calls += 1;
        self.id = id;
        self.accepted = accepted;
    }
};

test "global appearance retained local close follows hidden and visible theme publication without resolving" {
    const previous = theme.currentName();
    const material = theme.materialVisible();
    defer {
        theme.select(previous);
        _ = theme.setMaterialVisible(material);
    }
    theme.select(.dark);
    _ = theme.setMaterialVisible(false);
    const w = try Window.init();
    defer w.deinit();
    var receipt: Receipt = .{};
    const view = try Close.View.mount(w.cx, w.scope, .{ .context = &receipt, .resolve = Receipt.resolve });
    w.frame();
    const identity_id = view.identity.id;
    w.apply(.light, false);
    try view.show(410, null);
    w.frame();
    try std.testing.expectEqual(theme.current().fg_1, view.identity.getText().?.color);
    try std.testing.expectEqual(theme.current().fg_1, view.risk_title.getText().?.color);
    try std.testing.expectEqual(theme.current().fg_2, view.risk_detail.getText().?.color);
    try std.testing.expectEqual(theme.current().fg_2, view.extra_text.getText().?.color);
    const focus = w.cx.focus_manager.getFocused();
    w.apply(.sauber, true);
    try std.testing.expectEqual(w.cx.tokens.tokens.color.bg_primary, view.dialog.getBackground()); // zenit Modal default panel
    try std.testing.expectEqual(theme.popupAction().withAlpha(255), view.risk.getBackground());
    try std.testing.expectEqual(theme.current().fg_1, view.identity.getText().?.color);
    try std.testing.expectEqual(identity_id, view.identity.id);
    try std.testing.expectEqual(focus, w.cx.focus_manager.getFocused());
    try std.testing.expectEqual(@as(?@import("../../../host/session_lifecycle.zig").SessionId, 410), view.session);
    try std.testing.expectEqual(@as(usize, 0), receipt.calls);
    try std.testing.expectEqual(@as(f32, 480), view.dialog.globalRect().w);
    w.apply(.dark, false);
    try std.testing.expectEqual(w.cx.tokens.tokens.color.bg_primary, view.dialog.getBackground()); // zenit Modal default panel
    try std.testing.expectEqual(theme.current().fg_1, view.risk_title.getText().?.color);
    for (@import("../../../config/theme_presets.zig").ids) |id| {
        theme.selectTokens(@import("../../../config/theme_registry.zig").builtinTokens(id));
        w.publish.publish(w.cx, theme.widgetTheme(theme.currentName()));
        w.frame();
        try std.testing.expectEqual(w.cx.tokens.tokens.color.bg_primary, view.dialog.getBackground()); // zenit Modal default panel
        try std.testing.expectEqual(theme.current().fg_1, view.identity.getText().?.color);
        try std.testing.expectEqual(theme.popupAction().withAlpha(255), view.risk.getBackground());
        try std.testing.expectEqual(identity_id, view.identity.id);
        try std.testing.expectEqual(@as(usize, 0), receipt.calls);
    }
    view.cancel();
    try std.testing.expectEqual(@as(usize, 1), receipt.calls);
    try std.testing.expectEqual(@as(@import("../../../host/session_lifecycle.zig").SessionId, 410), receipt.id);
    try std.testing.expect(!receipt.accepted);
}

test "global appearance transfer confirmation repaint keeps captured intent and edited options" {
    const previous = theme.currentName();
    const material = theme.materialVisible();
    defer {
        theme.select(previous);
        _ = theme.setMaterialVisible(material);
    }
    theme.select(.dark);
    _ = theme.setMaterialVisible(false);
    const w = try Window.init();
    defer w.deinit();
    var panel: Transfer.Panel = .{};
    const root = try panel.mount(w.cx, w.scope);
    try w.cx.root.?.appendChild(w.cx.allocator, root);
    const owner: @import("../../../host/identity.zig").SessionHandle = .{ .session_id = @fromBackingInt(99), .generation = 7 };
    panel.show(.{ .mode = .download, .owner = owner, .endpoint = "original-host", .host_name = "Original", .sources = &.{"/immutable.bin"}, .local_dir = "/owned", .md5 = false });
    w.frame();
    const md5 = findText(panel.card, "MD5 校验") orelse return error.MissingMd5Control;
    const rect = md5.globalRect();
    w.cx.handleMouseDown(rect.x + rect.w / 2, rect.y + rect.h / 2, .{});
    w.cx.handleMouseUp(rect.x + rect.w / 2, rect.y + rect.h / 2);
    w.frame();
    try std.testing.expect(panel.md5);
    panel.rename_sig.set("kept.bin");
    w.cx.setFocus(panel.local_input.input_container);
    const focus = w.cx.focus_manager.getFocused();
    const node_id = panel.card.id;
    w.apply(.light, true);
    // This is the production main appearance-publication integration point.
    panel.retheme();
    w.frame();
    try std.testing.expectEqual(theme.current().overlay, panel.card.getBackground());
    try std.testing.expectEqual(theme.current().fg_1, panel.title.getText().?.color);
    try std.testing.expectEqual(node_id, panel.card.id);
    try std.testing.expectEqual(focus, w.cx.focus_manager.getFocused());
    try std.testing.expectEqual(owner, panel.captured_owner.?);
    try std.testing.expectEqualStrings("kept.bin", panel.rename_sig.peek());
    try std.testing.expect(panel.md5);
    try std.testing.expectEqualStrings("/owned", panel.local_dir_sig.peek());
    try std.testing.expect(panel.isVisible());
}

fn findText(node: *ui.Node, text: []const u8) ?*ui.Node {
    if (node.getText()) |value| if (std.mem.eql(u8, value.content, text)) return node;
    for (node.children.items) |child| if (findText(child, text)) |found| return found;
    return null;
}

test {
    _ = @import("../theme/app_theme.zig");
    _ = @import("../../../features/shell/view/shell_styles.zig");
    _ = @import("../../../features/shell/tests/status_detail_tests.zig");
    _ = @import("auxiliary_appearance_tests.zig");
}

test "global appearance worker frame default text repaints while ANSI and archived history stay intact" {
    const Terminal = @import("../../../features/terminal/view/terminal_view.zig").TerminalViewNode;
    const Slot = @import("../../../vt/text_slot.zig").TextSlot;
    const Wire = @import("../../../vt/text_frame.zig");
    const Styled = @import("../../../vt/text_projection_styled.zig");
    const previous = theme.currentName();
    const material = theme.materialVisible();
    defer {
        theme.select(previous);
        _ = theme.setMaterialVisible(material);
    }
    theme.select(.dark);
    _ = theme.setMaterialVisible(false);
    const w = try Window.init();
    defer w.deinit();
    var view = try Terminal.mount(w.cx);
    defer view.releaseBuffers(w.cx);
    try w.cx.root.?.appendChild(w.cx.allocator, view.root);
    view.setThemeColors(theme.current().fg_1, theme.current().border, theme.current().accent);
    var slot = try Slot.init(std.testing.allocator, 512);
    defer slot.deinit(std.testing.allocator);
    var header: [Wire.header_bytes]u8 = undefined;
    var span_bytes: [Wire.span_wire_bytes]u8 = undefined;
    const span: Styled.Span = .{ .start = 6, .end = 9, .color = 0xff0000ff, .bg = 0 };
    Wire.encodeSpans(&span_bytes, &.{span});
    var scratch: [512]u8 align(4) = undefined;
    var seen: u64 = 0;
    for ([_][]const u8{ "plain red\nfirst", "plain red\nlatest" }) |text| {
        Wire.encodeHeader(&header, .{}, 40, 2, 1, text.len);
        _ = try slot.publishParts(&.{ &header, &span_bytes, text });
        try std.testing.expect(try view.consumeText(w.cx, &slot, &seen, &scratch));
    }
    w.frame();
    const row = view.row_nodes[0].?;
    const row_id = row.id;
    try std.testing.expectEqual(theme.current().fg_1, row.getText().?.color);
    try std.testing.expect(hasRed(row));
    view.bindArchived();
    try std.testing.expect(view.openHistory());
    w.frame();
    const history_selected = view.history.selected;
    const text_before = try std.testing.allocator.dupe(u8, row.getText().?.content);
    defer std.testing.allocator.free(text_before);
    const focus = w.cx.focus_manager.getFocused();
    w.apply(.light, true);
    // Same in-place call used by the main global publication for SSH tabs.
    view.setThemeColors(theme.current().fg_1, theme.current().border, theme.current().accent);
    w.frame();
    try std.testing.expectEqual(theme.current().fg_1, row.getText().?.color);
    try std.testing.expectEqual(row_id, row.id);
    try std.testing.expectEqualStrings(text_before, row.getText().?.content);
    try std.testing.expect(hasRed(row));
    try std.testing.expectEqual(history_selected, view.history.selected);
    try std.testing.expectEqual(focus, w.cx.focus_manager.getFocused());
    try std.testing.expect(!view.tombstone.allowsRemoteInput());
}

fn hasRed(node: *ui.Node) bool {
    const props = node.getText() orelse return false;
    for (props.spans) |span| if (span.color) |color| if (ui.Color.eql(color, ui.Color.rgb(255, 0, 0))) return true;
    return false;
}

fn materialPatchTransmission(root: *ui.Node, x: f32, y: f32, transmission: *f32) usize {
    var count: usize = 0;
    for (root.children.items) |patch| {
        if (patch.style.display == .none) continue;
        const r = patch.globalRect();
        if (x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h) {
            transmission.* *= 1 - @as(f32, @floatFromInt(patch.getBackground().a)) / 255;
            count += 1;
        }
    }
    return count;
}

test "a retained panel replays missed themes before first open and after collapse" {
    const previous = theme.currentName();
    const parameters = theme.materialParameters();
    defer {
        theme.select(previous);
        _ = theme.setMaterialParameters(parameters.transparency, parameters.blur);
    }
    theme.select(.dark);
    _ = theme.setMaterialParameters(0, 0);
    const w = try Window.init();
    defer w.deinit();
    const holder = try ui.box(w.cx, .{ .position = .absolute, .width = .{ .px = 600 }, .height = .{ .px = 456 } }, .{});
    const assistant = try ui.boxStyled(w.cx, overlayPanel, .{});
    const title = try ui.textStyled(w.cx, @import("../../../features/ai/pane/view/ai_assistant_styles.zig").title, "AI 助手");
    try assistant.appendChild(w.cx.allocator, title);
    const draft = try w.scope.createText("保留草稿", .{});
    const editor = try ui.widgets.Textarea(.{ .value = draft, .embedded = true, .rows = 1 }).mountResult(w.scope, w.cx);
    @import("../../../features/ai/composer/view/ai_composer_sizing.zig").configure(editor);
    try @import("../../../features/ai/composer/view/ai_composer_sizing.zig").bindTheme(w.cx, w.scope, editor);
    try assistant.appendChild(w.cx.allocator, editor.wrapper);
    try holder.appendChild(w.cx.allocator, assistant);
    try w.cx.root.?.appendChild(w.cx.allocator, holder);
    // A closed panel's content is parked outside the window (`surface_migration`) and misses the
    // theme switches made meanwhile; putting it back replays the theme once.
    const surface_migration = @import("../surface/surface_migration.zig");
    const window_root = w.cx.root.?;
    try surface_migration.own(w.scope, w.cx, holder);
    surface_migration.park(w.cx, holder);
    const identity = assistant.id;
    for ([_]theme.Name{ .light, .sauber, .dark }) |name| {
        theme.select(name);
        _ = theme.setMaterialParameters(75, 24);
        w.publish.publish(w.cx, theme.widgetTheme(name));
        try surface_migration.move(w.cx, holder, .{ .parent = window_root });
        const published_version = w.cx.theme_version;
        w.frame();
        try std.testing.expectEqual(published_version, w.cx.theme_version);
        // The panel's own named style is replayed (its declared fill and blur), nothing else paints it.
        try std.testing.expectEqual(theme.current().overlay, assistant.getBackground());
        try std.testing.expectEqual(theme.current().fg_1, title.getText().?.color);
        try std.testing.expectEqual(@as(f32, 24), assistant.style.backdrop_blur());
        try std.testing.expectEqual(identity, assistant.id);
        try std.testing.expectEqualStrings("保留草稿", draft.peek());
        try std.testing.expectEqual(theme.current().fg_1, editor.state.tokens.tokens.color.fg_primary);
        try std.testing.expectEqual(theme.current().fg_1, findText(editor.wrapper, "保留草稿").?.getText().?.color);
        surface_migration.park(w.cx, holder);
        w.frame();
        try std.testing.expect(holder.parent == null);
    }
}

test "production recovery, inventory, image, code and risk cards declare their own fills" {
    const previous = theme.currentName();
    const parameters = theme.materialParameters();
    defer {
        theme.select(previous);
        _ = theme.setMaterialParameters(parameters.transparency, parameters.blur);
    }
    const w = try Window.init();
    defer w.deinit();
    w.cx.setViewport(1440, 1600);
    const assistant = try ui.boxStyled(w.cx, overlayPanel, .{});
    try w.cx.root.?.appendChild(w.cx.allocator, assistant);
    const Callbacks = struct {
        fn recover(_: *anyopaque, _: @import("../../../features/ai/cards/view/ai_recovery_view.zig").Envelope) void {}
        fn close(_: *anyopaque, _: @import("../../../host/session_lifecycle.zig").SessionId, _: bool) void {}
        fn inventory(_: *anyopaque, _: @import("../../../ai/inventory_approval.zig").Ticket, _: @import("../../../ai/inventory_approval.zig").Decision) !void {}
        fn preview(_: *anyopaque, _: @import("../../../ai/image_attachments.zig").ContentRef) !void {}
    };
    const recovery = try @import("../../../features/ai/cards/view/ai_recovery_view.zig").mount(w.cx, w.scope, .{ .ticket = .{ .owner = .{ .tab = 1 }, .turn = 1 }, .reason = "请求失败", .retries = 0, .max_retries = 3, .retry_enabled = true, .regenerate_enabled = false, .cooldown_seconds = 0 }, .{ .context = w.cx, .enqueue = Callbacks.recover });
    try assistant.appendChild(w.cx.allocator, recovery);
    const inventory = try @import("../../../features/ai/approvals/view/ai_inventory_grant_view.zig").View.mount(w.cx, w.scope, .{ .context = w.cx, .on_decision = Callbacks.inventory });
    inventory.root.setDisplay(.flex);
    try assistant.appendChild(w.cx.allocator, inventory.root);
    const images = @import("../../../features/ai/attachments/view/ai_transcript_images.zig");
    var store: images.Store = .{ .allocator = w.cx.allocator };
    defer store.deinit();
    const image_card = try images.mount(w.cx, w.scope, .{ .store = &store, .source = null, .conversation = 1, .turn = 1, .app = null, .preview_context = w.cx, .preview = Callbacks.preview }, .{ .start = 0, .end = 1, .alt = "", .path = "/fixture.png" }, 570);
    try assistant.appendChild(w.cx.allocator, image_card);
    const message = try @import("../../../features/ai/pane/view/ai_message_view.zig").mountCode(w.cx, w.scope, "printf hello", "sh");
    try assistant.appendChild(w.cx.allocator, message);
    const code = findLayerTestNode(message, "ai.message.code").?;
    const close = try Close.View.mount(w.cx, w.scope, .{ .context = w.cx, .resolve = Callbacks.close });
    try close.show(1, null);
    var terminal = try @import("../../../features/terminal/view/terminal_view.zig").TerminalViewNode.mount(w.cx);
    defer terminal.releaseBuffers(w.cx);
    try w.cx.root.?.appendChild(w.cx.allocator, terminal.root);
    try terminal.attachSearch(w.scope);
    terminal.history_bar.?.setDisplay(.flex);
    for ([_]theme.Name{ .dark, .light, .sauber }) |name| {
        for ([_]f32{ 0, 25, 75, 100 }) |t| {
            theme.select(name);
            _ = theme.setMaterialParameters(t, 24);
            w.publish.publish(w.cx, theme.widgetTheme(name));
            assistant.setStyleInline(w.cx.allocator, .{ .height = .{ .px = 1300 } });
            w.frame();
            // First-layer cards on the assistant pane (opaque when the transparency setting is zero).
            const action = theme.popupAction().withAlpha(theme.layerAlpha(1));
            const control = theme.popupInset().withAlpha(theme.layerAlpha(1));
            // Recovery is the native danger Alert (Kaf7E A9, user decision): zenit's own fill.
            try std.testing.expect(ui.Color.eql(recovery.getBackground(), w.cx.tokens.tokens.color.danger_alert_bg));
            try std.testing.expectEqual(action, inventory.root.getBackground());
            try std.testing.expectEqual(control, image_card.getBackground());
            // Code is the native W.CodeBlock (Kaf7E A4): bg_secondary, fg_primary code, fg_tertiary label.
            const k = w.cx.tokens.tokens.color;
            try std.testing.expect(ui.Color.eql(k.bg_secondary, code.getBackground()));
            try std.testing.expect(ui.Color.eql(k.fg_primary, findLayerTestNode(code, "ai.message.code.text").?.getText().?.color));
            try std.testing.expect(ui.Color.eql(k.fg_tertiary, findLayerTestNode(code, "ai.message.code.language").?.getText().?.color));
            // The risk card sits inside the native confirmation Modal: opaque at every setting.
            try std.testing.expectEqual(theme.popupAction().withAlpha(255), close.risk.getBackground());
            try std.testing.expectEqual(theme.current().surface_1.withAlpha(theme.layerAlpha(1)), terminal.history_bar.?.getBackground());
            try std.testing.expectEqual(@as(u8, 255), findLayerTestNode(recovery, "ai.recovery.title").?.getText().?.color.a);
        }
    }
}

fn findLayerTestNode(node: *ui.Node, id: []const u8) ?*ui.Node {
    if (node.meta.ownership.meta.test_id) |value| if (std.mem.eql(u8, value, id)) return node;
    for (node.children.items) |child| if (findLayerTestNode(child, id)) |found| return found;
    return null;
}

/// An overlay-material panel the size of the former AI floating panel (the material policy fixture;
/// the AI panel itself is now the unified floating chrome on a native floating Card).
fn overlayPanel(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .hit_behavior = .@"opaque", .width = .{ .px = 600 }, .height = .{ .px = 456 }, .direction = .column, .padding = ui.Padding.all(1), .background = theme.current().overlay, .glass = theme.overlayGlass(), .border = .{ .width = 0, .radius = 14 }, .shadows = ui.ShadowList.of(&.{.{ .color = ui.Color.rgba(0, 0, 0, 119), .blur = 48, .offset_y = 18 }}), .overflow = .hidden };
}
