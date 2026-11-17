//! 快捷键、关于与更新两个分类（P3 3e 第二批）的组件测试。夹具（`panes_b_fixture.yix`）挂真实面板 + 真 `ViewModel` + Ports 替身；
//! 只用 test_id、可见文字、`disabled`、草稿（Controller）与 view-model 的选择器断言。
//! 快捷键：行齐全且顺序与旧面板相同、键帽、固定行、行内录制状态机的每个转移（录制 → 提交 / Esc 取消 / 失焦、无效、冲突的交换与取消）、
//! 单行恢复默认的可用条件、录制期间整窗快捷键放行、局部更新、搜索、主题跟随。
//! 关于与更新：字段齐全与顺序、宿主状态投影（徽标 / 标题 / 按钮）、检查更新与发布来源只发 Effect、自动检查开关、搜索、主题跟随。
const std = @import("std");
const ui = @import("ui");
const kit = @import("../../../shared/testing/ui_kit.zig");
const Controller = @import("../model/settings_controller.zig").Controller;
const RuntimeConfig = @import("../../../config/runtime_config.zig").RuntimeConfig;
const m = @import("../model/view_model.zig");
const values = @import("../model/settings_values.zig");
const app_theme = @import("../../../shared/ui/theme/app_theme.zig");
const fixture = @import("_panes_b_fixture.yix.zig");
const keys = m.keybinding_edit;

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
        self.root = try ui.view.render(self.env.scope, self.env.cx, fixture.PanesBFixture(.{ .vm = &self.vm }));
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
    /// 点击键帽区进入录制，并把焦点放到它上面（夹具没有窗口模板根的 `focusRequest`）。
    fn record(self: *Panes, action: keys.Action) !void {
        var buffer: [64]u8 = undefined;
        const id = try std.fmt.bufPrint(&buffer, "settings.key.{s}", .{@tagName(action)});
        try self.click(id);
        self.env.cx.setFocus(try self.node(id));
        self.env.frame();
    }
    fn press(self: *Panes, key: ui.events.KeyCode, mods: ui.events.Modifiers) void {
        _ = self.env.cx.handleKeyDown(key, mods);
        self.env.frame();
    }
    fn chord(self: *Panes, action: keys.Action) keys.Chord {
        return self.controller.model.value.keys.get(action);
    }
    fn hasEffect(self: *Panes, tag: std.meta.Tag(m.Effect)) bool {
        for (self.effects.items) |effect| if (effect == tag) return true;
        return false;
    }
    fn text(self: *Panes, id: []const u8, buffer: []u8) ![]const u8 {
        return textOf(try self.node(id), buffer);
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
fn contains(haystack: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, haystack, needle) != null;
}
fn idsIn(node: *ui.Node, prefix: []const u8, out: *std.ArrayList([]const u8)) !void {
    if (node.meta.ownership.meta.test_id) |id| if (std.mem.startsWith(u8, id, prefix)) try out.append(std.testing.allocator, id);
    for (node.children.items) |child| try idsIn(child, prefix, out);
}
fn expectOrder(p: *Panes, pane: []const u8, prefix: []const u8, expected: []const []const u8) !void {
    var list: std.ArrayList([]const u8) = .empty;
    defer list.deinit(std.testing.allocator);
    try idsIn(try p.node(pane), prefix, &list);
    try std.testing.expectEqual(expected.len, list.items.len);
    for (expected, list.items) |want, got| try std.testing.expectEqualStrings(want, got);
}
/// 原生 `W.Kbd` 的键帽是它自己的按键列表（每键一个，按键文字作 key）：键帽增减时由组件增删，不算“重挂”——只收 Kbd 的根。
fn collectNodes(node: *ui.Node, out: *std.ArrayList(*ui.Node)) !void {
    try out.append(std.testing.allocator, node);
    if (node.meta.ownership.meta.component_name) |name| if (std.mem.eql(u8, name, "Kbd")) return;
    for (node.children.items) |child| try collectNodes(child, out);
}
fn snapshot(p: *Panes, id: []const u8) !std.ArrayList(*ui.Node) {
    var list: std.ArrayList(*ui.Node) = .empty;
    try collectNodes(try p.node(id), &list);
    return list;
}
/// 同一分类里原有的节点全部原样保留（指针相同、仍在树上）：按信号局部更新，没有重挂。焦点打开的原生 Tooltip
/// 会在触发点下挂上它的面板，所以只比较原有节点，不比较个数。
fn expectSameNodes(p: *Panes, id: []const u8, before: std.ArrayList(*ui.Node)) !void {
    var after = try snapshot(p, id);
    defer after.deinit(std.testing.allocator);
    for (before.items) |a| try std.testing.expect(std.mem.indexOfScalar(*ui.Node, after.items, a) != null);
    try std.testing.expect(after.items.len >= before.items.len);
}
fn firstFocusable(node: *ui.Node) ?*ui.Node {
    if (node.behavior.interaction.focusable) return node;
    for (node.children.items) |child| if (firstFocusable(child)) |found| return found;
    return null;
}
fn findKbd(node: *ui.Node) ?*ui.Node {
    if (node.meta.ownership.meta.component_name) |name| if (std.mem.eql(u8, name, "Kbd")) return node;
    for (node.children.items) |child| if (findKbd(child)) |found| return found;
    return null;
}
fn isOff(node: *ui.Node) bool {
    const a11y = node.behavior.interaction.a11y orelse return false;
    return a11y.disabled;
}

