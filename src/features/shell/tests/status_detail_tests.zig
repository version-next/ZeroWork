const std = @import("std");
const ui = @import("ui");
const View = @import("../view/status_detail_view.zig").View;

test "status popover mounts real widgets and closes when its captured owner changes" {
    const cx = try ui.Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    cx.viewport.width = 1440;
    cx.viewport.height = 900;
    const root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    cx.root = root;
    const scope = try ui.Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    const trigger = try ui.widgets.Button(.{ .label = "网格" }).mount(scope, cx);
    try root.appendChild(cx.allocator, trigger);
    var context: u8 = 0;
    const view = try View.mount(cx, scope, .{ .context = &context });
    try root.appendChild(cx.allocator, view.root);
    var source: @import("../model/status_controller.zig").Projection = .{ .owner = .{ .session = .{ .session_id = @fromBackingInt(1) } }, .owner_kind = .local, .source_revision = 1, .identity_label = "本地 · zsh", .encoding = .utf8, .grid = .{ .cols = 80, .rows = 24, .revision = 1 } };
    try view.update(source);
    try view.show(.grid, trigger, 860, false);
    try std.testing.expectEqualStrings("终端网格", view.title.getText().?.content);
    try std.testing.expectEqual(@as(f32, 186), view.chrome.style.height.px);
    source.owner.session.generation = 2;
    try view.update(source);
    try std.testing.expect(view.controller.popover == null);
    try std.testing.expect(!view.open.get());
}

test "local close modal keeps captured session and resolves once after user decision" {
    const Close = @import("../../terminal/view/local_close_view.zig");
    const SessionId = @import("../../../host/session_lifecycle.zig").SessionId;
    const Recorder = struct {
        calls: usize = 0,
        id: SessionId = 0,
        accepted: bool = false,
        fn resolve(raw: *anyopaque, id: SessionId, accepted: bool) void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.calls += 1;
            self.id = id;
            self.accepted = accepted;
        }
    };
    const cx = try ui.Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    cx.viewport.width = 1440;
    cx.viewport.height = 900;
    cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    const scope = try ui.Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    var recorder: Recorder = .{};
    const view = try Close.View.mount(cx, scope, .{ .context = &recorder, .resolve = Recorder.resolve });
    try view.show(41, null);
    try std.testing.expectEqualStrings("无法核实本地进程状态", view.risk_title.getText().?.content);
    try std.testing.expectEqual(@as(usize, 0), recorder.calls);
    try std.testing.expectError(error.CloseConfirmationAlreadyOpen, view.show(42, null));
    view.cancel();
    view.cancel();
    try std.testing.expectEqual(@as(usize, 1), recorder.calls);
    try std.testing.expectEqual(@as(SessionId, 41), recorder.id);
    try std.testing.expect(!recorder.accepted);
    try view.show(42, null);
    view.accept();
    try std.testing.expectEqual(@as(usize, 2), recorder.calls);
    try std.testing.expectEqual(@as(SessionId, 42), recorder.id);
    try std.testing.expect(recorder.accepted);
}

test "registry global theme publication preserves RGBA roles beyond three legacy names" {
    const theme = @import("../../../shared/ui/theme/app_theme.zig");
    const previous = theme.currentName();
    defer theme.select(previous);
    var registry = try @import("../../../config/theme_registry.zig").Registry.init(std.testing.allocator);
    defer registry.deinit();
    const record = registry.get("nord").?;
    theme.selectTokens(record.ui_tokens);
    const actual = theme.current();
    try std.testing.expectEqual(@as(u8, @intCast(record.ui_tokens.app >> 24)), actual.app.r);
    try std.testing.expectEqual(@as(u8, 0), actual.app.a);
    try std.testing.expectEqual(@as(u8, @intCast(record.ui_tokens.app & 255)), theme.baseColors().app.a);
    try std.testing.expectEqual(@as(u8, @intCast(record.ui_tokens.selection & 255)), actual.selection.a);
    const widgets = theme.widgetTheme(theme.currentName());
    try std.testing.expectEqual(actual.fg_1, widgets.tokens.color.fg_primary);
    // Text selection is the theme's own opaque role (native Input / Textarea draw it as published).
    try std.testing.expectEqual(@as(u8, 255), widgets.tokens.color.selection_bg.a);
}

