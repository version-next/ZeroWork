//! 进程窗口表 ProcessWindows（P2 自 src/main.zig 原样拆出）：多窗口运行时、待开窗口队列、退出流程与更新宿主。

const std = @import("std");
const applog = @import("../platform/applog.zig");
const application_test_mode = @import("application_options").test_mode;
const App = @import("zenit_app").App;
const MultiWindowApp = @import("zenit_app").MultiWindowApp;
const FontRegistry = @import("zenit_app").FontRegistry;
const ClearColor = @import("zenit_app").ClearColor;
const ws = @import("../features/workspace/mod.zig").ws;
const RuntimeConfig = @import("../config/runtime_config.zig").RuntimeConfig;
const DataPaths = @import("../config/paths.zig").Paths;
const shell_styles = @import("../features/shell/mod.zig").shell_styles;
const application_host_mod = @import("../features/shell/mod.zig").application_host_mod;
const process_state = @import("process_state.zig");
const AiHost = @import("../features/ai/mod.zig").AiHost;
const AppNavHost = @import("../features/shell/mod.zig").AppNavHost;
const SettingsHost = @import("../features/settings/mod.zig").SettingsHost;
const cleanupRuntimeConfig = @import("startup.zig").cleanupRuntimeConfig;
const installMonospaceFonts = @import("fonts.zig").installMonospaceFonts;
const mountUI = @import("main_window.zig").mountUI;
const window_ground = @import("window_ground.zig");
const verifyUiFontPaths = @import("fonts.zig").verifyUiFontPaths;

/// Main window: zenit window chrome with the platform's traffic lights (moved by
/// `setTrafficLightsLayout` into the sidebar header). The window drags where the shell marks
/// `window_region = .drag`: the view bar (`chrome_mount.mountTitleBar`) and the sidebar's title
/// band (`sidebar_view.zig`); the tab strip and the tool group are client regions.
pub const main_window: @import("zenit_app").WindowConfig = .{ .width = 1440, .height = 900, .min_width = 860, .min_height = 480, .title = "ZeroWork", .chrome = .{ .custom = .{} }, .titlebar_height = shell_styles.outer + shell_styles.title_height };

