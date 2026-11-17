//! Shared fixtures for ZeroWork component tests: a windowless `Cx`, lookup by
//! `test_id`, and the built-in theme matrix.
//!
//! Usage:
//!
//!     const kit = @import("shared/testing/ui_kit.zig"); // path relative to the test file
//!
//!     test "my view keeps its save button" {
//!         var env = try kit.headless(std.testing.allocator, .{ .width = 640, .height = 480 });
//!         defer env.deinit();
//!         const view = try MyView.mount(env.cx, env.scope, .{});
//!         try env.mount(view.root);
//!         env.frame();
//!         const save = try env.expect("settings.save");
//!         try std.testing.expect(save.globalRect().w > 0);
//!     }
//!
//!     test "my view is readable in every theme" {
//!         try kit.forEachTheme(std.testing.allocator, .{}, {}, struct {
//!             fn run(_: void, env: *kit.Headless, case: kit.ThemeCase) !void {
//!                 _ = case.name; // app_theme.Name family; case.id is the theme id
//!                 try env.mount(try MyView.mount(env.cx, env.scope, .{}));
//!                 env.frame();
//!             }
//!         }.run);
//!     }
//!
//! Boundaries (what this file does not do):
//! - No real window, renderer, fonts beyond zenit's headless defaults, or event loop.
//! - No feature views, core services, settings, data directories or network.
//! - Lookups are exact `meta.ownership.meta.test_id` matches over `children`;
//!   they ignore visibility, display, overlays and text content.
//! - Theme state is process-global (`shared/ui/theme/app_theme.zig`). The kit restores the
//!   appearance family and material parameters it touched; a registry palette
//!   selected before the call is restored as its family (`select`), exactly
//!   like the existing hand-written loops.
//! - It does not replace the existing per-file helpers; migration is separate.
const std = @import("std");
const ui = @import("ui");
const app_theme = @import("../ui/theme/app_theme.zig");
const ThemePublication = @import("../ui/theme/theme_publication.zig").ThemePublication;
const theme_registry = @import("../../config/theme_registry.zig");

// -- lookup by test_id ------------------------------------------------------

/// Depth-first, pre-order exact `test_id` match; the first hit wins.
/// Asserts that `actual` (the panel of a native Popover / Menu / Modal / Select) paints the same
/// surface as `reference`, an untouched panel of the same native component mounted in the same
/// window: fill, border, corner radius, shadows, backdrop glass and outline. Use it to pin
/// "this surface is zenit's own, nothing repaints it".
pub fn expectSameSurface(reference: *ui.Node, actual: *ui.Node) !void {
    try std.testing.expectEqual(reference.getBackground(), actual.getBackground());
    try std.testing.expectEqual(reference.style.border.width, actual.style.border.width);
    try std.testing.expectEqual(reference.style.border.color, actual.style.border.color);
    try std.testing.expectEqual(reference.style.effectiveRadius(), actual.style.effectiveRadius());
    const expected = reference.style.shadowSlice();
    const shadows = actual.style.shadowSlice();
    try std.testing.expectEqual(expected.len, shadows.len);
    for (expected, shadows) |a, b| try std.testing.expectEqual(a, b);
    try std.testing.expectEqual(reference.style.glass_params(), actual.style.glass_params());
    try std.testing.expectEqual(reference.style.outline(), actual.style.outline());
}
/// An untouched native Popover kept open in `parent`'s window, as the reference for
/// `expectSameSurface`. Returns its panel.
pub fn referencePopover(cx: *ui.Cx, scope: *ui.Scope, parent: *ui.Node) !*ui.Node {
    const open = try scope.createSignal(bool, true);
    const popup = try ui.widgets.Popover(.{ .open = open, .trigger = .manual, .enter_transition = .none, .exit_transition = .none, .close_on_outside_click = false, .close_on_escape = false, .trap_focus = false }).mount(scope, cx);
    try parent.appendChild(cx.allocator, popup.wrapper);
    return popup.chrome;
}
pub fn findByTestId(root: *ui.Node, id: []const u8) ?*ui.Node {
    if (root.meta.ownership.meta.test_id) |value| if (std.mem.eql(u8, value, id)) return root;
    for (root.children.items) |child| if (findByTestId(child, id)) |found| return found;
    return null;
}

