//! 已改写为 `.yix` 的四个分类（P3 3e：通知、SSH 与网络、文件传输、数据与日志）的组件测试。
//! 夹具（`rows_fixture.yix`）挂真实面板 + 真 `ViewModel` + Ports 替身；只用 test_id、可见文字、`disabled`、
//! 草稿（Controller）与 view-model 的选择器断言。每个分类：字段齐全且顺序与旧面板相同、编辑 → 草稿 → 未保存、
//! 校验提示与定位、依赖置灰、切换开关时同页其它节点不变且开关在滑动、搜索过滤、主题发布后颜色跟随。
const std = @import("std");
const ui = @import("ui");
const kit = @import("../../../shared/testing/ui_kit.zig");
const Controller = @import("../model/settings_controller.zig").Controller;
const RuntimeConfig = @import("../../../config/runtime_config.zig").RuntimeConfig;
const m = @import("../model/view_model.zig");
const values = @import("../model/settings_values.zig");
const app_theme = @import("../../../shared/ui/theme/app_theme.zig");
const fixture = @import("_rows_fixture.yix.zig");

const Panes = struct {
    env: kit.Headless,
    tmp: std.testing.TmpDir,
    runtime: RuntimeConfig,
    controller: Controller,
    vm: m.ViewModel,
    effects: std.ArrayList(m.Effect) = .empty,
    status: m.HostStatus = .{},
    root: *ui.Node = undefined,

    fn init(self: *Panes, query: []const u8) !void {
        const a = std.testing.allocator;
        self.* = .{ .env = try kit.headless(a, .{ .width = 760, .height = 3600, .root_style = .{ .width = .fill(), .height = .fill(), .direction = .column } }), .tmp = std.testing.tmpDir(.{}), .runtime = undefined, .controller = undefined, .vm = undefined };
        self.runtime = try RuntimeConfig.loadOrDefault(std.testing.io, self.tmp.dir, a, "config.toml");
        self.controller = try Controller.init(a, self.runtime.value);
        if (query.len != 0) try self.controller.setSearch(query);
        self.vm = m.ViewModel.init(&self.controller, .{ .context = self, .run = run, .allow = allow, .status = hostStatus });
        try self.vm.attach(self.env.scope);
        self.root = try ui.view.render(self.env.scope, self.env.cx, fixture.RowsFixture(.{ .vm = &self.vm }));
        try self.env.mount(self.root);
        self.env.frames(2);
    }
    fn deinit(self: *Panes) void {
        self.env.deinit();
        self.effects.deinit(std.testing.allocator);
        self.controller.deinit();
        self.runtime.deinit();
        self.tmp.cleanup();
    }
    fn run(raw: *anyopaque, effect: m.Effect) void {
        const self: *Panes = @ptrCast(@alignCast(raw));
        self.effects.append(std.testing.allocator, effect) catch {};
    }
    fn allow(_: *anyopaque, _: m.Gate) bool {
        return true;
    }
    fn hostStatus(raw: *anyopaque) m.HostStatus {
        const self: *Panes = @ptrCast(@alignCast(raw));
        return self.status;
    }
    fn node(self: *Panes, id: []const u8) !*ui.Node {
        return kit.expectByTestId(self.root, id);
    }
    fn click(self: *Panes, id: []const u8) !void {
        const rect = (try self.node(id)).globalRect();
        self.env.cx.handleClick(rect.x + rect.w / 2, rect.y + rect.h / 2);
        self.env.frame();
    }
    fn typeInto(self: *Panes, id: []const u8, text: []const u8) !void {
        self.env.cx.setFocus(try self.node(id));
        self.env.cx.handleKeyDown(.a, .{ .super = true });
        self.env.cx.handleTextInput(text);
        self.env.frame();
    }
    /// 整窗 Escape 在面板里的那一层，按宿主的方式取真实焦点（`SettingsHost.windowEscape`）。
    fn escape(self: *Panes) bool {
        // 真实窗口：改过的输入框先由原生 Input 回到聚焦时的值（OverlayHost → `Cx.input_escape`），再到宿主分层。
        @import("../../../shared/ui/overlay/overlay_host.zig").install(self.env.cx);
        if (ui.widgets.input.revertFocused(self.env.cx)) {
            self.env.frame();
            return true;
        }
        const focused = self.env.cx.focus_manager.getFocused();
        return self.vm.consumeEscape(if (focused) |owner| self.env.cx.focus_targets.targetName(self.env.cx, owner) else null);
    }
    fn read(self: *Panes, section: []const u8, key: []const u8) values.Value {
        return values.read(self.controller.model.value, section, key).?;
    }
    fn hasEffect(self: *Panes, tag: std.meta.Tag(m.Effect)) bool {
        for (self.effects.items) |effect| if (effect == tag) return true;
        return false;
    }
};

