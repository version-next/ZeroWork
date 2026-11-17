//! V-5：手写的“旧式命令式面板”，写法照搬 src/features/settings/view/panes/settings_updates.zig
//! 与 settings_notify.zig（mockup 模块不能 import src/**，见 V-1）：
//!   - 样式是 `fn (*const ui.ThemeTokens) ui.BoxStyle` 具名函数，经 `ui.boxStyled` / `ui.textStyled`
//!     挂 on_theme 钩子（= settings_updates_styles.zig 的 `S.card` / `S.pane`）；
//!   - 运行期颜色用 `scope.createEffect` 订阅 `cx.themeSignal()`（= app_theme.bindMaterial /
//!     paintSignal）；文字着色用 `node.meta.per_frame.hooks.on_theme`（= app_theme.bindInk）；
//!   - 有一个堆上的 `Live` 状态，`scope.onCleanup` 注册清理，清理里 `removeAfterLayoutHook`
//!     并释放自己（= settings_updates.zig 的 `Live`）；
//!   - `test_id` 直接写 `node.meta.ownership.meta.test_id`；
//!   - 子控件 `ui.widgets.Button(...).mount(scope, cx)` + `cx.on(State, s, method)`。
//! 与真实旧面板的差距见 docs/ui-revamp/YIX_SPIKE.md §V-5。
const std = @import("std");
const ui = @import("ui");

/// 探针：自检读取。
pub const Probe = struct {
    mounts: usize = 0,
    cleanups: usize = 0,
    theme_effect_runs: usize = 0,
    ink_hook_runs: usize = 0,
    after_layout_runs: usize = 0,
    clicks: usize = 0,
    live: usize = 0,
};
pub var probe: Probe = .{};

// ── 样式：具名主题函数（随 Cx.setTheme 重放） ──
fn card(t: *const ui.ThemeTokens) ui.BoxStyle {
    return .{
        .width = .fill(),
        .direction = .column,
        .gap = 6,
        .padding = .{ .left = 12, .right = 12, .top = 10, .bottom = 10 },
        .background = t.tokens.color.bg_secondary,
        .border = .{ .width = 1, .color = t.tokens.color.border, .radius = 8 },
    };
}
fn heading(t: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 13, .font_weight = 600, .color = t.tokens.color.fg_primary };
}

/// 旧面板依赖的“绑定”对象：真实代码里是 `settings_content_view.Binding`，
/// 其 `scope` 字段决定 onCleanup / createEffect 挂在哪个 scope 上。
pub const Binding = struct {
    scope: *ui.Scope,
    label: []const u8,
};

const Live = struct {
    cx: *ui.Cx,
    allocator: std.mem.Allocator,
    badge: ?*ui.Node = null,

    fn cleanup(self: *@This()) void {
        probe.cleanups += 1;
        probe.live -= 1;
        self.cx.removeAfterLayoutHook(self);
        self.allocator.destroy(self);
    }
    fn refresh(raw: *anyopaque, _: u8, _: bool) ui.AfterLayoutResult {
        _ = raw;
        probe.after_layout_runs += 1;
        return .done;
    }
};

const Click = struct {
    bound: *Binding,
    fn run(_: *@This()) void {
        probe.clicks += 1;
    }
};

/// 旧签名：`fn mountX(cx, bound) !*ui.Node`，与 settings_parts/*.zig 的 `mountContent` 同形。
pub fn mountContent(cx: *ui.Cx, bound: *Binding) !*ui.Node {
    probe.mounts += 1;
    const live = try bound.scope.allocator.create(Live);
    live.* = .{ .cx = cx, .allocator = bound.scope.allocator };
    probe.live += 1;
    try bound.scope.onCleanup(Live, live, Live.cleanup);
    try cx.addAfterLayoutHook(live, Live.refresh);

    const pane = try ui.boxStyled(cx, card, .{});
    pane.meta.ownership.meta.test_id = "spike.v5.legacy";
    const title = try ui.textStyled(cx, heading, bound.label);
    title.meta.ownership.meta.test_id = "spike.v5.legacy.title";
    try pane.appendChild(cx.allocator, title);

    // bindInk 式：on_theme 钩子直接改文字颜色。
    const badge = try ui.text(cx, "badge", .{ .font_size = 11, .color = cx.tokens.tokens.color.fg_secondary });
    badge.meta.ownership.meta.test_id = "spike.v5.legacy.badge";
    badge.meta.per_frame.hooks.on_theme = struct {
        fn paint(n: *ui.Node, t: *const ui.ThemeTokens, _: std.mem.Allocator) void {
            probe.ink_hook_runs += 1;
            n.setTextColor(t.tokens.color.fg_secondary);
        }
    }.paint;
    live.badge = badge;
    try pane.appendChild(cx.allocator, badge);

    // bindMaterial 式：effect 订阅主题信号，改背景。
    const swatch = try ui.box(cx, .{ .width = .{ .px = 40 }, .height = .{ .px = 12 } }, .{});
    swatch.meta.ownership.meta.test_id = "spike.v5.legacy.swatch";
    try bound.scope.createEffect(.{ .node = swatch, .publication = try cx.themeSignal() }, struct {
        fn paint(ctx: anytype) void {
            probe.theme_effect_runs += 1;
            ctx.node.setBackground(ctx.publication.get().tokens.color.bg_tertiary);
        }
    }.paint);
    try pane.appendChild(cx.allocator, swatch);

    const click = try bound.scope.createState(Click, .{ .bound = bound });
    const button = try ui.widgets.Button(.{ .label = "旧面板按钮", .on_click = cx.on(Click, click, Click.run) }).mount(bound.scope, cx);
    button.meta.ownership.meta.test_id = "spike.v5.legacy.button";
    try pane.appendChild(cx.allocator, button);
    return pane;
}

// ── 嵌入适配：把旧签名包成 ComponentOf 能接受的 fn (Props, *Scope, *Cx) !*Node ──
// 关键：Binding.scope 必须是组件的子 scope（参数 `scope`），旧面板注册的 cleanup / effect
// 才会随 Yix 分支卸载一起释放。
pub const LegacyProps = struct { label: []const u8 = "legacy" };
fn mountLegacy(props: LegacyProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const bound = try scope.createState(Binding, .{ .scope = scope, .label = props.label });
    return mountContent(cx, bound);
}
pub fn LegacyPanel(props: LegacyProps) ui.view.ComponentOf(mountLegacy) {
    return ui.view.component(mountLegacy, props);
}

// ── 反例：沿用外部长寿命 Binding（真实旧代码 `bound.scope` 就是这种情况） ──
pub var outer_binding: ?*Binding = null;
fn mountLegacyOuter(props: LegacyProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    _ = props;
    _ = scope;
    return mountContent(cx, outer_binding.?);
}
pub fn LegacyPanelOuterScope(props: LegacyProps) ui.view.ComponentOf(mountLegacyOuter) {
    return ui.view.component(mountLegacyOuter, props);
}
