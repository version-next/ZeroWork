//! Read-only identities plus native window selection/close for the existing
//! opt-in Zenit file-RPC harness. Production builds erase this entire route.
//! Commands address a captured WindowId, never whichever window became active.
const std = @import("std");
const zenit = @import("zenit_app");
const application = @import("../../shell/host/application_host.zig");
const plugin_window = @import("../../shell/host/plugin_window_host.zig");
const identity = @import("../../../host/identity.zig");
var domain: ?*application.Domain = null;
var runtime: ?*zenit.MultiWindowApp = null;
// App routes run serially on the main thread and CommandQueue copies the
// returned slice immediately. Its result capacity is 256 KiB; the supplied
// route scratch slice is only 1 KiB and cannot hold a multi-window snapshot.
pub var update_route: ?*const fn ([]const u8, []u8) ?[]const u8 = null;
/// Owner-confirmed application quit (same path as Cmd+Q). Set by main; a bare
/// `MultiWindowApp.quit()` would tear windows down without ZeroWork cleanup.
pub var quit_route: ?*const fn () void = null;
/// shortcuts 包：`/zerowork/shortcuts` 列出快捷键路由的注册表与当前提示文字（由 src/app 注入，test-mode 才有）。
pub var shortcuts_route: ?*const fn ([]u8) ?[]const u8 = null;
var response_buffer: [256 * 1024]u8 = undefined;

pub fn install(app_domain: *application.Domain, windows: *zenit.MultiWindowApp) void {
    if (!zenit.test_harness.enabled) return;
    domain = app_domain;
    runtime = windows;
    zenit.setTestRouteHandler(route);
}

/// usage-b3-titlebar：某个原生窗口（主窗口或辅助窗口）的 chrome 状态与拖动判定网格。
/// `region` 是 `Cx.windowRegionAt`（原生 mouseDown 问的同一个函数；d = 拖动、c = 客户区、o = 其他区域）。
/// `titlebar_presses` 是原生标题栏策略接走的按下次数（开始拖动窗口或执行双击动作），`frame` 是窗口在屏幕上的位置与尺寸。
/// 动作（默认 `probe`，只读）：
/// - `native_click`：把一次左键按下 + 抬起（`count` = 连击数）作为原生 NSEvent 投进本进程的事件队列，由真实事件泵
///   路由（zenit 的测试入口，不发全局事件、不移动物理指针）——Harness 的指针命令在这一层之下，测不到标题栏策略。
/// - `activate`：把这个窗口激活为 key 窗口（前台运行时连同应用一起激活）；探针里的 `active` 是它当前是否为活动窗口。
/// - `fullscreen`：请求进入 / 退出原生全屏（与绿色按钮 / 菜单同一条路径）。
fn windowChromeProbe(body: []const u8) ?[]const u8 {
    const windows = runtime orelse return "{\"ok\":false}";
    const Input = struct { action: []const u8 = "probe", window: u64 = 0, step: f32 = 4, height: f32 = 0, x: f32 = 0, y: f32 = 0, count: u8 = 1, enabled: bool = false };
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const input = if (body.len == 0) Input{} else std.json.parseFromSliceLeaky(Input, arena.allocator(), body, .{ .ignore_unknown_fields = true }) catch return "{\"ok\":false,\"error\":\"InvalidCommand\"}";
    const app = windows.window(input.window) orelse return "{\"ok\":false,\"error\":\"WindowClosed\"}";
    if (std.mem.eql(u8, input.action, "native_click")) {
        app.postNativeMouseForTesting(.down, input.x, input.y, input.count) catch |err| return actionFailed(err);
        app.postNativeMouseForTesting(.up, input.x, input.y, input.count) catch |err| return actionFailed(err);
        return "{\"ok\":true}";
    } else if (std.mem.eql(u8, input.action, "activate")) {
        _ = windows.activateWindow(app.windowId());
        return "{\"ok\":true}";
    } else if (std.mem.eql(u8, input.action, "fullscreen")) {
        app.setFullscreen(input.enabled) catch |err| return actionFailed(err);
        return "{\"ok\":true}";
    } else if (!std.mem.eql(u8, input.action, "probe")) return "{\"ok\":false,\"error\":\"UnsupportedAction\"}";
    const state = app.chromeState();
    const step = @max(1, input.step);
    const height = if (input.height > 0) @min(input.height, state.height) else state.height;
    const cols: usize = @intFromFloat(@ceil(state.width / step));
    const rows: usize = @intFromFloat(@ceil(height / step));
    if (cols * rows + 4096 > response_buffer.len) return "{\"ok\":false,\"error\":\"SnapshotCapacityExceeded\"}";
    var writer = std.Io.Writer.fixed(&response_buffer);
    const overflow = "{\"ok\":false,\"error\":\"SnapshotCapacityExceeded\"}";
    const frame = app.windowFrameForTesting();
    writer.print("{{\"ok\":true,\"width\":{d},\"height\":{d},\"requested_mode\":\"{s}\",\"effective_mode\":\"{s}\",\"controls_owner\":\"{s}\",\"active\":{},\"fullscreen\":{},\"fullscreen_transitioning\":{},\"maximized\":{},\"titlebar_presses\":{d},\"frame\":[{d},{d},{d},{d}],\"step\":{d},\"cols\":{d},\"rows\":{d},\"native_controls\":[", .{ state.width, state.height, @tagName(state.requested_mode), @tagName(state.effective_mode), @tagName(state.controls_owner), state.active, state.fullscreen, state.fullscreen_transitioning, state.maximized, app.titlebarPressesForTesting(), frame[0], frame[1], frame[2], frame[3], step, cols, rows }) catch return overflow;
    for (state.native_controls[0..state.native_controls_count], 0..) |rect, index| writer.print("{s}{{\"x\":{d},\"y\":{d},\"w\":{d},\"h\":{d}}}", .{ if (index == 0) "" else ",", rect.x, rect.y, rect.w, rect.h }) catch return overflow;
    writer.writeAll("],\"region\":\"") catch return overflow;
    for (0..rows) |row| for (0..cols) |col| {
        const region = app.cx.windowRegionAt((@as(f32, @floatFromInt(col)) + 0.5) * step, (@as(f32, @floatFromInt(row)) + 0.5) * step);
        writer.writeByte(switch (region) {
            .drag => 'd',
            .client, .inherit => 'c',
            else => 'o',
        }) catch return overflow;
    };
    writer.writeAll("\"}") catch return overflow;
    return writer.buffered();
}