test {
    _ = @import("../../terminal/view/local_status_view.zig");
}

const StatusFixture = struct {
    cx: *ui.Cx,
    scope: *ui.Scope,
    trigger: *ui.Node,
    view: *View,
    fn init(self: *StatusFixture) !void {
        const a = std.testing.allocator;
        self.* = .{ .cx = try ui.Cx.init(a, std.testing.io), .scope = undefined, .trigger = undefined, .view = undefined };
        self.cx.setViewport(1440, 900);
        self.cx.root = try ui.box(self.cx, .{ .width = .fill(), .height = .fill() }, .{});
        self.scope = try ui.Scope.init(a, null, self.cx.owner);
        self.trigger = try ui.widgets.Button(.{ .a11y_label = "状态" }).mount(self.scope, self.cx);
        self.trigger.setStyleInline(a, .{ .position = .absolute, .inset = .{ .left = .{ .px = 376 }, .top = .{ .px = 863 } }, .width = .{ .px = 94 }, .height = .{ .px = 26 } });
        try self.cx.root.?.appendChild(a, self.trigger);
        self.view = try View.mount(self.cx, self.scope, .{ .context = self });
        try self.cx.root.?.appendChild(a, self.view.root);
        self.cx.layout();
        _ = self.cx.render();
        try self.view.update(projection());
    }
    fn deinit(self: *StatusFixture) void {
        self.scope.dispose();
        self.cx.deinit();
    }
    fn projection() @import("../model/status_controller.zig").Projection {
        return .{ .owner = .{ .session = .{ .session_id = @fromBackingInt(401), .generation = 1 } }, .owner_kind = .local, .source_revision = 1, .identity_label = "本地 · zsh", .encoding = .utf8, .grid = .{ .cols = 132, .rows = 36, .revision = 1 }, .cwd = "/tmp/ZeroWork" };
    }
    fn settle(self: *StatusFixture) void {
        self.cx.setTestFrameStep(16) catch unreachable;
        for (0..20) |_| {
            self.cx.advanceFrameClock();
            self.cx.layout();
            _ = self.cx.render();
        }
    }
    /// Opened by a click on the trigger (which takes focus): where the native Popover returns focus.
    fn show(self: *StatusFixture, kind: @import("../model/status_controller.zig").Kind, narrow: bool) !void {
        if (self.trigger.behavior.interaction.focusable) self.cx.setFocus(self.trigger);
        try self.view.show(kind, self.trigger, 860, narrow);
        self.settle();
    }
    fn click(self: *StatusFixture, node: *ui.Node) void {
        const r = node.globalRect();
        self.cx.handleMouseDown(r.x + r.w / 2, r.y + r.h / 2, .{});
        self.cx.handleMouseUp(r.x + r.w / 2, r.y + r.h / 2);
    }
};
fn statusText(node: *ui.Node, text: []const u8) bool {
    if (node.getText()) |value| if (std.mem.indexOf(u8, value.content, text) != null) return true;
    for (node.children.items) |child| if (statusText(child, text)) return true;
    return false;
}
fn statusId(node: *ui.Node, id: []const u8) ?*ui.Node {
    if (node.meta.ownership.meta.test_id) |value| if (std.mem.eql(u8, value, id)) return node;
    for (node.children.items) |child| if (statusId(child, id)) |found| return found;
    return null;
}

