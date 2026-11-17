//! Native KVM content renderer. All state crosses the owner's typed service
//! boundary; this file has no Runtime, Controller, credential or token access.
const std = @import("std");
const ui = @import("ui");
const panel_header = @import("../../shared/ui/components/panel_header/panel_header.zig");
const contract = @import("../../host/plugin_ui_contract.zig");
const typed = @import("../../host/plugin_services.zig");
const console = @import("console_service.zig");
const framebuffer = @import("framebuffer.zig");
const input = @import("remote_input.zig");
const services = @import("services.zig");
const mapping = @import("input_mapping.zig");
const vm = @import("view_model.zig");
const S = @import("styles.zig");
const Rows = @import("_progress_rows.yss.zig");
const app_menu = @import("../../features/shell/mod.zig").app_menu;
const performance = @import("../../host/frame_performance.zig");
const LogS = @import("../../features/connections/progress/view/connection_logs_styles.zig");
const OM = @import("overlay_model.zig");
const OV = @import("overlay_view.zig");
const ai_control = @import("ai_control.zig");
const Menu = vm.Menu;
const Option = ui.widgets.SelectOption;
const WaitingBounds = struct { width: f32, height: f32, theme: u32, launcher: ?contract.LauncherPlacement };
/// Everything the view's geometry is computed from, read at the layout safety point. Equal key =
/// nothing to recompute. Rects are this view's own boxes (it owns their placement); `waiting`
/// is the connection card's applied size, which a theme replay of its recipe can reset.
const LayoutKey = struct {
    viewport: ui.ComputedRect,
    card: ui.ComputedRect,
    toolbar_width: f32,
    window: [2]f32,
    picture: [2]u32,
    mode: mapping.Mode,
    theme: u32,
    launcher: ?contract.LauncherPlacement,
    status_shown: bool,
    waiting: [2]f32,
    hud_height: f32,
    alert_height: f32,
    scrollbar_y: bool,
    /// Laid-out width of the toolbar's native controls (see `toolsWidth`).
    tools_width: f32,
};
/// Monotonic wall-clock milliseconds. The view's timed behaviour (hint timeout, HUD reveal,
/// elapsed readouts) runs on real time: the window's frame clock stands still while nothing is
/// drawn, and this view no longer draws frames just to keep a clock moving.
fn wallClockMs() f64 {
    return @floatFromInt(@divTrunc(@import("../../platform/realtime.zig").monotonicNs(), std.time.ns_per_ms));
}
const LogBounds = struct { width: f32, height: f32, above: f32, footer: f32, compact: bool, theme: u32 };
const max_order_rows = 256;
const scale_items = [_]ui.widgets.tabs.TabItem{
    .{ .id = @tagName(mapping.Mode.fit), .label = "适应窗口", .test_id = "bmc.display.fit" },
    .{ .id = @tagName(mapping.Mode.original), .label = "100%", .test_id = "bmc.display.original" },
};
pub const CaptureAuthority = struct {
    binding_generation: u64,
    input_epoch: u64,
    control_generation: u64,
    transport_generation: u64,
    frame_generation: u64,

    fn sameEpoch(self: CaptureAuthority, binding_generation: u64, snapshot: input.Snapshot, frame_generation: u64) bool {
        return self.binding_generation == binding_generation and self.input_epoch == snapshot.input_epoch and self.control_generation == snapshot.control_generation and self.transport_generation == snapshot.transport_generation and self.frame_generation == frame_generation;
    }
    fn matches(self: CaptureAuthority, binding_generation: u64, snapshot: input.Snapshot, frame_generation: u64) bool {
        return self.sameEpoch(binding_generation, snapshot, frame_generation) and geometryReady(snapshot, frame_generation) and snapshot.controlled and snapshot.focused and snapshot.connected and !snapshot.capture_paused and !snapshot.remote_unconfirmed;
    }
};
fn geometryReady(snapshot: input.Snapshot, frame_generation: u64) bool {
    // Zero preserves compatibility with an input-only typed provider. The
    // native pipeline starts pending and always publishes a nonzero generation.
    return !snapshot.geometry_pending and (snapshot.geometry_generation == 0 or snapshot.geometry_generation == frame_generation);
}

const menu_names = [_][]const u8{ "控制", "按键", "显示", "电源", "启动" };
const menu_ids = [_][]const u8{ "bmc.control", "bmc.keys", "bmc.display", "bmc.power", "bmc.boot" };
const menu_icons = [_]ui.SvgAsset{ ui.icons.mouse_pointer_2, ui.icons.keyboard, ui.icons.monitor_cog, ui.icons.power, ui.icons.rocket }; // Pencil TcJSa menu icons
const power_actions = [_]services.PowerAction{ .on, .graceful_shutdown, .graceful_restart, .force_off, .force_restart, .power_cycle };
const target_values = [_][]const u8{ "Disabled", "Pxe", "Hdd", "Cd", "Diags", "BiosSetup", "Usb", "None" };
const target_names = [_][]const u8{ "恢复默认（关闭覆盖）", "网络 PXE", "硬盘", "CD / DVD", "诊断", "BIOS 设置", "USB", "None（设备返回）" };
const mode_values = [_][]const u8{ "UEFI", "Legacy" };
const unverified_mapping_message = "尚未确认管理目标或系统信息的来源，仅供查看";
const response_diagnostic_message = "设备响应含附加诊断；以下字段按各自读取结果显示。";
const power_option_ids = [_][]const u8{ "bmc.power.option.on", "bmc.power.option.shutdown", "bmc.power.option.restart", "bmc.power.option.force_off", "bmc.power.option.force_restart", "bmc.power.option.power_cycle" };
const target_option_ids = [_][]const u8{ "bmc.boot.option.disabled", "bmc.boot.option.pxe", "bmc.boot.option.hdd", "bmc.boot.option.cd", "bmc.boot.option.diags", "bmc.boot.option.bios", "bmc.boot.option.usb", "bmc.boot.option.none" };

