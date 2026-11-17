//! Production Popover material checks; no native window is started.
const std = @import("std");
const ui = @import("ui");
const controls = @import("../../ai/composer/view/ai_composer_controls_view.zig");
const layers = @import("../view/background_layers.zig");
const theme = @import("../../../shared/ui/theme/app_theme.zig");
const assets = @import("../../../config/background_asset.zig");
const shell = @import("../view/shell_styles.zig");

fn frame(cx: *ui.Cx) []const ui.DisplayItem {
    for (0..20) |_| {
        cx.advanceFrameClock();
        _ = cx.render();
    }
    return cx.render();
}
fn action(_: *anyopaque, _: controls.Envelope) !void {}
fn find(node: *ui.Node, id: u64) ?*ui.Node {
    if (node.id == id) return node;
    for (node.children.items) |child| if (find(child, id)) |result| return result;
    return null;
}
fn expectOpaqueText(node: *ui.Node) !void {
    if (node.style.display == .none) return;
    if (node.getText()) |text| if (text.content.len != 0) try std.testing.expectEqual(@as(u8, 255), text.color.a);
    for (node.children.items) |child| try expectOpaqueText(child);
}
fn contains(rect: ui.ComputedRect, x: f32, y: f32) bool {
    return x > rect.x and y > rect.y and x < rect.x + rect.w and y < rect.y + rect.h;
}

test "AI sessions retained native rows follow every builtin theme publication" {
    const Sessions = @import("../../ai/sessions/view/ai_sessions_view.zig");
    const parameters = theme.materialParameters();
    defer _ = theme.setMaterialParameters(parameters.transparency, parameters.blur);
    _ = theme.setMaterialParameters(50, 24);
    const previous = theme.currentName();
    defer theme.select(previous);
    const a = std.testing.allocator;
    const cx = try ui.Cx.init(a, std.testing.io);
    defer cx.deinit();
    cx.setViewport(1000, 700);
    try cx.setTestFrameStep(16);
    const scope = try ui.Scope.init(a, null, cx.owner);
    defer scope.dispose();
    cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    const assistant = try ui.boxStyled(cx, overlayPanel, .{});
    try cx.root.?.appendChild(a, assistant);
    const anchor = try ui.box(cx, .{ .width = .{ .px = 24 }, .height = .{ .px = 24 } }, .{});
    try assistant.appendChild(a, anchor);
    var context: u8 = 0;
    const callbacks = struct {
        fn ignore(_: *anyopaque, _: u64) void {}
    };
    const list = try Sessions.View.mount(cx, scope, anchor, .{ .context = &context, .select = callbacks.ignore, .request_close = callbacks.ignore, .remove = callbacks.ignore });
    try assistant.appendChild(a, list.root);
    try std.testing.expect(list.badge.style.display == .none);
    try list.updateBoundCount(12);
    try std.testing.expectEqualStrings("12", list.badge.getText().?.content);
    try std.testing.expect(list.badge.style.display == .flex);
    try list.show(&.{ .{ .id = 1, .title = "等待审批", .owner = "当前终端", .active = true, .phase = .approval }, .{ .id = 2, .title = "正在运行", .owner = "当前终端", .phase = .running } });
    const row = findTestId(list.content, "ai.session.row.1").?;
    const publication = try cx.bindState(shell.ThemePublication, .{});
    for (@import("../../../config/theme_presets.zig").ids) |id| {
        theme.selectTokens(@import("../../../config/theme_registry.zig").builtinTokens(id));
        publication.publish(cx, theme.widgetTheme(theme.currentName()));
        _ = frame(cx);
        try std.testing.expect(list.open.peek());
        try std.testing.expectEqual(row, findTestId(list.content, "ai.session.row.1").?);
        // zenit's own panel: opaque at every material setting, no backdrop glass; nothing repaints it.
        try std.testing.expectEqual(@as(u8, 255), list.chrome.getBackground().a);
        try std.testing.expect(list.chrome.style.glass_params() == null);
        try std.testing.expectEqual(ui.Color.TRANSPARENT, list.badge.getBackground());
        try std.testing.expectEqual(theme.current().accent_ink, list.badge.getText().?.color);
        try std.testing.expectEqual(ui.Color.TRANSPARENT, list.surface.getBackground());
        // O7 (ai-redesign-c): the phase is a native W.Tag (its label in the slot named by the phase).
        try std.testing.expectEqualStrings("待确认", firstText(findTestId(list.content, "ai.session.status.approval").?).?);
        try std.testing.expectEqualStrings("运行中", firstText(findTestId(list.content, "ai.session.status.running").?).?);
    }
    try list.updateBoundCount(0);
    try std.testing.expect(list.badge.style.display == .none);
}

