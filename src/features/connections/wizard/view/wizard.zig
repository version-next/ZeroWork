//! Registry-driven connection editor shell. The shell owns Modal, contribution
//! picker and slots; connection fields, validation and actions belong to the
//! selected provider's EditorInstance.
const std = @import("std");
const ui = @import("ui");
const S = @import("wizard_styles.zig");
const panel_header = @import("../../../../shared/ui/components/panel_header/panel_header.zig");
const identity = @import("../../../../host/identity.zig");
const plugins = @import("../../../../host/plugin_registry.zig");
const plugin_ui = @import("../../../../host/plugin_ui_contract.zig");
const envelope_mod = @import("../../../../config/connection_envelope.zig");
const editor_credentials = @import("../../../../host/editor_credentials.zig");
const editor_probes = @import("../../../../host/probe_contract.zig");
// Compatibility value types are owned by the remote provider. Existing probe
// and persistence adapters may still exchange these; the shell never reads them.
const remote_types = @import("../../../../plugins/remote/editor.zig");
pub const Draft = remote_types.Draft;
pub const Protocol = remote_types.Protocol;
pub const Auth = remote_types.Auth;
pub const Result = remote_types.Result;
pub const SaveReceipt = remote_types.SaveReceipt;
pub const SaveFailure = remote_types.SaveFailure;
pub const Step = remote_types.Step;
pub const TestState = remote_types.TestState;
pub const TestProgress = remote_types.TestProgress;
pub const parsePort = remote_types.parsePort;
pub const advanceAllowed = remote_types.advanceAllowed;
pub const formatTestLine = remote_types.formatTestLine;
pub const test_detail_max = remote_types.test_detail_max;
pub const ValidationError = remote_types.ValidationError;
var next_editor_id: std.atomic.Value(u64) = .init(1);
const aux_window = @import("../../../../shared/ui/window/aux_window.zig");
const remote_factory = @import("../../../../plugins/remote/editor_factory.zig");

/// What to load once the wizard window has been created. Window creation is
/// deferred to the process loop boundary, so callers' "prepare + show"
/// sequences are recorded here and replayed in the new window.
pub const Launch = struct {
    arena: ?std.heap.ArenaAllocator = null,
    contribution: ?[]const u8 = null,
    reset: bool = false,
    envelope: ?envelope_mod.Envelope = null,
    draft: ?Draft = null,
    /// Converted temporary targets never offer to persist their password.
    forget_password: bool = false,
    show: bool = false,

    fn allocator(self: *Launch, backing: std.mem.Allocator) std.mem.Allocator {
        if (self.arena == null) self.arena = std.heap.ArenaAllocator.init(backing);
        return self.arena.?.allocator();
    }
    fn deinit(self: *Launch) void {
        if (self.arena) |*arena| arena.deinit();
        self.* = .{};
    }
};

/// Native window for the connection editor: 720 wide like hb6dT…zp7WE; the
/// height holds Stack 1 with its stepper and footer, and content scrolls.
/// 地面角色是 `.shell`：整个窗口自绘 ground（主题 app 色），不是设置窗口的 panel 底。
pub const window_spec: aux_window.Spec = .{ .title = "新建主机", .width = 720, .height = 640, .min_width = 600, .min_height = 420, .ground = .shell };

/// 编辑协议插件已禁用的已保存主机（Q5）：插件没有初始化、没有协议编辑器，只能改名称；载荷原样保留。
const DisabledEdit = struct {
    arena: std.heap.ArenaAllocator,
    envelope: envelope_mod.Envelope,
    name: *ui.Signal([]const u8),
    name_text: std.ArrayList(u8) = .empty,
    scope: *ui.Scope,
    /// 子作用域随窗口一起被释放时置位（之后不能再 dispose 它）。
    scope_disposed: bool = false,
};

