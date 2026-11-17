const std = @import("std");
const ui = @import("ui");
const m = @import("../view/socks_config_view.zig");
const C = struct { saved: usize = 0, tested: usize = 0, cancelled: usize = 0, exposure: bool = false };
test "forwarding switches are native sm switches that follow the published switch roles" {
    const theme = @import("../../../../shared/ui/theme/app_theme.zig");
    defer theme.select(.sauber);
    const cx = try ui.Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    cx.setViewport(800, 700);
    const scope = try ui.Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    const root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    cx.root = root;
    var c: C = .{};
    var publication: @import("../../../shell/view/shell_styles.zig").ThemePublication = .{};
    // Switch roles are zenit defaults, identical for the three (dark) palettes below.
    // Mount under the first one so the assertions see the published role rather
    // than a mount-time light → dark recolour transition (order dependent in the
    // full suite: it can be left mid-way, the upstream-candidate noted below).
    theme.selectTokens(@import("../../../../config/theme_registry.zig").builtinTokens("forest"));
    publication.publish(cx, theme.widgetTheme(theme.currentName()));
    const v = try m.View.mount(cx, scope, .{ .context = &c, .save = save, .test_cb = test_cb, .cancel = cancel, .confirm_exposure = exposure });
    if (!v.portaled) try root.appendChild(cx.allocator, v.root);
    for ([_][]const u8{ "forest", "plum", "sand" }) |id| {
        theme.selectTokens(@import("../../../../config/theme_registry.zig").builtinTokens(id));
        publication.publish(cx, theme.widgetTheme(theme.currentName()));
        try v.show(.{ .auto_start = false, .persist = true }, &.{});
        cx.layout();
        settle(cx); // theme replay and recipe transitions land with rendered frames
        const t = cx.tokens.tokens;
        const off_track = v.auto.children.items[0];
        const on_track = v.persist.children.items[0];
        // zenit Switch `.size = .sm`: track switch-width-sm × switch-height-sm, thumb switch-thumb-sm.
        try std.testing.expectEqual(t.size.switch_width_sm, off_track.style.width.px);
        try std.testing.expectEqual(t.size.switch_height_sm, off_track.style.height.px);
        try std.testing.expectEqual(t.size.switch_thumb_sm, off_track.children.items[0].style.width.px);
        try std.testing.expectEqual(t.color.switch_track_off, switchBackground(off_track));
        try std.testing.expectEqual(t.color.switch_track_on, switchBackground(on_track));
        // Positioned by the recipe's translate only (no inline inset).
        try std.testing.expect(off_track.children.items[0].style.ext == null or off_track.children.items[0].style.ext.?.inset.left == .auto);
        try std.testing.expectEqual(@as(f32, 2), switchTranslate(off_track.children.items[0]));
        try std.testing.expectEqual(t.size.switch_width_sm - t.size.switch_thumb_sm - 2, switchTranslate(on_track.children.items[0]));
        try v.show(.{ .auto_start = true, .persist = false }, &.{});
        cx.layout();
        settle(cx);
        try std.testing.expectEqual(t.color.switch_track_on, switchBackground(off_track));
        try std.testing.expectEqual(t.color.switch_track_off, switchBackground(on_track));
        try std.testing.expectEqual(t.size.switch_width_sm - t.size.switch_thumb_sm - 2, switchTranslate(off_track.children.items[0]));
        try std.testing.expectEqual(@as(f32, 2), switchTranslate(on_track.children.items[0]));
    }
}
// G23: View.mount/retheme repaint the card's retained fills by walking the subtree. Writing a
// native Switch track's background there landed in its style host's inline layer and pinned the
// mount-time fill above the recipe (the app publishes its theme before mounting, so every
// palette pinned; in-suite only after a test left `.dark` selected). The track must keep
// following `checked` whatever palette was selected at mount and across a palette change.
test "forwarding switch tracks keep following checked after the retained palette repaint" {
    const theme = @import("../../../../shared/ui/theme/app_theme.zig");
    defer theme.select(.sauber);
    for ([_]theme.Name{ .dark, .light, .sauber }) |mounted| for ([_]bool{ false, true }) |change_palette| {
        theme.select(mounted);
        const cx = try ui.Cx.init(std.testing.allocator, std.testing.io);
        defer cx.deinit();
        cx.setViewport(800, 700);
        const scope = try ui.Scope.init(std.testing.allocator, null, cx.owner);
        defer scope.dispose();
        const root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
        cx.root = root;
        var c: C = .{};
        var publication: @import("../../../shell/view/shell_styles.zig").ThemePublication = .{};
        publication.publish(cx, theme.widgetTheme(theme.currentName()));
        const v = try m.View.mount(cx, scope, .{ .context = &c, .save = save, .test_cb = test_cb, .cancel = cancel, .confirm_exposure = exposure });
        if (!v.portaled) try root.appendChild(cx.allocator, v.root);
        const track = v.persist.children.items[0];
        try v.show(.{ .auto_start = false, .persist = true }, &.{});
        cx.layout();
        settle(cx);
        try std.testing.expectEqual(cx.tokens.tokens.color.switch_track_on, switchBackground(track));
        if (change_palette) {
            theme.selectTokens(@import("../../../../config/theme_registry.zig").builtinTokens("forest"));
            publication.publish(cx, theme.widgetTheme(theme.currentName()));
            cx.layout();
            settle(cx);
            try std.testing.expectEqual(cx.tokens.tokens.color.switch_track_on, switchBackground(track));
        }
        try v.show(.{ .auto_start = false, .persist = false }, &.{});
        cx.layout();
        settle(cx);
        try std.testing.expectEqual(cx.tokens.tokens.color.switch_track_off, switchBackground(track));
        // The repaint left the recipe in charge: no inline background on the track's style host.
        try std.testing.expect(ui.view.styleHostStateForTest(track).?.inline_decl.background == null);
    };
}
// G26: zenit's default Switch "on" track (#4F5ED9) equals the light palette's accent roles, so
// the colour remap of the retained repaint took the native track for a ZeroWork fill and wrote
// the next palette's accent into its inline layer. Native components are never repainted.
test "forwarding switch tracks keep zenit roles when a light-mounted view changes palette" {
    const theme = @import("../../../../shared/ui/theme/app_theme.zig");
    const registry = @import("../../../../config/theme_registry.zig");
    defer theme.select(.sauber);
    for ([_][]const u8{ "forest", "plum", "sand", "dark" }) |next| {
        theme.select(.light);
        const cx = try ui.Cx.init(std.testing.allocator, std.testing.io);
        defer cx.deinit();
        cx.setViewport(800, 700);
        const scope = try ui.Scope.init(std.testing.allocator, null, cx.owner);
        defer scope.dispose();
        const root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
        cx.root = root;
        var c: C = .{};
        var publication: @import("../../../shell/view/shell_styles.zig").ThemePublication = .{};
        publication.publish(cx, theme.widgetTheme(theme.currentName()));
        // The collision this guards: a native recipe fill equal to an old palette role.
        try std.testing.expect(isRole(theme.current(), cx.tokens.tokens.color.switch_track_on));
        const v = try m.View.mount(cx, scope, .{ .context = &c, .save = save, .test_cb = test_cb, .cancel = cancel, .confirm_exposure = exposure });
        if (!v.portaled) try root.appendChild(cx.allocator, v.root);
        const off_track = v.auto.children.items[0];
        const on_track = v.persist.children.items[0];
        try v.show(.{ .auto_start = false, .persist = true }, &.{});
        cx.layout();
        settle(cx);
        theme.selectTokens(registry.builtinTokens(next));
        publication.publish(cx, theme.widgetTheme(theme.currentName()));
        cx.layout();
        settle(cx);
        for ([_]bool{ false, true }) |flipped| {
            if (flipped) {
                try v.show(.{ .auto_start = true, .persist = false }, &.{});
                cx.layout();
                settle(cx);
            }
            const t = cx.tokens.tokens.color;
            try std.testing.expectEqual(if (flipped) t.switch_track_on else t.switch_track_off, switchBackground(off_track));
            try std.testing.expectEqual(if (flipped) t.switch_track_off else t.switch_track_on, switchBackground(on_track));
            for ([_]*ui.Node{ off_track, on_track }) |track| try std.testing.expect(ui.view.styleHostStateForTest(track).?.inline_decl.background == null);
        }
    }
}
// The retained repaint leaves every node of a native Switch, Button and Input to zenit, even
// when their recipe fills equal roles of the palette being replaced.
test "socks retained palette repaint never writes native switch button or input fills" {
    const theme = @import("../../../../shared/ui/theme/app_theme.zig");
    const registry = @import("../../../../config/theme_registry.zig");
    const S = @import("../view/socks_config_styles.zig");
    defer theme.select(.sauber);
    theme.select(.light);
    const cx = try ui.Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    cx.setViewport(800, 700);
    const scope = try ui.Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    const root = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .direction = .column, .gap = 8 }, .{});
    cx.root = root;
    var publication: @import("../../../shell/view/shell_styles.zig").ThemePublication = .{};
    publication.publish(cx, theme.widgetTheme(theme.currentName()));
    const on = try scope.createSignal(bool, true);
    const off = try scope.createSignal(bool, false);
    const switch_on = try ui.widgets.Switch(.{ .checked = on, .size = .sm }).mount(scope, cx);
    const switch_off = try ui.widgets.Switch(.{ .checked = off, .size = .sm }).mount(scope, cx);
    const primary = try ui.widgets.Button(.{ .label = "保存", .variant = @as(ui.widgets.button.ButtonVariant, .primary) }).mount(scope, cx);
    const secondary = try ui.widgets.Button(.{ .label = "取消", .variant = @as(ui.widgets.button.ButtonVariant, .secondary) }).mount(scope, cx);
    const input = try ui.widgets.Input(.{}).mountResult(scope, cx);
    for ([_]*ui.Node{ switch_on, switch_off, primary, secondary, input.node }) |node| try root.appendChild(cx.allocator, node);
    cx.layout();
    settle(cx);
    const light = theme.current();
    // Preconditions: each control draws a fill the light palette also names.
    try std.testing.expect(isRole(light, switchBackground(switch_on.children.items[0])));
    try std.testing.expect(isRole(light, switchBackground(input.input_container)));
    theme.selectTokens(registry.builtinTokens("forest"));
    publication.publish(cx, theme.widgetTheme(theme.currentName()));
    S.repaint(root, light);
    cx.layout();
    settle(cx);
    const t = cx.tokens.tokens.color;
    try std.testing.expectEqual(t.switch_track_on, switchBackground(switch_on.children.items[0]));
    try std.testing.expectEqual(t.switch_track_off, switchBackground(switch_off.children.items[0]));
    on.set(false);
    off.set(true);
    cx.layout();
    settle(cx);
    try std.testing.expectEqual(t.switch_track_off, switchBackground(switch_on.children.items[0]));
    try std.testing.expectEqual(t.switch_track_on, switchBackground(switch_off.children.items[0]));
    for ([_]*ui.Node{ switch_on, switch_off, primary, secondary, input.node }) |node| try expectNoInlineBackground(node);
}
fn isRole(colors: anytype, color: ui.Color) bool {
    inline for (@typeInfo(@TypeOf(colors)).@"struct".field_names) |role| if (ui.Color.eql(@field(colors, role), color)) return true;
    return false;
}
fn expectNoInlineBackground(node: *ui.Node) !void {
    if (ui.view.styleHostStateForTest(node)) |host| try std.testing.expect(host.inline_decl.background == null);
    for (node.children.items) |child| try expectNoInlineBackground(child);
}
fn switchTranslate(node: *ui.Node) f32 {
    if (node.frame_state.frame_local.runtime.transitions) |slots| if (slots.find(.translate_x)) |slot| {
        if (slot.active) return slot.to_value;
    };
    return node.style.translate_x;
}
fn switchBackground(node: *ui.Node) ui.Color {
    if (node.frame_state.frame_local.runtime.transitions) |slots| if (slots.find(.background)) |slot| {
        if (slot.active) return slot.to_color;
    };
    return node.getBackground();
}
fn save(p: *anyopaque, d: m.Draft) void {
    _ = d;
    @as(*C, @ptrCast(@alignCast(p))).saved += 1;
}
fn test_cb(p: *anyopaque, d: m.Draft) void {
    _ = d;
    @as(*C, @ptrCast(@alignCast(p))).tested += 1;
}
fn cancel(p: *anyopaque) void {
    @as(*C, @ptrCast(@alignCast(p))).cancelled += 1;
}
fn exposure(p: *anyopaque, _: []const u8) bool {
    return @as(*C, @ptrCast(@alignCast(p))).exposure;
}
test "config modal mounts and checks exposure gate" {
    const cx = try ui.Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    cx.setViewport(600, 420);
    const scope = try ui.Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    const root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    cx.root = root;
    var c = C{};
    const v = try m.View.mount(cx, scope, .{ .context = @ptrCast(&c), .save = save, .test_cb = test_cb, .cancel = cancel, .confirm_exposure = exposure });
    if (!v.portaled) try root.appendChild(cx.allocator, v.root);
    try v.show(.{}, &.{});
    cx.layout();
    try std.testing.expect(v.root.style.display == .flex);
    v.bind_signal.set("0.0.0.0");
    v.draft.port = 1080;
    v.act(.save);
    try std.testing.expectEqual(@as(usize, 0), c.saved);
    c.exposure = true;
    v.act(.save);
    try std.testing.expectEqual(@as(usize, 1), c.saved);
    v.act(.cancel);
    try std.testing.expectEqual(@as(usize, 1), c.cancelled);
}

