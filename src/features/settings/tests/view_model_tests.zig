//! `model/view_model.zig`：不建任何节点，只喂 Intent、读投影信号与发出的 Effect；
//! 宿主用假的 `Ports` 代替（保存流水线由测试按 Effect 驱动 Controller 完成后回流 `.save_finished`）。
const std = @import("std");
const ui = @import("ui");
const m = @import("../model/view_model.zig");
const Controller = @import("../model/settings_controller.zig").Controller;
const runtime = @import("../../../config/runtime_config.zig");

const EffectTag = std.meta.Tag(m.Effect);
comptime {
    _ = @import("../model/keybinding_edit.zig");
    _ = @import("../model/save_flow.zig");
    _ = @import("../model/data_cleanup.zig");
}

const FakeHost = struct {
    effects: [64]m.Effect = undefined,
    len: usize = 0,
    navigate: bool = true,
    search: bool = true,
    save: bool = true,
    reset: bool = true,
    window_keys: bool = true,

    fn ports(self: *FakeHost) m.Ports {
        return .{ .context = self, .run = run, .allow = allow };
    }
    fn run(raw: *anyopaque, effect: m.Effect) void {
        const self: *FakeHost = @ptrCast(@alignCast(raw));
        self.effects[self.len] = effect;
        self.len += 1;
    }
    fn allow(raw: *anyopaque, gate: m.Gate) bool {
        const self: *FakeHost = @ptrCast(@alignCast(raw));
        return switch (gate) {
            .navigate => self.navigate,
            .search => self.search,
            .save => self.save,
            .reset => self.reset,
            .window_keys => self.window_keys,
        };
    }
    fn tags(self: *const FakeHost, buffer: []EffectTag) []const EffectTag {
        for (self.effects[0..self.len], 0..) |effect, index| buffer[index] = effect;
        return buffer[0..self.len];
    }
    fn expectTags(self: *const FakeHost, expected: []const EffectTag) !void {
        var buffer: [64]EffectTag = undefined;
        try std.testing.expectEqualSlices(EffectTag, expected, self.tags(&buffer));
    }
    fn has(self: *const FakeHost, tag: EffectTag) bool {
        for (self.effects[0..self.len]) |effect| if (effect == tag) return true;
        return false;
    }
    fn clear(self: *FakeHost) void {
        self.len = 0;
    }
};

const Fixture = struct {
    cx: *ui.Cx,
    scope: *ui.Scope,
    controller: Controller,
    host: FakeHost = .{},
    vm: m.ViewModel = undefined,

    fn init(self: *Fixture, value: @import("../../../config/config.zig").Config) !void {
        self.cx = try ui.Cx.init(std.testing.allocator, std.testing.io);
        errdefer self.cx.deinit();
        self.scope = try ui.Scope.init(std.testing.allocator, null, self.cx.owner);
        errdefer self.scope.dispose();
        self.controller = try Controller.init(std.testing.allocator, value);
        self.controller.drill_down = true;
        self.host = .{};
        self.vm = m.ViewModel.init(&self.controller, self.host.ports());
        try self.vm.attach(self.scope);
    }
    fn deinit(self: *Fixture) void {
        self.vm.detach();
        self.controller.deinit();
        self.scope.dispose();
        self.cx.deinit();
    }
};

const font_size: m.Key = .{ .section = "ui", .key = "font_size" };