pub const Wizard = struct {
    plugin_registry: plugins.Registry = .{},
    /// 本次启动时随应用插件的启用状态（Q5）：被禁用的插件在协议下拉里是禁用选项；它的已保存主机只能改通用字段。
    plugin_launch: ?*const @import("../model/plugin_availability.zig").Launch = null,
    disabled_edit: ?DisabledEdit = null,
    save_open_button: ?*ui.Node = null,
    connection_configs: ?@import("../../../../host/connection_config_resolver.zig").Resolver = null,
    editor_host: ?*@import("../../../../host/content_context.zig").EditorHost = null,
    /// Nested child editors only: why the parent opened this one.
    child_mount: ?plugin_ui.ChildMount = null,
    credential_host: ?*editor_credentials.Host = null,
    probe_host: ?*@import("../../../../host/probe_host.zig").Host = null,
    credentials: ?editor_credentials.Facade = null,
    probes: ?editor_probes.EditorProbes = null,
    protocol_id: []const u8 = "",
    queued_protocol: ?[]const u8 = null,
    protocol_options: []ui.widgets.SelectOption = &.{},
    owned_ids: std.ArrayList([]u8) = .empty,
    plugin_slot: ?*ui.Node = null,
    modal_body: ?*ui.Node = null,
    parent_presentation_visible: bool = true,
    presentation_warning: bool = false,
    parent_barrier_color: ui.Color = ui.Color.TRANSPARENT,
    plugin_scope: ?*ui.Scope = null,
    plugin_editor: ?plugin_ui.EditorInstance = null,
    plugin_error: ?*ui.Node = null,
    on_envelope: ?*const fn (*anyopaque, envelope_mod.Envelope, plugin_ui.SubmitIntent) anyerror!void = null,
    on_envelope_with_secret: ?*const fn (*anyopaque, envelope_mod.Envelope, plugin_ui.SubmitIntent, editor_credentials.Handoff) anyerror!void = null,
    envelope_context: ?*anyopaque = null,
    on_editor_mounted: ?*const fn (*anyopaque, plugin_ui.EditorInstance) anyerror!void = null,
    editor_mounted_context: ?*anyopaque = null,
    on_cancel: ?*const fn (*anyopaque) void = null,
    cancel_context: ?*anyopaque = null,
    draft_id: u64 = 0,
    draft_revision: u64 = 1,
    saving: bool = false,
    cx: *ui.Cx = undefined,
    scope: *ui.Scope = undefined,
    alloc: std.mem.Allocator = undefined,
    root: ?*ui.Node = null,
    modal: ?*ui.Node = null,
    header: ?*ui.Node = null,
    title: ?*ui.Node = null,
    footer: ?*ui.Node = null,
    authentication_area: *ui.Node = undefined,
    protocol_icon: ?*ui.Node = null,
    protocol_picker: ?*ui.Node = null,
    protocol_select: ?ui.widgets.SelectResult = null,
    painted_colors: ?S.theme.Colors = null,
    /// Raised by the window's theme publication; consumed where this view repaints.
    theme_watch: @import("../../../../shared/ui/theme/theme_watch.zig").ThemeWatch = .{},
    open: ?*ui.Signal(bool) = null,
    locked: ?*ui.Signal(bool) = null,
    sig_protocol: ?*ui.Signal(?[]const u8) = null,
    /// Island B v3: the connection editor is its own native window (hb6dT
    /// 720 wide) owned by the main window. Null keeps the legacy in-window
    /// Modal (unit tests and nested child editors).
    window: ?*aux_window.Slot = null,
    window_slot: aux_window.Slot = undefined,
    /// Called after the window UI mounted, before the pending launch applies
    /// (main.zig mounts the nested child editor host into the same window).
    on_window_mounted: ?*const fn (*anyopaque, *ui.Cx, *ui.Scope, *ui.Node) anyerror!void = null,
    window_mounted_context: ?*anyopaque = null,
    mounted: bool = false,
    native_closing: bool = false,
    publication: ?*@import("../../../shell/view/shell_styles.zig").ThemePublication = null,
    launch: Launch = .{},

    pub fn setRegistry(self: *Wizard, source: plugins.Registry) void {
        self.plugin_registry = source;
    }
    // ── Native window (Island B v3) ─────────────────────────────────────

    /// Present this editor in its own native window owned by `owner`.
    pub fn attachWindow(self: *Wizard, owner: aux_window.WindowId) void {
        if (self.window == null) {
            self.window_slot = .{ .spec = window_spec, .client = .{ .context = self, .mount = windowMount, .close_request = windowCloseRequest, .destroyed = windowDestroyed, .failed = windowFailed } };
            self.window = &self.window_slot;
        }
        self.window.?.owner = owner;
    }
    /// Close the window (if any) and stop presenting natively.
    pub fn detachWindow(self: *Wizard) void {
        const slot = self.window orelse return;
        slot.deinit();
        self.window = null;
        self.launch.deinit();
    }
    pub fn windowed(self: *const Wizard) bool {
        return self.window != null;
    }
    /// Visible, or its window is about to be created.
    pub fn isOpen(self: *const Wizard) bool {
        if (self.isVisible()) return true;
        const slot = self.window orelse return false;
        return slot.active();
    }
    /// Unmounted window wizard: record the request for the window mount.
    fn deferred(self: *const Wizard) bool {
        return self.window != null and !self.mounted;
    }
    /// `editor_factory.loadDraft` hook while the window does not exist yet.
    pub fn deferDraft(self: *Wizard, draft: Draft) !bool {
        if (!self.deferred()) return false;
        const manifest = self.plugin_registry.find(@tagName(draft.protocol)) orelse return error.UnknownPlugin;
        self.protocol_id = manifest.id;
        self.launch.envelope = null;
        self.launch.contribution = null;
        self.launch.draft = try draft.dupe(self.launch.allocator(std.heap.c_allocator));
        return true;
    }
    pub fn deferForgetPassword(self: *Wizard) void {
        if (self.deferred()) self.launch.forget_password = true;
    }
    fn windowMount(raw: *anyopaque, cx: *ui.Cx, scope: *ui.Scope) anyerror!*ui.Node {
        const self: *Wizard = @ptrCast(@alignCast(raw));
        const root = try self.mount(cx, scope);
        if (self.on_window_mounted) |hook| try hook(self.window_mounted_context orelse return error.WizardWindowUnavailable, cx, scope, root);
        var launch = self.launch;
        self.launch = .{};
        defer launch.deinit();
        if (launch.envelope) |value| {
            try self.loadEnvelope(value);
        } else if (launch.draft) |draft| {
            try remote_factory.loadDraft(self, draft);
        } else {
            // mount() already built the deferred contribution (protocol_id).
            if (launch.contribution) |id| if (!std.mem.eql(u8, id, self.protocol_id)) try self.selectContribution(id);
            if (launch.reset) try self.reset();
        }
        if (launch.forget_password) if (remote_factory.editor(self)) |editor| editor.sig_save_password.?.set(false);
        self.show();
        return root;
    }
    fn windowCloseRequest(raw: *anyopaque) bool {
        const self: *Wizard = @ptrCast(@alignCast(raw));
        if (!self.isVisible()) return true;
        // The traffic-light close is the editor's own cancel; it may keep the
        // window when the provider vetoes (e.g. a pending save).
        self.native_closing = true;
        defer self.native_closing = false;
        self.cancel();
        return !self.isVisible();
    }
    fn windowDestroyed(raw: *anyopaque) void {
        const self: *Wizard = @ptrCast(@alignCast(raw));
        self.launch.deinit();
    }
    fn windowFailed(raw: *anyopaque, err: anyerror) void {
        const self: *Wizard = @ptrCast(@alignCast(raw));
        self.launch.deinit();
        std.log.scoped(.wizard).warn("connection editor window: {s}", .{@errorName(err)});
    }
    /// Main window theme changed: publish the palette into this window's Cx.
    pub fn republishTheme(self: *Wizard) void {
        if (!self.mounted) return;
        const publication = self.publication orelse return;
        publication.publish(self.cx, S.theme.widgetTheme(S.theme.currentName()));
        self.refreshAppearance();
        self.cx.requestRedraw();
    }
    fn windowKey(key: ui.events.KeyCode, _: ui.events.Modifiers, raw: ?*anyopaque) ui.events.EventResult {
        const self: *Wizard = @ptrCast(@alignCast(raw orelse return .ignored));
        if (key != .escape or !self.isVisible()) return .ignored;
        self.cancel();
        return .stop;
    }

    pub fn selectContribution(self: *Wizard, id: []const u8) !void {
        const manifest = self.plugin_registry.find(id) orelse return error.UnknownPlugin;
        if (manifest.connection == null) return error.ConnectionEditorUnavailable;
        self.protocol_id = manifest.id;
        if (self.deferred()) {
            self.launch.draft = null;
            self.launch.envelope = null;
            self.launch.contribution = manifest.id;
            return;
        }
        self.sig_protocol.?.set(manifest.id);
        try self.mountContributedEditor(null);
        self.refreshAppearance();
    }
    pub fn reset(self: *Wizard) !void {
        if (self.title) |title| try title.setTextContent(self.alloc, "新建主机");
        self.draft_revision = std.math.add(u64, self.draft_revision, 1) catch return error.RevisionExhausted;
        if (self.deferred()) {
            self.launch.reset = true;
            return;
        }
        try self.mountContributedEditor(null);
    }
    pub fn loadEnvelope(self: *Wizard, value: envelope_mod.Envelope) !void {
        if (self.deferred()) {
            if (self.plugin_registry.find(value.protocol_id) == null) if (self.disabledLinked(value.protocol_id)) |linked| {
                self.protocol_id = linked.id;
                self.launch.draft = null;
                self.launch.contribution = null;
                self.launch.envelope = try value.clone(self.launch.allocator(std.heap.c_allocator));
                return;
            };
            const manifest = self.plugin_registry.find(value.protocol_id) orelse return error.UnknownPlugin;
            _ = manifest.connection orelse return error.ConnectionEditorUnavailable;
            self.protocol_id = manifest.id;
            self.launch.draft = null;
            self.launch.contribution = null;
            self.launch.envelope = try value.clone(self.launch.allocator(std.heap.c_allocator));
            return;
        }
        if (self.title) |title| try title.setTextContent(self.alloc, if (@backingInt(value.id) == 0) "新建主机" else "编辑主机");
        if (self.plugin_registry.find(value.protocol_id) == null) if (self.disabledLinked(value.protocol_id)) |linked| return self.mountDisabledEditor(value, linked);
        const manifest = self.plugin_registry.find(value.protocol_id) orelse return error.UnknownPlugin;
        const contribution = manifest.connection orelse return error.ConnectionEditorUnavailable;
        const decode = contribution.decode orelse return error.ConnectionCodecUnavailable;
        var arena = std.heap.ArenaAllocator.init(self.alloc);
        defer arena.deinit();
        const decoded = try decode(arena.allocator(), value);
        self.protocol_id = manifest.id;
        self.sig_protocol.?.set(manifest.id);
        try self.mountContributedEditor(decoded);
        self.refreshAppearance();
    }
    /// The nested-editor host arrives with the window, possibly after the
    /// provider's editor was mounted: hand it to that editor too.
    pub fn attachEditorHost(self: *Wizard, host: *@import("../../../../host/content_context.zig").EditorHost) void {
        self.editor_host = host;
        if (self.plugin_editor == null) return;
        host.setParentRevision(self.draft_id, self.draft_revision) catch {};
        if (remote_factory.editor(self)) |editor| editor.editor_host = host;
    }
    pub fn deliverChild(self: *Wizard, completion: @import("../../../../host/content_context.zig").ChildCompletion) void {
        if (completion.request.parent_editor_id != self.draft_id) return;
        const editor = self.plugin_editor orelse return;
        if (editor.vtable.child_completed) |deliver| deliver(editor.context, completion);
    }
    pub fn mount(self: *Wizard, cx: *ui.Cx, scope: *ui.Scope) !*ui.Node {
        self.cx = cx;
        self.scope = scope;
        try self.theme_watch.bind(cx, scope);
        self.alloc = cx.allocator;
        if (self.draft_id == 0) {
            const id = next_editor_id.fetchAdd(1, .monotonic);
            if (id == 0 or id == std.math.maxInt(u64)) return error.IdentityExhausted;
            self.draft_id = id;
        }
        self.open = try scope.createSignal(bool, false);
        self.locked = try scope.createSignal(bool, false);
        self.sig_protocol = try scope.createSignal(?[]const u8, null);
        const ModalParts = struct { overlay: *ui.Node, dialog: *ui.Node, body: *ui.Node, portaled: bool };
        const modal: ModalParts = if (self.window != null) blk: {
            // Native window: the window itself is the hb6dT frame (ground
            // fill); the title bar reserves the traffic lights (14 + 52 + 12).
            const publication = try cx.bindState(@import("../../../shell/view/shell_styles.zig").ThemePublication, .{});
            publication.publish(cx, S.theme.widgetTheme(S.theme.currentName()));
            self.publication = publication;
            const window_root = try ui.box(cx, S.windowRoot(), .{});
            window_root.meta.ownership.meta.test_id = "wizard.window";
            window_root.behavior.events.on_key_down = windowKey;
            window_root.behavior.events.key_context = self;
            break :blk .{ .overlay = window_root, .dialog = window_root, .body = window_root, .portaled = false };
        } else blk: {
            const value = try ui.widgets.Modal(.{ .open = ui.split(self.open.?, cx.on(Wizard, self, openChanged)), .width = S.width, .max_height = S.max_height, .close_on_overlay = false }).mount(scope, cx);
            value.overlay.meta.ownership.meta.test_id = "wizard.overlay";
            value.dialog.meta.ownership.meta.test_id = "wizard.dialog";
            value.dialog.setStyleInline(self.alloc, S.panel(cx.tokens));
            value.body.setStyleInline(self.alloc, S.modalBody());
            break :blk .{ .overlay = value.overlay, .dialog = value.dialog, .body = value.body, .portaled = value.portaled };
        };
        self.root = modal.overlay;
        self.modal = modal.dialog;
        self.modal_body = modal.body;
        const header = try ui.box(cx, if (self.window != null) S.windowHeader() else S.header(), .{});
        self.header = header;
        // Native window: the header row is the window's title bar; its empty space and title
        // drag the window (window chrome region), the protocol select stays a control.
        if (self.window != null) header.behavior.interaction.window_region = .drag;
        self.protocol_icon = try ui.iconTint(cx, ui.icons.plug, S.theme.current().accent, S.icon(18));
        self.protocol_icon.?.meta.ownership.meta.test_id = "wizard.protocol.icon";
        try header.appendChild(self.alloc, self.protocol_icon.?);
        // Window title (hb6dT Krxgk): 13 semibold fg_primary.
        self.title = try ui.text(cx, "新建主机", S.windowTitle());
        self.title.?.meta.ownership.meta.test_id = "wizard.title";
        try header.appendChild(self.alloc, self.title.?);

        var count: usize = 0;
        for (self.plugin_registry.manifests()) |manifest| if (manifest.connection != null) {
            count += 1;
        };
        // 被禁用的随应用插件（Q5，YWqSG）：仍列在协议下拉里，作为原生禁用选项（标“已禁用”，不能选中）。
        const disabled_count = self.disabledLinkedCount();
        self.protocol_options = try self.alloc.alloc(ui.widgets.SelectOption, count + disabled_count);
        var i: usize = 0;
        for (self.plugin_registry.manifests()) |manifest| {
            if (manifest.connection == null) continue;
            const test_id = try std.fmt.allocPrint(self.alloc, "wizard.protocol.{s}", .{manifest.id});
            try self.owned_ids.append(self.alloc, test_id);
            self.protocol_options[i] = .{ .value = manifest.id, .label = manifest.display_name, .icon = @import("../../../../shared/ui/components/session_icon/session_icon.zig").asset(manifest.icons.protocol), .test_id = test_id };
            i += 1;
        }
        if (self.plugin_launch) |launch| for (launch.linked(), launch.enabledFlags()) |linked, enabled| {
            if (enabled or !linked.creatable or self.plugin_registry.find(linked.id) != null) continue;
            const test_id = try std.fmt.allocPrint(self.alloc, "wizard.protocol.{s}", .{linked.id});
            try self.owned_ids.append(self.alloc, test_id);
            const label = try std.fmt.allocPrint(self.alloc, "{s} · 已禁用", .{linked.display_name});
            try self.owned_ids.append(self.alloc, label);
            self.protocol_options[i] = .{ .value = linked.id, .label = label, .icon = @import("../../../../shared/ui/components/session_icon/session_icon.zig").asset(linked.icons.protocol), .test_id = test_id, .disabled = true };
            i += 1;
        };
        if (self.plugin_registry.find(self.protocol_id) == null and self.disabledLinked(self.protocol_id) == null and count != 0) self.protocol_id = self.protocol_options[0].value;
        self.sig_protocol.?.set(if (count == 0) null else self.protocol_id);
        const protocol = try self.mountHeaderProtocol(cx, scope);
        try header.appendChild(self.alloc, protocol);
        try header.appendChild(self.alloc, try ui.spacer(cx));
        // panel-heads：统一关闭按钮（Modal / 窗口按键的 Esc 同样 `cancel`）。
        const close = try panel_header.mountClose(scope, cx, .{ .label = "关闭向导", .test_id = "wizard.close", .on_close = cx.on(Wizard, self, cancel) });
        // The native window closes through its traffic light (= cancel).
        if (self.window != null) close.setDisplay(.none);
        try header.appendChild(self.alloc, close);
        try modal.body.appendChild(self.alloc, header);
        // Stage [0,6,6,6] → View island (r12, p4) → Pane (r8, accent hairline).
        const stage = try ui.boxStyled(cx, S.stage, .{});
        const view_island = try ui.boxStyled(cx, S.island, .{});
        const pane = try ui.boxStyled(cx, S.pane, .{});
        pane.meta.ownership.meta.test_id = "wizard.pane";
        try view_island.appendChild(self.alloc, pane);
        try stage.appendChild(self.alloc, view_island);
        try modal.body.appendChild(self.alloc, stage);
        const body = try ui.box(cx, S.body(), .{});
        body.setStyleInline(self.alloc, .{ .padding = .{}, .gap = 0, .flex = 1 });
        self.plugin_slot = try ui.boxStyled(cx, S.editorSlot, .{});
        self.plugin_slot.?.meta.ownership.meta.test_id = "wizard.plugin.editor";
        self.plugin_slot.?.meta.ownership.hooks.on_cleanup = .{ .context = self, .callback = slotGone };
        try body.appendChild(self.alloc, self.plugin_slot.?);
        self.plugin_error = try ui.text(cx, "", S.text(12, 400, true));
        self.plugin_error.?.setDisplay(.none);
        try body.appendChild(self.alloc, self.plugin_error.?);
        self.authentication_area = try ui.boxStyled(cx, S.stack, .{});
        self.authentication_area.setDisplay(.none);
        try body.appendChild(self.alloc, self.authentication_area);
        try pane.appendChild(self.alloc, body);
        self.footer = try ui.box(cx, S.footer(), .{});
        self.footer.?.meta.ownership.meta.test_id = "wizard.footer";
        try self.footer.?.appendChild(self.alloc, try ui.spacer(cx));
        const save = try ui.widgets.Button(.{ .label = "保存主机", .variant = .secondary, .size = .sm, .disabled = self.locked.?, .on_click = cx.on(Wizard, self, saveOnly) }).mount(scope, cx);
        save.meta.ownership.meta.test_id = "wizard.save_only";
        try self.footer.?.appendChild(self.alloc, save);
        const submit = try ui.widgets.Button(.{ .label = "保存并打开", .variant = .primary, .size = .sm, .disabled = self.locked.?, .on_click = cx.on(Wizard, self, saveAndOpen) }).mount(scope, cx);
        submit.meta.ownership.meta.test_id = "wizard.save";
        self.save_open_button = submit;
        try self.footer.?.appendChild(self.alloc, submit);
        try pane.appendChild(self.alloc, self.footer.?);
        try self.mountContributedEditor(null);
        self.refreshAppearance();
        self.root.?.setHitTestVisible(false);
        self.root.?.setDisplay(.none);
        try cx.addAfterLayoutHook(self, viewportHook);
        try scope.onCleanup(Wizard, self, cleanup);
        self.mounted = true;
        _ = self.updateViewport();
        return if (modal.portaled) try ui.box(cx, .{ .width = .{ .px = 0 }, .height = .{ .px = 0 }, .display = .none }, .{}) else self.root.?;
    }
    fn slotGone(raw: *anyopaque) void {
        const self: *Wizard = @ptrCast(@alignCast(raw));
        self.plugin_slot = null;
    }
    fn destroyEditorNodes(self: *Wizard) void {
        if (self.plugin_slot) |slot| while (slot.children.items.len != 0) {
            const child = slot.children.items[slot.children.items.len - 1];
            slot.removeChild(child);
            self.cx.destroyDetached(child);
        };
    }
    /// Child scope created before the editor mounts (`mountContributedEditor`): a scope disposes
    /// its children in creation order and its own cleanups only after them, so this is the one
    /// point of a teardown through the parent (window close) where the editor's secret fields,
    /// which live in its child scopes, are still alive to be cleared.
    fn clearPluginSecrets(self: *Wizard) void {
        if (self.plugin_editor) |editor| editor.vtable.clear_secrets(editor.context);
    }
    fn releasePluginScope(self: *Wizard) void {
        self.plugin_scope = null;
        // Secrets were cleared by `clearPluginSecrets` before the editor's child scopes went;
        // clearing here would write into their freed field state.
        if (self.plugin_editor) |editor| editor.vtable.unmount(editor.context);
        self.plugin_editor = null;
        self.releaseEditorCapabilities();
        // Provider node cleanup callbacks may borrow scope-owned editor state.
        // Destroy the slot subtree while that state is still alive.
        self.destroyEditorNodes();
    }
    pub fn releaseContributedEditor(self: *Wizard) void {
        self.releaseDisabledEdit();
        if (self.plugin_editor) |editor| {
            editor.vtable.clear_secrets(editor.context);
            editor.vtable.unmount(editor.context);
        }
        self.plugin_editor = null;
        self.releaseEditorCapabilities();
        if (self.plugin_scope) |scope| scope.dispose();
        self.plugin_scope = null;
        self.destroyEditorNodes();
    }
    fn releaseEditorCapabilities(self: *Wizard) void {
        if (self.credentials) |credentials| credentials.destroy();
        self.credentials = null;
        if (self.probes) |probes| probes.destroy();
        self.probes = null;
        if (self.editor_host) |host| host.destroyParent(self.draft_id);
    }
    fn mountContributedEditor(self: *Wizard, initial: ?envelope_mod.Envelope) !void {
        self.releaseContributedEditor();
        const manifest = self.plugin_registry.find(self.protocol_id) orelse return;
        const connection = manifest.connection orelse return;
        const mount_editor = connection.editor_factory.mount orelse return error.ConnectionEditorUnavailable;
        const scope = try self.scope.childScope();
        self.plugin_scope = scope;
        errdefer self.releaseContributedEditor();
        const secrets = try scope.childScope();
        try secrets.onCleanup(Wizard, self, clearPluginSecrets);
        if (self.credential_host) |host| self.credentials = try host.bindEditor(self.draft_id, self.draft_revision);
        if (self.editor_host) |host| {
            if (self.probe_host) |probes| host.probe_host = probes;
            try host.setParentRevision(self.draft_id, self.draft_revision);
            self.probes = host.probesFor(self.draft_id);
        }
        if (self.probes == null) if (self.probe_host) |host| {
            self.probes = try host.bindParent(self.draft_id, self.draft_revision);
        };
        self.plugin_editor = try mount_editor(connection.editor_factory.context, .{ .cx = self.cx, .scope = scope, .slot = self.plugin_slot.?, .protocol_id = manifest.id, .initial = initial, .draft_revision = self.draft_revision, .events = .{ .context = self, .changed = editorChanged, .submit = editorSubmit, .submit_with_secret = editorSubmitWithSecret, .dismiss = editorDismiss, .cancelled = editorCancelled }, .editor_host = self.editor_host, .editor_id = self.draft_id, .child = self.child_mount, .credentials = self.credentials, .probes = self.probes, .connection_configs = self.connection_configs });
        try scope.onCleanup(Wizard, self, releasePluginScope);
        // "新建跳板主机" is SSH by definition: no protocol choice in its title bar.
        const jump_child = if (self.child_mount) |child| child.intent == .create_jump else false;
        if (self.protocol_picker) |picker| picker.setDisplay(if (jump_child) .none else .flex);
        if (self.on_editor_mounted) |hook| try hook(self.editor_mounted_context orelse return error.EditorHookUnavailable, self.plugin_editor.?);
        if (self.plugin_error) |node| node.setDisplay(.none);
        self.footer.?.setDisplay(if (self.plugin_editor.?.handles_actions) .none else .flex);
    }
    fn editorChanged(raw: *anyopaque) void {
        const self: *Wizard = @ptrCast(@alignCast(raw));
        self.draft_revision = std.math.add(u64, self.draft_revision, 1) catch 0;
        if (self.credentials) |credentials| credentials.setDraftRevision(self.draft_revision) catch {};
        if (self.probes) |probes| probes.setDraftRevision(self.draft_revision) catch {};
        if (self.probe_host) |host| host.cancelParent(self.draft_id) catch {};
        if (self.editor_host) |host| host.setParentRevision(self.draft_id, self.draft_revision) catch {};
        self.cx.requestRedraw();
    }
    fn editorDismiss(raw: *anyopaque) void {
        const self: *Wizard = @ptrCast(@alignCast(raw));
        self.hide();
    }
    fn editorCancelled(raw: *anyopaque) void {
        const self: *Wizard = @ptrCast(@alignCast(raw));
        self.hide();
        if (self.on_cancel) |callback| callback(self.cancel_context orelse return);
    }
    fn editorSubmit(raw: *anyopaque, value: envelope_mod.Envelope, intent: plugin_ui.SubmitIntent) !void {
        const self: *Wizard = @ptrCast(@alignCast(raw));
        var arena = std.heap.ArenaAllocator.init(self.alloc);
        defer arena.deinit();
        const encoded = try self.encodeSubmission(arena.allocator(), value);
        if (self.saving) return error.SaveInProgress;
        const submit = self.on_envelope orelse return error.ConnectionSubmitUnavailable;
        self.saving = true;
        self.locked.?.set(true);
        defer {
            self.saving = false;
            self.locked.?.set(false);
        }
        try submit(self.envelope_context orelse return error.ConnectionSubmitUnavailable, encoded, intent);
        if (intent != .probe) self.hide();
    }
    fn editorSubmitWithSecret(raw: *anyopaque, value: envelope_mod.Envelope, intent: plugin_ui.SubmitIntent, handoff: editor_credentials.Handoff) !void {
        const self: *Wizard = @ptrCast(@alignCast(raw));
        const credentials = self.credentials orelse return error.EditorCredentialsUnavailable;
        try credentials.requireHandoff(handoff);
        errdefer credentials.rollback(handoff);
        var arena = std.heap.ArenaAllocator.init(self.alloc);
        defer arena.deinit();
        const encoded = try self.encodeSubmission(arena.allocator(), value);
        if (self.saving) return error.SaveInProgress;
        const submit = self.on_envelope_with_secret orelse return error.ConnectionSubmitUnavailable;
        self.saving = true;
        self.locked.?.set(true);
        defer {
            self.saving = false;
            self.locked.?.set(false);
        }
        try submit(self.envelope_context orelse return error.ConnectionSubmitUnavailable, encoded, intent, handoff);
        if (intent == .save or intent == .save_and_open) try credentials.commit(handoff) else credentials.rollback(handoff);
        if (intent != .probe) self.hide();
    }
    fn encodeSubmission(self: *Wizard, allocator: std.mem.Allocator, value: envelope_mod.Envelope) !envelope_mod.Envelope {
        if (!std.mem.eql(u8, value.protocol_id, self.protocol_id)) return error.ProtocolMismatch;
        const manifest = self.plugin_registry.find(value.protocol_id) orelse return error.UnknownPlugin;
        const connection = manifest.connection orelse return error.ConnectionEditorUnavailable;
        try value.validate();
        if (value.payload_version != connection.payload_version) return error.UnsupportedPayloadVersion;
        try connection.validate_payload(value.payload);
        const encode = connection.encode orelse return error.ConnectionCodecUnavailable;
        const encoded = try encode(allocator, value);
        try encoded.validate();
        return encoded;
    }
    fn saveOnly(self: *Wizard) void {
        self.saveContributed(true);
    }
    fn saveAndOpen(self: *Wizard) void {
        self.saveContributed(false);
    }
    fn saveContributed(self: *Wizard, only: bool) void {
        if (self.disabled_edit != null) return self.saveDisabled();
        const editor = self.plugin_editor orelse return;
        var arena = std.heap.ArenaAllocator.init(self.alloc);
        defer arena.deinit();
        const value = editor.vtable.snapshot(editor.context, arena.allocator()) catch |err| {
            self.showError(err);
            return;
        };
        editorSubmit(self, value, if (only) .save else .save_and_open) catch |err| self.showError(err);
    }
    fn showError(self: *Wizard, err: anyerror) void {
        if (self.plugin_error) |node| {
            node.setTextContent(self.alloc, @errorName(err)) catch {};
            node.setDisplay(.flex);
        }
        self.cx.requestRedraw();
    }
    fn mountHeaderProtocol(self: *Wizard, cx: *ui.Cx, scope: *ui.Scope) !*ui.Node {
        // 有被禁用的插件（Q5）时面板按内容宽度展开，让“{名称} · 已禁用”完整显示（YWqSG）；否则同触发器宽。
        const panel_width: ui.widgets.select.PanelWidth = if (self.disabledLinkedCount() != 0) .content else .trigger;
        const select = try ui.widgets.Select(.{ .panel_width = panel_width, .options = self.protocol_options, .value = self.sig_protocol.?, .width = 152, .leading_icon = ui.icons.terminal, .disabled = self.locked.?, .on_change = cx.on(Wizard, self, protocolChanged) }).mount(scope, cx);
        self.protocol_select = select;
        self.protocol_picker = select.trigger;
        select.trigger.meta.ownership.meta.test_id = "wizard.protocol";
        return select.wrapper;
    }
    fn protocolChanged(self: *Wizard, value: ?[]const u8) void {
        const selected = value orelse return;
        if (std.mem.eql(u8, selected, self.protocol_id)) return;
        // 编辑已禁用插件的主机（Q5）：协议不能换（换了就成了另一台新主机，原载荷会丢）。
        if (self.disabled_edit != null) {
            self.sig_protocol.?.set(self.protocol_id);
            return;
        }
        // Dispose the provider only after the Select callback has returned.
        for (self.protocol_options) |option| if (std.mem.eql(u8, option.value, selected)) {
            self.queued_protocol = option.value;
            self.cx.requestRedraw();
            return;
        };
    }
    // ── 协议插件已禁用（PLUGIN_ARCH_PLAN 6.2.1 Q5） ──

    /// 已链接、但这次启动没有加载的随应用插件（区别于未知插件）。
    fn disabledLinked(self: *const Wizard, id: []const u8) ?@import("../model/plugin_availability.zig").Linked {
        const launch = self.plugin_launch orelse return null;
        return launch.disabled(id);
    }
    fn disabledLinkedCount(self: *const Wizard) usize {
        const launch = self.plugin_launch orelse return 0;
        var count: usize = 0;
        for (launch.linked(), launch.enabledFlags()) |linked, enabled| count += @intFromBool(!enabled and linked.creatable and self.plugin_registry.find(linked.id) == null);
        return count;
    }
    /// 编辑已禁用插件的已保存主机：卸下协议编辑器，挂原生提示 + 名称输入框；只能保存（不能连接、测试连接）。
    fn mountDisabledEditor(self: *Wizard, value: envelope_mod.Envelope, linked: @import("../model/plugin_availability.zig").Linked) !void {
        self.releaseContributedEditor();
        const scope = try self.scope.childScope();
        errdefer scope.dispose();
        var arena = std.heap.ArenaAllocator.init(self.alloc);
        errdefer arena.deinit();
        const envelope = try value.clone(arena.allocator());
        const title = try std.fmt.allocPrint(arena.allocator(), "{s} 已禁用", .{linked.display_name});
        const name = try scope.createSignal([]const u8, envelope.name);
        self.disabled_edit = .{ .arena = arena, .envelope = envelope, .name = name, .scope = scope };
        try scope.onCleanup(Wizard, self, disabledScopeGone);
        const edit = &self.disabled_edit.?;
        try edit.name_text.appendSlice(self.alloc, envelope.name);
        const view = try ui.view.render(scope, self.cx, @import("_disabled_plugin_editor.yix.zig").DisabledPluginEditor(.{ .title = title, .message = disabled_edit_message, .name = name, .on_name = self.cx.on(Wizard, self, disabledNameChanged) }));
        try self.plugin_slot.?.appendChild(self.alloc, view);
        self.protocol_id = linked.id;
        self.sig_protocol.?.set(linked.id);
        if (self.plugin_error) |node| node.setDisplay(.none);
        self.footer.?.setDisplay(.flex);
        if (self.save_open_button) |button| button.setDisplay(.none);
        self.refreshAppearance();
    }
    const disabled_edit_message = @import("../model/plugin_availability.zig").edit_message;
    fn disabledNameChanged(self: *Wizard, text: []const u8) void {
        const edit = &(self.disabled_edit orelse return);
        edit.name_text.clearRetainingCapacity();
        edit.name_text.appendSlice(self.alloc, text) catch return;
        edit.name.set(edit.name_text.items);
    }
    fn disabledScopeGone(self: *Wizard) void {
        if (self.disabled_edit) |*edit| edit.scope_disposed = true;
    }
    fn releaseDisabledEdit(self: *Wizard) void {
        var edit = self.disabled_edit orelse return;
        self.disabled_edit = null;
        if (!edit.scope_disposed) edit.scope.dispose();
        edit.name_text.deinit(self.alloc);
        edit.arena.deinit();
        self.destroyEditorNodes();
        if (self.save_open_button) |button| button.setDisplay(.flex);
    }
    /// 只替换名称后保存；载荷字节、版本、分组、修订号原样交给宿主（宿主不经插件编解码直接落盘）。
    fn saveDisabled(self: *Wizard) void {
        const edit = &(self.disabled_edit orelse return);
        if (self.saving) return;
        var value = edit.envelope;
        value.name = std.mem.trim(u8, edit.name_text.items, " \t");
        value.validate() catch |err| return self.showError(err);
        const submit = self.on_envelope orelse return self.showError(error.ConnectionSubmitUnavailable);
        self.saving = true;
        self.locked.?.set(true);
        defer {
            self.saving = false;
            self.locked.?.set(false);
        }
        submit(self.envelope_context orelse return self.showError(error.ConnectionSubmitUnavailable), value, .save) catch |err| return self.showError(err);
        self.hide();
    }

    fn refreshAppearance(self: *Wizard) void {
        const colors = S.theme.current();
        self.painted_colors = colors;
        // The Modal form keeps zenit's default panel surface; only the native window root repaints.
        if (self.window != null) if (self.modal) |node| node.setStyleInline(self.alloc, S.windowRoot());
        if (self.footer) |footer| footer.setBackground(S.footer().background.?);
        if (self.title) |node| node.setTextColor(colors.fg_1);
        if (self.protocol_select) |select| {
            var style = S.input();
            style.height = .{ .px = 28 };
            style.font_size = 13;
            select.trigger.setStyleInline(self.alloc, style);
            const manifest = self.plugin_registry.find(self.protocol_id);
            const asset = if (manifest) |value| @import("../../../../shared/ui/components/session_icon/session_icon.zig").asset(value.icons.protocol) else ui.icons.terminal;
            if (select.leading_icon) |icon| if (asset.icon_id) |id| if (asset.pickRep(14)) |rep| icon.setIcon(.{ .icon_id = id, .rep = rep, .tint = colors.fg_2 });
        }
        if (self.protocol_icon) |node| {
            const asset = if (self.presentation_warning) ui.icons.circle_alert else ui.icons.plug;
            if (asset.icon_id) |id| if (asset.pickRep(18)) |rep| node.setIcon(.{ .icon_id = id, .rep = rep, .tint = if (self.presentation_warning) colors.warn_ink else colors.accent });
        }
    }
    pub fn show(self: *Wizard) void {
        if (self.window) |slot| {
            // Create the window once, or raise the existing one.
            if (!self.mounted) {
                self.launch.show = true;
                _ = slot.present();
                return;
            }
            _ = slot.present();
        }
        self.refreshAppearance();
        const root = self.root orelse return;
        if (self.plugin_editor) |editor| if (editor.vtable.visibility_changed) |changed| changed(editor.context, true);
        self.open.?.set(true);
        root.setDisplay(.flex);
        root.setHitTestVisible(true);
        self.cx.requestRedraw();
    }
    pub fn hide(self: *Wizard) void {
        if (self.window) |slot| if (!self.mounted) {
            slot.close();
            self.launch.deinit();
            return;
        };
        const root = self.root orelse return;
        if (self.plugin_editor) |editor| {
            editor.vtable.clear_secrets(editor.context);
            if (editor.vtable.visibility_changed) |changed| changed(editor.context, false);
        }
        if (!self.saving) if (self.credentials) |credentials| credentials.clear();
        if (self.probe_host) |host| host.cancelParent(self.draft_id) catch {};
        self.open.?.set(false);
        root.setHitTestVisible(false);
        root.setDisplay(.none);
        // Saved or cancelled: the editor window goes away with its draft.
        if (self.window) |slot| if (!self.native_closing) slot.close();
    }
    pub fn cancel(self: *Wizard) void {
        if (self.plugin_editor) |editor| if (editor.vtable.cancel) |request| {
            request(editor.context);
            return;
        };
        self.hide();
        if (self.on_cancel) |callback| callback(self.cancel_context orelse return);
    }
    pub fn isVisible(self: *const Wizard) bool {
        return if (self.root) |root| root.style.display != .none else false;
    }
    fn openChanged(self: *Wizard, visible: bool) void {
        if (!visible and self.isVisible()) self.cancel();
    }
    pub fn updateViewport(self: *Wizard) bool {
        const node = self.modal orelse return false;
        // Modal's deferred style host can initialise after mount. Reapply the
        // owned content contract once, before natural editor height escapes it.
        var body_changed = false;
        if (self.theme_watch.take()) {
            self.refreshAppearance();
            body_changed = true;
        }
        const parent_visible = if (self.plugin_editor) |editor| if (editor.vtable.parent_presentation_visible) |get| get(editor.context) else true else true;
        // A native window keeps its frame; the nested copy dialog overlays it.
        if (self.window == null and self.parent_presentation_visible != parent_visible) {
            if (self.root) |barrier| {
                if (!parent_visible) self.parent_barrier_color = barrier.getBackground();
                barrier.setBackground(if (parent_visible) self.parent_barrier_color else ui.Color.TRANSPARENT);
            }
            node.setDisplay(if (parent_visible) .flex else .none);
            self.parent_presentation_visible = parent_visible;
            body_changed = true;
        }
        if (self.modal_body) |body| if (!std.meta.eql(body.style.padding, ui.Padding.ZERO)) {
            body.setStyleInline(self.alloc, S.modalBody());
            body_changed = true;
        };
        var desired_width = S.width;
        if (self.plugin_editor) |editor| if (editor.vtable.modal_presentation) |get| {
            const presentation = get(editor.context);
            if (std.math.isFinite(presentation.width) and presentation.width > 0) desired_width = @min(presentation.width, S.width);
            if (self.title) |title| if (title.getText()) |text| {
                if (!std.mem.eql(u8, text.content, presentation.title)) title.setTextContent(self.alloc, presentation.title) catch {};
            };
            if (self.presentation_warning != presentation.warning) {
                self.presentation_warning = presentation.warning;
                self.refreshAppearance();
                body_changed = true;
            }
        };
        // The native window is sized by its owner/user; content scrolls.
        if (self.window != null) return body_changed;
        const width = @min(desired_width, @max(1, self.cx.viewport.width - 32));
        var preferred = S.max_height;
        if (self.plugin_editor) |editor| if (editor.vtable.preferred_modal_height) |get| if (get(editor.context)) |value| {
            if (std.math.isFinite(value) and value > 0) preferred = @min(value, S.max_height);
        };
        const compact = self.cx.viewport.width <= 860 or self.cx.viewport.height <= 480;
        if (self.header) |header| {
            // Title bar is 44 in every window class (hb6dT zZR14 / o0vX11).
            const desired_h: f32 = S.header_height;
            if (header.style.height != .px or header.style.height.px != desired_h) {
                header.setStyleInline(self.alloc, S.header());
                body_changed = true;
            }
        }
        const height = @min(preferred, @max(1, self.cx.viewport.height - @as(f32, if (compact) 48 else 32)));
        const changed = node.style.width != .px or node.style.width.px != width or node.style.height != .px or node.style.height.px != height;
        if (changed) node.setStyleInline(self.alloc, .{ .width = .{ .px = width }, .height = .{ .px = height } });
        return changed or body_changed;
    }
    fn viewportHook(raw: *anyopaque, _: u8, _: bool) ui.AfterLayoutResult {
        const self: *Wizard = @ptrCast(@alignCast(raw));
        if (self.queued_protocol) |selected| {
            self.queued_protocol = null;
            self.selectContribution(selected) catch |err| self.showError(err);
            return .needs_layout;
        }
        return if (self.updateViewport()) .needs_layout else .done;
    }
    fn cleanup(self: *Wizard) void {
        self.cx.removeAfterLayoutHook(self);
        self.releaseContributedEditor();
        self.alloc.free(self.protocol_options);
        self.protocol_options = &.{};
        for (self.owned_ids.items) |value| self.alloc.free(value);
        self.owned_ids.deinit(self.alloc);
        self.owned_ids = .empty;
        // The window (or test Cx) owning these nodes and signals is gone.
        self.mounted = false;
        self.root = null;
        self.modal = null;
        self.modal_body = null;
        self.header = null;
        self.title = null;
        self.footer = null;
        self.plugin_error = null;
        self.protocol_icon = null;
        self.protocol_picker = null;
        self.protocol_select = null;
        self.painted_colors = null;
        self.theme_watch = .{};
        self.open = null;
        self.locked = null;
        self.sig_protocol = null;
        self.publication = null;
    }
};

