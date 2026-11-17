//! OverlayHost：窗口里一切浮层的唯一入口（CONSISTENCY_AUDIT #1；用户拍板 1、4）。
//!
//! 规则只在这里定，各功能只声明自己是哪一种浮层，不再自己写 Esc、点外部、焦点进入与归还：
//!
//! | 种类 | 打开后焦点 | Tab | Esc | 点外部 | 关闭后焦点 |
//! |---|---|---|---|---|---|
//! | `panel` 同级面板（标题栏工具、状态卡片、会话菜单…） | 面板第一个控件 | 圈在面板里 | 只关最上面一层 | 关闭，不吞点击 | 回到打开时的焦点（点击打开 = 触发按钮；快捷键打开 = 原来的位置）；点外部关闭时留在被点的地方 |
//! | `menu` 菜单（只有原生 `W.Menu`，经 `shell/view/app_menu.zig` 挂载；menus 包删去了 Popover 列表菜单） | 菜单 / 第一项 | 在菜单项间移动，不离开菜单 | 同上 | 同上 | 同上 |
//! | `dialog` 确认框（原生 `W.Modal` / `W.ConfirmDialog`） | 约定的安全按钮（Modal 的 `initialFocus`，按 focusId；ConfirmDialog 默认“取消”），没有约定时第一个控件 | 圈在对话框里 | 取消 | 点遮罩 = 取消 | 回到打开时的焦点 |
//! | `card` 浮动卡片（非模态，`float_layer`） | 卡片里的第一个控件（卡片主人打开时自己放了焦点的，以主人放的为准，见 `CardFocus`） | 焦点在卡片里时圈在卡片里 | **只在焦点在卡片里时**关闭 | **不关闭**，焦点留在被点的地方 | 焦点仍在卡片里（或已无焦点）时回到打开时的焦点 |
//!
//! 机制全部用 zenit 原生浮层栈：`panel` / `menu` 是原生 Popover（`trap_focus`、`close_on_escape`、
//! `close_on_outside_click`，焦点归还见 zenit 上游 Popover `return_focus` 与“焦点已被点击移走就不抢回”）、
//! 原生 Menu（Tab 不离开菜单，上游）与原生 Modal；Esc 由浮层栈按层处理，只关最上面一层，不再经过
//! `nav_host` 的手写判断。浮动卡片不是浮层栈里的层（它们是窗口里的常驻窗格），由 `CardFocus` 按上表处理。
//!
//! 输入框：`install` 把窗口设为 `Cx.input_escape = .revert_to_focus_value`（zenit 上游）——所有原生
//! `Input` 按 Esc 回到聚焦时的值（改过才回，回了就用掉这次 Esc；没改过的 Esc 照常关浮层 / 窗口）。
const std = @import("std");
const ui = @import("ui");

pub const Kind = enum { panel, menu, dialog, card };

pub const Policy = struct {
    /// Esc 关闭（浮层栈只关最上面一层；卡片要求焦点在卡片里）。
    escape: bool,
    /// 点外部关闭。
    outside: bool,
    /// 打开后焦点进入、Tab 圈在里面、关闭后焦点归还。
    trap_focus: bool,
};

pub fn policy(kind: Kind) Policy {
    return switch (kind) {
        .panel, .menu, .dialog => .{ .escape = true, .outside = true, .trap_focus = true },
        .card => .{ .escape = true, .outside = false, .trap_focus = true },
    };
}

/// 同级面板 / 菜单的原生 Popover：几何与内容由调用方给，行为由本文件的规则给（调用方写了也会被覆盖）。
pub fn Popover(comptime kind: Kind, props: anytype) ui.widgets.popover.PopoverBuilder {
    comptime std.debug.assert(kind == .panel or kind == .menu);
    var builder = ui.widgets.Popover(props);
    const rule = policy(kind);
    builder.props.close_on_escape = rule.escape;
    builder.props.close_on_outside_click = rule.outside;
    // 不吞点击：一次点击就能切到另一个工具，点到的控件拿到焦点。
    builder.props.consume_outside_click = false;
    builder.props.trap_focus = rule.trap_focus;
    return builder;
}