test "settings view model routes categories subpages and history through dispatch" {
    var f: Fixture = undefined;
    try f.init(.{});
    defer f.deinit();
    try std.testing.expectEqual(m.Mode.overview, f.vm.mode());
    try std.testing.expectEqualStrings(m.catalog.title(0), f.vm.title());
    try std.testing.expect(!f.vm.backEnabled() and !f.vm.forwardEnabled());

    f.vm.dispatch(m.Intent.selectCategory(2));
    try f.host.expectTags(&.{ .leave_page, .navigated });
    try std.testing.expectEqual(m.Location{ .page = 2 }, f.vm.location());
    try std.testing.expectEqual(m.Mode.overview, f.vm.mode());
    try std.testing.expect(f.vm.categorySelected(2) and !f.vm.categorySelected(0));
    try std.testing.expect(f.vm.backEnabled());

    f.vm.dispatch(m.Intent.openSubpage(1));
    try std.testing.expectEqual(m.Location{ .page = 2, .sub = 1 }, f.vm.location());
    try std.testing.expectEqual(m.Mode.panes, f.vm.mode());
    try std.testing.expectEqualStrings("SOCKS5 转发", f.vm.title());
    try std.testing.expect(f.vm.paneVisible("settings.ssh.socks"));
    try std.testing.expect(!f.vm.paneVisible("settings.ssh.connection"));

    f.vm.dispatch(.back);
    try std.testing.expectEqual(m.Location{ .page = 2 }, f.vm.location());
    try std.testing.expect(f.vm.forwardEnabled());
    try std.testing.expect(!f.vm.paneVisible("settings.ssh.socks"));
    f.vm.dispatch(.forward);
    try std.testing.expectEqual(m.Location{ .page = 2, .sub = 1 }, f.vm.location());
    try std.testing.expect(!f.vm.forwardEnabled());

    // 分类没有子页面：直接显示全部面板。
    f.vm.dispatch(m.Intent.openAt(.{ .page = 1 }));
    try std.testing.expectEqual(m.Mode.panes, f.vm.mode());
    try std.testing.expectEqualStrings(m.catalog.title(1), f.vm.title());
    try std.testing.expect(f.vm.paneVisible("settings.keys.tabs"));

    // 宿主拒绝（worker 忙、MCP 编辑未完成）时既不改位置也不发 Effect。
    f.host.navigate = false;
    f.host.clear();
    f.vm.dispatch(.back);
    try std.testing.expectEqual(@as(usize, 0), f.host.len);
    try std.testing.expectEqual(m.Location{ .page = 1 }, f.vm.location());
}

test "settings view model search projects results and back leaves the search" {
    var f: Fixture = undefined;
    try f.init(.{});
    defer f.deinit();
    f.vm.dispatch(m.Intent.openAt(.{ .page = 3, .sub = 2 }));
    f.host.clear();

    f.vm.dispatch(m.Intent.searchFor("重连"));
    try f.host.expectTags(&.{.rebuild});
    try std.testing.expectEqual(m.Mode.search, f.vm.mode());
    try std.testing.expectEqualStrings("搜索结果", f.vm.title());
    try std.testing.expectEqualStrings("重连", f.vm.searchText());
    try std.testing.expect(f.vm.backEnabled() and !f.vm.forwardEnabled());
    try std.testing.expect(f.vm.paneVisible("settings.ssh.reconnect"));

    f.vm.dispatch(.back);
    try std.testing.expectEqual(m.Mode.panes, f.vm.mode());
    try std.testing.expectEqualStrings("", f.vm.searchText());
    try std.testing.expectEqual(m.Location{ .page = 3, .sub = 2 }, f.vm.location());

    f.host.search = false;
    f.host.clear();
    f.vm.dispatch(m.Intent.searchFor("ssh"));
    try std.testing.expectEqual(@as(usize, 0), f.host.len);
    try std.testing.expectEqualStrings("", f.vm.searchText());
}

test "settings view model search field is a controlled value: written synchronously, kept when the gate refuses, cleared by navigation (S-4)" {
    var f: Fixture = undefined;
    try f.init(.{});
    defer f.deinit();
    try std.testing.expectEqualStrings("", f.vm.searchField());
    f.vm.dispatch(m.Intent.searchFor("重连"));
    try std.testing.expectEqualStrings("重连", f.vm.searchField());
    try std.testing.expectEqualStrings("重连", f.vm.searchText());
    // 关口拒绝（MCP 编辑中）：不搜索，但框里的文字照常落地（旧 Zig 搜索框的行为）。
    f.host.search = false;
    f.vm.dispatch(m.Intent.searchFor("重连x"));
    try std.testing.expectEqualStrings("重连x", f.vm.searchField());
    try std.testing.expectEqualStrings("重连", f.vm.searchText());
    f.host.search = true;
    // 导航清空搜索词与搜索框，不再经宿主（没有 Effect）。
    f.host.clear();
    f.vm.dispatch(m.Intent.selectCategory(2));
    try f.host.expectTags(&.{ .leave_page, .navigated });
    try std.testing.expectEqualStrings("", f.vm.searchField());
    try std.testing.expectEqualStrings("", f.vm.searchText());
    // 后退离开搜索同样清空。
    f.vm.dispatch(m.Intent.searchFor("ssh"));
    f.vm.dispatch(.back);
    try std.testing.expectEqualStrings("", f.vm.searchField());
}

