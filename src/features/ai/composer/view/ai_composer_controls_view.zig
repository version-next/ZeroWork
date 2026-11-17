//! Read-only projections of configured AI capabilities. Selection only emits
//! a typed, captured action; the host confirms it with update().
const std = @import("std");
const ui = @import("ui");
const config = @import("../../../../config/config.zig");
const provider = @import("../../../../ai/provider.zig");
const identity = @import("../../../../host/identity.zig");
pub const Owner = @import("../../../../ai/tool_scope.zig").Owner;
const S = @import("ai_composer_controls_styles.zig");
const template = @import("_ai_composer_controls.yix.zig");
const IdSpace = @import("../../shared/view/ai_id_space.zig").IdSpace;
const W = ui.widgets;
pub const Kind = S.Kind;
pub const ring_size = S.ring_size;
pub const width = S.width;
pub const height = S.height;
/// Template form of the menus package's right-click style menu (`AppMenu.initContext`).
pub const ContextMenu = app_menu.ContextMenu;
const shell = @import("../../../shell/mod.zig");
const app_menu = shell.app_menu;
pub const Effort = provider.Effort;
pub const PermissionMode = config.PermissionMode;
pub const ExecutionMode = config.ExecutionMode;
pub const SessionRetention = config.SessionRetention;
pub const Attachment = enum { image, local_text, remote_file, paste_image };
pub const AttachmentState = struct { image: bool = false, local_text: bool = false, remote_file: bool = false, paste_image: bool = false, count: usize = 0 };
pub const ModelKey = struct {
    provider_id: []const u8,
    model_id: []const u8,
    pub fn eql(self: ModelKey, other: ModelKey) bool {
        return std.mem.eql(u8, self.provider_id, other.provider_id) and std.mem.eql(u8, self.model_id, other.model_id);
    }
};
pub const UsagePart = struct { name: []const u8, tokens: u64, estimated: ?bool = null };
pub const Usage = struct {
    used_tokens: u64,
    limit_tokens: u64,
    estimated: bool = false,
    parts: []const UsagePart = &.{},
    request_tokens: ?u64 = null,
    redacted: ?bool = null,
    compaction: @import("../../../../ai/context_compaction.zig").Status = .idle,
    can_compact: bool = false,
    compaction_before: u64 = 0,
    compaction_after: u64 = 0,
};
pub const Snapshot = struct {
    owner: Owner,
    /// Configuration epoch. Current selection/usage may update within it;
    /// replacing provider identities/capabilities requires a newer epoch.
    revision: u64,
    providers: []const config.AiProvider = &.{},
    current: ?ModelKey = null,
    permission: PermissionMode = .confirm,
    allow_auto_permission: bool = true,
    global_execution_mode: ExecutionMode = .auto,
    global_session_retention: SessionRetention = .auto_idle,
    execution_mode_override: ?ExecutionMode = null,
    session_retention_override: ?SessionRetention = null,
    effort: ?Effort = null,
    thinking: ?bool = null,
    attachments: AttachmentState = .{},
    usage: ?Usage = null,
    editable: bool = true,
    inventory_authorized: bool = false,
    inventory_conversation_id: ?identity.ConversationId = null,
};
pub const Action = union(enum) {
    revoke_inventory: identity.ConversationId,
    compact_context,
    cancel_compaction,
    model: ModelKey,
    permission: PermissionMode,
    execution_mode: ?ExecutionMode,
    session_retention: ?SessionRetention,
    effort: struct { model: ModelKey, value: Effort },
    thinking: struct { model: ModelKey, enabled: bool },
    attachment: Attachment,
};
pub const Envelope = struct { owner: Owner, revision: u64, action: Action };
/// The composer controls a popover names for focus (`focusName`).
pub const FocusName = enum { model_anchor, usage_anchor, usage_action, slider };
/// Per-process counter for composer focus namespaces.
var next_focus_namespace: u32 = 0;

pub const ActionCallbacks = struct { context: *anyopaque, send: *const fn (*anyopaque) void, stop: *const fn (*anyopaque) void };
pub const Callbacks = struct { context: *anyopaque, action: *const fn (*anyopaque, Envelope) anyerror!void, open_settings: ?*const fn (*anyopaque) void = null, models_opened: ?*const fn (*anyopaque) void = null };
pub fn providerId(value: config.AiProvider) []const u8 {
    return if (value.name.len != 0) value.name else @tagName(value.kind);
}
pub fn permissionLabel(value: PermissionMode) []const u8 {
    return if (value == .confirm) "确认后执行" else "自动执行";
}
pub fn effortLabel(value: Effort) []const u8 {
    return switch (value) {
        .low => "低",
        .medium => "中",
        .high => "高",
        .xhigh => "较高",
        .max => "最高",
        .none => "关闭",
        .ultra => "超高",
    };
}
const Model = struct {
    key: ModelKey,
    enabled: bool,
    context_window: u32,
    context_discovered: bool,
    reasoning: bool,
    toggle: bool,
    thinking_default: ?bool,
    vision: bool,
    efforts: [7]bool,
    /// Display text of the model's row (owned by the projection): the details tooltip and the
    /// context window column.
    description: []const u8 = "",
    context_text: []const u8 = "",
};
const Projection = struct { owner: Owner, revision: u64, models: []const Model, current: ?ModelKey, permission: PermissionMode, allow_auto_permission: bool, global_execution_mode: ExecutionMode, global_session_retention: SessionRetention, execution_mode_override: ?ExecutionMode, session_retention_override: ?SessionRetention, effort: ?Effort, thinking: ?bool, attachments: AttachmentState, usage: ?Usage, editable: bool, inventory_authorized: bool, inventory_conversation_id: ?identity.ConversationId, config_hash: u64 };
// Discovery provenance changes authority/configuration, but does not change a
// model row when all resolved capabilities and displayed values are identical.
fn modelRowsEql(a: Projection, b: Projection) bool {
    if (!a.owner.eql(b.owner) or !optionalKeyEql(a.current, b.current) or a.editable != b.editable or a.models.len != b.models.len) return false;
    for (a.models, b.models) |left, right| {
        if (!left.key.eql(right.key) or left.enabled != right.enabled or left.context_window != right.context_window or
            left.reasoning != right.reasoning or left.vision != right.vision or left.toggle != right.toggle or
            left.thinking_default != right.thinking_default or !std.meta.eql(left.efforts, right.efforts)) return false;
    }
    return true;
}
const Owned = struct {
    arena: std.heap.ArenaAllocator,
    value: Projection,
    fn init(allocator: std.mem.Allocator, snapshot: Snapshot) !Owned {
        if (snapshot.revision == 0 or snapshot.owner.raw() == 0) return error.InvalidOwner;
        if (snapshot.usage) |usage| if (usage.limit_tokens == 0) return error.InvalidUsage;
        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();
        const a = arena.allocator();
        var models: std.ArrayList(Model) = .empty;
        var hash = std.hash.Wyhash.init(0);
        for (snapshot.providers) |item| {
            const id = providerId(item);
            for (item.models) |model| {
                if (model.id.len == 0) continue;
                try appendModel(a, &models, &hash, id, item.kind, item.endpoint, item.enabled and @import("../../../settings/model/settings_ai_draft.zig").endpointValid(item.endpoint) and (item.api_key.len != 0 or @import("../../../../ai/provider_config.zig").allowsNoAuth(item.kind, item.endpoint)), model);
            }
            if (item.models.len == 0 and item.model.len != 0) try appendModel(a, &models, &hash, id, item.kind, item.endpoint, item.enabled and @import("../../../settings/model/settings_ai_draft.zig").endpointValid(item.endpoint) and (item.api_key.len != 0 or @import("../../../../ai/provider_config.zig").allowsNoAuth(item.kind, item.endpoint)), .{ .id = item.model, .context_window = item.context_window, .efforts = @splat(false) });
        }
        var usage = snapshot.usage;
        if (usage) |*value| {
            const parts = try a.dupe(UsagePart, value.parts);
            for (parts) |*part| part.name = try a.dupe(u8, part.name);
            value.parts = parts;
        }
        for (models.items) |*model| try describe(a, model);
        const current = if (snapshot.current) |key| try cloneKey(a, key) else null;
        return .{ .arena = arena, .value = .{ .owner = snapshot.owner, .revision = snapshot.revision, .models = try models.toOwnedSlice(a), .current = current, .permission = snapshot.permission, .allow_auto_permission = snapshot.allow_auto_permission, .global_execution_mode = snapshot.global_execution_mode, .global_session_retention = snapshot.global_session_retention, .execution_mode_override = snapshot.execution_mode_override, .session_retention_override = snapshot.session_retention_override, .effort = snapshot.effort, .thinking = snapshot.thinking, .attachments = snapshot.attachments, .usage = usage, .editable = snapshot.editable, .inventory_authorized = snapshot.inventory_authorized, .inventory_conversation_id = snapshot.inventory_conversation_id, .config_hash = hash.final() } };
    }
    fn appendModel(a: std.mem.Allocator, models: *std.ArrayList(Model), hash: *std.hash.Wyhash, id: []const u8, kind: config.ProviderKind, endpoint: []const u8, enabled: bool, value: config.AiModel) !void {
        const key: ModelKey = .{ .provider_id = id, .model_id = value.id };
        for (models.items) |previous| if (previous.key.eql(key)) return error.DuplicateModel;
        const efforts = if (kind == .openai_compat or value.reasoning_discovered) value.efforts else @as([7]bool, @splat(false));
        try models.append(a, .{ .key = try cloneKey(a, key), .enabled = enabled and std.mem.trim(u8, value.id, " \t\r\n").len != 0 and value.context_window != 0, .context_window = value.context_window, .context_discovered = value.context_discovered, .reasoning = value.reasoning, .thinking_default = value.thinking_default, .toggle = value.reasoning_toggle and (value.reasoning_adaptive or @import("../../../../ai/provider_config.zig").toggleProtocol(kind, endpoint, value.id) != .none), .vision = value.vision, .efforts = efforts });
        hash.update(id);
        hash.update(&.{0});
        hash.update(value.id);
        hash.update(&.{ 0, @intFromBool(enabled), @intFromBool(value.reasoning), @intFromBool(value.vision), @intFromBool(value.reasoning_toggle), @intFromBool(value.reasoning_discovered), @intFromBool(value.reasoning_adaptive) });
        hash.update(&.{if (value.thinking_default) |v| (if (v) @as(u8, 1) else 2) else 0});
        hash.update(std.mem.asBytes(&value.context_window));
        hash.update(std.mem.asBytes(&value.context_discovered));
        for (efforts) |supported| hash.update(&.{@intFromBool(supported)});
    }
    fn deinit(self: *Owned) void {
        self.arena.deinit();
    }
    /// The row's details (name, provider, context, availability, input, reasoning levels) and
    /// its context window text.
    fn describe(a: std.mem.Allocator, model: *Model) !void {
        var levels: std.Io.Writer.Allocating = .init(a);
        for (model.efforts, 0..) |supported, effort_index| if (supported and model.reasoning) {
            if (levels.written().len != 0) try levels.writer.writeAll(" / ");
            try levels.writer.writeAll(effortLabel(@fromBackingInt(@intCast(effort_index))));
        };
        var token_buffer: [32]u8 = undefined;
        model.context_text = try a.dupe(u8, try tokenText(&token_buffer, model.context_window));
        model.description = try std.fmt.allocPrint(a, "{s}\n{s} · {s}\n上下文 {s} tokens · {s}\n{s} · 工具能力未声明\n{s}{s}", .{ model.key.model_id, model.key.provider_id, model.key.model_id, model.context_text, if (model.enabled) "可用" else "Provider 未配置或已禁用", if (model.vision) "支持图片输入" else "仅文本输入", if (model.reasoning) "推理档位：" else "无推理档位", levels.written() });
    }
};
fn cloneKey(a: std.mem.Allocator, key: ModelKey) !ModelKey {
    return .{ .provider_id = try a.dupe(u8, key.provider_id), .model_id = try a.dupe(u8, key.model_id) };
}
const ReasoningChoice = union(enum) { off, on, effort: Effort };
const Capture = struct { owner: Owner, revision: u64, inventory_conversation_id: ?identity.ConversationId };
/// Popover index of a kind (model and effort share the model popover).
fn popupIndex(kind: Kind) ?usize {
    return switch (kind) {
        .model, .effort => 0,
        .usage => 1,
        else => null,
    };
}
/// Native Menu index of a kind (selection-only choices: Pencil Kaf7E O1 / O2 / O3).
fn menuIndex(kind: Kind) ?usize {
    return switch (kind) {
        .attachment => 0,
        .permission => 1,
        .execution => 2,
        else => null,
    };
}
const menu_kinds = [3]Kind{ .attachment, .permission, .execution };
const Anchor = struct {
    view: *View,
    kind: Kind,
    fn get(raw: *anyopaque) W.popover.AnchorRect {
        const self: *Anchor = @ptrCast(@alignCast(raw));
        const rect = self.view.anchorButton(self.kind).globalRect();
        // Keep the place it opened at, relative to the tool row (the chip's own width follows
        // its text while the effort changes); a moved composer still carries it.
        if (popupIndex(self.kind) == 0) if (self.view.model_anchor) |pinned| {
            const row = self.view.root.globalRect();
            return .{ .x = row.x + pinned.x, .y = row.y + pinned.y, .w = pinned.w, .h = pinned.h };
        };
        return .{ .x = rect.x, .y = rect.y, .w = rect.w, .h = rect.h };
    }
};
/// Hooks of one menus-package menu (app_menu): the chosen row id goes back to the view, which
/// validates it against the capture taken when the menu opened.
const MenuHook = struct {
    view: *View,
    kind: Kind,
    fn select(raw: *anyopaque, id: []const u8) void {
        const self: *MenuHook = @ptrCast(@alignCast(raw));
        self.view.menuSelected(self.kind, id);
    }
    fn closed(raw: *anyopaque) void {
        const self: *MenuHook = @ptrCast(@alignCast(raw));
        // Escape / outside click: focus comes back to the control that opened the menu.
        if (self.view.cx.focus_manager.current_focus == null) self.view.cx.setFocus(self.view.anchorButton(self.kind));
    }
};
const no_keys = struct {
    const map: shell.shortcut_router.Map = .{};
};
const max_menu_rows = 16;
/// The composer controls' test ids; a child dialog's composer uses `ai.child.*` (child_dialog.prefix).
/// One row of the usage legend (O6), formatted for the view.
pub const UsageRow = struct {
    index: usize,
    tone: ui.widgets.ProgressTone,
    name: *ui.Signal([]const u8),
    value: *ui.Signal([]const u8),
};
/// One row of the model list (O4), projected for the view (`ModelRow`).
pub const Row = struct {
    id: []const u8 = "",
    basename: []const u8 = "",
    brand: ?ui.SvgAsset = null,
    description: []const u8 = "",
    context: []const u8 = "",
    selected: bool = false,
    enabled: bool = false,
    choosable: bool = false,
    reasoning: bool = false,
    vision: bool = false,
};
const max_usage_rows = 32;