test "registered editor owns the shared wizard slot and survives shell reopen" {
    const Driver = struct {
        mounts: usize = 0,
        releases: usize = 0,
        clears: usize = 0,
        submits: usize = 0,
        fn mount(raw: ?*anyopaque, args: plugin_ui.EditorMount) !plugin_ui.EditorInstance {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.mounts += 1;
            try args.slot.appendChild(args.cx.allocator, try ui.text(args.cx, "custom editor", .{}));
            return .{ .context = self, .vtable = &.{ .snapshot = snapshot, .clear_secrets = clear, .unmount = release } };
        }
        fn snapshot(_: *anyopaque, _: std.mem.Allocator) !envelope_mod.Envelope {
            return .{ .protocol_id = "spec.editor", .name = "retained draft", .payload = "{}" };
        }
        fn clear(raw: *anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.clears += 1;
        }
        fn release(raw: *anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.releases += 1;
        }
        fn validate(_: []const u8) !void {}
        fn codec(allocator: std.mem.Allocator, value: envelope_mod.Envelope) !envelope_mod.Envelope {
            return value.clone(allocator);
        }
        fn submit(raw: *anyopaque, value: envelope_mod.Envelope, _: plugin_ui.SubmitIntent) !void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            try std.testing.expectEqualStrings("spec.editor", value.protocol_id);
            try std.testing.expectEqualStrings("retained draft", value.name);
            self.submits += 1;
        }
    };
    var driver: Driver = .{};
    const manifests = [_]plugins.PluginManifest{.{ .id = "spec.editor", .display_name = "Custom editor", .workspace_kind = "custom", .content_renderer = "custom", .connection = .{ .editor_factory = .{ .context = &driver, .mount = Driver.mount }, .validate_payload = Driver.validate, .encode = Driver.codec, .decode = Driver.codec } }};
    const source: plugins.Registry = .{ .published = .{ .entries = &manifests, .renderers = &.{} } };
    const cx = try ui.Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    const scope = try ui.Scope.init(std.testing.allocator, null, cx.owner);
    cx.setViewport(900, 700);
    cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    var wizard: Wizard = .{};
    wizard.setRegistry(source);
    wizard.on_envelope = Driver.submit;
    wizard.envelope_context = &driver;
    try cx.root.?.appendChild(cx.allocator, try wizard.mount(cx, scope));
    try std.testing.expectEqual(@as(usize, 1), wizard.protocol_options.len);
    try std.testing.expectEqualStrings("spec.editor", wizard.protocol_options[0].value);
    wizard.show();
    try std.testing.expect(wizard.plugin_editor != null);
    try std.testing.expectEqual(ui.types.Display.flex, wizard.plugin_slot.?.style.display);
    wizard.hide();
    wizard.show();
    try std.testing.expectEqual(@as(usize, 1), driver.mounts);
    wizard.saveContributed(true);
    try std.testing.expectEqual(@as(usize, 1), driver.submits);
    scope.dispose();
    try std.testing.expectEqual(@as(usize, 1), driver.releases);
    try std.testing.expect(driver.clears >= 2);
}