test "settings view model edit marks dirty and save round trip resets through save_finished" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var target = try runtime.RuntimeConfig.loadOrDefault(std.testing.io, tmp.dir, std.testing.allocator, "settings.toml");
    defer target.deinit();
    var f: Fixture = undefined;
    try f.init(target.value);
    defer f.deinit();
    try std.testing.expect(!f.vm.isDirty());
    try std.testing.expectEqual(m.SaveState.clean, f.vm.saveState());
    // H-save：干净时没有 Save Bar，也没有常驻的“所有更改已保存”。
    try std.testing.expect(!f.vm.footerVisible());

    f.vm.dispatch(m.Intent.editValue(font_size, .{ .unsigned = 18 }));
    try std.testing.expectEqual(@as(usize, 0), f.host.len);
    try std.testing.expect(f.vm.isDirty());
    try std.testing.expectEqual(m.SaveState.dirty_valid, f.vm.saveState());
    try std.testing.expectEqual(@as(u32, 18), f.vm.valueOf(font_size).?.unsigned);
    try std.testing.expectEqualStrings("未保存", f.vm.footerMessage());
    try std.testing.expect(f.vm.footerVisible());

    f.vm.dispatch(.draft_changed);
    try f.host.expectTags(&.{ .resolve_problems, .rebuild });

    // Save Bar：发出 Effect.save，宿主完成后回流 save_finished。
    f.host.clear();
    f.vm.dispatch(m.Intent.runCommand(.save));
    try f.host.expectTags(&.{.save});
    try std.testing.expect(!f.host.effects[0].save.close_after);
    var request = try f.controller.beginSave(&target, false);
    defer request.deinit();
    f.vm.sync();
    try std.testing.expect(f.vm.isSaving());
    try std.testing.expect(!f.vm.backEnabled());
    try std.testing.expect(try f.controller.completeSave(std.testing.io, tmp.dir, &target, &request));
    f.host.clear();
    f.vm.dispatch(m.Intent.saveFinished(null));
    // 保存成功：view-model 发一条 Toast 请求（S-19，窗口模板的 `W.NotificationHost` 跟随）；Save Bar 随草稿干净而消失。
    try f.host.expectTags(&.{.saved});
    const toast = f.vm.toast();
    try std.testing.expect(toast.seq != 0);
    try std.testing.expectEqualStrings("设置已保存", toast.text);
    try std.testing.expectEqual(m.ToastTone.success, toast.tone);
    try std.testing.expect(!f.vm.isDirty());
    try std.testing.expect(!f.vm.footerVisible());
    try std.testing.expectEqual(m.SaveState.clean, f.vm.saveState());
    try std.testing.expectEqual(@as(u8, 18), target.value.ui.font_size);

    // 没有对话框时的“保存关闭”不算数（草稿干净时宿主 `toggle` 直接关窗，不经对话框）。
    f.host.clear();
    f.vm.dispatch(m.Intent.saveDraft(true));
    try std.testing.expectEqual(@as(usize, 0), f.host.len);
}

test "settings view model save and close closes only after a committed save" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var target = try runtime.RuntimeConfig.loadOrDefault(std.testing.io, tmp.dir, std.testing.allocator, "settings.toml");
    defer target.deinit();
    var f: Fixture = undefined;
    try f.init(target.value);
    defer f.deinit();
    f.vm.dispatch(m.Intent.editValue(font_size, .{ .unsigned = 20 }));
    // 没有对话框时的“保存关闭”不算数（选择只对打开的对话框有效）。
    f.vm.dispatch(m.Intent.decideWith(.save));
    try std.testing.expectEqual(@as(usize, 0), f.host.len);

    f.vm.askClose();
    try std.testing.expectEqual(m.Prompt.close, f.vm.promptKind());
    try std.testing.expectEqualStrings("保存关闭", f.vm.promptSaveLabel());
    f.host.clear();
    f.vm.dispatch(m.Intent.decideWith(.save));
    try f.host.expectTags(&.{ .prompt, .save });
    try std.testing.expect(f.host.effects[1].save.close_after);
    try std.testing.expect(!f.vm.promptOpen());
    // 宿主报告失败：不关窗，草稿保留，错误 Toast 由 view-model 发出（S-19）。
    f.host.clear();
    const before = f.vm.toast().seq;
    f.vm.dispatch(m.Intent.saveFinished(error.AccessDenied));
    try f.host.expectTags(&.{.save_failed});
    try std.testing.expect(f.vm.isDirty());
    // 错误 Toast：新请求、带原因。
    try std.testing.expect(f.vm.toast().seq != before);
    try std.testing.expectEqual(m.ToastTone.failure, f.vm.toast().tone);
    try std.testing.expect(std.mem.startsWith(u8, f.vm.toast().text, "保存失败"));

    var request = try f.controller.beginSave(&target, true);
    defer request.deinit();
    try std.testing.expect(try f.controller.completeSave(std.testing.io, tmp.dir, &target, &request));
    f.host.clear();
    f.vm.dispatch(m.Intent.saveFinished(null));
    // “保存关闭”提交后直接关窗，不弹 Toast。
    try f.host.expectTags(&.{.close_window});

    // 宿主拒绝保存（输入法组合中等）：什么也不发。
    f.vm.dispatch(m.Intent.editValue(font_size, .{ .unsigned = 16 }));
    f.host.save = false;
    f.host.clear();
    f.vm.dispatch(m.Intent.runCommand(.save));
    try std.testing.expectEqual(@as(usize, 0), f.host.len);
}

