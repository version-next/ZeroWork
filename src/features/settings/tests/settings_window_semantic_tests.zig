//! Settings window behaviour by test id (P3 safety net, `e2e/settings_revamp_native.ts`
//! at component level): category overview → subpages and their panes, Back /
//! Forward history, cross-category search, the draft on the Save Bar and the
//! overview summaries, save / revert, and deep links.
//!
//! Test bodies only use test ids, visible text, `disabled` and the owned draft
//! (Controller). How the window is mounted lives in `Window` alone: the
//! `.yix` `SettingsWindow` over the real `ViewModel` (a Ports double in place of
//! SettingsHost). 3f removed the legacy `mountPage` implementation these bodies
//! also used to run against.
const std = @import("std");
const ui = @import("ui");
const kit = @import("../../../shared/testing/ui_kit.zig");
const Controller = @import("../model/settings_controller.zig").Controller;
const RuntimeConfig = @import("../../../config/runtime_config.zig").RuntimeConfig;
const ThemeRegistry = @import("../../../config/theme_registry.zig").Registry;
const appearance = @import("../view/appearance_ui_context.zig");
const m = @import("../model/view_model.zig");
const frame_mod = @import("../view/window_frame.zig");
const settings_window = @import("../view/_settings_window.yix.zig");
const app_theme = @import("../../../shared/ui/theme/app_theme.zig");

// -- the window under test ----------------------------------------------------

