//! 设置预览 runner 的最小宿主（F-set-preview）：挂完整设置窗口（导航 + 页头 + 内容 + Save Bar）。
//!
//! 取舍：不经 `SettingsHost`。它依赖 `process_state` / `AppNavHost` / `ProcessWindows` /
//! `application_options`（整个主程序的模块图：SSH、VT、通知、更新…），预览步骤要补的不只是一个
//! build 选项。这里只用生产的 `Controller` + `ViewModel` + `.yix` 设置窗口 +
//! `aux_window.Slot`，`Ports` 是一个不做 I/O 的假实现。
//!
//! 与 `SettingsHost` 逐段对应、按原样复刻的部分（V-6 观察的就是它们）：
//! - `mountWindow` / `mountYixWindow`（主题发布、`vm.attach(scope)`；卡片不可聚焦）；
//! - `WindowHook.run`（跟随进程主题、两阶段重挂）；
//! - `rebuildYixContent` / `settleYixContent`（重挂前交出正文焦点，`focusRestore` 放回）；
//! - `detachWindow`（`vm.detach()`）。
//! 没有复刻：选择器 / 快捷键录制器 / AI 提供方 / 扩展 / 外观 worker / 保存流水线 / 通知授权 /
//! 滚动位置记忆。相应 Effect 只记日志；保存不落盘（预览不读写用户数据）。
const std = @import("std");
const ui = @import("ui");
const m = @import("../model/view_model.zig");
const Controller = @import("../model/settings_controller.zig").Controller;
const window_frame = @import("../view/window_frame.zig");
const settings_shell = @import("../view/settings_shell.zig");
const app_theme = @import("../../../shared/ui/theme/app_theme.zig");
const ThemePublication = @import("../../../shared/ui/theme/theme_publication.zig").ThemePublication;
pub const aux = @import("../../../shared/ui/window/aux_window.zig");

/// 生产的设置窗口参数（`settings_shell.window_spec`，960 × 780、标题栏 46、红绿灯 (28, 32)）。
pub const window_spec = settings_shell.window_spec;

pub const Counters = struct {
    attach: u32 = 0,
    detach: u32 = 0,
    window_cleanups: u32 = 0,
    rebuilds: u32 = 0,
    settles: u32 = 0,
    theme_republish: u32 = 0,
    close_requests: u32 = 0,
};

