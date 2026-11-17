//! 进程启动：数据目录、字体、MultiWindowApp 主循环（P2 自 src/main.zig 原样拆出；src/main.zig 只剩入口转发）。

const std = @import("std");
const applog = @import("../platform/applog.zig");
const application_test_mode = @import("application_options").test_mode;
const App = @import("zenit_app").App;
const MultiWindowApp = @import("zenit_app").MultiWindowApp;
const FontRegistry = @import("zenit_app").FontRegistry;
const DataPaths = @import("../config/paths.zig").Paths;
const shell_styles = @import("../features/shell/mod.zig").shell_styles;
const application_host_mod = @import("../features/shell/mod.zig").application_host_mod;
const NotificationHost = @import("../host/notification_host.zig").Host;
const process_state = @import("process_state.zig");
const AppNavHost = @import("../features/shell/mod.zig").AppNavHost;
const ProcessWindows = @import("process_windows.zig").ProcessWindows;
const dataStartupAlert = @import("startup.zig").dataStartupAlert;
const installMonospaceFonts = @import("fonts.zig").installMonospaceFonts;
const mountUI = @import("main_window.zig").mountUI;
const verifyUiFontPaths = @import("fonts.zig").verifyUiFontPaths;
const RuntimeConfig = @import("../config/runtime_config.zig").RuntimeConfig;
const app_theme = @import("../shared/ui/theme/app_theme.zig");
const window_ground = @import("window_ground.zig");
const wallClockMsTransfer = @import("../features/transfer/mod.zig").wallClockMsTransfer;