test "production AI usage popover paints its native default surface over the single global material" {
    const saved_parameters = theme.materialParameters();
    defer _ = theme.setMaterialParameters(saved_parameters.transparency, saved_parameters.blur);
    _ = theme.setMaterialParameters(75, 24);
    const old_name = theme.currentName();
    const old_material = theme.materialVisible();
    defer {
        theme.select(old_name);
        _ = theme.setMaterialVisible(old_material);
    }
    theme.select(.dark);
    _ = theme.setMaterialVisible(false);
    const a = std.testing.allocator;
    const cx = try ui.Cx.init(a, std.testing.io);
    defer cx.deinit();
    cx.setViewport(1440, 900);
    try cx.setTestFrameStep(16);
    const scope = try ui.Scope.init(a, null, cx.owner);
    defer scope.dispose();
    cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    const source = try layers.View.mount(cx, scope);
    try cx.root.?.appendChild(a, source.root);
    const publication = try cx.bindState(shell.ThemePublication, .{});
    publication.publish(cx, theme.widgetTheme(.dark));
    const parent = try ui.box(cx, .{ .position = .absolute, .inset = .{ .left = .{ .px = 100 }, .top = .{ .px = 100 } }, .width = .{ .px = 600 }, .height = .{ .px = 420 }, .background = theme.current().overlay }, .{});
    try cx.root.?.appendChild(a, parent);
    var context: u8 = 0;
    const view = try controls.View.mount(cx, scope, .{ .context = &context, .action = action });
    view.root.setStyleInline(a, .{ .position = .absolute, .inset = .{ .left = .{ .px = 14 }, .top = .{ .px = 384 } }, .width = .{ .px = 572 } });
    try parent.appendChild(a, view.root);
    // Permission / run mode are native menus now; the usage popover is a production Popover.
    try view.update(.{ .owner = .{ .tab = 1 }, .revision = 1, .usage = .{ .used_tokens = 5000, .limit_tokens = 200000 } });
    _ = frame(cx);
    _ = theme.setMaterialVisible(true);
    publication.publish(cx, theme.widgetTheme(.dark));
    parent.setBackground(theme.current().overlay);
    const material: assets.Materials = .{ .background = .{ .enabled = true, .path = "/fixture", .fit = .fill, .transparency = 35 } };
    try source.update(.{ .id = 777, .width = 2, .height = 2 }, material, 1440, 900);
    _ = frame(cx);
    cx.setFocus(findTestId(view.root, controls.buttonId(view, .usage)).?);
    cx.handleKeyDown(.@"return", .{});
    const items = frame(cx);
    const popup = view.popups[1];
    try std.testing.expect(view.popup_open[1].peek());
    for (popup.chrome.children.items) |child| try std.testing.expect(!layers.isSurface(child));
    // Native appearance is the zenit default: the Popover draws its own opaque surface (not a
    // ZeroWork overlay tint), above the one projected global material.
    try std.testing.expectEqual(@as(u8, 255), popup.chrome.getBackground().a);
    try expectOpaqueText(popup.chrome);
    const rect = popup.chrome.globalRect();
    var projected: usize = 0;
    var image_order: ?usize = null;
    var after_image_fills: usize = 0;
    var opaque_after_image: usize = 0;
    for (items, 0..) |item, index| switch (item) {
        .image_quad => |q| if (q.texture_id == 777) {
            projected += 1;
            image_order = index;
        },
        .fill_rect => |fill| if (image_order != null) {
            const node = find(cx.root.?, fill.header.node_id) orelse continue;
            if (!node.isDescendantOf(popup.chrome)) continue;
            if (contains(node.globalRect(), rect.x + rect.w / 2, rect.y + rect.h / 2)) {
                after_image_fills += 1;
                if (fill.color.a == 255) opaque_after_image += 1;
            }
        },
        else => {},
    };
    try std.testing.expectEqual(@as(usize, 1), projected);
    try std.testing.expect(image_order != null);
    try std.testing.expect(after_image_fills > 0);
    try std.testing.expect(opaque_after_image > 0);
}