pub const Host = struct {
    allocator: std.mem.Allocator,
    controller: Controller,
    vm: m.ViewModel = undefined,
    frame: window_frame.Frame = undefined,
    slot: aux.Slot = undefined,
    cx: ?*ui.Cx = null,
    scope: ?*ui.Scope = null,
    card: ?*ui.Node = null,
    content: ?*ui.Node = null,
    mounted_page: ?window_frame.Page = null,
    mounted_page_index: usize = 0,
    pending_rebuild: bool = false,
    yix_settling: bool = false,
    counters: Counters = .{},
    /// 设置窗口 scope 上的自检探针（V-7）：窗口销毁时随 scope 释放。
    on_mounted: ?*const fn (*Host, *ui.Cx, *ui.Scope) anyerror!void = null,
    probe_context: ?*anyopaque = null,

    pub fn create(allocator: std.mem.Allocator) !*Host {
        const self = try allocator.create(Host);
        errdefer allocator.destroy(self);
        self.* = .{ .allocator = allocator, .controller = try Controller.init(allocator, .{}) };
        self.vm = m.ViewModel.init(&self.controller, .{ .context = self, .run = runEffect, .allow = allowGate });
        self.frame = .{ .vm = &self.vm };
        self.slot = .{ .spec = window_spec, .client = .{ .context = self, .mount = mountWindow, .close_request = closeRequest, .destroyed = destroyed, .failed = failed } };
        return self;
    }

    pub fn destroy(self: *Host) void {
        self.slot.deinit();
        self.controller.deinit();
        self.allocator.destroy(self);
    }

    /// 与 `SettingsHost.toggle` 的重新打开一致：回到离开时的位置（搜索中则回到搜索起点），历史重来。
    pub fn reopenLocation(self: *Host) void {
        const c = &self.controller;
        const reopen: m.Location = if (c.search_return_page) |page| .{ .page = @intCast(page), .sub = c.search_return_subpage } else c.location();
        // 宿主发起的恢复位置（H-save：不按“离开作用域”确认）。
        self.vm.restoreLocation(reopen);
        c.history.reset(c.location());
    }

    // ── Ports（假实现：不做 I/O） ──

    /// 预览宿主没有会拦意图的状态（旧外壳的“组字中不保存”随旧正文删除；面板的输入框不经宿主）。
    fn allowGate(_: *anyopaque, _: m.Gate) bool {
        return true;
    }

    fn runEffect(raw: *anyopaque, effect: m.Effect) void {
        const self: *Host = @ptrCast(@alignCast(raw));
        switch (effect) {
            .leave_page => {},
            .navigated, .rebuild => {
                self.pending_rebuild = true;
                if (self.cx) |cx| cx.requestRedraw();
            },
            .close_window, .discard_and_close, .request_close => self.slot.close(),
            // 与宿主的 `windowEscape` 相同：先让面板收起提示 / 弹层 / 原地编辑，都没有时关窗（预览不弹未保存确认）。
            .escape => if (!self.vm.consumeEscape(if (self.cx) |cx| if (cx.focus_manager.getFocused()) |node| cx.focus_targets.targetName(cx, node) else null else null)) self.slot.close(),
            .failed => |err| std.log.warn("settings preview: {s}", .{@errorName(err)}),
            else => std.log.info("settings preview: effect .{s} is not carried out (read-only preview)", .{@tagName(effect)}),
        }
    }

    /// 搜索框当前显示的文字（view-model 的受控值）。
    pub fn searchFieldText(self: *Host) []const u8 {
        return if (self.vm.signals) |s| s.search_field.peek() else "";
    }

    // ── aux 窗口客户端 ──

    fn mountWindow(raw: *anyopaque, cx: *ui.Cx, scope: *ui.Scope) anyerror!*ui.Node {
        const self: *Host = @ptrCast(@alignCast(raw));
        const publication = try cx.bindState(ThemePublication, .{});
        publication.publish(cx, app_theme.widgetTheme(app_theme.currentName()));
        self.controller.drill_down = true;
        self.cx = cx;
        self.scope = scope;
        const root = try self.mountYix(cx, scope);
        // 与宿主相同：卡片不可聚焦，整窗按键在模板根（S-6）。
        self.card = self.frame.panel() orelse return error.SettingsWindowShape;
        const hook = try scope.createState(WindowHook, .{ .host = self, .cx = cx, .publication = publication });
        try cx.addAfterLayoutHook(hook, WindowHook.run);
        try scope.onCleanup(WindowHook, hook, WindowHook.cleanup);
        self.counters.attach += 1;
        self.pending_rebuild = true;
        if (self.on_mounted) |probe| try probe(self, cx, scope);
        return root;
    }

    fn mountYix(self: *Host, cx: *ui.Cx, scope: *ui.Scope) !*ui.Node {
        const settings_window = @import("../view/_settings_window.yix.zig");
        try self.vm.attach(scope);
        self.frame = .{ .vm = &self.vm };
        const root = try ui.view.render(scope, cx, settings_window.SettingsWindow(.{ .vm = &self.vm, .frame = &self.frame }));
        self.content = self.frame.island() orelse return error.SettingsWindowShape;
        self.mounted_page = window_frame.Page.of(&self.frame);
        return root;
    }

    /// 与 `SettingsHost.detachWindow` 相同：窗口 scope 即将销毁，忘掉信号与节点句柄。
    fn detachWindow(self: *Host) void {
        if (self.cx == null) return;
        self.vm.detach();
        self.counters.detach += 1;
        self.yix_settling = false;
        self.mounted_page = null;
        self.content = null;
        self.card = null;
        self.cx = null;
        self.scope = null;
    }

    fn closeRequest(raw: *anyopaque) bool {
        const self: *Host = @ptrCast(@alignCast(raw));
        self.counters.close_requests += 1;
        // 草稿留在 Controller（与生产“重新打开从草稿继续”一致）；预览不弹未保存确认。
        return true;
    }
    fn destroyed(raw: *anyopaque) void {
        const self: *Host = @ptrCast(@alignCast(raw));
        self.detachWindow();
    }
    fn failed(_: *anyopaque, err: anyerror) void {
        std.log.err("settings preview window: {s}", .{@errorName(err)});
    }

    const WindowHook = struct {
        host: *Host,
        cx: *ui.Cx,
        publication: *ThemePublication,
        fn run(raw: *anyopaque, _: u8, _: bool) ui.AfterLayoutResult {
            const self: *WindowHook = @ptrCast(@alignCast(raw));
            const host = self.host;
            if (host.cx != self.cx) return .done;
            // 跟随进程主题（app_theme 的选择是进程级全局）。
            const tokens = app_theme.widgetTheme(app_theme.currentName());
            if (!std.meta.eql(self.publication.snapshots[self.publication.slot], tokens.*)) {
                self.publication.publish(self.cx, tokens);
                host.counters.theme_republish += 1;
                host.pending_rebuild = true;
            }
            if (host.yix_settling) {
                host.settleYixContent();
                return .needs_layout;
            }
            if (host.pending_rebuild) {
                host.pending_rebuild = false;
                host.rebuildAll();
                return .needs_layout;
            }
            return .done;
        }
        fn cleanup(self: *WindowHook) void {
            self.cx.removeAfterLayoutHook(self);
            self.host.counters.window_cleanups += 1;
            if (self.host.cx == self.cx) self.host.detachWindow();
        }
    };

    fn rebuildAll(self: *Host) void {
        self.counters.rebuilds += 1;
        self.vm.sync();
        self.rebuildYixContent() catch |err| std.log.warn("settings content rebuild failed: {s}", .{@errorName(err)});
    }

    fn contentOwnsFocus(self: *Host, focused: *ui.Node) bool {
        const node = self.content orelse return false;
        return focused.isDescendantOf(node);
    }

    fn rebuildYixContent(self: *Host) !void {
        const cx = self.cx orelse return;
        // 与宿主相同（S-6）：输入框由 `focusRestore` 按 `focusId` 放回，不拍快照；其它正文控件先主动 blur。
        if (cx.focus_manager.current_focus) |focused| {
            if (self.contentOwnsFocus(focused)) {
                if (self.mounted_page) |page| page.releaseFocus(cx, focused) else cx.setFocus(null);
            }
        }
        self.mounted_page = null;
        self.vm.remountContent();
        self.yix_settling = true;
        cx.requestRedraw();
    }

    fn settleYixContent(self: *Host) void {
        self.counters.settles += 1;
        self.yix_settling = false;
        const page = window_frame.Page.of(&self.frame) orelse return;
        self.mounted_page = page;
        self.mounted_page_index = self.controller.model.page_index;
        if (self.cx) |cx| cx.requestRedraw();
    }

};

pub fn findTestId(node: *ui.Node, wanted: []const u8) ?*ui.Node {
    if (node.meta.ownership.meta.test_id) |value| if (std.mem.eql(u8, value, wanted)) return node;
    for (node.children.items) |child| if (findTestId(child, wanted)) |found| return found;
    return null;
}

pub fn countTestId(node: *ui.Node, wanted: []const u8) usize {
    var count: usize = 0;
    if (node.meta.ownership.meta.test_id) |value| if (std.mem.eql(u8, value, wanted)) {
        count += 1;
    };
    for (node.children.items) |child| count += countTestId(child, wanted);
    return count;
}