const Window = struct {
    env: kit.Headless,
    controller: Controller,
    registry: ThemeRegistry,
    tmp: std.testing.TmpDir,
    runtime: RuntimeConfig,
    appearance_context: appearance.Context,
    page_root: ?*ui.Node = null,
    pending: bool = false,
    vm: m.ViewModel = undefined,
    frame: frame_mod.Frame = undefined,

    fn init(self: *Window) !void {
        const a = std.testing.allocator;
        self.* = .{
            .env = try kit.headless(a, .{ .width = 960, .height = 780, .root_style = .{ .width = .fill(), .height = .fill(), .direction = .column } }),
            .controller = undefined,
            .registry = try ThemeRegistry.init(a),
            .tmp = std.testing.tmpDir(.{}),
            .runtime = undefined,
            .appearance_context = undefined,
        };
        self.runtime = try RuntimeConfig.loadOrDefault(std.testing.io, self.tmp.dir, a, "config.toml");
        self.controller = try Controller.init(a, self.runtime.value);
        self.appearance_context = .{ .registry = &self.registry, .runtime = &self.runtime, .context = self, .request = appearanceRequest, .busy = notBusy, .font_status = fontStatus };
        // As SettingsHost opens its window: drill-down pages, every pane open,
        // history starting at the current location.
        self.controller.drill_down = true;
        self.controller.folded_sections = 0;
        self.controller.history.reset(self.controller.location());
        self.vm = m.ViewModel.init(&self.controller, .{ .context = self, .run = runEffect, .allow = allowAll });
        self.frame = .{ .vm = &self.vm, .appearance = &self.appearance_context };
        try self.vm.attach(self.env.scope);
        const root = try ui.view.render(self.env.scope, self.env.cx, settings_window.SettingsWindow(.{ .vm = &self.vm, .frame = &self.frame }));
        self.page_root = root;
        try self.env.mount(root);
        self.env.frames(2);
    }

    fn deinit(self: *Window) void {
        self.env.deinit();
        self.controller.deinit();
        self.registry.deinit();
        self.runtime.deinit();
        self.tmp.cleanup();
    }

    // Adapter: replace the page as SettingsHost does after a change (SettingsHost.rebuildAll: a new content epoch).
    fn remount(self: *Window) !void {
        self.pending = false;
        self.vm.remountContent();
        self.env.frames(2);
    }

    fn settle(self: *Window) !void {
        var rebuilds: usize = 0;
        while (self.pending) : (rebuilds += 1) {
            if (rebuilds == 8) return error.SettingsRebuildLoop;
            try self.remount();
        }
    }

    // Ports double (SettingsHost.runEffect / allowGate, minus I/O).
    fn runEffect(raw: *anyopaque, effect: m.Effect) void {
        const self: *Window = @ptrCast(@alignCast(raw));
        switch (effect) {
            .navigated, .rebuild => self.pending = true,
            .save => {
                // SettingsHost.runSave：提交后同步回流 `.save_finished`（H-save：保存后的去向——离开 / 关窗——在这里执行）。
                const result = self.controller.save(std.testing.io, self.tmp.dir, &self.runtime);
                self.pending = true;
                self.vm.dispatch(m.Intent.saveFinished(if (result) |_| null else |err| err));
            },
            .revert => {
                self.controller.discardLatest(&self.runtime) catch {};
                self.pending = true;
            },
            else => {},
        }
    }
    fn allowAll(_: *anyopaque, _: m.Gate) bool {
        return true;
    }

    /// SettingsHost.navigateSettings: a location through the view-model (search cleared).
    fn navigate(self: *Window, target: m.Location) void {
        self.vm.dispatch(m.Intent.openAt(target));
    }
    fn appearanceRequest(_: *anyopaque, _: appearance.Command) void {}
    fn notBusy(_: *anyopaque) bool {
        return false;
    }
    fn fontStatus(_: *anyopaque) appearance.FontStatus {
        return .{ .problem = null };
    }

    // -- user-level operations ----------------------------------------------

    /// A Settings Nav category row (the nav list belongs to the window shell).
    fn openCategory(self: *Window, page: u8) !void {
        self.navigate(.{ .page = page });
        try self.settle();
    }
    /// A deep link (e.g. the assistant's "configure provider").
    fn deepLink(self: *Window, page: u8, sub: u8) !void {
        self.navigate(.{ .page = page, .sub = sub });
        try self.settle();
    }
    /// Typing into the window's search field (owned by the window shell).
    fn search(self: *Window, query: []const u8) !void {
        self.vm.dispatch(m.Intent.searchFor(query));
        try self.settle();
    }
    /// Real pointer click at the centre of the shown node.
    fn click(self: *Window, id: []const u8) !void {
        const node = try self.expectShown(id);
        const rect = node.globalRect();
        self.env.cx.handleClick(rect.x + rect.w / 2, rect.y + rect.h / 2);
        self.env.frame();
        try self.settle();
    }
    /// Focus the field, select all and type, as a user would.
    fn typeInto(self: *Window, id: []const u8, typed: []const u8) !void {
        const node = try self.expectShown(id);
        self.env.cx.setFocus(node);
        self.env.cx.handleKeyDown(.a, .{ .super = true });
        self.env.cx.handleTextInput(typed);
        self.env.frame();
        try self.settle();
    }

    // -- observations --------------------------------------------------------

    fn shownNode(self: *Window, id: []const u8) ?*ui.Node {
        const root = self.env.cx.root orelse return null;
        const all = kit.findAllByTestId(std.testing.allocator, root, id) catch return null;
        defer std.testing.allocator.free(all);
        for (all) |node| if (isShown(node)) return node;
        return null;
    }
    fn shown(self: *Window, id: []const u8) bool {
        return self.shownNode(id) != null;
    }
    fn expectShown(self: *Window, id: []const u8) !*ui.Node {
        return self.shownNode(id) orelse {
            std.debug.print("\nsettings window: \"{s}\" is not shown\n", .{id});
            return error.SettingsNodeNotShown;
        };
    }
    /// Visible text of the node's subtree, concatenated in tree order.
    fn text(self: *Window, id: []const u8, buffer: []u8) ![]const u8 {
        var used: usize = 0;
        collectText(try self.expectShown(id), buffer, &used);
        return buffer[0..used];
    }
    fn disabled(self: *Window, id: []const u8) !bool {
        const node = try self.expectShown(id);
        const a11y = node.behavior.interaction.a11y orelse return false;
        return a11y.disabled;
    }
    fn title(self: *Window, buffer: []u8) ![]const u8 {
        return self.text("settings.page.title", buffer);
    }
};

fn isShown(node: *ui.Node) bool {
    var current: ?*ui.Node = node;
    while (current) |item| : (current = item.parent) if (item.style.display == .none) return false;
    const rect = node.globalRect();
    return rect.w > 0 and rect.h > 0;
}

fn collectText(node: *ui.Node, buffer: []u8, used: *usize) void {
    if (node.style.display == .none) return;
    if (node.getText()) |value| {
        const n = @min(value.content.len, buffer.len - used.*);
        @memcpy(buffer[used.*..][0..n], value.content[0..n]);
        used.* += n;
    }
    for (node.children.items) |child| collectText(child, buffer, used);
}

fn expectTitle(w: *Window, expected: []const u8) !void {
    var buffer: [128]u8 = undefined;
    try std.testing.expectEqualStrings(expected, try w.title(&buffer));
}

