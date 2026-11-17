//! 主窗口组合根（原 mountUI）：把各 feature 宿主装进主窗口（P2 自 src/main.zig 原样拆出）。

const std = @import("std");
const applog = @import("../platform/applog.zig");
const ui = @import("ui");
const overlay = @import("../shared/ui/overlay/overlay_host.zig");
const ws = @import("../features/workspace/mod.zig").ws;
const wizard_mod = @import("../features/connections/mod.zig").wizard_mod;
const transfer_manager_view = @import("../features/transfer/mod.zig").transfer_manager_view;
const transfer_conflict_view = @import("../features/transfer/mod.zig").transfer_conflict_view;
const QuickConnect = @import("../features/connections/mod.zig").QuickConnect;
const RuntimeConfig = @import("../config/runtime_config.zig").RuntimeConfig;
const SettingsController = @import("../features/settings/mod.zig").SettingsController;
const DataPaths = @import("../config/paths.zig").Paths;
const AiController = @import("../ai/float_view.zig").Controller;
const AiManager = @import("../ai/turn_manager.zig").Manager;
const ai_provider = @import("../ai/provider.zig");
const AiClient = @import("../ai/provider_client.zig").Client;
const NativeContext = @import("../ai/provider_transport.zig").NativeContext;
const ai_provider_config = @import("../ai/provider_config.zig");
const Palette = ws.Palette;
const app_theme = @import("../shared/ui/theme/app_theme.zig");
const shell_styles = @import("../features/shell/mod.zig").shell_styles;
const session_menu_mod = @import("../features/workspace/mod.zig").session_menu_mod;
const application_host_mod = @import("../features/shell/mod.zig").application_host_mod;
const file_application_mod = @import("../features/files/mod.zig").file_application_mod;
const CollapsedSidebar = @import("../features/shell/mod.zig").CollapsedSidebar;
const HistoryHost = @import("../features/history/mod.zig").HistoryHost;
const MistChrome = @import("../features/workspace/mod.zig").MistChrome;
const Socks5Host = @import("../features/connections/mod.zig").Socks5Host;
const process_state = @import("process_state.zig");
const AiHost = @import("../features/ai/mod.zig").AiHost;
const AppNavHost = @import("../features/shell/mod.zig").AppNavHost;
const MenuHost = @import("../features/shell/mod.zig").MenuHost;
const NotificationWindowHook = @import("../features/notifications/mod.zig").NotificationWindowHook;
const NotificationHistoryView = @import("../features/notifications/mod.zig").NotificationHistoryView;
const QuickConnectHost = @import("../features/connections/mod.zig").QuickConnectHost;
const SettingsHost = @import("../features/settings/mod.zig").SettingsHost;
const TransferHost = @import("../features/transfer/mod.zig").TransferHost;
const WizardHost = @import("../features/connections/mod.zig").WizardHost;
const applyResolvedTerminalTypography = @import("../features/terminal/mod.zig").applyResolvedTerminalTypography;
const cleanupDataPaths = @import("startup.zig").cleanupDataPaths;
const cleanupRuntimeConfig = @import("startup.zig").cleanupRuntimeConfig;
const mountSidebar = @import("../features/shell/mod.zig").mountSidebar;
const mountStatusBar = @import("../features/shell/mod.zig").mountStatusBar;
const mountTitleBar = @import("../features/shell/mod.zig").mountTitleBar;
const terminalFamilyId = @import("../features/terminal/mod.zig").terminalFamilyId;

pub const PresentationWindow = struct {
    context: usize,
    target: @import("../platform/presentation_wakeup.zig").Target,
    fn cleanup(self: *@This(), allocator: std.mem.Allocator) void {
        @import("../platform/presentation_wakeup.zig").unregisterWindow(self.context, self.target);
        allocator.destroy(self);
    }
};