pub const View = struct {
    mount_request: contract.ContentMount,
    closed: bool = false,
    root: ?*ui.Node = null,
    toolbar: ?*ui.Node = null,
    connection_icon: ?*ui.Node = null,
    /// This view's box holding the title icon and title.
    connection_identity: ?*ui.Node = null,
    connection_title: ?*ui.Node = null,
    disconnect_node: ?*ui.Node = null,
    disconnect_disabled: *ui.Signal(bool) = undefined,
    disconnect_slot: ?*ui.Node = null,
    disconnect_icon_only: *ui.Signal(bool) = undefined,
    connection_symbol: *ui.Signal(?ui.SvgAsset) = undefined,
    connection_tint: *ui.Signal(?ui.Color) = undefined,
    connection_hint: *ui.Signal([]const u8) = undefined,
    connection_label: *ui.Signal([]const u8) = undefined,
    disconnect_confirm_open: *ui.Signal(bool) = undefined,
    disconnect_confirm_title: *ui.Signal([]const u8) = undefined,
    disconnect_confirm_action: *ui.Signal([]const u8) = undefined,
    disconnect_confirm_message: *ui.Signal([]const u8) = undefined,
    disconnect_confirm_dialog: ?*ui.Node = null,
    disconnect_confirm_target: ?*ui.Node = null,
    disconnect_confirm_detail: ?*ui.Node = null,
    disconnect_confirm_return: ?*ui.Node = null,
    connection_hovered: ?*ui.Signal(bool) = null,
    connection_focused: ?*ui.Signal(bool) = null,
    tool_nodes: [5]?*ui.Node = @splat(null),
    /// This view's boxes around the native toolbar controls: placement and show / hide.
    tool_slots: [5]?*ui.Node = @splat(null),
    tool_labels: [5]*ui.Signal([]const u8) = undefined,
    tool_icon_only: *ui.Signal(bool) = undefined,
    /// The native Button's dropdown chevron: shown beside a label, not on the icon-only toolbar.
    tool_chevron: *ui.Signal(bool) = undefined,
    /// Natural widths of the toolbar controls (disconnect + five menus) as zenit laid them out,
    /// labelled and icon-only: the toolbar folds when its width cannot hold them.
    tools_labelled_width: ?f32 = null,
    tools_icon_width: ?f32 = null,
    /// “更多 KVM 操作”（窄工具栏时收起的电源 / 启动）：原生 `W.Menu`，经菜单唯一入口（app_menu，menus 包）挂载。
    more: ?*app_menu.AppMenu = null,
    more_slot: ?*ui.Node = null,
    more_node: ?*ui.Node = null,
    more_open: ?*ui.Signal(bool) = null,
    /// Raised by the window when the theme is published.
    theme_watch: @import("../../shared/ui/theme/theme_watch.zig").ThemeWatch = .{},
    last_compact: ?bool = null,
    last_overflow: bool = false,
    viewport: ?*ui.Node = null,
    scroll: ?ui.widgets.ScrollAreaResult = null,
    image_node: ?*ui.Node = null,
    /// The scrolled extent inside the picture ScrollArea (this view's box).
    canvas: ?*ui.Node = null,
    waiting: ?*ui.Node = null,
    waiting_header: ?*ui.Node = null,
    waiting_title: ?*ui.Node = null,
    waiting_detail: ?*ui.Node = null,
    waiting_body: ?ui.widgets.ScrollAreaResult = null,
    /// This view's boxes around / inside the progress ScrollArea: the height and the content.
    waiting_viewport: ?*ui.Node = null,
    waiting_list: ?*ui.Node = null,
    progress_scroll_y: *ui.Signal(f32) = undefined,
    progress_expanded: [vm.progress_group_count]*ui.Signal(bool) = undefined,
    waiting_actions: ?*ui.Node = null,
    progress_active: bool = false,
    progress_projection: vm.ProgressProjection = .{},
    progress_disclosure: vm.ProgressDisclosure = .{},
    progress_failure_scroll: ?usize = null,
    progress_stage_scroll: ?usize = null,
    progress_last_stage: ?console.progress.Stage = null,
    progress_attempt: ?services.OperationKey = null,
    progress_timing: ?*ui.Node = null,
    progress_durations: [vm.progress_group_count]?*ui.Node = @splat(null),
    progress_total_time: ?*ui.Node = null,
    progress_status: ?*ui.Node = null,
    progress_notice: ?*ui.Node = null,
    progress_steps: ?*ui.Node = null,
    progress_rows: [vm.progress_group_count]?*ui.Node = @splat(null),
    progress_details: [vm.progress_group_count]?*ui.Node = @splat(null),
    progress_chevrons: [vm.progress_group_count]?*ui.Node = @splat(null),
    progress_icons: [vm.progress_group_count]?*ui.Node = @splat(null),
    progress_names: [vm.progress_group_count]?*ui.Node = @splat(null),
    progress_states: [vm.progress_group_count]?*ui.Node = @splat(null),
    progress_route: ?*ui.Node = null,
    progress_route_text: ?*ui.Node = null,
    cancel_node: ?*ui.Node = null,
    cancel_disabled: *ui.Signal(bool) = undefined,
    retry_disabled: *ui.Signal(bool) = undefined,
    cancel_pending: bool = false,
    retry_node: ?*ui.Node = null,
    log_open: ?*ui.Signal(bool) = null,
    log_modal: ?ui.widgets.ModalResult = null,
    log_footer: ?*ui.Node = null,
    log_scroll: ?ui.widgets.ScrollAreaResult = null,
    log_scroll_y: *ui.Signal(f32) = undefined,
    log_width: *ui.Signal(f32) = undefined,
    log_max_height: *ui.Signal(f32) = undefined,
    log_content: ?*ui.Node = null,
    log_list: ?*ui.Node = null,
    log_viewport: ?*ui.Node = null,
    log_detail: ?*ui.Node = null,
    log_empty: ?*ui.Node = null,
    log_rows: [vm.log_capacity]?*ui.Node = @splat(null),
    log_timestamps: [vm.log_capacity]?*ui.Node = @splat(null),
    log_messages: [vm.log_capacity]?*ui.Node = @splat(null),
    log_durations: [vm.log_capacity]?*ui.Node = @splat(null),
    log_route_text: ?*ui.Node = null,
    log_revision: ?u64 = null,
    log_layout_pending: bool = false,
    last_log_open: bool = false,
    log_scroll_pending: bool = false,
    log_follow_latest: bool = true,
    log_anchor: ?struct { sequence: u64, inside: f32, fallback: f32 } = null,
    log_sequences: [vm.log_capacity]u64 = @splat(0),
    log_count: usize = 0,
    waiting_bounds: ?WaitingBounds = null,
    log_bounds: ?LogBounds = null,
    bounds_layout_pending: bool = false,
    snapshot: ?console.OwnedSnapshot = null,
    power_snapshot: ?services.OwnedPowerSnapshot = null,
    boot_snapshot: ?services.OwnedBootSnapshot = null,
    management_operation: ?struct { key: services.OperationKey, boot: bool } = null,
    management_result: ?services.Owned(services.Result) = null,
    draft: vm.BootDraft = .{},
    mode: mapping.Mode = .fit,
    captured: bool = false,
    capture_authority: ?CaptureAuthority = null,
    view_only: bool = true,
    watch_only_selected: bool = false,
    window_focused: bool = true,
    pending_capture: bool = false,
    pending_capture_authority: ?CaptureAuthority = null,
    keyboard: mapping.Keyboard = .{},
    wheel: mapping.WheelAccumulator = .{},
    buttons: u8 = 0,
    pointer_captured: bool = false,
    pending_pointer: ?input.Pointer = null,
    last_pointer_ms: f64 = -1000,
    input_sequence: u64 = 0,
    texture: ?u32 = null,
    frame_revision: u64 = 0,
    frame_generation: u64 = 0,
    show_fps: *ui.Signal(bool) = undefined,
    /// Pencil j8WXoF card overlays (O1 status, O2 HUD, O3 hint, O4 waiting, O5 AI frame).
    overlays: ?*OV.Overlays = null,
    video_card: ?*ui.Node = null,
    /// Where the tab's AI launcher rests when this card occupies its corner (host-published).
    launcher: ?contract.LauncherPlacement = null,
    hud: OM.HudReveal = .{},
    /// The pointer is over the picture: the picture node's native hover, the only hover source.
    picture_hovered: ?*ui.Signal(bool) = null,
    hud_inside: bool = false,
    hint: OM.Hint = .{},
    /// The owner's change tokens this view last projected (console_service.Pulse).
    seen: ?console.Pulse = null,
    /// Re-read the console snapshot on the next frame: set by this view's own actions and clocks
    /// (the owner's publications arrive through `seen`).
    stale: bool = true,
    management_stale: bool = true,
    /// Recompute the card overlays (O1–O5) on the next frame.
    overlays_stale: bool = true,
    layout_key: ?LayoutKey = null,
    /// Wall-clock deadlines (monotonic ms), each armed only while its readout is on screen.
    progress_due_ms: ?f64 = null,
    performance_due_ms: ?f64 = null,
    overlay_due_ms: ?f64 = null,
    /// The connection attempt is still running (its elapsed readouts move).
    progress_running: bool = false,
    /// Tooltips of the icon-only toolbar: compact and no menu open.
    hints_enabled: *ui.Signal(bool) = undefined,
    clock: *const fn () f64 = wallClockMs,
    display_fps: ?f32 = null,
    decode_fps: ?f32 = null,
    /// O4 "waiting for picture" is up (power running or no signal); the progress card yields.
    picture_waiting: bool = false,
    no_signal: bool = false,
    /// The connection / failure card is up (O2 hides under it).
    progress_shown: bool = false,
    /// The power action this view submitted and when it started running (monotonic ms).
    power_action: ?services.PowerAction = null,
    power_started_ms: ?f64 = null,
    fps_detail: ?*ui.Node = null,
    fps_gap_value: ?*ui.Node = null,
    fps_age_value: ?*ui.Node = null,
    decoded_meter: performance.Meter = .{},
    decoded_total: ?u64 = null,
    decoded_generation: u64 = 0,
    width: u32 = 0,
    height: u32 = 0,
    after_layout_registered: bool = false,
    menus: [5]?ui.widgets.popover.PopoverResult = @splat(null),
    /// Per menu: this view's scroll viewport box (its height) and body box (its content).
    menu_viewports: [5]?*ui.Node = @splat(null),
    menu_bodies: [5]?*ui.Node = @splat(null),
    menu_scrolls: [5]?ui.widgets.ScrollAreaResult = @splat(null),
    open: [5]*ui.Signal(bool) = undefined,
    menu_signal_count: usize = 0,
    keys_disabled: *ui.Signal(bool) = undefined,
    request_disabled: *ui.Signal(bool) = undefined,
    capture_disabled: *ui.Signal(bool) = undefined,
    power_disabled: *ui.Signal(bool) = undefined,
    boot_disabled: *ui.Signal(bool) = undefined,
    mode_disabled: *ui.Signal(bool) = undefined,
    power_execute_disabled: *ui.Signal(bool) = undefined,
    boot_execute_disabled: *ui.Signal(bool) = undefined,
    power_query: ?*ui.Node = null,
    boot_query: ?*ui.Node = null,
    power_cancel: ?*ui.Node = null,
    boot_cancel: ?*ui.Node = null,
    switch_disabled: *ui.Signal(bool) = undefined,
    power_options: *ui.Signal([]const Option) = undefined,
    boot_options: *ui.Signal([]const Option) = undefined,
    mode_options: *ui.Signal([]const Option) = undefined,
    power_value: *ui.Signal(?[]const u8) = undefined,
    target_value: *ui.Signal(?[]const u8) = undefined,
    mode_value: *ui.Signal(?[]const u8) = undefined,
    boot_continuous: *ui.Signal(bool) = undefined,
    power_choice: services.PowerAction = .on,
    power_storage: [2][6]Option = undefined,
    target_storage: [2][8]Option = undefined,
    mode_storage: [2][2]Option = undefined,
    option_slot: usize = 0,
    control_label: ?*ui.Node = null,
    control_request_row: ?*ui.Node = null,
    power_label: ?*ui.Node = null,
    power_scope_label: ?*ui.Node = null,
    power_mapping_warning: ?*ui.Node = null,
    power_hint: ?*ui.Node = null,
    boot_label: ?*ui.Node = null,
    boot_scope_label: ?*ui.Node = null,
    boot_mapping_warning: ?*ui.Node = null,
    boot_pending_label: ?*ui.Node = null,
    boot_hint: ?*ui.Node = null,
    boot_details: ?*ui.Node = null,
    mode_row: ?*ui.Node = null,
    order_rows: ?*ui.Node = null,
    /// The boot-order rows this view has built so far (reused across refreshes).
    order_nodes: [max_order_rows]?*ui.Node = @splat(null),
    order_node_count: usize = 0,
    order_mapping_warning: ?*ui.Node = null,
    order_open: ?*ui.Signal(bool) = null,
    order_modal: ?ui.widgets.ModalResult = null,
    order_scroll: ?ui.widgets.ScrollAreaResult = null,
    order_viewport: ?*ui.Node = null,
    /// 适应窗口 / 100%：the native segmented Tabs' active id (`@tagName(mapping.Mode)`).
    scale_value: *ui.Signal(?[]const u8) = undefined,
    original_hint: ?*ui.Node = null,
    fullscreen_label: *ui.Signal([]const u8) = undefined,
    message: ?*ui.Node = null,

    const Borrowed = struct { binding: typed.Binding, table: *const console.Interface };
    fn borrowConsole(self: *View) !Borrowed {
        const access = self.mount_request.service_access orelse return error.ServiceUnavailable;
        const binding = (try access.lookup(self.mount_request.owner, console.definition)) orelse return error.ServiceUnavailable;
        return .{ .binding = binding, .table = try binding.borrow(console.Interface, console.key, self.mount_request.owner) };
    }
    fn lookup(self: *View, definition: typed.Definition) !?typed.Binding {
        const access = self.mount_request.service_access orelse return null;
        return access.lookup(self.mount_request.owner, definition);
    }
    fn anyMenu(self: *const View) bool {
        if (self.closed) return false;
        if (self.more_open) |open| if (open.peek()) return true;
        if (self.order_open) |open| if (open.peek()) return true;
        if (self.log_open) |open| if (open.peek()) return true;
        for (self.open[0..self.menu_signal_count]) |signal| if (signal.peek()) return true;
        return false;
    }
    fn closeMenus(self: *View) void {
        if (self.more_open) |open| open.set(false);
        for (self.open[0..self.menu_signal_count]) |signal| signal.set(false);
        if (self.order_open) |open| open.set(false);
        if (self.log_open) |open| open.set(false);
    }
    /// Something this view shows changed by its own doing (not through the owner's pulse):
    /// project again on the next frame.
    fn invalidate(self: *View) void {
        self.stale = true;
        self.overlays_stale = true;
        self.mount_request.cx.requestRedraw();
    }
    fn releaseInput(self: *View, cause: input.ReleaseCause) void {
        if (self.captured or self.pending_capture or self.hint.active) self.invalidate();
        self.captured = false;
        self.capture_authority = null;
        self.pending_capture = false;
        self.pending_capture_authority = null;
        self.buttons = 0;
        self.pending_pointer = null;
        self.keyboard.clear();
        self.wheel.clear();
        self.hint.clear();
        if (self.pointer_captured) self.mount_request.cx.releasePointerCapture();
        self.pointer_captured = false;
        if (self.lookup(input.definition) catch null) |binding| {
            if (binding.borrow(input.Interface, input.key, self.mount_request.owner)) |table| {
                _ = table.release_all(binding.context, binding, cause);
            } else |_| {}
        }
        if (self.borrowConsole()) |service| {
            service.table.set_focus(service.binding.context, service.binding, false) catch {};
        } else |_| {}
    }
    fn showMessage(self: *View, text: []const u8) void {
        if (self.message) |node| node.setTextContent(self.mount_request.cx.allocator, text) catch {};
        // O3: an error / refusal stays until the user's next action.
        self.hint.show(text, .until_action, self.clock());
        self.overlays_stale = true;
        self.mount_request.cx.requestRedraw();
    }
    /// 操作失败的提示：用户文案取 shared/base/error_text.zig（唯一目录），原始错误名只进应用日志。
    fn showFailure(self: *View, err: anyerror) void {
        @import("../../platform/applog.zig").warn(.app, "bmc console action failed: {s}", .{@errorName(err)});
        self.showMessage(@import("../../shared/base/error_text.zig").lineOr(err, "操作未完成，请重试；详情见应用日志"));
    }
    fn beginCapture(self: *View, requested: ?CaptureAuthority) void {
        if (self.closed or self.texture == null or self.watch_only_selected or !self.window_focused or !self.mount_request.cx.window_active or self.anyMenu() or self.mount_request.cx.overlay_stack.topmost() != null) return;
        const service = self.borrowConsole() catch return;
        var snapshot = service.table.snapshot(service.binding.context, service.binding, self.mount_request.cx.allocator) catch return;
        defer snapshot.deinit();
        if (!snapshot.value.rfb_ready or snapshot.value.read_only_requested or self.frame_generation != snapshot.value.frame_generation or !snapshot.value.input.connected or !snapshot.value.input.controlled or snapshot.value.input.remote_unconfirmed) return;
        if (!geometryReady(snapshot.value.input, self.frame_generation)) {
            self.showMessage("画面尺寸正在更新，收到完整新画面后可重新捕获键鼠。");
            return;
        }
        // Taking human focus can revoke an AI lease and advance the epoch.
        // Freeze the authority after that real handoff; later events must never
        // adopt a newer transport/control/focus grant implicitly.
        const binding = (self.lookup(input.definition) catch null) orelse {
            self.releaseInput(.released);
            return;
        };
        const table = binding.borrow(input.Interface, input.key, self.mount_request.owner) catch {
            self.releaseInput(.released);
            return;
        };
        if (requested) |authority| if (!authority.sameEpoch(binding.generation, snapshot.value.input, self.frame_generation)) return;
        service.table.set_focus(service.binding.context, service.binding, true) catch |err| {
            self.showFailure(err);
            return;
        };
        const current = table.snapshot(binding.context, binding) catch {
            self.releaseInput(.released);
            return;
        };
        var focused_snapshot = service.table.snapshot(service.binding.context, service.binding, self.mount_request.cx.allocator) catch {
            self.releaseInput(.released);
            return;
        };
        defer focused_snapshot.deinit();
        const authority: CaptureAuthority = .{ .binding_generation = binding.generation, .input_epoch = current.input_epoch, .control_generation = current.control_generation, .transport_generation = current.transport_generation, .frame_generation = self.frame_generation };
        if (!focused_snapshot.value.rfb_ready or focused_snapshot.value.frame_generation != self.frame_generation or snapshot.value.input.control_generation != current.control_generation or snapshot.value.input.transport_generation != current.transport_generation or !authority.matches(binding.generation, focused_snapshot.value.input, self.frame_generation)) {
            self.releaseInput(.released);
            return;
        }
        self.view_only = false;
        self.capture_authority = authority;
        self.captured = true;
        // O3: a transient hint fades after 3 s; O1 keeps the captured state in the toolbar.
        self.hint.show("已捕获键鼠，按 " ++ mapping.release_hint ++ " 释放", .transient, self.clock());
        if (self.viewport) |node| self.mount_request.cx.focus_manager.setFocus(node);
        self.invalidate();
    }
    fn submit(self: *View, event: input.Event) bool {
        if (self.closed or !self.captured or self.view_only) return false;
        if (!self.window_focused or !self.mount_request.cx.window_active or self.anyMenu() or self.mount_request.cx.overlay_stack.topmost() != null) {
            self.releaseInput(.lost_focus);
            return false;
        }
        const binding = (self.lookup(input.definition) catch null) orelse {
            self.releaseInput(.disconnected);
            return false;
        };
        const table = binding.borrow(input.Interface, input.key, self.mount_request.owner) catch {
            self.releaseInput(.disconnected);
            return false;
        };
        const snapshot = table.snapshot(binding.context, binding) catch {
            self.releaseInput(.disconnected);
            return false;
        };
        const authority = self.capture_authority orelse {
            self.releaseInput(.control_revoked);
            return false;
        };
        if (!authority.matches(binding.generation, snapshot, self.frame_generation)) {
            self.releaseInput(.control_revoked);
            return false;
        }
        self.input_sequence = @max(self.input_sequence, snapshot.last_input_sequence);
        if (self.input_sequence == std.math.maxInt(u64)) {
            self.releaseInput(.released);
            return false;
        }
        self.input_sequence += 1;
        const result = table.submit(binding.context, binding, .{ .session_handle = self.mount_request.owner, .binding_generation = authority.binding_generation, .input_sequence = self.input_sequence, .input_epoch = authority.input_epoch, .control_generation = authority.control_generation, .geometry_generation = authority.frame_generation, .event = event });
        return switch (result) {
            .accepted => true,
            else => blk: {
                self.releaseInput(.send_failed);
                break :blk false;
            },
        };
    }
    fn geometry(self: *View) ?mapping.Geometry {
        if (self.texture == null) return null;
        const node = self.viewport orelse return null;
        const rect = node.globalRect();
        const scroll = self.scroll orelse return null;
        // The scroll offset as painted: where this view's canvas sits relative to the viewport
        // (ScrollArea snaps the painted translation to the backing-pixel grid; the unsnapped
        // accumulator could shift a click by one pixel under fractional local scrolling).
        _ = scroll;
        const canvas = (self.canvas orelse return null).globalRect();
        return mapping.Geometry.calculate(.{ .x = rect.x, .y = rect.y, .width = rect.w, .height = rect.h }, self.width, self.height, self.mode, .{ .x = rect.x - canvas.x, .y = rect.y - canvas.y });
    }
    fn pointer(self: *View, x: f32, y: f32, mask: u8, dragging: bool) bool {
        const g = self.geometry() orelse return false;
        var value = g.remote(.{ .x = x, .y = y }, dragging) orelse return false;
        value.buttons = mask;
        if (!self.submit(.{ .pointer = value })) return false;
        self.buttons = mask;
        return true;
    }
    fn flushPointer(self: *View) void {
        const pending = self.pending_pointer orelse return;
        self.pending_pointer = null;
        if (self.submit(.{ .pointer = pending })) self.last_pointer_ms = ui.frame.estimateTimeMs();
    }
    fn flushPointerWhenDue(self: *View) void {
        if (self.pending_pointer == null) return;
        const now = ui.frame.estimateTimeMs();
        const remaining_ms = 1000.0 / 60.0 - (now - self.last_pointer_ms);
        if (remaining_ms <= 0 or now < self.last_pointer_ms) {
            self.flushPointer();
        } else {
            // A final move must not wait for the ordinary 33ms console poll.
            // Cx retains the earliest scheduled redraw, including at idle.
            self.mount_request.cx.scheduleRedrawAfterNs(@intFromFloat(@ceil(remaining_ms * std.time.ns_per_ms)));
        }
    }
    fn localPointerTarget(self: *View, x: f32, y: f32) bool {
        if (self.pointer_captured) return false;
        const area = self.scroll orelse return false;
        const hit = self.mount_request.cx.hitTestQuery(.{ .kind = .pointer, .world_x = x, .world_y = y }) orelse return false;
        const target = self.mount_request.cx.node_registry.resolve(hit.handle, null) orelse return false;
        // ScrollArea exposes its content slot publicly. Its local chrome and
        // sibling status controls must retain their native pointer handlers.
        return target != area.container and target != area.content and !target.isDescendantOf(area.content);
    }
    fn handle(event: ui.events.Event, raw: ?*anyopaque) ui.events.EventResult {
        const self: *View = @ptrCast(@alignCast(raw orelse return .ignored));
        if (self.closed) return .ignored;
        if ((event == .mouse_down or event == .key_down) and self.hint.active and self.hint.kind == .until_action) {
            self.hint.userAction();
            self.overlays_stale = true;
            self.mount_request.cx.requestRedraw();
        }
        switch (event) {
            .mouse_down => |value| {
                if (self.anyMenu()) return .ignored;
                if (self.localPointerTarget(value.x, value.y)) {
                    if (self.captured) self.releaseInput(.released);
                    return .ignored;
                }
                const g = self.geometry() orelse return .ignored;
                if (g.remote(.{ .x = value.x, .y = value.y }, false) == null) return .ignored;
                if (!self.captured) self.beginCapture(null);
                if (!self.captured) return .handled;
                self.flushPointer();
                const mask = self.buttons | buttonMask(value.button);
                if (self.pointer(value.x, value.y, mask, false)) {
                    self.mount_request.cx.setPointerCapture(self.viewport.?);
                    self.pointer_captured = true;
                    return .stop;
                }
            },
            .mouse_up => |value| {
                if (!self.captured) return .ignored;
                if (self.localPointerTarget(value.x, value.y)) return .ignored;
                self.flushPointer();
                _ = self.pointer(value.x, value.y, self.buttons & ~buttonMask(value.button), self.buttons != 0);
                if (self.buttons == 0 and self.pointer_captured) {
                    self.mount_request.cx.releasePointerCapture();
                    self.pointer_captured = false;
                }
                return .stop;
            },
            .mouse_move => |value| {
                if (!self.captured) return .ignored;
                if (self.localPointerTarget(value.x, value.y)) return .ignored;
                const g = self.geometry() orelse return .ignored;
                var pointer_value = g.remote(.{ .x = value.x, .y = value.y }, self.buttons != 0) orelse return .ignored;
                pointer_value.buttons = self.buttons;
                self.pending_pointer = pointer_value;
                self.flushPointerWhenDue();
                return .stop;
            },
            .scroll => |value| {
                if (!self.captured or self.anyMenu()) return .ignored;
                if (self.localPointerTarget(value.x, value.y)) {
                    self.releaseInput(.released);
                    return .ignored;
                }
                const g = self.geometry() orelse return .ignored;
                const p = g.remote(.{ .x = value.x, .y = value.y }, false) orelse return .ignored;
                const steps = self.wheel.add(value.dx, value.dy, value.isTrackpad());
                if (steps.x != 0 or steps.y != 0) _ = self.submit(.{ .wheel = .{ .x = p.x, .y = p.y, .steps_x = steps.x, .steps_y = steps.y } });
                return .stop;
            },
            .key_down, .key_up => |value| {
                const modifiers: mapping.Modifiers = .{ .shift = value.modifiers.shift, .ctrl = value.modifiers.ctrl, .alt = value.modifiers.alt, .super = value.modifiers.super };
                const raw_key = @backingInt(value.key);
                if (mapping.isReleaseShortcut(raw_key, modifiers)) {
                    if (event == .key_down) self.releaseCapture();
                    return .stop;
                }
                if (!self.captured or self.anyMenu()) return .ignored;
                if (self.keyboard.keyBatch(raw_key, modifiers, event == .key_down)) |batch| {
                    for (batch.slice()) |key| {
                        if (!self.submit(.{ .key = key })) break;
                    }
                } else self.showMessage("此按键尚不支持；可使用按键菜单发送常用按键。");
                return .stop;
            },
            // Physical keys already produced the remote event. Host IME text is
            // never guessed into scancodes and never sent a second time.
            .text_input, .ime_preedit, .ime_commit, .ime_delete_surrounding => return if (self.captured) .stop else .ignored,
            .blur => {
                self.releaseInput(.lost_focus);
            },
            else => {},
        }
        return .ignored;
    }
    fn reserved(event: ui.events.Event, raw: ?*anyopaque) ui.events.EventResult {
        if (event != .key_down and event != .key_up) return .ignored;
        const value = if (event == .key_down) event.key_down else event.key_up;
        if (!mapping.isReleaseShortcut(@backingInt(value.key), .{ .ctrl = value.modifiers.ctrl, .alt = value.modifiers.alt })) return .ignored;
        return handle(event, raw);
    }
    /// Re-read the owner's console snapshot and project it. Runs when the owner's pulse moved,
    /// after this view's own actions (`stale`), and while a running clock is on screen.
    fn refresh(self: *View) !void {
        self.stale = false;
        self.overlays_stale = true;
        const service = try self.borrowConsole();
        var next = try service.table.snapshot(service.binding.context, service.binding, self.mount_request.cx.allocator);
        var retained = false;
        errdefer if (!retained) next.deinit();
        if (!next.value.owner.eql(self.mount_request.owner)) return error.StaleBinding;
        if (self.captured) {
            const authority = self.capture_authority;
            if (authority == null or !authority.?.matches(authority.?.binding_generation, next.value.input, next.value.frame_generation) or !next.value.rfb_ready) self.releaseInput(.control_revoked);
        }
        if (self.snapshot) |*old| old.deinit();
        self.snapshot = next;
        retained = true;
        const value = self.snapshot.?.value;
        try setText(self, self.connection_title, if (value.name.len != 0) value.name else if (value.target.len != 0) value.target else "KVM 控制台");
        var chord_available = false;
        if (try self.lookup(input.definition)) |binding| {
            const table = try binding.borrow(input.Interface, input.key, self.mount_request.owner);
            if (self.capture_authority) |authority| if (binding.generation != authority.binding_generation) self.releaseInput(.control_revoked);
            if (comptime @hasField(input.Interface, "submit_chord")) chord_available = table.submit_chord != null;
        }
        self.keys_disabled.set(!value.rfb_ready or !value.input.controlled or value.read_only_requested or !chord_available);
        self.request_disabled.set(!value.rfb_ready or value.input.controlled or value.read_only_requested or value.control == .awaiting_authorization);
        self.capture_disabled.set(!value.rfb_ready or !value.input.controlled or value.input.remote_unconfirmed or !geometryReady(value.input, self.frame_generation));
        try setText(self, self.control_label, if (!value.input.connected) "视频通道未就绪" else if (value.input.controlled) (if (self.captured) "已获控制权 · 已捕获键鼠" else if (self.watch_only_selected) "已获控制权 · 仅观看" else "已获控制权 · 键鼠已释放") else switch (value.control) {
            .awaiting_authorization => "已申请控制权 · 等待目标授权",
            .rejected => "控制权申请已被目标拒绝",
            else => if (value.read_only_requested) "当前配置为仅观看" else "仅观看 · 尚未获控制权",
        });
        if (self.control_request_row) |row| row.setDisplay(if (value.control_request != null) .flex else .none);
        // Borrow the original framebuffer definition as well as the sink: the
        // former proves this owner exposes frames, the latter owns GPU lifetime.
        if (try self.lookup(framebuffer.definition)) |binding| _ = try binding.borrow(framebuffer.Interface, framebuffer.key, self.mount_request.owner);
        try self.presentFrame(value);
        try self.updatePerformance(value);
        try self.projectProgress(value);
        self.disconnect_disabled.set(self.cancel_pending or service.table.cancel == null or value.cleanup != .not_started or value.route == .closed or value.route == .failed);
        self.syncConnectionIndicator();
        if (self.mount_request.content_context) |context| self.fullscreen_label.set(if (context.fullscreen()) "退出全屏" else "进入全屏");
    }
    /// Read the owner's change tokens and re-read only what moved. The owner publishes; nothing
    /// here runs on a timer.
    fn consumePulse(self: *View) !void {
        const service = try self.borrowConsole();
        const pulse = try service.table.pulse(service.binding.context, service.binding);
        const before = self.seen;
        self.seen = pulse;
        if (before == null or before.?.state != pulse.state) self.stale = true;
        if (before == null or before.?.management != pulse.management) self.management_stale = true;
        self.sampleDecoded(pulse.decoded_frames);
    }
    /// Count newly decoded frames for the decode-rate readout (rates are refreshed by their own clock).
    fn sampleDecoded(self: *View, decoded_frames: u64) void {
        const total = self.decoded_total orelse {
            self.decoded_total = decoded_frames;
            if (decoded_frames != 0 and self.texture != null) self.decoded_meter.record(@intFromFloat(@max(0, self.clock())), 1);
            return;
        };
        if (decoded_frames == total) return;
        if (decoded_frames < total) self.decoded_meter = .{} else if (self.texture != null) self.decoded_meter.record(@intFromFloat(@max(0, self.clock())), decoded_frames - total);
        self.decoded_total = decoded_frames;
        // New frames: the rate readouts move again.
        self.framesMoved();
    }
    /// A video frame was decoded or shown: (re)start the 500 ms clock of the rate readouts if it
    /// is not running. It stops by itself once the readouts have settled (`updatePerformance`).
    fn framesMoved(self: *View) void {
        if (self.performance_due_ms == null and self.show_fps.peek()) self.performance_due_ms = self.clock() + 500;
    }
    /// Refresh the rate readouts (O2 HUD line and the display menu's statistics). They are live
    /// values on a 500 ms clock that runs only while a readout is on screen and still moving:
    /// with no new frame the one-second rates settle at 0 and the clock stops; the "since last
    /// frame" statistics keep counting only while the display menu is open.
    fn updatePerformance(self: *View, value: console.Snapshot) !void {
        const now_f = self.clock();
        const now: u64 = @intFromFloat(@max(0, now_f));
        const live = value.video == .streaming and self.texture != null;
        if (self.fps_detail) |detail| detail.setDisplay(if (self.show_fps.peek()) .flex else .none);
        if (self.decoded_generation != value.frame_generation) {
            self.decoded_meter = .{};
            self.decoded_generation = value.frame_generation;
        }
        const meter = if (self.mount_request.frame_sink) |sink| &sink.presentation.meter else null;
        self.display_fps = if (live and meter != null) (if (meter.?.fps(now)) |fps| @as(f32, @floatCast(fps)) else null) else null;
        self.decode_fps = if (live) (if (self.decoded_meter.fps(now)) |fps| @as(f32, @floatCast(fps)) else null) else null;
        self.syncHudText();
        var buf: [160]u8 = undefined;
        const has_stats = live and meter != null and meter.?.last_ms != null;
        try setText(self, self.fps_gap_value, if (has_stats) try std.fmt.bufPrint(&buf, "{d} ms", .{meter.?.maxGap(now)}) else "— ms");
        try setText(self, self.fps_age_value, if (has_stats) try std.fmt.bufPrint(&buf, "{d} ms", .{now -| meter.?.last_ms.?}) else "— ms");
        // Keep the clock only while a shown readout can still change.
        const shown = self.show_fps.peek() and live;
        const menu_open = shown and self.open[@backingInt(Menu.display)].peek();
        const last_frame: ?u64 = blk: {
            const displayed = if (meter) |m| m.last_ms else null;
            const decoded = self.decoded_meter.last_ms;
            break :blk if (displayed != null and decoded != null) @max(displayed.?, decoded.?) else displayed orelse decoded;
        };
        // A one-second window needs ~1.1 s after the last frame to read 0; warm-up (null) ends by then too.
        const settling = shown and (if (last_frame) |at| now -| at < 1200 else false);
        self.performance_due_ms = if (menu_open or settling) now_f + 500 else null;
    }
    /// O2 text: one line with the resolution (full) or just the display rate (narrow picture).
    fn syncHudText(self: *View) void {
        const overlays = self.overlays orelse return;
        const width = if (self.viewport) |node| node.globalRect().w else 0;
        var buf: [128]u8 = undefined;
        overlays.setHudText(OM.hudText(&buf, OM.hudMode(width), self.width, self.height, self.display_fps, self.decode_fps));
    }
    fn fpsChanged(self: *View, enabled: bool) void {
        self.show_fps.set(enabled);
        if (self.snapshot) |snapshot| self.updatePerformance(snapshot.value) catch {};
        self.overlays_stale = true;
        self.mount_request.cx.requestRedraw();
    }
    fn presentFrame(self: *View, value: console.Snapshot) !void {
        if (self.mount_request.frame_sink) |sink| {
            if (!sink.owner.eql(self.mount_request.owner)) return error.StaleBinding;
            if (sink.texture == null or sink.frame_generation != value.frame_generation) {
                // A queue may cross its resize barrier after the console
                // snapshot was read. Hide the old presentation before emit;
                // the next owned snapshot will authorize the new generation.
                self.texture = null;
                if (self.image_node) |node| node.setImage(null);
                if (self.captured) self.releaseInput(.released);
            }
            if (sink.texture != null and sink.frame_generation == value.frame_generation and sink.frame_generation >= self.frame_generation and sink.revision >= self.frame_revision) {
                if (sink.texture != self.texture or sink.revision != self.frame_revision) {
                    self.texture = sink.texture;
                    self.frame_revision = sink.revision;
                    self.frame_generation = sink.frame_generation;
                    self.width = sink.width;
                    self.height = sink.height;
                    if (self.image_node) |node| {
                        node.setImage(.{ .texture_id = sink.texture.? });
                        node.markRenderDirty();
                    }
                    self.framesMoved();
                }
            }
        }
        const current_texture = self.texture != null and self.frame_generation == value.frame_generation;
        const title = vm.statusTitle(value, current_texture);
        const interrupted = current_texture and value.route != .closed and (value.route == .failed or value.video == .failed) and value.cleanup != .awaiting and value.cleanup != .unknown;
        // O4 "waiting for picture" (j8WXoF): a running power action or a lost signal after a
        // picture was shown. The old picture stays underneath; the connection card yields unless
        // it has something else to say (failure, cleanup, cancel).
        const no_signal = current_texture and value.rfb_ready and value.route == .connected and value.video == .awaiting_frame and value.cleanup == .not_started and value.progress.failure_code == null;
        const blocking = title.len != 0 and !no_signal;
        self.no_signal = no_signal;
        self.picture_waiting = (no_signal or self.powerRunning()) and !blocking;
        self.progress_shown = title.len != 0 and !self.picture_waiting;
        if (self.waiting) |node| {
            node.setDisplay(if (self.progress_shown) .flex else .none);
        }
        if (self.image_node) |node| node.setDisplay(if (current_texture and (title.len == 0 or interrupted or self.picture_waiting)) .flex else .none);
        if (self.viewport) |node| node.setBackground(ui.Color.BLACK);
        try setText(self, self.waiting_title, title);
    }
    fn projectProgress(self: *View, value: console.Snapshot) !void {
        const cx = self.mount_request.cx;
        const progress = value.progress;
        if (self.progress_attempt == null or !self.progress_attempt.?.eql(value.operation)) {
            self.progress_attempt = value.operation;
            self.progress_projection = .{};
            self.progress_disclosure = .{};
            self.progress_failure_scroll = null;
            self.progress_stage_scroll = null;
            self.progress_last_stage = null;
            self.log_revision = null;
        }
        self.progress_active = progress.revision != 0;
        // A real phase change follows the active work once. Timer/revision
        // updates within that phase leave the reader's scroll position alone.
        if (self.progress_active and self.progress_last_stage != progress.stage) {
            self.progress_last_stage = progress.stage;
            self.progress_stage_scroll = if (progress.stage != .streaming and progress.failure_code == null) if (vm.progressGroup(progress.stage)) |group| @intCast(@backingInt(group)) else null else null;
        }
        self.progress_projection.observe(progress);
        const previous_failures = self.progress_disclosure.auto_opened;
        self.progress_disclosure.observe(progress);
        const newly_failed = self.progress_disclosure.auto_opened & ~previous_failures;
        if (newly_failed != 0) {
            if (progress.failure_stage) |stage| {
                if (vm.progressGroup(stage)) |group| self.progress_failure_scroll = @intCast(@backingInt(group));
            } else {
                for (0..vm.progress_group_count) |index| {
                    if (newly_failed & (@as(u8, 1) << @intCast(index)) == 0) continue;
                    self.progress_failure_scroll = index;
                    break;
                }
            }
        }
        var writer: std.Io.Writer.Allocating = .init(cx.allocator);
        defer writer.deinit();
        if (self.progress_active) try vm.writeDuration(&writer.writer, progress.elapsed_ms) else try writer.writer.writeAll("—");
        try setText(self, self.progress_total_time, writer.written());
        writer.clearRetainingCapacity();
        const failure_code = progress.failure_code orelse value.failure_code;
        const overall_failed = failure_code != null or value.route == .failed or value.video == .failed;
        const overall_success = !overall_failed and (progress.stage == .streaming or value.video == .streaming);
        const overall_status: []const u8 = if (overall_failed) "连接失败" else if (progress.stage == .cancelled) "已取消" else if (value.cleanup == .released or value.route == .closed or value.video == .closed) "已结束" else if (self.cancel_pending) "取消中" else if (overall_success) "连接成功" else "连接中";
        try setText(self, self.progress_status, overall_status);
        if (self.progress_status) |node| setTextColorIfChanged(node, if (overall_failed) S.theme.current().danger_ink else if (overall_success) S.theme.current().ok_ink else S.progressSecondary());
        if (failure_code) |code| {
            try writer.writer.print("错误码：{s}", .{code});
        } else if (progress.waiting_for_user) {
            try writer.writer.writeAll(if (progress.stage == .waiting_certificate or progress.stage == .waiting_video_certificate) "等待你的操作 · 请完成证书确认" else "等待你的操作 · 请完成凭据输入");
        } else if (self.cancel_pending and progress.stage != .cancelled) {
            try writer.writer.writeAll("正在取消连接，等待本次资源释放");
        } else if (progress.stage == .cancelled) try writer.writer.writeAll("本次连接已取消，目标与路由配置已保留");
        try setText(self, self.progress_notice, writer.written());
        if (self.progress_notice) |node| node.setDisplay(if (writer.written().len == 0) .none else .flex);
        if (self.progress_notice) |node| setTextColorIfChanged(node, if (failure_code != null) S.theme.current().danger_ink else S.progressSecondary());
        writer.clearRetainingCapacity();
        if (failure_code != null and progress.failure_stage == null) {
            try writer.writer.print("{s}\n错误码：{s}", .{ vm.failureReason(failure_code, null), failure_code.? });
        } else if (progress.waiting_for_user) {
            try writer.writer.writeAll(if (progress.stage == .waiting_certificate or progress.stage == .waiting_video_certificate) "请完成证书确认，连接正在等待你的选择。" else "请完成凭据输入，连接正在等待你的操作。");
        } else if (self.cancel_pending and progress.stage != .cancelled) {
            try writer.writer.writeAll("已请求取消，正在释放本次连接。");
        } else if (progress.stage == .cancelled) {
            try writer.writer.writeAll("本次连接已取消，目标与路由配置已保留。");
        } else if (!self.progress_active) {
            try writer.writer.writeAll(if (value.video == .awaiting_frame) "连接仍保持；等待目标发送完整视频帧。" else value.route_summary);
        }
        try setText(self, self.waiting_detail, writer.written());
        if (self.waiting_detail) |node| node.setDisplay(if (writer.written().len == 0) .none else .flex);
        writer.clearRetainingCapacity();
        for (self.progress_icons, self.progress_names, self.progress_states, 0..) |icon, name, status, index| {
            const group: vm.ProgressGroup = @fromBackingInt(@intCast(index));
            const state = self.progress_projection.state(progress, group);
            try setText(self, icon, vm.stepPrefix(state));
            try setText(self, status, vm.stepLabel(state));
            writer.clearRetainingCapacity();
            if (vm.progressGroupDuration(progress, group)) |ms| try vm.writeDuration(&writer.writer, ms) else try writer.writer.writeAll("—");
            try setText(self, self.progress_durations[index], writer.written());
            writer.clearRetainingCapacity();
            const color = switch (state) {
                .current, .waiting_for_user => S.theme.current().accent_ink,
                .done => S.theme.current().fg_1,
                .warning, .stopped => S.theme.current().warn_ink,
                .failed => S.theme.current().danger_ink,
                .waiting => S.theme.current().fg_1,
            };
            if (icon) |node| setTextColorIfChanged(node, color);
            if (name) |node| setTextColorIfChanged(node, color);
            const current = state == .current or state == .waiting_for_user;
            if (status) |node| setTextColorIfChanged(node, if (current) color else S.progressSecondary());
            if (self.progress_durations[index]) |node| setTextColorIfChanged(node, if (current) color else S.progressSecondary());
            if (self.progress_rows[index]) |row| {
                const fill = if (current) S.progressCurrentFill() else ui.Color.TRANSPARENT;
                if (!std.meta.eql(row.getBackground(), fill)) row.setBackground(fill);
            }
            const expanded = self.progress_disclosure.isOpen(group);
            self.progress_expanded[index].set(expanded);
            if (self.progress_details[index]) |node| node.setDisplay(if (expanded) .flex else .none);
            try setText(self, self.progress_chevrons[index], if (expanded) "⌄" else "›");
            if (self.log_revision == null or self.log_revision.? != progress.revision) {
                writer.clearRetainingCapacity();
                try vm.writeStepDiagnosticsForTarget(&writer.writer, progress, group, value.target);
                try setText(self, self.progress_details[index], writer.written());
                writer.clearRetainingCapacity();
            }
            if (group == .route) {
                if (progress.route_hops == 0) {
                    try writer.writer.writeAll("建立直连通道");
                } else try writer.writer.print("建立独立 SSH 路由 · {d} 跳", .{progress.route_hops});
                try setText(self, name, writer.written());
                writer.clearRetainingCapacity();
            }
        }
        try setText(self, self.progress_route_text, if (value.route_summary.len != 0) value.route_summary else value.target);
        try setText(self, self.log_route_text, if (value.route_summary.len != 0) value.route_summary else value.target);
        const failed = value.route == .failed or value.video == .failed or failure_code != null;
        const terminal = failed or progress.stage == .cancelled or value.route == .closed or value.video == .closed or value.cleanup == .released;
        // The elapsed readouts are the only values here that move by themselves: while the card
        // is on screen and the attempt is still running, re-read at the precision they show
        // (tenths below a minute, whole seconds after).
        self.progress_running = self.progress_active and value.cleanup != .released and value.route != .closed and progress.stage != .streaming;
        self.progress_due_ms = if (self.progress_shown and self.progress_running) self.clock() + @as(f64, if (progress.elapsed_ms < 60_000) 100 else 1000) else null;
        if (self.retry_node) |node| node.setDisplay(if (failed or progress.stage == .cancelled) .flex else .none);
        self.retry_disabled.set(value.cleanup != .released);
        const service = self.borrowConsole() catch null;
        const cancel_available = if (service) |borrowed| borrowed.table.cancel != null else false;
        if (self.cancel_node) |node| node.setDisplay(if (!terminal and cancel_available) .flex else .none);
        self.cancel_disabled.set(self.cancel_pending or value.cleanup == .awaiting or value.cleanup == .unknown);
        if (self.log_revision == null or self.log_revision.? != progress.revision) {
            self.captureLogPosition();
            const entries = vm.connectionLogEvents(progress);
            self.log_count = entries.count;
            if (self.log_empty) |node| node.setDisplay(if (entries.count == 0) .flex else .none);
            for (self.log_rows, 0..) |maybe_row, index| {
                const row = maybe_row orelse continue;
                row.setDisplay(if (index < entries.count) .flex else .none);
                if (index >= entries.count) continue;
                const event = entries.events[index];
                self.log_sequences[index] = event.sequence;
                writer.clearRetainingCapacity();
                try vm.writeLogTimestamp(&writer.writer, event);
                try setText(self, self.log_timestamps[index], writer.written());
                writer.clearRetainingCapacity();
                try vm.writeLogMessage(&writer.writer, event, value.target);
                try setText(self, self.log_messages[index], writer.written());
                if (self.log_messages[index]) |message| setTextColorIfChanged(message, if (event.kind == .failure or event.error_code != null) S.theme.current().danger_ink else S.theme.current().fg_1);
                writer.clearRetainingCapacity();
                try vm.writeLogDuration(&writer.writer, event);
                try setText(self, self.log_durations[index], writer.written());
            }
            self.log_revision = progress.revision;
            self.log_layout_pending = true;
        }
    }
    /// The view's only per-frame entry, at the layout safety point. A frame in which nothing
    /// changed costs: the owner's change tokens (two compares), the frame sink's texture identity
    /// (the host's earlier hook uploads textures; reading it here, before display-list emission,
    /// means a resize cannot paint an ID the host has just retired), the layout key (this view's
    /// own boxes) and its armed deadlines. Everything else runs only for the change that asks for
    /// it. The view never schedules frames to keep itself polled: the owner's worker wakes the
    /// presentation when it publishes, and each on-screen clock arms its own deadline.
    fn afterLayout(raw: *anyopaque, _: u8, _: bool) ui.AfterLayoutResult {
        const self: *View = @ptrCast(@alignCast(raw));
        if (self.closed) return .done;
        const cx = self.mount_request.cx;
        // Remote input never outlives the window's focus or a layer above the picture.
        if ((self.captured or self.pending_capture) and (!cx.window_active or (self.captured and cx.overlay_stack.topmost() != null))) self.releaseInput(.lost_focus);
        var relayout = false;
        self.consumePulse() catch |err| {
            // A provider that cannot answer is re-read through the ordinary path (and reported once).
            if (self.seen != null) self.showFailure(err);
            self.seen = null;
        };
        const now: ?f64 = if (self.progress_due_ms != null or self.performance_due_ms != null or self.overlay_due_ms != null) self.clock() else null;
        if (now) |t| self.fireDeadlines(t);
        // Layout: this view's own boxes, the picture size and the theme.
        const key = self.layoutKey();
        const layout_changed = self.layout_key == null or !std.meta.eql(self.layout_key.?, key);
        if (layout_changed) {
            // Colours projected from the palette follow a theme change.
            if (self.layout_key == null or self.layout_key.?.theme != key.theme) self.stale = true;
            self.layout_key = key;
            self.overlays_stale = true;
        }
        if (self.management_stale) {
            self.management_stale = false;
            self.refreshManagement() catch |err| self.showFailure(err);
            relayout = true;
        }
        if (self.stale) {
            self.refresh() catch |err| self.showFailure(err);
            relayout = true;
        }
        if (self.snapshot) |snapshot| {
            const prior = .{ self.width, self.height, self.texture };
            self.presentFrame(snapshot.value) catch |err| self.showFailure(err);
            if (prior[0] != self.width or prior[1] != self.height or (prior[2] == null) != (self.texture == null)) {
                self.overlays_stale = true;
                relayout = true;
            }
        }
        self.stagePresentation();
        if (layout_changed or relayout) {
            self.updateGeometry();
            relayout = true;
        }
        // Follow the content of what is open (a few rect reads while it is open).
        if (self.progress_shown or self.anyMenu()) relayout = self.updatePopovers() or relayout;
        if (self.progress_failure_scroll != null or self.progress_stage_scroll != null) relayout = self.scrollToProgressStep() or relayout;
        relayout = self.updateLogLayout() or relayout;
        if (self.bounds_layout_pending) {
            self.bounds_layout_pending = false;
            relayout = true;
        }
        // O2: the pointer over the picture is the picture node's native hover (one source).
        const inside = cx.window_active and (if (self.picture_hovered) |hovered| hovered.peek() else false);
        if (inside != self.hud_inside) {
            self.hud_inside = inside;
            self.hud.pointer(inside, now orelse self.clock());
            self.overlays_stale = true;
        }
        if (self.overlays_stale) self.updateOverlays(now orelse self.clock());
        self.flushPointerWhenDue();
        if (self.pending_capture) {
            if (!self.anyMenu() and cx.overlay_stack.topmost() == null) {
                const requested = self.pending_capture_authority;
                self.pending_capture = false;
                self.pending_capture_authority = null;
                if (requested) |authority| self.beginCapture(authority);
            } else {
                // The menu that asked for capture is still closing: look again on the next frame.
                cx.requestRedraw();
            }
        }
        self.armDeadlines();
        if (!relayout) return .done;
        // Geometry was written from rects measured before this round's changes: one more frame
        // settles it (that frame finds nothing to do).
        cx.requestRedraw();
        return .needs_layout;
    }
    fn layoutKey(self: *View) LayoutKey {
        const cx = self.mount_request.cx;
        const zero: ui.ComputedRect = .{ .x = 0, .y = 0, .w = 0, .h = 0 };
        const waiting: [2]f32 = if (self.waiting) |node| .{ if (node.style.width == .px) node.style.width.px else -1, if (node.style.height == .px) node.style.height.px else -1 } else .{ 0, 0 };
        return .{
            .viewport = if (self.viewport) |node| node.globalRect() else zero,
            .card = if (self.video_card) |node| node.globalRect() else zero,
            .toolbar_width = if (self.toolbar) |node| node.globalRect().w else 0,
            .window = .{ cx.viewport.width, cx.viewport.height },
            .picture = if (self.texture != null) .{ self.width, self.height } else .{ 0, 0 },
            .mode = self.mode,
            .theme = cx.theme_version,
            .launcher = self.launcher,
            .status_shown = if (self.overlays) |o| o.status_shown.peek() else false,
            .waiting = waiting,
            .hud_height = if (self.overlays) |o| o.hudHeight() else 0,
            .alert_height = if (self.overlays) |o| o.waitingHeight() orelse 0 else 0,
            .scrollbar_y = if (self.scroll) |area| self.mode == .original and area.state.maxScrollY() > 0 else false,
            .tools_width = self.toolsWidth(),
        };
    }
    /// Tell the host which video revision this UI frame shows, until the host has counted it
    /// (it confirms only after a successful native frame submission). A hidden view stages nothing.
    fn stagePresentation(self: *View) void {
        const sink = self.mount_request.frame_sink orelse return;
        if (self.texture == null or self.texture != sink.texture or self.frame_generation != sink.frame_generation) return;
        if (sink.presentation.generation == sink.frame_generation and sink.presentation.revision >= sink.revision) return;
        if (self.root) |root| if (!root.isDisplayedInTree()) return;
        sink.presentation.stage(self.mount_request.cx.frame_count, sink.frame_generation, sink.revision);
    }
    /// Run what has come due. A clock whose readout is no longer on screen is dropped here and
    /// re-armed by the projection that shows it again.
    fn fireDeadlines(self: *View, now: f64) void {
        const displayed = if (self.root) |root| root.isDisplayedInTree() else false;
        if (self.progress_due_ms) |at| if (now >= at) {
            self.progress_due_ms = null;
            if (displayed and self.progress_shown) self.stale = true;
        };
        if (self.performance_due_ms) |at| if (now >= at) {
            self.performance_due_ms = null;
            if (displayed) if (self.snapshot) |snapshot| self.updatePerformance(snapshot.value) catch {};
        };
        if (self.overlay_due_ms) |at| if (now >= at) {
            self.overlay_due_ms = null;
            if (displayed) self.overlays_stale = true;
        };
    }
    /// One native timer serves the whole window and keeps only its earliest request, so pending
    /// deadlines are re-requested on every frame that leaves them pending.
    fn armDeadlines(self: *View) void {
        var next: ?f64 = null;
        for ([_]?f64{ self.progress_due_ms, self.performance_due_ms, self.overlay_due_ms }) |maybe| if (maybe) |at| {
            next = if (next) |value| @min(value, at) else at;
        };
        const at = next orelse return;
        const delay_ms = @max(1, at - self.clock());
        self.mount_request.cx.scheduleRedrawAfterNs(@as(u64, @intFromFloat(@ceil(delay_ms))) * std.time.ns_per_ms);
    }
    /// Geometry comes from this view's own boxes (viewport box, list box, rows) as laid out in
    /// this pass; the offset is written through the ScrollArea's controlled `scroll_y`, which
    /// applies it once the area has this frame's extents.
    fn scrollToProgressStep(self: *View) bool {
        const index = self.progress_failure_scroll orelse self.progress_stage_scroll orelse return false;
        const body = self.waiting_body orelse return false;
        const viewport = self.waiting_viewport orelse return false;
        const list = self.waiting_list orelse return false;
        const row = self.progress_rows[index] orelse return false;
        const view_height = viewport.globalRect().h;
        if (view_height <= 0 or row.globalRect().h <= 0) return false;
        const top = row.globalRect().y - list.globalRect().y;
        var height = row.globalRect().h;
        if (self.progress_details[index]) |detail| if (detail.style.display != .none) {
            // Show the step header and the beginning of its expanded detail;
            // a long diagnostic remains independently scrollable in the body.
            height += 4 + @min(detail.globalRect().h, 16 + 2 * 18.7);
        };
        height = @min(height, view_height);
        const before = body.state.scroll_y;
        const wanted: f32 = if (self.progress_failure_scroll != null or top < before) top else if (top + height > before + view_height) top + height - view_height else before;
        const target = std.math.clamp(wanted, 0, @max(0, list.globalRect().h - view_height));
        self.progress_scroll_y.set(target);
        self.progress_failure_scroll = null;
        self.progress_stage_scroll = null;
        return @abs(before - target) > 0.1;
    }
    fn captureLogPosition(self: *View) void {
        if (self.log_open == null or !self.log_open.?.peek()) return;
        const scroll = self.log_scroll orelse return;
        const list = self.log_list orelse return;
        self.log_follow_latest = scroll.state.scroll_y >= scroll.state.maxScrollY() - 1;
        self.log_anchor = null;
        if (self.log_follow_latest or self.log_count == 0) return;
        const content_top = list.globalRect().y;
        var visible: usize = 0;
        for (self.log_rows[0..self.log_count], 0..) |maybe_row, index| {
            const row = maybe_row orelse continue;
            if (row.globalRect().y - content_top <= scroll.state.scroll_y) visible = index;
        }
        const row = self.log_rows[visible] orelse return;
        const top = row.globalRect().y - content_top;
        self.log_anchor = .{ .sequence = self.log_sequences[visible], .inside = scroll.state.scroll_y - top, .fallback = scroll.state.scroll_y };
    }
    /// Reflow preserved row nodes at the layout safety point. The anchor is an
    /// event sequence plus the position within its row, so wrapping or ring
    /// eviction cannot replace the event the user was reading.
    fn updateLogLayout(self: *View) bool {
        const open = if (self.log_open) |signal| signal.peek() else false;
        const newly_open = open and !self.last_log_open;
        self.last_log_open = open;
        if (!open) return false;
        const detail = self.log_detail orelse return false;
        const scroll = self.log_scroll orelse return false;
        const viewport = self.log_viewport orelse return false;
        const list = self.log_list orelse return false;
        if (newly_open) {
            self.log_follow_latest = true;
            self.log_anchor = null;
        }
        if (!newly_open and !self.log_layout_pending) {
            if (!self.log_scroll_pending) return false;
            // This pass's extents, from this view's own boxes.
            const max = @max(0, list.globalRect().h - viewport.globalRect().h);
            var target = if (self.log_follow_latest) max else scroll.state.scroll_y;
            if (!self.log_follow_latest) if (self.log_anchor) |anchor| {
                target = anchor.fallback;
                for (self.log_sequences[0..self.log_count], 0..) |sequence, index| if (sequence == anchor.sequence) {
                    const row = self.log_rows[index] orelse continue;
                    target = row.globalRect().y - list.globalRect().y + anchor.inside;
                    break;
                };
            };
            self.log_scroll_y.set(std.math.clamp(target, 0, max));
            self.log_scroll_pending = false;
            self.log_anchor = null;
            return false;
        }
        for (self.log_messages[0..self.log_count]) |maybe_message| if (maybe_message) |message| {
            message.clearTextLayout();
            message.markSizingDirty();
        };
        detail.markSizingDirty();
        list.markSizingDirty();
        self.log_layout_pending = false;
        self.log_scroll_pending = true;
        return true;
    }
    fn updatePopovers(self: *View) bool {
        var changed = self.updateProgressBounds();
        for (self.menu_viewports, self.menu_bodies, 0..) |maybe_viewport, maybe_body, index| {
            if (!self.open[index].peek()) continue;
            const viewport = maybe_viewport orelse continue;
            const body = maybe_body orelse continue;
            const natural_height = body.globalRect().h;
            if (natural_height <= 0) continue;
            const header_height = if (index == @backingInt(Menu.display)) S.display_header_height else S.popup_header_height;
            // The panel takes the room its placement leaves (the native Popover sits below its trigger,
            // offset 8, 12 from the window edge, and flips above when the whole panel only fits there):
            // the header stays, the rows scroll in what remains.
            const cx = self.mount_request.cx;
            const room = blk: {
                const trigger = MenuAction.anchorRectOf(self, @fromBackingInt(@intCast(index))) orelse break :blk cx.viewport.height - 24;
                const below = cx.viewport.height - S.popup_viewport_padding - (trigger.y + trigger.h + S.popup_offset);
                const above = trigger.y - S.popup_offset - S.popup_viewport_padding;
                const whole = header_height + natural_height;
                break :blk if (whole <= below) below else if (whole <= above) above else @max(below, above);
            };
            const cap = @max(1, @min(room, S.popup_max_height) - header_height);
            changed = setHeight(cx, viewport, @max(1, @min(natural_height, cap))) or changed;
        }
        return changed;
    }
    fn updateProgressBounds(self: *View) bool {
        const cx = self.mount_request.cx;
        var changed = false;
        if (self.waiting) |waiting| if (self.waiting_viewport) |viewport| {
            const route_height = if (self.progress_route) |route| route.globalRect().h else 0;
            const actions_height = if (self.waiting_actions) |actions| actions.globalRect().h else 0;
            const body_height = @max(0, waiting.globalRect().h - S.progress_padding * 2 - S.progress_header_height - actions_height - S.progress_gap * 3 - route_height);
            changed = setHeight(cx, viewport, body_height) or changed;
            // Collapsing diagnostics can make the content shorter than the
            // viewport. Drop the old offset before it clips the first row.
            if (self.waiting_body) |body| if (self.waiting_list) |list| {
                const max = @max(0, list.globalRect().h - viewport.globalRect().h);
                if (body.state.scroll_y > max) {
                    self.progress_scroll_y.set(max);
                    changed = true;
                }
            };
        };
        if (self.log_modal) |modal| if (self.log_viewport) |viewport| {
            const compact = cx.viewport.height < 600;
            const width = @min(S.log_width, @max(1, cx.viewport.width - 32));
            const max_height = @max(1, cx.viewport.height - 32);
            // What zenit's Modal puts above the list (title bar) and this view's own rows above
            // it, as laid out while the dialog is open; the footer below it.
            var above = if (self.log_bounds) |old| old.above else 0;
            var footer_height = if (self.log_bounds) |old| old.footer else 0;
            if (self.log_open.?.peek() and viewport.globalRect().h > 0 and modal.dialog.globalRect().h > 0) {
                above = viewport.globalRect().y - modal.dialog.globalRect().y;
                if (self.log_footer) |footer| footer_height = footer.globalRect().h;
            }
            const bounds: LogBounds = .{ .width = width, .height = cx.viewport.height, .above = above, .footer = footer_height, .compact = compact, .theme = cx.theme_version };
            if (self.log_bounds) |old| if (std.meta.eql(old, bounds)) return changed;
            self.log_bounds = bounds;
            self.bounds_layout_pending = true;
            self.log_width.set(width);
            self.log_max_height.set(max_height);
            if (self.log_content) |content| content.setStyleInline(cx.allocator, S.logContent(compact));
            if (self.log_footer) |footer| footer.setStyleInline(cx.allocator, S.logFooter(compact));
            const cap = @max(1, max_height - above - S.logContentBottom(compact) - footer_height);
            const height = @min(if (compact) @as(f32, 200) else @as(f32, 320), cap);
            changed = setHeight(cx, viewport, height) or changed;
        };
        return changed;
    }
    fn refreshManagement(self: *View) !void {
        const call: services.Call = .{ .owner = self.mount_request.owner, .binding_generation = self.mount_request.owner.generation };
        if (self.management_operation) |operation| {
            if (try self.lookup(services.power_definition)) |binding| {
                const table = try binding.borrow(services.PowerService, services.power_key, self.mount_request.owner);
                const next = try table.result(binding.context, call, operation.key, self.mount_request.cx.allocator);
                if (operation.boot and next.value.phase == .succeeded and (if (self.management_result) |old| old.value.phase != .succeeded else true)) self.draft.initialized = false;
                if (self.management_result) |*old| old.deinit();
                self.management_result = next;
            }
        }
        if (try self.lookup(services.power_definition)) |binding| {
            const table = try binding.borrow(services.PowerService, services.power_key, self.mount_request.owner);
            const next = try table.snapshot(binding.context, call, self.mount_request.cx.allocator);
            if (self.power_snapshot) |*old| old.deinit();
            self.power_snapshot = next;
        }
        if (try self.lookup(services.boot_definition)) |binding| {
            const table = try binding.borrow(services.BootService, services.boot_key, self.mount_request.owner);
            var next = try table.snapshot(binding.context, call, self.mount_request.cx.allocator);
            errdefer next.deinit();
            try self.draft.refresh(next.value);
            if (self.boot_snapshot) |*old| old.deinit();
            self.boot_snapshot = next;
        }
        try self.projectManagement();
    }
    fn projectManagement(self: *View) !void {
        self.option_slot = 1 - self.option_slot;
        const slot = self.option_slot;
        const power_unmapped = if (self.power_snapshot) |snapshot| snapshot.value.system_uri.len != 0 and !snapshot.value.capability.system_mapping_verified else false;
        const boot_unmapped = if (self.boot_snapshot) |snapshot| snapshot.value.system_uri.len != 0 and !snapshot.value.capability.system_mapping_verified else false;
        const power_diagnostic = if (self.power_snapshot) |snapshot| snapshot.value.resource_evidence.validity == .partial_with_error else false;
        const boot_diagnostic = if (self.boot_snapshot) |snapshot| snapshot.value.resource_evidence.validity == .partial_with_error else false;
        if (self.power_mapping_warning) |node| node.setDisplay(if (power_unmapped or power_diagnostic) .flex else .none);
        if (self.boot_mapping_warning) |node| node.setDisplay(if (boot_unmapped or boot_diagnostic) .flex else .none);
        if (self.order_mapping_warning) |node| node.setDisplay(if (boot_unmapped or boot_diagnostic) .flex else .none);
        try setText(self, self.power_mapping_warning, if (power_unmapped) unverified_mapping_message else response_diagnostic_message);
        try setText(self, self.boot_mapping_warning, if (boot_unmapped) unverified_mapping_message else response_diagnostic_message);
        try setText(self, self.order_mapping_warning, if (boot_unmapped) unverified_mapping_message else response_diagnostic_message);
        try setText(self, self.power_scope_label, if (power_unmapped) "资源电源状态" else "当前电源");
        try setText(self, self.boot_scope_label, if (boot_unmapped) "资源启动覆盖" else "当前启动覆盖");
        var power_count: usize = 0;
        if (self.power_snapshot) |snapshot| {
            var state_buffer: [128]u8 = undefined;
            const label = vm.powerStateLabel(snapshot.value.state.value);
            try setText(self, self.power_label, if (snapshot.value.state.value != null and snapshot.value.state.evidence.validity != .valid) try std.fmt.bufPrint(&state_buffer, "{s}（部分结果）", .{label}) else label);
            for (power_actions, power_option_ids) |action, id| if (services.contains(snapshot.value.reset_types.value orelse &.{}, action.redfish())) {
                self.power_storage[slot][power_count] = .{ .value = action.redfish(), .label = vm.powerLabel(action), .test_id = id };
                power_count += 1;
            };
        }
        self.power_options.set(self.power_storage[slot][0..power_count]);
        const locked = self.managementLocked();
        const power_ready = if (self.power_snapshot) |snapshot| vm.writeAllowed(snapshot.value.capability) and snapshot.value.capability.secondary_auth == .disabled else false;
        // A session without write authority (neither granted nor requestable) is read-only
        // as a whole: the draft controls are disabled together with the execute button, so
        // nothing is edited that this session could not execute.
        self.power_disabled.set(locked or power_unmapped or power_count == 0 or !power_ready);
        self.power_execute_disabled.set(locked or !power_ready or (if (self.power_snapshot) |snapshot| !vm.powerAllowed(snapshot.value, self.power_choice) else true));
        var target_count: usize = 0;
        var mode_count: usize = 0;
        if (self.boot_snapshot) |snapshot| {
            const value = snapshot.value;
            const current = value.state;
            var buffer: [768]u8 = undefined;
            const partial = (current.enabled != null and value.enabled_evidence.validity != .valid) or (current.target != null and value.target_evidence.validity != .valid) or (current.mode != null and value.mode_evidence.validity != .valid);
            const text = if (services.optionalEqual(current.enabled, "Disabled")) (if (partial) "未覆盖（部分结果）" else "未覆盖") else try std.fmt.bufPrint(&buffer, "{s} · {s} · {s}{s}", .{ current.target orelse "未知设备", current.enabled orelse "未知有效期", current.mode orelse "未知模式", if (partial) "（部分结果）" else "" });
            try setText(self, self.boot_label, text);
            if (value.pending) |pending| {
                const pending_text = try std.fmt.bufPrint(&buffer, "待生效：{s} · {s} · {s}", .{ pending.target orelse "未知设备", pending.enabled orelse "未知有效期", pending.mode orelse "未知模式" });
                try setText(self, self.boot_pending_label, pending_text);
            }
            if (self.boot_pending_label) |node| node.setDisplay(if (value.pending != null) .flex else .none);
            for (target_values, target_names, target_option_ids) |target, name, id| {
                const allowed = if (std.mem.eql(u8, target, "Disabled")) services.contains(value.allowed_enabled.value orelse &.{}, "Disabled") else services.contains(value.allowed_targets.value orelse &.{}, target);
                if (!allowed) continue;
                self.target_storage[slot][target_count] = .{ .value = target, .label = name, .test_id = id };
                target_count += 1;
            }
            for (mode_values) |mode| if (services.contains(value.allowed_modes.value orelse &.{}, mode)) {
                self.mode_storage[slot][mode_count] = .{ .value = mode, .label = mode, .test_id = if (std.mem.eql(u8, mode, "UEFI")) "bmc.boot.mode_option.uefi" else "bmc.boot.mode_option.legacy" };
                mode_count += 1;
            };
            try self.refreshOrder(value.boot_order.value);
        }
        self.boot_options.set(self.target_storage[slot][0..target_count]);
        self.mode_options.set(self.mode_storage[slot][0..mode_count]);
        const boot_ready = if (self.boot_snapshot) |snapshot| vm.writeAllowed(snapshot.value.capability) and snapshot.value.capability.secondary_auth == .disabled else false;
        // Read-only session: the Boot draft (target, mode, 持续生效) is read-only like 执行.
        self.boot_disabled.set(locked or boot_unmapped or target_count == 0 or !boot_ready);
        self.mode_disabled.set(locked or boot_unmapped or mode_count == 0 or !boot_ready);
        self.boot_execute_disabled.set(locked or !boot_ready or (if (self.boot_snapshot) |snapshot| !self.draft.canApply(snapshot.value) else true));
        const enabled_ready = if (self.boot_snapshot) |snapshot| snapshot.value.enabled_evidence.permitsWrite() and snapshot.value.allowed_enabled.evidence.permitsWrite() else false;
        self.switch_disabled.set(locked or boot_unmapped or !boot_ready or !enabled_ready or self.draft.disabled());
        self.target_value.set(if (self.draft.disabled()) "Disabled" else canonicalTarget(self.draft.value.target.get()));
        self.mode_value.set(canonicalMode(self.draft.value.mode.get()));
        self.boot_continuous.set(self.draft.continuous());
        if (self.boot_details) |node| node.setDisplay(if (!self.draft.initialized or self.draft.disabled()) .none else .flex);
        if (self.mode_row) |node| node.setDisplay(if (mode_count > 0) .flex else .none);
        const result = if (self.management_result) |value| value.value else null;
        const operation = self.management_operation;
        const unknown = if (result) |value| value.phase == .outcome_unknown else false;
        const running = if (result) |value| !value.terminal() else false;
        if (self.power_query) |node| node.setDisplay(if (unknown and operation != null and !operation.?.boot) .flex else .none);
        if (self.boot_query) |node| node.setDisplay(if (unknown and operation != null and operation.?.boot) .flex else .none);
        if (self.power_cancel) |node| node.setDisplay(if (running and operation != null and !operation.?.boot) .flex else .none);
        if (self.boot_cancel) |node| node.setDisplay(if (running and operation != null and operation.?.boot) .flex else .none);
        const power_reason = if (self.power_snapshot) |snapshot| vm.powerUnavailableReason(snapshot.value, self.power_choice) else @as(?[]const u8, "管理通道当前不可用。");
        const power_hint = if (result != null and operation != null and !operation.?.boot) vm.resultLabel(result.?) else if (power_reason) |reason| reason else if (self.power_choice == .force_off or self.power_choice == .force_restart or self.power_choice == .power_cycle) "强制动作可能造成数据丢失；点击执行后核对并批准本次操作。" else "选择不会执行；点击执行后核对并批准本次操作。";
        try setText(self, self.power_hint, power_hint);
        const boot_reason = if (self.boot_snapshot) |snapshot| self.draft.unavailableReason(snapshot.value) else @as(?[]const u8, "管理通道当前不可用。");
        try setText(self, self.boot_hint, if (result != null and operation != null and operation.?.boot) vm.resultLabel(result.?) else if (boot_unmapped) "仅查看该管理资源的启动覆盖与顺序，不会写入或重启。" else if (boot_reason) |reason| reason else "仅设置启动覆盖，不会自动重启。USB / 光驱指目标机已有设备，不提供镜像挂载。");
        // A running power action drives O1 / O4, and an unverified mapping the connection indicator.
        self.syncConnectionIndicator();
        self.overlays_stale = true;
        self.mount_request.cx.requestRedraw();
    }
    fn updateGeometry(self: *View) void {
        const alloc = self.mount_request.cx.allocator;
        const viewport = self.viewport orelse return;
        const rect = viewport.globalRect();
        const area = self.scroll orelse return;
        const canvas = self.canvas orelse return;
        const g = self.geometry();
        if (g) |geometry_value| {
            const dw = geometry_value.image.width;
            const dh = geometry_value.image.height;
            canvas.setStyleInline(alloc, S.canvas(@max(rect.w, dw), @max(rect.h, dh)));
            if (self.image_node) |node| node.setStyleInline(alloc, .{ .width = .{ .px = dw }, .height = .{ .px = dh }, .position = .absolute, .inset = .{ .left = .{ .px = @max(0, (rect.w - dw) / 2) }, .top = .{ .px = @max(0, (rect.h - dh) / 2) } } });
            if (self.mode == .fit) {
                // Nothing to scroll in fit mode: back to the origin through the ScrollArea's own setters.
                ui.widgets.scroll_area.setScrollX(area.state, area.content, 0);
                ui.widgets.scroll_area.setScrollY(area.state, area.content, 0);
            }
        } else canvas.setStyleInline(alloc, S.canvas(@max(1, rect.w), @max(1, rect.h)));
        if (self.waiting) |node| {
            // O4 (j8WXoF D): bottom-corner icon -> height cap - 80; top-corner icon -> below it
            // when the card reaches into the icon column.
            const card = OM.centerCard(.{ .x = rect.x, .y = rect.y, .w = rect.w, .h = rect.h }, S.progress_width, S.progress_height, null, self.launcher);
            const width = card.w;
            const height = card.h;
            const bounds: WaitingBounds = .{ .width = rect.w, .height = rect.h, .theme = self.mount_request.cx.theme_version, .launcher = self.launcher };
            // setTheme invokes the root's before-render hook before replaying
            // descendant recipes. That replay can restore the recipe's base
            // height after this cache was filled; repair only that mismatch.
            const size_changed = node.style.width != .px or @abs(node.style.width.px - width) > 0.1 or node.style.height != .px or @abs(node.style.height.px - height) > 0.1;
            if (self.waiting_bounds == null or !std.meta.eql(self.waiting_bounds.?, bounds) or size_changed) {
                self.waiting_bounds = bounds;
                node.setStyleInline(alloc, .{ .width = .{ .px = width }, .height = .{ .px = height }, .inset = .{ .left = .{ .px = card.x - rect.x }, .top = .{ .px = card.y - rect.y } } });
                self.bounds_layout_pending = true;
            }
        }
        if (self.toolbar != null) {
            const width = self.toolbar.?.globalRect().w;
            // The native controls' widths are zenit's: record them as laid out in the current
            // mode and fold when the toolbar cannot hold them (never assume a control's size).
            const tools = self.toolsWidth();
            if (tools > 0) {
                if (self.last_compact == false) self.tools_labelled_width = tools;
                if (self.last_compact == true and !self.last_overflow) self.tools_icon_width = tools;
            }
            // j8WXoF O1: while the status slot is up the menus fold earlier, never under it.
            const reserve: f32 = if (self.overlays) |o| (if (o.status_shown.peek()) S.status_reserve_width else 0) else 0;
            // Not measured yet: show the labelled toolbar (then the icon toolbar) once to measure it.
            const compact = if (self.tools_labelled_width) |need| width < S.toolbar_labelled_reserve + need + reserve else false;
            const overflow = compact and (if (self.tools_icon_width) |need| width < S.toolbar_icon_reserve + need + reserve else false);
            const themed = self.theme_watch.take();
            if (self.last_compact == null or self.last_compact.? != compact or self.last_overflow != overflow or themed) {
                if (self.last_compact != null and (self.last_compact.? != compact or self.last_overflow != overflow)) self.closeMenus();
                self.last_compact = compact;
                self.last_overflow = overflow;
                if (self.connection_icon) |icon| _ = icon.setTint(S.theme.current().accent);
                for (self.tool_labels, menu_names) |source, name| source.set(if (compact) "" else name);
                self.tool_icon_only.set(compact);
                self.tool_chevron.set(!compact);
                for (self.tool_slots[@backingInt(Menu.power)..]) |maybe| if (maybe) |slot| slot.setDisplay(if (overflow) .none else .flex);
                if (self.more_slot) |slot| slot.setDisplay(if (overflow) .flex else .none);
                self.disconnect_icon_only.set(compact);
                self.syncConnectionIndicator();
                self.overlays_stale = true;
                self.bounds_layout_pending = true;
            }
        }
    }
    /// Laid-out width of the toolbar's native controls (disconnect + the shown menus), gaps included.
    fn toolsWidth(self: *View) f32 {
        var total: f32 = 0;
        var count: f32 = 0;
        if (self.disconnect_slot) |slot| {
            const w = slot.globalRect().w;
            if (w <= 0) return 0;
            total += w;
            count += 1;
        }
        for (self.tool_slots) |maybe| if (maybe) |slot| {
            if (slot.style.display == .none) continue;
            const w = slot.globalRect().w;
            if (w <= 0) return 0;
            total += w;
            count += 1;
        };
        return total + S.toolbar_gap * @max(0, count - 1);
    }
    fn update(raw: *anyopaque, value: contract.ContentUpdate) !void {
        const self: *View = @ptrCast(@alignCast(raw));
        if (self.closed or !value.owner.eql(self.mount_request.owner)) return error.StaleBinding;
        // The host says the content changed: re-read everything now rather than on the next frame.
        self.management_stale = false;
        try self.refreshManagement();
        try self.refresh();
    }
    fn connectionStatus(raw: *anyopaque) contract.ConnectionStatus {
        const self: *View = @ptrCast(@alignCast(raw));
        return self.connectionState();
    }
    fn rectOf(r: ui.ComputedRect) contract.LauncherRect {
        return .{ .x = r.x, .y = r.y, .w = r.w, .h = r.h };
    }
    /// The card's side of the AI launcher (j8WXoF D): bounds, toolbar bottom (top anchor =
    /// toolbar + 12) and the captured picture (the launcher yields over it).
    fn launcherContext(raw: *anyopaque) contract.LauncherContext {
        const self: *View = @ptrCast(@alignCast(raw));
        if (self.closed) return .{};
        const root = self.root orelse return .{};
        if (!root.isDisplayedInTree()) return .{};
        const r = root.globalRect();
        if (r.w <= 0 or r.h <= 0) return .{};
        const bar = if (self.toolbar) |node| node.globalRect() else r;
        return .{
            .bounds = rectOf(r),
            .top_chrome_bottom = if (self.toolbar != null) bar.y + bar.h else null,
            .captured = if (self.captured) if (self.viewport) |vp| rectOf(vp.globalRect()) else null else null,
        };
    }
    /// The launcher rests in this card's corner (or not); the card's overlays give way to it.
    fn placeLauncher(raw: *anyopaque, placement: ?contract.LauncherPlacement) void {
        const self: *View = @ptrCast(@alignCast(raw));
        if (self.closed or std.meta.eql(self.launcher, placement)) return;
        self.launcher = placement;
        self.overlays_stale = true;
        self.mount_request.cx.requestRedraw();
    }
    fn powerRunning(self: *const View) bool {
        const operation = self.management_operation orelse return false;
        if (operation.boot) return false;
        const result = self.management_result orelse return false;
        return OM.powerRunning(result.value.phase);
    }
    /// One pass over the card overlays (O1–O5) from the controller snapshot and picture geometry.
    /// Runs when one of its inputs changed (`overlays_stale`) or one of its clocks came due; `now`
    /// is monotonic wall-clock ms. Leaves `overlay_due_ms` at the next moment it must run again.
    fn updateOverlays(self: *View, now: f64) void {
        self.overlays_stale = false;
        self.overlay_due_ms = null;
        const overlays = self.overlays orelse return;
        const card_node = self.video_card orelse return;
        const vp_node = self.viewport orelse return;
        const cr = card_node.globalRect();
        const vr = vp_node.globalRect();
        const card: OM.Rect = rectOf(cr);
        const vp: OM.Rect = rectOf(vr);
        const value: ?console.Snapshot = if (self.snapshot) |owned| owned.value else null;
        // O1
        const power = self.powerRunning();
        if (power) {
            if (self.power_started_ms == null or now < self.power_started_ms.?) self.power_started_ms = now;
        } else self.power_started_ms = null;
        const elapsed_s: u64 = if (self.power_started_ms) |start| @intFromFloat(@max(0, (now - start) / 1000)) else 0;
        const ai: OM.AiActivity = if (value) |v| switch (v.ai) {
            .none => .none,
            .observing => .observing,
            .operating => .operating,
        } else .none;
        const status = OM.status(power, ai, self.captured);
        var label: [96]u8 = undefined;
        overlays.setStatus(status, OM.statusLabel(&label, status, self.last_compact orelse false, self.power_action, elapsed_s));
        // The power readouts (O1 tag, O4 message) count whole seconds: next run at the next second.
        if (power) self.dueAt(self.power_started_ms.? + @as(f64, @floatFromInt(elapsed_s + 1)) * 1000);
        // O5
        overlays.setAiFrame(ai == .operating, cr.w, cr.h);
        // O4 waiting for picture
        if (self.picture_waiting) {
            const box = OM.centerCard(vp, S.progress_width, S.progress_height, overlays.waitingHeight() orelse 96, self.launcher);
            var title: [128]u8 = undefined;
            var message: [256]u8 = undefined;
            const verb = OM.powerVerb(self.power_action orelse .graceful_restart);
            const t = if (power) std.fmt.bufPrint(&title, "主机正在{s}，等待视频信号", .{verb}) catch "等待视频信号" else "等待视频信号";
            const m = if (power) std.fmt.bufPrint(&message, "已向 BMC 提交「{s}」，已 {d} s。画面恢复后自动继续。", .{ vm.powerLabel(self.power_action orelse .graceful_restart), elapsed_s }) catch "" else "视频通道仍连接，远端暂未输出新画面；恢复后自动继续。";
            overlays.setWaiting(true, box.x - cr.x, box.y - cr.y, box.w, t, m);
        } else overlays.setWaiting(false, 0, 0, 0, "", "");
        // O2
        const live = if (value) |v| v.video == .streaming and self.texture != null else false;
        self.hud.due(now);
        if (self.hud.deadline()) |at| self.dueAt(at);
        const faded = self.hud.faded();
        const scrollbar_y = if (self.scroll) |area| self.mode == .original and area.state.maxScrollY() > 0 else false;
        const insets = OM.hudInsets(card, vp, self.launcher, overlays.hudHeight(), scrollbar_y);
        self.syncHudText();
        overlays.setHud(self.show_fps.peek() and live and !self.captured and !self.progress_shown and !self.picture_waiting and OM.hudMode(vr.w) != .hidden, insets.right, insets.top, faded);
        // O3
        const band = OM.hintBand(card, vp);
        overlays.setHint(if (self.hint.visible(now)) self.hint.slice() else null, band.left, band.width, band.bottom, now);
        if (self.hint.deadline()) |at| self.dueAt(at);
        if (overlays.hintDeadline()) |at| self.dueAt(at);
    }
    fn dueAt(self: *View, at: f64) void {
        self.overlay_due_ms = if (self.overlay_due_ms) |current| @min(current, at) else at;
    }
    fn takeover(self: *View) void {
        // Host stop / takeover is always callable: it revokes the AI lease and cancels queued
        // automation input. Without the typed AI service, take the content lease back directly.
        if (self.lookup(ai_control.definition) catch null) |binding| {
            if (binding.borrow(ai_control.Interface, ai_control.key, self.mount_request.owner)) |table| {
                table.stop(binding.context, binding) catch |err| self.showFailure(err);
                return;
            } else |_| {}
        }
        if (self.mount_request.content_context) |context| context.takeHumanControl();
    }
    fn showConnectionDetails(raw: *anyopaque) void {
        const self: *View = @ptrCast(@alignCast(raw));
        self.showLog();
    }
    fn syncConnectionIndicator(self: *View) void {
        const status = self.connectionState();
        // Hover is the button's native hover and nothing else (zenit re-resolves hover under a
        // resting pointer when the scene changes; no geometry test here).
        const hovered = if (self.connection_hovered) |signal| signal.peek() else false;
        const focused = if (self.connection_focused) |signal| signal.peek() else false;
        const hot = (hovered or focused) and !self.disconnect_disabled.peek();
        const asset: ui.SvgAsset = if (hot) ui.icons.unplug else switch (status.state) {
            .connecting => ui.icons.loader_circle,
            .online => ui.icons.circle_check,
            .degraded => ui.icons.circle_x,
            .ended => ui.icons.unplug,
        };
        const color = if (hot) S.theme.current().danger else switch (status.state) {
            .connecting => S.theme.current().accent_ink,
            .online => S.theme.current().ok,
            .degraded => S.theme.current().danger,
            .ended => S.theme.current().fg_2,
        };
        if (self.connection_symbol.peek() == null or self.connection_symbol.peek().?.icon_id != asset.icon_id) self.connection_symbol.set(asset);
        if (self.connection_tint.peek() == null or !std.meta.eql(self.connection_tint.peek().?, color)) self.connection_tint.set(color);
        const hint = if (hot) (if (status.state == .connecting) "取消连接" else "断开连接") else if (status.state == .online) "已连接" else status.label;
        if (!std.mem.eql(u8, self.connection_hint.peek(), hint)) self.connection_hint.set(hint);
        const label = if (self.last_compact orelse false) "" else if (hot) hint else switch (status.state) {
            .connecting => "连接中",
            .online => "已连接",
            .degraded => "连接失败",
            .ended => "已断开",
        };
        if (!std.mem.eql(u8, self.connection_label.peek(), label)) self.connection_label.set(label);
    }
    fn connectionState(self: *View) contract.ConnectionStatus {
        if (self.closed) return .{ .state = .ended, .label = "已结束" };
        const snapshot = self.snapshot orelse return .{ .state = .connecting, .label = "正在准备连接" };
        const value = snapshot.value;
        if (self.cancel_pending) return if (value.cleanup == .released) .{ .state = .ended, .label = "已断开" } else if (value.cleanup == .unknown) .{ .state = .degraded, .label = "清理结果待确认" } else .{ .state = .connecting, .label = "断开中" };
        if (value.cleanup == .unknown) return .{ .state = .degraded, .label = "清理结果待确认" };
        if (value.cleanup == .awaiting) return .{ .state = .connecting, .label = "正在释放连接" };
        if (value.progress.stage == .cancelled) return .{ .state = .ended, .label = "连接已取消" };
        if (value.progress.failure_code != null) return .{ .state = .degraded, .label = "连接失败" };
        if (value.route == .closed or value.video == .closed) return .{ .state = .ended, .label = "已结束" };
        if (value.route == .failed or value.video == .failed) return .{ .state = .degraded, .label = if (self.texture != null) "视频已中断" else "连接失败" };
        if (value.cleanup == .released) return .{ .state = .ended, .label = "已结束" };
        if (value.video == .streaming) {
            const power_unmapped = if (self.power_snapshot) |resource| resource.value.system_uri.len != 0 and !resource.value.capability.system_mapping_verified else false;
            const boot_unmapped = if (self.boot_snapshot) |resource| resource.value.system_uri.len != 0 and !resource.value.capability.system_mapping_verified else false;
            if (self.texture != null and self.frame_generation == value.frame_generation and (power_unmapped or boot_unmapped)) return .{ .state = .degraded, .label = "视频已连接 · 管理条件待核实" };
            return .{ .state = .online, .label = if (value.management == .unavailable) "视频已连接 · 管理不可用" else "视频已连接" };
        }
        return .{ .state = .connecting, .label = if (value.progress.revision != 0) console.progress.stageLabel(value.progress.stage) else switch (value.video) {
            .authenticating => "正在验证视频会话",
            .negotiating => "正在协商视频通道",
            .awaiting_frame => "正在等待视频帧",
            else => "正在建立独立连接",
        } };
    }
    fn focus(raw: *anyopaque, focused: bool) void {
        const self: *View = @ptrCast(@alignCast(raw));
        if (self.closed) return;
        self.window_focused = focused;
        if (!focused) {
            self.closeMenus();
            self.releaseInput(.lost_focus);
        }
        // Also the moment a hidden view may be shown again: project afresh and re-arm its clocks.
        self.invalidate();
    }
    fn unmount(raw: *anyopaque) void {
        const self: *View = @ptrCast(@alignCast(raw));
        self.release();
    }
    /// Tell the owner which window shows this session (0 = none): its worker wakes that window.
    fn bindPresentation(self: *View, shown: bool) void {
        const target = @import("../../platform/presentation_wakeup.zig").targetForWindow(@intFromPtr(self.mount_request.cx));
        // An unregistered window has no target of its own: leave the owner on "every window".
        if (target == 0) return;
        const service = self.borrowConsole() catch return;
        const bind = service.table.bind_presentation orelse return;
        bind(service.binding.context, service.binding, target, shown) catch {};
    }
    fn release(self: *View) void {
        if (self.closed) return;
        self.bindPresentation(false);
        self.closeMenus();
        self.releaseInput(.closed);
        if (self.after_layout_registered) self.mount_request.cx.removeAfterLayoutHook(self);
        self.after_layout_registered = false;
        self.closed = true;
        if (self.snapshot) |*value| value.deinit();
        if (self.power_snapshot) |*value| value.deinit();
        if (self.boot_snapshot) |*value| value.deinit();
        if (self.management_result) |*value| value.deinit();
        self.snapshot = null;
        self.power_snapshot = null;
        self.boot_snapshot = null;
        self.management_result = null;
        self.management_operation = null;
        self.power_query = null;
        self.boot_query = null;
        self.power_cancel = null;
        self.boot_cancel = null;
        // GPU texture, content/window facade and protocol producer remain host
        // owned. Unmount releases presentation references and never joins IO.
        self.root = null;
        self.toolbar = null;
        self.more = null;
        self.more_node = null;
        self.connection_icon = null;
        self.connection_identity = null;
        self.tool_slots = @splat(null);
        self.disconnect_slot = null;
        self.more_slot = null;
        self.canvas = null;
        self.connection_title = null;
        self.connection_hovered = null;
        self.connection_focused = null;
        self.disconnect_node = null;
        self.disconnect_confirm_dialog = null;
        self.disconnect_confirm_target = null;
        self.disconnect_confirm_detail = null;
        self.disconnect_confirm_return = null;
        self.viewport = null;
        self.scroll = null;
        self.image_node = null;
        self.waiting = null;
        self.waiting_header = null;
        self.waiting_title = null;
        self.waiting_detail = null;
        self.waiting_body = null;
        self.waiting_viewport = null;
        self.waiting_list = null;
        self.waiting_actions = null;
        self.progress_timing = null;
        self.progress_durations = @splat(null);
        self.progress_total_time = null;
        self.progress_status = null;
        self.progress_notice = null;
        self.progress_steps = null;
        self.progress_rows = @splat(null);
        self.progress_details = @splat(null);
        self.progress_chevrons = @splat(null);
        self.progress_icons = @splat(null);
        self.progress_names = @splat(null);
        self.progress_states = @splat(null);
        self.progress_route = null;
        self.progress_route_text = null;
        self.cancel_node = null;
        self.retry_node = null;
        self.log_open = null;
        self.log_modal = null;
        self.log_footer = null;
        self.log_content = null;
        self.log_list = null;
        self.log_viewport = null;
        self.log_scroll = null;
        self.log_detail = null;
        self.log_empty = null;
        self.log_rows = @splat(null);
        self.log_timestamps = @splat(null);
        self.log_messages = @splat(null);
        self.log_durations = @splat(null);
        self.log_route_text = null;
        self.control_label = null;
        self.control_request_row = null;
        self.power_label = null;
        self.power_scope_label = null;
        self.power_mapping_warning = null;
        self.power_hint = null;
        self.boot_label = null;
        self.boot_scope_label = null;
        self.boot_mapping_warning = null;
        self.boot_pending_label = null;
        self.boot_hint = null;
        self.boot_details = null;
        self.mode_row = null;
        self.order_rows = null;
        self.order_nodes = @splat(null);
        self.order_node_count = 0;
        self.order_mapping_warning = null;
        self.order_open = null;
        self.order_modal = null;
        self.order_scroll = null;
        self.order_viewport = null;
        self.original_hint = null;
        self.message = null;
        self.overlays = null;
        self.video_card = null;
        self.launcher = null;
        self.fps_detail = null;
        self.fps_gap_value = null;
        self.fps_age_value = null;
        self.menus = @splat(null);
        self.menu_viewports = @splat(null);
        self.menu_bodies = @splat(null);
        self.menu_scrolls = @splat(null);
        self.tool_nodes = @splat(null);
        self.picture_hovered = null;
        self.layout_key = null;
    }
    fn requestControl(self: *View) void {
        self.releaseInput(.released);
        const service = self.borrowConsole() catch return;
        service.table.request_control(service.binding.context, service.binding) catch |err| self.showFailure(err);
        self.watch_only_selected = false;
        self.invalidate();
    }
    fn capture(self: *View) void {
        self.closeMenus();
        self.watch_only_selected = false;
        const binding = (self.lookup(input.definition) catch null) orelse return;
        const table = binding.borrow(input.Interface, input.key, self.mount_request.owner) catch return;
        const snapshot = table.snapshot(binding.context, binding) catch return;
        // Popover exit is asynchronous. Keep the user's click tied to the
        // visible attempt instead of silently recapturing a later connection.
        self.pending_capture_authority = .{ .binding_generation = binding.generation, .input_epoch = snapshot.input_epoch, .control_generation = snapshot.control_generation, .transport_generation = snapshot.transport_generation, .frame_generation = self.frame_generation };
        self.pending_capture = true;
        self.invalidate();
    }
    fn releaseCapture(self: *View) void {
        self.releaseInput(.released);
        if (self.mount_request.cx.focus_manager.getFocused() == self.viewport) self.mount_request.cx.focus_manager.clearFocus();
    }
    fn onlyView(self: *View) void {
        self.releaseInput(.released);
        self.view_only = true;
        self.watch_only_selected = true;
        self.closeMenus();
        self.invalidate();
    }
    fn fit(self: *View) void {
        self.setMode(.fit);
    }
    fn original(self: *View) void {
        self.setMode(.original);
    }
    fn scaleChanged(self: *View, id: []const u8) void {
        self.setMode(std.meta.stringToEnum(mapping.Mode, id) orelse return);
    }
    fn setMode(self: *View, mode: mapping.Mode) void {
        self.releaseInput(.released);
        self.mode = mode;
        self.scale_value.set(@tagName(mode));
        if (self.original_hint) |node| node.setDisplay(if (mode == .original) .flex else .none);
        self.invalidate();
    }
    fn fullscreen(self: *View) void {
        self.releaseInput(.released);
        const context = self.mount_request.content_context orelse return;
        context.requestFullscreen(!context.fullscreen()) catch |err| self.showFailure(err);
    }
    fn refreshVideo(self: *View) void {
        self.releaseInput(.released);
        const service = self.borrowConsole() catch return;
        service.table.refresh(service.binding.context, service.binding) catch |err| self.showFailure(err);
        self.invalidate();
    }
    fn retry(self: *View) void {
        self.releaseInput(.released);
        const service = self.borrowConsole() catch return;
        service.table.retry(service.binding.context, service.binding) catch |err| self.showFailure(err);
        self.invalidate();
    }
    fn disconnectConnection(self: *View) void {
        if (self.closed or self.disconnect_disabled.peek() or self.disconnect_confirm_open.peek()) return;
        const connecting = self.connectionState().state == .connecting;
        self.disconnect_confirm_title.set(if (connecting) "取消连接？" else "断开连接？");
        // 动词 + 对象 (shared/ui/confirm).
        self.disconnect_confirm_action.set(if (connecting) "停止连接" else "断开连接");
        setText(self, self.disconnect_confirm_target, if (self.connection_title) |node| node.getText().?.content else "KVM 控制台") catch return;
        self.disconnect_confirm_message.set(if (connecting) "将取消当前 KVM 连接尝试。" else "将结束当前 KVM 会话并释放键盘鼠标，主机将继续运行。");
        self.releaseInput(.released);
        self.closeMenus();
        // Focus lands on 取消 (the confirmation's autoFocus target).
        self.disconnect_confirm_open.set(true);
        self.mount_request.cx.requestRedraw();
    }
    fn dismissDisconnect(self: *View) void {
        self.disconnect_confirm_open.set(false);
    }
    fn confirmDisconnect(self: *View) void {
        if (self.closed or !self.disconnect_confirm_open.peek()) return;
        self.disconnect_confirm_open.set(false);
        if (!self.disconnect_disabled.peek()) self.cancel();
    }
    fn cancel(self: *View) void {
        if (self.closed or self.cancel_pending) return;
        self.releaseInput(.released);
        const service = self.borrowConsole() catch return;
        const callback = service.table.cancel orelse return;
        callback(service.binding.context, service.binding) catch |err| {
            self.showFailure(err);
            return;
        };
        self.cancel_pending = true;
        self.cancel_disabled.set(true);
        self.disconnect_disabled.set(true);
        self.closeMenus();
        self.invalidate();
    }
    fn showLog(self: *View) void {
        if (self.closed) return;
        self.releaseInput(.released);
        self.closeMenus();
        if (self.log_open) |open| open.set(true);
        if (self.log_viewport) |node| self.mount_request.cx.focus_manager.setFocus(node);
        self.mount_request.cx.requestRedraw();
    }
    fn closeLog(self: *View) void {
        if (self.log_open) |open| open.set(false);
    }
    fn progressKey(event: ui.events.Event, raw: ?*anyopaque) ui.events.EventResult {
        const self: *View = @ptrCast(@alignCast(raw orelse return .ignored));
        if (self.closed) return .ignored;
        return scrollKey(self.waiting_body orelse return .ignored, event);
    }
    fn logKey(event: ui.events.Event, raw: ?*anyopaque) ui.events.EventResult {
        const self: *View = @ptrCast(@alignCast(raw orelse return .ignored));
        if (self.closed) return .ignored;
        return scrollKey(self.log_scroll orelse return .ignored, event);
    }
    fn powerChanged(self: *View, selected: ?[]const u8) void {
        const value = selected orelse return;
        for (power_actions) |action| if (std.mem.eql(u8, value, action.redfish())) {
            self.power_choice = action;
            break;
        };
        self.projectManagement() catch {};
    }
    fn targetChanged(self: *View, selected: ?[]const u8) void {
        const value = selected orelse return;
        self.draft.selectTarget(value) catch return;
        self.projectManagement() catch {};
    }
    fn modeChanged(self: *View, selected: ?[]const u8) void {
        self.draft.selectMode(selected orelse return) catch {};
        self.projectManagement() catch {};
    }
    fn continuousChanged(self: *View, value: bool) void {
        self.draft.setContinuous(value) catch {};
        self.projectManagement() catch {};
    }
    fn managementLocked(self: *const View) bool {
        return if (self.management_result) |value| !value.value.terminal() or value.value.phase == .outcome_unknown else false;
    }
    fn execution(self: *View, capability: services.Capability, system_uri: []const u8) services.Execution {
        var nonce: [16]u8 = undefined;
        std.c.arc4random_buf(&nonce, nonce.len);
        if (std.mem.allEqual(u8, &nonce, 0)) nonce[0] = 1;
        var operation_id: u64 = undefined;
        std.c.arc4random_buf(@ptrCast(&operation_id), @sizeOf(u64));
        return .{ .call = .{ .owner = self.mount_request.owner, .binding_generation = capability.binding_generation }, .operation = .{ .owner = .{ .session = self.mount_request.owner }, .operation_id = operation_id | 1, .attempt_id = self.mount_request.owner.generation }, .nonce = nonce, .system_uri = system_uri, .capability_revision = capability.revision, .grant_revision = capability.grant_revision };
    }
    fn executePower(self: *View) void {
        if (self.closed or self.power_execute_disabled.peek() or self.managementLocked()) return;
        const snapshot = self.power_snapshot orelse return;
        self.submitManagement(.{ .power = .{ .execution = self.execution(snapshot.value.capability, snapshot.value.system_uri), .action = self.power_choice } });
    }
    fn executeBoot(self: *View) void {
        if (self.closed or self.boot_execute_disabled.peek() or self.managementLocked()) return;
        const snapshot = self.boot_snapshot orelse return;
        const draft = self.draft.value.state();
        self.submitManagement(.{ .boot = .{ .execution = self.execution(snapshot.value.capability, snapshot.value.system_uri), .baseline = self.draft.baseline.state(), .enabled = draft.enabled, .target = if (self.draft.disabled()) null else draft.target, .mode = if (self.draft.disabled()) null else draft.mode, .etag = snapshot.value.etag } });
    }
    fn submitManagement(self: *View, request: services.ManagementRequest) void {
        const borrowed = self.borrowConsole() catch return;
        const request_management = borrowed.table.request_management orelse {
            self.showMessage("当前会话未提供管理操作批准入口。");
            return;
        };
        self.releaseInput(.released);
        switch (request_management(borrowed.binding.context, borrowed.binding, request)) {
            .accepted => |key| {
                self.management_operation = .{ .key = key, .boot = request == .boot };
                if (request == .power) {
                    self.power_action = request.power.action;
                    self.power_started_ms = null;
                }
                if (self.management_result) |*old| old.deinit();
                self.management_result = services.Owned(services.Result).init(self.mount_request.cx.allocator, .{ .operation = key, .phase = .awaiting_approval }) catch null;
                self.projectManagement() catch {};
            },
            .rejected => |reason| self.showMessage(vm.reasonLabel(reason)),
        }
        self.mount_request.cx.requestRedraw();
    }
    fn queryManagement(self: *View) void {
        const operation = self.management_operation orelse return;
        const binding = (self.lookup(services.power_definition) catch return) orelse return;
        const table = binding.borrow(services.PowerService, services.power_key, self.mount_request.owner) catch return;
        const query = table.query orelse return;
        query(binding.context, .{ .owner = self.mount_request.owner, .binding_generation = self.mount_request.owner.generation }, operation.key) catch {
            self.showMessage("当前无法查询管理操作结果。");
            return;
        };
        if (self.management_result) |*value| value.value.phase = .verifying;
        self.projectManagement() catch {};
        self.mount_request.cx.requestRedraw();
    }
    fn cancelManagement(self: *View) void {
        const operation = self.management_operation orelse return;
        const binding = (self.lookup(services.power_definition) catch return) orelse return;
        const table = binding.borrow(services.PowerService, services.power_key, self.mount_request.owner) catch return;
        const result = table.cancel(binding.context, .{ .owner = self.mount_request.owner, .binding_generation = self.mount_request.owner.generation }, operation.key);
        self.showMessage(if (result == .cancelled_unsent) "已取消，本次请求未发送。" else if (result == .observation_stopped_remote_may_continue) "已停止等待；设备可能继续执行，仅可查询结果。" else "该操作已经结束或会话已变化。");
        self.refreshManagement() catch {};
        self.mount_request.cx.requestRedraw();
    }
    fn refreshOrder(self: *View, order: ?[]const []const u8) !void {
        const rows = self.order_rows orelse return;
        const cx = self.mount_request.cx;
        const references = order orelse &.{};
        const count = @max(1, @min(references.len, max_order_rows));
        var writer: std.Io.Writer.Allocating = .init(cx.allocator);
        defer writer.deinit();
        for (0..count) |index| {
            // Separate native text nodes give every option its own measured
            // row; a newline inside one shaped text run is not a row boundary.
            if (index == self.order_node_count) {
                const row = try ui.textStyled(cx, S.orderText, "");
                row.setStyleInline(cx.allocator, S.orderRow());
                var id: [48]u8 = undefined;
                row.meta.ownership.meta.test_id = try ownedText(self.mount_request.scope, try std.fmt.bufPrint(&id, "bmc.boot.order_row.{d:0>2}", .{index + 1}));
                try rows.appendChild(cx.allocator, row);
                self.order_nodes[index] = row;
                self.order_node_count += 1;
            }
            writer.clearRetainingCapacity();
            if (references.len == 0) try writer.writer.writeAll("设备尚未返回启动顺序。") else try writer.writer.print("{d:0>2}  {s}", .{ index + 1, references[index] });
            const row = self.order_nodes[index].?;
            try setText(self, row, writer.written());
            row.setDisplay(.flex);
        }
        for (self.order_nodes[count..self.order_node_count]) |row| row.?.setDisplay(.none);
    }
    fn showOrder(self: *View) void {
        self.releaseInput(.released);
        self.closeMenus();
        if (self.order_open) |open| open.set(true);
        if (self.order_viewport) |node| self.mount_request.cx.focus_manager.setFocus(node);
    }
    fn orderKey(event: ui.events.Event, raw: ?*anyopaque) ui.events.EventResult {
        const self: *View = @ptrCast(@alignCast(raw orelse return .ignored));
        if (self.closed or event != .key_down) return .ignored;
        const scroll = self.order_scroll orelse return .ignored;
        const current = scroll.state.scroll_y;
        const next: f32 = switch (event.key_down.key) {
            .home => 0,
            .end => scroll.state.maxScrollY(),
            .page_up => current - scroll.state.viewport_height,
            .page_down => current + scroll.state.viewport_height,
            .up => current - 22,
            .down => current + 22,
            else => return .ignored,
        };
        ui.widgets.scroll_area.setScrollY(scroll.state, scroll.content, next);
        return .stop;
    }
};

