//! Actual modal/widgets plus the production journal; no window or network.
const std = @import("std");
const ui = @import("ui");
const P = @import("../view/connection_progress_view.zig");
const F = @import("../model/failure_view.zig");
const Auth = @import("../../auth/view/auth_challenge_view.zig");
const ssh = @import("../../../../proto/ssh/session.zig");
const theme = @import("../../../../shared/ui/theme/app_theme.zig");
const a = std.testing.allocator;

test "idle connection progress hide does not request another frame" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    f.view.hide();
    f.cx.needs_redraw = false;
    f.view.hide();
    try std.testing.expect(!f.cx.needs_redraw);
    try std.testing.expectEqual(@as(usize, 0), f.cancellations);
}
const key: P.OperationKey = .{ .owner = .{ .session = .{ .session_id = @fromBackingInt(33), .generation = 1 } }, .operation_id = 12, .attempt_id = 1 };
const direct = [_]P.Hop{.{ .name = "DB", .host = "db.example", .user = "admin" }};
const route = [_]P.Hop{ .{ .name = "Bastion-01", .host = "b1.example", .user = "ops" }, .{ .name = "Bastion-02", .host = "b2.example", .user = "ops" }, direct[0] };

test "connection progress focus uses zenit's native focus ring and never repaints the fill" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    const publication = try f.cx.bindState(@import("../../../shell/view/shell_styles.zig").ThemePublication, .{});
    publication.publish(f.cx, theme.widgetTheme(theme.currentName()));
    try f.show(f.snapshot(&direct));
    try f.cx.setTestFrameStep(16);
    const settle = struct {
        fn run(cx: *ui.Cx) void {
            for (0..20) |_| {
                cx.advanceFrameClock();
                cx.layout();
                _ = cx.render();
            }
        }
    }.run;
    settle(f.cx);
    const resting = f.view.toggle_button.getBackground();
    // Pointer focus: no ring, no fill change.
    f.cx.focus_manager.setFocusWithReason(f.view.toggle_button, .click);
    settle(f.cx);
    try std.testing.expectEqual(resting, f.view.toggle_button.getBackground());
    // Keyboard focus: zenit's ring in the focus_ring role, fill unchanged.
    f.cx.focus_manager.setFocusWithReason(f.view.toggle_button, .tab);
    settle(f.cx);
    try std.testing.expectEqual(resting, f.view.toggle_button.getBackground());
    f.record(0, 1, .transport, .started);
    try f.show(f.snapshot(&direct));
    settle(f.cx);
    try std.testing.expectEqual(resting, f.view.toggle_button.getBackground());
    try std.testing.expect(!ui.Color.eql(f.view.cancel_button.?.getBackground(), f.view.footer.getBackground()));
    // Native md secondary Button (zenit default size).
    try std.testing.expectEqual(@as(f32, 32), f.view.cancel_button.?.globalRect().h);
}

test "connection progress full values survive updates and keyboard tooltips close with their modal" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    const hops = [_]P.Hop{.{ .name = "Production database with a long name", .user = "operations-administrator", .host = "2001:db8:1234:5678:abcd:ef01:2345:6789", .port = 2222 }};
    try f.show(f.snapshot(&hops));
    const full = "Production database with a long name\noperations-administrator@[2001:db8:1234:5678:abcd:ef01:2345:6789]:2222";
    try std.testing.expectEqualStrings(full, f.view.identity_tip_label.getText().?.content);
    // 头部关闭是共享 PanelClose（原生 Tooltip“关闭 · Esc”）；进行中“关闭即取消连接”写在底栏说明与无障碍名里。
    try std.testing.expectEqualStrings("关闭窗口将取消本次连接", f.view.footer_hint.getText().?.content);
    try std.testing.expectEqualStrings("", f.view.log_help.getText().?.content);
    try std.testing.expectEqualStrings("关闭窗口将取消本次连接", f.view.header_close.?.behavior.interaction.a11y.?.label.?);
    const copy = f.view.copy_icon.?.parent.?;
    copy.behavior.events.on_focus.?.invoke();
    try std.testing.expect(f.view.action_tips[0].open.?.peek());
    try std.testing.expectEqualStrings("复制连接日志，日志不含凭据", f.view.action_tips[0].content.children.items[0].getText().?.content);
    copy.behavior.events.on_blur.?.invoke();
    try std.testing.expect(!f.view.action_tips[0].open.?.peek());
    copy.behavior.events.on_focus.?.invoke();
    const slot = &f.view.slots[1];
    slot.node.behavior.events.on_focus.?.invoke();
    try std.testing.expect(slot.tip_open.peek());
    // A progress update replaces the owned snapshot while focus stays on the row.
    f.record(0, 1, .transport, .started);
    try f.show(f.snapshot(&hops));
    try std.testing.expectEqualStrings(full, slot.tip_label.getText().?.content);
    try std.testing.expectEqualStrings(full, slot.node.behavior.interaction.a11y.?.label.?);
    try std.testing.expect(slot.tip_open.peek());
    slot.node.behavior.events.on_blur.?.invoke();
    try std.testing.expect(!slot.tip_open.peek());
    slot.node.behavior.events.on_focus.?.invoke();
    f.view.identity_tip_open.set(true);
    f.view.hide();
    try std.testing.expect(!slot.tip_open.peek());
    try std.testing.expect(!f.view.identity_tip_open.peek());
    try std.testing.expect(!f.view.action_tips[0].open.?.peek());
    var failed = f.snapshot(&hops);
    failed.state = .failed;
    failed.cleanup = .releasing;
    try f.show(failed);
    try std.testing.expectEqualStrings("关闭连接结果", f.view.header_close.?.behavior.interaction.a11y.?.label.?);
    try std.testing.expectEqualStrings("正在结束上一次连接…", f.view.footer_hint.getText().?.content);
}

