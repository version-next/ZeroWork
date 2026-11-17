const std = @import("std");
const ui = @import("ui");
const SSH = @import("../host/ssh_status_host.zig");
const D = @import("../view/connection_details_view.zig");
const Logs = @import("../view/connection_logs_view.zig");
const a = std.testing.allocator;
const key: D.OperationKey = .{ .owner = .{ .session = .{ .session_id = @fromBackingInt(901), .generation = 1 } }, .operation_id = 4, .attempt_id = 1 };
fn snapshot(captured: D.OperationKey, name: []const u8) !D.Snapshot {
    var value: D.Snapshot = .{ .key = captured, .revision = 1, .source = .session, .hops = @splat(.{}), .hop_count = 2, .target_rtt_sample = null, .sampled_at = null };
    for (value.hops[0..2], 0..) |*hop, index| {
        hop.configured = true;
        hop.status = .online;
        hop.endpoint = .{ .host = try D.details.Text(1024).init(if (index == 0) "edge.example" else "db.example"), .user = try D.details.Text(256).init("admin"), .name = try D.details.Text(512).init(if (index == 0) "Bastion" else name) };
    }
    return value;
}
const Fixture = struct {
    cx: *ui.Cx,
    scope: *ui.Scope,
    bar: SSH.StatusBar,
    host: *SSH.Host,
    logs: *Logs.View,
    captures: usize = 0,
    copies: usize = 0,
    reconnects: usize = 0,
    themes: usize = 0,
    routes: usize = 0,
    captured: ?D.Snapshot = null,
    last_key: ?D.OperationKey = null,
    last_theme_trigger: ?*ui.Node = null,
    copied: ?[]u8 = null,
    fn init(self: *Fixture) !void {
        self.* = .{ .cx = try ui.Cx.init(a, std.testing.io), .scope = undefined, .bar = undefined, .host = undefined, .logs = undefined };
        self.cx.setViewport(1440, 900);
        self.cx.root = try ui.box(self.cx, .{ .width = .fill(), .height = .fill() }, .{});
        self.scope = try ui.Scope.init(a, null, self.cx.owner);
        self.bar = try SSH.mountStatusBar(self.cx, self.scope, try ui.text(self.cx, "就绪", .{}));
        self.bar.bar.setStyleInline(a, .{ .position = .absolute, .inset = .{ .left = .{ .px = 8 }, .top = .{ .px = 860 } }, .width = .{ .px = 1424 } });
        try self.cx.root.?.appendChild(a, self.bar.bar);
        try self.bar.progress_slot.appendChild(a, try ui.box(self.cx, .{ .width = .{ .px = 264 }, .height = .{ .px = 26 } }, .{}));
        self.logs = try Logs.View.mount(self.cx, self.scope, .{ .context = self, .copy_logs = copy });
        self.host = try SSH.Host.mount(self.cx, self.scope, .{ .context = self, .capture = capture, .copy = copy, .logs = openLogs, .reconnect = reconnect, .hide_chain = hideChain, .show_route = showRoute });
        self.host.bind(self.bar.controls, self, theme);
        try self.bar.controls.setThemeName(self.cx, "Sauber");
        self.cx.layout();
        _ = self.cx.render();
    }
    fn deinit(self: *Fixture) void {
        self.scope.dispose();
        self.cx.deinit();
        if (self.copied) |text| a.free(text);
    }
    fn settle(self: *Fixture) void {
        self.cx.setTestFrameStep(16) catch unreachable;
        for (0..20) |_| {
            self.cx.advanceFrameClock();
            self.cx.layout();
            _ = self.cx.render();
        }
    }
    fn update(self: *Fixture, source: D.Snapshot, retry: bool) !void {
        try self.host.updateActive(.{ .details = source, .utf8 = true, .grid = .{ .cols = 120, .rows = 36, .revision = 1 }, .can_reconnect = retry });
        self.settle();
    }
    fn enter(self: *Fixture, node: *ui.Node) void {
        self.cx.setFocus(node);
        self.cx.handleKeyDown(.@"return", .{});
        self.settle();
    }
    fn click(self: *Fixture, node: *ui.Node) void {
        const rect = node.globalRect();
        self.cx.handleMouseDown(rect.x + rect.w / 2, rect.y + rect.h / 2, .{});
        self.cx.handleMouseUp(rect.x + rect.w / 2, rect.y + rect.h / 2);
        self.settle();
    }
    fn capture(raw: *anyopaque, source: D.Snapshot) !void {
        const self: *Fixture = @ptrCast(@alignCast(raw));
        self.captures += 1;
        self.captured = source;
    }
    fn copy(raw: *anyopaque, captured: D.OperationKey, text: []const u8) !void {
        const self: *Fixture = @ptrCast(@alignCast(raw));
        if (self.captured == null or !self.captured.?.key.eql(captured)) return error.StaleConnection;
        const owned = try a.dupe(u8, text);
        if (self.copied) |old| a.free(old);
        self.copied = owned;
        self.copies += 1;
        self.last_key = captured;
    }
    fn openLogs(raw: *anyopaque, captured: D.OperationKey) !void {
        const self: *Fixture = @ptrCast(@alignCast(raw));
        if (self.captured == null or !self.captured.?.key.eql(captured)) return error.StaleConnection;
        var record: Logs.LogRecord = .{ .key = captured, .entry = .{ .hop_count = 2, .hop = 1, .status = .succeeded, .phase = .ready, .port = 22 } };
        @memcpy(record.entry.host[0..10], "db.example");
        record.entry.host_len = 10;
        try self.logs.show(.{ .key = captured, .revision = 1, .endpoint = self.captured.?.hops[1].endpoint, .records = (&record)[0..1] });
        self.last_key = captured;
    }
    fn reconnect(raw: *anyopaque, captured: D.OperationKey) !void {
        const self: *Fixture = @ptrCast(@alignCast(raw));
        if (self.captured == null or !self.captured.?.key.eql(captured)) return error.StaleConnection;
        self.reconnects += 1;
        self.last_key = captured;
    }
    fn hideChain(_: *anyopaque) void {}
    fn showRoute(raw: *anyopaque) void {
        const self: *Fixture = @ptrCast(@alignCast(raw));
        self.routes += 1;
    }
    fn theme(raw: *anyopaque, trigger: *ui.Node) void {
        const self: *Fixture = @ptrCast(@alignCast(raw));
        self.themes += 1;
        self.last_theme_trigger = trigger;
    }
};
fn id(node: *ui.Node, text: []const u8) ?*ui.Node {
    if (node.meta.ownership.meta.test_id) |value| if (std.mem.eql(u8, text, value)) return node;
    for (node.children.items) |child| if (id(child, text)) |found| return found;
    return null;
}