/// Like `findByTestId`, but a miss is `error.TestIdNotFound` and names the id.
pub fn expectByTestId(root: *ui.Node, id: []const u8) error{TestIdNotFound}!*ui.Node {
    return findByTestId(root, id) orelse {
        std.debug.print("\nui_kit: no node with test_id \"{s}\"\n", .{id});
        return error.TestIdNotFound;
    };
}

/// Every exact match in depth-first pre-order. Caller frees the slice.
pub fn findAllByTestId(allocator: std.mem.Allocator, root: *ui.Node, id: []const u8) ![]*ui.Node {
    return collect(allocator, root, id, .exact);
}

/// Every node whose test_id starts with `prefix` (dynamic ids such as
/// `settings.field.<key>`), depth-first pre-order. Caller frees the slice.
pub fn findAllByTestIdPrefix(allocator: std.mem.Allocator, root: *ui.Node, prefix: []const u8) ![]*ui.Node {
    return collect(allocator, root, prefix, .prefix);
}

const Match = enum { exact, prefix };

fn collect(allocator: std.mem.Allocator, root: *ui.Node, needle: []const u8, match: Match) ![]*ui.Node {
    var result: std.ArrayList(*ui.Node) = .empty;
    errdefer result.deinit(allocator);
    try collectInto(allocator, &result, root, needle, match);
    return result.toOwnedSlice(allocator);
}

fn collectInto(allocator: std.mem.Allocator, result: *std.ArrayList(*ui.Node), node: *ui.Node, needle: []const u8, match: Match) !void {
    if (node.meta.ownership.meta.test_id) |value| {
        const hit = switch (match) {
            .exact => std.mem.eql(u8, value, needle),
            .prefix => std.mem.startsWith(u8, value, needle),
        };
        if (hit) try result.append(allocator, node);
    }
    for (node.children.items) |child| try collectInto(allocator, result, child, needle, match);
}

// -- headless environment ---------------------------------------------------

pub const Options = struct {
    /// Viewport; the default root box fills it.
    width: f32 = 900,
    height: f32 = 600,
    root_style: ui.BoxStyle = .{ .width = .fill(), .height = .fill() },
    /// Locked frame clock step (ms) so `frame()` is deterministic; null keeps
    /// zenit's wall clock.
    frame_step_ms: ?f32 = 16,
    /// Select this appearance family for the environment's lifetime and
    /// restore the previous family in `deinit`. Null keeps the current theme.
    theme: ?app_theme.Name = null,
    /// Publish the current widget theme like a production window does
    /// (`theme_publication.ThemePublication`).
    publish_theme: bool = true,
    io: ?std.Io = null,
};

/// A windowless `Cx` with a root scope and a root box, ready for mounting.
/// All nodes appended under `root` (or assigned to `cx.root`) are released by
/// `deinit`.
pub const Headless = struct {
    allocator: std.mem.Allocator,
    cx: *ui.Cx,
    scope: *ui.Scope,
    root: *ui.Node,
    publication: *ThemePublication,
    restore_theme: ?app_theme.Name = null,

    pub fn deinit(self: *Headless) void {
        self.scope.dispose();
        self.cx.deinit();
        if (self.restore_theme) |name| app_theme.select(name);
        self.* = undefined;
    }

    /// Append `node` under the root box.
    pub fn mount(self: *Headless, node: *ui.Node) !void {
        try self.root.appendChild(self.allocator, node);
    }

    /// One host frame: advance the clock, lay out, render.
    pub fn frame(self: *Headless) void {
        self.cx.advanceFrameClock();
        self.cx.layout();
        _ = self.cx.render();
    }

    pub fn frames(self: *Headless, count: usize) void {
        for (0..count) |_| self.frame();
    }

    /// Re-publish the current global widget theme (after `app_theme.select`
    /// or `selectTokens`).
    pub fn publishTheme(self: *Headless) void {
        self.publication.publish(self.cx, app_theme.widgetTheme(app_theme.currentName()));
    }

    /// Searches from `cx.root`, so tests that replace the root still work.
    pub fn find(self: *Headless, id: []const u8) ?*ui.Node {
        return findByTestId(self.cx.root orelse return null, id);
    }

    pub fn expect(self: *Headless, id: []const u8) error{TestIdNotFound}!*ui.Node {
        const root = self.cx.root orelse return error.TestIdNotFound;
        return expectByTestId(root, id);
    }
};