test "connection progress passive tooltips do not take Escape: with a row tooltip open one Escape cancels the connection" {
    // The hop row, identity and action tooltips are passive explanations (`close_on_escape = false`): Escape is
    // the card's cancel / close action even while one of them is showing (a single Escape cancels the connection).
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    const hops = [_]P.Hop{ .{ .name = "Jump", .user = "ops", .host = "jump.example", .port = 22 }, .{ .name = "Production database with a long name", .user = "operations-administrator", .host = "2001:db8::1", .port = 2222 } };
    f.record(0, 2, .transport, .started);
    try f.show(f.snapshot(&hops));
    const slot = &f.view.slots[1];
    f.cx.setFocus(slot.node);
    slot.node.behavior.events.on_focus.?.invoke();
    f.view.identity_tip_open.set(true);
    f.cx.advanceFrameClock();
    _ = f.cx.render();
    try std.testing.expect(f.cx.isFocused(slot.node));
    try std.testing.expect(slot.tip_open.peek());
    try std.testing.expect(f.view.identity_tip_open.peek());
    f.cx.handleKeyDown(.escape, .{});
    try std.testing.expectEqual(@as(usize, 1), f.cancellations);
    try std.testing.expectEqual(key, f.last_key.?);
}

const Fixture = struct {
    cx: *ui.Cx,
    scope: *ui.Scope,
    view: *P.View,
    journal: P.progress.Journal = .{},
    cancellations: usize = 0,
    retries: usize = 0,
    closes: usize = 0,
    copies: usize = 0,
    copied: ?[]u8 = null,
    copy_error: bool = false,
    edits: usize = 0,
    editable: bool = true,
    stops: usize = 0,
    retry_now_calls: usize = 0,
    trusts: usize = 0,
    rejects: usize = 0,
    last_key: ?P.OperationKey = null,
    fn init(self: *Fixture) !void {
        self.* = .{ .cx = try ui.Cx.init(a, std.testing.io), .scope = undefined, .view = undefined };
        self.cx.setViewport(1440, 900);
        self.cx.root = try ui.box(self.cx, .{ .width = .fill(), .height = .fill() }, .{});
        self.scope = try ui.Scope.init(a, null, self.cx.owner);
        self.view = try P.View.mount(self.cx, self.scope, .{ .context = self, .cancel = cancel, .retry = retry, .close = close, .copy_logs = copy });
        self.journal.begin(1);
    }
    fn deinit(self: *Fixture) void {
        self.scope.dispose();
        self.cx.deinit();
        if (self.copied) |text| a.free(text);
    }
    fn cancel(raw: *anyopaque, captured: P.OperationKey) void {
        const self: *Fixture = @ptrCast(@alignCast(raw));
        self.cancellations += 1;
        self.last_key = captured;
    }
    fn retry(raw: *anyopaque, captured: P.OperationKey) !void {
        const self: *Fixture = @ptrCast(@alignCast(raw));
        self.retries += 1;
        self.last_key = captured;
    }
    fn close(raw: *anyopaque, captured: P.OperationKey) void {
        const self: *Fixture = @ptrCast(@alignCast(raw));
        self.closes += 1;
        self.last_key = captured;
    }
    fn copy(raw: *anyopaque, captured: P.OperationKey, text: []const u8) !void {
        const self: *Fixture = @ptrCast(@alignCast(raw));
        if (self.copy_error) return error.ClipboardUnavailable;
        const owned = try a.dupe(u8, text);
        if (self.copied) |old| a.free(old);
        self.copied = owned;
        self.copies += 1;
        self.last_key = captured;
    }
    fn edit(raw: *anyopaque, captured: P.OperationKey) void {
        const self: *Fixture = @ptrCast(@alignCast(raw));
        self.edits += 1;
        self.last_key = captured;
    }
    fn canEdit(raw: *anyopaque, _: P.OperationKey) bool {
        const self: *Fixture = @ptrCast(@alignCast(raw));
        return self.editable;
    }
    fn stopRetry(raw: *anyopaque, _: P.OperationKey) !void {
        const self: *Fixture = @ptrCast(@alignCast(raw));
        self.stops += 1;
    }
    fn retryNow(raw: *anyopaque, _: P.OperationKey) !void {
        const self: *Fixture = @ptrCast(@alignCast(raw));
        self.retry_now_calls += 1;
    }
    fn trustKey(raw: *anyopaque, _: P.OperationKey) !void {
        const self: *Fixture = @ptrCast(@alignCast(raw));
        self.trusts += 1;
    }
    fn rejectKey(raw: *anyopaque, _: P.OperationKey) void {
        const self: *Fixture = @ptrCast(@alignCast(raw));
        self.rejects += 1;
    }
    fn record(self: *Fixture, hop: usize, count: usize, phase: P.progress.Phase, status: P.progress.Status) void {
        self.journal.record(.{ .attempt = self.journal.attempt, .timestamp_ns = @as(i128, @intCast(self.journal.count)) * 50 * std.time.ns_per_ms, .hop = hop, .hop_count = count, .host = if (count == 1 or (count == 2 and hop == 1)) direct[0].host else route[hop].host, .port = 22, .phase = phase, .status = status, .failure = if (status == .failed) error.AuthenticationFailed else null });
    }
    fn snapshot(self: *Fixture, hops: []const P.Hop) P.Snapshot {
        return .{ .key = key, .hops = hops, .journal = self.journal.snapshot(), .local_ready = true };
    }
    fn show(self: *Fixture, source: P.Snapshot) !void {
        try self.view.show(source);
        self.cx.layout();
    }
};