const MenuAction = struct {
    view: *View,
    menu: Menu,
    fn anchor(raw: *anyopaque) ui.widgets.popover.AnchorRect {
        const self: *MenuAction = @ptrCast(@alignCast(raw));
        const rect = anchorRectOf(self.view, self.menu) orelse return .{ .x = 0, .y = 0, .w = 0, .h = 0 };
        return .{ .x = rect.x, .y = rect.y, .w = rect.w, .h = rect.h };
    }
    /// The control a menu opens from: its tool, or “更多” while the toolbar is folded.
    fn anchorRectOf(view: *View, menu: Menu) ?ui.ComputedRect {
        const node = if (view.last_overflow) view.more_node else view.tool_nodes[@backingInt(menu)];
        return (node orelse return null).globalRect();
    }
    fn toggle(self: *MenuAction) void {
        const index = @backingInt(self.menu);
        const should_open = !self.view.open[index].peek();
        // The compact management panel replaces the overflow menu. Its focus
        // return target must outlive the disappearing menu row.
        if (index >= 3 and self.view.last_overflow) self.view.mount_request.cx.setFocus(self.view.more_node);
        self.view.releaseInput(.released);
        self.view.closeMenus();
        self.view.open[index].set(should_open);
    }
    fn close(self: *MenuAction) void {
        self.view.open[@backingInt(self.menu)].set(false);
        if (self.menu == .display) self.view.mount_request.cx.setFocus(self.view.tool_nodes[@backingInt(self.menu)]);
    }
    fn changed(self: *MenuAction, open: bool) void {
        if (open) self.view.releaseInput(.released);
    }
};
const MoreAction = struct {
    fn toggle(self: *View) void {
        const should_open = !self.more_open.?.peek();
        self.releaseInput(.released);
        self.closeMenus();
        self.more_open.?.set(should_open);
    }
    /// 电源 / 启动：打开对应面板（锚在“更多”按钮上，同工具栏按钮的点击）。The menu item ids are the
    /// `Menu` tag names.
    fn selected(raw: *anyopaque, id: []const u8) void {
        const self: *View = @ptrCast(@alignCast(raw));
        const menu = std.meta.stringToEnum(Menu, id) orelse return;
        if (menu != .power and menu != .boot) return;
        var action: MenuAction = .{ .view = self, .menu = menu };
        action.toggle();
    }
};
const ChordAction = struct {
    view: *View,
    chord: input.Chord,
    fn send(self: *ChordAction) void {
        self.view.releaseInput(.released);
        // Explicit menu input has its own epoch and never acquires ordinary
        // keyboard focus. Both paths share the same monotonic sequence.
        if (comptime @hasField(input.Interface, "submit_chord")) {
            const binding = (self.view.lookup(input.definition) catch null) orelse return;
            const table = binding.borrow(input.Interface, input.key, self.view.mount_request.owner) catch return;
            const submit_chord = table.submit_chord orelse return;
            const snapshot = table.snapshot(binding.context, binding) catch return;
            if (!snapshot.controlled or !snapshot.connected) return;
            self.view.input_sequence = @max(self.view.input_sequence, snapshot.last_input_sequence);
            if (self.view.input_sequence == std.math.maxInt(u64)) return;
            self.view.input_sequence += 1;
            const result = submit_chord(binding.context, binding, .{ .session_handle = self.view.mount_request.owner, .binding_generation = binding.generation, .input_sequence = self.view.input_sequence, .input_epoch = snapshot.explicit_input_epoch, .control_generation = snapshot.control_generation, .transport_generation = snapshot.transport_generation, .chord = self.chord });
            if (result != .accepted) self.view.showMessage("按键未发送；请检查当前控制权。");
        } else self.view.showMessage("当前无法发送此组合键。");
    }
};
const ReplyAction = struct {
    view: *View,
    reply: console.ControlReply,
    fn send(self: *ReplyAction) void {
        self.view.releaseInput(.released);
        const service = self.view.borrowConsole() catch return;
        var snapshot = service.table.snapshot(service.binding.context, service.binding, self.view.mount_request.cx.allocator) catch return;
        defer snapshot.deinit();
        const request = snapshot.value.control_request orelse return;
        service.table.reply_control(service.binding.context, service.binding, request, self.reply) catch |err| self.view.showFailure(err);
    }
};