test "config owns routes and draft, validates inputs, resizes and cancels locally" {
    const cx = try ui.Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    cx.setViewport(600, 420);
    const scope = try ui.Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    const root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    cx.root = root;
    var c = C{};
    const v = try m.View.mount(cx, scope, .{ .context = @ptrCast(&c), .save = save, .test_cb = test_cb, .cancel = cancel, .confirm_exposure = exposure });
    if (!v.portaled) try root.appendChild(cx.allocator, v.root);
    var label = [_]u8{'A'};
    const routes = [_]m.Route{ .{ .label = "末端", .index = null }, .{ .label = &label, .index = 0 } };
    const original = m.Draft{ .port = 2000 };
    try v.show(original, &routes);
    label[0] = 'B';
    try std.testing.expectEqualStrings("A", v.routes[1].label);
    v.selectRoute(1);
    try std.testing.expectEqual(@as(?usize, 0), v.draft.exit);
    v.port_signal.set("bad");
    v.act(.save);
    try std.testing.expectEqual(@as(usize, 0), c.saved);
    try std.testing.expect(v.error_label.style.display == .flex);
    v.port_signal.set("2345");
    v.max_signal.set("257");
    v.act(.save);
    try std.testing.expectEqual(@as(usize, 0), c.saved);
    try std.testing.expectEqualStrings("并发上限必须为 1–256", v.error_label.getText().?.content);
    v.max_signal.set("256");
    v.act(.test_proxy);
    try std.testing.expectEqual(@as(usize, 1), c.tested);
    for (0..4) |_| {
        cx.layout();
        _ = v.updateGeometry();
    }
    try std.testing.expect(v.card.globalRect().w <= 480.5);
    cx.setViewport(350, 200);
    for (0..4) |_| {
        cx.layout();
        _ = v.updateGeometry();
    }
    try std.testing.expect(v.card.globalRect().w <= 318.5);
    try std.testing.expect(v.scrolling.container.globalRect().h <= 130.5);
    v.act(.cancel);
    try std.testing.expectEqual(@as(u16, 2000), original.port);
    try std.testing.expectEqual(@as(usize, 0), c.saved);
}