fn actionFailed(err: anyerror) []const u8 {
    var writer = std.Io.Writer.fixed(&response_buffer);
    std.json.Stringify.value(.{ .ok = false, .@"error" = @errorName(err) }, .{}, &writer) catch return "{\"ok\":false}";
    return writer.buffered();
}

fn route(path: []const u8, body: []const u8, _: []u8) ?[]const u8 {
    if (!zenit.test_harness.enabled) return null;
    if (std.mem.eql(u8, path, "/zerowork/update")) if (update_route) |handle| return handle(body, &response_buffer);
    if (std.mem.eql(u8, path, "/zerowork/menu-bar")) return @import("../../../platform/menu_bar.zig").testSnapshot(&response_buffer);
    // title-click: the native main menu's 显示 › 外观… (body {"invoke":true} chooses it through AppKit).
    // shortcuts: {"title":"…"} chooses that menu item through AppKit; every snapshot lists each item's key equivalent.
    if (std.mem.eql(u8, path, "/zerowork/app-menu")) {
        const app_menu = @import("../../../platform/app_menu.zig");
        const Input = struct { invoke: bool = false, title: []const u8 = "" };
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const input = if (body.len == 0) Input{} else std.json.parseFromSliceLeaky(Input, arena.allocator(), body, .{ .ignore_unknown_fields = true }) catch Input{};
        const action: app_menu.TestAction = if (input.title.len != 0) .{ .title = input.title } else if (input.invoke) .appearance else .snapshot;
        return app_menu.testRoute(action, &response_buffer) orelse "{\"ok\":false}";
    }
    if (std.mem.eql(u8, path, "/zerowork/shortcuts")) if (shortcuts_route) |handle| return handle(&response_buffer);
    // menus 包：每个打开中的原生菜单（面板 id）与它的行——标题、快捷键文字、命令、危险、禁用与原因、分组标题。
    if (std.mem.eql(u8, path, "/zerowork/menus")) {
        var writer = std.Io.Writer.fixed(&response_buffer);
        @import("../../shell/mod.zig").app_menu.writeSnapshot(&writer) catch return "{\"ok\":false}";
        return writer.buffered();
    }
    if (std.mem.eql(u8, path, "/zerowork/tab-icons")) return tabIconsSnapshot();
    if (std.mem.eql(u8, path, "/zerowork/window-chrome")) return windowChromeProbe(body);
    if (std.mem.eql(u8, path, "/zerowork/terminal")) return terminalRoute(body);
    if (std.mem.eql(u8, path, "/zerowork/lifecycle")) return lifecycleSnapshot();
    if (!std.mem.eql(u8, path, "/zerowork/windows")) return null;
    const app_domain = domain orelse return "{\"ok\":false}";
    const windows = runtime orelse return "{\"ok\":false}";
    if (body.len != 0) {
        const Input = struct { action: []const u8 = "snapshot", window: u64 = 0, session: u64 = 0, generation: u64 = 1, destination: u64 = 0, x: f32 = 0, y: f32 = 0, enabled: bool = false };
        var parsed = std.json.parseFromSlice(Input, app_domain.allocator, body, .{}) catch return "{\"ok\":false,\"error\":\"InvalidCommand\"}";
        defer parsed.deinit();
        const command = parsed.value;
        if (std.mem.eql(u8, command.action, "quit")) {
            if (quit_route) |quit| quit() else windows.quit();
        } else if (std.mem.eql(u8, command.action, "fullscreen_content")) {
            const owner: identity.SessionHandle = .{ .session_id = @fromBackingInt(command.session), .generation = command.generation };
            const source = app_domain.ownerForHandle(owner) orelse return "{\"ok\":false,\"error\":\"OwnerMissing\"}";
            if (command.window != 0 and source.window_id != @as(identity.WindowId, @fromBackingInt(command.window))) return "{\"ok\":false,\"error\":\"StaleWindow\"}";
            const host = plugin_window.Host.forApplication(source) orelse return "{\"ok\":false}";
            const input = host.inputFor(owner) orelse return "{\"ok\":false}";
            input.requestFullscreen(command.enabled) catch return "{\"ok\":false,\"error\":\"FullscreenRejected\"}";
        } else if (std.mem.eql(u8, command.action, "transfer_content") or std.mem.eql(u8, command.action, "input_content")) {
            const owner: identity.SessionHandle = .{ .session_id = @fromBackingInt(command.session), .generation = command.generation };
            const source = app_domain.ownerForHandle(owner) orelse return "{\"ok\":false,\"error\":\"OwnerMissing\"}";
            if (command.window != 0 and source.window_id != @as(identity.WindowId, @fromBackingInt(command.window))) return "{\"ok\":false,\"error\":\"StaleWindow\"}";
            const host = plugin_window.Host.forApplication(source) orelse return "{\"ok\":false,\"error\":\"PluginWindowMissing\"}";
            const input = host.inputFor(owner) orelse return "{\"ok\":false,\"error\":\"ContentMissing\"}";
            // Harness-only lease probe dispatches no key, text or pointer. It
            // supplies a real host lease so teardown can prove its revocation.
            if (input.human) |lease| input.release(lease);
            input.setAuthorization(true, input.authorization_revision) catch return "{\"ok\":false}";
            input.setFocus(true, false);
            _ = input.acquire(.automation, input.authorization_revision) catch return "{\"ok\":false,\"error\":\"LeaseUnavailable\"}";
            if (std.mem.eql(u8, command.action, "input_content")) {
                const lease = input.acquire(.automation, input.authorization_revision) catch return "{\"ok\":false}";
                _ = input.route(lease, nextInputSequence(input.last_automation_event) catch return "{\"ok\":false,\"error\":\"InputSequenceExhausted\"}", .{ .pointer = .{ .x = command.x, .y = command.y, .buttons = 0 } }, false) catch return "{\"ok\":false,\"error\":\"InputRejected\"}";
            } else input.transferWindow(@fromBackingInt(command.destination)) catch |err| {
                var failed = std.Io.Writer.fixed(&response_buffer);
                std.json.Stringify.value(.{ .ok = false, .error_code = @errorName(err) }, .{}, &failed) catch return "{\"ok\":false,\"error\":\"SnapshotCapacityExceeded\"}";
                return failed.buffered();
            };
        } else if (!std.mem.eql(u8, command.action, "snapshot")) {
            const target = app_domain.ownerForWindow(@fromBackingInt(command.window)) orelse return "{\"ok\":false,\"error\":\"WindowClosed\"}";
            const app = findNative(windows, target.workspace.cx) orelse return "{\"ok\":false,\"error\":\"NativeWindowMissing\"}";
            if (std.mem.eql(u8, command.action, "select")) {
                _ = windows.activateWindow(app.windowId());
                app.rebindTestHarness();
            } else if (std.mem.eql(u8, command.action, "close")) {
                // Same as the window close button: ZeroWork hides the window.
                app.win.hide();
            } else return "{\"ok\":false,\"error\":\"UnsupportedAction\"}";
        }
    }
    var writer = std.Io.Writer.fixed(&response_buffer);
    writer.writeAll("{\"ok\":true,\"native_count\":") catch return "{\"ok\":false,\"error\":\"SnapshotCapacityExceeded\"}";
    std.json.Stringify.value(zenit.MultiWindowApp.nativeWindowCount(), .{}, &writer) catch return "{\"ok\":false,\"error\":\"SnapshotCapacityExceeded\"}";
    writer.writeAll(",\"windows\":[") catch return "{\"ok\":false,\"error\":\"SnapshotCapacityExceeded\"}";
    for (app_domain.attachments.items, 0..) |host, index| {
        if (index != 0) writer.writeByte(',') catch return "{\"ok\":false,\"error\":\"SnapshotCapacityExceeded\"}";
        const native = findNative(windows, host.workspace.cx);
        std.json.Stringify.value(.{
            .window = @backingInt(host.window_id),
            .workspace = @backingInt(host.workspace_id),
            .native_window = if (native) |app| app.windowId() else 0,
            .shared_registry = host.sessions == &app_domain.sessions,
            .shared_local_adapter = host.local_adapter == app_domain.local_adapter,
            .closing = host.windowClosePending(),
            .frame_count = host.workspace.cx.frame_count,
            .tree_nodes = if (host.workspace.cx.root) |root| treeNodeCount(root) else 0,
        }, .{}, &writer) catch return "{\"ok\":false,\"error\":\"SnapshotCapacityExceeded\"}";
    }
    writer.writeAll("],\"sessions\":[") catch return "{\"ok\":false,\"error\":\"SnapshotCapacityExceeded\"}";
    var count: usize = 0;
    for (app_domain.sessions.sessions.items) |entry| {
        const state = app_domain.sessions.queryState(entry.handle) orelse continue;
        if (count != 0) writer.writeByte(',') catch return "{\"ok\":false,\"error\":\"SnapshotCapacityExceeded\"}";
        count += 1;
        const facade = if (app_domain.ownerForHandle(state.handle)) |host| plugin_window.Host.forApplication(host) else null;
        const input = if (facade) |host| host.inputFor(state.handle) else null;
        const sink = if (facade) |host| host.framesFor(state.handle) else null;
        std.json.Stringify.value(.{ .session = @backingInt(state.handle.session_id), .generation = state.handle.generation, .window = @backingInt(state.target.window_id), .workspace = @backingInt(state.target.workspace_id), .plugin = @tagName(state.plugin_id), .tab = if (state.attachment) |attachment| @backingInt(attachment.tab_id) else 0, .lifecycle = @tagName(state.lifecycle), .close_operation = if (state.close_operation) |key| key.operation_id else null, .close_cleanup_released = if (state.close_operation) |key| closeReleased(app_domain, key) else false, .create_operation = state.create_operation.operation_id, .attempt = state.create_operation.attempt_id, .capability_revision = app_domain.sessions.capabilityRevisionFor(state.handle), .fullscreen = if (input) |value| value.fullscreen() else false, .input_instance = if (input) |value| value.context_instance else 0, .transfer_state = if (input) |value| @tagName(value.transfer_state) else "unavailable", .transfer_error = if (input) |value| (if (value.transfer_state == .failed) @errorName(value.transfer_state.failed) else "") else "", .texture = if (sink) |value| value.texture else null, .frame_revision = if (sink) |value| value.revision else 0 }, .{}, &writer) catch return "{\"ok\":false,\"error\":\"SnapshotCapacityExceeded\"}";
    }
    writer.writeAll("],\"content_states\":[") catch return "{\"ok\":false,\"error\":\"SnapshotCapacityExceeded\"}";
    var content_count: usize = 0;
    for (app_domain.attachments.items) |app_host| if (plugin_window.Host.forApplication(app_host)) |host| {
        for (host.content_host.entries.items) |entry| {
            if (content_count != 0) writer.writeByte(',') catch return "{\"ok\":false,\"error\":\"SnapshotCapacityExceeded\"}";
            content_count += 1;
            std.json.Stringify.value(.{ .window = @backingInt(app_host.window_id), .session = @backingInt(entry.input.owner.session_id), .generation = entry.input.owner.generation, .context_instance = entry.input.context_instance, .retired = entry.retired, .input_closed = entry.input.closed, .frame_closed = !entry.frames.accepting.load(.acquire), .texture = entry.frames.texture, .frame_revision = entry.frames.revision }, .{}, &writer) catch return "{\"ok\":false,\"error\":\"SnapshotCapacityExceeded\"}";
        }
    };
    writer.writeAll("],\"transfers\":") catch return "{\"ok\":false,\"error\":\"SnapshotCapacityExceeded\"}";
    std.json.Stringify.value(plugin_window.transfer_receipts[0..plugin_window.transfer_receipt_count], .{}, &writer) catch return "{\"ok\":false,\"error\":\"SnapshotCapacityExceeded\"}";
    writer.writeAll(",\"tasks\":[") catch return "{\"ok\":false,\"error\":\"SnapshotCapacityExceeded\"}";
    if (app_domain.tasks) |tasks| for (0..tasks.manager.count()) |index| {
        const progress = tasks.manager.progressAt(index) orelse continue;
        if (index != 0) writer.writeByte(',') catch return "{\"ok\":false,\"error\":\"SnapshotCapacityExceeded\"}";
        const retained = tasks.manager.retainedOwner(progress.job);
        const binding = tasks.manager.transferBinding(progress.job);
        std.json.Stringify.value(.{
            .job = progress.job,
            .attempt = progress.attempt,
            .state = @tagName(progress.state),
            .cleanup = @tagName(progress.job_cleanup),
            .done_bytes = progress.done_bytes,
            .total_bytes = progress.total_bytes,
            .session = tasks.manager.sessionId(progress.job),
            .binding = if (binding) |value| value.binding_id else 0,
            .binding_generation = if (binding) |value| value.binding_generation else 0,
            .retained_owner = if (retained) |value| @backingInt(value.id) else 0,
            .original_session = if (retained) |value| @backingInt(value.original_handle.session_id) else 0,
            .original_generation = if (retained) |value| value.original_handle.generation else 0,
        }, .{}, &writer) catch return "{\"ok\":false,\"error\":\"SnapshotCapacityExceeded\"}";
    };
    writer.writeAll("],\"backgrounds\":[") catch return "{\"ok\":false,\"error\":\"SnapshotCapacityExceeded\"}";
    if (app_domain.tasks) |tasks| if (tasks.backgrounds) |model| for (model.rows.items, 0..) |row, index| {
        if (index != 0) writer.writeByte(',') catch return "{\"ok\":false,\"error\":\"SnapshotCapacityExceeded\"}";
        std.json.Stringify.value(.{
            .session = @backingInt(row.owner.session_id),
            .generation = row.owner.generation,
            .asset = @backingInt(row.source.id),
            .asset_revision = row.source.revision,
            .name = row.name,
            .phase = @tagName(row.phase),
            .local_port = row.local_port,
        }, .{}, &writer) catch return "{\"ok\":false,\"error\":\"SnapshotCapacityExceeded\"}";
    };
    writer.writeAll("]}") catch return "{\"ok\":false,\"error\":\"SnapshotCapacityExceeded\"}";
    return writer.buffered();
}