const ProgressStepAction = struct {
    view: *View,
    group: vm.ProgressGroup,
    fn toggle(self: *ProgressStepAction) void {
        self.view.progress_disclosure.toggle(self.group);
        if (self.view.snapshot) |snapshot| self.view.projectProgress(snapshot.value) catch {};
        self.view.mount_request.cx.requestRedraw();
    }
};

pub fn mount(_: ?*anyopaque, request: contract.ContentMount) !contract.RendererInstance {
    if (request.service_access == null) return error.ServiceUnavailable;
    const cx = request.cx;
    const scope = request.scope;
    const state = try cx.bindState(View, .{ .mount_request = request });
    errdefer state.release();
    for (&state.open) |*value| {
        value.* = try scope.createSignal(bool, false);
        state.menu_signal_count += 1;
    }
    state.keys_disabled = try scope.createSignal(bool, true);
    for (&state.tool_labels, menu_names) |*source, name| source.* = try scope.createSignal([]const u8, name);
    state.tool_icon_only = try scope.createSignal(bool, false);
    state.hints_enabled = try scope.createSignal(bool, false);
    state.tool_chevron = try scope.createSignal(bool, true);
    state.progress_scroll_y = try scope.createSignal(f32, 0);
    state.log_scroll_y = try scope.createSignal(f32, 0);
    state.log_width = try scope.createSignal(f32, S.log_width);
    state.log_max_height = try scope.createSignal(f32, 600);
    state.scale_value = try scope.createSignal(?[]const u8, @tagName(mapping.Mode.fit));
    state.request_disabled = try scope.createSignal(bool, true);
    state.capture_disabled = try scope.createSignal(bool, true);
    state.power_disabled = try scope.createSignal(bool, true);
    state.boot_disabled = try scope.createSignal(bool, true);
    state.mode_disabled = try scope.createSignal(bool, true);
    state.power_execute_disabled = try scope.createSignal(bool, true);
    state.boot_execute_disabled = try scope.createSignal(bool, true);
    state.switch_disabled = try scope.createSignal(bool, true);
    state.power_options = try scope.createSignal([]const Option, &.{});
    state.boot_options = try scope.createSignal([]const Option, &.{});
    state.mode_options = try scope.createSignal([]const Option, &.{});
    state.power_value = try scope.createSignal(?[]const u8, "On");
    state.target_value = try scope.createSignal(?[]const u8, null);
    state.mode_value = try scope.createSignal(?[]const u8, null);
    state.boot_continuous = try scope.createSignal(bool, false);
    state.show_fps = try scope.createSignal(bool, true);
    state.order_open = try scope.createSignal(bool, false);
    state.log_open = try scope.createSignal(bool, false);
    state.cancel_disabled = try scope.createSignal(bool, false);
    state.disconnect_disabled = try scope.createSignal(bool, true);
    state.disconnect_icon_only = try scope.createSignal(bool, false);
    state.connection_symbol = try scope.createSignal(?ui.SvgAsset, ui.icons.loader_circle);
    state.connection_tint = try scope.createSignal(?ui.Color, S.theme.current().accent_ink);
    state.connection_hint = try scope.createSignal([]const u8, "连接中");
    state.connection_label = try scope.createSignal([]const u8, "连接中");
    state.disconnect_confirm_open = try scope.createSignal(bool, false);
    state.disconnect_confirm_title = try scope.createSignal([]const u8, "断开连接？");
    state.disconnect_confirm_action = try scope.createSignal([]const u8, "断开连接");
    state.disconnect_confirm_message = try scope.createSignal([]const u8, "");
    state.retry_disabled = try scope.createSignal(bool, true);
    state.fullscreen_label = try scope.createSignal([]const u8, "进入全屏");
    const root = try ui.vstackStyled(cx, S.workspaceRoot, .{});
    root.meta.ownership.meta.test_id = "bmc.content";
    root.behavior.events.on_event_capture = View.reserved;
    root.behavior.events.capture_context = state;
    try request.slot.appendChild(cx.allocator, root);
    state.root = root;
    const bar = try ui.hstackStyled(cx, S.toolbar, .{});
    bar.meta.ownership.meta.test_id = "bmc.toolbar";
    try root.appendChild(cx.allocator, bar);
    state.toolbar = bar;
    const identity = try ui.hstackStyled(cx, S.connectionIdentity, .{});
    try bar.appendChild(cx.allocator, identity);
    state.connection_identity = identity;
    const connection_icon = try ui.iconTint(cx, ui.icons.monitor, S.theme.current().accent, S.connectionIcon());
    connection_icon.meta.ownership.meta.test_id = "bmc.title.icon";
    try identity.appendChild(cx.allocator, connection_icon);
    state.connection_icon = connection_icon;
    const connection_title = try ui.textStyled(cx, S.connectionTitle, "KVM 控制台");
    connection_title.setStyleInline(cx.allocator, .{ .width = .{ .fit = .{} }, .min_width = 0, .flex_shrink = 1 });
    connection_title.meta.ownership.meta.test_id = "bmc.title";
    try identity.appendChild(cx.allocator, connection_title);
    state.connection_title = connection_title;
    // Native ghost Button: the label / glyph / tint are the connection status (data), the frame and
    // its hover / pressed / disabled states are zenit's.
    const disconnect = try ui.widgets.Button(.{ .label = state.connection_label, .icon_only = state.disconnect_icon_only, .variant = .ghost, .size = .sm, .icon_asset = state.connection_symbol, .icon_tint = state.connection_tint, .a11y_label = state.connection_hint, .disabled = state.disconnect_disabled, .on_click = cx.on(View, state, View.disconnectConnection) }).mount(scope, cx);
    disconnect.meta.ownership.meta.test_id = "bmc.disconnect";
    const connection_tooltip = try @import("../../shared/ui/components/control_hint/control_hint.zig").mount(cx, scope, disconnect, state.connection_hint, .{ .id = "bmc.disconnect.tooltip", .enabled = state.hints_enabled });
    const disconnect_slot = try ui.boxStyled(cx, S.toolSlot, .{});
    try disconnect_slot.appendChild(cx.allocator, connection_tooltip.wrapper);
    try bar.appendChild(cx.allocator, disconnect_slot);
    state.disconnect_slot = disconnect_slot;
    // j8WXoF O1: the toolbar status slot; picture overlays (O2–O5) mount on the video card below.
    const overlays = try OV.Overlays.mount(cx, scope, cx.on(View, state, View.takeover));
    state.overlays = overlays;
    try bar.appendChild(cx.allocator, overlays.status);
    // TcJSa: title, status, then a spacer that pushes the menus right.
    try bar.appendChild(cx.allocator, try ui.spacer(cx));
    state.disconnect_node = disconnect;
    state.connection_hovered = try ui.hooks.useHover(scope, disconnect);
    state.connection_focused = (try ui.hooks.useFocusState(scope, cx, disconnect)).focused;
    for (menu_names, menu_ids, menu_icons, 0..) |name, id, icon, index| {
        const menu: Menu = @fromBackingInt(@intCast(index));
        const action = try cx.bindState(MenuAction, .{ .view = state, .menu = menu });
        const management = menu == .power or menu == .boot;
        const popup = try ui.widgets.Popover(.{ .trigger = .manual, .open = state.open[index], .position = @as(ui.widgets.popover.PopoverPosition, if (management) .bottom_end else .bottom_start), .anchor = if (management) ui.widgets.popover.Anchor{ .virtual = .{ .ctx = action, .getRect = MenuAction.anchor } } else null, .width = if (menu == .boot) S.boot_width else S.popup_width, .max_width = if (menu == .boot) S.boot_width else S.popup_width, .constrain_width_to_viewport = true, .max_height = S.popup_max_height, .viewport_padding = S.popup_viewport_padding, .shift_main_axis = true, .offset = .{ .static = S.popup_offset }, .size_policy = .fit_content, .enter_transition = .fade, .exit_transition = .fade, .color_scheme = S.popup_scheme, .on_open_change = cx.on(MenuAction, action, MenuAction.changed) }).mount(scope, cx);
        popup.chrome.meta.ownership.meta.test_id = try scopedId(scope, id, ".popover");
        // The panel's layout is this view's own boxes inside the Popover's content slot: a fixed
        // header over one bounded scroll viewport (the tall key menu scrolls, Close stays put).
        const panel = try ui.vstackStyled(cx, S.popupPanel, .{});
        try popup.content.appendChild(cx.allocator, panel);
        const is_display = menu == .display;
        const head = if (is_display) try ui.hstackStyled(cx, S.displayHead, .{}) else try ui.hstackStyled(cx, S.popupHead, .{});
        try panel.appendChild(cx.allocator, head);
        const title = if (is_display) try ui.textStyled(cx, S.displayTitle, name) else try ui.textStyled(cx, S.title, name);
        title.meta.ownership.meta.test_id = try scopedId(scope, id, ".title");
        try head.appendChild(cx.allocator, title);
        try head.appendChild(cx.allocator, try ui.spacer(cx));
        // panel-heads：统一关闭按钮（原生 Popover 默认 Esc 关闭菜单）。
        try head.appendChild(cx.allocator, try panel_header.mountClose(popup.scope, cx, .{ .label = "关闭菜单", .test_id = try scopedId(scope, id, ".close"), .on_close = cx.on(MenuAction, action, MenuAction.close) }));
        // The viewport box carries the height (content-sized up to the popover's cap, see
        // updatePopovers); the ScrollArea fills it.
        const menu_viewport = try ui.box(cx, S.menuViewport(1), .{});
        try panel.appendChild(cx.allocator, menu_viewport);
        const menu_scroll = try ui.widgets.ScrollArea(.{ .direction = .vertical, .rubber_band_y = false }).mount(popup.scope, cx);
        try menu_viewport.appendChild(cx.allocator, menu_scroll.container);
        const body = if (is_display) try ui.vstackStyled(cx, S.displayBody, .{}) else try ui.vstackStyled(cx, S.popupBody, .{});
        body.meta.ownership.meta.test_id = try scopedId(scope, id, ".body");
        try menu_scroll.content.appendChild(cx.allocator, body);
        state.menus[index] = popup;
        state.menu_viewports[index] = menu_viewport;
        state.menu_bodies[index] = body;
        state.menu_scrolls[index] = menu_scroll;
        // Native ghost Button with zenit's own dropdown chevron; no caller styling.
        const button = try ui.widgets.Button(.{ .label = state.tool_labels[index], .a11y_label = name, .icon_only = state.tool_icon_only, .variant = .ghost, .size = .sm, .icon_asset = icon, .chevron = state.tool_chevron, .on_click = cx.on(MenuAction, action, MenuAction.toggle) }).mount(scope, cx);
        button.meta.ownership.meta.test_id = id;
        state.tool_nodes[index] = button;
        const tooltip = try @import("../../shared/ui/components/control_hint/control_hint.zig").mount(cx, scope, button, name, .{ .id = try scopedId(scope, id, ".tooltip"), .enabled = state.hints_enabled });
        try popup.trigger.appendChild(cx.allocator, tooltip.wrapper);
        const slot = try ui.boxStyled(cx, S.toolSlot, .{});
        try slot.appendChild(cx.allocator, popup.wrapper);
        try bar.appendChild(cx.allocator, slot);
        state.tool_slots[index] = slot;
        try mountMenu(state, menu, popup.scope, body);
    }
    const more = try app_menu.AppMenu.mountTrigger(cx, scope, .{ .panel_test_id = "bmc.more.popover", .position = .bottom_end, .trigger = .manual, .color_scheme = S.popup_scheme }, .{ .context = state, .select = MoreAction.selected, .closed = null });
    state.more = more.menu;
    state.more_open = more.menu.open;
    const more_button = try ui.widgets.Button(.{ .variant = .ghost, .size = .sm, .icon_only = true, .icon_asset = ui.icons.ellipsis, .a11y_label = "更多 KVM 操作", .on_click = cx.on(View, state, MoreAction.toggle) }).mount(scope, cx);
    more_button.meta.ownership.meta.test_id = "bmc.more";
    state.more_node = more_button;
    try more.result.trigger.appendChild(cx.allocator, more_button);
    const more_slot = try ui.boxStyled(cx, S.toolSlot, .{});
    try more_slot.appendChild(cx.allocator, more.result.wrapper);
    try bar.appendChild(cx.allocator, more_slot);
    more_slot.setDisplay(.none);
    state.more_slot = more_slot;
    const no_keys = struct {
        const map: @import("../../features/shell/mod.zig").shortcut_router.Map = .{};
    };
    more.menu.set(&.{
        .{ .id = @tagName(Menu.power), .label = menu_names[@backingInt(Menu.power)], .icon = "power", .test_id = "bmc.more.power" },
        .{ .id = @tagName(Menu.boot), .label = menu_names[@backingInt(Menu.boot)], .icon = "rocket", .test_id = "bmc.more.boot" },
    }, .{ .keys = &no_keys.map });
    const workspace = try ui.boxStyled(cx, S.videoWorkspace, .{});
    workspace.meta.ownership.meta.test_id = "bmc.video_workspace";
    try root.appendChild(cx.allocator, workspace);
    const video_card = try ui.boxStyled(cx, S.videoCard, .{});
    video_card.meta.ownership.meta.test_id = "bmc.video_card";
    try workspace.appendChild(cx.allocator, video_card);
    // The picture viewport is this view's own box: it takes focus and input and positions the
    // connection card. The native ScrollArea inside it only scrolls the picture (100% mode).
    const viewport = try ui.boxStyled(cx, S.video, .{});
    viewport.meta.ownership.meta.test_id = "bmc.viewport";
    viewport.behavior.interaction.focusable = true;
    viewport.behavior.events.on_event_capture = View.handle;
    viewport.behavior.events.capture_context = state;
    try video_card.appendChild(cx.allocator, viewport);
    const scroll = try ui.widgets.ScrollArea(.{ .direction = .both, .rubber_band_x = false, .rubber_band_y = false, .background = ui.Color.BLACK }).mount(scope, cx);
    try viewport.appendChild(cx.allocator, scroll.container);
    state.scroll = scroll;
    state.viewport = viewport;
    // The canvas is the scrolled extent (at least the viewport, the picture in 100% mode); the
    // picture is placed inside it.
    const canvas = try ui.box(cx, S.canvas(1, 1), .{});
    try scroll.content.appendChild(cx.allocator, canvas);
    state.canvas = canvas;
    const image_node = try ui.image(cx, 0, S.image());
    image_node.setImage(null);
    image_node.meta.ownership.meta.test_id = "bmc.frame";
    try canvas.appendChild(cx.allocator, image_node);
    state.image_node = image_node;
    state.video_card = video_card;
    for ([_]*ui.Node{ overlays.ai_frame, overlays.hud, overlays.hint, overlays.waiting }) |node| try video_card.appendChild(cx.allocator, node);
    try mountProgress(state, viewport);
    try mountConnectionLog(state);
    try mountDisconnectConfirmation(state);
    try state.theme_watch.bind(cx, scope);
    try scope.createEffect(.{ .view = state, .publication = try cx.themeSignal() }, struct {
        fn paint(ctx: anytype) void {
            _ = ctx.publication.get();
            // Closed portal content is retained outside the window tree.
            const view = ctx.view;
            if (view.closed) return;
            for (view.menus, 0..) |maybe, index| if (maybe) |popup| {
                if (!view.open[index].peek()) view.mount_request.cx.replaySubtreeTheme(popup.chrome);
            };
            if (view.log_modal) |modal| if (!view.log_open.?.peek()) view.mount_request.cx.replaySubtreeTheme(modal.dialog);
            if (view.order_modal) |modal| if (!view.order_open.?.peek()) view.mount_request.cx.replaySubtreeTheme(modal.dialog);
            if (view.disconnect_confirm_dialog) |dialog| if (!view.disconnect_confirm_open.peek()) view.mount_request.cx.replaySubtreeTheme(dialog);
        }
    }.paint);
    // Events instead of per-frame checks: the disconnect button's hover / focus repaint its
    // indicator; the picture's hover feeds the HUD state machine on the next frame.
    try scope.createEffect(.{ .view = state, .hovered = state.connection_hovered.?, .focused = state.connection_focused.?, .disabled = state.disconnect_disabled }, struct {
        fn sync(ctx: anytype) void {
            _ = ctx.hovered.get();
            _ = ctx.focused.get();
            _ = ctx.disabled.get();
            if (!ctx.view.closed) ctx.view.syncConnectionIndicator();
        }
    }.sync);
    state.picture_hovered = try ui.hooks.useHover(scope, viewport);
    try scope.createEffect(.{ .view = state, .hovered = state.picture_hovered.? }, struct {
        fn moved(ctx: anytype) void {
            _ = ctx.hovered.get();
            if (!ctx.view.closed) ctx.view.mount_request.cx.requestRedraw();
        }
    }.moved);
    // Toolbar tooltips exist only for the icon-only toolbar and never under an open menu.
    try scope.createEffect(state, struct {
        fn sync(view: *View) void {
            var menu_open = view.more_open.?.get() or view.order_open.?.get() or view.log_open.?.get();
            for (view.open) |signal| menu_open = signal.get() or menu_open;
            view.hints_enabled.set(view.tool_icon_only.get() and !menu_open);
        }
    }.sync);
    try scope.onCleanup(View, state, View.release);
    state.bindPresentation(true);
    try cx.addAfterLayoutHook(state, View.afterLayout);
    state.after_layout_registered = true;
    try state.refresh();
    cx.requestRedraw();
    return .{ .context = state, .vtable = &.{ .update = View.update, .focus_changed = View.focus, .unmount = View.unmount, .connection_status = View.connectionStatus, .show_connection_details = View.showConnectionDetails, .launcher_context = View.launcherContext, .place_launcher = View.placeLauncher } };
}