test "production bottom More retains global material through row rebuild and reopen" {
    const old_name = theme.currentName();
    const old_material = theme.materialVisible();
    defer {
        theme.select(old_name);
        _ = theme.setMaterialVisible(old_material);
    }
    theme.select(.dark);
    _ = theme.setMaterialVisible(true);
    const a = std.testing.allocator;
    const cx = try ui.Cx.init(a, std.testing.io);
    defer cx.deinit();
    cx.setViewport(1440, 900);
    try cx.setTestFrameStep(16);
    const scope = try ui.Scope.init(a, null, cx.owner);
    defer scope.dispose();
    cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    const source = try layers.View.mount(cx, scope);
    try cx.root.?.appendChild(a, source.root);
    const trigger = try ui.widgets.Button(.{ .a11y_label = "更多终端状态" }).mount(scope, cx);
    trigger.setStyleInline(a, .{ .position = .absolute, .width = .{ .px = 26 }, .height = .{ .px = 26 }, .inset = .{ .right = .{ .px = 20 }, .bottom = .{ .px = 20 } } });
    try cx.root.?.appendChild(a, trigger);
    var context: u8 = 0;
    const view = try @import("../view/status_detail_view.zig").View.mount(cx, scope, .{ .context = &context });
    try cx.root.?.appendChild(a, view.root);
    try source.update(.{ .id = 777, .width = 2, .height = 2 }, .{ .background = .{ .enabled = true, .path = "/fixture", .fit = .fill, .transparency = 35 } }, 1440, 900);
    try view.update(.{ .owner = .{ .session = .{ .session_id = @fromBackingInt(1) } }, .owner_kind = .local, .source_revision = 1, .identity_label = "本地 · zsh", .encoding = .utf8, .grid = .{ .cols = 80, .rows = 24, .revision = 1 } });
    _ = frame(cx);
    for (view.chrome.children.items) |child| try std.testing.expect(!layers.isSurface(child));
    for (0..3) |_| {
        try view.show(.more, trigger, 860, false);
        const items = frame(cx);
        try std.testing.expect(view.open.peek());
        try std.testing.expectEqual(theme.current().overlay, view.chrome.getBackground());
        var images: usize = 0;
        var title = false;
        for (items) |item| switch (item) {
            .image_quad => |quad| if (quad.texture_id == 777) {
                images += 1;
            },
            .text_run => |run| if (std.mem.eql(u8, run.content, "更多状态")) {
                title = true;
            },
            else => {},
        };
        try std.testing.expectEqual(@as(usize, 1), images);
        try std.testing.expect(title);
        view.hide();
        _ = frame(cx);
        try std.testing.expect(!view.open.peek());
    }
}

fn authSubmit(_: *anyopaque, _: @import("../../../proto/ssh/auth_challenge.zig").RequestIdentity, _: @import("../../../proto/ssh/auth_challenge.zig").Reply) !void {}
fn authCancel(_: *anyopaque, _: @import("../../../proto/ssh/auth_challenge.zig").RequestIdentity) void {}

