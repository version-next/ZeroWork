//! `.yix` 设置窗口（P3 3d）的组件测试：内容页纪元、外壳组件。挂载方式与 SettingsHost 相同：真 `ViewModel` + Ports 替身。
const std = @import("std");
const ui = @import("ui");
const kit = @import("../../../shared/testing/ui_kit.zig");
const app_theme = @import("../../../shared/ui/theme/app_theme.zig");
/// 面板卡片的底色（原 `settings_styles.paneSurface`：窗口背后没有壁纸，角色色不透明）。
fn paneSurface() ui.Color {
    return app_theme.current().surface_2.withAlpha(255);
}
/// 次要墨色（原 `settings_styles.secondaryInk`：随材质透明度在 fg_2 与 fg_1 之间插值）。
fn secondaryInk() ui.Color {
    const c = app_theme.current();
    return ui.Color.lerp(c.fg_2, c.fg_1, @min(1, app_theme.materialParameters().transparency / 50));
}
const shell = @import("../view/settings_shell.zig");
const Controller = @import("../model/settings_controller.zig").Controller;
const RuntimeConfig = @import("../../../config/runtime_config.zig").RuntimeConfig;
const m = @import("../model/view_model.zig");
const frame_mod = @import("../view/window_frame.zig");
const settings_window = @import("../view/_settings_window.yix.zig");

const Fixture = struct {
    env: kit.Headless,
    tmp: std.testing.TmpDir,
    runtime: RuntimeConfig,
    controller: Controller,
    vm: m.ViewModel,
    frame: frame_mod.Frame,
    effects: std.ArrayList(std.meta.Tag(m.Effect)) = .empty,
    status_line: []const u8 = "",
    /// `Gate.window_keys`（宿主：没在录制快捷键、确认弹窗没打开）。
    window_keys: bool = true,
    root: *ui.Node = undefined,

    fn init(self: *Fixture, theme: app_theme.Name) !void {
        const a = std.testing.allocator;
        self.* = .{ .env = try kit.headless(a, .{ .width = shell.window.width, .height = shell.window.height, .theme = theme, .root_style = .{ .width = .fill(), .height = .fill(), .direction = .column } }), .tmp = std.testing.tmpDir(.{}), .runtime = undefined, .controller = undefined, .vm = undefined, .frame = undefined };
        self.runtime = try RuntimeConfig.loadOrDefault(std.testing.io, self.tmp.dir, a, "config.toml");
        self.controller = try Controller.init(a, self.runtime.value);
        self.controller.drill_down = true;
        self.controller.folded_sections = 0;
        self.controller.history.reset(self.controller.location());
        self.vm = m.ViewModel.init(&self.controller, .{ .context = self, .run = run, .allow = allow, .status = hostStatus });
        self.frame = .{ .vm = &self.vm };
        try self.vm.attach(self.env.scope);
        self.root = try ui.view.render(self.env.scope, self.env.cx, settings_window.SettingsWindow(.{ .vm = &self.vm, .frame = &self.frame }));
        try self.env.mount(self.root);
        // 与 zenit 运行时相同：窗口没有焦点时按键落到应用挂载的根（`Cx.content_root`）。
        self.env.cx.content_root = self.root;
        self.env.frames(2);
    }
    fn deinit(self: *Fixture) void {
        self.env.deinit();
        self.effects.deinit(std.testing.allocator);
        self.controller.deinit();
        self.runtime.deinit();
        self.tmp.cleanup();
    }
    fn run(raw: *anyopaque, effect: m.Effect) void {
        const self: *Fixture = @ptrCast(@alignCast(raw));
        self.effects.append(std.testing.allocator, effect) catch {};
    }
    fn hostStatus(raw: *anyopaque) m.HostStatus {
        const self: *Fixture = @ptrCast(@alignCast(raw));
        return .{ .status_line = self.status_line };
    }
    fn allow(raw: *anyopaque, gate: m.Gate) bool {
        const self: *Fixture = @ptrCast(@alignCast(raw));
        if (gate == .window_keys) return self.window_keys;
        return true;
    }
    /// SettingsHost: navigate, then a new content epoch.
    fn go(self: *Fixture, intent: m.Intent) void {
        self.vm.dispatch(intent);
        self.vm.remountContent();
        self.env.frames(2);
    }
    fn expect(self: *Fixture, id: []const u8) !*ui.Node {
        return kit.expectByTestId(self.root, id);
    }
    fn emitted(self: *Fixture, tag: std.meta.Tag(m.Effect)) bool {
        for (self.effects.items) |item| if (item == tag) return true;
        return false;
    }
};

fn findBackground(node: *ui.Node, color: ui.Color) ?*ui.Node {
    if (ui.Color.eql(node.getBackground(), color)) return node;
    for (node.children.items) |child| if (findBackground(child, color)) |found| return found;
    return null;
}

test "settings yix window: every category and subpage mounts a content page; epoch remounts keep the panes (V-5)" {
    // 3f：旧正文（`LegacyBody`）与它在 `Frame` 里的句柄已删除；这里守住每个位置都挂出内容页、换纪元重挂后面板仍在。
    const catalog = @import("../model/catalog.zig");
    var f: Fixture = undefined;
    try f.init(.light);
    defer f.deinit();
    for (0..catalog.categories.len) |page| {
        for ([_]?u8{ null, 0, 1 }) |sub| {
            f.go(m.Intent.openAt(.{ .page = @intCast(page), .sub = sub }));
            try std.testing.expect(frame_mod.Page.of(&f.frame) != null);
        }
    }
    f.go(m.Intent.openAt(.{ .page = 4, .sub = 1 }));
    _ = try f.expect("settings.ai.permissions");
    for (0..5) |_| {
        f.vm.remountContent();
        f.env.frame();
    }
    f.env.frames(2);
    _ = try f.expect("settings.ai.permissions");
}

test "settings yix window: theme publication repaints the shell and the pane cards (V-5)" {
    var f: Fixture = undefined;
    try f.init(.light);
    defer f.deinit();
    f.go(m.Intent.openAt(.{ .page = 2, .sub = 0 }));
    const nav = try f.expect("settings.navigation");
    const light_card = paneSurface();
    _ = findBackground(try f.expect("settings.ssh.connection"), light_card) orelse return error.TestPaneCardNotFound;
    try std.testing.expect(isGlassBox(nav));
    const light_title = app_theme.current().fg_1;
    try std.testing.expect(ui.Color.eql(light_title, (try f.expect("settings.header.title")).getText().?.color));
    app_theme.select(.dark);
    f.env.publishTheme();
    f.env.frames(2);
    try std.testing.expect(!ui.Color.eql(light_card, paneSurface()));
    // Settings Nav 是原生 `W.GlassBox`（反馈 1）：主题发布后仍是同一个玻璃容器，材质由组件按背景逐帧适配（无下游颜色）。
    try std.testing.expect(isGlassBox(nav));
    // The window title (`settings.header.title`, `S.window_title`: fg-primary) follows the
    // publication by itself; no host writes its colour (S-9 removed AppNavHost's).
    const window_title = try f.expect("settings.header.title");
    try std.testing.expect(ui.Color.eql(app_theme.current().fg_1, window_title.getText().?.color));
    try std.testing.expect(!ui.Color.eql(light_title, window_title.getText().?.color));
    // SettingsHost answers a publication with a rebuild; the pane cards (`.yss` tokens) carry the dark colours.
    f.vm.remountContent();
    f.env.frames(2);
    _ = findBackground(try f.expect("settings.ssh.connection"), paneSurface()) orelse return error.TestPaneCardNotRepainted;
    try std.testing.expect(findBackground(try f.expect("settings.ssh.connection"), light_card) == null);
}

test "settings yix window shell keeps the Island B v3 geometry" {
    var f: Fixture = undefined;
    try f.init(.light);
    defer f.deinit();
    const panel = (try f.expect("settings.panel")).globalRect();
    try std.testing.expectEqual(@as(f32, 960), panel.w);
    try std.testing.expectEqual(@as(f32, 780), panel.h);
    const nav = (try f.expect("settings.navigation")).globalRect();
    try std.testing.expectEqual(@as(f32, 8), nav.x);
    try std.testing.expectEqual(@as(f32, 216), nav.w);
    try std.testing.expectEqual(@as(f32, 780 - 16), nav.h);
    const lights = (try f.expect("settings.header.traffic_lights")).globalRect();
    try std.testing.expectEqual(shell.window.traffic_light_x - shell.window.traffic_light_diameter / 2, lights.x);
    try std.testing.expectEqual(shell.window.traffic_light_y, lights.y + lights.h / 2);
    try std.testing.expectEqual(@as(f32, 8 + 10 + 28 + 12), (try f.expect("settings.search")).globalRect().y);
    try std.testing.expectEqual(@as(f32, 200), (try f.expect("settings.search.slot")).globalRect().w);
    // Nav rows: 28 high, 1pt apart, directly in the nav list.
    const first = (try f.expect("settings.nav.appearance")).globalRect();
    const second = (try f.expect("settings.nav.keys")).globalRect();
    try std.testing.expectEqual(@as(f32, 28), first.h);
    try std.testing.expectEqual(first.y + 29, second.y);
    const note = (try f.expect("settings.navigation.note")).globalRect();
    try std.testing.expectEqual(nav.y + nav.h - 10, note.y + note.h);
    const island = (try f.expect("settings.island")).globalRect();
    try std.testing.expectEqual(@as(f32, 8 + 216), island.x);
    try std.testing.expectEqual(@as(f32, 960 - 8 - 216), island.w);
    const content = (try f.expect("settings.content")).globalRect();
    try std.testing.expectEqual(island.x, content.x);
    try std.testing.expectEqual(island.h, content.h);
}