const tab_rows = [_][]const u8{ "settings.key.row.new_tab", "settings.key.row.close_tab", "settings.key.row.tab_1", "settings.key.row.tab_2", "settings.key.row.tab_3", "settings.key.row.tab_4", "settings.key.row.tab_5", "settings.key.row.tab_6", "settings.key.row.tab_7", "settings.key.row.tab_8", "settings.key.row.tab_9", "settings.key.row.previous_tab", "settings.key.row.next_tab", "settings.key.row.recent_tab", "settings.key.row.split_vertical", "settings.key.row.split_horizontal" };
const terminal_rows = [_][]const u8{ "settings.key.row.copy", "settings.key.row.paste", "settings.key.row.search", "settings.key.row.completion", "settings.key.row.accept_completion", "settings.key.row.quick_connect", "settings.key.row.reconnect", "settings.key.row.sidebar", "settings.key.row.ai", "settings.key.row.upload", "settings.key.row.broadcast" };

test "settings panes keys: every action in the legacy order, one keycap per key, fixed rows locked" {
    var p: Panes = undefined;
    try p.init("");
    defer p.deinit();
    try expectOrder(&p, "settings.keys.tabs", "settings.key.row.", &tab_rows);
    try expectOrder(&p, "settings.keys.terminal", "settings.key.row.", &terminal_rows);
    var buffer: [512]u8 = undefined;
    try std.testing.expectEqualStrings("16 个动作", try p.text("settings.keys.tabs.summary", &buffer));
    try std.testing.expect(contains(try p.text("settings.keys.terminal.summary", &buffer), "Control 与 Tab 保留给远端"));
    // 键帽：原生 `W.Kbd`，每个修饰键与主键一个键帽，文字与旧面板相同。
    try std.testing.expectEqualStrings("⌘T", try p.text("settings.key.new_tab", &buffer));
    try std.testing.expectEqualStrings("⇧⌘[", try p.text("settings.key.previous_tab", &buffer));
    try std.testing.expectEqualStrings("⌃Tab", try p.text("settings.key.recent_tab", &buffer));
    try std.testing.expectEqualStrings("→", try p.text("settings.key.accept_completion", &buffer));
    // 键帽是原生 `W.Kbd`（不是 Tag）：⌘T 两个键帽。
    const kbd = findKbd(try p.node("settings.key.new_tab")) orelse return error.TestNoKbd;
    var caps: usize = 0;
    for (kbd.children.items) |child| if (child.getText() != null) {
        caps += 1;
    };
    try std.testing.expectEqual(@as(usize, 2), caps);
    try std.testing.expect(contains(try p.text("settings.key.row.ai", &buffer), "AI 运维助手"));
    // 固定动作：键帽区不可点（点了不录制），锁图标说明原因；其它行可点、没有锁。
    for ([_][]const u8{ "settings.key.recent_tab", "settings.key.accept_completion" }) |id| try std.testing.expect(isOff(try p.node(id)));
    _ = try p.node("settings.key.fixed.recent_tab");
    _ = try p.node("settings.key.fixed.accept_completion");
    // 锁按钮获得键盘焦点：外层盒子的 `onFocusWithin` 打开提示，`onBlurWithin` 收起（G31）。
    const fixed_tip = m.fields.keys.row(.recent_tab).ids.button_tip;
    p.env.cx.setFocus(firstFocusable(try p.node("settings.key.fixed.recent_tab")) orelse return error.TestLockNotFocusable);
    p.env.frame();
    try std.testing.expect(p.vm.popupOpen(fixed_tip));
    p.env.cx.setFocus(null);
    p.env.frame();
    try std.testing.expect(!p.vm.popupOpen(fixed_tip));
    try std.testing.expect(kit.findByTestId(p.root, "settings.key.fixed.new_tab") == null);
    try std.testing.expect(!isOff(try p.node("settings.key.new_tab")));
    try p.click("settings.key.recent_tab");
    try std.testing.expectEqual(m.KeyPhase.idle, p.vm.keyPhase(.recent_tab));
    // 静止：没有“未保存”、没有单行恢复默认、没有说明行。
    try std.testing.expect(!shown(try p.node("settings.key.unsaved.new_tab")));
    try std.testing.expect(!shown(try p.node("settings.key.reset.new_tab")));
    try std.testing.expect(!shown(try p.node("settings.key.error.new_tab")));
    try std.testing.expectEqualStrings("点击修改快捷键", p.vm.keyTip(.new_tab));
    try std.testing.expectEqualStrings("此快捷键不可修改", p.vm.keyTip(.recent_tab));
}

