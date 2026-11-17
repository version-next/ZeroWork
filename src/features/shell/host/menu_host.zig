//! 会话菜单宿主 MenuHost（P2 自 src/main.zig 拆出；menus 包改为只用原生 `W.Menu`）。
//!
//! 侧栏主机右键、页签右键、终端中键、会话结束横幅共用一个原生菜单（面板 `context.menu`），终端右键是另一个
//! （面板 `terminal.menu`，design-r3 B1）。两者都经 `shell/view/app_menu.zig` 挂载与投影：条目只来自
//! `workspace/model/context_menus.zig` 的声明，排列、分隔线、快捷键文字由 `model/menu_spec.zig` 统一给出。
//! 选中只把动作 id 交回这里，由 `runCapturedAction` 对打开菜单时捕获的对象执行；危险项的确认归动作的执行方。

const std = @import("std");
const applog = @import("../../../platform/applog.zig");
const ui = @import("ui");
const ws = @import("../../workspace/view/workspace.zig");
const hosts_mod = @import("../../../config/hosts.zig");
const wizard_mod = @import("../../connections/wizard/view/wizard.zig");
const TerminalViewNode = @import("../../terminal/view/terminal_view.zig").TerminalViewNode;
const MenuState = @import("../../workspace/model/context_menu_state.zig").State;
const MenuTrigger = @import("../../workspace/model/context_menu_state.zig").Trigger;
const ai_attachments = @import("../../../ai/local_text_attachments.zig");
const app_theme = @import("../../../shared/ui/theme/app_theme.zig");
const HistoryHost = @import("../../history/host/history_host.zig").Host;
const process_state = @import("../../../app/process_state.zig");
const AiHost = @import("../../ai/host/ai_host.zig").AiHost;
const SettingsHost = @import("../../settings/host/settings_host.zig").SettingsHost;
const TransferHost = @import("../../transfer/host/transfer_host.zig").TransferHost;
const WizardHost = @import("../../connections/wizard/host/wizard_host.zig").WizardHost;
const app_menu = @import("../view/app_menu.zig");

const menus = @import("../../workspace/model/context_menus.zig");

const shortcut_router = @import("../model/shortcut_router.zig");