test "SSH status click pin survives a refreshed projection click action" {
    const overlay = @import("../../../../shared/ui/overlay/overlay_host.zig");
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    var source = try snapshot(key, "DB-A");
    try f.update(source, false);
    var group: overlay.Siblings = .{};
    try group.add(f.cx, f.scope, f.bar.controls.identity_button, f.host.info.open, f.cx.on(@import("../../../shell/view/status_connection_view.zig").View, f.host.info, @import("../../../shell/view/status_connection_view.zig").View.dismiss));
    source.revision += 1;
    try f.update(source, false);
    const trigger = f.bar.controls.identity_button.globalRect();
    // title-click: hovering the identity opens no card.
    f.cx.handleMouseMove(trigger.x + trigger.w / 2, trigger.y + trigger.h / 2);
    f.settle();
    try std.testing.expect(!f.host.info.open.peek());
    f.click(f.bar.controls.identity_button);
    try std.testing.expect(group.open_entry != null);
    source.revision += 1;
    try f.update(source, false);
    f.cx.handleMouseMove(700, 300);
    f.settle();
    try std.testing.expect(f.host.info.open.peek());
}

test "SSH status host mounts exact live bar geometry and publishes only authoritative metrics" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    try f.update(try snapshot(key, "DB-A"), false);
    const theme_width = f.bar.controls.theme_button.globalRect().w;
    const Item = struct { node: *ui.Node, x: f32, w: f32 };
    for ([_]Item{ .{ .node = f.bar.controls.identity_button, .x = 0, .w = 118 }, .{ .node = f.bar.controls.encoding_button, .x = 124, .w = 68 }, .{ .node = f.bar.controls.grid_button, .x = 198, .w = 82 }, .{ .node = f.bar.chain_trigger, .x = 978 - theme_width, .w = 78 }, .{ .node = f.bar.controls.theme_button, .x = 1146 - theme_width, .w = theme_width } }) |item| {
        const r = item.node.globalRect();
        try std.testing.expectApproxEqAbs(8 + item.x, r.x, 0.1);
        try std.testing.expectEqual(item.w, r.w);
        try std.testing.expectEqual(@as(f32, 26), r.h);
        try std.testing.expectApproxEqAbs(f.bar.controls.identity_button.globalRect().y, r.y, 0.1);
    }
    try std.testing.expectEqualStrings("已连接", f.bar.controls.identity_label.getText().?.content);
    try std.testing.expectEqualStrings("UTF-8", f.bar.controls.encoding_label.getText().?.content);
    try std.testing.expectEqualStrings("120×36", f.bar.grid.getText().?.content);
    try std.testing.expectEqualStrings("—", f.bar.controls.rtt_label.getText().?.content);
    var source = try snapshot(key, "DB-A");
    source.revision = 2;
    source.hops[1].rtt_sample = .{ .request_id = 7, .duration_ms = 17, .started_ns = 1, .completed_ns = 17_000_001, .status = .ready, .cleanup = .released };
    source.target_rtt_sample = source.hops[1].rtt_sample;
    try f.update(source, false);
    try std.testing.expectEqualStrings("17 ms", f.bar.controls.rtt_label.getText().?.content);
    source.hops[1].metadata.cipher_c2s = try D.details.Text(64).init("aes256-ctr");
    source.hops[1].metadata.cipher_s2c = try D.details.Text(64).init("aes128-ctr");
    const captured_info = SSH.infoSnapshot(source, false);
    try std.testing.expectEqual(@as(?u64, 17), captured_info.latency_ms);
    try std.testing.expectEqualStrings("aes256-ctr", captured_info.cipher_c2s.slice());
    try std.testing.expectEqualStrings("aes128-ctr", captured_info.cipher_s2c.slice());
    try std.testing.expect(f.bar.controls.rtt_label.parent == f.bar.controls.identity_button);
    try std.testing.expect(f.bar.controls.rtt_button.style.display == .none);
    try std.testing.expectEqual(@as(usize, 0), f.captures);
}