test "settings panes keys: record then commit edits the draft in place; Escape and blur cancel without touching it" {
    var p: Panes = undefined;
    try p.init("");
    defer p.deinit();
    var before = try snapshot(&p, "settings.keys");
    defer before.deinit(std.testing.allocator);
    var buffer: [512]u8 = undefined;
    // 静止 → 录制：键帽区换成“按下新快捷键…”，焦点请求落到这一行。
    try p.record(.new_tab);
    try std.testing.expectEqual(m.KeyPhase.recording, p.vm.keyPhase(.new_tab));
    try std.testing.expectEqualStrings("focus:key.new_tab", p.vm.focusRequest().id.?);
    try std.testing.expect(contains(try p.text("settings.key.new_tab", &buffer), "按下新快捷键…"));
    try std.testing.expectEqualStrings("按下新快捷键，Esc 取消", p.vm.keyTip(.new_tab));
    // 录制中按住修饰键：实时显示。
    p.press(.left_super, .{ .super = true });
    try std.testing.expect(contains(try p.text("settings.key.new_tab", &buffer), "⌘"));
    try std.testing.expect(!contains(try p.text("settings.key.new_tab", &buffer), "T"));
    // 录制期间整窗快捷键不触发：⌘W 放行给这一行（一个待判定的组合）；Escape 由整窗捕获直接取消录制（G31）。
    try std.testing.expect(p.vm.keyCapturing());
    try std.testing.expect(!p.vm.windowKey(.w, .{ .super = true }));
    try std.testing.expect(!p.vm.windowKey(.comma, .{ .super = true }));
    try std.testing.expect(p.vm.windowKey(.escape, .{}));
    try std.testing.expect(!p.hasEffect(.escape) and !p.hasEffect(.request_close));
    // Esc：回到静止，草稿不变；之后 Escape 恢复为整窗分层。
    try std.testing.expectEqual(m.KeyPhase.idle, p.vm.keyPhase(.new_tab));
    try std.testing.expect(std.meta.eql(p.controller.model.value.keys, keys.Map{}));
    try std.testing.expect(!p.vm.isDirty());
    try std.testing.expect(p.vm.windowKey(.escape, .{}));
    try std.testing.expect(p.hasEffect(.escape));
    // Tab 离开键帽区（录制中）：按键照常移焦（不被接下），焦点离开键帽区（`onBlurWithin`，G31）回到静止。
    try p.record(.close_tab);
    try std.testing.expect(!p.vm.keyDown(.close_tab, .tab, .{}));
    try std.testing.expectEqual(m.KeyPhase.recording, p.vm.keyPhase(.close_tab));
    p.press(.tab, .{});
    try std.testing.expect(p.env.cx.focus_manager.getFocused() != try p.node("settings.key.close_tab"));
    try std.testing.expectEqual(m.KeyPhase.idle, p.vm.keyPhase(.close_tab));
    // 指针点到别处（焦点离开键帽区）同样结束录制。
    try p.record(.close_tab);
    p.env.cx.setFocus(try p.node("settings.key.search"));
    p.env.frame();
    try std.testing.expectEqual(m.KeyPhase.idle, p.vm.keyPhase(.close_tab));
    // 录制 → 合规组合：写草稿（整张表一次事务）、未保存、出现“未保存”与单行恢复默认；同页节点原样保留。
    try p.record(.new_tab);
    p.press(.k, .{ .super = true, .shift = true });
    try std.testing.expectEqual(m.KeyPhase.idle, p.vm.keyPhase(.new_tab));
    try std.testing.expect(p.chord(.new_tab).eql(.{ .key = .k, .shift = true }));
    try std.testing.expect(p.vm.isDirty());
    try std.testing.expectEqualStrings("⇧⌘K", try p.text("settings.key.new_tab", &buffer));
    try std.testing.expect(shown(try p.node("settings.key.unsaved.new_tab")));
    try std.testing.expect(shown(try p.node("settings.key.reset.new_tab")));
    try std.testing.expect(!shown(try p.node("settings.key.unsaved.close_tab")));
    try expectSameNodes(&p, "settings.keys", before);
    // 与当前值相同的组合：直接回到静止。
    try p.record(.new_tab);
    p.press(.k, .{ .super = true, .shift = true });
    try std.testing.expectEqual(m.KeyPhase.idle, p.vm.keyPhase(.new_tab));
}