test "settings view model invalid draft reports and navigates to the problem instead of saving" {
    var f: Fixture = undefined;
    try f.init(.{});
    defer f.deinit();
    f.controller.editRaw("ssh", "socks_port", "not a port") catch {};
    const problem = f.controller.validationProblem().?;
    f.vm.dispatch(.draft_changed);
    try f.host.expectTags(&.{.rebuild});
    try std.testing.expectEqual(m.SaveState.dirty_invalid, f.vm.saveState());

    f.host.clear();
    f.vm.dispatch(m.Intent.runCommand(.save));
    try f.host.expectTags(&.{ .report_problem, .focus_problem, .leave_page, .navigated });
    try std.testing.expect(!f.host.has(.save));
    try std.testing.expectEqual(@as(u8, @intCast(problem.page)), f.vm.location().page);
    try std.testing.expectEqual(m.Location{ .page = 2, .sub = 1 }, f.vm.location());
}

test "settings view model commands decisions and notification authorization effects" {
    var f: Fixture = undefined;
    try f.init(.{});
    defer f.deinit();
    const Pair = struct { m.Command, EffectTag };
    for ([_]Pair{
        .{ .revert, .revert },                 .{ .import_theme, .import_theme },
        .{ .export_logs, .export_logs },       .{ .clear_logs, .clear_logs },          .{ .clear_all, .clear_all },
        .{ .open_config_dir, .open_config_dir }, .{ .credential_help, .explain_credentials }, .{ .check_updates, .check_updates },
        .{ .open_update_release, .open_update_release }, .{ .notification_permission, .open_notification_permission },
    }) |pair| {
        f.host.clear();
        f.vm.dispatch(m.Intent.runCommand(pair[0]));
        try f.host.expectTags(&.{pair[1]});
    }

    // 关窗确认：“继续编辑”收起（宿主撤回挂起的原生关窗），“放弃”放弃并关窗。
    f.host.clear();
    f.vm.askClose();
    f.vm.dispatch(m.Intent.decideWith(.cancel));
    f.vm.askClose();
    f.vm.dispatch(m.Intent.decideWith(.discard));
    try f.host.expectTags(&.{ .prompt, .prompt, .dismiss_decision, .prompt, .prompt, .discard_and_close });

    // 事件提醒开关从关到开才申请系统授权。
    const transfer_done: m.Key = .{ .section = "notify", .key = "transfer_done" };
    f.vm.dispatch(m.Intent.editValue(transfer_done, .{ .boolean = false }));
    f.host.clear();
    f.vm.dispatch(m.Intent.editValue(transfer_done, .{ .boolean = true }));
    try f.host.expectTags(&.{.request_notification_authorization});
    try std.testing.expect(f.vm.boolOf(transfer_done));
    f.host.clear();
    f.vm.dispatch(m.Intent.editValue(transfer_done, .{ .boolean = true }));
    try std.testing.expectEqual(@as(usize, 0), f.host.len);

    // 写不进 schema 的值：Effect.failed 交给宿主报告。
    f.host.clear();
    f.vm.dispatch(m.Intent.editValue(.{ .section = "ui", .key = "no_such_key" }, .{ .boolean = true }));
    try f.host.expectTags(&.{.failed});
}

