const std = @import("std");
const ui = @import("ui");
const IdSpace = @import("../../shared/view/ai_id_space.zig").IdSpace;
const S = @import("ai_recovery_styles.zig");
pub const Action = enum { answer, edit, regenerate };
pub const Ticket = struct { owner: @import("../../../../ai/tool_scope.zig").Owner, turn: u64, conversation_id: ?@import("../../../../host/identity.zig").ConversationId = null };
pub const Envelope = struct { ticket: Ticket, action: Action };
pub const Snapshot = struct {
    ticket: Ticket,
    reason: []const u8,
    detail: ?[]const u8 = null,
    title: []const u8 = "请求失败",
    retries: u8,
    max_retries: u8,
    retry_enabled: bool,
    regenerate_enabled: bool,
    retry_disabled_reason: ?[]const u8 = null,
    regenerate_disabled_reason: ?[]const u8 = null,
    cooldown_seconds: u64,
    retained_answer: bool = true,
    has_tool_calls: bool = false,
};
pub const Actions = struct { context: *anyopaque, enqueue: *const fn (*anyopaque, Envelope) void };
const Click = struct {
    actions: Actions,
    envelope: Envelope,
    fn click(self: *Click) void {
        self.actions.enqueue(self.actions.context, self.envelope);
    }
};
/// Request-failure recovery (Pencil Kaf7E A9, user decision: the native danger Alert on its light
/// red fill): the title carries the HTTP status, the message the reason; the actions slot holds the
/// native sm buttons (retry the answer only · edit the question · new plan) and the hints under
/// them; the raw diagnostic folds under the Alert's details toggle.
pub fn mount(cx: *ui.Cx, scope: *ui.Scope, state: Snapshot, actions: Actions) !*ui.Node {
    const space = IdSpace.of(scope);
    const first_line = std.mem.trim(u8, state.reason[0 .. std.mem.indexOfScalar(u8, state.reason, '\n') orelse state.reason.len], " \t\r");
    const separator = if (std.mem.startsWith(u8, first_line, "HTTP ")) std.mem.indexOf(u8, first_line, " · ") else null;
    const code = if (separator) |offset| first_line[0..offset] else "";
    const summary = if (separator) |offset| first_line[offset + " · ".len ..] else first_line;
    const title = if (code.len > 0) try std.fmt.allocPrint(cx.allocator, "{s} · {s}", .{ state.title, code }) else try cx.allocator.dupe(u8, state.title);
    defer cx.allocator.free(title);
    const raw_diagnostic = std.mem.trim(u8, state.detail orelse state.reason, " \t\r\n");
    const diagnostic = if (std.mem.eql(u8, raw_diagnostic, first_line)) "" else if (std.mem.startsWith(u8, raw_diagnostic, first_line) and raw_diagnostic[first_line.len] == '\n') std.mem.trim(u8, raw_diagnostic[first_line.len + 1 ..], " \t\r\n") else raw_diagnostic;
    // Texts the Alert borrows live in this scope.
    const title_text = try scope.createText(title, .{});
    const summary_text = try scope.createText(summary, .{});
    const content: Content = .{ .cx = cx, .state = state, .actions = actions, .diagnostic = (try scope.createText(diagnostic, .{})).peek() };
    const v = ui.view;
    const alert = ui.widgets.Alert(.{
        .variant = .@"error",
        .title = title_text,
        .message = summary_text,
        .title_test_id = space.id("ai.recovery.title"),
        .message_test_id = space.id("ai.recovery.reason"),
        .details_test_id = space.id("ai.recovery.details"),
        .details_toggle_test_id = space.id("ai.recovery.details.toggle"),
        .details_text = "详情",
        .show_details_label = "展开错误详情",
        .hide_details_label = "收起错误详情",
    });
    const root = if (diagnostic.len > 0 or state.has_tool_calls)
        try v.render(scope, cx, v.with(alert, .{}).slots(.{ .actions = v.component(actionsNode, &content), .details = v.component(detailsNode, &content) }))
    else
        try v.render(scope, cx, v.with(alert, .{}).slots(.{ .actions = v.component(actionsNode, &content) }));
    root.meta.ownership.meta.test_id = space.id("ai.recovery");
    return root;
}

const Content = struct { cx: *ui.Cx, state: Snapshot, actions: Actions, diagnostic: []const u8 };