/// Disconnect / stop-connecting confirmation: the shared native confirmation (`shared/ui/confirm`,
/// zenit ConfirmDialog): 取消 takes focus; 取消 / × / Esc / scrim keep the session.
fn mountDisconnectConfirmation(state: *View) !void {
    const cx = state.mount_request.cx;
    const scope = state.mount_request.scope;
    const confirm_ui = @import("../../shared/ui/confirm/confirm.zig");
    const dialog = try confirm_ui.confirm(scope, cx, .{
        .open = state.disconnect_confirm_open,
        .title = state.disconnect_confirm_title,
        .message = state.disconnect_confirm_message,
        .action = state.disconnect_confirm_action,
        .width = @as(f32, 440),
        .max_height = @as(f32, 320),
        // confirmDisconnect closes the dialog itself (it checks that the dialog is still up).
        .close_on_confirm = false,
        .on_confirm = cx.on(View, state, View.confirmDisconnect),
        .test_id = "bmc.disconnect.confirmation",
        .test_ids = .{ .message = "bmc.disconnect.detail", .cancel = "bmc.disconnect.return", .confirm = "bmc.disconnect.confirm" },
    });
    if (!dialog.modal.portaled) try state.root.?.appendChild(cx.allocator, dialog.modal.overlay);
    state.disconnect_confirm_dialog = dialog.modal.dialog;
    const target = try ui.textStyled(cx, S.title, "KVM 控制台");
    target.setStyleInline(cx.allocator, .{ .width = .fill(), .min_width = 0 });
    try dialog.content.insertChildBefore(cx.allocator, target, dialog.message);
    state.disconnect_confirm_target = target;
    state.disconnect_confirm_detail = dialog.message;
    state.disconnect_confirm_return = dialog.cancel;
}

