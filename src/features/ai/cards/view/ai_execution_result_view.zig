//! Native projection for trusted host PTY execution results. Legacy/plugin cards
//! keep their existing renderer. Actions always carry the original full owner.
const std = @import("std");
const ui = @import("ui");
const IdSpace = @import("../../shared/view/ai_id_space.zig").IdSpace;
const facts = @import("../../../../ai/tool_results.zig");
const theme = @import("../../../../shared/ui/theme/app_theme.zig");
const S = @import("ai_execution_result_styles.zig");
pub const Action = enum { view_terminal, stop, takeover };
pub const Callbacks = struct {
    context: *anyopaque,
    perform: *const fn (*anyopaque, Action, facts.ExecutionActionTarget) anyerror!void,
};
const State = struct {
    cx: *ui.Cx,
    copy_command_feedback: *@import("../../../../shared/ui/components/copy_button/copy_button.zig").Button = undefined,
    copy_output_feedback: *@import("../../../../shared/ui/components/copy_button/copy_button.zig").Button = undefined,
    copy_recording_feedback: *@import("../../../../shared/ui/components/copy_button/copy_button.zig").Button = undefined,
    store: *facts.Store,
    record: *facts.Record,
    callbacks: ?Callbacks,
    on_toggle: ?ui.Handler(void),
    body: *@import("../../../../shared/ui/styles/layout_motion.zig").Disclosure,
    footer: *@import("../../../../shared/ui/styles/layout_motion.zig").Disclosure,
    feedback: *ui.Node,
    controls_disabled: *ui.Signal(bool),
    /// The row's disclosure state (the header Pressable's `expanded`, also its accessible state).
    expanded: *ui.Signal(bool),
    expected: ?facts.ExecutionActionTarget,
    collection: *ui.Node,
    details_label: *ui.Signal([]const u8),
    clock: *ui.Node,
    fn toggle(self: *State) void {
        self.record.expanded = !self.record.expanded;
        self.expanded.set(self.record.expanded);
        self.body.setExpanded(self.record.expanded);
        self.footer.setExpanded(self.record.expanded);
        self.clock.setDisplay(if (self.record.expanded) .flex else .none);
        self.collection.setDisplay(if (self.record.expanded and self.record.execution_details_expanded) .flex else .none);
        if (self.on_toggle) |callback| callback.invoke();
        self.cx.requestRedraw();
    }
    fn perform(self: *State, action: Action) void {
        const callback = self.callbacks orelse return;
        const projection = self.store.executionProjection(self.record) orelse return;
        const target = projection.actionTarget() orelse return;
        const expected = self.expected orelse return;
        if (!target.conversation_id.eql(expected.conversation_id) or !target.task_id.eql(expected.task_id) or !target.session.eql(expected.session) or !target.execution_id.eql(expected.execution_id)) return;
        if (action == .stop and !projection.canStop()) return;
        if (action == .takeover and !projection.canTakeover()) return;
        callback.perform(callback.context, action, target) catch {
            self.feedback.setTextContent(self.cx.allocator, "操作未完成，请核实原执行的最新状态。") catch {};
            self.feedback.setDisplay(.flex);
            return;
        };
        if (action != .view_terminal) self.controls_disabled.set(true);
        self.cx.requestRedraw();
    }
    fn viewTerminal(self: *State) void {
        self.perform(.view_terminal);
    }
    fn toggleDetails(self: *State) void {
        self.record.execution_details_expanded = !self.record.execution_details_expanded;
        self.collection.setDisplay(if (self.record.execution_details_expanded) .flex else .none);
        self.details_label.set(if (self.record.execution_details_expanded) "收起详情" else "详情");
        if (self.on_toggle) |callback| callback.invoke();
        self.cx.requestRedraw();
    }
    fn stop(self: *State) void {
        self.perform(.stop);
    }
    fn takeover(self: *State) void {
        self.perform(.takeover);
    }
    fn copyCommand(self: *State) void {
        const projection = self.store.executionProjection(self.record) orelse return;
        self.copy_command_feedback.copy(projection.command orelse return);
    }
    fn copyOutput(self: *State) void {
        const projection = self.store.executionProjection(self.record) orelse return;
        self.copy_output_feedback.copy(projection.terminal_output);
    }
    fn copyRecording(self: *State) void {
        const projection = self.store.executionProjection(self.record) orelse return;
        const id = projection.recording_id orelse return;
        const text = std.fmt.bytesToHex(id.bytes, .lower);
        self.copy_recording_feedback.copy(&text);
    }
};

