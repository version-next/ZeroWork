const std = @import("std");
const ui = @import("ui");
const theme = @import("../../../shared/ui/theme/app_theme.zig");

/// Island B v3 shell geometry (Pencil `aPxql`). Structural styles live in
/// shell/styles.yss; these constants feed native window chrome and layout math.
const Shell = @import("shell/_styles.yss.zig");
/// The sidebar and view bar start at the window edge (no outer frame).
pub const outer: f32 = 0;
/// Sidebar and content column are adjacent; the island carries its own inset.
pub const gap: f32 = 0;
/// View bar height (also the caption height handed to the platform).
pub const title_height: f32 = 44;
/// Native traffic lights in the sidebar header: first button center and diameter
/// (sidebar padding 8 + header inset 6 + radius 6; header top 12 + 28/2).
pub const traffic_light_x: f32 = 20;
pub const traffic_light_y: f32 = 26;
pub const traffic_light_diameter: f32 = 12;
pub const status_height: f32 = @import("../../../shared/ui/styles/v3_geometry.zig").status_height;
pub const sidebar_width: f32 = @import("../model/sidebar_model.zig").default_width;
pub const sidebar_collapsed: f32 = 0;
pub const card_radius: f32 = 12;
// Native traffic lights are hosted above the sidebar, outside the tool row.
pub const title_controls_inset: f32 = 79;
pub const title_content_inset: f32 = 10;

pub fn titlePaddingForChrome(chrome: anytype) ui.Padding {
    _ = chrome;
    return .{};
}

/// Apply after theme publication: boxStyled replays its windowed default.
/// Compare the retained node itself so a theme replay cannot mask the change.
pub fn syncTitleChrome(allocator: std.mem.Allocator, node: *ui.Node, chrome: anytype) bool {
    const padding = titlePaddingForChrome(chrome);
    if (std.meta.eql(node.style.padding, padding)) return false;
    node.setStyleInline(allocator, .{ .padding = padding });
    return true;
}

/// With the sidebar hidden, reserve only the native traffic-light footprint.
pub fn syncWorkspaceChrome(allocator: std.mem.Allocator, node: *ui.Node, chrome: anytype, collapsed: bool) bool {
    const controls_visible = if (chrome.controls_geometry_known) chrome.native_controls_count != 0 else !chrome.fullscreen;
    // View bar padding [0, 6, 0, 12]; a collapsed sidebar moves the traffic
    // lights into the view bar start (Pencil `KBJoz`), which reserves 72pt
    // (D8dPB Window chrome padding-left 14 + lights 52 + gap 6 = 72), followed
    // directly by the 24pt sidebar toggle.
    const padding: ui.Padding = .{ .left = if (collapsed and controls_visible) 14 + 52 + 6 else 12, .right = 6 };
    if (std.meta.eql(node.style.padding, padding)) return false;
    node.setStyleInline(allocator, .{ .padding = padding });
    return true;
}

/// Moved to shared/ui/theme/theme_publication.zig; re-exported for the shell and feature call sites.
pub const ThemePublication = @import("../../../shared/ui/theme/theme_publication.zig").ThemePublication;