pub fn headless(allocator: std.mem.Allocator, options: Options) !Headless {
    const previous = app_theme.currentName();
    if (options.theme) |name| app_theme.select(name);
    errdefer if (options.theme != null) app_theme.select(previous);
    const cx = try ui.Cx.init(allocator, options.io orelse std.testing.io);
    errdefer cx.deinit();
    cx.setViewport(options.width, options.height);
    if (options.frame_step_ms) |step| try cx.setTestFrameStep(step);
    // Widget transitions read the shared clock at mount; bind this Cx's clock
    // first so an earlier test's clock cannot leak into this fixture.
    cx.bindFrameClock();
    const scope = try ui.Scope.init(allocator, null, cx.owner);
    errdefer scope.dispose();
    const publication = try cx.bindState(ThemePublication, .{});
    if (options.publish_theme) publication.publish(cx, app_theme.widgetTheme(app_theme.currentName()));
    const root = try ui.box(cx, options.root_style, .{});
    cx.root = root;
    return .{
        .allocator = allocator,
        .cx = cx,
        .scope = scope,
        .root = root,
        .publication = publication,
        .restore_theme = if (options.theme != null) previous else null,
    };
}

// -- theme matrix -----------------------------------------------------------

pub const ThemeSet = enum {
    /// Every `app_theme.Name` (dark, light, sauber): what views branch on.
    families,
    /// Every built-in registry palette (`config/theme_presets.zig` ids, in
    /// `theme_registry.Registry` order), applied with `selectTokens`.
    builtin_palettes,
};

pub const ThemeCase = struct {
    /// `@tagName(name)` for families, the registry id for palettes. Valid for
    /// the duration of the callback.
    id: []const u8,
    /// Appearance family in effect (`app_theme.currentName()`).
    name: app_theme.Name,
    index: usize,
    count: usize,
};

pub const ThemeOptions = struct {
    set: ThemeSet = .families,
    /// Environment built fresh for every theme; `theme` is ignored.
    headless: Options = .{},
};

const ThemeSnapshot = struct {
    name: app_theme.Name,
    material_visible: bool,
    transparency: f32,
    blur: f32,

    fn capture() ThemeSnapshot {
        const material = app_theme.materialParameters();
        return .{ .name = app_theme.currentName(), .material_visible = app_theme.materialVisible(), .transparency = material.transparency, .blur = material.blur };
    }
    fn restoreMaterial(self: ThemeSnapshot) void {
        _ = app_theme.setMaterialVisible(self.material_visible);
        _ = app_theme.setMaterialParameters(self.transparency, self.blur);
    }
    fn restore(self: ThemeSnapshot) void {
        app_theme.select(self.name);
        self.restoreMaterial();
    }
};

/// Runs `callback(context, *Headless, ThemeCase)` once per built-in theme.
/// Each theme gets a fresh `Headless` (new Cx and scope) with the theme already
/// selected and published, and the material parameters reset to their values
/// at entry. The first callback error stops the loop, is printed with the
/// theme id, and is returned unchanged. Global theme state is restored on exit.
pub fn forEachTheme(allocator: std.mem.Allocator, options: ThemeOptions, context: anytype, comptime callback: anytype) !void {
    const snapshot = ThemeSnapshot.capture();
    defer snapshot.restore();
    var env_options = options.headless;
    env_options.theme = null;
    switch (options.set) {
        .families => {
            const names = std.enums.values(app_theme.Name);
            for (names, 0..) |name, index| {
                snapshot.restoreMaterial();
                app_theme.select(name);
                try runTheme(allocator, env_options, .{ .id = @tagName(name), .name = name, .index = index, .count = names.len }, context, callback);
            }
        },
        .builtin_palettes => {
            var registry = try theme_registry.Registry.init(allocator);
            defer registry.deinit();
            var count: usize = 0;
            for (registry.records.items) |record| count += @intFromBool(record.source_kind == .builtin);
            var index: usize = 0;
            for (registry.records.items) |record| {
                if (record.source_kind != .builtin) continue;
                snapshot.restoreMaterial();
                app_theme.selectTokens(record.ui_tokens);
                try runTheme(allocator, env_options, .{ .id = record.id, .name = app_theme.currentName(), .index = index, .count = count }, context, callback);
                index += 1;
            }
        },
    }
}