test "settings yix window stays inside its 960x780 window after a material publication (bugfix-2 C)" {
    // Saving or previewing a material change republishes the widget tokens into the preferences window.
    // The template root used to keep flex's automatic minimum height, so the re-measured content
    // (the long 外观与主题 › 主题 page) pushed it to 1082.6 pt: the Save Bar and the viewport bottom left the window.
    const saved = app_theme.materialParameters();
    defer _ = app_theme.setMaterialParameters(saved.transparency, saved.blur);
    var f: Fixture = undefined;
    try f.init(.dark);
    defer f.deinit();
    f.go(m.Intent.openAt(.{ .page = 0, .sub = 0 }));
    _ = try f.expect("settings.appearance.materials");
    for ([_]f32{ 42, 0, 100 }) |transparency| {
        _ = app_theme.setMaterialParameters(transparency, 12);
        f.env.publishTheme();
        f.env.frames(3);
        for ([_][]const u8{ "settings.window", "settings.panel" }) |id| {
            const rect = (try f.expect(id)).globalRect();
            try std.testing.expectEqual(@as(f32, 780), rect.h);
        }
        const viewport = (try f.expect("settings.viewport")).globalRect();
        try std.testing.expect(viewport.y + viewport.h <= 780 + 0.5);
        const nav = (try f.expect("settings.navigation")).globalRect();
        try std.testing.expectEqual(@as(f32, 780 - 16), nav.h);
    }
}

test "settings yix nav rows dispatch and follow the selection" {
    var f: Fixture = undefined;
    try f.init(.light);
    defer f.deinit();
    const keys = try f.expect("settings.nav.keys");
    const rect = keys.globalRect();
    f.env.cx.handleClick(rect.x + rect.w / 2, rect.y + rect.h / 2);
    f.env.frame();
    try std.testing.expectEqual(@as(usize, 1), f.controller.model.page_index);
    try std.testing.expect(f.emitted(.navigated));
    f.vm.remountContent();
    f.env.frames(2);
    // The selected row is repainted with the accent fill.
    try std.testing.expect(ui.Color.eql(app_theme.current().action_accent, (try f.expect("settings.nav.keys")).getBackground()));
    try std.testing.expect(!ui.Color.eql(app_theme.current().action_accent, (try f.expect("settings.nav.appearance")).getBackground()));
}

test "settings yix page intro follows the history and the title" {
    var f: Fixture = undefined;
    try f.init(.light);
    defer f.deinit();
    const back = try f.expect("settings.history.back");
    try std.testing.expect(back.behavior.interaction.a11y.?.disabled);
    f.go(m.Intent.selectCategory(2));
    try std.testing.expect(!(try f.expect("settings.history.back")).behavior.interaction.a11y.?.disabled);
    try std.testing.expect((try f.expect("settings.history.forward")).behavior.interaction.a11y.?.disabled);
    try std.testing.expectEqualStrings("SSH 与网络", (try f.expect("settings.page.title")).getText().?.content);
    const back_now = (try f.expect("settings.history.back")).globalRect();
    f.env.cx.handleClick(back_now.x + back_now.w / 2, back_now.y + back_now.h / 2);
    f.env.frame();
    try std.testing.expectEqual(@as(usize, 0), f.controller.model.page_index);
    // The title follows the projection before the host re-mounts the body.
    try std.testing.expectEqualStrings("外观与主题", (try f.expect("settings.page.title")).getText().?.content);
}


/// 原生 `W.GlassBox` 的根：挂着玻璃的逐帧状态，第一个子节点是带 `glass` 参数的玻璃面（组件根同时是 Yix 组件根时，
/// `component_name` 写的是外层组件名，所以按结构认）。
fn isGlassBox(node: *ui.Node) bool {
    if (node.meta.per_frame.hooks.slots.anim_state == null or node.children.items.len == 0) return false;
    const ext = node.children.items[0].style.ext orelse return false;
    return ext.glass != null;
}
fn componentAncestor(node: *ui.Node, name: []const u8) ?*ui.Node {
    var cursor: ?*ui.Node = node;
    while (cursor) |current| : (cursor = current.parent) {
        if (current.meta.ownership.meta.component_name) |own| if (std.mem.eql(u8, own, name)) return current;
    }
    return null;
}
fn findComponent(node: *ui.Node, name: []const u8) ?*ui.Node {
    if (node.meta.ownership.meta.component_name) |own| if (std.mem.eql(u8, own, name)) return node;
    for (node.children.items) |child| if (findComponent(child, name)) |found| return found;
    return null;
}
const Look = struct { background: ui.Color, w: f32, h: f32, opacity: f32 };
fn look(node: *ui.Node) Look {
    const r = node.globalRect();
    return .{ .background = node.getBackground(), .w = r.w, .h = r.h, .opacity = node.getOpacity() };
}

// 人工验收反馈 1 / 11：Settings Nav 浮层是 zenit 原生 liquid glass（`W.GlassBox`）；页头的浮动按钮是原生 macOS 26
// 工具栏按钮组（`W.GlassToolbarGroup` 胶囊 + `W.GlassToolbarButton`，S-17 已收回），禁用态用按钮自己的（淡墨、不可点），
// 与同参数的参照按钮组的墨色逐项相同；帮助的提示框是原生 `W.Tooltip` 的默认外观。
test "settings yix floating chrome is native liquid glass with default buttons and tooltip (feedback 1, 11)" {
    var f: Fixture = undefined;
    try f.init(.light);
    defer f.deinit();
    f.go(m.Intent.selectCategory(2));
    f.env.frames(2);
    const nav = try f.expect("settings.navigation");
    try std.testing.expect(isGlassBox(nav));
    const history = try f.expect("settings.history");
    try std.testing.expect(isGlassBox(history));
    try std.testing.expectEqualStrings("GlassToolbarGroup", history.meta.ownership.meta.component_name.?);
    const back = try f.expect("settings.history.back");
    const forward = try f.expect("settings.history.forward");
    const help = try f.expect(m.ids.help);
    for ([_]*ui.Node{ back, forward, help }) |button| try std.testing.expectEqualStrings("GlassToolbarButton", button.meta.ownership.meta.component_name.?);
    for ([_]*ui.Node{ back, forward }) |button| try std.testing.expect(componentAncestor(button, "GlassToolbarGroup") == history);
    const help_glass = componentAncestor(help, "GlassToolbarGroup") orelse return error.TestHelpNotInGlass;
    try std.testing.expect(help_glass != history and isGlassBox(help_glass));
    try std.testing.expect(componentAncestor(help_glass, "Tooltip") != null);
    // 胶囊高 36（工具栏 `.buttons` 组），按钮 38 宽；页头 48 高、上下各 6。
    try std.testing.expectEqual(@as(f32, 36), history.globalRect().h);
    try std.testing.expectEqual(ui.widgets.glass_toolbar.button_width, back.globalRect().w);
    // 后退可用、前进不可用：与参照按钮组（同参数、无覆盖）的墨色逐项相同。
    try std.testing.expect(!back.behavior.interaction.a11y.?.disabled);
    try std.testing.expect(forward.behavior.interaction.a11y.?.disabled);
    try std.testing.expect(back.children.items[1].getIcon().?.tint.a != forward.children.items[1].getIcon().?.tint.a);
    const slot = try ui.box(f.env.cx, .{ .direction = .row, .position = .absolute, .inset = .{ .left = .{ .px = 400 }, .top = .{ .px = 700 } } }, .{});
    var ref_enabled: *ui.Node = undefined;
    var ref_disabled: *ui.Node = undefined;
    try ui.view.mount(f.env.scope, f.env.cx, slot, ui.view.capture(&ref_enabled, ui.widgets.GlassToolbarButton(.{ .icon = ui.icons.chevron_left, .label = "返回" })));
    try ui.view.mount(f.env.scope, f.env.cx, slot, ui.view.capture(&ref_disabled, ui.widgets.GlassToolbarButton(.{ .icon = ui.icons.chevron_right, .label = "前进", .disabled = true })));
    const tip_ref = try ui.widgets.Tooltip(.{ .text = "参照" }).mount(f.env.scope, f.env.cx);
    try slot.appendChild(f.env.cx.allocator, tip_ref.wrapper);
    try f.env.mount(slot);
    f.env.frames(2);
    try std.testing.expectEqual(ref_disabled.children.items[1].getIcon().?.tint.a, forward.children.items[1].getIcon().?.tint.a);
    try std.testing.expectEqual(ui.widgets.glass_toolbar.light_palette.icon_disabled, forward.children.items[1].getIcon().?.tint.a);
    try std.testing.expect(ref_enabled.children.items[1].getIcon().?.tint.a != ref_disabled.children.items[1].getIcon().?.tint.a);
    // 提示框：原生默认的底色、圆角、内边距（不覆盖提示框外观）。
    f.env.cx.tooltip_state.last_close = null;
    const hr = help.globalRect();
    f.env.cx.handleMouseMove(hr.x + hr.w / 2, hr.y + hr.h / 2);
    var waited: usize = 0;
    const tip = while (waited < 120) : (waited += 1) {
        if (kit.findByTestId(f.env.cx.root.?, m.ids.help_content)) |node| if (node.getOpacity() > 0.99) break node;
        f.env.cx.advanceFrameClock();
        f.env.frame();
    } else return error.TestHelpTooltipNeverOpened;
    f.env.frames(30);
    try std.testing.expect(ui.Color.eql(tip_ref.content.getBackground(), tip.getBackground()));
    try std.testing.expectEqual(tip_ref.content.style.corner_radius(), tip.style.corner_radius());
    try std.testing.expectEqualDeep(tip_ref.content.style.padding, tip.style.padding);
}

