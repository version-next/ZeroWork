//! 窗格头部的视图模型与挂载（视图是 `pane_header.yix`；W-5 收回，panel-heads）。workspace 按会话 / 卡片事实填好
//! `Spec`，`mount` 建一份 Vm 并渲染模板；分屏每次呈现时重建（头部的事实——名字、状态、置顶、广播——变化即重建）。
//!
//! 手写部分两个，都是 YIX_REFERENCE 推荐的“手写 Zig 组件当标签用”（与页签条的 `TabCell` 同一写法）：
//! - `PaneDrag`：把手与标题外层的盒子，承载 zenit 拖动绑定（绑定占用节点的事件槽，要行自己的 scope，随头部卸载
//!   释放）——YIX_EXCEPTIONS W-5 的最小例外；
//! - `PaneMore`：“更多”菜单经菜单唯一入口 `AppMenu.mountTrigger` 挂载（排列规则、快捷键文字、测试路由
//!   `/zerowork/menus` 都在那里），触发按钮在模板里放进它的槽——YIX_EXCEPTIONS W-6（随 mountTrigger 一起收回）。
const std = @import("std");
const ui = @import("ui");
const template = @import("_pane_header.yix.zig");
const shell = @import("../../shell/mod.zig");
const app_menu = shell.app_menu;
const shortcut_router = shell.shortcut_router;

pub const Ids = struct {
    header: []const u8,
    type_icon: ?[]const u8 = null,
    title: []const u8,
    status_dot: ?[]const u8 = null,
    status: ?[]const u8 = null,
    grip: []const u8 = "",
    float: []const u8,
    float_tooltip: []const u8,
    more: []const u8,
    menu: []const u8,
};

/// 广播 / 置顶这类开关按钮：开启时原生 `secondary`，关闭时 `ghost`。
pub const Toggle = struct {
    on: bool,
    disabled: bool = false,
    label: []const u8,
    tooltip: []const u8,
    test_id: []const u8,
    on_click: ui.Handler(void),
};

pub const Drag = struct {
    context: *anyopaque,
    handler: *const fn (ui.interaction.drag.Event, *anyopaque) void,
};

pub const Spec = struct {
    test_ids: Ids,
    icon: ui.SvgAsset,
    accent_icon: bool = false,
    focused: bool = false,
    title: []const u8,
    /// 连接状态点的颜色：null = 不显示（卡片）。颜色与页签圆点同源——workspace 按会话的连接阶段经
    /// `connection_presenter` → `status_tone.dot` 取（连接中琥珀、已连接绿、失败红、已结束灰），这里不再自己映射。
    dot: ?ui.Color = null,
    /// 会话窗格有“路径 · 列 × 行”，卡片没有。
    has_meta: bool = false,
    meta: []const u8 = "",
    drag: ?Drag = null,
    broadcast: ?Toggle = null,
    pin: ?Toggle = null,
    float_refusal: ?[]const u8 = null,
    float_click: ui.Handler(void),
    /// “更多”的菜单声明（`app_menu.Entry`，id 唯一）与同序的动作。
    menu: []const app_menu.Entry,
    menu_handlers: []const ui.Handler(void),
    router: shortcut_router.Router,
    more_label: []const u8,
    on_focus: ?ui.Handler(void) = null,
};

pub const max_menu = 12;