test "status popover local identity matches the real cwd and original session with shared SSH connection styling" {
    var f: StatusFixture = undefined;
    try f.init();
    defer f.deinit();
    var cwd = [_]u8{ '/', 't', 'm', 'p', '/', 'o', 'w', 'n' };
    var source = StatusFixture.projection();
    source.source_revision = 2;
    source.cwd = &cwd;
    try f.view.update(source);
    cwd[1] = 'x';
    try f.show(.identity, false);
    const r = f.view.chrome.globalRect();
    try std.testing.expectEqual(@as(f32, 380), r.w);
    try std.testing.expectEqual(@as(f32, 272), r.h);
    try std.testing.expectEqual(@as(usize, 7), f.view.rows.children.items.len);
    try std.testing.expect(statusText(f.view.rows, "/tmp/own"));
    try std.testing.expect(statusText(f.view.rows, "会话 #401"));
    try std.testing.expect(statusText(f.view.rows, "本地 · 交互式 Shell"));
    // Pencil lBTBA: panel padding 12. The panel's hairline is zenit's own Popover border, drawn
    // over the edge without insetting the content.
    try std.testing.expectApproxEqAbs(r.y + 52, f.view.rows.children.items[0].globalRect().y, 0.1);
    try std.testing.expect(statusText(f.view.title, "会话详情"));
    try std.testing.expectEqual(@as(u16, 600), f.view.title.getText().?.font_weight);
    // 关闭是共享 PanelClose（原生 ghost sm 图标按钮 24 × 24）。
    const close_button = @import("../../../shared/testing/ui_kit.zig").findByTestId(f.view.chrome, "status.detail.close").?;
    try std.testing.expectEqual(close_button.globalRect().w, close_button.globalRect().h);
    try std.testing.expect(close_button.globalRect().h >= 24 and close_button.globalRect().h <= 26);
    f.cx.setFocus(close_button);
    f.cx.handleKeyDown(.escape, .{});
    f.settle();
    try std.testing.expect(f.view.controller.popover == null);
    try std.testing.expect(f.cx.isFocused(f.trigger));
}

test "status popover grid and encoding use exact live typography row spacing and passive facts" {
    var f: StatusFixture = undefined;
    try f.init();
    defer f.deinit();
    try f.show(.grid, false);
    var r = f.view.chrome.globalRect();
    try std.testing.expectEqual(@as(f32, 186), r.h);
    try std.testing.expectEqual(@as(f32, 32), f.view.rows.children.items[0].globalRect().h);
    const value = f.view.rows.children.items[0].children.items[0];
    try std.testing.expectEqualStrings("132 × 36", value.getText().?.content);
    try std.testing.expectEqual(@as(f32, 18), value.getText().?.font_size);
    try std.testing.expectEqual(@as(u16, 600), value.getText().?.font_weight);
    try std.testing.expect(!value.getText().?.use_monospace_font);
    try std.testing.expectApproxEqAbs(r.y + 46, value.globalRect().y, 0.1);
    try std.testing.expectApproxEqAbs(r.y + 84, f.view.rows.children.items[1].globalRect().y, 0.1);
    try std.testing.expectEqual(@as(u16, 700), f.view.title.getText().?.font_weight);
    f.view.hide();
    try f.show(.encoding, false);
    r = f.view.chrome.globalRect();
    try std.testing.expectEqual(@as(f32, 116), r.h);
    try std.testing.expectEqual(@as(usize, 2), f.view.rows.children.items.len);
    try std.testing.expect(statusText(f.view.rows, "UTF-8"));
    try std.testing.expect(!statusText(f.view.rows, "其他编码"));
    try std.testing.expect(!statusText(f.view.rows, "暂不可用"));
    try std.testing.expectApproxEqAbs(r.y + 78, f.view.rows.children.items[1].globalRect().y, 0.1);
    f.click(f.view.rows.children.items[1]);
    try std.testing.expectEqual(@import("../model/status_controller.zig").Kind.encoding, f.view.controller.popover.?.kind);
}