// 人工验收反馈 5：内容视口与导航列表是原生 `W.ScrollArea` 的默认回弹（RubberBand 开启）；触控板在顶端继续下拉时
// 内容越界（果冻位移），松手后回到边界、view-model 的存档仍是 0。真实触控板手感 Harness 测不到（未实证）。
test "settings yix viewport and nav list keep the native rubber band and settle back to the edge (feedback 5)" {
    var f: Fixture = undefined;
    try f.init(.light);
    defer f.deinit();
    try f.env.cx.setTestFrameStep(16);
    f.go(m.Intent.openAt(.{ .page = 4, .sub = 1 }));
    settle(&f.env);
    for ([_][]const u8{ m.ids.viewport, m.ids.navigation_scroll }) |id| {
        const node = try f.expect(id);
        const ctx: *ui.widgets.scroll_area.ScrollEventCtx = @ptrCast(@alignCast(node.behavior.events.event_context orelse return error.TestNotScrollArea));
        try std.testing.expect(ctx.state.rubber_band_y_enabled);
    }
    const viewport = try f.expect(m.ids.viewport);
    const ctx: *ui.widgets.scroll_area.ScrollEventCtx = @ptrCast(@alignCast(viewport.behavior.events.event_context.?));
    const r = viewport.globalRect();
    const at = .{ r.x + r.w / 2, r.y + r.h / 2 };
    f.env.cx.handleScroll(.{ .dx = 0, .dy = 0, .x = at[0], .y = at[1], .phase = .began });
    for (0..6) |_| {
        f.env.cx.handleScroll(.{ .dx = 0, .dy = 20, .x = at[0], .y = at[1], .phase = .changed });
        f.env.cx.advanceFrameClock();
        f.env.frame();
    }
    // 越过顶端：果冻位移（bonus）不为 0，内容被拉离边界。
    try std.testing.expect(ctx.state.bonus_y != 0);
    try std.testing.expect(try viewportOffset(&f) < 0);
    f.env.cx.handleScroll(.{ .dx = 0, .dy = 0, .x = at[0], .y = at[1], .phase = .ended });
    for (0..120) |_| {
        f.env.cx.advanceFrameClock();
        f.env.frame();
    }
    try std.testing.expectEqual(@as(f32, 0), ctx.state.bonus_y);
    try std.testing.expectApproxEqAbs(@as(f32, 0), try viewportOffset(&f), 0.5);
    try std.testing.expectEqual(@as(f32, 0), f.vm.scrollOffset(m.ScrollSlot.normal(4)));
}

// 人工验收反馈 3 / 第 2 轮（照 znote 画板详情页 chrome 的 header）：视口占满整列、从列顶开始，页头浮在上面（没有洗白渐变）；
// 视口的原生 scroll edge 带高 76、顶部 22.8 满糊后渐出（hold + fade_width）、模糊半径 180、满强度 1，静止时看不见。
// 页头整条是窗口拖动区（window chrome 的 `windowRegion={.drag}`）并拦截命中：空白处拖动窗口、滚到页头下的正文点不到，胶囊按钮仍是控件（S-10）。
test "settings yix page header floats over the viewport like znote's board header (feedback 3, round 2)" {
    var f: Fixture = undefined;
    try f.init(.light);
    defer f.deinit();
    f.go(m.Intent.openAt(.{ .page = 4, .sub = 1 }));
    settle(&f.env);
    const content = try f.expect("settings.content");
    const viewport = try f.expect(m.ids.viewport);
    const intro = try f.expect("settings.page.intro");
    try std.testing.expect(findComponent(content, "TitlebarEdge") == null);
    try std.testing.expect(intro.style.position == .absolute);
    try std.testing.expectEqual(ui.hit.HitBehavior.self_and_children, intro.style.ext.?.hit_behavior.?);
    try std.testing.expectEqual(@TypeOf(intro.behavior.interaction.window_region).drag, intro.behavior.interaction.window_region);
    const c = content.globalRect();
    try std.testing.expectEqual(c.y, viewport.globalRect().y);
    try std.testing.expectEqual(c.h, viewport.globalRect().h);
    try std.testing.expectEqual(c.y, intro.globalRect().y);
    try std.testing.expectEqual(@as(f32, 64), intro.globalRect().h);
    // 页头画在视口之上（同一父节点里的先后顺序）。
    const order = struct {
        fn index(parent: *ui.Node, child: *ui.Node) usize {
            var cursor = child;
            while (cursor.parent) |p| : (cursor = p) if (p == parent) break;
            for (parent.children.items, 0..) |item, i| if (item == cursor) return i;
            return std.math.maxInt(usize);
        }
    };
    try std.testing.expect(order.index(content, viewport) < order.index(content, intro));
    // 标题：上一级 › 标题（13 / 600），下一行分类说明。
    const title_node = try f.expect("settings.page.title");
    try std.testing.expectEqualStrings("行为与权限", title_node.getText().?.content);
    try std.testing.expectEqual(@as(f32, 13), title_node.getText().?.font_size);
    try std.testing.expectEqualStrings("AI 辅助", f.vm.crumb());
    // 页头空白处（标题与帮助之间）：指针落在页头本身（不穿到底下的正文），window chrome 判定为拖动；按钮仍是客户区。
    const title = title_node.globalRect();
    const help_rect = (try f.expect(m.ids.help)).globalRect();
    const back_rect = (try f.expect("settings.history.back")).globalRect();
    const blank_x = (title.x + title.w + help_rect.x) / 2;
    const blank_y = intro.globalRect().y + intro.globalRect().h / 2;
    try std.testing.expect(f.env.cx.hitTest(blank_x, blank_y) == intro);
    const Region = @TypeOf(intro.behavior.interaction.window_region);
    try std.testing.expectEqual(Region.drag, f.env.cx.windowRegionAt(blank_x, blank_y));
    try std.testing.expectEqual(Region.drag, f.env.cx.windowRegionAt(title.x + title.w / 2, title.y + title.h / 2));
    try std.testing.expectEqual(Region.client, f.env.cx.windowRegionAt(back_rect.x + back_rect.w / 2, back_rect.y + back_rect.h / 2));
    try std.testing.expectEqual(Region.client, f.env.cx.windowRegionAt(help_rect.x + help_rect.w / 2, help_rect.y + help_rect.h / 2));
    // 导航浮层顶部的标题带（红绿灯右侧、导航上内边距）也是拖动区；搜索框、导航行、正文是客户区。
    const nav_top = (try f.expect("settings.header")).globalRect();
    const nav_glass = (try f.expect("settings.navigation")).globalRect();
    try std.testing.expectEqual(Region.drag, f.env.cx.windowRegionAt(nav_top.x + nav_top.w - 12, nav_top.y + nav_top.h / 2));
    try std.testing.expectEqual(Region.drag, f.env.cx.windowRegionAt(nav_top.x + nav_top.w - 12, nav_glass.y + 3));
    const search_rect = (try f.expect(m.ids.search)).globalRect();
    try std.testing.expectEqual(Region.client, f.env.cx.windowRegionAt(search_rect.x + search_rect.w / 2, search_rect.y + search_rect.h / 2));
    try std.testing.expectEqual(Region.client, f.env.cx.windowRegionAt(c.x + c.w / 2, c.y + c.h * 0.7));
    // 静止时第一块面板在页头下方。
    const first_pane = try f.expect("settings.ai.permissions");
    try std.testing.expect(first_pane.globalRect().y >= c.y + 64);
    // 视口的原生 scroll edge（`W.ScrollArea scrollEdge`）：贴在视口上缘（= 列顶，页头下面）、不拦截命中，绑定视口自己的滚动状态。
    const band = findComponent(viewport, "ScrollEdgeEffect") orelse return error.TestNoScrollEdge;
    try std.testing.expectEqual(ui.hit.HitBehavior.pass_through, band.style.ext.?.hit_behavior.?);
    try std.testing.expectEqual(viewport.globalRect().y, band.globalRect().y);
    try std.testing.expectEqual(@as(f32, 76), band.globalRect().h);
    try std.testing.expectEqual(viewport.globalRect().w, band.globalRect().w);
    const scroll_ctx: *ui.widgets.scroll_area.ScrollEventCtx = @ptrCast(@alignCast(viewport.behavior.events.event_context orelse return error.TestNotScrollArea));
    const glass: *ui.widgets.glass_box.AdaptiveGlassBoxState = @ptrCast(@alignCast(band.meta.per_frame.hooks.slots.anim_state orelse return error.TestScrollEdgeNotGlass));
    try std.testing.expectEqual(ui.widgets.glass_box.GlassMaterial.blur_only, glass.material);
    try std.testing.expect(glass.scroll_edge.?.scroll == scroll_ctx.state);
    try std.testing.expectEqual(@as(f32, 22.8), glass.scroll_edge.?.hold);
    try std.testing.expectEqual(@as(f32, 53.2), glass.scroll_edge.?.fade_width);
    try std.testing.expectEqual(@as(f32, 1), glass.scroll_edge.?.max_strength);
    // 静止在顶端：看不见；带子不模糊下面的正文（基准模糊级 0，反馈 3 回归）。
    try std.testing.expectEqual(@as(f32, 0), glass.edge_strength);
    try std.testing.expectEqual(@as(f32, 0), glass.surface.style.ext.?.glass.?.blur_level);
    // 内容往上滚到页头下面：满强度的渐进磨砂（三段：满糊 30% → 渐出到清晰）。
    f.vm.dispatch(m.Intent.scrolledTo(160));
    for (0..60) |_| {
        f.env.cx.advanceFrameClock();
        f.env.frame();
    }
    try std.testing.expect(try viewportOffset(&f) > 100);
    try std.testing.expect(glass.edge_strength > 0.9);
    const g = glass.surface.style.ext.?.glass.?;
    try std.testing.expectEqual(@as(f32, 180), g.backdrop_blur);
    try std.testing.expectEqual(@as(u8, 3), g.blur_gradient.stop_count);
    try std.testing.expectApproxEqAbs(@as(f32, 0.3), g.blur_gradient.stops[1].pos, 1e-4);
    // 滚到页头下的正文点不到：页头范围里的指针仍落在页头。
    try std.testing.expect(f.env.cx.hitTest(c.x + 40, c.y + 60) == intro);
}
// H-save（人工验收反馈 4）：Save Bar 只在当前作用域有未保存改动时出现；胶囊是原生 `W.GlassBox`，按钮是原生
// `W.Button`（只用 variant / size，与同参数的参照按钮逐项相同）；“恢复默认…”在正文底部，只在作用域的值与默认值不同时可点。
test "settings yix save bar appears only with unsaved changes and uses native glass and buttons (feedback 4)" {
    var f: Fixture = undefined;
    try f.init(.light);
    defer f.deinit();
    f.go(m.Intent.openAt(.{ .page = 2, .sub = 0 }));
    // 干净：没有 Save Bar，也没有“所有更改已保存”。
    try std.testing.expectEqual(ui.types.Display.none, (try f.expect("settings.footer")).style.display);
    try std.testing.expect(kit.findByTestId(f.root, "settings.footer.state.icon") == null);
    // 默认值的页面：“恢复默认…”在，但不可点。
    const reset = try f.expect(m.ids.reset);
    try std.testing.expect(reset.behavior.interaction.a11y.?.disabled);
    f.vm.dispatch(m.Intent.editValue(.{ .section = "ssh", .key = "keepalive_sec" }, .{ .unsigned = 45 }));
    settle(&f.env);
    const footer = try f.expect("settings.footer");
    try std.testing.expect(footer.style.display != .none);
    const state = try f.expect("settings.footer.state");
    try std.testing.expectEqualStrings("未保存", state.getText().?.content);
    const save = try f.expect("settings.save");
    const revert = try f.expect("settings.revert");
    try std.testing.expect(!save.behavior.interaction.a11y.?.disabled);
    try std.testing.expect(!revert.behavior.interaction.a11y.?.disabled);
    try std.testing.expect(!reset.behavior.interaction.a11y.?.disabled);
    // 胶囊是原生 GlassBox，两个按钮在里面。
    const glass = componentAncestor(save, "GlassBox") orelse return error.TestSaveBarNotGlass;
    try std.testing.expect(isGlassBox(glass) and componentAncestor(revert, "GlassBox") == glass and glass.isDescendantOf(footer));
    // 与没有任何覆盖的参照按钮逐项相同（底色、尺寸、不透明度）。
    const slot = try ui.box(f.env.cx, .{ .direction = .row, .position = .absolute, .inset = .{ .left = .{ .px = 300 }, .top = .{ .px = 700 } } }, .{});
    const save_ref = try ui.widgets.Button(.{ .label = "保存", .a11y_label = "保存更改", .variant = .primary, .size = .sm }).mount(f.env.scope, f.env.cx);
    const revert_ref = try ui.widgets.Button(.{ .label = "撤销", .a11y_label = "撤销更改", .variant = .ghost, .size = .sm }).mount(f.env.scope, f.env.cx);
    const reset_ref = try ui.widgets.Button(.{ .label = "恢复默认…", .a11y_label = "恢复本页默认设置", .variant = .ghost, .size = .sm }).mount(f.env.scope, f.env.cx);
    for ([_]*ui.Node{ save_ref, revert_ref, reset_ref }) |node| try slot.appendChild(f.env.cx.allocator, node);
    try f.env.mount(slot);
    settle(&f.env);
    try std.testing.expectEqualDeep(look(save_ref), look(save));
    try std.testing.expectEqualDeep(look(revert_ref), look(revert));
    try std.testing.expectEqualDeep(look(reset_ref), look(reset));
    try std.testing.expect(ui.Color.eql(labelColor(save_ref), labelColor(save)));
    // 点“保存”发出 Effect.save。
    const rect = save.globalRect();
    f.env.cx.handleClick(rect.x + rect.w / 2, rect.y + rect.h / 2);
    f.env.frame();
    try std.testing.expect(f.emitted(.save));
}
fn labelColor(node: *ui.Node) ui.Color {
    if (node.getText()) |value| return value.color;
    for (node.children.items) |child| {
        const found = labelColor(child);
        if (!ui.Color.eql(found, ui.Color.TRANSPARENT)) return found;
    }
    return ui.Color.TRANSPARENT;
}

