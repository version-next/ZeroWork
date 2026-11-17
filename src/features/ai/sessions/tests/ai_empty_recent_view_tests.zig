//! Welcome uses the same phase, binding and icon action contract as history.
const std = @import("std");
const ui = @import("ui");
const V = @import("../view/ai_empty_view.zig");
const theme = @import("../../../../shared/ui/theme/app_theme.zig");
const a = std.testing.allocator;
const titles = [_][]const u8{
    "请检查 Nginx 服务的 error 日志，解释这个 SSH 连接超时问题，并给出每一步的排查方法与处理建议 Please inspect the complete application error log and explain the connection timeout in detail",
    "👩🏽‍💻 检查宽字符 ＡＢＣＤＥＦＧ 与中文日志 🧑‍🚀🚀🌍，保留整个原始问题并检查所有错误信息，尤其是终端输出中的启动失败 👩🏽‍💻 检查宽字符 ＡＢＣＤＥＦＧ 与中文日志 🧑‍🚀🚀🌍",
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789",
};
/// zenit Tooltip opens after its 500ms hover delay (was 200) and then fades in;
/// 16 settles of four 16ms frames cover both.
const tooltip_settles = 16;
const Fixture = struct {
    cx: *ui.Cx,
    scope: *ui.Scope,
    /// The window's conversation phases the recent rows follow.
    phases: *@import("../model/view_model.zig").SessionPhases = undefined,
    view: *ui.Node,
    clicks: usize = 0,
    selected: ?u64 = null,
    last_action: ?@import("../view/ai_session_row.zig").Action = null,
    fn init(self: *Fixture, title: []const u8) !void {
        self.* = .{ .cx = try ui.Cx.init(a, std.testing.io), .scope = undefined, .view = undefined };
        self.cx.setViewport(600, 276);
        self.cx.setTheme(theme.widgetTheme(theme.currentName()));
        self.cx.root = try ui.box(self.cx, .{ .width = .fill(), .height = .fill(), .direction = .column, .padding = .{ .left = 14, .right = 14 } }, .{});
        self.scope = try ui.Scope.init(a, null, self.cx.owner);
        self.phases = try @import("../model/view_model.zig").SessionPhases.mount(self.scope, a, null);
        self.view = try V.mount(self.cx, self.scope, true, .{ .context = self, .summarize = ignore, .logs = ignore, .settings = ignore, .ollama = ignore, .session_hooks = .{ .context = self, .select = select, .request_close = select, .remove = select, .act = act, .phases = self.phases }, .recent = &.{ .{ .id = 17, .title = title, .owner = "1 · Local Terminal", .phase = .running, .bound = true, .can_copy = true, .can_remove = false }, .{ .id = 29, .title = "普通短标题", .owner = "历史连接环境", .phase = .stopped, .can_restore = true, .can_copy = true }, .{ .id = 30, .title = "不应显示第三条", .owner = "" } } });
        try self.cx.root.?.appendChild(a, self.view);
        self.settle();
    }
    fn deinit(self: *Fixture) void {
        self.cx.clearFocus();
        self.scope.dispose();
        self.cx.deinit();
    }
    fn select(raw: *anyopaque, id: u64) void {
        const self: *Fixture = @ptrCast(@alignCast(raw));
        self.clicks += 1;
        self.selected = id;
    }
    fn act(raw: *anyopaque, id: u64, action: @import("../view/ai_session_row.zig").Action) void {
        const self: *Fixture = @ptrCast(@alignCast(raw));
        self.last_action = action;
        select(raw, id);
    }
    fn ignore(_: *anyopaque) void {}
    fn settle(self: *Fixture) void {
        self.cx.setTestFrameStep(16) catch unreachable;
        for (0..4) |_| {
            self.cx.advanceFrameClock();
            // The app frame loop lays out before painting; viewport resizes and
            // truncation (tooltip eligibility) are measured from that layout.
            self.cx.layout();
            _ = self.cx.render();
        }
    }
    fn node(self: *Fixture, id: []const u8) *ui.Node {
        return find(self.cx.root.?, id) orelse @panic("missing recent test node");
    }
    fn clickAt(self: *Fixture, x: f32, y: f32) void {
        self.cx.handleMouseDown(x, y, .{});
        self.cx.handleMouseUp(x, y);
        self.settle();
    }
    fn expectBounds(self: *Fixture) !void {
        const view = self.view.globalRect();
        const group = self.node("ai.empty.recent").globalRect();
        const row = self.node("ai.session.row.17").globalRect();
        const label = self.node("ai.session.title");
        const title = label.globalRect();
        const tag = self.node("ai.session.phase_tag").globalRect();
        const first = self.node("ai.session.first_line").globalRect();
        const second = self.node("ai.session.second_line").globalRect();
        try std.testing.expect(group.x >= view.x and group.x + group.w <= view.x + view.w + 0.1);
        try std.testing.expectApproxEqAbs(group.w, row.w, 0.1);
        try std.testing.expectApproxEqAbs(@as(f32, 63), row.h, 0.1); // O7 row: 8 + 19 + 4 + 24 + 8 (native xs buttons)
        try std.testing.expect(title.x + title.w <= tag.x);
        try std.testing.expectApproxEqAbs(first.x + first.w, tag.x + tag.w, 0.1);
        try std.testing.expect(first.y + first.h <= second.y);
        try std.testing.expectEqual(ui.types.TextOverflow.ellipsis, label.getText().?.text_overflow);
        try std.testing.expectEqual(ui.TextWrap.none, label.getText().?.wrap);
        try std.testing.expect(label.style.overflow_hidden);
        try std.testing.expect(title.w > 0 and title.h == 19); // O7: title 12.5/500, line 19
        for ([_][]const u8{ "ai.session.jump.17", "ai.session.locate.17", "ai.session.copy_use.17" }) |id| {
            const action = self.node(id).globalRect();
            // O7: native ghost xs icon buttons (square, zenit size).
            try std.testing.expect(action.w <= 24 and action.w > 18);
            try std.testing.expectApproxEqAbs(action.w, action.h, 0.1);
            try std.testing.expect(action.x + action.w <= second.x + second.w + 0.1);
            try std.testing.expect(action.y >= second.y and action.y + action.h <= second.y + second.h + 0.1);
        }
    }
};
fn find(node: *ui.Node, id: []const u8) ?*ui.Node {
    if (node.meta.ownership.meta.test_id) |value| if (std.mem.eql(u8, value, id)) return node;
    for (node.children.items) |child| if (find(child, id)) |result| return result;
    return null;
}
fn text(node: *ui.Node) []const u8 {
    if (node.getText()) |value| return value.content;
    for (node.children.items) |child| {
        const value = text(child);
        if (value.len > 0) return value;
    }
    return "";
}
test "AI welcome recent long mixed wide and unbroken titles stay bounded after resize and theme replay" {
    const previous = theme.currentName();
    defer theme.select(previous);
    for (titles) |title| {
        var f: Fixture = undefined;
        try f.init(title);
        defer f.deinit();
        for ([_]theme.Name{ .dark, .light, .sauber }) |name| {
            theme.select(name);
            f.cx.setTheme(theme.widgetTheme(name));
            for ([_]f32{ 360, 480, 600 }) |width| {
                f.cx.setViewport(width, 276);
                f.settle();
                try f.expectBounds();
                try std.testing.expectEqualStrings(title, text(f.node("ai.session.title")));
                const wrapper = f.node("ai.session.title").parent.?.parent.?;
                wrapper.behavior.events.on_hover.?.invoke();
                for (0..tooltip_settles) |_| f.settle();
                const tooltip = f.node("ai.session.title.tooltip");
                try std.testing.expect(tooltip.getOpacity() > 0.99);
                try std.testing.expect(tooltip.globalRect().w <= width - 16);
                try std.testing.expectEqualStrings(title, text(tooltip));
                wrapper.behavior.events.on_leave.?.invoke();
                for (0..5) |_| f.settle();
            }
        }
    }
}
test "AI welcome recent title tooltip only opens for truncated text and closes when it fits" {
    var f: Fixture = undefined;
    try f.init("检查当前服务器状态并分析最近的应用错误日志");
    defer f.deinit();
    const title = f.node("ai.session.title");
    const wrapper = title.parent.?.parent.?;
    wrapper.behavior.events.on_hover.?.invoke();
    for (0..8) |_| f.settle();
    try std.testing.expect(find(f.cx.root.?, "ai.session.title.tooltip") == null);

    f.cx.setViewport(240, 276);
    f.settle();
    wrapper.behavior.events.on_hover.?.invoke();
    for (0..tooltip_settles) |_| f.settle();
    try std.testing.expect(f.node("ai.session.title.tooltip").getOpacity() > 0.99);

    f.cx.setViewport(600, 276);
    for (0..8) |_| f.settle();
    try std.testing.expect(find(f.cx.root.?, "ai.session.title.tooltip") == null);
    wrapper.behavior.events.on_leave.?.invoke();
    wrapper.behavior.events.on_hover.?.invoke();
    for (0..8) |_| f.settle();
    try std.testing.expect(find(f.cx.root.?, "ai.session.title.tooltip") == null);
}
test "AI welcome recent actions preserve history semantics and phase updates" {
    var f: Fixture = undefined;
    try f.init(titles[0]);
    defer f.deinit();
    try std.testing.expect(find(f.view, "ai.session.row.30") == null);
    try std.testing.expect(find(f.view, "ai.session.restore.17") == null);
    try std.testing.expectEqual(@as(@TypeOf(f.node("ai.session.delete.17").style.display), .none), f.node("ai.session.delete.17").style.display);
    const row = f.node("ai.session.row.17").globalRect();
    f.clickAt(row.x + 10, row.y + 10);
    try std.testing.expectEqual(@as(usize, 0), f.clicks);
    inline for (.{ "jump", "locate", "copy_use" }, .{ .view, .locate, .copy_use }) |action, expected| {
        const button = f.node("ai.session." ++ action ++ ".17");
        const rect = button.globalRect();
        f.clickAt(rect.x + rect.w / 2, rect.y + rect.h / 2);
        try std.testing.expectEqual(expected, f.last_action.?);
        try std.testing.expectEqual(@as(?u64, 17), f.selected);
    }
    const restore = f.node("ai.session.restore.29");
    f.cx.setFocus(restore);
    f.cx.handleKeyDown(.@"return", .{});
    f.settle();
    try std.testing.expectEqual(@import("../view/ai_session_row.zig").Action.restore, f.last_action.?);
    try std.testing.expectEqual(@as(?u64, 29), f.selected);
    const remove = f.node("ai.session.delete.29").globalRect();
    f.clickAt(remove.x + remove.w / 2, remove.y + remove.h / 2);
    try std.testing.expectEqual(@as(usize, 5), f.clicks);
    inline for (.{ .idle, .running, .approval, .done, .failed, .stopped }, .{ "未开始", "运行中", "待确认", "已完成", "失败", "已暂停" }) |phase, label| {
        f.phases.publish(17, phase);
        f.settle();
        try std.testing.expectEqualStrings(label, text(f.node("ai.session.phase_tag")));
    }
}

