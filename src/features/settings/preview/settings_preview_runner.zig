//! 设置预览 runner（显式验收入口，不进默认安装，不是产品入口）。
//!
//! 布局只有一种（3f 删除了只挂旧内容区的 `--layout=content`；`--layout=window` 仍可写）：
//! - `--layout=window`（默认）：完整设置窗口（导航 + 页头 + 内容 + Save Bar），走与生产相同的
//!   `aux_window.Slot` → `MultiWindowApp.createWindowWith` 路径，960 × 780。`--multi` 再开一个占位主窗口
//!   作为 owner（两个窗口各有自己的 Cx / SignalOwner / root scope）。宿主见 `preview_host.zig`。
//!
//! 自检（`--self-check=v7|v11`）在 runner 进程内执行，逐行输出 `PASS|FAIL V-7 …` / `V-11 …`，
//! 结束时退出码非零表示有 FAIL。数据只用内存默认配置；不读写用户数据、不安装、不申请权限。
const std = @import("std");
const ui = @import("ui");
const zenit_app = @import("zenit_app");
const App = zenit_app.App;
const MultiWindowApp = zenit_app.MultiWindowApp;
const Controller = @import("../model/settings_controller.zig").Controller;
const m = @import("../model/view_model.zig");
const catalog = @import("../model/catalog.zig");
const theme = @import("../../../shared/ui/theme/app_theme.zig");
const preview_host = @import("preview_host.zig");
const Host = preview_host.Host;
const aux = preview_host.aux;
const checks = @import("self_checks.zig");

pub const Layout = enum { window };
pub const SelfCheck = enum { none, v7, v11 };

pub const Options = struct {
    layout: Layout = .window,
    selected_theme: theme.Name = .sauber,
    main_theme: ?theme.Name = null,
    page: ?u8 = null,
    sub: ?u8 = null,
    search: ?[]const u8 = null,
    multi: bool = false,
    self_check: SelfCheck = .none,
    plugin_fixture: bool = false,
};
var options: Options = .{};

const usage =
    \\settings-preview-runner [--layout=window] [--theme=sauber|dark|light]
    \\  window layout (default; full settings window through the aux-window path, 960x780):
    \\    --page=<0-8|appearance|keys|ssh|transfer|ai|plugins|notifications|data|updates>
    \\    --sub=<n>              subpage of --page (default: the category overview)
    \\    --search=<text>        start with a search query
    \\    --plugin-fixture       publish two metadata-only plugin manifests (no factory, no loading)
    \\    --multi                also open a placeholder main window that owns the settings window
    \\    --main-theme=<name>    theme selected while the placeholder main window mounts (with --multi)
    \\    --self-check=v7|v11    run the in-process checks, print PASS/FAIL lines and exit
    \\Read-only: in-memory default config; no install, permission, loading or config write.
    \\
;

fn parsePage(text: []const u8) !u8 {
    if (std.fmt.parseInt(u8, text, 10)) |index| {
        if (index >= catalog.categories.len) return error.InvalidPage;
        return index;
    } else |_| {}
    for (catalog.categories, 0..) |category, index| if (std.mem.eql(u8, category.slug, text)) return @intCast(index);
    return error.InvalidPage;
}

fn parse(init: std.process.Init) !?Options {
    var result: Options = .{};
    var args = init.minimal.args.iterate();
    _ = args.next();
    while (args.next()) |arg| {
        if (std.mem.startsWith(u8, arg, "--theme=")) {
            result.selected_theme = std.meta.stringToEnum(theme.Name, arg[8..]) orelse return error.InvalidTheme;
        } else if (std.mem.startsWith(u8, arg, "--main-theme=")) {
            result.main_theme = std.meta.stringToEnum(theme.Name, arg[13..]) orelse return error.InvalidTheme;
        } else if (std.mem.startsWith(u8, arg, "--layout=")) {
            result.layout = std.meta.stringToEnum(Layout, arg[9..]) orelse return error.InvalidLayout;
        } else if (std.mem.startsWith(u8, arg, "--page=")) {
            result.page = try parsePage(arg[7..]);
        } else if (std.mem.startsWith(u8, arg, "--sub=")) {
            result.sub = std.fmt.parseInt(u8, arg[6..], 10) catch return error.InvalidSubpage;
        } else if (std.mem.startsWith(u8, arg, "--search=")) {
            result.search = arg[9..];
        } else if (std.mem.eql(u8, arg, "--plugin-fixture")) {
            result.plugin_fixture = true;
        } else if (std.mem.eql(u8, arg, "--multi")) {
            result.multi = true;
        } else if (std.mem.startsWith(u8, arg, "--self-check=")) {
            result.self_check = std.meta.stringToEnum(SelfCheck, arg[13..]) orelse return error.InvalidSelfCheck;
        } else if (std.mem.eql(u8, arg, "--help")) {
            std.debug.print("{s}", .{usage});
            return null;
        } else return error.InvalidOption;
    }
    if (result.sub != null and result.page == null) return error.SubpageNeedsPage;
    if (result.self_check == .v7) result.multi = true;
    if (result.page) |page| if (result.sub) |sub| {
        if (sub >= catalog.categories[page].subpages.len) return error.InvalidSubpage;
    };
    return result;
}