test "SSH status host identity keyboard capture copies original owner and context switch dismisses without focus theft" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    try f.update(try snapshot(key, "DB-A"), false);
    f.enter(f.bar.controls.identity_button);
    try std.testing.expect(f.host.info.isVisible());
    try std.testing.expectEqualStrings("未知", f.host.info.duration.getText().?.content);
    f.enter(f.host.info.copy_button);
    try std.testing.expect(std.mem.indexOf(u8, f.copied.?, "身份：admin@db.example:22") != null);
    try std.testing.expect(f.last_key.?.eql(key));
    var next = key;
    next.owner.session.session_id = @fromBackingInt(902);
    next.operation_id += 1;
    const pane_focus = try ui.widgets.Button(.{ .label = "新页签" }).mount(f.scope, f.cx);
    try f.cx.root.?.appendChild(a, pane_focus);
    f.cx.setFocus(pane_focus);
    try f.update(try snapshot(next, "DB-B"), false);
    try std.testing.expect(!f.host.info.isVisible());
    try std.testing.expect(f.cx.isFocused(pane_focus));
    f.host.info.copyAddress();
    try std.testing.expectEqual(@as(usize, 1), f.copies);
    f.enter(f.bar.controls.identity_button);
    try std.testing.expect(f.captured.?.key.eql(next));
    try std.testing.expectEqualStrings("DB-B", f.host.info.name.getText().?.content);
}

test "SSH status host metrics remain static and collapsed state follows sidebar" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    try f.update(try snapshot(key, "DB-A"), false);
    for ([_]*ui.Node{ f.bar.controls.encoding_button, f.bar.controls.grid_button, f.bar.controls.rtt_button }) |node| {
        try std.testing.expect(node.behavior.events.on_click == null);
        f.click(node);
        try std.testing.expect(f.host.detail.controller.popover == null);
    }
    try std.testing.expectEqual(.none, f.bar.controls.more_button.style.display);
    f.bar.controls.sidebar_width = 48;
    try f.update(try snapshot(key, "DB-A"), false);
    try std.testing.expectEqual(@as(f32, 118), f.bar.controls.identity_button.globalRect().w);
    try std.testing.expectEqual(.flex, f.bar.controls.identity_label.style.display);
}

test "SSH status host reuses a single actual log modal and keeps its captured key and focus" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    try f.update(try snapshot(key, "DB-A"), false);
    f.enter(f.bar.controls.identity_button);
    f.enter(f.host.info.logs_button);
    try std.testing.expect(f.logs.isVisible());
    try std.testing.expect(!f.host.info.isVisible());
    try std.testing.expect(f.logs.source.?.key.eql(key));
    const focused = f.cx.focus_manager.current_focus orelse return error.NoModalFocus;
    try std.testing.expect(focused.isDescendantOf(f.logs.dialog));
    try std.testing.expectEqual(@as(usize, 1), f.captures);
    f.logs.copyLogs();
    try std.testing.expect(f.last_key.?.eql(key));
    try std.testing.expectEqualStrings("已复制连接日志", f.logs.feedback.getText().?.content);
    try f.logs.retheme();
    f.settle();
    const rebuilt_focus = f.cx.focus_manager.current_focus orelse return error.NoRebuiltModalFocus;
    try std.testing.expect(rebuilt_focus.isDescendantOf(f.logs.dialog));
    f.cx.handleKeyDown(.escape, .{});
    f.settle();
    try std.testing.expect(!f.logs.isVisible());
    try std.testing.expect(f.captured.?.key.eql(key));
}

test "SSH status host keeps captured info read only and the global theme entry" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    try f.update(try snapshot(key, "DB-A"), false);
    f.enter(f.bar.controls.identity_button);
    try std.testing.expect(!f.host.info.logs_disabled.peek());
    try std.testing.expect(id(f.host.info.root, "status.connection.reconnect") == null);
    var source = try snapshot(key, "DB-A");
    source.revision = 2;
    for (source.hops[0..2]) |*hop| hop.status = .released;
    try f.update(source, true);
    f.host.refreshFrozen(source, true);
    try f.host.info.flush();
    f.settle();
    try std.testing.expect(!f.host.info.logs_disabled.peek());
    try std.testing.expectEqual(@as(usize, 0), f.reconnects);
    try f.host.updateActive(null);
    f.settle();
    try std.testing.expect(f.bar.controls.theme_button.style.display == .flex);
    try std.testing.expect(f.bar.controls.more_button.style.display == .none);
    try std.testing.expect(f.bar.controls.chain_button.style.display == .flex);
    try std.testing.expect(f.bar.controls.disabled.peek());
    try std.testing.expect(!f.bar.controls.theme_disabled.peek());
    try f.update(source, true);
    try std.testing.expect(f.bar.controls.theme_button.style.display == .flex);
    f.enter(f.bar.controls.theme_button);
    try std.testing.expectEqual(@as(usize, 1), f.themes);
    try std.testing.expectEqual(f.bar.controls.theme_button, f.last_theme_trigger.?);
}

