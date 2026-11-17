//! Shared history row used by the session list and the welcome page.
const ui = @import("ui");
const S = @import("ai_sessions_styles.zig");
const T = @import("../../../../shared/ui/theme/app_theme.zig");
const Phase = @import("../../../../ai/assistant_store.zig").Phase;
const IdSpace = @import("../../shared/view/ai_id_space.zig").IdSpace;
pub const SessionPhases = @import("../model/view_model.zig").SessionPhases;
pub const Action = enum { view, locate, restore, copy, copy_use, end, new, more, children };
pub const Entry = struct { id: u64, title: []const u8, owner: []const u8, detail: []const u8 = "", active: bool = false, phase: @import("../../../../ai/assistant_store.zig").Phase = .idle, bound: bool = false, ending: bool = false, can_restore: bool = false, has_children: bool = false, can_copy: bool = false, can_remove: bool = true, first_use: bool = false };
pub const Hooks = struct { context: *anyopaque, select: *const fn (*anyopaque, u64) void, request_close: *const fn (*anyopaque, u64) void, remove: *const fn (*anyopaque, u64) void, act: ?*const fn (*anyopaque, u64, Action) void = null, confirmed: ?*const fn (*anyopaque, u64, bool) void = null,
    /// The window's conversation phases. A row follows its conversation's phase through it; without
    /// one the row keeps the phase it was built with (`Entry.phase`).
    phases: ?*SessionPhases = null };
const Row = struct {
    hooks: Hooks,
    menu_open: ?*ui.Signal(bool),
    space: IdSpace = .main,
    phase: Phase,
    action_id: [64]u8 = undefined,
    id: u64,
    select_id: [64]u8 = undefined,
    delete_id: [64]u8 = undefined,
    row_id: [64]u8 = undefined,
    status_slot: ?*ui.Node = null,
    tag_label: ?*ui.Signal([]const u8) = null,
    tag_color: ?*ui.Signal(ui.widgets.tag.TagColor) = null,
    action: Action = .view,
    fn select(self: *Row) void {
        if (self.menu_open) |open| open.set(false);
        if (self.hooks.act) |callback| callback(self.hooks.context, self.id, .view) else self.hooks.select(self.hooks.context, self.id);
    }
    fn act(self: *Row) void {
        if (self.hooks.act) |callback| callback(self.hooks.context, self.id, self.action);
    }
    fn remove(self: *Row) void {
        self.hooks.request_close(self.hooks.context, self.id);
    }
    /// Shows `phase`: the Tag's label and color, and the slot's `ai.session.status.<phase>` id.
    fn showPhase(self: *Row, phase: Phase) void {
        self.phase = phase;
        if (self.tag_label) |label| label.set(phaseLabel(phase));
        if (self.tag_color) |color| color.set(phaseTagColor(phase));
        if (self.status_slot) |slot| slot.meta.ownership.meta.test_id = phaseTestId(self.space, phase);
    }
};