test "configuration covers its owner and stays centered with fixed actions" {
    const cx = try ui.Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    cx.setViewport(1440, 900);
    const scope = try ui.Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    const root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    cx.root = root;
    var c = C{};
    const v = try m.View.mount(cx, scope, .{ .context = &c, .save = save, .test_cb = test_cb, .cancel = cancel, .confirm_exposure = exposure });
    if (!v.portaled) try root.appendChild(cx.allocator, v.root);
    v.setOwner("Owned multihop 3", 7);
    try v.show(.{}, &.{ .{ .label = "链路末端" }, .{ .label = "Owned multihop 1", .index = 0 } });
    for (0..8) |_| {
        cx.layout();
        _ = v.updateGeometry();
    }
    const overlay = v.root.globalRect();
    const card = v.card.globalRect();
    try std.testing.expectApproxEqAbs(@as(f32, 1440), overlay.w, 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 900), overlay.h, 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 480), card.w, 0.5);
    try std.testing.expect(card.h > 396 and card.h <= 650);
    try std.testing.expectApproxEqAbs(@as(f32, 720), card.x + card.w / 2, 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 450), card.y + card.h / 2, 0.5);
    try std.testing.expect(v.footer.globalRect().y >= card.y);
    try std.testing.expect(v.footer.globalRect().y + v.footer.globalRect().h <= card.y + card.h);
    try std.testing.expectEqualStrings("归属 Owned multihop 3 · 会话 #7", v.owner_label.getText().?.content);
    cx.setViewport(860, 480);
    for (0..8) |_| {
        cx.layout();
        _ = v.updateGeometry();
    }
    const small = v.card.globalRect();
    try std.testing.expect(small.h <= 448.5);
    try std.testing.expectApproxEqAbs(@as(f32, 430), small.x + small.w / 2, 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 240), small.y + small.h / 2, 0.5);
    try std.testing.expect(small.y >= 0 and small.y + small.h <= 480.5);
}

