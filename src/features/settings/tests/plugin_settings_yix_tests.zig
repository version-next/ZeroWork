//! 协议插件（F-set-plugins，人工验收反馈第 10 条）`.yix` 两级导航的组件测试：列表页（`T5k96`）→ 详情页（`KUKQ5`）。
//! 挂载方式同 `settings_window_yix_tests`：真实设置窗口模板 + 真 `ViewModel` + Ports 替身，注册表是只有元数据的插件清单。
//! 只用 test_id、可见文字、草稿（Controller）与 view-model 的选择器断言。
const std = @import("std");
const ui = @import("ui");
const kit = @import("../../../shared/testing/ui_kit.zig");
const app_theme = @import("../../../shared/ui/theme/app_theme.zig");
const shell = @import("../view/settings_shell.zig");
const Controller = @import("../model/settings_controller.zig").Controller;
const RuntimeConfig = @import("../../../config/runtime_config.zig").RuntimeConfig;
const registry = @import("../../../host/plugin_registry.zig");
const m = @import("../model/view_model.zig");
const frame_mod = @import("../view/window_frame.zig");
const settings_window = @import("../view/_settings_window.yix.zig");

const entries = [_]registry.PluginManifest{
    .{ .id = "ssh", .display_name = "SSH", .summary = "远程终端、认证与端口转发", .plugin_version = "9.8.7", .origin = .builtin, .icons = .{ .settings = "server" }, .workspace_kind = "terminal", .content_renderer = "terminal" },
    .{ .id = "probe", .display_name = "Real registered probe", .plugin_version = "0.3.1", .origin = .bundled, .workspace_kind = "canvas", .content_renderer = "canvas", .settings_section = .{ .fields = &.{
        .{ .key = "show_grid", .label = "显示网格", .kind = .boolean, .default_value = "true", .apply_timing = .next_connection },
        .{ .key = "label", .label = "标签", .kind = .string, .default_value = "grid", .apply_timing = .immediate },
        .{ .key = "mode", .label = "模式", .kind = .choice, .default_value = "a", .options = &.{ .{ .value = "a", .label = "甲" }, .{ .value = "b", .label = "乙" } } },
    } } },
    .{ .id = "bmc_ikvm", .display_name = "BMC · iKVM", .plugin_version = "0.3.2", .origin = .bundled, .icons = .{ .settings = "monitor" }, .workspace_kind = "console", .content_renderer = "console" },
};