test "production auth content inherits modal and inline material across retheme without replacing secrets" {
    const previous_parameters = theme.materialParameters();
    defer _ = theme.setMaterialParameters(previous_parameters.transparency, previous_parameters.blur);
    _ = theme.setMaterialParameters(75, 16);
    const auth_view = @import("../../connections/auth/view/auth_challenge_view.zig");
    const auth = auth_view.auth;
    const old_name = theme.currentName();
    const old_material = theme.materialVisible();
    defer {
        theme.select(old_name);
        _ = theme.setMaterialVisible(old_material);
    }
    for ([_]auth.Presentation{ .protected_form, .otp_modal }) |presentation| {
        theme.select(.dark);
        _ = theme.setMaterialVisible(false);
        const a = std.testing.allocator;
        const cx = try ui.Cx.init(a, std.testing.io);
        defer cx.deinit();
        cx.setViewport(1440, 900);
        try cx.setTestFrameStep(16);
        // Field transitions (ControlShell `fade`) start on the renderer's shared
        // clock; bind this window's clock first so the previous presentation's
        // later timestamps cannot leave this window's fields mid-transition.
        cx.bindFrameClock();
        const scope = try ui.Scope.init(a, null, cx.owner);
        defer scope.dispose();
        cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
        const source = try layers.View.mount(cx, scope);
        try cx.root.?.appendChild(a, source.root);
        // The connection dialog and inline form reveal the same global layer.
        const parent = try ui.box(cx, .{ .width = .{ .px = 620 }, .height = .{ .px = 620 }, .background = theme.current().overlay }, .{});
        try cx.root.?.appendChild(a, parent);
        var context: u8 = 0;
        const view = try auth_view.View.mount(cx, scope, .{ .context = &context, .submit = authSubmit, .cancel = authCancel });
        try parent.appendChild(a, view.root);
        try view.setMaterial(source);
        var bridge: auth.InteractiveBridge = .{};
        _ = try bridge.offerChallenge(.{
            .key = .{ .owner = .{ .session = .{ .session_id = @fromBackingInt(9), .generation = 3 } }, .operation_id = 7, .attempt_id = 2 },
            .hop_index = 1,
            .kind = .keyboard_interactive,
            .endpoint_identity = .{ .host = "target.example", .user = "operator", .port = 2222 },
            .prompts = &.{.{ .text = "Verification code:", .echo = false }},
            .presentation = presentation,
            .presentation_config_revision = 4,
        });
        try view.show(bridge.snapshot().?);
        _ = frame(cx);
        cx.setFocus(view.fields[0].input.input_container);
        cx.handleTextInput("654321");
        const input = view.fields[0].input.state;
        const form = view.form.?;
        const chrome = if (view.modal) |modal| modal.dialog else parent;
        for (chrome.children.items) |child| try std.testing.expect(!layers.isSurface(child));
        for ([_]bool{ false, true, false }) |enabled| {
            for ([_]theme.Name{ .dark, .light }) |name| {
                theme.select(name);
                _ = theme.setMaterialVisible(enabled);
                cx.setTheme(theme.widgetTheme(name));
                parent.setBackground(theme.current().overlay);
                try view.retheme();
                try source.update(if (enabled) .{ .id = 777, .width = 2, .height = 2 } else null, .{ .background = .{ .enabled = enabled, .path = "/fixture", .fit = .fill, .transparency = 35 } }, 1440, 900);
                const items = frame(cx);
                try std.testing.expectEqual(ui.Color.TRANSPARENT, form.getBackground());
                // The modal presentation is a zenit Modal with its default opaque bg-primary
                // panel (no material); the inline form keeps its parent's material.
                try std.testing.expectEqual(if (view.modal != null) cx.tokens.tokens.color.bg_primary else theme.current().overlay, chrome.getBackground());
                try std.testing.expectEqual(input, view.fields[0].input.state);
                try std.testing.expectEqualStrings("654321", input.getText());
                try std.testing.expectEqual(ui.widgets.input.InputType.password, input.input_type);
                try std.testing.expect(!view.submit_disabled.peek());
                try std.testing.expect(input.focused);
                // Island B v3: the field frame is zenit's ControlShell (field :focus =
                // 1px accent border, control_shell/styles.yss) over the retained material
                // inset; focus no longer replaces the fill with a focus surface.
                try std.testing.expectEqual(theme.popupInset(), view.fields[0].input.input_container.getBackground());
                try std.testing.expectEqual(cx.tokens.tokens.color.accent, view.fields[0].input.input_container.style.border.color);
                try std.testing.expectEqual(@as(f32, 1), view.fields[0].input.input_container.style.border.width);
                if (view.fields[0].input.input_container.style.outline()) |outline| try std.testing.expectEqual(@as(f32, 0), outline.width);
                var projected: usize = 0;
                var opaque_chrome = false;
                for (items) |item| switch (item) {
                    .image_quad => |q| {
                        if (q.texture_id == 777) projected += 1;
                    },
                    .fill_rect => |fill| {
                        // Transparent paint bookkeeping does not cover the inherited image.
                        if (fill.header.node_id == form.id) try std.testing.expectEqual(@as(u8, 0), fill.color.a);
                        if (fill.header.node_id == chrome.id and fill.color.a == 255) opaque_chrome = true;
                    },
                    else => {},
                };
                try std.testing.expectEqual(if (enabled) @as(usize, 1) else 0, projected);
                try std.testing.expect(view.modal != null or !opaque_chrome);
            }
        }
    }
}