test "settings view model selectors track signals and detach forgets them" {
    var f: Fixture = undefined;
    try f.init(.{});
    defer f.deinit();
    const before = f.vm.signals.?.revision.peek();
    f.vm.dispatch(m.Intent.selectCategory(6));
    try std.testing.expect(f.vm.signals.?.revision.peek() > before);
    try std.testing.expectEqual(m.Location{ .page = 6 }, f.vm.signals.?.location.peek());
    f.vm.detach();
    try std.testing.expect(!f.vm.attached());
    // 未挂窗口时照常 dispatch（例如重新打开窗口前定位），Controller 仍是唯一真相。
    f.vm.dispatch(m.Intent.openAt(.{ .page = 7, .sub = 1 }));
    try std.testing.expectEqual(m.Location{ .page = 7, .sub = 1 }, f.controller.location());
    try f.vm.attach(f.scope);
    try std.testing.expectEqual(m.Location{ .page = 7, .sub = 1 }, f.vm.location());
    try std.testing.expectEqualStrings("会话记录", f.vm.title());
}

test "settings view model stays readable between detach and the window scope's cleanup (discard and close)" {
    var f: Fixture = undefined;
    try f.init(.{});
    defer f.deinit();
    // ⌘W → 放弃更改: the host detaches while the window scope (and its memos) retires only at
    // the next safe boundary; a memo recomputed in that window must not find the signals gone.
    const window = try f.scope.childScope();
    try f.vm.attach(window);
    f.vm.detach();
    try std.testing.expect(!f.vm.attached());
    _ = f.vm.statusLine();
    _ = f.vm.title();
    window.dispose();
    try std.testing.expect(f.vm.signals == null);
    // A later window attaches fresh signals; an older scope's cleanup cannot clear them.
    try f.vm.attach(f.scope);
    try std.testing.expect(f.vm.attached());
}

test "settings view model window keys: Escape and ⌘W / ⌘, become host effects unless the gate refuses (S-6)" {
    var f: Fixture = undefined;
    try f.init(.{});
    defer f.deinit();
    f.host.clear();
    try std.testing.expect(f.vm.windowKey(.escape, .{}));
    try std.testing.expect(f.vm.windowKey(.w, .{ .super = true }));
    try std.testing.expect(f.vm.windowKey(.comma, .{ .super = true }));
    try std.testing.expect(!f.vm.windowKey(.a, .{}));
    try f.host.expectTags(&.{ .escape, .request_close, .request_close });
    // 确认对话框（原生 Modal）打开：按键归它（Escape 由浮层栈收起）。
    f.vm.askClose();
    f.host.clear();
    try std.testing.expect(!f.vm.windowKey(.escape, .{}));
    try std.testing.expectEqual(@as(usize, 0), f.host.len);
    f.vm.dismissPrompt();
    // 录制快捷键：放行（返回 false，模板不 stop），不发 Effect。
    f.host.window_keys = false;
    f.host.clear();
    try std.testing.expect(!f.vm.windowKey(.escape, .{}));
    try std.testing.expect(!f.vm.windowKey(.w, .{ .super = true }));
    try std.testing.expectEqual(@as(usize, 0), f.host.len);
}

// ── H-save：作用域、离开确认、恢复默认、Toast ──

const keepalive: m.Key = .{ .section = "ssh", .key = "keepalive_sec" };
const socks_port: m.Key = .{ .section = "ssh", .key = "socks_port" };

