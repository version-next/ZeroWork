//! “数据与日志 › 清除全部数据…”确认对话框（S-12）的组件测试：真 `.yix` 设置窗口 + 真 `ViewModel` + 宿主替身。
//! 宿主替身只做 `SettingsHost` 的那几步副作用：`Effect.clear_all` → 回流 `.show(阻塞原因)`；`Effect.data_cleanup(.confirm)` →
//! 回流 `.working`。断言只用 test_id、可见文字、禁用态、焦点与 Effect，不依赖节点层级（对话框面板按 dialog 角色找）。
const std = @import("std");
const ui = @import("ui");
const kit = @import("../../../shared/testing/ui_kit.zig");
const app_theme = @import("../../../shared/ui/theme/app_theme.zig");
const shell = @import("../view/settings_shell.zig");
const Controller = @import("../model/settings_controller.zig").Controller;
const RuntimeConfig = @import("../../../config/runtime_config.zig").RuntimeConfig;
const m = @import("../model/view_model.zig");
const frame_mod = @import("../view/window_frame.zig");
const settings_window = @import("../view/_settings_window.yix.zig");
const C = m.data_cleanup;

const Fixture = struct {
    env: kit.Headless,
    tmp: std.testing.TmpDir,
    runtime: RuntimeConfig,
    controller: Controller,
    vm: m.ViewModel,
    frame: frame_mod.Frame,
    /// 宿主在打开时 / 复查时给的阻塞原因。
    blocked: ?[]const u8 = null,
    choices: std.ArrayList(C.Action) = .empty,
    clear_all: usize = 0,
    root: *ui.Node = undefined,

    fn init(self: *Fixture, theme: app_theme.Name, width: f32, height: f32) !void {
        const a = std.testing.allocator;
        self.* = .{ .env = try kit.headless(a, .{ .width = width, .height = height, .theme = theme, .root_style = .{ .width = .fill(), .height = .fill(), .direction = .column } }), .tmp = std.testing.tmpDir(.{}), .runtime = undefined, .controller = undefined, .vm = undefined, .frame = undefined };
        self.runtime = try RuntimeConfig.loadOrDefault(std.testing.io, self.tmp.dir, a, "config.toml");
        self.controller = try Controller.init(a, self.runtime.value);
        self.controller.drill_down = true;
        self.controller.folded_sections = 0;
        self.controller.history.reset(self.controller.location());
        self.vm = m.ViewModel.init(&self.controller, .{ .context = self, .run = run, .allow = allow });
        self.frame = .{ .vm = &self.vm };
        try self.vm.attach(self.env.scope);
        self.root = try ui.view.render(self.env.scope, self.env.cx, settings_window.SettingsWindow(.{ .vm = &self.vm, .frame = &self.frame }));
        try self.env.mount(self.root);
        self.env.cx.content_root = self.root;
        self.vm.dispatch(m.Intent.openAt(.{ .page = 7, .sub = 2 }));
        self.vm.remountContent();
        self.settle();
    }
    fn deinit(self: *Fixture) void {
        // 先收起对话框再拆窗口（焦点作用域在拆除时归还焦点）。
        if (self.vm.cleanup.mode != .closed) {
            self.vm.cleanup.mode = .closed;
            self.vm.signals.?.cleanup.set(self.vm.signals.?.cleanup.peek() +% 1);
            self.settle();
        }
        self.env.deinit();
        self.choices.deinit(std.testing.allocator);
        self.controller.deinit();
        self.runtime.deinit();
        self.tmp.cleanup();
    }
    fn run(raw: *anyopaque, effect: m.Effect) void {
        const self: *Fixture = @ptrCast(@alignCast(raw));
        switch (effect) {
            .clear_all => {
                self.clear_all += 1;
                self.vm.dispatch(m.Intent.cleanupEvent(.{ .show = self.blocked }));
            },
            .data_cleanup => |choice| {
                self.choices.append(std.testing.allocator, choice) catch {};
                if (choice == .confirm or choice == .retry) self.vm.dispatch(m.Intent.cleanupEvent(.working));
            },
            else => {},
        }
    }
    fn allow(_: *anyopaque, _: m.Gate) bool {
        return true;
    }
    fn noop(_: *anyopaque) void {}
    fn settle(self: *Fixture) void {
        for (0..24) |_| {
            self.env.cx.advanceFrameClock();
            self.env.frame();
        }
    }
    /// 对话框挂在窗口浮层根上（不在设置窗口模板的子树里）：从 `cx.root` 找。
    fn node(self: *Fixture, id: []const u8) !*ui.Node {
        return kit.expectByTestId(self.env.cx.root.?, id);
    }
    fn find(self: *Fixture, id: []const u8) ?*ui.Node {
        return kit.findByTestId(self.env.cx.root.?, id);
    }
    fn click(self: *Fixture, id: []const u8) !void {
        const r = (try self.node(id)).globalRect();
        self.env.cx.handleClick(r.x + r.w / 2, r.y + r.h / 2);
        self.settle();
    }
    fn last(self: *Fixture) ?C.Action {
        return if (self.choices.items.len == 0) null else self.choices.items[self.choices.items.len - 1];
    }
};