// -- the drill-down map (mirrors e2e/settings_revamp_native.ts) ---------------

const Sub = struct { slug: []const u8, title: []const u8, panes: []const []const u8 };
const Category = struct { page: u8, slug: []const u8, name: []const u8, subs: []const Sub };

const overview_categories = [_]Category{
    .{ .page = 0, .slug = "appearance", .name = "外观与主题", .subs = &.{
        .{ .slug = "theme", .title = "主题", .panes = &.{ "settings.appearance.themes", "settings.appearance.app_icon", "settings.appearance.materials", "settings.appearance.preview" } },
        .{ .slug = "font", .title = "字体与排版", .panes = &.{"settings.appearance.font"} },
        .{ .slug = "terminal", .title = "终端与工作区", .panes = &.{"settings.appearance.aids"} },
    } },
    .{ .page = 2, .slug = "ssh", .name = "SSH 与网络", .subs = &.{
        .{ .slug = "connection", .title = "连接", .panes = &.{"settings.ssh.connection"} },
        .{ .slug = "socks", .title = "SOCKS5 转发", .panes = &.{"settings.ssh.socks"} },
        .{ .slug = "reconnect", .title = "断线重连", .panes = &.{"settings.ssh.reconnect"} },
        .{ .slug = "authentication", .title = "双因素认证", .panes = &.{"settings.ssh.authentication"} },
    } },
    .{ .page = 3, .slug = "transfer", .name = "文件传输", .subs = &.{
        .{ .slug = "connection", .title = "连接隔离", .panes = &.{"settings.transfer.connection"} },
        .{ .slug = "engine", .title = "SFTP 引擎", .panes = &.{"settings.transfer.engine"} },
        .{ .slug = "defaults", .title = "默认行为", .panes = &.{"settings.transfer.defaults"} },
    } },
    .{ .page = 4, .slug = "ai", .name = "AI 辅助", .subs = &.{
        .{ .slug = "providers", .title = "服务提供方", .panes = &.{"settings.ai.providers"} },
        .{ .slug = "behavior", .title = "行为与权限", .panes = &.{ "settings.ai.permissions", "settings.ai.execution", "settings.ai.conversation", "settings.ai.children", "settings.ai.context", "settings.ai.attachments", "settings.ai.behavior" } },
        .{ .slug = "extensions", .title = "技能与 MCP", .panes = &.{"settings.ai.extensions"} },
    } },
    .{ .page = 6, .slug = "notifications", .name = "通知", .subs = &.{
        .{ .slug = "events", .title = "事件提醒", .panes = &.{"settings.notifications.events"} },
        .{ .slug = "attention", .title = "注意标记与勿扰", .panes = &.{"settings.notifications.attention"} },
    } },
    .{ .page = 7, .slug = "data", .name = "数据与日志", .subs = &.{
        .{ .slug = "location", .title = "位置与凭据", .panes = &.{"settings.data.location"} },
        .{ .slug = "history", .title = "会话记录", .panes = &.{"settings.data.history"} },
        .{ .slug = "actions", .title = "导出与清理", .panes = &.{"settings.data.actions"} },
    } },
};

const Direct = struct { page: u8, name: []const u8, panes: []const []const u8 };
const direct_categories = [_]Direct{
    .{ .page = 1, .name = "快捷键", .panes = &.{ "settings.keys.tabs", "settings.keys.terminal" } },
    .{ .page = 5, .name = "协议插件", .panes = &.{"settings.plugins"} },
    .{ .page = 8, .name = "关于与更新", .panes = &.{ "settings.updates.version", "settings.updates.preferences" } },
};

fn rowId(buffer: []u8, category: Category, sub: Sub, suffix: []const u8) ![]const u8 {
    return std.fmt.bufPrint(buffer, "settings.overview.{s}.{s}{s}", .{ category.slug, sub.slug, suffix });
}

// -- tests ---------------------------------------------------------------------

