//! 设置搜索：配置键名（schema 别名）能搜到它所在的面板与控件，原文草稿与原分类在清空搜索后保留。
//! 3f 前这些用例挂旧 `settings_content_view.mountPage`；现在挂 `.yix` 设置窗口（真 `ViewModel` + Ports 替身），
//! 断言不变：同样的搜索词、同样的面板 / 控件 test_id、同样的草稿与分类。
const std = @import("std");
const ui = @import("ui");
const kit = @import("../../../shared/testing/ui_kit.zig");
const Controller = @import("../model/settings_controller.zig").Controller;
const ThemeRegistry = @import("../../../config/theme_registry.zig").Registry;
const m = @import("../model/view_model.zig");
const frame_mod = @import("../view/window_frame.zig");
const settings_window = @import("../view/_settings_window.yix.zig");
const schema = @import("../../../config/settings_schema.zig");
const a = std.testing.allocator;

const Fixture = struct {
    env: kit.Headless,
    controller: Controller,
    registry: ThemeRegistry,
    vm: m.ViewModel,
    frame: frame_mod.Frame,
    root: *ui.Node = undefined,
    pending: bool = false,

    fn init(self: *Fixture, page: usize) !void {
        var initial: @import("../../../config/config.zig").Config = .{};
        initial.ui.materials.background.enabled = true;
        initial.ui.materials.background.path = "/fixture/search-background.png";
        self.* = .{ .env = try kit.headless(a, .{ .width = 960, .height = 780, .root_style = .{ .width = .fill(), .height = .fill(), .direction = .column } }), .controller = try Controller.init(a, initial), .registry = try ThemeRegistry.init(a), .vm = undefined, .frame = undefined };
        self.controller.drill_down = true;
        self.controller.folded_sections = 0;
        self.controller.model.selectPage(page);
        self.controller.history.reset(self.controller.location());
        self.vm = m.ViewModel.init(&self.controller, .{ .context = self, .run = run, .allow = allow, .appearance = appearance });
        self.frame = .{ .vm = &self.vm };
        try self.vm.attach(self.env.scope);
        self.root = try ui.view.render(self.env.scope, self.env.cx, settings_window.SettingsWindow(.{ .vm = &self.vm, .frame = &self.frame }));
        try self.env.mount(self.root);
        self.env.frames(2);
    }
    fn deinit(self: *Fixture) void {
        self.env.deinit();
        self.controller.deinit();
        self.registry.deinit();
    }
    fn run(raw: *anyopaque, effect: m.Effect) void {
        const self: *Fixture = @ptrCast(@alignCast(raw));
        switch (effect) {
            .navigated, .rebuild => self.pending = true,
            else => {},
        }
    }
    fn allow(_: *anyopaque, _: m.Gate) bool {
        return true;
    }
    fn appearance(raw: *anyopaque) m.AppearanceStatus {
        const self: *Fixture = @ptrCast(@alignCast(raw));
        return .{ .ready = true, .registry = &self.registry, .saved_theme = self.controller.original.value.ui.theme, .font_actual = "Monaco" };
    }
    /// The window's search field (SettingsHost: a new content epoch after the query changes).
    fn search(self: *Fixture, query: []const u8) void {
        self.vm.dispatch(m.Intent.searchFor(query));
        self.vm.remountContent();
        self.pending = false;
        self.env.frames(3);
    }
    fn find(self: *Fixture, id: []const u8) ?*ui.Node {
        return kit.findByTestId(self.root, id);
    }
};

fn displayed(node: *ui.Node) bool {
    return node.isDisplayedInTree() and node.globalRect().h > 0;
}

test "settings search schema aliases mount their actual appearance section and control" {
    const Case = struct { query: []const u8, section: []const u8, control: ?[]const u8 = null };
    const cases = [_]Case{
        .{ .query = "theme", .section = "themes", .control = "settings.theme.current" },
        .{ .query = "font_family", .section = "font", .control = "settings.field.font_family" },
        .{ .query = "font_size", .section = "font", .control = "settings.field.font_size" },
        .{ .query = "font_weight", .section = "font", .control = "settings.field.font_weight" },
        .{ .query = "line_height", .section = "font", .control = "settings.field.line_height" },
        .{ .query = "cursor_style", .section = "font", .control = "settings.field.cursor_style" },
        .{ .query = "sidebar_collapsed", .section = "aids", .control = "settings.toggle.sidebar_collapsed" },
        .{ .query = "timestamp_gutter", .section = "aids", .control = "settings.toggle.timestamp_gutter" },
        .{ .query = "command_info", .section = "aids", .control = "settings.toggle.command_info" },
        .{ .query = "input_line_highlight", .section = "aids", .control = "settings.toggle.input_line_highlight" },
        .{ .query = "enabled", .section = "aids", .control = "settings.toggle.enabled" },
        .{ .query = "blur_px", .section = "materials", .control = "settings.field.blur_px" },
        .{ .query = "path", .section = "materials", .control = "settings.background.filename" },
        .{ .query = "transparency", .section = "materials", .control = "settings.field.transparency" },
        .{ .query = "fit", .section = "materials", .control = "settings.field.fit" },
        .{ .query = "alignment_x", .section = "materials", .control = "settings.field.alignment" },
        .{ .query = "alignment_y", .section = "materials", .control = "settings.field.alignment" },
    };
    for (cases) |case| {
        var f: Fixture = undefined;
        try f.init(2);
        defer f.deinit();
        f.search(case.query);
        try std.testing.expectEqual(@as(usize, 2), f.controller.model.page_index);
        var buffer: [80]u8 = undefined;
        const id = try std.fmt.bufPrint(&buffer, "settings.appearance.{s}", .{case.section});
        const section = f.find(id);
        if (section == null or !displayed(section.?)) std.debug.print("missing appearance section for schema alias {s}\n", .{case.query});
        try std.testing.expect(section != null);
        try std.testing.expect(displayed(section.?));
        if (case.control) |control| {
            if (kit.findByTestId(section.?, control) == null) std.debug.print("missing control {s} for alias {s}\n", .{ control, case.query });
            try std.testing.expect(kit.findByTestId(section.?, control) != null);
        }
    }
}