test "settings panes keys: Enter / Space on the focused key area start recording; Tab moves on" {
    var p: Panes = undefined;
    try p.init("");
    defer p.deinit();
    const area = try p.node("settings.key.search");
    p.env.cx.setFocus(area);
    p.env.frame();
    p.press(.@"return", .{});
    try std.testing.expectEqual(m.KeyPhase.recording, p.vm.keyPhase(.search));
    // 录制中 Enter 不再激活按钮，而是一个待判定的组合（没有 ⌘：无效）。
    p.press(.@"return", .{});
    try std.testing.expectEqual(m.KeyPhase.invalid, p.vm.keyPhase(.search));
    try std.testing.expect(p.vm.windowKey(.escape, .{}));
    p.env.cx.setFocus(area);
    p.env.frame();
    p.press(.space, .{});
    try std.testing.expectEqual(m.KeyPhase.recording, p.vm.keyPhase(.search));
    // Tab 不接（照常移焦）。
    try std.testing.expect(!p.vm.keyDown(.search, .tab, .{}));
}

test "settings panes keys: invalid combinations explain why and keep the draft" {
    var p: Panes = undefined;
    try p.init("");
    defer p.deinit();
    var buffer: [512]u8 = undefined;
    try p.record(.new_tab);
    p.press(.x, .{ .super = true, .ctrl = true });
    try std.testing.expectEqual(m.KeyPhase.invalid, p.vm.keyPhase(.new_tab));
    try std.testing.expect(shown(try p.node("settings.key.error.new_tab")));
    try std.testing.expect(contains(try p.text("settings.key.error.new_tab", &buffer), "Control"));
    try std.testing.expect(!shown(try p.node("settings.key.swap.new_tab")));
    try std.testing.expectEqualStrings("⌃⌘X", try p.text("settings.key.new_tab", &buffer));
    // 无效态仍在录制：直接再按一次。
    try std.testing.expect(p.vm.keyCapturing());
    p.press(.x, .{});
    try std.testing.expect(contains(try p.text("settings.key.error.new_tab", &buffer), "Command"));
    p.press(.f5, .{ .super = true });
    try std.testing.expectEqual(m.KeyPhase.idle, p.vm.keyPhase(.new_tab));
    try std.testing.expect(p.chord(.new_tab).eql(.{ .key = .f5 }));
    // Tab 离开（无效态）：回到静止，草稿不变。
    try p.record(.close_tab);
    p.press(.w, .{ .super = true, .ctrl = true });
    p.press(.tab, .{});
    try std.testing.expectEqual(m.KeyPhase.idle, p.vm.keyPhase(.close_tab));
    try std.testing.expect(p.chord(.close_tab).eql(.{ .key = .w }));
    try std.testing.expect(!shown(try p.node("settings.key.error.close_tab")));
}