fn shown(node: *ui.Node) bool {
    var cursor: ?*ui.Node = node;
    while (cursor) |current| : (cursor = current.parent) if (current.style.display == .none) return false;
    return node.globalRect().h > 0;
}
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
/// 面板里按树序出现的 test_id（只收 `prefixes` 开头的）。
fn idsIn(node: *ui.Node, prefixes: []const []const u8, out: *std.ArrayList([]const u8)) !void {
    if (node.meta.ownership.meta.test_id) |id| for (prefixes) |prefix| if (std.mem.startsWith(u8, id, prefix)) {
        try out.append(std.testing.allocator, id);
        break;
    };
    for (node.children.items) |child| try idsIn(child, prefixes, out);
}
fn expectOrder(p: *Panes, pane: []const u8, prefixes: []const []const u8, expected: []const []const u8) !void {
    var list: std.ArrayList([]const u8) = .empty;
    defer list.deinit(std.testing.allocator);
    try idsIn(try p.node(pane), prefixes, &list);
    try std.testing.expectEqual(expected.len, list.items.len);
    for (expected, list.items) |want, got| try std.testing.expectEqualStrings(want, got);
}
fn collectNodes(node: *ui.Node, out: *std.ArrayList(*ui.Node)) !void {
    try out.append(std.testing.allocator, node);
    for (node.children.items) |child| try collectNodes(child, out);
}
fn switchThumb(node: *ui.Node) *ui.Node {
    return node.children.items[0].children.items[0];
}
fn translateSlotActive(node: *ui.Node) bool {
    if (node.frame_state.frame_local.runtime.transitions) |slots| if (slots.find(.translate_x)) |slot| return slot.active;
    return false;
}
/// 切换一个开关：同一分类里其它节点全部原样保留（指针相同、仍在树上），开关的滑块在走 translate 过渡。
fn expectLocalToggle(p: *Panes, category: []const u8, field: []const u8) !void {
    var before: std.ArrayList(*ui.Node) = .empty;
    defer before.deinit(std.testing.allocator);
    try collectNodes(try p.node(category), &before);
    try p.click(field);
    try std.testing.expect(translateSlotActive(switchThumb(try p.node(field))));
    var after: std.ArrayList(*ui.Node) = .empty;
    defer after.deinit(std.testing.allocator);
    try collectNodes(try p.node(category), &after);
    try std.testing.expectEqual(before.items.len, after.items.len);
    for (before.items, after.items) |a, b| try std.testing.expect(a == b);
}

const row_prefixes = [_][]const u8{ "settings.row.", "settings.notifications.permission", "settings.field.download_dir", "settings.path.", "settings.data." };