test "global material component roles preserve readable bubble paints and material alpha" {
    const saved_colors = theme.baseColors();
    const saved_parameters = theme.materialParameters();
    defer {
        var tokens: @import("../../../config/theme_registry.zig").UiTokens = undefined;
        inline for (@typeInfo(@TypeOf(saved_colors)).@"struct".field_names) |field| {
            const color = @field(saved_colors, field);
            @field(tokens, field) = (@as(u32, color.r) << 24) | (@as(u32, color.g) << 16) | (@as(u32, color.b) << 8) | color.a;
        }
        theme.selectTokens(tokens);
        _ = theme.setMaterialParameters(saved_parameters.transparency, saved_parameters.blur);
    }
    const bubble = @import("../../ai/pane/view/ai_assistant_styles.zig");
    const recent = @import("../../ai/sessions/view/ai_empty_styles.zig");
    for (@import("../../../config/theme_presets.zig").ids) |id| {
        theme.selectTokens(@import("../../../config/theme_registry.zig").builtinTokens(id));
        for ([_]f32{ 0, 50, 100 }) |transparency| {
            _ = theme.setMaterialParameters(transparency, transparency * 0.48);
            const c = theme.current();
            // Kaf7E A3: the user bubble is the native W.Card bubble (zenit bg_active, no gradient);
            // its ink (fg_primary) stays readable (>= 4.5:1) over the bubble on the panel.
            const composed = theme.patchPaint(theme.states().pressed, c.overlay.withAlpha(255));
            try std.testing.expect(contrastRatio(c.fg_1, composed) >= 4.5);
            _ = bubble;
            // A2 (ai-redesign-c): the welcome's recent group paints no surface of its own (rows do).
            try std.testing.expect(recent.recentGroup(undefined).background == null);
        }
    }
}

fn firstText(node: *ui.Node) ?[]const u8 {
    if (node.getText()) |value| if (value.content.len != 0) return value.content;
    for (node.children.items) |child| if (firstText(child)) |found| return found;
    return null;
}

fn findTestId(node: *ui.Node, id: []const u8) ?*ui.Node {
    if (node.meta.ownership.meta.test_id) |value| if (std.mem.eql(u8, value, id)) return node;
    for (node.children.items) |child| if (findTestId(child, id)) |result| return result;
    return null;
}

test "material retained rename overlay updates alpha and blur independently" {
    const saved = theme.materialParameters();
    const old_name = theme.currentName();
    defer {
        _ = theme.setMaterialParameters(saved.transparency, saved.blur);
        theme.select(old_name);
    }
    theme.select(.dark);
    _ = theme.setMaterialParameters(0, 0);
    const a = std.testing.allocator;
    const cx = try ui.Cx.init(a, std.testing.io);
    defer cx.deinit();
    cx.setViewport(1440, 900);
    const scope = try ui.Scope.init(a, null, cx.owner);
    defer scope.dispose();
    cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    const publication = try cx.bindState(shell.ThemePublication, .{});
    publication.publish(cx, theme.widgetTheme(.dark));
    const Hooks = struct {
        fn rename(_: *anyopaque, _: u64, _: []const u8) bool {
            return true;
        }
        fn cancel(_: *anyopaque, _: u64) void {}
    };
    var context: u8 = 0;
    const rename = try @import("../view/tab_rename.zig").Editor.mount(cx, scope, 1, "Session", .{ .context = &context, .commit = Hooks.rename, .cancel = Hooks.cancel });
    const id = rename.dialog.id;
    // Include blur-only publication and all alpha endpoints, retaining the nodes.
    for ([_]f32{ 0, 0, 0, 25, 75, 100, 0 }, [_]f32{ 0, 8, 24, 24, 24, 96, 0 }) |t, b| {
        _ = theme.setMaterialParameters(t, b);
        publication.publish(cx, theme.widgetTheme(theme.currentName()));
        _ = frame(cx);
        // zenit's own panel: opaque at every material setting, no backdrop glass; nothing repaints it.
        try std.testing.expectEqual(@as(u8, 255), rename.dialog.getBackground().a);
        try std.testing.expect(rename.dialog.style.glass_params() == null);
        try std.testing.expectEqual(id, rename.dialog.id);
        try std.testing.expectEqual(theme.popupAction(), @import("../../notifications/view/notification_history_styles.zig").footer().background);
    }
}

test "native foreground aliases preserve readable ink roles through every builtin publication" {
    const previous = theme.currentName();
    defer theme.select(previous);
    theme.select(.dark);
    const old = theme.current();
    for (@import("../../../config/theme_presets.zig").ids) |id| {
        theme.selectTokens(@import("../../../config/theme_registry.zig").builtinTokens(id));
        inline for (.{ "fg_1", "fg_2", "fg_3", "accent_ink", "warn_ink", "ok_ink", "danger_ink" }) |role| {
            try std.testing.expectEqual(@field(theme.current(), role), theme.remapUiInk(@field(old, role), old));
        }
    }
}

