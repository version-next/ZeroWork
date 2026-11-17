//! 标题栏工具组（design-r3 稿 5）的挂载与信号。视图是 `title_tools.yix`（原生 Button / Tooltip / Divider / Menu / Badge）；
//! 规则在 `model/title_tools.zig`（纯函数 + 单测）。宿主每帧写入事实（折叠级别、按钮是否存在、进行中的传输、
//! 状态文案、可用性），同值不触发更新；各宿主经 `node(tool)` 拿到原生按钮节点，接自己的点击与弹层锚点。
const std = @import("std");
const ui = @import("ui");
const W = ui.widgets;
const m = @import("../model/title_tools.zig");
const template = @import("_title_tools.yix.zig");
const app_menu = @import("app_menu.zig");
const shortcut_router = @import("../model/shortcut_router.zig");

pub const ids = template.ids;
pub const Tool = m.Tool;
pub const Level = m.Level;

const tip_capacity = 160;

pub const ViewModel = struct {
    cx: *ui.Cx,
    root: *ui.Node = undefined,
    level: *ui.Signal(m.Level),
    facts: *ui.Signal(m.Facts),
    extra: *ui.Signal(bool),
    /// Per-tool glyph (lucide name); only the transfer button changes it by phase.
    icons: [m.count]*ui.Signal([]const u8),
    dot: *ui.Signal(bool),
    tips: [m.count]*ui.Signal([]const u8),
    disabled_signals: [m.count]*ui.Signal(bool),
    items: *ui.Signal([]const W.MenuItem),
    nodes: [m.count]?*ui.Node = @splat(null),
    more: ?*ui.Node = null,
    extra_slot: ?*ui.Node = null,
    /// Double-buffered texts: the signal keeps the previous slice alive until it is replaced.
    tip_buffers: [m.count][2][tip_capacity]u8 = undefined,
    tip_current: [m.count]u1 = @splat(0),
    /// “⋯”的行：经菜单唯一的投影（`app_menu.build`）生成，两块交替。
    item_built: [2]app_menu.Built = .{ .{}, .{} },
    item_current: u1 = 0,
    /// 菜单行右侧的快捷键文字从这个路由取（宿主写入本窗口的 `[keys]`）。
    shortcuts: ?shortcut_router.Router = null,
    /// State texts are copied: callers may pass a node's text that changes later.
    state_buffers: [m.count][tip_capacity]u8 = undefined,
    state_lens: [m.count]usize = @splat(0),
    keys: [m.count]?[]const u8 = @splat(null),
    reasons: [m.count][]const u8 = @splat(""),

    // ---- 模板读的选择器 ----

    pub fn present(self: *const ViewModel, tool: m.Tool) bool {
        return self.facts.get().present[@intFromEnum(tool)];
    }
    pub fn folded(self: *const ViewModel, tool: m.Tool) bool {
        return m.inMenu(tool, self.level.get(), self.facts.get());
    }
    pub fn icon(self: *const ViewModel, tool: m.Tool) ?ui.SvgAsset {
        return ui.icons.get(self.icons[@intFromEnum(tool)].get());
    }
    pub fn tip(self: *const ViewModel, tool: m.Tool) []const u8 {
        return self.tips[@intFromEnum(tool)].get();
    }
    pub fn disabled(self: *const ViewModel, tool: m.Tool) bool {
        return self.disabled_signals[@intFromEnum(tool)].get();
    }
    pub fn dividerShown(self: *const ViewModel, index: u1) bool {
        return m.dividerShown(index, self.level.get(), self.facts.get());
    }
    pub fn moreShown(self: *const ViewModel) bool {
        return self.level.get() != .expanded;
    }
    pub fn extraShown(self: *const ViewModel) bool {
        return self.extra.get() and self.level.get() == .expanded;
    }
    pub fn dotShown(self: *const ViewModel) bool {
        return self.dot.get() and self.level.get() == .collapsed;
    }
    pub fn menuItems(self: *const ViewModel) []const W.MenuItem {
        return self.items.get();
    }
    /// “⋯”菜单选中：触发这颗（收起的）原生按钮自己的点击，宿主的弹层锚在它上面，也就是“⋯”处。
    pub fn select(self: *ViewModel, id: []const u8) void {
        const tool = m.fromMenuId(id) orelse return;
        const button = self.nodes[@intFromEnum(tool)] orelse return;
        if (self.disabled_signals[@intFromEnum(tool)].peek()) return;
        if (button.behavior.events.on_click) |handler| handler.invoke();
        self.cx.requestRedraw();
    }

    // ---- 宿主接口 ----

    pub fn mount(cx: *ui.Cx, scope: *ui.Scope) !*ViewModel {
        const self = try scope.createState(ViewModel, .{
            .cx = cx,
            .level = try scope.createSignal(m.Level, .expanded),
            .facts = try scope.createSignal(m.Facts, .{}),
            .extra = try scope.createSignal(bool, false),
            .dot = try scope.createSignal(bool, false),
            .tips = undefined,
            .icons = undefined,
            .disabled_signals = undefined,
            .items = try scope.createSignal([]const W.MenuItem, &.{}),
        });
        for (&self.tips, &self.disabled_signals, &self.icons, 0..) |*text, *off, *glyph, index| {
            const tool: m.Tool = @enumFromInt(index);
            glyph.* = try scope.createSignal([]const u8, m.iconName(tool));
            text.* = try scope.createSignal([]const u8, m.label(tool));
            off.* = try scope.createSignal(bool, false);
        }
        for (0..m.count) |index| self.refreshTip(@enumFromInt(index));
        self.root = try ui.view.render(scope, cx, template.TitleTools(.{ .vm = self }));
        self.refreshItems();
        return self;
    }

    /// 原生按钮节点（宿主接点击、弹层锚点、焦点归还）。
    pub fn node(self: *const ViewModel, tool: m.Tool) *ui.Node {
        return self.nodes[@intFromEnum(tool)].?;
    }
    pub fn moreButton(self: *const ViewModel) ?*ui.Node {
        return self.more;
    }
    pub fn extraSlot(self: *const ViewModel) ?*ui.Node {
        return self.extra_slot;
    }
    pub fn currentLevel(self: *const ViewModel) m.Level {
        return self.level.peek();
    }
    pub fn currentFacts(self: *const ViewModel) m.Facts {
        return self.facts.peek();
    }
    /// 可用性信号（命令历史的宿主直接写它）。
    pub fn disabledSignal(self: *ViewModel, tool: m.Tool) *ui.Signal(bool) {
        return self.disabled_signals[@intFromEnum(tool)];
    }

    /// workspace_chrome seam: settle the fold level for the width the tabs
    /// leave (natural tab widths + new-tab slot), report the tools' width.
    pub fn fit(raw: *anyopaque, available: f32) struct { width: f32, changed: bool } {
        const self: *ViewModel = @ptrCast(@alignCast(raw));
        const facts = self.facts.peek();
        const level = m.choose(available, self.level.peek(), facts);
        const changed = self.setLevel(level);
        return .{ .width = m.width(level, facts), .changed = changed };
    }

    pub fn setLevel(self: *ViewModel, level: m.Level) bool {
        if (self.level.peek() == level) return false;
        self.level.set(level);
        self.refreshItems();
        return true;
    }
    pub fn setFacts(self: *ViewModel, facts: m.Facts) bool {
        if (std.meta.eql(self.facts.peek(), facts)) return false;
        self.facts.set(facts);
        self.refreshItems();
        return true;
    }
    pub fn setExtra(self: *ViewModel, shown: bool) void {
        if (self.extra.peek() != shown) self.extra.set(shown);
    }
    /// Glyph by lucide name (must be a static string).
    pub fn setIcon(self: *ViewModel, tool: m.Tool, name: []const u8) void {
        const signal = self.icons[@intFromEnum(tool)];
        if (!std.mem.eql(u8, signal.peek(), name)) signal.set(name);
    }
    pub fn setUnread(self: *ViewModel, unread: bool) void {
        if (self.dot.peek() != unread) self.dot.set(unread);
    }
    /// 状态文案（例如“通信链路 · 已连接”“传输进行中”）与可配置的快捷键（快捷键须是静态字符串）。
    pub fn setState(self: *ViewModel, tool: m.Tool, state: []const u8, key: ?[]const u8) void {
        const i = @intFromEnum(tool);
        var n = @min(state.len, tip_capacity);
        while (n > 0 and !std.unicode.utf8ValidateSlice(state[0..n])) n -= 1;
        const same_key = if (self.keys[i]) |old| (if (key) |new| std.mem.eql(u8, old, new) else false) else key == null;
        if (std.mem.eql(u8, self.state_buffers[i][0..self.state_lens[i]], state[0..n]) and same_key) return;
        @memcpy(self.state_buffers[i][0..n], state[0..n]);
        self.state_lens[i] = n;
        self.keys[i] = key;
        self.refreshTip(tool);
        if (!same_key) self.refreshItems();
    }
    /// 不可用与原因（原因写进 Tooltip 与菜单项）。
    pub fn setAvailable(self: *ViewModel, tool: m.Tool, available: bool, reason: []const u8) void {
        const i = @intFromEnum(tool);
        const off = !available;
        const why: []const u8 = if (available) "" else reason;
        if (self.disabled_signals[i].peek() == off and std.mem.eql(u8, self.reasons[i], why)) return;
        if (self.disabled_signals[i].peek() != off) self.disabled_signals[i].set(off);
        self.reasons[i] = why;
        self.refreshTip(tool);
        self.refreshItems();
    }

    fn refreshTip(self: *ViewModel, tool: m.Tool) void {
        const i = @intFromEnum(tool);
        const next: u1 = self.tip_current[i] ^ 1;
        const state = if (self.reasons[i].len != 0) self.reasons[i] else self.state_buffers[i][0..self.state_lens[i]];
        const text = m.tooltip(&self.tip_buffers[i][next], tool, state, self.keys[i]);
        if (std.mem.eql(u8, self.tips[i].peek(), text)) return;
        self.tip_current[i] = next;
        self.tips[i].set(text);
    }

    fn refreshItems(self: *ViewModel) void {
        const next: u1 = self.item_current ^ 1;
        var n: usize = 0;
        const level = self.level.peek();
        const facts = self.facts.peek();
        var entries: [m.count]app_menu.Entry = undefined;
        for (m.order) |tool| {
            if (!m.inMenu(tool, level, facts)) continue;
            const i = @intFromEnum(tool);
            const off = self.disabled_signals[i].peek();
            // The full reason is in the Tooltip; the menu row says why in short.
            entries[n] = .{ .id = m.menuId(tool), .label = m.label(tool), .test_id = m.menuId(tool), .disabled_reason = if (off) "本页签不可用" else null, .command = if (self.keys[i] != null) m.command(tool) else null, .icon = self.icons[i].peek() };
            n += 1;
        }
        const defaults = struct {
            const map: shortcut_router.Map = .{};
        };
        const items = app_menu.build(&self.item_built[next], entries[0..n], self.shortcuts orelse .{ .keys = &defaults.map });
        const old = self.items.peek();
        if (old.len == items.len) {
            var same = true;
            for (old, items) |a, b| if (!std.mem.eql(u8, a.id, b.id) or !std.mem.eql(u8, a.label, b.label) or a.disabled != b.disabled or !std.mem.eql(u8, a.shortcut orelse "", b.shortcut orelse "")) {
                same = false;
            };
            if (same) return;
        }
        self.item_current = next;
        self.items.set(items);
    }
};