test "settings panes notify: fields in the legacy order, edit marks the draft, quiet hours validation and permission state" {
    var p: Panes = undefined;
    try p.init("");
    defer p.deinit();
    try expectOrder(&p, "settings.notifications.events", &.{"settings.row."}, &.{ "settings.row.transfer_done", "settings.row.reconnect", "settings.row.ai_ready", "settings.row.bell" });
    _ = try p.node("settings.notifications.permission");
    try expectOrder(&p, "settings.notifications.attention", &.{"settings.row."}, &.{ "settings.row.tab_dot", "settings.row.quiet_hours" });
    var buffer: [512]u8 = undefined;
    try std.testing.expect(std.mem.startsWith(u8, textOf(try p.node("settings.notifications.events"), &buffer), "事件提醒后台事件与终端声音"));
    // 开关 → 草稿 → 未保存；事件提醒从关到开申请系统授权。
    const before = p.read("notify", "ai_ready").boolean;
    try expectLocalToggle(&p, "settings.notifications", "settings.field.ai_ready");
    try std.testing.expectEqual(!before, p.read("notify", "ai_ready").boolean);
    try std.testing.expect(p.vm.isDirty());
    if (!before) try std.testing.expect(p.hasEffect(.request_notification_authorization));
    // 勿扰时段：无效原文保留、行内提示、标红；改回有效值提示消失。
    try p.typeInto("settings.field.quiet_hours", "25:00-08:00");
    try std.testing.expect(shown(try p.node("settings.error.quiet_hours")));
    try std.testing.expect(std.mem.indexOf(u8, textOf(try p.node("settings.error.quiet_hours"), &buffer), "请输入有效时段") != null);
    try std.testing.expect(!p.hasEffect(.failed));
    try std.testing.expectEqualStrings("25:00-08:00", p.vm.fieldText(m.fields.notify.quiet_hours));
    try p.typeInto("settings.field.quiet_hours", "22:00-08:00");
    try std.testing.expect(!shown(try p.node("settings.error.quiet_hours")));
    try std.testing.expectEqualStrings("22:00-08:00", p.read("notify", "quiet_hours").text);
    // 授权状态来自宿主：未授权 → “允许通知”；等待结果 → “等待授权…”；不可用 → 不给按钮。
    p.status.authorization_help = "通知尚未授权。";
    p.vm.sync();
    p.env.frame();
    try std.testing.expect(shown(try p.node("settings.notifications.permission.open")));
    try std.testing.expect(std.mem.indexOf(u8, textOf(try p.node("settings.notifications.permission"), &buffer), "未授权") != null);
    try std.testing.expect(std.mem.indexOf(u8, textOf(try p.node("settings.notifications.permission.open"), &buffer), "允许通知") != null);
    try p.click("settings.notifications.permission.open");
    try std.testing.expect(p.hasEffect(.open_notification_permission));
    p.status.authorization_feedback = "正在等待系统通知授权结果…";
    p.vm.sync();
    p.env.frame();
    try std.testing.expect(!shown(try p.node("settings.notifications.permission.open")));
    try std.testing.expect(std.mem.indexOf(u8, textOf(try p.node("settings.notifications.permission"), &buffer), "等待授权…") != null);
    // 等待中的回执不重复显示；授权请求的结果（失败 / 请求后的说明）显示在权限行下方（旧外壳写在 Save Bar 的状态位）。
    try std.testing.expect(!shown(try p.node("settings.notifications.permission.feedback")));
    p.status.authorization_feedback = "系统通知授权请求失败";
    p.vm.sync();
    p.env.frame();
    try std.testing.expect(shown(try p.node("settings.notifications.permission.feedback")));
    try std.testing.expectEqualStrings("系统通知授权请求失败", textOf(try p.node("settings.notifications.permission.feedback"), &buffer));
    p.status = .{};
    p.vm.sync();
    p.env.frame();
    try std.testing.expect(!shown(try p.node("settings.notifications.permission.open")));
    try std.testing.expect(std.mem.indexOf(u8, textOf(try p.node("settings.notifications.permission"), &buffer), "不可用") != null);
}

