//! Transfer views. The application owns IO and native windows. Closing
//! these views never changes jobs; snapshots and displayed strings are copied.
const std = @import("std");
const app_menu = @import("../../shell/mod.zig").app_menu;
const text_match = @import("../../../shared/base/text_match.zig");
const ui = @import("ui");
const overlay = @import("../../../shared/ui/overlay/overlay_host.zig");
const backend = @import("../../../transfer/manager.zig");
const identity = @import("../../../host/identity.zig");
const S = @import("transfer_styles.zig");
const panel_header = @import("../../../shared/ui/components/panel_header/panel_header.zig");
const shared_format = @import("../../../shared/base/format.zig");

pub const Action = enum { pause, resume_transfer, cancel, retry, promote, reveal, resolve_conflict };
pub const Callbacks = struct {
    context: *anyopaque,
    action: *const fn (*anyopaque, backend.JobId, Action) void,
    can_reveal: ?*const fn (*anyopaque, backend.JobId) bool = null,
    open_sftp: ?*const fn (*anyopaque) void = null,
    open_manager: ?*const fn (*anyopaque, Scope) void = null,
    scope_choices: ?*const fn (*anyopaque, std.mem.Allocator) anyerror![]const ScopeChoice = null,
    owner_label: ?*const fn (*anyopaque, backend.JobId) []const u8 = null,
    metadata: ?*const fn (*anyopaque, backend.JobId) []const u8 = null,
    owner: ?*const fn (*anyopaque, backend.JobId) ?identity.SessionHandle = null,
};
pub const Statistics = struct { window_chunks: u8, chunk_kb: u16, today_bytes: ?u64 = null };
pub const Presentation = enum { window, global_popover, session_popover, session_tray };
pub const Options = struct { presentation: Presentation = .window, fill_window: bool = false };
pub const Target = struct { job: backend.JobId, attempt: u32, owner: ?identity.SessionHandle };
pub const TaskAction = enum { pause, resume_transfer, cancel, retry, reveal, new_draft, resolve_conflict };
pub const WindowAction = enum { minimize, zoom, close };
pub const Phase = enum { queued, running, retry_wait, pausing, paused, conflict, verifying, succeeded, skipped, failed, checksum_failed, cancelling, cancelled, cleanup_unknown };
pub const Scope = union(enum) {
    all,
    session: identity.SessionHandle,
    sessions: struct { members: []const identity.SessionHandle, revision: u64 },
};
pub const ScopeChoice = struct { label: []const u8, scope: Scope };
pub const Task = struct {
    target: Target,
    direction: backend.Direction,
    name: []const u8,
    owner_label: []const u8 = "",
    local_path: []const u8 = "",
    remote_path: []const u8 = "",
    route: []const u8 = "",
    phase: Phase,
    done_bytes: u64 = 0,
    total_bytes: ?u64 = null,
    speed_bps: u64 = 0,
    reading_source: bool = false,
    status_detail: []const u8 = "",
    options: []const u8 = "",
    events: []const u8 = "",
    event_summary: []const u8 = "",
    can_resume: bool = true,
    can_reveal: bool = true,
};
pub const Snapshot = struct {
    revision: u64,
    rows: []const Task,
    scope: Scope = .all,
    choices: []const ScopeChoice = &.{},
    scope_label: []const u8 = "全部会话",
    notice: []const u8 = "",
};
pub const Hooks = struct {
    context: *anyopaque,
    action: ?*const fn (*anyopaque, Target, TaskAction) anyerror!void = null,
    /// Host confirms destructive actions against this frozen selection.
    batch: ?*const fn (*anyopaque, []const Target, TaskAction) anyerror!void = null,
    window: ?*const fn (*anyopaque, WindowAction) anyerror!void = null,
    scope_changed: ?*const fn (*anyopaque, Scope) void = null,
    new_transfer: ?*const fn (*anyopaque) void = null,
    open_manager: ?*const fn (*anyopaque, Scope) void = null,
    closed: ?*const fn (*anyopaque) void = null,
};
pub const Filter = enum { all, active, waiting, paused, failed, ended };
pub const Counts = struct { active: usize = 0, waiting: usize = 0, paused: usize = 0, failed: usize = 0, ended: usize = 0, speed_bps: u64 = 0 };

fn category(phase: Phase) Filter {
    return switch (phase) {
        .running, .verifying, .pausing, .cancelling, .cleanup_unknown => .active,
        .queued, .retry_wait, .conflict => .waiting,
        .paused => .paused,
        .failed, .checksum_failed => .failed,
        .succeeded, .skipped, .cancelled => .ended,
    };
}
pub fn phaseLabel(phase: Phase) []const u8 {
    return switch (phase) {
        .queued => "排队中",
        .running => "传输中",
        .retry_wait => "等待重试",
        .pausing => "停止请求中",
        .paused => "已暂停",
        .conflict => "等待处理同名文件",
        .verifying => "正在校验",
        .succeeded => "已完成",
        .skipped => "已跳过",
        .failed => "传输失败",
        .checksum_failed => "校验失败",
        .cancelling => "清理中",
        .cancelled => "已取消",
        .cleanup_unknown => "清理结果未知",
    };
}
pub fn failureLabel(failure: backend.Failure) []const u8 {
    return switch (failure) {
        .invalid_request => "请求参数不可用",
        .not_found => "文件不存在",
        .permission_denied => "没有文件访问权限",
        .conflict => "文件冲突或内容已变化",
        .connection => "连接不可用",
        .timeout => "连接超时",
        .checksum => "文件校验未通过",
        .protocol => "传输状态异常",
        .io => "文件读写失败",
    };
}
pub fn progressDetail(progress: backend.Progress) []const u8 {
    if (progress.startup_failure) |problem| return problem.message();
    if (progress.failure) |failure| return failureLabel(failure);
    if (progress.binding_wait and progress.state == .queued) return "正在建立传输连接";
    return "";
}
pub fn allows(phase: Phase, action: TaskAction) bool {
    return switch (action) {
        .pause => phase == .running or phase == .queued or phase == .retry_wait,
        .resume_transfer => phase == .paused,
        .retry => phase == .failed,
        .new_draft => phase == .cancelled or phase == .checksum_failed,
        .resolve_conflict => phase == .conflict,
        .reveal => phase == .succeeded,
        .cancel => phase == .running or phase == .queued or phase == .retry_wait or phase == .pausing or phase == .paused or phase == .conflict or phase == .verifying,
    };
}
pub fn belongs(scope: Scope, owner: ?identity.SessionHandle) bool {
    return switch (scope) {
        .all => true,
        .session => |handle| if (owner) |value| handle.eql(value) else false,
        .sessions => |group| blk: {
            const actual = owner orelse break :blk false;
            for (group.members) |member| if (member.eql(actual)) break :blk true;
            break :blk false;
        },
    };
}
fn same(a: Target, b: Target) bool {
    return std.meta.eql(a, b);
}
pub fn scopeEql(a: Scope, b: Scope) bool {
    if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
    return switch (a) {
        .all => true,
        .session => |owner| owner.eql(b.session),
        .sessions => |group| blk: {
            if (group.revision != b.sessions.revision or group.members.len != b.sessions.members.len) break :blk false;
            for (group.members, b.sessions.members) |left, right| if (!left.eql(right)) break :blk false;
            break :blk true;
        },
    };
}
fn copyScope(a: std.mem.Allocator, scope: Scope) !Scope {
    return switch (scope) {
        .sessions => |group| .{ .sessions = .{ .members = try a.dupe(identity.SessionHandle, group.members), .revision = group.revision } },
        else => scope,
    };
}
fn taskEql(a: Task, b: Task) bool {
    if (!same(a.target, b.target) or a.direction != b.direction or a.phase != b.phase or
        a.done_bytes != b.done_bytes or a.total_bytes != b.total_bytes or a.speed_bps != b.speed_bps or
        a.can_resume != b.can_resume or a.can_reveal != b.can_reveal or a.reading_source != b.reading_source) return false;
    inline for (.{ "name", "owner_label", "local_path", "remote_path", "route", "status_detail", "options", "events", "event_summary" }) |field| {
        if (!std.mem.eql(u8, @field(a, field), @field(b, field))) return false;
    }
    return true;
}
/// Revisions order snapshots; only displayed facts require new row ownership.
fn snapshotEql(a: Snapshot, b: Snapshot) bool {
    if (!scopeEql(a.scope, b.scope) or !std.mem.eql(u8, a.scope_label, b.scope_label) or
        !std.mem.eql(u8, a.notice, b.notice) or a.rows.len != b.rows.len or a.choices.len != b.choices.len) return false;
    for (a.rows, b.rows) |left, right| if (!taskEql(left, right)) return false;
    for (a.choices, b.choices) |left, right| {
        if (!scopeEql(left.scope, right.scope) or !std.mem.eql(u8, left.label, right.label)) return false;
    }
    return true;
}
// Progress is independent of row identity, controls and borrowed metadata.
fn progressOnly(a: Snapshot, b: Snapshot) bool {
    if (!scopeEql(a.scope, b.scope) or !std.mem.eql(u8, a.scope_label, b.scope_label) or
        !std.mem.eql(u8, a.notice, b.notice) or a.rows.len != b.rows.len or a.choices.len != b.choices.len) return false;
    for (a.choices, b.choices) |left, right| {
        if (!scopeEql(left.scope, right.scope) or !std.mem.eql(u8, left.label, right.label)) return false;
    }
    for (a.rows, b.rows) |left, right| {
        var normalized = left;
        normalized.done_bytes = right.done_bytes;
        normalized.total_bytes = right.total_bytes;
        normalized.speed_bps = right.speed_bps;
        normalized.reading_source = right.reading_source;
        if (!taskEql(normalized, right)) return false;
    }
    return true;
}

const Owned = struct {
    arena: std.heap.ArenaAllocator,
    value: Snapshot,
    fn init(allocator: std.mem.Allocator, value: Snapshot) !Owned {
        if (value.revision == 0) return error.InvalidRevision;
        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();
        const a = arena.allocator();
        var copy = value;
        copy.scope = try copyScope(a, value.scope);
        copy.scope_label = try a.dupe(u8, value.scope_label);
        copy.notice = try a.dupe(u8, value.notice);
        const rows = try a.dupe(Task, value.rows);
        for (rows, 0..) |*task, i| {
            if (task.target.job == 0) return error.InvalidJob;
            if (task.target.owner) |owner| if (@backingInt(owner.session_id) == 0 or owner.generation == 0) return error.InvalidOwner;
            for (rows[0..i]) |previous| if (previous.target.job == task.target.job) return error.DuplicateJob;
            inline for (.{ "name", "owner_label", "local_path", "remote_path", "route", "status_detail", "options", "events", "event_summary" }) |field| @field(task, field) = try a.dupe(u8, @field(task, field));
        }
        copy.rows = rows;
        const choices = try a.dupe(ScopeChoice, value.choices);
        for (choices) |*choice| {
            choice.label = try a.dupe(u8, choice.label);
            choice.scope = try copyScope(a, choice.scope);
        }
        copy.choices = choices;
        return .{ .arena = arena, .value = copy };
    }
};

pub fn mountProjection(cx: *ui.Cx, scope: *ui.Scope, options: Options, hooks: Hooks) !*Panel {
    return Panel.mountProjection(cx, scope, options, hooks);
}
pub fn mount(cx: *ui.Cx, scope: *ui.Scope, manager: *backend.Manager, callbacks: Callbacks) !*Panel {
    const panel = try mountProjection(cx, scope, .{ .presentation = .session_popover }, .{ .context = callbacks.context, .new_transfer = callbacks.open_sftp, .open_manager = callbacks.open_manager });
    panel.manager = manager;
    panel.callbacks = callbacks;
    return panel;
}
/// Host appends root below its dual-pane file workspace and sets selected_scope
/// to the original owner, refreshes, then calls show(). The panel never derives authority from focus.
pub fn mountSessionTray(cx: *ui.Cx, scope: *ui.Scope, manager: *backend.Manager, callbacks: Callbacks) !*Panel {
    const panel = try mountProjection(cx, scope, .{ .presentation = .session_tray }, .{ .context = callbacks.context, .open_manager = callbacks.open_manager });
    panel.root.meta.ownership.meta.test_id = "transfer.session.tray";
    panel.manager = manager;
    panel.callbacks = callbacks;
    return panel;
}
/// The titlebar entry uses the global layout inside the current window.
/// Its close button only hides this view; it owns no native window or jobs.
pub fn mountGlobalPopover(cx: *ui.Cx, scope: *ui.Scope, manager: *backend.Manager, callbacks: Callbacks) !*Panel {
    const panel = try mountProjection(cx, scope, .{ .presentation = .global_popover }, .{ .context = callbacks.context });
    panel.manager = manager;
    panel.callbacks = callbacks;
    return panel;
}
pub fn mountWindow(cx: *ui.Cx, scope: *ui.Scope, manager: *backend.Manager, callbacks: Callbacks) !*Panel {
    const panel = try mountProjection(cx, scope, .{ .presentation = .window, .fill_window = true }, .{ .context = callbacks.context });
    panel.manager = manager;
    panel.callbacks = callbacks;
    return panel;
}