fn mountProgress(state: *View, parent: *ui.Node) !void {
    const cx = state.mount_request.cx;
    const scope = state.mount_request.scope;
    const waiting = try ui.vstackStyled(cx, S.waiting, .{});
    waiting.meta.ownership.meta.test_id = "bmc.progress";
    // This overlay is a sibling of the image's scroll content. A failure in
    // 100% mode must stay in the viewport even when the old frame is panned.
    try parent.appendChild(cx.allocator, waiting);
    state.waiting = waiting;
    const surface = try ui.boxStyled(cx, S.progressSurface, .{});
    surface.meta.ownership.meta.test_id = "bmc.progress.surface";
    try waiting.appendChild(cx.allocator, surface);
    const header = try ui.vstackStyled(cx, S.progressHeader, .{});
    try surface.appendChild(cx.allocator, header);
    state.waiting_header = header;
    state.waiting_title = try ui.textStyled(cx, S.progressTitle, "正在准备连接");
    state.waiting_title.?.setStyleInline(cx.allocator, .{ .width = .fill(), .height = .{ .px = 26 }, .flex_shrink = 0 });
    state.waiting_title.?.meta.ownership.meta.test_id = "bmc.progress.stage";
    try header.appendChild(cx.allocator, state.waiting_title.?);
    const route = try ui.boxStyled(cx, S.progressRouteBox, .{});
    route.meta.ownership.meta.test_id = "bmc.progress.route";
    try surface.appendChild(cx.allocator, route);
    state.progress_route = route;
    const route_heading = try ui.hstack(cx, .{ .width = .fill(), .height = .{ .px = 18 }, .gap = 12, .padding = .{ .right = 20 }, .align_items = .center, .flex_shrink = 0 }, .{});
    try route.appendChild(cx.allocator, route_heading);
    try route_heading.appendChild(cx.allocator, try ui.textStyled(cx, S.progressRouteLabel, "连接路径"));
    try route_heading.appendChild(cx.allocator, try ui.spacer(cx));
    const timing = try ui.hstack(cx, .{ .width = .{ .fit = .{} }, .height = .{ .px = 18 }, .gap = 8, .align_items = .center, .flex_shrink = 0 }, .{});
    timing.meta.ownership.meta.test_id = "bmc.progress.timing";
    try route_heading.appendChild(cx.allocator, timing);
    state.progress_timing = timing;
    state.progress_total_time = try ui.textStyled(cx, S.progressTiming, "—");
    state.progress_total_time.?.setStyleInline(cx.allocator, .{ .width = .{ .px = 76 }, .height = .{ .px = 18 }, .flex_shrink = 0 });
    state.progress_total_time.?.meta.ownership.meta.test_id = "bmc.progress.total_time";
    try timing.appendChild(cx.allocator, state.progress_total_time.?);
    state.progress_status = try ui.textStyled(cx, S.progressState, "连接中");
    state.progress_status.?.setStyleInline(cx.allocator, .{ .width = .{ .px = 55 }, .height = .{ .px = 18 }, .flex_shrink = 0 });
    state.progress_status.?.meta.ownership.meta.test_id = "bmc.progress.status";
    try timing.appendChild(cx.allocator, state.progress_status.?);
    state.progress_route_text = try ui.textStyled(cx, S.progressRoute, "");
    state.progress_route_text.?.meta.ownership.meta.test_id = "bmc.progress.target";
    state.progress_route_text.?.setStyleInline(cx.allocator, .{ .width = .fill(), .min_width = 0, .flex_shrink = 0 });
    try route.appendChild(cx.allocator, state.progress_route_text.?);
    state.progress_notice = try ui.textStyled(cx, S.progressNotice, "");
    state.progress_notice.?.setStyleInline(cx.allocator, .{ .width = .fill(), .height = .{ .px = 18 }, .flex_shrink = 0 });
    state.progress_notice.?.meta.ownership.meta.test_id = "bmc.progress.notice";

    // The viewport box carries the height (updateProgressBounds) and keyboard scrolling; the
    // native ScrollArea fills it and follows the controlled offset.
    const body_viewport = try ui.box(cx, S.scrollViewport(1), .{});
    body_viewport.meta.ownership.meta.test_id = "bmc.progress.body";
    body_viewport.behavior.interaction.focusable = true;
    body_viewport.behavior.events.on_event_capture = View.progressKey;
    body_viewport.behavior.events.capture_context = state;
    try surface.appendChild(cx.allocator, body_viewport);
    const body = try ui.widgets.ScrollArea(.{ .direction = .vertical, .rubber_band_y = false, .scroll_y = state.progress_scroll_y }).mount(scope, cx);
    try body_viewport.appendChild(cx.allocator, body.container);
    const list = try ui.vstackStyled(cx, S.progressList, .{});
    try body.content.appendChild(cx.allocator, list);
    state.waiting_body = body;
    state.waiting_viewport = body_viewport;
    state.waiting_list = list;
    try list.appendChild(cx.allocator, state.progress_notice.?);
    const steps = try ui.vstackStyled(cx, S.progressSteps, .{});
    steps.meta.ownership.meta.test_id = "bmc.progress.steps";
    try list.appendChild(cx.allocator, steps);
    state.progress_steps = steps;
    for (0..vm.progress_group_count) |index| {
        const group: vm.ProgressGroup = @fromBackingInt(@intCast(index));
        const block = try ui.vstack(cx, .{ .width = .fill(), .height = .{ .fit = .{} }, .gap = 0, .min_width = 0, .flex_shrink = 0 }, .{});
        try steps.appendChild(cx.allocator, block);
        const action = try cx.bindState(ProgressStepAction, .{ .view = state, .group = group });
        const row = try ui.hstackStyled(cx, S.progressStepBackdrop, .{});
        state.progress_rows[index] = row;
        try block.appendChild(cx.allocator, row);
        // Native Pressable: focus, keyboard, pressed and the expanded semantics are zenit's; the
        // status / name / duration / disclosure columns are its content.
        state.progress_expanded[index] = try scope.createSignal(bool, false);
        const button = try ui.view.render(scope, cx, ui.widgets.Pressable(.{ .expanded = state.progress_expanded[index], .a11y_label = vm.progressGroupLabel(group), .look = Rows.progress_step, .on_click = cx.on(ProgressStepAction, action, ProgressStepAction.toggle) }));
        button.meta.ownership.meta.test_id = try scopedId(scope, "bmc.progress.step.", @tagName(group));
        try row.appendChild(cx.allocator, button);
        const icon = try ui.textStyled(cx, S.progressText, "○");
        icon.setStyleInline(cx.allocator, .{ .width = .{ .px = 16 }, .flex_shrink = 0 });
        try button.appendChild(cx.allocator, icon);
        state.progress_icons[index] = icon;
        const name = try ui.textStyled(cx, S.progressText, vm.progressGroupLabel(group));
        name.setStyleInline(cx.allocator, .{ .width = .fill(), .min_width = 0 });
        try button.appendChild(cx.allocator, name);
        state.progress_names[index] = name;
        const duration = try ui.textStyled(cx, S.progressTiming, "—");
        duration.setStyleInline(cx.allocator, .{ .width = .{ .px = 76 }, .height = .{ .px = 18 }, .font_size = 11, .flex_shrink = 0 });
        setTextLayout(duration, 18.0 / 11.0, .end);
        duration.meta.ownership.meta.test_id = try scopedId(scope, "bmc.progress.duration.", @tagName(group));
        try button.appendChild(cx.allocator, duration);
        state.progress_durations[index] = duration;
        const status = try ui.textStyled(cx, S.progressState, "等待");
        status.setStyleInline(cx.allocator, .{ .width = .{ .px = 55 }, .flex_shrink = 0 });
        setTextLayout(status, 18.0 / 11.0, .end);
        try button.appendChild(cx.allocator, status);
        state.progress_states[index] = status;
        const chevron = try ui.textStyled(cx, S.progressState, "›");
        chevron.setStyleInline(cx.allocator, .{ .width = .{ .px = 12 }, .flex_shrink = 0 });
        try button.appendChild(cx.allocator, chevron);
        state.progress_chevrons[index] = chevron;
        const detail = try ui.textStyled(cx, S.progressDiagnostic, "该步骤尚无连接事件。");
        detail.setStyleInline(cx.allocator, .{ .width = .fill(), .min_width = 0, .flex_shrink = 0, .margin = .{ .left = 24, .top = 4 }, .padding = .{ .top = 8, .bottom = 8, .left = 10, .right = 10 }, .background = S.diagnosticFill(), .border = .{ .width = 0, .radius = 8 } });
        detail.meta.ownership.meta.test_id = try scopedId(scope, "bmc.progress.diagnostic.", @tagName(group));
        try @import("../../shared/ui/styles/surface_material.zig").bindFill(cx, scope, detail, S.diagnosticFill);
        detail.setDisplay(.none);
        try block.appendChild(cx.allocator, detail);
        state.progress_details[index] = detail;
    }
    state.waiting_detail = try ui.textStyled(cx, S.progressDetail, "");
    state.waiting_detail.?.setStyleInline(cx.allocator, .{ .width = .fill(), .flex_shrink = 0 });
    state.waiting_detail.?.meta.ownership.meta.test_id = "bmc.progress.detail";
    try list.appendChild(cx.allocator, state.waiting_detail.?);
    const actions = try ui.hstackStyled(cx, S.progressActions, .{});
    try surface.appendChild(cx.allocator, actions);
    state.waiting_actions = actions;
    _ = try progressButton(state, actions, "连接日志", "bmc.connection_log", null, View.showLog);
    // 取消 / 重试 share one place: only one of them is shown.
    state.cancel_node = try progressButton(state, actions, "取消连接", "bmc.cancel", state.cancel_disabled, View.cancel);
    state.retry_node = try progressButton(state, actions, "重试连接", "bmc.retry", state.retry_disabled, View.retry);
}