test "settings panes ssh: fields in the legacy order, reconnect dependencies grey out, the switch slides in place" {
    var p: Panes = undefined;
    try p.init("");
    defer p.deinit();
    try expectOrder(&p, "settings.ssh.connection", &.{"settings.row."}, &.{ "settings.row.keepalive_sec", "settings.row.connect_timeout_sec", "settings.row.term", "settings.row.compression", "settings.row.auto_shell_integration" });
    try expectOrder(&p, "settings.ssh.reconnect", &.{"settings.row."}, &.{ "settings.row.auto_reconnect", "settings.row.reconnect_max", "settings.row.reconnect_backoff", "settings.row.buffer_input" });
    try expectOrder(&p, "settings.ssh.socks", &.{"settings.row."}, &.{ "settings.row.socks_port", "settings.row.socks_bind" });
    try expectOrder(&p, "settings.ssh.authentication", &.{"settings.row."}, &.{ "settings.row.otp_modal", "settings.row.totp_autofill" });
    // 帮助：标题旁的“?”（提示在 `.tooltip`），易误用字段的说明写在标签下。
    _ = try p.node("settings.help.keepalive_sec");
    _ = try p.node("settings.help.content.socks_bind");
    try std.testing.expect(kit.findByTestId(p.root, "settings.help.socks_bind") == null);
    // 依赖：自动重连开着时次数可编辑；关掉后次数 / 间隔 / 缓存不可用（同一节点、没有重挂）。
    try std.testing.expect(p.read("ssh", "auto_reconnect").boolean);
    const max = try p.node("settings.field.reconnect_max");
    try std.testing.expect(!isOff(max));
    try expectLocalToggle(&p, "settings.ssh", "settings.field.auto_reconnect");
    try std.testing.expect(!p.read("ssh", "auto_reconnect").boolean);
    try std.testing.expect(max == try p.node("settings.field.reconnect_max"));
    try std.testing.expect(isOff(max));
    try std.testing.expect(isOff(try p.node("settings.field.reconnect_backoff")));
    try std.testing.expect(isOff(try p.node("settings.field.buffer_input")));
    // 输入 → 草稿：重连间隔按逗号序列显示。
    try std.testing.expectEqualStrings("1, 2, 4, 8, 16", p.vm.fieldText(m.fields.ssh.reconnect_backoff)[0..14]);
    try p.typeInto("settings.field.keepalive_sec", "45");
    try std.testing.expectEqual(@as(u32, 45), p.read("ssh", "keepalive_sec").unsigned);
    try std.testing.expect(p.vm.isDirty());
    try p.typeInto("settings.field.keepalive_sec", "0");
    try std.testing.expect(shown(try p.node("settings.error.keepalive_sec")));
    // Escape 撤回正在编辑（持有焦点）的输入框：回到聚焦时的值（这次聚焦从 30 开始，中间的有效草稿 45 不算），
    // 原生 Input 的统一规则（OverlayHost → `Cx.input_escape`）。
    try std.testing.expect(p.escape());
    try std.testing.expectEqualStrings("30", p.vm.fieldText(m.fields.ssh.keepalive_sec));
    p.env.frame();
    try std.testing.expect(!shown(try p.node("settings.error.keepalive_sec")));
    // 下一次 Escape（值已回到聚焦时）：让输入框失焦。
    try std.testing.expect(p.escape());
    // 清焦点经整窗根的 `focusRequest`（`.blur()`；夹具没有窗口根，这里只断言请求，再照做一次）。
    try std.testing.expect(p.vm.focusRequest().id == null);
    p.env.cx.setFocus(null);
    // 焦点不在输入框上（也没有弹层）时这一层不接，交给下一层（最终关窗）。
    try std.testing.expect(!p.escape());
    // 定位校验问题：出错的面板输入框收到焦点请求。
    try p.typeInto("settings.field.socks_port", "0");
    p.vm.dispatch(.locate_problem);
    try std.testing.expectEqualStrings(m.fields.ssh.socks_port.ids.focus, p.vm.focusRequest().id.?);
    // “自定义 TERM 声明…”在面板里原地编辑（S-13），不再请求宿主选择器。
    p.vm.dispatch(m.Intent.chooseFor(m.fields.ssh.term.key.?));
    try std.testing.expect(!p.hasEffect(.pick_directory));
    try std.testing.expect(p.vm.customOpen());
    p.vm.dispatch(m.Intent.popupChanged(m.ViewModel.custom_popup, false));
}