test "SSH status host projects only the original ready SFTP attachment without terminal capabilities" {
    const sessions = @import("../../../../host/session_host.zig");
    const file_owner: @import("../../../../host/identity.zig").SessionHandle = .{ .session_id = @fromBackingInt(902), .generation = 3 };
    const file_key: D.OperationKey = .{ .owner = .{ .session = file_owner }, .operation_id = 9, .attempt_id = 1 };
    const tab_id: @import("../../../../host/identity.zig").TabId = @fromBackingInt(77);
    const target: sessions.AttachmentTarget = .{ .window_id = @fromBackingInt(1), .workspace_id = @fromBackingInt(1) };
    var source: sessions.SessionSnapshot = .{ .handle = file_owner, .plugin_id = .sftp, .lifecycle = .attached, .target = target, .attachment = .{ .target = target, .tab_id = tab_id }, .create_operation = file_key, .close_operation = null, .create_cleanup = .not_started };
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    try f.update(try snapshot(key, "DB-A"), false);
    f.enter(f.bar.controls.identity_button);
    try std.testing.expect(f.host.info.isVisible());
    const file = try SSH.FileActive.fromSession(file_owner, tab_id, true, source, "VM Files");
    try std.testing.expectEqual(.connected, file.state);
    try std.testing.expect(file.key.?.eql(file_key));
    f.cx.setFocus(f.bar.controls.theme_button);
    try f.host.updateFile(file);
    f.settle();
    try std.testing.expect(!f.host.info.isVisible());
    try std.testing.expect(f.host.active == null);
    try std.testing.expect(f.host.file_active.?.owner.eql(file_owner));
    try std.testing.expectEqual(f.bar.controls.theme_button, f.cx.focus_manager.current_focus.?);
    try std.testing.expectEqualStrings("已连接", f.bar.controls.identity_label.getText().?.content);
    try std.testing.expectEqualStrings("SFTP · 已连接", f.bar.controls.identity_button.behavior.interaction.a11y.?.description.?);
    try std.testing.expectEqualDeep(@import("../../../../shared/ui/theme/app_theme.zig").current().ok, f.bar.controls.state_dot.getIcon().?.tint);
    try std.testing.expectEqualStrings("—", f.bar.controls.rtt_label.getText().?.content);
    try std.testing.expect(f.bar.controls.disabled.peek());
    for ([_]*ui.Node{ f.bar.controls.rtt_button, f.bar.controls.encoding_button, f.bar.controls.grid_button, f.bar.controls.more_button, f.bar.chain_trigger, f.bar.socks_chip, f.bar.controls.icons[0], f.bar.controls.icons[1] }) |node| try std.testing.expectEqual(.none, node.style.display);
    try std.testing.expectEqual(.none, f.bar.controls.file_icon.style.display);
    const rect = f.bar.controls.identity_button.globalRect();
    try std.testing.expectApproxEqAbs(@as(f32, 8), rect.x, 0.1);
    try std.testing.expectApproxEqAbs(@as(f32, 96), rect.w, 0.1);
    try std.testing.expectApproxEqAbs(@as(f32, 26), rect.h, 0.1);
    f.click(f.bar.controls.identity_button);
    try std.testing.expectEqual(@as(usize, 1), f.captures);
    f.enter(f.bar.controls.theme_button);
    try std.testing.expectEqual(@as(usize, 1), f.themes);

    // Same file_ready bit must not paint a replacement generation, mismatched
    // tab, missing domain receipt, or failed lifecycle as connected.
    source.handle.generation += 1;
    try std.testing.expectEqual(.unknown, (try SSH.FileActive.fromSession(file_owner, tab_id, true, source, "VM Files")).state);
    source.handle = file_owner;
    source.attachment.?.tab_id = @fromBackingInt(78);
    try std.testing.expectEqual(.unknown, (try SSH.FileActive.fromSession(file_owner, tab_id, true, source, "VM Files")).state);
    source.attachment.?.tab_id = tab_id;
    try std.testing.expectEqual(.unknown, (try SSH.FileActive.fromSession(file_owner, tab_id, false, source, "VM Files")).state);
    try std.testing.expectEqual(.unknown, (try SSH.FileActive.fromSession(file_owner, tab_id, true, null, "VM Files")).state);
    source.lifecycle = .failed;
    try f.host.updateFile(try SSH.FileActive.fromSession(file_owner, tab_id, true, source, "VM Files"));
    f.settle();
    try std.testing.expectEqualStrings("已断开", f.bar.controls.identity_label.getText().?.content);
    try std.testing.expectEqualStrings("SFTP · 已断开", f.bar.controls.identity_button.behavior.interaction.a11y.?.description.?);
    // copy-terms：断开显示危险色（connection_presenter → status_tone），不再与“未知”同为灰色。
    try std.testing.expectEqualDeep(@import("../../../../shared/ui/theme/app_theme.zig").current().danger, f.bar.controls.state_dot.getIcon().?.tint);

    try f.update(try snapshot(key, "DB-A"), false);
    try std.testing.expect(f.host.file_active == null);
    for ([_]*ui.Node{ f.bar.controls.rtt_label, f.bar.controls.encoding_button, f.bar.controls.grid_button, f.bar.chain_trigger, f.bar.socks_chip }) |node| try std.testing.expectEqual(.flex, node.style.display);
    try std.testing.expectEqual(.none, f.bar.controls.icons[1].style.display);
    try std.testing.expectEqual(.none, f.bar.controls.file_icon.style.display);
    try std.testing.expectEqualStrings("已连接", f.bar.controls.identity_label.getText().?.content);
    try std.testing.expectEqualStrings("UTF-8", f.bar.controls.encoding_label.getText().?.content);
    try std.testing.expectEqualStrings("120×36", f.bar.grid.getText().?.content);
    f.enter(f.bar.controls.identity_button);
    try std.testing.expectEqual(@as(usize, 2), f.captures);
    try std.testing.expect(f.captured.?.key.eql(key));
}

