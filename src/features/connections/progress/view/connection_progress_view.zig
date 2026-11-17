//! Formal connection progress. Network facts belong to the original Job;
//! this view owns only presentation (fold/filter/scroll), never a second Job.
const std = @import("std");
const ui = @import("ui");
pub const progress = @import("../../../../proto/ssh/connection_progress.zig");
const operations = @import("../../../../host/operation.zig");
const ssh = @import("../../../../proto/ssh/session.zig");
const S = @import("connection_progress_styles.zig");
const panel_header = @import("../../../../shared/ui/components/panel_header/panel_header.zig");
pub const OperationKey = operations.OperationKey;
pub const State = enum { connecting, waiting_auth, waiting_host_key, retrying, protocol_ready, attaching, failed, cancelled };
pub const Hop = struct {
    name: []const u8,
    host: []const u8,
    user: []const u8,
    port: u16 = 22,
    auth_mode: failure_model.AuthMode = .agent,
    identity_file: []const u8 = "",
    saved_password: bool = false,
    saved_passphrase: bool = false,
};
pub const Failure = struct { hop: ?usize = null, phase: ?progress.Phase = null, reason: []const u8, err: ?anyerror = null };
/// A pending automatic retry (design-r3 稿 1). Only the connect job's own
/// numbers: attempt about to start, its limit, and the wait.
pub const Retry = struct { next_attempt: u8, limit: u8, remaining_ns: i128, delay_ns: i128, delays_ns: []const i128 = &.{} };
pub const HostKeyPair = failure_model.HostKeyPair;
const failure_model = @import("../model/failure_view.zig");
const FailureView = @import("failure_controller.zig").FailureView;
const FailureAction = @import("failure_controller.zig").Action;
pub const LogRecord = struct { key: OperationKey, entry: progress.Journal.Entry };
pub const Snapshot = struct {
    key: OperationKey,
    /// Frozen network order, target last. Local is a source, not a session/hop.
    hops: []const Hop,
    journal: progress.Journal.Snapshot,
    state: State = .connecting,
    cleanup: operations.Cleanup = .not_started,
    resources: ?ssh.ResourceLedger.Snapshot = null,
    attached: bool = false,
    inline_authentication: bool = false,
    local_ready: bool = false,
    file_session: bool = false,
    activity: []const u8 = "",
    failure: ?Failure = null,
    /// Controller-owned history across whole-chain retries, newest 128 total.
    /// Empty means show this journal only; the view never fabricates history.
    logs: []const LogRecord = &.{},
    dropped: usize = 0,
    /// Waiting for an automatic retry of this attempt (failure stays in
    /// `failure`, the state stays `.retrying`).
    retry: ?Retry = null,
    /// A changed host key waiting for the user's decision (state
    /// `.waiting_host_key`), shown in the failure view instead of a modal.
    host_key: ?HostKeyPair = null,
    connect_timeout_sec: u16 = 0,
};

fn sameResult(a: *const Snapshot, b: *const Snapshot) bool {
    if (!a.key.eql(b.key) or a.state != b.state or a.cleanup != b.cleanup or
        a.attached != b.attached or a.inline_authentication != b.inline_authentication or
        a.local_ready != b.local_ready or a.file_session != b.file_session or
        a.dropped != b.dropped or !std.mem.eql(u8, a.activity, b.activity) or a.retry != null or b.retry != null or a.host_key != null or b.host_key != null or
        !std.meta.eql(a.resources, b.resources) or a.logs.len != b.logs.len or
        a.journal.attempt != b.journal.attempt or a.journal.count != b.journal.count or
        a.journal.dropped != b.journal.dropped or a.journal.completed != b.journal.completed or
        !std.meta.eql(a.journal.failure, b.journal.failure)) return false;
    // Compare only initialized records, without copying the large journal to
    // the UI stack. Hop identity was already validated by show().
    for (a.journal.entries[0..a.journal.count], b.journal.entries[0..b.journal.count]) |left, right| if (!std.meta.eql(left, right)) return false;
    for (a.logs, b.logs) |left, right| if (!std.meta.eql(left, right)) return false;
    if (a.failure) |left| {
        const right = b.failure orelse return false;
        return left.hop == right.hop and left.phase == right.phase and left.err == right.err and std.mem.eql(u8, left.reason, right.reason);
    }
    return b.failure == null;
}
pub const Callbacks = struct {
    context: *anyopaque,
    cancel: *const fn (*anyopaque, OperationKey) void,
    retry: *const fn (*anyopaque, OperationKey) anyerror!void,
    close: *const fn (*anyopaque, OperationKey) void,
    /// Text is valid during this callback only. The caller must copy it or
    /// synchronously write the clipboard and return its actual success/failure.
    copy_logs: *const fn (*anyopaque, OperationKey, []const u8) anyerror!void,
    /// ybb2B "编辑连接": open the attempt's saved host in its editor. Shown on
    /// failure only while `can_edit` reports an editable (still existing) host.
    edit: ?*const fn (*anyopaque, OperationKey) void = null,
    can_edit: ?*const fn (*anyopaque, OperationKey) bool = null,
    /// Failure view (design-r3 稿 1) actions. Absent ones are not offered.
    stop_retry: ?*const fn (*anyopaque, OperationKey) anyerror!void = null,
    retry_now: ?*const fn (*anyopaque, OperationKey) anyerror!void = null,
    retry_with_credentials: ?*const fn (*anyopaque, OperationKey) anyerror!void = null,
    trust_host_key: ?*const fn (*anyopaque, OperationKey) anyerror!void = null,
    reject_host_key: ?*const fn (*anyopaque, OperationKey) void = null,
};
// Journal/ledger records are self-contained value copies. Only the explicitly
// borrowed display strings need allocation; generic cloneValue(anyerror) is
// not a valid error-union payload on this project's Zig version.
const Owned = struct {
    arena: std.heap.ArenaAllocator,
    // Keep the large bounded journal in the arena: copying Owned must never
    // put another full journal on the UI thread stack.
    value: *Snapshot,
    fn init(allocator: std.mem.Allocator, source: *const Snapshot) !Owned {
        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();
        const owned = arena.allocator();
        const copy = try owned.create(Snapshot);
        copy.* = source.*;
        const hops = try owned.alloc(Hop, source.hops.len);
        for (source.hops, hops) |hop, *destination| {
            destination.* = hop;
            destination.name = try owned.dupe(u8, hop.name);
            destination.host = try owned.dupe(u8, hop.host);
            destination.user = try owned.dupe(u8, hop.user);
            destination.identity_file = try owned.dupe(u8, hop.identity_file);
        }
        copy.hops = hops;
        if (source.retry) |retry| {
            var frozen = retry;
            frozen.delays_ns = try owned.dupe(i128, retry.delays_ns);
            copy.retry = frozen;
        }
        if (source.host_key) |pair| copy.host_key = .{
            .saved_algorithm = try owned.dupe(u8, pair.saved_algorithm),
            .saved_fingerprint = try owned.dupe(u8, pair.saved_fingerprint),
            .offered_algorithm = try owned.dupe(u8, pair.offered_algorithm),
            .offered_fingerprint = try owned.dupe(u8, pair.offered_fingerprint),
        };
        copy.logs = try owned.dupe(LogRecord, source.logs);
        copy.activity = try owned.dupe(u8, source.activity);
        if (source.failure) |fault| {
            var frozen = fault;
            frozen.reason = try owned.dupe(u8, fault.reason);
            copy.failure = frozen;
        }
        return .{ .arena = arena, .value = copy };
    }
    fn deinit(self: *Owned) void {
        self.arena.deinit();
    }
};
const ActionContext = struct {
    view: *View,
    key: OperationKey,
    fn cancel(self: *ActionContext) void {
        if (self.view.matches(self.key)) self.view.cancel();
    }
    fn close(self: *ActionContext) void {
        if (self.view.matches(self.key)) self.view.close();
    }
    fn retry(self: *ActionContext) void {
        if (self.view.matches(self.key)) self.view.retry();
    }
    fn edit(self: *ActionContext) void {
        if (self.view.matches(self.key)) self.view.edit();
    }
    fn copy(self: *ActionContext) void {
        if (self.view.matches(self.key)) self.view.copyLogs();
    }
};
const TipFocus = struct {
    cx: *ui.Cx,
    open: *ui.Signal(bool),
    previous_focus: ?ui.HandlerRef,
    previous_blur: ?ui.HandlerRef,
    fn focus(self: *TipFocus) void {
        if (self.previous_focus) |handler| handler.invoke();
        self.open.set(true);
        self.cx.requestRedraw();
    }
    fn blur(self: *TipFocus) void {
        if (self.previous_blur) |handler| handler.invoke();
        self.open.set(false);
        self.cx.requestRedraw();
    }
};
const HopSlot = struct {
    view: *View,
    key: OperationKey,
    hop: ?usize,
    node: *ui.Node = undefined,
    name: *ui.Node = undefined,
    endpoint: *ui.Node = undefined,
    user: *ui.Node = undefined,
    status: *ui.Node = undefined,
    marker: *ui.Node = undefined,
    marker_box: *ui.Node = undefined,
    skin: *ui.Signal(ui.BoxStyle) = undefined,
    tip_content: *ui.Node = undefined,
    tip_label: *ui.Node = undefined,
    tip_open: *ui.Signal(bool) = undefined,
    tip_id: [64]u8 = @splat(0),
    id: [48]u8 = @splat(0),
    fn choose(self: *HopSlot) void {
        if (!self.view.matches(self.key)) return;
        self.view.copy_result = null;
        self.view.filter = if (self.view.filter == self.hop) null else self.hop;
        self.view.following = true;
        self.view.new_logs = 0;
        if (!self.view.logs_expanded) self.view.toggleLogs();
        self.view.refreshCards() catch {};
        self.view.refreshLogs() catch {};
    }
};
const LogRow = struct {
    view: *View,
    record: LogRecord,
    node: *ui.Node,
    text: *ui.Node,
    fn hover(self: *LogRow) void {
        self.view.showDiagnostic(self) catch {};
    }
    fn leave(self: *LogRow) void {
        if (self.view.diagnostic_row == self) self.view.closeLogTip();
    }
};
const Marker = struct { key: OperationKey, sequence: u64 };

