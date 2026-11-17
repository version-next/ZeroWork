//! Stateless native widget rendering of the frozen group-close ledger.
const std = @import("std");
const ui = @import("ui");
const controller = @import("../../../host/group_close_controller.zig");
const styles = @import("group_close_styles.zig");
const confirm = @import("../../../shared/ui/confirm/confirm.zig");
const theme = @import("../../../shared/ui/theme/app_theme.zig");
pub const Props = struct {
    open: ui.Model(bool),
    group_name: []const u8,
    plan: *const controller.Plan,
    partial: bool,
    approve: ui.Handler(void),
};
/// The shared native confirmation (`shared/ui/confirm`, zenit ConfirmDialog): the phase's question as
/// the title, the group summary as the message, the frozen member ledger in its slot. Confirming:
/// 取消 + danger “关闭 N 个会话”; closing: “停止后续关闭” + the disabled action; partial result:
/// “收起结果” + “重试未关闭项” (primary). 取消 / × / Esc / scrim all go to `open`'s write (cancel).
pub fn mount(cx: *ui.Cx, scope: *ui.Scope, props: Props) !confirm.Confirm {
    var buf: [512]u8 = undefined;
    const counts = props.plan.counts();
    const summary = if (props.partial) try std.fmt.bufPrint(&buf, "{s} · 已关闭 {d} · 未关闭 {d} · 待核实 {d}", .{ props.group_name, counts.closed, counts.unclosed, counts.unknown }) else try std.fmt.bufPrint(&buf, "{s} · {d} 个会话", .{ props.group_name, props.plan.approvalCount() });
    var action_buf: [64]u8 = undefined;
    const action = if (props.partial) confirm.label(.retry, "未关闭项") else confirm.labelFmt(&action_buf, .close, " {d} 个会话", .{props.plan.approvalCount()});
    const dialog = try confirm.confirm(scope, cx, .{
        .open = props.open,
        .title = try scope.createText(if (props.plan.phase == .closing) "正在关闭组内会话" else if (props.partial) "部分成员尚未关闭" else "关闭组内全部会话？", .{}),
        .message = try scope.createText(summary, .{}),
        .action = try scope.createText(action, .{}),
        .tone = @as(confirm.Tone, if (props.partial) .primary else .danger),
        .cancel = try scope.createText(if (props.plan.phase == .closing) "停止后续关闭" else if (props.partial) "收起结果" else confirm.cancel_label, .{}),
        .action_disabled = props.plan.phase == .closing or props.plan.phase == .complete,
        .width = 480,
        .max_height = 480,
        // approve re-renders the dialog for the next phase itself.
        .close_on_confirm = false,
        .on_confirm = props.approve,
        .test_id = if (props.partial) "groups.close.partial" else "groups.close.confirm",
        .test_ids = .{ .title = "groups.close.heading", .cancel = "groups.close.cancel", .confirm = "groups.close.accept" },
    });
    const body = dialog.content;
    const scroll = try ui.widgets.ScrollArea(.{ .direction = .vertical, .rubber_band_y = false }).mount(scope, cx);
    scroll.container.setStyleInline(cx.allocator, styles.scroll(props.partial));
    scroll.container.meta.ownership.meta.test_id = "groups.close.members";
    scroll.content.setStyleInline(cx.allocator, styles.scrollContent());
    const list = try ui.box(cx, styles.list(), .{});
    for (props.plan.members.items) |*member| {
        var line = std.Io.Writer.Allocating.init(cx.allocator);
        defer line.deinit();
        try line.writer.print("{s}  #{d} · {s}", .{ member.label(), member.id, if (props.partial or !member.eligible or member.state == .closed) stateText(member.state) else "确认关闭" });
        if (!props.partial and member.eligible and member.state == .queued) {
            const impact = member.impact;
            if (impact.detail_len != 0) {
                try line.writer.writeByte('\n');
                try line.writer.writeAll(impact.detailText());
            }
            if (member.risk & 8 != 0) try line.writer.writeAll("\n运行命令将结束");
            if (impact.transfer != 0 or member.risk & 1 != 0) try line.writer.writeAll(" · 传输暂停并保留");
            if (impact.ai != 0 or member.risk & 2 != 0) try line.writer.writeAll(" · 停止 AI");
            if (impact.socks != 0 or member.risk & 4 != 0) try line.writer.writeAll(" · 释放 SOCKS");
            if (impact.unknown != 0 or member.risk & 16 != 0) try line.writer.writeAll(" · 存在待核实资源");
        }
        if (member.remote_effect_unknown) try line.writer.writeAll(" · 远端后果待核实");
        var text_style = styles.text(true);
        if (props.partial) text_style.color = if (member.state == .closed) theme.current().ok_ink else theme.current().warn_ink;
        const row = try ui.text(cx, line.writer.buffered(), text_style);
        if (props.partial) {
            if (member.state == .closed) theme.bindInk(row, "ok_ink") else theme.bindInk(row, "warn_ink");
        } else theme.bindInk(row, "fg_1");
        row.setStyleInline(cx.allocator, .{ .width = .fill(), .flex_shrink = 0 });
        try list.appendChild(cx.allocator, row);
    }
    try scroll.content.appendChild(cx.allocator, list);
    try body.appendChild(cx.allocator, scroll.container);
    if (props.partial) {
        try label(cx, body, "已关闭成员保留结果；只重试尚未关闭的原成员。", .{ .width = .fill(), .flex_shrink = 0 }, styles.note());
    } else {
        try label(cx, body, "将关闭全部成员，包括它们的独立页签。停止命令、AI 与 SOCKS；传输暂停并保留。", .{ .width = .fill(), .flex_shrink = 0 }, styles.text(true));
        try label(cx, body, "已关闭的成员不能自动恢复。", .{ .width = .fill(), .flex_shrink = 0 }, styles.note());
    }
    try scope.createEffect(.{ .list = list, .publication = try cx.themeSignal() }, struct {
        fn paint(ctx: anytype) void {
            _ = ctx.publication.get();
            ctx.list.setBackground(theme.popupInset());
        }
    }.paint);
    return dialog;
}
fn label(cx: *ui.Cx, parent: *ui.Node, value: []const u8, box: ui.BoxStyle, text: ui.TextStyle) !void {
    const node = try ui.text(cx, value, text);
    if (ui.Color.eql(text.color, theme.current().fg_1)) theme.bindInk(node, "fg_1") else theme.bindInk(node, "fg_2");
    node.setStyleInline(cx.allocator, box);
    try parent.appendChild(cx.allocator, node);
}
pub fn stateText(state: controller.MemberState) []const u8 {
    return switch (state) {
        .queued => "等待关闭",
        .await_confirm => "等待成员确认",
        .closing => "正在关闭",
        .closed => "已关闭",
        .cancelled => "已取消 · 仍存活",
        .failed => "关闭失败 · 可重试",
        .cleanup_unknown => "资源释放待核实",
    };
}