test "connection progress view direct and routed facts keep the current hop distinct from waiting nodes" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    f.record(0, 1, .transport, .started);
    try f.show(f.snapshot(&direct));
    try std.testing.expectEqual(@as(usize, 2), f.view.slot_count);
    try std.testing.expectEqualStrings("admin@db.example:22", f.view.endpoint.getText().?.content);
    try std.testing.expectEqualStrings("TCP 连接中", f.view.slots[1].status.getText().?.content);
    // Island B v3 iY0Iz: a 580 card centred on the session pane.
    try std.testing.expectEqual(@as(f32, 580), f.view.dialog.globalRect().w);
    try std.testing.expectEqual(@as(f32, 358), f.view.dialog.globalRect().h);
    try std.testing.expectEqualStrings("第 1 次尝试", f.view.attempt.getText().?.content);
    try std.testing.expectEqual(@as(f32, 68), f.view.identity_chip.globalRect().w);
    try std.testing.expectEqual(@as(f32, 20), f.view.identity_chip.globalRect().h);
    try std.testing.expect(f.view.attempt.globalRect().w >= 64);
    try std.testing.expectEqual(@as(f32, 16), f.view.attempt.globalRect().h);
    try std.testing.expect(f.view.root.parent != null);
    try std.testing.expectEqualStrings("DB", f.view.title.getText().?.content);
    for (f.view.slots[0..f.view.slot_count]) |slot| {
        const r = slot.node.globalRect();
        try std.testing.expectApproxEqAbs(r.x + 34, slot.name.globalRect().x, 0.01);
        // AlEHs: 44 row; name 16 over address 15 (gap 1) centred; status centred.
        try std.testing.expectApproxEqAbs(@as(f32, 44), r.h, 0.01);
        try std.testing.expectApproxEqAbs(r.y + 6, slot.name.globalRect().y, 0.01);
        try std.testing.expectApproxEqAbs(r.y + 23, slot.endpoint.globalRect().y, 0.01);
        try std.testing.expectApproxEqAbs(@as(f32, 22), slot.marker_box.globalRect().w, 0.01);
        try std.testing.expectEqual(ui.types.Display.none, slot.user.style.display);
        try std.testing.expectApproxEqAbs(r.y + 14, slot.status.globalRect().y, 0.01);
    }
    try std.testing.expect(f.view.footer_hint.globalRect().x >= f.view.footer.globalRect().x);
    try std.testing.expectApproxEqAbs(f.view.cancel_button.?.globalRect().x + f.view.cancel_button.?.globalRect().w / 2, f.view.cancel_label.?.globalRect().x + f.view.cancel_label.?.globalRect().w / 2, 0.01);
    try std.testing.expectEqual(@as(f32, 16), f.view.copy_icon.?.globalRect().w);
    f.view.cancel();
    f.view.cancel();
    try std.testing.expectEqual(@as(usize, 1), f.cancellations);
    try std.testing.expect(f.last_key.?.eql(key));
    var other = f.snapshot(&direct);
    other.key.owner.session.session_id = @fromBackingInt(999);
    try std.testing.expectError(error.ProgressOwnerMismatch, f.view.show(other));
}

test "connection progress view failed attempt uses the failure view and retry waits for release facts" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    f.record(0, 3, .ready, .succeeded);
    f.record(1, 3, .authentication, .failed);
    var source = f.snapshot(&route);
    source.state = .failed;
    source.cleanup = .releasing;
    var ledger = try ssh.ResourceLedger.init(key, 3);
    _ = ledger.record(key, 0, .session, .owned);
    source.resources = ledger.snapshot();
    try f.show(source);
    // design-r3 稿 1: the failure replaces the progress card in the pane.
    try std.testing.expect(f.view.failureMode());
    try std.testing.expectEqual(ui.types.Display.none, f.view.dialog.style.display);
    try std.testing.expectEqual(ui.types.Display.flex, f.view.failure.?.root.style.display);
    var p = f.view.failure.?.projection.peek();
    try std.testing.expectEqual(F.Kind.authentication, p.kind);
    try std.testing.expectEqualStrings("Bastion-02 拒绝了认证", p.title);
    try std.testing.expectEqualStrings("服务器不接受 ops 的认证信息", p.alert_title);
    try std.testing.expectEqualStrings("连接路径 · 2 级跳板", p.route);
    try std.testing.expectEqualStrings("已就绪", p.hops[0].status);
    try std.testing.expectEqualStrings("已连通", p.hops[1].status);
    try std.testing.expectEqualStrings("认证失败", p.hops[2].status);
    try std.testing.expectEqualStrings("未连接", p.hops[3].status);
    try std.testing.expect(!p.retry_shown and !p.stop_retry);
    try std.testing.expectEqualStrings("不自动重试：请先修改认证方式或重新输入凭据", p.hold_text);
    try std.testing.expect(p.retry_disabled);
    for (p.hops) |hop| try std.testing.expect(std.mem.indexOf(u8, hop.status, "释放") == null);
    f.view.retry();
    try std.testing.expectEqual(@as(usize, 0), f.retries);
    f.view.close();
    try std.testing.expect(f.view.isVisible());
    try std.testing.expectEqual(@as(usize, 0), f.closes);
    _ = ledger.record(key, 0, .session, .unknown);
    source.cleanup = .unknown;
    source.resources = ledger.snapshot();
    try f.show(source);
    f.view.retry();
    try std.testing.expectEqual(@as(usize, 0), f.retries);
    try std.testing.expect(std.mem.indexOf(u8, f.view.resource_text.getText().?.content, "待核实") != null);
    _ = ledger.record(key, 0, .session, .released);
    source.cleanup = .released;
    source.resources = ledger.snapshot();
    try f.show(source);
    f.cx.layout();
    p = f.view.failure.?.projection.peek();
    try std.testing.expect(!p.retry_disabled and p.retry_now);
    // The column stays inside the pane, primary action on the trailing edge.
    const column = f.view.failure.?.root.globalRect();
    const retry_now = findId(f.view.failure.?.root, "connection.progress.failure.retry_now").?;
    const edit = findId(f.view.failure.?.root, "connection.progress.failure.logs.toggle").?;
    try std.testing.expect(retry_now.globalRect().w > 0);
    try std.testing.expect(edit.globalRect().x < retry_now.globalRect().x);
    try std.testing.expect(retry_now.globalRect().x + retry_now.globalRect().w <= column.x + column.w);
    // "查看日志" expands the attempt's own log lines inside the view.
    clickNode(&f, edit);
    try std.testing.expect(f.view.failure.?.projection.peek().logs_open);
    try std.testing.expectEqualStrings("收起日志", f.view.failure.?.projection.peek().logs_label);
    try std.testing.expect(f.view.failure.?.projection.peek().log_lines.len == 2);
    clickNode(&f, retry_now);
    clickNode(&f, retry_now);
    try std.testing.expectEqual(@as(usize, 1), f.retries);
    try std.testing.expect(f.last_key.?.eql(key));
}