/// View-model of the composer tool row (view: `ai_composer_controls.yix`, Pencil Kaf7E A3 / ⑤ /
/// O1–O4 / O6). Holds the owned projection, the captures, every value the view shows (signals),
/// the shrink rule (decided each frame from the measured row) and the actions sent to the host.
pub const View = struct {
    cx: *ui.Cx,
    scope: *ui.Scope,
    callbacks: Callbacks,
    /// Nodes of the mounted view (kept at mount, for the shrink rule's measurements, anchors and
    /// focus). `trailing` takes the host's send / stop controls.
    root: *ui.Node = undefined,
    trailing: *ui.Node = undefined,
    ordinary_spacer: *ui.Node = undefined,
    buttons: [6]*ui.Node = undefined,
    compact_wrappers: [2]*ui.Node = undefined,
    compact_buttons: [2]*ui.Node = undefined,
    /// The model (0) and usage (1) native Popovers.
    popups: [2]W.popover.PopoverResult = undefined,
    /// Send / Stop at the end of the row (the composer's, Pencil Kaf7E A8): shown once a composer
    /// enables them (`useActions`); the composer decides their state.
    actions: ?ActionCallbacks = null,
    stop_shown: *ui.Signal(bool) = undefined,
    send_shown: *ui.Signal(bool) = undefined,
    send_disabled: *ui.Signal(bool) = undefined,
    send_hint: *ui.Signal([]const u8) = undefined,
    send_label: *ui.Signal([]const u8) = undefined,
    interaction_active: bool = false,
    /// A child dialog's composer: menu rows carry `ai.child.*` test ids.
    /// Test-id namespace of the surface this row is mounted in (main assistant / child dialog).
    space: IdSpace,
    disabled: [6]*ui.Signal(bool) = undefined,
    /// Button labels / glyphs (native Button signals).
    texts: [6]*ui.Signal([]const u8) = undefined,
    glyphs: [6]*ui.Signal(?ui.SvgAsset) = undefined,
    /// The usage Button's native W.ProgressRing (12): the context share used.
    ring_value: *ui.Signal(f32) = undefined,
    /// The model control's full text ("model · effort"); afterLayout ellipsizes it to the room left.
    model_full: [320]u8 = undefined,
    model_full_len: usize = 0,
    /// Length of the model name inside `model_full` (the rest is " · effort").
    model_name_len: usize = 0,
    model_shown_name: [328]u8 = undefined,
    model_shown: [328]u8 = undefined,
    /// The model control's native Tooltip: the full model name.
    model_hint: *ui.Signal([]const u8) = undefined,
    popup_open: [2]*ui.Signal(bool) = undefined,
    anchors: [2]Anchor = undefined,
    menus: [3]*app_menu.AppMenu = undefined,
    menu_entries: [3][max_menu_rows]app_menu.Entry = undefined,
    retention_entries: [4]app_menu.Entry = undefined,
    retention_text: [2][320]u8 = undefined,
    retention_slot: u1 = 0,
    captures: [6]?Capture = @splat(null),
    source: ?Owned = null,
    pending: ?Owned = null,
    /// The projection replaced at the last flush: model rows built from it stay valid until the
    /// list rebuilds them (the same frame).
    retired: ?Owned = null,
    clear_pending: bool = false,
    usage_dirty: bool = true,
    filtered: std.ArrayList(usize) = .empty,
    model_rows: std.ArrayList(struct { index: usize, header: bool }) = .empty,
    collapsed_providers: std.ArrayList([]u8) = .empty,
    pending_provider: ?usize = null,
    model_count: *ui.Signal(usize),
    model_version: *ui.Signal(u64),
    /// Model card state: no model configured / the settings link / a failed update.
    models_empty: *ui.Signal(bool) = undefined,
    settings_shown: *ui.Signal(bool) = undefined,
    model_error: *ui.Signal(bool) = undefined,
    /// Reasoning control: shown, its value text, the slider marks and whether a step is chosen.
    effort_shown: *ui.Signal(bool) = undefined,
    effort_name: *ui.Signal([]const u8) = undefined,
    slider_value: *ui.Signal(f32),
    marks: *ui.Signal([]const W.SliderMark) = undefined,
    mark_rows: [2][8]W.SliderMark = undefined,
    mark_slot: u1 = 0,
    thumb_shown: *ui.Signal(bool) = undefined,
    reasoning_choices: [8]ReasoningChoice = undefined,
    reasoning_count: usize = 0,
    proposed_reasoning: ?ReasoningChoice = null,
    /// “粘贴图片”行右侧的快捷键文字（宿主从快捷键路由同步，`syncPasteShortcut`）。
    paste_hint_text: []const u8 = "",
    /// Usage popover (O6) content.
    usage_shown: *ui.Signal(bool) = undefined,
    usage_caption: *ui.Signal([]const u8) = undefined,
    usage_total: *ui.Signal([]const u8) = undefined,
    usage_segments: *ui.Signal([]const W.ProgressSegment) = undefined,
    usage_rows: *ui.Signal([]const UsageRow) = undefined,
    usage_cells: [max_usage_rows]?UsageRow = @splat(null),
    compaction_running: *ui.Signal(bool) = undefined,
    compaction_reason: *ui.Signal([]const u8) = undefined,
    can_compact: *ui.Signal(bool) = undefined,
    /// The popovers' focus is the native Popover's (`trapFocus`, FocusManager scope entry). The
    /// view-model only names controls (`focusId`, unique to this composer: two composers can share
    /// a window) and says which name a popover opens on (`initialFocus`) and returns to
    /// (`returnFocus`). `focus_prefix` is this composer's namespace; the buffers hold names a
    /// template reads (copied by zenit when read).
    focus_prefix_buf: [24]u8 = undefined,
    focus_prefix: []const u8 = "",
    focus_name_bufs: [std.enums.values(FocusName).len][64]u8 = undefined,
    initial_focus_bufs: [2][64]u8 = undefined,
    row_focus_buf: [64]u8 = undefined,
    last_error: ?anyerror = null,
    viewport: ui.Size = .ZERO,
    execution_compact: bool = false,
    /// Narrow rows: permission (0) and execution (1) collapse into native icon-only
    /// ghost Buttons wrapped in native Tooltips ("名称 · 当前值").
    permission_compact: bool = false,
    compact_shown: [2]*ui.Signal(bool) = undefined,
    compact_icons: [2]*ui.Signal(?ui.SvgAsset) = undefined,
    compact_texts: [2]*ui.Signal([]const u8) = undefined,
    compact_text_buffers: [2][2][160]u8 = undefined,
    compact_text_slot: [2]u1 = .{ 0, 0 },
    compact_width: f32 = 24,
    /// Measured frame of the permission / execution chips around their label (padding, glyph,
    /// gaps, chevron): their full width is this plus the label's measured width.
    chip_chrome: [2]f32 = .{ 0, 0 },
    model_chrome: f32 = 0,
    keep_model_popup_on_update: bool = false,
    model_anchor: ?W.popover.AnchorRect = null,
    row_kept: bool = false,
    popups_kept: u2 = 0,

    /// State only (the composer template places `ToolRow`); `mount` also renders it.
    pub fn init(cx: *ui.Cx, scope: *ui.Scope, callbacks: Callbacks) !*View {
        const self = try scope.createState(View, .{ .cx = cx, .scope = scope, .callbacks = callbacks, .space = IdSpace.of(scope), .model_count = try scope.createSignal(usize, 0), .model_version = try scope.createSignal(u64, 0), .slider_value = try scope.createSignal(f32, 0) });
        try scope.onCleanup(View, self, release);
        self.focus_prefix = std.fmt.bufPrint(&self.focus_prefix_buf, "composer#{d}", .{next_focus_namespace}) catch unreachable;
        next_focus_namespace +%= 1;
        for (0..6) |index| {
            const kind: Kind = @fromBackingInt(@intCast(index));
            self.disabled[index] = try scope.createSignal(bool, true);
            self.texts[index] = try scope.createText(switch (kind) {
                .attachment => "",
                .permission => "执行权限",
                .model => "未配置模型",
                .effort => "推理设置",
                .usage => "—",
                .execution => "自行判断",
            }, .{ .capacity = 330 });
            self.glyphs[index] = try scope.createSignal(?ui.SvgAsset, switch (kind) {
                .attachment => ui.icons.get("paperclip").?,
                .permission => ui.icons.get("hand").?,
                .execution => executionIcon(.auto),
                else => null,
            });
        }
        self.ring_value = try scope.createSignal(f32, 0);
        self.model_hint = try scope.createText("未配置模型", .{ .capacity = 330 });
        for (0..2) |slot| {
            self.popup_open[slot] = try scope.createSignal(bool, false);
            self.anchors[slot] = .{ .view = self, .kind = if (slot == 0) .model else .usage };
            self.compact_shown[slot] = try scope.createSignal(bool, false);
            self.compact_icons[slot] = try scope.createSignal(?ui.SvgAsset, if (slot == 0) ui.icons.get("hand").? else executionIcon(.auto));
            self.compact_texts[slot] = try scope.createSignal([]const u8, if (slot == 0) "执行权限" else "当前对话运行方式");
        }
        for (menu_kinds, 0..) |kind, index| {
            const hook = try scope.createState(MenuHook, .{ .view = self, .kind = kind });
            self.menus[index] = try app_menu.AppMenu.initContext(cx, scope, switch (kind) {
                .attachment => self.space.id("ai.attachment.menu"),
                .permission => self.space.id("ai.permission.menu"),
                else => self.space.id("ai.execution.menu"),
            }, .{ .context = hook, .select = MenuHook.select, .closed = MenuHook.closed });
        }
        self.models_empty = try scope.createSignal(bool, true);
        self.settings_shown = try scope.createSignal(bool, false);
        self.model_error = try scope.createSignal(bool, false);
        self.effort_shown = try scope.createSignal(bool, false);
        self.effort_name = try scope.createText("不支持推理设置", .{ .capacity = 64 });
        self.marks = try scope.createSignal([]const W.SliderMark, &.{});
        self.thumb_shown = try scope.createSignal(bool, true);
        self.usage_shown = try scope.createSignal(bool, false);
        self.usage_caption = try scope.createText("", .{ .capacity = 64 });
        self.usage_total = try scope.createText("", .{ .capacity = 64 });
        self.usage_segments = try scope.createList(W.ProgressSegment, &.{});
        self.usage_rows = try scope.createList(UsageRow, &.{});
        self.compaction_running = try scope.createSignal(bool, false);
        self.compaction_reason = try scope.createText("", .{ .capacity = 64 });
        self.can_compact = try scope.createSignal(bool, false);
        self.stop_shown = try scope.createSignal(bool, false);
        self.send_shown = try scope.createSignal(bool, true);
        self.send_disabled = try scope.createSignal(bool, true);
        self.send_hint = try scope.createText("发送问题", .{ .capacity = 96 });
        self.send_label = try scope.createText("发送问题", .{ .capacity = 32 });
        // Clear our focus before native Button/Popover child scopes dispose.
        const focus_guard = try scope.childScope();
        try focus_guard.onCleanup(View, self, releaseFocus);
        try cx.addAfterLayoutHook(self, afterLayout);
        return self;
    }
    /// Send / Stop belong to this row (before it is placed).
    pub fn useActions(self: *View, callbacks: ActionCallbacks) void {
        self.actions = callbacks;
    }
    pub fn mount(cx: *ui.Cx, scope: *ui.Scope, callbacks: Callbacks) !*View {
        const self = try init(cx, scope, callbacks);
        _ = try ui.view.render(scope, cx, template.ToolRow(.{ .m = self }));
        return self;
    }
    // ── Nodes kept at mount (template onMount) ──────────────────────────────────────────────
    pub fn keepRow(self: *View, root: ?*ui.Node, trailing: ?*ui.Node, spacer: ?*ui.Node) void {
        self.root = root.?;
        self.trailing = trailing.?;
        self.ordinary_spacer = spacer.?;
        self.row_kept = true;
    }
    pub fn keepButtons(self: *View, nodes: [6]?*ui.Node) void {
        for (nodes, 0..) |node, index| self.buttons[index] = node.?;
    }
    pub fn keepCompact(self: *View, slot: usize, wrap: ?*ui.Node, button: ?*ui.Node) void {
        self.compact_wrappers[slot] = wrap.?;
        self.compact_buttons[slot] = button.?;
    }
    pub fn keepPopup(self: *View, index: usize, popup: ?W.popover.PopoverResult) void {
        self.popups[index] = popup.?;
        self.popups_kept +|= 1;
    }
    fn compactActive(self: *const View, kind: Kind) bool {
        return switch (kind) {
            .permission => self.permission_compact,
            .execution => self.execution_compact,
            else => false,
        };
    }
    /// The visible control a popup or menu anchors to and returns focus to.
    fn anchorButton(self: *const View, kind: Kind) *ui.Node {
        if (self.compactActive(kind)) return self.compact_buttons[if (kind == .permission) 0 else 1];
        return self.buttons[@backingInt(if (kind == .effort) Kind.model else kind)];
    }
    fn setCompactText(self: *View, slot: usize, name: []const u8, value: []const u8) void {
        const next = self.compact_text_slot[slot] +% 1;
        const text_value = std.fmt.bufPrint(&self.compact_text_buffers[slot][next], "{s} · {s}", .{ name, value }) catch name;
        if (std.mem.eql(u8, text_value, self.compact_texts[slot].peek())) return;
        self.compact_text_slot[slot] = next;
        self.compact_texts[slot].set(text_value);
    }
    fn popupOpened(self: *const View, index: usize) bool {
        return self.popup_open[index].peek();
    }
    fn openPopupChanged(self: *View, index: usize, open: bool) void {
        if (open) {
            if (!self.popup_open[index].peek()) self.popup_open[index].set(true);
            return;
        }
        const kind: Kind = if (index == 0) .model else .usage;
        // The native Popover closed itself (Escape, outside click): only the bookkeeping is ours.
        // Focus goes back through `returnFocus`.
        if (self.popup_open[index].peek()) self.popup_open[index].set(false);
        if (index == 0) self.model_anchor = null;
        self.captures[@backingInt(kind)] = null;
    }
    /// The focusId of control `name` of this composer.
    fn focusName(self: *View, name: FocusName) []const u8 {
        const buf = &self.focus_name_bufs[@intFromEnum(name)];
        return std.fmt.bufPrint(buf, "{s}.{s}", .{ self.focus_prefix, @tagName(name) }) catch unreachable;
    }
    /// The focusId of model-list row `index` (rows are mounted per index).
    fn rowFocusName(self: *View, buf: []u8, index: usize) []const u8 {
        return std.fmt.bufPrint(buf, "{s}.row.{d}", .{ self.focus_prefix, index }) catch unreachable;
    }
    /// The control a popover opens on. Model popover: the first model row that can be chosen
    /// (its row may still be mounting: the list is virtual), else the effort Slider while it is
    /// enabled. Usage popover: the compaction action while it can act. Otherwise no name: the
    /// native default, the panel's first control.
    fn initialFocusName(self: *View, index: usize) ?[]const u8 {
        const buf = &self.initial_focus_bufs[index];
        if (index == 1) {
            if (!self.usage_shown.get() or (!self.compaction_running.get() and !self.can_compact.get())) return null;
            const name = self.focusName(.usage_action);
            @memcpy(buf[0..name.len], name);
            return buf[0..name.len];
        }
        _ = self.model_version.get();
        for (self.model_rows.items, 0..) |row, position| {
            if (row.header) continue;
            if (!self.rowData(position).choosable) continue;
            return self.rowFocusName(buf, position);
        }
        if (!self.disabled[3].get()) {
            const name = self.focusName(.slider);
            @memcpy(buf[0..name.len], name);
            return buf[0..name.len];
        }
        return null;
    }
    /// The rows of one selection menu (Pencil Kaf7E O1 / O2 / O3), projected by the menus package
    /// (header, check of the current choice, description, Tag, separators, danger last).
    fn menuItems(self: *View, kind: Kind) []const app_menu.Entry {
        const out = &self.menu_entries[menuIndex(kind).?];
        const source = if (self.source) |*value| &value.value else null;
        const editable = if (source) |value| value.editable else false;
        const space = self.space;
        var count: usize = 0;
        switch (kind) {
            .attachment => {
                const rows = [_]struct { id: []const u8, label: []const u8, icon: []const u8, test_id: []const u8, kind: Attachment }{
                    .{ .id = "attachment.image", .label = "选择图片…", .icon = "image", .test_id = space.id("ai.attachment.image"), .kind = .image },
                    .{ .id = "attachment.local_text", .label = "选择本地文件…", .icon = "file-text", .test_id = space.id("ai.attachment.local_text"), .kind = .local_text },
                    .{ .id = "attachment.remote_file", .label = "引用远程文件…", .icon = "server", .test_id = space.id("ai.attachment.remote_file"), .kind = .remote_file },
                    .{ .id = "attachment.paste_image", .label = "粘贴图片", .icon = "clipboard-paste", .test_id = space.id("ai.attachment.paste_image"), .kind = .paste_image },
                };
                for (rows) |row| {
                    out[count] = .{ .id = row.id, .label = row.label, .icon = row.icon, .test_id = row.test_id, .disabled = !self.attachmentAvailable(row.kind), .group = if (row.kind == .paste_image) 1 else 0, .note = if (row.kind == .paste_image and self.paste_hint_text.len != 0) self.paste_hint_text else null };
                    count += 1;
                }
            },
            .permission => {
                const current = if (source) |value| value.permission else PermissionMode.confirm;
                const allow_auto = if (source) |value| value.allow_auto_permission else false;
                out[count] = .{ .label = "执行权限", .kind = .header };
                out[count + 1] = .{ .id = "permission.confirm", .label = permissionLabel(.confirm), .icon = "hand", .description = "部分读取自动，其余按策略确认", .selected = current == .confirm, .disabled = !editable, .test_id = space.id("ai.permission.confirm") };
                out[count + 2] = .{ .id = "permission.auto", .label = permissionLabel(.auto), .icon = "shield-check", .description = "授权内自动执行（含组内写入）", .selected = current == .auto, .disabled = !editable or !allow_auto, .test_id = space.id("ai.permission.auto") };
                out[count + 3] = .{ .label = "当前助手范围 · 禁止项不可执行", .kind = .header, .danger = true };
                count += 4;
                const authorized = if (source) |value| value.inventory_authorized and value.inventory_conversation_id != null else false;
                if (authorized) {
                    out[count] = .{ .id = "permission.revoke", .label = "撤销会话列表授权", .icon = "unlink", .danger = true, .test_id = space.id("ai.permission.revoke_inventory") };
                    count += 1;
                }
            },
            .execution => {
                const selected = if (source) |value| value.execution_mode_override orelse value.global_execution_mode else ExecutionMode.auto;
                out[count] = .{ .label = "当前对话运行方式", .kind = .header };
                count += 1;
                const modes = [_]struct { mode: ExecutionMode, id: []const u8, test_id: []const u8 }{
                    .{ .mode = .auto, .id = "execution.auto", .test_id = space.id("ai.execution.auto") },
                    .{ .mode = .ask, .id = "execution.ask", .test_id = space.id("ai.execution.ask") },
                    .{ .mode = .isolated_exec, .id = "execution.isolated_exec", .test_id = space.id("ai.execution.isolated_exec") },
                    .{ .mode = .attached_pty, .id = "execution.attached_pty", .test_id = space.id("ai.execution.attached_pty") },
                    .{ .mode = .new_pty, .id = "execution.new_pty", .test_id = space.id("ai.execution.new_pty") },
                };
                for (modes) |row| {
                    out[count] = .{ .id = row.id, .label = config.executionModeLabel(row.mode), .icon = executionIconName(row.mode), .selected = selected == row.mode, .tag = if (row.mode == .attached_pty or row.mode == .new_pty) "交互式" else null, .disabled = !editable, .test_id = row.test_id };
                    count += 1;
                }
                const retention = if (source) |value| value.session_retention_override else null;
                const options = [_]struct { id: []const u8, label: []const u8, test_id: []const u8, value: ?SessionRetention }{
                    .{ .id = "retention.inherit", .label = "跟随全局", .test_id = space.id("ai.retention.inherit"), .value = null },
                    .{ .id = "retention.auto_idle", .label = "空闲后关闭", .test_id = space.id("ai.retention.auto_idle"), .value = .auto_idle },
                    .{ .id = "retention.ask", .label = "每次询问", .test_id = space.id("ai.retention.ask"), .value = .ask },
                    .{ .id = "retention.keep", .label = "保留任务会话", .test_id = space.id("ai.retention.keep"), .value = .keep },
                };
                var current_label: []const u8 = options[0].label;
                for (options, 0..) |option, index| {
                    const chosen = std.meta.eql(option.value, retention);
                    if (chosen) current_label = option.label;
                    self.retention_entries[index] = .{ .id = option.id, .label = option.label, .selected = chosen, .disabled = !editable, .test_id = option.test_id };
                }
                const slot = self.retention_slot +% 1;
                self.retention_slot = slot;
                const description = std.fmt.bufPrint(&self.retention_text[slot], "全局：{s} · 只影响之后的执行", .{config.sessionRetentionLabel(if (source) |value| value.global_session_retention else .auto_idle)}) catch "用于后续执行和新建任务会话，当前执行与已有终端保留原策略。";
                out[count] = .{ .id = "retention", .label = "任务会话处理", .icon = "timer", .note = current_label, .description = description, .group = 1, .disabled = !editable, .children = &self.retention_entries, .submenu_test_id = space.id("ai.retention.menu"), .test_id = space.id("ai.execution.retention") };
                count += 1;
            },
            else => unreachable,
        }
        return out[0..count];
    }
    fn menuSelected(self: *View, kind: Kind, id: []const u8) void {
        const action: Action = if (std.mem.startsWith(u8, id, "attachment."))
            .{ .attachment = std.meta.stringToEnum(Attachment, id["attachment.".len..]) orelse return }
        else if (std.mem.eql(u8, id, "permission.revoke")) {
            self.revokeInventory();
            return;
        } else if (std.mem.startsWith(u8, id, "permission."))
            .{ .permission = std.meta.stringToEnum(PermissionMode, id["permission.".len..]) orelse return }
        else if (std.mem.startsWith(u8, id, "execution."))
            .{ .execution_mode = std.meta.stringToEnum(ExecutionMode, id["execution.".len..]) orelse return }
        else if (std.mem.eql(u8, id, "retention.inherit"))
            .{ .session_retention = null }
        else if (std.mem.startsWith(u8, id, "retention."))
            .{ .session_retention = std.meta.stringToEnum(SessionRetention, id["retention.".len..]) orelse return }
        else
            return;
        self.emit(kind, action);
    }
    fn refreshExecution(self: *View, source: ?*const Projection) !void {
        const selected = if (source) |value| value.execution_mode_override else null;
        const global = if (source) |value| value.global_execution_mode else .auto;
        const mode = selected orelse global;
        self.texts[5].set(config.executionModeLabel(mode));
        self.glyphs[5].set(executionIcon(mode));
        self.compact_icons[1].set(executionIcon(mode));
        self.setCompactText(1, "当前对话运行方式", config.executionModeLabel(mode));
    }
    fn modelContextWidth(self: *const View) f32 {
        var w: f32 = 0;
        if (self.source) |source| for (source.value.models) |model| {
            var buffer: [64]u8 = undefined;
            const value = tokenText(&buffer, model.context_window) catch unreachable;
            w = @max(w, self.cx.text.measureTextWidth(value, 10, 400, true));
        };
        return @ceil(w);
    }
    fn openModelSettings(self: *View) void {
        if (self.callbacks.open_settings) |open| open(self.callbacks.context);
    }
    fn modelItemHeight(index: usize, raw: ?*anyopaque) f32 {
        const self: *View = @ptrCast(@alignCast(raw orelse return 30));
        return if (index < self.model_rows.items.len and self.model_rows.items[index].header) 28 else 30;
    }
    /// Borrowed inputs are projected to owned display data during this call.
    /// Publication/rebinding happens in the next safe layout hook.
    pub fn update(self: *View, snapshot: ?Snapshot) !void {
        if (snapshot) |value| {
            var next = try Owned.init(self.cx.allocator, value);
            errdefer next.deinit();
            const previous = if (self.pending) |*pending| &pending.value else if (self.source) |*source| &source.value else null;
            if (previous) |old| if (old.owner.eql(value.owner)) {
                if (value.revision < old.revision) return error.StaleSnapshot;
                if (value.revision == old.revision and next.value.config_hash != old.config_hash) return error.ConfigurationChangedWithoutRevision;
                if (projectionEql(old.*, next.value)) {
                    next.deinit();
                    return;
                }
            };
            if (self.pending) |*old| old.deinit();
            self.pending = next;
            self.clear_pending = false;
        } else {
            if (self.source == null and self.pending == null and !self.clear_pending) return;
            if (self.pending) |*old| old.deinit();
            self.pending = null;
            self.clear_pending = true;
        }
        self.cx.requestRedraw();
    }
    /// Discovery changes the control revision, but the model picker can rebind
    /// to the new catalog at flush's safe point without closing under the user.
    pub fn preserveModelPopup(self: *View) void {
        self.keep_model_popup_on_update = true;
    }
    pub fn dismiss(self: *View) void {
        for (0..6) |index| self.close(@fromBackingInt(@intCast(index)), false);
    }
    /// A pending decision replaces the whole composer (the textarea, and this row in its footer).
    pub fn setInteraction(self: *View, active: bool) void {
        if (active and !self.interaction_active) self.dismiss();
        self.interaction_active = active;
    }
    fn kindOpen(self: *const View, kind: Kind) bool {
        if (menuIndex(kind)) |index| return self.menus[index].isOpen();
        return self.popupOpened(popupIndex(kind).?);
    }
    pub fn isOpen(self: *const View) bool {
        for (self.menus) |menu| if (menu.isOpen()) return true;
        for (0..2) |index| if (self.popupOpened(index)) return true;
        return false;
    }
    pub fn flush(self: *View) !void {
        if (self.pending_provider) |index| {
            self.pending_provider = null;
            try self.toggleProvider(index);
        }
        var changed = false;
        var controls_changed = false;
        var models_changed = false;
        if (self.clear_pending) {
            self.clear_pending = false;
            self.dismiss();
            self.retire();
            changed = true;
            controls_changed = true;
            models_changed = true;
        } else if (self.pending) |next| {
            controls_changed = if (self.source) |old| !controlsEql(old.value, next.value) else true;
            models_changed = if (self.source) |old| !modelRowsEql(old.value, next.value) else true;
            if (self.source) |*old| {
                if (!old.value.owner.eql(next.value.owner) or old.value.revision != next.value.revision) {
                    const keep_model = self.keep_model_popup_on_update and old.value.owner.eql(next.value.owner) and self.popupOpened(0);
                    self.dismiss();
                    // A catalog refresh started by opening the picker keeps it open (reopened on the new rows).
                    if (keep_model) {
                        self.popup_open[0].set(true);
                        self.captures[@backingInt(Kind.model)] = .{ .owner = next.value.owner, .revision = next.value.revision, .inventory_conversation_id = next.value.inventory_conversation_id };
                    }
                } else if (!optionalKeyEql(old.value.current, next.value.current)) self.close(.effort, false);
            }
            self.retire();
            self.source = next;
            self.pending = null;
            changed = true;
        }
        if (controls_changed) self.proposed_reasoning = null;
        self.keep_model_popup_on_update = false;
        if (changed) {
            try self.refreshUsageBadge();
            self.usage_dirty = true;
        }
        if (controls_changed) try self.refresh();
        if (models_changed) try self.filterModels();
        if (self.usage_dirty and self.popupOpened(1)) {
            try self.refreshUsage();
            self.usage_dirty = false;
        }
        self.viewport = self.cx.viewport;
    }
    /// The current projection moves to `retired` (freed at the next replacement).
    fn retire(self: *View) void {
        if (self.retired) |*old| old.deinit();
        self.retired = self.source;
        self.source = null;
    }
    fn router() shell.shortcut_router.Router {
        return .{ .keys = &no_keys.map };
    }
    fn toggle(self: *View, requested: Kind) void {
        const kind: Kind = if (requested == .effort) .model else requested;
        const index = @backingInt(kind);
        if (self.disabled[index].peek() or self.source == null) return;
        if (self.kindOpen(kind)) {
            self.close(kind, true);
            return;
        }
        self.dismiss();
        const source = &self.source.?.value;
        self.last_error = null;
        self.model_error.set(false);
        self.captures[index] = .{ .owner = source.owner, .revision = source.revision, .inventory_conversation_id = source.inventory_conversation_id };
        if (menuIndex(kind)) |menu| {
            self.menus[menu].show(self.menuItems(kind), router(), self.anchorButton(kind).globalRect());
            return;
        }
        if (kind == .model) {
            const r = self.anchorButton(.model).globalRect();
            const row = self.root.globalRect();
            self.model_anchor = .{ .x = r.x - row.x, .y = r.y - row.y, .w = r.w, .h = r.h };
        }
        self.popup_open[popupIndex(kind).?].set(true);
        if (kind == .model) if (self.callbacks.models_opened) |opened| opened(self.callbacks.context);
        if (kind == .usage) self.usage_dirty = true;
        self.cx.requestRedraw();
    }
    fn close(self: *View, kind: Kind, restore: bool) void {
        // The effort control lives inside the model popover: there is nothing of its own to close
        // (closing it must not take the model list away, e.g. for a model without reasoning).
        if (kind == .effort) return;
        const was_open = self.kindOpen(kind);
        self.captures[@backingInt(kind)] = null;
        if (menuIndex(kind)) |menu| {
            self.menus[menu].hide();
            if (restore and was_open) self.cx.setFocus(self.anchorButton(kind));
            return;
        }
        // A popover gives focus back itself (`returnFocus`) when it closes with focus inside.
        if (self.popupOpened(popupIndex(kind).?)) self.popup_open[popupIndex(kind).?].set(false);
    }
    fn capture(self: *View, kind: Kind) ?Capture {
        const owner_kind: Kind = if (kind == .effort) .model else kind;
        // A menu closes before it reports the chosen row; the capture taken at open still decides.
        if (popupIndex(owner_kind)) |popup| if (!self.popupOpened(popup)) return null;
        const captured = self.captures[@backingInt(owner_kind)] orelse return null;
        const source = if (self.source) |*source| &source.value else return null;
        if (!captured.owner.eql(source.owner) or captured.revision != source.revision) return null;
        if (self.clear_pending) return null;
        if (self.pending) |*pending| if (!captured.owner.eql(pending.value.owner) or captured.revision != pending.value.revision) return null;
        return captured;
    }
    fn findModel(self: *const View, key: ModelKey) ?Model {
        const source = if (self.source) |source| source.value else return null;
        for (source.models) |item| if (item.key.eql(key)) return item;
        return null;
    }
    fn currentModel(self: *const View) ?Model {
        const source = if (self.source) |source| source.value else return null;
        return self.findModel(source.current orelse return null);
    }
    fn attachmentAvailable(self: *const View, attachment: Attachment) bool {
        const source = if (self.source) |source| source.value else return false;
        if (!source.editable) return false;
        const allowed = switch (attachment) {
            .image => source.attachments.image,
            .local_text => source.attachments.local_text,
            .remote_file => source.attachments.remote_file,
            .paste_image => source.attachments.paste_image,
        };
        if (!allowed) return false;
        // Capture remains available when the next model lacks vision. The
        // host preserves the image and explains why sending is blocked.
        return true;
    }
    fn revokeInventory(self: *View) void {
        const captured = self.capture(.permission) orelse return;
        const conversation_id = captured.inventory_conversation_id orelse return;
        self.emit(.permission, .{ .revoke_inventory = conversation_id });
    }
    fn emit(self: *View, kind: Kind, action: Action) void {
        const captured = self.capture(kind) orelse return;
        const source = &self.source.?.value;
        if (!source.editable and action != .revoke_inventory) return;
        if (action == .permission and action.permission == .auto and !source.allow_auto_permission) return;
        switch (action) {
            .revoke_inventory => |conversation_id| {
                if (!source.inventory_authorized or source.inventory_conversation_id == null or !source.inventory_conversation_id.?.eql(conversation_id)) return;
                if (self.pending) |pending| if (!pending.value.inventory_authorized or pending.value.inventory_conversation_id == null or !pending.value.inventory_conversation_id.?.eql(conversation_id)) return;
            },
            .model => |key| {
                const selected = self.findModel(key) orelse return;
                if (!selected.enabled) return;
            },
            .permission, .execution_mode, .session_retention => {},
            .compact_context => if (source.usage == null or !source.usage.?.can_compact) return,
            .cancel_compaction => if (source.usage == null or source.usage.?.compaction != .running) return,
            .effort => |value| {
                const selected = self.currentModel() orelse return;
                if (!selected.enabled or !selected.key.eql(value.model) or !selected.reasoning or !selected.efforts[@backingInt(value.value)]) return;
            },
            .thinking => |value| {
                const selected = self.currentModel() orelse return;
                if (!selected.enabled or !selected.key.eql(value.model) or !selected.reasoning or !selected.toggle) return;
            },
            .attachment => |attachment| if (!self.attachmentAvailable(attachment)) return,
        }
        self.callbacks.action(self.callbacks.context, .{ .owner = captured.owner, .revision = captured.revision, .action = action }) catch |err| {
            self.last_error = err;
            if (kind == .model or kind == .effort) self.model_error.set(true);
            return;
        };
        self.last_error = null;
        switch (action) {
            .effort => |value| self.proposed_reasoning = .{ .effort = value.value },
            .thinking => |value| self.proposed_reasoning = if (value.enabled) .on else .off,
            else => {},
        }
        if (kind != .effort and kind != .model and kind != .usage) self.close(kind, true);
    }
    fn chooseReasoning(self: *View, index: usize) void {
        if (index >= self.reasoning_count) return;
        const selected = self.currentModel() orelse return;
        switch (self.reasoning_choices[index]) {
            .off => self.emit(.model, .{ .thinking = .{ .model = selected.key, .enabled = false } }),
            .on => self.emit(.model, .{ .thinking = .{ .model = selected.key, .enabled = true } }),
            .effort => |value| self.emit(.effort, .{ .effort = .{ .model = selected.key, .value = value } }),
        }
    }
    fn effortProposed(self: *View, raw: f32) void {
        if (!std.math.isFinite(raw) or self.reasoning_count == 0) return;
        const index: usize = @intFromFloat(@round(std.math.clamp(raw, 0, 4) * @as(f32, @floatFromInt(self.reasoning_count - 1)) / 4));
        const source = if (self.pending) |value| value.value else if (self.source) |value| value.value else return;
        const choice = self.reasoning_choices[index];
        if (self.proposed_reasoning) |proposed| {
            if (std.meta.eql(proposed, choice)) return;
        } else switch (choice) {
            .effort => |effort| if (source.effort == effort and source.thinking != false) return,
            .off => if (source.thinking == false) return,
            .on => if (source.thinking == true) return,
        }
        self.chooseReasoning(index);
    }
    /// Left / right / home / end on the slider move between the model's supported steps only.
    pub fn sliderKey(self: *View, key: ui.events.KeyCode) bool {
        if (key != .left and key != .right and key != .home and key != .end) return false;
        if (self.capture(.effort) == null or self.disabled[@backingInt(Kind.effort)].peek()) return false;
        if (self.reasoning_count == 0) return false;
        const current: i32 = @intFromFloat(@round(self.slider_value.peek() * @as(f32, @floatFromInt(self.reasoning_count - 1)) / 4));
        const last: i32 = @intCast(self.reasoning_count - 1);
        const next = if (key == .home) 0 else if (key == .end) last else std.math.clamp(current + @as(i32, if (key == .left) -1 else 1), 0, last);
        self.chooseReasoning(@intCast(next));
        return true;
    }
    fn providerCollapsed(self: *const View, id: []const u8) bool {
        for (self.collapsed_providers.items) |value| if (std.mem.eql(u8, value, id)) return true;
        return false;
    }
    fn toggleProvider(self: *View, index: usize) !void {
        const source = if (self.source) |*value| &value.value else return;
        if (index >= source.models.len) return;
        const id = source.models[index].key.provider_id;
        for (self.collapsed_providers.items, 0..) |value, i| if (std.mem.eql(u8, value, id)) {
            self.cx.allocator.free(self.collapsed_providers.orderedRemove(i));
            try self.filterModels();
            return;
        };
        const copy = try self.cx.allocator.dupe(u8, id);
        errdefer self.cx.allocator.free(copy);
        try self.collapsed_providers.append(self.cx.allocator, copy);
        try self.filterModels();
    }
    fn filterModels(self: *View) !void {
        self.filtered.clearRetainingCapacity();
        if (self.source) |*source| for (source.value.models, 0..) |_, index| {
            try self.filtered.append(self.cx.allocator, index);
        };
        self.model_rows.clearRetainingCapacity();
        var previous: ?[]const u8 = null;
        if (self.source) |source| for (self.filtered.items) |index| {
            const id = source.value.models[index].key.provider_id;
            if (previous == null or !std.mem.eql(u8, previous.?, id)) try self.model_rows.append(self.cx.allocator, .{ .index = index, .header = true });
            if (!self.providerCollapsed(id)) try self.model_rows.append(self.cx.allocator, .{ .index = index, .header = false });
            previous = id;
        };
        self.model_count.set(self.model_rows.items.len);
        self.model_version.set(self.model_version.peek() +| 1);
        self.models_empty.set(self.filtered.items.len == 0);
        var available = false;
        if (self.source) |*value| for (value.value.models) |model| {
            available = available or model.enabled;
        };
        self.settings_shown.set(!available and self.callbacks.open_settings != null);
    }
    fn refresh(self: *View) !void {
        const source = if (self.source) |*source| &source.value else null;
        const editable = if (source) |value| value.editable else false;
        const current = self.currentModel();
        var any_model = false;
        if (source) |value| for (value.models) |item| {
            any_model = any_model or item.enabled;
        };
        var any_attachment = false;
        for (0..4) |index| any_attachment = any_attachment or self.attachmentAvailable(@fromBackingInt(@intCast(index)));
        var any_effort = false;
        if (current) |item| for (item.efforts) |enabled| {
            any_effort = any_effort or enabled;
        };
        self.disabled[0].set(!any_attachment);
        const inventory_authorized = if (source) |value| value.inventory_authorized and value.inventory_conversation_id != null else false;
        self.disabled[1].set(!editable and !inventory_authorized);
        self.disabled[5].set(!editable);
        self.disabled[2].set(!editable or (!any_model and self.callbacks.open_settings == null));
        self.reasoning_count = 0;
        if (current) |model| if (model.reasoning and model.enabled) {
            if (model.toggle) {
                self.reasoning_choices[self.reasoning_count] = .off;
                self.reasoning_count += 1;
            }
            for ([_]usize{ 5, 0, 1, 2, 3, 4, 6 }) |index| if (model.efforts[index]) {
                self.reasoning_choices[self.reasoning_count] = .{ .effort = @fromBackingInt(@intCast(index)) };
                self.reasoning_count += 1;
            };
            if (model.toggle and !any_effort) {
                self.reasoning_choices[self.reasoning_count] = .on;
                self.reasoning_count += 1;
            }
        };
        self.disabled[3].set(!editable or self.reasoning_count == 0);
        if (self.disabled[0].peek()) self.close(.attachment, false);
        if (self.disabled[1].peek()) self.close(.permission, false);
        if (self.disabled[2].peek()) self.close(.model, false);
        if (self.disabled[3].peek()) self.close(.effort, false);
        if (self.disabled[4].peek()) self.close(.usage, false);
        if (self.disabled[5].peek()) self.close(.execution, false);
        try self.refreshExecution(source);
        const permission = if (source) |value| value.permission else PermissionMode.confirm;
        self.texts[1].set(if (source != null) permissionLabel(permission) else "执行权限");
        const permission_icon = ui.icons.get(if (source != null and permission == .auto) "shield-check" else "hand").?;
        self.glyphs[1].set(permission_icon);
        self.compact_icons[0].set(permission_icon);
        self.setCompactText(0, "执行权限", if (source != null) permissionLabel(permission) else "未设置");
        const full_model_name = if (current) |item| item.key.model_id else if (source) |value| if (value.current) |key| key.model_id else "未配置模型" else "未配置模型";
        self.model_hint.set(full_model_name);
        const effort = if (source) |value| value.effort orelse (if (current != null and current.?.enabled and current.?.reasoning and value.thinking != false) Effort.lowestSupported(current.?.efforts) else null) else null;
        const default_thinking = if (current) |m| m.thinking_default orelse false else false;
        const thinking_enabled = if (source) |value| value.thinking orelse default_thinking else default_thinking;
        self.effort_shown.set(!self.disabled[3].peek());
        const effort_text = if (current == null or !current.?.enabled) "模型未就绪" else if (!current.?.reasoning) "不支持推理" else if (current.?.toggle and !any_effort) (if (source.?.thinking == null and current.?.thinking_default == null) "模型默认" else if (thinking_enabled) "思考开" else "思考关") else if (!any_effort) "推理未开放" else if (effort) |value| if (current.?.efforts[@backingInt(value)]) effortLabel(value) else "档位不支持" else "模型默认";
        self.effort_name.set(if (std.mem.eql(u8, effort_text, "模型默认")) "跟随模型默认" else if (current != null and current.?.enabled and current.?.reasoning and !current.?.toggle and !any_effort) "未开放思考开关或推理档位" else effort_text);
        self.texts[3].set(effort_text);
        // Model control: "model · effort" (Pencil Kaf7E A3 "sonnet-4 · 低"); afterLayout fits it.
        const show_effort = current != null and current.?.reasoning;
        const full = if (show_effort) std.fmt.bufPrint(&self.model_full, "{s} · {s}", .{ full_model_name, effort_text }) catch full_model_name else std.fmt.bufPrint(&self.model_full, "{s}", .{full_model_name}) catch "";
        self.model_full_len = full.len;
        self.model_name_len = @min(full.len, full_model_name.len);
        self.texts[2].set(full);
        var selected_choice: ?usize = null;
        for (self.reasoning_choices[0..self.reasoning_count], 0..) |choice, index| {
            const selected = switch (choice) {
                .off => (source.?.thinking != null or current.?.thinking_default != null) and !thinking_enabled,
                .on => (source.?.thinking != null or current.?.thinking_default != null) and thinking_enabled,
                .effort => |value| effort != null and value == effort.? and (source.?.thinking == null or thinking_enabled),
            };
            if (selected) selected_choice = index;
        }
        self.slider_value.set(if (self.reasoning_count > 1) @as(f32, @floatFromInt(selected_choice orelse 0)) * 4 / @as(f32, @floatFromInt(self.reasoning_count - 1)) else 0);
        self.thumb_shown.set(selected_choice != null);
        // One mark per supported step, evenly over the track (value 0 … 4), labelled.
        const slot = self.mark_slot +% 1;
        self.mark_slot = slot;
        const rows = &self.mark_rows[slot];
        for (0..self.reasoning_count) |index| rows[index] = .{
            .value = if (self.reasoning_count > 1) @as(f32, @floatFromInt(index)) * 4 / @as(f32, @floatFromInt(self.reasoning_count - 1)) else 0,
            .label = switch (self.reasoning_choices[index]) {
                .off => "关闭",
                .on => "开启",
                .effort => |value| effortLabel(value),
            },
            .test_id = self.space.id("ai.effort.marker"),
            .label_test_id = self.space.id("ai.effort.tick"),
        };
        self.marks.set(rows[0..self.reasoning_count]);
        // An open selection menu follows the new projection (same capture rules).
        for (menu_kinds, 0..) |kind, index| if (self.menus[index].isOpen()) self.menus[index].set(self.menuItems(kind), router());
    }
    fn refreshUsageBadge(self: *View) !void {
        const source = if (self.source) |*value| &value.value else null;
        self.disabled[4].set(source == null or source.?.usage == null);
        if (self.disabled[4].peek()) self.close(.usage, false);
        var buffer: [64]u8 = undefined;
        const usage = if (source) |value| value.usage else null;
        self.texts[4].set(if (usage) |value| try percentText(&buffer, value) else "—");
        self.ring_value.set(if (usage) |value| if (value.limit_tokens == 0) 0 else @min(100, 100 * @as(f32, @floatFromInt(value.used_tokens)) / @as(f32, @floatFromInt(value.limit_tokens))) else 0);
    }
    /// Pencil Kaf7E O6: head (label · used / limit), the segmented bar (parts cycle three colors),
    /// a legend row per part, a separator and the native secondary sm compaction Button.
    fn refreshUsage(self: *View) !void {
        const source = if (self.source) |source| source.value else {
            self.usage_shown.set(false);
            return;
        };
        const usage = source.usage orelse {
            self.usage_shown.set(false);
            return;
        };
        // Equal-value writes may be suppressed by signals. Own each row's
        // text for its whole lifetime rather than borrowing alternating arenas.
        var percent_buffer: [24]u8 = undefined;
        var caption_buffer: [64]u8 = undefined;
        self.usage_caption.set(try std.fmt.bufPrint(&caption_buffer, "上下文已用 {s}", .{try percentText(&percent_buffer, usage)}));
        var used_buffer: [24]u8 = undefined;
        var limit_buffer: [24]u8 = undefined;
        var total_buffer: [64]u8 = undefined;
        self.usage_total.set(try std.fmt.bufPrint(&total_buffer, "{s}{s} / {s}", .{ if (usage.estimated) "~" else "", try tokenText(&used_buffer, usage.used_tokens), try tokenText(&limit_buffer, usage.limit_tokens) }));
        // Native W.ProgressSegments: each source its share of the window, tones cycling like the legend.
        var segments: [ui.widgets.progress.max_segments]W.ProgressSegment = undefined;
        var segment_count: usize = 0;
        for (usage.parts, 0..) |part, index| {
            if (segment_count == segments.len) break;
            if (part.tokens == 0 or usage.limit_tokens == 0) continue;
            segments[segment_count] = .{ .value = 100 * @as(f32, @floatFromInt(part.tokens)) / @as(f32, @floatFromInt(usage.limit_tokens)), .tone = S.usageTone(index) };
            segment_count += 1;
        }
        var rows: [max_usage_rows]UsageRow = undefined;
        const row_count = @min(usage.parts.len, rows.len);
        for (usage.parts[0..row_count], rows[0..row_count], 0..) |part, *row, index| {
            if (self.usage_cells[index] == null) self.usage_cells[index] = .{
                .index = index,
                .tone = S.usageTone(index),
                .name = try self.scope.createText("", .{}),
                .value = try self.scope.createText("", .{ .capacity = 24 }),
            };
            row.* = self.usage_cells[index].?;
            row.name.set(part.name);
            var value_buffer: [32]u8 = undefined;
            row.value.set(try std.fmt.bufPrint(&value_buffer, "{s}{s}", .{ if (part.estimated orelse usage.estimated) "~" else "", try tokenText(&used_buffer, part.tokens) }));
        }
        self.usage_segments.set(segments[0..segment_count]);
        self.usage_rows.set(rows[0..row_count]);
        const running = usage.compaction == .running;
        self.compaction_reason.set(if (running) "取消压缩" else switch (usage.compaction) {
            .failed => "压缩失败，点击重试",
            .cancelled => "已取消压缩，点击重新压缩",
            .succeeded => if (usage.can_compact) "上下文已压缩，点击再次压缩" else "上下文已压缩",
            else => if (usage.can_compact) "压缩上下文" else "当前无可压缩的历史上下文",
        });
        self.compaction_running.set(running);
        self.can_compact.set(usage.can_compact);
        self.usage_shown.set(true);
    }
    /// Fit `text` into `room` points at the sm label size, ending in "…" when cut (codepoint steps).
    fn ellipsize(self: *View, text_value: []const u8, room: f32) []const u8 {
        if (self.measureLabel(text_value) <= room + 0.5) return text_value;
        var end = text_value.len;
        while (end > 0) {
            end -= 1;
            while (end > 0 and (text_value[end] & 0xC0) == 0x80) end -= 1;
            const candidate = std.fmt.bufPrint(&self.model_shown, "{s}…", .{text_value[0..end]}) catch return text_value;
            if (self.measureLabel(candidate) <= room + 0.5) return candidate;
        }
        return std.fmt.bufPrint(&self.model_shown, "…", .{}) catch text_value;
    }
    /// The model text for `room`: the whole “model · effort”; else the model name cut with “…”
    /// keeping “ · effort” while the name keeps at least `min_name`; else the name alone, cut.
    fn fitModel(self: *View, full: []const u8, room: f32, min_name: f32) []const u8 {
        if (self.measureLabel(full) <= room + 0.5) return full;
        const name = full[0..self.model_name_len];
        const suffix = full[self.model_name_len..];
        if (suffix.len != 0) {
            const name_room = room - self.measureLabel(suffix);
            if (name_room >= min_name) {
                const cut = self.ellipsize(name, name_room);
                const joined = std.fmt.bufPrint(&self.model_shown_name, "{s}{s}", .{ cut, suffix }) catch return cut;
                return joined;
            }
        }
        return self.ellipsize(name, room);
    }
    /// Width of `text` in the label style of the row's native ghost sm Buttons (zenit's own
    /// `Button.labelText`, not read back from a rendered label).
    fn measureLabel(self: *View, text_value: []const u8) f32 {
        const style = W.button.labelText(self.cx.tokens, .sm, .ghost);
        return @ceil(self.cx.text.measureTextWidth(text_value, style.font_size, style.font_weight, false));
    }
    fn afterLayout(raw: *anyopaque, _: u8, _: bool) ui.AfterLayoutResult {
        const self: *View = @ptrCast(@alignCast(raw));
        // Not placed yet (the composer template mounts the row after the view-model).
        if (!self.placed()) return .done;
        if (!self.root.isDisplayedInTree()) {
            self.dismiss();
            // Release a revoked snapshot even while hidden. Retain the clear
            // flag so reopening still repaints the empty projection once.
            if (self.clear_pending) self.retire();
            return .done;
        }
        self.flush() catch {};
        if (self.interaction_active) return .done;
        const row = self.root.globalRect();
        if (row.w <= 0) return .done;
        // Measure the chrome around each label while the full control is shown.
        for ([2]usize{ 1, 5 }, 0..) |index, slot| {
            const r = self.buttons[index].globalRect();
            if (self.buttons[index].style.display != .none and r.w > 0) self.chip_chrome[slot] = r.w - self.measureLabel(self.texts[index].peek());
        }
        const model_rect = self.buttons[2].globalRect();
        if (model_rect.w > 0) self.model_chrome = model_rect.w - self.measureLabel(self.texts[2].peek());
        for (self.compact_buttons) |button| if (button.globalRect().w > 0) {
            self.compact_width = button.globalRect().w;
        };
        const full_model = self.model_full[0..self.model_full_len];
        const model_width = self.measureLabel(full_model);
        const permission_width = (if (self.chip_chrome[0] > 0) self.chip_chrome[0] else 48) + self.measureLabel(self.texts[1].peek());
        const execution_width = (if (self.chip_chrome[1] > 0) self.chip_chrome[1] else 48) + self.measureLabel(self.texts[5].peek());
        // Everything on the row but the permission / execution / model controls and the spacer.
        var others: f32 = 0;
        var visible: f32 = 0;
        for (self.root.children.items) |child| {
            const r = child.globalRect();
            if (child.style.display == .none or child.style.position == .absolute or r.w <= 0) continue;
            visible += 1;
            if (child == self.ordinary_spacer or child == self.buttons[1] or child == self.buttons[5] or child == self.compact_wrappers[0] or child == self.compact_wrappers[1] or self.buttons[2].isDescendantOf(child)) continue;
            others += r.w;
        }
        // Gaps between the shown controls (spacer, permission, execution and model always count).
        // 4pt slack: the measured label width can trail the native label's rendered width.
        const gaps = @max(0, visible - 1) * S.row_gap + 4;
        const available = row.w - others - gaps - (if (self.model_chrome > 0) self.model_chrome else 24);
        // Shrink order (bugfix-2, Pencil ⑤ 宽度): truncate the model text first (down to 48),
        // then collapse permission into its icon button, then execution. Decided from the row
        // width alone, so it never oscillates.
        const min_model_label: f32 = @min(model_width, 48);
        const icon_width = self.compact_width;
        const permission_compact = available - permission_width - execution_width < min_model_label;
        const compact = permission_compact and available - icon_width - execution_width < min_model_label;
        if (compact != self.execution_compact or permission_compact != self.permission_compact) {
            const was_open = [2]bool{ self.kindOpen(.permission), self.kindOpen(.execution) };
            self.permission_compact = permission_compact;
            self.execution_compact = compact;
            for ([2]usize{ 1, 5 }, [2]bool{ permission_compact, compact }, 0..) |index, collapsed, slot| {
                if (self.compact_shown[slot].peek() != collapsed) self.compact_shown[slot].set(collapsed);
                // A width change while a menu is open keeps focus on the visible control.
                if (was_open[slot]) if (self.cx.focus_manager.current_focus) |focused| {
                    if (focused == self.buttons[index] or focused == self.compact_buttons[slot]) self.cx.setFocus(self.anchorButton(@fromBackingInt(@intCast(index))));
                };
            }
            return .needs_layout;
        }
        const used = (if (permission_compact) icon_width else permission_width) + (if (compact) icon_width else execution_width);
        const room = @max(0, available - used);
        const shown = self.fitModel(full_model, room, min_model_label);
        if (!std.mem.eql(u8, shown, self.texts[2].peek())) {
            self.texts[2].set(shown);
            return .needs_layout;
        }
        return .done;
    }
    /// The template has placed the row (its onMount kept the nodes).
    fn placed(self: *const View) bool {
        return self.row_kept and self.popups_kept == 2;
    }
    /// 粘贴的快捷键文字（静态字符串，来自快捷键路由；随 `[keys]` 变化）。
    pub fn syncPasteShortcut(self: *View, hint: []const u8) void {
        if (std.mem.eql(u8, self.paste_hint_text, hint)) return;
        self.paste_hint_text = hint;
        if (self.menus[0].isOpen()) self.menus[0].set(self.menuItems(.attachment), router());
        self.cx.requestRedraw();
    }
    /// One model-list row for the view (`ModelRow`); strings borrow the projection.
    fn rowData(self: *View, index: usize) Row {
        const source = if (self.source) |*source| &source.value else return .{};
        if (index >= self.model_rows.items.len) return .{};
        const entry = self.model_rows.items[index];
        const model = source.models[entry.index];
        const selected = if (source.current) |current| current.eql(model.key) else false;
        return .{
            .id = model.key.model_id,
            .basename = brand.basename(model.key.model_id),
            .brand = if (brand.model(model.key.model_id)) |value| brand.asset(value) else null,
            .description = model.description,
            .context = model.context_text,
            .selected = selected,
            .enabled = model.enabled,
            .choosable = model.enabled and source.editable,
            .reasoning = model.reasoning,
            .vision = model.vision,
        };
    }
    fn release(self: *View) void {
        self.cx.removeAfterLayoutHook(self);
        if (self.source) |*source| source.deinit();
        if (self.pending) |*pending| pending.deinit();
        if (self.retired) |*retired| retired.deinit();
        self.filtered.deinit(self.cx.allocator);
        self.model_rows.deinit(self.cx.allocator);
        for (self.collapsed_providers.items) |id| self.cx.allocator.free(id);
        self.collapsed_providers.deinit(self.cx.allocator);
    }
    fn releaseFocus(self: *View) void {
        if (!self.placed()) return;
        const focused = self.cx.focus_manager.current_focus orelse return;
        if (focused.isDescendantOf(self.root)) {
            self.cx.clearFocus();
            return;
        }
        for (self.popups) |popup| if (focused.isDescendantOf(popup.chrome)) {
            self.cx.clearFocus();
            return;
        };
    }
};
const brand = @import("../../shared/view/ai_brand.zig");

