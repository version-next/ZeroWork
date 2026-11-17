//! 命令帮助卡（`@help` 没有终端输出目标时打开；NATIVE_AUDIT B4，人工验收反馈 8）的组件测试。
//! 视图在 `view/command_help.yix`：原生 `W.Modal` 默认外观，显隐是宿主持有的 `*Signal(bool)`（`AppNavHost.help_open`，
//! `@help` 的打开动作就是把它置真）。隔离环境的真实窗口里触发不到这条路径（内置指令总有终端输出目标），
//! 所以这里是主要证据：打开后面板与无覆盖的参照 Modal 外观相同、遮罩是主题 overlay token；Esc / 关闭按钮 / 点遮罩都能关，
//! 关闭后焦点回到打开前的节点（终端）。
const std = @import("std");
const ui = @import("ui");
const kit = @import("../../../shared/testing/ui_kit.zig");
const help = @import("../view/_command_help.yix.zig");
const dispatch = @import("../model/builtin_dispatch.zig");

const Fixture = struct {
    env: kit.Headless,
    open: *ui.Signal(bool),
    /// 终端的替身：打开前持有焦点的节点。
    terminal: *ui.Node,

    fn init(a: std.mem.Allocator, height: f32) !Fixture {
        var env = try kit.headless(a, .{ .width = 1200, .height = height });
        errdefer env.deinit();
        const terminal = try ui.box(env.cx, .{ .width = .fill(), .height = .fill() }, .{});
        terminal.behavior.interaction.focusable = true;
        try env.mount(terminal);
        const open = try env.scope.createSignal(bool, false);
        // 与 main_window 相同：挂载点放在终端区里，Modal 自己挂到窗口浮层根。
        try terminal.appendChild(a, try ui.view.render(env.scope, env.cx, help.CommandHelp(.{ .open = open })));
        settle(&env);
        env.cx.focus_manager.setFocus(terminal);
        return .{ .env = env, .open = open, .terminal = terminal };
    }
    fn deinit(self: *Fixture) void {
        self.env.deinit();
    }
    /// 宿主的打开动作（`nav_host` `.help` 分支）：置真。
    fn show(self: *Fixture) !*ui.Node {
        self.open.set(true);
        settle(&self.env);
        const body = try self.env.expect(help.ids.body);
        return panelOf(body) orelse error.TestNoModalPanel;
    }
};

fn settle(env: *kit.Headless) void {
    for (0..20) |_| env.frame();
}

/// 原生 Modal 的对话框面板：正文往上第一个带 dialog 角色的节点。
fn panelOf(node: *ui.Node) ?*ui.Node {
    var cursor: ?*ui.Node = node;
    while (cursor) |current| : (cursor = current.parent) {
        if (current.behavior.interaction.a11y) |a11y| if (a11y.role == .dialog) return current;
    }
    return null;
}

fn focusedInside(cx: *ui.Cx, panel: *ui.Node) bool {
    const focused = cx.focus_manager.getFocused() orelse return false;
    return focused == panel or focused.isDescendantOf(panel);
}

fn textOf(node: *ui.Node, out: *std.ArrayList(u8), a: std.mem.Allocator) !void {
    if (node.getText()) |text| {
        try out.appendSlice(a, text.content);
        try out.append(a, '\n');
    }
    for (node.children.items) |child| try textOf(child, out, a);
}

test "command help: @help card is a native Modal with the zenit default barrier and panel" {
    const a = std.testing.allocator;
    var f = try Fixture.init(a, 900);
    defer f.deinit();
    // 关着时不可见：正文所在的遮罩缩成 0×0、不可命中。
    const closed_body = try f.env.expect(help.ids.body);
    const closed_barrier = panelOf(closed_body).?.parent.?;
    try std.testing.expectEqual(ui.Sizing{ .px = 0 }, closed_barrier.style.width);

    const panel = try f.show();
    const barrier = panel.parent.?;
    const colors = f.env.cx.tokens.tokens.color;
    // 遮罩：主题 overlay token（半透明），不再是硬编码的浅绿 rgba(236,255,244,102)。
    try std.testing.expect(ui.Color.eql(colors.overlay, barrier.getBackground()));
    try std.testing.expect(barrier.getBackground().a > 0 and barrier.getBackground().a < 255);
    try std.testing.expect(!ui.Color.eql(ui.Color.rgba(236, 255, 244, 102), barrier.getBackground()));
    try std.testing.expect(barrier.style.width != .px);

    // 参照：同宽、无任何覆盖的原生 Modal。
    const ref_open = try f.env.scope.createSignal(bool, true);
    const ref = try ui.widgets.Modal(.{ .open = ref_open, .title = "参照", .width = @as(f32, 580) }).mount(f.env.scope, f.env.cx);
    if (!ref.portaled) try f.env.root.appendChild(a, ref.overlay);
    settle(&f.env);
    try std.testing.expect(ui.Color.eql(ref.dialog.getBackground(), panel.getBackground()));
    try std.testing.expect(ui.Color.eql(colors.bg_primary, panel.getBackground()));
    try std.testing.expect(panel.getBackground().a == 255);
    try std.testing.expectEqual(ref.dialog.style.corner_radius(), panel.style.corner_radius());
    try std.testing.expect(ui.Color.eql(ref.dialog.style.border.color, panel.style.border.color));
    try std.testing.expectEqual(ref.dialog.style.border.width, panel.style.border.width);
    try std.testing.expectEqualDeep(ref.dialog.style.shadow(), panel.style.shadow());
    try std.testing.expect(panel.style.backdrop_blur() == 0);
    try std.testing.expect(ui.Color.eql(ref.overlay.getBackground(), barrier.getBackground()));
    try std.testing.expectEqual(ref.dialog.globalRect().w, panel.globalRect().w);
    ref_open.set(false);
    settle(&f.env);

    // 内容不变：标题、目录每一项（图标、用法、说明）与两行脚注；原生标题栏带关闭按钮。
    try std.testing.expect(kit.findByTestId(panel, "modal.close") != null);
    const rows = try kit.findAllByTestId(a, panel, help.ids.row);
    defer a.free(rows);
    try std.testing.expectEqual(dispatch.helpEntries().len, rows.len);
    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(a);
    try textOf(panel, &text, a);
    try std.testing.expect(std.mem.indexOf(u8, text.items, "❓ 内置指令速查") != null);
    for (dispatch.helpEntries()) |entry| {
        try std.testing.expect(std.mem.indexOf(u8, text.items, entry.usage) != null);
        try std.testing.expect(std.mem.indexOf(u8, text.items, entry.description) != null);
    }
    try std.testing.expect(std.mem.indexOf(u8, text.items, "在空命令行输入 @ 查看指令。") != null);
    try std.testing.expect(std.mem.indexOf(u8, text.items, "输入 @@ 可发送普通 @ 字符。") != null);
}