pub const View = struct {
    cx: *ui.Cx,
    scope: *ui.Scope,
    callbacks: Callbacks,
    root: *ui.Node,
    dialog: *ui.Node,
    modal_body: *ui.Node,
    open: *ui.Signal(bool),
    source: ?Owned = null,
    visible: bool = false,
    placed: bool = true,
    compact: bool = false,
    header: *ui.Node = undefined,
    body: *ui.Node = undefined,
    logs_expanded: bool = false,
    filter: ?usize = null,
    following: bool = true,
    new_logs: usize = 0,
    last_marker: ?Marker = null,
    last_scroll_y: f32 = 0,
    cancel_requested: bool = false,
    retry_requested: bool = false,
    copy_result: ?bool = null,
    action_scope: ?*ui.Scope = null,
    action_tips: [2]ui.widgets.TooltipResult = undefined,
    action_tip_count: usize = 0,
    chain_scope: ?*ui.Scope = null,
    title: *ui.Node,
    state_label: *ui.Node = undefined,
    state_badge: *ui.Node = undefined,
    route_label: *ui.Node = undefined,
    toggle_icon: *ui.Node = undefined,
    copy_label: *ui.Node = undefined,
    identity_tip_content: *ui.Node = undefined,
    identity_tip_label: *ui.Node = undefined,
    identity_tip_open: *ui.Signal(bool) = undefined,
    header_icon: *ui.Node = undefined,
    header_spinner: *ui.Node = undefined,
    spinner_color: *ui.Signal(?ui.Color),
    identity_chip: *ui.Node = undefined,
    toggle_button: *ui.Node = undefined,
    copy_icon: ?*ui.Node = null,
    copy_feedback: *@import("../../../../shared/ui/components/copy_button/copy_button.zig").Button = undefined,
    /// 头部统一关闭按钮（PanelClose 里的原生 Button；无障碍名随状态切换）。
    header_close: ?*ui.Node = null,
    connectors: [S.max_hops]struct { icon: *ui.Node, label: *ui.Node } = undefined,
    header_action: *ui.Node,
    endpoint: *ui.Node,
    attempt: *ui.Node,
    body_scroll: ui.widgets.ScrollAreaResult,
    chain_scroll: ui.widgets.ScrollAreaResult,
    slots: [S.max_hops + 1]HopSlot = undefined,
    slot_count: usize = 0,
    summary: *ui.Node,
    summary_title: *ui.Node,
    summary_detail: *ui.Node,
    resource_box: *ui.Node,
    resource_text: *ui.Node,
    /// Stable slot inside this original progress modal. Append AuthView.root
    /// once; show() never destroys or reparents it during state/log updates.
    authentication_area: *ui.Node,
    logs_scroll: ui.widgets.ScrollAreaResult,
    logs_disclosure: *@import("../../../../shared/ui/styles/layout_motion.zig").Disclosure = undefined,
    log_rows: [progress.Journal.capacity]LogRow = undefined,
    log_row_count: usize = 0,
    log_rows_hash: ?u64 = null,
    diagnostic_row: ?*LogRow = null,
    diagnostic_open: *ui.Signal(bool) = undefined,
    diagnostic_panel: *ui.Node = undefined,
    diagnostic_text: *ui.Node = undefined,
    diagnostic_title: *ui.Node = undefined,
    toggle_label: *ui.Node,
    log_help: *ui.Node,
    jump_button: *ui.Node,
    jump_label: *ui.Node,
    copy_host: *ui.Node,
    footer: *ui.Node,
    footer_hint: *ui.Node = undefined,
    retry_disabled: *ui.Signal(bool),
    copy_disabled: *ui.Signal(bool),
    cancel_disabled: *ui.Signal(bool),
    close_disabled: *ui.Signal(bool),
    header_disabled: *ui.Signal(bool),
    cancel_button: ?*ui.Node = null,
    retry_button: ?*ui.Node = null,
    edit_button: ?*ui.Node = null,
    close_button: ?*ui.Node = null,
    cancel_label: ?*ui.Node = null,
    retry_label: ?*ui.Node = null,
    close_label: ?*ui.Node = null,
    /// Mounted on the first failure (most attempts never fail).
    failure: ?*FailureView = null,
    failure_logs_open: bool = false,
    local_name: [256]u8 = @splat(0),
    local_name_len: usize = 0,
    cancel_text: ?*ui.Signal([]const u8) = null,
    retry_text: ?*ui.Signal([]const u8) = null,

    pub fn mount(cx: *ui.Cx, scope: *ui.Scope, callbacks: Callbacks) !*View {
        const self = try cx.allocator.create(View);
        var registered = false;
        errdefer if (!registered) cx.allocator.destroy(self);
        const open = try scope.createSignal(bool, false);
        // Island B v3 i7VdGA / ybb2B: the attempt is the session pane's own
        // content — a pane surface with a centred 580 card. No barrier, no
        // modal focus trap; the host places it over the session's pane.
        const pane = try ui.box(cx, S.paneSurface(), .{});
        pane.meta.ownership.meta.test_id = "connection.progress.pane";
        const card = try ui.box(cx, S.panel(S.normal_height, cx.viewport.width), .{});
        const card_body = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .min_height = 0, .direction = .column, .padding = .{}, .gap = 0 }, .{});
        try card.appendChild(cx.allocator, card_body);
        // Programmatic focus target only (the card itself is not a Tab stop).
        card.setFocusable(true);
        card.setStyleInline(cx.allocator, .{ .tab_index = -1 });
        try pane.appendChild(cx.allocator, card);
        const modal = .{ .overlay = pane, .dialog = card, .body = card_body };
        self.* = .{
            .cx = cx,
            .scope = scope,
            .callbacks = callbacks,
            .spinner_color = try scope.createSignal(?ui.Color, S.theme.current().accent),
            .root = modal.overlay,
            .dialog = modal.dialog,
            .modal_body = modal.body,
            .open = open,
            .retry_disabled = try scope.createSignal(bool, true),
            .copy_disabled = try scope.createSignal(bool, true),
            .cancel_disabled = try scope.createSignal(bool, false),
            .close_disabled = try scope.createSignal(bool, true),
            .header_disabled = try scope.createSignal(bool, false),
            .title = undefined,
            .header_action = undefined,
            .endpoint = undefined,
            .attempt = undefined,
            .body_scroll = undefined,
            .chain_scroll = undefined,
            .summary = undefined,
            .summary_title = undefined,
            .summary_detail = undefined,
            .resource_box = undefined,
            .resource_text = undefined,
            .authentication_area = undefined,
            .logs_scroll = undefined,
            .toggle_label = undefined,
            .log_help = undefined,
            .jump_button = undefined,
            .jump_label = undefined,
            .copy_host = undefined,
            .footer = undefined,
        };
        try scope.onCleanup(View, self, cleanup);
        registered = true;
        modal.dialog.setStyleInline(cx.allocator, S.panel(S.normal_height, cx.viewport.width));
        modal.dialog.meta.ownership.meta.test_id = "connection.progress";
        // min_height 0: the body must shrink to the dialog's max height (new zenit min-height
        // auto = content minimum), or a compact window pushes the action footer out.
        modal.body.setStyleInline(cx.allocator, .{ .width = .fill(), .height = .fill(), .min_height = 0, .padding = .{}, .gap = 0 });
        // The panel supplies its own header/body insets.
        modal.body.setStyle(cx.allocator, .padding, ui.Padding{});
        // Window-level portal: absolute coordinates are viewport coordinates,
        // so the host can align the surface with the session pane's rect.
        try (try cx.ensurePopoverPortalRoot()).appendChild(cx.allocator, pane);
        pane.setDisplay(.none);
        pane.setHitTestVisible(false);
        pane.behavior.events.on_key_down = paneKey;
        pane.behavior.events.key_context = self;
        self.compact = cx.viewport.width <= 860 or cx.viewport.height <= 480;
        const header = try ui.box(cx, S.attemptHeader(self.compact), .{});
        self.header = header;
        self.header_icon = try ui.iconTint(cx, ui.icons.get("network").?, S.theme.current().accent, S.icon(16));
        try header.appendChild(cx.allocator, self.header_icon);
        self.header_spinner = try ui.widgets.Spinner(.{ .size = 16, .stroke_width = 2, .color = self.spinner_color }).mount(scope, cx);
        self.header_spinner.meta.ownership.meta.test_id = "connection.progress.spinner";
        self.header_spinner.setDisplay(.none);
        try header.appendChild(cx.allocator, self.header_spinner);
        const identity_tip = try ui.widgets.Tooltip(.{ .close_on_escape = false, .text = "", .position = .bottom_start, .width = @as(f32, 420), .wrap = .word, .font_size = 11, .background = S.theme.popupInset(), .text_color = S.theme.current().fg_1 }).mount(scope, cx);
        identity_tip.wrapper.setStyleInline(cx.allocator, .{ .width = .fill(), .height = .{ .fit = .{} }, .flex = 1, .min_width = 0 });
        const identity = identity_tip.trigger;
        identity.setStyleInline(cx.allocator, S.identity());
        self.identity_tip_content = identity_tip.content;
        self.identity_tip_label = identity_tip.content.children.items[0];
        self.identity_tip_open = identity_tip.open.?;
        identity_tip.content.meta.ownership.meta.test_id = "connection.progress.identity.tooltip";
        try header.appendChild(cx.allocator, identity_tip.wrapper);
        self.title = try self.appendLabel(identity, "连接进度", S.targetTitle());
        self.title.setStyleInline(cx.allocator, .{ .width = .{ .fit = .{} }, .height = .{ .px = 18 }, .min_width = 0, .max_width = 200, .flex_shrink = 1 });
        self.title.meta.ownership.meta.test_id = "connection.progress.target";
        self.endpoint = try self.appendLabel(identity, "", S.text(11, 400, true));
        self.endpoint.setStyleInline(cx.allocator, .{ .width = .fill(), .height = .{ .px = 16 }, .min_width = 0, .flex = 1 });
        self.endpoint.meta.ownership.meta.test_id = "connection.progress.endpoint";
        self.state_badge = try ui.box(cx, S.stateBadge(false), .{});
        self.state_label = try self.appendLabel(self.state_badge, "正在连接", S.text(10.5, 500, false));
        self.state_label.meta.ownership.meta.test_id = "connection.progress.state";
        try header.appendChild(cx.allocator, self.state_badge);
        self.header_action = try ui.box(cx, S.iconButton(28), .{});
        try header.appendChild(cx.allocator, self.header_action);
        try modal.body.appendChild(cx.allocator, header);
        const body = try ui.box(cx, S.body(self.compact), .{});
        self.body = body;
        try modal.body.appendChild(cx.allocator, body);
        self.body_scroll = try ui.widgets.ScrollArea(.{ .direction = .vertical, .rubber_band_y = false }).mount(scope, cx);
        self.body_scroll.container.setStyleInline(cx.allocator, S.scroll());
        self.body_scroll.content.setStyleInline(cx.allocator, S.stack());
        self.body_scroll.container.meta.ownership.meta.test_id = "connection.progress.body";
        try body.appendChild(cx.allocator, self.body_scroll.container);
        const content = self.body_scroll.content;
        const identity_row = try ui.box(cx, S.row(24), .{}); // Route heading (eAcUg) 24
        // Route heading (eAcUg): 12 regular fg_secondary.
        self.route_label = try self.appendLabel(identity_row, "连接路径", S.text(12, 400, false));
        self.route_label.setStyleInline(cx.allocator, .{ .width = .fill(), .height = .{ .px = 16 }, .flex = 1, .min_width = 0 });
        self.route_label.meta.ownership.meta.test_id = "connection.progress.route";
        const chip = try ui.box(cx, S.chip(), .{});
        self.identity_chip = chip;
        self.attempt = try ui.text(cx, "", S.attemptText());
        self.attempt.setStyleInline(cx.allocator, S.attemptLabel());
        self.attempt.meta.ownership.meta.test_id = "connection.progress.attempt";
        try chip.appendChild(cx.allocator, self.attempt);
        try identity_row.appendChild(cx.allocator, chip);
        self.chain_scroll = try ui.widgets.ScrollArea(.{ .direction = .vertical, .rubber_band_y = false }).mount(scope, cx);
        self.chain_scroll.container.setStyleInline(cx.allocator, S.chainScroll());
        self.chain_scroll.container.meta.ownership.meta.test_id = "connection.progress.chain";
        self.summary = try ui.box(cx, S.notice(false), .{});
        var status_title = S.paragraph(20, 600); // Status (eCdmw): 20 semibold
        status_title.line_height = 24.0 / 20.0;
        self.summary_title = try self.appendLabel(self.summary, "", status_title);
        self.summary_title.meta.ownership.meta.test_id = "connection.progress.summary.title";
        self.summary_detail = try self.appendLabel(self.summary, "", S.paragraph(13, 400)); // JaOId 13
        self.summary_detail.meta.ownership.meta.test_id = "connection.progress.summary.detail";
        self.summary_detail.behavior.interaction.a11y = .{ .role = .status, .live = "polite" };
        try content.appendChild(cx.allocator, self.summary);
        self.resource_box = try ui.box(cx, S.notice(false), .{});
        self.resource_box.setDisplay(.none);
        self.resource_text = try self.appendLabel(self.resource_box, "", S.paragraph(11, 400));
        self.resource_text.meta.ownership.meta.test_id = "connection.progress.resources";
        try content.appendChild(cx.allocator, self.resource_box);
        self.authentication_area = try ui.box(cx, S.authentication(), .{});
        self.authentication_area.meta.ownership.meta.test_id = "connection.progress.authentication";
        try content.appendChild(cx.allocator, self.authentication_area);
        try content.appendChild(cx.allocator, identity_row);
        try content.appendChild(cx.allocator, self.chain_scroll.container);
        const log_controls = try ui.box(cx, S.row(24), .{}); // Log heading (bf8Wx) 24
        const toggle = try ui.widgets.Button(.{ .variant = .ghost, .hover_style = S.ghostHover(false), .pressed_style = S.ghostHover(true), .base_style = S.disclosure(), .a11y_label = "查看连接日志", .on_click = cx.on(View, self, toggleLogs) }).mount(scope, cx);
        prepareCustomButton(toggle);
        self.toggle_button = toggle;
        toggle.setStyleInline(cx.allocator, S.disclosure());
        toggle.unsetStyleInline(.{ .background = ui.Color.TRANSPARENT });
        toggle.meta.ownership.meta.test_id = "connection.progress.logs.toggle";
        toggle.behavior.interaction.a11y.?.expanded = false;
        self.toggle_icon = try ui.iconTint(cx, ui.icons.chevron_right, S.theme.current().fg_2, S.icon(13));
        try toggle.appendChild(cx.allocator, self.toggle_icon);
        // Log heading (bf8Wx): chevron 13 + 12 regular fg_secondary.
        self.toggle_label = try ui.text(cx, "查看连接日志", S.text(12, 400, false));
        try toggle.appendChild(cx.allocator, self.toggle_label);
        try log_controls.appendChild(cx.allocator, toggle);
        self.log_help = try self.appendLabel(log_controls, "", S.text(10, 400, false));
        self.log_help.setStyleInline(cx.allocator, .{ .width = .fill(), .height = .{ .px = 16 }, .flex = 1, .min_width = 0 });
        self.jump_button = try ui.widgets.Button(.{ .variant = .ghost, .hover_style = S.actionHover(false, false), .pressed_style = S.actionHover(false, true), .a11y_label = "回到阶段日志底部", .on_click = cx.on(View, self, jumpToBottom) }).mount(scope, cx);
        prepareCustomButton(self.jump_button);
        self.jump_button.setStyleInline(cx.allocator, S.button(154, 28, false));
        self.jump_button.setDisplay(.none);
        self.jump_button.meta.ownership.meta.test_id = "connection.progress.logs.bottom";
        self.jump_label = try ui.text(cx, "回到底部", S.text(11, 400, false));
        try self.jump_button.appendChild(cx.allocator, self.jump_label);
        try log_controls.appendChild(cx.allocator, self.jump_button);
        self.diagnostic_open = try scope.createSignal(bool, false);
        const diagnostic = try ui.widgets.Popover(.{ .trigger = .manual, .open = self.diagnostic_open, .anchor = .{ .virtual = .{ .ctx = self, .getRect = diagnosticAnchor } }, .open_delay_ms = 350, .position = .bottom_start, .width = 520, .max_width = 520, .max_height = 260, .constrain_width_to_viewport = true, .shift_main_axis = true, .offset = .{ .static = 6 }, .enter_transition = .none, .exit_transition = .none }).mount(scope, cx);
        diagnostic.wrapper.setStyleInline(cx.allocator, .{ .position = .absolute, .width = .{ .px = 0 }, .height = .{ .px = 0 } });
        try modal.body.appendChild(cx.allocator, diagnostic.wrapper);
        self.diagnostic_panel = diagnostic.content;
        diagnostic.content.setStyleInline(cx.allocator, S.diagnosticPanel());
        diagnostic.content.meta.ownership.meta.test_id = "connection.progress.logs.raw-popover";
        self.diagnostic_title = try self.appendLabel(diagnostic.content, "原始 SSH 日志", S.text(12, 600, false));
        const raw_scroll = try ui.widgets.ScrollArea(.{ .direction = .vertical, .rubber_band_y = false }).mount(diagnostic.scope, cx);
        raw_scroll.container.setStyleInline(cx.allocator, .{ .width = .fill(), .height = .{ .px = 200 }, .flex_shrink = 0 });
        raw_scroll.content.setStyleInline(cx.allocator, S.stack());
        var raw_style = S.paragraph(11, 400);
        raw_style.use_monospace_font = true;
        raw_style.selectable = true;
        raw_style.color = S.theme.current().fg_1;
        self.diagnostic_text = try self.appendLabel(raw_scroll.content, "", raw_style);
        self.diagnostic_text.meta.ownership.meta.test_id = "connection.progress.logs.raw-text";
        try diagnostic.content.appendChild(cx.allocator, raw_scroll.container);
        self.copy_host = try ui.box(cx, S.copyButton(), .{});
        try log_controls.appendChild(cx.allocator, self.copy_host);
        try content.appendChild(cx.allocator, log_controls);
        self.logs_scroll = try ui.widgets.ScrollArea(.{ .direction = .vertical, .rubber_band_y = false }).mount(scope, cx);
        self.logs_scroll.container.setStyleInline(cx.allocator, S.logs());

        self.logs_scroll.container.meta.ownership.meta.test_id = "connection.progress.logs";
        self.logs_scroll.content.setStyleInline(cx.allocator, S.logContent());
        self.logs_disclosure = try @import("../../../../shared/ui/styles/layout_motion.zig").Disclosure.mount(cx, scope, self.logs_scroll.container, false);
        try content.appendChild(cx.allocator, self.logs_disclosure.root);
        self.footer = try ui.box(cx, S.footer(self.compact), .{});
        self.footer.meta.ownership.meta.test_id = "connection.progress.actions";
        try modal.body.appendChild(cx.allocator, self.footer);
        if (std.c.gethostname(&self.local_name, self.local_name.len) == 0) self.local_name_len = std.mem.indexOfScalar(u8, &self.local_name, 0) orelse 0;
        try cx.addAfterLayoutHook(self, afterLayout);
        return self;
    }

    /// Safe-hook only. Takes an owned value copy and preserves the inline
    /// authentication slot, including its current focus/composition/selection.
    pub fn show(self: *View, snapshot: Snapshot) !void {
        try validate(&snapshot);
        var same = false;
        if (self.source) |current| {
            same = current.value.key.eql(snapshot.key);
            if (self.visible and !sameLogicalOwner(current.value.key, snapshot.key)) return error.ProgressOwnerMismatch;
            if (sameLogicalOwner(current.value.key, snapshot.key) and older(snapshot.key, current.value.key)) return error.StaleProgress;
            if (same and self.cancel_requested and snapshot.attached) return error.StaleCompletion;
            if (same) {
                if (current.value.hops.len != snapshot.hops.len) return error.FrozenConnectionChanged;
                for (current.value.hops, snapshot.hops) |before, after| {
                    if (before.port != after.port or !std.mem.eql(u8, before.name, after.name) or !std.mem.eql(u8, before.host, after.host) or !std.mem.eql(u8, before.user, after.user)) return error.FrozenConnectionChanged;
                }
                // A retained failure/cancellation is a result, not an active
                // animation. Repeated host polls must leave it clean.
                if (self.visible and self.open.peek() and
                    (snapshot.state == .failed or snapshot.state == .cancelled) and
                    sameResult(current.value, &snapshot)) return;
            }
        }
        var copy = try Owned.init(self.cx.allocator, &snapshot);
        var transferred = false;
        errdefer if (!transferred) copy.deinit();
        self.observeUserScroll();
        if (!same) {
            self.closeLogTip();
            self.log_rows_hash = null;
            self.cancel_requested = false;
            self.retry_requested = false;
            self.copy_result = null;
            self.filter = null;
            self.following = true;
            self.new_logs = 0;
            self.failure_logs_open = false;
        }
        if (self.source) |*old| old.deinit();
        self.source = copy;
        transferred = true;
        self.updateLogMarker();
        if (!same or self.action_scope == null) {
            try self.buildActions();
            try self.buildChain();
        }
        self.visible = !snapshot.attached;
        try self.refresh();
        self.open.set(!snapshot.attached);
        self.present(!snapshot.attached);
        if (snapshot.attached) {
            self.closeLogTip();
            for (self.action_tips[0..self.action_tip_count]) |tip| tip.open.?.set(false);
            self.authentication_area.setDisplay(.none);
        }
        self.cx.requestRedraw();
    }
    pub fn hide(self: *View) void {
        if (!self.visible and !self.open.peek() and self.authentication_area.style.display == .none) return;
        self.visible = false;
        self.closeLogTip();
        self.identity_tip_open.set(false);
        for (self.action_tips[0..self.action_tip_count]) |tip| tip.open.?.set(false);
        for (self.slots[0..self.slot_count]) |slot| slot.tip_open.set(false);
        self.open.set(false);
        self.present(false);
        self.authentication_area.setDisplay(.none);
        if (self.failure) |view| view.hide();
        self.cx.requestRedraw();
    }
    pub fn isVisible(self: *const View) bool {
        return self.visible;
    }
    pub fn operationKey(self: *const View) ?OperationKey {
        return if (self.visible) self.source.?.value.key else null;
    }
    /// Reapply only this view's public slots; never rebuild authentication.
    pub fn retheme(self: *View) !void {
        const c = S.theme.current();
        self.root.setBackground(S.paneSurface().background.?);
        self.dialog.setStyleInline(self.cx.allocator, S.panel(self.dialog.style.height.px, self.cx.viewport.width));
        _ = self.header_icon.setTint(c.accent);
        self.spinner_color.set(c.accent);
        self.title.setTextColor(c.fg_1);
        self.endpoint.setTextColor(c.fg_2);
        self.route_label.setTextColor(c.fg_1);
        self.identity_tip_content.setBackground(S.theme.popupInset());
        self.identity_tip_label.setTextColor(c.fg_1);
        for (self.action_tips[0..self.action_tip_count]) |tip| {
            tip.content.setBackground(S.theme.popupInset());
            tip.content.children.items[0].setTextColor(c.fg_1);
        }
        if (self.copy_icon != null) self.copy_label.setTextColor(c.fg_1);
        self.identity_chip.setStyleInline(self.cx.allocator, S.chip());
        self.footer.setStyleInline(self.cx.allocator, S.footer(self.compact));
        self.attempt.setTextColor(c.fg_2);
        self.toggle_button.setStyleInline(self.cx.allocator, S.disclosure());
        self.toggle_button.unsetStyleInline(.{ .background = ui.Color.TRANSPARENT });
        self.toggle_label.setTextColor(c.fg_1);
        self.log_help.setTextColor(c.fg_2);
        self.jump_button.setStyleInline(self.cx.allocator, S.button(154, 28, false));
        self.jump_label.setTextColor(c.fg_2);
        self.logs_scroll.container.setStyleInline(self.cx.allocator, S.logs());
        for (self.log_rows[0..self.log_row_count]) |row| row.text.setTextColor(c.fg_1);
        self.diagnostic_panel.setStyleInline(self.cx.allocator, S.diagnosticPanel());
        self.diagnostic_title.setTextColor(c.fg_1);
        self.diagnostic_text.setTextColor(c.fg_1);
        if (self.copy_icon) |node| _ = node.setTint(c.fg_2);
        for (self.slots[0..self.slot_count]) |slot| {
            self.ink(slot.name, c.fg_1);
            self.ink(slot.endpoint, c.fg_2);
            slot.user.setTextColor(c.fg_2);
            slot.tip_content.setBackground(S.theme.popupInset());
            slot.tip_label.setTextColor(c.fg_1);
        }
        for (self.connectors[0..self.slot_count -| 1]) |connector| {
            _ = connector.icon.setTint(c.fg_3);
            connector.label.setTextColor(c.fg_2);
        }
        if (self.source != null) self.footer_hint.setTextColor(c.fg_2);
        self.summary_title.setTextColor(c.fg_1);
        self.summary_detail.setTextColor(c.fg_2);
        self.resource_box.setStyleInline(self.cx.allocator, S.notice(false));
        self.resource_text.setTextColor(c.fg_2);
        if (self.source != null) try self.refresh();
    }
    pub fn matches(self: *const View, key: OperationKey) bool {
        return if (self.source) |source| self.visible and source.value.key.eql(key) else false;
    }
    pub fn toggleLogs(self: *View) void {
        if (!self.visible) return;
        self.logs_expanded = !self.logs_expanded;
        if (!self.logs_expanded) self.closeLogTip();
        self.logs_disclosure.setExpanded(self.logs_expanded);
        self.toggle_label.setTextContent(self.cx.allocator, if (self.logs_expanded) "收起连接日志" else "查看连接日志") catch {};
        self.toggle_button.behavior.interaction.a11y.?.expanded = self.logs_expanded;
        const asset = if (self.logs_expanded) ui.icons.chevron_down else ui.icons.chevron_right;
        if (asset.icon_id) |id| if (asset.pickRep(12)) |rep| self.toggle_icon.setIcon(.{ .icon_id = id, .rep = rep, .tint = S.theme.current().fg_2 });
        self.resize();
        self.cx.requestRedraw();
    }
    pub fn jumpToBottom(self: *View) void {
        self.following = true;
        self.new_logs = 0;
        self.syncLogScroll();
        self.cx.requestRedraw();
    }
    pub fn cancel(self: *View) void {
        const source = if (self.source) |source| source.value else return;
        if (!self.visible or self.cancel_requested or source.attached or (source.cleanup == .released and source.state != .retrying)) return;
        self.cancel_requested = true;
        self.cancel_disabled.set(true);
        self.callbacks.cancel(self.callbacks.context, source.key);
        self.refreshSummary() catch {};
    }
    pub fn retry(self: *View) void {
        if (!self.visible or self.retry_requested or !self.canRetry()) return;
        const key = self.source.?.value.key;
        self.retry_requested = true;
        self.retry_disabled.set(true);
        self.callbacks.retry(self.callbacks.context, key) catch {
            self.retry_requested = false;
            self.retry_disabled.set(!self.canRetry());
            self.log_help.setTextContent(self.cx.allocator, "无法开始重试，请保留原连接状态后重试。") catch {};
            return;
        };
    }
    pub fn close(self: *View) void {
        const source = if (self.source) |source| source.value else return;
        if (!self.visible) return;
        if (source.state != .failed and source.state != .cancelled and !source.attached) {
            self.cancel();
            return;
        }
        if (!self.canDismiss()) return;
        const key = source.key;
        self.hide();
        self.callbacks.close(self.callbacks.context, key);
    }
    /// Failed attempt → open the saved host in its editor (the host keeps the
    /// result card; editing does not dismiss or retry anything).
    pub fn edit(self: *View) void {
        const source = if (self.source) |source| source.value else return;
        if (!self.visible or source.state != .failed or !self.canEdit()) return;
        const callback = self.callbacks.edit orelse return;
        callback(self.callbacks.context, source.key);
    }
    fn canEdit(self: *const View) bool {
        const source = if (self.source) |source| source.value else return false;
        if (self.callbacks.edit == null) return false;
        const check = self.callbacks.can_edit orelse return false;
        return check(self.callbacks.context, source.key);
    }
    pub fn copyLogs(self: *View) void {
        if (!self.visible or self.copy_disabled.peek()) return;
        var text = std.Io.Writer.Allocating.init(self.cx.allocator);
        defer text.deinit();
        self.writeLogs(&text.writer) catch {
            self.copyFeedback(false);
            return;
        };
        self.callbacks.copy_logs(self.callbacks.context, self.source.?.value.key, text.writer.buffered()) catch {
            self.copyFeedback(false);
            return;
        };
        self.copyFeedback(true);
    }

    fn refresh(self: *View) !void {
        const source = self.source.?.value;
        const spinning = !source.attached and !self.cancel_requested and (source.state == .connecting or source.state == .retrying or source.state == .protocol_ready or source.state == .attaching);
        self.header_spinner.setDisplay(if (spinning) .flex else .none);
        self.header_icon.setDisplay(if (spinning) .none else .flex);
        const target = source.hops[source.hops.len - 1];
        var buffer: [2048]u8 = undefined;
        try self.endpoint.setTextContent(self.cx.allocator, try formatEndpoint(&buffer, target));
        try self.fullValueTip(self.identity_tip_content, self.identity_tip_label, target, null);
        try self.attempt.setTextContent(self.cx.allocator, try std.fmt.bufPrint(&buffer, "第 {d} 次尝试", .{source.key.attempt_id.?}));
        const state_label: []const u8 = if (source.attached) "已接入" else if (source.state == .failed) "连接失败" else if (source.state == .retrying) "正在重试" else if (source.state == .cancelled or self.cancel_requested) (if (source.cleanup == .released) "已取消" else "正在取消") else if (source.state == .waiting_auth) "等待认证" else if (source.state == .waiting_host_key) "等待确认" else "正在连接";
        try self.title.setTextContent(self.cx.allocator, target.name);
        try self.state_label.setTextContent(self.cx.allocator, state_label);
        self.state_badge.setStyleInline(self.cx.allocator, S.stateBadge(source.state == .failed));
        self.state_label.setTextColor(if (source.state == .failed) S.theme.current().danger_ink else S.theme.current().accent_ink);
        try self.route_label.setTextContent(self.cx.allocator, if (source.hops.len == 1) (if (source.file_session) "连接路径 · SFTP 直连" else "连接路径 · 直连") else try std.fmt.bufPrint(&buffer, "连接路径 · {d} 级跳板{s}", .{ source.hops.len - 1, if (source.file_session) " · SFTP" else "" }));
        self.authentication_area.setDisplay(if (source.inline_authentication and !source.attached) .flex else .none);
        self.retry_disabled.set(self.retry_requested or !self.canRetry());
        self.cancel_disabled.set(self.cancel_requested or source.attached);
        self.close_disabled.set(!self.canDismiss());
        self.header_disabled.set(if (source.state == .failed or source.state == .cancelled) !self.canDismiss() else self.cancel_requested or source.attached);
        const icon = ui.icons.get(if (source.state == .failed) "triangle-alert" else "network").?;
        if (icon.icon_id) |id| if (icon.pickRep(22)) |rep| self.header_icon.setIcon(.{ .icon_id = id, .rep = rep, .tint = if (source.state == .failed) S.theme.current().danger_ink else S.theme.current().accent });
        try self.refreshCards();
        try self.refreshSummary();
        try self.refreshResources();
        try self.refreshLogs();
        try self.refreshFailure();
        self.resize();
    }
    /// design-r3 稿 1: failed attempts, a pending automatic retry and a
    /// changed host key use the failure view instead of the progress card.
    pub fn failureMode(self: *const View) bool {
        const source = if (self.source) |source| source.value else return false;
        if (source.attached or self.cancel_requested) return false;
        if (source.host_key != null) return true;
        if (source.retry != null and source.failure != null) return true;
        return source.state == .failed;
    }
    fn refreshFailure(self: *View) !void {
        const source = self.source.?.value;
        const on = self.failureMode();
        self.dialog.setDisplay(if (on) .none else .flex);
        if (on and self.failure == null) {
            const view = try FailureView.mount(self.cx, self.scope, .{ .context = self, .act = failureAction });
            // Programmatic focus target (Escape reaches the pane), not a Tab stop.
            view.root.setFocusable(true);
            view.root.setStyleInline(self.cx.allocator, .{ .tab_index = -1 });
            try self.root.appendChild(self.cx.allocator, view.root);
            self.failure = view;
        }
        const failure_view = self.failure orelse return;
        failure_view.root.setDisplay(if (on) .flex else .none);
        if (!on) return failure_view.hide();
        var hops: [S.max_hops]failure_model.Hop = undefined;
        for (source.hops, hops[0..source.hops.len]) |hop, *destination| destination.* = .{ .name = hop.name, .host = hop.host, .user = hop.user, .port = hop.port, .auth_mode = hop.auth_mode, .identity_file = hop.identity_file, .saved_password = hop.saved_password, .saved_passphrase = hop.saved_passphrase };
        var reached: [S.max_hops]bool = @splat(false);
        for (source.journal.entries[0..source.journal.count]) |entry| if (entry.phase == .ready and entry.status == .succeeded and entry.hop < source.hops.len) {
            reached[entry.hop] = true;
        };
        // Same facts as the card: the host's failure, else the journal's.
        const fault: ?Failure = if (source.failure) |value| value else if (source.journal.failure) |entry| (if (entry.status == .failed) Failure{ .hop = entry.hop, .phase = entry.phase, .reason = failureText(entry.failure), .err = entry.failure } else null) else null;
        const reason = if (fault) |value| inlineFailureText(value.reason, if (source.journal.failure) |entry| entry.diagnostic.len != 0 else false) else "";
        const pending_retry: ?failure_model.Retry = if (source.retry) |value| .{
            .next_attempt = value.next_attempt,
            .limit = value.limit,
            .remaining_ns = value.remaining_ns,
            .delay_ns = value.delay_ns,
            .delays_ns = value.delays_ns,
        } else null;
        const a = failure_view.nextAllocator();
        const projection = try failure_model.project(a, .{
            .hops = hops[0..source.hops.len],
            .local_name = self.local_name[0..self.local_name_len],
            .failure = if (fault) |value| (value.err orelse if (source.journal.failure) |entry| entry.failure else null) else null,
            .reason = reason,
            .failed_hop = if (fault) |value| value.hop else null,
            .failed_phase = if (fault) |value| value.phase else null,
            .reached = reached[0..source.hops.len],
            .retry = pending_retry,
            .host_key = source.host_key,
            .connect_timeout_sec = source.connect_timeout_sec,
            .can_edit = self.canEdit(),
            .can_retry = self.canRetry() and !self.retry_requested,
            .retry_requested = self.retry_requested,
            .logs_open = self.failure_logs_open,
            .has_logs = self.logCount() != 0,
        });
        var visible = projection;
        visible.credentials = projection.credentials and self.callbacks.retry_with_credentials != null;
        if (!visible.credentials and projection.primary == .credentials) visible.primary = .retry_now;
        visible.stop_retry = projection.stop_retry and self.callbacks.stop_retry != null;
        visible.trust_key = projection.trust_key and self.callbacks.trust_host_key != null;
        visible.disconnect = projection.disconnect and self.callbacks.reject_host_key != null;
        if (self.failure_logs_open) visible.log_lines = try self.failureLogLines(a);
        try failure_view.publish(visible);
    }
    /// The newest lines of this attempt's log, one per phase event.
    fn failureLogLines(self: *View, a: std.mem.Allocator) ![]const failure_model.LogLine {
        const count = self.logCount();
        const first = count -| 12;
        const lines = try a.alloc(failure_model.LogLine, count - first);
        for (first..count, lines) |index, *line| {
            var text = std.Io.Writer.Allocating.init(a);
            try writeLogRecord(&text.writer, self.logAt(index), false);
            const value = std.mem.trimEnd(u8, text.written(), "\n");
            line.* = .{ .id = std.hash.Wyhash.hash(index, value), .text = value };
        }
        return lines;
    }
    fn failureAction(raw: *anyopaque, action: FailureAction) void {
        const self: *View = @ptrCast(@alignCast(raw));
        const source = if (self.source) |source| source.value else return;
        if (!self.visible or !self.failureMode()) return;
        const key = source.key;
        switch (action) {
            .edit => {
                if (!self.canEdit()) return;
                if (self.callbacks.edit) |callback| callback(self.callbacks.context, key);
            },
            .toggle_logs => self.failure_logs_open = !self.failure_logs_open,
            .retry_now => if (source.retry != null) {
                if (self.callbacks.retry_now) |callback| callback(self.callbacks.context, key) catch {};
            } else self.retry(),
            .stop_retry => if (self.callbacks.stop_retry) |callback| callback(self.callbacks.context, key) catch {},
            .credentials => if (self.callbacks.retry_with_credentials) |callback| {
                if (self.retry_requested or !self.canRetry()) return;
                self.retry_requested = true;
                callback(self.callbacks.context, key) catch {
                    self.retry_requested = false;
                };
            },
            .trust_key => if (self.callbacks.trust_host_key) |callback| callback(self.callbacks.context, key) catch {},
            .disconnect => if (self.callbacks.reject_host_key) |callback| callback(self.callbacks.context, key),
        }
        self.refreshFailure() catch {};
        self.cx.requestRedraw();
    }
    fn buildActions(self: *View) !void {
        self.clearNodes(self.header_action);
        self.clearNodes(self.copy_host);
        self.clearNodes(self.footer);
        if (self.action_scope) |scope| scope.dispose();
        self.action_tip_count = 0;
        const scope = try self.scope.childScope();
        self.action_scope = scope;
        const ctx = try self.cx.allocator.create(ActionContext);
        ctx.* = .{ .view = self, .key = self.source.?.value.key };
        try scope.adoptResource(ctx, struct {
            fn destroy(ptr: *anyopaque, allocator: std.mem.Allocator) void {
                allocator.destroy(@as(*ActionContext, @ptrCast(@alignCast(ptr))));
            }
        }.destroy);
        // panel-heads：统一关闭按钮（卡片 `paneKey` 的 Esc 同样走 `close`：进行中取消，结束后关闭）。
        const close_slot = try panel_header.mountClose(scope, self.cx, .{ .label = "关闭或取消当前连接", .test_id = "connection.progress.close", .tooltip_test_id = "connection.progress.close.tooltip", .disabled = self.header_disabled, .on_close = self.cx.on(ActionContext, ctx, ActionContext.close), .button = &self.header_close });
        try self.header_action.appendChild(self.cx.allocator, close_slot);
        const copy_button = try ui.widgets.Button(.{ .variant = .ghost, .hover_style = S.ghostHover(false), .pressed_style = S.ghostHover(true), .base_style = S.copyButton(), .a11y_label = "复制连接日志", .disabled = self.copy_disabled, .on_click = self.cx.on(ActionContext, ctx, ActionContext.copy) }).mount(scope, self.cx);
        prepareCustomButton(copy_button);
        self.copy_icon = try ui.iconTint(self.cx, ui.icons.copy, S.theme.current().fg_2, S.icon(16));
        try copy_button.appendChild(self.cx.allocator, self.copy_icon.?);
        self.copy_label = try ui.text(self.cx, "复制日志", S.text(11, 500, false));
        try copy_button.appendChild(self.cx.allocator, self.copy_label);
        copy_button.setStyleInline(self.cx.allocator, S.copyButton());
        copy_button.unsetStyleInline(.{ .background = ui.Color.TRANSPARENT });
        copy_button.meta.ownership.meta.test_id = "connection.progress.logs.copy";
        self.copy_feedback = try @import("../../../../shared/ui/components/copy_button/copy_button.zig").Button.attach(self.cx, scope, copy_button);
        try self.copy_host.appendChild(self.cx.allocator, try self.actionTip(scope, copy_button, "复制连接日志，日志不含凭据", "connection.progress.logs.copy.tooltip", S.copyButton()));
        // Actions (f8AFFO): 编辑连接 (secondary) leads; 关闭 / 重新连接 trail.
        self.edit_button = try self.button(self.footer, scope, ctx, "编辑主机", false, null, ActionContext.edit, "connection.progress.edit");
        self.edit_button.?.setDisplay(.none);
        const hint = try self.appendLabel(self.footer, "", S.text(10.5, 400, false));
        self.footer_hint = hint;
        hint.setStyleInline(self.cx.allocator, .{ .width = .fill(), .height = .{ .px = 16 }, .flex = 1, .min_width = 0 });
        self.cancel_button = try self.button(self.footer, scope, ctx, "取消连接", false, self.cancel_disabled, ActionContext.cancel, "connection.progress.cancel");
        self.close_button = try self.button(self.footer, scope, ctx, "关闭", false, self.close_disabled, ActionContext.close, "connection.progress.dismiss");
        self.retry_button = try self.button(self.footer, scope, ctx, "重新连接", true, self.retry_disabled, ActionContext.retry, "connection.progress.retry");
    }
    fn actionTip(self: *View, scope: *ui.Scope, button_node: *ui.Node, text: []const u8, id: []const u8, style: ui.BoxStyle) !*ui.Node {
        const tip = try ui.widgets.Tooltip(.{ .close_on_escape = false, .text = text, .position = .bottom_end, .font_size = 11, .background = S.theme.popupInset(), .text_color = S.theme.current().fg_1 }).mount(scope, self.cx);
        tip.wrapper.setStyleInline(self.cx.allocator, style);
        tip.trigger.setStyleInline(self.cx.allocator, style);
        tip.content.meta.ownership.meta.test_id = id;
        const focus = try scope.createState(TipFocus, .{ .cx = self.cx, .open = tip.open.?, .previous_focus = button_node.behavior.events.on_focus, .previous_blur = button_node.behavior.events.on_blur });
        button_node.behavior.events.on_focus = self.cx.on(TipFocus, focus, TipFocus.focus);
        button_node.behavior.events.on_blur = self.cx.on(TipFocus, focus, TipFocus.blur);
        try tip.trigger.appendChild(self.cx.allocator, button_node);
        self.action_tips[self.action_tip_count] = tip;
        self.action_tip_count += 1;
        return tip.wrapper;
    }
    fn buildChain(self: *View) !void {
        self.clearNodes(self.chain_scroll.content);
        if (self.chain_scope) |scope| scope.dispose();
        const scope = try self.scope.childScope();
        self.chain_scope = scope;
        const source = self.source.?.value;
        self.slot_count = source.hops.len + 1;
        // Hops (W5ibrC): 44 rows joined by 10pt links.
        const rows: f32 = @floatFromInt(self.slot_count);
        self.chain_scroll.container.setStyleInline(self.cx.allocator, .{ .height = .{ .px = rows * S.hop_height + (rows - 1) * S.link_height } });
        self.chain_scroll.content.setStyleInline(self.cx.allocator, S.chain(self.slot_count, @min(S.width, self.cx.viewport.width - 16) - 32));
        for (0..self.slot_count) |index| {
            if (index != 0) {
                const connector = try ui.box(self.cx, S.connector(), .{});
                const icon = try ui.iconTint(self.cx, ui.icons.arrow_right, S.theme.current().fg_3, S.icon(14));
                try connector.appendChild(self.cx.allocator, icon);
                const connector_label = try self.appendLabel(connector, if (index == 1) "TCP" else "隧道", S.connectorText());
                self.connectors[index - 1] = .{ .icon = icon, .label = connector_label };
                connector.setDisplay(.none);
                const link = try ui.box(self.cx, S.link(), .{});
                try link.appendChild(self.cx.allocator, try ui.boxStyled(self.cx, struct {
                    fn line(_: *const ui.ThemeTokens) ui.BoxStyle {
                        return S.linkLine();
                    }
                }.line, .{}));
                try self.chain_scroll.content.appendChild(self.cx.allocator, link);
                try self.chain_scroll.content.appendChild(self.cx.allocator, connector);
            }
            const slot = &self.slots[index];
            slot.* = .{ .view = self, .key = source.key, .hop = if (index == 0) null else index - 1 };
            const tip = try ui.widgets.Tooltip(.{ .close_on_escape = false, .text = "", .position = .bottom_start, .width = @as(f32, 420), .wrap = .word, .font_size = 11, .background = S.theme.popupInset(), .text_color = S.theme.current().fg_1 }).mount(scope, self.cx);
            tip.wrapper.setStyleInline(self.cx.allocator, .{ .width = .fill(), .align_self = .stretch, .height = .{ .px = S.hop_height }, .flex_shrink = 0 });
            // Cross-axis fill is not implicit: stretch the trigger so the hop row spans the card.
            tip.trigger.setStyleInline(self.cx.allocator, .{ .width = .fill(), .height = .fill(), .min_width = 0, .align_self = .stretch, .align_items = .stretch });
            slot.tip_content = tip.content;
            slot.tip_label = tip.content.children.items[0];
            slot.tip_open = tip.open.?;
            tip.content.meta.ownership.meta.test_id = try std.fmt.bufPrint(&slot.tip_id, "connection.progress.hop.tooltip.{d}", .{index});
            slot.skin = try scope.createSignal(ui.BoxStyle, S.card(false));
            slot.node = try ui.widgets.Button(.{ .variant = .ghost, .hover_style = S.ghostHover(false), .pressed_style = S.ghostHover(true), .base_style = slot.skin, .a11y_label = "查看该节点的连接日志", .on_click = self.cx.on(HopSlot, slot, HopSlot.choose) }).mount(scope, self.cx);
            const focus_tip = try scope.createState(TipFocus, .{ .cx = self.cx, .open = slot.tip_open, .previous_focus = slot.node.behavior.events.on_focus, .previous_blur = slot.node.behavior.events.on_blur });
            slot.node.behavior.events.on_focus = self.cx.on(TipFocus, focus_tip, TipFocus.focus);
            slot.node.behavior.events.on_blur = self.cx.on(TipFocus, focus_tip, TipFocus.blur);
            prepareCustomButton(slot.node);
            slot.node.meta.ownership.meta.test_id = try std.fmt.bufPrint(&slot.id, "connection.progress.hop.{d}", .{index});
            slot.marker_box = try ui.box(self.cx, S.marker(S.theme.current().fg_3), .{});
            slot.marker = try ui.iconTint(self.cx, ui.icons.circle_check, S.theme.current().fg_3, S.icon(13));
            try slot.marker_box.appendChild(self.cx.allocator, slot.marker);
            try slot.node.appendChild(self.cx.allocator, slot.marker_box);
            const copy_column = try ui.box(self.cx, S.hopCopy(), .{});
            try slot.node.appendChild(self.cx.allocator, copy_column);
            // Hop name (AlEHs): 13 medium.
            var name_style = S.text(13, 500, false);
            name_style.line_height = 16.0 / 13.0;
            slot.name = try self.cardLabel(copy_column, 16, name_style);

            var address_style = S.text(11, 400, true); // Address (zad9g): 11 mono fg_secondary
            address_style.line_height = 15.0 / 11.0;
            slot.endpoint = try self.cardLabel(copy_column, 15, address_style);
            self.ink(slot.endpoint, S.theme.current().fg_2);
            self.ink(slot.name, S.theme.current().fg_1);
            slot.user = try self.cardLabel(copy_column, 14, S.text(10, 400, false));
            slot.user.setDisplay(.none);
            var status_style = S.text(12, 400, false); // Hop status (LgOf0): 12 regular
            status_style.line_height = 16.0 / 12.0;
            status_style.text_align = .end;
            slot.status = try self.cardLabel(slot.node, 16, status_style);
            slot.status.setStyleInline(self.cx.allocator, .{ .width = .{ .fit = .{} }, .min_width = 64, .max_width = 160, .height = .{ .px = 16 }, .flex_shrink = 0 });

            try tip.trigger.appendChild(self.cx.allocator, slot.node);
            try self.chain_scroll.content.appendChild(self.cx.allocator, tip.wrapper);
        }
    }
    fn refreshCards(self: *View) !void {
        const source = self.source.?.value;
        const fault = self.currentFailure();
        var buffer: [1536]u8 = undefined;
        for (self.slots[0..self.slot_count]) |*slot| {
            var card_style = S.card(slot.hop != null and slot.hop == self.filter);
            if (slot.hop) |hop| {
                const item = source.hops[hop];
                try slot.name.setTextContent(self.cx.allocator, item.name);
                try slot.endpoint.setTextContent(self.cx.allocator, if (hop + 1 == source.hops.len) "目标主机" else try formatEndpoint(&buffer, item));
                try slot.user.setTextContent(self.cx.allocator, try std.fmt.bufPrint(&buffer, "身份  {s}", .{item.user}));
                try self.fullValueTip(slot.tip_content, slot.tip_label, item, slot.node);
                const latest = self.latestEvent(hop);
                var label: []const u8 = if (source.state == .retrying) "等待整链重建" else "等待上游";
                var color = S.theme.current().fg_2;
                if (source.attached) {
                    label = @import("../../../../shared/base/connection_presenter.zig").present(.connected).label;
                    color = S.theme.current().ok;
                } else if (fault != null and fault.?.hop != null and hop > fault.?.hop.?) {
                    label = "受阻 · 未连接";
                } else if (fault != null and fault.?.hop == hop) {
                    label = if (source.cleanup == .released) "连接失败 · 已断开" else "连接失败";
                    color = S.theme.current().danger_ink;
                } else if (latest) |event| {
                    if (source.cleanup == .released) label = "已断开" else if (source.cleanup == .releasing) label = "正在断开" else if (source.cleanup == .unknown) label = "断开结果待确认" else if (event.phase == .ready and event.status == .succeeded) {
                        label = if (hop + 1 == source.hops.len) "协议已就绪" else "已认证";
                        color = S.theme.current().ok;
                    } else {
                        label = try std.fmt.bufPrint(&buffer, "{s}{s}", .{ phaseName(event.phase), if (event.status == .succeeded) "完成" else "中" });
                        color = S.theme.current().accent_ink;
                    }
                }
                try slot.status.setTextContent(self.cx.allocator, label);
                self.ink(slot.status, color);
                const current = source.state != .failed and source.state != .cancelled and !self.cancel_requested and source.cleanup == .not_started and if (self.latestEvent(null)) |event| event.hop == hop and !(event.phase == .ready and event.status == .succeeded) else false;
                if (current and self.filter != hop) card_style.background = S.theme.current().accent.withAlpha(18);
                const mark = if (fault != null and fault.?.hop == hop) ui.icons.circle_alert else if (current) ui.icons.get("circle-dot").? else if (latest != null and latest.?.phase == .ready and latest.?.status == .succeeded) ui.icons.circle_check else ui.icons.get("circle").?;
                setMarker(slot.marker, mark, color);
            } else {
                try slot.name.setTextContent(self.cx.allocator, "本机");
                try slot.endpoint.setTextContent(self.cx.allocator, "连接起点");
                try slot.user.setTextContent(self.cx.allocator, "连接来源  本机进程");
                try slot.tip_label.setTextContent(self.cx.allocator, "本机\n连接起点");
                slot.tip_content.behavior.interaction.a11y.?.label = slot.tip_label.getText().?.content;
                try slot.status.setTextContent(self.cx.allocator, if (source.local_ready) "已就绪" else "准备中");
                self.ink(slot.status, if (source.local_ready) S.theme.current().ok_ink else S.theme.current().fg_2);
                setMarker(slot.marker, if (source.local_ready) ui.icons.circle_check else ui.icons.get("circle").?, if (source.local_ready) S.theme.current().ok else S.theme.current().fg_2);
            }
            slot.skin.set(card_style);
        }
    }
    fn fullValueTip(self: *View, content: *ui.Node, label: *ui.Node, hop: Hop, button_node: ?*ui.Node) !void {
        var address: [2048]u8 = undefined;
        const full = try std.fmt.allocPrint(self.cx.allocator, "{s}\n{s}", .{ hop.name, try formatEndpoint(&address, hop) });
        defer self.cx.allocator.free(full);
        try label.setTextContent(self.cx.allocator, full);
        content.behavior.interaction.a11y.?.label = label.getText().?.content;
        if (button_node) |node| node.behavior.interaction.a11y.?.label = label.getText().?.content;
    }
    fn refreshSummary(self: *View) !void {
        const source = self.source.?.value;
        const fault = self.currentFailure();
        self.summary.setStyleInline(self.cx.allocator, S.notice(fault != null or source.state == .failed));
        self.summary_title.setTextColor(if (fault != null or source.state == .failed) S.theme.current().danger_ink else S.theme.current().fg_1);
        self.cancel_button.?.setDisplay(if (source.state == .failed or source.state == .cancelled) .none else .flex);
        self.close_button.?.setDisplay(if (source.state == .failed or source.state == .cancelled) .flex else .none);
        self.retry_button.?.setDisplay(if (source.state == .failed) .flex else .none);
        self.edit_button.?.setDisplay(if (source.state == .failed and self.canEdit()) .flex else .none);
        try self.footer_hint.setTextContent(self.cx.allocator, if (source.state == .failed or source.state == .cancelled or self.cancel_requested) switch (source.cleanup) {
            .not_started => "正在确认连接状态",
            .releasing => "正在结束上一次连接…",
            .unknown => "连接结束状态待核实",
            .released => "",
        } else close_cancels);
        self.cancel_text.?.set(if (self.cancel_requested) "正在取消…" else "取消连接");
        self.retry_text.?.set(if (source.state == .failed and source.cleanup == .unknown) "暂不可重试" else if (source.state == .failed and source.cleanup != .released) "等待连接结束" else "重新连接");
        if (self.header_close) |button_node| {
            // panel-heads：关闭按钮提示统一为“关闭 · Esc”，进行中“关闭即取消连接”的后果写在无障碍名与底栏说明里。
            button_node.behavior.interaction.a11y.?.label = if (source.state == .failed or source.state == .cancelled) "关闭连接结果" else close_cancels;
        }
        var title = std.Io.Writer.Allocating.init(self.cx.allocator);
        defer title.deinit();
        var detail = std.Io.Writer.Allocating.init(self.cx.allocator);
        defer detail.deinit();
        if (fault) |failure| {
            try title.writer.print("{s}失败", .{if (failure.phase) |phase| phaseName(phase) else "连接"});
            try detail.writer.writeAll(failure.reason);
            if (source.hops.len > 1) if (failure.hop) |hop| try detail.writer.print("\n第 {d} 跳 · {s}", .{ hop + 1, source.hops[hop].name });
            if (failure.hop) |hop| if (hop + 1 < source.hops.len) {
                try detail.writer.writeAll("\n后续受阻：");
                for (source.hops[hop + 1 ..], 0..) |item, index| {
                    if (index != 0) try detail.writer.writeAll("、");
                    try detail.writer.writeAll(item.name);
                }
                try detail.writer.writeAll("。");
            };
        } else if (source.attached) {
            try title.writer.writeAll("已接入会话");
            try detail.writer.writeAll("连接已就绪，可以开始使用。");
        } else if (self.cancel_requested or source.state == .cancelled) {
            try title.writer.writeAll(if (source.cleanup == .released) "连接已取消" else "正在取消连接");
            try detail.writer.writeAll(cleanupText(source.cleanup));
        } else if (source.file_session) {
            try title.writer.writeAll("正在连接 SFTP");
            try detail.writer.writeAll(source.activity);
        } else if (source.state == .protocol_ready or source.state == .attaching) {
            try title.writer.writeAll("协议已就绪，正在接入会话");
            try detail.writer.writeAll("等待会话接入结果。");
        } else if (source.state == .retrying and source.cleanup == .released) {
            try title.writer.writeAll("正在准备重试连接");
            try detail.writer.writeAll("上次连接未完成，将自动重建完整链路。");
        } else if (source.state == .waiting_auth) {
            try title.writer.writeAll("需要完成身份认证");
            try detail.writer.writeAll("请完成服务器要求的身份认证后继续。");
        } else if (source.state == .waiting_host_key) {
            try title.writer.writeAll("需要确认主机身份");
            try detail.writer.writeAll("核对服务器指纹，确认后继续连接。");
        } else if (self.latestEvent(null)) |event| {
            if (event.status == .succeeded and event.phase != .ready) {
                try title.writer.print("{s}已完成", .{phaseName(event.phase)});
                try detail.writer.writeAll("等待下一阶段的连接结果。");
            } else {
                try title.writer.writeAll(switch (event.phase) {
                    .transport => "正在建立网络连接",
                    .tunnel => "正在建立跳板隧道",
                    .handshake => "正在进行 SSH 握手",
                    .host_key => "正在核对主机身份",
                    .authentication => "正在验证登录身份",
                    .shell => "正在准备终端",
                    .ready => "正在接入会话",
                });
                try detail.writer.writeAll(switch (event.phase) {
                    .transport => "等待目标服务器响应。",
                    .tunnel => "正在建立通往下一节点的转发通道。",
                    .handshake => "正在协商 SSH 协议和加密方式。",
                    .host_key => "正在校验服务器主机密钥。",
                    .authentication => "等待服务器确认认证结果。",
                    .shell => "SSH 认证已完成，正在创建终端通道。",
                    .ready => "协议已就绪，等待会话接入结果。",
                });
            }
            if (source.hops.len > 1) try detail.writer.print("\n第 {d} 跳 · {s}。", .{ event.hop + 1, source.hops[event.hop].name });
            if (event.hop + 1 < source.hops.len) try detail.writer.writeAll(if (source.state == .retrying) "其余节点等待整链重建。" else "其余节点等待上游完成。");
        } else {
            try title.writer.writeAll(if (source.state == .retrying) "正在从 Local 重建完整链路" else "正在准备连接");
            try detail.writer.writeAll("等待当前连接的阶段结果。");
        }
        try self.summary_title.setTextContent(self.cx.allocator, title.writer.buffered());
        try self.summary_detail.setTextContent(self.cx.allocator, detail.writer.buffered());
    }
    fn refreshResources(self: *View) !void {
        const source = self.source.?.value;
        const shown = source.cleanup == .releasing or source.cleanup == .unknown;
        self.resource_box.setDisplay(if (shown) .flex else .none);
        if (!shown) return;
        var text = std.Io.Writer.Allocating.init(self.cx.allocator);
        defer text.deinit();
        try text.writer.writeAll(cleanupText(source.cleanup));
        if (source.resources) |resources| {
            for (resources.resources[0..resources.hop_count], 0..) |hop, index| for (hop, 0..) |entry, kind| {
                if (entry.state == .absent or entry.state == .released) continue;
                try text.writer.print("\n第 {d} 跳 {s} · {s}：{s}", .{ index + 1, source.hops[index].name, resourceName(@fromBackingInt(@intCast(kind))), switch (entry.state) {
                    .owned => "仍由本次连接持有",
                    .releasing => "正在释放",
                    .unknown => "待核实",
                    else => unreachable,
                } });
            };
            if (resources.retained_count != 0) try text.writer.print("\n仍有 {d} 项连接资源等待释放。", .{resources.retained_count});
            if (resources.overflowed) try text.writer.writeAll("\n部分资源状态无法核实。");
        }
        try self.resource_text.setTextContent(self.cx.allocator, text.writer.buffered());
    }
    fn refreshLogs(self: *View) !void {
        try self.refreshLogRows();
        self.copy_disabled.set(self.logCount() == 0);
        if (self.copy_result) |success| {
            try self.log_help.setTextContent(self.cx.allocator, if (success) "已复制连接日志" else "复制失败，请重试");
            self.log_help.setTextColor(if (success) S.theme.current().ok_ink else S.theme.current().danger_ink);
            return;
        }
        self.log_help.setTextColor(S.theme.current().fg_2);
        var label: [256]u8 = undefined;
        try self.log_help.setTextContent(self.cx.allocator, if (self.filter) |hop| try std.fmt.bufPrint(&label, "第 {d} 跳", .{hop + 1}) else "");
        const drop_count = @max(self.source.?.value.dropped, self.source.?.value.journal.dropped);
        if (drop_count != 0) try self.log_help.setTextContent(self.cx.allocator, try std.fmt.bufPrint(&label, "已省略 {d} 条旧日志", .{drop_count}));
    }
    fn closeLogTip(self: *View) void {
        self.diagnostic_open.set(false);
        self.diagnostic_row = null;
    }
    fn diagnosticAnchor(raw: *anyopaque) ui.widgets.popover.AnchorRect {
        const self: *View = @ptrCast(@alignCast(raw));
        const row = self.diagnostic_row orelse return .{ .x = 0, .y = 0, .w = 0, .h = 0 };
        const rect = row.node.globalRect();
        return .{ .x = rect.x, .y = rect.y, .w = rect.w, .h = rect.h };
    }
    fn showDiagnostic(self: *View, row: *LogRow) !void {
        if (!self.visible or !self.logs_expanded or row.record.entry.status != .failed or row.record.entry.diagnostic.len == 0) return;
        var text = std.Io.Writer.Allocating.init(self.cx.allocator);
        defer text.deinit();
        try text.writer.print("尝试 {d} · 第 {d} 跳 · {s}\n", .{ row.record.key.attempt_id.?, row.record.entry.hop + 1, phaseName(row.record.entry.phase) });
        try row.record.entry.writeDiagnostic(&text.writer);
        try self.diagnostic_text.setTextContent(self.cx.allocator, text.writer.buffered());
        self.diagnostic_row = row;
        self.diagnostic_open.set(true);
        self.cx.requestRedraw();
    }
    fn refreshLogRows(self: *View) !void {
        var all = std.Io.Writer.Allocating.init(self.cx.allocator);
        defer all.deinit();
        try self.writeLogRecords(&all.writer, true);
        const hash = std.hash.Wyhash.hash(0, all.writer.buffered());
        if (self.log_rows_hash == hash) return;
        self.closeLogTip();
        self.clearNodes(self.logs_scroll.content);
        self.log_row_count = 0;
        var style = S.text(10.5, 400, false);
        style.line_height = 16.0 / 10.5;
        style.use_monospace_font = true;
        style.wrap = .word;
        style.text_overflow = .clip;
        for (0..self.logCount()) |index| {
            const record = self.logAt(index);
            if (self.filter) |hop| if (record.entry.hop != hop) continue;
            var line = std.Io.Writer.Allocating.init(self.cx.allocator);
            defer line.deinit();
            try writeLogRecord(&line.writer, record, false);
            const row = &self.log_rows[self.log_row_count];
            const node = try ui.box(self.cx, S.logRow(), .{});
            const label = try self.appendLabel(node, std.mem.trimEnd(u8, line.writer.buffered(), "\n"), style);
            try @import("../../../../shared/ui/styles/log_typography.zig").apply(self.cx, label);
            row.* = .{ .view = self, .record = record, .node = node, .text = label };
            self.log_row_count += 1;
            const has_diagnostic = record.entry.status == .failed and record.entry.diagnostic.len != 0;
            node.meta.ownership.meta.test_id = if (has_diagnostic) "connection.progress.logs.failure" else "connection.progress.logs.row";
            if (has_diagnostic) {
                node.behavior.events.on_hover = self.cx.on(LogRow, row, LogRow.hover);
                node.behavior.events.on_leave = self.cx.on(LogRow, row, LogRow.leave);
            }
            try self.logs_scroll.content.appendChild(self.cx.allocator, node);
        }
        if (self.log_row_count == 0) _ = try self.appendLabel(self.logs_scroll.content, "暂无当前节点的阶段日志", style);
        self.log_rows_hash = hash;
    }
    fn writeLogs(self: *View, writer: *std.Io.Writer) !void {
        const source = self.source.?.value;
        if (source.failure) |fault| try writer.print("失败原因：{s}\n", .{fault.reason});
        if (source.file_session) try writer.print("SFTP：{s}\n", .{source.activity});
        try self.writeLogRecords(writer, true);
    }
    fn writeLogRecords(self: *View, writer: *std.Io.Writer, include_raw: bool) !void {
        for (0..self.logCount()) |index| {
            const record = self.logAt(index);
            if (self.filter) |hop| if (record.entry.hop != hop) continue;
            try writeLogRecord(writer, record, include_raw);
        }
    }
    fn logCount(self: *const View) usize {
        const source = self.source.?.value;
        return if (source.logs.len != 0) source.logs.len else source.journal.count;
    }
    fn logAt(self: *const View, index: usize) LogRecord {
        const source = self.source.?.value;
        return if (source.logs.len != 0) source.logs[index] else .{ .key = source.key, .entry = source.journal.entries[index] };
    }
    fn updateLogMarker(self: *View) void {
        const count = self.logCount();
        if (count == 0) return;
        const last = self.logAt(count - 1);
        if (self.last_marker) |marker| {
            if (!marker.key.eql(last.key) or marker.sequence != last.entry.sequence) {
                self.copy_result = null;
                var added = count;
                for (0..count) |index| {
                    const entry = self.logAt(index);
                    if (entry.key.eql(marker.key) and entry.entry.sequence == marker.sequence) {
                        added = count - index - 1;
                        break;
                    }
                }
                if (!self.following) self.new_logs +|= added;
            }
        }
        self.last_marker = .{ .key = last.key, .sequence = last.entry.sequence };
    }
    fn observeUserScroll(self: *View) void {
        const state = self.logs_scroll.state;
        if (@abs(state.scroll_y - self.last_scroll_y) < 0.5) return;
        self.closeLogTip();
        self.following = state.scroll_y >= state.maxScrollY() - 1;
        if (self.following) self.new_logs = 0;
        self.last_scroll_y = state.scroll_y;
    }
    fn syncLogScroll(self: *View) void {
        const scroll = self.logs_scroll;
        self.observeUserScroll();
        scroll.state.content_height = scroll.content.globalRect().h;
        scroll.state.viewport_height = scroll.container.globalRect().h;
        if (self.following) ui.widgets.scroll_area.setScrollY(scroll.state, scroll.content, scroll.state.maxScrollY());
        self.last_scroll_y = scroll.state.scroll_y;
        self.jump_button.setDisplay(if (self.logs_expanded and !self.following) .flex else .none);
        var buffer: [80]u8 = undefined;
        const label = if (self.new_logs == 0) "回到底部" else std.fmt.bufPrint(&buffer, "{d} 条新日志 · 回到底部", .{self.new_logs}) catch "有新日志 · 回到底部";
        if (!std.mem.eql(u8, self.jump_label.getText().?.content, label)) self.jump_label.setTextContent(self.cx.allocator, label) catch {};
    }
    fn resize(self: *View) void {
        const source = if (self.source) |source| source.value else return;
        const natural = self.body_scroll.content.globalRect().h;
        const fallback = if (self.currentFailure() != null or source.state == .failed) S.failed_height else S.normal_height;
        const pane_h = self.root.globalRect().h;
        const available = (if (pane_h > 0) pane_h else self.cx.viewport.height) - 2 * S.pane_inset;
        const height = @min(if (natural > 0) natural + S.chrome_height else fallback, @max(100, available));
        const pane_w = self.root.globalRect().w;
        const panel = S.panel(height, if (pane_w > 0) pane_w else self.cx.viewport.width);
        if (!std.meta.eql(self.dialog.style.width, panel.width.?) or !std.meta.eql(self.dialog.style.height, panel.height.?)) self.dialog.setStyleInline(self.cx.allocator, panel);
    }
    fn afterLayout(raw: *anyopaque, _: u8, _: bool) ui.AfterLayoutResult {
        const self: *View = @ptrCast(@alignCast(raw));
        if (!self.visible) return .done;
        // A failed card's host may be deleted (or edited) while it is shown.
        if (self.failure) |view| if (self.failureMode() and view.isShown() and view.projection.peek().can_edit != self.canEdit()) {
            self.refreshFailure() catch {};
            return .needs_layout;
        };
        if (self.edit_button) |edit_node| if (self.source) |owned| {
            const editable = owned.value.state == .failed and self.canEdit();
            if ((edit_node.style.display != .none) != editable) {
                edit_node.setDisplay(if (editable) .flex else .none);
                return .needs_layout;
            }
        };
        const compact = self.cx.viewport.width <= 860 or self.cx.viewport.height <= 480;
        if (compact != self.compact) {
            self.compact = compact;
            self.header.setStyleInline(self.cx.allocator, S.attemptHeader(compact));
            self.body.setStyleInline(self.cx.allocator, S.body(compact));
            self.footer.setStyleInline(self.cx.allocator, S.footer(compact));
            return .needs_layout;
        }
        // Native widget style replay can restore Modal's default 16px inset
        // after mount. Normalize the public slot before accepting its layout.
        if (!std.meta.eql(self.modal_body.style.padding, ui.Padding{})) {
            self.modal_body.setStyle(self.cx.allocator, .padding, ui.Padding{});
            return .needs_layout;
        }
        const before_width = self.dialog.style.width;
        const before = self.dialog.style.height;
        self.resize();
        if (self.logs_expanded) self.syncLogScroll();
        return if (std.meta.eql(before_width, self.dialog.style.width) and std.meta.eql(before, self.dialog.style.height)) .done else .needs_layout;
    }
    fn latestEvent(self: *const View, hop: ?usize) ?progress.Journal.Entry {
        const journal = &self.source.?.value.journal;
        var index = journal.count;
        while (index > 0) {
            index -= 1;
            const entry = journal.entries[index];
            if (hop == null or entry.hop == hop.?) return entry;
        }
        return null;
    }
    fn currentFailure(self: *const View) ?Failure {
        const source = self.source.?.value;
        if (source.failure) |fault| {
            var result = fault;
            result.reason = inlineFailureText(fault.reason, if (source.journal.failure) |entry| entry.diagnostic.len != 0 else false);
            return result;
        }
        if (source.state == .retrying or source.state == .cancelled) return null;
        const fault = source.journal.failure orelse return null;
        if (fault.status != .failed) return null;
        return .{ .hop = fault.hop, .phase = fault.phase, .reason = inlineFailureText(failureText(fault.failure), fault.diagnostic.len != 0) };
    }
    fn canDismiss(self: *const View) bool {
        const source = if (self.source) |source| source.value else return false;
        return (source.state == .failed or source.state == .cancelled) and source.cleanup == .released;
    }
    fn canRetry(self: *const View) bool {
        const source = if (self.source) |source| source.value else return false;
        if (source.attached or source.state != .failed or source.cleanup != .released) return false;
        const resources = source.resources orelse return source.file_session;
        return resources.released() and !resources.hasUnknown();
    }
    fn copyFeedback(self: *View, success: bool) void {
        self.copy_feedback.report(success);
        self.copy_result = success;
        self.log_help.setTextContent(self.cx.allocator, if (success) "已复制连接日志" else "复制失败，请重试") catch {};
        self.log_help.setTextColor(if (success) S.theme.current().ok_ink else S.theme.current().danger_ink);
        self.cx.requestRedraw();
    }
    /// Escape bubbling out of the card: the inline authentication form owns
    /// its own Escape (composition first, then its request); anywhere else in
    /// the card it is the card's close/cancel action.
    fn paneKey(key: ui.events.KeyCode, _: ui.events.Modifiers, raw: ?*anyopaque) ui.events.EventResult {
        const self: *View = @ptrCast(@alignCast(raw orelse return .ignored));
        if (key != .escape or !self.visible) return .ignored;
        if (self.cx.focus_manager.getFocused()) |focused| {
            var ancestor: ?*ui.Node = focused;
            while (ancestor) |node| : (ancestor = node.parent) if (node == self.authentication_area) return .ignored;
        }
        self.close();
        return .stop;
    }
    /// Host placement: `on_screen` is false while the session's pane is not
    /// displayed (another tab is active); the attempt stays logically open.
    pub fn place(self: *View, frame: ?ui.types.ComputedRect, on_screen: bool) void {
        self.setFrame(frame);
        if (self.placed == on_screen) return;
        self.placed = on_screen;
        self.present(self.visible and self.open.peek());
    }
    fn present(self: *View, requested: bool) void {
        const shown = requested and self.placed;
        const was = self.root.style.display != .none;
        self.root.setDisplay(if (shown) .flex else .none);
        self.root.setHitTestVisible(shown);
        if (shown and !was) {
            // The card replaces the pane's content: keyboard focus follows it
            // (the former modal's auto focus), so Escape and Tab reach it.
            if (self.cx.focus_manager.getFocused()) |focused| {
                var ancestor: ?*ui.Node = focused;
                while (ancestor) |node| : (ancestor = node.parent) if (node == self.root) return;
            }
            if (self.failure) |view| if (self.failureMode()) return self.cx.setFocus(view.root);
            self.cx.setFocus(self.dialog);
        }
    }
    /// Host placement: the session pane's rect in window coordinates; null
    /// fills the window (headless hosts and tests).
    pub fn setFrame(self: *View, frame: ?ui.types.ComputedRect) void {
        const style: ui.BoxStyle = if (frame) |rect| .{ .inset = .{ .left = .{ .px = rect.x }, .top = .{ .px = rect.y } }, .width = .{ .px = rect.w }, .height = .{ .px = rect.h } } else .{ .inset = .{ .left = .{ .px = 0 }, .top = .{ .px = 0 } }, .width = .fill(), .height = .fill() };
        if (std.meta.eql(self.root.style.width, style.width.?) and std.meta.eql(self.root.style.height, style.height.?) and std.meta.eql(self.root.style.inset(), style.inset.?)) return;
        self.root.setStyleInline(self.cx.allocator, style);
        self.cx.requestRedraw();
    }
    fn clearNodes(self: *View, parent: *ui.Node) void {
        while (parent.children.items.len != 0) {
            const child = parent.children.items[parent.children.items.len - 1];
            self.cx.detachChild(parent, child);
            self.cx.freeNode(child);
        }
    }
    fn appendLabel(self: *View, parent: *ui.Node, text: []const u8, style: ui.TextStyle) !*ui.Node {
        const node = try ui.text(self.cx, text, style);
        node.setStyleInline(self.cx.allocator, .{ .width = .fill(), .height = .{ .fit = .{} }, .min_height = style.font_size * style.line_height, .flex_shrink = 0 });
        try parent.appendChild(self.cx.allocator, node);
        return node;
    }
    /// Hop rows are ghost Buttons whose label ink cascades to every text
    /// inside; a row's own inks (status/address) are set on the node itself.
    fn ink(self: *View, node: *ui.Node, color: ui.Color) void {
        node.setTextColor(color);
        node.setStyleInline(self.cx.allocator, .{ .text_color = color });
    }
    fn cardLabel(self: *View, parent: *ui.Node, height: f32, style: ui.TextStyle) !*ui.Node {
        const node = try self.appendLabel(parent, "", style);
        node.setStyleInline(self.cx.allocator, .{ .width = .fill(), .height = .{ .px = height }, .min_width = 0, .flex_shrink = 0 });
        return node;
    }
    fn button(self: *View, parent: *ui.Node, scope: *ui.Scope, ctx: *ActionContext, label_text: []const u8, primary: bool, disabled: ?*ui.Signal(bool), comptime callback: *const fn (*ActionContext) void, id: []const u8) !*ui.Node {
        // Native footer Button: zenit's default look, label and states.
        const variant: ui.widgets.button.ButtonVariant = if (primary) .primary else .secondary;
        const source: ui.Source(bool) = if (disabled) |signal| .{ .signal = signal } else .{ .value = false };
        const caption = try scope.createText(label_text, .{});
        const node = try ui.widgets.Button(.{ .label = caption, .variant = variant, .a11y_label = label_text, .disabled = source, .on_click = self.cx.on(ActionContext, ctx, callback) }).mount(scope, self.cx);
        node.meta.ownership.meta.test_id = id;
        const button_label = findLabel(node).?;
        if (std.mem.eql(u8, id, "connection.progress.cancel")) self.cancel_text = caption;
        if (std.mem.eql(u8, id, "connection.progress.retry")) self.retry_text = caption;
        if (std.mem.eql(u8, id, "connection.progress.cancel")) self.cancel_label = button_label;
        if (std.mem.eql(u8, id, "connection.progress.dismiss")) self.close_label = button_label;
        if (std.mem.eql(u8, id, "connection.progress.retry")) self.retry_label = button_label;
        try parent.appendChild(self.cx.allocator, node);
        return node;
    }
    fn findLabel(node: *ui.Node) ?*ui.Node {
        if (node.getText() != null) return node;
        for (node.children.items) |child| if (findLabel(child)) |found| return found;
        return null;
    }
    fn cleanup(self: *View) void {
        self.cx.removeAfterLayoutHook(self);
        if (self.source) |*source| source.deinit();
        self.cx.allocator.destroy(self);
    }
};