fn case1() !void {
    var w: Window = undefined;
    try w.init();
    defer w.deinit();
    for (overview_categories) |category| {
        errdefer std.debug.print("settings window category: {s}\n", .{category.slug});
        try w.openCategory(category.page);
        try std.testing.expect(w.shown("settings.overview"));
        try expectTitle(&w, category.name);
        for (category.subs) |sub| {
            var id: [96]u8 = undefined;
            try std.testing.expect(w.shown(try rowId(&id, category, sub, "")));
            var summary: [256]u8 = undefined;
            try std.testing.expect((try w.text(try rowId(&id, category, sub, ".summary"), &summary)).len > 0);
        }
        // A clean overview edits nothing: no Save Bar.
        try std.testing.expect(!w.shown("settings.footer"));
        for (category.subs) |sub| {
            errdefer std.debug.print("settings window subpage: {s}.{s}\n", .{ category.slug, sub.slug });
            var id: [96]u8 = undefined;
            try w.click(try rowId(&id, category, sub, ""));
            try expectTitle(&w, sub.title);
            try std.testing.expect(!w.shown("settings.overview"));
            for (sub.panes) |pane| try std.testing.expect(w.shown(pane));
            for (category.subs) |other| {
                if (std.mem.eql(u8, other.slug, sub.slug)) continue;
                for (other.panes) |pane| try std.testing.expect(!w.shown(pane));
            }
            // H-save：干净的子页面没有 Save Bar。
            try std.testing.expect(!w.shown("settings.footer"));
            try std.testing.expect(!try w.disabled("settings.history.back"));
            try w.click("settings.history.back");
            try std.testing.expect(w.shown("settings.overview"));
            try expectTitle(&w, category.name);
        }
    }
    try std.testing.expect(!w.controller.model.dirty);
}

fn case2() !void {
    var w: Window = undefined;
    try w.init();
    defer w.deinit();
    for (direct_categories) |category| {
        errdefer std.debug.print("settings window category: {s}\n", .{category.name});
        try w.openCategory(category.page);
        try expectTitle(&w, category.name);
        try std.testing.expect(!w.shown("settings.overview"));
        for (category.panes) |pane| try std.testing.expect(w.shown(pane));
        try std.testing.expect(!w.shown("settings.footer"));
    }
}

fn case3() !void {
    var w: Window = undefined;
    try w.init();
    defer w.deinit();
    // A freshly opened window has nowhere to go.
    try std.testing.expect(try w.disabled("settings.history.back"));
    try std.testing.expect(try w.disabled("settings.history.forward"));

    try w.openCategory(2);
    try std.testing.expect(!try w.disabled("settings.history.back"));
    try std.testing.expect(try w.disabled("settings.history.forward"));
    try w.click("settings.overview.ssh.reconnect");
    try expectTitle(&w, "断线重连");

    // Back to the overview, Forward to the same subpage, and back again.
    try w.click("settings.history.back");
    try expectTitle(&w, "SSH 与网络");
    try std.testing.expect(w.shown("settings.overview"));
    try std.testing.expect(!try w.disabled("settings.history.forward"));
    try w.click("settings.history.forward");
    try expectTitle(&w, "断线重连");
    try std.testing.expect(w.shown("settings.ssh.reconnect"));
    try std.testing.expect(try w.disabled("settings.history.forward"));
    try w.click("settings.history.back");
    try expectTitle(&w, "SSH 与网络");

    // A new step truncates the forward history.
    try w.openCategory(3);
    try expectTitle(&w, "文件传输");
    try std.testing.expect(try w.disabled("settings.history.forward"));
    // Back after a category switch returns to the previous category.
    try w.click("settings.history.back");
    try expectTitle(&w, "SSH 与网络");
    try w.click("settings.history.back");
    try expectTitle(&w, "外观与主题");
    try std.testing.expect(try w.disabled("settings.history.back"));
    try w.click("settings.history.forward");
    try expectTitle(&w, "SSH 与网络");
}