/// `.yix` 里的原生 `W.Popover` 读这几个常量（`closeOnEscape={O.panel.escape}` …），与 `Popover` 同一套规则。
pub const panel = policy(.panel);
pub const menu = policy(.menu);
pub const consume_outside_click = false;

/// 窗口级规则：一个窗口挂一次（主窗口、设置窗口、插件窗口）。
pub fn install(cx: *ui.Cx) void {
    cx.input_escape = .revert_to_focus_value;
}

// ── 同级面板（标题栏工具、页签身份卡片…）的点击语义 ─────────────────────────────────────────────

/// 一组同级面板：同一时间只开一个（互斥），再点一次触发按钮关闭。焦点进入 / 圈住 / 归还与 Esc、点外部
/// 都是面板自己的原生 Popover（`Popover(.panel, …)`）的事，这里不管焦点。
///
/// 两件事各有一个来源，都不靠逐帧检查：
///
/// - **点击语义**（`Sibling.click`）：`add` 时把触发按钮在挂载处声明的点击动作收为“打开动作”，换成本组的
///   点击（再点关闭、打开前把焦点放到触发按钮上）。只在 `add` 做这一次；触发按钮的主人之后不得再改写
///   `on_click`——按钮在不同状态下做不同的事，由它自己的动作读状态分派（见 `ssh_status_host.identityClicked`）。
/// - **互斥**（`Sibling.openChanged`）：每个面板的开合信号上挂一个 effect。无论由谁打开（触发按钮、快捷键、
///   菜单、面板自己），信号变为 true 的那一刻关掉同组里开着的另一个。
pub const Siblings = struct {
    open_entry: ?*Sibling = null,

    /// `trigger` 的点击动作必须已经声明（它就是“打开”）；`open` 是面板的开合信号，`close` 关闭它。
    pub fn add(self: *Siblings, cx: *ui.Cx, scope: *ui.Scope, trigger: *ui.Node, open: *ui.Signal(bool), close: ui.HandlerRef) !void {
        const action = trigger.behavior.events.on_click orelse return;
        const entry = try scope.createState(Sibling, .{ .group = self, .cx = cx, .trigger = trigger, .open = open, .action = action, .close = close });
        trigger.behavior.events.on_click = cx.on(Sibling, entry, Sibling.click);
        try scope.createEffect(.{ .entry = entry, .open = open }, Sibling.openChanged);
        try scope.onCleanup(Sibling, entry, Sibling.cleanup);
    }
};

pub const Sibling = struct {
    group: *Siblings,
    cx: *ui.Cx,
    trigger: *ui.Node,
    open: *ui.Signal(bool),
    action: ui.HandlerRef,
    close: ui.HandlerRef,

    fn click(self: *Sibling) void {
        // The clicked trigger holds focus while its panel opens: the panel returns focus to it on
        // close (a trigger folded into “⋯” is inert: the ⋯ menu's own focus stays).
        if (!self.open.peek() and self.trigger.behavior.interaction.focusable and !inertTrigger(self.trigger)) self.cx.setFocus(self.trigger);
        if (self.open.peek()) self.close.invoke() else self.action.invoke();
        self.cx.requestRedraw();
    }
    fn inertTrigger(node: *ui.Node) bool {
        var current: ?*ui.Node = node;
        while (current) |n| : (current = n.parent) if (n.behavior.interaction.inert) return true;
        return false;
    }
    /// The panel's open signal changed (whoever changed it): keep the group exclusive.
    fn openChanged(ctx: anytype) void {
        const self: *Sibling = ctx.entry;
        if (ctx.open.get()) {
            if (self.group.open_entry) |other| if (other != self and other.open.peek()) other.close.invoke();
            self.group.open_entry = self;
        } else if (self.group.open_entry == self) {
            self.group.open_entry = null;
        }
    }
    fn cleanup(self: *Sibling) void {
        if (self.group.open_entry == self) self.group.open_entry = null;
    }
};

// ── 浮动卡片（非模态） ─────────────────────────────────────────────────────────────────────────