test "SSH status host failed ended and closed lifecycle override unfinished hops and a new generation starts clean" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    var source = try snapshot(key, "failed target");
    try f.update(source, false);
    try std.testing.expectEqualStrings("已连接", f.bar.controls.identity_label.getText().?.content);
    source.hops[0].status = .released;
    source.hops[1].status = .not_attempted;
    for ([_]@FieldType(@import("../../../../host/session_host.zig").SessionSnapshot, "lifecycle"){ .failed, .ended, .closed }) |lifecycle| {
        const active = SSH.Active.fromTerminal(source, null, false).withLifecycle(lifecycle);
        try std.testing.expect(active.ended);
        try f.host.updateActive(active);
        f.settle();
        try std.testing.expectEqualStrings("已断开", f.bar.controls.identity_label.getText().?.content);
        try std.testing.expectEqualStrings("—", f.bar.controls.rtt_label.getText().?.content);
        f.enter(f.bar.controls.identity_button);
        try std.testing.expectEqual(@import("../../../shell/view/status_connection_view.zig").State.disconnected, f.host.info.source.?.state);
        // A later details refresh must not turn the ended lifecycle back into
        // an apparent in-progress connection or depend on retry permission.
        f.host.refreshFrozen(source, false);
        try f.host.info.flush();
        try std.testing.expectEqual(@import("../../../shell/view/status_connection_view.zig").State.disconnected, f.host.info.source.?.state);
        f.host.info.dismiss();
    }
    var reconnect_key = key;
    reconnect_key.owner.session = try key.owner.session.nextGeneration();
    reconnect_key.operation_id += 1;
    var reconnect = try snapshot(reconnect_key, "new generation");
    for (reconnect.hops[0..2]) |*hop| hop.status = .negotiating;
    try f.host.updateActive(SSH.Active.fromTerminal(reconnect, null, false).withLifecycle(.creating));
    f.settle();
    try std.testing.expect(!f.host.active.?.ended);
    try std.testing.expectEqualStrings("连接中", f.bar.controls.identity_label.getText().?.content);
    for (reconnect.hops[0..2]) |*hop| hop.status = .online;
    reconnect.revision += 1;
    try f.host.updateActive(SSH.Active.fromTerminal(reconnect, null, false).withLifecycle(.attached));
    f.settle();
    try std.testing.expectEqualStrings("已连接", f.bar.controls.identity_label.getText().?.content);
}

test "status transfer ticker displays only the filename and retains a plain filename" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    const ticker = try @import("../../../shell/view/status_transfer_view.zig").View.mount(f.cx, f.scope, null);
    try f.bar.progress_slot.appendChild(a, ticker.root);
    const absolute = try a.dupe(u8, "/fixture/远端目录/ticker-one.bin");
    ticker.update(absolute, "25%", "2", 0.25, false);
    a.free(absolute);
    f.settle();
    try std.testing.expectEqualStrings("ticker-one.bin", ticker.name.getText().?.content);
    try std.testing.expectEqualStrings("25%", ticker.percent.getText().?.content);
    ticker.update("普通文件.txt", "50%", "1", 0.5, true);
    f.settle();
    try std.testing.expectEqualStrings("普通文件.txt", ticker.name.getText().?.content);
    try std.testing.expectEqualStrings("50%", ticker.percent.getText().?.content);
    // The fill is a declared share of the track, which spans the button 7 in from each side.
    try std.testing.expectApproxEqAbs(ticker.track.globalRect().w * 0.5, ticker.fill.globalRect().w, 0.1);
    try std.testing.expectApproxEqAbs(ticker.root.globalRect().w - 14, ticker.track.globalRect().w, 0.1);
    ticker.updateSummary(.{ .name = "ubuntucloud_D91D1F2900_20260728225100.tgz", .percent = "72%", .rate = "12.6 MiB/s", .counts = "5", .fraction = 0.72 });
    f.settle();
    try std.testing.expectEqualStrings("12.6 MiB/s", ticker.speed.getText().?.content);
    const percent_bounds = ticker.percent.globalRect();
    const rate_bounds = ticker.speed.globalRect();
    const name_bounds = ticker.name.globalRect();
    try std.testing.expect(name_bounds.x + name_bounds.w <= percent_bounds.x);
    try std.testing.expect(percent_bounds.x + percent_bounds.w <= rate_bounds.x);
    try std.testing.expectEqual(@as(f32, 28), percent_bounds.w);
    try std.testing.expect(rate_bounds.w > 0 and rate_bounds.w < 76);
    ticker.update("传输 · 空闲", "", "", 0, false);
    f.settle();
    const trigger = ticker.root.globalRect();
    const label = ticker.name.globalRect();
    try std.testing.expectEqual(@as(f32, 11), ticker.name.getText().?.font_size);
    try std.testing.expectEqual(.clip, ticker.name.getText().?.text_overflow);
    try std.testing.expect(label.w >= @ceil(f.cx.text.measureTextWidth("传输 · 空闲", 11, 500, false)));
    try std.testing.expect(trigger.w < 140);
    try std.testing.expectApproxEqAbs(@as(f32, 7), trigger.x + trigger.w - label.x - label.w, 0.1);
}

test "SSH chain bottom bar reports online negotiating and disconnected without opening a card" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    const C = @import("../../socks/view/socks_info_styles.zig");
    var source = try snapshot(key, "DB-A");
    try f.update(source, false);
    f.settle();
    try std.testing.expect(!f.host.info.isVisible());
    try std.testing.expectEqualStrings("通信链路", f.bar.controls.chain_label.getText().?.content);
    try std.testing.expectEqual(C.theme.current().fg_1, f.bar.controls.chain_label.getText().?.color);
    for (f.bar.controls.chain_button.children.items) |child| if (child.getIcon()) |icon| {
        try std.testing.expectEqual(C.statusBarInk(C.text(.success)), icon.tint);
    };
    source.hops[source.hop_count - 1].status = .negotiating;
    source.revision += 1;
    try f.update(source, false);
    f.settle();
    try std.testing.expectEqualStrings("通信链路", f.bar.controls.chain_label.getText().?.content);
    try std.testing.expectEqual(C.theme.current().fg_1, f.bar.controls.chain_label.getText().?.color);
    for (f.bar.controls.chain_button.children.items) |child| if (child.getIcon()) |icon| {
        try std.testing.expectEqual(C.statusBarInk(C.text(.warning)), icon.tint);
    };
    try f.host.updateActive(.{ .details = source, .ended = true });
    f.settle();
    try std.testing.expectEqualStrings("通信链路", f.bar.controls.chain_label.getText().?.content);
    try std.testing.expectEqual(C.theme.current().fg_1, f.bar.controls.chain_label.getText().?.color);
    for (f.bar.controls.chain_button.children.items) |child| if (child.getIcon()) |icon| {
        try std.testing.expectEqual(C.statusBarInk(C.text(.danger)), icon.tint);
    };
    try std.testing.expect(!f.host.info.isVisible());
}