test "configuration changes global palette without replacing inputs or selected exit" {
    const theme = @import("../../../../shared/ui/theme/app_theme.zig");
    const previous = theme.currentName();
    defer theme.select(previous);
    theme.select(.dark);
    const cx = try ui.Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    try cx.setTestFrameStep(16);
    // Host entries bind the window clock before UI updates; this test drives
    // layout/geometry directly, so bind it here instead of inheriting the
    // process-wide clock an earlier test left behind.
    cx.bindFrameClock();
    // Production publication path (focus presentation is zenit's native default).
    const publication = try cx.bindState(@import("../../../shell/view/shell_styles.zig").ThemePublication, .{});
    publication.publish(cx, theme.widgetTheme(.dark));
    cx.setViewport(1440, 900);
    const scope = try ui.Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    const root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    cx.root = root;
    var c = C{};
    const v = try m.View.mount(cx, scope, .{ .context = &c, .save = save, .test_cb = test_cb, .cancel = cancel, .confirm_exposure = exposure });
    if (!v.portaled) try root.appendChild(cx.allocator, v.root);
    try v.show(.{ .port = 3456 }, &.{ .{ .label = "末端" }, .{ .label = "首跳", .index = 0 }, .{ .label = "中间跳", .index = 1 } });
    const original_input = v.input_parts[0].input_container;
    v.port_signal.set("4567");
    v.selectRoute(2);
    v.setSuccess("真实测试成功");
    inline for (.{ .light, .sauber, .dark }) |name| {
        theme.select(name);
        publication.publish(cx, theme.widgetTheme(name));
        for (0..8) |_| {
            cx.layout();
            _ = v.updateGeometry();
        }
        v.picker.open.?.set(true);
        for (0..4) |_| cx.layout();
        const first = findId(v.picker.panel, "socks.config.route.1").?;
        _ = first.behavior.events.on_event.?(.{ .click = .{ .x = 0, .y = 0 } }, first.behavior.events.event_context);
        try std.testing.expectEqual(@as(?usize, 0), v.draft.exit);
        v.picker.open.?.set(true);
        for (0..4) |_| cx.layout();
        const second = findId(v.picker.panel, "socks.config.route.2").?;
        _ = second.behavior.events.on_event.?(.{ .click = .{ .x = 0, .y = 0 } }, second.behavior.events.event_context);
        try std.testing.expectEqual(original_input, v.input_parts[0].input_container);
        try std.testing.expectEqualStrings("4567", v.port_signal.get());
        try std.testing.expectEqual(@as(?usize, 1), v.draft.exit);
        try std.testing.expectEqualStrings("2", v.route_value.get().?);
        try std.testing.expect(ui.Color.eql(theme.current().fg_1, ui.widgets.select.stateOf(v.picker).colors.text_primary));
        try std.testing.expect(ui.Color.eql(v.cx.tokens.tokens.color.bg_primary, v.card.getBackground())); // zenit Modal default panel
        for (0..16) |_| {
            cx.advanceFrameClock();
            _ = cx.render();
        }
        try std.testing.expect(cx.isFocused(original_input));
        // Island B v3 Input/focus (Pencil `W:AdAHY`): the field keeps its resting
        // fill and shows the ControlShell focus frame (accent border + halo).
        try std.testing.expectEqual(theme.popupInset(), original_input.getBackground());
        try std.testing.expectEqual(cx.tokens.tokens.color.accent, original_input.style.border.color);
        try std.testing.expect(original_input.style.outline() == null or original_input.style.outline().?.width == 0);
        cx.clearFocus();
        for (0..16) |_| {
            cx.advanceFrameClock();
            _ = cx.render();
        }
        try std.testing.expectEqual(theme.popupInset(), original_input.getBackground());
        cx.setFocus(original_input);
        for (0..16) |_| {
            cx.advanceFrameClock();
            _ = cx.render();
        }
        // Island B v3 Input/focus (Pencil `W:AdAHY`): the field keeps its resting
        // fill and shows the ControlShell focus frame (accent border + halo).
        try std.testing.expectEqual(theme.popupInset(), original_input.getBackground());
        try std.testing.expectEqual(cx.tokens.tokens.color.accent, original_input.style.border.color);
        try std.testing.expect(ui.Color.eql(theme.current().fg_1, v.title.getText().?.color));
        try std.testing.expect(ui.Color.eql(theme.current().ok_ink, v.error_label.getText().?.color));
    }
    v.act(.save);
    try std.testing.expectEqual(@as(usize, 1), c.saved);
    try std.testing.expectEqual(@as(?usize, 1), v.draft.exit);
    try std.testing.expectEqual(@as(u16, 4567), v.draft.port);
}