test "settings panes keys: a conflict names the other action and resolves in one step (swap) or cancels" {
    var p: Panes = undefined;
    try p.init("");
    defer p.deinit();
    var buffer: [512]u8 = undefined;
    // 冲突 → 取消：草稿不变。
    try p.record(.new_tab);
    p.press(.c, .{ .super = true });
    try std.testing.expectEqual(m.KeyPhase.conflict, p.vm.keyPhase(.new_tab));
    const message = try p.text("settings.key.error.new_tab", &buffer);
    try std.testing.expect(contains(message, "⌘C 已用于“复制”"));
    try std.testing.expect(contains(message, "改用 ⌘T"));
    try std.testing.expect(shown(try p.node("settings.key.swap.new_tab")));
    try p.click("settings.key.cancel.new_tab");
    try std.testing.expectEqual(m.KeyPhase.idle, p.vm.keyPhase(.new_tab));
    try std.testing.expect(std.meta.eql(p.controller.model.value.keys, keys.Map{}));
    // 冲突 → Tab 离开后提示仍在（不再接按键，可以 Tab 到【交换】【取消】），整窗 Escape 收起它。
    try p.record(.new_tab);
    p.press(.c, .{ .super = true });
    p.press(.tab, .{});
    try std.testing.expectEqual(m.KeyPhase.conflict, p.vm.keyPhase(.new_tab));
    try std.testing.expect(!p.vm.keyCapturing());
    try std.testing.expect(p.vm.consumeEscape(null));
    try std.testing.expectEqual(m.KeyPhase.idle, p.vm.keyPhase(.new_tab));
    // 冲突 → 交换：本动作取新组合，对方改用原来的组合。
    try p.record(.new_tab);
    p.press(.c, .{ .super = true });
    try p.click("settings.key.swap.new_tab");
    try std.testing.expectEqual(m.KeyPhase.idle, p.vm.keyPhase(.new_tab));
    try std.testing.expect(p.chord(.new_tab).eql(.{ .key = .c }));
    try std.testing.expect(p.chord(.copy).eql(.{ .key = .t }));
    try std.testing.expect(p.vm.isDirty());
    try std.testing.expectEqualStrings("⌘T", try p.text("settings.key.copy", &buffer));
    try std.testing.expect(shown(try p.node("settings.key.unsaved.copy")));
}

test "settings panes keys: per-row reset is offered only off the default and handles an occupied default" {
    var p: Panes = undefined;
    try p.init("");
    defer p.deinit();
    for (std.enums.values(keys.Action)) |action| try std.testing.expect(!p.vm.keyResettable(action));
    try p.record(.sidebar);
    p.press(.l, .{ .super = true });
    try std.testing.expect(p.vm.keyResettable(.sidebar));
    try std.testing.expect(shown(try p.node("settings.key.reset.sidebar")));
    try p.click("settings.key.reset.sidebar");
    try std.testing.expect(p.chord(.sidebar).eql(.{ .key = .b }));
    try std.testing.expect(!p.vm.keyResettable(.sidebar));
    try std.testing.expect(!shown(try p.node("settings.key.reset.sidebar")));
    try std.testing.expect(!p.vm.isDirty());
    // 默认值已被别的动作占用：恢复默认进入冲突态，交换一步解决。
    try p.record(.sidebar);
    p.press(.l, .{ .super = true });
    try p.record(.upload);
    p.press(.b, .{ .super = true });
    try std.testing.expect(p.chord(.upload).eql(.{ .key = .b }));
    try p.click("settings.key.reset.sidebar");
    try std.testing.expectEqual(m.KeyPhase.conflict, p.vm.keyPhase(.sidebar));
    try std.testing.expectEqual(m.KeyAction.upload, p.vm.signals.?.key_edit.peek().other.?);
    try p.click("settings.key.swap.sidebar");
    try std.testing.expect(p.chord(.sidebar).eql(.{ .key = .b }));
    try std.testing.expect(p.chord(.upload).eql(.{ .key = .l }));
    // 固定动作永远没有单行恢复默认。
    try std.testing.expect(!p.vm.keyResettable(.recent_tab));
}