/// The header's click, forwarded to the card state once it exists.
const Toggle = struct {
    state: ?*State = null,
    fn run(self: *Toggle) void {
        if (self.state) |state| state.toggle();
    }
};

pub fn mount(cx: *ui.Cx, scope: *ui.Scope, store: *facts.Store, record: *facts.Record, callbacks: ?Callbacks, on_toggle: ?ui.Handler(void)) !*ui.Node {
    const space = IdSpace.of(scope);
    const projection = store.executionProjection(record) orelse return error.NotExecutionResult;
    const positions = try @import("ai_card_scroll.zig").Offsets.mount(cx, scope, try record.scrollPositions(cx.allocator));
    record.execution_view_initialized = true;
    const root = try ui.boxStyled(cx, S.card, .{});
    const root_id = try scope.createState([@import("ai_tool_results_view.zig").facts_id_capacity]u8, undefined);
    root.meta.ownership.meta.test_id = try space.rebase(root_id, record.testId());
    // The card's state is made below; the header's click reaches it through this forwarder.
    const toggle = try scope.createState(Toggle, .{});
    const expanded = try scope.createSignal(bool, record.expanded);
    const observed_status = try std.fmt.allocPrint(cx.allocator, "{s}{s}", .{ if (projection.input_result) "输入结果 · " else "", projection.statusLabel() });
    defer cx.allocator.free(observed_status);
    // The row's accessible name is the observed status (owned by the scope: the a11y name borrows it).
    const status_name = try scope.createText(observed_status, .{});
    const header = try @import("ai_step_disclosure.zig").header(cx, scope, space.id("ai.execution.result.header"), status_name, expanded, cx.on(Toggle, toggle, Toggle.run));
    try root.appendChild(cx.allocator, header);
    const uncertain = projection.remote_effect_unknown or projection.state == .outcome_unknown or projection.call_status == .outcome_unknown or (projection.input_result and projection.input_receipt != null and projection.input_receipt.?.stage == .outcome_unknown) or (projection.state == null and projection.call_status == .succeeded and (!projection.input_result or projection.input_receipt == null));
    const finished = if (projection.input_result) projection.call_status == .succeeded and !uncertain and projection.input_receipt != null and (projection.input_receipt.?.stage == .consumed or projection.input_receipt.?.stage == .written) else !uncertain and projection.process != null and projection.process.?.foreground_finished and projection.process.?.exit_code == 0 and projection.process.?.signal == null;
    const process_failed = projection.process != null and (projection.process.?.signal != null or (projection.process.?.exit_code != null and projection.process.?.exit_code.? != 0));
    // Kaf7E A6: the row's status glyph (no chevron; the whole row opens the output well).
    const step_visual = @import("../model/ai_step_visual.zig");
    const row_visual: step_visual.Visual = if (process_failed) step_visual.step(.failed) else if (uncertain or projection.recording_failed or projection.outputWarning() != null) .{ .icon = "circle-alert", .tone = .warning } else if (finished) step_visual.step(.succeeded) else step_visual.step(.running);
    _ = try @import("ai_step_disclosure.zig").Indicator.mount(cx, scope, header, row_visual, space.id("ai.execution.result.icon"));
    const title = try ui.textStyled(cx, S.title, @import("../model/ai_tool_titles.zig").title(record.name) orelse "执行命令");
    title.meta.ownership.meta.test_id = space.id("ai.execution.result.title");
    title.setStyleInline(cx.allocator, @import("ai_tool_results_styles.zig").headerTitle(cx.tokens));
    try header.appendChild(cx.allocator, title);
    const summary = try ui.textStyled(cx, S.summary, observed_status);
    summary.meta.ownership.meta.test_id = space.id("ai.execution.result.summary");
    summary.setStyleInline(cx.allocator, @import("ai_tool_results_styles.zig").headerSummary(cx.tokens));
    try header.appendChild(cx.allocator, summary);
    var elapsed_buffer: [48]u8 = undefined;
    const elapsed = if (projection.elapsed_ms) |ms| @import("../../../../shared/base/format.zig").duration(&elapsed_buffer, ms, .short) else "—";
    const clock = try ui.textStyled(cx, @import("ai_tool_results_styles.zig").elapsed, elapsed);
    clock.meta.ownership.meta.test_id = space.id("ai.execution.result.elapsed");
    clock.setStyleInline(cx.allocator, @import("ai_tool_results_styles.zig").elapsedSlot(cx.tokens));
    clock.setDisplay(if (record.expanded) .flex else .none);
    try header.appendChild(cx.allocator, clock);
    // Bounded reading surfaces inside the conversation: their vertical input stays in them at
    // either edge, their thumb shows while they overflow.
    const scroll = try ui.widgets.ScrollArea(.{ .direction = .vertical, .overscroll_y = .contain, .scrollbars = .always, .scrollbar_gutter = .stable, .scroll_y = positions.scrollY(.body), .on_scroll_y_change = positions.onY(cx, .body) }).mount(scope, cx);
    scroll.container.setStyleInline(cx.allocator, S.body(cx.tokens));
    scroll.container.meta.ownership.meta.test_id = space.id("ai.execution.result.details");
    scroll.content.setStyleInline(cx.allocator, S.content(cx.tokens));
    const tool_detail = try @import("../model/ai_tool_titles.zig").detail(cx.allocator, record.name);
    defer cx.allocator.free(tool_detail);
    const tool = try ui.textStyled(cx, S.text, tool_detail);
    tool.meta.ownership.meta.test_id = space.id("ai.execution.result.tool");
    try scroll.content.appendChild(cx.allocator, tool);
    const body_disclosure = try @import("../../../../shared/ui/styles/layout_motion.zig").Disclosure.mount(cx, scope, scroll.container, record.expanded);
    try root.appendChild(cx.allocator, body_disclosure.root);
    const collection = try ui.widgets.ScrollArea(.{ .direction = .vertical, .overscroll_y = .contain, .scrollbars = .always, .scrollbar_gutter = .stable }).mount(scope, cx);
    collection.container.setStyleInline(cx.allocator, S.body(cx.tokens));
    collection.container.meta.ownership.meta.test_id = space.id("ai.execution.result.collection_details");
    collection.content.setStyleInline(cx.allocator, S.content(cx.tokens));
    collection.container.setDisplay(if (!projection.input_result and record.expanded and record.execution_details_expanded) .flex else .none);
    try root.appendChild(cx.allocator, collection.container);
    if (projection.input_result) {
        if (projection.input_receipt) |receipt| {
            const input_type = try ui.textStyled(cx, S.text, switch (receipt.kind) {
                .text => "输入类型 · 文本",
                .enter => "输入类型 · Enter",
                .host_secret => "输入类型 · 安全输入",
            });
            input_type.meta.ownership.meta.test_id = space.id("ai.execution.result.input_type");
            try scroll.content.appendChild(cx.allocator, input_type);
        }
        const input_limit = try ui.textStyled(cx, S.metadata, "此处仅确认本次输入的处理状态；命令执行结果请查看执行记录。");
        input_limit.meta.ownership.meta.test_id = space.id("ai.execution.result.input_limit");
        input_limit.setStyleInline(cx.allocator, .{ .width = .fill(), .min_width = 0, .flex_shrink = 0 });
        try scroll.content.appendChild(cx.allocator, input_limit);
    } else {
        const target = if (projection.target) |owner| try std.fmt.allocPrint(cx.allocator, "目标 · {s}{s}会话 #{d}", .{ projection.target_label, if (projection.target_label.len == 0) "" else " · ", @backingInt(owner.session_id) }) else try cx.allocator.dupe(u8, "目标身份未返回");
        defer cx.allocator.free(target);
        const target_node = try ui.textStyled(cx, S.text, target);
        target_node.meta.ownership.meta.test_id = space.id("ai.execution.result.target");
        target_node.setStyleInline(cx.allocator, .{ .width = .fill(), .min_width = 0, .flex_shrink = 0 });
        try scroll.content.appendChild(cx.allocator, target_node);
    }
    if (projection.failure) |code| {
        const recording_only = projection.recording_failed and projection.process != null and projection.process.?.foreground_finished;
        const label = if (recording_only) try std.fmt.allocPrint(cx.allocator, "记录保存异常 · {s}", .{code}) else null;
        defer if (label) |bytes| cx.allocator.free(bytes);
        const reason = try ui.textStyled(cx, S.text, label orelse failureLabel(code));
        reason.meta.ownership.meta.test_id = space.id("ai.execution.result.failure");
        reason.setStyleInline(cx.allocator, .{ .width = .fill(), .min_width = 0, .flex_shrink = 0 });
        try (if (recording_only) collection.content else scroll.content).appendChild(cx.allocator, reason);
    }
    if (projection.stop_requested or projection.input_handed_off or projection.recording_failed) {
        const effect = try ui.textStyled(cx, S.text, if (projection.recording_failed) "终端记录保存失败，可查看原终端。" else if (projection.input_handed_off) "输入权已交给用户；当前命令与输出观察可继续。" else if (projection.process != null and projection.process.?.foreground_finished) "已请求停止，前台命令已结束。" else "已请求停止；尚未确认前台结束或输入权释放。");
        effect.meta.ownership.meta.test_id = space.id("ai.execution.result.effect");
        effect.setStyleInline(cx.allocator, .{ .width = .fill(), .min_width = 0, .flex_shrink = 0 });
        try scroll.content.appendChild(cx.allocator, effect);
    }
    if (projection.process) |process| {
        var process_buffer: [128]u8 = undefined;
        const process_text = if (process.signal) |signal| try std.fmt.bufPrint(&process_buffer, "结束信号 {d}", .{signal}) else if (process.exit_code) |code| try std.fmt.bufPrint(&process_buffer, "退出码 {d}", .{code}) else if (process.foreground_finished) "命令已结束 · 未提供退出码" else "尚未确认命令结束";
        const process_node = try ui.textStyled(cx, S.metadata, process_text);
        process_node.meta.ownership.meta.test_id = space.id("ai.execution.result.process");
        try scroll.content.appendChild(cx.allocator, process_node);
    }
    if (projection.outputWarning()) |warning| {
        const note = try ui.textStyled(cx, S.warning, warning);
        note.meta.ownership.meta.test_id = space.id("ai.execution.result.uncertainty");
        note.setStyleInline(cx.allocator, .{ .width = .fill(), .min_width = 0, .flex_shrink = 0 });
        try scroll.content.appendChild(cx.allocator, note);
    }
    if (projection.output_scope == .session_interval) {
        const range = try ui.textStyled(cx, S.metadata, if (projection.intervalRecorded()) "本次终端输出 · 已保存" else if (projection.recording_failed) "本次终端输出 · 保存失败" else "本次终端输出 · 保存待确认");
        range.meta.ownership.meta.test_id = space.id("ai.execution.result.output_scope");
        range.setStyleInline(cx.allocator, .{ .width = .fill(), .min_width = 0, .flex_shrink = 0 });
        try collection.content.appendChild(cx.allocator, range);
        const attribution = try ui.textStyled(cx, S.metadata, projection.attributionLabel());
        attribution.meta.ownership.meta.test_id = space.id("ai.execution.result.output_attribution");
        attribution.setStyleInline(cx.allocator, .{ .width = .fill(), .min_width = 0, .flex_shrink = 0 });
        try collection.content.appendChild(cx.allocator, attribution);
        if (projection.output_attribution_reason) |code| {
            const reason = try ui.textStyled(cx, S.metadata, attributionReason(code));
            reason.meta.ownership.meta.test_id = space.id("ai.execution.result.output_attribution_reason");
            reason.setStyleInline(cx.allocator, .{ .width = .fill(), .min_width = 0, .flex_shrink = 0 });
            try collection.content.appendChild(cx.allocator, reason);
        }
        const limit = try ui.textStyled(cx, S.metadata, "仅保存本次采集期间的终端输出，可能包含其他程序的内容；后台任务可能继续输出。");
        limit.meta.ownership.meta.test_id = space.id("ai.execution.result.output_limit");
        limit.setStyleInline(cx.allocator, .{ .width = .fill(), .min_width = 0, .flex_shrink = 0 });
        try collection.content.appendChild(cx.allocator, limit);
    }
    if (!projection.input_result) {
        const source = try ui.textStyled(cx, S.metadata, switch (projection.completion_source) {
            .shell_reported => "结束状态来源 · Shell",
            .unknown => "结束状态来源 · 未确认",
            .private_protocol => "结束状态来源 · 执行服务",
        });
        source.meta.ownership.meta.test_id = space.id("ai.execution.result.completion_source");
        try collection.content.appendChild(cx.allocator, source);
    }
    var command_row: ?*ui.Node = null;
    if (projection.command) |command| {
        const row = try ui.box(cx, .{ .width = .fill(), .height = .{ .fit = .{} }, .direction = .row, .align_items = .center, .gap = 6, .min_width = 0, .flex_shrink = 0 }, .{});
        command_row = row;
        try scroll.content.appendChild(cx.allocator, row);
        const viewport = try appendOutput(cx, scope, row, command, .command, positions);
        viewport.setStyleInline(cx.allocator, .{ .flex = 1, .min_width = 0 });
    }
    if (projection.execution_id) |id| {
        const identity_text = try std.fmt.allocPrint(cx.allocator, "执行 · x1:{s}", .{std.fmt.bytesToHex(id.bytes, .lower)});
        defer cx.allocator.free(identity_text);
        const identity_node = try ui.textStyled(cx, S.identity, identity_text);
        identity_node.meta.ownership.meta.test_id = space.id("ai.execution.result.execution_id");
        identity_node.setStyleInline(cx.allocator, .{ .width = .fill(), .min_width = 0, .flex_shrink = 0 });
        try (if (projection.input_result) scroll.content else collection.content).appendChild(cx.allocator, identity_node);
    }
    if (!projection.input_result) {
        const output_label = try ui.textStyled(cx, S.metadata, if (projection.terminal_output.len != 0) "终端输出" else if (projection.output_available) "终端暂无输出" else "暂未取得终端输出");
        output_label.meta.ownership.meta.test_id = space.id("ai.execution.result.output_label");
        try scroll.content.appendChild(cx.allocator, output_label);
    }
    if (projection.terminal_output.len != 0) _ = try appendOutput(cx, scope, scroll.content, projection.terminal_output, .stdout, positions);
    if (projection.output_gap or projection.output_truncated) {
        const note = try ui.textStyled(cx, S.metadata, if (projection.output_gap) "部分输出不在本次返回范围内；可查看原终端记录。" else if (projection.output_scope == .session_interval) "本次返回的观测片段已截断；可查看原终端记录。" else "本次输出已截断；完整内容请查看原终端记录。");
        note.meta.ownership.meta.test_id = space.id("ai.execution.result.output_notice");
        note.setStyleInline(cx.allocator, .{ .width = .fill(), .min_width = 0, .flex_shrink = 0 });
        try scroll.content.appendChild(cx.allocator, note);
    }
    const footer = try ui.boxStyled(cx, S.footer, .{});
    footer.meta.ownership.meta.test_id = space.id("ai.execution.result.footer");
    const footer_disclosure = try @import("../../../../shared/ui/styles/layout_motion.zig").Disclosure.mount(cx, scope, footer, record.expanded);
    try root.appendChild(cx.allocator, footer_disclosure.root);
    const feedback = try ui.textStyled(cx, S.text, "");
    feedback.meta.ownership.meta.test_id = space.id("ai.execution.result.action_feedback");
    feedback.setStyleInline(cx.allocator, .{ .width = .fill(), .min_width = 0, .flex_shrink = 0 });
    feedback.setDisplay(.none);
    try footer.appendChild(cx.allocator, feedback);
    const state = try scope.createState(State, .{ .cx = cx, .store = store, .record = record, .callbacks = callbacks, .on_toggle = on_toggle, .body = body_disclosure, .footer = footer_disclosure, .feedback = feedback, .controls_disabled = try scope.createSignal(bool, callbacks == null), .expected = projection.actionTarget(), .expanded = expanded, .collection = collection.container, .clock = clock, .details_label = try scope.createSignal([]const u8, if (record.execution_details_expanded) "收起详情" else "详情") });
    toggle.state = state;
    if (command_row) |row| {
        state.copy_command_feedback = try @import("../../../../shared/ui/components/copy_button/copy_button.zig").Button.mount(cx, scope, .{ .variant = .ghost, .icon_only = true, .icon_asset = ui.icons.copy, .icon_size = @as(f32, 14), .a11y_label = "复制实际命令", .base_style = S.iconButton(), .on_click = cx.on(State, state, State.copyCommand) });
        const copy = state.copy_command_feedback.node;
        copy.meta.ownership.meta.test_id = space.id("ai.execution.result.copy_command");
        try row.appendChild(cx.allocator, copy);
    }
    if (projection.recording_id) |id| {
        const row = try ui.box(cx, .{ .width = .fill(), .height = .{ .fit = .{} }, .direction = .row, .align_items = .center, .gap = 6, .flex_shrink = 0 }, .{});
        const recording = try std.fmt.allocPrint(cx.allocator, "记录 · {s}", .{std.fmt.bytesToHex(id.bytes, .lower)});
        defer cx.allocator.free(recording);
        const text = try ui.textStyled(cx, S.identity, recording);
        text.meta.ownership.meta.test_id = space.id("ai.execution.result.recording_id");
        text.setStyleInline(cx.allocator, .{ .width = .fill(), .min_width = 0, .flex = 1, .flex_shrink = 0 });
        try row.appendChild(cx.allocator, text);
        state.copy_recording_feedback = try @import("../../../../shared/ui/components/copy_button/copy_button.zig").Button.mount(cx, scope, .{ .variant = .ghost, .icon_only = true, .icon_asset = ui.icons.copy, .icon_size = @as(f32, 14), .a11y_label = "复制真实记录 ID", .base_style = S.iconButton(), .on_click = cx.on(State, state, State.copyRecording) });
        const copy = state.copy_recording_feedback.node;
        copy.meta.ownership.meta.test_id = space.id("ai.execution.result.copy_recording");
        try row.appendChild(cx.allocator, copy);
        try collection.content.appendChild(cx.allocator, row);
    }
    if (projection.actionTarget() != null) {
        const view = try ui.widgets.Button(.{ .variant = .ghost, .icon_only = true, .icon_asset = ui.icons.get("terminal").?, .icon_size = 14, .a11y_label = "查看终端", .base_style = S.iconButton(), .disabled = callbacks == null, .on_click = cx.on(State, state, State.viewTerminal) }).mount(scope, cx);
        view.meta.ownership.meta.test_id = space.id("ai.execution.result.view_terminal");
        const view_hint = try @import("../../../../shared/ui/components/control_hint/control_hint.zig").mount(cx, scope, view, "查看原执行终端", .{ .id = space.id("ai.execution.result.view_terminal.tooltip") });
        try footer.appendChild(cx.allocator, view_hint.wrapper);
        if (projection.canStop()) {
            const stop = try ui.widgets.Button(.{ .variant = .secondary, .label = "停止执行", .base_style = try @import("../../../../shared/ui/theme/app_theme.zig").paintSignal(S.ButtonStyle, cx, scope, S.action, .{}), .disabled = state.controls_disabled, .on_click = cx.on(State, state, State.stop) }).mount(scope, cx);
            stop.meta.ownership.meta.test_id = space.id("ai.execution.result.stop");
            try footer.appendChild(cx.allocator, stop);
        }
        if (projection.canTakeover()) {
            const takeover = try ui.widgets.Button(.{ .variant = .secondary, .label = "接管输入", .base_style = try @import("../../../../shared/ui/theme/app_theme.zig").paintSignal(S.ButtonStyle, cx, scope, S.action, .{}), .disabled = state.controls_disabled, .on_click = cx.on(State, state, State.takeover) }).mount(scope, cx);
            takeover.meta.ownership.meta.test_id = space.id("ai.execution.result.takeover");
            try footer.appendChild(cx.allocator, takeover);
        }
    }
    if (projection.terminal_output.len != 0) {
        state.copy_output_feedback = try @import("../../../../shared/ui/components/copy_button/copy_button.zig").Button.mount(cx, scope, .{ .variant = .ghost, .icon_only = true, .icon_asset = ui.icons.copy, .icon_size = @as(f32, 14), .a11y_label = if (projection.output_scope == .session_interval) "复制本次观测片段" else "复制本次终端输出", .base_style = S.iconButton(), .on_click = cx.on(State, state, State.copyOutput) });
        const copy = state.copy_output_feedback.node;
        copy.meta.ownership.meta.test_id = space.id("ai.execution.result.copy_output");
        try footer.appendChild(cx.allocator, copy);
    }
    if (!projection.input_result) {
        const details = try ui.widgets.Button(.{ .variant = .ghost, .icon_only = true, .icon_asset = ui.map(state.details_label, struct {
            fn asset(label: []const u8) ?ui.SvgAsset {
                return if (std.mem.eql(u8, label, "收起详情")) ui.icons.chevron_up else ui.icons.chevron_down;
            }
        }.asset), .icon_size = 14, .a11y_label = state.details_label, .base_style = S.iconButton(), .on_click = cx.on(State, state, State.toggleDetails) }).mount(scope, cx);
        details.meta.ownership.meta.test_id = space.id("ai.execution.result.details_toggle");
        const details_hint = try @import("../../../../shared/ui/components/control_hint/control_hint.zig").mount(cx, scope, details, state.details_label, .{ .id = space.id("ai.execution.result.details_toggle.tooltip") });
        try footer.appendChild(cx.allocator, details_hint.wrapper);
    } else if (projection.actionTarget() == null and projection.terminal_output.len == 0) footer.setDisplay(.none);
    try @import("../../pane/view/ai_text_selection.zig").attach(cx, scope, scroll.content);
    try @import("../../pane/view/ai_text_selection.zig").attach(cx, scope, collection.content);
    return root;
}
/// An output well (the command, the terminal output): a native W.CodeBlock (borderless, no header,
/// long lines scroll sideways) whose body offsets are restored from the record's positions on mount
/// and saved back as they settle (the reading position survives a card rebuild). `slot` says which
/// well this is (`.command` or `.stdout`, the terminal output); its ids follow from it.
fn appendOutput(cx: *ui.Cx, scope: *ui.Scope, parent: *ui.Node, bytes: []const u8, slot: @import("ai_card_scroll.zig").Slot, positions: *@import("ai_card_scroll.zig").Offsets) !*ui.Node {
    const space = IdSpace.of(scope);
    const id: []const u8 = if (slot == .command) space.id("ai.execution.result.command") else space.id("ai.execution.result.terminal_output");
    const body_id: []const u8 = if (slot == .command) space.id("ai.execution.result.command_scroll") else space.id("ai.execution.result.terminal_output_scroll");
    const block = try ui.widgets.CodeBlock(.{
        .code = bytes,
        .options = @import("ai_tool_results_styles.zig").wellOptions(space),
        .test_ids = .{ .wrap = null, .copy = null, .body = body_id, .text = id },
        .scroll_x = positions.scrollX(slot),
        .scroll_y = positions.scrollY(slot),
        .on_scroll_x_change = positions.onX(cx, slot),
        .on_scroll_y_change = positions.onY(cx, slot),
    }).mount(scope, cx);
    block.setStyleInline(cx.allocator, .{ .width = .fill(), .min_width = 0, .flex_shrink = 0 });
    try parent.appendChild(cx.allocator, block);
    return block;
}

