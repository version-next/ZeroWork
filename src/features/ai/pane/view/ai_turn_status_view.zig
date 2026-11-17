//! One left-aligned lifecycle row, updated in place from submitted to completed.
const std = @import("std");
const ui = @import("ui");
const IdSpace = @import("../../shared/view/ai_id_space.zig").IdSpace;
const S = @import("ai_assistant_styles.zig");
const Turn = @import("../../../../ai/conversation_turn.zig").Turn;
/// Pencil Kaf7E A3 "Turn meta" at the chat scale: one 20-high row that never wraps (320 wide
/// included): the turn mark 12, the label 11 fg_tertiary (the "～回合结束～" decoration is kept, user
/// decision), the elapsed time (gives way first, ellipsis), the usage, then copy / fork at the right.
/// It closes the turn: 20 to the next one.
pub fn rowStyle(_: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .fill(), .min_width = 0, .height = .{ .px = 20 }, .direction = .row, .justify = .start, .align_items = .center, .gap = 4, .margin = .{ .bottom = S.turn_gap - S.turn_block_gap }, .flex_shrink = 0 };
}
pub fn metaText(t: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 11, .line_height = 1.5, .color = t.tokens.color.fg_tertiary, .wrap = .none, .text_overflow = .ellipsis };
}
fn separatorStyle(t: *const ui.ThemeTokens) ui.BoxStyle {
    return .{ .width = .{ .px = 3 }, .height = .{ .px = 3 }, .flex_shrink = 0, .background = t.tokens.color.fg_tertiary, .border = .{ .width = 0, .radius = 1.5 } };
}
pub fn dot(cx: *ui.Cx, space: IdSpace) !*ui.Node {
    const node = try ui.boxStyled(cx, separatorStyle, .{});
    node.meta.ownership.meta.test_id = space.id("ai.turn.separator");
    return node;
}
/// "处理用时 6 秒" / "处理用时 3 分 20 秒" (shared/base/format: whole seconds under a minute,
/// minutes and seconds above).
pub fn elapsedLabel(buffer: []u8, elapsed_ms: u64) ![]const u8 {
    var duration_buffer: [48]u8 = undefined;
    const format = @import("../../../../shared/base/format.zig");
    const value = if (elapsed_ms < std.time.ms_per_min) format.duration(&duration_buffer, elapsed_ms, .long) else format.duration(&duration_buffer, elapsed_ms, .short);
    return std.fmt.bufPrint(buffer, "处理用时 {s}", .{value});
}
pub fn elapsedMs(turn: *const Turn, now_wall: u64, now_mono: u64) u64 {
    const elapsed = if (turn.ended_at_ms) |ended| (if (turn.started_mono_ms > 0) turn.elapsed_ms else ended -| turn.sent_at_ms) else (if (turn.started_mono_ms > 0) now_mono -| turn.started_mono_ms else now_wall -| turn.sent_at_ms);
    var waiting: u64 = 0;
    for (turn.steps.items) |step| {
        waiting +|= step.approval_elapsed_ms;
        if (step.approval_started_ms) |start| waiting +|= (step.ended_ms orelse now_mono) -| start;
    }
    return elapsed -| waiting;
}
/// The usage button's label: short so the status row holds one line at 320 ("用量 2.6K"); the
/// popover and the accessible name say "本回合".
pub fn usageLabel(buffer: []u8, turn: *const Turn) ![]const u8 {
    const input = turn.input_tokens orelse return "用量未返回";
    const output = turn.output_tokens orelse return "用量未返回";
    var count_buffer: [32]u8 = undefined;
    return std.fmt.bufPrint(buffer, "用量 {s}", .{try @import("../../shared/model/ai_token_count.zig").format(&count_buffer, input +| output)});
}
pub fn usageDetails(buffer: []u8, turn: *const Turn) ![]const u8 {
    const input = turn.input_tokens orelse return "服务商未返回完整用量，无法显示输入和输出明细。";
    const output = turn.output_tokens orelse return "服务商未返回完整用量，无法显示输入和输出明细。";
    if (turn.request_count) |count| if (count > 0) return std.fmt.bufPrint(buffer, "输入 {d} Token\n输出 {d} Token\n请求次数 {d}\n\n本回合各次请求的累计用量。", .{ input, output, count });
    return std.fmt.bufPrint(buffer, "输入 {d} Token\n输出 {d} Token\n请求次数未记录\n\n本回合各次请求的累计用量。", .{ input, output });
}
pub fn waveOffset(time_ms: f64, index: usize, reduced_motion: bool) f32 {
    if (reduced_motion) return 0;
    return @floatCast(@sin(time_ms * (2.0 * std.math.pi / 1400.0) - @as(f64, @floatFromInt(index)) * 0.65) * 1.5);
}
pub const Label = struct {
    text: []const u8,
    animated: bool = true,
};
pub fn turnLabel(turn: *const Turn) Label {
    if (turn.ended_at_ms != null) return .{ .text = "～回合结束～", .animated = false };
    // A decision that needs the user takes precedence over other active tools.
    for (turn.steps.items) |step| if (step.phase == .approval) return .{ .text = "等待确认 · 流程暂停", .animated = false };
    var index = turn.steps.items.len;
    while (index > 0) {
        index -= 1;
        const step = turn.steps.items[index];
        if (step.phase != .running) continue;
        const text = if (std.mem.eql(u8, step.name, "run_command")) "～执行命令中～" else if (std.mem.eql(u8, step.name, "read_terminal")) "～读取终端中～" else if (std.mem.eql(u8, step.name, "read_remote_file")) "～读取文件中～" else if (std.mem.eql(u8, step.name, "list_remote_files")) "～查看目录中～" else "～执行操作中～";
        return .{ .text = text };
    }
    for (turn.steps.items) |step| if (step.phase == .assembling or step.phase == .approved) return .{ .text = "～准备操作中～" };
    return .{ .text = "～大浪淘金中～" };
}
const Wave = struct {
    cx: *ui.Cx,
    root: *ui.Node,
    fn tick(raw: *anyopaque, _: u8, _: bool) ui.AfterLayoutResult {
        const self: *Wave = @ptrCast(@alignCast(raw));
        if (@import("../../../../shared/ui/styles/visible_region.zig").snapshot(self.cx, self.root) == null) return .done;
        for (self.root.children.items, 0..) |glyph, index| glyph.setStyle(self.cx.allocator, .translate_y, waveOffset(self.cx.frame_time_ms, index, self.cx.reduced_motion));
        if (!self.cx.reduced_motion) self.cx.scheduleRedrawAfterNs(16 * std.time.ns_per_ms);
        return .done;
    }
};
/// The running label follows the live turn on its own: the footer that holds it is mounted by a
/// full conversation render, while step events and approval sync only invalidate the retained
/// timeline. The row's clock compares the turn's label with the one shown every laid-out frame
/// and rebuilds the glyphs in place when it changed; the wave runs only while it is animated.
const Activity = struct {
    wave: Wave,
    space: IdSpace,
    turn: *const Turn,
    shown: Label,
    waving: bool = false,
    fn release(self: *Activity) void {
        self.setWaving(false);
    }
    fn setWaving(self: *Activity, on: bool) void {
        if (on == self.waving) return;
        if (on) {
            self.wave.cx.addAfterLayoutHook(&self.wave, Wave.tick) catch return;
        } else self.wave.cx.removeAfterLayoutHook(&self.wave);
        self.waving = on;
    }
    fn glyphs(self: *Activity, text: []const u8) !void {
        const cx = self.wave.cx;
        const root = self.wave.root;
        while (root.children.items.len > 0) {
            const child = root.children.items[root.children.items.len - 1];
            cx.detachChild(root, child);
            cx.destroyDetached(child);
        }
        var characters = (try std.unicode.Utf8View.init(text)).iterator();
        while (characters.nextCodepointSlice()) |character| {
            const glyph = try ui.textStyled(cx, metaText, character);
            glyph.meta.ownership.meta.test_id = self.space.id("ai.turn.wave.glyph");
            glyph.behavior.interaction.a11y = .{ .hidden = true };
            try root.appendChild(cx.allocator, glyph);
        }
        root.behavior.interaction.a11y = .{ .role = .group, .label = text };
    }
    /// True when the label changed (the row needs layout).
    fn follow(self: *Activity) bool {
        const next = turnLabel(self.turn);
        if (std.mem.eql(u8, next.text, self.shown.text) and next.animated == self.shown.animated) return false;
        self.glyphs(next.text) catch return false;
        self.shown = next;
        self.setWaving(next.animated);
        return true;
    }
};
fn runningLabel(cx: *ui.Cx, scope: *ui.Scope, turn: *const Turn, label: Label) !*Activity {
    const root = try ui.box(cx, .{ .direction = .row, .height = .{ .px = 20 }, .gap = 0, .align_items = .center, .flex_shrink = 0 }, .{});
    const activity = try scope.createState(Activity, .{ .wave = .{ .cx = cx, .root = root }, .space = IdSpace.of(scope), .turn = turn, .shown = label });
    try activity.glyphs(label.text);
    try scope.onCleanup(Activity, activity, Activity.release);
    activity.setWaving(label.animated);
    return activity;
}
const Clock = struct {
    cx: *ui.Cx,
    node: *ui.Node,
    turn: *const Turn,
    activity: *Activity,
    seconds: ?u64 = null,
    fn release(self: *Clock) void {
        self.cx.removeAfterLayoutHook(self);
    }
    fn tick(raw: *anyopaque, _: u8, _: bool) ui.AfterLayoutResult {
        const self: *Clock = @ptrCast(@alignCast(raw));
        if (@import("../../../../shared/ui/styles/visible_region.zig").snapshot(self.cx, self.node) == null) return .done;
        const relabeled = self.activity.follow();
        const now_wall: u64 = @intCast(@max(0, @import("../../../../platform/realtime.zig").milliseconds(self)));
        const now_mono: u64 = @intCast(@divTrunc(@import("../../../../platform/realtime.zig").monotonicNs(), std.time.ns_per_ms));
        const elapsed = elapsedMs(self.turn, now_wall, now_mono);
        self.cx.scheduleRedrawAfterNs((std.time.ms_per_s - elapsed % std.time.ms_per_s) * std.time.ns_per_ms);
        if (self.seconds == elapsed / 1000) return if (relabeled) .needs_layout else .done;
        self.seconds = elapsed / 1000;
        var buffer: [96]u8 = undefined;
        self.node.setTextContent(self.cx.allocator, elapsedLabel(&buffer, elapsed) catch return .done) catch return .done;
        return .needs_layout;
    }
};
pub fn mount(cx: *ui.Cx, scope: *ui.Scope, turn: *const Turn, texture: ?u32) !*ui.Node {
    const space = IdSpace.of(scope);
    const row = try ui.boxStyled(cx, rowStyle, .{});
    const completed = turn.ended_at_ms != null;
    row.meta.ownership.meta.test_id = if (completed) space.id("ai.turn.complete") else space.id("ai.turn.running");
    const logo = try ui.image(cx, texture orelse 0, .{ .width = .{ .px = 12 }, .height = .{ .px = 12 }, .flex_shrink = 0 });
    logo.meta.ownership.meta.test_id = space.id("ai.turn.logo");
    try row.appendChild(cx.allocator, logo);
    const activity = turnLabel(turn);
    const running: ?*Activity = if (!completed) try runningLabel(cx, scope, turn, activity) else null;
    const label = if (running) |value| value.wave.root else try ui.textStyled(cx, metaText, activity.text);
    label.setStyleInline(cx.allocator, .{ .flex_shrink = 0 });
    label.meta.ownership.meta.test_id = space.id("ai.turn.label");
    try row.appendChild(cx.allocator, label);
    var buffer: [96]u8 = undefined;
    const wall: u64 = @intCast(@max(0, @import("../../../../platform/realtime.zig").milliseconds(row)));
    const mono: u64 = @intCast(@divTrunc(@import("../../../../platform/realtime.zig").monotonicNs(), std.time.ns_per_ms));
    const elapsed = try ui.textStyled(cx, metaText, try elapsedLabel(&buffer, elapsedMs(turn, wall, mono)));
    // The elapsed time gives way first so the row stays on one line at 320.
    elapsed.setStyleInline(cx.allocator, .{ .min_width = 0, .flex_shrink = 1 });
    elapsed.meta.ownership.meta.test_id = space.id("ai.turn.elapsed");
    try row.appendChild(cx.allocator, elapsed);
    if (!completed) {
        const clock = try scope.createState(Clock, .{ .cx = cx, .node = elapsed, .turn = turn, .activity = running.? });
        try cx.addAfterLayoutHook(clock, Clock.tick);
        try scope.onCleanup(Clock, clock, Clock.release);
    } else {
        const popup = try ui.widgets.Popover(.{ .trigger = .manual, .position = .top_start, .width = @as(f32, 250), .constrain_width_to_viewport = true }).mount(scope, cx);
        popup.wrapper.setStyleInline(cx.allocator, .{ .flex_shrink = 0 });
        const usage = try ui.widgets.Button(.{
            .label = try usageLabel(&buffer, turn),
            .a11y_label = "查看本回合用量明细",
            .variant = .ghost,
            .size = .xs,
            .on_click = popup.toggle,
        }).mount(scope, cx);
        usage.meta.ownership.meta.test_id = space.id("ai.turn.tokens");
        try popup.trigger.appendChild(cx.allocator, usage);
        var detail_buffer: [320]u8 = undefined;
        const details = try ui.textStyled(cx, usageDetailText, try usageDetails(&detail_buffer, turn));
        details.meta.ownership.meta.test_id = space.id("ai.turn.usage.details");
        try popup.content.appendChild(cx.allocator, details);
        try row.appendChild(cx.allocator, popup.wrapper);
        // Copy / fork (appended by the host) sit at the right.
        try row.appendChild(cx.allocator, try ui.box(cx, .{ .width = .fill(), .min_width = 0, .height = .{ .px = 1 } }, .{}));
    }
    return row;
}
fn usageDetailText(t: *const ui.ThemeTokens) ui.TextStyle {
    return .{ .font_size = 12, .line_height = 1.6, .color = t.tokens.color.fg_secondary, .wrap = .word };
}