pub fn root(t: *const ui.ThemeTokens) ui.BoxStyle {
    return @TypeOf(Shell.root).box(t);
}
/// View bar (44): tabs on the island edge, toolbar at the end.
pub fn title(t: *const ui.ThemeTokens) ui.BoxStyle {
    return @TypeOf(Shell.view_bar).box(t);
}
pub fn floating(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .height = .{ .px = 44 }, .direction = .row, .align_items = .center, .padding = ui.Padding.all(6), .gap = 8, .flex_shrink = 0, .background = theme.current().overlay, .border = .{ .radius = 14 }, .shadow = .{ .blur = 14, .offset_y = 3, .color = theme.baseColors().shadow.withAlpha(18) } };
}
/// Compact top-level chrome; content-page toolbars retain floating().
pub fn titleFloating(_: *const ui.ThemeTokens) ui.BoxStyle {
    const c = theme.current();
    return .{ .height = .{ .px = title_height }, .direction = .row, .align_items = .center, .padding = ui.Padding.all(4), .gap = 4, .flex_shrink = 0, .background = c.overlay, .border = .{ .radius = 18 }, .shadow = .{ .blur = 8, .offset_y = 3, .color = theme.baseColors().shadow.withAlpha(20) } };
}
pub fn toolbar(t: *const ui.ThemeTokens) ui.BoxStyle {
    return @TypeOf(Shell.toolbar).box(t);
}
pub fn toolbarGroup(t: *const ui.ThemeTokens) ui.BoxStyle {
    return @TypeOf(Shell.toolbar_group).box(t);
}
pub fn toolbarDivider(t: *const ui.ThemeTokens) ui.BoxStyle {
    return @TypeOf(Shell.toolbar_divider).box(t);
}
/// Tab strip: plain row of tabs (no capsule surface in Island B v3).
pub fn tabCapsule(t: *const ui.ThemeTokens) ui.BoxStyle {
    return @TypeOf(Shell.tabs).box(t);
}
pub fn body(t: *const ui.ThemeTokens) ui.BoxStyle {
    return @TypeOf(Shell.body).box(t);
}
pub fn sidebar(t: *const ui.ThemeTokens) ui.BoxStyle {
    return @TypeOf(Shell.sidebar).box(t);
}
/// The focused view island (stage inset + radius 12) hosting the workspace.
pub fn pane(t: *const ui.ThemeTokens) ui.BoxStyle {
    return @TypeOf(Shell.island).box(t);
}
/// Session status row as the island's pane header (ZW2 / Pane Header).
pub fn status(t: *const ui.ThemeTokens) ui.BoxStyle {
    return @TypeOf(Shell.pane_header).box(t);
}
/// The status bar's progress slot (the transfer ticker sits in it). It gives way with the bar, down to the
/// ticker's own floor, so the ticker's declared width rules rather than a measurement of the bar.
pub fn statusProgressSlot() ui.BoxStyle {
    return .{ .height = .fill(), .direction = .row, .align_items = .center, .gap = 6, .flex_shrink = 1, .min_width = 0 };
}
pub fn settingsBackdrop(t: *const ui.ThemeTokens) ui.BoxStyle {
    return .{
        .position = .absolute,
        .inset = .{ .top = .{ .px = 0 }, .right = .{ .px = 0 }, .bottom = .{ .px = 0 }, .left = .{ .px = 0 } },
        .width = .fill(),
        .height = .fill(),
        .z_index = 400,
        .hit_behavior = .@"opaque",
        .hit_roles = .{ .pointer = true, .scroll = true },
        .direction = .column,
        .align_items = .center,
        .justify = .center,
        .background = t.tokens.color.overlay,
    };
}

test "light settings surfaces stay light across transparency and retained theme changes" {
    const previous = theme.currentName();
    const parameters = theme.materialParameters();
    defer {
        theme.select(previous);
        _ = theme.setMaterialParameters(parameters.transparency, parameters.blur);
    }
    theme.select(.dark);
    const cx = try ui.Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    const publication = try cx.bindState(ThemePublication, .{});
    publication.publish(cx, theme.widgetTheme(.dark));
    const backdrop = try ui.boxStyled(cx, settingsBackdrop, .{});
    cx.root = backdrop;
    const id = backdrop.id;
    for ([_]theme.Name{ .light, .sauber, .dark }) |name| {
        for ([_]f32{ 0, 50, 75, 100 }) |transparency| {
            theme.select(name);
            _ = theme.setMaterialParameters(transparency, 0);
            publication.publish(cx, theme.widgetTheme(name));
            try std.testing.expectEqual(id, backdrop.id);
            // zenit default modal overlay for the scheme (retained node repaints on publish).
            try std.testing.expectEqual((if (name == .dark) ui.theme.dark else ui.theme.light).tokens.color.overlay, backdrop.getBackground());
            if (name != .dark) {
                const card = theme.settingsCard();
                try std.testing.expect(card.r > 210 and card.g > 210 and card.b > 210);
                try std.testing.expectEqual(theme.current().surface_2.a, card.a);
            }
        }
    }
}