test "settings view model leaving a subpage with unsaved changes asks first: cancel stays, discard leaves clean" {
    var f: Fixture = undefined;
    try f.init(.{});
    defer f.deinit();
    f.vm.dispatch(m.Intent.openAt(.{ .page = 2, .sub = 0 }));
    // 干净的子页面：没有 Save Bar；切页不确认。
    try std.testing.expect(!f.vm.footerVisible());
    f.vm.dispatch(m.Intent.openAt(.{ .page = 2, .sub = 1 }));
    try std.testing.expectEqual(m.Location{ .page = 2, .sub = 1 }, f.vm.location());
    f.vm.dispatch(.back);
    try std.testing.expectEqual(m.Location{ .page = 2, .sub = 0 }, f.vm.location());

    f.vm.dispatch(m.Intent.editValue(keepalive, .{ .unsigned = 45 }));
    try std.testing.expect(f.vm.footerVisible());
    // 去别的子页面：挂起，弹“未保存的设置”，位置不变。
    f.host.clear();
    f.vm.dispatch(m.Intent.openAt(.{ .page = 2, .sub = 1 }));
    try f.host.expectTags(&.{.prompt});
    try std.testing.expectEqual(m.Prompt.leave, f.vm.promptKind());
    try std.testing.expectEqualStrings("保存", f.vm.promptSaveLabel());
    try std.testing.expect(std.mem.indexOf(u8, f.vm.promptMessage(), "连接") != null);
    try std.testing.expectEqual(m.Location{ .page = 2, .sub = 0 }, f.vm.location());
    // 对话框开着时别的导航不叠加。
    f.vm.dispatch(m.Intent.selectCategory(6));
    try std.testing.expectEqual(m.Location{ .page = 2, .sub = 0 }, f.vm.location());
    // 继续编辑：留在原处，草稿还在。
    f.host.clear();
    f.vm.dispatch(m.Intent.decideWith(.cancel));
    try f.host.expectTags(&.{ .prompt, .dismiss_decision });
    try std.testing.expect(!f.vm.promptOpen() and f.vm.isDirty());
    try std.testing.expectEqual(m.Location{ .page = 2, .sub = 0 }, f.vm.location());
    // 后退（回到外观概览，作用域为空）同样要确认；放弃：宿主撤销草稿后导航。
    f.vm.dispatch(.back);
    try std.testing.expectEqual(m.Prompt.leave, f.vm.promptKind());
    f.host.clear();
    f.controller.discard(); // 假宿主：`Effect.revert` 由宿主执行，这里预先放弃，模拟宿主同步完成。
    f.vm.dispatch(m.Intent.decideWith(.discard));
    try std.testing.expect(f.host.has(.revert));
    try std.testing.expect(f.host.has(.navigated));
    try std.testing.expectEqual(m.Location{ .page = 0 }, f.vm.location());
    try std.testing.expect(!f.vm.isDirty() and !f.vm.footerVisible());
}

test "settings view model leaving after save: the pending navigation runs only once the save commits" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var target = try runtime.RuntimeConfig.loadOrDefault(std.testing.io, tmp.dir, std.testing.allocator, "settings.toml");
    defer target.deinit();
    var f: Fixture = undefined;
    try f.init(target.value);
    defer f.deinit();
    f.vm.dispatch(m.Intent.openAt(.{ .page = 2, .sub = 0 }));
    f.vm.dispatch(m.Intent.editValue(keepalive, .{ .unsigned = 46 }));
    f.vm.dispatch(m.Intent.selectCategory(6));
    f.host.clear();
    f.vm.dispatch(m.Intent.decideWith(.save));
    try f.host.expectTags(&.{ .prompt, .save });
    try std.testing.expect(!f.host.effects[1].save.close_after);
    try std.testing.expectEqual(m.Location{ .page = 2, .sub = 0 }, f.vm.location());
    // 失败：留在原处，去向作废。
    f.vm.dispatch(m.Intent.saveFinished(error.AccessDenied));
    try std.testing.expectEqual(m.Location{ .page = 2, .sub = 0 }, f.vm.location());
    // 再走一遍，这次提交成功：Toast，然后去通知页。
    f.vm.dispatch(m.Intent.selectCategory(6));
    f.vm.dispatch(m.Intent.decideWith(.save));
    var request = try f.controller.beginSave(&target, false);
    defer request.deinit();
    try std.testing.expect(try f.controller.completeSave(std.testing.io, tmp.dir, &target, &request));
    f.host.clear();
    f.vm.dispatch(m.Intent.saveFinished(null));
    try std.testing.expect(f.host.has(.saved) and f.host.has(.navigated));
    try std.testing.expectEqual(m.Location{ .page = 6 }, f.vm.location());
    try std.testing.expectEqual(@as(u16, 46), target.value.ssh.keepalive_sec);
}