const Control = struct {
    panel: *Panel,
    target: ?Target = null,
    action: ?TaskAction = null,
    window: ?WindowAction = null,
    choice: ?usize = null,
    menu_open: ?*ui.Signal(bool) = null,
    state_filter: ?Filter = null,
    copy_feedback: ?*@import("../../../shared/ui/components/copy_button/copy_button.zig").Button = null,
    copy_anchor: ?*ui.Node = null,
    event_anchor: ?*ui.Node = null,
    kind: enum { action, detail, events, copy_path, copy_local_path, window, choice, search, filter, new_transfer, batch, batch_pause, batch_resume, batch_cancel, all_tasks, scope_tasks, state_filter } = .action,
    fn run(self: *Control) void {
        const p = self.panel;
        const copy_rect = if (self.copy_anchor) |node| node.globalRect() else p.root.globalRect();
        if (self.menu_open) |open| open.set(false);
        p.in_action = true;
        defer p.in_action = false;
        switch (self.kind) {
            .state_filter => p.setFilter(self.state_filter.?),
            .action => p.perform(self.target.?, self.action.?) catch |err| p.fail(err),
            .events => {
                const task_ = p.task(self.target.?) orelse return;
                if (p.event_view == null) p.event_view = @import("transfer_events_view.zig").View.mount(p.cx, p.scope) catch |err| {
                    p.fail(err);
                    return;
                };
                p.event_view.?.show(task_.target.job, task_.events, self.event_anchor orelse return) catch |err| p.fail(err);
            },
            .copy_path, .copy_local_path => {
                const task_ = p.task(self.target.?) orelse return;
                const success = ui.platform_services.clipboardSetText(p.cx.system_sdk, if (self.kind == .copy_local_path) task_.local_path else task_.remote_path);
                if (self.copy_feedback) |button| button.report(success);
                if (!success) p.fail(error.ClipboardUnavailable) else if (self.menu_open != null or self.copy_feedback == null) @import("../../notifications/mod.zig").acknowledgeAt(p.cx, copy_rect, "路径已复制") catch {};
            },
            .detail => {
                if (p.task(self.target.?) == null) return;
                p.expanded = if (p.expanded != null and same(p.expanded.?, self.target.?) and self.kind == .detail) null else self.target;
                p.events_open = self.kind == .events;
                p.invalidate();
            },
            .window => {
                if (p.options.presentation == .window) {
                    if (p.hooks.window) |call| call(p.window_context orelse p.hooks.context, self.window.?) catch |err| {
                        p.fail(err);
                        return;
                    };
                }
                if (self.window == .close) {
                    p.hide();
                    if (p.hooks.closed) |call| call(p.hooks.context);
                }
            },
            .choice => {
                const source = p.source orelse return;
                if (self.choice.? >= source.value.choices.len) return;
                p.scope_choice = self.choice;
                p.selected_scope = source.value.choices[self.choice.?].scope;
                p.scopes_dirty = true;
                if (p.hooks.scope_changed) |call| call(p.hooks.context, p.selected_scope);
                p.invalidate();
            },
            .search => {
                p.search_visible = !p.search_visible;
                p.invalidate();
            },
            .filter => {
                p.filter_visible = !p.filter_visible;
                p.invalidate();
            },
            .new_transfer => if (p.hooks.new_transfer) |call| call(p.hooks.context),
            .all_tasks, .scope_tasks => {
                if (p.hooks.open_manager) |call| call(p.hooks.context, if (self.kind == .all_tasks) .all else p.selected_scope) else if (self.kind == .all_tasks) {
                    p.selected_scope = .all;
                    p.scope_choice = 0;
                    p.scopes_dirty = true;
                    p.invalidate();
                }
            },
            .batch => {
                p.scopes_dirty = true;
                p.batch_visible = !p.batch_visible;
                if (!p.batch_visible) p.selection.clearRetainingCapacity();
                p.invalidate();
            },
            .batch_pause => p.performBatch(.pause) catch |err| p.fail(err),
            .batch_resume => p.performBatch(.resume_transfer) catch |err| p.fail(err),
            .batch_cancel => p.performBatch(.cancel) catch |err| p.fail(err),
        }
    }
    fn checked(self: *Control, value: bool) void {
        const p = self.panel;
        const target = self.target.?;
        if (p.task(target) == null) return;
        if (value) {
            for (p.selection.items) |selected| if (same(selected, target)) return;
            p.selection.append(p.cx.allocator, target) catch |err| {
                p.fail(err);
                return;
            };
        } else {
            for (p.selection.items, 0..) |selected, i| if (same(selected, target)) {
                _ = p.selection.orderedRemove(i);
                break;
            };
        }
        p.batch_visible = true;
        p.invalidate();
    }
};