pub const MenuHost = struct {
    /// 菜单项右侧的快捷键文字从这个路由取（键位读本窗口的 `[keys]`）。
    fn shortcuts(self: *const MenuHost) shortcut_router.Router {
        const defaults = struct {
            const map: shortcut_router.Map = .{};
        };
        return .{ .keys = if (self.workspace) |workspace| &workspace.app_config.keys else &defaults.map };
    }

    pending_sidebar_action: ?struct { owner: @import("../../../host/identity.zig").AssetOwner, action: @import("../view/sidebar_view.zig").HostAction } = null,

    allocator: std.mem.Allocator,
    cx: *ui.Cx,
    state: MenuState = .{},
    workspace: ?*ws.Workspace = null,
    ai: ?*AiHost = null,
    command_history: ?*@import("../../terminal/view/command_history_view.zig").View = null,
    wizard: ?*wizard_mod.Wizard = null,
    wizard_host: ?*WizardHost = null,
    edit_host_index: ?usize = null,
    /// Host registry index when the menu targets a sidebar row.
    context_host: ?usize = null,
    /// Tab index when the menu targets the tab strip.
    context_tab: ?usize = null,
    connection_details_host: ?*@import("../../connections/progress/host/connection_details_host.zig").Host = null,
    anchor: ui.ComputedRect = .{ .x = 0, .y = 40, .w = 0, .h = 0 },
    history_host: ?*HistoryHost = null,
    captured_tab: ?@import("../../../host/identity.zig").TabId = null,
    captured_owner: ?@import("../../../host/identity.zig").ContentOwner = null,
    captured_terminal_intent: ?AiHost.TerminalIntent = null,
    captured_host: ?ws.HostId = null,
    captured_asset: ?@import("../../../host/identity.zig").AssetOwner = null,
    captured_group_target: ?@import("../../../host/identity.zig").TabId = null,
    asset_action_view: ?*@import("../../connections/assets/view/asset_action_view.zig").View = null,
    /// Raised by the window's theme publication; the asset action card repaints when shown.
    asset_action_theme: @import("../../../shared/ui/theme/theme_watch.zig").ThemeWatch = .{},
    sidebar_search_value: ?*ui.Signal([]const u8) = null,
    using_capture: bool = false,
    settings: ?*SettingsHost = null,
    transfer_host: ?*TransferHost = null,
    /// 页签菜单“会话连接”（title-click）：为这个页签打开会话连接卡片（点击语义）。
    session_identity_context: ?*anyopaque = null,
    session_identity: ?*const fn (*anyopaque, usize) void = null,
    background_socks: ?*@import("../../connections/socks/host/socks_background_host.zig").Host = null,
    /// 侧栏主机 / 页签 / 中键 / 会话结束的原生菜单（面板 `context.menu`）；`mountMenus` 之前为 null。
    context_menu: ?*app_menu.AppMenu = null,
    /// 终端右键菜单（原生 `W.Menu`，design-r3 B1，面板 `terminal.menu`）。
    terminal_menu: ?*app_menu.AppMenu = null,
    /// 当前打开菜单的条目（条目借用这里的字符串与子菜单，直到下一次打开）。
    entries: menus.Entries = .{},

    fn show(self: *MenuHost, trigger: MenuTrigger) void {
        self.showWith(trigger, null, null);
    }

    /// Full trigger entry: carries the sidebar host / tab strip context the
    /// actions need (open a session for host N, close tab M, …).
    fn showWith(self: *MenuHost, trigger: MenuTrigger, host_index: ?usize, tab_index: ?usize) void {
        // Terminal right click (design-r3 B1) opens its own menu at the pointer; the full menu stays on
        // middle click. Direct paste (设置 › 右键行为) never reaches here: the workspace declines and the
        // terminal pastes itself.
        if (trigger == .terminal_right_click) {
            if (self.context_menu) |menu| menu.hide();
        } else if (self.terminal_menu) |menu| menu.hide();
        if (self.workspace) |workspace| workspace.setTabMenuOpen(true);
        const kind = @import("../../workspace/model/context_menu_state.zig").kindFor(trigger);
        self.context_host = if (kind == .host_asset) host_index else null;
        self.captured_host = if (self.context_host) |index| if (self.workspace) |workspace| workspace.hostId(index) else null else null;
        self.captured_asset = if (self.context_host) |index| if (self.workspace) |workspace| if (index < workspace.registry.hosts.len) workspace.registry.hosts[index].owner() else null else null else null;
        self.context_tab = tab_index orelse if (kind != .host_asset) if (self.workspace) |workspace| workspace.active_tab else null else null;
        self.captured_tab = null;
        self.captured_owner = null;
        self.captured_terminal_intent = null;
        self.captured_group_target = if (self.workspace) |workspace| workspace.currentGroupTarget() else null;
        if (self.workspace) |workspace| if (self.context_tab) |index| if (index < workspace.tabs.items.len) {
            self.captured_tab = workspace.tabs.items[index].tab_id;
            self.captured_owner = workspace.tabs.items[index].content_owner;
            if (kind == .terminal) self.captured_terminal_intent = self.terminalIntent(index);
        };
        self.state.show(kind, .{
            .capability_snapshot = self.capabilitiesForTab(self.context_tab),
            .has_saved_connection = if (self.workspace) |workspace| if (self.context_tab) |index| workspace.savedConnectionForTab(index) != null else null else null,
            .has_unsaved_connection = if (self.context_tab) |index| self.unsavedConnectionForTab(index) != null else false,
            .new_window_available = process_state.process_windows != null and (self.captured_asset != null or self.captured_tab != null),
            .reuse_connection_available = if (self.context_tab) |index| if (self.workspace) |workspace| workspace.tabs.items[index].runtime != null else false else false,
            .local_session = self.isLocalTarget(),
            .read_only = self.localTargetReadonly(),
            .transfer_available = self.transferTargetAvailable(),
            .has_selection = self.activeHasSelection() and (kind != .terminal or self.captured_terminal_intent != null),
            .multi_tabs = if (self.workspace) |w| w.model.tabs.items.len > 1 else false,
            .background_socks = self.backgroundAvailable(),
            .background_active = if (self.background_socks) |background| if (self.captured_asset) |asset| background.hasAsset(asset) else false else false,
            .group_target_available = self.captured_group_target != null,
            .single_session = if (self.workspace) |workspace| workspace.active_group_view == null else false,
            .plugin_disabled = if (self.workspace) |workspace| if (self.context_host) |index| index < workspace.registry.hosts.len and workspace.disabledPlugin(workspace.registry.hosts[index]) != null else false else false,
        });
        if (trigger == .terminal_right_click) {
            const menu = self.terminal_menu orelse return self.declined();
            menu.show(menus.rightClickEntries(self.state.context, &self.entries), self.shortcuts(), .{ .x = self.anchor.x, .y = self.anchor.y, .w = 0, .h = 0 });
            return;
        }
        const menu = self.context_menu orelse return self.declined();
        const extra: menus.Extra = .{
            .host_name = if (self.captured_asset) |owner| if (self.workspace) |workspace| if (workspace.registry.get(owner)) |host| host.name else |_| "" else "" else "",
            .host_pinned = if (self.captured_asset) |owner| if (self.workspace) |workspace| if (workspace.registry.get(owner)) |host| host.pinned else |_| false else false else false,
            .tab_color = if (kind == .tab) if (self.workspace) |workspace| if (self.captured_tab) |id| workspace.tabColorChoice(id) else null else null else null,
        };
        // Sidebar rows: the menu opens to the right of the row's top edge; tabs: under the tab; the pointer
        // otherwise (a zero-size rectangle at the press point).
        const rect: ui.ComputedRect = if (kind == .host_asset) .{ .x = self.anchor.x + self.anchor.w, .y = self.anchor.y, .w = 0, .h = 0 } else self.anchor;
        menu.show(menus.entries(kind, self.state.context, extra, &self.entries), self.shortcuts(), rect);
    }
    fn declined(self: *MenuHost) void {
        if (self.workspace) |workspace| workspace.setTabMenuOpen(false);
        self.state.dismiss();
    }

    /// MenuBridge callback: (ctx, trigger, host_index, tab_index, multi_tabs).
    pub fn sidebarAction(ctx: ?*anyopaque, index: usize, action: @import("../view/sidebar_view.zig").HostAction) void {
        const self: *MenuHost = @ptrCast(@alignCast(ctx orelse return));
        const workspace = self.workspace orelse return;
        if (index >= workspace.registry.hosts.len) return;
        self.pending_sidebar_action = .{ .owner = workspace.registry.hosts[index].owner(), .action = action };
        self.cx.requestRedraw();
    }
    pub fn drainSidebarAction(self: *MenuHost) void {
        const pending = self.pending_sidebar_action orelse return;
        self.pending_sidebar_action = null;
        const workspace = self.workspace orelse return;
        _ = workspace.registry.get(pending.owner) catch return;
        const index = workspace.registry.indexOf(pending.owner.id) orelse return;
        self.hide();
        self.context_host = index;
        self.captured_host = workspace.hostId(index);
        self.captured_asset = pending.owner;
        self.context_tab = null;
        self.captured_tab = null;
        self.captured_owner = null;
        self.runCapturedAction(if (pending.action == .copy) .clone_host else .edit_host);
    }
    pub fn bridgeFire(ctx: ?*anyopaque, trigger: MenuTrigger, host_index: usize, tab_index: ?usize, multi_tabs: bool, anchor: ui.ComputedRect) void {
        const self: *MenuHost = @ptrCast(@alignCast(ctx orelse return));
        _ = multi_tabs; // recomputed inside showWith from the live tab count
        self.anchor = anchor;
        self.showWith(trigger, host_index, tab_index);
    }

    pub fn hide(self: *MenuHost) void {
        if (self.context_menu) |menu| menu.hide();
        if (self.terminal_menu) |menu| menu.hide();
        self.declined();
        self.cx.requestRedraw();
    }

    /// Mounts both native menus under `parent` (zero-size anchors); the panels live in the window overlay portal.
    pub fn mountMenus(self: *MenuHost, scope: *ui.Scope, parent: *ui.Node) !void {
        const hooks: app_menu.Hooks = .{ .context = self, .select = menuSelected, .closed = menuClosed };
        self.context_menu = try app_menu.AppMenu.mountContext(self.cx, scope, parent, .{ .panel_test_id = "context.menu" }, hooks);
        self.terminal_menu = try app_menu.AppMenu.mountContext(self.cx, scope, parent, .{ .panel_test_id = "terminal.menu" }, hooks);
    }

    fn menuSelected(raw: *anyopaque, id: []const u8) void {
        const self: *MenuHost = @ptrCast(@alignCast(raw));
        if (menus.parseTabColorId(id)) |color| {
            const workspace = self.workspace orelse return;
            const tab_id = self.captured_tab orelse return;
            if (workspace.tabIndexById(tab_id)) |at| {
                if (self.captured_owner) |owner| if (!workspace.tabs.items[at].content_owner.eql(owner)) return;
            } else return;
            _ = workspace.setTabColor(tab_id, color);
            return;
        }
        const action = std.meta.stringToEnum(menus.Action, id) orelse return;
        self.runCapturedAction(action);
    }
    fn menuClosed(raw: *anyopaque) void {
        const self: *MenuHost = @ptrCast(@alignCast(raw));
        const other_open = (if (self.context_menu) |menu| menu.isOpen() else false) or (if (self.terminal_menu) |menu| menu.isOpen() else false);
        if (other_open or self.state.open == null) return;
        self.declined();
    }

    fn isLocalTarget(self: *const MenuHost) bool {
        const workspace = self.workspace orelse return false;
        const index = self.context_tab orelse return false;
        return index < workspace.tabs.items.len and workspace.isLocalSession(workspace.tabs.items[index].id);
    }

    fn transferTargetAvailable(self: *MenuHost) bool {
        const transfer = self.transfer_host orelse return false;
        const workspace = self.workspace orelse return false;
        const index = self.context_tab orelse return false;
        if (index >= workspace.tabs.items.len) return false;
        const tab = workspace.tabs.items[index];
        if (tab.closing or tab.isCard() or tab.failed or tab.runtime == null or tab.content_owner != .session) return false;
        const snapshot_value = (transfer.application.sessions.capabilitySnapshot(tab.content_owner.session) catch return false) orelse return false;
        return @import("../../../host/actions.zig").project(.upload, snapshot_value).enabled;
    }

    fn capabilitiesForTab(self: *MenuHost, index: ?usize) ?@import("../../../host/capability_snapshot.zig").Snapshot {
        const workspace = self.workspace orelse return null;
        const selected = index orelse return null;
        if (selected >= workspace.tabs.items.len) return null;
        const owner = workspace.tabs.items[selected].content_owner;
        if (owner != .session) return null;
        const application = if (self.transfer_host) |transfer| transfer.application else if (self.ai) |ai| ai.application_host orelse return null else return null;
        return application.sessions.capabilitySnapshot(owner.session) catch null;
    }

    const UnsavedConnection = union(enum) {
        remote: hosts_mod.HostConfig,
        plugin: @import("../../../config/connection_envelope.zig").Envelope,
    };

    fn unsavedConnectionForTab(self: *MenuHost, index: usize) ?UnsavedConnection {
        const workspace = self.workspace orelse return null;
        if (index >= workspace.tabs.items.len) return null;
        const tab = workspace.tabs.items[index];
        if (tab.local or tab.closing or tab.content_owner != .session) return null;
        if (tab.temporaryHost()) |host| {
            const manifest = workspace.plugins.find(host.protocolId()) orelse return null;
            _ = manifest.connection orelse return null;
            return .{ .remote = host };
        }
        if (tab.plugin_protocol_id.len == 0) return null;
        const wizard = self.wizard_host orelse return null;
        const value = wizard.application_host.sessions.connectionEnvelope(tab.content_owner.session) orelse return null;
        if (@backingInt(value.id) != 0) return null;
        const manifest = workspace.plugins.find(value.protocol_id) orelse return null;
        _ = manifest.connection orelse return null;
        return .{ .plugin = value };
    }

    fn backgroundAvailable(self: *MenuHost) bool {
        if (self.background_socks == null or self.state.open != .host_asset and self.context_host == null) return false;
        const workspace = self.workspace orelse return false;
        const owner = self.captured_asset orelse return false;
        const host = workspace.registry.get(owner) catch return false;
        const manifest = workspace.plugins.find(host.protocolId()) orelse return false;
        return manifest.session_factory != null and manifest.supports(@import("../../../host/plugin_registry.zig").legacyServiceDefinition(.forward)) and @backingInt(owner.id) != 0 and !workspace.shutting_down;
    }

    fn localTargetReadonly(self: *MenuHost) bool {
        if (!self.isLocalTarget()) return false;
        const terminal = self.activeTerminal() orelse return true;
        const owner = self.captured_owner orelse return true;
        return switch (owner) {
            .session => |handle| if (terminal.terminalSnapshot(handle)) |snapshot| snapshot.read_only else true,
            else => true,
        };
    }

    pub fn activeTerminal(self: *MenuHost) ?*TerminalViewNode {
        const workspace = self.workspace orelse return null;
        const index = if (self.using_capture or self.state.open != null) blk: {
            const id = self.captured_tab orelse return null;
            const found = workspace.tabIndexById(id) orelse return null;
            if (self.captured_owner) |owner| if (!workspace.tabs.items[found].content_owner.eql(owner)) return null;
            break :blk found;
        } else workspace.active_tab orelse return null;
        if (index >= workspace.tabs.items.len) return null;
        return if (workspace.tabs.items[index].terminal) |*terminal| terminal else null;
    }

    fn terminalIntent(self: *MenuHost, index: usize) ?AiHost.TerminalIntent {
        const workspace = self.workspace orelse return null;
        if (index >= workspace.tabs.items.len) return null;
        const tab = workspace.tabs.items[index];
        if (tab.closing or tab.content_owner != .session or tab.terminal == null) return null;
        const terminal = &tab.terminal.?;
        const surface = terminal.terminal_surface;
        if (surface) |current| if (!current.owner.eql(tab.content_owner.session)) return null;
        if (surface == null and (terminal.worker == null or terminal.history.selected != null)) return null;
        var owner: ai_attachments.Owner = .{ .tab = @backingInt(tab.tab_id) };
        var intent: AiHost.TerminalIntent = .{ .tab = tab.tab_id, .source = tab.content_owner.session, .assistant_owner = owner, .selection = if (surface) |current| current.selection else null };
        if (surface == null) {
            const range = terminal.selection.normalized() orelse return null;
            const worker = terminal.worker.?;
            _ = worker.notificationSnapshot(tab.content_owner.session) catch return null;
            intent.legacy_selection = .{ .range = range, .source_version = terminal.selectionSourceVersion() };
        }
        if (workspace.active_group_view != null) {
            const ai = self.ai orelse return null;
            const current = ai.currentScope() orelse return null;
            _ = current.validate(&.{@backingInt(tab.content_owner.session.session_id)}) catch return null;
            owner = current.owner;
            for (current.members.slice()) |member_id| {
                const member = ai.tabForSession(member_id) orelse return null;
                if (member.closing or member.content_owner != .session) return null;
                intent.members[intent.member_count] = member.content_owner.session;
                intent.member_count += 1;
            }
        }
        intent.assistant_owner = owner;
        return intent;
    }

    fn activeHasSelection(self: *MenuHost) bool {
        const terminal = self.activeTerminal() orelse return false;
        return terminal.hasSelection();
    }

    /// 克隆主机：arena 追加「name 副本」，写回 hosts.toml，重建侧栏。
    fn cloneHostPersist(self: *MenuHost, host_index: usize) !void {
        const workspace = self.workspace orelse return;
        if (host_index >= workspace.registry.hosts.len) return error.InvalidHost;
        const host = workspace.registry.hosts[host_index];
        const name = try std.fmt.allocPrint(self.allocator, "{s}-副本", .{host.name});
        defer self.allocator.free(name);
        _ = try workspace.applyAssetAction(.{ .clone = .{ .owner = self.captured_asset orelse host.owner(), .name = name } });
    }

    fn pinHostPersist(self: *MenuHost, host_index: usize) !void {
        const workspace = self.workspace orelse return;
        if (host_index >= workspace.registry.hosts.len) return error.InvalidHost;
        const host = workspace.registry.hosts[host_index];
        _ = try workspace.applyAssetAction(.{ .pin = .{ .owner = self.captured_asset orelse host.owner(), .pinned = !host.pinned } });
    }

    fn showAssetAction(self: *MenuHost, mode: @import("../../connections/assets/view/asset_action_view.zig").Mode, host_index: usize) !void {
        const workspace = self.workspace orelse return error.MissingWorkspace;
        const view = self.asset_action_view orelse return error.ViewUnavailable;
        if (host_index >= workspace.registry.hosts.len) return error.InvalidHost;
        const owner = self.captured_asset orelse workspace.registry.hosts[host_index].owner();
        const host = try workspace.registry.get(owner);
        const group_index = if (host.asset_group_id) |id| workspace.registry.groupIndex(id) else null;
        const Group = @import("../../connections/assets/view/asset_action_view.zig").Group;
        const groups = try self.allocator.alloc(Group, workspace.registry.groups.len);
        defer self.allocator.free(groups);
        for (workspace.registry.groups, groups) |group, *destination| destination.* = .{ .reference = .{ .id = group.group_id, .revision = group.revision }, .name = group.name, .host_count = group.ordered_connection_ids.len };
        const endpoint = try workspace.assetActionEndpoint(self.allocator, host);
        defer self.allocator.free(endpoint);
        const open_sessions = workspace.connectionTabs(owner.id).count;
        try view.retheme();
        _ = self.asset_action_theme.take();
        try view.show(.{ .mode = mode, .owner = owner, .name = host.name, .endpoint = endpoint, .source_group = if (group_index) |index| .{ .id = workspace.registry.groups[index].group_id, .revision = workspace.registry.groups[index].revision } else null, .source_group_name = if (group_index) |index| workspace.registry.groups[index].name else "未分组", .groups = groups, .open_sessions = open_sessions });
    }

    pub fn assetActionAnchor(raw: *anyopaque, owner: @import("../../../host/identity.zig").AssetOwner) ?ui.ComputedRect {
        const self: *MenuHost = @ptrCast(@alignCast(raw));
        const workspace = self.workspace orelse return null;
        const index = workspace.registry.indexOf(owner.id) orelse return null;
        for (workspace.host_rows.items) |row| if (row.host_index == index) return row.node.globalRect();
        return null;
    }
    pub fn assetActionClosed(raw: *anyopaque) void {
        const self: *MenuHost = @ptrCast(@alignCast(raw));
        const workspace = self.workspace orelse return;
        if (self.asset_action_view) |view| if (view.source) |source| {
            if (workspace.registry.indexOf(source.value.owner.id)) |index| for (workspace.host_rows.items) |row| {
                if (row.host_index == index) {
                    self.cx.setFocus(row.view.menu_trigger);
                    return;
                }
            };
        };
        if (workspace.sidebar_chrome) |sidebar| sidebar.focusSearchFallback();
    }
    pub fn assetActionCompleted(raw: *anyopaque, mode: @import("../../connections/assets/view/asset_action_view.zig").Mode) void {
        const self: *MenuHost = @ptrCast(@alignCast(raw));
        if (self.workspace) |workspace| {
            _ = mode;
            workspace.status("主机已移动，已打开的会话继续运行");
            if (workspace.sidebar_chrome) |sidebar| sidebar.focusSearchFallback();
        }
    }
    pub fn submitAssetAction(raw: *anyopaque, request: @import("../../../config/asset_actions.zig").Request) !@import("../../../config/asset_actions.zig").Result {
        const self: *MenuHost = @ptrCast(@alignCast(raw));
        const workspace = self.workspace orelse return error.MissingWorkspace;
        return workspace.applyAssetAction(request);
    }

    pub fn viewAssetGroup(raw: *anyopaque, group_id: ?@import("../../../host/identity.zig").AssetGroupId) void {
        const self: *MenuHost = @ptrCast(@alignCast(raw));
        const workspace = self.workspace orelse return;
        if (group_id) |id| if (workspace.registry.groupIndex(id) == null) {
            workspace.status("目标分组已不存在");
            return;
        };
        for (workspace.registry.hosts, 0..) |host, index| if (host.asset_group_id == group_id) {
            workspace.selected_host = index;
            if (self.sidebar_search_value) |value| value.set("");
            workspace.setSearch("");
            for (workspace.host_rows.items) |row| if (row.host_index == index) {
                self.cx.setFocus(row.node);
                break;
            };
            return;
        };
        workspace.status("目标分组当前没有主机");
    }

    pub fn viewAssetSessions(raw: *anyopaque, owner: @import("../../../host/identity.zig").AssetOwner) void {
        const self: *MenuHost = @ptrCast(@alignCast(raw));
        const workspace = self.workspace orelse return;
        if (workspace.connectionTabs(owner.id).first_index) |index| {
            workspace.selectTab(index);
            return;
        }
        workspace.status("该主机的会话已关闭");
    }

    /// Executes a menu action against the active session. Copy/paste are
    /// fully wired; the rest surface their status on the status bar so the
    /// interaction loop is complete even where the feature lands later.
    pub fn runAction(self: *MenuHost, action: @import("../../workspace/model/context_menus.zig").Action) void {
        const workspace = self.workspace orelse return;
        if (self.using_capture) {
            if (self.captured_asset) |owner| {
                _ = workspace.registry.get(owner) catch {
                    workspace.status("主机配置已变化，请重新打开菜单");
                    return;
                };
            }
            if (self.captured_host) |id| self.context_host = workspace.hostIndex(id) orelse return;
            if (self.captured_tab) |id| {
                self.context_tab = workspace.tabIndexById(id) orelse return;
                if (self.captured_owner) |owner| if (!workspace.tabs.items[self.context_tab.?].content_owner.eql(owner)) return;
            }
        } else {
            self.context_host = null;
            self.context_tab = workspace.active_tab;
        }
        if (action == .command_history) {
            if (self.context_tab) |index| {
                if (index < workspace.tabs.items.len) workspace.setActiveTab(index);
            }
            if (self.command_history) |history| history.toggle();
            return;
        }
        var action_context = self.state.context;
        const current_capabilities = self.capabilitiesForTab(self.context_tab);
        if (self.using_capture) if (action_context.capability_snapshot) |captured| {
            const current = current_capabilities orelse return;
            if (!captured.owner.eql(current.owner) or captured.revision != current.revision) {
                workspace.status("会话能力已变化，请重新打开菜单");
                return;
            }
        };
        action_context.capability_snapshot = current_capabilities;
        if (!@import("../../workspace/model/context_menus.zig").isVisible(action, action_context) or !@import("../../workspace/model/context_menus.zig").isEnabled(action, action_context)) return;
        switch (action) {
            .command_history => unreachable,
            .copy => {
                const terminal = self.activeTerminal() orelse return;
                const text = terminal.copySelectionText(self.cx.allocator) catch |err| {
                    workspace.statusFailure("复制失败：无法读取选区");
                    applog.warn(.ui, "copySelection: {s}", .{@errorName(err)});
                    return;
                } orelse return;
                defer self.cx.allocator.free(text);
                if (text.len == 0) return;
                if (terminal.terminal_surface) |surface| {
                    surface.copySelectionToClipboard(text) catch |err| {
                        surface.showError(err);
                        return;
                    };
                } else if (!terminal.copySelectionToClipboard(self.cx, text)) {
                    workspace.statusFailure("复制失败：剪贴板不可用");
                    return;
                }
                if (self.using_capture) {
                    var anchor = self.anchor;
                    anchor.w = @max(1, anchor.w);
                    anchor.h = @max(1, anchor.h);
                    @import("../../notifications/mod.zig").acknowledgeAt(self.cx, anchor, "已复制选中内容") catch {};
                } else workspace.status("已复制选中内容");
            },
            .paste => {
                const terminal = self.activeTerminal() orelse return;
                const buffer = self.cx.allocator.alloc(u8, 1024 * 1024 + 1) catch {
                    workspace.statusFailure("粘贴失败：内存不足");
                    return;
                };
                defer self.cx.allocator.free(buffer);
                const text = ui.platform_services.clipboardGetText(self.cx.system_sdk, buffer) orelse {
                    workspace.status("剪贴板为空");
                    return;
                };
                terminal.requestPaste(text) catch |err| {
                    workspace.statusFailure(@errorName(err));
                    return;
                };
            },
            .upload_file, .download_file => {
                if (!self.transferTargetAvailable()) return;
                const index = self.context_tab orelse return;
                const owner = workspace.tabs.items[index].content_owner.session;
                const transfer = self.transfer_host orelse return;
                transfer.showSessionTransfer(owner, if (action == .download_file) .download else .upload, null);
            },
            .search => if (self.activeTerminal()) |terminal| terminal.openSearch(),
            .clear_screen => {
                const terminal = self.activeTerminal() orelse return;
                terminal.clearScreen() catch |err| workspace.statusFailure(@errorName(err));
            },
            .history => {
                if (self.context_host) |host_index| {
                    if (host_index >= workspace.registry.hosts.len) return;
                    // 侧栏主机右键“查看历史会话日志”：打开会话记录卡片（浮动，按这台主机筛选）。
                    if (self.history_host) |history| {
                        history.open(.{ .saved_connection = @backingInt((self.captured_asset orelse return).id) }) catch |err| {
                            workspace.statusFailure(@errorName(err));
                        };
                    }
                } else {
                    const terminal = self.activeTerminal() orelse return;
                    if (!terminal.openHistory()) workspace.status("暂无可回溯的终端历史");
                }
            },
            .toggle_timestamp => {
                const terminal = self.activeTerminal() orelse return;
                const enabled = terminal.toggleTimestampGutter();
                workspace.status(if (enabled) "时间戳侧栏已开启" else "时间戳侧栏已关闭");
            },
            .toggle_block_selection => {
                if (self.isLocalTarget()) {
                    workspace.status("按住 " ++ shortcut_router.glyph.option ++ " 并拖动以进行矩形选择");
                    return;
                }
                const terminal = self.activeTerminal() orelse return;
                const enabled = terminal.toggleBlockSelection();
                workspace.status(if (enabled) "矩形块选模式已开启" else "矩形块选模式已关闭");
            },
            .export_selection => {
                const terminal = self.activeTerminal() orelse return;
                const saved = terminal.exportText(self.cx, workspace.io, .selection) catch |err| {
                    workspace.statusFailure(@errorName(err));
                    return;
                };
                if (saved) workspace.status("已导出选中内容");
            },
            .ask_ai => if (self.ai) |ai| {
                const intent = if (self.using_capture) self.captured_terminal_intent else if (self.context_tab) |index| self.terminalIntent(index) else null;
                ai.openTerminalSelection(intent orelse {
                    workspace.status("终端选区来源不可用，请重新选择后打开菜单");
                    return;
                }) catch |err| workspace.statusFailure(@errorName(err));
            },
            .reconnect => {
                const tab_index = self.context_tab orelse workspace.active_tab orelse return;
                workspace.reconnectTab(tab_index) catch |err| workspace.statusFailure(@errorName(err));
            },
            // ── Host asset actions (sidebar right-click) ──────────────
            .start_background_socks => {
                const background = self.background_socks orelse return;
                background.requestStart(self.captured_host orelse return, self.captured_asset orelse return) catch |err| workspace.statusFailure(@errorName(err));
            },
            .manage_background_socks => {
                const background = self.background_socks orelse return;
                background.showAsset(self.captured_asset orelse return, self.anchor);
            },
            .new_tab => {
                if (self.context_tab) |tab| {
                    workspace.newSessionFromTab(tab) catch |err| workspace.statusFailure(@errorName(err));
                } else if (self.context_host) |host| {
                    workspace.newSession(host) catch |err| workspace.statusFailure(@errorName(err));
                }
            },
            .open_in_current_group => {
                const host = self.context_host orelse return;
                const target = self.captured_group_target orelse return;
                workspace.openHostInGroup(host, target) catch |err| workspace.statusFailure(@errorName(err));
            },
            .duplicate_into_group => {
                const index = self.context_tab orelse return;
                workspace.duplicateSessionIntoGroup(index) catch |err| workspace.statusFailure(@errorName(err));
            },
            .reuse_connection => {
                if (self.context_tab) |tab| workspace.reuseSessionFromTab(tab) catch |err| workspace.statusFailure(@errorName(err));
            },
            .new_window => {
                const process = process_state.process_windows orelse return;
                const source = if (self.transfer_host) |transfer| transfer.application else return;
                if (self.context_tab) |index| {
                    process.queueTab(source, workspace.tabs.items[index].id) catch |err| workspace.statusFailure(@errorName(err));
                    return;
                }
                const asset = self.captured_asset orelse return;
                _ = workspace.registry.get(asset) catch {
                    workspace.status("主机配置已更改，请重新打开菜单");
                    return;
                };
                process.queue(source, self.captured_host orelse return) catch |err| workspace.statusFailure(@errorName(err));
            },
            .clone_host => {
                const host_index = self.context_host orelse return;
                self.cloneHostPersist(host_index) catch |err| {
                    applog.warn(.ui, "clone host failed: {s}", .{@errorName(err)});
                    workspace.statusFailure("克隆主机失败");
                };
            },
            .edit_host => {
                const host_index = self.context_host orelse if (self.context_tab) |tab| blk: {
                    const asset = workspace.savedConnectionForTab(tab) orelse return;
                    break :blk workspace.registry.indexOf(asset.id) orelse return;
                } else return;
                const host = self.wizard_host orelse return;
                if (host_index >= workspace.registry.hosts.len) return;
                WizardHost.openCapturedAsset(host, workspace.registry.hosts[host_index].owner()) catch |err| {
                    workspace.statusFailure(@errorName(err));
                    return;
                };
                self.edit_host_index = host_index;
            },
            .save_host => {
                const index = self.context_tab orelse return;
                const source = self.unsavedConnectionForTab(index) orelse return;
                const host = self.wizard_host orelse return;
                var arena: std.heap.ArenaAllocator = .init(self.allocator);
                defer arena.deinit();
                const value = switch (source) {
                    .remote => |remote| @import("../../../config/connection_envelope.zig").fromTemporaryHost(arena.allocator(), remote) catch |err| {
                        workspace.statusFailure(@errorName(err));
                        return;
                    },
                    .plugin => |value| value,
                };
                WizardHost.openConnectionDraft(host, value) catch |err| workspace.statusFailure(@errorName(err));
            },
            .pin_host => {
                const host_index = self.context_host orelse return;
                self.pinHostPersist(host_index) catch |err| {
                    applog.warn(.ui, "pin host failed: {s}", .{@errorName(err)});
                    workspace.statusFailure("置顶失败");
                };
            },
            .move_group => {
                const host_index = self.context_host orelse return;
                self.showAssetAction(.move, host_index) catch |err| workspace.statusFailure(@errorName(err));
            },
            .delete_host => {
                // 可撤销：直接执行（侧栏先藏起来），弹带“撤销”的 Toast（CONSISTENCY_AUDIT #2）。
                const host_index = self.context_host orelse return;
                workspace.deleteHostUndoable(host_index) catch |err| workspace.statusFailure(@import("../../../shared/base/error_text.zig").lineOr(err, "删除主机失败"));
            },
            // ── Tab actions (tab strip right-click) ───────────────────
            // 稿 3: the colour is chosen in the tab menu's “颜色 ›” submenu (tabMenuSelected).
            .tab_color, .arrange_side, .arrange_stack => {},
            .join_session_group => {
                workspace.showGroupPicker(self.context_tab orelse return) catch |err| workspace.statusFailure(@errorName(err));
            },
            .rename_tab => {
                const tab_index = self.context_tab orelse return;
                if (tab_index >= workspace.tabs.items.len) return;
                workspace.beginRenameTab(workspace.tabs.items[tab_index].id) catch |err| workspace.statusFailure(@errorName(err));
                self.hide();
                self.state.dismiss();
            },
            .clone_session => {
                const tab_index = self.context_tab orelse return;
                if (tab_index >= workspace.tabs.items.len) return;
                workspace.duplicateSessionFromTab(tab_index) catch |err| {
                    workspace.statusFailure(@errorName(err));
                };
            },
            .view_jump_chain => {
                const tab_index = self.context_tab orelse return;
                const details = self.connection_details_host orelse return;
                details.showForTab(tab_index);
            },
            .session_identity => {
                const tab_index = self.context_tab orelse return;
                if (self.session_identity) |open_card| open_card(self.session_identity_context orelse return, tab_index);
            },
            .export_session => {
                const Export = @import("../../workspace/host/session_export.zig");
                const tab_index = self.context_tab orelse workspace.active_tab orelse return;
                if (tab_index >= workspace.tabs.items.len) return;
                const source_tab = workspace.tabs.items[tab_index];
                // 会话记录卡片的 tab：导出卡片详情区正在显示的那条记录（原归档 tab 的导出）。
                if (source_tab.isCard()) {
                    const history = self.history_host orelse return;
                    history.exportShown(source_tab.content_owner.card) catch |err| workspace.statusFailure(@errorName(err));
                    return;
                }
                const runtime = source_tab.runtime;
                const local_service = if (source_tab.local) blk: {
                    const terminal_view = source_tab.terminal orelse break :blk null;
                    const surface = terminal_view.terminal_surface orelse break :blk null;
                    break :blk @as(?@import("../../../host/terminal_service.zig").Service, surface.service);
                } else null;
                if (runtime == null and local_service == null) {
                    workspace.status("会话尚未连接");
                    return;
                }
                const capture: Export.SessionCapture = .{ .tab_id = source_tab.tab_id, .owner = source_tab.content_owner };
                const format = Export.Format.parse(workspace.app_config.log.export_format) catch |err| {
                    workspace.statusFailure(@errorName(err));
                    return;
                };
                const sdk = self.cx.system_sdk orelse return;
                var path_buffer: [4096]u8 = undefined;
                const path = @import("../../../platform/dialog_port.zig").run(sdk, .{ .kind = .save_file, .title = format.defaultFilename() }, &path_buffer) catch |err| {
                    workspace.statusFailure(@errorName(err));
                    return;
                };
                const destination = path orelse return;
                const current_index = workspace.tabIndexById(capture.tab_id) orelse return;
                const current_tab = workspace.tabs.items[current_index];
                if (!capture.matches(current_tab.tab_id, current_tab.content_owner) or current_tab.runtime != runtime or current_tab.closing) {
                    workspace.status("StaleExportOwner");
                    return;
                }
                const Jobs = @import("../../workspace/host/session_export_jobs.zig");
                const manager = Jobs.Manager.forCx(self.cx) orelse return;
                if (manager.job != null) {
                    workspace.status("日志正在导出中");
                    return;
                }
                const source: Jobs.Source = if (local_service) |service| blk: {
                    const surface = (current_tab.terminal orelse return).terminal_surface orelse return;
                    if (!surface.service.binding.eql(service.binding)) return;
                    break :blk .{ .live = service.recordingLease() catch |err| {
                        workspace.statusFailure(@errorName(err));
                        return;
                    } };
                } else if (runtime) |current| blk: {
                    if (current.torn_down) return;
                    break :blk .{ .frozen = current.captureExport(std.heap.c_allocator) catch |err| {
                        workspace.statusFailure(@errorName(err));
                        return;
                    } };
                } else return;
                manager.start(source, format, destination) catch |err| workspace.statusFailure(@errorName(err));
            },
            .close_others => {
                const tab_index = self.context_tab orelse return;
                workspace.requestCloseOthers(tab_index);
            },
            .close_session => {
                const tab_index = self.context_tab orelse workspace.active_tab orelse return;
                if (tab_index < workspace.tabs.items.len) workspace.requestCloseTab(tab_index);
            },
        }
    }

    pub fn runCapturedAction(self: *MenuHost, action: @import("../../workspace/model/context_menus.zig").Action) void {
        self.using_capture = true;
        defer self.using_capture = false;
        self.runAction(action);
    }

    pub fn cleanup(self: *MenuHost) void {
        // The parent scope disposes both native menus.
        self.allocator.destroy(self);
    }
};