// ── Template accessors (ai_composer_controls.yix) ─────────────────────────────────────────
pub fn buttonId(m: *const View, kind: Kind) []const u8 {
    return switch (kind) {
        .attachment => m.space.id("ai.composer.attachment"),
        .permission => m.space.id("ai.composer.permission"),
        .model => m.space.id("ai.composer.model"),
        .effort => m.space.id("ai.composer.effort"),
        .usage => m.space.id("ai.composer.usage"),
        .execution => m.space.id("ai.composer.execution"),
    };
}
pub fn text(m: *View, kind: Kind) []const u8 {
    return m.texts[@backingInt(kind)].get();
}
pub fn glyph(m: *View, kind: Kind) ?ui.SvgAsset {
    return m.glyphs[@backingInt(kind)].get();
}
pub fn hasChevron(kind: Kind) bool {
    return kind == .permission or kind == .model or kind == .execution;
}
/// Icon-only and the usage badge name themselves; the hidden effort control reads its value; the
/// others read their label.
pub fn chipA11y(m: *View, kind: Kind, name: []const u8) []const u8 {
    return switch (kind) {
        .attachment, .usage => name,
        .effort => m.effort_name.get(),
        else => "",
    };
}
pub fn disabled(m: *View, kind: Kind) bool {
    return m.disabled[@backingInt(kind)].get();
}
/// Effort lives inside the model control's label and the model popover (its chip never shows);
/// permission / run mode give way to their compact form on narrow rows.
pub fn chipShown(m: *View, kind: Kind) bool {
    return switch (kind) {
        .effort => false,
        .permission => !m.compact_shown[0].get(),
        .execution => !m.compact_shown[1].get(),
        else => true,
    };
}
pub fn toggle(m: *View, kind: Kind) void {
    m.toggle(kind);
}
pub fn compactKind(slot: usize) Kind {
    return if (slot == 0) .permission else .execution;
}
pub fn compactId(m: *const View, slot: usize) []const u8 {
    return if (slot == 0) m.space.id("ai.composer.permission.compact") else m.space.id("ai.composer.execution.compact");
}
pub fn compactTooltipId(m: *const View, slot: usize) []const u8 {
    return if (slot == 0) m.space.id("ai.composer.permission.compact.tooltip") else m.space.id("ai.composer.execution.compact.tooltip");
}
pub fn compactText(m: *View, slot: usize) []const u8 {
    return m.compact_texts[slot].get();
}
pub fn compactIcon(m: *View, slot: usize) ?ui.SvgAsset {
    return m.compact_icons[slot].get();
}
pub fn compactShown(m: *View, slot: usize) bool {
    return m.compact_shown[slot].get();
}
pub fn ringValue(m: *View) f32 {
    return m.ring_value.get();
}
pub fn modelHint(m: *View) []const u8 {
    return m.model_hint.get();
}
pub fn menuOpen(m: *View, index: usize) bool {
    return m.menus[index].open.get();
}
pub fn menuRows(m: *View, index: usize) []const W.MenuItem {
    return m.menus[index].items.get();
}
pub fn menuAnchor(m: *View, index: usize) W.popover.Anchor {
    return m.menus[index].virtualAnchor();
}
pub fn menuOpenChanged(m: *View, index: usize, open: bool) void {
    m.menus[index].openChange(open);
}
pub fn menuSelected(m: *View, index: usize, id: []const u8) void {
    m.menus[index].select(id);
}
pub fn popupOpen(m: *View, index: usize) bool {
    return m.popup_open[index].get();
}
pub fn popupAnchor(m: *View, index: usize) W.popover.Anchor {
    return .{ .virtual = .{ .ctx = &m.anchors[index], .getRect = Anchor.get } };
}
/// focusId of the control popover `index` (0 model, 1 usage) opens on, or null (its first control).
pub fn initialFocus(m: *View, index: usize) ?[]const u8 {
    return m.initialFocusName(index);
}
/// focusId of one of this composer's named controls (`focusId` / `returnFocus`).
pub fn focusName(m: *View, name: FocusName) []const u8 {
    return m.focusName(name);
}
/// focusId of model-list row `index`.
pub fn rowFocusId(m: *View, index: usize) []const u8 {
    return m.rowFocusName(&m.row_focus_buf, index);
}
pub fn popupOpenChanged(m: *View, index: usize, open: bool) void {
    m.openPopupChanged(index, open);
}
pub fn modelsEmpty(m: *View) bool {
    return m.models_empty.get();
}
pub fn settingsShown(m: *View) bool {
    return m.settings_shown.get();
}
pub fn openSettings(m: *View) void {
    m.openModelSettings();
}
pub fn modelError(m: *View) bool {
    return m.model_error.get();
}
pub fn effortShown(m: *View) bool {
    return m.effort_shown.get();
}
pub fn effortName(m: *View) []const u8 {
    return m.effort_name.get();
}
/// The slider shows the chosen step (read-only); a proposal goes to `effortProposed`.
pub fn sliderValue(m: *View) f32 {
    return m.slider_value.get();
}
pub fn effortProposed(m: *View, raw: f32) void {
    m.effortProposed(raw);
}
pub fn marks(m: *View) []const W.SliderMark {
    return m.marks.get();
}
pub fn thumbShown(m: *View) bool {
    return m.thumb_shown.get();
}
/// The model list (O4): a native VirtualList of provider headers and model rows.
pub fn ModelList(props: struct { m: ui.Source(*View) }) @TypeOf(W.VirtualList(.{}).rows(@as(*View, undefined), listRow)) {
    const m = props.m.peek();
    return W.VirtualList(.{ .item_count = m.model_count, .data_version = m.model_version, .item_height = 30, .item_height_fn = View.modelItemHeight, .item_height_context = m, .height = 172, .overscan = 1 }).rows(m, listRow);
}
fn listRow(m: *View, index: usize) @TypeOf(template.ListRow(.{ .m = @as(*View, undefined), .index = 0 })) {
    return template.ListRow(.{ .m = m, .index = index });
}
pub fn isHeader(m: *View, index: usize) bool {
    return index < m.model_rows.items.len and m.model_rows.items[index].header;
}
fn providerAt(m: *View, index: usize) ?Model {
    const source = if (m.source) |*source| &source.value else return null;
    if (index >= m.model_rows.items.len) return null;
    return source.models[m.model_rows.items[index].index];
}
pub fn providerName(m: *View, index: usize) []const u8 {
    return if (providerAt(m, index)) |model| model.key.provider_id else "";
}
pub fn providerBrand(m: *View, index: usize) ?ui.SvgAsset {
    return if (brand.provider(providerName(m, index), "")) |value| brand.asset(value) else null;
}
pub fn providerChevron(m: *View, index: usize) ui.SvgAsset {
    return if (m.providerCollapsed(providerName(m, index))) ui.icons.chevron_right else ui.icons.chevron_down;
}
pub fn toggleProvider(m: *View, index: usize) void {
    if (index >= m.model_rows.items.len) return;
    m.pending_provider = m.model_rows.items[index].index;
    m.cx.requestRedraw();
}
pub fn modelRow(m: *View, index: usize) Row {
    return m.rowData(index);
}
pub fn markerId(m: *const View, selected: bool) []const u8 {
    return if (selected) m.space.id("ai.model.selected") else m.space.id("ai.model.unselected");
}
pub fn chooseModel(m: *View, index: usize) void {
    const model = providerAt(m, index) orelse return;
    m.emit(.model, .{ .model = model.key });
}
pub fn contextWidth(m: *View) f32 {
    return m.modelContextWidth();
}
pub fn reasoningHint(on: bool) []const u8 {
    return if (on) "支持推理" else "不支持推理";
}
pub fn visionHint(on: bool) []const u8 {
    return if (on) "支持图片输入与识图" else "不支持识图，仅支持文本输入";
}
pub fn visionGlyph(on: bool) ui.SvgAsset {
    return ui.icons.get(if (on) "image" else "image-off").?;
}
pub fn glyphNamed(comptime name: []const u8) ui.SvgAsset {
    return ui.icons.get(name).?;
}
/// The name's first character (a brand mark without a bundled glyph).
pub fn initial(name: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, name, " \t\r\n");
    if (trimmed.len == 0) return "?";
    const len = std.unicode.utf8ByteSequenceLength(trimmed[0]) catch return "?";
    if (len > trimmed.len or !std.unicode.utf8ValidateSlice(trimmed[0..len])) return "?";
    return trimmed[0..len];
}
pub fn usageShown(m: *View) bool {
    return m.usage_shown.get();
}
pub fn usageCaption(m: *View) []const u8 {
    return m.usage_caption.get();
}
pub fn usageTotal(m: *View) []const u8 {
    return m.usage_total.get();
}
pub fn usageSegments(m: *View) []const W.ProgressSegment {
    return m.usage_segments.get();
}
pub fn usageParts(m: *View) []const UsageRow {
    return m.usage_rows.get();
}
pub fn usagePartName(row: UsageRow) []const u8 {
    return row.name.get();
}
pub fn usagePartValue(row: UsageRow) []const u8 {
    return row.value.get();
}
pub fn compactionRunning(m: *View) bool {
    return m.compaction_running.get();
}
pub fn compactionReason(m: *View) []const u8 {
    return m.compaction_reason.get();
}
pub fn canCompact(m: *View) bool {
    return m.can_compact.get();
}
pub fn startCompaction(m: *View) void {
    m.emit(.usage, .compact_context);
}
pub fn cancelCompaction(m: *View) void {
    m.emit(.usage, .cancel_compaction);
}