pub fn main(init: std.process.Init) !void {
    options = (try parse(init)) orelse return;
    switch (options.layout) {
        .window => try runWindow(init),
    }
}

// ── window 布局 ──

/// 运行期上下文：MultiWindowApp + aux_window 运行时适配（对应 ProcessWindows.drainAux）。
pub const Runtime = struct {
    app: *MultiWindowApp,
    io: std.Io,
    host: *Host,
    poll: bool,
    main_id: ?u64 = null,
    counting: *checks.CountingAllocator,

    pub fn settingsApp(self: *Runtime) ?*App {
        const id = self.host.slot.window_id orelse return null;
        if (self.host.slot.phase != .open) return null;
        return self.app.window(id);
    }

    /// 与 `ProcessWindows.drainAux` 相同的窗口参数。
    pub fn drainAux(self: *Runtime) void {
        if (aux.runtime == null) aux.runtime = .{ .context = self, .activate = auxActivate, .close = auxClose };
        while (aux.takePending()) |slot| {
            const window: zenit_app.WindowConfig = .{ .width = slot.spec.width, .height = slot.spec.height, .min_width = slot.spec.min_width, .min_height = slot.spec.min_height, .title = slot.spec.title, .chrome = slot.spec.chrome, .titlebar_height = slot.spec.titlebar_height, .maximizable = slot.spec.maximizable, .restorable = false, .owner = slot.owner, .placement = .center_on_owner };
            const ground = theme.windowClearColor(slot.spec.ground);
            aux.beginMount(slot);
            const created = self.app.createWindowWith(.{
                .io = self.io,
                .window = window,
                .clear_color = .{ .r = ground.r, .g = ground.g, .b = ground.b, .a = ground.a },
                .on_close_request = auxCloseRequest,
                .frame_pacing = if (self.poll) .poll else .display_link,
                .idle_skip_frames = !self.poll,
            }, aux.mount);
            aux.endMount();
            const app = created catch |err| {
                std.log.err("settings preview window: {s}", .{@errorName(err)});
                slot.createFailed(err);
                continue;
            };
            app.win.setTrafficLightsLayout(slot.spec.traffic_light_x, slot.spec.traffic_light_y, slot.spec.traffic_light_diameter);
            slot.opened(app.windowId());
            _ = self.app.activateWindow(app.windowId());
        }
    }
    fn auxActivate(raw: *anyopaque, id: u64) bool {
        const self: *Runtime = @ptrCast(@alignCast(raw));
        return self.app.activateWindow(id);
    }
    fn auxClose(raw: *anyopaque, id: u64) bool {
        const self: *Runtime = @ptrCast(@alignCast(raw));
        return self.app.closeWindow(id);
    }
    fn auxCloseRequest(app: *App) bool {
        return aux.closeRequest(app.windowId());
    }

    /// 跑 n 个 tick（每个 tick 前在循环边界创建待开的 aux 窗口）。返回 false 表示应用已结束。
    pub fn ticks(self: *Runtime, n: usize) !bool {
        for (0..n) |_| {
            self.drainAux();
            if (!try self.app.tick()) return false;
        }
        return true;
    }
};