/// One session row (Pencil O7 `cMKkE`，ai-redesign-c): line 1 title 12.5/500 · native `W.Tag` sm (phase);
/// line 2 已绑定 / 未绑定 · 归属 · native ghost xs icon Buttons (查看 · 定位 · 恢复 / 使用 · 复制并使用 · 删除),
/// each with a native Tooltip. The current conversation sits on bg-hover.
pub fn mount(cx: *ui.Cx, scope: *ui.Scope, entry: Entry, hooks: Hooks, highlighted: ?*ui.Signal(u64), menu_open: ?*ui.Signal(bool)) !*ui.Node {
    const space = IdSpace.of(scope);
    const state = try scope.createState(Row, .{ .hooks = hooks, .menu_open = menu_open, .space = space, .phase = entry.phase, .id = entry.id });
    const row = try ui.box(cx, S.row(), .{});
    row.meta.ownership.meta.test_id = try space.print(&state.row_id, "ai.session.row.{d}", .{entry.id});
    const hovered = try ui.hooks.useHover(scope, row);
    try scope.createEffect(.{ .cx = cx, .row = row, .hovered = hovered, .highlighted = highlighted, .active = entry.active, .id = entry.id, .publication = try cx.themeSignal() }, struct {
        fn run(ctx: anytype) void {
            _ = ctx.publication.get();
            ctx.row.setStyleInline(ctx.cx.allocator, S.rowBackground(ctx.cx.tokens, if (ctx.highlighted) |signal| signal.get() == ctx.id else ctx.active, ctx.hovered.get()));
            ctx.cx.requestRedraw();
        }
    }.run);
    const first_line = try ui.box(cx, S.firstLine(), .{});
    first_line.meta.ownership.meta.test_id = space.id("ai.session.first_line");
    try row.appendChild(cx.allocator, first_line);
    const title = try ui.textStyled(cx, S.title, entry.title);
    title.setStyleInline(cx.allocator, S.titleBox());
    title.meta.ownership.meta.test_id = space.id("ai.session.title");
    // The full title, only while the row shows it cut short (native expansion hint: the Tooltip
    // judges the truncation from the title's layout; `fill` bounds the title by the row).
    const title_hint = try ui.widgets.Tooltip(.{ .text = entry.title, .width = @as(f32, 320), .wrap = .char, .max_lines = 0, .fill = true, .show = .if_truncated }).mount(scope, cx);
    title_hint.content.meta.ownership.meta.test_id = space.id("ai.session.title.tooltip");
    title_hint.wrapper.setStyleInline(cx.allocator, S.titleBox());
    try title_hint.trigger.appendChild(cx.allocator, title);
    try first_line.appendChild(cx.allocator, title_hint.wrapper);
    // Phase: native W.Tag sm. `ai.session.status.<phase>` names the slot around it (e2e waits on it).
    state.tag_label = try scope.createText(phaseLabel(entry.phase), .{});
    state.tag_color = try scope.createSignal(ui.widgets.tag.TagColor, phaseTagColor(entry.phase));
    const slot = try ui.box(cx, .{ .width = .{ .fit = .{} }, .height = .{ .fit = .{} }, .flex_shrink = 0, .direction = .row, .align_items = .center }, .{});
    slot.meta.ownership.meta.test_id = phaseTestId(space, entry.phase);
    state.status_slot = slot;
    // The row follows its conversation's phase (model → view): the effect runs again whenever the
    // window's phases change, and repaints only when this conversation's did.
    if (hooks.phases) |phases| try scope.createEffect(.{ .row = state, .phases = phases, .initial = entry.phase, .cx = cx }, struct {
        fn run(ctx: anytype) void {
            const phase = ctx.phases.phase(ctx.row.id, ctx.initial);
            if (phase == ctx.row.phase) return;
            ctx.row.showPhase(phase);
            ctx.cx.requestRedraw();
        }
    }.run);
    const tag = try ui.view.render(scope, cx, ui.widgets.Tag(.{ .label = state.tag_label.?, .color = state.tag_color.?, .size = .sm }));
    tag.meta.ownership.meta.test_id = space.id("ai.session.phase_tag");
    try slot.appendChild(cx.allocator, tag);
    try first_line.appendChild(cx.allocator, slot);
    const second_line = try ui.box(cx, S.secondLine(), .{});
    second_line.meta.ownership.meta.test_id = space.id("ai.session.second_line");
    try row.appendChild(cx.allocator, second_line);
    if (hooks.act != null) {
        const binding = if (entry.bound) try ui.textStyled(cx, S.boundText, "已绑定") else try ui.textStyled(cx, S.unboundText, "未绑定");
        binding.setStyleInline(cx.allocator, .{ .flex_shrink = 0 });
        binding.meta.ownership.meta.test_id = if (entry.bound) space.id("ai.session.bound") else space.id("ai.session.unbound");
        try second_line.appendChild(cx.allocator, binding);
    }
    const owner = try ui.textStyled(cx, S.owner, "");
    owner.meta.ownership.meta.test_id = space.id("ai.session.owner");
    const summary = if (entry.ending) try @import("std").fmt.allocPrint(cx.allocator, "{s} · 正在停止任务", .{entry.owner}) else try cx.allocator.dupe(u8, entry.owner);
    defer cx.allocator.free(summary);
    try owner.setTextContent(cx.allocator, summary);
    // O7: “已绑定 · 归属” — the separator is its own text, so the owner text stays the owner.
    if (hooks.act != null and summary.len != 0) {
        const dot = try ui.textStyled(cx, S.owner, "·");
        dot.setStyleInline(cx.allocator, .{ .flex_shrink = 0 });
        try second_line.appendChild(cx.allocator, dot);
    }
    owner.setStyleInline(cx.allocator, S.ownerBox());
    const owner_hint = try @import("../../../../shared/ui/components/control_hint/control_hint.zig").mount(cx, scope, owner, summary, .{ .id = space.id("ai.session.owner.tooltip"), .width = 320, .wrap = .char, .visible = menu_open, .layout = S.ownerBox() });
    try second_line.appendChild(cx.allocator, owner_hint.wrapper);
    const actions = try ui.box(cx, S.rowActions(), .{});
    try second_line.appendChild(cx.allocator, actions);
    const select = try ui.widgets.Button(.{ .variant = .ghost, .size = .xs, .icon_only = true, .icon_asset = ui.icons.get("arrow-up-right").?, .a11y_label = "查看此 AI 会话", .on_click = cx.on(Row, state, Row.select) }).mount(scope, cx);
    select.meta.ownership.meta.test_id = try space.print(&state.select_id, "ai.session.jump.{d}", .{entry.id});
    try actions.appendChild(cx.allocator, try actionTooltip(cx, scope, select, "查看此 AI 会话"));
    if (hooks.act != null) {
        inline for (.{ .{ Action.locate, "locate-fixed", "locate" }, .{ Action.restore, "rotate-ccw", "restore" }, .{ Action.copy_use, "copy-plus", "copy_use" } }) |spec| {
            const enabled = switch (spec[0]) {
                .locate => entry.bound,
                .restore => entry.can_restore,
                .copy_use => entry.can_copy,
                else => false,
            };
            if (enabled) {
                const action_state = try scope.createState(Row, .{ .hooks = hooks, .menu_open = menu_open, .phase = entry.phase, .id = entry.id, .action = spec[0] });
                const label = if (spec[0] == .locate) "定位原持有者" else if (spec[0] == .copy_use) "复制并使用到当前 Agent" else if (entry.first_use) "使用到当前 Agent" else "恢复到当前 Agent";
                const action_button = try ui.widgets.Button(.{ .variant = .ghost, .size = .xs, .icon_only = true, .icon_asset = ui.icons.get(if (spec[0] == .restore and entry.first_use) "play" else spec[1]).?, .a11y_label = label, .on_click = cx.on(Row, action_state, Row.act) }).mount(scope, cx);
                action_button.meta.ownership.meta.test_id = try space.print(&action_state.action_id, "ai.session.{s}.{d}", .{ spec[2], entry.id });
                try actions.appendChild(cx.allocator, try actionTooltip(cx, scope, action_button, label));
            }
        }
    }
    const remove = try ui.widgets.Button(.{ .variant = .ghost, .size = .xs, .icon_only = true, .icon_asset = ui.icons.get("trash-2").?, .a11y_label = "删除 AI 会话", .on_click = cx.on(Row, state, Row.remove) }).mount(scope, cx);
    if (!entry.can_remove) remove.setDisplay(.none);
    remove.meta.ownership.meta.test_id = try space.print(&state.delete_id, "ai.session.delete.{d}", .{entry.id});
    if (entry.can_remove) try actions.appendChild(cx.allocator, try actionTooltip(cx, scope, remove, "删除 AI 会话")) else try actions.appendChild(cx.allocator, remove);
    return row;
}
fn actionTooltip(cx: *ui.Cx, scope: *ui.Scope, button: *ui.Node, label: []const u8) !*ui.Node {
    const tooltip = try ui.widgets.Tooltip(.{ .text = label }).mount(scope, cx);
    tooltip.wrapper.setStyleInline(cx.allocator, .{ .width = .{ .fit = .{} }, .height = .{ .fit = .{} }, .flex_shrink = 0 });
    try tooltip.trigger.appendChild(cx.allocator, button);
    return tooltip.wrapper;
}