pub fn settingsPanel(_: *const ui.ThemeTokens) ui.BoxStyle {
    const c = theme.current();
    return .{ .width = .{ .px = @import("../../../shared/ui/styles/v3_geometry.zig").settings_width }, .height = .{ .px = @import("../../../shared/ui/styles/v3_geometry.zig").settings_height }, .direction = .column, .gap = 0, .padding = .{}, .background = c.overlay, .border = .{ .width = 0, .color = c.border, .radius = 14 }, .shadow = .{ .blur = 32, .offset_y = 24, .color = c.shadow }, .hit_behavior = .@"opaque", .hit_roles = .{ .pointer = true, .scroll = true } };
}
pub fn settingsBody(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .fill(), .min_height = 0, .direction = .row, .gap = 10, .padding = .{ .left = 14, .right = 14, .bottom = 12 } };
}
pub fn settingsNavigation(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .{ .px = @import("../../../shared/ui/styles/v3_geometry.zig").settings_sidebar }, .height = .fill(), .flex_shrink = 0, .direction = .column, .padding = .{ .top = 4 }, .gap = 6, .background = ui.Color.TRANSPARENT, .border = .{ .width = 0, .radius = 0 } };
}
pub fn settingsContent(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .height = .fill(), .min_width = 0, .min_height = 0, .direction = .column };
}
pub fn toolbarButton(allocator: std.mem.Allocator, node: *ui.Node) void {
    const c = theme.current();
    node.setStyleInline(allocator, .{ .width = .{ .px = @import("../../../shared/ui/styles/v3_geometry.zig").icon_action }, .height = .{ .px = @import("../../../shared/ui/styles/v3_geometry.zig").icon_action }, .corner_radius = 12, .padding = ui.Padding.ZERO, .flex_shrink = 0, .border = .{ .width = 0, .color = c.border, .radius = 12 } });
}

/// Title-bar tools are zenit's native md icon-only ghost Buttons (Pencil p773F9:
/// 32 × 32, glyph 16, radius 6) at their default size. Status controls that the
/// workspace chrome folds into the toolbar as icons take the same square.
pub const toolbar_icon_size: f32 = 32;

pub fn emptyGuide(_: *const ui.ThemeTokens) ui.BoxStyle {
    // Pencil hmCmB "Empty content": mascot 88 · copy · actions, gap 20.
    return .{ .width = .{ .px = 520 }, .max_width = 520, .height = .{ .fit = .{} }, .flex_shrink = 0, .direction = .column, .align_items = .center, .padding = .ZERO, .gap = 20 };
}
pub fn emptyActions(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .height = .{ .px = 32 }, .flex_shrink = 0, .direction = .row, .gap = 8, .align_items = .center };
}
/// Pencil hmCmB "Copy": title over description, gap 6, centered.
pub fn emptyCopy(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .height = .{ .fit = .{} }, .flex_shrink = 0, .direction = .column, .gap = 6, .align_items = .center };
}

pub fn collapsedSidebar(_: *const ui.ThemeTokens) ui.BoxStyle {
    const c = theme.current();
    return .{ .shadow = cardShadow(), .inset_shadow = cardHighlight(), .width = .{ .px = sidebar_collapsed }, .height = .fill(), .flex_shrink = 0, .direction = .column, .align_items = .center, .gap = 4, .padding = .{ .top = 8, .bottom = 8 }, .background = c.surface_1, .border = .{ .width = 0, .color = c.border, .radius = card_radius } };
}

pub fn collapsedAction() ui.BoxStyle {
    const c = theme.current();
    return .{ .width = .{ .px = 34 }, .height = .{ .px = 34 }, .flex_shrink = 0, .align_items = .center, .justify = .center, .padding = ui.Padding.ZERO, .background = ui.Color.TRANSPARENT, .border = .{ .width = 0, .color = c.border, .radius = 9 } };
}