test "title tools view: native buttons, tooltips, fold levels and the ⋯ menu" {
    const a = std.testing.allocator;
    const cx = try ui.Cx.init(a, std.testing.io);
    defer cx.deinit();
    cx.setViewport(1200, 200);
    const scope = try ui.Scope.init(a, null, cx.owner);
    defer scope.dispose();
    cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .direction = .row, .align_items = .start }, .{});
    const vm = try ViewModel.mount(cx, scope);
    try cx.root.?.appendChild(a, vm.root);
    cx.layout();
    for (m.order) |tool| try std.testing.expect(vm.nodes[@intFromEnum(tool)] != null);
    // The host writes each tool's shortcut text from the router.
    vm.setState(.command_history, "", "⇧⌘B");
    vm.setState(.settings, "", "⌘,");
    try std.testing.expectEqualStrings("命令历史 · ⇧⌘B", vm.tip(.command_history));
    try std.testing.expectEqualStrings("设置 · ⌘,", vm.tip(.settings));
    // Each Tooltip's hint panel has its own id `<button id>.tooltip` (e2e reads the text by id, not from the
    // whole window tree): hovering 设置 shows the panel `toolbar.settings.tooltip`.
    for (m.order) |tool| {
        var buf: [96]u8 = undefined;
        const want = try std.fmt.bufPrint(&buf, "{s}.tooltip", .{m.buttonId(tool)});
        try std.testing.expectEqualStrings(want, m.tooltipId(tool));
    }
    {
        const kit = @import("../../../shared/testing/ui_kit.zig");
        const r = vm.node(.settings).globalRect();
        try cx.setTestFrameStep(16);
        cx.handleMouseMove(r.x + r.w / 2, r.y + r.h / 2);
        for (0..60) |_| {
            cx.advanceFrameClock();
            cx.layout();
            _ = cx.render();
        }
        const panel = kit.findByTestId(cx.root.?, m.tooltipId(.settings)) orelse return error.TooltipPanelMissing;
        try std.testing.expect(panel.getOpacity() > 0.9);
        cx.handleMouseMove(1, 199);
    }
    try std.testing.expectEqual(@as(usize, 0), vm.menuItems().len);
    try std.testing.expect(!vm.moreShown());
    // 7 visible buttons × 32 + in-group gaps + dividers (broadcast is absent outside session groups).
    try std.testing.expectApproxEqAbs(m.width(.expanded, .{}), vm.root.globalRect().w, 0.5);
    vm.setState(.chain, "通信链路 · 已连接", null);
    try std.testing.expectEqualStrings("通信链路 · 已连接", vm.tip(.chain));
    vm.setAvailable(.forward, false, "当前页签不是 SSH 会话");
    try std.testing.expectEqualStrings("端口转发 · 当前页签不是 SSH 会话", vm.tip(.forward));
    try std.testing.expect(vm.disabled(.forward));
    _ = vm.setLevel(.compact);
    cx.layout();
    try std.testing.expect(vm.moreShown());
    try std.testing.expect(vm.folded(.chain) and !vm.folded(.settings));
    const items = vm.menuItems();
    try std.testing.expectEqual(@as(usize, 5), items.len);
    for (items) |item| try std.testing.expect(!std.mem.eql(u8, item.id, "toolbar.more.theme"));
    try std.testing.expectEqualStrings("toolbar.more.chain", items[0].id);
    try std.testing.expectEqualStrings("端口转发", items[1].label);
    try std.testing.expect(items[1].disabled);
    try std.testing.expectEqualStrings("本页签不可用", items[1].disabled_reason.?);
    try std.testing.expectEqualStrings("⇧⌘B", items[3].shortcut.?);
    try std.testing.expectApproxEqAbs(m.width(.compact, .{}), vm.root.globalRect().w, 0.5);
    // Selecting a folded tool runs that native button's own click.
    const Counter = struct {
        hits: u32 = 0,
        fn hit(self: *@This()) void {
            self.hits += 1;
        }
    };
    var counter: Counter = .{};
    vm.node(.history).behavior.events.on_click = cx.on(Counter, &counter, Counter.hit);
    vm.select("toolbar.more.history");
    vm.select("toolbar.more.forward");
    try std.testing.expectEqual(@as(u32, 1), counter.hits);
    // W-4: a folded button stays mounted (its popover anchors there) but leaves the Tab order.
    const fm = &cx.focus_manager;
    try fm.collectFocusableNodes(cx.root.?);
    try std.testing.expect(!fm.keyboardReachable(vm.node(.chain)));
    try std.testing.expect(fm.keyboardReachable(vm.node(.settings)));
    // Shift+Tab from the first unfolded button skips the folded ones (history, command history …).
    cx.setFocus(vm.node(.notifications));
    fm.focusPrev();
    for ([_]m.Tool{ .chain, .forward, .transfers, .command_history, .history }) |tool| try std.testing.expect(fm.getFocused() != vm.node(tool));
    _ = vm.setLevel(.collapsed);
    vm.setUnread(true);
    try std.testing.expect(vm.dotShown());
}