fn case4() !void {
    var w: Window = undefined;
    try w.init();
    defer w.deinit();
    try w.openCategory(2);
    try w.click("settings.overview.ssh.socks");
    try expectTitle(&w, "SOCKS5 转发");

    // Results ignore the drill-down: they span every category.
    try w.search("重连");
    try expectTitle(&w, "搜索结果");
    try std.testing.expect(!w.shown("settings.overview"));
    try std.testing.expect(w.shown("settings.field.reconnect_max"));
    try std.testing.expect(w.shown("settings.field.reconnect"));
    try std.testing.expect(!w.shown("settings.field.socks_port"));
    try std.testing.expect(!w.shown("settings.field.transfer_done"));
    try std.testing.expect(!try w.disabled("settings.history.back"));
    try std.testing.expect(try w.disabled("settings.history.forward"));

    try w.search("keepalive");
    try expectTitle(&w, "搜索结果");
    try std.testing.expect(w.shown("settings.field.keepalive_sec"));
    try std.testing.expect(!w.shown("settings.field.reconnect_max"));

    // Back only leaves the results, for the page the search started from.
    try w.click("settings.history.back");
    try expectTitle(&w, "SOCKS5 转发");
    try std.testing.expect(w.shown("settings.ssh.socks"));
    try std.testing.expect(!w.shown("settings.ssh.connection"));
    try std.testing.expectEqualStrings("", w.controller.search_query);
    try w.click("settings.history.back");
    try expectTitle(&w, "SSH 与网络");

    // Nothing matches: the results say so; clearing returns to the page.
    try w.search("unmatched-setting-zzz");
    try expectTitle(&w, "搜索结果");
    try std.testing.expect(!w.shown("settings.field.keepalive_sec"));
    var buffer: [512]u8 = undefined;
    try std.testing.expect(std.mem.indexOf(u8, try w.text("settings.viewport", &buffer), "没有匹配的设置") != null);
    try w.search("");
    try expectTitle(&w, "SSH 与网络");
    try std.testing.expect(w.shown("settings.overview"));
}

fn case5() !void {
    var w: Window = undefined;
    try w.init();
    defer w.deinit();
    var buffer: [256]u8 = undefined;
    try w.openCategory(2);
    try std.testing.expect(std.mem.indexOf(u8, try w.text("settings.overview.ssh.connection.summary", &buffer), "保活 30 秒") != null);
    try w.click("settings.overview.ssh.connection");
    // H-save：干净时没有 Save Bar、没有“所有更改已保存”。
    try std.testing.expect(!w.shown("settings.footer"));

    try w.typeInto("settings.field.keepalive_sec", "45");
    try std.testing.expectEqual(@as(u16, 45), w.controller.model.value.ssh.keepalive_sec);
    try std.testing.expect(w.shown("settings.footer"));
    try std.testing.expectEqualStrings("未保存", try w.text("settings.footer.state", &buffer));
    try std.testing.expect(!try w.disabled("settings.save"));

    // H-save：带着本页改动离开先确认；“保存”提交后才回到概览，概览干净、摘要是新值。
    try w.click("settings.history.back");
    try std.testing.expectEqual(m.Prompt.leave, w.vm.promptKind());
    try std.testing.expect(w.shown("settings.footer"));
    w.vm.dispatch(m.Intent.decideWith(.save));
    try w.settle();
    try std.testing.expect(!w.controller.model.dirty);
    try std.testing.expect(w.shown("settings.overview"));
    try std.testing.expect(!w.shown("settings.footer"));
    try std.testing.expect(std.mem.indexOf(u8, try w.text("settings.overview.ssh.connection.summary", &buffer), "保活 45 秒") != null);
    var saved = try RuntimeConfig.loadOrDefault(std.testing.io, w.tmp.dir, std.testing.allocator, "config.toml");
    defer saved.deinit();
    try std.testing.expectEqual(@as(u16, 45), saved.value.ssh.keepalive_sec);
}

fn case6() !void {
    var w: Window = undefined;
    try w.init();
    defer w.deinit();
    var buffer: [256]u8 = undefined;
    try w.openCategory(2);
    try w.click("settings.overview.ssh.connection");
    try w.typeInto("settings.field.keepalive_sec", "47");
    try std.testing.expectEqualStrings("未保存", try w.text("settings.footer.state", &buffer));
    try w.click("settings.revert");
    try std.testing.expect(!w.controller.model.dirty);
    try std.testing.expectEqual(@as(u16, 30), w.controller.model.value.ssh.keepalive_sec);
    try std.testing.expect(!w.shown("settings.footer"));
    try w.click("settings.history.back");
    try std.testing.expect(!w.shown("settings.footer"));
    try std.testing.expect(std.mem.indexOf(u8, try w.text("settings.overview.ssh.connection.summary", &buffer), "保活 30 秒") != null);
}

fn case7() !void {
    var w: Window = undefined;
    try w.init();
    defer w.deinit();
    try w.openCategory(2);
    // The assistant's "configure provider": AI 辅助 › 服务提供方.
    try w.deepLink(4, 0);
    try expectTitle(&w, "服务提供方");
    try std.testing.expect(w.shown("settings.ai.providers"));
    try std.testing.expect(!w.shown("settings.ai.permissions"));
    try std.testing.expect(!w.shown("settings.overview"));
    try w.click("settings.history.back");
    try expectTitle(&w, "SSH 与网络");
    try w.click("settings.history.forward");
    try expectTitle(&w, "服务提供方");
}