test "AI welcome starters are native block Buttons that each fill half of the starter row" {
    // V0.1.7_AI_ASSISTANT.md：两个快捷提问同一行、各占半行；按钮是原生 Button 的默认尺寸，不改高度 / 内边距 / 底色。
    var f: Fixture = undefined;
    try f.init("短标题");
    defer f.deinit();
    const welcome = f.node("ai.empty.configured").globalRect();
    // A2 (ai-redesign-c): the starter row spans the welcome, 4 in from each side.
    const row_w = welcome.w - 8;
    const reference = try ui.widgets.Button(.{ .label = "概括终端报错", .variant = .secondary, .icon_asset = ui.icons.get("terminal").? }).mount(f.scope, f.cx);
    try f.cx.root.?.appendChild(a, reference);
    f.settle();
    const native_h = reference.globalRect().h;
    for ([_][]const u8{ "ai.empty.summarize", "ai.empty.logs" }) |id| {
        const starter = f.node(id).globalRect();
        try std.testing.expectApproxEqAbs((row_w - 8) / 2, starter.w, 0.5);
        try std.testing.expectApproxEqAbs(native_h, starter.h, 0.01);
    }
    const left = f.node("ai.empty.summarize").globalRect();
    const right = f.node("ai.empty.logs").globalRect();
    try std.testing.expectApproxEqAbs(@as(f32, 8), right.x - (left.x + left.w), 0.5);
}