fn runTheme(allocator: std.mem.Allocator, options: Options, case: ThemeCase, context: anytype, comptime callback: anytype) !void {
    errdefer std.debug.print("\nui_kit forEachTheme: theme \"{s}\" ({d}/{d}) failed\n", .{ case.id, case.index + 1, case.count });
    var env = try headless(allocator, options);
    defer env.deinit();
    try callback(context, &env, case);
}

// -- tests ------------------------------------------------------------------

const testing = std.testing;

fn testBox(env: *Headless, parent: *ui.Node, id: ?[]const u8) !*ui.Node {
    const node = try ui.box(env.cx, .{ .width = .{ .px = 10 }, .height = .{ .px = 10 } }, .{});
    node.meta.ownership.meta.test_id = id;
    try parent.appendChild(env.allocator, node);
    return node;
}

test "ui_kit headless creates a laid-out root and releases everything" {
    var env = try headless(testing.allocator, .{ .width = 320, .height = 200 });
    defer env.deinit();
    try testing.expectEqual(env.root, env.cx.root.?);
    const child = try testBox(&env, env.root, "kit.child");
    const signal = try env.scope.createSignal(bool, true);
    try testing.expect(signal.get());
    env.frames(3);
    const rect = env.root.globalRect();
    try testing.expectApproxEqAbs(@as(f32, 320), rect.w, 0.01);
    try testing.expectApproxEqAbs(@as(f32, 200), rect.h, 0.01);
    try testing.expectEqual(@as(f32, 10), child.globalRect().w);
    try testing.expectEqual(child, env.find("kit.child").?);
}

test "ui_kit headless theme option selects and restores the family" {
    const previous = app_theme.currentName();
    defer app_theme.select(previous);
    app_theme.select(.dark);
    {
        var env = try headless(testing.allocator, .{ .theme = .sauber });
        defer env.deinit();
        try testing.expectEqual(app_theme.Name.sauber, app_theme.currentName());
        try testing.expectEqualStrings("sauber", env.cx.tokens.name);
    }
    try testing.expectEqual(app_theme.Name.dark, app_theme.currentName());
}

test "ui_kit findByTestId hits, misses, nests and returns the first duplicate" {
    var env = try headless(testing.allocator, .{});
    defer env.deinit();
    const outer = try testBox(&env, env.root, "kit.outer");
    const first = try testBox(&env, outer, null);
    const deep = try testBox(&env, first, "kit.dup");
    const nested = try testBox(&env, deep, "kit.deep");
    const later = try testBox(&env, env.root, "kit.dup");
    const prefixed = try testBox(&env, later, "kit.dup.child");

    try testing.expectEqual(outer, findByTestId(env.root, "kit.outer").?);
    try testing.expectEqual(nested, findByTestId(env.root, "kit.deep").?);
    try testing.expectEqual(deep, findByTestId(env.root, "kit.dup").?);
    try testing.expectEqual(later, findByTestId(later, "kit.dup").?);
    try testing.expectEqual(@as(?*ui.Node, null), findByTestId(env.root, "kit.missing"));
    try testing.expectEqual(@as(?*ui.Node, null), findByTestId(env.root, "kit.du"));
    try testing.expectEqual(@as(?*ui.Node, null), findByTestId(outer, "kit.dup.child"));
    try testing.expectError(error.TestIdNotFound, expectByTestId(env.root, "kit.missing"));
    try testing.expectError(error.TestIdNotFound, env.expect("kit.missing"));
    try testing.expectEqual(nested, try env.expect("kit.deep"));

    const all = try findAllByTestId(testing.allocator, env.root, "kit.dup");
    defer testing.allocator.free(all);
    try testing.expectEqualSlices(*ui.Node, &.{ deep, later }, all);
    const by_prefix = try findAllByTestIdPrefix(testing.allocator, env.root, "kit.dup");
    defer testing.allocator.free(by_prefix);
    try testing.expectEqualSlices(*ui.Node, &.{ deep, later, prefixed }, by_prefix);
    const none = try findAllByTestId(testing.allocator, env.root, "kit.missing");
    defer testing.allocator.free(none);
    try testing.expectEqual(@as(usize, 0), none.len);
}

