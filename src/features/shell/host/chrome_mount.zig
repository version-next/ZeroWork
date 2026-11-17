//! 主窗口外壳区域的挂载函数：标题栏、侧栏、状态条（P2 自 src/main.zig 原样拆出；这些函数会创建宿主并接线回调，不只是建节点，所以放 host/；P5 改为 .yix 视图 + 宿主接线）。

const std = @import("std");
const ui = @import("ui");
const ws = @import("../../workspace/view/workspace.zig");
const Palette = ws.Palette;
const app_theme = @import("../../../shared/ui/theme/app_theme.zig");
const shell_styles = @import("../view/shell_styles.zig");
const HistoryHost = @import("../../history/host/history_host.zig").Host;
const MistChrome = @import("../../workspace/view/workspace_chrome.zig");
const AppNavHost = @import("nav_host.zig").AppNavHost;
const NavClick = @import("nav_host.zig").NavClick;
const SearchHost = @import("../../terminal/host/search_host.zig").SearchHost;
const SettingsHost = @import("../../settings/host/settings_host.zig").SettingsHost;
const SettingsNavClick = @import("../../settings/host/settings_host.zig").SettingsNavClick;
const onNavClick = @import("nav_host.zig").onNavClick;
const TitleTools = @import("../view/title_tools_view.zig");

// ── Region builders ─────────────────────────────────────────────────

/// 标题栏“回看日志”（以及“⋯”菜单里的同一项）：打开会话记录卡片（浮动，全部来源）。
pub fn openGlobalHistory(history: *HistoryHost) void {
    history.open(null) catch |err| {
        history.workspace.statusFailure(@errorName(err));
    };
}

pub fn mountTitleBar(cx: *ui.Cx, scope: *ui.Scope, p: Palette, settings_host: *SettingsHost, workspace: *ws.Workspace, nav_host: *AppNavHost, history_host: *HistoryHost) !*ui.Node {
    const bar = try ui.boxStyled(cx, shell_styles.title, .{});
    bar.meta.ownership.meta.test_id = "workspace.titlebar";
    // The view bar is the content column's title bar: its empty space drags the window (window
    // chrome region). Buttons inside are controls by themselves; the tab strip and the tool group
    // are declared client regions below, gaps included.
    bar.behavior.interaction.window_region = .drag;
    nav_host.title_bar = bar;
    if (nav_host.collapsed_sidebar) |restore| try bar.appendChild(cx.allocator, restore.root);
    const icon_tint = try scope.createSignal(?ui.Color, p.fg_secondary);
    nav_host.chrome.toolbar_tint = icon_tint;
    // Tabs and toolbar sit on the view bar's bottom edge (the island's top).
    const controls = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .direction = .row, .align_items = .end, .gap = 6 }, .{});
    nav_host.title_controls = controls;
    controls.setDisplay(.flex);
    try bar.appendChild(cx.allocator, controls);
    const tabs = try ui.boxStyled(cx, shell_styles.tabCapsule, .{});
    // The entire tab capsule is a client drag surface, including the title
    // text and gaps. AppKit must not consume these presses as window drags.
    tabs.behavior.interaction.window_region = .client;
    tabs.setStyleInline(cx.allocator, .{ .hit_roles = .{ .pointer = true }, .hit_behavior = .@"opaque" });
    tabs.meta.ownership.meta.test_id = "workspace.tabs.capsule";
    try controls.appendChild(cx.allocator, tabs);
    try tabs.appendChild(cx.allocator, workspace.tab_bar);
    // design-r3 稿 3: the tab strip (`tab_strip.yix`) ends with “⌄ n” and the native ghost sm
    // “+” (Pencil nCMeb). This host wires its click and anchors the new-session menu on it.
    const strip = try workspace.tabStrip();
    const tab_add = strip.newTabButton().?;
    tab_add.behavior.events.on_click = cx.on(AppNavHost, nav_host, AppNavHost.showSessionMenu);
    nav_host.session_menu_anchor = tab_add;
    try controls.appendChild(cx.allocator, try ui.spacer(cx));
    // design-r3 稿 5: the title bar tool group is `title_tools.yix` (native
    // ghost / md / icon-only Buttons with Tooltips, Dividers and a ⋯ Menu).
    // Each host wires its own click / popover anchor onto these native nodes.
    const tools = try TitleTools.ViewModel.mount(cx, scope);
    nav_host.title_tools = tools;
    tools.root.behavior.interaction.window_region = .client;
    try controls.appendChild(cx.allocator, tools.root);
    const history_button = tools.node(.history);
    history_button.behavior.events.on_click = cx.on(HistoryHost, history_host, openGlobalHistory);
    history_host.entry_button = history_button;
    const xfer_click = try cx.allocator.create(NavClick);
    xfer_click.* = .{ .host = nav_host, .kind = .transfer };
    const transfer_button = tools.node(.transfers);
    transfer_button.behavior.events.on_click = .{ .callback = onNavClick, .context = @ptrCast(xfer_click) };
    nav_host.transfer_anchor = transfer_button;
    nav_host.mist_transfer = try @import("../../transfer/view/transfer_toolbar_view.zig").View.mount(cx, scope, transfer_button);
    nav_host.notification_anchor = tools.node(.notifications);
    const settings_click = try cx.allocator.create(SettingsNavClick);
    settings_click.* = .{ .host = settings_host, .page_index = 0 };
    const settings_button = tools.node(.settings);
    settings_button.behavior.events.on_click = .{ .callback = onSettingsTitleClick, .context = @ptrCast(settings_click) };
    settings_host.focus_return = settings_button;
    nav_host.mist = try MistChrome.View.mount(cx, scope, workspace, controls, tabs, .{ .context = tools, .fit = foldTools });
    return bar;
}