fn textOf(node: *ui.Node, buffer: []u8) []const u8 {
    var used: usize = 0;
    collect(node, buffer, &used);
    return buffer[0..used];
}
fn collect(node: *ui.Node, buffer: []u8, used: *usize) void {
    if (node.style.display == .none) return;
    if (node.getText()) |value| {
        const n = @min(value.content.len, buffer.len - used.*);
        @memcpy(buffer[used.*..][0..n], value.content[0..n]);
        used.* += n;
    }
    for (node.children.items) |child| collect(child, buffer, used);
}
fn contains(node: *ui.Node, needle: []const u8) bool {
    var buffer: [4096]u8 = undefined;
    return std.mem.indexOf(u8, textOf(node, &buffer), needle) != null;
}
fn disabled(node: *ui.Node) bool {
    const a11y = node.behavior.interaction.a11y orelse return false;
    return a11y.disabled;
}
fn shown(node: *ui.Node) bool {
    var cursor: ?*ui.Node = node;
    while (cursor) |current| : (cursor = current.parent) if (current.style.display == .none) return false;
    return node.globalRect().h > 0;
}

test "settings data cleanup (S-12): the button opens a native W.Modal default with focus on Cancel; host recheck enables Clear" {
    var f: Fixture = undefined;
    try f.init(.light, shell.window.width, shell.window.height);
    defer f.deinit();
    f.blocked = "请先结束所有窗口的活动会话与后台连接";
    try std.testing.expect(f.find("data.cleanup.modal") == null);
    try f.click("settings.data.clear_all");
    try std.testing.expectEqual(@as(usize, 1), f.clear_all);
    const panel = try f.node("data.cleanup.modal");
    try std.testing.expectEqual(@as(f32, 520), panel.globalRect().w);
    try std.testing.expect(contains(panel, "清除全部应用数据？"));
    try std.testing.expect(contains(panel, "将清除全部应用数据"));
    try std.testing.expect(contains(panel, C.scope_text));
    try std.testing.expect(contains(panel, C.preserved_text));
    try std.testing.expect(contains(panel, C.outcome_text));
    _ = try f.node("data.cleanup.headline");
    try std.testing.expect(contains(try f.node("data.cleanup.message"), "请先结束所有窗口的活动会话与后台连接"));
    // 焦点在“取消”；阻塞时“清除全部数据”不可点，点了也不发动作。
    const cancel = try f.node("data.cleanup.cancel");
    try std.testing.expect(f.env.cx.focus_manager.getFocused() == cancel);
    try std.testing.expect(disabled(try f.node("data.cleanup.confirm")));
    try f.click("data.cleanup.confirm");
    try std.testing.expectEqual(@as(usize, 0), f.choices.items.len);
    // 默认面板：与同参数、无覆盖的原生 Modal 底色 / 圆角 / 遮罩相同，面板不透明。
    const ref_open = try f.env.scope.createSignal(bool, true);
    const ref = try ui.widgets.Modal(.{ .open = ref_open, .title = "参照", .width = @as(f32, 520), .close_on_overlay = false }).mount(f.env.scope, f.env.cx);
    if (!ref.portaled) try f.env.root.appendChild(f.env.cx.allocator, ref.overlay);
    f.settle();
    try std.testing.expect(ui.Color.eql(ref.dialog.getBackground(), panel.getBackground()));
    try std.testing.expect(panel.getBackground().a == 255);
    try std.testing.expectEqual(ref.dialog.style.corner_radius(), panel.style.corner_radius());
    try std.testing.expect(ui.Color.eql(ref.overlay.getBackground(), panel.parent.?.getBackground()));
    ref_open.set(false);
    f.settle();
    // 宿主复查：不再阻塞 → 状态行清空、可点。
    f.vm.dispatch(m.Intent.cleanupEvent(.{ .blocked = null }));
    f.settle();
    try std.testing.expect(!disabled(try f.node("data.cleanup.confirm")));
    var buffer: [256]u8 = undefined;
    try std.testing.expectEqualStrings("", textOf(try f.node("data.cleanup.message"), &buffer));
    // Escape = 取消：收起并请宿主回焦（`dismiss`）。
    f.env.cx.handleKeyDown(.escape, .{});
    f.settle();
    try std.testing.expectEqual(C.Action.dismiss, f.last().?);
    try std.testing.expect(f.find("data.cleanup.modal") == null);
    try std.testing.expect(!f.vm.cleanupOpen());
}