test "settings view model search: entering keeps the draft, clearing back to a page that cannot hold it asks" {
    var f: Fixture = undefined;
    try f.init(.{});
    defer f.deinit();
    f.vm.dispatch(m.Intent.openAt(.{ .page = 2, .sub = 0 }));
    f.vm.dispatch(m.Intent.searchFor("通知"));
    try std.testing.expectEqual(m.Mode.search, f.vm.mode());
    // 在搜索结果里改了别的分类的字段，再清空搜索：回到“连接”装不下它，先确认。
    f.vm.dispatch(m.Intent.editValue(.{ .section = "notify", .key = "bell" }, .{ .boolean = true }));
    f.vm.dispatch(m.Intent.searchFor(""));
    try std.testing.expectEqual(m.Prompt.leave, f.vm.promptKind());
    try std.testing.expectEqual(m.Mode.search, f.vm.mode());
    try std.testing.expectEqualStrings("", f.vm.searchField());
    // 继续编辑：搜索框回到当前搜索词。
    f.vm.dispatch(m.Intent.decideWith(.cancel));
    try std.testing.expectEqualStrings("通知", f.vm.searchField());
    try std.testing.expectEqual(m.Mode.search, f.vm.mode());
}

test "settings view model reset defaults: only where the scope differs from defaults, and only the scope" {
    var f: Fixture = undefined;
    try f.init(.{});
    defer f.deinit();
    // 概览没有“恢复默认”。
    f.vm.dispatch(m.Intent.selectCategory(2));
    try std.testing.expect(!f.vm.resetShown());
    f.vm.dispatch(m.Intent.openSubpage(0));
    try std.testing.expect(f.vm.resetShown());
    // 默认值的页面：不可点，命令也不弹确认。
    try std.testing.expect(!f.vm.resetEnabled());
    f.host.clear();
    f.vm.dispatch(m.Intent.runCommand(.reset_defaults));
    try std.testing.expect(!f.vm.promptOpen());
    // 本页改一个值、别的子页面也有一个非默认值（直接写进 Controller，模拟已保存的配置）。
    f.vm.dispatch(m.Intent.editValue(keepalive, .{ .unsigned = 50 }));
    try std.testing.expect(f.vm.resetEnabled());
    f.vm.dispatch(m.Intent.runCommand(.reset_defaults));
    try std.testing.expectEqual(m.Prompt.reset, f.vm.promptKind());
    try std.testing.expect(!f.vm.promptAsksSave() and f.vm.promptAsksReset());
    // 取消：什么也不变。
    f.vm.dispatch(m.Intent.decideWith(.cancel));
    try std.testing.expectEqual(@as(u32, 50), f.vm.valueOf(keepalive).?.unsigned);
    // 关口拒绝（外观 worker 忙）：确认后也不改。
    f.vm.dispatch(m.Intent.runCommand(.reset_defaults));
    f.host.reset = false;
    f.vm.dispatch(m.Intent.decideWith(.reset));
    try std.testing.expectEqual(@as(u32, 50), f.vm.valueOf(keepalive).?.unsigned);
    f.host.reset = true;
    f.vm.dispatch(m.Intent.runCommand(.reset_defaults));
    f.host.clear();
    f.vm.dispatch(m.Intent.decideWith(.reset));
    try std.testing.expect(f.host.has(.rebuild));
    try std.testing.expectEqual(@as(u32, 30), f.vm.valueOf(keepalive).?.unsigned);
    try std.testing.expect(!f.vm.resetEnabled());
    // 初始配置就是默认值：恢复后与已保存的相同，草稿回到干净。
    try std.testing.expect(!f.vm.isDirty());
}

test "settings view model reset defaults leaves other subpages and their invalid input alone" {
    var value: @import("../../../config/config.zig").Config = .{};
    value.ssh.socks_port = 2080;
    value.ssh.keepalive_sec = 40;
    var f: Fixture = undefined;
    try f.init(value);
    defer f.deinit();
    f.vm.dispatch(m.Intent.openAt(.{ .page = 2, .sub = 0 }));
    try std.testing.expect(f.vm.resetEnabled());
    f.vm.dispatch(m.Intent.runCommand(.reset_defaults));
    f.vm.dispatch(m.Intent.decideWith(.reset));
    try std.testing.expectEqual(@as(u32, 30), f.vm.valueOf(keepalive).?.unsigned);
    try std.testing.expectEqual(@as(u32, 2080), f.vm.valueOf(socks_port).?.unsigned);
    // 恢复默认是草稿：与已保存的不同，Save Bar 出现，可撤销。
    try std.testing.expect(f.vm.isDirty() and f.vm.footerVisible() and f.vm.revertEnabled());
}