fn executionIconName(mode: ExecutionMode) []const u8 {
    return switch (mode) {
        .auto => "wand-sparkles",
        .ask => "message-circle-question",
        .isolated_exec => "package",
        .attached_pty => "square-terminal",
        .new_pty => "square-plus",
    };
}
/// Narrow rows show only this glyph for the execution mode, so each mode has its own.
pub fn executionIcon(mode: ExecutionMode) ui.SvgAsset {
    return ui.icons.get(executionIconName(mode)).?;
}
fn percentage(value: Usage) u64 {
    return @intFromFloat(@min(999, @floor(@as(f64, @floatFromInt(value.used_tokens)) * 100 / @as(f64, @floatFromInt(value.limit_tokens)))));
}
fn optionalKeyEql(first: ?ModelKey, second: ?ModelKey) bool {
    if (first) |key| return if (second) |other| key.eql(other) else false;
    return second == null;
}
fn controlsEql(first: Projection, second: Projection) bool {
    var one = first;
    var two = second;
    one.usage = null;
    two.usage = null;
    return projectionEql(one, two);
}
fn projectionEql(first: Projection, second: Projection) bool {
    return first.owner.eql(second.owner) and first.revision == second.revision and first.config_hash == second.config_hash and optionalKeyEql(first.current, second.current) and first.permission == second.permission and first.allow_auto_permission == second.allow_auto_permission and first.global_execution_mode == second.global_execution_mode and first.global_session_retention == second.global_session_retention and first.execution_mode_override == second.execution_mode_override and first.session_retention_override == second.session_retention_override and first.effort == second.effort and first.thinking == second.thinking and std.meta.eql(first.attachments, second.attachments) and first.editable == second.editable and first.inventory_authorized == second.inventory_authorized and std.meta.eql(first.inventory_conversation_id, second.inventory_conversation_id) and usageEql(first.usage, second.usage);
}
fn usageEql(first: ?Usage, second: ?Usage) bool {
    const one = first orelse return second == null;
    const two = second orelse return false;
    if (one.compaction_before != two.compaction_before or one.compaction_after != two.compaction_after or one.compaction != two.compaction or one.can_compact != two.can_compact or one.used_tokens != two.used_tokens or one.limit_tokens != two.limit_tokens or one.estimated != two.estimated or one.request_tokens != two.request_tokens or one.redacted != two.redacted or one.parts.len != two.parts.len) return false;
    for (one.parts, two.parts) |left, right| if (left.tokens != right.tokens or left.estimated != right.estimated or !std.mem.eql(u8, left.name, right.name)) return false;
    return true;
}