// H-save：未保存的确认（切页 / 关窗）与恢复默认确认是原生 `W.Modal` 的默认外观——默认遮罩、默认（不透明）面板底色、
// 默认标题栏；打开时焦点在对话框里（不在左侧搜索框上）；Escape 收起 = “继续编辑”。
test "settings yix confirmations are the native W.Modal default with focus inside (feedback 4, 8)" {
    var f: Fixture = undefined;
    try f.init(.light);
    defer f.deinit();
    // 用例中途失败时先收起对话框再拆窗口（对话框的焦点作用域在拆除时会把焦点还给搜索框）。
    defer {
        f.vm.dismissPrompt();
        f.env.frames(2);
    }
    f.go(m.Intent.openAt(.{ .page = 2, .sub = 0 }));
    // 先让搜索框拿到焦点（人工验收看到的现象：弹窗时搜索框带焦点描边）。
    const search = try f.expect("settings.search");
    const sr = search.globalRect();
    f.env.cx.handleClick(sr.x + sr.w / 2, sr.y + sr.h / 2);
    f.env.frames(2);
    f.vm.dispatch(m.Intent.editValue(.{ .section = "ssh", .key = "keepalive_sec" }, .{ .unsigned = 45 }));
    f.vm.dispatch(m.Intent.openAt(.{ .page = 2, .sub = 1 }));
    settle(&f.env);
    try std.testing.expectEqual(m.Prompt.leave, f.vm.promptKind());
    // 原生 Modal 挂在窗口的浮层根上（不在设置窗口模板的子树里）。
    const body = try kit.expectByTestId(f.env.cx.root.?, m.ids.confirmation);
    // 焦点在对话框里（不再留在左侧搜索框上）。
    const panel = panelOf(body) orelse return error.TestNoModalPanel;
    const focused = f.env.cx.focus_manager.getFocused() orelse return error.TestNothingFocused;
    try std.testing.expect(focused.isDescendantOf(panel) or focused == panel);
    try std.testing.expect(!focused.isDescendantOf(search) and focused != search);
    // 参照：同参数、无覆盖的原生 Modal。
    const ref_open = try f.env.scope.createSignal(bool, true);
    const ref = try ui.widgets.Modal(.{ .open = ref_open, .title = "参照", .width = @as(f32, 440), .close_on_overlay = false }).mount(f.env.scope, f.env.cx);
    if (!ref.portaled) try f.env.root.appendChild(f.env.cx.allocator, ref.overlay);
    settle(&f.env);
    try std.testing.expect(ui.Color.eql(ref.dialog.getBackground(), panel.getBackground()));
    try std.testing.expect(panel.getBackground().a == 255);
    try std.testing.expectEqual(ref.dialog.style.corner_radius(), panel.style.corner_radius());
    try std.testing.expect(ui.Color.eql(ref.overlay.getBackground(), panel.parent.?.getBackground()));
    ref_open.set(false);
    settle(&f.env);
    // Escape = 继续编辑：收起，留在原处，草稿还在。
    f.env.cx.handleKeyDown(.escape, .{});
    settle(&f.env);
    try std.testing.expect(!f.vm.promptOpen());
    try std.testing.expectEqual(m.Location{ .page = 2, .sub = 0 }, f.vm.location());
    try std.testing.expect(f.vm.isDirty());
    // 常驻挂载（G36 / G37 上游已补）：收起后对话框还在树上（原生退出动画），关着的对话框不在 Tab 顺序里；
    // 再次打开时焦点又落到“继续编辑”（声明的 autoFocus，每次打开都聚焦）。
    try std.testing.expect(kit.findByTestId(f.env.cx.root.?, m.ids.confirmation) == body);
    // 退出动画期间正文不跳变：仍是“未保存的设置”的说明与按钮。
    try std.testing.expect((try kit.expectByTestId(f.env.cx.root.?, m.ids.confirmation_discard)).style.display != .none);
    try std.testing.expect(std.mem.indexOf(u8, f.vm.promptMessage(), "尚未保存") != null);
    try std.testing.expectEqualStrings("未保存的设置", f.vm.promptTitle());
    f.env.cx.setFocus(null);
    f.env.frame();
    for (0..6) |_| {
        f.env.cx.handleKeyDown(.tab, .{});
        f.env.frame();
        const now = f.env.cx.focus_manager.getFocused() orelse continue;
        try std.testing.expect(!now.isDescendantOf(panel) and now != panel);
    }
    f.vm.dispatch(m.Intent.openAt(.{ .page = 2, .sub = 1 }));
    settle(&f.env);
    try std.testing.expectEqual(m.Prompt.leave, f.vm.promptKind());
    const again = f.env.cx.focus_manager.getFocused() orelse return error.TestNothingFocusedOnReopen;
    try std.testing.expect(again == try kit.expectByTestId(f.env.cx.root.?, m.ids.confirmation_cancel) or again.isDescendantOf(try kit.expectByTestId(f.env.cx.root.?, m.ids.confirmation_cancel)));
}
/// 原生 Modal 的对话框面板：正文往上第一个带 dialog 角色的节点。
fn panelOf(node: *ui.Node) ?*ui.Node {
    var cursor: ?*ui.Node = node;
    while (cursor) |current| : (cursor = current.parent) {
        if (current.behavior.interaction.a11y) |a| if (a.role == .dialog) return current;
    }
    return null;
}

test "settings yix overview rows show live summaries and open their subpage" {
    var f: Fixture = undefined;
    try f.init(.light);
    defer f.deinit();
    f.go(m.Intent.selectCategory(2));
    try std.testing.expect((try f.expect("settings.overview.hero")).globalRect().h > 0);
    const summary = try f.expect("settings.overview.ssh.connection.summary");
    const before = try std.testing.allocator.dupe(u8, summary.getText().?.content);
    defer std.testing.allocator.free(before);
    f.vm.dispatch(m.Intent.editValue(.{ .section = "ssh", .key = "keepalive_sec" }, .{ .unsigned = 45 }));
    f.env.frame();
    try std.testing.expect(!std.mem.eql(u8, before, summary.getText().?.content));
    // 概览本身没有可编辑字段（H-save：带着改动离开会先确认）；这里的草稿是直接写进去的，先放弃再点行。
    f.controller.discard();
    f.vm.sync();
    const row = (try f.expect("settings.overview.ssh.socks")).globalRect();
    f.env.cx.handleClick(row.x + row.w / 2, row.y + row.h / 2);
    f.env.frame();
    try std.testing.expectEqual(@as(?u8, 1), f.controller.location().sub);
}