pub const Panel = struct {
    cx: *ui.Cx,
    scope: *ui.Scope,
    root: *ui.Node,
    options: Options,
    hooks: Hooks,
    manager: ?*backend.Manager = null,
    callbacks: ?Callbacks = null,
    source: ?Owned = null,
    pending_source: ?Owned = null,
    visible: std.ArrayList(usize) = .empty,
    selection: std.ArrayList(Target) = .empty,
    selected_scope: Scope = .all,
    scope_choice: ?usize = null,
    filter: Filter = .all,
    direction_filter: ?backend.Direction = null,
    tray_requested_show: bool = false,
    counts: Counts = .{},
    expanded: ?Target = null,
    tray_layout_width: f32 = 0,
    metadata_layout_width: f32 = 0,
    owner_column_width: f32 = 106,
    /// R3LCmV list header (window only) and its 连接 cell, resized with owner_column_width.
    table_header: ?*ui.Node = null,
    header_connection: ?*ui.Node = null,
    header_select: ?*ui.Node = null,
    events_open: bool = false,
    event_view: ?*@import("transfer_events_view.zig").View = null,
    batch_visible: bool = false,
    search_visible: bool = false,
    filter_visible: bool = false,
    dirty: bool = false,
    in_action: bool = false,
    anchor_id: ?u32 = null,
    /// title-click: the global (title bar) presentation is a native Popover under the 传输管理 button.
    popover: ?ui.widgets.popover.PopoverResult = null,
    /// Own zero-size box holding the manual popover's trigger wrapper (the popover's place in the tree).
    popover_anchor: ?*ui.Node = null,
    popover_open: ?*ui.Signal(bool) = null,
    pending_refresh: ?struct { now: u64, stats: Statistics } = null,
    revision: u64 = 0,
    window_disabled: *ui.Signal(bool),
    window_context: ?*anyopaque = null,
    paint_colors: S.theme.Colors,
    scopes_dirty: bool = false,
    head: *ui.Node,
    heading_title: *ui.Node,
    foot: *ui.Node,
    scope_row: *ui.Node,
    scope_scope: ?*ui.Scope = null,
    scope_picker: ?*ui.Node = null,
    v3_filters: ?*ui.Node = null,
    v3_filter_labels: [3]?*ui.Node = @splat(null),
    counts_row: *ui.Node,
    tools_row: *ui.Node,
    counts_labels: [5]*ui.Node,
    title_badge: *ui.Node,
    notice: *ui.Node,
    footer_label: *ui.Node,
    footer_rate: *ui.Node,
    /// 托盘（`session_tray`）的空状态标题节点；其他放置用原生 `W.Empty` + `empty_title`。
    empty: ?*ui.Node = null,
    empty_title: ?*ui.Signal([]const u8) = null,
    /// 头部计数“N 条”（共享 `PanelHeader`；托盘没有）。
    count_text: ?*ui.Signal([]const u8) = null,
    empty_container: *ui.Node = undefined,
    empty_description: ?*ui.Node = null,
    failure: *ui.Node,
    search: *ui.Signal([]const u8),
    search_node: *ui.Node,
    /// The native search Input's focus target.
    search_input: *ui.Node = undefined,
    /// Right gutter inside the task list (the native list's `padding`).
    list_gutter: f32 = 0,
    filters_node: *ui.Node,
    batch_row: *ui.Node,
    batch_label: *ui.Node,
    /// The native VirtualList's root (its public result node).
    list_container: *ui.Node,
    virtual: *ui.widgets.VirtualListState,
    /// The task rows currently mounted (see `MountedRow`).
    mounted_rows: ?*MountedRow = null,
    samples: [8]u64 = @splat(0),
    sample_count: usize = 0,
    last_sample_ms: ?u64 = null,

    pub fn mountProjection(cx: *ui.Cx, scope: *ui.Scope, options: Options, hooks: Hooks) !*Panel {
        const p = try cx.allocator.create(Panel);
        p.* = .{ .cx = cx, .scope = scope, .root = undefined, .options = options, .hooks = hooks, .window_disabled = try scope.createSignal(bool, hooks.window == null), .paint_colors = S.theme.current(), .head = undefined, .heading_title = undefined, .foot = undefined, .scope_row = undefined, .counts_row = undefined, .tools_row = undefined, .counts_labels = undefined, .title_badge = undefined, .notice = undefined, .footer_label = undefined, .footer_rate = undefined, .failure = undefined, .search = try scope.createText("", .{}), .search_node = undefined, .filters_node = undefined, .batch_row = undefined, .batch_label = undefined, .list_container = undefined, .virtual = undefined };
        try scope.onCleanup(Panel, p, cleanup);
        const tray = options.presentation == .session_tray;
        const window = !tray;
        const native_window = options.presentation == .window;
        const global_popover = options.presentation == .global_popover;
        p.root = try ui.box(cx, if (tray) S.sessionTray() else if (global_popover) S.popoverContent() else S.panel(true), .{});
        if (global_popover) {
            const open = try scope.createSignal(bool, false);
            const popup = try overlay.Popover(.panel, .{ .open = open, .trigger = .manual, .anchor = .{ .virtual = .{ .ctx = p, .getRect = popoverAnchor } }, .position = .bottom_end, .offset = .{ .static = 8 }, .viewport_padding = 12, .flip = true, .constrain_width_to_viewport = true, .close_on_outside_click = true, .consume_outside_click = false, .close_on_escape = true, .size_policy = .fit_content, .on_open_change = cx.on(Panel, p, popoverChanged) }).mount(scope, cx);
            // Manual popover: its (empty) trigger wrapper sits in an own zero-size box; nothing is written on the native parts.
            const anchor_box = try ui.box(cx, .{ .position = .absolute, .width = .{ .px = 0 }, .height = .{ .px = 0 } }, .{});
            try anchor_box.appendChild(cx.allocator, popup.wrapper);
            p.popover_anchor = anchor_box;
            try popup.content.appendChild(cx.allocator, p.root);
            p.popover = popup;
            p.popover_open = open;
        }
        @import("../../../shared/ui/components/floating_input/floating_input.zig").protect(cx, p.root);
        p.root.meta.ownership.meta.test_id = "transfer.manager";
        if (!native_window and !tray and !global_popover) p.root.setStyleInline(cx.allocator, .{ .position = .absolute, .inset = .{ .top = .{ .px = 46 }, .right = .{ .px = 14 } }, .z_index = 50 });
        p.root.setDisplay(.none);
        if (tray) {
            p.head = try ui.box(cx, S.row(28, 6), .{});
            p.head.meta.ownership.meta.test_id = "transfer.header";
            try p.root.appendChild(cx.allocator, p.head);
            const heading_title = try p.label(p.head, "当前会话传输", 12, 700, false);
            p.heading_title = heading_title;
            heading_title.meta.ownership.meta.test_id = "transfer.header.title";
            heading_title.setStyleInline(cx.allocator, S.flexibleLabel());
            p.title_badge = try p.label(p.head, "", 10.5, 400, true);
            p.title_badge.setDisplay(.none);
            _ = try p.button(p.head, scope, "管理任务", "transfer.batch", "list-checks", .{ .panel = p, .kind = .batch }, false, 24);
        } else {
            // panel-heads：共享头部（图标 · “传输任务” · “N 条” · 动作区：范围 · 窗口按钮 · 统一关闭按钮）。
            p.count_text = try scope.createText("", .{});
            const close = try scope.createState(Control, .{ .panel = p, .kind = .window, .window = .close });
            var header_slots: panel_header.Slots = .{};
            p.head = try panel_header.mountHeader(scope, cx, &header_slots, .{ .icon = ui.icons.arrow_down_up, .title = "传输任务", .subtitle = p.count_text, .inset = .flush, .header_test_id = "transfer.header", .title_test_id = "transfer.header.title", .subtitle_test_id = "transfer.header.count", .close_label = if (native_window) "收起传输" else "关闭传输", .close_test_id = "transfer.window.close", .close_tooltip_test_id = "transfer.window.close.tooltip", .on_close = cx.on(Control, close, Control.run) });
            try p.root.appendChild(cx.allocator, p.head);
            p.heading_title = p.head;
            try p.root.insertChildBefore(cx.allocator, try ui.boxStyled(cx, S.topFade, .{}), p.head);
            // The popovers (title bar, session) are anchored and cannot be dragged: no grip there.
            if (native_window) try p.root.appendChild(cx.allocator, try ui.boxStyled(cx, S.grip, .{}));
            const actions = header_slots.actions.?;
            try actions.appendChild(cx.allocator, try ui.iconTint(cx, ui.icons.lock_keyhole, S.theme.current().fg_2, S.icon(12)));
            p.title_badge = try p.label(actions, "", 10.5, 400, true);
            p.title_badge.setStyleInline(cx.allocator, .{ .height = .{ .px = 22 }, .padding = .{ .left = 8, .right = 8 }, .background = S.theme.current().surface_2, .border = .{ .radius = 6 } });
            if (options.presentation != .session_popover) {
                p.scope_picker = try ui.box(cx, .{ .direction = .row, .align_items = .center, .min_width = 0 }, .{});
                try actions.appendChild(cx.allocator, p.scope_picker.?);
                p.title_badge.setDisplay(.none);
            }
            if (native_window) {
                _ = try p.button(actions, scope, "最小化传输窗口", "transfer.window.minimize", "minus", .{ .panel = p, .kind = .window, .window = .minimize }, p.window_disabled, 22);
                _ = try p.button(actions, scope, "缩放传输窗口", "transfer.window.zoom", "maximize-2", .{ .panel = p, .kind = .window, .window = .zoom }, p.window_disabled, 22);
            }
        }
        try p.root.appendChild(cx.allocator, try ui.box(cx, S.gap(if (tray) 6 else 9), .{}));
        p.scope_row = try ui.box(cx, S.row(@import("../../workspace/view/workspace_tab_styles.zig").height, 4), .{});
        try p.root.appendChild(cx.allocator, p.scope_row);
        p.counts_row = try ui.box(cx, S.row(28, 6), .{});
        p.counts_row.meta.ownership.meta.test_id = "transfer.states.toolbar";
        try p.root.appendChild(cx.allocator, p.counts_row);
        for (&p.counts_labels, 0..) |*label_, i| {
            const box = try ui.box(cx, S.badge(if (i == 0) 64 else 54, countColor(i)), .{});
            label_.* = try p.label(box, "", 10, 500, true);
            try p.counts_row.appendChild(cx.allocator, box);
        }
        try p.counts_row.appendChild(cx.allocator, try ui.spacer(cx));
        p.tools_row = try ui.box(cx, .{ .height = .{ .px = 28 }, .direction = .row, .align_items = .center, .gap = 6, .flex_shrink = 0 }, .{});
        try p.counts_row.appendChild(cx.allocator, p.tools_row);
        // Native Input with its default look; the own box around it takes the row (shown / hidden by the search toggle).
        const search_input = try ui.widgets.Input(.{ .value = p.search, .placeholder = "搜索文件名、路径或会话", .on_change = cx.on(Panel, p, searchChanged) }).mountResult(scope, cx);
        p.search_input = search_input.input_container;
        p.search_node = try ui.box(cx, .{ .width = .fill(), .height = .{ .fit = .{} }, .direction = .column, .flex_shrink = 0 }, .{});
        p.search_node.meta.ownership.meta.test_id = "transfer.search";
        try p.search_node.appendChild(cx.allocator, search_input.node);
        try p.root.appendChild(cx.allocator, p.search_node);
        const filter_result = try ui.widgets.Select(.{ .panel_width = .trigger, .options = &[_]ui.widgets.SelectOption{
            .{ .value = "all", .label = "全部状态" },
            .{ .value = "active", .label = "进行中" },
            .{ .value = "waiting", .label = "等待" },
            .{ .value = "paused", .label = "暂停" },
            .{ .value = "failed", .label = "失败" },
            .{ .value = "ended", .label = "结束" },
        }, .placeholder = "全部状态", .width = 120, .on_change = cx.on(Panel, p, filterChanged) }).mount(scope, cx);
        // Native Select with its default look; the own box around it is what the filter toggle shows / hides.
        p.filters_node = try ui.box(cx, .{ .width = .fill(), .height = .{ .fit = .{} }, .direction = .column, .flex_shrink = 0 }, .{});
        p.filters_node.meta.ownership.meta.test_id = "transfer.filter";
        try p.filters_node.appendChild(cx.allocator, filter_result.wrapper);
        try p.root.appendChild(cx.allocator, p.filters_node);
        const notice_row = try ui.box(cx, S.row(30, 6), .{});
        notice_row.meta.ownership.meta.test_id = "transfer.notice";
        notice_row.setDisplay(.none);
        try notice_row.appendChild(cx.allocator, try ui.iconTint(cx, ui.icons.lock_keyhole, S.theme.current().fg_2, S.icon(14)));
        p.notice = try p.label(notice_row, "", 10.5, 400, true);
        p.notice.setStyleInline(cx.allocator, S.flexibleLabel());
        try p.root.appendChild(cx.allocator, notice_row);
        if (window) {
            p.scope_row.setStyleInline(cx.allocator, .{ .margin = .{ .bottom = 6 } });
            p.counts_row.setStyleInline(cx.allocator, .{ .margin = .{ .bottom = 6 } });
            notice_row.setStyleInline(cx.allocator, .{ .margin = .{ .bottom = 6 } });
        } else {
            p.scope_row.setDisplay(.none);
            p.counts_row.setDisplay(.none);
            notice_row.setDisplay(.none);
        }
        p.search_node.setDisplay(.none);
        p.filters_node.setDisplay(.none);
        p.failure = try p.label(p.root, "", 10.5, 400, true);
        p.failure.setStyleInline(cx.allocator, S.errorLine());
        p.failure.setDisplay(.none);
        const empty_state = try ui.box(cx, S.emptyState(), .{});
        p.empty_container = empty_state;
        empty_state.meta.ownership.meta.test_id = "transfer.empty";
        try p.root.appendChild(cx.allocator, empty_state);
        if (!tray) {
            // panel-heads：原生 `W.Empty`（图标 · 标题 · 说明）。
            p.empty_title = try scope.createText("", .{});
            const description: []const u8 = if (options.presentation == .global_popover or window) "上传、下载与复制的文件会在这里显示进度；可从文件工作区或 @up / @dl 开始。" else "这个会话里上传、下载的文件会在这里显示进度。";
            try empty_state.appendChild(cx.allocator, try ui.view.render(scope, cx, ui.widgets.Empty(.{ .icon = ui.icons.arrow_down_up, .title = p.empty_title.?, .description = description, .title_test_id = "transfer.empty.title", .description_test_id = "transfer.empty.description" })));
        } else {
            const icon_ = try ui.iconTint(cx, ui.icons.arrow_down_up, S.theme.current().fg_2, S.icon(24));
            icon_.meta.ownership.meta.test_id = "transfer.empty.icon";
            try empty_state.appendChild(cx.allocator, icon_);
            const text_column = try ui.box(cx, .{ .width = .fill(), .flex = 1, .min_width = 0, .direction = .column, .gap = 3 }, .{});
            text_column.meta.ownership.meta.test_id = "transfer.empty.text";
            try empty_state.appendChild(cx.allocator, text_column);
            p.empty = try p.label(text_column, "", 12, 600, false);
            p.empty.?.setStyleInline(cx.allocator, .{ .width = .fill(), .height = .{ .px = 18 }, .flex_shrink = 0 });
            if (p.empty.?.getText()) |old| {
                var props = old;
                props.line_height = 1.5;
                p.empty.?.setText(props);
            }
            const description = try p.label(text_column, if (options.presentation == .global_popover or window) "从文件工作区或 @up / @dl 开始。" else "选择文件后上传或下载。", 11, 400, true);
            description.meta.ownership.meta.test_id = "transfer.empty.description";
            description.setStyleInline(cx.allocator, .{ .width = .fill(), .height = .{ .px = 16 }, .flex_shrink = 0 });
            if (description.getText()) |old| {
                var props = old;
                props.line_height = 16.0 / 11.0;
                description.setText(props);
            }
            p.empty_description = description;
        }
        if (tray) p.empty.?.meta.ownership.meta.test_id = "transfer.empty.title";
        empty_state.setDisplay(.none);
        p.batch_row = try ui.box(cx, S.row(30, 6), .{});
        p.batch_label = try p.label(p.batch_row, "", 11, 400, true);
        p.batch_label.setStyleInline(cx.allocator, S.flexibleLabel());
        _ = try p.button(p.batch_row, scope, "暂停所选任务", "transfer.batch.pause", "pause", .{ .panel = p, .kind = .batch_pause }, hooks.batch == null, 24);
        _ = try p.button(p.batch_row, scope, "恢复所选任务", "transfer.batch.resume", "play", .{ .panel = p, .kind = .batch_resume }, hooks.batch == null, 24);
        _ = try p.button(p.batch_row, scope, "取消所选任务", "transfer.batch.cancel", "x", .{ .panel = p, .kind = .batch_cancel }, hooks.batch == null, 24);
        p.batch_row.setDisplay(.none);
        try p.root.appendChild(cx.allocator, p.batch_row);
        if (native_window) {
            // R3LCmV Header: 文件 · 连接 · 进度 · 速度 · (操作), 26pt, bottom hairline.
            const header = try ui.boxStyled(cx, S.tableHeader, .{});
            header.meta.ownership.meta.test_id = "transfer.table.header";
            p.table_header = header;
            // The list content reserves 14pt for its scrollbar; keep the columns aligned.
            header.setStyleInline(cx.allocator, .{ .padding = .{ .left = 10, .right = 24 } });
            const select_slot = try ui.box(cx, .{ .width = .{ .px = 16 }, .height = .{ .px = 16 }, .flex_shrink = 0 }, .{});
            select_slot.setDisplay(.none);
            p.header_select = select_slot;
            try header.appendChild(cx.allocator, select_slot);
            const cells = [_]struct { label: []const u8, width: ?f32 }{ .{ .label = "文件", .width = null }, .{ .label = "连接", .width = S.connection_column }, .{ .label = "进度", .width = S.progress_column }, .{ .label = "速度", .width = S.speed_column } };
            for (cells, 0..) |cell, i| {
                const box = try ui.box(cx, if (cell.width) |w| S.cellColumn(w, 0) else S.fileCell(), .{});
                if (cell.label.len > 0) try box.appendChild(cx.allocator, try ui.textStyled(cx, S.headerLabel, cell.label));
                if (i == 1) p.header_connection = box;
                try header.appendChild(cx.allocator, box);
            }
            try header.appendChild(cx.allocator, try ui.boxStyled(cx, S.actionsHeader, .{}));
            try p.root.appendChild(cx.allocator, header);
        }
        const list = try ui.widgets.VirtualList(.{ .item_count = @as(usize, 0), .item_height = if (native_window) S.table_row_height else S.popover_row_height, .padding = .{ .right = if (tray) 0 else S.list_gutter }, .overscan = 1, .item_height_fn = itemHeight, .item_height_context = p, .item_label_fn = itemLabel, .item_label_context = p }).mountScoped(scope, cx, p, renderItem);
        p.virtual = list.state;
        p.list_container = list.container;
        p.list_gutter = if (tray) 0 else S.list_gutter;
        // The native list fills this own box, which takes the panel's remaining height.
        const list_box = try ui.box(cx, S.viewport(), .{});
        try list_box.appendChild(cx.allocator, list.container);
        try p.root.appendChild(cx.allocator, list_box);
        try p.root.appendChild(cx.allocator, try ui.box(cx, S.gap(if (tray) 0 else 6), .{}));
        p.foot = try ui.box(cx, if (native_window or window) S.row(32, 6) else S.v3Footer(), .{});
        try p.root.appendChild(cx.allocator, p.foot);
        p.footer_label = try p.label(p.foot, "", 10.5, 400, true);
        p.footer_label.setStyleInline(cx.allocator, .{ .width = .{ .px = 210 }, .min_width = 0, .overflow = .hidden, .flex_shrink = 1 });
        p.footer_rate = try p.label(p.foot, "", 10.5, 400, true);
        p.footer_rate.setStyleInline(cx.allocator, S.flexibleLabel());
        try cx.addAfterLayoutHook(p, afterLayout);
        return p;
    }

    fn cleanup(self: *Panel) void {
        self.cx.removeAfterLayoutHook(self);
        if (self.source) |*source| source.arena.deinit();
        if (self.pending_source) |*source| source.arena.deinit();
        self.visible.deinit(self.cx.allocator);
        self.selection.deinit(self.cx.allocator);
        self.cx.allocator.destroy(self);
    }
    fn label(self: *Panel, parent: *ui.Node, value: []const u8, size: f32, weight: u16, secondary: bool) !*ui.Node {
        const node = try ui.text(self.cx, "", S.text(size, weight, secondary));
        try node.setTextContent(self.cx.allocator, value);
        try parent.appendChild(self.cx.allocator, node);
        return node;
    }
    fn button(self: *Panel, parent: *ui.Node, scope: *ui.Scope, label_: []const u8, test_id: []const u8, icon: []const u8, control: Control, disabled: anytype, size: f32) !*ui.Node {
        const state = try scope.createState(Control, control);
        const owned_label = try scope.createText(label_, .{});
        const node = try ui.widgets.Button(.{ .variant = .ghost, .icon_only = true, .icon_asset = ui.icons.get(icon), .size = if (size <= 24) S.compact_button_size else ui.widgets.button.ButtonSize.md, .a11y_label = owned_label, .disabled = disabled, .on_click = self.cx.on(Control, state, Control.run) }).mount(scope, self.cx);
        node.meta.ownership.meta.test_id = test_id;
        if (control.kind == .copy_path or control.kind == .copy_local_path) {
            state.copy_feedback = try @import("../../../shared/ui/components/copy_button/copy_button.zig").Button.attach(self.cx, scope, node);
            state.copy_anchor = node;
        }
        if (control.kind == .events) {
            state.event_anchor = node;
            if (self.event_view) |events| events.reanchor(control.target.?.job, node);
        }
        try parent.appendChild(self.cx.allocator, node);
        return node;
    }
    pub fn update(self: *Panel, snapshot: Snapshot) !void {
        if (self.pending_source) |pending| if (snapshot.revision <= pending.value.revision) return;
        if (self.source) |source| if (snapshot.revision <= source.value.revision) return;
        if (self.pending_source) |*pending| {
            if (snapshotEql(pending.value, snapshot)) {
                pending.value.revision = snapshot.revision;
                if (!self.in_action) try self.flush();
                return;
            }
        } else if (self.source) |*source| {
            if (snapshotEql(source.value, snapshot)) {
                source.value.revision = snapshot.revision;
                self.revision = snapshot.revision;
                if (self.dirty and !self.in_action) try self.flush();
                return;
            }
        }
        if (self.pending_source == null and !self.dirty and !self.in_action) {
            if (self.source) |*source| if (progressOnly(source.value, snapshot)) {
                // Keep the existing arena: retained tooltips and a11y labels borrow
                // its unchanged strings. Only copy numeric progress facts.
                source.value.revision = snapshot.revision;
                self.revision = snapshot.revision;
                self.counts.speed_bps = 0;
                for (snapshot.rows) |row| if (belongs(self.selected_scope, row.target.owner) and
                    (self.direction_filter == null or self.direction_filter.? == row.direction) and row.phase == .running)
                {
                    self.counts.speed_bps +|= row.speed_bps;
                };
                var mounted = self.mounted_rows;
                while (mounted) |row| : (mounted = row.next) {
                    if (row.index >= self.visible.items.len) continue;
                    const row_index = self.visible.items[row.index];
                    if (!taskEql(source.value.rows[row_index], snapshot.rows[row_index]))
                        try self.patchProgress(row, snapshot.rows[row_index]);
                }
                for (@constCast(source.value.rows), snapshot.rows) |*row, next| {
                    row.done_bytes = next.done_bytes;
                    row.total_bytes = next.total_bytes;
                    row.speed_bps = next.speed_bps;
                    row.reading_source = next.reading_source;
                }
                var buffer: [40]u8 = undefined;
                try self.format(self.footer_rate, "{d} 进行中 · {s} · {d} 等待", .{ self.counts.active, shared_format.liveRate(&buffer, self.counts.speed_bps), self.counts.waiting });
                return;
            };
        }
        const owned = try Owned.init(self.cx.allocator, snapshot);
        if (self.pending_source) |*old| old.arena.deinit();
        self.pending_source = owned;
        self.invalidate();
        if (!self.in_action) try self.flush();
    }
    pub fn flush(self: *Panel) !void {
        if (self.in_action) return;
        var retired_source: ?Owned = null;
        var rows_reset = false;
        defer if (retired_source) |*old| {
            // Allocation failures must not free strings still borrowed by old
            // row scopes. The normal path clears the pool once at its new count.
            if (!rows_reset) ui.widgets.virtual_list.updateItemCount(self.virtual, 0);
            old.arena.deinit();
        };
        if (self.pending_source) |next| {
            const same_scope = scopeEql(self.selected_scope, next.value.scope);
            retired_source = self.source;
            self.source = next;
            self.pending_source = null;
            self.selected_scope = next.value.scope;
            self.scope_choice = null;
            self.revision = next.value.revision;
            // A different scope starts at the top (the list's public programmatic scroll).
            if (!same_scope) ui.widgets.virtual_list.scrollToIndex(self.virtual, 0);
            try self.renderScopes();
        }
        if (!self.dirty) return;
        self.dirty = false;
        const source = self.source orelse return;
        if (self.scopes_dirty) {
            self.scopes_dirty = false;
            try self.renderScopes();
        }
        self.visible.clearRetainingCapacity();
        self.counts = .{};
        const query = self.search.peek();
        for (source.value.rows, 0..) |task_, i| {
            if (!belongs(self.selected_scope, task_.target.owner)) continue;
            if (self.direction_filter) |direction| if (task_.direction != direction) continue;
            const kind = category(task_.phase);
            switch (kind) {
                .active => self.counts.active += 1,
                .waiting => self.counts.waiting += 1,
                .paused => self.counts.paused += 1,
                .failed => self.counts.failed += 1,
                .ended => self.counts.ended += 1,
                .all => unreachable,
            }
            if (task_.phase == .running) self.counts.speed_bps +|= task_.speed_bps;
            if (self.filter != .all and self.filter != kind) continue;
            if (!text_match.matches(query, &.{ task_.name, task_.local_path, task_.remote_path, task_.owner_label })) continue;
            try self.visible.append(self.cx.allocator, i);
        }
        var selected_index: usize = 0;
        while (selected_index < self.selection.items.len) {
            var retained = false;
            for (self.visible.items) |i| if (same(source.value.rows[i].target, self.selection.items[selected_index])) {
                retained = true;
                break;
            };
            if (retained) selected_index += 1 else _ = self.selection.orderedRemove(selected_index);
        }
        if (self.options.presentation != .session_popover and self.options.presentation != .session_tray) {
            const table = self.options.presentation == .window;
            // R3LCmV 连接 column starts at 148 (12pt owner); the global popover
            // keeps its owner (11pt) at the end of the Gq5xg name line.
            const owner_font: f32 = if (table) 12 else 11;
            var preferred: f32 = if (table) S.connection_column else 106;
            for (self.visible.items) |index| preferred = @max(preferred, self.cx.text.measureTextWidth(source.value.rows[index].owner_label, owner_font, 400, false) + 2);
            // Keep a useful filename slot; long filenames ellipsize within it.
            const filename_width: f32 = 160;
            const available = if (self.metadata_layout_width > 0) self.metadata_layout_width else 812;
            // Row padding, 24pt icon + 10 gap, the fixed columns with their 12pt
            // gaps (table) or the 10pt row gaps and name/owner gap (popover).
            const actions_width = S.actionsWidth(self.cx.tokens);
            const fixed: f32 = if (table) 20 + 34 + 4 * 12 + S.progress_column + S.speed_column + actions_width else 16 + 34 + 10 + actions_width + 6;
            const reserved: f32 = fixed + (if (self.batch_visible) @as(f32, if (table) 28 else 26) else 0);
            const budget = @max(0, available - reserved);
            const filename_reserved = @min(filename_width, @max(0, budget - 48));
            self.owner_column_width = @min(preferred, @max(0, budget - filename_reserved));
            if (self.header_connection) |cell| cell.setStyleInline(self.cx.allocator, .{ .width = .{ .px = self.owner_column_width } });
            if (self.header_select) |slot| slot.setDisplay(if (self.batch_visible) .flex else .none);
        }
        if (self.expanded) |target| if (self.task(target) == null) {
            self.expanded = null;
            self.events_open = false;
        };

        const scope_label = if (self.scope_choice) |i| source.value.choices[i].label else source.value.scope_label;
        if (self.selected_scope == .session) {
            try self.format(self.title_badge, "会话 #{d}", .{@backingInt(self.selected_scope.session.session_id)});
        } else try self.title_badge.setTextContent(self.cx.allocator, if (self.selected_scope == .all) "全局" else scope_label);
        try self.notice.setTextContent(self.cx.allocator, source.value.notice);
        self.notice.parent.?.setDisplay(if (self.options.presentation != .session_popover and source.value.notice.len != 0) .flex else .none);
        const values = [_]usize{ self.counts.active, self.counts.waiting, self.counts.paused, self.counts.failed, self.counts.ended };
        for ([_][]const u8{ "进行中", "等待", "暂停", "失败", "结束" }, values, self.counts_labels, 0..) |name, count, node, i| {
            try self.format(node, "{s} {d}", .{ name, count });
            node.setTextColor(if (count == 0) S.theme.current().fg_3 else countColor(i));
            node.parent.?.setStyleInline(self.cx.allocator, S.badge(if (i == 0) 64 else 54, if (count == 0) S.theme.current().fg_3 else countColor(i)));
        }
        const has_tasks = self.counts.active + self.counts.waiting + self.counts.paused + self.counts.failed + self.counts.ended != 0;
        self.counts_row.setDisplay(if (self.options.presentation != .session_tray and has_tasks) .flex else .none);
        self.footer_rate.setDisplay(if (has_tasks) .flex else .none);
        try self.footer_label.setTextContent(self.cx.allocator, scope_label);
        self.footer_label.setDisplay(.none);
        self.foot.setDisplay(if (has_tasks and self.options.presentation == .window) .flex else .none);
        var speed_buffer: [40]u8 = undefined;
        try self.format(self.footer_rate, "{d} 进行中 · {s} · {d} 等待", .{ self.counts.active, shared_format.liveRate(&speed_buffer, self.counts.speed_bps), self.counts.waiting });
        self.search_node.setDisplay(if (self.search_visible) .flex else .none);
        self.filters_node.setDisplay(if (self.filter_visible) .flex else .none);
        self.batch_row.setDisplay(if (self.batch_visible) .flex else .none);
        if (self.options.presentation == .session_tray) {
            self.scope_row.setDisplay(.none);
            self.counts_row.setDisplay(.none);
            self.foot.setDisplay(.none);
            self.search_node.setDisplay(.none);
            self.filters_node.setDisplay(.none);
            self.notice.parent.?.setDisplay(.none);
        }
        if (self.options.presentation == .session_tray) {
            try self.heading_title.setTextContent(self.cx.allocator, if (self.direction_filter) |direction| (if (direction == .upload) "上传传输" else "下载传输") else "当前会话传输");
            self.root.setDisplay(if (self.tray_requested_show and self.visible.items.len > 0) .flex else .none);
        }
        try self.format(self.batch_label, "已选择 {d} 项", .{self.selection.items.len});
        self.empty_container.setDisplay(if (self.visible.items.len == 0) .flex else .none);
        self.list_container.setDisplay(if (self.visible.items.len == 0) .none else .flex);
        const empty_text: []const u8 = if (self.options.presentation == .global_popover) "没有传输任务" else if (self.options.presentation == .session_popover or self.options.presentation == .session_tray) "当前没有传输任务" else if (self.filter != .all or query.len > 0) "没有符合筛选的任务" else switch (self.selected_scope) {
            .all => "暂无传输任务",
            .session => "本会话暂无传输任务",
            .sessions => "所选组暂无传输任务",
        };
        if (self.empty) |node| try node.setTextContent(self.cx.allocator, empty_text);
        if (self.empty_title) |signal| if (!std.mem.eql(u8, signal.peek(), empty_text)) signal.set(empty_text);
        if (self.count_text) |signal| {
            var count_buffer: [32]u8 = undefined;
            const count = shared_format.count(&count_buffer, self.visible.items.len);
            if (!std.mem.eql(u8, signal.peek(), count)) signal.set(count);
        }
        ui.widgets.virtual_list.updateItemCount(self.virtual, self.visible.items.len);
        rows_reset = true;
        ui.widgets.virtual_list.invalidateHeights(self.virtual);
        ui.widgets.virtual_list.refreshRange(self.virtual, 0, self.visible.items.len);
        // Host refreshes run after before_render. Rebind now so this submitted
        // frame cannot paint the cleared pool while waiting for the next tick.
        self.virtual.updateVisibleItems();
        self.root.markLayoutDirty();
        self.cx.requestRedraw();
    }
    fn renderScopes(self: *Panel) !void {
        if (self.scope_scope) |scope| scope.dispose();
        self.scope_scope = null;
        for ([_]*ui.Node{ self.scope_row, self.tools_row }) |parent| {
            while (parent.children.items.len > 0) {
                const child = parent.children.items[parent.children.items.len - 1];
                self.cx.detachChild(parent, child);
                self.cx.destroyDetached(child);
            }
        }
        self.scope_row.setDisplay(.none);
        const scope = try self.scope.childScope();
        self.scope_scope = scope;
        const source = self.source orelse return;
        if (self.scope_picker) |picker| {
            while (picker.children.items.len > 0) {
                const child = picker.children.items[picker.children.items.len - 1];
                self.cx.detachChild(picker, child);
                self.cx.destroyDetached(child);
            }
            var choices: std.ArrayList(ui.widgets.SelectOption) = .empty;
            defer choices.deinit(self.cx.allocator);
            var selected: ?[]const u8 = null;
            var width: f32 = 64;
            var menu_width: f32 = 160;
            for (source.value.choices, 0..) |choice, i| {
                if (choice.scope == .sessions) continue;
                const storage = try scope.createState(struct { value: [20]u8 = undefined, id: [64]u8 = undefined }, .{});
                const value = try std.fmt.bufPrint(&storage.value, "{d}", .{i});
                const choice_label = if (choice.scope == .all) "全局" else choice.label;
                menu_width = @max(menu_width, self.cx.text.measureTextWidth(choice_label, 11, 400, false) + 56);
                try choices.append(self.cx.allocator, .{ .value = value, .label = choice_label, .test_id = try std.fmt.bufPrint(&storage.id, "transfer.scope.option.{d}", .{i}) });
                if (scopeEql(choice.scope, self.selected_scope)) {
                    selected = value;
                    width = std.math.clamp(self.cx.text.measureTextWidth(choice_label, 10, 400, false) + 38, 64, 260);
                }
            }
            const select = try ui.widgets.Select(.{ .options = choices.items, .value = selected, .placeholder = "全局", .size = .xs, .width = width, .panel_width = .{ .px = @min(menu_width, 320) }, .panel_position = .bottom_start, .on_change = self.cx.on(Panel, self, scopeChanged) }).mount(scope, self.cx);
            // Native Select (xs) with its default trigger, menu and option rows.
            select.panel.meta.ownership.meta.test_id = "transfer.scope.menu";
            select.trigger.meta.ownership.meta.test_id = "transfer.scope.select";
            if (select.trigger.behavior.interaction.a11y) |*a11y| a11y.label = "选择传输会话";
            try picker.appendChild(self.cx.allocator, select.wrapper);
        }
        const manage_label = if (self.batch_visible) "完成管理" else "管理任务";
        const manage = try self.button(self.tools_row, scope, manage_label, "transfer.batch", if (self.batch_visible) "check" else "list-checks", .{ .panel = self, .kind = .batch }, false, 28);
        if (manage.behavior.interaction.a11y) |*a11y| a11y.pressed = self.batch_visible;
        self.tools_row.removeChild(manage);
        const manage_hint = try @import("../../../shared/ui/components/control_hint/control_hint.zig").mount(self.cx, scope, manage, manage_label, .{ .id = "transfer.batch.tooltip", .layout = .{ .flex_shrink = 0 } });
        try self.tools_row.appendChild(self.cx.allocator, manage_hint.wrapper);
        _ = try self.button(self.tools_row, scope, "搜索任务", "transfer.search.toggle", "search", .{ .panel = self, .kind = .search }, false, 28);
        _ = try self.button(self.tools_row, scope, "筛选任务状态", "transfer.filter.toggle", "filter", .{ .panel = self, .kind = .filter }, false, 28);
    }
    /// `list_scope` is the list's own scope (it owns the pool slots): a row mounted under it is
    /// released with its slot on recycle and with the list (the `renderInto` contract).
    fn renderItem(node: *ui.Node, index: usize, list_scope: *ui.Scope, cx: *ui.Cx, raw: ?*anyopaque) void {
        const self: *Panel = @ptrCast(@alignCast(raw.?));
        ui.view.renderInto(list_scope, cx, node, renderTask, self, .{ index, node }, "transfer task") catch {
            _ = ui.widgets.virtual_list.markPoolNodeRenderIncomplete(node);
        };
    }
    /// A mounted task row's own handles: the nodes a progress update rewrites and the slot it
    /// occupies. Created with the row (in the row's scope), linked into the panel while mounted,
    /// so progress updates and `presents` address rows directly — no search by test id, no reading
    /// of the list's pool.
    const MountedRow = struct {
        panel: *Panel,
        /// Index into `Panel.visible`.
        index: usize,
        slot: *ui.Node,
        bytes: *ui.Node,
        /// null on an error row (its rate text is the error).
        rate: ?*ui.Node,
        remaining: ?*ui.Node,
        status: *ui.Node,
        fill: *ui.Node,
        next: ?*MountedRow = null,

        fn unlink(self: *MountedRow) void {
            var link: *?*MountedRow = &self.panel.mounted_rows;
            while (link.*) |current| : (link = &current.next) if (current == self) {
                link.* = self.next;
                return;
            };
        }
    };
    fn renderTask(self: *Panel, index: usize, pool_slot: *ui.Node, scope: *ui.Scope, cx: *ui.Cx) !*ui.Node {
        const task_ = self.source.?.value.rows[self.visible.items[index]];

        // Island B v3: the transfer window (R3LCmV) lays tasks out as 48pt table
        // rows (文件 · 连接 · 进度 · 速度 · 操作); popovers and the SFTP tray use
        // the Gq5xg row (24pt file icon, name over status, inline 4pt progress).
        const table = self.options.presentation == .window;
        const selected = self.isSelected(task_.target);
        const root = try ui.box(cx, S.stack(), .{});
        // The session tray lies on the pane island; the window and the popovers are opaque panels.
        const in_tray = self.options.presentation == .session_tray;
        const row = try ui.box(cx, if (table) S.tableRow(selected, in_tray) else S.popoverRow(selected, in_tray), .{});
        try scope.createEffect(.{ .node = row, .selected = selected, .in_tray = in_tray, .publication = try cx.themeSignal() }, struct {
            fn paint(ctx: anytype) void {
                _ = ctx.publication.get();
                ctx.node.setBackground(S.taskRowFill(ctx.selected, ctx.in_tray));
            }
        }.paint);
        row.meta.ownership.meta.test_id = "transfer.task";
        try root.appendChild(cx.allocator, row);
        const compact = self.options.presentation == .session_tray and self.tray_layout_width < 480;
        const control = try scope.createState(Control, .{ .panel = self, .target = task_.target });
        const checkbox = try ui.widgets.Checkbox(.{ .checked = selected, .label = "", .disabled = task_.target.owner == null, .on_change = cx.on(Control, control, Control.checked) }).mount(scope, cx);
        checkbox.behavior.interaction.a11y.?.label = "选择传输任务";
        checkbox.meta.ownership.meta.test_id = "transfer.task.select";
        // Native Checkbox in an own slot that only exists while managing tasks.
        const checkbox_slot = try ui.box(cx, .{ .flex_shrink = 0, .align_items = .center, .justify = .center }, .{});
        try checkbox_slot.appendChild(cx.allocator, checkbox);
        try row.appendChild(cx.allocator, checkbox_slot);
        checkbox_slot.setDisplay(if (self.batch_visible) .flex else .none);
        const color = phaseColor(task_.phase);
        // File cell: 24pt file-type icon (fg-secondary) + name / detail column.
        const file_cell = try ui.box(cx, S.fileCell(), .{});
        file_cell.meta.ownership.meta.test_id = "transfer.task.file";
        try row.appendChild(cx.allocator, file_cell);
        const file_icon = try ui.iconTint(cx, @import("../../files/view/file_workspace_icons.zig").asset(task_.name), S.theme.current().fg_2, S.icon(24));
        file_icon.meta.ownership.meta.test_id = "transfer.task.icon";
        try file_cell.appendChild(cx.allocator, file_icon);
        const copy = try ui.box(cx, S.copyColumn(), .{});
        try file_cell.appendChild(cx.allocator, copy);
        const upper = try ui.box(cx, S.row(S.name_line, 6), .{});
        upper.meta.ownership.meta.test_id = "transfer.task.head";
        try copy.appendChild(cx.allocator, upper);
        const tip = try ui.widgets.Popover(.{ .trigger = .click, .position = .bottom_start, .offset = .{ .static = 8 }, .width = @as(f32, 420), .max_width = @as(f32, 420), .max_height = @as(f32, 520), .constrain_width_to_viewport = true, .shift_main_axis = true, .size_policy = .fit_content, .fill_trigger = true }).mount(scope, cx);
        // Native Popover: `fill_trigger` makes the trigger take the row's width; the own boxes carry the geometry.
        const name_cell = try ui.box(cx, .{ .width = .fill(), .height = .{ .px = S.name_line }, .flex = 1, .min_width = 0 }, .{});
        try name_cell.appendChild(cx.allocator, tip.wrapper);
        const name_slot = try ui.box(cx, .{ .width = .fill(), .height = .{ .px = S.name_line }, .direction = .row, .min_width = 0, .align_items = .center, .cursor = .pointer }, .{});
        try tip.trigger.appendChild(cx.allocator, name_slot);
        try upper.appendChild(cx.allocator, name_cell);
        _ = try self.taskTextSlot(name_slot, scope, task_.name, 12.5, false, false, "transfer.task.name");
        // Popover meta line (Gq5xg): bytes · rate · status over the 4pt bar.
        // In the table these move to the 进度 / 速度 columns below.
        const lower = try ui.box(cx, S.row(S.meta_line, 6), .{});
        lower.meta.ownership.meta.test_id = "transfer.task.meta";
        if (table) {
            var where_buffer: [512]u8 = undefined;
            const where = std.fmt.bufPrint(&where_buffer, "{s}到 {s}", .{ if (task_.direction == .upload) "上传" else "下载", std.fs.path.dirname(if (task_.direction == .upload) task_.remote_path else task_.local_path) orelse "—" }) catch "—";
            const path_line = try self.label(copy, where, 11, 400, true);
            path_line.meta.ownership.meta.test_id = "transfer.task.path";
            path_line.setStyleInline(cx.allocator, .{ .width = .fill(), .height = .{ .px = S.meta_line }, .min_width = 0, .overflow = .hidden });
            if (path_line.getText()) |old| {
                var props = old;
                props.text_overflow = .ellipsis;
                props.line_height = S.meta_line / 11.0;
                path_line.setText(props);
            }
        } else try copy.appendChild(cx.allocator, lower);
        if (self.options.presentation != .session_tray and self.options.presentation != .session_popover) {
            // 连接 column (table) / trailing owner in the global popover name line.
            const connection = if (table) try ui.box(cx, S.cellColumn(self.owner_column_width, 3), .{}) else upper;
            if (table) try row.appendChild(cx.allocator, connection);
            const owner = try self.label(connection, task_.owner_label, if (table) 12 else 11, 400, !table);
            owner.setStyleInline(cx.allocator, S.label(self.owner_column_width));
            owner.meta.ownership.meta.test_id = "transfer.task.owner";
            if (owner.getText()) |old| {
                var text_props = old;
                text_props.text_overflow = .ellipsis;
                text_props.text_align = if (table) .start else .end;
                owner.setText(text_props);
            }
            if (table) {
                const route = try self.label(connection, if (task_.route.len > 0) task_.route else "—", 11, 400, true);
                route.meta.ownership.meta.test_id = "transfer.task.route";
                route.setStyleInline(cx.allocator, S.label(self.owner_column_width));
                if (route.getText()) |old| {
                    var text_props = old;
                    text_props.text_overflow = .ellipsis;
                    route.setText(text_props);
                }
            }
        }
        // 进度 column (table): bytes · status over the bar.
        const progress_cell = if (table) try ui.box(cx, S.cellColumn(S.progress_column, 5), .{}) else copy;
        if (table) {
            progress_cell.meta.ownership.meta.test_id = "transfer.task.progress_cell";
            try row.appendChild(cx.allocator, progress_cell);
            try progress_cell.appendChild(cx.allocator, lower);
        }
        var buffer: [96]u8 = undefined;
        const description = if (task_.phase == .running) shared_format.liveRate(&buffer, task_.speed_bps) else if (task_.status_detail.len > 0) task_.status_detail else switch (task_.phase) {
            .queued => "等待连接",
            .paused => if (task_.can_resume) "等待继续" else "数据已保留",
            else => "",
        };
        const progress = try self.label(lower, "", 11, 400, true);
        progress.meta.ownership.meta.test_id = "transfer.task.bytes";
        try self.writeBytes(progress, null, task_);
        progress.setStyleInline(cx.allocator, .{ .width = .fill(), .flex = 1, .min_width = 0, .flex_shrink = 1, .overflow = .hidden, .overflow_hidden = true });
        if (progress.getText()) |value| {
            var props = value;
            props.text_overflow = .ellipsis;
            progress.setText(props);
        }
        // 速度 column (table, 12 fg-primary or "—") / rate in the popover meta line.
        const speed_cell = if (table) try ui.box(cx, S.cellColumn(S.speed_column, 3), .{}) else lower;
        if (table) try row.appendChild(cx.allocator, speed_cell);
        const rate = try self.label(speed_cell, if (table and description.len == 0) "—" else description, if (table) 12 else 11, 400, !table);
        rate.meta.ownership.meta.test_id = "transfer.task.rate";
        rate.setStyleInline(cx.allocator, if (table) S.label(S.speed_column) else S.fitLabel(S.rate_max));
        if (table and description.len == 0) rate.setTextColor(S.theme.current().fg_3);
        var remaining_node: ?*ui.Node = null;
        const is_error = v3HasError(task_);
        if (is_error) {
            rate.meta.ownership.meta.test_id = "transfer.task.error";
            rate.setTextColor(S.theme.current().danger_ink);
        }
        if (compact) rate.setDisplay(.none);
        if (table) {
            // 速度 column second line (R3LCmV Remaining, 11 fg-secondary).
            const remaining_label = try self.label(speed_cell, "", 11, 400, true);
            remaining_label.meta.ownership.meta.test_id = "transfer.task.remaining";
            remaining_label.setStyleInline(cx.allocator, S.label(S.speed_column));
            try self.writeBytes(progress, remaining_label, task_);
            remaining_node = remaining_label;
        }
        if (rate.getText()) |old| {
            var text_props = old;
            text_props.text_align = if (table) .start else .end;
            text_props.text_overflow = .ellipsis;
            rate.setText(text_props);
        }
        const fraction: f64 = if (task_.phase == .succeeded) 1 else if (task_.total_bytes) |total| if (total > 0) @min(@as(f64, 1), @as(f64, @floatFromInt(task_.done_bytes)) / @as(f64, @floatFromInt(total))) else 0 else 0;
        const status = try self.label(lower, "", 11, 400, true);
        const status_label = if (task_.reading_source) "读取源文件" else phaseLabel(task_.phase);
        if (task_.phase == .succeeded or (task_.total_bytes != null and task_.total_bytes.? > 0)) {
            try self.format(status, "{s} {d:.0}%", .{ status_label, fraction * 100 });
        } else try self.format(status, "{s} —%", .{status_label});
        status.setTextColor(color);
        status.meta.ownership.meta.test_id = "transfer.task.status";
        status.setStyleInline(cx.allocator, S.fitLabel(S.status_max));
        if (status.getText()) |value| {
            var props = value;
            props.text_overflow = .ellipsis;
            props.text_align = .end;
            status.setText(props);
        }
        if (table) {
            // R3LCmV 进度 status line holds one text: bytes while running,
            // otherwise the phase (the bar carries the running percentage).
            const show_bytes = task_.phase == .running and !task_.reading_source;
            progress.setDisplay(if (show_bytes) .flex else .none);
            status.setDisplay(if (show_bytes) .none else .flex);
            status.setStyleInline(cx.allocator, .{ .max_width = S.progress_column });
            if (status.getText()) |value| {
                var props = value;
                props.text_align = .start;
                status.setText(props);
            }
        }
        // Meta labels sit on the 14pt line (11pt text) in both layouts.
        for ([_]*ui.Node{ progress, status }) |meta_label| if (meta_label.getText()) |value| {
            var props = value;
            props.line_height = S.meta_line / 11.0;
            meta_label.setText(props);
        };
        if (!table) if (rate.getText()) |value| {
            var props = value;
            props.line_height = S.meta_line / 11.0;
            rate.setText(props);
        };
        {
            // W:hl4YW progress: 4pt track, radius 2.
            const track = try ui.box(cx, S.track(), .{});
            track.meta.ownership.meta.test_id = "transfer.task.progress";
            try progress_cell.appendChild(cx.allocator, track);
            const fill = try ui.box(cx, S.fill(@floatCast(fraction), progressColor(task_.phase)), .{});
            try track.appendChild(cx.allocator, fill);
            const mounted = try scope.createState(MountedRow, .{ .panel = self, .index = index, .slot = pool_slot, .bytes = progress, .rate = if (is_error) null else rate, .remaining = remaining_node, .status = status, .fill = fill, .next = self.mounted_rows });
            self.mounted_rows = mounted;
            try scope.onCleanup(MountedRow, mounted, MountedRow.unlink);
        }
        // 操作 column: native compact ghost actions.
        const actions = try ui.boxStyled(cx, S.actionsCell, .{});
        actions.meta.ownership.meta.test_id = "transfer.task.actions";
        try row.appendChild(cx.allocator, actions);
        // Successful uploads have no local reveal action; their single copy
        // action below matches the HTML card and avoids duplicate copy icons.
        if (!(task_.phase == .succeeded and task_.direction == .upload)) {
            if (primaryAction(task_.phase)) |action| {
                _ = try self.button(actions, scope, actionLabel(action, task_.direction), "transfer.task.primary", actionIcon(action, task_.direction), .{ .panel = self, .target = task_.target, .action = action }, !self.actionAvailable(task_.target) or (action == .resume_transfer and !task_.can_resume) or (action == .reveal and !self.canReveal(task_.target)), 24);
            } else {
                const slot = try ui.boxStyled(cx, S.passiveActionSlot, .{});
                try slot.appendChild(cx.allocator, try ui.iconTint(cx, ui.icons.get(if (task_.phase == .queued or task_.phase == .retry_wait) "clock" else if (task_.phase == .verifying or task_.phase == .pausing or task_.phase == .cancelling) "loader-circle" else "minus").?, S.theme.current().fg_3, S.icon(14)));
                try actions.appendChild(cx.allocator, slot);
            }
        }
        _ = try self.button(actions, scope, "复制远程路径", "transfer.task.copy_path", "copy", .{ .panel = self, .target = task_.target, .kind = .copy_path }, false, 24);
        _ = try self.button(actions, scope, "查看任务事件", "transfer.task.events", "list", .{ .panel = self, .target = task_.target, .kind = .events }, false, 24);
        if (allows(task_.phase, .cancel)) _ = try self.button(actions, scope, "取消任务", "transfer.task.cancel", "x", .{ .panel = self, .target = task_.target, .action = .cancel }, !self.actionAvailable(task_.target), 24);
        tip.content.meta.ownership.meta.test_id = "transfer.task.detail_popup";
        // Own column inside the native popover panel (its surface, radius and padding are the defaults).
        const detail_col = try ui.box(cx, S.hoverDetail(), .{});
        try tip.content.appendChild(cx.allocator, detail_col);
        const identity_text = try std.fmt.allocPrint(cx.allocator, "任务 #{d} · {s}", .{ task_.target.job, task_.owner_label });
        defer cx.allocator.free(identity_text);
        const detail_identity = try self.detailLabel(detail_col, identity_text, false, true, "transfer.detail.identity");
        detail_identity.setStyleInline(cx.allocator, S.hoverDetailIdentity());
        const filename_group = try ui.box(cx, S.hoverDetailField(), .{});
        try detail_col.appendChild(cx.allocator, filename_group);
        _ = try self.detailLabel(filename_group, "文件名", false, true, "transfer.detail.label");
        _ = try self.detailLabel(filename_group, task_.name, false, false, "transfer.detail.name");
        try self.detailField(detail_col, "本地路径", task_.local_path, "transfer.detail.local", scope, task_.target, true);
        try self.detailField(detail_col, "远程路径", task_.remote_path, "transfer.detail.remote", scope, task_.target, false);
        if (task_.options.len != 0) {
            const tags = try ui.box(cx, S.row(24, 6), .{});
            tags.meta.ownership.meta.test_id = "transfer.detail.options";
            try detail_col.appendChild(cx.allocator, tags);
            var parts = std.mem.splitSequence(u8, task_.options, " · ");
            while (parts.next()) |part| {
                const enabled = std.mem.endsWith(u8, part, "开");
                const tag = try ui.box(cx, S.optionTag(enabled), .{});
                try tags.appendChild(cx.allocator, tag);
                var tag_text = S.text(10, 400, true);
                tag_text.color = if (enabled) S.theme.current().ok_ink else S.theme.current().fg_2;
                const label_ = try ui.text(cx, "", tag_text);
                try label_.setTextContent(cx.allocator, part);
                try tag.appendChild(cx.allocator, label_);
            }
        }
        tip.content.behavior.interaction.a11y = .{ .role = .dialog, .label = "传输任务详情" };
        tip.trigger.behavior.interaction.a11y = .{ .role = .button, .label = task_.name };
        return root;
    }
    /// Bytes for the meta line. The Gq5xg popover appends the remaining time;
    /// the R3LCmV table moves it under the rate (速度 column, "剩余").
    fn writeBytes(self: *Panel, progress: *ui.Node, remaining_node: ?*ui.Node, task_: Task) !void {
        var done_buffer: [40]u8 = undefined;
        var total_buffer: [40]u8 = undefined;
        const done = shared_format.bytes(&done_buffer, task_.done_bytes);
        // Remaining time in whole seconds (rounded up), written with the shared duration format.
        var seconds: ?u64 = null;
        var eta_buffer: shared_format.Buffer = undefined;
        if (task_.total_bytes) |total| {
            const total_text = shared_format.bytes(&total_buffer, total);
            if (task_.phase == .running and task_.speed_bps > 0 and total > task_.done_bytes) {
                const remaining = total - task_.done_bytes;
                seconds = remaining / task_.speed_bps + @intFromBool(remaining % task_.speed_bps != 0);
            }
            if (seconds != null and remaining_node == null) {
                try self.format(progress, "{s} / {s} · 约 {s}", .{ done, total_text, shared_format.duration(&eta_buffer, @as(u128, seconds.?) * 1000, .short) });
            } else try self.format(progress, "{s} / {s}", .{ done, total_text });
        } else try self.format(progress, "{s} / 大小未知", .{done});
        if (remaining_node) |node| {
            if (seconds) |value| try self.format(node, "剩余约 {s}", .{shared_format.duration(&eta_buffer, @as(u128, value) * 1000, .short)}) else try node.setTextContent(self.cx.allocator, "");
            node.setDisplay(if (seconds != null) .flex else .none);
        }
    }
    fn patchProgress(self: *Panel, row: *const MountedRow, task_: Task) !void {
        var buffer: [96]u8 = undefined;
        if (task_.phase == .running) if (row.rate) |node|
            try node.setTextContent(self.cx.allocator, shared_format.liveRate(&buffer, task_.speed_bps));
        try self.writeBytes(row.bytes, row.remaining, task_);
        const fraction: f64 = if (task_.phase == .succeeded) 1 else if (task_.total_bytes) |total| if (total > 0) @min(@as(f64, 1), @as(f64, @floatFromInt(task_.done_bytes)) / @as(f64, @floatFromInt(total))) else 0 else 0;
        const label_ = if (task_.reading_source) "读取源文件" else phaseLabel(task_.phase);
        if (task_.phase == .succeeded or (task_.total_bytes != null and task_.total_bytes.? > 0)) {
            try self.format(row.status, "{s} {d:.0}%", .{ label_, fraction * 100 });
        } else try self.format(row.status, "{s} —%", .{label_});
        const width: f32 = @floatCast(fraction * 100);
        if (!std.meta.eql(row.fill.style.width, S.fill(@floatCast(fraction), progressColor(task_.phase)).width.?))
            row.fill.setStyleInline(self.cx.allocator, .{ .width = .{ .percent = width } });
    }
    fn detailLabel(self: *Panel, parent: *ui.Node, value: []const u8, mono: bool, secondary: bool, test_id: []const u8) !*ui.Node {
        var style = S.text(11, 400, secondary);
        style.use_monospace_font = mono;
        style.line_height = 16.0 / 11.0;
        style.wrap = .word;
        const node = try ui.text(self.cx, "", style);
        try node.setTextContent(self.cx.allocator, value);
        node.setStyleInline(self.cx.allocator, .{ .width = .fill(), .min_width = 0, .flex_shrink = 0 });
        node.meta.ownership.meta.test_id = test_id;
        try parent.appendChild(self.cx.allocator, node);
        return node;
    }

    fn detailField(self: *Panel, parent: *ui.Node, title: []const u8, value: []const u8, test_id: []const u8, scope: *ui.Scope, target: Target, local: bool) !void {
        const group = try ui.box(self.cx, S.hoverDetailField(), .{});
        try parent.appendChild(self.cx.allocator, group);
        const heading = try ui.box(self.cx, S.row(24, 6), .{});
        try group.appendChild(self.cx.allocator, heading);
        _ = try self.detailLabel(heading, title, false, true, "transfer.detail.label");
        const copy_button = if (value.len != 0) try self.button(heading, scope, if (local) "复制本地路径" else "复制远程路径", if (local) "transfer.detail.copy_local" else "transfer.detail.copy_remote", "copy", .{ .panel = self, .target = target, .kind = if (local) .copy_local_path else .copy_path }, false, 24) else null;
        const path = try self.detailLabel(group, if (value.len != 0) value else "未提供", true, false, test_id);
        if (value.len != 0) {
            // Clicking the path acknowledges on its adjacent copy button too.
            _ = ui.clickable(path, copy_button.?.behavior.events.on_click.?);
        }
    }

    /// Owned shrinking text keeps paint and hit bounds inside its row while
    /// exposing the complete task identity in a bounded native tooltip.
    fn taskTextSlot(self: *Panel, parent: *ui.Node, scope: *ui.Scope, value: []const u8, size: f32, mono: bool, right: bool, test_id: []const u8) !*ui.Node {
        _ = scope;
        const height: f32 = if (mono) 16 else S.name_line;
        const slot = try ui.box(self.cx, .{ .width = .fill(), .height = .{ .px = height }, .flex = 1, .min_width = 0, .overflow = .hidden, .overflow_hidden = true }, .{});
        try parent.appendChild(self.cx.allocator, slot);
        // Gq5xg / R3LCmV file name: 12.5 / 500, fg-primary.
        var style = S.text(size, if (mono) 400 else 500, mono);
        style.line_height = height / size;
        style.text_overflow = .ellipsis;
        style.use_monospace_font = mono;
        style.text_align = if (right) .end else .start;
        const node = try ui.text(self.cx, "", style);
        try node.setTextContent(self.cx.allocator, value);
        node.setStyleInline(self.cx.allocator, .{ .width = .fill(), .height = .{ .px = height }, .min_width = 0, .overflow = .hidden, .overflow_hidden = true });
        node.meta.ownership.meta.test_id = test_id;
        try slot.appendChild(self.cx.allocator, node);
        return node;
    }
    fn v3TaskAction(self: *Panel, parent: *ui.Node, scope: *ui.Scope, label_: []const u8, test_id: []const u8, control: Control, disabled: bool) !void {
        const state = try scope.createState(Control, control);
        const owned = try scope.createText(label_, .{});
        const button_ = try ui.widgets.Button(.{ .label = owned, .a11y_label = owned, .variant = .secondary, .size = .sm, .disabled = disabled, .on_click = self.cx.on(Control, state, Control.run) }).mount(scope, self.cx);
        button_.meta.ownership.meta.test_id = test_id;
        try parent.appendChild(self.cx.allocator, button_);
    }
    fn v3FooterAction(self: *Panel, parent: *ui.Node, scope: *ui.Scope, label_: []const u8, test_id: []const u8, control: Control, disabled: bool, primary: bool) !void {
        const state = try scope.createState(Control, control);
        const owned = try scope.createText(label_, .{});
        const button_ = try ui.widgets.Button(.{ .label = owned, .a11y_label = owned, .variant = if (primary) ui.widgets.button.ButtonVariant.primary else ui.widgets.button.ButtonVariant.secondary, .size = .sm, .disabled = disabled, .on_click = self.cx.on(Control, state, Control.run) }).mount(scope, self.cx);
        button_.meta.ownership.meta.test_id = test_id;
        try parent.appendChild(self.cx.allocator, button_);
    }
    /// 任务“⋯”：原生 `W.Menu`，经菜单唯一入口（`shell/view/app_menu.zig`，menus 包）挂载与投影；
    /// 危险项“取消任务”排在最后（确认归动作执行方），每个 id 运行它的 `Control`。
    const TaskMenu = struct {
        ids: [3][]const u8 = undefined,
        controls: [3]*Control = undefined,
        count: usize = 0,
        fn select(raw: *anyopaque, id: []const u8) void {
            const self: *TaskMenu = @ptrCast(@alignCast(raw));
            for (self.ids[0..self.count], self.controls[0..self.count]) |known, control| if (std.mem.eql(u8, known, id)) return control.run();
        }
    };
    fn taskMenu(self: *Panel, parent: *ui.Node, scope: *ui.Scope, task_: Task) !void {
        const actions = try scope.createState(TaskMenu, .{});
        const mounted = try app_menu.AppMenu.mountTrigger(self.cx, scope, .{ .panel_test_id = "transfer.task.menu" }, .{ .context = actions, .select = TaskMenu.select });
        const trigger = try ui.widgets.Button(.{ .variant = .ghost, .size = .sm, .icon_only = true, .icon_asset = ui.icons.ellipsis, .a11y_label = "任务操作" }).mount(scope, self.cx);
        trigger.meta.ownership.meta.test_id = "transfer.task.more";
        try mounted.result.trigger.appendChild(self.cx.allocator, trigger);
        const more_slot = try ui.box(self.cx, .{ .flex_shrink = 0 }, .{});
        try more_slot.appendChild(self.cx.allocator, mounted.result.wrapper);
        try parent.appendChild(self.cx.allocator, more_slot);
        const declared = [_]struct { label: []const u8, id: []const u8, icon: []const u8, kind: @FieldType(Control, "kind"), action: ?TaskAction = null }{
            .{ .label = "复制远程路径", .id = "transfer.task.copy_path", .icon = "copy", .kind = .copy_path },
            .{ .label = "查看任务事件", .id = "transfer.task.events", .icon = "list", .kind = .events },
            .{ .label = "取消任务", .id = "transfer.task.cancel", .icon = "x", .kind = .action, .action = .cancel },
        };
        var entries: [declared.len]app_menu.Entry = undefined;
        for (declared) |entry| {
            if (entry.action) |action| if (!allows(task_.phase, action)) continue;
            const state = try scope.createState(Control, .{ .panel = self, .target = task_.target, .kind = entry.kind, .action = entry.action, .menu_open = mounted.menu.open });
            if (entry.kind == .copy_path) state.copy_anchor = trigger;
            if (entry.kind == .events) {
                state.event_anchor = trigger;
                if (self.event_view) |events| events.reanchor(task_.target.job, trigger);
            }
            entries[actions.count] = .{ .id = entry.id, .label = entry.label, .icon = entry.icon, .test_id = entry.id, .danger = entry.action != null, .disabled = entry.action != null and !self.actionAvailable(task_.target) };
            actions.ids[actions.count] = entry.id;
            actions.controls[actions.count] = state;
            actions.count += 1;
        }
        const no_keys = struct {
            const map: @import("../../shell/mod.zig").shortcut_router.Map = .{};
        };
        mounted.menu.set(entries[0..actions.count], .{ .keys = &no_keys.map });
    }
    fn renderDetail(self: *Panel, root: *ui.Node, scope: *ui.Scope, task_: Task) !void {
        const detail_box = try ui.box(self.cx, S.detail(), .{});
        detail_box.meta.ownership.meta.test_id = "transfer.task.detail";
        try root.appendChild(self.cx.allocator, detail_box);
        const title = try self.label(detail_box, "", 10.5, 400, true);
        if (task_.route.len == 0) try self.format(title, "任务 #{d} · {s}", .{ task_.target.job, task_.owner_label }) else try self.format(title, "任务 #{d} · {s} · {s}", .{ task_.target.job, task_.owner_label, task_.route });
        title.setStyleInline(self.cx.allocator, .{ .width = .fill(), .height = .{ .px = 26 }, .padding = .{ .left = 8, .right = 8, .top = 5 }, .background = S.theme.current().well, .border = .{ .radius = 8 }, .flex_shrink = 0, .overflow = .hidden });
        if (title.getText()) |value| {
            var props = value;
            props.text_overflow = .ellipsis;
            title.setText(props);
        }
        const paths = try ui.box(self.cx, S.row(20, 8), .{});
        try detail_box.appendChild(self.cx.allocator, paths);
        inline for (.{ .{ "本地", "local_path" }, .{ "远程", "remote_path" } }) |field| {
            const value = try std.fmt.allocPrint(self.cx.allocator, "{s}  {s}", .{ field[0], @field(task_, field[1]) });
            defer self.cx.allocator.free(value);
            const owned = try scope.createText(value, .{});
            const tip = try ui.widgets.Tooltip(.{ .text = owned, .width = @as(f32, 480), .wrap = .word, .fill = true }).mount(scope, self.cx);
            // Native Tooltip (`fill`: the trigger takes the cell's width); the own cell carries the geometry.
            const path_cell = try ui.box(self.cx, .{ .width = .fill(), .height = .{ .px = 20 }, .flex = 1, .min_width = 0, .overflow = .hidden, .overflow_hidden = true }, .{});
            try path_cell.appendChild(self.cx.allocator, tip.wrapper);
            try paths.appendChild(self.cx.allocator, path_cell);
            var path_text_style = S.text(10.5, 400, true);
            path_text_style.text_overflow = .ellipsis;
            path_text_style.use_monospace_font = true;
            const node = try ui.text(self.cx, owned.get(), path_text_style);
            node.meta.ownership.meta.test_id = if (std.mem.eql(u8, field[1], "local_path")) "transfer.task.detail.local" else "transfer.task.detail.remote";
            try tip.trigger.appendChild(self.cx.allocator, node);
            node.setStyleInline(self.cx.allocator, .{ .width = .fill(), .min_width = 0, .height = .{ .px = 17 }, .overflow = .hidden });
            if (node.getText()) |old| {
                var props = old;
                props.text_overflow = .ellipsis;
                props.use_monospace_font = true;
                node.setText(props);
            }
        }
        const metadata = try ui.box(self.cx, S.row(18, 8), .{});
        try detail_box.appendChild(self.cx.allocator, metadata);
        const options = try self.label(metadata, task_.options, 10.5, 400, true);
        options.setTextColor(S.theme.current().accent_ink);
        options.setStyleInline(self.cx.allocator, S.flexibleLabel());
        const summary = try self.label(metadata, if (task_.status_detail.len > 0) task_.status_detail else task_.event_summary, 10.5, 400, true);
        summary.setStyleInline(self.cx.allocator, S.flexibleLabel());
        const actions = try ui.box(self.cx, S.row(24, 4), .{});
        try detail_box.appendChild(self.cx.allocator, actions);
        try actions.appendChild(self.cx.allocator, try ui.spacer(self.cx));
        _ = try self.button(actions, scope, "复制远程路径", "transfer.task.copy_path", "copy", .{ .panel = self, .target = task_.target, .kind = .copy_path }, false, 24);
        _ = try self.button(actions, scope, "查看任务事件", "transfer.task.events", "list", .{ .panel = self, .target = task_.target, .kind = .events }, false, 24);
        _ = try self.button(actions, scope, "收起任务详情", "transfer.task.collapse", "chevron-up", .{ .panel = self, .target = task_.target, .kind = .detail }, false, 24);
    }

    fn itemHeight(index: usize, raw: ?*anyopaque) f32 {
        const p: *Panel = @ptrCast(@alignCast(raw.?));
        _ = index;
        return p.rowPitch();
    }
    /// R3LCmV table rows (window) are 48; Gq5xg popover / tray rows are 54.
    fn rowPitch(self: *const Panel) f32 {
        return if (self.options.presentation == .window) S.table_row_height else S.popover_row_height;
    }
    fn itemLabel(index: usize, buffer: []u8, raw: ?*anyopaque) []const u8 {
        const p: *Panel = @ptrCast(@alignCast(raw.?));
        if (p.source == null or index >= p.visible.items.len) return "";
        const task_ = p.source.?.value.rows[p.visible.items[index]];
        return std.fmt.bufPrint(buffer, "{s} · {s} · {s}", .{ task_.name, task_.owner_label, phaseLabel(task_.phase) }) catch task_.name;
    }
    fn task(self: *const Panel, target: Target) ?Task {
        const source = self.pending_source orelse self.source orelse return null;
        for (source.value.rows) |task_| if (same(task_.target, target)) return task_;
        return null;
    }
    fn canReveal(self: *const Panel, target: Target) bool {
        if (self.options.presentation == .window) return self.actionAvailable(target);
        if (self.manager == null) return (self.task(target) orelse return false).can_reveal and self.actionAvailable(target);
        const callback = self.callbacks.?.can_reveal orelse return false;
        return callback(self.callbacks.?.context, target.job);
    }
    fn actionAvailable(self: *const Panel, target: Target) bool {
        return target.owner != null and (self.manager != null or self.hooks.action != null);
    }
    pub fn perform(self: *Panel, target: Target, action: TaskAction) !void {
        const task_ = self.task(target) orelse return error.StaleTask;
        if (!allows(task_.phase, action)) return error.ActionUnavailable;
        if (action == .resume_transfer and !task_.can_resume) return error.ActionUnavailable;
        if (action == .reveal and self.options.presentation != .window and !self.canReveal(target)) return error.ActionUnavailable;
        if (target.owner == null) return error.UnknownOwner;
        if (self.manager) |manager| {
            const actual = manager.progress(target.job) orelse return error.StaleTask;
            if (actual.attempt != target.attempt) return error.StaleAttempt;
            if (action == .resume_transfer and !manager.canResume(target.job)) return error.ActionUnavailable;
            const session = manager.sessionId(target.job) orelse return error.StaleTask;
            if (self.callbacks.?.owner) |resolve| {
                const current = resolve(self.callbacks.?.context, target.job) orelse return error.StaleOwner;
                if (target.owner == null or !current.eql(target.owner.?)) return error.StaleOwner;
            }

            if (session != if (target.owner) |owner| @backingInt(owner.session_id) else @as(u64, 0)) return error.StaleOwner;
            const action_: Action = switch (action) {
                .pause => .pause,
                .resume_transfer => .resume_transfer,
                .cancel => .cancel,
                .retry => .retry,
                .reveal => .reveal,
                .new_draft => return error.ActionUnavailable,
                .resolve_conflict => .resolve_conflict,
            };
            self.callbacks.?.action(self.callbacks.?.context, target.job, action_);
        } else {
            if (target.owner == null) return error.UnknownOwner;
            const call = self.hooks.action orelse return error.ActionUnavailable;
            try call(self.hooks.context, target, action);
        }
        self.failure.setDisplay(.none);
    }
    fn performBatch(self: *Panel, action: TaskAction) !void {
        const call = self.hooks.batch orelse return error.ActionUnavailable;
        if (self.selection.items.len == 0) return error.EmptySelection;
        const frozen = try self.cx.allocator.dupe(Target, self.selection.items);
        defer self.cx.allocator.free(frozen);
        for (frozen) |target| {
            const task_ = self.task(target) orelse return error.StaleTask;
            if (target.owner == null or !allows(task_.phase, action)) return error.ActionUnavailable;
        }
        try call(self.hooks.context, frozen, action);
    }
    fn isSelected(self: *const Panel, target: Target) bool {
        for (self.selection.items) |target_| if (same(target_, target)) return true;
        return false;
    }
    fn format(self: *Panel, node: *ui.Node, comptime pattern: []const u8, args: anytype) !void {
        const value = try std.fmt.allocPrint(self.cx.allocator, pattern, args);
        defer self.cx.allocator.free(value);
        try node.setTextContent(self.cx.allocator, value);
    }
    fn invalidate(self: *Panel) void {
        self.dirty = true;
        self.root.markLayoutDirty();
        self.cx.requestRedraw();
    }
    fn fail(self: *Panel, err: anyerror) void {
        self.failure.setTextContent(self.cx.allocator, switch (err) {
            error.StaleTask, error.StaleAttempt, error.StaleOwner => "任务已变化，请重新选择原任务",
            error.UnknownOwner => "任务归属未知，暂不可执行操作",
            error.ActionUnavailable => "此任务当前不支持该操作",
            else => @errorName(err),
        }) catch {};
        self.failure.setTextColor(S.theme.current().danger_ink);
        self.failure.setDisplay(.flex);
        self.cx.requestRedraw();
    }
    fn searchChanged(self: *Panel, _: []const u8) void {
        self.invalidate();
    }
    fn scopeChanged(self: *Panel, value: ?[]const u8) void {
        const index = std.fmt.parseInt(usize, value orelse return, 10) catch return;
        var control: Control = .{ .panel = self, .kind = .choice, .choice = index };
        control.run();
    }
    fn filterChanged(self: *Panel, value: ?[]const u8) void {
        self.filter = std.meta.stringToEnum(Filter, value orelse "all") orelse .all;
        self.invalidate();
    }
    pub fn setDirectionFilter(self: *Panel, direction: ?backend.Direction) void {
        self.direction_filter = direction;
        self.dirty = true;
        self.cx.requestRedraw();
    }
    pub fn setFilter(self: *Panel, filter: Filter) void {
        self.filter = filter;
        self.invalidate();
    }
    pub fn show(self: *Panel) void {
        const display: ui.Display = if (self.options.presentation == .session_tray and self.visible.items.len == 0) .none else .flex;
        if (display == .flex and self.root.style.display == .none) self.cx.dispatcher.cancelScrollGesture();
        self.tray_requested_show = true;
        self.root.setDisplay(display);
        if (self.popover_open) |open| if (!open.peek()) open.set(true);
    }
    /// The node the window tree holds: the Popover wrapper for the title bar presentation.
    pub fn mountNode(self: *const Panel) *ui.Node {
        return self.popover_anchor orelse self.root;
    }
    /// Escape / outside click (the Popover's own dismissals): close like the close button.
    fn popoverChanged(self: *Panel, value: bool) void {
        if (value or self.root.style.display == .none) return;
        self.hide();
        if (self.hooks.closed) |call| call(self.hooks.context);
    }
    fn popoverAnchor(raw: *anyopaque) ui.widgets.popover.AnchorRect {
        const self: *Panel = @ptrCast(@alignCast(raw));
        // Without a trigger: the former default corner (46 from the top, 12 from the right).
        const fallback: ui.widgets.popover.AnchorRect = .{ .x = self.cx.viewport.width - 12, .y = 38, .w = 0, .h = 0 };
        const root = self.cx.root orelse return fallback;
        const anchor = findNode(root, self.anchor_id orelse return fallback) orelse return fallback;
        const r = anchor.globalRect();
        return .{ .x = r.x, .y = r.y, .w = r.w, .h = r.h };
    }
    /// Context switches must not return focus to the previous session's trigger.
    pub fn dismiss(self: *Panel) void {
        self.tray_requested_show = false;
        if (self.event_view) |view| view.close();
        self.cx.invalidateReferencesTo(self.root);
        self.root.setDisplay(.none);
        if (self.popover_open) |open| if (open.peek()) open.set(false);
        self.cx.requestRedraw();
    }
    pub fn hide(self: *Panel) void {
        self.tray_requested_show = false;
        if (self.event_view) |view| view.close();
        // Focus return (back to the trigger while focus is in the panel; an outside click keeps
        // the focus it gave to what was clicked) is the native Popover's (OverlayHost `panel`).
        if (self.options.presentation != .window) self.cx.invalidateReferencesTo(self.root);
        self.root.setDisplay(.none);
        if (self.popover_open) |open| if (open.peek()) open.set(false);
        self.cx.requestRedraw();
    }
    pub fn setAnchor(self: *Panel, anchor: *ui.Node) void {
        self.anchor_id = anchor.id;
        self.invalidate();
    }
    pub fn setWindowHook(self: *Panel, context: *anyopaque, callback: *const fn (*anyopaque, WindowAction) anyerror!void) void {
        self.window_context = context;
        self.hooks.window = callback;
        self.window_disabled.set(false);
    }
    pub fn retheme(self: *Panel) void {
        if (self.event_view) |view| view.retheme();
        S.repaint(self.root, self.paint_colors);
        self.paint_colors = S.theme.current();
        self.root.setStyleInline(self.cx.allocator, if (self.options.presentation == .session_tray) S.sessionTray() else if (self.popover != null) S.popoverContent() else S.panel(true));
        self.scopes_dirty = true;
        self.invalidate();
    }
    pub fn refresh(self: *Panel, now: u64, stats: Statistics) !void {
        if (self.in_action) {
            self.pending_refresh = .{ .now = now, .stats = stats };
            self.invalidate();
            return;
        }
        const manager = self.manager orelse return;
        var arena = std.heap.ArenaAllocator.init(self.cx.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const rows = try a.alloc(Task, manager.count());
        for (rows, 0..) |*row, i| {
            const p = manager.progressAt(i).?;
            const spec = manager.specAt(i).?;
            const session = manager.sessionId(p.job) orelse 0;
            const original = manager.sourceName(i) orelse "";
            const name = spec.rename orelse std.fs.path.basename(original);
            const display_name = if (spec.sources.len > 1) try std.fmt.allocPrint(a, "{s} 等{d}个文件", .{ name, spec.sources.len }) else name;
            row.* = .{ .target = .{ .job = p.job, .attempt = p.attempt, .owner = if (self.callbacks.?.owner) |resolve| resolve(self.callbacks.?.context, p.job) else if (session == 0) null else .{ .session_id = @fromBackingInt(session) } }, .direction = spec.direction, .name = display_name, .owner_label = if (session == 0) "归属未知" else try std.fmt.allocPrint(a, "会话 #{d}", .{session}), .local_path = if (spec.direction == .upload) original else try std.fs.path.join(a, &.{ spec.local_dir, name }), .remote_path = try spec.allocRemotePath(a, original), .phase = if (p.job_cleanup == .unknown) .cleanup_unknown else if (p.state == .failed and p.failure == .checksum) .checksum_failed else std.meta.stringToEnum(Phase, @tagName(p.state)).?, .done_bytes = p.done_bytes, .total_bytes = if (p.total_bytes == 0 and p.state != .succeeded) null else p.total_bytes, .speed_bps = p.speed_bps, .status_detail = progressDetail(p), .route = if (self.callbacks.?.metadata) |call| call(self.callbacks.?.context, p.job) else "", .options = try std.fmt.allocPrint(a, "断点续传 {s} · MD5 {s}", .{ if (spec.resume_transfer) "开" else "关", if (spec.md5_check) "开" else "关" }) };
            if (p.state == .running) if (p.verification) |verification| {
                row.phase = .verifying;
                row.speed_bps = 0;
                row.status_detail = switch (verification.state) {
                    .repairing => "正在修复末块",
                    .unavailable => "校验不可用",
                    else => "正在校验",
                };
            };
            if (p.state == .running and p.conflict_waiting) {
                row.phase = .conflict;
                row.speed_bps = 0;
                row.status_detail = "";
            }
            if (p.state == .running) if (p.source_read) |read| {
                row.reading_source = true;
                row.done_bytes = read.done_bytes;
                row.total_bytes = read.total_bytes;
                row.speed_bps = read.speed_bps;
            };
            if (p.state == .succeeded and p.skipped_files > 0) {
                if (p.skipped_files == spec.sources.len) row.phase = .skipped;
                row.status_detail = try std.fmt.allocPrint(a, "已跳过 {d} 项", .{p.skipped_files});
            }
            if (self.callbacks.?.owner_label) |read_label| row.owner_label = try std.fmt.allocPrint(a, "{s} #{d}", .{ read_label(self.callbacks.?.context, p.job), session });
            row.events = try eventText(a, manager, p);
            const history = manager.eventHistory(p.job) orelse &.{};
            row.event_summary = try std.fmt.allocPrint(a, "{d} 条状态事件 · 当前尝试 {d} · {s}", .{ history.len, p.attempt, phaseLabel(row.phase) });
            row.can_resume = manager.canResume(p.job);
            row.can_reveal = if (self.callbacks.?.can_reveal) |read_capability| read_capability(self.callbacks.?.context, p.job) else false;
        }
        var speed: u64 = 0;
        for (rows) |row| if (row.phase == .running) {
            speed +|= row.speed_bps;
        };
        if (self.last_sample_ms == null or now >= self.last_sample_ms.? + 500) {
            std.mem.copyForwards(u64, self.samples[0..7], self.samples[1..8]);
            self.samples[7] = speed;
            self.sample_count = @min(8, self.sample_count + 1);
            self.last_sample_ms = now;
        }
        var choices: std.ArrayList(ScopeChoice) = .empty;
        try choices.append(a, .{ .label = "全部会话", .scope = .all });
        if (self.callbacks.?.scope_choices) |extra| try choices.appendSlice(a, try extra(self.callbacks.?.context, a));
        for (rows) |row| if (row.target.owner) |owner| {
            var exists = false;
            for (choices.items) |choice| if (scopeEql(choice.scope, .{ .session = owner })) {
                exists = true;
                break;
            };
            if (!exists) try choices.append(a, .{ .label = row.owner_label, .scope = .{ .session = owner } });
        };
        var selected: Scope = if (self.options.presentation == .session_popover or self.options.presentation == .session_tray) self.selected_scope else .all;
        var scope_label: []const u8 = if (self.options.presentation == .session_popover or self.options.presentation == .session_tray) (if (self.selected_scope == .sessions) "当前组" else "当前会话") else "全部会话";
        for (choices.items) |choice| if (scopeEql(choice.scope, self.selected_scope)) {
            selected = choice.scope;
            scope_label = choice.label;
            break;
        };
        try self.update(.{ .revision = self.revision + 1, .rows = rows, .choices = choices.items, .scope = selected, .scope_label = scope_label });
    }
    /// True only for a mounted task row intersecting this list's viewport.
    /// Consult current manager state too: a completion can precede snapshot paint.
    pub fn presents(self: *const Panel, job: backend.JobId) bool {
        const source = self.source orelse return false;
        const clip = self.list_container.globalRect();
        if (clip.w <= 0 or clip.h <= 0) return false;
        var mounted = self.mounted_rows;
        while (mounted) |row| : (mounted = row.next) {
            const visible_index = row.index;
            if (visible_index >= self.visible.items.len) continue;
            const task_ = source.value.rows[self.visible.items[visible_index]];
            if (task_.target.job != job or !belongs(self.selected_scope, task_.target.owner)) continue;
            if (self.direction_filter) |direction| if (task_.direction != direction) continue;
            var phase = task_.phase;
            if (self.manager) |manager| if (manager.progress(job)) |progress| {
                phase = if (progress.job_cleanup == .unknown) .cleanup_unknown else if (progress.state == .failed and progress.failure == .checksum) .checksum_failed else std.meta.stringToEnum(Phase, @tagName(progress.state)).?;
            };
            if (self.filter != .all and self.filter != category(phase)) continue;
            const search_text = self.search.peek();
            if (!text_match.matches(search_text, &.{ task_.name, task_.local_path, task_.remote_path, task_.owner_label })) continue;
            const rect = row.slot.globalRect();
            if (rect.w > 0 and rect.h > 0 and rect.x < clip.x + clip.w and rect.x + rect.w > clip.x and rect.y < clip.y + clip.h and rect.y + rect.h > clip.y) return true;
        }
        return false;
    }
    fn afterLayout(raw: *anyopaque, _: u8, _: bool) ui.AfterLayoutResult {
        const p: *Panel = @ptrCast(@alignCast(raw));
        if (p.pending_refresh) |pending| {
            p.pending_refresh = null;
            p.refresh(pending.now, pending.stats) catch {};
            return .needs_layout;
        }
        if (p.dirty) {
            p.flush() catch {};
            return .needs_layout;
        }
        if (p.root.style.display == .none) return .done;
        const parent = p.root.parent orelse return .done;
        // The title bar popover is sized against the window; the Popover places it.
        const bounds: ui.ComputedRect = if (p.popover != null) .{ .x = 0, .y = 0, .w = p.cx.viewport.width, .h = p.cx.viewport.height } else parent.globalRect();
        if (bounds.w <= 0 or bounds.h <= 0) return .done;
        if (p.options.presentation != .session_popover and p.options.presentation != .session_tray) {
            const width = p.list_container.globalRect().w - p.list_gutter;
            if (width > 0 and @abs(width - p.metadata_layout_width) > 0.5) {
                p.metadata_layout_width = width;
                p.dirty = true;
                return .needs_layout;
            }
        }
        if (p.options.presentation == .window) {
            const available_width = @max(0, bounds.w - parent.style.padding.left - parent.style.padding.right);
            const available_height = @max(0, bounds.h - parent.style.padding.top - parent.style.padding.bottom);
            const width = if (p.options.fill_window) available_width else @min(@as(f32, 840), available_width);
            const height = if (p.options.fill_window) available_height else @min(@as(f32, 578), available_height);
            if (p.root.style.width == .px and p.root.style.height == .px and p.root.style.width.px == width and p.root.style.height.px == height) return .done;
            p.root.setStyleInline(p.cx.allocator, .{ .width = .{ .px = width }, .height = .{ .px = height } });
            return .needs_layout;
        }
        if (p.options.presentation == .session_tray) {
            // Width changes must rebind virtual rows, including the first real
            // layout after mount (where no usable width was available yet).
            const actual_width = p.root.globalRect().w;
            if (actual_width > 0 and @abs(actual_width - p.tray_layout_width) > 0.5) {
                p.tray_layout_width = actual_width;
                p.dirty = true;
                p.cx.requestRedraw();
                return .needs_layout;
            }
            var task_height: f32 = 0;
            for (p.visible.items, 0..) |_, i| task_height += itemHeight(i, p);
            // Keep file rows usable at the minimum window height; extra
            // transfer rows stay in this list's native scroll viewport.
            // Header/insets and list gap preserve one complete compact row.
            // 9/8px insets + 28px header + 6px gap + one complete card.
            // A short/self-sized parent must not feed the old clipped height
            // back into this budget; management adds its own 28px row.
            const chrome: f32 = 9 + 28 + 6 + 8 + (if (p.batch_visible) @as(f32, 28) else 0);
            const minimum: f32 = chrome + S.popover_row_height;
            const maximum = @min(@as(f32, 190), @max(minimum, bounds.h * 0.32));
            const height = std.math.clamp(chrome + task_height, minimum, maximum);
            if (p.root.style.height == .px and p.root.style.height.px == height) return .done;
            p.root.setStyleInline(p.cx.allocator, .{ .width = .fill(), .height = .{ .px = height }, .padding = .{ .top = 9, .right = 12, .bottom = 8, .left = 12 } });
            return .needs_layout;
        }
        const global = p.options.presentation == .global_popover;
        const desired_width: f32 = if (global) 640 else 560;
        const width = @max(@as(f32, 1), @min(desired_width, bounds.w - 24));
        var list_height: f32 = 0;
        for (p.visible.items, 0..) |_, i| list_height += itemHeight(i, p);
        if (list_height == 0) list_height = 100;
        const max_height = @max(@as(f32, 1), @min(bounds.h - 24, @as(f32, 578)));
        const failure_height: f32 = if (p.failure.style.display != .none) @max(@as(f32, 24), p.failure.globalRect().h) else 0;
        const notice_height: f32 = if (p.notice.parent.?.style.display != .none) @max(@as(f32, 36), p.notice.parent.?.globalRect().h) else 0;
        const chrome: f32 = (if (global) @as(f32, 156) else 112) + (if (p.batch_visible) @as(f32, 28) else 0);
        const presentation_cap: f32 = if (global) 578 else 420;
        const height = @min(chrome + list_height + failure_height + notice_height, @min(presentation_cap, max_height));
        if (p.popover != null) {
            if (p.anchor_id) |id| if (findNode(p.cx.root orelse return .done, id) == null) {
                p.hide();
                return .done;
            };
            if (p.root.style.width == .px and p.root.style.height == .px and p.root.style.width.px == width and p.root.style.height.px == height) return .done;
            p.root.setStyleInline(p.cx.allocator, .{ .width = .{ .px = width }, .height = .{ .px = height } });
            return .needs_layout;
        }
        var top: f32 = 46;
        var right: f32 = 12;
        if (p.anchor_id) |id| {
            if (findNode(p.cx.root orelse return .done, id)) |anchor| {
                const r = anchor.globalRect();
                const left = std.math.clamp(r.x - bounds.x, @as(f32, 12), @max(@as(f32, 12), bounds.w - width - 12));
                right = bounds.w - width - left;
                top = if (global) r.y - bounds.y + r.h + 8 else r.y - bounds.y - height - 8;
                if (global and top + height > bounds.h - 12) top = r.y - bounds.y - height - 8;
            } else {
                p.hide();
                return .done;
            }
        }
        // 12px window bounds, 8px anchor gap, flip before clamping.
        top = std.math.clamp(top, @as(f32, 12), @max(@as(f32, 12), bounds.h - height - 12));
        right = std.math.clamp(right, @as(f32, 12), @max(@as(f32, 12), bounds.w - width - 12));
        const ext = p.root.style.ensureExtPanic(p.cx.allocator);
        if (p.root.style.width.px == width and p.root.style.height.px == height and ext.inset.top.px == top and ext.inset.right.px == right) return .done;
        p.root.setStyleInline(p.cx.allocator, .{ .width = .{ .px = width }, .height = .{ .px = height }, .inset = .{ .top = .{ .px = top }, .right = .{ .px = right } } });
        return .needs_layout;
    }
};
fn v3RateLabel(task_: Task, buffer: *[96]u8, total_buffer: *[40]u8) []const u8 {
    if (task_.status_detail.len > 0 and !v3HasError(task_)) return task_.status_detail;
    if (task_.phase == .paused) return if (task_.can_resume) "等待继续" else "数据已保留";
    const fraction: f64 = if (task_.total_bytes) |total| if (total > 0) @min(@as(f64, 1), @as(f64, @floatFromInt(task_.done_bytes)) / @as(f64, @floatFromInt(total))) else 0 else 0;
    if (task_.phase == .running) {
        var speed_buffer: [40]u8 = undefined;
        return std.fmt.bufPrint(buffer, "{d:.0}% · {s}", .{ fraction * 100, shared_format.liveRate(&speed_buffer, task_.speed_bps) }) catch "大小待确认";
    }
    const total = if (task_.total_bytes) |bytes| shared_format.bytes(total_buffer, bytes) else "大小待确认";
    return std.fmt.bufPrint(buffer, "{d:.0}% · {s}", .{ fraction * 100, total }) catch "大小待确认";
}
fn v3HasError(task_: Task) bool {
    return (task_.phase == .failed or task_.phase == .checksum_failed) and task_.status_detail.len > 0;
}
fn v3TaskHeight(task_: Task) f32 {
    _ = task_;
    return S.v3_card_height;
}
fn findNode(node: *ui.Node, id: u32) ?*ui.Node {
    if (node.id == id) return node;
    for (node.children.items) |child| if (findNode(child, id)) |found| return found;
    return null;
}
fn countColor(index: usize) ui.Color {
    const c = S.theme.current();
    return switch (index) {
        0 => c.accent_ink,
        2 => c.warn_ink,
        3 => c.danger_ink,
        4 => c.ok_ink,
        else => c.fg_2,
    };
}
fn progressColor(phase: Phase) ui.Color {
    const s = S.theme.states();
    return switch (category(phase)) {
        .active => s.range_fill,
        .paused => s.progress_warn,
        .failed => s.progress_danger,
        .ended => if (phase == .succeeded or phase == .skipped) s.progress_ok else s.range_disabled,
        else => s.range_disabled,
    };
}
fn phaseColor(phase: Phase) ui.Color {
    return countColor(switch (category(phase)) {
        .active => 0,
        .paused => 2,
        .failed => 3,
        .ended => if (phase == .succeeded or phase == .skipped) @as(usize, 4) else @as(usize, 1),
        else => 1,
    });
}
fn primaryAction(phase: Phase) ?TaskAction {
    return switch (phase) {
        .running => .pause,
        .conflict => .resolve_conflict,
        .paused => .resume_transfer,
        .failed => .retry,
        .succeeded => .reveal,
        .cancelled, .checksum_failed => .new_draft,
        else => null,
    };
}
fn actionIcon(action: TaskAction, direction: backend.Direction) []const u8 {
    return switch (action) {
        .pause => "pause",
        .resolve_conflict => "triangle-alert",
        .resume_transfer => "play",
        .retry => "rotate-cw",
        .reveal => if (direction == .upload) "copy" else "folder-open",
        .new_draft => "file-plus",
        .cancel => "x",
    };
}
fn actionLabel(action: TaskAction, direction: backend.Direction) []const u8 {
    return switch (action) {
        .pause => "暂停传输",
        .resolve_conflict => "处理同名文件",
        .resume_transfer => "继续传输",
        .retry => "重试原任务",
        .reveal => if (direction == .upload) "复制远程路径" else "打开本地目录",
        .new_draft => "再次传输，重新核对",
        .cancel => "取消传输",
    };
}

fn eventText(a: std.mem.Allocator, manager: *const backend.Manager, progress: backend.Progress) ![]const u8 {
    var output: std.Io.Writer.Allocating = .init(a);
    defer output.deinit();
    try output.writer.print("任务 #{d} · 会话 #{d}\n", .{ progress.job, manager.sessionId(progress.job) orelse 0 });
    const history = manager.eventHistory(progress.job) orelse &.{};
    if (history.len > 0 and history[0].sequence > 1) try output.writer.writeAll("仅保留最近 32 条状态事件\n");
    for (history) |event| {
        if (event.timestamp_ms) |stamp| {
            const seconds = (stamp / 1000) % 86400;
            try output.writer.print("{d:0>2}:{d:0>2}:{d:0>2} UTC  ", .{ seconds / 3600, (seconds / 60) % 60, seconds % 60 });
        }
        const state = if (event.attempt == 0 and event.state == .queued) "入队" else phaseLabel(std.meta.stringToEnum(Phase, @tagName(event.state)).?);
        try output.writer.print("{s} · 尝试 {d}", .{ state, event.attempt });
        if (event.binding_wait and event.state == .queued) try output.writer.writeAll(" · 等待连接");
        if (event.conflict_waiting) try output.writer.writeAll(" · 等待处理同名冲突");
        if (event.startup_failure) |problem| {
            try output.writer.print(" · {s}（{s}） · 阶段：{s}", .{ problem.message(), problem.code(), problem.stageLabel() });
        } else if (event.failure) |failure| try output.writer.print(" · {s}", .{failureLabel(failure)});
        if (event.verification) |verification| try output.writer.print(" · {s}", .{switch (verification) {
            .pending => "等待校验",
            .reading => "正在校验",
            .repairing => "正在修复末块",
            .passed => "校验通过",
            .failed => "校验失败",
            .unavailable => "校验不可用",
        }});
        if (event.attempt > 0 and event.state != .running) try output.writer.print(" · {s}", .{switch (event.cleanup) {
            .awaiting => "等待资源释放",
            .released => "资源已释放",
            .unknown => "资源释放待核实",
        }});
        try output.writer.writeAll("\n");
    }
    if (progress.total_bytes == 0 and progress.state != .succeeded) try output.writer.print("当前进度 · 已传 {d} B · 大小未知", .{progress.done_bytes}) else try output.writer.print("当前进度 · 已传 {d} / {d} B", .{ progress.done_bytes, progress.total_bytes });
    return output.toOwnedSlice();
}