pub fn phaseTestId(space: IdSpace, phase: @import("../../../../ai/assistant_store.zig").Phase) []const u8 {
    return switch (phase) {
        .idle => space.id("ai.session.status.idle"),
        .running => space.id("ai.session.status.running"),
        .approval => space.id("ai.session.status.approval"),
        .done => space.id("ai.session.status.done"),
        .failed => space.id("ai.session.status.failed"),
        .stopped => space.id("ai.session.status.stopped"),
    };
}
pub fn phaseIcon(phase: @import("../../../../ai/assistant_store.zig").Phase) []const u8 {
    return switch (phase) {
        .idle => "circle-dashed",
        .running => "loader-circle",
        .approval => "circle-help",
        .done => "circle-check",
        .failed => "circle-alert",
        .stopped => "circle-stop",
    };
}
pub fn phaseColor(phase: @import("../../../../ai/assistant_store.zig").Phase) ui.Color {
    return switch (phase) {
        .idle, .stopped => T.current().fg_2,
        .running => T.current().accent_ink,
        .approval => T.current().warn_ink,
        .done => T.current().ok_ink,
        .failed => T.current().danger_ink,
    };
}
/// The phase's native Tag color (O7: 运行中 accent · 待确认 warning · 已完成 success · 失败 danger).
pub fn phaseTagColor(phase: Phase) ui.widgets.tag.TagColor {
    return switch (phase) {
        .idle, .stopped => .neutral,
        .running => .accent,
        .approval => .warning,
        .done => .success,
        .failed => .danger,
    };
}
pub fn phaseLabel(phase: @import("../../../../ai/assistant_store.zig").Phase) []const u8 {
    return switch (phase) {
        .idle => "未开始",
        .running => "运行中",
        .approval => "待确认",
        .done => "已完成",
        .failed => "失败",
        .stopped => "已暂停",
    };
}
