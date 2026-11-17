//! AI 子会话对话框 ChildDialog（P2 自 src/main.zig 原样拆出）。

const std = @import("std");
const ui = @import("ui");
const AiController = @import("../../../ai/float_view.zig").Controller;
const AiManager = @import("../../../ai/turn_manager.zig").Manager;
const app_theme = @import("../../../shared/ui/theme/app_theme.zig");
const panel_header = @import("../../../shared/ui/components/panel_header/panel_header.zig");
const AiHost = @import("ai_host.zig").AiHost;
const IdSpace = @import("../shared/view/ai_id_space.zig").IdSpace;
const child_projection = @import("../../../ai/child_projection.zig");
const mountAssistantConversation = @import("ai_host.zig").mountAssistantConversation;

/// A presentation subscription, never an execution owner or a second Worker.
pub const ChildDialog = struct {
    parent: *AiHost,
    host: *AiHost,
    scope: *ui.Scope,
    open: *ui.Signal(bool),
    dialog: *ui.Node,
    parent_label: *ui.Node,
    restore_parent: *ui.Node = undefined,
    last_writable: ?bool = null,
    title: *ui.Node = undefined,
    task_summary: *ui.Node = undefined,
    history_label: *ui.Node = undefined,
    history_arrow: *ui.Node = undefined,
    history_toggle: *ui.Node = undefined,
    props: *ui.Node,
    props_open: *ui.Signal(bool),
    apply_disabled: *ui.Signal(bool),
    props_scroll: *ui.Node = undefined,
    props_chrome: *ui.Node = undefined,
    status_label: *ui.Signal([]const u8) = undefined,
    status_color: *ui.Signal(ui.widgets.tag.TagColor) = undefined,
    /// The dialog's geometry, handed to the native Modal (its `width` / `height` / `max_height`
    /// sources): follows the window size and 放大 / 还原 (`fit`), never written onto the panel.
    dialog_width: *ui.Signal(f32),
    dialog_height: *ui.Signal(?f32),
    dialog_max_height: *ui.Signal(f32),
    /// The window size the geometry was last fitted to (`ViewportFit` refits only when it changes).
    fitted_width: f32 = 0,
    fitted_height: f32 = 0,
    maximized: bool = false,
    /// 任务记录 disclosure state (the native Pressable's `expanded`, also its accessible state).
    history_open: *ui.Signal(bool) = undefined,
    name: *ui.Signal([]const u8),
    reusable: *ui.Signal(bool),
    skill_bits: u32 = 0,
    mcp_bits: u32 = 0,
    target_bits: u32 = 0,
    target_handles: [32]@import("../../../host/identity.zig").SessionHandle = undefined,
    target_count: usize = 0,
    revision: u64,
    released: bool = false,
    pub fn mount(parent: *AiHost, record: *@import("../../../ai/session_lifecycle.zig").Record) !*ChildDialog {
        const cx = parent.cx;
        const scope = try parent.scope.?.childScope();
        errdefer scope.dispose();
        // Everything mounted under this Scope names its nodes in the child namespace (`ai.child.*`).
        try IdSpace.provideChild(scope);
        const open = try scope.createSignal(bool, true);
        const size = dialogSize(cx.viewport.width, cx.viewport.height, false);
        const dialog_width = try scope.createSignal(f32, size.width);
        const dialog_height = try scope.createSignal(?f32, size.height);
        const dialog_max_height = try scope.createSignal(f32, size.height);
        const modal = try ui.widgets.Modal(.{ .open = open, .width = dialog_width, .height = dialog_height, .max_height = dialog_max_height }).mount(scope, cx);
        if (!modal.portaled) if (cx.root) |root| try root.appendChild(cx.allocator, modal.overlay);
        modal.dialog.meta.ownership.meta.test_id = "ai.child.dialog";
        modal.body.setStyleInline(cx.allocator, .{ .width = .fill(), .height = .fill(), .flex = 1, .min_height = 0, .direction = .column, .padding = .{}, .gap = 0 });
        const service = parent.shared_service.?;
        const state = try service.presentations.createChildPresentation(record, record.initial_origin orelse parent.display_owner.?);
        const prefs = @import("../../../ai/session_lifecycle.zig").Store.childPreferences(record);
        const prompt = try scope.createText(record.draft orelse state.draft orelse "", .{});
        const host = try cx.allocator.create(AiHost);
        host.* = .{ .allocator = cx.allocator, .cx = cx, .scope = scope, .controller = AiController.init(cx.allocator), .manager = AiManager.init(cx.allocator), .stream_mailbox = @import("../../../ai/stream_mailbox.zig").Mailbox.init(cx.allocator), .step_mailbox = @import("../../../ai/step_events.zig").Mailbox.init(cx.allocator), .tool_bridge = @import("../tools/host/ai_tools.zig").Bridge.init(std.heap.c_allocator), .execution_bridge = @import("../tools/host/ai_tools.zig").Bridge.init(std.heap.c_allocator), .tool_results = @import("../../../ai/tool_results.zig").Store.init(cx.allocator), .provider = parent.provider, .native_context = null, .native_client = null, .native_binding = null, .endpoint = "", .model = "", .panel = modal.body, .prompt = prompt, .runtime_config = parent.runtime_config, .assistant_states = &service.presentations, .shared_service = service, .workspace = parent.workspace, .application_host = parent.application_host, .roster = parent.roster, .file_application = parent.file_application, .data_root = parent.data_root, .recording_archive = parent.recording_archive, .notification_window = parent.notification_window, .child_identity = record.child.?.info.agent, .child_parent = parent, .id_space = .child, .display_conversation = state.id, .display_owner = state.owner, .settings_host = parent.settings_host };
        try scope.onCleanup(AiHost, host, AiHost.cleanup);
        // The dialog's own phases board: its rows follow the shared conversations for as long as the
        // dialog lives, independent of the parent's content view (released while the panel is closed).
        host.child_phases = try @import("../sessions/model/view_model.zig").SessionPhases.mount(scope, cx.allocator, &service.presentations);
        try host.bindWindowWake();
        const self = try scope.createState(ChildDialog, .{ .parent = parent, .host = host, .scope = scope, .open = open, .dialog = modal.dialog, .parent_label = undefined, .props = undefined, .props_open = try scope.createSignal(bool, false), .apply_disabled = try scope.createSignal(bool, !host.childCanWrite()), .dialog_width = dialog_width, .dialog_height = dialog_height, .dialog_max_height = dialog_max_height, .fitted_width = cx.viewport.width, .fitted_height = cx.viewport.height, .name = try scope.createText(prefs.name, .{}), .reusable = try scope.createSignal(bool, prefs.reusable), .revision = record.child_settings_revision });
        // Closed by Esc / the close button inside the Modal: the parent's pass releases it.
        try parent.wakeOnChange(bool, scope, open);
        const shell = try @import("../pane/view/ai_assistant_header.zig").mount(cx, scope, modal.body, prefs.name);
        const heading = shell.bar;
        self.title = shell.owner;
        self.title.meta.ownership.meta.test_id = "ai.child.name";
        // O9: status is a native W.Tag sm (accent while it works, warning when it waits for the user,
        // success / neutral when it has ended); the host writes its label (`status_label`).
        self.status_label = try scope.createText("", .{});
        self.status_color = try scope.createSignal(ui.widgets.tag.TagColor, .accent);
        const child_status = try ui.view.render(scope, cx, ui.widgets.Tag(.{ .label = self.status_label, .color = self.status_color, .size = .sm }));
        host.status_label = self.status_label;
        self.showStatus(child_projection.entry(&service.service, record));
        child_status.meta.ownership.meta.test_id = "ai.child.status";
        try shell.owner_pill.appendChild(cx.allocator, child_status);
        const properties = try ui.widgets.Button(.{ .icon_only = true, .icon_asset = ui.icons.settings_2, .icon_size = 14, .a11y_label = "子智能体设置", .variant = .ghost, .size = .sm, .on_click = cx.on(ChildDialog, self, toggleProps) }).mount(scope, cx);
        properties.meta.ownership.meta.test_id = "ai.child.properties";
        const properties_hint = try @import("../../../shared/ui/components/control_hint/control_hint.zig").mount(cx, scope, properties, "子智能体设置", .{ .id = "ai.child.properties.hint", .layout = .{ .width = .{ .px = 24 }, .height = .{ .px = 24 }, .flex_shrink = 0 } });
        try heading.appendChild(cx.allocator, properties_hint.wrapper);
        const collapse = try ui.widgets.Button(.{ .variant = .ghost, .icon_only = true, .icon_asset = ui.icons.minus, .icon_size = 14, .a11y_label = "收起子对话", .size = .sm, .on_click = cx.on(ChildDialog, self, close) }).mount(scope, cx);
        collapse.meta.ownership.meta.test_id = "ai.child.collapse";
        try heading.appendChild(cx.allocator, collapse);
        const maximize = try ui.widgets.Button(.{ .variant = .ghost, .icon_only = true, .icon_asset = ui.icons.get("maximize-2").?, .icon_size = 14, .a11y_label = "放大或还原子对话", .size = .sm, .on_click = cx.on(ChildDialog, self, toggleMaximize) }).mount(scope, cx);
        maximize.meta.ownership.meta.test_id = "ai.child.maximize";
        try heading.appendChild(cx.allocator, maximize);
        // panel-heads：统一关闭按钮（Modal 的 Esc 同样关闭子对话）。
        try heading.appendChild(cx.allocator, try panel_header.mountClose(scope, cx, .{ .label = "关闭子智能体", .test_id = "ai.child.close", .on_close = cx.on(ChildDialog, self, close) }));
        var parent_text: [192]u8 = undefined;
        self.parent_label = try ui.textStyled(cx, @import("../pane/view/ai_child_header_styles.zig").subtitle, try std.fmt.bufPrint(&parent_text, "父对话 {s} · {s}上下文", .{ std.fmt.bytesToHex(record.child.?.info.owning_parent_conversation.bytes, .lower)[0..8], if (record.child.?.info.context_mode == .inherit) "继承" else "独立" }));
        self.parent_label.setStyleInline(cx.allocator, @import("../pane/view/ai_child_header_styles.zig").subtitleBox());
        // O9: 父对话 · 上下文 is the header's subtitle (after the status Tag).
        try shell.owner_pill.appendChild(cx.allocator, self.parent_label);
        self.parent_label.meta.ownership.meta.test_id = "ai.child.parent";
        self.restore_parent = try ui.widgets.Button(.{ .label = "恢复父对话…", .variant = .secondary, .on_click = cx.on(ChildDialog, self, restoreParent) }).mount(scope, cx);
        self.restore_parent.meta.ownership.meta.test_id = "ai.child.restore_parent";
        self.restore_parent.setDisplay(.none);
        const popup = try ui.widgets.Popover(.{ .open = self.props_open, .trigger = .manual, .anchor = .{ .node = properties }, .position = .bottom_end, .offset = .{ .static = 8 }, .width = 320, .max_height = @max(120, @min(420, cx.viewport.height - 32)), .close_on_escape = true, .close_on_outside_click = true, .constrain_width_to_viewport = true, .flip = true, .shift_main_axis = true, .viewport_padding = 16 }).mount(scope, cx);
        popup.wrapper.setStyleInline(cx.allocator, .{ .position = .absolute, .width = .{ .px = 0 }, .height = .{ .px = 0 } });
        self.props = popup.content;
        self.props_chrome = popup.chrome;
        self.props_chrome.meta.ownership.meta.test_id = "ai.child.settings";
        self.props.setStyleInline(cx.allocator, .{ .width = .fill(), .direction = .column, .gap = 0 });
        self.props_chrome.setStyleInline(cx.allocator, @import("../sessions/view/ai_children_styles.zig").settings(cx.tokens));
        try heading.appendChild(cx.allocator, popup.wrapper);
        const props_heading = try ui.box(cx, .{ .width = .fill(), .height = .{ .px = 36 }, .direction = .row, .align_items = .center, .padding = .{ .left = 12, .right = 8 }, .gap = 8, .flex_shrink = 0 }, .{});
        const props_title = try ui.textStyled(cx, @import("../sessions/view/ai_children_styles.zig").name, "子智能体设置");
        props_title.setStyleInline(cx.allocator, .{ .width = .fill(), .flex = 1 });
        try props_heading.appendChild(cx.allocator, props_title);
        // panel-heads：统一关闭按钮（设置 Popover `close_on_escape`）。
        try props_heading.appendChild(cx.allocator, try panel_header.mountClose(scope, cx, .{ .label = "关闭子智能体设置", .test_id = "ai.child.settings.close", .on_close = cx.on(ChildDialog, self, toggleProps) }));
        try self.props.appendChild(cx.allocator, props_heading);
        const props_scroll = try ui.widgets.ScrollArea(.{ .direction = .vertical }).mount(scope, cx);
        self.props_scroll = props_scroll.container;
        props_scroll.container.setStyleInline(cx.allocator, @import("../sessions/view/ai_children_styles.zig").settingsBody(cx.viewport.height));
        props_scroll.container.meta.ownership.meta.test_id = "ai.child.settings.viewport";
        props_scroll.content.setStyleInline(cx.allocator, @import("../sessions/view/ai_children_styles.zig").settingsContent(cx.tokens));
        try self.props.appendChild(cx.allocator, props_scroll.container);
        const name_field = try ui.boxStyled(cx, @import("../sessions/view/ai_children_styles.zig").settingsRow, .{});
        const name_label = try ui.textStyled(cx, @import("../sessions/view/ai_children_styles.zig").settingLabel, "名称");
        name_label.meta.ownership.meta.test_id = "ai.child.property.name.label";
        name_label.setStyleInline(cx.allocator, .{ .width = .{ .px = 48 }, .flex_shrink = 0 });
        try name_field.appendChild(cx.allocator, name_label);
        const name = try ui.widgets.Input(.{ .value = self.name, .placeholder = "子智能体名称", .on_change = cx.on(ChildDialog, self, nameChanged) }).mount(scope, cx);
        name.meta.ownership.meta.test_id = "ai.child.property.name";
        name.setStyleInline(cx.allocator, .{ .width = .fill(), .flex = 1, .min_width = 0 });
        try name_field.appendChild(cx.allocator, name);
        try props_scroll.content.appendChild(cx.allocator, name_field);
        const reuse_row = try ui.boxStyled(cx, @import("../sessions/view/ai_children_styles.zig").settingsRow, .{});
        const reuse = try ui.widgets.Switch(.{ .checked = self.reusable, .on_change = cx.on(ChildDialog, self, reusableChanged) }).mount(scope, cx);
        reuse.meta.ownership.meta.test_id = "ai.child.property.reusable";
        const reuse_label = try ui.textStyled(cx, @import("../sessions/view/ai_children_styles.zig").settingLabel, "允许模型自动复用");
        reuse_label.setStyleInline(cx.allocator, .{ .width = .fill(), .flex = 1, .min_width = 0 });
        try reuse_row.appendChild(cx.allocator, reuse_label);
        try reuse_row.appendChild(cx.allocator, reuse);
        try props_scroll.content.appendChild(cx.allocator, reuse_row);
        const options_section = try ui.box(cx, .{ .width = .fill(), .direction = .column, .gap = 4, .flex_shrink = 0 }, .{});
        const options_divider = try ui.boxStyled(cx, @import("../sessions/view/ai_children_styles.zig").divider, .{});
        try props_scroll.content.appendChild(cx.allocator, options_divider);
        try options_section.appendChild(cx.allocator, try ui.textStyled(cx, @import("../sessions/view/ai_children_styles.zig").settingLabel, "授权范围"));
        try props_scroll.content.appendChild(cx.allocator, options_section);
        const info = record.child.?.info;
        inline for (.{ "skill_ids", "mcp_ids" }, 0..) |field, kind| for (@field(info, field), 0..) |key, i| {
            const chosen = for (@field(prefs, field)) |selected| {
                if (std.mem.eql(u8, key, selected)) break true;
            } else false;
            if (chosen) {
                if (kind == 0) self.skill_bits |= @as(u32, 1) << @intCast(i) else self.mcp_bits |= @as(u32, 1) << @intCast(i);
            }
            try self.option(options_section, if (kind == 0) "技能" else "MCP", key, @intCast(kind), i, chosen);
        };
        if (host.currentBinding()) |owner| {
            const allowed = try parent.captureOwnerScope(owner);
            defer if (allowed.inventory) |ids| parent.allocator.free(ids);
            for (allowed.memberIds()) |session_id| {
                if (self.target_count == 32) break;
                const tab = host.tabForSession(session_id) orelse continue;
                const handle = tab.content_owner.session;
                const i = self.target_count;
                self.target_handles[i] = handle;
                self.target_count += 1;
                const chosen = for (prefs.targets) |target| {
                    if (target.eql(handle)) break true;
                } else false;
                if (chosen) self.target_bits |= @as(u32, 1) << @intCast(i);
                try self.option(options_section, "目标", tab.titleSlice(), 2, i, chosen);
            }
        }
        if (info.skill_ids.len == 0 and info.mcp_ids.len == 0 and self.target_count == 0) {
            options_section.setDisplay(.none);
            options_divider.setDisplay(.none);
        }
        // 任务记录: a native Pressable (button semantics, no look of its own) holding the caller's
        // chevron + label; its `expanded` is the disclosure state.
        self.history_open = try scope.createSignal(bool, false);
        self.history_toggle = try ui.view.render(scope, cx, ui.widgets.Pressable(.{ .a11y_label = "任务记录", .expanded = self.history_open, .look = @import("../sessions/view/_ai_children_rows.yss.zig").history_row, .on_click = cx.on(ChildDialog, self, toggleHistory) }));
        self.history_toggle.meta.ownership.meta.test_id = "ai.child.tasks.toggle";
        self.history_arrow = try ui.iconTint(cx, ui.icons.chevron_right, app_theme.current().fg_2, .{ .width = .{ .px = 12 }, .height = .{ .px = 12 }, .flex_shrink = 0 });
        self.history_label = try ui.textStyled(cx, @import("../sessions/view/ai_children_styles.zig").settingLabel, "任务记录");
        self.history_label.setStyleInline(cx.allocator, .{ .width = .fill(), .flex = 1, .min_width = 0 });
        self.history_label.meta.ownership.meta.test_id = "ai.child.tasks.label";
        try self.history_toggle.appendChild(cx.allocator, self.history_arrow);
        try self.history_toggle.appendChild(cx.allocator, self.history_label);
        try props_scroll.content.appendChild(cx.allocator, self.history_toggle);
        self.task_summary = try ui.textStyled(cx, @import("../sessions/view/ai_children_styles.zig").detail, "");
        self.task_summary.setStyleInline(cx.allocator, .{ .width = .fill(), .flex_shrink = 0 });
        self.task_summary.meta.ownership.meta.test_id = "ai.child.tasks";
        self.task_summary.setDisplay(.none);
        try props_scroll.content.appendChild(cx.allocator, self.task_summary);
        const props_footer = try ui.boxStyled(cx, @import("../sessions/view/ai_children_styles.zig").settingsFooter, .{});
        const apply = try ui.widgets.Button(.{ .label = "保存", .variant = .primary, .size = .sm, .disabled = self.apply_disabled, .on_click = cx.on(ChildDialog, self, applyProperties) }).mount(scope, cx);
        apply.meta.ownership.meta.test_id = "ai.child.property.save";
        try props_footer.appendChild(cx.allocator, apply);
        try self.props.appendChild(cx.allocator, props_footer);
        const conversation = try ui.boxStyled(cx, @import("../pane/view/ai_assistant_styles.zig").conversation, .{});
        const scroll = try ui.widgets.ScrollArea(.{ .height = 276, .direction = .vertical, .scrollbars = .always }).mount(scope, cx);
        scroll.content.setStyleInline(cx.allocator, .{ .will_change_transform = false });
        scroll.container.setStyleInline(cx.allocator, .{ .width = .fill(), .height = .fill(), .flex = 1, .min_height = 0, .overflow_hidden = true, .composited_group = true });
        scroll.container.meta.ownership.meta.test_id = "ai.child.conversation.viewport";
        try scroll.content.appendChild(cx.allocator, conversation);
        try modal.body.appendChild(cx.allocator, scroll.container);
        self.restore_parent.setStyleInline(cx.allocator, .{ .margin = .{ .left = 14, .right = 14, .bottom = 8 }, .flex_shrink = 0 });
        try modal.body.appendChild(cx.allocator, self.restore_parent);
        host.conversation = conversation;
        host.conversation_viewport = scroll.container;
        host.card_box = modal.dialog;
        host.tail_follow = .{ .scroll = scroll };
        try mountAssistantConversation(host, scope, modal.body, scroll, conversation, prompt);
        if (host.images_view) |view| {
            if (parent.images_view) |source| view.app = source.app;
        }
        try self.takePresentation(state, record);
        if (service.bridgeFor(info.agent)) |bridge| {
            const backend: *AiHost = @ptrCast(@alignCast(bridge.context));
            backend.backend_owner = host;
            host.execution_host = backend;
        }
        try AiHost.PollHook.install(host, scope);
        try scope.onCleanup(ChildDialog, self, cleanup);
        host.controller.model.visible = true;
        host.controller.model.expanded = true;
        host.conversation_dirty = true;
        // The settings surface and the chevron are painted from the palette: repainted when the
        // window publishes a theme, not compared every frame.
        try scope.createEffect(.{ .dialog = self, .publication = try cx.themeSignal() }, struct {
            fn run(ctx: anytype) void {
                _ = ctx.publication.get();
                ctx.dialog.repaint();
            }
        }.run);
        const viewport_fit = try scope.createState(ViewportFit, .{ .dialog = self });
        try cx.addAfterLayoutHook(viewport_fit, ViewportFit.run);
        try scope.onCleanup(ViewportFit, viewport_fit, ViewportFit.cleanup);
        host.refresh("AI 助手");
        return self;
    }
    /// The dialog's size for a window of `width` × `height`: 600 × 456 (or the whole window when
    /// maximized), 16 pt inside the window's edges.
    pub fn dialogSize(width: f32, height: f32, maximized: bool) struct { width: f32, height: f32 } {
        return .{
            .width = @max(0, if (maximized) width - 32 else @min(600, width - 32)),
            .height = @max(0, if (maximized) height - 32 else @min(456, height - 32)),
        };
    }
    /// Sizes the dialog (through the Modal's sources) and the settings body for the current window.
    fn fit(self: *ChildDialog) void {
        const cx = self.host.cx;
        self.fitted_width = cx.viewport.width;
        self.fitted_height = cx.viewport.height;
        const size = dialogSize(self.fitted_width, self.fitted_height, self.maximized);
        self.dialog_width.set(size.width);
        self.dialog_height.set(size.height);
        self.dialog_max_height.set(size.height);
        self.props_scroll.setStyleInline(cx.allocator, @import("../sessions/view/ai_children_styles.zig").settingsBody(self.fitted_height));
    }
    /// Refits the dialog when the window has been resized (one comparison per layout pass, no walk).
    const ViewportFit = struct {
        dialog: *ChildDialog,
        fn run(raw: *anyopaque, _: u8, _: bool) ui.AfterLayoutResult {
            const self: *ViewportFit = @ptrCast(@alignCast(raw));
            const dialog = self.dialog;
            const viewport = dialog.host.cx.viewport;
            if (viewport.width == dialog.fitted_width and viewport.height == dialog.fitted_height) return .done;
            dialog.fit();
            return .needs_layout;
        }
        fn cleanup(self: *ViewportFit) void {
            self.dialog.host.cx.removeAfterLayoutHook(self);
        }
    };
    fn repaint(self: *ChildDialog) void {
        self.props_chrome.setStyleInline(self.host.cx.allocator, @import("../sessions/view/ai_children_styles.zig").settings(self.host.cx.tokens));
        _ = self.history_arrow.setTint(app_theme.current().fg_2);
        self.host.cx.requestRedraw();
    }
    /// Shows the child's projected state in the header: the status Tag's label and its color.
    pub fn showStatus(self: *ChildDialog, entry: child_projection.Entry) void {
        self.status_label.set(entry.status);
        self.status_color.set(statusColor(entry));
    }
    pub fn statusColor(entry: child_projection.Entry) ui.widgets.tag.TagColor {
        return if (entry.group == .attention) .warning else if (entry.running or entry.group == .active) .accent else if (std.mem.eql(u8, entry.status, "失败")) .danger else .success;
    }
    fn toggleMaximize(self: *ChildDialog) void {
        self.maximized = !self.maximized;
        self.fit();
        self.host.cx.requestRedraw();
    }
    fn restoreParent(self: *ChildDialog) void {
        const record = self.host.childRecord() orelse return;
        const parent = self.host.assistant_states.?.findConversation(record.child.?.info.owning_parent_conversation) orelse return;
        self.close();
        AiHost.conversationAction(self.parent, parent.id, .restore);
    }
    fn nameChanged(self: *ChildDialog, value: []const u8) void {
        self.name.set(value);
    }
    fn reusableChanged(self: *ChildDialog, value: bool) void {
        self.reusable.set(value);
    }
    fn toggleProps(self: *ChildDialog) void {
        self.props_open.set(!self.props_open.peek());
        if (self.props_open.peek()) self.updateTaskSummary() catch |err| self.host.setFeedback(@errorName(err));
    }
    fn toggleHistory(self: *ChildDialog) void {
        const expanded = !self.history_open.peek();
        self.history_open.set(expanded);
        self.task_summary.setDisplay(if (expanded) .flex else .none);
        self.history_arrow.setStyleInline(self.host.allocator, .{ .rotate = if (expanded) std.math.pi / 2.0 else 0 });
        self.host.cx.requestRedraw();
    }
    fn updateTaskSummary(self: *ChildDialog) !void {
        const shared = self.host.shared_service.?;
        const record = self.host.childRecord() orelse return error.ChildNotFound;
        const agent = record.child.?.info.agent;
        var facts: [32]@import("../../../ai/task_budget.zig").Fact = undefined;
        var count: usize = 0;
        for (shared.service.store.task_facts.items) |saved| if (saved.fact.agent.eql(agent) and count < facts.len) {
            facts[count] = saved.fact;
            count += 1;
        };
        for (shared.service.task_roots.items) |root| {
            root.lock();
            defer root.mutex.unlock();
            for (root.facts[0..root.count]) |fact| if (fact.agent.eql(agent)) {
                const index: ?usize = for (facts[0..count], 0..) |old, i| {
                    if (old.task.eql(fact.task)) break i;
                } else null;
                if (index) |i| facts[i] = fact else {
                    if (count == facts.len) {
                        std.mem.copyForwards(@import("../../../ai/task_budget.zig").Fact, facts[0..31], facts[1..32]);
                        count -= 1;
                    }
                    facts[count] = fact;
                    count += 1;
                }
            };
        }
        var buffer: [4096]u8 = undefined;
        var writer = std.Io.Writer.fixed(&buffer);
        if (record.child.?.info.context_source) |source| try writer.print("继承快照：第 {d} 回合，{d} 条消息\n", .{ source.turn, source.message_count });
        var label: [64]u8 = undefined;
        try self.history_label.setTextContent(self.host.allocator, try std.fmt.bufPrint(&label, "任务记录 · {d}", .{count}));
        if (count == 0) try writer.writeAll("暂无任务记录");
        for (facts[0..count], 1..) |fact, number| try writer.print("第 {d} 次 · {s} · 请求 {d} / 工具 {d}\n", .{ number, switch (fact.status) {
            .running => "运行中",
            .waiting_model => "等待模型",
            .waiting_children => "等待子任务",
            .human_wait => "等待用户",
            .settling => "收尾中",
            .succeeded => "已完成",
            .failed => "失败",
            .cancelled => "已停止",
            .outcome_unknown => "结果未知",
            .interrupted => "已中断",
        }, fact.counters.requests, fact.counters.calls });
        try self.task_summary.setTextContent(self.host.allocator, writer.buffered());
    }
    fn close(self: *ChildDialog) void {
        self.props_open.set(false);
        self.open.set(false);
        self.parent.cx.requestRedraw();
    }
    fn option(self: *ChildDialog, body: *ui.Node, prefix_label: []const u8, label: []const u8, kind: u8, index: usize, checked: bool) !void {
        const toggle = try self.scope.createState(Toggle, .{ .dialog = self, .kind = kind, .index = @intCast(index) });
        const signal = try self.scope.createSignal(bool, checked);
        const row = try ui.boxStyled(self.host.cx, @import("../sessions/view/ai_children_styles.zig").settingsRow, .{});
        const control = try ui.widgets.Switch(.{ .checked = signal, .on_change = self.host.cx.on(Toggle, toggle, Toggle.change) }).mount(self.scope, self.host.cx);
        control.meta.ownership.meta.test_id = try std.fmt.bufPrint(&toggle.test_id, "ai.child.property.{d}.{d}", .{ kind, index });
        var text: [512]u8 = undefined;
        const text_node = try ui.textStyled(self.host.cx, @import("../sessions/view/ai_children_styles.zig").settingLabel, try std.fmt.bufPrint(&text, "{s}：{s}", .{ prefix_label, label }));
        text_node.setStyleInline(self.host.allocator, .{ .width = .fill(), .flex = 1, .min_width = 0 });
        try row.appendChild(self.host.allocator, text_node);
        try row.appendChild(self.host.allocator, control);
        try body.appendChild(self.host.allocator, row);
    }
    const Toggle = struct {
        dialog: *ChildDialog,
        kind: u8,
        index: u5,
        test_id: [64]u8 = undefined,
        fn change(self: *Toggle, enabled: bool) void {
            const bits = switch (self.kind) {
                0 => &self.dialog.skill_bits,
                1 => &self.dialog.mcp_bits,
                else => &self.dialog.target_bits,
            };
            const mask = @as(u32, 1) << self.index;
            if (enabled) bits.* |= mask else bits.* &= ~mask;
        }
    };
    fn applyProperties(self: *ChildDialog) void {
        self.saveProperties() catch |err| self.host.setFeedback(@errorName(err));
    }
    fn saveProperties(self: *ChildDialog) !void {
        if (!self.host.childCanWrite()) return error.ParentBindingChanged;
        const record = self.host.childRecord() orelse return error.ChildNotFound;
        const life = @import("../../../ai/session_lifecycle.zig");
        var prefs = life.Store.childPreferences(record);
        var skills: [32][]const u8 = undefined;
        var skill_count: usize = 0;
        var mcps: [32][]const u8 = undefined;
        var mcp_count: usize = 0;
        var targets: [32]@import("../../../host/identity.zig").SessionHandle = undefined;
        var target_count: usize = 0;
        for (record.child.?.info.skill_ids, 0..) |key, i| if (self.skill_bits & (@as(u32, 1) << @intCast(i)) != 0) {
            skills[skill_count] = key;
            skill_count += 1;
        };
        for (record.child.?.info.mcp_ids, 0..) |key, i| if (self.mcp_bits & (@as(u32, 1) << @intCast(i)) != 0) {
            mcps[mcp_count] = key;
            mcp_count += 1;
        };
        for (self.target_handles[0..self.target_count], 0..) |handle, i| if (self.target_bits & (@as(u32, 1) << @intCast(i)) != 0) {
            targets[target_count] = handle;
            target_count += 1;
        };
        const current_targets = if (record.binding != null) self.host.shared_service.?.service.store.agent(record.child.?.info.agent).?.targets else prefs.targets;
        if (!@import("../../../config/settings_schema.zig").same(current_targets, targets[0..target_count]) and record.binding != null) {
            const runner = self.host.shared_service.?.service.runnerFor(record.child.?.info.agent) orelse return error.AgentNotFound;
            if (runner.thread != null or record.task_pending) return error.ChildScopeBusy;
            const fence = try self.host.shared_service.?.service.store.fence(record.id);
            const operation = if (record.ending) |ending| ending.operation else @import("../../../host/identity.zig").HostOperationId.generate();
            try self.host.shared_service.?.service.endConversation(fence, operation);
            if (record.binding != null) return error.ResourceCleanupPending;
        }
        prefs.name = self.name.peek();
        prefs.reusable = self.reusable.peek();
        prefs.skill_ids = skills[0..skill_count];
        prefs.mcp_ids = mcps[0..mcp_count];
        prefs.targets = targets[0..target_count];
        const shared = self.host.shared_service.?;
        const parent = try shared.service.store.fence(record.child.?.info.owning_parent_conversation);
        const owner = (try shared.service.store.validate(parent)).binding.?.owner;
        const allowed = try self.parent.captureOwnerScope(owner);
        defer if (allowed.inventory) |ids| self.parent.allocator.free(ids);
        try shared.service.store.updateChildSettings(parent, record.child.?.info.agent, self.revision, prefs, allowed);
        self.revision = record.child_settings_revision;
        self.props_open.set(false);
        try self.title.setTextContent(self.host.allocator, prefs.name);
        self.host.setFeedback("子配置已保存，作用于后续任务");
    }
    fn takePresentation(self: *ChildDialog, state: *@import("../../../ai/assistant_store.zig").State, record: *@import("../../../ai/session_lifecycle.zig").Record) !void {
        const host = self.host;
        host.tool_results.deinit();
        host.tool_results = state.tool_results orelse @import("../../../ai/tool_results.zig").Store.init(host.allocator);
        state.tool_results = null;
        host.history = state.history;
        state.history = .empty;
        host.wire_history = state.wire_history;
        state.wire_history = .{};
        host.current_turn = state.current_turn;
        state.current_turn = .{};
        host.controller.stream.deinit();
        host.controller.stream = state.stream;
        state.stream = @import("../../../ai/card_stream.zig").Stream.init(host.allocator);
        host.last_user_text = state.last_user_text;
        state.last_user_text = null;
        host.last_user_wire = state.last_user_wire;
        state.last_user_wire = null;
        host.last_user_attachments = state.last_user_attachments;
        state.last_user_attachments = null;
        host.last_user_images = state.last_user_images;
        state.last_user_images = null;
        if (host.wire_history.messages.len == 0 and record.history.messages.len != 0) host.wire_history = try @import("../../../ai/wire_history.zig").History.copy(host.allocator, record.history.messages, "");
        if (host.history.items.len == 0 and host.last_user_text == null) host.history = try @import("../../../ai/conversation_presentation.zig").restoreHistory(host.allocator, record.presentation, record.last_turn, record.history.messages);
        if (state.controls.model == null) try state.controls.setModel(host.allocator, @import("../../../ai/session_lifecycle.zig").Store.childPreferences(record).model);
        const prefs = @import("../../../ai/session_lifecycle.zig").Store.childPreferences(record);
        state.controls.effort = prefs.effort;
        state.controls.permission = prefs.permission;
        state.controls.thinking = prefs.thinking;
        state.controls.session_retention = prefs.session_retention;
        state.controls.execution_mode = prefs.execution_mode;
    }
    pub fn releaseView(self: *ChildDialog) !void {
        if (self.released) return;
        const host = self.host;
        try host.persistDisplayedDraft();
        try host.saveDisplayedPresentation();
        const state = host.assistant_states.?.find(host.display_conversation.?) orelse return error.ConversationNotFound;
        if (state.draft) |old| host.allocator.free(old);
        state.draft = try host.allocator.dupe(u8, host.prompt.peek());
        state.history = host.history;
        host.history = .empty;
        state.wire_history = host.wire_history;
        host.wire_history = .{};
        state.current_turn = host.current_turn;
        host.current_turn = .{};
        state.stream.deinit();
        state.stream = host.controller.stream;
        host.controller.stream = @import("../../../ai/card_stream.zig").Stream.init(host.allocator);
        if (state.tool_results) |*old| old.deinit();
        state.tool_results = host.tool_results;
        host.tool_results = @import("../../../ai/tool_results.zig").Store.init(host.allocator);
        state.last_user_text = host.last_user_text;
        host.last_user_text = null;
        state.last_user_wire = host.last_user_wire;
        host.last_user_wire = null;
        state.last_user_attachments = host.last_user_attachments;
        host.last_user_attachments = null;
        state.last_user_images = host.last_user_images;
        host.last_user_images = null;
        if (host.execution_host) |backend| {
            if (backend.backend_owner == host) backend.backend_owner = self.parent;
        }
        host.execution_host = null;
        self.released = true;
    }
    fn cleanup(self: *ChildDialog) void {
        self.releaseView() catch |err| self.parent.setFeedback(@errorName(err));
        if (self.parent.child_dialog == self) self.parent.child_dialog = null;
    }
};