test "settings panes ssh: custom TERM opens a native Popover under the Select, edits a view-model draft and commits on Enter (S-13)" {
    var p: Panes = undefined;
    try p.init("");
    defer p.deinit();
    const original = try std.testing.allocator.dupe(u8, p.read("ssh", "term").text);
    defer std.testing.allocator.free(original);
    // 选择框里选“自定义 TERM 声明…”（原生 `W.Select` 的选项在窗口浮层根上）。
    try p.click("settings.field.term");
    p.env.frames(8);
    const option = try kit.expectByTestId(p.env.cx.root.?, "settings.term.option.custom");
    const or_ = option.globalRect();
    p.env.cx.handleClick(or_.x + or_.w / 2, or_.y + or_.h / 2);
    p.env.frames(4);
    try std.testing.expect(p.vm.customOpen());
    try std.testing.expectEqualStrings(original, p.read("ssh", "term").text);
    // 浮层是原生 Popover（默认面板），在选择框下方；说明在里面；焦点进了输入框，原文是当前 TERM。
    const chrome = try kit.expectByTestId(p.env.cx.root.?, m.ViewModel.custom_popup);
    const note = try kit.expectByTestId(p.env.cx.root.?, "settings.term.custom.note");
    try std.testing.expect(note.isDescendantOf(chrome));
    var buffer: [256]u8 = undefined;
    try std.testing.expectEqualStrings("自定义仅声明 TERM 名称，不保证对应终端兼容。", textOf(note, &buffer));
    const trigger = (try p.node("settings.field.term")).globalRect();
    const panel = chrome.globalRect();
    try std.testing.expect(panel.y >= trigger.y + trigger.h - 0.5);
    // 左缘对齐选择框；夹具窗口只有 760 宽，放不下时原生横向平移回视口（右侧留 8）。
    try std.testing.expect(panel.x <= trigger.x + 0.5 and panel.x + panel.w <= 760 - 8 + 0.5);
    const focused = p.env.cx.focus_manager.getFocused() orelse return error.TestNothingFocused;
    try std.testing.expect(focused.isDescendantOf(chrome));
    try std.testing.expectEqualStrings(original, p.vm.customText());
    // 逐字编辑只改草稿；空名提交不通过（原生 errorMsg），浮层留着。
    p.env.cx.handleKeyDown(.a, .{ .super = true });
    p.env.cx.handleKeyDown(.delete, .{});
    p.env.frame();
    p.env.cx.handleKeyDown(.@"return", .{});
    p.env.frames(2);
    try std.testing.expect(p.vm.customOpen());
    try std.testing.expect(p.vm.customInvalid());
    try std.testing.expectEqualStrings(original, p.read("ssh", "term").text);
    // 输入名字，Enter：写草稿、收起。
    p.env.cx.handleTextInput("vt100-custom");
    p.env.frame();
    try std.testing.expectEqualStrings("vt100-custom", p.vm.customText());
    try std.testing.expectEqualStrings(original, p.read("ssh", "term").text);
    p.env.cx.handleKeyDown(.@"return", .{});
    p.env.frames(4);
    try std.testing.expectEqualStrings("vt100-custom", p.read("ssh", "term").text);
    try std.testing.expect(!p.vm.customOpen());
    try std.testing.expect(p.vm.isDirty());
    try std.testing.expect(kit.findByTestId(p.env.cx.root.?, "settings.term.custom.note") == null or !shown(kit.findByTestId(p.env.cx.root.?, "settings.term.custom.note").?));
    // 选择框显示自定义的值（追加的一项）。
    try std.testing.expectEqualStrings("vt100-custom", p.vm.selectValue(m.fields.ssh.term).?);
    // 再打开、整窗 Escape：先收起浮层（草稿不变）。
    p.vm.dispatch(m.Intent.chooseFor(m.fields.ssh.term.key.?));
    p.env.frames(4);
    try std.testing.expect(p.vm.customOpen());
    try std.testing.expect(p.escape());
    p.env.frames(4);
    try std.testing.expect(!p.vm.customOpen());
    try std.testing.expectEqualStrings("vt100-custom", p.read("ssh", "term").text);
}