test "registered editor clears its secrets while its fields are alive when the window tears down" {
    // A window close disposes the editor through the window's root scope: no hide / save path
    // runs first. The editor's fields (Input state) live in child scopes of the editor scope.
    const Driver = struct {
        field_alive: bool = false,
        clears_alive: usize = 0,
        clears_after_fields: usize = 0,
        fn mount(raw: ?*anyopaque, args: plugin_ui.EditorMount) !plugin_ui.EditorInstance {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            const field = try args.scope.childScope();
            try field.onCleanup(@This(), self, fieldGone);
            self.field_alive = true;
            try args.slot.appendChild(args.cx.allocator, try ui.text(args.cx, "editor with a password field", .{}));
            return .{ .context = self, .vtable = &.{ .snapshot = snapshot, .clear_secrets = clear, .unmount = release } };
        }
        fn fieldGone(self: *@This()) void {
            self.field_alive = false;
        }
        fn snapshot(_: *anyopaque, _: std.mem.Allocator) !envelope_mod.Envelope {
            return error.EditorClosed;
        }
        fn clear(raw: *anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            if (self.field_alive) self.clears_alive += 1 else self.clears_after_fields += 1;
        }
        fn release(_: *anyopaque) void {}
        fn validate(_: []const u8) !void {}
        fn codec(allocator: std.mem.Allocator, value: envelope_mod.Envelope) !envelope_mod.Envelope {
            return value.clone(allocator);
        }
    };
    var driver: Driver = .{};
    const manifests = [_]plugins.PluginManifest{.{ .id = "spec.secret", .display_name = "Secret editor", .workspace_kind = "custom", .content_renderer = "custom", .connection = .{ .editor_factory = .{ .context = &driver, .mount = Driver.mount }, .validate_payload = Driver.validate, .encode = Driver.codec, .decode = Driver.codec } }};
    const source: plugins.Registry = .{ .published = .{ .entries = &manifests, .renderers = &.{} } };
    const cx = try ui.Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    const scope = try ui.Scope.init(std.testing.allocator, null, cx.owner);
    cx.setViewport(900, 700);
    cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    var wizard: Wizard = .{};
    wizard.setRegistry(source);
    try cx.root.?.appendChild(cx.allocator, try wizard.mount(cx, scope));
    wizard.show();
    try std.testing.expect(wizard.plugin_editor != null);
    try std.testing.expect(driver.field_alive);
    scope.dispose();
    try std.testing.expect(!driver.field_alive);
    try std.testing.expect(driver.clears_alive >= 1);
    try std.testing.expectEqual(@as(usize, 0), driver.clears_after_fields);
}