pub fn main() !void {
    // Test builds refuse to start without a private HOME (never the account's).
    try @import("../platform/user_dirs.zig").requireIsolatedStartup();
    @import("../vt/input_timing.zig").configure();
    @import("../vt/output_timing.zig").configure();
    try @import("../platform/ui_fonts.zig").register();
    const presentation = @import("../platform/presentation_wakeup.zig");
    presentation.wake_fn = struct {
        fn wake() void {
            @FieldType(App, "win").postEmptyEvent();
        }
    }.wake;

    var data_paths = try DataPaths.forApplication(std.heap.c_allocator);
    defer data_paths.deinit();
    const update_data = try std.heap.c_allocator.dupeSentinel(u8, data_paths.directory, 0);
    defer std.heap.c_allocator.free(update_data);
    if (@import("../update/client.zig").zw_update_startup_gate(update_data.ptr) == 0) return;
    var scope_lock = @import("../platform/data_scope_lock.zig").Lock.acquire(std.heap.c_allocator, data_paths.directory, data_paths.is_override) catch |err| {
        _ = dataStartupAlert(err, false);
        return err;
    };
    defer scope_lock.release();
    var io_threaded: std.Io.Threaded = .init(std.heap.c_allocator, .{});
    defer io_threaded.deinit();
    const lifecycle = @import("../config/data_lifecycle.zig");
    const credentials = @import("../config/credential_store.zig");
    try credentials.configureScope(data_paths.directory, data_paths.is_override);
    // test-mode：凭据只存进本实例私有数据目录里的文件，不碰真实钥匙串（明文 api_key 迁移时原先会卡在
    // 原生钥匙串授权上，应用启动即挂起）。
    if (comptime application_test_mode) {
        const test_credentials = try @import("../config/test_mode_credentials.zig").FileBackend.init(io_threaded.io(), std.heap.c_allocator, data_paths.directory);
        credentials.useTestModeBackend(test_credentials.backend());
    }
    _ = lifecycle.prepare(io_threaded.io(), &data_paths) catch |err| {
        if (err == error.ResetIncomplete and dataStartupAlert(err, true)) {
            credentials.eraseScope() catch |failure| {
                _ = dataStartupAlert(failure, false);
                return failure;
            };
            const report = try lifecycle.eraseOwned(io_threaded.io(), &data_paths);
            for (report.items[0..report.count]) |item| if (item.failure) |failure| {
                _ = dataStartupAlert(failure, false);
                return failure;
            };
            return;
        }
        if (err != error.ResetIncomplete) _ = dataStartupAlert(err, false);
        return err;
    };
    @import("../config/store.zig").prepareCredentials(io_threaded.io(), std.Io.Dir.cwd(), std.heap.c_allocator, data_paths.config, data_paths.hosts) catch |err| {
        if ((err == error.CredentialDenied or err == error.CredentialLocked) and dataStartupAlert(err, false)) {
            credentials.authorizeScope() catch |failure| {
                // Do not offer another authorization loop after cancel/denial.
                _ = dataStartupAlert(error.CredentialAuthorizationFailed, false);
                return failure;
            };
            @import("../config/store.zig").prepareCredentials(io_threaded.io(), std.Io.Dir.cwd(), std.heap.c_allocator, data_paths.config, data_paths.hosts) catch |failure| {
                _ = dataStartupAlert(error.CredentialAuthorizationFailed, false);
                return failure;
            };
        } else {
            if (err != error.CredentialDenied and err != error.CredentialLocked) _ = dataStartupAlert(err, false);
            return err;
        }
    };
    applog.init(.{}, io_threaded.io());
    defer applog.shutdown();
    applog.info(.app, "ZeroWork starting", .{});
    const notifications = try NotificationHost.create(std.heap.c_allocator, .{});
    defer notifications.destroy();
    process_state.process_notifications = notifications;
    defer process_state.process_notifications = null;
    // Q5（PLUGIN_ARCH_PLAN 6.2.1）：构造插件 bundle 之前读出各随应用插件的 `host.enabled`；被禁用的不初始化、不注册。
    const Contributions = @import("../plugins/application_plugins.zig").Bundle(@import("application_options").plugin_fixture);
    const plugin_launch = readPluginLaunch(io_threaded.io(), data_paths.config, &Contributions.linked);
    var contributions = try Contributions.init(std.heap.c_allocator, io_threaded.io(), data_paths.directory, &plugin_launch);
    defer contributions.deinit() catch |err| applog.warn(.app, "plugin resources retained: {s}", .{@errorName(err)});
    const domain = try application_host_mod.Domain.initWithContributions(std.heap.c_allocator, true, contributions.manifests(), contributions.renderers());
    domain.plugin_launch = plugin_launch;
    domain.frame_budget = contributions.frameBudget();
    domain.editor_credentials = @import("../host/editor_credentials.zig").Host.init(std.heap.c_allocator, io_threaded.io(), &domain.plugin_security.secret_store);
    for (domain.sessions.registry.manifests()) |manifest| for (manifest.notifications) |definition| try notifications.registerDefinition(definition);
    const app_menu_model = @import("app_menu_model.zig");
    var windows = MultiWindowApp.init(std.heap.c_allocator, .{ .shared_gpu = true, .on_quit_request = ProcessWindows.onQuitRequest, .on_menu_command = app_menu_model.onMenuCommand });
    var process: ProcessWindows = .{ .runtime = &windows, .domain = domain, .io = io_threaded.io(), .data_paths = &data_paths };
    defer {
        domain.deinit();
        process.deinit();
    }
    process.font_system = try @FieldType(App, "font_manager").init(std.heap.c_allocator, io_threaded.io());
    process.font_system.?.setDefaultFamily("Inter Variable");
    process_state.process_windows = &process;
    defer process_state.process_windows = null;
    var registry = FontRegistry.init(std.heap.c_allocator);
    defer registry.deinit();
    defer {
        @import("../features/shell/mod.zig").plugin_window_host.Host.prepareShutdown(domain);
        windows.deinit();
    }
    // 首个窗口创建前先载入配置并选定主题：窗口的 clear color 与首帧前的 layer 背景
    // 要用主题底色，而不是 zenit 的框架默认白。mountUI 复用这份进程级配置，不重复加载。
    if (process.runtime_config == null) {
        const runtime = try std.heap.c_allocator.create(RuntimeConfig);
        errdefer std.heap.c_allocator.destroy(runtime);
        runtime.* = try RuntimeConfig.loadOrDefault(io_threaded.io(), std.Io.Dir.cwd(), std.heap.c_allocator, data_paths.config);
        process.runtime_config = runtime;
    }
    app_theme.selectTokens(@import("../config/theme_registry.zig").builtinTokens(process.runtime_config.?.value.ui.theme));
    // 主窗口地面角色是 `.shell`（外壳 ground = 主题 app 色）；clear 与首帧前 layer
    // 背景共用同一个取样值。
    const ground = window_ground.clear(.shell);
    const app = try windows.createWindow(.{
        .io = io_threaded.io(),
        .font = .{ .fallback_families = @import("../platform/ui_fonts.zig").families },
        .window = @import("process_windows.zig").main_window,
        .clear_color = ground,
        .on_close_request = AppNavHost.nativeWindowCloseRequest,
    });
    process.primary = app;
    app.win.setTrafficLightsLayout(shell_styles.traffic_light_x, shell_styles.traffic_light_y, shell_styles.traffic_light_diameter);
    installMonospaceFonts(app);
    registry.setFontSystem(&process.font_system.?);
    app.setFontRegistry(&registry);
    if (application_test_mode) try verifyUiFontPaths(app);
    process_state.app_font_registry = &registry;
    defer process_state.app_font_registry = null;
    try app.mount(mountUI);
    const nav: *AppNavHost = @ptrCast(@alignCast(app.cx.root.?.behavior.events.capture_context orelse return error.MissingApplicationController));
    nav.app_runtime = app;
    nav.rememberSidebar();
    try nav.loadEmptyLogo();
    if (nav.settings) |settings| settings.app_runtime = app;
    const plugin_window = @import("../features/shell/mod.zig").plugin_window_host.Host.mount(app, nav.application_host orelse return error.MissingApplicationController, process_state.process_notifications, if (nav.ai) |ai| ai.notification_window else null) catch |err| {
        applog.err(.app, "plugin window services initialization: {s}", .{@errorName(err)});
        return err;
    };
    if (nav.wizard) |wizard| {
        wizard.probe_host = plugin_window.probes.?;
        // The connection editor window is owned by (and closes with) this window.
        wizard.attachWindow(app.windowId());
    }
    if (nav.ai) |ai| ai.setContentApp(app);
    @import("../features/workspace/mod.zig").multiwindow_test_routes.install(domain, &windows);
    // 菜单栏由快捷键路由生成；设置里改了键位后在主循环里重建（`menu_sync.sync`）。
    var menu_sync: app_menu_model.Sync = .{};
    if (process.runtime_config) |runtime| menu_sync.sync(&windows, &runtime.value.keys);
    if (application_test_mode) @import("../features/workspace/mod.zig").multiwindow_test_routes.shortcuts_route = shortcutsRoute;
    if (application_test_mode) @import("../features/workspace/mod.zig").multiwindow_test_routes.quit_route = struct {
        fn quit() void {
            if (process_state.process_windows) |active| active.requestQuit();
        }
    }.quit;
    // e2e: ZEROWORK_E2E_DIALOG_DIR answers system file dialogs from a queue (test-mode builds only).
    if (comptime application_test_mode) @import("../platform/test_dialog_injection.zig").install();
    const menu_bar = @import("../platform/menu_bar.zig");
    if (!menu_bar.start()) applog.warn(.app, "menu bar initialization failed", .{});
    defer menu_bar.stop();
    menu_bar.setActionHandler(&process, ProcessWindows.menuBarAction);
    var badge_fingerprint: ?u64 = null;
    var badge_revision: ?u64 = null;
    var updater: @import("../features/update/mod.zig").app_host.Host(ProcessWindows) = .{ .process = &process };
    process.updater = &updater;
    if (application_test_mode) @import("../features/workspace/mod.zig").multiwindow_test_routes.update_route = struct {
        fn route(body: []const u8, buffer: []u8) ?[]const u8 {
            const active_process = process_state.process_windows orelse return null;
            return (active_process.updater orelse return null).testRoute(body, buffer);
        }
    }.route;
    defer updater.deinit();
    @import("../update/client.zig").zw_update_start(@intFromBool(process.runtime_config.?.value.updates.auto_check));
    var update_healthy_sent = false;
    // The callback has no Cx/window pointer and remains valid through worker cleanup.
    while (windows.shouldContinue()) {
        const menu_action = menu_bar.takeAction();
        if (menu_action == 2) {
            // Menu-bar Quit takes the same owner-confirmed path as Cmd+Q;
            // MultiWindowApp.quit() would tear windows down without cleanup.
            process.requestQuit();
            continue;
        }
        if (menu_action >= 3) _ = notifications.activateActivity(menu_action);
        if (process.runtime_config) |runtime| menu_sync.sync(&windows, &runtime.value.keys);
        // 显示 › 外观… (native main menu): Settings › 外观与主题 in the key window.
        if (@import("../platform/app_menu.zig").takeAppearanceRequest()) process.openAppearance();
        notifications.activity.setForeground(menu_bar.active());

        const global_changed = presentation.take();
        var changed = global_changed;
        for (windows.windows.items) |managed| {
            const window_changed = presentation.takeWindow(@intFromPtr(managed.app.cx));
            if (global_changed or window_changed) {
                managed.app.cx.requestRedraw();
                changed = true;
            }
        }
        // A native empty event interrupts a blocking tick; consume its publication
        // at this next loop boundary without another timed wait before painting.
        windows.config.pump_timeout_ms = if (changed) 0 else 16;
        if (!try windows.tick()) break;
        notifications.activity.setForeground(menu_bar.active());
        const maintenance_ran = notifications.maintain(wallClockMsTransfer()) catch |err| blk: {
            applog.warn(.app, "system notification maintenance: {s}", .{@errorName(err)});
            // Window facts still ran; a native receipt error must not prevent
            // the bounded menu metadata refresh below either.
            break :blk true;
        };
        // Activity revisions update immediately; title/icon/order changes use
        // the same bounded maintenance fallback. Do not allocate and project
        // all background rows on every native event-pump iteration.
        if (maintenance_ran or badge_revision == null or badge_revision.? != notifications.activity.revision) {
            badge_revision = notifications.activity.revision;
            var activity_rows = try notifications.activityRows(std.heap.c_allocator);
            defer activity_rows.deinit(std.heap.c_allocator);
            var menu_hash = std.hash.Wyhash.init(0);
            for (activity_rows.items) |row| {
                const item = row.presentation;
                std.hash.autoHash(&menu_hash, .{ row.token, row.window_id, item.tab_id, item.order, item.icon_id, item.icon_tint, item.icon_backdrop, item.icon_original, item.icon_bouncing, item.current });
                menu_hash.update(item.title);
                menu_hash.update(item.status);
            }
            const fingerprint = menu_hash.final();
            if (badge_fingerprint == null or badge_fingerprint.? != fingerprint) {
                badge_fingerprint = fingerprint;
                menu_bar.update(activity_rows.items.len);
                for (activity_rows.items) |row| {
                    menu_bar.addSession(row.token, row.presentation);
                    if (application_test_mode) std.debug.print("MENU_BAR_ROW {{\"token\":{d},\"window\":{d},\"tab\":{d},\"order\":{d},\"icon\":{d},\"tint\":{d},\"current\":{},\"title\":{f},\"status\":{f}}}\n", .{ row.token, row.window_id, @backingInt(row.presentation.tab_id), row.presentation.order, row.presentation.icon_id, row.presentation.icon_tint, row.presentation.current, std.json.fmt(row.presentation.title, .{}), std.json.fmt(row.presentation.status, .{}) });
                }
                menu_bar.finish();
                if (application_test_mode) std.debug.print("MENU_BAR_BADGE {{\"count\":{d},\"foreground\":{}}}\n", .{ activity_rows.items.len, menu_bar.active() });
            }
        }
        for (windows.windows.items) |managed| @import("../features/shell/mod.zig").plugin_window_host.Host.observePresentedFrame(managed.app);
        @import("../vt/input_timing.zig").frameReturned();
        if (process.data_cleanup_exit) break;
        if (process.data_cleanup_pending) {
            process.data_cleanup_pending = false;
            if (process.data_cleanup_owner) |owner| owner.performDataCleanup();
            if (process.data_cleanup_exit) break;
        }
        if (process.data_cleanup_owner == null and !@import("../update/admission.zig").blocked()) process.drain(&registry);
        if (!process.data_cleanup_exit) process.drainAux(&registry);
        @import("../update/client.zig").zw_update_set_automatic(@intFromBool(process.runtime_config.?.value.updates.auto_check));
        updater.tick() catch |err| {
            applog.warn(.app, "updater: {s}", .{@errorName(err)});
            updater.coordinator.cancel();
            @import("../update/admission.zig").set(false);
        };
        if (!update_healthy_sent) {
            @import("../update/client.zig").zw_update_healthy();
            update_healthy_sent = true;
        }
        if (updater.exit) break;
    }
    // “立即重启”（Q5）：只在正常退出（所有窗口都走完关闭流程）之后再启动；更新退出、清除数据退出不在此列。
    if (process.relaunch_requested and !updater.exit and !process.data_cleanup_exit and windows.windows.items.len == 0) @import("../platform/relaunch.zig").schedule(io_threaded.io(), std.heap.c_allocator, application_test_mode);
}