/// 占位主窗口（--multi）：没有设置宿主，只有自己的 scope 与 V-7 探针。
pub const MainWindow = struct {
    pub var probe: ?*checks.MainProbe = null;
    fn mount(cx: *ui.Cx, scope: *ui.Scope) anyerror!*ui.Node {
        if (options.main_theme) |name| theme.select(name);
        const name = theme.currentName();
        cx.setTheme(theme.widgetTheme(name));
        const root = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .direction = .column, .padding = ui.Padding.all(24), .gap = 8, .background = theme.current().app }, .{});
        try root.appendChild(cx.allocator, try ui.text(cx, "ZeroWork · 占位主窗口（设置预览 runner）", .{ .font_size = 15, .color = theme.current().fg_1 }));
        try root.appendChild(cx.allocator, try ui.text(cx, "设置窗口是本窗口的 aux 窗口（owner）。两个窗口各有自己的 Cx 与 scope。", .{ .font_size = 12, .color = theme.current().fg_2 }));
        probe = try checks.MainProbe.create(scope);
        return root;
    }
};

fn runWindow(init: std.process.Init) !void {
    // 自检用 DebugAllocator（退出时报告泄漏），外面包一层计数器（V-7 观察开关窗口前后的存活字节）。
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    var counting: checks.CountingAllocator = .{ .child = if (options.self_check != .none) debug_allocator.allocator() else std.heap.c_allocator };
    const allocator = counting.allocator();
    var leaked = false;
    defer if (options.self_check != .none) {
        leaked = debug_allocator.deinit() == .leak;
        checks.report(if (options.self_check == .v7) "V-7" else "V-11", !leaked, "DebugAllocator: 进程退出时无泄漏（全部窗口、宿主、Controller 释放后）", .{});
        checks.finish();
    };

    theme.select(options.selected_theme);
    var application = MultiWindowApp.init(allocator, .{ .pump_timeout_ms = 16 });
    defer application.deinit();
    defer aux.runtime = null;

    const host = try Host.create(allocator);
    defer host.destroy();
    var rt: Runtime = .{ .app = &application, .io = init.io, .host = host, .poll = options.self_check != .none, .counting = &counting };

    // 初始位置（窗口挂载前，view-model 未 attach 时也能 dispatch）。
    if (options.page) |page| {
        host.controller.drill_down = true;
        host.vm.dispatch(m.Intent.openAt(.{ .page = page, .sub = options.sub }));
    }
    if (options.plugin_fixture) host.controller.plugin_page.refreshRegistry(.{ .published = .{ .entries = &plugin_fixture, .renderers = &.{} } }, 0);
    host.controller.history.reset(host.controller.location());
    if (options.search) |query| host.vm.dispatch(m.Intent.searchFor(query));

    if (options.multi) {
        const main_app = try application.createWindowWith(.{
            .io = init.io,
            .window = .{ .width = 720, .height = 480, .title = "ZeroWork · 占位主窗口" },
            .frame_pacing = if (rt.poll) .poll else .display_link,
            .idle_skip_frames = !rt.poll,
        }, MainWindow.mount);
        rt.main_id = main_app.windowId();
        host.slot.owner = rt.main_id;
        // 主窗口挂载时可能选了另一个主题（--main-theme）；设置窗口按 --theme 打开。
        theme.select(options.selected_theme);
    }
    _ = host.slot.present();
    rt.drainAux();
    // Harness 绑定设置窗口（多窗口时 App.mount 最后挂载的窗口获得绑定，这里显式再绑一次）。
    if (rt.settingsApp()) |settings_app| settings_app.rebindTestHarness();

    switch (options.self_check) {
        .none => while (try rt.ticks(1)) {},
        .v7 => try checks.runV7(&rt),
        .v11 => try checks.runV11(&rt),
    }
}

/// `--plugin-fixture`：只有元数据的插件清单（没有 session_factory / 编辑器 / 服务），让协议插件页非空。
/// 生产的注册表由 `application_host.registry()` 从 src/plugins 组装，runner 不能跨 feature 引用它。
const PluginManifest = @import("../../../host/plugin_registry.zig").PluginManifest;
const plugin_fixture = [_]PluginManifest{
    .{ .id = "preview.fixture.alpha", .display_name = "预览夹具 · 终端", .origin = .builtin, .workspace_kind = "terminal", .content_renderer = "terminal", .settings_section = .{ .fields = &.{.{ .key = "show_banner", .label = "显示欢迎横幅", .kind = .boolean, .default_value = "true" }} } },
    .{ .id = "preview.fixture.beta", .display_name = "预览夹具 · 内容页", .workspace_kind = "content", .content_renderer = "content" },
};