test "fixture nested editor opens its registered child from real pointer dispatch" {
    const fixtures = @import("../../../../plugins/fixture_probe/plugin.zig");
    const Driver = struct {
        fn create(_: *anyopaque, _: @import("../../../../host/session_host.zig").CreateRequest) !void {}
        fn cancel(_: *anyopaque, _: @import("../../../../host/session_host.zig").OperationKey) @import("../../../../host/session_host.zig").CloseReceipt {
            return .released;
        }
        fn close(_: *anyopaque, _: identity.SessionHandle, _: @import("../../../../host/session_host.zig").OperationKey) !@import("../../../../host/session_host.zig").CloseReceipt {
            return .released;
        }
        fn stale(_: *anyopaque, _: identity.SessionHandle, _: @import("../../../../host/session_host.zig").OperationKey) void {}
        fn validate(_: []const u8) !void {}
        fn codec(a: std.mem.Allocator, value: envelope_mod.Envelope) !envelope_mod.Envelope {
            return value.clone(a);
        }
        fn migrate(a: std.mem.Allocator, value: envelope_mod.Envelope, _: u32) !envelope_mod.Envelope {
            return value.clone(a);
        }
        fn save(_: *anyopaque, _: envelope_mod.Envelope) !identity.AssetOwner {
            return .{ .id = @fromBackingInt(91), .revision = 1 };
        }
        fn find(node: *ui.Node, id: []const u8) ?*ui.Node {
            if (node.meta.ownership.meta.test_id) |actual| if (std.mem.eql(u8, actual, id)) return node;
            for (node.children.items) |child| if (find(child, id)) |found| return found;
            return null;
        }
        fn click(cx: *ui.Cx, node: *ui.Node) void {
            const rect = node.globalRect();
            cx.handleClick(rect.x + rect.w / 2, rect.y + rect.h / 2);
            cx.handleMouseUpEx(rect.x + rect.w / 2, rect.y + rect.h / 2, .left, .{});
        }
    };
    const a = std.testing.allocator;
    const fixture = try fixtures.Plugin.init(a);
    defer fixture.deinit();
    var definitions = plugins.PluginHost.init(a);
    defer definitions.deinit();
    try definitions.registerRenderer(.{ .kind = "terminal", .shared_renderer = true });
    try definitions.registerRenderer(fixture.renderer());
    var driver: u8 = 0;
    const factory: @import("../../../../host/session_host.zig").Adapter.VTable = .{ .create = Driver.create, .cancel = Driver.cancel, .close = Driver.close, .release_stale = Driver.stale };
    try definitions.register(.{ .id = "ssh", .display_name = "SSH", .connection = .{ .create_kind = .saved_or_temporary, .editor_factory = .{ .mount = @import("../../../../plugins/remote/editor_factory.zig").mount }, .validate_payload = Driver.validate, .encode = Driver.codec, .decode = Driver.codec, .migrate = Driver.migrate }, .session_factory = .{ .context = &driver, .vtable = &factory }, .workspace_kind = "terminal", .content_renderer = "terminal" });
    try definitions.register(fixture.manifest());
    var source = try definitions.publish();
    defer source.deinit();
    const cx = try ui.Cx.init(a, std.testing.io);
    defer cx.deinit();
    cx.setViewport(1440, 900);
    try cx.setTestFrameStep(100);
    cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    const scope = try ui.Scope.init(a, null, cx.owner);
    defer scope.dispose();
    const parent = try cx.bindState(Wizard, .{});
    parent.setRegistry(source);
    try cx.root.?.appendChild(a, try parent.mount(cx, scope));
    const nested = try @import("../host/plugin_editor_host.zig").Host.mount(cx, scope, parent, source, .{ .context = &driver, .save = Driver.save });
    try cx.root.?.appendChild(a, nested.root);
    defer parent.releaseContributedEditor();
    try parent.selectContribution("fixture_probe");
    parent.show();
    for (0..4) |_| {
        cx.advanceFrameClock();
        _ = cx.render();
    }
    var retained_arena = std.heap.ArenaAllocator.init(a);
    defer retained_arena.deinit();
    const parent_instance = parent.plugin_editor.?;
    const before = try parent_instance.vtable.snapshot(parent_instance.context, retained_arena.allocator());
    const route = Driver.find(parent.plugin_slot.?, "fixture.route").?;
    Driver.click(cx, route);
    for (0..4) |_| {
        cx.advanceFrameClock();
        _ = cx.render();
    }
    const child_button = Driver.find(parent.plugin_slot.?, "fixture.child_ssh").?;
    try std.testing.expect(child_button.isDisplayedInTree());
    Driver.click(cx, child_button);
    for (0..4) |_| {
        cx.advanceFrameClock();
        _ = cx.render();
    }
    try std.testing.expect(nested.host.active != null);
    try std.testing.expect(nested.host.child.open.?.get());
    try std.testing.expect(nested.host.child.root.?.isDisplayedInTree());
    const name = Driver.find(nested.host.child.root.?, "wizard.name").?;
    try std.testing.expect(name.isDisplayedInTree());
    const cancel_button = Driver.find(nested.host.child.root.?, "wizard.cancel").?;
    Driver.click(cx, cancel_button);
    for (0..4) |_| {
        cx.advanceFrameClock();
        _ = cx.render();
    }
    try std.testing.expect(nested.host.active == null);
    try std.testing.expect(!nested.host.child.isVisible());
    try std.testing.expect(parent.isVisible());
    try std.testing.expectEqual(parent_instance.context, parent.plugin_editor.?.context);
    try std.testing.expect(child_button.isDisplayedInTree());
    Driver.click(cx, route);
    for (0..4) |_| {
        cx.advanceFrameClock();
        _ = cx.render();
    }
    const after = try parent_instance.vtable.snapshot(parent_instance.context, retained_arena.allocator());
    try std.testing.expectEqualStrings(before.name, after.name);
    try std.testing.expectEqualStrings(before.payload, after.payload);
}