/// 搜索框（S-4）里实际获得焦点、承载文字的节点（`W.Input` 的输入框）。
fn searchBox(f: *Fixture) !*ui.Node {
    const root = try f.expect(m.ids.search);
    return firstFocusable(root) orelse error.TestSearchNotFocusable;
}
fn firstFocusable(node: *ui.Node) ?*ui.Node {
    if (node.behavior.interaction.focusable) return node;
    for (node.children.items) |child| if (firstFocusable(child)) |found| return found;
    return null;
}
test "settings yix search field dispatches the query" {
    var f: Fixture = undefined;
    try f.init(.light);
    defer f.deinit();
    const box = try searchBox(&f);
    f.env.cx.setFocus(box);
    f.env.cx.handleTextInput("keepalive");
    f.env.frame();
    try std.testing.expectEqualStrings("keepalive", f.controller.search_query);
    try std.testing.expectEqual(m.Mode.search, f.vm.mode());
    try std.testing.expectEqualStrings("keepalive", f.vm.searchField());
}

test "settings yix search field: typing lands in place, navigation clears it without a host handle (S-4)" {
    var f: Fixture = undefined;
    try f.init(.light);
    defer f.deinit();
    const box = try searchBox(&f);
    f.env.cx.setFocus(box);
    f.env.cx.handleTextInput("keep");
    f.env.frame();
    f.env.cx.handleKeyDown(.left, .{});
    f.env.cx.handleTextInput("x");
    f.env.frame();
    // 同步写回：编辑原地落地（光标在插入处），不被当成外部写入整段替换。
    try std.testing.expectEqualStrings("keexp", f.vm.searchField());
    try std.testing.expectEqualStrings("keexp", f.controller.search_query);
    try std.testing.expect(f.env.cx.focus_manager.getFocused() == box);
    // 导航：view-model 清空受控值，不再有 `clear_search_field`。
    f.go(m.Intent.selectCategory(2));
    try std.testing.expectEqualStrings("", f.vm.searchField());
    try std.testing.expectEqualStrings("", f.controller.search_query);
    try std.testing.expectEqual(m.Mode.overview, f.vm.mode());
    // 搜索框不随内容页纪元重挂：还是同一个节点。
    try std.testing.expect((try searchBox(&f)) == box);
}

test "settings yix search field: a clear during IME composition waits for the composition (S-4, G18)" {
    var f: Fixture = undefined;
    try f.init(.light);
    defer f.deinit();
    const box = try searchBox(&f);
    f.env.cx.setFocus(box);
    f.env.cx.handleTextInput("ssh");
    f.env.frame();
    try std.testing.expectEqualStrings("ssh", f.controller.search_query);
    // 组字中导航：搜索词立即清空（内容按非搜索重挂），输入框保留预编辑、推迟清空。
    f.env.cx.handleImePreedit("ni", 2);
    f.env.frame();
    f.go(m.Intent.selectCategory(2));
    try std.testing.expectEqualStrings("", f.controller.search_query);
    try std.testing.expectEqualStrings("", f.vm.searchField());
    // 取消组字后应用推迟的清空：不回调 onChange（搜索词保持空）。
    f.env.cx.handleImePreedit("", 0);
    f.env.frame();
    try std.testing.expectEqualStrings("", f.controller.search_query);
    try std.testing.expectEqual(m.Mode.overview, f.vm.mode());
    // 再次组字中导航，这次提交：用户输入优先，经 onChange 重新成为搜索词。
    f.env.cx.handleTextInput("ab");
    f.env.frame();
    f.env.cx.handleImePreedit("ni", 2);
    f.env.frame();
    f.go(m.Intent.selectCategory(3));
    try std.testing.expectEqualStrings("", f.controller.search_query);
    f.env.cx.handleImeCommit("你");
    f.env.frame();
    try std.testing.expectEqualStrings(f.vm.searchField(), f.controller.search_query);
    try std.testing.expect(std.mem.endsWith(u8, f.controller.search_query, "你"));
}

/// 设置外壳从 Zig 覆盖改为 token（F-set-thin）后，每个 token 必须与它取代的 Zig 算式逐值相等：
/// 三个外观族与注册表里全部主题，叠加材质透明度与“有壁纸”两档。右边是原 `settings_shell` /
/// `settings_styles` / `components/shell` 里的算式原文。
fn expectWindowTokens() !void {
    const c = app_theme.current();
    const s = app_theme.states();
    const t = app_theme.widgetTheme(app_theme.currentName()).tokens.color;
    const eq = std.testing.expectEqual;
    try eq(c.surface_1.withAlpha(255), t.zw_window_surface); // settings_shell.surface / glassSurface
    try eq(c.surface_2.withAlpha(255), t.zw_window_rest); // navigation / paneSurface
    try eq(c.fg_3, t.zw_fg_faint); // 锁、尾部箭头、Save Bar 幽灵按钮文字
    try eq(c.fg_3, t.fg_disabled); // ghost 色调的禁用墨色（“撤销更改”禁用前后同色）
    try eq(secondaryInk(), t.zw_fg_supporting);
    // Button role tokens are zenit defaults (T-1); the brand mark ink is zw_primary_fg.
    try eq(app_theme.zenitDefaults(app_theme.currentName()).tokens.color.button_primary_bg, t.button_primary_bg); // settings_shell.selectedFill
    try eq(app_theme.zenitDefaults(app_theme.currentName()).tokens.color.button_primary_fg, t.button_primary_fg);
    try eq(s.primary_ink, t.zw_primary_fg);
    try eq(s.hover, t.bg_hover); // rowHover / glassNavHover / buttonHover
    try eq(s.pressed, t.bg_active); // glassNavPressed
    try eq(c.fg_1, t.fg_primary);
    try eq(c.fg_2, t.fg_secondary);
    try eq(c.border, t.border); // heroTile / overviewTile / glassStroke
    try eq(c.ok_ink, t.success); // Save Bar 对勾
    try eq(c.accent_ink, t.info); // Save Bar “恢复默认…”链接
    // 关于与更新的应用图标（品牌对角渐变）；Save Bar 的“保存”已是原生 primary（H-save），不再用这组 token。
    try eq(s.primary, t.zw_primary);
    try eq(s.primary_to, t.zw_primary_to);
    try eq(c.surface_2, t.zw_island_rest);
    try eq(c.fg_3, t.fg_disabled); // 不可用时的墨色（原 baseStyle 的 fg_3，被色调的 :disabled 压过）
}

test "settings window tokens equal the Zig colours they replace for every family, registry theme and material" {
    const previous = app_theme.currentName();
    const was_visible = app_theme.materialVisible();
    const material = app_theme.materialParameters();
    defer {
        _ = app_theme.setMaterialParameters(material.transparency, material.blur);
        _ = app_theme.setMaterialVisible(was_visible);
        app_theme.select(previous);
    }
    var registry = try @import("../../../config/theme_registry.zig").Registry.init(std.testing.allocator);
    defer registry.deinit();
    var checked: usize = 0;
    for ([_]bool{ false, true }) |visible| {
        _ = app_theme.setMaterialVisible(visible);
        for ([_]f32{ 0, 25, 60, 100 }) |transparency| {
            _ = app_theme.setMaterialParameters(transparency, 0);
            for (std.enums.values(app_theme.Name)) |name| {
                app_theme.select(name);
                try expectWindowTokens();
                checked += 1;
            }
            for (registry.records.items) |record| {
                errdefer std.debug.print("settings window token mismatch: {s} transparency {d} visible {}\n", .{ record.id, transparency, visible });
                app_theme.selectTokens(record.ui_tokens);
                try expectWindowTokens();
                checked += 1;
            }
        }
    }
    try std.testing.expectEqual(2 * 4 * (3 + registry.records.items.len), checked);
    try std.testing.expect(registry.records.items.len >= 39);
}

fn findText(node: *ui.Node, content: []const u8) ?*ui.Node {
    if (node.getText()) |t| if (std.mem.eql(u8, t.content, content)) return node;
    for (node.children.items) |child| if (findText(child, content)) |found| return found;
    return null;
}

test "settings yix status line is a view-model projection of the host status (hidden, text follows sync)" {
    var f: Fixture = undefined;
    try f.init(.light);
    defer f.deinit();
    const island = try f.expect("settings.island");
    var first = "InvalidValue: ssh.keepalive_sec".*;
    f.status_line = &first;
    f.vm.sync();
    f.env.frames(2);
    const line = findText(island, "InvalidValue: ssh.keepalive_sec") orelse return error.TestStatusLineNotProjected;
    // 宿主没有显示状态行的写入点：始终隐藏，只保留文字。
    try std.testing.expectEqual(ui.types.Display.none, line.style.display);
    var second = "设置 · 未保存".*;
    f.status_line = &second;
    f.vm.sync();
    f.env.frames(2);
    try std.testing.expect(findText(island, "设置 · 未保存") == line);
}

/// Thumb of a zenit Switch (root → track → thumb).
fn switchThumb(node: *ui.Node) *ui.Node {
    return node.children.items[0].children.items[0];
}
fn translateSlotActive(node: *ui.Node) bool {
    if (node.frame_state.frame_local.runtime.transitions) |slots| if (slots.find(.translate_x)) |slot| return slot.active;
    return false;
}
/// Composite thumb offset inside the track (`globalRect` includes translate).
fn thumbOffset(node: *ui.Node) f32 {
    const thumb = switchThumb(node);
    return thumb.globalRect().x - node.children.items[0].globalRect().x;
}
fn thumbLayout(node: *ui.Node) f32 {
    return thumbOffset(node) - switchThumb(node).style.translate_x;
}