fn writeLogRecord(writer: *std.Io.Writer, record: LogRecord, include_raw: bool) !void {
    try record.entry.writeLine(writer, "{s} · {s} · {s}:{d} · 第 {d} 跳 · 尝试 {d} · #{d}", .{ phaseName(record.entry.phase), switch (record.entry.status) {
        .started => "进行中",
        .succeeded => "完成",
        .failed => inlineFailureText(failureText(record.entry.failure), record.entry.diagnostic.len != 0),
        .cancelled => "已取消",
    }, record.entry.hostSlice(), record.entry.port, record.entry.hop + 1, record.key.attempt_id.?, record.entry.sequence });
    if (include_raw) try record.entry.writeDiagnostic(writer);
}

fn validate(snapshot: *const Snapshot) !void {
    const attempt = snapshot.key.attempt_id orelse return error.InvalidProgressIdentity;
    if (attempt == 0 or snapshot.key.operation_id == 0 or snapshot.journal.attempt != attempt) return error.InvalidProgressIdentity;
    if (snapshot.hops.len == 0 or snapshot.hops.len > S.max_hops or snapshot.journal.count > progress.Journal.capacity or snapshot.logs.len > progress.Journal.capacity) return error.InvalidProgressSnapshot;
    for (snapshot.journal.entries[0..snapshot.journal.count]) |entry| if (entry.hop >= snapshot.hops.len or entry.hop_count != snapshot.hops.len or entry.diagnostic.len > entry.diagnostic.bytes.len) return error.InvalidProgressSnapshot;
    if (snapshot.journal.failure) |entry| if (entry.hop >= snapshot.hops.len or entry.hop_count != snapshot.hops.len or entry.diagnostic.len > entry.diagnostic.bytes.len) return error.InvalidProgressSnapshot;
    if (snapshot.failure) |fault| if (fault.hop) |hop| if (hop >= snapshot.hops.len) return error.InvalidProgressSnapshot;
    if (snapshot.resources) |resources| {
        const key = resources.key orelse return error.InvalidResourceOwner;
        if (!key.eql(snapshot.key) or resources.hop_count != snapshot.hops.len) return error.InvalidResourceOwner;
    }
    for (snapshot.logs) |record| {
        if (!sameLogicalOwner(record.key, snapshot.key) or record.key.attempt_id == null or record.entry.hop >= record.entry.hop_count or record.entry.hop_count > S.max_hops or record.entry.diagnostic.len > record.entry.diagnostic.bytes.len) return error.InvalidLogOwner;
        if (older(snapshot.key, record.key)) return error.InvalidLogOwner;
    }
    if (snapshot.attached and snapshot.key.owner != .session) return error.InvalidAttachmentOwner;
}
/// Two attempts of the same logical connection (a session's automatic / manual retries, one app operation).
pub fn sameLogicalOwner(a: OperationKey, b: OperationKey) bool {
    if (a.owner == .session and b.owner == .session) return a.owner.session.session_id == b.owner.session.session_id;
    if (a.owner == .app and b.owner == .app) return a.operation_id == b.operation_id;
    return a.owner.eql(b.owner);
}
fn older(a: OperationKey, b: OperationKey) bool {
    if (a.owner == .session and b.owner == .session and a.owner.session.generation != b.owner.session.generation) return a.owner.session.generation < b.owner.session.generation;
    if (a.operation_id != b.operation_id) return a.operation_id < b.operation_id;
    return a.attempt_id.? < b.attempt_id.?;
}
pub fn phaseName(phase: progress.Phase) []const u8 {
    return switch (phase) {
        .transport => "TCP 连接",
        .tunnel => "隧道建立",
        .handshake => "SSH 握手",
        .host_key => "主机密钥核对",
        .authentication => "SSH 认证",
        .shell => "终端准备",
        .ready => "协议就绪",
    };
}
fn cleanupText(cleanup: operations.Cleanup) []const u8 {
    return switch (cleanup) {
        .not_started => "等待确认本次连接资源状态",
        .releasing => "本次链路资源正在释放",
        .released => "本次链路资源已释放",
        .unknown => "本次链路资源释放待核实",
    };
}
pub fn inlineFailureText(reason: []const u8, has_diagnostic: bool) []const u8 {
    const suffix = "（详情见应用日志）";
    return if (has_diagnostic and std.mem.endsWith(u8, reason, suffix)) reason[0 .. reason.len - suffix.len] else reason;
}
/// 失败原因的单行文案：只查 shared/base/error_text.zig 这一份目录（日志页同用）。
/// 目录没有收录的错误给通用说法；原始错误码只在日志与“复制日志”的详情里。
pub fn failureText(err: ?anyerror) []const u8 {
    const failure = err orelse return "连接失败";
    return @import("../../../../shared/base/error_text.zig").lineOr(failure, unknown_failure);
}
pub const unknown_failure = "连接失败，请查看连接日志中的错误码";
/// 进行中关闭的后果（底栏说明与关闭按钮的无障碍名）。
pub const close_cancels = "关闭窗口将取消本次连接";
fn prepareCustomButton(button: *ui.Node) void {
    for (button.children.items) |child| child.setDisplay(.none);
}
fn resourceName(kind: ssh.ResourceKind) []const u8 {
    return switch (kind) {
        .transport => "网络连接",
        .session => "SSH 会话",
        .shell => "终端通道",
        .tunnel => "隧道",
        .relay_socket => "转发连接",
        .relay_worker => "转发任务",
        .rtt_channel => "延迟检测通道",
        .execution_control => "SSH 执行控制通道",
        .bootstrap => "SSH 临时集成资源",
    };
}