test "connection progress failure view counts down a pending automatic retry and stops or starts it on request" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    f.view.callbacks.stop_retry = Fixture.stopRetry;
    f.view.callbacks.retry_now = Fixture.retryNow;
    f.record(0, 1, .transport, .failed);
    var source = f.snapshot(&direct);
    source.state = .retrying;
    source.failure = .{ .hop = 0, .phase = .transport, .reason = P.failureText(error.ConnectionRefused), .err = error.ConnectionRefused };
    const delays = [_]i128{ 500 * std.time.ns_per_ms, 1000 * std.time.ns_per_ms };
    source.retry = .{ .next_attempt = 2, .limit = 3, .remaining_ns = 250 * std.time.ns_per_ms, .delay_ns = 500 * std.time.ns_per_ms, .delays_ns = &delays };
    try f.show(source);
    try std.testing.expect(f.view.failureMode());
    const p = f.view.failure.?.projection.peek();
    try std.testing.expectEqual(F.Kind.refused, p.kind);
    try std.testing.expectEqualStrings("db.example:22 拒绝连接", p.alert_title);
    try std.testing.expectEqualStrings("自动重试 · 第 2 次 / 共 3 次 · 1 秒后开始 · 间隔 0.5 → 1 秒", p.retry_text);
    try std.testing.expectApproxEqAbs(@as(f32, 50), p.retry_percent, 0.01);
    try std.testing.expect(p.stop_retry and p.retry_now and !p.credentials);
    f.cx.layout();
    try std.testing.expect(findId(f.view.failure.?.root, "connection.progress.failure.retry.bar").?.globalRect().w > 0);
    clickNode(&f, findId(f.view.failure.?.root, "connection.progress.failure.retry_now").?);
    try std.testing.expectEqual(@as(usize, 1), f.retry_now_calls);
    try std.testing.expectEqual(@as(usize, 0), f.retries);
    clickNode(&f, findId(f.view.failure.?.root, "connection.progress.failure.stop").?);
    try std.testing.expectEqual(@as(usize, 1), f.stops);
}

test "connection progress failure view answers a changed host key in place with both fingerprints" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    f.view.callbacks.trust_host_key = Fixture.trustKey;
    f.view.callbacks.reject_host_key = Fixture.rejectKey;
    f.record(0, 1, .host_key, .started);
    var source = f.snapshot(&direct);
    source.state = .waiting_host_key;
    source.failure = .{ .hop = 0, .phase = .host_key, .reason = "" };
    source.host_key = .{ .saved_algorithm = "ssh-ed25519", .saved_fingerprint = "SHA256:saved", .offered_algorithm = "ssh-ed25519", .offered_fingerprint = "SHA256:offered" };
    try f.show(source);
    const p = f.view.failure.?.projection.peek();
    try std.testing.expectEqual(F.Kind.host_key_changed, p.kind);
    try std.testing.expectEqualStrings("SHA256:saved", p.saved_key);
    try std.testing.expectEqualStrings("SHA256:offered", p.offered_key);
    try std.testing.expect(p.trust_key and p.disconnect and !p.retry_now);
    f.cx.layout();
    // 替换主机密钥 is irreversible: the button opens the shared native confirmation first.
    clickNode(&f, findId(f.view.failure.?.root, "connection.progress.failure.trust").?);
    try std.testing.expectEqual(@as(usize, 0), f.trusts);
    try std.testing.expect(f.view.failure.?.trust_confirm.peek());
    // 取消 keeps the old key.
    f.view.failure.?.trust_confirm.set(false);
    try std.testing.expectEqual(@as(usize, 0), f.trusts);
    // The confirmation's 替换主机密钥 hands the replacement to the host.
    f.view.failure.?.act(.trust_key);
    f.view.failure.?.trustConfirmed();
    try std.testing.expectEqual(@as(usize, 1), f.trusts);
    try std.testing.expect(!f.view.failure.?.trust_confirm.peek());
    clickNode(&f, findId(f.view.failure.?.root, "connection.progress.failure.disconnect").?);
    try std.testing.expectEqual(@as(usize, 1), f.rejects);
}

fn clickNode(f: *Fixture, node: *ui.Node) void {
    f.cx.layout();
    const rect = node.globalRect();
    f.cx.handleClick(rect.x + rect.w / 2, rect.y + rect.h / 2);
    f.cx.handleMouseUpEx(rect.x + rect.w / 2, rect.y + rect.h / 2, .left, .{});
}
fn findId(node: *ui.Node, id: []const u8) ?*ui.Node {
    if (node.meta.ownership.meta.test_id) |value| if (std.mem.eql(u8, value, id)) return node;
    for (node.children.items) |child| if (findId(child, id)) |found| return found;
    return null;
}

