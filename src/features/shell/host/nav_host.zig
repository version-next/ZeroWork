//! 主窗口导航宿主 AppNavHost 与导航点击上下文 NavClick（P2 自 src/main.zig 原样拆出）。

const std = @import("std");
const applog = @import("../../../platform/applog.zig");
const ui = @import("ui");
const overlay_host = @import("../../../shared/ui/overlay/overlay_host.zig");
const App = @import("zenit_app").App;
const ws = @import("../../workspace/view/workspace.zig");
const wizard_mod = @import("../../connections/wizard/view/wizard.zig");
const remote_editor = @import("../../../plugins/remote/editor_factory.zig");
const TerminalViewNode = @import("../../terminal/view/terminal_view.zig").TerminalViewNode;
const QuickConnect = @import("../../connections/quick_connect/model/quick_connect.zig").Model;
const app_theme = @import("../../../shared/ui/theme/app_theme.zig");
const shell_styles = @import("../view/shell_styles.zig");
const session_menu_mod = @import("../../workspace/view/session_menu.zig");
const application_host_mod = @import("application_host.zig");
const file_application_mod = @import("../../files/host/file_application_host.zig");
const CollapsedSidebar = @import("../view/sidebar_collapsed_view.zig").View;
const MistChrome = @import("../../workspace/view/workspace_chrome.zig");
const Socks5Host = @import("../../connections/socks/host/socks_application_host.zig").Host;
const process_state = @import("../../../app/process_state.zig");
const AiHost = @import("../../ai/host/ai_host.zig").AiHost;
const MenuHost = @import("menu_host.zig").MenuHost;
const ProcessWindows = @import("../../../app/process_windows.zig").ProcessWindows;
const QuickConnectHost = @import("../../connections/quick_connect/host/quick_connect_host.zig").QuickConnectHost;
const SettingsHost = @import("../../settings/host/settings_host.zig").SettingsHost;
const TransferHost = @import("../../transfer/host/transfer_host.zig").TransferHost;
const WizardHost = @import("../../connections/wizard/host/wizard_host.zig").WizardHost;
const applyCommandInfoSettings = @import("../../terminal/host/typography.zig").applyCommandInfoSettings;