test "settings panes transfer: fields in the legacy order, live pane summaries and the window budget problem" {
    var p: Panes = undefined;
    try p.init("");
    defer p.deinit();
    try expectOrder(&p, "settings.transfer.connection", &.{"settings.row."}, &.{ "settings.row.dedicated_connection", "settings.row.shared_pacing_kbps" });
    try expectOrder(&p, "settings.transfer.engine", &.{"settings.row."}, &.{ "settings.row.window_chunks", "settings.row.chunk_kb", "settings.row.max_tasks", "settings.row.resume", "settings.row.verify_md5" });
    try expectOrder(&p, "settings.transfer.defaults", &.{ "settings.field.download_dir", "settings.row." }, &.{ "settings.field.download_dir", "settings.row.conflict_policy" });
    var buffer: [512]u8 = undefined;
    const summary = try p.node("settings.transfer.engine.summary");
    const before = try std.testing.allocator.dupe(u8, textOf(summary, &buffer));
    defer std.testing.allocator.free(before);
    try p.typeInto("settings.field.max_tasks", "7");
    try std.testing.expect(summary == try p.node("settings.transfer.engine.summary"));
    try std.testing.expect(std.mem.indexOf(u8, textOf(summary, &buffer), "7 并发") != null);
    try std.testing.expect(!std.mem.eql(u8, before, textOf(summary, &buffer)));
    // 窗口预算：分块过大时三个引擎字段都提示。
    try p.typeInto("settings.field.chunk_kb", "65535");
    try p.typeInto("settings.field.window_chunks", "255");
    try std.testing.expect(shown(try p.node("settings.error.chunk_kb")));
    try std.testing.expect(std.mem.indexOf(u8, textOf(try p.node("settings.error.chunk_kb"), &buffer), "单任务窗口超过 2 MiB") != null);
    // 改另一个策略字段把预算修好：提示消失，已输入的原文不变（原旧面板的 “actual Cx inputs” 用例，3f 迁到这里；
    // 并发回到默认的 3，只看单任务窗口预算）。
    try p.typeInto("settings.field.max_tasks", "3");
    try p.typeInto("settings.field.window_chunks", "33");
    try std.testing.expect(shown(try p.node("settings.error.window_chunks")));
    try p.typeInto("settings.field.chunk_kb", "32");
    try std.testing.expect(!shown(try p.node("settings.error.window_chunks")));
    try std.testing.expect(!shown(try p.node("settings.error.chunk_kb")));
    try std.testing.expectEqual(@as(u32, 33), p.read("transfer", "window_chunks").unsigned);
    try std.testing.expectEqual(@as(u32, 32), p.read("transfer", "chunk_kb").unsigned);
    // 下载目录直接交宿主的系统目录面板（`Effect.pick_directory`，S-13），不开浮层。
    try p.click("settings.field.download_dir");
    try std.testing.expect(p.hasEffect(.pick_directory));
    try std.testing.expect(!p.vm.customOpen());
    try expectLocalToggle(&p, "settings.transfer", "settings.field.verify_md5");
}