/// 一张浮动卡片的焦点协议（文件头表格的 `card` 行）。卡片不是浮层栈里的层（它是窗口里的常驻窗格，
/// 点外部不关、不挡住外面），所以不能用原生 Popover / Modal 的模态焦点，规则写在这里，一处。
///
/// 协议是状态与事件，不数帧：
///
/// 1. **打开** `opened(trigger)`：记下归还目标（当时的焦点；没有焦点时是 `trigger`），进入“待进入”状态。
/// 2. **进入**（`sync`，卡片显示出来之后才判断）——只有一个裁决者，按顺序：
///    - 焦点已经在卡片里（卡片主人打开时同步放的，或用户放的）→ 完成。主人的内容在打开那一步就已在窗口里
///      （按需挂载的表面由 `surface_migration` 同步放回），所以没有“主人的请求还在路上”这种中间状态；
///    - 否则放到卡片里第一个键盘可达的控件 → 完成；还没有这样的控件（内容尚未挂上）→ 继续待进入；
///    - 卡片显示之后焦点转到了卡片外（用户点了别处）→ 放弃进入，焦点留在那里。
/// 3. **圈住**：焦点在卡片里时 Tab 圈在卡片里（焦点作用域入栈）；焦点到了外面就出栈（非模态）。卡片里打开的
///    浮层（菜单、确认框）压在我们上面时保留作用域，关闭后还能回到卡片。
/// 4. **Esc** `escapeCloses`：只有焦点在卡片里时关闭（卡片根冒泡阶段，里面的输入框、浮层先拿到）。
/// 5. **关闭** `closed()`：焦点还在卡片里（或已无焦点）时回到归还目标；已经被点到别处就留在那里；输入法
///    组字中不动焦点。归还目标还没显示（卡片收回去的入口按钮）时进入“待归还”：它显示出来的那一帧归还；
///    期间用户把焦点放到别处、目标已销毁、或卡片再次打开，都取消归还。
///
/// `float_layer.Card` 持有它：显式打开 / 关闭时调用 `opened` / `closed`，每帧布局后 `sync`，卡片根的冒泡
/// 阶段按键交给 `escapeCloses`。
pub const CardFocus = struct {
    cx: *ui.Cx,
    root: *ui.Node,
    /// 打开时的焦点（点击打开 = 触发按钮，快捷键打开 = 原来的位置）。
    return_to: ?ui.hit.NodeHandle = null,
    /// 待进入（协议第 2 步）；null = 没有进行中的进入。
    entry: ?Entry = null,
    scope_pushed: bool = false,
    /// Our place on the focus manager's scope stack while pushed.
    scope_index: usize = 0,
    /// 待归还（协议第 5 步）的目标：还没显示出来的入口按钮。
    pending_return: ?ui.hit.NodeHandle = null,

    const Entry = struct {
        /// 卡片显示出来那一刻的焦点转移序号；之后序号变了而焦点不在卡片里 = 用户把焦点放到了别处。
        shown_epoch: ?u64 = null,
    };

    fn track(self: *CardFocus, node: *ui.Node) ?ui.hit.NodeHandle {
        const generation = self.cx.node_registry.trackGeneration(node) catch return null;
        return .{ .id = node.id, .generation = generation };
    }

    pub fn init(cx: *ui.Cx, root: *ui.Node) CardFocus {
        // 焦点在卡片里时 Tab 圈在卡片里：圈住的作用域只在焦点进入时挂上并入栈（见 `push`），焦点在外面时
        // 卡片里的控件照常可达（卡片自己的焦点请求、外面 Tab 进来）。
        return .{ .cx = cx, .root = root };
    }

    pub fn contains(self: *const CardFocus, node: ?*ui.Node) bool {
        const n = node orelse return false;
        return n == self.root or n.isDescendantOf(self.root);
    }

    /// 显式打开（入口按钮、快捷键、菜单）。`trigger`：入口按钮；打开时没有焦点（入口按钮点击不取焦点）就回到它。
    pub fn opened(self: *CardFocus, trigger: ?*ui.Node) void {
        self.pending_return = null;
        const focused = self.cx.focus_manager.getFocused();
        if (!self.contains(focused)) {
            const target = focused orelse trigger;
            self.return_to = if (target) |node| self.track(node) else null;
        }
        self.entry = .{};
        self.cx.requestRedraw();
    }

    /// 显式关闭（Esc、卡片的 ×、入口再点一次）。焦点还在卡片里（或已无焦点）时回到打开时的焦点；
    /// 焦点已经被点到别处就留在那里。
    pub fn closed(self: *CardFocus) void {
        self.entry = null;
        const focused = self.cx.focus_manager.getFocused();
        const inside = focused == null or self.contains(focused);
        self.release();
        // Never move focus away from a composition in progress.
        if (focused) |node| if (node.behavior.interaction.text_input_client) |client| if (client.is_composing) |query| if (query(client.context)) {
            self.return_to = null;
            return;
        };
        const target = self.return_to;
        self.return_to = null;
        if (!inside) return;
        if (focused != null) self.cx.focus_manager.abandonFocus(focused.?);
        if (target) |handle| {
            // The trigger may still be hidden (a launcher the card folds back into): it gets focus on
            // the frame it shows (`sync`). One frame is asked for here; nothing keeps frames coming.
            self.pending_return = handle;
            if (!self.tryReturn()) self.cx.requestRedraw();
        }
    }

    /// Focus the pending return target if it shows; false while still waiting.
    fn tryReturn(self: *CardFocus) bool {
        const handle = self.pending_return orelse return true;
        const fm = &self.cx.focus_manager;
        // The user focused something else meanwhile: leave it.
        if (fm.getFocused()) |focused| if (!self.contains(focused)) {
            self.pending_return = null;
            return true;
        };
        const node = self.cx.node_registry.resolve(handle, null) orelse {
            self.pending_return = null;
            return true;
        };
        if (!node.isDisplayedInTree()) return false;
        // A trigger given as its wrapper: its first focusable control.
        const target = if (node.behavior.interaction.focusable) node else firstFocusable(self.cx, node) orelse return false;
        self.cx.setFocus(target);
        self.pending_return = null;
        return true;
    }

    /// 每帧布局后：待归还、待进入的判断；Tab 作用域随焦点进出卡片入栈 / 出栈（非模态：点到外面就不再圈住）。
    pub fn sync(self: *CardFocus, shown: bool) void {
        _ = self.tryReturn();
        if (!shown) {
            self.entry = null;
            self.release();
            return;
        }
        const fm = &self.cx.focus_manager;
        if (self.entry != null and self.root.isDisplayedInTree()) self.enter();
        if (self.contains(fm.getFocused())) {
            self.push();
        } else if (self.scope_pushed and fm.scope_count > self.scope_index + 1) {
            // A layer opened from inside the card (its menu, a confirmation) holds focus above our
            // scope: keep ours, or its way back into the card would be cut.
        } else self.release();
    }

    /// 协议第 2 步：卡片已显示时裁决一次“待进入”。
    fn enter(self: *CardFocus) void {
        const fm = &self.cx.focus_manager;
        const entry = &self.entry.?;
        if (self.contains(fm.getFocused())) {
            // The owner (the AI composer, the history search) or the user already put focus in.
            self.entry = null;
            return;
        }
        if (entry.shown_epoch) |epoch| {
            if (epoch != fm.transition_epoch) {
                // Focus moved after the card showed and is not in the card: the user's choice stands.
                self.entry = null;
                return;
            }
        } else entry.shown_epoch = fm.transition_epoch;
        // The trap scope makes the card's controls reachable; push it before picking.
        self.push();
        for (fm.focus_order.items) |candidate| {
            if (candidate.isDescendantOf(self.root) and candidate.isDisplayedInTree() and fm.keyboardReachable(candidate)) {
                fm.setFocus(candidate);
                self.entry = null;
                return;
            }
        }
        // No control yet (content still mounting): stay pending; the frame that mounts one enters.
    }

    fn push(self: *CardFocus) void {
        if (self.scope_pushed) return;
        const fm = &self.cx.focus_manager;
        self.root.setFocusScope(.{ .trap = true, .auto_focus = false });
        const before = fm.scope_count;
        fm.pushScope(self.root);
        self.scope_pushed = fm.scope_count != before;
        self.scope_index = before;
        if (!self.scope_pushed) self.root.setFocusScope(null);
    }

    fn firstFocusable(cx: *ui.Cx, root: *ui.Node) ?*ui.Node {
        for (cx.focus_manager.focus_order.items) |candidate| {
            if (candidate.isDescendantOf(root) and candidate.isDisplayedInTree()) return candidate;
        }
        return null;
    }

    fn release(self: *CardFocus) void {
        if (!self.scope_pushed) return;
        self.scope_pushed = false;
        self.cx.focus_manager.removeScope(self.root.id, false);
        self.root.setFocusScope(null);
    }

    /// 卡片根冒泡阶段的 Esc（卡片里的输入框、浮层先拿到）：焦点在卡片里才走到这里 → 关闭。
    pub fn escapeCloses(self: *const CardFocus, key: ui.events.KeyCode) bool {
        return key == .escape and self.contains(self.cx.focus_manager.getFocused());
    }
};