fn failureLabel(code: []const u8) []const u8 {
    if (std.mem.eql(u8, code, "IntegrationUnavailable")) return "当前终端的执行能力不可用。";
    if (std.mem.eql(u8, code, "HostToolGatewayUnavailable")) return "执行服务当前不可用。";
    if (std.mem.eql(u8, code, "ToolApprovalRejected")) return "本次调用未获批准。";
    if (std.mem.eql(u8, code, "CancelledBeforeDispatch")) return "派发前已取消，命令未执行。";
    if (std.mem.eql(u8, code, "PermissionDenied") or std.mem.eql(u8, code, "ToolExecutionDenied")) return "当前执行权限不足。";
    if (std.mem.eql(u8, code, "TargetUnavailable") or std.mem.eql(u8, code, "StaleSession") or std.mem.eql(u8, code, "StaleReference")) return "原目标会话已不可用。";
    if (std.mem.eql(u8, code, "TerminalBusy")) return "目标终端正忙。";
    if (std.mem.eql(u8, code, "ExecutionSuperseded")) return "终端已开始其他执行，请核实原命令结果。";
    if (std.mem.eql(u8, code, "InvalidHostToolResult")) return "执行信息未通过校验，结果仍需核实。";
    if (std.mem.eql(u8, code, "UnsupportedInteraction")) return "当前前台交互不受支持，可在原终端查看并接管。";
    return "本次调用未能完成，请核实原终端状态。";
}

fn attributionReason(code: []const u8) []const u8 {
    if (std.mem.eql(u8, code, "BackgroundJobsObserved")) return "检测到后台任务。";
    if (std.mem.eql(u8, code, "OutputProcessIdentityUnknown")) return "无法确认同一终端中的其他进程身份。";
    if (std.mem.eql(u8, code, "OutputDescriptorsUnknown") or std.mem.eql(u8, code, "OutputDescriptorIdentityUnknown")) return "无法完整观察其他输出来源。";
    if (std.mem.eql(u8, code, "OutputObservationDeadline")) return "并发观察未在时限内完成。";
    if (std.mem.eql(u8, code, "BackgroundJobsUnknown")) return "无法完整确认后台任务。";
    return "无法确认输出来源。";
}