test "status popover SSH more follows wide and narrow ordering with real metrics and keyboard details" {
    var f: StatusFixture = undefined;
    try f.init();
    defer f.deinit();
    var source = StatusFixture.projection();
    source.source_revision = 2;
    source.owner_kind = .ssh;
    source.identity_label = "K8s-Node01";
    source.rtt = .{ .milliseconds = 17 };
    try f.view.update(source);
    try f.show(.more, false);
    try std.testing.expectEqual(@as(f32, 148), f.view.chrome.globalRect().h);
    try std.testing.expectEqualStrings("status.more.rtt", f.view.rows.children.items[0].meta.ownership.meta.test_id.?);
    try std.testing.expect(statusText(f.view.rows.children.items[0], "17 ms"));
    try std.testing.expect(statusText(f.view.rows.children.items[1], "UTF-8"));
    try std.testing.expect(statusText(f.view.rows.children.items[2], "132×36"));
    const row = statusId(f.view.rows, "status.more.encoding").?;
    f.cx.setFocus(row);
    f.cx.handleKeyDown(.@"return", .{});
    try f.view.flush();
    f.settle();
    try std.testing.expectEqual(@import("../model/status_controller.zig").Kind.encoding, f.view.controller.popover.?.kind);
    try std.testing.expect(f.view.controller.popover.?.owner.eql(source.owner));
    try std.testing.expectEqual(@as(u64, f.trigger.id), f.view.controller.popover.?.trigger);
    f.view.hide();
    try f.show(.more, true);
    // The narrow More list carries no theme row (copy-terms: themes live in 设置 › 外观 only).
    try std.testing.expectEqual(@as(f32, 148), f.view.chrome.globalRect().h);
    try std.testing.expectEqual(@as(usize, 3), f.view.rows.children.items.len);
    try std.testing.expectEqualStrings("status.more.encoding", f.view.rows.children.items[0].meta.ownership.meta.test_id.?);
    try std.testing.expectEqualStrings("status.more.grid", f.view.rows.children.items[1].meta.ownership.meta.test_id.?);
    try std.testing.expectEqualStrings("status.more.rtt", f.view.rows.children.items[2].meta.ownership.meta.test_id.?);
    try std.testing.expect(statusId(f.view.rows, "status.more.theme") == null);
}

test "status popover local more has no fictitious RTT and rejects late old owner actions" {
    var f: StatusFixture = undefined;
    try f.init();
    defer f.deinit();
    try f.show(.more, true);
    try std.testing.expectEqual(@as(usize, 2), f.view.rows.children.items.len);
    try std.testing.expect(statusId(f.view.rows, "status.more.rtt") == null);
    try std.testing.expect(statusId(f.view.rows, "status.more.theme") == null);
    const original_grid = statusId(f.view.rows, "status.more.grid").?;
    f.click(original_grid);
    try f.view.flush();
    f.settle();
    try std.testing.expectEqual(@import("../model/status_controller.zig").Kind.grid, f.view.controller.popover.?.kind);
    f.view.hide();
    try f.show(.more, true);
    const original_encoding = statusId(f.view.rows, "status.more.encoding").?;
    var source = StatusFixture.projection();
    source.owner.session.generation = 2;
    try f.view.update(source);
    _ = f.cx.dispatcher.dispatch(.{ .click = .{ .x = 0, .y = 0 } }, original_encoding);
    try std.testing.expect(f.view.controller.popover == null);
    try std.testing.expect(!f.view.open.peek());
}

test "status popover More carries no theme entry at any width" {
    var f: StatusFixture = undefined;
    try f.init();
    defer f.deinit();
    try f.show(.more, true);
    try std.testing.expect(statusId(f.view.rows, "status.more.theme") == null);
    f.view.hide();
    try std.testing.expect(!f.view.open.peek());
    try f.show(.more, false);
    try std.testing.expectEqual(@as(usize, 2), f.view.rows.children.items.len);
    try std.testing.expectEqual(@as(f32, 116), f.view.chrome.globalRect().h);
}

test "status popover local status keyboard triggers retain the selected generation" {
    const Local = @import("../../terminal/view/local_status_view.zig");
    const Recorder = struct {
        view: *Local.View = undefined,
        kind: ?@import("../model/status_controller.zig").Kind = null,
        owner: ?@import("../../../host/identity.zig").SessionHandle = null,
        fn detail(raw: *anyopaque, kind: @import("../model/status_controller.zig").Kind, _: *ui.Node) void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.kind = kind;
            self.owner = self.view.currentOwner();
        }
    };
    var f: StatusFixture = undefined;
    try f.init();
    defer f.deinit();
    var recorder: Recorder = .{};
    const view = try Local.View.mount(f.cx, f.scope, .{ .context = &recorder, .detail = Recorder.detail });
    recorder.view = view;
    try f.cx.root.?.appendChild(std.testing.allocator, view.root);
    var value: Local.Update = .{ .owner = .{ .session_id = @fromBackingInt(401), .generation = 1 }, .source_revision = 1, .cwd = "/tmp/ZeroWork", .encoding = .utf8, .grid = .{ .cols = 132, .rows = 36, .revision = 1 } };
    try view.update(value);
    f.cx.layout();
    const Trigger = struct { node: *ui.Node, kind: @import("../model/status_controller.zig").Kind };
    for ([_]Trigger{.{ .node = view.identity_button, .kind = .identity }}) |trigger| {
        f.cx.setFocus(trigger.node);
        f.cx.handleKeyDown(.@"return", .{});
        try std.testing.expectEqual(trigger.kind, recorder.kind.?);
        try std.testing.expect(recorder.owner.?.eql(value.owner));
    }
    value.owner.generation = 2;
    try view.update(value);
    f.cx.setFocus(view.identity_button);
    f.cx.handleKeyDown(.@"return", .{});
    try std.testing.expect(recorder.owner.?.eql(value.owner));
    try std.testing.expectEqual(@as(u64, 2), recorder.owner.?.generation);
}