test "connection progress view protocol completion does not close before the exact attached receipt" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    f.record(0, 1, .ready, .succeeded);
    var source = f.snapshot(&direct);
    source.state = .protocol_ready;
    try f.show(source);
    try std.testing.expect(f.view.isVisible());
    try std.testing.expect(f.view.open.peek());
    source.attached = true;
    try f.show(source);
    try std.testing.expect(!f.view.isVisible());
    try std.testing.expect(!f.view.open.peek());
}

test "connection progress view copies only owned real diagnostics and rejects stale attempts or another owner history" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    f.record(0, 1, .transport, .started);
    const previous = f.snapshot(&direct);
    const old_record: P.LogRecord = .{ .key = key, .entry = previous.journal.entries[0] };
    var new_key = key;
    new_key.attempt_id = 2;
    new_key.operation_id += 1;
    f.journal.begin(2);
    f.record(0, 1, .transport, .started);
    var records = [_]P.LogRecord{ old_record, .{ .key = new_key, .entry = f.journal.snapshot().entries[0] } };
    var source = f.snapshot(&direct);
    source.key = new_key;
    source.state = .retrying;
    source.logs = &records;
    source.dropped = 4;
    try f.show(source);
    records[0].entry.host[0] = 'x';
    f.view.copyLogs();
    try std.testing.expectEqual(@as(usize, 1), f.copies);
    try std.testing.expect(f.last_key.?.eql(new_key));
    try std.testing.expect(std.mem.indexOf(u8, f.copied.?, "尝试 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, f.copied.?, "尝试 2") != null);
    try std.testing.expect(std.mem.indexOf(u8, f.copied.?, "db.example") != null);
    try std.testing.expectEqualStrings("已复制连接日志", f.view.log_help.getText().?.content);
    try f.show(source);
    try std.testing.expectEqualStrings("已复制连接日志", f.view.log_help.getText().?.content);
    f.copy_error = true;
    f.view.copyLogs();
    try std.testing.expectEqualStrings("复制失败，请重试", f.view.log_help.getText().?.content);
    try f.show(source);
    try std.testing.expectEqualStrings("复制失败，请重试", f.view.log_help.getText().?.content);
    try std.testing.expectError(error.StaleProgress, f.view.show(previous));
    records[0].key.owner.session.session_id = @fromBackingInt(999);
    try std.testing.expectError(error.InvalidLogOwner, f.view.show(source));
}

test "connection progress view cancellation keeps its original modal until release and then closes without another cancel" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    f.record(0, 1, .transport, .started);
    var source = f.snapshot(&direct);
    try f.show(source);
    f.view.close();
    try std.testing.expectEqual(@as(usize, 1), f.cancellations);
    try std.testing.expect(f.view.operationKey().?.eql(key));
    source.state = .cancelled;
    source.cleanup = .releasing;
    try f.show(source);
    f.view.close();
    try std.testing.expect(f.view.isVisible());
    try std.testing.expectEqual(@as(usize, 0), f.closes);
    source.cleanup = .released;
    try f.show(source);
    try std.testing.expectEqualStrings("DB", f.view.title.getText().?.content);
    try std.testing.expectEqualStrings("连接已取消", f.view.summary_title.getText().?.content);
    f.view.close();
    try std.testing.expect(!f.view.isVisible());
    try std.testing.expect(f.view.operationKey() == null);
    try std.testing.expectEqual(@as(usize, 1), f.cancellations);
    try std.testing.expectEqual(@as(usize, 1), f.closes);
    try std.testing.expect(f.last_key.?.eql(key));
}

test "connection progress view original modal routes inline IME Escape once and preserves the field on update and theme" {
    const Recorder = struct {
        bridge: Auth.auth.InteractiveBridge = .{},
        cancelled: usize = 0,
        fn submit(raw: *anyopaque, id: Auth.auth.RequestIdentity, reply: Auth.auth.Reply) !void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            try self.bridge.submit(id, reply);
        }
        fn cancel(raw: *anyopaque, id: Auth.auth.RequestIdentity) void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            if (self.bridge.cancelRequest(id)) self.cancelled += 1;
        }
    };
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    f.record(0, 1, .authentication, .started);
    var source = f.snapshot(&direct);
    source.state = .waiting_auth;
    source.inline_authentication = true;
    try f.show(source);
    var recorder: Recorder = .{};
    const auth = try Auth.View.mount(f.cx, f.scope, .{ .context = &recorder, .submit = Recorder.submit, .cancel = Recorder.cancel });
    try f.view.authentication_area.appendChild(a, auth.root);
    _ = try recorder.bridge.offerChallenge(.{ .key = key, .kind = .keyboard_interactive, .hop_index = 0, .endpoint_identity = .{ .host = direct[0].host, .user = direct[0].user }, .prompts = &.{.{ .text = "Response:", .echo = true }}, .presentation = .protected_form, .presentation_config_revision = 1 });
    try auth.show(recorder.bridge.snapshot().?);
    f.cx.layout();
    const input = auth.fields[0].input.state;
    f.cx.setFocus(auth.fields[0].input.input_container);
    f.cx.handleTextInput("answer");
    _ = input.setAccessibilitySelection(1, 3);
    f.cx.handleImePreedit("pin", 3);
    const cursor = input.cursor_pos;
    const anchor = input.selection_anchor;
    try f.show(source);
    f.view.toggleLogs();
    const previous_theme = theme.currentName();
    defer theme.select(previous_theme);
    for ([_]theme.Name{ .dark, .light, .sauber }) |name| {
        theme.select(name);
        f.cx.setTheme(theme.widgetTheme(name));
        try f.view.retheme();
        try auth.retheme();
        // Submit is a native primary Button: its label is zenit's (resolveTextProps is the
        // layout+paint resolution) and the primary foreground is zenit's default role.
        const primary_fg = theme.zenitDefaults(name).tokens.color.button_primary_fg;
        const submit_label = struct {
            fn find(node: *ui.Node) ?*ui.Node {
                if (node.getText() != null) return node;
                for (node.children.items) |child| if (find(child)) |found| return found;
                return null;
            }
        }.find(auth.submit_button).?;
        if (!auth.submit_button.behavior.interaction.a11y.?.disabled)
            try std.testing.expectEqual(primary_fg, submit_label.resolveTextProps().?.color);
        // Retry is unavailable while authentication waits: zenit's ControlShell :disabled
        // state paints its label with fg-disabled (Island B v3 disabled action), not the
        // primary foreground.
        try std.testing.expect(f.view.retry_button.?.behavior.interaction.a11y.?.disabled);
        try std.testing.expectEqual(f.cx.tokens.tokens.color.fg_disabled, f.view.retry_label.?.resolveTextProps().?.color);
        // Island B v3 i7VdGA: progress content sits on the focused island surface.
        try std.testing.expectEqual(theme.widgetTheme(theme.currentName()).tokens.color.zw_island_focus, f.view.dialog.getBackground());
    }
    try std.testing.expectEqual(input, auth.fields[0].input.state);
    try std.testing.expect(auth.isComposing());
    try std.testing.expectEqual(cursor, input.cursor_pos);
    try std.testing.expectEqual(anchor, input.selection_anchor);
    try std.testing.expect(auth.modal == null);
    try std.testing.expect(f.cx.isFocused(auth.fields[0].input.input_container));
    f.cx.handleKeyDown(.escape, .{});
    try std.testing.expect(!auth.isComposing());
    try std.testing.expectEqual(@as(usize, 0), recorder.cancelled);
    try std.testing.expectEqual(@as(usize, 0), f.cancellations);
    try std.testing.expect(f.view.open.peek());
    f.cx.handleKeyDown(.escape, .{});
    try std.testing.expectEqual(@as(usize, 1), recorder.cancelled);
    try std.testing.expectEqual(@as(usize, 0), f.cancellations);
}