test "settings panes data: rows in the legacy order, host paths, action states and commands" {
    var p: Panes = undefined;
    try p.init("");
    defer p.deinit();
    // 配置文件 / 主机配置读不到时不显示；缓存与日志目录“由应用管理”。
    try std.testing.expect(kit.findByTestId(p.root, "settings.path.配置文件") == null);
    var buffer: [512]u8 = undefined;
    try std.testing.expect(std.mem.indexOf(u8, textOf(try p.node("settings.data.location"), &buffer), "由应用管理") != null);
    p.status.data_paths = .{ "/Users/me/.config/zerowork/config.toml", "/Users/me/.config/zerowork/hosts.toml", "/Users/me/Library/Caches/zerowork", null };
    p.vm.sync();
    p.env.frame();
    // 只读行由挂载时的形态决定显示与否：路径行在内容页重挂后出现（宿主的路径在打开窗口前就定了）。
    try std.testing.expect(std.mem.indexOf(u8, textOf(try p.node("settings.data.location"), &buffer), "/Users/me/Library/Caches/zerowork") != null);
    try expectOrder(&p, "settings.data.history", &.{"settings.row."}, &.{ "settings.row.ring_mb", "settings.row.checkpoint_sec", "settings.row.retention_days", "settings.row.export_format" });
    try expectOrder(&p, "settings.data.actions", &.{ "settings.data.export_logs", "settings.data.clear_logs", "settings.data.clear_all" }, &.{ "settings.data.export_logs", "settings.data.clear_logs", "settings.data.clear_all" });
    try p.click("settings.data.export_logs");
    try std.testing.expect(p.hasEffect(.export_logs));
    try p.click("settings.data.credential_help");
    try std.testing.expect(p.hasEffect(.explain_credentials));
    // 清理被宿主拦下：按钮不可用，悬停说明原因。
    p.status.clear_logs = .{ .enabled = false, .reason = "请先结束活动会话" };
    p.vm.sync();
    p.env.frame();
    try std.testing.expect(isOff(try p.node("settings.data.clear_logs")));
    try std.testing.expectEqualStrings("请先结束活动会话", p.vm.actionReason(m.fields.data.clear_logs));
    p.effects.clearRetainingCapacity();
    try p.click("settings.data.clear_logs");
    try std.testing.expect(!p.hasEffect(.clear_logs));
    try p.click("settings.data.clear_all");
    try std.testing.expect(p.hasEffect(.clear_all));
}

// 原 `shared/ui/tests/ui_constraint_tests.zig` 的“long directory”用例（挂旧 `mountPage`），3f 迁到 `.yix` 目录行。
test "settings panes long download directory keeps a bounded ellipsis label, a full-path tooltip and the real edit action" {
    var p: Panes = undefined;
    try p.init("");
    defer p.deinit();
    const path = "/Users/fixture/Downloads/团队服务器归档与诊断输出/production-cluster-2026-10-26/very-long-download-destination";
    try p.controller.editKey("transfer", "download_dir", .{ .text = path });
    p.vm.sync();
    p.env.frames(2);
    const button = try p.node("settings.field.download_dir");
    const label = kit.findByTestId(button, "settings.directory.label") orelse return error.TestDirectoryLabelMissing;
    try std.testing.expectEqualStrings(path, label.getText().?.content);
    try std.testing.expectEqual(@as(@TypeOf(label.getText().?.text_overflow), .ellipsis), label.getText().?.text_overflow);
    const outer = button.globalRect();
    const value = label.globalRect();
    try std.testing.expect(value.x >= outer.x);
    try std.testing.expect(value.x + value.w <= outer.x + outer.w);
    try std.testing.expect(value.w < p.env.cx.text.measureTextWidth(path, 12, 400, false));
    try std.testing.expectEqualStrings(path, button.behavior.interaction.a11y.?.label.?);
    p.env.cx.focus_manager.setFocusWithReason(button, .tab);
    p.env.frames(2);
    const tip = kit.findByTestId(p.env.cx.root.?, "settings.directory.tooltip") orelse return error.TestDirectoryTooltipMissing;
    try std.testing.expect(tip.globalRect().h > 24);
    try std.testing.expect(tip.globalRect().w <= 292);
    try std.testing.expect(p.escape());
    p.effects.clearRetainingCapacity();
    try p.click("settings.field.download_dir");
    try std.testing.expect(p.hasEffect(.pick_directory));
}

