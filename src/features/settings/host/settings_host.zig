//! 偏好设置宿主 SettingsHost 及其点击辅助（SettingsNavClick、SettingsEditCell 等）（P2 自 src/main.zig 原样拆出）。

const std = @import("std");
const applog = @import("../../../platform/applog.zig");
const error_text = @import("../../../shared/base/error_text.zig");
const application_test_mode = @import("application_options").test_mode;
const ui = @import("ui");
const App = @import("zenit_app").App;
const ws = @import("../../workspace/view/workspace.zig");
const RuntimeConfig = @import("../../../config/runtime_config.zig").RuntimeConfig;
const SettingsController = @import("../model/settings_controller.zig").Controller;
const window_frame = @import("../view/window_frame.zig");
const design = @import("../../../shared/ui/theme/design.zig");
const app_theme = @import("../../../shared/ui/theme/app_theme.zig");
const shell_styles = @import("../../shell/view/shell_styles.zig");
const application_host_mod = @import("../../shell/host/application_host.zig");
const process_state = @import("../../../app/process_state.zig");
const AppNavHost = @import("../../shell/host/nav_host.zig").AppNavHost;
const ProcessWindows = @import("../../../app/process_windows.zig").ProcessWindows;
const applyCommandInfoSettings = @import("../../terminal/host/typography.zig").applyCommandInfoSettings;