test "settings yix switches appear at rest and slide only by translate when toggled (default-on first paint)" {
    var f: Fixture = undefined;
    try f.init(.light);
    defer f.deinit();
    // SSH › 断线重连: auto_reconnect defaults to on.
    f.go(m.Intent.openAt(.{ .page = 2, .sub = 2 }));
    const on = try f.expect("settings.field.auto_reconnect");
    const thumb = switchThumb(on);
    // md Switch: track 40 × 22, thumb 18, on rest 20 / off rest 2, no inline geometry.
    try std.testing.expectEqual(@as(f32, 40), on.children.items[0].globalRect().w);
    try std.testing.expectEqual(@as(f32, 22), on.children.items[0].globalRect().h);
    try std.testing.expectEqual(@as(f32, 18), thumb.globalRect().w);
    try std.testing.expect(!translateSlotActive(thumb));
    try std.testing.expectApproxEqAbs(@as(f32, 20), thumbOffset(on), 0.01);
    const layout = thumbLayout(on);
    // Toggle off: the recipe transition slides translate 20 → 2; the layout box stays put.
    const r = on.globalRect();
    f.env.cx.handleClick(r.x + r.w / 2, r.y + r.h / 2);
    f.env.frame();
    try std.testing.expect(translateSlotActive(thumb));
    try std.testing.expectApproxEqAbs(layout, thumbLayout(on), 0.01);
    f.env.frames(30);
    try std.testing.expect(!translateSlotActive(thumb));
    try std.testing.expectApproxEqAbs(layout, thumbLayout(on), 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 2), thumbOffset(on), 0.01);
    // A remount (new content epoch) paints the stored value at rest again.
    f.go(m.Intent.openAt(.{ .page = 2, .sub = 0 }));
    const off = try f.expect("settings.field.compression");
    try std.testing.expect(!translateSlotActive(switchThumb(off)));
    try std.testing.expectApproxEqAbs(@as(f32, 2), thumbOffset(off), 0.01);
    f.go(m.Intent.openAt(.{ .page = 2, .sub = 2 }));
    const again = try f.expect("settings.field.auto_reconnect");
    try std.testing.expect(!translateSlotActive(switchThumb(again)));
}

const Pill = struct { background: ui.Color, border: ui.Color, border_width: f32, radius: ?ui.types.CornerRadius };
fn pill(node: *ui.Node) Pill {
    return .{ .background = node.getBackground(), .border = node.style.border.color, .border_width = node.style.border.width, .radius = node.style.corner_radius() };
}
fn settle(env: *kit.Headless) void {
    for (0..20) |_| {
        env.cx.advanceFrameClock();
        env.frame();
    }
}

// 搜索框（S-4）是原生 `W.Input`（sm）的默认外观（人工验收反馈 1 / 原生规则）：与一个没有任何覆盖的同尺寸
// `W.Input` 在静止、悬停、聚焦、有文字时画得一样——圆角始终是 sm 输入框自己的值（不再照搬旧实现“首次聚焦前 14”），
// 底色与描边是组件默认；主题发布后跟随 token。
test "settings yix search field is the native W.Input default in every state (S-4)" {
    for ([_]app_theme.Name{ .light, .dark }) |name| {
        var f: Fixture = undefined;
        try f.init(name);
        defer f.deinit();
        try f.env.cx.setTestFrameStep(16);
        // 参照：同参数的原生 `W.Input`，挂在窗口下方同宽的槽里，没有任何样式覆盖。
        const slot = try ui.box(f.env.cx, .{ .width = .{ .px = 200 }, .height = .{ .px = 28 }, .direction = .row, .align_items = .stretch, .position = .absolute, .inset = .{ .left = .{ .px = 400 }, .top = .{ .px = 700 } } }, .{});
        const native = try ui.widgets.Input(.{ .placeholder = "搜索设置", .leading_icon_asset = ui.icons.search, .size = .sm }).mountResult(f.env.scope, f.env.cx);
        try slot.appendChild(f.env.cx.allocator, native.node);
        try f.env.mount(slot);
        settle(&f.env);
        const box = try searchBox(&f);
        const ref_box = firstFocusable(native.node) orelse return error.TestSearchNotFocusable;
        try std.testing.expectEqualDeep(pill(ref_box), pill(box));
        // 悬停：各自在指针下时比较
        const hover_native = blk: {
            const r = ref_box.globalRect();
            f.env.cx.handleMouseMove(r.x + r.w / 2, r.y + r.h / 2);
            settle(&f.env);
            break :blk pill(ref_box);
        };
        {
            const r = box.globalRect();
            f.env.cx.handleMouseMove(r.x + r.w / 2, r.y + r.h / 2);
            settle(&f.env);
        }
        try std.testing.expectEqualDeep(hover_native, pill(box));
        f.env.cx.handleMouseMove(1, 1);
        settle(&f.env);
        // 聚焦 + 打字：圆角在聚焦前后不变（没有旧实现的 14 → 4）；失焦后与参照一致。
        const rest_radius = pill(box).radius;
        for ([_]*ui.Node{ ref_box, box }) |node| {
            f.env.cx.setFocus(node);
            f.env.cx.handleTextInput("ab");
            settle(&f.env);
        }
        f.env.cx.setFocus(box);
        settle(&f.env);
        try std.testing.expectEqualDeep(rest_radius, pill(box).radius);
        f.env.cx.setFocus(null);
        settle(&f.env);
        try std.testing.expectEqualDeep(rest_radius, pill(box).radius);
        // 主题发布：搜索框随 token 重画。
        const before = pill(box).background;
        app_theme.select(if (name == .light) .dark else .light);
        defer app_theme.select(name);
        f.env.publishTheme();
        settle(&f.env);
        try std.testing.expect(!ui.Color.eql(before, pill(box).background));
    }
}

/// 内容视口（`settings.viewport`）的滚动内容节点与它当前的偏移（`translate_y` 的相反数）。
fn viewportOffset(f: *Fixture) !f32 {
    const viewport = try f.expect(m.ids.viewport);
    return -viewport.children.items[0].style.translate_y;
}
/// 视口显示的偏移（像素对齐）与 view-model 的存档一致。
fn expectShownOffset(f: *Fixture, expected: f32) !void {
    try std.testing.expectApproxEqAbs(expected, try viewportOffset(f), 0.5);
}
fn wheel(f: *Fixture, dy: f32) !void {
    const r = (try f.expect(m.ids.viewport)).globalRect();
    f.env.cx.handleScroll(.{ .dx = 0, .dy = dy, .x = r.x + r.w / 2, .y = r.y + r.h / 2 });
    settle(&f.env);
}

test "settings yix viewport scroll offsets live in the view-model per location and come back on remount (S-5)" {
    var f: Fixture = undefined;
    try f.init(.light);
    defer f.deinit();
    try f.env.cx.setTestFrameStep(16);
    const Slot = m.ScrollSlot;
    f.go(m.Intent.openAt(.{ .page = 4, .sub = 1 }));
    settle(&f.env);
    try std.testing.expectEqual(Slot.normal(4), f.vm.mountedScroll());
    try std.testing.expectEqual(@as(f32, 0), try viewportOffset(&f));
    // 用户滚动：视口回报稳定偏移，view-model 按挂载时的槽存档（Controller.scroll_offsets）。
    try wheel(&f, -150);
    const reading = f.vm.scrollOffset(Slot.normal(4));
    try expectShownOffset(&f, reading);
    try std.testing.expect(reading > 0);
    try std.testing.expectEqual(reading, f.vm.scrollOffset(Slot.normal(4)));
    try std.testing.expectEqual(reading, f.controller.scroll_offsets[4]);
    // 同一位置重挂（草稿变化 / 主题发布的重建）：新视口回到原偏移，没有宿主参与。
    f.vm.remountContent();
    settle(&f.env);
    try expectShownOffset(&f, reading);
    // 搜索各分类一份：从 0 开始，滚动不覆盖页面的阅读位置。
    f.go(m.Intent.searchFor("a"));
    settle(&f.env);
    try std.testing.expectEqual(Slot.search(4), f.vm.mountedScroll());
    try std.testing.expectEqual(@as(f32, 0), try viewportOffset(&f));
    try wheel(&f, -80);
    const search_reading = f.vm.scrollOffset(Slot.search(4));
    try expectShownOffset(&f, search_reading);
    try std.testing.expect(search_reading > 0);
    try std.testing.expectEqual(search_reading, f.vm.scrollOffset(Slot.search(4)));
    try std.testing.expectEqual(reading, f.vm.scrollOffset(Slot.normal(4)));
    // 后退离开搜索（位置不变）：回到页面的阅读位置。
    f.go(.back);
    settle(&f.env);
    try std.testing.expectEqual(Slot.normal(4), f.vm.mountedScroll());
    try expectShownOffset(&f, reading);
    // 导航到新位置：新位置从顶部开始（槽清零），旧分类的存档也按旧规则清零于再次进入时。
    f.go(m.Intent.selectCategory(2));
    settle(&f.env);
    try std.testing.expectEqual(@as(f32, 0), try viewportOffset(&f));
    f.go(m.Intent.openAt(.{ .page = 4, .sub = 1 }));
    settle(&f.env);
    try std.testing.expectEqual(@as(f32, 0), try viewportOffset(&f));
    // 宿主“恢复原位置”（数据清理）：写当前槽，视口滚过去。
    f.vm.setScroll(f.vm.mountedScroll(), reading);
    settle(&f.env);
    try expectShownOffset(&f, reading);
    // 超出范围的写入被夹取并回报。
    f.vm.setScroll(f.vm.mountedScroll(), 1e6);
    settle(&f.env);
    const max = f.vm.scrollOffset(Slot.normal(4));
    try expectShownOffset(&f, max);
    try std.testing.expect(max < 1e6 and max > reading);
    try std.testing.expectEqual(max, f.vm.scrollOffset(Slot.normal(4)));
    // 窗口关闭再打开：新信号从存档初始化。
    f.vm.detach();
    try f.vm.attach(f.env.scope);
    try std.testing.expectEqual(max, f.vm.signals.?.scroll[Slot.normal(4).index()].peek());
}