test "status popover numeric samples and anchors retain rows icons and callbacks" {
    var f: StatusFixture = undefined;
    try f.init();
    defer f.deinit();
    var p = StatusFixture.projection();
    p.source_revision = 2;
    p.rtt = .{ .milliseconds = 1 };
    p.owner_kind = .ssh;
    try f.view.update(p);
    try f.view.show(.rtt, f.trigger, 860, false);
    f.settle();
    const row = f.view.rows.children.items[0].id;
    const icon = f.view.header_icon.children.items[0].id;
    const epoch = f.view.root.ownedTreeStructureRevision();
    for (3..123) |i| {
        p.source_revision = i;
        p.rtt.?.milliseconds = i;
        try f.view.update(p);
        try f.view.flush();
    }
    try std.testing.expectEqual(row, f.view.rows.children.items[0].id);
    try std.testing.expectEqual(icon, f.view.header_icon.children.items[0].id);
    try std.testing.expectEqual(epoch, f.view.root.ownedTreeStructureRevision());
    try std.testing.expectEqualStrings("122 ms", f.view.labels.items[1].getText().?.content);
}

test "status popover closed by Escape returns focus only when it was inside the card" {
    const cx = try ui.Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    cx.bindFrameClock();
    cx.viewport.width = 1440;
    cx.viewport.height = 900;
    const root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    cx.root = root;
    const scope = try ui.Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    const trigger = try ui.widgets.Button(.{ .label = "会话连接" }).mount(scope, cx);
    try root.appendChild(cx.allocator, trigger);
    // Stand-in for the terminal input that keeps keyboard focus while the card is a hover preview.
    const terminal = try ui.widgets.Button(.{ .label = "terminal" }).mount(scope, cx);
    try root.appendChild(cx.allocator, terminal);
    var context: u8 = 0;
    const view = try View.mount(cx, scope, .{ .context = &context });
    try root.appendChild(cx.allocator, view.root);
    const source: @import("../model/status_controller.zig").Projection = .{ .owner = .{ .session = .{ .session_id = @fromBackingInt(1) } }, .owner_kind = .local, .source_revision = 1, .identity_label = "本地 · zsh", .encoding = .utf8, .grid = .{ .cols = 80, .rows = 24, .revision = 1 } };
    try view.update(source);
    const settle = struct {
        fn run(c: *ui.Cx) void {
            for (0..12) |_| {
                c.advanceFrameClock();
                c.layout();
                _ = c.render();
            }
        }
    }.run;
    // Hover preview: focus stays on the terminal after Escape closes the card.
    cx.setFocus(terminal);
    try view.show(.grid, trigger, 860, false);
    settle(cx);
    cx.handleKeyDown(.escape, .{});
    settle(cx);
    try std.testing.expect(!view.open.get());
    try std.testing.expectEqual(terminal, cx.focus_manager.current_focus.?);
    // Keyboard use: focus inside the card goes back to its trigger.
    cx.setFocus(trigger);
    try view.show(.grid, trigger, 860, false);
    settle(cx);
    cx.setFocus(view.chrome);
    cx.handleKeyDown(.escape, .{});
    settle(cx);
    try std.testing.expect(!view.open.get());
    try std.testing.expectEqual(trigger, cx.focus_manager.current_focus.?);
}