fn logColumns() ui.BoxStyle {
    var style = LogS.row(28);
    style.gap = 12;
    style.padding = .{ .left = 12, .right = 12 };
    return style;
}
fn logMuted(_: *const ui.ThemeTokens) ui.TextStyle {
    var style = LogS.logs();
    style.color = LogS.theme.current().fg_2;
    style.wrap = .none;
    return style;
}
fn logMessageStyle(_: *const ui.ThemeTokens) ui.TextStyle {
    return LogS.logs();
}
fn logCell(cx: *ui.Cx, text: []const u8, width: ?f32, right: bool) !*ui.Node {
    const node = try ui.textStyled(cx, logMuted, text);
    node.setStyleInline(cx.allocator, .{ .width = if (width) |value| .{ .px = value } else .fill(), .height = .{ .px = 16 }, .min_width = 0, .flex_shrink = 0 });
    if (right) setTextLayout(node, 16.0 / 10.5, .end);
    return node;
}

fn mountConnectionLog(state: *View) !void {
    const cx = state.mount_request.cx;
    const scope = state.mount_request.scope;
    // Native Modal: its title bar, close button and panel are zenit's (the close button is named
    // through `close_label` and its `close_button` part); width and height cap follow the window through
    // sources. The body is edge to edge so this view's own boxes lay out the content and footer.
    const modal = try ui.widgets.Modal(.{ .title = "连接日志", .open = state.log_open.?, .width = state.log_width, .max_height = state.log_max_height, .close_icon_asset = ui.icons.x, .close_label = "关闭日志，连接继续", .body_padding = ui.Padding.all(0), .body_gap = @as(f32, 0), .enter_transition = .fade, .exit_transition = .fade }).mount(scope, cx);
    // The title bar's close button is a public part of the native Modal: its test id goes on it.
    if (modal.close_button) |close| close.meta.ownership.meta.test_id = "bmc.connection_log.close";
    if (!modal.portaled) try state.root.?.appendChild(cx.allocator, modal.overlay);
    modal.overlay.meta.ownership.meta.test_id = "bmc.connection_log.overlay";
    modal.dialog.meta.ownership.meta.test_id = "bmc.connection_log.modal";
    state.log_modal = modal;
    const content = try ui.box(cx, S.logContent(cx.viewport.height < 600), .{});
    try modal.body.appendChild(cx.allocator, content);
    state.log_content = content;
    const hint = try ui.textStyled(cx, S.hint, "最近 32 条脱敏事件 · 当前会话");
    hint.setStyleInline(cx.allocator, .{ .width = .fill(), .flex_shrink = 0 });
    try content.appendChild(cx.allocator, hint);
    state.log_route_text = try ui.textStyled(cx, S.progressRoute, "");
    state.log_route_text.?.setStyleInline(cx.allocator, .{ .width = .fill(), .min_width = 0, .flex_shrink = 0, .padding = ui.Padding.all(10), .margin = .{ .bottom = 12 }, .background = S.logWellFill(), .border = .{ .width = 0, .radius = 8 } });
    state.log_route_text.?.meta.ownership.meta.test_id = "bmc.connection_log.route";
    try @import("../../shared/ui/styles/surface_material.zig").bindFill(cx, scope, state.log_route_text.?, S.logWellFill);
    try content.appendChild(cx.allocator, state.log_route_text.?);
    const columns = try ui.box(cx, logColumns(), .{});
    columns.meta.ownership.meta.test_id = "bmc.connection_log.columns";
    try content.appendChild(cx.allocator, columns);
    try columns.appendChild(cx.allocator, try logCell(cx, "时间戳", 86, false));
    try columns.appendChild(cx.allocator, try logCell(cx, "消息", null, false));
    try columns.appendChild(cx.allocator, try logCell(cx, "耗时", 76, true));
    // The list viewport is this view's own box (height, well surface, keyboard scrolling); the
    // native ScrollArea fills it and follows the controlled offset.
    const list_viewport = try ui.box(cx, S.logViewport(320), .{});
    list_viewport.meta.ownership.meta.test_id = "bmc.connection_log.list";
    try @import("../../shared/ui/styles/surface_material.zig").bindFill(cx, scope, list_viewport, S.logWellFill);
    list_viewport.behavior.interaction.focusable = true;
    list_viewport.behavior.events.on_event_capture = View.logKey;
    list_viewport.behavior.events.capture_context = state;
    try content.appendChild(cx.allocator, list_viewport);
    state.log_viewport = list_viewport;
    const scroll = try ui.widgets.ScrollArea(.{ .direction = .vertical, .rubber_band_y = false, .scroll_y = state.log_scroll_y }).mount(scope, cx);
    try list_viewport.appendChild(cx.allocator, scroll.container);
    state.log_scroll = scroll;
    // The scrolled extent (padded list) and, inside it, the event rows.
    const log_list = try ui.box(cx, LogS.logContent(), .{});
    try scroll.content.appendChild(cx.allocator, log_list);
    state.log_list = log_list;
    state.log_detail = try ui.vstack(cx, .{ .width = .fill(), .height = .{ .fit = .{} }, .gap = 0, .min_width = 0, .flex_shrink = 0 }, .{});
    state.log_detail.?.meta.ownership.meta.test_id = "bmc.connection_log.events";
    try log_list.appendChild(cx.allocator, state.log_detail.?);
    state.log_empty = try ui.textStyled(cx, logMessageStyle, "本会话尚未产生连接事件。");
    try state.log_detail.?.appendChild(cx.allocator, state.log_empty.?);
    for (0..state.log_rows.len) |index| {
        var row_style = LogS.row(28);
        row_style.height = .{ .fit = .{} };
        row_style.min_height = 28;
        row_style.align_items = .start;
        row_style.gap = 12;
        row_style.padding = .{ .top = 6, .bottom = 6 };
        const row = try ui.box(cx, row_style, .{});
        var index_buffer: [12]u8 = undefined;
        const suffix = try std.fmt.bufPrint(&index_buffer, "{d}", .{index});
        row.meta.ownership.meta.test_id = try scopedId(scope, "bmc.connection_log.row.", suffix);
        try state.log_detail.?.appendChild(cx.allocator, row);
        state.log_rows[index] = row;
        const timestamp = try logCell(cx, "时间未知", 86, false);
        timestamp.meta.ownership.meta.test_id = try scopedId(scope, "bmc.connection_log.timestamp.", suffix);
        try row.appendChild(cx.allocator, timestamp);
        state.log_timestamps[index] = timestamp;
        const message = try ui.textStyled(cx, logMessageStyle, "");
        message.setStyleInline(cx.allocator, .{ .width = .fill(), .min_width = 0, .flex_shrink = 0 });
        message.meta.ownership.meta.test_id = try scopedId(scope, "bmc.connection_log.message.", suffix);
        try row.appendChild(cx.allocator, message);
        state.log_messages[index] = message;
        const duration = try logCell(cx, "—", 76, true);
        duration.meta.ownership.meta.test_id = try scopedId(scope, "bmc.connection_log.duration.", suffix);
        try row.appendChild(cx.allocator, duration);
        state.log_durations[index] = duration;
        row.setDisplay(.none);
    }
    const footer = try ui.box(cx, S.logFooter(cx.viewport.height < 600), .{});
    footer.meta.ownership.meta.test_id = "bmc.connection_log.footer";
    try @import("../../shared/ui/styles/surface_material.zig").bindFill(cx, scope, footer, S.logFooterFill);
    try modal.body.appendChild(cx.allocator, footer);
    state.log_footer = footer;
    const close = try ui.widgets.Button(.{ .label = "关闭", .variant = .secondary, .on_click = cx.on(View, state, View.closeLog) }).mount(scope, cx);
    close.meta.ownership.meta.test_id = "bmc.connection_log.dismiss";
    try footer.appendChild(cx.allocator, close);
}