test "SSH status theme name follows committed display name and fits long names" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    try f.update(try snapshot(key, "DB-A"), false);
    const controls = f.bar.controls;
    const short_width = controls.theme_button.globalRect().w;
    const long_name = "自定义配色 · Catppuccin Mocha Extended";
    try controls.setThemeName(f.cx, long_name);
    f.settle();
    try std.testing.expectEqualStrings(long_name, controls.theme_label.getText().?.content);
    const button = controls.theme_button.globalRect();
    const label = controls.theme_label.globalRect();
    try std.testing.expect(button.w > short_width);
    try std.testing.expectApproxEqAbs(@as(f32, 27), label.x - button.x, 0.1);
    try std.testing.expectApproxEqAbs(@as(f32, 7), button.x + button.w - label.x - label.w, 0.1);
    try controls.setThemeName(f.cx, "Sauber");
    f.settle();
    try std.testing.expectApproxEqAbs(short_width, controls.theme_button.globalRect().w, 0.1);
}

test "workspace toolbar state updates keep broadcast chain forwarding and theme icon only" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    const Chrome = @import("../../../workspace/view/workspace_chrome.zig");
    const controls = f.bar.controls;
    controls.workspace_chrome = true;
    const tools = try ui.hstack(f.cx, .{ .width = .{ .fit = .{} }, .height = .{ .px = 36 }, .gap = 4 }, .{});
    try f.cx.root.?.appendChild(a, tools);
    const buttons = [_]*ui.Node{ controls.chain_button, controls.socks_button, controls.theme_button, controls.broadcast_button };
    const labels = [_]*ui.Node{ controls.chain_label, controls.forward_label, controls.theme_label, controls.broadcast_label };
    const icons = [_]*ui.Node{ f.bar.chain_icon, controls.icons[6], controls.icons[7], controls.broadcast_icon };
    for (buttons, labels, icons) |button, label, icon| {
        Chrome.iconOnly(f.cx, button, icon, label);
        try Chrome.move(f.cx, tools, button);
    }
    controls.broadcast_button.setDisplay(.flex);
    var source = try snapshot(key, "DB-A");
    for ([_]f32{ 1440, 820, 1100 }) |width| {
        f.cx.setViewport(width, 900);
        for ([_]bool{ false, true, false }, [_]usize{ 0, 128, 0 }) |running, participants| {
            source.revision += 1;
            source.hops[1].status = if (running) .online else .negotiating;
            try f.host.updateActive(.{ .details = source, .ended = !running });
            try controls.setThemeName(f.cx, "自定义配色 · Catppuccin Mocha Extended");
            try controls.setBroadcastState(f.cx, running, participants);
            f.cx.setTheme(if (running) &ui.theme.light else &ui.theme.dark);
            f.settle();
            for (buttons, labels, icons) |button, label, icon| {
                try std.testing.expectEqual(.none, label.style.display);
                // Toolbar icons take zenit's native md icon-only Button square, 32 x 32
                // (shell_styles.toolbar_icon_size), with the 16pt glyph centered.
                try std.testing.expectApproxEqAbs(@as(f32, 32), button.globalRect().w, 0.01);
                try std.testing.expectApproxEqAbs(@as(f32, 32), button.globalRect().h, 0.01);
                const glyph = icon.globalRect();
                try std.testing.expectApproxEqAbs(button.globalRect().x + 8, glyph.x, 0.01);
                try std.testing.expectApproxEqAbs(button.globalRect().y + 8, glyph.y, 0.01);
            }
            try std.testing.expectEqualStrings("", controls.broadcast_label.getText().?.content);
            try std.testing.expectEqual(running, controls.broadcast_button.behavior.interaction.a11y.?.pressed);
            try std.testing.expectEqualStrings(if (running) "组广播 · 已开启 · 查看参与终端" else "组广播 · 已关闭", controls.broadcast_button.behavior.interaction.a11y.?.label.?);
        }
    }
}

test "legacy broadcast status retains participant text across viewport changes" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    const controls = f.bar.controls;
    controls.broadcast_button.setDisplay(.flex);
    try controls.setBroadcastState(f.cx, true, 3);
    f.settle();
    try std.testing.expectEqualStrings("广播 · 3", controls.broadcast_label.getText().?.content);
    try std.testing.expectEqual(.flex, controls.broadcast_label.style.display);
    f.cx.setViewport(820, 900);
    try controls.setBroadcastState(f.cx, true, 3);
    try std.testing.expectEqualStrings("3", controls.broadcast_label.getText().?.content);
    try controls.setBroadcastState(f.cx, false, 0);
    try std.testing.expectEqual(.none, controls.broadcast_label.style.display);
}

test "SSH status host reuses original graphical bar and trims terminal and transfer entries" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    const source = try snapshot(key, "db");
    try fixture.update(source, false);
    const controls = fixture.bar.controls;
    const count = controls.bar.children.items.len;
    try fixture.host.updateGraphical(.{ .state = .online, .label = "视频已连接" });
    fixture.settle();
    try std.testing.expectEqual(count, controls.bar.children.items.len);
    try std.testing.expectEqualStrings("已连接", controls.identity_label.getText().?.content);
    try std.testing.expectEqualStrings("—", controls.rtt_label.getText().?.content);
    for ([_]*ui.Node{ controls.rtt_label, controls.chain_button, controls.theme_button }) |node| try std.testing.expectEqual(.flex, node.style.display);
    for ([_]*ui.Node{ controls.encoding_button, controls.grid_button, controls.socks_button, controls.progress_slot }) |node| try std.testing.expectEqual(.none, node.style.display);
    try fixture.host.updateGraphical(.{ .state = .ended, .label = "已断开" });
    // copy-terms：图形会话正常结束统一叫“已结束”（与页签状态同源）。
    try std.testing.expectEqualStrings("已结束", controls.identity_label.getText().?.content);
    try fixture.update(source, false);
    try std.testing.expectEqual(.flex, controls.chain_button.style.display);
    try std.testing.expectEqual(.flex, controls.progress_slot.style.display);
    try std.testing.expectEqualStrings("已连接", controls.identity_label.getText().?.content);
}