test "shell publishes reused registry tokens and repaints retained chrome" {
    const previous = theme.currentName();
    defer theme.select(previous);
    var registry = try @import("../../../config/theme_registry.zig").Registry.init(std.testing.allocator);
    defer registry.deinit();
    const cx = try ui.Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    const publication = try cx.bindState(ThemePublication, .{});
    theme.selectTokens(registry.get("dark").?.ui_tokens);
    const prepared = theme.widgetTheme(theme.currentName());
    publication.publish(cx, prepared);
    const shell = try ui.boxStyled(cx, root, .{});
    cx.root = shell;
    const titlebar = try ui.boxStyled(cx, title, .{});
    try shell.appendChild(cx.allocator, titlebar);
    const side = try ui.boxStyled(cx, sidebar, .{});
    try shell.appendChild(cx.allocator, side);
    const title_id = titlebar.id;
    const side_id = side.id;
    const content = try ui.boxStyled(cx, pane, .{});
    try shell.appendChild(cx.allocator, content);
    const content_id = content.id;
    var previous_publication = cx.tokens;
    for ([_][]const u8{ "light", "sauber", "dark" }) |id| {
        theme.selectTokens(registry.get(id).?.ui_tokens);
        // The prepared registry address never changes, so passing it straight
        // to Cx.setTheme would skip the second and following updates.
        try std.testing.expectEqual(prepared, theme.widgetTheme(theme.currentName()));
        publication.publish(cx, prepared);
        try std.testing.expect(cx.tokens != previous_publication);
        previous_publication = cx.tokens;
        const c = theme.current();
        // The window root paints nothing (shell/styles.yss `root`, single writer since 90ebf53f): the
        // ground between the islands is the window background layer's (background_layers.zig, which
        // has its own theme tests), so a theme change must not write a background onto the root.
        try std.testing.expectEqual(ui.Color.TRANSPARENT, shell.getBackground());
        try std.testing.expectEqual(ui.Color.TRANSPARENT, titlebar.getBackground());
        // Island B v3 (shell/styles.yss, Pencil `aPxql`): the sidebar is flush and
        // transparent over the window ground (no card surface or shadow); the view
        // island keeps radius 12 and declares no background either — its plate
        // (zw-island-focus) is painted by the window background layer from the
        // island's rect (`background_layers.zig`: "the island plate has one writer").
        try std.testing.expectEqual(ui.Color.TRANSPARENT, side.getBackground());
        try std.testing.expectEqual(ui.Color.TRANSPARENT, content.getBackground());
        try std.testing.expectEqual(content_id, content.id);
        try std.testing.expectEqual(card_radius, content.style.effectiveRadius());
        try std.testing.expect(titlebar.style.shadow() == null);
        try std.testing.expect(side.style.shadow() == null);
        try std.testing.expectEqual(c.fg_1, cx.tokens.tokens.color.fg_primary);
        try std.testing.expectEqual(title_id, titlebar.id);
        try std.testing.expectEqual(side_id, side.id);
        try std.testing.expectEqual(title_height, titlebar.style.height.px);
        try std.testing.expectEqual(sidebar_width, side.style.width.px);
    }
}

