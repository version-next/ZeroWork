//! 新建连接向导宿主 WizardHost 及草稿辅助（P2 自 src/main.zig 原样拆出）。

const std = @import("std");
const applog = @import("../../../../platform/applog.zig");
const ui = @import("ui");
const ws = @import("../../../workspace/view/workspace.zig");
const hosts_mod = @import("../../../../config/hosts.zig");
const wizard_mod = @import("../view/wizard.zig");
const remote_editor = @import("../../../../plugins/remote/editor_factory.zig");
const ssh_session = @import("../../../../proto/ssh/session.zig");
const application_host_mod = @import("../../../shell/host/application_host.zig");

/// Draft is borrowed during the callback; persistence and async work own copies.
pub fn hostFromDraft(draft: wizard_mod.Draft) !hosts_mod.HostConfig {
    return draft.toHostConfig();
}

pub fn freeDraft(allocator: std.mem.Allocator, draft: wizard_mod.Draft) void {
    var owned = draft;
    owned.deinit(allocator);
}

pub fn onWizardResultTrampoline(ctx: *anyopaque, result: wizard_mod.Result) anyerror!?wizard_mod.SaveReceipt {
    const self: *WizardHost = @ptrCast(@alignCast(ctx));
    return self.onWizardResult(result);
}

pub const WizardHost = struct {
    allocator: std.mem.Allocator,
    workspace: *ws.Workspace,
    wizard: *wizard_mod.Wizard,
    application_host: *application_host_mod.ApplicationHost,
    cx_ptr: *ui.Cx,
    assets: []wizard_mod.Draft = &.{},
    edit_host_index: ?usize = null,
    selected_group: ?@import("../../../../config/asset_actions.zig").GroupRef = null,

    probe_library: ?ssh_session.Library = null,
    probe_controller: @import("wizard_probe.zig").Controller,
    probe_presentation: ?*@import("probe_connection_host.zig").Host = null,

    /// The wizard window exists: nested child editors live in the same window.
    pub fn windowMounted(raw: *anyopaque, cx: *ui.Cx, scope: *ui.Scope, root: *ui.Node) !void {
        const self: *WizardHost = @ptrCast(@alignCast(raw));
        const child_editor = try @import("plugin_editor_host.zig").Host.mount(cx, scope, self.wizard, self.application_host.registry(), .{ .context = self, .save = WizardHost.saveEnvelope });
        try root.appendChild(cx.allocator, child_editor.root);
        try self.refreshAssets();
    }

    /// Already open: raise its window instead of replacing the draft.
    pub fn raiseOpen(self: *WizardHost) bool {
        if (!self.wizard.isOpen()) return false;
        self.wizard.show();
        return true;
    }

    pub fn configureEditor(raw: *anyopaque, instance: @import("../../../../host/plugin_ui_contract.zig").EditorInstance) !void {
        const self: *WizardHost = @ptrCast(@alignCast(raw));
        const state = remote_editor.fromInstance(instance) orelse return;
        state.on_result = onWizardResultTrampoline;
        state.result_context = self;
        state.editor.on_test = startProbe;
        state.editor.test_ctx = self;
        state.editor.setSshDefaults(self.workspace.app_config.ssh.connect_timeout_sec, self.workspace.app_config.ssh.keepalive_sec);
        state.editor.setScrollbackDefault(self.workspace.app_config.ui.scrollback_limit);
        try state.editor.setAssets(self.assets);
        try self.installEditorGroups(&state.editor);
    }

    pub fn submitEnvelope(raw: *anyopaque, value: @import("../../../../config/connection_envelope.zig").Envelope, intent: @import("../../../../host/plugin_ui_contract.zig").SubmitIntent) !void {
        const self: *WizardHost = @ptrCast(@alignCast(raw));
        const manifest = self.application_host.registry().find(value.protocol_id) orelse {
            // 协议插件被禁用（Q5）：只允许保存通用字段的修改，不能连接、不能测试连接。
            if (self.application_host.pluginLaunch().disabled(value.protocol_id) == null) return error.UnknownPlugin;
            if (intent != .save) return error.PluginDisabled;
            _ = try saveEnvelope(self, value);
            return;
        };
        const contribution = manifest.connection orelse return error.ConnectionEditorUnavailable;
        try value.validate();
        if (value.payload_version != contribution.payload_version) return error.UnsupportedPayloadVersion;
        try contribution.validate_payload(value.payload);
        if (intent == .probe) return error.ProbeUnsupported;
        if (intent == .temporary) {
            if (contribution.create_kind != .saved_or_temporary) return error.SaveRequired;
            _ = try self.application_host.openEnvelope(value, try self.application_host.dispatcher.issue());
            return;
        }
        const owner = try saveEnvelope(self, value);
        if (intent == .save_and_open) {
            var saved = value;
            saved.id = owner.id;
            saved.revision = owner.revision;
            _ = self.application_host.openEnvelope(saved, try self.application_host.dispatcher.issue()) catch |err| {
                // The asset transaction has committed. A failed connection must
                // leave one saved asset, rather than invite another save.
                self.workspace.statusFailure(@errorName(err));
                applog.warn(.ui, "saved plugin connection open: {s}", .{@errorName(err)});
                return;
            };
        }
    }

    pub fn submitEnvelopeWithSecret(raw: *anyopaque, value: @import("../../../../config/connection_envelope.zig").Envelope, intent: @import("../../../../host/plugin_ui_contract.zig").SubmitIntent, handoff: @import("../../../../host/editor_credentials.zig").Handoff) !void {
        const self: *WizardHost = @ptrCast(@alignCast(raw));
        if (self.application_host.pending_editor_handoff != null) return error.CredentialHandoffBusy;
        self.application_host.pending_editor_handoff = handoff;
        defer self.application_host.pending_editor_handoff = null;
        try submitEnvelope(raw, value, intent);
    }

    fn saveEnvelope(raw: *anyopaque, value: @import("../../../../config/connection_envelope.zig").Envelope) !@import("../../../../host/identity.zig").AssetOwner {
        const self: *WizardHost = @ptrCast(@alignCast(raw));
        if (self.application_host.registry().find(value.protocol_id)) |manifest| {
            const contribution = manifest.connection orelse return error.ConnectionEditorUnavailable;
            try value.validate();
            if (value.payload_version != contribution.payload_version) return error.UnsupportedPayloadVersion;
            try contribution.validate_payload(value.payload);
        } else {
            // 协议插件被禁用（Q5）：插件没有初始化，不解码、不校验、不改写载荷；只能改已保存主机的通用字段。
            if (self.application_host.pluginLaunch().disabled(value.protocol_id) == null) return error.UnknownPlugin;
            if (@backingInt(value.id) == 0) return error.PluginDisabled;
            try value.validate();
        }
        var arena: std.heap.ArenaAllocator = .init(self.allocator);
        defer arena.deinit();
        const record = try @import("../../../../config/connection_envelope.zig").toHostConfig(arena.allocator(), value);
        const expected: ?@import("../../../../host/identity.zig").AssetOwner = if (@backingInt(value.id) == 0) null else .{ .id = value.id, .revision = value.revision };
        const owner = try self.commitHost(expected, record);
        self.edit_host_index = null;
        self.workspace.rebuildSidebar() catch |err| applog.warn(.ui, "saved plugin asset sidebar refresh: {s}", .{@errorName(err)});
        // The parent resolves the new asset as soon as the child completes.
        self.refreshAssets() catch |err| applog.warn(.ui, "saved child asset refresh: {s}", .{@errorName(err)});
        return owner;
    }

    pub fn openInAssetGroup(raw: *anyopaque, reference: ?@import("../../../../config/asset_actions.zig").GroupRef) !void {
        const self: *WizardHost = @ptrCast(@alignCast(raw));
        if (self.raiseOpen()) return error.WizardAlreadyOpen;
        var group_name: ?[]const u8 = null;
        if (reference) |group| {
            const index = self.workspace.registry.groupIndex(group.id) orelse return error.StaleGroup;
            const current = self.workspace.registry.groups[index];
            if (current.revision != group.revision) return error.StaleGroup;
            group_name = current.name;
        }
        try self.refreshAssets();
        self.edit_host_index = null;
        self.selected_group = reference;
        try remote_editor.loadDraft(self.wizard, .{ .group = group_name });
        self.wizard.show();
    }

    pub fn openCapturedAsset(raw: *anyopaque, owner: @import("../../../../host/identity.zig").AssetOwner) !void {
        const self: *WizardHost = @ptrCast(@alignCast(raw));
        // An existing draft must be dismissed explicitly before replacing it.
        if (self.raiseOpen()) return error.WizardAlreadyOpen;
        _ = try self.workspace.registry.get(owner);
        const index = self.workspace.registry.indexOf(owner.id) orelse return error.StaleAsset;
        try self.refreshAssets();
        self.edit_host_index = index;
        self.selected_group = null;
        const record = self.workspace.registry.hosts[index];
        if (self.application_host.registry().find(record.protocolId())) |manifest| {
            _ = manifest.connection orelse return error.ConnectionEditorUnavailable;
        } else if (self.application_host.pluginLaunch().disabled(record.protocolId()) == null) return error.UnknownPlugin;
        var arena: std.heap.ArenaAllocator = .init(self.allocator);
        defer arena.deinit();
        try self.wizard.loadEnvelope(try @import("../../../../config/connection_envelope.zig").fromLegacy(arena.allocator(), record));
        self.wizard.show();
    }

    pub fn openConnectionDraft(self: *WizardHost, value: @import("../../../../config/connection_envelope.zig").Envelope) !void {
        if (self.raiseOpen()) return error.WizardAlreadyOpen;
        if (@backingInt(value.id) != 0) return error.ConnectionAlreadySaved;
        try self.refreshAssets();
        self.edit_host_index = null;
        self.selected_group = null;
        try self.wizard.loadEnvelope(value);
        if (remote_editor.editor(self.wizard)) |editor| editor.sig_save_password.?.set(false) else self.wizard.deferForgetPassword();
        self.wizard.show();
    }

    fn startProbe(raw: *anyopaque, draft: *const wizard_mod.Draft) void {
        const self: *WizardHost = @ptrCast(@alignCast(raw));
        self.probe_controller.cancelAll();
        const editor = remote_editor.editor(self.wizard) orelse return;
        if (self.probe_library == null) self.probe_library = ssh_session.Library.init() catch {
            editor.setTestResult(.{ .fail = "SSH 库初始化失败" });
            return;
        };
        _ = self.probe_controller.start(draft.*, self.workspace.registry.hosts, self.workspace.app_config.*, editor.test_generation, &self.probe_library.?) catch |err| {
            editor.setTestResult(.{ .fail = @errorName(err) });
            return;
        };
        self.cx_ptr.requestRedraw();
    }

    fn releaseAssets(self: *WizardHost, assets: []wizard_mod.Draft) void {
        for (assets) |*asset| asset.deinit(self.allocator);
        if (assets.len > 0) self.allocator.free(assets);
    }

    fn installEditorGroups(self: *WizardHost, editor: *@import("../../../../plugins/remote/editor.zig").RemoteEditor) !void {
        const names = try self.allocator.alloc([]const u8, self.workspace.registry.groups.len);
        defer self.allocator.free(names);
        for (self.workspace.registry.groups, 0..) |group, index| names[index] = group.name;
        try editor.setGroups(names);
    }

    pub fn refreshAssets(self: *WizardHost) !void {
        if (remote_editor.editor(self.wizard)) |editor| {
            editor.setSshDefaults(self.workspace.app_config.ssh.connect_timeout_sec, self.workspace.app_config.ssh.keepalive_sec);
            editor.setScrollbackDefault(self.workspace.app_config.ui.scrollback_limit);
        }
        const next = try remote_editor.projectAssets(self.allocator, self.workspace.registry.hosts);
        errdefer self.releaseAssets(next);
        // Install the replacement before freeing slices borrowed by the wizard.
        if (remote_editor.editor(self.wizard)) |editor| {
            try editor.setAssets(next);
            try self.installEditorGroups(editor);
        }
        self.releaseAssets(self.assets);
        self.assets = next;
    }

    fn assetsCurrent(self: *WizardHost) bool {
        return remote_editor.assetsCurrent(self.assets, self.workspace.registry.hosts);
    }

    pub fn hookRun(raw: *anyopaque, _: u8, _: bool) ui.AfterLayoutResult {
        const self: *WizardHost = @ptrCast(@alignCast(raw));
        if (self.probe_presentation) |presentation| presentation.presentProgress() catch |err| {
            applog.warn(.ui, "connection test progress unavailable: {s}", .{@errorName(err)});
        };
        var index: usize = 0;
        while (index < self.probe_controller.jobs.items.len) {
            const job = self.probe_controller.jobs.items[index];
            const state = self.probe_controller.poll(job) catch |err| {
                applog.warn(.ui, "connection test result pending: {s}", .{@errorName(err)});
                index += 1;
                continue;
            };
            switch (state) {
                .pending => {
                    if (remote_editor.editor(self.wizard)) |editor| {
                        if (job.generation != editor.test_generation) job.cancel();
                    } else job.cancel();
                    index += 1;
                },
                .finished => |outcome| {
                    if (self.probe_presentation) |presentation| presentation.presentJob(job) catch |err| {
                        applog.warn(.ui, "connection final test presentation: {s}", .{@errorName(err)});
                    };
                    var buffer: [160]u8 = undefined;
                    const message = if (outcome.failure) |failure| @errorName(failure) else std.fmt.bufPrint(&buffer, "连接成功 · {d} ms", .{outcome.elapsed_ms}) catch "连接成功";
                    if (remote_editor.editor(self.wizard)) |editor| _ = editor.setTestResultForDraft(outcome.generation, outcome.draft_id, outcome.draft_revision, if (outcome.failure != null) .{ .fail = message } else .{ .ok = message });
                    self.probe_controller.retire(job) catch |err| {
                        applog.warn(.ui, "connection test cleanup pending: {s}", .{@errorName(err)});
                        index += 1;
                    };
                },
            }
        }
        if (self.probe_controller.jobs.items.len != 0) self.cx_ptr.scheduleRedrawAfterNs(33 * std.time.ns_per_ms);
        if (self.assetsCurrent()) return .done;
        self.refreshAssets() catch |err| {
            applog.warn(.ui, "wizard assets refresh failed: {s}", .{@errorName(err)});
            return .done;
        };
        return .needs_layout;
    }

    pub fn cleanup(self: *WizardHost) void {
        self.cx_ptr.removeAfterLayoutHook(self);
        self.probe_controller.deinit();
        if (self.probe_library) |*library| library.deinit();
        if (remote_editor.editor(self.wizard)) |editor| editor.assets = &.{};
        // The main window is going away: its editor window goes with it.
        self.wizard.detachWindow();
        self.releaseAssets(self.assets);
        self.allocator.destroy(self);
    }

    fn onWizardResult(self: *WizardHost, result: wizard_mod.Result) !?wizard_mod.SaveReceipt {
        switch (result) {
            .cancelled => {
                self.probe_controller.cancelAll();
                self.edit_host_index = null;
                self.selected_group = null;
                return null;
            },
            .save_only => |draft| {
                const owned = try draft.dupe(self.allocator);
                defer freeDraft(self.allocator, owned);
                const host = try owned.toPersistentHostConfig();
                const owner = try self.commitHost(owned.source_owner, host);
                self.edit_host_index = null;
                self.workspace.rebuildSidebar() catch |err| applog.warn(.ui, "saved host sidebar refresh failed: {s}", .{@errorName(err)});
                return .{ .owner = owner };
            },
            .saved => |draft| {
                const owned = try draft.dupe(self.allocator);
                defer freeDraft(self.allocator, owned);
                return try self.connectDraft(owned);
            },
        }
    }

    fn connectDraft(self: *WizardHost, draft: wizard_mod.Draft) !wizard_mod.SaveReceipt {
        const host = try draft.toHostConfig();
        const owner = try self.commitHost(draft.source_owner, try draft.toPersistentHostConfig());
        // Persistence already succeeded. A subsequent retry targets this
        // receipt's asset rather than appending another copy of the draft.
        self.edit_host_index = null;
        self.workspace.rebuildSidebar() catch |err| applog.warn(.ui, "saved host sidebar refresh failed: {s}", .{@errorName(err)});
        self.workspace.newSessionWithCredentials(owner, host.password, host.key_passphrase) catch |err| {
            applog.warn(.ui, "saved connection open failed: {s}", .{@errorName(err)});
            return .{ .owner = owner, .open_failure = err };
        };
        return .{ .owner = owner };
    }

    fn commitHost(self: *WizardHost, expected: ?@import("../../../../host/identity.zig").AssetOwner, host: hosts_mod.HostConfig) !@import("../../../../host/identity.zig").AssetOwner {
        try self.workspace.identities.appendHosts(self.allocator, self.workspace.registry.hosts.len);
        if (expected == null) try self.workspace.identities.hosts.ensureTotalCapacity(self.allocator, self.workspace.registry.hosts.len + 1);
        var transaction = try @import("../../../../config/store.zig").HostsTransaction.init(self.allocator, &self.workspace.registry);
        defer transaction.deinit();
        const candidate = &transaction.candidate.?;
        var persistent = host;
        if (self.selected_group) |reference| {
            if (remote_editor.editor(self.wizard)) |editor| {
                persistent.asset_group_id = try @import("../../../../config/asset_group_actions.zig").hostDraftGroup(candidate, reference, persistent.group, editor.group_edited);
            } else {
                const index = candidate.groupIndex(reference.id) orelse return error.StaleGroup;
                const group = candidate.groups[index];
                if (group.revision != reference.revision) return error.StaleGroup;
                if (std.mem.eql(u8, persistent.group orelse "", group.name)) persistent.asset_group_id = group.group_id;
            }
        }
        // Login-password persistence is explicitly selected by the editor.
        // The host transaction stores it in Keychain and writes only a ref.
        persistent.key_passphrase = null;
        persistent.totp_secret = null;
        const owner = if (expected) |baseline| blk: {
            const previous = try candidate.get(baseline);
            var value = persistent;
            value.pinned = previous.pinned;
            value.ts_default = previous.ts_default;
            value.unknown_fields = previous.unknown_fields;
            value.unknown_options = previous.unknown_options;
            value.unknown_auth = previous.unknown_auth;
            value.asset_group_id = if (std.mem.eql(u8, value.group orelse "", previous.group orelse "")) previous.asset_group_id else null;
            break :blk try candidate.update(baseline, value);
        } else try candidate.add(persistent);
        try transaction.commit(self.workspace.io, std.Io.Dir.cwd(), self.workspace.hosts_path, &self.workspace.registry);
        self.selected_group = null;
        self.workspace.identities.appendHosts(self.allocator, self.workspace.registry.hosts.len) catch unreachable;
        return owner;
    }
};