test "SSH status unchanged terminal and graphical projections leave the scene clean" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    for (0..3) |_| {
        try fixture.host.updateActive(null);
        fixture.settle();
    }
    try std.testing.expect(!fixture.cx.hasPendingSceneWork());
    try fixture.host.updateActive(null);
    try std.testing.expect(!fixture.cx.hasPendingSceneWork());
    const source: SSH.Active = .{ .details = try snapshot(key, "db"), .utf8 = true };
    for (0..3) |_| {
        try fixture.host.updateActive(source);
        fixture.settle();
    }
    try fixture.host.updateActive(source);
    try std.testing.expect(!fixture.cx.hasPendingSceneWork());
    for (0..3) |_| {
        try fixture.host.updateGraphical(.{ .state = .online, .label = "视频已连接" });
        fixture.settle();
    }
    try fixture.host.updateGraphical(.{ .state = .online, .label = "视频已连接" });
    try std.testing.expect(!fixture.cx.hasPendingSceneWork());
    try fixture.host.updateGraphical(.{ .state = .ended, .label = "已断开" });
    try std.testing.expectEqualStrings("已结束", fixture.bar.controls.identity_label.getText().?.content);
}

test "status transfer ticker reports an unpainted theme publication until its owner refreshes it" {
    const theme_mod = @import("../../../../shared/ui/theme/app_theme.zig");
    const previous = theme_mod.currentName();
    defer theme_mod.select(previous);
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    const publication = try f.cx.bindState(@import("../../../../shared/ui/theme/theme_publication.zig").ThemePublication, .{});
    publication.publish(f.cx, theme_mod.widgetTheme(theme_mod.currentName()));
    const ticker = try @import("../../../shell/view/status_transfer_view.zig").View.mount(f.cx, f.scope, null);
    try f.bar.progress_slot.appendChild(a, ticker.root);
    ticker.updateSummary(.{ .name = "a.bin", .percent = "10%", .counts = "1", .fraction = 0.1 });
    f.settle();
    try std.testing.expect(!ticker.repaintDue());
    const next: theme_mod.Name = if (previous == .dark) .light else .dark;
    theme_mod.select(next);
    publication.publish(f.cx, theme_mod.widgetTheme(next));
    f.settle();
    // Nothing has refreshed the ticker since the publication: it says so, and its track still has the old tint.
    try std.testing.expect(ticker.repaintDue());
    try std.testing.expect(!ui.Color.eql(ticker.track.getBackground(), theme_mod.current().fg_2.withAlpha(46)));
    ticker.updateSummary(.{ .name = "a.bin", .percent = "10%", .counts = "1", .fraction = 0.1 });
    f.settle();
    try std.testing.expect(!ticker.repaintDue());
    try std.testing.expect(ui.Color.eql(ticker.track.getBackground(), theme_mod.current().fg_2.withAlpha(46)));
}
test "status transfer ticker fits the actual narrow bottom bar and keeps speed before task count" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    while (f.bar.progress_slot.children.items.len > 0) {
        const child = f.bar.progress_slot.children.items[0];
        f.cx.detachChild(f.bar.progress_slot, child);
        f.cx.destroyDetached(child);
    }
    const ticker = try @import("../../../shell/view/status_transfer_view.zig").View.mount(f.cx, f.scope, null);
    try f.bar.progress_slot.appendChild(a, ticker.root);
    ticker.updateSummary(.{ .name = "ubuntucloud_D91D1F2900_20260728225100.tgz", .percent = "72%", .rate = "12.6 MiB/s", .counts = "5", .fraction = 0.72 });
    f.cx.setViewport(860, 480);
    f.bar.bar.setStyleInline(a, .{ .width = .{ .px = 844 }, .inset = .{ .left = .{ .px = 8 }, .top = .{ .px = 440 } } });
    try f.update(try snapshot(key, "ZZ-GPU25"), true);
    const bar = f.bar.bar.globalRect();
    const control = ticker.root.globalRect();
    try std.testing.expect(control.x >= bar.x);
    try std.testing.expect(control.x + control.w <= bar.x + bar.w - 8 + 0.1);
    try std.testing.expect(ticker.speed.globalRect().w > 0 and ticker.speed.globalRect().w < 76);
    try std.testing.expect(ticker.speed.globalRect().x + ticker.speed.globalRect().w <= control.x + control.w);
    const speed = @import("../../../../shared/base/format.zig").liveRate;
    var buffer: [48]u8 = undefined;
    try std.testing.expectEqualStrings("64 B/s", speed(&buffer, 64));
    try std.testing.expectEqualStrings("8 KiB/s", speed(&buffer, 8192));
}