test "settings yix scroll slots follow the old mounted-offset rule (S-5)" {
    const Slot = m.ScrollSlot;
    try std.testing.expectEqual(Slot.search(0), Slot.of(0, true));
    try std.testing.expectEqual(Slot.normal(0), Slot.of(0, false));
    try std.testing.expectEqual(Slot.search(5), Slot.of(5, true));
    try std.testing.expectEqual(Slot.normal(5), Slot.of(5, false));
    // 槽两两不同、编号连续。
    var seen: std.StaticBitSet(m.scroll_slots) = .empty;
    for (0..9) |page| {
        try std.testing.expect(!seen.isSet(Slot.normal(page).index()));
        seen.set(Slot.normal(page).index());
        try std.testing.expect(!seen.isSet(Slot.search(page).index()));
        seen.set(Slot.search(page).index());
    }
    try std.testing.expectEqual(@as(usize, m.scroll_slots), seen.count());
}

fn effectCount(f: *Fixture, tag: std.meta.Tag(m.Effect)) usize {
    var n: usize = 0;
    for (f.effects.items) |item| n += @intFromBool(item == tag);
    return n;
}
fn fieldBox(f: *Fixture, id: []const u8) !*ui.Node {
    return firstFocusable(try f.expect(id)) orelse error.TestFieldNotFocusable;
}

test "settings window shortcuts map Escape, ⌘W and ⌘, (S-6)" {
    try std.testing.expectEqual(m.WindowCommand.escape, m.windowCommand(.escape, .{}).?);
    try std.testing.expectEqual(m.WindowCommand.escape, m.windowCommand(.escape, .{ .shift = true }).?);
    try std.testing.expectEqual(m.WindowCommand.close, m.windowCommand(.w, .{ .super = true }).?);
    try std.testing.expectEqual(m.WindowCommand.close, m.windowCommand(.comma, .{ .super = true }).?);
    try std.testing.expect(m.windowCommand(.w, .{}) == null);
    try std.testing.expect(m.windowCommand(.comma, .{ .ctrl = true }) == null);
    try std.testing.expect(m.windowCommand(.a, .{ .super = true }) == null);
}

test "settings yix window keys reach the template root's capture handler with or without focus; the card is not focusable (S-6)" {
    var f: Fixture = undefined;
    try f.init(.light);
    defer f.deinit();
    f.go(m.Intent.openAt(.{ .page = 2, .sub = 0 }));
    const card = try f.expect("settings.panel");
    try std.testing.expect(!card.behavior.interaction.focusable);
    // 打开时不抢焦点（旧宿主把焦点塞给卡片，不画焦点环；现在保持无焦点）。
    try std.testing.expect(f.env.cx.focus_manager.getFocused() == null);
    f.effects.clearRetainingCapacity();
    // 无焦点：按键落到模板根，捕获处理器照样收到。
    f.env.cx.handleKeyDown(.escape, .{});
    f.env.cx.handleKeyDown(.w, .{ .super = true });
    f.env.cx.handleKeyDown(.comma, .{ .super = true });
    f.env.cx.handleKeyDown(.a, .{});
    try std.testing.expectEqual(@as(usize, 1), effectCount(&f, .escape));
    try std.testing.expectEqual(@as(usize, 2), effectCount(&f, .request_close));
    // 焦点在正文输入框里：捕获阶段先于输入框（与旧卡片捕获同序），Escape 不再交给输入框。
    const field = try fieldBox(&f, "settings.field.keepalive_sec");
    f.env.cx.setFocus(field);
    f.effects.clearRetainingCapacity();
    f.env.cx.handleKeyDown(.escape, .{});
    try std.testing.expectEqual(@as(usize, 1), effectCount(&f, .escape));
    try std.testing.expect(f.env.cx.focus_manager.getFocused() == field);
    // 关口拒绝（录制快捷键 / 确认弹窗）：放行，不发 Effect。
    f.window_keys = false;
    f.effects.clearRetainingCapacity();
    f.env.cx.handleKeyDown(.escape, .{});
    f.env.cx.handleKeyDown(.w, .{ .super = true });
    try std.testing.expectEqual(@as(usize, 0), f.effects.items.len);
    f.window_keys = true;
    // 组字中：按键归输入法，捕获处理器不被调用（旧卡片捕获在组字时也会收到 Escape）。
    f.env.cx.handleImePreedit("ni", 2);
    f.env.frame();
    f.effects.clearRetainingCapacity();
    f.env.cx.handleKeyDown(.escape, .{});
    try std.testing.expectEqual(@as(usize, 0), effectCount(&f, .escape));
    // Tab 从无焦点开始：落到窗口里第一个可聚焦控件（搜索框）。
    f.env.cx.handleImePreedit("", 0);
    f.env.cx.setFocus(null);
    f.env.frame();
    f.env.cx.handleKeyDown(.tab, .{});
    f.env.frame();
    try std.testing.expect(f.env.cx.focus_manager.getFocused() == try searchBox(&f));
}

test "settings yix content remount puts focus and selection back into the same field (S-6 focusRestore)" {
    var f: Fixture = undefined;
    try f.init(.light);
    defer f.deinit();
    f.go(m.Intent.openAt(.{ .page = 2, .sub = 0 }));
    const field = try fieldBox(&f, "settings.field.keepalive_sec");
    f.env.cx.setFocus(field);
    f.env.cx.handleKeyDown(.a, .{ .super = true });
    f.env.cx.handleTextInput("123");
    f.env.cx.handleKeyDown(.left, .{ .shift = true });
    f.env.frame();
    // 宿主的重挂（`SettingsHost.rebuildYixContent`）：交出正文焦点，再开一个新纪元（旧宿主在这里拍焦点快照，settle 后放回）。
    (frame_mod.Page.of(&f.frame) orelse return error.TestNoPage).releaseFocus(f.env.cx, field);
    try std.testing.expect(f.env.cx.focus_manager.getFocused() == null);
    f.vm.remountContent();
    f.env.frames(3);
    const again = try fieldBox(&f, "settings.field.keepalive_sec");
    try std.testing.expect(again != field);
    try std.testing.expect(f.env.cx.focus_manager.getFocused() == again);
    const client = again.behavior.interaction.text_input_client.?;
    const selection = client.selection(client.context);
    try std.testing.expectEqual(@as(u32, 2), selection.start);
    try std.testing.expectEqual(@as(u32, 3), selection.end);
    // 换到别的分类：没有同名字段，焦点不落到任何地方（旧宿主落到卡片）。先放弃草稿——带着本页改动离开会先弹确认（H-save）。
    f.controller.discard();
    f.vm.sync();
    f.go(m.Intent.selectCategory(3));
    f.env.frames(2);
    try std.testing.expect(f.env.cx.focus_manager.getFocused() == null);
}

test "settings yix view-model focus requests land on the data page's clear buttons (S-6)" {
    var f: Fixture = undefined;
    try f.init(.light);
    defer f.deinit();
    f.go(m.Intent.openAt(.{ .page = 7, .sub = 2 }));
    f.vm.requestFocus(m.focus_ids.data_clear_all);
    f.env.frame();
    const focused = f.env.cx.focus_manager.getFocused() orelse return error.TestNothingFocused;
    const all = try f.expect("settings.data.clear_all");
    try std.testing.expect(focused == all or focused.isDescendantOf(all));
    f.vm.requestFocus(m.focus_ids.data_clear_logs);
    f.env.frame();
    const logs = try f.expect("settings.data.clear_logs");
    const now = f.env.cx.focus_manager.getFocused() orelse return error.TestNothingFocused;
    try std.testing.expect(now == logs or now.isDescendantOf(logs));
}

test "settings yix overview rows derive from the current category; switching to a category with fewer rows before the remount is safe (G21)" {
    var f: Fixture = undefined;
    try f.init(.light);
    defer f.deinit();
    f.go(m.Intent.selectCategory(2)); // SSH 与网络：4 个子页面
    _ = try f.expect("settings.overview.ssh.authentication");
    // 只派发、不重挂：行内派生（读当前分类）与驱动列表的分类信号同时变脏（G21 的场景）。被删的两行不再以新分类重算；
    // 留下的两行 key 不变，标题随新分类（test_id 是挂载时属性，宿主随后整页重挂）。
    {
        // 用户点导航行（事件处理器里写信号，与真实路径相同）。
        const r = (try f.expect("settings.nav.notifications")).globalRect();
        f.env.cx.handleClick(r.x + r.w / 2, r.y + r.h / 2);
    }
    f.env.frames(2);
    const list = try f.expect("settings.overview.list");
    var shown_rows: usize = 0;
    for (list.children.items) |child| shown_rows += @intFromBool(child.style.display != .none);
    try std.testing.expectEqual(@as(usize, 2), shown_rows);
    try std.testing.expect(findText(list, "事件提醒") != null);
    try std.testing.expect(kit.findByTestId(f.root, "settings.overview.ssh.authentication") == null);
    f.vm.remountContent();
    f.env.frames(2);
    _ = try f.expect("settings.overview.notifications.events");
    _ = try f.expect("settings.overview.notifications.attention");
    // 回到项更多的分类：行数随之增加。
    f.go(m.Intent.selectCategory(2));
    _ = try f.expect("settings.overview.ssh.reconnect");
    _ = try f.expect("settings.overview.ssh.authentication");
}

// H-save：草稿在面板之外被直接改动（宿主侧的编辑）后，宿主换纪元整页重挂；新内容页的 Save Bar 必须跟着草稿出现。
test "settings yix save bar shows after a direct draft edit and the epoch remount (H-save)" {
    var f: Fixture = undefined;
    try f.init(.light);
    defer f.deinit();
    f.go(m.Intent.openAt(.{ .page = 0, .sub = 1 }));
    try std.testing.expectEqual(ui.types.Display.none, (try f.expect("settings.footer")).style.display);
    try f.controller.editKey("ui", "cursor_style", .{ .text = "underline" });
    f.vm.sync();
    f.vm.dispatch(.draft_changed);
    f.vm.remountContent();
    settle(&f.env);
    const footer = try f.expect("settings.footer");
    try std.testing.expect(footer.style.display != .none);
    try std.testing.expect(footer.globalRect().w > 0);
}