test "command help: Esc, the close button and the barrier close it and focus returns to the terminal" {
    const a = std.testing.allocator;
    var f = try Fixture.init(a, 900);
    defer f.deinit();
    const cx = f.env.cx;

    // Esc。
    var panel = try f.show();
    try std.testing.expect(focusedInside(cx, panel));
    try std.testing.expectEqual(try f.env.expect(help.ids.close), cx.focus_manager.getFocused().?);
    cx.handleKeyDown(.escape, .{});
    settle(&f.env);
    try std.testing.expect(!f.open.peek());
    try std.testing.expectEqual(f.terminal, cx.focus_manager.getFocused().?);

    // 标题栏的原生关闭按钮。
    panel = try f.show();
    try std.testing.expect(focusedInside(cx, panel));
    const close = kit.findByTestId(panel, "modal.close") orelse return error.TestNoCloseButton;
    const cr = close.globalRect();
    cx.handleClick(cr.x + cr.w / 2, cr.y + cr.h / 2);
    settle(&f.env);
    try std.testing.expect(!f.open.peek());
    try std.testing.expectEqual(f.terminal, cx.focus_manager.getFocused().?);

    // 点遮罩（面板外）。
    panel = try f.show();
    const pr = panel.globalRect();
    try std.testing.expect(pr.x > 20);
    cx.handleClick(pr.x / 2, pr.y + pr.h / 2);
    settle(&f.env);
    try std.testing.expect(!f.open.peek());
    try std.testing.expectEqual(f.terminal, cx.focus_manager.getFocused().?);

    // 脚注的原生“关闭”按钮（打开时焦点就在它上面）。
    panel = try f.show();
    const footer_close = try f.env.expect(help.ids.close);
    try std.testing.expectEqual(footer_close, cx.focus_manager.getFocused().?);
    const fr = footer_close.globalRect();
    try std.testing.expect(fr.x >= panel.globalRect().x and fr.x + fr.w <= panel.globalRect().x + panel.globalRect().w);
    cx.handleClick(fr.x + fr.w / 2, fr.y + fr.h / 2);
    settle(&f.env);
    try std.testing.expect(!f.open.peek());
    try std.testing.expectEqual(f.terminal, cx.focus_manager.getFocused().?);

    // 点面板里的只读内容不关闭；宿主写回假（`nav_host` 的 Esc 分支）同样关闭并还焦点。
    panel = try f.show();
    const list = (try f.env.expect(help.ids.list)).globalRect();
    cx.handleClick(list.x + list.w / 2, list.y + 14);
    settle(&f.env);
    try std.testing.expect(f.open.peek());
    f.open.set(false);
    settle(&f.env);
    try std.testing.expectEqual(f.terminal, cx.focus_manager.getFocused().?);
}

test "command help: the catalog sits in a ScrollArea inside the panel within the default max height" {
    const a = std.testing.allocator;
    var f = try Fixture.init(a, 900);
    defer f.deinit();
    const panel = try f.show();
    const pr = panel.globalRect();
    // 原生 Modal 默认 max_height 600：面板不超过它，目录的 ScrollArea 在面板里、脚注之上。
    try std.testing.expect(pr.h <= 600 + 0.5);
    const list = try f.env.expect(help.ids.list);
    const lr = list.globalRect();
    try std.testing.expect(lr.y >= pr.y and lr.y + lr.h <= pr.y + pr.h + 0.5);
    try std.testing.expect(lr.h > 0);
    const rows = try kit.findAllByTestId(a, panel, help.ids.row);
    defer a.free(rows);
    const first = rows[0].globalRect();
    try std.testing.expect(first.y >= lr.y - 0.5);
    try std.testing.expectEqual(@as(f32, 28), first.h);
    // 17 行在默认 600 上限内放得下（面板约 588）：列表不滚动、最后一行在列表视口里。
    const last = rows[rows.len - 1].globalRect();
    try std.testing.expect(last.y + last.h <= lr.y + lr.h + 0.5);
}