fn findId(node: *ui.Node, id: []const u8) ?*ui.Node {
    if (node.meta.ownership.meta.test_id) |value| if (std.mem.eql(u8, value, id)) return node;
    for (node.children.items) |child| if (findId(child, id)) |found| return found;
    return null;
}

test "existing wizard protocol Select uses Light and Sauber tokens and still selects SFTP" {
    const theme = @import("../../../../shared/ui/theme/app_theme.zig");
    const Wizard = @import("../../../../plugins/remote/editor.zig").RemoteEditor;
    const previous = theme.currentName();
    defer theme.select(previous);
    inline for (.{ .light, .sauber }) |name| {
        theme.select(name);
        const cx = try ui.Cx.init(std.testing.allocator, std.testing.io);
        defer cx.deinit();
        cx.setTheme(theme.widgetTheme(name));
        cx.setViewport(1440, 900);
        const scope = try ui.Scope.init(std.testing.allocator, null, cx.owner);
        defer scope.dispose();
        cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
        var wizard: Wizard = .{};
        try cx.root.?.appendChild(cx.allocator, try wizard.mount(cx, scope));
        wizard.show();
        for (0..8) |_| {
            cx.layout();
            _ = wizard.updateViewport();
        }
        const protocol = wizard.protocol_select.?;
        try std.testing.expectEqualStrings("wizard.protocol", protocol.trigger.meta.ownership.meta.test_id.?);
        try std.testing.expect(ui.Color.eql(theme.current().fg_1, ui.widgets.select.stateOf(protocol).colors.text_primary));
        try std.testing.expect(ui.Color.eql(theme.current().accent, ui.widgets.select.stateOf(protocol).colors.primary));
        protocol.open.?.set(true);
        for (0..4) |_| cx.layout();
        const option = findId(protocol.panel, "wizard.protocol.sftp").?;
        const event = option.behavior.events.on_event.?;
        _ = event(.{ .click = .{ .x = 0, .y = 0 } }, option.behavior.events.event_context);
        for (0..4) |_| cx.layout();
        try std.testing.expectEqualStrings("sftp", wizard.sig_protocol.?.get().?);
        try std.testing.expectEqual(@import("../../../../plugins/remote/editor.zig").Protocol.sftp, wizard.protocol);
        try std.testing.expect(!protocol.open.?.get());
    }
}