test "settings data cleanup (S-12): Clear hands over to the host, working ignores Cancel / Escape, failure offers retry and exit" {
    var f: Fixture = undefined;
    try f.init(.dark, shell.window.width, shell.window.height);
    defer f.deinit();
    try f.click("settings.data.clear_all");
    try f.click("data.cleanup.confirm");
    try std.testing.expectEqual(C.Action.confirm, f.last().?);
    // 宿主接手：进行中的文案，按钮不可点，Escape / 取消 / 标题栏关闭都不收起。
    const panel = try f.node("data.cleanup.modal");
    try std.testing.expect(contains(panel, "正在清除应用数据…"));
    try std.testing.expect(contains(try f.node("data.cleanup.message"), "请稍候。全部清除成功后，应用将退出。"));
    try std.testing.expect(contains(try f.node("data.cleanup.confirm"), "正在清除…"));
    try std.testing.expect(disabled(try f.node("data.cleanup.confirm")));
    try std.testing.expect(disabled(try f.node("data.cleanup.cancel")));
    f.env.cx.handleKeyDown(.escape, .{});
    f.settle();
    try f.click("data.cleanup.cancel");
    try std.testing.expectEqual(@as(usize, 1), f.choices.items.len);
    try std.testing.expect(f.vm.cleanupOpen());
    try std.testing.expect(shown(try f.node("data.cleanup.modal")));
    // 整窗快捷键不接（Escape / ⌘W 归对话框，不关窗）。
    try std.testing.expect(!f.vm.windowKey(.escape, .{}));
    try std.testing.expect(!f.vm.windowKey(.w, .{ .super = true }));
    // 失败（可重试）：文案、“退出应用”拿到焦点、“重试清除”。
    f.vm.dispatch(m.Intent.cleanupEvent(.{ .failed = .{ .message = "钥匙串清除失败：AccessDenied。部分内容可能已删除；可重试或退出，应用不会继续保存配置。" } }));
    f.settle();
    try std.testing.expect(contains(try f.node("data.cleanup.modal"), "清除未完成，应用尚未退出"));
    try std.testing.expect(contains(try f.node("data.cleanup.message"), "钥匙串清除失败"));
    const exit_button = try f.node("data.cleanup.cancel");
    try std.testing.expect(contains(exit_button, "退出应用"));
    try std.testing.expectEqualStrings("退出应用", exit_button.behavior.interaction.a11y.?.label.?);
    try std.testing.expect(f.env.cx.focus_manager.getFocused() == exit_button);
    try std.testing.expect(contains(try f.node("data.cleanup.confirm"), "重试清除"));
    try f.click("data.cleanup.confirm");
    try std.testing.expectEqual(C.Action.retry, f.last().?);
    // 不可重试的失败：没有主按钮；“退出应用” = dismiss（宿主：清除已开始 → 退出）。
    f.vm.dispatch(m.Intent.cleanupEvent(.{ .failed = .{ .message = "目录验证失败。未继续删除，请重新启动应用。", .retryable = false } }));
    f.settle();
    if (f.find("data.cleanup.confirm")) |primary| try std.testing.expect(!shown(primary));
    try f.click("data.cleanup.cancel");
    try std.testing.expectEqual(C.Action.dismiss, f.last().?);
    try std.testing.expect(f.find("data.cleanup.modal") == null);
}

test "settings data cleanup (S-12): the dialog fits the minimum window in every theme with the actions inside the panel" {
    for ([_]app_theme.Name{ .dark, .light, .sauber }) |theme| {
        var f: Fixture = undefined;
        try f.init(theme, 640, 480);
        defer f.deinit();
        f.vm.dispatch(m.Intent.cleanupEvent(.{ .show = null }));
        f.settle();
        const r = (try f.node("data.cleanup.modal")).globalRect();
        try std.testing.expect(r.x >= 0 and r.y >= 0 and r.x + r.w <= 640 and r.y + r.h <= 480);
        const b = (try f.node("data.cleanup.confirm")).globalRect();
        try std.testing.expect(b.y + b.h <= r.y + r.h + 0.5);
        try std.testing.expect(f.env.cx.focus_manager.getFocused() == try f.node("data.cleanup.cancel"));
        try std.testing.expectEqual(@as(usize, 0), f.choices.items.len);
    }
}