test "SSH status identity click follows the projection: one handler, state decides (terminal card / graphical route), projections never rewrite it" {
    const overlay = @import("../../../../shared/ui/overlay/overlay_host.zig");
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    try f.update(try snapshot(key, "DB-A"), false);
    var group: overlay.Siblings = .{};
    try group.add(f.cx, f.scope, f.bar.controls.identity_button, f.host.info.open, f.cx.on(@import("../../../shell/view/status_connection_view.zig").View, f.host.info, @import("../../../shell/view/status_connection_view.zig").View.dismiss));
    const declared = f.bar.controls.identity_button.behavior.events.on_click.?;
    // Graphical (KVM): the identity opens the route entry, no SSH card.
    try f.host.updateGraphical(.{ .state = .online, .label = "视频已连接" });
    f.click(f.bar.controls.identity_button);
    try std.testing.expectEqual(@as(usize, 1), f.routes);
    try std.testing.expect(!f.host.info.open.peek());
    // File, then terminal again: the same handler, now the connection card.
    try f.host.updateFile(.{ .owner = key.owner.session, .name = try D.details.Text(512).init("VM Files") });
    try f.update(try snapshot(key, "DB-A"), false);
    f.click(f.bar.controls.identity_button);
    try std.testing.expectEqual(@as(usize, 1), f.routes);
    try std.testing.expect(f.host.info.open.peek());
    const now = f.bar.controls.identity_button.behavior.events.on_click.?;
    try std.testing.expect(now.callback == declared.callback and now.context == declared.context);
}

test "SSH status card anchor is handed over explicitly: the chrome's session surface when shown, else the identity button" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    try f.update(try snapshot(key, "DB-A"), false);
    const anchor = f.host.cardAnchor();
    try std.testing.expect(anchor.node() == f.bar.controls.identity_button);
    // A chrome provides the session's surface (a tab): asked every time, never cached here.
    const Chrome = struct {
        tab: ?*ui.Node = null,
        fn resolve(raw: *anyopaque) ?*ui.Node {
            const self: *@This() = @ptrCast(@alignCast(raw));
            return self.tab;
        }
    };
    var chrome: Chrome = .{};
    f.host.setSessionAnchor(.{ .context = &chrome, .resolve = Chrome.resolve });
    try std.testing.expect(anchor.node() == f.bar.controls.identity_button);
    const tab = try ui.box(f.cx, .{ .width = .{ .px = 120 }, .height = .{ .px = 28 } }, .{});
    try f.cx.root.?.appendChild(a, tab);
    chrome.tab = tab;
    try std.testing.expect(anchor.node() == tab);
    // The strip rebuilt the tab: the next question gets the new node.
    const rebuilt = try ui.box(f.cx, .{ .width = .{ .px = 120 }, .height = .{ .px = 28 } }, .{});
    try f.cx.root.?.appendChild(a, rebuilt);
    chrome.tab = rebuilt;
    try std.testing.expect(anchor.node() == rebuilt);
    chrome.tab = null;
    f.host.setSessionAnchor(null);
    f.bar.controls.identity_button.setDisplay(.none);
    try std.testing.expect(anchor.node() == null);
}

test "SSH status click only panel ignores hover toggles and survives refreshed actions" {
    const overlay = @import("../../../../shared/ui/overlay/overlay_host.zig");
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    var source = try snapshot(key, "DB-A");
    try f.update(source, false);
    var group: overlay.Siblings = .{};
    try group.add(f.cx, f.scope, f.bar.controls.identity_button, f.host.info.open, f.cx.on(@import("../../../shell/view/status_connection_view.zig").View, f.host.info, @import("../../../shell/view/status_connection_view.zig").View.dismiss));
    source.revision += 1;
    try f.update(source, false);
    const trigger = f.bar.controls.identity_button.globalRect();
    f.cx.handleMouseMove(trigger.x + trigger.w / 2, trigger.y + trigger.h / 2);
    f.settle();
    try std.testing.expect(!f.host.info.open.peek());
    f.click(f.bar.controls.identity_button);
    try std.testing.expect(f.host.info.open.peek());
    f.cx.handleMouseMove(700, 300);
    f.settle();
    try std.testing.expect(f.host.info.open.peek());
    f.click(f.bar.controls.identity_button);
    try std.testing.expect(!f.host.info.open.peek());
}

test "SSH status card shows the session's current terminal grid while open and when reopened" {
    // The card's facts come from two sources: the connection details (their own revision) and the terminal's
    // display publication (grid, encoding). A resize changes only the latter, so the card must not judge
    // "unchanged" by the details revision alone.
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    const source = try snapshot(key, "DB-A");
    try f.update(source, false);
    f.enter(f.bar.controls.identity_button);
    try std.testing.expect(f.host.info.isVisible());
    try std.testing.expectEqualStrings("120 × 36", f.host.info.grid.getText().?.content);
    // Resized while the card is open: the window's refresh (connection_details_host hook) re-projects the active
    // session and the open card with the same details revision.
    try f.host.updateActive(.{ .details = source, .utf8 = true, .grid = .{ .cols = 66, .rows = 18, .revision = 2 } });
    f.host.refreshFrozen(source, false);
    try f.host.info.flush();
    f.settle();
    try std.testing.expectEqualStrings("66 × 18", f.host.info.grid.getText().?.content);
    try std.testing.expectEqualStrings("66×18", f.bar.controls.grid_label.getText().?.content);
    // Resized while closed: reopening the same session's card shows the grid it has now.
    f.host.info.dismiss();
    f.settle();
    try f.host.updateActive(.{ .details = source, .utf8 = false, .grid = .{ .cols = 80, .rows = 24, .revision = 3 } });
    f.settle();
    f.enter(f.bar.controls.identity_button);
    try std.testing.expect(f.host.info.isVisible());
    try std.testing.expectEqualStrings("80 × 24", f.host.info.grid.getText().?.content);
    try std.testing.expectEqualStrings("未知", f.host.info.encoding.getText().?.content);
}