test "settings panes keys: search matches action names, tags and the current chord; the category name shows everything" {
    var p: Panes = undefined;
    try p.init("上一个");
    defer p.deinit();
    try std.testing.expect(shown(try p.node("settings.key.row.previous_tab")));
    // 未命中的行不建（形态在挂载时定下）。
    try std.testing.expect(kit.findByTestId(p.root, "settings.key.row.new_tab") == null);
    try std.testing.expect(!shown(try p.node("settings.keys.terminal")));
    try std.testing.expect(p.vm.pageHits(1));
    var q: Panes = undefined;
    try q.init("快捷键");
    defer q.deinit();
    for (tab_rows ++ terminal_rows) |id| try std.testing.expect(shown(try q.node(id)));
    var r: Panes = undefined;
    try r.init("⇧⌘D");
    defer r.deinit();
    // 面板词没有命中“⇧⌘D”时整个面板不显示（旧面板相同）；“分栏”面板词命中时按组合过滤行。
    try std.testing.expect(!r.vm.pageHits(1));
    var s: Panes = undefined;
    try s.init("tab");
    defer s.deinit();
    try std.testing.expect(shown(try s.node("settings.key.row.new_tab")));
    try std.testing.expect(kit.findByTestId(s.root, "settings.key.row.copy") == null);
}

test "settings panes keys and updates follow a theme publication without remounting" {
    var p: Panes = undefined;
    try p.init("");
    defer p.deinit();
    const previous = app_theme.currentName();
    defer app_theme.select(previous);
    app_theme.select(.light);
    p.env.publishTheme();
    p.env.frames(2);
    const pane = try p.node("settings.keys.tabs");
    const card = pane.children.items[1];
    const light = card.getBackground();
    try std.testing.expect(ui.Color.eql(p.env.cx.tokens.tokens.color.zw_window_rest, light));
    const cap = try p.node("settings.key.new_tab");
    const badge = try p.node("settings.updates.badge");
    app_theme.select(.dark);
    p.env.publishTheme();
    p.env.frames(2);
    try std.testing.expect(pane == try p.node("settings.keys.tabs"));
    try std.testing.expect(cap == try p.node("settings.key.new_tab"));
    try std.testing.expect(badge == try p.node("settings.updates.badge"));
    try std.testing.expect(!ui.Color.eql(light, card.getBackground()));
    try std.testing.expect(ui.Color.eql(p.env.cx.tokens.tokens.color.zw_window_rest, card.getBackground()));
    // 相邻行之间一条 1pt `border` 发丝线，最后一行没有。
    const first = try p.node("settings.key.row.new_tab");
    try std.testing.expect(ui.Color.eql(p.env.cx.tokens.tokens.color.border, first.style.border.color));
    try std.testing.expectEqual(@as(f32, 0), divider(try p.node("settings.key.row.split_horizontal")));
}