test "connection progress view all routed variants use their actual current node and downstream waiting" {
    const cases = [_]struct { count: usize, current: usize, phase: P.progress.Phase }{
        .{ .count = 2, .current = 0, .phase = .authentication },
        .{ .count = 3, .current = 1, .phase = .authentication },
        .{ .count = 2, .current = 1, .phase = .transport },
    };
    for (cases) |case| {
        var f: Fixture = undefined;
        try f.init();
        defer f.deinit();
        const hops: []const P.Hop = if (case.count == 3) &route else &.{ route[0], direct[0] };
        for (0..case.current) |hop| f.record(hop, case.count, .ready, .succeeded);
        f.record(case.current, case.count, case.phase, .started);
        try f.show(f.snapshot(hops));
        try std.testing.expectEqualStrings(hops[case.current].name, f.view.slots[case.current + 1].name.getText().?.content);
        try std.testing.expect(std.mem.indexOf(u8, f.view.slots[case.current + 1].status.getText().?.content, P.phaseName(case.phase)) != null);
        for (case.current + 1..case.count) |hop| try std.testing.expectEqualStrings("等待上游", f.view.slots[hop + 1].status.getText().?.content);
        for (0..case.current) |hop| try std.testing.expectEqualStrings("已认证", f.view.slots[hop + 1].status.getText().?.content);
    }
}

test "connection progress view log follow pauses on scroll new rows stay pending and compact footer remains reachable" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    try f.cx.setTestFrameStep(16);
    const hops = [_]P.Hop{ route[0], direct[0] };
    for ([_]P.progress.Phase{ .transport, .handshake, .host_key, .authentication, .ready }) |phase| {
        f.record(0, 2, phase, .started);
        f.record(0, 2, phase, .succeeded);
    }
    for ([_]P.progress.Phase{ .transport, .handshake, .host_key, .authentication }) |phase| {
        f.record(1, 2, phase, .started);
        f.record(1, 2, phase, .succeeded);
    }
    f.record(1, 2, .shell, .started);
    try f.show(f.snapshot(&hops));
    f.view.toggleLogs();
    f.cx.advanceFrameClock();
    _ = f.cx.render();
    const scroll = f.view.logs_scroll;
    try std.testing.expect(scroll.state.maxScrollY() > 0);
    try std.testing.expectApproxEqAbs(scroll.state.maxScrollY(), scroll.state.scroll_y, 0.01);
    ui.widgets.scroll_area.setScrollY(scroll.state, scroll.content, 0);
    f.cx.requestRedraw();
    f.cx.advanceFrameClock();
    _ = f.cx.render();
    try std.testing.expect(!f.view.following);
    f.record(1, 2, .shell, .succeeded);
    try f.show(f.snapshot(&hops));
    f.cx.advanceFrameClock();
    _ = f.cx.render();
    try std.testing.expectEqual(@as(f32, 0), scroll.state.scroll_y);
    try std.testing.expectEqual(@as(usize, 1), f.view.new_logs);
    f.view.jumpToBottom();
    try std.testing.expectApproxEqAbs(scroll.state.maxScrollY(), scroll.state.scroll_y, 0.01);
    const choose = f.view.slots[1].node.behavior.events.on_click.?;
    choose.callback(choose.context);
    try std.testing.expectEqual(@as(?usize, 0), f.view.filter);
    try std.testing.expect(f.view.log_row_count != 0);
    for (f.view.log_rows[0..f.view.log_row_count]) |row| {
        try std.testing.expect(std.mem.indexOf(u8, row.text.getText().?.content, "b1.example") != null);
        try std.testing.expect(std.mem.indexOf(u8, row.text.getText().?.content, "db.example") == null);
    }
    choose.callback(choose.context);
    try std.testing.expect(f.view.filter == null);
    f.cx.setViewport(860, 480);
    try f.show(f.snapshot(&hops));
    // Disclosure height and Modal entrance animate. Assert the compact layout
    // after both finish, using virtual frames rather than wall-clock sleeps.
    for (0..60) |_| {
        f.cx.requestRedraw();
        f.cx.advanceFrameClock();
        _ = f.cx.render();
        if (!f.view.logs_disclosure.animating and !f.cx.overlay_stack.hasActiveAnimations()) break;
    }
    try std.testing.expect(!f.view.logs_disclosure.animating);
    try std.testing.expect(!f.cx.overlay_stack.hasActiveAnimations());
    // The compact 480 pane keeps a 24 inset around the card: 480 − 48.
    try std.testing.expectEqual(@as(f32, 432), f.view.dialog.globalRect().h);
    try std.testing.expectApproxEqAbs(f.view.dialog.globalRect().y + f.view.dialog.globalRect().h, f.view.footer.globalRect().y + f.view.footer.globalRect().h, 0.01);
    try std.testing.expect(f.view.dialog.globalRect().y >= 8);
    try std.testing.expect(f.view.footer.globalRect().y + f.view.footer.globalRect().h <= 472);
}