test "AI welcome rebuilt while its panel's open flight is in the air lands laid out, with no settle hook of its own" {
    // The open flight (AnchorTransition, static texture) keeps the panel `display: none` while its picture
    // flies. A welcome page mounted into the panel during that time used to come back unlaid (children
    // stacked at the corner); the view carried an after-layout hook that re-laid it out once displayed.
    // zenit now lays out what changed inside a hidden subtree when it is shown again (5ec77389), so the
    // view has no such hook; this is the scenario the hook existed for.
    const cx = try ui.Cx.init(a, std.testing.io);
    defer cx.deinit();
    cx.setViewport(600, 500);
    cx.setTheme(theme.widgetTheme(theme.currentName()));
    cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    const scope = try ui.Scope.init(a, null, cx.owner);
    defer scope.dispose();
    const panel = try ui.box(cx, .{ .position = .absolute, .inset = .{ .left = .{ .px = 60 }, .top = .{ .px = 40 } }, .width = .{ .px = 420 }, .height = .{ .px = 400 }, .direction = .column }, .{});
    const body = try ui.box(cx, .{ .width = .fill(), .flex = 1, .direction = .column, .padding = .{ .left = 14, .right = 14 } }, .{});
    try panel.appendChild(a, body);
    try cx.root.?.appendChild(a, panel);
    const Frames = struct {
        fn run(c: *ui.Cx, n: usize) void {
            c.setTestFrameStep(16) catch unreachable;
            for (0..n) |_| {
                c.advanceFrameClock();
                c.layout();
                _ = c.render();
            }
        }
    };
    const Ignore = struct {
        fn run(_: *anyopaque) void {}
    };
    var marker: u8 = 0;
    const actions: V.Actions = .{ .context = &marker, .summarize = Ignore.run, .logs = Ignore.run, .settings = Ignore.run, .ollama = Ignore.run };
    var view_scope = try scope.childScope();
    var view = try V.mount(cx, view_scope, true, actions);
    try body.appendChild(a, view);
    Frames.run(cx, 4);

    const t = try ui.fx.AnchorTransition.attach(scope, cx, panel, .{});
    t.snapTo(true);
    Frames.run(cx, 2);
    t.expand(.{ .rect = .{ .x = 500, .y = 440, .w = 40, .h = 40 } });
    Frames.run(cx, 4);
    try std.testing.expect(t.phase() == .expanding);
    // Mid flight: the host rebuilds the conversation — the welcome page is a new subtree.
    cx.detachChild(body, view);
    cx.destroyDetached(view);
    view_scope.dispose();
    view_scope = try scope.childScope();
    view = try V.mount(cx, view_scope, true, actions);
    try body.appendChild(a, view);
    var guard: usize = 0;
    while (t.phase() != .expanded and guard < 200) : (guard += 1) Frames.run(cx, 1);
    try std.testing.expect(t.phase() == .expanded);
    Frames.run(cx, 2);

    const welcome = find(view, "ai.empty.configured").?.globalRect();
    const body_rect = body.globalRect();
    try std.testing.expect(welcome.w > 300);
    const title = find(view, "ai.empty.title").?.globalRect();
    const left = find(view, "ai.empty.summarize").?.globalRect();
    const right = find(view, "ai.empty.logs").?.globalRect();
    // Laid out inside the panel body: the title has a size, the two starters sit side by side below it.
    try std.testing.expect(title.w > 0 and title.h > 0);
    try std.testing.expect(title.x >= body_rect.x and title.x + title.w <= body_rect.x + body_rect.w + 0.5);
    try std.testing.expect(left.w > 100 and right.w > 100);
    try std.testing.expect(right.x > left.x + left.w - 0.5);
    try std.testing.expect(left.y > title.y + title.h - 0.5);
    try std.testing.expectApproxEqAbs(left.y, right.y, 0.5);
}