fn tabIconsSnapshot() []const u8 {
    const app_domain = domain orelse return "[]";
    var writer = std.Io.Writer.fixed(&response_buffer);
    writer.writeByte('[') catch return "[]";
    var count: usize = 0;
    for (app_domain.attachments.items) |host| {
        const workspace = host.workspace;
        for (workspace.tab_nodes.items) |node| {
            const at = workspace.model.indexOf(node.tab_id) orelse continue;
            const item = workspace.tabPresentation(workspace.model.tabs.items[at].owner) orelse continue;
            if (count != 0) writer.writeByte(',') catch return "[]";
            count += 1;
            std.json.Stringify.value(.{ .window = @backingInt(host.window_id), .tab = @backingInt(item.tab_id), .title = item.title, .state = @tagName(workspace.tabIconState(item.tab_id)), .icon = item.icon_id, .tint = item.icon_tint, .backdrop = item.icon_backdrop, .original = item.icon_original, .bouncing = item.icon_bouncing, .offset = node.type_icon.style.translate_y, .rendered_background = node.type_icon.getBackground(), .rendered_shape = @tagName(node.type_icon.style.shape()), .rendered_vector_fill = node.type_icon.getLayoutOutput().vector.fill.path != null }, .{}, &writer) catch return "[]";
        }
    }
    writer.writeByte(']') catch return "[]";
    return writer.buffer[0..writer.end];
}

