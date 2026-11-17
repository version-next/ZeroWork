const std = @import("std");
const presenter = @import("../../../shared/base/connection_presenter.zig");
const status_tone = @import("../../../shared/ui/theme/status_tone.zig");
const applog = @import("../../../platform/applog.zig");
const ui = @import("ui");
const overlay = @import("../../../shared/ui/overlay/overlay_host.zig");
const surface_migration = @import("../../../shared/ui/surface/surface_migration.zig");
const confirm_ui = @import("../../../shared/ui/confirm/confirm.zig");
const design = @import("../../../shared/ui/theme/design.zig");
const tab_rename = @import("../../shell/view/tab_rename.zig");
const lifecycle = @import("../../../host/session_lifecycle.zig");
const TerminalViewNode = @import("../../terminal/view/terminal_view.zig").TerminalViewNode;
const ReplaySurface = @import("../../terminal/mod.zig").ReplaySurface;
const Tombstone = @import("../model/session_tombstone.zig").Tombstone;
const host_key_confirmation = @import("../../../host/host_key_confirmation.zig");
const SessionRuntime = @import("../../../host/runtime_service.zig").Runtime;
const RuntimeReleaseReceipt = @import("../../../host/runtime_service.zig").ReleaseReceipt;
const ResourceLedger = @import("../../../proto/ssh/session.zig").ResourceLedger;
const TextSlot = @import("../../../vt/text_slot.zig").TextSlot;
const hosts_mod = @import("../../../config/hosts.zig");
const store = @import("../../../config/store.zig");
const config_mod = @import("../../../config/config.zig");
const auth_challenge = @import("../../../proto/ssh/auth_challenge.zig");
const identity = @import("../../../host/identity.zig");
const OperationKey = @import("../../../host/operation.zig").OperationKey;
const workspace_model = @import("../model/workspace_model.zig");
const tab_layout = @import("../../shell/model/tab_strip_layout.zig");
const tab_styles = @import("workspace_tab_styles.zig");
const tab_naming = @import("../model/tab_naming.zig");
const app_theme = @import("../../../shared/ui/theme/app_theme.zig");
const tab_strip = @import("tab_strip_view.zig");
const app_menu = @import("../../shell/mod.zig").app_menu;
const tab_strip_model = @import("../model/tab_strip.zig");
const menus_model = @import("../model/context_menus.zig");
const terminal_service = @import("../../../host/terminal_service.zig");
const local_styles = @import("../../terminal/view/local_session_styles.zig");
const RemoteNotice = @import("remote_session_notice.zig");
const session_icon = @import("../../../shared/ui/components/session_icon/session_icon.zig");
const group_view = @import("group_workspace_model.zig");
const card_dock = @import("../model/card_dock.zig");
const group_close = @import("../../../host/group_close_controller.zig");
const group_close_view = @import("group_close_view.zig");
const group_styles = @import("group_workspace_styles.zig");
const pane_header = @import("pane_header_view.zig");
const group_model = @import("../model/group_model.zig");
const card_placement = @import("../model/card_placement.zig");
const sidebar_view = @import("../../shell/view/sidebar_view.zig");
const plugin_registry = @import("../../../host/plugin_registry.zig");
const plugin_ui = @import("../../../host/plugin_ui_contract.zig");
const envelopes = @import("../../../config/connection_envelope.zig");
const ai_tab_grouping = @import("../../../ai/tab_grouping.zig");

var tab_ids: identity.Allocator(identity.TabId) = .{};

pub const Palette = struct {
    bg: ui.Color,
    chrome: ui.Color,
    sidebar: ui.Color,
    fg: ui.Color,
    fg_secondary: ui.Color,
    fg_muted: ui.Color,
    accent: ui.Color,
    border: ui.Color,
    green: ui.Color,
    red: ui.Color,
    status_bg: ui.Color,
    terminal_bg: ui.Color,

    pub fn fromTheme() Palette {
        const colors = app_theme.current();
        return .{
            .bg = colors.app,
            .chrome = colors.surface_1,
            .sidebar = colors.surface_1,
            .fg = colors.fg_1,
            .fg_secondary = colors.fg_2,
            .fg_muted = colors.fg_3,
            .accent = colors.accent,
            .border = colors.border,
            .green = colors.ok_ink,
            .red = colors.danger_ink,
            .status_bg = colors.surface_1,
            .terminal_bg = colors.terminal,
        };
    }
};

pub fn hex(rgba: u32) ui.Color {
    return ui.Color.hex(@truncate(rgba >> 8));
}

pub fn dot(cx: *ui.Cx, size: f32, color: ui.Color) !*ui.Node {
    return ui.box(cx, .{
        .width = .{ .px = size },
        .height = .{ .px = size },
        .background = color,
        .border = .{ .width = 0, .color = color, .radius = size / 2 },
    }, .{});
}

pub fn separator(cx: *ui.Cx, _: Palette) !*ui.Node {
    return ui.box(cx, .{
        .width = .{ .px = 1 },
        .height = .{ .px = 14 },
        .margin = .{ .top = 0, .right = 6, .bottom = 0, .left = 6 },
        .background = ui.Color.TRANSPARENT,
    }, .{});
}

pub const HostId = lifecycle.HostId;
pub const SessionId = lifecycle.SessionId;
const HostSnapshot = lifecycle.Snapshot(hosts_mod.HostConfig);
pub const removed_host_index = std.math.maxInt(usize);

/// One open session tab: UI nodes + live runtime (null until connected).
pub const SessionTab = struct {
    group_broadcast_enabled: bool = false,
    tab_color: ?u32 = null,
    id: SessionId,
    tab_id: identity.TabId,
    content_owner: identity.ContentOwner,
    /// 这张卡片的类型（PLUGIN_ARCH_PLAN 2.5 M2）：放置约束与 AI 声明都从这里读。与 `content_owner`
    /// 并存，`card_placement.consistent` 断言两者一致。默认是通用会话卡片；创建处按内容显式给出
    /// （终端、文件、插件声明的类型、会话记录卡片）。
    card_type: *const card_placement.CardTypeDef = &card_placement.session_def,
    generation: u64 = 1,
    host_id: HostId,
    /// Compatibility position for asset editing only; never a transport target.
    host_index: usize,
    host_snapshot: ?HostSnapshot,
    title: [64]u8 = undefined,
    title_len: usize = 0,
    root: *ui.Node,
    terminal: ?TerminalViewNode = null,
    file_ready: bool = false,
    content_ready: bool = false,
    runtime: ?*SessionRuntime = null,
    failed: bool = false,
    /// 非会话卡片的内容节点（如会话记录卡片，PL4b）：节点归卡片宿主所有，放在 `root` 里；tab 关闭时
    /// 先摘下交还宿主（`CardTabPort.closed`），不随 `root` 销毁。
    card_content: ?*ui.Node = null,
    /// A task creation is not selectable or a group member until ready commit.
    owned_pending: bool = false,
    owned_origin: bool = false,
    closing: bool = false,
    local: bool = false,
    detected_os: session_icon.Os = .unknown,
    local_scope: ?*ui.Scope = null,
    remote_notice_scope: ?*ui.Scope = null,
    remote_notice: ?*RemoteNotice.View = null,
    remote_retrying: bool = false,
    remote_retry_deadline: ?i128 = null,
    shell_init_confirmation_required: bool = false,
    /// Explicit confirmation is bound to the failed operation, never settings.
    shell_init_skip_for_operation: ?OperationKey = null,
    file_scope: ?*ui.Scope = null,
    transfer_trays: [2]?*@import("../../transfer/view/transfer_manager_view.zig").Panel = .{ null, null },
    plugin_renderer: ?plugin_ui.RendererInstance = null,
    plugin_protocol_id: []const u8 = "",
    /// cards-float: the session card floats on the window's float layer (its `root` is in the
    /// floating card's chrome). It still belongs to its tab (the single-card tab, or its group).
    floating: bool = false,
    local_bound: bool = false,
    local_state: LocalState = .starting,
    local_banner: ?*ui.Node = null,
    local_spinner: ?*ui.Node = null,
    local_ended_icon: ?*ui.Node = null,
    local_failure_icon: ?*ui.Node = null,
    local_message: ?*ui.Node = null,
    local_detail: ?*ui.Node = null,
    local_cancel: ?*ui.Node = null,
    local_close: ?*ui.Node = null,
    local_retry: ?*ui.Node = null,
    local_reconnect: ?*ui.Node = null,

    pub fn ticket(self: *const SessionTab) lifecycle.Ticket {
        return .{ .session_id = self.id, .generation = self.generation };
    }

    /// Frozen source identity survives deletion of the saved asset. Generic
    /// plugin tabs carry it directly rather than through a legacy snapshot.
    pub fn sourceConnectionId(self: *const SessionTab) ?identity.ConnectionId {
        const id: identity.ConnectionId = if (self.host_snapshot) |snapshot| snapshot.value.connection_id else if (self.plugin_protocol_id.len != 0) @fromBackingInt(self.host_id) else return null;
        return if (@backingInt(id) == 0) null else id;
    }

    /// Only the tab's frozen remote target can seed a new saved connection.
    /// Sidebar selection and registry edits must never retarget this draft.
    pub fn temporaryHost(self: *const SessionTab) ?hosts_mod.HostConfig {
        if (self.local or self.closing or self.content_owner != .session) return null;
        const snapshot = self.host_snapshot orelse return null;
        if (@backingInt(snapshot.value.connection_id) != 0 or !snapshot.value.isLegacy()) return null;
        return snapshot.value;
    }

    pub fn titleSlice(self: *const SessionTab) []const u8 {
        return self.title[0..self.title_len];
    }

    /// 非会话卡片的 tab（会话记录卡片等，owner 是 `CardId`）：没有会话、终端运行时与传输，
    /// 只读；不进分屏、不进 roster、不随窗口移交（读卡片类型的约束）。
    pub fn isCard(self: *const SessionTab) bool {
        return self.content_owner == .card;
    }

    /// The only write of the tab title. The AI's approval / question panel shows it, so it is an
    /// environment input too: an actual change publishes, rewriting the same title does not.
    pub fn setTitle(self: *SessionTab, name: []const u8) void {
        var n = @min(name.len, self.title.len);
        while (n > 0 and !std.unicode.utf8ValidateSlice(name[0..n])) n -= 1;
        if (std.mem.eql(u8, self.title[0..self.title_len], name[0..n])) return;
        @memcpy(self.title[0..n], name[0..n]);
        self.title_len = n;
        workspace_model.publishEnvironment();
    }

    // The tab's content owner, closing state, plugin renderer, runtime, floating and pending state
    // are part of the environment the AI's authority is checked against (LIFECYCLE.md §5.2–5.3).
    // Production code writes them only through these setters; each publishes an actual change.
    pub fn setContentOwner(self: *SessionTab, owner: identity.ContentOwner) void {
        if (self.content_owner.eql(owner)) return;
        self.content_owner = owner;
        workspace_model.publishEnvironment();
    }
    pub fn setClosing(self: *SessionTab, closing: bool) void {
        if (self.closing == closing) return;
        self.closing = closing;
        workspace_model.publishEnvironment();
    }
    pub fn setPluginRenderer(self: *SessionTab, renderer: ?plugin_ui.RendererInstance) void {
        if (std.meta.eql(self.plugin_renderer, renderer)) return;
        self.plugin_renderer = renderer;
        workspace_model.publishEnvironment();
    }
    pub fn setRuntime(self: *SessionTab, runtime: ?*SessionRuntime) void {
        if (self.runtime == runtime) return;
        self.runtime = runtime;
        workspace_model.publishEnvironment();
    }
    pub fn setFloating(self: *SessionTab, floating: bool) void {
        if (self.floating == floating) return;
        self.floating = floating;
        workspace_model.publishEnvironment();
    }
    pub fn setOwnedPending(self: *SessionTab, pending: bool) void {
        if (self.owned_pending == pending) return;
        self.owned_pending = pending;
        workspace_model.publishEnvironment();
    }
};

/// Normalize and validate a user supplied session-tab title.
///
/// Tab names are presentation state owned by the session, so they must not
/// mutate the host asset.  Trimming surrounding whitespace keeps inline
/// editing from producing titles that only look empty, while control bytes
/// (including newlines) are rejected because they make the tab strip
/// ambiguous.  The storage bound is explicit rather than silently truncating
/// a name typed by the user.
fn normalizeTabName(name: []const u8) ![]const u8 {
    return tab_rename.normalize(name);
}

const HostRow = struct {
    node: *ui.Node,
    name_node: *ui.Node,
    host_index: usize,
    click_ctx: *ClickCtx,
    view: *sidebar_view.HostRow,
};

/// One rendered tab of the strip (`tab_strip.yix`): read-only references to the nodes the
/// template mounted (geometry, rename anchor, tests). Nothing writes their styles.
const TabNode = struct {
    /// The tab surface (Pencil SHfTh), the Z12 motion anchor.
    node: *ui.Node,
    holder: *ui.Node,
    /// The ⌘ ordinal text in the close slot.
    icon: *ui.Node,
    type_icon: *ui.Node,
    icon_asset: ui.SvgAsset,
    label: *ui.Node,
    close: *ui.Node,
    tab_id: identity.TabId,
    tab_index: usize,
    cell: *tab_strip.Cell,
};

const PendingHostDelete = struct { token: u64, id: identity.ConnectionId };

/// One risk row on the close-confirmation card: category label plus the
/// detail text node. The mockup-close-confirm rule list ships all rows
/// (SSH/传输/AI/SOCKS5/历史); rows for subsystems without live state are
/// hidden at show time via setRiskVisible (setRiskDetail rewrites details).
const CloseRiskRow = struct {
    category: []const u8,
    detail_node: *ui.Node,
    row_node: *ui.Node,
};

/// Heap cell carrying (workspace, payload) through the void* handler seam.
///
/// Lifetime: host cells live until workspace cleanup. Tab cells are reclaimed
/// only by the deferred tab-bar rebuild, after event dispatch has returned.
/// Stable session IDs prevent pending clicks from targeting shifted indices.
const ClickCtx = struct {
    workspace: *Workspace,
    index: usize,
    tab_generation: u64 = 0,
    node: ?*ui.Node = null,
    host_id: ?lifecycle.HostId = null,
    asset_owner: ?identity.AssetOwner = null,
    session_id: ?SessionId = null,
    tab_id: ?identity.TabId = null,
    hovered: bool = false,
    pressed: bool = false,
    tooltip_open: ?*ui.Signal(bool) = null,
    tooltip_suppressed: bool = false,
    drag_binding: ?*ui.interaction.drag.Binding = null,
    test_id: [48]u8 = undefined,
    cell_test_id: [48]u8 = undefined,
};

/// Adds one non-empty tooltip line unless an earlier line already says it.
fn appendHintLine(allocator: std.mem.Allocator, hint: *std.ArrayList(u8), line: []const u8) !void {
    const value = std.mem.trim(u8, line, " \t\r\n");
    if (value.len == 0) return;
    var lines = std.mem.splitScalar(u8, hint.items, '\n');
    while (lines.next()) |existing| if (std.mem.eql(u8, existing, value)) return;
    if (hint.items.len != 0) try hint.append(allocator, '\n');
    try hint.appendSlice(allocator, value);
}

/// Menu trigger seam: main.zig owns the menu panel + renderer (MenuHost);
/// Workspace owns host/tab context data. The bridge carries the trigger plus
/// the exact context the menu needs to build/enable rows, without exposing
/// Workspace internals across the module boundary.
pub const MenuBridge = struct {
    host_action: ?*const fn (?*anyopaque, usize, sidebar_view.HostAction) void = null,
    context: ?*anyopaque = null,
    fire: ?*const fn (ctx: ?*anyopaque, trigger: Trigger, host_index: usize, tab_index: ?usize, multi_tabs: bool, anchor: ui.ComputedRect) void = null,

    pub const Trigger = @import("../model/context_menu_state.zig").Trigger;

    pub fn fireHost(self: *MenuBridge, trigger: Trigger, host_index: usize, anchor: ui.ComputedRect) void {
        const f = self.fire orelse return;
        f(self.context, trigger, host_index, null, false, anchor);
    }

    pub fn fireTab(self: *MenuBridge, trigger: Trigger, tab_index: usize, multi_tabs: bool, anchor: ui.ComputedRect) void {
        const f = self.fire orelse return;
        f(self.context, trigger, 0, tab_index, multi_tabs, anchor);
    }
};

pub const CloseRisk = struct {
    transfer: bool = false,
    ai_write: bool = false,
    socks: bool = false,
    local_process: bool = false,
    local_unknown: bool = false,
    pub fn any(self: CloseRisk) bool {
        return self.transfer or self.ai_write or self.socks or self.local_process or self.local_unknown;
    }
};

pub const CloseBridge = struct {
    context: ?*anyopaque = null,
    risk: ?*const fn (?*anyopaque, SessionId) CloseRisk = null,
    impact: ?*const fn (?*anyopaque, SessionId) group_close.Impact = null,
    close_state: ?*const fn (?*anyopaque, SessionId) ?group_close.MemberState = null,
    cleanup: ?*const fn (?*anyopaque, SessionId) void = null,
    request_close: ?*const fn (?*anyopaque, identity.TabId, identity.ContentOwner) CloseResult = null,
    confirm: ?*const fn (?*anyopaque, SessionId) void = null,
};
pub const CloseResult = enum { released, awaiting, unknown, rejected };
pub const NotificationAttentionBridge = struct {
    context: ?*anyopaque = null,
    has_dot: ?*const fn (?*anyopaque, identity.ContentOwner) bool = null,
};

pub const BackgroundForwardBridge = struct {
    context: ?*anyopaque = null,
    badge: ?*const fn (?*anyopaque, identity.AssetOwner) ?sidebar_view.ForwardBadge = null,
};
pub const WindowCloseBridge = struct {
    context: ?*anyopaque = null,
    cancelled: ?*const fn (?*anyopaque, u64) void = null,
};
/// Additional native file connections reuse the same authentication UI while
/// keeping their own original operation and worker-owned challenge bridges.
pub const ExternalAuthentication = struct {
    context: *anyopaque,
    pending: *const fn (*anyopaque) ?auth_challenge.Snapshot,
    submit: *const fn (*anyopaque, auth_challenge.RequestIdentity, auth_challenge.Reply) anyerror!void,
    cancel: *const fn (*anyopaque, auth_challenge.RequestIdentity) bool,
    host: *const fn (*anyopaque, auth_challenge.RequestIdentity) ?hosts_mod.HostConfig,
    parent: *const fn (*anyopaque, auth_challenge.RequestIdentity) ?*ui.Node,
    host_key: *const fn (*anyopaque, auth_challenge.RequestIdentity) ?host_key_confirmation.Request,
    totp: ?*const fn (*anyopaque, auth_challenge.RequestIdentity, @import("../../../proto/ssh/totp_prefill.zig").Time) anyerror!?@import("../../../proto/ssh/totp_prefill.zig").Suggestion = null,
};

pub const SessionBridge = struct {
    context: ?*anyopaque = null,
    create: ?*const fn (?*anyopaque, hosts_mod.HostConfig, HostId, usize, []const u8) anyerror!void = null,
    recreate: ?*const fn (?*anyopaque, SessionId) anyerror!void = null,
    reuse: ?*const fn (?*anyopaque, SessionId) anyerror!void = null,
    connected: ?*const fn (?*anyopaque, SessionId, u64) void = null,
    failed: ?*const fn (?*anyopaque, SessionId, u64, []const u8) void = null,
    cleanup: ?*const fn (?*anyopaque, SessionId, u64) void = null,
    cleanup_status: ?*const fn (?*anyopaque, SessionId, u64, RuntimeReleaseReceipt) void = null,
    create_local: ?*const fn (?*anyopaque, ?[]const u8) anyerror!void = null,
    duplicate_local: ?*const fn (?*anyopaque, SessionId) anyerror!void = null,
    retry_local: ?*const fn (?*anyopaque, SessionId) anyerror!void = null,
    retry_ssh: ?*const fn (?*anyopaque, SessionId) anyerror!void = null,
    /// Presentation-only OSC 7 directory of a Local session; null when unknown.
    local_cwd: ?*const fn (?*anyopaque, SessionId, std.mem.Allocator) ?[]u8 = null,
    /// Presentation-only name of the Local PTY's foreground program when it is
    /// not the shell itself (`zw_local_foreground`); null when idle or unknown.
    local_program: ?*const fn (?*anyopaque, SessionId, *[64]u8) ?[]const u8 = null,
    local_metadata_revision: ?*const fn (?*anyopaque) u64 = null,
};
pub const LocalState = enum { starting, running, exited, failed, closing, cleanup_unknown };
pub const TerminalTypographyConfig = @FieldType(config_mod.Config, "ui");

fn fontWeight(name: []const u8) u16 {
    return @backingInt(@import("../../../config/font_weight.zig").parse(name) orelse .regular);
}
fn cursorStyle(name: []const u8) TerminalViewNode.CursorStyle {
    if (std.mem.eql(u8, name, "bar")) return .bar;
    if (std.mem.eql(u8, name, "underline")) return .underline;
    return .block;
}

/// The Z12 flight of a pane coming from a floating card (float-split / cards-float).
pub const GroupFlight = group_view.Flight;
/// A card's own action in a docked pane's "更多" menu.
pub const CardMenuItem = group_view.CardMenuItem;
pub const GroupAction = enum { pin, leave, close_member, toggle_broadcast, broadcast, split_side, split_stack, stop_broadcast, stop_group_ai };

pub const Workspace = struct {
    recent_connections: @import("../../connections/quick_connect/model/quick_connect.zig").RecentList = .{},
    plugins: plugin_registry.Registry = .{},
    /// 本次启动时随应用插件的启用状态（Q5）：被禁用插件的已保存主机留在原位、以禁用样式显示、不可连接。
    plugin_launch: ?*const @import("../model/plugin_availability.zig").Launch = null,
    content_services: ?plugin_ui.ContentServicesFactory = null,

    font_family_resolver: ?*const fn ([]const u8) u16 = null,
    terminal_typography_resolver: ?*const fn (*TerminalViewNode, TerminalTypographyConfig) anyerror!void = null,
    allocator: std.mem.Allocator,
    cx: *ui.Cx,
    scope: *ui.Scope,
    io: std.Io,
    app_config: *const config_mod.Config,
    palette: Palette,

    registry: hosts_mod.Registry,
    identities: lifecycle.Identities = .{},
    hosts_path: []const u8,
    credential_provider: ?store.plugin_credential_references.Provider = null,

    sidebar_list: *ui.Node,
    sidebar_bridge: sidebar_view.Bridge = .{},
    background_forward_bridge: BackgroundForwardBridge = .{},
    sidebar_scope: ?*ui.Scope = null,
    sidebar_chrome: ?*sidebar_view.View = null,
    default_group_row: ?*sidebar_view.GroupRow = null,
    default_group_collapsed: bool = false,
    default_group_forced_open: bool = false,
    host_rows: std.ArrayList(HostRow) = .empty,
    group_headers: std.ArrayList(*ui.Node) = .empty,
    group_rows: std.ArrayList(*sidebar_view.GroupRow) = .empty,
    sidebar_drag_owner: ?identity.AssetOwner = null,
    sidebar_drop: ?@import("../../../config/asset_actions.zig").Request = null,
    pending_sidebar_drop: ?@import("../../../config/asset_actions.zig").Request = null,
    sidebar_session_drop: ?identity.TabId = null,
    pending_host_group_drop: ?struct { owner: identity.AssetOwner, target: identity.TabId } = null,
    group_drop_hint: ?*ui.Node = null,
    sidebar_drop_marker: ?*ui.Node = null,
    search_query: [128]u8 = undefined,
    search_len: usize = 0,
    selected_host: ?usize = null,

    tab_bar: *ui.Node,
    model: workspace_model.Model,
    /// The tab strip view (`tab_strip.yix`), mounted under `tab_bar` on first use.
    strip_vm: ?*tab_strip.ViewModel = null,
    strip_widths: std.ArrayList(f32) = .empty,
    /// Per visible tab: shown in the strip (false = in the “⌄ n” overflow menu, 稿 3).
    /// Lives in the strip view's row arena (valid until the render after next).
    strip_shown: []const bool = &.{},
    /// Recompute every tab's type icon on the next visual refresh (OS detected, history toggled).
    strip_icons_dirty: bool = true,
    /// Per visible tab: a session-group tab (稿 3 width 160–240 + member count).
    strip_grouped: std.ArrayList(bool) = .empty,
    strip_advances: std.ArrayList(f32) = .empty,
    strip_geometry: tab_layout.Result = .{ .mode = .normal, .content = 0, .hidden = 0 },
    header_width: f32 = 0,
    tab_budget: ?f32 = null,
    reveal_active: bool = false,
    command_held: bool = false,
    /// When ⌘ went down (frame clock); ordinals appear after it is held 300 ms (稿 3).
    command_held_since_ms: ?f64 = null,
    command_ordinals_shown: bool = false,
    names_metadata_revision: u64 = 0,
    drag_tab: ?identity.TabId = null,
    drag_binding: ?*ui.interaction.drag.Binding = null,
    drag_pointer_x: f32 = 0,
    rename_scope: ?*ui.Scope = null,
    rename_request: ?workspace_model.Rename = null,
    rename_pending: bool = false,
    close_targets: std.ArrayList(workspace_model.CloseTarget) = .empty,
    close_cursor: usize = 0,
    window_close_request: ?u64 = null,
    window_close_reconcile: bool = false,
    window_close_bridge: WindowCloseBridge = .{},
    close_receipts: std.ArrayList(workspace_model.CloseTarget) = .empty,
    tabs: std.ArrayList(*SessionTab) = .empty,
    tab_nodes: std.ArrayList(TabNode) = .empty,
    /// Incremented by every tab-bar rebuild. Cells stamped with an older
    /// generation belong to removed nodes and are ignored by the trampolines.
    tab_generation: u64 = 0,
    rename_session: ?SessionId = null,
    rename_draft: std.ArrayList(u8) = .empty,
    rename_editor: ?*tab_rename.Editor = null,
    tab_rebuild_pending: bool = false,
    tab_drop_target: ?identity.TabId = null,
    tab_reorder_target: ?identity.TabId = null,
    pending_tab_drop: ?struct {
        source: identity.TabId,
        target: identity.TabId,
        captured: bool = false,
        source_handle: ?identity.SessionHandle = null,
        target_handle: ?identity.SessionHandle = null,
        group: ?u32 = null,
        membership_revision: u64 = 0,
        settlement: ?ai_tab_grouping.Settlement = null,
    } = null,
    tab_menu_open: bool = false,
    /// Set by the workspace chrome while the active tab carries the session
    /// connection card preview; that card is then the tab's only hover popover.
    /// Island B v3 standalone Pane Header (tOrT3) above a single session.
    standalone_header: ?*ui.Node = null,
    /// The single session's header view-model (`pane_header.yix`): meta refreshes go through it.
    standalone_header_vm: ?*pane_header.Vm = null,
    standalone_scope: ?*ui.Scope = null,
    standalone_hash: u64 = 0,
    standalone_meta_ms: f64 = 0,
    group_tab_menu: ?*app_menu.AppMenu = null,
    /// 会话组页签菜单当前的条目（借用到下一次打开）。
    group_menu_entries: menus_model.Entries = .{},
    group_menu_target: ?u32 = null,
    active_tab: ?usize = null,
    /// Set only by a rendered group workspace. Membership alone never makes
    /// an independently opened session tab a group-owned AI conversation.
    active_group_view: ?u32 = null,

    group_roster: ?*group_model.Roster = null,
    ai_grouping_bridge: ai_tab_grouping.Bridge = .{},
    group_views: std.ArrayList(*group_view.View) = .empty,
    group_action_context: ?*anyopaque = null,
    group_action: ?*const fn (?*anyopaque, u32, u64, GroupAction) void = null,
    group_present_pending: bool = false,
    pane_meta_refreshed_ms: f64 = -1000,
    /// Empty-state "已保存的连接" list (Pencil hmCmB); mounted by the window shell.
    saved_connections: ?*@import("empty_saved_connections.zig").View = null,
    group_join: ?*@import("group_join_view.zig").View = null,
    pending_split: ?struct { group: u32, session: SessionId, revision: u64 } = null,

    terminal_area: *ui.Node,
    history_card_host: ?*ui.Node = null,
    /// Where tab-body flights (docked pane, tab body put back) draw their picture: the window shell,
    /// whose later children (AI launcher z 199, floating layer z 200) stack above it. Null = cx.root.
    flight_layer_parent: ?*ui.Node = null,
    /// 非会话卡片 tab 的宿主（会话记录卡片，PL4b）：tab 关闭后把卡片交还。
    card_tab_port: ?CardTabPort = null,
    /// Next non-session card leaf of a tab body split (float-split, `card_dock.cardLeaf`).
    next_card_leaf: u64 = 1,
    /// cards-float: the window's floating session cards (`SessionFloatHost`); null = this window
    /// cannot float session cards (the pane header's 浮动 is disabled with the reason).
    session_float: ?SessionFloatPort = null,
    /// The tab body empty state of a tab whose cards all float (`card_floated.yix`).
    floated_placeholder: ?*@import("card_floated_view.zig").View = null,
    /// The flight of a session card put back into its single-card tab (owns the transition).
    restore_flight_scope: ?*ui.Scope = null,
    /// 会话记录卡片详情区里的只读回放表面（不在 tab 里），设置与主题变化时与 tab 的终端一起更新。
    replays: std.ArrayList(*ReplaySurface) = .empty,
    empty_state: *ui.Node,
    status_node: ?*ui.Node = null,
    status_feedback: ?struct { context: *anyopaque, publish: *const fn (*anyopaque, ?identity.ContentOwner, []const u8, StatusKind) void } = null,
    command_output: ?*TerminalViewNode = null,
    creation_group: ?u32 = null,
    owned_creation_pending: bool = false,
    prepared_group_views: usize = 0,
    creation_tab_color: ?u32 = null,
    /// Status-bar grid-size label; bound to the active tab's terminal so the
    /// live PTY dimensions (frame_cols/frame_rows) replace the static text.
    grid_node: ?*ui.Node = null,
    /// Context-menu trigger seam (sidebar host rows, tab strip); owned by
    /// main.zig's MenuHost. Null keeps the legacy direct-connect behavior.
    menu_bridge: MenuBridge = .{},
    command_bridge: TerminalViewNode.PaletteObserver = .{ .on_command = ignoreCommand },
    input_bridge: ?TerminalViewNode.InputObserver = null,
    terminal_takeover_handler: ?@import("../../terminal/view/terminal_view.zig").TakeoverHandler = null,
    error_hint_handler: ?@import("../../../ai/command_error_hint.zig").Handler = null,
    close_bridge: CloseBridge = .{},
    notification_attention_bridge: NotificationAttentionBridge = .{},
    session_bridge: SessionBridge = .{},
    pending_shared_connection: ?@import("../../../host/runtime_service.zig").SharedLease = null,
    pending_bootstrap: ?*@import("../../../ai/ssh_bootstrap_product.zig").Prepared = null,
    external_auth: ?ExternalAuthentication = null,
    close_others_keep: ?SessionId = null,
    // ── Close-confirmation card (see requestCloseTab) ─────────────────
    /// Tab index whose close is awaiting user confirmation; null while no
    /// card is up.
    confirming_tab: ?usize = null,
    confirming_id: ?identity.TabId = null,
    /// Close confirmation Modal (see mountCloseConfirm): open state, barrier
    /// (zenit default overlay, window portal) and dialog panel.
    confirm_open: ?*ui.Signal(bool) = null,
    confirm_root: ?*ui.Node = null,
    confirm_card: ?*ui.Node = null,
    /// 取消: keyboard focus target while the dialog is up.
    confirm_cancel: ?*ui.Node = null,
    /// Message (consequence) text, rewritten with the pending tab's name on show.
    confirm_message: ?*ui.Signal([]const u8) = null,
    /// Risk rows (category + live detail text node), mounted once. Array so
    /// the upcoming 传输/AI/SOCKS5 rows can be appended without reworking
    /// the card layout.
    confirm_risk_rows: std.ArrayList(CloseRiskRow) = .empty,
    click_ctxs: std.ArrayList(*ClickCtx) = .empty,
    connect_jobs: std.ArrayList(*ConnectJob) = .empty,
    poll_hook: ?*PollHook = null,
    shutting_down: bool = false,
    host_key_job: ?*ConnectJob = null,
    host_key_generation: u64 = 0,
    /// Legacy host-key Modal (see mountHostKeyConfirm): open state, barrier,
    /// dialog panel and the default-focus 拒绝 button.
    host_key_open: ?*ui.Signal(bool) = null,
    host_key_root: ?*ui.Node = null,
    host_key_card: ?*ui.Node = null,
    host_key_reject: ?*ui.Node = null,
    host_key_detail: ?*ui.Node = null,
    host_key_changed_button: ?*ui.Node = null,
    /// 撤销窗口里的“删除主机”（CONSISTENCY_AUDIT #2，`shared/ui/confirm` 的 `undoable`）：这些主机先从侧栏藏起来，
    /// Toast 离场后才真正删除（按当时的注册表重新组请求），点“撤销”重新显示。
    pending_host_deletes: std.ArrayList(PendingHostDelete) = .empty,
    host_delete_token: u64 = 0,
    host_delete_text: [160]u8 = undefined,
    /// 撤销窗口里的“删除空分组”：这些分组先从侧栏藏起来（登记与提交在 `connections/assets/host/asset_group_host.zig`）。
    hidden_groups: std.ArrayList(identity.AssetGroupId) = .empty,
    auth_job: ?*ConnectJob = null,
    authentication_ui_ready: bool = false,
    auth_generation: u64 = 0,
    auth_root: ?*ui.Node = null,
    auth_card: ?*ui.Node = null,
    auth_detail: ?*ui.Node = null,
    auth_input: ?*ui.Signal([]const u8) = null,

    pub fn init(
        allocator: std.mem.Allocator,
        cx: *ui.Cx,
        scope: *ui.Scope,
        io: std.Io,
        app_config: *const config_mod.Config,
        hosts_path: []const u8,
        sidebar_list: *ui.Node,
        tab_bar: *ui.Node,
        terminal_area: *ui.Node,
        empty_state: *ui.Node,
    ) !*Workspace {
        applog.info(.workspace, "init: loading hosts from {s}", .{hosts_path});
        const registry = store.loadHosts(io, std.Io.Dir.cwd(), allocator, hosts_path) catch |err| blk: {
            applog.err(.workspace, "loadHosts({s}) failed: {s}", .{ hosts_path, @errorName(err) });
            break :blk hosts_mod.Registry{ .arena = std.heap.ArenaAllocator.init(allocator), .hosts = &.{} };
        };
        applog.info(.workspace, "hosts loaded: {d} entries", .{registry.hosts.len});
        const self = try allocator.create(Workspace);
        self.* = .{
            .allocator = allocator,
            .cx = cx,
            .scope = scope,
            .io = io,
            .app_config = app_config,
            .palette = Palette.fromTheme(),
            .registry = registry,
            .hosts_path = hosts_path,
            .sidebar_list = sidebar_list,
            .tab_bar = tab_bar,
            .model = .{ .allocator = allocator, .window = @fromBackingInt(1), .workspace = @fromBackingInt(1) },
            .terminal_area = terminal_area,
            .empty_state = empty_state,
        };
        current_workspace = self;
        try scope.onCleanup(Workspace, self, cleanup);
        try self.rebuildSidebar();
        try self.rebuildTabBar();
        try self.mountCloseConfirm();
        return self;
    }

    pub fn configureIdentity(self: *Workspace, window: identity.WindowId, workspace: identity.WorkspaceId) void {
        self.model.window = window;
        self.model.workspace = workspace;
    }

    fn cleanup(self: *Workspace) void {
        self.shutting_down = true;
        // 撤销窗口里的删除照常提交（只写盘，不再刷新界面）。
        confirm_ui.flushOwner(self.cx, self);
        self.sidebar_scope = null; // child scopes already disposed by parent
        self.sidebar_chrome = null;
        self.default_group_row = null;
        self.strip_vm = null; // disposed with the workspace scope
        self.rename_editor = null;
        if (self.poll_hook) |hook| {
            self.cx.removeAfterLayoutHook(hook);
            self.allocator.destroy(hook);
            self.poll_hook = null;
        }
        // Connect jobs own snapshots and no UI pointers. Cancel and join all
        // remaining attempts before any workspace storage is released.
        for (self.connect_jobs.items) |job| {
            job.cancelled.store(true, .release);
            job.host_key_bridge.cancel();
            job.auth_bridge.cancel();
        }
        for (self.connect_jobs.items) |job| {
            if (job.thread) |thread| thread.join();
            ConnectJob.destroy(job);
        }
        self.connect_jobs.deinit(self.allocator);
        self.rename_draft.deinit(self.allocator);
        for (self.group_views.items) |view| {
            view.deinit(self.allocator);
            self.allocator.destroy(view);
        }
        self.group_views.deinit(self.allocator);
        self.model.deinit();
        self.strip_widths.deinit(self.allocator);
        // 回放表面归卡片宿主所有（随它的作用域释放）；这里只放掉登记表。
        self.replays.deinit(self.allocator);
        self.strip_grouped.deinit(self.allocator);
        self.strip_advances.deinit(self.allocator);
        self.close_targets.deinit(self.allocator);
        self.close_receipts.deinit(self.allocator);
        for (self.tabs.items) |tab| {
            // FrameHook and SessionRuntime scope entries run BEFORE this
            // (reverse-registration order): hooks are gone and runtimes are
            // torn down+destroyed by their sole owners. Here we only release
            // tab-owned state — touching tab.runtime now would dereference
            // freed memory (the 0x10 quit crash).
            if (tab.terminal) |*terminal| {
                terminal.removeFrameHook(self.cx);
                terminal.clearPendingPaste();
                terminal.releaseBuffers(self.cx);
            }
            if (tab.plugin_protocol_id.len != 0) self.allocator.free(tab.plugin_protocol_id);
            // Child scopes dispose before this workspace cleanup. Native
            // renderers must register resource cleanup in their own scope.
            if (tab.host_snapshot) |*snapshot| snapshot.deinit();
            self.allocator.destroy(tab);
        }
        for (self.click_ctxs.items) |cell| self.allocator.destroy(cell);
        self.tabs.deinit(self.allocator);
        self.tab_nodes.deinit(self.allocator);
        self.host_rows.deinit(self.allocator);
        self.group_headers.deinit(self.allocator);
        self.group_rows.deinit(self.allocator);
        self.click_ctxs.deinit(self.allocator);
        self.confirm_risk_rows.deinit(self.allocator);
        self.pending_host_deletes.deinit(self.allocator);
        self.hidden_groups.deinit(self.allocator);
        self.identities.deinit(self.allocator);
        self.registry.deinit();
        if (current_workspace == self) current_workspace = null;
        self.allocator.destroy(self);
    }

    fn newClickCtx(self: *Workspace, index: usize) !*ClickCtx {
        const cell = try self.allocator.create(ClickCtx);
        cell.* = .{ .workspace = self, .index = index, .host_id = self.identities.hostAt(index), .asset_owner = if (@backingInt(self.registry.hosts[index].connection_id) == 0) null else self.registry.hosts[index].owner() };
        try self.click_ctxs.append(self.allocator, cell);
        return cell;
    }


    fn onClickTrampoline(raw: *anyopaque) void {
        const cell: *ClickCtx = @ptrCast(@alignCast(raw));
        const id = cell.host_id orelse return;
        const index = cell.workspace.identities.hostIndex(id) orelse return;
        cell.workspace.selected_host = index;
        cell.workspace.refreshSelection();
    }

    /// Full mouse handler on host rows: single click selects, double click
    /// connects, right click selects + connects (temp menu shortcut until the
    /// context menu component lands).
    fn onHostEvent(event: ui.events.Event, context: ?*anyopaque) ui.events.EventResult {
        const cell: *ClickCtx = @ptrCast(@alignCast(context orelse return .ignored));
        const self = cell.workspace;
        const id = cell.host_id orelse return .ignored;
        const index = self.identities.hostIndex(id) orelse return .ignored;
        switch (event) {
            // zenit 事件契约：右键不合成 click（event_dispatcher 只为左键合成），
            // 右键菜单必须在 mouse_down 捕获。
            .mouse_down => |mouse| {
                if (mouse.button == .right) {
                    self.logHostSelection(index, "right-click menu");
                    self.selected_host = index;
                    self.refreshSelection();
                    const node = cell.node orelse return .ignored;
                    self.menu_bridge.fireHost(.host_right_click, index, node.globalRect());
                    return .handled;
                }
                return .ignored;
            },
            .click => |click| {
                if (click.button != .left) return .handled;
                self.logHostSelection(index, "click select");
                self.selected_host = index;
                self.refreshSelection();
                return .handled;
            },
            .double_click => |click| {
                if (click.button != .left) return .ignored;
                self.logHostSelection(index, "double-click connect");
                self.selected_host = index;
                self.refreshSelection();
                self.openSession(index) catch |err| self.statusFailure(@errorName(err));
                return .handled;
            },
            else => return .ignored,
        }
    }

    /// True when the cell belongs to a tab bar that has since been rebuilt.
    /// Such cells stay allocated (dispatcher may still reference them) but
    /// must never act.
    fn isStaleTabCell(self: *const Workspace, cell: *const ClickCtx) bool {
        return cell.tab_generation != self.tab_generation;
    }

    // ---- tab strip hooks (tab_strip_view.Hooks) ----

    fn stripSelect(raw: *anyopaque, id: u64) void {
        const self: *Workspace = @ptrCast(@alignCast(raw));
        const tab_id: identity.TabId = @fromBackingInt(id);
        if (self.model.indexOf(tab_id) == null) return;
        if (self.tabIndexById(tab_id)) |at| if (self.rename_session == self.tabs.items[at].id) return;
        self.activateTabId(tab_id);
    }
    fn stripClose(raw: *anyopaque, id: u64) void {
        const self: *Workspace = @ptrCast(@alignCast(raw));
        self.closeTabById(@fromBackingInt(id));
    }
    fn closeTabById(self: *Workspace, id: identity.TabId) void {
        if (self.groupIdByTab(id)) |group| self.requestCloseGroup(group) else if (self.tabIndexById(id)) |index| self.requestCloseTab(index);
    }
    fn stripOverflow(raw: *anyopaque, id: u64) void {
        const self: *Workspace = @ptrCast(@alignCast(raw));
        const tab_id: identity.TabId = @fromBackingInt(id);
        if (self.model.indexOf(tab_id) == null) return;
        self.reveal_active = true;
        self.activateTabId(tab_id);
    }
    /// Every tab, the active one too, hovers its native hint only (title-click: the session
    /// connection card opens from the tab menu); no hint while a tab menu is open.
    /// A strip row mounted or unmounted (tab_strip.Hooks.mounted / unmounted): re-bind `tab_nodes`
    /// from the rows as they are mounted now, and repaint the type icons of rows that just mounted.
    fn stripRowBound(raw: *anyopaque, id: u64) void {
        const self: *Workspace = @ptrCast(@alignCast(raw));
        _ = id;
        if (self.shutting_down or self.strip_vm == null) return;
        self.collectTabNodes() catch |err| applog.err(.ui, "tab node binding: {s}", .{@errorName(err)});
        self.strip_icons_dirty = true;
        self.cx.requestRedraw();
    }
    fn stripTipAllowed(raw: *anyopaque, id: u64) bool {
        const self: *Workspace = @ptrCast(@alignCast(raw));
        _ = id;
        if (self.tab_menu_open) return false;
        if (self.group_tab_menu) |menu| if (menu.isOpen()) return false;
        return true;
    }


    /// Tab cell events (bubble phase, after the strip view recorded press state): select, the
    /// zeditor close column, context menu, middle-click close, double-click rename, Enter / Space.
    fn stripEvent(raw: *anyopaque, cell: *tab_strip.Cell, event: ui.events.Event) ui.events.EventResult {
        const self: *Workspace = @ptrCast(@alignCast(raw));
        const tab_id: identity.TabId = @fromBackingInt(cell.id);
        if (self.model.indexOf(tab_id) == null) return .ignored;
        if (event == .click and event.click.button == .left) {
            // zeditor close column: with the close glyph shown, a left click whose x falls in
            // its column (2pt either side, full cell height) closes without activating.
            if (cell.hovered and self.strip_vm.?.closeShown(cell.id)) if (cell.close) |chip| if (cell.surface) |surface| {
                const r = chip.globalRect();
                const s = surface.globalRect();
                if (r.w > 0 and event.click.x >= r.x - 2 and event.click.x <= s.x + s.w + tab_styles.outer_inset) {
                    self.closeTabById(tab_id);
                    return .stop;
                }
            };
            stripSelect(self, cell.id);
            return .handled;
        }
        // Keyboard: Enter / Space on a focused tab activates it (zeditor).
        if (event == .key_down and (event.key_down.key == .@"return" or event.key_down.key == .space)) {
            const focused = self.cx.focus_manager.getFocused();
            if (focused != null and cell.surface != null and focused == cell.surface) {
                self.activateTabId(tab_id);
                return .stop;
            }
        }
        if (self.groupIdByTab(tab_id)) |group| {
            if (event == .mouse_down and event.mouse_down.button == .right) {
                self.showGroupTabMenu(group, cell.surface orelse return .ignored) catch {};
                return .stop;
            }
            if (event == .mouse_down and event.mouse_down.button == .middle) {
                self.requestCloseGroup(group);
                return .stop;
            }
            if (event == .double_click and !self.groupClosing(group)) {
                self.beginRenamePresentation(tab_id) catch {};
                return .stop;
            }
            return .ignored;
        }
        const index = self.tabIndexById(tab_id) orelse return .ignored;
        const id = self.tabs.items[index].id;
        switch (event) {
            // 右键 / 中键不合成 click（zenit 事件契约），在 mouse_down 处理。
            .mouse_down => |mouse| {
                if (mouse.button == .right) {
                    const node = cell.surface orelse return .ignored;
                    self.menu_bridge.fireTab(.tab_right_click, index, self.model.tabs.items.len > 1, node.globalRect());
                    return .handled;
                }
                if (mouse.button == .middle) {
                    self.requestCloseTab(index);
                    return .handled;
                }
                return .ignored;
            },
            .double_click => {
                if (self.tabs.items[index].closing or self.rename_session == id) return .ignored;
                self.beginRenameTab(id) catch {};
                return .stop;
            },
            else => {},
        }
        return .ignored;
    }

    fn logHostSelection(self: *Workspace, index: usize, action: []const u8) void {
        if (index < self.registry.hosts.len) {
            applog.debug(.ui, "host row {s}: {s}", .{ action, self.registry.hosts[index].name });
        }
    }

    pub fn hostId(self: *const Workspace, index: usize) ?HostId {
        return self.identities.hostAt(index);
    }

    pub fn hostIndex(self: *const Workspace, id: HostId) ?usize {
        return self.identities.hostIndex(id);
    }

    /// The running session owns this snapshot even when its asset is deleted.
    pub fn tabHost(self: *const Workspace, index: usize) ?hosts_mod.HostConfig {
        if (index >= self.tabs.items.len) return null;
        return if (self.tabs.items[index].host_snapshot) |snapshot| snapshot.value else null;
    }

    pub fn activeHost(self: *const Workspace) ?hosts_mod.HostConfig {
        return self.tabHost(self.active_tab orelse return null);
    }

    pub fn tabIndex(self: *const Workspace, id: SessionId) ?usize {
        for (self.tabs.items, 0..) |tab, index| if (tab.id == id) return index;
        return null;
    }

    pub fn tabIndexById(self: *const Workspace, id: identity.TabId) ?usize {
        for (self.tabs.items, 0..) |tab, index| if (tab.tab_id == id) return index;
        return null;
    }

    pub fn visibleLocalTerminalTabRect(self: *const Workspace) ?ui.ComputedRect {
        if (self.tab_rebuild_pending or self.model.dragging) return null;
        for (self.tab_nodes.items) |cell| {
            const index = self.tabIndexById(cell.tab_id) orelse continue;
            if (!self.tabs.items[index].local) continue;
            const rect = cell.node.globalRect();
            if (rect.w > 0) return rect;
        }
        return null;
    }

    pub fn sessionTab(self: *const Workspace, id: SessionId) ?*SessionTab {
        return if (self.tabIndex(id)) |index| self.tabs.items[index] else null;
    }

    // ── AI environment (LIFECYCLE.md §5.2–5.3) ─────────────────────────
    // The current tab and group view, the tab set, and the group views with their docked cards are
    // part of the environment the AI host's pass checks; the AI host runs that pass on the frame
    // after the environment revision moved. Every write below publishes an actual change.

    /// The current tab index: the presented single-card tab, or the focused member of the presented
    /// group (`active_group_view`). Hosts that focus a member in place (a float card, a pane menu,
    /// a terminal command) set it here too; it never re-presents the tab body.
    pub fn setActiveTab(self: *Workspace, index: ?usize) void {
        if (self.active_tab == index) return;
        self.active_tab = index;
        self.noteEnvironment();
    }
    fn setActiveGroupView(self: *Workspace, group: ?u32) void {
        if (self.active_group_view == group) return;
        self.active_group_view = group;
        self.noteEnvironment();
    }
    /// A direct write to the tab set, the model's tab owners / containers, or the group views and
    /// their docked cards (each call site is an actual change).
    fn noteEnvironment(self: *const Workspace) void {
        _ = self;
        workspace_model.publishEnvironment();
    }
    /// Capacity was reserved before the tab's last fallible step.
    fn appendTabAssumeCapacity(self: *Workspace, tab: *SessionTab) void {
        self.tabs.appendAssumeCapacity(tab);
        self.noteEnvironment();
    }
    fn removeTabAt(self: *Workspace, index: usize) void {
        _ = self.tabs.orderedRemove(index);
        self.noteEnvironment();
    }

    pub fn bindSessionOwner(self: *Workspace, id: SessionId, handle: identity.SessionHandle) !void {
        const tab = self.sessionTab(id) orelse return error.InvalidTab;
        if (!tab.owned_pending) try self.model.replaceOwner(tab.tab_id, tab.content_owner, .{ .session = handle });
        tab.setContentOwner(.{ .session = handle });
    }

    /// Validate identities and reserve every fallible structure before making
    /// the pending terminal a member. This is the sole owned member commit.
    pub fn commitOwnedSession(self: *Workspace, group_owner: identity.GroupOwner, handle: identity.SessionHandle, id: SessionId) !u64 {
        const tab = self.sessionTab(id) orelse return error.StaleSession;
        if (!tab.content_owner.eql(.{ .session = handle }) or tab.closing or tab.isCard()) return error.StaleSession;
        const group_id = std.math.cast(u32, @backingInt(group_owner.id)) orelse return error.UnknownGroup;
        const roster = self.group_roster orelse return error.UnknownGroup;
        const group = roster.findById(group_id) orelse return error.UnknownGroup;
        if (self.groupClosing(group_id)) return error.GroupClosing;
        const parent = self.groupTabId(group_id) orelse return error.GroupNotOpen;
        const parent_index = self.model.indexOf(parent) orelse return error.GroupNotOpen;
        if (!self.model.tabs.items[parent_index].owner.eql(.{ .group = group_owner })) return error.StaleReference;
        if (!tab.owned_pending) {
            if (group.contains(id) and self.model.tabs.items[self.model.indexOf(tab.tab_id) orelse return error.TabClosed].container == parent) return group.membership_revision;
            return error.MembershipCommitFailed;
        }
        if (group.contains(id)) return error.MembershipCommitFailed;
        const revision = try identity.advance(group.membership_revision);
        try group.members.ensureUnusedCapacity(roster.allocator, 1);
        const ambient = self.creation_group;
        self.creation_group = null;
        defer self.creation_group = ambient;
        tab.setOwnedPending(false);
        errdefer tab.setOwnedPending(true);
        try self.installTabModel(tab);
        // No fallible work remains after publication of membership.
        const model_tab = &self.model.tabs.items[self.model.indexOf(tab.tab_id).?];
        model_tab.container = parent;
        self.model.active = parent;
        self.noteEnvironment();
        group.admitAssumeCapacity(id, revision);
        self.setActiveGroupView(group_id);
        self.group_present_pending = true;
        if (self.groupView(group_id)) |view| view.dirty = true;
        self.tab_rebuild_pending = true;
        self.cx.requestRedraw();
        return revision;
    }

    fn findTicket(self: *const Workspace, ticket: lifecycle.Ticket) ?*SessionTab {
        const index = self.tabIndex(ticket.session_id) orelse return null;
        const tab = self.tabs.items[index];
        return if (tab.ticket().matches(ticket)) tab else null;
    }

    /// Adds a config with workspace-owned storage. Persistence is explicit so
    /// quick-connect can also create temporary process-local assets.
    pub fn appendHost(self: *Workspace, host: hosts_mod.HostConfig) !usize {
        try host.validate();
        try self.identities.appendHosts(self.allocator, self.registry.hosts.len);
        const arena = self.registry.arena.allocator();
        const value = try lifecycle.cloneValue(hosts_mod.HostConfig, arena, host);
        const next = try arena.alloc(hosts_mod.HostConfig, self.registry.hosts.len + 1);
        @memcpy(next[0..self.registry.hosts.len], self.registry.hosts);
        next[next.len - 1] = value;
        try self.identities.appendHosts(self.allocator, next.len);
        self.registry.hosts = next;
        return next.len - 1;
    }

    /// Removes the asset only. Session snapshots and stable IDs are retained.
    pub fn applyAssetAction(self: *Workspace, request: @import("../../../config/asset_actions.zig").Request) !@import("../../../config/asset_actions.zig").Result {
        try self.identities.appendHosts(self.allocator, self.registry.hosts.len);
        const selected = if (self.selected_host) |position| self.hostId(position) else null;
        // Reserve the only potentially growing process-local projection before
        // committing. A disk failure must not publish a new sidebar identity.
        if (request == .clone) try self.identities.hosts.ensureTotalCapacity(self.allocator, self.registry.hosts.len + 1);
        const result = try @import("../../../config/asset_actions.zig").apply(self.allocator, self.io, std.Io.Dir.cwd(), self.hosts_path, &self.registry, request);
        switch (result.kind) {
            .clone => self.identities.appendHosts(self.allocator, self.registry.hosts.len) catch unreachable,
            .delete => _ = self.identities.removeHost(result.previous_index) catch unreachable,
            .move => if (result.index) |index| {
                if (index != result.previous_index) self.identities.moveHost(result.previous_index, index) catch unreachable;
            },
            .pin => {},
        }
        self.refreshAssetPositions(selected);
        self.rebuildSidebar() catch |err| {
            // Persistence succeeded. Do not turn a paint/allocation failure
            // into an action failure that would invite duplicating the write.
            applog.warn(.ui, "asset saved; sidebar refresh failed: {s}", .{@errorName(err)});
            self.statusFailure("配置已保存，列表刷新失败");
        };
        return result;
    }

    /// 删除主机（侧栏菜单“删除主机”）：可撤销。先从侧栏藏起来并弹出带“撤销”的 Toast，Toast 离场后才删除配置
    /// （连带它的凭据引用）；点“撤销”重新显示。已打开的会话不受影响。
    pub fn deleteHostUndoable(self: *Workspace, index: usize) !void {
        if (index >= self.registry.hosts.len) return error.InvalidHost;
        const host = self.registry.hosts[index];
        if (@backingInt(host.connection_id) == 0) return error.InvalidHost;
        if (self.hostDeletePending(host.connection_id)) return;
        self.host_delete_token +%= 1;
        const token = self.host_delete_token;
        try self.pending_host_deletes.append(self.allocator, .{ .token = token, .id = host.connection_id });
        if (self.selected_host == index) self.selected_host = null;
        self.rebuildSidebar() catch |err| applog.warn(.ui, "hide deleted host: {s}", .{@errorName(err)});
        const text = std.fmt.bufPrint(&self.host_delete_text, "已删除主机 {s}", .{host.name}) catch "已删除主机";
        _ = confirm_ui.undoable(self.cx, .{ .text = text, .owner = self, .context = self, .token = token, .commit = commitHostDelete, .revert = revertHostDelete });
    }
    pub fn hostDeletePending(self: *const Workspace, id: identity.ConnectionId) bool {
        for (self.pending_host_deletes.items) |pending| if (pending.id == id) return true;
        return false;
    }
    fn takeHostDelete(self: *Workspace, token: u64) ?identity.ConnectionId {
        for (self.pending_host_deletes.items, 0..) |pending, i| if (pending.token == token) {
            _ = self.pending_host_deletes.orderedRemove(i);
            return pending.id;
        };
        return null;
    }
    fn commitHostDelete(raw: *anyopaque, token: u64) void {
        const self: *Workspace = @ptrCast(@alignCast(raw));
        const id = self.takeHostDelete(token) orelse return;
        // The host may have changed or gone meanwhile (another window, an edit): rebuild the request
        // from the registry as it is now.
        const index = self.registry.indexOf(id) orelse return;
        const request: @import("../../../config/asset_actions.zig").Request = .{ .delete = .{ .owner = self.registry.hosts[index].owner() } };
        if (self.shutting_down) {
            _ = @import("../../../config/asset_actions.zig").apply(self.allocator, self.io, std.Io.Dir.cwd(), self.hosts_path, &self.registry, request) catch |err| applog.warn(.ui, "deferred host delete at shutdown: {s}", .{@errorName(err)});
            return;
        }
        _ = self.applyAssetAction(request) catch |err| {
            applog.warn(.ui, "deferred host delete: {s}", .{@errorName(err)});
            self.statusFailure(@import("../../../shared/base/error_text.zig").lineOr(err, "删除主机失败，主机配置尚未更改"));
            self.rebuildSidebar() catch {};
            return;
        };
        self.status("主机配置已删除，已打开的会话继续运行");
    }
    fn revertHostDelete(raw: *anyopaque, token: u64) void {
        const self: *Workspace = @ptrCast(@alignCast(raw));
        _ = self.takeHostDelete(token) orelse return;
        if (self.shutting_down) return;
        self.rebuildSidebar() catch |err| applog.warn(.ui, "restore deleted host: {s}", .{@errorName(err)});
    }

    pub fn removeHost(self: *Workspace, index: usize) !void {
        if (index >= self.registry.hosts.len) return error.InvalidHost;
        try self.identities.appendHosts(self.allocator, self.registry.hosts.len);
        const selected = if (self.selected_host) |position| self.hostId(position) else null;
        const next = try self.registry.arena.allocator().alloc(hosts_mod.HostConfig, self.registry.hosts.len - 1);
        @memcpy(next[0..index], self.registry.hosts[0..index]);
        @memcpy(next[index..], self.registry.hosts[index + 1 ..]);
        try self.saveHostSlice(next);
        _ = try self.identities.removeHost(index);
        self.registry.hosts = next;
        self.refreshAssetPositions(selected);
        try self.rebuildSidebar();
    }

    /// The asset moves to the first position of its own group, as shown by
    /// the sidebar menu. Running sessions continue to target their snapshots.
    pub fn pinHost(self: *Workspace, index: usize) !void {
        if (index >= self.registry.hosts.len) return error.InvalidHost;
        try self.identities.appendHosts(self.allocator, self.registry.hosts.len);
        const group = self.registry.hosts[index].group orelse "";
        var target: usize = 0;
        while (target < index and !std.mem.eql(u8, self.registry.hosts[target].group orelse "", group)) target += 1;
        if (target == index) return;
        const selected = if (self.selected_host) |position| self.hostId(position) else null;
        const next = try self.registry.arena.allocator().dupe(hosts_mod.HostConfig, self.registry.hosts);
        const picked = next[index];
        std.mem.copyBackwards(hosts_mod.HostConfig, next[target + 1 .. index + 1], next[target..index]);
        next[target] = picked;
        try self.saveHostSlice(next);
        try self.identities.moveHost(index, target);
        self.registry.hosts = next;
        self.refreshAssetPositions(selected);
        try self.rebuildSidebar();
    }

    pub fn replaceHost(self: *Workspace, index: usize, host: hosts_mod.HostConfig) !void {
        if (index >= self.registry.hosts.len) return error.InvalidHost;
        try host.validate();
        try self.identities.appendHosts(self.allocator, self.registry.hosts.len);
        const arena = self.registry.arena.allocator();
        const next = try arena.dupe(hosts_mod.HostConfig, self.registry.hosts);
        next[index] = try lifecycle.cloneValue(hosts_mod.HostConfig, arena, host);
        try self.saveHostSlice(next);
        self.registry.hosts = next;
        try self.rebuildSidebar();
    }

    fn saveHostSlice(self: *Workspace, hosts: []hosts_mod.HostConfig) !void {
        var candidate = self.registry;
        candidate.hosts = hosts;
        _ = try store.saveHostsWithOptions(self.io, std.Io.Dir.cwd(), self.hosts_path, candidate, .{ .provider = self.credential_provider });
    }

    fn refreshAssetPositions(self: *Workspace, selected: ?HostId) void {
        self.selected_host = if (selected) |id| self.hostIndex(id) else null;
        for (self.tabs.items) |tab| tab.host_index = self.hostIndex(tab.host_id) orelse removed_host_index;
    }

    /// 把当前注册表原子写回 hosts.toml（菜单 clone/pin/delete 持久化共用）。
    pub fn saveRegistry(self: *Workspace) !void {
        _ = try store.saveHostsWithOptions(self.io, std.Io.Dir.cwd(), self.hosts_path, self.registry, .{ .provider = self.credential_provider });
    }

    pub const StatusKind = enum { info, failure };

    pub fn status(self: *Workspace, text: []const u8) void {
        self.statusWithKind(text, .info);
    }
    pub fn statusFailure(self: *Workspace, text: []const u8) void {
        self.statusWithKind(text, .failure);
    }
    pub fn reportFailure(self: *Workspace, owner: identity.ContentOwner, text: []const u8) void {
        if (self.status_feedback) |feedback| feedback.publish(feedback.context, owner, text, .failure);
    }
    fn statusWithKind(self: *Workspace, text: []const u8, kind: StatusKind) void {
        if (self.command_output) |terminal| {
            terminal.showCommandMessage(text);
            return;
        }
        if (self.status_feedback) |feedback| feedback.publish(feedback.context, if (self.active_tab) |index| (if (index < self.tabs.items.len) self.tabs.items[index].content_owner else null) else null, text, kind);
        const target = self.status_node orelse return;
        var buffer: [768]u8 = undefined;
        target.setTextContent(self.allocator, @import("../../../shared/base/feedback_message.zig").message(text, &buffer)) catch return;
        target.markRenderDirty();
        self.cx.requestRedraw();
    }

    // ── Sidebar: data-driven host list from hosts.toml ───────────────

    pub fn setSidebarMenuOwner(self: *Workspace, owner: ?identity.AssetOwner) void {
        for (self.host_rows.items) |row| {
            const captured = row.click_ctx.asset_owner;
            row.view.setMenuOpen(owner != null and captured != null and std.meta.eql(owner.?, captured.?));
        }
    }

    pub fn setSidebarBridge(self: *Workspace, bridge: sidebar_view.Bridge) !void {
        self.sidebar_bridge = bridge;
        if (self.sidebar_chrome) |chrome| chrome.setBridge(bridge);
        try self.rebuildSidebar();
    }

    pub fn setBackgroundForwardBridge(self: *Workspace, bridge: BackgroundForwardBridge) void {
        self.background_forward_bridge = bridge;
        self.refreshBackgroundForwardBadges();
    }
    pub fn refreshBackgroundForwardBadges(self: *Workspace) void {
        for (self.host_rows.items) |row| {
            const owner = row.click_ctx.asset_owner orelse continue;
            row.view.setForwardBadge(self.backgroundForwardBadge(owner));
        }
    }
    fn backgroundForwardBadge(self: *Workspace, owner: identity.AssetOwner) ?sidebar_view.ForwardBadge {
        const bridge = self.background_forward_bridge;
        return if (bridge.badge) |read| read(bridge.context, owner) else null;
    }

    pub fn rebuildSidebar(self: *Workspace) !void {
        self.refreshSavedConnections() catch {};
        self.sidebar_drag_owner = null;
        self.sidebar_drop = null;
        self.sidebar_drop_marker = null;
        // Preserve an interrupted group's visible height across the registry's
        // safe-boundary row rebuild; persistence still owns the final state.
        const FoldFrame = struct { reference: sidebar_view.GroupRef, collapsed: bool, height: f32, animating: bool };
        var folds: std.ArrayList(FoldFrame) = .empty;
        defer folds.deinit(self.allocator);
        for (self.group_rows.items) |row| if (row.reference) |reference| {
            try folds.append(self.allocator, .{ .reference = reference, .collapsed = row.collapsed, .height = row.disclosure.root.globalRect().h, .animating = row.disclosure.animating });
        };
        try self.identities.appendHosts(self.allocator, self.registry.hosts.len);
        if (self.default_group_row) |row| if (!self.default_group_forced_open) {
            self.default_group_collapsed = row.collapsed;
        };
        self.default_group_row = null;
        // End focus/hover while handlers still own their scope. The rows below
        // are rebuilt only after the originating event has returned.
        for (self.sidebar_list.children.items) |child| self.cx.invalidateReferencesTo(child);
        if (self.sidebar_scope) |old| old.dispose();
        self.sidebar_scope = null;
        while (self.sidebar_list.children.items.len > 0) {
            const child = self.sidebar_list.children.items[self.sidebar_list.children.items.len - 1];
            self.cx.detachChild(self.sidebar_list, child);
            self.cx.destroyDetached(child);
        }
        self.host_rows.clearRetainingCapacity();
        self.group_headers.clearRetainingCapacity();
        self.group_rows.clearRetainingCapacity();
        const scope = try self.scope.childScope();
        self.sidebar_scope = scope;
        self.sidebar_list.setStyleInline(self.allocator, sidebar_view.styles.list());
        const query = self.search_query[0..self.search_len];
        self.default_group_forced_open = query.len > 0;
        for (0..self.registry.groups.len + 1) |group_index| {
            const group = if (group_index == 0) null else self.registry.groups[group_index - 1];
            const group_id = if (group) |value| value.group_id else null;
            if (group_id) |id| if (std.mem.indexOfScalar(identity.AssetGroupId, self.hidden_groups.items, id) != null) continue;
            var matches: std.ArrayList(usize) = .empty;
            defer matches.deinit(self.allocator);
            const ids = try self.registry.orderedIds(self.allocator, group_id);
            defer self.allocator.free(ids);
            var count: usize = 0;
            for (ids) |id| {
                const index = self.registry.indexOf(id) orelse continue;
                if (self.hostDeletePending(id)) continue;
                count += 1;
                if (self.sidebarMatches(index, query)) try matches.append(self.allocator, index);
            }
            // Unsaved quick-connect entries have a runtime host identity only.
            if (group_id == null) for (self.registry.hosts, 0..) |host, index| {
                if (@backingInt(host.connection_id) != 0) continue;
                count += 1;
                if (self.sidebarMatches(index, query)) try matches.append(self.allocator, index);
            };
            if (group == null and count == 0 and (self.registry.hosts.len == 0 or query.len > 0)) continue;
            if (query.len > 0 and matches.items.len == 0 and !@import("../../../shared/base/text_match.zig").matchesText(query, if (group) |value| value.name else "默认分组")) continue;
            const section = try sidebar_view.GroupRow.mount(self.cx, scope, .{
                .reference = if (group) |value| .{ .id = value.group_id, .revision = value.revision } else null,
                .name = if (group) |value| value.name else "默认分组",
                .count = count,
                .collapsed = if (query.len > 0) false else if (group) |value| value.collapsed else self.default_group_collapsed,
                .color = if (group) |value| sidebarGroupColor(value.color) else null,
            }, self.sidebar_bridge);
            if (group == null) self.default_group_row = section;
            if (group == null and count == 0) section.root.setDisplay(.none);
            try self.sidebar_list.appendChild(self.allocator, section.root);
            try self.group_headers.append(self.allocator, section.root);
            try self.group_rows.append(self.allocator, section);
            if (section.reference) |reference| for (folds.items) |fold| {
                if (fold.reference.id == reference.id and (fold.collapsed != section.collapsed or fold.animating)) {
                    section.disclosure.motion = .{ .value = fold.height, .target = fold.height, .from = fold.height };
                    section.disclosure.animating = true;
                    section.disclosure.root.setStyle(self.allocator, .height, .{ .px = fold.height });
                    break;
                }
            };
            for (matches.items) |index| {
                const host = self.registry.hosts[index];
                const context = try self.newClickCtx(index);
                const route = try self.sidebarRoute(host);
                defer self.allocator.free(route.text);
                const detail = try std.fmt.allocPrint(self.allocator, "{s}@{s}:{d}", .{ host.user, host.host, host.port });
                defer self.allocator.free(detail);
                const unavailable = try self.disabledPluginReason(host);
                defer if (unavailable) |text| self.allocator.free(text);
                const row = try sidebar_view.HostRow.mount(self.cx, scope, .{
                    .sidebar = &self.sidebar_chrome,
                    .name = host.name,
                    .kind = if (host.protocol == .sftp) .file else .terminal,
                    .icon = session_icon.forHost(self.plugins, host.protocolId(), @import("../host/session_os_cache.zig").load(self.allocator, self.io, self.hosts_path, host)),
                    .protocol = host.protocolId(),
                    .supports_route = route.supported,
                    .detail = detail,
                    .route = route.text,
                    .hops = route.hops,
                    .online = self.hostOnline(index),
                    .selected = self.selected_host == index,
                    .forward = self.backgroundForwardBadge(host.owner()),
                    .unavailable = unavailable,
                }, .{ .context = context, .select = onSidebarSelect, .connect = onSidebarConnect, .menu = onSidebarMenu, .action = onSidebarAction });
                context.node = row.node;
                // Buttons already own their capture handler (status/actions).
                // A parent drag binding preserves those handlers and normal clicks.
                const holder = try ui.box(self.cx, .{ .width = .fill(), .min_width = 0, .direction = .column, .flex_shrink = 0 }, .{});
                try holder.appendChild(self.allocator, row.node);
                if (context.asset_owner != null) context.drag_binding = try ui.interaction.drag.Binding.attach(scope, self.cx, holder, .{ .axis = .both }, onSidebarDrag, context);
                try section.members.appendChild(self.allocator, holder);
                try self.host_rows.append(self.allocator, .{ .node = row.node, .name_node = row.name, .host_index = index, .click_ctx = context, .view = row });
            }
        }
        if (query.len > 0 and self.host_rows.items.len == 0 and self.group_headers.items.len == 0) {
            const empty = try ui.box(self.cx, .{ .width = .fill(), .padding = ui.Padding.all(12) }, .{});
            _ = try sidebar_view.text(self.cx, empty, "未找到匹配的主机或分组", 11, 400, true);
            try self.sidebar_list.appendChild(self.allocator, empty);
        }
        const marker = try ui.box(self.cx, sidebar_view.styles.dropMarker(), .{});
        marker.meta.ownership.meta.test_id = "sidebar.drop_hint";
        (try marker.style.ensureExtFallible(self.allocator)).z_index = 20;
        marker.setDisplay(.none);
        try self.sidebar_list.appendChild(self.allocator, marker);
        self.sidebar_drop_marker = marker;
        self.cx.requestRedraw();
    }

    fn sidebarGroupRef(self: *const Workspace, id: ?identity.AssetGroupId) ?sidebar_view.GroupRef {
        const index = self.registry.groupIndex(id orelse return null) orelse return null;
        const group = self.registry.groups[index];
        return .{ .id = group.group_id, .revision = group.revision };
    }

    fn updateSidebarDrop(self: *Workspace, point: ui.interaction.drag.Point) void {
        self.sidebar_drop = null;
        self.sidebar_session_drop = null;
        self.clearTabDropFeedback();
        const marker = self.sidebar_drop_marker orelse return;
        marker.setDisplay(.none);
        if (self.groupingTargetAt(point, null)) |target| {
            self.sidebar_session_drop = target;
            self.showGroupDropFeedback(target, point);
            return;
        }
        const clip = if (self.sidebar_chrome) |view| view.viewport.globalRect() else self.sidebar_list.globalRect();
        if (point.x < clip.x or point.x > clip.x + clip.w or point.y < clip.y or point.y > clip.y + clip.h) return;
        const owner = self.sidebar_drag_owner orelse return;
        const source = self.registry.get(owner) catch return;
        var target: ?ui.ComputedRect = null;
        var destination: ?sidebar_view.GroupRef = null;
        var placement: @import("../../../config/asset_actions.zig").Placement = .end;
        for (self.host_rows.items) |row| {
            const rect = row.node.globalRect();
            if (!row.node.isDisplayedInTree() or point.x < rect.x or point.x > rect.x + rect.w or point.y < rect.y or point.y > rect.y + rect.h) continue;
            const host = self.registry.hosts[row.host_index];
            if (host.connection_id == owner.id or @backingInt(host.connection_id) == 0 or host.pinned != source.pinned) return;
            const after = point.y >= rect.y + rect.h / 2;
            target = .{ .x = rect.x, .y = rect.y + if (after) rect.h else 0, .w = rect.w, .h = 2 };
            destination = self.sidebarGroupRef(host.asset_group_id);
            placement = if (after) .{ .after = host.owner() } else .{ .before = host.owner() };
            break;
        }
        if (target == null) for (self.group_rows.items) |group| {
            const rect = group.header.globalRect();
            if (!group.root.isDisplayedInTree() or point.x < rect.x or point.x > rect.x + rect.w or point.y < rect.y or point.y > rect.y + rect.h) continue;
            target = .{ .x = rect.x, .y = rect.y + rect.h - 2, .w = rect.w, .h = 2 };
            destination = group.reference;
            break;
        };
        const rect = target orelse return;
        self.sidebar_drop = .{ .move = .{ .owner = owner, .source_group = self.sidebarGroupRef(source.asset_group_id), .destination = destination, .placement = placement } };
        const bounds = self.sidebar_list.globalRect();
        marker.setStyleInline(self.allocator, .{ .inset = .{ .left = .{ .px = rect.x - bounds.x }, .top = .{ .px = rect.y - bounds.y } }, .width = .{ .px = rect.w }, .display = .flex });
    }

    fn onSidebarDrag(event: ui.interaction.drag.Event, raw: *anyopaque) void {
        const context: *ClickCtx = @ptrCast(@alignCast(raw));
        const self = context.workspace;
        switch (event.phase) {
            .start => {
                self.sidebar_drag_owner = context.asset_owner;
                if (self.default_group_row) |group| if (group.count == 0) group.root.setDisplay(.flex);
            },
            .move => {},
            .end, .cancel => {
                if (event.phase == .end) {
                    self.updateSidebarDrop(event.position_window);
                    if (self.sidebar_session_drop) |target| {
                        if (self.pending_host_group_drop == null and self.pending_tab_drop == null)
                            self.pending_host_group_drop = .{ .owner = context.asset_owner.?, .target = target };
                    } else self.pending_sidebar_drop = self.sidebar_drop;
                }
                self.sidebar_session_drop = null;
                self.clearTabDropFeedback();
                self.sidebar_drag_owner = null;
                self.sidebar_drop = null;
                if (self.sidebar_drop_marker) |marker| marker.setDisplay(.none);
                if (self.default_group_row) |group| if (group.count == 0) group.root.setDisplay(.none);
                self.cx.requestRedraw();
                return;
            },
        }
        self.updateSidebarDrop(event.position_window);
        self.cx.requestRedraw();
    }

    fn sidebarMatches(self: *Workspace, index: usize, query: []const u8) bool {
        const host = self.registry.hosts[index];
        return @import("../../../shared/base/text_match.zig").matches(query, &.{ host.name, host.host, host.group orelse "" });
    }
    const SidebarRoute = struct { text: []const u8, hops: usize = 0, supported: bool = false };

    /// 已保存主机的协议插件被禁用（Q5）时，返回它不可连接的原因与恢复路径（qQaos 的 Tooltip 全文，调用方释放）；
    /// 插件已加载或是未知插件时为 null。
    pub fn disabledPlugin(self: *const Workspace, host: hosts_mod.HostConfig) ?@import("../model/plugin_availability.zig").Linked {
        const launch = self.plugin_launch orelse return null;
        return launch.disabled(host.protocolId());
    }
    fn disabledPluginReason(self: *Workspace, host: hosts_mod.HostConfig) !?[]u8 {
        const linked = self.disabledPlugin(host) orelse return null;
        return try @import("../model/plugin_availability.zig").reason(self.allocator, linked);
    }
    fn sidebarRoute(self: *Workspace, host: hosts_mod.HostConfig) !SidebarRoute {
        var ids = host.route;
        var names = host.jump_chain;
        var kvm_ids: [8]identity.ConnectionId = undefined;
        var supported = if (self.plugins.find(host.protocolId())) |plugin| plugin.supports(plugin_registry.legacyServiceDefinitions(&.{.route})[0]) else false;
        // KVM consumes SSH routes, but does not expose the legacy SSH route
        // service. Its persisted payload is the source for both count and hint.
        const kvm = @import("../../../plugins/bmc_ikvm/model.zig");
        if (std.mem.eql(u8, host.protocolId(), kvm.protocol_id)) {
            if (host.payload_version != kvm.payload_version) return .{ .text = try self.allocator.dupe(u8, "路径不可用") };
            var parsed = kvm.parse(self.allocator, host.plugin_payload orelse "") catch |err| switch (err) {
                error.OutOfMemory => return err,
                else => return .{ .text = try self.allocator.dupe(u8, "路径不可用") },
            };
            defer parsed.deinit();
            const hops = switch (parsed.value().access) {
                .direct => &.{},
                .ssh_route => |route| route.hops,
            };
            for (hops, 0..) |hop, i| kvm_ids[i] = @fromBackingInt(hop.asset_id);
            ids = kvm_ids[0..hops.len];
            names = &.{};
            supported = true;
        }
        const hops = if (ids.len > 0) ids.len else names.len;
        const parts = try self.allocator.alloc([]const u8, hops + 2);
        defer self.allocator.free(parts);
        parts[0] = "本机";
        for (0..hops) |i| parts[i + 1] = if (ids.len > 0) if (self.registry.indexOf(ids[i])) |position| self.registry.hosts[position].name else "缺失的跳板" else names[i];
        parts[hops + 1] = host.name;
        return .{ .text = try std.mem.join(self.allocator, " → ", parts), .hops = hops, .supported = supported };
    }
    fn sidebarIndex(cell: *ClickCtx) ?usize {
        if (cell.asset_owner) |owner| {
            _ = cell.workspace.registry.get(owner) catch return null;
            return cell.workspace.registry.indexOf(owner.id);
        }
        return cell.workspace.identities.hostIndex(cell.host_id orelse return null);
    }
    fn onSidebarAction(raw: *anyopaque, action: sidebar_view.HostAction) void {
        const cell: *ClickCtx = @ptrCast(@alignCast(raw));
        const index = sidebarIndex(cell) orelse return;
        const run = cell.workspace.menu_bridge.host_action orelse return;
        run(cell.workspace.menu_bridge.context, index, action);
    }
    fn onSidebarSelect(raw: *anyopaque) void {
        const cell: *ClickCtx = @ptrCast(@alignCast(raw));
        const index = sidebarIndex(cell) orelse return;
        cell.workspace.selected_host = index;
        cell.workspace.refreshSelection();
    }
    fn onSidebarConnect(raw: *anyopaque) void {
        const cell: *ClickCtx = @ptrCast(@alignCast(raw));
        const index = sidebarIndex(cell) orelse return;
        cell.workspace.selected_host = index;
        cell.workspace.refreshSelection();
        cell.workspace.newSession(index) catch |err| cell.workspace.statusFailure(@errorName(err));
    }
    /// Group broadcast fact of a session (connection details card, Pencil lBTBA).
    /// Null when the session is not a group member: broadcast only exists in groups.
    pub fn sessionBroadcast(self: *const Workspace, id: SessionId) ?struct { group: u32, enabled: bool } {
        const tab = self.sessionTab(id) orelse return null;
        const group = self.groupIdByTab(tab.tab_id) orelse blk: {
            // Members keep their own tab id; the group container owns the strip tab.
            const at = self.model.indexOf(tab.tab_id) orelse return null;
            const container = self.model.tabs.items[at].container orelse return null;
            break :blk self.groupIdByTab(container) orelse return null;
        };
        return .{ .group = group, .enabled = tab.group_broadcast_enabled };
    }
    /// Runs the same member toggle as the pane header's broadcast button.
    pub fn toggleSessionBroadcast(self: *Workspace, id: SessionId) void {
        const fact = self.sessionBroadcast(id) orelse return;
        if (self.group_action) |action| action(self.group_action_context, fact.group, id, .toggle_broadcast);
    }
    /// Mounts the empty-state saved connections list under `parent`.
    pub fn mountSavedConnections(self: *Workspace, parent: *ui.Node) !void {
        const Saved = @import("empty_saved_connections.zig");
        self.saved_connections = try Saved.View.mount(self.cx, self.scope, parent, .{ .context = self, .run = savedConnect });
        try self.refreshSavedConnections();
    }
    pub fn refreshSavedConnections(self: *Workspace) !void {
        const Saved = @import("empty_saved_connections.zig");
        const view = self.saved_connections orelse return;
        var picked_buffer: [Saved.max_rows]usize = undefined;
        const picked = Saved.pick(self.registry.hosts, &self.recent_connections, &picked_buffer);
        var entries: [Saved.max_rows]Saved.Entry = undefined;
        var routes: [Saved.max_rows]?[]const u8 = @splat(null);
        defer for (routes) |text| if (text) |value| self.allocator.free(value);
        var reasons: [Saved.max_rows]?[]u8 = @splat(null);
        defer for (reasons) |text| if (text) |value| self.allocator.free(value);
        var shown: usize = 0;
        for (picked) |index| {
            const host = self.registry.hosts[index];
            // 撤销窗口里的“删除主机”与侧栏一样先藏起来。
            if (self.hostDeletePending(host.connection_id)) continue;
            const i = shown;
            shown += 1;
            const route = try self.sidebarRoute(host);
            routes[i] = route.text;
            // 与侧栏同一规则（Q5 qQaos）：协议插件被禁用时标“已禁用”、不能连接。
            reasons[i] = try self.disabledPluginReason(host);
            entries[i] = .{ .index = index, .name = host.name, .protocol = host.protocolId(), .sftp = host.protocol == .sftp and host.protocol_id == null, .hops = route.hops, .unavailable = reasons[i] };
        }
        try view.update(entries[0..shown]);
    }
    /// Same path as the sidebar row's connect action.
    fn savedConnect(raw: *anyopaque, index: usize) void {
        const self: *Workspace = @ptrCast(@alignCast(raw));
        if (index >= self.registry.hosts.len) return;
        if (self.disabledPlugin(self.registry.hosts[index]) != null) return;
        self.selected_host = index;
        self.refreshSelection();
        self.newSession(index) catch |err| self.statusFailure(@errorName(err));
    }
    fn onSidebarMenu(raw: *anyopaque, node: *ui.Node) void {
        const cell: *ClickCtx = @ptrCast(@alignCast(raw));
        const index = sidebarIndex(cell) orelse return;
        cell.workspace.selected_host = index;
        cell.workspace.refreshSelection();
        cell.workspace.menu_bridge.fireHost(.host_right_click, index, node.globalRect());
    }
    fn sidebarGroupColor(value: []const u8) ?ui.Color {
        if (value.len == 7 and value[0] == '#') return ui.Color.hex(std.fmt.parseInt(u24, value[1..], 16) catch return null);
        if (std.mem.eql(u8, value, "blue") or std.mem.eql(u8, value, "purple")) return app_theme.current().accent;
        if (std.mem.eql(u8, value, "green")) return app_theme.current().ok;
        if (std.mem.eql(u8, value, "orange")) return app_theme.current().warn;
        return null;
    }

    /// mockup-main 侧栏状态点：有存活会话（runtime 已连接）的主机为绿，
    /// 其余灰（#CBD5E1）。失败会话由页签红点表达，主机行不标红。
    pub fn hostOnline(self: *Workspace, host_index: usize) bool {
        for (self.tabs.items) |tab| {
            if (tab.host_id != self.identities.hostAt(host_index) or tab.failed) continue;
            if (tab.terminal) |*terminal| {
                if (tab.runtime != null and terminal.tombstone.state == .active) return true;
            } else if (tab.file_ready) return true;
        }
        return false;
    }

    fn refreshSelection(self: *Workspace) void {
        for (self.host_rows.items) |row| row.view.setSelected(self.selected_host == row.host_index);
        self.cx.requestRedraw();
    }

    pub fn setSearch(self: *Workspace, query: []const u8) void {
        const n = @min(query.len, self.search_query.len);
        @memcpy(self.search_query[0..n], query[0..n]);
        self.search_len = n;
        self.rebuildSidebar() catch return;
    }

    // ── Tabs ─────────────────────────────────────────────────────────

    /// 稿 3 tab names: user rename > host name > Local cwd basename (with the
    /// foreground program); duplicates get the shortest distinguishing suffix.
    /// Presentation only: writes `Tab.display`, never the rename revision.
    /// The name every surface shows for a session tab (稿 3 derived name).
    pub fn shownName(self: *const Workspace, tab: *const SessionTab) []const u8 {
        if (self.model.indexOf(tab.tab_id)) |at| return self.model.tabs.items[at].name();
        return tab.titleSlice();
    }

    /// Local workers wake presentation after publishing a changed CWD or foreground process.
    pub fn refreshTabNames(self: *Workspace, force: bool) void {
        const revision = if (self.session_bridge.local_metadata_revision) |get| get(self.session_bridge.context) else 0;
        if (!force and !self.tab_rebuild_pending and revision == self.names_metadata_revision) return;
        const count = self.model.tabs.items.len;
        if (count == 0) {
            self.names_metadata_revision = revision;
            return;
        }
        var arena_state = std.heap.ArenaAllocator.init(self.allocator);
        defer arena_state.deinit();
        const arena = arena_state.allocator();
        const sources = arena.alloc(tab_naming.Source, count) catch return;
        const ids = arena.alloc(?identity.TabId, count) catch return;
        var used: usize = 0;
        const home = homeDirectory();
        for (self.model.tabs.items) |*model_tab| {
            // Group containers keep “组 · 组名”; members are named like tabs.
            if (model_tab.owner == .group) continue;
            const custom: ?[]const u8 = if (model_tab.custom) model_tab.baseName() else null;
            var source: tab_naming.Source = .{ .kind = .other, .custom = custom, .label = model_tab.baseName() };
            if (self.tabIndexById(model_tab.id)) |at| {
                const tab = self.tabs.items[at];
                if (tab.local and !tab.isCard()) {
                    source.kind = .local;
                    source.home = home;
                    source.suffix = switch (tab.local_state) {
                        .failed => "启动失败",
                        .exited => "已退出",
                        else => "",
                    };
                    if (tab.local_state == .running) {
                        if (self.session_bridge.local_cwd) |copy| source.cwd = copy(self.session_bridge.context, tab.id, arena);
                        if (self.session_bridge.local_program) |program| {
                            const buffer = arena.create([64]u8) catch null;
                            if (buffer) |b| source.program = program(self.session_bridge.context, tab.id, b);
                        }
                    }
                } else if (!tab.isCard() and (tab.host_snapshot != null or tab.plugin_protocol_id.len != 0 or tab.terminal != null)) {
                    source.kind = .remote;
                    source.label = tab.titleSlice();
                }
            }
            sources[used] = source;
            ids[used] = model_tab.id;
            used += 1;
        }
        const names = tab_naming.resolve(arena, sources[0..used]) catch return;
        self.names_metadata_revision = revision;
        var changed = false;
        for (names, ids[0..used]) |name, id| changed = self.model.setDisplayName(id.?, name) or changed;
        if (changed) {
            self.rebuildTabBar() catch {};
        }
    }

    pub fn rebuildTabBar(self: *Workspace) !void {
        try self.startPollLoop();
        self.tab_rebuild_pending = true;
        self.cx.requestRedraw();
    }

    /// 页签菜单“颜色 ›”（稿 3）：跟随环境 · 6 色 · 无。The menu passes its captured TabId, never the
    /// current active session. A session-group tab has no environment: “跟随环境” is not offered for it.
    pub fn setTabColor(self: *Workspace, id: identity.TabId, color: menus_model.TabColor) bool {
        if (self.groupIdByTab(id)) |group_id| {
            if (color == .follow) return false;
            const group = (self.group_roster orelse return false).findById(group_id) orelse return false;
            group.color = switch (color) {
                .rgb => |value| 0xff000000 | value,
                // Alpha 0: no tint (groupTabColor).
                else => group.color & 0xffffff,
            };
        } else {
            const index = self.tabIndexById(id) orelse return false;
            const tab = self.tabs.items[index];
            if (tab.closing) return false;
            tab.tab_color = menus_model.tabColorStored(color);
        }
        self.rebuildTabBar() catch return false;
        return true;
    }
    /// The colour the tab menu shows as chosen (稿 3 “颜色：紫（自定义）”).
    pub fn tabColorChoice(self: *Workspace, id: identity.TabId) ?menus_model.TabColor {
        if (self.groupIdByTab(id)) |group_id| {
            const group = (self.group_roster orelse return null).findById(group_id) orelse return null;
            if (group.color >> 24 == 0) return .none;
            return .{ .rgb = @as(u32, @truncate(group.color)) & 0xffffff };
        }
        const index = self.tabIndexById(id) orelse return null;
        return menus_model.tabColorOf(self.tabs.items[index].tab_color);
    }


    pub fn setNotificationAttentionBridge(self: *Workspace, bridge: NotificationAttentionBridge) void {
        self.notification_attention_bridge = bridge;
        self.refreshNotificationAttention();
    }

    /// Per-frame tab visuals: type icon (history / detected OS), its tint, the connection dot and
    /// the attention bounce of unread background tabs. The existing host owns activity / read
    /// receipts; the animation never changes their generations.
    pub fn refreshNotificationAttention(self: *Workspace) void {
        self.refreshStripVisuals() catch |err| applog.warn(.ui, "tab visuals: {s}", .{@errorName(err)});
    }
    fn refreshStripVisuals(self: *Workspace) !void {
        const vm = self.strip_vm orelse return;
        const list = &vm.scratch;
        list.clearRetainingCapacity();
        const recompute = self.strip_icons_dirty;
        self.strip_icons_dirty = false;
        for (vm.rows_signal.peek()) |row| {
            const id: identity.TabId = @fromBackingInt(row.id);
            const at = self.model.indexOf(id) orelse continue;
            const previous = vm.visual(row.id);
            const asset = if (self.groupIdByTab(id) != null) ui.icons.columns_2 else if (self.tabIndexById(id)) |index| blk: {
                const tab = self.tabs.items[index];
                const known = vm.hasVisual(row.id);
                const history_now = tabShowsHistory(tab);
                const history_shown = previous.icon.icon_id == session_icon.resolve(.history).icon_id;
                break :blk if (recompute or !known or history_now != history_shown) self.tabIcon(tab) else previous.icon;
            } else continue;
            const tab = &self.model.tabs.items[at];
            var bounce: f32 = 0;
            const unread = self.tabHasActivity(id);
            if (!unread) tab.attention_started_ms = null;
            const background = !(self.cx.window_active and self.model.active == id);
            if (unread and background and !self.command_held) {
                if (tab.attention_started_ms == null) tab.attention_started_ms = self.cx.frame_time_ms;
                const elapsed = @max(0, self.cx.frame_time_ms - tab.attention_started_ms.?);
                bounce = tab_styles.attentionOffset(elapsed);
                if (elapsed < tab_styles.attention_duration_ms) self.cx.scheduleRedrawAfterNs(16 * std.time.ns_per_ms);
            }
            try list.append(self.allocator, .{ .id = row.id, .icon = asset, .tint = self.tabTypeTint(id, asset), .dot = self.tabConnectionColor(id), .bounce = bounce });
        }
        try vm.setVisuals(list.items);
        for (self.tab_nodes.items) |*node| node.icon_asset = vm.visual(@backingInt(node.tab_id)).icon;
    }
    fn tabIsBouncing(self: *Workspace, id: identity.TabId) bool {
        if (!self.tabHasActivity(id) or (self.cx.window_active and self.model.active == id)) return false;
        const at = self.model.indexOf(id) orelse return false;
        const started = self.model.tabs.items[at].attention_started_ms orelse return true;
        return @max(0, self.cx.frame_time_ms - started) < tab_styles.attention_duration_ms;
    }

    fn tabHasActivity(self: *Workspace, id: identity.TabId) bool {
        const has_activity = self.notification_attention_bridge.has_dot orelse return false;
        for (self.model.tabs.items) |item| if (item.id == id or item.container == id) {
            if (has_activity(self.notification_attention_bridge.context, item.owner)) return true;
        };
        return false;
    }

    fn installTabModel(self: *Workspace, tab: *SessionTab) !void {
        std.debug.assert(card_placement.consistent(tab.card_type, tab.content_owner == .session));
        tab.tab_color = self.creation_tab_color;
        if (self.owned_creation_pending) {
            tab.setOwnedPending(true);
            tab.owned_origin = true;
            tab.root.setDisplay(.none);
            return;
        }
        try self.model.tabs.ensureUnusedCapacity(self.allocator, self.prepared_group_views + 1);
        try self.model.recent.ensureUnusedCapacity(self.allocator, self.prepared_group_views + 1);
        try self.model.append(tab.tab_id, tab.content_owner, tab.titleSlice());
        errdefer self.model.completeClose(tab.tab_id, tab.content_owner) catch {};
        const detail = if (tab.host_snapshot) |saved| blk: {
            const protocol = saved.value.protocolId();
            const fallback = try std.ascii.allocUpperString(self.allocator, protocol);
            defer self.allocator.free(fallback);
            const kind = if (self.plugins.find(protocol)) |manifest| manifest.display_name else fallback;
            break :blk try std.fmt.allocPrint(self.allocator, "{s}@{s}:{d} · {s}", .{ saved.value.user, saved.value.host, saved.value.port, kind });
        } else try self.allocator.dupe(u8, if (tab.local) "本机 · macOS · /bin/zsh" else if (self.plugins.find(tab.plugin_protocol_id)) |manifest| manifest.display_name else tab.titleSlice());
        defer self.allocator.free(detail);
        try self.model.setDetails(tab.tab_id, detail);
        if (self.creation_group) |group_id| if (self.group_roster) |roster| if (roster.findById(group_id)) |group| {
            if (!self.groupClosing(group_id) and tab.content_owner == .session and !tab.isCard()) {
                _ = try roster.join(group.name, tab.id, group.color);
                if (self.groupTabId(group_id)) |parent| try self.model.setContainer(tab.tab_id, parent);
                self.setActiveGroupView(group_id);
                self.group_present_pending = true;
                if (self.groupView(group_id)) |view| view.dirty = true;
            }
        };
        self.reveal_active = true;
    }

    /// 稿 3 widths and overflow: content width 88–200 (groups 160–240), shrink toward the minimum,
    /// then the least recently used inactive tabs go into “⌄ n”. `arena` holds `strip_shown`.
    fn measureTabs(self: *Workspace, arena: std.mem.Allocator) !void {
        const count = self.model.visibleCount();
        try self.strip_advances.resize(self.allocator, count);
        try self.strip_widths.resize(self.allocator, count);
        try self.strip_grouped.resize(self.allocator, count);
        const shown = try arena.alloc(bool, count);
        const ranks = try arena.alloc(usize, count);
        const family = if (self.font_family_resolver) |resolve| resolve("Inter Variable") else 0;
        var active: ?usize = null;
        for (self.strip_advances.items, ranks, 0..) |*advance, *rank, ordinal| {
            const tab = &self.model.tabs.items[self.model.visibleAt(ordinal).?];
            if (self.model.active == tab.id) active = ordinal;
            // Most recently used first; tabs never activated count as the oldest.
            rank.* = std.mem.indexOfScalar(identity.TabId, self.model.recent.items, tab.id) orelse self.model.recent.items.len;
            const grouped = tab.owner == .group;
            self.strip_grouped.items[ordinal] = grouped;
            // 稿 3: “组 · 组名” plus a never-truncated “(n)” member count.
            var count_buffer: [16]u8 = undefined;
            const count_text = if (grouped) tab_naming.memberCount(&count_buffer, self.groupMemberCount(tab.id)) else "";
            const extra: f32 = if (grouped) @ceil(self.cx.text.measureTextWidth(count_text, tab_styles.title_font, tab_styles.active_title_weight, false)) + tab_styles.group_count_gap else 0;
            // Measured at the active 600 weight so activating a tab never
            // truncates its title (zeditor reserves the bold width).
            // Match the visual line used by native Text's ellipsis check.
            // Round outward so adding/removing the chrome cannot round
            // a fractional title width down and spuriously truncate it.
            const line = self.cx.text.visualLine(.{ .text = tab.name(), .font_family = if (family != 0) "Inter Variable" else "system", .font_family_id = family, .font_size = tab_styles.title_font, .font_weight = tab_styles.active_title_weight }) catch {
                advance.* = @ceil(self.cx.text.measureTextWidth(tab.name(), tab_styles.title_font, tab_styles.active_title_weight, false)) + extra;
                continue;
            };
            advance.* = @ceil(line.width) + extra;
        }
        self.header_width = @max(0, self.cx.viewport.width - 2 * @import("../../shell/view/shell_styles.zig").outer);
        self.strip_geometry = try tab_layout.plan(.{ .available = self.tab_budget orelse @max(0, self.header_width - 272), .advances = self.strip_advances.items, .grouped = self.strip_grouped.items, .active = active, .rank = ranks }, self.strip_widths.items, shown);
        self.strip_shown = shown;
        self.reveal_active = false;
    }

    /// The tab strip view (`tab_strip.yix`), mounted under `tab_bar` on first use.
    pub fn tabStrip(self: *Workspace) !*tab_strip.ViewModel {
        if (self.strip_vm) |vm| return vm;
        const vm = try tab_strip.ViewModel.mount(self.cx, self.scope, .{ .context = self, .select = stripSelect, .close = stripClose, .event = stripEvent, .drag = stripDrag, .overflow = stripOverflow, .tip_allowed = stripTipAllowed, .mounted = stripRowBound, .unmounted = stripRowBound });
        self.tab_bar.setStyleInline(self.allocator, .{ .width = .{ .fit = .{} }, .height = .{ .px = tab_styles.height }, .gap = 0, .flex_shrink = 0 });
        try self.tab_bar.appendChild(self.allocator, vm.root);
        self.strip_vm = vm;
        return vm;
    }

    /// Rows for the strip (names, widths, tooltips, ⌘ ordinals) and the “⌄ n” overflow menu.
    /// Rows update in place by tab id; nothing here writes node styles.
    fn renderTabBar(self: *Workspace) !void {
        if (self.model.dragging) return;
        const vm = try self.tabStrip();
        if (self.tab_generation == std.math.maxInt(u64)) return error.RevisionExhausted;
        self.tab_generation += 1;
        const arena = vm.nextArena();
        try self.measureTabs(arena);
        const count = self.model.visibleCount();
        var rows: std.ArrayList(tab_strip.Row) = .empty;
        var hidden: std.ArrayList(app_menu.Entry) = .empty;
        for (0..count) |ordinal| {
            const index = self.model.visibleAt(ordinal).?;
            const model_tab = &self.model.tabs.items[index];
            const id = @backingInt(model_tab.id);
            const grouped = self.groupIdByTab(model_tab.id) != null;
            const ordinal_text: []const u8 = if (tab_naming.commandOrdinal(ordinal, count)) |digit| self.ordinalHint(digit) else "";
            const name = try arena.dupe(u8, model_tab.name());
            if (!self.strip_shown[ordinal]) {
                // 稿 3 “⌄ n”: the type icon (tinted like the tab) · name · ⌘ shortcut.
                const asset = if (grouped) ui.icons.columns_2 else if (self.tabIndexById(model_tab.id)) |at| self.tabIcon(self.tabs.items[at]) else ui.icons.terminal;
                const tint = self.tabIdentityColor(model_tab.id);
                const icon = try arena.create(ui.SvgAsset);
                icon.* = asset;
                const command: ?app_menu.Command = if (tab_naming.commandOrdinal(ordinal, count)) |digit| @enumFromInt(@intFromEnum(shortcut_router.Command.tab_1) + @as(usize, digit) - 1) else null;
                try hidden.append(arena, .{ .id = try std.fmt.allocPrint(arena, "{d}", .{id}), .label = name, .test_id = try std.fmt.allocPrint(arena, "tabs.all.item.{d}", .{id}), .command = command, .icon_asset = icon, .tint = if (tint) |color| (@as(u32, color.r) << 16) | (@as(u32, color.g) << 8) | color.b else null });
                continue;
            }
            const width = self.strip_widths.items[ordinal];
            const surface = tab_styles.surfaceWidth(width);
            var title_width = tab_styles.titleWidth(surface);
            var count_text: []const u8 = "";
            var count_width: f32 = 0;
            if (grouped) {
                // 稿 3: truncate the group name, never the member count.
                var count_buffer: [16]u8 = undefined;
                count_text = try arena.dupe(u8, tab_naming.memberCount(&count_buffer, self.groupMemberCount(model_tab.id)));
                const weight: u16 = if (self.model.active == model_tab.id) tab_styles.active_title_weight else tab_styles.title_weight;
                count_width = @ceil(self.cx.text.measureTextWidth(count_text, tab_styles.title_font, weight, false)) + 1;
                const name_width = @max(0, self.strip_advances.items[ordinal] - count_width + 1 - tab_styles.group_count_gap);
                title_width = @max(0, @min(name_width, title_width - count_width - tab_styles.group_count_gap));
            }
            const hint = try self.tabTooltipText(ordinal, index);
            defer self.allocator.free(hint);
            var anchor_buffer: [48]u8 = undefined;
            var id_buffer: [48]u8 = undefined;
            const cell = try vm.cellFor(id);
            const previous = rows.getLastOrNull();
            try rows.append(arena, .{
                .id = id,
                .width = width,
                .active = self.model.active == model_tab.id,
                .previous_id = if (previous) |row| row.id else null,
                .previous_active = if (previous) |row| row.active else false,
                .grouped = grouped,
                .name = try cell.text(.name, name),
                .count = try cell.text(.count, count_text),
                .title_width = title_width,
                .count_width = count_width,
                .tip = try cell.text(.tip, hint),
                .ordinal = try cell.text(.ordinal, ordinal_text),
                .close_label = if (grouped) "关闭组内全部会话" else "关闭页签",
                .test_id = try cell.text(.test_id, try std.fmt.bufPrint(&id_buffer, "tabs.tab.{d}", .{id})),
                .cell_test_id = try cell.text(.cell_test_id, try std.fmt.bufPrint(&id_buffer, "tabs.cell.{d}", .{id})),
                .close_test_id = if (grouped) "groups.close" else try cell.text(.close_test_id, try std.fmt.bufPrint(&id_buffer, "tabs.close.{d}", .{id})),
                .anchor = try cell.text(.anchor, tab_strip_model.tabAnchorId(&anchor_buffer, id) orelse ""),
            });
        }
        const label = if (hidden.items.len == 0) "" else try std.fmt.allocPrint(arena, "{d}", .{hidden.items.len});
        // “⌄ n”: the one menu projection (app_menu.build), shortcut text from the router.
        const overflow = try arena.create(app_menu.Built);
        vm.setRows(rows.items, app_menu.build(overflow, hidden.items, self.shortcuts()), label);
        // The strip's own box takes a definite width (tabs + “⌄ n” slot + “+” slot) so the title bar
        // never grows with its content and the chrome's tab budget stays the window's.
        const plus = if (vm.new_tab) |button| @max(tab_styles.new_tab_size, button.globalRect().w) else tab_styles.new_tab_size;
        const tail: f32 = (if (hidden.items.len != 0) tab_layout.overflow_reserve else 0) + plus + (if (rows.items.len != 0) @as(f32, 4) else 0);
        self.tab_bar.setStyle(self.allocator, .width, .{ .px = self.strip_geometry.content + tail });
        self.strip_icons_dirty = true;
        try self.refreshStripVisuals();
        try self.collectTabNodes();
        self.refreshCommandIcons();
        self.cx.requestRedraw();
    }

    /// `tab_nodes` in strip order from the mounted rows (read-only node references). Called when the
    /// rows are written (`renderTabBar`: order and model indexes) and whenever a row mounts or
    /// unmounts (`stripRowBound`): the list reconciles those writes when the reactive batch they were
    /// made in ends, so a row written from an after-layout hook is only mounted after `renderTabBar`.
    fn collectTabNodes(self: *Workspace) !void {
        const vm = self.strip_vm orelse return;
        self.tab_nodes.clearRetainingCapacity();
        for (vm.rows_signal.peek()) |row| {
            const cell = vm.findCell(row.id) orelse continue;
            const id: identity.TabId = @fromBackingInt(row.id);
            try self.tab_nodes.append(self.allocator, .{
                .node = cell.surface orelse continue,
                .holder = cell.holder orelse continue,
                .icon = cell.ordinal orelse continue,
                .type_icon = cell.icon_slot orelse continue,
                .icon_asset = vm.visualNow(row.id).icon,
                .label = cell.title orelse continue,
                .close = cell.close orelse continue,
                .tab_id = id,
                .tab_index = self.model.indexOf(id) orelse continue,
                .cell = cell,
            });
        }
    }

    fn tabShowsHistory(tab: *const SessionTab) bool {
        return tab.isCard() or (if (tab.terminal) |terminal| terminal.history.selected != null else false);
    }

    fn tabIcon(self: *Workspace, tab: *SessionTab) ui.SvgAsset {
        if (tabShowsHistory(tab)) return session_icon.resolve(.history);
        if (tab.local) return session_icon.forOs(@import("../../../proto/ssh/remote_os.zig").local()) orelse session_icon.resolve(.terminal);
        if (tab.plugin_protocol_id.len != 0) return session_icon.forConnection(self.plugins, tab.plugin_protocol_id, self.tabOs(tab), false);
        if (tab.host_snapshot) |saved| return session_icon.forConnection(self.plugins, saved.value.protocolId(), self.tabOs(tab), false);
        return session_icon.forTab(tab.local, false, tab.terminal != null);
    }

    /// The menu bar consumes the same visible Tab name, icon and status tint.
    /// Group members resolve to their container rather than duplicate its row.
    pub fn tabPresentation(self: *Workspace, owner: identity.ContentOwner) ?@import("../../../host/tab_presentation.zig").Presentation {
        var source_index: ?usize = null;
        for (self.model.tabs.items, 0..) |item, index| if (item.owner.eql(owner)) {
            source_index = index;
            break;
        };
        const source = self.model.tabs.items[source_index orelse return null];
        const index = if (source.container) |container| self.model.indexOf(container) orelse return null else source_index.?;
        const model_tab = &self.model.tabs.items[index];
        for (self.tab_nodes.items) |node| if (node.tab_id == model_tab.id) {
            const asset = node.icon_asset;
            const state = self.tabIconState(model_tab.id);
            // 稿 3: the same identity / environment tint as the strip's type icon.
            const tint = self.tabTypeTint(model_tab.id, asset);
            const tinted = state == .normal and self.tabIdentityColor(model_tab.id) != null;
            const backdrop = session_icon.artworkBackdrop(asset.icon_id.?);
            const artwork = @import("../../../shared/ui/assets/host_os_assets.zig");
            return .{
                .tab_id = model_tab.id,
                .order = index,
                .title = model_tab.name(),
                .icon_svg = asset.svg_data,
                .icon_rgba = if (artwork.index(asset.icon_id.?)) |i| if (state == .normal) artwork.display_pixels[i] else artwork.status_pixels[i] else &.{},
                .icon_original = state == .normal and !tinted and artwork.index(asset.icon_id.?) != null,
                .icon_bouncing = self.tabIsBouncing(model_tab.id),
                .icon_id = asset.icon_id.?,
                .icon_tint = (@as(u32, tint.r) << 24) | (@as(u32, tint.g) << 16) | (@as(u32, tint.b) << 8) | tint.a,
                .icon_backdrop = (@as(u32, backdrop.r) << 24) | (@as(u32, backdrop.g) << 16) | (@as(u32, backdrop.b) << 8) | backdrop.a,
                .current = self.model.active == model_tab.id,
                .status = self.tabStatus(model_tab.id),
            };
        };
        return null;
    }


    pub fn tabIconState(self: *Workspace, id: identity.TabId) session_icon.TabState {
        if (self.groupIdByTab(id) != null) return .normal;
        const index = self.tabIndexById(id) orelse return .normal;
        const tab = self.tabs.items[index];
        if (tab.isCard() or tab.closing) return .normal;
        if (tab.local) return switch (tab.local_state) {
            .starting => .connecting,
            .failed, .cleanup_unknown => .failed,
            else => .normal,
        };
        if (tab.terminal) |terminal| if (terminal.tombstone.state == .reconnecting) return .connecting;
        if (tab.remote_notice) |notice| if (notice.snapshot) |snapshot| switch (snapshot.state) {
            .reconnecting => return .connecting,
            .disconnected, .retry_failed => return .failed,
            .cancelled, .exited => return .normal,
            .connected => {},
        };
        if (tab.failed) return .failed;
        if (tab.plugin_renderer != null) return switch (pluginConnectionState(tab)) {
            .degraded => .failed,
            .connecting => .connecting,
            else => .normal,
        };
        if (tab.terminal) |terminal| {
            if (terminal.tombstone.state != .active) return .normal;
            return if (tab.runtime == null) .connecting else .normal;
        }
        return if (tab.file_ready or tab.content_ready) .normal else .connecting;
    }

    fn tabConnectionColor(self: *Workspace, id: identity.TabId) ui.Color {
        return status_tone.dot(presenter.present(self.tabConnectionPhase(id) orelse .ended).tone);
    }

    fn tabOs(self: *Workspace, tab: *SessionTab) session_icon.Os {
        if (tab.detected_os != .unknown) return tab.detected_os;
        if (tab.host_snapshot) |saved| return @import("../host/session_os_cache.zig").load(self.allocator, self.io, self.hosts_path, saved.value);
        if (tab.host_index < self.registry.hosts.len) return @import("../host/session_os_cache.zig").load(self.allocator, self.io, self.hosts_path, self.registry.hosts[tab.host_index]);
        return .unknown;
    }


    fn pluginConnectionState(tab: *const SessionTab) @FieldType(plugin_ui.ConnectionStatus, "state") {
        if (tab.plugin_renderer) |renderer| if (renderer.vtable.connection_status) |project| return project(renderer.context).state;
        return if (tab.content_ready) .online else .connecting;
    }
    fn tabStatus(self: *Workspace, id: identity.TabId) []const u8 {
        if (self.groupIdByTab(id)) |group| {
            return if (self.groupClosing(group)) "关闭中" else "会话组";
        }
        const index = self.tabIndexById(id) orelse return "已关闭";
        const tab = self.tabs.items[index];
        if (tab.isCard()) return "只读";
        if (tab.closing) return "关闭中";
        // 插件自己的状态说明（如“视频已连接 · 管理不可用”）比通用文案更具体。
        if (tab.plugin_renderer) |renderer| if (renderer.vtable.connection_status) |project| return project(renderer.context).label;
        return presenter.present(self.tabConnectionPhase(id) orelse .unknown).label;
    }

    /// 页签的连接状态：文案（tabStatus）与圆点色（tabConnectionColor）都由它经
    /// shared/base/connection_presenter.zig 得出，不再各写一份。
    fn tabConnectionPhase(self: *Workspace, id: identity.TabId) ?presenter.Phase {
        const index = self.tabIndexById(id) orelse return null;
        const tab = self.tabs.items[index];
        if (tab.isCard() or tab.closing) return .ended;
        if (tab.failed) return .failed;
        if (tab.local) return switch (tab.local_state) {
            .running => .connected,
            .starting => .connecting,
            .closing => .disconnecting,
            .failed, .cleanup_unknown => .failed,
            else => .ended,
        };
        if (tab.plugin_renderer != null) return switch (pluginConnectionState(tab)) {
            .online => .connected,
            .connecting => .connecting,
            .degraded => .degraded,
            .ended => .ended,
        };
        // The notice only speaks for what it shows (reconnecting, lost, ended). Its resting state is also the
        // default of a session whose first connection is still being made, so it must not read as "connected":
        // fall through to the tab's own runtime facts (as tabIconState does).
        if (tab.remote_notice) |notice| if (notice.snapshot) |snapshot| if (snapshot.reportedPhase()) |phase| return phase;
        // Only an ended tombstone is an ended session; a retry that is being made (`.reconnecting`, also set for
        // the manual retry of a first connection that never came up) is `connecting` below, as in tabIconState.
        if (tab.terminal) |surface| if (surface.tombstone.state == .ended) return .ended;
        return switch (self.tabIconState(id)) {
            .failed => .failed,
            .connecting => .connecting,
            .normal => if (tab.file_ready or tab.runtime != null) .connected else .not_connected,
        };
    }

    /// 稿 3: ordinals only while ⌘ is held for more than 300 ms (they save
    /// width otherwise); releasing ⌘ restores the close buttons at once.
    pub const command_ordinal_delay_ms: f64 = 300;
    pub fn setCommandHeld(self: *Workspace, held: bool) void {
        if (self.command_held == held) return;
        self.command_held = held;
        self.command_held_since_ms = if (held) self.cx.frame_time_ms else null;
        if (held) self.cx.scheduleRedrawAfterNs(@as(u64, @intFromFloat(command_ordinal_delay_ms)) * std.time.ns_per_ms + 16 * std.time.ns_per_ms);
        self.refreshCommandOrdinals();
    }
    fn refreshCommandOrdinals(self: *Workspace) void {
        const shown = if (self.command_held_since_ms) |since| self.command_held and self.cx.frame_time_ms - since >= command_ordinal_delay_ms else false;
        if (shown == self.command_ordinals_shown) return;
        self.command_ordinals_shown = shown;
        self.refreshCommandIcons();
    }
    fn refreshCommandIcons(self: *Workspace) void {
        if (self.strip_vm) |vm| vm.setOrdinals(self.command_ordinals_shown);
        self.cx.requestRedraw();
    }
    /// Session-group member count (稿 3 “(n)”).
    fn groupMemberCount(self: *Workspace, id: identity.TabId) usize {
        const group_id = self.groupIdByTab(id) orelse return 0;
        const roster = self.group_roster orelse return 0;
        const group = roster.findById(group_id) orelse return 0;
        return group.members.items.len;
    }
    /// 稿 3 colour: only the type icon is tinted — user colour, else the
    /// host's environment (sidebar group) colour; Local is not tinted by
    /// default. Connecting / failed keep the status tint.
    fn tabTypeTint(self: *Workspace, id: identity.TabId, asset: ui.SvgAsset) ui.Color {
        const state = self.tabIconState(id);
        if (state == .normal) if (self.tabIdentityColor(id)) |color| return color;
        return session_icon.tabTint(state, asset);
    }
    fn tabIdentityColor(self: *Workspace, id: identity.TabId) ?ui.Color {
        if (self.groupIdByTab(id)) |group| return self.groupTabColor(group);
        const index = self.tabIndexById(id) orelse return null;
        const tab = self.tabs.items[index];
        if (tab.tab_color) |color| return ui.Color.hex(@intCast(color));
        if (tab.local) return null;
        return self.environmentColor(tab);
    }
    /// The colour of the sidebar group (environment) the tab's saved host belongs to.
    fn environmentColor(self: *Workspace, tab: *const SessionTab) ?ui.Color {
        const host = if (tab.host_snapshot) |saved| saved.value else if (tab.host_index < self.registry.hosts.len) self.registry.hosts[tab.host_index] else return null;
        const group_id = host.asset_group_id orelse return null;
        for (self.registry.groups) |group| if (group.group_id == group_id) return sidebarGroupColor(group.color);
        return null;
    }
    /// “完整名称 · 路径或地址 · shell · 快捷键” (稿 3 hover).
    fn tabTooltipText(self: *Workspace, ordinal: usize, index: usize) ![]u8 {
        const model_tab = &self.model.tabs.items[index];
        const shortcut = if (tab_naming.commandOrdinal(ordinal, self.model.visibleCount())) |digit| self.ordinalHint(digit) else "";
        const state_text = self.tabStatus(model_tab.id);
        const status_part: []const u8 = if (std.mem.eql(u8, state_text, presenter.present(.connected).label) or std.mem.eql(u8, state_text, "会话组")) "" else state_text;
        if (model_tab.owner == .group) {
            var count_buffer: [24]u8 = undefined;
            const members = std.fmt.bufPrint(&count_buffer, "{d} 个会话", .{self.groupMemberCount(model_tab.id)}) catch "";
            return tab_naming.tooltip(self.allocator, &.{ model_tab.name(), members, status_part, shortcut });
        }
        const tab = if (self.tabIndexById(model_tab.id)) |at| self.tabs.items[at] else return tab_naming.tooltip(self.allocator, &.{ model_tab.name(), model_tab.details, status_part, shortcut });
        if (tab.local) {
            const cwd = if (self.session_bridge.local_cwd) |copy| copy(self.session_bridge.context, tab.id, self.allocator) else null;
            defer if (cwd) |value| self.allocator.free(value);
            var path_buffer: [512]u8 = undefined;
            const path = if (cwd) |value| tab_naming.shortPath(&path_buffer, value, homeDirectory()) else "";
            // The Local PTY always runs /bin/zsh (local/darwin_process.c).
            return tab_naming.tooltip(self.allocator, &.{ model_tab.name(), path, "zsh", status_part, shortcut });
        }
        return tab_naming.tooltip(self.allocator, &.{ model_tab.name(), model_tab.details, status_part, shortcut });
    }
    const shortcut_router = @import("../../shell/mod.zig").shortcut_router;
    /// 本窗口的快捷键路由（键位读 `[keys]`）：页签序号、Tooltip、菜单里的快捷键文字都从这里取。
    pub fn shortcuts(self: *const Workspace) shortcut_router.Router {
        return .{ .keys = &self.app_config.keys };
    }
    /// 第 `digit`（1…9）个页签的直达快捷键文字（“⌘1”；随 `[keys]` 变化）。
    fn ordinalHint(self: *const Workspace, digit: u8) []const u8 {
        const first = @intFromEnum(shortcut_router.Command.tab_1);
        return self.shortcuts().hint(@enumFromInt(first + @as(usize, digit) - 1));
    }
    /// 页签条收到的快捷键（由快捷键路由判定；让位规则也在路由里）。
    pub const TabShortcut = enum { none, rename, recent };
    /// 路由的让位规则需要的事实（当前页签 / 终端的状态）。
    pub const ShortcutFacts = struct {
        /// 当前终端正在输入法组字。
        preedit: bool = false,
        /// 当前终端的本地行编辑器打开。
        local_editor: bool = false,
        /// 当前内容自己处理 F2 这类键：终端全屏程序、插件会话、组字中的终端（会话组页签不算）。
        content: bool = false,
    };
    pub fn shortcutFacts(self: *const Workspace) ShortcutFacts {
        var facts: ShortcutFacts = .{};
        const index = self.active_tab orelse return facts;
        if (index >= self.tabs.items.len) return facts;
        const tab = self.tabs.items[index];
        if (tab.terminal) |*terminal| {
            facts.preedit = terminal.preedit != null;
            facts.local_editor = terminal.local_editor.active;
        }
        const grouped = if (self.model.active) |id| self.groupIdByTab(id) != null else false;
        if (!grouped and !tab.closing) facts.content = facts.preedit or renameKeyBelongsToContent(tab);
        return facts;
    }
    pub fn handleTabKey(self: *Workspace, key: ui.events.KeyCode, modifiers: ui.events.Modifiers, shortcut: TabShortcut) ui.events.EventResult {
        if (self.rename_editor) |editor| if (editor.isVisible()) return editor.handleKey(key);
        if (self.rename_request != null) return .ignored;
        if (self.model.dragging) {
            if (key == .escape) {
                if (self.drag_binding) |binding| binding.cancel(.escape);
                return .stop;
            }
            return .ignored;
        }
        switch (shortcut) {
            .none => return .ignored,
            .rename => {
                if (self.confirming_id != null or self.host_key_job != null or self.auth_job != null) return .ignored;
                if (self.model.active) |id| if (self.groupIdByTab(id)) |group| {
                    if (self.groupClosing(group)) return .ignored;
                    self.beginRenamePresentation(id) catch |err| self.statusFailure(@errorName(err));
                    return .stop;
                };
                if (self.active_tab) |index| if (index < self.tabs.items.len and !self.tabs.items[index].closing) {
                    self.beginRenameTab(self.tabs.items[index].id) catch |err| self.statusFailure(@errorName(err));
                    return .stop;
                };
                return .ignored;
            },
            .recent => {
                if (self.confirming_id != null or self.host_key_job != null or self.auth_job != null) return .ignored;
                var excluded: std.ArrayList(identity.TabId) = .empty;
                defer excluded.deinit(self.allocator);
                for (self.tabs.items) |tab| if (tab.closing) {
                    excluded.append(self.allocator, tab.tab_id) catch return .stop;
                };
                for (self.group_views.items) |view| if (self.groupClosing(view.id)) {
                    if (self.groupTabId(view.id)) |id| excluded.append(self.allocator, id) catch return .stop;
                };
                const id = self.model.cycleRecent(modifiers.shift, excluded.items) catch return .stop;
                if (id) |target| self.presentTabId(target, .take);
                return .stop;
            },
        }
    }
    /// F2 (稿 3 rename) is also a key programs use: a full-screen terminal program (mc, htop, vim
    /// mappings — alternate screen) and plugin content that forwards keys (KVM: F2 enters a BIOS
    /// setup) keep it; at a shell prompt and on other tabs F2 renames.
    fn renameKeyBelongsToContent(tab: *const SessionTab) bool {
        if (tab.plugin_renderer != null) return true;
        const terminal = tab.terminal orelse return false;
        const surface = terminal.terminal_surface orelse return false;
        const snapshot = surface.snapshot orelse return false;
        return snapshot.projection.modes.alternate_screen;
    }
    /// Called on Control release and window blur, never on each Tab preview.
    pub fn finishRecentTabSwitch(self: *Workspace) void {
        self.model.finishRecentSwitch();
    }
    /// Context menus own the pointer until dismissed; a stationary pointer
    /// must leave and re-enter its tab before showing another hover hint.
    pub fn setTabMenuOpen(self: *Workspace, open: bool) void {
        self.tab_menu_open = open;
        if (open) if (self.strip_vm) |vm| vm.suppressTips();
    }
    fn clearTabDropFeedback(self: *Workspace) void {
        if (self.strip_vm) |vm| vm.setDropTarget(null);
        if (self.group_drop_hint) |hint| hint.setDisplay(.none);
    }
    fn containsDrop(rect: ui.ComputedRect, point: ui.interaction.drag.Point) bool {
        return rect.w > 0 and rect.h > 0 and point.x >= rect.x and point.x <= rect.x + rect.w and point.y >= rect.y and point.y <= rect.y + rect.h;
    }
    pub fn canGroupTarget(self: *Workspace, target: identity.TabId) bool {
        if (self.group_roster == null) return false;
        if (self.groupIdByTab(target)) |id| return !self.groupClosing(id) and self.group_roster != null and self.group_roster.?.findById(id) != null;
        const index = self.tabIndexById(target) orelse return false;
        const tab = self.tabs.items[index];
        std.debug.assert(card_placement.consistent(tab.card_type, tab.content_owner == .session));
        return card_placement.canJoinSplit(tab.card_type, tab.closing, tab.owned_pending);
    }
    /// 已发布的卡片类型（带 AI 声明）；注册表尚未发布卡片类型时（只装了 workspace 的单测）用
    /// feature 声明的同一份放置约束。
    fn resolveCardType(self: *const Workspace, declared: *const card_placement.CardTypeDef) *const card_placement.CardTypeDef {
        return self.plugins.cardType(declared.id) orelse declared;
    }
    /// 插件会话呈现的卡片类型：清单声明的类型，未声明时是通用会话卡片。
    fn pluginCardType(self: *const Workspace, protocol_id: []const u8) *const card_placement.CardTypeDef {
        if (self.plugins.find(protocol_id)) |manifest| if (self.plugins.cardTypeFor(manifest)) |card| return card;
        return self.resolveCardType(&card_placement.session_def);
    }
    /// M4：离开分屏 / 组、回到独立 tab 之前校验卡片类型允许独立成 tab。
    pub fn canLeaveSplit(self: *Workspace, session_id: SessionId) bool {
        const index = self.tabIndex(session_id) orelse return false;
        return card_placement.canStandalone(self.tabs.items[index].card_type);
    }
    pub fn currentGroupTarget(self: *Workspace) ?identity.TabId {
        const target = if (self.active_group_view) |id| self.groupTabId(id) orelse return null else if (self.active_tab) |index| (if (index < self.tabs.items.len) self.tabs.items[index].tab_id else return null) else return null;
        return if (self.canGroupTarget(target)) target else null;
    }
    fn groupingTargetAt(self: *Workspace, point: ui.interaction.drag.Point, source: ?identity.TabId) ?identity.TabId {
        for (self.tab_nodes.items) |node| {
            if (source == node.tab_id or !self.canGroupTarget(node.tab_id)) continue;
            const r = node.node.globalRect();
            if (containsDrop(.{ .x = r.x + r.w * 0.25, .y = r.y, .w = r.w * 0.5, .h = r.h }, point)) return node.tab_id;
        }
        if (!containsDrop(self.terminal_area.globalRect(), point)) return null;
        const target = self.currentGroupTarget() orelse return null;
        return if (source == target) null else target;
    }
    fn showGroupDropFeedback(self: *Workspace, target: identity.TabId, point: ui.interaction.drag.Point) void {
        if (containsDrop(self.terminal_area.globalRect(), point)) {
            if (self.group_drop_hint == null) {
                const hint = ui.box(self.cx, .{ .position = .absolute, .inset = .{ .left = .{ .px = 2 }, .top = .{ .px = 2 } }, .width = .fill(), .height = .fill(), .outline = .{ .color = app_theme.current().accent, .width = 2, .offset = -2 }, .z_index = 100 }, .{}) catch return;
                hint.meta.ownership.meta.test_id = "groups.external_drop_hint";
                self.terminal_area.appendChild(self.allocator, hint) catch return;
                self.group_drop_hint = hint;
            }
            self.group_drop_hint.?.setDisplay(.flex);
        } else if (self.strip_vm) |vm| vm.setDropTarget(@backingInt(target));
    }
    fn stripDrag(raw: *anyopaque, cell: *tab_strip.Cell, event: ui.interaction.drag.Event) void {
        const self: *Workspace = @ptrCast(@alignCast(raw));
        const id: identity.TabId = @fromBackingInt(cell.id);
        if (self.model.indexOf(id) == null) return;
        const vm = self.strip_vm orelse return;
        self.clearTabDropFeedback();
        switch (event.phase) {
            .start => {
                self.model.beginDrag() catch return;
                self.drag_tab = id;
                self.tab_reorder_target = null;
                self.drag_binding = cell.drag;
                vm.clearPressed(cell.id);
                // Pencil YLyJw: the dragged tab lifts as a card (close hidden) until the strip rebuilds.
                vm.setLifted(cell.id);
            },
            .move => {},
            .end, .cancel => {
                if (event.phase == .end) {
                    if (self.tabIndexById(id) != null and self.canGroupTarget(id)) if (self.groupingTargetAt(event.position_window, id)) |target|
                        if (self.pending_tab_drop == null) {
                            self.pending_tab_drop = .{ .source = id, .target = target };
                        };
                    // 卡片类型不允许分屏（会话记录卡片，Q11）：落在分屏落点上时拒绝并提示，不静默忽略。
                    if (self.tabIndexById(id)) |at| if (!self.canGroupTarget(id) and !self.tabs.items[at].card_type.placements.split and self.groupingTargetAt(event.position_window, id) != null) self.rejectSplitPlacement(self.tabs.items[at].card_type);
                }
                if (event.phase == .end and self.pending_tab_drop == null and containsDrop(self.tab_bar.globalRect(), event.position_window)) {
                    if (self.tab_reorder_target) |target| if (self.model.indexOf(target)) |at| self.model.moveTab(id, at) catch {};
                }
                self.tab_drop_target = null;
                self.tab_reorder_target = null;
                self.model.endDrag(event.phase == .cancel) catch {};
                self.drag_tab = null;
                self.drag_binding = null;
                vm.setGap(null);
                vm.setLifted(null);
                self.syncModelOrder() catch {};
                self.tab_rebuild_pending = true;
                self.cx.requestRedraw();
                return;
            },
        }
        self.tab_drop_target = null;
        if (self.tabIndexById(id) != null and self.canGroupTarget(id)) {
            if (self.groupingTargetAt(event.position_window, id)) |target| {
                self.tab_drop_target = target;
                self.showGroupDropFeedback(target, event.position_window);
                vm.setGap(null);
                self.cx.requestRedraw();
                return;
            }
        }
        self.drag_pointer_x = event.position_window.x;
        self.moveDraggedTab();
    }
    /// 把不允许分屏的卡片拖到分屏落点：拒绝并在状态栏说明（PLUGIN_ARCH_PLAN PL4b 退出标准）。
    pub fn rejectSplitPlacement(self: *Workspace, card_type: *const card_placement.CardTypeDef) void {
        var buffer: [160]u8 = undefined;
        self.status(std.fmt.bufPrint(&buffer, "{s}卡片不能放进分屏，可作为独立标签页或浮动打开", .{card_type.title}) catch "该卡片不能放进分屏");
    }
    fn dropTabIntoGroup(self: *Workspace, source_id: identity.TabId, target_id: identity.TabId) !void {
        if (source_id == target_id) return;
        const source = self.tabs.items[self.tabIndexById(source_id) orelse return error.StaleSession];
        if (source.isCard() or source.closing or source.owned_pending or source.content_owner != .session) return error.StaleSession;
        const roster = self.group_roster orelse return error.UnknownGroup;
        const group_id: u32 = if (self.groupIdByTab(target_id)) |id| existing: {
            if (self.groupClosing(id)) return error.GroupClosing;
            const group = roster.findById(id) orelse return error.UnknownGroup;
            if (group.contains(source.id)) return;
            const revision = try identity.advance(group.membership_revision);
            try group.members.ensureUnusedCapacity(self.allocator, 1);
            const plan = try self.prepareTabGrouping(.{ .source = @backingInt(source.tab_id), .group = id, .container = @backingInt(self.groupTabId(id) orelse return error.UnknownGroup) });
            group.admitAssumeCapacity(source.id, revision);
            self.commitTabGrouping(plan);
            break :existing id;
        } else fresh: {
            const target = self.tabs.items[self.tabIndexById(target_id) orelse return error.StaleSession];
            if (target.isCard() or target.closing or target.owned_pending or target.content_owner != .session) return error.StaleSession;
            // 稿 3: the group name defaults to its first member's shown name.
            // Copied: preparing the group view may grow the model's tab list.
            var name_buffer: [96]u8 = undefined;
            const shown = if (self.model.indexOf(target.tab_id)) |at| self.model.tabs.items[at].name() else target.titleSlice();
            const name = name_buffer[0..@min(shown.len, name_buffer.len)];
            @memcpy(name, shown[0..name.len]);
            var prepared = try roster.prepareNew(name, 0xff818cf8, target.id);
            defer prepared.deinit();
            const entry = &prepared.entry.?;
            try entry.members.append(self.allocator, .{ .pane_id = source.id, .membership_revision = 3 });
            entry.membership_revision = 3;
            var view = try self.prepareGroupView(prepared.id, name, target.id);
            defer view.deinit();
            try view.validate();
            const plan = try self.prepareTabGrouping(.{ .source = @backingInt(source.tab_id), .target = @backingInt(target.tab_id), .group = prepared.id, .container = @backingInt(view.tab.id) });
            const id = prepared.commit() catch unreachable;
            self.commitTabGrouping(plan);
            view.commit(roster) catch unreachable;
            break :fresh id;
        };
        const group = roster.findById(group_id).?;
        try self.openGroup(roster, group.id);
        const parent = self.groupTabId(group.id).?;
        for (group.members.items) |member| if (self.sessionTab(member.pane_id)) |tab| try self.model.setContainer(tab.tab_id, parent);
        self.refreshGroup(group.id);
        self.tab_rebuild_pending = true;
    }
    fn prepareTabGrouping(self: *Workspace, drop: ai_tab_grouping.Drop) !?ai_tab_grouping.Plan {
        const prepare = self.ai_grouping_bridge.prepare orelse return null;
        return try prepare(self.ai_grouping_bridge.context orelse return error.ContextUnavailable, drop);
    }
    /// Keep the original identities and group revision throughout child cleanup.
    /// Repeated frames never allocate/publish a fresh group while waiting.
    fn settleTabDrop(self: *Workspace) !bool {
        const drop = &self.pending_tab_drop.?;
        const source = self.tabs.items[self.tabIndexById(drop.source) orelse return error.StaleSession];
        if (source.isCard() or source.closing or source.owned_pending or source.content_owner != .session) return error.StaleSession;
        const group_id = self.groupIdByTab(drop.target);
        var target: ?identity.SessionHandle = null;
        var revision: u64 = 0;
        if (group_id) |id| {
            if (self.groupClosing(id)) return error.GroupClosing;
            revision = (self.group_roster.?.findById(id) orelse return error.UnknownGroup).membership_revision;
        } else {
            const tab = self.tabs.items[self.tabIndexById(drop.target) orelse return error.StaleSession];
            if (tab.isCard() or tab.closing or tab.owned_pending or tab.content_owner != .session) return error.StaleSession;
            target = tab.content_owner.session;
        }
        if (!drop.captured) {
            drop.source_handle = source.content_owner.session;
            drop.target_handle = target;
            drop.group = group_id;
            drop.membership_revision = revision;
            if (self.ai_grouping_bridge.capture) |capture| drop.settlement = try capture(self.ai_grouping_bridge.context.?, @backingInt(source.tab_id), if (group_id == null) @backingInt(drop.target) else null);
            drop.captured = true;
        } else if (!drop.source_handle.?.eql(source.content_owner.session) or !std.meta.eql(drop.target_handle, target) or drop.group != group_id or drop.membership_revision != revision) return error.SourceChanged;
        if (drop.settlement) |intent| if (self.ai_grouping_bridge.settle) |settle| return settle(self.ai_grouping_bridge.context.?, intent);
        return true;
    }
    fn releaseTabDrop(self: *Workspace) void {
        if (self.pending_tab_drop) |drop| if (drop.settlement) |intent| if (self.ai_grouping_bridge.release) |release| release(self.ai_grouping_bridge.context.?, intent);
        self.pending_tab_drop = null;
    }
    fn commitTabGrouping(self: *Workspace, plan: ?ai_tab_grouping.Plan) void {
        if (plan) |value| if (self.ai_grouping_bridge.commit) |commit| commit(self.ai_grouping_bridge.context.?, value);
    }

    fn moveDraggedTab(self: *Workspace) void {
        const id = self.drag_tab orelse return;
        const vm = self.strip_vm orelse return;
        const viewport = vm.viewport orelse return;
        const rect = viewport.globalRect();
        const content_x = self.drag_pointer_x - rect.x;
        // Keep target geometry stable while the pointer crosses tab edges.
        // Only the tabs in the strip count; tabs in “⌄ n” keep their places.
        var left: f32 = 0;
        var slot: usize = self.strip_widths.items.len;
        var gap_x: f32 = 0;
        var seen_any = false;
        for (self.strip_widths.items, 0..) |width, index| {
            if (index >= self.strip_shown.len or !self.strip_shown[index]) continue;
            if (!seen_any or content_x >= left + width / 2) {
                if (content_x < left + width / 2) {
                    slot = index;
                    gap_x = left;
                    break;
                }
            } else {
                slot = index;
                gap_x = left;
                break;
            }
            seen_any = true;
            left += width + tab_styles.gap;
            slot = index + 1;
            gap_x = left;
        }
        const source = self.model.visibleIndexOf(id) orelse return;
        const destination = @min(self.model.visibleCount() - 1, slot - @as(usize, if (source < slot) 1 else 0));
        const target_at = self.model.visibleAt(destination) orelse return;
        self.tab_reorder_target = self.model.tabs.items[target_at].id;
        vm.setGap(gap_x - 2);
    }
    fn syncModelOrder(self: *Workspace) !void {
        // Presentation order belongs only to model.tabs; the strip re-renders its rows in that
        // order (keyed by tab id, rows move without being rebuilt).
        var next: usize = 0;
        for (self.model.tabs.items) |tab| {
            if (next >= self.tab_nodes.items.len) break;
            for (self.tab_nodes.items[next..], next..) |node, at| if (node.tab_id == tab.id) {
                std.mem.swap(TabNode, &self.tab_nodes.items[next], &self.tab_nodes.items[at]);
                self.tab_nodes.items[next].tab_index = next;
                next += 1;
                break;
            };
        }
        self.tab_rebuild_pending = true;
        self.refreshCommandIcons();
    }

    pub fn beginRenameTab(self: *Workspace, id: SessionId) !void {
        const index = self.tabIndex(id) orelse return error.InvalidTab;
        try self.beginRenamePresentation(self.tabs.items[index].tab_id);
    }

    fn beginRenamePresentation(self: *Workspace, id: identity.TabId) !void {
        self.rename_request = try self.model.beginRename(id);
        self.rename_draft.clearRetainingCapacity();
        try self.rename_draft.appendSlice(self.allocator, self.model.tabs.items[self.model.indexOf(id).?].name());
        self.rename_session = if (self.tabIndexById(id)) |index| self.tabs.items[index].id else null;
        self.rename_pending = true;
        try self.startPollLoop();
        self.cx.requestRedraw();
    }

    pub fn cancelRenameTab(self: *Workspace) bool {
        if (self.rename_session == null and self.rename_request == null) return false;
        self.rename_session = null;
        self.rename_request = null;
        self.rename_pending = true;
        self.cx.requestRedraw();
        return true;
    }
    fn flushRename(self: *Workspace) !void {
        if (!self.rename_pending) return;
        self.rename_pending = false;
        if (self.rename_scope) |old| old.dispose();
        self.rename_scope = null;
        self.rename_editor = null;
        const request = self.rename_request orelse return;
        const index = self.model.indexOf(request.tab) orelse {
            self.rename_request = null;
            self.rename_session = null;
            return;
        };
        if (!self.model.tabs.items[index].owner.eql(request.owner)) return;
        const scope = try self.scope.childScope();
        self.rename_scope = scope;
        self.rename_editor = try tab_rename.Editor.mount(self.cx, scope, @backingInt(request.tab), self.rename_draft.items, .{ .context = self, .commit = commitRename, .cancel = cancelRename, .change = changeRename, .anchor = renameAnchor });
        self.cx.setFocus(self.rename_editor.?.node);
    }
    fn renameAnchor(raw: *anyopaque, id: u64) ?ui.ComputedRect {
        const self: *Workspace = @ptrCast(@alignCast(raw));
        for (self.tab_nodes.items) |tab| if (@backingInt(tab.tab_id) == id) return tab.node.globalRect();
        return null;
    }
    fn commitRename(raw: *anyopaque, id: u64, name: []const u8) bool {
        const self: *Workspace = @ptrCast(@alignCast(raw));
        const request = self.rename_request orelse return false;
        if (@backingInt(request.tab) != id) return false;
        self.model.renameCustom(request, name) catch return false;
        if (self.tabIndexById(request.tab)) |index| self.tabs.items[index].setTitle(self.model.tabs.items[self.model.indexOf(request.tab).?].name());
        self.refreshTabNames(true);
        self.reveal_active = true;
        self.rebuildTabBar() catch {};
        _ = self.cancelRenameTab();
        return true;
    }
    fn changeRename(raw: *anyopaque, id: u64, name: []const u8) void {
        const self: *Workspace = @ptrCast(@alignCast(raw));
        const request = self.rename_request orelse return;
        if (@backingInt(request.tab) != id) return;
        self.rename_draft.clearRetainingCapacity();
        self.rename_draft.appendSlice(self.allocator, name) catch {};
    }
    fn cancelRename(raw: *anyopaque, id: u64) void {
        const self: *Workspace = @ptrCast(@alignCast(raw));
        const request = self.rename_request orelse return;
        if (@backingInt(request.tab) == id) _ = self.cancelRenameTab();
    }

    fn groupConnectionState(tab: *const SessionTab) @FieldType(plugin_ui.ConnectionStatus, "state") {
        if (tab.closing) return .ended;
        if (tab.failed) return .degraded;
        if (tab.local) return switch (tab.local_state) {
            .running => .online,
            .starting => .connecting,
            .failed, .cleanup_unknown => .degraded,
            else => .ended,
        };
        if (tab.plugin_renderer != null) return pluginConnectionState(tab);
        if (tab.terminal == null) return if (tab.file_ready) .online else .connecting;
        if (tab.terminal.?.tombstone.state != .active) return .ended;
        return if (tab.runtime) |runtime| (if (runtime.isConnected()) .online else .ended) else .connecting;
    }

    /// A floating session card's header facts (cards-float): the type icon of its pane header and a
    /// subtitle naming the kind ("本地终端" / the protocol's display name).
    pub fn floatCardIcon(self: *Workspace, tab: *SessionTab) ui.SvgAsset {
        return if (tab.terminal != null) (if (tab.local) ui.icons.square_terminal else ui.icons.server) else self.tabIcon(tab);
    }
    pub fn floatCardKind(self: *Workspace, tab: *const SessionTab) []const u8 {
        return self.groupMemberKind(tab);
    }

    fn groupMemberKind(self: *Workspace, tab: *const SessionTab) []const u8 {
        if (tab.local) return tab_naming.home_label;
        const protocol = if (tab.plugin_protocol_id.len != 0) tab.plugin_protocol_id else if (tab.host_snapshot) |snapshot| snapshot.value.protocolId() else if (tab.terminal != null) "ssh" else "sftp";
        if (self.plugins.find(protocol)) |manifest| return manifest.display_name;
        return protocol;
    }

    const GroupJoinTarget = struct {
        workspace: *Workspace,
        tab_id: identity.TabId,
        owner: identity.ContentOwner,
        fn current(self: *@This()) !*SessionTab {
            const index = self.workspace.tabIndexById(self.tab_id) orelse return error.StaleSession;
            const tab = self.workspace.tabs.items[index];
            if (!tab.content_owner.eql(self.owner) or tab.content_owner != .session or !card_placement.canJoinSplit(tab.card_type, tab.closing, tab.owned_pending)) return error.StaleSession;
            return tab;
        }
        fn join(raw: *anyopaque, name: []const u8) !void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            const tab = try self.current();
            const workspace = self.workspace;
            const roster = workspace.group_roster orelse return error.UnknownGroup;
            const existing = roster.find(name);
            if (existing) |group| if (workspace.groupClosing(group.id)) return error.GroupClosing;
            const already_member = if (existing) |group| group.contains(tab.id) else false;
            const group = try roster.join(name, tab.id, if (existing) |previous| previous.color else 0xff818cf8);
            const id = group.id;
            errdefer if (!already_member) roster.leave(name, tab.id) catch {};
            try workspace.openGroup(roster, id);
            workspace.refreshGroup(id);
        }
        fn leave(raw: *anyopaque) !void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            const tab = try self.current();
            const workspace = self.workspace;
            const roster = workspace.group_roster orelse return error.UnknownGroup;
            for (roster.groups.items) |group| if (group.contains(tab.id) and workspace.groupClosing(group.id)) return error.GroupClosing;
            if (!card_placement.canStandalone(tab.card_type)) return error.PlacementNotAllowed;
            _ = roster.leavePane(tab.id);
            for (roster.groups.items) |group| workspace.refreshGroup(group.id);
            workspace.activateTabId(tab.tab_id);
        }
    };
    pub fn showGroupPicker(self: *Workspace, index: usize) !void {
        if (index >= self.tabs.items.len) return error.StaleSession;
        const tab = self.tabs.items[index];
        if (tab.content_owner != .session or !card_placement.canJoinSplit(tab.card_type, tab.closing, tab.owned_pending)) return error.StaleSession;
        const roster = self.group_roster orelse return error.UnknownGroup;
        if (self.group_join) |view| {
            self.group_join = null;
            const old_scope = view.scope;
            const old_overlay = view.overlay;
            view.open.set(false);
            if (old_overlay.parent) |parent| self.cx.detachChild(parent, old_overlay);
            self.cx.destroyDetached(old_overlay);
            old_scope.dispose();
        }
        const scope = try self.scope.childScope();
        const target = try scope.createState(GroupJoinTarget, .{ .workspace = self, .tab_id = tab.tab_id, .owner = tab.content_owner });
        self.group_join = try @import("group_join_view.zig").View.mount(self.cx, scope, self.terminal_area, roster, .{ .context = target, .join = GroupJoinTarget.join, .leave = GroupJoinTarget.leave });
    }

    fn loadGroupLayout(self: *Workspace, view: *group_view.View) void {
        if (view.layout_loaded) return;
        view.layout_loaded = true;
        if (self.hosts_path.len == 0) return;
        const group = (self.group_roster orelse return).findById(view.id) orelse return;
        const file_path = group_view.sizing.path(self.allocator, self.hosts_path, group.name) catch return;
        defer self.allocator.free(file_path);
        const source = std.Io.Dir.cwd().readFileAlloc(self.io, file_path, self.allocator, .limited(1024 * 1024)) catch return;
        defer self.allocator.free(source);
        const parsed = std.json.parseFromSlice(group_view.sizing.Snapshot, self.allocator, source, .{}) catch return;
        defer parsed.deinit();
        if (!group_view.sizing.valid(parsed.value)) return;
        var snapshot = parsed.value;
        snapshot.nodes = self.allocator.dupe(group_view.sizing.Node, snapshot.nodes) catch return;
        view.saved_layout = snapshot;
        view.layout = snapshot.layout;
    }
    fn saveGroupLayout(self: *Workspace, view: *group_view.View) void {
        if (self.hosts_path.len == 0 or view.tree.root == null) return;
        // cards-float: while a member floats the presented tree lacks it; the saved layout waits until
        // it is back (floating is not restored on the next launch either).
        if (self.groupHasFloating(view.id)) return;
        const group = (self.group_roster orelse return).findById(view.id) orelse return;
        const file_path = group_view.sizing.path(self.allocator, self.hosts_path, group.name) catch return;
        defer self.allocator.free(file_path);
        // float-split: docked floating cards are not saved (they are not restored on the next launch);
        // the saved layout keeps only the session leaves.
        var sessions_only: ?group_view.sizing.Tree = null;
        defer if (sessions_only) |*tree| tree.deinit(self.allocator);
        if (view.cards.items.len != 0 or view.tree.count() != view.panes.items.len) {
            const members = self.allocator.alloc(u64, view.panes.items.len) catch return;
            defer self.allocator.free(members);
            for (view.panes.items, members) |pane, *id_| id_.* = pane.session;
            sessions_only = view.tree.pruned(self.allocator, members) catch return;
        }
        const tree = if (sessions_only) |*tree| tree else &view.tree;
        const tree_root = tree.root orelse return;
        const nodes = self.allocator.dupe(group_view.sizing.Node, tree.nodes.items) catch return;
        defer self.allocator.free(nodes);
        for (nodes) |*node| if (node.* == .leaf) {
            for (view.panes.items, 0..) |pane, slot| if (pane.session == node.leaf) {
                node.leaf = slot + 1;
                break;
            };
        };
        group_view.sizing.save(self.allocator, self.io, file_path, .{ .layout = view.layout, .root = tree_root, .nodes = nodes }) catch |err| self.statusFailure(@errorName(err));
    }
    // ── float-split / cards-float：卡片在 tab body 分屏与浮动之间 ─────────────────────────────
    // A card's content node (and a session's `SessionTab.root`) is a kept surface: it only ever
    // changes host through `surface_migration` (LIFECYCLE.md §2) — `move` while it stays in the
    // window (focus, IME, selection, scroll and identity are kept), `park` when its host goes away.

    /// What a floating card's owner hands the split when docking (`dockCard`).
    pub const DockRequest = struct {
        /// The card's owner tab (strip id); null = the card belongs to the window.
        owner_tab: ?u64,
        /// The card's content node (a kept surface). It stays where it is until the pane exists, then
        /// moves into it in one step (`surface_migration.move`): focus, selection, scroll stay.
        content: *ui.Node,
        title: []const u8,
        icon: ui.SvgAsset,
        ids: group_view.CardIds,
        port: group_view.CardPort,
        /// The floating card's window rectangle: picks the side and is where the pane flies from.
        from: ui.ComputedRect,
        flight: group_view.Flight,
    };
    pub const Docked = struct {
        leaf: u64,
        /// The tab the pane now lives in (a standalone session tab becomes its group tab).
        tab: u64,
        /// The single-card tab that became the group for this dock (its tab-bound AI hands over to
        /// `tab`); null when the owner tab was already a split.
        created_from: ?u64 = null,
    };
    pub const Undocked = struct {
        /// The pane's window rectangle (where the floating card unfolds from).
        rect: ?ui.ComputedRect = null,
        /// The tab the card belongs to now: the group tab, or the restored single-card tab when the
        /// group dissolved; null when the card was not docked.
        tab: ?u64 = null,
        /// The group tab that dissolved back into `tab` (its tab-bound AI hands back to `tab`).
        dissolved_from: ?u64 = null,
    };

    /// Why the owner tab cannot take a docked card now; null = it can (float-split, `card_dock`).
    /// The card type's own `split` is the caller's (it is shown on the button before any state).
    pub fn dockRefusal(self: *Workspace, owner_tab: ?u64) ?card_dock.Refusal {
        const raw = owner_tab orelse return .no_tab;
        const id: identity.TabId = @fromBackingInt(raw);
        if (self.model.indexOf(id) == null) return .no_tab;
        if (self.group_roster == null) return .tab_not_splittable;
        const r = self.terminal_area.globalRect();
        const body: card_dock.Rect = .{ .x = r.x, .y = r.y, .w = r.w, .h = r.h };
        if (self.groupIdByTab(id)) |group| {
            if (self.groupClosing(group)) return .tab_busy;
            if (self.group_roster.?.findById(group) == null) return .tab_not_splittable;
            const view = self.groupView(group) orelse return .tab_not_splittable;
            return if (card_dock.fits(body, self.presentedLeafCount(view))) null else .full;
        }
        const index = self.tabIndexById(id) orelse return .tab_not_splittable;
        const tab = self.tabs.items[index];
        if (tab.closing or tab.owned_pending) return .tab_busy;
        if (tab.content_owner != .session or tab.isCard() or !card_placement.canJoinSplit(tab.card_type, tab.closing, tab.owned_pending)) return .tab_not_splittable;
        return if (card_dock.fits(body, if (tab.floating) 0 else 1)) null else .full;
    }

    /// Panes the split shows now: session members that are not floating, and docked cards.
    fn presentedLeafCount(self: *Workspace, view: *const group_view.View) usize {
        var count = view.cards.items.len;
        const roster = self.group_roster orelse return count;
        const group = roster.findById(view.id) orelse return count;
        for (group.members.items) |member| if (self.sessionTab(member.pane_id)) |tab| {
            if (!tab.floating and tab.content_owner == .session and !tab.isCard() and !tab.owned_pending) count += 1;
        };
        return count;
    }

    /// Dock a floating card into its owner tab's split as a pane: a standalone session tab becomes a
    /// two-card split (the same group tab "向右分屏" creates), an existing split gets one more pane.
    pub fn dockCard(self: *Workspace, request: DockRequest) !Docked {
        if (self.dockRefusal(request.owner_tab) != null) return error.DockRefused;
        const id: identity.TabId = @fromBackingInt(request.owner_tab.?);
        const roster = self.group_roster.?;
        var origin: ?u64 = null;
        const group_id = self.groupIdByTab(id) orelse fresh: {
            const source = self.tabs.items[self.tabIndexById(id).?];
            const name = try std.fmt.allocPrint(self.allocator, "{s} 终端组 #{d}", .{ source.titleSlice(), source.id });
            defer self.allocator.free(name);
            origin = source.id;
            break :fresh (try roster.join(name, source.id, 0xff818cf8)).id;
        };
        try self.openGroup(roster, group_id);
        const group = roster.findById(group_id) orelse return error.UnknownGroup;
        const parent = self.groupTabId(group_id) orelse return error.UnknownGroup;
        for (group.members.items) |member| if (self.sessionTab(member.pane_id)) |tab| try self.model.setContainer(tab.tab_id, parent);
        const view = self.groupView(group_id) orelse return error.UnknownGroup;
        if (origin) |session| view.dock_origin = session;
        const leaf = card_dock.cardLeaf(self.next_card_leaf);
        self.next_card_leaf += 1;
        const r = self.terminal_area.globalRect();
        const edge = card_dock.edgeFor(.{ .x = r.x, .y = r.y, .w = r.w, .h = r.h }, .{ .x = request.from.x, .y = request.from.y, .w = request.from.w, .h = request.from.h });
        try view.cards.append(self.allocator, .{ .leaf = leaf, .content = request.content, .title = request.title, .icon = request.icon, .ids = request.ids, .port = request.port, .edge = edge, .flight = request.flight });
        self.noteEnvironment();
        view.dirty = true;
        self.group_present_pending = true;
        self.tab_rebuild_pending = true;
        self.cx.requestRedraw();
        return .{ .leaf = leaf, .tab = @backingInt(parent), .created_from = if (origin != null) request.owner_tab.? else null };
    }

    /// Take a docked card out of its split (its pane header's "浮动" / "关闭"): the content node moves
    /// to `into` (the owner's floating frame) in one step, or leaves the window when the owner gives
    /// none; the pane's window rectangle is handed back. When the split was made from a
    /// single-card tab for docking and only that session is left, the group dissolves back into the
    /// original single-card tab (float-split leftover, ruled by the main session).
    pub fn undockCard(self: *Workspace, leaf: u64, into: ?surface_migration.Host) Undocked {
        for (self.group_views.items) |view| for (view.cards.items, 0..) |card, index| if (card.leaf == leaf) {
            const rect: ?ui.ComputedRect = if (card.pane) |pane| pane.globalRect() else null;
            const moved = if (into) |host| if (surface_migration.move(self.cx, card.content, host)) |_| true else |_| false else false;
            if (!moved) surface_migration.park(self.cx, card.content);
            _ = view.cards.orderedRemove(index);
            self.noteEnvironment();
            view.dirty = true;
            view.persist_pending = true;
            if (self.active_group_view == view.id) self.group_present_pending = true;
            self.cx.requestRedraw();
            var result: Undocked = .{ .rect = rect, .tab = if (self.groupTabId(view.id)) |tab| @backingInt(tab) else null };
            if (self.dissolveDockGroup(view)) |restored| {
                result.dissolved_from = result.tab;
                result.tab = restored;
            }
            return result;
        };
        return .{};
    }

    /// A split made only to dock cards into a single-card tab goes back to that tab once its last
    /// card left (no session closes; the group tab disappears from the strip). Returns the restored
    /// tab, or null when the group stays (it has other members or cards, or a member floats).
    fn dissolveDockGroup(self: *Workspace, view: *group_view.View) ?u64 {
        const origin = view.dock_origin orelse return null;
        if (view.cards.items.len != 0 or view.close != null or view.redock.items.len != 0) return null;
        const roster = self.group_roster orelse return null;
        const group = roster.findById(view.id) orelse return null;
        if (group.members.items.len != 1 or group.members.items[0].pane_id != origin) return null;
        const tab = self.sessionTab(origin) orelse return null;
        if (tab.closing or tab.owned_pending) return null;
        const group_tab = self.groupTabId(view.id) orelse return null;
        const was_active = self.active_group_view == view.id;
        roster.leave(group.name, origin) catch return null;
        self.restoreGroupRoots();
        if (view.root) |root| {
            if (root.parent) |parent| self.cx.detachChild(parent, root);
            self.cx.destroyDetached(root);
        }
        view.root = null;
        if (view.scope) |scope| scope.dispose();
        view.scope = null;
        for (self.group_views.items, 0..) |candidate, at| if (candidate == view) {
            _ = self.group_views.orderedRemove(at);
            self.noteEnvironment();
            break;
        };
        view.deinit(self.allocator);
        self.allocator.destroy(view);
        self.model.setContainer(tab.tab_id, null) catch {};
        if (self.model.indexOf(group_tab)) |at| self.model.completeClose(group_tab, self.model.tabs.items[at].owner) catch {};
        if (was_active) {
            self.setActiveGroupView(null);
            if (self.tabIndexById(tab.tab_id)) |index| self.selectTabFocus(index, .keep);
        } else tab.root.setDisplay(.none);
        self.tab_rebuild_pending = true;
        self.rebuildTabBar() catch {};
        self.cx.requestRedraw();
        return @backingInt(tab.tab_id);
    }

    /// The tab a docked card's pane lives in, null when it is not docked.
    pub fn dockedCardTab(self: *const Workspace, leaf: u64) ?u64 {
        for (self.group_views.items) |view| for (view.cards.items) |card| if (card.leaf == leaf) {
            return if (self.groupTabId(view.id)) |tab| @backingInt(tab) else null;
        };
        return null;
    }

    /// The docked card's pane root (probes / tests), null when not docked or not presented yet.
    pub fn dockedCardPane(self: *const Workspace, leaf: u64) ?*ui.Node {
        for (self.group_views.items) |view| for (view.cards.items) |card| if (card.leaf == leaf) return card.pane;
        return null;
    }

    /// The docked card's pane header "更多" button, null when not docked or not presented.
    pub fn dockedCardMore(self: *const Workspace, leaf: u64) ?*ui.Node {
        for (self.group_views.items) |view| for (view.cards.items) |card| if (card.leaf == leaf) return card.more;
        return null;
    }

    /// Where a docked card's content belongs while its pane is presented (the pane's body), null when
    /// the pane is not built yet. An owner whose one content node serves several tabs (the AI) moves
    /// it there itself when that tab becomes current (`surface_migration.move`).
    pub fn dockedCardHost(self: *const Workspace, leaf: u64) ?surface_migration.Host {
        for (self.group_views.items) |view| for (view.cards.items) |card| if (card.leaf == leaf) {
            return if (card.body) |body| .{ .parent = body } else null;
        };
        return null;
    }

    /// The frame a docked card's pane flight draws this frame (window coordinates), null at rest.
    pub fn dockedCardFlight(self: *const Workspace, leaf: u64) ?ui.fx.anchor_transition.Frame {
        for (self.group_views.items) |view| for (view.cards.items) |card| if (card.leaf == leaf) {
            const t = card.transition orelse return null;
            return t.currentFrame();
        };
        return null;
    }

    /// The view's panes are going away for good (its tab closed): the cards' contents leave the
    /// window; each owner places its own again.
    fn parkCardContents(cx: *ui.Cx, view: *group_view.View) void {
        var presented = false;
        for (view.cards.items) |*card| {
            surface_migration.park(cx, card.content);
            presented = presented or card.pane != null or card.body != null or card.more != null;
            card.pane = null;
            card.body = null;
            card.more = null;
            card.transition = null;
        }
        // A docked card's pane / body / More button are what the AI reads to present into its pane.
        if (presented) workspace_model.publishEnvironment();
    }

    /// A docked card's pane-header action (float-split / cards-float): every callback only records the
    /// owner's request (the owner acts on its next frame).
    const CardPaneCell = struct {
        workspace: *Workspace,
        leaf: u64,
        action: enum { float, close, menu, rest } = .float,
        index: usize = 0,
        fn press(raw: ?*anyopaque) void {
            const self: *CardPaneCell = @ptrCast(@alignCast(raw orelse return));
            for (self.workspace.group_views.items) |view| for (view.cards.items) |card| if (card.leaf == self.leaf) {
                const port = card.port;
                switch (self.action) {
                    .float => if (port.float_back) |callback| callback(port.ctx),
                    .close => if (port.close) |callback| callback(port.ctx),
                    .menu => if (port.menu_action) |callback| callback(port.ctx, self.index),
                    .rest => {},
                }
                return;
            };
        }
        fn act(self: *CardPaneCell) void {
            press(self);
        }
        fn rest(raw: ?*anyopaque, _: ui.fx.anchor_transition.Phase) void {
            const self: *CardPaneCell = @ptrCast(@alignCast(raw orelse return));
            for (self.workspace.group_views.items) |view| for (view.cards.items) |*card| if (card.leaf == self.leaf) {
                card.flight = null;
                card.transition = null;
            };
        }
    };

    /// One pane per docked card, the same frame and Pane Header as a session member
    /// (`mountCardPaneHeader`). The content moves in once the panes are in the window (`presentGroup`). A fresh dock unfolds the pane from the floating
    /// rectangle (Z12 anchor mode) or fades it in.
    fn mountCardPanes(self: *Workspace, scope: *ui.Scope, view: *group_view.View) !void {
        for (view.cards.items) |*card| {
            const pane = try ui.box(self.cx, paneStyle(), .{});
            pane.meta.ownership.meta.test_id = card.ids.pane;
            try pane.appendChild(self.allocator, try self.mountCardPaneHeader(scope, view.id, card));
            // The content layer fills the pane body without adding to the pane's intrinsic size: a
            // card's long content scrolls in its own scroll area inside the split cell.
            const body = try ui.box(self.cx, .{ .width = .fill(), .min_width = 0, .height = .fill(), .min_height = 0, .flex = 1, .flex_basis = 0, .direction = .column, .overflow_hidden = true }, .{});
            const slot = try ui.box(self.cx, .{ .position = .absolute, .inset = .{ .left = .{ .px = 0 }, .top = .{ .px = 0 } }, .width = .fill(), .height = .fill(), .direction = .column }, .{});
            try body.appendChild(self.allocator, slot);
            try pane.appendChild(self.allocator, body);
            card.pane = pane;
            card.body = slot;
            if (card.flight) |flight| {
                const cell = try scope.createState(CardPaneCell, .{ .workspace = self, .leaf = card.leaf, .action = .rest });
                const t = try ui.fx.AnchorTransition.attach(scope, self.cx, pane, .{ .on_complete = CardPaneCell.rest, .on_complete_ctx = cell, .layer_parent = self.flight_layer_parent orelse self.cx.root, .z_index = flight_layer_z });
                t.setTokens(flight.tokens);
                t.snapTo(true);
                t.expand(flight.anchor);
                card.transition = t;
            }
        }
    }

    /// Flights of tab-body content (a docked pane, a tab body put back) are drawn in the window shell
    /// just under the AI launcher (z 199) and the floating layer (z 200), not in an overlay above
    /// them: the landing frame then stacks exactly like the live pane (the launcher stays on top).
    const flight_layer_z: i16 = 198;

    /// The pane frame shared by session members and docked cards (rounded, no fill or stroke).
    fn paneStyle() ui.BoxStyle {
        var pane_style = group_styles.pane();
        pane_style.background = ui.Color.TRANSPARENT;
        pane_style.border = .{ .width = 0, .radius = group_styles.pane_radius };
        pane_style.padding = .{};
        pane_style.width = .fill();
        pane_style.height = .fill();
        pane_style.flex = 1;
        pane_style.min_width = 0;
        pane_style.min_height = 0;
        return pane_style;
    }

    // ── cards-float：会话卡片浮动 ───────────────────────────────────────────────────────

    /// The window's floating session cards (`SessionFloatHost`): the workspace asks, the host acts on
    /// its next frame.
    pub const SessionFloatPort = struct {
        ctx: *anyopaque,
        /// Float `session`; `from` is its pane / tab body rectangle (where the card unfolds from).
        float: *const fn (ctx: *anyopaque, session: u64, from: ?ui.ComputedRect) void,
        /// Put a floating `session` back in place (the tab body's "放回标签页").
        put_back: *const fn (ctx: *anyopaque, session: u64) void,
    };
    pub const FloatTake = struct {
        /// The session's content node (`SessionTab.root`), now inside the floating card's frame.
        content: *ui.Node,
        /// The tab the floating card belongs to: the session's own tab, or its group tab.
        owner_tab: u64,
    };
    pub const PutBack = enum {
        /// Its own single-card tab (a group member leaves the group, keeping the session).
        own_tab,
        /// Its owner tab's split (a single-card tab's card simply goes back into its tab body).
        split,
    };

    /// The group view whose roster group holds `session`.
    fn sessionGroup(self: *const Workspace, session: u64) ?u32 {
        const roster = self.group_roster orelse return null;
        for (self.group_views.items) |view| if (roster.findById(view.id)) |group| if (group.contains(session)) return view.id;
        return null;
    }

    /// Why `session` cannot float now (the 浮动 button's Tooltip); null = it can.
    pub fn floatRefusal(self: *Workspace, session: u64) ?[]const u8 {
        const tab = self.sessionTab(session) orelse return "会话已关闭";
        if (self.session_float == null) return "这个窗口不能浮动卡片";
        if (!tab.card_type.placements.float) return "这种卡片不支持浮动";
        if (tab.floating) return "已在浮动";
        if (tab.closing or tab.owned_pending or tab.isCard() or tab.content_owner != .session) return "会话正在关闭或尚未就绪";
        if (self.sessionGroup(session)) |group| if (self.groupClosing(group)) return "所属标签页正在关闭";
        return null;
    }

    /// The pane header's 浮动 for a session card.
    pub fn requestFloatSession(self: *Workspace, session: u64) void {
        if (self.floatRefusal(session) != null) return;
        const tab = self.sessionTab(session).?;
        const port = self.session_float.?;
        const frame = if (self.sessionGroup(session) != null) tab.root.parent orelse tab.root else tab.root;
        const r = frame.globalRect();
        port.float(port.ctx, session, if (r.w > 0 and r.h > 0) r else null);
    }

    /// The floating card's owner tab: the session's group tab, or its own tab.
    pub fn floatOwnerTab(self: *const Workspace, session: u64) ?u64 {
        const tab = self.sessionTab(session) orelse return null;
        if (self.sessionGroup(session)) |group| return if (self.groupTabId(group)) |id| @backingInt(id) else null;
        return @backingInt(tab.tab_id);
    }

    /// Hand `session`'s content node to its floating card: it moves into `into` (the card's frame
    /// body) in one step. The session keeps running; the tab stays on the strip (its body shows
    /// "卡片已浮动" when nothing else is left in it).
    pub fn takeFloatSession(self: *Workspace, session: u64, into: surface_migration.Host) !FloatTake {
        if (self.floatRefusal(session) != null) return error.FloatRefused;
        const owner = self.floatOwnerTab(session) orelse return error.UnknownTab;
        const tab = self.sessionTab(session).?;
        try surface_migration.move(self.cx, tab.root, into);
        tab.setFloating(true);
        if (tab.terminal) |*terminal| terminal.setGrouped(false);
        tab.root.setStyleInline(self.allocator, .{ .width = .fill(), .height = .fill(), .flex_shrink = 1, .padding = .{} });
        tab.root.setDisplay(.flex);
        if (self.sessionGroup(session)) |group| {
            if (self.groupView(group)) |view| view.dirty = true;
            if (self.active_group_view == group) self.group_present_pending = true;
        }
        self.cx.requestRedraw();
        return .{ .content = tab.root, .owner_tab = owner };
    }

    /// Why a floating session cannot go back into its owner tab's split now; null = it can.
    pub fn floatDockRefusal(self: *Workspace, session: u64) ?[]const u8 {
        const tab = self.sessionTab(session) orelse return "会话已关闭";
        if (tab.closing) return "会话正在关闭";
        const group = self.sessionGroup(session) orelse return null;
        if (self.groupClosing(group)) return card_dock.Refusal.tab_busy.text();
        const view = self.groupView(group) orelse return card_dock.Refusal.tab_not_splittable.text();
        const r = self.terminal_area.globalRect();
        return if (card_dock.fits(.{ .x = r.x, .y = r.y, .w = r.w, .h = r.h }, self.presentedLeafCount(view))) null else card_dock.Refusal.full.text();
    }

    /// Why a floating session cannot open as its own tab now; null = it can.
    pub fn floatTabRefusal(self: *Workspace, session: u64) ?[]const u8 {
        const tab = self.sessionTab(session) orelse return "会话已关闭";
        if (tab.closing) return "会话正在关闭";
        if (self.sessionGroup(session)) |group| {
            if (self.groupClosing(group)) return card_dock.Refusal.tab_busy.text();
            if (!card_placement.canStandalone(tab.card_type)) return "这种卡片不能单独成为标签页";
        }
        return null;
    }

    /// Put a floating session card back: its content node goes back into the tab body (`split`: at
    /// the side of the split nearest to `from`, or simply back into its single-card tab) or into its
    /// own single-card tab (`own_tab`: a group member leaves the group, keeping the session). The
    /// pane flies in from `from` (Z12 anchor mode) or fades in.
    pub fn returnFloatSession(self: *Workspace, session: u64, to: PutBack, from: ?ui.ComputedRect, flight: ?group_view.Flight) !void {
        const tab = self.sessionTab(session) orelse return error.UnknownSession;
        if (!tab.floating) return;
        try surface_migration.move(self.cx, tab.root, .{ .parent = self.terminal_area });
        tab.setFloating(false);
        tab.root.setStyleInline(self.allocator, .{ .width = .fill(), .height = .fill(), .flex_shrink = 1, .padding = .{} });
        if (self.sessionGroup(session)) |group| {
            const view = self.groupView(group).?;
            if (to == .split) {
                const r = self.terminal_area.globalRect();
                const f = from orelse r;
                try view.redock.append(self.allocator, .{ .session = session, .edge = card_dock.edgeFor(.{ .x = r.x, .y = r.y, .w = r.w, .h = r.h }, .{ .x = f.x, .y = f.y, .w = f.w, .h = f.h }), .flight = flight });
                view.dirty = true;
                view.persist_pending = true;
                if (self.active_group_view == group) self.group_present_pending = true else tab.root.setDisplay(.none);
                self.cx.requestRedraw();
                return;
            }
            const roster = self.group_roster.?;
            const entry = roster.findById(group).?;
            try roster.leave(entry.name, session);
            self.refreshGroup(group);
        }
        if (self.tabIndexById(tab.tab_id)) |index| {
            const current = self.active_group_view == null and self.active_tab != null and self.active_tab.? == index;
            if (current or to == .own_tab) {
                self.selectTab(index);
                self.flyIntoTab(tab, flight);
            } else tab.root.setDisplay(.none);
        }
        self.cx.requestRedraw();
    }

    /// The single-card tab body flight of a session card put back (Z12: from the floating rectangle,
    /// or fading in place).
    fn flyIntoTab(self: *Workspace, tab: *SessionTab, flight: ?group_view.Flight) void {
        const f = flight orelse return;
        if (self.restore_flight_scope) |old| old.dispose();
        self.restore_flight_scope = null;
        const scope = self.scope.childScope() catch return;
        self.restore_flight_scope = scope;
        const t = ui.fx.AnchorTransition.attach(scope, self.cx, tab.root, .{ .layer_parent = self.flight_layer_parent orelse self.cx.root, .z_index = flight_layer_z }) catch return;
        t.setTokens(f.tokens);
        t.snapTo(true);
        t.expand(f.anchor);
    }

    /// Floating session members of the tab currently shown (for the tab body's empty state).
    fn floatedInCurrentTab(self: *Workspace, out: []u64) usize {
        var count: usize = 0;
        if (self.active_group_view) |id| {
            const view = self.groupView(id) orelse return 0;
            if (view.cards.items.len != 0) return 0;
            const group = (self.group_roster orelse return 0).findById(id) orelse return 0;
            for (group.members.items) |member| {
                const tab = self.sessionTab(member.pane_id) orelse continue;
                if (tab.content_owner != .session or tab.isCard() or tab.owned_pending) continue;
                if (!tab.floating) return 0;
                if (count < out.len) out[count] = tab.id;
                count += 1;
            }
            return count;
        }
        const index = self.active_tab orelse return 0;
        if (index >= self.tabs.items.len) return 0;
        const tab = self.tabs.items[index];
        if (!tab.floating) return 0;
        if (out.len != 0) out[0] = tab.id;
        return 1;
    }

    /// The tab body empty state "卡片已浮动" while every card of the current tab floats.
    fn syncFloatedPlaceholder(self: *Workspace) void {
        var floated: [8]u64 = undefined;
        const count = self.floatedInCurrentTab(&floated);
        if (count == 0) {
            if (self.floated_placeholder) |view| if (view.root.style.display != .none) {
                view.root.setDisplay(.none);
                self.cx.requestRedraw();
            };
            return;
        }
        const view = self.floated_placeholder orelse blk: {
            const mounted = @import("card_floated_view.zig").View.mount(self.cx, self.scope, self, putBackFloated) catch return;
            self.terminal_area.appendChild(self.allocator, mounted.root) catch return;
            self.floated_placeholder = mounted;
            break :blk mounted;
        };
        const first = self.sessionTab(floated[0]) orelse return;
        view.setFloated(self.shownName(first), count);
        if (view.root.parent != self.terminal_area) {
            if (view.root.parent) |parent| self.cx.detachChild(parent, view.root);
            self.terminal_area.appendChild(self.allocator, view.root) catch return;
        }
        if (view.root.style.display == .none) {
            view.root.setDisplay(.flex);
            self.empty_state.setDisplay(.none);
            self.cx.requestRedraw();
        }
    }

    fn putBackFloated(raw: ?*anyopaque) void {
        const self: *Workspace = @ptrCast(@alignCast(raw orelse return));
        const port = self.session_float orelse return;
        var floated: [8]u64 = undefined;
        const count = @min(self.floatedInCurrentTab(&floated), floated.len);
        for (floated[0..count]) |session| port.put_back(port.ctx, session);
    }

    pub fn dockGroupMember(self: *Workspace, group: u32, source: u64, target: u64, edge: group_view.sizing.Edge) !void {
        if (self.groupClosing(group)) return error.GroupClosing;
        const view = self.groupView(group) orelse return error.UnknownGroup;
        if (view.resizing) self.cx.cancelPointerInteractions(.explicit);
        try view.tree.dock(self.allocator, source, target, edge);
        if (view.saved_layout) |snapshot| self.allocator.free(snapshot.nodes);
        view.saved_layout = null;
        self.refreshGroup(group);
    }
    fn dropEdge(rect: ui.ComputedRect, point: ui.interaction.drag.Point) group_view.sizing.Edge {
        const x = (point.x - rect.x) / @max(1, rect.w);
        const y = (point.y - rect.y) / @max(1, rect.h);
        const nearest = @min(@min(x, 1 - x), @min(y, 1 - y));
        if (nearest == y) return .top;
        if (nearest == 1 - y) return .bottom;
        return if (x < 0.5) .left else .right;
    }
    const GroupResize = struct {
        workspace: *Workspace,
        group: u32,
        split_id: u32,
        first: *ui.Node,
        second: *ui.Node,
        first_pixels: f32 = 0,
        total_pixels: f32 = 0,
        initial_ratio: f32 = 0.5,
        test_id: [96]u8 = undefined,
        fn apply(self: *@This(), ratio: f32) void {
            const view = self.workspace.groupView(self.group) orelse return;
            view.tree.nodes.items[self.split_id].split.ratio = ratio;
            self.first.setStyleInline(self.workspace.allocator, .{ .flex = ratio });
            self.second.setStyleInline(self.workspace.allocator, .{ .flex = 1 - ratio });
            self.workspace.cx.requestRedraw();
        }
        fn update(self: *@This(), event_value: ui.interaction.drag.Event) void {
            const view = self.workspace.groupView(self.group) orelse return;
            const split = view.tree.nodes.items[self.split_id].split;
            const axis = view.presentedAxis(self.split_id);
            const delta = if (axis == .stacked) event_value.delta.y else event_value.delta.x;
            self.apply(group_view.sizing.resized(self.first_pixels, self.total_pixels, delta, view.tree.minimum(split.first, axis), view.tree.minimum(split.second, axis)));
        }
        fn drag(event_value: ui.interaction.drag.Event, raw: *anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            const view = self.workspace.groupView(self.group) orelse return;
            if (self.workspace.groupClosing(self.group) and event_value.phase != .cancel) return;
            switch (event_value.phase) {
                .start => {
                    const split = view.tree.nodes.items[self.split_id].split;
                    const axis = view.presentedAxis(self.split_id);
                    const first = self.first.globalRect();
                    const second = self.second.globalRect();
                    self.first_pixels = if (axis == .stacked) first.h else first.w;
                    self.total_pixels = self.first_pixels + if (axis == .stacked) second.h else second.w;
                    self.initial_ratio = split.ratio;
                    view.resizing = true;
                    self.update(event_value);
                },
                .move => if (view.resizing) self.update(event_value),
                .end => if (view.resizing) {
                    self.update(event_value);
                    view.resizing = false;
                    if (view.saved_layout) |snapshot| self.workspace.allocator.free(snapshot.nodes);
                    view.saved_layout = null;
                    self.workspace.saveGroupLayout(view);
                },
                .cancel => if (view.resizing) {
                    view.resizing = false;
                    self.apply(self.initial_ratio);
                },
            }
        }
    };
    fn mountGroupTree(self: *Workspace, scope: *ui.Scope, view: *group_view.View, id: u32, width: f32) anyerror!*ui.Node {
        switch (view.tree.nodes.items[id]) {
            .leaf => |session| {
                for (view.panes.items) |pane| if (pane.session == session) return pane.node;
                for (view.cards.items) |card| if (card.leaf == session) if (card.pane) |pane| return pane;
                return error.StaleSession;
            },
            .empty => return error.InvalidGroupLayout,
            .split => |split| {
                // 稿 2: before the first layout the saved axis stands; `reflowGroupAxes` corrects it.
                const axis = if (width > 0) view.tree.presentedAxis(id, width) else split.axis;
                const widths = if (width > 0) view.tree.childWidths(id, width) else [2]f32{ 0, 0 };
                var style = group_styles.root(axis == .stacked);
                style.gap = 0;
                style.flex_shrink = 1;
                style.min_width = 0;
                style.min_height = 0;
                const container = try ui.box(self.cx, style, .{});
                const first = try self.mountGroupTree(scope, view, split.first, widths[0]);
                const second = try self.mountGroupTree(scope, view, split.second, widths[1]);
                // Zero basis: the split ratio alone divides the free space, so a
                // pane's intrinsic header or content width cannot skew the
                // proportion that GroupResize measures and restores.
                first.setStyleInline(self.allocator, .{ .flex = split.ratio, .flex_basis = 0, .min_width = 0, .min_height = 0 });
                second.setStyleInline(self.allocator, .{ .flex = 1 - split.ratio, .flex_basis = 0, .min_width = 0, .min_height = 0 });
                const cell = try scope.createState(GroupResize, .{ .workspace = self, .group = view.id, .split_id = id, .first = first, .second = second });
                const vertical = axis == .stacked;
                const divider = try ui.box(self.cx, group_styles.separator(vertical), .{});
                try view.splits.append(self.allocator, .{ .split = id, .container = container, .divider = divider, .axis = axis });
                divider.setPointerDownFocus(.preserve);
                divider.meta.ownership.meta.test_id = try std.fmt.bufPrint(&cell.test_id, "groups.separator.{d}", .{id});
                divider.behavior.interaction.a11y = .{ .role = .separator, .label = if (vertical) "拖动调整上下会话高度" else "拖动调整左右会话宽度" };
                _ = try ui.interaction.drag.Binding.attach(scope, self.cx, divider, .{ .axis = if (vertical) .vertical else .horizontal, .activation_distance = @import("../../../shared/ui/interaction.zig").resize_drag_activation, .active_cursor = if (vertical) .ns_resize else .ew_resize }, GroupResize.drag, cell);
                _ = try ui.hooks.useHoverHighlight(scope, divider, divider, .background, ui.Color.TRANSPARENT, app_theme.current().selection, .{});
                try container.appendChild(self.allocator, first);
                try container.appendChild(self.allocator, divider);
                try container.appendChild(self.allocator, second);
                return container;
            },
        }
    }

    /// 稿 2: cards in one row share the width equally and keep ≥ 320 each; a
    /// row that cannot fit is presented top-bottom, and returns to a row when
    /// the window widens again. Runs after layout on the measured group root;
    /// a changed presentation re-mounts the group (only when crossing the
    /// threshold), so dividers and drag axes always match what is shown.
    pub fn reflowGroupAxes(self: *Workspace) bool {
        const id = self.active_group_view orelse return false;
        const view = self.groupView(id) orelse return false;
        const root = view.root orelse return false;
        const tree_root = view.tree.root orelse return false;
        if (view.resizing or view.dirty) return false;
        const rect = root.globalRect();
        if (rect.w <= 0) return false;
        const width = @max(0, rect.w - 2 * group_styles.gap);
        view.presented_width = width;
        if (!presentationDiffers(view, tree_root, width)) return false;
        view.dirty = true;
        self.group_present_pending = true;
        return true;
    }
    fn presentationDiffers(view: *const group_view.View, id: u32, width: f32) bool {
        const split = switch (view.tree.nodes.items[id]) {
            .split => |value| value,
            else => return false,
        };
        if (view.presentedAxis(id) != view.tree.presentedAxis(id, width)) return true;
        const widths = view.tree.childWidths(id, width);
        return presentationDiffers(view, split.first, widths[0]) or presentationDiffers(view, split.second, widths[1]);
    }

    /// 稿 3 group tab menu: the same declaration as the session tab menu (`context_menus.entries(.group_tab)`:
    /// 重命名… · 颜色 › | 全部左右 / 上下排列 | 关闭页签, danger last), mounted through `shell/view/app_menu.zig`.
    /// The menu captures the group id; every action re-checks it.
    fn showGroupTabMenu(self: *Workspace, group: u32, anchor: *ui.Node) !void {
        if (self.groupClosing(group)) return;
        const tab_id = self.groupTabId(group) orelse return;
        if (self.group_tab_menu == null) self.group_tab_menu = try app_menu.AppMenu.mountContext(self.cx, self.scope, self.tab_bar, .{ .panel_test_id = "groups.tab.menu" }, .{ .context = self, .select = groupMenuSelected, .closed = groupMenuClosed });
        const menu = self.group_tab_menu.?;
        self.group_menu_target = group;
        if (self.strip_vm) |vm| vm.suppressTips();
        const list = menus_model.entries(.group_tab, .{}, .{ .tab_color = self.tabColorChoice(tab_id) }, &self.group_menu_entries);
        menu.show(list, self.shortcuts(), anchor.globalRect());
    }
    fn groupMenuSelected(raw: *anyopaque, id: []const u8) void {
        const self: *Workspace = @ptrCast(@alignCast(raw));
        const group = self.group_menu_target orelse return;
        if (self.groupClosing(group)) return;
        const tab_id = self.groupTabId(group) orelse return;
        if (menus_model.parseTabColorId(id)) |color| {
            _ = self.setTabColor(tab_id, color);
            return;
        }
        switch (std.meta.stringToEnum(menus_model.Action, id) orelse return) {
            .rename_tab => self.beginRenamePresentation(tab_id) catch {},
            .close_session => self.requestCloseGroup(group),
            .arrange_side => self.setGroupLayout(group, .side_by_side),
            .arrange_stack => self.setGroupLayout(group, .stacked),
            else => {},
        }
    }
    fn groupMenuClosed(raw: *anyopaque) void {
        const self: *Workspace = @ptrCast(@alignCast(raw));
        self.group_menu_target = null;
    }

    /// Island B v3 focus and rest views: the focused member is the current
    /// pane (a11y `selected`); the material layer paints its plate as the
    /// focused island with an accent hairline, the others as rest islands.
    /// Pencil Tc5cZ: the focused pane's header title is 600 fg_primary with an
    /// accent type icon; resting panes use 500 fg_secondary.
    /// Pencil Tc5cZ pane meta "路径 · 列 × 行": the OSC 7 directory when the
    /// session reported one (home shortened to ~), then the live grid. Until
    /// the pane is online (or before a frame exists) the connection status
    /// text stays, so the header never shows invented facts.
    fn paneMeta(self: *Workspace, tab: *SessionTab, buffer: []u8) []const u8 {
        const status_text = if (tab.closing) "关闭中" else self.tabStatus(tab.tab_id);
        if (groupConnectionState(tab) != .online) return status_text;
        const terminal = if (tab.terminal) |*value| value else return status_text;
        if (terminal.frame_cols == 0 or terminal.frame_rows == 0) return status_text;
        const cwd: ?[]u8 = if (tab.local)
            (if (self.session_bridge.local_cwd) |copy| copy(self.session_bridge.context, tab.id, self.allocator) else null)
        else if (tab.runtime) |runtime| runtime.copyCwd(self.allocator) catch null else null;
        defer if (cwd) |path| self.allocator.free(path);
        return formatPaneMeta(buffer, cwd, homeDirectory(), terminal.frame_cols, terminal.frame_rows);
    }
    fn homeDirectory() ?[]const u8 {
        const home = std.c.getenv("HOME") orelse return null;
        return std.mem.sliceTo(home, 0);
    }
    pub fn formatPaneMeta(buffer: []u8, cwd: ?[]const u8, home: ?[]const u8, cols: u16, rows: u16) []const u8 {
        if (cwd) |path| if (path.len != 0) {
            if (home) |prefix| if (prefix.len > 1 and std.mem.startsWith(u8, path, prefix) and (path.len == prefix.len or path[prefix.len] == '/'))
                return std.fmt.bufPrint(buffer, "~{s} · {d} × {d}", .{ path[prefix.len..], cols, rows }) catch "";
            return std.fmt.bufPrint(buffer, "{s} · {d} × {d}", .{ path, cols, rows }) catch "";
        };
        return std.fmt.bufPrint(buffer, "{d} × {d}", .{ cols, rows }) catch "";
    }
    /// Keeps pane meta current without rebuilding the group (throttled; the
    /// directory query is a worker snapshot copy, not a PTY request).
    fn refreshPaneMeta(self: *Workspace, view: *group_view.View) void {
        if (self.cx.frame_time_ms - self.pane_meta_refreshed_ms < 500) return;
        self.pane_meta_refreshed_ms = self.cx.frame_time_ms;
        for (view.panes.items) |pane| {
            const tab = self.sessionTab(pane.session) orelse continue;
            const header = pane.header orelse continue;
            var buffer: [512]u8 = undefined;
            if (header.setMeta(self.paneMeta(tab, &buffer))) self.cx.requestRedraw();
        }
    }
    /// Pane-header connection dots follow the same phase as the tab dots (`tabConnectionColor`). The phase also
    /// depends on facts the rebuild hashes do not cover (the remote notice: reconnecting / lost), so the colour is a
    /// signal written here every frame instead of a value frozen at mount.
    fn refreshPaneDots(self: *Workspace, view: *group_view.View) void {
        for (view.panes.items) |pane| {
            const tab = self.sessionTab(pane.session) orelse continue;
            const header = pane.header orelse continue;
            if (header.setDot(self.tabConnectionColor(tab.tab_id))) self.cx.requestRedraw();
        }
    }
    fn syncGroupFocus(cx: *ui.Cx, view: anytype) void {
        for (view.panes.items) |pane| {
            const focused = view.focused != null and pane.session == view.focused.?;
            if (pane.header) |header| header.setFocused(focused);
            if (pane.node.behavior.interaction.a11y) |*attrs| {
                if (attrs.selected == focused) continue;
                attrs.selected = focused;
            } else pane.node.behavior.interaction.a11y = .{ .role = .group, .selected = focused };
            pane.node.markRenderDirty();
        }
        cx.requestRedraw();
    }
    /// One session pane of the split shown now, for whoever paints behind it (the shell's canvas
    /// layer paints each member's plate). The workspace owns the membership and the focus; nobody
    /// has to find the panes in the tree.
    pub const ShownGroupPane = struct { node: *ui.Node, focused: bool };
    /// Appends the session panes of the split that is displayed now (none when no split is shown).
    pub fn shownGroupPanes(self: *Workspace, out: *std.ArrayList(ShownGroupPane), allocator: std.mem.Allocator) !void {
        for (self.group_views.items) |view| {
            const root = view.root orelse continue;
            if (!root.isDisplayedInTree()) continue;
            for (view.panes.items) |pane| try out.append(allocator, .{ .node = pane.node, .focused = view.focused != null and view.focused.? == pane.session });
            return;
        }
    }
    fn groupView(self: *Workspace, id: u32) ?*group_view.View {
        for (self.group_views.items) |view| if (view.id == id) return view;
        return null;
    }

    pub fn groupIdByTab(self: *const Workspace, id: identity.TabId) ?u32 {
        const at = self.model.indexOf(id) orelse return null;
        const owner = self.model.tabs.items[at].owner;
        return if (owner == .group) @intCast(@backingInt(owner.group.id)) else null;
    }

    pub fn groupTabId(self: *const Workspace, id: u32) ?identity.TabId {
        for (self.model.tabs.items) |tab| if (tab.owner == .group and @backingInt(tab.owner.group.id) == id) return tab.id;
        return null;
    }

    pub fn groupAssistantBounds(self: *Workspace, id: u32) ?ui.ComputedRect {
        const view = self.groupView(id) orelse return null;
        const root = view.root orelse return null;
        var bounds = root.globalRect();
        const bottom = bounds.y + bounds.h;
        var top = bottom;
        for (view.panes.items) |pane| {
            if (pane.node.children.items.len == 0) continue;
            const header = pane.node.children.items[0].globalRect();
            if (header.w > 0 and header.h > 0) top = @min(top, header.y + header.h);
        }
        if (top >= bottom) return null;
        bounds.y = @max(bounds.y, top);
        bounds.h = @max(0, bottom - bounds.y);
        return bounds;
    }

    fn groupTabColor(self: *Workspace, id: u32) ?ui.Color {
        const roster = self.group_roster orelse return null;
        const group = roster.findById(id) orelse return null;
        return ui.Color.hex(@truncate(group.color));
    }

    fn groupTabStatusColor(self: *Workspace, id: u32) ui.Color {
        // 组页签的状态色与单个页签同源（shared/base/connection_presenter.zig → status_tone）。
        const roster = self.group_roster orelse return status_tone.ink(presenter.present(.ended).tone);
        const group = roster.findById(id) orelse return status_tone.ink(presenter.present(.ended).tone);
        var pending = false;
        var failed = false;
        for (group.members.items) |member| if (self.sessionTab(member.pane_id)) |tab| {
            const state = groupConnectionState(tab);
            if (state == .online) return status_tone.ink(presenter.present(.connected).tone);
            pending = pending or state == .connecting;
            failed = failed or state == .degraded;
        };
        return status_tone.ink(presenter.present(if (pending) .connecting else if (failed) .failed else .ended).tone);
    }

    pub fn activateTabId(self: *Workspace, id: identity.TabId) void {
        self.model.activate(id) catch return;
        self.presentTabId(self.model.active orelse return, .take);
    }

    fn presentTabId(self: *Workspace, id: identity.TabId, focus: TabFocus) void {
        if (self.rename_request) |request| {
            if (request.tab != id) _ = self.cancelRenameTab();
        }
        if (self.groupIdByTab(id)) |group| {
            self.setActiveGroupView(group);
            if (self.groupView(group)) |view| view.dirty = true;
            self.reveal_active = true;
            self.group_present_pending = true;
            self.rebuildTabBar() catch {};
        } else if (self.tabIndexById(id)) |index| self.presentActiveTab(index, focus);
    }

    pub const PreparedGroupView = struct {
        workspace: *Workspace,
        group_id: u32,
        tab: workspace_model.Tab,
        view: ?*group_view.View,
        source_tab: identity.TabId,
        source_owner: identity.ContentOwner,
        source_revision: u64,
        source_container: ?identity.TabId,

        pub fn validate(self: *const PreparedGroupView) !void {
            const workspace = self.workspace;
            if (self.view == null) return error.GroupTransactionConsumed;
            if (workspace.shutting_down or workspace.model.window_close != null) return error.WorkspaceClosed;
            if (workspace.groupTabId(self.group_id) != null or workspace.groupView(self.group_id) != null) return error.GroupIdentityConflict;
            const at = workspace.model.indexOf(self.source_tab) orelse return error.SourceChanged;
            const source = workspace.model.tabs.items[at];
            if (!source.owner.eql(self.source_owner) or source.revision != self.source_revision or source.container != self.source_container) return error.SourceChanged;
            if (workspace.model.order_revision == std.math.maxInt(u64)) return error.RevisionExhausted;
        }
        /// Called at the safe controller point after the roster transaction
        /// commits. Storage reservation survives unrelated ordinary tab opens.
        pub fn commit(self: *PreparedGroupView, roster: *group_model.Roster) !void {
            try self.validate();
            const group = roster.findById(self.group_id) orelse return error.UnknownGroup;
            const source = self.workspace.sessionTab(self.workspace.tabs.items[self.workspace.tabIndexById(self.source_tab) orelse return error.SourceChanged].id) orelse return error.SourceChanged;
            if (!group.contains(source.id)) return error.SourceChanged;
            const workspace = self.workspace;
            workspace.group_roster = roster;
            workspace.group_views.appendAssumeCapacity(self.view.?);
            workspace.model.tabs.appendAssumeCapacity(self.tab);
            workspace.model.recent.appendAssumeCapacity(self.tab.id);
            workspace.model.order_revision += 1;
            workspace.model.tabs.items[workspace.model.indexOf(self.source_tab).?].container = self.tab.id;
            workspace.noteEnvironment();
            workspace.model.activate(self.tab.id) catch unreachable;
            workspace.setActiveGroupView(self.group_id);
            workspace.group_present_pending = true;
            workspace.tab_rebuild_pending = true;
            workspace.reveal_active = true;
            workspace.prepared_group_views -= 1;
            self.view = null;
            workspace.cx.requestRedraw();
        }
        pub fn deinit(self: *PreparedGroupView) void {
            if (self.view) |view| {
                view.deinit(self.workspace.allocator);
                self.workspace.allocator.destroy(view);
                self.workspace.allocator.free(self.tab.details);
                self.workspace.prepared_group_views -= 1;
                self.view = null;
            }
        }
    };

    pub fn prepareGroupView(self: *Workspace, group_id: u32, name: []const u8, initial_pane: u64) !PreparedGroupView {
        if (self.shutting_down or self.model.window_close != null) return error.WorkspaceClosed;
        if (group_id == 0 or self.groupTabId(group_id) != null or self.groupView(group_id) != null) return error.GroupIdentityConflict;
        const source = self.sessionTab(initial_pane) orelse return error.SourceChanged;
        if (source.isCard() or source.owned_pending or source.closing or source.content_owner != .session) return error.SourceChanged;
        const source_at = self.model.indexOf(source.tab_id) orelse return error.SourceChanged;
        const source_model = self.model.tabs.items[source_at];
        if (self.model.order_revision == std.math.maxInt(u64)) return error.RevisionExhausted;
        const view = try self.allocator.create(group_view.View);
        errdefer self.allocator.destroy(view);
        view.* = .{ .id = group_id };
        errdefer view.deinit(self.allocator);
        try view.panes.ensureUnusedCapacity(self.allocator, 1);
        const detail = try self.allocator.dupe(u8, "会话组 · 分栏工作区");
        errdefer self.allocator.free(detail);
        const label = try std.fmt.allocPrint(self.allocator, "组 · {s}", .{name});
        defer self.allocator.free(label);
        var tab: workspace_model.Tab = .{ .id = try tab_ids.allocate(), .owner = .{ .group = .{ .id = @fromBackingInt(group_id) } }, .details = detail };
        var count = @min(label.len, tab.title.len);
        while (count > 0 and !std.unicode.utf8ValidateSlice(label[0..count])) count -= 1;
        @memcpy(tab.title[0..count], label[0..count]);
        tab.title_len = @intCast(count);
        const reservations = self.prepared_group_views + 1;
        try self.group_views.ensureUnusedCapacity(self.allocator, reservations);
        try self.model.tabs.ensureUnusedCapacity(self.allocator, reservations);
        try self.model.recent.ensureUnusedCapacity(self.allocator, reservations);
        try self.terminal_area.children.ensureUnusedCapacity(self.allocator, reservations);
        self.prepared_group_views = reservations;
        return .{ .workspace = self, .group_id = group_id, .tab = tab, .view = view, .source_tab = source.tab_id, .source_owner = source.content_owner, .source_revision = source_model.revision, .source_container = source_model.container };
    }

    pub fn openGroup(self: *Workspace, roster: *group_model.Roster, id: u32) !void {
        const group = roster.findById(id) orelse return error.UnknownGroup;
        self.group_roster = roster;
        if (self.groupView(id) == null) {
            const created = try self.allocator.create(group_view.View);
            errdefer self.allocator.destroy(created);
            created.* = .{ .id = id };
            try self.group_views.ensureUnusedCapacity(self.allocator, self.prepared_group_views + 1);
            try self.model.tabs.ensureUnusedCapacity(self.allocator, self.prepared_group_views + 1);
            try self.model.recent.ensureUnusedCapacity(self.allocator, self.prepared_group_views + 1);
            const tab_id = try tab_ids.allocate();
            const title = try std.fmt.allocPrint(self.allocator, "组 · {s}", .{group.name});
            defer self.allocator.free(title);
            try self.model.append(tab_id, .{ .group = .{ .id = @fromBackingInt(id), .revision = 1 } }, title);
            self.group_views.appendAssumeCapacity(created);
            self.noteEnvironment();
            try self.model.setDetails(tab_id, "会话组 · 分栏工作区");
        }
        if (self.groupView(id)) |view| self.loadGroupLayout(view);
        self.activateTabId(self.groupTabId(id).?);
    }

    pub fn refreshGroup(self: *Workspace, id: u32) void {
        for (self.model.tabs.items) |tab| self.restoreStandaloneIfUngrouped(tab.id);
        if (self.groupView(id)) |view| {
            view.dirty = true;
            view.persist_pending = true;
        }
        self.group_present_pending = self.active_group_view == id;
        self.rebuildTabBar() catch {};
    }

    pub fn setGroupLayout(self: *Workspace, id: u32, layout: group_view.Layout) void {
        if (self.groupClosing(id)) return;
        if (self.groupView(id)) |view| {
            if (view.resizing) self.cx.cancelPointerInteractions(.explicit);
            view.layout = layout;
            const ids = self.allocator.alloc(u64, view.panes.items.len) catch return;
            defer self.allocator.free(ids);
            for (view.panes.items, ids) |pane, *id_| id_.* = pane.session;
            view.tree.arrange(self.allocator, ids, layout) catch return;
            if (view.saved_layout) |snapshot| self.allocator.free(snapshot.nodes);
            view.saved_layout = null;
            self.saveGroupLayout(view);
            view.dirty = true;
            self.group_present_pending = true;
            self.cx.requestRedraw();
        }
    }

    pub fn splitGroup(self: *Workspace, roster: *group_model.Roster, stacked: bool) !void {
        if (self.active_group_view) |id| if (self.groupClosing(id)) return error.GroupClosing;
        const active = self.active_tab orelse return error.NoActiveTab;
        const source = self.tabs.items[active];
        if (source.content_owner != .session or source.isCard() or source.closing) return error.UnsupportedService;
        var id = self.active_group_view;
        if (id == null) {
            const name = try std.fmt.allocPrint(self.allocator, "{s} 终端组 #{d}", .{ source.titleSlice(), source.id });
            defer self.allocator.free(name);
            id = (try roster.join(name, source.id, 0xff818cf8)).id;
        }
        const group = roster.findById(id.?) orelse return error.UnknownGroup;
        const revision = group.membership_revision;
        try self.openGroup(roster, id.?);
        // The source session is a member now: it lives in the group tab, not as its own tab on the
        // strip any more (the new session joins the same way through `creation_group`).
        if (self.groupTabId(id.?)) |parent| try self.model.setContainer(source.tab_id, parent);

        const count = self.tabs.items.len;
        try self.newSessionFromTab(active);
        if (self.tabs.items.len <= count) return error.SessionNotCreated;
        const destination = self.tabs.items[self.tabs.items.len - 1].id;
        if (self.groupView(id.?)) |view| view.pending_placement = .{ .source = source.id, .session = destination, .axis = if (stacked) .stacked else .side_by_side };
        if (!group.contains(destination)) self.pending_split = .{ .group = id.?, .session = destination, .revision = revision };
        // Startup owns its independent tab until a real terminal service exists.
        try self.openGroup(roster, id.?);
    }

    /// ⌘1…⌘8 pick that tab; ⌘9 always picks the last tab (稿 3).
    pub fn selectTabOrdinal(self: *Workspace, index: usize) void {
        const target = tab_naming.ordinalTarget(index, self.model.visibleCount()) orelse return;
        if (self.model.visibleAt(target)) |at| self.activateTabId(self.model.tabs.items[at].id);
    }

    pub fn selectAdjacentTab(self: *Workspace, next: bool) void {
        const count = self.model.visibleCount();
        if (count == 0) return;
        const at = if (self.model.active) |id| self.model.visibleIndexOf(id) orelse 0 else 0;
        self.selectTabOrdinal(if (next) (at + 1) % count else (at + count - 1) % count);
    }

    pub fn requestCloseActive(self: *Workspace) void {
        if (self.active_group_view) |id| self.requestCloseGroup(id) else if (self.active_tab) |index| self.requestCloseTab(index);
    }

    /// Every presented pane of a split (session members and docked cards, float-split / cards-float):
    /// the drag-to-reorder targets. A card's leaf id stands in for the session id.
    fn dropTargets(self: *Workspace, view: *group_view.View, out: []group_view.Pane) []group_view.Pane {
        _ = self;
        var count: usize = 0;
        for (view.panes.items) |pane| if (count < out.len) {
            out[count] = pane;
            count += 1;
        };
        for (view.cards.items) |card| if (card.pane) |node| if (count < out.len) {
            out[count] = .{ .session = card.leaf, .node = node };
            count += 1;
        };
        return out[0..count];
    }

    /// Whether a member of group `id` floats (cards-float).
    fn groupHasFloating(self: *Workspace, id: u32) bool {
        const group = (self.group_roster orelse return false).findById(id) orelse return false;
        for (group.members.items) |member| if (self.sessionTab(member.pane_id)) |tab| if (tab.floating) return true;
        return false;
    }

    fn restoreGroupRoots(self: *Workspace) void {
        for (self.group_views.items) |view| if (view.resizing or view.drag_source != null) self.cx.cancelPointerInteractions(.explicit);
        for (self.tabs.items) |tab| {
            if (tab.terminal) |*terminal| {
                terminal.setHistoryHost(null) catch {};
                terminal.setGrouped(false);
            }
            // cards-float: a floating card's content stays in its floating chrome.
            if (tab.floating) continue;
            if (tab.root.parent != self.terminal_area) {
                surface_migration.move(self.cx, tab.root, .{ .parent = self.terminal_area }) catch {};
                tab.root.setStyleInline(self.allocator, .{ .width = .fill(), .height = .fill(), .flex_shrink = 1, .padding = .{} });
            }
        }
        for (self.group_views.items) |view| if (view.root) |root| root.setDisplay(.none);
    }

    const GroupCell = struct {
        workspace: *Workspace,
        group: u32,
        session: u64 = 0,
        action: GroupAction = .pin,
        test_id: [96]u8 = undefined,
        layout: ?group_view.Layout = null,
        close_dialog_open: ?*ui.Signal(bool) = null,
        fn open(self: *@This()) void {
            const roster = self.workspace.group_roster orelse return;
            self.workspace.openGroup(roster, self.group) catch {};
        }
        fn close(self: *@This()) void {
            self.workspace.requestCloseGroup(self.group);
        }
        fn act(self: *@This()) void {
            if (self.layout) |layout| {
                self.workspace.setGroupLayout(self.group, layout);
                return;
            }
            if (self.workspace.group_action) |action| action(self.workspace.group_action_context, self.group, self.session, self.action);
        }
        fn cancel(self: *@This()) void {
            if (self.workspace.groupView(self.group) == null) {
                if (self.close_dialog_open) |dialog_open| dialog_open.set(false);
                return;
            }
            self.workspace.cancelGroupClose(self.group);
        }
        fn approve(self: *@This()) void {
            self.workspace.approveGroupClose(self.group);
        }
        /// The group-close dialog's own close proposal (取消, ×, Esc, scrim): the cancel action.
        fn dialogChanged(self: *@This(), shown: bool) void {
            if (shown) return;
            self.cancel();
        }
        fn drag(event_value: ui.interaction.drag.Event, raw: *anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            const workspace = self.workspace;
            const view = workspace.groupView(self.group) orelse return;
            if (workspace.groupClosing(self.group)) return;
            switch (event_value.phase) {
                .start => {
                    view.drag_source = self.session;
                    view.drag_target = self.session;
                },
                .move => {
                    view.drag_target = null;
                    if (view.drop_marker) |marker| marker.setDisplay(.none);
                    var targets: [32]group_view.Pane = undefined;
                    for (workspace.dropTargets(view, &targets)) |pane| {
                        const rect = pane.node.globalRect();
                        const target = event_value.position_window.x >= rect.x and event_value.position_window.x < rect.x + rect.w and event_value.position_window.y >= rect.y and event_value.position_window.y < rect.y + rect.h;
                        pane.node.setBorderWidth(0);
                        pane.node.setOpacityRaw(if (target) 0.86 else 1);
                        if (target) {
                            view.drag_target = pane.session;
                            view.drop_edge = Workspace.dropEdge(rect, event_value.position_window);
                            if (pane.session != self.session) if (view.drop_marker) |marker| {
                                const bounds = view.root.?.globalRect();
                                const horizontal = view.drop_edge == .top or view.drop_edge == .bottom;
                                marker.setStyleInline(workspace.allocator, .{ .display = .flex, .width = .{ .px = if (horizontal) rect.w else 4 }, .height = .{ .px = if (horizontal) 4 else rect.h }, .inset = .{ .left = .{ .px = rect.x - bounds.x + if (view.drop_edge == .right) rect.w - 4 else 0 }, .top = .{ .px = rect.y - bounds.y + if (view.drop_edge == .bottom) rect.h - 4 else 0 } } });
                            };
                        }
                    }
                },
                .end, .cancel => {
                    if (view.drop_marker) |marker| marker.setDisplay(.none);
                    view.drag_target = null;
                    var targets: [32]group_view.Pane = undefined;
                    const presented = workspace.dropTargets(view, &targets);
                    if (event_value.phase == .end) for (presented) |pane| {
                        const rect = pane.node.globalRect();
                        const point = event_value.position_window;
                        if (point.x >= rect.x and point.x < rect.x + rect.w and point.y >= rect.y and point.y < rect.y + rect.h) {
                            view.drag_target = pane.session;
                            view.drop_edge = Workspace.dropEdge(rect, point);
                        }
                    };
                    for (presented) |pane| {
                        pane.node.setBorderWidth(0);
                        pane.node.setOpacityRaw(1);
                    }
                    if (event_value.phase == .end) if (view.drag_target) |target| if (view.drag_source) |source| {
                        workspace.dockGroupMember(self.group, source, target, view.drop_edge) catch |err| workspace.statusFailure(@errorName(err));
                    };
                    view.drag_source = null;
                    view.drag_target = null;
                },
            }
        }
        fn focusContent(self: *@This()) void {
            const index = self.workspace.tabIndex(self.session) orelse return;
            const tab = self.workspace.tabs.items[index];
            self.workspace.cx.setFocus(if (tab.terminal) |terminal| terminal.root else tab.root);
        }
        fn event(event_value: ui.events.Event, raw: ?*anyopaque) ui.events.EventResult {
            const self: *@This() = @ptrCast(@alignCast(raw orelse return .ignored));
            switch (event_value) {
                .mouse_down => {
                    const index = self.workspace.tabIndex(self.session) orelse return .ignored;
                    self.workspace.setActiveTab(index);
                    if (self.workspace.groupView(self.group)) |view| {
                        view.focused = self.session;
                        for (self.workspace.tabs.items) |tab| if (tab.plugin_renderer) |renderer| renderer.vtable.focus_changed(renderer.context, tab.id == self.session);
                        syncGroupFocus(self.workspace.cx, view);
                    }
                },
                .key_down => |key| if (key.key == .escape) {
                    self.cancel();
                    return .stop;
                },
                else => {},
            }
            return .ignored;
        }
    };

    pub fn setGroupMemberBroadcast(self: *Workspace, session: u64, enabled: bool) void {
        const tab = self.sessionTab(session) orelse return;
        if (tab.terminal == null or tab.group_broadcast_enabled == enabled) return;
        tab.group_broadcast_enabled = enabled;
        self.group_present_pending = true;
        self.cx.requestRedraw();
    }

    /// Where a Pane Header lives: a group member pane, or the standalone
    /// session in the view island (Pencil tOrT3).
    const PaneHeaderSpec = struct {
        /// Null: the single, ungrouped session (no grip, no pin, no broadcast).
        group: ?u32 = null,
        focused: bool = false,
        pinned: bool = false,
        /// Group member cell owning drag and focus routing.
        group_cell: ?*GroupCell = null,
    };
    /// Pane-header actions of a single session; group members use GroupCell.
    const StandaloneCell = struct {
        workspace: *Workspace,
        session: u64,
        action: enum { split_side, split_stack, close } = .close,
        fn act(self: *@This()) void {
            const workspace = self.workspace;
            const index = workspace.tabIndex(self.session) orelse return;
            switch (self.action) {
                .split_side, .split_stack => {
                    const roster = workspace.group_roster orelse return;
                    workspace.setActiveTab(index);
                    workspace.splitGroup(roster, self.action == .split_stack) catch |err| workspace.statusFailure(@errorName(err));
                },
                .close => workspace.requestCloseTab(index),
            }
        }
        fn focusContent(self: *@This()) void {
            const index = self.workspace.tabIndex(self.session) orelse return;
            const tab = self.workspace.tabs.items[index];
            self.workspace.cx.setFocus(if (tab.terminal) |terminal| terminal.root else tab.root);
        }
    };

    /// ZW2 / Pane Header (QGtx5), one component for split members and the
    /// single session (`pane_header.yix`, W-5 收回): grip (members only) · type icon 14 · title 12 ·
    /// status dot 6 · spacer · meta 11 · [broadcast · pin, members only] · 浮动 · More, whose menu
    /// gathers every pane action. Returns the header's view-model (root node: `vm.root`).
    fn mountPaneHeader(self: *Workspace, scope: *ui.Scope, tab: *SessionTab, spec: PaneHeaderSpec) !*pane_header.Vm {
        const grouped = spec.group != null;
        const standalone: ?*StandaloneCell = if (grouped) null else try scope.createState(StandaloneCell, .{ .workspace = self, .session = tab.id });
        const on_focus = if (spec.group_cell) |cell| self.cx.on(GroupCell, cell, GroupCell.focusContent) else self.cx.on(StandaloneCell, standalone.?, StandaloneCell.focusContent);
        const title_text = if (!grouped)
            try self.allocator.dupe(u8, self.shownName(tab))
        else if (tab.local)
            try std.fmt.allocPrint(self.allocator, "{s} · #{d}", .{ self.shownName(tab), tab.id })
        else
            try std.fmt.allocPrint(self.allocator, "{s} · {s} · #{d}", .{ self.groupMemberKind(tab), self.shownName(tab), tab.id });
        defer self.allocator.free(title_text);
        const type_asset = if (tab.terminal != null) (if (!grouped and !tab.local) ui.icons.server else ui.icons.square_terminal) else self.tabIcon(tab);
        const online = groupConnectionState(tab) == .online;
        var meta_buffer: [512]u8 = undefined;
        const broadcasting = tab.group_broadcast_enabled;
        var broadcast: ?pane_header.Toggle = null;
        var pin: ?pane_header.Toggle = null;
        var grip_id: []const u8 = "";
        if (spec.group) |group_id| {
            const grip_cell = try self.groupCell(scope, group_id, tab.id, .pin);
            grip_id = try std.fmt.bufPrint(&grip_cell.test_id, "groups.drag.{d}", .{tab.id});
            if (tab.terminal != null) {
                const broadcast_cell = try self.groupCell(scope, group_id, tab.id, .toggle_broadcast);
                const tip: []const u8 = if (!online) "连接未就绪" else if (broadcasting) "广播已开启" else "广播已关闭";
                broadcast = .{ .on = broadcasting, .disabled = !online, .label = if (!online) "广播 · 连接未就绪" else if (broadcasting) "广播 · 已开启" else "广播 · 已关闭", .tooltip = tip, .test_id = try std.fmt.bufPrint(&broadcast_cell.test_id, "groups.broadcast.{d}", .{tab.id}), .on_click = self.cx.on(GroupCell, broadcast_cell, GroupCell.act) };
            }
            // Pin: "组内置顶" is a group-only fact (host/actions.zig toggle_pin).
            const pin_cell = try self.groupCell(scope, group_id, tab.id, .pin);
            const pin_label: []const u8 = if (spec.pinned) "取消置顶" else "置顶成员";
            pin = .{ .on = spec.pinned, .label = pin_label, .tooltip = pin_label, .test_id = try std.fmt.bufPrint(&pin_cell.test_id, "groups.pin.{d}", .{tab.id}), .on_click = self.cx.on(GroupCell, pin_cell, GroupCell.act) };
        }
        // 浮动 (cards-float): every session card type may float; the button is disabled with the reason
        // when this session cannot float now.
        const float_cell = try scope.createState(SessionFloatCell, .{ .workspace = self, .session = tab.id });
        const float_id = if (grouped) try std.fmt.bufPrint(&float_cell.test_id, "groups.float.{d}", .{tab.id}) else "pane.float";
        const tooltip_id = if (grouped) try std.fmt.bufPrint(&float_cell.tooltip_id, "groups.float.{d}.tooltip", .{tab.id}) else "pane.float.tooltip";
        // More: every pane action of this header, members and single sessions alike. Declared as menu
        // entries (one arrangement rule: common first, danger last); each id runs its cell.
        var entries: [10]app_menu.Entry = undefined;
        var handlers: [10]ui.Handler(void) = undefined;
        var count: usize = 0;
        if (spec.group) |group_id| {
            const Entry = struct { action: GroupAction, id: []const u8, label: []const u8, danger: bool = false, reason: ?[]const u8 = null, group: u8 = 0, layout: ?group_view.Layout = null };
            const list = [_]Entry{
                .{ .action = .split_side, .id = "split_side", .label = "向右分屏" },
                .{ .action = .split_stack, .id = "split_stack", .label = "向下分屏" },
                .{ .action = .toggle_broadcast, .id = "toggle_broadcast", .label = if (broadcasting) "关闭广播" else "开启广播", .reason = if (!online) "连接未就绪" else if (tab.terminal == null) "不是终端会话" else null, .group = 1 },
                .{ .action = .pin, .id = "arrange_side", .label = "全部改为左右排列", .group = 1, .layout = .side_by_side },
                .{ .action = .pin, .id = "arrange_stack", .label = "全部改为上下排列", .group = 1, .layout = .stacked },
                .{ .action = .leave, .id = "leave", .label = "移出组，保留会话", .group = 2 },
                .{ .action = .close_member, .id = "close_member", .label = "关闭此会话", .danger = true },
            };
            for (list) |entry| {
                const action_cell = try self.groupCell(scope, group_id, tab.id, entry.action);
                action_cell.layout = entry.layout;
                entries[count] = .{ .id = entry.id, .label = entry.label, .danger = entry.danger, .disabled_reason = entry.reason, .group = entry.group };
                handlers[count] = self.cx.on(GroupCell, action_cell, GroupCell.act);
                count += 1;
            }
        } else {
            const can_split = card_placement.canSplitPane(tab.card_type, tab.closing) and self.group_roster != null;
            for ([_]@FieldType(StandaloneCell, "action"){ .split_side, .split_stack, .close }) |action| {
                const action_cell = try scope.createState(StandaloneCell, .{ .workspace = self, .session = tab.id, .action = action });
                entries[count] = switch (action) {
                    .split_side => .{ .id = "split_side", .label = "向右分屏", .disabled_reason = if (can_split) null else "此会话不能分屏" },
                    .split_stack => .{ .id = "split_stack", .label = "向下分屏", .disabled_reason = if (can_split) null else "此会话不能分屏" },
                    .close => .{ .id = "close", .label = "关闭页签", .command = .close_tab, .danger = true },
                };
                handlers[count] = self.cx.on(StandaloneCell, action_cell, StandaloneCell.act);
                count += 1;
            }
        }
        const trigger_id = if (spec.group) |group_id| blk: {
            const menu_cell = try self.groupCell(scope, group_id, tab.id, .pin);
            break :blk try std.fmt.bufPrint(&menu_cell.test_id, "groups.menu.{d}", .{tab.id});
        } else "pane.more";
        return pane_header.mount(self.cx, scope, .{
            .test_ids = .{
                .header = if (grouped) "groups.pane.header" else "pane.header",
                .type_icon = if (grouped) "groups.pane.type_icon" else "pane.type_icon",
                .title = if (grouped) "groups.pane.title" else "pane.title",
                .status_dot = if (grouped) "groups.pane.status_dot" else "pane.status_dot",
                .status = if (grouped) "groups.pane.status" else "pane.status",
                .grip = grip_id,
                .float = float_id,
                .float_tooltip = tooltip_id,
                .more = trigger_id,
                .menu = if (grouped) "groups.member_menu" else "pane.menu",
            },
            .icon = type_asset,
            .focused = spec.focused,
            .title = title_text,
            .dot = self.tabConnectionColor(tab.tab_id),
            .has_meta = true,
            .meta = self.paneMeta(tab, &meta_buffer),
            .drag = if (spec.group_cell) |cell| .{ .context = cell, .handler = GroupCell.drag } else null,
            .broadcast = broadcast,
            .pin = pin,
            .float_refusal = self.floatRefusal(tab.id),
            .float_click = self.cx.on(SessionFloatCell, float_cell, SessionFloatCell.act),
            .menu = entries[0..count],
            .menu_handlers = handlers[0..count],
            .router = self.shortcuts(),
            .more_label = if (grouped) "成员菜单" else "窗格操作",
            .on_focus = on_focus,
        });
    }

    /// The pane header's 浮动 of a session card (cards-float).
    const SessionFloatCell = struct {
        workspace: *Workspace,
        session: u64,
        test_id: [96]u8 = undefined,
        tooltip_id: [96]u8 = undefined,
        fn act(self: *@This()) void {
            self.workspace.requestFloatSession(self.session);
        }
    };

    /// The Pane Header of a docked card (float-split / cards-float): the same `pane_header.yix` as a
    /// session member, with the parts the card has — grip (drag to re-split) · type icon · title ·
    /// 浮动 · 更多 (浮动 · the card's own actions · 关闭). Session facts (status dot, path meta,
    /// broadcast, pin) are not there: a non-session card is not a roster member (M6).
    fn mountCardPaneHeader(self: *Workspace, scope: *ui.Scope, group: u32, card: *group_view.CardLeaf) !*ui.Node {
        const drag_cell = try self.groupCell(scope, group, card.leaf, .pin);
        const grip_id = if (card.ids.grip.len != 0) card.ids.grip else try std.fmt.bufPrint(&drag_cell.test_id, "groups.drag.{d}", .{card.leaf});
        var refusal_buffer: [96]u8 = undefined;
        const float_refusal: ?[]const u8 = if (card.port.float_back == null) std.fmt.bufPrint(&refusal_buffer, "{s}不支持浮动", .{card.title}) catch "不支持浮动" else null;
        const float_cell = try scope.createState(CardPaneCell, .{ .workspace = self, .leaf = card.leaf, .action = .float });
        var entries: [12]app_menu.Entry = undefined;
        var handlers: [12]ui.Handler(void) = undefined;
        var count: usize = 0;
        // Pencil O5 (ai-redesign-c): every row carries its icon (关闭 stays last: danger rows sort last).
        entries[count] = .{ .id = "float", .label = "浮动", .icon = "picture-in-picture-2", .disabled_reason = if (card.port.float_back == null) "不支持浮动" else null };
        handlers[count] = self.cx.on(CardPaneCell, float_cell, CardPaneCell.act);
        count += 1;
        const menu_ids = [_][]const u8{ "menu.0", "menu.1", "menu.2", "menu.3", "menu.4", "menu.5" };
        for (card.port.menu[0..@min(card.port.menu.len, 6)], 0..) |entry, index| {
            const cell = try scope.createState(CardPaneCell, .{ .workspace = self, .leaf = card.leaf, .action = .menu, .index = index });
            entries[count] = .{ .id = menu_ids[index], .label = entry.label, .icon = entry.icon, .group = 1 };
            handlers[count] = self.cx.on(CardPaneCell, cell, CardPaneCell.act);
            count += 1;
        }
        if (card.port.close != null) {
            const cell = try scope.createState(CardPaneCell, .{ .workspace = self, .leaf = card.leaf, .action = .close });
            entries[count] = .{ .id = "close", .label = "关闭", .icon = "x", .danger = true };
            handlers[count] = self.cx.on(CardPaneCell, cell, CardPaneCell.act);
            count += 1;
        }
        const vm = try pane_header.mount(self.cx, scope, .{
            .test_ids = .{
                .header = card.ids.header,
                .title = card.ids.title,
                .grip = grip_id,
                .float = card.ids.float,
                .float_tooltip = card.ids.float_tooltip,
                .more = if (card.ids.more.len != 0) card.ids.more else "groups.card_more",
                .menu = if (card.ids.menu.len != 0) card.ids.menu else "groups.card_menu",
            },
            .icon = card.icon,
            .accent_icon = card.port.accent_icon,
            .title = card.title,
            .drag = .{ .context = drag_cell, .handler = GroupCell.drag },
            .float_refusal = float_refusal,
            .float_click = self.cx.on(CardPaneCell, float_cell, CardPaneCell.act),
            .menu = entries[0..count],
            .menu_handlers = handlers[0..count],
            .router = self.shortcuts(),
            .more_label = "窗格操作",
        });
        card.more = vm.more_node;
        return vm.root.?;
    }

    /// Island B v3 single session (Pencil oQFwD › Pane bCHLr › Pane Header
    /// tOrT3): the same Pane Header as a split member sits above an ungrouped
    /// terminal session, so split / close stay one click away in its More menu.
    /// Rebuilt only when its facts change; meta refreshes on the pane-meta clock.
    fn syncStandaloneHeader(self: *Workspace) bool {
        const tab: ?*SessionTab = blk: {
            if (self.active_group_view != null) break :blk null;
            const index = self.active_tab orelse break :blk null;
            if (index >= self.tabs.items.len) break :blk null;
            const candidate = self.tabs.items[index];
            if (candidate.terminal == null or candidate.content_owner != .session or candidate.isCard() or candidate.owned_pending) break :blk null;
            if (candidate.root.parent != self.terminal_area or candidate.root.style.display == .none) break :blk null;
            break :blk candidate;
        };
        const current = tab orelse {
            if (self.standalone_header) |header| if (header.style.display != .none) {
                header.setDisplay(.none);
                return true;
            };
            return false;
        };
        var hash = std.hash.Wyhash.init(1);
        std.hash.autoHash(&hash, current.id);
        hash.update(self.shownName(current));
        std.hash.autoHash(&hash, groupConnectionState(current));
        std.hash.autoHash(&hash, current.closing);
        std.hash.autoHash(&hash, current.local);
        std.hash.autoHash(&hash, self.group_roster != null);
        std.hash.autoHash(&hash, self.session_float != null);
        const next = hash.final();
        if (self.standalone_header != null and self.standalone_hash == next) {
            const header = self.standalone_header.?;
            var changed = false;
            if (header.style.display == .none) {
                header.setDisplay(.flex);
                changed = true;
            }
            if (self.standalone_header_vm) |vm| {
                if (vm.setDot(self.tabConnectionColor(current.tab_id))) self.cx.requestRedraw();
            }
            if (self.cx.frame_time_ms - self.standalone_meta_ms >= 500) {
                self.standalone_meta_ms = self.cx.frame_time_ms;
                if (self.standalone_header_vm) |vm| {
                    var buffer: [512]u8 = undefined;
                    if (vm.setMeta(self.paneMeta(current, &buffer))) self.cx.requestRedraw();
                }
            }
            return changed;
        }
        self.standalone_hash = next;
        self.dropStandaloneHeader();
        const scope = self.scope.childScope() catch return false;
        self.standalone_scope = scope;
        const header_vm = self.mountPaneHeader(scope, current, .{}) catch |err| {
            applog.warn(.workspace, "pane header: {s}", .{@errorName(err)});
            return false;
        };
        const header = header_vm.root.?;
        self.terminal_area.insertChildBefore(self.allocator, header, if (self.terminal_area.children.items.len != 0) self.terminal_area.children.items[0] else null) catch {
            self.cx.destroyDetached(header);
            return false;
        };
        self.standalone_header = header;
        self.standalone_header_vm = header_vm;
        self.standalone_meta_ms = self.cx.frame_time_ms;
        self.cx.requestRedraw();
        return true;
    }
    fn dropStandaloneHeader(self: *Workspace) void {
        if (self.standalone_header) |old| {
            self.cx.detachChild(self.terminal_area, old);
            self.cx.destroyDetached(old);
        }
        self.standalone_header = null;
        self.standalone_header_vm = null;
        if (self.standalone_scope) |old| old.dispose();
        self.standalone_scope = null;
    }

    fn groupCell(self: *Workspace, scope: *ui.Scope, id: u32, session: u64, action: GroupAction) !*GroupCell {
        return scope.createState(GroupCell, .{ .workspace = self, .group = id, .session = session, .action = action });
    }

    fn presentGroup(self: *Workspace, view: *group_view.View) !void {
        @import("../../../shared/ui/surface/lifecycle_budget.zig").counters.group_presentations += 1;
        self.loadGroupLayout(view);
        const roster = self.group_roster orelse return;
        const group = roster.findById(view.id) orelse return;
        // A live group's status/layout refresh must not take input from an
        // outside editor. An explicit tab activation still hands input to the
        // member: its prior group root is hidden, or focus is on the tab strip.
        // A docked card that holds the keyboard keeps it too: its content is a kept surface that
        // only moved into (or between) panes, the reader is working in it.
        const preserve_outside_focus = if (self.cx.focus_manager.getFocused()) |focused| focus: {
            for (view.cards.items) |card| if (focused == card.content or focused.isDescendantOf(card.content)) break :focus true;
            break :focus if (view.root) |old_root|
                old_root.isDisplayedInTree() and !focused.isDescendantOf(old_root) and
                    !focused.isDescendantOf(self.tab_bar)
            else
                false;
        } else false;
        self.restoreGroupRoots();
        view.resizing = false;
        view.drop_marker = null;
        // The panes are rebuilt around the kept surfaces: the new panes go into the window first,
        // the surfaces move from the old panes into them in one step each, the old panes go last.
        // A surface is never out of the window in between (LIFECYCLE.md §2).
        var retired: RetiredGroupRoot = .{ .workspace = self, .view = view, .root = view.root, .scope = view.scope };
        defer retired.finish();
        view.root = null;
        view.scope = null;
        // The docked cards' panes are rebuilt (cleared here, mounted by `mountCardPanes`): the AI
        // reads them to present into its pane. Published after the rebuild, whether it completed.
        defer if (view.cards.items.len != 0) self.noteEnvironment();
        for (view.cards.items) |*card| {
            card.pane = null;
            card.body = null;
            card.more = null;
            card.transition = null;
        }
        const scope = try self.scope.childScope();
        view.scope = scope;
        view.panes.clearRetainingCapacity();
        view.splits.clearRetainingCapacity();
        var root_style = group_styles.root(view.layout == .stacked);
        root_style.gap = 0;
        // The island's 4pt inset around the split panes (Pencil `hQA3L` padding 4).
        root_style.padding = ui.Padding.all(group_styles.gap);
        const root = try ui.box(self.cx, root_style, .{});
        root.meta.ownership.meta.test_id = "groups.workspace";
        view.root = root;
        for (self.tabs.items) |tab| if (!tab.floating) tab.root.setDisplay(.none);
        var ordered: std.ArrayList(group_model.Member) = .empty;
        defer ordered.deinit(self.allocator);
        if (group.pinned_pane) |pinned| for (group.members.items) |member| {
            if (member.pane_id == pinned) try ordered.append(self.allocator, member);
        };
        for (group.members.items) |member| if (group.pinned_pane != member.pane_id) try ordered.append(self.allocator, member);
        for (ordered.items) |member| {
            const tab = self.sessionTab(member.pane_id) orelse continue;
            if (tab.content_owner != .session or tab.isCard() or tab.owned_pending) continue;
            // cards-float: a floating member stays in its floating chrome; it is not a pane now.
            if (tab.floating) continue;
            if (tab.terminal) |*terminal| terminal.setGrouped(true);
            const pane = try ui.box(self.cx, paneStyle(), .{});
            const cell = try self.groupCell(scope, view.id, tab.id, .pin);
            pane.meta.ownership.meta.test_id = try std.fmt.bufPrint(&cell.test_id, "groups.pane.{d}", .{tab.id});
            pane.behavior.events.capture_context = cell;
            pane.behavior.events.on_event_capture = GroupCell.event;
            const header = try self.mountPaneHeader(scope, tab, .{ .group = view.id, .focused = view.focused != null and view.focused.? == tab.id, .pinned = group.pinned_pane == tab.id, .group_cell = cell });
            try view.panes.append(self.allocator, .{ .session = tab.id, .node = pane, .header = header });
            try pane.appendChild(self.allocator, header.root.?);

            if (view.focused == null or self.sessionTab(view.focused.?) == null) view.focused = tab.id;
        }
        try self.mountCardPanes(scope, view);
        if (view.focused) |focused| {
            var found = false;
            for (view.panes.items) |pane| if (pane.session == focused) {
                found = true;
            };
            if (!found) view.focused = if (view.panes.items.len != 0) view.panes.items[0].session else null;
        }
        syncGroupFocus(self.cx, view);
        const ids = try self.allocator.alloc(u64, view.panes.items.len + view.cards.items.len);
        defer self.allocator.free(ids);
        for (view.panes.items, ids[0..view.panes.items.len]) |pane, *id_| id_.* = pane.session;
        for (view.cards.items, ids[view.panes.items.len..]) |card, *id_| id_.* = card.leaf;
        // float-split: a freshly docked card goes to one side of the whole tab body split.
        for (view.cards.items) |*card| if (!card.placed) {
            card.placed = true;
            if (view.tree.root != null) try view.tree.dockOuter(self.allocator, card.leaf, card.edge);
            view.persist_pending = true;
        };
        // cards-float: a floating member put back goes to one side of the whole split, like a card.
        // (Its leaf left the tree while it floated: `sync` prunes leaves that are not presented.)
        var redocked: std.ArrayList(group_view.Redock) = .empty;
        defer redocked.deinit(self.allocator);
        for (view.redock.items) |entry| {
            for (view.panes.items) |pane| if (pane.session == entry.session) {
                try redocked.append(self.allocator, entry);
                if (view.tree.root != null and view.tree.find(entry.session) == null) {
                    // Drop leaves that are no longer presented first, so the new side is measured
                    // against what is shown.
                    if (view.tree.root) |tree_root| view.tree.root = view.tree.pruneTo(tree_root, ids);
                    if (view.tree.root != null) try view.tree.dockOuter(self.allocator, entry.session, entry.edge);
                }
                break;
            };
        }
        view.redock.clearRetainingCapacity();
        try view.tree.sync(self.allocator, ids, view.layout);
        if (view.saved_layout) |snapshot| if (view.cards.items.len == 0 and group_view.sizing.leafCount(snapshot) == ids.len) {
            var restored: group_view.sizing.Tree = .{};
            errdefer restored.deinit(self.allocator);
            try restored.nodes.appendSlice(self.allocator, snapshot.nodes);
            restored.root = snapshot.root;
            for (restored.nodes.items) |*node| if (node.* == .leaf) {
                node.leaf = ids[@intCast(node.leaf - 1)];
            };
            view.tree.deinit(self.allocator);
            view.tree = restored;
            self.allocator.free(snapshot.nodes);
            view.saved_layout = null;
        };
        if (view.pending_placement) |placement| if (view.tree.find(placement.session) != null and view.tree.find(placement.source) != null) {
            if (view.saved_layout) |snapshot| self.allocator.free(snapshot.nodes);
            view.saved_layout = null;
            try view.tree.dock(self.allocator, placement.session, placement.source, if (placement.axis == .stacked) .bottom else .right);
            view.pending_placement = null;
            view.persist_pending = true;
        };
        if (group.pinned_pane != view.presented_pin) {
            if (group.pinned_pane) |pinned| if (view.tree.find(pinned)) |pinned_id| if (view.tree.root) |tree_root| {
                var first_id = tree_root;
                while (view.tree.nodes.items[first_id] == .split) first_id = view.tree.nodes.items[first_id].split.first;
                const displaced = view.tree.nodes.items[first_id];
                view.tree.nodes.items[first_id] = .{ .leaf = pinned };
                view.tree.nodes.items[pinned_id] = displaced;
            };
            view.presented_pin = group.pinned_pane;
        }
        if (view.tree.root) |tree_root| try root.appendChild(self.allocator, try self.mountGroupTree(scope, view, tree_root, view.presented_width));
        const marker = try ui.box(self.cx, .{ .position = .absolute, .display = .none, .background = app_theme.current().accent, .hit_behavior = .pass_through, .z_index = 30 }, .{});
        marker.meta.ownership.meta.test_id = "groups.drop_hint";
        view.drop_marker = marker;
        try root.appendChild(self.allocator, marker);
        try self.terminal_area.appendChild(self.allocator, root);
        for (view.panes.items) |pane| {
            const tab = self.sessionTab(pane.session) orelse continue;
            try surface_migration.move(self.cx, tab.root, .{ .parent = pane.node });
            tab.root.setStyleInline(self.allocator, .{ .width = .fill(), .height = .fill(), .flex_shrink = 1, .padding = .{} });
            tab.root.setDisplay(.flex);
        }
        for (view.cards.items) |card| if (card.body) |body| try surface_migration.move(self.cx, card.content, .{ .parent = body });
        self.empty_state.setDisplay(.none);
        for (self.tabs.items) |tab| if (tab.plugin_renderer) |renderer| renderer.vtable.focus_changed(renderer.context, view.focused == tab.id);
        if (view.focused) |id| if (self.tabIndex(id)) |index| {
            self.setActiveTab(index);
            if (!(preserve_outside_focus and self.cx.focus_manager.getFocused() != null) and
                self.confirming_id == null and (view.dialog_open == null or !view.dialog_open.?.peek()))
            {
                self.cx.setFocus(if (self.tabs.items[index].terminal) |terminal| terminal.root else self.tabs.items[index].root);
            }
        };
        // cards-float: the pane of a member put back flies in from its floating rectangle (Z12).
        for (redocked.items) |entry| if (entry.flight) |flight| for (view.panes.items) |pane| if (pane.session == entry.session) {
            const t = try ui.fx.AnchorTransition.attach(scope, self.cx, pane.node, .{ .layer_parent = self.flight_layer_parent orelse self.cx.root, .z_index = flight_layer_z });
            t.setTokens(flight.tokens);
            t.snapTo(true);
            t.expand(flight.anchor);
            break;
        };
        if (view.persist_pending and view.saved_layout == null and !self.groupHasFloating(view.id)) {
            self.saveGroupLayout(view);
            view.persist_pending = false;
        }
        view.dirty = false;
    }

    /// The previous presentation of a group view, taken down once the new one holds the surfaces.
    /// A card content still inside it (the rebuild failed half way) leaves the window instead of
    /// being destroyed with the panes; its owner places it again.
    const RetiredGroupRoot = struct {
        workspace: *Workspace,
        view: *group_view.View,
        root: ?*ui.Node,
        scope: ?*ui.Scope,

        fn finish(self: *RetiredGroupRoot) void {
            const cx = self.workspace.cx;
            if (self.root) |root| {
                for (self.view.cards.items) |card| if (card.content.isDescendantOf(root)) surface_migration.park(cx, card.content);
                for (self.workspace.tabs.items) |tab| if (tab.root.isDescendantOf(root)) {
                    surface_migration.move(cx, tab.root, .{ .parent = self.workspace.terminal_area }) catch surface_migration.park(cx, tab.root);
                };
                if (root.parent) |parent| cx.detachChild(parent, root);
                cx.destroyDetached(root);
            }
            if (self.scope) |scope| scope.dispose();
            self.root = null;
            self.scope = null;
        }
    };

    fn restoreStandaloneIfUngrouped(self: *Workspace, tab_id: identity.TabId) void {
        const index = self.model.indexOf(tab_id) orelse return;
        const parent = self.model.tabs.items[index].container orelse return;
        const group_id = self.groupIdByTab(parent) orelse {
            self.model.setContainer(tab_id, null) catch {};
            return;
        };
        const session_index = self.tabIndexById(tab_id) orelse return;
        const roster = self.group_roster orelse return;
        const group = roster.findById(group_id);
        if (group == null or !group.?.contains(self.tabs.items[session_index].id)) self.model.setContainer(tab_id, null) catch {};
    }
    fn creationGroupFor(self: *Workspace, source: SessionId) ?u32 {
        const roster = self.group_roster orelse return null;
        if (self.active_group_view) |id| if (roster.findById(id)) |group| if (group.contains(source) and !self.groupClosing(id)) return id;
        for (roster.groups.items) |group| if (group.contains(source) and !self.groupClosing(group.id)) return group.id;
        return null;
    }

    fn pollGroupWorkspace(self: *Workspace) bool {
        if (self.pending_host_group_drop) |drop| {
            self.pending_host_group_drop = null;
            _ = self.registry.get(drop.owner) catch |err| {
                self.statusFailure(@errorName(err));
                return false;
            };
            const index = self.registry.indexOf(drop.owner.id) orelse return false;
            self.openHostInGroup(index, drop.target) catch |err| self.statusFailure(@errorName(err));
        }
        if (self.pending_sidebar_drop) |request| {
            self.pending_sidebar_drop = null;
            _ = self.applyAssetAction(request) catch |err| {
                self.statusFailure(@errorName(err));
                return false;
            };
            return true;
        }
        if (self.pending_tab_drop) |drop| {
            const ready = self.settleTabDrop() catch |err| {
                applog.warn(.workspace, "group settle failed: {s}", .{@errorName(err)});
                self.releaseTabDrop();
                self.statusFailure(@errorName(err));
                return false;
            };
            if (!ready) return false;
            defer self.releaseTabDrop();
            self.dropTabIntoGroup(drop.source, drop.target) catch |err| {
                applog.warn(.workspace, "group drop failed: {s}", .{@errorName(err)});
                self.statusFailure(@errorName(err));
            };
        }

        for (self.model.tabs.items) |tab| self.restoreStandaloneIfUngrouped(tab.id);
        if (self.pending_split) |pending| {
            if (self.sessionTab(pending.session)) |tab| {
                const ready = groupConnectionState(tab) == .online;
                if (ready) {
                    self.pending_split = null;
                    if (self.group_roster) |roster| if (roster.findById(pending.group)) |group| {
                        if (group.membership_revision == pending.revision) {
                            _ = roster.join(group.name, tab.id, group.color) catch return false;
                            self.refreshGroup(group.id);
                        } else self.status("组成员已变化，新会话保留为独立页签");
                    };
                } else if (tab.failed or (tab.local and tab.local_state == .failed)) {
                    self.pending_split = null;
                    self.statusFailure("新分栏启动失败，原组布局已保留");
                }
            } else self.pending_split = null;
        }
        self.pollGroupClose();
        if (self.active_group_view) |group_id| if (self.groupView(group_id)) |view| if (self.group_roster) |roster| if (roster.findById(group_id)) |group| {
            var hash = std.hash.Wyhash.init(0);
            std.hash.autoHash(&hash, group.membership_revision);
            std.hash.autoHash(&hash, group.pinned_pane);
            for (group.members.items) |member| {
                std.hash.autoHash(&hash, member.pane_id);
                if (self.sessionTab(member.pane_id)) |tab| {
                    std.hash.autoHash(&hash, tab.generation);
                    std.hash.autoHash(&hash, tab.failed);
                    std.hash.autoHash(&hash, tab.closing);
                    std.hash.autoHash(&hash, tab.local_state);
                    std.hash.autoHash(&hash, tab.group_broadcast_enabled);
                    std.hash.autoHash(&hash, tab.file_ready);
                    std.hash.autoHash(&hash, pluginConnectionState(tab));
                    if (tab.terminal) |terminal| std.hash.autoHash(&hash, terminal.tombstone.state);
                    std.hash.autoHash(&hash, if (tab.runtime) |runtime| runtime.isConnected() else false);
                }
            }
            const next = hash.final();
            if (view.state_hash != next) {
                view.state_hash = next;
                self.group_present_pending = true;
            }
        };
        if (!self.group_present_pending) {
            if (self.active_group_view) |id| if (self.groupView(id)) |view| {
                self.refreshPaneMeta(view);
                self.refreshPaneDots(view);
            };
            return false;
        }
        self.group_present_pending = false;
        if (self.active_group_view) |id| if (self.groupView(id)) |view| {
            self.presentGroup(view) catch |err| self.statusFailure(@errorName(err));
            return true;
        };
        return false;
    }
    fn groupRisk(self: *Workspace, id: SessionId) u8 {
        const risk = if (self.close_bridge.risk) |callback| callback(self.close_bridge.context, id) else CloseRisk{};
        return @as(u8, @intFromBool(risk.transfer)) | (@as(u8, @intFromBool(risk.ai_write)) << 1) | (@as(u8, @intFromBool(risk.socks)) << 2) | (@as(u8, @intFromBool(risk.local_process)) << 3) | (@as(u8, @intFromBool(risk.local_unknown)) << 4);
    }

    pub fn groupClosing(self: *Workspace, id: u32) bool {
        const view = self.groupView(id) orelse return false;
        return if (view.close) |plan| plan.phase == .closing else false;
    }

    fn groupImpact(self: *Workspace, id: SessionId) group_close.Impact {
        if (self.close_bridge.impact) |callback| return callback(self.close_bridge.context, id);
        const risk = self.groupRisk(id);
        return .{ .command = @intFromBool(risk & 8 != 0), .transfer = @intFromBool(risk & 1 != 0), .ai = @intFromBool(risk & 2 != 0), .socks = @intFromBool(risk & 4 != 0), .unknown = @intFromBool(risk & 16 != 0) };
    }

    fn captureGroupCloseMember(self: *Workspace, id: SessionId) ?group_close.Member {
        const tab = self.sessionTab(id) orelse return null;
        var member: group_close.Member = .{ .id = tab.id, .generation = tab.generation, .risk = self.groupRisk(id), .impact = self.groupImpact(id), .handle = if (tab.content_owner == .session) tab.content_owner.session else null };
        member.remote_effect_unknown = member.impact.remote_effect_unknown;
        var buffer: [512]u8 = undefined;
        const display = std.fmt.bufPrint(&buffer, "{s} · {s}", .{ tab.titleSlice(), self.groupMemberKind(tab) }) catch tab.titleSlice();
        member.setLabel(display);
        return member;
    }

    /// Local release and remote business consequences are separate receipts.
    /// The AI/tool owner must first retain its bounded remote-effect check.
    pub fn receiveGroupRemoteEffectUnknown(self: *Workspace, handle: identity.SessionHandle) void {
        for (self.group_views.items) |view| if (view.close) |*plan| {
            for (plan.members.items) |*member| if (member.handle != null and member.handle.?.eql(handle)) {
                member.remote_effect_unknown = true;
                self.cx.requestRedraw();
            };
        };
    }

    pub fn requestCloseGroup(self: *Workspace, id: u32) void {
        const roster = self.group_roster orelse return;
        const group = roster.findById(id) orelse return;
        const view = self.groupView(id) orelse return;
        if (self.groupClosing(id)) return;
        // Never replace the ledger of an unfinished original cleanup request.
        if (view.close) |*plan| {
            if (plan.phase == .partial) {
                self.showGroupCloseDialog(view, true) catch {};
                return;
            }
            for (plan.members.items) |member| if (member.state == .cleanup_unknown or member.state == .closing or member.state == .await_confirm) {
                self.showGroupCloseDialog(view, true) catch {};
                return;
            };
            plan.deinit(self.allocator);
        }
        view.close = .{ .revision = group.membership_revision };
        for (group.members.items) |member| if (self.captureGroupCloseMember(member.pane_id)) |captured| {
            view.close.?.append(self.allocator, captured) catch return;
        };
        self.showGroupCloseDialog(view, false) catch |err| self.statusFailure(@errorName(err));
    }

    fn cancelGroupClose(self: *Workspace, id: u32) void {
        const view = self.groupView(id) orelse return;
        if (view.dialog_open) |open| open.set(false);
        if (view.close) |*plan| {
            if (plan.phase == .closing) {
                plan.stop();
                self.showGroupCloseDialog(view, true) catch {};
            } else if (plan.phase == .confirming) {
                if (plan.retry) {
                    plan.stop();
                } else {
                    plan.deinit(self.allocator);
                    view.close = null;
                }
            }
        }
        self.abortCloseBatch();
    }

    fn approveGroupClose(self: *Workspace, id: u32) void {
        const roster = self.group_roster orelse return;
        const group = roster.findById(id) orelse return;
        const view = self.groupView(id) orelse return;
        const plan = if (view.close) |*p| p else return;
        if (plan.phase == .partial) {
            plan.prepareRetry(group.membership_revision) catch |err| {
                self.statusFailure(@errorName(err));
                return;
            };
            // Reprepare only original failed/cancelled handles. A replacement
            // generation is not covered, and newly joined members never enter.
            for (plan.members.items) |*member| if (member.eligible) {
                const fresh = self.captureGroupCloseMember(member.id) orelse {
                    member.state = .closed;
                    member.eligible = false;
                    continue;
                };
                if (fresh.generation != member.generation or !std.meta.eql(fresh.handle, member.handle)) {
                    member.state = .failed;
                    member.eligible = false;
                } else {
                    member.impact = fresh.impact;
                    member.risk = fresh.risk;
                }
            };
            self.showGroupCloseDialog(view, false) catch {};
            return;
        }
        if (plan.phase != .confirming) return;
        var valid = plan.revision == group.membership_revision;
        for (plan.members.items) |*member| if (member.eligible and member.state == .queued) {
            const fresh = self.captureGroupCloseMember(member.id) orelse {
                valid = false;
                continue;
            };
            if (fresh.generation != member.generation or !std.meta.eql(fresh.handle, member.handle) or !fresh.impact.eql(member.impact) or fresh.risk != member.risk) valid = false;
        };
        if (!valid) {
            if (plan.retry) {
                plan.revision = group.membership_revision;
                for (plan.members.items) |*member| if (member.eligible) {
                    if (self.captureGroupCloseMember(member.id)) |fresh| {
                        if (fresh.generation == member.generation and std.meta.eql(fresh.handle, member.handle)) {
                            member.impact = fresh.impact;
                            member.risk = fresh.risk;
                        } else {
                            member.state = .failed;
                            member.eligible = false;
                        }
                    } else {
                        member.state = .closed;
                        member.eligible = false;
                    }
                };
                self.showGroupCloseDialog(view, false) catch {};
            } else self.requestCloseGroup(id);
            self.status("组成员或影响已变化，请重新确认");
            return;
        }
        plan.phase = .closing;
        if (!plan.group_hook_started) {
            plan.group_hook_started = true;
            if (self.group_action) |action| {
                action(self.group_action_context, id, 0, .stop_broadcast);
                action(self.group_action_context, id, 0, .stop_group_ai);
            }
        }
        // Individual owners continue through the existing V0.1.1 coordinator.
        self.showGroupCloseDialog(view, true) catch {};
        self.cx.requestRedraw();
    }

    fn showGroupCloseDialog(self: *Workspace, view: *group_view.View, partial: bool) !void {
        if (view.dialog_open) |open| open.set(false);
        const scope = try self.scope.childScope();
        const open = try scope.createSignal(bool, false);
        view.dialog_open = open;
        view.dialog_scope = scope;
        const cell = try self.groupCell(scope, view.id, 0, .pin);
        cell.close_dialog_open = open;
        const plan = if (view.close) |*p| p else return;
        const roster = self.group_roster orelse return;
        const group = roster.findById(view.id) orelse return;
        // The shared confirmation (focus on 取消; 取消 / × / Esc / scrim = GroupCell.cancel).
        const dialog = try group_close_view.mount(self.cx, scope, .{ .open = .{ .split = ui.split(open, self.cx.on(GroupCell, cell, GroupCell.dialogChanged)) }, .group_name = group.name, .plan = plan, .partial = partial, .approve = self.cx.on(GroupCell, cell, GroupCell.approve) });
        if (!dialog.modal.portaled) try self.terminal_area.appendChild(self.allocator, dialog.modal.overlay);
        view.dialog = dialog.modal.overlay;
        open.set(true);
    }

    fn pollGroupClose(self: *Workspace) void {
        var retired: ?*group_view.View = null;
        for (self.group_views.items) |view| {
            const plan = if (view.close) |*p| p else continue;
            if (plan.phase != .closing and !(plan.phase == .partial and plan.awaiting != null)) continue;
            if (plan.awaiting) |id| {
                if (self.sessionTab(id)) |tab| {
                    const reported = if (self.close_bridge.close_state) |callback| callback(self.close_bridge.context, id) else null;
                    if (reported == .cleanup_unknown) {
                        const changed = plan.record(id, .cleanup_unknown);
                        plan.phase = .partial;
                        if (changed) self.showGroupCloseDialog(view, true) catch {};
                        self.cx.scheduleRedrawAfterNs(100 * std.time.ns_per_ms);
                        continue;
                    }
                    if (tab.closing or self.confirming_id == tab.tab_id) {
                        _ = plan.record(id, if (self.confirming_id == tab.tab_id) .await_confirm else .closing);
                        self.cx.scheduleRedrawAfterNs(33 * std.time.ns_per_ms);
                        continue;
                    }
                    _ = plan.record(id, if (reported == .failed) .failed else .cancelled);
                    plan.awaiting = null;
                    plan.stop();
                    self.showGroupCloseDialog(view, true) catch {};
                    continue;
                }
                _ = plan.record(id, .closed);
                plan.awaiting = null;
                view.dirty = true;
                if (self.group_roster) |roster| _ = roster.leavePane(id);
                self.group_present_pending = self.active_group_view == view.id;
                if (plan.phase == .partial) {
                    if (plan.counts().closed != plan.members.items.len) {
                        self.showGroupCloseDialog(view, true) catch {};
                        continue;
                    }
                    // The last original cleanup may converge after Stop.
                    // All local receipts are now real; perform normal retirement.
                    plan.phase = .closing;
                }
            }
            if (plan.phase != .closing) continue;
            const member = plan.next() orelse {
                if (plan.counts().closed == plan.members.items.len) {
                    plan.phase = .complete;
                    if (plan.counts().unknown != 0) {
                        self.showGroupCloseDialog(view, true) catch {};
                    } else if (view.dialog_open) |open| open.set(false);
                    if (self.active_group_view == view.id) {
                        self.restoreGroupRoots();
                        self.setActiveGroupView(null);
                    }
                    retired = view;
                    break;
                }
                plan.phase = .partial;
                self.showGroupCloseDialog(view, true) catch {};
                continue;
            };
            if (self.tabIndex(member.id)) |index| {
                const fresh = self.captureGroupCloseMember(member.id).?;
                if (fresh.generation != member.generation or !std.meta.eql(fresh.handle, member.handle)) {
                    _ = plan.record(member.id, .failed);
                    plan.stop();
                    self.showGroupCloseDialog(view, true) catch {};
                    continue;
                }
                plan.awaiting = member.id;
                if (!fresh.impact.eql(member.impact) or fresh.risk != member.risk) {
                    _ = plan.record(member.id, .await_confirm);
                    self.requestCloseTab(index);
                } else {
                    _ = plan.record(member.id, .closing);
                    self.forceCloseTab(index);
                    if (self.sessionTab(member.id)) |remaining| {
                        if (!remaining.closing and self.confirming_id != remaining.tab_id) {
                            _ = plan.record(member.id, .failed);
                            plan.awaiting = null;
                            plan.stop();
                            self.showGroupCloseDialog(view, true) catch {};
                        }
                    }
                }
            } else _ = plan.record(member.id, .closed);
            self.cx.scheduleRedrawAfterNs(33 * std.time.ns_per_ms);
        }
        if (retired) |view| {
            if (self.groupTabId(view.id)) |id| {
                const at = self.model.indexOf(id).?;
                self.model.completeClose(id, self.model.tabs.items[at].owner) catch {};
            }
            self.restoreGroupRoots();
            // float-split: docked floating cards close with the tab that holds them.
            parkCardContents(self.cx, view);
            var closing_cards = view.cards;
            view.cards = .empty;
            defer closing_cards.deinit(self.allocator);
            for (closing_cards.items) |card| card.port.closed(card.port.ctx);
            if (view.root) |root| {
                self.cx.detachChild(self.terminal_area, root);
                self.cx.destroyDetached(root);
            }
            if (view.scope) |scope| scope.dispose();
            for (self.group_views.items, 0..) |candidate, index| if (candidate == view) {
                _ = self.group_views.orderedRemove(index);
                self.noteEnvironment();
                break;
            };
            view.deinit(self.allocator);
            self.allocator.destroy(view);
            if (self.model.active) |id| self.presentTabId(id, .take);
            self.rebuildTabBar() catch {};
        }
    }

    pub fn selectTab(self: *Workspace, index: usize) void {
        self.selectTabFocus(index, .take);
    }

    /// `take`: the reader activated the tab — its content gets the keyboard. `keep`: the tab body is
    /// only put back in shape (a split made for a docked card dissolved); whoever holds the keyboard
    /// outside the tab body (the card that just floated again) keeps it.
    const TabFocus = enum { take, keep };

    fn selectTabFocus(self: *Workspace, index: usize, focus: TabFocus) void {
        if (self.tabs.items.len == 0) return;
        if (index >= self.tabs.items.len) return;
        if (self.tabs.items[index].owned_pending) return;
        const tab_id = self.tabs.items[index].tab_id;
        self.restoreStandaloneIfUngrouped(tab_id);
        self.model.activate(tab_id) catch return;
        if (self.model.active != tab_id) {
            self.presentTabId(self.model.active orelse return, focus);
            return;
        }
        self.presentActiveTab(index, focus);
    }
    fn presentActiveTab(self: *Workspace, index: usize, focus: TabFocus) void {
        if (self.rename_request) |request| {
            if (request.tab != self.tabs.items[index].tab_id) _ = self.cancelRenameTab();
        }
        self.reveal_active = true;
        applog.debug(.ui, "selectTab index={d}", .{index});
        self.setActiveTab(index);
        self.restoreGroupRoots();
        self.setActiveGroupView(null);
        for (self.tabs.items, 0..) |tab, i| {
            // cards-float: a floating card's content is shown by its floating card (folded into its tab
            // when another tab is current), never hidden here.
            tab.root.setDisplay(if (i == index or tab.floating) .flex else .none);
            if (tab.plugin_renderer) |renderer| renderer.vtable.focus_changed(renderer.context, i == index);
        }
        self.empty_state.setDisplay(.none);
        // The status-bar grid label mirrors the ACTIVE tab only: other tabs'
        // frame hooks keep running, so they must not write the shared node.
        for (self.tabs.items) |tab| if (tab.terminal) |*terminal| {
            terminal.grid_status_node = null;
        };
        const terminal = if (self.tabs.items[index].terminal) |*value| value else null;
        if (terminal) |value| {
            // Pencil CC3v4: the playback bar belongs to the replay pane (bottom), not a slot above the island.
            value.setHistoryHost(null) catch {};
            if (self.history_card_host) |slot| slot.setDisplay(.none);
            value.grid_status_node = self.grid_node;
            value.grid_label_shown = false;
        } // force one rewrite from the new tab
        self.rebuildTabBar() catch return;
        // The terminal pane is the tab's primary input surface: route
        // keystrokes there immediately instead of waiting for a click.
        const held_outside = if (self.cx.focus_manager.getFocused()) |focused| !focused.isDescendantOf(self.terminal_area) and !focused.isDescendantOf(self.tab_bar) else false;
        if (focus == .take or !held_outside) self.cx.setFocus(if (self.tabs.items[index].terminal) |*value| value.root else self.tabs.items[index].root);
    }

    /// Entry point for every tab-close request. A live session (runtime
    /// attached) must first pass the close-confirmation card
    /// (docs/SPEC/mockups/mockup-close-confirm.png): the ✕ button and any
    /// future close paths route here. Failed or never-connected tabs close
    /// immediately — exactly the old behavior.
    pub fn requestCloseTab(self: *Workspace, index: usize) void {
        if (index >= self.tabs.items.len) return;
        if (self.tabs.items[index].closing) {
            self.forceCloseTab(index);
            return;
        }
        const risk = if (self.close_bridge.risk) |callback| callback(self.close_bridge.context, self.tabs.items[index].id) else CloseRisk{};
        if (risk.any()) {
            self.confirmClose(index);
            return;
        }
        self.forceCloseTab(index);
    }

    fn confirmClose(self: *Workspace, index: usize) void {
        const tab = self.tabs.items[index];
        if (tab.local) if (self.close_bridge.confirm) |confirm| {
            self.confirming_tab = index;
            self.confirming_id = tab.tab_id;
            confirm(self.close_bridge.context, tab.id);
            return;
        };
        self.showCloseConfirm(index);
    }

    pub fn resolveLocalCloseConfirmation(self: *Workspace, id: SessionId, confirm: bool) void {
        const tab = self.sessionTab(id) orelse return;
        if (!tab.local or self.confirming_id != tab.tab_id) return;
        if (confirm) self.onConfirmForceClose() else self.onCancelConfirm();
    }

    pub fn requestCloseOthers(self: *Workspace, keep: usize) void {
        if (keep >= self.tabs.items.len or self.model.window_close != null) return;
        const kept = self.tabs.items[keep];
        var excluded: std.ArrayList(identity.GroupId) = .empty;
        defer excluded.deinit(self.allocator);
        if (self.group_roster) |roster| for (roster.groups.items) |group| {
            if (group.contains(kept.id)) excluded.append(self.allocator, @fromBackingInt(group.id)) catch return;
        };
        const targets = self.model.freezeCloseTargets(kept.tab_id, excluded.items) catch return;
        defer self.allocator.free(targets);
        self.close_targets.clearRetainingCapacity();
        // The mandatory group decision precedes every member's standalone
        // presentation. Released session targets then fall out by stable ID.
        for (targets) |target| if (target.owner == .group) self.close_targets.append(self.allocator, target) catch return;
        for (targets) |target| if (target.owner != .group) self.close_targets.append(self.allocator, target) catch return;
        self.close_cursor = 0;
        self.close_others_keep = self.tabs.items[keep].id;
        self.continueCloseOthers();
    }

    fn continueCloseOthers(self: *Workspace) void {
        if (self.close_others_keep == null and self.window_close_request == null) return;
        if (self.window_close_reconcile) {
            self.window_close_reconcile = false;
            self.hideCloseConfirm();
        }
        while (self.close_cursor < self.close_targets.items.len) {
            const target = self.close_targets.items[self.close_cursor];
            if (!self.model.isCurrentTarget(target)) {
                self.close_cursor += 1;
                continue;
            }
            if (target.owner == .group) {
                const group_id: u32 = @intCast(@backingInt(target.owner.group.id));
                const view = self.groupView(group_id) orelse {
                    self.close_cursor += 1;
                    continue;
                };
                if (view.close) |plan| {
                    if (plan.phase == .partial) self.abortCloseBatch();
                } else self.requestCloseGroup(group_id);
                return;
            }
            const index = self.tabIndexById(target.tab) orelse return;
            if (self.tabs.items[index].closing) {
                if (self.window_close_request != null) {
                    self.close_cursor += 1;
                    continue;
                }
                return;
            }
            const risk = if (self.close_bridge.risk) |callback| callback(self.close_bridge.context, self.tabs.items[index].id) else CloseRisk{};
            if (risk.any()) {
                self.confirmClose(index);
                return;
            }
            self.forceCloseTab(index);
            // Window close must dispatch every approved owner before waiting
            // for release: sibling SSH channels can share one native parent.
            // windowTargetsReleased still requires every actual close receipt.
            if (self.tabIndexById(target.tab)) |remaining| {
                if (self.window_close_request == null or !self.tabs.items[remaining].closing) return;
            }
            self.close_cursor += 1;
        }
        self.close_others_keep = null;
    }

    /// One queue owns the frozen targets for both close-others and window
    /// close. A cursor preserves the original slice for host receipt checks.
    pub fn beginWindowCloseBatch(self: *Workspace, ticket: @import("../../../host/window_host.zig").Close) ![]const workspace_model.CloseTarget {
        try self.startPollLoop();
        const targets = try self.model.beginWindowClose(ticket);
        self.close_targets.deinit(self.allocator);
        self.close_targets = .empty;
        defer self.allocator.free(targets);
        for (targets) |target| if (target.owner == .group) try self.close_targets.append(self.allocator, target);
        for (targets) |target| if (target.owner != .group) try self.close_targets.append(self.allocator, target);

        self.close_cursor = 0;
        self.close_others_keep = null;
        self.window_close_request = ticket.request;
        self.window_close_reconcile = true;
        self.cx.requestRedraw();
        self.cx.scheduleRedrawAfterNs(33 * std.time.ns_per_ms);
        return self.close_targets.items;
    }

    /// The application owns ticket/model cancellation and operation receipts.
    /// Clearing this queue never cancels a different or newer window request.
    pub fn endWindowCloseBatch(self: *Workspace, request: u64) bool {
        if (self.window_close_request != request) return false;
        self.window_close_request = null;
        self.window_close_reconcile = false;
        self.close_cursor = 0;
        self.close_targets.clearRetainingCapacity();
        self.close_others_keep = null;
        return true;
    }

    fn abortCloseBatch(self: *Workspace) void {
        const request = self.window_close_request;
        self.close_targets.clearRetainingCapacity();
        self.close_cursor = 0;
        self.close_others_keep = null;
        self.window_close_request = null;
        self.window_close_reconcile = false;
        if (request) |id| if (self.window_close_bridge.cancelled) |cancelled| cancelled(self.window_close_bridge.context, id);
    }

    /// Compatibility alias: keeps the historic public name working while
    /// routing through the confirm-first flow above.
    pub fn closeTab(self: *Workspace, index: usize) void {
        self.requestCloseTab(index);
    }

    /// Unconditional tab teardown — the former closeTab body. Only
    /// requestCloseTab (dead tabs) and the confirmation card (user accepted
    /// the risk rows) may call this.
    pub fn forceCloseTab(self: *Workspace, index: usize) void {
        if (index >= self.tabs.items.len) return;
        const tab = self.tabs.items[index];
        if (self.close_bridge.request_close) |request| {
            tab.setClosing(true);
            switch (request(self.close_bridge.context, tab.tab_id, tab.content_owner)) {
                .released => self.receiveCloseReceipt(tab.tab_id, tab.content_owner, true),
                .awaiting => self.status("正在关闭会话，等待已启动的操作收尾。"),
                .unknown => self.statusFailure("关闭尚未完成：资源释放结果未知。再次点击关闭按钮可重试检查。"),
                .rejected => {
                    tab.setClosing(false);
                    self.abortCloseBatch();
                    self.statusFailure("关闭失败：会话状态已变化，请重试；连接资源尚未确认释放。");
                },
            }
            return;
        }
        self.removeClosedTab(index);
    }

    /// Resource owners call this from their controller thread. Actual node
    /// removal is deferred until the after-layout hook, outside event dispatch.
    pub fn receiveCloseReceipt(self: *Workspace, id: identity.TabId, owner: identity.ContentOwner, released: bool) void {
        const index = self.tabIndexById(id) orelse return;
        if (!self.tabs.items[index].content_owner.eql(owner)) return;
        if (!released) {
            self.status("会话仍在关闭，请稍候");
            return;
        }
        for (self.close_receipts.items) |pending| if (pending.tab == id and pending.owner.eql(owner)) return;
        self.close_receipts.append(self.allocator, .{ .tab = id, .owner = owner }) catch return;
        self.cx.requestRedraw();
    }

    fn removeClosedTab(self: *Workspace, requested_index: usize) void {
        if (requested_index >= self.tabs.items.len) return;
        const requested_id = self.tabs.items[requested_index].tab_id;
        if (self.close_bridge.cleanup) |callback| callback(self.close_bridge.context, self.tabs.items[requested_index].id);
        const index = self.tabIndexById(requested_id) orelse return;
        if (self.confirming_id) |pending| {
            if (pending == requested_id) self.hideCloseConfirm() else self.confirming_tab = self.tabIndexById(pending);
        }
        applog.info(.workspace, "forceCloseTab index={d}", .{index});
        const tab = self.tabs.items[index];
        if (!tab.owned_pending) self.model.completeClose(tab.tab_id, tab.content_owner) catch return;
        if (tab.owned_origin) {
            if (self.group_roster) |roster| _ = roster.leavePane(tab.id);
        }
        if (self.rename_session == tab.id) _ = self.cancelRenameTab();
        for (self.connect_jobs.items) |job| {
            if (job.ticket.matches(tab.ticket())) {
                job.cancelled.store(true, .release);
                job.host_key_bridge.cancel();
                job.auth_bridge.cancel();
                if (self.host_key_job == job) self.hideHostKeyConfirm();
            }
        }
        // Stop the per-frame hook first (same UI thread → no interleaving):
        // after this point nothing may touch the tab's worker or terminal
        // nodes. The hook used to keep running until app exit, and its next
        // frame after runtime cleanup read a destroyed TextSlot / detached
        // node tree (assertOwnedByActiveWorld SIGSEGV).
        if (tab.terminal) |*terminal| {
            terminal.removeFrameHook(self.cx);
            if (tab.runtime != null) terminal.releaseCommandDocument();
        }
        if (tab.root.parent) |parent| self.cx.detachChild(parent, tab.root);
        // Member teardown only (idempotent): the runtime struct stays alive
        // until its scope cleanup entry destroys it at app dispose —
        // destroying here would double-free on the quit path.
        if (tab.runtime) |runtime| _ = runtime.releaseStep(.{ .session_id = tab.id, .retention_days = self.app_config.log.retention_days });
        // Remove the pane from all runtime broadcast groups before freeing
        // its tab identity, so later input cannot target a closed session.
        if (self.input_bridge) |bridge| _ = bridge;
        if (tab.terminal) |*terminal| {
            terminal.clearPendingPaste();
            terminal.releaseBuffers(self.cx);
        }
        // Search and other terminal child scopes are released by releaseBuffers;
        // dispose their Local parent only after those owned pointers are cleared.
        if (tab.local_scope) |scope| scope.dispose();
        tab.local_scope = null;
        if (tab.remote_notice_scope) |scope| scope.dispose();
        tab.remote_notice_scope = null;
        tab.remote_notice = null;
        if (tab.plugin_renderer) |renderer| renderer.vtable.unmount(renderer.context);
        tab.setPluginRenderer(null);
        tab.transfer_trays = .{ null, null };
        if (tab.file_scope) |scope| scope.dispose();
        tab.file_scope = null;
        // 非会话卡片的内容节点归卡片宿主：先摘下，tab 的槽销毁后再交还宿主。
        const card_closed: ?identity.CardId = if (tab.content_owner == .card) tab.content_owner.card else null;
        if (tab.card_content) |content| if (content.parent) |parent| self.cx.detachChild(parent, content);
        tab.card_content = null;
        self.cx.destroyDetached(tab.root);
        if (tab.plugin_protocol_id.len != 0) self.allocator.free(tab.plugin_protocol_id);
        if (tab.host_snapshot) |*snapshot| snapshot.deinit();
        self.allocator.destroy(tab);
        if (card_closed) |card| if (self.card_tab_port) |port| port.closed(port.context, card);
        self.removeTabAt(index);
        if (self.tabs.items.len == 0) {
            self.setActiveTab(null);
            self.status("未连接");
            self.empty_state.setDisplay(.flex);
            self.refreshSavedConnections() catch {};
            // No live session: reset the grid-size label to a placeholder.
            if (self.grid_node) |grid| {
                grid.setTextContent(self.allocator, "—") catch {};
                grid.markRenderDirty();
            }
        } else self.setActiveTab(if (self.model.active) |id| self.tabIndexById(id) else null);
        self.rebuildTabBar() catch return;
        // 会话关闭 → 主机可能回到离线，状态点重算。
        self.rebuildSidebar() catch {};
        if (self.active_group_view) |group| {
            if (self.groupView(group)) |view| view.dirty = true;
            self.group_present_pending = true;
        } else if (self.model.active) |id| self.presentTabId(id, .take);
    }

    /// Legacy host-key confirmation for runners without a connection host
    /// (production windows route host keys through the authentication
    /// challenge, see pollHostKeyConfirm). A zenit `Modal`: default barrier
    /// and panel, window portal, focus trap; Esc (its dismiss proposal) rejects
    /// the key. Mounted once and hidden; showing it rewrites the detail text.
    fn mountHostKeyConfirm(self: *Workspace) !void {
        if (self.host_key_root != null) return;
        const cx = self.cx;
        const p = self.palette;
        const open = try self.scope.createSignal(bool, false);
        const modal = try ui.widgets.Modal(.{
            .open = ui.split(open, cx.on(Workspace, self, hostKeyOpenChanged)),
            .width = 430,
            .max_height = 600,
            .close_on_overlay = false,
        }).mount(self.scope, cx);
        if (!modal.portaled) try self.terminal_area.appendChild(cx.allocator, modal.overlay);
        const body = modal.body;
        try body.appendChild(cx.allocator, try ui.text(cx, "主机密钥首连确认", .{ .font_size = 14, .font_weight = 600, .color = p.fg }));
        const detail = try ui.text(cx, "", .{ .font_size = 11, .color = p.fg_secondary, .wrap = .word });
        try body.appendChild(cx.allocator, detail);
        const buttons = try ui.box(cx, .{ .direction = .row, .justify = .center, .gap = 10 }, .{});
        const reject_button = try ui.widgets.Button(.{
            .label = "拒绝",
            .variant = .secondary,
            .on_click = cx.on(Workspace, self, rejectHostKey),
        }).mount(self.scope, cx);
        try buttons.appendChild(cx.allocator, reject_button);
        // 替换主机密钥：与认证卡片、连接失败页同一文案与危险样式（CONSISTENCY_AUDIT #2）。
        const changed_button = try ui.widgets.Button(.{
            .label = confirm_ui.label(.replace, "主机密钥"),
            .variant = .danger,
            .on_click = cx.on(Workspace, self, trustChangedHostKey),
        }).mount(self.scope, cx);
        changed_button.setDisplay(.none);
        try buttons.appendChild(cx.allocator, changed_button);
        try buttons.appendChild(cx.allocator, try ui.widgets.Button(.{
            .label = "仅本次",
            .variant = .secondary,
            .on_click = cx.on(Workspace, self, trustHostKeyOnce),
        }).mount(self.scope, cx));
        // Persist this fingerprint in the configured known_hosts store. This
        // remains an explicit first-use choice; subsequent connections with
        // the same host/port/key skip the modal, while a changed key still
        // requires an explicit replacement confirmation.
        const remember_button = try ui.widgets.Button(.{
            .label = "记住此主机",
            .variant = .primary,
            .on_click = cx.on(Workspace, self, trustHostKeySave),
        }).mount(self.scope, cx);
        try buttons.appendChild(cx.allocator, remember_button);
        try body.appendChild(cx.allocator, buttons);
        self.host_key_open = open;
        self.host_key_root = modal.overlay;
        self.host_key_card = modal.dialog;
        self.host_key_reject = reject_button;
        self.host_key_detail = detail;
        self.host_key_changed_button = changed_button;
    }

    /// Modal dismissal (Esc) only proposes closing; for a pending host key
    /// that means "reject", exactly like the 拒绝 button.
    fn hostKeyOpenChanged(self: *Workspace, open: bool) void {
        if (!open) self.rejectHostKey();
    }

    fn hideHostKeyConfirm(self: *Workspace) void {
        if (self.host_key_open) |open| open.set(false);
        self.host_key_job = null;
        if (self.active_tab) |index| if (index < self.tabs.items.len) self.cx.setFocus(if (self.tabs.items[index].terminal) |*value| value.root else self.tabs.items[index].root);
    }

    fn rejectHostKey(self: *Workspace) void {
        if (self.host_key_job) |job| job.host_key_bridge.cancel();
        self.hideHostKeyConfirm();
    }

    fn trustHostKeyOnce(self: *Workspace) void {
        self.replyHostKey(.trust_once);
        self.hideHostKeyConfirm();
    }

    fn trustHostKeySave(self: *Workspace) void {
        self.replyHostKey(.trust_save);
        self.hideHostKeyConfirm();
    }

    fn trustChangedHostKey(self: *Workspace) void {
        self.replyHostKey(.{ .replace_host_key = "yes" });
        self.hideHostKeyConfirm();
    }

    /// Per-tick lifecycle checks do not need the connection log or hop labels.
    pub const ConnectionLifecycle = struct {
        finished: bool,
        failure: ?anyerror,
        cleanup: @import("../../../host/operation.zig").Cleanup,
    };

    fn projectConnectionLifecycle(job: *ConnectJob, finished: bool, cancelled: bool, resources: *const ResourceLedger.Snapshot) ConnectionLifecycle {
        return .{
            .finished = finished,
            .failure = if (finished and job.automatic_retry_deadline_ns == null) job.err else null,
            .cleanup = if (resources.hasUnknown() or job.cleanup_unknown) .unknown else if (finished and resources.released()) .released else if (cancelled) .releasing else .not_started,
        };
    }

    pub fn connectionLifecycle(self: *Workspace, key: OperationKey) ?ConnectionLifecycle {
        for (self.connect_jobs.items) |job| {
            if (job.operation_key == null or !job.operation_key.?.eql(key)) continue;
            _ = self.findTicket(job.ticket) orelse return null;
            const finished = job.ready.load(.acquire);
            const resources = job.resource_ledger.snapshot();
            return projectConnectionLifecycle(job, finished, job.cancelled.load(.acquire), &resources);
        }
        return null;
    }

    pub const ConnectionProgress = struct {
        pub const Hop = struct {
            name: []const u8,
            host: []const u8,
            user: []const u8,
            port: u16,
            auth_mode: hosts_mod.AuthMode = .agent,
            /// Path only; never key material.
            identity_file: []const u8 = "",
            /// Presence of a saved secret, never its value.
            saved_password: bool = false,
            saved_passphrase: bool = false,
        };
        /// A pending automatic retry of this initial connection.
        pub const Retry = struct {
            /// The attempt that will start when the wait ends (1-based).
            next_attempt: u8,
            limit: u8,
            deadline_ns: i128,
            delay_ns: i128,
            /// Every automatic wait of this chain, in order.
            delays_ns: [8]i128 = @splat(0),
            delay_count: usize = 0,

            pub fn delays(self: *const Retry) []const i128 {
                return self.delays_ns[0..self.delay_count];
            }
        };
        pub const LogRecord = struct { key: OperationKey, entry: @import("../../../proto/ssh/connection_progress.zig").Journal.Entry };
        key: OperationKey,
        hops: [9]Hop = undefined,
        hop_count: usize,
        journal: @import("../../../proto/ssh/connection_progress.zig").Journal.Snapshot,
        resources: ResourceLedger.Snapshot,
        finished: bool,
        attached: bool,
        attachment_failed: bool,
        cancelled: bool,
        failure: ?anyerror,
        cleanup: @import("../../../host/operation.zig").Cleanup,
        automatic_retry_pending: bool = false,
        retry: ?Retry = null,
        /// The failure that scheduled `retry` (hidden from `failure` while a
        /// retry is pending, which keeps the attempt out of the failed state).
        pending_failure: ?anyerror = null,
        connect_timeout_sec: u16 = 0,
        logs: [128]LogRecord = undefined,
        log_count: usize = 0,
        dropped: usize = 0,

        fn appendJournal(self: *ConnectionProgress, key: OperationKey, journal: @import("../../../proto/ssh/connection_progress.zig").Journal.Snapshot) void {
            self.dropped +|= journal.dropped;
            for (journal.entries[0..journal.count]) |entry| {
                if (self.log_count == self.logs.len) {
                    std.mem.copyForwards(LogRecord, self.logs[0 .. self.logs.len - 1], self.logs[1..]);
                    self.log_count -= 1;
                    self.dropped +|= 1;
                }
                self.logs[self.log_count] = .{ .key = key, .entry = entry };
                self.log_count += 1;
            }
        }
    };

    pub fn nextConnectionPresentationKey(self: *Workspace) ?OperationKey {
        for (self.connect_jobs.items) |job| {
            if (job.progress_dismissed) continue;
            const key = job.operation_key orelse continue;
            const tab = self.findTicket(job.ticket) orelse continue;
            if (job.ready.load(.acquire) and !tab.failed) if (tab.runtime) |runtime| {
                if (runtime.isAttached()) continue;
            };
            return key;
        }
        return null;
    }

    pub fn dismissConnectionProgress(self: *Workspace, key: OperationKey) !void {
        const progress = self.connectionLifecycle(key) orelse return error.StaleConnection;
        if (!progress.finished or progress.cleanup != .released) return error.CleanupNotReleased;
        for (self.connect_jobs.items) |job| {
            if (job.operation_key != null and job.operation_key.?.eql(key)) {
                job.progress_dismissed = true;
                return;
            }
        }
        return error.StaleConnection;
    }

    /// Endpoint slices borrow the frozen job only for this UI call. Consumers
    /// must copy them before retaining; no credentials enter this projection.
    pub fn connectionProgress(self: *Workspace, key: OperationKey) ?ConnectionProgress {
        for (self.connect_jobs.items) |job| {
            if (job.operation_key == null or !job.operation_key.?.eql(key)) continue;
            const tab = self.findTicket(job.ticket) orelse return null;
            const finished = job.ready.load(.acquire);
            const resources = job.resource_ledger.snapshot();
            const cancelled = job.cancelled.load(.acquire);
            const lifecycle_state = projectConnectionLifecycle(job, finished, cancelled, &resources);
            var result: ConnectionProgress = .{
                .key = key,
                .hop_count = job.jump_snapshot.value.len + 1,
                .journal = job.progress.snapshot(),
                .resources = resources,
                .finished = lifecycle_state.finished,
                .attached = false,
                .attachment_failed = finished and tab.failed and job.automatic_retry_deadline_ns == null,
                .cancelled = cancelled,
                .failure = lifecycle_state.failure,
                .automatic_retry_pending = job.automatic_retry_deadline_ns != null,
                .retry = if (job.automatic_retry_deadline_ns) |deadline| automaticRetry(job, deadline) else null,
                .pending_failure = if (job.automatic_retry_deadline_ns != null) job.err else null,
                .connect_timeout_sec = job.config_snapshot.value.ssh.connect_timeout_sec,
                .cleanup = lifecycle_state.cleanup,
            };
            if (result.hop_count > result.hops.len) return null;
            result.dropped = job.progress_history_dropped;
            for (job.progress_history.items) |previous| result.appendJournal(previous.key, previous.journal);
            result.appendJournal(key, result.journal);
            for (0..result.hop_count) |hop| {
                const host = authenticationHost(job, hop) orelse return null;
                result.hops[hop] = .{ .name = host.name, .host = host.host, .user = host.user, .port = host.port, .auth_mode = host.auth_mode, .identity_file = host.identity_file orelse "", .saved_password = host.password != null and host.password.?.len != 0, .saved_passphrase = host.key_passphrase != null and host.key_passphrase.?.len != 0 };
            }
            if (finished and !cancelled and !tab.failed) if (tab.runtime) |runtime| {
                result.attached = runtime.isAttached();
            };
            return result;
        }
        return null;
    }

    fn automaticRetry(job: *const ConnectJob, deadline: i128) ConnectionProgress.Retry {
        var retry: ConnectionProgress.Retry = .{ .next_attempt = job.connection_attempts + 1, .limit = ConnectJob.automatic_attempt_limit, .deadline_ns = deadline, .delay_ns = job.automatic_retry_delay_ns };
        retry.delay_count = @min(retry.delays_ns.len, ConnectJob.automatic_attempt_limit - 1);
        for (retry.delays_ns[0..retry.delay_count], 1..) |*delay, attempts| delay.* = @as(i128, ConnectJob.automaticRetryDelayMs(@intCast(attempts))) * std.time.ns_per_ms;
        return retry;
    }

    fn pendingRetryJob(self: *Workspace, key: OperationKey) ?*ConnectJob {
        for (self.connect_jobs.items) |job| {
            if (job.operation_key == null or !job.operation_key.?.eql(key) or job.cancelled.load(.acquire)) continue;
            if (job.automatic_retry_deadline_ns == null) return null;
            return job;
        }
        return null;
    }

    /// "立即重试" while an automatic retry is waiting: start it now. The
    /// normal deadline paths (drainResults / ApplicationHost tick) run it.
    pub fn retryAutomaticallyNow(self: *Workspace, key: OperationKey) !void {
        const job = self.pendingRetryJob(key) orelse return error.NoAutomaticRetry;
        job.automatic_retry_deadline_ns = @import("../../../platform/realtime.zig").monotonicNs();
        self.cx.requestRedraw();
    }

    /// "停止重试": drop the pending automatic retry and settle this attempt
    /// as failed. Owned creations publish the failure through drainResults
    /// exactly once; host-issued ones already reported it when scheduling.
    pub fn stopAutomaticRetry(self: *Workspace, key: OperationKey) !void {
        const job = self.pendingRetryJob(key) orelse return error.NoAutomaticRetry;
        const tab = self.findTicket(job.ticket) orelse return error.StaleConnection;
        job.automatic_retry_stopped = true;
        job.automatic_retry_deadline_ns = null;
        if (tab.owned_origin) job.drained = false else tab.failed = true;
        self.cx.requestRedraw();
    }

    /// "重新输入凭据": the next manual retry of this failed attempt prompts for
    /// the password / key passphrase instead of using the saved one.
    pub fn requestCredentialPrompt(self: *Workspace, key: OperationKey) !void {
        for (self.connect_jobs.items) |job| {
            if (job.operation_key == null or !job.operation_key.?.eql(key)) continue;
            job.credential_prompt_requested = true;
            return;
        }
        return error.StaleConnection;
    }
    pub fn cancelCredentialPrompt(self: *Workspace, key: OperationKey) void {
        for (self.connect_jobs.items) |job| if (job.operation_key != null and job.operation_key.?.eql(key)) {
            job.credential_prompt_requested = false;
        };
    }

    pub fn initialConnectionRetryDeadline(self: *Workspace, key: OperationKey) ?i128 {
        if (self.shutting_down) return null;
        for (self.connect_jobs.items) |job| {
            if (job.operation_key == null or !job.operation_key.?.eql(key) or job.cancelled.load(.acquire)) continue;
            const tab = self.findTicket(job.ticket) orelse return null;
            if (tab.closing or !job.drained or !job.resource_ledger.snapshot().released()) return null;
            return job.automatic_retry_deadline_ns;
        }
        return null;
    }

    fn replyHostKey(self: *Workspace, reply: auth_challenge.Reply) void {
        const job = self.host_key_job orelse return;
        const request = job.host_key_bridge.snapshot() orelse return;
        if (request.generation != self.host_key_generation or job.cancelled.load(.acquire)) return;
        const key = request.operation_key orelse return;
        if (job.operation_key == null or !job.operation_key.?.eql(key)) return;
        _ = job.host_key_bridge.decideScoped(.{ .key = key, .hop_index = request.hop_index, .request_id = request.generation }, reply);
    }

    /// Authentication belongs to the frozen operation, independent of the
    /// selected tab. Snapshots contain no answer secrets or worker pointers.
    pub fn pendingAuthentication(self: *Workspace) ?auth_challenge.Snapshot {
        self.auth_job = null;
        for (self.connect_jobs.items) |job| {
            if (job.cancelled.load(.acquire) or job.ready.load(.acquire) or self.findTicket(job.ticket) == null) continue;
            const key = job.operation_key orelse continue;
            if (job.host_key_bridge.snapshot()) |request| {
                if (request.operation_key == null or !request.operation_key.?.eql(key)) continue;
                const host = authenticationHost(job, request.hop_index) orelse {
                    job.cancelled.store(true, .release);
                    job.host_key_bridge.cancel();
                    job.auth_bridge.cancel();
                    continue;
                };
                if (host.user.len > 256) {
                    job.cancelled.store(true, .release);
                    job.host_key_bridge.cancel();
                    job.auth_bridge.cancel();
                    continue;
                }
                var challenge: auth_challenge.Snapshot = .{
                    .identity = .{ .key = key, .hop_index = request.hop_index, .request_id = request.generation },
                    .source_owner = request.source_owner,
                    .kind = if (request.status == .changed) .host_key_changed else .host_key_unknown,
                    .presentation = .protected_form,
                    .presentation_config_revision = job.config_snapshot.value.config_revision,
                    .expires_at_ns = null,
                    .port = request.port,
                    .host_len = request.host_len,
                    .user_len = host.user.len,
                };
                @memcpy(challenge.host[0..request.host_len], request.hostSlice());
                @memcpy(challenge.user[0..host.user.len], host.user);
                self.auth_job = job;
                return challenge;
            }
            const challenge = job.auth_bridge.snapshot() orelse continue;
            if (!challenge.identity.key.eql(key)) continue;
            switch (challenge.state) {
                .completed, .cancelled => continue,
                else => {},
            }
            self.auth_job = job;
            return challenge;
        }
        if (self.external_auth) |external| return external.pending(external.context);
        return null;
    }

    pub fn saveAuthenticationPassword(self: *Workspace, request: auth_challenge.Snapshot, password: []const u8) !void {
        if (request.kind != .password) return error.InvalidChallengeResponse;
        const frozen = self.authenticationHostFor(request.identity) orelse return error.StaleAuthentication;
        var transaction = try store.HostsTransaction.init(self.allocator, &self.registry);
        defer transaction.deinit();
        const candidate = &transaction.candidate.?;
        const index = candidate.indexOf(frozen.connection_id) orelse return error.InvalidHost;
        var host = candidate.hosts[index];
        if (host.auth_mode != .password or host.port != frozen.port or
            !std.mem.eql(u8, host.host, frozen.host) or !std.mem.eql(u8, host.user, frozen.user)) return error.RevisionConflict;
        const owner = host.owner();
        host.password = password;
        host.auth_mode = .password;
        _ = try candidate.update(owner, host);
        _ = try transaction.commitWithOptions(self.io, std.Io.Dir.cwd(), self.hosts_path, &self.registry, .{ .provider = self.credential_provider });
    }

    pub fn submitAuthentication(self: *Workspace, request: auth_challenge.RequestIdentity, reply: auth_challenge.Reply) !void {
        for (self.connect_jobs.items) |job| {
            const key = job.operation_key orelse continue;
            if (!key.eql(request.key)) continue;
            if (job.cancelled.load(.acquire) or job.ready.load(.acquire) or self.findTicket(job.ticket) == null) return error.StaleAuthentication;
            switch (reply) {
                .answers => try job.auth_bridge.submit(request, reply),
                else => if (!job.host_key_bridge.decideScoped(request, reply)) return error.StaleAuthentication,
            }
            self.cx.requestRedraw();
            return;
        }
        if (self.external_auth) |external| {
            try external.submit(external.context, request, reply);
            self.cx.requestRedraw();
            return;
        }
        return error.StaleAuthentication;
    }

    pub fn cancelAuthentication(self: *Workspace, request: auth_challenge.RequestIdentity) bool {
        for (self.connect_jobs.items) |job| {
            const key = job.operation_key orelse continue;
            if (!key.eql(request.key) or self.findTicket(job.ticket) == null) continue;
            const host_key = job.host_key_bridge.snapshot();
            const matches_host = if (host_key) |pending| pending.operation_key != null and pending.operation_key.?.eql(request.key) and pending.hop_index == request.hop_index and pending.generation == request.request_id else false;
            if (!matches_host and !job.auth_bridge.cancelRequest(request)) return false;
            job.cancelled.store(true, .release);
            job.host_key_bridge.cancel();
            job.auth_bridge.cancel();
            self.auth_job = null;
            self.cx.requestRedraw();
            return true;
        }
        if (self.external_auth) |external| {
            const accepted = external.cancel(external.context, request);
            if (accepted) self.cx.requestRedraw();
            return accepted;
        }
        return false;
    }

    fn authenticationHost(job: *ConnectJob, hop: usize) ?hosts_mod.HostConfig {
        if (hop < job.jump_snapshot.value.len) return job.jump_snapshot.value[hop];
        if (hop == job.jump_snapshot.value.len) return job.host_snapshot.value;
        return null;
    }

    pub fn authenticationHostFor(self: *Workspace, request: auth_challenge.RequestIdentity) ?hosts_mod.HostConfig {
        for (self.connect_jobs.items) |job| {
            if (job.operation_key == null or !job.operation_key.?.eql(request.key) or self.findTicket(job.ticket) == null) continue;
            if (job.cancelled.load(.acquire) or job.ready.load(.acquire)) return null;
            if (job.host_key_bridge.snapshot()) |current| {
                const key = current.operation_key orelse return null;
                const current_identity: auth_challenge.RequestIdentity = .{ .key = key, .hop_index = current.hop_index, .request_id = current.generation };
                if (!current_identity.eql(request)) return null;
            } else {
                const current = job.auth_bridge.snapshot() orelse return null;
                if (!current.identity.eql(request) or current.state == .completed or current.state == .cancelled) return null;
            }
            var host = authenticationHost(job, request.hop_index) orelse return null;
            // This accessor is display metadata, never a credential accessor.
            host.password = null;
            host.key_passphrase = null;
            host.totp_secret = null;
            return host;
        }
        if (self.external_auth) |external| return external.host(external.context, request);
        return null;
    }

    pub fn authenticationTotp(self: *Workspace, request: auth_challenge.RequestIdentity, now: @import("../../../proto/ssh/totp_prefill.zig").Time) !?@import("../../../proto/ssh/totp_prefill.zig").Suggestion {
        for (self.connect_jobs.items) |job| {
            if (job.operation_key == null or !job.operation_key.?.eql(request.key) or self.findTicket(job.ticket) == null) continue;
            if (job.cancelled.load(.acquire) or job.ready.load(.acquire)) return null;
            const current = job.auth_bridge.snapshot() orelse return null;
            if (!current.identity.eql(request)) return null;
            const host = authenticationHost(job, request.hop_index) orelse return null;
            return @import("../../../proto/ssh/totp_prefill.zig").suggest(&current, request, host, job.config_snapshot.value.ssh.totp_autofill, now);
        }
        if (self.external_auth) |external| if (external.totp) |propose| return propose(external.context, request, now);
        return null;
    }

    pub fn authenticationParent(self: *Workspace, request: auth_challenge.RequestIdentity) ?*ui.Node {
        for (self.connect_jobs.items) |job| {
            if (job.operation_key == null or !job.operation_key.?.eql(request.key)) continue;
            return (self.findTicket(job.ticket) orelse return null).root;
        }
        if (self.external_auth) |external| return external.parent(external.context, request);
        return null;
    }

    pub fn authenticationHostKey(self: *Workspace, request: auth_challenge.RequestIdentity) ?host_key_confirmation.Request {
        for (self.connect_jobs.items) |job| {
            if (job.operation_key == null or !job.operation_key.?.eql(request.key)) continue;
            if (self.findTicket(job.ticket) == null or job.cancelled.load(.acquire)) return null;
            const observed = job.host_key_bridge.lastSnapshot() orelse return null;
            const key = observed.operation_key orelse return null;
            if (!key.eql(request.key) or observed.hop_index != request.hop_index) return null;
            return observed;
        }
        if (self.external_auth) |external| return external.host_key(external.context, request);
        return null;
    }

    fn pollHostKeyConfirm(self: *Workspace) void {
        if (self.authentication_ui_ready) {
            if (self.host_key_job != null) self.hideHostKeyConfirm();
            return;
        }
        if (self.host_key_job) |job| {
            if (job.host_key_bridge.pending() and !job.cancelled.load(.acquire)) return;
            self.hideHostKeyConfirm();
        }
        for (self.connect_jobs.items) |job| {
            const request = job.host_key_bridge.snapshot() orelse continue;
            if (job.cancelled.load(.acquire) or self.findTicket(job.ticket) == null) {
                job.host_key_bridge.cancel();
                continue;
            }
            self.mountHostKeyConfirm() catch {
                job.host_key_bridge.cancel();
                continue;
            };
            var buffer: [1024]u8 = undefined;
            const message = if (request.status == .changed)
                std.fmt.bufPrint(&buffer, "警告：服务器 {s}:{d} 的主机密钥已变化\n当前主机指纹\n{s} {s}\n核对指纹后，点击替换主机密钥", .{
                    request.hostSlice(), request.port, request.algorithmSlice(), request.fingerprintSlice(),
                }) catch "主机密钥已变化"
            else
                std.fmt.bufPrint(&buffer, "服务器 {s}:{d} 的身份尚未记录\n主机指纹\n{s} {s}", .{
                    request.hostSlice(), request.port, request.algorithmSlice(), request.fingerprintSlice(),
                }) catch "无法显示主机指纹";
            self.host_key_detail.?.setTextContent(self.cx.allocator, message) catch {
                job.host_key_bridge.cancel();
                continue;
            };
            const changed = request.status == .changed;
            self.host_key_detail.?.setTextColor(if (changed) ui.Color.rgb(0xDC, 0x4C, 0x3F) else ui.Color.rgb(0x47, 0x55, 0x69));
            if (self.host_key_changed_button) |button| button.setDisplay(if (changed) .flex else .none);
            self.host_key_job = job;
            self.host_key_generation = request.generation;
            self.cx.dispatcher.cancelScrollGesture();
            self.host_key_open.?.set(true);
            // Default focus on the safe choice: Enter never trusts a key.
            self.cx.setFocus(self.host_key_reject.?);
            self.cx.scheduleRedrawAfterNs(0);
            return;
        }
    }

    // ── Close confirmation dialog ────────────────────────────────────

    /// One-shot mount of the close confirmation: the shared `confirm(spec)` (zenit `ConfirmDialog`,
    /// OverlayHost `dialog` rule: focus on 取消, Esc / × / scrim = 取消). The consequence goes in the
    /// message (glossary §4: “关闭页签会断开此会话。”), the risk rows in its slot. Hidden right away;
    /// showing it later only rewrites the dynamic texts and opens it.
    fn mountCloseConfirm(self: *Workspace) !void {
        if (self.confirm_root != null) return;
        const p = self.palette;
        const cx = self.cx;
        const allocator = cx.allocator;

        const open = try self.scope.createSignal(bool, false);
        const message = try self.scope.createText("关闭页签会断开此会话。", .{});
        const dialog = try confirm_ui.confirm(self.scope, cx, .{
            .open = ui.split(open, cx.on(Workspace, self, closeConfirmOpenChanged)),
            .title = "关闭页签？",
            .message = message,
            .action = confirm_ui.label(.close, "页签"),
            // The accept path takes the card down itself (hideCloseConfirm) before closing the tab;
            // a close proposal through the split would read as 取消.
            .close_on_confirm = false,
            .on_confirm = cx.on(Workspace, self, onConfirmForceClose),
            .test_id = "session.close.confirm",
            .test_ids = .{ .message = "session.close.message", .cancel = "session.close.cancel", .confirm = "session.close.accept" },
        });
        if (!dialog.modal.portaled) try self.terminal_area.appendChild(allocator, dialog.modal.overlay);

        // Risk rows (category → detail) — the mockup-close-confirm rule list: 传输 / AI / SOCKS5 /
        // 历史 plus the live-session SSH row. setRiskDetail rewrites details by category at show
        // time; rows without live state keep the design-text default.
        const risk_specs = [_]struct { category: []const u8, detail: []const u8 }{
            .{ .category = "SSH", .detail = "" },
            .{ .category = "传输", .detail = "关闭将暂停未完成的传输" },
            .{ .category = "AI", .detail = "关闭将中止正在执行的命令" },
            .{ .category = "SOCKS5", .detail = "关闭将停止代理并断开连接" },
            .{ .category = "历史", .detail = "已保存的记录可从「查看历史」回放" },
        };
        const rows = try ui.box(cx, .{
            .width = .fill(),
            .direction = .column,
        }, .{});
        for (risk_specs) |spec| {
            const row = try ui.box(cx, .{
                .width = .fill(),
                .direction = .row,
                .align_items = .center,
                .gap = 10,
                .padding = .{ .left = 0, .right = 0, .top = 6, .bottom = 6 },
            }, .{});
            const category = try ui.box(cx, .{ .width = .{ .px = 64 }, .flex_shrink = 0 }, .{});
            try category.appendChild(allocator, try ui.text(cx, spec.category, .{
                .font_size = 12,
                .font_weight = 600,
                .color = p.fg,
            }));
            try row.appendChild(allocator, category);
            const detail = try ui.box(cx, .{ .width = .fill() }, .{});
            const detail_text = try ui.text(cx, spec.detail, .{
                .font_size = 12,
                .color = p.fg_secondary,
                .wrap = .word,
            });
            try detail.appendChild(allocator, detail_text);
            try row.appendChild(allocator, detail);
            try rows.appendChild(allocator, row);
            try self.confirm_risk_rows.append(self.allocator, .{ .category = spec.category, .detail_node = detail_text, .row_node = row });
        }
        try dialog.content.appendChild(allocator, rows);

        self.confirm_open = open;
        self.confirm_root = dialog.modal.overlay;
        self.confirm_card = dialog.modal.dialog;
        self.confirm_cancel = dialog.cancel;
        self.confirm_message = message;
    }

    /// Esc on the close confirmation proposes closing it: same as 取消.
    fn closeConfirmOpenChanged(self: *Workspace, open: bool) void {
        if (!open and self.confirming_id != null) self.onCancelConfirm();
    }

    /// Puts the confirmation card up for `index` (live session): records the
    /// pending tab, rewrites the dynamic texts (title + SSH risk row),
    /// opens the Modal and moves keyboard focus onto 取消.
    fn showCloseConfirm(self: *Workspace, index: usize) void {
        self.cx.dispatcher.cancelScrollGesture();
        if (index >= self.tabs.items.len) return;
        const open = self.confirm_open orelse return;
        const tab = self.tabs.items[index];
        // A repeated requestCloseTab while the card is up simply overwrites
        // the pending index; the texts re-render for the new tab.
        self.confirming_tab = index;
        self.confirming_id = self.tabs.items[index].tab_id;
        applog.debug(.workspace, "close confirm shown for tab {d}", .{index});
        var message_buffer: [192]u8 = undefined;
        var message_writer = std.Io.Writer.fixed(&message_buffer);
        message_writer.print("关闭页签会断开此会话（{s}）。仍有任务运行时，关闭会影响以下内容。", .{self.shownName(tab)}) catch {};
        if (self.confirm_message) |message| message.set(message_writer.buffered());
        if (tab.host_snapshot) |snapshot| {
            const host = snapshot.value;
            var detail_buffer: [160]u8 = undefined;
            var detail_writer = std.Io.Writer.fixed(&detail_buffer);
            detail_writer.print("与 {s} 的连接将断开", .{host.host}) catch {};
            self.setRiskDetail("SSH", detail_writer.buffered());
        }
        self.setRiskVisible("SSH", !tab.local);
        // 传输/AI/SOCKS5 rows: hidden until those subsystems report live
        // state for the pending tab (wiring lands with their integration;
        // the rows mount with the design text so no fallback text is
        // invented here).
        const risk = if (self.close_bridge.risk) |callback| callback(self.close_bridge.context, tab.id) else CloseRisk{};
        self.setRiskVisible("传输", risk.transfer);
        self.setRiskVisible("AI", risk.ai_write);
        self.setRiskVisible("SOCKS5", risk.socks);
        if (risk.transfer) self.setRiskDetail("传输", "尚有未完成任务，关闭将暂停并保留续传数据");
        if (risk.ai_write) self.setRiskDetail("AI", "写命令执行中，关闭将中止并清理远端进程");
        if (risk.socks) self.setRiskDetail("SOCKS5", "正在监听，关闭将释放代理连接与端口");
        // Focus on the safe choice (取消) and its return are the native Modal's (OverlayHost `dialog`).
        open.set(true);
        self.cx.requestRedraw();
    }

    /// Takes the card down and clears the pending index. Does not touch
    /// focus — callers decide where keyboard input goes next.
    fn hideCloseConfirm(self: *Workspace) void {
        self.confirming_tab = null;
        self.confirming_id = null;
        if (self.confirm_open) |open| open.set(false);
        self.cx.requestRedraw();
    }

    /// Rewrites one risk row's detail line, matched by category label.
    fn setRiskDetail(self: *Workspace, category: []const u8, detail: []const u8) void {
        for (self.confirm_risk_rows.items) |row| {
            if (!std.mem.eql(u8, row.category, category)) continue;
            row.detail_node.setTextContent(self.allocator, detail) catch return;
            row.detail_node.markRenderDirty();
            return;
        }
    }

    /// Shows/hides one risk row. 传输/AI/SOCKS5 rows stay hidden until the
    /// corresponding subsystem reports live state for the pending tab
    /// (they mount with the mockup design text so the card matches the
    /// png the moment real data lands in setRiskDetail).
    fn setRiskVisible(self: *Workspace, category: []const u8, visible: bool) void {
        for (self.confirm_risk_rows.items) |row| {
            if (!std.mem.eql(u8, row.category, category)) continue;
            row.row_node.setDisplay(if (visible) .flex else .none);
            return;
        }
    }

    /// Confirm-card "取消": keep the tab, take the card down.
    fn onCancelConfirm(self: *Workspace) void {
        self.abortCloseBatch();
        applog.debug(.workspace, "close confirm: cancelled", .{});
        // 焦点回到打开确认框前的位置（原生 Modal 的焦点归还，OverlayHost `dialog`）。
        self.hideCloseConfirm();
    }

    /// Confirm-card "关闭页签": the user accepted the risk rows — tear the
    /// pending tab down for real.
    fn onConfirmForceClose(self: *Workspace) void {
        const id = self.confirming_id orelse return;
        const index = self.tabIndexById(id) orelse {
            self.hideCloseConfirm();
            return;
        };
        applog.info(.workspace, "close confirm: force closing tab {d}", .{index});
        self.hideCloseConfirm();
        self.forceCloseTab(index);
        self.continueCloseOthers();
    }

    // ── Session lifecycle ────────────────────────────────────────────

    /// Opens (or focuses) a session tab for the host. The terminal surface and
    /// tab appear immediately with a "连接中" state; the SSH connection then
    /// proceeds on a background thread and finishes back on the UI thread.
    /// Saved connections are configurations, not running sessions. Every
    /// activation creates a new session with its own immutable snapshot.
    pub fn openSession(self: *Workspace, index: usize) !void {
        try self.newSession(index);
    }

    fn validateGroupCreation(self: *Workspace, target: identity.TabId) !void {
        if (self.shutting_down or self.model.window_close != null) return error.WorkspaceClosed;
        if (!self.canGroupTarget(target)) return error.StaleSession;
        if (self.pending_tab_drop != null or self.pending_host_group_drop != null) return error.GroupingBusy;
    }
    fn groupCreatedSession(self: *Workspace, before: usize, target: identity.TabId) !void {
        if (self.tabs.items.len != before + 1) return error.SessionNotCreated;
        self.pending_tab_drop = .{ .source = self.tabs.items[before].tab_id, .target = target };
        self.cx.requestRedraw();
    }
    /// Create through the existing provider, then use the same deferred AI
    /// settlement/membership transaction as a tab drop. The original session
    /// remains standalone if creation fails.
    pub fn openHostInGroup(self: *Workspace, index: usize, target: identity.TabId) !void {
        try self.validateGroupCreation(target);
        const before = self.tabs.items.len;
        const ambient = self.creation_group;
        self.creation_group = null;
        defer self.creation_group = ambient;
        try self.newSession(index);
        try self.groupCreatedSession(before, target);
    }
    pub fn duplicateSessionIntoGroup(self: *Workspace, index: usize) !void {
        if (index >= self.tabs.items.len) return error.InvalidTab;
        const target = self.tabs.items[index].tab_id;
        try self.validateGroupCreation(target);
        const before = self.tabs.items.len;
        try self.duplicateSession(index, false);
        try self.groupCreatedSession(before, target);
    }

    /// Always creates a distinct session for this asset, even if already open.
    pub fn newSession(self: *Workspace, index: usize) !void {
        if (index >= self.registry.hosts.len) return error.InvalidHost;
        // 协议插件被禁用（Q5）：不可连接（侧栏与右键菜单已不提供入口，这里再挡一次）。
        if (self.disabledPlugin(self.registry.hosts[index]) != null) return error.PluginDisabled;
        try self.identities.appendHosts(self.allocator, self.registry.hosts.len);
        try self.createSession(self.registry.hosts[index], self.hostId(index).?, index, "");
        self.recent_connections.record(self.registry.hosts[index].connection_id, 0);
    }

    /// The saved revision supplies every routing and policy field. Secrets
    /// entered for this connection are copied by SessionHost, never persisted.
    pub fn newSessionWithCredentials(self: *Workspace, owner: identity.AssetOwner, password: ?[]const u8, key_passphrase: ?[]const u8) !void {
        var host = try self.registry.get(owner);
        if (password) |value| host.password = value;
        if (key_passphrase) |value| host.key_passphrase = value;
        const index = self.registry.indexOf(owner.id) orelse return error.InvalidHost;
        try self.identities.appendHosts(self.allocator, self.registry.hosts.len);
        try self.createSession(host, self.hostId(index).?, index, "");
        self.recent_connections.record(owner.id, 0);
    }

    /// The session factory owns a frozen copy. A temporary direct endpoint
    /// never enters the asset registry or consumes an asset identity.
    pub fn newTemporarySession(self: *Workspace, host: hosts_mod.HostConfig) !void {
        if (self.shutting_down or self.model.window_close != null) return error.WorkspaceClosed;
        if (@backingInt(host.connection_id) != 0 or host.protocol != .ssh or host.route.len != 0 or host.jump_chain.len != 0) return error.InvalidTemporaryTarget;
        try host.validate();
        try self.createSession(host, 0, removed_host_index, "");
    }

    pub fn isLocalSession(self: *const Workspace, id: SessionId) bool {
        const tab = self.sessionTab(id) orelse return false;
        return tab.local;
    }

    pub fn newLocalSession(self: *Workspace, cwd: ?[]const u8) !void {
        if (self.shutting_down or self.model.window_close != null) return error.WorkspaceClosed;
        const create = self.session_bridge.create_local orelse return error.LocalAdapterUnavailable;
        try create(self.session_bridge.context, cwd);
    }

    pub fn retryLocalSession(self: *Workspace, id: SessionId) !void {
        if (self.shutting_down or self.model.window_close != null) return error.WorkspaceClosed;
        const tab = self.sessionTab(id) orelse return error.InvalidTab;
        if (!tab.local or tab.closing or (tab.local_state != .failed and tab.local_state != .exited)) return error.LifecycleDoesNotAllowRetry;
        const retry = self.session_bridge.retry_local orelse return error.LocalAdapterUnavailable;
        try retry(self.session_bridge.context, id);
        if (self.active_tab) |index| if (self.tabs.items[index] == tab) tab.terminal.?.focus();
    }

    /// Presentation only; SessionHost has already assigned this exact owner.
    /// No HostConfig or process creation is allowed in this path.
    fn applyTerminalTypography(self: *Workspace, terminal: *TerminalViewNode) !void {
        if (self.terminal_typography_resolver) |resolve| return resolve(terminal, self.app_config.ui);
        try terminal.setTypographyFamily(self.app_config.ui.font_size, self.app_config.ui.line_height, fontWeight(self.app_config.ui.font_weight), self.app_config.ui.font_family, if (self.font_family_resolver) |resolve| resolve(self.app_config.ui.font_family) else 0);
    }

    pub fn createLocalSessionDirect(self: *Workspace, handle: identity.SessionHandle) !SessionId {
        if (self.shutting_down) return error.WorkspaceClosed;
        try self.tabs.ensureUnusedCapacity(self.allocator, 1);
        try self.startPollLoop();
        const tab = try self.allocator.create(SessionTab);
        errdefer self.allocator.destroy(tab);
        var terminal = try TerminalViewNode.mount(self.cx);
        terminal.setTerminalTakeoverHandler(self.terminal_takeover_handler);
        var owned_pane: ?*ui.Node = null;
        var local_scope: ?*ui.Scope = null;
        var terminal_attached = false;
        errdefer {
            if (local_scope) |scope| scope.dispose();
            terminal.releaseBuffers(self.cx);
            if (owned_pane) |pane| self.cx.destroyDetached(pane);
            if (!terminal_attached) self.cx.destroyDetached(terminal.root);
        }
        local_scope = try self.scope.childScope();
        terminal.completion_enabled = self.app_config.completion.enabled;
        terminal.keymap = &self.app_config.keys;
        terminal.palette_observer = self.command_bridge;
        terminal.input_observer = self.input_bridge;
        terminal.setThemeColors(self.palette.fg, self.palette.border, self.palette.accent);
        try self.applyTerminalTypography(&terminal);
        terminal.setCursorStyle(cursorStyle(self.app_config.ui.cursor_style));
        terminal.setTimestampGutter(self.app_config.ui.timestamp_gutter);
        try terminal.setInputLineHighlight(self.app_config.ui.input_line_highlight);
        const pane = try ui.box(self.cx, local_styles.pane(), .{});
        owned_pane = pane;
        terminal.root.setStyleInline(self.allocator, .{ .width = .fill(), .height = .fill(), .flex = 1, .min_height = 0 });
        const ticket = self.identities.newTicket();
        tab.* = .{ .id = ticket.session_id, .tab_id = try tab_ids.allocate(), .content_owner = .{ .session = handle }, .card_type = self.resolveCardType(&card_placement.terminal_def), .generation = handle.generation, .host_id = 0, .host_index = removed_host_index, .host_snapshot = null, .root = pane, .terminal = terminal, .local = true, .local_scope = local_scope };
        tab.setTitle(tab_naming.home_label);
        try self.mountLocalBanner(tab);
        try pane.appendChild(self.allocator, terminal.root);
        terminal_attached = true;
        try tab.terminal.?.attachSearch(local_scope.?);
        try self.installTabModel(tab);
        errdefer self.model.completeClose(tab.tab_id, tab.content_owner) catch {};
        try self.terminal_area.appendChild(self.allocator, pane);
        self.appendTabAssumeCapacity(tab);
        self.updateLocalState(tab.id, .starting, "正在启动 zsh…");
        self.rebuildTabBar() catch {};
        self.selectTab(self.tabs.items.len - 1);
        return tab.id;
    }

    /// Mount any native renderer in the existing content area and tab model.
    /// The provider receives only its slot, owned scope, identity and facades.
    /// UI-only detach for a transferred renderer. It never sends an owner close.
    pub fn validatePluginTransfer(self: *Workspace, owner: identity.SessionHandle, id: SessionId) !void {
        if (self.shutting_down) return error.WorkspaceClosed;
        const tab = self.sessionTab(id) orelse return error.UnknownSession;
        // 窗口移交读卡片类型（PLUGIN_ARCH_PLAN 2.5.3）：只有声明 `supports_window_transfer` 的会话卡片
        // （插件渲染器呈现的 tab）能整体移交；与改动前“有插件渲染器、没有终端也没有运行时”逐项等价
        // （`card_placement` 的等价性单测）。
        if (tab.content_owner != .session or !tab.content_owner.session.eql(owner) or !card_placement.canTransferWindow(tab.card_type, true, tab.closing)) return error.ContentTransferUnavailable;
        if (self.model.order_revision == std.math.maxInt(u64)) return error.RevisionExhausted;
    }
    pub fn discardTransferredPlugin(self: *Workspace, owner: identity.SessionHandle, id: SessionId) void {
        self.validatePluginTransfer(owner, id) catch unreachable;
        const tab = self.sessionTab(id).?;
        const index = self.tabIndexById(tab.tab_id).?;
        self.model.completeClose(tab.tab_id, tab.content_owner) catch unreachable;
        if (self.rename_session == tab.id) _ = self.cancelRenameTab();
        if (tab.root.parent) |parent| self.cx.detachChild(parent, tab.root);
        tab.plugin_renderer.?.vtable.unmount(tab.plugin_renderer.?.context);
        tab.setPluginRenderer(null);
        tab.transfer_trays = .{ null, null };
        if (tab.file_scope) |scope| scope.dispose();
        tab.file_scope = null;
        self.cx.destroyDetached(tab.root);
        if (tab.plugin_protocol_id.len != 0) self.allocator.free(tab.plugin_protocol_id);
        self.allocator.destroy(tab);
        self.removeTabAt(index);
        self.setActiveTab(if (self.model.active) |active| self.tabIndexById(active) else null);
        if (self.tabs.items.len == 0) {
            self.status("未连接");
            self.empty_state.setDisplay(.flex);
            self.refreshSavedConnections() catch {};
        }
        self.rebuildTabBar() catch {};
        self.rebuildSidebar() catch {};
        if (self.model.active) |active| self.presentTabId(active, .take);
        self.cx.requestRedraw();
    }

    /// Replace a released generation in the same tab after a registered plugin
    /// retries. The new renderer is prepared before replacing the old owner.
    pub fn remountPluginSession(self: *Workspace, id: SessionId, expected: identity.SessionHandle, owner: identity.SessionHandle, value: envelopes.Envelope, renderer: plugin_ui.RendererDefinition) !void {
        const tab = self.sessionTab(id) orelse return error.StaleSession;
        if (tab.closing or tab.plugin_renderer == null or !tab.content_owner.eql(.{ .session = expected }) or expected.session_id != owner.session_id or expected.generation >= owner.generation) return error.StaleSession;
        const mount_renderer = renderer.mount orelse return error.ContentRendererUnavailable;
        const scope = try self.scope.childScope();
        errdefer scope.dispose();
        const pane = try ui.box(self.cx, local_styles.pane(), .{});
        errdefer self.cx.destroyDetached(pane);
        pane.meta.ownership.meta.test_id = "workspace.plugin.content";
        const services = if (self.content_services) |factory| try factory.create(factory.context, owner) else plugin_ui.ContentServices{};
        const instance = try mount_renderer(renderer.context, .{ .cx = self.cx, .scope = scope, .slot = pane, .owner = owner, .connection = value, .content_context = services.content_context, .frame_sink = services.frame_sink, .service_access = services.service_access });
        errdefer instance.vtable.unmount(instance.context);
        try self.terminal_area.appendChild(self.allocator, pane);
        errdefer self.cx.detachChild(self.terminal_area, pane);
        try self.model.replaceOwner(tab.tab_id, tab.content_owner, .{ .session = owner });
        const old_root = tab.root;
        const old_scope = tab.file_scope;
        const old_renderer = tab.plugin_renderer.?;
        tab.root = pane;
        tab.file_scope = scope;
        tab.setPluginRenderer(instance);
        tab.setContentOwner(.{ .session = owner });
        tab.generation = owner.generation;
        tab.content_ready = true;
        tab.failed = false;
        tab.setTitle(value.name);
        old_renderer.vtable.unmount(old_renderer.context);
        if (old_root.parent) |parent| self.cx.detachChild(parent, old_root);
        if (old_scope) |previous| previous.dispose();
        self.cx.destroyDetached(old_root);
        if (self.model.active) |active| self.presentTabId(active, .take);
        self.cx.requestRedraw();
    }

    /// Saved plugin tabs intentionally have no legacy HostSnapshot. Resolve
    /// their asset by its stable identity, as for terminal/file snapshots.
    pub fn savedConnectionForTab(self: *Workspace, index: usize) ?identity.AssetOwner {
        if (index >= self.tabs.items.len) return null;
        const id = self.tabs.items[index].sourceConnectionId() orelse return null;
        const asset_index = self.registry.indexOf(id) orelse return null;
        return self.registry.hosts[asset_index].owner();
    }

    pub const ConnectionTabs = struct { count: usize = 0, first_index: ?usize = null };
    pub fn connectionTabs(self: *const Workspace, id: identity.ConnectionId) ConnectionTabs {
        var result: ConnectionTabs = .{};
        if (@backingInt(id) == 0) return result;
        for (self.tabs.items, 0..) |tab, index| if (tab.sourceConnectionId()) |source| {
            if (source != id) continue;
            result.count += 1;
            if (result.first_index == null) result.first_index = index;
        };
        return result;
    }

    /// Opaque plugin payloads do not have legacy user/host/port fields. Use
    /// their public name instead of inventing an SSH endpoint such as @:22.
    pub fn assetActionEndpoint(self: *const Workspace, allocator: std.mem.Allocator, host: hosts_mod.HostConfig) ![]u8 {
        if (host.isLegacy()) return std.fmt.allocPrint(allocator, "{s}@{s}:{d}", .{ host.user, host.host, host.port });
        return allocator.dupe(u8, if (self.plugins.find(host.protocolId())) |manifest| manifest.display_name else host.protocolId());
    }

    pub fn createPluginSession(self: *Workspace, owner: identity.SessionHandle, value: envelopes.Envelope, renderer: plugin_ui.RendererDefinition) !SessionId {
        if (self.shutting_down) return error.WorkspaceClosed;
        const mount_renderer = renderer.mount orelse return error.ContentRendererUnavailable;
        try self.tabs.ensureUnusedCapacity(self.allocator, 1);
        const tab = try self.allocator.create(SessionTab);
        errdefer self.allocator.destroy(tab);
        const scope = try self.scope.childScope();
        errdefer scope.dispose();
        const pane = try ui.box(self.cx, local_styles.pane(), .{});
        errdefer self.cx.destroyDetached(pane);
        pane.meta.ownership.meta.test_id = "workspace.plugin.content";
        const protocol_id = try self.allocator.dupe(u8, value.protocol_id);
        errdefer self.allocator.free(protocol_id);
        const services = if (self.content_services) |factory| try factory.create(factory.context, owner) else plugin_ui.ContentServices{};
        const instance = try mount_renderer(renderer.context, .{ .cx = self.cx, .scope = scope, .slot = pane, .owner = owner, .connection = value, .content_context = services.content_context, .frame_sink = services.frame_sink, .service_access = services.service_access });
        errdefer instance.vtable.unmount(instance.context);
        const ticket = self.identities.newTicket();
        tab.* = .{ .id = ticket.session_id, .tab_id = try tab_ids.allocate(), .content_owner = .{ .session = owner }, .card_type = self.pluginCardType(protocol_id), .generation = owner.generation, .host_id = @backingInt(value.id), .host_index = self.registry.indexOf(value.id) orelse removed_host_index, .host_snapshot = null, .root = pane, .file_scope = scope, .plugin_renderer = instance, .plugin_protocol_id = protocol_id, .content_ready = true };
        tab.setTitle(value.name);
        try self.installTabModel(tab);
        errdefer self.model.completeClose(tab.tab_id, tab.content_owner) catch {};
        try self.terminal_area.appendChild(self.allocator, pane);
        self.appendTabAssumeCapacity(tab);
        self.rebuildTabBar() catch {};
        self.selectTab(self.tabs.items.len - 1);
        return tab.id;
    }

    /// Attach a real file workspace without constructing VT, PTY or a shell.
    /// Ownership of content/scope transfers only after this method succeeds.
    pub fn createFileSessionDirect(self: *Workspace, handle: identity.SessionHandle, host: hosts_mod.HostConfig, host_id: HostId, source_index: usize, content: *ui.Node, content_scope: *ui.Scope) !SessionId {
        if (self.shutting_down) return error.WorkspaceClosed;
        if (host.protocol != .sftp) return error.WrongPlugin;
        if (content.parent != null) return error.ContentAlreadyAttached;
        try self.tabs.ensureUnusedCapacity(self.allocator, 1);
        const tab = try self.allocator.create(SessionTab);
        errdefer self.allocator.destroy(tab);
        var snapshot = try HostSnapshot.init(self.allocator, host);
        errdefer snapshot.deinit();
        const ticket = self.identities.newTicket();
        tab.* = .{ .id = ticket.session_id, .tab_id = try tab_ids.allocate(), .content_owner = .{ .session = handle }, .card_type = self.resolveCardType(&card_placement.file_def), .generation = handle.generation, .host_id = host_id, .host_index = source_index, .host_snapshot = snapshot, .root = content, .file_scope = content_scope };
        tab.setTitle(host.name);
        try self.installTabModel(tab);
        errdefer self.model.completeClose(tab.tab_id, tab.content_owner) catch {};
        content.behavior.interaction.focusable = true;
        try self.terminal_area.appendChild(self.allocator, content);
        self.appendTabAssumeCapacity(tab);
        self.rebuildTabBar() catch {};
        self.selectTab(self.tabs.items.len - 1);
        return tab.id;
    }

    fn mountLocalBanner(self: *Workspace, tab: *SessionTab) !void {
        const banner = try ui.box(self.cx, local_styles.banner(true), .{});
        try tab.root.appendChild(self.allocator, banner);
        tab.local_banner = banner;
        banner.meta.ownership.meta.test_id = "local.notice";
        tab.local_spinner = try ui.widgets.Spinner(.{ .size = 16, .stroke_width = 2, .color = app_theme.current().fg_2 }).mount(tab.local_scope.?, self.cx);
        try banner.appendChild(self.allocator, tab.local_spinner.?);
        tab.local_ended_icon = try ui.iconTint(self.cx, ui.icons.get("terminal").?, app_theme.current().fg_2, local_styles.icon());
        try banner.appendChild(self.allocator, tab.local_ended_icon.?);
        tab.local_failure_icon = try ui.iconTint(self.cx, ui.icons.circle_alert, app_theme.current().danger, local_styles.icon());
        try banner.appendChild(self.allocator, tab.local_failure_icon.?);
        const copy = try ui.box(self.cx, local_styles.copy(), .{});
        copy.behavior.interaction.a11y = .{ .role = .status, .live = "polite" };
        try banner.appendChild(self.allocator, copy);
        tab.local_message = try ui.text(self.cx, "正在启动本地终端…", local_styles.title());
        tab.local_message.?.meta.ownership.meta.test_id = "local.notice.title";
        try copy.appendChild(self.allocator, tab.local_message.?);
        tab.local_detail = try ui.text(self.cx, "", local_styles.detail());
        tab.local_detail.?.meta.ownership.meta.test_id = "local.notice.detail";
        try copy.appendChild(self.allocator, tab.local_detail.?);
        const cell = try self.allocator.create(ClickCtx);
        var adopted = false;
        errdefer if (!adopted) self.allocator.destroy(cell);
        cell.* = .{ .workspace = self, .index = 0, .session_id = tab.id };
        // Banner callbacks live with the pane, not the rebuilt tab-strip pool.
        try tab.local_scope.?.adoptResource(@ptrCast(cell), struct {
            fn release(raw: *anyopaque, allocator: std.mem.Allocator) void {
                allocator.destroy(@as(*ClickCtx, @ptrCast(@alignCast(raw))));
            }
        }.release);
        adopted = true;
        const cancel = try ui.widgets.Button(.{ .label = "取消启动", .variant = .secondary, .size = .sm, .on_click = self.cx.on(ClickCtx, cell, cancelLocalStart) }).mount(tab.local_scope.?, self.cx);
        cancel.meta.ownership.meta.test_id = "local.start.cancel";
        tab.local_cancel = cancel;
        try banner.appendChild(self.allocator, cancel);
        const close = try ui.widgets.Button(.{ .label = "关闭页签", .variant = .secondary, .size = .sm, .on_click = self.cx.on(ClickCtx, cell, cancelLocalStart) }).mount(tab.local_scope.?, self.cx);
        close.meta.ownership.meta.test_id = "local.ended.close";
        tab.local_close = close;
        try banner.appendChild(self.allocator, close);
        const retry = try ui.widgets.Button(.{ .label = "重试启动", .variant = .primary, .size = .sm, .on_click = self.cx.on(ClickCtx, cell, retryLocalStart) }).mount(tab.local_scope.?, self.cx);
        retry.meta.ownership.meta.test_id = "local.start.retry";
        tab.local_retry = retry;
        try banner.appendChild(self.allocator, retry);
        const reconnect = try ui.widgets.Button(.{ .label = "重新连接", .variant = .primary, .size = .sm, .on_click = self.cx.on(ClickCtx, cell, retryLocalStart) }).mount(tab.local_scope.?, self.cx);
        reconnect.meta.ownership.meta.test_id = "local.ended.reconnect";
        tab.local_reconnect = reconnect;
        try banner.appendChild(self.allocator, reconnect);
    }

    fn cancelLocalStart(cell: *ClickCtx) void {
        const self = cell.workspace;
        const index = self.tabIndex(cell.session_id orelse return) orelse return;
        // This explicit startup action cancels the creating operation. A late
        // click after startup completed uses the ordinary risk-gated close.
        if (self.tabs.items[index].local_state == .starting) {
            self.forceCloseTab(index);
            return;
        }
        self.requestCloseTab(index);
    }
    fn retryLocalStart(cell: *ClickCtx) void {
        cell.workspace.retryLocalSession(cell.session_id orelse return) catch |err| cell.workspace.statusFailure(@errorName(err));
    }

    pub fn userInputRevision(self: *Workspace, handle: identity.SessionHandle) ?u64 {
        for (self.tabs.items) |tab| {
            if (tab.isCard() or tab.content_owner != .session or !tab.content_owner.session.eql(handle)) continue;
            const view = if (tab.terminal) |*terminal_view| terminal_view else return null;
            if (view.terminal_surface) |surface| return if (surface.owner.eql(handle)) surface.user_input_revision else null;
            return view.user_input_revision;
        }
        return null;
    }
    pub fn setTerminalTakeoverHandler(self: *Workspace, handler: ?@import("../../terminal/view/terminal_view.zig").TakeoverHandler) void {
        self.terminal_takeover_handler = handler;
        for (self.tabs.items) |tab| if (tab.terminal) |*view| view.setTerminalTakeoverHandler(handler);
    }
    pub fn bindLocalTerminal(self: *Workspace, id: SessionId, handle: identity.SessionHandle, service: terminal_service.Service) !void {
        const tab = self.sessionTab(id) orelse return error.InvalidTab;
        if (!tab.local or !tab.content_owner.eql(.{ .session = handle })) return error.StaleSession;
        if (tab.local_bound) return;
        tab.terminal.?.setTerminalMenuHandler(.{ .context = self, .request = onTerminalServiceMenu, .secondary = onTerminalServiceContext });
        try tab.terminal.?.bindTerminalService(service);
        tab.local_bound = true;
    }

    fn onTerminalServiceMenu(raw: ?*anyopaque, handle: identity.SessionHandle, x: f32, y: f32) void {
        const self: *Workspace = @ptrCast(@alignCast(raw orelse return));
        const index = self.terminalMenuTab(handle) orelse return;
        self.menu_bridge.fireTab(.terminal_middle_click, index, self.tabs.items.len > 1, .{ .x = x, .y = y, .w = 0, .h = 0 });
    }

    /// Terminal right click (design-r3 B1): opens the native right-click menu at the pointer
    /// unless 设置 › 终端与工作区 › 右键行为 is "直接粘贴". Returning false makes the terminal paste
    /// the clipboard itself (the previous behavior), so the choice is read live at click time.
    fn onTerminalServiceContext(raw: ?*anyopaque, handle: identity.SessionHandle, x: f32, y: f32) bool {
        const self: *Workspace = @ptrCast(@alignCast(raw orelse return false));
        if (self.app_config.ui.terminal_right_click == .paste or self.menu_bridge.fire == null) return false;
        const index = self.terminalMenuTab(handle) orelse return false;
        self.menu_bridge.fireTab(.terminal_right_click, index, self.tabs.items.len > 1, .{ .x = x, .y = y, .w = 0, .h = 0 });
        return true;
    }

    fn terminalMenuTab(self: *Workspace, handle: identity.SessionHandle) ?usize {
        if (self.shutting_down) return null;
        for (self.tabs.items, 0..) |tab, index| {
            if (tab.closing or !tab.content_owner.eql(.{ .session = handle })) continue;
            if (!tab.local and (tab.isCard() or tab.failed or tab.runtime == null)) continue;
            return index;
        }
        return null;
    }

    pub fn unbindLocalTerminal(self: *Workspace, id: SessionId, handle: identity.SessionHandle) void {
        const tab = self.sessionTab(id) orelse return;
        if (!tab.local or !tab.content_owner.eql(.{ .session = handle })) return;
        tab.terminal.?.unbindTerminalService(handle);
        tab.local_bound = false;
    }

    pub fn updateLocalState(self: *Workspace, id: SessionId, state: LocalState, text: []const u8) void {
        const tab = self.sessionTab(id) orelse return;
        if (!tab.local) return;
        const changed = tab.local_state != state;
        tab.local_state = state;
        tab.failed = state == .failed;
        if (tab.local_message) |node| {
            node.setTextContent(self.allocator, switch (state) {
                .starting => "正在启动本地终端…",
                .running => "本地终端",
                .exited => "本地终端已退出",
                .failed => "本地终端启动失败",
                .closing => "正在关闭本地终端…",
                .cleanup_unknown => "暂时无法确认终端已关闭",
            }) catch {};
        }
        if (tab.local_banner) |node| {
            node.setStyleInline(self.allocator, local_styles.banner(state == .starting));
            node.setDisplay(if (state == .running) .none else .flex);
        }
        if (tab.local_detail) |node| {
            var buffer: [512]u8 = undefined;
            const detail: []const u8 = switch (state) {
                .starting => "正在准备 zsh 环境，请稍候",
                .running => "",
                .failed => std.fmt.bufPrint(&buffer, "{s}；请检查初始目录与可执行权限", .{text}) catch text,
                .exited => blk: {
                    const exit_detail = if (std.mem.indexOf(u8, text, " · ")) |offset| text[offset + " · ".len ..] else "";
                    const prefix: []const u8 = if (std.mem.startsWith(u8, exit_detail, "exit ")) " · 退出码 " else if (std.mem.startsWith(u8, exit_detail, "signal ")) " · 终止信号 " else if (exit_detail.len > 0) " · " else "";
                    const value = if (std.mem.startsWith(u8, exit_detail, "exit ")) exit_detail[5..] else if (std.mem.startsWith(u8, exit_detail, "signal ")) exit_detail[7..] else exit_detail;
                    break :blk std.fmt.bufPrint(&buffer, "历史输出仍可查看{s}{s}", .{ prefix, value }) catch "历史输出仍可查看";
                },
                .closing => "正在释放会话资源，请稍候",
                .cleanup_unknown => "资源清理结果未知，已保留会话；请稍后查看状态",
            };
            node.setTextContent(self.allocator, detail) catch {};
        }
        if (tab.local_cancel) |node| node.setDisplay(if (state == .starting) .flex else .none);
        if (tab.local_close) |node| node.setDisplay(if (state == .exited or state == .failed) .flex else .none);
        if (tab.local_spinner) |node| node.setDisplay(if (state == .starting or state == .closing) .flex else .none);
        if (tab.local_ended_icon) |node| node.setDisplay(if (state == .exited) .flex else .none);
        if (tab.local_failure_icon) |node| node.setDisplay(if (state == .failed or state == .cleanup_unknown) .flex else .none);
        if (tab.local_retry) |node| node.setDisplay(if (state == .failed) .flex else .none);
        if (tab.local_reconnect) |node| node.setDisplay(if (state == .exited) .flex else .none);
        if (changed) {
            // The state suffix (启动失败 / 已退出) is part of the derived display
            // name (tab_naming); it never renames the tab, so an in-flight
            // rename keeps its revision.
            self.refreshTabNames(true);
            self.rebuildTabBar() catch {};
        }
    }

    fn createSession(self: *Workspace, host: hosts_mod.HostConfig, host_id: HostId, index: usize, initial_input: []const u8) !void {
        const create = self.session_bridge.create orelse return error.SessionHostUnavailable;
        return create(self.session_bridge.context, host, host_id, index, initial_input);
    }

    /// Capture the host's real operation before any connection thread starts.
    /// Legacy direct callers carry no operation rather than inventing one.
    pub fn createSessionDirectForOperation(self: *Workspace, host: hosts_mod.HostConfig, host_id: HostId, source_index: usize, initial_input: []const u8, operation: OperationKey) !SessionId {
        if (operation.owner != .session or operation.operation_id == 0) return error.InvalidOperation;
        try self.spawnSessionWithInput(host, host_id, source_index, initial_input, operation);
        return self.tabs.items[self.tabs.items.len - 1].id;
    }

    pub fn cancelSessionCreation(self: *Workspace, id: SessionId) void {
        for (self.connect_jobs.items) |job| if (job.ticket.session_id == id) {
            const was_cancelled = job.cancelled.swap(true, .acq_rel);
            const retry_pending = job.automatic_retry_deadline_ns != null;
            if (retry_pending) {
                job.automatic_retry_deadline_ns = null;
                job.err = null;
            }
            // Installation may have drained the creation result before the
            // host accepted attached. Cancel must still poll the real runtime
            // destructor and publish its create-cleanup receipt exactly once.
            if (!was_cancelled and job.drained and (job.runtime != null or retry_pending)) job.drained = false;
            job.host_key_bridge.cancel();
            job.auth_bridge.cancel();
            if (self.host_key_job == job) self.hideHostKeyConfirm();
            if (self.auth_job == job) {
                if (self.auth_root) |root| root.setDisplay(.none);
                self.auth_job = null;
            }
        };
    }

    /// Protocol ownership is released before the host acknowledges view removal.
    /// Pending connect jobs are cancelled, then report their own final receipt.
    pub fn protocolRelease(self: *Workspace, id: SessionId) bool {
        return self.protocolReleaseStep(id) == .released;
    }

    pub fn protocolReleaseStep(self: *Workspace, id: SessionId) RuntimeReleaseReceipt {
        self.cancelSessionCreation(id);
        var receipt: RuntimeReleaseReceipt = .released;
        if (self.sessionTab(id)) |tab| {
            if (tab.terminal) |*terminal| {
                terminal.removeFrameHook(self.cx);
                terminal.releaseCommandDocument();
                terminal.worker = null;
            }
            if (tab.terminal) |*terminal| terminal.root.behavior.interaction.text_input_client = null;
            self.cx.refreshTextInputSession();
            if (tab.runtime) |runtime| receipt = runtime.releaseStep(.{ .session_id = tab.id, .retention_days = self.app_config.log.retention_days });
        }
        for (self.connect_jobs.items) |job| {
            if (job.ticket.session_id != id) continue;
            if (job.cleanup_unknown) return .unknown;
            if (job.ready.load(.acquire)) if (job.runtime) |runtime| {
                switch (runtime.releaseStep(null)) {
                    .unknown => return .unknown,
                    .awaiting => receipt = .awaiting,
                    .released => {},
                }
            };
            if (!job.drained and receipt == .released) receipt = .awaiting;
        }
        return receipt;
    }

    /// Called only after SessionHost has accepted this operation's attachment.
    pub fn acknowledgeSessionAttached(self: *Workspace, id: SessionId, generation: u64, operation: OperationKey) bool {
        const tab = self.sessionTab(id) orelse return false;
        if (tab.generation != generation or tab.content_owner != .session or operation.owner != .session or !tab.content_owner.session.eql(operation.owner.session)) return false;
        const runtime = tab.runtime orelse return false;
        if (runtime.torn_down) return false;
        for (self.connect_jobs.items) |job| {
            if (!job.ticket.matches(tab.ticket()) or job.cancelled.load(.acquire)) continue;
            const original = job.operation_key orelse return false;
            if (!original.eql(operation)) return false;
            const attached = runtime.acknowledgeAttached(operation);
            // This attempt's creation card is terminal after the host accepts
            // its pane. Later shell exit must not reopen an attaching dialog.
            if (attached) job.progress_dismissed = true;
            return attached;
        }
        return false;
    }

    /// 非会话卡片的 tab 宿主（PLUGIN_ARCH_PLAN 2.5 / PL4b）：卡片实例归卡片宿主（如 `HistoryHost`），
    /// workspace 只提供 tab 这个放置。tab 关闭完成后把内容节点摘下交还宿主。
    pub const CardTabPort = struct {
        context: *anyopaque,
        closed: *const fn (context: *anyopaque, card: identity.CardId) void,
    };

    /// 把一张非会话卡片放进一个新的独立 tab（单卡 tab）。卡片类型必须允许 `standalone_tab`；
    /// `content` 是卡片的内容根（归宿主所有），挂进 tab 的内容槽。返回新 tab 的 id。
    pub fn openCardTab(self: *Workspace, card_type: *const card_placement.CardTypeDef, card: identity.CardId, content: *ui.Node, title: []const u8) !identity.TabId {
        if (self.shutting_down) return error.WorkspaceClosed;
        if (!card.valid() or card_type.binding == .session) return error.InvalidCardOwner;
        if (!card_placement.canStandalone(card_type)) return error.PlacementNotAllowed;
        if (self.cardTabIndex(card) != null) return error.CardAlreadyPlaced;
        try self.tabs.ensureUnusedCapacity(self.allocator, 1);
        const tab = try self.allocator.create(SessionTab);
        errdefer self.allocator.destroy(tab);
        const pane = try ui.box(self.cx, local_styles.pane(), .{});
        errdefer self.cx.destroyDetached(pane);
        pane.meta.ownership.meta.test_id = "workspace.card.content";
        const ticket = self.identities.newTicket();
        tab.* = .{ .id = ticket.session_id, .tab_id = try tab_ids.allocate(), .content_owner = .{ .card = card }, .card_type = self.resolveCardType(card_type), .generation = ticket.generation, .host_id = 0, .host_index = removed_host_index, .host_snapshot = null, .root = pane, .card_content = content, .content_ready = true };
        tab.setTitle(title);
        try self.installTabModel(tab);
        errdefer self.model.completeClose(tab.tab_id, tab.content_owner) catch {};
        if (content.parent) |parent| self.cx.detachChild(parent, content);
        try pane.appendChild(self.allocator, content);
        errdefer self.cx.detachChild(pane, content);
        try self.terminal_area.appendChild(self.allocator, pane);
        self.appendTabAssumeCapacity(tab);
        self.rebuildTabBar() catch {};
        self.selectTab(self.tabs.items.len - 1);
        return tab.tab_id;
    }

    pub fn cardTabIndex(self: *const Workspace, card: identity.CardId) ?usize {
        for (self.tabs.items, 0..) |tab, index| if (tab.content_owner == .card and tab.content_owner.card.eql(card) and !tab.closing) return index;
        return null;
    }

    /// 只读回放表面（PL4b H2）：会话记录卡片的详情区要显示一条记录时，由 workspace 按当前显示设置
    /// （主题色、排版、光标、时间戳、输入行高亮、快捷键）建一个归档模式的终端视图，并按记录保存的
    /// 原布局参数恢复字体与提示（原归档 tab 的 `restoreArchiveDisplay`）。表面登记在 `replays` 里，
    /// 设置与主题变化时与 tab 里的终端一起更新；`releaseReplaySurface` 注销并销毁。
    pub fn mountReplaySurface(self: *Workspace, scope: *ui.Scope, document: *@import("../../history/model/history_archive.zig").Document) !*ReplaySurface {
        if (self.shutting_down) return error.WorkspaceClosed;
        if (document.timeline.frames.items.len == 0) return error.EmptyRecording;
        try self.replays.ensureUnusedCapacity(self.allocator, 1);
        const surface = try ReplaySurface.create(self.cx);
        errdefer surface.destroy();
        const terminal = surface.terminal();
        terminal.setTerminalTakeoverHandler(self.terminal_takeover_handler);
        terminal.completion_enabled = self.app_config.completion.enabled;
        terminal.keymap = &self.app_config.keys;
        terminal.root.setBackground(self.palette.terminal_bg);
        terminal.setThemeColors(self.palette.fg, self.palette.border, self.palette.accent);
        self.applyTerminalTypography(terminal) catch {};
        terminal.setCursorStyle(cursorStyle(self.app_config.ui.cursor_style));
        terminal.setTimestampGutter(self.app_config.ui.timestamp_gutter);
        terminal.setInputLineHighlight(self.app_config.ui.input_line_highlight) catch {};
        try surface.load(scope, &document.timeline, &document.reading);
        self.restoreArchiveDisplay(terminal, document.record.descriptor);
        self.replays.appendAssumeCapacity(surface);
        return surface;
    }

    pub fn releaseReplaySurface(self: *Workspace, surface: *ReplaySurface) void {
        for (self.replays.items, 0..) |item, index| if (item == surface) {
            _ = self.replays.swapRemove(index);
            break;
        };
        surface.destroy();
    }

    /// 把记录保存的原布局参数（字体、字号、行高、分组外观）套到回放表面，并给出缺口 / 回退提示。
    fn restoreArchiveDisplay(self: *Workspace, terminal: *TerminalViewNode, descriptor: anytype) void {
        if (descriptor.manifest_revision == 0) {
            terminal.setArchiveNotice("旧版记录：未保存原布局参数，按可用记录展示");
            return;
        }
        const display = descriptor.display;
        terminal.setGrouped(display.grouped);
        var fallback = display.font_family == null or display.font_size_px == null or display.line_height == null;
        if (display.font_family) |family| {
            const family_id = if (self.font_family_resolver) |resolve| resolve(family) else 0;
            fallback = fallback or (family_id == 0 and !std.mem.eql(u8, family, "system"));
            const size = display.font_size_px orelse terminal.terminal_font_size;
            const line_height = display.line_height orelse terminal.terminal_line_height;
            if (terminal.terminal_font_family == null or !std.mem.eql(u8, terminal.terminal_font_family.?, family) or terminal.terminal_font_family_id != family_id or terminal.terminal_font_size != size or terminal.terminal_line_height != line_height) {
                terminal.setTypographyFamily(size, line_height, terminal.terminal_font_weight, family, family_id) catch {
                    fallback = true;
                };
                terminal.history_reading_height = 0;
                terminal.root.markLayoutDirty();
            }
        }
        const notice: []const u8 = switch (descriptor.coverage) {
            .partial, .gapped => if (fallback) "记录存在缺口；部分原布局参数不可用，已使用可用样式" else "记录存在缺口，部分输出不可用",
            .retained => if (fallback) "显示保留片段；部分原布局参数不可用，已使用可用样式" else "显示保留的记录片段",
            else => if (fallback) "部分原字体或布局参数不可用，已使用可用样式" else "",
        };
        if (notice.len > 0) terminal.setArchiveNotice(notice);
    }

    /// Rename a live or ended tab without changing its host identity.
    pub fn renameTab(self: *Workspace, index: usize, name: []const u8) !void {
        if (index >= self.tabs.items.len) return error.InvalidTab;
        const normalized = try normalizeTabName(name);
        const tab = self.tabs.items[index];
        try self.model.renameCustom(try self.model.beginRename(tab.tab_id), normalized);
        tab.setTitle(self.model.tabs.items[self.model.indexOf(tab.tab_id).?].name());
        self.refreshTabNames(true);
        self.reveal_active = true;
        try self.rebuildTabBar();
    }

    /// Uses the target tab's owned config rather than its mutable asset index.
    /// This also works after deleting that host from the sidebar.
    pub fn newSessionFromTab(self: *Workspace, index: usize) !void {
        if (index >= self.tabs.items.len) return error.InvalidTab;
        const source = self.tabs.items[index];
        if (source.isCard()) return error.ArchivedSessionReadOnly;
        const recreate = self.session_bridge.recreate orelse return error.SessionHostUnavailable;
        const previous_group = self.creation_group;
        const previous_output = self.command_output;
        self.creation_group = self.creationGroupFor(source.id);
        self.command_output = null;
        defer {
            self.creation_group = previous_group;
            self.command_output = previous_output;
        }
        try recreate(self.session_bridge.context, source.id);
    }

    pub fn reuseSessionFromTab(self: *Workspace, index: usize) !void {
        if (index >= self.tabs.items.len) return error.InvalidTab;
        const source = self.tabs.items[index];
        if (source.isCard() or source.closing or source.runtime == null) return error.SessionNotConnected;
        const reuse = self.session_bridge.reuse orelse return error.SessionHostUnavailable;
        const previous_group = self.creation_group;
        const previous_output = self.command_output;
        self.creation_group = self.creationGroupFor(source.id);
        self.command_output = null;
        defer {
            self.creation_group = previous_group;
            self.command_output = previous_output;
        }
        try reuse(self.session_bridge.context, source.id);
    }

    /// Mirror the source's OSC directory into a distinct session. This takes
    /// an owned snapshot under the VT lock before starting the async job.
    /// A missing OSC directory explicitly skips cd; never invent a path or
    /// claim the remote shell has successfully changed directories.
    pub fn duplicateSessionFromTab(self: *Workspace, index: usize) !void {
        return self.duplicateSession(index, true);
    }
    fn duplicateSession(self: *Workspace, index: usize, inherit_group: bool) !void {
        if (index >= self.tabs.items.len) return error.InvalidTab;
        const source = self.tabs.items[index];
        if (source.isCard()) return error.ArchivedSessionReadOnly;
        const previous_group = self.creation_group;
        const previous_color = self.creation_tab_color;
        self.creation_tab_color = source.tab_color;
        const previous_output = self.command_output;
        self.creation_group = if (inherit_group) self.creationGroupFor(source.id) else null;
        self.command_output = null;
        defer {
            self.creation_group = previous_group;
            self.creation_tab_color = previous_color;
            self.command_output = previous_output;
        }
        if (source.local) {
            const duplicate = self.session_bridge.duplicate_local orelse return error.LocalAdapterUnavailable;
            return duplicate(self.session_bridge.context, source.id);
        }
        const runtime = source.runtime orelse return error.SessionNotConnected;
        if (runtime.torn_down or source.terminal.?.tombstone.state != .active or !runtime.isConnected()) return error.SessionNotConnected;
        const cwd = try runtime.copyCwd(self.allocator);
        defer if (cwd) |path| self.allocator.free(path);
        const input = if (cwd) |path| try lifecycle.mirrorDirectoryInput(self.allocator, path) else null;
        defer if (input) |bytes| self.allocator.free(bytes);
        try self.createSession(source.host_snapshot.?.value, source.host_id, self.hostIndex(source.host_id) orelse removed_host_index, input orelse "");
        if (cwd == null) self.status("镜像会话正在连接 · 当前会话未报告 OSC 7 目录，已跳过目录切换");
    }

    /// Reconnect an ended session using the tab's owned host snapshot. The
    /// tombstone tab remains visible while the replacement job is starting,
    /// so a failed reconnect never loses the user's read-only terminal.
    pub fn reconnectTab(self: *Workspace, index: usize) !void {
        if (index >= self.tabs.items.len) return error.InvalidTab;
        const source = self.tabs.items[index];
        if (source.isCard()) return error.ArchivedSessionReadOnly;
        if (source.local) return error.LocalSessionDoesNotReconnect;
        const retry = self.session_bridge.retry_ssh orelse return error.SessionHostUnavailable;
        try retry(self.session_bridge.context, source.id);
    }

    fn reconnectConfiguration(self: *Workspace, source: hosts_mod.HostConfig) @import("../../../vt/reconnect.zig").Configuration {
        const host = if (self.registry.indexOf(source.connection_id)) |index| self.registry.hosts[index] else source;
        return .{
            .startup_commands = host.startup_commands,
            .auto_shell_integration = host.auto_shell_integration orelse self.app_config.ssh.auto_shell_integration,
        };
    }

    /// Keep the original tab/VT and connection identity. Each new shell gets
    /// the current startup commands and initialization policy.
    pub fn retrySshSession(self: *Workspace, id: SessionId, next: OperationKey) !void {
        const tab = self.sessionTab(id) orelse return error.StaleSession;
        if (tab.local or tab.isCard() or tab.closing or next.owner != .session) return error.LifecycleDoesNotAllowRetry;
        const index = self.model.indexOf(tab.tab_id) orelse return error.StaleSession;
        if (self.model.tabs.items[index].revision == std.math.maxInt(u64)) return error.RevisionExhausted;
        var original: ?*ConnectJob = null;
        for (self.connect_jobs.items) |job| if (job.ticket.matches(tab.ticket())) {
            original = job;
            break;
        };
        const job = original orelse return error.StaleSession;
        const previous = job.operation_key orelse return error.MissingOperation;
        if (tab.runtime) |runtime| {
            const state = runtime.reconnectSnapshot() orelse return error.SessionClosed;
            if (state.key == null or !state.key.?.eql(previous) or (state.phase != .waiting and state.phase != .ended) or state.cleanup != .released) return error.CleanupNotReleased;
        } else if (!job.ready.load(.acquire) or !job.drained or !job.resource_ledger.snapshot().released()) return error.CleanupNotReleased;
        const configuration = self.reconnectConfiguration(job.host_snapshot.value);
        if (tab.runtime == null) {
            // No worker has been installed; its next construction must use the
            // same resolved startup policy as an existing worker's new shell.
            job.host_snapshot.value.startup_commands = try lifecycle.cloneValue([]const []const u8, job.host_snapshot.arena.allocator(), configuration.startup_commands);
            if (self.registry.indexOf(job.host_snapshot.value.connection_id)) |host_index| job.host_snapshot.value.auto_shell_integration = self.registry.hosts[host_index].auto_shell_integration;
            job.config_snapshot.value.ssh.auto_shell_integration = self.app_config.ssh.auto_shell_integration;
        }
        if (job.progress_history.items.len < 6) try job.progress_history.ensureUnusedCapacity(std.heap.c_allocator, 1);
        try job.retained_cleanup.resetReleased();
        const generation = try identity.advance(tab.generation);
        // Reserve every fallible presentation mutation before offering the
        // worker its grant. No old IO is running at this released boundary.
        try self.bindSessionOwner(id, next.owner.session);
        if (job.progress_history.items.len == 6) {
            const removed = job.progress_history.orderedRemove(0);
            job.progress_history_dropped +|= removed.journal.count;
            job.progress_history_dropped +|= removed.journal.dropped;
        }
        job.progress_history.appendAssumeCapacity(.{ .key = previous, .journal = job.progress.snapshot() });
        const automatic = job.automatic_retry_deadline_ns != null;
        if (automatic) job.connection_attempts += 1 else job.connection_attempts = 1;
        job.automatic_retry_deadline_ns = null;
        // A manual retry starts a fresh automatic chain; only it may carry the
        // one-shot credential prompt requested from the failure view.
        if (!automatic) job.automatic_retry_stopped = false;
        job.prompt_credentials = !automatic and job.credential_prompt_requested;
        job.credential_prompt_requested = false;
        job.host_key_bridge.reset();
        job.auth_bridge.resetForAttempt();
        job.cancelled.store(false, .release);
        job.err = null;
        job.cleanup_unknown = false;
        // Existing terminals keep retry progress inline; authentication still
        // uses its protected challenge presenter when required.
        job.progress_dismissed = tab.runtime != null;
        job.operation_key = next;
        tab.generation = generation;
        job.ticket = tab.ticket();
        job.progress.begin(next.attempt_id orelse 0);
        job.ready.store(false, .release);
        tab.failed = false;
        tab.remote_retrying = tab.runtime != null;
        tab.remote_retry_deadline = null;
        if (tab.remote_notice) |notice| notice.update(.{ .state = if (tab.runtime != null) .reconnecting else .connected });
        tab.terminal.?.clearPendingPaste();
        tab.terminal.?.paste_confirmation_pending = false;
        if (tab.runtime) |runtime| {
            // The mailbox is single-use and the old native graph is released.
            // A rejected grant is surfaced on the new operation, never turned
            // into a factory error claiming that this Runtime does not exist.
            const skip = if (tab.shell_init_skip_for_operation) |key| key.eql(previous) else false;
            tab.shell_init_skip_for_operation = null;
            tab.shell_init_confirmation_required = false;
            runtime.requestReconnectConfigured(previous, next, skip, configuration) catch |err| {
                job.err = err;
                job.ready.store(true, .release);
                tab.failed = true;
                return;
            };
        } else {
            job.resource_ledger.beginAttempt(previous, next) catch |err| {
                job.err = err;
                job.ready.store(true, .release);
                tab.failed = true;
                job.cleanup_unknown = true;
                return;
            };
            job.host_key_store.refresh() catch |err| {
                job.err = err;
                job.ready.store(true, .release);
                tab.failed = true;
                return;
            };
            job.drained = false;
            job.thread = std.Thread.spawn(.{}, @import("../../../plugins/ssh/connect_job.zig").connectThread, .{job}) catch |err| {
                job.err = err;
                job.ready.store(true, .release);
                return;
            };
        }
        tab.terminal.?.tombstone.state = .reconnecting;
        tab.terminal.?.refreshTombstone();
        self.tab_rebuild_pending = true;
        self.cx.requestRedraw();
    }

    fn reconnectRemoteNotice(raw: *anyopaque, id: u64) void {
        const self: *Workspace = @ptrCast(@alignCast(raw));
        const index = self.tabIndex(id) orelse return;
        self.reconnectTab(index) catch |err| self.statusFailure(@errorName(err));
    }
    fn reconnectWithoutInitialization(raw: *anyopaque, id: u64) void {
        const self: *Workspace = @ptrCast(@alignCast(raw));
        const tab = self.sessionTab(id) orelse return;
        if (!tab.shell_init_confirmation_required) return;
        const runtime = tab.runtime orelse return;
        const state = runtime.reconnectSnapshot() orelse return;
        const key = state.key orelse return;
        if ((state.failure == null or state.failure.? != error.ShellInitializationFailed) or state.cleanup != .released or state.phase != .waiting) return;
        tab.shell_init_skip_for_operation = key;
        const index = self.tabIndex(id) orelse return;
        self.reconnectTab(index) catch |err| {
            tab.shell_init_skip_for_operation = null;
            self.statusFailure(@errorName(err));
        };
    }

    fn closeRemoteNotice(raw: *anyopaque, id: u64) void {
        const self: *Workspace = @ptrCast(@alignCast(raw));
        self.requestCloseTab(self.tabIndex(id) orelse return);
    }

    /// Updates only controller facts for the same attempt. Native completions
    /// remain tagged by their captured key, not this Job's later current key.
    pub fn finishSshReconnect(self: *Workspace, id: SessionId, key: OperationKey, failure: ?anyerror) void {
        const tab = self.sessionTab(id) orelse return;
        for (self.connect_jobs.items) |job| {
            if (!job.ticket.matches(tab.ticket()) or job.operation_key == null or !job.operation_key.?.eql(key)) continue;
            job.err = failure;
            job.ready.store(true, .release);
            tab.failed = failure != null;
            self.tab_rebuild_pending = true;
            return;
        }
    }

    pub fn connectionDetailsStore(self: *Workspace, id: SessionId, key: OperationKey) !*@import("../../../proto/ssh/connection_details.zig").Store {
        const tab = self.sessionTab(id) orelse return error.StaleSession;
        for (self.connect_jobs.items) |job| {
            if (job.ticket.matches(tab.ticket()) and job.operation_key != null and job.operation_key.?.eql(key)) return &job.connection_details;
        }
        return error.StaleOperation;
    }

    fn spawnSessionWithInput(self: *Workspace, host: hosts_mod.HostConfig, host_id: HostId, host_index: usize, initial_input: []const u8, operation: ?OperationKey) !void {
        if (self.shutting_down) return error.WorkspaceClosed;
        try self.tabs.ensureUnusedCapacity(self.allocator, 1);
        try self.connect_jobs.ensureUnusedCapacity(self.allocator, 1);
        try self.startPollLoop();
        const ticket = self.identities.newTicket();
        const job = try ConnectJob.create(ticket, host, self.registry.hosts, self.app_config.*, self.io);
        errdefer job.destroy();
        if (self.pending_shared_connection) |lease| job.shared_connection = lease.retain();
        if (self.pending_bootstrap) |prepared| job.bootstrap = prepared.retain();
        job.operation_key = operation;
        job.resource_ledger.key = operation;
        job.progress.begin(if (operation) |key| key.attempt_id orelse 0 else 0);
        job.initial_input = try std.heap.c_allocator.dupe(u8, initial_input);
        const tab = try self.allocator.create(SessionTab);
        errdefer self.allocator.destroy(tab);
        var snapshot = try HostSnapshot.init(self.allocator, host);
        errdefer snapshot.deinit();
        var terminal = try TerminalViewNode.mount(self.cx);
        terminal.setTerminalTakeoverHandler(self.terminal_takeover_handler);
        var notice_scope: ?*ui.Scope = null;
        var owned_pane: ?*ui.Node = null;
        var terminal_attached = false;
        errdefer {
            terminal.releaseBuffers(self.cx);
            if (notice_scope) |scope| scope.dispose();
            if (owned_pane) |pane| self.cx.destroyDetached(pane);
            if (!terminal_attached) self.cx.destroyDetached(terminal.root);
        }
        terminal.completion_enabled = self.app_config.completion.enabled;
        terminal.keymap = &self.app_config.keys;
        terminal.palette_observer = self.command_bridge;
        terminal.input_observer = self.input_bridge;
        terminal.root.setBackground(self.palette.terminal_bg);
        terminal.setThemeColors(self.palette.fg, self.palette.border, self.palette.accent);
        self.applyTerminalTypography(&terminal) catch {};
        terminal.setCursorStyle(cursorStyle(self.app_config.ui.cursor_style));
        terminal.setTimestampGutter(self.app_config.ui.timestamp_gutter);
        terminal.setInputLineHighlight(self.app_config.ui.input_line_highlight) catch {};
        terminal.setOutput(self.cx, "正在连接…") catch {};
        notice_scope = try self.scope.childScope();
        const pane = try ui.box(self.cx, local_styles.pane(), .{});
        owned_pane = pane;
        terminal.root.setStyleInline(self.allocator, .{ .width = .fill(), .height = .fill(), .flex = 1, .min_height = 0 });
        const notice = try RemoteNotice.View.mount(self.cx, notice_scope.?, pane, .{ .context = self, .session_id = ticket.session_id, .reconnect = reconnectRemoteNotice, .without_initialization = reconnectWithoutInitialization, .close = closeRemoteNotice });
        try pane.appendChild(self.allocator, terminal.root);
        terminal_attached = true;
        tab.* = .{
            .id = ticket.session_id,
            .tab_id = try tab_ids.allocate(),
            .content_owner = .{ .session = .{ .session_id = @fromBackingInt(ticket.session_id), .generation = ticket.generation } },
            .card_type = self.resolveCardType(&card_placement.terminal_def),
            .generation = ticket.generation,
            .host_id = host_id,
            .host_index = host_index,
            .host_snapshot = snapshot,
            .root = pane,
            .remote_notice_scope = notice_scope,
            .remote_notice = notice,
            .terminal = terminal,
        };
        tab.setTitle(host.name);
        try self.installTabModel(tab);
        try tab.terminal.?.attachSearch(self.scope);
        try self.terminal_area.appendChild(self.cx.allocator, pane);
        // After publishing, every failure is represented by this tab. No worker
        // owns a pointer to it, so closing it cannot invalidate a pending job.
        self.appendTabAssumeCapacity(tab);
        const tab_index = self.tabs.items.len - 1;
        job.thread = std.Thread.spawn(.{}, @import("../../../plugins/ssh/connect_job.zig").connectThread, .{job}) catch |err| {
            tab.failed = true;
            job.err = err;
            job.ready.store(true, .release);
            self.connect_jobs.appendAssumeCapacity(job);
            self.rebuildTabBar() catch {};
            self.selectTab(tab_index);
            self.statusFailure(@errorName(err));
            return;
        };
        self.connect_jobs.appendAssumeCapacity(job);
        self.rebuildTabBar() catch {};
        self.selectTab(tab_index);
        self.status("连接中…");
        self.cx.scheduleRedrawAfterNs(33 * std.time.ns_per_ms);
    }

    fn ignoreCommand(_: ?*anyopaque, _: []const u8, _: bool) void {}

    const ConnectJob = @import("../../../plugins/ssh/connect_job.zig").ConnectJob;

    /// Jobs stay alive for the workspace lifetime: attached runtimes retain
    /// their job's private IO context for checkpoint writes. The scope destroys
    /// those runtimes before Workspace.cleanup frees the IO contexts.
    fn drainResults(self: *Workspace, publish_views: bool) void {
        for (self.connect_jobs.items) |job| {
            if (!publish_views and !job.cancelled.load(.acquire)) continue;
            if (job.drained and !self.shutting_down and !job.cancelled.load(.acquire)) if (job.automatic_retry_deadline_ns) |deadline| {
                if (self.findTicket(job.ticket)) |tab| if (tab.owned_origin and !tab.closing and @import("../../../platform/realtime.zig").monotonicNs() >= deadline) {
                    job.retryOwnedTransport() catch |err| {
                        job.automatic_retry_deadline_ns = null;
                        job.err = err;
                        job.drained = false;
                        job.ready.store(true, .release);
                    };
                };
            };
            // Reconnect runs on the existing Runtime thread, not a second
            // ConnectJob.thread. Cancellation must poll that Runtime even
            // while its current auth/handshake has not produced ready.
            const cancelled_runtime = job.cancelled.load(.acquire) and job.runtime_scope_owned and job.runtime != null;
            if (job.drained or job.cleanup_unknown or (!job.ready.load(.acquire) and !cancelled_runtime)) continue;
            if (job.thread) |thread| {
                thread.join();
                job.thread = null;
            }
            const tab = if (!job.cancelled.load(.acquire)) self.findTicket(job.ticket) else null;
            if (tab == null or self.shutting_down) {
                if (job.runtime) |runtime| switch (runtime.releaseStep(null)) {
                    .awaiting => continue,
                    .unknown => {
                        job.cleanup_unknown = true;
                        self.notifyConnectionCleanup(job, .unknown);
                        continue;
                    },
                    .released => if (!job.runtime_scope_owned) runtime.cleanup(),
                };
                // Scope-owned runtimes retain their struct until its single
                // registered destructor. Every owned member is already gone.
                if (!job.runtime_scope_owned) job.runtime = null;
                switch (job.failedCleanupReceipt()) {
                    .awaiting => continue,
                    .unknown => {
                        job.cleanup_unknown = true;
                        self.notifyConnectionCleanup(job, .unknown);
                        continue;
                    },
                    .released => {},
                }
                job.drained = true;
                job.ready.store(true, .release);
                // A cancelled initial connection can keep its tab after the
                // progress sheet closes. Retire its connecting placeholder
                // only once cleanup completes; reconnects retain their output.
                if (publish_views and !self.shutting_down and job.cancelled.load(.acquire)) {
                    if (self.findTicket(job.ticket)) |cancelled_tab| {
                        if (cancelled_tab.runtime == null) {
                            if (cancelled_tab.terminal) |*terminal| terminal.setOutput(self.cx, "") catch {};
                            if (cancelled_tab.remote_notice) |notice| notice.update(.{ .state = .cancelled });
                            if (self.active_tab == self.tabIndex(cancelled_tab.id)) self.status("连接已取消");
                        }
                    }
                }
                self.notifyConnectionCleanup(job, .released);
                continue;
            }
            const target = tab.?;
            if (job.err) |err| {
                if (self.session_bridge.retry_ssh != null and (if (target.owned_origin) job.canRetryOwnedTransport() else job.canAutomaticallyRetry())) {
                    const receipt = job.failedCleanupReceipt();
                    if (receipt == .awaiting) continue;
                    if (receipt == .released) {
                        // Keep transient failures in diagnostics; only an exhausted
                        // attempt publishes failure feedback or replaces terminal text.
                        const delay_ms: i128 = ConnectJob.automaticRetryDelayMs(job.connection_attempts);
                        job.automatic_retry_delay_ns = delay_ms * std.time.ns_per_ms;
                        job.automatic_retry_deadline_ns = @import("../../../platform/realtime.zig").monotonicNs() + delay_ms * std.time.ns_per_ms;
                        applog.info(.workspace, "connect retry scheduled session={d} attempt={d}/3 delay_ms={d} cause={s}", .{ target.id, job.connection_attempts + 1, delay_ms, @errorName(err) });
                        job.drained = true;
                        if (!target.owned_origin) {
                            if (self.session_bridge.failed) |failed| failed(self.session_bridge.context, target.id, target.generation, @errorName(err));
                            self.notifyConnectionCleanup(job, .released);
                        }
                        self.cx.scheduleRedrawAfterNs(@intCast(delay_ms * std.time.ns_per_ms));
                        continue;
                    }
                }
                target.failed = true;
                var failure_buffer: [512]u8 = undefined;
                const failure_title = std.fmt.bufPrint(&failure_buffer, "连接失败：{s}", .{@import("../../../shared/base/error_text.zig").lineOr(err, "请查看连接日志中的错误码")}) catch "连接失败";
                var buffer: [768]u8 = undefined;
                const text = std.fmt.bufPrint(&buffer, "{s} · 会话 {d} {s}", .{ target.titleSlice(), target.id, failure_title }) catch failure_title;
                target.terminal.?.setOutput(self.cx, text) catch {};
                if (self.active_tab == self.tabIndex(target.id)) self.status(text);
                self.notifyConnectionFailure(job, failure_title);
                const cleanup_receipt = job.failedCleanupReceipt();
                if (cleanup_receipt != .released) {
                    if (cleanup_receipt == .unknown) job.cleanup_unknown = true;
                    self.notifyConnectionCleanup(job, cleanup_receipt);
                    continue;
                }
                job.drained = true;
                self.notifyConnectionCleanup(job, .released);
            } else if (job.runtime) |runtime| {
                // Register the runtime owner before publishing it to the tab.
                // Workspace is registered first and will clean up the job last.
                self.scope.onCleanup(ConnectJob, job, cleanupJobRuntime) catch {
                    self.failRuntimeAttachment(job, target, "无法安装会话资源");
                    continue;
                };
                job.runtime_scope_owned = true;
                target.setRuntime(runtime);
                if (target.content_owner == .session) target.terminal.?.setWorkerMenuHandler(target.content_owner.session, .{ .context = self, .request = onTerminalServiceMenu, .secondary = onTerminalServiceContext });
                const active = self.active_tab == self.tabIndex(target.id);
                if (active) {
                    target.terminal.?.grid_status_node = self.grid_node;
                    target.terminal.?.grid_label_shown = false;
                }
                runtime.mountTerminal(&target.terminal.?, self.status_node orelse target.terminal.?.root) catch {
                    self.failRuntimeAttachment(job, target, "无法安装终端绘制回调");
                    continue;
                };
                if (active) {
                    self.status("已连接");
                    self.cx.setFocus(target.terminal.?.root);
                }
                job.drained = true;
                if (self.session_bridge.connected) |connected| {
                    connected(self.session_bridge.context, target.id, target.generation);
                } else {
                    // Legacy direct callers have no host controller. Their
                    // successful local installation is the attachment boundary.
                    runtime.markAttached();
                }
            }
            self.rebuildTabBar() catch {};
            self.rebuildSidebar() catch {};
        }
    }

    /// Native teardown no longer runs the layout hook. Poll only attempts
    /// already cancelled by owner shutdown so their final release receipt
    /// can reach SessionHost without installing or updating a view.
    pub fn drainCancelledConnections(self: *Workspace) void {
        self.drainResults(false);
    }

    /// The application controller may drain completed workers at its existing
    /// UI safe point; the Workspace hook also calls the same idempotent drain.
    pub fn pollConnectionResults(self: *Workspace) void {
        self.drainResults(true);
        self.pollSessionOs();
        self.drainCloseReceipts();
    }

    /// Called on the UI owner, after worker publication. Never touches SSH IO.
    pub fn pollSessionOs(self: *Workspace) void {
        for (self.tabs.items) |tab| {
            if (tab.local or tab.closing) continue;
            const runtime = tab.runtime orelse continue;
            if (tab.remote_notice) |notice| if (runtime.reconnectSnapshot()) |captured| {
                var state = RemoteNotice.Snapshot.fromRuntime(captured, tab.remote_retrying);
                state.initialization_confirmation = tab.shell_init_confirmation_required;
                state.buffer_input = self.app_config.ssh.buffer_input;
                if (tab.remote_retry_deadline) |deadline| {
                    const remaining = @max(0, deadline - @import("../../../platform/realtime.zig").monotonicNs());
                    state.auto_retry_seconds = @intCast(@divTrunc(remaining + std.time.ns_per_s - 1, std.time.ns_per_s));
                }
                if (state.state == .connected) tab.remote_retrying = false;
                if (state.state == .reconnecting) tab.remote_retrying = true;
                notice.update(state);
                // Keep input and contextual actions in step with the same facts,
                // including a failed successor after the first transport loss.
                if (tab.terminal) |*terminal| switch (state.state) {
                    .cancelled, .exited, .disconnected, .retry_failed => {
                        if (terminal.tombstone.state != .ended) {
                            terminal.tombstone.end(state.title());
                            terminal.refreshTombstone();
                        }
                    },
                    .reconnecting => {
                        terminal.tombstone.state = .reconnecting;
                        terminal.refreshTombstone();
                    },
                    .connected => {},
                };
            };
            const detection = runtime.osDetection();
            if (detection.pending) self.cx.scheduleRedrawAfterNs(100 * std.time.ns_per_ms);
            const kind = detection.kind;
            if (kind == .unknown or kind == tab.detected_os) continue;
            self.updateSessionOs(tab.content_owner.session, kind, if (tab.host_snapshot) |saved| saved.value else null);
        }
    }

    pub fn updateSessionOs(self: *Workspace, owner: identity.SessionHandle, kind: session_icon.Os, original: ?hosts_mod.HostConfig) void {
        if (kind == .unknown) return;
        for (self.tabs.items) |tab| {
            if (tab.content_owner != .session or !tab.content_owner.session.eql(owner) or tab.closing or tab.detected_os == kind) continue;
            tab.detected_os = kind;
            if (original) |host| {
                @import("../host/session_os_cache.zig").save(self.allocator, self.io, self.hosts_path, host, kind);
                for (self.host_rows.items) |row| {
                    const current = self.registry.hosts[row.host_index];
                    if (current.connection_id == host.connection_id and std.mem.eql(u8, current.host, host.host) and current.port == host.port and std.mem.eql(u8, current.user, host.user)) session_icon.setHostNode(row.view.dot, self.plugins, current.protocolId(), kind);
                }
            }
            // The strip recomputes type icons on its next visual refresh (tab_strip.yix).
            self.strip_icons_dirty = true;
            self.cx.requestRedraw();
        }
    }

    fn drainCloseReceipts(self: *Workspace) void {
        while (self.close_receipts.items.len > 0) {
            const receipt = self.close_receipts.orderedRemove(0);
            if (self.tabIndexById(receipt.tab)) |index| {
                const tab = self.tabs.items[index];
                if (self.model.isCurrentTarget(receipt) or (tab.owned_pending and tab.content_owner.eql(receipt.owner))) self.removeClosedTab(index);
            }
        }
    }

    fn notifyConnectionFailure(self: *Workspace, job: *ConnectJob, message: []const u8) void {
        if (self.findTicket(job.ticket)) |tab| self.reportFailure(tab.content_owner, message);
        if (self.session_bridge.failed) |failed| failed(self.session_bridge.context, job.ticket.session_id, job.ticket.generation, message);
    }

    fn notifyConnectionCleanup(self: *Workspace, job: *ConnectJob, receipt: RuntimeReleaseReceipt) void {
        if (self.session_bridge.cleanup_status) |callback| {
            callback(self.session_bridge.context, job.ticket.session_id, job.ticket.generation, receipt);
        } else if (receipt == .released) {
            if (self.session_bridge.cleanup) |callback| callback(self.session_bridge.context, job.ticket.session_id, job.ticket.generation);
        }
    }

    fn failRuntimeAttachment(self: *Workspace, job: *ConnectJob, tab: *SessionTab, message: []const u8) void {
        tab.failed = true;
        tab.terminal.?.removeFrameHook(self.cx);
        tab.terminal.?.worker = null;
        if (tab.terminal) |*terminal| terminal.root.behavior.interaction.text_input_client = null;
        self.cx.refreshTextInputSession();
        self.notifyConnectionFailure(job, message);
        self.cancelSessionCreation(tab.id);
        if (job.runtime) |runtime| _ = runtime.releaseStep(null);
    }

    fn cleanupJobRuntime(job: *ConnectJob) void {
        if (job.runtime) |runtime| if (!runtime.cleanupReleased()) return;
        job.runtime = null;
    }

    const PollHook = struct {
        workspace: *Workspace,

        fn run(ctx: *anyopaque, _: u8, _: bool) ui.AfterLayoutResult {
            const hook: *PollHook = @ptrCast(@alignCast(ctx));
            const workspace = hook.workspace;
            if (workspace.shutting_down) return .done;
            workspace.pollHostKeyConfirm();
            for (workspace.host_rows.items) |row| row.view.setOnline(workspace.hostOnline(row.host_index));
            workspace.drainResults(true);
            workspace.pollSessionOs();
            // Hidden Local panes must keep consuming their own TextSlot so a
            // bounded producer can progress. Only the active pane gets a live
            // input clock; TerminalView additionally checks actual focus.
            for (workspace.tabs.items, 0..) |tab, index| {
                if (tab.terminal != null and tab.content_owner == .session) tab.terminal.?.configureErrorHint(tab.content_owner.session, workspace.app_config.ai.error_hint, workspace.error_hint_handler) catch {};
                if (!tab.local or !tab.local_bound or tab.content_owner != .session) continue;
                _ = tab.terminal.?.refreshTerminalService(tab.content_owner.session, workspace.active_tab == index or tab.floating) catch |err| switch (err) {
                    error.WorkerBusy, error.SnapshotUnavailable => false,
                    else => blk: {
                        applog.warn(.workspace, "Local view refresh: {s}", .{@errorName(err)});
                        break :blk false;
                    },
                };
            }
            workspace.refreshTabNames(false);
            workspace.refreshCommandOrdinals();
            workspace.refreshNotificationAttention();
            workspace.drainCloseReceipts();
            if (workspace.pollGroupWorkspace()) return .needs_layout;
            if (workspace.reflowGroupAxes()) return .needs_layout;
            if (workspace.syncStandaloneHeader()) return .needs_layout;
            // cards-float: the tab body's "卡片已浮动" while every card of the current tab floats.
            workspace.syncFloatedPlaceholder();
            if ((workspace.close_others_keep != null or workspace.window_close_request != null) and (workspace.confirming_id == null or workspace.window_close_reconcile)) workspace.continueCloseOthers();
            if (workspace.header_width != @max(0, workspace.cx.viewport.width - 2 * @import("../../shell/view/shell_styles.zig").outer)) {
                workspace.reveal_active = true;
                workspace.tab_rebuild_pending = true;
            }
            if (workspace.rename_request) |request| {
                if (workspace.model.indexOf(request.tab) == null) _ = workspace.cancelRenameTab();
            }
            workspace.flushRename() catch |err| applog.err(.ui, "rename dialog: {s}", .{@errorName(err)});
            if (workspace.tab_rebuild_pending and !workspace.model.dragging) {
                workspace.tab_rebuild_pending = false;
                workspace.renderTabBar() catch |err| applog.err(.ui, "tab-bar rebuild: {s}", .{@errorName(err)});
                return .needs_layout;
            }
            // A canceled job still needs polling after its tab has disappeared.
            for (workspace.connect_jobs.items) |job| {
                if ((!job.drained and !job.cleanup_unknown) or job.host_key_bridge.pending()) {
                    workspace.cx.scheduleRedrawAfterNs(33 * std.time.ns_per_ms);
                    break;
                }
            }
            return .done;
        }
    };

    fn startPollLoop(self: *Workspace) !void {
        if (self.poll_hook != null) return;
        const hook = try self.allocator.create(PollHook);
        errdefer self.allocator.destroy(hook);
        hook.* = .{ .workspace = self };
        try self.cx.addAfterLayoutHook(hook, PollHook.run);
        self.poll_hook = hook;
    }
};

pub fn cleanupRuntime(runtime: *SessionRuntime) void {
    runtime.cleanup();
}

/// Shared handle for click trampolines; UI-thread only.
pub var current_workspace: ?*Workspace = null;

test "recent tab input leaves plain Tab and higher priority input untouched" {
    const allocator = std.testing.allocator;
    // Only the input gate is exercised; reaching presentation would touch
    // uninitialised view fields and fail rather than silently switch a tab.
    var workspace: Workspace = undefined;
    workspace.group_views = .empty;
    workspace.group_roster = null;
    workspace.active_group_view = null;
    workspace.external_auth = null;
    workspace.allocator = allocator;
    workspace.rename_editor = null;
    workspace.rename_request = null;
    workspace.model = .{ .allocator = allocator, .window = @fromBackingInt(1), .workspace = @fromBackingInt(1) };
    defer workspace.model.deinit();
    workspace.confirming_id = null;
    workspace.host_key_job = null;
    workspace.auth_job = null;
    workspace.active_tab = null;
    workspace.tabs = .empty;
    const control: ui.events.Modifiers = .{ .ctrl = true };
    // Plain Tab is not a shortcut; the router decides which keys reach here as `recent`.
    try std.testing.expectEqual(ui.events.EventResult.ignored, workspace.handleTabKey(.tab, .{}, .none));
    try std.testing.expectEqual(ui.events.EventResult.ignored, workspace.handleTabKey(.tab, .{ .ctrl = true, .alt = true }, .none));
    workspace.confirming_id = @fromBackingInt(1);
    try std.testing.expectEqual(ui.events.EventResult.ignored, workspace.handleTabKey(.tab, control, .recent));
    workspace.confirming_id = null;
    var tab: SessionTab = undefined;
    tab.closing = false;
    tab.plugin_renderer = null;
    tab.terminal = @as(TerminalViewNode, undefined);
    tab.terminal.?.terminal_surface = null;
    var preedit = [_]u8{'x'};
    tab.terminal.?.preedit = &preedit;
    tab.terminal.?.local_editor.active = false;
    var tabs = [_]*SessionTab{&tab};
    workspace.tabs.items = &tabs;
    workspace.tabs.capacity = tabs.len;
    workspace.active_tab = 0;
    // The yield facts the router reads: composing and local editing keep ⌃Tab; F2 belongs to the content.
    const router = @import("../../shell/mod.zig").shortcut_router;
    const map: router.Map = .{};
    var facts = workspace.shortcutFacts();
    try std.testing.expect(facts.preedit and facts.content and !facts.local_editor);
    try std.testing.expectEqual(router.Decision{ .yield = .recent_tab }, (router.Router{ .keys = &map }).route(ui.events.KeyCode.tab, control, .{ .preedit = facts.preedit, .local_editor = facts.local_editor, .content = facts.content }));
    try std.testing.expectEqual(router.Decision{ .yield = .rename_tab }, (router.Router{ .keys = &map }).route(ui.events.KeyCode.f2, ui.events.Modifiers{}, .{ .preedit = facts.preedit, .local_editor = facts.local_editor, .content = facts.content }));
    tab.terminal.?.preedit = null;
    tab.terminal.?.local_editor.active = true;
    facts = workspace.shortcutFacts();
    try std.testing.expect(!facts.preedit and facts.local_editor and !facts.content);
    try std.testing.expectEqual(router.Decision{ .yield = .recent_tab }, (router.Router{ .keys = &map }).route(ui.events.KeyCode.tab, control, .{ .preedit = facts.preedit, .local_editor = facts.local_editor, .content = facts.content }));
    try std.testing.expect(workspace.model.recent_cursor == null);
}

test "tab grouping native drop preserves target conversation and refreshes existing group membership only" {
    const allocator = std.testing.allocator;
    const cx = try ui.Cx.init(allocator, std.testing.io);
    defer cx.deinit();
    const scope = try ui.Scope.init(allocator, null, cx.owner);
    const root = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .direction = .column }, .{});
    cx.root = root;
    const strip = try ui.box(cx, .{ .height = .{ .px = 32 }, .direction = .row }, .{});
    try root.appendChild(allocator, strip);
    const area = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    try root.appendChild(allocator, area);
    const empty = try ui.box(cx, .{ .display = .none }, .{});
    try area.appendChild(allocator, empty);
    const config: config_mod.Config = .{};
    var roster = group_model.Roster.init(allocator);
    defer roster.deinit();
    var workspace: Workspace = .{ .allocator = allocator, .cx = cx, .scope = scope, .io = std.testing.io, .app_config = &config, .palette = Palette.fromTheme(), .registry = .{ .arena = std.heap.ArenaAllocator.init(allocator), .hosts = &.{} }, .hosts_path = "", .sidebar_list = root, .tab_bar = strip, .terminal_area = area, .empty_state = empty, .group_roster = &roster, .model = .{ .allocator = allocator, .window = @fromBackingInt(1), .workspace = @fromBackingInt(1) } };
    defer {
        if (workspace.poll_hook) |hook| {
            cx.removeAfterLayoutHook(hook);
            allocator.destroy(hook);
            workspace.poll_hook = null;
        }
        scope.dispose();
        for (workspace.click_ctxs.items) |cell| allocator.destroy(cell);
        workspace.click_ctxs.deinit(allocator);
        workspace.tab_nodes.deinit(allocator);
        workspace.strip_advances.deinit(allocator);
        workspace.strip_widths.deinit(allocator);
        workspace.strip_grouped.deinit(allocator);
        workspace.tabs.deinit(allocator);
        workspace.model.deinit();
        workspace.registry.deinit();
        for (workspace.group_views.items) |view| {
            view.deinit(allocator);
            allocator.destroy(view);
        }
        workspace.group_views.deinit(allocator);
    }
    const Probe = struct {
        store: @import("../../../ai/assistant_store.zig").Store,
        preparations: usize = 0,
        stops: usize = 0,
        captures: usize = 0,
        releases: usize = 0,
        ready: bool = false,
        fn capture(raw: *anyopaque, _: u64, _: ?u64) !ai_tab_grouping.Settlement {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.captures += 1;
            return .{ .operation = identity.HostOperationId.generate() };
        }
        fn settle(raw: *anyopaque, _: ai_tab_grouping.Settlement) !bool {
            const self: *@This() = @ptrCast(@alignCast(raw));
            return self.ready;
        }
        fn release(raw: *anyopaque, _: ai_tab_grouping.Settlement) void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.releases += 1;
        }
        fn prepare(raw: *anyopaque, drop: ai_tab_grouping.Drop) !ai_tab_grouping.Plan {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.preparations += 1;
            return ai_tab_grouping.prepare(&self.store, drop);
        }
        fn commit(raw: *anyopaque, plan: ai_tab_grouping.Plan) void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            ai_tab_grouping.commit(&self.store, plan, self, stop) catch unreachable;
        }
        fn stop(raw: *anyopaque, _: ai_tab_grouping.Activity) void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.stops += 1;
        }
    };
    var probe: Probe = .{ .store = @import("../../../ai/assistant_store.zig").Store.init(allocator) };
    defer probe.store.deinit();
    workspace.ai_grouping_bridge = .{ .context = &probe, .prepare = Probe.prepare, .commit = Probe.commit, .capture = Probe.capture, .settle = Probe.settle, .release = Probe.release };
    cx.setViewport(860, 480);
    var tabs: [3]SessionTab = undefined;
    var conversations: [3]u64 = undefined;
    for (&tabs, 0..) |*tab, index| {
        const id: u64 = @intCast(index + 71);
        const pane = try ui.box(cx, .{}, .{});
        try area.appendChild(allocator, pane);
        tab.* = .{ .id = id, .tab_id = try tab_ids.allocate(), .content_owner = .{ .session = .{ .session_id = @fromBackingInt(id), .generation = 1 } }, .host_id = 0, .host_index = 0, .host_snapshot = null, .root = pane, .local = true };
        tab.setTitle(if (index == 0) "Source A" else if (index == 1) "Target B" else "Source C");
        try workspace.tabs.append(allocator, tab);
        try workspace.installTabModel(tab);
        conversations[index] = (try probe.store.create(.{ .tab = @backingInt(tab.tab_id) })).id;
    }
    const b_identity = probe.store.find(conversations[1]).?.conversation_id;
    // A genuine edge drop follows the reorder path and never calls the AI bridge.
    try workspace.renderTabBar();
    cx.layout();
    const first = workspace.tab_nodes.items[0].node.globalRect();
    const last = workspace.tab_nodes.items[2].node.globalRect();
    cx.handleMouseDown(first.x + 35, first.y + 15, .{});
    cx.handleMouseMove(last.x + last.w - 2, last.y + 15);
    cx.handleMouseUp(last.x + last.w - 2, last.y + 15);
    try std.testing.expect(workspace.pending_tab_drop == null);
    try std.testing.expectEqual(@as(usize, 0), probe.preparations);
    try std.testing.expectEqual(@as(usize, 0), probe.stops);
    // Drag a real tab into the currently displayed session's content area.
    workspace.selectTab(workspace.tabIndexById(tabs[1].tab_id).?);
    try workspace.renderTabBar();
    cx.layout();
    var source_rect: ui.ComputedRect = undefined;
    for (workspace.tab_nodes.items) |node| if (node.tab_id == tabs[0].tab_id) {
        source_rect = node.node.globalRect();
    };
    const content_rect = area.globalRect();
    cx.handleMouseDown(source_rect.x + 45, source_rect.y + 15, .{});
    cx.handleMouseMove(content_rect.x + content_rect.w / 2, content_rect.y + content_rect.h / 2);
    cx.handleMouseUp(content_rect.x + content_rect.w / 2, content_rect.y + content_rect.h / 2);
    try std.testing.expectEqual(tabs[1].tab_id, workspace.pending_tab_drop.?.target);
    _ = workspace.pollGroupWorkspace();
    _ = workspace.pollGroupWorkspace();
    try std.testing.expectEqual(@as(usize, 1), probe.captures);
    try std.testing.expectEqual(@as(usize, 0), probe.preparations);
    try std.testing.expectEqual(@as(usize, 0), roster.groups.items.len);
    try std.testing.expect(workspace.pending_tab_drop != null);
    probe.ready = true;
    _ = workspace.pollGroupWorkspace();
    try std.testing.expect(workspace.pending_tab_drop == null);
    try std.testing.expectEqual(@as(usize, 1), probe.releases);
    const group = roster.groups.items[0].id;
    try std.testing.expectEqualStrings("Target B", roster.groups.items[0].name);
    const parent = workspace.groupTabId(group).?;
    try std.testing.expect(probe.store.find(conversations[0]).?.ended);
    try std.testing.expect(probe.store.active(.{ .tab = @backingInt(parent) }).?.conversation_id.eql(b_identity));
    try std.testing.expectEqual(@as(usize, 1), probe.stops);
    const revision = roster.findById(group).?.membership_revision;
    probe.ready = false;
    workspace.pending_tab_drop = .{ .source = tabs[2].tab_id, .target = parent };
    try std.testing.expect(!try workspace.settleTabDrop());
    roster.findById(group).?.membership_revision += 1;
    try std.testing.expectError(error.SourceChanged, workspace.settleTabDrop());
    workspace.releaseTabDrop();
    try std.testing.expect(!probe.store.find(conversations[2]).?.ended);
    try std.testing.expectEqual(@as(usize, 2), roster.findById(group).?.members.items.len);
    roster.findById(group).?.membership_revision = revision;
    try workspace.dropTabIntoGroup(tabs[2].tab_id, parent);
    try std.testing.expectEqual(revision + 1, roster.findById(group).?.membership_revision);
    try std.testing.expectEqual(@as(usize, 3), roster.findById(group).?.members.items.len);
    try std.testing.expect(probe.store.active(.{ .tab = @backingInt(parent) }).?.conversation_id.eql(b_identity));
    try std.testing.expect(probe.store.find(conversations[2]).?.ended);
    try std.testing.expectEqual(@as(usize, 2), probe.stops);
    for (tabs) |tab| {
        try std.testing.expect(!tab.closing);
        try std.testing.expectEqual(parent, workspace.model.tabs.items[workspace.model.indexOf(tab.tab_id).?].container.?);
    }
}

test {
    _ = ai_tab_grouping;
}

test "temporary connection source uses the frozen remote tab and excludes saved local or closed tabs" {
    var endpoint = "frozen.example".*;
    var tab: SessionTab = .{
        .id = 91,
        .tab_id = @fromBackingInt(7),
        .content_owner = .{ .session = .{ .session_id = @fromBackingInt(91) } },
        .host_id = 0,
        .host_index = removed_host_index,
        .host_snapshot = try HostSnapshot.init(std.testing.allocator, .{ .name = "temporary target", .host = &endpoint, .port = 2222, .user = "operator" }),
        .root = undefined,
    };
    defer tab.host_snapshot.?.deinit();
    const owner = tab.content_owner;
    @memset(&endpoint, 'x');
    try std.testing.expectEqualStrings("frozen.example", tab.temporaryHost().?.host);
    try std.testing.expectEqual(@as(u16, 2222), tab.temporaryHost().?.port);
    tab.host_snapshot.?.value.protocol = .sftp;
    try std.testing.expectEqual(hosts_mod.Protocol.sftp, tab.temporaryHost().?.protocol);
    try std.testing.expect(tab.content_owner.eql(owner));
    tab.host_snapshot.?.value.connection_id = @fromBackingInt(41);
    try std.testing.expect(tab.temporaryHost() == null);
    tab.host_snapshot.?.value.connection_id = @fromBackingInt(0);
    tab.local = true;
    try std.testing.expect(tab.temporaryHost() == null);
    tab.local = false;
    tab.closing = true;
    try std.testing.expect(tab.temporaryHost() == null);
    tab.closing = false;
    tab.content_owner = .{ .card = .{ .slot = 3, .generation = 1 } };
    try std.testing.expect(tab.temporaryHost() == null);
    tab.content_owner = owner;
    var without_snapshot = tab;
    without_snapshot.host_snapshot = null;
    try std.testing.expect(without_snapshot.temporaryHost() == null);
}

test "tab and environment row states follow Pencil SHfTh and F0U1j" {
    // ZW4 / Tab normal lDeYm · hover Rq2G8 · press xOZyz · active I1ajLU.
    // zeditor tab rules: close follows pointer hover or keyboard focus on any tab,
    // active included; at rest it keeps its slot at opacity 0 (lDeYm Close).
    // hvc0K: tab cells abut; each surface is inset 2 inside its cell.
    try std.testing.expectEqual(@as(f32, 0), tab_styles.gap);
    try std.testing.expectEqual(@as(f32, 128), tab_styles.surfaceWidth(132));
    // One tab hint: lines are trimmed, empty lines dropped, repeats removed.
    var hint: std.ArrayList(u8) = .empty;
    defer hint.deinit(std.testing.allocator);
    for ([_][]const u8{ "prod-web-01", "", "prod-web-01 ", "deploy@192.0.2.10:22 · SSH", "在线" }) |line| try appendHintLine(std.testing.allocator, &hint, line);
    try std.testing.expectEqualStrings("prod-web-01\ndeploy@192.0.2.10:22 · SSH\n在线", hint.items);
    // Active tab content is transparent over the window background’s joined island plate.
    const strip_styles = @import("_tab_strip.yss.zig");
    const tokens = app_theme.widgetTheme(app_theme.currentName());
    try std.testing.expectEqual(@as(u8, 0), strip_styles.surface(.{ .width = 120 }, tokens).background.?.a);
    try std.testing.expect(ui.Color.eql(tokens.tokens.color.bg_hover, strip_styles.surface(.{ .width = 120, .state = .hover }, tokens).background.?));
    try std.testing.expect(ui.Color.eql(tokens.tokens.color.bg_active, strip_styles.surface(.{ .width = 120, .state = .press }, tokens).background.?));
    try std.testing.expectEqual(ui.Color.TRANSPARENT, strip_styles.surface(.{ .width = 120, .state = .active }, tokens).background.?);
    try std.testing.expectEqual(@as(f32, 33), strip_styles.surface(.{ .width = 120, .state = .active }, tokens).height.?.px);
    try std.testing.expectEqual(@as(f32, 30), strip_styles.surface(.{ .width = 120 }, tokens).height.?.px);
    try std.testing.expect(ui.Color.eql(app_theme.current().fg_2, strip_styles.title(.{ .width = 120 }, tokens).color));
    try std.testing.expect(ui.Color.eql(app_theme.current().fg_1, strip_styles.title(.{ .width = 120, .state = .hover }, tokens).color));
    // ZW4 / Project Row: 28 high, radius 6; press NQngd = pressed tint, active rQNox = list surface.
    const S = @import("../../shell/view/sidebar_styles.zig");
    try std.testing.expectEqual(@as(f32, 28), S.hostState(.normal).height.?.px);
    try std.testing.expectEqual(@as(u8, 0), S.hostState(.normal).background.?.a);
    try std.testing.expect(ui.Color.eql(app_theme.states().hover, S.hostState(.hover).background.?));
    try std.testing.expect(ui.Color.eql(app_theme.states().pressed, S.hostState(.press).background.?));
    try std.testing.expect(ui.Color.eql(app_theme.current().surface_1, S.hostState(.active).background.?));
    // ZW2 / Pane Header in split panes (Tc5cZ): focused title 600 fg_primary, resting 500 fg_secondary —
    // now `pane_header.yss` (Title / Type recipes), covered by the pane header UI test.
    // Pane meta "路径 · 列 × 行" (Tc5cZ): home shortened to ~; size only without OSC 7.
    var buffer: [128]u8 = undefined;
    try std.testing.expectEqualStrings("~/Projects/zerowork · 64 × 35", Workspace.formatPaneMeta(&buffer, "/Users/dev/Projects/zerowork", "/Users/dev", 64, 35));
    try std.testing.expectEqualStrings("/srv/app · 138 × 36", Workspace.formatPaneMeta(&buffer, "/srv/app", "/Users/dev", 138, 36));
    try std.testing.expectEqualStrings("/Users/developer · 80 × 24", Workspace.formatPaneMeta(&buffer, "/Users/developer", "/Users/dev", 80, 24));
    try std.testing.expectEqualStrings("64 × 16", Workspace.formatPaneMeta(&buffer, null, "/Users/dev", 64, 16));
}

test "first tab resizes an already laid out empty title strip" {
    const allocator = std.testing.allocator;
    var cx = try ui.Cx.init(allocator, std.testing.io);
    defer cx.deinit();
    const FractionalMeasure = struct {
        fn width(_: [*]const u8, _: usize, _: f32, _: u16, _: bool) f32 {
            return 52.676; // The saved Local title's fractional-width boundary.
        }
    };
    cx.text.measure_fn = FractionalMeasure.width;
    const scope = try ui.Scope.init(allocator, null, cx.owner);
    const root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    cx.root = root;
    const controls = try ui.box(cx, .{ .width = .fill(), .height = .{ .px = 46 }, .direction = .row, .align_items = .center, .gap = 6 }, .{});
    try root.appendChild(allocator, controls);
    const strip = try ui.box(cx, .{ .direction = .row, .align_items = .center, .gap = 6 }, .{});
    try controls.appendChild(allocator, strip);
    const config: config_mod.Config = .{};
    var workspace: Workspace = .{
        .allocator = allocator,
        .cx = cx,
        .scope = scope,
        .io = std.testing.io,
        .app_config = &config,
        .palette = Palette.fromTheme(),
        .registry = .{ .arena = std.heap.ArenaAllocator.init(allocator), .hosts = &.{} },
        .hosts_path = "",
        .sidebar_list = root,
        .tab_bar = strip,
        .model = .{ .allocator = allocator, .window = @fromBackingInt(1), .workspace = @fromBackingInt(1) },
        .terminal_area = root,
        .empty_state = root,
    };
    defer {
        scope.dispose();
        for (workspace.click_ctxs.items) |cell| allocator.destroy(cell);
        workspace.click_ctxs.deinit(allocator);
        workspace.tab_nodes.deinit(allocator);
        workspace.strip_advances.deinit(allocator);
        workspace.strip_widths.deinit(allocator);
        workspace.strip_grouped.deinit(allocator);
        workspace.tabs.deinit(allocator);
        workspace.model.deinit();
        workspace.registry.arena.deinit();
    }
    cx.setViewport(1440, 900);
    try workspace.renderTabBar();
    cx.layout();
    // 稿 3: with no tabs the strip is only the native “+”.
    try std.testing.expectEqual(tab_styles.new_tab_size, strip.globalRect().w);

    const tab_id: identity.TabId = @fromBackingInt(1);
    const owner: identity.ContentOwner = .{ .session = .{ .session_id = @fromBackingInt(91) } };
    var tab: SessionTab = .{ .id = 91, .tab_id = tab_id, .content_owner = owner, .host_id = 1, .host_index = 0, .host_snapshot = undefined, .root = root, .terminal = undefined };
    tab.setTitle(tab_naming.home_label);
    try workspace.model.append(tab_id, owner, tab.titleSlice());
    try workspace.tabs.append(allocator, &tab);
    try workspace.renderTabBar();
    cx.layout();
    const width = workspace.strip_geometry.content;
    try std.testing.expect(width >= tab_layout.minimum);
    // The strip ends with the native “+” (ghost sm, 24) 4 after the last tab.
    try std.testing.expectApproxEqAbs(width + 4 + workspace.strip_vm.?.new_tab.?.globalRect().w, strip.globalRect().w, 0.01);
    try std.testing.expectApproxEqAbs(width, workspace.strip_vm.?.viewport.?.globalRect().w, 0.01);
    // Island B v3 tab (Pencil `ZW4 / Tab` active): the only tab is active, so its
    // surface is the full 33pt strip height that joins the island, its title
    // is semibold (600), and the native xs close (20) sits 2pt from the right
    // edge, vertically centred in the 30pt surface row.
    try std.testing.expectApproxEqAbs(@as(f32, 33), workspace.tab_nodes.items[0].node.globalRect().h, 0.01);
    const tab_rect = workspace.tab_nodes.items[0].node.globalRect();
    const title_rect = workspace.tab_nodes.items[0].label.globalRect();
    try std.testing.expect(title_rect.w >= @as(f32, 52.676));
    try std.testing.expectEqual(@as(f32, 12), workspace.tab_nodes.items[0].label.getText().?.font_size);
    try std.testing.expectEqual(@as(u16, 600), workspace.tab_nodes.items[0].label.getText().?.font_weight);
    const close_rect = workspace.tab_nodes.items[0].close.parent.?.globalRect();
    try std.testing.expect(title_rect.x + title_rect.w <= close_rect.x);
    try std.testing.expectApproxEqAbs(tab_rect.x + tab_rect.w - 22, close_rect.x, 0.01);
    try std.testing.expectApproxEqAbs(tab_rect.y + (30 - 20) / 2, close_rect.y, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 20), close_rect.w, 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 20), close_rect.h, 0.01);
    const close_slot = workspace.tab_nodes.items[0].close.parent.?;
    // The active tab is transparent over the joined plate. The close button is
    // hidden at rest even on the active tab (slot kept: the title width above
    // already excludes it) and appears while the pointer is over the tab.
    try std.testing.expectEqual(@as(f32, 0), close_slot.getOpacity());
    try std.testing.expectEqual(ui.Color.TRANSPARENT, workspace.tab_nodes.items[0].node.getBackground());
    // hvc0K / ZW4 / Tab padding [0, 2, 3, 2]: the surface is inset 2 in its cell.
    const cell_rect = workspace.tab_nodes.items[0].holder.globalRect();
    try std.testing.expectApproxEqAbs(cell_rect.x + 2, tab_rect.x, 0.01);
    try std.testing.expectApproxEqAbs(cell_rect.w - 4, tab_rect.w, 0.01);
    // The 3pt foot below the surface is part of the tab: hovering it shows close.
    cx.handleMouseMove(tab_rect.x + 30, cell_rect.y + cell_rect.h - 1);
    cx.layout();
    try std.testing.expectEqual(@as(f32, 1), close_slot.getOpacity());
    try std.testing.expectEqual(ui.Color.TRANSPARENT, workspace.tab_nodes.items[0].node.getBackground());
    cx.handleMouseMove(close_rect.x + 10, close_rect.y + 10);
    const Sink = struct {
        calls: usize = 0,
        tab: ?identity.TabId = null,
        fn close(raw: ?*anyopaque, id: identity.TabId, _: identity.ContentOwner) CloseResult {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.calls += 1;
            self.tab = id;
            return .awaiting;
        }
    };
    var sink: Sink = .{};
    workspace.close_bridge = .{ .context = &sink, .request_close = Sink.close };
    cx.handleMouseDown(close_rect.x + 10, close_rect.y + 10, .{});
    cx.handleMouseUp(close_rect.x + 10, close_rect.y + 10);
    try std.testing.expectEqual(@as(usize, 1), sink.calls);
    try std.testing.expectEqual(tab_id, sink.tab.?);
    try std.testing.expect(tab.closing);
    try std.testing.expect(workspace.drag_binding == null);
    try std.testing.expect(workspace.rename_request == null);
    try std.testing.expectEqual(@as(?usize, null), workspace.active_tab);
}

test "tab node binding follows the strip's mounted rows when the rebuild runs inside a reactive batch" {
    // Workspace rebuilds its strip from its after-layout hook, and zenit runs those hooks inside the
    // reactive owner's batch (cx_render.zig runAfterLayoutHooks): the strip's rows mount when the
    // batch ends, after renderTabBar has returned. `tab_nodes` (the tab id → mounted node binding the
    // chrome's identity regions and session-card anchors read) must still name the mounted rows.
    const allocator = std.testing.allocator;
    var cx = try ui.Cx.init(allocator, std.testing.io);
    defer cx.deinit();
    const scope = try ui.Scope.init(allocator, null, cx.owner);
    const root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    cx.root = root;
    const strip = try ui.box(cx, .{ .direction = .row, .align_items = .center, .gap = 6 }, .{});
    try root.appendChild(allocator, strip);
    const config: config_mod.Config = .{};
    var workspace: Workspace = .{
        .allocator = allocator,
        .cx = cx,
        .scope = scope,
        .io = std.testing.io,
        .app_config = &config,
        .palette = Palette.fromTheme(),
        .registry = .{ .arena = std.heap.ArenaAllocator.init(allocator), .hosts = &.{} },
        .hosts_path = "",
        .sidebar_list = root,
        .tab_bar = strip,
        .model = .{ .allocator = allocator, .window = @fromBackingInt(1), .workspace = @fromBackingInt(1) },
        .terminal_area = root,
        .empty_state = root,
    };
    defer {
        scope.dispose();
        for (workspace.click_ctxs.items) |cell| allocator.destroy(cell);
        workspace.click_ctxs.deinit(allocator);
        workspace.tab_nodes.deinit(allocator);
        workspace.strip_advances.deinit(allocator);
        workspace.strip_widths.deinit(allocator);
        workspace.strip_grouped.deinit(allocator);
        workspace.tabs.deinit(allocator);
        workspace.model.deinit();
        workspace.registry.arena.deinit();
    }
    cx.setViewport(1440, 900);
    try workspace.renderTabBar();
    cx.layout();
    var tabs: [2]SessionTab = undefined;
    for (&tabs, 0..) |*tab, index| {
        const tab_id: identity.TabId = @fromBackingInt(index + 1);
        const owner: identity.ContentOwner = .{ .session = .{ .session_id = @fromBackingInt(91 + index) } };
        tab.* = .{ .id = 91 + index, .tab_id = tab_id, .content_owner = owner, .host_id = 1, .host_index = 0, .host_snapshot = undefined, .root = root, .terminal = undefined };
        tab.setTitle(if (index == 0) "First" else "Second");
        try workspace.model.append(tab_id, owner, tab.titleSlice());
        try workspace.tabs.append(allocator, tab);
        // The rebuild as the after-layout hook runs it.
        cx.owner.beginBatch();
        try workspace.renderTabBar();
        cx.owner.endBatch();
        cx.layout();
        try std.testing.expectEqual(index + 1, workspace.tab_nodes.items.len);
        for (workspace.tab_nodes.items, 0..) |bound, at| {
            try std.testing.expectEqual(tabs[at].tab_id, bound.tab_id);
            try std.testing.expect(bound.node.isDisplayedInTree());
            try std.testing.expect(bound.node.globalRect().w > 0);
        }
    }
    // Removing a tab unmounts its row; the binding never keeps the removed row's nodes.
    _ = workspace.tabs.orderedRemove(0);
    try workspace.model.completeClose(tabs[0].tab_id, tabs[0].content_owner);
    cx.owner.beginBatch();
    try workspace.renderTabBar();
    cx.owner.endBatch();
    cx.layout();
    try std.testing.expectEqual(@as(usize, 1), workspace.tab_nodes.items.len);
    try std.testing.expectEqual(tabs[1].tab_id, workspace.tab_nodes.items[0].tab_id);
    try std.testing.expect(workspace.tab_nodes.items[0].node.isDisplayedInTree());
}

test "chrome identity region settles over the active tab in the frame its strip row mounts" {
    // The tab menu's “会话详情” opens through the identity region over the active tab (nav_host.zig
    // openPendingIdentity). A tab that becomes active while its strip row is (re)built from an
    // after-layout hook must get its region laid out over its surface within that frame, and the
    // chrome must say so (identityRegion) instead of leaving the opener to retry frames.
    const Chrome = @import("workspace_chrome.zig");
    const allocator = std.testing.allocator;
    var cx = try ui.Cx.init(allocator, std.testing.io);
    defer cx.deinit();
    const scope = try ui.Scope.init(allocator, null, cx.owner);
    const root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    cx.root = root;
    const bar = try ui.box(cx, .{ .width = .fill(), .height = .{ .px = 46 }, .direction = .row, .align_items = .end, .gap = 6 }, .{});
    try root.appendChild(allocator, bar);
    const capsule = try ui.box(cx, .{ .direction = .row }, .{});
    try bar.appendChild(allocator, capsule);
    const strip = try ui.box(cx, .{ .direction = .row, .align_items = .center, .gap = 6 }, .{});
    try capsule.appendChild(allocator, strip);
    const config: config_mod.Config = .{};
    var workspace: Workspace = .{
        .allocator = allocator,
        .cx = cx,
        .scope = scope,
        .io = std.testing.io,
        .app_config = &config,
        .palette = Palette.fromTheme(),
        .registry = .{ .arena = std.heap.ArenaAllocator.init(allocator), .hosts = &.{} },
        .hosts_path = "",
        .sidebar_list = root,
        .tab_bar = strip,
        .model = .{ .allocator = allocator, .window = @fromBackingInt(1), .workspace = @fromBackingInt(1) },
        .terminal_area = root,
        .empty_state = root,
    };
    defer {
        scope.dispose();
        for (workspace.click_ctxs.items) |cell| allocator.destroy(cell);
        workspace.click_ctxs.deinit(allocator);
        workspace.tab_nodes.deinit(allocator);
        workspace.strip_advances.deinit(allocator);
        workspace.strip_widths.deinit(allocator);
        workspace.strip_grouped.deinit(allocator);
        workspace.tabs.deinit(allocator);
        workspace.model.deinit();
        workspace.registry.arena.deinit();
    }
    cx.setViewport(1440, 900);
    try cx.setTestFrameStep(16);
    const Frame = struct {
        fn run(c: *ui.Cx) void {
            c.advanceFrameClock();
            c.layout();
            _ = c.render();
        }
    };
    const Fold = struct {
        fn fit(_: *anyopaque, _: f32) Chrome.ToolFold.Fit {
            return .{ .width = 0, .changed = false };
        }
    };
    var fold_context: u8 = 0;
    const chrome = try Chrome.View.mount(cx, scope, &workspace, bar, capsule, .{ .context = &fold_context, .fit = Fold.fit });
    const remote = try ui.box(cx, .{}, .{});
    const local = try ui.box(cx, .{}, .{});
    try chrome.identitiesAtTabs(remote, local);
    // Workspace's poll hook (PollHook.run): the strip is rebuilt from an after-layout hook,
    // registered after the chrome's here (the later of the two orders for the chrome).
    const Rebuild = struct {
        workspace: *Workspace,
        fn run(raw: *anyopaque, _: u8, _: bool) ui.AfterLayoutResult {
            const self: *@This() = @ptrCast(@alignCast(raw));
            if (!self.workspace.tab_rebuild_pending) return .done;
            self.workspace.tab_rebuild_pending = false;
            self.workspace.renderTabBar() catch unreachable;
            return .needs_layout;
        }
    };
    var rebuild: Rebuild = .{ .workspace = &workspace };
    try cx.addAfterLayoutHook(&rebuild, Rebuild.run);
    defer cx.removeAfterLayoutHook(&rebuild);
    workspace.tab_rebuild_pending = true;
    Frame.run(cx);
    try std.testing.expectEqual(@as(usize, 0), workspace.tab_nodes.items.len);

    var tabs: [2]SessionTab = undefined;
    for (&tabs, 0..) |*tab, index| {
        const tab_id: identity.TabId = @fromBackingInt(index + 1);
        const owner: identity.ContentOwner = .{ .session = .{ .session_id = @fromBackingInt(91 + index) } };
        tab.* = .{ .id = 91 + index, .tab_id = tab_id, .content_owner = owner, .host_id = 1, .host_index = 0, .host_snapshot = undefined, .root = root, .terminal = undefined, .local = index == 1 };
        tab.setTitle(if (index == 0) "SSH tab" else "Local tab");
        try workspace.model.append(tab_id, owner, tab.titleSlice());
        try workspace.tabs.append(allocator, tab);
        // The new tab becomes the active one; its row is built by the next frame's hook.
        try workspace.model.activate(tab_id);
        workspace.active_tab = index;
        workspace.tab_rebuild_pending = true;
        try std.testing.expect(chrome.identityRegion(tab_id) == .settling);
        Frame.run(cx);
        const shown_region = if (index == 1) local else remote;
        const hidden_region = if (index == 1) remote else local;
        switch (chrome.identityRegion(tab_id)) {
            .shown => |node| try std.testing.expectEqual(shown_region, node),
            else => return error.TestUnexpectedResult,
        }
        try std.testing.expect(hidden_region.style.display == .none);
        var surface: ?ui.ComputedRect = null;
        for (workspace.tab_nodes.items) |bound| if (bound.tab_id == tab_id) {
            surface = bound.node.globalRect();
        };
        const expected = surface orelse return error.TestUnexpectedResult;
        const actual = shown_region.globalRect();
        try std.testing.expect(expected.w > 0 and expected.h > 0);
        try std.testing.expectApproxEqAbs(expected.x, actual.x, 0.5);
        try std.testing.expectApproxEqAbs(expected.y, actual.y, 0.5);
        try std.testing.expectApproxEqAbs(expected.w, actual.w, 0.5);
        try std.testing.expectApproxEqAbs(expected.h, actual.h, 0.5);
        // The previous tab is no longer the one the regions stand over.
        if (index == 1) try std.testing.expect(chrome.identityRegion(tabs[0].tab_id) == .settling);
    }
}

test "Local presentation has independent owners and keeps ended output beneath its banner" {
    const allocator = std.testing.allocator;
    const cx = try ui.Cx.init(allocator, std.testing.io);
    defer cx.deinit();
    const scope = try ui.Scope.init(allocator, null, cx.owner);
    defer scope.dispose();
    const root = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .direction = .column }, .{});
    cx.root = root;
    const strip = try ui.box(cx, .{ .width = .fill(), .height = .{ .px = 46 }, .flex_shrink = 0 }, .{});
    try root.appendChild(allocator, strip);
    const area = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .flex = 1, .direction = .column }, .{});
    try root.appendChild(allocator, area);
    const empty = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .position = .absolute }, .{});
    try area.appendChild(allocator, empty);
    const sidebar = try ui.box(cx, .{ .display = .none }, .{});
    try root.appendChild(allocator, sidebar);
    var config: config_mod.Config = .{};
    config.ui.timestamp_gutter = true;
    const workspace = try allocator.create(Workspace);
    workspace.* = .{
        .allocator = allocator,
        .cx = cx,
        .scope = scope,
        .io = std.testing.io,
        .app_config = &config,
        .palette = Palette.fromTheme(),
        .registry = .{ .arena = std.heap.ArenaAllocator.init(allocator), .hosts = &.{} },
        .hosts_path = "",
        .sidebar_list = sidebar,
        .tab_bar = strip,
        .model = .{ .allocator = allocator, .window = @fromBackingInt(1), .workspace = @fromBackingInt(1) },
        .terminal_area = area,
        .empty_state = empty,
    };
    try scope.onCleanup(Workspace, workspace, Workspace.cleanup);
    cx.setViewport(1194, 800);
    const CommandSink = struct {
        calls: usize = 0,
        fn command(raw: ?*anyopaque, text: []const u8, executed: bool) void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            if (executed and std.mem.eql(u8, text, "@grp Acceptance")) self.calls += 1;
        }
    };
    var command_sink: CommandSink = .{};
    workspace.command_bridge = .{ .context = &command_sink, .on_command = CommandSink.command };
    const first_owner: identity.SessionHandle = .{ .session_id = @fromBackingInt(41) };
    const second_owner: identity.SessionHandle = .{ .session_id = @fromBackingInt(42) };
    const first = try workspace.createLocalSessionDirect(first_owner);
    const local_command_observer = workspace.sessionTab(first).?.terminal.?.palette_observer orelse return error.LocalCommandObserverMissing;
    local_command_observer.on_command(local_command_observer.context, "@grp Acceptance", true);
    try std.testing.expectEqual(@as(usize, 1), command_sink.calls);
    try std.testing.expect(workspace.sessionTab(first).?.terminal.?.local_state.timestamp_gutter);
    config.ui.timestamp_gutter = false;
    const second = try workspace.createLocalSessionDirect(second_owner);
    try std.testing.expect(!workspace.sessionTab(second).?.terminal.?.local_state.timestamp_gutter);
    try std.testing.expect(first != second);
    const MenuSink = struct {
        calls: usize = 0,
        index: ?usize = null,
        anchor: ui.ComputedRect = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
        fn fire(raw: ?*anyopaque, trigger: MenuBridge.Trigger, _: usize, index: ?usize, _: bool, anchor: ui.ComputedRect) void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            if (trigger != .terminal_middle_click) return;
            self.calls += 1;
            self.index = index;
            self.anchor = anchor;
        }
    };
    var menu_sink: MenuSink = .{};
    workspace.menu_bridge = .{ .context = &menu_sink, .fire = MenuSink.fire };
    // The second pane is active, but the captured first owner stays first.
    Workspace.onTerminalServiceMenu(workspace, first_owner, 213, 47);
    try std.testing.expectEqual(@as(usize, 1), menu_sink.calls);
    try std.testing.expectEqual(@as(?usize, 0), menu_sink.index);
    try std.testing.expectEqual(ui.ComputedRect{ .x = 213, .y = 47, .w = 0, .h = 0 }, menu_sink.anchor);
    Workspace.onTerminalServiceMenu(workspace, try first_owner.nextGeneration(), 99, 99);
    try std.testing.expectEqual(@as(usize, 1), menu_sink.calls);
    try std.testing.expect(workspace.tabs.items[0].tab_id != workspace.tabs.items[1].tab_id);
    const tab = workspace.sessionTab(second).?;
    try std.testing.expect(tab.local and tab.host_snapshot == null);
    try std.testing.expect(tab.content_owner.eql(.{ .session = second_owner }));
    try std.testing.expect(workspace.tabHost(1) == null);
    cx.layout();
    const pane = tab.root.globalRect();
    const starting = tab.local_banner.?.globalRect();
    try std.testing.expectApproxEqAbs(pane.x + 16, starting.x, 0.1);
    try std.testing.expectApproxEqAbs(pane.y + 16, starting.y, 0.1);
    try std.testing.expectApproxEqAbs(pane.w - 32, starting.w, 0.1);
    try std.testing.expectApproxEqAbs(@as(f32, 64), starting.h, 0.1);
    try std.testing.expectApproxEqAbs(pane.y, tab.terminal.?.root.globalRect().y, 0.1);
    workspace.updateLocalState(second, .failed, "无法启动 /bin/zsh · EACCES");
    cx.layout();
    try std.testing.expectApproxEqAbs(@as(f32, 64), tab.local_banner.?.globalRect().h, 0.1);
    try std.testing.expectApproxEqAbs(pane.y + 64, tab.terminal.?.root.globalRect().y, 0.1);
    try std.testing.expect(tab.local_retry.?.style.display != .none);
    try std.testing.expectEqualStrings("本地终端启动失败", tab.local_message.?.getText().?.content);
    try std.testing.expect(std.mem.indexOf(u8, tab.local_detail.?.getText().?.content, "EACCES") != null);
    try std.testing.expect(tab.local_cancel.?.style.display == .none);
    try workspace.renameTab(1, "我的终端");
    workspace.updateLocalState(second, .exited, "本地 zsh 已退出 · exit 0");
    try std.testing.expectEqualStrings("我的终端", workspace.model.tabs.items[1].name());
    try std.testing.expectEqualStrings("本地终端已退出", tab.local_message.?.getText().?.content);
    try std.testing.expectEqualStrings("历史输出仍可查看 · 退出码 0", tab.local_detail.?.getText().?.content);
    try std.testing.expect(tab.local_reconnect.?.style.display != .none);
    try std.testing.expect(tab.local_close.?.style.display != .none);
    try std.testing.expect(tab.local_retry.?.style.display == .none);
    const RetrySink = struct {
        calls: usize = 0,
        id: ?SessionId = null,
        fn retry(raw: ?*anyopaque, id: SessionId) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.calls += 1;
            self.id = id;
        }
    };
    var retry_sink: RetrySink = .{};
    workspace.session_bridge = .{ .context = &retry_sink, .retry_local = RetrySink.retry };
    // Rebuilding tabs must not free the still visible pane's callback context.
    try workspace.renderTabBar();
    try workspace.renderTabBar();
    tab.local_reconnect.?.behavior.events.on_click.?.invoke();
    try std.testing.expectEqual(@as(usize, 1), retry_sink.calls);
    try std.testing.expectEqual(second, retry_sink.id.?);
    try std.testing.expectEqual(@as(usize, 2), workspace.tabs.items.len);
    workspace.updateLocalState(second, .starting, "");
    try std.testing.expect(tab.local_reconnect.?.style.display == .none);
    try std.testing.expectError(error.LifecycleDoesNotAllowRetry, workspace.retryLocalSession(second));
    workspace.updateLocalState(second, .failed, "retry failed");
    tab.local_retry.?.behavior.events.on_click.?.invoke();
    try std.testing.expectEqual(@as(usize, 2), retry_sink.calls);
    workspace.removeClosedTab(1);
    try std.testing.expectEqual(@as(usize, 1), workspace.tabs.items.len);
    try std.testing.expectEqual(first, workspace.tabs.items[0].id);
}

test "rebuilt tab bar invalidates older click cells" {
    // Contract for the trampoline guard: tab click cells carry the bar
    // generation they were built for; a rebuild bumps the workspace
    // generation so in-flight clicks routed through removed nodes become
    // no-ops instead of dereferencing freed/stale state (the selectTab
    // SIGSEGV on tab close).
    var workspace: Workspace = undefined;
    workspace.group_views = .empty;
    workspace.group_roster = null;
    workspace.active_group_view = null;
    workspace.external_auth = null;
    workspace.tab_generation = 2;
    const live_cell: ClickCtx = .{ .workspace = undefined, .index = 0, .tab_generation = 2 };
    const stale_cell: ClickCtx = .{ .workspace = undefined, .index = 0, .tab_generation = 1 };
    try std.testing.expect(!workspace.isStaleTabCell(&live_cell));
    try std.testing.expect(workspace.isStaleTabCell(&stale_cell));
}

test "tab title validation trims whitespace and rejects unusable names" {
    try std.testing.expectEqualStrings("prod", try normalizeTabName("  prod\t"));
    try std.testing.expectError(error.EmptyName, normalizeTabName(" \t\n"));
    try std.testing.expectError(error.InvalidName, normalizeTabName("prod\nnode"));
    var oversized: [65]u8 = undefined;
    @memset(&oversized, 'x');
    try std.testing.expectError(error.NameTooLong, normalizeTabName(&oversized));
}

test "reconnect lifecycle is ended-only and rolls back after spawn failure" {
    // Workspace.reconnectTab must never start a second transport for an
    // active/reconnecting tab.  Once the replacement spawn fails, the
    // read-only tombstone is restored to an ended state so the user can try
    // again and the original terminal remains available.
    var tombstone: Tombstone = .{};
    try std.testing.expect(!tombstone.beginReconnect());

    tombstone.end("connection lost");
    try std.testing.expect(tombstone.beginReconnect());
    try std.testing.expect(!tombstone.beginReconnect());

    // This is the rollback performed by reconnectTab's spawnSession error
    // path.  It must make the reconnect action reachable again, rather than
    // leaving the source tab permanently in "正在重连…".
    tombstone.end("reconnect failed");
    try std.testing.expectEqual(@TypeOf(tombstone.state).ended, tombstone.state);
    try std.testing.expect(tombstone.canReconnect());
    try std.testing.expectEqualStrings("重新连接", tombstone.reconnectLabel());
}

test "reconnect uses an owned host snapshot after source storage changes" {
    const source = hosts_mod.HostConfig{
        .name = "original",
        .host = "host.example",
        .user = "alice",
        .password = "secret",
        .jump_chain = &.{"bastion.example"},
    };
    var snapshot = try HostSnapshot.init(std.testing.allocator, source);
    defer snapshot.deinit();

    // Simulate the registry/asset being edited or removed while reconnect is
    // queued.  The queued operation must continue to target its retained
    // values, rather than reading a mutable host-index entry.
    try std.testing.expectEqualStrings("original", snapshot.value.name);
    try std.testing.expectEqualStrings("host.example", snapshot.value.host);
    try std.testing.expectEqualStrings("alice", snapshot.value.user);
    try std.testing.expectEqualStrings("secret", snapshot.value.password.?);
    try std.testing.expectEqualStrings("bastion.example", snapshot.value.jump_chain[0]);
}

test "connection job resolves only persistent route IDs including same named hops" {
    var target: hosts_mod.HostConfig = .{ .connection_id = @fromBackingInt(10), .revision = 2, .name = "target", .host = "target.test", .user = "test", .route = &.{ @fromBackingInt(21), @fromBackingInt(20) }, .jump_chain = &.{ "stale display", "stale display" } };
    const registry = [_]hosts_mod.HostConfig{
        .{ .connection_id = @fromBackingInt(20), .revision = 3, .name = "same", .host = "first.test", .user = "jump", .strict_host_key_checking = false },
        .{ .connection_id = @fromBackingInt(21), .revision = 4, .name = "same", .host = "second.test", .user = "jump" },
    };
    const hops = try Workspace.ConnectJob.resolvedHops(std.testing.allocator, target, &registry);
    defer std.testing.allocator.free(hops);
    try std.testing.expectEqual(@as(usize, 2), hops.len);
    try std.testing.expectEqualStrings("second.test", hops[0].host);
    try std.testing.expectEqualStrings("first.test", hops[1].host);
    try std.testing.expectEqual(@as(u64, 4), hops[0].revision);
    try std.testing.expect(!hops[1].strict_host_key_checking);
    target.route = &.{@fromBackingInt(22)};
    target.jump_chain = &.{"same"};
    try std.testing.expectError(error.MissingRouteReference, Workspace.ConnectJob.resolvedHops(std.testing.allocator, target, &registry));
    target.route = &.{};
    try std.testing.expectError(error.UnmigratedRoute, Workspace.ConnectJob.resolvedHops(std.testing.allocator, target, &registry));
}

test "connection job runtime target retains the actual host operation and frozen identity" {
    const key: OperationKey = .{ .owner = .{ .session = .{ .session_id = @fromBackingInt(99), .generation = 4 } }, .operation_id = 81, .attempt_id = 3 };
    var job: Workspace.ConnectJob = undefined;
    job.bootstrap = null;
    job.ticket = .{ .session_id = 7, .generation = 1 };
    job.operation_key = key;
    job.initial_input = null;
    job.progress = .{};
    job.progress.begin(3);
    job.host_snapshot = try HostSnapshot.init(std.testing.allocator, .{ .connection_id = @fromBackingInt(10), .revision = 8, .name = "target", .host = "target.test", .user = "target", .auth_mode = .password, .strict_host_key_checking = false, .route = &.{@fromBackingInt(20)} });
    defer job.host_snapshot.deinit();
    job.jump_snapshot = try lifecycle.Snapshot([]const hosts_mod.HostConfig).init(std.testing.allocator, &.{.{ .connection_id = @fromBackingInt(20), .revision = 6, .name = "jump", .host = "hop.test", .user = "jump", .strict_host_key_checking = true }});
    defer job.jump_snapshot.deinit();
    const target = @import("../../../plugins/ssh/connect_job.zig").runtimeTarget(&job);
    try std.testing.expect(target.operation_key.?.eql(key));
    try std.testing.expectEqualDeep(identity.AssetOwner{ .id = @fromBackingInt(10), .revision = 8 }, target.source_owner.?);
    try std.testing.expect(!target.strict_host_key_checking);
    try std.testing.expectEqual(hosts_mod.AuthMode.password, target.auth_mode);
    try std.testing.expectEqualSlices(identity.ConnectionId, &.{@fromBackingInt(20)}, target.route);
    try std.testing.expectEqual(@as(u64, 6), target.jump_hosts[0].revision);
    try std.testing.expect(target.jump_hosts[0].strict_host_key_checking);
    try std.testing.expect(target.keyboard_bridge.? == &job.auth_bridge);
    var options_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer options_arena.deinit();
    const options = try @import("../host/session_runtime.zig").prepareConnectionOptions(options_arena.allocator(), .{}, target, .session);
    try std.testing.expectEqual(@as(usize, 2), options.len);
    for (options, 0..) |option, hop| {
        const observer = option.progress_observer.?;
        observer.callback(observer.context, .{ .attempt = 3, .hop = hop, .hop_count = 2, .host = option.host, .port = option.port, .phase = .transport, .status = .started });
    }
    const recorded = job.progress.snapshot();
    try std.testing.expectEqual(@as(usize, 2), recorded.count);
    try std.testing.expectEqualStrings("hop.test", recorded.entries[0].hostSlice());
    try std.testing.expectEqualStrings("target.test", recorded.entries[1].hostSlice());
    job.host_snapshot.value.connection_id = @fromBackingInt(0);
    job.operation_key = null;
    const legacy = @import("../../../plugins/ssh/connect_job.zig").runtimeTarget(&job);
    try std.testing.expect(legacy.source_owner == null);
    try std.testing.expect(legacy.operation_key == null);
    var unused: Workspace = undefined;
    try std.testing.expectError(error.InvalidOperation, unused.createSessionDirectForOperation(job.host_snapshot.value, 7, 0, "", .{ .owner = .app, .operation_id = 1 }));
}

test "SSH attachment gate rejects stale operation generation and cancelled jobs" {
    const handle: identity.SessionHandle = .{ .session_id = @fromBackingInt(99), .generation = 4 };
    const key: OperationKey = .{ .owner = .{ .session = handle }, .operation_id = 81, .attempt_id = 3 };
    var worker: @import("../../../vt/ssh_worker.zig").SshWorker = undefined;
    worker.execution = null;
    worker.execution_mutex = .unlocked;
    worker.execution_recording = null;
    worker.execution_control = null;
    worker.execution_deployment = null;
    worker.presentation_attached = .init(false);
    var native_runtime: @import("../host/session_runtime.zig").SessionRuntime = undefined;
    native_runtime.torn_down = false;
    native_runtime.worker = &worker;
    var worker_thread: @import("../../../vt/ssh_worker_thread.zig").Thread = undefined;
    worker_thread.reconnect_control = @import("../../../vt/reconnect.zig").Control.init(key);
    worker_thread.worker = &worker;
    native_runtime.thread = &worker_thread;
    var runtime = @import("../../../plugins/ssh/runtime_binding.zig").borrow(&native_runtime);
    var tab: SessionTab = undefined;
    tab.id = 7;
    tab.generation = 1;
    tab.content_owner = .{ .session = handle };
    tab.runtime = &runtime;
    var job: Workspace.ConnectJob = undefined;
    job.bootstrap = null;
    job.ticket = tab.ticket();
    job.operation_key = key;
    job.cancelled = .init(false);
    var tabs = [_]*SessionTab{&tab};
    var jobs = [_]*Workspace.ConnectJob{&job};
    var workspace: Workspace = undefined;
    workspace.group_views = .empty;
    workspace.group_roster = null;
    workspace.active_group_view = null;
    workspace.external_auth = null;
    workspace.tabs = .empty;
    workspace.tabs.items = &tabs;
    workspace.tabs.capacity = tabs.len;
    workspace.connect_jobs = .empty;
    workspace.connect_jobs.items = &jobs;
    workspace.connect_jobs.capacity = jobs.len;
    var stale = key;
    stale.operation_id += 1;
    try std.testing.expect(!workspace.acknowledgeSessionAttached(tab.id, tab.generation, stale));
    try std.testing.expect(!workspace.acknowledgeSessionAttached(tab.id, tab.generation + 1, key));
    try std.testing.expect(!worker.presentation_attached.load(.acquire));
    job.cancelled.store(true, .release);
    try std.testing.expect(!workspace.acknowledgeSessionAttached(tab.id, tab.generation, key));
    job.cancelled.store(false, .release);
    try std.testing.expect(workspace.acknowledgeSessionAttached(tab.id, tab.generation, key));
    try std.testing.expect(worker.presentation_attached.load(.acquire));
    try std.testing.expect(job.progress_dismissed);
    worker.presentation_attached.store(false, .release);
    try std.testing.expect(workspace.nextConnectionPresentationKey() == null);
}

test "SSH cancellation reopens an installed jobs cleanup drain only once" {
    var runtime: SessionRuntime = undefined;
    var job: Workspace.ConnectJob = undefined;
    job.bootstrap = null;
    job.ticket = .{ .session_id = 7, .generation = 1 };
    job.cancelled = .init(false);
    job.drained = true;
    job.runtime = &runtime;
    job.host_key_bridge = .{};
    job.auth_bridge = .{};
    var jobs = [_]*Workspace.ConnectJob{&job};
    var workspace: Workspace = undefined;
    workspace.group_views = .empty;
    workspace.group_roster = null;
    workspace.active_group_view = null;
    workspace.external_auth = null;
    workspace.connect_jobs = .empty;
    workspace.connect_jobs.items = &jobs;
    workspace.connect_jobs.capacity = jobs.len;
    workspace.host_key_job = null;
    workspace.auth_job = null;
    workspace.cancelSessionCreation(7);
    try std.testing.expect(!job.drained);
    job.drained = true; // the real destructor has subsequently been drained
    workspace.cancelSessionCreation(7);
    try std.testing.expect(job.drained);
}

test "cancelled initial connection retires placeholder after cleanup without replacing reconnect output" {
    const allocator = std.testing.allocator;
    const cx = try ui.Cx.init(allocator, std.testing.io);
    defer cx.deinit();
    const scope = try ui.Scope.init(allocator, null, cx.owner);
    defer scope.dispose();
    const Hooks = struct {
        fn ignore(_: *anyopaque, _: u64) void {}
    };
    cx.root = try ui.box(cx, local_styles.pane(), .{});
    const terminal = try TerminalViewNode.mount(cx);
    var tab: SessionTab = undefined;
    tab.id = 7;
    tab.generation = 1;
    tab.runtime = null;
    tab.terminal = terminal;
    tab.remote_notice = try RemoteNotice.View.mount(cx, scope, cx.root.?, .{ .context = &tab, .session_id = tab.id, .reconnect = Hooks.ignore, .close = Hooks.ignore });
    try cx.root.?.appendChild(allocator, terminal.root);
    defer tab.terminal.?.releaseBuffers(cx);
    var job: Workspace.ConnectJob = undefined;
    job.bootstrap = null;
    job.ticket = tab.ticket();
    job.cancelled = .init(true);
    job.ready = .init(false);
    job.drained = false;
    job.cleanup_unknown = false;
    job.runtime_scope_owned = false;
    job.runtime = null;
    job.thread = null;
    job.resource_ledger = try ResourceLedger.init(null, 1);
    var jobs = [_]*Workspace.ConnectJob{&job};
    var tabs = [_]*SessionTab{&tab};
    var workspace: Workspace = undefined;
    workspace.group_views = .empty;
    workspace.group_roster = null;
    workspace.active_group_view = null;
    workspace.cx = cx;
    workspace.allocator = allocator;
    workspace.connect_jobs = .empty;
    workspace.connect_jobs.items = &jobs;
    workspace.tabs = .empty;
    workspace.tabs.items = &tabs;
    workspace.shutting_down = false;
    workspace.active_tab = 0;
    workspace.status_node = null;
    workspace.command_output = null;
    workspace.status_feedback = null;
    workspace.session_bridge = .{};
    try tab.terminal.?.setOutput(cx, "正在连接…");
    workspace.drainResults(true);
    try std.testing.expectEqualStrings("正在连接…", tab.terminal.?.row_texts[0]);
    job.ready.store(true, .release);
    workspace.drainResults(true);
    try std.testing.expect(job.drained);
    try std.testing.expectEqualStrings("", tab.terminal.?.row_texts[0]);
    try std.testing.expectEqual(RemoteNotice.State.cancelled, tab.remote_notice.?.snapshot.?.state);
    try std.testing.expectEqualStrings("连接已取消", tab.remote_notice.?.title_node.getText().?.content);
    // A completed older generation must not change the replacement tab.
    try tab.terminal.?.setOutput(cx, "new attempt");
    tab.generation += 1;
    job.drained = false;
    workspace.drainResults(true);
    try std.testing.expectEqualStrings("new attempt", tab.terminal.?.row_texts[0]);
    // Cancelled reconnects keep their already installed terminal transcript.
    tab.generation = job.ticket.generation;
    var runtime: SessionRuntime = undefined;
    tab.runtime = &runtime;
    job.drained = false;
    try tab.terminal.?.setOutput(cx, "existing transcript");
    workspace.drainResults(true);
    try std.testing.expectEqualStrings("existing transcript", tab.terminal.?.row_texts[0]);
}

test "connection job preserves known host load errors instead of inventing unknown" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "known_hosts", .data = "malformed\n" });
    try std.testing.expectError(error.InvalidKnownHosts, Workspace.ConnectJob.loadHostKeyStore(std.testing.allocator, std.testing.io, tmp.dir, "known_hosts"));
    var missing = try Workspace.ConnectJob.loadHostKeyStore(std.testing.allocator, std.testing.io, tmp.dir, "missing_known_hosts");
    defer missing.deinit();
    try std.testing.expectEqual(@as(usize, 0), missing.records.items.len);
    try std.testing.expectEqualStrings("missing_known_hosts", missing.persist_path.?);
}

test "connection job loads the selected OpenSSH path without migrating private TSV trust" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var home_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const home_len = try tmp.dir.realPath(std.testing.io, &home_buffer);
    const PathsType = @import("../../../config/paths.zig").Paths;
    var paths = try PathsType.fromHome(std.testing.allocator, home_buffer[0..home_len]);
    defer paths.deinit();
    const legacy = "host.test\t22\tssh-ed25519\tSHA256:legacy-fingerprint-only\n";
    try tmp.dir.createDirPath(std.testing.io, ".zerowork");
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = ".zerowork/known_hosts", .data = legacy });
    var missing = try Workspace.ConnectJob.loadHostKeyStore(std.testing.allocator, std.testing.io, std.Io.Dir.cwd(), paths.known_hosts);
    defer missing.deinit();
    try std.testing.expectEqual(@as(usize, 0), missing.records.items.len);
    try std.testing.expectEqualStrings(paths.known_hosts, missing.persist_path.?);
    try std.testing.expectError(error.FileNotFound, tmp.dir.openFile(std.testing.io, ".ssh/known_hosts", .{}));
    const preserved = try tmp.dir.readFileAlloc(std.testing.io, ".zerowork/known_hosts", std.testing.allocator, .limited(4096));
    defer std.testing.allocator.free(preserved);
    try std.testing.expectEqualStrings(legacy, preserved);

    // Even an explicitly selected file cannot silently reinterpret old hashes
    // as OpenSSH key bodies or turn them into a trusted/unknown classification.
    try tmp.dir.createDirPath(std.testing.io, ".ssh");
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = ".ssh/known_hosts", .data = legacy });
    try std.testing.expectError(error.LegacyTrustMigrationRequired, Workspace.ConnectJob.loadHostKeyStore(std.testing.allocator, std.testing.io, std.Io.Dir.cwd(), paths.known_hosts));
    const rejected = try tmp.dir.readFileAlloc(std.testing.io, ".ssh/known_hosts", std.testing.allocator, .limited(4096));
    defer std.testing.allocator.free(rejected);
    try std.testing.expectEqualStrings(legacy, rejected);

    const instance_dir = try std.fs.path.join(std.testing.allocator, &.{ home_buffer[0..home_len], "isolated-instance" });
    defer std.testing.allocator.free(instance_dir);
    var isolated = try PathsType.fromDirectory(std.testing.allocator, instance_dir);
    defer isolated.deinit();
    var isolated_missing = try Workspace.ConnectJob.loadHostKeyStore(std.testing.allocator, std.testing.io, std.Io.Dir.cwd(), isolated.known_hosts);
    defer isolated_missing.deinit();
    try std.testing.expectEqual(@as(usize, 0), isolated_missing.records.items.len);
    try std.testing.expectEqualStrings(isolated.known_hosts, isolated_missing.persist_path.?);
}

test "稿 3 overflow: least recently used inactive tabs go into ⌄ n, the active tab stays" {
    const allocator = std.testing.allocator;
    const cx = try ui.Cx.init(allocator, std.testing.io);
    defer cx.deinit();
    var workspace: Workspace = undefined;
    workspace.group_views = .empty;
    workspace.group_roster = null;
    workspace.active_group_view = null;
    workspace.external_auth = null;
    workspace.allocator = allocator;
    workspace.cx = cx;
    workspace.model = .{ .allocator = allocator, .window = @fromBackingInt(1), .workspace = @fromBackingInt(1) };
    defer workspace.model.deinit();
    workspace.strip_widths = .empty;
    defer workspace.strip_widths.deinit(allocator);
    workspace.strip_advances = .empty;
    defer workspace.strip_advances.deinit(allocator);
    workspace.strip_grouped = .empty;
    defer workspace.strip_grouped.deinit(allocator);
    workspace.font_family_resolver = null;
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    for (1..11) |id| try workspace.model.append(@fromBackingInt(id), .{ .session = .{ .session_id = @fromBackingInt(id) } }, "long terminal session title");
    cx.setViewport(860, 480);
    for (1..11) |id| try workspace.model.activate(@fromBackingInt(id));
    try workspace.measureTabs(arena);
    try std.testing.expectEqual(tab_layout.Mode.overflow, workspace.strip_geometry.mode);
    try std.testing.expect(workspace.strip_geometry.hidden > 0);
    // Tab 10 is active and the most recent; tab 1 the oldest.
    try std.testing.expect(workspace.strip_shown[9]);
    try std.testing.expect(!workspace.strip_shown[0]);
    var shown_width: f32 = 0;
    for (workspace.strip_widths.items, workspace.strip_shown) |width, shown| {
        if (shown) try std.testing.expect(width >= tab_layout.minimum) else try std.testing.expectEqual(@as(f32, 0), width);
        shown_width += width;
    }
    try std.testing.expectApproxEqAbs(workspace.strip_geometry.content, shown_width, 0.01);
    // Activating the oldest tab brings it back; the active one is never hidden.
    try workspace.model.activate(@fromBackingInt(1));
    try workspace.measureTabs(arena);
    try std.testing.expect(workspace.strip_shown[0]);
    try std.testing.expect(workspace.strip_shown[9]);
    try std.testing.expect(!workspace.strip_shown[1]);
}

test "authentication routes frozen requests despite tab changes and rejects late replies" {
    const cx = try ui.Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    const key: OperationKey = .{ .owner = .{ .session = .{ .session_id = @fromBackingInt(91), .generation = 3 } }, .operation_id = 201, .attempt_id = 2 };
    var tab: SessionTab = undefined;
    tab.id = 17;
    tab.generation = 4;
    var job: Workspace.ConnectJob = undefined;
    job.bootstrap = null;
    job.ticket = tab.ticket();
    job.operation_key = key;
    job.cancelled = .init(false);
    job.ready = .init(false);
    job.auth_bridge = .{};
    job.host_key_bridge = .{};
    job.host_snapshot = try HostSnapshot.init(std.testing.allocator, .{ .name = "frozen", .host = "frozen-hop.test", .user = "operator", .password = "private-password", .key_passphrase = "private-passphrase", .totp_secret = "JBSWY3DPEHPK3PXP" });
    defer job.host_snapshot.deinit();
    job.jump_snapshot = try lifecycle.Snapshot([]const hosts_mod.HostConfig).init(std.testing.allocator, &.{.{ .name = "upstream", .host = "other.test", .user = "other" }});
    defer job.jump_snapshot.deinit();
    defer job.auth_bridge.cancel();
    const request = try job.auth_bridge.offerChallenge(.{
        .key = key,
        .hop_index = 1,
        .kind = .keyboard_interactive,
        .endpoint_identity = .{ .host = "frozen-hop.test", .user = "operator" },
        .prompts = &.{.{ .text = "Verification code:", .echo = false }},
        .presentation_config_revision = 8,
    });
    var tabs = [_]*SessionTab{&tab};
    var jobs = [_]*Workspace.ConnectJob{&job};
    var workspace: Workspace = undefined;
    workspace.group_views = .empty;
    workspace.group_roster = null;
    workspace.active_group_view = null;
    workspace.external_auth = null;
    workspace.cx = cx;
    workspace.tabs = .empty;
    workspace.tabs.items = &tabs;
    workspace.tabs.capacity = tabs.len;
    workspace.connect_jobs = .empty;
    workspace.connect_jobs.items = &jobs;
    workspace.connect_jobs.capacity = jobs.len;
    workspace.active_tab = null;
    workspace.auth_job = null;
    const snapshot = workspace.pendingAuthentication().?;
    try std.testing.expect(snapshot.identity.eql(request));
    try std.testing.expectEqualStrings("frozen-hop.test", snapshot.endpoint().host);
    const display = workspace.authenticationHostFor(request).?;
    try std.testing.expectEqualStrings("frozen", display.name);
    try std.testing.expect(display.password == null and display.key_passphrase == null and display.totp_secret == null);
    var stale = request;
    stale.request_id += 1;
    try std.testing.expect(workspace.authenticationHostFor(stale) == null);
    var wrong_hop = request;
    wrong_hop.hop_index = 0;
    try std.testing.expect(workspace.authenticationHostFor(wrong_hop) == null);
    job.ready.store(true, .release);
    try std.testing.expect(workspace.authenticationHostFor(request) == null);
    job.ready.store(false, .release);
    try std.testing.expectError(error.StaleChallenge, workspace.submitAuthentication(stale, .{ .answers = &.{"123456"} }));
    try std.testing.expect(!workspace.cancelAuthentication(stale));
    try std.testing.expect(!job.cancelled.load(.acquire));
    try workspace.submitAuthentication(request, .{ .answers = &.{"123456"} });
    try std.testing.expectError(error.StaleChallenge, workspace.submitAuthentication(request, .{ .answers = &.{"654321"} }));
    try std.testing.expect(workspace.cancelAuthentication(request));
    try std.testing.expect(job.cancelled.load(.acquire));
    try std.testing.expect(workspace.authenticationHostFor(request) == null);
    try std.testing.expect(workspace.pendingAuthentication() == null);
    try std.testing.expectError(error.StaleAuthentication, workspace.submitAuthentication(request, .{ .answers = &.{"123456"} }));
}

test "temporary session freezes its endpoint without becoming a saved asset even on failure" {
    const Capture = struct {
        snapshot: ?HostSnapshot = null,
        calls: usize = 0,
        fail: bool = false,
        fn create(raw: ?*anyopaque, host: hosts_mod.HostConfig, host_id: HostId, index: usize, input: []const u8) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            try std.testing.expectEqual(@as(HostId, 0), host_id);
            try std.testing.expectEqual(removed_host_index, index);
            try std.testing.expectEqualStrings("", input);
            self.calls += 1;
            if (self.fail) return error.FactoryUnavailable;
            self.snapshot = try HostSnapshot.init(std.testing.allocator, host);
        }
    };
    var capture: Capture = .{};
    defer if (capture.snapshot) |*snapshot| snapshot.deinit();
    var workspace: Workspace = undefined;
    workspace.group_views = .empty;
    workspace.group_roster = null;
    workspace.active_group_view = null;
    workspace.external_auth = null;
    workspace.shutting_down = false;
    workspace.model.window_close = null;
    workspace.registry = try hosts_mod.Registry.parse(std.testing.allocator, "[[hosts]] name=\"saved\"; host=\"saved.test\"; user=\"operator\"");
    defer workspace.registry.deinit();
    const revision = workspace.registry.revision;
    const next_id = workspace.registry.connection_ids.next_value;
    const source_hash = workspace.registry.source_hash;
    workspace.session_bridge = .{ .context = &capture, .create = Capture.create };
    var address = "temporary.test".*;
    var temporary: hosts_mod.HostConfig = .{ .name = "temporary", .host = &address, .user = "operator" };
    try workspace.newTemporarySession(temporary);
    @memset(&address, 'x');
    try std.testing.expectEqualStrings("temporary.test", capture.snapshot.?.value.host);
    try std.testing.expectEqual(@as(usize, 1), workspace.registry.hosts.len);
    try std.testing.expectEqual(revision, workspace.registry.revision);
    try std.testing.expectEqual(next_id, workspace.registry.connection_ids.next_value);
    try std.testing.expectEqual(source_hash, workspace.registry.source_hash);
    capture.fail = true;
    try std.testing.expectError(error.FactoryUnavailable, workspace.newTemporarySession(temporary));
    temporary.connection_id = @fromBackingInt(99);
    try std.testing.expectError(error.InvalidTemporaryTarget, workspace.newTemporarySession(temporary));
    temporary.connection_id = @fromBackingInt(0);
    temporary.route = &.{@fromBackingInt(1)};
    try std.testing.expectError(error.InvalidTemporaryTarget, workspace.newTemporarySession(temporary));
    temporary.route = &.{};
    workspace.shutting_down = true;
    try std.testing.expectError(error.WorkspaceClosed, workspace.newTemporarySession(temporary));
    try std.testing.expectEqual(@as(usize, 2), capture.calls);
    try std.testing.expectEqual(@as(usize, 1), workspace.registry.hosts.len);
    try std.testing.expectEqual(next_id, workspace.registry.connection_ids.next_value);
}

test "saved revision opens with transient credentials without mutating registry" {
    const Capture = struct {
        calls: usize = 0,
        fn create(raw: ?*anyopaque, host: hosts_mod.HostConfig, _: HostId, _: usize, _: []const u8) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            try std.testing.expectEqualStrings("target.test", host.host);
            try std.testing.expect(!host.strict_host_key_checking);
            try std.testing.expectEqualStrings("one-use-password", host.password.?);
            try std.testing.expectEqualStrings("one-use-passphrase", host.key_passphrase.?);
            self.calls += 1;
        }
    };
    var capture: Capture = .{};
    var workspace: Workspace = undefined;
    workspace.group_views = .empty;
    workspace.group_roster = null;
    workspace.active_group_view = null;
    workspace.external_auth = null;
    workspace.allocator = std.testing.allocator;
    workspace.registry = try hosts_mod.Registry.parse(std.testing.allocator,
        \\[[hosts]]
        \\name="target"; host="target.test"; user="operator"
        \\options={strict_host_key=false}
    );
    defer workspace.registry.deinit();
    workspace.recent_connections = .{};
    workspace.identities = .{};
    defer workspace.identities.deinit(std.testing.allocator);
    workspace.session_bridge = .{ .context = &capture, .create = Capture.create };
    const owner = workspace.registry.hosts[0].owner();
    try workspace.newSessionWithCredentials(owner, "one-use-password", "one-use-passphrase");
    try std.testing.expectEqual(@as(usize, 1), capture.calls);
    try std.testing.expect(workspace.registry.hosts[0].password == null);
    try std.testing.expect(workspace.registry.hosts[0].key_passphrase == null);
    var stale = owner;
    stale.revision += 1;
    try std.testing.expectError(error.RevisionConflict, workspace.newSessionWithCredentials(stale, "stale", null));
    try std.testing.expectEqual(@as(usize, 1), capture.calls);
}

test "connection lifecycle polls authentication failure retries cleanup and stale keys without log snapshots" {
    const key: OperationKey = .{ .owner = .{ .session = .{ .session_id = @fromBackingInt(91), .generation = 3 } }, .operation_id = 201, .attempt_id = 2 };
    var tab: SessionTab = undefined;
    tab.id = 17;
    tab.generation = 4;
    var job: Workspace.ConnectJob = undefined;
    job.ticket = tab.ticket();
    job.operation_key = key;
    job.ready = .init(false);
    job.cancelled = .init(false);
    job.cleanup_unknown = false;
    job.automatic_retry_deadline_ns = null;
    job.resource_ledger = try ResourceLedger.init(key, 1);
    // Logs, endpoint snapshots and runtime are deliberately unavailable to
    // this lifecycle-only consumer, including while authentication is pending.
    var tabs = [_]*SessionTab{&tab};
    var jobs = [_]*Workspace.ConnectJob{&job};
    var workspace: Workspace = undefined;
    workspace.tabs = .empty;
    workspace.tabs.items = &tabs;
    workspace.connect_jobs = .empty;
    workspace.connect_jobs.items = &jobs;
    const pending = workspace.connectionLifecycle(key).?;
    try std.testing.expect(!pending.finished and pending.failure == null);
    try std.testing.expectEqual(.not_started, pending.cleanup);

    job.err = error.AuthenticationFailed;
    job.ready.store(true, .release);
    const failed = workspace.connectionLifecycle(key).?;
    try std.testing.expect(failed.finished);
    try std.testing.expectEqual(error.AuthenticationFailed, failed.failure.?);
    try std.testing.expectEqual(.released, failed.cleanup);
    job.automatic_retry_deadline_ns = 1;
    try std.testing.expect(workspace.connectionLifecycle(key).?.failure == null);
    job.automatic_retry_deadline_ns = null;
    job.ready.store(false, .release);
    try std.testing.expect(workspace.connectionLifecycle(key).?.failure == null);

    try std.testing.expect(job.resource_ledger.record(key, 0, .transport, .owned));
    job.cancelled.store(true, .release);
    try std.testing.expectEqual(.releasing, workspace.connectionLifecycle(key).?.cleanup);
    try std.testing.expectError(error.CleanupNotReleased, workspace.dismissConnectionProgress(key));
    try std.testing.expect(job.resource_ledger.record(key, 0, .transport, .unknown));
    job.ready.store(true, .release);
    try std.testing.expectEqual(.unknown, workspace.connectionLifecycle(key).?.cleanup);
    try std.testing.expectError(error.CleanupNotReleased, workspace.dismissConnectionProgress(key));
    try std.testing.expect(job.resource_ledger.record(key, 0, .transport, .released));
    try std.testing.expectEqual(.released, workspace.connectionLifecycle(key).?.cleanup);
    job.cleanup_unknown = true;
    try std.testing.expectEqual(.unknown, workspace.connectionLifecycle(key).?.cleanup);
    job.cleanup_unknown = false;
    try workspace.dismissConnectionProgress(key);
    try std.testing.expect(job.progress_dismissed);

    var stale = key;
    stale.attempt_id = 1;
    try std.testing.expect(workspace.connectionLifecycle(stale) == null);
    stale = key;
    stale.owner.session.generation += 1;
    try std.testing.expect(workspace.connectionLifecycle(stale) == null);
    var next = key;
    next.operation_id += 1;
    job.operation_key = next;
    try std.testing.expect(workspace.connectionLifecycle(key) == null);
    try std.testing.expect(workspace.connectionLifecycle(next) != null);
    tab.generation += 1;
    try std.testing.expect(workspace.connectionLifecycle(next) == null);
    try std.testing.expectError(error.StaleConnection, workspace.dismissConnectionProgress(next));
}

test "connection progress keeps protocol readiness separate from host attachment" {
    const key: OperationKey = .{ .owner = .{ .session = .{ .session_id = @fromBackingInt(91), .generation = 3 } }, .operation_id = 201, .attempt_id = 2 };
    var tab: SessionTab = undefined;
    tab.id = 17;
    tab.generation = 4;
    tab.failed = false;
    tab.runtime = null;
    var job: Workspace.ConnectJob = undefined;
    job.bootstrap = null;
    job.ticket = tab.ticket();
    job.operation_key = key;
    job.ready = .init(true);
    job.cancelled = .init(false);
    job.cleanup_unknown = false;
    job.automatic_retry_deadline_ns = null;
    job.err = null;
    job.resource_ledger = try ResourceLedger.init(key, 1);
    job.progress = .{};
    job.progress.begin(2);
    job.progress_history = .empty;
    job.progress_history_dropped = 0;
    job.progress.record(.{ .attempt = 2, .hop = 0, .hop_count = 1, .host = "target.test", .port = 22, .phase = .ready, .status = .succeeded });
    job.host_snapshot = try HostSnapshot.init(std.testing.allocator, .{ .name = "target", .host = "target.test", .user = "operator", .password = "not-in-progress" });
    defer job.host_snapshot.deinit();
    job.jump_snapshot = try lifecycle.Snapshot([]const hosts_mod.HostConfig).init(std.testing.allocator, &.{});
    defer job.jump_snapshot.deinit();
    var tabs = [_]*SessionTab{&tab};
    var jobs = [_]*Workspace.ConnectJob{&job};
    var workspace: Workspace = undefined;
    workspace.group_views = .empty;
    workspace.group_roster = null;
    workspace.active_group_view = null;
    workspace.external_auth = null;
    workspace.tabs = .empty;
    workspace.tabs.items = &tabs;
    workspace.connect_jobs = .empty;
    workspace.connect_jobs.items = &jobs;
    const projection = workspace.connectionProgress(key).?;
    const lifecycle_state = workspace.connectionLifecycle(key).?;
    try std.testing.expectEqual(projection.finished, lifecycle_state.finished);
    try std.testing.expectEqual(projection.failure, lifecycle_state.failure);
    try std.testing.expectEqual(projection.cleanup, lifecycle_state.cleanup);
    try std.testing.expect(projection.finished and projection.journal.completed);
    try std.testing.expect(!projection.attached);
    try std.testing.expectEqual(@as(usize, 1), projection.hop_count);
    try std.testing.expectEqualStrings("operator", projection.hops[0].user);
    var stale = key;
    stale.attempt_id = 1;
    try std.testing.expect(workspace.connectionProgress(stale) == null);
    var previous: @import("../../../proto/ssh/connection_progress.zig").Journal = .{};
    previous.begin(1);
    for (0..200) |_| previous.record(.{ .attempt = 1, .hop = 0, .hop_count = 1, .host = "target.test", .port = 22, .phase = .transport, .status = .started });
    try job.progress_history.append(std.testing.allocator, .{ .key = stale, .journal = previous.snapshot() });
    defer job.progress_history.deinit(std.testing.allocator);
    const history = workspace.connectionProgress(key).?;
    try std.testing.expectEqual(@as(usize, 128), history.log_count);
    try std.testing.expectEqual(@as(usize, 73), history.dropped);
    try std.testing.expect(history.logs[0].key.eql(stale));
    try std.testing.expectEqual(@as(u64, 73), history.logs[0].entry.sequence);
    try std.testing.expect(history.logs[127].key.eql(key));
}

test "file presentation selects and closes without constructing a terminal or connect job" {
    const allocator = std.testing.allocator;
    const cx = try ui.Cx.init(allocator, std.testing.io);
    defer cx.deinit();
    const scope = try ui.Scope.init(allocator, null, cx.owner);
    defer scope.dispose();
    const root = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .direction = .column }, .{});
    cx.root = root;
    const strip = try ui.box(cx, .{ .width = .fill(), .height = .{ .px = 46 }, .flex_shrink = 0 }, .{});
    try root.appendChild(allocator, strip);
    const area = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .flex = 1, .direction = .column }, .{});
    try root.appendChild(allocator, area);
    const empty = try ui.box(cx, .{}, .{});
    try area.appendChild(allocator, empty);
    const sidebar = try ui.box(cx, .{ .display = .none }, .{});
    try root.appendChild(allocator, sidebar);
    var config: config_mod.Config = .{};
    const workspace = try allocator.create(Workspace);
    workspace.* = .{ .allocator = allocator, .cx = cx, .scope = scope, .io = std.testing.io, .app_config = &config, .palette = Palette.fromTheme(), .registry = .{ .arena = std.heap.ArenaAllocator.init(allocator), .hosts = &.{} }, .hosts_path = "", .sidebar_list = sidebar, .tab_bar = strip, .model = .{ .allocator = allocator, .window = @fromBackingInt(1), .workspace = @fromBackingInt(1) }, .terminal_area = area, .empty_state = empty };
    try scope.onCleanup(Workspace, workspace, Workspace.cleanup);
    cx.setViewport(860, 480);
    const content_scope = try scope.childScope();
    const content = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    const owner: identity.SessionHandle = .{ .session_id = @fromBackingInt(81), .generation = 3 };
    const id = try workspace.createFileSessionDirect(owner, .{ .connection_id = @fromBackingInt(9), .protocol = .sftp, .name = "Files", .host = "files.test", .user = "operator" }, 9, removed_host_index, content, content_scope);
    const tab = workspace.sessionTab(id).?;
    try std.testing.expect(tab.terminal == null and tab.runtime == null and !tab.local);
    try std.testing.expect(tab.content_owner.eql(.{ .session = owner }));
    try std.testing.expectEqual(@as(usize, 0), workspace.connect_jobs.items.len);
    try std.testing.expectEqualStrings("operator@files.test:22 · SFTP", workspace.model.tabs.items[0].details);
    workspace.selectTab(0);
    cx.layout();
    try std.testing.expectEqual(@as(?usize, 0), workspace.active_tab);
    try std.testing.expect(content.style.display != .none);
    try std.testing.expectEqual(content, cx.focus_manager.getFocused().?);
    try std.testing.expectEqual(RuntimeReleaseReceipt.released, workspace.protocolReleaseStep(id));
    workspace.forceCloseTab(0);
    try std.testing.expectEqual(@as(usize, 0), workspace.tabs.items.len);
    try std.testing.expect(workspace.active_tab == null);
}

test "SSH middle menu bridge preserves the clicked handle across active changes and rejects stale owners" {
    const allocator = std.testing.allocator;
    const cx = try ui.Cx.init(allocator, std.testing.io);
    defer cx.deinit();
    const root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    cx.root = root;
    const first: identity.SessionHandle = .{ .session_id = @fromBackingInt(901), .generation = 7 };
    const second: identity.SessionHandle = .{ .session_id = @fromBackingInt(902), .generation = 4 };
    // The callback reads only tab identity/state and runtime presence. It never
    // dereferences or starts these IO placeholders.
    var runtime: SessionRuntime = undefined;
    var clicked: SessionTab = .{ .id = 11, .tab_id = @fromBackingInt(51), .content_owner = .{ .session = first }, .generation = first.generation, .host_id = 0, .host_index = removed_host_index, .host_snapshot = null, .root = root, .runtime = &runtime };
    var other: SessionTab = .{ .id = 12, .tab_id = @fromBackingInt(52), .content_owner = .{ .session = second }, .generation = second.generation, .host_id = 0, .host_index = removed_host_index, .host_snapshot = null, .root = root, .runtime = &runtime };
    var tabs = [_]*SessionTab{ &clicked, &other };
    var workspace: Workspace = undefined;
    workspace.group_views = .empty;
    workspace.group_roster = null;
    workspace.active_group_view = null;
    workspace.shutting_down = false;
    workspace.tabs = .empty;
    workspace.tabs.items = &tabs;
    workspace.tabs.capacity = tabs.len;
    workspace.active_tab = 1;
    const Sink = struct {
        calls: usize = 0,
        index: ?usize = null,
        anchor: ui.ComputedRect = .{ .x = 0, .y = 0, .w = 0, .h = 0 },
        fn fire(raw: ?*anyopaque, trigger: MenuBridge.Trigger, _: usize, index: ?usize, _: bool, anchor: ui.ComputedRect) void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            if (trigger != .terminal_middle_click) return;
            self.calls += 1;
            self.index = index;
            self.anchor = anchor;
        }
    };
    var sink: Sink = .{};
    workspace.menu_bridge = .{ .context = &sink, .fire = Sink.fire };
    Workspace.onTerminalServiceMenu(&workspace, first, 213, 47);
    try std.testing.expectEqual(@as(usize, 1), sink.calls);
    try std.testing.expectEqual(@as(?usize, 0), sink.index);
    try std.testing.expectEqual(ui.ComputedRect{ .x = 213, .y = 47, .w = 0, .h = 0 }, sink.anchor);
    Workspace.onTerminalServiceMenu(&workspace, try first.nextGeneration(), 90, 90);
    clicked.closing = true;
    Workspace.onTerminalServiceMenu(&workspace, first, 90, 90);
    clicked.closing = false;
    clicked.failed = true;
    Workspace.onTerminalServiceMenu(&workspace, first, 90, 90);
    clicked.failed = false;
    clicked.runtime = null;
    Workspace.onTerminalServiceMenu(&workspace, first, 90, 90);
    try std.testing.expectEqual(@as(usize, 1), sink.calls);
}

test "notification output keeps marker colors and stops old unread animation across rebuilds" {
    const allocator = std.testing.allocator;
    const cx = try ui.Cx.init(allocator, std.testing.io);
    defer cx.deinit();
    const scope = try ui.Scope.init(allocator, null, cx.owner);
    defer scope.dispose();
    const root = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .direction = .column }, .{});
    cx.root = root;
    const strip = try ui.box(cx, .{ .width = .fill(), .height = .{ .px = 46 }, .flex_shrink = 0 }, .{});
    try root.appendChild(allocator, strip);
    const area = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .flex = 1, .direction = .column }, .{});
    try root.appendChild(allocator, area);
    const empty = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .position = .absolute }, .{});
    try area.appendChild(allocator, empty);
    const sidebar = try ui.box(cx, .{ .display = .none }, .{});
    try root.appendChild(allocator, sidebar);
    const config: config_mod.Config = .{};
    const workspace = try allocator.create(Workspace);
    workspace.* = .{
        .allocator = allocator,
        .cx = cx,
        .scope = scope,
        .io = std.testing.io,
        .app_config = &config,
        .palette = Palette.fromTheme(),
        .registry = .{ .arena = std.heap.ArenaAllocator.init(allocator), .hosts = &.{} },
        .hosts_path = "",
        .sidebar_list = sidebar,
        .tab_bar = strip,
        .model = .{ .allocator = allocator, .window = @fromBackingInt(1), .workspace = @fromBackingInt(1) },
        .terminal_area = area,
        .empty_state = empty,
    };
    try scope.onCleanup(Workspace, workspace, Workspace.cleanup);
    cx.setViewport(1194, 800);
    const first_owner: identity.SessionHandle = .{ .session_id = @fromBackingInt(41) };
    const second_owner: identity.SessionHandle = .{ .session_id = @fromBackingInt(42) };
    const first = try workspace.createLocalSessionDirect(first_owner);
    const second = try workspace.createLocalSessionDirect(second_owner);
    workspace.updateLocalState(first, .running, "");
    workspace.updateLocalState(second, .failed, "fixture failure");
    // A background Local tab has no SSH SessionRuntime; its picker status
    // must follow the Local lifecycle rather than stay "connecting" forever.
    const first_tab_id = workspace.sessionTab(first).?.tab_id;
    // copy-terms：状态文案取 connection_presenter（“已连接”，不写“在线”；退出叫“已结束”）。
    try std.testing.expectEqualStrings("已连接", workspace.tabStatus(first_tab_id));
    workspace.sessionTab(first).?.local_state = .exited;
    try std.testing.expectEqualStrings("已结束", workspace.tabStatus(first_tab_id));
    workspace.sessionTab(first).?.local_state = .running;
    workspace.sessionTab(first).?.tab_color = 0x67b88b;
    try workspace.renderTabBar();
    cx.layout();
    try std.testing.expectEqual(cx.tokens.tokens.color.fg_secondary, workspace.tab_nodes.items[0].label.getText().?.color);
    // 稿 3: the user colour tints only the type icon; no marker dot, no surface fill.
    try std.testing.expectEqual(ui.Color.hex(0x67b88b), workspace.strip_vm.?.visual(@backingInt(workspace.tab_nodes.items[0].tab_id)).tint);
    try std.testing.expectEqual(workspace.palette.red, workspace.strip_vm.?.visual(@backingInt(workspace.tab_nodes.items[1].tab_id)).tint);
    const first_presentation = workspace.tabPresentation(.{ .session = first_owner }).?;
    const second_presentation = workspace.tabPresentation(.{ .session = second_owner }).?;
    const live_icon = workspace.strip_vm.?.visual(@backingInt(workspace.tab_nodes.items[0].tab_id));
    try std.testing.expectEqual(live_icon.icon.icon_id.?, first_presentation.icon_id);
    try std.testing.expectEqual((@as(u32, live_icon.tint.r) << 24) | (@as(u32, live_icon.tint.g) << 16) | (@as(u32, live_icon.tint.b) << 8) | live_icon.tint.a, first_presentation.icon_tint);
    try std.testing.expectEqualStrings(workspace.model.tabs.items[0].name(), first_presentation.title);
    try std.testing.expectEqualStrings("已连接", first_presentation.status);
    try std.testing.expectEqualStrings("连接失败", second_presentation.status);
    try std.testing.expect(first_presentation.order < second_presentation.order);
    try std.testing.expect(first_presentation.icon_svg.len > 0);
    const first_child_count = workspace.tab_nodes.items[0].node.children.items.len;
    const second_child_count = workspace.tab_nodes.items[1].node.children.items.len;
    const notifications = @import("../../../host/notification_coordinator.zig");
    const preferences: config_mod.Notify = .{};
    var coordinator = try notifications.Coordinator.init(allocator, preferences, .{});
    defer coordinator.deinit();
    const Bridge = struct {
        fn hasDot(raw: ?*anyopaque, owner: identity.ContentOwner) bool {
            const value: *notifications.Coordinator = @ptrCast(@alignCast(raw.?));
            return value.hasDot(owner);
        }
    };
    _ = try coordinator.observeOutput(.{ .session = first_owner }, 7);
    _ = try coordinator.observeOutput(.{ .session = second_owner }, 3);
    workspace.setNotificationAttentionBridge(.{ .context = &coordinator, .has_dot = Bridge.hasDot });
    cx.layout();
    try std.testing.expect(coordinator.hasDot(.{ .session = first_owner }));
    try std.testing.expect(coordinator.hasDot(.{ .session = second_owner }));
    try std.testing.expectEqual(first_child_count, workspace.tab_nodes.items[0].node.children.items.len);
    try std.testing.expectEqual(second_child_count, workspace.tab_nodes.items[1].node.children.items.len);
    for (workspace.tab_nodes.items) |cell| {
        for (cell.node.children.items) |child| {
            const id = child.meta.ownership.meta.test_id orelse continue;
            try std.testing.expect(!std.mem.eql(u8, id, "tabs.unread_attention"));
            try std.testing.expect(!std.mem.eql(u8, id, "tabs.connection_status"));
        }
    }
    try std.testing.expectEqual(cx.tokens.tokens.color.fg_secondary, workspace.tab_nodes.items[0].label.getText().?.color);
    // 稿 3: the user colour tints only the type icon; no marker dot, no surface fill.
    try std.testing.expectEqual(ui.Color.hex(0x67b88b), workspace.strip_vm.?.visual(@backingInt(workspace.tab_nodes.items[0].tab_id)).tint);
    try std.testing.expectEqual(workspace.palette.red, workspace.strip_vm.?.visual(@backingInt(workspace.tab_nodes.items[1].tab_id)).tint);
    try std.testing.expect(coordinator.markRead(.{ .session = second_owner }, 3, true));
    workspace.refreshNotificationAttention();
    try std.testing.expect(!coordinator.hasDot(.{ .session = second_owner }));
    // Only an unread background tab bounces; colour and custom titles stay put.
    cx.window_active = true;
    workspace.model.active = workspace.sessionTab(second).?.tab_id;
    workspace.model.tabs.items[workspace.model.indexOf(first_tab_id).?].attention_started_ms = null;
    cx.frame_time_ms = 100;
    workspace.refreshNotificationAttention();
    cx.frame_time_ms = 220;
    workspace.refreshNotificationAttention();
    try std.testing.expectApproxEqAbs(@as(f32, -3), workspace.strip_vm.?.visual(@backingInt(workspace.tab_nodes.items[0].tab_id)).bounce, 0.01);
    try std.testing.expectEqual(@as(f32, 0), workspace.strip_vm.?.visual(@backingInt(workspace.tab_nodes.items[1].tab_id)).bounce);
    try std.testing.expect(workspace.tabPresentation(.{ .session = first_owner }).?.icon_bouncing);
    try std.testing.expect(!workspace.tabPresentation(.{ .session = second_owner }).?.icon_bouncing);
    cx.frame_time_ms = 2000;
    workspace.refreshNotificationAttention();
    try std.testing.expectEqual(@as(f32, 0), workspace.strip_vm.?.visual(@backingInt(workspace.tab_nodes.items[0].tab_id)).bounce);
    try std.testing.expect(!workspace.tabPresentation(.{ .session = first_owner }).?.icon_bouncing);
    try workspace.renderTabBar();
    workspace.refreshNotificationAttention();
    try std.testing.expectEqual(@as(f32, 0), workspace.strip_vm.?.visual(@backingInt(workspace.tab_nodes.items[0].tab_id)).bounce);
    try std.testing.expect(!workspace.tabPresentation(.{ .session = first_owner }).?.icon_bouncing);
    try std.testing.expect(coordinator.markRead(.{ .session = first_owner }, 7, true));
    workspace.refreshNotificationAttention();
    try std.testing.expectEqual(@as(f32, 0), workspace.strip_vm.?.visual(@backingInt(workspace.tab_nodes.items[0].tab_id)).bounce);
    _ = try coordinator.observeOutput(.{ .session = first_owner }, 8);
    workspace.model.active = first_tab_id;
    workspace.refreshNotificationAttention();
    try std.testing.expect(workspace.model.tabs.items[workspace.model.indexOf(first_tab_id).?].attention_started_ms == null);
    const second_tab = @backingInt(workspace.tab_nodes.items[1].tab_id);
    workspace.sessionTab(second).?.local_state = .starting;
    workspace.refreshNotificationAttention();
    try std.testing.expectEqual(session_icon.tabTint(.connecting, workspace.tab_nodes.items[1].icon_asset), workspace.strip_vm.?.visual(second_tab).tint);
    workspace.sessionTab(second).?.local_state = .exited;
    workspace.refreshNotificationAttention();
    try std.testing.expectEqual(session_icon.tabTint(.normal, workspace.tab_nodes.items[1].icon_asset), workspace.strip_vm.?.visual(second_tab).tint);
}

test "notification standalone Local tab settles without new activity and does not restart old unread output" {
    const allocator = std.testing.allocator;
    const cx = try ui.Cx.init(allocator, std.testing.io);
    defer cx.deinit();
    const scope = try ui.Scope.init(allocator, null, cx.owner);
    defer scope.dispose();
    const root = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .direction = .column }, .{});
    cx.root = root;
    const strip = try ui.box(cx, .{ .width = .fill(), .height = .{ .px = 46 }, .flex_shrink = 0 }, .{});
    try root.appendChild(allocator, strip);
    const area = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .flex = 1, .direction = .column }, .{});
    try root.appendChild(allocator, area);
    const empty = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .position = .absolute }, .{});
    try area.appendChild(allocator, empty);
    const sidebar = try ui.box(cx, .{ .display = .none }, .{});
    try root.appendChild(allocator, sidebar);
    const config: config_mod.Config = .{};
    const workspace = try allocator.create(Workspace);
    workspace.* = .{
        .allocator = allocator,
        .cx = cx,
        .scope = scope,
        .io = std.testing.io,
        .app_config = &config,
        .palette = Palette.fromTheme(),
        .registry = .{ .arena = std.heap.ArenaAllocator.init(allocator), .hosts = &.{} },
        .hosts_path = "",
        .sidebar_list = sidebar,
        .tab_bar = strip,
        .model = .{ .allocator = allocator, .window = @fromBackingInt(1), .workspace = @fromBackingInt(1) },
        .terminal_area = area,
        .empty_state = empty,
    };
    try scope.onCleanup(Workspace, workspace, Workspace.cleanup);
    cx.setViewport(1194, 800);
    const owner: identity.SessionHandle = .{ .session_id = @fromBackingInt(43) };
    const session = try workspace.createLocalSessionDirect(owner);
    workspace.updateLocalState(session, .running, "");
    try workspace.renderTabBar();
    const id = workspace.sessionTab(session).?.tab_id;
    const notifications = @import("../../../host/notification_coordinator.zig");
    var coordinator = try notifications.Coordinator.init(allocator, .{}, .{});
    defer coordinator.deinit();
    const Bridge = struct {
        fn hasDot(raw: ?*anyopaque, content: identity.ContentOwner) bool {
            const value: *notifications.Coordinator = @ptrCast(@alignCast(raw.?));
            return value.hasDot(content);
        }
    };
    cx.window_active = false;
    cx.frame_time_ms = 100;
    workspace.setNotificationAttentionBridge(.{ .context = &coordinator, .has_dot = Bridge.hasDot });
    try std.testing.expectEqual(@as(usize, 1), workspace.tab_nodes.items.len);
    try std.testing.expectEqual(id, workspace.model.active.?);
    try std.testing.expect(!workspace.tabPresentation(.{ .session = owner }).?.icon_bouncing);
    try std.testing.expectEqual(@as(f32, 0), workspace.strip_vm.?.visual(@backingInt(workspace.tab_nodes.items[0].tab_id)).bounce);

    _ = try coordinator.observeOutput(.{ .session = owner }, 7);
    workspace.refreshNotificationAttention();
    cx.frame_time_ms = 220;
    workspace.refreshNotificationAttention();
    try std.testing.expectApproxEqAbs(@as(f32, -3), workspace.strip_vm.?.visual(@backingInt(workspace.tab_nodes.items[0].tab_id)).bounce, 0.01);
    try std.testing.expect(workspace.tabPresentation(.{ .session = owner }).?.icon_bouncing);
    // Exactly one burst, including the former 1600ms repeat boundary.
    for ([_]f64{ 580, 1720, 3320 }) |now| {
        cx.frame_time_ms = now;
        workspace.refreshNotificationAttention();
        try std.testing.expectEqual(@as(f32, 0), workspace.strip_vm.?.visual(@backingInt(workspace.tab_nodes.items[0].tab_id)).bounce);
        try std.testing.expect(!workspace.tabPresentation(.{ .session = owner }).?.icon_bouncing);
    }
    try workspace.renderTabBar();
    workspace.refreshNotificationAttention();
    cx.window_active = true;
    workspace.refreshNotificationAttention();
    cx.window_active = false;
    _ = try coordinator.observeOutput(.{ .session = owner }, 8);
    workspace.refreshNotificationAttention();
    try std.testing.expect(coordinator.hasDot(.{ .session = owner }));
    try std.testing.expectEqual(@as(f32, 0), workspace.strip_vm.?.visual(@backingInt(workspace.tab_nodes.items[0].tab_id)).bounce);
    try std.testing.expect(!workspace.tabPresentation(.{ .session = owner }).?.icon_bouncing);
    // A real read receipt permits a later unread episode to animate again.
    try std.testing.expect(coordinator.markRead(.{ .session = owner }, 8, true));
    workspace.refreshNotificationAttention();
    _ = try coordinator.observeOutput(.{ .session = owner }, 9);
    workspace.refreshNotificationAttention();
    cx.frame_time_ms += 120;
    workspace.refreshNotificationAttention();
    try std.testing.expectApproxEqAbs(@as(f32, -3), workspace.strip_vm.?.visual(@backingInt(workspace.tab_nodes.items[0].tab_id)).bounce, 0.01);
}

test "Local rename survives same title startup but rejects real title or owner changes" {
    const allocator = std.testing.allocator;
    const cx = try ui.Cx.init(allocator, std.testing.io);
    defer cx.deinit();
    const scope = try ui.Scope.init(allocator, null, cx.owner);
    defer scope.dispose();
    const root = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .direction = .column }, .{});
    cx.root = root;
    const strip = try ui.box(cx, .{ .width = .fill(), .height = .{ .px = 46 }, .flex_shrink = 0 }, .{});
    try root.appendChild(allocator, strip);
    const area = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .flex = 1, .direction = .column }, .{});
    try root.appendChild(allocator, area);
    const empty = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .position = .absolute }, .{});
    try area.appendChild(allocator, empty);
    const sidebar = try ui.box(cx, .{ .display = .none }, .{});
    try root.appendChild(allocator, sidebar);
    var config: config_mod.Config = .{};
    config.ui.timestamp_gutter = true;
    const workspace = try allocator.create(Workspace);
    workspace.* = .{
        .allocator = allocator,
        .cx = cx,
        .scope = scope,
        .io = std.testing.io,
        .app_config = &config,
        .palette = Palette.fromTheme(),
        .registry = .{ .arena = std.heap.ArenaAllocator.init(allocator), .hosts = &.{} },
        .hosts_path = "",
        .sidebar_list = sidebar,
        .tab_bar = strip,
        .model = .{ .allocator = allocator, .window = @fromBackingInt(1), .workspace = @fromBackingInt(1) },
        .terminal_area = area,
        .empty_state = empty,
    };
    try scope.onCleanup(Workspace, workspace, Workspace.cleanup);
    cx.setViewport(1194, 800);
    const Helpers = struct {
        fn frames(value: *ui.Cx) void {
            for (0..6) |_| {
                value.frame_count += 1;
                value.frame_time_ms += 16;
                _ = value.render();
            }
        }
        fn find(node: *ui.Node, id: []const u8) ?*ui.Node {
            if (node.meta.ownership.meta.test_id) |name| if (std.mem.eql(u8, name, id)) return node;
            for (node.children.items) |child| if (find(child, id)) |found| return found;
            return null;
        }
        fn save(value: *Workspace) void {
            const button = find(value.rename_editor.?.dialog, "tabs.rename.save").?;
            const rect = button.globalRect();
            value.cx.handleMouseDown(rect.x + rect.w / 2, rect.y + rect.h / 2, .{});
            value.cx.handleMouseUp(rect.x + rect.w / 2, rect.y + rect.h / 2);
        }
    };
    const first_owner: identity.SessionHandle = .{ .session_id = @fromBackingInt(41) };
    const second_owner: identity.SessionHandle = .{ .session_id = @fromBackingInt(42) };
    const first = try workspace.createLocalSessionDirect(first_owner);
    const second = try workspace.createLocalSessionDirect(second_owner);
    try workspace.beginRenameTab(second);
    Helpers.frames(cx);
    const captured_revision = workspace.rename_request.?.revision;
    workspace.rename_editor.?.value.set("chosen title");
    // Starting -> running keeps the exact same visible default title. It must
    // not invalidate the rename already being edited for that same tab owner.
    workspace.updateLocalState(second, .running, "");
    Helpers.frames(cx);
    Helpers.save(workspace);
    try std.testing.expectEqualStrings("chosen title", workspace.sessionTab(second).?.titleSlice());
    try std.testing.expectEqualStrings(tab_naming.home_label, workspace.sessionTab(first).?.titleSlice());
    try std.testing.expectEqual(captured_revision + 1, workspace.model.tabs.items[1].revision);
    Helpers.frames(cx);
    try std.testing.expect(workspace.rename_request == null);

    try workspace.beginRenameTab(second);
    Helpers.frames(cx);
    workspace.rename_editor.?.value.set("late title");
    try workspace.renameTab(1, "new external title");
    Helpers.frames(cx);
    Helpers.save(workspace);
    try std.testing.expectEqualStrings("new external title", workspace.sessionTab(second).?.titleSlice());
    try std.testing.expect(workspace.rename_editor.?.isVisible());
    try std.testing.expect(workspace.cancelRenameTab());
    Helpers.frames(cx);

    try workspace.beginRenameTab(second);
    Helpers.frames(cx);
    workspace.rename_editor.?.value.set("old owner title");
    try workspace.bindSessionOwner(second, try second_owner.nextGeneration());
    Helpers.frames(cx);
    Helpers.save(workspace);
    try std.testing.expectEqualStrings("new external title", workspace.sessionTab(second).?.titleSlice());
    try std.testing.expect(workspace.rename_editor.?.isVisible());
    try std.testing.expect(workspace.cancelRenameTab());
    Helpers.frames(cx);
}

test "group close cancel has no resource effects and membership change needs new approval" {
    const allocator = std.testing.allocator;
    const cx = try ui.Cx.init(allocator, std.testing.io);
    defer cx.deinit();
    const scope = try ui.Scope.init(allocator, null, cx.owner);
    defer scope.dispose();
    const area = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    cx.root = area;
    const first_root = try ui.box(cx, .{}, .{});
    const second_root = try ui.box(cx, .{}, .{});
    try area.appendChild(allocator, first_root);
    try area.appendChild(allocator, second_root);
    const config: config_mod.Config = .{};
    var roster = group_model.Roster.init(allocator);
    defer roster.deinit();
    const first_id: u64 = 0x1_0000_0011;
    const second_id: u64 = 0x1_0000_0012;
    const group_id = (try roster.join("real sessions", first_id, 0xff818cf8)).id;
    _ = try roster.join("real sessions", second_id, 0xff818cf8);
    var first: SessionTab = .{ .id = first_id, .tab_id = @fromBackingInt(1), .content_owner = .{ .session = .{ .session_id = @fromBackingInt(first_id) } }, .host_id = 0, .host_index = 0, .host_snapshot = null, .root = first_root, .local = true };
    first.setTitle("本机 · zsh");
    var second: SessionTab = .{ .id = second_id, .tab_id = @fromBackingInt(2), .content_owner = .{ .session = .{ .session_id = @fromBackingInt(second_id) } }, .host_id = 0, .host_index = 0, .host_snapshot = null, .root = second_root, .local = true };
    second.setTitle("另一个独立进程");
    var workspace: Workspace = .{ .allocator = allocator, .cx = cx, .scope = scope, .io = std.testing.io, .app_config = &config, .palette = Palette.fromTheme(), .registry = .{ .arena = std.heap.ArenaAllocator.init(allocator), .hosts = &.{} }, .hosts_path = "", .sidebar_list = area, .tab_bar = area, .terminal_area = area, .empty_state = area, .model = .{ .allocator = allocator, .window = @fromBackingInt(1), .workspace = @fromBackingInt(1) }, .group_roster = &roster };
    defer if (workspace.poll_hook) |hook| {
        cx.removeAfterLayoutHook(hook);
        allocator.destroy(hook);
    };
    defer workspace.registry.deinit();
    defer workspace.model.deinit();
    defer workspace.tabs.deinit(allocator);
    defer workspace.group_views.deinit(allocator);
    try workspace.tabs.appendSlice(allocator, &.{ &first, &second });
    const view = try allocator.create(group_view.View);
    var view_retired = false;
    defer if (!view_retired) allocator.destroy(view);
    view.* = .{ .id = group_id };
    defer if (!view_retired) view.deinit(allocator);
    try workspace.group_views.append(allocator, view);
    const Sink = struct {
        calls: usize = 0,
        remote_unknown: bool = false,
        fn impact(raw: ?*anyopaque, _: SessionId) group_close.Impact {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            return .{ .remote_effect_unknown = self.remote_unknown };
        }
        fn close(raw: ?*anyopaque, _: identity.TabId, _: identity.ContentOwner) CloseResult {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.calls += 1;
            return .awaiting;
        }
    };
    var sink: Sink = .{};
    workspace.close_bridge = .{ .context = &sink, .request_close = Sink.close, .impact = Sink.impact };
    workspace.requestCloseGroup(group_id);
    try std.testing.expectEqual(@as(usize, 2), view.close.?.members.items.len);
    try std.testing.expectEqual(first_id, view.close.?.members.items[0].id);
    workspace.cancelGroupClose(group_id);
    try std.testing.expectEqual(@as(usize, 0), sink.calls);
    try std.testing.expect(view.close == null);
    try std.testing.expect(!first.closing and !second.closing);
    workspace.requestCloseGroup(group_id);
    _ = try roster.join("real sessions", 99, 0xff818cf8);
    workspace.approveGroupClose(group_id);
    try std.testing.expectEqual(group_view.ClosePhase.confirming, view.close.?.phase);
    try std.testing.expectEqual(@as(usize, 0), sink.calls);
    // The refreshed plan still only contains original valid handles; unknown
    // roster entries cannot become fabricated terminal resources.
    try std.testing.expectEqual(@as(usize, 2), view.close.?.members.items.len);
    workspace.cancelGroupClose(group_id);

    // A real AI outcome may predate the plan. Its retained owner fact must be
    // captured from impact without requiring a live receive callback or AI job.
    sink.remote_unknown = true;
    workspace.requestCloseGroup(group_id);
    try std.testing.expect(view.close.?.members.items[0].remote_effect_unknown);
    try std.testing.expectEqual(@as(usize, 2), view.close.?.counts().unknown);
    _ = view.close.?.record(first_id, .closed);
    _ = view.close.?.record(second_id, .closed);
    view.close.?.cursor = view.close.?.members.items.len;
    view.close.?.phase = .closing;
    workspace.pollGroupClose();
    view_retired = true;
    try std.testing.expectEqual(@as(usize, 0), workspace.group_views.items.len);
    const Find = struct {
        fn node(root: *ui.Node, id: []const u8) ?*ui.Node {
            if (root.meta.ownership.meta.test_id) |name| if (std.mem.eql(u8, name, id)) return root;
            for (root.children.items) |child| if (node(child, id)) |found| return found;
            return null;
        }
    };
    const result = Find.node(area, "groups.close.partial").?;
    const retry = Find.node(result, "groups.close.accept").?;
    try std.testing.expect(retry.behavior.interaction.a11y.?.disabled);
}

test "mixed tab group identity unifies drag cursor rollback ordinals picker and MRU" {
    const allocator = std.testing.allocator;
    const cx = try ui.Cx.init(allocator, std.testing.io);
    defer cx.deinit();
    const scope = try ui.Scope.init(allocator, null, cx.owner);
    const root = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .direction = .column }, .{});
    cx.root = root;
    const strip = try ui.box(cx, .{ .height = .{ .px = 32 }, .direction = .row }, .{});
    try root.appendChild(allocator, strip);
    const area = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    try root.appendChild(allocator, area);
    const config: config_mod.Config = .{};
    var roster = group_model.Roster.init(allocator);
    defer roster.deinit();
    const group_id = (try roster.join("Acceptance", 71, 0xff818cf8)).id;
    var workspace: Workspace = .{ .allocator = allocator, .cx = cx, .scope = scope, .io = std.testing.io, .app_config = &config, .palette = Palette.fromTheme(), .registry = .{ .arena = std.heap.ArenaAllocator.init(allocator), .hosts = &.{} }, .hosts_path = "", .sidebar_list = root, .tab_bar = strip, .terminal_area = area, .empty_state = area, .model = .{ .allocator = allocator, .window = @fromBackingInt(1), .workspace = @fromBackingInt(1) } };
    defer {
        if (workspace.poll_hook) |hook| {
            cx.removeAfterLayoutHook(hook);
            allocator.destroy(hook);
            workspace.poll_hook = null;
        }
        scope.dispose();
        for (workspace.click_ctxs.items) |cell| allocator.destroy(cell);
        workspace.click_ctxs.deinit(allocator);
        workspace.tab_nodes.deinit(allocator);
        workspace.strip_advances.deinit(allocator);
        workspace.strip_widths.deinit(allocator);
        workspace.strip_grouped.deinit(allocator);
        workspace.tabs.deinit(allocator);
        workspace.rename_draft.deinit(allocator);
        workspace.model.deinit();
        workspace.registry.deinit();
        for (workspace.group_views.items) |view| {
            view.deinit(allocator);
            allocator.destroy(view);
        }
        workspace.group_views.deinit(allocator);
    }
    cx.setViewport(860, 480);
    const first_id = try tab_ids.allocate();
    const last_id = try tab_ids.allocate();
    const first_root = try ui.box(cx, .{}, .{});
    const last_root = try ui.box(cx, .{}, .{});
    try area.appendChild(allocator, first_root);
    try area.appendChild(allocator, last_root);
    var first: SessionTab = .{ .id = 71, .tab_id = first_id, .content_owner = .{ .session = .{ .session_id = @fromBackingInt(71) } }, .host_id = 0, .host_index = 0, .host_snapshot = null, .root = first_root, .local = true };
    first.setTitle("First Local");
    var last: SessionTab = .{ .id = 72, .tab_id = last_id, .content_owner = .{ .session = .{ .session_id = @fromBackingInt(72) } }, .host_id = 0, .host_index = 0, .host_snapshot = null, .root = last_root, .local = true };
    last.setTitle("Last Local");
    try workspace.tabs.append(allocator, &first);
    try workspace.installTabModel(&first);
    try workspace.openGroup(&roster, group_id);
    const group_tab = workspace.groupTabId(group_id).?;
    try workspace.tabs.append(allocator, &last);
    try workspace.installTabModel(&last);
    try workspace.renderTabBar();
    cx.layout();
    try std.testing.expectEqual(@as(usize, 3), workspace.model.tabs.items.len);
    try std.testing.expectEqual(group_tab, workspace.tab_nodes.items[1].tab_id);
    try std.testing.expectEqual(group_id, workspace.groupIdByTab(group_tab).?);
    try std.testing.expect(workspace.tabIndexById(group_tab) == null);
    // The close control is zenit's native ghost xs icon button in a 20pt slot.
    try std.testing.expectApproxEqAbs(@as(f32, 20), workspace.tab_nodes.items[1].close.parent.?.globalRect().w, 0.01);
    // 稿 3: ordinals appear in the close slot only after ⌘ is held 300 ms.
    workspace.setCommandHeld(true);
    try std.testing.expect(workspace.tab_nodes.items[1].icon.parent.?.style.display == .none);
    workspace.command_held_since_ms = workspace.cx.frame_time_ms - Workspace.command_ordinal_delay_ms;
    workspace.refreshCommandOrdinals();
    try std.testing.expect(workspace.tab_nodes.items[1].icon.parent.?.style.display != .none);
    try std.testing.expectEqualStrings("⌘2", workspace.tab_nodes.items[1].icon.getText().?.content);
    try std.testing.expect(workspace.tab_nodes.items[1].close.parent.?.getOpacity() == 0);
    try workspace.model.beginDrag();
    try workspace.model.moveTab(group_tab, 0);
    try workspace.syncModelOrder();
    try std.testing.expectEqual(group_tab, workspace.tab_nodes.items[0].tab_id);
    try std.testing.expectEqual(first_id, workspace.tabs.items[0].tab_id);
    try std.testing.expectEqual(last_id, workspace.tabs.items[1].tab_id);
    try workspace.model.endDrag(true);
    try workspace.syncModelOrder();
    try std.testing.expectEqual(group_tab, workspace.tab_nodes.items[1].tab_id);
    cx.layout();
    const drag_rect = workspace.tab_nodes.items[1].node.globalRect();
    const target_rect = workspace.tab_nodes.items[0].node.globalRect();
    cx.handleMouseMove(drag_rect.x + drag_rect.w / 2, drag_rect.y + 15);
    try std.testing.expectEqual(ui.CursorShape.grab, cx.current_cursor);
    cx.handleMouseDown(drag_rect.x + drag_rect.w / 2, drag_rect.y + 15, .{});
    cx.handleMouseMove(target_rect.x + 8, target_rect.y + 15);
    try std.testing.expect(workspace.model.dragging);
    try std.testing.expectEqual(ui.CursorShape.grabbing, cx.current_cursor);
    try std.testing.expectEqual(first_id, workspace.model.tabs.items[0].id);
    try std.testing.expectEqual(first_id, workspace.tab_reorder_target.?);
    cx.cancelPointerInteractions(.window_blur);
    try std.testing.expect(!workspace.model.dragging);
    try std.testing.expectEqual(group_tab, workspace.model.tabs.items[1].id);
    try std.testing.expect(workspace.drag_binding == null);
    try std.testing.expectEqual(first.content_owner, workspace.model.tabs.items[0].owner);
    workspace.selectTabOrdinal(1);
    try std.testing.expectEqual(group_id, workspace.active_group_view.?);
    workspace.selectAdjacentTab(true);
    try std.testing.expectEqual(last_id, workspace.model.active.?);
    // 稿 3 “⌄ n”: choosing a tab from the overflow menu activates it.
    Workspace.stripOverflow(&workspace, @backingInt(group_tab));
    try std.testing.expectEqual(group_id, workspace.active_group_view.?);
    try std.testing.expectEqual(group_tab, workspace.model.active.?);
    try workspace.renderTabBar();
    for (workspace.strip_vm.?.rows_signal.peek()) |row| try std.testing.expectEqual(row.id == @backingInt(group_tab), row.active);
    // Unchanged renders write nothing; the next real change still reaches the rows (the signal
    // keeps the old array on equal content, so a reused arena must not alias it).
    try workspace.renderTabBar();
    try workspace.renderTabBar();
    workspace.activateTabId(last_id);
    try workspace.renderTabBar();
    for (workspace.strip_vm.?.rows_signal.peek()) |row| try std.testing.expectEqual(row.id == @backingInt(last_id), row.active);
    workspace.activateTabId(group_tab);
    try workspace.renderTabBar();
    for (workspace.strip_vm.?.rows_signal.peek()) |row| try std.testing.expectEqual(row.id == @backingInt(group_tab), row.active);
    const previous = try workspace.model.cycleRecent(false, &.{});
    try std.testing.expectEqual(last_id, previous.?);
    workspace.presentTabId(previous.?, .take);
    const again = try workspace.model.cycleRecent(false, &.{});
    try std.testing.expectEqual(first_id, again.?);
    try std.testing.expect(roster.findById(group_id).?.contains(71));
    try std.testing.expectEqual(@as(usize, 1), roster.findById(group_id).?.members.items.len);
    workspace.model.finishRecentSwitch();
    workspace.activateTabId(group_tab);
    try workspace.beginRenamePresentation(group_tab);
    try std.testing.expect(Workspace.commitRename(&workspace, @backingInt(group_tab), "renamed group tab"));
    try std.testing.expectEqualStrings("renamed group tab", workspace.model.tabs.items[workspace.model.indexOf(group_tab).?].name());
    try std.testing.expectEqualStrings("First Local", first.titleSlice());
    try std.testing.expectEqual(group_id, workspace.groupIdByTab(group_tab).?);
    try workspace.showGroupTabMenu(group_id, workspace.tab_nodes.items[1].node);
    try std.testing.expect(workspace.group_tab_menu.?.isOpen());
    // Menu order (one rule, menu_spec.arrange): 重命名… · 颜色 › | layouts | 关闭页签 (danger last);
    // “跟随环境” is not offered for a group.
    const group_items = workspace.group_tab_menu.?.currentItems();
    try std.testing.expectEqualStrings("groups.tab.rename", group_items[0].test_id);
    try std.testing.expectEqualStrings("groups.tab.color", group_items[1].test_id);
    try std.testing.expect(group_items[1].children[0].disabled);
    try std.testing.expect(group_items[2].kind == .separator);
    try std.testing.expectEqualStrings("groups.tab.side", group_items[3].test_id);
    try std.testing.expect(group_items[5].kind == .separator);
    try std.testing.expectEqualStrings("groups.tab.close", group_items[6].test_id);
    try std.testing.expect(group_items[6].danger);
    Workspace.groupMenuSelected(&workspace, "arrange_side");
    try std.testing.expectEqual(group_view.Layout.side_by_side, workspace.groupView(group_id).?.layout);
    Workspace.groupMenuSelected(&workspace, "arrange_stack");
    try std.testing.expectEqual(group_view.Layout.stacked, workspace.groupView(group_id).?.layout);
    Workspace.groupMenuSelected(&workspace, "tab_color.67b88b");
    try std.testing.expectEqual(@as(u32, 0x67b88b), workspace.tabColorChoice(group_tab).?.rgb);
    try workspace.renderTabBar();
    cx.layout();
    workspace.activateTabId(last_id);
    try workspace.renderTabBar();
    cx.layout();
    try std.testing.expectEqual(ui.Color.TRANSPARENT, workspace.tab_nodes.items[1].node.getBackground());
    workspace.strip_vm.?.hover(@backingInt(workspace.tab_nodes.items[1].tab_id), false);
    try std.testing.expectEqual(ui.Color.TRANSPARENT, workspace.tab_nodes.items[1].node.getBackground());
    // The island plate listens to the active tab, including a normal terminal tab.
    const normal_target = try ui.widgets.joined_surface.targetOf(cx, workspace.tab_nodes.items[2].node);
    try std.testing.expect(normal_target.eql(workspace.strip_vm.?.activeSurface().peek()));
    workspace.activateTabId(group_tab);
    try workspace.renderTabBar();
    cx.layout();
    const group_node = workspace.tab_nodes.items[1].node;
    // The group colour tints the type icon and the plate follows the active group.
    try std.testing.expectEqual(ui.Color.hex(0x67b88b), workspace.strip_vm.?.visual(@backingInt(group_tab)).tint);
    const group_target = try ui.widgets.joined_surface.targetOf(cx, group_node);
    try std.testing.expect(group_target.eql(workspace.strip_vm.?.activeSurface().peek()));
    // Actual pointer events must reach the holder's drag binding through the tab.
    const source_rect = workspace.tab_nodes.items[2].node.globalRect();
    const group_rect = group_node.globalRect();
    cx.handleMouseDown(source_rect.x + 35, source_rect.y + 15, .{});
    cx.handleMouseMove(group_rect.x + group_rect.w - 2, group_rect.y + 15);
    cx.layout();
    try std.testing.expectEqual(group_rect, group_node.globalRect());
    cx.handleMouseMove(group_rect.x + group_rect.w / 2, group_rect.y + 15);
    try std.testing.expectEqual(group_tab, workspace.tab_drop_target.?);
    cx.handleMouseUp(group_rect.x + group_rect.w / 2, group_rect.y + 15);
    try std.testing.expect(workspace.pending_tab_drop != null);
    _ = workspace.pollGroupWorkspace();
    try std.testing.expect(roster.findById(group_id).?.contains(last.id));
    try std.testing.expectEqual(group_tab, workspace.model.tabs.items[workspace.model.indexOf(last_id).?].container.?);
}

test "registered nonterminal renderer mounts into the existing tab without a legacy host snapshot" {
    const Driver = struct {
        mounts: usize = 0,
        fn mount(raw: ?*anyopaque, request: plugin_ui.ContentMount) !plugin_ui.RendererInstance {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.mounts += 1;
            try request.slot.appendChild(request.cx.allocator, try ui.text(request.cx, "native nonterminal content", .{}));
            return .{ .context = self, .vtable = &.{ .update = update, .focus_changed = focus, .unmount = unmount } };
        }
        fn update(_: *anyopaque, _: plugin_ui.ContentUpdate) !void {}
        fn focus(_: *anyopaque, _: bool) void {}
        fn unmount(_: *anyopaque) void {}
    };
    const a = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "hosts.toml", .data = "" });
    const path = try tmp.dir.realPathFileAlloc(std.testing.io, "hosts.toml", a);
    defer a.free(path);
    const cx = try ui.Cx.init(a, std.testing.io);
    defer cx.deinit();
    const scope = try ui.Scope.init(a, null, cx.owner);
    defer scope.dispose();
    cx.setViewport(1100, 720);
    cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .direction = .column }, .{});
    var nodes: [4]*ui.Node = undefined;
    for (&nodes) |*node| {
        node.* = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
        try cx.root.?.appendChild(a, node.*);
    }
    const settings: config_mod.Config = .{};
    const workspace = try Workspace.init(a, cx, scope, std.testing.io, &settings, path, nodes[0], nodes[1], nodes[2], nodes[3]);
    var driver: Driver = .{};
    const owner: identity.SessionHandle = .{ .session_id = @fromBackingInt(781), .generation = 3 };
    const id = try workspace.createPluginSession(owner, .{ .id = @fromBackingInt(27), .revision = 1, .protocol_id = "example.canvas", .name = "Canvas owner", .payload_version = 1, .payload = "{}" }, .{ .kind = "example.canvas", .context = &driver, .mount = Driver.mount });
    const tab = workspace.sessionTab(id).?;
    try std.testing.expectEqual(@as(usize, 1), driver.mounts);
    try std.testing.expect(tab.host_snapshot == null and tab.terminal == null and tab.runtime == null);
    try std.testing.expect(tab.plugin_renderer != null);
    try std.testing.expect(tab.content_owner.eql(.{ .session = owner }));
    try std.testing.expectEqualStrings("Canvas owner", workspace.model.tabs.items[0].details);
    try std.testing.expectEqual(@as(usize, 1), workspace.model.tabs.items.len);
    try std.testing.expect(workspace.savedConnectionForTab(0) == null);
    const saved = try workspace.registry.add(.{ .name = "Saved canvas", .host = "", .user = "", .protocol_id = "example.canvas", .plugin_payload = "{}" });
    tab.host_id = @backingInt(saved.id);
    try std.testing.expectEqual(saved, workspace.savedConnectionForTab(0).?);
    tab.host_id = 0;
    try std.testing.expect(workspace.savedConnectionForTab(0) == null);
    try std.testing.expect(workspace.savedConnectionForTab(99) == null);
    _ = cx.render();
    workspace.forceCloseTab(0);
    try std.testing.expectEqual(@as(usize, 0), workspace.model.tabs.items.len);
}

test "workspace environment: adding, switching, closing and removing tabs publish; same-value writes do not" {
    const environment = @import("../../../host/environment.zig");
    const Driver = struct {
        fn mount(raw: ?*anyopaque, request: plugin_ui.ContentMount) !plugin_ui.RendererInstance {
            try request.slot.appendChild(request.cx.allocator, try ui.text(request.cx, "content", .{}));
            return .{ .context = raw.?, .vtable = &.{ .update = update, .focus_changed = focus, .unmount = unmount } };
        }
        fn update(_: *anyopaque, _: plugin_ui.ContentUpdate) !void {}
        fn focus(_: *anyopaque, _: bool) void {}
        fn unmount(_: *anyopaque) void {}
    };
    const Close = struct {
        calls: usize = 0,
        fn request(raw: ?*anyopaque, _: identity.TabId, _: identity.ContentOwner) CloseResult {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.calls += 1;
            return .awaiting;
        }
    };
    const a = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "hosts.toml", .data = "" });
    const path = try tmp.dir.realPathFileAlloc(std.testing.io, "hosts.toml", a);
    defer a.free(path);
    const cx = try ui.Cx.init(a, std.testing.io);
    defer cx.deinit();
    const scope = try ui.Scope.init(a, null, cx.owner);
    defer scope.dispose();
    cx.setViewport(1100, 720);
    cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .direction = .column }, .{});
    var nodes: [4]*ui.Node = undefined;
    for (&nodes) |*node| {
        node.* = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
        try cx.root.?.appendChild(a, node.*);
    }
    const settings: config_mod.Config = .{};
    const workspace = try Workspace.init(a, cx, scope, std.testing.io, &settings, path, nodes[0], nodes[1], nodes[2], nodes[3]);
    var driver: u8 = 0;
    const renderer: plugin_ui.RendererDefinition = .{ .kind = "example.canvas", .context = &driver, .mount = Driver.mount };

    // A new tab (the tab set, the model, the current tab).
    var before = environment.revision();
    const first = try workspace.createPluginSession(.{ .session_id = @fromBackingInt(801), .generation = 1 }, .{ .id = @fromBackingInt(31), .revision = 1, .protocol_id = "example.canvas", .name = "First", .payload_version = 1, .payload = "{}" }, renderer);
    try std.testing.expect(environment.revision() > before);
    _ = try workspace.createPluginSession(.{ .session_id = @fromBackingInt(802), .generation = 1 }, .{ .id = @fromBackingInt(32), .revision = 1, .protocol_id = "example.canvas", .name = "Second", .payload_version = 1, .payload = "{}" }, renderer);
    _ = cx.render();
    try std.testing.expectEqual(@as(?usize, 1), workspace.active_tab);

    // Switching the current tab.
    before = environment.revision();
    workspace.selectTab(0);
    try std.testing.expectEqual(@as(?usize, 0), workspace.active_tab);
    try std.testing.expect(environment.revision() > before);
    before = environment.revision();
    workspace.selectTab(0);
    workspace.setActiveTab(0);
    try std.testing.expectEqual(before, environment.revision());

    // Closing: the tab is retained while its owner releases it.
    var close: Close = .{};
    workspace.close_bridge = .{ .context = &close, .request_close = Close.request };
    const tab = workspace.sessionTab(first).?;
    workspace.forceCloseTab(0);
    try std.testing.expect(tab.closing);
    try std.testing.expect(environment.revision() > before);
    before = environment.revision();
    workspace.forceCloseTab(0);
    try std.testing.expectEqual(@as(usize, 2), close.calls);
    try std.testing.expectEqual(before, environment.revision());

    // The released tab leaves the tab set; the other tab becomes current.
    workspace.close_bridge = .{};
    workspace.removeClosedTab(0);
    try std.testing.expectEqual(@as(usize, 1), workspace.tabs.items.len);
    try std.testing.expectEqual(@as(?usize, 0), workspace.active_tab);
    try std.testing.expect(environment.revision() > before);

    // Each tab setter publishes only an actual change.
    const remaining = workspace.tabs.items[0];
    before = environment.revision();
    remaining.setClosing(false);
    remaining.setFloating(false);
    remaining.setOwnedPending(false);
    remaining.setRuntime(null);
    remaining.setPluginRenderer(remaining.plugin_renderer);
    remaining.setContentOwner(remaining.content_owner);
    try std.testing.expectEqual(before, environment.revision());
    remaining.setContentOwner(.{ .session = .{ .session_id = @fromBackingInt(802), .generation = 2 } });
    try std.testing.expect(environment.revision() > before);
    remaining.setContentOwner(.{ .session = .{ .session_id = @fromBackingInt(802), .generation = 1 } });
    // The title (shown by the AI's approval panel): only a different title publishes.
    before = environment.revision();
    remaining.setTitle(remaining.titleSlice());
    try std.testing.expectEqual(before, environment.revision());
    remaining.setTitle("Renamed");
    try std.testing.expect(environment.revision() > before);
    try std.testing.expectEqualStrings("Renamed", remaining.titleSlice());
    workspace.forceCloseTab(0);
    try std.testing.expectEqual(@as(usize, 0), workspace.tabs.items.len);
}

test "asset action projections retain plugin sessions after deletion without inventing SSH endpoints" {
    const a = std.testing.allocator;
    var workspace: Workspace = undefined;
    workspace.registry = .{ .arena = .init(a), .hosts = &.{} };
    defer workspace.registry.deinit();
    workspace.plugins = .{ .published = .{ .entries = &.{.{ .id = "bmc_ikvm", .display_name = "BMC · iKVM", .workspace_kind = "bmc_ikvm", .content_renderer = "bmc_ikvm" }}, .renderers = &.{} } };
    workspace.tabs = .empty;
    defer workspace.tabs.deinit(a);
    const saved = try workspace.registry.add(.{ .name = "Saved KVM", .host = "", .user = "", .protocol_id = "bmc_ikvm", .plugin_payload = "{}" });
    var tab: SessionTab = .{
        .id = 17,
        .tab_id = @fromBackingInt(17),
        .content_owner = .{ .session = .{ .session_id = @fromBackingInt(17) } },
        .host_id = @backingInt(saved.id),
        .host_index = 0,
        .host_snapshot = null,
        .root = undefined,
        .plugin_protocol_id = "bmc_ikvm",
    };
    try workspace.tabs.append(a, &tab);
    const expected: Workspace.ConnectionTabs = .{ .count = 1, .first_index = 0 };
    try std.testing.expectEqual(saved.id, tab.sourceConnectionId().?);
    try std.testing.expectEqualDeep(expected, workspace.connectionTabs(saved.id));
    try std.testing.expectEqual(saved, workspace.savedConnectionForTab(0).?);
    const endpoint = try workspace.assetActionEndpoint(a, try workspace.registry.get(saved));
    defer a.free(endpoint);
    try std.testing.expectEqualStrings("BMC · iKVM", endpoint);

    // The asset action removes only configuration; the existing frozen tab
    // must remain countable and selectable from its success panel.
    try workspace.registry.remove(saved);
    try std.testing.expect(workspace.savedConnectionForTab(0) == null);
    try std.testing.expectEqualDeep(expected, workspace.connectionTabs(saved.id));
    tab.host_id = 0;
    try std.testing.expect(tab.sourceConnectionId() == null);
    try std.testing.expectEqualDeep(Workspace.ConnectionTabs{}, workspace.connectionTabs(saved.id));
    try std.testing.expectEqualDeep(Workspace.ConnectionTabs{}, workspace.connectionTabs(@fromBackingInt(0)));

    var legacy: hosts_mod.HostConfig = .{ .name = "SSH", .host = "legacy.example", .port = 2222, .user = "operator" };
    const ssh_endpoint = try workspace.assetActionEndpoint(a, legacy);
    defer a.free(ssh_endpoint);
    try std.testing.expectEqualStrings("operator@legacy.example:2222", ssh_endpoint);
    legacy.protocol_id = "future.plugin";
    const future_endpoint = try workspace.assetActionEndpoint(a, legacy);
    defer a.free(future_endpoint);
    try std.testing.expectEqualStrings("future.plugin", future_endpoint);
}

test "workspace creation without its registered session host never starts a native connection" {
    var workspace: Workspace = undefined;
    workspace.session_bridge = .{};
    try std.testing.expectError(error.SessionHostUnavailable, workspace.createSession(.{ .name = "offline", .host = "unreachable.invalid", .user = "test" }, 1, 0, ""));
}

test "group session creation new and duplicate preserve group without duplicate tab or source feedback" {
    const allocator = std.testing.allocator;
    const cx = try ui.Cx.init(allocator, std.testing.io);
    defer cx.deinit();
    const scope = try ui.Scope.init(allocator, null, cx.owner);
    defer scope.dispose();
    const root = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .direction = .column }, .{});
    cx.root = root;
    const strip = try ui.box(cx, .{ .width = .fill(), .height = .{ .px = 46 }, .flex_shrink = 0 }, .{});
    try root.appendChild(allocator, strip);
    const area = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .flex = 1, .direction = .column }, .{});
    try root.appendChild(allocator, area);
    const empty = try ui.box(cx, .{ .display = .none }, .{});
    try area.appendChild(allocator, empty);
    const sidebar = try ui.box(cx, .{ .display = .none }, .{});
    try root.appendChild(allocator, sidebar);
    const config: config_mod.Config = .{};
    const workspace = try allocator.create(Workspace);
    workspace.* = .{ .allocator = allocator, .cx = cx, .scope = scope, .io = std.testing.io, .app_config = &config, .palette = Palette.fromTheme(), .registry = .{ .arena = std.heap.ArenaAllocator.init(allocator), .hosts = &.{} }, .hosts_path = "", .sidebar_list = sidebar, .tab_bar = strip, .terminal_area = area, .empty_state = empty, .model = .{ .allocator = allocator, .window = @fromBackingInt(1), .workspace = @fromBackingInt(1) } };
    try scope.onCleanup(Workspace, workspace, Workspace.cleanup);
    cx.setViewport(1194, 800);
    var roster = group_model.Roster.init(allocator);
    defer roster.deinit();
    const original = try workspace.createLocalSessionDirect(.{ .session_id = @fromBackingInt(50) });
    const group = (try roster.join("Acceptance", original, 0xff818cf8)).id;
    try workspace.openGroup(&roster, group);
    const Factory = struct {
        workspace: *Workspace,
        calls: usize = 0,
        feedback: usize = 0,
        fn create(raw: ?*anyopaque, _: SessionId) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.calls += 1;
            _ = try self.workspace.createLocalSessionDirect(.{ .session_id = @fromBackingInt(50 + self.calls) });
            self.workspace.status("连接中…");
        }
        fn feedbackStatus(raw: *anyopaque, _: ?identity.ContentOwner, _: []const u8, _: Workspace.StatusKind) void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.feedback += 1;
        }
        fn host(raw: ?*anyopaque, _: hosts_mod.HostConfig, _: HostId, _: usize, _: []const u8) !void {
            try create(raw, 0);
        }
    };
    var factory: Factory = .{ .workspace = workspace };
    workspace.session_bridge = .{ .context = &factory, .recreate = Factory.create, .duplicate_local = Factory.create };
    workspace.status_feedback = .{ .context = &factory, .publish = Factory.feedbackStatus };
    workspace.command_output = &workspace.sessionTab(original).?.terminal.?;
    try workspace.newSessionFromTab(workspace.tabIndex(original).?);
    try std.testing.expectEqual(@as(usize, 1), factory.calls);
    try std.testing.expectEqual(@as(usize, 2), workspace.tabs.items.len);
    try std.testing.expectEqual(@as(usize, 2), workspace.model.visibleCount());
    try std.testing.expectEqual(group, workspace.active_group_view.?);
    const created = workspace.tabs.items[1];
    try std.testing.expect(roster.findById(group).?.contains(created.id));
    try std.testing.expectEqual(workspace.groupTabId(group), workspace.model.tabs.items[workspace.model.indexOf(created.tab_id).?].container);
    workspace.sessionTab(original).?.tab_color = 0x67b88b;
    try workspace.duplicateSessionFromTab(workspace.tabIndex(original).?);
    try std.testing.expectEqual(@as(?u32, 0x67b88b), workspace.tabs.items[2].tab_color);
    try std.testing.expectEqual(@as(?u32, null), workspace.creation_tab_color);
    try std.testing.expectEqual(@as(usize, 2), factory.calls);
    try std.testing.expectEqual(@as(usize, 3), workspace.tabs.items.len);
    try std.testing.expectEqual(@as(usize, 3), roster.findById(group).?.members.items.len);
    try std.testing.expectEqual(@as(usize, 2), workspace.model.visibleCount());
    try std.testing.expectEqual(@as(usize, 2), factory.feedback);
    try std.testing.expect(workspace.sessionTab(original).?.terminal.?.command_message == null);
    try roster.leave("Acceptance", created.id);
    workspace.refreshGroup(group);
    try std.testing.expectEqual(@as(?identity.TabId, null), workspace.model.tabs.items[workspace.model.indexOf(created.tab_id).?].container);
    try std.testing.expectEqual(@as(usize, 3), workspace.model.visibleCount());
    workspace.selectTab(workspace.tabIndex(created.id).?);
    try std.testing.expect(workspace.active_group_view == null);
    try std.testing.expectEqual(created.tab_id, workspace.model.active.?);
    workspace.command_output = null;
    workspace.status_feedback = null;
    const standalone = try workspace.createLocalSessionDirect(.{ .session_id = @fromBackingInt(99) });
    try workspace.renameTab(workspace.tabIndex(standalone).?, "Quick session");
    workspace.selectTab(workspace.tabIndex(standalone).?);
    try workspace.duplicateSessionIntoGroup(workspace.tabIndex(standalone).?);
    try std.testing.expectEqual(@as(usize, 1), roster.groups.items.len);
    _ = workspace.pollGroupWorkspace();
    try std.testing.expect(workspace.pending_tab_drop == null);
    const quick_group = workspace.active_group_view.?;
    try std.testing.expectEqualStrings("Quick session", roster.findById(quick_group).?.name);
    try std.testing.expectEqual(@as(usize, 2), roster.findById(quick_group).?.members.items.len);
    try std.testing.expect(roster.findById(quick_group).?.contains(standalone));
    const host_index = try workspace.appendHost(.{ .name = "Another asset", .host = "fixture.invalid", .user = "fixture" });
    workspace.session_bridge.create = Factory.host;
    const before_calls = factory.calls;
    const parent = workspace.groupTabId(quick_group).?;
    try workspace.openHostInGroup(host_index, parent);
    try std.testing.expectEqual(before_calls + 1, factory.calls);
    _ = workspace.pollGroupWorkspace();
    try std.testing.expectEqual(@as(usize, 3), roster.findById(quick_group).?.members.items.len);
    try std.testing.expectEqual(@as(usize, 2), roster.groups.items.len);
    // A stale captured asset must not start another connection on drop.
    workspace.pending_host_group_drop = .{ .owner = workspace.registry.hosts[host_index].owner(), .target = parent };
    workspace.registry.hosts[host_index].revision += 1;
    _ = workspace.pollGroupWorkspace();
    try std.testing.expectEqual(before_calls + 1, factory.calls);
}

test "workspace close and host key confirmations are native Modals with the zenit default barrier and panel" {
    const a = std.testing.allocator;
    const cx = try ui.Cx.init(a, std.testing.io);
    defer cx.deinit();
    cx.setViewport(1440, 900);
    const scope = try ui.Scope.init(a, null, cx.owner);
    defer scope.dispose();
    const root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    cx.root = root;
    const config: config_mod.Config = .{};
    var workspace: Workspace = .{
        .allocator = a,
        .cx = cx,
        .scope = scope,
        .io = std.testing.io,
        .app_config = &config,
        .palette = Palette.fromTheme(),
        .registry = .{ .arena = std.heap.ArenaAllocator.init(a), .hosts = &.{} },
        .hosts_path = "",
        .sidebar_list = root,
        .tab_bar = root,
        .model = .{ .allocator = a, .window = @fromBackingInt(1), .workspace = @fromBackingInt(1) },
        .terminal_area = root,
        .empty_state = root,
    };
    defer workspace.registry.arena.deinit();
    defer workspace.confirm_risk_rows.deinit(a);
    try workspace.mountCloseConfirm();
    try workspace.mountHostKeyConfirm();
    const colors = cx.tokens.tokens.color;
    try std.testing.expectEqualStrings("session.close.confirm", workspace.confirm_card.?.meta.ownership.meta.test_id.?);
    for ([_]*ui.Node{ workspace.confirm_root.?, workspace.host_key_root.? }, [_]*ui.Node{ workspace.confirm_card.?, workspace.host_key_card.? }) |barrier, dialog| {
        // zenit Modal: the dialog panel is the barrier's child, nothing repaints either.
        try std.testing.expectEqual(barrier, dialog.parent.?);
        try std.testing.expectEqual(colors.overlay, barrier.getBackground());
        try std.testing.expect(barrier.getBackground().a > 0);
        try std.testing.expectEqual(colors.bg_primary, dialog.getBackground());
        try std.testing.expect(dialog.style.backdrop_blur() == 0);
    }
    // Esc proposes closing the open dialog: the close confirmation cancels.
    workspace.confirming_id = @fromBackingInt(7);
    workspace.confirm_open.?.set(true);
    _ = cx.render();
    try std.testing.expect(workspace.confirm_open.?.peek());
    cx.handleKeyDown(.escape, .{});
    _ = cx.render();
    try std.testing.expect(!workspace.confirm_open.?.peek());
    try std.testing.expect(workspace.confirming_id == null);
    // Host key: Esc is 拒绝 (no job here, so it only hides).
    workspace.host_key_open.?.set(true);
    _ = cx.render();
    cx.handleKeyDown(.escape, .{});
    _ = cx.render();
    try std.testing.expect(!workspace.host_key_open.?.peek());
}

test "repeated close on retained closing tab reaches the same owner bridge" {
    const Retry = struct {
        calls: usize = 0,
        fn request(raw: ?*anyopaque, _: identity.TabId, _: identity.ContentOwner) CloseResult {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.calls += 1;
            return .awaiting;
        }
    };
    var retry: Retry = .{};
    var tab: SessionTab = undefined;
    tab.closing = true;
    tab.tab_id = @fromBackingInt(12);
    tab.content_owner = .{ .session = .{ .session_id = @fromBackingInt(22) } };
    var tabs = [_]*SessionTab{&tab};
    var workspace: Workspace = undefined;
    workspace.tabs = .empty;
    workspace.tabs.items = &tabs;
    workspace.tabs.capacity = 1;
    workspace.close_bridge = .{ .context = &retry, .request_close = Retry.request };
    workspace.status_feedback = null;
    workspace.status_node = null;
    workspace.command_output = null;
    workspace.requestCloseTab(0);
    workspace.requestCloseTab(0);
    try std.testing.expectEqual(@as(usize, 2), retry.calls);
    try std.testing.expect(tab.closing);
}

test "mixed session group mounts terminal file KVM and future content and retains split proportions and resize cursor" {
    const a = std.testing.allocator;
    const cx = try ui.Cx.init(a, std.testing.io);
    defer cx.deinit();
    cx.setViewport(1280, 720);
    const scope = try ui.Scope.init(a, null, cx.owner);
    const root = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .direction = .column }, .{});
    cx.root = root;
    const strip = try ui.box(cx, .{ .width = .fill(), .height = .{ .px = 32 }, .flex_shrink = 0 }, .{});
    const area = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .hit_behavior = .@"opaque" }, .{});
    const empty = try ui.box(cx, .{}, .{});
    try root.appendChild(a, strip);
    try root.appendChild(a, area);
    try area.appendChild(a, empty);
    const config: config_mod.Config = .{};
    var roster = group_model.Roster.init(a);
    defer roster.deinit();
    var workspace: Workspace = .{ .allocator = a, .cx = cx, .scope = scope, .io = std.testing.io, .app_config = &config, .palette = Palette.fromTheme(), .registry = .{ .arena = std.heap.ArenaAllocator.init(a), .hosts = &.{} }, .hosts_path = "", .sidebar_list = root, .tab_bar = strip, .terminal_area = area, .empty_state = empty, .model = .{ .allocator = a, .window = @fromBackingInt(1), .workspace = @fromBackingInt(1) }, .group_roster = &roster };
    const Renderer = struct {
        fn update(_: *anyopaque, _: plugin_ui.ContentUpdate) !void {}
        fn focus(raw: *anyopaque, focused: bool) void {
            const flag: *bool = @ptrCast(@alignCast(raw));
            flag.* = focused;
        }
        fn unmount(_: *anyopaque) void {}
        fn status(_: *anyopaque) plugin_ui.ConnectionStatus {
            return .{ .state = .online, .label = "视频已连接" };
        }
    };
    var kvm_focused = false;
    var tabs: [5]SessionTab = undefined;
    var count: usize = 0;
    defer {
        for (tabs[0..count]) |*tab| if (tab.terminal) |*terminal| terminal.releaseBuffers(cx);
        if (workspace.poll_hook) |hook| {
            cx.removeAfterLayoutHook(hook);
            a.destroy(hook);
            workspace.poll_hook = null;
        }
        scope.dispose();
        for (workspace.click_ctxs.items) |cell| a.destroy(cell);
        workspace.click_ctxs.deinit(a);
        workspace.tab_nodes.deinit(a);
        workspace.strip_advances.deinit(a);
        workspace.strip_widths.deinit(a);
        workspace.strip_grouped.deinit(a);
        workspace.tabs.deinit(a);
        workspace.model.deinit();
        workspace.registry.deinit();
        for (workspace.group_views.items) |view| {
            view.deinit(a);
            a.destroy(view);
        }
        workspace.group_views.deinit(a);
    }
    const kinds = [_][]const u8{ "local", "ssh", "sftp", "bmc_ikvm", "future-renderer" };
    for (&tabs, kinds, 0..) |*tab, kind, i| {
        const terminal: ?TerminalViewNode = if (i < 2) try TerminalViewNode.mount(cx) else null;
        const content = if (terminal) |view| view.root else try ui.box(cx, .{ .width = .fill(), .height = .fill(), .hit_behavior = .@"opaque" }, .{});
        try area.appendChild(a, content);
        tab.* = .{ .id = 101 + i, .tab_id = try tab_ids.allocate(), .content_owner = .{ .session = .{ .session_id = @fromBackingInt(101 + i) } }, .host_id = 0, .host_index = 0, .host_snapshot = null, .root = content, .terminal = terminal, .local = i == 0, .plugin_protocol_id = if (i >= 2) kind else "", .content_ready = true, .file_ready = i == 2 };
        if (i == 3) tab.plugin_renderer = .{ .context = &kvm_focused, .vtable = &.{ .update = Renderer.update, .focus_changed = Renderer.focus, .unmount = Renderer.unmount, .connection_status = Renderer.status } };
        count += 1;
        tab.setTitle(kind);
        try workspace.tabs.append(a, tab);
        try workspace.installTabModel(tab);
        var target: Workspace.GroupJoinTarget = .{ .workspace = &workspace, .tab_id = tab.tab_id, .owner = tab.content_owner };
        try Workspace.GroupJoinTarget.join(&target, "Mixed");
    }
    const group = roster.find("Mixed").?;
    const view = workspace.groupView(group.id).?;
    try workspace.presentGroup(view);
    cx.layout();
    try std.testing.expectEqual(@as(usize, 5), view.panes.items.len);
    for (tabs, view.panes.items) |tab, pane| try std.testing.expect(tab.root.parent == pane.node);
    // Selecting a member through its header must hand keyboard input to the
    // same member; the visual active-member marker alone is insufficient.
    for (0..3) |_| {
        cx.advanceFrameClock();
        _ = cx.render();
    }
    const member_title = view.panes.items[1].node.children.items[0].children.items[1].globalRect();
    cx.handleMouseDown(member_title.x + member_title.w / 2, member_title.y + member_title.h / 2, .{});
    cx.handleMouseUp(member_title.x + member_title.w / 2, member_title.y + member_title.h / 2);
    try std.testing.expectEqual(tabs[1].id, view.focused.?);
    try std.testing.expect(cx.focus_manager.getFocused() == tabs[1].terminal.?.root);
    const outside_editor = try ui.widgets.Input(.{ .placeholder = "assistant or other outside editor" }).mountResult(scope, cx);
    outside_editor.node.setStyleInline(a, .{ .position = .absolute, .inset = .{ .left = .{ .px = 0 }, .top = .{ .px = 0 } }, .width = .{ .px = 120 }, .height = .{ .px = 24 } });
    try root.appendChild(a, outside_editor.node);
    cx.setFocus(outside_editor.input_container);
    // Group status/membership updates rebuild the presentation while an AI
    // composer or another outside editor can still own keyboard input.
    try workspace.presentGroup(view);
    cx.advanceFrameClock();
    _ = cx.render();
    try std.testing.expect(cx.focus_manager.getFocused() == outside_editor.input_container);
    cx.setFocus(tabs[1].terminal.?.root);
    try roster.leave("Mixed", tabs[4].id);
    try workspace.dockGroupMember(group.id, tabs[0].id, tabs[1].id, .top);
    try workspace.dockGroupMember(group.id, tabs[2].id, tabs[3].id, .top);
    try workspace.presentGroup(view);
    const split_id = view.tree.root.?;
    const left_id = view.tree.nodes.items[split_id].split.first;
    const right_id = view.tree.nodes.items[split_id].split.second;
    view.tree.nodes.items[split_id].split.ratio = 0.6;
    view.tree.nodes.items[left_id].split.ratio = 0.65;
    view.tree.nodes.items[right_id].split.ratio = 0.35;
    try workspace.presentGroup(view);
    cx.layout();
    const first = view.panes.items[0].node.globalRect();
    const second = view.panes.items[1].node.globalRect();
    const third = view.panes.items[2].node.globalRect();
    const fourth = view.panes.items[3].node.globalRect();
    try std.testing.expectApproxEqAbs(first.x, second.x, 0.1);
    try std.testing.expectApproxEqAbs(third.x, fourth.x, 0.1);
    try std.testing.expect(first.w > third.w);
    try std.testing.expect(second.y > fourth.y + 100);
    const tree_root = view.root.?.children.items[0];
    const divider = tree_root.children.items[1].globalRect();
    cx.handleMouseMove(divider.x + 2, divider.y + 90);
    try std.testing.expectEqual(ui.CursorShape.ew_resize, cx.current_cursor);
    const resize_focus = cx.focus_manager.getFocused();
    try std.testing.expect(resize_focus != null);
    cx.handleMouseDown(divider.x + 2, divider.y + 90, .{});
    try std.testing.expect(cx.focus_manager.getFocused() == resize_focus);
    cx.handleMouseMove(divider.x + 62, divider.y + 90);
    try std.testing.expectEqual(ui.CursorShape.ew_resize, cx.current_cursor);
    cx.handleMouseUp(divider.x + 62, divider.y + 90);
    try std.testing.expect(cx.focus_manager.getFocused() == resize_focus);
    cx.layout();
    try std.testing.expect(view.panes.items[0].node.globalRect().w > first.w + 40);
    try std.testing.expectApproxEqAbs(third.h, view.panes.items[2].node.globalRect().h, 0.1);
    const upper = view.panes.items[0].node.globalRect();
    const horizontal = tree_root.children.items[0].children.items[1].globalRect();
    cx.handleMouseMove(horizontal.x + 100, horizontal.y + 2);
    try std.testing.expectEqual(ui.CursorShape.ns_resize, cx.current_cursor);
    cx.handleMouseDown(horizontal.x + 100, horizontal.y + 2, .{});
    cx.handleMouseMove(horizontal.x + 100, horizontal.y - 28);
    try std.testing.expectEqual(ui.CursorShape.ns_resize, cx.current_cursor);
    cx.handleMouseUp(horizontal.x + 100, horizontal.y - 28);
    cx.layout();
    try std.testing.expect(view.panes.items[0].node.globalRect().h < upper.h - 10);
    try std.testing.expectApproxEqAbs(third.h, view.panes.items[2].node.globalRect().h, 0.1);
    const before_cancel = view.tree.nodes.items[left_id].split.ratio;
    const next_divider = tree_root.children.items[0].children.items[1].globalRect();
    cx.handleMouseDown(next_divider.x + 100, next_divider.y + 2, .{});
    cx.handleMouseMove(next_divider.x + 100, next_divider.y + 20);
    cx.cancelPointerInteractions(.window_blur);
    try std.testing.expect(cx.focus_manager.getFocused() == resize_focus);
    try std.testing.expectApproxEqAbs(before_cancel, view.tree.nodes.items[left_id].split.ratio, 0.001);
    cx.layout();
    try std.testing.expectEqual(.online, Workspace.groupConnectionState(&tabs[3]));
    const kvm_rect = view.panes.items[3].node.globalRect();
    cx.handleMouseDown(kvm_rect.x + 20, kvm_rect.y + 50, .{});
    cx.handleMouseUp(kvm_rect.x + 20, kvm_rect.y + 50);
    try std.testing.expect(kvm_focused);
    const local_rect = view.panes.items[0].node.globalRect();
    cx.handleMouseDown(local_rect.x + 20, local_rect.y + 50, .{});
    cx.handleMouseUp(local_rect.x + 20, local_rect.y + 50);
    try std.testing.expect(!kvm_focused);
    workspace.setGroupMemberBroadcast(tabs[3].id, true);
    try std.testing.expect(!tabs[3].group_broadcast_enabled);
    // A stale picker cannot move a replacement generation into the group.
    var stale: Workspace.GroupJoinTarget = .{ .workspace = &workspace, .tab_id = tabs[4].tab_id, .owner = tabs[4].content_owner };
    tabs[4].content_owner.session.generation += 1;
    try std.testing.expectError(error.StaleSession, Workspace.GroupJoinTarget.join(&stale, "Other"));
    var file: Workspace.GroupJoinTarget = .{ .workspace = &workspace, .tab_id = tabs[2].tab_id, .owner = tabs[2].content_owner };
    try Workspace.GroupJoinTarget.leave(&file);
    try std.testing.expect(!group.contains(tabs[2].id));
    try std.testing.expect(!tabs[2].closing);
}

test "pane header connection dot uses the tab dot phase mapping: connecting is amber and the dot follows the phase" {
    const a = std.testing.allocator;
    const cx = try ui.Cx.init(a, std.testing.io);
    defer cx.deinit();
    cx.setViewport(1280, 720);
    const scope = try ui.Scope.init(a, null, cx.owner);
    const root = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .direction = .column }, .{});
    cx.root = root;
    const strip = try ui.box(cx, .{ .width = .fill(), .height = .{ .px = 32 }, .flex_shrink = 0 }, .{});
    const area = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .hit_behavior = .@"opaque" }, .{});
    const empty = try ui.box(cx, .{}, .{});
    try root.appendChild(a, strip);
    try root.appendChild(a, area);
    try area.appendChild(a, empty);
    const config: config_mod.Config = .{};
    var roster = group_model.Roster.init(a);
    defer roster.deinit();
    var workspace: Workspace = .{ .allocator = a, .cx = cx, .scope = scope, .io = std.testing.io, .app_config = &config, .palette = Palette.fromTheme(), .registry = .{ .arena = std.heap.ArenaAllocator.init(a), .hosts = &.{} }, .hosts_path = "", .sidebar_list = root, .tab_bar = strip, .terminal_area = area, .empty_state = empty, .model = .{ .allocator = a, .window = @fromBackingInt(1), .workspace = @fromBackingInt(1) }, .group_roster = &roster };
    const State = @FieldType(plugin_ui.ConnectionStatus, "state");
    // The renderer reports whatever phase the test sets: the pane header must not keep its own mapping.
    const Renderer = struct {
        fn update(_: *anyopaque, _: plugin_ui.ContentUpdate) !void {}
        fn focus(_: *anyopaque, _: bool) void {}
        fn unmount(_: *anyopaque) void {}
        fn status(raw: *anyopaque) plugin_ui.ConnectionStatus {
            const state: *State = @ptrCast(@alignCast(raw));
            return .{ .state = state.*, .label = @tagName(state.*) };
        }
    };
    var state: State = .connecting;
    var tabs: [2]SessionTab = undefined;
    var count: usize = 0;
    defer {
        if (workspace.poll_hook) |hook| {
            cx.removeAfterLayoutHook(hook);
            a.destroy(hook);
            workspace.poll_hook = null;
        }
        scope.dispose();
        for (workspace.click_ctxs.items) |cell| a.destroy(cell);
        workspace.click_ctxs.deinit(a);
        workspace.tab_nodes.deinit(a);
        workspace.strip_advances.deinit(a);
        workspace.strip_widths.deinit(a);
        workspace.strip_grouped.deinit(a);
        workspace.tabs.deinit(a);
        workspace.model.deinit();
        workspace.registry.deinit();
        for (workspace.group_views.items) |view| {
            view.deinit(a);
            a.destroy(view);
        }
        workspace.group_views.deinit(a);
    }
    for (&tabs, 0..) |*tab, i| {
        const content = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .hit_behavior = .@"opaque" }, .{});
        try area.appendChild(a, content);
        tab.* = .{ .id = 301 + i, .tab_id = try tab_ids.allocate(), .content_owner = .{ .session = .{ .session_id = @fromBackingInt(301 + i) } }, .host_id = 0, .host_index = 0, .host_snapshot = null, .root = content, .terminal = null, .plugin_protocol_id = "bmc_ikvm", .content_ready = true };
        tab.plugin_renderer = .{ .context = &state, .vtable = &.{ .update = Renderer.update, .focus_changed = Renderer.focus, .unmount = Renderer.unmount, .connection_status = Renderer.status } };
        count += 1;
        tab.setTitle("kvm");
        try workspace.tabs.append(a, tab);
        try workspace.installTabModel(tab);
        var target: Workspace.GroupJoinTarget = .{ .workspace = &workspace, .tab_id = tab.tab_id, .owner = tab.content_owner };
        try Workspace.GroupJoinTarget.join(&target, "Dots");
    }
    const group = roster.find("Dots").?;
    const view = workspace.groupView(group.id).?;
    try workspace.presentGroup(view);
    cx.layout();
    try std.testing.expectEqual(@as(usize, 2), view.panes.items.len);
    const settle = struct {
        fn run(c: *ui.Cx) void {
            c.advanceFrameClock();
            _ = c.render();
        }
    }.run;
    const expectDots = struct {
        fn run(ws: *Workspace, v: anytype, members: []SessionTab, tone: status_tone.Tone) !void {
            for (members, v.panes.items) |*tab, pane| {
                const header_dot = findTestIdIn(pane.node, "groups.pane.status_dot").?;
                // The same colour the tab strip paints for this tab, and the tone of the phase.
                try std.testing.expect(ui.Color.eql(ws.tabConnectionColor(tab.tab_id), header_dot.getBackground()));
                try std.testing.expect(ui.Color.eql(status_tone.dot(tone), header_dot.getBackground()));
            }
        }
    }.run;
    settle(cx);
    // Connecting is amber (warn), the same as the tab dot — not the old online-or-red.
    try std.testing.expect(!ui.Color.eql(status_tone.dot(.warn), status_tone.dot(.danger)));
    try expectDots(&workspace, view, &tabs, .warn);
    // The per-frame refresh writes the dot signal in place (phase facts outside the group hash, such as the remote
    // notice, reach the header only this way): same node, new colour, no re-present.
    const header_before = findTestIdIn(view.panes.items[0].node, "groups.pane.status_dot").?;
    state = .online;
    workspace.refreshPaneDots(view);
    try std.testing.expect(findTestIdIn(view.panes.items[0].node, "groups.pane.status_dot").? == header_before);
    try expectDots(&workspace, view, &tabs, .ok);
    settle(cx);
    try expectDots(&workspace, view, &tabs, .ok);
    // Through the workspace poll (the plugin state is part of the group hash, so this one re-presents): still one mapping.
    state = .degraded;
    _ = workspace.pollGroupWorkspace();
    cx.layout();
    settle(cx);
    try expectDots(&workspace, view, &tabs, .danger);
}

test "reconnect configuration reads current host commands global policy and host overrides" {
    var registry = try hosts_mod.Registry.parse(std.testing.allocator, "[[hosts]]\nname=\"target\"\nhost=\"target.test\"\nuser=\"operator\"\nstartup_commands=[\"old command\"]\n");
    defer registry.deinit();
    const original = registry.hosts[0];
    var config: config_mod.Config = .{};
    var workspace: Workspace = undefined;
    workspace.registry = registry;
    workspace.app_config = &config;
    config.ssh.auto_shell_integration = false;
    registry.hosts[0].startup_commands = &.{"new command"};
    var resolved = workspace.reconnectConfiguration(original);
    try std.testing.expectEqualStrings("new command", resolved.startup_commands[0]);
    try std.testing.expect(!resolved.auto_shell_integration);
    registry.hosts[0].auto_shell_integration = true;
    resolved = workspace.reconnectConfiguration(original);
    try std.testing.expect(resolved.auto_shell_integration);
    workspace.registry.hosts = &.{};
    resolved = workspace.reconnectConfiguration(original);
    try std.testing.expectEqualStrings("old command", resolved.startup_commands[0]);
    try std.testing.expect(!resolved.auto_shell_integration);
}

fn firstFocusableIn(cx: *ui.Cx, root: *ui.Node) ?*ui.Node {
    for (cx.focus_manager.focus_order.items) |candidate| if (candidate.isDescendantOf(root)) return candidate;
    return null;
}

fn findTestIdIn(node: *ui.Node, id: []const u8) ?*ui.Node {
    if (node.meta.ownership.meta.test_id) |value| if (std.mem.eql(u8, value, id)) return node;
    for (node.children.items) |child| if (findTestIdIn(child, id)) |found| return found;
    return null;
}

test "float-split: a floating card docks into its standalone tab as a two-card split, keeps its content node and state, and floats back" {
    const a = std.testing.allocator;
    const cx = try ui.Cx.init(a, std.testing.io);
    defer cx.deinit();
    cx.setViewport(1280, 720);
    const scope = try ui.Scope.init(a, null, cx.owner);
    const root = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .direction = .column }, .{});
    cx.root = root;
    const strip = try ui.box(cx, .{ .width = .fill(), .height = .{ .px = 32 }, .flex_shrink = 0 }, .{});
    const area = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .hit_behavior = .@"opaque" }, .{});
    const empty = try ui.box(cx, .{}, .{});
    try root.appendChild(a, strip);
    try root.appendChild(a, area);
    try area.appendChild(a, empty);
    const config: config_mod.Config = .{};
    var roster = group_model.Roster.init(a);
    defer roster.deinit();
    var workspace: Workspace = .{ .allocator = a, .cx = cx, .scope = scope, .io = std.testing.io, .app_config = &config, .palette = Palette.fromTheme(), .registry = .{ .arena = std.heap.ArenaAllocator.init(a), .hosts = &.{} }, .hosts_path = "", .sidebar_list = root, .tab_bar = strip, .terminal_area = area, .empty_state = empty, .model = .{ .allocator = a, .window = @fromBackingInt(1), .workspace = @fromBackingInt(1) }, .group_roster = &roster };
    var tab: SessionTab = undefined;
    defer {
        if (workspace.poll_hook) |hook| {
            cx.removeAfterLayoutHook(hook);
            a.destroy(hook);
            workspace.poll_hook = null;
        }
        scope.dispose();
        for (workspace.click_ctxs.items) |cell| a.destroy(cell);
        workspace.click_ctxs.deinit(a);
        workspace.tab_nodes.deinit(a);
        workspace.strip_advances.deinit(a);
        workspace.strip_widths.deinit(a);
        workspace.strip_grouped.deinit(a);
        workspace.tabs.deinit(a);
        workspace.model.deinit();
        workspace.registry.deinit();
        for (workspace.group_views.items) |view| {
            view.deinit(a);
            a.destroy(view);
        }
        workspace.group_views.deinit(a);
    }
    const session_root = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .hit_behavior = .@"opaque" }, .{});
    try area.appendChild(a, session_root);
    tab = .{ .id = 201, .tab_id = try tab_ids.allocate(), .content_owner = .{ .session = .{ .session_id = @fromBackingInt(201) } }, .host_id = 0, .host_index = 0, .host_snapshot = null, .root = session_root, .terminal = null, .plugin_protocol_id = "future-renderer", .content_ready = true };
    tab.setTitle("probe");
    try workspace.tabs.append(a, &tab);
    try workspace.installTabModel(&tab);
    workspace.selectTab(0);
    cx.layout();
    // The floating card: the test-mode fixture content (native Input + ScrollArea of Buttons).
    const fixture_view = @import("float_fixture_view.zig");
    const content = try fixture_view.Content.mount(cx, scope);
    const float_frame = try ui.box(cx, .{ .position = .absolute, .inset = .{ .left = .{ .px = 1100 }, .top = .{ .px = 100 } }, .width = .{ .px = 160 }, .height = .{ .px = 300 } }, .{});
    try float_frame.appendChild(a, content.root);
    try root.appendChild(a, float_frame);
    content.vm.edit("保留的文字");
    content.vm.select(7);
    cx.layout();
    // Window card (no tab), a card tab, then the standalone session tab.
    try std.testing.expectEqual(card_dock.Refusal.no_tab, workspace.dockRefusal(null).?);
    const owner = @backingInt(tab.tab_id);
    try std.testing.expect(workspace.dockRefusal(owner) == null);
    const Port = struct {
        floated: usize = 0,
        closed: usize = 0,
        fn back(raw: *anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.floated += 1;
        }
        fn close(raw: *anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.closed += 1;
        }
    };
    var port: Port = .{};
    const from = float_frame.globalRect();
    const focus_target = firstFocusableIn(cx, content.root).?;
    cx.setFocus(focus_target);
    const docked = try workspace.dockCard(.{
        .owner_tab = owner,
        .content = content.root,
        .title = "测试卡片",
        .icon = ui.icons.flask_conical,
        .ids = .{ .pane = "t.pane", .header = "t.header", .title = "t.title", .float = "t.float", .float_tooltip = "t.float.tooltip", .grip = "t.grip", .more = "t.more", .menu = "t.menu" },
        .port = .{ .ctx = &port, .float_back = Port.back, .closed = Port.close },
        .from = from,
        .flight = .{ .anchor = .none, .tokens = ui.fx.anchor_transition.default_tokens },
    });
    // The standalone tab became its group tab with the session and the card.
    const group = workspace.groupIdByTab(@fromBackingInt(docked.tab)).?;
    const view = workspace.groupView(group).?;
    try std.testing.expect(roster.findById(group).?.contains(tab.id));
    try std.testing.expectEqual(@as(usize, 1), view.cards.items.len);
    // Until the pane exists the content stays where it was.
    try std.testing.expect(content.root.parent == float_frame);
    try workspace.presentGroup(view);
    cx.layout();
    try std.testing.expectEqual(@as(usize, 2), view.tree.count());
    // Near the right edge → docked right; the same node now sits in the pane body.
    const split = view.tree.nodes.items[view.tree.root.?].split;
    try std.testing.expectEqual(group_view.Layout.side_by_side, split.axis);
    try std.testing.expectEqual(docked.leaf, view.tree.nodes.items[split.second].leaf);
    const pane = workspace.dockedCardPane(docked.leaf).?;
    try std.testing.expect(content.root.isDescendantOf(pane));
    try std.testing.expect(tab.root.globalRect().x < pane.globalRect().x);
    try std.testing.expectEqual(docked.tab, workspace.dockedCardTab(docked.leaf).?);
    // Keyboard focus inside the card went along: it was never taken away (LIFECYCLE.md §2).
    try std.testing.expect(cx.focus_manager.getFocused() == focus_target);
    // Re-presenting the split (status refresh) keeps the same content node and its state.
    try workspace.presentGroup(view);
    cx.layout();
    try std.testing.expect(content.root.isDescendantOf(workspace.dockedCardPane(docked.leaf).?));
    try std.testing.expect(cx.focus_manager.getFocused() == focus_target);
    try std.testing.expectEqualStrings("保留的文字", content.vm.text());
    try std.testing.expectEqual(@as(usize, 7), content.vm.selected.peek());
    // The pane header is the session pane header with the card's actions: grip, title, 浮动, 更多.
    const header = findTestIdIn(workspace.dockedCardPane(docked.leaf).?, "t.header").?;
    try std.testing.expect(findTestIdIn(header, "t.grip") != null and findTestIdIn(header, "t.float") != null and findTestIdIn(header, "t.more") != null);
    try std.testing.expect(findTestIdIn(header, "groups.pane.status_dot") == null);
    // Docking a second card into the existing split appends a pane; near the left edge → left.
    const second = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    float_frame.setStyleInline(a, .{ .inset = .{ .left = .{ .px = 10 }, .top = .{ .px = 200 } } });
    cx.layout();
    const again = try workspace.dockCard(.{ .owner_tab = docked.tab, .content = second, .title = "测试卡片 2", .icon = ui.icons.flask_conical, .ids = .{ .pane = "t2.pane", .header = "t2.header", .title = "t2.title", .float = "t2.float", .float_tooltip = "t2.float.tooltip" }, .port = .{ .ctx = &port, .float_back = Port.back, .closed = Port.close }, .from = float_frame.globalRect(), .flight = .{ .anchor = .none, .tokens = ui.fx.anchor_transition.default_tokens } });
    try std.testing.expectEqual(docked.tab, again.tab);
    try std.testing.expect(again.created_from == null);
    try workspace.presentGroup(view);
    cx.layout();
    const outer = view.tree.nodes.items[view.tree.root.?].split;
    try std.testing.expectEqual(again.leaf, view.tree.nodes.items[outer.first].leaf);
    try std.testing.expect(workspace.dockedCardPane(again.leaf).?.globalRect().x < tab.root.globalRect().x);
    // The pane header's 浮动 goes to the owner; undocking hands the node back with the pane rect.
    const pane_rect = workspace.dockedCardPane(docked.leaf).?.globalRect();
    var float_cell: Workspace.CardPaneCell = .{ .workspace = &workspace, .leaf = docked.leaf, .action = .float };
    Workspace.CardPaneCell.press(&float_cell);
    try std.testing.expectEqual(@as(usize, 1), port.floated);
    const back = workspace.undockCard(docked.leaf, .{ .parent = float_frame });
    try std.testing.expectApproxEqAbs(pane_rect.x, back.rect.?.x, 0.1);
    try std.testing.expectEqual(docked.tab, back.tab.?);
    try std.testing.expect(back.dissolved_from == null);
    // The content went straight into the frame the owner named; focus never left it.
    try std.testing.expect(content.root.parent == float_frame);
    try std.testing.expect(cx.focus_manager.getFocused() == focus_target);
    try workspace.presentGroup(view);
    cx.layout();
    try std.testing.expectEqual(@as(usize, 2), view.tree.count());
    try std.testing.expect(workspace.dockedCardTab(docked.leaf) == null);
    try std.testing.expectEqualStrings("保留的文字", content.vm.text());
    try std.testing.expectEqual(@as(usize, 7), content.vm.selected.peek());
    // The last card leaves: the split made for docking dissolves back into the single-card tab.
    // An owner that names no frame: the content leaves the window (kept, not destroyed).
    const last = workspace.undockCard(again.leaf, null);
    try std.testing.expect(second.parent == null);
    try std.testing.expectEqual(owner, last.tab.?);
    try std.testing.expectEqual(docked.tab, last.dissolved_from.?);
    try std.testing.expect(workspace.groupIdByTab(@fromBackingInt(docked.tab)) == null);
    try std.testing.expect(workspace.model.indexOf(@fromBackingInt(docked.tab)) == null);
    try std.testing.expect(workspace.model.tabs.items[workspace.model.indexOf(tab.tab_id).?].container == null);
    try std.testing.expect(!roster.findById(group).?.contains(tab.id));
    try std.testing.expect(tab.root.parent == area and workspace.active_group_view == null);
    cx.destroyDetached(second);
    try root.appendChild(a, content.root);
}

test "float-split: a tab that cannot split refuses with the reason" {
    const a = std.testing.allocator;
    const cx = try ui.Cx.init(a, std.testing.io);
    defer cx.deinit();
    cx.setViewport(1280, 720);
    const scope = try ui.Scope.init(a, null, cx.owner);
    defer scope.dispose();
    const root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    cx.root = root;
    const config: config_mod.Config = .{};
    var workspace: Workspace = .{ .allocator = a, .cx = cx, .scope = scope, .io = std.testing.io, .app_config = &config, .palette = Palette.fromTheme(), .registry = .{ .arena = std.heap.ArenaAllocator.init(a), .hosts = &.{} }, .hosts_path = "", .sidebar_list = root, .tab_bar = root, .terminal_area = root, .empty_state = root, .model = .{ .allocator = a, .window = @fromBackingInt(1), .workspace = @fromBackingInt(1) } };
    defer {
        workspace.tabs.deinit(a);
        workspace.model.deinit();
        workspace.registry.deinit();
    }
    var tab: SessionTab = .{ .id = 301, .tab_id = try tab_ids.allocate(), .content_owner = .{ .session = .{ .session_id = @fromBackingInt(301) } }, .host_id = 0, .host_index = 0, .host_snapshot = null, .root = root, .terminal = null, .content_ready = true };
    tab.setTitle("probe");
    try workspace.tabs.append(a, &tab);
    try workspace.installTabModel(&tab);
    // No roster (no group support in this window) → not splittable; a closing tab → busy.
    try std.testing.expectEqual(card_dock.Refusal.tab_not_splittable, workspace.dockRefusal(@backingInt(tab.tab_id)).?);
    var roster = group_model.Roster.init(a);
    defer roster.deinit();
    workspace.group_roster = &roster;
    tab.card_type = &card_placement.history_def;
    try std.testing.expectEqual(card_dock.Refusal.tab_not_splittable, workspace.dockRefusal(@backingInt(tab.tab_id)).?);
    tab.card_type = &card_placement.session_def;
    tab.closing = true;
    try std.testing.expectEqual(card_dock.Refusal.tab_busy, workspace.dockRefusal(@backingInt(tab.tab_id)).?);
    try std.testing.expectEqualStrings("所属标签页不能分屏", card_dock.Refusal.tab_not_splittable.text());
}

test "cards-float: a session card floats out of its tab and its split and comes back with the same content node; the tab stays" {
    const a = std.testing.allocator;
    const cx = try ui.Cx.init(a, std.testing.io);
    defer cx.deinit();
    cx.setViewport(1280, 720);
    const scope = try ui.Scope.init(a, null, cx.owner);
    const root = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .direction = .column }, .{});
    cx.root = root;
    const strip = try ui.box(cx, .{ .width = .fill(), .height = .{ .px = 32 }, .flex_shrink = 0 }, .{});
    const area = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .hit_behavior = .@"opaque" }, .{});
    const empty = try ui.box(cx, .{}, .{});
    try root.appendChild(a, strip);
    try root.appendChild(a, area);
    try area.appendChild(a, empty);
    const config: config_mod.Config = .{};
    var roster = group_model.Roster.init(a);
    defer roster.deinit();
    var workspace: Workspace = .{ .allocator = a, .cx = cx, .scope = scope, .io = std.testing.io, .app_config = &config, .palette = Palette.fromTheme(), .registry = .{ .arena = std.heap.ArenaAllocator.init(a), .hosts = &.{} }, .hosts_path = "", .sidebar_list = root, .tab_bar = strip, .terminal_area = area, .empty_state = empty, .model = .{ .allocator = a, .window = @fromBackingInt(1), .workspace = @fromBackingInt(1) }, .group_roster = &roster };
    defer {
        if (workspace.poll_hook) |hook| {
            cx.removeAfterLayoutHook(hook);
            a.destroy(hook);
            workspace.poll_hook = null;
        }
        scope.dispose();
        for (workspace.click_ctxs.items) |cell| a.destroy(cell);
        workspace.click_ctxs.deinit(a);
        workspace.tab_nodes.deinit(a);
        workspace.strip_advances.deinit(a);
        workspace.strip_widths.deinit(a);
        workspace.strip_grouped.deinit(a);
        workspace.tabs.deinit(a);
        workspace.model.deinit();
        workspace.registry.deinit();
        for (workspace.group_views.items) |view| {
            view.deinit(a);
            a.destroy(view);
        }
        workspace.group_views.deinit(a);
    }
    const Port = struct {
        floated: ?u64 = null,
        from: ?ui.ComputedRect = null,
        put_back: ?u64 = null,
        fn float(raw: *anyopaque, session: u64, from: ?ui.ComputedRect) void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.floated = session;
            self.from = from;
        }
        fn back(raw: *anyopaque, session: u64) void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.put_back = session;
        }
    };
    var port: Port = .{};
    // No floating host yet: the 浮动 button says why.
    var tabs: [2]SessionTab = undefined;
    for (&tabs, 0..) |*tab, i| {
        const session_root = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .hit_behavior = .@"opaque" }, .{});
        try area.appendChild(a, session_root);
        tab.* = .{ .id = 401 + i, .tab_id = try tab_ids.allocate(), .content_owner = .{ .session = .{ .session_id = @fromBackingInt(401 + i) } }, .host_id = 0, .host_index = 0, .host_snapshot = null, .root = session_root, .terminal = null, .plugin_protocol_id = "future-renderer", .content_ready = true, .card_type = &card_placement.terminal_def };
        tab.setTitle(if (i == 0) "alpha" else "beta");
        try workspace.tabs.append(a, tab);
        try workspace.installTabModel(tab);
    }
    try std.testing.expectEqualStrings("这个窗口不能浮动卡片", workspace.floatRefusal(401).?);
    workspace.session_float = .{ .ctx = &port, .float = Port.float, .put_back = Port.back };
    workspace.selectTab(0);
    cx.layout();
    try std.testing.expect(workspace.floatRefusal(401) == null);

    // 1. A single-card tab: its card floats, the tab stays on the strip with "卡片已浮动".
    workspace.requestFloatSession(401);
    try std.testing.expectEqual(@as(u64, 401), port.floated.?);
    try std.testing.expect(port.from.?.w > 0);
    const content = tabs[0].root;
    const frame = try ui.box(cx, .{ .position = .absolute, .inset = .{ .left = .{ .px = 600 }, .top = .{ .px = 120 } }, .width = .{ .px = 480 }, .height = .{ .px = 300 } }, .{});
    try root.appendChild(a, frame);
    const take = try workspace.takeFloatSession(401, .{ .parent = frame });
    try std.testing.expect(take.content == content and take.owner_tab == @backingInt(tabs[0].tab_id));
    try std.testing.expect(tabs[0].floating and content.parent == frame);
    try std.testing.expectEqualStrings("已在浮动", workspace.floatRefusal(401).?);
    workspace.syncFloatedPlaceholder();
    cx.layout();
    const placeholder = workspace.floated_placeholder.?;
    try std.testing.expect(placeholder.root.style.display != .none and placeholder.root.parent == area);
    try std.testing.expect(std.mem.indexOf(u8, placeholder.vm.detail.peek(), "alpha") != null);
    try std.testing.expect(workspace.model.indexOf(tabs[0].tab_id) != null);
    // Tab switches and split refreshes never take the floating content back.
    workspace.selectTab(1);
    workspace.restoreGroupRoots();
    workspace.selectTab(0);
    try std.testing.expect(content.parent == frame and content.style.display != .none);
    // 放回标签页 asks the floating host; the host puts it back into the tab body.
    Workspace.putBackFloated(&workspace);
    try std.testing.expectEqual(@as(u64, 401), port.put_back.?);
    try workspace.returnFloatSession(401, .split, frame.globalRect(), null);
    workspace.syncFloatedPlaceholder();
    cx.layout();
    try std.testing.expect(!tabs[0].floating and content.parent == area and content.style.display != .none);
    try std.testing.expect(placeholder.root.style.display == .none);

    // 2. A split member: it leaves the presented split (the group stays), then comes back on the side
    //    nearest to where it floated, as the same node.
    const group = (try roster.join("G", 401, 0xff818cf8)).id;
    _ = try roster.join("G", 402, 0xff818cf8);
    try workspace.openGroup(&roster, group);
    const view = workspace.groupView(group).?;
    try workspace.presentGroup(view);
    cx.layout();
    try std.testing.expectEqual(@as(usize, 2), view.panes.items.len);
    try std.testing.expectEqual(@as(?u64, @backingInt(workspace.groupTabId(group).?)), workspace.floatOwnerTab(402));
    _ = try workspace.takeFloatSession(402, .{ .parent = frame });
    try workspace.presentGroup(view);
    cx.layout();
    try std.testing.expectEqual(@as(usize, 1), view.panes.items.len);
    try std.testing.expectEqual(@as(usize, 1), view.tree.count());
    try std.testing.expect(tabs[1].root.parent == frame);
    try std.testing.expect(roster.findById(group).?.contains(402));
    try std.testing.expect(workspace.floatDockRefusal(402) == null and workspace.floatTabRefusal(402) == null);
    // Floating near the left edge of the tab body → back on the left.
    const body = area.globalRect();
    try workspace.returnFloatSession(402, .split, .{ .x = body.x + 4, .y = body.y + 40, .w = 200, .h = 200 }, null);
    try workspace.presentGroup(view);
    cx.layout();
    try std.testing.expectEqual(@as(usize, 2), view.panes.items.len);
    const split = view.tree.nodes.items[view.tree.root.?].split;
    try std.testing.expectEqual(@as(u64, 402), view.tree.nodes.items[split.first].leaf);
    try std.testing.expect(tabs[1].root.parent.?.parent != null and tabs[1].root.globalRect().x < tabs[0].root.globalRect().x);
    // 作为标签页打开 from a split: the member leaves the group and keeps its session.
    _ = try workspace.takeFloatSession(402, .{ .parent = frame });
    try workspace.returnFloatSession(402, .own_tab, null, null);
    try std.testing.expect(!roster.findById(group).?.contains(402));
    try std.testing.expect(!tabs[1].floating and tabs[1].root.parent == area);
    root.removeChild(frame);
    cx.destroyDetached(frame);
}

test "split: 向右分屏 puts the source session into the group tab; the strip no longer shows it on its own" {
    const a = std.testing.allocator;
    const cx = try ui.Cx.init(a, std.testing.io);
    defer cx.deinit();
    cx.setViewport(1280, 720);
    const scope = try ui.Scope.init(a, null, cx.owner);
    const root = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .direction = .column }, .{});
    cx.root = root;
    const strip = try ui.box(cx, .{ .width = .fill(), .height = .{ .px = 32 }, .flex_shrink = 0 }, .{});
    const area = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    const empty = try ui.box(cx, .{}, .{});
    try root.appendChild(a, strip);
    try root.appendChild(a, area);
    try area.appendChild(a, empty);
    const config: config_mod.Config = .{};
    var roster = group_model.Roster.init(a);
    defer roster.deinit();
    var workspace: Workspace = .{ .allocator = a, .cx = cx, .scope = scope, .io = std.testing.io, .app_config = &config, .palette = Palette.fromTheme(), .registry = .{ .arena = std.heap.ArenaAllocator.init(a), .hosts = &.{} }, .hosts_path = "", .sidebar_list = root, .tab_bar = strip, .terminal_area = area, .empty_state = empty, .model = .{ .allocator = a, .window = @fromBackingInt(1), .workspace = @fromBackingInt(1) }, .group_roster = &roster };
    defer {
        if (workspace.poll_hook) |hook| {
            cx.removeAfterLayoutHook(hook);
            a.destroy(hook);
            workspace.poll_hook = null;
        }
        scope.dispose();
        for (workspace.click_ctxs.items) |cell| a.destroy(cell);
        workspace.click_ctxs.deinit(a);
        workspace.tab_nodes.deinit(a);
        workspace.strip_advances.deinit(a);
        workspace.strip_widths.deinit(a);
        workspace.strip_grouped.deinit(a);
        workspace.tabs.deinit(a);
        workspace.model.deinit();
        workspace.registry.deinit();
        for (workspace.group_views.items) |view| {
            view.deinit(a);
            a.destroy(view);
        }
        workspace.group_views.deinit(a);
    }
    // The session host's "new session like this one": a second Local session tab.
    const Host = struct {
        workspace: *Workspace,
        tab: SessionTab = undefined,
        fn recreate(raw: ?*anyopaque, _: SessionId) anyerror!void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            const node = try ui.box(self.workspace.cx, .{ .width = .fill(), .height = .fill() }, .{});
            try self.workspace.terminal_area.appendChild(self.workspace.allocator, node);
            self.tab = .{ .id = 502, .tab_id = try tab_ids.allocate(), .content_owner = .{ .session = .{ .session_id = @fromBackingInt(502) } }, .host_id = 0, .host_index = 0, .host_snapshot = null, .root = node, .local = true };
            self.tab.setTitle("本地终端 · 2");
            try self.workspace.tabs.append(self.workspace.allocator, &self.tab);
            try self.workspace.installTabModel(&self.tab);
        }
    };
    var host: Host = .{ .workspace = &workspace };
    workspace.session_bridge = .{ .context = &host, .recreate = Host.recreate };
    const source_root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    try area.appendChild(a, source_root);
    var source: SessionTab = .{ .id = 501, .tab_id = try tab_ids.allocate(), .content_owner = .{ .session = .{ .session_id = @fromBackingInt(501) } }, .host_id = 0, .host_index = 0, .host_snapshot = null, .root = source_root, .local = true };
    source.setTitle("本地终端");
    try workspace.tabs.append(a, &source);
    try workspace.installTabModel(&source);
    workspace.selectTab(0);
    try std.testing.expectEqual(@as(usize, 1), workspace.model.visibleCount());

    try workspace.splitGroup(&roster, false);
    const group = workspace.active_group_view.?;
    const group_tab = workspace.groupTabId(group).?;
    try std.testing.expect(roster.findById(group).?.contains(501) and roster.findById(group).?.contains(502));
    // Both sessions live in the group tab; the strip shows the group only.
    try std.testing.expectEqual(group_tab, workspace.model.tabs.items[workspace.model.indexOf(source.tab_id).?].container.?);
    try std.testing.expectEqual(group_tab, workspace.model.tabs.items[workspace.model.indexOf(host.tab.tab_id).?].container.?);
    try std.testing.expectEqual(@as(usize, 1), workspace.model.visibleCount());
    // The membership check that runs every frame keeps it there.
    for (workspace.model.tabs.items) |tab| workspace.restoreStandaloneIfUngrouped(tab.id);
    try std.testing.expectEqual(@as(usize, 1), workspace.model.visibleCount());
}