const Visits = struct {
    ids: [64][]const u8 = undefined,
    names: [64]app_theme.Name = undefined,
    backgrounds: [64]ui.Color = undefined,
    count: usize = 0,
    fail_at: ?usize = null,
    // Palette ids are registry-owned and only valid inside the callback.
    expected_ids: ?[]const []const u8 = null,

    fn visit(self: *Visits, env: *Headless, case: ThemeCase) !void {
        try testing.expectEqual(self.count, case.index);
        try testing.expectEqual(case.name, app_theme.currentName());
        // Isolation: a fresh environment per theme, with no leftovers from the last callback.
        try testing.expectEqual(@as(usize, 0), env.root.children.items.len);
        try testing.expectEqual(@as(?*ui.Node, null), env.find("kit.leftover"));
        _ = try testBox(env, env.root, "kit.leftover");
        _ = app_theme.setMaterialParameters(100, 40);
        if (self.expected_ids) |ids| try testing.expectEqualStrings(ids[case.index], case.id);
        self.ids[self.count] = case.id;
        self.names[self.count] = case.name;
        self.backgrounds[self.count] = env.cx.tokens.tokens.color.bg_base;
        self.count += 1;
        if (self.fail_at) |index| if (index == case.index) return error.KitCallbackFailed;
    }
};

test "ui_kit forEachTheme visits every family from app_theme.Name once with distinct tokens" {
    const before = ThemeSnapshot.capture();
    var visits: Visits = .{};
    try forEachTheme(testing.allocator, .{}, &visits, Visits.visit);
    const names = std.enums.values(app_theme.Name);
    try testing.expectEqual(names.len, visits.count);
    for (names, 0..) |name, index| {
        try testing.expectEqual(name, visits.names[index]);
        try testing.expectEqualStrings(@tagName(name), visits.ids[index]);
        for (0..index) |other| try testing.expect(!std.meta.eql(visits.backgrounds[index], visits.backgrounds[other]));
    }
    const after = ThemeSnapshot.capture();
    try testing.expectEqual(before, after);
}

test "ui_kit forEachTheme builtin palettes follow the registry list" {
    const before = ThemeSnapshot.capture();
    const ids = @import("../../config/theme_presets.zig").ids;
    var visits: Visits = .{ .expected_ids = &ids };
    try testing.expect(ids.len <= visits.ids.len);
    try forEachTheme(testing.allocator, .{ .set = .builtin_palettes }, &visits, Visits.visit);
    try testing.expectEqual(ids.len, visits.count);
    var distinct: usize = 0;
    for (0..ids.len) |index| {
        var seen = false;
        for (0..index) |other| seen = seen or std.meta.eql(visits.backgrounds[index], visits.backgrounds[other]);
        distinct += @intFromBool(!seen);
    }
    // Palettes differ by many roles; the app ground alone is already unique for most.
    try testing.expect(distinct * 2 > ids.len);
    try testing.expectEqual(before, ThemeSnapshot.capture());
}

test "ui_kit forEachTheme stops at the failing theme and returns its error" {
    const before = ThemeSnapshot.capture();
    var visits: Visits = .{ .fail_at = 1 };
    try testing.expectError(error.KitCallbackFailed, forEachTheme(testing.allocator, .{}, &visits, Visits.visit));
    try testing.expectEqual(@as(usize, 2), visits.count);
    try testing.expectEqualStrings(@tagName(std.enums.values(app_theme.Name)[1]), visits.ids[1]);
    try testing.expectEqual(before, ThemeSnapshot.capture());
}