pub const Vm = struct {
    ids: Ids,
    icon: ui.SvgAsset,
    accent_icon: bool,
    /// 聚焦窗格（标题加粗、类型图标 accent）：分屏切换焦点时由 workspace 写，不重建头部。
    focused: *ui.Signal(bool),
    /// 连接状态点的颜色：阶段变化时由 workspace 写（`setDot`），不重建头部；null = 没有状态点。
    dot: ?*ui.Signal(ui.Color),
    has_meta: bool,
    /// 路径 · 列 × 行：workspace 节流刷新（自持有文本信号）。
    meta: *ui.Signal([]const u8),
    drag: ?Drag,
    broadcast: ?Toggle,
    pin: ?Toggle,
    float_refusal: ?[]const u8,
    float_click: ui.Handler(void),
    more_label: []const u8,
    on_focus: ?ui.Handler(void),
    /// 文字与菜单由 Vm 自己持有（workspace 传的是临时缓冲）。
    title_buffer: [256]u8 = undefined,
    title_len: usize = 0,
    refusal_buffer: [128]u8 = undefined,
    entries: [max_menu]app_menu.Entry = undefined,
    handlers: [max_menu]ui.Handler(void) = undefined,
    entry_count: usize = 0,
    router: shortcut_router.Router,
    /// 挂载后写入：头部根节点与“更多”按钮（卡片的弹层锚点）。
    root: ?*ui.Node = null,
    more_node: ?*ui.Node = null,

    pub fn titleText(self: *const Vm) []const u8 {
        return self.title_buffer[0..self.title_len];
    }
    pub fn metaText(self: *const Vm) []const u8 {
        return self.meta.get();
    }
    pub fn isFocused(self: *const Vm) bool {
        return self.focused.get();
    }
    /// A card that asks for emphasis (AI: accent icon) keeps the floating chrome's title, 12/600
    /// fg-primary, in its pane too (主会话判定, ai-redesign-c); other cards use the focus state.
    pub fn titleEmphasized(self: *const Vm) bool {
        return self.accent_icon or self.focused.get();
    }
    pub fn accentShown(self: *const Vm) bool {
        return self.accent_icon or self.focused.get();
    }
    pub fn dotColor(self: *const Vm) ui.Color {
        return if (self.dot) |color| color.get() else ui.Color.TRANSPARENT;
    }
    /// 返回是否有变化（调用方据此请求重绘）。没有状态点的头部（卡片）忽略。
    pub fn setDot(self: *Vm, color: ui.Color) bool {
        const signal = self.dot orelse return false;
        if (ui.Color.eql(signal.peek(), color)) return false;
        signal.set(color);
        return true;
    }
    pub fn setFocused(self: *Vm, focused: bool) void {
        if (self.focused.peek() != focused) self.focused.set(focused);
    }
    /// 返回是否有变化（调用方据此请求重绘）。
    pub fn setMeta(self: *Vm, meta: []const u8) bool {
        if (std.mem.eql(u8, self.meta.peek(), meta)) return false;
        self.meta.set(meta);
        return true;
    }
    pub fn floatTooltip(self: *const Vm) []const u8 {
        return self.float_refusal orelse "浮动";
    }
    pub fn menuEntries(self: *const Vm) []const app_menu.Entry {
        return self.entries[0..self.entry_count];
    }
    /// 菜单选中：按 id 找到同序的动作。
    fn selectMenu(raw: *anyopaque, id: []const u8) void {
        const self: *Vm = @ptrCast(@alignCast(raw));
        for (self.menuEntries(), self.handlers[0..self.entry_count]) |entry, handler| {
            if (std.mem.eql(u8, entry.id, id)) return handler.invoke();
        }
    }
    pub fn pressBroadcast(self: *Vm) void {
        if (self.broadcast) |toggle| toggle.on_click.invoke();
    }
    pub fn pressPin(self: *Vm) void {
        if (self.pin) |toggle| toggle.on_click.invoke();
    }
    pub fn pressFloat(self: *Vm) void {
        self.float_click.invoke();
    }
    pub fn focusContent(self: *Vm) void {
        if (self.on_focus) |handler| handler.invoke();
    }
};

fn copyInto(buffer: []u8, value: []const u8) []const u8 {
    const n = @min(buffer.len, value.len);
    @memcpy(buffer[0..n], value[0..n]);
    return buffer[0..n];
}