fn hasText(node: *ui.Node, needle: []const u8) bool {
    if (node.getText()) |t| if (std.mem.indexOf(u8, t.content, needle) != null) return true;
    for (node.children.items) |child| if (hasText(child, needle)) return true;
    return false;
}

// S-19（G38）：设置窗口的 Toast 是模板里的原生 `W.NotificationHost`，请求来自 view-model 的 `toast` 信号；宿主不持有 Notifier。
test "settings yix save toast comes from the view-model through the native notification host (S-19)" {
    var f: Fixture = undefined;
    try f.init(.light);
    defer f.deinit();
    f.go(m.Intent.openAt(.{ .page = 2, .sub = 0 }));
    try std.testing.expect(!hasText(f.env.cx.root.?, "设置已保存"));
    f.vm.dispatch(m.Intent.saveFinished(null));
    settle(&f.env);
    try std.testing.expect(hasText(f.env.cx.root.?, "设置已保存"));
    try std.testing.expectEqual(m.ToastTone.success, f.vm.toast().tone);
}

test "settings yix window: the host's node handles are live refs — the page handle follows epoch remounts, all are withdrawn on unmount" {
    var f: Fixture = undefined;
    try f.init(.light);
    var live = true;
    defer if (live) f.deinit();
    // What the template handed over is what carries the ids (no lookup by test id in the host).
    try std.testing.expectEqual(try f.expect("settings.panel"), f.frame.panel().?);
    try std.testing.expectEqual(try f.expect("settings.island"), f.frame.island().?);
    const first = frame_mod.Page.of(&f.frame).?.root;
    try std.testing.expectEqual(try f.expect(m.ids.content), first);
    // A new content epoch: the old page is unmounted, the handle moves to the new page's root.
    f.go(m.Intent.openAt(.{ .page = 4, .sub = 1 }));
    const second = frame_mod.Page.of(&f.frame).?.root;
    try std.testing.expectEqual(try f.expect(m.ids.content), second);
    for (0..5) |_| {
        f.vm.remountContent();
        f.env.frame();
        // Whenever a page is mounted the handle is that page — never a page that was freed.
        if (frame_mod.Page.of(&f.frame)) |page| try std.testing.expectEqual(try f.expect(m.ids.content), page.root);
    }
    f.env.frames(2);
    try std.testing.expectEqual(try f.expect(m.ids.content), frame_mod.Page.of(&f.frame).?.root);
    // The panel / island handles did not move.
    try std.testing.expectEqual(try f.expect("settings.panel"), f.frame.panel().?);
    // Window scope gone (the aux window closed): nothing left to read.
    live = false;
    f.deinit();
    try std.testing.expect(f.frame.handles == null);
    try std.testing.expect(frame_mod.Page.of(&f.frame) == null);
    try std.testing.expect(f.frame.panel() == null);
}

fn within(node: *ui.Node, root: *ui.Node) bool {
    var cur: ?*ui.Node = node;
    while (cur) |n| : (cur = n.parent) if (n == root) return true;
    return false;
}

test "settings yix window: with a main window beside it, a theme switch replays in both and the content handle is the mounted page (never an old one)" {
    // The main window: its own Cx, same process-wide theme.
    var main = try kit.headless(std.testing.allocator, .{ .width = 900, .height = 600, .theme = .light, .root_style = .{ .width = .fill(), .height = .fill(), .direction = .column } });
    defer main.deinit();
    try main.mount(try ui.text(main.cx, "main window", .{ .font_size = 13 }));
    main.frames(2);
    var f: Fixture = undefined;
    try f.init(.light);
    defer f.deinit();
    f.go(m.Intent.openAt(.{ .page = 2, .sub = 0 }));
    const panel = f.frame.panel().?;
    const island = f.frame.island().?;
    var previous = frame_mod.Page.of(&f.frame).?.root;
    for ([_]app_theme.Name{ .dark, .light, .dark }) |name| {
        // One process-wide switch, published in both windows.
        app_theme.select(name);
        main.publishTheme();
        f.env.publishTheme();
        main.frames(2);
        f.env.frames(2);
        // Theme replay alone: the same page, restyled; the handle still is that page.
        const replayed = frame_mod.Page.of(&f.frame).?.root;
        try std.testing.expectEqual(previous, replayed);
        try std.testing.expectEqual(try f.expect(m.ids.content), replayed);
        try std.testing.expect(within(replayed, f.root));
        // The host answers a publication with a new content epoch (rebuild): for every frame of the
        // remount the handle is either empty or the page that is mounted right now.
        f.vm.remountContent();
        for (0..4) |_| {
            f.env.frame();
            main.frame();
            if (frame_mod.Page.of(&f.frame)) |page| {
                try std.testing.expectEqual(try f.expect(m.ids.content), page.root);
                try std.testing.expect(within(page.root, f.root));
            }
        }
        const now = frame_mod.Page.of(&f.frame).?.root;
        try std.testing.expect(now != previous);
        try std.testing.expectEqual(try f.expect(m.ids.content), now);
        // Only one page is mounted: the old root is gone from the tree.
        var pages: usize = 0;
        for (island.children.items[0].children.items) |child| pages += @intFromBool(child == now or child == previous);
        try std.testing.expectEqual(@as(usize, 1), pages);
        // The window-level handles did not move.
        try std.testing.expectEqual(panel, f.frame.panel().?);
        try std.testing.expectEqual(island, f.frame.island().?);
        // The page really carries the new theme.
        _ = findBackground(try f.expect("settings.ssh.connection"), paneSurface()) orelse return error.TestPaneCardNotRepainted;
        previous = now;
    }
}

/// `SettingsHost.windowEscape` for the fixture: the focused control's focus id goes to the view-model.
fn hostEscape(f: *Fixture) bool {
    const cx = f.env.cx;
    const focused = cx.focus_manager.getFocused();
    return f.vm.consumeEscape(if (focused) |node| cx.focus_targets.targetName(cx, node) else null);
}

test "settings yix window: focus that moved to another window — Escape and close hand the field over cleanly, and coming back lands where asked" {
    var f: Fixture = undefined;
    try f.init(.light);
    var open = true;
    defer if (open) f.deinit();
    const cx = f.env.cx;
    f.go(m.Intent.openAt(.{ .page = 2, .sub = 0 }));
    const field = try fieldBox(&f, "settings.field.keepalive_sec");
    cx.setFocus(field);
    cx.handleKeyDown(.a, .{ .super = true });
    cx.handleTextInput("45");
    f.env.frame();
    try std.testing.expectEqualStrings(m.focus_ids.legacy_field_prefix ++ "settings.field.keepalive_sec", cx.focus_targets.targetName(cx, field).?);

    // Another window takes key: this window keeps its focused field but is inactive.
    cx.window_active = false;
    f.env.frames(2);
    try std.testing.expect(cx.focus_manager.getFocused() == field);
    // Escape arriving for the settings window while it is inactive: the field is recognised by its
    // focus id and gives focus up; nothing else is closed.
    try std.testing.expect(hostEscape(&f));
    f.env.frames(2);
    try std.testing.expect(cx.focus_manager.getFocused() == null);
    try std.testing.expect(frame_mod.Page.of(&f.frame) != null);
    // A second Escape has no field to take: the host would close the window.
    try std.testing.expect(!hostEscape(&f));
    // Back in this window: focus stays where Escape left it (nowhere); asking for the field by its
    // focus id lands on it.
    cx.window_active = true;
    f.env.frames(2);
    try std.testing.expect(cx.focus_manager.getFocused() == null);
    f.vm.requestFocus(m.focus_ids.legacy_field_prefix ++ "settings.field.keepalive_sec");
    f.env.frames(2);
    try std.testing.expect(cx.focus_manager.getFocused() == field);

    // Inactive again, and the window is closed with the field still focused (the host: release the
    // content focus, detach the view-model, the window scope goes).
    cx.window_active = false;
    f.env.frame();
    (frame_mod.Page.of(&f.frame) orelse return error.TestNoPage).releaseFocus(cx, field);
    try std.testing.expect(cx.focus_manager.getFocused() == null);
    f.vm.detach();
    const old_root = f.root;
    cx.content_root = null;
    cx.detachChild(old_root.parent.?, old_root);
    cx.freeNode(old_root);
    // Nothing the host holds points into the closed window.
    try std.testing.expect(f.frame.handles == null);
    try std.testing.expect(frame_mod.Page.of(&f.frame) == null);
    try std.testing.expect(cx.focus_manager.getFocused() == null);
    try std.testing.expect(!hostEscape(&f));
    f.env.frames(3);
    try std.testing.expect(cx.focus_manager.getFocused() == null);

    // Reopened (the draft stays in the controller) and active again: a fresh window, no focus
    // restored into it from the closed one; the field is reachable by its focus id.
    cx.window_active = true;
    try f.vm.attach(f.env.scope);
    f.root = try ui.view.render(f.env.scope, cx, settings_window.SettingsWindow(.{ .vm = &f.vm, .frame = &f.frame }));
    try f.env.mount(f.root);
    cx.content_root = f.root;
    f.vm.sync();
    f.env.frames(3);
    try std.testing.expect(f.frame.handles != null);
    try std.testing.expectEqual(try f.expect(m.ids.content), frame_mod.Page.of(&f.frame).?.root);
    try std.testing.expect(cx.focus_manager.getFocused() == null);
    const again = try fieldBox(&f, "settings.field.keepalive_sec");
    try std.testing.expect(again != field);
    f.vm.requestFocus(m.focus_ids.legacy_field_prefix ++ "settings.field.keepalive_sec");
    f.env.frames(2);
    try std.testing.expect(cx.focus_manager.getFocused() == again);
    try std.testing.expect(hostEscape(&f));
    f.env.frames(2);
    try std.testing.expect(cx.focus_manager.getFocused() == null);
    open = false;
    f.deinit();
}