test "settings panes path and directory tooltips open on focus and the window Escape closes them first" {
    var p: Panes = undefined;
    try p.init("");
    defer p.deinit();
    p.status.data_paths = .{ null, null, "/Users/me/Library/Caches/zerowork", null };
    p.vm.sync();
    p.env.frame();
    // 路径行（旧 `HintFocus` + `registerTooltip`）：聚焦即打开全文提示；整窗 Escape 先收起提示（接下了，不关窗）。
    p.env.cx.setFocus(try p.node("settings.path.缓存目录"));
    p.env.frame();
    try std.testing.expect(p.vm.popupOpen("settings.path.缓存目录.tooltip"));
    try std.testing.expect(p.escape());
    try std.testing.expect(!p.vm.popupOpen("settings.path.缓存目录.tooltip"));
    try std.testing.expect(!p.escape());
    // 下载目录按钮：原生 Tooltip 在键盘聚焦 / 悬停时打开并经 `onOpenChange` 登记到 `popup`，整窗 Escape 同样先收起它。
    p.env.cx.focus_manager.setFocusWithReason(try p.node("settings.field.download_dir"), .tab);
    p.env.frame();
    try std.testing.expect(p.vm.popupOpen("settings.directory.tooltip"));
    try std.testing.expect(p.escape());
    try std.testing.expect(!p.vm.popupOpen("settings.directory.tooltip"));
    try std.testing.expect(!p.escape());
}

test "settings panes search keeps only matching panes and rows; the category name shows the whole category" {
    var p: Panes = undefined;
    try p.init("压缩");
    defer p.deinit();
    try std.testing.expect(shown(try p.node("settings.row.compression")));
    try std.testing.expect(!shown(try p.node("settings.row.keepalive_sec")));
    try std.testing.expect(!shown(try p.node("settings.ssh.socks")));
    try std.testing.expect(!shown(try p.node("settings.transfer.engine")));
    try std.testing.expect(p.vm.pageHits(2) and !p.vm.pageHits(3));
    // 最后一个命中的行下面没有分隔线。
    try std.testing.expectEqual(@as(f32, 0), divider(try p.node("settings.row.compression")));
    var q: Panes = undefined;
    try q.init("文件传输");
    defer q.deinit();
    for ([_][]const u8{ "settings.transfer.connection", "settings.transfer.engine", "settings.transfer.defaults" }) |id| try std.testing.expect(shown(try q.node(id)));
}

test "settings panes follow a theme publication without remounting and draw dividers between rows" {
    var p: Panes = undefined;
    try p.init("");
    defer p.deinit();
    const previous = app_theme.currentName();
    defer app_theme.select(previous);
    app_theme.select(.light);
    p.env.publishTheme();
    p.env.frames(2);
    const pane = try p.node("settings.ssh.connection");
    const card = pane.children.items[1];
    const light = card.getBackground();
    try std.testing.expect(ui.Color.eql(p.env.cx.tokens.tokens.color.zw_window_rest, light));
    // 相邻行之间一条 1pt `border` 发丝线，最后一行没有。
    const first = try p.node("settings.row.keepalive_sec");
    try std.testing.expectEqual(@as(f32, 1), divider(first));
    try std.testing.expect(ui.Color.eql(p.env.cx.tokens.tokens.color.border, first.style.border.color));
    try std.testing.expectEqual(@as(f32, 0), divider(try p.node("settings.row.auto_shell_integration")));
    const label = (try p.node("settings.help.keepalive_sec"));
    app_theme.select(.dark);
    p.env.publishTheme();
    p.env.frames(2);
    try std.testing.expect(pane == try p.node("settings.ssh.connection"));
    try std.testing.expect(label == try p.node("settings.help.keepalive_sec"));
    try std.testing.expect(!ui.Color.eql(light, card.getBackground()));
    try std.testing.expect(ui.Color.eql(p.env.cx.tokens.tokens.color.zw_window_rest, card.getBackground()));
    try std.testing.expect(ui.Color.eql(p.env.cx.tokens.tokens.color.border, first.style.border.color));
}

fn isOff(node: *ui.Node) bool {
    const a11y = node.behavior.interaction.a11y orelse return false;
    return a11y.disabled;
}
/// 行根底部发丝线的宽度（`side_widths` 未单独写时取整体宽度）。
fn divider(node: *ui.Node) f32 {
    const side = node.style.border.side_widths[2];
    return if (side < 0) node.style.border.width else side;
}