pub fn mountUI(cx: *ui.Cx, scope: *ui.Scope) anyerror!*ui.Node {
    const presentation_window = try scope.allocator.create(PresentationWindow);
    presentation_window.* = .{ .context = @intFromPtr(cx), .target = @import("../platform/presentation_wakeup.zig").registerWindow(@intFromPtr(cx)) };
    try scope.adoptResource(presentation_window, struct {
        fn destroy(raw: *anyopaque, allocator: std.mem.Allocator) void {
            const value: *PresentationWindow = @ptrCast(@alignCast(raw));
            value.cleanup(allocator);
        }
    }.destroy);
    const data_paths = try cx.allocator.create(DataPaths);
    data_paths.* = try DataPaths.forApplication(cx.allocator);
    try scope.onCleanup(DataPaths, data_paths, cleanupDataPaths);
    const config_path = data_paths.config;
    const hosts_path = data_paths.hosts;
    const app_config = if (process_state.process_windows) |process| blk: {
        if (process.runtime_config) |existing| break :blk existing;
        const runtime = try std.heap.c_allocator.create(RuntimeConfig);
        errdefer std.heap.c_allocator.destroy(runtime);
        runtime.* = try RuntimeConfig.loadOrDefault(cx.io, std.Io.Dir.cwd(), std.heap.c_allocator, config_path);
        process.runtime_config = runtime;
        break :blk runtime;
    } else blk: {
        const runtime = try cx.allocator.create(RuntimeConfig);
        runtime.* = try RuntimeConfig.loadOrDefault(cx.io, std.Io.Dir.cwd(), cx.allocator, config_path);
        try scope.onCleanup(RuntimeConfig, runtime, cleanupRuntimeConfig);
        break :blk runtime;
    };
    if (!@import("../platform/app_icon.zig").apply(app_config.value.ui.icon_background)) std.log.warn("Dock icon could not be applied", .{});
    @import("../platform/app_menu.zig").apply();
    if (process_state.process_notifications) |notifications| try notifications.updatePolicy(app_config.value.notify);
    app_theme.selectTokens(@import("../config/theme_registry.zig").builtinTokens(app_config.value.ui.theme));
    app_theme.publishSchemes(cx);
    cx.setTheme(app_theme.widgetTheme(app_theme.currentName()));
    const p = Palette.fromTheme();

    // ── Overlay panels (hidden by default) ──────────────────────────
    // AI Float（mockup-ai-float .af）：锚 pane 顶中央（top14 居中），600 宽
    // 浮窗。外层为全宽定位容器（display 切换目标），内层 .af 卡片承载视觉。
    const ai_panel = try ui.box(cx, .{
        .position = .absolute,
        .inset = .{ .top = .{ .px = 14 }, .left = .{ .px = 0 }, .right = .{ .px = 0 } },
        .z_index = 200,
        .width = .fill(),
        .direction = .row,
        .justify = .center,
        .align_items = .start,
    }, .{});
    ai_panel.setDisplay(.none);
    const ai_host = try cx.allocator.create(AiHost);
    // The assistant floats in the generic unified window chrome (shared/ui/float_card/float_chrome):
    // native floating Card, `ai.float.drag` grip, header (sparkles · AI 助手 · owner) and the actions
    // its card type declares (minimize = 收起, maximize, close = 结束当前 AI 会话); its own buttons
    // (子智能体 / 会话列表 / 新建) sit in the chrome's slot left of them.
    const ai_chrome = try @import("../shared/ui/float_card/float_chrome.zig").Chrome.mount(cx, scope, .{
        .title = "AI 助手",
        .icon = ui.icons.sparkles,
        .accent_icon = true,
        // Placement actions derive from the card type's placements (float-split / cards-float): AI never
        // opens as a tab (shown disabled with the reason) and may go into its tab's split.
        .descriptor = @import("../host/card_types.zig").floatDescriptor(&@import("../features/ai/mod.zig").chat_card_type).?,
        .ids = .{ .root = "ai.panel", .grip = "ai.float.drag", .grabber = "ai.float.grabber", .header = "ai.header", .subtitle = "ai.owner", .open_as_tab = "ai.open_as_tab", .open_as_tab_tooltip = "ai.open_as_tab.tooltip", .dock_to_split = "ai.dock_to_split", .dock_to_split_tooltip = "ai.dock_to_split.tooltip", .minimize = "ai.collapse", .maximize = "ai.maximize", .close = "ai.close", .minimize_tooltip = "ai.collapse.tooltip", .maximize_tooltip = "ai.maximize.tooltip", .close_tooltip = "ai.close.tooltip" },
        .labels = .{ .close = "结束当前 AI 会话" },
        .slot_buttons = &.{
            .{ .test_id = "ai.children", .tooltip_id = "ai.children.tooltip", .icon = ui.icons.get("bot").?, .label = "子智能体" },
            .{ .test_id = "ai.sessions", .tooltip_id = "ai.sessions.tooltip", .icon = ui.icons.get("messages-square").?, .label = "AI 会话列表" },
            .{ .test_id = "ai.session.new", .tooltip_id = "ai.session.new.tooltip", .icon = ui.icons.plus, .label = "新建 AI 会话" },
        },
    });
    ai_chrome.setSlotHandler(.{ .ctx = ai_host, .slot = AiHost.headerSlot });
    // The AI content (conversation, composer, header popovers) is a view the host mounts on demand
    // (`AiHost.mountContent`, LIFECYCLE.md §3); this window only builds the frame it is shown in.
    const ai_header = ai_chrome.header;
    const ai_prompt = try scope.createText("", .{});
    var native_context: ?*NativeContext = null;
    var native_client: ?*AiClient = null;
    var native_binding: ?*AiClient.Binding = null;
    var ai_native_io: ?*std.Io.Threaded = null;
    var ai_provider_instance: ai_provider.Provider = undefined;
    // Bootstrap the transport from saved settings. Sending validates the exact
    // current selection and credentials before any network request.
    const provider_config = ai_provider_config.fromSettings(app_config.value.ai) catch ai_provider_config.defaults(.openai_compat);
    {
        // Dedicated io instance for the AI worker thread: std.Io is not
        // thread-safe and the UI thread owns cx.io. The worker runs the
        // synchronous HTTP call on this private instance exclusively.
        const ai_io = try cx.allocator.create(std.Io.Threaded);
        ai_io.* = .init(std.heap.c_allocator, .{});
        ai_native_io = ai_io;
        const context = try cx.allocator.create(NativeContext);
        context.* = .{ .io = ai_io.io() };
        native_context = context;
        // The provider chain captures POINTERS: Binding.asProvider stores
        // ctx = *Binding and Binding holds client: *AiClient. These MUST
        // outlive mountUI's stack frame — as locals the worker thread
        // dereferenced dead stack memory after mountUI returned (SIGSEGV
        // in transport.request, and the pre-async "AI request failed"
        // ghost). Heap-allocate both; AiHost.cleanup frees them.
        const client_ptr = try cx.allocator.create(AiClient);
        client_ptr.* = AiClient.native(cx.allocator, context, switch (provider_config.kind) {
            .anthropic => .anthropic,
            else => .openai_compat,
        });
        native_client = client_ptr;
        const binding_ptr = try cx.allocator.create(AiClient.Binding);
        binding_ptr.* = .{ .client = client_ptr, .config = provider_config };
        native_binding = binding_ptr;
        ai_provider_instance = binding_ptr.asProvider();
    }
    const endpoint = provider_config.endpoint;
    const model = provider_config.model;
    ai_host.* = .{ .allocator = cx.allocator, .cx = cx, .scope = scope, .controller = AiController.init(cx.allocator), .manager = AiManager.init(cx.allocator), .stream_mailbox = @import("../ai/stream_mailbox.zig").Mailbox.init(cx.allocator), .step_mailbox = @import("../ai/step_events.zig").Mailbox.init(cx.allocator), .tool_bridge = @import("../features/ai/mod.zig").ai_tools.Bridge.init(std.heap.c_allocator), .execution_bridge = @import("../features/ai/mod.zig").ai_tools.Bridge.init(std.heap.c_allocator), .tool_results = @import("../ai/tool_results.zig").Store.init(cx.allocator), .provider = ai_provider_instance, .native_context = native_context, .native_client = native_client, .native_binding = native_binding, .endpoint = endpoint, .model = model, .panel = ai_panel, .prompt = ai_prompt };
    ai_host.data_root = data_paths.directory;
    ai_host.manager.observer = .{ .context = ai_host, .reset = AiHost.streamReset, .delta = AiHost.streamDelta, .tool_rejected = AiHost.streamToolRejected, .round_start = AiHost.streamRoundStart, .context_usage = AiHost.streamContextUsage, .input_consumed = AiHost.streamInputConsumed };
    ai_host.chrome = ai_chrome;
    // The host's publications wake this window (LIFECYCLE.md §5.1).
    try ai_host.bindWindowWake();

    const ai_close = ai_chrome.actionNode(.close) orelse return error.FloatChromeIncomplete;
    ai_host.close_confirmation_view = try @import("../features/ai/mod.zig").ai_close_confirmation_view.View.mount(cx, scope, ai_close, .{ .context = ai_host, .on_confirm = AiHost.confirmCloseWindow, .on_cancel = AiHost.cancelCloseWindow });
    try ai_header.appendChild(cx.allocator, ai_host.close_confirmation_view.?.root);
    ai_host.runtime_config = app_config;
    ai_host.card_box = ai_chrome.root;
    try scope.onCleanup(AiHost, ai_host, AiHost.cleanup);
    // Own the AI-threaded io AFTER the full struct literal above (the
    // literal resets every unlisted field, so assigning earlier leaked).
    if (ai_native_io) |io| ai_host.ai_io = io;
    // Result poller: consumes worker-thread completions on the UI thread
    // (self-scheduling only while a request is in flight). Registered
    // AFTER the AiHost cleanup entry: scope teardown is reverse-order, so
    // the poll hook is gone before the worker may be joined.
    try AiHost.PollHook.install(ai_host, scope);
    // The chrome's native floating Card paints the surface; only pointer / wheel isolation is added.
    @import("../shared/ui/components/floating_input/floating_input.zig").protect(cx, ai_chrome.root);
    try ai_panel.appendChild(cx.allocator, ai_chrome.root);

    // Preferences live in one process-wide native window (Island B v3 `p6ZVS`,
    // SettingsHost.mountWindow). This window keeps the settings services and a
    // hidden placeholder the host falls back to while no window is attached.
    const settings_panel = try ui.boxStyled(cx, shell_styles.settingsBackdrop, .{});
    settings_panel.meta.ownership.meta.test_id = "settings.overlay";
    settings_panel.setDisplay(.none);
    const settings_host = try cx.allocator.create(SettingsHost);
    settings_host.* = .{ .allocator = cx.allocator, .cx = cx, .scope = scope, .controller = try SettingsController.init(cx.allocator, app_config.value), .runtime = app_config, .io = cx.io, .panel = settings_panel };
    ai_host.settings_host = settings_host;
    try scope.onCleanup(SettingsHost, settings_host, SettingsHost.cleanup);
    settings_host.content = settings_panel;
    settings_host.main_cx = cx;
    settings_host.main_scope = scope;
    settings_host.placeholder_panel = settings_panel;
    try settings_host.initAppearance();

    const menu_host = try cx.allocator.create(MenuHost);
    menu_host.* = .{ .allocator = cx.allocator, .cx = cx };
    try scope.onCleanup(MenuHost, menu_host, MenuHost.cleanup);

    menu_host.settings = settings_host;

    // ── Root shell ──────────────────────────────────────────────────
    const root = try ui.boxStyled(cx, shell_styles.root, .{});
    root.meta.ownership.meta.test_id = "workspace.shell";
    // App.runWith already provides cx.root and its popover portal. Keep that
    // runtime-owned root: replacing it bypasses viewport layout constraints.

    const status_text = try ui.text(cx, "未连接", .{ .font_size = 11, .color = p.fg_secondary });

    const main_row = try ui.boxStyled(cx, shell_styles.body, .{});
    main_row.meta.ownership.meta.test_id = "workspace.body";

    // Workspace owns host data, sidebar rows, tab strip nodes and sessions.
    const sidebar_list = try ui.box(cx, .{ .width = .fill(), .direction = .column }, .{});
    const tab_strip = try ui.box(cx, .{ .direction = .row, .align_items = .center, .gap = 6 }, .{});
    const content_stack = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .min_width = 0, .min_height = 0, .direction = .column }, .{});
    const history_card_host = try ui.box(cx, .{ .width = .fill(), .direction = .column, .flex_shrink = 0 }, .{});
    history_card_host.meta.ownership.meta.test_id = "workspace.history.slot";
    history_card_host.setDisplay(.none);
    try content_stack.appendChild(cx.allocator, history_card_host);
    const terminal_area = try ui.boxStyled(cx, shell_styles.pane, .{});
    terminal_area.meta.ownership.meta.test_id = "workspace.pane";
    terminal_area.style.flex_shrink = 1;
    try content_stack.appendChild(cx.allocator, terminal_area);
    // Empty workspace keeps the Local / saved-connection entry points.
    // The pane owns its background so this child cannot cover its rounded corners.
    const empty_state = try ui.box(cx, .{
        .width = .fill(),
        .height = .fill(),
        .direction = .column,
        .align_items = .center,
        .justify = .center,
        .gap = 0,
    }, .{});
    const empty_guide = try ui.boxStyled(cx, shell_styles.emptyGuide, .{});
    empty_guide.meta.ownership.meta.test_id = "workspace.empty";
    const empty_icon_box = try ui.boxStyled(cx, shell_styles.emptyIcon, .{});
    empty_icon_box.meta.ownership.meta.test_id = "workspace.empty.icon";
    const empty_icon = try ui.box(cx, .{ .width = .{ .px = 88 }, .height = .{ .px = 88 }, .flex_shrink = 0 }, .{});
    try empty_icon_box.appendChild(cx.allocator, empty_icon);
    try empty_guide.appendChild(cx.allocator, empty_icon_box);
    const empty_copy = try ui.boxStyled(cx, shell_styles.emptyCopy, .{});
    try empty_guide.appendChild(cx.allocator, empty_copy);
    const empty_title = try ui.textStyled(cx, shell_styles.emptyTitle, "打开终端，开始工作");
    empty_title.style.height = .{ .px = 24 };
    empty_title.style.flex_shrink = 0;
    try empty_copy.appendChild(cx.allocator, empty_title);
    const empty_description = try ui.textStyled(cx, shell_styles.emptyDescription, "直接打开本地终端，或从左侧选择已保存的 SSH / SFTP 主机。");
    empty_description.style.height = .{ .px = 20 };
    empty_description.style.flex_shrink = 0;
    try empty_copy.appendChild(cx.allocator, empty_description);
    const empty_btns = try ui.boxStyled(cx, shell_styles.emptyActions, .{});
    // Native md Buttons (Pencil hmCmB: primary RtNVt / secondary E9luVp), zenit default look.
    const empty_local = try ui.widgets.Button(.{ .label = "本地终端", .icon_asset = ui.icons.square_terminal, .variant = .primary }).mount(scope, cx);
    empty_local.meta.ownership.meta.test_id = "workspace.empty.local";
    try empty_btns.appendChild(cx.allocator, empty_local);
    const empty_choose_label = try scope.createText("快速连接", .{});
    const empty_choose_icon = try scope.createSignal(?ui.SvgAsset, @import("../features/connections/mod.zig").quick_connect_icon.asset);
    const empty_choose = try ui.widgets.Button(.{ .label = empty_choose_label, .icon_asset = empty_choose_icon, .variant = .secondary }).mount(scope, cx);
    empty_choose.meta.ownership.meta.test_id = "workspace.empty.choose";
    try empty_btns.appendChild(cx.allocator, empty_choose);
    try empty_guide.appendChild(cx.allocator, empty_btns);
    try empty_state.appendChild(cx.allocator, empty_guide);
    try terminal_area.appendChild(cx.allocator, empty_state);

    const workspace = try ws.Workspace.init(
        cx.allocator,
        cx,
        scope,
        cx.io,
        &app_config.value,
        hosts_path,
        sidebar_list,
        tab_strip,
        terminal_area,
        empty_state,
    );
    // Pencil hmCmB: saved connections under the empty-state actions.
    try workspace.mountSavedConnections(empty_guide);
    workspace.history_card_host = history_card_host;
    // Tab-body flights draw in the shell, under the AI launcher and the floating layer (genie-static).
    workspace.flight_layer_parent = root;
    workspace.status_node = status_text;
    settings_host.workspace = workspace;
    workspace.font_family_resolver = terminalFamilyId;
    workspace.terminal_typography_resolver = applyResolvedTerminalTypography;
    ai_host.workspace = workspace;
    workspace.error_hint_handler = .{ .context = ai_host, .on_open = AiHost.openCommandError, .on_notice = AiHost.archiveCommandError };
    workspace.setTerminalTakeoverHandler(.{ .context = ai_host, .request = AiHost.takeoverTerminal });
    menu_host.workspace = workspace;
    _ = try @import("../features/workspace/mod.zig").session_export_jobs.Manager.mount(cx, scope, .{
        .context = workspace,
        .publish = struct {
            fn publish(raw: *anyopaque, message: []const u8) void {
                const target: *ws.Workspace = @ptrCast(@alignCast(raw));
                target.status(message);
            }
        }.publish,
    });
    menu_host.ai = ai_host;
    // Wizard is mounted below; MenuHost receives the live pointers after
    // WizardHost initialization so edit actions can reuse the same draft UI.

    // Wire the menu seam: sidebar/tab triggers flow Workspace → MenuHost.
    workspace.menu_bridge = .{ .context = @ptrCast(menu_host), .fire = MenuHost.bridgeFire, .host_action = MenuHost.sidebarAction };
    applog.info(.ui, "workspace ready: hosts={d} ui={s}x{s}", .{ workspace.registry.hosts.len, "1280", "800" });

    const quick_host = try cx.allocator.create(QuickConnectHost);
    quick_host.* = .{ .allocator = cx.allocator, .cx = cx, .workspace = workspace };
    try scope.onCleanup(QuickConnectHost, quick_host, QuickConnectHost.cleanup);
    quick_host.view = try @import("../features/connections/mod.zig").quick_connect_view.View.mount(cx, scope, .{ .context = quick_host, .saved = QuickConnectHost.saved, .local = QuickConnectHost.local, .temporary = QuickConnectHost.temporary, .new_profile = QuickConnectHost.newProfile, .closed = QuickConnectHost.closed });
    const quick_panel = quick_host.view.root;
    try quick_host.refreshAssets();

    const nav_host = try cx.allocator.create(AppNavHost);
    nav_host.* = .{ .allocator = cx.allocator, .cx = cx, .quick = QuickConnect.init(cx.allocator), .quick_panel = quick_panel, .settings = settings_host, .ai = ai_host, .roster = @import("../features/workspace/mod.zig").group_model.Roster.init(cx.allocator), .overlay = overlay.OverlayHost.init(cx.allocator) };
    // 浮层的唯一入口（OverlayHost）：窗口级规则（输入框 Esc 回到聚焦时的值）在这里装一次。
    overlay.install(cx);
    try nav_host.overlay.addLayer(.{ .ctx = settings_host, .is_open = SettingsHost.materialPreviewOpen, .close = SettingsHost.endMaterialPreview });
    if (app_config.value.ui.sidebar_width) |width| {
        const available = if (cx.viewport.width > 0) @min(480, @max(220, cx.viewport.width - 480)) else 480;
        nav_host.quick.sidebar.expanded_width = @min(width, available);
        nav_host.quick.sidebar.initial_width_pending = false;
    }
    nav_host.appearance_theme = try cx.bindState(shell_styles.ThemePublication, .{});
    nav_host.empty_choose_label = empty_choose_label;
    nav_host.empty_choose_icon = empty_choose_icon;
    nav_host.chrome.empty_icon = empty_icon;
    nav_host.chrome.empty_title = empty_title;
    nav_host.chrome.empty_description = empty_description;
    ai_host.roster = &nav_host.roster;
    quick_host.nav = nav_host;
    nav_host.quick_host = quick_host;
    empty_choose.behavior.events.on_click = cx.on(AppNavHost, nav_host, AppNavHost.homeConnect);
    empty_local.behavior.events.on_click = cx.on(AppNavHost, nav_host, AppNavHost.newLocalSessionClick);
    nav_host.workspace = workspace;
    nav_host.bindGroupWorkspace(workspace);
    settings_host.preview_viewport = terminal_area;
    ai_host.content_env.preview_content = terminal_area;
    const background_view = try @import("../features/shell/mod.zig").background_layers.View.mount(cx, scope);
    nav_host.background_view = background_view;
    if (cx.root) |window_root| try window_root.insertChildBefore(cx.allocator, background_view.root, if (window_root.children.items.len != 0) window_root.children.items[0] else null);

    settings_host.native_close_waiter = &nav_host.native_close_pending;
    // “新建 KVM”只在 bmc_ikvm 注册时出现：随应用插件被禁用（Q5）时它的创建入口随注册表一起消失。
    const kvm_registered = if (process_state.process_windows) |process| process.domain.sessions.registry.find("bmc_ikvm") != null else true;
    const session_menu = try session_menu_mod.View.mount(cx, scope, .{ .context = nav_host, .new_profile = AppNavHost.newSessionProfile, .new_sftp = AppNavHost.newSftpProfile, .new_kvm = if (kvm_registered) AppNavHost.newKvmProfile else null, .quick = AppNavHost.quickSession, .local = AppNavHost.newLocalSession, .saved = AppNavHost.savedSession });
    nav_host.session_menu = session_menu;
    try root.appendChild(cx.allocator, session_menu.root);
    nav_host.local_close_view = try @import("../features/terminal/mod.zig").local_close_view.View.mount(cx, scope, .{ .context = nav_host, .resolve = AppNavHost.resolveLocalClose });
    workspace.close_bridge = .{ .context = @ptrCast(nav_host), .risk = AppNavHost.closeRisk, .impact = AppNavHost.closeImpact, .cleanup = AppNavHost.cleanupSession, .confirm = AppNavHost.showLocalClose };
    const file_application = try file_application_mod.Host.create(cx.allocator, workspace);
    const application_host = (if (process_state.process_windows) |process|
        application_host_mod.ApplicationHost.initInDomain(process.domain, workspace, file_application.plugin())
    else
        application_host_mod.ApplicationHost.initWithFilePlugin(cx.allocator, workspace, file_application.plugin())) catch |err| {
        _ = file_application.shutdownStep();
        file_application.deinit() catch {};
        return err;
    };
    file_application.bind(application_host) catch |err| {
        file_application.abortInitialization();
        application_host.deinit();
        if (file_application.released) file_application.deinit() catch {};
        return err;
    };
    nav_host.file_application = file_application;
    nav_host.application_host = application_host;
    settings_host.application_host = application_host;
    ai_host.application_host = application_host;
    nav_host.roster.shared_identity = &application_host.domain.group_identity;
    if (ai_host.shared()) |_| {} else |err| workspace.statusFailure(@errorName(err));
    ai_host.file_application = file_application;
    application_host.install();
    application_host.setCloseExtension(nav_host, AppNavHost.closeStep);
    settings_host.controller.plugin_page.refreshRegistry(application_host.registry(), workspace.app_config.config_revision);
    settings_host.controller.plugin_page.setLaunch(application_host.pluginLaunch());
    workspace.command_bridge = .{ .context = @ptrCast(nav_host), .on_command = AppNavHost.onLocalCommand, .on_command_from = AppNavHost.onLocalCommandFrom, .parameter_candidates = AppNavHost.builtinParameterCandidates };
    workspace.input_bridge = .{ .context = @ptrCast(nav_host), .on_input = AppNavHost.onTerminalInput, .on_service_input = AppNavHost.onServiceBroadcast, .paste_stamp = AppNavHost.broadcastPasteStamp };
    for (workspace.tabs.items) |tab| if (tab.terminal) |*terminal| {
        terminal.input_observer = .{ .context = @ptrCast(nav_host), .on_input = AppNavHost.onTerminalInput, .on_service_input = AppNavHost.onServiceBroadcast, .paste_stamp = AppNavHost.broadcastPasteStamp };
    };
    root.behavior.events.event_context = @ptrCast(nav_host);
    // Capture once at the runtime root. A second capture on this subtree
    // processes .handled again (e.g. cancel editor then close settings).
    // With no focused control, Zenit sends keys to the runtime root. Route
    // application shortcuts there as well as through the business subtree.
    if (cx.root) |app_root| {
        app_root.behavior.events.capture_context = @ptrCast(nav_host);
        app_root.behavior.events.on_event_capture = AppNavHost.onEvent;
    }
    try scope.onCleanup(AppNavHost, nav_host, AppNavHost.cleanup);

    const sidebar = try mountSidebar(cx, scope, p, workspace, nav_host);
    nav_host.sidebar_panel = sidebar;
    try main_row.appendChild(cx.allocator, sidebar);
    // Keep the 8pt hit target while cancelling the extra flex gap it introduces.
    const sidebar_grip = try ui.box(cx, .{ .width = .{ .px = 8 }, .height = .fill(), .margin = .{ .left = -shell_styles.gap, .right = -8 }, .flex_shrink = 0, .cursor = .ew_resize, .hit_behavior = .@"opaque" }, .{});
    sidebar_grip.meta.ownership.meta.test_id = "sidebar.resize";
    _ = try ui.interaction.drag.Binding.attach(scope, cx, sidebar_grip, .{ .axis = .horizontal, .activation_distance = @import("../shared/ui/interaction.zig").resize_drag_activation, .active_cursor = .ew_resize }, AppNavHost.resizeSidebar, nav_host);
    nav_host.sidebar_grip = sidebar_grip;
    try main_row.appendChild(cx.allocator, sidebar_grip);
    const collapsed_sidebar = try CollapsedSidebar.mount(cx, scope, workspace, .{
        .context = @ptrCast(nav_host),
        .search = AppNavHost.collapsedSearch,
        .new_host = AppNavHost.collapsedNew,
        .expand = AppNavHost.collapsedExpand,
        .host_action = AppNavHost.collapsedHostAction,
    });
    nav_host.collapsed_sidebar = collapsed_sidebar;
    nav_host.initSidebarMemory(data_paths.directory, app_config.value.ui.sidebar_collapsed);

    try main_row.appendChild(cx.allocator, content_stack);
    // `@help` 没有终端输出目标时的命令帮助卡（B4）：原生 `W.Modal`（`features/terminal/view/command_help.yix`），
    // 显隐是 `nav_host.help_open`；Modal 挂到窗口浮层根，这里只留一个不占位的挂载点。
    const help_open = try scope.createSignal(bool, false);
    const command_help = @import("../features/terminal/mod.zig").command_help_view;
    try terminal_area.appendChild(cx.allocator, try ui.view.render(scope, cx, command_help.CommandHelp(.{ .open = help_open })));
    nav_host.help_open = help_open;
    // 终端右键菜单（design-r3 B1）：原生 `W.Menu`（`features/terminal/view/terminal_context_menu.yix`），在指针处弹出。
    try menu_host.mountMenus(scope, terminal_area);
    try root.appendChild(cx.allocator, main_row);

    try root.insertChildBefore(cx.allocator, settings_panel, main_row);
    ai_host.launcher = try @import("../features/ai/mod.zig").ai_launcher_view.View.mount(cx, scope, cx.on(AiHost, ai_host, AiHost.openFromLauncher), cx.on(AiHost, ai_host, AiHost.dragLauncher));
    ai_host.loadLauncherCorner();
    try root.appendChild(cx.allocator, ai_host.launcher.?.ring);
    try root.appendChild(cx.allocator, ai_host.launcher.?.root);
    // PLUGIN_ARCH_PLAN 2.5.7: one floating card layer per window; the AI chat card is its first card.
    const float_layer = try @import("../shared/ui/float_card/float_layer.zig").FloatLayer.mount(cx, scope, root);
    nav_host.float_layer = float_layer;
    float_layer.setModeSource(.{ .ctx = nav_host, .read = AppNavHost.floatCardMode });
    // 会话记录卡片 `history`（PL4b）：窗口级宿主持有记录目录，卡片浮在同一浮动层上，或作为独立 tab。
    const history_host = try HistoryHost.mount(cx, scope, data_paths.directory, workspace, float_layer);
    ai_host.recording_archive = history_host.archive;
    menu_host.history_host = history_host;
    // cards-float：会话卡片（终端 / 文件 / KVM / 通用会话）可以浮动，同一浮动层、统一外框。
    _ = try @import("../features/workspace/mod.zig").SessionFloatHost.mount(cx, scope, workspace, float_layer);
    // float-split：测试卡片 `fixture.float`（允许浮动与分屏）只在 test-mode 构建里装配，e2e 用它走“放入分屏 ⇄ 浮动”。
    if (comptime @import("application_options").test_mode) _ = try @import("../features/workspace/mod.zig").FloatFixtureHost.mount(cx, scope, workspace, float_layer);
    const title_bar = try mountTitleBar(cx, scope, p, settings_host, workspace, nav_host, history_host);
    try content_stack.insertChildBefore(cx.allocator, title_bar, history_card_host);
    try root.appendChild(cx.allocator, ai_panel);
    // 浮动声明来自已发布的 `ai.chat` 卡片类型（PL4a：Descriptor 并入卡片类型注册表）。
    const ai_chat_card = workspace.plugins.cardType(@import("../host/card_types.zig").ids.ai_chat) orelse return error.UnregisteredCardType;
    ai_host.card = try float_layer.attach(scope, .{
        .node = ai_panel,
        .chrome = ai_chrome,
        .descriptor = @import("../host/card_types.zig").floatDescriptor(ai_chat_card).?,
        .placement = &ai_host.controller.model.placement,
        .callbacks = .{ .ctx = ai_host, .close = AiHost.closeFloatCard, .action = AiHost.headerAction },
        .grip_test_id = "ai.float.drag",
        .handle_test_ids = .{ "ai.float.resize.n", "ai.float.resize.s", "ai.float.resize.w", "ai.float.resize.e", "ai.float.resize.nw", "ai.float.resize.ne", "ai.float.resize.sw", "ai.float.resize.se" },
    });
    ai_host.motion_probe = try @import("../features/ai/mod.zig").ai_panel_motion_view.View.mount(cx, scope);
    try root.appendChild(cx.allocator, ai_host.motion_probe.?.root);
    try root.insertChildBefore(cx.allocator, quick_panel, main_row);

    const status_bar = try mountStatusBar(cx, scope, p, status_text, nav_host.title_tools);
    try background_view.bindIsland(scope, terminal_area, (try workspace.tabStrip()).activeSurface());
    // The workspace owns the split's membership and focus; the canvas layer paints the plates.
    background_view.bindGroup(.{ .ctx = workspace, .members = struct {
        fn list(raw: *anyopaque, out: *std.ArrayList(@import("../features/shell/mod.zig").background_layers.GroupMember), allocator: std.mem.Allocator) anyerror!void {
            const owner: *ws.Workspace = @ptrCast(@alignCast(raw));
            var shown: std.ArrayList(ws.Workspace.ShownGroupPane) = .empty;
            defer shown.deinit(allocator);
            try owner.shownGroupPanes(&shown, allocator);
            for (shown.items) |pane| try out.append(allocator, .{ .node = pane.node, .focused = pane.focused });
        }
    }.list });
    // The workspace routes live grid dimensions into this label.
    workspace.grid_node = status_bar.grid;
    nav_host.session_details = status_bar.details;
    nav_host.socks_chip = status_bar.socks_chip;
    nav_host.status_bar = status_bar.bar;
    if (nav_host.mist == null) try status_bar.bar.insertChildBefore(cx.allocator, collapsed_sidebar.root, if (status_bar.bar.children.items.len != 0) status_bar.bar.children.items[0] else null);
    MistChrome.retainLegacy(cx, status_bar.bar);
    // Island B v3: session status is the focused island's pane header row.
    try terminal_area.insertChildBefore(cx.allocator, status_bar.bar, if (terminal_area.children.items.len != 0) terminal_area.children.items[0] else null);
    // 主题入口只有 设置 › 外观 与菜单栏“显示 › 外观…”；@theme 打开同一页（copy-terms）。
    menu_host.session_identity_context = nav_host;
    menu_host.session_identity = AppNavHost.showIdentityForTab;
    const local_status = try @import("../features/terminal/mod.zig").local_status_view.View.mount(cx, scope, .{ .context = nav_host, .detail = AppNavHost.showLocalStatusDetail });
    local_status.root.setDisplay(.none);
    MistChrome.retainLegacy(cx, local_status.root);
    nav_host.local_status_view = local_status;
    // Local sessions swap in their own status row: also the island's pane header.
    try terminal_area.insertChildBefore(cx.allocator, local_status.root, if (terminal_area.children.items.len > 1) terminal_area.children.items[1] else null);
    const command_history = try @import("../features/terminal/mod.zig").command_history_view.View.mountWith(cx, scope, workspace, status_bar.bar, local_status.root, if (nav_host.title_tools) |tools| .{ .button = tools.node(.command_history), .unavailable = tools.disabledSignal(.command_history) } else null);
    command_history.workspace_chrome = true;
    nav_host.command_history = command_history;
    menu_host.command_history = command_history;
    const status_detail = try @import("../features/shell/mod.zig").status_detail_view.View.mount(cx, scope, .{ .context = nav_host });
    nav_host.status_detail_view = status_detail;
    try root.appendChild(cx.allocator, status_detail.root);

    // ── 统一传输呈现：进程任务域 + 面板 + 进度行 ──────────
    const transfer_host = try cx.allocator.create(TransferHost);
    const tasks = application_host.domain.tasks orelse return error.TaskDomainUnavailable;
    transfer_host.* = .{
        .allocator = tasks.allocator,
        .cx = cx,
        .workspace = workspace,
        .panel = undefined,
        .tasks = tasks,
        .dispatch = &tasks.dispatch,
        .application = application_host,
        .files = file_application,
        .settings = settings_host,
        .manager = &tasks.manager,
        .retained_store = &tasks.retained_store,
    };
    try scope.onCleanup(TransferHost, transfer_host, TransferHost.cleanup);
    const tp_root = try transfer_host.panel_mounted(cx, scope);
    try root.appendChild(cx.allocator, tp_root);
    transfer_host.progress_slot = status_bar.progress_slot;
    const ticker = try @import("../features/shell/mod.zig").status_transfer_view.View.mount(cx, scope, cx.on(TransferHost, transfer_host, TransferHost.toggleManager));
    transfer_host.status_transfer = ticker;
    transfer_host.toolbar_progress = nav_host.mist_transfer;
    try status_bar.progress_slot.appendChild(cx.allocator, ticker.root);
    nav_host.transfer_host = transfer_host;
    menu_host.transfer_host = transfer_host;
    file_application.setTransferHandler(.{ .context = transfer_host, .submit = TransferHost.showFileTransfer, .confirm = TransferHost.confirmFileTransfer, .export_start = TransferHost.exportFileTransfer, .export_poll = TransferHost.pollFileExport, .export_cancel = TransferHost.cancelFileExport });
    const download_list = try transfer_manager_view.mountGlobalPopover(cx, scope, transfer_host.manager, .{ .context = transfer_host, .action = TransferHost.managerAction, .owner = TransferHost.jobOwner, .owner_label = TransferHost.jobOwnerLabel, .scope_choices = TransferHost.transferScopeChoices, .can_reveal = TransferHost.canReveal });
    transfer_host.manager_panel = download_list;
    download_list.hooks.closed = TransferHost.managerClosed;
    const conflict_dialog = try transfer_conflict_view.View.mount(cx, scope, .{ .context = transfer_host, .decision = TransferHost.conflictDecision, .defer_conflict = TransferHost.deferConflict });
    try root.appendChild(cx.allocator, conflict_dialog.root);
    transfer_host.conflict_view = conflict_dialog;
    if (nav_host.transfer_anchor) |anchor| download_list.setAnchor(anchor);
    try root.appendChild(cx.allocator, download_list.mountNode());
    try cx.addAfterLayoutHook(transfer_host, TransferHost.hookRun);

    var bell_history: ?*NotificationHistoryView = null;
    if (process_state.process_notifications) |notifications| {
        const notification_hook = try NotificationWindowHook.mount(cx, scope, notifications, workspace, settings_host, nav_host, transfer_host);
        settings_host.notification_window = notification_hook.id;
        bell_history = notification_hook.history_view;
        ai_host.notification_window = notification_hook.id;
        transfer_host.notification_window = notification_hook.id;
        workspace.setNotificationAttentionBridge(.{ .context = notification_hook, .has_dot = NotificationWindowHook.hasDot });
    }

    // ── SOCKS5 动态转发：chip 开关 + 独立连接 ────────────────────────
    const socks_host = try cx.allocator.create(Socks5Host);
    socks_host.* = try Socks5Host.init(cx.allocator, cx, workspace, application_host, data_paths.known_hosts);
    socks_host.bindAuthentication();
    socks_host.chip_label = status_bar.socks_label;
    socks_host.chip = status_bar.socks_chip;
    const socks_info = try @import("../features/connections/mod.zig").socks_info_view.mount(cx, scope, .{ .context = @ptrCast(socks_host), .action = Socks5Host.infoAction });
    socks_host.info = socks_info;
    if (!socks_info.portaled) try root.appendChild(cx.allocator, socks_info.wrapper);
    const socks_config = try @import("../features/connections/mod.zig").socks_config_view.View.mount(cx, scope, .{
        .context = @ptrCast(socks_host),
        .save = Socks5Host.saveConfig,
        .test_cb = Socks5Host.testConfig,
        .cancel = Socks5Host.cancelConfig,
        .confirm_exposure = Socks5Host.confirmExposure,
    });
    socks_host.config = socks_config;
    if (!socks_config.portaled) try root.appendChild(cx.allocator, socks_config.root);
    const exposure = try @import("../features/connections/mod.zig").socks_exposure_confirm.View.mount(cx, scope, .{ .context = @ptrCast(socks_host), .confirm = Socks5Host.exposureConfirmed, .cancel = Socks5Host.exposureCancelled });
    socks_host.exposure = exposure;
    if (!exposure.portaled) try root.appendChild(cx.allocator, exposure.root);
    nav_host.socks_host = socks_host;
    status_bar.socks_chip.behavior.events.on_click = .{ .callback = onSocksChipClick, .context = @ptrCast(socks_host) };
    try scope.onCleanup(Socks5Host, socks_host, Socks5Host.cleanup);
    try cx.addAfterLayoutHook(socks_host, Socks5Host.hookRun);
    const background_socks = try @import("../features/connections/mod.zig").socks_background_host.Host.mount(cx, scope, workspace, application_host, socks_host.backend);
    menu_host.background_socks = background_socks;
    // 稿 5: the remote background-SOCKS entry sits after the connection group.
    if (nav_host.title_tools) |tools| {
        if (tools.extraSlot()) |slot| try slot.appendChild(cx.allocator, background_socks.view.remote_entry);
    } else try status_bar.bar.insertChildBefore(cx.allocator, background_socks.view.remote_entry, status_bar.controls.theme_button);
    try local_status.root.appendChild(cx.allocator, background_socks.view.local_entry);
    try root.appendChild(cx.allocator, background_socks.view.popover.wrapper);
    if (!background_socks.exposure.portaled) try root.appendChild(cx.allocator, background_socks.exposure.root);

    // 新建连接向导：bindState 存活至 Cx 销毁；on_result 由 WizardHost 处理
    // （.saved → Draft 深拷贝转 HostConfig 存盘 + 建连；.cancelled → 忽略）。
    const wiz = try cx.bindState(wizard_mod.Wizard, .{});
    const wiz_host = try cx.allocator.create(WizardHost);
    wiz_host.* = .{ .allocator = cx.allocator, .workspace = workspace, .wizard = wiz, .application_host = application_host, .cx_ptr = cx, .probe_controller = @import("../features/connections/mod.zig").wizard_probe.Controller.init(cx.allocator, &application_host.sessions.journal) };
    wiz.setRegistry(application_host.registry());
    wiz.plugin_launch = application_host.pluginLaunch();
    wiz.connection_configs = @import("../host/connection_config_resolver.zig").Resolver.init(&workspace.registry);
    wiz.credential_host = if (application_host.domain.editor_credentials) |*host| host else null;
    wiz.on_envelope = WizardHost.submitEnvelope;
    wiz.on_envelope_with_secret = WizardHost.submitEnvelopeWithSecret;
    wiz.envelope_context = wiz_host;
    wiz.on_editor_mounted = WizardHost.configureEditor;
    wiz.editor_mounted_context = wiz_host;
    // Island B v3: the connection editor is its own native window, mounted on
    // demand (shared/ui/window/aux_window.zig); the owner id is attached once this App exists.
    wiz.on_window_mounted = WizardHost.windowMounted;
    wiz.window_mounted_context = wiz_host;
    wiz.attachWindow(0);
    try wiz_host.refreshAssets();
    try scope.onCleanup(WizardHost, wiz_host, WizardHost.cleanup);
    try cx.addAfterLayoutHook(wiz_host, WizardHost.hookRun);
    nav_host.wizard = wiz;
    nav_host.wizard_host = wiz_host;
    nav_host.menu_host = menu_host;
    menu_host.wizard = wiz;
    menu_host.wizard_host = wiz_host;
    if (nav_host.chrome.sidebar_search_input) |input| menu_host.sidebar_search_value = input.value;
    nav_host.connection_host = try @import("../features/connections/mod.zig").connection_host.Host.mount(cx, scope, workspace, application_host);
    // The connection attempt card is pane content (i7VdGA), not floating chrome.
    nav_host.probe_connection_host = try @import("../features/connections/mod.zig").probe_connection_host.Host.mount(cx, scope, &wiz_host.probe_controller, wiz, root);
    wiz_host.probe_presentation = nav_host.probe_connection_host;
    menu_host.asset_action_view = try @import("../features/connections/mod.zig").asset_action_view.View.mount(cx, scope, .{ .context = menu_host, .submit = MenuHost.submitAssetAction, .anchor = MenuHost.assetActionAnchor, .completed = MenuHost.assetActionCompleted, .close = MenuHost.assetActionClosed, .view_group = MenuHost.viewAssetGroup, .view_sessions = MenuHost.viewAssetSessions });
    try menu_host.asset_action_theme.bind(cx, scope);
    const details_host = try @import("../features/connections/mod.zig").connection_details_host.Host.mount(cx, scope, workspace, application_host, status_bar.chain_trigger, status_bar.chain_icon, status_bar.chain_hover, status_bar.bar);
    details_host.bindEditor(wiz_host, WizardHost.openCapturedAsset);
    // ybb2B: a failed connection card edits its host through the same entry.
    nav_host.connection_host.?.bindEditor(wiz_host, WizardHost.openCapturedAsset);
    details_host.bindStatus(status_bar.controls, nav_host, AppNavHost.showGlobalTheme);
    nav_host.connection_details_host = details_host;
    // Pencil lBTBA: live SOCKS forward / group broadcast rows on the connection card.
    const status_extras = try scope.createState(@import("../features/shell/mod.zig").status_connection_extras.Provider, .{ .workspace = workspace, .application = application_host, .socks = socks_host });
    details_host.ssh_status.info.extras = status_extras.provider();
    menu_host.connection_details_host = details_host;
    if (nav_host.mist) |chrome| {
        const c = status_bar.controls;
        c.workspace_chrome = true;
        local_status.workspace_chrome = true;
        try chrome.identitiesAtTabs(c.identity_button, local_status.identity_button);
        // The session cards' anchor is the active tab's surface, handed over by the chrome that owns it.
        details_host.ssh_status.setSessionAnchor(.{ .context = chrome, .resolve = @TypeOf(chrome.*).resolveActiveTab });
        for ([_]*ui.Node{ c.identity_label, c.state_dot, c.rtt_label, c.file_icon, c.icons[0], c.icons[1], local_status.identity_label, local_status.state_dot, local_status.identity_icon, local_status.identity_chevron }) |node| node.setDisplay(.none);
        // 稿 5: chain / forward / broadcast / command history are the
        // title bar's native buttons already (title_tools.yix); nothing moves.
    }
    // 同级面板（标题栏工具、页签身份卡片）：点击语义与互斥归 OverlayHost（焦点、Esc、点外部归各面板的原生 Popover）。
    const status_previews = &nav_host.overlay.siblings;
    // title-click: nothing opens on hover. The identity regions over the active tab are geometry
    // only (anchors); their cards open from the tab menu's “会话连接” (MenuHost), click semantics.
    try status_previews.add(cx, scope, status_bar.controls.identity_button, details_host.ssh_status.info.open, cx.on(@import("../features/shell/mod.zig").status_connection_view.View, details_host.ssh_status.info, @import("../features/shell/mod.zig").status_connection_view.View.dismiss));
    try status_previews.add(cx, scope, status_bar.chain_trigger, details_host.view.open, cx.on(@import("../features/connections/mod.zig").connection_details_view.View, details_host.view, @import("../features/connections/mod.zig").connection_details_view.View.dismiss));
    try status_previews.add(cx, scope, status_bar.socks_chip, socks_info.open, cx.on(@import("../features/connections/mod.zig").socks_info_view.View, socks_info, @import("../features/connections/mod.zig").socks_info_view.View.hide));
    if (nav_host.title_tools) |tools| {
        try status_previews.add(cx, scope, tools.node(.transfers), download_list.popover_open.?, cx.on(TransferHost, transfer_host, TransferHost.closeManagerPopover));
        if (bell_history) |bell| try status_previews.add(cx, scope, tools.node(.notifications), bell.open, cx.on(NotificationHistoryView, bell, NotificationHistoryView.close));
        try status_previews.add(cx, scope, tools.node(.command_history), command_history.open, cx.on(@import("../features/terminal/mod.zig").command_history_view.View, command_history, @import("../features/terminal/mod.zig").command_history_view.View.hide));
    }
    try status_previews.add(cx, scope, local_status.identity_button, status_detail.open, cx.on(@import("../features/shell/mod.zig").status_detail_view.View, status_detail, @import("../features/shell/mod.zig").status_detail_view.View.dismiss));
    for ([_]*ui.Node{ background_socks.view.remote_entry, background_socks.view.local_entry }) |trigger| {
        try status_previews.add(cx, scope, trigger, background_socks.view.popover.open.?, background_socks.view.popover.close);
    }
    if (nav_host.mist) |chrome| try chrome.installFeedback(scope);
    nav_host.asset_group_host = try @import("../features/connections/mod.zig").asset_group_host.Host.mount(cx, scope, workspace, .{ .context = wiz_host, .open = WizardHost.openInAssetGroup });
    try cx.addAfterLayoutHook(nav_host, AppNavHost.hookRun);
    // The closed AI panel keeps only its empty frame in the layer; its content view is mounted when
    // the panel is shown (`AiHost.placeContent`) and released when it has closed (LIFECYCLE.md §3).
    // The settings placeholder is one hidden node.
    if (app_config.value.ui.materials.background.enabled) {
        const startup = try @import("../features/shell/mod.zig").startup_view.View.mount(cx, scope);
        try root.appendChild(cx.allocator, startup.root);
        nav_host.startup_view = startup;
    }
    return root;
}

pub fn onSocksChipClick(raw: *anyopaque) void {
    const host: *Socks5Host = @ptrCast(@alignCast(raw));
    host.showInfo();
}