/// One menu's content, mounted into this view's own body box inside the Popover (`scope` is the
/// Popover's).
fn mountMenu(state: *View, menu: Menu, scope: *ui.Scope, parent: *ui.Node) !void {
    const cx = state.mount_request.cx;
    switch (menu) {
        .control => {
            state.control_label = try ui.textStyled(cx, S.body, "仅观看 · 尚未获控制权");
            try parent.appendChild(cx.allocator, state.control_label.?);
            _ = try actionButton(state, scope, parent, "申请控制权", "bmc.control.request", state.request_disabled, View.requestControl);
            const capture_button = try menuButton(state, scope, "捕获键盘鼠标", "bmc.control.capture", state.capture_disabled, View.capture);
            const capture_hint = try @import("../../shared/ui/components/control_hint/control_hint.zig").mount(cx, scope, capture_button, "点击画面后路由键鼠。Command 映射为远端 Super。", .{ .id = "bmc.control.capture.tooltip", .width = 300, .visible = state.open[@backingInt(Menu.control)] });
            try parent.appendChild(cx.allocator, capture_hint.wrapper);
            _ = try actionButton(state, scope, parent, "释放键盘鼠标 · " ++ mapping.release_hint, "bmc.control.release", null, View.releaseCapture);
            _ = try actionButton(state, scope, parent, "仅观看", "bmc.control.view_only", null, View.onlyView);
            state.control_request_row = try ui.vstackStyled(cx, S.root, .{});
            state.control_request_row.?.setStyleInline(cx.allocator, .{ .height = .{ .fit = .{} }, .gap = 6 });
            try parent.appendChild(cx.allocator, state.control_request_row.?);
            try state.control_request_row.?.appendChild(cx.allocator, try ui.textStyled(cx, S.hint, "另一个客户端请求控制权"));
            for ([_]console.ControlReply{ .full_control, .video_only, .reject }, [_][]const u8{ "移交完整控制", "允许仅观看", "拒绝请求" }, [_][]const u8{ "bmc.control.grant", "bmc.control.video_only", "bmc.control.reject" }) |reply, label, id| {
                const action = try cx.bindState(ReplyAction, .{ .view = state, .reply = reply });
                const button = try ui.widgets.Button(.{ .label = label, .variant = .secondary, .on_click = cx.on(ReplyAction, action, ReplyAction.send) }).mount(scope, cx);
                button.meta.ownership.meta.test_id = id;
                try state.control_request_row.?.appendChild(cx.allocator, button);
            }
            state.message = try ui.textStyled(cx, S.hint, "");
            try parent.appendChild(cx.allocator, state.message.?);
        },
        .keys => {
            const keys_hint = try ui.textStyled(cx, S.hint, "需要已获控制权；不会自动抢占。");
            keys_hint.meta.ownership.meta.test_id = "bmc.keys.hint";
            try parent.appendChild(cx.allocator, keys_hint);
            try chordButton(state, scope, parent, "Ctrl + Alt + Delete", "bmc.keys.ctrl_alt_delete", &.{ 0xffe3, 0xffe9, 0xffff });
            for (0..6) |row_index| {
                const row = try ui.hstackStyled(cx, S.keyRow, .{});
                try parent.appendChild(cx.allocator, row);
                for (0..2) |column| {
                    const index = row_index * 2 + column;
                    var label_buffer: [32]u8 = undefined;
                    var id_buffer: [48]u8 = undefined;
                    const label = try std.fmt.bufPrint(&label_buffer, "Ctrl + Alt + F{d}", .{index + 1});
                    const id = try std.fmt.bufPrint(&id_buffer, "bmc.keys.ctrl_alt_f{d}", .{index + 1});
                    try chordButton(state, scope, row, label, id, &.{ 0xffe3, 0xffe9, 0xffbe + @as(u32, @intCast(index)) });
                }
            }
            const row = try ui.hstackStyled(cx, S.keyRow, .{});
            try parent.appendChild(cx.allocator, row);
            try chordButton(state, scope, row, "远端 Esc", "bmc.keys.escape", &.{0xff1b});
            try chordButton(state, scope, row, "F1", "bmc.keys.f1", &.{0xffbe});
            const function_row = try ui.hstackStyled(cx, S.keyRow, .{});
            try parent.appendChild(cx.allocator, function_row);
            for ([_]u32{ 0xffbf, 0xffc7, 0xffc8, 0xffc9 }, [_][]const u8{ "F2", "F10", "F11", "F12" }, [_][]const u8{ "bmc.keys.f2", "bmc.keys.f10", "bmc.keys.f11", "bmc.keys.f12" }) |key, label, id| try chordButton(state, scope, function_row, label, id, &.{key});
        },
        .display => {
            const controls = try ui.vstackStyled(cx, S.displayControls, .{});
            try parent.appendChild(cx.allocator, controls);
            // 适应窗口 / 100%：zenit 原生分段选择（`W.Tabs` segmented），选中态与键盘行为都是它的。
            const scale = try ui.box(cx, S.displayScale(), .{});
            scale.meta.ownership.meta.test_id = "bmc.display.scale";
            try controls.appendChild(cx.allocator, scale);
            try scale.appendChild(cx.allocator, try ui.widgets.Tabs(.{ .items = &scale_items, .active = state.scale_value, .variant = .segmented, .size = .sm, .on_change = cx.on(View, state, View.scaleChanged) }).mount(scope, cx));
            state.original_hint = try ui.textStyled(cx, S.hint, "按逻辑原尺寸显示。超出区域可在释放键鼠后滚动。");
            state.original_hint.?.meta.ownership.meta.test_id = "bmc.display.original.hint";
            state.original_hint.?.setDisplay(if (state.mode == .original) .flex else .none);
            try controls.appendChild(cx.allocator, state.original_hint.?);
            const fullscreen = try ui.widgets.Button(.{ .label = state.fullscreen_label, .icon_asset = ui.icons.maximize, .variant = .secondary, .block = true, .on_click = cx.on(View, state, View.fullscreen) }).mount(scope, cx);
            fullscreen.meta.ownership.meta.test_id = "bmc.display.fullscreen";
            try controls.appendChild(cx.allocator, fullscreen);

            const performance_section = try ui.vstackStyled(cx, S.displayPerformance, .{});
            try parent.appendChild(cx.allocator, performance_section);
            try performance_section.appendChild(cx.allocator, try ui.widgets.Divider(.{ .spacing = .none }).mount(scope, cx));
            // Native Switch in its default layout; the row around it is this view's box.
            const fps_row = try ui.boxStyled(cx, S.displaySwitchRow, .{});
            try performance_section.appendChild(cx.allocator, fps_row);
            const fps_toggle = try ui.widgets.Switch(.{ .label = "显示 FPS", .checked = state.show_fps, .on_change = cx.on(View, state, View.fpsChanged) }).mount(scope, cx);
            fps_toggle.meta.ownership.meta.test_id = "bmc.display.fps";
            const fps_hint = try @import("../../shared/ui/components/control_hint/control_hint.zig").mount(cx, scope, fps_toggle, "显示：每秒提交到窗口的新视频帧数。\n解码：每秒发布的完整视频帧数。\n无新帧不一定表示卡顿。", .{ .id = "bmc.display.fps.tooltip", .width = 320, .visible = state.open[@backingInt(Menu.display)] });
            try fps_row.appendChild(cx.allocator, fps_hint.wrapper);
            const detail = try ui.vstackStyled(cx, S.displayStats, .{});
            state.fps_detail = detail;
            detail.meta.ownership.meta.test_id = "bmc.fps.detail";
            detail.setDisplay(if (state.show_fps.peek()) .flex else .none);
            try performance_section.appendChild(cx.allocator, detail);
            for ([_][]const u8{ "最近 10 秒最大帧间隔", "距上一显示帧" }, [_][]const u8{ "bmc.fps.max_gap", "bmc.fps.frame_age" }, 0..) |label, id, index| {
                const stat_row = try ui.hstackStyled(cx, S.displayStatRow, .{});
                try detail.appendChild(cx.allocator, stat_row);
                try stat_row.appendChild(cx.allocator, try ui.textStyled(cx, S.displayStatLabel, label));
                const value = try ui.textStyled(cx, S.displayStatValue, "— ms");
                value.meta.ownership.meta.test_id = id;
                try stat_row.appendChild(cx.allocator, value);
                if (index == 0) state.fps_gap_value = value else state.fps_age_value = value;
            }
            try parent.appendChild(cx.allocator, try ui.widgets.Divider(.{ .spacing = .none }).mount(scope, cx));
            const actions = try ui.hstackStyled(cx, S.displayFooter, .{});
            actions.meta.ownership.meta.test_id = "bmc.display.actions";
            try parent.appendChild(cx.allocator, actions);
            const refresh_button = try ui.widgets.Button(.{ .label = "请求完整视频帧", .icon_asset = ui.icons.refresh_cw, .variant = .secondary, .block = true, .on_click = cx.on(View, state, View.refreshVideo) }).mount(scope, cx);
            refresh_button.meta.ownership.meta.test_id = "bmc.display.refresh";
            try actions.appendChild(cx.allocator, refresh_button);
            const log_button = try ui.widgets.Button(.{ .label = "连接日志", .icon_asset = ui.icons.file_text, .variant = .ghost, .on_click = cx.on(View, state, View.showLog) }).mount(scope, cx);
            log_button.meta.ownership.meta.test_id = "bmc.display.connection_log";
            try actions.appendChild(cx.allocator, log_button);
        },
        .power => {
            state.power_mapping_warning = try mappingWarning(state, parent, "bmc.power.mapping_warning");
            const well = try wellValue(state, parent, "bmc.power.summary", "当前电源", "未知");
            state.power_label = well.value;
            state.power_scope_label = well.label;
            try selectField(state, scope, parent, "操作", "bmc.power.action", state.power_options, state.power_value, state.power_disabled, View.powerChanged);
            state.power_hint = try ui.textStyled(cx, S.hint, "当前仅查看管理状态。");
            try parent.appendChild(cx.allocator, state.power_hint.?);
            const actions = try ui.hstackStyled(cx, S.actions, .{});
            try parent.appendChild(cx.allocator, actions);
            state.power_cancel = try actionButton(state, scope, actions, "取消等待", "bmc.power.cancel", null, View.cancelManagement);
            state.power_cancel.?.setDisplay(.none);
            state.power_query = try actionButton(state, scope, actions, "查询结果", "bmc.power.query", null, View.queryManagement);
            state.power_query.?.setDisplay(.none);
            _ = try actionButton(state, scope, actions, "执行", "bmc.power.execute", state.power_execute_disabled, View.executePower);
        },
        .boot => {
            state.boot_mapping_warning = try mappingWarning(state, parent, "bmc.boot.mapping_warning");
            const well = try wellValue(state, parent, "bmc.boot.summary", "当前启动覆盖", "未知");
            state.boot_label = well.value;
            state.boot_scope_label = well.label;
            state.boot_pending_label = try ui.textStyled(cx, S.hint, "");
            state.boot_pending_label.?.setDisplay(.none);
            try parent.appendChild(cx.allocator, state.boot_pending_label.?);
            try selectField(state, scope, parent, "启动设备", "bmc.boot.target", state.boot_options, state.target_value, state.boot_disabled, View.targetChanged);
            const details = try ui.vstackStyled(cx, S.root, .{});
            details.setStyleInline(cx.allocator, .{ .height = .{ .fit = .{} }, .gap = 12, .overflow_hidden = false });
            try parent.appendChild(cx.allocator, details);
            state.boot_details = details;
            const switch_node = try ui.widgets.Switch(.{ .label = "持续生效", .size = .sm, .checked = state.boot_continuous, .disabled = state.switch_disabled, .on_change = cx.on(View, state, View.continuousChanged) }).mount(scope, cx);
            switch_node.meta.ownership.meta.test_id = "bmc.boot.continuous";
            try details.appendChild(cx.allocator, switch_node);
            const mode_row = try ui.hstackStyled(cx, S.field, .{});
            try details.appendChild(cx.allocator, mode_row);
            state.mode_row = mode_row;
            try selectFieldContents(state, scope, mode_row, "下次启动模式", "bmc.boot.mode", state.mode_options, state.mode_value, state.mode_disabled, View.modeChanged);
            _ = try actionButton(state, scope, parent, "查看启动顺序（只读）", "bmc.boot.order", null, View.showOrder);
            const modal = try ui.widgets.Modal(.{ .title = "启动顺序 · 只读", .open = state.order_open.?, .width = @as(f32, 420), .max_height = @as(f32, 360), .close_icon_asset = ui.icons.x, .close_label = "关闭启动顺序", .enter_transition = .fade, .exit_transition = .fade }).mount(scope, cx);
            // The title bar's close button is a public part of the native Modal: its test id goes on it.
            if (modal.close_button) |close| close.meta.ownership.meta.test_id = "bmc.boot.order_close";
            if (!modal.portaled) try state.root.?.appendChild(cx.allocator, modal.overlay);
            modal.dialog.meta.ownership.meta.test_id = "bmc.boot.order_modal";
            state.order_modal = modal;
            state.order_mapping_warning = try mappingWarning(state, modal.body, "bmc.boot.order_mapping_warning");
            state.order_mapping_warning.?.setStyleInline(cx.allocator, .{ .margin = .{ .bottom = 12 } });
            // The list viewport is this view's box (height, keyboard scrolling); the ScrollArea fills it.
            const order_viewport = try ui.box(cx, S.scrollViewport(240), .{});
            order_viewport.meta.ownership.meta.test_id = "bmc.boot.order_list";
            order_viewport.behavior.interaction.focusable = true;
            order_viewport.behavior.events.on_event_capture = View.orderKey;
            order_viewport.behavior.events.capture_context = state;
            try modal.body.appendChild(cx.allocator, order_viewport);
            state.order_viewport = order_viewport;
            const order_scroll = try ui.widgets.ScrollArea(.{ .direction = .vertical, .rubber_band_y = false }).mount(scope, cx);
            try order_viewport.appendChild(cx.allocator, order_scroll.container);
            state.order_scroll = order_scroll;
            state.order_rows = try ui.vstack(cx, .{ .width = .fill(), .height = .{ .fit = .{} }, .gap = 0, .min_width = 0, .flex_shrink = 0 }, .{});
            try order_scroll.content.appendChild(cx.allocator, state.order_rows.?);
            try state.refreshOrder(null);
            state.boot_hint = try ui.textStyled(cx, S.hint, "仅查看启动覆盖；保存启动项不会自动重启。");
            try parent.appendChild(cx.allocator, state.boot_hint.?);
            const actions = try ui.hstackStyled(cx, S.actions, .{});
            try parent.appendChild(cx.allocator, actions);
            state.boot_cancel = try actionButton(state, scope, actions, "取消等待", "bmc.boot.cancel", null, View.cancelManagement);
            state.boot_cancel.?.setDisplay(.none);
            state.boot_query = try actionButton(state, scope, actions, "查询结果", "bmc.boot.query", null, View.queryManagement);
            state.boot_query.?.setDisplay(.none);
            _ = try actionButton(state, scope, actions, "执行", "bmc.boot.execute", state.boot_execute_disabled, View.executeBoot);
        },
    }
}

/// A menu action: zenit's native secondary Button, default size and frame.
fn menuButton(state: *View, scope: *ui.Scope, label: []const u8, id: []const u8, disabled: ?*ui.Signal(bool), comptime action: fn (*View) void) !*ui.Node {
    const button = try ui.widgets.Button(.{ .label = label, .variant = .secondary, .disabled = if (disabled) |signal| ui.Source(bool){ .signal = signal } else ui.Source(bool){ .value = false }, .on_click = state.mount_request.cx.on(View, state, action) }).mount(scope, state.mount_request.cx);
    button.meta.ownership.meta.test_id = id;
    return button;
}
fn actionButton(state: *View, scope: *ui.Scope, parent: *ui.Node, label: []const u8, id: []const u8, disabled: ?*ui.Signal(bool), comptime action: fn (*View) void) !*ui.Node {
    const button = try menuButton(state, scope, label, id, disabled, action);
    try parent.appendChild(state.mount_request.cx.allocator, button);
    return button;
}
fn progressButton(state: *View, parent: *ui.Node, label: []const u8, id: []const u8, disabled: ?*ui.Signal(bool), comptime action: fn (*View) void) !*ui.Node {
    return actionButton(state, state.mount_request.scope, parent, label, id, disabled, action);
}
fn setHeight(cx: *ui.Cx, node: *ui.Node, height: f32) bool {
    const current = switch (node.style.height) {
        .px => |value| value,
        else => @as(f32, -1),
    };
    if (@abs(current - height) <= 0.1) return false;
    node.setStyleInline(cx.allocator, .{ .height = .{ .px = height }, .flex_shrink = 0 });
    return true;
}
fn setTextLayout(node: *ui.Node, height: f32, alignment: ui.TextAlign) void {
    var text = node.getText() orelse return;
    if (@abs(text.line_height - height) <= 0.0001 and text.text_align == alignment) return;
    text.line_height = height;
    text.text_align = alignment;
    node.setText(text);
}
fn setTextColorIfChanged(node: *ui.Node, color: ui.Color) void {
    const text = node.getText() orelse return;
    if (!std.meta.eql(text.color, color)) node.setTextColor(color);
}
fn scrollKey(scroll: ui.widgets.ScrollAreaResult, event: ui.events.Event) ui.events.EventResult {
    if (event != .key_down) return .ignored;
    const current = scroll.state.scroll_y;
    const next: f32 = switch (event.key_down.key) {
        .home => 0,
        .end => scroll.state.maxScrollY(),
        .page_up => current - scroll.state.viewport_height,
        .page_down => current + scroll.state.viewport_height,
        .up => current - 22,
        .down => current + 22,
        else => return .ignored,
    };
    ui.widgets.scroll_area.setScrollY(scroll.state, scroll.content, next);
    return .stop;
}
fn chordButton(state: *View, scope: *ui.Scope, parent: *ui.Node, label: []const u8, id: []const u8, keys: []const u32) !void {
    const cx = state.mount_request.cx;
    const action = try cx.bindState(ChordAction, .{ .view = state, .chord = try input.Chord.init(keys) });
    const owned_label = try ownedText(scope, label);
    const owned_id = try ownedText(scope, id);
    const button = try ui.widgets.Button(.{ .label = owned_label, .variant = .secondary, .block = true, .disabled = state.keys_disabled, .on_click = cx.on(ChordAction, action, ChordAction.send) }).mount(scope, cx);
    button.meta.ownership.meta.test_id = owned_id;
    try parent.appendChild(cx.allocator, button);
}
const WellValue = struct { label: *ui.Node, value: *ui.Node };
fn wellValue(state: *View, parent: *ui.Node, id: []const u8, label: []const u8, value: []const u8) !WellValue {
    const cx = state.mount_request.cx;
    const row = try ui.hstackStyled(cx, S.well, .{});
    row.meta.ownership.meta.test_id = id;
    try parent.appendChild(cx.allocator, row);
    const label_node = try ui.textStyled(cx, S.hint, label);
    try row.appendChild(cx.allocator, label_node);
    const node = try ui.textStyled(cx, S.value, value);
    try row.appendChild(cx.allocator, node);
    return .{ .label = label_node, .value = node };
}
fn mappingWarning(state: *View, parent: *ui.Node, test_id: []const u8) !*ui.Node {
    const cx = state.mount_request.cx;
    const node = try ui.textStyled(cx, S.hint, unverified_mapping_message);
    node.meta.ownership.meta.test_id = test_id;
    node.setDisplay(.none);
    try parent.appendChild(cx.allocator, node);
    return node;
}
fn selectField(state: *View, scope: *ui.Scope, parent: *ui.Node, label: []const u8, id: []const u8, options: *ui.Signal([]const Option), value: *ui.Signal(?[]const u8), disabled: *ui.Signal(bool), comptime changed: fn (*View, ?[]const u8) void) !void {
    const row = try ui.hstackStyled(state.mount_request.cx, S.field, .{});
    try parent.appendChild(state.mount_request.cx.allocator, row);
    try selectFieldContents(state, scope, row, label, id, options, value, disabled, changed);
}
fn selectFieldContents(state: *View, scope: *ui.Scope, row: *ui.Node, label: []const u8, id: []const u8, options: *ui.Signal([]const Option), value: *ui.Signal(?[]const u8), disabled: *ui.Signal(bool), comptime changed: fn (*View, ?[]const u8) void) !void {
    const cx = state.mount_request.cx;
    try row.appendChild(cx.allocator, try ui.textStyled(cx, S.body, label));
    const select = try ui.widgets.Select(.{ .panel_width = .trigger, .options = options, .value = value, .disabled = disabled, .width = S.select_width, .size = .md, .placeholder = "暂无可用选项", .virtualize = true, .on_change = cx.on(View, state, changed) }).mount(scope, cx);
    select.wrapper.meta.ownership.meta.test_id = id;
    select.trigger.meta.ownership.meta.test_id = try scopedId(scope, id, ".trigger");
    select.panel.meta.ownership.meta.test_id = try scopedId(scope, id, ".dropdown");
    // Selects only appear inside the fixed-scheme KVM popups; their portaled panel follows it.
    // The panel, its rows and the trigger are zenit's own (native Select surface).
    cx.setColorScheme(select.panel, S.popup_scheme);
    try row.appendChild(cx.allocator, select.wrapper);
}
fn setText(state: *View, node: ?*ui.Node, text: []const u8) !void {
    const target = node orelse return;
    if (target.getText()) |existing| if (std.mem.eql(u8, existing.content, text)) return;
    try target.setTextContent(state.mount_request.cx.allocator, text);
}
fn scopedId(scope: *ui.Scope, prefix: []const u8, suffix: []const u8) ![]const u8 {
    const joined = try std.mem.concat(scope.allocator, u8, &.{ prefix, suffix });
    defer scope.allocator.free(joined);
    return ownedText(scope, joined);
}
fn ownedText(scope: *ui.Scope, text: []const u8) ![]const u8 {
    const Storage = struct {
        bytes: []u8,
        fn destroy(raw: *anyopaque, allocator: std.mem.Allocator) void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            allocator.free(self.bytes);
            allocator.destroy(self);
        }
    };
    const holder = try scope.allocator.create(Storage);
    errdefer scope.allocator.destroy(holder);
    holder.bytes = try scope.allocator.dupe(u8, text);
    errdefer scope.allocator.free(holder.bytes);
    try scope.registerResource(holder, Storage.destroy);
    return holder.bytes;
}
fn canonicalTarget(value: ?[]const u8) ?[]const u8 {
    for (target_values) |candidate| if (services.optionalEqual(value, candidate)) return candidate;
    return null;
}
fn canonicalMode(value: ?[]const u8) ?[]const u8 {
    for (mode_values) |candidate| if (services.optionalEqual(value, candidate)) return candidate;
    return null;
}
fn buttonMask(button: ui.events.MouseButton) u8 {
    return switch (button) {
        .left => 1,
        .middle => 2,
        .right => 4,
    };
}