/// 建 Vm 并渲染头部；返回头部根节点（Vm 由 `scope` 持有，随头部卸载释放）。
pub fn mount(cx: *ui.Cx, scope: *ui.Scope, spec: Spec) !*Vm {
    const vm = try scope.createState(Vm, .{
        .ids = spec.test_ids,
        .icon = spec.icon,
        .accent_icon = spec.accent_icon,
        .focused = try scope.createSignal(bool, spec.focused),
        .dot = if (spec.dot) |color| try scope.createSignal(ui.Color, color) else null,
        .has_meta = spec.has_meta,
        .meta = try scope.createText(spec.meta, .{}),
        .drag = spec.drag,
        .broadcast = spec.broadcast,
        .pin = spec.pin,
        .float_refusal = null,
        .float_click = spec.float_click,
        .more_label = spec.more_label,
        .on_focus = spec.on_focus,
        .router = spec.router,
    });
    vm.title_len = copyInto(&vm.title_buffer, spec.title).len;
    if (spec.float_refusal) |refusal| vm.float_refusal = copyInto(&vm.refusal_buffer, refusal);
    std.debug.assert(spec.menu.len == spec.menu_handlers.len);
    vm.entry_count = @min(spec.menu.len, max_menu);
    @memcpy(vm.entries[0..vm.entry_count], spec.menu[0..vm.entry_count]);
    @memcpy(vm.handlers[0..vm.entry_count], spec.menu_handlers[0..vm.entry_count]);
    const root = try ui.view.render(scope, cx, template.PaneHeader(.{ .vm = vm }));
    // A header selects its member but is not an editor: focusable for the pointer's default focus
    // transfer (on_focus hands focus to the member's content), never a Tab stop.
    root.behavior.interaction.tab_index = -1;
    return vm;
}

// ---- PaneDrag：把手 / 标题外层盒子 + 拖动绑定（手写组件，模板里当标签用；W-5 最小例外）----

pub const PaneDragProps = struct {
    vm: ui.Source(*Vm),
    /// 把手（固定 13 宽、带 test_id 与无障碍名）还是标题（随标题宽度，可收缩）。
    grip: ui.Source(bool) = .{ .value = false },
};

fn mountPaneDrag(props: PaneDragProps, scope: *ui.Scope, cx: *ui.Cx) !ui.view.ViewParts {
    const vm = props.vm.peek();
    const grip = props.grip.peek();
    const drag = vm.drag.?;
    const root = try ui.box(cx, if (grip)
        .{ .width = .{ .px = 13 }, .height = .{ .px = 24 }, .flex_shrink = 0, .direction = .row, .align_items = .center, .justify = .center, .cursor = .grab, .hit_behavior = .@"opaque" }
    else
        .{ .width = .{ .fit = .{} }, .min_width = 0, .flex_shrink = 1, .direction = .row, .align_items = .center, .overflow_hidden = true, .cursor = .grab }, .{});
    errdefer cx.destroyDetached(root);
    if (grip) {
        root.meta.ownership.meta.test_id = vm.ids.grip;
        root.behavior.interaction.a11y = .{ .role = .button, .label = "拖到其他卡片的上下左右边缘以分割布局" };
    }
    _ = try ui.interaction.drag.Binding.attach(scope, cx, root, .{ .axis = .both }, drag.handler, drag.context);
    return .{ .root = root, .slot = root };
}
pub fn PaneDrag(props: anytype) ui.view.SlottedOf(mountPaneDrag) {
    return ui.view.slotted(mountPaneDrag, props);
}

// ---- PaneMore：“更多”菜单经 `AppMenu.mountTrigger` 挂载（手写组件，模板里当标签用；W-6）----

pub const PaneMoreProps = struct {
    vm: ui.Source(*Vm),
};

fn mountPaneMore(props: PaneMoreProps, scope: *ui.Scope, cx: *ui.Cx) !ui.view.ViewParts {
    const vm = props.vm.peek();
    const mounted = try app_menu.AppMenu.mountTrigger(cx, scope, .{ .panel_test_id = vm.ids.menu, .position = .bottom_end }, .{ .context = vm, .select = Vm.selectMenu });
    mounted.menu.set(vm.menuEntries(), vm.router);
    return .{ .root = mounted.result.wrapper, .slot = mounted.result.trigger };
}
pub fn PaneMore(props: anytype) ui.view.SlottedOf(mountPaneMore) {
    return ui.view.slotted(mountPaneMore, props);
}