fn foldTools(raw: *anyopaque, available: f32) MistChrome.ToolFold.Fit {
    const value = TitleTools.ViewModel.fit(raw, available);
    return .{ .width = value.width, .changed = value.changed };
}

/// Settings 图标回调：打开设置模态（与 ⌘, 同效）。
pub fn onSettingsTitleClick(raw: *anyopaque) void {
    const click: *SettingsNavClick = @ptrCast(@alignCast(raw));
    click.host.show();
}

pub fn mountSidebar(cx: *ui.Cx, scope: *ui.Scope, p: Palette, workspace: *ws.Workspace, nav_host: *AppNavHost) !*ui.Node {
    _ = p;
    const Sidebar = @import("../view/sidebar_view.zig");
    const search_host = try cx.allocator.create(SearchHost);
    search_host.* = .{ .allocator = cx.allocator, .workspace = workspace };
    try scope.onCleanup(SearchHost, search_host, SearchHost.cleanup);
    if (workspace.sidebar_bridge.new_host == null) {
        workspace.sidebar_bridge.context = nav_host;
        workspace.sidebar_bridge.new_host = struct {
            fn run(raw: ?*anyopaque, _: ?Sidebar.GroupRef) void {
                const host: *AppNavHost = @ptrCast(@alignCast(raw orelse return));
                if (host.wizard) |wizard| wizard.show();
            }
        }.run;
    }
    const view = try Sidebar.View.mount(cx, scope, workspace.sidebar_list, .{
        .context = nav_host,
        .local = AppNavHost.newLocalSession,
        .collapse = struct {
            fn run(raw: *anyopaque) void {
                const host: *AppNavHost = @ptrCast(@alignCast(raw));
                host.toggleSidebar();
            }
        }.run,
        .search_changed = cx.on(SearchHost, search_host, SearchHost.onChange),
        .bridge = workspace.sidebar_bridge,
    });
    workspace.sidebar_chrome = view;
    nav_host.sidebar_full = view.full;
    nav_host.sidebar_empty = view.empty;
    nav_host.chrome.sidebar_search_input = view.search;
    view.setSearchAvailable(workspace.registry.hosts.len != 0);
    const empty = workspace.registry.hosts.len == 0 and workspace.registry.groups.len == 0;
    view.full.setDisplay(if (empty) .none else .flex);
    view.empty.setDisplay(if (empty) .flex else .none);
    return view.root;
}

pub fn mountStatusBar(cx: *ui.Cx, scope: *ui.Scope, p: Palette, status_node: *ui.Node, tools: ?*TitleTools.ViewModel) !@import("../../connections/progress/host/ssh_status_host.zig").StatusBar {
    _ = p;
    const status = @import("../../connections/progress/host/ssh_status_host.zig");
    const native: ?status.ToolButtons = if (tools) |view| .{ .chain = view.node(.chain), .forward = view.node(.forward), .broadcast = view.node(.broadcast) } else null;
    return status.mountStatusBarWith(cx, scope, status_node, native);
}