test "connection progress viewport width changes preserve reachable actions at unchanged height" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    f.record(0, 1, .transport, .started);
    try f.show(f.snapshot(&direct));
    f.cx.advanceFrameClock();
    _ = f.cx.render();
    const before_height = f.view.dialog.globalRect().h;
    f.cx.setViewport(700, 900);
    f.cx.advanceFrameClock();
    _ = f.cx.render();
    try std.testing.expect(f.view.dialog.globalRect().w <= 684);
    try std.testing.expect(f.view.dialog.globalRect().h <= before_height);
    f.cx.setViewport(620, 900);
    f.cx.advanceFrameClock();
    _ = f.cx.render();
    try std.testing.expect(f.view.dialog.globalRect().w <= 604);
    const panel = f.view.dialog.globalRect();
    const cancel = f.view.cancel_button.?.globalRect();
    try std.testing.expect(cancel.x >= panel.x and cancel.x + cancel.w <= panel.x + panel.w);
}

test "SFTP progress snapshot refresh fits a bounded UI stack and retains owned diagnostics" {
    const Worker = struct {
        failure: ?anyerror = null,
        fn run(self: *@This()) void {
            self.check() catch |err| {
                self.failure = err;
            };
        }
        fn check(_: *@This()) !void {
            const f = try a.create(Fixture);
            defer a.destroy(f);
            try f.init();
            defer f.deinit();
            const snapshot = try a.create(P.Snapshot);
            defer a.destroy(snapshot);
            f.record(0, 1, .transport, .started);
            snapshot.* = .{ .key = key, .hops = &direct, .journal = f.journal.snapshot(), .file_session = true, .activity = "正在读取 SFTP 初始目录…", .local_ready = true };
            for (0..16) |_| try f.view.show(snapshot.*);
            snapshot.journal.entries[0].host[0] = 'x';
            try std.testing.expectEqualStrings("db.example", f.view.source.?.value.journal.entries[0].hostSlice());
            try std.testing.expect(f.view.isVisible());
        }
    };
    var worker: Worker = .{};
    // Budget: new zenit's Yix/template view emission makes the Debug mount of this
    // view (ControlShell Buttons) need between 2.5 and 3 MiB on its own (2 and 2.5 MiB
    // overflow inside Button mount, connection_progress_view.zig:382). 3 MiB leaves under
    // 512 KiB of headroom, less than two by-value journal copies (P.Snapshot is
    // ~305 KiB). Production UI runs on the 8 MiB main thread. panel-heads: the header
    // close is the shared PanelClose (Tooltip + Button template), one more nested Yix
    // component render in the same mount; 3 MiB overflowed, so the budget is 4 MiB.
    const thread = try std.Thread.spawn(.{ .stack_size = 4 * 1024 * 1024 }, Worker.run, .{&worker});
    thread.join();
    if (worker.failure) |err| return err;
}

test "SFTP progress keeps failure code and permits retry only after actual cleanup" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    f.record(0, 1, .transport, .started);
    var snapshot = f.snapshot(&direct);
    snapshot.file_session = true;
    snapshot.activity = "正在读取 SFTP 初始目录…";
    try f.show(snapshot);
    try std.testing.expect(f.view.isVisible());
    try std.testing.expect(f.view.header_spinner.style.display == .flex);
    snapshot.state = .failed;
    snapshot.failure = .{ .reason = "服务器拒绝 SFTP 子系统（SftpSubsystemDenied）" };
    snapshot.cleanup = .releasing;
    try f.show(snapshot);
    try std.testing.expect(f.view.header_spinner.style.display == .none);
    f.view.retry();
    try std.testing.expectEqual(@as(usize, 0), f.retries);
    snapshot.cleanup = .released;
    try f.show(snapshot);
    try std.testing.expect(std.mem.indexOf(u8, f.view.summary_detail.getText().?.content, "SftpSubsystemDenied") != null);
    f.view.copyLogs();
    try std.testing.expectEqual(@as(usize, 1), f.copies);
    f.view.retry();
    try std.testing.expectEqual(@as(usize, 1), f.retries);
}