fn percentText(buffer: []u8, usage: Usage) ![]const u8 {
    if (usage.used_tokens > 0 and percentage(usage) == 0) return "<1%";
    return std.fmt.bufPrint(buffer, "{d}%", .{percentage(usage)});
}
const tokenText = @import("../../shared/model/ai_token_count.zig").format;

test "composer readiness matches an unauthenticated local gateway without enabling remote endpoints" {
    var models = [_]config.AiModel{.{ .id = "local-model", .context_window = 8192, .default = true }};
    var providers = [_]config.AiProvider{.{ .name = "local", .kind = .openai_compat, .enabled = true, .endpoint = "http://127.0.0.1:3425/v1/chat/completions", .model_count = 1, .models = &models }};
    var local = try Owned.init(std.testing.allocator, .{ .owner = .{ .tab = 1 }, .revision = 1, .providers = &providers });
    defer local.arena.deinit();
    try std.testing.expect(local.value.models[0].enabled);
    providers[0].endpoint = "https://example.test/v1/chat/completions";
    var remote = try Owned.init(std.testing.allocator, .{ .owner = .{ .tab = 1 }, .revision = 2, .providers = &providers });
    defer remote.arena.deinit();
    try std.testing.expect(!remote.value.models[0].enabled);
}
pub fn hasActions(m: *View) bool {
    return m.actions != null;
}
pub fn stopShown(m: *View) bool {
    return m.stop_shown.get();
}
pub fn sendShown(m: *View) bool {
    return m.send_shown.get();
}
pub fn sendDisabled(m: *View) bool {
    return m.send_disabled.get();
}
pub fn sendHint(m: *View) []const u8 {
    return m.send_hint.get();
}
pub fn sendLabel(m: *View) []const u8 {
    return m.send_label.get();
}
pub fn send(m: *View) void {
    if (m.actions) |a| a.send(a.context);
}
pub fn stop(m: *View) void {
    if (m.actions) |a| a.stop(a.context);
}