/// Page-intro help (Glass Icon Button `L5zOX`): a keyboard-reachable icon button whose tooltip
/// shows the category's description after its open delay (the search's own text while
/// searching). Returns the frames (16ms each) the tooltip took to open, per hover.
fn case8() ![2]usize {
    var w: Window = undefined;
    try w.init();
    defer w.deinit();
    try w.openCategory(2);
    const page = try expectHelp(&w, m.catalog.categories[2].description);
    try w.search("keepalive");
    const searching = try expectHelp(&w, "在全部设置分类中查找。");
    return .{ page, searching };
}

fn expectHelp(w: *Window, expected: []const u8) !usize {
    var buffer: [256]u8 = undefined;
    const help = try w.expectShown("settings.help");
    // 原生工具栏按钮 `W.GlassToolbarButton`（S-17），与 macOS 原生工具栏一样不进 Tab 顺序，提示只由悬停打开。
    try std.testing.expectEqualStrings("分类帮助", help.behavior.interaction.a11y.?.label.?);
    // The id is on the button (not the Tooltip wrapper), inside the page intro; the button sits in a
    // native `W.GlassToolbarGroup` capsule inside the Tooltip trigger (feedback 1).
    try std.testing.expect(help.isDescendantOf(try w.expectShown("settings.page.intro")));
    try std.testing.expect(help.behavior.interaction.a11y.?.role == .button);
    try std.testing.expect(!helpOpen(w));
    // 提示的“暖启动”按墙钟算（上一个提示关闭后很快再悬停就不等延迟）：先清掉，量的是冷启动延迟。
    w.env.cx.tooltip_state.last_close = null;
    const rect = help.globalRect();
    w.env.cx.handleMouseMove(rect.x + rect.w / 2, rect.y + rect.h / 2);
    var frames: usize = 0;
    while (!helpOpen(w)) : (frames += 1) {
        if (frames == 120) return error.TestHelpTooltipNeverOpened;
        w.env.frame();
    }
    try std.testing.expectEqualStrings(expected, try w.text("settings.help.content", &buffer));
    w.env.cx.handleMouseMove(1, 1);
    w.env.cx.handlePointerLeave();
    w.env.frames(40);
    try std.testing.expect(!helpOpen(w));
    return frames;
}

// -- control paint (removed in H-save) ----------------------------------------
//
// 这里原来逐状态比较两种实现里 Save Bar“保存更改”的底色 / 渐变 / 墨色，要求 `.yix` 与旧外壳逐值相同。
// H-save（人工验收反馈 4）把 `.yix` 的保存按钮改成原生 `W.Button` primary 的默认外观（删掉 `save_fill` 渐变覆盖），
// 两者有意不同；`.yix` 一侧由 `settings_window_yix_tests` 的“native glass and buttons”用例对照同参数的原生按钮断言。

// -- the bodies ------------------------------------------------------------------
// 3f 之前每个用例对旧外壳与 `.yix` 各跑一遍；旧外壳已删除，只剩 `.yix`。

test "settings window (yix) overview rows drill into subpages that show only their own panes" {
    try case1();
}
test "settings window (yix) direct categories render their panes without an overview" {
    try case2();
}
test "settings window (yix) back and forward follow subpage and category history" {
    try case3();
}
test "settings window (yix) search shows results across categories and Back restores the page" {
    try case4();
}
test "settings window (yix) subpage edit marks the Save Bar and overview summary until save" {
    try case5();
}
test "settings window (yix) revert discards the draft and restores clean overview summaries" {
    try case6();
}
test "settings window (yix) deep link lands on a subpage and Back returns to the previous page" {
    try case7();
}

test "settings window page-intro help shows the category description after its open delay (page and search)" {
    const frames = try case8();
    // 冷启动要等提示的打开延迟（不是立即出现）；分类页与搜索结果页是同一个提示，延迟相同。
    try std.testing.expect(frames[0] > 0);
    try std.testing.expectEqual(frames[0], frames[1]);
}

/// The help tooltip is on screen: shown and not faded out (it fades before it unmounts).
fn helpOpen(w: *Window) bool {
    const node = w.shownNode("settings.help.content") orelse return false;
    var current: ?*ui.Node = node;
    while (current) |item| : (current = item.parent) if (item.getOpacity() < 0.01) return false;
    return true;
}