pub const AppNavHost = struct {
    /// 窗口浮层的唯一入口（`shared/ui/overlay/overlay_host.zig`）：同级面板互斥、窗口级层的 Esc。
    overlay: overlay_host.OverlayHost,
    mist: ?*MistChrome.View = null,
    /// design-r3 稿 5 title bar tool group (native buttons; `title_tools.yix`).
    title_tools: ?*@import("../view/title_tools_view.zig").ViewModel = null,
    /// Pushed each frame by the window's notification hook (稿 5 tooltip / ⋯ dot).
    notification_pending: usize = 0,
    notification_unread: bool = false,
    mist_transfer: ?*@import("../../transfer/view/transfer_toolbar_view.zig").View = null,
    startup_view: ?*@import("../view/startup_view.zig").View = null,
    file_application: ?*file_application_mod.Host = null,
    allocator: std.mem.Allocator,
    cx: *ui.Cx,
    quick: QuickConnect,
    quick_panel: *ui.Node,
    quick_host: ?*QuickConnectHost = null,
    sidebar_panel: *ui.Node = undefined,
    /// The window's floating card layer (PLUGIN_ARCH_PLAN 2.5.7); the shell feeds it the region.
    float_layer: ?*@import("../../../shared/ui/float_card/float_layer.zig").FloatLayer = null,
    ai_float_rect: @import("../../../shared/base/float_card.zig").Rect = .{ .x = 0, .y = 0, .width = 0, .height = 0 },
    /// cards-float: the docked AI content height last used for its transcript viewport.
    ai_docked_height: f32 = 0,
    sidebar_grip: ?*ui.Node = null,
    sidebar_resizing: bool = false,
    sidebar_saved_width: f32 = @import("../model/sidebar_model.zig").default_width,
    sidebar_drag_width: f32 = @import("../model/sidebar_model.zig").default_width,
    sidebar_alignment_pending_before_drag: bool = true,
    /// Per-window sidebar memory and the one-time narrow-window hint (design-r3 C2).
    sidebar_memory: @import("sidebar_memory.zig").Memory = .{},
    sidebar_full: ?*ui.Node = null,
    sidebar_empty: ?*ui.Node = null,
    collapsed_sidebar: ?*CollapsedSidebar = null,
    settings: ?*SettingsHost = null,
    ai: ?*AiHost = null,
    command_history: ?*@import("../../terminal/view/command_history_view.zig").View = null,
    /// 页签菜单“会话连接”选中的页签（title-click）：激活它后，在下一帧打开它的会话连接卡片。
    identity_pending: ?@import("../../../host/identity.zig").TabId = null,
    quick_backdrop: ?*ui.Node = null,
    session_details: ?*ui.Node = null,
    socks_chip: ?*ui.Node = null,
    status_bar: ?*ui.Node = null,
    title_controls: ?*ui.Node = null,
    title_bar: ?*ui.Node = null,
    transfer_anchor: ?*ui.Node = null,
    notification_anchor: ?*ui.Node = null,
    /// 命令帮助卡（原生 `W.Modal`，`terminal/view/command_help.yix`）的显隐。
    help_open: ?*ui.Signal(bool) = null,
    last_width: f32 = 0,
    last_height: f32 = 0,
    window_focused: ?bool = null,
    workspace: ?*ws.Workspace = null,
    wizard: ?*wizard_mod.Wizard = null,
    wizard_host: ?*WizardHost = null,
    transfer_host: ?*TransferHost = null,
    connection_details_host: ?*@import("../../connections/progress/host/connection_details_host.zig").Host = null,
    asset_group_host: ?*@import("../../connections/assets/host/asset_group_host.zig").Host = null,
    menu_host: ?*MenuHost = null,
    roster: @import("../../workspace/model/group_model.zig").Roster = undefined,
    broadcasts: std.ArrayList(@import("../../workspace/model/broadcast_controller.zig").Approval) = .empty,
    broadcast_view: ?*@import("../../workspace/view/broadcast_view.zig").View = null,
    broadcast_epoch: u64 = 1,
    broadcast_view_fingerprint: ?u64 = null,
    socks_host: ?*Socks5Host = null,
    ime_composing: bool = false,
    app_runtime: ?*App = null,
    native_close_pending: bool = false,
    native_close_started: bool = false,
    application_host: ?*application_host_mod.ApplicationHost = null,
    connection_host: ?*@import("../../connections/progress/host/connection_host.zig").Host = null,
    probe_connection_host: ?*@import("../../connections/wizard/host/probe_connection_host.zig").Host = null,
    session_menu: ?*session_menu_mod.View = null,
    session_menu_anchor: ?*ui.Node = null,
    builtin_new_group: ?u32 = null,
    local_close_view: ?*@import("../../terminal/view/local_close_view.zig").View = null,
    pending_command_creations: std.ArrayList(struct { source: @import("../../../host/identity.zig").SessionHandle, command_id: u64, created: @import("../../../host/identity.zig").SessionHandle }) = .empty,
    local_drop: ?struct { tab: @import("../../../host/identity.zig").TabId, owner: @import("../../../host/identity.zig").SessionHandle, input_id: u64 } = null,

    local_status_view: ?*@import("../../terminal/view/local_status_view.zig").View = null,
    status_detail_view: ?*@import("../view/status_detail_view.zig").View = null,
    local_status_hash: ?u64 = null,
    local_status_revision: u64 = 0,
    background_view: ?*@import("../view/background_layers.zig").View = null,
    appearance_ui_hash: ?u64 = null,
    appearance_theme: *shell_styles.ThemePublication = undefined,
    empty_choose_label: ?*ui.Signal([]const u8) = null,
    empty_choose_icon: ?*ui.Signal(?ui.SvgAsset) = null,
    empty_has_hosts: ?bool = null,
    host_artwork: [@import("../../../shared/ui/assets/host_os_assets.zig").pixels.len]?u32 = @splat(null),
    tab_mask_artwork: [@import("../../../shared/ui/assets/host_os_assets.zig").pixels.len]?u32 = @splat(null),
    empty_logo_texture: ?u32 = null,
    ai_logo_texture: ?u32 = null,
    chrome: struct {
        toolbar_tint: ?*ui.Signal(?ui.Color) = null,
        transfer_badge: ?*ui.Node = null,
        empty_icon: ?*ui.Node = null,
        empty_title: ?*ui.Node = null,
        empty_description: ?*ui.Node = null,
        sidebar_title: ?*ui.Node = null,
        sidebar_search: ?*ui.Node = null,
        sidebar_search_icon: ?*ui.Node = null,
        sidebar_search_input: ?ui.widgets.input.InputResult = null,
        sidebar_footer: ?*ui.Node = null,
        sidebar_footer_label: ?*ui.Node = null,
        sidebar_empty_label: ?*ui.Node = null,
    } = .{},

    last_status_sample_ms: f64 = -1000,

    /// Window close button: ZeroWork keeps the window (and its sessions) alive
    /// and only hides it; Dock reopen shows it again. Real teardown happens
    /// through an application quit (`beginApplicationClose`).
    pub fn nativeWindowCloseRequest(app: *App) bool {
        const self = ProcessWindows.navFor(app) orelse return true;
        if (self.native_close_pending) return false;
        app.win.hide();
        return false;
    }

    /// Application quit for this window: run the owner-confirmed cleanup
    /// pipeline in `afterRender`; the window is closed through
    /// `MultiWindowApp.closeWindow` once every owned resource is released.
    pub fn beginApplicationClose(self: *AppNavHost) void {
        if (self.native_close_pending) return;
        if (@import("../../../update/admission.zig").blocked()) {
            if (process_state.process_windows) |process| {
                if (process.updater) |updater| updater.notifyCloseBlocked();
                process.cancelRelaunch();
            }
            return;
        }
        if (process_state.process_windows) |process| if (process.data_cleanup_owner != null) {
            process.data_cleanup_exit = true;
            return;
        };
        self.native_close_pending = true;
        self.native_close_started = false;
        if (self.transfer_host) |transfer| transfer.closeManagerPopover();
        if (self.settings) |settings| if (settings.open) settings.toggle();
        self.cx.requestRedraw();
    }

    /// Final step of the close pipeline: publish the close receipt, then hand
    /// the window to the runtime. Retried on the next frame if the receipt
    /// cannot be published yet.
    fn finishApplicationClose(self: *AppNavHost, app: *App) void {
        const host = self.application_host orelse return;
        host.completeWindowClose() catch |err| {
            applog.warn(.workspace, "window close completion: {s}", .{@errorName(err)});
            self.cx.scheduleRedrawAfterNs(33 * std.time.ns_per_ms);
            return;
        };
        const process = process_state.process_windows orelse return;
        _ = process.runtime.closeWindow(app.windowId());
    }

    pub fn showSessionMenu(self: *AppNavHost) void {
        if (self.session_menu) |menu| if (self.session_menu_anchor) |anchor| {
            if (menu.isOpen()) {
                menu.hide();
                self.builtin_new_group = null;
            } else {
                self.builtin_new_group = null;
                if (self.workspace) |workspace| {
                    var entries: std.ArrayList(session_menu_mod.Saved) = .empty;
                    defer entries.deinit(self.cx.allocator);
                    for (workspace.registry.hosts) |host| entries.append(self.cx.allocator, .{ .owner = host.owner(), .name = host.name, .icon = @import("../../../shared/ui/components/session_icon/session_icon.zig").forHost(workspace.plugins, host.protocolId(), @import("../../workspace/host/session_os_cache.zig").load(workspace.allocator, workspace.io, workspace.hosts_path, host)) }) catch return;
                    menu.setAll(entries.items) catch return;
                    var recent: std.ArrayList(session_menu_mod.Saved) = .empty;
                    defer recent.deinit(self.cx.allocator);
                    for (0..workspace.recent_connections.len) |rank| {
                        const owner = workspace.recent_connections.resolve(rank, &workspace.registry) orelse continue;
                        for (entries.items) |entry| if (entry.owner.id == owner.id) {
                            recent.append(self.cx.allocator, entry) catch return;
                            break;
                        };
                        if (recent.items.len == 3) break;
                    }
                    menu.setSaved(recent.items) catch return;
                }
                menu.show(anchor) catch |err| applog.warn(.workspace, "session menu: {s}", .{@errorName(err)});
            }
        };
    }

    pub fn savedSession(raw: *anyopaque, owner: @import("../../../host/identity.zig").AssetOwner) void {
        const self: *AppNavHost = @ptrCast(@alignCast(raw));
        const workspace = self.workspace orelse return;
        _ = workspace.registry.get(owner) catch |err| {
            workspace.statusFailure(@errorName(err));
            return;
        };
        const index = workspace.registry.indexOf(owner.id) orelse return;
        const group = self.builtin_new_group;
        self.builtin_new_group = null;
        if (group) |id| if (self.roster.findById(id) == null or workspace.groupTabId(id) == null) {
            workspace.statusFailure("原会话组已关闭，请重新选择主机");
            return;
        };
        const previous_group = workspace.creation_group;
        workspace.creation_group = group;
        defer workspace.creation_group = previous_group;
        workspace.newSession(index) catch |err| workspace.statusFailure(@errorName(err));
    }

    pub fn newSessionProfile(raw: *anyopaque) void {
        const self: *AppNavHost = @ptrCast(@alignCast(raw));
        if (self.wizard_host) |host| {
            if (host.raiseOpen()) return;
            host.selected_group = null;
            host.refreshAssets() catch return;
            remote_editor.loadDraft(host.wizard, .{}) catch return;
            host.wizard.show();
        }
    }

    pub fn newSftpProfile(raw: *anyopaque) void {
        const self: *AppNavHost = @ptrCast(@alignCast(raw));
        const host = self.wizard_host orelse return;
        if (host.raiseOpen()) return;
        host.selected_group = null;
        host.refreshAssets() catch return;
        remote_editor.loadDraft(host.wizard, .{ .protocol = .sftp, .port = 22 }) catch return;
        host.wizard.show();
    }
    pub fn newKvmProfile(raw: *anyopaque) void {
        const self: *AppNavHost = @ptrCast(@alignCast(raw));
        const host = self.wizard_host orelse return;
        if (host.raiseOpen()) return;
        host.selected_group = null;
        host.refreshAssets() catch return;
        host.wizard.selectContribution("bmc_ikvm") catch return;
        host.wizard.reset() catch return;
        host.wizard.show();
    }
    pub fn quickSession(raw: *anyopaque) void {
        const self: *AppNavHost = @ptrCast(@alignCast(raw));
        self.toggleQuickConnect();
    }

    pub fn newLocalSession(raw: *anyopaque) void {
        const self: *AppNavHost = @ptrCast(@alignCast(raw));
        const workspace = self.workspace orelse return;
        const group = self.builtin_new_group;
        self.builtin_new_group = null;
        if (group) |id| if (self.roster.findById(id) == null or workspace.groupTabId(id) == null) {
            workspace.statusFailure("原会话组已关闭，请重新选择主机");
            return;
        };
        const previous_group = workspace.creation_group;
        workspace.creation_group = group;
        defer workspace.creation_group = previous_group;
        workspace.newLocalSession(null) catch |err| {
            workspace.statusFailure(@errorName(err));
            applog.warn(.workspace, "local session: {s}", .{@errorName(err)});
        };
    }

    pub fn newLocalSessionClick(self: *AppNavHost) void {
        self.builtin_new_group = null;
        newLocalSession(self);
    }

    pub fn toggleSidebar(self: *AppNavHost) void {
        self.quick.toggleSidebar();
        self.sidebar_memory.changed(self.allocator, self.cx.io, self.quick.sidebar.collapsed);
        self.applySidebar();
        self.cx.requestRedraw();
    }

    /// Mount-time visibility of this window: its remembered state (main
    /// window) or the 「默认隐藏侧栏」 setting. Window width never changes it.
    pub fn restoreSidebar(self: *AppNavHost, collapsed: bool) void {
        self.quick.sidebar.restore(collapsed);
        self.applySidebar();
    }

    /// Mount: load the device memory from the private data directory and
    /// start from the 「默认隐藏侧栏」 setting.
    pub fn initSidebarMemory(self: *AppNavHost, data_directory: []const u8, default_collapsed: bool) void {
        self.sidebar_memory = @import("sidebar_memory.zig").Memory.init(self.allocator, self.cx.io, data_directory) catch |err| blk: {
            applog.warn(.ui, "sidebar memory: {s}", .{@errorName(err)});
            break :blk .{};
        };
        self.restoreSidebar(default_collapsed);
    }

    /// The main window remembers its own sidebar across restarts.
    pub fn rememberSidebar(self: *AppNavHost) void {
        self.sidebar_memory.remember = true;
        if (self.sidebar_memory.remembered()) |collapsed| self.restoreSidebar(collapsed);
    }

    /// 稿 5: per-frame facts for the title bar tools — which buttons exist,
    /// whether a transfer is running, state texts and unavailable reasons.
    /// The views only re-render on change (the view-model compares values).
    fn refreshTitleTools(self: *AppNavHost, forward_available: bool, terminal_active: bool) void {
        const tools = self.title_tools orelse return;
        const T = @import("../model/title_tools.zig");
        var facts = tools.currentFacts();
        const present = struct {
            fn of(node: *ui.Node) bool {
                return node.style.display != .none;
            }
        };
        facts.present[@intFromEnum(T.Tool.chain)] = present.of(tools.node(.chain));
        facts.present[@intFromEnum(T.Tool.forward)] = present.of(tools.node(.forward));
        facts.present[@intFromEnum(T.Tool.broadcast)] = present.of(tools.node(.broadcast));
        facts.present[@intFromEnum(T.Tool.command_history)] = present.of(tools.node(.command_history));
        if (self.mist_transfer) |view| {
            facts.transfers_active = view.phase != .idle;
            var buffer: [64]u8 = undefined;
            tools.setState(.transfers, view.stateText(&buffer), null);
            tools.setIcon(.transfers, view.iconName());
        }
        if (tools.setFacts(facts)) self.cx.requestRedraw();
        tools.setAvailable(.forward, forward_available, "当前页签不是 SSH 会话");
        tools.setAvailable(.command_history, terminal_active, "当前页签没有终端");
        if (self.connection_details_host) |host| if (host.ssh_status.controls) |controls| {
            const chain = if (controls.chain_button.behavior.interaction.a11y) |props| props.description orelse "" else "";
            tools.setState(.chain, chain, null);
            const forward = controls.forward_label.getText().?.content;
            tools.setState(.forward, if (std.mem.eql(u8, forward, "端口转发")) "" else forward, null);
            const running = if (controls.broadcast_button.behavior.interaction.a11y) |props| props.pressed else false;
            tools.setState(.broadcast, if (running) "已开启" else "已关闭", self.shortcuts().hint(.broadcast));
        };
        // 快捷键文字只从路由取（随 `[keys]` 变化；固定键被覆盖时为空）。
        tools.shortcuts = self.shortcuts();
        tools.setState(.command_history, "", self.shortcuts().hint(.command_history));
        tools.setState(.settings, "", self.shortcuts().hint(.open_settings));
        {
            const pending = self.notification_pending;
            tools.setState(.notifications, switch (@min(pending, 10)) {
                0 => "",
                1 => "1 条待处理",
                2 => "2 条待处理",
                3 => "3 条待处理",
                4 => "4 条待处理",
                5 => "5 条待处理",
                6 => "6 条待处理",
                7 => "7 条待处理",
                8 => "8 条待处理",
                9 => "9 条待处理",
                else => "9+ 条待处理",
            }, null);
            tools.setUnread(self.notification_unread);
        }
    }

    /// The float layer's mode source: `ui.float_card_transition`, read when each run starts (Z12b).
    pub fn floatCardMode(ctx: ?*anyopaque) @import("../../../shared/ui/styles/float_card_motion.zig").Mode {
        const self: *AppNavHost = @ptrCast(@alignCast(ctx orelse return .anchor));
        const config = @import("../../../config/config.zig");
        const mode = config.floatTransitionMode(if (self.settings) |settings| &settings.runtime.value else null);
        return switch (mode) {
            .anchor => .anchor,
            .fade => .fade,
        };
    }

    /// PLUGIN_ARCH_PLAN 2.5.7: window content minus the title bar and the expanded sidebar, inset 8;
    /// the status bar may be covered (Q20). Window content coordinates.
    pub fn floatRegion(self: *AppNavHost) @import("../../../shared/base/float_card.zig").Rect {
        const sidebar_right: f32 = if (self.quick.sidebar.collapsed or self.sidebar_panel.style.display == .none) 0 else blk: {
            const r = self.sidebar_panel.globalRect();
            break :blk r.x + r.w;
        };
        return @import("../../../shared/base/float_card.zig").floatRegion(self.cx.viewport.width, self.cx.viewport.height, shell_styles.outer + shell_styles.title_height, sidebar_right);
    }

    /// First narrow frame with the sidebar shown: one native info toast (bottom centre; `laneFor`: no actions, info).
    fn hintNarrowSidebar(self: *AppNavHost, workspace: *ws.Workspace) void {
        const memory = @import("sidebar_memory.zig");
        const content = workspace.terminal_area.globalRect().w;
        if (!self.sidebar_memory.wantsHint(self.allocator, self.cx.io, self.quick.sidebar.collapsed, content)) return;
        const toasts = @import("../../notifications/mod.zig").windowToasts(self.cx) orelse return;
        _ = toasts.tip(memory.hint_text, memory.hint_duration_ms) catch |err| {
            applog.warn(.ui, "narrow sidebar hint: {s}", .{@errorName(err)});
            return;
        };
        self.sidebar_memory.hinted(self.allocator, self.cx.io);
        self.cx.requestRedraw();
    }

    pub fn resizeSidebar(event: ui.interaction.drag.Event, raw: *anyopaque) void {
        const self: *AppNavHost = @ptrCast(@alignCast(raw));
        switch (event.phase) {
            .start => {
                self.sidebar_saved_width = self.quick.sidebar.expanded_width;
                self.sidebar_resizing = true;
                self.sidebar_drag_width = self.sidebar_panel.globalRect().w;
                self.sidebar_alignment_pending_before_drag = self.quick.sidebar.initial_width_pending;
                self.quick.sidebar.initial_width_pending = false;
            },
            .move, .end => {
                self.quick.sidebar.expanded_width = std.math.clamp(self.sidebar_drag_width + event.delta.x, 220, @min(480, @max(220, self.cx.viewport.width - 480)));
                if (event.phase == .end) if (self.settings) |settings| {
                    var candidate = settings.runtime.value;
                    candidate.ui.sidebar_width = self.quick.sidebar.expanded_width;
                    settings.runtime.save(self.cx.io, std.Io.Dir.cwd(), candidate) catch |err| {
                        std.log.err("failed to save sidebar width: {s}", .{@errorName(err)});
                        if (self.workspace) |workspace| workspace.statusFailure("侧栏宽度保存失败");
                    };
                };
            },
            .cancel => {
                self.quick.sidebar.expanded_width = self.sidebar_saved_width;
                self.quick.sidebar.initial_width_pending = self.sidebar_alignment_pending_before_drag;
            },
        }
        if (event.phase == .end or event.phase == .cancel) self.sidebar_resizing = false;
        self.applySidebar();
        self.cx.requestRedraw();
    }

    fn applySidebar(self: *AppNavHost) void {
        self.sidebar_panel.setDisplay(if (self.quick.sidebar.collapsed) .none else .flex);
        self.sidebar_panel.setStyle(self.allocator, .width, .{ .px = self.quick.sidebar.expanded_width });
        if (self.sidebar_grip) |grip| grip.setDisplay(if (self.quick.sidebar.collapsed) .none else .flex);
        if (self.collapsed_sidebar) |collapsed| collapsed.setCollapsed(self.quick.sidebar.collapsed);
    }

    pub fn homeConnect(self: *AppNavHost) void {
        if (self.workspace) |workspace| if (workspace.registry.hosts.len == 0) {
            if (self.wizard) |wizard| wizard.show();
            return;
        };
        self.toggleQuickConnect();
    }
    pub fn loadEmptyLogo(self: *AppNavHost) !void {
        const app = self.app_runtime orelse return;
        if (self.ai_logo_texture == null) {
            var mascot = try @import("../../../config/background_asset.zig").decode(self.allocator, @import("app_icon_assets").ai_assistant, .{});
            defer mascot.deinit(self.allocator);
            self.ai_logo_texture = try app.renderer.image_renderer.loadTexture(mascot.width, mascot.height, mascot.pixels);
            if (self.ai) |ai| ai.welcome_logo_texture = self.ai_logo_texture;
        }
        const node = self.chrome.empty_icon orelse return;
        if (self.empty_logo_texture != null) return;
        var image = try @import("../../../config/background_asset.zig").decode(self.allocator, @import("app_icon_assets").transparent, .{});
        defer image.deinit(self.allocator);
        const texture = try app.renderer.image_renderer.loadTexture(image.width, image.height, image.pixels);
        self.empty_logo_texture = texture;
        node.setImage(.{ .texture_id = texture });
        node.markRenderDirty();
        if (self.startup_view) |startup| startup.logo.setImage(.{ .texture_id = texture });
    }

    fn paintHostArtwork(self: *AppNavHost, node: *ui.Node) void {
        const app = self.app_runtime orelse return;
        const assets = @import("../../../shared/ui/assets/host_os_assets.zig");
        if (node.getImage()) |image| {
            const isoft = self.host_artwork[assets.index(assets.isoft.icon_id.?).?] == image.texture_id;
            self.paintArtworkBackdrop(node, if (isoft) ui.Color.WHITE else ui.Color.TRANSPARENT);
            if (!ui.Color.eql(image.tint, ui.Color.WHITE)) _ = node.setTint(ui.Color.WHITE);
            return;
        }
        const icon = node.getIcon() orelse return;
        self.paintArtworkBackdrop(node, @import("../../../shared/ui/components/session_icon/session_icon.zig").artworkBackdrop(icon.icon_id));
        const index = assets.index(icon.icon_id) orelse return;
        if (self.host_artwork[index] == null) self.host_artwork[index] = app.renderer.image_renderer.loadTexture(72, 72, assets.display_pixels[index]) catch return;
        node.setIcon(null);
        node.setImage(.{ .texture_id = self.host_artwork[index].?, .tint = ui.Color.WHITE });
        node.markRenderDirty();
    }
    fn syncHostArtwork(self: *AppNavHost) void {
        const workspace = self.workspace orelse return;
        for (workspace.host_rows.items) |row| self.paintHostArtwork(row.view.dot);
        for (workspace.tab_nodes.items) |tab| self.paintTabArtwork(tab.type_icon, tab.icon_asset, workspace.tabIconState(tab.tab_id));
    }

    fn paintTabArtwork(self: *AppNavHost, node: *ui.Node, asset: ui.SvgAsset, state: @import("../../../shared/ui/components/session_icon/session_icon.zig").TabState) void {
        const app = self.app_runtime orelse return;
        self.paintArtworkBackdrop(node, @import("../../../shared/ui/components/session_icon/session_icon.zig").artworkBackdrop(asset.icon_id.?));
        const assets = @import("../../../shared/ui/assets/host_os_assets.zig");
        const index = assets.index(asset.icon_id.?) orelse return;
        const texture = if (state == .normal) &self.host_artwork[index] else &self.tab_mask_artwork[index];
        if (texture.* == null) {
            var mask: [72 * 72 * 4]u8 = undefined;
            const pixels = if (state == .normal) assets.display_pixels[index] else blk: {
                for (0..72 * 72) |i| {
                    @memset(mask[i * 4 ..][0..3], 255);
                    mask[i * 4 + 3] = assets.status_pixels[index][i * 4 + 3];
                }
                break :blk &mask;
            };
            texture.* = app.renderer.image_renderer.loadTexture(72, 72, pixels) catch return;
        }
        const tint = @import("../../../shared/ui/components/session_icon/session_icon.zig").tabTint(state, asset);
        if (node.getImage()) |current| if (current.texture_id == texture.*.? and ui.Color.eql(current.tint, tint)) return;
        node.setIcon(null);
        node.setImage(.{ .texture_id = texture.*.?, .tint = tint });
        node.markRenderDirty();
    }
    fn paintArtworkBackdrop(self: *AppNavHost, node: *ui.Node, color: ui.Color) void {
        // iconTint retains its temporary vector geometry for hit testing. A
        // background would fill that path instead of the requested circle.
        if (color.a != 0) if (node.layoutOutput()) |output| if (output.vector.fill.path != null) {
            node.releasePathGeometry(self.allocator);
            node.setStyle(self.allocator, .hit_shape, .circle);
            node.markRenderDirty();
        };
        if (!ui.Color.eql(node.getBackground(), color)) node.setBackground(color);
        const shape: @TypeOf(node.style.shape()) = if (color.a == 0) .rounded_rect else .ellipse;
        if (node.style.shape() != shape) node.setStyleInline(self.allocator, .{ .shape = shape });
    }
    fn syncHomeConnect(self: *AppNavHost) void {
        const workspace = self.workspace orelse return;
        const has_hosts = workspace.registry.hosts.len > 0;
        if (self.empty_has_hosts == has_hosts) return;
        self.empty_has_hosts = has_hosts;
        if (self.empty_choose_label) |label| label.set(if (has_hosts) "快速连接" else "新建主机");
        if (self.empty_choose_icon) |icon| icon.set(if (has_hosts) @import("../../connections/quick_connect/model/quick_connect_icon.zig").asset else ui.icons.plus);
        if (self.chrome.empty_description) |node| node.setTextContent(self.allocator, if (has_hosts) "直接打开本地终端，或从左侧选择已保存的 SSH / SFTP 主机。" else "直接打开本地终端，或新建一个 SSH / SFTP 主机。") catch {};
    }
    fn toggleQuickConnect(self: *AppNavHost) void {
        const host = self.quick_host orelse return;
        if (host.view.isOpen()) host.close() else host.show() catch |err| {
            if (self.workspace) |workspace| workspace.statusFailure(@errorName(err));
        };
        self.cx.requestRedraw();
    }

    /// Tab menu “会话详情” (title-click): the session card opens on this click, never on hover. The
    /// card anchors on the identity region over the active tab (workspace chrome), so a menu opened on
    /// another tab first activates that tab; the card opens once the region has settled over it.
    pub fn showIdentityForTab(raw: *anyopaque, tab_index: usize) void {
        const self: *AppNavHost = @ptrCast(@alignCast(raw));
        const workspace = self.workspace orelse return;
        if (tab_index >= workspace.tabs.items.len) return;
        const tab = workspace.tabs.items[tab_index];
        if (tab.isCard()) return;
        self.identity_pending = tab.tab_id;
        if (workspace.active_tab != tab_index) workspace.activateTabId(tab.tab_id);
        self.cx.requestRedraw();
    }
    /// Runs after this pass's status projections (the SSH status host's hook runs before this one,
    /// the Local status is refreshed in hookRun just before), so the identity's click opens the card
    /// of the session the region now stands over. The request ends deterministically: it opens when
    /// the chrome reports the region settled over the tab, and is dropped when the tab is gone, is
    /// no longer the active tab, or settles with no region. While the chrome is settling it re-runs
    /// by itself (layout rounds, row mount, strip rebuild), so nothing here counts frames.
    fn openPendingIdentity(self: *AppNavHost) void {
        const id = self.identity_pending orelse return;
        const workspace = self.workspace orelse return;
        const chrome = self.mist orelse {
            self.identity_pending = null;
            return;
        };
        const index = workspace.tabIndexById(id) orelse {
            self.identity_pending = null;
            return;
        };
        // showIdentityForTab activated it synchronously; another active tab means the user moved on.
        if (workspace.active_tab != index) {
            self.identity_pending = null;
            return;
        }
        switch (chrome.identityRegion(id)) {
            .settling => {},
            .none => self.identity_pending = null,
            .shown => |node| {
                self.identity_pending = null;
                if (node.behavior.events.on_click) |click| click.invoke();
                self.cx.requestRedraw();
            },
        }
    }

    pub fn hookRun(ctx: *anyopaque, _: u8, _: bool) ui.AfterLayoutResult {
        const self: *AppNavHost = @ptrCast(@alignCast(ctx));
        if (self.menu_host) |menu| menu.drainSidebarAction();
        if (self.wizard_host) |host| if (self.workspace) |workspace| {
            if (remote_editor.editor(host.wizard)) |editor| editor.setScrollbackDefault(workspace.app_config.ui.scrollback_limit);
        };
        if (process_state.process_windows) |process| if (process.data_cleanup_owner != null) return .done;
        if (self.quick_host) |host| if (host.view.isOpen()) host.refreshAssets() catch |err| {
            if (self.workspace) |workspace| workspace.statusFailure(@errorName(err));
        };
        if (self.workspace) |workspace| {
            const menu_owner = if (self.menu_host) |menu| if (menu.state.open == .host_asset) menu.captured_asset else null else null;
            workspace.setSidebarMenuOwner(menu_owner);
        }
        if (self.menu_host) |menu| if (menu.asset_action_view) |view| if (view.isVisible()) {
            if (menu.asset_action_theme.take()) view.retheme() catch {};
        };
        if (self.app_runtime) |app| {
            const focused = app.win.isFocused();
            if (self.window_focused == true and !focused) {
                self.ime_composing = false;
                if (self.workspace) |workspace| {
                    workspace.setCommandHeld(false);
                    workspace.finishRecentTabSwitch();
                }
            }
            self.window_focused = focused;
        }
        if (self.settings) |settings| {
            _ = settings.poll();
            if (self.workspace) |workspace| applyCommandInfoSettings(workspace, settings.runtime.value.ui.command_info);
        }
        var appearance_published = true;
        self.refreshAppearance() catch |err| {
            appearance_published = false;
            applog.warn(.ui, "appearance publication: {s}", .{@errorName(err)});
        };
        if (self.startup_view) |startup| {
            const settled = if (self.settings) |settings| if (settings.resource_worker) |*worker| !worker.busy() else true else true;
            startup.update(appearance_published and settled);
        }
        // AppKit reports only controls occupying the client header. In native
        // fullscreen its hidden header has none; zoom/maximize keeps them.
        const title_chrome_changed = if (self.app_runtime) |app|
            if (self.title_bar) |bar| shell_styles.syncWorkspaceChrome(self.allocator, bar, app.chromeState(), self.quick.sidebar.collapsed) else false
        else
            false;
        if (self.application_host) |host| {
            _ = host.safeTick() catch |err| {
                applog.warn(.workspace, "host receipt: {s}", .{@errorName(err)});
                return .done;
            };
        }
        self.pollCommandCreations();
        if (self.local_close_view) |view| if (view.session) |id| if (self.workspace) |workspace| {
            const tab = workspace.sessionTab(id);
            if (tab == null or workspace.confirming_id == null or workspace.confirming_id.? != tab.?.tab_id) view.cancel();
        };
        if (self.native_close_pending) {
            if (self.settings) |settings| {
                if (settings.busy()) {
                    self.cx.requestRedraw();
                    return .done;
                }
                // 未保存确认归设置窗口的 view-model：再次请求关闭只会让它保持打开（`SettingsHost.toggle`）。
                if (settings.open) settings.toggle();
            }
            const settings_open = if (self.settings) |settings| settings.open else false;
            if (!settings_open) if (self.application_host) |host| {
                if (self.wizard_host) |wizard_host| wizard_host.probe_controller.cancelAll();
                if (self.native_close_started and !host.windowClosePending()) {
                    self.native_close_pending = false;
                    self.native_close_started = false;
                    // 关闭确认里取消了：“立即重启”（Q5）随之撤销（已经关完的窗口不算）。
                    if (host.windowCloseCancelled()) if (process_state.process_windows) |process| process.cancelRelaunch();
                    return .done;
                }
                if (!self.native_close_started) {
                    _ = host.requestWindowClose() catch |err| {
                        self.native_close_pending = false;
                        applog.warn(.workspace, "window close request: {s}", .{@errorName(err)});
                        return .done;
                    };
                    self.native_close_started = true;
                }
                // Keep the original file host alive while cancelled picker
                // reads deliver their terminal response and retire their key.
                const remote_released = if (self.ai) |ai| if (ai.remote_picker) |picker| picker.shutdown() else true else true;
                if (host.windowCloseReady()) if (self.app_runtime) |app| {
                    const execution_released = if (self.ai) |ai| ai.executionShutdownReady() else true;
                    if (!remote_released or !execution_released) {
                        self.cx.scheduleRedrawAfterNs(33 * std.time.ns_per_ms);
                        return .done;
                    }
                    // A test owns app-scoped native resources outside the tab
                    // batch. Its controller retires only after real release.
                    if (self.wizard_host) |wizard_host| if (wizard_host.probe_controller.jobs.items.len != 0) {
                        self.cx.scheduleRedrawAfterNs(33 * std.time.ns_per_ms);
                        return .done;
                    };
                    if (host.domain.attachments.items.len == 1) if (self.transfer_host) |transfer| {
                        if (transfer.tasks.shutdownStep() != .released) {
                            self.cx.scheduleRedrawAfterNs(33 * std.time.ns_per_ms);
                            return .done;
                        }
                    };
                    self.finishApplicationClose(app);
                };
            };
        }
        // Settings pages rebuild inside their own window (SettingsHost.WindowHook).
        const width = self.cx.viewport.width;
        self.syncHomeConnect();
        self.syncHostArtwork();
        var sidebar_width_changed = false;
        // Content-fit tabs no longer determine the width of the independent sidebar.
        self.quick.sidebar.initial_width_pending = false;
        // design-r3 C2: the sidebar keeps the user's width at every window width.
        const sidebar_width: ui.Sizing = .{ .px = self.quick.sidebar.expanded_width };
        if (!std.meta.eql(self.sidebar_panel.style.width, sidebar_width)) {
            self.sidebar_panel.setStyle(self.allocator, .width, sidebar_width);
            sidebar_width_changed = true;
        }
        const before = self.quick.sidebar.collapsed;
        if (self.settings) |settings| self.quick.sidebar.applyCommittedPreference(settings.runtime.value.ui.sidebar_collapsed);
        if (self.workspace) |workspace| _ = self.quick.sidebar.setSessionCount(workspace.tabs.items.len);
        const resize = @abs(width - self.last_width) > 0.5 or @abs(self.cx.viewport.height - self.last_height) > 0.5;
        self.last_width = width;
        self.last_height = self.cx.viewport.height;
        if (before != self.quick.sidebar.collapsed) {
            self.sidebar_memory.changed(self.allocator, self.cx.io, self.quick.sidebar.collapsed);
            self.applySidebar();
        }
        if (self.workspace) |workspace| self.hintNarrowSidebar(workspace);

        if (self.workspace) |workspace| {
            const no_hosts = workspace.registry.hosts.len == 0 and workspace.registry.groups.len == 0;
            if (workspace.sidebar_chrome) |sidebar| sidebar.setSearchAvailable(workspace.registry.hosts.len != 0);
            if (self.title_controls) |controls| controls.setDisplay(.flex);
            if (self.sidebar_full) |full| full.setDisplay(if (no_hosts) .none else .flex);
            if (self.sidebar_empty) |empty| empty.setDisplay(if (no_hosts) .flex else .none);
            const has_session = workspace.active_tab != null or workspace.active_group_view != null;
            if (self.chrome.transfer_badge) |badge| {
                const count = if (self.transfer_host) |transfer| transfer.unreadTransferCount() else 0;
                badge.setDisplay(.none);
                if (count != 0 and badge.children.items.len != 0) {
                    var count_buffer: [24]u8 = undefined;
                    const label = std.fmt.bufPrint(&count_buffer, "{d}", .{count}) catch "";
                    // Every frame of the shell pump: rewrite the count only when it changed.
                    const shown = if (badge.children.items[0].getText()) |text| text.content else "";
                    if (!std.mem.eql(u8, shown, label)) badge.children.items[0].setTextContent(self.allocator, label) catch {};
                }
            }
            if (self.transfer_host) |transfer| {
                const pane: ?*ui.Node = if (workspace.active_tab) |active| if (active < workspace.tabs.items.len) workspace.tabs.items[active].root else null else null;
                transfer.panel.setPaneAnchor(pane);
            }
            // 4c-3: floating cards live on the window's float layer (shared/ui/float_card); the shell
            // hands it the drag region (everything below the title bar, sidebar included, #62) and the work area (maximize and
            // default placement: title bar and expanded sidebar excluded) every frame. The AI card positions itself; only its inner layout is AI's.
            if (self.float_layer) |layer| {
                layer.setRegion(@import("../../../shared/base/float_card.zig").dragRegion(self.cx.viewport.width, self.cx.viewport.height, shell_styles.outer + shell_styles.title_height));
                layer.setWorkRegion(self.floatRegion());
            }
            if (self.ai) |ai| if (ai.floatOrigin()) |origin| if (ai.card) |card| {
                card.update(origin, ai.controller.model.visible);
            };
            if (self.ai) |ai| if (ai.card) |card| if (ai.controller.model.visible and card.bounds_ready) {
                const rect = card.rect();
                const composer_height: f32 = if (ai.composer_node) |node| if (node.style.height == .px) node.style.height.px else 90 else 90;
                const ai_geometry_changed = !std.meta.eql(self.ai_float_rect, rect);
                self.ai_float_rect = rect;
                if (ai.conversation_viewport) |viewport| {
                    if (ai.sessions_view) |view| view.reflow();
                    // Unified chrome (grip 14 + header 30) + 6px transcript gap.
                    const chrome_height: f32 = @import("../../../shared/ui/float_card/float_chrome.zig").top_height + 6;
                    const queue_height: f32 = if (ai.pending_view) |view| if (view.root.style.display == .none) 0 else view.root.globalRect().h else 0;
                    // cards-float: docked in a split, the pane's content box gives the height (no floating chrome).
                    const docked_height: ?f32 = if (ai.controller.model.docked_leaf != null) if (ai.content_node) |content| content.globalRect().h else null else null;
                    const available = if (docked_height) |h| h - 6 else rect.height - chrome_height;
                    const desired_height = @max(0, available - composer_height - queue_height);
                    if (viewport.style.height != .px or @abs(viewport.style.height.px - desired_height) > 0.5) {
                        viewport.setStyleInline(self.allocator, .{ .height = .{ .px = desired_height } });
                    }
                }
                if (resize or ai_geometry_changed) ai.panel.markLayoutDirty();
                if (ai.controller.model.docked_leaf != null) if (ai.content_node) |content| if (content.globalRect().h != self.ai_docked_height) {
                    self.ai_docked_height = content.globalRect().h;
                    content.markLayoutDirty();
                };
            };
            const local_active = if (workspace.active_tab) |index| index < workspace.tabs.items.len and workspace.isLocalSession(workspace.tabs.items[index].id) else false;
            const terminal_active = if (workspace.active_tab) |index| index < workspace.tabs.items.len and workspace.tabs.items[index].terminal != null else false;
            const status_capabilities = if (self.application_host) |application| if (workspace.active_tab) |index| if (index < workspace.tabs.items.len and workspace.tabs.items[index].content_owner == .session) application.sessions.capabilitySnapshot(workspace.tabs.items[index].content_owner.session) catch null else null else null else null;
            const route_status = if (status_capabilities) |snapshot| @import("../../../host/actions.zig").project(.open_route_details, snapshot).visible else false;
            const transfer_status = if (status_capabilities) |snapshot| @import("../../../host/actions.zig").project(.upload, snapshot).visible else false;
            const plugin_status = if (workspace.active_tab) |index| index < workspace.tabs.items.len and workspace.tabs.items[index].plugin_renderer != null else false;
            const forward_status = if (status_capabilities) |snapshot| @import("../../../host/actions.zig").project(.toggle_socks, snapshot).visible else false;
            if (self.session_details) |details| details.setDisplay(if (has_session and (plugin_status or route_status or (terminal_active and !local_active))) .flex else .none);
            if (self.socks_chip) |chip| chip.setDisplay(if (self.mist != null or forward_status or (terminal_active and !local_active)) .flex else .none);
            if (self.status_bar) |bar| bar.setDisplay(if (self.mist != null or local_active or (has_session and !terminal_active and !route_status and !transfer_status and !plugin_status)) .none else .flex);
            if (self.connection_details_host) |host| if (host.ssh_status.controls) |controls| {
                controls.sidebar_width = self.quick.sidebar.width();
                self.refreshBroadcastStatus(controls);
                if (plugin_status) controls.broadcast_button.setDisplay(.none);
                // Group status follows the focused member, including Local.
                // Keep the same broadcast control on the visible status bar.
                const local_status = if (local_active) self.local_status_view else null;
                const destination = if (local_status) |view| view.root else controls.bar;
                const anchor: ?*ui.Node = if (local_status != null) null else controls.chain_button;
                // 稿 5: in the workspace chrome the broadcast control is the
                // title bar's own native button; it never moves.
                if (!controls.native_tools and controls.broadcast_button.parent != destination) {
                    if (controls.broadcast_button.parent) |parent| parent.removeChild(controls.broadcast_button);
                    if (anchor) |anchor_node| destination.insertChildBefore(self.allocator, controls.broadcast_button, anchor_node) catch {} else destination.appendChild(self.allocator, controls.broadcast_button) catch {};
                }
            };
            self.refreshTitleTools(forward_status, terminal_active);
            self.refreshShortcutHints();
            if (self.local_status_view) |view| {
                view.root.setDisplay(if (self.mist == null and local_active) .flex else .none);
                view.setSidebarCollapsed(self.quick.sidebar.collapsed);
                view.layoutForWidth(@max(0, self.cx.viewport.width - 2 * shell_styles.outer));
            }
            if (self.mist == null) if (self.collapsed_sidebar) |restore| {
                const destination = if (local_active and self.local_status_view != null) self.local_status_view.?.root else self.status_bar;
                if (destination) |bar| if (restore.root.parent != bar) {
                    if (restore.root.parent) |parent| parent.removeChild(restore.root);
                    bar.insertChildBefore(self.allocator, restore.root, if (bar.children.items.len != 0) bar.children.items[0] else null) catch {};
                };
            };
            self.refreshLocalStatus(local_active) catch |err| applog.warn(.ui, "local status: {s}", .{@errorName(err)});
            self.openPendingIdentity();
            if (self.status_detail_view) |view| {
                if (self.local_status_view) |status_view| view.reanchor(status_view.root.globalRect().y);
                view.flush() catch |err| applog.warn(.ui, "status detail: {s}", .{@errorName(err)});
            }
            if (!has_session) {
                if (self.ai) |ai| if (ai.controller.model.visible or ai.panel.style.display != .none) ai.hidePanelNow();
            }
        }

        return if (before != self.quick.sidebar.collapsed or resize or title_chrome_changed or sidebar_width_changed) .needs_layout else .done;
    }

    pub fn onEvent(event: ui.events.Event, context: ?*anyopaque) ui.events.EventResult {
        const self: *AppNavHost = @ptrCast(@alignCast(context orelse return .ignored));
        if (process_state.process_windows) |process| if (process.data_cleanup_owner) |owner| {
            return if (self.settings == owner) .ignored else .handled;
        };
        if (self.asset_group_host) |host| if (host.isVisible()) switch (event) {
            .key_down, .key_up => return .ignored,
            .drag => return .stop,
            else => {},
        };
        if (self.connection_host) |host| if (host.blocksGlobalActions()) switch (event) {
            .key_down, .key_up => return .ignored,
            .drag => return .stop,
            else => {},
        };
        if (self.probe_connection_host) |host| if (host.blocksGlobalActions()) switch (event) {
            .key_down, .key_up => return .ignored,
            .drag => return .stop,
            else => {},
        };
        if (self.connection_details_host) |host| if (host.blocksGlobalActions()) switch (event) {
            .key_down, .key_up => return .ignored,
            .drag => return .stop,
            else => {},
        };
        if (self.menu_host) |menu| if (menu.asset_action_view) |view| if (view.isVisible()) switch (event) {
            .key_down, .key_up => return .ignored,
            .drag => return .stop,
            else => {},
        };
        if (self.transfer_host) |transfer| if (transfer.conflict_view) |view| if (view.isVisible()) switch (event) {
            .key_down, .key_up => return .ignored,
            .drag => return .stop,
            else => {},
        };
        switch (event) {
            .drag => |drag| return self.localDrag(drag),
            .key_down => |key| {
                if (self.workspace) |workspace| workspace.setCommandHeld(key.modifiers.super);
                // 快捷键只经路由判定（注册、让位规则都在 shortcut_router）；下面按原来的先后顺序执行。
                const facts = self.shortcutContext();
                const decision = self.shortcuts().route(key.key, key.modifiers, facts);
                if (decision == .suspended) return .ignored;
                if (decision.runs(.command_history)) {
                    if (self.command_history) |history| history.toggle();
                    return .handled;
                }
                // Esc：原生浮层栈（面板、菜单、确认框，只关最上面一层）与输入框（回到聚焦时的值）在这之前
                // 已经处理；浮动卡片在卡片根上按卡片规则处理。走到这里的只剩窗口级层（OverlayHost）。
                if (key.key == .escape and self.overlay.escape(self.ime_composing)) return .stop;
                if (self.session_menu) |menu| if (menu.isOpen()) {
                    const result = menu.handleKey(key.key);
                    if (result != .ignored) return result;
                    if (key.modifiers.super) return .stop;
                    return .ignored;
                };
                // 浮层打开时页签 MRU 与重命名让给浮层（不进入页签条的按键处理）。
                if (facts.panel and (key.key == .tab and key.modifiers.ctrl or decision.command() == .rename_tab)) return .ignored;
                if (self.workspace) |workspace| {
                    const shortcut: ws.Workspace.TabShortcut = switch (decision) {
                        .run => |command| switch (command) {
                            .rename_tab => .rename,
                            .recent_tab => .recent,
                            else => .none,
                        },
                        else => .none,
                    };
                    const handled = workspace.handleTabKey(key.key, key.modifiers, shortcut);
                    if (handled != .ignored) return handled;
                }
                if (!key.modifiers.super) return .ignored;
                switch (decision) {
                    .yield => |command| switch (command) {
                        // Inputs and read-only message selections own their clipboard and
                        // completion keys before terminal shortcuts (rules in shortcut_router).
                        .copy, .paste, .completion => return .ignored,
                        else => {},
                    },
                    .run => |command| if (self.runShortcut(command)) |result| return result,
                    else => {},
                }
                return .ignored;
            },
            .key_up => |key| {
                if (self.workspace) |workspace| {
                    workspace.setCommandHeld(key.modifiers.super);
                    if (!key.modifiers.ctrl) workspace.finishRecentTabSwitch();
                }
                return .ignored;
            },
            .ime_preedit => |preedit| {
                self.ime_composing = preedit.text.len > 0;
                return .ignored;
            },
            .ime_commit => {
                self.ime_composing = false;
                return .ignored;
            },
            .blur => {
                self.ime_composing = false;
                return .ignored;
            },
            else => return .ignored,
        }
    }

    const shortcut_router = @import("../model/shortcut_router.zig");

    /// 本窗口的快捷键路由：键位读 `[keys]`（设置保存后立即生效）。
    pub fn shortcuts(self: *const AppNavHost) shortcut_router.Router {
        const defaults = struct {
            const map: shortcut_router.Map = .{};
        };
        return .{ .keys = if (self.workspace) |workspace| &workspace.app_config.keys else &defaults.map };
    }

    /// 其余带快捷键文字的控件（侧栏开合、命令历史按钮）：键位变化后更新 Tooltip 与无障碍名。
    fn refreshShortcutHints(self: *AppNavHost) void {
        const router = self.shortcuts();
        if (self.collapsed_sidebar) |view| view.syncShortcut(router.hint(.sidebar));
        if (self.workspace) |workspace| if (workspace.sidebar_chrome) |view| view.syncShortcut(router.hint(.sidebar));
        if (self.command_history) |view| view.syncShortcut(router.hint(.command_history));
    }

    /// 让位规则用到的事实（规则本身在 shortcut_router）。
    fn shortcutContext(self: *AppNavHost) shortcut_router.Context {
        const facts: ws.Workspace.ShortcutFacts = if (self.workspace) |workspace| workspace.shortcutFacts() else .{};
        return .{
            .composing = self.ime_composing,
            .editor = self.focusedTextEditor(),
            .ai_selection = @import("../../ai/pane/view/ai_text_selection.zig").ownsFocus(self.cx),
            .panel = self.recentTabBlocked(),
            .preedit = facts.preedit,
            .content = facts.content,
            .local_editor = facts.local_editor,
        };
    }

    /// 执行路由判定出的命令（只在按下 ⌘ 的组合上到达这里）；null 表示不处理。
    fn runShortcut(self: *AppNavHost, command: shortcut_router.Command) ?ui.events.EventResult {
        switch (command) {
            .new_host => {
                if (self.wizard) |wizard| wizard.show();
                return .handled;
            },
            .open_settings => {
                if (self.settings) |settings| settings.show();
                return .handled;
            },
            else => {},
        }
        const workspace = self.workspace orelse return null;
        switch (command) {
            .new_tab => self.showSessionMenu(),
            .close_tab => workspace.requestCloseActive(),
            .split_vertical, .split_horizontal => {
                self.bindGroupWorkspace(workspace);
                workspace.splitGroup(&self.roster, command == .split_horizontal) catch |err| workspace.statusFailure(@errorName(err));
            },
            .quick_connect => self.toggleQuickConnect(),
            .sidebar => self.toggleSidebar(),
            .ai => if (self.ai) |ai| ai.toggle(),
            .search => if (self.menu_host) |menu| if (menu.activeTerminal()) |terminal| terminal.openSearch(),
            .completion => if (self.menu_host) |menu| if (menu.activeTerminal()) |terminal| {
                _ = terminal.openCompletion();
            },
            .reconnect => {
                const index = workspace.active_tab orelse return .handled;
                workspace.reconnectTab(index) catch |err| workspace.statusFailure(@errorName(err));
            },
            .broadcast => openBroadcastStatus(self),
            .upload => if (self.transfer_host) |transfer| transfer.openPanel(),
            .copy => {
                if (self.menu_host) |menu| {
                    if (menu.activeTerminal()) |terminal| {
                        if (!terminal.hasSelection()) _ = terminal.pushText("\x03") else menu.runAction(.copy);
                    }
                }
                return .stop;
            },
            // The AI Input owns the paste event while its floating panel is open
            // (yield rule); never inject clipboard text into the SSH PTY.
            .paste => {
                if (self.menu_host) |menu| menu.runAction(.paste);
                return .stop;
            },
            .tab_1, .tab_2, .tab_3, .tab_4, .tab_5, .tab_6, .tab_7, .tab_8, .tab_9 => workspace.selectTabOrdinal(@intFromEnum(command) - @intFromEnum(shortcut_router.Command.tab_1)),
            .previous_tab, .next_tab => workspace.selectAdjacentTab(command == .next_tab),
            else => return null,
        }
        return .handled;
    }

    fn recentTabBlocked(self: *AppNavHost) bool {
        if (self.focusedTextEditor() or self.quick.quick_connect_open) return true;
        if (self.menu_host) |menu| if (menu.state.open != null) return true;
        if (self.wizard) |wizard| if (!wizard.windowed()) if (wizard.root) |root| if (root.style.display != .none) return true;
        if (self.transfer_host) |transfer| if (transfer.panel.isVisible()) return true;
        if (self.socks_host) |socks| {
            if (socks.exposure) |view| if (view.visible) return true;
            if (socks.config) |view| if (view.visible) return true;
            if (socks.info) |view| if (view.root.style.display != .none) return true;
        }
        if (self.help_open) |open| if (open.peek()) return true;
        if (self.ai) |ai| if (ai.controller.model.visible) return true;
        return false;
    }

    fn focusedTextEditor(self: *AppNavHost) bool {
        const focused = self.cx.focus_manager.getFocused() orelse return false;
        // Terminal is also a text-input client for IME. It retains its own
        // clipboard policy; all other editors consume native clipboard keys.
        if (self.workspace) |workspace| {
            for (workspace.tabs.items) |tab| if (tab.terminal != null and focused == tab.terminal.?.root) return false;
        }
        return focused.behavior.interaction.text_input_client != null;
    }

    fn importHosts(self: *AppNavHost) void {
        self.importHostsFile() catch |err| {
            if (self.workspace) |workspace| workspace.statusFailure(@errorName(err));
        };
    }

    fn importHostsFile(self: *AppNavHost) !void {
        const workspace = self.workspace orelse return error.WorkspaceUnavailable;
        const sdk = self.cx.system_sdk orelse return error.NativeDialogUnavailable;
        var buffer: [4096]u8 = undefined;
        const path = (try @import("../../../platform/dialog_port.zig").run(sdk, .{ .kind = .open_file, .title = "导入 hosts.toml" }, &buffer)) orelse return;
        var imported = try @import("../../../config/store.zig").loadHostsForImport(self.cx.io, std.Io.Dir.cwd(), self.allocator, path);
        defer imported.deinit();
        // Parse and validate the complete file before changing live assets.
        for (imported.hosts) |host| try host.validate();
        const previous = workspace.registry.hosts;
        errdefer workspace.registry.hosts = previous;
        for (imported.hosts) |host| _ = try workspace.appendHost(host);
        try workspace.saveRegistry();
        try workspace.rebuildSidebar();
        workspace.status("已导入主机配置");
    }

    pub fn cleanup(self: *AppNavHost) void {
        self.overlay.deinit();
        self.sidebar_memory.deinit(self.allocator);
        if (self.app_runtime) |app| if (self.ai_logo_texture) |id| app.renderer.image_renderer.unloadTexture(id);
        if (self.app_runtime) |app| if (self.empty_logo_texture) |id| app.renderer.image_renderer.unloadTexture(id);
        if (self.app_runtime) |app| for (self.host_artwork) |texture| if (texture) |id| app.renderer.image_renderer.unloadTexture(id);
        if (self.app_runtime) |app| for (self.tab_mask_artwork) |texture| if (texture) |id| app.renderer.image_renderer.unloadTexture(id);
        self.cx.removeAfterLayoutHook(self);
        if (self.ai) |ai| {
            ai.cancelRef().cancel();
            ai.execution().tool_bridge.shutdown(self.application_host);
            if (ai.worker_thread) |thread| {
                thread.join();
                ai.worker_thread = null;
            }
            if (ai.remote_picker) |picker| {
                if (picker.shutdown()) picker.release() catch {};
            }
            ai.file_application = null;
            ai.application_host = null;
        }
        const application_host = self.application_host;
        self.application_host = null;
        const file_application = self.file_application;
        const files_released = if (file_application) |files| files.shutdownStep() == .released else true;
        if (application_host) |host| host.deinit();
        if (files_released) if (file_application) |files| files.deinit() catch {};
        for (self.broadcasts.items) |*approval| approval.deinit(self.allocator);
        self.broadcasts.deinit(self.allocator);
        self.pending_command_creations.deinit(self.allocator);
        self.roster.deinit();
        if (self.cx.root) |root| {
            if (root.behavior.events.capture_context == @as(?*anyopaque, @ptrCast(self))) {
                root.behavior.events.on_event_capture = null;
                root.behavior.events.capture_context = null;
            }
        }
        self.quick.deinit();
        self.allocator.destroy(self);
    }

    pub fn collapsedSearch(ctx: *anyopaque) void {
        const self: *AppNavHost = @ptrCast(@alignCast(ctx));
        self.toggleQuickConnect();
    }

    fn localDropMarker(_: *AppNavHost, _: ui.HandlerRef.DropPayload) void {}

    fn localDrag(self: *AppNavHost, drag: ui.events.DragEvent) ui.events.EventResult {
        if (drag.kind == .exited) {
            if (drag.session_ended) self.local_drop = null;
            return .ignored;
        }
        const workspace = self.workspace orelse return .ignored;
        if (drag.kind == .entered or drag.kind == .updated) {
            if (self.local_drop != null) return .ignored;
            const index = workspace.active_tab orelse return .ignored;
            if (index >= workspace.tabs.items.len) return .ignored;
            const tab = workspace.tabs.items[index];
            if (!tab.local or tab.closing or self.cx.focus_manager.getFocused() != tab.terminal.?.root) return .ignored;
            const rect = tab.terminal.?.root.globalRect();
            if (drag.x < rect.x or drag.y < rect.y or drag.x >= rect.x + rect.w or drag.y >= rect.y + rect.h) return .ignored;
            const owner = switch (tab.content_owner) {
                .session => |owner| owner,
                else => return .ignored,
            };
            self.local_drop = .{ .tab = tab.tab_id, .owner = owner, .input_id = tab.terminal.?.root.id };
            return .ignored;
        }
        if (drag.kind != .dropped) return .ignored;
        const captured = self.local_drop orelse return .ignored;
        self.local_drop = null;
        const index = workspace.tabIndexById(captured.tab) orelse return .stop;
        const tab = workspace.tabs.items[index];
        if (!tab.local or tab.closing or workspace.active_tab != index or !tab.content_owner.eql(.{ .session = captured.owner }) or tab.terminal.?.root.id != captured.input_id or self.cx.focus_manager.getFocused() != tab.terminal.?.root) return .stop;
        const rect = tab.terminal.?.root.globalRect();
        if (drag.x < rect.x or drag.y < rect.y or drag.x >= rect.x + rect.w or drag.y >= rect.y + rect.h) return .stop;
        if (drag.payload_truncated or drag.payload_kind != .file_or_url or self.ime_composing) {
            workspace.status(if (self.ime_composing) "请先完成输入法组字再插入路径" else "无法插入：拖入的文件列表不完整或不是本地路径");
            return .stop;
        }
        var paths = @import("../../../local/path_input.zig").decodeDropPaths(self.allocator, drag.paths) catch |err| {
            workspace.statusFailure(@errorName(err));
            return .stop;
        };
        defer paths.deinit();
        if (paths.paths.len == 0) return .stop;
        tab.terminal.?.insertLocalPaths(captured.owner, paths.paths) catch |err| workspace.statusFailure(@errorName(err));
        return .stop;
    }

    pub fn selectGlobalTheme(raw: *anyopaque, id: []const u8) !void {
        const self: *AppNavHost = @ptrCast(@alignCast(raw));
        const settings = self.settings orelse return error.SettingsUnavailable;
        try settings.immediateTheme(id);
        self.cx.requestRedraw();
    }
    pub fn manageGlobalThemes(raw: *anyopaque) void {
        const self: *AppNavHost = @ptrCast(@alignCast(raw));
        const settings = self.settings orelse return;
        if (settings.busy()) return;
        if (!settings.open) settings.toggle();
        if (settings.appearance_context.preview_active) settings.setMaterialPreview(false);
        settings.navigateSettings(.{ .page = 0, .sub = 0 }); // 外观与主题 › 主题
        settings.pending_rebuild = true;
        self.cx.requestRedraw();
    }
    /// title-click: legacy status-bar theme triggers (hidden retained rows) open the same
    /// Settings › 外观与主题 page as every other theme entry.
    pub fn showGlobalTheme(raw: *anyopaque, _: *ui.Node) void {
        manageGlobalThemes(raw);
    }
    /// @theme and the menu bar's 显示 › 外观…: Settings › 外观与主题 › 主题 (the tab menu has no theme item).
    /// The theme is not a title bar tool (not a frequent action).
    pub fn showThemeFromMenu(raw: *anyopaque) void {
        manageGlobalThemes(raw);
    }

    pub fn refreshAppearance(self: *AppNavHost) !void {
        const settings = self.settings orelse return;
        if (!settings.appearance_initialized) return;
        settings.updateBackgroundIdentity();
        const runtime = settings.runtime.value;
        const record = settings.registry.get(runtime.ui.theme) orelse return;
        if (self.connection_details_host) |host| if (host.ssh_status.controls) |controls| {
            try controls.setThemeName(self.cx, record.theme.name);
        };
        const preview = settings.appearance_context.preview_active;
        const materials = if (preview) settings.controller.model.value.ui.materials else runtime.ui.materials;
        const texture = if (preview) settings.draft_texture orelse settings.committed_texture else settings.committed_texture;
        const image: ?@import("../view/background_layers.zig").Image = if (texture) |value| .{ .id = value.id, .width = value.width, .height = value.height, .repeating = value.repeating } else null;
        const showing = materials.background.enabled and image != null;
        _ = app_theme.setMaterialParameters(materials.background.transparency, @floatFromInt(materials.blur_px));
        _ = app_theme.setMaterialVisible(showing);
        var hash = std.hash.Wyhash.init(0);
        hash.update(record.id);
        std.hash.autoHash(&hash, record.ui_tokens);
        std.hash.autoHash(&hash, showing);
        std.hash.autoHash(&hash, .{ @as(u32, @bitCast(materials.background.transparency)), materials.blur_px });
        const fingerprint = hash.final();
        if (self.appearance_ui_hash != fingerprint) {
            app_theme.selectTokens(record.ui_tokens);
            self.appearance_theme.publish(self.cx, app_theme.widgetTheme(app_theme.currentName()));
            if (self.wizard) |wizard| wizard.republishTheme();
            if (settings.open) settings.pending_rebuild = true;
            self.rethemeChrome();
            if (self.local_status_view) |view| view.retheme();
            if (self.transfer_host) |transfer| transfer.panel.retheme();
            if (self.transfer_host) |transfer| {
                if (transfer.manager_panel) |panel| panel.retheme();
                for (transfer.workspace.tabs.items) |tab| for (tab.transfer_trays) |tray| {
                    if (tray) |panel| panel.retheme();
                };
            }
            if (self.file_application) |files| files.retheme();
            self.local_status_hash = null;
            if (self.status_detail_view) |view| view.dirty = true;
            if (self.workspace) |workspace| {
                workspace.palette = ws.Palette.fromTheme();
                for (workspace.tabs.items) |tab| if (tab.terminal != null and !tab.local) {
                    tab.terminal.?.setThemeColors(app_theme.current().fg_1, app_theme.current().border, app_theme.current().accent);
                };
                for (workspace.replays.items) |replay| replay.terminal().setThemeColors(app_theme.current().fg_1, app_theme.current().border, app_theme.current().accent);
                try workspace.rebuildSidebar();
                try workspace.rebuildTabBar();
            }
            if (self.collapsed_sidebar) |collapsed| try collapsed.refresh();
            self.appearance_ui_hash = fingerprint;
        }
        const theme_revision = settings.appearance_state.theme_revision +| runtime.config_revision;
        if (self.workspace) |workspace| for (workspace.tabs.items) |tab| {
            if (tab.terminal == null) continue;
            if (tab.local and tab.terminal.?.root.behavior.events.on_drop == null) {
                tab.terminal.?.root.behavior.events.on_drop = ui.Cx.dropHandlerFrom(AppNavHost, self, localDropMarker);
                tab.terminal.?.root.markLayoutDirty();
            }
            tab.terminal.?.setTerminalTheme(.{ .revision = theme_revision, .cursor_shape = std.meta.stringToEnum(@FieldType(@import("../../../vt/theme.zig").Theme, "cursor_shape"), runtime.ui.cursor_style) orelse .bar, .foreground = record.theme.fg, .background = record.theme.bg, .cursor = record.theme.cursor, .selection = record.theme.selection orelse record.ui_tokens.selection, .ansi = record.theme.ansi }) catch |err| {
                if (err != error.WorkerBusy) return err;
            };
        };
        // 会话记录卡片里的只读回放表面跟随同一份终端主题（与原归档 tab 相同）。
        if (self.workspace) |workspace| for (workspace.replays.items) |replay| {
            replay.terminal().setTerminalTheme(.{ .revision = theme_revision, .cursor_shape = std.meta.stringToEnum(@FieldType(@import("../../../vt/theme.zig").Theme, "cursor_shape"), runtime.ui.cursor_style) orelse .bar, .foreground = record.theme.fg, .background = record.theme.bg, .cursor = record.theme.cursor, .selection = record.theme.selection orelse record.ui_tokens.selection, .ansi = record.theme.ansi }) catch |err| {
                if (err != error.WorkerBusy) return err;
            };
        };
        if (self.background_view) |view| try view.update(image, materials, self.cx.viewport.width, self.cx.viewport.height);
    }

    /// Retained plain nodes do not replay styles when the widget theme changes.
    /// Update only paint; keep draft input, focus, node IDs and shell geometry.
    fn rethemeChrome(self: *AppNavHost) void {
        const c = app_theme.current();
        if (self.chrome.toolbar_tint) |tint| tint.set(c.fg_2);
        if (self.chrome.transfer_badge) |badge| badge.setBackground(c.ok);
        if (self.chrome.empty_title) |node| node.setTextColor(c.fg_1);
        if (self.chrome.empty_description) |node| node.setTextColor(c.fg_2);
        if (self.chrome.sidebar_title) |node| node.setTextColor(c.fg_1);
        if (self.chrome.sidebar_search) |node| {
            node.setBackground(c.well);
            node.setBorderColor(c.well_border);
        }
        if (self.chrome.sidebar_search_icon) |node| node.setTextColor(c.fg_3);
        if (self.chrome.sidebar_search_input) |input| {
            input.state.tokens = self.cx.tokens;
            input.state.placeholder_color = c.fg_1;
            input.state.dirty = true;
            if (input.state.text_display_node) |node| node.setTextColor(c.fg_1);
            input.input_container.markRenderDirty();
        }
        if (self.chrome.sidebar_footer) |node| {
            node.setBackground(c.well);
            node.setBorderColor(c.border);
        }
        if (self.chrome.sidebar_footer_label) |node| node.setTextColor(c.fg_2);
        if (self.chrome.sidebar_empty_label) |node| node.setTextColor(c.fg_3);
    }

    pub fn showLocalStatusDetail(raw: *anyopaque, kind: @import("../model/status_controller.zig").Kind, trigger: *ui.Node) void {
        const self: *AppNavHost = @ptrCast(@alignCast(raw));
        const view = self.local_status_view orelse return;
        const detail = self.status_detail_view orelse return;
        const owner = view.currentOwner() orelse return;
        const workspace = self.workspace orelse return;
        const index = workspace.active_tab orelse return;
        if (index >= workspace.tabs.items.len or !workspace.tabs.items[index].content_owner.eql(.{ .session = owner })) return;
        detail.show(kind, trigger, trigger.globalRect().y, view.encoding_button.style.display == .none or view.grid_button.style.display == .none) catch |err| workspace.statusFailure(@errorName(err));
    }

    fn refreshLocalStatus(self: *AppNavHost, active: bool) !void {
        const view = self.local_status_view orelse return;
        const detail = self.status_detail_view orelse return;
        if (!active) {
            if (detail.controller.source) |source| detail.invalidate(source.value.owner);
            self.local_status_hash = null;
            return;
        }
        const workspace = self.workspace orelse return;
        const index = workspace.active_tab orelse return;
        if (index >= workspace.tabs.items.len) return;
        const tab = workspace.tabs.items[index];
        const owner = switch (tab.content_owner) {
            .session => |owner| owner,
            else => return,
        };
        const owner_changed = if (view.currentOwner()) |previous| !previous.eql(owner) else true;
        if (!owner_changed and self.cx.frame_time_ms - self.last_status_sample_ms < 300) return;
        self.last_status_sample_ms = self.cx.frame_time_ms;
        const host = self.application_host orelse return;
        const process = host.localProcess(tab.id) catch |err| switch (err) {
            error.WorkerBusy => if (owner_changed) null else return,
            else => null,
        };
        var cwd = host.localCwd(tab.id, self.allocator) catch |err| switch (err) {
            error.WorkerBusy => if (owner_changed) null else return,
            else => null,
        };
        defer if (cwd) |*value| value.deinit(self.allocator);
        const snapshot = host.terminalSnapshot(tab.id);
        const grid: ?@import("../../terminal/view/local_status_view.zig").Grid = if (snapshot) |value| .{ .cols = value.projection.cols, .rows = value.projection.rows, .revision = value.geometry_revision } else null;
        const directory: ?[]const u8 = if (cwd) |value| value.value else null;
        const readonly = if (snapshot) |value| value.read_only else false;
        var hash = std.hash.Wyhash.init(0);
        std.hash.autoHash(&hash, owner);
        std.hash.autoHash(&hash, process);
        std.hash.autoHash(&hash, grid);
        std.hash.autoHash(&hash, readonly);
        if (directory) |value| hash.update(value);
        const fingerprint = hash.final();
        if (self.local_status_hash == fingerprint) return;
        if (self.local_status_revision == std.math.maxInt(u64)) return error.RevisionExhausted;
        self.local_status_revision += 1;
        const revision = self.local_status_revision;
        try view.update(.{ .owner = owner, .source_revision = revision, .process = process, .cwd = directory, .grid = grid, .encoding = if (snapshot != null) .utf8 else .unknown });
        try detail.update(.{ .owner = .{ .session = owner }, .owner_kind = .local, .source_revision = revision, .identity_label = "本地终端", .encoding = if (snapshot != null) .utf8 else .unknown, .grid = if (grid) |value| .{ .cols = value.cols, .rows = value.rows, .revision = value.revision } else null, .cwd = directory, .read_only = readonly });
        self.local_status_hash = fingerprint;
    }

    pub fn showLocalClose(raw: ?*anyopaque, session_id: ws.SessionId) void {
        const self: *AppNavHost = @ptrCast(@alignCast(raw orelse return));
        const workspace = self.workspace orelse return;
        const view = self.local_close_view orelse {
            workspace.resolveLocalCloseConfirmation(session_id, false);
            workspace.status("无法显示本地进程关闭确认");
            return;
        };
        var risk = if (self.application_host) |host| host.localCloseRisk(session_id, self.allocator) catch null else null;
        defer if (risk) |*snapshot| snapshot.deinit(self.allocator);
        view.show(session_id, if (risk) |*snapshot| snapshot else null) catch |err| {
            workspace.resolveLocalCloseConfirmation(session_id, false);
            workspace.statusFailure(@errorName(err));
        };
    }

    pub fn resolveLocalClose(raw: *anyopaque, session_id: ws.SessionId, accepted: bool) void {
        const self: *AppNavHost = @ptrCast(@alignCast(raw));
        const workspace = self.workspace orelse return;
        workspace.resolveLocalCloseConfirmation(session_id, accepted);
    }

    pub fn closeRisk(raw: ?*anyopaque, session_id: ws.SessionId) ws.CloseRisk {
        const self: *AppNavHost = @ptrCast(@alignCast(raw orelse return .{}));
        var risk: ws.CloseRisk = .{};
        if (self.transfer_host) |transfer| {
            const owner = if (self.application_host) |host| host.ownerForLegacy(session_id) else null;
            for (0..transfer.manager.count()) |index| {
                const progress = transfer.manager.progressAt(index).?;
                const original = TransferHost.jobOwner(transfer, progress.job);
                if (owner == null or original == null or !original.?.eql(owner.?)) continue;
                if (progress.job_cleanup != .released or (progress.state != .succeeded and progress.state != .failed and progress.state != .cancelled)) risk.transfer = true;
            }
        }
        if (self.socks_host) |socks| risk.socks = socks.hasLive(session_id);
        if (self.ai) |ai| if (self.application_host) |host| if (host.ownerForLegacy(session_id)) |owner| {
            risk.ai_write = ai.execution().tool_bridge.writeRisk(owner);
        };
        return risk;
    }

    pub fn closeImpact(raw: ?*anyopaque, session_id: ws.SessionId) @import("../../../host/group_close_controller.zig").Impact {
        const self: *AppNavHost = @ptrCast(@alignCast(raw orelse return .{}));
        var result: @import("../../../host/group_close_controller.zig").Impact = .{};
        const owner = if (self.application_host) |host| host.ownerForLegacy(session_id) else null;
        var details: [512]u8 = undefined;
        var length: usize = 0;
        if (self.transfer_host) |transfer| {
            var hash = std.hash.Wyhash.init(0);
            var count: usize = 0;
            for (0..transfer.manager.count()) |index| {
                const progress = transfer.manager.progressAt(index).?;
                const original = TransferHost.jobOwner(transfer, progress.job);
                if (owner == null or original == null or !original.?.eql(owner.?)) continue;
                if (progress.job_cleanup == .released and (progress.state == .succeeded or progress.state == .failed or progress.state == .cancelled)) continue;
                std.hash.autoHash(&hash, progress.job);
                std.hash.autoHash(&hash, progress.attempt);
                std.hash.autoHash(&hash, progress.state);
                std.hash.autoHash(&hash, progress.job_cleanup);
                if (progress.job_cleanup == .unknown) result.unknown = 1;
                count += 1;
            }
            if (count != 0) {
                result.transfer = hash.final();
                const text = std.fmt.bufPrint(details[length..], "传输 {d} 项", .{count}) catch "";
                length += text.len;
            }
        }
        if (self.socks_host) |socks| {
            const snapshot = socks.closeImpact(session_id);
            result.socks = snapshot.socks;
            result.unknown |= snapshot.unknown;
            if (snapshot.detail_len != 0) {
                const text = std.fmt.bufPrint(details[length..], "{s}{s}", .{ if (length == 0) @as([]const u8, "") else "；", snapshot.detailText() }) catch "";
                length += text.len;
            }
        }
        if (self.ai) |ai| {
            if (owner) |original| {
                const snapshot = ai.execution().tool_bridge.closeImpact(original);
                result.ai = snapshot.ai;
                result.unknown |= snapshot.unknown;
                if (snapshot.detail_len != 0) {
                    const text = std.fmt.bufPrint(details[length..], "{s}{s}", .{ if (length == 0) @as([]const u8, "") else "；", snapshot.detailText() }) catch "";
                    length += text.len;
                }
                for (ai.tool_results.records.items) |record| for (record.targets) |target| {
                    const source = target.source orelse continue;
                    if (!source.eql(original) or !target.result.remote_effect_unknown) continue;
                    var hash = std.hash.Wyhash.init(result.ai);
                    std.hash.autoHash(&hash, source);
                    std.hash.autoHash(&hash, record.turn_id);
                    hash.update(record.call_id);
                    result.ai = hash.final();
                    result.remote_effect_unknown = true;
                };
                if (result.remote_effect_unknown) {
                    const text = std.fmt.bufPrint(details[length..], "{s}远端执行结果待核实", .{if (length == 0) @as([]const u8, "") else "；"}) catch "";
                    length += text.len;
                }
            }
            if (ai.execution().request_owner) |request| {
                const owns = if (ai.ownerContent(request)) |held| switch (held) {
                    .session => |id| if (owner) |original| @backingInt(original.session_id) == id else false,
                    .group => |id| if (self.roster.findById(std.math.cast(u32, id) orelse 0)) |group| group.contains(session_id) else false,
                } else false;
                if (owns and ai.execution().thread_state.load(.acquire) == 1) {
                    var hash = std.hash.Wyhash.init(result.ai);
                    std.hash.autoHash(&hash, request);
                    std.hash.autoHash(&hash, ai.request_operation_id);
                    if (ai.request_text) |prompt| hash.update(prompt);
                    result.ai = hash.final();
                    const text = std.fmt.bufPrint(details[length..], "{s}AI 请求处理中", .{if (length == 0) @as([]const u8, "") else "；"}) catch "";
                    length += text.len;
                }
            }
        }
        result.setDetail(details[0..length]);
        return result;
    }

    pub fn closeStep(raw: *anyopaque, session_id: ws.SessionId, step: application_host_mod.CloseStep) application_host_mod.CloseReceipt {
        const self: *AppNavHost = @ptrCast(@alignCast(raw));
        switch (step) {
            .pause_transfers => if (self.transfer_host) |transfer| {
                const owner = if (self.application_host) |host| host.ownerForLegacy(session_id) else null;
                if (owner) |original| return transfer.retainForClose(original) catch |err| {
                    applog.warn(.transfer, "retain original transfer: {s}", .{@errorName(err)});
                    return .unknown;
                };
            },
            .stop_ai => if (self.ai) |ai| {
                if (self.application_host) |host| if (host.ownerForLegacy(session_id)) |owner| {
                    const receipt = ai.closeAttachedSession(owner, false);
                    if (receipt != .released) return receipt;
                    if (ai.remote_picker) |picker| switch (picker.stopSource(owner)) {
                        .released => {},
                        .awaiting => return .awaiting,
                        .unknown => return .unknown,
                    };
                    if (ai.transcript_images) |store| {
                        const image_receipt = store.stopOwner(owner, host);
                        if (image_receipt != .released) return image_receipt;
                    }
                };
            },
            .release_forwards => if (self.socks_host) |socks| return socks.closeForSession(session_id),
            .release_content => {
                if (self.ai) |ai| if (self.application_host) |host| if (host.ownerForLegacy(session_id)) |owner| {
                    const receipt = ai.closeAttachedSession(owner, true);
                    if (receipt != .released) return receipt;
                };
                _ = self.roster.leavePane(session_id);
            },
            .close_protocol => {},
        }
        return .released;
    }

    pub fn cleanupSession(raw: ?*anyopaque, session_id: ws.SessionId) void {
        const self: *AppNavHost = @ptrCast(@alignCast(raw orelse return));
        _ = self.roster.leavePane(session_id);
        if (self.transfer_host) |transfer| if (transfer.session_id == session_id) {
            const owner = if (self.application_host) |host| host.ownerForLegacy(session_id) else null;
            for (0..transfer.manager.count()) |index| {
                const progress = transfer.manager.progressAt(index).?;
                const original = TransferHost.jobOwner(transfer, progress.job);
                if (owner == null or original == null or !original.?.eql(owner.?)) continue;
                if (progress.state == .running or progress.state == .queued or progress.state == .retry_wait) transfer.manager.pause(progress.job) catch {};
            }
        };
        if (self.socks_host) |socks| _ = socks.stopForSession(session_id);
    }

    pub fn collapsedNew(ctx: *anyopaque) void {
        const self: *AppNavHost = @ptrCast(@alignCast(ctx));
        if (self.wizard) |wizard| wizard.show();
    }

    pub fn collapsedHostAction(ctx: *anyopaque, owner: @import("../../../host/identity.zig").AssetOwner, action: @import("../view/sidebar_collapsed_view.zig").HostAction) void {
        const self: *AppNavHost = @ptrCast(@alignCast(ctx));
        const workspace = self.workspace orelse return;
        _ = workspace.registry.get(owner) catch {
            workspace.status("主机配置已变化，请重新打开详情");
            return;
        };
        const index = workspace.registry.indexOf(owner.id) orelse return;
        switch (action) {
            .connect => workspace.newSession(index) catch |err| workspace.statusFailure(@errorName(err)),
            .edit => {
                const menu = self.menu_host orelse return;
                menu.hide();
                menu.context_host = index;
                menu.captured_host = workspace.hostId(index);
                menu.captured_asset = owner;
                menu.context_tab = null;
                menu.captured_tab = null;
                menu.captured_owner = null;
                menu.runCapturedAction(.edit_host);
            },
        }
    }

    pub fn collapsedExpand(ctx: *anyopaque) void {
        const self: *AppNavHost = @ptrCast(@alignCast(ctx));
        self.toggleSidebar();
    }

    fn broadcastFacts(self: *AppNavHost, group_id: u32) ![]@import("../../workspace/model/broadcast_controller.zig").Fact {
        const BC = @import("../../workspace/model/broadcast_controller.zig");
        var facts: std.ArrayList(BC.Fact) = .empty;
        errdefer facts.deinit(self.allocator);
        const group = self.roster.findById(group_id) orelse return error.UnknownGroup;
        const workspace = self.workspace orelse return error.NoWorkspace;
        for (group.members.items) |member| for (workspace.tabs.items) |tab| {
            if (tab.id != member.pane_id or tab.terminal == null) continue;
            const view = &tab.terminal.?;
            const application = self.application_host orelse continue;
            if (view.terminal_surface == null) {
                const runtime = tab.runtime orelse continue;
                const owner = application.ownerForLegacy(tab.id) orelse continue;
                const capabilities = (application.sessions.capabilitySnapshot(owner) catch continue) orelse continue;
                var projection = runtime.copyProjection(self.allocator) catch continue;
                defer projection.deinit(self.allocator);
                try facts.append(self.allocator, .{ .handle = owner, .membership_revision = member.membership_revision, .writable = member.active and !tab.closing and !tab.failed and runtime.isConnected() and runtime.isAttached() and view.history.selected == null and @import("../../../host/actions.zig").project(.toggle_broadcast, capabilities).enabled, .capability_revision = capabilities.revision, .mode_revision = projection.mode_revision });
                continue;
            }
            const surface = view.terminal_surface.?;
            // Use the owned displayed snapshot for source facts. A transient
            // worker lock during accepted input must not erase the source;
            // recipient submission still validates live owner/mode/writability.
            const snapshot = surface.snapshot orelse continue;
            if (!snapshot.owner.eql(surface.owner)) continue;
            const capabilities = (application.sessions.capabilitySnapshot(snapshot.owner) catch continue) orelse continue;
            try facts.append(self.allocator, .{ .handle = snapshot.owner, .membership_revision = member.membership_revision, .writable = member.active and !snapshot.read_only and !tab.closing and view.history.selected == null and @import("../../../host/actions.zig").project(.toggle_broadcast, capabilities).enabled, .capability_revision = capabilities.revision, .mode_revision = snapshot.projection.mode_revision, .input_revision = snapshot.input_revision });
        };
        return facts.toOwnedSlice(self.allocator);
    }

    fn refreshBroadcastStatus(self: *AppNavHost, controls: *@import("../../connections/progress/host/ssh_status_host.zig").Controls) void {
        const workspace = self.workspace orelse return;
        for (workspace.tabs.items) |tab| {
            var enabled = false;
            if (self.application_host) |application| if (application.ownerForLegacy(tab.id)) |handle| {
                for (self.broadcasts.items) |approval| {
                    const facts = self.broadcastFacts(approval.group_id) catch continue;
                    defer self.allocator.free(facts);
                    if (approval.participates(handle, facts)) {
                        enabled = true;
                        break;
                    }
                }
            };
            if (tab.terminal) |*terminal| terminal.local_state.broadcast = enabled;
            workspace.setGroupMemberBroadcast(tab.id, enabled);
        }
        const group_id = workspace.active_group_view;
        controls.broadcast_button.setDisplay(if (group_id != null) .flex else .none);
        controls.broadcast_button.behavior.events.on_click = .{ .context = self, .callback = openBroadcastStatus };
        var participants: usize = 0;
        var running = false;
        if (group_id) |id| if (self.broadcastFor(id)) |approval| if (approval.enabled) {
            const facts = self.broadcastFacts(id) catch return;
            defer self.allocator.free(facts);
            participants = approval.participantCount(facts);
            running = participants > 0;
        };
        controls.setBroadcastState(self.cx, running, participants) catch {};
        if (self.broadcast_view) |view| if (view.open.peek()) {
            if (group_id) |id| {
                if (self.broadcastFor(id)) |approval| {
                    const facts = self.broadcastFacts(id) catch return;
                    defer self.allocator.free(facts);
                    self.showBroadcast(approval, facts);
                }
            } else view.dismiss();
        };
    }
    fn openBroadcastStatus(raw: ?*anyopaque) void {
        const self: *AppNavHost = @ptrCast(@alignCast(raw orelse return));
        const workspace = self.workspace orelse return;
        const group = workspace.active_group_view orelse return;
        const index = workspace.active_tab orelse return;
        if (index >= workspace.tabs.items.len) return;
        self.requestBroadcast(group, workspace.tabs.items[index].id);
    }

    fn broadcastFor(self: *AppNavHost, id: u32) ?*@import("../../workspace/model/broadcast_controller.zig").Approval {
        for (self.broadcasts.items) |*approval| if (approval.group_id == id) return approval;
        return null;
    }

    pub fn requestBroadcast(self: *AppNavHost, group_id: u32, source_id: u64) void {
        const workspace = self.workspace orelse return;
        const group = self.roster.findById(group_id) orelse return;
        const facts = self.broadcastFacts(group_id) catch |err| {
            workspace.statusFailure(@errorName(err));
            return;
        };
        defer self.allocator.free(facts);
        if (self.broadcastFor(group_id)) |old| {
            self.showBroadcast(old, facts);
            return;
        }
        var source: ?@import("../../workspace/model/broadcast_controller.zig").Fact = null;
        for (facts) |fact| if (fact.writable and self.application_host != null and self.application_host.?.legacyForHandle(fact.handle) == source_id) {
            source = fact;
            break;
        };
        if (source == null) for (facts) |fact| {
            if (fact.writable) {
                source = fact;
                break;
            }
        };
        var approval = @import("../../workspace/model/broadcast_controller.zig").prepare(self.allocator, group_id, group.membership_revision, source orelse {
            workspace.status("请选择已连接且可写的来源终端");
            return;
        }, facts) catch |err| {
            workspace.statusFailure(@errorName(err));
            return;
        };
        approval.source_selected = false;
        for (approval.targets) |*target| target.selected = false;
        self.broadcasts.append(self.allocator, approval) catch {
            var owned = approval;
            owned.deinit(self.allocator);
            return;
        };
        self.showBroadcast(self.broadcastFor(group_id).?, facts);
    }

    fn toggleMemberBroadcast(self: *AppNavHost, group_id: u32, source_id: u64) void {
        const application = self.application_host orelse return;
        const handle = application.ownerForLegacy(source_id) orelse return;
        const was_open = if (self.broadcast_view) |view| view.open.peek() else false;
        if (self.broadcastFor(group_id) == null) self.requestBroadcast(group_id, source_id);
        const approval = self.broadcastFor(group_id) orelse return;
        const facts = self.broadcastFacts(group_id) catch return;
        defer self.allocator.free(facts);
        const selected = !approval.participates(handle, facts);
        approval.setMember(self.allocator, handle, selected, facts) catch return;
        self.broadcast_epoch +|= 1;
        if (self.broadcast_view) |view| if (was_open) self.showBroadcast(approval, facts) else view.dismiss();
        self.cx.requestRedraw();
    }

    fn showBroadcast(self: *AppNavHost, approval: *@import("../../workspace/model/broadcast_controller.zig").Approval, facts: []const @import("../../workspace/model/broadcast_controller.zig").Fact) void {
        const workspace = self.workspace orelse return;
        const application = self.application_host orelse return;
        const group = self.roster.findById(approval.group_id) orelse return;
        const details = self.connection_details_host orelse return;
        const controls = details.ssh_status.controls orelse return;
        const BV = @import("../../workspace/view/broadcast_view.zig");
        if (self.broadcast_view == null) self.broadcast_view = BV.View.mount(self.cx, workspace.scope, .{ .context = self, .resolve = resolveBroadcast, .select = selectBroadcastMember }) catch return;
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const allocator = arena.allocator();
        var members: std.ArrayList(BV.Member) = .empty;
        for (group.members.items) |member| {
            const tab = workspace.sessionTab(member.pane_id) orelse continue;
            const owner = application.ownerForLegacy(tab.id);
            const source = workspace.active_tab != null and workspace.tabs.items[workspace.active_tab.?].id == tab.id;
            const selected = if (owner) |handle| approval.participates(handle, facts) else false;
            var available = false;
            if (owner) |handle| for (facts) |fact| if (fact.handle.eql(handle)) {
                available = fact.writable;
                break;
            };
            const unavailable_reason = if (owner == null) "无终端" else "不可写";
            const endpoint = if (tab.local) "本机 · zsh" else if (tab.host_snapshot) |host| std.fmt.allocPrint(allocator, "{s}@{s}:{d}", .{ host.value.user, host.value.host, host.value.port }) catch return else "无终端服务";
            members.append(allocator, .{ .id = tab.id, .owner = owner, .name = std.fmt.allocPrint(allocator, "{s} · #{d}", .{ tab.titleSlice(), tab.id }) catch return, .endpoint = endpoint, .source = source, .selected = selected, .available = available, .unavailable_reason = unavailable_reason }) catch return;
        }
        var hash = std.hash.Wyhash.init(approval.group_id);
        hash.update(group.name);
        std.hash.autoHash(&hash, approval.participantCount(facts));
        for (members.items) |member| {
            std.hash.autoHash(&hash, .{ member.id, member.owner, member.source, member.selected, member.available });
            hash.update(member.name);
            hash.update(member.endpoint);
        }
        const fingerprint = hash.final();
        if (self.broadcast_view.?.open.peek() and self.broadcast_view_fingerprint == fingerprint) return;
        self.broadcast_view_fingerprint = fingerprint;
        self.broadcast_view.?.show(.{ .group = approval.group_id, .name = group.name, .running = approval.participantCount(facts) > 0, .can_enable = for (facts) |fact| {
            if (fact.writable) break true;
        } else false, .members = members.items }, controls.broadcast_button) catch {};
    }

    fn selectBroadcastMember(raw: *anyopaque, group_id: u32, owner: @import("../../../host/identity.zig").SessionHandle, selected: bool) void {
        const self: *AppNavHost = @ptrCast(@alignCast(raw));
        const approval = self.broadcastFor(group_id) orelse return;
        const facts = self.broadcastFacts(group_id) catch return;
        defer self.allocator.free(facts);
        approval.setMember(self.allocator, owner, selected, facts) catch |err| {
            if (self.workspace) |workspace| workspace.statusFailure(@errorName(err));
            self.showBroadcast(approval, facts);
            return;
        };
        self.broadcast_epoch +|= 1;
        self.showBroadcast(approval, facts);
    }

    fn setMemberBroadcast(self: *AppNavHost, group_id: u32, session_id: u64, enabled: bool) !void {
        const workspace = self.workspace orelse return error.NoWorkspace;
        const application = self.application_host orelse return error.NoApplication;
        const handle = application.ownerForLegacy(session_id) orelse return error.EndedSession;
        if (!enabled and self.broadcastFor(group_id) == null) return;
        const was_open = if (self.broadcast_view) |view| view.open.peek() else false;
        if (self.broadcastFor(group_id) == null) self.requestBroadcast(group_id, session_id);
        const approval = self.broadcastFor(group_id) orelse return error.DisconnectedTerminal;
        const facts = try self.broadcastFacts(group_id);
        defer self.allocator.free(facts);
        try approval.setMember(self.allocator, handle, enabled, facts);
        const participating = approval.participates(handle, facts);
        if (workspace.sessionTab(session_id)) |tab| if (tab.terminal) |*terminal| {
            terminal.local_state.broadcast = participating;
        };
        workspace.setGroupMemberBroadcast(session_id, participating);
        self.broadcast_epoch +|= 1;
        if (self.broadcast_view) |view| if (was_open) self.showBroadcast(approval, facts) else view.dismiss();
        self.cx.requestRedraw();
    }

    fn resolveBroadcast(raw: *anyopaque, group_id: u32, accepted: bool) void {
        const self: *AppNavHost = @ptrCast(@alignCast(raw));
        const approval = self.broadcastFor(group_id) orelse return;
        if (!accepted) return;
        const facts = self.broadcastFacts(group_id) catch return;
        defer self.allocator.free(facts);
        if (approval.participantCount(facts) > 0) {
            // A batch stop clears captured selections even when a member has
            // temporarily disappeared from the current terminal snapshot.
            approval.source_selected = false;
            for (approval.targets) |*target| target.selected = false;
            approval.enabled = false;
        } else {
            for (facts) |fact| if (fact.writable) {
                approval.setMember(self.allocator, fact.handle, true, facts) catch continue;
            };
        }
        self.broadcast_epoch +|= 1;
        self.showBroadcast(approval, facts);
    }

    pub fn stopBroadcast(self: *AppNavHost, group_id: u32) void {
        if (self.workspace) |workspace| if (self.roster.findById(group_id)) |group| for (group.members.items) |member| {
            if (workspace.sessionTab(member.pane_id)) |tab| {
                if (tab.terminal) |*terminal| {
                    terminal.local_state.broadcast = false;
                }
            }
            workspace.setGroupMemberBroadcast(member.pane_id, false);
        };
        for (self.broadcasts.items, 0..) |*approval, index| if (approval.group_id == group_id) {
            if (self.application_host) |application| if (application.legacyForHandle(approval.source.handle)) |id| {
                if (self.workspace.?.sessionTab(id)) |tab| if (tab.terminal) |*view| {
                    view.local_state.broadcast = false;
                };
            };
            approval.deinit(self.allocator);
            _ = self.broadcasts.orderedRemove(index);
            self.broadcast_epoch +|= 1;
            break;
        };
        if (self.broadcast_view) |view| if (view.group_id == group_id) view.dismiss();
        self.cx.requestRedraw();
    }

    pub fn onServiceBroadcast(raw: ?*anyopaque, source: @import("../../../host/identity.zig").SessionHandle, event: u64, payload: @import("../../workspace/model/broadcast_event.zig").Payload) void {
        const self: *AppNavHost = @ptrCast(@alignCast(raw orelse return));
        var context = BroadcastSend{ .host = self, .payload = payload };
        defer context.seen.deinit(self.allocator);
        for (self.broadcasts.items) |*approval| {
            if (!approval.enabled) continue;
            const facts = self.broadcastFacts(approval.group_id) catch continue;
            defer self.allocator.free(facts);
            approval.dispatchMembers(source, event, facts, &context, BroadcastSend.send) catch |err| {
                if (self.workspace) |workspace| workspace.status(switch (err) {
                    error.StaleSource => "广播输入未发送：来源会话状态已变化，可在卡片重新开启。",
                    error.DisconnectedTerminal, error.EndedSession => "广播输入未发送：接收会话已断开。",
                    error.PendingPaste => "广播输入未发送：接收会话有待确认的粘贴，请先处理。",
                    else => @errorName(err),
                });
            };
            if (self.broadcast_view) |view| if (view.group_id == approval.group_id and view.open.get()) self.showBroadcast(approval, facts);
        }
    }

    const BroadcastSend = struct {
        host: *AppNavHost,
        payload: @import("../../workspace/model/broadcast_event.zig").Payload,
        seen: std.ArrayList(@import("../../../host/identity.zig").SessionHandle) = .empty,
        fn send(raw: *anyopaque, handle: @import("../../../host/identity.zig").SessionHandle) !void {
            const self: *BroadcastSend = @ptrCast(@alignCast(raw));
            for (self.seen.items) |previous| if (previous.eql(handle)) return;
            try self.seen.append(self.host.allocator, handle);
            const workspace = self.host.workspace orelse return error.NoWorkspace;
            const application = self.host.application_host orelse return error.UnsupportedService;
            const capabilities = (try application.sessions.capabilitySnapshot(handle)) orelse return error.StaleOwner;
            if (!@import("../../../host/actions.zig").project(.toggle_broadcast, capabilities).enabled) return error.CapabilityUnavailable;
            for (workspace.tabs.items) |tab| {
                if (application.legacyForHandle(handle) != tab.id or tab.terminal == null) continue;
                if (tab.terminal.?.terminal_surface == null) {
                    const view = &tab.terminal.?;
                    const runtime = tab.runtime orelse return error.EndedSession;
                    const bytes = switch (self.payload) {
                        .bytes => |value| try self.host.allocator.dupe(u8, value),
                        .key => |key| try runtime.encodeKey(key, self.host.allocator),
                        .paste => |value| blk: {
                            var projection = try runtime.copyProjection(self.host.allocator);
                            defer projection.deinit(self.host.allocator);
                            break :blk if (projection.modes.bracketed_paste) try std.mem.concat(self.host.allocator, u8, &.{ "\x1b[200~", value, "\x1b[201~" }) else try self.host.allocator.dupe(u8, value);
                        },
                    };
                    defer self.host.allocator.free(bytes);
                    try view.receiveBroadcast(bytes);
                    return;
                }
                const surface = tab.terminal.?.terminal_surface.?;
                if (!surface.owner.eql(handle) or tab.terminal.?.history.selected != null) return error.StaleOwner;
                if (surface.pending_paste != null or surface.paste_requested != null or surface.pending.items.len > 0) return error.PendingPaste;
                const status = try surface.service.status();
                if (!status.writable or !status.owner.eql(handle)) return error.ReadOnlyTerminal;
                const sequence = surface.next_input;
                // Reserve the sequence before submission so no accepted target is repeated.
                surface.next_input = try std.math.add(u64, surface.next_input, 1);
                switch (self.payload) {
                    .bytes => |bytes| {
                        _ = try surface.service.write(.{ .input_sequence = sequence, .mode_revision = status.mode_revision, .bytes = bytes });
                    },
                    .key => |key| {
                        _ = try surface.service.writeKey(.{ .input_sequence = sequence, .mode_revision = status.mode_revision, .event = key });
                    },
                    .paste => |text| {
                        var paste = try surface.service.preparePaste(self.host.allocator, text);
                        defer paste.deinit(self.host.allocator);
                        _ = try surface.service.commitPaste(paste, sequence, true);
                    },
                }
                return;
            }
            return error.EndedSession;
        }
    };

    pub fn broadcastPasteStamp(raw: ?*anyopaque, source: @import("../../../host/identity.zig").SessionHandle) u64 {
        const self: *AppNavHost = @ptrCast(@alignCast(raw orelse return 0));
        var hash = std.hash.Wyhash.init(self.broadcast_epoch);
        var found = false;
        for (self.broadcasts.items) |approval| {
            if (!approval.enabled) continue;
            const group = self.roster.findById(approval.group_id) orelse return 1;
            std.hash.autoHash(&hash, group.membership_revision);
            const facts = self.broadcastFacts(approval.group_id) catch return 1;
            defer self.allocator.free(facts);
            if (!approval.participates(source, facts)) continue;
            found = true;
            for (facts) |fact| {
                std.hash.autoHash(&hash, fact);
            }
        }
        return if (found) hash.final() else 0;
    }

    pub fn onTerminalInput(raw: ?*anyopaque, source: *TerminalViewNode, bytes: []const u8) void {
        const self: *AppNavHost = @ptrCast(@alignCast(raw orelse return));
        const workspace = self.workspace orelse return;
        const application = self.application_host orelse return;
        for (workspace.tabs.items) |tab| {
            if (tab.terminal == null or &tab.terminal.? != source) continue;
            const owner = application.ownerForLegacy(tab.id) orelse return;
            source.broadcast_event = std.math.add(u64, source.broadcast_event, 1) catch return;
            onServiceBroadcast(raw, owner, source.broadcast_event, .{ .bytes = bytes });
            return;
        }
    }

    pub fn bindGroupWorkspace(self: *AppNavHost, workspace: *ws.Workspace) void {
        workspace.group_roster = &self.roster;
        workspace.group_action_context = self;
        workspace.group_action = groupWorkspaceAction;
        workspace.ai_grouping_bridge = .{ .context = self, .prepare = prepareTabGrouping, .commit = commitTabGrouping, .capture = captureTabGrouping, .settle = settleTabGrouping, .release = releaseTabGrouping };
    }
    fn captureTabGrouping(raw: *anyopaque, source: u64, target: ?u64) !@import("../../../ai/tab_grouping.zig").Settlement {
        const self: *AppNavHost = @ptrCast(@alignCast(raw));
        if (self.ai) |ai| if (ai.assistant_states) |store| return @import("../../../ai/tab_grouping.zig").capture(store, source, target);
        return .{ .operation = @import("../../../host/identity.zig").HostOperationId.generate() };
    }
    fn settleTabGrouping(raw: *anyopaque, intent: @import("../../../ai/tab_grouping.zig").Settlement) !bool {
        const self: *AppNavHost = @ptrCast(@alignCast(raw));
        if (self.ai) |ai| if (ai.assistant_states) |store| return @import("../../../ai/tab_grouping.zig").settle(store, intent);
        return true;
    }
    fn releaseTabGrouping(raw: *anyopaque, intent: @import("../../../ai/tab_grouping.zig").Settlement) void {
        const self: *AppNavHost = @ptrCast(@alignCast(raw));
        if (self.ai) |ai| if (ai.assistant_states) |store| @import("../../../ai/tab_grouping.zig").release(store, intent);
    }
    fn prepareTabGrouping(raw: *anyopaque, drop: @import("../../../ai/tab_grouping.zig").Drop) !@import("../../../ai/tab_grouping.zig").Plan {
        const self: *AppNavHost = @ptrCast(@alignCast(raw));
        const ai = self.ai orelse return .{ .group = drop.group, .container = drop.container };
        const store = if (ai.assistant_states) |value| value else return .{ .group = drop.group, .container = drop.container };
        return @import("../../../ai/tab_grouping.zig").prepare(store, drop);
    }
    fn commitTabGrouping(raw: *anyopaque, plan: @import("../../../ai/tab_grouping.zig").Plan) void {
        const self: *AppNavHost = @ptrCast(@alignCast(raw));
        if (self.ai) |ai| ai.commitTabGrouping(plan);
    }

    fn groupWorkspaceAction(raw: ?*anyopaque, group_id: u32, session_id: u64, action: ws.GroupAction) void {
        const self: *AppNavHost = @ptrCast(@alignCast(raw orelse return));
        const workspace = self.workspace orelse return;
        if (action == .stop_broadcast) {
            self.stopBroadcast(group_id);
            return;
        }
        if (action == .stop_group_ai) {
            if (self.ai) |ai| {
                if (ai.execution().request_owner) |owner| if (ai.ownerContent(owner)) |held| if (held == .group and held.group == group_id) ai.cancelRef().cancel();
                _ = ai.execution().tool_bridge.stopGroup(group_id);
                ai.cx.requestRedraw();
            }
            return;
        }
        if (workspace.groupClosing(group_id)) {
            workspace.status("组正在关闭，暂不能修改成员");
            return;
        }
        const group = self.roster.findById(group_id) orelse return;
        switch (action) {
            .pin => {
                self.roster.pin(group.name, if (group.pinned_pane == session_id) null else session_id) catch |err| {
                    workspace.statusFailure(@errorName(err));
                    return;
                };
                workspace.refreshGroup(group_id);
            },
            .leave => {
                // M4：离开组 = 回到独立 tab，读卡片类型的 standalone_tab 约束。
                if (!workspace.canLeaveSplit(session_id)) return workspace.statusFailure("PlacementNotAllowed");
                self.roster.leave(group.name, session_id) catch |err| {
                    workspace.statusFailure(@errorName(err));
                    return;
                };
                workspace.refreshGroup(group_id);
            },
            .close_member => if (workspace.tabIndex(session_id)) |index| workspace.requestCloseTab(index),
            .broadcast => self.requestBroadcast(group_id, session_id),
            .toggle_broadcast => self.toggleMemberBroadcast(group_id, session_id),
            .split_side, .split_stack => {
                if (workspace.tabIndex(session_id)) |index| workspace.setActiveTab(index);
                workspace.splitGroup(&self.roster, action == .split_stack) catch |err| workspace.statusFailure(@errorName(err));
            },
            .stop_broadcast, .stop_group_ai => unreachable,
        }
    }

    fn finishOwnedCommand(self: *AppNavHost, owner: @import("../../../host/identity.zig").SessionHandle, id: u64, state: TerminalViewNode.CommandRecordState, text: []const u8) void {
        const workspace = self.workspace orelse return;
        for (workspace.tabs.items) |tab| {
            if (tab.terminal) |*terminal| if (terminal.commandRecordOwner()) |current| {
                if (current.eql(owner)) {
                    _ = terminal.finishCommandRecord(owner, id, state, text);
                    return;
                }
            };
        }
    }
    fn pollCommandCreations(self: *AppNavHost) void {
        const application = self.application_host orelse return;
        var i: usize = 0;
        while (i < self.pending_command_creations.items.len) {
            const pending = &self.pending_command_creations.items[i];
            const snapshot = application.sessions.queryState(pending.created);
            if (snapshot) |state| switch (state.lifecycle) {
                .creating, .ready => {
                    i += 1;
                    continue;
                },
                .attached => self.finishOwnedCommand(pending.source, pending.command_id, .success, "新会话已连接"),
                else => {
                    const failure = for (application.mappings.items) |*mapping| {
                        if (mapping.handle.eql(pending.created) and mapping.failure_len > 0) break mapping.failure[0..mapping.failure_len];
                    } else "新会话未建立，连接详情保留在目标页签";
                    self.finishOwnedCommand(pending.source, pending.command_id, .failure, failure);
                },
            } else self.finishOwnedCommand(pending.source, pending.command_id, .failure, "新会话已失效");
            _ = self.pending_command_creations.orderedRemove(i);
        }
    }
    pub fn builtinParameterCandidates(raw: ?*anyopaque, command: []const u8, a: std.mem.Allocator) ![]const []const u8 {
        const self: *AppNavHost = @ptrCast(@alignCast(raw orelse return error.NoWorkspace));
        const workspace = self.workspace orelse return error.NoWorkspace;
        var names: std.ArrayList([]const u8) = .empty;
        if (std.mem.eql(u8, command, "@new")) {
            try names.append(a, "--pick");
            for (workspace.registry.hosts) |host| try names.append(a, host.name);
        } else if (std.mem.eql(u8, command, "@grp")) {
            try names.appendSlice(a, &.{ "off", "leave" });
            for (self.roster.groups.items) |group| try names.append(a, group.name);
        }
        return names.toOwnedSlice(a);
    }
    pub fn onLocalCommandFrom(raw: ?*anyopaque, origin: *TerminalViewNode, text: []const u8, executed: bool) void {
        const self: *AppNavHost = @ptrCast(@alignCast(raw orelse return));
        const workspace = self.workspace orelse return;
        const application = self.application_host orelse return;
        const owner = origin.commandRecordOwner();
        const command_id = origin.active_command_record;
        const parsed = @import("../../../vt/builtin_commands.zig").parse(text);
        const creates = switch (parsed) {
            .new_session, .duplicate => true,
            else => false,
        };
        if (creates and owner != null and command_id != null) self.pending_command_creations.ensureUnusedCapacity(self.allocator, 1) catch {
            _ = origin.finishCommandRecord(owner.?, command_id.?, .failure, "无法记录新会话结果");
            return;
        };
        for (workspace.tabs.items, 0..) |tab, index| {
            if (tab.terminal == null or &tab.terminal.? != origin or (tab.closing and parsed != .ai and parsed != .command_history)) continue;
            workspace.setActiveTab(index);
            const before = application.sessions.sessions.items.len;
            workspace.command_output = origin;
            defer workspace.command_output = null;
            onLocalCommand(raw, text, executed);
            if (!executed) return;
            if (parsed == .new_session and parsed.new_session.len > 0 and application.sessions.sessions.items.len == before) return;
            if (parsed == .upload or parsed == .download or parsed == .ai or parsed == .command_history or parsed == .sync) return;
            if (owner) |source| if (command_id) |id| {
                if (creates and application.sessions.sessions.items.len > before) {
                    const created = application.sessions.sessions.items[before].handle;
                    self.pending_command_creations.appendAssumeCapacity(.{ .source = source, .command_id = id, .created = created });
                    self.finishOwnedCommand(source, id, .pending, "正在建立新会话…");
                } else {
                    self.finishOwnedCommand(source, id, .success, switch (parsed) {
                        .help => "已打开内置指令帮助",
                        .ai => "已打开 AI 助手",
                        .group => "已加入终端组",
                        .pin => "已更新组内置顶状态",
                        .sync => "已更新本会话广播状态",
                        .theme => "已打开 设置 › 外观",
                        .socks => "已提交 SOCKS5 转发请求",
                        else => "内置指令已执行",
                    });
                }
            };
            return;
        }
    }
    fn commandFailure(self: *AppNavHost, text: []const u8) void {
        const workspace = self.workspace orelse return;
        if (workspace.command_output) |terminal| {
            if (terminal.commandRecordOwner()) |owner| if (terminal.active_command_record) |id| {
                _ = terminal.finishCommandRecord(owner, id, .failure, text);
                return;
            };
        }
        workspace.statusFailure(text);
    }
    fn commandSuccess(self: *AppNavHost, text: []const u8) void {
        const workspace = self.workspace orelse return;
        if (workspace.command_output) |terminal| {
            if (terminal.commandRecordOwner()) |owner| if (terminal.active_command_record) |id| {
                _ = terminal.finishCommandRecord(owner, id, .success, text);
                return;
            };
        }
        workspace.status(text);
    }
    pub fn onLocalCommand(raw: ?*anyopaque, text: []const u8, executed: bool) void {
        const self: *AppNavHost = @ptrCast(@alignCast(raw orelse return));
        if (!executed) return;
        const workspace = self.workspace orelse return;
        const active = workspace.active_tab orelse return;
        if (active >= workspace.tabs.items.len) return;
        switch (@import("../../../vt/builtin_commands.zig").parse(text)) {
            .new_session => |target| {
                if (std.mem.eql(u8, target, "--pick")) {
                    self.showSessionMenu();
                    self.builtin_new_group = workspace.active_group_view;
                    self.commandSuccess("请选择本地终端或已保存的主机");
                } else if (target.len == 0) {
                    workspace.newSessionFromTab(active) catch |err| workspace.statusFailure(@errorName(err));
                } else {
                    var match: ?usize = null;
                    for (workspace.registry.hosts, 0..) |host, index| if (std.mem.eql(u8, host.name, target)) {
                        if (match != null) {
                            self.commandFailure("存在同名主机，请使用 @new --pick 选择");
                            return;
                        }
                        match = index;
                    };
                    const index = match orelse {
                        self.commandFailure("找不到该主机，可使用 @new --pick 选择");
                        return;
                    };
                    const previous = workspace.creation_group;
                    workspace.creation_group = workspace.active_group_view;
                    defer workspace.creation_group = previous;
                    workspace.newSession(index) catch |err| self.commandFailure(@errorName(err));
                }
            },
            .command_history => |enabled| {
                const history = self.command_history orelse {
                    workspace.statusFailure("命令历史暂不可用");
                    return;
                };
                if (enabled) |show| history.show(show) else history.toggle();
                self.commandSuccess(if (history.mode == .closed) "已隐藏命令历史" else "已打开命令历史");
            },
            .help => {
                if (workspace.command_output != null) {
                    var buffer: [4096]u8 = undefined;
                    const help = @import("../../terminal/model/builtin_dispatch.zig").formatHelp(self.allocator, &buffer) catch |err| {
                        workspace.statusFailure(@errorName(err));
                        return;
                    };
                    self.commandSuccess(help);
                } else if (self.help_open) |help| {
                    self.cx.dispatcher.cancelScrollGesture();
                    help.set(true);
                } else workspace.status("内置指令帮助暂不可用");
            },
            .ai => |question| if (self.ai) |ai| {
                if (ai.currentBinding() == null) {
                    workspace.statusFailure("当前页签暂不支持 AI 助手");
                    return;
                }
                ai.syncOwner() catch |err| {
                    workspace.statusFailure(@errorName(err));
                    return;
                };
                if (!ai.controller.model.visible) ai.toggle();
                if (question.len > 0) {
                    const previous = ai.prompt.peek();
                    const draft = std.fmt.allocPrint(self.allocator, "{s}{s}{s}", .{ previous, if (previous.len == 0) "" else "\n", question }) catch {
                        workspace.status("无法保留 AI 问题草稿");
                        return;
                    };
                    defer self.allocator.free(draft);
                    ai.prompt.set(draft);
                    ai.promptChanged(ai.prompt.peek());
                }
                ai.focusComposer();
                self.commandSuccess("已打开 AI 助手");
            } else workspace.statusFailure("AI 运维助手暂不可用"),
            .upload => |source| if (self.transfer_host) |transfer| {
                transfer.requestCommandTransfer(active, .upload, source) catch |err| self.commandFailure(@errorName(err));
            } else self.commandFailure("传输面板暂不可用"),
            .download => |download| if (self.transfer_host) |transfer| {
                transfer.requestCommandTransfer(active, .download, download.remote_path) catch |err| self.commandFailure(@errorName(err));
            } else self.commandFailure("传输面板暂不可用"),
            .group => |name| {
                if (name.len == 0) {
                    workspace.status("@grp 需要组名");
                    return;
                }
                const pane_id: ws.SessionId = workspace.tabs.items[active].id;
                self.bindGroupWorkspace(workspace);
                if (workspace.active_group_view) |id| if (workspace.groupClosing(id)) {
                    workspace.status("组正在关闭，暂不能修改成员");
                    return;
                };
                if (std.ascii.eqlIgnoreCase(name, "off") or std.ascii.eqlIgnoreCase(name, "leave")) {
                    if (!workspace.canLeaveSplit(pane_id)) return self.commandFailure("当前卡片不能单独成为页签");
                    const old_group = workspace.active_group_view;
                    const removed = self.roster.leavePane(pane_id);
                    if (old_group) |id| workspace.refreshGroup(id);
                    workspace.selectTab(active);
                    self.commandSuccess(if (removed) "已退出终端组" else "当前未加入该组");
                } else {
                    if (self.roster.find(name)) |existing| if (workspace.groupClosing(existing.id)) {
                        workspace.status("组正在关闭，暂不能修改成员");
                        return;
                    };
                    const joined = self.roster.join(name, pane_id, 0xff1351f6) catch {
                        workspace.statusFailure("加入终端组失败");
                        return;
                    };
                    workspace.openGroup(&self.roster, joined.id) catch |err| workspace.statusFailure(@errorName(err));
                }
            },
            .duplicate => workspace.duplicateSessionFromTab(active) catch |err| workspace.statusFailure(@errorName(err)),
            .pin => {
                // Pin only changes member presentation order.
                const pane_id: ws.SessionId = workspace.tabs.items[active].id;
                var found = false;
                var names: [64][]const u8 = undefined;
                var name_count: usize = 0;
                for (self.roster.groups.items) |group| {
                    if (!group.contains(pane_id)) continue;
                    if (name_count == names.len) break;
                    names[name_count] = group.name;
                    name_count += 1;
                }
                for (names[0..name_count]) |name| {
                    const group = self.roster.find(name) orelse continue;
                    const next: ?u64 = if (group.pinned_pane == pane_id) null else pane_id;
                    self.roster.pin(name, next) catch |err| {
                        workspace.statusFailure(@errorName(err));
                        continue;
                    };
                    workspace.refreshGroup(group.id);
                    found = true;
                }
                if (!found) workspace.status("当前会话未加入终端组") else self.commandSuccess(if (name_count > 0 and (self.roster.find(names[0]).?.pinned_pane == pane_id)) "已置顶当前会话" else "已取消会话置顶");
            },
            .socks => |request| if (self.socks_host) |socks| {
                const original = workspace.tabs.items[active].id;
                if (request.enabled) {
                    if (!socks.hasLive(original)) socks.commandToggle(request.port);
                } else if (socks.hasLive(original)) {
                    _ = socks.stopForSession(original);
                } else {
                    self.commandSuccess("SOCKS5 转发当前已停止");
                }
            } else workspace.status("SOCKS5 转发暂不可用"),
            .literal => |literal| if (workspace.tabs.items[active].terminal) |*terminal| {
                _ = terminal.pushText(literal);
            },
            // These commands are applied inside TerminalViewNode before the
            // workspace observer is normally called. Keep explicit cases so
            // the observer remains exhaustive if a caller routes one here.
            .sync => |enabled| {
                const source_id = workspace.tabs.items[active].id;
                var found = false;
                for (self.roster.groups.items) |group| if (group.contains(source_id)) {
                    found = true;
                    self.setMemberBroadcast(group.id, source_id, enabled) catch |err| {
                        self.commandFailure(switch (err) {
                            error.InvalidSource, error.DisconnectedTerminal => "当前会话未就绪，无法开启广播",
                            else => @errorName(err),
                        });
                        return;
                    };
                    self.commandSuccess(if (enabled) "本会话广播已开启" else "本会话广播已关闭");
                    break;
                };
                if (!found) self.commandFailure("请先加入终端组");
            },
            // 主题入口只有 设置 › 外观 与菜单栏“显示 › 外观…”：@theme（带不带名称）都只打开设置的外观页，
            // 不在终端里直接切换主题（copy-terms，用户拍板）。
            .theme => showThemeFromMenu(self),
            .timestamp, .log, .shell, .dots => {},
            .invalid => |invalid| workspace.status(switch (invalid.reason) {
                .missing_parameter => "命令缺少必要参数",
                .unexpected_parameter => "命令参数不符合设计格式",
                .invalid_switch => "命令开关只支持 on/off",
                .invalid_port => "端口参数无效",
                .invalid_path => "路径参数无效",
            }),
            .not_command => workspace.status("未知本地命令，未发送到远端"),
        }
        self.cx.requestRedraw();
    }
};

pub const NavClick = struct {
    host: *AppNavHost,
    kind: enum { sidebar, quick_connect, wizard, transfer, session_menu },
};

pub fn onNavClick(raw: *anyopaque) void {
    const ctx: *NavClick = @ptrCast(@alignCast(raw));
    switch (ctx.kind) {
        .session_menu => ctx.host.showSessionMenu(),
        .sidebar => ctx.host.toggleSidebar(),
        .quick_connect => ctx.host.toggleQuickConnect(),
        .wizard => if (ctx.host.wizard) |wiz| wiz.show(),
        .transfer => if (ctx.host.transfer_host) |th| th.toggleManager(),
    }
}