test "settings search aliases preserve invalid raw draft and original category on clear" {
    var f: Fixture = undefined;
    try f.init(3);
    defer f.deinit();
    try std.testing.expectError(error.OutOfRange, f.controller.editRaw("ui", "font_size", "97"));
    const folds = f.controller.folded_sections;
    f.search("font_size");
    const shownIn = struct {
        fn of(fx: *Fixture, id: []const u8) bool {
            const node = fx.find(id) orelse return false;
            return displayed(node);
        }
    }.of;
    try std.testing.expect(shownIn(&f, "settings.field.font_size"));
    try std.testing.expect(!shownIn(&f, "settings.field.font_family"));
    try std.testing.expect(!shownIn(&f, "settings.field.font_weight"));
    try std.testing.expect(!shownIn(&f, "settings.field.line_height"));
    try std.testing.expect(shownIn(&f, "settings.field.cursor_style"));
    try std.testing.expect(shownIn(&f, "settings.font.preview"));
    const raw = f.controller.raw_fields[schema.find("ui", "font_size").?];
    try std.testing.expectEqualStrings("97", raw.input.?);
    try std.testing.expect(raw.problem != null);
    try std.testing.expect(!f.controller.canSave());
    f.search("");
    try std.testing.expectEqual(@as(usize, 3), f.controller.model.page_index);
    try std.testing.expectEqual(folds, f.controller.folded_sections);
    try std.testing.expectEqualStrings("97", f.controller.raw_fields[schema.find("ui", "font_size").?].input.?);
}

test "settings search every scalar schema key keeps its own category and mounts its control" {
    const pages = @import("../../../config/settings_pages.zig").pages;
    for (schema.fields) |entry| {
        const expected_page = for (pages, 0..) |page, index| {
            if (std.mem.eql(u8, entry.page, page.name)) break index;
        } else unreachable;
        var f: Fixture = undefined;
        try f.init(expected_page);
        defer f.deinit();
        // Rotation fields exist only for a directory; source itself is detected
        // by the existing image/directory picker, rather than a separate control.
        if (std.mem.eql(u8, entry.section, "ui.materials.background") and
            (std.mem.eql(u8, entry.key, "order") or std.mem.eql(u8, entry.key, "interval_minutes")))
            try f.controller.editKey(entry.section, "source", .{ .text = "directory" });
        f.search(entry.key);
        try std.testing.expectEqual(expected_page, f.controller.model.page_index);
        var buffer: [96]u8 = undefined;
        const id = if (expected_page == 0) blk: {
            if (std.mem.eql(u8, entry.key, "theme")) break :blk "settings.theme.current";
            if (std.mem.eql(u8, entry.key, "path") or std.mem.eql(u8, entry.key, "source")) break :blk "settings.background.filename";
            if (std.mem.eql(u8, entry.key, "alignment_x") or std.mem.eql(u8, entry.key, "alignment_y")) break :blk "settings.field.alignment";
            const boolean = @import("../model/settings_values.zig").read(f.controller.model.value, entry.section, entry.key).? == .boolean;
            break :blk try std.fmt.bufPrint(&buffer, "settings.{s}.{s}", .{ if (boolean) "toggle" else "field", entry.key });
        } else if (std.mem.eql(u8, entry.section, "ai") and std.mem.eql(u8, entry.key, "default_provider")) "settings.ai.behavior" else try std.fmt.bufPrint(&buffer, "settings.field.{s}", .{entry.key});
        if (f.find(id) == null) std.debug.print("missing scalar search control {s}.{s} ({s})\n", .{ entry.section, entry.key, id });
        try std.testing.expect(f.find(id) != null);
    }
}