pub const ProcessWindows = struct {
    runtime: *MultiWindowApp,
    domain: *application_host_mod.Domain,
    io: std.Io,
    data_paths: *const DataPaths,
    data_cleanup_owner: ?*SettingsHost = null,
    data_cleanup_pending: bool = false,
    data_cleanup_exit: bool = false,
    primary: ?*App = null,
    updater: ?*@import("../features/update/mod.zig").app_host.Host(ProcessWindows) = null,
    runtime_config: ?*RuntimeConfig = null,
    font_system: ?@FieldType(App, "font_manager") = null,
    pending: std.ArrayList(PendingWindow) = .empty,
    update_test_legacy_preflight: bool = false,
    /// 上次同步到各窗口的主题地面色（`[.panel, .shell]` 两个角色，见
    /// window_ground.syncWindow；null = 尚未同步过）。
    grounds: ?[2]ClearColor = null,
    /// “立即重启”（设置 › 协议插件，Q5）：走与 ⌘Q 相同的退出流程，退出完成后由 `relaunch.zig` 再启动同一个应用。
    /// 任一窗口在关闭确认里被取消时清除（`cancelRelaunch`），之后的普通退出不再重启。
    relaunch_requested: bool = false,
    const PendingWindow = struct {
        source: @import("../host/session_host.zig").AttachmentTarget,
        connection: application_host_mod.WindowConnection,
    };

    /// Cmd+Q / application menu Quit (zenit `on_quit_request`). ZeroWork
    /// vetoes the immediate quit and closes each window through its own
    /// cleanup pipeline; the loop ends when the last window is closed.
    pub fn onQuitRequest(runtime: *MultiWindowApp) bool {
        _ = runtime;
        const process = process_state.process_windows orelse return true;
        process.requestQuit();
        return false;
    }

    /// “立即重启”：登记再启动，然后发起正常退出（同 ⌘Q：未保存内容、运行中的会话照常逐项确认，不强制结束任何进程）。
    pub fn requestRelaunch(self: *ProcessWindows) void {
        self.relaunch_requested = true;
        applog.info(.app, "relaunch requested; starting normal quit", .{});
        if (application_test_mode) std.debug.print("ZW_RELAUNCH {{\"requested\":true}}\n", .{});
        self.requestQuit();
    }
    /// 关闭确认被取消：撤销登记的再启动（开关保持“重启后生效”）。
    pub fn cancelRelaunch(self: *ProcessWindows) void {
        if (!self.relaunch_requested) return;
        self.relaunch_requested = false;
        applog.info(.app, "relaunch cancelled by the close confirmation", .{});
        if (application_test_mode) std.debug.print("ZW_RELAUNCH {{\"requested\":false}}\n", .{});
    }

    pub fn requestQuit(self: *ProcessWindows) void {
        for (self.runtime.windows.items) |managed| {
            // The preferences window closes through its owner's close pipeline
            // (unsaved-draft decision first).
            if (@import("../shared/ui/window/aux_window.zig").find(managed.app.windowId()) == &process_state.settings_window_slot) continue;
            const nav = navFor(managed.app) orelse {
                _ = self.runtime.closeWindow(managed.app.windowId());
                continue;
            };
            nav.beginApplicationClose();
        }
    }

    pub fn navFor(app: *App) ?*AppNavHost {
        const root = app.cx.root orelse return null;
        return @ptrCast(@alignCast(root.behavior.events.capture_context orelse return null));
    }

    pub fn queue(self: *ProcessWindows, source: *application_host_mod.ApplicationHost, host_id: ws.HostId) !void {
        try @import("../update/admission.zig").require();
        var connection = try source.freezeWindowConnection(host_id);
        errdefer connection.deinit();
        try self.pending.append(std.heap.c_allocator, .{ .source = .{ .window_id = source.window_id, .workspace_id = source.workspace_id }, .connection = connection });
    }

    pub fn queueTab(self: *ProcessWindows, source: *application_host_mod.ApplicationHost, id: ws.SessionId) !void {
        try @import("../update/admission.zig").require();
        var connection = try source.freezeTabWindowConnection(id);
        errdefer connection.deinit();
        try self.pending.append(std.heap.c_allocator, .{ .source = .{ .window_id = source.window_id, .workspace_id = source.workspace_id }, .connection = connection });
    }

    /// Execute between MultiWindowApp ticks: creating a native App while its
    /// windows array is being rendered would invalidate the runtime iterator.
    pub fn drain(self: *ProcessWindows, registry: *FontRegistry) void {
        while (self.pending.items.len != 0) {
            var pending = self.pending.orderedRemove(0);
            defer pending.connection.deinit();
            self.open(&pending.connection, registry) catch |err| {
                if (self.domain.ownerForTarget(pending.source)) |source| source.workspace.statusFailure(@errorName(err));
                applog.warn(.workspace, "new window: {s}", .{@errorName(err)});
            };
        }
    }

    /// Auxiliary native windows (connection editor, …) requested since the
    /// last tick; created here, outside the runtime's window iteration.
    pub fn drainAux(self: *ProcessWindows, registry: *FontRegistry) void {
        const aux = @import("../shared/ui/window/aux_window.zig");
        if (aux.runtime == null) aux.runtime = .{ .context = self, .activate = auxActivate, .close = auxClose, .destroyed = auxDestroyed };
        // 每个循环迭代都经过这里：检测主题切换，同步各窗口的 clear/layer 地面色。
        self.syncGrounds();
        while (aux.takePending()) |slot| {
            // clear 与首帧前 layer 背景共用同一个取样值（mount 前后不重复取样）。
            const ground = window_ground.clear(slot.spec.ground);
            aux.beginMount(slot);
            const created = self.runtime.createWindowWith(.{
                .io = self.io,
                .font = .{ .fallback_families = @import("../platform/ui_fonts.zig").families },
                .window = .{ .width = slot.spec.width, .height = slot.spec.height, .min_width = slot.spec.min_width, .min_height = slot.spec.min_height, .title = slot.spec.title, .chrome = slot.spec.chrome, .titlebar_height = slot.spec.titlebar_height, .maximizable = slot.spec.maximizable, .restorable = false, .owner = slot.owner, .placement = .center_on_owner },
                .clear_color = ground,
                .on_close_request = auxCloseRequest,
            }, aux.mount);
            aux.endMount();
            const app = created catch |err| {
                applog.warn(.workspace, "auxiliary window: {s}", .{@errorName(err)});
                slot.createFailed(err);
                continue;
            };
            app.win.setTrafficLightsLayout(slot.spec.traffic_light_x, slot.spec.traffic_light_y, slot.spec.traffic_light_diameter);
            installMonospaceFonts(app);
            app.setFontRegistry(registry);
            slot.opened(app.windowId());
            _ = self.runtime.activateWindow(app.windowId());
        }
    }

    /// 主题发布后把每个窗口的 clear color 与 layer 背景同步到当前主题的地面色
    /// （辅助窗口按各自 spec.ground，主窗口用 `.shell`）。窗口内容随后会被自己的
    /// 重绘覆盖；这里只为 live resize 暴露的未上帧条带与后续帧的 clear 保底。
    fn syncGrounds(self: *ProcessWindows) void {
        const aux_window = @import("../shared/ui/window/aux_window.zig");
        const next = [2]ClearColor{ window_ground.clear(.panel), window_ground.clear(.shell) };
        if (self.grounds) |applied| if (std.meta.eql(applied, next)) return;
        self.grounds = next;
        for (self.runtime.windows.items) |managed| {
            const ground = if (aux_window.find(managed.app.windowId())) |slot|
                next[@intFromEnum(slot.spec.ground)]
            else
                next[@intFromEnum(aux_window.Ground.shell)];
            window_ground.syncWindow(managed.app, ground);
        }
    }
    fn auxActivate(raw: *anyopaque, id: u64) bool {
        const self: *ProcessWindows = @ptrCast(@alignCast(raw));
        return self.runtime.activateWindow(id);
    }
    fn auxClose(raw: *anyopaque, id: u64) bool {
        const self: *ProcessWindows = @ptrCast(@alignCast(raw));
        return self.runtime.closeWindow(id);
    }
    /// An auxiliary window (connection editor, …) mounted its own App, which
    /// rebinds the test-mode automation harness to it; hand it back to the
    /// owning main window once the auxiliary window is gone (settings does the
    /// same in SettingsHost). Release builds: no-op.
    fn auxDestroyed(raw: *anyopaque, owner: ?u64) void {
        if (!application_test_mode) return;
        const self: *ProcessWindows = @ptrCast(@alignCast(raw));
        const id = owner orelse return;
        if (self.runtime.window(id)) |app| app.rebindTestHarness();
    }
    fn auxCloseRequest(app: *App) bool {
        return @import("../shared/ui/window/aux_window.zig").closeRequest(app.windowId());
    }

    fn open(self: *ProcessWindows, connection: *const application_host_mod.WindowConnection, registry: *FontRegistry) !void {
        const ground = window_ground.clear(.shell);
        const app = try self.runtime.createWindowWith(.{
            .io = self.io,
            .font = .{ .fallback_families = @import("../platform/ui_fonts.zig").families },
            .window = main_window,
            .clear_color = ground,
            .on_close_request = AppNavHost.nativeWindowCloseRequest,
        }, mountUI);
        // A mounted native window still belongs to this request if later
        // attachment/factory validation fails. Close it through its owner at
        // the next runtime boundary instead of leaving an orphan empty view.
        errdefer _ = self.runtime.closeWindow(app.windowId());
        app.win.setTrafficLightsLayout(shell_styles.traffic_light_x, shell_styles.traffic_light_y, shell_styles.traffic_light_diameter);
        installMonospaceFonts(app);
        app.setFontRegistry(registry);
        if (application_test_mode) try verifyUiFontPaths(app);
        const nav: *AppNavHost = @ptrCast(@alignCast(app.cx.root.?.behavior.events.capture_context orelse return error.MissingApplicationController));
        nav.app_runtime = app;
        try nav.loadEmptyLogo();
        if (nav.settings) |settings| settings.app_runtime = app;
        const plugin_window = @import("../features/shell/mod.zig").plugin_window_host.Host.mount(app, nav.application_host orelse return error.MissingApplicationController, process_state.process_notifications, if (nav.ai) |ai| ai.notification_window else null) catch |err| {
            applog.err(.app, "plugin window services initialization: {s}", .{@errorName(err)});
            return err;
        };
        if (nav.wizard) |wizard| {
            wizard.probe_host = plugin_window.probes.?;
            // The connection editor window is owned by (and closes with) this window.
            wizard.attachWindow(app.windowId());
        }
        if (nav.ai) |ai| ai.setContentApp(app);
        const host = nav.application_host orelse return error.MissingApplicationController;
        _ = host.createWindowConnection(connection) catch |err| {
            host.workspace.statusFailure(@errorName(err));
            return err;
        };
        _ = self.runtime.activateWindow(app.windowId());
        applog.info(.workspace, "workspace ready window={d} workspace={d} shared_sessions={d}", .{ @backingInt(host.window_id), @backingInt(host.workspace_id), self.domain.sessions.sessions.items.len });
    }

    pub fn updateDraftReason(self: *ProcessWindows, allow_unsaved: bool) ?[]const u8 {
        if (self.data_cleanup_owner != null) return "正在清除应用数据，请先完成该操作";
        if (self.pending.items.len != 0) return "有窗口正在创建，请稍后重试";
        for (self.runtime.windows.items) |managed| {
            const nav = navFor(managed.app) orelse continue;
            if (nav.native_close_pending) return "有窗口正在关闭，请等待收尾";
            if (nav.settings) |settings| {
                if (settings.busy()) return "请先完成设置资源操作";
                if (!allow_unsaved and settings.controller.state() != .clean) return "有未保存的设置，请返回工作区保存或放弃后再更新";
            }
            if (allow_unsaved) continue;
            if (nav.wizard) |wizard| if (wizard.open) |editor_open| if (editor_open.get()) return "连接编辑器尚未关闭，请先保存或放弃编辑";
            if (nav.quick_host) |quick| if (quick.view.isOpen()) return "请先关闭快捷连接输入，避免丢失未提交内容";
            if (nav.ai) |ai| {
                if (application_test_mode and self.update_test_legacy_preflight) {
                    if (legacyUpdateAiReason(ai)) |reason| return reason;
                }
                // Inspect the live composer, not retained controller/model copies.
                if (ai.assistant_states) |store| {
                    if (ai.display_conversation) |id| if (store.find(id)) |current| {
                        if (!current.closed and !current.ended and std.mem.trim(u8, ai.prompt.peek(), " \t\r\n").len != 0) return "当前 AI 会话有未发送的输入";
                    };
                    for (store.states.items) |state| {
                        if (@import("../update/draft_guard.zig").blocks(state, ai.display_conversation)) return "其他 AI 会话有未发送的输入";
                    }
                }
            }
        }
        return null;
    }
    // Test-only observation/replay of the pre-fix AI guard. Never changes draft data.
    fn legacyUpdateAiReason(ai: *AiHost) ?[]const u8 {
        if (ai.controller.input.len != 0 or ai.controller.model.prompt.len != 0) return "有未发送的 AI 输入，请返回工作区发送或清空后再更新";
        if (ai.assistant_states) |store| for (store.states.items) |state| if (state.draft) |draft| if (std.mem.trim(u8, draft, " \t\r\n").len != 0) return "其他 AI 会话有未发送的输入，请先保存或清空后再更新";
        return null;
    }
    pub fn updateTestLegacyPreflight(self: *ProcessWindows, enabled: bool) void {
        if (application_test_mode) self.update_test_legacy_preflight = enabled;
    }
    pub fn updateTestDrafts(self: *ProcessWindows, buffer: []u8) ?[]const u8 {
        if (!application_test_mode) return null;
        var output = std.Io.Writer.fixed(buffer);
        output.writeAll("{\"windows\":[") catch return null;
        var first = true;
        for (self.runtime.windows.items) |managed| {
            const nav = navFor(managed.app) orelse continue;
            const ai = nav.ai orelse continue;
            const Entry = struct {
                id: u64,
                closed: bool,
                ended: bool,
                listed: bool,
                selected: bool,
                draft_len: usize,
                draft_hash: u64,
                model_prompt_len: usize,
                journal_present: bool,
                journal_draft_len: usize,
                journal_draft_hash: u64,
                bound: bool,
            };
            var states: std.ArrayList(Entry) = .empty;
            defer states.deinit(std.heap.c_allocator);
            if (ai.assistant_states) |store| for (store.states.items) |state| {
                const record = if (ai.shared_service) |host| host.service.store.find(state.conversation_id) else null;
                const draft = state.draft orelse "";
                const persisted = if (record) |r| r.draft orelse "" else "";
                states.append(std.heap.c_allocator, .{ .id = state.id, .closed = state.closed, .ended = state.ended, .listed = state.listed, .selected = state.selected, .draft_len = draft.len, .draft_hash = std.hash.Wyhash.hash(0, draft), .model_prompt_len = state.model.prompt.len, .journal_present = record != null, .journal_draft_len = persisted.len, .journal_draft_hash = std.hash.Wyhash.hash(0, persisted), .bound = if (record) |r| r.binding != null else false }) catch return null;
            };
            if (!first) output.writeAll(",") catch return null;
            first = false;
            std.json.Stringify.value(.{ .window = @backingInt(nav.application_host.?.window_id), .display = ai.display_conversation, .prompt_len = ai.prompt.peek().len, .prompt_hash = std.hash.Wyhash.hash(0, ai.prompt.peek()), .controller_input_len = ai.controller.input.len, .controller_model_prompt_len = ai.controller.model.prompt.len, .legacy_reason = legacyUpdateAiReason(ai), .states = states.items }, .{}, &output) catch return null;
        }
        output.writeAll("]}") catch return null;
        return output.buffered();
    }
    pub fn updateTestTheme(self: *ProcessWindows, id: []const u8) !void {
        const app = self.primary orelse return error.NoWindow;
        const nav = navFor(app) orelse return error.NoWindow;
        try AppNavHost.selectGlobalTheme(nav, id);
        for (self.runtime.windows.items) |managed| if (navFor(managed.app)) |current| try current.refreshAppearance();
    }
    /// The menu bar's 显示 › 外观…: Settings › 外观与主题 › 主题 in the key window (else the primary one).
    pub fn openAppearance(self: *ProcessWindows) void {
        var target = self.primary;
        for (self.runtime.windows.items) |managed| if (managed.app.cx.window_active) {
            target = managed.app;
            break;
        };
        const app = target orelse return;
        const nav = navFor(app) orelse return;
        AppNavHost.showThemeFromMenu(nav);
        app.cx.requestRedraw();
    }
    pub fn updateRevision(self: *ProcessWindows) u64 {
        var hash = std.hash.Wyhash.init(0);
        std.hash.autoHash(&hash, self.pending.items.len);
        for (self.domain.sessions.sessions.items) |entry| std.hash.autoHash(&hash, .{ entry.handle, entry.state, entry.create_operation });
        for (self.domain.attachments.items) |host| std.hash.autoHash(&hash, .{ host.window_id, host.workspace.model.order_revision });
        return hash.final();
    }
    pub fn updateSnapshot(self: *ProcessWindows) ![:0]u8 {
        var out = std.Io.Writer.Allocating.init(std.heap.c_allocator);
        defer out.deinit();
        const writer = &out.writer;
        try writer.writeAll("{\"schema\":1,\"phase\":\"before-close\",\"replay_tasks\":false,\"windows\":[");
        var first = true;
        for (self.runtime.windows.items) |managed| {
            const nav = navFor(managed.app) orelse continue;
            const workspace = nav.workspace orelse continue;
            if (!first) try writer.writeByte(',');
            first = false;
            try writer.print("{{\"window\":{d},\"workspace\":{d},\"tabs\":[", .{ @backingInt(nav.application_host.?.window_id), @backingInt(nav.application_host.?.workspace_id) });
            for (workspace.tabs.items, 0..) |tab, index| {
                if (index != 0) try writer.writeByte(',');
                try std.json.Stringify.value(.{ .session = tab.id, .tab = @backingInt(tab.tab_id), .asset = tab.host_id, .local = tab.local, .title = tab.title[0..tab.title_len], .generation = tab.generation }, .{}, writer);
            }
            try writer.writeAll("],\"groups\":[");
            for (nav.roster.groups.items, 0..) |group, index| {
                if (index != 0) try writer.writeByte(',');
                try std.json.Stringify.value(.{ .id = group.id, .name = group.name, .color = group.color, .members = group.members.items, .pinned = group.pinned_pane }, .{}, writer);
            }
            try writer.writeAll("],\"views\":[");
            for (workspace.group_views.items, 0..) |view, index| {
                if (index != 0) try writer.writeByte(',');
                try std.json.Stringify.value(.{ .id = view.id, .layout = view.layout, .root = view.tree.root, .nodes = view.tree.nodes.items, .focused = view.focused }, .{}, writer);
            }
            try writer.writeAll("],\"active\":");
            try std.json.Stringify.value(if (workspace.model.active) |id| @as(?u64, @backingInt(id)) else null, .{}, writer);
            try writer.writeByte('}');
        }
        try writer.writeAll("]}");
        return std.heap.c_allocator.dupeSentinel(u8, out.written(), 0);
    }
    pub fn updateCancelJob(self: *ProcessWindows, id: u64) !void {
        const tasks = self.domain.tasks orelse return error.UnknownJob;
        const progress = tasks.manager.progress(id) orelse return error.UnknownJob;
        if (tasks.manager.retainedOwner(id)) |owner| {
            if (progress.state == .cancelled and progress.job_cleanup == .released) return;
            try tasks.retained_store.cancel(id, progress.attempt);
            try tasks.manager.retainedCancelReceipt(id, progress.attempt, owner, .awaiting);
        } else if (progress.state != .succeeded and progress.state != .failed and progress.state != .cancelled) try tasks.manager.cancel(id);
    }
    pub fn updateJobReceipt(self: *ProcessWindows, id: u64) @import("../update/close_coordinator.zig").Receipt {
        const tasks = self.domain.tasks orelse return .unknown;
        const progress = tasks.manager.progress(id) orelse return .unknown;
        if (progress.job_cleanup == .unknown) return .unknown;
        if ((progress.state == .succeeded or progress.state == .failed or progress.state == .cancelled) and progress.job_cleanup == .released) return .released;
        return .awaiting;
    }
    pub fn updateCancelAux(self: *ProcessWindows, id: @import("../host/identity.zig").WindowId) void {
        if (self.domain.ai) |ai| _ = ai.closeWindow(id) catch false;
        const host = self.domain.ownerForWindow(id) orelse return;
        for (self.runtime.windows.items) |managed| {
            const nav = navFor(managed.app) orelse continue;
            if (nav.application_host != host) continue;
            if (host.window_auxiliary) |aux| aux.cancel(aux.context);
            if (nav.wizard_host) |wizard| wizard.probe_controller.cancelAll();
            if (nav.ai) |ai| {
                ai.cancelRef().cancel();
                ai.model_discovery.cancelRequest();
                ai.conversation_titles.cancel();
                for (ai.attachment_readers.items) |reader| reader.cancel();
                for (ai.image_readers.items) |reader| reader.cancel();
                if (ai.transcript_images) |store| store.cancel();
            }
        }
    }
    pub fn updateAuxReceipt(self: *ProcessWindows, id: @import("../host/identity.zig").WindowId) @import("../update/close_coordinator.zig").Receipt {
        if (self.domain.ai) |ai| if (!ai.windowReady(id)) return .awaiting;
        const host = self.domain.ownerForWindow(id) orelse return .released;
        if (host.window_auxiliary) |aux| if (!aux.released(aux.context)) return .awaiting;
        for (self.runtime.windows.items) |managed| {
            const nav = navFor(managed.app) orelse continue;
            if (nav.application_host != host) continue;
            if (nav.wizard_host) |wizard| if (wizard.probe_controller.jobs.items.len != 0) return .awaiting;
            if (nav.ai) |ai| if (ai.execution().thread_state.load(.acquire) != 0 or ai.model_discovery.busy() or ai.conversation_titles.jobs.items.len != 0 or ai.attachment_readers.items.len != 0 or ai.image_readers.items.len != 0 or (if (ai.transcript_images) |store| store.busy() else false)) return .awaiting;
        }
        return .released;
    }
    pub fn updateFinalReceipt(self: *ProcessWindows) @import("../update/close_coordinator.zig").Receipt {
        if (self.domain.ai) |ai| if (!(ai.shutdown() catch return .unknown)) return .awaiting;
        for (self.domain.sessions.sessions.items) |entry| if (entry.state != .closed) return .awaiting;
        if (self.domain.tasks) |tasks| {
            for (0..tasks.manager.count()) |index| if (tasks.manager.progressAt(index)) |p| if (self.updateJobReceipt(p.job) != .released) return .awaiting;
            for (tasks.auxiliary_connections.items) |c| if (!c.released) return .awaiting;
            for (tasks.shared_connections.items) |c| if (!c.released) return .awaiting;
            for (tasks.retained_connections.items) |c| if (!c.released) return .awaiting;
        }
        return .released;
    }

    /// AppKit menu actions originate outside the Zenit node tree. Apply the
    /// selection while dispatching that native event, before tick renders it.
    pub fn menuBarAction(raw: *anyopaque, action: u64) callconv(.c) void {
        const self: *ProcessWindows = @ptrCast(@alignCast(raw));
        if (action >= 3) if (process_state.process_notifications) |notifications| {
            _ = notifications.activateActivity(action);
        };
        for (self.runtime.windows.items) |*managed| {
            managed.app.cx.requestRedraw();
            managed.force_frame = true;
        }
    }

    pub fn deinit(self: *ProcessWindows) void {
        for (self.pending.items) |*pending| pending.connection.deinit();
        self.pending.deinit(std.heap.c_allocator);
        if (self.runtime_config) |runtime| cleanupRuntimeConfig(runtime);
        if (self.font_system) |*fonts| fonts.deinit();
    }
};