fn hasOpaqueLeaf(node: *ui.Node, color: ui.Color) bool {
    if (node.children.items.len == 0 and ui.Color.eql(node.getBackground(), color)) return true;
    for (node.children.items) |child| if (hasOpaqueLeaf(child, color)) return true;
    return false;
}
fn hasTexture(node: *ui.Node, id: u32) bool {
    if (node.getImage()) |image| if (image.texture_id == id) return true;
    for (node.children.items) |child| if (hasTexture(child, id)) return true;
    return false;
}

test "configuration Select reveals one global material through options and theme updates" {
    const theme = @import("../../../../shared/ui/theme/app_theme.zig");
    const background = @import("../../../shell/view/background_layers.zig");
    const previous = theme.currentName();
    const was_material = theme.materialVisible();
    defer {
        theme.select(previous);
        _ = theme.setMaterialVisible(was_material);
    }
    theme.select(.light);
    _ = theme.setMaterialVisible(true);
    const cx = try ui.Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    cx.setTheme(theme.widgetTheme(.light));
    cx.setViewport(1440, 900);
    const scope = try ui.Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    const root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    cx.root = root;
    const material = try background.View.mount(cx, scope);
    try root.appendChild(cx.allocator, material.root);
    var c = C{};
    const v = try m.View.mount(cx, scope, .{ .context = &c, .save = save, .test_cb = test_cb, .cancel = cancel, .confirm_exposure = exposure });
    if (!v.portaled) try root.appendChild(cx.allocator, v.root);
    try material.update(.{ .id = 73, .width = 320, .height = 180 }, .{ .background = .{ .enabled = true, .path = "/owned-headless-fixture", .transparency = 100 }, .blur_px = 4 }, 1440, 900);
    inline for (.{ .light, .sauber, .dark }) |name| {
        theme.select(name);
        cx.setTheme(theme.widgetTheme(name));
        try v.show(.{}, &.{ .{ .label = "末端" }, .{ .label = "首跳", .index = 0 } });
        for (0..8) |_| {
            cx.layout();
            _ = v.updateGeometry();
        }
        v.picker.open.?.set(true);
        for (0..8) |_| {
            cx.layout();
            _ = cx.render();
        }
        try material.update(.{ .id = 73, .width = 320, .height = 180 }, .{ .background = .{ .enabled = true, .path = "/owned-headless-fixture", .transparency = 100 }, .blur_px = 4 }, 1440, 900);
        cx.layout();
        // New zenit Select has no separate chrome: its panel is the popup surface, so
        // the panel carries the overlay tint exactly once (options stay unfilled) and
        // the material image is the single isolated layer behind it.
        // zenit's own panel: opaque at every material setting, no backdrop glass; nothing repaints it.
        try std.testing.expectEqual(@as(u8, 255), v.picker.panel.getBackground().a);
        try std.testing.expect(v.picker.panel.style.glass_params() == null);
        try std.testing.expect(findId(v.picker.panel, "appearance.surface") == null);
        try std.testing.expect(hasTexture(material.root, 73));
        try std.testing.expect(!hasTexture(v.picker.panel, 73));
        // Updating Select options keeps the single global background untouched.
        try v.show(.{}, &.{ .{ .label = "新末端" }, .{ .label = "新首跳", .index = 0 } });
        for (0..4) |_| cx.layout();
        try std.testing.expect(findId(v.picker.panel, "appearance.surface") == null);
        // New zenit Select has no separate chrome: its panel is the popup surface, so
        // the panel carries the overlay tint exactly once (options stay unfilled) and
        // the material image is the single isolated layer behind it.
        // zenit's own panel: opaque at every material setting, no backdrop glass; nothing repaints it.
        try std.testing.expectEqual(@as(u8, 255), v.picker.panel.getBackground().a);
        try std.testing.expect(v.picker.panel.style.glass_params() == null);
        try std.testing.expect(v.card.globalRect().h > 396 and v.card.globalRect().h <= 650);
    }
}