// ── 不属于浮层栈的窗口级层（预览之类）：Esc 的最后一站 ─────────────────────────────────────────

/// 窗口里不是原生浮层、也不是卡片、但要被 Esc 收起的层（例如设置里“材质预览”盖在主窗口上）。
/// 主窗口的按键捕获只调用 `escape` 一次；后注册 / 后打开的层先收。
pub const OverlayHost = struct {
    allocator: std.mem.Allocator,
    layers: std.ArrayList(Layer) = .empty,
    siblings: Siblings = .{},

    pub const Layer = struct {
        ctx: *anyopaque,
        is_open: *const fn (ctx: *anyopaque) bool,
        close: *const fn (ctx: *anyopaque) void,
    };

    pub fn init(allocator: std.mem.Allocator) OverlayHost {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *OverlayHost) void {
        self.layers.deinit(self.allocator);
    }

    pub fn addLayer(self: *OverlayHost, layer: Layer) !void {
        try self.layers.append(self.allocator, layer);
    }

    pub fn removeLayer(self: *OverlayHost, ctx: *anyopaque) void {
        var index = self.layers.items.len;
        while (index > 0) {
            index -= 1;
            if (self.layers.items[index].ctx == ctx) _ = self.layers.orderedRemove(index);
        }
    }

    /// Esc 到了窗口这一层（原生浮层栈、输入框、卡片都没接）：收起最上面一个打开的窗口级层。IME 组字中不接。
    pub fn escape(self: *OverlayHost, ime_composing: bool) bool {
        if (ime_composing) return false;
        var index = self.layers.items.len;
        while (index > 0) {
            index -= 1;
            const layer = self.layers.items[index];
            if (layer.is_open(layer.ctx)) {
                layer.close(layer.ctx);
                return true;
            }
        }
        return false;
    }
};