/// Native sm buttons in the design's order, then the hints (each on its own line under them).
fn actionsNode(content: *const Content, scope: *ui.Scope, cx: *ui.Cx) !*ui.Node {
    const space = IdSpace.of(scope);
    const state = content.state;
    // Buttons on one wrapping row, each hint on its own line under them.
    const holder = try ui.box(cx, .{ .width = .fill(), .min_width = 0, .direction = .column, .gap = 4 }, .{});
    const buttons = try ui.box(cx, .{ .width = .fill(), .min_width = 0, .direction = .row, .flex_wrap = .wrap, .align_items = .center, .gap = 6 }, .{});
    try holder.appendChild(cx.allocator, buttons);
    for ([_]Action{ .answer, .edit, .regenerate }) |action| {
        const label: []const u8 = switch (action) {
            .answer => "仅重试答复",
            .edit => "编辑问题",
            .regenerate => "重新生成计划",
        };
        const id: []const u8 = switch (action) {
            .answer => space.id("ai.recovery.answer"),
            .edit => space.id("ai.recovery.edit"),
            .regenerate => space.id("ai.recovery.regenerate"),
        };
        if (action == .regenerate and !state.has_tool_calls) continue;
        const enabled = switch (action) {
            .answer => state.retry_enabled,
            .regenerate => state.regenerate_enabled,
            .edit => true,
        };
        const click = try scope.createState(Click, .{ .actions = content.actions, .envelope = .{ .ticket = state.ticket, .action = action } });
        var cooldown: [64]u8 = undefined;
        const action_label = if (action == .answer and state.cooldown_seconds != 0) try std.fmt.bufPrint(&cooldown, "仅重试答复 · {d}s", .{state.cooldown_seconds}) else label;
        const shown_label = try scope.createText(if (action == .answer) action_label else if (action == .regenerate) "新计划" else label, .{});
        const button = try ui.widgets.Button(.{ .label = shown_label, .size = .sm, .a11y_label = label, .variant = @as(ui.widgets.button.ButtonVariant, if (action == .answer) .primary else .secondary), .disabled = !enabled, .on_click = cx.on(Click, click, Click.click) }).mount(scope, cx);
        button.meta.ownership.meta.test_id = id;
        try buttons.appendChild(cx.allocator, button);
    }
    const retained = if (state.retained_answer) "已保留部分答复" else "问题和附件已保留";
    const attempts = if (state.retries > 0) try std.fmt.allocPrint(cx.allocator, "{s} · 重试 {d}/{d}", .{ retained, state.retries, state.max_retries }) else try cx.allocator.dupe(u8, retained);
    defer cx.allocator.free(attempts);
    try appendHint(cx, holder, space.id("ai.recovery.retained"), attempts);
    if (state.cooldown_seconds != 0) {
        const reason = try std.fmt.allocPrint(cx.allocator, "服务冷却中，{d} 秒后可重试。", .{state.cooldown_seconds});
        defer cx.allocator.free(reason);
        try appendHint(cx, holder, space.id("ai.recovery.cooldown"), reason);
    }
    if (!state.retry_enabled) if (state.retry_disabled_reason) |reason| try appendHint(cx, holder, space.id("ai.recovery.answer.disabled_reason"), reason);
    if (!state.regenerate_enabled and state.has_tool_calls) if (state.regenerate_disabled_reason) |reason| try appendHint(cx, holder, space.id("ai.recovery.regenerate.disabled_reason"), reason);
    try appendHint(cx, holder, space.id("ai.recovery.answer.hint"), "仅重试答复：只根据已有结果生成答复，不执行命令。");
    return holder;
}

/// The folded diagnostic scrolls inside 120 (its wheel input stays in it, like any card scroller).
fn detailsNode(content: *const Content, scope: *ui.Scope, cx: *ui.Cx) !*ui.Node {
    const space = IdSpace.of(scope);
    const area = try ui.widgets.ScrollArea(.{ .direction = .vertical, .overscroll_y = .contain, .scrollbars = .always, .scrollbar_gutter = .stable }).mount(scope, cx);
    area.container.setStyleInline(cx.allocator, S.details(cx.tokens));
    area.container.meta.ownership.meta.test_id = space.id("ai.recovery.details.scroll");
    area.content.setStyleInline(cx.allocator, .{ .direction = .column, .gap = 4, .width = .fill(), .flex_shrink = 0 });
    if (content.diagnostic.len > 0) {
        const full_reason = try ui.textStyled(cx, S.detailText, content.diagnostic);
        full_reason.meta.ownership.meta.test_id = space.id("ai.recovery.diagnostic");
        try area.content.appendChild(cx.allocator, full_reason);
    }
    if (content.state.has_tool_calls) try area.content.appendChild(cx.allocator, try ui.textStyled(cx, S.detailText, "已完成调用不会重放；结果未知的操作需先核实。"));
    return area.container;
}

fn appendHint(cx: *ui.Cx, parent: *ui.Node, id: []const u8, text: []const u8) !void {
    const node = try ui.textStyled(cx, S.recoveryHint, text);
    node.meta.ownership.meta.test_id = id;
    node.setStyleInline(cx.allocator, .{ .width = .fill(), .min_width = 0 });
    try parent.appendChild(cx.allocator, node);
}