test "settings panes updates: version card and preferences in the legacy order, host status projected in place, buttons only emit effects" {
    var p: Panes = undefined;
    try p.init("");
    defer p.deinit();
    var buffer: [512]u8 = undefined;
    // 字段：版本卡（徽标、版本行、检查更新），更新偏好（自动检查、更新通道、上次检查、发布来源）。
    try expectOrder(&p, "settings.updates.preferences", "settings.", &.{ "settings.updates.preferences", "settings.updates.preferences.header", "settings.updates.preferences.summary", "settings.row.auto_check", "settings.help.content.auto_check", "settings.field.auto_check", "settings.error.auto_check", "settings.updates.channel", "settings.updates.last_check", "settings.updates.source" });
    try std.testing.expectEqualStrings("待检查", try p.text("settings.updates.badge", &buffer));
    try std.testing.expectEqualStrings("— · 构建信息未知", try p.text("settings.updates.version_text", &buffer));
    try std.testing.expectEqualStrings("检查更新", try p.text("settings.updates.open", &buffer));
    try std.testing.expectEqualStrings("正式版", try p.text("settings.updates.channel", &buffer));
    try std.testing.expectEqualStrings("尚未检查", try p.text("settings.updates.last_check", &buffer));
    try std.testing.expect(contains(try p.text("settings.help.content.auto_check", &buffer), "24 小时限频"));
    try std.testing.expect(contains(try p.text("settings.updates.version", &buffer), "检查是否有可用的新版本"));
    // 检查更新与发布来源只发 Effect（宿主做实际的事；e2e 在 auto_check=false 的断网沙箱里不发网络请求）。
    try p.click("settings.updates.open");
    try std.testing.expect(p.hasEffect(.check_updates));
    try p.click("settings.updates.source");
    try std.testing.expect(p.hasEffect(.open_update_release));
    // 宿主状态变化：只重新投影，节点原样保留。
    var before = try snapshot(&p, "settings.updates");
    defer before.deinit(std.testing.allocator);
    p.status.update = .{ .state = "checking", .current_version = "0.3.0", .metadata = "main@abc1234 · 2026-11-12", .badge = "正在检查", .title = "正在检查新版本…", .last_check = "刚刚", .channel = "正式版" };
    p.vm.sync();
    p.env.frame();
    try std.testing.expectEqualStrings("正在检查", try p.text("settings.updates.badge", &buffer));
    try std.testing.expectEqualStrings("0.3.0 · main@abc1234 · 2026-11-12", try p.text("settings.updates.version_text", &buffer));
    try std.testing.expectEqualStrings("正在检查…", try p.text("settings.updates.open", &buffer));
    try std.testing.expect(isOff(try p.node("settings.updates.open")));
    try std.testing.expectEqualStrings("刚刚", try p.text("settings.updates.last_check", &buffer));
    try std.testing.expectEqual(m.UpdateTone.active, p.vm.updateTone());
    try expectSameNodes(&p, "settings.updates", before);
    p.status.update = .{ .state = "available", .badge = "有新版本", .title = "0.4.0 正式版可用", .available_version = "0.4.0" };
    p.vm.sync();
    p.env.frame();
    try std.testing.expectEqualStrings("查看更新", try p.text("settings.updates.open", &buffer));
    try std.testing.expect(!isOff(try p.node("settings.updates.open")));
    try std.testing.expect(p.vm.updateAvailable());
    p.status.update = .{ .state = "failed", .badge = "检查失败" };
    p.vm.sync();
    try std.testing.expectEqual(m.UpdateTone.warning, p.vm.updateTone());
    p.status.update = .{ .state = "idle", .badge = "无需更新", .current_version = "0.3.0" };
    p.vm.sync();
    try std.testing.expectEqual(m.UpdateTone.done, p.vm.updateTone());
    p.status.update = .{ .state = "draining", .badge = "正在收尾" };
    p.vm.sync();
    try std.testing.expectEqualStrings("查看收尾进度", p.vm.updateButton());
    // 自动检查更新：草稿 → 未保存，开关原地切换。
    try std.testing.expect(!p.vm.isDirty());
    const before_value = values.read(p.controller.model.value, "updates", "auto_check").?.boolean;
    try p.click("settings.field.auto_check");
    try std.testing.expectEqual(!before_value, values.read(p.controller.model.value, "updates", "auto_check").?.boolean);
    try std.testing.expect(p.vm.isDirty());
    try expectSameNodes(&p, "settings.updates", before);
}

test "settings panes updates: search keeps the matching pane" {
    var p: Panes = undefined;
    try p.init("通道");
    defer p.deinit();
    try std.testing.expect(shown(try p.node("settings.updates.preferences")));
    try std.testing.expect(!shown(try p.node("settings.updates.version")));
    try std.testing.expect(shown(try p.node("settings.updates.channel")));
    try std.testing.expect(shown(try p.node("settings.updates.source")));
    var q: Panes = undefined;
    try q.init("版本");
    defer q.deinit();
    try std.testing.expect(shown(try q.node("settings.updates.version")));
    try std.testing.expect(!shown(try q.node("settings.updates.preferences")));
}

fn divider(node: *ui.Node) f32 {
    const side = node.style.border.side_widths[2];
    return if (side < 0) node.style.border.width else side;
}