/// LIFECYCLE.md §6：每个窗口的节点数（整棵树、弹层 portal、根下各区域、标签页正文、停放在窗口外的表面）、
/// after-layout hook 数、Scope 数，以及进程级的“重的事情做了几次”。只读，test-mode 才有。
fn lifecycleSnapshot() []const u8 {
    const app_domain = domain orelse return "{\"ok\":false}";
    const overflow = "{\"ok\":false,\"error\":\"SnapshotCapacityExceeded\"}";
    const budget = @import("../../../shared/ui/surface/lifecycle_budget.zig");
    const surface_migration = @import("../../../shared/ui/surface/surface_migration.zig");
    var writer = std.Io.Writer.fixed(&response_buffer);
    writer.print("{{\"ok\":true,\"counters\":{{\"conversation_rebuilds\":{d},\"group_presentations\":{d},\"surface_moves\":{d},\"surface_parks\":{d},\"content_mounts\":{d},\"content_unmounts\":{d},\"last_content_mount_ns\":{d},\"ai_hook_runs\":{d},\"ai_passes\":{d},\"ai_pass_rounds\":{d},\"ai_frame_steps\":{d},\"ai_pass_ns\":{d},\"ai_idle_ns\":{d},\"ai_pass_reasons\":{{", .{ budget.counters.conversation_rebuilds, budget.counters.group_presentations, budget.surfaceMoves(), budget.surfaceParks(), budget.counters.content_mounts, budget.counters.content_unmounts, budget.counters.last_content_mount_ns, budget.counters.ai_hook_runs, budget.counters.ai_passes, budget.counters.ai_pass_rounds, budget.counters.ai_frame_steps, budget.counters.ai_pass_ns, budget.counters.ai_idle_ns }) catch return overflow;
    for (budget.ai_pass_reason_names, 0..) |name, at| {
        writer.print("{s}\"{s}\":{d}", .{ if (at == 0) "" else ",", name, budget.counters.ai_pass_reasons[at] }) catch return overflow;
    }
    // Who follows the shared conversations (session views' phase boards, bound-count badges): a released view
    // must have stopped listening, a mounted one must listen.
    const ai_phase_observers: usize = if (app_domain.ai) |ai| ai.presentations.phase_observers.items.len else 0;
    const ai_binding_observers: usize = if (app_domain.ai) |ai| ai.service.store.binding_observers.items.len else 0;
    writer.print("}},\"ai_phase_observers\":{d},\"ai_binding_observers\":{d}", .{ ai_phase_observers, ai_binding_observers }) catch return overflow;
    // Rest (LIFECYCLE.md §5.5): how many AI frame hooks would run a pass on their next frame (a pending
    // publication / environment change / rerun, the card in flight, a deadline not yet passed).
    writer.writeAll(",\"ai_hooks\":[") catch return overflow;
    for (budget.restProbes(), 0..) |probe, at| {
        const rest = probe.state(probe.context);
        if (at != 0) writer.writeByte(',') catch return overflow;
        std.json.Stringify.value(.{ .due = rest.due, .deadline_in_ms = if (rest.deadline_in_ns) |ns| @divTrunc(ns, std.time.ns_per_ms) else null }, .{}, &writer) catch return overflow;
    }
    writer.writeByte(']') catch return overflow;
    writer.writeAll("},\"windows\":[") catch return overflow;
    for (app_domain.attachments.items, 0..) |host, index| {
        const workspace = host.workspace;
        const cx = workspace.cx;
        const root = cx.root orelse continue;
        if (index != 0) writer.writeByte(',') catch return overflow;
        var top = workspace.scope;
        while (top.parent) |parent| top = parent;
        var parked_buffer: [16]*@import("ui").Node = undefined;
        var parked: struct { surfaces: usize = 0, nodes: usize = 0 } = .{};
        for (surface_migration.parkedIn(cx, &parked_buffer)) |surface| {
            parked.surfaces += 1;
            parked.nodes += treeNodeCount(surface);
        }
        writer.print("{{\"window\":{d},\"input_epoch\":{d},\"frame_count\":{d},\"tree_nodes\":{d},\"portal_nodes\":{d},\"tab_body_nodes\":{d},\"tab_strip_nodes\":{d},\"parked_surfaces\":{d},\"parked_nodes\":{d},\"after_layout_hooks\":{d},\"scopes\":{d},\"regions\":[", .{
            @backingInt(host.window_id),                                                cx.input_epoch,
            cx.frame_count,
            treeNodeCount(root),                                                        if (cx.popover_portal_root) |portal| treeNodeCount(portal) else 0,
            treeNodeCount(workspace.terminal_area),                                     treeNodeCount(workspace.tab_bar),
            parked.surfaces,                                                            parked.nodes,
            cx.after_layout_hooks.items.len,                                            scopeCount(top),
        }) catch return overflow;
        // The window root's direct children are the shell's regions (title bar, main row, float layer, …).
        for (root.children.items, 0..) |region, at| {
            if (at != 0) writer.writeByte(',') catch return overflow;
            writer.writeAll("{\"id\":") catch return overflow;
            std.json.Stringify.value(region.meta.ownership.meta.test_id orelse "", .{}, &writer) catch return overflow;
            writer.print(",\"nodes\":{d},\"displayed\":{}}}", .{ treeNodeCount(region), region.style.display != .none }) catch return overflow;
        }
        writer.writeAll("]}") catch return overflow;
    }
    writer.writeAll("]}") catch return overflow;
    return writer.buffered();
}

