//! Main-thread presentation of an existing connection operation. The workspace
//! and SessionHost retain all protocol resources and allocate every identity.
const std = @import("std");
const ui = @import("ui");
const ThemeWatch = @import("../../../../shared/ui/theme/theme_watch.zig").ThemeWatch;
const Workspace = @import("../../../workspace/view/workspace.zig").Workspace;
const ApplicationHost = @import("../../../shell/host/application_host.zig").ApplicationHost;
const operations = @import("../../../../host/operation.zig");
const auth = @import("../../../../proto/ssh/auth_challenge.zig");
const Bridge = @import("../../../../plugins/remote/challenge_bridge.zig");
const Shared = @import("../../auth/host/challenge_window_host.zig").Services;
const Presenter = @import("../../auth/host/plugin_challenge_presenter.zig").Presenter;
const Progress = @import("../view/connection_progress_view.zig");
const theme = @import("../../../../shared/ui/theme/app_theme.zig");
const applog = @import("../../../../platform/applog.zig");
const AssetOwner = @import("../../../../host/identity.zig").AssetOwner;

pub const Host = struct {
    cx: *ui.Cx,
    workspace: *Workspace,
    application: *ApplicationHost,
    progress: *Progress.View,
    authentication: *Presenter,
    challenges: *Shared,
    bridge: Bridge.Bridge = .{},
    painted_colors: ?theme.Colors = null,
    /// Raised by the window's theme publication; consumed where this view repaints.
    theme_watch: ThemeWatch = .{},
    last_error: ?anyerror = null,
    /// The changed-host-key challenge currently answered from the failure
    /// view (design-r3 稿 1) instead of the protected challenge modal.
    host_key_request: ?auth.RequestIdentity = null,
    totp_clock: @import("../../../../proto/ssh/totp_prefill.zig").Clock = .{},

    /// Existing "edit host" entry (the connection editor window).
    editor: ?struct { context: *anyopaque, open: *const fn (*anyopaque, AssetOwner) anyerror!void } = null,

    /// ybb2B "编辑连接": a failed attempt opens its saved host in the editor.
    pub fn bindEditor(self: *Host, context: *anyopaque, open: *const fn (*anyopaque, AssetOwner) anyerror!void) void {
        self.editor = .{ .context = context, .open = open };
        self.progress.callbacks.edit = editConnection;
        self.progress.callbacks.can_edit = canEditConnection;
    }
    /// The attempt's saved asset, while it still exists in the registry.
    fn assetFor(self: *Host, key: operations.OperationKey) ?AssetOwner {
        if (key.owner != .session) return null;
        const id = self.application.legacyForHandle(key.owner.session) orelse return null;
        const index = self.workspace.tabIndex(id) orelse return null;
        const connection = self.workspace.tabs.items[index].sourceConnectionId() orelse return null;
        const asset = self.workspace.registry.indexOf(connection) orelse return null;
        return .{ .id = connection, .revision = self.workspace.registry.hosts[asset].revision };
    }
    fn canEditConnection(raw: *anyopaque, key: operations.OperationKey) bool {
        const self: *Host = @ptrCast(@alignCast(raw));
        return self.editor != null and self.assetFor(key) != null;
    }
    fn editConnection(raw: *anyopaque, key: operations.OperationKey) void {
        const self: *Host = @ptrCast(@alignCast(raw));
        const editor = self.editor orelse return;
        const owner = self.assetFor(key) orelse return;
        editor.open(editor.context, owner) catch |err| switch (err) {
            // Already open: the editor window was raised instead.
            error.WizardAlreadyOpen => {},
            else => applog.warn(.ui, "edit failed connection: {s}", .{@errorName(err)}),
        };
    }

    pub fn mount(cx: *ui.Cx, scope: *ui.Scope, workspace: *Workspace, application: *ApplicationHost) !*Host {
        // Mount runs outside a render/input entry. Inputs created below can
        // start transitions immediately; use this window's clock rather than
        // the last rendered window's (potentially much later) timestamp.
        cx.bindFrameClock();
        const self = try cx.allocator.create(Host);
        var registered = false;
        errdefer if (!registered) cx.allocator.destroy(self);
        self.* = .{ .cx = cx, .workspace = workspace, .application = application, .progress = undefined, .authentication = undefined, .challenges = try Shared.mount(cx, scope) };
        self.progress = try Progress.View.mount(cx, scope, .{ .context = self, .cancel = cancel, .retry = retry, .close = close, .copy_logs = copyLogs, .stop_retry = stopRetry, .retry_now = retryNow, .retry_with_credentials = retryWithCredentials, .trust_host_key = trustHostKey, .reject_host_key = rejectHostKey });
        self.authentication = self.challenges.view;
        try scope.onCleanup(Host, self, cleanup);
        registered = true;
        try self.theme_watch.bind(cx, scope);
        try cx.addAfterLayoutHook(self, hook);
        workspace.authentication_ui_ready = true;
        return self;
    }

    pub fn blocksGlobalActions(self: *const Host) bool {
        // The attempt card is pane content (not modal); only a protected
        // authentication challenge takes the window-wide keyboard.
        return self.bridge.visible();
    }

    fn hook(raw: *anyopaque, _: u8, _: bool) ui.AfterLayoutResult {
        const self: *Host = @ptrCast(@alignCast(raw));
        self.refresh() catch |err| {
            if (self.last_error == null or self.last_error.? != err) applog.warn(.ui, "connection presentation failed: {s}", .{@errorName(err)});
            self.last_error = err;
            return .done;
        };
        self.last_error = null;
        return .done;
    }

    fn refresh(self: *Host) !void {
        const colors = theme.current();
        if (self.theme_watch.take()) {
            try self.progress.retheme();
            self.painted_colors = colors;
        }
        const pending = self.workspace.pendingAuthentication();
        defer self.placeOnPane();
        if (try self.refreshFilePresentation(pending)) return;
        try self.refreshTerminal(pending);
    }

    /// Island B v3 i7VdGA / ybb2B: the attempt card is the connecting
    /// session's pane content. Align it with that tab's content rect; while
    /// another tab is shown the attempt stays open but off screen. A file
    /// connection can show progress before it has a tab or after cancellation.
    fn placeOnPane(self: *Host) void {
        const key = self.progress.operationKey() orelse return;
        const pane = self.ownerPane(key) orelse self.workspace.terminal_area;
        if (!pane.isDisplayedInTree()) return self.progress.place(null, false);
        const rect = pane.globalRect();
        if (rect.w <= 0 or rect.h <= 0) return self.progress.place(null, false);
        self.progress.place(rect, true);
    }

    fn ownerPane(self: *Host, key: operations.OperationKey) ?*ui.Node {
        if (key.owner != .session) return null;
        const id = self.application.legacyForHandle(key.owner.session) orelse return null;
        const index = self.workspace.tabIndex(id) orelse return null;
        return self.workspace.tabs.items[index].root;
    }

    fn capturedPaneShown(self: *Host, key: operations.OperationKey) bool {
        const pane = self.ownerPane(key) orelse return false;
        return pane.isDisplayedInTree();
    }

    fn refreshFilePresentation(self: *Host, pending: ?auth.Snapshot) !bool {
        // A later owner's prompt cannot replace the card currently being
        // read. Reconcile its actual attached/released receipt first.
        const captured = self.progress.operationKey();
        const file_key = blk: {
            const key = captured orelse break :blk self.application.fileProgressKey();
            if (self.application.fileConnectionProgress(key) != null) break :blk key;
            if (self.workspace.connectionProgress(key) == null) break :blk self.application.fileProgressKey();
            // A captured terminal attempt is the content of its own pane. While that pane is
            // not on screen (another tab is active) it does not hold the card against a file
            // attempt, which has no pane before ready: otherwise a saved SFTP connection opened
            // after a failed SSH attempt connects, fails and closes with no visible trace.
            // The terminal attempt takes the card again (nextConnectionPresentationKey) once
            // the file attempt is attached or dismissed.
            if (self.capturedPaneShown(key)) break :blk null;
            const file = self.application.fileProgressKey() orelse break :blk null;
            // The card keeps one owner while it is visible (ProgressOwnerMismatch): release
            // the off-screen terminal card first; its failure stays with its tab.
            self.progress.hide();
            break :blk file;
        };
        if (file_key) |key| {
            return self.refreshFile(key, pending);
        }
        return false;
    }

    // Terminal progress carries bounded route/history arrays. Keep its stack
    // frame out of the SFTP presentation path.
    fn refreshTerminal(self: *Host, pending: ?auth.Snapshot) !void {
        const captured = self.progress.operationKey();
        var source = if (captured) |key| self.workspace.connectionProgress(key) else null;
        if (captured) |old| if (source == null) {
            // The captured attempt is gone. When the next attempt to present is a successor of the same connection (an
            // automatic retry replaces the operation key), the card stays that session's pane content and is shown
            // with the new attempt below: hiding it in between would re-run its first-presentation focus grab and pull
            // keyboard focus back from wherever the person moved it on every retry. Only the old attempt's
            // authentication bridge goes.
            // Same choice as `key` below (a pending challenge first, then the next presentation key).
            const next = if (pending) |request| request.identity.key else self.workspace.nextConnectionPresentationKey();
            if (next != null and Progress.sameLogicalOwner(old, next.?)) self.bridge.clear() else self.hide();
        };
        const key = if (source) |current| current.key else if (pending) |request| request.identity.key else self.workspace.nextConnectionPresentationKey() orelse {
            self.hide();
            return;
        };
        if (source == null) source = self.workspace.connectionProgress(key);
        const current = source orelse {
            // File connections own their original authentication operation but
            // have no terminal ConnectJob/progress graph. Reuse the protected
            // modal directly; never synthesize a terminal resource snapshot.
            if (pending) |request| if (self.workspace.external_auth != null and self.workspace.authenticationHostFor(request.identity) != null) {
                self.progress.hide();
                var modal_request = request;
                modal_request.presentation = .otp_modal;
                try self.showAuthentication(modal_request);
                self.cx.scheduleRedrawAfterNs(33 * std.time.ns_per_ms);
                return;
            };
            self.hide();
            return;
        };
        if (current.attached) {
            const restore_focus = self.progress.isVisible() or self.bridge.current != null;
            self.hide();
            if (restore_focus) if (self.workspace.active_tab) |index| {
                const tab = self.workspace.tabs.items[index];
                if (tab.terminal) |*terminal| terminal.focus();
            };
            return;
        }
        const challenge = if (pending) |request| (if (request.identity.key.eql(key)) pending else null) else null;
        var hops: [9]Progress.Hop = undefined;
        var logs: [128]Progress.LogRecord = undefined;
        for (current.logs[0..current.log_count], logs[0..current.log_count]) |record, *destination| destination.* = .{ .key = record.key, .entry = record.entry };
        for (current.hops[0..current.hop_count], hops[0..current.hop_count]) |hop, *destination| destination.* = .{ .name = hop.name, .host = hop.host, .user = hop.user, .port = hop.port, .auth_mode = switch (hop.auth_mode) {
            .agent => .agent,
            .private_key => .private_key,
            .password => .password,
        }, .identity_file = hop.identity_file, .saved_password = hop.saved_password, .saved_passphrase = hop.saved_passphrase };
        const waiting = if (challenge) |request| request.identity.key.eql(key) else false;
        const is_host_key = if (challenge) |request| request.kind == .host_key_unknown or request.kind == .host_key_changed else false;
        // A changed host key is decided in the failure view (two labelled
        // fingerprints, danger-coloured trust) when its details are known.
        const changed_key: ?struct { request: auth.Snapshot, details: @import("../../../../host/host_key_confirmation.zig").Request } = if (challenge) |request| (if (waiting and request.kind == .host_key_changed) (if (self.workspace.authenticationHostKey(request.identity)) |details| .{ .request = request, .details = details } else null) else null) else null;
        const state: Progress.State = if (current.cancelled) .cancelled else if (current.automatic_retry_pending) .retrying else if (current.failure != null or current.attachment_failed) .failed else if (waiting) (if (is_host_key) .waiting_host_key else .waiting_auth) else if (current.journal.completed) (if (current.finished) .attaching else .protocol_ready) else if ((key.attempt_id orelse 1) > 1) .retrying else .connecting;
        const shown_failure: ?anyerror = if (current.failure) |err| err else current.pending_failure;
        const failure: ?Progress.Failure = if (shown_failure != null or current.attachment_failed) .{
            .hop = if (current.journal.failure) |entry| entry.hop else null,
            .phase = if (current.journal.failure) |entry| entry.phase else null,
            .reason = if (shown_failure) |err| Progress.failureText(err) else "终端接入失败",
            .err = shown_failure,
        } else if (changed_key) |decision| .{ .hop = decision.request.identity.hop_index, .phase = .host_key, .reason = "" } else null;
        const pending_retry: ?Progress.Retry = if (current.retry) |*value| .{ .next_attempt = value.next_attempt, .limit = value.limit, .remaining_ns = value.deadline_ns - @import("../../../../platform/realtime.zig").monotonicNs(), .delay_ns = value.delay_ns, .delays_ns = value.delays() } else null;
        const host_key: ?Progress.HostKeyPair = if (changed_key) |decision| .{
            .saved_algorithm = decision.details.old_algorithm[0..decision.details.old_algorithm_len],
            .saved_fingerprint = decision.details.old_fingerprint[0..decision.details.old_fingerprint_len],
            .offered_algorithm = decision.details.algorithmSlice(),
            .offered_fingerprint = decision.details.fingerprintSlice(),
        } else null;
        self.host_key_request = if (changed_key) |decision| decision.request.identity else null;
        // A protected challenge owns the active modal/focus trap. Reopening
        // progress while it is visible makes the password form inert.
        if (waiting and changed_key == null) self.progress.hide() else try self.progress.show(.{ .key = key, .hops = hops[0..current.hop_count], .journal = current.journal, .logs = logs[0..current.log_count], .dropped = current.dropped, .resources = current.resources, .state = state, .cleanup = current.cleanup, .attached = current.attached, .local_ready = true, .inline_authentication = false, .failure = failure, .retry = pending_retry, .host_key = host_key, .connect_timeout_sec = current.connect_timeout_sec });
        if (changed_key != null) {
            self.bridge.clear();
        } else if (challenge) |request| {
            try self.showAuthentication(request);
        } else {
            self.bridge.clear();
        }
        // A failure/cancellation is idle only after cleanup settles. Polling a
        // released result at 30 Hz keeps the failure modal and CPU active.
        if ((state != .failed and state != .cancelled) or current.cleanup == .not_started or current.cleanup == .releasing)
            self.cx.scheduleRedrawAfterNs(33 * std.time.ns_per_ms);
    }

    fn showAuthentication(self: *Host, request: auth.Snapshot) !void {
        const host = self.workspace.authenticationHostFor(request.identity) orelse return error.StaleAuthentication;
        const ns = @import("../../../../platform/realtime.zig").monotonicNs();
        try self.bridge.sync(&self.challenges.host, request, .{ .allow_save_password = @backingInt(host.connection_id) != 0, .display_name = host.name, .private_key_path = host.identity_file orelse "", .host_key = self.workspace.authenticationHostKey(request.identity) }, .{ .context = self, .submit = submitAuthentication, .save_password = savePassword, .cancel = cancelAuthentication }, @intCast(@max(0, ns) / std.time.ns_per_ms));
        if (self.workspace.authenticationTotp(request.identity, self.totp_clock.now()) catch null) |proposed| {
            var value = proposed;
            defer value.deinit();
            if (value.validAt(self.totp_clock.now())) _ = try self.authentication.prefill(Bridge.Bridge.owner(request.identity), request.identity.request_id, Bridge.Bridge.generation(request.identity), value.code.slice(), value.window, value.expires_at_ns, .{ .context = self, .valid = prefillValid });
        }
    }

    fn refreshFile(self: *Host, key: operations.OperationKey, pending: ?auth.Snapshot) !bool {
        if (key.owner != .session) return false;
        const state = self.application.sessions.queryState(key.owner.session) orelse return false;
        if (!state.create_operation.eql(key)) return false;
        if (state.lifecycle == .attached or state.lifecycle == .closed or state.lifecycle == .ended) {
            self.application.dismissFileProgress(key);
            self.hide();
            return false;
        }
        const diagnostic = self.application.fileConnectionProgress(key) orelse return false;
        if (pending) |request| if (self.workspace.authenticationHostFor(request.identity) != null) {
            self.progress.hide();
            var modal_request = request;
            modal_request.presentation = .otp_modal;
            try self.showAuthentication(modal_request);
            self.cx.scheduleRedrawAfterNs(33 * std.time.ns_per_ms);
            return true;
        };
        self.bridge.clear();
        const source = try self.application.fileSource(key.owner.session, key);
        var reason: [1536]u8 = undefined;
        const fault = diagnostic.failure;
        const failure: ?Progress.Failure = if (fault) |value| .{
            .hop = if (diagnostic.journal.failure) |entry| entry.hop else null,
            .phase = if (diagnostic.journal.failure) |entry| entry.phase else null,
            .reason = try std.fmt.bufPrint(&reason, "{s} · {s}（{s}）", .{ ApplicationHost.fileFailureText(value.code), value.stage orelse diagnostic.activity, value.code }),
        } else null;
        const saved = source.host;
        const hop: Progress.Hop = .{ .name = saved.name, .host = saved.host, .user = saved.user, .port = saved.port };
        try self.progress.show(.{
            .key = key,
            .hops = &.{hop},
            .journal = diagnostic.journal,
            .state = if (fault != null) .failed else if (state.lifecycle == .failed) .cancelled else if (diagnostic.journal.completed) .protocol_ready else .connecting,
            .cleanup = state.create_cleanup,
            .local_ready = true,
            .failure = failure,
            .file_session = true,
            .activity = diagnostic.activity,
        });
        // File connections have the same terminal-result contract as SSH:
        // preserve cleanup polling, then let the retained diagnostic go idle.
        if ((fault == null and state.lifecycle != .failed) or state.create_cleanup == .not_started or state.create_cleanup == .releasing)
            self.cx.scheduleRedrawAfterNs(33 * std.time.ns_per_ms);
        return true;
    }

    fn prefillValid(raw: *anyopaque, window: u64, expires_ns: ?i128) bool {
        const self: *Host = @ptrCast(@alignCast(raw));
        const now = self.totp_clock.now();
        return now.unix_seconds / @import("../../../../proto/ssh/totp.zig").period_seconds == window and (if (expires_ns) |expiry| now.monotonic_ns < expiry else true);
    }
    fn hide(self: *Host) void {
        self.bridge.clear();
        self.progress.hide();
    }
    fn savePassword(raw: *anyopaque, request: auth.Snapshot, password: []const u8) !void {
        const self: *Host = @ptrCast(@alignCast(raw));
        try self.workspace.saveAuthenticationPassword(request, password);
    }
    fn submitAuthentication(raw: *anyopaque, request: auth.RequestIdentity, reply: auth.Reply) !void {
        const self: *Host = @ptrCast(@alignCast(raw));
        try self.workspace.submitAuthentication(request, reply);
    }
    fn cancelAuthentication(raw: *anyopaque, request: auth.RequestIdentity) void {
        const self: *Host = @ptrCast(@alignCast(raw));
        if (self.workspace.cancelAuthentication(request)) _ = self.application.sessions.cancel(request.key) catch false;
    }
    fn cancel(raw: *anyopaque, key: operations.OperationKey) void {
        const self: *Host = @ptrCast(@alignCast(raw));
        if (self.workspace.connectionProgress(key)) |current| if (current.automatic_retry_pending) {
            const id = self.application.legacyForHandle(key.owner.session) orelse return;
            self.workspace.cancelSessionCreation(id);
        };
        _ = self.application.sessions.cancel(key) catch false;
    }
    fn retry(raw: *anyopaque, key: operations.OperationKey) !void {
        const self: *Host = @ptrCast(@alignCast(raw));
        if (key.owner != .session) return error.InvalidOperation;
        if (self.application.fileConnectionProgress(key) != null) {
            _ = try self.application.sessions.retry(key.owner.session);
            self.application.dismissFileProgress(key);
            self.progress.hide();
            return;
        }
        const current = self.workspace.connectionProgress(key) orelse return error.StaleConnection;
        if (current.cleanup != .released) return error.CleanupNotReleased;
        const id = self.application.legacyForHandle(key.owner.session) orelse return error.StaleConnection;
        try self.application.requestSshReconnect(id);
    }
    fn stopRetry(raw: *anyopaque, key: operations.OperationKey) !void {
        const self: *Host = @ptrCast(@alignCast(raw));
        try self.workspace.stopAutomaticRetry(key);
    }
    fn retryNow(raw: *anyopaque, key: operations.OperationKey) !void {
        const self: *Host = @ptrCast(@alignCast(raw));
        try self.workspace.retryAutomaticallyNow(key);
    }
    /// "重新输入凭据": the manual retry asks for the secret instead of using
    /// the saved one (the request is dropped again if the retry is refused).
    fn retryWithCredentials(raw: *anyopaque, key: operations.OperationKey) !void {
        const self: *Host = @ptrCast(@alignCast(raw));
        try self.workspace.requestCredentialPrompt(key);
        retry(raw, key) catch |err| {
            self.workspace.cancelCredentialPrompt(key);
            return err;
        };
    }
    fn trustHostKey(raw: *anyopaque, key: operations.OperationKey) !void {
        const self: *Host = @ptrCast(@alignCast(raw));
        const request = self.host_key_request orelse return error.StaleAuthentication;
        if (!request.key.eql(key)) return error.StaleAuthentication;
        try self.workspace.submitAuthentication(request, .{ .replace_host_key = "yes" });
    }
    fn rejectHostKey(raw: *anyopaque, key: operations.OperationKey) void {
        const self: *Host = @ptrCast(@alignCast(raw));
        const request = self.host_key_request orelse return;
        if (!request.key.eql(key)) return;
        cancelAuthentication(raw, request);
    }
    fn close(raw: *anyopaque, key: operations.OperationKey) void {
        const self: *Host = @ptrCast(@alignCast(raw));
        self.application.dismissFileProgress(key);
        self.workspace.dismissConnectionProgress(key) catch {};
    }
    fn copyLogs(raw: *anyopaque, key: operations.OperationKey, text: []const u8) !void {
        const self: *Host = @ptrCast(@alignCast(raw));
        if (self.workspace.connectionProgress(key) == null and self.application.fileConnectionProgress(key) == null) return error.StaleConnection;
        if (!ui.platform_services.clipboardSetText(self.cx.system_sdk, text)) return error.ClipboardUnavailable;
    }
    fn cleanup(self: *Host) void {
        self.cx.removeAfterLayoutHook(self);
        self.bridge.clear();
        self.workspace.authentication_ui_ready = false;
        // Each view owns its scope cleanup. Child input scopes may already be
        // disposed here, so do not call presentation methods during teardown.
        self.cx.allocator.destroy(self);
    }
};