test "wizard native window opens once, re-raises, and closes on cancel, native close and save" {
    const Driver = struct {
        mounts: usize = 0,
        submits: usize = 0,
        cancels: usize = 0,
        fn mount(raw: ?*anyopaque, args: plugin_ui.EditorMount) !plugin_ui.EditorInstance {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.mounts += 1;
            try args.slot.appendChild(args.cx.allocator, try ui.text(args.cx, "window editor", .{}));
            return .{ .context = self, .vtable = &.{ .snapshot = snapshot, .clear_secrets = noop, .unmount = noop } };
        }
        fn snapshot(_: *anyopaque, _: std.mem.Allocator) !envelope_mod.Envelope {
            return .{ .protocol_id = "spec.window", .name = "window draft", .payload = "{}" };
        }
        fn noop(_: *anyopaque) void {}
        fn validate(_: []const u8) !void {}
        fn codec(allocator: std.mem.Allocator, value: envelope_mod.Envelope) !envelope_mod.Envelope {
            return value.clone(allocator);
        }
        fn submit(raw: *anyopaque, value: envelope_mod.Envelope, _: plugin_ui.SubmitIntent) !void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            try std.testing.expectEqualStrings("window draft", value.name);
            self.submits += 1;
        }
        fn cancelled(raw: *anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.cancels += 1;
        }
    };
    const Runtime = struct {
        activated: usize = 0,
        closed: usize = 0,
        fn activate(raw: *anyopaque, _: aux_window.WindowId) bool {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.activated += 1;
            return true;
        }
        fn close(raw: *anyopaque, _: aux_window.WindowId) bool {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.closed += 1;
            return true;
        }
    };
    var driver: Driver = .{};
    var native: Runtime = .{};
    aux_window.runtime = .{ .context = &native, .activate = Runtime.activate, .close = Runtime.close };
    defer aux_window.runtime = null;
    const manifests = [_]plugins.PluginManifest{.{ .id = "spec.window", .display_name = "Window editor", .workspace_kind = "custom", .content_renderer = "custom", .connection = .{ .editor_factory = .{ .context = &driver, .mount = Driver.mount }, .validate_payload = Driver.validate, .encode = Driver.codec, .decode = Driver.codec } }};
    const source: plugins.Registry = .{ .published = .{ .entries = &manifests, .renderers = &.{} } };
    var wizard: Wizard = .{};
    defer wizard.detachWindow();
    wizard.setRegistry(source);
    wizard.on_envelope = Driver.submit;
    wizard.envelope_context = &driver;
    wizard.on_cancel = Driver.cancelled;
    wizard.cancel_context = &driver;
    wizard.attachWindow(1);
    const Native = struct {
        cx: *ui.Cx,
        scope: *ui.Scope,
        // Stand-in for ProcessWindows.drainAux: create + mount one window.
        fn create(w: *Wizard, id: aux_window.WindowId) !@This() {
            const slot = aux_window.takePending() orelse return error.NoPendingWindow;
            try std.testing.expectEqual(w.window.?, slot);
            try std.testing.expectEqual(@as(?aux_window.WindowId, 1), slot.owner);
            try std.testing.expectEqual(@as(u16, 720), slot.spec.width);
            const cx = try ui.Cx.init(std.testing.allocator, std.testing.io);
            errdefer cx.deinit();
            cx.setViewport(720, 640);
            const scope = try ui.Scope.init(std.testing.allocator, null, cx.owner);
            aux_window.beginMount(slot);
            defer aux_window.endMount();
            // App.mount provides the window root and its overlay portal first.
            cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
            try cx.root.?.appendChild(cx.allocator, try aux_window.mount(cx, scope));
            slot.opened(id);
            return .{ .cx = cx, .scope = scope };
        }
        fn destroy(self: @This()) void {
            self.scope.dispose();
            self.cx.deinit();
        }
    };

    // Requests before the window exists are replayed on mount; nothing is
    // mounted into the caller's window.
    try wizard.selectContribution("spec.window");
    wizard.show();
    try std.testing.expect(wizard.isOpen());
    try std.testing.expect(!wizard.isVisible());
    try std.testing.expectEqual(@as(usize, 0), driver.mounts);
    wizard.show();
    try std.testing.expectEqual(aux_window.Phase.pending, wizard.window.?.phase);

    // 1. Opening creates one independent window with the editor mounted.
    var first = try Native.create(&wizard, 5);
    try std.testing.expect(wizard.isVisible());
    try std.testing.expect(aux_window.owns(5));
    try std.testing.expectEqual(@as(usize, 1), driver.mounts);
    try std.testing.expectEqualStrings("spec.window", wizard.protocol_id);
    try std.testing.expectEqual(first.cx.root.?, wizard.root.?.parent.?);
    // 2. Opening again raises the same window; no second window is queued.
    wizard.show();
    try std.testing.expectEqual(@as(usize, 1), native.activated);
    try std.testing.expectEqual(@as(?*aux_window.Slot, null), aux_window.takePending());
    try std.testing.expectEqual(@as(u32, 1), wizard.window.?.created);
    // 3. Closing the window is the editor's cancel.
    try std.testing.expect(aux_window.closeRequest(5));
    try std.testing.expectEqual(@as(usize, 1), driver.cancels);
    try std.testing.expect(!wizard.isVisible());
    first.destroy();
    try std.testing.expect(!wizard.mounted);
    try std.testing.expect(!wizard.isOpen());
    try std.testing.expect(!aux_window.owns(5));

    // 4. Saving hands the envelope back to the owner and closes the window.
    wizard.show();
    var second = try Native.create(&wizard, 6);
    try std.testing.expect(wizard.isVisible());
    const closed_before = native.closed;
    wizard.saveContributed(true);
    try std.testing.expectEqual(@as(usize, 1), driver.submits);
    try std.testing.expect(!wizard.isVisible());
    try std.testing.expectEqual(closed_before + 1, native.closed);
    try std.testing.expectEqual(aux_window.Phase.closing, wizard.window.?.phase);
    second.destroy();
    try std.testing.expectEqual(aux_window.Phase.closed, wizard.window.?.phase);
    try std.testing.expectEqual(@as(u32, 2), wizard.window.?.created);
}