fn scopeCount(scope: *const @import("ui").Scope) usize {
    var count: usize = 1;
    for (scope.children.items) |child| count += scopeCount(child);
    return count;
}

fn findNative(windows: *zenit.MultiWindowApp, cx: *@import("ui").Cx) ?*zenit.App {
    for (windows.windows.items) |managed| if (managed.app.cx == cx) return managed.app;
    return null;
}

fn treeNodeCount(node: *const @import("ui").Node) usize {
    var count: usize = 1;
    for (node.children.items) |child| count += treeNodeCount(child);
    return count;
}

fn closeReleased(app_domain: *application.Domain, key: @import("../../../host/operation.zig").OperationKey) bool {
    for (app_domain.sessions.journal.records.items) |record| if (record.key.eql(key)) return record.cleanup_released;
    return false;
}

fn nextInputSequence(previous: u64) error{InputSequenceExhausted}!u64 {
    if (previous == std.math.maxInt(u64)) return error.InputSequenceExhausted;
    return previous + 1;
}

test "content input event sequence starts at one and never wraps" {
    try std.testing.expectEqual(@as(u64, 1), try nextInputSequence(0));
    try std.testing.expectEqual(@as(u64, 2), try nextInputSequence(1));
    try std.testing.expectError(error.InputSequenceExhausted, nextInputSequence(std.math.maxInt(u64)));
}