/// 启动前读启用状态（Q5 / Q5c）：只读、只解析，不碰钥匙串。对内置三项写的 `host.enabled` 不生效，逐条记警告（Q5a）。
fn readPluginLaunch(io: std.Io, config_path: []const u8, linked: []const @import("../host/plugin_enablement.zig").Linked) @import("../host/plugin_enablement.zig").Launch {
    const enablement = @import("../host/plugin_enablement.zig");
    var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena.deinit();
    const source = enablement.readSource(io, std.Io.Dir.cwd(), arena.allocator(), config_path);
    switch (source) {
        .unreadable => applog.warn(.app, "plugin enablement: configuration unreadable; bundled plugins are not loaded", .{}),
        .preferences => |preferences| for (preferences) |preference| {
            if (enablement.ignoredBuiltinEntry(preference, &.{ "local", "ssh", "sftp" })) applog.warn(.app, "plugin enablement: builtin plugin {s} cannot be disabled; host.enabled ignored", .{preference.plugin_id});
        },
    }
    const launch = enablement.Launch.init(linked, source);
    for (launch.linked(), launch.enabledFlags()) |entry, enabled| {
        if (!enabled) applog.info(.app, "plugin {s} disabled; not initialized or registered", .{entry.id});
        if (application_test_mode) std.debug.print("ZW_PLUGIN_LAUNCH {{\"id\":\"{s}\",\"enabled\":{},\"config_unreadable\":{}}}\n", .{ entry.id, enabled, launch.config_unreadable });
    }
    return launch;
}