test "native primary Button keeps zenit's default primary roles on every builtin palette" {
    const previous = theme.currentName();
    defer theme.select(previous);
    const a = std.testing.allocator;
    const cx = try ui.Cx.init(a, std.testing.io);
    defer cx.deinit();
    cx.setViewport(800, 600);
    const scope = try ui.Scope.init(a, null, cx.owner);
    defer scope.dispose();
    cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    const disabled = try scope.createSignal(bool, false);
    const button = try ui.widgets.Button(.{ .label = "确认", .variant = .primary, .disabled = disabled }).mount(scope, cx);
    try cx.root.?.appendChild(a, button);
    const publication = try cx.bindState(shell.ThemePublication, .{});
    try cx.setTestFrameStep(16);
    for (@import("../../../config/theme_presets.zig").ids) |id| {
        theme.selectTokens(@import("../../../config/theme_registry.zig").builtinTokens(id));
        publication.publish(cx, theme.widgetTheme(theme.currentName()));
        const defaults = theme.zenitDefaults(theme.currentName()).tokens.color;
        // ZeroWork's theme no longer rewrites the primary roles (T-1, user decision A).
        try std.testing.expectEqual(defaults.button_primary_bg, cx.tokens.tokens.color.button_primary_bg);
        try std.testing.expectEqual(defaults.button_primary_fg, cx.tokens.tokens.color.button_primary_fg);
        try std.testing.expectEqual(defaults.button_primary_hover, cx.tokens.tokens.color.button_primary_hover);
        try std.testing.expectEqual(defaults.button_primary_pressed, cx.tokens.tokens.color.button_primary_pressed);
        try std.testing.expect(contrastRatio(defaults.button_primary_bg, defaults.button_primary_fg) >= 4.5);
        disabled.set(false);
        _ = frame(cx);
        try std.testing.expect(button.style.gradient() == null);
        try std.testing.expectEqual(defaults.button_primary_bg, button.getBackground());
        disabled.set(true);
        _ = frame(cx);
        try std.testing.expect(button.style.gradient() == null);
        try std.testing.expect(button.behavior.interaction.a11y.?.disabled);
    }
}

fn contrastRatio(a: ui.Color, b: ui.Color) f64 {
    const lum = struct {
        fn of(c: ui.Color) f64 {
            var result: f64 = 0;
            inline for (.{ .{ "r", 0.2126 }, .{ "g", 0.7152 }, .{ "b", 0.0722 } }) |item| {
                const channel = @as(f64, @floatFromInt(@field(c, item[0]))) / 255;
                result += item[1] * (if (channel <= 0.04045) channel / 12.92 else std.math.pow(f64, (channel + 0.055) / 1.055, 2.4));
            }
            return result;
        }
    };
    const x = lum.of(a);
    const y = lum.of(b);
    return (@max(x, y) + 0.05) / (@min(x, y) + 0.05);
}

test "native Tooltip keeps zenit's bubble under the global material policy" {
    const a = std.testing.allocator;
    const cx = try ui.Cx.init(a, std.testing.io);
    defer cx.deinit();
    cx.setViewport(800, 500);
    try cx.setTestFrameStep(16);
    const scope = try ui.Scope.init(a, null, cx.owner);
    defer scope.dispose();
    cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    const tip = try ui.widgets.Tooltip(.{ .text = "本地终端 · ~/docs · zsh · ⌘4", .open_delay_ms = 0 }).mount(scope, cx);
    try tip.trigger.appendChild(a, try ui.box(cx, .{ .width = .{ .px = 80 }, .height = .{ .px = 24 } }, .{}));
    try cx.root.?.appendChild(a, tip.wrapper);
    tip.open.?.set(true);
    _ = frame(cx);
    try std.testing.expect(tip.content.isDisplayedInTree());
    // zenit's own tooltip_bg / tooltip_fg, not ZeroWork's overlay material.
    try std.testing.expectEqual(cx.tokens.tokens.color.tooltip_bg, tip.content.getBackground());
    try std.testing.expect(tip.content.style.glass_params() == null);
}

/// An overlay-material panel the size of the former AI floating panel (the material policy fixture;
/// the AI panel itself is now the unified floating chrome on a native floating Card).
fn overlayPanel(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .hit_behavior = .@"opaque", .width = .{ .px = 600 }, .height = .{ .px = 456 }, .direction = .column, .padding = ui.Padding.all(1), .background = theme.current().overlay, .glass = theme.overlayGlass(), .border = .{ .width = 0, .radius = 14 }, .shadows = ui.ShadowList.of(&.{.{ .color = ui.Color.rgba(0, 0, 0, 119), .blur = 48, .offset_y = 18 }}), .overflow = .hidden };
}