pub const SettingsHost = struct {
    const RecordCleanup = @import("../../../host/record_cleanup.zig");
    const RecordCleanupView = @import("../../history/view/record_cleanup_view.zig");
    const CleanupOrigin = struct { draft_id: u64, page: usize, scroll: f32 };
    const ThemeRegistry = @import("../../../config/theme_registry.zig").Registry;
    const AppearanceWorker = @import("appearance_ui_worker.zig").Worker;
    const AppearanceContext = @import("../view/appearance_ui_context.zig").Context;
    const AppearanceCommand = @import("../view/appearance_ui_context.zig").Command;
    const FontResolved = @import("../../../config/appearance_font.zig").Resolved;
    const AppearanceApply = @import("../../../config/appearance_apply.zig");
    const BackgroundTexture = @import("../../shell/model/background_texture.zig").Texture;
    /// 宿主读值的键（数据页路径、更新器状态）。
    const ValueKey = struct { section: []const u8, key: []const u8 };
    /// 数据清理对话框里的选择（`Effect.data_cleanup`）。
    const CleanupChoice = enum { confirm, retry, dismiss };
    notification_window: ?@import("../../../host/notification_host.zig").WindowId = null,
    application_host: ?*application_host_mod.ApplicationHost = null,
    allocator: std.mem.Allocator,
    cx: *ui.Cx,
    scope: *ui.Scope,
    controller: SettingsController,
    /// F-set-ai：`.yix` 的 AI 面板交给宿主的后台任务（获取模型清单、测试模型、技能 / MCP 任务；`Effect.ai`）。首次使用时建。
    ai_jobs: ?AiJobs = null,
    runtime: *RuntimeConfig,
    io: std.Io,
    panel: *ui.Node,
    /// 设置窗口的内容列（`settings.island`，窗口挂着时）；否则是主窗口的占位节点。
    content: *ui.Node = undefined,
    open: bool = false,
    card: ?*ui.Node = null,
    pending_rebuild: bool = false,
    workspace: ?*ws.Workspace = null,
    mounted_page: ?window_frame.Page = null,
    /// 设置窗口与宿主的接口（宿主给视图的外观上下文，见 `view/window_frame.zig`）。
    yix_frame: window_frame.Frame = undefined,
    /// A content epoch was requested; `settleYixContent` runs in the next hook round.
    yix_settling: bool = false,
    mounted_page_index: usize = 0,
    /// 当前内容页挂载时的位置与搜索词（哈希）；都没变时，草稿 / 主题变化不重挂（P3 3e）。
    mounted_location: @import("../model/settings_history.zig").Location = .{ .page = 0 },
    mounted_query: u64 = 0,
    /// `.yix`：关于与更新页上次投影的更新器状态指纹（`pollUpdateStatus`）；变了才 `vm.sync()`（旧面板是每帧的 after-layout 钩子）。
    update_fingerprint: u64 = 0,
    focus_return: ?*ui.Node = null,
    native_close_waiter: ?*bool = null,
    record_cleanup: ?RecordCleanup.Controller = null,
    record_cleanup_dir: ?std.Io.Dir = null,
    record_cleanup_view: ?*RecordCleanupView.View = null,
    record_cleanup_origin: ?CleanupOrigin = null,
    data_cleanup_origin: ?CleanupOrigin = null,
    registry: ThemeRegistry = undefined,
    appearance_state: AppearanceApply.State = undefined,
    appearance_context: AppearanceContext = undefined,
    resource_worker: ?AppearanceWorker = null,
    resource_dir: ?std.Io.Dir = null,
    appearance_initialized: bool = false,
    font_result: ?FontResolved = null,
    font_problem: ?anyerror = null,
    installation: ?@import("../../../config/theme_registry.zig").Installation = null,
    pending_save: ?bool = null,
    pending_discard_close: bool = false,
    loading_saved_background: bool = false,
    background_rotation: @import("../../../config/background_rotation.zig").Rotation = .{},
    app_runtime: ?*App = null,
    draft_texture: ?BackgroundTexture = null,
    pending_texture: ?BackgroundTexture = null,
    committed_texture: ?BackgroundTexture = null,
    preview_scope: ?*ui.Scope = null,
    preview_root: ?*ui.Node = null,
    /// `.yix` 材质预览条的状态文字（“42.0% · 12px”），条随每次重建重挂。
    preview_status: [64]u8 = undefined,
    preview_viewport: ?*ui.Node = null,
    /// Renderer publication is installed by the application host. It shares
    /// this State/Registry with the instantaneous status theme transaction.
    on_appearance_publish: ?*const fn (*SettingsHost) void = null,
    on_material_preview: ?*const fn (*SettingsHost, bool) void = null,
    /// The native preferences window while this host owns it. `cx`/`scope`
    /// then belong to that window; otherwise they are the owning main
    /// window's, and the page fields point at hidden placeholders.
    windowed: bool = false,
    native_closing: bool = false,
    main_cx: *ui.Cx = undefined,
    main_scope: *ui.Scope = undefined,
    placeholder_panel: *ui.Node = undefined,
    /// 宿主状态行的最后一条文字（两份交替，换地址以便投影判出变化）；`Ports.status` → `ViewModel.statusLine`。
    status_lines: [2][256]u8 = undefined,
    status_line: []const u8 = "",
    /// Settings view-model (P3 3b): its core lives as long as this host, its
    /// projection signals are attached to the preferences window's scope.
    /// Created on first use (`viewModel`).
    view_model: ?SettingsViewModel = null,

    const AiJobs = @import("ai_settings_host.zig").AiJobs;
    const settings_pages_mod = @import("../../../config/settings_pages.zig");
    const settings_values_mod = @import("../model/settings_values.zig");
    const SettingsViewModel = view_model_mod.ViewModel;
    const view_model_mod = @import("../model/view_model.zig");

    /// The single entry for settings intents (the window template, the
    /// category list, the search field, the decision modal, deferred saves).
    pub fn viewModel(self: *SettingsHost) *SettingsViewModel {
        if (self.view_model == null) self.view_model = SettingsViewModel.init(&self.controller, .{ .context = self, .run = runEffect, .allow = allowGate, .status = hostStatus, .appearance = appearanceStatus });
        return &self.view_model.?;
    }
    fn dispatch(self: *SettingsHost, intent: view_model_mod.Intent) void {
        self.viewModel().dispatch(intent);
    }

    /// `Ports.allow`: host-held state that may refuse an intent.
    fn allowGate(raw: *anyopaque, gate: view_model_mod.Gate) bool {
        const self: *SettingsHost = @ptrCast(@alignCast(raw));
        const extensions_blocked = self.aiExtensionsBusy();
        switch (gate) {
            .search => return !extensions_blocked,
            .reset => return !self.busy(),
            // 确认弹窗与快捷键录制归 view-model（`ViewModel.windowKey` 自己拦截）；宿主没有别的状态要拦。
            .window_keys => return true,
            .navigate, .save => {
                if (self.busy()) return false;
                if (extensions_blocked) {
                    self.refresh("请先完成扩展操作，并应用或取消 MCP 编辑。");
                    return false;
                }
                if (gate == .navigate) return true;
                // F-set-ai：模型编辑器 / 删除确认打开时不保存。
                if (self.view_model) |*vm| if (vm.ai.modalOpen()) return false;
                return true;
            },
        }
    }

    /// `Ports.status`: host-held state the window shows (Save Bar, data page, notifications, updates).
    fn hostStatus(raw: *anyopaque) view_model_mod.HostStatus {
        const self: *SettingsHost = @ptrCast(@alignCast(raw));
        const appearance = self.appearance_initialized;
        return .{
            .appearance_busy = appearance and self.busy(),
            .font_problem = appearance and fontStatus(self).problem != null,
            .authorization_feedback = notificationAuthorizationFeedback(self),
            .authorization_help = notificationAuthorizationHelp(self),
            .clear_logs = contentActionState(self, .clear_logs),
            .clear_all = contentActionState(self, .clear_all),
            .data_paths = .{ dataPath(self, "config_path"), dataPath(self, "hosts_path"), dataPath(self, "cache_dir"), dataPath(self, "logs_dir") },
            .update = updateStatusOf(self),
            .status_line = self.status_line,
            .ai = if (self.ai_jobs) |*jobs| jobs.status() else .{},
        };
    }

    // ── F-set-ai：AI 面板的宿主侧（`Effect.ai`、`HostStatus.ai`；任务在 `ai_settings_host.zig`） ──

    fn aiJobs(self: *SettingsHost) *AiJobs {
        if (self.ai_jobs == null) self.ai_jobs = AiJobs.init(self.allocator);
        return &self.ai_jobs.?;
    }
    /// 扩展任务进行中，或 MCP 编辑表单开着。
    fn aiExtensionsBusy(self: *SettingsHost) bool {
        if (self.ai_jobs) |*jobs| if (jobs.extensionBusy()) return true;
        if (self.view_model) |*vm| if (vm.ai.mcp.editing) return true;
        return false;
    }
    /// 每帧收尾 AI 面板的后台任务：有结果就重新投影；仍在进行就继续排帧（旧视图在 after-layout 钩子里 33ms 轮询）。
    fn pollAi(self: *SettingsHost) void {
        const jobs = if (self.ai_jobs) |*value| value else return;
        if (jobs.poll(&self.controller)) if (self.view_model) |*vm| {
            if (self.controller.validationProblem() == null) if (process_state.process_notifications) |notifications| if (self.notification_window) |window| notifications.resolveOperationErrors(window, "偏好设置");
            vm.sync();
            self.cx.requestRedraw();
        };
        if (jobs.busy()) self.cx.scheduleRedrawAfterNs(33 * std.time.ns_per_ms);
    }

    /// 关于与更新页的更新器状态（P3 3e 第二批，`HostStatus.update`）：同旧面板读的 `Hooks.read(.{ .section = "updates" })` 各键。
    fn updateStatusOf(self: *SettingsHost) view_model_mod.UpdateStatus {
        const text = struct {
            fn of(host: *SettingsHost, key: []const u8) []const u8 {
                const value = readContentValue(host, .{ .section = "updates", .key = key }) orelse return "";
                return if (value == .text) value.text else "";
            }
        }.of;
        return .{
            .state = text(self, "state"),
            .current_version = text(self, "current_version"),
            .metadata = text(self, "version_metadata"),
            .badge = text(self, "version_badge"),
            .title = text(self, "available_title"),
            .available_version = text(self, "available_version"),
            .last_check = text(self, "last_check"),
            .channel = text(self, "release_channel"),
        };
    }
    /// `.yix`：关于与更新页挂着（或搜索结果里有它）时每帧比较更新器状态的指纹，变了才重新投影
    /// （旧面板每帧在 after-layout 钩子里重写文字节点；这里只在状态真的变化时 `sync`）。
    fn pollUpdateStatus(self: *SettingsHost) void {
        if (!self.windowed or self.mounted_page == null) return;
        const vm = if (self.view_model) |*value| value else return;
        if (self.controller.model.page_index != 8 and vm.contentMode() != .search) return;
        const status = updateStatusOf(self);
        var hasher = std.hash.Wyhash.init(0);
        for ([_][]const u8{ status.state, status.current_version, status.metadata, status.badge, status.title, status.available_version, status.last_check, status.channel }) |part| {
            hasher.update(part);
            hasher.update(&.{0});
        }
        const fingerprint = hasher.final();
        if (fingerprint == self.update_fingerprint) return;
        self.update_fingerprint = fingerprint;
        vm.sync();
    }

    /// `Ports.run`: carry out what the view-model asked for.
    fn runEffect(raw: *anyopaque, effect: view_model_mod.Effect) void {
        const self: *SettingsHost = @ptrCast(@alignCast(raw));
        switch (effect) {
            // 滚动位置是 view-model 的信号（视口自己回报，S-5），离开页面时宿主没有要存的。
            .leave_page => {},
            .navigated => {
                self.pending_rebuild = true;
                self.writeStatusLine(null);
                self.cx.requestRedraw();
            },
            .rebuild => {
                self.pending_rebuild = true;
                self.cx.requestRedraw();
            },
            .failed => |err| self.fail(err, "设置操作未完成"),
            .resolve_problems => if (process_state.process_notifications) |notifications| if (self.notification_window) |window| notifications.resolveOperationErrors(window, "偏好设置"),
            .report_problem => self.notifyProblem(""),
            // 跳到 AI 草稿里的问题：view-model 自己导航并打开对应的提供方 / 模型编辑器（`ai_pane.locateProblem`）。
            .focus_problem => {},
            .request_notification_authorization => if (process_state.process_notifications) |notifications| if (self.notification_window) |window| {
                notifications.requestAuthorization(window) catch |err| {
                    self.fail(err, "无法请求系统通知授权");
                    return;
                };
                self.refresh("正在等待系统通知授权结果…");
            },
            .save => |request| self.runSave(request.close_after),
            .revert => self.revertDraft(),
            // 确认对话框归 view-model：窗口按 `ViewModel.prompt` 信号显示原生 `W.Modal`，宿主不画（H-save）。
            .prompt => {},
            .dismiss_decision => self.cancelDecision(),
            // Toast 由 view-model 的 `toast` 信号驱动窗口模板里的 `W.NotificationHost`（S-19），宿主不持有 Notifier。
            .saved, .save_failed => {},
            .discard_and_close => self.discardAndClose(),
            .close_window => self.closeNow(),
            .escape => self.windowEscape(),
            .request_close => self.toggle(),
            .import_theme => self.importTheme() catch |err| self.failWith(error_text.theme(err), err, "导入主题失败"),
            .export_logs => self.exportLogs() catch |err| self.fail(err, "导出诊断日志失败"),
            .clear_logs => self.clearLogs() catch |err| self.fail(err, "清除日志失败"),
            .clear_all => self.showDataCleanup() catch |err| self.fail(err, "无法打开数据清除"),
            .data_cleanup => |choice| switch (choice) {
                .none => {},
                .confirm => self.dataCleanupChoice(.confirm),
                .retry => self.dataCleanupChoice(.retry),
                .dismiss => self.dataCleanupChoice(.dismiss),
            },
            .open_config_dir => self.openConfigDirectory() catch |err| self.fail(err, "无法打开配置目录"),
            .explain_credentials => self.refresh("凭据由 macOS 钥匙串保管；访问权限在实际读取或保存时由系统确认。"),
            .check_updates => @import("../../../update/client.zig").zw_update_open(),
            .open_update_release => @import("../../../update/client.zig").zw_update_command(6),
            // “立即重启”（Q5）：与 ⌘Q 相同的退出流程，退出完成后再启动（`app/relaunch.zig`）。
            .restart_app => if (process_state.process_windows) |process| process.requestRelaunch(),
            .pick_directory => |key| chooseSettingsDirectory(self, &self.controller, .{ .section = key.section, .key = key.key }),
            .appearance => |request| self.appearanceEffect(request),
            .ai => |job| {
                self.aiJobs().run(&self.controller, self.dataDirectory(), job);
                self.cx.requestRedraw();
            },
            .open_notification_permission => {
                self.openNotificationPermission() catch |err| self.refresh(switch (err) {
                    error.AuthorizationRequestPending => "正在等待系统通知授权结果…",
                    error.NotificationUnavailable => "当前无法使用系统通知，请从 ZeroWork.app 启动。",
                    error.OpenNotificationSettingsFailed => "无法打开系统设置，请前往「系统设置 → 通知 → ZeroWork」允许通知。",
                    else => "系统通知授权请求失败，请重试。",
                });
                self.pending_rebuild = true;
                self.cx.requestRedraw();
            },
        }
    }

    /// `Ports.appearance`（P3 3e 外观包）：外观页要显示的宿主状态（旧 `appearance_ui_context.Context` 的只读部分）。
    fn appearanceStatus(raw: *anyopaque) view_model_mod.AppearanceStatus {
        const self: *SettingsHost = @ptrCast(@alignCast(raw));
        if (!self.appearance_initialized) return .{};
        const font = fontStatus(self);
        return .{
            .ready = true,
            .busy = self.busy(),
            .registry = &self.registry,
            .saved_theme = self.runtime.value.ui.theme,
            .saved_background = self.runtime.value.ui.materials.background,
            .font_family_id = font.family_id,
            .font_actual = font.actual_family,
            .font_fallback = font.fallback,
            .font_problem = font.problem,
            .font_cell_width = if (self.font_result) |resolved| resolved.cell_width else 0,
            .selected_image_path = self.appearance_context.selected_image_path,
            .runtime_image_path = self.appearance_context.runtime_image_path,
            .preview_active = self.appearance_context.preview_active,
            .thumbnail = self.thumbnailTexture(),
        };
    }
    /// 背景缩略图用哪张纹理（同旧 `mountAppearanceImage`：草稿就是已保存的那张时用已提交的纹理，否则用草稿纹理）。
    fn thumbnailTexture(self: *SettingsHost) ?view_model_mod.Texture {
        const draft = self.controller.background.last_good;
        const saved = self.appearance_state.asset;
        const use_saved = !self.appearance_context.preview_active and draft != null and saved != null and draft.?.asset_revision == saved.?.asset_revision and draft.?.matches(self.runtime.value.ui.materials.background);
        const texture = (if (use_saved) self.committed_texture else self.draft_texture orelse self.committed_texture) orelse return null;
        return .{ .id = texture.id, .width = texture.width, .height = texture.height };
    }
    /// `Effect.appearance`（P3 3e 外观包）：面板要宿主做的外观操作，转给旧 `appearanceCommand` 的同一套处理。
    fn appearanceEffect(self: *SettingsHost, request: view_model_mod.AppearanceEffect) void {
        if (!self.appearance_initialized) return;
        switch (request) {
            .changed => appearanceCommand(self, .draft_values_changed),
            .validate_font => appearanceCommand(self, .validate_font),
            .pick_background => appearanceCommand(self, .{ .pick_background = .{ .draft_id = self.controller.draft_id, .asset_revision = self.controller.background.asset_revision } }),
            .remove_theme => |id| appearanceCommand(self, .{ .remove_theme = .{ .id = id, .registry_revision = self.registry.revision } }),
            .preview_material => |active| appearanceCommand(self, .{ .preview_material = active }),
            .restore_materials => appearanceCommand(self, .restore_materials),
        }
        if (self.view_model) |*vm| vm.sync();
    }

    pub fn initAppearance(self: *SettingsHost) !void {
        self.registry = try ThemeRegistry.init(self.allocator);
        errdefer self.registry.deinit();
        const directory = try std.Io.Dir.cwd().openDir(self.io, self.dataDirectory(), .{});
        errdefer directory.close(self.io);
        self.resource_worker = try AppearanceWorker.init(self.allocator, self.io, directory);
        errdefer self.resource_worker.?.deinit();
        self.resource_dir = directory;
        self.appearance_state = .{ .allocator = self.allocator };
        self.appearance_context = .{ .registry = &self.registry, .runtime = self.runtime, .context = self, .request = appearanceCommand, .busy = appearanceBusy, .font_status = fontStatus, .mount_image = mountAppearanceImage, .mount_material_preview = mountAppearanceMaterial };
        self.resource_worker.?.background_preflight = .{ .context = self, .prepare = prepareDraftTexture, .complete = completeDraftTexture };
        try self.resource_worker.?.loadLibrary(&self.registry);
        self.appearance_initialized = true;
    }

    /// Includes the shared registry lease and deferred Save/Discard. Native
    /// close waits on this same gate instead of invalidating a worker's owner.
    pub fn busy(self: *const SettingsHost) bool {
        return self.controller.state() == .saving or self.pending_save != null or self.pending_discard_close or if (self.resource_worker) |*worker| worker.busy() else false;
    }
    fn appearanceBusy(raw: *anyopaque) bool {
        const self: *SettingsHost = @ptrCast(@alignCast(raw));
        return self.busy();
    }
    fn fontStatus(raw: *anyopaque) @import("../view/appearance_ui_context.zig").FontStatus {
        const self: *SettingsHost = @ptrCast(@alignCast(raw));
        return .{ .family_id = if (self.font_result) |font| font.family_id else 0, .actual_family = if (self.font_result) |font| font.actual_family else "", .fallback = if (self.font_result) |font| font.fallback_reason != null else false, .problem = if (self.font_problem) |problem| @import("../../../config/appearance_font.zig").problemMessage(problem) else null };
    }
    fn validateFont(self: *SettingsHost) void {
        const registry = process_state.app_font_registry orelse {
            self.font_problem = error.FontUnavailable;
            return;
        };
        const setting = self.controller.model.value.ui;
        if (self.font_problem == null) if (self.font_result) |font| {
            if (std.mem.eql(u8, font.requested_family, setting.font_family) and font.requested_size == @as(f32, @floatFromInt(setting.font_size)) and font.requested_weight == @import("../../../config/font_weight.zig").parse(setting.font_weight)) return;
        };
        const resolved = @import("../../../config/appearance_font.zig").resolve(self.allocator, registry, .{ .family = setting.font_family, .size = @floatFromInt(setting.font_size), .weight = setting.font_weight }) catch |err| {
            self.font_problem = err;
            self.refreshFooter();
            return;
        };
        if (self.font_result) |*previous| previous.deinit(self.allocator);
        self.font_result = resolved;
        self.font_problem = null;
        self.refreshFooter();
    }
    fn appearanceCommand(raw: *anyopaque, command: AppearanceCommand) void {
        const self: *SettingsHost = @ptrCast(@alignCast(raw));
        const worker = if (self.resource_worker) |*value| value else return;
        const dispatched = @import("appearance_ui_picker.zig").dispatch(self.cx, worker, &self.controller, &self.registry, self.runtime.value.ui.theme, command) catch |err| {
            self.controller.theme_library.problem = err;
            self.failWith(error_text.theme(err), err, "外观操作未完成");
            self.pending_rebuild = true;
            return;
        };
        if (dispatched) {
            // An explicit re-selection of the saved source refreshes its
            // resources even when the configuration identity is unchanged.
            if (command == .pick_background and worker.busy()) self.loading_saved_background = std.mem.eql(u8, worker.selectedPath(), self.runtime.value.ui.materials.background.path);
            self.appearance_context.selected_image_path = worker.selectedPath();
            self.pending_rebuild = true;
        } else switch (command) {
            .validate_font => self.validateFont(),
            .draft_values_changed => {
                self.validateFont();
                self.loadCurrentBackground();
                if (self.controller.model.value.ui.materials.background.path.len == 0) {
                    worker.clearSelectedPath();
                    self.appearance_context.selected_image_path = "";
                }
                if (self.on_material_preview) |update| update(self, self.appearance_context.preview_active);
                // TextInput and IME remain mounted during ordinary edits.
                self.refreshFooter();
            },
            .preview_material => |active| self.setMaterialPreview(active),
            .restore_materials => {
                if (self.busy()) return;
                self.controller.restoreMaterials(self.runtime) catch |err| {
                    self.fail(err, "无法恢复材质设置");
                    return;
                };
                if (self.draft_texture) |*texture| texture.deinit();
                self.draft_texture = null;
                worker.clearSelectedPath();
                self.appearance_context.selected_image_path = "";
                self.loadCurrentBackground();
                self.pending_rebuild = true;
                if (self.on_material_preview) |update| update(self, self.appearance_context.preview_active);
            },
            else => {},
        }
        self.cx.requestRedraw();
    }
    fn loadCurrentBackground(self: *SettingsHost) void {
        const worker = if (self.resource_worker) |*value| value else return;
        const selected = self.controller.model.value.ui.materials.background;
        if (!selected.enabled or selected.path.len == 0 or worker.busy()) return;
        if (self.controller.background.canSave(selected)) return;
        // Opening/reverting settings must preserve the live directory cursor.
        // The committed pixels and playlist are already validated and uploaded.
        if (self.appearance_state.asset) |*current| if (current.matches(selected)) {
            var copy = current.clone(self.allocator) catch |err| {
                self.fail(err, "背景图片加载失败");
                return;
            };
            const request = self.controller.background.select(selected.path) catch |err| {
                copy.deinit(self.allocator);
                self.fail(err, "背景图片加载失败");
                return;
            };
            copy.draft_id = request.draft_id;
            copy.asset_revision = request.asset_revision;
            _ = self.controller.completeBackground(&copy) catch |err| {
                self.fail(err, "背景图片加载失败");
                return;
            };
            return;
        };
        var request = self.controller.requestBackground(selected.path) catch |err| {
            self.fail(err, "背景图片加载失败");
            return;
        };
        self.loading_saved_background = selected.source == self.runtime.value.ui.materials.background.source and std.mem.eql(u8, selected.path, self.runtime.value.ui.materials.background.path);
        request.request.resume_progress = self.loading_saved_background;
        worker.startBackground(&request) catch |err| {
            self.loading_saved_background = false;
            _ = self.controller.failBackground(request.request, err);
            request.deinit();
            self.fail(err, "背景图片加载失败");
        };
    }
    /// Called by the application's safe hook even while the settings panel is
    /// hidden. It never destroys a node from inside its own input callback.
    pub fn poll(self: *SettingsHost) bool {
        self.pollBackgroundRotation();
        self.pollRecordCleanup();
        if (self.view_model) |*vm| if (vm.cleanupConfirming()) vm.dispatch(view_model_mod.Intent.cleanupEvent(.{ .blocked = self.dataCleanupBlocked() }));
        const worker = if (self.resource_worker) |*value| value else return false;
        if (!worker.busy()) return false;
        const result = worker.poll(&self.controller, &self.registry, self.runtime.value.ui.theme);
        self.appearance_context.selected_image_path = worker.selectedPath();
        if (result.pending) {
            self.cx.requestRedraw();
            return false;
        }
        if (result.problem) |problem| {
            self.controller.theme_library.problem = if (result.kind == .background) self.controller.theme_library.problem else problem;
            self.failWith(error_text.theme(problem), problem, "外观资源处理失败");
        }
        if (result.kind == .load_library) {
            self.validateFont();
            if (self.registry.get(self.runtime.value.ui.theme)) |current| {
                app_theme.selectTokens(current.ui_tokens);
                app_theme.publishSchemes(self.cx);
                self.cx.setTheme(app_theme.widgetTheme(app_theme.currentName()));
            }
            self.loadCurrentBackground();
            if (self.on_appearance_publish) |publish| publish(self);
        }
        if (result.kind == .background and self.loading_saved_background) {
            self.loading_saved_background = false;
            if (result.problem == null and result.changed) if (self.controller.background.last_good) |good| {
                if (good.matches(self.runtime.value.ui.materials.background)) {
                    self.runtime.confirmLoadedBackground(&good) catch |err| {
                        self.fail(err, "背景图片加载失败");
                        return true;
                    };
                    const saved_asset = self.copyAsset(good) catch |err| {
                        self.fail(err, "背景图片加载失败");
                        self.pending_rebuild = true;
                        return true;
                    };
                    if (self.appearance_state.asset) |*old| old.deinit(self.allocator);
                    self.appearance_state.asset = saved_asset;
                    self.updateBackgroundIdentity();
                    if (self.committed_texture) |*old| old.deinit();
                    self.committed_texture = self.draft_texture;
                    self.draft_texture = null;
                    self.background_rotation.deadline_ms = null;
                    if (self.on_appearance_publish) |publish| publish(self);
                }
            };
        }
        if (result.kind == .installation) self.installation = worker.takeInstallation();
        if (result.kind == .abort_installation) {
            if (worker.takeInstallation()) |receipt| {
                self.installation = receipt;
                self.pending_discard_close = false;
            } else if (self.pending_discard_close) {
                self.pending_discard_close = false;
                self.discardAndClose();
            }
        }
        if (self.pending_save) |close_after_save| {
            self.pending_save = null;
            if (result.problem == null) self.saveWithClose(close_after_save);
        }
        if (result.changed or result.problem != null) {
            self.pending_rebuild = true;
            if (self.on_material_preview) |update| update(self, self.appearance_context.preview_active);
        }
        self.refreshFooter();
        self.cx.requestRedraw();
        return result.changed;
    }
    fn persistBackgroundProgress(self: *SettingsHost) void {
        const directory = self.resource_dir orelse return;
        const progress = @import("../../../config/background_progress.zig");
        const background = self.runtime.value.ui.materials.background;
        if (background.source != .directory or background.path.len == 0) {
            directory.deleteFile(self.io, progress.filename) catch |err| switch (err) {
                error.FileNotFound => {},
                else => std.log.warn("Cannot clear background progress: {s}", .{@errorName(err)}),
            };
            return;
        }
        const current = if (self.appearance_state.asset) |*value| value else return;
        if (!current.matches(background)) return;
        const list = if (current.playlist) |*value| value else return;
        list.changeOrder(background.order == .random);
        progress.save(self.io, directory, self.allocator, current.path, list) catch |err| {
            std.log.warn("Cannot save background progress: {s}", .{@errorName(err)});
        };
    }
    pub fn updateBackgroundIdentity(self: *SettingsHost) void {
        self.persistBackgroundProgress();
        self.appearance_context.runtime_image_path = if (self.appearance_state.asset) |*current| current.selectedPath() else "";
    }
    fn pollBackgroundRotation(self: *SettingsHost) void {
        const background = self.runtime.value.ui.materials.background;
        const now: u64 = @intCast(std.Io.Clock.real.now(self.io).toMilliseconds());
        const key = @import("../../../config/background_rotation.zig").Rotation.identity(background, self.runtime.value.config_revision);
        const active = background.enabled and background.source == .directory and if (self.appearance_state.asset) |*current| current.matches(background) and if (current.playlist) |list| list.paths.items.len > 1 else false else false;
        const rotation = &self.background_rotation;
        rotation.sync(key, now, background.interval_minutes, active);
        // Keep draft previews stable; a completed job can wait without touching
        // either draft resources or the settings transaction's textures.
        if (!self.busy() and !self.appearance_context.preview_active) {
            if (rotation.take()) |job| {
                defer job.destroy();
                if (job.key == key and active) {
                    if (job.result) |*prepared| {
                        const texture = @import("../../shell/model/background_texture.zig").upload(self.app_runtime orelse return, prepared) catch |err| {
                            rotation.reset(now, background.interval_minutes);
                            self.fail(err, "背景轮换失败");
                            return;
                        };
                        if (self.appearance_state.asset) |*old| old.deinit(self.allocator);
                        self.appearance_state.asset = prepared.*;
                        job.result = null;
                        if (self.committed_texture) |*old| old.deinit();
                        self.committed_texture = texture;
                        self.appearance_state.material_revision +%= 1;
                        self.updateBackgroundIdentity();
                        if (self.open) self.pending_rebuild = true;
                        if (self.on_appearance_publish) |publish| publish(self);
                        self.cx.requestRedraw();
                    } else if (job.problem) |problem| self.fail(problem, "背景轮换失败");
                    rotation.reset(now, background.interval_minutes);
                }
            }
            if (active and rotation.due(now)) {
                rotation.start(self.allocator, self.io, self.resource_dir.?, &self.appearance_state.asset.?, background.order == .random) catch |err| {
                    rotation.reset(now, background.interval_minutes);
                    self.fail(err, "背景轮换失败");
                };
            }
        }
        if (rotation.job != null and !rotation.ready()) {
            self.cx.scheduleRedrawAfterNs(33 * std.time.ns_per_ms);
        } else if (active and !rotation.due(now)) {
            const delay = rotation.deadline_ms.? -| now;
            self.cx.scheduleRedrawAfterNs(@max(1, delay) * std.time.ns_per_ms);
        }
    }
    fn prepareDraftTexture(raw: *anyopaque, prepared: *const @import("../../../config/background_asset.zig").Prepared) !void {
        const self: *SettingsHost = @ptrCast(@alignCast(raw));
        const app = self.app_runtime orelse return error.RendererNotReady;
        if (self.pending_texture) |*old| old.deinit();
        self.pending_texture = null;
        self.pending_texture = try @import("../../shell/model/background_texture.zig").upload(app, prepared);
    }
    fn completeDraftTexture(raw: *anyopaque, accepted: bool) void {
        const self: *SettingsHost = @ptrCast(@alignCast(raw));
        if (accepted) {
            if (self.draft_texture) |*old| old.deinit();
            self.draft_texture = self.pending_texture;
        } else if (self.pending_texture) |*failed| failed.deinit();
        self.pending_texture = null;
    }
    fn mountAppearanceImage(raw: *anyopaque, cx: *ui.Cx, _: *ui.Scope, width: f32, height: f32) !*ui.Node {
        const self: *SettingsHost = @ptrCast(@alignCast(raw));
        const draft = self.controller.background.last_good;
        const saved = self.appearance_state.asset;
        const use_saved = !self.appearance_context.preview_active and draft != null and saved != null and draft.?.asset_revision == saved.?.asset_revision and draft.?.matches(self.runtime.value.ui.materials.background);
        const texture = (if (use_saved) self.committed_texture else self.draft_texture orelse self.committed_texture) orelse return ui.iconTint(cx, ui.icons.image, app_theme.current().fg_3, .{ .width = .{ .px = width }, .height = .{ .px = height } });
        const frame = try ui.box(cx, .{ .width = .{ .px = width }, .height = .{ .px = height }, .overflow = .hidden, .overflow_hidden = true, .border = .{ .radius = 5 }, .flex_shrink = 0 }, .{});
        const scale = @max(width / @as(f32, @floatFromInt(texture.width)), height / @as(f32, @floatFromInt(texture.height)));
        const image_width = @as(f32, @floatFromInt(texture.width)) * scale;
        const image_height = @as(f32, @floatFromInt(texture.height)) * scale;
        const image = try ui.image(cx, texture.id, .{ .position = .absolute, .width = .{ .px = image_width }, .height = .{ .px = image_height } });
        image.setStyleInline(cx.allocator, .{ .inset = .{ .left = .{ .px = (width - image_width) / 2 }, .top = .{ .px = (height - image_height) / 2 } } });
        try frame.appendChild(cx.allocator, image);
        return frame;
    }
    const MaterialPreviewHook = struct {
        host: *SettingsHost,
        cx: *ui.Cx,
        frame: *ui.Node,
        view: *@import("../../shell/view/background_layers.zig").View,
        fn run(raw: *anyopaque, _: u8, _: bool) ui.AfterLayoutResult {
            const self: *@This() = @ptrCast(@alignCast(raw));
            const rect = self.frame.globalRect();
            if (rect.w <= 0 or rect.h <= 0) return .done;
            const texture = self.host.draft_texture orelse self.host.committed_texture;
            const image: ?@import("../../shell/view/background_layers.zig").Image = if (texture) |value| .{ .id = value.id, .width = value.width, .height = value.height, .repeating = value.repeating } else null;
            self.view.update(image, self.host.controller.model.value.ui.materials, rect.w, rect.h) catch {};
            return .done;
        }
        fn cleanup(self: *@This()) void {
            self.cx.removeAfterLayoutHook(self);
            self.cx.allocator.destroy(self);
        }
    };
    fn mountAppearanceMaterial(raw: *anyopaque, cx: *ui.Cx, scope: *ui.Scope, width: f32, height: f32) !*ui.Node {
        const self: *SettingsHost = @ptrCast(@alignCast(raw));
        const frame = try ui.box(cx, .{ .width = if (width > 0) .{ .px = width } else .fill(), .height = .{ .px = height }, .min_width = 0, .overflow = .hidden, .overflow_hidden = true, .composited_group = true, .background = app_theme.baseColors().app, .border = .{ .radius = 8 }, .flex_shrink = 0 }, .{});
        frame.meta.ownership.meta.test_id = "settings.background.material.surface";
        const view = try @import("../../shell/view/background_layers.zig").View.mount(cx, scope);
        view.root.meta.ownership.meta.test_id = "settings.background.material.layer";
        try frame.appendChild(cx.allocator, view.root);
        const hook = try cx.allocator.create(MaterialPreviewHook);
        hook.* = .{ .host = self, .cx = cx, .frame = frame, .view = view };
        try scope.onCleanup(MaterialPreviewHook, hook, MaterialPreviewHook.cleanup);
        try cx.addAfterLayoutHook(hook, MaterialPreviewHook.run);
        return frame;
    }
    /// 主窗口 OverlayHost 的窗口级层：材质预览盖在主窗口上时，主窗口的 Esc 结束预览。
    pub fn materialPreviewOpen(raw: *anyopaque) bool {
        const self: *SettingsHost = @ptrCast(@alignCast(raw));
        return self.open and self.appearance_context.preview_active;
    }
    pub fn endMaterialPreview(raw: *anyopaque) void {
        const self: *SettingsHost = @ptrCast(@alignCast(raw));
        self.setMaterialPreview(false);
    }

    pub fn setMaterialPreview(self: *SettingsHost, active: bool) void {
        if (active and self.busy()) return;
        if (!active) self.mounted_page = null;
        self.appearance_context.preview_active = active;
        // The preview is shown in the owning main window; bring that window
        // forward while previewing and return to preferences afterwards.
        if (process_state.process_windows) |process| {
            const target = if (active) (if (self.app_runtime) |app| app.windowId() else null) else process_state.settings_window_slot.window_id;
            if (target) |id| _ = process.runtime.activateWindow(id);
        }
        self.pending_rebuild = true;
        self.main_cx.requestRedraw();
        if (self.preview_root) |root| root.setDisplay(if (active) .flex else .none);
        if (self.on_material_preview) |update| update(self, active);
        self.cx.requestRedraw();
    }

    /// 操作失败：用户看到的文案只查 `shared/base/error_text.zig`，目录里没有时用本处的通用说法
    /// （接“详情见应用日志”）；原始错误名只写进应用日志（GLOSSARY §5）。
    fn fail(self: *SettingsHost, err: anyerror, comptime fallback: []const u8) void {
        self.failWith(error_text.describe(err), err, fallback);
    }
    /// 同 `fail`，按领域目录（如 `error_text.theme`）查。
    fn failWith(self: *SettingsHost, found: ?error_text.Text, err: anyerror, comptime fallback: []const u8) void {
        applog.warn(.ui, "settings: {s}: {s}", .{ fallback, @errorName(err) });
        self.refresh(error_text.lineFrom(found, fallback ++ error_text.log_suffix));
    }

    pub fn refresh(self: *SettingsHost, prefix: []const u8) void {
        if (self.controller.validationProblem() != null or self.controller.state() == .save_failed) {
            self.notifyProblem(prefix);
            self.refreshFooter();
            self.cx.requestRedraw();
            return;
        }
        var buffer: [256]u8 = undefined;
        var writer = std.Io.Writer.fixed(&buffer);
        writer.print("{s}{s}", .{ prefix, if (self.controller.model.dirty) " · 未保存" else "" }) catch return;
        self.writeStatusLine(writer.buffered());
        self.refreshFooter();
        if (prefix.len > 0 and !std.mem.startsWith(u8, prefix, "已") and !std.mem.startsWith(u8, prefix, "正在")) self.notifyProblem(prefix);
        self.cx.requestRedraw();
    }

    /// Footer state may have changed outside a dispatch (worker results,
    /// provider drafts, font checks): re-project, then repaint the Save Bar.
    /// 宿主状态行：记下最后一条文字并保持隐藏（现有写入点没有一处显示它，`HostStatus.status_line_shown`
    /// 恒为 false）。窗口经 `Ports.status` 投影成 `ViewModel.statusLine`，宿主不碰节点。
    fn writeStatusLine(self: *SettingsHost, text: ?[]const u8) void {
        if (text) |value| {
            const slot = &self.status_lines[if (@intFromPtr(self.status_line.ptr) == @intFromPtr(&self.status_lines[0])) 1 else 0];
            const n = @min(value.len, slot.len);
            @memcpy(slot[0..n], value[0..n]);
            self.status_line = slot[0..n];
        }
        if (text != null) if (self.view_model) |*vm| vm.sync();
    }
    fn refreshFooter(self: *SettingsHost) void {
        if (self.view_model) |*vm| vm.sync();
    }
    fn notifyProblem(self: *SettingsHost, fallback: []const u8) void {
        const notifications = process_state.process_notifications orelse return;
        const window = self.notification_window orelse return;
        var buffer: [2048]u8 = undefined;
        const invalid = self.controller.validationProblem() != null;
        const message = if (invalid) self.controller.validationMessage(&buffer) else @import("../../../shared/base/feedback_message.zig").message(fallback, &buffer);
        notifications.publishOperationError(window, null, "偏好设置", if (invalid) "无法保存设置" else "设置操作失败", message, if (invalid) .settings_problem else null) catch |err| applog.warn(.ui, "settings failure notification: {s}", .{@errorName(err)});
        self.cx.requestRedraw();
    }

    pub fn toggle(self: *SettingsHost) void {
        if (self.busy()) return;
        if (self.open) {
            switch (self.controller.requestClose()) {
                .blocked_saving => return,
                .confirmation_required => {
                    // H-save：确认对话框归 view-model（窗口模板里的原生 `W.Modal`）。
                    self.viewModel().askClose();
                    return;
                },
                .allow => self.closeNow(),
            }
        } else {
            // One preferences window per process: another window's host keeps
            // its draft; this request only brings that window forward.
            if (process_state.settings_window_slot.active() and process_state.settings_window_owner != self) {
                self.show();
                return;
            }
            self.controller.discardLatest(self.runtime) catch |err| {
                self.fail(err, "无法打开偏好设置");
                return;
            };
            // Island B v3: every pane opens expanded; folding stays per session.
            self.controller.folded_sections = 0;
            self.controller.ai_fields.provider_open.clearRetainingCapacity();
            self.controller.ai_fields.connection_open.clearRetainingCapacity();
            self.controller.ai_fields.model_open.clearRetainingCapacity();
            self.controller.ai_fields.existing_open = false;
            // Reopen where the window was left (category or subpage); history starts over.
            const reopen: @import("../model/settings_history.zig").Location = if (self.controller.search_return_page) |page| .{ .page = @intCast(page), .sub = self.controller.search_return_subpage } else self.controller.location();
            // 宿主发起的恢复位置（H-save：不按“离开作用域”确认；这里草稿刚基于最新配置重建，本来也是干净的）。
            self.viewModel().restoreLocation(reopen);
            self.controller.history.reset(self.controller.location());
            self.open = true;
            self.validateFont();
            self.loadCurrentBackground();
            self.cx.dispatcher.cancelScrollGesture();
            self.writeStatusLine(null);
            self.pending_rebuild = true;
            self.requestWindow();
        }
        self.cx.requestRedraw();
    }

    /// Open the preferences window, or bring the existing one forward.
    pub fn show(self: *SettingsHost) void {
        if (process_state.settings_window_slot.active()) {
            self.presentWindow();
            return;
        }
        if (!self.open) self.toggle() else self.requestWindow();
    }

    /// Queue the native window (created by ProcessWindows.drainAux between
    /// runtime ticks, never while a window is rendering), or raise it.
    fn requestWindow(self: *SettingsHost) void {
        if (process_state.settings_window_slot.active()) {
            self.presentWindow();
            return;
        }
        process_state.settings_window_owner = self;
        process_state.settings_window_slot.client = .{ .context = self, .mount = mountWindow, .close_request = windowCloseRequest, .destroyed = windowDestroyed, .failed = windowFailedCallback };
        process_state.settings_window_slot.owner = if (self.app_runtime) |app| app.windowId() else null;
        _ = process_state.settings_window_slot.present();
        self.main_cx.requestRedraw();
    }

    fn presentWindow(_: *SettingsHost) void {
        _ = process_state.settings_window_slot.present();
        if (application_test_mode) if (process_state.settings_window_slot.window_id) |id| if (process_state.process_windows) |process| if (process.runtime.window(id)) |app| app.rebindTestHarness();
    }

    fn windowFailedCallback(raw: *anyopaque, err: anyerror) void {
        const self: *SettingsHost = @ptrCast(@alignCast(raw));
        if (process_state.settings_window_owner == self) process_state.settings_window_owner = null;
        self.open = false;
        self.fail(err, "无法打开偏好设置窗口");
    }

    /// Auxiliary-window client mount: build the preferences window UI and
    /// point this host's page fields at it.
    fn mountWindow(raw: *anyopaque, cx: *ui.Cx, scope: *ui.Scope) anyerror!*ui.Node {
        const self: *SettingsHost = @ptrCast(@alignCast(raw));
        // 浮层与输入框的窗口级规则（OverlayHost）：输入框 Esc 回到聚焦时的值。
        @import("../../../shared/ui/overlay/overlay_host.zig").install(cx);
        const publication = try cx.bindState(shell_styles.ThemePublication, .{});
        publication.publish(cx, app_theme.widgetTheme(app_theme.currentName()));
        return self.mountYixWindow(cx, scope, publication);
    }

    /// Forget every node and scope owned by the preferences window and fall
    /// back to the main window's placeholders. `close_native` asks the runtime
    /// to retire the window at its next safe boundary.
    fn detachWindow(self: *SettingsHost, close_native: bool) void {
        if (process_state.settings_window_owner == self and !self.windowed and close_native) {
            // Requested but not mounted yet: drop the queued creation.
            process_state.settings_window_slot.close();
            process_state.settings_window_owner = null;
            return;
        }
        if (!self.windowed) return;
        self.windowed = false;
        if (self.view_model) |*vm| vm.detach();
        if (process_state.settings_window_owner == self) process_state.settings_window_owner = null;
        self.mounted_page = null;
        self.yix_settling = false;
        // F-set-ai：关窗取消 AI 面板的后台任务、收起它的对话框。
        if (self.ai_jobs) |*jobs| jobs.stop();
        if (self.view_model) |*vm| vm.ai = .{};
        self.record_cleanup_view = null;
        if (self.view_model) |*vm| vm.dismissCleanup();
        self.card = null;
        self.panel = self.placeholder_panel;
        self.content = self.placeholder_panel;
        self.cx = self.main_cx;
        self.scope = self.main_scope;
        if (close_native and !self.native_closing) process_state.settings_window_slot.close();
        // Automation follows focus back to the owning main window.
        if (application_test_mode) if (self.app_runtime) |owner| owner.rebindTestHarness();
        self.main_cx.requestRedraw();
    }

    /// Native close button / ⌘W: the same draft semantics as Escape and the
    /// Save Bar. Returns true only once the draft allowed closing.
    fn windowCloseRequest(raw: *anyopaque) bool {
        const self: *SettingsHost = @ptrCast(@alignCast(raw));
        self.native_closing = true;
        defer self.native_closing = false;
        if (self.open) self.toggle() else self.detachWindow(true);
        return !self.open;
    }

    /// The window's Cx/scope is going away for any reason (owner close, quit).
    fn windowDestroyed(raw: *anyopaque) void {
        const self: *SettingsHost = @ptrCast(@alignCast(raw));
        self.native_closing = true;
        defer self.native_closing = false;
        self.detachWindow(false);
        if (process_state.settings_window_owner == self) process_state.settings_window_owner = null;
        // The draft stays in the controller; reopening starts from it.
        self.open = false;
    }

    /// `Effect.escape`：按层收起，最上层先走；都没有时按关闭处理。
    fn windowEscape(self: *SettingsHost) void {
        if (self.appearance_context.preview_active) return self.setMaterialPreview(false);
        // 面板：提示 / 下拉 / 正在编辑的输入框（P3 3e，`ViewModel.consumeEscape`）。
        // 改过的输入框在这之前已由原生 Input 回到聚焦时的值（OverlayHost：`Cx.input_escape`），
        // 走到这里的 Esc 只让正在编辑的输入框失焦；输入法组字中不接。
        if (self.view_model) |*vm| {
            const focused = self.cx.focus_manager.getFocused();
            const composing = if (focused) |node| if (ui.widgets.input.editStateOf(node)) |state| switch (state) {
                .input => |input| input.imeIsComposing(),
                .textarea => |textarea| textarea.imeIsComposing(),
            } else false else false;
            if (!composing and vm.consumeEscape(if (focused) |node| self.cx.focus_targets.targetName(self.cx, node) else null)) return;
        }
        self.toggle();
    }

    /// Per-window frame work: follow the process palette, drain the
    /// appearance worker and rebuild pages inside the preferences window.
    const WindowHook = struct {
        host: *SettingsHost,
        cx: *ui.Cx,
        publication: *shell_styles.ThemePublication,
        fn run(raw: *anyopaque, _: u8, _: bool) ui.AfterLayoutResult {
            const self: *WindowHook = @ptrCast(@alignCast(raw));
            // The owner may already be gone (main window closed); never touch it then.
            if (process_state.settings_window_owner != self.host) return .done;
            const host = self.host;
            if (host.cx != self.cx) return .done;
            const tokens = app_theme.widgetTheme(app_theme.currentName());
            if (!std.meta.eql(self.publication.snapshots[self.publication.slot], tokens.*)) {
                self.publication.publish(self.cx, tokens);
                host.pending_rebuild = true;
            }
            _ = host.poll();
            host.pollUpdateStatus();
            host.pollAi();
            if (host.yix_settling) {
                host.settleYixContent();
                return .needs_layout;
            }
            if (host.open and host.pending_rebuild) {
                host.pending_rebuild = false;
                host.rebuildAll();
                return .needs_layout;
            }
            return .done;
        }
        fn cleanup(self: *WindowHook) void {
            self.cx.removeAfterLayoutHook(self);
            // A runtime-initiated teardown (quit, update) must not leave the
            // host pointing into this window.
            if (process_state.settings_window_owner == self.host and self.host.cx == self.cx) self.host.detachWindow(false);
        }
    };

    fn closeNow(self: *SettingsHost) void {
        if (self.installation != null) {
            self.discardAndClose();
            return;
        }
        if (self.appearance_initialized) {
            self.registry.discard(self.controller.draft_id);
            self.appearance_context.preview_active = false;
            if (self.preview_root) |root| root.setDisplay(.none);
            if (self.on_material_preview) |update| update(self, false);
        }
        self.open = false;
        if (self.record_cleanup_view) |view| view.hide();
        self.record_cleanup_origin = null;
        if (self.view_model) |*vm| vm.dismissPrompt();
        // Retire the preferences window; focus returns to this main window.
        self.detachWindow(true);
        if (self.workspace) |workspace| {
            if (workspace.active_tab) |active| {
                if (active < workspace.tabs.items.len) {
                    self.cx.setFocus((if (workspace.tabs.items[active].terminal) |*terminal| terminal.root else workspace.tabs.items[active].root));
                    self.cx.requestRedraw();
                    return;
                }
            }
        }
        if (self.focus_return) |trigger| self.cx.setFocus(trigger);
        self.cx.requestRedraw();
    }

    // Save against the mounted view, not the already changed search/page state.
    // A short preview or empty search must not replace the list's reading position.
    fn mountedScrollSlot(self: *SettingsHost) view_model_mod.ScrollSlot {
        return self.viewModel().mountedScroll();
    }
    fn mountedScrollOffset(self: *SettingsHost) f32 {
        return self.viewModel().scrollOffset(self.mountedScrollSlot());
    }
    /// 数据清理等流程回到原位置：写当前页的偏移槽（视口随信号滚过去）。
    fn restoreMountedScroll(self: *SettingsHost, offset: f32) void {
        self.viewModel().setScroll(self.mountedScrollSlot(), offset);
    }

    fn selectPage(self: *SettingsHost, index: usize) void {
        self.dispatch(view_model_mod.Intent.selectCategory(index));
    }

    /// Category rows, overview rows and the page intro's Back / Forward all
    /// land in the view-model: same guards as a page switch, search cleared,
    /// new location starts at the top.
    pub fn navigateSettings(self: *SettingsHost, location: view_model_mod.Location) void {
        self.dispatch(view_model_mod.Intent.openAt(location));
    }

    fn save(self: *SettingsHost) void {
        self.saveWithClose(false);
    }

    pub fn locateSettingsProblem(self: *SettingsHost) void {
        self.dispatch(.locate_problem);
    }

    /// Save Bar, "保存关闭" and the deferred retry after a theme installation
    /// is prepared: the view-model checks the gates, the draft and validation,
    /// then asks for `runSave` (Effect.save).
    fn saveWithClose(self: *SettingsHost, close_after_save: bool) void {
        self.dispatch(view_model_mod.Intent.saveDraft(close_after_save));
    }

    /// `Effect.save`: font check, theme installation, background texture and
    /// the config commit. The outcome flows back as `.save_finished`.
    fn runSave(self: *SettingsHost, close_after_save: bool) void {
        self.validateFont();
        if (self.font_problem) |problem| {
            self.refresh(@import("../../../config/appearance_font.zig").problemMessage(problem));
            self.refreshFooter();
            return;
        }
        var staged_count: usize = 0;
        for (self.registry.records.items) |record| if (record.staged_for == self.controller.draft_id) {
            staged_count += 1;
        };
        if (self.installation) |*receipt| {
            const valid = receipt.ready and receipt.draft_id == self.controller.draft_id and receipt.entries.len == staged_count;
            if (!valid) {
                self.resource_worker.?.abortInstallation(receipt) catch |err| {
                    self.fail(err, "主题安装未完成");
                    return;
                };
                self.installation = null;
                self.pending_save = close_after_save;
                self.cx.requestRedraw();
                return;
            }
        } else if (staged_count != 0) {
            self.resource_worker.?.prepareInstallation(&self.registry, self.controller.draft_id) catch |err| {
                self.fail(err, "主题安装未完成");
                return;
            };
            self.pending_save = close_after_save;
            self.refreshFooter();
            self.cx.requestRedraw();
            return;
        }
        var request = self.controller.beginSave(self.runtime, close_after_save) catch |err| {
            self.fail(err, "保存失败，草稿已保留");
            return;
        };
        defer request.deinit();
        // A new CPU image gets an owned copy before commit. The draft retains
        // its last good pixels on any allocation, preflight or Config failure.
        var asset: ?@import("../../../config/background_asset.zig").Prepared = null;
        defer if (asset) |*image| image.deinit(self.allocator);
        const background = request.prepared.owned.?.value.ui.materials.background;
        if (background.enabled and (self.appearance_state.asset == null or !self.appearance_state.asset.?.matches(background) or if (self.controller.background.last_good) |draft_asset| draft_asset.asset_revision != self.appearance_state.asset.?.asset_revision else false)) {
            const good = self.controller.background.last_good orelse {
                _ = self.controller.failSave(&request, error.BackgroundNotPrepared);
                self.fail(error.BackgroundNotPrepared, "保存失败，草稿已保留");
                self.dispatch(view_model_mod.Intent.saveFinished(error.BackgroundNotPrepared));
                return;
            };
            asset = self.copyAsset(good) catch |err| {
                _ = self.controller.failSave(&request, err);
                self.fail(err, "保存失败，草稿已保留");
                self.dispatch(view_model_mod.Intent.saveFinished(err));
                return;
            };
        }
        var prepared = AppearanceApply.prepare(self.allocator, &self.registry, &request.prepared, &self.appearance_state, AppearanceApply.Typography.fromResolved(self.font_result.?), if (asset) |*image| image else null, .{ .context = self, .check = prepareSaveTexture }) catch |err| {
            if (self.pending_texture) |*texture| texture.deinit();
            self.pending_texture = null;
            _ = self.controller.failSave(&request, err);
            self.fail(err, "保存失败，草稿已保留");
            self.pending_rebuild = true;
            self.dispatch(view_model_mod.Intent.saveFinished(err));
            return;
        };
        asset = null; // AppearanceApply owns the copy from here.
        defer prepared.deinit();
        defer {
            if (self.pending_texture) |*texture| texture.deinit();
            self.pending_texture = null;
        }
        const completed = self.appearance_state.completeSettings(self.io, std.Io.Dir.cwd(), &self.registry, &self.controller, self.runtime, &request, &prepared, if (self.installation) |*receipt| receipt else null) catch |err| {
            if (self.pending_texture) |*texture| texture.deinit();
            self.pending_texture = null;
            self.fail(err, "保存失败，草稿已保留");
            self.pending_rebuild = true;
            self.dispatch(view_model_mod.Intent.saveFinished(err));
            return;
        };
        if (!completed) return;
        if (process_state.process_notifications) |notifications| if (self.notification_window) |window| notifications.resolveOperationErrors(window, "偏好设置");
        self.updateBackgroundIdentity();
        if (self.installation) |*receipt| receipt.deinit();
        self.installation = null;
        if (self.pending_texture) |texture| {
            if (self.committed_texture) |*old| old.deinit();
            self.committed_texture = texture;
            self.pending_texture = null;
        } else if (self.draft_texture) |texture| {
            if (self.committed_texture) |*old| old.deinit();
            self.committed_texture = texture;
            self.draft_texture = null;
        }
        if (self.appearance_state.theme) |theme| {
            app_theme.selectTokens(theme.ui_tokens);
            app_theme.publishSchemes(self.cx);
            self.cx.setTheme(app_theme.widgetTheme(app_theme.currentName()));
        }
        if (self.on_appearance_publish) |publish| publish(self);
        self.applyRuntimeSettings();
        self.pending_rebuild = true;
        self.writeStatusLine(null);
        // The view-model closes the window when the commit was a "保存关闭".
        self.dispatch(view_model_mod.Intent.saveFinished(null));
        self.cx.requestRedraw();
    }

    fn copyAsset(self: *SettingsHost, image: @import("../../../config/background_asset.zig").Prepared) !@import("../../../config/background_asset.zig").Prepared {
        return image.clone(self.allocator);
    }
    /// The status palette commits only this field against the latest Runtime;
    /// an unrelated settings draft and its raw validation errors stay owned.
    pub fn immediateTheme(self: *SettingsHost, id: []const u8) !void {
        if (!self.appearance_initialized) return error.AppearanceUnavailable;
        if (self.busy()) return error.AppearanceBusy;
        const record = self.registry.get(id) orelse return error.UnknownTheme;
        if (record.staged_for != null) return error.ThemeNotPrepared;
        const registry = process_state.app_font_registry orelse return error.FontUnavailable;
        const setting = self.runtime.value.ui;
        var resolved = try @import("../../../config/appearance_font.zig").resolve(self.allocator, registry, .{ .family = setting.font_family, .size = @floatFromInt(setting.font_size), .weight = setting.font_weight });
        defer resolved.deinit(self.allocator);
        var candidate = self.runtime.value;
        candidate.ui.theme = record.id;
        var config = try self.runtime.prepare(candidate);
        defer config.deinit();
        var resource = try AppearanceApply.prepare(self.allocator, &self.registry, &config, &self.appearance_state, AppearanceApply.Typography.fromResolved(resolved), null, .{ .context = self, .check = prepareSaveTexture });
        defer resource.deinit();
        defer {
            if (self.pending_texture) |*texture| texture.deinit();
            self.pending_texture = null;
        }
        try self.appearance_state.commit(self.io, std.Io.Dir.cwd(), &self.registry, self.runtime, &config, &resource, null);
        if (self.pending_texture) |texture| {
            if (self.committed_texture) |*previous| previous.deinit();
            self.committed_texture = texture;
            self.pending_texture = null;
        }
        app_theme.selectTokens(self.appearance_state.theme.?.ui_tokens);
        app_theme.publishSchemes(self.cx);
        self.cx.setTheme(app_theme.widgetTheme(app_theme.currentName()));
        if (!self.controller.model.dirty) try self.controller.discardLatest(self.runtime);
        self.applyRuntimeSettings();
        if (self.on_appearance_publish) |publish| publish(self);
        self.pending_rebuild = true;
        self.cx.requestRedraw();
    }
    fn prepareSaveTexture(raw: *anyopaque, image: *const @import("../../../config/background_asset.zig").Prepared) !void {
        const self: *SettingsHost = @ptrCast(@alignCast(raw));
        if (self.controller.background.last_good) |draft| {
            if (self.draft_texture != null and draft.asset_revision == image.asset_revision and std.mem.eql(u8, draft.path, image.path)) return;
        }
        if (self.appearance_state.asset) |saved| {
            if (self.committed_texture != null and std.mem.eql(u8, saved.path, image.path)) return;
        }
        try prepareDraftTexture(raw, image);
    }

    fn applyRuntimeSettings(self: *SettingsHost) void {
        if (!@import("../../../platform/app_icon.zig").apply(self.runtime.value.ui.icon_background)) self.refresh("无法更新 Dock 图标，请稍后重试");
        if (process_state.process_notifications) |notifications| notifications.updatePolicy(self.runtime.value.notify) catch |err| self.fail(err, "通知设置未生效");
        // The preferences window is process-wide: every main window applies
        // the committed settings, and repaints so its appearance republishes.
        if (process_state.process_windows) |process| for (process.runtime.windows.items) |managed| {
            const nav = ProcessWindows.navFor(managed.app) orelse continue;
            if (nav.workspace) |workspace| if (workspace != self.workspace) self.applyToWorkspace(workspace);
            managed.app.cx.requestRedraw();
        };
        if (self.workspace) |workspace| self.applyToWorkspace(workspace);
    }

    fn applyToWorkspace(self: *SettingsHost, workspace: *ws.Workspace) void {
        {
            const setting = self.runtime.value.ui;
            applyCommandInfoSettings(workspace, setting.command_info);
            const font = self.appearance_state.layout.?.font;
            for (workspace.tabs.items) |tab| {
                if (tab.terminal == null) continue;
                tab.terminal.?.setTimestampGutter(setting.timestamp_gutter);
                tab.terminal.?.setTypographyFamily(setting.font_size, setting.line_height, font.weight, font.actual_family, font.family_id) catch {};
                tab.terminal.?.setCursorStyle(if (std.mem.eql(u8, setting.cursor_style, "bar")) .bar else if (std.mem.eql(u8, setting.cursor_style, "underline")) .underline else .block);
                tab.terminal.?.setInputLineHighlight(setting.input_line_highlight) catch {};
                // Keep the live terminal behavior in sync with the saved
                // completion toggle. New sessions receive the same value from
                // Workspace.mount; existing tabs must update immediately after
                // Settings → Save without rebuilding their terminal trees.
                tab.terminal.?.completion_enabled = self.runtime.value.completion.enabled;
                tab.terminal.?.refreshCompletionState();
            }
            // 会话记录卡片里的只读回放：时间戳显示跟随当前设置；排版 / 布局属于录制本身，不改。
            // 主题色经 refreshAppearance 另行发布。
            for (workspace.replays.items) |replay| replay.terminal().setTimestampGutter(setting.timestamp_gutter);
        }
    }

    /// 用户选了“继续编辑 / 取消”：撤回挂起的原生关窗请求（主窗口的退出流程在等它）。
    fn cancelDecision(self: *SettingsHost) void {
        if (self.native_close_waiter) |pending| pending.* = false;
    }
    fn discardAndClose(self: *SettingsHost) void {
        if (self.busy()) return;
        if (self.installation) |*receipt| {
            self.resource_worker.?.abortInstallation(receipt) catch |err| {
                self.fail(err, "无法撤销草稿");
                return;
            };
            self.installation = null;
            self.pending_discard_close = true;
            self.cx.requestRedraw();
            return;
        }
        self.registry.discard(self.controller.draft_id);
        self.controller.discardLatest(self.runtime) catch |err| {
            self.fail(err, "无法撤销草稿");
            return;
        };
        self.validateFont();
        if (self.resource_worker) |*worker| worker.clearSelectedPath();
        self.appearance_context.selected_image_path = "";
        if (self.draft_texture) |*texture| texture.deinit();
        self.draft_texture = null;
        self.closeNow();
    }
    fn revertDraft(self: *SettingsHost) void {
        if (self.busy() or self.installation != null) return;
        self.controller.discardLatest(self.runtime) catch |err| {
            self.fail(err, "无法撤销草稿");
            return;
        };
        self.registry.discard(self.controller.draft_id);
        if (self.resource_worker) |*worker| worker.clearSelectedPath();
        self.appearance_context.selected_image_path = "";
        if (self.draft_texture) |*texture| texture.deinit();
        self.draft_texture = null;
        // 撤销后外观字段回到已保存值：与手动改值同一条路径（重新校验字体、按需准备背景、刷新材质预览）。
        if (self.appearance_initialized) appearanceCommand(self, .draft_values_changed) else self.validateFont();
        self.pending_rebuild = true;
        self.cx.requestRedraw();
    }

    /// Re-project, then re-mount the content page when its location or search changed.
    fn rebuildAll(self: *SettingsHost) void {
        if (self.view_model) |*vm| vm.sync();
        if (self.appearance_context.preview_active) {
            self.rebuildPreview() catch |err| self.fail(err, "设置界面刷新失败");
            return;
        }
        // P3 3e：位置与搜索词都没变时（草稿、宿主状态、主题发布），面板按信号局部更新——只重新投影，不换纪元。
        if (self.windowed and self.yixContentCurrent()) {
            self.rebuildPreview() catch |err| self.fail(err, "设置界面刷新失败");
            return;
        }
        // Navigation rows are keyed by the content epoch: one new epoch
        // re-mounts both the rows and the content page.
        if (self.windowed) self.rebuildYixContent() catch |err| {
            applog.warn(.ui, "settings content rebuild failed: {s}", .{@errorName(err)});
        };
        self.rebuildPreview() catch |err| self.fail(err, "设置界面刷新失败");
    }

    /// The material preview action bar sits over the owning main window,
    /// whose wallpaper and surfaces are what the preview shows.
    fn rebuildPreview(self: *SettingsHost) !void {
        if (self.preview_scope) |old| old.dispose();
        self.preview_scope = null;
        if (self.preview_root) |old| {
            if (old.parent) |parent| self.main_cx.detachChild(parent, old);
            self.main_cx.destroyDetached(old);
        }
        self.preview_root = null;
        if (!self.appearance_context.preview_active) return;
        const scope = try self.main_scope.childScope();
        self.preview_scope = scope;
        const area = if (self.preview_viewport) |viewport| viewport.globalRect() else ui.ComputedRect{ .x = 0, .y = 0, .w = self.main_cx.viewport.width, .h = self.main_cx.viewport.height };
        const width = @min(@as(f32, 660), @max(@as(f32, 1), area.w - 32));
        // P3 3e 外观包：操作条是 `.yix`（`view/material_preview_bar.yix`），参数按此刻的状态给；每次重建都重挂。
        const Bar = @import("../view/_material_preview_bar.yix.zig");
        const materials = self.controller.model.value.ui.materials;
        const status = std.fmt.bufPrint(&self.preview_status, "{d:.1}% · {d}px", .{ materials.background.transparency, materials.blur_px }) catch "";
        const savable = self.controller.model.dirty and self.controller.state() != .saving and !self.busy() and fontStatus(self).problem == null;
        const root = try ui.view.render(scope, self.main_cx, Bar.MaterialPreviewBar(.{ .vm = self.viewModel(), .place = .{ .left = area.x + (area.w - width) / 2, .bottom = 58, .width = width }, .status = status, .restorable = !self.busy(), .savable = savable }));
        self.preview_root = root;
        try self.main_cx.root.?.appendChild(self.allocator, root);
        self.main_cx.requestRedraw();
    }

    /// 焦点是否在内容列里（重挂前要交出）。
    fn contentOwnsFocus(self: *SettingsHost, focused: *ui.Node) bool {
        return focused.isDescendantOf(self.content);
    }

    /// 当前内容页还能不能原样留着——已挂好（不在两阶段之间）、位置与搜索词与挂载时相同。
    /// 概览页、导航与搜索仍整页重挂（位置 / 搜索结果的形态在挂载时定下）。
    fn yixContentCurrent(self: *SettingsHost) bool {
        if (self.yix_settling or self.mounted_page == null) return false;
        if (self.viewModel().contentMode() == .overview) return false;
        if (!std.meta.eql(self.mounted_location, self.controller.location())) return false;
        return self.mounted_query == std.hash.Wyhash.hash(0, self.controller.search_query);
    }
    fn dataPath(self: *SettingsHost, key: []const u8) ?[]const u8 {
        const value = readContentValue(self, .{ .section = "data", .key = key }) orelse return null;
        return if (value == .text) value.text else null;
    }

    /// Content re-mount, in two phases. A new content epoch re-keys the
    /// window's content page; the reactive update (dispose the old page scope,
    /// mount the new page) runs when the after-layout batch ends, so the page
    /// handle is only valid in the next hook round (`settleYixContent`).
    fn rebuildYixContent(self: *SettingsHost) !void {
        // 焦点（S-6）：正文输入框的焦点静默交出（`Page.releaseFocus`），外壳的 `focusRestore` 在新页挂好后
        // 按同名 `focusId` 放回（含选区）。其它正文控件（按钮、提示图标等带 blur 回调的节点）
        // 先主动 blur，让 blur 在页面回调释放前送达——它们本来就不恢复焦点。
        if (self.cx.focus_manager.current_focus) |focused| {
            if (self.contentOwnsFocus(focused)) {
                if (self.mounted_page) |page| page.releaseFocus(self.cx, focused) else self.cx.setFocus(null);
            }
        }
        self.mounted_page = null;
        self.viewModel().remountContent();
        self.yix_settling = true;
        self.cx.requestRedraw();
    }
    /// Second phase: the old page scope is gone; point the host at the new page.
    fn settleYixContent(self: *SettingsHost) void {
        self.yix_settling = false;
        const page = window_frame.Page.of(&self.yix_frame) orelse return;
        self.mounted_page = page;
        self.mounted_page_index = self.controller.model.page_index;
        self.mounted_location = self.controller.location();
        self.mounted_query = std.hash.Wyhash.hash(0, self.controller.search_query);
        self.cx.requestRedraw();
    }

    /// Render `SettingsWindow` and point the host's node fields at what it mounted.
    fn mountYixWindow(self: *SettingsHost, cx: *ui.Cx, scope: *ui.Scope, publication: *shell_styles.ThemePublication) !*ui.Node {
        const settings_window = @import("../view/_settings_window.yix.zig");
        self.controller.drill_down = true;
        const vm = self.viewModel();
        try vm.attach(scope);
        self.yix_frame = .{ .vm = vm, .appearance = if (self.appearance_initialized) &self.appearance_context else null };
        self.cx = cx;
        self.scope = scope;
        const root = try ui.view.render(scope, cx, settings_window.SettingsWindow(.{ .vm = vm, .frame = &self.yix_frame }));
        // 卡片、内容岛、内容页根由模板经 live Ref 交出（`window_frame.Handles`）。
        const card = self.yix_frame.panel() orelse return error.SettingsWindowShape;
        // S-6：卡片不再可聚焦、不挂捕获处理器——整窗快捷键是模板根的 `onKeyDownCapture`（`ViewModel.windowKey`），
        // 无焦点时按键落到模板根（窗口内容根），同样经过它。
        const hook = try scope.createState(WindowHook, .{ .host = self, .cx = cx, .publication = publication });
        try cx.addAfterLayoutHook(hook, WindowHook.run);
        try scope.onCleanup(WindowHook, hook, WindowHook.cleanup);
        self.windowed = true;
        self.panel = root;
        // 状态行由 view-model 投影（`writeStatusLine`），宿主不持有窗口里的文字节点。
        self.content = self.yix_frame.island() orelse return error.SettingsWindowShape;
        self.card = card;
        self.mounted_page = window_frame.Page.of(&self.yix_frame);
        self.mounted_location = self.controller.location();
        self.mounted_query = std.hash.Wyhash.hash(0, self.controller.search_query);
        self.pending_rebuild = true;
        return root;
    }

    fn readContentValue(raw: *anyopaque, key: ValueKey) ?settings_values_mod.Value {
        const self: *SettingsHost = @ptrCast(@alignCast(raw));
        if (std.mem.eql(u8, key.section, "updates")) if (process_state.process_windows) |process| if (process.updater) |updater| if (!updater.coordinator.intent and updater.coordinator.draining() != 0) {
            if (std.mem.eql(u8, key.key, "state")) return .{ .text = "draining" };
            if (std.mem.eql(u8, key.key, "version_badge")) return .{ .text = "正在收尾" };
            if (std.mem.eql(u8, key.key, "available_title")) return .{ .text = "更新已取消，部分工作正在收尾" };
            if (std.mem.eql(u8, key.key, "status")) {
                const Message = struct {
                    var bytes: [192]u8 = undefined;
                };
                return .{ .text = std.fmt.bufPrint(&Message.bytes, "仍有 {d} 项工作正在收尾，其余工作继续运行", .{updater.coordinator.draining()}) catch "正在等待已发出的关闭请求" };
            }
        };
        if (std.mem.eql(u8, key.section, "updates")) {
            const Snapshot = struct {
                var value: @import("../../../update/client.zig").Status = .{};
            };
            @import("../../../update/client.zig").zw_update_status(&Snapshot.value);
            const state = Snapshot.value.state;
            if (std.mem.eql(u8, key.key, "release_channel")) return .{ .text = "正式版" };
            if (std.mem.eql(u8, key.key, "state")) return .{ .text = switch (state) {
                1 => "checking",
                2 => "available",
                3 => "downloading",
                4 => "verifying",
                5, 9, 11 => "ready",
                6, 7 => "preparing",
                8 => "installing",
                10 => "failed",
                else => "idle",
            } };
            if (std.mem.eql(u8, key.key, "available_version")) return .{ .text = if (state >= 2 and state <= 8 or state == 9 or state == 11) Snapshot.value.versionText() else "" };
            if (std.mem.eql(u8, key.key, "version_badge")) return .{ .text = switch (state) {
                1 => "正在检查",
                2 => "有新版本",
                3 => "下载中",
                4 => "校验中",
                5, 9, 11 => "已准备",
                6, 7 => "准备安装",
                8 => "安装中",
                10 => Snapshot.value.failureBadge(),
                12 => "暂无正式版",
                else => if (Snapshot.value.versionText().len != 0) "无需更新" else "待检查",
            } };
            if (std.mem.eql(u8, key.key, "available_title") and (state == 2 or state == 5 or state == 9 or state == 11)) {
                const Title = struct {
                    var bytes: [192]u8 = undefined;
                };
                return .{ .text = if (state == 2) (std.fmt.bufPrint(&Title.bytes, "{s} 正式版可用", .{Snapshot.value.versionText()}) catch "更新信息") else (std.fmt.bufPrint(&Title.bytes, "{s} · 已准备好安装", .{Snapshot.value.versionText()}) catch "更新信息") };
            }
            if (std.mem.eql(u8, key.key, "available_title")) return .{ .text = switch (state) {
                1 => "正在检查新版本…",
                2 => "发现可用的新版本",
                3 => "正在下载更新",
                4 => "正在检查更新包",
                5, 9, 11 => "更新已准备好安装",
                6, 7 => "正在准备安装",
                8 => "正在安装更新",
                10 => Snapshot.value.failureTitle(),
                12 => "暂无可用的正式版更新",
                else => if (Snapshot.value.versionText().len != 0) "当前无需更新" else "检查应用更新",
            } };
        }
        if (std.mem.eql(u8, key.section, "updates") and std.mem.eql(u8, key.key, "status")) {
            const Native = struct {
                extern fn zw_update_summary() [*:0]const u8;
            };
            return .{ .text = std.mem.span(Native.zw_update_summary()) };
        }
        if (std.mem.eql(u8, key.section, "updates") and std.mem.eql(u8, key.key, "last_check")) {
            const Native = struct {
                extern fn zw_update_last_check() [*:0]const u8;
            };
            return .{ .text = std.mem.span(Native.zw_update_last_check()) };
        }
        if (std.mem.eql(u8, key.section, "updates") and std.mem.eql(u8, key.key, "current_version")) {
            const Native = struct {
                extern fn zw_update_current_version() [*:0]const u8;
            };
            return .{ .text = std.mem.span(Native.zw_update_current_version()) };
        }
        if (std.mem.eql(u8, key.section, "updates")) {
            const metadata = @import("application_options");
            if (std.mem.eql(u8, key.key, "version_metadata")) return .{ .text = metadata.version_metadata };
        }
        if (std.mem.eql(u8, key.section, "data")) {
            if (std.mem.eql(u8, key.key, "config_path")) return .{ .text = self.runtime.path };
            if (std.mem.eql(u8, key.key, "hosts_path")) return .{ .text = (self.workspace orelse return null).hosts_path };
        }
        if (std.mem.eql(u8, key.section, "data") and std.mem.eql(u8, key.key, "config_dir")) {
            return .{ .text = std.fs.path.dirname(self.runtime.path) orelse self.runtime.path };
        }
        if (std.mem.eql(u8, key.section, "data")) if (process_state.process_windows) |process| {
            if (std.mem.eql(u8, key.key, "cache_dir")) return .{ .text = process.data_paths.cache_directory };
            if (std.mem.eql(u8, key.key, "logs_dir")) return .{ .text = process.data_paths.diagnostic_directory };
        };
        return null;
    }

    fn notificationAuthorizationHelp(_: *anyopaque) []const u8 {
        return if (process_state.process_notifications) |notifications| notifications.authorizationHelp() else "当前无法使用系统通知。";
    }

    fn notificationAuthorizationFeedback(_: *anyopaque) ?[]const u8 {
        return if (process_state.process_notifications) |notifications| notifications.authorization_feedback else null;
    }

    fn openNotificationPermission(self: *SettingsHost) !void {
        const notifications = process_state.process_notifications orelse return error.NotificationUnavailable;
        if (!notifications.driver.capabilities.system_notifications) return error.NotificationUnavailable;
        const settings = notifications.driver.settings orelse {
            try notifications.refreshAuthorization();
            self.refresh("正在查询系统通知授权…");
            return;
        };
        if (settings.authorization == .not_determined) {
            const window = self.notification_window orelse return error.NotificationWindowClosed;
            try notifications.requestAuthorization(window);
            self.refresh("正在等待系统通知授权结果…");
            return;
        }
        if (settings.authorization == .unavailable) return error.NotificationUnavailable;
        var result = try std.process.run(self.allocator, self.io, .{
            .argv = &.{ "/usr/bin/open", "x-apple.systempreferences:com.apple.preference.notifications?id=com.zerowork.app" },
            .stdout_limit = .limited(4096),
            .stderr_limit = .limited(4096),
        });
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);
        if (!result.term.success()) return error.OpenNotificationSettingsFailed;
        self.refresh("已打开系统通知设置，请允许 ZeroWork 通知。");
    }

    fn dataDirectory(self: *SettingsHost) []const u8 {
        return std.fs.path.dirname(self.runtime.path) orelse ".";
    }

    fn importTheme(self: *SettingsHost) !void {
        if (self.busy()) return error.AppearanceBusy;
        const request = try self.controller.requestThemeImport();
        appearanceCommand(self, .{ .pick_theme = request });
    }

    /// Reveal the resolved user-data directory using the platform's normal
    /// file manager.  The settings value is the actual runtime path, so this
    /// action never opens a guessed or hard-coded HOME location.
    fn openConfigDirectory(self: *SettingsHost) !void {
        const directory = self.dataDirectory();
        const argv = [_][]const u8{ "open", directory };
        var result = try std.process.run(self.allocator, self.io, .{
            .argv = &argv,
            .stdout_limit = .limited(4096),
            .stderr_limit = .limited(4096),
        });
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);
        if (!result.term.success()) return error.OpenConfigDirectoryFailed;
        self.refresh("已打开配置目录");
    }

    /// Explicit diagnostics only. Capture the bounded original files before
    /// AppKit's nested picker; later output and rotation do not expand them.
    fn exportLogs(self: *SettingsHost) !void {
        const Export = @import("../../../host/diagnostic_export.zig");
        const Sequence = struct {
            var next: u64 = 1;
        };
        const sdk = self.cx.system_sdk orelse return error.NativeDialogUnavailable;
        if (Sequence.next == 0) return error.DiagnosticOperationExhausted;
        const operation_id = Sequence.next;
        Sequence.next = if (Sequence.next == std.math.maxInt(u64)) 0 else Sequence.next + 1;
        var capture_failure: Export.Failure = .{};
        var plan = Export.Plan.capture(self.allocator, self.io, self.dataDirectory(), .{ .operation_id = operation_id, .failure = &capture_failure, .diagnostic_directory = if (process_state.process_windows) |process| process.data_paths.diagnostic_directory else null }) catch |err| {
            if (err == error.NoDiagnosticLogs) {
                self.refresh("暂无可导出的诊断日志");
                return;
            }
            var message: [240]u8 = undefined;
            applog.warn(.ui, "settings: diagnostic capture failed ({s}): {s}", .{ capture_failure.sourceName(), @errorName(err) });
            self.refresh(std.fmt.bufPrint(&message, "读取诊断日志失败 · {s} · {s}", .{ capture_failure.sourceName(), error_text.lineOr(err, "详情见应用日志") }) catch "读取诊断日志失败");
            return;
        };
        defer plan.deinit();
        var path_buffer: [4096]u8 = undefined;
        const target = (try @import("../../../platform/dialog_port.zig").run(sdk, .{ .kind = .save_file, .title = "zerowork-diagnostics.tar.gz" }, &path_buffer)) orelse return;
        plan.write(target, .{}) catch |err| {
            var message: [240]u8 = undefined;
            const phase = if (plan.failure.stage == .publish) "发布诊断日志失败" else "写入诊断日志失败";
            applog.warn(.ui, "settings: diagnostic export failed ({s}): {s}", .{ plan.failure.sourceName(), @errorName(err) });
            self.refresh(std.fmt.bufPrint(&message, "{s} · {s} · {s}", .{ phase, plan.failure.sourceName(), error_text.lineOr(err, "详情见应用日志") }) catch phase);
            return;
        };
        self.refresh("应用诊断日志已导出");
    }

    /// Rechecked at dispatch across every process-owned window and resource domain.
    fn dataCleanupBlocked(self: *SettingsHost) ?[]const u8 {
        if (self.hasActiveCleanupSessions()) return "请先结束所有窗口的活动会话与后台连接";
        const process = process_state.process_windows orelse return "应用尚未准备好，请稍后重试";
        if (process.data_cleanup_owner) |owner| if (owner != self) return "另一窗口正在清除应用数据";
        if (process.pending.items.len != 0) return "请等待新窗口创建完成";
        if (process.domain.tasks) |tasks| {
            for (0..tasks.manager.count()) |index| if (tasks.manager.progressAt(index)) |job| {
                switch (job.state) {
                    .succeeded, .failed, .cancelled => if (job.job_cleanup != .released) return "请等待传输资源释放",
                    else => return "请先结束全部传输任务",
                }
            };
            for (tasks.auxiliary_connections.items) |connection| if (!connection.released) return "请先结束后台传输连接";
            for (tasks.retained_connections.items) |connection| if (!connection.released) return "请先结束后台传输连接";
            for (tasks.shared_connections.items) |connection| if (!connection.released) return "请先结束共享传输连接";
        }
        for (process.runtime.windows.items) |managed| {
            const root = managed.app.cx.root orelse continue;
            const nav: *AppNavHost = @ptrCast(@alignCast(root.behavior.events.capture_context orelse continue));
            if (nav.native_close_pending) return "请等待窗口关闭完成";
            if (nav.settings) |settings| {
                if (settings.busy() or settings.installation != null) return "请先完成设置资源操作";
                if (settings.record_cleanup) |*operation| if (operation.running) return "正在清理会话记录";
            }
            if (nav.wizard_host) |wizard| if (wizard.probe_controller.jobs.items.len != 0) return "请先结束连接测试";
            if (nav.ai) |ai| {
                if (ai.execution().thread_state.load(.acquire) != 0 or ai.model_discovery.busy() or ai.attachment_readers.items.len != 0 or ai.image_readers.items.len != 0 or (if (ai.transcript_images) |store| store.busy() else false)) return "请先结束 AI 请求与文件读取";
            }
        }
        return null;
    }

    fn showDataCleanup(self: *SettingsHost) !void {
        if (process_state.process_windows) |process| if (process.data_cleanup_owner != null) return error.CleanupAlreadyRunning;
        // 焦点回到“清除全部数据”走 view-model 的 `requestFocus`（见 `.cancel`），这里只记位置。
        self.data_cleanup_origin = .{ .draft_id = self.controller.draft_id, .page = self.mounted_page_index, .scroll = self.mountedScrollOffset() };
        self.dataCleanupEvent(.{ .show = self.dataCleanupBlocked() });
    }

    /// S-12：把清理流程的进展交给对话框（对话框归 view-model：`model/data_cleanup.zig` + `view/data_cleanup.yix`）。
    fn dataCleanupEvent(self: *SettingsHost, event: view_model_mod.data_cleanup.Event) void {
        if (self.view_model) |*vm| vm.dispatch(view_model_mod.Intent.cleanupEvent(event));
        self.cx.requestRedraw();
    }

    /// 对话框里的选择（`Effect.data_cleanup`）。
    fn dataCleanupChoice(self: *SettingsHost, action: CleanupChoice) void {
        const process = process_state.process_windows orelse return;
        switch (action) {
            .dismiss => {
                // After destructive work starts, returning to editable stale
                // snapshots would recreate data. Failure dismissal only exits.
                if (process.data_cleanup_owner != null) {
                    process.data_cleanup_exit = true;
                    return;
                }
                const origin = self.data_cleanup_origin orelse return;
                self.data_cleanup_origin = null;
                if (!self.open or origin.draft_id != self.controller.draft_id or origin.page != self.mounted_page_index) return;
                self.restoreMountedScroll(origin.scroll);
                // 经 view-model 按 `focusId` 回到“清除全部数据”（S-6）。
                self.viewModel().requestFocus(view_model_mod.focus_ids.data_clear_all);
                self.cx.requestRedraw();
            },
            .confirm, .retry => {
                const origin = self.data_cleanup_origin orelse return;
                if (!self.open or origin.draft_id != self.controller.draft_id) return;
                if (self.dataCleanupBlocked()) |reason| {
                    self.dataCleanupEvent(.{ .blocked = reason });
                    return;
                }
                process.data_cleanup_owner = self;
                process.data_cleanup_pending = true;
                self.dataCleanupEvent(.working);
                self.cx.requestRedraw();
            },
        }
    }

    fn requireCleanupReceipt(receipt: anytype, awaiting: *bool) !void {
        switch (receipt) {
            .released => {},
            .awaiting => awaiting.* = true,
            .unknown => return error.CleanupResourcesUnknown,
        }
    }

    /// Idle controllers can still own an asynchronous native file worker.
    /// Drain its real shutdown receipt before removing any persistent data.
    fn quiesceDataWriters(_: *SettingsHost, process: *ProcessWindows) !void {
        const deadline = @import("../../../platform/realtime.zig").monotonicNs() + 5 * std.time.ns_per_s;
        while (true) {
            var awaiting = false;
            for (process.runtime.windows.items) |managed| {
                const root = managed.app.cx.root orelse continue;
                const nav: *AppNavHost = @ptrCast(@alignCast(root.behavior.events.capture_context orelse continue));
                if (nav.ai) |ai| if (ai.remote_picker) |picker| if (!picker.shutdown()) {
                    awaiting = true;
                };
                if (nav.file_application) |files| try requireCleanupReceipt(files.shutdownStep(), &awaiting);
                if (nav.application_host) |host| _ = try host.safeTick();
            }
            try requireCleanupReceipt(process.domain.local_adapter.shutdownStep(), &awaiting);
            if (process.domain.tasks) |tasks| try requireCleanupReceipt(tasks.shutdownStep(), &awaiting);
            if (process.domain.backgrounds) |backgrounds| try requireCleanupReceipt(backgrounds.shutdownStep(), &awaiting);
            if (!awaiting) return;
            if (@import("../../../platform/realtime.zig").monotonicNs() >= deadline) return error.CleanupResourcesNotReleased;
            var unused: [1]std.c.pollfd = undefined;
            _ = std.c.poll(&unused, 0, 2);
        }
    }

    /// Runs between native ticks after the confirmation frame, with all writers idle.
    pub fn performDataCleanup(self: *SettingsHost) void {
        const process = process_state.process_windows orelse return;
        if (self.dataCleanupBlocked()) |reason| {
            process.data_cleanup_owner = null;
            self.dataCleanupEvent(.{ .show = reason });
            return;
        }
        // A slow log syscall retains its own writer. Poll the real close
        // receipt before erasing directories; never join it on the UI thread.
        if (applog.shutdownStep() != .released) {
            process.data_cleanup_pending = true;
            self.cx.scheduleRedrawAfterNs(16 * std.time.ns_per_ms);
            return;
        }
        self.quiesceDataWriters(process) catch |err| {
            self.dataCleanupFailure("后台资源", err);
            return;
        };
        @import("../../../config/data_lifecycle.zig").beginReset(self.io, process.data_paths) catch |err| {
            self.dataCleanupFailure("清除标记", err);
            return;
        };
        @import("../../../config/credential_store.zig").eraseScope() catch |err| {
            self.dataCleanupFailure("钥匙串", err);
            return;
        };
        const report = @import("../../../config/data_lifecycle.zig").eraseOwned(self.io, process.data_paths) catch |err| {
            self.dataCleanupFailure("应用目录", err);
            return;
        };
        for (report.items[0..report.count]) |item| if (item.failure) |err| {
            self.dataCleanupFailure(switch (item.area) {
                .data => "应用数据",
                .cache => "缓存",
                .diagnostic => "诊断日志",
                .legacy => "旧数据",
            }, err);
            return;
        };
        process.data_cleanup_exit = true;
    }

    fn dataCleanupFailure(self: *SettingsHost, area: []const u8, err: anyerror) void {
        var buffer: [256]u8 = undefined;
        applog.warn(.ui, "settings: data cleanup failed: {s}", .{@errorName(err)});
        const message = std.fmt.bufPrint(&buffer, "{s}清除失败：{s}。部分内容可能已删除；可重试或退出，应用不会继续保存配置。", .{ area, error_text.lineOr(err, "详情见应用日志") }) catch "清除未完成，请重试或退出应用。";
        self.dataCleanupEvent(.{ .failed = .{ .message = message, .retryable = true } });
        self.cx.requestRedraw();
    }

    fn clearLogs(self: *SettingsHost) !void {
        try RecordCleanup.requireIdle(self.hasActiveCleanupSessions());
        if (self.record_cleanup) |*operation| if (operation.running) return error.CleanupAlreadyRunning;
        if (self.record_cleanup_view == null) self.record_cleanup_view = try RecordCleanupView.View.mount(self.cx, self.scope, .{ .context = self, .action = recordCleanupAction });
        self.record_cleanup_origin = .{ .draft_id = self.controller.draft_id, .page = self.mounted_page_index, .scroll = self.mountedScrollOffset() };
        const view = self.record_cleanup_view.?;
        if (self.record_cleanup) |*operation| {
            if (operation.progress().failed != 0) {
                try self.updateRecordCleanup();
                view.showResult();
                return;
            }
        }
        // No enumeration or file mutation occurs before explicit confirmation.
        try view.showConfirmation();
    }

    fn hasActiveCleanupSessions(self: *SettingsHost) bool {
        if (self.application_host) |host| {
            for (host.sessions.sessions.items) |entry| switch (entry.state) {
                .closed => {},
                .ended, .failed => if (entry.create_cleanup != .released) return true,
                .creating, .ready, .attached, .closing, .cleanup_unknown => return true,
            };
        } else if (self.workspace) |workspace| {
            for (workspace.tabs.items) |tab| if (!tab.isCard()) return true;
        }
        return false;
    }

    fn recordCleanupAction(raw: *anyopaque, action: RecordCleanupView.Action) void {
        const self: *SettingsHost = @ptrCast(@alignCast(raw));
        switch (action) {
            .dismiss => self.restoreCleanupOrigin(),
            .confirm, .retry => self.startRecordCleanup(action == .retry) catch |err| {
                if (self.record_cleanup_view) |view| view.showProblem(err);
                self.fail(err, "清除记录失败");
            },
        }
    }

    fn startRecordCleanup(self: *SettingsHost, retry: bool) !void {
        const origin = self.record_cleanup_origin orelse return error.CleanupConfirmationExpired;
        if (origin.draft_id != self.controller.draft_id or !self.open) return error.CleanupConfirmationExpired;
        try RecordCleanup.requireIdle(self.hasActiveCleanupSessions());
        if (self.record_cleanup) |*operation| {
            if (operation.running) return error.CleanupAlreadyRunning;
            if (retry and operation.progress().failed != 0) {
                try operation.retryFailed(false);
                try self.updateRecordCleanup();
                return;
            }
        }
        self.releaseRecordCleanup();
        const directory = try std.Io.Dir.cwd().openDir(self.io, self.dataDirectory(), .{ .follow_symlinks = false });
        errdefer directory.close(self.io);
        var operation = try RecordCleanup.Controller.freeze(self.allocator, self.io, directory, self.hasActiveCleanupSessions());
        errdefer operation.deinit();
        try operation.begin(self.hasActiveCleanupSessions());
        self.record_cleanup_dir = directory;
        self.record_cleanup = operation;
        self.updateRecordCleanup() catch |err| self.fail(err, "清除进度更新失败");
        self.cx.requestRedraw();
    }

    fn pollRecordCleanup(self: *SettingsHost) void {
        const operation = if (self.record_cleanup) |*value| value else return;
        if (!operation.running) return;
        _ = operation.step(self.hasActiveCleanupSessions()) catch |err| {
            if (self.record_cleanup_view) |view| view.showProblem(err);
            operation.running = false;
            return;
        };
        self.updateRecordCleanup() catch |err| self.fail(err, "清除进度更新失败");
        self.cx.requestRedraw();
    }

    fn updateRecordCleanup(self: *SettingsHost) !void {
        const operation = if (self.record_cleanup) |*value| value else return;
        const progress = operation.progress();
        var index_missing = false;
        for (operation.records.items) |record| if (record.state == .failed and record.key != null and record.files.items.len != 0) {
            var all_removed = true;
            for (record.files.items) |file| all_removed = all_removed and file.removed;
            index_missing = index_missing or all_removed;
        };
        if (self.record_cleanup_view) |view| try view.update(progress, operation.firstFailure(), index_missing);
        var buffer: [128]u8 = undefined;
        self.refresh(try std.fmt.bufPrint(&buffer, "已清理 {d} 项 · 失败 {d} 项{s}", .{ progress.deleted, progress.failed, if (progress.done()) "" else " · 处理中" }));
    }

    fn restoreCleanupOrigin(self: *SettingsHost) void {
        const origin = self.record_cleanup_origin orelse return;
        self.record_cleanup_origin = null;
        if (!self.open or origin.draft_id != self.controller.draft_id or origin.page != self.mounted_page_index) return;
        self.restoreMountedScroll(origin.scroll);
        self.viewModel().requestFocus(view_model_mod.focus_ids.data_clear_logs);
        self.cx.requestRedraw();
    }

    fn releaseRecordCleanup(self: *SettingsHost) void {
        if (self.record_cleanup) |*operation| operation.deinit();
        self.record_cleanup = null;
        if (self.record_cleanup_dir) |directory| directory.close(self.io);
        self.record_cleanup_dir = null;
    }

    /// “清理会话记录 / 清除全部数据”此刻能不能点（不能时给原因）。
    fn contentActionState(raw: *anyopaque, action: enum { clear_logs, clear_all }) view_model_mod.ActionState {
        if (action == .clear_all) {
            const self: *SettingsHost = @ptrCast(@alignCast(raw));
            if (self.dataCleanupBlocked()) |reason| return .{ .enabled = false, .reason = reason };
            return .{};
        }
        const self: *SettingsHost = @ptrCast(@alignCast(raw));
        if (self.record_cleanup) |*operation| if (operation.running) return .{ .enabled = false, .reason = "正在清理会话记录" };
        if (self.hasActiveCleanupSessions()) return .{ .enabled = false, .reason = "请先结束活动会话" };
        return .{};
    }

    fn chooseSettingsDirectory(raw: *anyopaque, controller: *SettingsController, key: ValueKey) void {
        const self: *SettingsHost = @ptrCast(@alignCast(raw));
        const sdk = self.cx.system_sdk orelse return;
        var buffer: [4096]u8 = undefined;
        const directory = (@import("../../../platform/dialog_port.zig").run(sdk, .{ .kind = .pick_folder }, &buffer) catch return) orelse return;
        controller.editKey(key.section, key.key, .{ .text = directory }) catch |err| {
            self.fail(err, "无法使用所选目录");
            return;
        };
        self.pending_rebuild = true;
        self.cx.requestRedraw();
    }

    pub fn cleanup(self: *SettingsHost) void {
        // The owning main window is going away: retire the preferences window
        // without calling back into this host.
        if (process_state.settings_window_owner == self) {
            process_state.settings_window_slot.deinit();
            process_state.settings_window_owner = null;
            self.windowed = false;
            if (self.view_model) |*vm| vm.detach();
        }
        self.releaseRecordCleanup();
        if (self.appearance_initialized) {
            self.background_rotation.deinit();
            self.resource_worker.?.shutdown(&self.registry) catch |err| {
                applog.warn(.ui, "appearance worker shutdown failed: {s}", .{@errorName(err)});
                if (self.resource_worker.?.takeInstallation()) |value| {
                    var failed = value;
                    failed.deinit();
                }
            };
            if (self.installation) |*receipt| {
                self.resource_worker.?.abortInstallation(receipt) catch |err| {
                    applog.warn(.ui, "appearance installation cleanup could not start: {s}", .{@errorName(err)});
                    receipt.deinit();
                };
                self.installation = null;
            }
            self.resource_worker.?.shutdown(&self.registry) catch |err| {
                applog.warn(.ui, "appearance installation cleanup failed: {s}", .{@errorName(err)});
                if (self.resource_worker.?.takeInstallation()) |value| {
                    var failed = value;
                    failed.deinit();
                }
            };
            self.resource_worker.?.deinit();
            if (self.font_result) |*font| font.deinit(self.allocator);
            if (self.pending_texture) |*texture| texture.deinit();
            if (self.draft_texture) |*texture| texture.deinit();
            if (self.committed_texture) |*texture| texture.deinit();
            self.appearance_state.deinit();
            self.registry.deinit();
            if (self.resource_dir) |directory| directory.close(self.io);
        }
        if (self.ai_jobs) |*jobs| jobs.deinit();
        self.controller.deinit();
        self.allocator.destroy(self);
    }
};

pub const SettingsNavClick = struct {
    host: *SettingsHost,
    page_index: usize,

    fn activate(self: *SettingsNavClick) void {
        self.host.selectPage(self.page_index);
    }

    fn cleanup(self: *SettingsNavClick) void {
        self.host.allocator.destroy(self);
    }
};