test "forward modes validate fixed targets and keep session-only settings" {
    const cx = try ui.Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    cx.setViewport(860, 480);
    const scope = try ui.Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    const root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    cx.root = root;
    var c = C{};
    const v = try m.View.mount(cx, scope, .{ .context = &c, .save = save, .test_cb = test_cb, .cancel = cancel, .confirm_exposure = exposure });
    if (!v.portaled) try root.appendChild(cx.allocator, v.root);
    try v.show(.{}, &.{});
    v.act(.mode_local);
    for (v.mode_highlights, 0..) |highlight, i| try std.testing.expectEqual(i == 1, highlight.style.display == .flex);
    try std.testing.expect(v.target_group.style.display == .flex);
    try std.testing.expect(v.persist_row.style.display == .none);
    v.target_host_signal.set("database.internal");
    v.target_port_signal.set("0");
    v.act(.save);
    try std.testing.expectEqual(@as(usize, 0), c.saved);
    v.target_port_signal.set("5432");
    v.act(.save);
    try std.testing.expectEqual(@as(usize, 1), c.saved);
    try std.testing.expect(!v.draft.persist and !v.draft.auto_start);
    v.act(.mode_remote);
    for (v.mode_highlights, 0..) |highlight, i| try std.testing.expectEqual(i == 2, highlight.style.display == .flex);
    v.act(.save);
    try std.testing.expectEqual(@as(usize, 1), c.saved);
    try std.testing.expect(std.mem.indexOf(u8, v.error_label.getText().?.content, "IPv4") != null);
    v.target_host_signal.set("::1");
    v.act(.save);
    try std.testing.expectEqual(@as(usize, 2), c.saved);
    v.act(.mode_socks5);
    for (v.mode_highlights, 0..) |highlight, i| try std.testing.expectEqual(i == 0, highlight.style.display == .flex);
    try std.testing.expect(v.target_group.style.display == .none);
    try std.testing.expect(v.persist_row.style.display == .flex);
}
fn settle(cx: *ui.Cx) void {
    for (0..18) |_| {
        cx.frame_count += 1;
        cx.frame_time_ms += 16;
        cx.bindFrameClock();
        cx.layout();
        _ = cx.render();
    }
}

test "configuration modal barrier is zenit's default translucent overlay in every appearance family" {
    const theme = @import("../../../../shared/ui/theme/app_theme.zig");
    const previous = theme.currentName();
    defer theme.select(previous);
    for ([_]theme.Name{ .dark, .light, .sauber }) |name| {
        theme.select(name);
        const cx = try ui.Cx.init(std.testing.allocator, std.testing.io);
        defer cx.deinit();
        cx.setTheme(theme.widgetTheme(name));
        cx.setViewport(1440, 900);
        const scope = try ui.Scope.init(std.testing.allocator, null, cx.owner);
        defer scope.dispose();
        const root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
        cx.root = root;
        var c = C{};
        const v = try m.View.mount(cx, scope, .{ .context = &c, .save = save, .test_cb = test_cb, .cancel = cancel, .confirm_exposure = exposure });
        if (!v.portaled) try root.appendChild(cx.allocator, v.root);
        try v.show(.{}, &.{.{ .label = "链路末端" }});
        cx.layout();
        const zenit_default = if (name == .dark) ui.theme.dark else ui.theme.light;
        try std.testing.expectEqual(zenit_default.tokens.color.overlay, v.root.getBackground());
        try std.testing.expect(v.root.getBackground().a > 0);
    }
}