const Probe = struct {
    open: bool = true,
    closes: usize = 0,
    fn isOpen(raw: *anyopaque) bool {
        const self: *Probe = @ptrCast(@alignCast(raw));
        return self.open;
    }
    fn close(raw: *anyopaque) void {
        const self: *Probe = @ptrCast(@alignCast(raw));
        self.open = false;
        self.closes += 1;
    }
};

test "OverlayHost: Escape closes only the top open window layer, IME first" {
    var host = OverlayHost.init(std.testing.allocator);
    defer host.deinit();
    var lower = Probe{};
    var upper = Probe{};
    try host.addLayer(.{ .ctx = &lower, .is_open = Probe.isOpen, .close = Probe.close });
    try host.addLayer(.{ .ctx = &upper, .is_open = Probe.isOpen, .close = Probe.close });
    try std.testing.expect(!host.escape(true));
    try std.testing.expect(host.escape(false));
    try std.testing.expect(!upper.open and lower.open);
    try std.testing.expect(host.escape(false));
    try std.testing.expect(!lower.open);
    try std.testing.expect(!host.escape(false));
    host.removeLayer(&upper);
    try std.testing.expectEqual(@as(usize, 1), host.layers.items.len);
}

test "OverlayHost policy: panels and menus close on Escape and outside, cards only on Escape" {
    try std.testing.expect(policy(.panel).escape and policy(.panel).outside and policy(.panel).trap_focus);
    try std.testing.expect(policy(.menu).outside and policy(.menu).trap_focus);
    try std.testing.expect(policy(.card).escape and !policy(.card).outside);
    const built = Popover(.panel, .{ .trigger = .manual, .close_on_escape = false, .consume_outside_click = true });
    try std.testing.expect(built.props.close_on_escape and built.props.close_on_outside_click and !built.props.consume_outside_click);
    try std.testing.expectEqual(@as(?bool, true), built.props.trap_focus);
}