test "global material publication repaints retained shell after an image becomes ready" {
    const saved_parameters = theme.materialParameters();
    defer _ = theme.setMaterialParameters(saved_parameters.transparency, saved_parameters.blur);
    _ = theme.setMaterialParameters(75, 24);
    const previous = theme.currentName();
    const was_visible = theme.materialVisible();
    defer {
        theme.select(previous);
        _ = theme.setMaterialVisible(was_visible);
    }
    _ = theme.setMaterialVisible(false);
    theme.select(.dark);
    const cx = try ui.Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    const publication = try cx.bindState(ThemePublication, .{});
    publication.publish(cx, theme.widgetTheme(.dark));
    const shell = try ui.boxStyled(cx, root, .{});
    cx.root = shell;
    const recipes = .{ title, sidebar, status, settingsPanel, settingsNavigation };
    var nodes: [recipes.len]*ui.Node = undefined;
    var ids: [recipes.len]u32 = undefined;
    inline for (recipes, 0..) |recipe, index| {
        nodes[index] = try ui.boxStyled(cx, recipe, .{});
        ids[index] = nodes[index].id;
        try shell.appendChild(cx.allocator, nodes[index]);
    }
    const revision = cx.theme_version;
    _ = theme.setMaterialVisible(true);
    publication.publish(cx, theme.widgetTheme(.dark));
    try std.testing.expect(cx.theme_version > revision);
    try std.testing.expectEqual(@as(u8, 0), shell.getBackground().a);
    inline for (recipes, 0..) |recipe, index| {
        const node = nodes[index];
        try std.testing.expectEqual(ids[index], node.id);
        // Island B v3 shell chrome (view bar, sidebar, pane header) is transparent in its
        // YSS recipe; materials paint only the island, so a null recipe fill is transparent.
        try std.testing.expectEqual(recipe(cx.tokens).background orelse ui.Color.TRANSPARENT, node.getBackground());
        try std.testing.expect(node.getBackground().a < 255);
    }
    try std.testing.expectEqual(title_height, nodes[0].style.height.px);
    try std.testing.expectEqual(sidebar_width, nodes[1].style.width.px);
    // The v3 status row is the island pane header (Pencil `QGtx5`, 30 high in
    // shell/styles.yss), not the legacy 26pt status bar constant.
    try std.testing.expectEqual(status(cx.tokens).height.?.px, nodes[2].style.height.px);
    try std.testing.expectEqual(@import("../../../shared/ui/styles/v3_geometry.zig").settings_width, nodes[3].style.width.px);
    try std.testing.expectEqual(@import("../../../shared/ui/styles/v3_geometry.zig").settings_sidebar, nodes[4].style.width.px);
    _ = theme.setMaterialVisible(false);
    publication.publish(cx, theme.widgetTheme(.dark));
    // Only the settings panel keeps an opaque floating fill; the v3 view bar, sidebar and
    // pane header stay transparent over the window ground (shell/styles.yss).
    for (nodes, 0..) |node, index| try std.testing.expectEqual(if (index == 3) theme.current().overlay.a else @as(u8, 0), node.getBackground().a);
    try std.testing.expectEqual(@as(u8, 0), shell.getBackground().a);
}

pub fn emptyTitle(_: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 18, .font_weight = 600, .line_height = 24.0 / 18.0, .color = theme.current().fg_1 };
}
pub fn emptyDescription(_: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 13, .line_height = 20.0 / 13.0, .color = theme.current().fg_2 };
}
pub fn emptyIcon(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .{ .px = 88 }, .height = .{ .px = 88 }, .flex_shrink = 0, .align_items = .center, .justify = .center };
}

pub fn cardHighlight() @typeInfo(@FieldType(ui.BoxStyle, "inset_shadow")).optional.child {
    // Keep the outer shell shadow, without a hard one-pixel highlight rim.
    return .{ .offset_y = 0, .blur = 0, .color = ui.Color.TRANSPARENT };
}
pub fn cardShadow() @typeInfo(@FieldType(ui.BoxStyle, "shadow")).optional.child {
    return .{ .blur = 4.4, .offset_y = 2, .color = theme.current().shadow };
}

test "settings backdrop paints zenit's default modal overlay instead of a transparent barrier" {
    const previous = theme.currentName();
    defer theme.select(previous);
    for ([_]theme.Name{ .dark, .light, .sauber }) |name| {
        theme.select(name);
        const tokens = theme.widgetTheme(name);
        const zenit_default = if (name == .dark) ui.theme.dark else ui.theme.light;
        const backdrop = settingsBackdrop(tokens);
        try std.testing.expectEqual(zenit_default.tokens.color.overlay, backdrop.background.?);
        try std.testing.expect(backdrop.background.?.a > 0);
        try std.testing.expect(backdrop.hit_behavior == .@"opaque");
    }
}