const Fixture = struct {
    env: kit.Headless,
    tmp: std.testing.TmpDir,
    runtime: RuntimeConfig,
    controller: Controller,
    vm: m.ViewModel,
    frame: frame_mod.Frame,
    effects: std.ArrayList(std.meta.Tag(m.Effect)) = .empty,
    root: *ui.Node = undefined,

    fn init(self: *Fixture, theme: app_theme.Name) !void {
        const a = std.testing.allocator;
        self.* = .{ .env = try kit.headless(a, .{ .width = shell.window.width, .height = shell.window.height, .theme = theme, .root_style = .{ .width = .fill(), .height = .fill(), .direction = .column } }), .tmp = std.testing.tmpDir(.{}), .runtime = undefined, .controller = undefined, .vm = undefined, .frame = undefined };
        self.runtime = try RuntimeConfig.loadOrDefault(std.testing.io, self.tmp.dir, a, "config.toml");
        self.controller = try Controller.init(a, self.runtime.value);
        self.controller.drill_down = true;
        self.controller.plugin_page.refreshRegistry(.{ .published = .{ .entries = &entries, .renderers = &.{} } }, 0);
        self.controller.history.reset(self.controller.location());
        self.vm = m.ViewModel.init(&self.controller, .{ .context = self, .run = run, .allow = allow, .status = hostStatus });
        self.frame = .{ .vm = &self.vm };
        try self.vm.attach(self.env.scope);
        self.root = try ui.view.render(self.env.scope, self.env.cx, settings_window.SettingsWindow(.{ .vm = &self.vm, .frame = &self.frame }));
        try self.env.mount(self.root);
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
    fn hostStatus(_: *anyopaque) m.HostStatus {
        return .{};
    }
    fn allow(_: *anyopaque, _: m.Gate) bool {
        return true;
    }
    fn changed(_: *anyopaque) void {}
    fn hostView(_: *anyopaque, cx: *ui.Cx, _: *ui.Scope) anyerror!*ui.Node {
        return ui.box(cx, .{ .width = .fill(), .height = .{ .px = 120 }, .flex_shrink = 0 }, .{});
    }
    /// SettingsHost：导航后换一个内容页纪元。
    fn settle(self: *Fixture) void {
        self.vm.remountContent();
        self.env.frames(2);
    }
    fn go(self: *Fixture, intent: m.Intent) void {
        self.vm.dispatch(intent);
        self.settle();
    }
    fn node(self: *Fixture, id: []const u8) !*ui.Node {
        return kit.expectByTestId(self.root, id);
    }
    fn missing(self: *Fixture, id: []const u8) bool {
        const found = kit.findByTestId(self.root, id) orelse return true;
        return !shown(found);
    }
    fn click(self: *Fixture, id: []const u8) !void {
        const rect = (try self.node(id)).globalRect();
        self.env.cx.handleClick(rect.x + rect.w / 2, rect.y + rect.h / 2);
        self.env.frame();
    }
    fn text(self: *Fixture, id: []const u8) ![]const u8 {
        return ((try self.node(id)).getText() orelse return error.TestNoText).content;
    }
};

fn shown(node: *ui.Node) bool {
    var cursor: ?*ui.Node = node;
    while (cursor) |current| : (cursor = current.parent) if (current.style.display == .none) return false;
    return node.globalRect().h > 0;
}
fn hasText(node: *ui.Node, expected: []const u8) bool {
    if (node.style.display == .none) return false;
    if (node.getText()) |value| if (std.mem.eql(u8, value.content, expected)) return true;
    for (node.children.items) |child| if (hasText(child, expected)) return true;
    return false;
}
/// 树序里第一个 `prefix` 开头、`suffix` 结尾的 test_id 序列（只收显示着的）。
fn idsIn(node: *ui.Node, prefix: []const u8, suffix: []const u8, out: *std.ArrayList([]const u8)) !void {
    if (node.style.display == .none) return;
    if (node.meta.ownership.meta.test_id) |id| if (std.mem.startsWith(u8, id, prefix) and std.mem.endsWith(u8, id, suffix)) try out.append(std.testing.allocator, id);
    for (node.children.items) |child| try idsIn(child, prefix, suffix, out);
}

test "plugin settings yix: list page groups registered plugins by origin, one drill-down row each (T5k96)" {
    var f: Fixture = undefined;
    try f.init(.light);
    defer f.deinit();
    f.go(m.Intent.selectCategory(5));
    try std.testing.expectEqualStrings("协议插件", try f.text("settings.page.title"));
    _ = try f.node("settings.plugins");
    // 两个来源分组，页头是标题 + “N 个协议 · 随应用管理”（旧分组标签）。
    try std.testing.expect(shown(try f.node("settings.plugins.builtin")));
    try std.testing.expect(shown(try f.node("settings.plugins.bundled")));
    try std.testing.expectEqualStrings("1 个协议 · 随应用管理", try f.text("settings.plugins.builtin.summary"));
    try std.testing.expectEqualStrings("2 个协议 · 随应用管理", try f.text("settings.plugins.bundled.summary"));
    // 每个插件一行：名称、说明（清单的 `summary`，没写时是工作区类型）、版本尾注；行序同旧实现（已内置在前，注册表顺序）。
    var rows: std.ArrayList([]const u8) = .empty;
    defer rows.deinit(std.testing.allocator);
    try idsIn(try f.node("settings.plugins"), "settings.plugin.", ".row", &rows);
    try std.testing.expectEqual(@as(usize, 3), rows.items.len);
    try std.testing.expectEqualStrings("settings.plugin.ssh.row", rows.items[0]);
    try std.testing.expectEqualStrings("settings.plugin.probe.row", rows.items[1]);
    try std.testing.expectEqualStrings("settings.plugin.bmc_ikvm.row", rows.items[2]);
    try std.testing.expectEqualStrings("SSH", try f.text("settings.plugin.ssh.name"));
    try std.testing.expectEqualStrings("远程终端、认证与端口转发", try f.text("settings.plugin.ssh.description"));
    try std.testing.expectEqualStrings("canvas", try f.text("settings.plugin.probe.description"));
    try std.testing.expectEqualStrings("9.8.7", try f.text("settings.plugin.ssh.trail"));
    // 列表页只导航：没有详情、没有对话框、没有“恢复默认…”（列表页没有可编辑字段）。
    try std.testing.expect(kit.findByTestId(f.root, "settings.plugin.ssh.detail") == null);
    try std.testing.expect(kit.findByTestId(f.root, "settings.plugins.list") == null);
    try std.testing.expect(f.missing(m.ids.reset));
    try std.testing.expectEqualStrings("0.3.2", try f.text("settings.plugin.bmc_ikvm.trail"));
    // “计划中”只有路线条目（网页连接）：名称 + “0.5 版本待实施”，没有版本尾注、不是插件行、点了不进详情。
    try std.testing.expect(shown(try f.node("settings.plugins.planned")));
    try std.testing.expectEqualStrings("网页连接", try f.text("settings.plugins.planned.web.name"));
    try std.testing.expectEqualStrings("0.5 版本待实施", try f.text("settings.plugins.planned.web.summary"));
    try std.testing.expect(kit.findByTestId(f.root, "settings.plugin.web.row") == null);
    try std.testing.expect(!hasText(try f.node("settings.plugins.planned"), "KVM"));
    try std.testing.expect(!hasText(f.root, "FTP / FTPS"));
    try std.testing.expect(kit.findByTestId(f.root, "settings.plugin.detail") == null);
    try f.click("settings.plugins.planned.web.row");
    f.settle();
    try std.testing.expectEqual(m.Location{ .page = 5 }, f.controller.location());
    // 计划中在已注册分组之后。
    try std.testing.expect((try f.node("settings.plugins.planned")).globalRect().y > (try f.node("settings.plugins.bundled")).globalRect().y);
}

test "plugin settings yix: a row opens the protocol's detail page; back / forward walk the history (KUKQ5)" {
    var f: Fixture = undefined;
    try f.init(.light);
    defer f.deinit();
    f.go(m.Intent.selectCategory(5));
    try f.click("settings.plugin.ssh.row");
    f.settle();
    try std.testing.expectEqual(m.Location{ .page = 5, .sub = 0 }, f.controller.location());
    try std.testing.expectEqualStrings("SSH", try f.text("settings.page.title"));
    _ = try f.node("settings.plugins");
    _ = try f.node("settings.plugin.ssh.detail");
    try std.testing.expect(kit.findByTestId(f.root, "settings.plugin.ssh.row") == null);
    // 头部卡片：说明、来源标签（原生 `W.Tag`）、管理说明（旧“已内置 · 随应用管理”与“插件随应用更新”）。
    try std.testing.expectEqualStrings("远程终端、认证与端口转发", try f.text("settings.plugin.ssh.summary"));
    try std.testing.expect(hasText(try f.node("settings.plugin.ssh.origin"), "内置"));
    try std.testing.expectEqualStrings("已内置 · 随应用管理 · 插件随应用更新", try f.text("settings.plugin.ssh.version.message"));
    // 插件信息：版本值、权限值 + 原生“?”提示全文。
    try std.testing.expectEqualStrings("9.8.7", try f.text("settings.plugin.ssh.version"));
    try std.testing.expectEqualStrings("连接时按需请求", try f.text("settings.plugin.ssh.permissions.value"));
    _ = try f.node("settings.plugins.builtin.body");
    try f.click("settings.plugin.ssh.permissions");
    f.env.frames(2);
    try std.testing.expect(f.vm.popupOpen("settings.plugin.ssh.permissions.tooltip"));
    try std.testing.expectEqualStrings("连接时按需读取钥匙串、进行网络连接及用户批准的转发。", f.vm.pluginPermissions(0));
    try std.testing.expectEqualStrings(f.vm.pluginPermissions(0), (try f.node("settings.plugin.ssh.permissions")).behavior.interaction.a11y.?.label.?);
    // 整窗 Escape 先收起提示，不关窗。
    try std.testing.expect(f.vm.consumeEscape(null));
    try std.testing.expect(!f.vm.popupOpen("settings.plugin.ssh.permissions.tooltip"));
    // 没有偏好字段的插件：不显示偏好面板与“恢复默认…”。
    try std.testing.expect(f.missing("settings.plugins.preferences"));
    try std.testing.expect(f.missing(m.ids.reset));
    // 后退回列表、前进回详情。
    f.go(.back);
    try std.testing.expectEqual(m.Location{ .page = 5 }, f.controller.location());
    _ = try f.node("settings.plugin.ssh.row");
    f.go(.forward);
    _ = try f.node("settings.plugin.ssh.detail");
    // 注册表里没有的下标回到列表页。
    f.go(m.Intent.openAt(.{ .page = 5, .sub = 9 }));
    try std.testing.expectEqual(m.Location{ .page = 5 }, f.controller.location());
    _ = try f.node("settings.plugin.bmc_ikvm.row");
}

test "plugin settings yix: preferences edit the draft in the detail page's save scope" {
    var f: Fixture = undefined;
    try f.init(.light);
    defer f.deinit();
    f.go(m.Intent.openAt(.{ .page = 5, .sub = 1 }));
    try std.testing.expectEqual(m.Location{ .page = 5, .sub = 1 }, f.controller.location());
    try std.testing.expect(!f.controller.model.dirty);
    _ = try f.node("settings.plugin.probe.detail");
    try std.testing.expect(shown(try f.node("settings.plugins.preferences")));
    // 生效时机：可聚焦的“?”式按钮，名字是提示文字，不直接画字。
    const timing = try f.node("settings.plugin.probe.show_grid.timing");
    try std.testing.expect(timing.behavior.interaction.focusable);
    try std.testing.expectEqualStrings("下次连接生效", timing.behavior.interaction.a11y.?.label.?);
    try std.testing.expect(!hasText(try f.node("settings.plugins.preferences"), "下次连接生效"));
    try std.testing.expectEqualStrings("保存后生效", (try f.node("settings.plugin.probe.label.timing")).behavior.interaction.a11y.?.label.?);
    // 开关：草稿改成 "false"，出现 Save Bar 与“恢复默认…”。
    try f.click("settings.plugin.probe.show_grid");
    f.env.frames(2);
    try std.testing.expectEqualStrings("false", f.controller.model.value.pluginPreference("probe", "show_grid").?);
    try std.testing.expect(f.controller.model.dirty);
    try std.testing.expect(f.vm.footerVisible());
    try std.testing.expect(shown(try f.node(m.ids.reset)));
    // 选择框与输入框经同一个 Intent 写草稿。
    f.vm.dispatch(m.Intent.setPluginPreference(1, 2, "b"));
    try std.testing.expectEqualStrings("b", f.controller.model.value.pluginPreference("probe", "mode").?);
    f.vm.dispatch(m.Intent.setPluginPreference(1, 1, "dots"));
    try std.testing.expectEqualStrings("dots", f.controller.model.value.pluginPreference("probe", "label").?);
    // 不合法的值被 Controller 拒绝：草稿不变，行下提示原因。
    f.vm.dispatch(m.Intent.setPluginPreference(1, 2, "zzz"));
    f.env.frames(2);
    try std.testing.expectEqualStrings("b", f.controller.model.value.pluginPreference("probe", "mode").?);
    try std.testing.expect(shown(try f.node("settings.plugin.probe.mode.error")));
    try std.testing.expectEqualStrings("取值无效，请检查后重新填写", try f.text("settings.plugin.probe.mode.error"));
    // 偏好改动属于详情页：回列表页（没有可编辑字段）要先确认。
    f.vm.dispatch(.back);
    try std.testing.expectEqual(m.Prompt.leave, f.vm.promptKind());
    f.go(m.Intent.decideWith(.cancel));
    try std.testing.expectEqual(m.Location{ .page = 5, .sub = 1 }, f.controller.location());
}

test "plugin settings yix: search lists matching protocols and a hit opens its detail" {
    var f: Fixture = undefined;
    try f.init(.dark);
    defer f.deinit();
    f.go(m.Intent.searchFor("随应用"));
    const results = try f.node("settings.search.results");
    _ = results;
    try std.testing.expect(shown(try f.node("settings.plugins.bundled")));
    try std.testing.expect(f.missing("settings.plugins.builtin"));
    try std.testing.expect(shown(try f.node("settings.plugin.probe.row")));
    try std.testing.expect(f.missing("settings.plugin.ssh.row"));
    try std.testing.expect(f.vm.pageShownInResults(5));
    try std.testing.expect(f.missing("settings.plugins.planned"));
    // 路线条目也参与搜索。
    f.go(m.Intent.searchFor("网页"));
    try std.testing.expect(f.vm.pageShownInResults(5));
    try std.testing.expect(shown(try f.node("settings.plugins.planned.web.row")));
    try std.testing.expect(f.missing("settings.plugins.builtin"));
    // 名称命中。
    f.go(m.Intent.searchFor("SSH"));
    try std.testing.expect(shown(try f.node("settings.plugin.ssh.row")));
    try std.testing.expectEqualStrings("1 个协议 · 随应用管理", try f.text("settings.plugins.builtin.summary"));
    // 没有命中：整个分类不显示。
    f.go(m.Intent.searchFor("保活"));
    try std.testing.expect(!f.vm.pageShownInResults(5));
    try std.testing.expect(f.missing("settings.plugins"));
    try std.testing.expect(f.missing("settings.plugins.planned"));
    // 点命中的行：清空搜索，进入详情页。
    f.go(m.Intent.searchFor("probe"));
    try f.click("settings.plugin.probe.row");
    f.settle();
    try std.testing.expectEqualStrings("", f.controller.search_query);
    try std.testing.expectEqual(m.Location{ .page = 5, .sub = 1 }, f.controller.location());
    _ = try f.node("settings.plugin.probe.detail");
}

test "plugin settings yix: an empty registry says so; only roadmap entries are planned" {
    var f: Fixture = undefined;
    try f.init(.light);
    defer f.deinit();
    f.go(m.Intent.selectCategory(5));
    _ = try f.node("settings.plugin.ssh.row");
    // 旧的硬编码计划（FTP / FTPS、VNC、RDP、KVM）与预览状态已删除（PLUGIN_ARCH_PLAN 6.2.1 Q1）。
    for ([_][]const u8{ "FTP / FTPS", "VNC", "RDP", "未发布", "待定义" }) |old| try std.testing.expect(!hasText(f.root, old));
    try std.testing.expect(!f.controller.model.dirty);
    f.controller.plugin_page.refreshRegistry(.{ .published = .{ .entries = &.{}, .renderers = &.{} } }, 0);
    f.go(m.Intent.selectCategory(2));
    f.go(m.Intent.selectCategory(5));
    try std.testing.expect(shown(try f.node("settings.plugins.empty")));
    try std.testing.expect(f.missing("settings.plugins.builtin"));
    try std.testing.expect(shown(try f.node("settings.plugins.planned")));
}

// ── 随应用插件的启用开关（PLUGIN_ARCH_PLAN 6.2.1 Q5；Pencil XqqLV 稿 2） ──

const enablement = @import("../../../host/plugin_enablement.zig");
const linked_table = [_]enablement.Linked{
    .{ .id = "probe", .display_name = "Real registered probe", .plugin_version = "0.3.1" },
    .{ .id = "bmc_ikvm", .display_name = "BMC · iKVM", .summary = "远程画面、键鼠输入、电源与启动管理", .plugin_version = "0.3.2", .icons = .{ .settings = "monitor" } },
};
/// 本次启动的事实：注册表只剩 ssh / probe（bmc 被禁用、不在注册表里）。
const launched_entries = [_]registry.PluginManifest{ entries[0], entries[1] };

fn save(f: *Fixture) !void {
    try f.controller.save(std.testing.io, f.tmp.dir, &f.runtime);
    f.vm.dispatch(m.Intent.saveFinished(null));
    f.env.frames(2);
}

test "plugin settings yix Q5: bundled toggle walks enabled → draft → pending restart; builtins have no toggle" {
    var f: Fixture = undefined;
    try f.init(.light);
    defer f.deinit();
    const launch = enablement.Launch.init(&linked_table, .{ .preferences = &.{} });
    f.controller.plugin_page.setLaunch(&launch);
    // 内置插件：没有“状态”分组与开关（Q5a）。
    f.go(m.Intent.openAt(.{ .page = 5, .sub = 0 }));
    try std.testing.expect(f.missing("settings.plugin.ssh.enabled"));
    try std.testing.expect(f.missing("settings.plugin.ssh.status"));
    // 随应用提供：已启用（Jm2fZ），开关打开，说明如实写“禁用不是卸载”。
    f.go(m.Intent.openAt(.{ .page = 5, .sub = 1 }));
    try std.testing.expect(shown(try f.node("settings.plugin.probe.status")));
    try std.testing.expect((try f.node("settings.plugin.probe.enabled")).behavior.interaction.a11y.?.checked.?);
    try std.testing.expect(std.mem.indexOf(u8, try f.text("settings.plugin.probe.enabled.hint"), "插件代码仍随应用分发") != null);
    try std.testing.expect(f.missing("settings.plugin.probe.notice"));
    try std.testing.expect(f.missing("settings.plugin.probe.state"));
    // 拨动开关 → 改了未保存（SH1gb）：草稿写 host.enabled = "false"，保存栏出现。
    try f.click("settings.plugin.probe.enabled");
    f.env.frames(2);
    try std.testing.expectEqualStrings("false", f.controller.model.value.pluginPreference("probe", "host.enabled").?);
    try std.testing.expect(f.vm.footerVisible());
    try std.testing.expectEqual(enablement.Phase.draft, f.vm.pluginPhase(1));
    try std.testing.expect(f.missing("settings.plugin.probe.notice"));
    // 撤销：回到原值，没有残留条目。
    f.vm.dispatch(m.Intent.setPluginEnabled(1, true));
    f.env.frames(2);
    try std.testing.expect(f.controller.model.value.pluginPreference("probe", "host.enabled") == null);
    try std.testing.expect(!f.controller.model.dirty);
    // 再关、保存 → 待重启（NHr2L）：warning 标签“重启后停用”、提示与“立即重启”。
    f.vm.dispatch(m.Intent.setPluginEnabled(1, false));
    try save(&f);
    try std.testing.expectEqual(enablement.Phase.pending_disable, f.vm.pluginPhase(1));
    try std.testing.expect(shown(try f.node("settings.plugin.probe.notice")));
    try std.testing.expectEqualStrings("重启后停用", f.vm.pluginStateTag(1));
    try std.testing.expect(shown(try f.node("settings.plugin.probe.restart")));
    // 配置里只多了这一条。
    const written = try f.tmp.dir.readFileAlloc(std.testing.io, "config.toml", std.testing.allocator, .limited(1 << 20));
    defer std.testing.allocator.free(written);
    try std.testing.expect(std.mem.indexOf(u8, written, "key = \"host.enabled\"") != null or std.mem.indexOf(u8, written, "key=\"host.enabled\"") != null);
    // “立即重启”：交给宿主走正常退出流程。
    f.effects.clearRetainingCapacity();
    try f.click("settings.plugin.probe.restart");
    var restart = false;
    for (f.effects.items) |effect| restart = restart or effect == .restart_app;
    try std.testing.expect(restart);
    // 待重启时拨回并保存：回到原状态，不需要重启（条目被删除而不是写成 "true"）。
    f.vm.dispatch(m.Intent.setPluginEnabled(1, true));
    try save(&f);
    try std.testing.expectEqual(enablement.Phase.enabled, f.vm.pluginPhase(1));
    try std.testing.expect(f.controller.model.value.pluginPreference("probe", "host.enabled") == null);
    try std.testing.expect(f.missing("settings.plugin.probe.notice"));
}

test "plugin settings yix Q5: a disabled bundled plugin stays listed, dimmed, and its detail shows the disabled notice" {
    var f: Fixture = undefined;
    try f.init(.dark);
    defer f.deinit();
    const prefs = [_]@import("../../../config/config.zig").PluginPreference{.{ .plugin_id = "bmc_ikvm", .key = "host.enabled", .value = "false" }};
    const launch = enablement.Launch.init(&linked_table, .{ .preferences = &prefs });
    f.controller.plugin_page.refreshRegistry(.{ .published = .{ .entries = &launched_entries, .renderers = &.{} } }, 0);
    f.controller.plugin_page.setLaunch(&launch);
    // 已保存配置与本次启动一致：已禁用。
    try f.controller.setPluginEnabled("bmc_ikvm", false);
    try save(&f);
    f.go(m.Intent.selectCategory(5));
    _ = try f.node("settings.plugin.bmc_ikvm.row");
    try std.testing.expectEqualStrings("已禁用", f.vm.pluginStateTag(2));
    try std.testing.expect(shown(try f.node("settings.plugin.bmc_ikvm.disabled")));
    try std.testing.expect(f.missing("settings.plugin.bmc_ikvm.trail"));
    f.go(m.Intent.openAt(.{ .page = 5, .sub = 2 }));
    try std.testing.expect(shown(try f.node("settings.plugin.bmc_ikvm.disabled")));
    try std.testing.expect(!(try f.node("settings.plugin.bmc_ikvm.enabled")).behavior.interaction.a11y.?.checked.?);
    try std.testing.expect(f.missing("settings.plugin.bmc_ikvm.restart"));
    try std.testing.expectEqualStrings("BMC · iKVM 已禁用", f.vm.pluginDisabledTitle(2));
    // 重新打开并保存 → 待重启（重启后启用）。
    f.vm.dispatch(m.Intent.setPluginEnabled(2, true));
    try save(&f);
    try std.testing.expectEqual(enablement.Phase.pending_enable, f.vm.pluginPhase(2));
    try std.testing.expectEqualStrings("重启后启用", f.vm.pluginStateTag(2));
    try std.testing.expect(shown(try f.node("settings.plugin.bmc_ikvm.restart")));
}

test "plugin settings Q5: builtins cannot be disabled; a provider another enabled plugin depends on cannot be disabled" {
    var f: Fixture = undefined;
    try f.init(.light);
    defer f.deinit();
    const provider: enablement.Linked = .{ .id = "probe", .display_name = "Probe", .plugin_version = "1", .provides = &.{.{ .id = "probe.api" }} };
    const consumer: enablement.Linked = .{ .id = "bmc_ikvm", .display_name = "BMC · iKVM", .plugin_version = "1", .dependencies = &.{.{ .id = "probe.api" }} };
    const launch = enablement.Launch.init(&.{ provider, consumer }, .{ .preferences = &.{} });
    f.controller.plugin_page.setLaunch(&launch);
    try std.testing.expectError(error.PluginNotDisableable, f.controller.setPluginEnabled("ssh", false));
    try std.testing.expectError(error.PluginRequired, f.controller.setPluginEnabled("probe", false));
    try std.testing.expect(!f.controller.model.dirty);
    try f.controller.setPluginEnabled("bmc_ikvm", false);
    try f.controller.setPluginEnabled("probe", false);
}