fn setMarker(node: *ui.Node, asset: ui.SvgAsset, color: ui.Color) void {
    // Marker (UOmVj): the state glyph on a 22 circle of its subtle tint —
    // check (done), loader (current), x (failed), dashed circle (waiting).
    const glyph = if (std.meta.eql(asset.icon_id, ui.icons.circle_check.icon_id)) ui.icons.check else if (std.meta.eql(asset.icon_id, ui.icons.circle_alert.icon_id)) ui.icons.x else if (std.meta.eql(asset.icon_id, ui.icons.get("circle-dot").?.icon_id)) ui.icons.loader_circle else ui.icons.circle_dashed;
    if (glyph.icon_id) |id| if (glyph.pickRep(13)) |rep| node.setIcon(.{ .icon_id = id, .rep = rep, .tint = color });
    if (node.parent) |box| box.setBackground(color.withAlpha(28));
}

fn formatEndpoint(buffer: []u8, hop: Hop) ![]const u8 {
    const ipv6 = std.mem.indexOfScalar(u8, hop.host, ':') != null and !std.mem.startsWith(u8, hop.host, "[");
    if (ipv6) return std.fmt.bufPrint(buffer, "{s}@[{s}]:{d}", .{ hop.user, hop.host, hop.port });
    return std.fmt.bufPrint(buffer, "{s}@{s}:{d}", .{ hop.user, hop.host, hop.port });
}