fn terminalRoute(body: []const u8) []const u8 {
    const app_domain = domain orelse return "{\"ok\":false}";
    const Input = struct { action: []const u8 = "metrics", path: []const u8 = "", format: []const u8 = "txt_cast", window: u64 = 0 };
    var parsed = std.json.parseFromSlice(Input, app_domain.allocator, body, .{}) catch return "{\"ok\":false,\"error\":\"InvalidCommand\"}";
    defer parsed.deinit();
    const command = parsed.value;
    if (std.mem.eql(u8, command.action, "memory")) {
        var writer = std.Io.Writer.fixed(&response_buffer);
        var capacity: usize = 0;
        var scratch_capacity: usize = 0;
        var pending = false;
        for (app_domain.attachments.items) |host| {
            const cx = host.workspace.cx;
            const display = cx.display_list.memoryStats();
            capacity += display.item_capacity_bytes;
            scratch_capacity += display.item_capacity_bytes + display.payload_capacity_bytes + cx.frame_arena.queryCapacity();
            pending = pending or cx.idle_scratch_limit != null or cx.display_list.idle_payload_limit != null;
        }
        var cpu_max: u64 = 0;
        if (runtime) |windows| for (app_domain.attachments.items) |host| {
            if (findNative(windows, host.workspace.cx)) |app| cpu_max = @max(cpu_max, app.renderer.timing_ring.cpuPercentile(100));
        };
        std.json.Stringify.value(.{ .ok = true, .background_search_tasks = @import("../../../vt/search_task.zig").live_count.load(.monotonic), .search_executor = @import("../../../vt/search_executor.zig").stats(), .idle_reclaim_runs = app_domain.idle_reclaim_runs, .idle_reclaim_running = pending, .idle_trimmed_bytes = app_domain.idle_trimmed_bytes, .display_capacity_bytes = capacity, .scratch_capacity_bytes = scratch_capacity, .cpu_max_us = cpu_max }, .{}, &writer) catch return "{\"ok\":false}";
        return writer.buffered();
    }
    const host = for (app_domain.attachments.items) |candidate| {
        if (command.window == 0 or @backingInt(candidate.window_id) == command.window) break candidate;
    } else return "{\"ok\":false,\"error\":\"WindowMissing\"}";
    const workspace = host.workspace;
    const index = workspace.active_tab orelse return "{\"ok\":false,\"error\":\"TabMissing\"}";
    const view = workspace.tabs.items[index].terminal orelse return "{\"ok\":false,\"error\":\"TerminalMissing\"}";
    const surface = view.terminal_surface orelse return "{\"ok\":false,\"error\":\"SurfaceMissing\"}";
    if (std.mem.eql(u8, command.action, "profile")) {
        const app = findNative(runtime.?, workspace.cx) orelse return "{\"ok\":false}";
        const p = workspace.cx.perf;
        var writer = std.Io.Writer.fixed(&response_buffer);
        std.json.Stringify.value(.{ .ok = true, .frame = workspace.cx.frame_count, .timing = app.renderer.last_frame_stats, .before_render_us = p.before_render_us, .inner_layout_us = p.inner_layout_us, .render_node_us = p.render_node_us, .slow_hook_us = p.slow_hook_us, .slow_hook = p.slow_hook_name[0..p.slow_hook_name_len], .compose_us = surface.composite.profile_compose_us, .compose_rows = surface.composite.last_composed_rows, .refresh_calls = view.profile_refresh_calls, .refresh_us = view.profile_refresh_us, .surface_us = view.profile_surface_us, .history_us = view.profile_history_us }, .{}, &writer) catch return "{\"ok\":false}";
        return writer.buffered();
    }
    const Jobs = @import("session_export_jobs.zig");
    const manager = Jobs.Manager.forCx(workspace.cx);
    if (std.mem.eql(u8, command.action, "export")) {
        const exports = manager orelse return "{\"ok\":false,\"error\":\"ExportUnavailable\"}";
        const format = @import("session_export.zig").Format.parse(command.format) catch return "{\"ok\":false,\"error\":\"InvalidFormat\"}";
        const lease = surface.service.recordingLease() catch return "{\"ok\":false,\"error\":\"RecordingUnavailable\"}";
        exports.start(.{ .live = lease }, format, command.path) catch return "{\"ok\":false,\"error\":\"ExportStartFailed\"}";
    }
    var writer = std.Io.Writer.fixed(&response_buffer);
    const cached = surface.composite.cached;
    std.json.Stringify.value(.{
        .ok = true,
        .grid = if (surface.snapshot) |snapshot| .{ .cols = snapshot.projection.cols, .rows = snapshot.projection.rows } else null,
        .history_bytes = view.history.bytes,
        .history_frames = view.history.frames.items.len,
        .history_latest_wire_bytes = if (view.history.latest()) |last| last.wire.len else 0,
        .composite_bytes = if (cached) |doc| doc.text.len + doc.rows.len * @sizeOf(@import("../../../vt/search_snapshot.zig").Row) + doc.spans.len * @sizeOf(@import("../../../vt/search_snapshot.zig").Span) else 0,
        .composite_full_rebuilds = surface.composite.full_rebuilds,
        .composite_tail_updates = surface.composite.tail_updates,
        .composite_incremental_rebuilds = surface.composite.incremental_rebuilds,
        .composite_background_scans = surface.composite.background_scans,
        .composite_synchronous_scans = surface.composite.synchronous_scans,
        .composite_source_complete = surface.composite.source_complete,
        .composite_search_pending = surface.composite.search_task != null,
        .composite_last_composed_rows = surface.composite.last_composed_rows,
        .glyphs_pending = surface.glyphs_pending,
        .search_open = view.search_open,
        .search_matches = view.search.matches.items.len,
        .search_background_scans = view.service_search_background_scans,
        .search_synchronous_scans = view.service_search_synchronous_scans,
        .search_cancelled = view.service_search_cancelled,
        .search_task_pending = view.service_search_task != null,
        .input_during_hydration = surface.input_during_hydration,
        .glyph_nodes = blk: {
            var count: usize = 0;
            for (surface.rows.items) |row| count += row.glyphs.items.len;
            break :blk count;
        },
        .record_count = surface.composite.records.items.len,
        .frame = workspace.cx.frame_count,
        .export_running = if (manager) |exports| exports.job != null else false,
        .exports_completed = if (manager) |exports| exports.completed else 0,
        .export_error = if (manager) |exports| if (exports.last_failure) |err| @errorName(err) else @as(?[]const u8, null) else null,
    }, .{}, &writer) catch return "{\"ok\":false}";
    return writer.buffered();
}