/// Test harness only (`/zerowork/shortcuts`): the shortcut router's registry with the current hint of every
/// command (from the shared `[keys]`) and the menu bar menu that lists it, so e2e can compare Tooltip, menu
/// and the settings page against one source.
fn shortcutsRoute(buffer: []u8) ?[]const u8 {
    const router_mod = @import("../features/shell/mod.zig").shortcut_router;
    const process = process_state.process_windows orelse return null;
    const runtime = process.runtime_config orelse return null;
    const router: router_mod.Router = .{ .keys = &runtime.value.keys };
    var writer = std.Io.Writer.fixed(buffer);
    writer.writeAll("{\"ok\":true,\"commands\":[") catch return null;
    for (router_mod.entries, 0..) |item, index| {
        var menu: []const u8 = "";
        for (router_mod.menu_bar) |bar| for (bar.items) |entry| switch (entry) {
            .command => |command| if (command == item.command) {
                menu = bar.title;
            },
            else => {},
        };
        if (index != 0) writer.writeAll(",") catch return null;
        writer.print("{{\"id\":\"{s}\",\"kind\":\"{s}\",\"label\":", .{ @tagName(item.command), @tagName(item.kind) }) catch return null;
        std.json.Stringify.value(item.label, .{}, &writer) catch return null;
        writer.writeAll(",\"hint\":") catch return null;
        std.json.Stringify.value(router.hint(item.command), .{}, &writer) catch return null;
        writer.writeAll(",\"menu\":") catch return null;
        std.json.Stringify.value(menu, .{}, &writer) catch return null;
        writer.print(",\"menu_key\":{}}}", .{router_mod.menuChord(router, .{ .command = item.command }) != null and menu.len != 0}) catch return null;
    }
    writer.writeAll("]}") catch return null;
    return writer.buffered();
}