test "material connection progress native diagnostics are owned, filtered, copied and dismissed with their attempt" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    var raw = "handshake failed rc=-13 libssh2_code=-13 message=Failed getting banner".*;
    f.journal.record(.{ .attempt = 1, .hop = 1, .hop_count = route.len, .host = route[1].host, .port = 22, .phase = .handshake, .status = .failed, .failure = error.SshHandshakeDisconnected, .diagnostic = &raw });
    var source = f.snapshot(&route);
    source.state = .failed;
    source.cleanup = .released;
    try f.show(source);
    @memset(&raw, 'x');
    f.view.toggleLogs();
    const row = &f.view.log_rows[0];
    try std.testing.expect(row.node.behavior.events.on_click == null);
    row.node.behavior.events.on_hover.?.invoke();
    const expected = "尝试 1 · 第 2 跳 · SSH 握手\n时间未知 - handshake failed rc=-13 libssh2_code=-13 message=Failed getting banner - —\n";
    try std.testing.expectEqualStrings(expected, f.view.diagnostic_text.getText().?.content);
    try std.testing.expect(f.view.diagnostic_open.peek());
    // Portal chrome owns the only material fill. Its content must not add an
    // independent overlay or a perimeter line on top of that alpha.
    try std.testing.expectEqual(ui.Color.TRANSPARENT, f.view.diagnostic_panel.getBackground());
    try std.testing.expectEqual(@as(f32, 0), f.view.diagnostic_panel.style.border.width);
    f.view.copyLogs();
    try std.testing.expect(std.mem.indexOf(u8, f.copied.?, "libssh2_code=-13") != null);
    // A different hop must never show this failure's diagnostic bubble.
    f.view.slots[3].node.behavior.events.on_click.?.invoke();
    try std.testing.expectEqual(@as(usize, 0), f.view.log_row_count);
    try std.testing.expect(!f.view.diagnostic_open.peek());
    f.view.slots[2].node.behavior.events.on_click.?.invoke();
    f.view.log_rows[0].node.behavior.events.on_hover.?.invoke();
    try std.testing.expectEqualStrings(expected, f.view.diagnostic_text.getText().?.content);
    f.view.log_rows[0].node.behavior.events.on_leave.?.invoke();
    try std.testing.expect(!f.view.diagnostic_open.peek());
    f.view.log_rows[0].node.behavior.events.on_hover.?.invoke();
    f.view.hide();
    try std.testing.expect(!f.view.diagnostic_open.peek());
    f.journal.begin(2);
    source = f.snapshot(&route);
    source.key.attempt_id = 2;
    source.key.operation_id += 1;
    try f.show(source);
    try std.testing.expectEqual(@as(usize, 0), f.view.log_row_count);
}

test "connection progress hover shows only the original diagnostic for that failed history row" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    f.record(0, 1, .handshake, .failed);
    var first: P.LogRecord = .{ .key = key, .entry = f.journal.snapshot().entries[0] };
    first.entry.diagnostic.format("{s}", .{"first attempt native error"});
    var next = key;
    next.attempt_id = 2;
    next.operation_id += 1;
    f.journal.begin(2);
    f.record(0, 1, .handshake, .failed);
    var second: P.LogRecord = .{ .key = next, .entry = f.journal.snapshot().entries[0] };
    second.entry.diagnostic.format("{s}", .{"second attempt native error"});
    const records = [_]P.LogRecord{ first, second };
    var source = f.snapshot(&direct);
    source.key = next;
    source.logs = &records;
    try f.show(source);
    f.view.toggleLogs();
    f.view.log_rows[0].node.behavior.events.on_hover.?.invoke();
    try std.testing.expect(std.mem.indexOf(u8, f.view.diagnostic_text.getText().?.content, "first attempt native error") != null);
    f.view.log_rows[1].node.behavior.events.on_hover.?.invoke();
    try std.testing.expect(std.mem.indexOf(u8, f.view.diagnostic_text.getText().?.content, "second attempt native error") != null);
    f.view.log_rows[0].node.behavior.events.on_leave.?.invoke();
    try std.testing.expect(f.view.diagnostic_open.peek());
    // An unchanged snapshot must preserve the hovered row and its pending bubble.
    try f.show(source);
    try std.testing.expect(f.view.diagnostic_open.peek());
    f.view.toggleLogs();
    try std.testing.expect(!f.view.diagnostic_open.peek());
}

test "connection progress failed card offers edit connection only for an editable host" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    f.view.callbacks.edit = Fixture.edit;
    f.view.callbacks.can_edit = Fixture.canEdit;
    // While connecting, ybb2B's 编辑连接 is not offered.
    f.record(0, 1, .transport, .started);
    try f.show(f.snapshot(&direct));
    try std.testing.expectEqual(ui.types.Display.none, f.view.edit_button.?.style.display);
    // Failed (design-r3 稿 1): the failure view leads its actions with it.
    f.record(0, 1, .transport, .failed);
    var failed = f.snapshot(&direct);
    failed.state = .failed;
    failed.cleanup = .released;
    try f.show(failed);
    f.cx.layout();
    const edit = findId(f.view.failure.?.root, "connection.progress.failure.edit").?;
    const retry_now = findId(f.view.failure.?.root, "connection.progress.failure.retry_now").?;
    try std.testing.expect(edit.globalRect().w > 0);
    try std.testing.expect(edit.globalRect().x < retry_now.globalRect().x);
    clickNode(&f, edit);
    try std.testing.expectEqual(@as(usize, 1), f.edits);
    try std.testing.expect(f.last_key.?.eql(key));
    // Editing neither dismisses the result nor retries.
    try std.testing.expect(f.view.isVisible());
    try std.testing.expectEqual(@as(usize, 0), f.retries);
    // The host was deleted: the button hides on the next frame and is inert.
    f.editable = false;
    for (0..3) |_| f.cx.layout();
    _ = f.cx.render();
    f.cx.layout();
    try std.testing.expect(!f.view.failure.?.projection.peek().can_edit);
    try std.testing.expectEqual(@as(f32, 0), edit.globalRect().w);
    f.view.edit();
    try std.testing.expectEqual(@as(usize, 1), f.edits);
}
